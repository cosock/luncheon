local statuses = require "luncheon.status"
local ReqResp = require "luncheon.shared"

---@class Response
---
---An HTTP Response
---
---@field public headers Headers The HTTP headers for this response
---@field public body string the contents of the response body
---@field public status number The HTTP status 3 digit number
---@field public status_msg string The HTTP status message
---@field public http_version string
---@field public socket table The socket to send/receive on
---@field private _source fun(pat:string|number|nil):string
---@field private _parsed_headers boolean
---@field private _received_body boolean
---@field private _send_state {stage: string, sent: integer}
---@field public trailers Headers|nil The HTTP trailers
local Response = {}
setmetatable(Response, ReqResp)
Response.__index = Response

--#region Parser


---Create a request parser from a source function
---@param source fun(pat:string|number|nil):string|nil,string|nil,string|nil
---@return Response|nil
---@return nil|string error if return 1 is nil the error string
function Response.source(source)
  local ret, pre, err = ReqResp.source(Response, source)

  if not pre then
    return nil, err
  end
  ret.status = pre.status
  ret.status_msg = pre.status_msg
  ret.http_version = pre.http_version
  return ret
end

---Create a response from a lua socket tcp socket
---@param socket table tcp socket
---@return Response|nil
---@return nil|string
function Response.tcp_source(socket)
  local ret, err = ReqResp.tcp_source(Response, socket)
  return ret, err
end

---Create a response from a lua socket udp socket
---@param socket table udp socket
---@return Response|nil
---@return nil|string
function Response.udp_source(socket)
  local ret, err = ReqResp.udp_source(Response, socket)
  return ret, err
end

---Parse the first line of an incoming response
---@param line string
---@return nil|table @`{http_version: number, status: number, status_msg: string}`
---@return nil|string @Error message if populated
function Response._parse_preamble(line)
  local version, status, msg = string.match(line, "HTTP/([0-9.]+) ([^%s]+) (.+)")
  if not version then
    return nil, string.format("Invalid http response first line: %q", line)
  end
  return {
    http_version = tonumber(version),
    status = math.tointeger(status),
    status_msg = msg,
  }
end

---Get the next line from an incoming request, checking first
---if we have reached the end of the content
---@return string|nil
---@return string|nil
function Response:next_line()
  if not self._source then
    return nil, "nil source"
  end
  return self:_next_line()
end

function Response:get_body()
  return ReqResp.get_body(self)
end

--#region builder

---Create a new response for building in memory
---@param status_code number|nil if not provided 200
---@param socket table|nil luasocket for sending (not required)
function Response.new(status_code, socket)
  if status_code == nil then
    status_code = 200
  end
  if ({ string = true, number = true })[type(status_code)] then
    status_code = math.tointeger(status_code)
  else
    return nil, string.format("Invalid status code %s", type(status_code))
  end

  local ret = ReqResp.new(Response, socket)
  ret.status = status_code or 200
  ret.status_msg = statuses[status_code] or "Unknown"
  return ret
end

---Generate the first line of this response without the trailing \r\n
---@return string|nil
function Response:_serialize_preamble()
  return string.format("HTTP/%s %s %s",
    self.http_version,
    self.status,
    statuses[self.status] or ""
  )
end

---Set the status for this outgoing request
---@param n number|string the 3 digit status
---@return Response|nil response
---@return nil|string error
function Response:set_status(n)
  if type(n) == "string" then
    n = math.tointeger(n) or n
  end
  if type(n) ~= "number" then
    return nil, string.format("http status must be a number, found %s", type(n))
  end
  self.status = n
  self.status_msg = statuses[n] or ""
  return self
end

--#endregion

--#region sink

function Response:has_sent()
  return self._send_state.stage ~= "none"
end

--#endregion

return Response
