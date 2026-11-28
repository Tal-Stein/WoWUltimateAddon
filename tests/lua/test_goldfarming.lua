local ns = __ns

-- Eastern Kingdoms (1415) with Elwynn (1429) and Westfall (1436); a herbalist at 75.
Enum = Enum or {}
Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3 }
local MAPS = {
  [1415] = { mapID = 1415, name = "Eastern Kingdoms", mapType = 2 },
  [1429] = { mapID = 1429, name = "Elwynn Forest", mapType = 3, parentMapID = 1415 },
  [1436] = { mapID = 1436, name = "Westfall", mapType = 3, parentMapID = 1415 },
}
local RECTS = { [1429] = { 0.4, 0.5, 0.7, 0.8 }, [1436] = { 0.3, 0.4, 0.7, 0.8 } }
C_Map = {
  GetMapInfo = function(id) return MAPS[id] end,
  GetMapChildrenInfo = function(id) if id == 1415 then return { MAPS[1429], MAPS[1436] } end return {} end,
  GetMapRectOnMap = function(id) local r = RECTS[id]; if r then return r[1], r[2], r[3], r[4] end end,
  GetMapInfoAtPosition = function(_, x, y)
    for id, r in pairs(RECTS) do if x >= r[1] and x <= r[2] and y >= r[3] and y <= r[4] then return MAPS[id] end end
  end,
  GetMapHighlightInfoAtPosition = function(_, x, y)
    local m = C_Map.GetMapInfoAtPosition(nil, x, y)
    if m then return 1000 + m.mapID, nil, 1, 1, 0.1, 0.1, x - 0.05, y - 0.05 end
  end,
}
local skillRank = 75
C_SkillInfo = { GetSkillLineInfoByID = function(id)
  if id == 182 then return { rank = skillRank } end
end }
ns.GatherNodes = {
  ["Peacebloom"] = { prof = "herbalism", skill = 1, item = 2447 },
  ["Briarthorn"] = { prof = "herbalism", skill = 70, item = 2450 },
  ["Copper Vein"] = { prof = "mining", skill = 1, item = 2770 },
}
local PRICES = { [2447] = 10, [2450] = 60 }
Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(_, id) return PRICES[id] end,
  GetAuctionAgeByItemID = function() return 1 end,
  RegisterForDBUpdate = function(_, fn) Auctionator.__update = fn end,
} } }
local tooltipPost
Enum.TooltipDataType = { Unit = 2 }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) if kind == 2 then tooltipPost = fn end end }
local menuMods = {}
Menu = { ModifyMenu = function(tag, fn) menuMods[tag] = fn end }

__boot(nil, {})
ns.db.farming.lens = "gathering" -- the gathering lens first; the mobs lens has its own tests below
local G = ns.GoldFarming
local FS = ns.FarmSources
FS.Zones = function()
  return { [1429] = { ["Peacebloom"] = 40, ["Copper Vein"] = 9 }, [1436] = { ["Briarthorn"] = 20 } }
end
FS.Spawns = function(mapID)
  if mapID == 1436 then
    return { { name = "Briarthorn", x = 0.5, y = 0.5 }, { name = "Copper Vein", x = 0.2, y = 0.2 } }
  end
  return {}
end

local MOBS = { zones = {}, values = {}, names = {} }
FS.Mobs = function() return MOBS end

local canvas = CreateFrame("Frame")
function canvas:GetWidth() return 1000 end
function canvas:GetHeight() return 700 end
local shownMap = 1415
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame")
WorldMapFrame.ScrollContainer = CreateFrame("Frame")
function WorldMapFrame:GetMapID() return shownMap end
function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:OnMapChanged() end
function WorldMapFrame:GetNormalizedCursorPosition() return 0.35, 0.75 end
WorldMapFrame:Show()
G.Attach()

