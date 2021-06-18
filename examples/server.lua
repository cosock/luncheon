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
  local req = lunch.Request.incoming(incoming)
  print('into request')
  print('url', req.url.path)
  print('method', req.method)
  print('body', req:get_body())
  local res = assert(lunch.Response.outgoing(incoming)
    :content_length(math.tointeger(req:get_headers().content_length or 0) or 0))
  print('into response')
  for part in res:source() do
    print('sending', string.format('%q', part))
    assert(incoming:send(part))
  end
  assert(incoming:send(req:get_body()))
  print('sent')
  res:close()
end
