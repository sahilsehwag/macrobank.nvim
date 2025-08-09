local U = require('macrobank.util')
local S = require('macrobank.scopes')
local Store = require('macrobank.store')

local UI = {}
local cfg = nil

function UI.setup(config) cfg = config end

-- Picker label: [scope] Name  —  «keys»
local function context_for(scope)
  if not scope or not scope.type then return '' end
  local v = scope.value or ''
  if scope.type == 'directory' or scope.type == 'file' or scope.type == 'cwd' then
    v = vim.fn.fnamemodify(v, ':~')
  end
  return v
end

function UI.picker_label(m)
  local scope = m.scope and m.scope.type or 'global'
  local ctx = context_for(m.scope)
  if ctx ~= '' then return string.format('[%s] %s %s', scope, m.name, ctx) end
  return string.format('[%s] %s', scope, m.name)
end

-- Context-aware select; returns chosen macro
function UI.select_macro(cb, ctx)
  local all = Store.all(ctx)
  local cur = ctx or S.current_context(function() return Store.get_session_id() end)
  local groups = {}
  for _, m in ipairs(all) do
    local label
    if S.matches(m.scope, cur) then
      label = 'Active macros'
    else
      label = S.label(m.scope, cfg and cfg.nerd_icons)
    end
    groups[label] = groups[label] or { label = label, macros = {} }
    table.insert(groups[label].macros, m)
  end

  local ordered = {}
  for _, g in pairs(groups) do table.insert(ordered, g) end
  table.sort(ordered, function(a,b) return a.label < b.label end)
  local final = {}
  for _, g in ipairs(ordered) do if g.label == 'Active macros' then table.insert(final, 1, g) else final[#final+1] = g end end

  local items, map = {}, {}
  for _, g in ipairs(final) do
    table.insert(items, U.hr_left(g.label, 60, '-')); table.insert(map, { __sep = true })
    table.sort(g.macros, function(a,b) return a.name < b.name end)
    for _, m in ipairs(g.macros) do table.insert(items, UI.picker_label(m)); table.insert(map, m) end
  end

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

function UI.input_scope(cb, ctx)
  local scopes = { 'global', 'filetype', 'session', 'cwd', 'file', 'directory' }
  vim.ui.select(scopes, { prompt = 'Scope' }, function(kind)
    if not kind then return cb(nil) end
    local base = ctx or S.current_context(function() return Store.get_session_id() end)
    cb({ type = kind, value = S.default_value_for(kind, base) })
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
function UI.search_macros(cb, ctx)
  local all = Store.all(ctx)
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
