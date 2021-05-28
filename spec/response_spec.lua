local MockSocket = require 'spec.mock_socket'.MockSocket
local Response = require 'luncheon.response'
local ltn12 = require('ltn12')

describe('Response', function()
    describe('parse_preamble', function()
        it('HTTP/1.1 200 Ok should work', function()
            local r, e = Response.parse_preamble('HTTP/1.1 200 Ok')
            assert(e == nil)
            assert.are.equal(r.status, 200)
            assert.are.equal(r.status_msg, 'Ok')
            assert(r.http_version == 1.1)
        end)
    end)
    it('should send some stuff', function()
        local sock = MockSocket.new()
        local r = Response.outgoing(sock)
        r:send()
        local res = assert(sock.inner[1], 'nothing was sent')
        assert(string.find(res, '^HTTP/1.1 200 OK'), 'Didn\'t contain HTTP preamble')
        assert(string.find(res, 'Content-Length: 0', 0, true), 'expected content length ' .. res)
    end)
    it('should send the right status', function()
        local sock = MockSocket.new()
        local r = Response.outgoing(sock):status(500)
        r:send()
        local res = assert(sock.inner[1], 'nothing was sent')
        assert(string.find(res, '^HTTP/1.1 500 Internal Server Error'), 'expected 500, found ' .. res)
    end)
    it('should send the right default content type/length', function()
        local sock = MockSocket.new()
        local r = Response.outgoing(sock)
        r:send('body')
        local res = assert(sock.inner[1], 'nothing was sent')
        assert(string.find(res, 'Content-Type: text/plain', 0, true), 'expected text/plain ' .. res)
        assert(string.find(res, 'Content-Length: 4', 0, true), 'expected length to be 4 ' .. res)
    end)
    it('should send the right explicit content type', function()
        local sock = MockSocket.new()
        local r = Response.outgoing(sock):content_type('application/json')
        r:send('body')
        local res = assert(sock.inner[1], 'nothing was sent')
        assert(string.find(res, 'Content-Type: application/json', 0, true), 'expected application/json ' .. res)
    end)
    it('should retry on error', function()
        local sock = MockSocket.new()
        local r = Response.outgoing(sock):content_type('application/json')
        r:send('panic')
        local res = assert(sock.inner[1], 'nothing was sent')
        assert(string.find(res, 'Content-Type: application/json', 0, true), 'expected application/json ' .. res)
    end)
    describe('has_sent', function()
        it('should work as expected with normal usage', function()
            local sock = MockSocket.new()
            local r = Response.outgoing(sock)
            r:send('body')
            assert(r:has_sent(), 'expected that `send` would actually send...')
        end)
        it('should work as expected with direct socket usage', function()
            local sock = MockSocket.new()
            local r = Response.outgoing(sock)
            r._outgoing:send('body')
            assert(r:has_sent(), 'expected that `outgoing:send` would actually send...')
        end)
        it('true should be cached', function()
            local sock = MockSocket.new()
            local s = spy.on(sock, 'getstats')
            local r = Response.outgoing(sock)
            r._outgoing:send('body')
            assert(r:has_sent())
            assert(r:has_sent())
            assert.spy(s).was.called(1)
        end)
        it('false should not be cached', function()
            local sock = MockSocket.new()
            local s = spy.on(sock, 'getstats')
            local r = Response.outgoing(sock)
            assert(not r:has_sent())
            assert(not r:has_sent())
            assert.spy(s).was.called(2)
        end)
    end)
    describe('buffered mode', function()
        it('should handle buffering with 1 chunk', function()
            local sock = MockSocket.new()
            local r = Response.outgoing(sock)
            local s = spy.on(sock, 'send')
            r._send_buffer_size = 10
            r:append_body('1234567890')
            r:send()
            assert.spy(s).was.called(1)
            assert(r.body == '')
            assert(sock.inner[1] == 'HTTP/1.1 200 OK\r\n\r\n'..'1234567890', string.format('unexpected socket content, %s', sock.inner[1]))
        end)
        it('should handle buffering with many chunks', function()
            local sock = MockSocket.new()
            local r = Response.outgoing(sock)
            local s = spy.on(sock, 'send')
            r:set_send_buffer_size(10)
            for i = 1, 20, 1 do
                r:append_body('12345')
                if i % 2 == 0 then
                    assert(r.body == '', string.format('expected empty body found %s', r.body))
                    if i == 2 then
                        assert(sock.inner[1] == 'HTTP/1.1 200 OK\r\n\r\n'..'1234512345')
                    else
                        assert(sock.inner[#sock.inner] == '1234512345', string.format('%i, unexpected socket content, %s', i, table.concat(sock.inner, '\n')))
                    end
                else
                    assert(r.body == '12345', string.format('expected 12345 found %s', r.body))
                end
            end
            
            r:send()
            assert.spy(s).was.called(10)
            assert(r.body == '')
        end)
        -- it('sink should work as expected: short', function()
        --     local sock = MockSocket.new()
        --     local r = Response.new(sock)
        --     r:set_send_buffer_size(10)
        --     local body = 'This is the body of a Response, please send all of these bytes to the socket'
        --     ltn12.pump.all(
        --         ltn12.source.string(body),
        --         r:sink()
        --     )
            
        --     assert(sock.inner[1] == 'HTTP/1.1 200 OK\r\n\r\n'..body, string.format('unexpected body, found %s', sock.inner[1] or table.concat(sock.inner, '\n')))
        -- end)
        -- it('sink should work as expected: long', function()
        --     local sock = MockSocket.new()
        --     local r = Response.new(sock)
        --     r:set_send_buffer_size(10)
        --     local body = [[Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium
        --     doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et
        --     quasi architecto beatae vitae dicta sunt explicabo. Nemo enim ipsam voluptatem quia voluptas
        --     sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos qui ratione
        --     voluptatem sequi nesciunt. Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet,
        --     consectetur, adipisci velit, sed quia non numquam eius modi tempora incidunt ut labore et
        --     dolore magnam aliquam quaerat voluptatem. Ut enim ad minima veniam, quis nostrum exercitationem
        --     ullam corporis suscipit laboriosam, nisi ut aliquid ex ea commodi consequatur? Quis autem vel
        --     eum iure reprehenderit qui in ea voluptate velit esse quam nihil molestiae consequatur, vel
        --     illum qui dolorem eum fugiat quo voluptas nulla pariatur?]]
        --     for _ = 1, 10, 1 do
        --         body = body .. body
        --     end
        --     ltn12.pump.all(
        --         ltn12.source.string(body),
        --         r:sink()
        --     )
        --     assert(table.concat(sock.inner, '') == 'HTTP/1.1 200 OK\r\n\r\n'..body, string.format('unexpected body, found %s', sock.inner[1]))
        -- end)
    end)
    describe('status', function ()
        it('as number', function ()
            local sock = MockSocket.new()
            local r = Response.outgoing(sock)
            r:status(200)
            assert(r._status == 200)
        end)
        it('as string', function ()
            local sock = MockSocket.new()
            local r = Response.outgoing(sock)
            r:status('200')
            assert(r._status == 200)
        end)
        it('as table', function ()
            local sock = MockSocket.new()
            local r = Response.outgoing(sock)
            local _, err = r:status({})
            assert(err)
        end)
    end)
    describe('send failures', function ()
        it('timeouts', function ()
            local sock = MockSocket.new()
            local r = Response.outgoing(sock)
            r:set_send_buffer_size(7)
            local s = pcall(r.append_body, r, '       ')
            assert(s)
            local s = pcall(r.append_body, r, 'timeout')
            assert(s)
            local s = pcall(r.append_body, r, 'timeout')
            assert(s)
            local s = pcall(r.append_body, r, 'timeout')
            assert(s)
            local s = pcall(r.append_body, r, 'timeout')
            assert(s)
            assert(sock.inner[1] == sock.inner[1]:gsub('timeout', ''))
        end)
        it('closed', function ()
            local sock = MockSocket.new()
            local r = Response.outgoing(sock)
            r:set_send_buffer_size(6)
            local s1, err = assert(r:append_body('       '))
            -- assert(s1, string.format('%q %q', s1, err))
            local s2, err = r:append_body('closed')
            assert(not s2, string.format("%q", s2))
            assert(err == 'Attempt to send on closed socket', string.format('%s', err))
            assert(sock.inner[1] == sock.inner[1]:gsub('closed', ''))
        end)
    end)
    it('content_type table fails', function ()
        local r = Response.outgoing(MockSocket.new())
        local _, err = r:content_type({})
        assert.is.equal('mime type must be a string, found table', err)
    end)
    it('content_length table fails', function ()
        local r = Response.outgoing(MockSocket.new())
        local _, err = r:content_length({})
        assert.is.equal('content length must be a number, found table', err)
    end)
    it('source works', function ()
        local r = Response.outgoing(MockSocket.new())
        r:content_type('application/json')
        r.headers.last_key = 'junk'
        local lines = {
            'HTTP/1.1 200 OK\r\n',
            'Content-Type: application/json\r\n',
            '\r\n',
            ''
        }
        local idx = 1
        for line in r:source() do
            assert.is.equal(lines[idx], line)
            idx = idx + 1
        end
    end)
    it('nested source works', function ()
        local r = Response.outgoing(MockSocket.new({}))
        r:content_type('application/json')
        r.headers.last_key = 'junk'
        r.body = function() return function () end end
        local lines = {
            'HTTP/1.1 200 OK\r\n',
            'Content-Type: application/json\r\n',
            '\r\n',
            ''
        }
        local idx = 1
        for line in r:source() do
            assert.is.equal(lines[idx], line)
            idx = idx + 1
        end
    end)
    it('can close', function ()
        local r = assert(Response.outgoing(MockSocket.new()))
        assert(r:close())
    end)
    it('incoming will construct', function ()
        local r = assert(Response.incoming(MockSocket.new({'HTTP/1.1 200 Ok'})))
    end)
    it('incoming source', function ()
        local expected = {
            'HTTP/1.1 200 OK',
            'Content-Length: 4',
            '',
            'asdf'
        }
        local r = assert(Response.incoming(MockSocket.new({
            'HTTP/1.1 200 OK',
            'Content-Length: 4',
            '',
            'asdf'
        })))
        local idx = 1
        for line in r:source() do
            assert.is_equal(expected[idx], line)
            idx = idx + 1
        end
    end)
    it('Response.incoming fails with empty socket', function ()
        local r, err = Response.incoming(MockSocket.new({}))
        assert.is.falsy(r)
        assert.are.equal('empty', err)
    end)
    it('Response.incoming fails with bad pre', function ()
        local r, err = Response.incoming(MockSocket.new({'junk'}))
        assert.is.falsy(r)
        assert.are.equal('invalid preamble: "junk"', err)
    end)
end)
