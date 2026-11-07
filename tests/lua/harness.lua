-- Test harness: tiny assertion library + WoW API stubs.
-- Loaded before the add-on files in every test runtime.

__results = { passed = 0, failed = 0, messages = {} }
local currentDescribe = ""

function describe(name, fn) currentDescribe = name; fn(); currentDescribe = "" end

function it(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    __results.passed = __results.passed + 1
  else
    __results.failed = __results.failed + 1
    table.insert(__results.messages, "FAIL " .. currentDescribe .. " > " .. name .. ": " .. tostring(err))
  end
end

local function dump(v, depth)
  depth = depth or 0
  if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
  if depth > 3 then return "{...}" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. dump(v[k], depth + 1) end
  return "{" .. table.concat(parts, ",") .. "}"
end
__dump = dump

local function deepEq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function assertEq(actual, expected, msg)
  if not deepEq(actual, expected) then
    error((msg or "assertEq") .. ": expected " .. dump(expected) .. ", got " .. dump(actual), 2)
  end
end
function assertTrue(v, msg) if not v then error((msg or "assertTrue") .. ": got " .. dump(v), 2) end end
function assertFalse(v, msg) if v then error((msg or "assertFalse") .. ": got " .. dump(v), 2) end end
function assertNil(v, msg) if v ~= nil then error((msg or "assertNil") .. ": got " .. dump(v), 2) end end

------------------------------------------------------------------------------
-- Add-on loading
------------------------------------------------------------------------------
__ns = {}
function __loadAddonFile(path)
  local chunk, err = loadfile(path)
  if not chunk then error("load " .. path .. ": " .. tostring(err)) end
  chunk("Ultimate", __ns)
end
-- Called after all add-on files load; simulates ADDON_LOADED unless a test opts out.
function __afterLoad() end

------------------------------------------------------------------------------
-- WoW API stubs (minimal, extended per test as needed)
------------------------------------------------------------------------------
__time = 1000
function GetTime() return __time end
function time() return math.floor(__time) end
__inCombat = false
function InCombatLockdown() return __inCombat end
__secret = {}
function issecretvalue(v) return v ~= nil and __secret[v] == true end
function print(...) end
function geterrorhandler() return function(e) end end
function hooksecurefunc() end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove

__frames = {}
local Frame = {}
Frame.__index = Frame
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:IsEventRegistered(e) return self.events[e] == true end
function Frame:SetScript(k, fn) self.scripts[k] = fn end
function Frame:GetScript(k) return self.scripts[k] end
function Frame:HookScript(k, fn) local old = self.scripts[k]; self.scripts[k] = function(...) if old then old(...) end fn(...) end end
function Frame:SetAttribute(k, v)
  if self.secure and __inCombat then error("ACTION_BLOCKED SetAttribute " .. tostring(k)) end
  self.attrs[k] = v
  table.insert(__attrLog, { frame = self.name, key = k, value = v })
end
function Frame:GetAttribute(k) return self.attrs[k] end
function Frame:Show() if self.secure and __inCombat then error("ACTION_BLOCKED Show") end self.shown = true end
function Frame:Hide() if self.secure and __inCombat then error("ACTION_BLOCKED Hide") end self.shown = false end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown end
function Frame:GetName() return self.name end
function Frame:SetParent(p) self.parent = p end
function Frame:GetParent() return self.parent end
function Frame:CreateTexture(name) return setmetatable({ kind = "Texture", name = name, attrs = {}, events = {}, scripts = {}, shown = true }, Frame) end
function Frame:CreateFontString(name) return setmetatable({ kind = "FontString", name = name, attrs = {}, events = {}, scripts = {}, shown = true, text = "" }, Frame) end
function Frame:CreateAnimationGroup() return setmetatable({ kind = "AnimGroup", attrs = {}, events = {}, scripts = {}, shown = true }, Frame) end
function Frame:CreateAnimation() return setmetatable({ kind = "Anim", attrs = {}, events = {}, scripts = {}, shown = true }, Frame) end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:SetFormattedText(f, ...) self.text = string.format(f, ...) end
function Frame:SetPoint(...)
  if self.secure and __inCombat then error("ACTION_BLOCKED SetPoint") end
  self.point = { ... }
end
function Frame:GetPoint() if self.point then return unpack(self.point) end end
-- Any other method is a recorded no-op.
setmetatable(Frame, { __index = function(_, k) return function(self, ...) end end })

__attrLog = {}
function CreateFrame(kind, name, parent, template)
  local f = setmetatable({ kind = kind, name = name, parent = parent, template = template,
    attrs = {}, events = {}, scripts = {}, shown = true }, Frame)
  f.secure = template and tostring(template):find("Secure") ~= nil or false
  table.insert(__frames, f)
  if name then _G[name] = f end
  return f
end
UIParent = CreateFrame("Frame", "UIParent")

function __fire(event, ...)
  for _, f in ipairs(__frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

__timers = {}
C_Timer = {
  After = function(sec, fn) table.insert(__timers, { at = __time + sec, fn = fn }) end,
  NewTicker = function(sec, fn)
    local t = { interval = sec, fn = fn, cancelled = false }
    function t:Cancel() self.cancelled = true end
    function t:IsCancelled() return self.cancelled end
    table.insert(__timers, { ticker = t })
    return t
  end,
}
-- Advance time and run due one-shot timers; tickers fire once per call when tick=true.
function __advance(sec, tick)
  __time = __time + (sec or 0)
  local pending = __timers
  __timers = {}
  for _, t in ipairs(pending) do
    if t.ticker then
      if not t.ticker.cancelled then
        if tick then t.ticker.fn(t.ticker) end
        table.insert(__timers, t)
      end
    elseif t.at <= __time then
      t.fn()
    else
      table.insert(__timers, t)
    end
  end
end
