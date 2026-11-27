local ns = __ns

UnitLevel = function() return 10 end
__boot(nil, {})
local FT = ns.FarmTargeting
local T = ns.Targeting

local function mob(name, npc, level, extra)
  local m = { name = name, npcId = npc, level = level, attackable = true, classification = "normal",
    guid = "Creature-0-1-0-12-" .. npc .. "-00", unit = "nameplate" .. npc }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

UltimateDB.farmMobs = {
  [116] = { kills = 10, copper = 500, items = {}, skins = {}, maps = {} }, -- 50c a kill
  [117] = { kills = 10, copper = 100, items = {}, skins = {}, maps = {} }, -- 10c a kill
}

describe("Farming mode candidates", function()
  local mobs = {
    mob("Defias Bandit", 116, 10), mob("Defias Thug", 117, 9), mob("Murloc", 118, 11),
    mob("Elite Ogre", 119, 10, { classification = "elite" }), mob("Rabbit", 120, 1),
    mob("Tagged", 121, 10, { tapped = true }), mob("Way Above", 122, 20),
  }
  local list = FT.Candidates(mobs)
  local by = {}
  for _, c in ipairs(list) do by[c.name] = c end

  it("offers non-elite hostile mobs around your level", function()
    assertTrue(by["Defias Bandit"] ~= nil)
    assertTrue(by["Murloc"] ~= nil, "not farmed yet, still a candidate")
    assertNil(by["Elite Ogre"]); assertNil(by["Rabbit"]); assertNil(by["Tagged"]); assertNil(by["Way Above"])
  end)
  it("rates them by the gold per kill you recorded", function()
    assertEq(by["Defias Bandit"].gold, 50)
    assertEq(by["Defias Bandit"].goldGrade, "excellent")
    assertEq(by["Defias Thug"].goldGrade, "fair")
    assertNil(by["Murloc"].gold)
    assertEq(by["Defias Bandit"].kind, "farm")
  end)
  it("adds the gold rating to the bar's tooltip", function()
    local lines = {}
    by["Defias Bandit"].tooltip({ AddLine = function(_, t) lines[#lines + 1] = t end })
    assertTrue(lines[1]:find(ns.L.FARM_GRADE_excellent, 1, true) ~= nil, lines[1])
    assertTrue(lines[1]:find("50c per kill", 1, true) ~= nil, lines[1])
  end)
  it("prompts to farm an unrated mob", function()
    assertEq((FT.TooltipLine(118)), ns.L.FARM_TIP_UNRATED)
  end)
end)

describe("Farming mode", function()
  it("is off by default", function()
    assertFalse(FT.Active())
    assertNil(T.providers.farm)
  end)
  it("adds the grinding mobs to the target bar, best gold first", function()
    FT.SetMode(true)
    assertTrue(T.providers.farm ~= nil)
    local criteria = FT.Criteria(ns.db.targeting.ranking)
    assertEq(criteria[2].id, "gold")
    local ranked = ns.Ranking.rank({
      { name = "Thug", gold = 10, level = 9, count = 1 }, { name = "Bandit", gold = 50, level = 10, count = 1 },
      { name = "Murloc", level = 8, count = 1 },
    }, { criteria = criteria })
    assertEq(ranked, { "Bandit", "Thug", "Murloc" })
  end)
  it("goes back to quests only when turned off", function()
    FT.SetMode(false)
    assertNil(T.providers.farm)
    assertEq(FT.Criteria(ns.db.targeting.ranking), ns.db.targeting.ranking)
  end)
  it("short gold for the bar", function()
    assertEq(FT.ShortMoney(3100), "31s")
    assertEq(FT.ShortMoney(12000), "1g 20s")
    assertEq(FT.ShortMoney(45), "45c")
    assertEq(FT.ShortMoney(20000), "2g")
  end)
end)
