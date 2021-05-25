# Luncheon

HTTP types for Lua
![Sandwiches on a plate](./Luncheon.svg)


## Usage

Luncheon provides data types that represent the request/response cycle of http communication.
Both the `Request` and `Response` objects expect to receive a `luasocket` like interface for 
sending and receiving hyper text but expose an ergonomic api for lazily parsing/generating the
content of the messages.

### Basic echo server

```lua
local Request = require 'luncheon.request'.Request
local Response = require 'luncheo.response'.Response
local socket = require 'socket' --luasocket
local tcp = assert(socket.tcp())
assert(tcp:bind('0.0.0.0', 8080))
assert(tcp:listen())
while true do
  local incoming= assert(tcp:accept())
  local req = assert(Request.new(incoming))
  print('Request')
  print('url', req.url.path)
  print('method', req.method)
  print('body', req:get_body())
  local res = Response.new(incoming)
  res:content_type(req.headers.content_type or 'text/plain')
  res:send(req:get_body())
end
```
