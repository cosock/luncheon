local Headers = require 'luncheon.headers'
local statuses = require 'luncheon.status'
local utils = require 'luncheon.utils'

---@class Response
---@field public headers Headers The HTTP headers for this response
---@field public body string the contents of the response body
---@field public status number The HTTP status 3 digit number
---@field public http_version string
---@field private _source fun(pat:string|nil):string ltn12 source
---@field private _parsed_headers boolean
---@field private _received_body boolean
local Response = {}
Response.__index = Response

--#endregion
--#region Parser


---Create a request parser from an ltn12 source function
---@param source fun():string
---@return Response
---@return string @if return 1 is nil the error string
function Response.source(source)
    local ret = setmetatable({
        headers = Headers.new(),
        _source = source,
        _parsed_headers = false,
    }, Response)
    local line, err = ret:next_line()
    if not line then
        return nil, err
    end
    local pre, err = Response._parse_preamble(line)
    if not pre then
        return nil, err
    end
    ret.status = pre.status
    ret.status_msg = pre.status_msg
    ret.http_version = pre.http_version
    return ret
end

---Parse the first line of an incoming response
---@param line string
---@return nil|table @`{http_version: number, status: number, status_msg: string}`
---@return nil|string @Error message if populated
function Response._parse_preamble(line)
    local version, status, msg = string.match(line, 'HTTP/([0-9.]+) ([^%s]+) ([^%s]+)')
    if not version then
        return nil, string.format('invalid preamble: %q', line)
    end
    return {
        http_version = tonumber(version),
        status = math.tointeger(status),
        status_msg = msg,
    }
end

---Fill this incoming request's headers
---@return nil|string @if not `nil` an error message
function Response:_fill_headers()
    while true do
        local done, err = self:_parse_header()
        if err ~= nil then
            return err
        end
        if done then
            self._parsed_headers = true
            return
        end
    end
end

function Response:get_headers()
    if not self._parsed_headers then
        local err = self:_fill_headers()
        if err ~= nil then
            return nil, err
        end
    end
    return self.headers
end

---Read a single line from the socket and parse it as an http header, appending to self.headers
---returns true when the end of the http headers
---@return boolean|nil @true when end of headers have been reached, nil when error
---@return string|nil @when not nil the error message
function Response:_parse_header()
    local line, err = self:_next_line()
    if err ~= nil then
        return nil, err
    end
    if line == '' then
        return true
    else
        self.headers:append_chunk(line)
    end
    return false
end

---Attempt to get the value from Content-Length header
---@return number|nil @when not `nil` the Content-Length
---@return string|nil @when not `nil` the error message
function Response:get_content_length()
    if not self._parsed_headers then
        self:_fill_headers() 
    end
    if not self._content_length then
        if not self.headers.content_length then
            return
        end 
        local n = math.tointeger(self.headers.content_length)
        if not n then
            return nil, 'bad Content-Length header'
        end
        self._content_length = n
    end
    return self._content_length
end

---Get the next line from an incoming request, checking first
---if we have reached the end of the content
---@return string|nil
---@return string|nil
function Response:next_line()
    if not self._source then
        return nil, 'nil source'
    end
    return self:_next_line()
end

---Read from the socket, filling the body property
---of this request
---@return string|nil
function Response:_fill_body()
    local len, err = self:get_content_length()
    if err ~= nil then
        return err
    end
    len = len or 'a*'
    local body, err = self._source(len)
    if not body then
        return err
    end
    self.body = body
    self._received_body = true
end

function Response:get_body()
    if not self._received_body then
        local err = self:_fill_body()
        if err ~= nil then
            return nil, err
        end
    end
    return self.body
end

---Receive the next line from an incoming request w/o checking
---the content-length header
---@return string|nil
---@return string|nil
function Response:_next_line()
    local line, err = self._source()
    self._recvd = (self._recvd or 0) + #(line or '')
    return line, err
end

--#region builder

function Response.new(status_code)
    return setmetatable(
        {
            status = status_code or 200,
            status_msg = statuses[status_code] or 'Unknown',
            http_version = 1.1,
            headers = Headers.new(),
            body = '',
            _parsed_headers = true,
        },
        Response
    )
end

function Response:add_header(key, value)
    if type(value) ~= 'string' then
        value = tostring(value)
    end
    self.headers:append(key, value)
    return self
end

---Set the Content-Type of the outbound request
---@param s string the mime type for this request
---@return Response
function Response:set_content_type(s)
    if type(s) ~= 'string' then
        return nil, string.format('mime type must be a string, found %s', type(s))
    end
    return self:add_header('content_type', s)
end

---Set the Content-Length header of the outbound response
---@param len number The length of the content that will be sent
---@return Response
function Response:set_content_length(len)
    if type(len) ~= 'number' then
        return nil, string.format('content length must be a number, found %s', type(len))
    end
    return self:add_header('content_length', string.format('%i', len))
end

---Serialize this full response into a string
---@return string
function Response:serialize()
    self:set_content_length(#self.body)
    return self:_generate_prebody()
        .. (self.body or '')
end

---Generate the first line of this response without the trailing \r\n
---@return string
function Response:_generate_preamble()
    return string.format('HTTP/%s %s %s',
        self.http_version,
        self.status,
        statuses[self.status] or ''
    )
end

---Create the string representing the pre-body entries for
---this request. including the 2 trailing \r\n
---@return string
function Response:_generate_prebody()
    return self:_generate_preamble() .. '\r\n'
        .. self.headers:serialize() .. '\r\n'
end

---Append text to the body
---@param s string the text to append
---@return Response
function Response:append_body(s)
    self.body = (self.body or '') .. s
    self:set_content_length(#self.body)
    return self
end

---Set the status for this outgoing request
---@param n number the 3 digit status
---@return Response
function Response:set_status(n)
    if type(n) == 'string' then
        n = math.tointeger(n)
    end
    if type(n) ~= 'number' then
        return nil, string.format('http status must be a number, found %s', type(n))
    end
    self.status = n
    return self
end

---Creates an LTN12 source for this request
---@return function
function Response:as_source()
    local state = 'start'
    local last_header, value
    local suffix = '\r\n'
    local body = self.body
    return function()
        if state == 'start' then
            state = 'headers'
            return self:_generate_preamble() .. suffix
        end
        if state == 'headers' then
            last_header, value = next(self.headers, last_header)
            if last_header == 'last_key' then
                last_header, value = next(self.headers, last_header)
            end
            if not last_header then
                state = 'body'
                return suffix
            end
            return Headers.serialize_header(last_header, value) .. suffix
        end
        if state == 'body' then
            value, body = utils.next_line(body, true)
            if not value then
                state = nil
                return body
            end
            return value
        end
    end
end

--#endregion

return Response
