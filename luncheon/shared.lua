local Headers = require "luncheon.headers"
local utils = require "luncheon.utils"

---@enum Mode
--- Enumeration of the 2 sources of data
local Mode = {
    --- This is a Request or Response constructed via `source` it will rely on pulling
    --- new bytes from the `_source` function
    Incoming = "incoming",
    --- This is a Request or Response constructed via `new` it will assume all the
    --- properties have been filled manually
    Outgoing = "outgoing",
}
local SharedLogic = {}

---@alias Interface {mode:"incoming"|"outgoing", _fill_headers: (fun(Interface):nil|string),_fill_body: (fun(Interface):nil|string),_serialize_preamble: (fun(Interface): string|nil,nil|string), get_headers:(fun(Inteface):Headers|nil,nil|string), get_body: (fun(Inteface): string|nil,nil|string)}


---@param self Request|Response
---@return boolean|nil
---@return nil|string
function SharedLogic.parse_header(self)
    local line, err = self:_next_line()
    if not line then
        return nil, err
    end
    if self.headers == nil then
        self.headers = Headers.new()
    end
    if line == '' then
        return true
    else
        self.headers:append_chunk(line)
    end
    return false
end

---
---@param self Request|Response
---@return string|nil
function SharedLogic.fill_headers(self)
    ---@diagnostic disable-next-line: invisible
    if self._parsed_headers then
        return
    end
    while true do
        local done, err = SharedLogic.parse_header(self)
        if err ~= nil then
            return err
        end
        if done then
            ---@diagnostic disable-next-line: invisible
            self._parsed_headers = true
            return
        end
    end
end

function SharedLogic.get_content_length(self)
    if not self._parsed_headers then
        local err = SharedLogic.fill_headers(self)
        if err then return nil, err end
    end
    if not self._content_length then
        assert(self.headers, debug.traceback())
        local cl = self.headers:get_one('content_length')
        if not cl then
            return
        end
        local n = math.tointeger(cl)
        if not n then
            return nil, 'bad Content-Length header'
        end
        self._content_length = n
    end
    return self._content_length
end

---
---@param self Request|Response
---@return nil|string
function SharedLogic.fill_body(self)
    if self.mode == Mode.Incoming
    ---@diagnostic disable-next-line: invisible
    and not self._received_body then
        local len, err = SharedLogic.get_content_length(self)
        if err ~= nil then
            return err
        end
        ---@diagnostic disable-next-line: invisible
        local body, err = self._source(len or '*a')
        if not body then
            return err
        end
        self.body = body
        ---@diagnostic disable-next-line: invisible
        self._received_body = true
    end
end

---
---@param self Request|Response
---@return string|nil
---@return nil|string
function SharedLogic.get_body(self)
    local err = SharedLogic.fill_body(self)
    if err then
        return nil, err
    end
    return self.body
end

---@param self Request|Response
---@return Headers|nil
---@return nil|string
function SharedLogic.get_headers(self)
    ---@diagnostic disable-next-line: invisible
    if self.mode == Mode.Incoming and not self._parsed_headers then
        local err = SharedLogic.fill_headers(self)
        if err ~= nil then
            return nil, err
        end
    end
    return self.headers
end

---Serialize the pre body text of a request/response including the trailing new line
---@param t Request|Response
function SharedLogic.serialize_pre_body(t)
    local first, headers, headers_str, err
    first, err = t:_serialize_preamble()
    if not first then
        return nil, err
    end
    headers, err = t:get_headers()
    if not headers then
        return nil, err
    end
    headers_str, err = headers:serialize()
    if not headers_str then
        return nil, err
    end
    return first
        .. '\r\n'
        .. headers_str
        .. '\r\n'
end

--- Serailize the provide Request or Response into a string with new lines
---@param t Request|Response
---@return string|nil result The serialized string if nil an error occured
---@return nil|string err If not nil the error
function SharedLogic.serialize(t)
    local pre, body, e
    if t.mode == Mode.Incoming then
        e = SharedLogic.fill_headers(t)
        if e then return nil, e end
        e = SharedLogic.fill_body(t)
        if e then return nil, e end
    end
    pre, e = SharedLogic.serialize_pre_body(t)
    if not pre then
        return nil, e
    end
    body, e = t:get_body()
    if not body then
        return nil, e
    end
    return pre .. body
end

function SharedLogic.iter(self)
    local state = 'start'
    local suffix = '\r\n'
    local header_iter = self:get_headers():iter()
    local value, body
    return function()
        if state == 'start' then
            state = 'headers'
            return self:_serialize_preamble() .. suffix
        end
        if state == 'headers' then
            local header = header_iter()
            if not header then
                state = 'body'
                return suffix
            end
            return header .. suffix
        end
        if state == 'body' then
            if self.mode == Mode.Incoming then
                local line, err = self._next_line()
                if err == 'closed' or not line then
                    state = 'complete'
                    return nil
                end
                return line, err
            end
            
            if not body then
                local b, err = self:get_body()
                if not b then
                    return nil, err
                end
                state = 'body'
                body = b
            end
            value, body = utils.next_line(body, true)
            if not value then
                state = 'complete'
                return body
            end
            return value
        end
    end
end

return {
    SharedLogic = SharedLogic,
    Mode = Mode,
}
