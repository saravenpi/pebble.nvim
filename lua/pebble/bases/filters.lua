local M = {}

local function get_file_property(file_path, property)
	local stat = vim.loop.fs_stat(file_path)
	if not stat then return nil end
	
	if property == "name" then
		return vim.fn.fnamemodify(file_path, ":t:r")
	elseif property == "ext" then
		return vim.fn.fnamemodify(file_path, ":e")
	elseif property == "size" then
		return stat.size
	elseif property == "mtime" then
		return stat.mtime.sec
	elseif property == "ctime" then
		return stat.ctime.sec
	elseif property == "path" then
		return file_path
	end
	
	return nil
end

local function get_note_property(file_path, property, frontmatter)
	if not frontmatter then
		local lines = vim.fn.readfile(file_path, "", 50)
		if not lines or #lines == 0 or lines[1] ~= "---" then
			return nil
		end
		
		frontmatter = {}
		for i = 2, #lines do
			local line = lines[i]
			if line == "---" or line == "..." then
				break
			end
			
			local key, value = line:match("^([%w_%-]+):%s*(.*)$")
			if key then
				value = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
				frontmatter[key] = value
			end
		end
	end
	
	return frontmatter[property]
end

-- Cache file content to avoid repeated reads
local content_cache = {}
local CACHE_TTL = 30000 -- 30 seconds

local function get_file_content(file_path)
	local now = vim.loop.now()
	local cached = content_cache[file_path]
	
	-- Check if cache is valid
	if cached and (now - cached.timestamp) < CACHE_TTL then
		local stat = vim.loop.fs_stat(file_path)
		if stat and stat.mtime.sec == cached.mtime then
			return cached.content
		end
	end
	
	-- Read file content
	local stat = vim.loop.fs_stat(file_path)
	if not stat then return "" end
	
	local lines = vim.fn.readfile(file_path, "", 200) -- Reduced from 500 for speed
	if not lines then return "" end
	
	local content = table.concat(lines, "\n")
	content_cache[file_path] = {
		content = content,
		mtime = stat.mtime.sec,
		timestamp = now
	}
	
	return content
end

function M.clear_content_cache()
	content_cache = {}
end

local function has_tag(file_path, tag)
	local content = get_file_content(file_path)
	
	-- Check for inline #tags
	if content:match("#" .. vim.pesc(tag) .. "%f[%W]") then
		return true
	end
	
	-- Check for frontmatter tags
	local frontmatter_start = content:match("^%-%-%-")
	if frontmatter_start then
		local frontmatter_end = content:match("\n%-%-%-")
		if frontmatter_end then
			local frontmatter = content:match("^%-%-%-\n(.-)%-%-%-")
			if frontmatter then
				-- Check for tags: [tag1, tag2] format
				if frontmatter:match("tags:%s*%[.-" .. vim.pesc(tag) .. ".-]") then
					return true
				end
				-- Check for tags:\n  - tag format
				if frontmatter:match("tags:%s*\n%s*%-%s*" .. vim.pesc(tag)) then
					return true
				end
			end
		end
	end
	
	return false
end

local function has_link(file_path, link)
	local content = get_file_content(file_path)
	return content:match("%[%[" .. vim.pesc(link) .. "%]%]") ~= nil
end

local function in_folder(file_path, folder)
	local dir = vim.fn.fnamemodify(file_path, ":h")
	return dir:match(vim.pesc(folder)) ~= nil
end

