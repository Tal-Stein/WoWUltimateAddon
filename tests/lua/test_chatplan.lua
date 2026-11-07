local ns = __ns
local P = ns.ChatPlan

local LABELS = { focused = "Focused", whispers = "Whispers", party = "Party", raid = "Raid",
  instance = "Instance", guild = "Guild", officer = "Officer", sayyell = "Say & Yell", emotes = "Emotes" }
local ALL = { WHISPER = true, BN_WHISPER = true, PARTY = true, PARTY_LEADER = true, RAID = true,
  RAID_LEADER = true, RAID_WARNING = true, INSTANCE_CHAT = true, INSTANCE_CHAT_LEADER = true,
  GUILD = true, GUILD_DISCORD = true, OFFICER = true, SAY = true, YELL = true, EMOTE = true, CHANNEL = true }

-- A fresh character: General (1, docked 1) and Combat Log (2, docked 2); 3..10 free.
local function freshState()
  local windows = {
    [1] = { name = "General", shown = true, docked = 1,
      groups = { "SAY", "EMOTE", "YELL", "GUILD", "OFFICER", "WHISPER", "BN_WHISPER", "PARTY", "PARTY_LEADER",
        "RAID", "RAID_LEADER", "RAID_WARNING", "CHANNEL" } },
    [2] = { name = "Combat Log", shown = true, docked = 2, groups = {} },
  }
  for i = 3, 10 do windows[i] = { name = "", shown = false, docked = nil, groups = {} } end
  return { windows = windows, reserved = 2, max = 10 }
end

local function settings(over)
  local s = { categories = {}, removeFromGeneral = true, ownedNames = {}, removedFromGeneral = {} }
  for _, c in ipairs(P.CATEGORIES) do s.categories[c.key] = { focused = c.focused, tab = c.tab } end
  for k, v in pairs(over or {}) do s[k] = v end
  return s
end

local function ctx() return { labels = LABELS, available = ALL } end

