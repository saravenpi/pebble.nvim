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
	local escaped_tag = vim.pesc(tag)
	local filename = vim.fn.fnamemodify(file_path, ":t")
	
	-- Debug: Log what we're checking
	vim.notify("Checking " .. filename .. " for tag: " .. tag, vim.log.levels.INFO)
	
	-- Check for inline #tags in content (outside frontmatter)
	local after_frontmatter = content
	local frontmatter_match = content:match("^%-%-%-.-\n%-%-%-\n(.*)$")
	if frontmatter_match then
		after_frontmatter = frontmatter_match
	end
	
	if after_frontmatter:match("#" .. escaped_tag .. "(%s|$|%p)") then
		vim.notify("✅ Found inline tag #" .. tag .. " in " .. filename, vim.log.levels.INFO)
		return true
	end
	
	-- Check frontmatter tags
	local frontmatter = content:match("^%-%-%-\n(.-)%-%-%-")
	if frontmatter then
		-- tags: [tag1, tag2] format
		local tags_line = frontmatter:match("tags:%s*(%[.-%])")
		if tags_line then
			local tags_content = tags_line:match("%[(.-)%]")
			if tags_content then
				for t in tags_content:gmatch("([^,]+)") do
					t = t:match("^%s*(.-)%s*$"):gsub('^["\']', ''):gsub('["\']$', '')
					if t == tag then
						vim.notify("✅ Found frontmatter tag " .. tag .. " in " .. filename, vim.log.levels.INFO)
						return true
					end
				end
			end
		end
		
		-- tags:\n  - tag format  
		for line in frontmatter:gmatch("[^\n]+") do
			if line:match("^%s*%-%s*" .. escaped_tag .. "%s*$") then
				-- vim.notify("Found list tag " .. tag .. " in " .. filename, vim.log.levels.DEBUG)
				return true
			end
		end
		
		-- tags: tag format
		if frontmatter:match("tags:%s*" .. escaped_tag .. "(%s|$)") then
			-- vim.notify("Found single tag " .. tag .. " in " .. filename, vim.log.levels.DEBUG)
			return true
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
			-- Handle multiple tags: file.hasTag("tag1", "tag2") -> check if has ALL of these tags (AND logic)
			if not tag then
				local tags_str = condition:match('^file%.hasTag%((.+)%)')
				if tags_str then
					-- Parse multiple quoted tags and check ALL must be present
					local tags_to_check = {}
					for t in tags_str:gmatch('"([^"]+)"') do
						table.insert(tags_to_check, t)
					end
					for t in tags_str:gmatch("'([^']+)'") do
						table.insert(tags_to_check, t)
					end
					
					-- All tags must be present
					for _, t in ipairs(tags_to_check) do
						if not has_tag(file_path, t) then
							return false
						end
					end
					
					return #tags_to_check > 0 -- Return true only if we had tags to check and all were found
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