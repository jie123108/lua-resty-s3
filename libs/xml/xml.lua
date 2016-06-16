local slaxdom = require 'xml.slaxdom' -- https://github.com/Phrogz/SLAXML
local cjson = require "cjson"

local XML = {}

-- 如果没有子元素，才返回。
local function ele_text(ele)
	local text = nil
	for _,n in ipairs(ele.kids) do
		if n.type=='text' then
			text = n.value
		elseif n.type == "element" then
			return nil
		end
	end
	return text
end

local function dom_parse(xml)
	return slaxdom:dom(xml)
end

function XML.loads(xml)
	local ok, doc = pcall(dom_parse, xml)
	if not ok or doc == nil or doc.root == nil then
		if doc == nil or doc.root == nil then
			doc = "doc.root is nil"
		end
		ngx.log(ngx.ERR, "parse xml [", tostring(xml) , "] failed! err:", doc)
		return nil, "xml-invalid"
	end
	local root = doc.root
	local function parse_element(ele, t)
		if not t then
			t = {}
		end
		--ngx.say("--- ele:", ele.name, ", childs: ", #ele.kids)
		local value = ele_text(ele)
		if value then -- 直接有内容的。
			
		else
			for _,child in ipairs(ele.kids) do
			    if child.type=='element' then
			    	if value == nil then
			    		value = {}
			    	end
			    	parse_element(child, value)
			    end
			end			
		end
		value = value or ""
		
		local old_ele = t[ele.name]
		if old_ele then -- 已经有相同的对象了，需要使用数组存储。
			--ngx.say("same obj:", ele.name, " type:", type(old_ele) == 'table', " size:", #old_ele >= 1)
			if type(old_ele) == 'table' and #old_ele >= 1 then
				table.insert(old_ele, value)
			else 
				local arr = {}
				table.insert(arr, old_ele)
				table.insert(arr, value)
				t[ele.name] = arr
			end
		else
			t[ele.name] = value
		end
		
		return t
	end

	return parse_element(root)
end

--[[
local function dump_tab(child_tab, name)
		local values = {}
		if #child_tab > 0 then -- 数组类型。
			for _, value in ipairs(child_tab) do 
				if type(value) == 'table' then
					value = dump_tab(value)
					table.insert(values, string.format("<%s>%s</%s>", name, value, name))
				else 
					value = tostring(value)
					table.insert(values, string.format("<%s>%s</%s>", name, value, name))
				end
			end
		else
			for key, value in pairs(child_tab) do 
				if type(value) == 'table' then
					if #value > 0 then -- 数组类型，需要把key传进去。
						value = dump_tab(value, key)
						table.insert(values, value)
					else
						key = tostring(key)
						value = dump_tab(value)
						table.insert(values, string.format("<%s>%s</%s>", key, value, key))
					end
				else 
					key = tostring(key)
					value = tostring(value)
					table.insert(values, string.format("<%s>%s</%s>", key, value, key))
				end
			end
		end
		return table.concat(values)
	end
]]
function XML.dumps(tab)
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
return XML