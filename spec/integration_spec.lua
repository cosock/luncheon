local Request = require 'luncheon.request'
local Response = require 'luncheon.response'
local utils = require 'luncheon.utils'

describe('real sockets tests', function ()
  local cosock = require 'cosock'
  it('tcp sockets', function ()
    local server = cosock.socket.tcp()
    server:bind('*', 0)
    local ip, port = assert(server:getsockname())
    cosock.spawn(function ()
      server:listen()
      local incoming = server:accept()
      local req = assert(Request.source(utils.tcp_socket_source(incoming)))
      req:get_body()
      local res = assert(Response.new(200))
      for chunk in res:as_source() do
        assert(incoming:send(chunk))
      end
    end, 'server task')
    cosock.spawn(function ()
      local client = cosock.socket.tcp()
      client:connect(ip, port)
      local r = assert(Request.new('GET', '/'))
      for chunk in r:as_source() do
        assert(client:send(chunk))
      end
      local res = assert(Response.source(utils.tcp_socket_source(client)))
      assert.are.equal(200, res.status)
    end, 'client task')
    cosock.run()
  end)
  it('udp sockets', function ()
    local server = cosock.socket.udp()
    server:setsockname('*', 0)
    local server_ip, server_port = assert(server:getsockname())
    local client = cosock.socket.udp()
    client:setsockname('*', 0)
    local client_ip, client_port = assert(client:getsockname())
    cosock.spawn(function ()
      server:setpeername(client_ip, client_port)
      assert(Request.source(utils.udp_socket_source(server)))
      local res = assert(Response.new(200))
      for chunk in res:as_source() do
        assert(server:send(chunk))
      end
    end, 'server task')
    cosock.spawn(function()
      client:setpeername(server_ip, server_port)
      local r = assert(Request.new('GET', '/'))
      for chunk in r:as_source() do
        assert(client:send(chunk))
      end
      local res = assert(Response.source(utils.udp_socket_source(client)))
      assert.are.equal(200, res.status)
    end, 'client task')
    cosock.run()
  end)
end)
