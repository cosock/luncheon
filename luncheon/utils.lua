---Send all text provided, retrying on failure or timeout
---@param sock table The client socket to send on
---@param s string The string to send
local function send_all(sock, s)
    local total_sent = 0
    local target = #s
    local retries = 0
    while total_sent < target and retries < 5 do
        local success, sent_or_err, err = pcall(sock.send, sock, string.sub(s, total_sent))
        if not success then
            retries = retries + 1
        else
            if not sent_or_err then
                if err == 'closed' then
                    return nil, 'Attempt to send on closed socket'
                elseif err == 'timeout' then
                    retries = retries + 1
                end
                
            else
                total_sent = total_sent + sent_or_err
            end
        end
    end
    return total_sent
end

return {
    send_all = send_all,
}