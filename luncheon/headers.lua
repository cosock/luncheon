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
---@field private _inner table A table containing the deserialized header key/value pairs
---@field private _last_key string The last key deserialized, for multiline headers
local Headers = {}

Headers.__index = Headers

--- Following this comment are Lua Patterns for parsing HTTP/1.1 Headers (key/value pairs).
--- The HTTP/1.1 Message Format is defined here: https://www.rfc-editor.org/rfc/rfc2616#page-32
---
--- Reproducing the BNF for a HTTP message header locally:
---
---         message-header = field-name ":" [ field-value ]
---         field-name     = token
---         field-value    = *( field-content | LWS )
---         field-content  = <the OCTETs making up the field-value
---                          and consisting of either *TEXT or combinations
---                          of token, separators, and quoted-string>
---
--- `token` is defined here: https://www.rfc-editor.org/rfc/rfc2616#page-17
---
---         token          = 1*<any CHAR except CTLs or separators>
---         separators     = "(" | ")" | "<" | ">" | "@"
---                        | "," | ";" | ":" | "\" | <">
---                        | "/" | "[" | "]" | "?" | "="
---                        | "{" | "}" | SP | HT
---
--- Relevant additional rules from: https://www.rfc-editor.org/rfc/rfc2616#section-2.2
---
---         OCTET          = <any 8-bit sequence of data>
---         CHAR           = <any US-ASCII character (octets 0 - 127)>
---         SP             = <US-ASCII SP, space (32)>
---         HT             = <US-ASCII HT, horizontal-tab (9)>
---         CR             = <US-ASCII CR, carriage return (13)>
---         LF             = <US-ASCII LF, linefeed (10)>
---         LWS            = [CRLF] 1*( SP | HT )
---         CRLF           = CR LF
---         CTL            = <any US-ASCII control character (octets 0 - 31) and DEL (127)>
---         TEXT           = <any OCTET except CTLs, but including LWS>
---
--- Square brackets denote optional elements. The Kleene Star `*` is used for repetition.
--- By itself it means 0 or more. A preceding digit `n` means at least `n`, and a suffix `m`
--- means at most `m`.

--- *************************************
--- *                                   *
--- *     Begin Pattern Definitions     *
--- *                                   *
--- *************************************

--- Pattern for extracting a header line's `field-name` based on the BNF above.
--- We first construct a pattern to match all of the illegal characters:
---   - `%c` matches all control characters, which should capture SP and HT as well
---   - `%(%)` matches parens
---   - `<>` matches angle brackets
---   - `@` matches the at symbol
---   - `,;:\\/"` matches `,`, `;`, `:`, `\`, `/`, and `"`
---   - `%[%]` matches square brackets
---   - `%?` matches question mark
---   - `=` matches the equal sign `=`
---   - `{}` matches curly braces
---
--- We create a char-set out of this using the unescaped square brackets, and make it a complement
--- to the char-set by using the caret anchor `^` at the start of the charset. The `+` makes it capture
--- one or more repeitions of this complement char-set (the set of *legal* characters).
---
--- More information on the Lua Pattern syntax can be found here: https://www.lua.org/pil/20.2.html
local header_field_name_pattern = '([^%c%(%)<>@,;:\\/"%[%]%?={}]+)'

--- Pattern for extracting a header line's optional `field-value` based on the BNF above.
--- The field value is, essentially, arbitrary stripped out leading whitespace, followed by
--- almost any sequence of bytes. Note that here we're extracting the field *value* but not the
--- field *content*, so some trailing whitespace may still be present.
---
--- More information on the Lua Pattern syntax can be found here: https://www.lua.org/pil/20.2.html
local header_field_value_pattern = '%s*(.*)'

--- BNF:
---     message-header = field-name ":" [ field-value ]
local message_header_pattern = header_field_name_pattern .. ":" .. header_field_value_pattern

--- *************************************
--- *                                   *
--- *      End Pattern Definitions      *
--- *                                   *
--- *************************************

local function _append(t, key, value)
  value = tostring(value)
  if not t[key] then
    t[key] = value
  elseif type(t[key]) == "string" then
    t[key] = { t[key], value }
  else
    table.insert(t[key], value)
  end
end

