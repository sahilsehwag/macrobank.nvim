---@brief [[
---Scopes module for MacroBank handling context matching and scope utilities.
---Provides context detection, scope matching, and display formatting.
---@brief ]]

---@tag macrobank-scopes

local S = {}

-- Icons (nerdfont); fallback to ASCII if disabled by config
local ICONS = {
  global    = '',
  filetype  = '',
  cwd       = '',
  file      = '󰈔',
  directory = '',
  project   = '',
}

local function icon(kind, nerd)
  if nerd then return ICONS[kind] or '' end
  return ({ global='G', filetype='FT', cwd='CWD', file='F', directory='DIR', project='PROJ' })[kind] or ''
end

--- Get icon for scope type
---@param kind string Scope type (global, filetype, file, directory, cwd, project)
---@param nerd boolean Whether to use nerd font icons
---@return string Icon character or ASCII fallback
function S.icon_only(kind, nerd)
  return icon(kind, nerd)
end

--- Get current context information
---@param get_session_id function Function returning session ID
---@return table Context with file, dir, filetype, cwd fields
function S.current_context(get_session_id)
  local file = vim.fn.expand('%:p')
  local dir = file ~= '' and vim.fn.fnamemodify(file, ':h') or vim.fn.getcwd()
  local ft = vim.bo.filetype or ''
  local cwd = vim.fn.getcwd()
  return { file = file, dir = dir, filetype = ft, cwd = cwd }
end

-- Return default scope value for a type given current context
function S.default_value_for(kind, ctx)
  if kind == 'filetype' then return ctx.filetype end
  if kind == 'cwd'      then return vim.fn.fnamemodify(ctx.cwd, ':~') end
  if kind == 'file'     then return vim.fn.fnamemodify(ctx.file, ':~') end
  if kind == 'directory'then return vim.fn.fnamemodify(ctx.dir, ':~') end
  if kind == 'project'  then return 'project' end
  return nil -- global
end

-- Match logic
function S.matches(scope, ctx)
  if not scope or not scope.type then return false end
  local t, v = scope.type, scope.value
  if t == 'global' then return true end
  if t == 'filetype' then return ctx.filetype ~= '' and ctx.filetype == v end
  if t == 'cwd' then return ctx.cwd ~= '' and ctx.cwd == v end
  if t == 'file' then
    local f = vim.fn.fnamemodify(v or '', ':p')
    return f ~= '' and ctx.file == f
  end
  if t == 'directory' then
    if not v or v == '' then return false end
    local dir = vim.fn.fnamemodify(v, ':p')
    local file = ctx.file or ''
    if dir == '' or file == '' then return false end
    return file:sub(1, #dir) == dir
  end
  if t == 'project' then return true end -- project scope matches all contexts within project
  return false
end

-- Human label for scope (for UI)
function S.label(scope, nerd)
  if not scope or not scope.type then return '?' end
  local t = scope.type
  local i = icon(t, nerd)
  local v = scope.value
  if v and (t == 'directory' or t == 'file' or t == 'cwd') then
    v = vim.fn.fnamemodify(v, ':~')
  end
  if v and v ~= '' then return string.format('%s %s(%s)', i, t, v) end
  return string.format('%s %s', i, t)
end

return S
