local m = {}

m.create_chunked_source = function(body)
    local buf = body
    return function(pat)
        if #buf == 0 then
            return nil, "closed"
        end
        pat = pat or "*l"
        if type(pat) == "number" then
            local ret = string.sub(buf, 1, pat)
            buf = string.sub(buf, pat + 1)
            return ret
        end
        local s, end_idx = string.find(buf, "\r?\n")
        if not s then
            return nil, "closed"
        end
        local ret = string.sub(buf, 1, s - 1)
        buf = string.sub(buf, end_idx + 1)
        return ret
    end
end

m.wikipedia_chunks = (function()
    local chunked_body = table.concat({
        "4",
        "Wiki",
        "6",
        "pedia ",
        "E",
        "in ",
        "",
        "chunks.",
        "0",
        "",  
    }, "\r\n")
    local body = "Wikipedia in \r\n\r\nchunks."
    local request = table.concat({
        "GET / HTTP/1.1",
        "Transfer-Encoding: chunked",
        "",
        chunked_body
    }, "\r\n")
    local response = table.concat({
        "HTTP/1.1 200 OK",
        "Transfer-Encoding: chunked",
        "",
        chunked_body
    }, "\r\n")
    return {
        chunked_body = chunked_body,
        request = request,
        response = response,
        assert_body = body,
    }
end)()

return m