---Serialize a key value pair w/o the trailing new line
---
--- If the provided value is a `string[]`, it will be joined with `\r\n` into one
--- string, though no trailing new line will be provided
---@param key string
---@param value string|string[]
---@return string
function Headers.serialize_header(key, value)
  if type(value) == "table" then
    local serialized = {}
    for _, v in ipairs(value) do
      table.insert(serialized, Headers.serialize_header(key, v))
    end
    return table.concat(serialized, "\r\n")
  end
  -- special case for MD5
  key = string.gsub(key, "md5", "mD5")
  -- special case for ETag
  key = string.gsub(key, "etag", "ETag")
  if #key < 3 then
    return string.format("%s: %s", key:upper(), value)
  end
  -- special case for WWW-*
  key = string.gsub(key, "www", "WWW")
  local replaced = key:sub(1, 1):upper() .. string.gsub(key:sub(2), "_(%l)", function(c)
    return "-" .. c:upper()
  end)
  return string.format("%s: %s", replaced, value)
end

---Serialize the whole set of headers separating them with a '\\r\\n'
---@return string
function Headers:serialize()
  local ret = ""
  for header in self:iter() do
    ret = ret .. header .. "\r\n"
  end
  return ret
end

function Headers:_handle_single_line(line)
  if string.match(line, "^%s+") ~= nil then
    if not self._last_key then
      return nil, "Header continuation with no key"
    end
    local existing = self:get_one(self._last_key)
    self._inner[self._last_key] = string.format("%s %s", existing, string.sub(line, 2))
    return 1
  end
  for raw_key, value in string.gmatch(line, message_header_pattern) do
    self:append(raw_key, value)
  end
  return 1
end

---Append a chunk of headers to this map
---@param text string
---@return integer|nil success 1 if successful
---@return nil|string err if ret1 is `nil` an error message
function Headers:append_chunk(text)
  if type(text) ~= "string" then
    return nil, "invalid header, expected string found " .. type(text)
  end
  for chunk in string.gmatch(text, "([^\r\n]+)") do
    local s, err = self:_handle_single_line(chunk)
    if not s then
      return nil, err
    end
  end
  return 1
end

---Constructor for a Headers instance with the provided text
---@param text string
---@return Headers|nil
---@return nil|string
function Headers.from_chunk(text)
  local headers = Headers.new()
  local s, err = headers:append_chunk(text)
  if not s then
    return nil, err
  end
  return headers
end

---Bare constructor
---@return Headers
function Headers.new()
  local ret = {
    _inner = {},
    last_key = nil,
  }
  setmetatable(ret, Headers)
  return ret
end

---Convert a standard header key to the normalized
---lua identifer used by this collection
---@param key string
---@return string
function Headers.normalize_key(key)
  local lower = string.lower(key)
  local normalized = string.gsub(lower, "-", "_")
  return normalized
end

---Insert a single key value pair to the collection will duplicate existing keys
---@param key string
---@param value string|nil
---@return Headers
function Headers:append(key, value)
  key = Headers.normalize_key(key)
  -- because parsing a value-less header line populates the map with an empty string,
  -- we normalize passed nil values to empty string.
  _append(self._inner, key, (value or ''))
  self._last_key = key
  return self
end

---Insert a single key value pair to the collection will not duplicate keys
---@param key string
---@param value string
---@return Headers
function Headers:replace(key, value)
  key = Headers.normalize_key(key)
  -- We *don't* normalize here, to allow for nil'ing out a key.
  self._inner[key] = value
  self._last_key = key
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
  local k = Headers.normalize_key(key or "")
  local value = self._inner[k]
  if type(value) == "table" then
    return value[#value]
  else
    return value
  end
end

---Get a header from the map of headers as a list of strings.
---In the event that a header's key is duplicated, the value
---is stored internally as a list of values. This method is
---useful for getting that list.
---
---
---This will first normalize the provided key. For example
---'Content-Type' will be normalized to `content_type`.
---@param key string
---@return string[]
function Headers:get_all(key)
  local k = Headers.normalize_key(key or "")
  local values = self._inner[k]
  if type(values) == "string" then
    return { values }
  end
  return values
end

---Return a lua iterator over the key/value pairs in this header map
---@return function():string|nil
function Headers:iter()
  local last = nil
  return function()
    local k, v = next(self._inner, last)
    last = k
    if not k then
      return
    end
    return Headers.serialize_header(k, v)
  end
end

return Headers
