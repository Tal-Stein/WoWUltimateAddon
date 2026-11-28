local FM = __ns.Farming

local NODES = {
  ["Peacebloom"] = { prof = "herbalism", skill = 1, item = 2447 },
  ["Briarthorn"] = { prof = "herbalism", skill = 70, item = 2450 },
  ["Copper Vein"] = { prof = "mining", skill = 1, item = 2770 },
  ["Demonsage"] = { prof = "herbalism" }, -- a Forever node: skill and item not known yet
}
local PRICES = { [2447] = { 10, "auction", 0 }, [2450] = { 60, "auction", 5 }, [2770] = { 25, "vendor" } }
local function price(id)
  local p = PRICES[id]
  if p then return p[1], p[2], p[3] end
end

describe("Who can gather a node", function()
  it("needs the profession", function()
    assertNil(FM.CanGather(NODES["Copper Vein"], { herbalism = 100 }))
  end)
  it("needs the skill", function()
    assertEq(FM.CanGather(NODES["Briarthorn"], { herbalism = 50 }), "skill")
    assertEq(FM.CanGather(NODES["Briarthorn"], { herbalism = 70 }), "yes")
  end)
  it("allows a node whose skill isn't known, flagged", function()
    assertEq(FM.CanGather(NODES["Demonsage"], { herbalism = 1 }), "unknown")
  end)
end)

describe("Zone values", function()
  local zones = {
    [1429] = { ["Peacebloom"] = 40, ["Copper Vein"] = 10 },          -- Elwynn
    [1436] = { ["Briarthorn"] = 20, ["Peacebloom"] = 5 },            -- Westfall
    [1433] = { ["Demonsage"] = 30 },                                   -- unknown herb only
    [1411] = { ["Copper Vein"] = 50 },                                 -- mining only
  }
  local skills = { herbalism = 75 }
  local list = FM.ScoreZones(zones, NODES, skills, price)
  local byMap = {}
  for _, z in ipairs(list) do byMap[z.mapID] = z end

  it("adds up what you can gather: nodes times the item's price", function()
    assertEq(byMap[1429].value, 400)
    assertEq(byMap[1436].value, 20 * 60 + 5 * 10)
  end)
  it("ranks the most valuable zone first", function()
    assertEq(list[1].mapID, 1436)
    assertEq(list[2].mapID, 1429)
  end)
  it("leaves out zones with nothing you can gather", function()
    assertNil(byMap[1411])
  end)
  it("keeps zones whose nodes have no price yet, without a value", function()
    assertEq(byMap[1433].value, 0)
    assertEq(byMap[1433].entries[1].status, "unknown")
    assertNil(byMap[1433].entries[1].price)
  end)
  it("lists each zone's nodes, best first, with price and where it came from", function()
    local e = byMap[1436].entries[1]
    assertEq(e.name, "Briarthorn")
    assertEq(e.count, 20)
    assertEq(e.price, 60)
    assertEq(e.source, "auction")
    assertEq(e.age, 5)
  end)
  it("weighs value by zone size when sizes are known", function()
    local area = function(id) return ({ [1429] = 1, [1436] = 10 })[id] end
    local l = FM.ScoreZones({ [1429] = zones[1429], [1436] = zones[1436] }, NODES, skills, price, area)
    assertEq(l[1].mapID, 1429)
  end)
end)

describe("Zone grades", function()
  local function zone(id, v) return { mapID = id, value = v, density = v } end
  it("grades the zones against each other", function()
    local list = { zone(1, 800), zone(2, 400), zone(3, 200), zone(4, 100) }
    FM.Grade(list)
    assertEq(list[1].grade, "excellent")
    assertEq(list[2].grade, "good")
    assertEq(list[3].grade, "fair")
    assertEq(list[4].grade, "poor")
  end)
  it("gives the only valued zone the top grade", function()
    local list = { zone(1, 50) }
    FM.Grade(list)
    assertEq(list[1].grade, "excellent")
  end)
  it("doesn't grade a zone with no value", function()
    local list = { zone(1, 50), zone(2, 0) }
    FM.Grade(list)
    assertNil(list[2].grade)
  end)
end)

