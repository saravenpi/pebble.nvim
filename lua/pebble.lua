local M = {}

-- Performance: Cache git root to avoid repeated system calls
local _git_root_cache = nil
local _git_root_cache_time = 0
local GIT_ROOT_CACHE_TTL = 30000  -- 30 seconds

local file_cache = {}
local alias_cache = {}
local cache_valid = false
local navigation_history = {}
local current_history_index = 0
local is_navigating_history = false
local graph_buf = nil
local graph_win = nil
local graph_cache = {}
local link_cache = {}
local graph_cache_timestamp = 0
local GRAPH_CACHE_TTL = 5000
local MAX_FILES_TO_SCAN = 200

--- Parse YAML frontmatter from file content and extract aliases
local function parse_yaml_frontmatter(file_path)
	if not vim.fn.filereadable(file_path) then
		return nil
	end
	
	-- Only read first 10 lines for performance - frontmatter should be at the top
	local lines = vim.fn.readfile(file_path, "", 10)
	if not lines or #lines == 0 then
		return nil
	end
	
	-- Check if file starts with YAML frontmatter
	if lines[1] ~= "---" then
		return nil
	end
	
	local frontmatter = {}
	local in_frontmatter = true
	local end_found = false
	
	local i = 2
	while i <= #lines do
		local line = lines[i]
		if line == "---" then
			end_found = true
			break
		elseif line == "..." then
			end_found = true
			break
		end
		
		-- Parse simple YAML key-value pairs and arrays
		local key, value = line:match("^([%w_%-]+):%s*(.*)$")
		if key then
			-- Handle arrays (simple case: "- item")
			if value == "" and i + 1 <= #lines and lines[i + 1]:match("^%s*%- ") then
				local array_items = {}
				local j = i + 1
				while j <= #lines and lines[j]:match("^%s*%- ") do
					local item = lines[j]:match("^%s*%-%s*(.+)$")
					if item then
						-- Remove quotes if present
						item = item:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
						table.insert(array_items, item)
					end
					j = j + 1
				end
				frontmatter[key] = array_items
				i = j  -- Skip the processed array items
			else
				-- Remove quotes if present
				value = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
				frontmatter[key] = value
				i = i + 1
			end
		else
			i = i + 1
		end
	end
	
	return end_found and frontmatter or nil
end

--- Build alias cache on demand for a specific file
local function ensure_file_alias(file_path)
	if alias_cache[file_path] ~= nil then
		return -- Already cached
	end
	
	local frontmatter = parse_yaml_frontmatter(file_path)
	if frontmatter then
		-- Handle single alias
		if frontmatter.alias and type(frontmatter.alias) == "string" then
			alias_cache[frontmatter.alias:lower()] = file_path
		end
		-- Handle multiple aliases
		if frontmatter.aliases and type(frontmatter.aliases) == "table" then
			for _, alias in ipairs(frontmatter.aliases) do
				if type(alias) == "string" then
					alias_cache[alias:lower()] = file_path
				end
			end
		end
	end
	
	-- Mark as processed (even if no aliases found)
	alias_cache[file_path] = true
end

--- Get root directory with caching for performance
local function get_root_dir()
	local now = vim.loop.now()
	-- Use cached git root if still valid
	if _git_root_cache and (now - _git_root_cache_time) < GIT_ROOT_CACHE_TTL then
		return _git_root_cache
	end
	
	local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
	local root_dir
	if vim.v.shell_error ~= 0 or git_root == "" then
		root_dir = vim.fn.getcwd()
	else
		root_dir = git_root
	end
	
	-- Cache the result
	_git_root_cache = root_dir
	_git_root_cache_time = now
	return root_dir
end

--- Build cache of all markdown files in the current repository or directory
local function build_file_cache()
	file_cache = {}
	-- Don't clear alias_cache - keep it for performance
	local cwd = get_root_dir()

	-- Performance: Use lazy loading with reduced initial scan limit
	local md_files = vim.fs.find(function(name)
		return name:match("%.md$")
	end, {
		path = cwd,
		type = "file",
		limit = 500,  -- Reduced for performance - lazy load more if needed
		upward = false,
	})

	-- Performance: Process files in batches to avoid blocking
	local batch_size = 50
	local processed = 0
	
	for _, file_path in ipairs(md_files) do
		local filename = vim.fn.fnamemodify(file_path, ":t:r")
		if not file_cache[filename] then
			file_cache[filename] = {}
		end
		table.insert(file_cache[filename], file_path)
		
		processed = processed + 1
		-- Yield control periodically to prevent blocking UI
		if processed % batch_size == 0 then
			vim.schedule(function() end)  -- Yield to UI
		end
	end

	cache_valid = true
end

--- Invalidate the file cache when files change
local function invalidate_cache()
	cache_valid = false
	alias_cache = {}
end

--- Invalidate all caches including graph and link caches
local function invalidate_graph_caches()
	graph_cache = {}
	link_cache = {}
	alias_cache = {}
	cache_valid = false
	graph_cache_timestamp = 0
