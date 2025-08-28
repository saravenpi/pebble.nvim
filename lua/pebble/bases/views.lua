local M = {}

local base_view_buf = nil
local base_view_win = nil
local current_view_data = nil
local current_selection = 1

local function create_buffer()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
	vim.api.nvim_buf_set_option(buf, 'swapfile', false)
	vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
	vim.api.nvim_buf_set_option(buf, 'filetype', 'pebble-base')
	vim.api.nvim_buf_set_option(buf, 'modifiable', false)
	return buf
end

local function format_value(value, max_width)
	if value == nil then
		return ""
	elseif type(value) == "table" then
		-- Safety check for tables - avoid infinite recursion
		local ok, str = pcall(function()
			if #value > 50 then
				-- Too many items, truncate
				local limited = {}
				for i = 1, 50 do
					table.insert(limited, tostring(value[i] or ""))
				end
				return table.concat(limited, ", ") .. "..."
			else
				return table.concat(value, ", ")
			end
		end)
		if not ok then
			return "[complex table]"
		end
		if #str > max_width then
			return str:sub(1, max_width - 3) .. "..."
		end
		return str
	else
		local str = tostring(value)
		if #str > max_width then
			return str:sub(1, max_width - 3) .. "..."
		end
		return str
	end
end

local function get_column_widths(files, columns, display_config, max_width)
	local widths = {}
	local total_width = 0
	
	for _, col in ipairs(columns) do
		local display_name = col
		if display_config and display_config[col] then
			if type(display_config[col]) == "table" and display_config[col].displayName then
				display_name = display_config[col].displayName
			elseif type(display_config[col]) == "string" then
				display_name = display_config[col]
			end
		end
		
		local width = #display_name
		for _, file in ipairs(files) do
			-- Safely get value only if file is a table
			if type(file) == "table" then
				local val = format_value(file[col], 50)
				width = math.max(width, #val)
			end
		end
		width = math.min(width, max_width)
		widths[col] = width
		total_width = total_width + width + 3
	end
	
	local available_width = vim.o.columns - 6
	if total_width > available_width then
		local scale = available_width / total_width
		for col, width in pairs(widths) do
			widths[col] = math.max(8, math.floor(width * scale))
		end
	end
	
	return widths
end

local function render_table_view(files, view_config, display_config)
	local lines = {}
	local highlights = {}
	
	if #files == 0 then
		table.insert(lines, "")
		table.insert(lines, "  No items found")
		table.insert(lines, "")
		return lines, highlights
	end
	
	local columns = {}
	if view_config.columns then
		columns = view_config.columns
	else
		local seen = {}
		local priority_cols = {"name", "file.name", "title", "status"}
		
		for _, col in ipairs(priority_cols) do
			for _, file in ipairs(files) do
				if file[col] ~= nil and not seen[col] then
					seen[col] = true
					table.insert(columns, col)
					break
				end
			end
		end
		
		-- Safety limit: only process first 100 files and max 20 columns
		local file_limit = math.min(#files, 100)
		for i = 1, file_limit do
			local file = files[i]
			-- Ensure file is a valid table before iterating
			if type(file) == "table" then
				for key, _ in pairs(file) do
					if not seen[key] and not key:match("^_") and not key:match("^path$") then
						seen[key] = true
						table.insert(columns, key)
						-- Safety limit: max 20 columns
						if #columns >= 20 then
							break
						end
					end
				end
			end
			if #columns >= 20 then
				break
			end
		end
	end
	
	local widths = get_column_widths(files, columns, display_config, 40)
	
	local header_line = "│ "
	for _, col in ipairs(columns) do
		local display_name = col
		if display_config and display_config[col] then
			if type(display_config[col]) == "table" and display_config[col].displayName then
				display_name = display_config[col].displayName
			elseif type(display_config[col]) == "string" then
				display_name = display_config[col]
			end
		end
		header_line = header_line .. string.format("%-" .. widths[col] .. "s │ ", display_name)
	end
	table.insert(lines, header_line)
	
	local separator_line = "├─"
	for _, col in ipairs(columns) do
		separator_line = separator_line .. string.rep("─", widths[col]) .. "─┼─"
	end
	separator_line = separator_line:sub(1, -3) .. "┤"
	table.insert(lines, separator_line)
	
	local limit = math.min(view_config.limit or 100, 500) -- Hard limit of 500 files
	local count = 0
	for i, file in ipairs(files) do
		if count >= limit then break end
		
		-- Skip files that aren't valid tables
		if type(file) ~= "table" then
			goto continue
		end
		
		local line = "│ "
		for _, col in ipairs(columns) do
			local value = format_value(file[col], widths[col])
			line = line .. string.format("%-" .. widths[col] .. "s │ ", value)
		end
		
		table.insert(lines, line)
		
		if i == current_selection then
			table.insert(highlights, {
				line = #lines - 1,
				col_start = 0,
				col_end = -1,
				hl_group = "PebbleBaseSelection"
			})
		end
		
		count = count + 1
		
		::continue::
	end
	
	local footer_line = "└─"
	for _, col in ipairs(columns) do
		footer_line = footer_line .. string.rep("─", widths[col]) .. "─┴─"
	end
	footer_line = footer_line:sub(1, -3) .. "┘"
	table.insert(lines, footer_line)
	
	table.insert(lines, "")
	table.insert(lines, string.format(" %d items • j/k or ↑↓: navigate • Enter: open • q/Esc: quit • r: refresh", #files))
	
	return lines, highlights
end

function M.render_view(files, view_config, display_config)
	view_config = view_config or {}
	local view_type = view_config.type or "table"
	
	if view_type == "table" then
		return render_table_view(files, view_config, display_config)
	else
		return {"View type '" .. view_type .. "' not yet implemented"}, {}
	end
end

function M.open_base_view(base_data, files)
	-- Close existing view if open
	if base_view_win and vim.api.nvim_win_is_valid(base_view_win) then
		vim.api.nvim_win_close(base_view_win, true)
		base_view_win = nil
		base_view_buf = nil
	end
	
	-- Validate inputs
	if not base_data then
		vim.notify("No base data provided", vim.log.levels.ERROR)
		return
	end
	
	files = files or {}
	
	-- Create buffer
	local ok, buf = pcall(create_buffer)
	if not ok then
		vim.notify("Failed to create buffer: " .. buf, vim.log.levels.ERROR)
		return
	end
	base_view_buf = buf
	
	-- Calculate window dimensions
	local width = math.max(60, math.floor(vim.o.columns * 0.8))
	local height = math.max(20, math.floor(vim.o.lines * 0.8))
	local row = math.max(0, math.floor((vim.o.lines - height) / 2))
	local col = math.max(0, math.floor((vim.o.columns - width) / 2))
	
	-- Create floating window
	local ok_win, win = pcall(vim.api.nvim_open_win, base_view_buf, true, {
		relative = 'editor',
		width = width,
		height = height,
		row = row,
		col = col,
		style = 'minimal',
		border = 'rounded',
		title = ' Base View ',
		title_pos = 'center',
	})
	
	if not ok_win then
		vim.notify("Failed to create window: " .. win, vim.log.levels.ERROR)
		return
	end
	base_view_win = win
	
	local view_config = base_data.views and base_data.views[1] or {}
	local display_config = base_data.display or base_data.properties
	
	-- Render view with error protection
	local lines, highlights = {}, {}
	local ok, result_lines, result_highlights = pcall(M.render_view, files, view_config, display_config)
	
	if ok then
		lines = result_lines or {}
		highlights = result_highlights or {}
	else
		lines = {"", "Error rendering base view:", tostring(result_lines), ""}
		highlights = {}
		vim.notify("Error rendering base view: " .. tostring(result_lines), vim.log.levels.ERROR)
	end
	
	vim.api.nvim_buf_set_option(base_view_buf, 'modifiable', true)
	vim.api.nvim_buf_set_lines(base_view_buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(base_view_buf, 'modifiable', false)
	
	vim.api.nvim_create_namespace("pebble_base_highlights")
	local ns = vim.api.nvim_create_namespace("pebble_base_highlights")
	
	vim.api.nvim_set_hl(0, "PebbleBaseSelection", { bg = "#4a4a4a", bold = true })
	vim.api.nvim_set_hl(0, "PebbleBaseHeader", { fg = "#7aa2f7", bold = true })
	vim.api.nvim_set_hl(0, "PebbleBaseBorder", { fg = "#565f89" })
	
	for _, hl in ipairs(highlights) do
		vim.api.nvim_buf_add_highlight(base_view_buf, ns, hl.hl_group, hl.line, hl.col_start, hl.col_end)
	end
	
	current_view_data = files
	current_selection = 1
	
	local function move_selection(delta)
		if #files == 0 then return end
		current_selection = math.max(1, math.min(#files, current_selection + delta))
		local lines, highlights = M.render_view(files, view_config, display_config)
		vim.api.nvim_buf_set_option(base_view_buf, 'modifiable', true)
		vim.api.nvim_buf_set_lines(base_view_buf, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(base_view_buf, 'modifiable', false)
		
		vim.api.nvim_buf_clear_namespace(base_view_buf, ns, 0, -1)
		for _, hl in ipairs(highlights) do
			vim.api.nvim_buf_add_highlight(base_view_buf, ns, hl.hl_group, hl.line, hl.col_start, hl.col_end)
		end
		
		-- Ensure selection is visible
		local win_height = vim.api.nvim_win_get_height(base_view_win)
		local cursor_line = current_selection + 2 -- Account for header and separator
		if cursor_line > win_height - 3 then
			vim.api.nvim_win_set_cursor(base_view_win, {cursor_line, 0})
		end
	end
	
	local function open_selected()
		if current_view_data and current_view_data[current_selection] then
			local file = current_view_data[current_selection]
			if file.path and vim.fn.filereadable(file.path) == 1 then
				vim.api.nvim_win_close(base_view_win, true)
				vim.cmd('edit ' .. vim.fn.fnameescape(file.path))
			end
		end
	end
	
	vim.api.nvim_buf_set_keymap(base_view_buf, 'n', 'j', '', {
		callback = function() move_selection(1) end,
		noremap = true,
		silent = true
	})
	
	vim.api.nvim_buf_set_keymap(base_view_buf, 'n', 'k', '', {
		callback = function() move_selection(-1) end,
		noremap = true,
		silent = true
	})
	
	vim.api.nvim_buf_set_keymap(base_view_buf, 'n', '<Down>', '', {
		callback = function() move_selection(1) end,
		noremap = true,
		silent = true
	})
	
	vim.api.nvim_buf_set_keymap(base_view_buf, 'n', '<Up>', '', {
		callback = function() move_selection(-1) end,
		noremap = true,
		silent = true
	})
	
	vim.api.nvim_buf_set_keymap(base_view_buf, 'n', '<CR>', '', {
		callback = open_selected,
		noremap = true,
		silent = true
	})
	
	vim.api.nvim_buf_set_keymap(base_view_buf, 'n', 'q', ':q<CR>', {
		noremap = true,
		silent = true
	})
	
	vim.api.nvim_buf_set_keymap(base_view_buf, 'n', '<Esc>', ':q<CR>', {
		noremap = true,
		silent = true
	})
	
	vim.api.nvim_buf_set_keymap(base_view_buf, 'n', 'r', '', {
		callback = function()
			local cache = require("pebble.bases.cache")
			local filters = require("pebble.bases.filters")
			cache.clear_cache()
			filters.clear_content_cache()
			vim.notify("Base cache refreshed", vim.log.levels.INFO)
			vim.api.nvim_win_close(base_view_win, true)
		end,
		noremap = true,
		silent = true
	})
	
	vim.api.nvim_buf_set_keymap(base_view_buf, 'n', 'G', '', {
		callback = function() 
			current_selection = #files
			move_selection(0)
		end,
		noremap = true,
		silent = true
	})
	
	vim.api.nvim_buf_set_keymap(base_view_buf, 'n', 'gg', '', {
		callback = function() 
			current_selection = 1
			move_selection(0)
		end,
		noremap = true,
		silent = true
	})
end

function M.close_base_view()
	if base_view_win and vim.api.nvim_win_is_valid(base_view_win) then
		vim.api.nvim_win_close(base_view_win, true)
	end
	base_view_buf = nil
	base_view_win = nil
	current_view_data = nil
end

return M