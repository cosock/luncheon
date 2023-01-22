local MockSocket = require 'spec.mock_socket'.MockSocket
local Response = require 'luncheon.response'
local ltn12 = require('ltn12')
local utils = require 'luncheon.utils'
local shared= require 'luncheon.shared'

describe('Response', function()
    describe('parse_preamble', function()
        it('HTTP/1.1 200 Ok should work', function()
            local r = assert(Response._parse_preamble('HTTP/1.1 200 Ok'))
            assert.are.equal(r.status, 200)
            assert.are.equal(r.status_msg, 'Ok')
            assert(r.http_version == 1.1)
        end)
    end)
    describe('set_status', function ()
        it('as number', function ()
            local r = assert(Response.new())
            r:set_status(200)
            assert(r.status == 200)
        end)
        it('as string', function ()
            local r = assert(Response.new())
            r:set_status('200')
            assert(r.status == 200)
        end)
        it('as table', function ()
            local r = assert(Response.new(200))
---@diagnostic disable-next-line: param-type-mismatch
            local _, err = r:set_status({})
            assert(err)
        end)
        it('new table', function ()
---@diagnostic disable-next-line: param-type-mismatch
            local r, err = Response.new({})
            assert.is.equal(err, 'Invalid status code table')
        end)
    end)
    it('content_type string', function ()
        local r = assert(Response.new(200))
        local _, err = r:set_content_type('application/json')
        assert.is.falsy(err)
        assert.is.equal('application/json', r:get_headers():get_one('content_type'))
    end)
    it('content_type table fails', function ()
        local r = assert(Response.new(200))
---@diagnostic disable-next-line: param-type-mismatch
        local _, err = r:set_content_type({})
        assert.is.equal('mime type must be a string, found table', err)
    end)
    it('content_length table fails', function ()
        local r = assert(Response.new(200))
---@diagnostic disable-next-line: param-type-mismatch
        local _, err = r:set_content_length({})
        assert.is.equal('content length must be a number, found table', err)
    end)
    it('add_header calls tostring with non-string', function()
        local r = Response.new(200)
            :add_header("some key", 1)

        assert.are.same("1", r:get_headers():get_one("some key"))
    end)
    it('replace_header calls tostring with non-string', function()
        local r = Response.new(200)
            :replace_header("some key", 1)

        assert.are.same("1", r:get_headers():get_one("some key"))
    end)
    it("set_content_type errors with non string", function()
        local r = Response.new(200)
        local _, err = r:set_content_type(1)
        assert.are.same("mime type must be a string, found number", err)
    end)
    it('seralize works', function ()
        local r = assert(Response.new(200))
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
        assert.are.equal('Invalid http response first line: "junk"', err)
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
        local err = shared.SharedLogic.fill_body(r)
        assert.are.equal('bad Content-Length header', err)
    end)
    it('Response:serialize', function()
        local response_table = {
            'HTTP/1.1 200 OK',
            'Content-Length: 1',
            '',
            '1'
        }
        local response_text = table.concat(response_table, '\r\n')
        local r = assert(Response.source(utils.tcp_socket_source(MockSocket.new(response_table))))
        local headers = assert(r:get_headers())
        assert.are.equal('1', headers:get_one('content_length'))
        local res = assert(r:serialize())
        assert.are.equal(response_text, res)
    end)
    it('Response error socket #target', function ()
        local r = assert(Response.source(utils.tcp_socket_source(MockSocket.new({
            'HTTP/1.1 200 OK\r\n',
            'Content-Length: 10\r\n',
            '\r\n',
            'timeout'
        }))))
        local body, err = r:get_body()
        assert.is.falsy(body)
        assert.are.equal('timeout', err)
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
    it('Response:iter multi-line body', function ()
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
        for line in r:iter() do
            assert.are.equal(expected_lines[ct], line)
            ct = ct + 1
        end
    end)
    describe('sink', function()
        it('can send', function()
            local socket = MockSocket.new()
            local r = assert(Response.new(200, socket))
            r:send('body')
            local all_sent = table.concat(socket.inner, "")
            assert.are.equal('HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nbody', all_sent)
        end)
        it('can send large payload #v', function()
            local socket = MockSocket.new()
            local r = assert(Response.new(200, socket))
            local expected = "HTTP/1.1 200 OK\r\nContent-Length: 4096\r\n\r\n"
            local body = string.rep('a', 4096)
            expected = expected .. body
            r:send(body)
            local all_sent = table.concat(socket.inner, "")
            assert.are.equal(#expected, #all_sent)
        end)
        it('does not duplicate preamble', function()
            local socket = MockSocket.new()
            local r = assert(Response.new(200, socket))
            r:send_preamble()
            r:send_preamble()
            assert.are.equal('HTTP/1.1 200 OK\r\n', socket.inner[1])
            assert.are.equal(1, #socket.inner)
        end)
        it('send_preamble forwards errors', function()
            local socket = MockSocket.new({}, {'error'})
            local r = assert(Response.new(200, socket))
            local s, e = r:send_preamble()
            assert.is.falsy(s)
            assert.are.equal('error', e)
        end)
        it('send_header forwards errors', function()
            local socket = MockSocket.new({}, {})
            local r = assert(Response.new(200, socket))
            assert(r:send_preamble())
            table.insert(socket.send_errs, 'error')
            local s, e = r:send_header()
            assert.is.falsy(s)
            assert.are.equal('error', e)
        end)
        it('send_header forwards errors deeper', function()
            local socket = MockSocket.new({}, {})
            local r = Response.new(200, socket):add_header('X-A-Header', 'yes')
            assert(r:send_preamble())
            table.insert(socket.send_errs, 'error')
            local s, e = r:send_header()
            assert.is.falsy(s)
            assert.are.equal('error', e)
        end)
        it('cannot send headers after body', function()
            local socket = MockSocket.new({}, {})
            local r = assert(Response.new(200, socket))
            assert(r:send('asdf'))
            local s, e = r:send_header()
            assert.is.falsy(s)
            assert.are.equal('cannot send headers after body', e)
        end)
        it('send_body_chunk forwards errors', function()
            local socket = MockSocket.new({}, {})
            local r = Response.new(200, socket):add_header('X-A-Header', 'yes')
                :append_body('asdf')
            assert(r:send_preamble())
            assert(r:send_header())
            assert(r:send_header())
            assert(r:send_header())
            table.insert(socket.send_errs, 'error')
            local s, e = r:send_body_chunk()
            assert.is.falsy(s)
            assert.are.equal('error', e)
        end)
        it('send forwards errors', function()
            local socket = MockSocket.new({}, {'error'})
            local s, e = Response.new(200, socket):send('asdf')
            assert.is.falsy(s)
            assert.are.equal('error', e)
        end)
        it('has_sent', function()
            local socket = MockSocket.new({}, {})
            local res = assert(Response.new(200, socket))
            res:send('asdf')
            assert(res:has_sent())
        end)
    end)
    describe("Response.*_source", function()
        it("tcp source works", function()
            assert(Response.tcp_source(MockSocket.new({ "HTTP/1.1 200 Ok\r\n" })))
        end)
        it("udp source works", function()
            assert(Response.udp_source(MockSocket.new({ "HTTP/1.1 200 Ok\r\n" })))
        end)
        it("tcp error bad preamble", function()
            local _, err = Response.tcp_source(MockSocket.new({ "junk" }))
            assert.are.same("Invalid http response first line: \"junk\"", err)
        end)
        it("udp error bad preamble", function()
            local _, err = Response.udp_source(MockSocket.new({ "junk" }))
            assert.are.same("empty", err)
        end)
    end)
    describe("chunk encoding #enc", function()
        local test_utils = require "spec.test_utils"
        it("get_body works", function()
            local r = assert(Response.source(test_utils.create_chunked_source(test_utils.wikipedia_chunks.response)))
            local b = assert(r:get_body())
            assert.are.equal(test_utils.wikipedia_chunks.assert_body, b or nil)
        end)
        it("large chunks works", function()
            local r = assert(Response.source(test_utils.create_chunked_source(test_utils.large_chunks.response)))
            local b = assert(r:get_body())
            assert.are.equal(test_utils.large_chunks.assert_body, b or nil)
        end)
        it("iter works", function()
            local r = assert(Response.source(test_utils.create_chunked_source(test_utils.wikipedia_chunks.response)))
            local iter = r:iter()
            assert.are.same("HTTP/1.1 200 OK\r\n", iter())
            assert.are.same("Transfer-Encoding: chunked\r\n", iter())
            assert.are.same("\r\n", iter())
            assert.are.same("Wiki", iter())
            assert.are.same("pedia ", iter())
            assert.are.same("in \r\n\r\nchunks.", iter())
        end)
        it("extensions works", function()
            local r = assert(Response.source(test_utils.create_chunked_source(test_utils.extended.response)))
            local b = assert(r:get_body())
            assert.are.equal(test_utils.extended.assert_body, b or nil)
        end)
        it("trailers works", function()
            local r = assert(Response.source(test_utils.create_chunked_source(test_utils.trailers.response)))
            local headers = assert(r:get_headers())
            assert.are.equal(nil, headers:get_one("Date") or nil)
            local b = assert(r:get_body())
            assert.are.equal(test_utils.trailers.assert_body, b or nil)
            assert.are.equal("Today", r.trailers:get_one("Date") or nil)
        end)
        it("iter works with trailers", function()
            local r = assert(Response.source(test_utils.create_chunked_source(test_utils.trailers.response)))
            local iter = r:iter()
            assert.are.same("HTTP/1.1 200 OK\r\n", iter())

            local header_set = {
                ["Trailer: Date,Junk\r\n"] = true,
                ["Transfer-Encoding: chunked\r\n"] = true
            }
            local header1 = assert(iter())
            test_utils.assert_in_set(header_set, header1)
            -- assert(header_set[header1], string.format("Expected header1 to be Trailers or Junk found %q", header1))
            -- header_set[header1] = nil
            local header2 = assert(iter())
            test_utils.assert_in_set(header_set, header2)
            -- assert(header_set[header2], string.format("Expected header2 to be Trailers or Junk found %q", header2))
            -- header_set[header2] = nil
            assert.are.same("\r\n", iter())
            assert.are.same("the message will have extra headers", iter())
            assert.are.same("after it", iter())
            local trailer_set = {
                ["Date: Today\r\n"] = true,
                ["Junk: This is a junk header!\r\n"] = true
            }
            local trailer1 = assert(iter())
            test_utils.assert_in_set(trailer_set, trailer1)
            local trailer2 = assert(iter())
            test_utils.assert_in_set(trailer_set, trailer2)
        end)
    end)
end)
