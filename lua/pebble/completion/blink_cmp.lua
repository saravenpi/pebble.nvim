local M = {}

local completion = require("pebble.completion")

-- blink.cmp source implementation
local source = {}

--- Check if blink.cmp is available
function M.is_available()
	local ok, blink = pcall(require, "blink.cmp")
	return ok and blink ~= nil
end

--- Register the pebble completion source with blink.cmp
function M.register(opts)
	opts = opts or {}
	
	if not M.is_available() then
		return false
	end

	local blink = require("blink.cmp")
	
	-- Configure the source
	source.opts = vim.tbl_deep_extend("force", {
		name = "pebble",
		priority = opts.priority or 100,
		max_item_count = opts.max_item_count or 50,
		trigger_characters = opts.trigger_characters or { "[", "(" },
		enabled = function() 
			return completion.is_completion_enabled()
		end,
	}, opts)

	-- Create source instance
	local source_instance = vim.tbl_deep_extend("force", source, {
		opts = source.opts
	})

	-- Register with blink.cmp
	if blink.register_source then
		blink.register_source("pebble", source_instance)
	elseif blink.sources and blink.sources.register then
		blink.sources.register("pebble", source_instance)
	else
		-- Fallback: try to add to config if available
		local config = require("blink.cmp.config")
		if config and config.sources then
			config.sources.pebble = source_instance
		end
	end
	
	return true
end

--- blink.cmp source: enabled function
function source:enabled()
	return completion.is_completion_enabled()
end

--- blink.cmp source: get trigger characters
function source:get_trigger_characters()
	return self.opts.trigger_characters
end

--- blink.cmp source: should show completion
function source:should_show_completion_on_trigger_character(trigger_character, line_before_cursor, triggered_manually)
	-- Only show completion for specific triggers in markdown files
	if not completion.is_completion_enabled() then
		return false
	end
	
	-- Show for [[ (wiki links)
	if trigger_character == "[" and line_before_cursor:match("%[$") then
		return true
	end
	
	-- Show for ]( (markdown links)
	if trigger_character == "(" and line_before_cursor:match("%]$") then
		return true
	end
	
	-- Show if manually triggered
	return triggered_manually
end

--- blink.cmp source: get completions
function source:get_completions(context, callback)
	-- Only complete in markdown files
	if not completion.is_completion_enabled() then
		callback({ items = {}, is_incomplete = false })
		return
	end

	local line = context.line
	local col = context.cursor[2] + 1 -- blink.cmp uses 0-based indexing
	
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

	-- Convert to blink.cmp format
	local blink_items = {}
	for _, item in ipairs(items) do
		local blink_item = {
			label = item.label,
			kind = item.kind,
			detail = item.detail,
			documentation = item.documentation,
			insert_text = item.insertText,
			filter_text = item.filterText,
			sort_text = item.sortText,
			text_edit = item.textEdit,
			data = item.data,
		}
		
		-- Add source-specific data
		blink_item.data = blink_item.data or {}
		blink_item.data.source = "pebble"
		
		-- Convert textEdit format for blink.cmp if needed
		if blink_item.text_edit then
			blink_item.text_edit.range = {
				start = { 
					line = blink_item.text_edit.range.start.line,
					character = blink_item.text_edit.range.start.character 
				},
				["end"] = { 
					line = blink_item.text_edit.range["end"].line,
					character = blink_item.text_edit.range["end"].character 
				}
			}
		end
		
		table.insert(blink_items, blink_item)
	end

	callback({
		items = blink_items,
		is_incomplete = false
	})
end

--- blink.cmp source: resolve completion item
function source:resolve(item, callback)
	-- Add additional documentation or details if needed
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
					item.insert_text,
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
	
	callback(item)
end

--- blink.cmp source: execute completion item
function source:execute(item, callback)
	-- Could add actions like navigating to the file after completion
	callback(item)
end

--- blink.cmp source: get position encoding offset
function source:get_position_encoding_offset(context)
	-- Return UTF-8 offset by default
	return "utf-8"
end

return M