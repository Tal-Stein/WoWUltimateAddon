local ns = __ns

time = time or os.time
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
