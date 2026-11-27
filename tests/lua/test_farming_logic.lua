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
