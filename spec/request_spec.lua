local Request = require "luncheon.request"
local MockSocket = require "spec.mock_socket".MockSocket
local normal_headers = require "spec.normal_headers"
local utils = require "luncheon.utils"
local shared = require "luncheon.shared"

describe("Request", function()
  describe("parse_preamble", function()
    it("GET / HTTP/1.1 should work", function()
      local r = assert(Request._parse_preamble("GET / HTTP/1.1"))
      assert.are.equal("GET", r.method)
      assert.are.equal("/", r.url.path)
      assert.are.equal("1.1", r.http_version)
    end)
    it("GET /things HTTP/2 should work", function()
      local r = assert(Request._parse_preamble("GET /things HTTP/2"))
      assert.are.equal("GET", r.method)
      assert.are.equal("/things", r.url.path)
      assert.are.equal("2", r.http_version)
    end)
    it("POST /stuff HTTP/2 should work", function()
      local r = assert(Request._parse_preamble("POST /stuff HTTP/2"))
      assert.are.equal("POST", r.method)
      assert.are.equal("/stuff", r.url.path)
      assert.are.equal("2", r.http_version)
    end)
    it("bad request", function()
      local _, e = Request._parse_preamble("")
      assert(e)
    end)
  end)
  describe("Request.headers", function()
    it("works", function()
      local inner = { "GET / HTTP/1.1 should work" }
      for _, set in ipairs(normal_headers) do
        table.insert(inner, set[1])
      end
      table.insert(inner, "")
      local r = assert(Request.source(utils.tcp_socket_source(MockSocket.new(inner))))
      local headers, e2 = r:get_headers()
      assert(e2 == nil, string.format("error in get_headers %s", e2))
      assert(headers, string.format("headers was nil"))
      for _, set in ipairs(normal_headers) do
        local key = set[2]
        local expected = set[3]
        assert(headers:get_one(key) == expected,
          string.format("%s, found %s expected %s", key, headers:get_one(key), expected))
      end
    end)
    it("fails with no headers", function()
      local inner = { "GET / HTTP/1.1 should work" }
      local r, e = Request.source(utils.tcp_socket_source(MockSocket.new(inner)))
      assert(r)
      assert(not e, string.format("expected no error found %q", e))
      local headers, e2 = r:get_headers()
      assert.is.equal(e2, "empty")
    end)
  end)
  describe("Request.body", function()
    it("_fill_body", function()
      local lines = {
        "POST / HTTP/1.1 should work",
        "Content-Length: 4",
        "",
        "asdfg",
      }
      local r = assert(Request.source(utils.tcp_socket_source(MockSocket.new(lines))))
      local e2 = shared.SharedLogic.fill_body(r)
      assert(e2 == nil, "error parsing body: " .. (e2 or "nil"))
      assert.are.equal("asdfg", r.body)
    end)
    it("get_body", function()
      local lines = {
        "POST / HTTP/1.1 should work",
        "Content-Length: 4",
        "",
        "asdfg",
      }
      local r = assert(Request.source(utils.tcp_socket_source(MockSocket.new(lines))))
      local b = assert(r:get_body())
      assert.are.equal("asdfg", b)
    end)
    it("get_body fails #b", function()
      local lines = {
        "POST / HTTP/1.1 should work",
      }
      local r = assert(Request.source(utils.tcp_socket_source(MockSocket.new(lines))))
      local b, e2 = r:get_body()
      assert.is.falsy(b)
      assert.is.equal("empty", e2)
    end)
    it("content-length nil", function()
      local lines = {
        "POST / HTTP/1.1 should work",
        "",
      }
      local r, e = assert(Request.source(utils.tcp_socket_source(MockSocket.new(lines))))
      assert(not r:get_content_length())
    end)
    it("content-length bad", function()
      local lines = {
        "POST / HTTP/1.1 should work",
        "Content-Length: a",
        ""
      }
      local r = assert(Request.source(utils.tcp_socket_source(MockSocket.new(lines))))
      assert.is.falsy(r:get_content_length())
    end)
  end)
  describe("Manual Construction", function()
    it("add_header calls tostring with non-string", function()
      local r = Request.new("GET", "/")
          :add_header("some key", 1)

      assert.are.same("1", r:get_headers():get_one("some key"))
    end)
    it("replace_header calls tostring with non-string", function()
      local r = Request.new("GET", "/")
          :replace_header("some key", 1)

      assert.are.same("1", r:get_headers():get_one("some key"))
    end)
    it("set_content_type errors with non string", function()
      local r = Request.new("GET", "/")
      local _, err = r:set_content_type(1)
      assert.are.same("mime type must be a string, found number", err)
    end)
    it("serialize works", function()
      local r = assert(Request.new("GET", "/"):set_content_type("application/json")
        :append_body("{}"))
      local ser = assert(r:serialize())
      assert(string.find(ser, "^GET / HTTP/1%.1\r\n"), 'Preamble missing\n"' .. ser .. '"')
      assert(string.find(ser, "Content%-Type: application/json\r\n"),
        'CT missing\n"' .. ser .. '"')
      assert(string.find(ser, "Content%-Length: 2\r\n"), 'CL missing\n"' .. ser .. '"')
      assert(string.find(ser, "\r\n\r\n"), 'headers end missing\n"' .. ser .. '"')
      assert(string.find(ser, "{}$"), 'body missing\n"' .. ser .. '"')
    end)
    it("as_source works in a loop string body", function()
      local r = Request.new("GET", "/"):set_content_type("application/json"):append_body("{}")
      local expected_lines = {
        "GET / HTTP/1.1\r\n",
        "Content-Type: application/json\r\n",
        "Content-Length: 2\r\n",
        "\r\n",
        "{}",
      }
      local line_n = 1
      for line in r:iter() do
        if line_n > 1 and line_n < 4 then
          assert(line == expected_lines[2] or line == expected_lines[3])
        else
          assert.is_equal(line, expected_lines[line_n])
        end
        line_n = line_n + 1
      end
    end)
    it("iter works with a multi-line body", function()
      local r = Request.new("GET", "/"):set_content_type("application/json"):append_body(
            "one\n"
          ):append_body("two\n")
          :append_body("three")
      local expected_lines = {
        "GET / HTTP/1.1\r\n",
        "Content-Length: 13\r\n",
        "Content-Type: application/json\r\n",
        "\r\n",
        "one\n",
        "two\n",
        "three",
      }
      local line_n = 1
      for line in r:iter() do
        if line_n > 1 and line_n < 4 then
          assert(line == expected_lines[2] or line == expected_lines[3],
            string.format("line: %q\n2: %q\n3: %q", line, expected_lines[2],
              expected_lines[3]))
        else
          assert(expected_lines[line_n] == line,
            string.format("%s %q ~= %q", line_n, expected_lines[line_n], line))
        end
        line_n = line_n + 1
      end
    end)
    it("builder serialize works", function()
      local r = Request.new("GET", "/"):append_body(
            "one\n"
          ):append_body("two\n")
          :append_body("three")
      local expected = table.concat({
        "GET / HTTP/1.1\r\n",
        "Content-Length: 13\r\n",
        "\r\n",
        "one\n",
        "two\n",
        "three",
      })
      assert.are.same(expected, r:serialize())
    end)
    it("source serialize works", function()
      local body = "one\ntwo\nthree"
      local lines = {
        "GET / HTTP/1.1",
        string.format("Content-Length: %s", #body),
        "",
        body
      }
      local sock = MockSocket.new(lines)
      local expected = table.concat(lines, "\r\n")
      local r = assert(Request.tcp_source(sock))
      local result = assert(r:serialize())
      assert.are.same(expected
      , result)
    end)
    it("serialize_path works", function()
      local path_str = "/endpoint?asdf=2&qwer=3"
      local r = Request.new("GET", path_str)
      assert.are.equal(r:_serialize_path(), path_str)
      ---@diagnostic disable-next-line: assign-type-mismatch
      r.url = path_str
      assert.are.equal(r:_serialize_path(), path_str)
    end)
    it("set_content_length", function()
      local r = Request.new("GET", "/")
      r.headers.content_length = nil
      assert(r:set_content_length(10))
    end)
  end)
  it("source fails with nil source", function()
    ---@diagnostic disable-next-line: missing-parameter
    local r, err = Request.source()
    assert.is.falsy(r)
    assert.are.equal("cannot create request with nil source", err)
  end)

  it("source fails with empty socket", function()
    local r, err = Request.source(utils.tcp_socket_source(MockSocket.new({})))
    assert.is.falsy(r)
    assert.are.equal("empty", err)
  end)
  it("source fails with bad pre", function()
    local r, err = Request.source(utils.tcp_socket_source(MockSocket.new({ "junk" })))
    assert.is.falsy(r)
    assert.are.equal('Invalid http request first line: "junk"', err)
  end)
  describe("sink", function()
    it("can send", function()
      local socket = MockSocket.new()
      local r = Request.new("GET", "/", socket)
      r:send("body")
      local all_sent = table.concat(socket.inner, "")
      assert.are.equal("GET / HTTP/1.1\r\nContent-Length: 4\r\n\r\nbody", all_sent)
    end)
    it("does not duplicate preamble", function()
      local socket = MockSocket.new()
      local r = Request.new("GET", "/", socket)
      r:send_preamble()
      r:send_preamble()
      assert.are.equal("GET / HTTP/1.1\r\n", socket.inner[1])
      assert.are.equal(1, #socket.inner)
    end)
    it("send_preamble forwards errors", function()
      local socket = MockSocket.new({}, { "error" })
      local r = Request.new("GET", "/", socket)
      local s, e = r:send_preamble()
      assert.is.falsy(s)
      assert.are.equal("error", e)
    end)
    it("send_header forwards errors", function()
      local socket = MockSocket.new()
      local ct = 0
      local r = Request.new("GET", "/", socket)
      assert(r:send_preamble())
      table.insert(socket.send_errs, "error")
      local s, e = r:send_header()
      assert.is.falsy(s)
      assert.are.equal("error", e)
    end)
    it("send_header forwards errors deeper", function()
      local socket = MockSocket.new({}, {})
      local ct = 0
      local r = Request.new("GET", "/", socket):add_header("X-A-Header", "yes")
      assert(r:send_preamble())
      table.insert(socket.send_errs, "error")
      local s, e = r:send_header()
      assert.is.falsy(s)
      assert.are.equal("error", e)
    end)
    it("cannot send headers after body", function()
      local socket = MockSocket.new()
      local r = Request.new("GET", "/", socket)
      assert(r:send("asdf"))
      local s, e = r:send_header()
      assert.is.falsy(s)
      assert.are.equal("cannot send headers after body", e)
    end)
    it("send_body_chunk forwards errors", function()
      local socket = MockSocket.new({}, {})
      local r = Request.new("GET", "/", socket)
          :add_header("X-A-Header", "yes")
          :append_body("asdf")
      assert(r:send_preamble())
      assert(r:send_header())
      assert(r:send_header())
      assert(r:send_header())
      table.insert(socket.send_errs, "error")
      local s, e = r:send_body_chunk()
      assert.is.falsy(s)
      assert.are.equal("error", e)
    end)
    it("send forwards errors", function()
      local socket = MockSocket.new({}, { "error" })
      local s, e = Request.new("GET", "/", socket):send("asdf")
      assert.is.falsy(s)
      assert.are.equal("error", e)
    end)
    it("incoming iter works", function()
      local socket = MockSocket.new({
        "GET / HTTP/1.1",
        "Content-Length: 13",
        "",
        "1234567890",
        "123"
      })
      local r = assert(Request.tcp_source(socket))
      local iter = r:iter()
      assert.are.same("GET / HTTP/1.1\r\n", iter())
      assert.are.same("Content-Length: 13\r\n", iter())
      assert.are.same("\r\n", iter())
      assert.are.same("1234567890", iter())
      assert.are.same("123", iter())
    end)
    it("long first line can send", function()
      local r = Request.new("DELETE", "/" .. string.rep("a", 4096), MockSocket.new({}))
      assert(r:send(""))
    end)
  end)
  describe("Request.*_source", function()
    it("tcp source works", function()
      assert(Request.tcp_source(MockSocket.new({ "GET / HTTP/1.1\r\n" })))
    end)
    it("udp source works", function()
      assert(Request.udp_source(MockSocket.new({ "GET / HTTP/1.1\r\n" })))
    end)
    it("tcp error bad preamble", function()
      local _, err = Request.tcp_source(MockSocket.new({ "junk" }))
      assert.are.same("Invalid http request first line: \"junk\"", err)
    end)
    it("udp error bad preamble", function()
      local _, err = Request.udp_source(MockSocket.new({ "junk" }))
      assert.are.same("empty", err)
    end)
    it("can handle leading whitespace in preamble", function()
      assert(Request.udp_source(MockSocket.new({ "          GET / HTTP/1.1\r\n" })))
    end)
  end)
  describe("chunk encoding", function()
    local test_utils = require "spec.test_utils"
    describe("inbound", function()
      it("get_body works", function()
        local r = assert(Request.source(test_utils.create_chunked_source(test_utils
          .wikipedia_chunks.request)))
        local b = assert(r:get_body())
        assert.are.equal(test_utils.wikipedia_chunks.assert_body, b or nil)
      end)
      it("large chunks works", function()
        local r = assert(Request.source(test_utils.create_chunked_source(test_utils.large_chunks
          .request)))
        local b = assert(r:get_body())
        assert.are.equal(test_utils.large_chunks.assert_body, b or nil)
      end)
      it("extensions works", function()
        local r = assert(Request.source(test_utils.create_chunked_source(test_utils.extended
          .request)))
        local b = assert(r:get_body())
        assert.are.equal(test_utils.extended.assert_body, b or nil)
      end)
      it("trailers works", function()
        local r = assert(Request.source(test_utils.create_chunked_source(test_utils.trailers
          .request)))
        local headers = assert(r:get_headers())
        assert.are.equal(nil, headers:get_one("Date") or nil)
        local b = assert(r:get_body())
        assert.are.equal(test_utils.trailers.assert_body, b or nil)
        assert.are.equal("Today", r.trailers:get_one("Date") or nil)
      end)
      it("iter works", function()
        local r = assert(Request.source(test_utils.create_chunked_source(test_utils
          .wikipedia_chunks.request)))
        local iter = r:iter()
        assert.are.same("GET / HTTP/1.1\r\n", iter())
        assert.are.same("Transfer-Encoding: chunked\r\n", iter())
        assert.are.same("\r\n", iter())
        assert.are.same("Wiki", iter())
        assert.are.same("pedia ", iter())
        assert.are.same("in \r\n\r\nchunks.", iter())
      end)
      it("iter works with trailers", function()
        local r = assert(Request.source(test_utils.create_chunked_source(test_utils.trailers
          .request)))
        local iter = r:iter()
        assert.are.same("GET /trailers HTTP/1.1\r\n", iter())
        local header_set = {
          ["Trailer: Date,Junk\r\n"] = true,
          ["Transfer-Encoding: chunked\r\n"] = true
        }
        local header1 = assert(iter())
        test_utils.assert_in_set(header_set, header1)
        local header2 = assert(iter())
        test_utils.assert_in_set(header_set, header2)
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
    describe("outbound", function()
      it("mixed encoding works #target", function()
        local expectations = {
          { header = "", chunk_size = nil },
          
        }
        local r = assert(Request.new("GET", "/", nil))
        r:set_transfer_encoding("chunked,gzip")
        assert.are.equal(1024, r._chunk_size)
      end)
      it("iter works", function()
        local r = assert(Request.new("GET", "/", nil))
        local chunk1 = string.rep("a", 10)
        local chunk2 = string.rep("b", 10)
        local chunk3 = string.rep("c", 10)
        r:set_transfer_encoding("chunked", 10)
        r:append_body(chunk1)
        r:append_body(chunk2)
        r:append_body(chunk3)

        local expected_chunks = {
          "GET / HTTP/1.1\r\n",
          "Transfer-Encoding: chunked\r\n",
          "\r\n",
          string.format("%x\r\n%s\r\n", #chunk1, chunk1),
          string.format("%x\r\n%s\r\n", #chunk2, chunk2),
          string.format("%x\r\n%s\r\n", #chunk3, chunk3),
          string.format("0\r\n"),
          string.format("\r\n")
        }
        for line in r:iter() do
          local expected = table.remove(expected_chunks, 1)
          assert.are.same(expected, line)
        end
        assert.are.same({}, expected_chunks)
      end)
      it("iter with trailers", function()
        local r = assert(Request.new("GET", "/", nil))
        local chunk1 = string.rep("a", 10)
        local chunk2 = string.rep("b", 10)
        local chunk3 = string.rep("c", 10)
        r:set_transfer_encoding("chunked", 10)
            :add_header("trailer", "x-trailing-header")
            :append_body(chunk1)
            :append_body(chunk2)
            :append_body(chunk3)
            :add_trailer("x-trailing-header", "some-trailing-value")
        local expected_chunks = {
          "GET / HTTP/1.1\r\n",
          "Transfer-Encoding: chunked\r\n",
          "Trailer: x-trailing-header\r\n",
          "\r\n",
          string.format("%x\r\n%s\r\n", #chunk1, chunk1),
          string.format("%x\r\n%s\r\n", #chunk2, chunk2),
          string.format("%x\r\n%s\r\n", #chunk3, chunk3),
          string.format("0\r\n"),
          "X-Trailing-Header: some-trailing-value",
          "\r\n",
        }
        local iter = r:iter()
        assert.are.same(table.remove(expected_chunks, 1), iter())
        local header_set = {
          [table.remove(expected_chunks, 1)] = true,
          [table.remove(expected_chunks, 1)] = true,
        }
        test_utils.assert_in_set(header_set, iter())
        test_utils.assert_in_set(header_set, iter())
        for line in iter do
          local expected = table.remove(expected_chunks, 1)
          assert.are.same(expected, line)
        end
        assert.are.same({}, expected_chunks)
      end)
    end)
  end)
end)