end

--- Get the link under the cursor and determine its type
local function get_link_under_cursor()
	-- Safety check
	local success, line = pcall(vim.api.nvim_get_current_line)
	if not success or not line then
		return nil, nil
	end
	
	local cursor_result = vim.api.nvim_win_get_cursor(0)
	if not cursor_result or not cursor_result[2] then
		return nil, nil
	end
	
	local col = cursor_result[2] + 1

	-- Find all obsidian links in the line
	local start_pos = 1
	while start_pos <= #line do
		local obsidian_start, obsidian_end = line:find("%[%[[^%]]*%]%]", start_pos)
		if not obsidian_start then
			break
		end
		
		if col >= obsidian_start and col <= obsidian_end then
			local link_text = line:sub(obsidian_start + 2, obsidian_end - 2)
			if link_text and link_text ~= "" then
				return link_text, "obsidian"
			end
		end
		
		start_pos = obsidian_end + 1
		if start_pos > #line then break end
	end

	-- Find all markdown links in the line
	start_pos = 1
	while start_pos <= #line do
		local md_start, md_end = line:find("%[[^%]]*%]%([^%)]*%)", start_pos)
		if not md_start then
			break
		end
		
		if col >= md_start and col <= md_end then
			-- Find parentheses within this specific link match
			local paren_start, paren_end = line:find("%]%(([^%)]*)%)", md_start)
			if paren_start and paren_end and paren_start + 2 <= paren_end - 1 then
				local link_url = line:sub(paren_start + 2, paren_end - 1) -- +2 to skip ](, -1 to skip )
				if link_url and link_url ~= "" then
					return link_url, "markdown"
				end
			end
		end
		
		start_pos = md_end + 1
		if start_pos > #line then break end
	end

	return nil, nil
end

--- Find a markdown file matching the given filename
local function find_markdown_file(filename)
	if not filename or filename == "" then
		return nil
	end

	if not cache_valid then
		build_file_cache()
	end

	-- Check if it's an alias (case-insensitive) - but only search existing aliases
	local filename_lower = filename:lower()
	local alias_match = alias_cache[filename_lower]
	if alias_match and type(alias_match) == "string" then
		return alias_match
	end

	local search_name = filename:gsub("%.md$", "")
	
	-- Try exact match first
	local matches = file_cache[search_name]
	if matches and #matches > 0 then
		-- Prioritize files in the same directory as the current buffer
		local current_file = vim.api.nvim_buf_get_name(0)
		if current_file and current_file ~= "" and current_file:match("%.md$") then
			local current_dir = vim.fn.fnamemodify(current_file, ":h")

			-- First, look for a file in the same directory
			for _, file_path in ipairs(matches) do
				local file_dir = vim.fn.fnamemodify(file_path, ":h")
				if file_dir == current_dir then
					return file_path
				end
			end
		end

		-- If no file found in current directory, return the first match
		return matches[1]
	end
	
	-- Try case-insensitive match if exact match fails
	local search_name_lower = search_name:lower()
	for filename_key, file_paths in pairs(file_cache) do
		if filename_key:lower() == search_name_lower then
			if file_paths and #file_paths > 0 then
				-- Apply same directory prioritization
				local current_file = vim.api.nvim_buf_get_name(0)
				if current_file and current_file ~= "" and current_file:match("%.md$") then
					local current_dir = vim.fn.fnamemodify(current_file, ":h")

					for _, file_path in ipairs(file_paths) do
						local file_dir = vim.fn.fnamemodify(file_path, ":h")
						if file_dir == current_dir then
							return file_path
						end
					end
				end
				return file_paths[1]
			end
		end
	end
	
	-- If no filename match found, do a lazy search for aliases
	-- Only check files that haven't been processed yet
	for _, file_paths in pairs(file_cache) do
		for _, file_path in ipairs(file_paths) do
			if alias_cache[file_path] == nil then
				ensure_file_alias(file_path)
				-- Check if we found the alias we're looking for
				local found_alias = alias_cache[filename_lower]
				if found_alias and type(found_alias) == "string" then
					return found_alias
				end
			end
		end
	end

	return nil
end

--- Add current file to navigation history before navigating away
local function add_current_to_history()
	if is_navigating_history then
		return
	end

	local current_file = vim.api.nvim_buf_get_name(0)
	if not current_file or current_file == "" or not current_file:match("%.md$") then
		return
	end

	if current_history_index > 0 and current_history_index < #navigation_history then
		for i = #navigation_history, current_history_index + 1, -1 do
			navigation_history[i] = nil
		end
	end

	if #navigation_history > 0 and navigation_history[#navigation_history] == current_file then
		return
	end

	table.insert(navigation_history, current_file)
	current_history_index = #navigation_history
end

