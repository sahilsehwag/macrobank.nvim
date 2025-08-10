local U = require("macrobank.util")
local S = require("macrobank.scopes")
local Store = require("macrobank.store")

local UI = require("macrobank.ui")

local B = {}
local cfg = nil

local state = {
	buf = nil,
	win = nil,
	header_lines = 0,
	rows = {},
	id_by_row = {},
	virt_ns = nil,
	header_ns = nil,
	last_run_keys = nil,
	ctx = nil,
}

function B.setup(config)
	cfg = config
end

local function context_for(scope)
	if not scope or not scope.type then
		return ""
	end
	local v = scope.value or ""
	if scope.type == "directory" or scope.type == "file" or scope.type == "cwd" then
		v = vim.fn.fnamemodify(v, ":~")
	end
	return v
end

local function render_header()
	if not state.header_ns then
		state.header_ns = vim.api.nvim_create_namespace("macrobank_bank_header")
	end
	local width = state.win and vim.api.nvim_win_get_width(state.win) or vim.o.columns
	local hdr = {
		"MacroBank — Saved Macro Bank",
		"Save <C-s> • Select @@ • Load @<reg> • Play <CR> • Delete D",
		"History <C-h> • Search / • Repeat . • Switch <Tab> • Close <Esc>",
		"Scope: Global <C-g> • Filetype <C-t> • File <C-f> • Directory <C-d> • CWD <C-c> • Project <C-p>",
		"Export: Keymap M • Lua X",
		U.hr("", width, "─"),
	}
	state.header_lines = #hdr
	-- Create empty header lines (virtual text only)
	local empty_lines = {}
	for i = 1, #hdr do
		empty_lines[i] = ""
	end
	vim.api.nvim_buf_set_lines(state.buf, 0, state.header_lines, false, empty_lines)

	vim.api.nvim_buf_clear_namespace(state.buf, state.header_ns, 0, -1)
	for i, line in ipairs(hdr) do
		vim.api.nvim_buf_set_extmark(state.buf, state.header_ns, i - 1, 0, {
			virt_text = { { line, (i == 1) and "Title" or "Comment" } },
			virt_text_pos = "overlay",
		})
	end
end

local function ensure_ns()
	if not state.virt_ns then
		state.virt_ns = vim.api.nvim_create_namespace("macrobank_bank")
	end
end

