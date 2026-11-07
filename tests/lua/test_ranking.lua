local ns = __ns
local Ranking = ns.Ranking

local function c(name, level, remaining, extra)
  local t = { name = name, level = level, remaining = remaining, firstSeen = 0, count = 1 }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

local function defaults(over)
  local o = { rareFirst = true, criteria = Ranking.defaultCriteria() }
  for k, v in pairs(over or {}) do o[k] = v end
  return o
end

describe("Ranking.rank", function()
  it("test_rank_default_order", function()
    local list = { c("Seven", 7, 3, { firstSeen = 1 }), c("FiveA", 5, 9, { firstSeen = 2 }), c("FiveB", 5, 1, { firstSeen = 3 }) }
    assertEq(Ranking.rank(list, defaults()), { "FiveB", "FiveA", "Seven" })
  end)
  it("test_rank_rare_first", function()
    local list = { c("Low", 2, 1), c("Rare", 30, 99, { isRare = true }) }
    assertEq(Ranking.rank(list, defaults())[1], "Rare")
    assertEq(Ranking.rank(list, defaults({ rareFirst = false }))[1], "Low")
  end)
  it("test_rank_pinned", function()
    local list = { c("Low", 2, 1), c("Pinned", 9, 9, { pinned = true }) }
    assertEq(Ranking.rank(list, defaults())[1], "Pinned")
  end)
  it("test_rank_criteria_reorder", function()
    local list = { c("A", 5, 9), c("B", 7, 1) }
    assertEq(Ranking.rank(list, defaults())[1], "A")
    local crit = {
      { id = "remaining", enabled = true },
      { id = "level", enabled = true },
    }
    assertEq(Ranking.rank(list, defaults({ criteria = crit }))[1], "B")
  end)
  it("level descending when desc is set", function()
    local list = { c("A", 5, 1), c("B", 7, 1) }
    local crit = { { id = "level", enabled = true, desc = true } }
    assertEq(Ranking.rank(list, defaults({ criteria = crit }))[1], "B")
  end)
  it("health and count criteria; missing values sort last", function()
    local list = { c("Full", 5, 1, { healthPct = 1 }), c("Hurt", 5, 1, { healthPct = 0.2 }), c("Unknown", 5, 1) }
    local crit = { { id = "health", enabled = true } }
    assertEq(Ranking.rank(list, defaults({ criteria = crit })), { "Hurt", "Full", "Unknown" })
    local list2 = { c("One", 5, 1, { count = 1 }), c("Many", 5, 1, { count = 4 }) }
    local crit2 = { { id = "count", enabled = true, desc = true } }
    assertEq(Ranking.rank(list2, defaults({ criteria = crit2 }))[1], "Many")
  end)
  it("disabled criteria are ignored and ties are stable by firstSeen", function()
    local list = { c("Second", 1, 1, { firstSeen = 2 }), c("First", 9, 9, { firstSeen = 1 }) }
    local crit = { { id = "level", enabled = false } }
    assertEq(Ranking.rank(list, defaults({ criteria = crit })), { "First", "Second" })
  end)
end)
