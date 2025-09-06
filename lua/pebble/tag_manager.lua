local M = {}

-- Tag management for pebble.nvim
-- Provides functionality to add, view, and search tags in markdown files

local search = require("pebble.search")

-- Cache for tag data
local tag_cache = {}
local cache_timestamp = 0
local CACHE_TTL = 30000 -- 30 seconds

-- Extract tags from a file's content
local function extract_tags_from_file(file_path)
	if vim.fn.filereadable(file_path) ~= 1 then
		return {}
	end
	
	local tags = {}
	local lines = vim.fn.readfile(file_path, "", 100) -- Read first 100 lines
	local in_frontmatter = false
	local frontmatter_tags = {}
	
	for i, line in ipairs(lines) do
		-- Check for YAML frontmatter tags
		if i == 1 and line == "---" then
			in_frontmatter = true
		elseif in_frontmatter and (line == "---" or line == "...") then
			in_frontmatter = false
		elseif in_frontmatter then
			-- Parse frontmatter tags
			local tags_match = line:match("^%s*tags:%s*%[(.*)%]")
			if tags_match then
				for tag in tags_match:gmatch("([^,]+)") do
					tag = tag:gsub("[%s\"']", "") -- Remove quotes and spaces
					if tag ~= "" then
						table.insert(frontmatter_tags, tag)
					end
				end
			elseif line:match("^%s*tags:") then
				-- Multi-line tags format
				local j = i + 1
				while j <= #lines and lines[j]:match("^%s*-%s*") do
					local tag = lines[j]:match("^%s*-%s*(.+)")
					if tag then
						tag = tag:gsub("[\"']", "") -- Remove quotes
						table.insert(frontmatter_tags, tag)
					end
					j = j + 1
				end
			end
		end
		
		-- Extract inline tags (#tag format) - matches both single and multi-char tags
		for tag in line:gmatch("#([a-zA-Z0-9_][a-zA-Z0-9_/%-]*)") do
			if not vim.tbl_contains(tags, tag) then
				table.insert(tags, tag)
			end
		end
	end
	
	-- Combine frontmatter and inline tags
	for _, tag in ipairs(frontmatter_tags) do
		if not vim.tbl_contains(tags, tag) then
			table.insert(tags, tag)
		end
	end
	
	return tags
end

-- Get tags for the current file
function M.get_current_file_tags()
	local current_file = vim.api.nvim_buf_get_name(0)
	if not current_file or current_file == "" or not current_file:match("%.md$") then
		return {}
	end
	
	return extract_tags_from_file(current_file)
end

-- Add a tag to the current file
function M.add_tag_to_current_file(tag)
	local current_file = vim.api.nvim_buf_get_name(0)
	if not current_file or current_file == "" or not current_file:match("%.md$") then
		vim.notify("Not in a markdown file", vim.log.levels.WARN)
		return false
	end
	
	if not tag or tag == "" then
		vim.notify("Invalid tag", vim.log.levels.WARN)
		return false
	end
	
	-- Clean the tag
	tag = tag:gsub("[^a-zA-Z0-9_/%-]", "")
	if tag == "" then
		vim.notify("Invalid tag format", vim.log.levels.WARN)
		return false
	end
	
	local current_tags = M.get_current_file_tags()
	if vim.tbl_contains(current_tags, tag) then
		vim.notify("Tag '" .. tag .. "' already exists in this file", vim.log.levels.INFO)
		return false
	end
	
	-- Get current buffer lines
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local has_frontmatter = #lines > 0 and lines[1] == "---"
	local frontmatter_end = 0
	
	if has_frontmatter then
		-- Find end of frontmatter
		for i = 2, #lines do
			if lines[i] == "---" or lines[i] == "..." then
				frontmatter_end = i
				break
			end
		end
	end
	
	if has_frontmatter and frontmatter_end > 0 then
		-- Check if tags field exists in frontmatter
		local tags_line_idx = nil
		local tags_format = nil
		
		for i = 2, frontmatter_end - 1 do
			if lines[i]:match("^%s*tags:%s*%[") then
				tags_line_idx = i
				tags_format = "array"
				break
			elseif lines[i]:match("^%s*tags:%s*$") then
				tags_line_idx = i
				tags_format = "list"
				break
			end
		end
		
		if tags_line_idx then
			if tags_format == "array" then
				-- Add to existing array format: tags: [tag1, tag2]
				local current_tags_str = lines[tags_line_idx]:match("tags:%s*%[(.*)%]")
				local new_tags_str
				if current_tags_str and vim.trim(current_tags_str) ~= "" then
					new_tags_str = string.format("tags: [%s, %s]", current_tags_str, tag)
				else
					new_tags_str = string.format("tags: [%s]", tag)
				end
				lines[tags_line_idx] = new_tags_str
			else
				-- Add to list format
				table.insert(lines, tags_line_idx + 1, "  - " .. tag)
			end
		else
			-- Add new tags field to frontmatter
			table.insert(lines, frontmatter_end, string.format("tags: [%s]", tag))
		end
	else
		-- No frontmatter, create one
		local new_frontmatter = {
			"---",
			"title: " .. vim.fn.fnamemodify(current_file, ":t:r"),
			"tags: [" .. tag .. "]",
			"---",
			""
		}
		
		-- Insert at beginning
		for i = #new_frontmatter, 1, -1 do
			table.insert(lines, 1, new_frontmatter[i])
		end
	end
	
	-- Update buffer
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	vim.notify("Added tag: " .. tag, vim.log.levels.INFO)
	return true
end

-- Get all files that contain a specific tag using ripgrep (optimized)
function M.find_files_with_tag(tag, callback)
	if not search.has_ripgrep() then
		vim.notify("ripgrep is required for tag search", vim.log.levels.ERROR)
		return
	end
	
	local root_dir = search.get_root_dir()
	
	-- Escape special regex characters in tag name
	local escaped_tag = tag:gsub("([%.%-%+%*%?%[%]%^%$%(%)%%])", "\\%1")
	
	-- Use a single optimized ripgrep command with OR patterns for better performance
	local pattern = string.format(
		"(#%s([^a-zA-Z0-9_/%-]|$))|(tags:.*%s)|(- %s$)",
		escaped_tag, escaped_tag, escaped_tag
	)
	
	-- Run single ripgrep search asynchronously to prevent UI freezing
	vim.system({
		"rg", 
		"--type", "md",
		"--files-with-matches",
		"--max-count", "1", -- Stop at first match per file for speed
		pattern,
		root_dir
	}, {}, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				callback({}, "No files found with tag: " .. tag)
				return
			end
			
			local files = vim.split(result.stdout, "\n", {plain = true})
			-- Remove empty lines
			files = vim.tbl_filter(function(file) return file ~= "" end, files)
			
			-- Quick validation: only verify files that are likely matches
			-- This reduces file I/O significantly
			local verified_files = {}
			local batch_size = 10
			local processed = 0
			
			local function process_batch(start_idx)
				local end_idx = math.min(start_idx + batch_size - 1, #files)
				
				for i = start_idx, end_idx do
					local file = files[i]
					local file_tags = extract_tags_from_file(file)
					if vim.tbl_contains(file_tags, tag) then
						table.insert(verified_files, file)
					end
				end
				
				processed = end_idx
				
				if processed < #files then
					-- Schedule next batch to avoid blocking UI
					vim.schedule(function()
						process_batch(processed + 1)
					end)
				else
					-- All done, call callback
					callback(verified_files, nil)
				end
			end
			
			-- Start processing batches
			if #files > 0 then
				process_batch(1)
			else
				callback({}, nil)
			end
		end)
	end)
end

-- Build tag cache using ripgrep for performance (optimized)
local function build_tag_cache()
	if not search.has_ripgrep() then
		return {}
	end
	
	local now = vim.loop.now()
	if tag_cache and cache_timestamp and (now - cache_timestamp) < CACHE_TTL then
		return tag_cache
	end
	
	local root_dir = search.get_root_dir()
	
	-- Use faster ripgrep with optimized flags
	local cmd = {
		"rg", 
		"--type", "md",
		"--no-heading",
		"--no-line-number",
		"--no-filename",
		"--max-count", "100", -- Limit matches per file for speed
		"-o",
		"#[a-zA-Z0-9_][a-zA-Z0-9_/%-]*",
		root_dir
	}
	
	-- Execute command with timeout to prevent hanging
	local result = vim.fn.systemlist(cmd)
	if vim.v.shell_error ~= 0 then
		return {}
	end
	
	local tags = {}
	local tag_set = {} -- Use set for O(1) duplicate checking
	
	for _, line in ipairs(result) do
		local tag = line:match("#(.+)")
		if tag and not tag_set[tag] then
			tag_set[tag] = true
			table.insert(tags, tag)
		end
	end
	
	tag_cache = tags
	cache_timestamp = now
	return tags
end

-- Show UI for current file's tags
function M.show_current_file_tags()
	local current_tags = M.get_current_file_tags()
	
	if #current_tags == 0 then
		vim.notify("No tags found in current file", vim.log.levels.INFO)
		return
	end
	
	-- Check if telescope is available
	local telescope_ok, telescope = pcall(require, 'telescope')
	if not telescope_ok then
		-- Fallback to vim.ui.select
		vim.ui.select(current_tags, {
			prompt = "Select a tag to find other files:",
		}, function(choice)
			if choice then
				M.find_files_with_tag_ui(choice)
			end
		end)
		return
	end
	
	local pickers = require('telescope.pickers')
	local finders = require('telescope.finders')
	local conf = require('telescope.config')
	local actions = require('telescope.actions')
	local action_state = require('telescope.actions.state')
	
	local opts_telescope = require("telescope.themes").get_dropdown({})
	pickers.new(opts_telescope, {
		prompt_title = "Tags in Current File",
		finder = finders.new_table({
			results = current_tags,
			entry_maker = function(entry)
				return {
					value = entry,
					display = "#" .. entry,
					ordinal = entry,
				}
			end,
		}),
		sorter = conf.values.generic_sorter({}),
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				actions.close(prompt_bufnr)
				local selection = action_state.get_selected_entry()
				if selection then
					M.find_files_with_tag_ui(selection.value)
				end
			end)
			return true
		end,
	}):find()
