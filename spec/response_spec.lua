local MockSocket = require 'spec.mock_socket'.MockSocket
local Response = require 'luncheon.response'
local ltn12 = require('ltn12')
local utils = require 'luncheon.utils'

describe('Response', function()
    describe('parse_preamble', function()
        it('HTTP/1.1 200 Ok should work', function()
            local r, e = Response._parse_preamble('HTTP/1.1 200 Ok')
            assert(e == nil)
            assert.are.equal(r.status, 200)
            assert.are.equal(r.status_msg, 'Ok')
            assert(r.http_version == 1.1)
        end)
    end)
    describe('set_status', function ()
        it('as number', function ()
            local r = Response.new()
            r:set_status(200)
            assert(r.status == 200)
        end)
        it('as string', function ()
            local r = Response.new()
            r:set_status('200')
            assert(r.status == 200)
        end)
        it('as table', function ()
            local r = Response.new(200)
            local _, err = r:set_status({})
            assert(err)
        end)
        it('new table', function ()
            local r, err = Response.new({})
            assert.is.equal(err, 'Invalid status code table')
        end)
    end)
    it('content_type string', function ()
        local r = Response.new(200)
        local _, err = r:set_content_type('application/json')
        assert.is.falsy(err)
        assert.is.equal('application/json', r:get_headers():get_one('content_type'))
    end)
    it('content_type table fails', function ()
        local r = Response.new(200)
        local _, err = r:set_content_type({})
        assert.is.equal('mime type must be a string, found table', err)
    end)
    it('content_length table fails', function ()
        local r = Response.new(200)
        local _, err = r:set_content_length({})
        assert.is.equal('content length must be a number, found table', err)
    end)
    it('seralize works', function ()
        local r = Response.new(200)
        assert(r:append_body('this is a body'))
        assert.is.equal(table.concat({
            'HTTP/1.1 200 OK\r\n',
            'Content-Length: 14\r\n',
            '\r\n',
            'this is a body'
        }), r:serialize())
    end)
    it('source will construct', function ()
        local r = assert(Response.source(utils.tcp_socket_source(MockSocket.new({'HTTP/1.1 200 Ok'}))))
    end)
    it('Response.source fails with empty socket', function ()
        local r, err = Response.source(utils.tcp_socket_source(MockSocket.new({})))
        assert.is.falsy(r)
        assert.are.equal('empty', err)
    end)
    it('Response.source fails with bad pre', function ()
        local r, err = Response.source(utils.tcp_socket_source(MockSocket.new({'junk'})))
        assert.is.falsy(r)
        assert.are.equal('invalid preamble: "junk"', err)
    end)
    it('Response.new cannot recv', function ()
        local r = assert(Response.new(200))
        local _, err = r:next_line()
        assert.are.equal('nil source', err)
    end)
    it('Response:get_content_length twice', function ()
        local r = assert(Response.source(utils.tcp_socket_source(MockSocket.new({
            'HTTP/1.1 200 OK',
            'Content-Length: 1',
            '',
            '1'
        }))))
        local len1 = assert(r:get_content_length())
        local len2 = assert(r:get_content_length())
        assert.are.equal(len1, len2)
    end)
    it('Response:get_content_length no header', function ()
        local r = assert(Response.source(utils.tcp_socket_source(MockSocket.new({
            'HTTP/1.1 200 OK',
            '',
            '1'
        }))))
        local len, err = r:get_content_length()
        assert(not len)
        assert(not err)
    end)
    it('Response:get_content_length bad header', function ()
        local r = assert(Response.source(utils.tcp_socket_source(MockSocket.new({
            'HTTP/1.1 200 OK',
            'Content-Length: Q',
            '',
            '1'
        }))))
        local len, err = r:get_content_length()
        assert(not len)
        assert.are.equal('bad Content-Length header', err)
    end)
    it('Response:get_headers', function ()
        local r = assert(Response.source(utils.tcp_socket_source(MockSocket.new({
            'HTTP/1.1 200 OK',
            'Content-Length: 1',
            '',
            '1'
        }))))
        local headers = assert(r:get_headers())
        assert.are.equal('1', headers:get_one('content_length'))
    end)
    it('Response:_fill_body bad content-length', function ()
        local r = assert(Response.source(utils.tcp_socket_source(MockSocket.new({
            'HTTP/1.1 200 OK',
            'Content-Length: Q',
            '',
            '1'
        }))))
        local err = r:_fill_body()
        assert.are.equal('bad Content-Length header', err)
    end)
    it('Response:serialize', function ()
        local r = assert(Response.source(utils.tcp_socket_source(MockSocket.new({
            'HTTP/1.1 200 OK',
            'Content-Length: 1',
            '',
            '1'
        }))))
        local headers = assert(r:get_headers())
        assert.are.equal('1', headers:get_one('content_length'))
    end)
    it('Response error socket', function ()
        local r = assert(Response.source(utils.tcp_socket_source(MockSocket.new({
            'HTTP/1.1 200 OK\r\n',
            'Content-Length: 10\r\n',
            '\r\n',
            'timeout'
        }))))
        local body, err = r:get_body()
        assert.is.falsy(body)
        assert.are.equal('empty', err)
    end)
    it('Response error socket', function ()
        local r = assert(Response.source(utils.tcp_socket_source(MockSocket.new({
            'HTTP/1.1 200 OK\r\n',
            'Content-Length: 10\r\n',
            'timeout'
        }))))
        local headers, err = r:get_headers()
        assert.is.falsy(headers)
        assert.are.equal('timeout', err)
    end)
    it('Response:add_header non-strings', function ()
        local t = {}
        local f = function () end
        local r = assert(Response.new())
            :add_header('X-Integer-Value', 1)
            :add_header('X-Number-Value', 1.1)
            :add_header('X-Table-Value', t)
            :add_header('X-Function-Value', f)
            :add_header('X-Boolean-Value', true)
        assert.are.equal('1', r.headers:get_one('x_integer_value'))
        assert.are.equal('1.1', r.headers:get_one('x_number_value'))
        assert.are.equal(tostring(t), r.headers:get_one('x_table_value'))
        assert.are.equal(tostring(f), r.headers:get_one('x_function_value'))
        assert.are.equal(tostring(true), r.headers:get_one('x_boolean_value'))
    end)
    it('Response:as_source multi-line body', function ()
        local r = assert(Response.new())
            :append_body('First Line\n')
            :append_body('Second Line')
        local ct = 1
        local expected_lines = {
            'HTTP/1.1 200 OK\r\n',
            'Content-Length: 22\r\n',
            '\r\n',
            'First Line\n',
            'Second Line',
        }
        for line in r:as_source() do
            assert.are.equal(expected_lines[ct], line)
            ct = ct + 1
        end
    end)
end)
