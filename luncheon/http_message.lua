---@diagnostic disable: invisible
local Headers = require "luncheon.headers"
local utils = require "luncheon.utils"
local log = require "log"

---@alias SendState {stage: string, sent: integer}
---@alias Preamble {method:string,url:table,http_version:string}
---@alias Iterator fun():string|nil,string|nil

local CHUNKED = "chunked"

---@class HttpMessage
---
---An HTTP HttpMessage which represents common functionality between requests and responses
---
---@field public method string
---@field public headers Headers The HTTP headers for this HttpMessage
---@field public body string the contents of the body
---@field public http_version string
---@field public socket table The socket to send/receive on
---@field private _source SourceFn
---@field private _parsed_headers boolean
---@field private _received_body boolean
---@field private _send_state SendState
---@field public trailers Headers|nil The HTTP trailers
local HttpMessage = {}
HttpMessage.__index = HttpMessage

function HttpMessage:new(socket)
  local o = {
    _parsed_headers = true,
    _send_state = {
      stage = "none"
    },
    http_version = 1.1,
    headers = Headers.new(),
    body = "",
    socket = socket,
  }
  setmetatable(o, self)
  self.__index = self
  return o
end

---Construct a HttpMessage from a source function
---@generic T: HttpMessage
---@param source SourceFn
---@return T|nil
---@return table|string preamble or error
function HttpMessage:source(source)
  if not source then
    return nil, "cannot create request/response with nil source"
  end
  local o = {
    headers = Headers.new(),
    _source = source,
    _parsed_headers = false,
  }
  setmetatable(o, self)

  -- Parse source lines to preamble
  local line, err = o:_next_line()
  if err then
    return nil, err
  end

  -- check if line is only whitespace and move to next line
  while line and line:match("^%s*$") and not err do
    line, err = o:_next_line()
  end
  if not line then
    return nil, err
  end

  local pre, pre_err = o._parse_preamble(line)
  if not pre then
    return nil, pre_err
  end

  return o, pre
end

---Create a HttpMessage from a lua socket tcp socket
---@generic T: HttpMessage
---@param socket table tcp socket
---@return T|nil
---@return nil|string
function HttpMessage:tcp_source(socket)
  ---@diagnostic disable-next-line: missing-parameter
  local ret, err = self.source(
    utils.tcp_socket_source(socket)
  )
  if not ret then
    return nil, err
  end
  ret.socket = socket
  return ret
end

---Create a response from a lua socket udp socket
---@generic T: HttpMessage
---@param socket table udp socket
---@return T|nil
---@return nil|string
function HttpMessage:udp_source(socket)
  local utils = require "luncheon.utils"
  local ret, err = self.source(
    utils.udp_socket_source(socket)
  )
  if not ret then
    return nil, err
  end
  ret.socket = socket
  return ret
end

function HttpMessage:_next_line()
  local line, err = self._source("*l")
  return line, err
end

---Append a header to the `Headers` with the matching name
---@param k string
---@param v string|any
---@param name string
function HttpMessage:_append_header(k, v, name)
  if not self[name] then
    self[name] = Headers.new()
  end
  if type(v) ~= "string" then
    v = tostring(v)
  end
  self[name]:append(k, v)
end

---Append a header to the `Headers` with the matching name
---@param k string
---@param v string|any
---@param name string
function HttpMessage:_replace_header(k, v, name)
  if not self[name] then
    self[name] = Headers.new()
  end
  if type(v) ~= "string" then
    v = tostring(v)
  end
  self[name]:replace(k, v)
end

---Add a header to the internal map of headers
---note: this is additive, so adding X-Forwarded-For twice will
---cause there to be multiple X-Forwarded-For entries in the serialized
---headers
---note: This is only intended for use with chunk-encoding any other encoding scheme
---will end up ignoring these values
---@param key string The Header's key
---@param value string The Header's value
---@return HttpMessage
function HttpMessage:add_header( key, value)
  self:_append_header(key, value, "headers")
  return self
end

---Add a trailer to the internal map of trailers
---note: this is additive, so adding X-Forwarded-For twice will
---cause there to be multiple X-Forwarded-For entries in the serialized
---headers
---@param key string The Header's key
---@param value string The Header's value
---@return HttpMessage
function HttpMessage:add_trailer(key, value)
  self:_append_header(key, value, "trailers")
  return self
end

---Replace or append a header to the internal headers map
---
---note: this is not additive, any existing value will be lost
---@param key string
---@param value any If not a string will call tostring
---@return HttpMessage
function HttpMessage:replace_header(key, value)
  self:_replace_header(key, value, "headers")
  return self
end

