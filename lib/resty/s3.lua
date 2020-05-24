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
_M._VERSION = '0.01'

local mt = { __index = _M }

function _M:new(aws_access_key, aws_secret_key, aws_bucket, args)    
    if not aws_access_key then
        return nil, "must provide aws_access_key"
    end
    if not aws_secret_key then
        return nil, "must provide aws_secret_key"
    end

    local host = aws_bucket .. ".s3.amazonaws.com"
    local timeout = 5
    local aws_region = nil
    if args and type(args) == 'table' then
        if args.timeout then
            timeout = args.timeout
        end
        if args.aws_region then
            aws_region = args.aws_region
        end
    end

    local err = nil
    if not aws_region then
        aws_region,err = get_bucket_region(aws_access_key, aws_secret_key, aws_bucket, "us-east-1", host, timeout)
        if aws_region == nil or aws_region == "" then
            ngx.log(ngx.INFO, "get_bucket_region(", aws_bucket, ") failed! err:", tostring(err))
            aws_region = "us-east-1"
        end
    end

    local auth = s3_auth:new(aws_access_key, aws_secret_key, aws_bucket, aws_region, nil)
    if aws_region == "us-east-1" then
      host = aws_bucket .. ".s3.amazonaws.com"
    else
      host = aws_bucket .. ".s3" .. "-" .. aws_region .. ".amazonaws.com"
    end
    return setmetatable({ auth=auth, host=host, aws_region=aws_region,timeout=timeout}, mt)
end

-- http://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectHEAD.html
function _M:head(key)
    local short_uri = '/' .. proc_uri(key)
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
    local short_uri = '/' .. proc_uri(key)
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
    local short_uri = '/' .. proc_uri(key)
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

-- http://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectDELETE.html
function _M:delete(key)
    local short_uri = '/' .. proc_uri(key)
    local myheaders = util.new_headers()
    local authorization = self.auth:authorization_v4("DELETE", short_uri, myheaders, value)
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
    local myheaders = util.new_headers()
    local Object = {}
    for _, key in ipairs(keys) do
        table.insert(Object, {Key=proc_uri(key, self.cd)})
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
    prefix = proc_uri(prefix)
    local url = "http://" .. self.host .. "/?prefix=" .. prefix 
    if delimiter then
        url = url .. "&delimiter=" .. delimiter
    end
    if page_size then
        url = url .. "&max-keys=" .. tostring(tonumber(page_size))
    end
    if marker then
        url = url .. "&marker=" .. tostring(marker)
    end

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

    return true, doc
end

-- http://docs.aws.amazon.com/AmazonS3/latest/API/mpUploadInitiate.html
function _M:start_multi_upload(key, myheaders)
    key = proc_uri(key)
    local url = "http://" .. self.host .. "/" .. key .. "?uploads"

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

local function get_bucket_location(s3auth, host, timeout)
    local url = "http://" .. host .. "/?location"

    local myheaders = util.new_headers()
    local authorization = s3auth:authorization_v4("GET", url, myheaders, nil)
    
    -- TODO: check authorization.
    local res, err, req_debug = util.http_get(url, myheaders, timeout)
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

    return true, doc
end

get_bucket_region = function(aws_access_key, aws_secret_key, aws_bucket, aws_region, host, timeout)
    for i = 1, 3 do
        --ngx.log(ngx.INFO, "-----", i, " get bucket region ...")
        local s3auth = s3_auth:new(aws_access_key, aws_secret_key, aws_bucket, aws_region, nil)
        local ok, doc, status = get_bucket_location(s3auth, host, timeout)
        if ok then
            if type(doc) == 'table' and doc.LocationConstraint then
                aws_region = doc.LocationConstraint
                return aws_region
            else
                ngx.log(ngx.ERR, "get bucket(", aws_bucket, ") region failed! resp body invalid:", cjson.encode(doc))
            end
        else
            local body = doc
            doc = xml.loads(body)
            if status == 400 and type(doc) == 'table' and doc.Error and doc.Error.Region then
                ngx.log(ngx.INFO, "the ok resion is: ", doc.Error.Region)
                return doc.Error.Region
            else
                ngx.log(ngx.ERR, "get bucket(", aws_bucket, ") region failed! err:", body)
                return nil, body
            end
        end
    end
end

return _M
