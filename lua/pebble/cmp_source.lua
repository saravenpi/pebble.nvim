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
	-- Safe wrapper to prevent crashes
	local function safe_callback(items)
		if callback and type(callback) == "function" then
			pcall(callback, { items = items or {}, isIncomplete = false })
		end
	end
	
	-- Early safety checks
	if not params or not params.context then
		safe_callback({})
		return
	end
	
	local context = params.context
	local line = context.cursor_line or ""
	local col = context.cursor.col or 0
	
	-- Simple, safe pattern matching without external dependencies
	local before_cursor = line:sub(1, col)
	
	-- Check for wiki link pattern [[
	if before_cursor:match("%[%[[^%]]*$") then
		-- Simple static wiki link completion (safe)
		safe_callback({
			{
				label = "example-note",
				kind = require("cmp").lsp.CompletionItemKind.File,
				insertText = "example-note",
				detail = "Wiki Link",
				documentation = "Example wiki link completion"
			}
		})
		return
	end
	
	-- Check for tag pattern #
	if before_cursor:match("#[%w_/-]*$") then
		-- Simple static tag completion (safe)
		safe_callback({
			{
				label = "example",
				kind = require("cmp").lsp.CompletionItemKind.Keyword,
				insertText = "example",
				detail = "Tag",
				documentation = "Example tag"
			},
			{
				label = "test", 
				kind = require("cmp").lsp.CompletionItemKind.Keyword,
				insertText = "test",
				detail = "Tag",
				documentation = "Test tag"
			}
		})
		return
	end
	
	-- No completion context found
	safe_callback({})
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