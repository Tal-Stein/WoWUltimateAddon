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
