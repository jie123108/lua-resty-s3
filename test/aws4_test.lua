local awss3auth = require "resty.s3_auth"
local cjson = require "cjson"
local xml = require "resty.s3_xml"
local util = require "resty.s3_util"
local tb    = require "resty.iresty_test"
local test = tb.new({unit_name="amazon_s3_test"})

local AWSAccessKeyId='THE_ACCESS_KEY_ID'
local AWSSecretAccessKey="THE_SECRET_ACCESS_KEY"
local aws_bucket = "test"
local aws_region = "us-east-1"
local aws4_testsuite_dir = "/root/work/lua-resty-s3/test/aws4_testsuite"
local debug_file = false
local aws4_debugfile_dir = "/root/work/lua-resty-s3/test/aws4_debug"

local function datetime_cb()
	local date = "20110909"
	local time = "233600"
	local datetime = date .. "T" .. time .. "Z"
	return date, time, datetime
end

function tb:init()
	self.s3_auth = awss3auth:new(AWSAccessKeyId, AWSSecretAccessKey, aws_bucket, aws_region)
end

--------------------------------------------------------
--------------------------------------------------------

function split(s, delimiter)
    local result = {};
    for match in string.gmatch(s, "[^"..delimiter.."]+") do
        table.insert(result, match);
    end
    return result;
end


