package = "luncheon"
version = "0.1.0-pre3"
source = {
   url = "https://github.com/FreeMasen/luncheon",
   tag = "v0.1.0-pre3"
}
description = {
   homepage = "https://github.com/FreeMasen/luncheon",
   license = "MIT"
}
dependencies = {
   "net-url >= 0.9",
}
build = {
   type = "builtin",
   modules = {
      luncheon = "luncheon/init.lua",
      ["luncheon.headers"] = "luncheon/headers.lua",
      ["luncheon.request"] = "luncheon/request.lua",
      ["luncheon.response"] = "luncheon/response.lua",
      ["luncheon.status"] = "luncheon/status.lua",
   }
}
