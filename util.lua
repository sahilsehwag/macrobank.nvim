local U = {}

function U.readable(keys)
  return vim.fn.keytrans(keys or '')
end

function U.to_termcodes(s)
  return vim.api.nvim_replace_termcodes(s or '', true, true, true)
end

-- Parse a Live Editor line: "a  keys" → { reg = 'a', text = 'keys' }
function U.parse_reg_line(line)
  if not line then return nil end
  local reg, text = line:match('^([a-z])%s%s(.*)$')
  if not reg then return nil end
  return { reg = reg, text = text or '' }
end

-- Parse a Macro Bank line: "name  keys" → { name, text }
function U.parse_bank_line(line)
  if not line then return nil end
  local name, text = line:match('^(.-)%s%s(.*)$')
  if not name then return nil end
  return { name = vim.trim(name), text = text or '' }
end

-- Tiny uuid (good enough for ids)
function U.uuid()
  local n = tostring(vim.loop.hrtime()):reverse()
  return n:sub(1,8)..'-'..n:sub(9,12)..'-'..n:sub(13,16)
end

-- Messages
function U.info(msg)  vim.notify(msg, vim.log.levels.INFO) end
function U.warn(msg)  vim.notify(msg, vim.log.levels.WARN) end
function U.err(msg)   vim.notify(msg, vim.log.levels.ERROR) end

-- Fuzzy helper (built-in fallback)
function U.matchfuzzy(list, query)
  if query == '' then return list end
  if vim.fn.exists('*matchfuzzy') == 1 then return vim.fn.matchfuzzy(list, query) end
  local out, q = {}, query:lower()
  for _, s in ipairs(list) do if tostring(s):lower():find(q, 1, true) then table.insert(out, s) end end
  return out
end

-- Horizontal rule with centered text
function U.hr(text, width, ch)
  ch = ch or '-'
  width = width or vim.o.columns
  local t = text and text ~= '' and (' '..text..' ') or ''
  local fill = width - #t
  if fill < 0 then fill = 0 end
  local left = math.floor(fill/2)
  local right = fill - left
  return string.rep(ch, left)..t..string.rep(ch, right)
end

return U
