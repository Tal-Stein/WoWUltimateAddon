local ns = __ns
local W = ns.Watchlist

local function q(questID, title, have, need, objIndex)
  return { questID = questID, title = title, objIndex = objIndex or 1, text = "obj", have = have, need = need }
end

local quests = {
  [100] = { questID = 100, title = "Kobold Camp", logIndex = 2 },
  [200] = { questID = 200, title = "Wolves", logIndex = 1 },
}

local function entries()
  return {
    { name = "Kobold Vermin", npcIds = { [40] = true }, quests = { q(100, "Kobold Camp", 4, 10) } },
    { name = "Kobold Worker", npcIds = { [43] = true }, quests = { q(100, "Kobold Camp", 1, 8, 2) } },
    { name = "Gray Wolf", npcIds = { [50] = true }, quests = { q(200, "Wolves", 0, 5), q(100, "Kobold Camp", 1, 8, 2) } },
    { name = nil, npcIds = { [60] = true }, quests = { q(200, "Wolves", 0, 5) } },
  }
end

describe("Watchlist.build", function()
  it("groups mobs under their quests in quest log order", function()
    local groups = W.build(entries(), { quests = quests })
    assertEq(#groups, 2)
    assertEq(groups[1].questID, 200, "log order: Wolves first")
    assertEq(groups[2].title, "Kobold Camp")
    assertEq(#groups[2].mobs, 3, "a mob serving two quests appears under both")
    assertEq(#groups[1].mobs, 1, "unnamed entries are skipped")
  end)
  it("carries progress, npc id and DB level range", function()
    local groups = W.build(entries(), { quests = quests, levelOf = function(ids)
      if ids[40] then return 2, 3 end
    end })
    local vermin
    for _, m in ipairs(groups[2].mobs) do if m.name == "Kobold Vermin" then vermin = m end end
    assertEq(vermin.have, 4)
    assertEq(vermin.need, 10)
    assertEq(vermin.npcId, 40)
    assertEq(vermin.minLevel, 2)
    assertEq(vermin.maxLevel, 3)
  end)
  it("puts mobs in view first, then sorts by name, and counts them", function()
    local groups, total, nearby = W.build(entries(), { quests = quests, nearby = { ["Kobold Worker"] = true } })
    local names = {}
    for _, m in ipairs(groups[2].mobs) do names[#names + 1] = m.name end
    assertEq(names, { "Kobold Worker", "Gray Wolf", "Kobold Vermin" })
    assertTrue(groups[2].mobs[1].nearby)
    assertEq(groups[2].nearbyCount, 1)
    assertEq(total, 3, "unique mob names")
    assertEq(nearby, 1)
  end)
  it("puts pinned quests first and drops ignored ones", function()
    local groups = W.build(entries(), { quests = quests, pinned = { [100] = true } })
    assertEq(groups[1].questID, 100)
    assertTrue(groups[1].pinned)
    groups = W.build(entries(), { quests = quests, ignored = { [200] = true } })
    assertEq(#groups, 1)
    assertEq(groups[1].questID, 100)
  end)
  it("handles an empty index", function()
    local groups, total, nearby = W.build({}, { quests = {} })
    assertEq(#groups, 0)
    assertEq(total, 0)
    assertEq(nearby, 0)
  end)
end)
