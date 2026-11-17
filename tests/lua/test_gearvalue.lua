local ns = __ns

local scores, equipped, locs = {}, {}, {}
GetItemInfoInstant = function(link)
  local id = tonumber(string.match(tostring(link), "item:(%d+)"))
  return id, nil, nil, locs[id]
end
GetInventoryItemID = function(unit, slot) return equipped[slot] end
__boot(nil, {})

local GV = ns.GearValue
local function link(id) return "|cffffffff|Hitem:" .. id .. "::::|h[Item]|h|r" end

local function setup()
  GearQuest = { Compare = { ScoreItemStats = function(_, entry) return scores[entry.itemId] or 0 end } }
  scores, equipped, locs = {}, {}, {}
end

describe("GearValue", function()
  it("scores a reward against the equipped item in its slot", function()
    setup()
    locs[100] = "INVTYPE_HAND"; scores[100] = 50
    equipped[10] = 10; scores[10] = 40
    local best = GV:BestUpgrade({ link(100) })
    assertEq(best.newScore, 50); assertEq(best.oldScore, 40)
    assertEq(best.link, link(100))
  end)
  it("picks the reward with the bigger gain", function()
    setup()
    locs[100] = "INVTYPE_HAND"; scores[100] = 50
    locs[101] = "INVTYPE_FEET"; scores[101] = 90
    equipped[10] = 10; scores[10] = 40
    equipped[8] = 8; scores[8] = 45
    assertEq(GV:BestUpgrade({ link(100), link(101) }).newScore, 90)
  end)
  it("treats an empty slot as zero", function()
    setup()
    locs[100] = "INVTYPE_WAIST"; scores[100] = 20
    assertEq(GV:BestUpgrade({ link(100) }).oldScore, 0)
  end)
  it("compares rings against the weaker equipped ring", function()
    setup()
    locs[100] = "INVTYPE_FINGER"; scores[100] = 30
    equipped[11] = 11; scores[11] = 25
    equipped[12] = 12; scores[12] = 10
    assertEq(GV:BestUpgrade({ link(100) }).oldScore, 10)
  end)
  it("says nothing while an item isn't cached yet", function()
    setup()
    locs[100] = "INVTYPE_HAND"
    assertNil(GV:BestUpgrade({ link(100) }))
  end)
  it("needs GearQuestForever", function()
    setup()
    GearQuest = nil
    locs[100] = "INVTYPE_HAND"; scores[100] = 50
    assertNil(GV:BestUpgrade({ link(100) }))
    assertFalse(GV.available())
  end)
  it("ignores rewards that aren't gear", function()
    setup()
    scores[100] = 50
    assertEq(GV:BestUpgrade({ link(100) }), false, "false = no gear, nil = unknown")
    assertEq(GV:BestUpgrade({}), false)
  end)
end)