function split_line(s)
	local delimiter = "\n"
    local result = {};
    for match in string.gmatch(s, "[^"..delimiter.."]*" .. delimiter) do
		match = string.sub(match, 1, #match-1)
        table.insert(result, match);
		if match == "" then
			local idx = string.find(s, delimiter .. delimiter)
			if idx then
				local body = string.sub(s, idx + 2)
				table.insert(result, body)
			end
			break
		end
    end
    return result;
end

function trim (s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function parse_req_line(req_line)
	local space_idx = string.find(req_line, " ")
	if not space_idx then
		return false
	end
	local method = string.sub(req_line, 1, space_idx-1)

	local last_space_pos = req_line:reverse():find(" ")
	last_space_pos = #req_line - last_space_pos + 1
	local url = string.sub(req_line, space_idx+1, last_space_pos-1)
	local http_ver = string.sub(req_line, last_space_pos+1)
	return true, method, url, http_ver
end

local function parse_req(req)
	local arr = split_line(req)
	local req_line = arr[1]
	--[[
	local req_line = split(arr[1], " ")
	if #req_line ~= 3 then
		error("req_line [" .. arr[1] .. "] invalid ")
	end
	local method = req_line[1]
	local url = req_line[2]
	local http_ver = req_line[3]
	]]
	local ok, method, url, http_ver = parse_req_line(req_line)
	if not ok then
		error("req_line [" .. req_line .. "] invalid ")
	end
	local headers = util.new_headers()

	local body_idx = 2
	for i, head in ipairs(arr) do
		if i >= 2 then
			if head == "" or head == nil then
				body_idx = i + 1
				break
			end
			local idx = string.find(head, ":")
			if idx == nil then
				ngx.log(ngx.ERR, "----invalid HEAD:", head)
			else
				local key = string.lower(string.sub(head, 1, idx-1))
				local value = trim(string.sub(head, idx+1))
				if headers[key] == nil then
					headers[key] = value
				else
					local old_value = headers[key]
					local values = nil
					if type(old_value) == 'table' then
						values = old_value
					else
						values = {old_value}
					end
					table.insert(values, value)
					headers[key] = values
				end
			end
		end
	end

	local body = nil
	if body_idx > #arr then
		body = ""
	else
		local body_lines = {}
		for i = body_idx, #arr do
			table.insert(body_lines, arr[i])
		end
		body = table.concat(body_lines, "\n")
	end
	return {method=method, url=url, headers=headers, body=body}
end

--------------------------------------------

function file_read(filename)
	local file = io.open(filename, "r")
	if file == nil then
		return false, "not-exist"
	end
	local content = file:read("*a")
	file:close()
	return true, content
end

local function file_write(filename, content)
	local file = io.open(filename, "w")
	if file == nil then
		return false, "not-exist"
	end
	local content = file:write(content)
	file:close()
	return true
end

local function write_debug_file(filename, content)
	if not debug_file then
		return
	end
	local fullfilename = aws4_debugfile_dir  .. "/" .. filename
	file_write(fullfilename, content)
end


function tb:_s3_auth_v4_test(data, filename)
	local req_str = data.req 
	local req = parse_req(req_str)
	local auth, sign, extinfo = self.s3_auth:authorization_v4_4test(req.method, req.url, req.headers, req.body)
	if extinfo.request == data.creq then
		self.log(filename .. " creq OK")
	else
		write_debug_file(filename .. ".creq", extinfo.request)
		error(filename .. " creq error! cale creq [\n" .. extinfo.request .. "\n] ok creq [\n" .. data.creq .. "\n]")
	end
	if extinfo.string_to_sign == data.sts then
		self.log("sts OK")
	else
		write_debug_file(filename .. ".sts", extinfo.string_to_sign)
		error(filename .. " sts error! cale sts [\n" .. extinfo.string_to_sign .. "\n] ok sts [\n" .. data.sts .. "\n]")
	end
	if extinfo.authorization == data.authz then
		self.log("authz OK")
	else
		write_debug_file(filename .. ".authz", extinfo.authorization)
		error(filename .. " sts error! cale authz [\n" .. extinfo.authorization .. "\n] ok authz [\n" .. data.authz .. "\n]")
	end
end


function read_data(filename)
	local suffixs = {"req", "creq", "sts", "authz", "sreq"}
	local data = {}
	for _, suffix in ipairs(suffixs) do 
		local fullfilename = filename .. "." .. suffix
		local ok, content = file_read(fullfilename)
		if not ok then
			error("file [" .. fullfilename .. "] not exist!")
			return ok, content
		end
		content = string.gsub(content, "\r\n", "\n")
		data[suffix] = content
		--ngx.log(ngx.INFO, "-----", suffix, ">>>>", content)
	end
	return true, data
end

function tb:_file_test(filename)
	local dir = aws4_testsuite_dir
	local fullfilename = dir .. "/" .. filename
	local ok, data = read_data(fullfilename)
	if not ok then
		error("file test [" .. filename .."] failed! err:" .. data)
		return
	end
	self:_s3_auth_v4_test(data, filename)
	self:log("test [" .. filename .."] OK")
end

---- shell 生成的代码。
--[[ 
cd aws4_testsuite && find . | grep -v "txt" | awk -F[/\.] '{print $3}' | uniq |awk '
{fn=$1;gsub(/-/,"_",$1);
printf("function tb:test_%s()\n    self:_file_test(\"%s\")\nend\n\n", $1, fn);}'
]]


function tb:test_get_header_key_duplicate()
        self:_file_test("get-header-key-duplicate")
end

function tb:test_get_header_value_order()
        self:_file_test("get-header-value-order")
end

function tb:test_get_header_value_trim()
        self:_file_test("get-header-value-trim")
end

function tb:test_get_relative_relative()
        self:_file_test("get-relative-relative")
end

function tb:test_get_relative()
        self:_file_test("get-relative")
end

function tb:test_get_slash_dot_slash()
        self:_file_test("get-slash-dot-slash")
end

function tb:test_get_slash_pointless_dot()
        self:_file_test("get-slash-pointless-dot")
end

function tb:test_get_slash()
        self:_file_test("get-slash")
end

function tb:test_get_slashes()
        self:_file_test("get-slashes")
end

function tb:test_get_space()
        self:_file_test("get-space")
end

function tb:test_get_unreserved()
        self:_file_test("get-unreserved")
end

function tb:test_get_utf8()
        self:_file_test("get-utf8")
end

function tb:test_get_vanilla_empty_query_key()
        self:_file_test("get-vanilla-empty-query-key")
end

function tb:test_get_vanilla_query_order_key_case()
        self:_file_test("get-vanilla-query-order-key-case")
end

function tb:test_get_vanilla_query_order_key()
        self:_file_test("get-vanilla-query-order-key")
end

function tb:test_get_vanilla_query_order_value()
        self:_file_test("get-vanilla-query-order-value")
end

function tb:test_get_vanilla_query_unreserved()
        self:_file_test("get-vanilla-query-unreserved")
end

function tb:test_get_vanilla_query()
        self:_file_test("get-vanilla-query")
end

function tb:test_get_vanilla_ut8_query()
        self:_file_test("get-vanilla-ut8-query")
end

function tb:test_get_vanilla()
        self:_file_test("get-vanilla")
end

function tb:test_post_header_key_case()
        self:_file_test("post-header-key-case")
end

function tb:test_post_header_key_sort()
        self:_file_test("post-header-key-sort")
end

function tb:test_post_header_value_case()
        self:_file_test("post-header-value-case")
end

function tb:test_post_vanilla_empty_query_value()
        self:_file_test("post-vanilla-empty-query-value")
end

--[[
function tb:test_post_vanilla_query_nonunreserved()
        self:_file_test("post-vanilla-query-nonunreserved")
end

function tb:test_post_vanilla_query_space()
        self:_file_test("post-vanilla-query-space")
end
]]

function tb:test_post_vanilla_query()
        self:_file_test("post-vanilla-query")
end

function tb:test_post_vanilla()
        self:_file_test("post-vanilla")
end

function tb:test_post_x_www_form_urlencoded_parameters()
        self:_file_test("post-x-www-form-urlencoded-parameters")
end

function tb:test_post_x_www_form_urlencoded()
        self:_file_test("post-x-www-form-urlencoded")
end

-- units test
test:run()

-- bench units test
-- test:bench_run()

