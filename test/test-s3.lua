local awss3 = require "resty.s3"
local cjson = require "cjson"
local test = require "resty.iresty_test"
local tb = test.new({unit_name="amazon_s3_test"})

local AWSAccessKeyId='THE_ACCESS_KEY_ID'
local AWSSecretAccessKey="THE_SECRET_ACCESS_KEY"
local aws_bucket = "def"

function tb:init()
	local host = '127.0.0.1:9000' -- minio for test.
	self.s3 = awss3:new(AWSAccessKeyId, AWSSecretAccessKey, aws_bucket, {timeout=1000*10, host=host})
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
		error("s3:list failed! resp:" .. tostring(files))
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
			error("s3:list(" .. dir .. ") failed! resp:" .. tostring(files))
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
tb:run()

-- bench units test
-- test:bench_run()
