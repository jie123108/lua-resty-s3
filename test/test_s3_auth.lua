local auth = require "resty.s3_auth"

--AWSAccessKeyId	THE_ACCESS_KEY_ID
--AWSSecretAccessKey	THE_SECRET_ACCESS_KEY
-- 20130524T000000Z
local AWSAccessKeyId='THE_ACCESS_KEY_ID'
local AWSSecretAccessKey='THE_SECRET_ACCESS_KEY'
local aws_bucket = "examplebucket"
local aws_region = "us-east-1"

local function datetime_cb()
	local date = "20130524"
	local time = "000000"
	local datetime = date .. "T" .. time .. "Z"
	return date, time, datetime
end

-- aws_access_key, aws_secret_key, aws_bucket, aws_region, datetime_cb
local s3_sign = auth:new(AWSAccessKeyId, AWSSecretAccessKey, aws_bucket, aws_region, datetime_cb)

--- GET OBJECT
local headers = {}
headers["x-amz-date"] = "20130524T000000Z"
headers["Range"] = "bytes=0-9"
headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
local auth, sign = s3_sign:authorization_v4("GET", "/test.txt", headers, "")
ngx.say("get test ok:", sign == "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
ngx.say("get auth test ok:", auth == "AWS4-HMAC-SHA256 Credential=THE_ACCESS_KEY_ID/20130524/us-east-1/s3/aws4_request,SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")

--- PUT OBJECT
local headers = {}
headers["x-amz-date"] = "20130524T000000Z"
headers["Date"] = "Fri, 24 May 2013 00:00:00 GMT"
headers["x-amz-storage-class"] = "REDUCED_REDUNDANCY"
headers["x-amz-content-sha256"] = "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072"
local auth, sign = s3_sign:authorization_v4("PUT", "test$file.text", headers, "Welcome to Amazon S3.")
ngx.say("put test ok:", sign == "98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd")
ngx.say("put auth test ok:", auth == "AWS4-HMAC-SHA256 Credential=THE_ACCESS_KEY_ID/20130524/us-east-1/s3/aws4_request,SignedHeaders=date;host;x-amz-content-sha256;x-amz-date;x-amz-storage-class,Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd")

--- GET LIFECYCLE
local headers = {}
headers["x-amz-date"] = "20130524T000000Z"
headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

local auth, sign = s3_sign:authorization_v4("GET", "?lifecycle", headers, "")
ngx.say("get lifecycle test ok:", sign == "fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543")
ngx.say("get lifecycle auth test ok:", auth == "AWS4-HMAC-SHA256 Credential=THE_ACCESS_KEY_ID/20130524/us-east-1/s3/aws4_request,SignedHeaders=host;x-amz-content-sha256;x-amz-date,Signature=fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543")

--- Get Bucket 
local headers = {}
headers["x-amz-date"] = "20130524T000000Z"
headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

local auth, sign = s3_sign:authorization_v4("GET", "?max-keys=2&prefix=J", headers, "")
ngx.say("get bucket list test ok:", sign == "34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7")
ngx.say("get bucket list auth test ok:", auth == "AWS4-HMAC-SHA256 Credential=THE_ACCESS_KEY_ID/20130524/us-east-1/s3/aws4_request,SignedHeaders=host;x-amz-content-sha256;x-amz-date,Signature=34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7")
