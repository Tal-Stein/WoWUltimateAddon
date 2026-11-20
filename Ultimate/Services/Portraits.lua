local ADDON, ns = ...

-- Creature portraits for mobs with no unit to draw from (long-range finds). A portrait can be
-- drawn from a creature's model number (display ID) with SetPortraitTextureFromCreatureDisplayID,
-- the call Blizzard's UI uses. The display ID comes from the creature's NPC ID, which Questie
-- already knows for every quest mob: a hidden DressUpModel is given the creature (SetCreature),
-- the client asks the server about it if needed, and GetDisplayInfo then answers. Same approach
-- as Spoken's quest portraits. Answers are kept per name, account-wide.
local P = { waiting = {}, gaveUp = {}, npcOf = {} }
ns.Portraits = P

local POLL = 0.1      -- seconds between reads while a creature loads
local RESEND = 1      -- ask again if still nothing after this long
local GIVE_UP = 8     -- stop trying for a creature after this long...
local RETRY_AFTER = 120 -- ...and don't try it again for this long
local MOST = 8        -- creatures loading at once

local function store()
  if not ns.global then return nil end
  ns.global.displayIds = ns.global.displayIds or {}
  return ns.global.displayIds
end

function P.NewModel()
  local ok, frame = pcall(CreateFrame, "DressUpModel")
  if not (ok and frame and frame.GetDisplayInfo and frame.SetCreature) then return nil end
  frame:Hide() -- never shown: a shown model draws a 3D scene every frame
  return frame
end

local function readDisplay(model)
  local ok, id = pcall(model.GetDisplayInfo, model)
  id = ok and tonumber(id) or 0
  return id > 0 and id or nil
end

-- While a creature isn't cached yet, a model answers with a stand-in: the player's look, or what
-- an empty model shows. Neither is the creature's, so neither is believed.
local function standIns()
  if P.probes == nil then
    P.probes = false
    local own, blank = P.NewModel(), P.NewModel()
    if own and blank then P.probes = { own = own, blank = blank } end
  end
  if not P.probes then return nil, nil end
  pcall(P.probes.own.SetUnit, P.probes.own, "player")
  return readDisplay(P.probes.own), readDisplay(P.probes.blank)
end

-- The NPC ID for a name: from Questie's quest data, else learned from a sighting.
function P:NpcIdFor(name)
  local entry = ns.QuestIndex and ns.QuestIndex.byName and ns.QuestIndex.byName[name]
  local best
  for id in pairs(entry and entry.npcIds or {}) do
    if type(id) == "number" and (not best or id < best) then best = id end
  end
  return best or self.npcOf[name]
end

local step
local function schedule()
  if P.scheduled or not next(P.waiting) then return end
  P.scheduled = true
  C_Timer.After(POLL, function() P.scheduled = false; ns.SafeCall(step) end)
end

-- Start loading name's portrait. Returns nothing; ULT_PORTRAIT_READY fires once it's known.
function P:Request(name)
  local cache = store()
  if not cache or not name or cache[name] or self.waiting[name] then return end
  if type(SetPortraitTextureFromCreatureDisplayID) ~= "function" then return end
  local now = GetTime()
  if self.gaveUp[name] and now - self.gaveUp[name] < RETRY_AFTER then return end
  local npcId = self:NpcIdFor(name)
  if not npcId then return end
  local count = 0
  for _ in pairs(self.waiting) do count = count + 1 end
  if count >= MOST then return end
  self.pool = self.pool or {}
  local model = table.remove(self.pool) or self.NewModel()
  if not model then return end
  if model.ClearModel then pcall(model.ClearModel, model) end
  local before = readDisplay(model)
  if not pcall(model.SetCreature, model, npcId) then table.insert(self.pool, model); return end
  self.waiting[name] = { model = model, npcId = npcId, since = now, sent = now, before = before }
  schedule()
end

step = function()
  local cache = store()
  local now = GetTime()
  local own, blank
  local ready = false
  for name, w in pairs(P.waiting) do
    local id = readDisplay(w.model)
    if id and id ~= w.before then
      if own == nil and blank == nil then own, blank = standIns() end
      if id == own or id == blank then id = nil end
    else
      id = nil
    end
    if id and cache then
      cache[name] = id
      ready = true
    elseif now - w.since >= GIVE_UP then
      P.gaveUp[name] = now
    elseif now - w.sent >= RESEND then
      w.sent = now
      pcall(w.model.SetCreature, w.model, w.npcId)
    end
    if id or now - w.since >= GIVE_UP then
      P.waiting[name] = nil
      table.insert(P.pool, w.model)
    end
  end
  if ready then ns:Fire("ULT_PORTRAIT_READY") end
  schedule()
end
P.Step = function() return step() end

-- A sighted unit tells us its NPC ID (from its GUID) even when Questie doesn't know the name.
function P:Learn(unit)
  if not ns.Safe.read(UnitExists, unit) or ns.Safe.read(UnitIsPlayer, unit) then return end
  local name = ns.Safe.read(UnitName, unit)
  local guid = ns.Safe.read(UnitGUID, unit)
  if type(name) ~= "string" or type(guid) ~= "string" then return end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
  if (kind == "Creature" or kind == "Vehicle") and not self.npcOf[name] then self.npcOf[name] = tonumber(id) end
  self:Request(name)
end

-- Draw a portrait into texture; false (and starts loading it) if it isn't known yet.
function P:Apply(texture, name)
  local cache = store()
  local id = cache and name and cache[name]
  local draw = SetPortraitTextureFromCreatureDisplayID
  if not id then self:Request(name); return false end
  if not (texture and type(draw) == "function") then return false end
  return (pcall(draw, texture, id))
end

ns:On("PLAYER_TARGET_CHANGED", P, function() ns.SafeCall(P.Learn, P, "target") end)
ns:On("UPDATE_MOUSEOVER_UNIT", P, function() ns.SafeCall(P.Learn, P, "mouseover") end)
