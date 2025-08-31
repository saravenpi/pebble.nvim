local M = {}

local function format_value(value, max_width)
	if value == nil then
		return ""
	elseif type(value) == "table" then
		local ok, str = pcall(function()
			if #value > 50 then
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

local function check_telescope()
	local ok, telescope = pcall(require, 'telescope')
	if not ok then
		vim.notify("Telescope is required for bases functionality. Please install telescope.nvim", vim.log.levels.ERROR)
		return false, nil
	end
	
	local pickers_ok, pickers = pcall(require, 'telescope.pickers')
	local finders_ok, finders = pcall(require, 'telescope.finders')
	local conf_ok, conf = pcall(require, 'telescope.config')
	local actions_ok, actions = pcall(require, 'telescope.actions')
	local action_state_ok, action_state = pcall(require, 'telescope.actions.state')
	local previewers_ok, previewers = pcall(require, 'telescope.previewers')
	
	if not (pickers_ok and finders_ok and conf_ok and actions_ok and action_state_ok) then
		vim.notify("Essential telescope modules not available. Please ensure telescope.nvim is properly installed", vim.log.levels.ERROR)
		return false, nil
	end
	
	-- Check if config values are available
	if not conf.values then
		vim.notify("Telescope configuration not initialized. Please ensure telescope.setup() has been called", vim.log.levels.ERROR)
		return false, nil
	end
	
	return true, {
		telescope = telescope,
		pickers = pickers,
		finders = finders,
		conf = conf,
		actions = actions,
		action_state = action_state,
		previewers = previewers_ok and previewers or nil
	}
end

local function get_display_columns(files, view_config, display_config)
	local columns = {}
	
	if view_config.columns then
		columns = view_config.columns
	else
		local seen = {}
		local priority_cols = {"name", "file.name", "title", "status"}
		
		-- Add priority columns if they exist in files
		for _, col in ipairs(priority_cols) do
			for i, file in ipairs(files) do
				if i > 10 then break end -- Limit iteration for performance
				if type(file) == "table" and file[col] ~= nil and not seen[col] then
					seen[col] = true
					table.insert(columns, col)
					break
				end
			end
		end
		
		-- Performance: Add other columns (limited to prevent excessive processing)
		local file_limit = math.min(#files, 10)  -- Further reduced for performance
		for i = 1, file_limit do
			local file = files[i]
			if type(file) == "table" then
				local key_count = 0
				for key, _ in pairs(file) do
					key_count = key_count + 1
					if key_count > 20 then break end -- Prevent processing files with too many keys
					
					if not seen[key] and not key:match("^_") and not key:match("^path$") then
						seen[key] = true
						table.insert(columns, key)
						if #columns >= 6 then -- Reduced column limit for better performance
							break
						end
					end
				end
			end
			if #columns >= 6 then
				break
			end
		end
	end
	
	return columns
end

local function create_display_entry(file, columns, display_config)
	if type(file) ~= "table" then
		return "Invalid file entry"
	end
	
	-- Performance: Limit display parts to essential information
	local parts = {}
	local max_parts = 4  -- Limit for performance
	local part_count = 0
	
	for _, col in ipairs(columns) do
		if part_count >= max_parts then break end
		
		local value = file[col]
		local display_name = col
		
		-- Get display name if configured
		if display_config and display_config[col] then
			if type(display_config[col]) == "table" and display_config[col].displayName then
				display_name = display_config[col].displayName
			elseif type(display_config[col]) == "string" then
				display_name = display_config[col]
			end
		end
		
		local formatted_value = format_value(value, 40)  -- Reduced width for performance
		if formatted_value ~= "" then
			table.insert(parts, display_name .. ": " .. formatted_value)
			part_count = part_count + 1
		end
	end
	
	if #parts == 0 then
		-- Fallback display
		return file.name or file.title or file.path or "Unknown item"
	end
	
	return table.concat(parts, " | ")
end

function M.open_base_view(base_data, files)
	-- Check if telescope is available
	local telescope_ok, telescope_modules = check_telescope()
	if not telescope_ok then
		return
	end
	
	-- Validate inputs
	if not base_data then
		vim.notify("No base data provided", vim.log.levels.ERROR)
		return
	end
	
	files = files or {}
	
	-- Improved handling for empty files
	if #files == 0 then
		vim.notify("No items match the base criteria. Try checking your filters or adding markdown files to the directory.", vim.log.levels.WARN)
		-- Still show telescope with empty results instead of returning
		-- This allows users to see the base is working but just has no matches
	end
	
	local view_config = base_data.views and base_data.views[1] or {}
	local display_config = base_data.display or base_data.properties or {}
	
	-- Get columns to display
	local columns = get_display_columns(files, view_config, display_config)
	
	-- Create telescope picker
	local pickers = telescope_modules.pickers
	local finders = telescope_modules.finders
	local conf = telescope_modules.conf
	local actions = telescope_modules.actions
	local action_state = telescope_modules.action_state
	
	-- Limit files to prevent performance issues
	local display_files = {}
	local limit = math.min(view_config.limit or 1000, 2000) -- Increased reasonable limit
	
	-- Handle empty files case
	if #files == 0 then
		-- Create a dummy entry to show the picker with a helpful message
		display_files = {{
			name = "No items found",
			path = "",
			_empty = true
		}}
	else
		for i = 1, math.min(#files, limit) do
			if type(files[i]) == "table" then
				table.insert(display_files, files[i])
			end
		end
	end
	
	-- Enhanced picker configuration
	local picker_opts = {
		prompt_title = "Base: " .. (base_data.name or "View"),
		finder = finders.new_table({
			results = display_files,
			entry_maker = function(file)
				-- Handle empty state
				if file._empty then
					return {
						value = file,
						display = "No items found - check your base filters or add markdown files",
						path = "",
						ordinal = "no items",
					}
				end
				
				local display = create_display_entry(file, columns, display_config)
				return {
					value = file,
					display = display,
					path = file.path,
					ordinal = display,
				}
			end,
		}),
		sorter = conf.values.generic_sorter and conf.values.generic_sorter({}) or conf.values.file_sorter({}),
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				actions.close(prompt_bufnr)
				local selection = action_state.get_selected_entry()
				
				-- Handle empty state
				if selection and selection.value and selection.value._empty then
					vim.notify("No files to open. Try adjusting your base filters or adding markdown files to your directory.", vim.log.levels.INFO)
					return
				end
				
				if selection and selection.value and selection.value.path and selection.value.path ~= "" then
					local path = selection.value.path
					if vim.fn.filereadable(path) == 1 then
						-- Use pcall to safely open file
						local ok, err = pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(path))
						if not ok then
							vim.notify("Error opening file: " .. tostring(err), vim.log.levels.ERROR)
						end
					else
						vim.notify("File not found: " .. path, vim.log.levels.WARN)
					end
				else
					vim.notify("No valid file selected", vim.log.levels.WARN)
				end
			end)
			
			-- Add additional keybindings for enhanced functionality
			if telescope_modules.actions then
				map('i', '<C-d>', function()
					local selection = action_state.get_selected_entry()
					if selection and selection.value and selection.value.path then
						vim.notify("File: " .. selection.value.path, vim.log.levels.INFO)
					end
				end)
			end
			
			return true
		end,
	}
	
	-- Add previewer if available and files exist
	if telescope_modules.previewers and #display_files > 0 and not display_files[1]._empty then
		picker_opts.previewer = telescope_modules.previewers.vim_buffer_cat.new({
			title = "Preview",
		})
	end
	
	local picker = pickers.new({}, picker_opts)
	
	-- Safely start the picker
	local ok, err = pcall(function() picker:find() end)
	if not ok then
		vim.notify("Error opening telescope picker: " .. tostring(err), vim.log.levels.ERROR)
	end
end

-- Keep the render_view function for backward compatibility, but make it simple
function M.render_view(files, view_config, display_config)
	local lines = {}
	local highlights = {}
	
	if #files == 0 then
		table.insert(lines, "No items found")
		return lines, highlights
	end
	
	-- Simple text-based rendering for compatibility
	local columns = get_display_columns(files, view_config or {}, display_config or {})
	
	-- Header
	table.insert(lines, "Items: " .. #files)
	table.insert(lines, string.rep("-", 50))
	
	-- Items (limited)
	local limit = math.min(#files, 20)
	for i = 1, limit do
		local file = files[i]
		if type(file) == "table" then
			local display = create_display_entry(file, columns, display_config)
			table.insert(lines, string.format("%2d. %s", i, display))
		end
	end
	
	if #files > limit then
		table.insert(lines, "... and " .. (#files - limit) .. " more items")
	end
	
	return lines, highlights
end

return M