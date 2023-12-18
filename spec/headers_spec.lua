---@diagnostic disable: invisible
local Headers = require "luncheon.headers"
local normal_headers = require "spec.normal_headers"
local test_utils = require "spec.test_utils"

describe("Headers", function()
  describe("append_chunk", function()
    it("All Standard headers", function()
      local h = Headers.new()
      for _, set in ipairs(normal_headers) do
        local chunk = set[1]
        local key = set[2]
        local expected = set[3]
        h:append_chunk(chunk)
        assert(h:get_one(key) == expected,
          string.format("%s found %s expected %s", key, h[key], expected))
      end
    end)
    it("from_chunk", function()
      local h = assert(Headers.from_chunk("Accept: application/json"))
      assert(h:get_one("accept") == "application/json",
        string.format("expected application/json, found %s", h._inner.accept))
    end)
    it("append", function()
      local h = Headers.new()
      h:append("accept", "application/json1")
      ---@diagnostic disable-next-line: undefined-field
      assert(h:get_one("accept") == "application/json1",
        string.format("expected application/json, found %s", h._inner.accept))
      h:append("accept", "application/json2")
      assert(h:get_all("accept")[1] == "application/json1",
        string.format("expected application/json1, found %s", h._inner.accept))
      assert(h:get_all("accept")[2] == "application/json2",
        string.format("expected application/json2, found %s", h._inner.accept))
    end)
    it("append key-only header, nil value", function()
      local h = Headers.new()
      h:append("EXT", nil)
      assert.are.same('', h:get_one("ext"))
    end)
    it("append key-only header, empty string value", function()
      local h = Headers.new()
      h:append("EXT", "")
      assert.are.same('', h:get_one("ext"))
    end)
    it("append key-only header, empty string value handled the same as nil value", function()
      local h = Headers.new()
      h:append("EXT1", nil)
      h:append("EXT2", "")
      assert.are.same(h:get_one("ext1"), h:get_one("ext2"))
    end)
    it("append_chunk", function()
      local h = Headers.new()
      local _, err1 = h:append_chunk("Accept: application/json")
      assert(err1 == nil, string.format('error frrom first append "%s"', err1))
      local _, err2 = h:append_chunk(" application/text")
      assert(err2 == nil, string.format('error frrom second append "%s"', err2))
      assert.are.same("application/json application/text", h:get_one("accept"))
    end)
    it("append_chunk key-only header", function()
      local h = Headers.new()
      local _, err1 = h:append_chunk("EXT:")
      assert(err1 == nil, string.format('error from append_chunk: "%s"', err1))
      assert.are.same('', h:get_one("ext"))
    end)
    it("append_chunk continuation with no key", function()
      local h = Headers.new()
      local _, err1 = h:append_chunk(" bad")
      assert(err1 == "Header continuation with no key", err1)
    end)
    it("from_chunk key-only header", function()
      local h, err1 = Headers.from_chunk("EXT:")
      assert(err1 == nil, string.format('error from append_chunk: "%s"', err1))
      assert.are.same('', h:get_one("ext"))
    end)
    it("from_chunk continuation with no key", function()
      local _, err1 = Headers.from_chunk(" bad")
      assert(err1 == "Header continuation with no key", err1)
    end)
    it("append_chunk nil", function()
      local h = Headers.new()
      ---@diagnostic disable-next-line: missing-parameter
      local _, err1 = h:append_chunk()
      assert.are.equal("invalid header, expected string found nil", err1)
    end)
    it("append", function()
      local h = Headers.new()
      h:append("accept", "application/json1")
      assert(h:get_one("accept") == "application/json1",
        string.format("expected application/json, found %s", h._inner.accept))
      h:append("accept", "application/json2")
      assert(h:get_all("accept")[1] == "application/json1",
        string.format("expected application/json1, found %s", h._inner.accept))
      assert(h:get_all("accept")[2] == "application/json2",
        string.format("expected application/json2, found %s", h._inner.accept))
      h:append("accept", "application/json3")
      assert(h:get_all("accept")[1] == "application/json1",
        string.format("expected application/json1, found %s", h._inner.accept))
      assert(h:get_all("accept")[2] == "application/json2",
        string.format("expected application/json2, found %s", h._inner.accept))
      assert(h:get_all("accept")[3] == "application/json3",
        string.format("expected application/json3, found %s", h._inner.accept))
    end)
    it("get_one", function()
      local h = Headers.new()
      h:append("accept", "application/json1")
      assert(h:get_one("accept") == "application/json1",
        string.format("expected application/json1, found %s", h:get_one("accept")))
      h:append("accept", "application/json2")
      assert(h:get_one("accept") == "application/json2",
        string.format("expected application/json1, found %s", h:get_one("accept")))
    end)
    it("get_all", function()
      local h = Headers.new()
      h:append("accept", "application/json1")
      local table1 = h:get_all("accept")
      assert(table1[1] == "application/json1",
        string.format("expected application/json1, found %s", table[1]))
      h:append("accept", "application/json2")
      local table2 = h:get_all("accept")
      assert(table2[1] == "application/json1",
        string.format("expected application/json1, found %s", table[1]))
      assert(table2[2] == "application/json2",
        string.format("expected application/json2, found %s", table[2]))
    end)
    it("Can handle multi line headers", function()
      local h = Headers.new()
      h:append_chunk("x-Multi-Line-Header: things and stuff")
      h:append_chunk(" places and people")
      assert.are.same("things and stuff places and people", h:get_one("x_multi_line_header"))
    end)
    it("Can handle multi line headers in chunk #hc", function()
      local h = Headers.new()
      h:append_chunk(
        table.concat({
          "content-type: application/json",
          "x-Multi-Line-Header: things and stuff",
          " people and places",
        }, "\r\n")
      )
      assert.are.same("application/json", h:get_one("content_type"))
      assert.are.same("things and stuff people and places", h:get_one("x_multi_line_header"))
    end)
  end)
  describe("serialize_header", function()
    it("can handle normal header", function()
      for _, set in ipairs(normal_headers) do
        local header = Headers.serialize_header(set[2], set[3])
        assert(header == set[1], string.format("expected %s found %s", set[1], header))
      end
    end)
    it("multiline header", function()
      local header1 = Headers.serialize_header("accept", { "application/json1" })
      assert.are.equal("Accept: application/json1", header1)
      local header2 = Headers.serialize_header("accept", { "application/json1", "application/json2" })
      assert.are.equal("Accept: application/json1\r\nAccept: application/json2", header2)
    end)
    it("handle all", function()
      local headers = Headers.new()
      local header_set = {}
      for _, set in ipairs(normal_headers) do
        header_set[set[1]] = true
        headers:append_chunk(set[1])
      end
      local serialized = headers:serialize()
      local ct = 0
      for line in string.gmatch(serialized, "([^\r\n]+)\r\n") do
        ct = ct + 1
        test_utils.assert_in_set(header_set, line)
      end
    end)
  end)
end)
