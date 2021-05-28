local lunch = require 'luncheon'
local socket = require 'socket'
local json = require 'dkjson'

local function format_non_table(v)
  if v == nil then
      return 'nil'
  end
  if type(v) == 'string' then return string.format('\'%s\'', v) end
  return string.format('%s', v)
end
---Format a table as a pretty printed string
---@param v any can be any value but works best with a table
---@param pre string|nil the current prefix (set by recursive calls)
---@param visited table[] tables that have been already printed to avoid infinite recursion (set by recursive calls)
local function table_string(v, pre, visited)
  pre = pre or ''
  visited = visited or {}
  if type(v) ~= 'table' then
      return format_non_table(v)
  elseif next(v) == nil then
      return '{ }'
  end
  local ret = '{'
  local orig_pre = pre
  pre = pre .. '  '
  visited[v] = true
  for key, value in pairs(v) do
      ret = ret .. '\n' .. pre .. key .. ' = '
      if type(value) == 'table' then
          if visited[value] then
              ret = ret .. '[recursive]'
          else
              ret = ret .. table_string(value, pre .. '  ', visited)
          end
      else
          ret = ret .. format_non_table(value)
      end
  end
  return string.format('%s\n%s}', ret, orig_pre)
end

-- print(table_string(lunch))
-- print(table_string(lunch.Request))
-- print(table_string(getmetatable(lunch.Request)))

local sock = socket.tcp()
sock:connect('0.0.0.0', 8080)

local r = assert(lunch.Request.outgoing('GET', '/', sock)
  :set_body('asdf')
  :send())

for line in r:source() do
  print(line)
end
