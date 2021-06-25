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
  local req = lunch.Request.source(
    lunch.utils.tcp_socket_source(incoming)
  )
  print('into request')
  print('url', req.url.path)
  print('method', req.method)
  print('body', req:get_body())
  local res = assert(lunch.Response.new()
    :set_content_length(math.tointeger(req:get_headers().content_length or 0) or 0))
    :append_body(req:get_body())
  print('into response')
  for part in res:as_source() do
    print('sending', string.format('%q', part))
    assert(lunch.utils.send_all(incoming, part))
  end
  print('sent')
  incoming:close()
end