describe("Mob value per kill", function()
  -- 10 kills: 2s 50c coin in all, 4 Linen Cloth (5c each at auction) and a grey (12c vendor).
  local stat = { kills = 10, copper = 250, items = { [2589] = 4, [3300] = 1 }, skinned = 5, skins = { [2318] = 5 } }
  local prices = { [2589] = 5, [3300] = 12, [2318] = 20 }
  local function p(id) return prices[id], "auction" end
  it("adds coin and the loot's value, per kill", function()
    local v = FM.MobValue(stat, p, {})
    assertEq(v.perKill, (250 + 4 * 5 + 12) / 10)
    assertEq(v.coin, 25)
    assertEq(v.kills, 10)
  end)
  it("counts skinning only for skinners", function()
    assertEq(FM.MobValue(stat, p, {}).skin, 0)
    local v = FM.MobValue(stat, p, { skinning = 100 })
    assertEq(v.skin, 5 * 20 / 10)
    assertEq(v.perKill, (250 + 4 * 5 + 12 + 100) / 10)
  end)
  it("knows nothing without kills", function()
    assertNil(FM.MobValue({ kills = 0, copper = 0, items = {} }, p, {}))
  end)
end)

describe("Gold per hour at your pace", function()
  it("is value per kill times your kills per hour", function()
    assertEq(FM.PerHour(30, { sum = 600, n = 20 }), 30 * 3600 / 30)
  end)
  it("needs enough timed kills", function()
    assertNil(FM.PerHour(30, { sum = 60, n = 2 }))
    assertNil(FM.PerHour(30, nil))
  end)
end)

describe("Zone values with mobs", function()
  local mobs = {
    zones = { [1436] = { [116] = 30, [117] = 10 }, [1411] = { [3098] = 50 } },
    values = { [116] = { perKill = 40, kills = 25 }, [3098] = { perKill = 2, kills = 3 } },
    names = { [116] = "Defias Bandit", [3098] = "Mottled Boar" },
  }
  local list = FM.ScoreZones({ [1436] = { ["Peacebloom"] = 5 } }, NODES, { herbalism = 75 }, price, nil, mobs)
  local byMap = {}
  for _, z in ipairs(list) do byMap[z.mapID] = z end
  it("adds every mob's spawns times its value per kill", function()
    assertEq(byMap[1436].value, 5 * 10 + 30 * 40)
  end)
  it("lists mobs beside nodes, best first", function()
    local e = byMap[1436].entries[1]
    assertEq(e.kind, "mob")
    assertEq(e.name, "Defias Bandit")
    assertEq(e.count, 30)
    assertEq(e.price, 40)
    assertEq(e.kills, 25)
  end)
  it("leaves out mobs with too few kills to trust", function()
    assertNil(byMap[1411])
  end)
end)

