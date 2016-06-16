local awss3 = require "resty.s3"
local cjson = require "cjson"
local tb    = require "resty.iresty_test"
local test = tb.new({unit_name="amazon_s3_test"})

local AWSAccessKeyId='THE_ACCESS_KEY_ID'
local AWSSecretAccessKey="THE_SECRET_ACCESS_KEY"
local aws_bucket = "lxj-xjp"
--local aws_bucket = "lxj-us1"
local function bigstring(x)
	local tmp = string.rep(x, 1023) .."\n"
	return string.rep(tmp, 1024*6)
end

function tb:init()
	self.s3 = awss3:new(AWSAccessKeyId, AWSSecretAccessKey, aws_bucket, {timeout=1000*10})
	self.filenames = {"/testdir/standard.txt","/testdir/我的文件.txt", "testdir/no_first_slash.txt", "blankfile", "中文文件名.doc", "中文目录/中文.doc"}
	self.contents = {"standard standard", "我的文件", "no_first_slash no_first_slash", "", "中文文件 中文文件", "中文目录里面的文件"}
end

function tb:test_01put()
	for i =1,#self.filenames do 
		local filename = self.filenames[i]
		local content = self.contents[i]
		local ok, resp = self.s3:put(filename, content)
		if not ok then
			error("save [" .. content .. "] to [" .. filename .. "] failed! resp:" .. tostring(resp))
		end
	end
    self.log("PUT OK")
end

function tb:test_02get()
	for i =1,#self.filenames do 
		local filename = self.filenames[i]
		local content_ok = self.contents[i]
		local ok, content = self.s3:get(filename)
		if not ok then
			error("get [" .. filename .. "] content failed! resp:" .. tostring(content))
		end
		if content_ok ~= content then
			error("file [" .. filename .."] content [" .. content .."] ~= ok_content [" .. content_ok .."]")
		end
	end
    self.log("GET OK")
end

local function first_dir(filename)
	local i = string.find(filename, "/")
	if not i then
		return nil
	end
	return string.sub(filename, 1, i-1)
end

function tb:test_03list()
	local ok, files = self.s3:list("")
	if not ok then
		error("s3:list failed! resp:" .. tostring(content))
	end
	local dirs = {}
	for i =1,#self.filenames do 
		local filename = self.filenames[i]
		if string.sub(filename, 1, 1) == "/" then
			filename = string.sub(filename, 2)
		end
		local dir = first_dir(filename)
		if dir then
			table.insert(dirs, dir)
		end
	end
	for _,dir in ipairs(dirs) do 
		local ok, files = self.s3:list(dir)
		if not ok then
			error("s3:list(" .. dir .. ") failed! resp:" .. tostring(content))
		end
	end
end

function tb:test_04delete()
	for i =1, 2 do 
		local filename = self.filenames[i]
		if i <= 2 then
			local ok, err = self.s3:delete(filename)
			if not ok then
				error("delete [" .. filename .. "] failed! resp:" .. tostring(err))
			end
		end
	end
	local dels = {}
	for i=3, #self.filenames do 
		table.insert(dels, self.filenames[i])
	end
	local ok ,err = self.s3:deletes(dels)
	if not ok then
		error("deletes [" .. table.concat(dels, ",") .. "] failed! resp:" .. tostring(err))
	end

	for i =1,#self.filenames do 
		local filename = self.filenames[i]
		
		local ok, content = self.s3:get(filename)
		if not ok and content == "not-exist" then

		else
			error("file [" .. filename .. "] delete failed! ok:" .. tostring(ok).. " .. content:"..tostring(content))
		end
	end

    self.log("DELETE OK")
end

-- units test
--test:run()

-- bench units test
-- test:bench_run()


s3 = awss3:new(AWSAccessKeyId, AWSSecretAccessKey, aws_bucket, {timeout=1000*10})
local ok, resp = s3:list("/", nil,10240)
print("ok:", ok)
print("resp:", cjson.encode(resp))

--[[
s3 = awss3:new(AWSAccessKeyId, AWSSecretAccessKey, aws_bucket, {timeout=1000*60*10})
local filename = ngx.var.arg_filename or "multi/001.doc"

local ok, upload = s3:start_multi_upload(filename)
if not ok then
	ngx.say("start_multi_upload [" .. aws_bucket .. "." .. filename .. "] failed! resp:" .. tostring(resp))
else
	ngx.say("start_multi_upload [" .. aws_bucket .. "." .. filename .. "] ok")
end

ngx.say(upload:upload(1, bigstring('a')))

ngx.say(upload:upload(2, bigstring('b')))
ngx.say(upload:upload(3, bigstring('c')))
local ok, err = upload:complete()
if ok then
	ngx.say("upload [", filename, "] success!")
else
	ngx.say("upload [", filename, "] failed! err:", err)
	local ok, err = upload:abort()
	ngx.say("abort ok:", ok)
	ngx.say("abort err:", err)
end
]]

--[[
local ok, content = s3:get(filename)
ngx.say("ok:", ok)
ngx.say("content:", content)

local ok, files = s3:list("中文目录")
ngx.say("ok:", ok)
ngx.say("files:", cjson.encode(files))
]]

--[[
local filename = "/file003"
s3:put(filename, "file 003 content")
local ok, content = s3:get(filename)
ngx.say("file content:", content)

local ok, body = s3:delete(filename)
ngx.say("s3:delete: ok:", ok, " body:", tostring(body))
local ok, content = s3:get(filename)
ngx.say("s3:get ok:", ok, ", content:", content)


for i=1,10 do 
	local filename = "/rootfile-" .. tostring(i)
	local filecontent = "file " .. tostring(i) .. " content ..."
	local ok, content = s3:put(filename, filecontent)
	ngx.say("ok:", ok, ", content:", content)
end

local ok, files = s3:list("", nil, 5, "dir/file003")
ngx.say("ok:", ok)
ngx.say("files:", cjson.encode(files))


local ids = {}
for i=1,4 do 
	local filename = "rootfile-" .. tostring(i)
	local filecontent = "file " .. tostring(i) .. " content ..."
	local ok, resp = s3:put(filename, filecontent)
	ngx.say("ok:", ok, ", content:", resp)

	table.insert(ids, filename)
end

local ok, resp = s3:deletes(ids, false)
ngx.say("ok:", ok)
ngx.say("resp:", cjson.encode(resp))


for _, id in ipairs(ids) do 
	local ok, content = s3:get(id)
	ngx.say("get [", id, "] ok :", ok)
	ngx.say("get [", id, "] content :", content)
end

]]

