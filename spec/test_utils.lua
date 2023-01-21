local m = {}

m.create_chunked_source = function(body)
  local buf = body
  return function(pat)
    if #buf == 0 then
      return nil, "closed"
    end
    pat = pat or "*l"
    if type(pat) == "number" then
      local ret = string.sub(buf, 1, pat)
      buf = string.sub(buf, pat + 1)
      return ret
    end
    local s, end_idx = string.find(buf, "\r?\n")
    if not s then
      return nil, "closed"
    end
    local ret = string.sub(buf, 1, s - 1)
    buf = string.sub(buf, end_idx + 1)
    return ret
  end
end
local function create_chunked_body(chunks, extensions, trailers)
  local body = ""
  local assert_body = ""
  for i, chunk in ipairs(chunks) do
    local ext = (extensions[i] and ";" .. extensions[i]) or ""
    body = body .. string.format("%x%s\r\n%s\r\n", #chunk, ext, chunk)
    assert_body = assert_body .. chunk
  end
  body = body .. "0\r\n"
  for _, trailer in ipairs(trailers) do
    body = body .. trailer .. "\r\n"
  end
  body = body .. "\r\n"
  return body, assert_body
end

local function request_first_line(method, url)
  return string.format("%s %s HTTP/1.1", method, url)
end

local function response_first_line(status)
  local statuses = require "luncheon.status"
  return string.format("HTTP/1.1 %s %s", status, statuses[status])
end

local function generate_trailer_header(trailers)
  if #trailers == 0 then
    return ""
  end
  local ret = "Trailer: "
  for i, trailer in ipairs(trailers) do
    if i > 1 then
      ret = ret .. ","
    end
    ret = ret .. string.match(trailer, "^[^:]+")
  end
  return ret .. "\r\n"
end

local function create_chunked(chunks, status, method, url, extensions, trailers)
  status = status or 200
  method = method or "GET"
  url = url or "/"
  extensions = extensions or {}
  trailers = trailers or {}
  local body, assert_body = create_chunked_body(chunks, extensions, trailers)
  local header = "transfer-encoding: chunked"
  local header2 = generate_trailer_header(trailers)
  local request = request_first_line(method, url) .. "\r\n"
    .. header .. "\r\n"
    .. header2
    .. "\r\n"
    .. body
  local response = response_first_line(status).."\r\n"
    .. header.."\r\n"
    .. header2
    .. "\r\n"
    .. body
  return {
    chunked_body = body,
    assert_body = assert_body,
    request = request,
    response = response,
  }
end

m.wikipedia_chunks = create_chunked({
  "Wiki",
  "pedia ",
  "in \r\n\r\nchunks."
}, 200, "GET", "/")

m.large_chunks = create_chunked({
  string.rep("a", 1024),
  string.rep("b", 2048),
  string.rep("c", 3096),
}, 200, "GET", "/large")

m.extended = create_chunked({
  "hello",
  "world"
}, 200, "GET", "/extended", {"ext1", "ext2", "ext3"})
m.trailers = create_chunked({
  "the message will have extra headers",
  "after it"
}, 200, "GET", "/trailers", {}, {"Date: Today", "Junk: This is a junk header!"})

--- Checks if the value provided is in the set and removes it if it is
function m.assert_in_set(set, value)
  if set[value] then
    set[value] = nil
    return
  end
  local msg = ""
  for k, _ in pairs(set) do
    if #msg > 0 then
      msg = msg .. " or "
    end
    msg = msg .. string.gsub(string.gsub(k, "\r", "\\r"), "\n", "\\n")
  end
  error(string.format("Expected %s found %q", msg, value), 2)
end

return m
