local M = {}

-- Use utils module to avoid circular dependencies
local utils = require("pebble.completion.utils")

-- nvim-cmp source implementation
local source = {}
local source_name = "pebble"
local registered = false

--- Check if nvim-cmp is available
function M.is_available()
	local ok, cmp = pcall(require, "cmp")
	return ok and cmp ~= nil
end

--- Register the pebble completion source with nvim-cmp
function M.register(opts)
	opts = opts or {}
	
	if not M.is_available() then
		return false, "nvim-cmp not available"
	end

	if registered then
		return true, "already registered"
	end

	local cmp = require("cmp")
	
	-- Configure the source
	source.opts = vim.tbl_deep_extend("force", {
		name = source_name,
		priority = opts.priority or 100,
		max_item_count = opts.max_item_count or 50,
		trigger_characters = opts.trigger_characters or { "[", "(", "#" },
		keyword_pattern = opts.keyword_pattern or [[\k\+]],
		keyword_length = opts.keyword_length or 0,
		debug = opts.debug or false,
	}, opts)

	-- Register the source with error handling
	local success, err = pcall(cmp.register_source, source_name, source)
	if success then
		registered = true
		return true, "registered"
	else
		return false, err or "registration failed"
	end
end

--- nvim-cmp source: get trigger characters
function source:get_trigger_characters()
	return self.opts.trigger_characters
end

--- nvim-cmp source: get keyword pattern
function source:get_keyword_pattern()
	return self.opts.keyword_pattern
end

--- nvim-cmp source: check if available in current context
function source:is_available()
	-- Only available in markdown files
	return vim.bo.filetype == "markdown"
end

