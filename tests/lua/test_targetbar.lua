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
  it("shows the empty panel right after login", function()
    assertTrue(UltimateTargetBar:IsShown())
    assertTrue(Bar.empty:IsShown())
  end)
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
  it("stays visible while enabled, hides when disabled", function()
    changed({})
    assertTrue(UltimateTargetBar:IsShown(), "the panel stays put when empty")
    assertTrue(Bar.empty:IsShown(), "and says nothing is nearby")
    changed({ "A" })
    assertTrue(UltimateTargetBar:IsShown())
    assertFalse(Bar.empty:IsShown())
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

describe("TargetBar button art", function()
  it("keeps the template's own button size and scales the bar instead", function()
    for _, b in ipairs(Bar.buttons) do b.GetWidth = function() return 45 end end
    Bar.native = nil
    changed({ "Q" })
    Bar:Layout(true)
    assertTrue(math.abs(Bar.barScale - 36 / 45) < 1e-6)
  end)
end)

describe("TargetBar panel", function()
  local function point(b) return b.point end -- { "TOPLEFT", frame, "TOPLEFT", x, y }
  it("wraps many targets into rows, aligned to the same columns", function()
    for _, b in ipairs(Bar.buttons) do b.GetWidth = function() return 36 end end
    Bar.native = nil
    ns.db.targeting.bar.max = 24
    ns.db.targeting.bar.perRow = 6
    local names = {}
    for i = 1, 14 do names[i] = "Mob" .. i end
    changed(names)
    assertTrue(UltimateTargetBarButton14:IsShown(), "up to 24 buttons")
    local p1, p7, p13 = point(UltimateTargetBarButton1), point(UltimateTargetBarButton7), point(UltimateTargetBarButton13)
    assertEq(p1[1], "TOPLEFT")
    assertTrue(p1[2] == Bar.frame, "anchored inside the panel")
    assertEq(p7[4], p1[4], "row 2 starts in column 1")
    assertEq(p13[4], p1[4], "row 3 starts in column 1")
    assertTrue(p7[5] < p1[5] and p13[5] < p7[5], "rows go downwards")
    assertEq(p7[5] - p13[5], p1[5] - p7[5], "even row spacing")
    assertEq(Bar.grid.rows, 3)
    assertEq(Bar.grid.cols, 6)
    ns.db.targeting.bar.max = 6
  end)
  it("vertical orientation fills columns", function()
    ns.db.targeting.bar.orientation = "VERTICAL"
    ns.db.targeting.bar.perRow = 3
    ns.db.targeting.bar.max = 24
    changed({ "V1", "V2", "V3", "V4" })
    local p1, p4 = UltimateTargetBarButton1.point, UltimateTargetBarButton4.point
    assertEq(p4[5], p1[5], "4th starts the 2nd column at the top")
    assertTrue(p4[4] > p1[4])
    ns.db.targeting.bar.orientation = "HORIZONTAL"
    ns.db.targeting.bar.perRow = 6
    ns.db.targeting.bar.max = 6
  end)
  it("keeps its title inside the panel even when locked", function()
    ns.db.targeting.bar.locked = true
    ns:Fire("ULT_SETTING_CHANGED", "targeting.bar.locked")
    assertTrue(Bar.title:IsShown())
    assertEq(Bar.title:GetText(), ns.L.TARGET_BAR_TITLE)
    ns.db.targeting.bar.locked = false
  end)
end)