describe("Ranking views", function()
  local function zone(id, d, grade) return { mapID = id, value = d, density = d, grade = grade } end
  local list = { zone(1, 900, "excellent"), zone(2, 500, "good"), zone(3, 300, "fair"), zone(4, 100, "poor"), zone(5, 0) }
  local minutes = { [1] = 25, [2] = 4, [3] = 0, [4] = 8 }
  local levels = { [1] = { 30, 40 }, [2] = { 10, 20 }, [3] = { 1, 10 }, [4] = { 15, 25 } }
  local ctx = {
    minutes = function(id) return minutes[id] end,
    levels = function(id) local l = levels[id]; if l then return l[1], l[2] end end,
    level = 18,
  }
  local function ids(l) local t = {} for _, z in ipairs(l) do t[#t + 1] = z.mapID end return t end

  it("best: every graded zone, most valuable first", function()
    assertEq(ids(FM.View(list, "best", ctx)), { 1, 2, 3, 4 })
  end)
  it("near: graded zones within ten minutes, most valuable first, with the travel time", function()
    local l = FM.View(list, "near", ctx)
    assertEq(ids(l), { 2, 3, 4 })
    assertEq(l[1].minutes, 4)
  end)
  it("near: reaches further when little is close", function()
    minutes[2], minutes[4] = 15, 18
    assertEq(ids(FM.View(list, "near", ctx)), { 2, 3, 4 })
    minutes[2], minutes[4] = 4, 8
  end)
  it("near: knows nothing without your position", function()
    assertEq(ids(FM.View(list, "near", { minutes = function() end })), {})
  end)
  it("levelling: zones whose level range suits you", function()
    local l = FM.View(list, "level", ctx)
    assertEq(ids(l), { 2, 4 })
    assertEq({ l[1].minLevel, l[1].maxLevel }, { 10, 20 })
  end)
end)

describe("Gold goals", function()
  it("says how much is left", function()
    local g = FM.Goal(1000000, 376000)
    assertEq(g.left, 624000)
    assertFalse(g.reached)
    assertNil(g.hours)
  end)
  it("says how long it takes at a known gold per hour", function()
    assertEq(FM.Goal(1000000, 400000, 200000).hours, 3)
  end)
  it("is reached once you have the gold", function()
    local g = FM.Goal(1000000, 1000500)
    assertTrue(g.reached)
    assertEq(g.left, 0)
  end)
  it("formats hours and minutes", function()
    assertEq(FM.FormatHours(3), "3h")
    assertEq(FM.FormatHours(1.5), "1h 30m")
    assertEq(FM.FormatHours(0.25), "15m")
    assertEq(FM.FormatHours(0.001), "1m")
  end)
end)

describe("Mob zones", function()
  -- index: [mapID][npcID] = spawns; levels: [npcID] = { min, max }
  local index = {
    [1436] = { [116] = 40, [117] = 30, [500] = 10 },
    [1429] = { [299] = 20 },
    [1411] = { [3098] = 50 },
  }
  local levels = { [116] = { 10, 11 }, [117] = { 9, 10 }, [500] = { 30, 31 }, [299] = { 5, 6 }, [3098] = { 1, 2 } }
  local values = { [116] = { perKill = 40, kills = 25 } }
  local names = function(id) return ({ [116] = "Defias Bandit", [117] = "Defias Thug" })[id] or ("npc" .. id) end
  local list = FM.MobZones(index, levels, 10, values, names)
  local byMap = {}
  for _, z in ipairs(list) do byMap[z.mapID] = z end

  it("counts the mobs at your level that live in each zone", function()
    assertEq(byMap[1436].value, 70)
    assertEq(byMap[1429].value, 20, "level 5-6 still gives a level 10 experience")
  end)
  it("leaves out mobs far above or below you", function()
    assertNil(byMap[1411])
    for _, e in ipairs(byMap[1436].entries) do assertTrue(e.npcID ~= 500) end
  end)
  it("lists the mobs, the ones you've farmed first, with their levels and gold", function()
    local e = byMap[1436].entries[1]
    assertEq(e.kind, "mob")
    assertEq(e.name, "Defias Bandit")
    assertEq({ e.minLevel, e.maxLevel, e.count, e.price, e.kills }, { 10, 11, 40, 40, 25 })
    assertNil(byMap[1436].entries[2].price, "not farmed yet")
  end)
  it("grades zones by how many mobs at your level live there", function()
    assertEq(list[1].mapID, 1436)
    assertEq(list[1].grade, "excellent")
  end)

  describe("with gold values to rate against", function()
    -- A big sparse zone with a valuable mob, a dense zone of cheap mobs, one with nothing known.
    local idx = {
      [10] = { [1] = 6, [2] = 4 },   -- sparse: 10 mobs over a large area
      [20] = { [3] = 80 },           -- dense, cheap
      [30] = { [4] = 50 },           -- dense, no value known
      [40] = { [5] = 1, [3] = 5 },   -- a lone valuable spawn, otherwise cheap
    }
    local lv = { [1] = { 10, 10 }, [2] = { 10, 10 }, [3] = { 10, 10 }, [4] = { 10, 10 }, [5] = { 10, 10 } }
    local vals = { [1] = { perKill = 300, kills = 30 }, [3] = { perKill = 10, kills = 30 },
      [5] = { perKill = 900, kills = 30 } }
    local sizes = { [10] = 100, [20] = 1, [30] = 1, [40] = 1 }
    local yard = { 5, 10, 20, 50, 100, 200, 300, 400 }
    local zl = FM.MobZones(idx, lv, 10, vals, function(id) return "npc" .. id end,
      function(m) return sizes[m] end, yard)
    local by = {}
    for _, z in ipairs(zl) do by[z.mapID] = z end

    it("rates a zone by its best mob's gold, as its areas are rated", function()
      assertEq(by[10].grade, "excellent", "a sparse zone with a valuable mob isn't poor")
      assertEq(by[20].grade, "poor", "many cheap mobs")
      assertEq(by[10].best, 300)
    end)
    it("doesn't let a lone spawn rate the zone", function()
      assertEq(by[40].grade, "poor")
    end)
    it("rates zones of mobs not valued yet no higher than fair", function()
      assertEq(by[30].grade, "fair")
    end)
    it("lists valued zones best first", function()
      assertEq(zl[1].mapID, 10)
    end)
  end)
end)

describe("Mob areas from spawn points", function()
  it("groups nearby spawns into one area around them", function()
    local pts = { { x = 0.40, y = 0.40 }, { x = 0.42, y = 0.41 }, { x = 0.41, y = 0.43 }, { x = 0.80, y = 0.20 } }
    local areas = FM.Clusters(pts, 0.05)
    assertEq(#areas, 2)
    table.sort(areas, function(a, b) return a.n > b.n end)
    assertEq(areas[1].n, 3)
    assertTrue(math.abs(areas[1].x - 0.41) < 0.001 and math.abs(areas[1].y - 0.415) < 0.001)
    assertTrue(areas[1].rx >= 0.01 + 0.025 - 1e-9, "covers the spawns with room around them")
    assertEq(areas[2].n, 1)
    assertEq(areas[2].rx, 0.025, "a lone spawn gets a small area")
  end)
  it("joins spawns in a chain of neighbouring cells", function()
    local pts = {}
    for i = 0, 5 do pts[#pts + 1] = { x = 0.1 + i * 0.04, y = 0.5 } end
    assertEq(#FM.Clusters(pts, 0.05), 1)
  end)
  it("has nothing without spawns", function()
    assertEq(FM.Clusters({}, 0.05), {})
  end)
end)

describe("Values from ForeverDB", function()
  local prices = { [2589] = 10, [2318] = 20 }
  local function p(id) return prices[id] end
  local d = { coin = 7, kills = 16, drops = { 2589, 3000, 1019, 6600 }, skins = { 2318, 5000 } }
  it("is the average coin plus each drop's chance times its price", function()
    local v = FM.DataMobValue(d, p, {})
    assertEq(v.perKill, 7 + 10 * 0.3)
    assertEq(v.source, "forever")
    assertEq(v.dataKills, 16)
  end)
  it("counts skinning for skinners", function()
    assertEq(FM.DataMobValue(d, p, { skinning = 50 }).perKill, 7 + 3 + 10)
  end)
  it("keeps rare drops out of what a kill typically gives, and says what they add", function()
    -- a 2% green worth 500 adds 10 per kill on average, but almost no kill gives it
    local rare = { coin = 7, kills = 16, drops = { 2589, 3000, 9999, 200 } }
    local v = FM.DataMobValue(rare, function(id) return id == 9999 and 500 or prices[id] end, {})
    assertEq(v.perKill, 7 + 3)
    assertEq(v.rare, 10)
  end)
  it("is worth something with only rare drops known", function()
    local v = FM.DataMobValue({ drops = { 9999, 200 } }, function() return 500 end, {})
    assertEq(v.perKill, 0)
    assertEq(v.rare, 10)
  end)
  it("your own kills win once there are many of them", function()
    local data = FM.DataMobValue(d, p, {})
    assertEq(FM.PickValue({ perKill = 99, kills = 25, source = "yours" }, data).perKill, 99)
    assertEq(FM.PickValue({ perKill = 99, kills = 8, source = "yours" }, data).perKill, 10, "a few kills: ForeverDB")
    assertEq(FM.PickValue({ perKill = 99, kills = 8, source = "yours" }, nil).perKill, 99, "no data: yours")
    assertNil(FM.PickValue({ perKill = 99, kills = 2, source = "yours" }, nil))
  end)
end)

describe("Rating yardstick", function()
  it("is the 90th-percentile value, so one odd mob doesn't make every other one poor", function()
    local vals = {}
    for i = 1, 19 do vals[i] = 10 end
    vals[20] = 80 -- one mob seen once with a big coin drop
    assertEq(FM.Percentile(vals, 0.9), 10)
    assertEq(FM.RatioGrade(8, FM.Percentile(vals, 0.9)), "excellent")
  end)
  it("ignores coin averages from too few kills, keeping the drops", function()
    local d = { coin = 80, kills = 1, drops = { 2589, 1000 } }
    local v = FM.DataMobValue(d, function() return 10 end, {})
    assertEq(v.coin, 0)
    assertEq(v.perKill, 1)
  end)
end)

describe("Grades by rank", function()
  local sorted = { 1, 2, 3, 4, 5, 6, 7, 8 }
  it("grades by quarter of the ranking", function()
    assertEq(FM.RankGrade(8, sorted), "excellent")
    assertEq(FM.RankGrade(7, sorted), "excellent")
    assertEq(FM.RankGrade(5, sorted), "good")
    assertEq(FM.RankGrade(3, sorted), "fair")
    assertEq(FM.RankGrade(1, sorted), "poor")
    assertEq(FM.RankGrade(100, sorted), "excellent")
    assertEq(FM.RankGrade(0.5, sorted), "poor")
  end)
  it("isn't thrown off by one very valuable mob", function()
    assertEq(FM.RankGrade(7, { 5, 6, 7, 8, 9000 }), "good")
  end)
  it("knows nothing without others", function()
    assertNil(FM.RankGrade(5, {}))
  end)
end)
