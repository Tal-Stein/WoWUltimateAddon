local ADDON, ns = ...

-- Pure: plan the Focused Chat layout as changes to the saved chat-window configuration.
--
-- state:    { reserved = n, max = n, windows = { [id] = { name, shown, docked = index|nil, groups = {...} } } }
-- settings: { categories = { [key] = { focused, tab } }, removeFromGeneral,
--             ownedNames = { [name] = true }, removedFromGeneral = { [group] = true } }
-- ctx:      { labels = { focused = "Focused", [key] = "Label" }, available = { [GROUP] = true } }
--
-- plan() -> actions, info
--   actions: { { id, op = "name"|"show"|"hide"|"dock"|"undock"|"add"|"remove", value } }
--   info:    { created = { [name] = id }, owned = {...}, removedFromGeneral = {...}, skipped = { names } }
local P = {}
ns.ChatPlan = P

local GENERAL = 1

P.CATEGORIES = {
  { key = "whispers", groups = { "WHISPER", "BN_WHISPER" }, focused = true, tab = true },
  { key = "party", groups = { "PARTY", "PARTY_LEADER" }, focused = true, tab = true },
  { key = "raid", groups = { "RAID", "RAID_LEADER", "RAID_WARNING" }, focused = false, tab = true },
  { key = "instance", groups = { "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" }, focused = true, tab = false },
  { key = "guild", groups = { "GUILD", "GUILD_DISCORD" }, focused = true, tab = true },
  { key = "officer", groups = { "OFFICER" }, focused = true, tab = false },
  { key = "sayyell", groups = { "SAY", "YELL" }, focused = false, tab = false },
  { key = "emotes", groups = { "EMOTE" }, focused = false, tab = false },
}

local function contains(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

local function availableGroups(cat, available)
  local out = {}
  for _, g in ipairs(cat.groups) do
    if available[g] then out[#out + 1] = g end
  end
  return out
end

-- The tabs the settings ask for, in dock order: Focused, then each "own tab" category.
function P.desiredTabs(settings, ctx)
  local combined, tabs = {}, {}
  for _, cat in ipairs(P.CATEGORIES) do
    local s = settings.categories[cat.key]
    local groups = availableGroups(cat, ctx.available)
    if s and s.focused and #groups > 0 then
      for _, g in ipairs(groups) do combined[#combined + 1] = g end
      if s.tab then tabs[#tabs + 1] = { name = ctx.labels[cat.key], groups = groups } end
    end
  end
  if #combined == 0 then return {} end
  table.insert(tabs, 1, { name = ctx.labels.focused, groups = combined })
  return tabs
end

local function focusedGroups(settings, ctx)
  local set = {}
  for _, cat in ipairs(P.CATEGORIES) do
    local s = settings.categories[cat.key]
    if s and s.focused then
      for _, g in ipairs(availableGroups(cat, ctx.available)) do set[g] = true end
    end
  end
  return set
end

local function findByName(state, name)
  for id = state.reserved + 1, state.max do
    local w = state.windows[id]
    if w and w.name == name then return id end
  end
end

function P.plan(state, settings, ctx)
  local actions = {}
  local function act(id, op, value) actions[#actions + 1] = { id = id, op = op, value = value } end
  local info = { created = {}, owned = {}, removedFromGeneral = {}, skipped = {} }

  local tabs = P.desiredTabs(settings, ctx)
  local wanted = {}
  for _, t in ipairs(tabs) do wanted[t.name] = true end

  -- Next dock slot: after every docked window that stays.
  local nextDock = 0
  for id = 1, state.max do
    local w = state.windows[id]
    if w and w.docked and not (settings.ownedNames[w.name] and not wanted[w.name] and id > state.reserved) then
      nextDock = math.max(nextDock, w.docked)
    end
  end

  -- Place each wanted tab: reuse a window with its name, else take a free one.
  local claimed = {}
  for _, t in ipairs(tabs) do
    local id = findByName(state, t.name)
    if id then claimed[id] = true end
  end
  for _, t in ipairs(tabs) do
    local id = findByName(state, t.name)
    local fresh = false
    if not id then
      for i = state.reserved + 1, state.max do
        local w = state.windows[i]
        if w and not claimed[i] and not w.shown and not w.docked then id = i; break end
      end
      fresh = id ~= nil
    end
    if not id then
      info.skipped[#info.skipped + 1] = t.name
    else
      claimed[id] = true
      local w = state.windows[id]
      if fresh or not w.shown then info.created[t.name] = id end
      info.owned[t.name] = true
      if w.name ~= t.name then act(id, "name", t.name) end
      if not w.shown then act(id, "show") end
      if not w.docked then nextDock = nextDock + 1; act(id, "dock", nextDock) end
      for _, g in ipairs(w.groups) do
        if not contains(t.groups, g) then act(id, "remove", g) end
      end
      for _, g in ipairs(t.groups) do
        if not contains(w.groups, g) then act(id, "add", g) end
      end
    end
  end

  -- Close tabs this add-on owns that are no longer wanted.
  for name in pairs(settings.ownedNames) do
    if not wanted[name] then
      local id = findByName(state, name)
      local w = id and state.windows[id]
      if w and (w.shown or w.docked or #w.groups > 0) then
        for _, g in ipairs(w.groups) do act(id, "remove", g) end
        if w.shown then act(id, "hide") end
        if w.docked then act(id, "undock") end
      end
    end
  end

  -- General: take focused groups out (if asked), give back what we took and no longer need to.
  local general = state.windows[GENERAL] or { groups = {} }
  local take = settings.removeFromGeneral and focusedGroups(settings, ctx) or {}
  for _, g in ipairs(general.groups) do
    if take[g] then
      act(GENERAL, "remove", g)
      info.removedFromGeneral[g] = true
    end
  end
  for g in pairs(settings.removedFromGeneral) do
    if take[g] then
      info.removedFromGeneral[g] = true
    elseif not contains(general.groups, g) then
      act(GENERAL, "add", g)
    end
  end
  return actions, info
end

-- Apply actions to a state table (used by tests and to preview a plan).
function P.applyToState(state, actions)
  for _, a in ipairs(actions) do
    local w = state.windows[a.id]
    if a.op == "name" then w.name = a.value
    elseif a.op == "show" then w.shown = true
    elseif a.op == "hide" then w.shown = false
    elseif a.op == "dock" then w.docked = a.value
    elseif a.op == "undock" then w.docked = nil
    elseif a.op == "add" then w.groups[#w.groups + 1] = a.value
    elseif a.op == "remove" then
      for i = #w.groups, 1, -1 do if w.groups[i] == a.value then table.remove(w.groups, i) end end
    end
  end
  return state
end
