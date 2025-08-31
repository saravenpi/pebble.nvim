local M = {}

local completion = require("pebble.completion")

-- nvim-cmp source implementation
local source = {}

--- Check if nvim-cmp is available
function M.is_available()
	local ok, cmp = pcall(require, "cmp")
	return ok and cmp ~= nil
end

--- Register the pebble completion source with nvim-cmp
function M.register(opts)
	opts = opts or {}
	
	if not M.is_available() then
		return false
	end

	local cmp = require("cmp")
	
	-- Configure the source
	source.opts = vim.tbl_deep_extend("force", {
		name = "pebble",
		priority = opts.priority or 100,
		max_item_count = opts.max_item_count or 50,
		trigger_characters = opts.trigger_characters or { "[", "(" },
		keyword_pattern = opts.keyword_pattern or [[\k\+]],
		keyword_length = opts.keyword_length or 0,
	}, opts)

	-- Register the source
	cmp.register_source("pebble", source)
	
	return true
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
	return completion.is_completion_enabled()
end

--- nvim-cmp source: complete function
function source:complete(request, callback)
	-- Only complete in markdown files
	if not completion.is_completion_enabled() then
		callback({ items = {}, isIncomplete = false })
		return
	end

	-- Get line and column info
	local line = request.context.cursor_line
	local col = request.context.cursor.col
	
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
	local is_wiki, _ = completion.is_wiki_link_context()
	local is_markdown, _ = completion.is_markdown_link_context()
	
	if is_wiki or is_markdown then
		should_complete = true
	end
	
	-- If no completion context, return empty
	if not should_complete then
		callback({ items = {}, isIncomplete = false })
		return
	end
	
	-- Get completions based on context
	local items = completion.get_completions_for_context(line, col)
	
	-- Limit results to max_item_count
	if #items > self.opts.max_item_count then
		local limited_items = {}
		for i = 1, self.opts.max_item_count do
			table.insert(limited_items, items[i])
		end
		items = limited_items
	end

	-- Convert to nvim-cmp format
	local cmp_items = {}
	for _, item in ipairs(items) do
		local cmp_item = {
			label = item.label,
			kind = item.kind,
			detail = item.detail,
			documentation = item.documentation,
			insertText = item.insertText,
			filterText = item.filterText,
			sortText = item.sortText,
			textEdit = item.textEdit,
			data = item.data,
		}
		
		-- Add source-specific data
		cmp_item.data = cmp_item.data or {}
		cmp_item.data.source = "pebble"
		
		table.insert(cmp_items, cmp_item)
	end

	callback({
		items = cmp_items,
		isIncomplete = false
	})
end

--- nvim-cmp source: resolve completion item (for additional info)
function source:resolve(completion_item, callback)
	-- Add additional documentation or details if needed
	local data = completion_item.data
	if data and data.type then
		if data.type == "wiki_link" then
			completion_item.documentation = {
				kind = "markdown",
				value = string.format(
					"**Wiki Link**: `[[%s]]`\n\n**File**: %s\n\n*Creates an Obsidian-style link that can be followed with `<CR>`*",
					completion_item.label,
					data.relative_path or data.file_path or ""
				)
			}
		elseif data.type == "file_path" then
			completion_item.documentation = {
				kind = "markdown",
				value = string.format(
					"**Markdown Link**: `[text](%s)`\n\n**File**: %s\n\n*Creates a standard markdown link*",
					completion_item.insertText,
					data.relative_path or data.file_path or ""
				)
			}
		elseif data.type == "text_search" then
			completion_item.documentation = {
				kind = "markdown",
				value = string.format(
					"**Text Search Result**\n\n**Found in**: %s (line %d)\n\n**Content**: `%s`\n\n*Text found using ripgrep search*",
					data.relative_path or data.file_path or "",
					data.line_num or 0,
					completion_item.label
				)
			}
		end
	end
	
	callback(completion_item)
end

--- nvim-cmp source: execute completion item (for additional actions)
function source:execute(completion_item, callback)
	-- Could add actions like navigating to the file after completion
	callback(completion_item)
end

return M