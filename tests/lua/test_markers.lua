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
    assertEq(a.anim, a.pulse, "pulse animation now")
    assertTrue(a.pulse:IsPlaying() and not a.bob:IsPlaying())
    ns.db.targeting.markers.anim = "none"
    fire()
    assertFalse(a.bob:IsPlaying() or a.pulse:IsPlaying())
    ns.db.targeting.markers.anim = "bob"
  end)
  it("bobs like Blizzard's own bobbing arrow: a repeating eased move up, then down", function()
    ns.db.targeting.markers.anim = "bob"
    fire()
    local bob = M:ForPlate(plateA).bob
    assertEq(bob:GetLooping(), "REPEAT", "no BOUNCE turnaround")
    local up, down = bob.anims[1], bob.anims[2]
    assertEq(up.animType, "Translation"); assertEq(down.animType, "Translation")
    assertTrue(up.offsetY > 0 and down.offsetY == -up.offsetY, "ends where it started")
    assertEq(down.startDelay, up.duration, "down starts as up ends")
    assertEq(up.smoothing, "IN_OUT"); assertEq(down.smoothing, "IN_OUT")
  end)
  it("draws the icon off the pixel grid so it moves in sub-pixel steps", function()
    fire()
    local tex = M:ForPlate(plateA).tex
    assertEq(tex.snapToPixelGrid, false)
    assertEq(tex.texelSnappingBias, 0)
  end)
  it("bobs a longer path by default", function()
    local m = ns.db.targeting.markers
    assertEq(m.animDistance, 16); assertEq(m.animTime, 0.8); assertEq(m.pulseScale, 1.15)
  end)
  it("uses the animation settings and restarts when they change", function()
    local m = ns.db.targeting.markers
    m.anim = "bob"
    fire()
    local a = M:ForPlate(plateA)
    local up, down = a.bob.anims[1], a.bob.anims[2]
    assertEq(up.offsetY, 16); assertEq(down.offsetY, -16)
    assertEq(up.duration, 0.8); assertEq(down.startDelay, 0.8)
    m.animDistance, m.animTime = 20, 1.2
    ns:Fire("ULT_SETTING_CHANGED", "targeting.markers.animDistance")
    fire()
    a = M:ForPlate(plateA)
    up, down = a.bob.anims[1], a.bob.anims[2]
    assertEq(up.offsetY, 20); assertEq(down.offsetY, -20)
    assertEq(up.duration, 1.2); assertEq(down.duration, 1.2); assertEq(down.startDelay, 1.2)
    assertTrue(a.bob:IsPlaying())
    m.anim, m.pulseScale = "pulse", 1.4
    fire()
    assertEq(a.pulse.anims[1].scaleX, 1.4); assertEq(a.pulse.anims[1].duration, 1.2)
    m.anim, m.animDistance, m.animTime, m.pulseScale = "bob", 12, 0.8, 1.15
  end)
end)

describe("Elite markers", function()
  local plate = CreateFrame("Frame")
  local o = ns.db.targeting.markers
  -- The mob under test is second in rank, so nothing here comes from being the top target.
  local function mark(classification, level, kind)
    local byName = {
      A = { name = "A", level = 5, mobs = { { plate = plateA, level = 5 } }, kind = "quest" },
      E = { name = "E", kind = kind or "quest",
        mobs = { { plate = plate, level = level or 12, classification = classification } } },
    }
    ns:Fire("ULT_TARGETS_CHANGED", { "A", "E" }, byName)
    return M:ForPlate(plate)
  end
  local function isGold(c) return c[1] > c[2] and c[2] > c[3] and c[3] < 0.4 end
  local function isSilver(c) return c[3] >= c[2] and c[2] >= c[1] and c[1] > 0.6 end

  it("elites and bosses get a large, opaque gold mark with a spinning burst", function()
    o.anim = "bob"
    for _, case in ipairs({ { "elite", 12 }, { "worldboss", 20 }, { "normal", -1 } }) do
      local f = mark(case[1], case[2])
      assertTrue(isGold(f.tex.vertexColor), case[1] .. " is gold")
      assertTrue(isGold(f.burst.vertexColor), case[1] .. " burst is gold")
      assertTrue(f.tex.desaturated, "the yellow art is desaturated so the tint is true")
      assertTrue(f.burst.shown and f.spin:IsPlaying(), "burst spins")
      assertTrue(f.markerSize > o.size and f.alpha == 1)
    end
  end)
  it("rare elites are silver, whether a quest mob or a rare", function()
    for _, kind in ipairs({ "quest", "rare" }) do
      local f = mark("rareelite", 12, kind)
      assertTrue(isSilver(f.tex.vertexColor) and isSilver(f.burst.vertexColor))
      assertTrue(f.burst.shown and f.spin:IsPlaying())
    end
  end)
  it("ordinary mobs and plain rares have no burst", function()
    for _, case in ipairs({ { "normal" }, { "rare", "rare" } }) do
      local f = mark(case[1], 12, case[2])
      assertFalse(f.burst.shown or f.spin:IsPlaying(), case[1])
      assertFalse(f.tex.desaturated, case[1])
    end
  end)
  it("a marker that was elite turns fully ordinary again", function()
    mark("elite")
    local f = mark("normal")
    assertFalse(f.burst.shown or f.spin:IsPlaying() or f.tex.desaturated)
    assertEq(f.markerSize, o.size)
  end)
  it("doesn't restart the burst on every scan", function()
    local f = mark("elite")
    local plays = f.spin.plays
    mark("elite"); mark("elite")
    assertEq(f.spin.plays, plays)
  end)
  it("keeps the burst but holds it still when animation is off", function()
    o.anim = "none"
    local f = mark("elite")
    assertTrue(f.burst.shown)
    assertFalse(f.spin:IsPlaying())
    o.anim = "bob"
  end)
  it("stops the burst when the marker is released", function()
    local f = mark("elite")
    ns:Fire("ULT_TARGETS_CHANGED", {}, {})
    assertFalse(f.spin:IsPlaying())
  end)
end)

describe("Elite markers with the alert", function()
  it("the elite that plays the elite alert has its gold burst a quarter second later", function()
    local plate, unit = CreateFrame("Frame"), "nameplate1"
    plate.namePlateUnitToken = unit
    C_NamePlate.GetNamePlates = function() return { plate } end
    C_NamePlate.GetNamePlateForUnit = function(u) if u == unit then return plate end end
    UnitGUID = function(u) if u == unit then return "Creature-0-1-2-3-99999-000001" end end
    UnitName = function(u) if u == unit then return "Test Ogre" end end
    UnitLevel = function(u) return u == unit and 12 or 12 end
    UnitClassification = function() return "elite" end
    UnitCanAttack = function() return true end
    ns.QuestIndex.byName = { ["Test Ogre"] = { name = "Test Ogre",
      quests = { { questID = 1, title = "Ogres", objIndex = 1, text = "Test Ogre slain: 0/1", have = 0, need = 1 } } } }
    local heard
    local notify = ns.Alerts.Notify
    ns.Alerts.Notify = function(a) heard = a.soundKey end
    __fire("NAME_PLATE_UNIT_ADDED", unit)
    ns.Alerts.Notify = notify
    assertEq(heard, ns.db.questTargeting.alerts.sounds.elite)
    __advance(0.3)
    local f = M:ForPlate(plate)
    assertTrue(f and f.burst.shown and f.spin:IsPlaying(), "burst is up")
  end)
end)
