local ns = __ns
local T = ns.Targeting

UnitName = function(unit) return __targetName end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
IsInGroup = function() return false end

__boot(nil, {})

local function cand(name, level, remaining, extra)
  local c = { name = name, level = level, remaining = remaining, count = 1, mobs = {}, kind = "quest" }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

local function macro() return UltimateTargetButton:GetAttribute("macrotext") end

describe("Targeting", function()
  it("button is a secure macro button", function()
    assertEq(UltimateTargetButton:GetAttribute("type"), "macro")
    assertTrue(UltimateTargetButton.secure)
  end)
  it("test_refresh_merges_providers_and_sets_macro", function()
    T:RegisterProvider("p1", function() return { cand("A", 5, 3), cand("B", 6, 1) } end)
    T:RegisterProvider("p2", function() return { cand("A", 4, 9, { isRare = true, count = 2 }) } end)
    T:Refresh()
    assertEq(T.ranked, { "A", "B" }, "rare A first")
    assertEq(T.byName.A.count, 3)
    assertEq(T.byName.A.level, 4)
    assertEq(T.byName.A.remaining, 3)
    assertTrue(T.byName.A.isRare)
    local expected = ns.Macro.build({ "A", "B" }, 1, { stopInCombat = true, fallbacks = 2, marker = 0 })
    assertEq(macro(), expected)
    T:UnregisterProvider("p1"); T:UnregisterProvider("p2")
  end)
  it("test_refresh_in_combat_deferred", function()
    T:RegisterProvider("p", function() return { cand("C", 5, 1) } end)
    __inCombat = true
    T:Refresh()
    assertTrue(macro():find("C", 1, true) == nil, "not applied during combat")
    __inCombat = false
    __fire("PLAYER_REGEN_ENABLED")
    assertTrue(macro():find("/targetexact C", 1, true) ~= nil, "applied after combat")
    T:UnregisterProvider("p")
  end)
  it("test_cursor_advance_on_target_change", function()
    T:RegisterProvider("p", function() return { cand("A", 1, 1), cand("B", 2, 1) } end)
    T:Refresh()
    assertTrue(macro():find("/targetexact A\n", 1, true) ~= nil)
    __targetName = "A"
    __fire("PLAYER_TARGET_CHANGED")
    assertTrue(macro():find("/targetexact B\n", 1, true) ~= nil, "advanced to B")
    __targetName = "Unrelated"
    __fire("PLAYER_TARGET_CHANGED")
    assertTrue(macro():find("/targetexact B\n", 1, true) ~= nil, "unchanged for other targets")
    __targetName = nil
    T:UnregisterProvider("p")
  end)
  it("test_no_providers_empty_macro", function()
    T:Refresh()
    assertEq(macro(), "/cleartarget [dead]")
    assertEq(#T.ranked, 0)
  end)
  it("auto-arm off keeps the macro until a forced refresh", function()
    ns.db.targeting.autoArm = false
    T:RegisterProvider("p", function() return { cand("D", 1, 1) } end)
    T:Refresh()
    assertTrue(macro():find("D", 1, true) == nil, "not armed")
    T:Refresh(true)
    assertTrue(macro():find("/targetexact D", 1, true) ~= nil, "forced refresh arms")
    ns.db.targeting.autoArm = true
    T:UnregisterProvider("p")
  end)
  it("adds the raid marker only when allowed", function()
    ns.db.targeting.marker = 8
    T:RegisterProvider("p", function() return { cand("E", 1, 1) } end)
    T:Refresh()
    assertTrue(macro():find("/tm", 1, true) ~= nil)
    IsInGroup = function() return true end
    T:Refresh()
    assertTrue(macro():find("/tm", 1, true) == nil, "solo-only by default")
    IsInGroup = function() return false end
    ns.db.targeting.marker = 0
    T:UnregisterProvider("p")
  end)
  it("fires ULT_TARGETS_CHANGED with the ranking", function()
    local got
    ns:On("ULT_TARGETS_CHANGED", "t", function(_, ranked) got = ranked end)
    T:RegisterProvider("p", function() return { cand("F", 1, 1) } end)
    T:Refresh()
    assertEq(got, { "F" })
    ns:Off("ULT_TARGETS_CHANGED", "t")
    T:UnregisterProvider("p")
  end)
end)

describe("Targeting review fixes", function()
  it("clears the key when nothing is left, even with auto-arm off", function()
    T:RegisterProvider("p", function() return { cand("Stale", 1, 1) } end)
    T:Refresh()
    ns.db.targeting.autoArm = false
    T:UnregisterProvider("p")
    assertEq(macro(), "/cleartarget [dead]")
    ns.db.targeting.autoArm = true
  end)
  it("does not rewrite an unchanged macro", function()
    T:RegisterProvider("p", function() return { cand("Same", 1, 1) } end)
    T:Refresh()
    local before = #__attrLog
    T:Refresh()
    assertEq(#__attrLog, before, "no SetAttribute for identical text")
    T:UnregisterProvider("p")
  end)
end)
