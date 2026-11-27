local ns = __ns

local function guid(npc, spawn) return "Creature-0-1-0-12-" .. npc .. "-" .. (spawn or "0000AA") end
local PLAYER = "Player-1-0000001"
local loot = {}   -- slots: { type = 1|2, link, sources = { guid, qty, guid, qty } }
GetNumLootItems = function() return #loot end
GetLootSlotType = function(i) return loot[i].type end
GetLootSlotLink = function(i) return loot[i].link end
GetLootSourceInfo = function(i) return unpack(loot[i].sources) end
Enum = Enum or {}
Enum.LootSlotType = { None = 0, Item = 1, Money = 2, Currency = 3 }
UnitGUID = function(u) if u == "player" then return PLAYER end end
C_Map = { GetBestMapForUnit = function() return 1436 end }
C_SkillInfo = { GetSkillLineInfoByID = function(id) if id == 393 then return { name = "Skinning", rank = 50 } end end }
C_Spell = { GetSpellName = function(id) return ({ [8613] = "Skinning", [133] = "Fireball" })[id] end }
local combat = {}
CombatLogGetCurrentEventInfo = function() return unpack(combat) end

__boot(nil, {})
local KL = ns.KillLog

local function coin(g, copper) return { type = 2, sources = { g, copper } } end
local function item(g, id, qty) return { type = 1, link = "|cff9d9d9d|Hitem:" .. id .. "::::|h[x]|h|r", sources = { g, qty } } end
local function openLoot(slots)
  loot = slots
  __fire("LOOT_READY")
  __fire("LOOT_CLOSED")
end

describe("Recording your kills", function()
  it("counts a looted corpse as a kill, with its coin and items", function()
    openLoot({ coin(guid(116, "A1"), 31), item(guid(116, "A1"), 2589, 2) })
    local s = KL.Stats()[116]
    assertEq(s.kills, 1)
    assertEq(s.copper, 31)
    assertEq(s.items[2589], 2)
    assertEq(s.maps[1436], 1)
  end)
  it("doesn't count the same corpse twice when reopened", function()
    openLoot({ item(guid(116, "A1"), 2589, 2) })
    local s = KL.Stats()[116]
    assertEq(s.kills, 1)
    assertEq(s.items[2589], 2)
  end)
  it("splits area loot between the corpses it came from", function()
    openLoot({ { type = 2, sources = { guid(116, "B1"), 20, guid(116, "B2"), 40 } } })
    local s = KL.Stats()[116]
    assertEq(s.kills, 3)
    assertEq(s.copper, 91)
  end)
  it("counts kills that left nothing to loot, from the combat log", function()
    combat = { 0, "PARTY_KILL", false, PLAYER, "Me", 0, 0, guid(116, "C1"), "Defias Bandit", 0, 0 }
    __fire("COMBAT_LOG_EVENT_UNFILTERED")
    assertEq(KL.Stats()[116].kills, 4)
    openLoot({ coin(guid(116, "C1"), 10) })
    assertEq(KL.Stats()[116].kills, 4, "the later loot doesn't count it again")
    assertEq(KL.Stats()[116].copper, 101)
  end)
  it("records skinning separately", function()
    __fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 8613)
    openLoot({ item(guid(116, "A1"), 2318, 1) })
    local s = KL.Stats()[116]
    assertEq(s.skinned, 1)
    assertEq(s.skins[2318], 1)
    assertNil(s.items[2318])
    assertEq(s.kills, 4)
  end)
  it("ignores other players' and non-creature loot", function()
    openLoot({ item("GameObject-0-1-0-12-1731-00", 2770, 2) })
    assertNil(KL.Stats()[1731])
  end)
  it("times your kills for gold per hour, ignoring long breaks", function()
    local pace = KL.Pace()
    local n = pace.n
    __time = __time + 20
    openLoot({ coin(guid(116, "D1"), 5) })
    __time = __time + 25
    openLoot({ coin(guid(116, "D2"), 5) })
    __time = __time + 600
    openLoot({ coin(guid(116, "D3"), 5) })
    assertEq(pace.n, n + 2)
  end)
  it("records nothing with recording switched off", function()
    ns.db.farming.recordKills = false
    openLoot({ coin(guid(500, "E1"), 5) })
    assertNil(KL.Stats()[500])
    ns.db.farming.recordKills = true
  end)
end)