local function evaluate_condition(condition, file_path, frontmatter)
	if type(condition) == "string" then
		-- Support both old and new Obsidian syntax
		if condition:match("^file%.hasTag%(") or condition:match("^taggedWith%(") then
			-- Handle single tag: file.hasTag("tag")
			local tag = condition:match('^file%.hasTag%("([^"]+)"%)')
			if not tag then
				tag = condition:match("^file%.hasTag%('([^']+)'%)")
			end
			-- Handle multiple tags: file.hasTag("tag1", "tag2") -> check if has any of these tags
			if not tag then
				local tags_str = condition:match('^file%.hasTag%((.+)%)')
				if tags_str then
					-- Parse multiple quoted tags
					local has_any = false
					for t in tags_str:gmatch('"([^"]+)"') do
						if has_tag(file_path, t) then
							has_any = true
							break
						end
					end
					for t in tags_str:gmatch("'([^']+)'") do
						if has_tag(file_path, t) then
							has_any = true
							break
						end
					end
					return has_any
				end
			end
			-- Handle old taggedWith syntax
			if not tag then
				tag = condition:match('^taggedWith%([^,]+,%s*"([^"]+)"%)')
			end
			return tag and has_tag(file_path, tag)
		elseif condition:match("^file%.hasLink%(") or condition:match("^linksTo%(") then
			local link = condition:match('^file%.hasLink%("([^"]+)"%)')
			if not link then
				link = condition:match("^file%.hasLink%('([^']+)'%)")
			end
			if not link then
				link = condition:match('^linksTo%([^,]+,%s*"([^"]+)"%)')
			end
			return link and has_link(file_path, link)
		elseif condition:match("^file%.inFolder%(") or condition:match("^inFolder%(") then
			local folder = condition:match('^file%.inFolder%("([^"]+)"%)')
			if not folder then
				folder = condition:match("^file%.inFolder%('([^']+)'%)")
			end
			if not folder then
				folder = condition:match('^inFolder%([^,]+,%s*"([^"]+)"%)')
			end
			return folder and in_folder(file_path, folder)
		else
			local left, op, right = condition:match("^(.-)%s*([!=<>]+)%s*(.+)$")
			if left and op and right then
				local left_val, right_val
				
				if left:match("^file%.") then
					local prop = left:match("^file%.(.+)$")
					left_val = get_file_property(file_path, prop)
				elseif left:match("^note%.") or not left:match("%.") then
					local prop = left:match("^note%.(.+)$") or left
					left_val = get_note_property(file_path, prop, frontmatter)
				else
					left_val = left
				end
				
				right_val = right:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
				
				if op == "==" or op == "=" then
					return tostring(left_val) == tostring(right_val)
				elseif op == "!=" then
					return tostring(left_val) ~= tostring(right_val)
				elseif op == ">" then
					return tonumber(left_val) and tonumber(right_val) and tonumber(left_val) > tonumber(right_val)
				elseif op == "<" then
					return tonumber(left_val) and tonumber(right_val) and tonumber(left_val) < tonumber(right_val)
				elseif op == ">=" then
					return tonumber(left_val) and tonumber(right_val) and tonumber(left_val) >= tonumber(right_val)
				elseif op == "<=" then
					return tonumber(left_val) and tonumber(right_val) and tonumber(left_val) <= tonumber(right_val)
				end
			end
		end
	elseif type(condition) == "table" then
		if condition["and"] then
			for _, subcond in ipairs(condition["and"]) do
				if not M.evaluate_filter(subcond, file_path, frontmatter) then
					return false
				end
			end
			return true
		elseif condition["or"] then
			for _, subcond in ipairs(condition["or"]) do
				if M.evaluate_filter(subcond, file_path, frontmatter) then
					return true
				end
			end
			return false
		elseif condition["not"] then
			if type(condition["not"]) == "table" then
				for _, subcond in ipairs(condition["not"]) do
					if M.evaluate_filter(subcond, file_path, frontmatter) then
						return false
					end
				end
				return true
			else
				return not M.evaluate_filter(condition["not"], file_path, frontmatter)
			end
		end
	end
	
	return false
end

function M.evaluate_filter(filter, file_path, frontmatter)
	if not filter then return true end
	return evaluate_condition(filter, file_path, frontmatter)
end

function M.filter_files(files, filter)
	if not filter then return files end
	
	local filtered = {}
	for _, file in ipairs(files) do
		if M.evaluate_filter(filter, file.path, file.frontmatter) then
			table.insert(filtered, file)
		end
	end
	
	return filtered
end

return M