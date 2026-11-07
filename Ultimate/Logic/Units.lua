local ADDON, ns = ...

local Units = {}
ns.Units = Units

-- "Creature-0-4372-0-1-1234-0000ABCD" -> 1234. Players, pets and items return nil.
function Units.npcIdFromGuid(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = string.match(guid, "^(%a+)-(%d+)-(%d+)-(%d+)-(%d+)-(%d+)-")
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  return tonumber(id)
end

-- Strip anything that could break out of a /targetexact macro line.
function Units.sanitizeName(name)
  if type(name) ~= "string" then return nil end
  local clean = string.gsub(name, "[%c%[%];/|]", "")
  clean = string.gsub(clean, "^%s+", "")
  clean = string.gsub(clean, "%s+$", "")
  if clean == "" then return nil end
  return clean
end
