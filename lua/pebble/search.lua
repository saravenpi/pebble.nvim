local M = {}

-- Simple search utilities without bases functionality

--- Check if ripgrep is available
function M.has_ripgrep()
	return vim.fn.executable("rg") == 1
end

--- Get git root directory or current working directory
function M.get_root_dir()
	local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
	if vim.v.shell_error == 0 and git_root then
		return git_root
	end
	return vim.fn.getcwd()
end

--- Find markdown files synchronously using ripgrep or vim.fs.find
function M.find_markdown_files_sync(root_dir)
	root_dir = root_dir or M.get_root_dir()
	
	if M.has_ripgrep() then
		local cmd = {"rg", "--files", "--glob", "*.md", root_dir}
		local files = vim.fn.systemlist(cmd)
		if vim.v.shell_error == 0 then
			return files
		end
	end
	
	-- Fallback to vim.fs.find
	return vim.fs.find(function(name)
		return name:match("%.md$")
	end, {
		path = root_dir,
		type = "file",
		limit = 1000,
		upward = false,
	})
end

--- Find markdown files asynchronously using ripgrep
function M.find_markdown_files_async(root_dir, callback)
	root_dir = root_dir or M.get_root_dir()
	
	if not M.has_ripgrep() then
		-- Fallback to synchronous method
		local files = M.find_markdown_files_sync(root_dir)
		vim.schedule(function()
			callback(files, nil)
		end)
		return
	end
	
	local cmd = {"rg", "--files", "--glob", "*.md", root_dir}
	
	vim.system(cmd, {}, function(result)
		vim.schedule(function()
			if result.code == 0 then
				local files = vim.split(result.stdout, "\n", {plain = true})
				-- Remove empty lines
				files = vim.tbl_filter(function(file) return file ~= "" end, files)
				callback(files, nil)
			else
				-- Fallback to synchronous method
				local files = M.find_markdown_files_sync(root_dir)
				callback(files, nil)
			end
		end)
	end)
end

--- Search in markdown files synchronously
function M.search_in_files(pattern, root_dir, opts)
	opts = opts or {}
	root_dir = root_dir or M.get_root_dir()
	
	if not M.has_ripgrep() then
		return {}, "ripgrep not available"
	end
	
	local cmd = {"rg", "--type", "md"}
	
	if opts.files_with_matches then
		table.insert(cmd, "--files-with-matches")
	end
	
	if opts.max_results then
		table.insert(cmd, "--max-count")
		table.insert(cmd, tostring(opts.max_results))
	end
	
	table.insert(cmd, pattern)
	table.insert(cmd, root_dir)
	
	local files = vim.fn.systemlist(cmd)
	if vim.v.shell_error ~= 0 then
		return {}, "search failed"
	end
	
	return files, nil
end

--- Search in markdown files asynchronously
function M.search_in_files_async(pattern, root_dir, opts, callback)
	opts = opts or {}
	root_dir = root_dir or M.get_root_dir()
	
	if not M.has_ripgrep() then
		vim.schedule(function()
			callback({}, "ripgrep not available")
		end)
		return
	end
	
	local cmd = {"rg", "--type", "md"}
	
	if opts.files_with_matches then
		table.insert(cmd, "--files-with-matches")
	end
	
	if opts.max_results then
		table.insert(cmd, "--max-count")
		table.insert(cmd, tostring(opts.max_results))
	end
	
	table.insert(cmd, pattern)
	table.insert(cmd, root_dir)
	
	vim.system(cmd, {}, function(result)
		vim.schedule(function()
			if result.code == 0 then
				local files = vim.split(result.stdout, "\n", {plain = true})
				-- Remove empty lines
				files = vim.tbl_filter(function(file) return file ~= "" end, files)
				callback(files, nil)
			else
				callback({}, "search failed")
			end
		end)
	end)
end

return M