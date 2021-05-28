local lunch = require 'luncheon'
local socket = require 'socket'

local sock = socket.tcp()
sock:setoption('reuseaddr', true)
sock:bind('0.0.0.0', 8080)
sock:listen()

while true do
  local incoming, err = sock:accept()
  if not incoming then
    print('error', err)
    break
  end
  local req = lunch.Request.incoming(incoming)
  local res = assert(lunch.Response.outgoing(incoming)
    :content_length(math.tointeger(req:get_headers().content_length or 0) or 0))
  for part in res:source() do
    assert(incoming:send(part))
  end
  
end
