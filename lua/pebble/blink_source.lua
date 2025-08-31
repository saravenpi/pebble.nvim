-- blink.cmp source for pebble wiki links
local completion = require("pebble.completion")

local M = {}

M.name = "pebble_wiki_links"

function M.get_completions(context, callback)
	-- Only activate in markdown files
	if vim.bo.filetype ~= "markdown" then
		callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
		return
	end
	
	-- Check if we're in a wiki link context
	local is_wiki_context, query = completion.is_wiki_link_context()
	
	if not is_wiki_context then
		callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
		return
	end
	
	-- Get completions asynchronously
	vim.schedule(function()
		local root_dir = completion.get_root_dir()
		local completions = completion.get_wiki_completions(query, root_dir)
		
		-- Convert to blink.cmp format
		local items = {}
		for _, comp in ipairs(completions) do
			table.insert(items, {
				label = comp.label,
				kind = "File",
				detail = comp.detail,
				documentation = comp.documentation and comp.documentation.value or nil,
				insertText = comp.insertText,
				sortText = comp.sortText,
				filterText = comp.label,
				-- Add custom data
				data = {
					note_metadata = comp.note_metadata,
					pebble_completion = true
				}
			})
		end
		
		callback({
			is_incomplete_forward = false,
			is_incomplete_backward = false,
			items = items
		})
	end)
end

function M.should_show_completions(context)
	if vim.bo.filetype ~= "markdown" then
		return false
	end
	
	local is_wiki_context, _ = completion.is_wiki_link_context()
	return is_wiki_context
end

function M.get_trigger_characters()
	return { "[" }
end

function M.resolve(item, callback)
	-- Item is already complete, just return it
	callback(item)
end

return M