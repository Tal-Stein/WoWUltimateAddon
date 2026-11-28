local ADDON, ns = ...
local L = ns.L

-- Records what goes wrong so it can be found and fixed: Ultimate's own Lua errors (which
-- SafeCall otherwise swallows) with their stack, and every blocked/forbidden action the game
-- reports, naming the add-on and function. Kept in UltimateDB.errorLog, which the game writes
-- to disk on /reload and logout. Repeats are counted, not duplicated; at most MAX entries.
local EL = { pending = {} }
ns.ErrorLog = EL

local MAX = 50

local function now() return (time and time()) or 0 end

local function store()
  local g = ns.global
  if not g then return nil end
  g.errorLog = g.errorLog or {}
  return g.errorLog
end

local function version()
  local fn = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return ns.Safe and ns.Safe.read(fn, ADDON, "Version") or nil
end

-- kind: "lua" | "blocked" | "forbidden"; key identifies repeats; extra fields are merged in.
function EL:Record(kind, key, detail, extra)
  local list = store()
  if not list then
    self.pending[#self.pending + 1] = { kind, key, detail, extra }
    return
  end
  for _, e in ipairs(list) do
    if e.kind == kind and e.key == key then
      e.count, e.last = (e.count or 1) + 1, now()
      return
    end
  end
  local e = { kind = kind, key = key, detail = detail, count = 1, first = now(), last = now(),
    version = version() }
  for k, v in pairs(extra or {}) do e[k] = v end
  list[#list + 1] = e
  if #list > MAX then
    local oldest = 1
    for i, x in ipairs(list) do
      if (x.last or 0) < (list[oldest].last or 0) then oldest = i end
    end
    table.remove(list, oldest)
  end
end

function EL:Clear()
  if ns.global then ns.global.errorLog = {} end
  self.pending = {}
end

function EL:Report()
  local list = store() or {}
  ns:Print(string.format(L.ERRORS_HEADER, #list))
  for _, e in ipairs(list) do
    local what = e.kind == "lua" and (string.match(e.detail or "", "^[^\n]*") or e.key)
      or string.format("%s: %s", e.addon or "?", e.func or "?")
    ns:Print(string.format("  [%s x%d] %s", e.kind, e.count or 1, what))
  end
end

local function firstLine(s) return string.match(tostring(s), "^[^\n]*") end

-- Ultimate's own errors (Init's onError calls this).
function EL.OnLuaError(msg)
  EL:Record("lua", firstLine(msg), tostring(msg))
end

ns:On("ULT_DB_READY", EL, function()
  local pending = EL.pending
  EL.pending = {}
  for _, p in ipairs(pending) do EL:Record(p[1], p[2], p[3], p[4]) end
end)

-- A blocked action may reach us twice (the event, and the game's own handler hooked below):
-- the second report of the same one within SAME_ACTION seconds is the same action.
local SAME_ACTION = 0.5
local lastAction
local function recordAction(kind, addon, func, stack)
  local key = kind .. ":" .. tostring(addon) .. ":" .. tostring(func)
  local t = GetTime and GetTime() or now()
  if lastAction and lastAction.key == key and t - lastAction.at < SAME_ACTION then
    if stack and lastAction.entry and not lastAction.entry.detail then lastAction.entry.detail = stack end
    return
  end
  EL:Record(kind, key, stack, { addon = addon, func = func, inCombat = InCombatLockdown() and true or false })
  local entry
  for _, e in ipairs(store() or {}) do if e.key == key and e.kind == kind then entry = e end end
  lastAction = { key = key, at = t, entry = entry }
end

local function onAction(kind)
  return function(_, addon, func) recordAction(kind, addon, func) end
end
ns:On("ADDON_ACTION_BLOCKED", EL, onAction("blocked"))
ns:On("ADDON_ACTION_FORBIDDEN", EL, onAction("forbidden"))

-- The game also handles blocked actions itself (Blizzard_Game's HandleAddonActionBlocked /
-- HandleAddonActionForbidden, which show "Interface action failed because of an AddOn"), at
-- times without the event reaching add-ons. Post-hooking those (hooksecurefunc: no taint)
-- records them too, with the stack at that moment, which leads to the code that caused it.
local hooked = {}
local function hookHandlers()
  for name, kind in pairs({ HandleAddonActionBlocked = "blocked", HandleAddonActionForbidden = "forbidden" }) do
    if not hooked[name] and type(_G[name]) == "function" and hooksecurefunc then
      hooked[name] = true
      hooksecurefunc(name, function(addon, func)
        pcall(recordAction, kind, addon, func, debugstack and debugstack(2) or nil)
      end)
    end
  end
end
hookHandlers()
ns:On("PLAYER_LOGIN", EL, hookHandlers)

-- Lua errors the game reports outside Ultimate's own guards (frame scripts, hooks): wrap the
-- game's error handler like BugGrabber does. Only errors whose message or stack runs through
-- Ultimate's files are recorded; every error is still passed on unchanged.
local function mentionsUltimate(text)
  text = tostring(text or "")
  return string.find(text, "AddOns/Ultimate/", 1, true) or string.find(text, "AddOns\\Ultimate\\", 1, true)
end

if type(geterrorhandler) == "function" and type(seterrorhandler) == "function" then
  EL.previousHandler = geterrorhandler()
  seterrorhandler(function(msg, ...)
    pcall(function()
      local stack = debugstack and debugstack(3) or ""
      if mentionsUltimate(msg) or mentionsUltimate(stack) then
        EL:Record("lua", firstLine(msg), tostring(msg) .. "\n" .. stack)
      end
    end)
    if EL.previousHandler then return EL.previousHandler(msg, ...) end
  end)
end
