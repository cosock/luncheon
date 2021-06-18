# Luncheon

HTTP types for Lua

![Sandwiches on a plate](./Luncheon.svg)

## Usage

Luncheon provides data types that represent the request/response cycle of http communication.
Both the `Request` and `Response` objects expect to receive a `luasocket` like interface for 
sending and receiving hyper text but expose an ergonomic api for lazily parsing/constructing the
content of the messages.

### Basic echo server

```lua
Request = require 'luncheon.request'
Response = require 'luncheon.response'
socket = require 'socket' --luasocket
tcp = assert(socket.tcp())
assert(tcp:bind('0.0.0.0', 8080))
assert(tcp:listen())
while true do
  local incoming= assert(tcp:accept())
  local req = assert(Request.incoming(incoming))
  print('Request')
  print('url', req.url.path)
  print('method', req.method)
  print('body', req:get_body())
  Response.outgoing(incoming)
    :content_type(req.headers.content_type or 'text/plain')
    :add_header('Server', 'Luncheon Echo Server')
    :send(req:get_body())
end
```
