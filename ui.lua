local U = require('macrobank.util')
local S = require('macrobank.scopes')
local Store = require('macrobank.store')

local UI = {}
local cfg = nil

function UI.setup(config) cfg = config end

-- Picker label: [scope] Name  —  «keys»
function UI.picker_label(m)
  local scope = S.label(m.scope, cfg and cfg.nerd_icons)
  local keys  = U.readable(m.keys)
  return string.format('%s  %s  —  %s', scope, m.name, keys ~= '' and ('«'..keys..'»') or '∅')
end

-- Context-aware select; returns chosen macro
function UI.select_macro(cb)
  local eligible, others = Store.partition_by_context()
  table.sort(eligible, function(a,b) return a.name < b.name end)
  table.sort(others,    function(a,b) return a.name < b.name end)

  local items, map = {}, {}
  for _, m in ipairs(eligible) do table.insert(items, UI.picker_label(m)); table.insert(map, m) end
  if #eligible > 0 and #others > 0 then table.insert(items, '──────── ┈ non-context macros ┈ ────────'); table.insert(map, { __sep = true }) end
  for _, m in ipairs(others) do table.insert(items, UI.picker_label(m)); table.insert(map, m) end

  vim.ui.select(items, { prompt = 'Select macro' }, function(choice)
    if not choice then return cb(nil) end
    local idx = nil
    for i, lbl in ipairs(items) do if lbl == choice then idx = i; break end end
    local m = idx and map[idx] or nil
    if m and not m.__sep then cb(m) else cb(nil) end
  end)
end

function UI.input_name(default_name, cb)
  vim.ui.input({ prompt = 'Name for macro:', default = default_name or '' }, function(val)
    cb(val and vim.trim(val) or '')
  end)
end

function UI.input_scope(cb)
  local scopes = { 'global', 'filetype', 'session', 'cwd', 'file', 'directory' }
  vim.ui.select(scopes, { prompt = 'Scope' }, function(kind)
    if not kind then return cb(nil) end
    local ctx = S.current_context(function() return Store.get_session_id() end)
    cb({ type = kind, value = S.default_value_for(kind, ctx) })
  end)
end

-- Conflict resolver prompt
function UI.resolve_conflict(name, scope, cb)
  local items = {
    'Rename (choose a new name)',
    'Overwrite (replace existing)',
    'Duplicate (auto-suffix)',
    'Cancel',
  }
  vim.ui.select(items, { prompt = string.format('"%s" exists in %s — choose action', name, S.label(scope, cfg and cfg.nerd_icons)) }, function(choice)
    cb(choice)
  end)
end

-- Simple fuzzy search by name+keys
function UI.search_macros(cb)
  local all = Store.all()
  local labels, map = {}, {}
  for _, m in ipairs(all) do
    local label = UI.picker_label(m)
    table.insert(labels, label); table.insert(map, m)
  end
  vim.ui.input({ prompt = 'Search (fuzzy):' }, function(q)
    if not q then return cb(nil) end
    local filtered = U.matchfuzzy(labels, q)
    vim.ui.select(filtered, { prompt = 'Results' }, function(choice)
      if not choice then return cb(nil) end
      for i, l in ipairs(labels) do if l == choice then return cb(map[i]) end end
      cb(nil)
    end)
  end)
end

return UI
