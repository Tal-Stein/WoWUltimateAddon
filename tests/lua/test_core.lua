local ns = __ns

describe("Combat queue", function()
  it("test_combat_queue_defers_and_coalesces", function()
    local ran = {}
    __inCombat = true
    ns.Combat:Run("a", function() ran[#ran + 1] = "f1" end)
    ns.Combat:Run("b", function() ran[#ran + 1] = "g" end)
    ns.Combat:Run("a", function() ran[#ran + 1] = "f2" end)
    assertEq(#ran, 0, "nothing runs in combat")
    __inCombat = false
    __fire("PLAYER_REGEN_ENABLED")
    assertEq(ran, { "f2", "g" }, "last per key wins, insertion order kept")
    ns.Combat:Run("c", function() ran[#ran + 1] = "now" end)
    assertEq(ran[3], "now", "runs immediately out of combat")
    __fire("PLAYER_REGEN_ENABLED")
    assertEq(#ran, 3, "queue emptied after flush")
  end)
  it("reports pending work", function()
    __inCombat = true
    ns.Combat:Run("x", function() end)
    assertTrue(ns.Combat:IsPending("x"))
    __inCombat = false
    __fire("PLAYER_REGEN_ENABLED")
    assertFalse(ns.Combat:IsPending("x"))
  end)
end)

describe("Event bus", function()
  it("test_guarded_dispatch", function()
    local second = false
    ns:On("ULT_TEST", "one", function() error("boom") end)
    ns:On("ULT_TEST", "two", function(_, v) second = v end)
    ns:Fire("ULT_TEST", 42)
    assertEq(second, 42)
    assertTrue(ns.errorCount >= 1)
  end)
  it("Off removes only that owner", function()
    local hits = 0
    ns:On("ULT_T2", "a", function() hits = hits + 1 end)
    ns:On("ULT_T2", "b", function() hits = hits + 10 end)
    ns:Off("ULT_T2", "b")
    ns:Fire("ULT_T2")
    assertEq(hits, 1)
  end)
  it("registers WoW events on the frame and dispatches them", function()
    local got
    ns:On("PLAYER_TARGET_CHANGED", "t", function(event) got = event end)
    __fire("PLAYER_TARGET_CHANGED")
    assertEq(got, "PLAYER_TARGET_CHANGED")
  end)
end)

describe("Safe.read", function()
  it("test_safe_read_secret", function()
    local sentinel = {}
    __secret[sentinel] = true
    assertNil(ns.Safe.read(function() return sentinel end))
    assertNil(ns.Safe.read(function() error("x") end))
    assertEq(ns.Safe.read(function(a) return a + 1 end, 1), 2)
    assertTrue(ns.Safe.isSecret(sentinel))
    assertFalse(ns.Safe.isSecret(5))
  end)
end)

describe("DB and modules", function()
  local enables, disables = 0, 0
  ns.Modules:Register({ key = "alpha", name = "Alpha", defaults = { size = 3 },
    OnEnable = function() enables = enables + 1 end, OnDisable = function() disables = disables + 1 end })
  ns.Modules:Register({ key = "beta", name = "Beta", defaultEnabled = false, defaults = {},
    OnEnable = function() error("beta must stay off") end })
  __boot(nil, { alpha = { size = 9 } })

  it("test_db_merge_defaults", function()
    assertEq(ns.db.alpha.size, 9, "saved value kept")
    assertEq(ns.db.core.scanInterval, 0.5, "core default filled")
    assertEq(ns.global.scope, "char")
    assertTrue(ns.db == UltimateCharDB, "char scope uses per-character table")
  end)
  it("test_modules_enable_disable", function()
    assertEq(enables, 1, "enabled on login")
    assertFalse(ns.Modules:IsEnabled("beta"), "defaultEnabled=false stays off")
    ns.Modules:SetEnabled("alpha", false)
    ns.Modules:SetEnabled("alpha", false)
    assertEq(disables, 1, "OnDisable once")
    assertEq(ns.db.modules.alpha, false, "persisted")
    ns.Modules:SetEnabled("alpha", true)
    assertEq(enables, 2)
    local keys = {}
    for def in ns.Modules:Iterate() do if def.key == "alpha" or def.key == "beta" then keys[#keys + 1] = def.key end end
    assertEq(keys, { "alpha", "beta" }, "registration order")
  end)
end)

describe("Slash", function()
  it("routes subcommands to events", function()
    local scanned, reset = false, false
    ns:On("ULT_DEBUG_SCAN", "s", function() scanned = true end)
    ns:On("ULT_RESET_POSITIONS", "s", function() reset = true end)
    SlashCmdList.ULTIMATE("scan")
    SlashCmdList.ULTIMATE("reset")
    assertTrue(scanned and reset)
    SlashCmdList.ULTIMATE("debug")
    assertTrue(ns.db.core.debug)
  end)
end)
