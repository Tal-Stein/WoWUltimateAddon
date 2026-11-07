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
  it("keeps the animation running across scans instead of restarting it", function()
    ns.db.targeting.markers.anim = "bob"
    fire()
    local a = M:ForPlate(plateA)
    local before = a.anim.plays
    assertTrue(a.anim:IsPlaying())
    fire(); fire(); fire()
    assertEq(M:ForPlate(plateA), a, "same marker frame")
    assertEq(a.anim.plays, before, "not restarted on every scan")
  end)
  it("restarts the animation only when the style changes", function()
    ns.db.targeting.markers.anim = "bob"
    fire()
    local a = M:ForPlate(plateA)
    local before = a.anim.plays
    ns.db.targeting.markers.anim = "pulse"
    fire()
    assertEq(a.anim.plays, before + 1)
    ns.db.targeting.markers.anim = "none"
    fire()
    assertFalse(a.anim:IsPlaying())
    ns.db.targeting.markers.anim = "bob"
  end)
end)
