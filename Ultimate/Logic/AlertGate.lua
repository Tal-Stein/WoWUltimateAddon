local ADDON, ns = ...

-- Alert de-duplication (pure): a mob alerts at most once per guidCooldown seconds, and a mob
-- name at most once per nameCooldown seconds (so a pack of the same mob plays one sound).
local AlertGate = {}
AlertGate.__index = AlertGate
ns.AlertGate = AlertGate

function AlertGate.new(opts)
  local gate = setmetatable({ byGuid = {}, byName = {} }, AlertGate)
  gate:configure(opts)
  return gate
end

function AlertGate:configure(opts)
  self.guidCooldown = opts.guidCooldown or 60
  self.nameCooldown = opts.nameCooldown or 10
end

function AlertGate:shouldAlert(guid, name, now)
  local g = guid and self.byGuid[guid]
  if g and now - g < self.guidCooldown then return false end
  local n = name and self.byName[name]
  if n and now - n < self.nameCooldown then return false end
  if guid then self.byGuid[guid] = now end
  if name then self.byName[name] = now end
  return true
end

function AlertGate:prune(now)
  for k, t in pairs(self.byGuid) do if now - t >= self.guidCooldown then self.byGuid[k] = nil end end
  for k, t in pairs(self.byName) do if now - t >= self.nameCooldown then self.byName[k] = nil end end
end
