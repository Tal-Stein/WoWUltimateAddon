local ns = __ns
local L = ns.L

UnitLevel = function(unit) if unit == "player" then return 10 end end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
GetCVarBool = function() return true end
Minimap = CreateFrame("Frame", "Minimap", UIParent)
local opened = 0
local tooltipLines = {}
GameTooltip = CreateFrame("Frame", "GameTooltip", UIParent)
function GameTooltip:SetText(t) tooltipLines = { t } end
function GameTooltip:AddLine(t) tooltipLines[#tooltipLines + 1] = t end
function GameTooltip:AddDoubleLine(a, b) tooltipLines[#tooltipLines + 1] = a .. " " .. b end

__boot(nil, {})
ns.OpenSettings = function() opened = opened + 1 end

local TL = ns.TargetListModule
local QI = ns.QuestIndex

local function seed()
  QI.quests = {
    [100] = { questID = 100, title = "Kobold Camp", logIndex = 1 },
    [200] = { questID = 200, title = "Wolves", logIndex = 3 },
  }
  local vermin = { name = "Kobold Vermin", npcIds = { [40] = true }, quests = { { questID = 100, title = "Kobold Camp",
    objIndex = 1, text = "Kobold Vermin slain: 4/10", have = 4, need = 10 } } }
  local wolf = { name = "Gray Wolf", npcIds = { [50] = true }, quests = { { questID = 200, title = "Wolves",
    objIndex = 1, text = "Gray Wolf slain: 0/5", have = 0, need = 5 } } }
  QI.byNpc = { [40] = vermin, [50] = wolf }
  QI.byName = { ["Kobold Vermin"] = vermin, ["Gray Wolf"] = wolf }
  ns:Fire("ULT_QUEST_INDEX_CHANGED")
end

local function shownRows()
  local out = {}
  for _, r in ipairs(TL.rows) do
    if r:IsShown() then out[#out + 1] = { kind = r.kind, text = r.label:GetText() } end
  end
  return out
end

describe("Target list panel", function()
  it("is an enabled-by-default module with a visible panel", function()
    assertTrue(ns.Modules:IsEnabled("targetList"))
    assertTrue(TL.frame:IsShown(), "panel shown even before anything is found")
    assertEq(TL.title:GetText(), L.TARGET_LIST_TITLE)
  end)
  it("says so when there is nothing to look for", function()
    QI.byNpc, QI.byName, QI.quests = {}, {}, {}
    ns:Fire("ULT_QUEST_INDEX_CHANGED")
    assertTrue(TL.empty:IsShown())
    assertEq(#shownRows(), 0)
  end)
  it("lists quest headers and mob rows with progress", function()
    seed()
    assertFalse(TL.empty:IsShown())
    local rows = shownRows()
    assertEq(#rows, 4)
    assertEq(rows[1], { kind = "quest", text = "Kobold Camp" })
    assertEq(rows[2], { kind = "mob", text = "Kobold Vermin" })
    assertEq(TL.rows[2].progress:GetText(), "4/10")
    assertEq(TL.rows[2].npcId, 40, "portrait uses the NPC id")
    assertEq(rows[3], { kind = "quest", text = "Wolves" })
  end)
  it("highlights mobs in view and counts them in the header", function()
    seed()
    ns:Fire("ULT_TARGETS_CHANGED", { "Gray Wolf" }, { ["Gray Wolf"] = { name = "Gray Wolf" } })
    local wolfRow = TL.rows[4]
    assertEq(wolfRow.label:GetText(), "Gray Wolf")
    assertTrue(wolfRow.nearbyGlow:IsShown())
    assertFalse(TL.rows[2].nearbyGlow:IsShown())
    assertEq(TL.count:GetText(), string.format(L.TARGET_LIST_COUNT, 1, 2))
    ns:Fire("ULT_TARGETS_CHANGED", {}, {})
    assertFalse(wolfRow.nearbyGlow:IsShown())
  end)
  it("collapses and expands, also in combat, and remembers it", function()
    seed()
    __inCombat = true
    TL:Toggle()
    assertTrue(ns.db.targetList.collapsed)
    assertFalse(TL.body:IsShown())
    TL:Toggle()
    __inCombat = false
    assertFalse(ns.db.targetList.collapsed)
    assertTrue(TL.body:IsShown())
  end)
  it("caps the rows and says how many more there are", function()
    seed()
    ns.db.targetList.maxRows = 2
    ns:Fire("ULT_SETTING_CHANGED", "targetList.maxRows")
    assertEq(#shownRows(), 2)
    assertTrue(TL.more:IsShown())
    assertEq(TL.more:GetText(), string.format(L.TARGET_LIST_MORE, 2))
    ns.db.targetList.maxRows = 20
    ns:Fire("ULT_SETTING_CHANGED", "targetList.maxRows")
    assertFalse(TL.more:IsShown())
  end)
  it("can show only mobs in view", function()
    seed()
    ns.db.targetList.nearbyOnly = true
    ns:Fire("ULT_TARGETS_CHANGED", { "Gray Wolf" }, { ["Gray Wolf"] = { name = "Gray Wolf" } })
    local rows = shownRows()
    assertEq(#rows, 2)
    assertEq(rows[2].text, "Gray Wolf")
    ns.db.targetList.nearbyOnly = false
  end)
  it("hides when the feature is turned off", function()
    ns.Modules:SetEnabled("targetList", false)
    assertFalse(TL.frame:IsShown())
    ns.Modules:SetEnabled("targetList", true)
    assertTrue(TL.frame:IsShown())
  end)
end)

describe("Minimap button", function()
  local MB = ns.MinimapButton
  it("sits on the minimap", function()
    assertTrue(MB.button ~= nil)
    assertTrue(MB.button:GetParent() == Minimap)
    assertTrue(MB.button:IsShown())
  end)
  it("left-click toggles the target list, right-click opens settings", function()
    local before = ns.db.targetList.collapsed
    MB.button:GetScript("OnClick")(MB.button, "LeftButton")
    assertEq(ns.db.targetList.collapsed, not before)
    MB.button:GetScript("OnClick")(MB.button, "LeftButton")
    MB.button:GetScript("OnClick")(MB.button, "RightButton")
    assertEq(opened, 1)
  end)
  it("left-click opens settings when the target list is off", function()
    ns.Modules:SetEnabled("targetList", false)
    MB.button:GetScript("OnClick")(MB.button, "LeftButton")
    assertEq(opened, 2)
    ns.Modules:SetEnabled("targetList", true)
  end)
  it("tooltip shows the counts", function()
    seed()
    ns:Fire("ULT_TARGETS_CHANGED", { "Gray Wolf" }, { ["Gray Wolf"] = { name = "Gray Wolf" } })
    MB.button:GetScript("OnEnter")(MB.button)
    assertEq(tooltipLines[1], L.ADDON_TITLE)
    assertEq(tooltipLines[2], string.format(L.TARGET_LIST_COUNT, 1, 2))
  end)
  it("places itself by angle and can be hidden", function()
    ns.db.core.minimap.angle = 90
    MB:Place()
    local p = MB.button.point
    assertEq(p[1], "CENTER")
    assertTrue(math.abs(p[4]) < 0.001, "x = 0 at 90 degrees")
    assertTrue(p[5] > 0, "y above center")
    ns.db.core.minimap.hide = true
    ns:Fire("ULT_SETTING_CHANGED", "core.minimap.hide")
    assertFalse(MB.button:IsShown())
    ns.db.core.minimap.hide = false
    ns:Fire("ULT_SETTING_CHANGED", "core.minimap.hide")
    assertTrue(MB.button:IsShown())
  end)
end)
