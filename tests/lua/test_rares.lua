local ns = __ns

UnitLevel = function(unit) if unit == "player" then return 30 end end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
local played, notices = {}, {}
PlaySound = function(kit) played[#played + 1] = kit end
RaidWarningFrame = {}
RaidNotice_AddMessage = function(_, text) notices[#notices + 1] = text end
GetZoneText = function() return "Duskwood" end

__boot(nil, {})
local RS = ns.RareScannerModule

local function mob(over)
  local m = { unit = "nameplate1", guid = "Creature-0-1-0-1-50-01", npcId = 50, name = "Mor'Ladim", level = 35,
    classification = "rareelite", dead = false, tapped = false, attackable = true, isPlayer = false }
  for k, v in pairs(over or {}) do m[k] = v end
  return m
end

local function reset()
  played, notices = {}, {}
  RS.gate = ns.AlertGate.new({ guidCooldown = 300, nameCooldown = 300 })
  RS.history = {}
end

describe("RareScanner", function()
  it("is on by default and registers a provider", function()
    assertTrue(ns.Modules:IsEnabled("rareScanner"))
    assertTrue(ns.Targeting.providers.rare ~= nil)
  end)
  it("test_rare_detection", function()
    assertTrue(RS.IsRare(mob()))
    assertTrue(RS.IsRare(mob({ classification = "rare" })))
    assertTrue(RS.IsRare(mob({ classification = "worldboss" })))
    assertFalse(RS.IsRare(mob({ classification = "elite" })))
    ns.db.rareScanner.watch["Hogger"] = true
    assertTrue(RS.IsRare(mob({ classification = "normal", name = "Hogger" })), "watch list")
    ns.db.rareScanner.watch["Hogger"] = nil
  end)
  it("alerts once with sound, text and history", function()
    reset()
    RS.OnMobAdded(mob())
    RS.OnMobAdded(mob())
    assertEq(#played, 1)
    assertTrue(notices[1]:find("Mor'Ladim", 1, true) ~= nil)
    assertEq(#RS.history, 1)
    assertEq(RS.history[1].zone, "Duskwood")
  end)
  it("test_rare_tagged_alert_no_candidate", function()
    reset()
    RS.OnMobAdded(mob({ tapped = true }))
    assertTrue(notices[1]:find("tagged", 1, true) ~= nil, "tagged suffix")
    assertEq(#RS.Candidates({ mob({ tapped = true }) }), 0, "no candidate for tagged rare")
    reset()
    ns.db.rareScanner.alertTagged = false
    RS.OnMobAdded(mob({ tapped = true }))
    assertEq(#played, 0)
    ns.db.rareScanner.alertTagged = true
  end)
  it("ignores dead or friendly rares", function()
    reset()
    RS.OnMobAdded(mob({ dead = true }))
    RS.OnMobAdded(mob({ attackable = false, guid = "x" }))
    assertEq(#played, 0)
  end)
  it("test_rare_barmode", function()
    local c = RS.Candidates({ mob() })
    assertEq(#c, 1)
    assertTrue(c[1].isRare)
    assertEq(c[1].kind, "rare")
    ns.db.rareScanner.barMode = "ranked"
    c = RS.Candidates({ mob() })
    assertFalse(c[1].isRare, "ranked normally")
    assertEq(c[1].kind, "rare", "still drawn as rare")
    ns.db.rareScanner.barMode = "hidden"
    assertEq(#RS.Candidates({ mob() }), 0)
    ns.db.rareScanner.barMode = "first"
  end)
end)
