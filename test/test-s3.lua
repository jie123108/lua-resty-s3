local awss3 = require "resty.s3"
local util = require("resty.s3_util")
local cjson = require "cjson"
local test = require "resty.iresty_test"
local tb = test.new({unit_name="amazon_s3_test"})

local AWSAccessKeyId='THE_ACCESS_KEY_ID'
local AWSSecretAccessKey="THE_SECRET_ACCESS_KEY"
local aws_bucket = "def"
local aws_region = nil
local host = '127.0.0.1:9000' -- minio for test.

local s3_config = os.getenv("S3_CONFIG")
if s3_config then
	local configs = util.split(s3_config, ":")
	AWSAccessKeyId=configs[1]
	AWSSecretAccessKey=configs[2]
	aws_bucket = configs[3]
	if #configs >= 4 then
		aws_region = configs[4]
	end
	host = nil
end

function tb:init()
	self.s3 = awss3:new(AWSAccessKeyId, AWSSecretAccessKey, aws_bucket, {timeout=1000*10, aws_region=aws_region, host=host})
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

function tb:test_021head()
	for i =1,#self.filenames do 
		local filename = self.filenames[i]
		local ok, content = self.s3:head(filename)
		if not ok then
			error("get [" .. filename .. "] content failed! resp:" .. tostring(content))
		end
	end
    self.log("HEAD OK")
end


local function first_dir(filename)
	local i = string.find(filename, "/")
	if not i then
		return nil
	end
	return string.sub(filename, 1, i-1)
end

function tb:test_03list()
	local ok, resp = self.s3:list("")
	if not ok then
		error("s3:list failed! resp:" .. tostring(resp))
	elseif table.getn(resp.ListBucketResult.Contents) ~= #self.filenames then
		error("s3:list failed!, Mismatch in the number of resp")
	else
		-- print("resp: ", cjson.encode(resp.ListBucketResult.Contents))
	end
	local dirs = {}
	for i =1,#self.filenames do
		local filename = self.filenames[i]
		if string.sub(filename, 1, 1) == "/" then
			filename = string.sub(filename, 2)
		end
		local dir = first_dir(filename)
		if dir then
			if dirs[dir] then
				dirs[dir] = dirs[dir] + 1
			else
				dirs[dir] = 1
			end
		end
	end
	for dir, number in pairs(dirs) do
		local ok, resp = self.s3:list(dir)
		if not ok then
			error("s3:list(" .. dir .. ") failed! resp:" .. tostring(resp))
		else
			-- print("list(" .. dir ..") result:", cjson.encode(resp.ListBucketResult))
			local file_count = table.getn(resp.ListBucketResult.Contents)
			-- resp.ListBucketResult.Contents is a object.
			if file_count == 0 and resp.ListBucketResult.Contents['Key'] then
				file_count = 1
			end
			if file_count ~= number then
				error("s3:list(" .. dir .. ") failed!, Mismatch in the number of files, expect: " .. number .. ", but got: " .. file_count)
			end
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

function tb:test_20multi_upload()
	local key = "path/to/a/bigfile"
	local myheaders = util.new_headers()
	local ok, uploader = self.s3:start_multi_upload(key, myheaders)
	if not ok then
		error("start_multi_upload " .. cjson.encode({key=key, myheaders=myheaders}) .. "] failed! resp:" .. tostring(uploader))
	end

	local filesize = 0
	for i = 1, 2 do
		local part_number = i;
		local value = string.rep(tostring(i), 1024*1024*5) -- size is 5M
		filesize = filesize + #value
		print("Uploading part ", part_number, " now, this will take a while, please wait...")
		local ok, etag = uploader:upload(part_number, value)
		print("Part ", part_number, " Upload completed, ok:", ok, ", etag: ", etag)
		if not ok then
			error("uploader:upload " .. cjson.encode({key=key, part_number=part_number, value="..."}) .. "] failed! resp:" .. tostring(etag))
		end
	end
	local ok, resp = uploader:complete()
	if not ok then
		error("uploader:complete " .. cjson.encode({key=key, part_number=part_number, value=value}) .. "] failed! resp:" .. tostring(resp))
	end

	print("Downloading file " .. key .. " now, as the file is large, please be patient...")
	local ok, content = self.s3:get(key)
	if not ok then
		error("get content of [", key, "] failed!, err:", content)
	end
	if #content ~= filesize then
		error("There may be a problem with the upload or download process, the file size should be " .. tostring(filesize) .. ", but it is actually " .. tostring(#content))
	end

	-- md5: echo "io.write(string.rep(tostring(1), 1024*1024*5));io.write( string.rep(tostring(2), 1024*1024*5))" | lua | md5
	local expect_md5 = "4cffd339951bb6aba6a2ecd9f2b7a8f4"
	local actually_md5 = ngx.md5(content)
	if actually_md5 ~= expect_md5 then
		error("There may be a problem with the upload or download process, the file md5 should be " .. expect_md5 .. ", but it is actually " .. actually_md5)
	end

	-- delete the bigfile
	local ok, err = self.s3:delete(key)
	if not ok then
		error("delete [" .. key .. "] failed! resp:" .. tostring(err))
	end
    self.log("multi upload OK")
end


-- units test
tb:run()

-- bench units test
-- test:bench_run()