---Replace or append a trailer to the internal trailers map
---
---note: This is not additive, any existing value will be lost
---note: This is only intended for use with chunk-encoding any other encoding scheme
---will end up ignoring these values
---@param key string
---@param value any If not a string will call tostring
---@return HttpMessage
function HttpMessage:replace_trailer(key, value)
  self:_replace_header(key, value, "trailers")
  return self
end

---Set the Content-Type header for this HttpMessage
---convenience wrapper around self:replace_header('content_type', len)
---@param ct string The mime type to add as the Content-Type header's value
---@return HttpMessage|nil
---@return nil|string
function HttpMessage:set_content_type(ct)
  if type(ct) ~= "string" then
    return nil, string.format("mime type must be a string, found %s", type(ct))
  end
  return self:replace_header("content_type", ct)
end

---Set the Content-Length header for this HttpMessage
---@param len number The length of the content that will be sent
---@return HttpMessage|nil
---@return nil|string
function HttpMessage:set_content_length(len)
  if type(len) ~= "number" then
    return nil, string.format("content length must be a number, found %s", type(len))
  end
  return self:replace_header("content_length", string.format("%i", len))
end

---Set the Transfer-Encoding header for this request by default this will be length encoding
---@generic T: HttpMessage
---@param te string The transfer encoding
---@param chunk_size integer|nil if te is "chunked" the size of the chunk to send defaults to 1024
---@return T
function HttpMessage:set_transfer_encoding(te, chunk_size)
  if HttpMessage.includes_chunk_encoding(te) then
    self._chunk_size = chunk_size or 1024
  end
  return self:replace_header("transfer_encoding", te)
end

