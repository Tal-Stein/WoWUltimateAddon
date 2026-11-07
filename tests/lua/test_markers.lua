local ns = __ns
local M = ns.Markers

C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
__boot(nil, {})

local plateA, plateB, plateT = CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame")

local function fire()
  local byName = {
    A = { name = "A", level = 5, mobs = { { plate = plateA, tapped = false, level = 5 } }, kind = "quest" },
    B = { name = "B", level = 6, mobs = { { plate = plateB, tapped = false, level = 6 }, { plate = plateT, tapped = true } }, kind = "rare" },
  }
  ns:Fire("ULT_TARGETS_CHANGED", { "A", "B" }, byName)
end

describe("Markers", function()
  it("marks untagged quest mobs, top one larger", function()
    fire()
    local a, b, t = M:ForPlate(plateA), M:ForPlate(plateB), M:ForPlate(plateT)
    assertTrue(a ~= nil and b ~= nil, "both marked")
    assertNil(t, "tagged mob not marked")
    assertTrue(a.markerSize > ns.db.targeting.markers.size, "top-ranked is larger")
    assertTrue(b.isRare, "rare variant")
  end)
  it("releases markers when names drop out", function()
    fire()
    ns:Fire("ULT_TARGETS_CHANGED", {}, {})
    assertNil(M:ForPlate(plateA))
    assertEq(M:ActiveCount(), 0)
  end)
  it("top-only and disabled settings", function()
    ns.db.targeting.markers.topOnly = true
    fire()
    assertNil(M:ForPlate(plateB))
    ns.db.targeting.markers.topOnly = false
    ns.db.targeting.markers.enabled = false
    fire()
    assertEq(M:ActiveCount(), 0)
    ns.db.targeting.markers.enabled = true
  end)
end)
