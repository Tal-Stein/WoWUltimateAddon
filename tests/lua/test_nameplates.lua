local ns = __ns
local NP = ns.Nameplates

__units = {}
local function unitField(field) return function(unit) local u = __units[unit]; return u and u[field] end end
UnitGUID = unitField("guid")
UnitName = unitField("name")
UnitLevel = unitField("level")
UnitClassification = unitField("classification")
UnitIsDead = unitField("dead")
UnitIsTapDenied = unitField("tapped")
UnitIsPlayer = unitField("isPlayer")
UnitHealth = unitField("hp")
UnitHealthMax = unitField("hpMax")
UnitCanAttack = function(_, unit) local u = __units[unit]; return u and u.attackable end
local plates = {}
C_NamePlate = {
  GetNamePlates = function() local out = {} for _, p in pairs(plates) do out[#out + 1] = p end return out end,
  GetNamePlateForUnit = function(unit) return plates[unit] end,
}

local function addUnit(unit, over)
  local u = { guid = "Creature-0-1-0-1-" .. (over and over.id or 40) .. "-000" .. unit, name = "Kobold", level = 5,
    classification = "normal", dead = false, tapped = false, isPlayer = false, attackable = true, hp = 50, hpMax = 100 }
  for k, v in pairs(over or {}) do u[k] = v end
  __units[unit] = u
  plates[unit] = { namePlateUnitToken = unit }
end

__boot(nil, {})

describe("Nameplates", function()
  it("test_snapshot_reads_fields", function()
    addUnit("nameplate1", { id = 40 })
    local m = NP:Snapshot("nameplate1")
    assertEq(m.npcId, 40)
    assertEq(m.name, "Kobold")
    assertEq(m.level, 5)
    assertEq(m.healthPct, 0.5)
    assertEq(m.attackable, true)
    assertTrue(m.plate == plates.nameplate1)
  end)
  it("test_snapshot_skips_secret_values", function()
    local secretGuid = "SECRET-GUID"
    addUnit("nameplate2", { guid = secretGuid })
    __secret[secretGuid] = true
    assertNil(NP:Snapshot("nameplate2"), "secret GUID -> skip unit")
    local secretLevel = {}
    __secret[secretLevel] = true
    addUnit("nameplate3", { level = secretLevel, hp = secretLevel })
    local m = NP:Snapshot("nameplate3")
    assertTrue(m ~= nil)
    assertNil(m.level)
    assertNil(m.healthPct)
    local ok, reason = ns.Filters.passes(m, 5, 0, { minOffset = -10, maxOffset = 3, exclude = {} })
    assertFalse(ok)
    assertEq(reason, "level")
  end)
  it("test_listeners_added_removed", function()
    for k in pairs(plates) do plates[k] = nil end
    local added, removed, refreshed = {}, {}, 0
    NP:AddListener("t", {
      onAdded = function(m) added[#added + 1] = m.name end,
      onRemoved = function(unit, guid) removed[#removed + 1] = unit end,
      onRefresh = function(mobs) refreshed = refreshed + 1 end,
    })
    addUnit("nameplate4", { name = "Murloc" })
    __fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
    assertEq(added, { "Murloc" })
    local found = false
    for _, m in ipairs(NP:All()) do if m.name == "Murloc" then found = true end end
    assertTrue(found, "All() includes the plate")
    __fire("NAME_PLATE_UNIT_REMOVED", "nameplate4")
    plates.nameplate4 = nil
    assertEq(removed, { "nameplate4" })
    __advance(0, true)
    assertTrue(refreshed >= 1, "ticker refresh")
    NP:RemoveListener("t")
    __advance(0, true)
    local before = refreshed
    __advance(0, true)
    assertEq(refreshed, before, "no refresh after removal")
  end)
  it("announces plates that become readable on refresh", function()
    local added = {}
    NP:AddListener("late", { onAdded = function(m) added[#added + 1] = m.name end })
    local g = "LATE-GUID"
    __secret[g] = true
    addUnit("nameplate5", { name = "Late", guid = g })
    __fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
    assertEq(#added, 0)
    __secret[g] = nil
    __units.nameplate5.guid = "Creature-0-1-0-1-99-0005"
    __advance(0, true)
    assertEq(added, { "Late" })
    NP:RemoveListener("late")
  end)
end)
