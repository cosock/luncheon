local lunch = require 'luncheon'
local socket = require 'socket'

local sock = socket.tcp()
sock:setoption('reuseaddr', true)
assert(sock:bind('0.0.0.0', 8080))
assert(sock:listen())

while true do
  local incoming, err = sock:accept()
  print('accepted')
  if not incoming then
    print('error', err)
    break
  end
  local req = assert(lunch.Request.tcp_source(
    incoming
  ))
  print('into request')
  print('url', req.url.path)
  print('method', req.method)
  print('body', req:get_body())
  local res = assert(lunch.Response.new())
    -- avoid setting the content length (note append_body does this automatically)
    -- :set_content_length(math.tointeger(req:get_headers().content_length or 0) or 0))
    -- :append_body(req:get_body())
  print('into response')
  for part in res:iter() do
    print('sending', string.format('%q', part))
    assert(lunch.utils.send_all(incoming, part))
  end
  -- send some body
  assert(lunch.utils.send_all(incoming, "asdf"))

  print('sent')
  -- The server leaves the socket open when it should close it because the client has no other
  -- way to know the end of the response. The client receives successfully if uncommented.
  -- incoming:close()
end
