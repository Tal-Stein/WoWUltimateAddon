local ns = __ns

time = time or os.time
-- The game's own handlers for blocked actions (Blizzard_Game), which add-ons don't always get an
-- event for.
debugstack = debugstack or function() return debug.traceback() end
HandleAddonActionBlocked = function(addon, func) end
HandleAddonActionForbidden = function(addon, func) end
__boot(nil, {})

local EL = ns.ErrorLog

local function entries() return ns.global.errorLog end

describe("Error log", function()
  it("records Ultimate's own errors with their stack, counting repeats", function()
    EL:Clear()
    local function broken() error("boom") end
    ns.SafeCall(broken)
    ns.SafeCall(broken)
    local e = entries()[1]
    assertEq(#entries(), 1)
    assertEq(e.kind, "lua")
    assertEq(e.count, 2)
    assertTrue(string.find(e.detail, "boom", 1, true) ~= nil)
  end)
  it("records blocked and forbidden actions, naming the add-on and function", function()
    EL:Clear()
    __inCombat = true
    __fire("ADDON_ACTION_BLOCKED", "Ultimate", "UltimateTargetBar:SetPoint()")
    __inCombat = false
    __fire("ADDON_ACTION_FORBIDDEN", "Questie", "TargetUnit()")
    assertEq(#entries(), 2)
    local blocked, forbidden
    for _, e in ipairs(entries()) do
      if e.kind == "blocked" then blocked = e else forbidden = e end
    end
    assertEq(blocked.addon, "Ultimate")
    assertEq(blocked.func, "UltimateTargetBar:SetPoint()")
    assertTrue(blocked.inCombat)
    assertEq(forbidden.addon, "Questie")
  end)
  it("keeps at most 50 different errors, dropping the oldest", function()
    EL:Clear()
    for i = 1, 55 do EL:Record("lua", "e" .. i, "error " .. i) end
    assertEq(#entries(), 50)
    for _, e in ipairs(entries()) do assertTrue(e.key ~= "e1", "oldest dropped") end
  end)
  it("lists and clears with /ult errors", function()
    EL:Clear()
    EL:Record("lua", "x", "something broke")
    local printed = {}
    local print = ns.Print
    ns.Print = function(_, fmt, ...) printed[#printed + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end
    SlashCmdList.ULTIMATE("errors")
    assertTrue(#printed >= 2, table.concat(printed, " | "))
    SlashCmdList.ULTIMATE("errors clear")
    ns.Print = print
    assertEq(#entries(), 0)
  end)
end)

describe("Error log: errors outside Ultimate's own guards", function()
  it("records game-reported Lua errors that run through Ultimate's files, and passes every error on", function()
    EL:Clear()
    local handler = geterrorhandler()
    local passed = {}
    -- the previous handler (Blizzard's) still gets every error
    EL.previousHandler = function(msg) passed[#passed + 1] = msg end
    handler("Interface/AddOns/Ultimate/Services/GradeSurfaces.lua:120: attempt to index a nil value")
    handler("Interface/AddOns/Questie/Modules/Foo.lua:5: something else")
    assertEq(#passed, 2)
    assertEq(#entries(), 1)
    assertEq(entries()[1].kind, "lua")
    assertTrue(string.find(entries()[1].detail, "GradeSurfaces", 1, true) ~= nil)
  end)
end)

describe("Error log: blocked actions the game handles itself", function()
  it("records them from the game's own handler, with the stack that caused them", function()
    EL:Clear()
    local function offender() HandleAddonActionBlocked("SomeAddon", "CastSpellByName()") end
    offender()
    local e = entries()[1]
    assertEq(#entries(), 1)
    assertEq(e.kind, "blocked")
    assertEq(e.addon, "SomeAddon")
    assertEq(e.func, "CastSpellByName()")
    assertTrue(type(e.detail) == "string" and e.detail ~= "", "a stack to find the caller by")
  end)
  it("counts one blocked action once when the event comes too", function()
    EL:Clear()
    HandleAddonActionForbidden("Questie", "TargetUnit()")
    __fire("ADDON_ACTION_FORBIDDEN", "Questie", "TargetUnit()")
    assertEq(#entries(), 1)
    assertEq(entries()[1].count, 1)
  end)
end)
