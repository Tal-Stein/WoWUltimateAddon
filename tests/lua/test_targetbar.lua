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
end)

describe("TargetBar look and right-click menu", function()
  local L = ns.L
  it("is frameless like the quest item bar", function()
    assertNil(Bar.frame.template, "no backdrop template")
  end)
  it("shows its title only while unlocked", function()
    ns.db.targeting.bar.locked = true
    ns:Fire("ULT_SETTING_CHANGED", "targeting.bar.locked")
    assertFalse(Bar.handle:IsShown())
    ns.db.targeting.bar.locked = false
    ns:Fire("ULT_SETTING_CHANGED", "targeting.bar.locked")
    assertTrue(Bar.handle:IsShown())
  end)
  it("right-click never targets", function()
    local b = UltimateTargetBarButton1
    assertEq(b:GetAttribute("type2"), "macro")
    assertEq(b:GetAttribute("macrotext2"), "")
  end)
  it("right-click on a button opens the menu once, with the mob's own entry", function()
    changed({ "Kobold" })
    __menu = nil
    local b = UltimateTargetBarButton1
    b:GetScript("OnClick")(b, "RightButton", true)
    assertNil(__menu, "nothing on the down stroke")
    b:GetScript("OnClick")(b, "RightButton", false)
    assertTrue(__menu ~= nil and __menu.owner == b)
    assertEq(__menu.root.entries[1].text, L.TARGET_BAR_TITLE)
    local never = __menuEntry(string.format(L.TARGET_MENU_NEVER, "Kobold"))
    assertTrue(never ~= nil)
    never.a()
    assertTrue(ns.db.questTargeting.filters.exclude.Kobold)
    ns.db.questTargeting.filters.exclude.Kobold = nil
  end)
  it("the title and the empty message open the menu too", function()
    __menu = nil
    Bar.handle:GetScript("OnMouseUp")(Bar.handle, "RightButton")
    assertTrue(__menu ~= nil)
    assertNil(__menuEntry(string.format(L.TARGET_MENU_NEVER, "Kobold")))
    __menu = nil
    Bar.emptyArea:GetScript("OnMouseUp")(Bar.emptyArea, "RightButton")
    assertTrue(__menu ~= nil)
  end)
  it("offers lock, orientation, hide and settings", function()
    Bar.ShowMenu(Bar.handle)
    local lock = __menuEntry(L.LOCK_BAR)
    lock.b()
    assertTrue(ns.db.targeting.bar.locked)
    ns.db.targeting.bar.locked = false
    local vertical = __menuEntry(L.VERTICAL)
    vertical.b(vertical.c)
    assertEq(ns.db.targeting.bar.orientation, "VERTICAL")
    ns.db.targeting.bar.orientation = "HORIZONTAL"
    local opened = false
    ns.OpenSettings = function() opened = true end
    __menuEntry(L.OPEN_SETTINGS).a()
    assertTrue(opened)
    __inCombat = true
    __menuEntry(L.TARGET_MENU_HIDE).a()
    assertFalse(ns.db.targeting.bar.enabled)
    __inCombat = false
    ns.Combat:Flush()
    assertFalse(UltimateTargetBar:IsShown())
    ns.db.targeting.bar.enabled = true
    ns:Fire("ULT_SETTING_CHANGED", "targeting.bar.enabled")
  end)
end)

describe("TargetBar portraits", function()
  local UI = ns.UI
  local portraits = {}
  SetPortraitTexture = function(tex, unit) portraits[#portraits + 1] = { tex = tex, unit = unit } end
  local function withIcons()
    for _, b in ipairs(Bar.buttons) do
      b.icon = b.icon or b:CreateTexture()
    end
  end
  local function show(c)
    ns:Fire("ULT_TARGETS_CHANGED", { c.name }, { [c.name] = c })
  end
  it("shows the mob's own portrait from its nameplate", function()
    withIcons()
    portraits = {}
    show({ name = "Kobold", level = 5, count = 1, kind = "quest", mobs = { { unit = "nameplate4", classification = "normal" } } })
    local b = UltimateTargetBarButton1
    assertEq(#portraits >= 1 and portraits[#portraits].unit, "nameplate4")
    assertTrue(portraits[#portraits].tex == b.icon)
    assertTrue(b.badge:IsShown(), "small quest badge in the corner")
    assertEq(b.badge.texture, UI.ICON_QUEST)
  end)
  it("rares get the rare badge", function()
    show({ name = "Mor'Ladim", level = 35, count = 1, kind = "rare", mobs = { { unit = "nameplate2", classification = "rareelite" } } })
    assertEq(UltimateTargetBarButton1.badge.texture, UI.ICON_RARE)
  end)
  it("falls back to the plain icon without a unit, or with portraits off", function()
    portraits = {}
    show({ name = "Ghost", level = 5, count = 1, kind = "quest", mobs = {} })
    assertEq(#portraits, 0)
    assertEq(UltimateTargetBarButton1.icon.texture, UI.ICON_QUEST)
    assertFalse(UltimateTargetBarButton1.badge:IsShown())
    ns.db.targeting.bar.portraits = false
    show({ name = "Kobold", level = 5, count = 1, kind = "quest", mobs = { { unit = "nameplate4" } } })
    assertEq(#portraits, 0)
    assertEq(UltimateTargetBarButton1.icon.texture, UI.ICON_QUEST)
    ns.db.targeting.bar.portraits = true
  end)
end)

describe("UltimateTargetBarButton click handler", function()
  it("a mouse click reaches the secure action, not the flyout handler", function()
    for i = 1, 4 do
      assertEq(_G["UltimateTargetBarButton" .. i].clickHandler, "secure", "SecureActionButtonTemplate must be applied last")
    end
  end)
end)
