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
local awss3 = require("resty.s3")
```

### Methods

```
-- require package
local awss3 = require "resty.s3"

-- init instance.
local s3 = awss3:new(AWSAccessKeyId, AWSSecretAccessKey, aws_bucket, {timeout=1000*10})

-- get a object. http://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectGET.html
local ok, response = s3:get(key)

-- get a object. http://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectHEAD.html
local ok, response = s3:head(key)

-- put a object. http://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectPUT.html
local ok, response = s3:put(key, value, headers)

-- delete a object. http://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectDELETE.html
local ok, response = s3:delete(key)

-- delete multi objects. http://docs.aws.amazon.com/AmazonS3/latest/API/multiobjectdeleteapi.html
local ok, response = s3:deletes(keys, quiet)

-- list files. http://docs.aws.amazon.com/AmazonS3/latest/API/v2-RESTBucketGET.html
local ok, files = s3:list(prefix, delimiter, page_size, marker)

-- copy files.  https://docs.aws.amazon.com/AmazonS3/latest/API/API_CopyObject.html
local ok, response = s3:copy(key, source, headers)

-- -- signature-v4. http://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-authenticating-requests.html
local authorization, signature, extinfo = s3:authorization_v4(method, url, headers)

```

# depends

* [ledgetech/lua-resty-http](https://github.com/ledgetech/lua-resty-http)
* [jkeys089/lua-resty-hmac >= 0.01](https://github.com/jkeys089/lua-resty-hmac) 

# test

### install test dependencies

* [iresty/lua-resty-test >= 0.01](https://github.com/iresty/lua-resty-test)

```
opm get jie123108/lua-resty-test
```

### run the signature-v4-test-suite

```
cd path/to/lua-resty-s3
resty -I lib test/aws-sig-v4-test-suite.lua
```

* test suite：[http://docs.aws.amazon.com/zh_cn/general/latest/gr/signature-v4-test-suite.html(The link is dead.)](http://docs.aws.amazon.com/zh_cn/general/latest/gr/signature-v4-test-suite.html)

### Run the signature examples on the AWS website.

[Signature Examples On AWS Website](https://docs.aws.amazon.com/zh_cn/AmazonS3/latest/API/sig-v4-header-based-auth.html)

```
resty -I lib test/test-s3-sign-examples.lua
```


### Run s3 tests

#### Testing with Minio

##### Using docker to run minio:

* 1. Startup minio container

```
docker run -d -it --name s3 -p 9000:9000 \
-e MINIO_ACCESS_KEY=THE_ACCESS_KEY_ID \
-e MINIO_SECRET_KEY=THE_SECRET_ACCESS_KEY \
minio/minio server /data/minio_data
```

* 2. Access the minio console: http://127.0.0.1:9000/minio/
  * Access Key: THE_ACCESS_KEY_ID
  * Secret Key: THE_SECRET_ACCESS_KEY
* 3. Add a storage bucket named `def' in the console
  * Once logged in, click the `+` button in the lower right corner and click the `Create bucket` in the pop-up menu.

##### Run Tests:

```shell
resty -I lib test/test-s3.lua
```

#### Testing with aws s3

```shell
S3_CONFIG="S3_ACCESS_ID:S3_ACCESS_SECERT_KEY:s3_bucket_name:s3_region" resty -I lib test/test-s3.lua
```

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

