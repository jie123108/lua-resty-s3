local util = require "resty.s3_util"
local cjson = require "cjson"
local xml = require "resty.s3_xml"

local _M = {}
_M._VERSION = '0.01'

local mt = { __index = _M }

--[[
startResult is a table that return by start multi upload.
"Bucket":"the-bucket","Key":"the/file/path","UploadId":"the-upload-id"}
]]

function _M:new(auth, host, timeout, startResult)
	local bucket = startResult.Bucket
	local key = startResult.Key
    local upload_id = startResult.UploadId
    local add_bucket_to_uri = false
    if not util.endswith(host, ".amazonaws.com") then
        add_bucket_to_uri = true
        key = bucket .. "/" .. key
    end
    return setmetatable({ auth=auth, bucket=bucket, key=key, upload_id = upload_id, host=host, add_bucket_to_uri=add_bucket_to_uri, timeout=timeout, parts={}}, mt)
end

function _M:upload(part_number, value)
    local short_uri = '/' .. self.key .. "?partNumber=" .. tostring(part_number) .. "&uploadId=" .. self.upload_id
    local myheaders = util.new_headers()
    local authorization = self.auth:authorization_v4("PUT", short_uri, myheaders, value)
    -- 默认该模块为上传失败。
    self.parts[part_number] = "error"
    local url = "http://" .. self.host .. short_uri
    ngx.log(ngx.INFO, "----- url: ", url)
    -- TODO: check authorization.
    local res, err, req_debug = util.http_put(url, value, myheaders, self.timeout)
    if not res then
        ngx.log(ngx.ERR, "fail request to aws s3 service: [ ", req_debug, " ] err: ", err)
        return false, "request to aws s3 failed", 500
    end

    ngx.log(ngx.INFO, "aws s3 request:", req_debug, ", status:", res.status, ",body:", tostring(res.body))

    if res.status ~= 200 then
        ngx.log(ngx.ERR, "request [ ", req_debug, " ] failed! status:", res.status, ", body:", tostring(res.body))
        return false, res.body or "request to aws s3 failed", res.status
    end

    local ETag = res.headers["ETag"]
    if ETag == nil then
    	ngx.log(ngx.ERR, "request [ ", req_debug, " ] failed! Response Header 'ETag' missing!")
    	return false, "ETag missing", 200
    end

    ngx.log(ngx.INFO, "aws return partNumber [", part_number, "] ETag [", ETag, "]")
    self.parts[part_number] = ETag

    return true, ETag
end

function _M:complete()
    local short_uri = '/' .. self.key .. "?uploadId=" .. self.upload_id

    local parts = {}
    for part_number, ETag in ipairs(self.parts) do 
    	if ETag == "error" then
    		ngx.log(ngx.ERR, "part [", part_number, "] upload failed! you must be reupload this part or abort the whole upload")
    		return false, "some-part-failed"
    	end
    	local part = {PartNumber=part_number, ETag=ETag}
    	table.insert(parts, part)
    end
    local body = {CompleteMultipartUpload={Part=parts}}
    body = xml.dumps(body)
    ngx.log(ngx.INFO, "---- complete body ...[", body, "]")

    local myheaders = util.new_headers()
    local authorization = self.auth:authorization_v4("POST", short_uri, myheaders, body)

    local url = "http://" .. self.host .. short_uri
    ngx.log(ngx.INFO, "----- url: ", url)
    -- TODO: check authorization.
    local res, err, req_debug = util.http_post(url, body, myheaders, self.timeout)
    if not res then
        ngx.log(ngx.ERR, "fail request to aws s3 service: [ ", req_debug, " ] err: ", err)
        return false, "request to aws s3 failed", 500
    end

    ngx.log(ngx.INFO, "aws s3 request:", req_debug, ", status:", res.status, ",body:", tostring(res.body))

    if res.status ~= 200 then
        ngx.log(ngx.ERR, "request [ ", req_debug, " ] failed! status:", res.status, ", body:", tostring(res.body))
        return false, res.body or "request to aws s3 failed", res.status
    end
	local doc, err = xml.loads(res.body)
    if doc == nil then
        return false, "xml-invalid", 500
    end

    return true, doc
end

function _M:abort()
    local short_uri = '/' .. self.key .. "?uploadId=" .. self.upload_id
    
    local myheaders = util.new_headers()
    local authorization = self.auth:authorization_v4("DELETE", short_uri, myheaders, body)

    local url = "http://" .. self.host .. short_uri
    ngx.log(ngx.INFO, "----- url: ", url)
    -- TODO: check authorization.
    local res, err, req_debug = util.http_del(url, myheaders, self.timeout)
    if not res then
        ngx.log(ngx.ERR, "fail request to aws s3 service: [ ", req_debug, " ] err: ", err)
        return false, "request to aws s3 failed", 500
    end

    ngx.log(ngx.INFO, "aws s3 request:", req_debug, ", status:", res.status, ",body:", tostring(res.body))

    if res.status ~= 204 then
        ngx.log(ngx.ERR, "request [ ", req_debug, " ] failed! status:", res.status, ", body:", tostring(res.body))
        return false, res.body or "request to aws s3 failed", res.status
    end
	
    return true, res.body
end

return _M