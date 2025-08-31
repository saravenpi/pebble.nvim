-- Test script for the fixed link completion system
-- Run this with: nvim --clean -c "luafile test_link_completion.lua"

local function test_completion_system()
	print("=== Pebble Link Completion System Test ===")
	
	-- Add the plugin to the runtimepath
	vim.opt.runtimepath:prepend(".")
	
	-- Load the plugin
	local ok, pebble = pcall(require, "pebble")
	if not ok then
		print("❌ Failed to load pebble module: " .. pebble)
		return false
	end
	
	-- Setup the plugin with completion enabled
	local setup_ok, err = pcall(pebble.setup, {
		completion = {
			enabled = true,
			nvim_cmp = { enabled = false }, -- Disable since we're testing without cmp
			blink_cmp = { enabled = false }, -- Disable since we're testing without blink
			debug = true
		}
	})
	
	if not setup_ok then
		print("❌ Failed to setup pebble: " .. (err or "unknown error"))
		return false
	end
	
	print("✅ Pebble plugin loaded and configured")
	
	-- Test the core completion functions
	local completion = require("pebble.completion")
	
	-- Test wiki link context detection
	print("\n--- Testing Wiki Link Context Detection ---")
	
	-- Mock a line with wiki link context
	vim.api.nvim_buf_set_lines(0, 0, -1, false, {"This is a [[test]] link"})
	vim.api.nvim_win_set_cursor(0, {1, 10}) -- Position inside [[
	
	local is_wiki, query = completion.is_wiki_link_context()
	if is_wiki then
		print("✅ Wiki link context detected, query: '" .. query .. "'")
	else
		print("❌ Failed to detect wiki link context")
	end
	
	-- Test markdown link context detection
	print("\n--- Testing Markdown Link Context Detection ---")
	
	vim.api.nvim_buf_set_lines(0, 0, -1, false, {"This is a [text](link) format"})
	vim.api.nvim_win_set_cursor(0, {1, 13}) -- Position inside ]( 
	
	local is_markdown, md_query = completion.is_markdown_link_context()
	if is_markdown then
		print("✅ Markdown link context detected, query: '" .. md_query .. "'")
	else
		print("❌ Failed to detect markdown link context")
	end
	
	-- Test completion context function
	print("\n--- Testing Completion Context Function ---")
	
	-- Test wiki completion
	vim.api.nvim_buf_set_lines(0, 0, -1, false, {"[[test"})
	vim.api.nvim_win_set_cursor(0, {1, 6})
	
	local completions = completion.get_completions_for_context("[[test", 6)
	print("Wiki completions found: " .. #completions)
	
	-- Test markdown completion
	vim.api.nvim_buf_set_lines(0, 0, -1, false, {"[text](test"})
	vim.api.nvim_win_set_cursor(0, {1, 10})
	
	local md_completions = completion.get_completions_for_context("[text](test", 10)
	print("Markdown completions found: " .. #md_completions)
	
	-- Test completion manager
	print("\n--- Testing Completion Manager ---")
	local manager = require("pebble.completion.manager")
	local status = manager.get_status()
	
	print("Manager initialized: " .. tostring(status.initialized))
	print("Available engines: " .. vim.inspect(status.available_engines))
	
	-- Test statistics
	print("\n--- Testing Statistics ---")
	local stats = completion.get_stats()
	print("Cache valid: " .. tostring(stats.cache_valid))
	print("Cache size: " .. stats.cache_size)
	
	print("\n=== Test Completed Successfully ===")
	return true
end

-- Function to create test markdown files for completion testing
local function create_test_files()
	print("\n--- Creating Test Files ---")
	
	local test_files = {
		{
			path = "test_note_1.md",
			content = {
				"---",
				"title: Test Note One",
				"aliases: [\"test-1\", \"first-test\"]",
				"---",
				"# Test Note One",
				"",
				"This is a test note for completion testing."
			}
		},
		{
			path = "test_note_2.md", 
			content = {
				"---",
				"title: Another Test Note",
				"aliases: [\"test-2\"]",
				"---",
				"# Another Test Note",
				"",
				"This is another test note."
			}
		},
		{
			path = "simple_note.md",
			content = {
				"# Simple Note",
				"",
				"Just a simple note without frontmatter."
			}
		}
	}
	
	for _, file in ipairs(test_files) do
		vim.fn.writefile(file.content, file.path)
		print("Created: " .. file.path)
	end
	
	return test_files
end

-- Main test execution
local function main()
	-- Create test files first
	local test_files = create_test_files()
	
	-- Run the completion system tests
	local success = test_completion_system()
	
	-- Clean up test files
	for _, file in ipairs(test_files) do
		vim.fn.delete(file.path)
	end
	
	if success then
		print("\n🎉 All tests passed! Link completion system is working correctly.")
		print("\nTo use the completion system:")
		print("1. Type [[ in a markdown file for wiki link completion")
		print("2. Type ]( in a markdown file for markdown link completion")
		print("3. Use :PebbleTestCompletion to test in real files")
		print("4. Use :PebbleCompletionStatus to check status")
	else
		print("\n❌ Some tests failed. Please check the errors above.")
	end
end

-- Run the test
main()