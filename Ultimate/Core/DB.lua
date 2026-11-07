local ADDON, ns = ...

-- SavedVariables: UltimateDB (account) and UltimateCharDB (character).
-- The active profile (ns.db) is the character table by default, or UltimateDB.profile when
-- the owner switches scope to "account" (takes effect after /reload).
local DB = { defaults = {} }
ns.DB = DB

DB.defaults.core = {
  debug = false,
  scanInterval = 0.5,
  lockAll = false,
}
DB.defaults.modules = {}

function DB:RegisterDefaults(path, defaults)
  self.defaults[path] = defaults
  if ns.db then
    ns.db[path] = ns.db[path] or {}
    ns.Tables.merge(defaults, ns.db[path])
  end
end

function DB:Load()
  UltimateDB = UltimateDB or {}
  UltimateCharDB = UltimateCharDB or {}
  local global = UltimateDB
  if global.scope ~= "account" then global.scope = "char" end
  local profile
  if global.scope == "account" then
    global.profile = global.profile or {}
    profile = global.profile
  else
    profile = UltimateCharDB
  end
  for path, defaults in pairs(self.defaults) do
    profile[path] = profile[path] or {}
    ns.Tables.merge(defaults, profile[path])
  end
  ns.global, ns.db = global, profile
  ns:Fire("ULT_DB_READY")
end

ns:On("ADDON_LOADED", DB, function(_, name)
  if name ~= ADDON then return end
  ns:Off("ADDON_LOADED", DB)
  DB:Load()
end)
