local utils = require "luncheon.utils"
local MockSocket = require "spec.mock_socket".MockSocket

describe("utils", function()
  describe("send_all", function()
    it("sends", function()
      local sock = MockSocket.new()
      assert.is.equal(4, utils.send_all(sock, "asdf"))
    end)
    it("retries on timeout", function()
      local sock = MockSocket.new()
      assert.is.equal(8, utils.send_all(sock, "timeout2"))
    end)
    it("errors on 5+ timeout", function()
      local sock = MockSocket.new()
      local ct, err = utils.send_all(sock, "timeout6")
      assert.is.falsy(ct)
      assert.is.equal(err, "timeout")
    end)
    it("retries on panic", function()
      local sock = MockSocket.new()
      assert.is.equal(5, utils.send_all(sock, "panic"))
    end)
    it("retries on error", function()
      local sock = MockSocket.new()
      local s, e, s2 = utils.send_all(sock, "error2")
      assert.is.falsy(s)
      assert.is.equal("error", e)
      assert.is.equal(0, s2)
    end)
    it("errors on closed", function()
      local sock = MockSocket.new()
      local n, e = utils.send_all(sock, "closed")
      assert.is.falsy(n)
      assert.are.equal("Attempt to send on closed socket", e)
    end)
    it("next_line works \\n", function()
      local text, line = table.concat({ "1", "2", "3", "4", "" }, "\n"), nil
      for i = 1, 4 do
        line, text = utils.next_line(text)
        assert.are.equal(tostring(i), line)
      end
    end)
    it("next_line works \\r\\n", function()
      local text, line = table.concat({ "1", "2", "3", "4", "" }, "\r\n"), nil
      for i = 1, 4 do
        line, text = utils.next_line(text)
        assert.are.equal(tostring(i), line)
      end
    end)
    it("next_line mixed", function()
      local text, line =
          table.concat({ "1", "2", "" }, "\r\n") .. table.concat({ "3", "4", "" }, "\n"), nil
      for i = 1, 4 do
        line, text = utils.next_line(text)
        assert.are.equal(tostring(i), line)
      end
    end)
    describe("udp socket wrapper", function()
      it("can handle chunky receives", function()
        local target = table.concat({
              "HTTP/1.1 200 Ok",
              "Content-Type: application/json",
              "Content-Length: 14",
              "\r\n",
            }, "\r\n") .. '{"one": "two"}'
        local inner = {}
        for ch in string.gmatch(target, ".") do
          table.insert(inner, ch)
        end
        local sock = MockSocket.new(inner)
        local wrapped = utils.udp_socket_source(sock)
        assert.are.equal("HTTP/1.1 200 Ok", assert(wrapped()))
        assert.are.equal("Content-Type: application/json", assert(wrapped()))
        assert.are.equal("Content-Length: 14", assert(wrapped()))
        assert.are.equal("", assert(wrapped()))
        assert.are.equal('{"one": "two"}', assert(wrapped(14)))
      end)
      it("can handle one receive", function()
        local target = table.concat({
              "HTTP/1.1 200 Ok",
              "Content-Type: application/json",
              "Content-Length: 14",
              "\r\n",
            }, "\r\n") .. '{"one": "two"}'
        local sock = MockSocket.new({ target })
        local wrapped = utils.udp_socket_source(sock)
        assert.are.equal("HTTP/1.1 200 Ok", assert(wrapped()))
        assert.are.equal("Content-Type: application/json", assert(wrapped()))
        assert.are.equal("Content-Length: 14", assert(wrapped()))
        assert.are.equal("", assert(wrapped()))
        assert.are.equal('{"one": "two"}', assert(wrapped(14)))
      end)
      it("can two receives", function()
        local target = table.concat({
              "HTTP/1.1 200 Ok",
              "Content-Type: application/json",
              "Content-Length: 14",
              "\r\n",
            }, "\r\n") .. '{"one": "two"}'
        local len1 = math.floor(#target / 2)
        local len2 = math.ceil(#target / 2)
        local sock = MockSocket.new({ target:sub(1, len1 + 5), target:sub(len1 + 6) })
        local wrapped = utils.udp_socket_source(sock)
        assert.are.equal(target:sub(1, len1), assert(wrapped(len1)))
        assert.are.equal(target:sub(len1 + 1), assert(wrapped(len2)))
      end)
      it("bad buffer", function()
        local target = table.concat({
              "HTTP/1.1 200 Ok",
              "Content-Type: application/json",
              "Content-Length: 14",
              "\r\n",
            }, "\r\n") .. '{"one": "two"}'
        local len1 = math.floor(#target / 2)
        local len2 = math.ceil(#target / 2)
        local sock = MockSocket.new({ target:sub(1, len1 + 5), target:sub(len1 + 6) })
        local wrapped = utils.udp_socket_source(sock)
        assert.are.equal(target:sub(1, len1), assert(wrapped(len1)))
        assert.are.equal(target:sub(len1 + 1), assert(wrapped(len2)))
      end)
      it("short buffer", function()
        local inner = {
          "HTTP/1.1 200 Ok\r\n",
          "Content-Type: application/json\r\n",
          "Content-Length: 14\r\n",
        }
        local sock = MockSocket.new(inner)
        local wrapped = utils.udp_socket_source(sock)
        assert(wrapped())
        assert(wrapped())
        assert(wrapped())
        local line, err = wrapped()
        assert.is.falsy(line)
        assert("empty", err)
      end)
      it("short buffer len", function()
        local inner = {
          "HTTP/1.1 200 Ok\r\n",
          "Content-Type: application/json\r\n",
          "Content-Length: 14\r\n",
        }
        local sock = MockSocket.new(inner)
        local wrapped = utils.udp_socket_source(sock)
        assert(wrapped())
        assert(wrapped())
        assert(wrapped())
        local line, err = wrapped(12)
        assert.is.falsy(line)
        assert("empty", err)
      end)
    end)
    describe("tcp socket wrapper", function()
      it("zero receive", function()
        local wrapped = utils.tcp_socket_source({})
        assert.are.equal("", wrapped(0))
      end)
    end)
  end)
end)
