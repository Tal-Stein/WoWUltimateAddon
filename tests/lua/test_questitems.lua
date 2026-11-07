local ns = __ns

UnitName = function(unit) return __targetName end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
GetZoneText = function() return "Westfall" end
local special = {}
GetQuestLogSpecialItemInfo = function(logIndex) return special[logIndex] end
local bags = {}
C_Container = {
  GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
  GetContainerItemInfo = function(bag, slot) local b = bags[bag] and bags[bag][slot]; return b and { itemID = b.itemID, stackCount = 1 } end,
  GetContainerItemQuestInfo = function(bag, slot) local b = bags[bag] and bags[bag][slot]; return b and b.quest or {} end,
  GetItemCooldown = function() return 0, 0, 1 end,
}
local usable = { [600] = true, [601] = true, [700] = true }
C_Item = {
  GetItemSpell = function(id) if usable[id] then return "Use", 1 end end,
  GetItemIconByID = function() return 134400 end,
  GetItemCount = function() return 1 end,
  PickupItem = function() end,
}
C_QuestLog = { GetNumQuestLogEntries = function() return 0 end, IsOnMap = function(id) return false end }

__boot(nil, {})
local QIt = ns.QuestItemsModule
local QI = ns.QuestIndex

local function setup()
  QI.quests = {
    [100] = { questID = 100, title = "Murloc Menace", header = "Westfall", logIndex = 2, npcNames = { Murloc = true } },
    [200] = { questID = 200, title = "Far Away", header = "Duskwood", logIndex = 4, npcNames = { Wolf = true } },
  }
  special = { [2] = "|cffffffff|Hitem:600::::::::|h[Torch]|h|r", [4] = "|cffffffff|Hitem:700::::::::|h[Bell]|h|r" }
  bags = { [0] = {
    { itemID = 600, quest = { isQuestItem = true, questID = 100, isActive = true } },
    { itemID = 601, quest = { isQuestItem = true, questID = 200, isActive = true } },
    { itemID = 602, quest = { isQuestItem = true, questID = 200 } }, -- not usable
    { itemID = 9 },
  } }
end

describe("QuestItems.Collect", function()
  it("test_collect_special_and_bag_items", function()
    setup()
    local items = QIt.Collect()
    local ids = {}
    for _, it in ipairs(items) do ids[#ids + 1] = it.itemID end
    table.sort(ids)
    assertEq(ids, { 600, 601, 700 }, "deduped, only usable quest items")
    for _, it in ipairs(items) do
      if it.itemID == 600 then
        assertEq(it.questID, 100)
        assertTrue(it.questZoneMatch)
        assertTrue(it.npcNames.Murloc)
      end
      if it.itemID == 700 then assertFalse(it.questZoneMatch) end
    end
  end)
end)

describe("QuestItems layout", function()
  local function shownIds()
    local out = {}
    for i = 1, 8 do
      local b = _G["UltimateQuestItem" .. i]
      if b:IsShown() then out[#out + 1] = b:GetAttribute("item") end
    end
    return out
  end
  it("relevant mode shows zone items, the target's item and pinned items", function()
    setup()
    QIt.Update()
    assertEq(shownIds(), { "item:600" }, "only the Westfall quest item")
    __targetName = "Wolf"
    QIt.Update()
    assertEq(#shownIds(), 3, "targeting a Duskwood quest mob adds both Duskwood items")
    __targetName = nil
    ns.db.questItems.pinned[700] = true
    QIt.Update()
    assertEq(#shownIds(), 2)
    ns.db.questItems.pinned[700] = nil
  end)
  it("always mode shows everything up to max", function()
    setup()
    ns.db.questItems.mode = "always"
    ns.db.questItems.max = 2
    QIt.Update()
    assertEq(#shownIds(), 2)
    ns.db.questItems.mode = "relevant"
    ns.db.questItems.max = 4
  end)
  it("test_layout_deferred_in_combat", function()
    setup()
    QIt.Update()
    local errors = ns.errorCount
    __inCombat = true
    ns.db.questItems.mode = "always"
    QIt.Update()
    assertEq(ns.errorCount, errors, "no blocked actions: " .. tostring(ns.lastError))
    assertEq(#shownIds(), 1, "unchanged during combat")
    __inCombat = false
    __fire("PLAYER_REGEN_ENABLED")
    assertEq(#shownIds(), 3)
    ns.db.questItems.mode = "relevant"
  end)
  it("buttons use secure item actions", function()
    setup()
    QIt.Update()
    assertEq(UltimateQuestItem1:GetAttribute("type"), "item")
    assertTrue(UltimateQuestItem1.secure)
  end)
end)
