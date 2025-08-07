local M = {}

local file_cache = {}
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

--- Build cache of all markdown files in the current repository or directory
local function build_file_cache()
	file_cache = {}
	local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
	local cwd = (vim.v.shell_error == 0 and git_root ~= "") and git_root or vim.fn.getcwd()

	local md_files = vim.fs.find(function(name)
		return name:match("%.md$")
	end, {
		path = cwd,
		type = "file",
		limit = 1000,
		upward = false,
	})

	for _, file_path in ipairs(md_files) do
		local filename = vim.fn.fnamemodify(file_path, ":t:r")
		if not file_cache[filename] then
			file_cache[filename] = {}
		end
		table.insert(file_cache[filename], file_path)
	end

	cache_valid = true
end

--- Invalidate the file cache when files change
local function invalidate_cache()
	cache_valid = false
end

--- Invalidate all caches including graph and link caches
local function invalidate_graph_caches()
	graph_cache = {}
	link_cache = {}
	cache_valid = false
	graph_cache_timestamp = 0
end

--- Get the link under the cursor and determine its type
local function get_link_under_cursor()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1

	local obsidian_start, obsidian_end = line:find("%[%[[^%]]*%]%]")
	if obsidian_start and obsidian_end and col >= obsidian_start and col <= obsidian_end then
		local link_text = line:sub(obsidian_start + 2, obsidian_end - 2)
		return link_text, "obsidian"
	end

	local md_start, md_end = line:find("%[[^%]]*%]%([^%)]*%)")
	if md_start and md_end and col >= md_start and col <= md_end then
		local paren_start = line:find("%(", md_start)
		local paren_end = line:find("%)", paren_start)
		if paren_start and paren_end then
			local link_url = line:sub(paren_start + 1, paren_end - 1)
			return link_url, "markdown"
		end
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

	local search_name = filename:gsub("%.md$", "")
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
		local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
		target_dir = (vim.v.shell_error == 0 and git_root ~= "") and git_root or vim.fn.getcwd()
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
	local link, link_type = get_link_under_cursor()
	if link and link_type then
		open_link(link, link_type)
	else
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
	end
end

--- Find all markdown links in the current buffer
local function find_all_links()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local links = {}

	for line_num, line in ipairs(lines) do
		for start_pos, end_pos in line:gmatch("()%[%[[^%]]*%]%]()") do
			table.insert(links, {
				line = line_num,
				col = start_pos,
				end_col = end_pos - 1,
				type = "obsidian",
			})
		end

		for start_pos, end_pos in line:gmatch("()%[[^%]]*%]%([^%)]*%)()") do
			table.insert(links, {
				line = line_num,
				col = start_pos,
				end_col = end_pos - 1,
				type = "markdown",
			})
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

--- Build a comprehensive graph with depth 3 connections between markdown files
local function build_comprehensive_graph(current_name, max_depth)
	max_depth = max_depth or 3
	local graph = {}
	local processed = {}
	local to_process = { { name = current_name, level = 0 } }

	if not cache_valid then
		build_file_cache()
	end

	-- Initialize current file
	local current_file = vim.api.nvim_buf_get_name(0)
	graph[current_name] = {
		file_path = current_file,
		outgoing = {},
		incoming = {},
		level = 0,
	}

	while #to_process > 0 do
		local current = table.remove(to_process, 1)
		local name, level = current.name, current.level

		if processed[name] or level > max_depth then
			goto continue
		end

		processed[name] = true

		-- Get file path for this node
		local file_path = name == current_name and current_file or find_markdown_file(name)
		if not file_path then
			goto continue
		end

		-- Initialize node if not exists
		if not graph[name] then
			graph[name] = {
				file_path = file_path,
				outgoing = {},
				incoming = {},
				level = level,
			}
		end

		-- Find all outgoing links from this file
		local links = find_links_in_file(file_path)
		for _, link in ipairs(links) do
			if link ~= name then -- Avoid self-references
				-- Initialize target node
				if not graph[link] then
					local target_file = find_markdown_file(link)
					graph[link] = {
						file_path = target_file,
						outgoing = {},
						incoming = {},
						level = level + 1,
					}
				end

				-- Create bidirectional relationship
				graph[name].outgoing[link] = true
				graph[link].incoming[name] = true

				-- Add to processing queue if not too deep
				if level < max_depth and not processed[link] then
					table.insert(to_process, { name = link, level = level + 1 })
				end
			end
		end

		::continue::
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

	local graph = build_comprehensive_graph(current_name, 3)

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

