package.path = "/root/work/lua-resty-s3/?.lua;/root/work/lua-resty-s3/lib/?.lua;/usr/local/ngx_openresty/lualib/?.lua;;"
package.cpath = "/root/work/lua-resty-s3/lib/?.so;/usr/local/ngx_openresty/lualib/?.so;;"

local cjson = require("cjson")
local xml = require("xml.xml")
local cxml = require("xml.cxml")
local Bucket = "test-bucket"
local Prefix = "/test/to/xml"
local files = {}
for i=1,3 do 
	local Key = "myfile" .. tostring(i) .. ".doc"
	local file = {Key=Key, LastModified="2009-10-12T17:50:30.000Z", 
					ETag=string.format([["%s"]], Key), Size=1024000,
					StorageClass="STANDARD"}
	table.insert(files, file)
end
local map = {ListBucketResult={Name=Bucket, Prefix=Prefix,MaxKeys=1000,IsTruncated=false,Contents=files}}

local xmlstr = xml.dumps(map)
--print("[", xmlstr, "]")
local map = cxml.loads(xmlstr)
--print(cjson.encode(map))
--print(cjson.encode(xml.loads(xmlstr)))
function test(name, func, arg)
	local begin = os.time()
	for w=1,10 do
		for i=1,10000 do 
			--local xmlstr = xml.dumps(map)
			--local map = xml.loads(xmlstr)
			--local map = cxml.loads(xmlstr)
			local obj = func(arg)
		end
		--ngx.update_time()
		print(name, ": ------ ", w, " 万 ...")
	end
	local end_ = os.time()
	print(name, ":", (end_-begin))
end

test("xml.dumps", xml.dumps, map)
test("xml.loads", xml.loads, xmlstr)
test("cxml.loads", cxml.loads, xmlstr)
