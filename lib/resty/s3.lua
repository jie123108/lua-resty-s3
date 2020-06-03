local util = require "resty.s3_util"
local s3_auth = require "resty.s3_auth"
local cjson = require "cjson"
local xml = require "resty.s3_xml"
local s3_multi_upload = require("resty.s3_multi_upload")

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function (narr, nrec) return {} end
end

local function proc_uri(uri)
    if uri == nil then
        return nil
    end

    if uri and string.len(uri) > 0 and string.sub(uri, 1,1) == '/' then
        uri = string.sub(uri, 2)
    end

    return uri
end

local get_bucket_region = nil

local _M = new_tab(0, 100)
_M._VERSION = '0.03'

local mt = { __index = _M }

function _M:new(aws_access_key, aws_secret_key, aws_bucket, args)
    if not aws_access_key then
        return nil, "must provide aws_access_key"
    end
    if not aws_secret_key then
        return nil, "must provide aws_secret_key"
    end
    args = args or {}

    local timeout = 5
    local aws_region = "us-east-1"
    if args and type(args) == 'table' then
        if args.timeout then
            timeout = args.timeout
        end
        if args.aws_region then
            aws_region = args.aws_region
        end
    end

    local host =  args.host or (aws_bucket .. ".s3.amazonaws.com")
    local aws_service = "s3"
    local auth = s3_auth:new(aws_access_key, aws_secret_key, aws_bucket, aws_region, aws_service, nil)
    if not args.host then
        if aws_region ~= "us-east-1" then
          host = aws_bucket .. ".s3" .. "-" .. aws_region .. ".amazonaws.com"
        end
    end
    local add_bucket_to_uri = false
    if not util.endswith(host, ".amazonaws.com") then
        add_bucket_to_uri = true
    end

    return setmetatable({ auth=auth, host=host, aws_bucket=aws_bucket, add_bucket_to_uri=add_bucket_to_uri, aws_region=aws_region,timeout=timeout}, mt)
end

function _M:get_short_uri(key)
    local short_uri = '/' .. proc_uri(key)
    if self.add_bucket_to_uri then
        short_uri = '/' .. self.aws_bucket .. short_uri
    end
    return short_uri
end

-- http://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectHEAD.html
function _M:head(key)
    local short_uri = self:get_short_uri(key)
    local myheaders = util.new_headers()
    local authorization = self.auth:authorization_v4("HEAD", short_uri, myheaders, nil)
    --ngx.log(ngx.INFO, "headers [[[", cjson.encode(myheaders), "]]]")

    -- TODO: check authorization.
    local url = "http://" .. self.host .. util.uri_encode(short_uri, false)
    local res, err, req_debug = util.http_head(url, myheaders, self.timeout)
    if not res then
        ngx.log(ngx.ERR, "fail request to aws s3 service: [", req_debug, "] err: ", err)
        return false, "request to aws s3 failed", 500
    end

    ngx.log(ngx.INFO, "aws s3 request:", url, ", status:", res.status, ",body:", tostring(res.body))

    if res.status ~= 200 then
        if res.status == 404 then
            ngx.log(ngx.INFO, "object [", key, "] not exist")
            return false, "not-exist", res.status
        else
            ngx.log(ngx.ERR, "request [ ", req_debug,  " ] failed! status:", res.status, ", body:", tostring(res.body))
            return false, res.body or "request to aws s3 failed", res.status
        end
    end

    return true, res
end

