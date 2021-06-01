local Headers = require 'luncheon.headers'
local statuses = require 'luncheon.status'
local utils = require 'luncheon.utils'

---@alias Source fun():fun():string

---@class Response
---@field public headers Headers The HTTP headers for this response
---@field public body string|Source the contents of the response body
---@field private _incoming table|nil LuaSocket api conforming table
---@field private _outgoing table|nil LuaSocket api conforming table
---@field public http_version string
local Response = {}
Response.__index = Response

---create a response for to a corresponding request
---@param socket table anything that can call `:send()`
---@param send_buffer_size number|nil If provided, sending will happen in a buffered fashion
---@return Response
function Response.outgoing(socket, send_buffer_size)
    local base = {
        headers = Headers.new(),
        _status = 200,
        body = '',
        http_version = '1.1',
        _outgoing = socket,
        _send_buffer_size = send_buffer_size,
        chunks_sent = 0,
    }
    setmetatable(base, Response)
    return base
end

function Response.incoming(socket)
    local ret = setmetatable({
        headers = Headers.new(),
        _incoming = socket,
    }, Response)
    local line, err = ret:next_line()
    if not line then
        return nil, err
    end
    local pre, err = Response._parse_preamble(line)
    if not pre then
        return nil, err
    end
    ret._status = pre.status
    ret._status_msg = pre.status_msg
    ret.http_version = pre.http_version
    ret:_fill_headers()
    ret.body = function () return ret:_body_source() end
    return ret
end

---Generate a LTN12 of just the body portion of this response
---Only usable on incoming responses
---@return Source
function Response:_body_source()
    local recvd = 0
    local target = self:get_content_length()
    return function ()
        if not target or target > recvd then
            local line, err = self:_next_line()
            if line then
                recvd = recvd + #line
            end
            return line, err
        end
    end
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
            self.parsed_headers = true
            return
        end
    end
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

---If this response should attempt to receive more data
---@return boolean
function Response:_should_recv()
    if not self.headers.content_length then
        return true
    end
    self.headers.content_length = math.tointeger(self.headers.content_length)
    return (self._recvd or 0) < self.headers.content_length
end

---Attempt to get the value from Content-Length header
---@return number|nil @when not `nil` the Content-Length
---@return string|nil @when not `nil` the error message
function Response:get_content_length()
    local ty = type(self.headers.content_length)
    if ty == 'number' then
        return self.headers.content_length
    end
    if ty == 'string' then
        local n = math.tointeger(self.headers.content_length)
        if not n then
            return nil, 'bad Content-Length header'
        end
        self.headers.content_length = n
        return n
    end
    return nil, 'no content length header'
end

---Get the next line from an incoming request, checking first
---if we have reached the end of the content
---@return string|nil
---@return string|nil
function Response:next_line()
    if not self._incoming then
        return nil, 'Outgoing request cannot receive'
    end
    if not self:_should_recv() then
        return nil, nil
    end
    return self:_next_line()
end

---Receive the next line from an incoming request w/o checking
---the content-length header
---@return string|nil
---@return string|nil
function Response:_next_line()
    local line, err = self._incoming:receive('*l')
    self._recvd = (self._recvd or 0) + #(line or '')
    return line, err
end

---Set the status for this outgoing request
---@param n number the 3 digit status
---@return Response
function Response:status(n)
    if type(n) == 'string' then
        n = math.tointeger(n)
    end
    if type(n) ~= 'number' then
        return nil, string.format('http status must be a number, found %s', type(n))
    end
    self._status = n
    return self
end

---Set the Content-Type of the outbound request
---@param s string the mime type for this request
---@return Response
function Response:content_type(s)
    if type(s) ~= 'string' then
        return nil, string.format('mime type must be a string, found %s', type(s))
    end
    self.headers.content_type = s
    return self
end

---Set the Content-Length header of the outbound response
---@param len number The length of the content that will be sent
---@return Response
function Response:content_length(len)
    if type(len) ~= 'number' then
        return nil, string.format('content length must be a number, found %s', type(len))
    end
    self.headers.content_length = string.format('%i', len)
    return self
end

---Set the send buffer size to enable buffered writes
---if unset, the full response body is buffered before sending
---@param size number|nil
function Response:set_send_buffer_size(size)
    self._send_buffer_size = size
end

---Serialize this full response into a string
---@return string
function Response:_serialize()
    self:content_length(#self.body)
    return self:_generate_prebody()
        .. (self.body or '')
end

---Generate the first line of this response without the trailing \r\n
---@return string
function Response:_generate_preamble()
    return string.format('HTTP/%s %s %s',
        self.http_version,
        self._status,
        statuses[self._status] or ''
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
    if type(s) == 'string' then
        self.body = (self.body or '') .. s
    end
    if self:_should_send() then
        local success, err = self:_send_chunk()
        if not success then
            return nil, err
        end
    end
    return self
end

---Check if we are sending in buffered mode
---and if we should send the current buffer
---@return number|nil
function Response:_should_send()
    return self._send_buffer_size and
        #self.body >= self._send_buffer_size
end

---Send a chunk when sending in buffered mode
---this will truncate self.body to an empty string
function Response:_send_chunk()
    local to_send = self.body
    if not self:has_sent() then
        to_send = self:_generate_prebody()..to_send
    end
    local num_sent, err = utils.send_all(self._outgoing, to_send)
    self.body = ''
    if num_sent == nil then
        return nil, err
    end
    return 1
end

---complete this http request by sending this response as text
---@param s string|nil
function Response:send(s)
    if type(s) == 'string' then
        self:append_body(s)
    end
    if self.headers.content_type == nil then
        self:content_type('text/plain')
    end
    if self._send_buffer_size == nil
    or not self:has_sent() then
        return utils.send_all(self._outgoing, self:_serialize())
    end
    return utils.send_all(self._outgoing, self.body)
end

---Creates an LTN12 source for this request
---@return function
function Response:source()
    local state = 'start'
    local last_header, value, body_iter
    local suffix = '\r\n'
    if self._incoming then
        suffix = ''
    else
    end
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
            if type(self.body) == 'string' then
                state = nil
                return self.body
            elseif type(self.body == 'function') then
                if not body_iter then
                    body_iter = self.body()
                end
                return body_iter()
            end
        end
    end
end


---Check if this response has sent any bytes
function Response:has_sent()
    if self._has_sent then
        return self._has_sent
    end
    local _, s = self._outgoing:getstats()
    self._has_sent = s > 0
    return self._has_sent
end

function Response:close()
    return self._outgoing:close()
end

return Response
