local lunch = require 'luncheon'
local socket = require 'socket'

local sock = socket.tcp()
sock:connect('0.0.0.0', 8080)

local r = assert(lunch.Request.new('GET', '/', sock)
  :append_body('asdf'))

for line in r:iter() do
  sock:send(line)
end

local res = assert(lunch.Response.tcp_source(sock))

print('Response')
print(res.status)
print(res:get_body())

sock:close()
