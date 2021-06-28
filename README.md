# Luncheon

HTTP types for Lua

![Luncheon Logo](./Luncheon.svg)

## Install

This library is published on [luarocks](https://luarocks.org/modules/FreeMasen/luncheon)

```sh
luarocks install luncheon
```

## Usage

Luncheon provides Lua tables that represent HTTP `Request`s and `Response`s and
a way to parse or build them.

### Parsing

Both `Request` and `Response` expose a constructor `source`, which expects the only argument to
be a function that returns a single line of the request when called. So a simple example of that
might look like this.

```lua
local Request = 'luncheon.request'
local req_lines = {
  'GET / HTTP/1.1',
  'Content-Length: 0',
  ''
}
local req = Request.source(function()
  return table.remove(req_lines, 1)
end)
assert(req.method == 'GET')
assert(req.url.path == '/')
assert(req.http_version == 1.1)
assert(req:get_headers():get_one('content_length') == 0)

local Response = 'luncheon.response'
local res_lines = {
  'HTTP/1.1 200 Ok',
  'Content-Length: 0',
  ''
}
local res = Response.source(function()
  return table.remove(res_lines, 1)
end)
assert(res.status == 200)
assert(res.status_msg == 'Ok')
assert(res.http_version == 1.1)
assert(res:get_headers():get_one('content_length') == 0)
```

Notice how in both of the above examples, the lines _do not_ contain a new line character, this is because
Lua's normal methods for reading IO, will omit a trailing new line. For example `io.open('README.md'):read('*l')`
returns `'# Luncheon'` with no trailing new line.

To handle some common use cases, the `utils` module provides a source wrapper around luasocket's tcp and udp sockets.

### Building

Both `Request` and `Response` expose a constructor `new` along 
with the `serialize` and `as_source` methods
for building them and then converting them into "hypertext". 

```lua
local Request = require 'luncheon.request'
local req = Request.new('GET', '/')
  :add_header('Host', 'example.com')
  :append_body('I am a request body')
for line in req:as_source()
  print(string.gsub(line, '\r?\n$', ''))
end
local Response = require 'luncheon.response'
local res = Response.new(200)
  :add_header('age', '2000')
  :append_body('I am a response body')
print(res:serialize())
```

Notice how the `req:as_source()` loop has to remove new lines
before printing. That means we already get the `CRLF` line endings
required for the start line and headers.

## Examples

### Basic echo server

This example uses [luasocket](https://w3.impa.br/~diego/software/luasocket/home.html)
to receive incoming HTTP `Request`s and echo them back out as `Response`s.


```lua
Request = require 'luncheon.request'
Response = require 'luncheon.response'
utils = require 'luncheon.utils'
socket = require 'socket' --luasocket
tcp = assert(socket.tcp())
assert(tcp:bind('0.0.0.0', 8080))
assert(tcp:listen())
while true do
  local incoming = assert(tcp:accept())
  local source = utils.tcp_socket_source(incoming)
  local req = assert(Request.source(source))
  print('Request')
  print('url', req.url.path)
  print('method', req.method)
  print('body', req:get_body())
  local res = Response.new()
    :add_header('Server', 'Luncheon Echo Server')
    :append_body(req:get_body())
  for chunk in res:as_source() do
    assert(utils.send_all(incoming, chunk))
  end
  incoming:close()
end
```

See the [examples](/examples) directory for more
