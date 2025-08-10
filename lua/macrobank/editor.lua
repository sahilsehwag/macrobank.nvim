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
    -- Only include the macro content, register char will be virtual text
    out[#out+1] = U.readable(raw)
  end
  return out
end

local function render_register_labels()
  if not state.reg_ns then
    state.reg_ns = vim.api.nvim_create_namespace('macrobank_live_regs')
  end

  vim.api.nvim_buf_clear_namespace(state.buf, state.reg_ns, 0, -1)

  for i, reg in ipairs(state.regs) do
    local row = state.header_lines + i - 1
    vim.api.nvim_buf_set_extmark(state.buf, state.reg_ns, row, 0, {
      virt_text = { { reg .. '  ', 'Identifier' } },
      virt_text_pos = 'inline',
    })
  end
end

-- Get register and text from current cursor position
local function get_current_register_info()
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  local idx = row - state.header_lines
  if idx < 1 or idx > #state.regs then return nil end

  local reg = state.regs[idx]
  local line_content = vim.api.nvim_buf_get_lines(state.buf, row-1, row, false)[1] or ''

  return {
    reg = reg,
    text = line_content
  }
end

local function render_header()
  if not state.header_ns then state.header_ns = vim.api.nvim_create_namespace('macrobank_live_header') end
  local width = state.win and vim.api.nvim_win_get_width(state.win) or vim.o.columns
  local hdr = {
    'MacroBank — Live Macro Editor',
    'Save changes <C-s> • Play <CR> • Delete D • Load @ • Load(All) ` • Switch <Tab> • Quit <Esc>',
    'Save macro: Global <C-g> • Filetype <C-t> • File <C-f> • Directory <C-d> • CWD <C-c> • Project <C-p>',
    'Navigation: Press a-z to jump to that register',
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
  render_register_labels()
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

  local map = function(mode, lhs, rhs, action_name) 
    -- Check for user override first
    local override = cfg and cfg.live_editor_mappings and cfg.live_editor_mappings[action_name]
    local key_to_use = lhs  -- default key
    
    if override ~= nil then
      if override == false then
        return  -- skip mapping entirely
      else
        key_to_use = override  -- use custom key
      end
    end
    
    vim.keymap.set(mode, key_to_use, rhs, { buffer=state.buf, silent=true, nowait=true })
  end

  -- Save current register
  map('n', '<C-s>', function()
    local info = get_current_register_info()
    if not info then return end
    vim.fn.setreg(info.reg, U.to_termcodes(info.text), 'n')
    -- Update the display line with readable version
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    vim.api.nvim_buf_set_lines(state.buf, row-1, row, false, { U.readable(info.text) })
    render_register_labels() -- Re-render virtual text after content change
    U.info('Saved @'..info.reg)
  end, 'save')

  -- Play current register
  map('n', '<CR>', function()
    local info = get_current_register_info()
    if not info then return end
    state.last_run_reg = info.reg
    local count = vim.v.count1
    E.close(); vim.schedule(function() vim.cmd(('normal! %d@%s'):format(count, info.reg)) end)
  end, 'play')

  -- Repeat last macro
  map('n', '.', function()
    if not state.last_run_reg then return U.warn('No macro played yet') end
    local count = vim.v.count1
    E.close(); vim.schedule(function() vim.cmd(('normal! %d@%s'):format(count, state.last_run_reg)) end)
  end, 'repeat')

  -- Clear current register
  map('n', 'D', function()
    local info = get_current_register_info()
    if not info then return end
    vim.fn.setreg(info.reg, '', 'n')

    -- Store current cursor position
    local cursor_pos = vim.api.nvim_win_get_cursor(state.win)
    local row = cursor_pos[1]

    -- Ensure buffer is modifiable
    local old_modifiable = vim.bo[state.buf].modifiable
    vim.bo[state.buf].modifiable = true

    -- Clear the line content
    vim.api.nvim_buf_set_lines(state.buf, row-1, row, false, { '' })

    -- Re-render virtual text after content change
    vim.schedule(function()
      render_register_labels()
      -- Restore cursor position
      if vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_set_cursor(state.win, cursor_pos)
      end
    end)

    -- Restore modifiable state
    vim.bo[state.buf].modifiable = old_modifiable

    U.info('Cleared @'..info.reg)
  end, 'delete')

  -- Load macro from bank into current register (available only)
  map('n', '@', function()
    local info = get_current_register_info()
    if not info then return end
    require('macrobank.ui').select_macro(function(m)
      if not m then return end
      vim.fn.setreg(info.reg, m.keys, 'n')
      local row = vim.api.nvim_win_get_cursor(state.win)[1]
      vim.api.nvim_buf_set_lines(state.buf, row-1, row, false, { U.readable(m.keys) })
      render_register_labels() -- Re-render virtual text after content change
      U.info(('Loaded "%s" → @%s'):format(m.name, info.reg))
    end, state.ctx, false)
  end, 'load')

  -- Load macro from bank into current register (all macros)
  map('n', '`', function()
    local info = get_current_register_info()
    if not info then return end
    require('macrobank.ui').select_macro(function(m)
      if not m then return end
      vim.fn.setreg(info.reg, m.keys, 'n')
      local row = vim.api.nvim_win_get_cursor(state.win)[1]
      vim.api.nvim_buf_set_lines(state.buf, row-1, row, false, { U.readable(m.keys) })
      render_register_labels() -- Re-render virtual text after content change
      U.info(('Loaded "%s" → @%s'):format(m.name, info.reg))
    end, state.ctx, true)
  end, 'load_all')

  local function save_current(scope_type)
    local info = get_current_register_info()
    if not info then return end
    local ctx = state.ctx or S.current_context(function() return Store.get_session_id() end)
    local scope = { type = scope_type, value = S.default_value_for(scope_type, ctx) }
    UI.input_name('macro_'..info.reg, function(name)
      if name == '' then return end
      local existing = Store.find_by_name_scope(name, scope, state.ctx)
      local entry = { name=name, keys=U.to_termcodes(info.text), scope=scope }
      if existing then Store.update(existing.id, entry, state.ctx) else Store.add_many({ entry }, state.ctx) end
      U.info(('Saved %s macro %s for %s'):format(scope_type, name, scope.value or ''))
    end, scope)
  end

  map('n', '<C-g>', function() save_current('global') end, 'save_global')
  map('n', '<C-t>', function() save_current('filetype') end, 'save_filetype')
  map('n', '<C-f>', function() save_current('file') end, 'save_file')
  map('n', '<C-d>', function() save_current('directory') end, 'save_directory')
  map('n', '<C-c>', function() save_current('cwd') end, 'save_cwd')
  map('n', '<C-p>', function() save_current('project') end, 'save_project')

  map('n', '<Tab>', function() E.close(); require('macrobank.bank_editor').open(state.ctx) end, 'switch')

  -- Register navigation (a-z jumps to specific register)
  for c = string.byte('a'), string.byte('z') do
    local reg = string.char(c)
    map('n', reg, function()
      for i, r in ipairs(state.regs) do
        if r == reg then
          vim.api.nvim_win_set_cursor(state.win, { state.header_lines + i, 0 })
          break
        end
      end
    end, 'jump_' .. reg)
  end

  -- Close
  map('n', '<Esc>', E.close, 'close')
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
