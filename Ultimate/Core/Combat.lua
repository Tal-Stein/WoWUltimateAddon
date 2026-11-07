local ADDON, ns = ...

-- Combat-safe queue for protected work (secure attributes, secure frame layout, CVars, macros).
-- Out of combat the work runs immediately; in combat it is stored per key (last call wins) and
-- runs in first-queued order once combat ends.
local Combat = { queue = {}, order = {} }
ns.Combat = Combat

function Combat:Run(key, fn)
  if not InCombatLockdown() then
    self.queue[key] = nil
    ns.SafeCall(fn)
    return true
  end
  if not self.queue[key] then self.order[#self.order + 1] = key end
  self.queue[key] = fn
  return false
end

function Combat:IsPending(key) return self.queue[key] ~= nil end

function Combat:Flush()
  if InCombatLockdown() then return end
  local order, queue = self.order, self.queue
  self.order, self.queue = {}, {}
  for _, key in ipairs(order) do
    if queue[key] then ns.SafeCall(queue[key]) end
  end
end

ns:On("PLAYER_REGEN_ENABLED", Combat, function() Combat:Flush() end)
