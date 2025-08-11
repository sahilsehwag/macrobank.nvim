local U = require('macrobank.util')
local S = require('macrobank.scopes')

local Store = {}

local cfg = nil
local STATE = { session_id = tostring(vim.loop.hrtime()) }

-- JSON helpers
local function json_encode(tbl)
  if vim.json and vim.json.encode then return vim.json.encode(tbl) end
  return vim.fn.json_encode(tbl)
end
local function json_decode(s)
  if vim.json and vim.json.decode then return vim.json.decode(s) end
  return vim.fn.json_decode(s)
end

-- IO helpers
local function read_file(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local s = f:read('*a'); f:close(); return s
end
local function write_file(path, s)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  local f = io.open(path, 'w')
  if not f then return false end
  f:write(s); f:close(); return true
end

local DEFAULT_PROJECT_FILES = {
  '.macrobank.json',
  '.nvim/macrobank.json',
}

-- Upward search from a directory for any of the candidate files; returns all found
local function find_upwards(start_dir, candidates)
  local found = {}
  local dir = start_dir
  local seen = {}
  while dir and dir ~= '' and not seen[dir] do
    seen[dir] = true
    for _, name in ipairs(candidates) do
      local p = dir .. '/' .. name
      if vim.loop.fs_stat(p) then table.insert(found, p) end
    end
    local parent = vim.fn.fnamemodify(dir, ':h')
    if parent == dir then break end
    dir = parent
  end
  return found
end

-- Compose project paths based on config
local function project_paths(ctx)
  local curr_file = (ctx and ctx.file and ctx.file ~= '') and ctx.file or vim.api.nvim_buf_get_name(0)
  local start_dir = curr_file ~= '' and vim.fn.fnamemodify(curr_file, ':h') or vim.loop.cwd()

  local list = {}
  if type(cfg.project_store_paths) == 'string' and cfg.project_store_paths ~= '' then
    list = { cfg.project_store_paths }
  elseif type(cfg.project_store_paths) == 'table' and #cfg.project_store_paths > 0 then
    list = cfg.project_store_paths
  else
    -- Use defaults with smart .nvim/ detection
    local root = vim.fn.getcwd()
    if vim.loop.fs_stat(root .. '/.nvim') and (vim.loop.fs_stat(root .. '/.nvim').type == 'directory') then
      list = { '.nvim/macrobank.json', '.macrobank.json' }
    else
      list = { '.macrobank.json', '.nvim/macrobank.json' }
    end
  end
  return find_upwards(start_dir, list)
end

local function global_path()
  return (cfg and cfg.store_path_global) or (vim.fn.stdpath('config') .. '/macrobank_store.json')
end

-- Load from multiple stores and annotate source path
local function load_all_sources(ctx)
  local paths = project_paths(ctx)
  table.insert(paths, global_path())
  local merged, by_id = { version = 2, macros = {} }, {}
  for _, p in ipairs(paths) do
    local raw = read_file(p)
    if raw and raw ~= '' then
      local ok, data = pcall(json_decode, raw)
      if ok and type(data) == 'table' and type(data.macros) == 'table' then
        for _, m in ipairs(data.macros) do
          -- migrate v1 if needed
          if not m.keys and m.disp then m.keys = U.to_termcodes(m.disp); m.disp = nil end
          m.scope = m.scope or { type = 'global' }
          m.id = m.id or U.uuid()
          m.__source = p
          if not by_id[m.id] then
            by_id[m.id] = true
            table.insert(merged.macros, m)
          end
        end
      end
    end
  end
  return merged
end

local function save_to_path(path, data)
  data.version = 2
  return write_file(path, json_encode({ version = 2, macros = data.macros }))
end

-- Get the first project path for creation when no project store exists
local function get_project_create_path(ctx)
  local curr_file = (ctx and ctx.file and ctx.file ~= '') and ctx.file or vim.api.nvim_buf_get_name(0)
  local root = curr_file ~= '' and vim.fn.fnamemodify(curr_file, ':h') or vim.loop.cwd()
  -- Walk up to find project root (could be improved, but use getcwd for simplicity)
  root = vim.fn.getcwd()

  -- Determine the first path from project_store_paths configuration
  local first_path
  if type(cfg.project_store_paths) == 'string' and cfg.project_store_paths ~= '' then
    first_path = cfg.project_store_paths
  elseif type(cfg.project_store_paths) == 'table' and #cfg.project_store_paths > 0 then
    first_path = cfg.project_store_paths[1]
  else
    -- Use smart default: .nvim/macrobank.json if .nvim/ exists, otherwise .macrobank.json
    if vim.loop.fs_stat(root .. '/.nvim') and (vim.loop.fs_stat(root .. '/.nvim').type == 'directory') then
      first_path = '.nvim/macrobank.json'
    else
      first_path = '.macrobank.json'
    end
  end

  return root .. '/' .. first_path
end

-- Choose a target file for a new macro, based on scope
local function choose_target_path(scope, ctx)
  -- Only project-scoped macros go to project config
  if scope and scope.type == 'project' then
    local existing_proj_paths = project_paths(ctx)
    -- Use any existing project config file; if none exist, create using first configured path
    local existing_proj_target = (#existing_proj_paths > 0) and existing_proj_paths[1] or nil
    return existing_proj_target or get_project_create_path(ctx)
  end

  -- All other scopes (global, filetype, file, directory, cwd) go to global config
  return global_path()
end

function Store.setup(config)
  cfg = config
end

function Store.get_session_id() return STATE.session_id end

function Store.all(ctx)
  return load_all_sources(ctx).macros
end

-- Find by name+scope (exact match of type+value)
function Store.find_by_name_scope(name, scope, ctx)
  if not name or not scope then return nil end
  for _, m in ipairs(Store.all(ctx)) do
    if m.name == name and m.scope and m.scope.type == scope.type and (m.scope.value or '') == (scope.value or '') then
      return m
    end
  end
  return nil
end

function Store.add_many(entries, ctx)
  -- entries: { {name, keys, scope} ... }
  for _, e in ipairs(entries) do
    local target = choose_target_path(e.scope, ctx)
    local data = { version = 2, macros = {} }
    local raw = read_file(target)
    if raw and raw ~= '' then
      local ok, loaded = pcall(json_decode, raw)
      if ok and type(loaded) == 'table' and type(loaded.macros) == 'table' then data = loaded end
    end
    e.id = e.id or U.uuid()
    e.saved_at = e.saved_at or os.date('!%Y-%m-%dT%H:%M:%SZ')
    e.updated_at = os.date('!%Y-%m-%dT%H:%M:%SZ')
    table.insert(data.macros, e)
    save_to_path(target, data)
  end
end

function Store.update(id, fields, ctx)
  -- update within the original source file when possible
  local all = load_all_sources(ctx).macros
  local target = nil; local current = nil
  for _, m in ipairs(all) do if m.id == id then target = m.__source; current = m; break end end
  target = target or global_path()

  local raw = read_file(target)
  local data = { version = 2, macros = {} }
  if raw and raw ~= '' then
    local ok, loaded = pcall(json_decode, raw)
    if ok and type(loaded) == 'table' and type(loaded.macros) == 'table' then data = loaded end
  end

  for _, m in ipairs(data.macros) do
    if m.id == id then
      -- history snapshot
      m.history = m.history or {}
      table.insert(m.history, { keys = m.keys, name = m.name, updated_at = m.updated_at or m.saved_at })
      for k, v in pairs(fields) do m[k] = v end
      m.updated_at = os.date('!%Y-%m-%dT%H:%M:%SZ')
      break
    end
  end
  save_to_path(target, data)
end

function Store.delete(id, ctx)
  -- delete from its source
  local all = load_all_sources(ctx).macros
  local target = nil
  for _, m in ipairs(all) do if m.id == id then target = m.__source; break end end
  target = target or global_path()
  local raw = read_file(target)
  local data = { version = 2, macros = {} }
  if raw and raw ~= '' then
    local ok, loaded = pcall(json_decode, raw)
    if ok and type(loaded) == 'table' and type(loaded.macros) == 'table' then data = loaded end
  end
  local out = {}
  for _, m in ipairs(data.macros) do if m.id ~= id then table.insert(out, m) end end
  data.macros = out
  save_to_path(target, data)
end

-- History helpers
function Store.history(id, ctx)
  for _, m in ipairs(Store.all(ctx)) do if m.id == id then return m.history or {} end end
  return {}
end

-- Return two arrays: eligible (match current ctx) and others
function Store.partition_by_context(ctx)
  local data = load_all_sources(ctx)
  ctx = ctx or S.current_context(function() return STATE.session_id end)
  local eligible, others = {}, {}
  for _, m in ipairs(data.macros) do
    if S.matches(m.scope, ctx) then table.insert(eligible, m) else table.insert(others, m) end
  end
  return eligible, others
end

return Store
