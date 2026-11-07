local ns = __ns

-- A character set up by the first version: guild/whispers taken out of General, a Raid tab.
local cfg, calls, popups = {}, {}, {}
cfg[1] = { name = "General", shown = true, docked = 1, groups = { "SAY", "CHANNEL" } }
cfg[2] = { name = "Combat Log", shown = true, docked = 2, groups = {} }
cfg[3] = { name = "Focused", shown = true, docked = 3, groups = { "WHISPER", "GUILD", "RAID" } }
cfg[4] = { name = "Raid", shown = true, docked = 4, groups = { "RAID" } }
for i = 5, 10 do cfg[i] = { name = "", shown = false, docked = nil, groups = {} } end
local function record(...) calls[#calls + 1] = table.concat({ ... }, ",") end
GetChatWindowInfo = function(id) local w = cfg[id]; return w.name, 14, 0, 0, 0, 0.25, w.shown, false, w.docked, false end
GetChatWindowMessages = function(id) return unpack(cfg[id].groups) end
SetChatWindowName = function(id, n) record("name", id, n); cfg[id].name = n end
SetChatWindowShown = function(id, v) record("shown", id, tostring(v)); cfg[id].shown = v end
SetChatWindowDocked = function(id, v) record("docked", id, tostring(v)); cfg[id].docked = v end
AddChatWindowMessages = function(id, g) record("add", id, g); table.insert(cfg[id].groups, g) end
RemoveChatWindowMessages = function(id, g)
  record("remove", id, g)
  for i = #cfg[id].groups, 1, -1 do if cfg[id].groups[i] == g then table.remove(cfg[id].groups, i) end end
end
C_ChatInfo = { GetNumReservedChatWindows = function() return 2 end }
Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }
ChatTypeGroup = { SAY = {}, WHISPER = {}, BN_WHISPER = {}, PARTY = {}, PARTY_LEADER = {}, RAID = {},
  GUILD = {}, OFFICER = {}, CHANNEL = {} }
ChatTypeInfo = {}
StaticPopup_Show = function(name) popups[#popups + 1] = name end

__boot(nil, {
  focusedChat = { removeFromGeneral = true, copyHistory = true,
    categories = { raid = { focused = true, tab = true } } },
  focusedChatState = { ownedNames = { Focused = true, Raid = true },
    removedFromGeneral = { GUILD = true, WHISPER = true, RAID = true }, pendingHistory = {} },
})

local function has(list, item) for _, v in ipairs(list) do if v == item then return true end end return false end

describe("Focused Chat upgrade to additive tabs", function()
  it("turns raid off for characters set up with the old default", function()
    assertFalse(ns.db.focusedChat.categories.raid.focused)
  end)
  it("at login gives General back what the old version took, closes the Raid tab, asks to reload", function()
    __fire("PLAYER_ENTERING_WORLD")
    __advance(3)
    assertTrue(has(calls, "add,1,GUILD") and has(calls, "add,1,WHISPER") and has(calls, "add,1,RAID"),
      table.concat(calls, " | "))
    assertTrue(has(calls, "shown,4,false"), "Raid tab closed")
    assertTrue(has(calls, "remove,3,RAID"), "raid leaves the Focused tab")
    assertEq(UltimateCharDB.focusedChatState.removedFromGeneral, {})
    assertEq(popups[#popups], "ULTIMATE_CHAT_RELOAD")
  end)
  it("only once", function()
    calls, popups = {}, {}
    __fire("PLAYER_ENTERING_WORLD")
    __advance(3)
    assertEq(calls, {})
    assertEq(popups, {})
  end)
end)