--- Navigate back in the navigation history
local function go_back_in_history()
	if #navigation_history == 0 then
		vim.notify("No navigation history available", vim.log.levels.INFO)
		return
	end

	if current_history_index <= 1 then
		vim.notify("Already at the beginning of navigation history", vim.log.levels.INFO)
		return
	end

	current_history_index = current_history_index - 1
	local file_path = navigation_history[current_history_index]

	if file_path and vim.fn.filereadable(file_path) == 1 then
		is_navigating_history = true
		vim.cmd("edit " .. vim.fn.fnameescape(file_path))
		vim.defer_fn(function()
			is_navigating_history = false
		end, 100)
	else
		vim.notify("File no longer exists: " .. (file_path or "unknown"), vim.log.levels.WARN)
	end
end

--- Navigate forward in the navigation history
local function go_forward_in_history()
	if current_history_index >= #navigation_history then
		vim.notify("Already at the end of navigation history", vim.log.levels.INFO)
		return
	end

	current_history_index = current_history_index + 1
	local file_path = navigation_history[current_history_index]

	if file_path and vim.fn.filereadable(file_path) == 1 then
		is_navigating_history = true
		vim.cmd("edit " .. vim.fn.fnameescape(file_path))
		vim.defer_fn(function()
			is_navigating_history = false
		end, 100)
	else
		vim.notify("File no longer exists: " .. (file_path or "unknown"), vim.log.levels.WARN)
	end
end

--- Create a new markdown file with the given name and title
local function create_new_file(link, title)
	-- First check if file already exists anywhere to prevent duplicates
	local existing_file = find_markdown_file(link)
	if existing_file then
		return existing_file
	end

	-- Get current buffer's directory, fallback to git root, then cwd
	local current_file = vim.api.nvim_buf_get_name(0)
	local target_dir

	if current_file and current_file ~= "" and current_file:match("%.md$") then
		target_dir = vim.fn.fnamemodify(current_file, ":h")
	else
		target_dir = get_root_dir()
	end

	local new_file_path = target_dir .. "/" .. link .. ".md"

	-- Double-check file doesn't exist at target location
	if vim.fn.filereadable(new_file_path) == 1 then
		return new_file_path
	end

	local initial_content = { "# " .. title, "", "" }
	vim.fn.writefile(initial_content, new_file_path)

	invalidate_cache()

	return new_file_path
end

--- Open a link based on its type (obsidian or markdown)
local function open_link(link, link_type)
	if link_type == "obsidian" then
		local file_path = find_markdown_file(link)
		if file_path then
			add_current_to_history()
			vim.cmd("edit " .. vim.fn.fnameescape(file_path))
		else
			local new_file_path = create_new_file(link, link)
			add_current_to_history()
			vim.cmd("edit " .. vim.fn.fnameescape(new_file_path))
			vim.notify("Created file: " .. link .. ".md", vim.log.levels.INFO)
		end
	elseif link_type == "markdown" then
		if link:match("^https?://") then
			vim.fn.system("open " .. vim.fn.shellescape(link))
		else
			local file_path = link
			if not vim.fn.filereadable(file_path) then
				file_path = find_markdown_file(link)
			end

			if file_path and vim.fn.filereadable(file_path) then
				add_current_to_history()
				vim.cmd("edit " .. vim.fn.fnameescape(file_path))
			else
				local filename = link:gsub("%.md$", "")
				local new_file_path = create_new_file(filename, filename)
				add_current_to_history()
				vim.cmd("edit " .. vim.fn.fnameescape(new_file_path))
				vim.notify("Created file: " .. filename .. ".md", vim.log.levels.INFO)
			end
		end
	end
end

--- Follow the link under cursor or fallback to default Enter behavior
function M.follow_link()
	-- Wrap in pcall for safety
	local success, link, link_type = pcall(get_link_under_cursor)
	if success and link and link_type and link ~= "" then
		local open_success, err = pcall(open_link, link, link_type)
		if not open_success then
			vim.notify("Error opening link: " .. (err or "unknown error"), vim.log.levels.ERROR)
		end
	else
		-- Fallback to default Enter behavior
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
	end
end

--- Find all markdown links in the current buffer
local function find_all_links()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local links = {}

	for line_num, line in ipairs(lines) do
		-- Find all obsidian links in the line
		local start_pos = 1
		while true do
			local obs_start, obs_end = line:find("%[%[[^%]]*%]%]", start_pos)
			if not obs_start then
				break
			end
			
			table.insert(links, {
				line = line_num,
				col = obs_start,
				end_col = obs_end,
				type = "obsidian",
			})
			
			start_pos = obs_end + 1
		end

		-- Find all markdown links in the line
		start_pos = 1
		while true do
			local md_start, md_end = line:find("%[[^%]]*%]%([^%)]*%)", start_pos)
			if not md_start then
				break
			end
			
			table.insert(links, {
				line = line_num,
				col = md_start,
				end_col = md_end,
				type = "markdown",
			})
			
			start_pos = md_end + 1
		end
	end

	return links
