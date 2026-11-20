local ADDON, ns = ...

-- Remembered creature portraits. A portrait can only be drawn from a live unit, but its model
-- number (display ID) can be kept: when a mob is seen (nameplate, target, mouseover) a hidden
-- model frame loads it and reads the display ID, stored per name, account-wide. A mob with no
-- unit (e.g. a long-range find) then gets its portrait via the game's
-- SetPortraitTextureFromCreatureDisplayID, the same call Blizzard's UI uses for creatures.
local P = {}
ns.Portraits = P

local function store()
  if not ns.global then return nil end
  ns.global.displayIds = ns.global.displayIds or {}
  return ns.global.displayIds
end

-- A model frame of our own, invisible but not hidden (hidden models may not load).
P.model = CreateFrame("PlayerModel", nil, UIParent)
P.model:SetSize(1, 1)
P.model:SetAlpha(0)
P.model:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10)

local function read(name)
  local ok, id = pcall(P.model.GetDisplayInfo, P.model)
  id = ok and tonumber(id) or 0
  local cache = store()
  if cache and id > 0 then cache[name] = id; return true end
  return false
end

function P:Learn(unit)
  local cache = store()
  if not cache or not ns.Safe.read(UnitExists, unit) or ns.Safe.read(UnitIsPlayer, unit) then return end
  local name = ns.Safe.read(UnitName, unit)
  if type(name) ~= "string" or cache[name] then return end
  if not pcall(self.model.SetUnit, self.model, unit) then return end
  if not read(name) then self.model.pendingName = name end -- the model may still be loading
end

if P.model.SetScript then
  P.model:SetScript("OnModelLoaded", function(self)
    if self.pendingName then
      read(self.pendingName)
      self.pendingName = nil
    end
  end)
end

-- Draw a remembered portrait into texture; false if this mob hasn't been seen yet.
function P:Apply(texture, name)
  local cache = store()
  local id = cache and name and cache[name]
  local draw = SetPortraitTextureFromCreatureDisplayID
  if not (id and texture and type(draw) == "function") then return false end
  return (pcall(draw, texture, id))
end

ns:On("NAME_PLATE_UNIT_ADDED", P, function(_, unit) ns.SafeCall(P.Learn, P, unit) end)
ns:On("PLAYER_TARGET_CHANGED", P, function() ns.SafeCall(P.Learn, P, "target") end)
ns:On("UPDATE_MOUSEOVER_UNIT", P, function() ns.SafeCall(P.Learn, P, "mouseover") end)
