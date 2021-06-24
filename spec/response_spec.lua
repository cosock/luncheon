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
    end)
    it('content_type table fails', function ()
        local r = Response.new(200)
        local _, err = r:content_type({})
        assert.is.equal('mime type must be a string, found table', err)
    end)
    it('content_length table fails', function ()
        local r = Response.new(200)
        local _, err = r:content_length({})
        assert.is.equal('content length must be a number, found table', err)
    end)
    it('source will construct', function ()
        local r = assert(Response.source(utils.tcp_socket_source(MockSocket.new({'HTTP/1.1 200 Ok'}))))
    end)
    it('Response.incoming fails with empty socket', function ()
        local r, err = Response.source(utils.tcp_socket_source(MockSocket.new({})))
        assert.is.falsy(r)
        assert.are.equal('empty', err)
    end)
    it('Response.incoming fails with bad pre', function ()
        local r, err = Response.source(utils.tcp_socket_source(MockSocket.new({'junk'})))
        assert.is.falsy(r)
        assert.are.equal('invalid preamble: "junk"', err)
    end)
    it('Response.outgoing cannot recv', function ()
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
        assert.are.equal('no content length header', err)
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
end)
