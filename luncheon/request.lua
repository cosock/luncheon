local net_url = require "net.url"
local HttpMessage = require "luncheon.http_message"

---@class Request:HttpMessage
local Request = {}
setmetatable(Request, HttpMessage)
Request.__index = Request

--#region Parser

---Parse the first line of an HTTP request
---@param line string
---@return Preamble|nil
---@return nil|string
function Request._parse_preamble(line)
  local start, _, method, path, http_version = string.find(line, "([^ ]+) (.+) HTTP/([0-9.]+)")
  if not start then
    return nil, string.format('Invalid http request first line: "%s"', line)
  end
  return {
    method = method,
    url = net_url.parse(path),
    http_version = http_version,
    body = nil,
    headers = nil,
  }
end

---Construct a request from a source function
---@param source fun(pat:string|number|nil):string|nil,nil|string
---@return Request|nil request
---@return nil|string error
function Request.source(source)
  local r, pre_or_err = HttpMessage.source(Request, source)
  if not r then
    return nil, pre_or_err
  end
  r.http_version = pre_or_err.http_version
  r.method = pre_or_err.method
  r.url = pre_or_err.url
  return r
end

---Create a new Request with a lua socket
---@param socket table tcp socket
---@return Request|nil request with the first line parsed
---@return nil|string if not nil an error message
function Request.tcp_source(socket)
  return HttpMessage.tcp_source(Request, socket)
end

---Create a new Request with a lua socket
---@param socket table udp socket
---@return Request|nil
---@return nil|string
function Request.udp_source(socket)
  return HttpMessage.udp_source(Request, socket)
end

---@deprecated see get_content_length
function Request:content_length()
  return self:get_content_length()
end

--#endregion Parser

--#region Builder
---Construct a request Builder
---@param method string|nil an http method string
---@param url string|table|nil the path for this request as a string or as a net_url table
---@param socket table|nil
---@return Request
function Request.new(method, url, socket)
  local ret = HttpMessage.new(Request, socket)
  if type(url) == "string" then
    url = net_url.parse(url)
  end
  ret.url = url
  ret.method = method or "GET"
  return ret
end

---Private method for serializing the url property into a valid URL string suitable
---for the first line of an HTTP request
---@return string
function Request:_serialize_path()
  if type(self.url) == "string" then
    self.url = net_url.parse(self.url)
  end
  local path = self.url.path or "/"
  if not self.url.query or not next(self.url.query) then
    return path
  end
  return path .. "?" .. net_url.buildQuery(self.url.query)
end

---Private method for serializing the first line of the request
---@return string
function Request:_serialize_preamble()
  return string.format("%s %s HTTP/%s", string.upper(self.method), self:_serialize_path(),
    self.http_version)
end

--#endregion Builder

return Request
