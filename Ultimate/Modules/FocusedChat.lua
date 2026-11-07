local ADDON, ns = ...
local L = ns.L

-- Focused Chat: a "Focused" tab with the chats that matter (whispers, party, guild, ...) plus one
-- tab per chosen category, all real Blizzard chat tabs in the main dock. Purely additive: General
-- keeps everything it shows; the planner's "remove from General" path is only used to give back
-- what the first version of this module took out of it.
--
-- Taint safety: this module never writes Blizzard's live chat frames. It changes only the saved
-- chat-window configuration (the same client functions Blizzard's chat settings use) and then
-- reloads; Blizzard rebuilds the windows from that configuration with its own code. The only
-- frame call is AddMessage (what print() does) to put saved history back after the reload.
-- See docs/superpowers/specs/2026-11-07-focused-chat-design.md.
local FC = {}
ns.FocusedChatModule = FC

local P = ns.ChatPlan
local HISTORY_MAX = 200

local function o() return ns.db.focusedChat end

-- Per-character facts about this character's chat windows (independent of the profile scope).
local function charState()
  UltimateCharDB = UltimateCharDB or {}
  local s = UltimateCharDB.focusedChatState or {}
  UltimateCharDB.focusedChatState = s
  s.ownedNames = s.ownedNames or {}
  s.removedFromGeneral = s.removedFromGeneral or {}
  s.pendingHistory = s.pendingHistory or {}
  return s
end

local function labels()
  return { focused = L.CHAT_FOCUSED, whispers = L.CHAT_WHISPERS, party = L.CHAT_PARTY, raid = L.CHAT_RAID,
    instance = L.CHAT_INSTANCE, guild = L.CHAT_GUILD, officer = L.CHAT_OFFICER, sayyell = L.CHAT_SAYYELL,
    emotes = L.CHAT_EMOTES }
end

local function available()
  local set = {}
  for group in pairs(ChatTypeGroup or {}) do set[group] = true end
  return set
end

local function limits()
  local max = Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows
    or NUM_CHAT_WINDOWS or 10
  local reserved = 2
  if C_ChatInfo and C_ChatInfo.GetNumReservedChatWindows then
    local ok, n = pcall(C_ChatInfo.GetNumReservedChatWindows)
    if ok and type(n) == "number" then reserved = n end
  end
  return reserved, max
end

-- Read the saved chat-window configuration.
function FC.ReadState()
  local reserved, max = limits()
  local windows = {}
  for id = 1, max do
    local name, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(id)
    windows[id] = { name = name or "", shown = shown and true or false,
      docked = (type(docked) == "number" and docked > 0) and docked or nil,
      groups = { GetChatWindowMessages(id) } }
  end
  return { windows = windows, reserved = reserved, max = max }
end

local function execute(actions)
  for _, a in ipairs(actions) do
    if a.op == "name" then SetChatWindowName(a.id, a.value)
    elseif a.op == "show" then SetChatWindowShown(a.id, true)
    elseif a.op == "hide" then SetChatWindowShown(a.id, false)
    elseif a.op == "dock" then SetChatWindowDocked(a.id, a.value)
    elseif a.op == "undock" then SetChatWindowDocked(a.id, nil)
    elseif a.op == "add" then AddChatWindowMessages(a.id, a.value)
    elseif a.op == "remove" then RemoveChatWindowMessages(a.id, a.value)
    end
  end
end

-- Chat-type ids (ChatTypeInfo[type].id, stored with every chat line) for a list of groups.
local function typeIds(groups)
  local ids = {}
  for _, group in ipairs(groups) do
    for _, event in ipairs((ChatTypeGroup or {})[group] or {}) do
      local info = ChatTypeInfo and ChatTypeInfo[(string.gsub(event, "^CHAT_MSG_", ""))]
      if info and info.id then ids[info.id] = true end
    end
  end
  return ids
end

-- This session's lines for the given groups, oldest first, newest HISTORY_MAX kept.
local function collect(groups, max)
  local ids, seen, lines = typeIds(groups), {}, {}
  for id = 1, max do
    local frame = _G["ChatFrame" .. id]
    if frame and frame.GetNumMessages and frame.GetMessageInfo then
      for i = 1, frame:GetNumMessages() do
        local ok, text, r, g, b, typeID, _, lineID = pcall(frame.GetMessageInfo, frame, i)
        if ok and ids[typeID] and type(text) == "string" and not ns.Safe.isSecret(text) then
          local key = lineID or text
          if not seen[key] then
            seen[key] = true
            lines[#lines + 1] = { text = text, r = r, g = g, b = b, order = lineID or (1e9 + #lines) }
          end
        end
      end
    end
  end
  table.sort(lines, function(a, b) return a.order < b.order end)
  local out = {}
  for i = math.max(1, #lines - HISTORY_MAX + 1), #lines do
    local l = lines[i]
    out[#out + 1] = { text = l.text, r = l.r, g = l.g, b = l.b }
  end
  return out
end

local function plan(settingsOverride)
  local s = charState()
  local settings = settingsOverride or { categories = o().categories, removeFromGeneral = false }
  settings.ownedNames, settings.removedFromGeneral = s.ownedNames, s.removedFromGeneral
  local ctx = { labels = labels(), available = available() }
  local state = FC.ReadState()
  local actions, info = P.plan(state, settings, ctx)
  return actions, info, state, ctx, settings
end

local function run(settingsOverride)
  if InCombatLockdown() then ns:Print(L.CHAT_IN_COMBAT); return false end
  local actions, info, state, ctx, settings = plan(settingsOverride)
  if #actions == 0 then ns:Print(L.CHAT_UP_TO_DATE); return true end
  local s = charState()
  if o().copyHistory and not settingsOverride then
    local tabs = {}
    for _, t in ipairs(P.desiredTabs(settings, ctx)) do tabs[t.name] = t.groups end
    for name in pairs(info.created) do
      local lines = collect(tabs[name] or {}, state.max)
      if #lines > 0 then s.pendingHistory[name] = lines end
    end
  end
  execute(actions)
  s.ownedNames, s.removedFromGeneral = info.owned, info.removedFromGeneral
  if #info.skipped > 0 then ns:Print(string.format(L.CHAT_SKIPPED, table.concat(info.skipped, ", "))) end
  if StaticPopup_Show then StaticPopup_Show("ULTIMATE_CHAT_RELOAD") end
  return true
end

function FC:Apply() return run(nil) end

-- Undo everything this module set up (feature turned off).
function FC:Remove()
  local categories = {}
  for _, c in ipairs(P.CATEGORIES) do categories[c.key] = { focused = false, tab = false } end
  return run({ categories = categories, removeFromGeneral = false })
end

-- After a reload: put the saved history into the tabs that were just created, once.
function FC:ReplayHistory()
  local s = charState()
  if not next(s.pendingHistory) then return end
  local _, max = limits()
  for id = 1, max do
    local name = GetChatWindowInfo(id)
    local lines = name and s.pendingHistory[name]
    local frame = _G["ChatFrame" .. id]
    if lines and frame and frame.AddMessage then
      frame:AddMessage(L.CHAT_HISTORY_HEADER, 0.6, 0.6, 0.6)
      for _, l in ipairs(lines) do frame:AddMessage(l.text, l.r, l.g, l.b) end
    end
  end
  s.pendingHistory = {}
end

local defaults = { copyHistory = true, categories = {} }
for _, c in ipairs(P.CATEGORIES) do defaults.categories[c.key] = { focused = c.focused, tab = c.tab } end

FC.def = ns.Modules:Register({
  key = "focusedChat",
  name = L.MODULE_FOCUSED_CHAT,
  description = L.MODULE_FOCUSED_CHAT_DESC,
  defaults = defaults,
  OnEnable = function() end, -- inert until Apply
  OnDisable = function() FC:Remove() end,
})

-- Version 2: tabs are additive and raid is no longer focused by default. Characters set up by
-- version 1 get raid switched off once (their saved setting was the old default).
ns:On("ULT_DB_READY", FC, function()
  local fc = ns.db.focusedChat
  if (fc.version or 1) < 2 then
    if fc.categories and fc.categories.raid then fc.categories.raid.focused = false end
    fc.removeFromGeneral = nil
    fc.version = 2
  end
end)

-- Give General back whatever version 1 took out of it (and apply the new defaults), once.
function FC:RestoreGeneral()
  if not next(charState().removedFromGeneral) then return end
  ns:Print(L.CHAT_GENERAL_RESTORED)
  run(nil)
end

ns:On("PLAYER_ENTERING_WORLD", FC, function()
  ns:Off("PLAYER_ENTERING_WORLD", FC)
  -- Give Blizzard's chat windows a moment to rebuild from their configuration first.
  C_Timer.After(2, function()
    ns.SafeCall(FC.ReplayHistory, FC)
    ns.SafeCall(FC.RestoreGeneral, FC)
  end)
end)

function FC.def.BuildSettings(ctx)
  local names = labels()
  ctx:Header(L.CHAT_SECTION_CATEGORIES)
  for _, c in ipairs(P.CATEGORIES) do
    ctx:Checkbox("focusedChat.categories." .. c.key .. ".focused", names[c.key], L.CHAT_FOCUSED_TIP)
    ctx:Checkbox("focusedChat.categories." .. c.key .. ".tab", string.format(L.CHAT_OWN_TAB, names[c.key]), L.CHAT_OWN_TAB_TIP)
  end
  ctx:Header(L.CHAT_SECTION_OPTIONS)
  ctx:Checkbox("focusedChat.copyHistory", L.CHAT_COPY_HISTORY, L.CHAT_COPY_HISTORY_TIP)
  ctx:Button(L.CHAT_APPLY_LABEL, L.CHAT_APPLY, function() FC:Apply() end, L.CHAT_APPLY_TIP)
end

if StaticPopupDialogs then
  StaticPopupDialogs.ULTIMATE_CHAT_RELOAD = {
    text = L.CHAT_RELOAD_PROMPT, button1 = L.RELOAD, button2 = L.LATER,
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
end