local function lines_for_bank()
	local ctx = state.ctx
	local eligible, others = Store.partition_by_context(ctx)
	table.sort(eligible, function(a, b)
		return a.name < b.name
	end)

	local order = { global = 1, filetype = 2, cwd = 3, session = 4, directory = 5, file = 6 }
	local groups = {}
	for _, m in ipairs(others) do
		local s = m.scope or { type = "global" }
		local key = s.type .. "|" .. (s.value or "")
		groups[key] = groups[key] or { scope = s, macros = {} }
		table.insert(groups[key].macros, m)
	end

	local rows, ids, headers, macros = {}, {}, {}, {}

	local function add_group(label, macro_list, add_gap)
		-- Add header for this group
		if #macro_list > 0 then
			local header_idx = #rows + 1
			headers[header_idx] = label
		end

		for _, m in ipairs(macro_list) do
			-- Format: <name> <definition> (icon and context will be virtual text)
			rows[#rows + 1] = string.format("%s  %s", m.name, U.readable(m.keys))
			ids[#ids + 1] = m.id
			macros[#macros + 1] = m
		end
		-- Add gap after group (but not after the last one)
		if #macro_list > 0 and add_gap then
			-- TODO:
			--rows[#rows + 1] = ""
			ids[#ids + 1] = nil
			macros[#macros + 1] = nil
		end
	end

	local ordered = {}
	for _, g in pairs(groups) do
		table.insert(ordered, g)
	end
	table.sort(ordered, function(a, b)
		local oa = order[a.scope.type] or 99
		local ob = order[b.scope.type] or 99
		if oa ~= ob then
			return oa < ob
		end
		local va = a.scope.value or ""
		local vb = b.scope.value or ""
		return va < vb
	end)

	local has_eligible = #eligible > 0
	local has_ordered = #ordered > 0

	if has_eligible then
		add_group("Active macros", eligible, has_ordered)
	end

	for i, g in ipairs(ordered) do
		table.sort(g.macros, function(a, b)
			return a.name < b.name
		end)
		local is_last_group = (i == #ordered)
		add_group(S.label(g.scope, cfg and cfg.nerd_icons), g.macros, not is_last_group)
	end

	return rows, ids, headers, macros
end

local function redraw()
	local rows, ids, headers, macro_list = lines_for_bank()
	state.rows, state.id_by_row = rows, ids
	render_header()
	vim.api.nvim_buf_set_lines(state.buf, state.header_lines, -1, false, rows)

	ensure_ns()
	vim.api.nvim_buf_clear_namespace(state.buf, state.virt_ns, 0, -1)
	local line = state.header_lines
	local width = state.win and vim.api.nvim_win_get_width(state.win) or vim.o.columns
	for i = 1, #ids do
		local id = ids[i]
		local row = line + i
		local header = headers[i]
		if header then
			vim.api.nvim_buf_set_extmark(state.buf, state.virt_ns, row - 1, 0, {
				virt_lines = {
					{{ U.hr("", width, " "), "Comment" }},
					{{ U.hr(header, width, "-"), "MacroBankGroupHeader" }},
				},
				virt_lines_above = true,
			})
		end
		if id then
			local macro = macro_list[i]
			if macro then
				-- Add scope icon at the start as virtual text
				local scope_icon = S.icon_only(macro.scope and macro.scope.type or "global", cfg and cfg.nerd_icons)
				vim.api.nvim_buf_set_extmark(state.buf, state.virt_ns, row - 1, 0, {
					virt_text = { { scope_icon .. " ", "Comment" } },
					virt_text_pos = "inline",
				})

				-- Add context at end of line if it exists
				local ctx = context_for(macro.scope)
				if ctx ~= "" then
					vim.api.nvim_buf_set_extmark(state.buf, state.virt_ns, row - 1, 0, {
						virt_text = { { " " .. ctx, "Comment" } },
						virt_text_pos = "eol",
					})
				end
			end
		end
	end
end

local function ensure()
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.win and vim.api.nvim_win_is_valid(state.win) then
		return
	end
	state.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.buf].buftype = "nofile"
	vim.bo[state.buf].bufhidden = "wipe"
	vim.bo[state.buf].swapfile = false
	vim.bo[state.buf].filetype = "macrobank"

	local w = (cfg and cfg.window and cfg.window.width) or 0.7
	local h = (cfg and cfg.window and cfg.window.height) or 0.7
	local width = math.max(50, (w < 1) and math.floor(vim.o.columns * w) or w)
	local height = math.max(18, (h < 1) and math.floor(vim.o.lines * h) or h)
	local row = math.floor((vim.o.lines - height) / 2 - 1)
	local col = math.floor((vim.o.columns - width) / 2)
	state.win = vim.api.nvim_open_win(
		state.buf,
		true,
		{
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = col,
			style = "minimal",
			border = "rounded",
		}
	)

	vim.wo[state.win].signcolumn = "yes"

	redraw()
	vim.bo[state.buf].modifiable = true
	
	-- Position cursor on first available macro
	local first_macro_row = state.header_lines + 1
	for i = 1, #state.id_by_row do
		if state.id_by_row[i] then
			first_macro_row = state.header_lines + i
			break
		end
	end
	if first_macro_row <= state.header_lines + #state.id_by_row then
		vim.api.nvim_win_set_cursor(state.win, { first_macro_row, 0 })
	end

	local map = function(mode, lhs, rhs)
		vim.keymap.set(mode, lhs, rhs, { buffer = state.buf, silent = true, nowait = true })
	end

	-- Save current macro
	map("n", "<C-s>", function()
		local row = vim.api.nvim_win_get_cursor(state.win)[1]
		local idx = row - state.header_lines
		local id = state.id_by_row[idx]
		if not id then
			return
		end
		local line = vim.api.nvim_buf_get_lines(state.buf, row - 1, row, false)[1]
		local p = U.parse_bank_line(line)
		if not p then
			return
		end
		Store.update(id, { name = p.name, keys = U.to_termcodes(p.text) }, state.ctx)
		redraw()
		U.info('Saved "' .. p.name .. '"')
	end)

	-- Delete current macro
	map("n", "D", function()
		local row = vim.api.nvim_win_get_cursor(state.win)[1]
		local idx = row - state.header_lines
		local id = state.id_by_row[idx]
		if not id then
			return
		end
		Store.delete(id, state.ctx)
		redraw()
		U.info("Deleted macro")
	end)

	-- Play macro
	map("n", "<CR>", function()
		local row = vim.api.nvim_win_get_cursor(state.win)[1]
		local idx = row - state.header_lines
		local id = state.id_by_row[idx]
		if not id then
			return
		end
		local macro = nil
		for _, m in ipairs(Store.all(state.ctx)) do
			if m.id == id then
				macro = m
				break
			end
		end
		if not macro then
			return
		end
		state.last_run_keys = macro.keys
		local reg = (cfg and cfg.default_play_register) or "q"
		local prev = vim.fn.getreg(reg)
		vim.fn.setreg(reg, macro.keys, "n")
		local count = vim.v.count1
		B.close()
		vim.schedule(function()
			vim.cmd(("normal! %d@%s"):format(count, reg))
			vim.fn.setreg(reg, prev, "n")
		end)
	end)

	-- Repeat last played macro
	map("n", ".", function()
		if not state.last_run_keys then
			return U.warn("No macro played yet")
		end
		local reg = (cfg and cfg.default_play_register) or "q"
		local prev = vim.fn.getreg(reg)
		vim.fn.setreg(reg, state.last_run_keys, "n")
		local count = vim.v.count1
		B.close()
		vim.schedule(function()
			vim.cmd(("normal! %d@%s"):format(count, reg))
			vim.fn.setreg(reg, prev, "n")
		end)
	end)

	-- Select macro into default register
	local load_macro_in_default_register = function ()
		local row = vim.api.nvim_win_get_cursor(state.win)[1]
		local idx = row - state.header_lines
		local id = state.id_by_row[idx]
		if not id then
			return
		end
		local macro = nil
		for _, m in ipairs(Store.all(state.ctx)) do
			if m.id == id then
				macro = m
				break
			end
		end
		if not macro then
			return
		end
		local reg = (cfg and cfg.default_select_register) or "q"
		vim.fn.setreg(reg, macro.keys, "n")
		U.info(('Loaded "%s" → @%s'):format(macro.name, reg))
	end

	-- Load macro into chosen register
	map("n", "@", function()
		local row = vim.api.nvim_win_get_cursor(state.win)[1]
		local idx = row - state.header_lines
		local id = state.id_by_row[idx]
		if not id then
			return
		end
		local macro = nil
		for _, m in ipairs(Store.all(state.ctx)) do
			if m.id == id then
				macro = m
				break
			end
		end
		if not macro then
			return
		end

		local reg = vim.fn.getcharstr()
		if not reg or reg == "" then
			return
		end
		if reg == "@" then
			return load_macro_in_default_register()
		end

		vim.fn.setreg(reg, macro.keys, "n")
		U.info(('Loaded "%s" → @%s'):format(macro.name, reg))
	end)

	-- History / rollback
	map("n", "<C-h>", function()
		local row = vim.api.nvim_win_get_cursor(state.win)[1]
		local idx = row - state.header_lines
		local id = state.id_by_row[idx]
		if not id then
			return
		end
		local hist = Store.history(id, state.ctx)
		if #hist == 0 then
			return U.warn("No history")
		end
		local items = {}
		for i = #hist, 1, -1 do
			local h = hist[i]
			local name = h.name or ""
			local keys = U.readable(h.keys or "")
			local datetime = U.format_datetime(h.updated_at)
			table.insert(items, string.format("%s %s [%s]", name, keys, datetime))
		end
		vim.ui.select(items, { prompt = "Rollback to version" }, function(choice)
			if not choice then
				return
			end
			local sel_idx = nil
			for i, it in ipairs(items) do
				if it == choice then
					sel_idx = i
					break
				end
			end
			local h = hist[#hist - sel_idx + 1]
			if h then
				Store.update(id, { keys = h.keys, name = h.name }, state.ctx)
			end
			redraw()
			U.info("Rolled back")
		end)
	end)

	-- Export as Lua snippet(s)
	map("n", "X", function()
		local row = vim.api.nvim_win_get_cursor(state.win)[1]
		if row <= state.header_lines then
			return
		end
		local idx = row - state.header_lines
		local id = state.id_by_row[idx]
		if not id then
			return
		end
		local macro = nil
		for _, m in ipairs(Store.all(state.ctx)) do
			if m.id == id then
				macro = m
				break
			end
		end
		if not macro then
			return
		end
		local lua = string.format(
			[[-- MacroBank snippet
return {
  name = %q,
  scope = %q,
  keys = %q, -- feed with: vim.api.nvim_replace_termcodes(keys, true, true, true)
}]],
			macro.name,
			macro.scope and macro.scope.type or "global",
			macro.keys
		)
		vim.cmd("new")
		local b = vim.api.nvim_get_current_buf()
		vim.bo[b].filetype = "lua"
		vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.split(lua, "\n"))
	end)

	-- Keymap generator
	map("n", "M", function()
		local row = vim.api.nvim_win_get_cursor(state.win)[1]
		if row <= state.header_lines then
			return
		end
		local idx = row - state.header_lines
		local id = state.id_by_row[idx]
		if not id then
			return
		end
		local macro = nil
		for _, m in ipairs(Store.all(state.ctx)) do
			if m.id == id then
				macro = m
				break
			end
		end
		if not macro then
			return
		end
		vim.ui.input({ prompt = "Map key (e.g., <leader>mk):" }, function(lhs)
			if not lhs or lhs == "" then
				return
			end
			vim.ui.select({ "n", "v", "x", "i" }, { prompt = "Mode" }, function(mode)
				if not mode then
					return
				end
				local code = string.format(
					[[-- MacroBank keymap
vim.keymap.set(%q, %q, function()
  local reg = %q
  local prev = vim.fn.getreg(reg)
  vim.fn.setreg(reg, %q, 'n')
  vim.cmd('normal! @'..reg)
  vim.fn.setreg(reg, prev, 'n')
end, { desc = 'Play macro: %s' })]],
					mode,
					lhs,
					(cfg.default_play_register or "q"),
					macro.keys,
					macro.name
				)
				vim.cmd("new")
				local b = vim.api.nvim_get_current_buf()
				vim.bo[b].filetype = "lua"
				vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.split(code, "\n"))
			end)
		end)
	end)

	-- Search (fuzzy)
	map("n", "/", function()
		UI.search_macros(function(m)
			if not m then
				return
			end
			local reg = (cfg and cfg.default_select_register) or "q"
			vim.fn.setreg(reg, m.keys, "n")
			U.info(('Loaded "%s" → @%s'):format(m.name, reg))
		end, state.ctx)
	end)

	map("n", "<Tab>", function()
		B.close()
		require("macrobank.editor").open(state.ctx)
	end)

	-- Change scope mappings (similar to live editor)
	local function change_scope(scope_type)
		local row = vim.api.nvim_win_get_cursor(state.win)[1]
		local idx = row - state.header_lines
		local id = state.id_by_row[idx]
		if not id then
			return
		end
		local macro = nil
		for _, m in ipairs(Store.all(state.ctx)) do
			if m.id == id then
				macro = m
				break
			end
		end
		if not macro then
			return
		end
		local ctx = state.ctx or S.current_context(function()
			return Store.get_session_id()
		end)
		local new_scope = { type = scope_type, value = S.default_value_for(scope_type, ctx) }
		Store.update(id, { scope = new_scope }, state.ctx)
		redraw()
		U.info(('Changed "%s" scope to %s'):format(macro.name, scope_type))
	end

	map("n", "<C-g>", function()
		change_scope("global")
	end)
	map("n", "<C-t>", function()
		change_scope("filetype")
	end)
	map("n", "<C-f>", function()
		change_scope("file")
	end)
	map("n", "<C-d>", function()
		change_scope("directory")
	end)
	map("n", "<C-c>", function()
		change_scope("cwd")
	end)
	map("n", "<C-p>", function()
		change_scope("project")
	end)

	-- Close
	map("n", "<Esc>", B.close)
end

function B.open(ctx)
	state.ctx = ctx or S.current_context(function()
		return Store.get_session_id()
	end)
	ensure()
end

function B.close()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		vim.api.nvim_buf_delete(state.buf, { force = true })
	end
	state.buf = nil
end

return B
