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

describe("QuestItems review fixes", function()
  it("shift-click pins exactly once per click (down+up)", function()
    setup()
    QIt.Update()
    IsShiftKeyDown = function() return true end
    local b = UltimateQuestItem1
    local id = b.itemID
    b.scripts.OnClick(b, "LeftButton", true)
    b.scripts.OnClick(b, "LeftButton", false)
    assertTrue(ns.db.questItems.pinned[id] == true, "pinned after one full click")
    IsShiftKeyDown = function() return false end
    ns.db.questItems.pinned[id] = nil
  end)
  it("disabling the module clears item attributes so bound keys do nothing", function()
    setup()
    QIt.Update()
    ns.Modules:SetEnabled("questItems", false)
    assertNil(UltimateQuestItem1:GetAttribute("item"))
    ns.Modules:SetEnabled("questItems", true)
  end)
end)

describe("QuestItems right-click menu", function()
  -- Minimal MenuUtil stand-in: records what the generator builds.
  local shown
  local function newRoot()
    local root = { entries = {} }
    local function add(kind, text, a, b, c)
      local e = { kind = kind, text = text, a = a, b = b, c = c }
      root.entries[#root.entries + 1] = e
      return e
    end
    function root:CreateTitle(t) return add("title", t) end
    function root:CreateButton(t, fn) return add("button", t, fn) end
    function root:CreateCheckbox(t, isSel, set) return add("checkbox", t, isSel, set) end
    function root:CreateRadio(t, isSel, set, v) return add("radio", t, isSel, set, v) end
    function root:CreateDivider() return add("divider") end
    return root
  end
  MenuUtil = { CreateContextMenu = function(owner, gen)
    local root = newRoot()
    gen(owner, root)
    shown = { owner = owner, root = root }
  end }
  local function entry(text)
    for _, e in ipairs(shown.root.entries) do if e.text == text then return e end end
  end
  local L = ns.L

  it("right-click never uses the item", function()
    local b = QIt.buttons[1]
    assertEq(b:GetAttribute("type2"), "macro")
    assertEq(b:GetAttribute("macrotext2"), "")
  end)
  it("right-click on a button opens the menu once per click", function()
    shown = nil
    local b = QIt.buttons[1]
    b.itemID = 600
    b:GetScript("OnClick")(b, "RightButton", true)
    assertNil(shown, "nothing on the down stroke")
    b:GetScript("OnClick")(b, "RightButton", false)
    assertTrue(shown ~= nil and shown.owner == b)
    assertEq(shown.root.entries[1].text, L.MODULE_QUEST_ITEMS)
  end)
  it("left-click does not open the menu", function()
    shown = nil
    local b = QIt.buttons[1]
    b:GetScript("OnClick")(b, "LeftButton", false)
    assertNil(shown)
  end)
  it("offers pin, lock, show mode and settings", function()
    local b = QIt.buttons[1]
    b.itemID = 600
    ns.db.questItems.pinned[600] = nil
    QIt.ShowMenu(b)
    entry(L.ITEM_MENU_PIN).b()
    assertTrue(ns.db.questItems.pinned[600], "pin toggles")
    ns.db.questItems.pinned[600] = nil
    local lock = entry(L.LOCK_BAR)
    assertFalse(lock.a())
    lock.b()
    assertTrue(ns.db.questItems.locked)
    ns.db.questItems.locked = false
    local always = entry(L.ITEM_MODE_ALWAYS)
    always.b(always.c)
    assertEq(ns.db.questItems.mode, "always")
    ns.db.questItems.mode = "relevant"
    assertTrue(entry(L.ITEM_MODE_RELEVANT).a(entry(L.ITEM_MODE_RELEVANT).c))
    local opened = false
    ns.OpenSettings = function() opened = true end
    entry(L.OPEN_SETTINGS).a()
    assertTrue(opened)
  end)
  it("the title bar opens the menu too, without the pin entry", function()
    shown = nil
    QIt.handle:GetScript("OnMouseUp")(QIt.handle, "RightButton")
    assertTrue(shown ~= nil)
    assertNil(entry(L.ITEM_MENU_PIN))
  end)
  it("Hide turns the feature off, also in combat, and says how to get it back", function()
    QIt.ShowMenu(QIt.buttons[1])
    __inCombat = true
    entry(L.ITEM_MENU_HIDE).a()
    assertFalse(ns.Modules:IsEnabled("questItems"))
    __inCombat = false
    ns.Combat:Flush()
    assertFalse(QIt.frame:IsShown())
    ns.Modules:SetEnabled("questItems", true)
  end)
end)

describe("QuestItems button art", function()
  it("keeps the template's own button size and scales the bar instead", function()
    setup()
    ns.db.questItems.mode = "always"
    local resized = 0
    for _, b in ipairs(QIt.buttons) do
      b.GetWidth = function() return 45 end
      b.SetSize = function() resized = resized + 1 end
    end
    QIt.native = nil
    QIt.Update()
    assertEq(resized, 0, "buttons are never resized, so the template art stays centred")
    assertTrue(math.abs(QIt.barScale - 36 / 45) < 1e-6, "bar scaled to look 36px")
    ns.db.questItems.scale = 2
    QIt.Update()
    assertTrue(math.abs(QIt.barScale - 2 * 36 / 45) < 1e-6, "user scale still applies")
    ns.db.questItems.scale = 1
    ns.db.questItems.mode = "relevant"
  end)
end)

describe("UltimateQuestItem click handler", function()
  it("a mouse click reaches the secure action, not the flyout handler", function()
    for i = 1, 4 do
      assertEq(_G["UltimateQuestItem" .. i].clickHandler, "secure", "SecureActionButtonTemplate must be applied last")
    end
  end)
end)
