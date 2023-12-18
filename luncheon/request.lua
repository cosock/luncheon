local net_url = require "net.url"
local Headers = require "luncheon.headers"
local ReqResp = require "luncheon.shared"

---@class Request
---
---An HTTP Request
---
---@field public method string the HTTP method for this request
---@field public url table The parsed url of this request
---@field public http_version string The http version from the request first line
---@field public headers Headers The HTTP headers for this request
---@field public body string The contents of the request's body
---@field public socket table Lua socket for receiving/sending
---@field private _send_state {stage: string, sent: integer}
---@field private _source fun(pat:string|number|nil):string
---@field private _parsed_headers boolean
---@field private _received_body boolean
---@field public trailers Headers|nil The HTTP trailers
local Request = {}
setmetatable(Request, ReqResp)
Request.__index = Request

--#region Parser

---Parse the first line of an HTTP request
---@param line string
---@return {method:string,url:table,http_version:string}|nil table
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
  local r, pre, err = ReqResp.source(Request, source)
  if not pre then
    return nil, err
  end
  r.http_version = pre.http_version
  r.method = pre.method
  r.url = pre.url
  return r
end

---Create a new Request with a lua socket
---@param socket table tcp socket
---@return Request|nil request with the first line parsed
---@return nil|string if not nil an error message
function Request.tcp_source(socket)
  local ret, err = ReqResp.tcp_source(Request, socket)
  return ret, err
end

---Create a new Request with a lua socket
---@param socket table udp socket
---@return Request|nil
---@return nil|string
function Request.udp_source(socket)
  local ret, err = ReqResp.udp_source(Request, socket)
  return ret, err
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
  local ret = ReqResp.new(Request, socket)
  if type(url) == "string" then
    url = net_url.parse(url)
  end
  ret.url = url
  ret.method = method or "GET"
  return ret
end

---Add a header to the internal map of headers
---note: this is additive, so adding X-Forwarded-For twice will
---cause there to be multiple X-Forwarded-For entries in the serialized
---headers
---note: This is only intended for use with chunk-encoding any other encoding scheme
---will end up ignoring these values
---@param key string The Header's key
---@param value string The Header's value
---@return Request
function Request:add_header(key, value)
  ReqResp.append_header(self, key, value, "headers")
  return self
end

---Add a trailer to the internal map of trailers
---note: this is additive, so adding X-Forwarded-For twice will
---cause there to be multiple X-Forwarded-For entries in the serialized
---headers
---@param key string The Header's key
---@param value string The Header's value
---@return Request
function Request:add_trailer(key, value)
  ReqResp.append_header(self, key, value, "trailers")
  return self
end

---Replace or append a header to the internal headers map
---
---note: this is not additive, any existing value will be lost
---@param key string
---@param value any If not a string will call tostring
---@return Request
function Request:replace_header(key, value)
  ReqResp.replace_header(self, key, value, "headers")
  return self
end

---Replace or append a trailer to the internal trailers map
---
---note: This is not additive, any existing value will be lost
---note: This is only intended for use with chunk-encoding any other encoding scheme
---will end up ignoring these values
---@param key string
---@param value any If not a string will call tostring
---@return Request
function Request:replace_trailer(key, value)
  ReqResp.replace_header(self, key, value, "trailers")
  return self
end

---Set the Content-Type header for this request
---convenience wrapper around self:replace_header('content_type', len)
---@param ct string The mime type to add as the Content-Type header's value
---@return Request|nil
---@return nil|string
function Request:set_content_type(ct)
  if type(ct) ~= "string" then
    return nil, string.format("mime type must be a string, found %s", type(ct))
  end
  self:replace_header("content_type", ct)
  return self
end

---Set the Content-Length header for this request
---convenience wrapper around self:replace_header('content_length', len)
---@param len number The Expected length of the body
---@return Request
function Request:set_content_length(len)
  self:replace_header("content_length", tostring(len))
  return self
end

---Set the Transfer-Encoding header for this request by default this will be length encoding
---@param te string The transfer encoding
---@param chunk_size integer|nil if te is "chunked" the size of the chunk to send defaults to 1024
---@return Request
function Request:set_transfer_encoding(te, chunk_size)
  if ReqResp.includes_chunk_encoding(te) then
    self._chunk_size = chunk_size or 1024
  end
  return self:replace_header("transfer_encoding", te)
end

---append the provided chunk to this Request's body
---@param chunk string The text to add to this request's body
---@return Request
function Request:append_body(chunk)
  self.body = (self.body or "") .. chunk
  if not self._chunk_size then
    self:set_content_length(#self.body)
  end
  return self
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
