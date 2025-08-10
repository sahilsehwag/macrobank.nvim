local U = require('macrobank.util')
local UI = require('macrobank.ui')
local Store = require('macrobank.store')
local S = require('macrobank.scopes')

local E = {}
local cfg = nil

local state = { buf=nil, win=nil, header_lines=0, regs={}, last_run_reg=nil, header_ns=nil, ctx=nil }

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

local function render_header()
  if not state.header_ns then state.header_ns = vim.api.nvim_create_namespace('macrobank_live_header') end
  local width = state.win and vim.api.nvim_win_get_width(state.win) or vim.o.columns
  local hdr = {
    'MacroBank — Live Macro Editor',
    'Save changes <C-s> • Play <CR> • Delete dd • Load @ • Load All ` • Repeat . • Switch <Tab> • Quit q',
    'Save macro: Global <C-g> • Filetype <C-t> • File <C-f> • Directory <C-d> • CWD <C-c> • Project <C-p>',
    U.hr('', width, '─'),
  }
  state.header_lines = #hdr
  -- Create empty header lines (virtual text only)
  local empty_lines = {}
  for i = 1, #hdr do empty_lines[i] = '' end
  vim.api.nvim_buf_set_lines(state.buf, 0, state.header_lines, false, empty_lines)

  vim.api.nvim_buf_clear_namespace(state.buf, state.header_ns, 0, -1)
  for i, line in ipairs(hdr) do
    vim.api.nvim_buf_set_extmark(state.buf, state.header_ns, i-1, 0, {
      virt_text = { { line, (i==1) and 'Title' or 'Comment' } },
      virt_text_pos = 'overlay',
    })
  end
end