--- Create clean text representation of the graph with interactive elements
local function create_graph_text(graph, current_name)
	local lines = {}
	local processed = {}
	local interactive_lines = {}

	local function add_line(content, is_interactive, filename)
		lines[#lines + 1] = content
		interactive_lines[#lines] = {
			interactive = is_interactive or false,
			filename = filename,
		}
	end

	local incoming_files = {}
	local outgoing_files = {}
	local orphaned = {}

	for file, _ in pairs(graph[current_name].incoming) do
		table.insert(incoming_files, file)
	end
	table.sort(incoming_files)

	for file, _ in pairs(graph[current_name].outgoing) do
		table.insert(outgoing_files, file)
	end
	table.sort(outgoing_files)

	for _, file in ipairs(incoming_files) do
		processed[file] = true
	end
	for _, file in ipairs(outgoing_files) do
		processed[file] = true
	end

	for file, _ in pairs(graph) do
		if not processed[file] and file ~= current_name then
			table.insert(orphaned, file)
		end
	end
	table.sort(orphaned)

	add_line("Pebble - Markdown Link Graph", false)
	add_line("", false)

	if #incoming_files > 0 then
		add_line("◄── Incoming Links:", false)
		for _, file in ipairs(incoming_files) do
			add_line("  ➤ " .. file, true, file)
		end
		add_line("", false)
	end

	local current_display = "● " .. current_name .. " (current)"
	add_line(current_display, false)
	add_line("", false)

	if #outgoing_files > 0 then
		add_line("──► Outgoing Links:", false)
		for _, file in ipairs(outgoing_files) do
			local exists = graph[file] and graph[file].file_path and vim.fn.filereadable(graph[file].file_path) == 1
			local marker = exists and "➤ " or "✗ "
			local interactive = exists
			add_line("  " .. marker .. file, interactive, exists and file or nil)
		end
		add_line("", false)
	end

	if #orphaned > 0 then
		add_line("○ Other Connected Files:", false)
		local orphaned_limit = math.min(#orphaned, 5)
		for i = 1, orphaned_limit do
			local file = orphaned[i]
			local exists = graph[file] and graph[file].file_path and vim.fn.filereadable(graph[file].file_path) == 1
			local marker = exists and "➤ " or "○ "
			add_line("  " .. marker .. file, exists, exists and file or nil)
		end
		if #orphaned > 5 then
			local more_count = #orphaned - 5
			add_line("  ... and " .. more_count .. " more", false)
		end
		add_line("", false)
	end

	local total_files = 0
	for _ in pairs(graph) do
		total_files = total_files + 1
	end

	add_line(
		"Total files: " .. total_files .. " │ Outgoing: " .. #outgoing_files .. " │ Incoming: " .. #incoming_files,
		false
	)
	add_line("", false)
	add_line("↑/↓: Navigate │ Enter: Open │ q: Close", false)

	return lines, interactive_lines
end

--- Set up syntax highlighting for the graph view
local function setup_graph_syntax(buf)
	vim.api.nvim_buf_call(buf, function()
		vim.cmd("syntax clear")

		vim.cmd("syntax match GraphTitle /^Pebble - Markdown Link Graph$/")
		vim.cmd("syntax match GraphCurrent /^● .* (current)$/")

		vim.cmd("syntax match GraphInteractiveMarker /➤/ contained")
		vim.cmd("syntax match GraphInteractiveFile /\\(➤ \\)\\@<=.*$/ contained")
		vim.cmd("syntax match GraphInteractiveLine /^  ➤ .*$/ contains=GraphInteractiveMarker,GraphInteractiveFile")

		vim.cmd("syntax match GraphMissingMarker /✗/ contained")
		vim.cmd("syntax match GraphMissingFile /\\(✗ \\)\\@<=.*$/ contained")
		vim.cmd("syntax match GraphMissingLine /^  ✗ .*$/ contains=GraphMissingMarker,GraphMissingFile")

		vim.cmd("syntax match GraphSection /^◄──.*:\\|^──►.*:\\|^○.*:/")

		vim.cmd("syntax match GraphStats /^Total files.*/")
		vim.cmd("syntax match GraphHelp /^↑\\/↓.*/")

		vim.cmd("highlight GraphTitle guifg=#b4befe ctermfg=147 gui=bold")
		vim.cmd("highlight GraphCurrent guifg=#f9e2af ctermfg=221 gui=bold")

		vim.cmd("highlight GraphInteractiveMarker guifg=#a6e3a1 ctermfg=151 gui=bold")
		vim.cmd("highlight GraphInteractiveFile guifg=#a6e3a1 ctermfg=151")

		vim.cmd("highlight GraphMissingMarker guifg=#f38ba8 ctermfg=210 gui=bold")
		vim.cmd("highlight GraphMissingFile guifg=#f38ba8 ctermfg=210")

		vim.cmd("highlight GraphSection guifg=#89b4fa ctermfg=117 gui=bold")
		vim.cmd("highlight GraphStats guifg=#cdd6f4 ctermfg=189")
		vim.cmd("highlight GraphHelp guifg=#6c7086 ctermfg=245 gui=italic")
	end)
end

--- Find next or previous interactive line in the graph
local function find_interactive_line(interactive_lines, current_line, direction)
	local lines = {}
	for line_num, data in pairs(interactive_lines) do
		if data.interactive then
			table.insert(lines, line_num)
		end
	end

	if #lines == 0 then
		return current_line
	end

	table.sort(lines)

	local current_idx = 1
	for i, line_num in ipairs(lines) do
		if line_num >= current_line then
			current_idx = i
			break
		end
	end

	if direction > 0 then
		current_idx = current_idx + 1
		if current_idx > #lines then
			current_idx = 1
		end
	else
		current_idx = current_idx - 1
		if current_idx < 1 then
			current_idx = #lines
		end
	end

	return lines[current_idx]
end

--- Toggle the interactive graph view
function M.toggle_graph()
	if graph_win and vim.api.nvim_win_is_valid(graph_win) then
		vim.api.nvim_win_close(graph_win, true)
		if graph_buf and vim.api.nvim_buf_is_valid(graph_buf) then
			vim.api.nvim_buf_delete(graph_buf, { force = true })
		end
		graph_win = nil
		graph_buf = nil
		return
	end

	local graph, current_name = build_link_graph()
	local graph_lines, interactive_lines = create_graph_text(graph, current_name)

	graph_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(graph_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(graph_buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(graph_buf, "filetype", "pebble-graph")
	vim.api.nvim_buf_set_option(graph_buf, "modifiable", false)

	vim.api.nvim_buf_set_option(graph_buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(graph_buf, 0, -1, false, graph_lines)
	vim.api.nvim_buf_set_option(graph_buf, "modifiable", false)

	setup_graph_syntax(graph_buf)

	local height = math.min(#graph_lines + 2, math.floor(vim.o.lines * 0.4))
	vim.cmd("botright " .. height .. "split")
	graph_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(graph_win, graph_buf)

	vim.api.nvim_win_set_option(graph_win, "wrap", false)
	vim.api.nvim_win_set_option(graph_win, "cursorline", true)
	vim.api.nvim_win_set_option(graph_win, "number", false)
	vim.api.nvim_win_set_option(graph_win, "relativenumber", false)
	vim.api.nvim_win_set_option(graph_win, "signcolumn", "no")
	vim.api.nvim_win_set_option(graph_win, "cursorlineopt", "both")

	local opts = { buffer = graph_buf, nowait = true, silent = true }

	vim.keymap.set("n", "q", M.toggle_graph, opts)
	vim.keymap.set("n", "<ESC>", M.toggle_graph, opts)

	vim.keymap.set("n", "j", function()
		local current_line = vim.api.nvim_win_get_cursor(graph_win)[1]
		local next_line = find_interactive_line(interactive_lines, current_line, 1)
		vim.api.nvim_win_set_cursor(graph_win, { next_line, 0 })
	end, opts)

	vim.keymap.set("n", "k", function()
		local current_line = vim.api.nvim_win_get_cursor(graph_win)[1]
		local prev_line = find_interactive_line(interactive_lines, current_line, -1)
		vim.api.nvim_win_set_cursor(graph_win, { prev_line, 0 })
	end, opts)

	vim.keymap.set("n", "<Down>", function()
		local current_line = vim.api.nvim_win_get_cursor(graph_win)[1]
		local next_line = find_interactive_line(interactive_lines, current_line, 1)
		vim.api.nvim_win_set_cursor(graph_win, { next_line, 0 })
	end, opts)

	vim.keymap.set("n", "<Up>", function()
		local current_line = vim.api.nvim_win_get_cursor(graph_win)[1]
		local prev_line = find_interactive_line(interactive_lines, current_line, -1)
		vim.api.nvim_win_set_cursor(graph_win, { prev_line, 0 })
	end, opts)

	vim.keymap.set("n", "<CR>", function()
		local current_line = vim.api.nvim_win_get_cursor(graph_win)[1]
		local line_data = interactive_lines[current_line]

		if line_data and line_data.interactive and line_data.filename then
			M.toggle_graph()
			local file_path = find_markdown_file(line_data.filename)
			if file_path then
				add_current_to_history()
				vim.cmd("edit " .. vim.fn.fnameescape(file_path))
			else
				vim.notify("File not found: " .. line_data.filename, vim.log.levels.WARN)
			end
		end
	end, opts)

	vim.cmd("normal! gg")
	local first_interactive = find_interactive_line(interactive_lines, 1, 1)
	if first_interactive then
		vim.api.nvim_win_set_cursor(graph_win, { first_interactive, 0 })
	end
end

--- Initialize the plugin with configuration options
function M.setup(opts)
	opts = opts or {}

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
			end,
		})
	end

	if opts.global_keymaps then
		vim.keymap.set("n", "<leader>mg", M.toggle_graph, { desc = "Toggle markdown graph" })
		vim.keymap.set("n", "<leader>mb", M.go_back, { desc = "Go back in markdown history" })
		vim.keymap.set("n", "<leader>mf", M.go_forward, { desc = "Go forward in markdown history" })
	end
end

return M

