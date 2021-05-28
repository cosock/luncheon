local net_url = require 'net.url'
local Headers = require 'luncheon.headers'

---@class Request
---@field public method string the HTTP method for this request
---@field public url table The parse url of this request
---@field public http_version string The http version from the request preamble
---@field public headers Headers The HTTP headers for this request
---@field public body string The contents of the request
---@field private err string|nil The _last_ error from the handler or middleware
---@field public handled boolean|nil `true` when the request has been handled
---@field public socket table Luasocket api conforming socket
local Request = {}

Request.__index = Request

---Parse the first line of an HTTP request
---@param line string
---@return table
function Request._parse_preamble(line)
    local start, _, method, path, http_version = string.find(line, '([A-Z]+) (.+) HTTP/([0-9.]+)')
    if not start then
        return nil, string.format('Invalid http request first line: "%s"', line)
    end
    return {
        method = method,
        url = net_url.parse(path),
        http_version = http_version,
        _body = nil,
        _headers = nil,
    }
end

---Get the headers for this request
---parsing the incoming stream of headers
---if not already parsed
---@return Headers, string|nil
function Request:get_headers()
    if self.parsed_headers == false then
        local err = self:_fill_headers()
        if err ~= nil then
            return nil, err
        end
    end
    return self._headers
end

---read from the socket filling in the headers property
function Request:_fill_headers()
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

---Read a single line from the socket and parse it as an http header
---returning true when the end of the http headers
---@return boolean|nil, string|nil
function Request:_parse_header()
    local line, err = self:_next_line()
    if err ~= nil then
        return nil, err
    end
    if self._headers == nil then
        self._headers = Headers.new()
    end
    if line == '' then
        return true
    else
        self._headers:append_chunk(line)
    end
    return false
end
---Read a single line from the socket
---@return string|nil, string|nil
function Request:_next_line()
    local line, err = self.socket:receive('*l')
    return line, err
end

---Get the contents of this request's body
---if not yet received, this will read the body
---from the socket
---@return string|nil, string|nil
function Request:get_body()
    if not self._received_body then
        local err = self:_fill_body()
        if err ~= nil then
            return nil, err
        end
    end
    return self._body
end

---Read from the socket, filling the body property
---of this request
---@return string|nil
function Request:_fill_body()
    local len, err = self:content_length()
    if len == nil then
        return err
    end
    self._body = self.socket:receive(len)
    self._received_body = true
end

---Get the value from the Content-Length header that should be present
---for all http requests
---@return number|nil, string|nil
function Request:content_length()
    local headers, err = self:get_headers()
    if err then
        return nil, err
    end
    if headers.content_length == nil then
        return 0
    end
    return math.tointeger(headers.content_length) or 0
end

---Construct a new Request
---@param socket table The tcp client socket for this request
---@return Request|nil, string|nil
function Request.from_socket(socket)
    if not socket then
        return nil, 'cannot create request with nil socket'
    end
    local r = {
        socket = socket,
        parsed_headers = false,
    }
    setmetatable(r, Request)
    local line, acc_err = r:_next_line()
    if acc_err then
        return nil, acc_err
    end
    local pre, pre_err = Request._parse_preamble(line)
    if pre_err then
        return nil, pre_err
    end
    r.http_version = pre.http_version
    r.method = pre.method
    r.url = pre.url
    return r
end

-- Builder Pattern

---Create a new outbound request
---@param method string
---@param url string|table
---@return Request
function Request.new(method, url)
    if type(url) == 'string' then
        url = net_url.parse(url)
    end
    return setmetatable({
        method = string.upper(method or 'GET'),
        url = url or '/',
        headers = Headers.new(),
        http_version = '1.1',
    }, Request)
end

---Add a header to the internal map of headers
---@param key string
---@param value string
---@return Request
function Request:add_header(key, value)
    self.headers:append(key, value)
    return self
end

---Set the Content-Type header for this request
---convenience wrapper around self:add_header('content_type', len)
function Request:set_content_type(ct)
    self:add_header('content_type', ct)
    return self
end

---Set the Content-Length header for this request
---convenience wrapper around self:add_header('content_length', len)
---@param len number
---@return Request
function Request:set_content_length(len)
    self:add_header('content_length', len)
    return self
end

---Set the body for this outbound request
---The provided body argument can be a string or an iterator/ltn12 source function
---
---If `body` is a string, the `Content-Length` header will be set automatically to `#body`
---If `body` is not a string, the optional `len` property can be used to set the `Content-Length` header
---@param body string|fun():fun(err:string|nil,last:string|nil):string
---@param len number|nil The content length of the ltn12 source function
---@return Request
function Request:set_body(body, len)
    if type(body) == 'string' then
        self:set_content_length(#body)
    elseif len then
        self:set_content_length(len)
    end
    self._body = body
    return self
end

---Private method for serializing the url property into a valid URL string suitable
---for the first line of an HTTP request
---@return string
function Request:_serialize_path()
    if type(self.url) == 'string' then
        self.url = net_url.parse(self.url)
    end
    local path = self.url.path or '/'
    if not self.url.query or not next(self.url.query) then
        return path
    end
    return path .. '?' .. net_url.buildQuery(self.url.query)
end

---Serialize this request into a single string for sending
---@return string
function Request:serialize()
    local ret = ''
    for part in self:source() do
        ret = ret .. part
    end
    return ret
end

---Serialize this request as an ltn12 source function
---Each pre-body line will be sent as a chunk followed by
---either the full body if it is a string or this will delegate
---the iteration to the body ltn12 source body
---@return function
function Request:source()
    local state = 'start'
    local last_header, value
    local body_iter
    return function ()
        if state == 'start' then
            state = 'headers'
            return string.format(
                '%s %s HTTP/1.1\r\n',
                string.upper(self.method),
                self:_serialize_path()
            )
        end
        if state == 'headers' then
            last_header, value = next(self.headers, last_header)
            if last_header == 'last_key' then
                last_header, value = next(self.headers, last_header)
            end
            if last_header then
                return Headers.serialize_header(last_header, value) .. '\r\n'
            end
            state = 'body'
            return '\r\n'
        end
        if state == 'body' then
            if type(self._body) == 'function' then
                if not body_iter then
                    body_iter = self._body()
                end
                return body_iter()
            elseif type(self._body) == 'string' then
                state = nil
                return self._body
            end
        end
    end
end

return Request