---Append text to the body
---@param s string the text to append
---@return HttpMessage
function HttpMessage:append_body(s)
  self.body = (self.body or "") .. s
  if not self._chunk_size then
    self:set_content_length(#self.body)
  end
  return self
end

---@param key string|nil The header map key to use, defaults to "headers"
---@return boolean|nil
---@return nil|string
function HttpMessage:read_header(key)
  key = key or "headers"
  local line, err = self:_next_line()
  if not line then
    return nil, err
  end
  if self[key] == nil then
    self[key] = Headers.new()
  end
  if line == "" then
    return true
  else
    local s, e = self[key]:append_chunk(line)
    if not s then
      return nil, e
    end
  end
  return false
end

---
---@return string|nil
function HttpMessage:fill_headers(key)
  key = key or "headers"
  local parsed_key = string.format("_parsed_%s", key)
  if self[parsed_key] then
    return
  end
  while true do
    local done, err = HttpMessage.read_header(self, key)
    if err ~= nil then
      return err
    end
    if done then
      self[parsed_key] = true
      return
    end
  end
end

function HttpMessage:get_content_length()
  if not self._parsed_headers then
    local err = HttpMessage.fill_headers(self, "headers")
    if err then return nil, err end
  end
  if not self._content_length then
    local cl = self.headers:get_one("content_length")
    if not cl then
      return
    end
    local n = math.tointeger(cl)
    if not n then
      return nil, "bad Content-Length header"
    end
    self._content_length = n
  end
  return self._content_length
end

function HttpMessage.includes_chunk_encoding(header)
  if header == CHUNKED then
    return true
  end
  for value in string.gmatch(header, "([^ ,]+)") do
    if value == CHUNKED then
      return true
    end
  end
  return false
end

---Determine what type of body we are dealing with
---@return table|nil
---@return nil|string
function HttpMessage:body_type()
  local len, headers, enc, err
  len, err = self:get_content_length()
  if not len and err then
    return nil, err
  end
  if len then
    return {
      type = "length",
      length = len
    }
  end
  headers, err = self:get_headers()
  if not headers then
    return nil, err
  end

  enc = headers:get_all("transfer_encoding")
  local ty = "close"
  if not enc then
    return {
      type = ty,
    }
  end
  for _, v in ipairs(enc) do
    if HttpMessage.includes_chunk_encoding(v) then
      ty = "chunked"
      break
    end
  end
  local trailers = false
  if ty == "chunked" then
    local trailer = headers:get_all("trailer")
    trailers = trailer and #trailer > 0 and #trailer[1] > 0
  end
  return {
    type = ty,
    trailers = trailers
  }
end

---fill a body based on content-length
---@param len integer
---@return string|nil
---@return nil|string
function HttpMessage:fill_fixed_length_body(len)
  local body, err = self._source(len)
  if not body then
    return nil, err
  end
  return body
end

---fill a body by reading until the socket is closed
---@return string|nil
---@return nil|string
function HttpMessage:fill_closed_body()
  local body, err = self._source("*a")
  if not body then
    return nil, err
  end
  return body
end

---@return string|nil
---@return nil|string
function HttpMessage:fill_chunked_body_step()
  -- read chunk length with trailing new lines

  local len, err = self._source("*l")
  if not len then
    return nil, err
  end
  local trimmed = string.match(len, "^[^;]+")
  for extension in string.gmatch(len, ";([^;]+)") do
    log.warn(string.format("found unsupported extension: %q", extension))
  end
  if trimmed == "0" then
    return nil, "___eof___"
  end
  local len2 = tonumber(trimmed, 16)
  if not len2 then
    return nil, "invalid number for chunk length"
  end

  local chunk, err = self._source(len2)
  if not chunk then
    return nil, err
  end
  -- clear new line
  self._source(2)
  return chunk
end

---@return string|nil
---@return nil|string
---@return nil|string
function HttpMessage:fill_chunked_body()
  local ret, chunk, err = "", nil, nil
  repeat
    chunk, err = HttpMessage.fill_chunked_body_step(self)
    ret = ret .. (chunk or "")
  until err
  if err == "___eof___" then
    return ret
  end
  return nil, err, ret
end

---Check for trailers and add them to the headers if present
---this should only be called when chunked encoding has been detected
function HttpMessage:check_for_trailers()
  local headers, err = self:get_headers()
  if not headers then
    return nil, err
  end
  local trailer = headers:get_all("trailer")
  for _, _header_name in ipairs(trailer or {}) do
    local done, err = HttpMessage.read_header(self, "trailers")
    if done then
      break
    end
    if err ~= nil then
      return nil, err
    end
  end
  return 1
end

---
---@return nil|string
function HttpMessage:fill_body()
  if self._source ~= nil
      and not self._received_body then
    local ty, err = self:body_type()
    if not ty then
      return err
    end
    local body, err
    if ty.type == "length" then
      body, err = self:fill_fixed_length_body(ty.length)
      if not body then
        return err
      end
    elseif ty.type == "close" then
      -- We only want to read until socket closing if the socket
      -- will actually close, otherwise it will hang. The lack of
      -- a content-length header is not enough of a clue as the
      -- socket may be setup for keep-alive.
      body, err = self:fill_closed_body()
      if not body then
        return err
      end
    else
      body, err = self:fill_chunked_body()
      self:check_for_trailers()
      if not body then
        return err
      end
    end
    self.body = body
    self._received_body = true
  end
end

---
---@return string|nil
---@return nil|string
function HttpMessage:get_body()
  local err = self:fill_body()
  if err then
    return nil, err
  end
  return self.body
end

---@return Headers|nil
---@return nil|string
function HttpMessage:get_headers()
  if self._source ~= nil and not self._parsed_headers then
    local err = self:fill_headers()
    if err ~= nil then
      return nil, err
    end
  end
  return self.headers
end

--- Serailize the provide Request or Response into a string with new lines
---@return string|nil result The serialized string if nil an error occured
---@return nil|string err If not nil the error
function HttpMessage:serialize()
  local ret = ""
  for chunk in self:iter() do
    ret = ret .. chunk
  end
  return ret
end

---build and iterator for outbound chunked encoding
---@return Iterator|nil
---@return string|nil
function HttpMessage:chunked_oubtbound_body_iter()
  local chunk_size = self._chunk_size or 1024
  local body, err = self:get_body()
  if not body then
    return nil, err
  end
  return function()
    if not body then
      return nil, "___eof___"
    end
    local chunk = string.sub(body, 1, chunk_size)
    body = string.sub(body, math.min(#chunk, chunk_size) + 1, #body)
    if chunk == "" then
      body = nil
    end
    local ret = string.format("%x\r\n%s", #chunk, chunk)
    if #chunk > 0 then
      return ret .. "\r\n"
    end
    return ret
  end
end

---build and iterator for outbound non-chunked encoding
---@return Iterator|nil
---@return nil|string
function HttpMessage:normal_body_iter()
  local body, line, err
  body, err = self:get_body()
  if not body then
    return nil, err
  end
  return function()
    line, body = utils.next_line(body, true)
    if not line then
      if #body == 0 then
        return nil, "___eof___"
      else
        local ret = body
        body = ""
        return ret
      end
    end

    return line
  end
end

function HttpMessage.iter(self)
  local state = "start"
  local suffix = "\r\n"
  local header_iter = self:get_headers():iter()
  local value, body, body_iter, body_type, err, trailers_iter
  return function()
    if state == "start" then
      state = "headers"
      return self:_serialize_preamble() .. suffix
    end
    if state == "headers" then
      local header = header_iter()
      if not header then
        state = "body"
        return suffix
      end
      return header .. suffix
    end
    if state == "body" then
      if self._source ~= nil then
        if not body_type then
          body_type, err = self:body_type()
          if not body_type then
            return nil, err
          end
        end
        if body_type.type == "chunked" then
          local chunk, err = self:fill_chunked_body_step()
          if err == "___eof___" then
            if body_type.trailers then
              state = "trailers"
              self:fill_headers("trailers")
              if self.trailers then
                trailers_iter = self.trailers:iter()
                local trailer = trailers_iter()
                if trailer then
                  return trailer .. suffix
                end
              end
            end
            state = "complete"
            return suffix
          end
          return chunk, err
        end
        local line, err = self:_next_line()
        if err == "closed" or not line then
          state = "complete"
          return nil
        end
        return line, err
      end
      if not body_iter then
        if self._chunk_size then
          body_iter, err = self:chunked_oubtbound_body_iter()
        else
          body_iter, err = self:normal_body_iter()
        end
        if not body_iter then
          body_iter = function() return nil, err end
        end
      end
      value, err = body_iter()
      if not value then
        if err == "___eof___" then
          if self._chunk_size then
            if self.trailers then
              state = "trailers"
              trailers_iter = self.trailers:iter()
              return trailers_iter()
            end
            state = "complete"
            return "\r\n"
          else
            state = "complete"
          end
        else
          return nil, err
        end
      end
      return value
    end
    if state == "trailers" then
      if not trailers_iter then
        state = "complete"
        return nil
      end
      local trailer = trailers_iter()
      if not trailer then
        state = "complete"
        return "\r\n"
      end
      return trailer .. suffix
    end
  end
end

---Send the first line of the Request|Response
---@return integer|nil
---@return string|nil
function HttpMessage:send_preamble()
  if self._send_state.stage ~= "none" then
    return 1 --already sent
  end
  local line = self:_serialize_preamble() .. "\r\n"
  local s, err = utils.send_all(self.socket, line)
  if not s then
    return nil, err
  end
  self._send_state.stage = "header"
  return 1
end

---Collect the preamble and headers to the provided limit
---@param max integer
---@return string
---@return integer
function HttpMessage:build_chunk(max)
  local buf = ""
  if self._send_state.stage == "none" then
    buf = self:_serialize_preamble() .. "\r\n"

    self._send_state.stage = "header"
  end
  if #buf >= max then
    return buf, 0
  end
  local inner_headers = self.headers._inner
  while self._send_state.stage == "header" do
    local key, value = next(inner_headers, self._send_state.last_header)
    if not key then
      buf = buf .. "\r\n"

      self._send_state = {
        stage = "body",
        sent = 0,
      }
      break
    end
    local line = Headers.serialize_header(key, value) .. "\r\n"
    if #line + #buf > max then
      return buf, 0
    end
    self._send_state.last_header = key
    buf = buf .. line
  end
  local body_len = 0
  if #buf < max then
    body_len = max - #buf
    local start_idx = (self._send_state.sent or 0) + 1
    local end_idx = start_idx + body_len
    local chunk = string.sub(self.body, start_idx, end_idx)
    body_len = #chunk
    buf = buf .. chunk
  end
  return buf, body_len
end

---Pass a single header line into the sink functions
---@return integer|nil If not nil, then successfully "sent"
---@return nil|string If not nil, the error message
function HttpMessage:send_header()
  if self._send_state.stage == "none" then
    return self:send_preamble()
  end
  if self._send_state.stage == "body" then
    return nil, "cannot send headers after body"
  end
  local key, value = next(self.headers._inner, self._send_state.last_header)
  if not key then
    local s, e = utils.send_all(self.socket, "\r\n")
    if not s then
      return nil, e
    end
    self._send_state = {
      stage = "body",
      sent = 0,
    }
    return 1
  end
  local line = Headers.serialize_header(key, value) .. "\r\n"
  local s, e = utils.send_all(self.socket, line)
  if not s then
    return nil, e
  end
  self._send_state.last_header = key
  return 1
end

---Slice a chunk of at most 1024 bytes from `self.body` and pass it to
---the sink
---@return integer|nil if not nil, success
---@return nil|string if not nil and error message
function HttpMessage:send_body_chunk()
  local chunk, body_len = self:build_chunk(1024)
  local s, e, i = utils.send_all(self.socket, chunk)
  if not s then
    return nil, e
  end
  self._send_state.sent = (self._send_state.sent or 0) + body_len
  return 1
end

---Final send of a request or response
---@param bytes string|nil
---@param skip_length boolean|nil
function HttpMessage:send(bytes, skip_length)
  if bytes then
    self.body = self.body .. bytes
  end
  if self._send_state.stage ~= "body" and not skip_length then
    self:set_content_length(#self.body)
  end
  while self._send_state.stage ~= "body"
    or (self._send_state.sent or 0) < #self.body do
    local s, e = self:send_body_chunk()
    if not s then
      return nil, e
    end
  end
  return 1
end

return HttpMessage
