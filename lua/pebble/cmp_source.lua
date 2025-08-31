-- nvim-cmp source for pebble wiki links
local completion = require("pebble.completion")

local source = {}

function source.new()
	return setmetatable({}, { __index = source })
end

function source:is_available()
	-- Only available in markdown files
	return vim.bo.filetype == "markdown"
end

function source:get_debug_name()
	return "pebble_wiki_links"
end

function source:get_keyword_pattern()
	-- Match wiki link content inside [[]]
	return "\\[\\[\\zs[^\\]]*\\ze\\]\\]"
end

function source:get_trigger_characters()
	return { "[" }
end

function source:complete(params, callback)
	local context = params.context
	local line = context.cursor_line
	local col = context.cursor.col
	
	-- Check if we're in a wiki link context
	local is_wiki_context, query = completion.is_wiki_link_context()
	
	if not is_wiki_context then
		callback({ items = {}, isIncomplete = false })
		return
	end
	
	-- Async completion to avoid blocking
	vim.schedule(function()
		-- Get completions
		local root_dir = completion.get_root_dir()
		local completions = completion.get_wiki_completions(query, root_dir)
		
		-- Convert to nvim-cmp format
		local items = {}
		for _, comp in ipairs(completions) do
			table.insert(items, {
				label = comp.label,
				kind = require("cmp").lsp.CompletionItemKind.File,
				detail = comp.detail,
				documentation = comp.documentation,
				insertText = comp.insertText,
				sortText = comp.sortText,
				filterText = comp.label,
				-- Add custom data for potential post-processing
				data = {
					note_metadata = comp.note_metadata,
					pebble_completion = true
				}
			})
		end
		
		callback({
			items = items,
			isIncomplete = false
		})
	end)
end

-- Register the source with nvim-cmp if available
local function register_cmp_source()
	local ok, cmp = pcall(require, "cmp")
	if ok then
		cmp.register_source("pebble_wiki_links", source)
	end
end

-- Auto-register when module is loaded
register_cmp_source()

return source