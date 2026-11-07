local ns = __ns
local L = ns.L

-- The client's nameplateMaxDistance, with an optional cap (what the client accepts at most).
local cvar = { nameplateMaxDistance = "20" }
local cap, sets, printed
SetCVar = function(k, v)
  sets[#sets + 1] = k .. "=" .. tostring(v)
  local n = tonumber(v)
  if cap and n and n > cap then v = tostring(cap) end
  cvar[k] = tostring(v)
end
GetCVar = function(k) return cvar[k] end
sets = {}

__boot(nil, {})
local R = ns.NameplateRange
local o = function() return ns.db.targeting.range end

local function capturePrints(fn)
  printed = {}
  local old = ns.Print
  ns.Print = function(_, ...) printed[#printed + 1] = table.concat({ ... }, " ") end
  fn()
  ns.Print = old
end

describe("Nameplate range", function()
  it("is on by default at 41 yards, Classic's own maximum", function()
    assertTrue(o().enabled)
    assertEq(o().yards, 41)
  end)
  it("sets the client's nameplate distance at login and remembers the old value", function()
    assertEq(cvar.nameplateMaxDistance, "41")
    assertEq(o().original, "20")
  end)
  it("follows the slider", function()
    o().yards = 30
    R:Apply()
    assertEq(cvar.nameplateMaxDistance, "30")
    assertEq(o().original, "20", "still the value from before the add-on")
  end)
  it("accepts the client's cap and says so once, instead of fighting it", function()
    cap = 35
    o().yards = 41
    capturePrints(function() R:Apply() end)
    assertEq(cvar.nameplateMaxDistance, "35")
    assertEq(#printed, 1, table.concat(printed, " | "))
    assertTrue(printed[1]:find("35", 1, true) ~= nil)
    sets = {}
    capturePrints(function() R:Apply() end)
    assertEq(#printed, 0, "not again")
    cap = nil
  end)
  it("turning it off puts the old value back", function()
    o().enabled = false
    R:Apply()
    assertEq(cvar.nameplateMaxDistance, "20")
    assertNil(o().original)
    o().enabled = true
  end)
  it("does nothing when the client has no such setting", function()
    cvar.nameplateMaxDistance = nil
    sets = {}
    capturePrints(function() R:Apply() end)
    assertEq(#sets, 0)
    assertEq(printed[1], L.RANGE_UNAVAILABLE)
    cvar.nameplateMaxDistance = "20"
  end)
  it("waits for combat to end", function()
    __inCombat = true
    o().yards = 25
    sets = {}
    R:Apply()
    assertEq(#sets, 0)
    __inCombat = false
    ns.Combat:Flush()
    assertEq(cvar.nameplateMaxDistance, "25")
  end)
  it("re-applies when its settings change", function()
    o().yards = 33
    ns:Fire("ULT_SETTING_CHANGED", "targeting.range.yards")
    assertEq(cvar.nameplateMaxDistance, "33")
  end)
end)
