local ADDON, ns = ...

-- SavedVariables: UltimateDB (account) and UltimateCharDB (character).
-- The active profile (ns.db) is UltimateDB.profile (account-wide, the default) or the character
-- table when the owner switches scope to "char" (takes effect after /reload).
local DB = { defaults = {} }
ns.DB = DB

DB.defaults.core = {
  debug = false,
  scanInterval = 0.5,
  lockAll = false,
  minimap = { hide = false, angle = 200 },
}
DB.defaults.modules = {}

-- Character facts kept in UltimateCharDB whatever the profile scope.
local PER_CHARACTER = { focusedChatState = true }

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
  -- Version 2: account-wide is the default. Profiles from before that move once to account-wide;
  -- the shared profile starts from this character's settings when it doesn't exist yet.
  if (global.scopeVersion or 1) < 2 then
    if global.scope ~= "account" and next(global.profile or {}) == nil then
      global.profile = {}
      for k, v in pairs(UltimateCharDB) do
        if not PER_CHARACTER[k] then global.profile[k] = ns.Tables.copy(v) end
      end
    end
    global.scope = "account"
    global.scopeVersion = 2
  end
  if global.scope ~= "char" then global.scope = "account" end
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
