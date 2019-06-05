
local sha2 = require "resty.sha2"
local util = require "resty.s3_util"

local NEW_LINE = "\n"

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function (narr, nrec) return {} end
end

local function get_datetime()
    local datetime = ngx.utctime()
    local m, err = ngx.re.match(datetime, "(\\d{4})-(\\d{2})-(\\d{2}) (\\d{2}):(\\d{2}):(\\d{2})")
    if err == nil and (type(m)=='table' and #m == 6) then
        local date = m[1] .. m[2] .. m[3]
        local time = m[4] .. m[5] .. m[6]
        return date, time, date .. "T" .. time .. "Z"
    else
        local datetime = os.date("!%Y%m%dT%H%M%S")
        local x = string.find(datetime, 'T')
        local date, time = string.sub(datetime, 1, x-1), string.sub(datetime, x+1)
        return date, time, date .. "T" .. time .. "Z"
    end
end

local _M = new_tab(0, 100)
_M._VERSION = '0.01'

local hmac_sha256 = util.hmac_sha256

local mt = { __index = _M }

function _M:new(aws_access_key, aws_secret_key, aws_bucket, aws_region, datetime_cb)
    if not aws_access_key then
        return nil, "must provide aws_access_key"
    end
    if not aws_secret_key then
        return nil, "must provide aws_secret_key"
    end
    if not aws_bucket then
        return nil, "must provide aws_bucket"
    end

    if not aws_region then
        aws_region = "ap-southeast-1"
    end
    if datetime_cb == nil then
        datetime_cb = get_datetime
    end
    local cd = nil

    return setmetatable({ aws_access_key = aws_access_key, aws_secret_key = aws_secret_key, 
                        aws_bucket=aws_bucket, aws_region=aws_region, aws_service = "s3",
                        datetime_cb = datetime_cb}, mt)
end

local function uri_encode(arg, encodeSlash, cd)
    return util.uri_encode(arg, encodeSlash, cd)
end

local function URI_ENCODE(arg, cd)
    --ngx.log(ngx.INFO, "----------------- cd:", type(cd))
    return uri_encode(arg, false, cd)
end

local function parse_args(args)
    local kv_args = {}
    for arg in string.gmatch(args, "[^&]+") do
        local x = string.find(arg, "=")
        local key, value = nil, nil
        if x then -- 包含值
            key = string.sub(arg, 1, x-1)
            value = string.sub(arg, x+1)
        else -- 不包含值。
            key = arg
            value = ""
        end
        if kv_args[key] then
            local values = kv_args[key]
            if type(values) ~= 'table' then
                values = {values}
            end
            table.insert(values,value)
            value = values
        end
        kv_args[key] = value
    end

    return kv_args
end

local function _query_string(args, cd)
    if args == nil then
        return ""
    end
    args = parse_args(args)

    local keys = {}
    for key, _ in pairs(args) do 
        table.insert(keys, key)
    end
    table.sort(keys)
    local key_values = {}
    for _, key in ipairs(keys) do 
        local value = args[key]
        if type(value) == 'table' then
            -- TODO: value是否要排序。
            table.sort(value)
            for _, value_sub in ipairs(value) do 
                table.insert(key_values, uri_encode(key, true, cd) .. "=" .. uri_encode(value_sub, true, cd))
            end
        else
            table.insert(key_values, uri_encode(key, true, cd) .. "=" .. uri_encode(value, true, cd))
        end
    end
    return table.concat(key_values, "&")
end

local function startswith(str,startstr)
   return startstr=='' or string.sub(str,1, string.len(startstr))==startstr
end
local function endswith(str,endstr)
   return endstr=='' or string.sub(str,-string.len(endstr))==endstr
end

local function uri2short(uri)
    if startswith(uri, "http://") then
        local first = string.find(uri, "/", 8)
        if first then
            uri = string.sub(uri, first)
        end
    elseif startswith(uri, "https://") then
        local first = string.find(uri, "/", 9)
        if first then
            uri = string.sub(uri, first)
        end
    end
    if uri and string.sub(uri, 1,1) ~= "/" then
        uri = "/" .. uri
    end
    -- 处理: // --> /
    uri = string.gsub(uri, "//", "/")
    -- 处理: /./ --> / 以./结尾的，去掉。
    uri = string.gsub(uri, "/%./", "/")


    -- 处理：/path/to/../.. --> /
    local relatives = 0
    for i = 1, 16 do 
        if uri and endswith(uri, "/..") then
            uri = string.sub(uri, 1, #uri-3)
            relatives = i
        else
            break
        end 
    end

    for i = 1, relatives do
        local slash_pos = uri:reverse():find("/")
        if slash_pos then
            local pos = #uri - slash_pos
            uri = string.sub(uri, 1, pos)
        end
    end
    if uri == "" then
        uri = "/"
    end
    return uri
end

local function trim (s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function proc_headers(headers)
    local t = headers
    local headers_lower = {}
    local signed_headers = {}
    local header_values = {}
    local all_normal_headers = {host=true, ["content-type"]=true, ["content-md5"]=true, range=true, date=true}
    for k,v in pairs(t) do 
        k = string.lower(k)
        if type(v) == 'table' then
            table.sort(v)
            v = table.concat(v, ",")
        end
        --ngx.log(ngx.INFO, "HEADER>", k, ":", v)
        --if all_normal_headers[k] or startswith(k, "x-amz-") then
            table.insert(signed_headers, k)
            headers_lower[k] = v
            --ngx.log(ngx.INFO, "key:", k, " added ..")
        --end
    end
    table.sort(signed_headers)
    for _, k in ipairs(signed_headers) do 
        table.insert(header_values, k .. ":" .. trim(headers_lower[k]) .. '\n')
    end
    return table.concat(header_values), table.concat(signed_headers, ";")
end

-- Task 1: Create a Canonical Request
local function create_canonical_request(req)
    -- http://docs.aws.amazon.com/zh_cn/AmazonS3/latest/API/sig-v4-header-based-auth.html
    --[[
    <HTTPMethod>\n
    <CanonicalURI>\n
    <CanonicalQueryString>\n
    <CanonicalHeaders>\n
    <SignedHeaders>\n
    <HashedPayload>
    HTTPMethod: HTTP请求的方法，包括：GET, PUT, HEAD, and DELETE。
    CanonicalURI: 请求URI，从域名(或端口)后的部分，直到?号出现的部分。 /不需要转义。
    CanonicalQueryString: 请求参数列表，需要按参数名排序。
    CanonicalHeaders: 请求头列表，需要按请求头排序。请求头必须包含：host, content-type, x-amz-*
    SignedHeaders: 已经签名的请求头名称，要求排序。使用分号分割。
    HashedPayload: 计算Body的Hex(Sha256())值。
    ]]
    local uri, args = util.short_url_parse(req.url)

    local header_str, signed_headers = proc_headers(req.headers)
    local hashed_payload = req.content_sha256
    local requestStr =  req.method .. NEW_LINE .. 
                        URI_ENCODE(uri, req.cd) .. NEW_LINE .. 
                        _query_string(args, req.cd) .. NEW_LINE ..
                         header_str .. NEW_LINE .. 
                         signed_headers .. NEW_LINE .. 
                         hashed_payload
    ngx.log(ngx.INFO, "Canonical Request[[[\n", requestStr, "\n]]]")

    return requestStr, signed_headers
end

-- Task 2: Create a String to Sign
local function create_string_to_sign(req, aws_region, aws_service, date, time)
    --[[
    "AWS4-HMAC-SHA256" + "\n" +
    timeStampISO8601Format + "\n" +
    <Scope> + "\n" +
    Hex(SHA256Hash(<CanonicalRequest>))
    ]]
    local algorithm = "AWS4-HMAC-SHA256"
    local timeStampISO8601Format = date .. "T" .. time .. "Z"
    local scope = string.format("%s/%s/%s/aws4_request", date, aws_region, aws_service)
    
    local request, signed_headers = create_canonical_request(req)
    local sha265hash_of_request = sha2.sha256(request)
    
    local string_to_sign =  algorithm .. NEW_LINE ..
                            timeStampISO8601Format .. NEW_LINE .. 
                            scope .. NEW_LINE .. 
                            sha265hash_of_request
    ngx.log(ngx.INFO, "String to Sign:[[[\n", string_to_sign, "\n]]]")

    return string_to_sign, {algorithm=algorithm, scope=scope, signed_headers=signed_headers, request=request}
end

-- Task 3: Calculate Signature
-- req is a table ,contains: {method=method, url=url, headers=headers, body=body}
local function calculate_sign(req, secret_access_key, aws_region, aws_service, date, time)
    --[[
    DateKey              = HMAC-SHA256("AWS4"+"<SecretAccessKey>", "<yyyymmdd>")
    DateRegionKey        = HMAC-SHA256(<DateKey>, "<aws-region>")
    DateRegionServiceKey = HMAC-SHA256(<DateRegionKey>, "<aws-service>")
    SigningKey           = HMAC-SHA256(<DateRegionServiceKey>, "aws4_request")
    ]]
   
    local date_key = hmac_sha256("AWS4" .. secret_access_key, date)
    local date_region_key = hmac_sha256(date_key, aws_region) 
    local signing_key = hmac_sha256(hmac_sha256(date_region_key, aws_service), "aws4_request")
    local string_to_sign, extinfo = create_string_to_sign(req, aws_region, aws_service, date, time)
    extinfo.string_to_sign = string_to_sign
    return hmac_sha256(signing_key, string_to_sign, true), extinfo
end

-- 实现 http://docs.aws.amazon.com/zh_cn/AmazonS3/latest/API/sig-v4-header-based-auth.html 中的签名算法。
function _M:sign_v4(method, url, headers, content_sha256, date, time)
    -- headers["Host"] = self.aws_bucket .. ".s3.amazonaws.com"
    local aws_service = self.aws_service
    if not headers["Host"] then
        headers["Host"] = self.aws_bucket .. ".s3.amazonaws.com"
    else
        local host = headers.host
        local idx = string.find(host, "%.")
        if idx then
            aws_service = string.sub(host, 1, idx-1)
        end
        ngx.log(ngx.INFO, "aws_service: ", aws_service)
    end
    url = uri2short(url)

    local req = {method=method, url=url, headers=headers, content_sha256=content_sha256, cd=self.cd}
    local signature, extinfo = calculate_sign(req, self.aws_secret_key, self.aws_region, aws_service, date, time)
    extinfo.url = url
    return signature, extinfo
end

function _M:authorization_v4(method, url, headers, body)
    local date, time, datetime = self.datetime_cb()
    local content_sha256 = sha2.sha256(body or "")
    headers["x-amz-content-sha256"] = content_sha256
    headers["x-amz-date"] = datetime
    return _M.authorization_v4_internal(self, method, url, headers)
end

function _M:authorization_v4_4test(method, url, headers, body)
    local date, time, datetime = self.datetime_cb()
    local content_sha256 = sha2.sha256(body or "")
    --headers["x-amz-content-sha256"] = content_sha256
    --headers["x-amz-date"] = datetime
    return _M.authorization_v4_internal(self, method, url, headers, content_sha256)
end

local function get_date_and_time_s3(datetime)
    if not datetime then
        return nil
    end
    --20130524T000000Z
    local ti = string.find(datetime, "T")
    if ti then
        local zi = string.find(datetime, "Z", ti-1)
        if zi then
            return string.sub(datetime, 1, ti-1), string.sub(datetime, ti+1, zi-1)
        end
        return nil
    end
    return nil
end

--[[
extinfo structure:
algorithm
scope
signed_headers
request
string_to_sign
signature
authorization
url 最终请求的url(不包含域名端口部分)
]]
function _M:authorization_v4_internal(method, url, headers, content_sha256)
    --local datetime = date .. "T" .. time .. "Z"
    local content_sha256 = headers["x-amz-content-sha256"] or content_sha256 or sha2.sha256("")
    local datetime = headers["x-amz-date"]
    local date, time = nil, nil
    if datetime then
        date, time = get_date_and_time_s3(datetime)
        if date == nil then
            date, time, datetime = self.datetime_cb()
            headers["x-amz-date"] = datetime
        end
    else
        -- datetime = headers["date"]
        -- local t = ngx.parse_http_time(datetime)
        -- if t ~= nil then
        --     --  {year=2005, month=11, day=6, hour=22,min=18,sec=30}
        --     t = os.date("!*t",t)
        --     date = string.format("%04d%02d%02d", t.year, t.month, t.day)
        --     time = string.format("%02d%02d%02d", t.hour, t.min, t.sec)
        -- else
            headers["date"] = nil
            date, time, datetime = self.datetime_cb()
            headers["x-amz-date"] = datetime
        -- end
    end
    local signature, extinfo = _M.sign_v4(self, method, url, headers, content_sha256, date, time)
    local algorithm, scope, signed_headers = extinfo.algorithm, extinfo.scope, extinfo.signed_headers

    --[[
    AWS4-HMAC-SHA256 Credential=THE_ACCESS_KEY_ID/20130524/us-east-1/s3/aws4_request, 
    SignedHeaders=host;range;x-amz-date,
    Signature=fe5f80f77d5fa3beca038a248ff027d0445342fe2855ddc963176630326f1024
    ]]
    local authorization = string.format("%s Credential=%s/%s, SignedHeaders=%s, Signature=%s", 
                                    algorithm, self.aws_access_key, scope, signed_headers, signature)

    headers["Authorization"] = authorization
    extinfo.signature = signature
    extinfo.authorization = authorization
    return authorization, signature, extinfo
end


return _M
