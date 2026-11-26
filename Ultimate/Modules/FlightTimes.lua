local ADDON, ns = ...
local L = ns.L
local UI = ns.UI
local FT = ns.FlightTime

-- Flight Times: how long each flight takes, on the flight master's map (right side of the
-- destination's name line in its tooltip), and a countdown bar in the air styled after the
-- game's own breath/fatigue bar. Times come from flights you've taken (account-wide, kept in
-- UltimateDB.flightTimes) and otherwise from the shipped table (Data/FlightTimes.lua).
local F = {}
ns.FlightTimesModule = F

local TICK = 0.1
local TAKEOFF_WINDOW = 5 -- seconds between choosing a flight and being on the taxi
local MIN_LEARN = 5      -- shorter "flights" are glitches, not timings
local DEFAULT_POINT = { "TOP", "TOP", 0, -100 } -- where the game's breath/fatigue bars sit
local BAR_ATLAS = "ui-castingbar-filling-applyingcrafting" -- the breath bar's fill

local function o() return ns.db.flightTimes end
local function active() return ns.Modules:IsActive("flightTimes") end
local function faction() return ns.Safe.read(UnitFactionGroup, "player") end

local function learned()
  local g, side = ns.global, faction()
  if not g or not side then return nil end
  g.flightTimes = g.flightTimes or {}
  g.flightTimes[side] = g.flightTimes[side] or {}
  return g.flightTimes[side]
end

