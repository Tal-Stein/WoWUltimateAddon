local ADDON, ns = ...

-- Feature registry. A module is a table:
--   { key, name, description, defaults, defaultEnabled, OnEnable, OnDisable, BuildSettings }
-- Enabled state persists at ns.db.modules[key]. Modules start on PLAYER_LOGIN.
local Modules = { list = {}, byKey = {}, active = {}, started = false }
ns.Modules = Modules

function Modules:Register(def)
  assert(def.key and not self.byKey[def.key], "module key missing or duplicate")
  self.list[#self.list + 1] = def
  self.byKey[def.key] = def
  ns.DB:RegisterDefaults(def.key, def.defaults or {})
  return def
end

function Modules:Get(key) return self.byKey[key] end

function Modules:IsEnabled(key)
  local def = self.byKey[key]
  if not def or not ns.db then return false end
  local v = ns.db.modules[key]
  if v == nil then return def.defaultEnabled ~= false end
  return v
end

function Modules:IsActive(key) return self.active[key] == true end

local function start(def)
  if Modules.active[def.key] then return end
  Modules.active[def.key] = true
  if def.OnEnable then ns.SafeCall(def.OnEnable, def) end
end

local function stop(def)
  if not Modules.active[def.key] then return end
  Modules.active[def.key] = nil
  if def.OnDisable then ns.SafeCall(def.OnDisable, def) end
end

function Modules:SetEnabled(key, enabled)
  local def = self.byKey[key]
  if not def then return end
  enabled = enabled and true or false
  ns.db.modules[key] = enabled
  if self.started then
    if enabled then start(def) else stop(def) end
  end
  ns:Fire("ULT_MODULE_TOGGLED", key, enabled)
end

function Modules:Iterate()
  local i = 0
  return function()
    i = i + 1
    return self.list[i]
  end
end

ns:On("PLAYER_LOGIN", Modules, function()
  Modules.started = true
  for _, def in ipairs(Modules.list) do
    if Modules:IsEnabled(def.key) then start(def) end
  end
  ns:Fire("ULT_MODULES_STARTED")
end)