--- nvim-cmp source: complete function
function source:complete(request, callback)
	-- Debug: uncomment to log when completion is called
	-- vim.notify("Pebble completion called", vim.log.levels.INFO)
	
	-- Safety wrapper for callback
	local function safe_callback(result)
		if callback and type(callback) == "function" then
			local ok, err = pcall(callback, result)
			if not ok and self.opts.debug then
				vim.notify("Pebble completion callback error: " .. tostring(err), vim.log.levels.ERROR)
			end
		end
	end

	-- Validate request
	if not request or not request.context then
		safe_callback({ items = {}, isIncomplete = false })
		return
	end

	-- Only complete in markdown files
	-- Always enabled for markdown files
	if vim.bo.filetype ~= "markdown" then
		safe_callback({ items = {}, isIncomplete = false })
		return
	end

	-- Get line and column info with safety checks
	local line = request.context.cursor_line or ""
	local col = (request.context.cursor and request.context.cursor.col) or 0
	
	-- Wrap completion logic in pcall for safety
	local ok, result = pcall(function()
		-- Check if we should trigger completion based on context
		local should_complete = false
		
		-- Check for [[ (wiki links)
		if line:sub(math.max(1, col - 1), col) == "[[" then
			should_complete = true
		end
		
		-- Check for ]( (markdown links)
		if line:sub(math.max(1, col - 1), col) == "](" then
			should_complete = true
		end
		
		-- Check if we're inside existing wiki or markdown link contexts
		local is_wiki, _ = utils.is_wiki_link_context()
		local is_markdown, _ = utils.is_markdown_link_context()
		
		if is_wiki or is_markdown then
			should_complete = true
		end
		
		-- If no completion context, return empty
		if not should_complete then
			return { items = {}, isIncomplete = false }
		end
		
		-- Get completions based on context
		local items = {}
		
		-- Check for tag context first  
		local is_tag, tag_query = utils.is_tag_context()
		-- vim.notify("Debug: is_tag=" .. tostring(is_tag) .. ", tag_query='" .. (tag_query or "nil") .. "'")
		if is_tag then
			local root_dir = utils.get_root_dir()
			items = utils.get_tag_completions(tag_query, root_dir)
			-- vim.notify("Tag context detected: '" .. (tag_query or "") .. "', found " .. #items .. " items")
		else
			-- Check for wiki link context
			local is_wiki, wiki_query = utils.is_wiki_link_context()
			-- vim.notify("Debug: is_wiki=" .. tostring(is_wiki) .. ", wiki_query='" .. (wiki_query or "nil") .. "'")
			if is_wiki then
				local root_dir = utils.get_root_dir()
				items = utils.get_wiki_completions(wiki_query, root_dir)
				-- vim.notify("Wiki context detected: '" .. (wiki_query or "") .. "', found " .. #items .. " items")
			else
				-- Check for markdown link context
				local is_markdown, markdown_query = utils.is_markdown_link_context()
				-- vim.notify("Debug: is_markdown=" .. tostring(is_markdown) .. ", markdown_query='" .. (markdown_query or "nil") .. "'")
				if is_markdown then
					local root_dir = utils.get_root_dir()
					items = utils.get_markdown_link_completions(markdown_query, root_dir)
					-- vim.notify("Markdown context detected: '" .. (markdown_query or "") .. "', found " .. #items .. " items")
				end
			end
		end
		
		-- Debug: Log how many items we got from completion functions
		-- vim.notify("Raw completion items found: " .. #items)
		
		-- Limit results to max_item_count
		local max_items = self.opts and self.opts.max_item_count or 50
		if #items > max_items then
			local limited_items = {}
			for i = 1, max_items do
				table.insert(limited_items, items[i])
			end
			items = limited_items
		end

		-- Convert to nvim-cmp format
		local cmp_items = {}
		for _, item in ipairs(items) do
			local cmp_item = {
				label = item.label or "",
				kind = item.kind or 17, -- File kind constant
				detail = item.detail,
				documentation = item.documentation,
				insertText = item.insertText or item.label,
				filterText = item.filterText or item.label,
				sortText = item.sortText,
			}
			
			table.insert(cmp_items, cmp_item)
		end

		-- Debug: Log what we're returning
		local result = {
			items = cmp_items,
			isIncomplete = false
		}
		-- vim.notify("Pebble returning " .. #result.items .. " items to nvim-cmp")
		-- if #result.items > 0 then
		-- 	vim.notify("First item: " .. result.items[1].label .. " (" .. result.items[1].kind .. ")")
		-- end
		
		return result
	end)

	if ok then
		safe_callback(result)
	else
		if self.opts and self.opts.debug then
			vim.notify("Pebble completion error: " .. tostring(result), vim.log.levels.ERROR)
		end
		safe_callback({ items = {}, isIncomplete = false })
	end
end

--- nvim-cmp source: resolve completion item (for additional info)
function source:resolve(completion_item, callback)
	-- Safety wrapper for callback
	local function safe_callback(item)
		if callback and type(callback) == "function" then
			local ok, err = pcall(callback, item)
			if not ok and self.opts and self.opts.debug then
				vim.notify("Pebble resolve callback error: " .. tostring(err), vim.log.levels.ERROR)
			end
		end
	end

	-- Wrap resolution logic in pcall for safety
	local ok, resolved_item = pcall(function()
		local item = vim.deepcopy(completion_item)
		local data = item.data
		
		if data and data.type then
			if data.type == "wiki_link" then
				item.documentation = {
					kind = "markdown",
					value = string.format(
						"**Wiki Link**: `[[%s]]`\n\n**File**: %s\n\n*Creates an Obsidian-style link that can be followed with `<CR>`*",
						item.label,
						data.relative_path or data.file_path or ""
					)
				}
			elseif data.type == "file_path" then
				item.documentation = {
					kind = "markdown",
					value = string.format(
						"**Markdown Link**: `[text](%s)`\n\n**File**: %s\n\n*Creates a standard markdown link*",
						item.insertText or item.label,
						data.relative_path or data.file_path or ""
					)
				}
			elseif data.type == "text_search" then
				item.documentation = {
					kind = "markdown",
					value = string.format(
						"**Text Search Result**\n\n**Found in**: %s (line %d)\n\n**Content**: `%s`\n\n*Text found using ripgrep search*",
						data.relative_path or data.file_path or "",
						data.line_num or 0,
						item.label
					)
				}
			end
		end
		
		return item
	end)

	if ok then
		safe_callback(resolved_item)
	else
		if self.opts and self.opts.debug then
			vim.notify("Pebble resolve error: " .. tostring(resolved_item), vim.log.levels.ERROR)
		end
		safe_callback(completion_item) -- Return original item on error
	end
end

--- nvim-cmp source: execute completion item (for additional actions)
function source:execute(completion_item, callback)
	-- Safety wrapper for callback
	local function safe_callback(item)
		if callback and type(callback) == "function" then
			local ok, err = pcall(callback, item)
			if not ok and self.opts and self.opts.debug then
				vim.notify("Pebble execute callback error: " .. tostring(err), vim.log.levels.ERROR)
			end
		end
	end

	-- Could add actions like navigating to the file after completion
	-- For now, just return the item unchanged
	safe_callback(completion_item)
end

--- Get registration status and info
function M.get_status()
	return {
		registered = registered,
		source_name = source_name,
		available = M.is_available(),
		opts = source.opts
	}
end

--- Unregister source (for cleanup)
function M.unregister()
	if not registered then
		return true, "not registered"
	end
	
	local ok, cmp = pcall(require, "cmp")
	if not ok then
		return false, "nvim-cmp not available"
	end
	
	-- Note: nvim-cmp doesn't have an unregister function, so we just mark as unregistered
	registered = false
	return true, "unregistered"
end

return M