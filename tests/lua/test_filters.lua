local ns = __ns
local Levels, Units, Filters = ns.Levels, ns.Units, ns.Filters

describe("Levels.bucket", function()
  it("matches Blizzard difficulty thresholds", function()
    assertEq(Levels.bucket(15, 10, 4), "impossible")
    assertEq(Levels.bucket(13, 10, 4), "hard")
    assertEq(Levels.bucket(12, 10, 4), "normal")
    assertEq(Levels.bucket(8, 10, 4), "normal")
    assertEq(Levels.bucket(5, 10, 4), "easy")
    assertEq(Levels.bucket(4, 10, 4), "trivial")
    assertEq(Levels.bucket(-1, 10, 4), "impossible")
  end)
  it("flags dangerous buckets", function()
    assertTrue(Levels.isDangerous("hard"))
    assertTrue(Levels.isDangerous("impossible"))
    assertFalse(Levels.isDangerous("normal"))
  end)
end)

describe("Units", function()
  it("parses NPC ids from creature GUIDs only", function()
    assertEq(Units.npcIdFromGuid("Creature-0-4372-0-1-1234-0000ABCD"), 1234)
    assertEq(Units.npcIdFromGuid("Vehicle-0-4372-0-1-77-0000ABCD"), 77)
    assertNil(Units.npcIdFromGuid("Player-1-0ABC"))
    assertNil(Units.npcIdFromGuid(nil))
  end)
  it("sanitises names for macros", function()
    assertEq(Units.sanitizeName("Bad;/Name|[x]"), "BadNamex")
    assertEq(Units.sanitizeName("  Kobold Miner \n"), "Kobold Miner")
    assertNil(Units.sanitizeName(";;"))
    assertNil(Units.sanitizeName(nil))
  end)
end)

describe("Filters.passes", function()
  local function opts(over)
    local o = { minOffset = -10, maxOffset = 3, hideGrey = true, includeElites = true,
      includeBosses = false, hideTapped = true, exclude = {} }
    for k, v in pairs(over or {}) do o[k] = v end
    return o
  end
  local function mob(over)
    local m = { name = "Kobold", level = 10, classification = "normal", dead = false, tapped = false,
      attackable = true, isPlayer = false }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
  end
  local function check(m, o, expectOk, expectReason)
    local ok, reason = Filters.passes(m, 10, 4, o)
    assertEq(ok, expectOk, "ok")
    assertEq(reason, expectReason, "reason")
  end

  it("passes a normal in-range mob", function() check(mob(), opts(), true, nil) end)
  it("rejects tapped when hideTapped", function()
    check(mob({ tapped = true }), opts(), false, "tapped")
    check(mob({ tapped = true }), opts({ hideTapped = false }), true, nil)
  end)
  it("rejects outside the level window", function()
    check(mob({ level = 20 }), opts(), false, "level")
    check(mob({ level = 13 }), opts(), true, nil)
    check(mob({ level = 5 }), opts({ minOffset = -2, hideGrey = false }), false, "level")
  end)
  it("rejects grey when hideGrey", function()
    check(mob({ level = 4 }), opts(), false, "grey")
    check(mob({ level = 4 }), opts({ hideGrey = false }), true, nil)
  end)
  it("handles elites", function()
    check(mob({ classification = "elite" }), opts({ includeElites = false }), false, "elite")
    check(mob({ classification = "rareelite" }), opts({ includeElites = false }), false, "elite")
    check(mob({ classification = "elite" }), opts(), true, nil)
  end)
  it("handles bosses", function()
    check(mob({ level = -1 }), opts(), false, "boss")
    check(mob({ classification = "worldboss", level = 30 }), opts(), false, "boss")
    check(mob({ level = -1 }), opts({ includeBosses = true }), true, nil)
    check(mob({ classification = "worldboss", level = 60 }), opts({ includeBosses = true }), true, nil)
  end)
  it("rejects excluded, dead, players and friendlies", function()
    check(mob(), opts({ exclude = { Kobold = true } }), false, "excluded")
    check(mob({ dead = true }), opts(), false, "dead")
    check(mob({ isPlayer = true }), opts(), false, "player")
    check(mob({ attackable = false }), opts(), false, "friendly")
  end)
end)
