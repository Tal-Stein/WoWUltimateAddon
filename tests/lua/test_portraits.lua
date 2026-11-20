local ns = __ns

local displayOf = { nameplate3 = 4211, target = 2595 }
local names = { nameplate3 = "Murloc Streamrunner", target = "Mother Fang" }
UnitName = function(unit) return names[unit] end
UnitExists = function(unit) return names[unit] ~= nil end
UnitIsPlayer = function() return false end
local drawn = {}
SetPortraitTextureFromCreatureDisplayID = function(tex, id) drawn[#drawn + 1] = { tex = tex, id = id } end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }

__boot(nil, {})

local P = ns.Portraits
-- The hidden model reports the display of whatever unit was last loaded into it.
P.model.SetUnit = function(self, unit) self.unit = unit end
P.model.GetDisplayInfo = function(self) return displayOf[self.unit] or 0 end

describe("Portraits", function()
  it("learns a mob's display from a unit and remembers it by name, account-wide", function()
    ns.global.displayIds = {}
    P:Learn("nameplate3")
    assertEq(ns.global.displayIds["Murloc Streamrunner"], 4211)
  end)
  it("draws a remembered portrait for a mob with no nameplate", function()
    ns.global.displayIds = { ["Murloc Streamrunner"] = 4211 }
    drawn = {}
    local tex = CreateFrame("Frame"):CreateTexture()
    assertTrue(P:Apply(tex, "Murloc Streamrunner"))
    assertEq(drawn[1].id, 4211)
    assertTrue(drawn[1].tex == tex)
    assertFalse(P:Apply(tex, "Never Seen"))
  end)
  it("learns when you target or mouse over a mob", function()
    ns.global.displayIds = {}
    __fire("PLAYER_TARGET_CHANGED")
    assertEq(ns.global.displayIds["Mother Fang"], 2595)
  end)
  it("ignores players and units whose model isn't loaded yet", function()
    ns.global.displayIds = {}
    UnitIsPlayer = function() return true end
    P:Learn("target")
    assertNil(ns.global.displayIds["Mother Fang"])
    UnitIsPlayer = function() return false end
    displayOf.target = 0
    P:Learn("target")
    assertNil(ns.global.displayIds["Mother Fang"])
    displayOf.target = 2595
  end)
  it("the target bar uses it for far-away entries", function()
    ns.global.displayIds = { ["Murloc Streamrunner"] = 4211 }
    drawn = {}
    local b = UltimateTargetBarButton1
    b.icon = b.icon or b:CreateTexture()
    names.target = nil
    ns:Fire("ULT_TARGETS_CHANGED", { "Murloc Streamrunner" },
      { ["Murloc Streamrunner"] = { name = "Murloc Streamrunner", count = 1, kind = "quest", mobs = {}, farAway = true } })
    assertTrue(#drawn >= 1 and drawn[#drawn].id == 4211)
    assertTrue(b.badge:IsShown(), "small quest badge in the corner, like other portraits")
  end)
end)
