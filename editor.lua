local U = require('macrobank.util')
local UI = require('macrobank.ui')
local Store = require('macrobank.store')
local S = require('macrobank.scopes')

local E = {}
local cfg = nil

local state = { buf=nil, win=nil, header_lines=7, regs={}, last_run_reg=nil }

function E.setup(config) cfg = config end

local function collect_regs()
  local regs = {}
  for c = string.byte('a'), string.byte('z') do regs[#regs+1] = string.char(c) end
  return regs
end

local function lines_for_view()
  local out = {}
  for _, r in ipairs(state.regs) do
    local raw = vim.fn.getreg(r)
    out[#out+1] = string.format('%s  %s', r, U.readable(raw))
  end
  return out
end

local function header_lines()
  local i = cfg and cfg.nerd_icons
  local ico = function(k, fallback) if not i then return fallback end return ({ Play='', Save='', Select='󰆾', Delete='', Rec='', Prev='' })[k] or fallback end
  return {
    'MacroBank — Live Macro Editor',
    string.format(' %-9s %-16s %-18s %-16s %-14s %-14s', 'Ops:', ico('Play','Play: r/R'), ico('Save','Save: <CR>/S'), ico('Select','Select: L'), ico('Delete','Delete: X'), ico('Rec','Record: K')),
    '  • Edit right side; <CR> saves @reg, S saves all. X clears @reg.',
    '  • E exports (normal/visual) with name+scope; L selects from bank (context-aware).',
    '  • r plays @reg; R repeats last. K toggles record on a chosen register.',
    '  • P preview (dry-run): open scratch diff and run macro there.',
    '—',
  }
end

local function ensure()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.win and vim.api.nvim_win_is_valid(state.win) then return end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype='nofile'; vim.bo[state.buf].bufhidden='wipe'; vim.bo[state.buf].swapfile=false; vim.bo[state.buf].filetype='macrobank'

  local width = math.max(50, math.floor(vim.o.columns*0.65))
  local height= math.max(18, math.floor(vim.o.lines*0.6))
  local row   = math.floor((vim.o.lines-height)/2-1)
  local col   = math.floor((vim.o.columns-width)/2)
  state.win = vim.api.nvim_open_win(state.buf, true, { relative='editor', width=width, height=height, row=row, col=col, style='minimal', border='rounded' })

  local hdr = header_lines()
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, hdr)
  for i=0, state.header_lines-2 do vim.api.nvim_buf_add_highlight(state.buf, -1, (i==0) and 'Title' or 'Comment', i, 0, -1) end
  vim.api.nvim_buf_set_lines(state.buf, state.header_lines, -1, false, lines_for_view())
  vim.bo[state.buf].modifiable = true

  local map = function(mode, lhs, rhs) vim.keymap.set(mode, lhs, rhs, { buffer=state.buf, silent=true, nowait=true }) end

  -- Save one
  map('n', '<CR>', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    if row <= state.header_lines then return end
    local p = U.parse_reg_line(vim.api.nvim_buf_get_lines(state.buf, row-1, row, false)[1]); if not p then return end
    vim.fn.setreg(p.reg, U.to_termcodes(p.text), 'n'); U.info('Saved @'..p.reg)
  end)

  -- Save all
  map('n', 'S', function()
    local lines = vim.api.nvim_buf_get_lines(state.buf, state.header_lines, -1, false)
    for _, line in ipairs(lines) do local p = U.parse_reg_line(line); if p then vim.fn.setreg(p.reg, U.to_termcodes(p.text), 'n') end end
    U.info('Saved all (a–z)')
  end)

  -- Play current
  map('n', 'r', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    if row <= state.header_lines then return end
    local p = U.parse_reg_line(vim.api.nvim_buf_get_lines(state.buf, row-1, row, false)[1]); if not p then return end
    state.last_run_reg = p.reg
    local count = vim.v.count1
    E.close(); vim.schedule(function() vim.cmd(('normal! %d@%s'):format(count, p.reg)) end)
  end)

  -- Repeat last
  map('n', 'R', function()
    if not state.last_run_reg then return U.warn('No macro played yet') end
    local count = vim.v.count1
    E.close(); vim.schedule(function() vim.cmd(('normal! %d@%s'):format(count, state.last_run_reg)) end)
  end)

  -- Clear current register (Delete)
  map('n', 'X', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    if row <= state.header_lines then return end
    local p = U.parse_reg_line(vim.api.nvim_buf_get_lines(state.buf, row-1, row, false)[1]); if not p then return end
    vim.fn.setreg(p.reg, '', 'n')
    vim.api.nvim_buf_set_lines(state.buf, row-1, row, false, { string.format('%s  ', p.reg) })
    U.info('Cleared @'..p.reg)
  end)

  -- Single mapping for Export (normal/visual): E
  local function do_export()
    local mode = vim.fn.mode()
    if mode == 'n' then
      local row = vim.api.nvim_win_get_cursor(state.win)[1]
      if row <= state.header_lines then return end
      local p = U.parse_reg_line(vim.api.nvim_buf_get_lines(state.buf, row-1, row, false)[1]); if not p then return end
      E._export_prompt({ { reg=p.reg, text=p.text } })
    else
      local srow = vim.fn.getpos('v')[2]
      local erow = vim.fn.getpos('.')[2]
      if srow > erow then srow, erow = erow, srow end
      srow = math.max(srow, state.header_lines+1)
      local lines = vim.api.nvim_buf_get_lines(state.buf, srow-1, erow, false)
      local sel = {}
      for _, line in ipairs(lines) do local p = U.parse_reg_line(line); if p then table.insert(sel, { reg=p.reg, text=p.text }) end end
      if #sel > 0 then E._export_prompt(sel) end
    end
  end
  map({ 'n', 'x' }, 'E', do_export)

  -- Selecting (context UI) into current register
  map('n', 'L', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    if row <= state.header_lines then return end
    local p = U.parse_reg_line(vim.api.nvim_buf_get_lines(state.buf, row-1, row, false)[1]); if not p then return end
    require('macrobank.ui').select_macro(function(m)
      if not m then return end
      vim.fn.setreg(p.reg, m.keys, 'n')
      vim.api.nvim_buf_set_lines(state.buf, row-1, row, false, { string.format('%s  %s', p.reg, U.readable(m.keys)) })
      U.info(('Selected "%s" → @%s'):format(m.name, p.reg))
    end)
  end)

  -- Toggle recording on a chosen register
  map('n', 'K', function()
    local rec = vim.fn.reg_recording()
    if rec ~= '' then vim.cmd('normal! q'); U.info('Stopped recording @'..rec); return end
    vim.ui.input({ prompt = 'Record into register (a–z):', default = cfg.default_play_register or 'q' }, function(r)
      if not r or #r ~= 1 or not r:match('[a-z]') then return end
      vim.cmd('normal! q'..r)
      U.info('Recording... press q to stop')
    end)
  end)

  -- Preview (dry-run) in a scratch diff
  map('n', 'P', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    if row <= state.header_lines then return end
    local p = U.parse_reg_line(vim.api.nvim_buf_get_lines(state.buf, row-1, row, false)[1]); if not p then return end
    local count = vim.v.count1
    E.close()
    vim.schedule(function()
      local src_buf = vim.api.nvim_get_current_buf()
      local src_name = vim.api.nvim_buf_get_name(src_buf)
      -- duplicate buffer into scratch
      local tmp = vim.api.nvim_create_buf(true, true)
      local lines = vim.api.nvim_buf_get_lines(src_buf, 0, -1, false)
      vim.api.nvim_buf_set_lines(tmp, 0, -1, false, lines)
      -- open side-by-side diff
      vim.cmd('leftabove vnew')
      local left = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(left, 0, -1, false, lines)
      vim.cmd('diffthis')
      vim.cmd('vnew')
      local right = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(right, 0, -1, false, lines)
      vim.cmd('diffthis')
      -- run macro on right
      vim.api.nvim_set_current_buf(right)
      vim.fn.setreg(p.reg, vim.fn.getreg(p.reg), 'n')
      vim.cmd(('normal! %d@%s'):format(count, p.reg))
      vim.cmd('redraw!')
      U.info('Preview: left = original, right = after macro')
    end)
  end)

  -- Close
  map('n', 'q', E.close)
end

-- Export helpers ---------------------------------------------------------
local function to_entries(sel)
  local out = {}
  for _, item in ipairs(sel) do
    local keys = U.to_termcodes(item.text or '')
    table.insert(out, { name = nil, keys = keys })
  end
  return out
end

function E._export_prompt(sel)
  UI.input_name('macro_' .. (sel[1] and sel[1].reg or 'x'), function(base_name)
    if base_name == '' then return end
    UI.input_scope(function(scope)
      if not scope then return end
      local entries = to_entries(sel)
      local many = #entries > 1
      for i, e in ipairs(entries) do
        e.name = many and (base_name .. '_' .. (sel[i].reg)) or base_name
        e.scope = scope
        local dup = Store.find_by_name_scope(e.name, e.scope)
        if dup then
          UI.resolve_conflict(e.name, e.scope, function(choice)
            if choice == 'Rename (choose a new name)' then
              vim.ui.input({ prompt = 'New name:', default = e.name .. '_1' }, function(n)
                if not n or n == '' then return end
                e.name = n; Store.add_many({ e }); U.info('Saved as '..n)
              end)
            elseif choice == 'Overwrite (replace existing)' then
              Store.update(dup.id, { name = e.name, keys = e.keys, scope = e.scope }); U.info('Overwrote '..e.name)
            elseif choice == 'Duplicate (auto-suffix)' then
              e.name = e.name .. '_' .. string.sub(U.uuid(), 1, 4); Store.add_many({ e }); U.info('Saved duplicate '..e.name)
            else
              U.info('Canceled')
            end
          end)
        else
          Store.add_many({ e }); U.info('Saved '..e.name)
        end
      end
    end)
  end)
end

-- Public API
function E.open()
  state.regs = collect_regs(); ensure()
end

function E.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win=nil
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then vim.api.nvim_buf_delete(state.buf, { force=true }) end
  state.buf=nil
end

return E