-- http://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectGET.html
function _M:get(key)
    local short_uri = self:get_short_uri(key)
    local myheaders = util.new_headers()
    local authorization = self.auth:authorization_v4("GET", short_uri, myheaders, nil)
    --ngx.log(ngx.INFO, "headers [[[", cjson.encode(myheaders), "]]]")

    -- TODO: check authorization.
    local url = "http://" .. self.host .. util.uri_encode(short_uri, false)
    local res, err, req_debug = util.http_get(url, myheaders, self.timeout)
    if not res then
        ngx.log(ngx.ERR, "fail request to aws s3 service: [", req_debug, "] err: ", err)
        return false, "request to aws s3 failed", 500
    end

    ngx.log(ngx.INFO, "aws s3 request:", url, ", status:", res.status, ",body:", tostring(res.body))

    if res.status ~= 200 then
        if res.status == 404 then
            ngx.log(ngx.INFO, "object [", key, "] not exist")
            return false, "not-exist", res.status
        else
            ngx.log(ngx.ERR, "request [ ", req_debug,  " ] failed! status:", res.status, ", body:", tostring(res.body))
            return false, res.body or "request to aws s3 failed", res.status
        end
    end

    ngx.log(ngx.INFO, "aws returned: body:", res.body)

    return true, res.body
end

-- http://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectPUT.html
function _M:put(key, value, headers)
    local short_uri = self:get_short_uri(key)
    headers = headers or util.new_headers()
    local authorization = self.auth:authorization_v4("PUT", short_uri, headers, value)

    local url = "http://" .. self.host .. util.uri_encode(short_uri, false)
    ngx.log(ngx.INFO, "----- url: ", url)
    -- TODO: check authorization.
    local res, err, req_debug = util.http_put(url, value, headers, self.timeout)
    if not res then
        ngx.log(ngx.ERR, "fail request to aws s3 service: [ ", req_debug, " ] err: ", err)
        return false, "request to aws s3 failed", 500
    end

    ngx.log(ngx.INFO, "aws s3 request:", req_debug, ", status:", res.status, ",body:", tostring(res.body))

    if res.status ~= 200 then
        ngx.log(ngx.ERR, "request [ ", req_debug, " ] failed! status:", res.status, ", body:", tostring(res.body))
        return false, res.body or "request to aws s3 failed", res.status
    end

    ngx.log(ngx.INFO, "aws returned: body: [", res.body, "]")

    return true, res.body
end

-- https://docs.aws.amazon.com/AmazonS3/latest/API/API_CopyObject.html
function _M:copy(key, source, headers)
    headers = headers or util.new_headers()
    headers["x-amz-copy-source"] = source

    return self:put(key, "", headers)
end

-- http://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectDELETE.html
function _M:delete(key)
    local short_uri = self:get_short_uri(key)
    local myheaders = util.new_headers()
    local authorization = self.auth:authorization_v4("DELETE", short_uri, myheaders, nil)
    --ngx.log(ngx.INFO, "headers [[[", cjson.encode(myheaders), "]]]")

    -- TODO: check authorization.
    local url = "http://" .. self.host .. util.uri_encode(short_uri, false)
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

    ngx.log(ngx.INFO, "aws returned: body: [", res.body, "]")

    return true, res.body
end

-- http://docs.aws.amazon.com/AmazonS3/latest/API/multiobjectdeleteapi.html
function _M:deletes(keys, quiet)
    if type(keys) ~= 'table' or #keys < 1 then
        ngx.log(ngx.ERR, "args [keys] invalid!")
        return false, "args-invalid"
    end
    local url = "http://" .. self.host .. '/?delete'
    if self.add_bucket_to_uri then
        url = "http://" .. self.host .. '/' .. self.aws_bucket .. '?delete'
    end
    local myheaders = util.new_headers()
    local Object = {}
    for _, key in ipairs(keys) do
        table.insert(Object, {Key=key})
    end
    if quiet == nil then
        quiet = true
    end
    local body = {Delete={Quiet=quiet, Object=Object}}
    body = xml.dumps(body)
    local content_md5 = ngx.encode_base64(ngx.md5_bin(body))
    myheaders["content-md5"] = content_md5
    -- ngx.log(ngx.INFO, "-----------------Content-md5:", content_md5)
    local authorization = self.auth:authorization_v4("POST", url, myheaders, body)
    --ngx.log(ngx.INFO, "headers [[[", cjson.encode(myheaders), "]]]")

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

    ngx.log(ngx.INFO, "aws returned: body:", res.body)
    local doc, err = xml.loads(res.body)
    if doc == nil then
        return false, "xml-invalid", 500
    end

    return true, doc