local function tables()
  local side = faction()
  local list = {}
  local mine = learned()
  if mine then list[#list + 1] = mine end
  local data = side and ns.FlightTimesData and ns.FlightTimesData[side]
  if data then list[#list + 1] = data end
  return list
end

-- "Sentinel Hill, Westfall" -> "Sentinel Hill"
local function shortName(name)
  return type(name) == "string" and (name:match("^([^,]+)") or name) or ""
end

------------------------------------------------------------------------------
-- The flight master's nodes: slot index (what the taxi functions take) -> node ID.
------------------------------------------------------------------------------
function F.Snapshot()
  F.nodes, F.current = {}, nil
  local mapID = C_Map and ns.Safe.read(C_Map.GetBestMapForUnit, "player")
  local list = mapID and C_TaxiMap and ns.Safe.read(C_TaxiMap.GetAllTaxiNodes, mapID)
  local current = Enum and Enum.FlightPathState and Enum.FlightPathState.Current
  for _, n in ipairs(type(list) == "table" and list or {}) do
    if n.slotIndex and n.nodeID then
      F.nodes[n.slotIndex] = n.nodeID
      if n.state == current then F.current = n.nodeID end
    end
  end
end

-- Seconds for the flight to taxi slot `index`, or nil.
function F.TimeFor(index)
  if not F.nodes then F.Snapshot() end
  local dest = F.nodes[index]
  local hops = {}
  for i = 1, ns.Safe.read(GetNumRoutes, index) or 0 do
    local a = F.nodes[ns.Safe.read(TaxiGetNodeSlot, index, i, true)]
    local b = F.nodes[ns.Safe.read(TaxiGetNodeSlot, index, i, false)]
    hops[#hops + 1] = { a, b }
  end
  return FT.Route(tables(), F.current, dest, hops), dest
end

-- After Blizzard's TaxiNodeOnButtonEnter has built and shown the tooltip.
function F.OnNodeEnter(button)
  if not active() or not o().showOnMap or not button or not button.GetID then return end
  local index = button:GetID()
  if ns.Safe.read(TaxiNodeGetType, index) ~= "REACHABLE" then return end
  local seconds = F.TimeFor(index)
  if not seconds or not GameTooltipTextRight1 then return end
  GameTooltipTextRight1:SetText("|cffffffff" .. FT.Format(seconds) .. "|r")
  GameTooltipTextRight1:Show()
  GameTooltip:Show() -- re-fit the tooltip around the new text
end

-- Before the game starts the flight (post-hook on TakeTaxiNode, which runs it).
function F.OnTakeTaxi(index)
  if not active() then return end
  local expected, dest = F.TimeFor(index)
  F.pending = { src = F.current, dest = dest, name = shortName(ns.Safe.read(TaxiNodeName, index)),
    expected = expected, at = GetTime() }
end

------------------------------------------------------------------------------
-- The bar: the game's breath/fatigue bar, rebuilt (its template belongs to MirrorTimerContainer).
------------------------------------------------------------------------------
local bar = CreateFrame("Frame", "UltimateFlightTimer", UIParent)
bar:SetSize(206, 32)
bar:SetFrameStrata("MEDIUM")
bar:Hide()
F.bar = bar
bar.StatusBar = CreateFrame("StatusBar", nil, bar)
bar.StatusBar:SetSize(195, 13)
bar.StatusBar:SetPoint("TOP", 0, -2)
local fill = bar.StatusBar:CreateTexture(nil, "ARTWORK")
fill:SetAtlas(BAR_ATLAS)
bar.StatusBar:SetStatusBarTexture(fill)
bar.StatusBar:SetMinMaxValues(0, 1)
bar.TextBorder = bar:CreateTexture(nil, "BACKGROUND", nil, 0)
bar.TextBorder:SetAtlas("ui-castingbar-textbox")
bar.TextBorder:SetPoint("TOPLEFT", bar.StatusBar, "TOPLEFT", 0, 0)
bar.TextBorder:SetPoint("BOTTOMRIGHT", bar.StatusBar, "BOTTOMRIGHT", 0, -14)
local bg = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
bg:SetAtlas("ui-castingbar-background")
bg:SetPoint("TOPLEFT", bar.StatusBar, "TOPLEFT", -1, 1)
bg:SetPoint("BOTTOMRIGHT", bar.StatusBar, "BOTTOMRIGHT", 1, -1)
bar.Border = bar:CreateTexture(nil, "OVERLAY")
bar.Border:SetAtlas("ui-castingbar-frame")
bar.Border:SetPoint("TOPLEFT", bar.StatusBar, "TOPLEFT", -2, 2)
bar.Border:SetPoint("BOTTOMRIGHT", bar.StatusBar, "BOTTOMRIGHT", 2, -2)
bar.Text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
bar.Text:SetPoint("TOPLEFT", bar.StatusBar, "BOTTOMLEFT", 0, 0)
bar.Text:SetPoint("BOTTOMRIGHT", bar.TextBorder, "BOTTOMRIGHT", 0, 2)

local function locked() return o().locked or ns.db.core.lockAll end
local place = UI.MakeMovable(bar, bar, setmetatable({}, {
  __index = function(_, k) return o()[k] end,
  __newindex = function(_, k, v) o()[k] = v end,
}), locked, DEFAULT_POINT)

function F.ShowMenu(owner)
  ns.Menu.Show(owner, {
    title = L.MODULE_FLIGHTS,
    lock = { get = function() return o().locked end, set = function(v) ns.Menu.Set("flightTimes.locked", v) end },
    hide = { label = L.FLIGHT_MENU_HIDE, fn = function()
      ns.Menu.Set("flightTimes.showTimer", false)
      ns:Print(L.FLIGHT_TIMER_HIDDEN)
    end },
  })
end
bar:SetScript("OnMouseUp", function(self, button)
  if button == "RightButton" then F.ShowMenu(self) end
end)

local function render()
  local f = F.flight
  if not f or not o().showTimer then bar:Hide(); return end
  local elapsed = GetTime() - f.start
  if f.expected and f.expected > 0 then
    bar.StatusBar:SetValue(math.max(0, 1 - elapsed / f.expected))
    bar.Text:SetText(f.name .. "  " .. FT.Format(f.expected - elapsed))
  else
    bar.StatusBar:SetValue(1)
    bar.Text:SetText(f.name .. "  " .. FT.Format(math.floor(elapsed + 1e-3)))
  end
  if not bar:IsShown() then place(); bar:Show() end
end

------------------------------------------------------------------------------
-- Flight tracking
------------------------------------------------------------------------------
local function startFlight(p, start)
  F.flight = { src = p.src, dest = p.dest, name = p.name, expected = p.expected, start = start }
  if type(UltimateCharDB) == "table" then
    UltimateCharDB.flight = { src = p.src, dest = p.dest, name = p.name, expected = p.expected,
      startedAt = time() - math.floor(GetTime() - start + 0.5), startedUp = start }
  end
end

local function land()
  local f = F.flight
  F.flight = nil
  if type(UltimateCharDB) == "table" then UltimateCharDB.flight = nil end
  bar:Hide()
  if not f or not f.src or not f.dest or o().learn == false then return end
  local took = GetTime() - f.start
  if took < MIN_LEARN then return end
  local mine = learned()
  if not mine then return end
  mine[f.src] = mine[f.src] or {}
  mine[f.src][f.dest] = math.floor(took + 0.5)
end

function F.Tick()
  local onTaxi = ns.Safe.read(UnitOnTaxi, "player")
  if F.pending then
    if onTaxi then
      startFlight(F.pending, GetTime())
      F.pending = nil
    elseif GetTime() - F.pending.at > TAKEOFF_WINDOW then
      F.pending = nil
    end
  end
  if F.flight then
    if onTaxi then render() else land() end
  end
end

-- After a reload (or relog) in the air: carry on with the saved flight, or drop a stale one.
function F.Resume()
  local c = type(UltimateCharDB) == "table" and UltimateCharDB.flight
  if not c then return end
  if F.flight then return end
  if not ns.Safe.read(UnitOnTaxi, "player") then
    UltimateCharDB.flight = nil
    return
  end
  -- GetTime() survives a /reload; time() is the fallback across a restart.
  local byEpoch = GetTime() - (time() - (c.startedAt or time()))
  local start = byEpoch
  if c.startedUp and c.startedUp <= GetTime() and math.abs(c.startedUp - byEpoch) < 5 then start = c.startedUp end
  F.flight = { src = c.src, dest = c.dest, name = c.name, expected = c.expected, start = start }
end

local hooked = false
F.def = ns.Modules:Register({
  key = "flightTimes",
  name = L.MODULE_FLIGHTS,
  description = L.MODULE_FLIGHTS_DESC,
  defaults = { showOnMap = true, showTimer = true, learn = true, locked = false },
  OnEnable = function()
    if not hooked then
      hooked = true
      if type(TaxiNodeOnButtonEnter) == "function" then hooksecurefunc("TaxiNodeOnButtonEnter", F.OnNodeEnter) end
      if type(TakeTaxiNode) == "function" then hooksecurefunc("TakeTaxiNode", F.OnTakeTaxi) end
    end
    ns:On("TAXIMAP_OPENED", F, F.Snapshot)
    ns:On("PLAYER_ENTERING_WORLD", F, F.Resume)
    ns:On("ULT_RESET_POSITIONS", F, function() o().point = nil; if bar:IsShown() then place() end end)
    ns:On("ULT_SETTING_CHANGED", F, function(_, path)
      if path and path:find("^flightTimes") then render() end
    end)
    F.ticker = C_Timer.NewTicker(TICK, F.Tick)
    F.Resume()
  end,
  OnDisable = function()
    ns:OffAll(F)
    if F.ticker then F.ticker:Cancel(); F.ticker = nil end
    F.pending, F.flight = nil, nil
    bar:Hide()
  end,
})

function F.def.BuildSettings(ctx)
  ctx:Checkbox("flightTimes.showOnMap", L.FLIGHT_SHOW_MAP, L.FLIGHT_SHOW_MAP_TIP)
  ctx:Checkbox("flightTimes.showTimer", L.FLIGHT_SHOW_TIMER, L.FLIGHT_SHOW_TIMER_TIP)
  ctx:Checkbox("flightTimes.learn", L.FLIGHT_LEARN, L.FLIGHT_LEARN_TIP)
  ctx:Checkbox("flightTimes.locked", L.LOCK_BAR, L.LOCK_BAR_TIP)
end