end

--- Navigate to the next markdown link in the buffer
function M.next_link()
	local links = find_all_links()
	if #links == 0 then
		return
	end

	local current_pos = vim.api.nvim_win_get_cursor(0)
	local current_line = current_pos[1]
	local current_col = current_pos[2] + 1

	for _, link in ipairs(links) do
		if link.line > current_line or (link.line == current_line and link.col > current_col) then
			vim.api.nvim_win_set_cursor(0, { link.line, link.col - 1 })
			return
		end
	end

	if #links > 0 then
		vim.api.nvim_win_set_cursor(0, { links[1].line, links[1].col - 1 })
	end
end

--- Navigate to the previous markdown link in the buffer
function M.prev_link()
	local links = find_all_links()
	if #links == 0 then
		return
	end

	local current_pos = vim.api.nvim_win_get_cursor(0)
	local current_line = current_pos[1]
	local current_col = current_pos[2] + 1

	for i = #links, 1, -1 do
		local link = links[i]
		if link.line < current_line or (link.line == current_line and link.col < current_col) then
			vim.api.nvim_win_set_cursor(0, { link.line, link.col - 1 })
			return
		end
	end

	if #links > 0 then
		local last_link = links[#links]
		vim.api.nvim_win_set_cursor(0, { last_link.line, last_link.col - 1 })
	end
end

--- Go back in navigation history
function M.go_back()
	go_back_in_history()
end

--- Go forward in navigation history
function M.go_forward()
	go_forward_in_history()
end

--- Display navigation history for debugging
function M.show_history()
	print("Navigation History:")
	print("Current index: " .. current_history_index)
	print("History length: " .. #navigation_history)
	print("Is navigating: " .. tostring(is_navigating_history))
	print("Current file: " .. (vim.api.nvim_buf_get_name(0) or "none"))
	for i, file in ipairs(navigation_history) do
		local marker = (i == current_history_index) and " -> " or "    "
		local filename = file and vim.fn.fnamemodify(file, ":t") or "nil"
		print(marker .. i .. ": " .. filename)
	end
end

--- Display cache performance statistics
function M.show_cache_stats()
	print("=== Pebble Cache Statistics ===")
	print("File cache valid: " .. tostring(cache_valid))
	print("File cache entries: " .. vim.tbl_count(file_cache))
	print("Link cache entries: " .. vim.tbl_count(link_cache))
	print("Graph cache entries: " .. vim.tbl_count(graph_cache))
	print("Max files to scan: " .. MAX_FILES_TO_SCAN)
	print("Graph cache TTL: " .. GRAPH_CACHE_TTL .. "ms")

	local now = vim.loop.hrtime() / 1000000
	print("\nGraph cache details:")
	for file, cached in pairs(graph_cache) do
		local age = now - cached.timestamp
		local expired = age > GRAPH_CACHE_TTL
		print("  " .. file .. ": " .. math.floor(age) .. "ms old" .. (expired and " (expired)" or " (valid)"))
	end

	print("\nLink cache details:")
	for file, cached in pairs(link_cache) do
		print("  " .. vim.fn.fnamemodify(file, ":t") .. ": " .. #cached.links .. " links")
	end
end

--- Toggle markdown checklist/todo items on current line
function M.toggle_checklist()
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_get_current_line()

	local patterns = {
		{ pattern = "^(%s*)%- %[ %] (.*)$", replacement = "%1- [x] %2" },
		{ pattern = "^(%s*)%- %[x%] (.*)$", replacement = "%1- [ ] %2" },
		{ pattern = "^(%s*)%- %[X%] (.*)$", replacement = "%1- [ ] %2" },
		{ pattern = "^(%s*)%* %[ %] (.*)$", replacement = "%1* [x] %2" },
		{ pattern = "^(%s*)%* %[x%] (.*)$", replacement = "%1* [ ] %2" },
		{ pattern = "^(%s*)%* %[X%] (.*)$", replacement = "%1* [ ] %2" },
		{ pattern = "^(%s*)(%d+%.) %[ %] (.*)$", replacement = "%1%2 [x] %3" },
		{ pattern = "^(%s*)(%d+%.) %[x%] (.*)$", replacement = "%1%2 [ ] %3" },
		{ pattern = "^(%s*)(%d+%.) %[X%] (.*)$", replacement = "%1%2 [ ] %3" },
	}

	for _, p in ipairs(patterns) do
		local new_line = line:gsub(p.pattern, p.replacement)
		if new_line ~= line then
			vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, { new_line })
			return
		end
	end

	local create_patterns = {
		{ pattern = "^(%s*)%- (.*)$", replacement = "%1- [ ] %2" },
		{ pattern = "^(%s*)%* (.*)$", replacement = "%1* [ ] %2" },
		{ pattern = "^(%s*)(%d+%.) (.*)$", replacement = "%1%2 [ ] %3" },
	}

	for _, p in ipairs(create_patterns) do
		local new_line = line:gsub(p.pattern, p.replacement)
		if new_line ~= line then
			vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, { new_line })
			return
		end
	end

	local indent = line:match("^(%s*)")
	local content = line:match("^%s*(.*)$")
	if content and content ~= "" then
		local new_line = indent .. "- [ ] " .. content
		vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, { new_line })
	end
