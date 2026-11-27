local ns = __ns

-- Questie's Forever database: two Copper Vein object IDs in Elwynn (area 12 -> map 1429), and
-- Peacebloom in Elwynn and Westfall (area 40 -> map 1436).
local OBJECTS = {
  [1731] = { [12] = { { 10, 20 }, { 30, 40 } } },
  [103713] = { [12] = { { 50, 60 } } },
  [1618] = { [12] = { { 1, 2 }, { -1, -1 } }, [40] = { { 5, 5 }, { 6, 6 }, { 7, 7 } } },
}
local IDS = { ["Copper Vein"] = { 1731, 103713 }, ["Peacebloom"] = { 1618 } }
local lookups = 0
LibQuestieDB = {
  RequireContract = function() return true end,
  Object = {
    IdsByName = function(name) lookups = lookups + 1; return IDS[name] end,
    BuildNameIndexAsync = function() __asyncIndex = true end,
    Get = function(id, field) if field == "spawns" then return OBJECTS[id] end end,
  },
}
local NPCS = {
  [116] = { name = "Defias Bandit", minLevel = 10, maxLevel = 11, rank = 0, spawns = { [40] = { { 1, 1 }, { 2, 2 } } } },
  [100] = { name = "Gruff Swiftbite", minLevel = 12, maxLevel = 12, rank = 4, spawns = { [12] = { { 1, 1 } } } },
  [500] = { name = "Ogre", minLevel = 30, maxLevel = 31, rank = 0, spawns = { [40] = { { 3, 3 } } } },
}
NPCS[200] = { name = "Stormwind Guard", minLevel = 55, maxLevel = 55, rank = 0, friendlyToFaction = "A", spawns = { [12] = { { 1, 1 } } } }
NPCS[201] = { name = "Rabbit", minLevel = 1, maxLevel = 1, rank = 0, factionID = 188, spawns = { [12] = { { 1, 1 } } } }
NPCS[202] = { name = "Kobold Vermin", minLevel = 2, maxLevel = 3, rank = 0, spawns = { [12] = { { 1, 1 }, { 2, 2 }, { 3, 3 } } } }
NPCS[203] = { name = "Innkeeper", minLevel = 30, maxLevel = 30, rank = 0, npcFlags = 128, spawns = { [12] = { { 1, 1 } } } }
LibQuestieDB.Npc = {
  Get = function(id, field) local n = NPCS[id]; return n and n[field] end,
  GetAllIds = function() local ids = {} for id in pairs(NPCS) do ids[#ids + 1] = id end table.sort(ids) return ids end,
}
UnitFactionGroup = function() return "Alliance" end
UnitLevel = function() return 10 end
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

describe("Questie's name index", function()
  it("is built a little at a time from login, so the map never hangs building it", function()
    assertTrue(__asyncIndex)
  end)
end)

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
  it("are used only when Questie has none", function()
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
    C_Map = { GetMapChildrenInfo = function() return { { mapID = 1429 }, { mapID = 1436 } } end }
    assertEq(FS.Zones()[1429]["Copper Vein"], 3, "Questie's spawn points win")
    local savedIDs, savedCache = IDS, UltimateDB.farmNodes
    IDS, UltimateDB.farmNodes = {}, nil
    assertEq(FS.Zones(), { [1429] = { ["Copper Vein"] = 2 } })
    IDS, UltimateDB.farmNodes = savedIDs, savedCache
    LibStub = nil
    versions.GatherMate2 = nil
    C_Map = nil
  end)
end)

describe("Mobs you've killed", function()
  it("values each recorded mob and counts its spawns per map from Questie", function()
    UltimateDB.farmMobs = {
      [116] = { kills = 8, copper = 400, items = {}, skins = {}, maps = {} },
      [100] = { kills = 8, copper = 4000, items = {}, skins = {}, maps = {} },
      [500] = { kills = 8, copper = 4000, items = {}, skins = {}, maps = {} },
    }
    local mobs = FS.Mobs({})
    assertEq(mobs.zones[1436], { [116] = 2 })
    assertEq(mobs.values[116].perKill, 50)
    assertEq(mobs.names[116], "Defias Bandit")
  end)
  it("leaves out elites and rares, and mobs well above your level", function()
    local mobs = FS.Mobs({})
    assertNil(mobs.zones[1429])
    assertNil(mobs.values[500])
  end)
end)

describe("Which mobs live where", function()
  it("is built from Questie a few at a time, then kept", function()
    assertNil(FS.MobIndex(), "still building")
    __advance(1, true)
    local index, levels = FS.MobIndex()
    assertEq(index[1429][202], 3)
    assertEq(index[1436][116], 2)
    assertEq(levels[202], { 2, 3 })
    assertEq(UltimateDB.farmMobIndex.maps[1429][202], 3)
  end)
  it("leaves out friendly NPCs, critters, townsfolk and elites", function()
    local index = FS.MobIndex()
    assertNil(index[1429][200])
    assertNil(index[1429][201])
    assertNil(index[1429][203])
    assertNil(index[1429][100])
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
