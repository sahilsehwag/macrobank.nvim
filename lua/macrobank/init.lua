---@brief [[
---MacroBank is a powerful Neovim plugin for managing, editing, and organizing
---macros with persistent storage across sessions and projects.
---
---Features:
--- • Live Macro Editor for real-time editing with quick navigation
--- • Persistent storage with global and project-local macro files  
--- • Smart selection with fuzzy matching and context awareness
--- • Multiple scope types (global, filetype, file, directory, cwd, project)
--- • Rich UI with Nerd Font icons and clean interface
--- • Comprehensive Lua API for programmatic access
---@brief ]]

---@tag macrobank.nvim

local M = {}

---@class macrobank.Config
---@field store_path_global string Path to global macro store file
---@field project_store_paths string|string[]|nil Project store discovery paths  
---@field default_select_register string Register to load selected macros into
---@field default_play_register string Temporary register for macro playback
---@field nerd_icons boolean Use Nerd Font icons in UI elements
---@field window {width: number, height: number} Editor window dimensions
---@field live_editor_mappings table<string, string|boolean> Live editor mapping overrides
---@field bank_editor_mappings table<string, string|boolean> Bank editor mapping overrides

--- Default configuration
---@type macrobank.Config
local DEFAULTS = {
  -- Global store (always read; also the fallback write target)
  store_path_global = vim.fn.stdpath('config') .. '/macrobank_store.json',

  -- Project-local store discovery:
  --  - string: override defaults (single relative path, e.g. '.nvim/macrobank.json')
  --  - list:   merge with defaults below
  --  - first entry is used for creation when no project store exists yet
  project_store_paths = nil, -- {'.macrobank.json', '.nvim/macrobank.json'} or '.macrobank.json'

  default_select_register = 'q',  -- register to load selected macro into
  default_play_register   = 'q',  -- temporary register used to play from bank
  nerd_icons = true,              -- use nerdfont icons in UI labels

  window = {                     -- editor window dimensions
    width  = 0.7,                -- fraction of columns or absolute number
    height = 0.7,                -- fraction of lines   or absolute number
  },

  

  -- Editor buffer mappings override (optional)
  live_editor_mappings = {},      -- override live editor buffer mappings: {action_name = 'keymap' | false}
  bank_editor_mappings = {},      -- override bank editor buffer mappings: {action_name = 'keymap' | false}
}

M.config = vim.deepcopy(DEFAULTS)

--- Setup MacroBank with user configuration
---@param user macrobank.Config|nil User configuration to merge with defaults
function M.setup(user)
  if user then M.config = vim.tbl_deep_extend('force', vim.deepcopy(DEFAULTS), user) end

  require('macrobank.store').setup(M.config)
  require('macrobank.ui').setup(M.config)
  require('macrobank.editor').setup(M.config)
  require('macrobank.bank_editor').setup(M.config)

  -- Commands
  vim.api.nvim_create_user_command('MacroBankLive', function() require('macrobank.editor').open() end, {})
  vim.api.nvim_create_user_command('MacroBank',     function() require('macrobank.bank_editor').open() end, {})

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

  

  -- Define highlight groups
  vim.api.nvim_set_hl(0, 'MacroBankGroupHeader', { link = 'Function', default = true })
end

---@tag macrobank-api

-- Convenience re-exports so users can `require('macrobank')` directly
local Editor = require('macrobank.editor')
local Bank   = require('macrobank.bank_editor')
local UI     = require('macrobank.ui')
local Store  = require('macrobank.store')

--- Open the Live Macro Editor
---@param ctx table|nil Optional context (uses current if nil)
M.open_live = Editor.open

--- Open the Macro Bank Editor  
---@param ctx table|nil Optional context (uses current if nil)
M.open_bank = Bank.open

--- Show macro selection picker
---@param callback function Function called with selected macro or nil
---@param ctx table|nil Optional context (uses current if nil) 
---@param show_all boolean|nil Show all scopes if true, context-only if false
M.select_macro = UI.select_macro

--- Show fuzzy search picker for macros
---@param callback function Function called with selected macro or nil
---@param ctx table|nil Optional context (uses current if nil)
M.search_macros = UI.search_macros

--- Get all macros merged from global and project stores
---@param ctx table|nil Optional context (uses current if nil)
---@return table[] List of macro objects
M.store_all = Store.all

--- Add multiple macros to appropriate stores
---@param entries table[] List of {name, keys, scope} objects
---@param ctx table|nil Optional context
M.store_add_many = Store.add_many

--- Update existing macro, preserving history
---@param id string Macro ID
---@param fields table Fields to update
---@param ctx table|nil Optional context
M.store_update = Store.update

--- Delete macro permanently from its source file
---@param id string Macro ID
---@param ctx table|nil Optional context
M.store_delete = Store.delete

--- Find specific macro by name and scope
---@param name string Macro name
---@param scope table Scope object {type, value?}
---@param ctx table|nil Optional context
---@return table|nil Macro object or nil if not found
M.store_find_by_name_scope = Store.find_by_name_scope

--- Get version history for macro rollback
---@param id string Macro ID
---@param ctx table|nil Optional context
---@return table[] List of previous versions
M.store_history = Store.history

--- Partition macros by current context
---@param ctx table|nil Optional context
---@return table[], table[] active_macros, other_macros
M.store_partition_by_context = Store.partition_by_context

--- Get current session ID
---@return string Session identifier
M.get_session_id = Store.get_session_id

--- Scope utilities module
---@type table
M.scopes = require('macrobank.scopes')

--- Utility functions module  
---@type table
M.util = require('macrobank.util')

return M
