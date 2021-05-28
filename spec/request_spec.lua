local Request = require 'luncheon.request'
local MockSocket = require 'spec.mock_socket'.MockSocket
local normal_headers = require 'spec.normal_headers'

describe('Request', function()
    describe('parse_preamble', function()
        it('GET / HTTP/1.1 should work', function()
            local r, e = Request._parse_preamble('GET / HTTP/1.1')
            assert(e == nil)
            assert(r.method == 'GET')
            assert(r.url.path == '/')
            assert(r.http_version == '1.1')
        end)
        it('GET /things HTTP/2 should work', function()
            local r, e = Request._parse_preamble('GET /things HTTP/2')
            assert(r.method == 'GET', 'expected method to be GET')
            assert(r.url.path == '/things', 'expected path to be /things')
            assert(r.http_version == '2', 'expected version to be 2')
        end)
        it('POST /stuff HTTP/2 should work', function()
            local r, e = Request._parse_preamble('POST /stuff HTTP/2')
            assert(r.method == 'POST', 'expected method to be POST')
            assert(r.url.path == '/stuff', 'expected path to be /stuff')
            assert(r.http_version == '2', 'expected version to be 2')
        end)
        it('bad request', function()
            local _, e = Request._parse_preamble('')
            assert(e)
        end)
    end)
    describe('Request.headers', function ()
        it('works', function ()
            local inner = {'GET / HTTP/1.1 should work'}
            for _, set in ipairs(normal_headers) do
                table.insert(inner, set[1])
            end
            table.insert(inner, '')
            local r, e = Request.from_socket(MockSocket.new(inner))
            assert(e == nil, string.format('error in Request.from: %s', e))
            local headers, e2 = r:get_headers()
            assert(e2 == nil, string.format('error in get_headers %s', e2))
            assert(headers, string.format('headers was nil'))
            for _, set in ipairs(normal_headers) do
                local key = set[2]
                local expected = set[3]
                assert(headers[key] == expected, string.format('%s, found %s expected %s', key, headers[key], expected))
            end
        end)
        it('fails with no headers', function ()
            local inner = {'GET / HTTP/1.1 should work'}
            local r, e = Request.from_socket(MockSocket.new(inner))
            assert(r)
            assert(not e, string.format('expected no error found %q', e))
            local headers, e2 = r:get_headers()
            assert.is.equal(e2, 'empty')
        end)
    end)
    describe('Request.body', function()
        it('_fill_body', function()
            local lines = {
                'POST / HTTP/1.1 should work',
                'Content-Length: 4',
                '',
                'asdfg',
            }
            local r, e = Request.from_socket(MockSocket.new(lines))
            assert(e == nil, 'error parsing preamble ' .. (e or 'nil'))
            local e2 = r:_fill_body()
            assert(e2 == nil, 'error parsing body: ' .. (e2 or 'nil'))
            assert(r._body == 'asdfg', 'Expected asdfg, found ' .. (r._body or 'nil'))
        end)
        it('get_body', function()
            local lines = {
                'POST / HTTP/1.1 should work',
                'Content-Length: 4',
                '',
                'asdfg',
            }
            local r, e = Request.from_socket(MockSocket.new(lines))
            assert(e == nil, 'error parsing preamble ' .. (e or 'nil'))
            local b, e2 = r:get_body()
            assert(e2 == nil, 'error parsing body: ' .. (e2 or 'nil'))
            assert(b == 'asdfg', 'Expected asdfg, found ' .. (r._body or 'nil'))
        end)
        it('get_body fails', function()
            local lines = {
                'POST / HTTP/1.1 should work',
            }
            local r, e = Request.from_socket(MockSocket.new(lines))
            assert.is.falsy(e)
            local b, e2 = r:get_body()
            assert.is.falsy(b)
            assert.is.equal('empty', e2)
        end)
    end)
    describe('Manual Construction', function ()
        it('serialize works', function ()
            local r = Request.new('GET', '/'):set_content_type('application/json'):set_body('{}')
            local expected_lines = {
                'GET / HTTP/1.1\r\n',
                'Content-Type: application/json\r\n',
                'Content-Length: 2\r\n',
                '\r\n',
                '{}',
            }
            local ser = r:serialize()
            local idx = 1
            for l in string.gmatch(ser, '[^\r\n]*\r?\n?') do
                if idx > 1 and idx < 4 then
                    assert(l == expected_lines[2] or l == expected_lines[3])
                else
                    assert.are_equal(l, expected_lines[idx])
                end
                idx = idx + 1
            end
        end)
        it('source works in a loop string body', function ()
            local r = Request.new('GET', '/'):set_content_type('application/json'):set_body('{}')
            local expected_lines = {
                'GET / HTTP/1.1\r\n',
                'Content-Type: application/json\r\n',
                'Content-Length: 2\r\n',
                '\r\n',
                '{}',
            }
            local line_n = 1
            for line in r:source() do
                if line_n > 1 and line_n < 4 then
                    assert(line == expected_lines[2] or line == expected_lines[3])
                else
                    assert.is_equal(line, expected_lines[line_n])
                end
                line_n = line_n + 1
            end
        end)
        it('source works in a loop fn body', function ()
            local r = Request.new('GET', '/'):set_content_type('application/json'):set_body(function()
                local lines = {
                    'three',
                    'two',
                    'one',
                }
                return function ()
                    return table.remove(lines)
                end
            end, 11)
            local expected_lines = {
                'GET / HTTP/1.1\r\n',
                'Content-Length: 11\r\n',
                'Content-Type: application/json\r\n',
                '\r\n',
                'one',
                'two',
                'three',
            }
            local line_n = 1
            for line in r:source() do
                if line_n > 1 and line_n < 4 then
                    assert(line == expected_lines[2] or line == expected_lines[3])
                else
                    assert.is_equal(line, expected_lines[line_n])
                end
                line_n = line_n + 1
            end
        end)
        it('serialize_path works', function ()
            local path_str = '/endpoint?asdf=2&qwer=3'
            local r = Request.new('GET', path_str)
            assert.are.equal(r:_serialize_path(), path_str)
            r.url = path_str
            assert.are.equal(r:_serialize_path(), path_str)
        end)
    end)
end)