end

--- Increase heading level on current line
function M.increase_heading()
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_get_current_line()
	
	-- Check if line already has heading
	local indent, hashes, content = line:match("^(%s*)(#+)(%s*.*)$")
	if hashes then
		if #hashes < 6 then -- Don't go beyond h6
			local new_line = indent .. "#" .. hashes .. content
			vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, { new_line })
		end
	else
		-- Create first level heading, handle empty lines
		local trimmed_line = line:match("^%s*(.-)%s*$") or ""
		if trimmed_line == "" then
			vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, { "# " })
			-- Position cursor after the space
			vim.api.nvim_win_set_cursor(0, { line_num, 2 })
		else
			local new_line = "# " .. line
			vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, { new_line })
		end
	end
end

--- Decrease heading level on current line
function M.decrease_heading()
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_get_current_line()
	
	-- Check if line has heading
	local indent, hashes, content = line:match("^(%s*)(#+)(%s*.*)$")
	if indent and hashes then
		if #hashes > 1 then
			-- Remove one hash
			local new_line = indent .. hashes:sub(2) .. content
			vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, { new_line })
		else
			-- Remove heading completely, keeping just the content
			local clean_content = content:match("^%s*(.*)$") or ""
			local new_line = indent .. clean_content
			vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, { new_line })
		end
	end
end

