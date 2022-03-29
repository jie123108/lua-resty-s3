package = "lua-resty-s3"
version = "0.1-1"
source = {
   url = "git+https://github.com/jie123108¡/lua-resty-s3.git"
}
description = {
   summary = "amazon s3 client for ngx_lua.",
   homepage = "https://github.com/jie123108/lua-resty-s3",
   license = "BSD"
}
dependencies = {
   "lua ~> 5.1"
}
build = {
   type = "builtin",
   modules = {
      ["resty.s3"] = "lib/resty/s3.lua",
      ["resty.s3_auth"] = "lib/resty/s3_auth.lua",
      ["resty.s3_multi_upload"] = "lib/resty/s3_multi_upload.lua",
      ["resty.s3_sha2"] = "lib/resty/s3_sha2.lua",
      ["resty.s3_util"] = "lib/resty/s3_util.lua",
      ["resty.s3_xml"] = "lib/resty/s3_xml.lua"
   }
}
