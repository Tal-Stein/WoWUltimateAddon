local ns = __ns

__boot(nil, {})

local function load(account, char)
  UltimateDB, UltimateCharDB = account, char
  ns.DB:Load()
end

describe("Settings profile", function()
  it("a new install shares one account-wide profile", function()
    load(nil, nil)
    assertEq(ns.global.scope, "account")
    assertTrue(ns.db == UltimateDB.profile)
    assertEq(ns.db.core.scanInterval, 0.5, "defaults filled")
  end)
  it("a character that used per-character settings moves to account-wide, keeping its settings", function()
    load({ scope = "char" }, { core = { scanInterval = 1.2 }, targeting = { bar = { perRow = 3 } },
      focusedChatState = { ownedNames = { Focused = true } } })
    assertEq(ns.global.scope, "account")
    assertTrue(ns.db == UltimateDB.profile)
    assertEq(ns.db.core.scanInterval, 1.2)
    assertEq(ns.db.targeting.bar.perRow, 3)
    assertNil(ns.db.focusedChatState, "chat-window state stays with the character")
    assertTrue(UltimateCharDB.focusedChatState.ownedNames.Focused)
  end)
  it("an existing account-wide profile is kept, not overwritten", function()
    load({ scope = "char", profile = { core = { scanInterval = 0.9 } } }, { core = { scanInterval = 1.5 } })
    assertEq(ns.global.scope, "account")
    assertEq(ns.db.core.scanInterval, 0.9)
  end)
  it("choosing per-character after the switch sticks", function()
    load({ scope = "char", scopeVersion = 2 }, { core = { scanInterval = 1.5 } })
    assertEq(ns.global.scope, "char")
    assertTrue(ns.db == UltimateCharDB)
  end)
end)
