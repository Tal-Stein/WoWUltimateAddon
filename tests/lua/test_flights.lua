local ns = __ns

-- A flight master in Stormwind (node 2): Sentinel Hill (4) is one hop, Lakeshire (5) two hops
-- through Sentinel Hill in this made-up layout, Nowhere (99) has no data at all.
UnitFactionGroup = function() return "Alliance" end
C_Map = { GetBestMapForUnit = function() return 1429 end }
Enum = Enum or {}
Enum.FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 }
local NODES = {
  { nodeID = 2, slotIndex = 1, name = "Stormwind, Elwynn", state = 0 },
  { nodeID = 4, slotIndex = 2, name = "Sentinel Hill, Westfall", state = 1 },
  { nodeID = 5, slotIndex = 3, name = "Lakeshire, Redridge", state = 1 },
  { nodeID = 99, slotIndex = 4, name = "Nowhere, Barrens", state = 1 },
}
C_TaxiMap = { GetAllTaxiNodes = function() return NODES end }
local ROUTES = { [2] = { { 1, 2 } }, [3] = { { 1, 2 }, { 2, 3 } }, [4] = { { 1, 4 } } }
GetNumRoutes = function(i) return #(ROUTES[i] or {}) end
TaxiGetNodeSlot = function(i, hop, src) local h = ROUTES[i][hop]; return src and h[1] or h[2] end
TaxiNodeName = function(i) return NODES[i].name end
TaxiNodeGetType = function(i) return i == 1 and "CURRENT" or "REACHABLE" end
local onTaxi = false
UnitOnTaxi = function() return onTaxi end

GameTooltipTextLeft1 = CreateFrame("Frame", nil)
GameTooltip = CreateFrame("Frame", "GameTooltip")
function GameTooltip:AddLine() end
local blizzardEnter = 0
function TaxiNodeOnButtonEnter(button)
  blizzardEnter = blizzardEnter + 1
  GameTooltipTextLeft1:SetText(TaxiNodeName(button:GetID())) -- the name line, which may wrap
end
local taken = {}
function TakeTaxiNode(i) taken[#taken + 1] = i end

ns.FlightTimesData = { Alliance = { [2] = { [4] = 86 }, [4] = { [5] = 130 } } }

__boot(nil, {})
local F = ns.FlightTimesModule

local function button(id) return { GetID = function() return id end } end
local function hover(id)
  TaxiNodeOnButtonEnter(button(id))
  local text = GameTooltipTextLeft1:GetText()
  return text ~= TaxiNodeName(id) and text or nil
end
local function fly(id, seconds)
  __fire("TAXIMAP_OPENED")
  TakeTaxiNode(id)
  __advance(0.5, true)
  onTaxi = true
  __advance(0.1, true)
  for _ = 1, seconds * 10 do __advance(0.1, true) end
end
local function land()
  onTaxi = false
  __advance(0.1, true)
end

describe("Flight times on the flight map", function()
  it("is on by default", function()
    assertTrue(ns.Modules:IsEnabled("flightTimes"))
  end)
  it("adds the flight time to the destination's name, so it wraps with it", function()
    __fire("TAXIMAP_OPENED")
    assertEq(hover(2), "Sentinel Hill, Westfall  |cffffffff1:26|r")
    assertEq(blizzardEnter, 1, "Blizzard's own tooltip still runs")
  end)
  it("adds up the legs of a route with stops", function()
    assertEq(hover(3), "Lakeshire, Redridge  |cffffffff3:36|r")
  end)
  it("shows nothing for an unknown flight or where you stand", function()
    assertNil(hover(4))
    assertNil(hover(1))
  end)
  it("leaves the tooltip alone when switched off", function()
    ns.db.flightTimes.showOnMap = false
    assertNil(hover(2))
    ns.db.flightTimes.showOnMap = true
  end)
end)

describe("Flight timer", function()
  it("counts down to landing with the destination's name", function()
    fly(2, 10)
    assertTrue(F.bar.shown, "bar shown in flight")
    assertEq(F.bar.Text:GetText(), "Sentinel Hill  1:16")
    land()
    assertFalse(F.bar.shown, "bar hidden after landing")
  end)
  it("still lets the game take the flight", function()
    assertEq(taken[#taken], 2)
  end)
  it("remembers how long your own flight took and uses it next time", function()
    fly(2, 80)
    land()
    assertEq(ns.global.flightTimes.Alliance[2][4], 80)
    __fire("TAXIMAP_OPENED")
    assertEq(hover(2), "Sentinel Hill, Westfall  |cffffffff1:20|r")
  end)
  it("counts up when the time isn't known, and learns it", function()
    fly(4, 30)
    assertEq(F.bar.Text:GetText(), "Nowhere  0:30")
    land()
    assertEq(ns.global.flightTimes.Alliance[2][99], 30)
  end)
  it("doesn't learn from a flight that never left", function()
    __fire("TAXIMAP_OPENED")
    TakeTaxiNode(3)
    __advance(6, true)
    __advance(0.1, true)
    assertFalse(F.bar.shown)
    assertNil(ns.global.flightTimes.Alliance[2][5])
  end)
  it("shows no bar with the timer switched off, but still learns", function()
    ns.db.flightTimes.showTimer = false
    fly(3, 20)
    assertFalse(F.bar.shown)
    land()
    assertEq(ns.global.flightTimes.Alliance[2][5], 20)
    ns.db.flightTimes.showTimer = true
  end)
  it("picks the flight up again after a reload in the air", function()
    fly(2, 10)
    -- Reload: in-memory state is gone; the character's saved flight remains (80 s learned above).
    F.flight = nil
    F.bar:Hide()
    __time = __time + 5
    F.Resume()
    __advance(0.1, true)
    assertTrue(F.bar.shown)
    assertEq(F.bar.Text:GetText(), "Sentinel Hill  1:05")
    land()
  end)
  it("forgets a saved flight when you're no longer flying", function()
    UltimateCharDB.flight = { src = 2, dest = 4, name = "Sentinel Hill", expected = 80, startedAt = time() - 10 }
    F.Resume()
    assertNil(UltimateCharDB.flight)
  end)
end)

describe("Flight timer menu", function()
  it("offers lock, hide and settings on right-click", function()
    F.ShowMenu(F.bar)
    assertTrue(__menuEntry(ns.L.LOCK_BAR) ~= nil)
    assertTrue(__menuEntry(ns.L.FLIGHT_MENU_HIDE) ~= nil)
    assertTrue(__menuEntry(ns.L.OPEN_SETTINGS) ~= nil)
    __menuEntry(ns.L.FLIGHT_MENU_HIDE).a()
    assertFalse(ns.db.flightTimes.showTimer)
    ns.db.flightTimes.showTimer = true
  end)
end)
