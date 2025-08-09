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
  local order = { global=1, filetype=2, cwd=3, session=4, directory=5, file=6 }
  local active, groups = {}, {}
  for _, m in ipairs(all) do
    if S.matches(m.scope, cur) then
      table.insert(active, m)
    else
      local s = m.scope or { type = 'global' }
      local key = s.type .. '|' .. (s.value or '')
      groups[key] = groups[key] or { scope = s, macros = {} }
      table.insert(groups[key].macros, m)
    end
  end

  table.sort(active, function(a,b) return a.name < b.name end)
  local ordered = {}
  for _, g in pairs(groups) do table.insert(ordered, g) end
  table.sort(ordered, function(a,b)
    local oa = order[a.scope.type] or 99
    local ob = order[b.scope.type] or 99
    if oa ~= ob then return oa < ob end
    local va = a.scope.value or ''
    local vb = b.scope.value or ''
    return va < vb
  end)

  local final = {}
  if #active > 0 then final[#final+1] = { label = 'Active macros', macros = active } end
  for _, g in ipairs(ordered) do
    table.sort(g.macros, function(a,b) return a.name < b.name end)
    g.label = S.label(g.scope, cfg and cfg.nerd_icons)
    final[#final+1] = g
  end

  local items, map = {}, {}
  for _, g in ipairs(final) do
    table.insert(items, U.hr(g.label, 60, '-')); table.insert(map, { __sep = true })
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
