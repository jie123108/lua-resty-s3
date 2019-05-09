Name
====

amazon s3 client for ngx_lua. 

Implementation of the Amazon signature V4: http://docs.aws.amazon.com/zh_cn/AmazonS3/latest/API/sig-v4-authenticating-requests.html. 

# Usage

### To load this library

you need to specify this library's path in ngx_lua's lua_package_path directive. For example:
```nginx
http {
   lua_package_path '/path/to/lua-resty-s3/lib/?.lua;;';
}
```

you use require to load the library into a local Lua variable:
```lua
local stats = require("resty.s3")
```

### Methods

```
-- require package
local awss3 = require "resty.s3"

-- init instance.
local s3 = awss3:new(AWSAccessKeyId, AWSSecretAccessKey, aws_bucket, {timeout=1000*10})

-- get a object. http://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectGET.html
local ok, response = s3:get(key)

-- put a object. http://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectPUT.html
local ok, response = s3:put(key, value, headers)

-- delete a object. http://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectDELETE.html
local ok, response = s3:delete(key)

-- delete multi objects. http://docs.aws.amazon.com/AmazonS3/latest/API/multiobjectdeleteapi.html
local ok, response = s3:deletes(keys, quiet)

-- list files. http://docs.aws.amazon.com/AmazonS3/latest/API/v2-RESTBucketGET.html
local ok, files = s3:list(prefix, delimiter, page_size, marker)

-- -- signature-v4. http://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-authenticating-requests.html
local authorization, signature, extinfo = s3:authorization_v4(method, url, headers)

```

# depends
* https://github.com/jie123108/lua-resty-http
* https://github.com/jkeys089/lua-resty-hmac
* https://github.com/membphis/lua-resty-test

# s3相关：
* 测试集：http://docs.aws.amazon.com/zh_cn/general/latest/gr/signature-v4-test-suite.html
* s3 rest api: http://docs.aws.amazon.com/AmazonS3/latest/API/multiobjectdeleteapi.html

# Licence

This module is licensed under the 2-clause BSD license.

Copyright (c) 2017, Xiaojie Liu <jie123108@163.com>

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR AN
Y DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUD
ING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

