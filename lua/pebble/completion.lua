local M = {}

-- Cache for note metadata to avoid repeated file operations
local notes_cache = {}
local cache_timestamp = 0
local CACHE_TTL = 30000 -- 30 seconds
local CACHE_MAX_SIZE = 2000 -- Maximum number of cached notes

-- Fuzzy matching score calculation
local function calculate_fuzzy_score(query, target)
	if not query or not target then return 0 end
	
	local query_lower = query:lower()
	local target_lower = target:lower()
	
	-- Exact match gets highest score
	if query_lower == target_lower then
		return 1000
	end
	
	-- Prefix match gets high score
	if vim.startswith(target_lower, query_lower) then
		return 900 - #target + #query * 10
	end
	
	-- Word boundary matches get medium-high score
	if target_lower:match("%f[%w]" .. vim.pesc(query_lower)) then
		return 700 - #target + #query * 5
	end
	
	-- Check for consecutive character matches (fuzzy matching)
	local score = 0
	local target_idx = 1
	local consecutive_bonus = 0
	local last_match_idx = 0
	
	for i = 1, #query_lower do
		local char = query_lower:sub(i, i)
		local match_idx = target_lower:find(char, target_idx, true)
		
		if match_idx then
			-- Base score for match
			score = score + 10
			
			-- Bonus for consecutive matches
			if match_idx == last_match_idx + 1 then
				consecutive_bonus = consecutive_bonus + 5
				score = score + consecutive_bonus
			else
				consecutive_bonus = 0
			end
			
			-- Penalty for distance
			score = score - (match_idx - target_idx)
			
			target_idx = match_idx + 1
			last_match_idx = match_idx
		else
			-- Character not found, heavily penalize
			return 0
		end
	end
	
	-- Bonus for shorter targets (prefer concise matches)
	score = score + (100 - #target)
	
	-- Bonus for query coverage
	local coverage = #query / #target
	score = score + (coverage * 50)
	
	return math.max(0, score)
end

-- Parse YAML frontmatter to extract title and aliases
local function parse_frontmatter(file_path)
	local ok, file = pcall(io.open, file_path, 'r')
	if not ok or not file then return nil end
	
	local lines = {}
	local line_count = 0
	local ok_read, err = pcall(function()
		for line in file:lines() do
			line_count = line_count + 1
			table.insert(lines, line)
			-- Only read first 20 lines for performance
			if line_count >= 20 then break end
		end
	end)
	
	pcall(file.close, file)
	
	if not ok_read then
		return nil
	end
	
	if #lines == 0 or lines[1] ~= "---" then
		return nil
	end
	
	local frontmatter = {}
	local i = 2
	while i <= #lines do
		local line = lines[i]
		if line == "---" or line == "..." then
			break
		end
		
		-- Parse simple YAML key-value pairs
		local key, value = line:match("^([%w_%-]+):%s*(.*)$")
		if key then
			if value == "" and i + 1 <= #lines and lines[i + 1]:match("^%s*%-") then
				-- Handle arrays
				local array_items = {}
				local j = i + 1
				while j <= #lines and lines[j]:match("^%s*%-") do
					local item = lines[j]:match("^%s*%-%s*(.+)$")
					if item then
						-- Remove quotes
						item = item:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
						table.insert(array_items, item)
					end
					j = j + 1
				end
				frontmatter[key] = array_items
				i = j
			else
				-- Remove quotes
				value = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
				frontmatter[key] = value
				i = i + 1
			end
		else
			i = i + 1
		end
	end
	
	return frontmatter
end

-- Extract note metadata from file
local function extract_note_metadata(file_path)
	local filename = vim.fn.fnamemodify(file_path, ":t:r")
	local relative_path = vim.fn.fnamemodify(file_path, ":.")
	
	-- Try to parse frontmatter for title and aliases
	local frontmatter = parse_frontmatter(file_path)
	local title = filename
	local aliases = {}
	
	if frontmatter then
		if frontmatter.title and type(frontmatter.title) == "string" then
			title = frontmatter.title
		end
		
		if frontmatter.aliases and type(frontmatter.aliases) == "table" then
			aliases = frontmatter.aliases
		elseif frontmatter.alias and type(frontmatter.alias) == "string" then
			aliases = {frontmatter.alias}
		end
	end
	
	return {
		filename = filename,
		title = title,
		aliases = aliases,
		file_path = file_path,
		relative_path = relative_path,
		display_name = title ~= filename and title or filename
	}
end

-- Get all markdown files using optimized search with async support
local function get_all_notes(root_dir)
	-- Wrap in error handling
	local ok, result = pcall(function()
		local search = require("pebble.search")
		
		-- Check cache validity
		local now = vim.loop.now()
		if notes_cache.data and (now - cache_timestamp) < CACHE_TTL then
			return notes_cache.data
		end
		
		-- Use optimized search with multiple fallback strategies
		local files = {}
		
		-- Try ripgrep first (fastest)
		if search.has_ripgrep() then
			files = search.find_markdown_files_sync(root_dir)
		end
		
		-- Fallback 1: vim.fs.find (Neovim 0.8+)
		if (#files == 0 or not files) and vim.fs and vim.fs.find then
			files = vim.fs.find(function(name)
				return name:match("%.md$")
			end, {
				path = root_dir,
				type = "file",
				limit = CACHE_MAX_SIZE,
			})
		end
		
		-- Fallback 2: vim.fn.glob (most compatible)
		if (#files == 0 or not files) then
			local glob_pattern = root_dir .. "/**/*.md"
			local glob_result = vim.fn.glob(glob_pattern, false, true)
			files = glob_result or {}
		end
		
		if not files or #files == 0 then
			-- Cache empty result to avoid repeated expensive searches
			notes_cache.data = {}
			cache_timestamp = now
			return {}
		end
		
		local notes = {}
		local processed = 0
		
		-- Process files with improved batching and error handling
		for _, file_path in ipairs(files) do
			-- Validate file path
			if type(file_path) == "string" and file_path ~= "" and vim.fn.filereadable(file_path) == 1 then
				local ok_extract, metadata = pcall(extract_note_metadata, file_path)
				if ok_extract and metadata then
					table.insert(notes, metadata)
					processed = processed + 1
				end
				
				-- Limit processing for performance
				if processed >= CACHE_MAX_SIZE then
					break
				end
				
				-- Yield control every 25 files (more frequent for responsiveness)
				if processed % 25 == 0 then
					vim.schedule(function() end)
				end
			end
		end
		
		-- Cache the results
		notes_cache.data = notes
		cache_timestamp = now
		
		return notes
	end)
	
	-- Return empty list on error and cache the failure
	if not ok then
		-- Cache empty result to avoid repeated failed attempts
		notes_cache.data = {}
		cache_timestamp = vim.loop.now()
		return {}
	end
	
	return result or {}
end

-- Invalidate cache when files change
function M.invalidate_cache()
	notes_cache = {}
	cache_timestamp = 0
end

-- Get completion items for wiki links
function M.get_wiki_completions(query, root_dir)
	local notes = get_all_notes(root_dir)
	if not notes or #notes == 0 then
		return {}
	end
	
	local completions = {}
	query = query or ""
	
	for _, note in ipairs(notes) do
		-- Calculate scores for filename, title, and aliases
		local filename_score = calculate_fuzzy_score(query, note.filename)
		local title_score = calculate_fuzzy_score(query, note.title)
		local best_alias_score = 0
		
		for _, alias in ipairs(note.aliases) do
			local alias_score = calculate_fuzzy_score(query, alias)
			best_alias_score = math.max(best_alias_score, alias_score)
		end
		
		local best_score = math.max(filename_score, title_score, best_alias_score)
		
		-- Only include items with a reasonable score
		if best_score > 0 then
			-- Determine the best matching text
			local match_text = note.filename
			local match_type = "filename"
			
			if title_score > filename_score and title_score >= best_alias_score then
				match_text = note.title
				match_type = "title"
			elseif best_alias_score > filename_score and best_alias_score > title_score then
				-- Find the best matching alias
				for _, alias in ipairs(note.aliases) do
					if calculate_fuzzy_score(query, alias) == best_alias_score then
						match_text = alias
						match_type = "alias"
						break
					end
				end
			end
			
			table.insert(completions, {
				label = match_text,
				insertText = match_text,
				kind = 18, -- File kind for LSP
				detail = note.relative_path,
				documentation = {
					kind = "markdown",
					value = string.format("**%s**\n\nFile: `%s`\nType: %s", 
						note.display_name, 
						note.relative_path,
						match_type
					)
				},
				sortText = string.format("%04d_%s", 9999 - math.floor(best_score), match_text),
				score = best_score,
				note_metadata = note
			})
		end
	end
	
	-- Sort by score (highest first)
	table.sort(completions, function(a, b)
		return a.score > b.score
	end)
	
	-- Limit results for performance
	local max_results = 50
	if #completions > max_results then
		local limited = {}
		for i = 1, max_results do
			table.insert(limited, completions[i])
		end
		completions = limited
	end
	
	return completions
end

-- Check if we're inside wiki link brackets
function M.is_wiki_link_context()
	local ok, line = pcall(vim.api.nvim_get_current_line)
	if not ok or not line then
		return false, ""
	end
	
	local cursor_ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
	if not cursor_ok or not cursor or not cursor[2] then
		return false, ""
	end
	
	local col = cursor[2]
	
	-- Find the position of [[ before cursor
	local bracket_start = nil
	for i = col, 1, -1 do
		local char_pair = line:sub(i, i + 1)
		if char_pair == "[[" then
			bracket_start = i
			break
		elseif char_pair == "]]" or line:sub(i, i) == "\n" then
			break
		end
	end
	
	if not bracket_start then
		return false, ""
	end
	
	-- Find the position of ]] after cursor (if any)
	local bracket_end = line:find("]]", col + 1)
	
	-- Extract the query text between [[ and current cursor
	local query_start = bracket_start + 2
	local query_end = col
	local query = line:sub(query_start, query_end) or ""
	
	-- Handle display text (|) - only complete the link part
	local pipe_pos = query:find("|")
	if pipe_pos then
		query = query:sub(1, pipe_pos - 1)
	end
	
	return true, query
end

-- Get root directory using centralized utility
function M.get_root_dir()
	local search = require("pebble.search")
	return search.get_root_dir()
end

--- Check if completion is enabled for current buffer
function M.is_completion_enabled()
	-- Only enable completion in markdown files
	return vim.bo.filetype == "markdown"
end

-- Check if we're inside markdown link brackets
function M.is_markdown_link_context()
	local ok, line = pcall(vim.api.nvim_get_current_line)
	if not ok or not line then
		return false, ""
	end
	
	local cursor_ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
	if not cursor_ok or not cursor or not cursor[2] then
		return false, ""
	end
	
	local col = cursor[2]
	
	-- Find the position of ]( before cursor for markdown links
	local paren_start = nil
	for i = col, 1, -1 do
		local char_pair = line:sub(i, i + 1)
		if char_pair == "](" then
			paren_start = i + 1
			break
		elseif char_pair == ")" or line:sub(i, i) == "\n" then
			break
		end
	end
	
	if not paren_start then
		return false, ""
	end
	
	-- Find the position of ) after cursor (if any)
	local paren_end = line:find(")", col + 1)
	
	-- Extract the query text between ]( and current cursor
	local query_start = paren_start + 1
	local query_end = col
	local query = line:sub(query_start, query_end) or ""
	
	return true, query
end

-- Main completion function that determines context and returns appropriate completions
function M.get_completions_for_context(line, col)
	-- Ensure parameters are valid
	if not line or not col then
		return {}
	end
	
	-- Wrap in error handling to prevent crashes
	local ok, result = pcall(function()
		-- Check for wiki link context first ([[)
		local is_wiki, wiki_query = M.is_wiki_link_context()
		if is_wiki then
			local root_dir = M.get_root_dir()
			local completions = M.get_wiki_completions(wiki_query, root_dir)
			
			-- Convert to completion format with textEdit for replacing partial text
			for _, comp in ipairs(completions) do
				-- Find the start of the current query to replace it properly
				local query_start_col = math.max(0, col - #wiki_query)
				comp.textEdit = {
					range = {
						start = { line = 0, character = query_start_col },
						["end"] = { line = 0, character = col }
					},
					newText = comp.insertText or comp.label
				}
				comp.data = comp.data or {}
				comp.data.type = "wiki_link"
			end
			
			return completions
		end
		
		-- Check for markdown link context ]()
		local is_markdown, markdown_query = M.is_markdown_link_context()
		if is_markdown then
			local root_dir = M.get_root_dir()
			local completions = M.get_markdown_link_completions(markdown_query, root_dir)
			
			-- Convert to completion format with textEdit for replacing partial text
			for _, comp in ipairs(completions) do
				-- Find the start of the current query to replace it properly
				local query_start_col = math.max(0, col - #markdown_query)
				comp.textEdit = {
					range = {
						start = { line = 0, character = query_start_col },
						["end"] = { line = 0, character = col }
					},
					newText = comp.insertText or comp.label
				}
				comp.data = comp.data or {}
				comp.data.type = "file_path"
			end
			
			return completions
		end
		
		-- No relevant completion context found
		return {}
	end)
	
	-- If an error occurred, return empty completions
	if not ok then
		return {}
	end
	
	return result or {}
end

-- Get completion items for markdown link paths ]()
function M.get_markdown_link_completions(query, root_dir)
	local notes = get_all_notes(root_dir)
	if not notes or #notes == 0 then
		return {}
	end
	
	local completions = {}
	query = query or ""
	
	for _, note in ipairs(notes) do
		-- For markdown links, we want the relative path
		local relative_path = note.relative_path
		local filename_score = calculate_fuzzy_score(query, relative_path)
		local title_score = calculate_fuzzy_score(query, note.title)
		
		local best_score = math.max(filename_score, title_score)
		
		-- Only include items with a reasonable score
		if best_score > 0 then
			-- Use relative path for markdown links
			local insert_text = relative_path
			
			table.insert(completions, {
				label = note.display_name,
				insertText = insert_text,
				kind = 17, -- File kind for LSP
				detail = relative_path,
				documentation = {
					kind = "markdown",
					value = string.format("**Markdown Link Path**\n\nFile: `%s`\nTitle: %s", 
						relative_path,
						note.title
					)
				},
				sortText = string.format("%04d_%s", 9999 - math.floor(best_score), insert_text),
				score = best_score,
				note_metadata = note
			})
		end
	end
	
	-- Sort by score (highest first)
	table.sort(completions, function(a, b)
		return a.score > b.score
	end)
	
	-- Limit results for performance
	local max_results = 50
	if #completions > max_results then
		local limited = {}
		for i = 1, max_results do
			table.insert(limited, completions[i])
		end
		completions = limited
	end
	
	return completions
end

--- Get statistics about completion cache
function M.get_stats()
	local now = vim.loop.now()
	return {
		cache_valid = notes_cache.data and (now - cache_timestamp) < CACHE_TTL,
		cache_size = notes_cache.data and #notes_cache.data or 0,
		cache_age = now - cache_timestamp,
		cache_ttl = CACHE_TTL,
		cache_max_size = CACHE_MAX_SIZE
	}
end

-- Check if we're inside markdown link parentheses ]()
function M.is_markdown_link_context()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	
	-- Find the position of ]( before cursor
	local bracket_start = nil
	for i = col, 1, -1 do
		local char_pair = line:sub(i, i + 1)
		if char_pair == "](" then
			bracket_start = i
			break
		elseif char_pair == ")" or line:sub(i, i) == "\n" then
			break
		end
	end
	
	if not bracket_start then
		return false, ""
	end
	
	-- Extract the query text between ]( and current cursor
	local query_start = bracket_start + 2
	local query_end = col
	local query = line:sub(query_start, query_end)
	
	return true, query
end

-- Get completion items for markdown links ](path)
function M.get_markdown_link_completions(query, root_dir)
	local notes = get_all_notes(root_dir)
	if not notes or #notes == 0 then
		return {}
	end
	
	local completions = {}
	query = query or ""
	
	for _, note in ipairs(notes) do
		-- For markdown links, we want to complete with relative paths
		local relative_path = note.relative_path
		
		-- Calculate scores for relative path and filename
		local path_score = calculate_fuzzy_score(query, relative_path)
		local filename_score = calculate_fuzzy_score(query, note.filename)
		
		local best_score = math.max(path_score, filename_score)
		
		-- Only include items with a reasonable score
		if best_score > 0 then
			table.insert(completions, {
				label = note.display_name,
				insertText = relative_path,
				kind = 17, -- Reference kind for LSP
				detail = relative_path,
				documentation = {
					kind = "markdown",
					value = string.format("**%s**\n\nPath: `%s`\nType: markdown link", 
						note.display_name, 
						relative_path
					)
				},
				sortText = string.format("%04d_%s", 9999 - math.floor(best_score), relative_path),
				score = best_score,
				note_metadata = note
			})
		end
	end
	
	-- Sort by score (highest first)
	table.sort(completions, function(a, b)
		return a.score > b.score
	end)
	
	-- Limit results for performance
	local max_results = 50
	if #completions > max_results then
		local limited = {}
		for i = 1, max_results do
			table.insert(limited, completions[i])
		end
		completions = limited
	end
	
	return completions
end

-- Get completions for any context (wiki or markdown links)
function M.get_completions_for_context(line, col)
	local completions = {}
	
	-- Check wiki link context first
	local is_wiki, wiki_query = M.is_wiki_link_context()
	if is_wiki then
		local root_dir = M.get_root_dir()
		completions = M.get_wiki_completions(wiki_query, root_dir)
		
		-- Convert to generic completion format
		for _, comp in ipairs(completions) do
			comp.data = comp.data or {}
			comp.data.type = "wiki_link"
			comp.data.note_metadata = comp.note_metadata
		end
		
		return completions
	end
	
	-- Check markdown link context
	local is_markdown, markdown_query = M.is_markdown_link_context()
	if is_markdown then
		local root_dir = M.get_root_dir()
		completions = M.get_markdown_link_completions(markdown_query, root_dir)
		
		-- Convert to generic completion format
		for _, comp in ipairs(completions) do
			comp.data = comp.data or {}
			comp.data.type = "file_path"
			comp.data.note_metadata = comp.note_metadata
		end
		
		return completions
	end
	
	return {}
end

--- Setup completion with configuration options
function M.setup(opts)
	opts = opts or {}
	
	-- Setup tag completion if enabled
	if opts.tags ~= false then
		local tags = require("pebble.completion.tags")
		tags.setup(opts.tags or {})
	end
	
	-- Configuration can be stored here if needed
	-- For now, just ensure the module is initialized
	return true
end

return M