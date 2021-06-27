local LAST_KEY = '@LASTKEY'
local LAST_KEY_GETTER = '@LASTKEYGETTER'
---@class Headers
---
---A map of the key value pairs from the header portion
---of an HTTP request or response. The fields listed below
---are some common headers but the list is not exhaustive.
---
---When each header is serialized, it is added as a property with
---lower_snake_case. For example, `X-Forwarded-For` becomes `x_forwarded_for`.
---
---Typically each header's value will be a string, however if there are multiple entries
---for any header, it will be a table of strings.
---
---@field public accept string
---@field public accept_charset string
---@field public accept_encoding string
---@field public accept_language string
---@field public accept_ranges string
---@field public age string
---@field public allow string
---@field public authorization string
---@field public cache_control string
---@field public connection string
---@field public content_encoding string
---@field public content_language string
---@field public content_length string
---@field public content_location string
---@field public content_md5 string
---@field public content_range string
---@field public content_type string
---@field public date string
---@field public etag string
---@field public expect string
---@field public expires string
---@field public from string
---@field public host string
---@field public if_match string
---@field public if_modified_since string
---@field public if_none_match string
---@field public if_range string
---@field public if_unmodified_since string
---@field public last_modified string
---@field public location string
---@field public max_forwards string
---@field public pragma string
---@field public proxy_authenticate string
---@field public proxy_authorization string
---@field public range string
---@field public referer string
---@field public retry_after string
---@field public server string
---@field public te string
---@field public trailer string
---@field public upgrade string
---@field public user_agent string
---@field public vary string
---@field public via string
---@field public warning string
---@field public www_authenticate string
local Headers = {}

Headers.__index = Headers

local function _append(t, key, value)
    if not t[key] then
        t[key] = value
    elseif type(t[key]) == 'string' then
        t[key] = {t[key], value}
    else
        table.insert(t[key], value)
    end
end

---Serialize a key value pair
---@param key string
---@param value string
---@return string
function Headers.serialize_header(key, value)
    if type(value) == 'table' then
        value = value[#value]
    end
    -- special case for MD5
    key = string.gsub(key, 'md5', 'mD5')
    -- special case for ETag
    key = string.gsub(key, 'etag', 'ETag')
    if #key < 3 then
        return string.format('%s: %s', key:upper(), value)
    end
    -- special case for WWW-*
    key = string.gsub(key, 'www', 'WWW')
    local replaced = key:sub(1, 1):upper() .. string.gsub(key:sub(2), '_(%l)', function (c)
        return '-' .. c:upper()
    end)
    return string.format('%s: %s', replaced, value)
end

---Serialize the whole set of headers separating them with a '\\r\\n'
---@return string
function Headers:serialize()
    local ret = ''
    for key, value in pairs(self) do
        ret = ret .. Headers.serialize_header(key, value) .. '\r\n'
    end
    return ret
end

---Append a chunk of headers to this map
---@param text string
function Headers:append_chunk(text)
    if text == nil then
        return nil, 'nil header'
    end
    if string.match(text, '^%s+') ~= nil then
        local last_key = self[LAST_KEY_GETTER]()
        if not last_key then
            return nil, 'Header continuation with no key'
        end
        local existing = self[last_key]
        self[last_key] = string.format('%s %s', existing, text)
        return 1
    end
    for raw_key, value in string.gmatch(text, '([^%c()<>@,;:\\"/%[%]?={} \t]+): (.+);?') do
        self:append(raw_key, value)
    end
    return 1
end

---Constructor for a Headers instance with the provided text
---@param text string
---@return Headers
function Headers.from_chunk(text)
    local headers = Headers.new()
    headers:append_chunk(text)
    return headers
end

---Bare constructor
---@param base table|nil
function Headers.new(base)
    local proxy = {
        [LAST_KEY] = nil,
    }
    local last_key_getter = function ()
       return proxy[LAST_KEY]
    end

    local ret = base or {}
    setmetatable(ret, {
        __index = function (t, k)
            if k ~= LAST_KEY then
                if k == LAST_KEY_GETTER then
                    return last_key_getter
                end
                return Headers[k]
            end
        end,
        __newindex = function(t, k, v)
            if k == LAST_KEY then
                proxy[LAST_KEY] = v
                return
            end
            rawset(t, k, v)
        end,
    })
    return ret
end

---Convert a standard header key to the normalized
---lua identifer used by this collection
---@param key string
---@return string
function Headers.normalize_key(key)
    local lower = string.lower(key)
    local normalized = string.gsub(lower, '-', '_')
    return normalized
end

---Insert a single key value pair to the collection
---@param key string
---@param value string|string[]
---@return Headers
function Headers:append(key, value)
    key = Headers.normalize_key(key)
    _append(self, key, value)
    self[LAST_KEY] = key
    return self
end

---Get a header from the map of headers
---
---This will first normalize the provided key. For example
---'Content-Type' will be normalized to `content_type`.
---If more than one value is provided for that header, the
---last value will be provided
---@param key string
---@return string
function Headers:get_one(key)
    local k = Headers.normalize_key(key or '')
    local value = self[k]
    if type(value) == 'table' then
        return value[#value]
    else
        return value
    end
end

---Get a header from the map of headers as a list of strings
---
---This will first normalize the provided key. For example
---'Content-Type' will be normalized to `content_type`.
---@param key string
---@return string[]
function Headers:get_all(key)
    local k = Headers.normalize_key(key or '')
    local values = self[k]
    if type(values) == 'string' then
        return {values}
    end
    return values
end

return Headers
