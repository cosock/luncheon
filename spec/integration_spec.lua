local Request = require 'luncheon.request'
local Response = require 'luncheon.response'

describe('real sockets tests', function ()
  local cosock = require 'cosock'
  it('outgoing creates Response error', function ()
    local server = cosock.socket.tcp()
    server:bind('*', 0)
    local ip, port = assert(server:getsockname())
    cosock.spawn(function ()
        server:listen()
        local incoming = server:accept()
        assert(Request.incoming(incoming))
        local Response = require 'luncheon.response'
        local res = assert(Response.outgoing(incoming))
        assert(res:send())
    end, 'server task')
    cosock.spawn(function ()
        local client = cosock.socket.tcp()
        client:connect(ip, port)
        local r = assert(Request.outgoing('GET', '/', client):set_body(''))
        local res = assert(r:send())
        assert.are.same(Response, getmetatable(res))
    end, 'client task')
    cosock.run()
  end)
end)
