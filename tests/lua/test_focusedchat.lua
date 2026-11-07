local ns = __ns
local L = ns.L

-- Chat client stubs: the saved chat-window configuration, plus chat frames with message history.
local cfg, calls, popups
local function resetConfig()
  cfg, calls, popups = {}, {}, {}
  cfg[1] = { name = "General", shown = true, docked = 1, groups = { "SAY", "GUILD", "WHISPER", "PARTY", "CHANNEL" } }
  cfg[2] = { name = "Combat Log", shown = true, docked = 2, groups = {} }
  for i = 3, 10 do cfg[i] = { name = "", shown = false, docked = nil, groups = {} } end
end
resetConfig()
local function record(...) calls[#calls + 1] = table.concat({ ... }, ",") end
GetChatWindowInfo = function(id)
  local w = cfg[id]
  return w.name, 14, 0, 0, 0, 0.25, w.shown, false, w.docked, false
end
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
ChatTypeGroup = {
  SAY = { "CHAT_MSG_SAY" }, YELL = { "CHAT_MSG_YELL" }, EMOTE = { "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" },
  WHISPER = { "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM" }, BN_WHISPER = { "CHAT_MSG_BN_WHISPER" },
  PARTY = { "CHAT_MSG_PARTY" }, PARTY_LEADER = { "CHAT_MSG_PARTY_LEADER" },
  RAID = { "CHAT_MSG_RAID" }, RAID_LEADER = { "CHAT_MSG_RAID_LEADER" }, RAID_WARNING = { "CHAT_MSG_RAID_WARNING" },
  GUILD = { "CHAT_MSG_GUILD" }, OFFICER = { "CHAT_MSG_OFFICER" }, CHANNEL = { "CHAT_MSG_CHANNEL" },
}
ChatTypeInfo = { SAY = { id = 1 }, GUILD = { id = 2 }, WHISPER = { id = 3 }, WHISPER_INFORM = { id = 4 },
  PARTY = { id = 5 }, CHANNEL = { id = 6 }, OFFICER = { id = 7 } }
StaticPopup_Show = function(name) popups[#popups + 1] = name end

-- Chat frames: ChatFrame1 has this session's lines; others start empty.
local function chatFrame(id)
  local f = CreateFrame("Frame", "ChatFrame" .. id, UIParent)
  f.lines = {}
  function f:GetNumMessages() return #self.lines end
  function f:GetMessageInfo(i) local l = self.lines[i]; return l.text, 1, 1, 1, l.typeID, nil, l.lineID end
  function f:AddMessage(text, r, g, b) self.lines[#self.lines + 1] = { text = text } end
  return f
end
for i = 1, 10 do chatFrame(i) end

__boot(nil, {})
local FC = ns.FocusedChatModule

local function has(list, item) for _, v in ipairs(list) do if v == item then return true end end return false end
local function state() return UltimateCharDB.focusedChatState end

describe("Focused Chat", function()
  it("is a module that does nothing until Apply", function()
    assertTrue(ns.Modules:IsEnabled("focusedChat"))
    assertEq(#calls, 0, "no chat changes at login")
  end)
  it("Apply writes the plan through Blizzard's chat-window functions and asks to reload", function()
    resetConfig()
    FC:Apply()
    assertTrue(has(calls, "name,3,Focused"), table.concat(calls, " | "))
    assertTrue(has(calls, "shown,3,true") and has(calls, "docked,3,3"))
    assertTrue(has(calls, "add,3,GUILD") and has(calls, "add,3,WHISPER"))
    assertTrue(has(calls, "name,4,Whispers"))
    assertTrue(has(calls, "remove,1,GUILD") and not has(calls, "remove,1,SAY"))
    assertTrue(state().ownedNames.Focused and state().removedFromGeneral.GUILD)
    assertEq(popups[#popups], "ULTIMATE_CHAT_RELOAD")
  end)
  it("applying twice changes nothing the second time", function()
    resetConfig()
    state().ownedNames, state().removedFromGeneral = {}, {}
    FC:Apply()
    calls = {}
    FC:Apply()
    assertEq(calls, {})
  end)
  it("copies this session's matching lines into new tabs, skipping secret ones", function()
    resetConfig()
    state().ownedNames, state().removedFromGeneral, state().pendingHistory = {}, {}, {}
    local secretText = "secret!"
    __secret[secretText] = true
    ChatFrame1.lines = {
      { text = "[Guild] Arthas: anyone for SM?", typeID = 2, lineID = 10 },
      { text = "[Say] Bob: hi", typeID = 1, lineID = 11 },
      { text = "[Whisper] Jaina: thanks", typeID = 3, lineID = 12 },
      { text = secretText, typeID = 2, lineID = 13 },
    }
    FC:Apply()
    local pending = state().pendingHistory
    assertEq(#pending.Guild, 1)
    assertEq(pending.Guild[1].text, "[Guild] Arthas: anyone for SM?")
    assertEq(#pending.Focused, 2, "guild + whisper, not say, not the secret line")
    assertEq(pending.Focused[2].text, "[Whisper] Jaina: thanks", "in the order they arrived")
    __secret[secretText] = nil
  end)
  it("keeps at most 200 lines per tab, the newest ones", function()
    resetConfig()
    state().ownedNames, state().removedFromGeneral, state().pendingHistory = {}, {}, {}
    ChatFrame1.lines = {}
    for i = 1, 250 do ChatFrame1.lines[i] = { text = "g" .. i, typeID = 2, lineID = i } end
    FC:Apply()
    assertEq(#state().pendingHistory.Guild, 200)
    assertEq(state().pendingHistory.Guild[1].text, "g51")
  end)
  it("after the reload, adds the saved lines to the matching tabs once", function()
    cfg[3].name, cfg[7].name = "Focused", "Guild"
    state().pendingHistory = { Guild = { { text = "[Guild] Arthas: anyone for SM?", r = 0.25, g = 1, b = 0.25 } } }
    ChatFrame7.lines = {}
    FC:ReplayHistory()
    assertEq(ChatFrame7.lines[1].text, L.CHAT_HISTORY_HEADER)
    assertEq(ChatFrame7.lines[2].text, "[Guild] Arthas: anyone for SM?")
    assertEq(state().pendingHistory, {})
    FC:ReplayHistory()
    assertEq(#ChatFrame7.lines, 2, "not twice")
  end)
  it("does nothing in combat", function()
    resetConfig()
    __inCombat = true
    FC:Apply()
    __inCombat = false
    assertEq(#calls, 0)
  end)
  it("turning the feature off hides its tabs, restores General and asks to reload", function()
    resetConfig()
    state().ownedNames, state().removedFromGeneral = {}, {}
    FC:Apply()
    calls, popups = {}, {}
    ns.Modules:SetEnabled("focusedChat", false)
    assertTrue(has(calls, "shown,3,false") and has(calls, "docked,3,nil"), table.concat(calls, " | "))
    assertTrue(has(calls, "add,1,GUILD") and has(calls, "add,1,WHISPER"))
    assertEq(state().ownedNames, {})
    assertEq(popups[#popups], "ULTIMATE_CHAT_RELOAD")
    ns.Modules:SetEnabled("focusedChat", true)
  end)
end)
