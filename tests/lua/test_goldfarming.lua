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
local menuMods = {}
Menu = { ModifyMenu = function(tag, fn) menuMods[tag] = fn end }

__boot(nil, {})
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
    G.Refresh()
    assertEq(#shownPins(), 0)
    skillRank = 75
    G.Refresh()
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
    open(1415)
    local byTex = {}
    for _, t in ipairs(shownHighlights()) do byTex[t.texture] = t end
    assertEq(byTex[2429].vertexColor, G.COLORS.excellent)
  end)
end)