local function ensure()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.win and vim.api.nvim_win_is_valid(state.win) then return end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype='nofile'; vim.bo[state.buf].bufhidden='wipe'; vim.bo[state.buf].swapfile=false; vim.bo[state.buf].filetype='macrobank'

  local w = (cfg and cfg.window and cfg.window.width) or 0.7
  local h = (cfg and cfg.window and cfg.window.height) or 0.7
  local width = math.max(50, (w < 1) and math.floor(vim.o.columns * w) or w)
  local height= math.max(18, (h < 1) and math.floor(vim.o.lines * h) or h)
  local row   = math.floor((vim.o.lines-height)/2-1)
  local col   = math.floor((vim.o.columns-width)/2)
  state.win = vim.api.nvim_open_win(state.buf, true, { relative='editor', width=width, height=height, row=row, col=col, style='minimal', border='rounded' })

  vim.wo[state.win].signcolumn = 'yes'

  render_header()
  vim.api.nvim_buf_set_lines(state.buf, state.header_lines, -1, false, lines_for_view())
  vim.bo[state.buf].modifiable = true

  -- Position cursor on appropriate register
  local target_reg = nil
  if state.last_run_reg and vim.fn.getreg(state.last_run_reg) ~= '' then
    target_reg = state.last_run_reg
  else
    -- Fall back to default register if last register is empty
    target_reg = (cfg and cfg.default_select_register) or 'q'
  end

  for i, r in ipairs(state.regs) do
    if r == target_reg then
      vim.api.nvim_win_set_cursor(state.win, { state.header_lines + i, 0 })
      break
    end
  end

  local map = function(mode, lhs, rhs) vim.keymap.set(mode, lhs, rhs, { buffer=state.buf, silent=true, nowait=true }) end

  -- Save current register
  map('n', '<C-s>', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    local p = U.parse_reg_line(vim.api.nvim_buf_get_lines(state.buf, row-1, row, false)[1]); if not p then return end
    vim.fn.setreg(p.reg, U.to_termcodes(p.text), 'n')
    vim.api.nvim_buf_set_lines(state.buf, row-1, row, false, { string.format('%s  %s', p.reg, U.readable(p.text)) })
    U.info('Saved @'..p.reg)
  end)

  -- Play current register
  map('n', '<CR>', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    local p = U.parse_reg_line(vim.api.nvim_buf_get_lines(state.buf, row-1, row, false)[1]); if not p then return end
    state.last_run_reg = p.reg
    local count = vim.v.count1
    E.close(); vim.schedule(function() vim.cmd(('normal! %d@%s'):format(count, p.reg)) end)
  end)

  -- Repeat last macro
  map('n', '.', function()
    if not state.last_run_reg then return U.warn('No macro played yet') end
    local count = vim.v.count1
    E.close(); vim.schedule(function() vim.cmd(('normal! %d@%s'):format(count, state.last_run_reg)) end)
  end)

  -- Clear current register
  map('n', 'dd', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    local p = U.parse_reg_line(vim.api.nvim_buf_get_lines(state.buf, row-1, row, false)[1]); if not p then return end
    vim.fn.setreg(p.reg, '', 'n')
    vim.api.nvim_buf_set_lines(state.buf, row-1, row, false, { string.format('%s  ', p.reg) })
    U.info('Cleared @'..p.reg)
  end)

  -- Load macro from bank into current register (available only)
  map('n', '@', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    local p = U.parse_reg_line(vim.api.nvim_buf_get_lines(state.buf, row-1, row, false)[1]); if not p then return end
    require('macrobank.ui').select_macro(function(m)
      if not m then return end
      vim.fn.setreg(p.reg, m.keys, 'n')
      vim.api.nvim_buf_set_lines(state.buf, row-1, row, false, { string.format('%s  %s', p.reg, U.readable(m.keys)) })
      U.info(('Loaded "%s" → @%s'):format(m.name, p.reg))
    end, state.ctx, false)
  end)

  -- Load macro from bank into current register (all macros)
  map('n', '`', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    local p = U.parse_reg_line(vim.api.nvim_buf_get_lines(state.buf, row-1, row, false)[1]); if not p then return end
    require('macrobank.ui').select_macro(function(m)
      if not m then return end
      vim.fn.setreg(p.reg, m.keys, 'n')
      vim.api.nvim_buf_set_lines(state.buf, row-1, row, false, { string.format('%s  %s', p.reg, U.readable(m.keys)) })
      U.info(('Loaded "%s" → @%s'):format(m.name, p.reg))
    end, state.ctx, true)
  end)

  local function save_current(scope_type)
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    local p = U.parse_reg_line(vim.api.nvim_buf_get_lines(state.buf, row-1, row, false)[1]); if not p then return end
    local ctx = state.ctx or S.current_context(function() return Store.get_session_id() end)
    local scope = { type = scope_type, value = S.default_value_for(scope_type, ctx) }
    UI.input_name('macro_'..p.reg, function(name)
      if name == '' then return end
      local existing = Store.find_by_name_scope(name, scope, state.ctx)
      local entry = { name=name, keys=U.to_termcodes(p.text), scope=scope }
      if existing then Store.update(existing.id, entry, state.ctx) else Store.add_many({ entry }, state.ctx) end
      U.info(('Saved %s macro %s for %s'):format(scope_type, name, scope.value or ''))
    end, scope)
  end

  map('n', '<C-g>', function() save_current('global') end)
  map('n', '<C-t>', function() save_current('filetype') end)
  map('n', '<C-f>', function() save_current('file') end)
  map('n', '<C-d>', function() save_current('directory') end)
  map('n', '<C-c>', function() save_current('cwd') end)
  map('n', '<C-p>', function() save_current('project') end)

  map('n', '<Tab>', function() E.close(); require('macrobank.saved_editor').open(state.ctx) end)

  -- Close
  map('n', 'q', E.close)
end

-- Public API
function E.open(ctx)
  state.regs = collect_regs()
  state.ctx = ctx or S.current_context(function() return Store.get_session_id() end)
  ensure()
end

function E.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win=nil
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then vim.api.nvim_buf_delete(state.buf, { force=true }) end
  state.buf=nil
end

return E
