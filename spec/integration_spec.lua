local Request = require 'luncheon.request'
local Response = require 'luncheon.response'
local utils = require 'luncheon.utils'

describe('real sockets tests', function ()
  local cosock = require 'cosock'
  local expected_body = 'this is a request body'
  it('tcp sockets', function ()
    local server = cosock.socket.tcp()
    server:bind('*', 0)
    local ip, port = assert(server:getsockname())
    cosock.spawn(function ()
      server:listen()
      local incoming = server:accept()
      local req = assert(Request.source(utils.tcp_socket_source(incoming)))
      local body = req:get_body()
      assert.are.equal(expected_body, body)
      local res = assert(Response.new(200))
        :append_body(body)
      for chunk in res:as_source() do
        assert(incoming:send(chunk))
      end
    end, 'server task')
    cosock.spawn(function ()
      local client = cosock.socket.tcp()
      client:connect(ip, port)
      local r = assert(Request.new('GET', '/'))
        :append_body(expected_body)
      for chunk in r:as_source() do
        assert(client:send(chunk))
      end
      local res = assert(Response.source(utils.tcp_socket_source(client)))
      assert.are.equal(200, res.status)
      local cl = res:get_content_length()
      assert.are.equal(#expected_body, cl)
      assert.are.equal(expected_body, res:get_body())
    end, 'client task')
    cosock.run()
  end)
  it('udp sockets', function ()
    local expected_body = 'this is a request body'
    local server = cosock.socket.udp()
    server:setsockname('*', 0)
    local server_ip, server_port = assert(server:getsockname())
    local client = cosock.socket.udp()
    client:setsockname('*', 0)
    local client_ip, client_port = assert(client:getsockname())
    cosock.spawn(function ()
      server:setpeername(client_ip, client_port)
      local req = assert(Request.source(utils.udp_socket_source(server)))
      assert.are.equal(expected_body, req:get_body())
      local res = assert(Response.new(200))
        :append_body(expected_body)
      for chunk in res:as_source() do
        assert(server:send(chunk))
      end
    end, 'server task')
    cosock.spawn(function()
      client:setpeername(server_ip, server_port)
      local r = assert(Request.new('GET', '/'))
        :append_body(expected_body)
      for chunk in r:as_source() do
        assert(client:send(chunk))
      end
      local res = assert(Response.source(utils.udp_socket_source(client)))
      assert.are.equal(200, res.status)
      assert.are.equal(expected_body, res:get_body())
    end, 'client task')
    cosock.run()
  end)
end)
