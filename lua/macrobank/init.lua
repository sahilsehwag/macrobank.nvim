local M = {}

-- Default configuration; override via require('macrobank').setup{ ... }
local DEFAULTS = {
  -- Global store (always read; also the fallback write target)
  store_path_global = vim.fn.stdpath('config') .. '/macrobank_store.json',

  -- Project-local store discovery:
  --  - string: override defaults (single relative path, e.g. '.nvim/macrobank.json')
  --  - list:   merge with defaults below
  project_store_paths = nil, -- {'.macrobank.json', '.nvim/macrobank.json'} or '.macrobank.json'

  default_select_register = 'q',  -- register to load selected macro into
  default_play_register   = 'q',  -- temporary register used to play from bank
  nerd_icons = true,              -- use nerdfont icons in UI labels

  window = {                     -- editor window dimensions
    width  = 0.7,                -- fraction of columns or absolute number
    height = 0.7,                -- fraction of lines   or absolute number
  },

  mappings = {
    open_live   = '<leader>mm',   -- open Live Macro Editor (registers)
    open_bank   = '<leader>mb',   -- open Macro Bank (saved macros)
  },
}

M.config = vim.deepcopy(DEFAULTS)

function M.setup(user)
  if user then M.config = vim.tbl_deep_extend('force', vim.deepcopy(DEFAULTS), user) end

  require('macrobank.store').setup(M.config)
  require('macrobank.ui').setup(M.config)
  require('macrobank.editor').setup(M.config)
  require('macrobank.saved_editor').setup(M.config)

  -- Commands
  vim.api.nvim_create_user_command('MacroBankLive', function() require('macrobank.editor').open() end, {})
  vim.api.nvim_create_user_command('MacroBank',     function() require('macrobank.saved_editor').open() end, {})
  
  vim.api.nvim_create_user_command('MacroBankSelect', function(opts)
    local Store = require('macrobank.store')
    local U = require('macrobank.util')
    local UI = require('macrobank.ui')
    
    if opts.args == '' then
      -- No argument provided, open picker
      local show_all = opts.bang
      UI.select_macro(function(m)
        if not m then return end
        local reg = (M.config.default_select_register) or 'q'
        vim.fn.setreg(reg, m.keys, 'n')
        U.info(('Loaded "%s" → @%s'):format(m.name, reg))
      end, nil, show_all)
      return
    end
    
    -- Argument provided, select by name
    local name = opts.args
    local macro = nil
    local S = require('macrobank.scopes')
    local ctx = S.current_context(function() return Store.get_session_id() end)
    local search_macros = opts.bang and Store.all(ctx) or Store.partition_by_context(ctx)
    for _, m in ipairs(search_macros) do if m.name == name then macro = m; break end end
    if not macro then return U.warn('Macro not found') end
    local reg = (M.config.default_select_register) or 'q'
    vim.fn.setreg(reg, macro.keys, 'n')
    U.info(('Loaded "%s" → @%s'):format(macro.name, reg))
  end, {
    nargs = '?',
    bang = true,
    complete = function(ArgLead, CmdLine, CursorPos)
      local Store = require('macrobank.store')
      local S = require('macrobank.scopes')
      local ctx = S.current_context(function() return Store.get_session_id() end)
      local has_bang = CmdLine:match('^%S+!')
      local macros = has_bang and Store.all(ctx) or Store.partition_by_context(ctx)
      local names = {}
      for _, macro in ipairs(macros) do
        if macro.name and macro.name:match('^' .. vim.pesc(ArgLead)) then
          table.insert(names, macro.name)
        end
      end
      return names
    end
  })
  
  
  vim.api.nvim_create_user_command('MacroBankPlay', function(opts)
    local Store = require('macrobank.store')
    local U = require('macrobank.util')
    local UI = require('macrobank.ui')
    
    if opts.args == '' then
      -- No argument provided, open picker
      local show_all = opts.bang
      UI.select_macro(function(m)
        if not m then return end
        local reg = (M.config.default_play_register) or 'q'
        local prev = vim.fn.getreg(reg); vim.fn.setreg(reg, m.keys, 'n')
        if opts.range > 0 then
          vim.cmd(('%d,%dnormal! @%s'):format(opts.line1, opts.line2, reg))
        else
          vim.cmd(('normal! @%s'):format(reg))
        end
        vim.fn.setreg(reg, prev, 'n')
      end, nil, show_all)
      return
    end
    
    -- Argument provided, play by name
    local name = opts.args
    local macro = nil
    local S = require('macrobank.scopes')
    local ctx = S.current_context(function() return Store.get_session_id() end)
    local search_macros = opts.bang and Store.all(ctx) or Store.partition_by_context(ctx)
    for _, m in ipairs(search_macros) do if m.name == name then macro = m; break end end
    if not macro then return U.warn('Macro not found') end
    local reg = (M.config.default_play_register) or 'q'
    local prev = vim.fn.getreg(reg); vim.fn.setreg(reg, macro.keys, 'n')
    if opts.range > 0 then
      vim.cmd(('%d,%dnormal! @%s'):format(opts.line1, opts.line2, reg))
    else
      vim.cmd(('normal! @%s'):format(reg))
    end
    vim.fn.setreg(reg, prev, 'n')
  end, {
    nargs = '?',
    range = true,
    bang = true,
    complete = function(ArgLead, CmdLine, CursorPos)
      local Store = require('macrobank.store')
      local S = require('macrobank.scopes')
      local ctx = S.current_context(function() return Store.get_session_id() end)
      local has_bang = CmdLine:match('^%S+!')
      local macros = has_bang and Store.all(ctx) or Store.partition_by_context(ctx)
      local names = {}
      for _, macro in ipairs(macros) do
        if macro.name and macro.name:match('^' .. vim.pesc(ArgLead)) then
          table.insert(names, macro.name)
        end
      end
      return names
    end
  })

  -- Sample mappings (optional)
  if M.config.mappings and M.config.mappings.open_live then
    vim.keymap.set('n', M.config.mappings.open_live, require('macrobank.editor').open, { desc = '[Macrobank]: Edit macros' })
  end
  if M.config.mappings and M.config.mappings.open_bank then
    vim.keymap.set('n', M.config.mappings.open_bank, require('macrobank.saved_editor').open, { desc = '[MacroBank] Edit saved macros' })
  end
  
  -- Define highlight groups
  vim.api.nvim_set_hl(0, 'MacroBankGroupHeader', { link = 'Function', default = true })
end

return M
