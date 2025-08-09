local U = require('macrobank.util')
local S = require('macrobank.scopes')
local Store = require('macrobank.store')

local UI = require('macrobank.ui')

local B = {}
local cfg = nil

local state = { buf=nil, win=nil, header_lines=7, rows={}, id_by_row={}, virt_ns=nil }

function B.setup(config) cfg = config end

local function header_lines()
  local i = cfg and cfg.nerd_icons
  local ico = function(k, fallback)
    if not i then return fallback end
    return ({ Play='', Save='', Select='󰆾', Delete='', History='', Map='', Export='󰆐', Search='' })[k] or fallback
  end
  return {
    'MacroBank — Saved Macro Bank',
    string.format(' %-9s %-16s %-18s %-16s %-14s %-12s %-12s %-10s', 'Ops:', ico('Play','Play: r'), ico('Save','Save: <CR>'), ico('Select','Select: L'), ico('Delete','Delete: dd'), ico('History','History: H'), ico('Map','Keymap: M'), ico('Export','Lua: X'), ico('Search','Search: /')),
    '  • Edit: change name or keys (right side); <CR> saves. dd deletes.',
    '  • L: load into default register; r: play directly using temp register.',
    '  • H: view versions; rollback. M: generate keymap. X: export as Lua snippet(s).',
    '  • Groups: context-matching macros appear first; scope labels shown as ghost text.',
    '—',
  }
end

local function ensure_ns()
  if not state.virt_ns then state.virt_ns = vim.api.nvim_create_namespace('macrobank_bank') end
end

local function set_scope_ghost(row, scope)
  ensure_ns()
  vim.api.nvim_buf_set_extmark(state.buf, state.virt_ns, row-1, 0, {
    virt_text = { { S.label(scope, cfg and cfg.nerd_icons), 'Comment' } },
    virt_text_pos = 'eol', hl_mode = 'combine',
  })
end

