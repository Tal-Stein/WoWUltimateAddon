local ADDON, ns = ...

-- Nameplate scanner: one pass over visible nameplates shared by every feature.
-- Requires enemy nameplates to be on (the client only creates plates for visible units).
local NP = { units = {}, listeners = {}, order = {}, ticker = nil }
ns.Nameplates = NP

local read = ns.Safe.read

local function plateUnit(plate)
  if not plate then return nil end
  local unit = plate.namePlateUnitToken or plate.unitToken
  if not unit and plate.GetUnit then
    local ok, u = pcall(plate.GetUnit, plate)
    if ok then unit = u end
  end
  if ns.Safe.isSecret(unit) then return nil end
  return unit
end

function NP:Snapshot(unit)
  local guid = read(UnitGUID, unit)
  local name = read(UnitName, unit)
  if type(guid) ~= "string" or type(name) ~= "string" then return nil end
  local hp, hpMax = read(UnitHealth, unit), read(UnitHealthMax, unit)
  local healthPct
  if type(hp) == "number" and type(hpMax) == "number" and hpMax > 0 then healthPct = hp / hpMax end
  local level = read(UnitLevel, unit)
  return {
    unit = unit,
    guid = guid,
    npcId = ns.Units.npcIdFromGuid(guid),
    name = name,
    level = type(level) == "number" and level or nil,
    classification = read(UnitClassification, unit),
    dead = read(UnitIsDead, unit) and true or false,
    tapped = read(UnitIsTapDenied, unit) and true or false,
    attackable = read(UnitCanAttack, "player", unit) and true or false,
    isPlayer = read(UnitIsPlayer, unit) and true or false,
    healthPct = healthPct,
    plate = C_NamePlate and read(C_NamePlate.GetNamePlateForUnit, unit) or nil,
  }
end

function NP:All()
  local out = {}
  for _, m in pairs(self.units) do out[#out + 1] = m end
  return out
end

local function notify(method, ...)
  for _, owner in ipairs(NP.order) do
    local l = NP.listeners[owner]
    if l and l[method] then ns.SafeCall(l[method], ...) end
  end
end

function NP:Add(unit)
  local mob = self:Snapshot(unit)
  if not mob then return end
  self.units[unit] = mob
  notify("onAdded", mob)
end

function NP:Remove(unit)
  local mob = self.units[unit]
  self.units[unit] = nil
  if mob then notify("onRemoved", unit, mob.guid) end
end

function NP:Refresh()
  local seen = {}
  local plates = C_NamePlate and read(C_NamePlate.GetNamePlates) or {}
  for _, plate in ipairs(plates) do
    local unit = plateUnit(plate)
    if unit then
      seen[unit] = true
      local mob = self:Snapshot(unit)
      local old = self.units[unit]
      if mob then
        self.units[unit] = mob
        if not old or old.guid ~= mob.guid then notify("onAdded", mob) end
      elseif old then
        self.units[unit] = nil
        notify("onRemoved", unit, old.guid)
      end
    end
  end
  for unit, mob in pairs(self.units) do
    if not seen[unit] then
      self.units[unit] = nil
      notify("onRemoved", unit, mob.guid)
    end
  end
  notify("onRefresh", self:All())
end

local function interval()
  local v = ns.db and ns.db.core and ns.db.core.scanInterval or 0.5
  if v < 0.2 then v = 0.2 elseif v > 2 then v = 2 end
  return v
end

function NP:StartTicker()
  if self.ticker then self.ticker:Cancel() end
  self.ticker = C_Timer.NewTicker(interval(), function() NP:Refresh() end)
end

function NP:StopTicker()
  if self.ticker then self.ticker:Cancel(); self.ticker = nil end
end

function NP:AddListener(owner, callbacks)
  if not self.listeners[owner] then self.order[#self.order + 1] = owner end
  self.listeners[owner] = callbacks
  if not self.active then
    self.active = true
    ns:On("NAME_PLATE_UNIT_ADDED", NP, function(_, unit) NP:Add(unit) end)
    ns:On("NAME_PLATE_UNIT_REMOVED", NP, function(_, unit) NP:Remove(unit) end)
    self:StartTicker()
    self:Refresh()
  end
end

function NP:RemoveListener(owner)
  if not self.listeners[owner] then return end
  self.listeners[owner] = nil
  for i = #self.order, 1, -1 do if self.order[i] == owner then table.remove(self.order, i) end end
  if #self.order == 0 and self.active then
    self.active = false
    ns:Off("NAME_PLATE_UNIT_ADDED", NP)
    ns:Off("NAME_PLATE_UNIT_REMOVED", NP)
    self:StopTicker()
    self.units = {}
  end
end

function NP:EnemyPlatesOn()
  if not GetCVarBool then return true end
  return read(GetCVarBool, "nameplateShowEnemies") and true or false
end

ns:On("ULT_SETTING_CHANGED", NP, function(_, path)
  if path == "core.scanInterval" and NP.ticker then NP:StartTicker() end
end)