local function open(mapID) shownMap = mapID; WorldMapFrame:OnMapChanged() end
local function shownHighlights()
  local list = {}
  for _, t in ipairs(G.highlights) do if t.shown then list[#list + 1] = t end end
  return list
end
local function shownPins()
  local list = {}
  for _, p in ipairs(G.pins) do if p.shown then list[#list + 1] = p end end
  return list
end
local function panelText()
  local lines = {}
  for _, fs in ipairs(G.panel.lines) do if fs.shown and fs.text ~= "" then lines[#lines + 1] = fs.text end end
  return table.concat(lines, "\n")
end

describe("Gold farming on the world map", function()
  it("is on by default", function()
    assertTrue(ns.Modules:IsEnabled("farming"))
  end)
  it("shades each zone you can gather in with its grade's color", function()
    open(1415)
    local hl = shownHighlights()
    assertEq(#hl, 2)
    local byTex = {}
    for _, t in ipairs(hl) do byTex[t.texture] = t end
    assertEq(byTex[2436].vertexColor, G.COLORS.excellent, "Westfall is worth more")
    assertEq(byTex[2429].vertexColor, G.COLORS.fair, "a third of Westfall's value")
  end)
  it("lists the best zones for you beside the map", function()
    local text = panelText()
    assertTrue(text:find("Herbalism 75", 1, true) ~= nil, text)
    assertTrue(text:find("Westfall", 1, true) < text:find("Elwynn Forest", 1, true), text)
  end)
  it("shows the zone under the cursor in detail", function()
    G.UpdateHover()
    local text = panelText()
    assertTrue(text:find("20 Briarthorn", 1, true) ~= nil, text)
  end)
  it("pins the nodes you can gather on a zone's map, and no shading", function()
    open(1436)
    assertEq(#shownHighlights(), 0)
    local pins = shownPins()
    assertEq(#pins, 1, "copper needs Mining")
    assertEq(pins[1].node, "Briarthorn")
  end)
  it("drops nodes above your skill", function()
    skillRank = 60
    __fire("SKILL_LINES_CHANGED")
    __advance(3, true)
    assertEq(#shownPins(), 0)
    skillRank = 75
    __fire("SKILL_LINES_CHANGED")
    __advance(3, true)
  end)
  it("doesn't work the scores out again just for browsing the map", function()
    local calls = 0
    local zones = FS.Zones
    FS.Zones = function() calls = calls + 1; return zones() end
    open(1415); open(1436); open(1415)
    assertEq(calls, 0)
    WorldMapFrame:GetScript("OnShow")()
    assertEq(calls, 0, "nor opening it: nothing changed")
    FS.Bump(true)
    assertEq(calls, 1, "a data change does")
    FS.Zones = zones
  end)
end)

describe("Gold farming toggle", function()
  it("adds a checkbox to the map's own filter menu", function()
    local entries = {}
    local root = {}
    function root:CreateDivider() end
    function root:CreateTitle(t) entries[#entries + 1] = { title = t } end
    function root:CreateCheckbox(t, get, set) entries[#entries + 1] = { text = t, get = get, set = set } end
    menuMods["MENU_WORLD_MAP_TRACKING"](nil, root)
    local box = entries[#entries]
    assertEq(box.text, ns.L.FARM_MAP_TOGGLE)
    assertTrue(box.get())
    box.set()
    assertFalse(ns.db.farming.showOnMap)
    open(1415)
    assertEq(#shownHighlights(), 0)
    assertFalse(G.panel.shown)
    box.set()
    assertTrue(ns.db.farming.showOnMap)
    assertEq(#shownHighlights(), 2)
  end)
end)

describe("Gold farming panel menu", function()
  it("offers hide and settings on right-click", function()
    G.ShowMenu(G.panel)
    assertTrue(__menuEntry(ns.L.FARM_MENU_HIDE) ~= nil)
    assertTrue(__menuEntry(ns.L.OPEN_SETTINGS) ~= nil)
    __menuEntry(ns.L.FARM_MENU_HIDE).a()
    assertFalse(ns.db.farming.showOnMap)
    ns.Menu.Set("farming.showOnMap", true)
  end)
end)

describe("Gold farming updates", function()
  it("regrades when Auctionator finishes a scan", function()
    PRICES[2447] = 1000
    Auctionator.__update()
    __advance(3, true)
    open(1415)
    local byTex = {}
    for _, t in ipairs(shownHighlights()) do byTex[t.texture] = t end
    assertEq(byTex[2429].vertexColor, G.COLORS.excellent)
  end)
end)

describe("Gold farming with your kills", function()
  it("lists a mob you've farmed with its gold per kill and per hour", function()
    MOBS.zones[1436] = { [116] = 30 }
    MOBS.values[116] = { perKill = 50, kills = 12 }
    MOBS.names[116] = "Defias Bandit"
    UltimateCharDB.farmPace = { sum = 300, n = 10 }
    G.Invalidate()
    open(1436)
    local text = panelText()
    assertTrue(text:find("Defias Bandit", 1, true) ~= nil, text)
    assertTrue(text:find("50c per kill", 1, true) ~= nil, text)
    assertTrue(text:find("12 kills", 1, true) ~= nil, text)
    assertTrue(text:find("60s 0c/hr", 1, true) ~= nil, text)
  end)
  it("adds the mob's value to its tooltip", function()
    UltimateDB.farmMobs = { [116] = { kills = 12, copper = 600, items = {}, skins = {}, maps = {} } }
    local lines = {}
    local tip = { AddLine = function(_, text) lines[#lines + 1] = text end }
    tooltipPost(tip, { guid = "Creature-0-1-0-12-116-00AB" })
    assertTrue(lines[1] and lines[1]:find("50c per kill", 1, true) ~= nil, tostring(lines[1]))
  end)
  it("adds nothing for a mob you haven't killed enough", function()
    local lines = {}
    tooltipPost({ AddLine = function(_, t) lines[#lines + 1] = t end }, { guid = "Creature-0-1-0-12-999-00AB" })
    assertEq(#lines, 0)
  end)
end)

describe("Gold farming views", function()
  -- You stand in Elwynn (center 0,0 in world yards); Westfall's center is 840 yards away.
  UnitPosition = function() return 0, 0, 0, 0 end
  CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
  C_Map.GetWorldPosFromMapPos = function(id)
    local c = ({ [1429] = { 0, 0 }, [1436] = { 840, 0 } })[id]
    if c then return 0, CreateVector2D(c[1], c[2]) end
  end
  C_Map.GetBestMapForUnit = function() return 1429 end
  C_Map.GetMapLevels = function(id) return ({ [1429] = { 1, 10 }, [1436] = { 10, 20 } })[id][1], ({ [1429] = { 1, 10 }, [1436] = { 10, 20 } })[id][2] end
  GetUnitSpeed = function() return 0, 7 end
  UnitLevel = function() return 5 end

  local function choose(view)
    G.ShowMenu(G.panel)
    __menuEntry(ns.L["FARM_VIEW_" .. view]).b()
  end

  it("offers the views in the panel's menu, best first by default", function()
    assertEq(ns.db.farming.view, "best")
    G.ShowMenu(G.panel)
    assertTrue(__menuEntry(ns.L.FARM_VIEW_near) ~= nil)
    assertTrue(__menuEntry(ns.L.FARM_VIEW_level) ~= nil)
  end)
  it("near me: shows how far each zone is", function()
    choose("near")
    assertEq(ns.db.farming.view, "near")
    open(1415)
    local text = panelText()
    assertTrue(text:find(ns.L.FARM_VIEW_near, 1, true) ~= nil, text)
    assertTrue(text:find("2 min", 1, true) ~= nil, text)
    assertTrue(text:find(ns.L.FARM_HERE, 1, true) ~= nil, text)
  end)
  it("levelling: only zones that suit your level, and only those are shaded", function()
    choose("level")
    open(1415)
    local text = panelText()
    assertTrue(text:find("Elwynn Forest", 1, true) ~= nil, text)
    assertTrue(text:find("Westfall", 1, true) == nil, text)
    assertEq(#shownHighlights(), 1)
    choose("best")
  end)
end)

describe("Gold goals", function()
  MoneyInputFrame_GetCopper = function(f) return f.copper end
  local money = 400000
  GetMoney = function() return money end
  local printed = {}
  local oldPrint = ns.Print
  ns.Print = function(_, msg) printed[#printed + 1] = msg end

  it("sets a goal from the panel's menu with the game's money box, in our own dialog", function()
    G.ShowMenu(G.panel)
    __menuEntry(ns.L.FARM_GOAL_SET).a()
    local f = G.goalFrame
    assertTrue(f.shown)
    assertNil(StaticPopupDialogs and StaticPopupDialogs.ULTIMATE_FARM_GOAL, "no shared popup")
    f.money.copper = 1000000
    f.ok:GetScript("OnClick")()
    assertEq(UltimateCharDB.farmGoal, 1000000)
    assertFalse(f.shown)
  end)
  it("turns down a goal you've already reached", function()
    G.AcceptGoal(300000)
    assertEq(UltimateCharDB.farmGoal, 1000000)
    assertEq(printed[#printed], ns.L.FARM_GOAL_ALREADY)
  end)
  it("shows what's left, and how long at your best timed mob", function()
    open(1436)
    local text = panelText()
    assertTrue(text:find("60g 0s 0c to go", 1, true) ~= nil, text)
    -- Defias Bandit: 50c per kill, 30 s a kill -> 60s/hr -> 600000c takes 100h
    assertTrue(text:find("100h", 1, true) ~= nil, text)
  end)
  it("celebrates and clears the goal once you have the gold", function()
    money = 1000000
    __fire("PLAYER_MONEY")
    assertNil(UltimateCharDB.farmGoal)
    assertEq(printed[#printed], ns.L.FARM_GOAL_REACHED)
  end)
  it("can be cleared from the menu", function()
    UltimateCharDB.farmGoal = 5000000
    G.ShowMenu(G.panel)
    __menuEntry(ns.L.FARM_GOAL_CLEAR).a()
    assertNil(UltimateCharDB.farmGoal)
    ns.Print = oldPrint
  end)
end)

describe("/ult farm", function()
  it("reports what Gold Farming reads, for checking it in game", function()
    local out = {}
    local oldPrint = ns.Print
    ns.Print = function(_, msg) out[#out + 1] = msg end
    UltimateDB.farmMobs = { [116] = { kills = 12, copper = 600, items = { [2589] = 3 }, skins = {}, maps = {} } }
    SlashCmdList.ULTIMATE("farm")
    ns.Print = oldPrint
    local text = table.concat(out, "\n")
    assertTrue(text:find("Herbalism 75", 1, true) ~= nil, text)
    assertTrue(text:find("Copper Vein", 1, true) ~= nil, text)
    assertTrue(text:find("12 kills", 1, true) ~= nil, text)
    assertTrue(text:find("Auctionator", 1, true) ~= nil, text)
  end)
end)

describe("Gold farming map button", function()
  it("sits on the map, and left-click turns gold farming off and on", function()
    local b = G.button
    assertTrue(b.shown)
    b:GetScript("OnClick")(b, "LeftButton")
    assertFalse(ns.db.farming.showOnMap)
    assertTrue(b.shown, "still there to turn it back on")
    assertTrue(b.icon.desaturated)
    b:GetScript("OnClick")(b, "LeftButton")
    assertTrue(ns.db.farming.showOnMap)
  end)
  it("right-click: on/off, lenses, views, settings", function()
    local b = G.button
    b:GetScript("OnClick")(b, "RightButton")
    assertTrue(__menuEntry(ns.L.FARM_MAP_TOGGLE) ~= nil)
    assertTrue(__menuEntry(ns.L.FARM_LENS_mobs) ~= nil)
    assertTrue(__menuEntry(ns.L.FARM_LENS_gathering) ~= nil)
    assertTrue(__menuEntry(ns.L.FARM_VIEW_near) ~= nil)
    assertTrue(__menuEntry(ns.L.OPEN_SETTINGS) ~= nil)
  end)
end)

describe("Mobs lens", function()
  local index = { [1436] = { [116] = 40, [117] = 12 }, [1429] = { [299] = 8 } }
  local levels = { [116] = { 10, 11 }, [117] = { 9, 10 }, [299] = { 5, 6 } }
  local ready = false
  FS.MobIndex = function() if ready then return index, levels end end
  FS.NpcName = function(id) return ({ [116] = "Defias Bandit", [117] = "Defias Thug", [299] = "Kobold Miner" })[id] end

  it("is the default for a new character", function()
    assertEq(G.def.defaults.lens, "mobs")
  end)
  it("says it's reading Questie while the mob list is being built", function()
    UnitLevel = function() return 10 end
    ns.Menu.Set("farming.lens", "mobs")
    ns.Menu.Set("farming.view", "best")
    open(1415)
    assertTrue(panelText():find(ns.L.FARM_BUILDING, 1, true) ~= nil, panelText())
  end)
  it("grades zones by the mobs at your level once it's ready", function()
    ready = true
    ns:Fire("ULT_FARM_DATA")
    local text = panelText()
    assertTrue(text:find(ns.L.FARM_LENS_mobs, 1, true) ~= nil, text)
    assertTrue(text:find("Westfall", 1, true) < text:find("Elwynn Forest", 1, true), text)
    local byTex = {}
    for _, t in ipairs(shownHighlights()) do byTex[t.texture] = t end
    assertEq(byTex[2436].vertexColor, G.COLORS.excellent)
  end)
  it("lists a zone's mobs with level, count and gold per kill once farmed", function()
    open(1436)
    local text = panelText()
    assertTrue(text:find("Defias Bandit (10-11)", 1, true) ~= nil, text)
    assertTrue(text:find("40 here", 1, true) ~= nil, text)
    assertTrue(text:find("50c per kill", 1, true) ~= nil, text)
    assertTrue(text:find("Defias Thug (9-10)", 1, true) ~= nil, text)
    assertTrue(text:find(ns.L.FARM_NOT_FARMED, 1, true) ~= nil, text)
  end)
  it("doesn't pin gathering nodes", function()
    assertEq(#shownPins(), 0)
  end)
  it("draws where each mob lives as areas, colored by its rating", function()
    FS.MobPoints = function(mapID, npcID)
      if npcID == 116 then return { { x = 0.4, y = 0.4 }, { x = 0.42, y = 0.41 } } end
      if npcID == 117 then return { { x = 0.6, y = 0.7 } } end
      return {}
    end
    G.Invalidate()
    open(1436)
    local shown, grades = 0, {}
    for _, a in ipairs(G.areas) do
      if a.shown then shown = shown + 1; grades[a.entry.npcID] = a.grade end
    end
    assertEq(shown, 2, "one area per group of nearby spawns")
    assertEq(grades[116], "excellent", "the mob you farm best")
    assertEq(grades[117], "fair", "no value: ranked by how many live here")
  end)
  it("shows a mob's level, numbers and rating when hovering its area", function()
    local b
    for _, x in ipairs(G.areas) do if x.shown and x.entry.npcID == 116 then b = x end end
    local lines = {}
    GameTooltip = GameTooltip or CreateFrame("Frame", "GameTooltip")
    local oldSet, oldAdd = GameTooltip.SetText, GameTooltip.AddLine
    GameTooltip.SetText = function(_, t) lines[#lines + 1] = t end
    GameTooltip.AddLine = function(_, t) lines[#lines + 1] = t end
    b:GetScript("OnEnter")(b)
    GameTooltip.SetText, GameTooltip.AddLine = oldSet, oldAdd
    local text = table.concat(lines, "\n")
    assertTrue(text:find("Defias Bandit (10-11)", 1, true) ~= nil, text)
    assertTrue(text:find("40 live here", 1, true) ~= nil, text)
  end)
  it("are hidden in the gathering lens", function()
    ns.Menu.Set("farming.lens", "gathering")
    open(1436)
    for _, a in ipairs(G.areas) do assertFalse(a.shown) end
    ns.Menu.Set("farming.lens", "mobs")
  end)
end)

describe("With OpenMap", function()
  it("keeps the shading and spots above OpenMap's stitched art", function()
    OpenMapAPI = { ArtTopLevel = function() return 3000 end }
    for _, f in ipairs({ G.overlay, G.pinLayer }) do
      f.level = 5
      f.SetFrameLevel = function(self, l) self.level = l end
      f.GetFrameLevel = function(self) return self.level end
    end
    G.Refresh()
    assertEq(G.overlay.level, 3001)
    assertEq(G.pinLayer.level, 3002)
    OpenMapAPI = nil
  end)
end)

describe("Map performance", function()
  it("doesn't redraw while nothing changed (OpenMap pans call this many times a second)", function()
    open(1436)
    local calls = 0
    local mp = FS.MobPoints
    FS.MobPoints = function(...) calls = calls + 1; return mp(...) end
    for _ = 1, 20 do WorldMapFrame:OnMapChanged() end
    assertEq(calls, 0)
    G.Invalidate()
    WorldMapFrame:OnMapChanged()
    assertTrue(calls > 0, "redraws after a change")
    FS.MobPoints = mp
  end)
end)

describe("Item prices arriving", function()
  it("don't redo the ratings while the map is open, only when it next opens", function()
    open(1436)
    local scores = (G.perf.score and G.perf.score.n) or 0
    FS.itemsWaiting = true
    __advance(5, true)
    assertEq((G.perf.score and G.perf.score.n) or 0, scores, "nothing while open")
    WorldMapFrame:GetScript("OnShow")()
    assertTrue(G.perf.score.n > scores, "taken in when the map opens")
    assertFalse(FS.itemsWaiting)
  end)
  it("/ult farm saves its diagnostics", function()
    local d = G.Diagnose()
    assertEq(UltimateDB.farmDiag, d)
    assertTrue(d.perf.refresh.n > 0)
  end)
end)

describe("Mob area ratings", function()
  it("rates a valued mob by its gold among the mobs around your level", function()
    assertEq(G.MobGrade({ price = 300, count = 2 }, { 10, 20, 30, 300 }, { 2 }), "excellent")
  end)
  it("rates a mob not valued yet no higher than fair, however many live there", function()
    assertEq(G.MobGrade({ count = 50 }, { 10, 20 }, { 1, 2, 50 }), "fair")
    assertEq(G.MobGrade({ count = 1 }, { 10, 20 }, { 1, 2, 50, 60 }), "poor")
  end)
end)
