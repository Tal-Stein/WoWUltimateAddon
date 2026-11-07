local ADDON, ns = ...

-- Pure table helpers (no WoW globals).
local Tables = {}
ns.Tables = Tables

function Tables.copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = Tables.copy(v) end
  return out
end

-- Fill keys missing from `saved` with copies of `defaults`. Existing values are never replaced.
function Tables.merge(defaults, saved)
  for k, v in pairs(defaults) do
    if saved[k] == nil then
      saved[k] = Tables.copy(v)
    elseif type(v) == "table" and type(saved[k]) == "table" then
      Tables.merge(v, saved[k])
    end
  end
  return saved
end

-- Resolve a dotted path ("a.b.c") inside root. Returns value, parentTable, lastKey.
function Tables.getPath(root, path)
  local parent, key = root, nil
  for part in string.gmatch(path, "[^%.]+") do
    if key ~= nil then
      if type(parent[key]) ~= "table" then return nil end
      parent = parent[key]
    end
    key = tonumber(part) or part
  end
  if type(parent) ~= "table" then return nil end
  return parent[key], parent, key
end

function Tables.setPath(root, path, value)
  local parent, key = root, nil
  for part in string.gmatch(path, "[^%.]+") do
    if key ~= nil then
      if type(parent[key]) ~= "table" then parent[key] = {} end
      parent = parent[key]
    end
    key = tonumber(part) or part
  end
  parent[key] = value
end
