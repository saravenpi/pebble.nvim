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

-- Get all markdown files using ripgrep for speed
local function get_all_notes(root_dir)
	local search = require("pebble.bases.search")
	
	-- Check cache validity
	local now = vim.loop.now()
	if notes_cache.data and (now - cache_timestamp) < CACHE_TTL then
		return notes_cache.data
	end
	
	-- Use ripgrep to find markdown files
	local files = search.find_markdown_files_rg(root_dir)
	
	if not files or #files == 0 then
		notes_cache.data = {}
		cache_timestamp = now
		return {}
	end
	
	local notes = {}
	local processed = 0
	
	-- Process files in batches to avoid blocking
	for _, file_path in ipairs(files) do
		if vim.fn.filereadable(file_path) == 1 then
			local metadata = extract_note_metadata(file_path)
			table.insert(notes, metadata)
			
			processed = processed + 1
			-- Limit cache size for performance
			if processed >= CACHE_MAX_SIZE then
				break
			end
			
			-- Yield control periodically
			if processed % 50 == 0 then
				vim.schedule(function() end)
			end
		end
	end
	
	-- Cache the results
	notes_cache.data = notes
	cache_timestamp = now
	
	return notes
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
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	
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
	local query = line:sub(query_start, query_end)
	
	-- Handle display text (|) - only complete the link part
	local pipe_pos = query:find("|")
	if pipe_pos then
		query = query:sub(1, pipe_pos - 1)
	end
	
	return true, query
end

-- Get root directory for searching notes
function M.get_root_dir()
	-- Try git root first
	local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
	if vim.v.shell_error == 0 and git_root ~= "" then
		return git_root
	end
	
	-- Fallback to current working directory
	return vim.fn.getcwd()
end

--- Check if completion is enabled for current buffer
function M.is_completion_enabled()
	-- Only enable completion in markdown files
	return vim.bo.filetype == "markdown"
end

--- Get statistics about completion cache
function M.get_stats()
	local now = vim.loop.hrtime() / 1000000
	local wiki_cache = completion_cache.wiki_links or { items = {}, timestamp = 0 }
	local files_cache = completion_cache.files or { items = {}, timestamp = 0 }
	
	return {
		cache_valid = is_cache_valid("wiki_links"),
		cache_size = #wiki_cache.items + #files_cache.items,
		cache_age = now - math.max(wiki_cache.timestamp, files_cache.timestamp),
		cache_ttl = CACHE_TTL,
		wiki_links_count = #wiki_cache.items,
		files_count = #files_cache.items,
		text_search_cached_queries = vim.tbl_count(completion_cache) - 3, -- Subtract the 3 main cache types
	}
end

--- Invalidate completion cache
function M.invalidate_cache()
	completion_cache = {
		wiki_links = { items = {}, timestamp = 0 },
		files = { items = {}, timestamp = 0 },
		text_search = { items = {}, timestamp = 0 }
	}
end

return M