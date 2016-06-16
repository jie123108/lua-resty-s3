local cjson = require("cjson")
local xml = require("xml.xml")
local cxml = require("xml.cxml")
local Bucket = "test-bucket"
local Prefix = "/test/to/xml"
local files = {}
for i=1,30 do 
	local Key = "myfile" .. tostring(i) .. ".doc"
	local file = {Key=Key, LastModified="2009-10-12T17:50:30.000Z", 
					ETag=string.format([["%s"]], ngx.md5(Key)), Size=1024000,
					StorageClass="STANDARD"}
	table.insert(files, file)
end
local map = {ListBucketResult={Name=Bucket, Prefix=Prefix,MaxKeys=1000,IsTruncated=false,Contents=files}}

-- local xmlstr = xml.dumps(map)
-- local map = cxml.loads(xmlstr)
-- ngx.say(cjson.encode(map))

-- local begin = ngx.now()
-- for w=1,0 do
-- 	for i=1,10000 do 
-- 		--local xmlstr = xml.dumps(map)
-- 		--local map = xml.loads(xmlstr)
-- 		local map = cxml.loads(xmlstr)
-- 	end
-- 	ngx.update_time()
-- 	ngx.say("------ ", w, " 万 ...")
-- end
-- local end_ = ngx.now()
-- ngx.say("dumps:", (end_-begin))

local myxml = [[<Tag attr="attr">xxx</Tag>

]]

-- local xmlhdr = [[<?xml version="1.0" encoding="UTF-8"?>]]
-- local hdrlen = #xmlhdr

-- ngx.update_time()
-- local begin = ngx.now()
-- for i=0,10000*1000 do 
-- ngx.re.gsub(myxml, "^<?.*?>", "", "jos")
-- local prefix = string.sub(myxml, 1, hdrlen)
-- if prefix == xmlhdr then end
-- end
-- ngx.update_time()
-- local end_ = ngx.now()
-- ngx.say("time:", (end_-begin))

local xml = cxml.loads(myxml)
if xml then
print(cjson.encode(xml))
end