end

-- http://docs.aws.amazon.com/AmazonS3/latest/API/v2-RESTBucketGET.html
function _M:list(prefix, delimiter, page_size, marker)
    prefix = prefix or ""
    local args = {prefix=prefix}

    local url = "http://" .. self.host .. "/"
    if self.add_bucket_to_uri then
        url = url .. self.aws_bucket
    end
    if delimiter then
        args.delimiter = delimiter
    end
    if page_size then
        args["max-keys"] = tostring(tonumber(page_size))
    end
    if marker then
        args.marker =  tostring(marker)
    end
    url = url .. "?" .. ngx.encode_args(args)

    local myheaders = util.new_headers()
    local authorization = self.auth:authorization_v4("GET", url, myheaders, nil)
    --ngx.log(ngx.INFO, "headers [[[", cjson.encode(myheaders), "]]]")

    -- TODO: check authorization.
    local res, err, req_debug = util.http_get(url, myheaders, self.timeout)
    if not res then
        ngx.log(ngx.ERR, "fail request to aws s3 service: [", req_debug, "] err: ", err)
        return false, "request to aws s3 failed", 500
    end

    ngx.log(ngx.INFO, "aws s3 request:", url, ", status:", res.status, ",body:", tostring(res.body))

    if res.status ~= 200 then
        if res.status == 404 then
            ngx.log(ngx.INFO, "object [", prefix, "] not exist")
            return false, "not-exist", res.status
        else
            ngx.log(ngx.ERR, "request [ ", req_debug,  " ] failed! status:", res.status, ", body:", tostring(res.body))
            return false, res.body or "request to aws s3 failed", res.status
        end
    end

    ngx.log(ngx.INFO, "aws returned: body:", res.body)
    local doc, err = xml.loads(res.body)
    if doc == nil then
        return false, "xml-invalid", 500
    end
    if doc.ListBucketResult == nil then
       return false, "no-list-result", 500
    end
    return true, doc
end

-- http://docs.aws.amazon.com/AmazonS3/latest/API/mpUploadInitiate.html
function _M:start_multi_upload(key, myheaders)
    local short_uri = self:get_short_uri(key)
    local url = "http://" .. self.host .. short_uri .. "?uploads"

    myheaders = myheaders or util.new_headers()
    local authorization = self.auth:authorization_v4("POST", url, myheaders, nil)
    ngx.log(ngx.INFO, "headers [", cjson.encode(myheaders), "]")

    -- TODO: check authorization.
    local res, err, req_debug = util.http_post(url, "", myheaders, self.timeout)
    if not res then
        ngx.log(ngx.ERR, "fail request to aws s3 service: [", req_debug, "] err: ", err)
        return false, "request to aws s3 failed", 500
    end

    ngx.log(ngx.INFO, "aws s3 request:", url, ", status:", res.status, ",body:", tostring(res.body))

    if res.status ~= 200 then
        ngx.log(ngx.ERR, "request [ ", req_debug,  " ] failed! status:", res.status, ", body:", tostring(res.body))
        return false, res.body or "request to aws s3 failed", res.status
    end

    ngx.log(ngx.INFO, "aws returned: body:", res.body)
    local doc, err = xml.loads(res.body)
    if doc == nil then
        return false, "xml-invalid", 500
    end
    if type(doc.InitiateMultipartUploadResult) ~= "table" then
        return false, "xml-invalid", 500
    end
    local uploadResult = doc.InitiateMultipartUploadResult

    local upload = s3_multi_upload:new(self.auth, self.host, self.timeout, uploadResult)
    return true, upload
end

function _M:authorization_v4(method, url, headers)
    return self.auth:authorization_v4_internal(method, url, headers)
end

return _M