local function ops(actions, id)
  local out = {}
  for _, a in ipairs(actions) do
    if a.id == id then out[#out + 1] = a.op .. (a.value ~= nil and ("=" .. tostring(a.value)) or "") end
  end
  return out
end
local function has(list, item) for _, v in ipairs(list) do if v == item then return true end end return false end

describe("ChatPlan.desiredTabs", function()
  it("Focused first with every focused category's groups, then one tab per 'own tab' category", function()
    local tabs = P.desiredTabs(settings(), ctx())
    local names = {}
    for _, t in ipairs(tabs) do names[#names + 1] = t.name end
    assertEq(names, { "Focused", "Whispers", "Party", "Raid", "Guild" })
    assertTrue(has(tabs[1].groups, "OFFICER") and has(tabs[1].groups, "INSTANCE_CHAT"), "Focused has all focused groups")
    assertFalse(has(tabs[1].groups, "SAY"), "say is not focused by default")
    assertEq(tabs[5].groups, { "GUILD", "GUILD_DISCORD" })
  end)
  it("drops groups this client doesn't have", function()
    local c = ctx()
    c.available = { GUILD = true }
    local tabs = P.desiredTabs(settings(), c)
    assertEq(tabs[1].groups, { "GUILD" })
    assertEq(#tabs, 2, "Focused + Guild; categories with no groups vanish")
  end)
  it("no focused categories means no tabs", function()
    local s = settings()
    for _, c in pairs(s.categories) do c.focused = false end
    assertEq(#P.desiredTabs(s, ctx()), 0)
  end)
end)

describe("ChatPlan.plan", function()
  it("creates the tabs in free windows, docked after Combat Log, with only their groups", function()
    local actions, info = P.plan(freshState(), settings(), ctx())
    assertEq(info.created, { Focused = 3, Whispers = 4, Party = 5, Raid = 6, Guild = 7 })
    local w3 = ops(actions, 3)
    assertTrue(has(w3, "name=Focused") and has(w3, "show") and has(w3, "dock=3"), table.concat(w3, ","))
    assertTrue(has(w3, "add=OFFICER"))
    assertTrue(has(ops(actions, 7), "dock=7"))
    assertEq(info.owned, { Focused = true, Whispers = true, Party = true, Raid = true, Guild = true })
  end)
  it("removes focused groups from General and remembers them", function()
    local actions, info = P.plan(freshState(), settings(), ctx())
    local g = ops(actions, 1)
    assertTrue(has(g, "remove=GUILD") and has(g, "remove=WHISPER") and has(g, "remove=OFFICER"))
    assertFalse(has(g, "remove=SAY") or has(g, "remove=CHANNEL"), "social stays in General")
    assertTrue(info.removedFromGeneral.GUILD and info.removedFromGeneral.WHISPER)
    assertNil(info.removedFromGeneral.INSTANCE_CHAT, "General never had it, nothing to give back")
  end)
  it("keeps General untouched when that option is off", function()
    local actions = P.plan(freshState(), settings({ removeFromGeneral = false }), ctx())
    assertEq(#ops(actions, 1), 0)
  end)
  it("is idempotent: applying the result again changes nothing", function()
    local state = freshState()
    local actions, info = P.plan(state, settings(), ctx())
    P.applyToState(state, actions)
    local again = P.plan(state, settings({ ownedNames = info.owned, removedFromGeneral = info.removedFromGeneral }), ctx())
    assertEq(again, {}, "second plan is empty")
  end)
  it("reuses an existing tab with the same name instead of making another", function()
    local state = freshState()
    state.windows[5] = { name = "Guild", shown = true, docked = 3, groups = { "GUILD", "SAY" } }
    local actions, info = P.plan(state, settings(), ctx())
    assertEq(info.created.Guild, nil, "not newly created")
    local g5 = ops(actions, 5)
    assertTrue(has(g5, "remove=SAY") and has(g5, "add=GUILD_DISCORD"), table.concat(g5, ","))
    assertFalse(has(g5, "dock=" .. 3), "already docked stays put")
  end)
  it("hides tabs it owns that are no longer wanted, and gives General its groups back", function()
    local state = freshState()
    local actions, info = P.plan(state, settings(), ctx())
    P.applyToState(state, actions)
    local s = settings({ ownedNames = info.owned, removedFromGeneral = info.removedFromGeneral })
    s.categories.guild.focused = false
    local actions2, info2 = P.plan(state, s, ctx())
    local w7 = ops(actions2, 7)
    assertTrue(has(w7, "hide") and has(w7, "undock") and has(w7, "remove=GUILD"), table.concat(w7, ","))
    local g = ops(actions2, 1)
    assertTrue(has(g, "add=GUILD") and has(g, "add=GUILD_DISCORD") == false, "only what we removed comes back")
    assertNil(info2.owned.Guild)
    assertNil(info2.removedFromGeneral.GUILD)
  end)
  it("never hides a window it doesn't own", function()
    local state = freshState()
    state.windows[4] = { name = "Trade", shown = true, docked = 3, groups = { "CHANNEL" } }
    local actions = P.plan(state, settings(), ctx())
    assertEq(#ops(actions, 4), 0)
  end)
  it("turning everything off undoes it all", function()
    local state = freshState()
    local actions, info = P.plan(state, settings(), ctx())
    P.applyToState(state, actions)
    local off = settings({ ownedNames = info.owned, removedFromGeneral = info.removedFromGeneral })
    for _, c in pairs(off.categories) do c.focused = false end
    local undo, info2 = P.plan(state, off, ctx())
    P.applyToState(state, undo)
    for i = 3, 7 do assertFalse(state.windows[i].shown, "window " .. i .. " hidden") end
    assertTrue(has(state.windows[1].groups, "GUILD") and has(state.windows[1].groups, "WHISPER"))
    assertEq(info2.owned, {})
    assertEq(info2.removedFromGeneral, {})
  end)
  it("skips tabs when out of chat windows and says which", function()
    local state = freshState()
    for i = 3, 8 do state.windows[i] = { name = "Mine" .. i, shown = true, docked = i, groups = {} } end
    local _, info = P.plan(state, settings(), ctx())
    assertEq(info.created, { Focused = 9, Whispers = 10 })
    assertEq(info.skipped, { "Party", "Raid", "Guild" })
  end)
end)
