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
	-- More permissive pattern for wiki links
	return [[\w\+]]
end

function source:get_trigger_characters()
	return { "[", "#" }
end

function source:complete(params, callback)
	local context = params.context
	local line = context.cursor_line
	local col = context.cursor.col
	
	-- Check if we're in a wiki link context first
	local is_wiki_context, wiki_query = completion.is_wiki_link_context()
	
	if is_wiki_context then
		-- Async wiki link completion
		vim.schedule(function()
			local root_dir = completion.get_root_dir()
			local completions = completion.get_wiki_completions(wiki_query, root_dir)
			
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
					data = {
						note_metadata = comp.note_metadata,
						pebble_completion = true,
						completion_type = "wiki_link"
					}
				})
			end
			
			callback({
				items = items,
				isIncomplete = false
			})
		end)
		return
	end
	
	-- Check for tag context
	local before_cursor = line:sub(1, col)
	local tag_pattern = "#([%w_/-]*)" .. "$"
	local tag_match = before_cursor:match(tag_pattern)
	
	if tag_match then
		-- Simple tag completion (fallback if tag completion module isn't working)
		vim.schedule(function()
			local items = {
				{
					label = "productivity",
					kind = require("cmp").lsp.CompletionItemKind.Keyword,
					insertText = "productivity",
					detail = "Tag",
					data = { completion_type = "tag" }
				},
				{
					label = "example",
					kind = require("cmp").lsp.CompletionItemKind.Keyword,
					insertText = "example", 
					detail = "Tag",
					data = { completion_type = "tag" }
				},
				{
					label = "test",
					kind = require("cmp").lsp.CompletionItemKind.Keyword,
					insertText = "test",
					detail = "Tag", 
					data = { completion_type = "tag" }
				}
			}
			
			callback({
				items = items,
				isIncomplete = false
			})
		end)
		return
	end
	
	-- No completion context found
	callback({ items = {}, isIncomplete = false })
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