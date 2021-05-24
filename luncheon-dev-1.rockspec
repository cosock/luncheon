package = "luncheon"
version = "dev-1"
source = {
   url = "*** please add URL for source tarball, zip or repository here ***"
}
description = {
   homepage = "*** please enter a project homepage ***",
   license = "*** please specify a license ***"
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