--- Initialize YAML header if not present
function M.init_yaml_header()
	-- Check if buffer is empty or if YAML header already exists
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	
	-- If buffer is empty or first line is not YAML start, add header
	if #lines == 0 or lines[1] ~= "---" then
		-- Get the current file name for title
		local current_file = vim.api.nvim_buf_get_name(0)
		local title = "Untitled"
		
		if current_file and current_file ~= "" then
			title = vim.fn.fnamemodify(current_file, ":t:r")
		end
		
		-- Create default YAML header
		local yaml_header = {
			"---",
			"title: " .. title,
			"aliases: []",
			"tags: []",
			"created: " .. os.date("%Y-%m-%d"),
			"---",
			""
		}
		
		-- Insert at the beginning of the buffer
		vim.api.nvim_buf_set_lines(0, 0, 0, false, yaml_header)
		
		-- Position cursor after the header
		vim.api.nvim_win_set_cursor(0, {#yaml_header + 1, 0})
		
		vim.notify("YAML header initialized", vim.log.levels.INFO)
	else
		vim.notify("YAML header already exists", vim.log.levels.INFO)
	end
end

--- Extract text from current visual selection
local function get_visual_selection()
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)

	local start_pos = vim.api.nvim_buf_get_mark(0, "<")
	local end_pos = vim.api.nvim_buf_get_mark(0, ">")
	local start_row, start_col = start_pos[1] - 1, start_pos[2]
	local end_row, end_col = end_pos[1] - 1, end_pos[2]

	local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col + 1, {})

	if #lines == 0 then
		return ""
	end

	return table.concat(lines, " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
end

--- Create a link from selection, create the file, and navigate to it
function M.create_link_and_navigate()
	local selection = get_visual_selection()
	if selection == "" then
		vim.notify("No text selected", vim.log.levels.WARN)
		return
	end

	local filename = selection:gsub('[/\\:*?"<>|]', ""):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
	if filename == "" then
		vim.notify("Selection doesn't contain valid filename characters", vim.log.levels.WARN)
		return
	end

	local link_text = "[[" .. filename .. "]]"

	local start_pos = vim.api.nvim_buf_get_mark(0, "<")
	local end_pos = vim.api.nvim_buf_get_mark(0, ">")
	local start_row, start_col = start_pos[1] - 1, start_pos[2]
	local end_row, end_col = end_pos[1] - 1, end_pos[2] + 1

	vim.api.nvim_buf_set_text(0, start_row, start_col, end_row, end_col, { link_text })

	local existing_file = find_markdown_file(filename)
	if existing_file then
		add_current_to_history()
		vim.cmd("edit " .. vim.fn.fnameescape(existing_file))
		vim.notify("Linked to existing file: " .. filename .. ".md", vim.log.levels.INFO)
	else
		local new_file_path = create_new_file(filename, selection)
		add_current_to_history()
		vim.cmd("edit " .. vim.fn.fnameescape(new_file_path))
		vim.notify("Created link and file: " .. filename .. ".md", vim.log.levels.INFO)
	end
end

--- Create a link from selection and create the file without navigation
function M.create_link_and_file()
	local selection = get_visual_selection()
	if selection == "" then
		vim.notify("No text selected", vim.log.levels.WARN)
		return
	end

	local link_name = selection:gsub('[/\\:*?"<>|]', ""):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
	if link_name == "" then
		vim.notify("Selection doesn't contain valid link characters", vim.log.levels.WARN)
		return
	end

	local link_text = "[[" .. link_name .. "]]"

	local start_pos = vim.api.nvim_buf_get_mark(0, "<")
	local end_pos = vim.api.nvim_buf_get_mark(0, ">")
	local start_row, start_col = start_pos[1] - 1, start_pos[2]
	local end_row, end_col = end_pos[1] - 1, end_pos[2] + 1

	vim.api.nvim_buf_set_text(0, start_row, start_col, end_row, end_col, { link_text })

	local existing_file = find_markdown_file(link_name)
	if existing_file then
		vim.notify("Created link: " .. link_text .. " (file already exists)", vim.log.levels.INFO)
	else
		create_new_file(link_name, selection)
		vim.notify("Created link and file: " .. link_name .. ".md", vim.log.levels.INFO)
	end
end

--- Find all links in a file with caching for performance
local function find_links_in_file(file_path)
	if not vim.fn.filereadable(file_path) then
		return {}
	end

	local file_stat = vim.loop.fs_stat(file_path)
	if not file_stat then
		return {}
	end

	local cache_key = file_path
	local cached_entry = link_cache[cache_key]

	if cached_entry and cached_entry.mtime >= file_stat.mtime.sec then
		return cached_entry.links
	end

	local links = {}
	local lines = vim.fn.readfile(file_path, "", 100)

	for _, line in ipairs(lines) do
		local start = 1
		while true do
			local s, e = line:find("%[%[[^%]]+%]%]", start)
			if not s then
				break
			end
			local link = line:sub(s + 2, e - 2)
			if link ~= "" then
				table.insert(links, link)
			end
			start = e + 1
		end

		start = 1
		while true do
			local s, e = line:find("%[[^%]]*%]%([^%)]+%)", start)
			if not s then
				break
			end
			local paren_start = line:find("%(", s)
			local paren_end = line:find("%)", paren_start)
			if paren_start and paren_end then
				local link = line:sub(paren_start + 1, paren_end - 1)
				if link:match("%.md$") or not link:match("%.") then
					link = link:gsub("%.md$", "")
					if link ~= "" then
						table.insert(links, link)
					end
				end
			end
			start = e + 1
		end
	end

	link_cache[cache_key] = {
		links = links,
		mtime = file_stat.mtime.sec,
	}

	return links
end

-- Removed complex build_comprehensive_graph - was causing performance issues

--- Build a simple, fast graph showing only direct connections
local function build_simple_graph(current_name)
	local current_file = vim.api.nvim_buf_get_name(0)
	local graph = {}
	
	-- Initialize current file node
	graph[current_name] = {
		file_path = current_file,
		outgoing = {},
		incoming = {},
	}
	
	-- Get links from current file only (fast, no recursion)
	local links = find_links_in_file(current_file)
	for _, link_name in ipairs(links) do
		if link_name ~= "" and link_name ~= current_name then
			graph[current_name].outgoing[link_name] = true
			
			-- Initialize target node (minimal data for performance)
			if not graph[link_name] then
				local target_path = find_markdown_file(link_name)
				graph[link_name] = {
					file_path = target_path,
					outgoing = {},
					incoming = {}, -- Keep structure but don't populate
				}
			end
			-- Don't populate incoming links to avoid scanning requirement
		end
	end
	
	return graph
end

--- Build a graph of connections between markdown files with caching
local function build_link_graph()
	local current_file = vim.api.nvim_buf_get_name(0)
	local current_name = vim.fn.fnamemodify(current_file, ":t:r")
	local now = vim.loop.hrtime() / 1000000

	local cache_key = current_name
	local cached_graph = graph_cache[cache_key]

	if cached_graph and (now - cached_graph.timestamp) < GRAPH_CACHE_TTL then
		return cached_graph.graph, current_name
	end

	-- Use simple graph instead of comprehensive (performance)
	local graph = build_simple_graph(current_name)

	graph_cache[cache_key] = {
		graph = graph,
		timestamp = now,
	}

	-- Clean old cache entries
	for key, cached in pairs(graph_cache) do
		if (now - cached.timestamp) > (GRAPH_CACHE_TTL * 2) then
			graph_cache[key] = nil
		end
	end

	return graph, current_name
end


--- Toggle the interactive graph view
function M.toggle_graph()
	-- Check if telescope is available
	local telescope_ok, telescope = pcall(require, 'telescope')
	if not telescope_ok then
		vim.notify("Telescope is required for graph functionality. Please install telescope.nvim", vim.log.levels.ERROR)
		return
	end
	
	local pickers_ok, pickers = pcall(require, 'telescope.pickers')
	local finders_ok, finders = pcall(require, 'telescope.finders')
	local conf_ok, conf = pcall(require, 'telescope.config')
	local actions_ok, actions = pcall(require, 'telescope.actions')
	local action_state_ok, action_state = pcall(require, 'telescope.actions.state')
	
	if not (pickers_ok and finders_ok and conf_ok and actions_ok and action_state_ok) then
		vim.notify("Telescope modules not available. Please ensure telescope.nvim is properly installed", vim.log.levels.ERROR)
		return
	end

	local graph, current_name = build_link_graph()
	
	-- Create a list of all linked files for telescope
	local graph_entries = {}
	
	-- Skip incoming links detection to prevent performance issues
	-- (Finding incoming links requires scanning all files, causing freezes)
	
	-- Add current file
	table.insert(graph_entries, {
		filename = current_name,
		display = "● " .. current_name .. " (current)",
		file_path = vim.api.nvim_buf_get_name(0),
		type = "current"
	})
	
	-- Add outgoing links  
	for file, _ in pairs(graph[current_name].outgoing) do
		local file_info = graph[file]
		local exists = file_info and file_info.file_path and vim.fn.filereadable(file_info.file_path) == 1
		local display_text = "──► " .. file .. " (outgoing)" .. (exists and "" or " [missing]")
		table.insert(graph_entries, {
			filename = file,
			display = display_text,
			file_path = file_info and file_info.file_path,
			type = "outgoing",
			exists = exists
		})
	end
	
	-- Skip orphaned files detection to maintain performance
	
	if #graph_entries == 0 then
		vim.notify("No linked files found", vim.log.levels.INFO)
		return
	end
	
	-- Create telescope picker
	local picker = pickers.new({}, {
		prompt_title = "Markdown Link Graph - " .. current_name,
		finder = finders.new_table({
			results = graph_entries,
			entry_maker = function(entry)
				return {
					value = entry,
					display = entry.display,
					ordinal = entry.filename,
					path = entry.file_path,
				}
			end,
		}),
		sorter = conf.values.generic_sorter({}),
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				actions.close(prompt_bufnr)
				local selection = action_state.get_selected_entry()
				if selection and selection.value then
					local entry = selection.value
					if entry.type == "current" then
						-- Already in current file, do nothing special
						return
					end
					
					if entry.file_path and vim.fn.filereadable(entry.file_path) == 1 then
						add_current_to_history()
						vim.cmd("edit " .. vim.fn.fnameescape(entry.file_path))
					elseif entry.type == "outgoing" and not entry.exists then
						-- For missing outgoing links, try to create the file
						local potential_path = vim.fn.expand("%:h") .. "/" .. entry.filename .. ".md"
						add_current_to_history()
						vim.cmd("edit " .. vim.fn.fnameescape(potential_path))
						vim.notify("Created new file: " .. entry.filename, vim.log.levels.INFO)
					else
						vim.notify("File not found: " .. entry.filename, vim.log.levels.WARN)
					end
				end
			end)
			return true
		end,
	})
	
	picker:find()
