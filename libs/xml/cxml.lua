local ffi = require("ffi")

local _M = {}
_M.inited = false

function _M.init()
	ffi.cdef[[
	typedef void xml_document;
	typedef void xml_node;
	typedef void xml_string;
	
	xml_document* xml_parse_document(const char* buffer, size_t length);

	void xml_document_free(xml_document* document, bool free_buffer);

	xml_node* xml_document_root(xml_document* document);

	xml_string* xml_node_name(xml_node* node);

	xml_string* xml_node_content(xml_node* node);

	size_t xml_node_children(xml_node* node);

	xml_node* xml_node_child(xml_node* node, size_t child);

	const char* xml_easy_name(xml_node* node);

	const char* xml_easy_content(xml_node* node);

	size_t xml_string_length(xml_string* string);
	const char* xml_string_str(struct xml_string* string);

	void free(const char *ptr);
	]]
	_M.inited = true
	return _M.inited
end

_M.inited = _M.init()

local function find_shared_obj(cpath, so_name)
    --ngx.log(ngx.INFO, "cpath:", cpath, ",so_name:", so_name)
    for k, v in string.gmatch(cpath, "[^;]+") do
        local so_path = string.match(k, "(.*/)")
        --ngx.log(ngx.INFO, "so_path:", so_path)

        if so_path then
            -- "so_path" could be nil. e.g, the dir path component is "."
            so_path = so_path .. so_name

            -- Don't get me wrong, the only way to know if a file exist is
            -- trying to open it.
            local f = io.open(so_path)
            if f ~= nil then
                io.close(f)
                return so_path
            end
        end
    end
end

local function get_cxml()    
    local so_path = find_shared_obj(package.cpath, "libcxml.so")
    if so_path == nil then
        ngx_log(ngx.ERR, "### can't find libcxml.so in :" .. package.cpath)
        return nil
    end
   --ngx_log(ngx.INFO, "load so_path:", so_path)
   return ffi.load(so_path)
end

_M.xml = get_cxml()


local function node_name(node)
	--[[
	local c_name = _M.xml.xml_easy_name(node)
	local name = nil 
	if c_name and c_name ~= ffi.NULL then
		name = ffi.string(c_name)
		ffi.C.free(c_name)
	end
	return name
	]]
	
	local c_name = _M.xml.xml_node_name(node)
	local name = nil 
	if c_name and c_name ~= ffi.NULL then
		name = ffi.string(_M.xml.xml_string_str(c_name), _M.xml.xml_string_length(c_name))
	end
	return name
end

local function node_content(node)
	local c_content = _M.xml.xml_node_content(node)
	local content = nil
	if c_content and c_content ~= ffi.NULL then
		content = ffi.string(_M.xml.xml_string_str(c_content), _M.xml.xml_string_length(c_content))
	end
	return content
end

local xmlhdr = [[<?xml version="1.0" encoding="UTF-8"?>]]
local hdrlen = #xmlhdr
function _M.loads(str)
	if not _M.inited then
		ngx.log(ngx.ERR, "xml.c must be init first! [init at init_worker_by_luaxxx,init_by_luaxxx]")
		return nil, "xml-c-not-inited"
	end
	if str == nil or type(str) ~= "string" then
		ngx.log(ngx.INFO, 'input str [', tostring(str), "] invalid!")
		return nil, "xml-invalid"
	end
	local prefix = string.sub(str, 1, hdrlen)
	
	if prefix == xmlhdr then 
		str = string.sub(str, hdrlen+1)
	elseif string.sub(str, 1, 2) == "<?" then 
		str = ngx.re.gsub(str, "^<?.*?>", "", "jos")
	end
	local doc = _M.xml.xml_parse_document(str, #str)
	-- TODO: 测试：如果返回的是NULL ,lua值是多少。
	if doc == nil then
		return nil, "xml-invalid"
	end
	local  root = _M.xml.xml_document_root(doc)
	local function parse_element(ele, t)
		if t == nil then
			t = {}
		end

		local name = node_name(ele)
		local value = node_content(ele)
		--print("name:", name)
		if value then -- 直接有数据的。

		else
			local children_cnt = tonumber(_M.xml.xml_node_children(ele))
			if children_cnt and children_cnt > 0 then
				for i=0,children_cnt-1 do 
					local child = _M.xml.xml_node_child(ele, i)
					if value == nil then
						value = {}
					end
					parse_element(child, value)
				end
			end
		end
		value = value or ""
		
		local old_ele = t[name]
		if old_ele then -- 已经有相同的对象了，需要使用数组存储。
			--ngx.say("same obj:", ele.name, " type:", type(old_ele) == 'table', " size:", #old_ele >= 1)
			if type(old_ele) == 'table' and #old_ele >= 1 then
				table.insert(old_ele, value)
			else 
				local arr = {}
				table.insert(arr, old_ele)
				table.insert(arr, value)
				t[name] = arr
			end
		else
			t[name] = value
		end
		return t
	end

	local root_tab = parse_element(root)
	_M.xml.xml_document_free(doc, false)
	return root_tab
end


function _M.dumps(tab)
	if type(tab) ~= 'table' then
		return false, "tab-invalid"
	end
	local function xtabs(x)
		if x == nil or x == 0 then
			return ""
		end
		local t = {}
		for i=1,x do 
			table.insert(t, '    ')
		end
		return table.concat(t)
	end
	local function add_value(values, key, value, level, multiline)
		if multiline then
			table.insert(values, xtabs(level) .. string.format("<%s>", key))
			-- 已经缩进过了。
			if string.sub(value, 1, 4) == '    ' then
				table.insert(values, value)
			else
			 	table.insert(values, xtabs(level) .. value)
			end
			table.insert(values, xtabs(level) .. string.format("</%s>", key))
		else 
			table.insert(values, xtabs(level) .. string.format("<%s>%s</%s>", key, value, key))
		end
	end

	local function dump_tab(child_tab, level)
		level = level or 0
		local values = {}
		for key, value in pairs(child_tab) do 
			if type(value) == 'table' then
				if #value > 0 then -- 数组类型，需要把key传进去。
					for _, arr_val in ipairs(value) do 
						if type(arr_val) == 'table' then
							arr_val = dump_tab(arr_val, level + 1)
							add_value(values, key, arr_val, level, true)
						else 
							arr_val = tostring(arr_val)
							add_value(values, key, arr_val, level)
						end
					end
				else
					key = tostring(key)
					value = dump_tab(value, level + 1)
					add_value(values, key, value, level, true)
				end
			else 
				key = tostring(key)
				value = tostring(value)
				add_value(values, key, value, level)
			end
		end
	
		return table.concat(values, "\n")
	end
	return dump_tab(tab)
end

return _M