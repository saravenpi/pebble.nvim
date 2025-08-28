local M = {}

local function safe_eval(expr, context)
	local env = {
		math = math,
		string = string,
		tostring = tostring,
		tonumber = tonumber,
		type = type,
		pairs = pairs,
		ipairs = ipairs,
		os = { time = os.time, difftime = os.difftime, date = os.date },
		date = function(str)
			if not str then
				return os.time()
			end
			local year, month, day = str:match("(%d+)-(%d+)-(%d+)")
			if year then
				return os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 0, min = 0, sec = 0})
			end
			return os.time()
		end,
		now = function()
			return os.time()
		end,
		format = function(date_val, fmt)
			if type(date_val) == "number" then
				return os.date(fmt or "%Y-%m-%d", date_val)
			end
			return ""
		end,
		link = function(val)
			return "[[" .. tostring(val) .. "]]"
		end,
		list = function(val)
			if type(val) == "string" then
				return {val}
			end
			return val or {}
		end,
		["if"] = function(cond, true_val, false_val)
			if cond then
				return true_val
			else
				return false_val or nil
			end
		end,
		concat = function(...)
			local args = {...}
			return table.concat(args, "")
		end,
		length = function(val)
			if type(val) == "string" then
				return string.len(val)
			elseif type(val) == "table" then
				return #val
			end
			return 0
		end,
	}
	
	for k, v in pairs(context) do
		env[k] = v
	end
	
	local fn_str = "return " .. expr
	local fn, err = load(fn_str, "formula", "t", env)
	
	if not fn then
		return nil, err
	end
	
	local success, result = pcall(fn)
	if not success then
		return nil, result
	end
	
	return result, nil
end

local function add_date_string(date_val, modifier)
	if type(date_val) ~= "number" then
		return date_val
	end
	
	local amount, unit = modifier:match("^(%d+)([YMDhms])$")
	if not amount or not unit then
		return date_val
	end
	
	amount = tonumber(amount)
	local t = os.date("*t", date_val)
	
	if unit == "Y" then
		t.year = t.year + amount
	elseif unit == "M" then
		t.month = t.month + amount
	elseif unit == "D" then
		t.day = t.day + amount
	elseif unit == "h" then
		t.hour = t.hour + amount
	elseif unit == "m" then
		t.min = t.min + amount
	elseif unit == "s" then
		t.sec = t.sec + amount
	end
	
	return os.time(t)
end

function M.evaluate_formulas(formulas, file_data)
	if not formulas then return {} end
	
	local results = {}
	local context = {
		file = file_data.file or {},
		note = file_data.note or {},
		formula = results,
	}
	
	context["+"] = add_date_string
	
	for name, formula in pairs(formulas) do
		local expr = formula
		
		expr = expr:gsub('([%w_%.]+)%.toFixed%((%d+)%)', function(var, precision)
			return string.format("string.format('%%.%sf', %s)", precision, var)
		end)
		
		expr = expr:gsub('date%("([^"]+)"%)', function(date_str)
			return string.format("date('%s')", date_str)
		end)
		
		expr = expr:gsub('([%w_%.%(%)]+)%.format%(', 'format(%1, ')
		
		expr = expr:gsub('(%w+) %+ "([^"]+)"', function(var, mod)
			return string.format("(function() local d = %s; if type(d) == 'number' then return d + %d * %s else return d end end)()",
				var,
				tonumber(mod:match("(%d+)")) or 1,
				mod:match("[YMDhms]") == "Y" and "365*24*3600" or
				mod:match("[YMDhms]") == "M" and "30*24*3600" or
				mod:match("[YMDhms]") == "D" and "24*3600" or
				mod:match("[YMDhms]") == "h" and "3600" or
				mod:match("[YMDhms]") == "m" and "60" or "1")
		end)
		
		local result, err = safe_eval(expr, context)
		if result ~= nil then
			results[name] = result
			context.formula[name] = result
		end
	end
	
	return results
end

function M.apply_formulas_to_files(files, formulas)
	for _, file in ipairs(files) do
		local file_data = {
			file = {
				name = vim.fn.fnamemodify(file.path, ":t:r"),
				ext = vim.fn.fnamemodify(file.path, ":e"),
				path = file.path,
				size = file.size or 0,
			},
			note = file.frontmatter or {},
		}
		
		local formula_results = M.evaluate_formulas(formulas, file_data)
		
		for k, v in pairs(formula_results) do
			file["formula." .. k] = v
		end
	end
	
	return files
end

return M