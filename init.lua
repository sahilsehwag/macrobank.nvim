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
  vim.api.nvim_create_user_command('MacroBankPlay', function(opts)
    local Store = require('macrobank.store')
    local U = require('macrobank.util')
    local name = opts.args
    local macro = nil
    for _, m in ipairs(Store.all()) do if m.name == name then macro = m; break end end
    if not macro then return U.warn('Macro not found') end
    local reg = (M.config.default_play_register) or 'q'
    local prev = vim.fn.getreg(reg); vim.fn.setreg(reg, macro.keys, 'n')
    if opts.range > 0 then
      vim.cmd(('%d,%dnormal! @%s'):format(opts.line1, opts.line2, reg))
    else
      vim.cmd(('normal! @%s'):format(reg))
    end
    vim.fn.setreg(reg, prev, 'n')
  end, { nargs=1, range=true })

  -- Sample mappings (optional)
  if M.config.mappings and M.config.mappings.open_live then
    vim.keymap.set('n', M.config.mappings.open_live, require('macrobank.editor').open, { desc = 'MacroBank: Live Macro Editor' })
  end
  if M.config.mappings and M.config.mappings.open_bank then
    vim.keymap.set('n', M.config.mappings.open_bank, require('macrobank.saved_editor').open, { desc = 'MacroBank: Saved Macro Bank' })
  end
end

return M