local function lines_for_bank()
  local eligible, others = Store.partition_by_context()
  table.sort(eligible, function(a,b) return a.name < b.name end)
  table.sort(others,    function(a,b) return a.name < b.name end)

  local rows, ids = {}, {}
  local function push_group(title, list)
    if #rows > 0 then rows[#rows+1] = ''; ids[#ids+1] = nil end
    rows[#rows+1] = title; ids[#ids+1] = '__group__'
    for _, m in ipairs(list) do rows[#rows+1] = string.format('%s  %s', m.name, U.readable(m.keys)); ids[#ids+1] = m.id end
  end
  if #eligible > 0 then push_group('— context macros —', eligible) end
  if #others > 0 then push_group('— other macros —', others) end
  return rows, ids
end

local function redraw()
  local rows, ids = lines_for_bank()
  state.rows, state.id_by_row = rows, ids
  vim.api.nvim_buf_set_lines(state.buf, state.header_lines, -1, false, rows)

  ensure_ns(); vim.api.nvim_buf_clear_namespace(state.buf, state.virt_ns, 0, -1)
  local line = state.header_lines
  local all = Store.all(); local by_id = {}; for _, m in ipairs(all) do by_id[m.id] = m end
  for i, id in ipairs(ids) do if id and id ~= '__group__' then set_scope_ghost(line+i, by_id[id].scope) end end
end

local function ensure()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.win and vim.api.nvim_win_is_valid(state.win) then return end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype='nofile'; vim.bo[state.buf].bufhidden='wipe'; vim.bo[state.buf].swapfile=false; vim.bo[state.buf].filetype='macrobank'

  local width = math.max(60, math.floor(vim.o.columns*0.7))
  local height= math.max(20, math.floor(vim.o.lines*0.7))
  local row   = math.floor((vim.o.lines-height)/2-1)
  local col   = math.floor((vim.o.columns-width)/2)
  state.win = vim.api.nvim_open_win(state.buf, true, { relative='editor', width=width, height=height, row=row, col=col, style='minimal', border='rounded' })

  local hdr = header_lines()
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, hdr)
  for i=0, state.header_lines-2 do vim.api.nvim_buf_add_highlight(state.buf, -1, (i==0) and 'Title' or 'Comment', i, 0, -1) end

  redraw(); vim.bo[state.buf].modifiable = true

  local map = function(mode, lhs, rhs) vim.keymap.set(mode, lhs, rhs, { buffer=state.buf, silent=true, nowait=true }) end

  -- Save current row
  map('n', '<CR>', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    if row <= state.header_lines then return end
    local idx = row - state.header_lines; local id = state.id_by_row[idx]; if not id or id == '__group__' then return end
    local line = vim.api.nvim_buf_get_lines(state.buf, row-1, row, false)[1]
    local p = require('macrobank.util').parse_bank_line(line); if not p then return end
    Store.update(id, { name = p.name, keys = require('macrobank.util').to_termcodes(p.text) })
    redraw(); require('macrobank.util').info('Saved "'..p.name..'"')
  end)

  -- Delete (dd)
  map('n', 'dd', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    if row <= state.header_lines then return end
    local idx = row - state.header_lines; local id = state.id_by_row[idx]; if not id or id == '__group__' then return end
    Store.delete(id); redraw(); require('macrobank.util').info('Deleted macro')
  end)

  -- Select (load into default register)
  map('n', 'L', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    if row <= state.header_lines then return end
    local idx = row - state.header_lines; local id = state.id_by_row[idx]; if not id or id == '__group__' then return end
    local macro = nil; for _, m in ipairs(Store.all()) do if m.id == id then macro = m; break end end
    if not macro then return end
    local reg = (cfg and cfg.default_select_register) or 'q'
    vim.fn.setreg(reg, macro.keys, 'n'); require('macrobank.util').info(('Selected "%s" → @%s'):format(macro.name, reg))
  end)

  -- Play directly (using temp register)
  map('n', 'r', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    if row <= state.header_lines then return end
    local idx = row - state.header_lines; local id = state.id_by_row[idx]; if not id or id == '__group__' then return end
    local macro = nil; for _, m in ipairs(Store.all()) do if m.id == id then macro = m; break end end
    if not macro then return end
    local reg = (cfg and cfg.default_play_register) or 'q'
    local prev = vim.fn.getreg(reg); vim.fn.setreg(reg, macro.keys, 'n')
    local count = vim.v.count1
    B.close(); vim.schedule(function() vim.cmd(('normal! %d@%s'):format(count, reg)); vim.fn.setreg(reg, prev, 'n') end)
  end)

  -- History / rollback
  map('n', 'H', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    if row <= state.header_lines then return end
    local idx = row - state.header_lines; local id = state.id_by_row[idx]; if not id or id == '__group__' then return end
    local hist = Store.history(id)
    if #hist == 0 then return require('macrobank.util').warn('No history') end
    local items = {}
    for i=#hist,1,-1 do local h = hist[i]; table.insert(items, string.format('%s — %s', h.updated_at or '?', U.readable(h.keys or ''))) end
    vim.ui.select(items, { prompt = 'Rollback to version' }, function(choice)
      if not choice then return end
      local sel_idx = nil; for i, it in ipairs(items) do if it == choice then sel_idx = i; break end end
      local h = hist[#hist - sel_idx + 1]
      if h then Store.update(id, { keys = h.keys, name = h.name }) end
      redraw(); require('macrobank.util').info('Rolled back')
    end)
  end)

  -- Export as Lua snippet(s)
  map('n', 'X', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    if row <= state.header_lines then return end
    local idx = row - state.header_lines; local id = state.id_by_row[idx]; if not id or id == '__group__' then return end
    local macro = nil; for _, m in ipairs(Store.all()) do if m.id == id then macro = m; break end end
    if not macro then return end
    local lua = string.format([[-- MacroBank export
return {
  name = %q,
  scope = %q,
  keys = %q, -- feed with: vim.api.nvim_replace_termcodes(keys, true, true, true)
}]], macro.name, macro.scope and macro.scope.type or 'global', macro.keys)
    vim.cmd('new'); local b = vim.api.nvim_get_current_buf(); vim.bo[b].filetype='lua'; vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.split(lua, '\n'))
  end)

  -- Keymap generator
  map('n', 'M', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    if row <= state.header_lines then return end
    local idx = row - state.header_lines; local id = state.id_by_row[idx]; if not id or id == '__group__' then return end
    local macro = nil; for _, m in ipairs(Store.all()) do if m.id == id then macro = m; break end end
    if not macro then return end
    vim.ui.input({ prompt = 'Map key (e.g., <leader>mk):' }, function(lhs)
      if not lhs or lhs == '' then return end
      vim.ui.select({ 'n', 'v', 'x', 'i' }, { prompt = 'Mode' }, function(mode)
        if not mode then return end
        local code = string.format([[-- MacroBank keymap
vim.keymap.set(%q, %q, function()
  local reg = %q
  local prev = vim.fn.getreg(reg)
  vim.fn.setreg(reg, %q, 'n')
  vim.cmd('normal! @'..reg)
  vim.fn.setreg(reg, prev, 'n')
end, { desc = 'Play macro: %s' })]], mode, lhs, (cfg.default_play_register or 'q'), macro.keys, macro.name)
        vim.cmd('new'); local b = vim.api.nvim_get_current_buf(); vim.bo[b].filetype='lua'; vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.split(code, '\n'))
      end)
    end)
  end)

  -- Search (fuzzy)
  map('n', '/', function()
    UI.search_macros(function(m)
      if not m then return end
      local reg = (cfg and cfg.default_select_register) or 'q'
      vim.fn.setreg(reg, m.keys, 'n'); require('macrobank.util').info(('Loaded "%s" → @%s'):format(m.name, reg))
    end)
  end)

  -- Close
  map('n', 'q', B.close)
end

function B.open() ensure() end

function B.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win=nil
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then vim.api.nvim_buf_delete(state.buf, { force=true }) end
  state.buf=nil
end

return B