end

--- Setup tags syntax highlighting for markdown files
local function setup_tags_syntax(opts)
	opts = opts or {}
	local enable_tags = opts.enable_tags ~= false -- Default to true
	local tag_color = opts.tag_highlight or "Special"
	
	if not enable_tags then
		return
	end
	
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "markdown",
		callback = function()
			-- Add hashtag syntax highlighting - improved pattern to handle more cases
			vim.cmd([[
				syntax match PebbleTag /#[a-zA-Z0-9_-]\+/ containedin=ALL
				highlight link PebbleTag ]] .. tag_color .. [[
			]])
		end,
	})
end

--- Initialize the plugin with configuration options
function M.setup(opts)
	opts = opts or {}

	-- Setup tags syntax highlighting
	setup_tags_syntax(opts)

	vim.api.nvim_create_autocmd({ "BufWritePost", "BufNewFile", "BufDelete" }, {
		pattern = "*.md",
		callback = invalidate_graph_caches,
	})

	vim.api.nvim_create_autocmd({ "BufReadPost" }, {
		pattern = "*.md",
		callback = function()
			if is_navigating_history then
				return
			end

			vim.defer_fn(function()
				add_current_to_history()
			end, 50)
		end,
	})

	vim.api.nvim_create_user_command("PebbleFollow", M.follow_link, { desc = "Follow link under cursor" })
	vim.api.nvim_create_user_command("PebbleNext", M.next_link, { desc = "Go to next link" })
	vim.api.nvim_create_user_command("PebblePrev", M.prev_link, { desc = "Go to previous link" })
	vim.api.nvim_create_user_command("PebbleBack", M.go_back, { desc = "Go back in navigation history" })
	vim.api.nvim_create_user_command("PebbleForward", M.go_forward, { desc = "Go forward in navigation history" })
	vim.api.nvim_create_user_command("PebbleGraph", M.toggle_graph, { desc = "Toggle link graph view" })
	vim.api.nvim_create_user_command("PebbleHistory", M.show_history, { desc = "Show navigation history" })
	vim.api.nvim_create_user_command("PebbleStats", M.show_cache_stats, { desc = "Show cache statistics" })
	vim.api.nvim_create_user_command(
		"PebbleToggleChecklist",
		M.toggle_checklist,
		{ desc = "Toggle markdown checklist/todo item" }
	)
	vim.api.nvim_create_user_command("PebbleCreateLinkAndNavigate", function()
		vim.notify("Select text in visual mode first", vim.log.levels.WARN)
	end, { desc = "Create link, file and navigate (use in visual mode)" })
	vim.api.nvim_create_user_command("PebbleCreateLinkAndFile", function()
		vim.notify("Select text in visual mode first", vim.log.levels.WARN)
	end, { desc = "Create link and file without navigation (use in visual mode)" })
	vim.api.nvim_create_user_command(
		"PebbleIncreaseHeading",
		M.increase_heading,
		{ desc = "Increase markdown heading level" }
	)
	vim.api.nvim_create_user_command(
		"PebbleDecreaseHeading", 
		M.decrease_heading,
		{ desc = "Decrease markdown heading level" }
	)
	vim.api.nvim_create_user_command(
		"PebbleInitHeader",
		M.init_yaml_header,
		{ desc = "Initialize YAML header" }
	)
	vim.api.nvim_create_user_command(
		"PebbleBase",
		function(opts)
			local bases = require("pebble.bases")
			if opts.args ~= "" then
				bases.open_base(opts.args)
			else
				bases.open_current_base()
			end
		end,
		{ desc = "Open a base view", nargs = "?", complete = "file" }
	)
	vim.api.nvim_create_user_command(
		"PebbleBases",
		function()
			require("pebble.bases").list_bases()
		end,
		{ desc = "List and select available bases" }
	)

	if opts.auto_setup_keymaps ~= false then
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "markdown",
			callback = function()
				local buf_opts = { buffer = true, silent = true }
				vim.keymap.set(
					"n",
					"<CR>",
					M.follow_link,
					vim.tbl_extend("force", buf_opts, { desc = "Follow markdown link" })
				)
				vim.keymap.set(
					"n",
					"<Tab>",
					M.next_link,
					vim.tbl_extend("force", buf_opts, { desc = "Next markdown link" })
				)
				vim.keymap.set(
					"n",
					"<S-Tab>",
					M.prev_link,
					vim.tbl_extend("force", buf_opts, { desc = "Previous markdown link" })
				)
				vim.keymap.set(
					"n",
					"<leader>mg",
					M.toggle_graph,
					vim.tbl_extend("force", buf_opts, { desc = "Toggle markdown graph" })
				)
				vim.keymap.set(
					{ "n", "i" },
					"<C-t>",
					M.toggle_checklist,
					vim.tbl_extend("force", buf_opts, { desc = "Toggle markdown checklist" })
				)
				vim.keymap.set(
					{ "n", "i" },
					"<leader>mt",
					M.toggle_checklist,
					vim.tbl_extend("force", buf_opts, { desc = "Toggle markdown checklist" })
				)
				vim.keymap.set(
					"v",
					"<leader>mc",
					M.create_link_and_navigate,
					vim.tbl_extend("force", buf_opts, { desc = "Create link, file and navigate" })
				)
				vim.keymap.set(
					"v",
					"<leader>ml",
					M.create_link_and_file,
					vim.tbl_extend("force", buf_opts, { desc = "Create link and file" })
				)
				vim.keymap.set(
					"n",
					"+",
					M.increase_heading,
					vim.tbl_extend("force", buf_opts, { desc = "Increase heading level" })
				)
				vim.keymap.set(
					"n",
					"-",
					M.decrease_heading,
					vim.tbl_extend("force", buf_opts, { desc = "Decrease heading level" })
				)
				vim.keymap.set(
					"n",
					"<leader>mh",
					M.init_yaml_header,
					vim.tbl_extend("force", buf_opts, { desc = "Initialize YAML header" })
				)
			end,
		})
		
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "base",
			callback = function()
				local buf_opts = { buffer = true, silent = true }
				vim.keymap.set(
					"n",
					"<leader>bo",
					function() require("pebble.bases").open_current_base() end,
					vim.tbl_extend("force", buf_opts, { desc = "Open current base view" })
				)
			end,
		})
	end

	if opts.global_keymaps then
		vim.keymap.set("n", "<leader>mg", M.toggle_graph, { desc = "Toggle markdown graph" })
		vim.keymap.set("n", "<leader>mp", M.go_back, { desc = "Go to previous in markdown history" })
		vim.keymap.set("n", "<leader>mn", M.go_forward, { desc = "Go to next in markdown history" })
		vim.keymap.set("n", "<leader>mB", function() require("pebble.bases").list_bases() end, { desc = "List available bases" })
		vim.keymap.set("n", "<leader>mb", function() require("pebble.bases").open_current_base() end, { desc = "Open current/select base view" })
	end
end

return M

