local ADDON, ns = ...

-- Secret-value safe reads. Midnight-era clients may return "secret" values that add-on code
-- must not inspect; any such value (or any error) reads as nil, and callers skip the unit.
local Safe = {}
ns.Safe = Safe

function Safe.isSecret(v)
  if v == nil or not issecretvalue then return false end
  local ok, secret = pcall(issecretvalue, v)
  return not ok or secret == true
end

-- Returns the first return value of fn(...), or nil if it errored or is secret.
function Safe.read(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or Safe.isSecret(v) then return nil end
  return v
end