end

-- Show telescope UI for files with a specific tag
function M.find_files_with_tag_ui(tag)
	if not tag then
		vim.ui.input({
			prompt = "Enter tag name: ",
		}, function(input)
			if input and input ~= "" then
				M.find_files_with_tag_ui(input)
			end
		end)
		return
	end
	
	-- Clean the tag (remove # if present)
	tag = tag:gsub("^#", "")
	
	-- Show progress indicator
	vim.notify("🔍 Searching for tag: #" .. tag .. "...", vim.log.levels.INFO)
	
	M.find_files_with_tag(tag, function(files, err)
		if err then
			vim.notify("Error searching for tag: " .. err, vim.log.levels.ERROR)
			return
		end
		
		if not files or #files == 0 then
			vim.notify("❌ No files found with tag: #" .. tag, vim.log.levels.WARN)
			return
		end
		
		-- Show completion notification
		vim.notify("✅ Found " .. #files .. " files with tag: #" .. tag, vim.log.levels.INFO)
		
		-- Check if telescope is available
		local telescope_ok, telescope = pcall(require, 'telescope')
		if not telescope_ok then
			-- Fallback: just open the first file
			vim.cmd("edit " .. vim.fn.fnameescape(files[1]))
			return
		end
		
		local pickers = require('telescope.pickers')
		local finders = require('telescope.finders')
		local conf = require('telescope.config')
		local actions = require('telescope.actions')
		local action_state = require('telescope.actions.state')
		
		local opts_telescope = require("telescope.themes").get_dropdown({})
		pickers.new(opts_telescope, {
			prompt_title = "Files with tag: #" .. tag .. " (" .. #files .. " files)",
			finder = finders.new_table({
				results = files,
				entry_maker = function(entry)
					return {
						value = entry,
						display = vim.fn.fnamemodify(entry, ":."),
						ordinal = entry,
						path = entry,
					}
				end,
			}),
			sorter = conf.values.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						vim.cmd("edit " .. vim.fn.fnameescape(selection.value))
					end
				end)
				return true
			end,
		}):find()
	end)
end

-- Interactive tag addition
function M.add_tag_interactive()
	-- Get existing tags for autocomplete
	local existing_tags = build_tag_cache()
	
	vim.ui.input({
		prompt = "Add tag: ",
		completion = "customlist,v:lua.require('pebble.tag_manager').complete_tags",
	}, function(input)
		if input and input ~= "" then
			M.add_tag_to_current_file(input)
		end
	end)
end

-- Tag completion function
function M.complete_tags(ArgLead, CmdLine, CursorPos)
	local tags = build_tag_cache()
	local matches = {}
	
	for _, tag in ipairs(tags) do
		if tag:lower():find(ArgLead:lower(), 1, true) then
			table.insert(matches, tag)
		end
	end
	
	return matches
end

-- Clear cache (useful for testing or manual refresh)
function M.clear_cache()
	tag_cache = {}
	cache_timestamp = 0
end

return M