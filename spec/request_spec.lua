local r = require 'luncheon.request'
local Request = r.Request
local parse_preamble = r.testable.parse_preamble
local MockSocket = require 'spec.mock_socket'.MockSocket
local normal_headers = require 'spec.normal_headers'

describe('Request', function()
    describe('parse_preamble', function()
        it('GET / HTTP/1.1 should work', function()
            local r, e = parse_preamble('GET / HTTP/1.1')
            assert(e == nil)
            assert(r.method == 'GET')
            assert(r.url.path == '/')
            assert(r.http_version == '1.1')
        end)
        it('GET /things HTTP/2 should work', function()
            local r, e = parse_preamble('GET /things HTTP/2')
            assert(r.method == 'GET', 'expected method to be GET')
            assert(r.url.path == '/things', 'expected path to be /things')
            assert(r.http_version == '2', 'expected version to be 2')
        end)
        it('POST /stuff HTTP/2 should work', function()
            local r, e = parse_preamble('POST /stuff HTTP/2')
            assert(r.method == 'POST', 'expected method to be POST')
            assert(r.url.path == '/stuff', 'expected path to be /stuff')
            assert(r.http_version == '2', 'expected version to be 2')
        end)
        it('bad request', function()
            local _, e = pcall(parse_preamble, '')
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
            local r, e = Request.new(MockSocket.new(inner))
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
    end)
    describe('Request.body', function()
        it('_fill_body', function()
            local lines = {
                'POST / HTTP/1.1 should work',
                'Content-Length: 4',
                '',
                'asdfg',
            }
            local r, e = Request.new(MockSocket.new(lines))
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
            local r, e = Request.new(MockSocket.new(lines))
            assert(e == nil, 'error parsing preamble ' .. (e or 'nil'))
            local b, e2 = r:get_body()
            assert(e2 == nil, 'error parsing body: ' .. (e2 or 'nil'))
            assert(b == 'asdfg', 'Expected asdfg, found ' .. (r._body or 'nil'))
        end)
    end)
end)
