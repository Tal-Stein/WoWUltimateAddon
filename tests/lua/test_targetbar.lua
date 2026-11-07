local ns = __ns
local Bar = ns.TargetBar

C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
__boot(nil, {})

local function changed(names)
  local byName = {}
  for i, n in ipairs(names) do
    byName[n] = { name = n, level = 5, count = i, mobs = {}, tooltips = {}, kind = i == 1 and "rare" or "quest" }
  end
  ns:Fire("ULT_TARGETS_CHANGED", names, byName)
end

describe("TargetBar", function()
  it("lays out one secure button per name", function()
    changed({ "A", "B" })
    assertEq(UltimateTargetBarButton1:GetAttribute("macrotext"), "/cleartarget\n/targetexact A")
    assertEq(UltimateTargetBarButton2:GetAttribute("macrotext"), "/cleartarget\n/targetexact B")
    assertTrue(UltimateTargetBarButton1:IsShown())
    assertFalse(UltimateTargetBarButton3:IsShown())
  end)
  it("caps at the configured maximum", function()
    ns.db.targeting.bar.max = 2
    changed({ "A", "B", "C" })
    assertFalse(UltimateTargetBarButton3:IsShown())
    ns.db.targeting.bar.max = 6
  end)
  it("defers layout in combat without blocked actions", function()
    local errors = ns.errorCount
    __inCombat = true
    changed({ "Z" })
    assertEq(ns.errorCount, errors, "no protected calls attempted: " .. tostring(ns.lastError))
    assertEq(UltimateTargetBarButton1:GetAttribute("macrotext"), "/cleartarget\n/targetexact A")
    __inCombat = false
    __fire("PLAYER_REGEN_ENABLED")
    assertEq(UltimateTargetBarButton1:GetAttribute("macrotext"), "/cleartarget\n/targetexact Z")
  end)
  it("hides when disabled or empty", function()
    changed({})
    assertFalse(UltimateTargetBar:IsShown())
    changed({ "A" })
    assertTrue(UltimateTargetBar:IsShown())
    ns.db.targeting.bar.enabled = false
    changed({ "A" })
    assertFalse(UltimateTargetBar:IsShown())
    ns.db.targeting.bar.enabled = true
  end)
end)

describe("TargetBar review fixes", function()
  it("skips relayout when the names are unchanged", function()
    changed({ "A", "B" })
    local before = #__attrLog
    changed({ "A", "B" })
    assertEq(#__attrLog, before, "no secure writes on an identical refresh")
  end)
  it("still relayouts after a setting change", function()
    changed({ "A", "B" })
    ns.db.targeting.bar.max = 1
    ns:Fire("ULT_SETTING_CHANGED", "targeting.bar.max")
    assertFalse(UltimateTargetBarButton2:IsShown())
    ns.db.targeting.bar.max = 6
  end)
end)
