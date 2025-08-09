local S = {}

-- Icons (nerdfont); fallback to ASCII if disabled by config
local ICONS = {
  global    = '',
  filetype  = '',
  session   = '',
  cwd       = '',
  file      = '󰈔',
  directory = '',
}

local function icon(kind, nerd)
  if nerd then return ICONS[kind] or '' end
  return ({ global='G', filetype='FT', session='S', cwd='CWD', file='F', directory='DIR' })[kind] or ''
end

function S.current_context(get_session_id)
  local file = vim.api.nvim_buf_get_name(0)
  local file_abs = vim.fn.fnamemodify(file, ':p')
  local dir = file_abs ~= '' and vim.fn.fnamemodify(file_abs, ':h') or vim.loop.cwd()
  local ft = vim.bo.filetype or ''
  local cwd = vim.loop.cwd() or ''
  return { file = file_abs, dir = dir, filetype = ft, cwd = cwd, session = get_session_id() }
end

-- Return default scope value for a type given current context
function S.default_value_for(kind, ctx)
  if kind == 'filetype' then return ctx.filetype end
  if kind == 'cwd'      then return ctx.cwd end
  if kind == 'file'     then return ctx.file end
  if kind == 'session'  then return ctx.session end
  if kind == 'directory'then return ctx.dir end
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
  if t == 'session' then return ctx.session == v end
  if t == 'directory' then
    if not v or v == '' then return false end
    local dir = vim.fn.fnamemodify(v, ':p')
    local file = ctx.file or ''
    if dir == '' or file == '' then return false end
    return file:sub(1, #dir) == dir
  end
  return false
end

-- Human label for scope (for UI)
function S.label(scope, nerd)
  if not scope or not scope.type then return '[?]' end
  local t = scope.type
  local i = icon(t, nerd)
  local v = scope.value
  if t == 'file' or t == 'directory' then if v then v = vim.fn.fnamemodify(v, ':.') end end
  if v and v ~= '' then return string.format('[%s %s:%s]', i, t, v) end
  return string.format('[%s %s]', i, t)
end

return S
