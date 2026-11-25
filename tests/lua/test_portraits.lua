local ns = __ns

local names = { target = "Mother Fang" }
local guids = { target = "Creature-0-1-0-12-299-0000ABCD" }
UnitName = function(unit) return names[unit] end
UnitGUID = function(unit) return guids[unit] end
UnitExists = function(unit) return names[unit] ~= nil end
UnitIsPlayer = function() return false end
local drawn = {}
SetPortraitTextureFromCreatureDisplayID = function(tex, id) drawn[#drawn + 1] = { tex = tex, id = id } end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }

-- The client: creature -> display, answered only once the creature has "loaded".
local displayOfNpc = { [735] = 4211, [299] = 2595 }
local loaded = {}
local PLAYER_DISPLAY = 49
local function fakeModel()
  local m = { creature = nil }
  function m:Hide() end
  function m:ClearModel() self.creature = nil; self.unit = nil end
  function m:SetCreature(id) self.creature = id; self.unit = nil end
  function m:SetUnit(unit) self.unit = unit end
  function m:GetDisplayInfo()
    if self.unit == "player" then return PLAYER_DISPLAY end
    if self.creature and loaded[self.creature] then return displayOfNpc[self.creature] or 0 end
    if self.creature then return PLAYER_DISPLAY end -- stand-in while the server answers
    return 0
  end
  return m
end

__boot(nil, {})

local P = ns.Portraits
P.NewModel = fakeModel

describe("Portraits", function()
  it("loads a quest mob's portrait from its NPC ID, without ever seeing it", function()
    ns.global.displayIds = {}
    ns.QuestIndex.byName["Murloc Streamrunner"] = { name = "Murloc Streamrunner", npcIds = { [735] = true }, quests = {} }
    local readyFired = 0
    ns:On("ULT_PORTRAIT_READY", {}, function() readyFired = readyFired + 1 end)
    local tex = CreateFrame("Frame"):CreateTexture()
    assertFalse(P:Apply(tex, "Murloc Streamrunner"), "not known yet: starts loading")
    __advance(0.1)
    assertNil(ns.global.displayIds["Murloc Streamrunner"], "the player's look is a stand-in, not the answer")
    loaded[735] = true
    __advance(0.1)
    assertEq(ns.global.displayIds["Murloc Streamrunner"], 4211)
    assertTrue(readyFired >= 1)
    drawn = {}
    assertTrue(P:Apply(tex, "Murloc Streamrunner"))
    assertEq(drawn[1].id, 4211)
  end)
  it("gives up quietly on a creature that never loads", function()
    ns.global.displayIds = {}
    ns.QuestIndex.byName["Ghost Mob"] = { name = "Ghost Mob", npcIds = { [999] = true }, quests = {} }
    P:Request("Ghost Mob")
    for _ = 1, 100 do __advance(0.1) end
    assertNil(P.waiting["Ghost Mob"])
    assertNil(ns.global.displayIds["Ghost Mob"])
  end)
  it("learns an unknown mob's NPC ID from its GUID when you target it", function()
    ns.global.displayIds = {}
    loaded[299] = true
    __fire("PLAYER_TARGET_CHANGED")
    assertEq(P.npcOf["Mother Fang"], 299)
    __advance(0.1)
    assertEq(ns.global.displayIds["Mother Fang"], 2595)
  end)
  it("ignores players", function()
    ns.global.displayIds = {}
    P.npcOf = {}
    UnitIsPlayer = function() return true end
    P:Learn("target")
    assertNil(P.npcOf["Mother Fang"])
    UnitIsPlayer = function() return false end
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
