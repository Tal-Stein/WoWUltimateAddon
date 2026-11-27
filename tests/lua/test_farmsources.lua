local ns = __ns

-- Questie's Forever database: two Copper Vein object IDs in Elwynn (area 12 -> map 1429), and
-- Peacebloom in Elwynn and Westfall (area 40 -> map 1436).
local OBJECTS = {
  [1731] = { [12] = { { 10, 20 }, { 30, 40 } } },
  [103713] = { [12] = { { 50, 60 } } },
  [1618] = { [12] = { { 1, 2 } }, [40] = { { 5, 5 }, { 6, 6 }, { 7, 7 } } },
}
local IDS = { ["Copper Vein"] = { 1731, 103713 }, ["Peacebloom"] = { 1618 } }
local lookups = 0
LibQuestieDB = {
  RequireContract = function() return true end,
  Object = {
    IdsByName = function(name) lookups = lookups + 1; return IDS[name] end,
    Get = function(id, field) if field == "spawns" then return OBJECTS[id] end end,
  },
}
local AREA = { [12] = 1429, [40] = 1436 }
QuestieLoader = { _modules = { ZoneDB = {
  GetUiMapIdByAreaId = function(_, a) return AREA[a] end,
  GetAreaIdByUiMapId = function(_, m) for a, id in pairs(AREA) do if id == m then return a end end end,
} } }
local versions = { Questie = "12.11.1", QuestieDB = "1.1.3" }
C_AddOns = {
  GetAddOnMetadata = function(a, k) if k == "Version" then return versions[a] end end,
  IsAddOnLoaded = function(a) return versions[a] ~= nil end,
}
C_SkillInfo = { GetSkillLineInfoByID = function(id)
  if id == 182 then return { skillID = 182, name = "Herbalism", rank = 120 } end
end }
local scans = { [2447] = 15 }
Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(_, id) return scans[id] end,
  GetAuctionAgeByItemID = function(_, id) if scans[id] then return 2 end end,
  RegisterForDBUpdate = function(_, fn) Auctionator.__update = fn end,
} } }
C_Item = { GetItemInfo = function(id)
  if id == 2770 then return "Copper Ore", nil, 1, 1, 1, "Trade Goods", "Metal", 20, "", 0, 5 end
end }

__boot(nil, {})
local FS = ns.FarmSources

describe("Your professions", function()
  it("reads gathering skill levels from the game", function()
    assertEq(FS.Skills(), { herbalism = 120 })
  end)
end)

describe("Node counts from Questie's Forever database", function()
  it("doesn't keep an empty result while Questie's data isn't ready", function()
    local saved = IDS
    IDS = {}
    assertEq(FS.Zones(), {})
    assertNil(UltimateDB.farmNodes)
    IDS = saved
  end)
  it("counts every object of a node's name, per map", function()
    local zones = FS.Zones()
    assertEq(zones[1429]["Copper Vein"], 3)
    assertEq(zones[1429]["Peacebloom"], 1)
    assertEq(zones[1436]["Peacebloom"], 3)
  end)
  it("keeps the counts, so the database is read once", function()
    local before = lookups
    FS.Zones()
    assertEq(lookups, before)
    assertEq(UltimateDB.farmNodes.zones[1436]["Peacebloom"], 3)
  end)
  it("reads them again when Questie updates", function()
    local before = lookups
    versions.QuestieDB = "1.1.4"
    FS.Zones()
    assertTrue(lookups > before, "re-read after an update")
  end)
  it("gives a map's node positions for its pins (0-1 coordinates)", function()
    local spawns = FS.Spawns(1436)
    assertEq(#spawns, 3)
    assertEq(spawns[1].name, "Peacebloom")
    assertEq(spawns[1].x, 0.05)
  end)
end)

describe("Node counts from GatherMate2", function()
  it("replaces Questie's counts for a map and node type GatherMate2 knows", function()
    local gm = {
      GetNodesForZone = function(_, mapID, nodeType)
        local t = {}
        if mapID == 1429 and nodeType == "Mining" then t[12345600] = 1; t[22345600] = 1 end
        return pairs(t)
      end,
      GetNameForNode = function(_, nodeType, id) if nodeType == "Mining" and id == 1 then return "Copper Vein" end end,
    }
    LibStub = function() return { GetAddon = function(_, name) if name == "GatherMate2" then return gm end end } end
    versions.GatherMate2 = "1.0"
    local zones = FS.Zones()
    assertEq(zones[1429]["Copper Vein"], 2, "GatherMate2's own count")
    assertEq(zones[1429]["Peacebloom"], 1, "herbs still from Questie")
    LibStub = nil
    versions.GatherMate2 = nil
  end)
end)

describe("Prices", function()
  it("uses your Auctionator scan, with its age", function()
    local p, source, age = FS.Price(2447)
    assertEq({ p, source, age }, { 15, "auction", 2 })
  end)
  it("falls back to the vendor price", function()
    local p, source = FS.Price(2770)
    assertEq({ p, source }, { 5, "vendor" })
  end)
  it("knows nothing for an item with neither", function()
    assertNil(FS.Price(999))
  end)
end)

describe("Data sources", function()
  it("reports what it's reading from", function()
    local s = FS.Status()
    assertEq(s.questie, "12.11.1")
    assertTrue(s.auctionator)
    assertFalse(s.gathermate)
  end)
end)
