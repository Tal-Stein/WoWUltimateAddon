local ns = __ns

-- Settings API stub that records what the add-on registers.
local registered = { categories = {}, addon = {}, settings = {}, inits = {} }
local function newLayout(cat)
  return { AddInitializer = function(self, init) cat.inits[#cat.inits + 1] = init end }
end
local function newCategory(name, parent)
  local cat = { name = name, parent = parent, inits = {}, id = #registered.categories + 1 }
  function cat:GetID() return self.id end
  registered.categories[#registered.categories + 1] = cat
  return cat
end
local function initializer(kind, data)
  local init = { kind = kind, data = data }
  function init:AddModifyPredicate(fn) self.predicate = fn end
  function init:SetParentInitializer(p) self.parentInit = p end
  return init
end
Settings = {
  VarType = { Boolean = "boolean", Number = "number", String = "string" },
  RegisterVerticalLayoutCategory = function(name) local c = newCategory(name); return c, newLayout(c) end,
  RegisterVerticalLayoutSubcategory = function(parent, name) local c = newCategory(name, parent); return c, newLayout(c) end,
  RegisterCanvasLayoutSubcategory = function(parent, frame, name) local c = newCategory(name, parent); c.frame = frame; return c end,
  RegisterAddOnCategory = function(cat) registered.addon[#registered.addon + 1] = cat end,
  RegisterProxySetting = function(cat, var, varType, name, default, get, set)
    local s = { var = var, varType = varType, name = name, default = default, get = get, set = set }
    function s:GetValue() return self.get() end
    function s:SetValue(v) self.set(v) end
    registered.settings[var] = s
    return s
  end,
  CreateCheckbox = function(cat, setting, tooltip)
    local i = initializer("checkbox", { setting = setting, tooltip = tooltip }); cat.inits[#cat.inits + 1] = i; return i
  end,
  CreateSlider = function(cat, setting, options, tooltip)
    local i = initializer("slider", { setting = setting, options = options }); cat.inits[#cat.inits + 1] = i; return i
  end,
  CreateSliderOptions = function(min, max, step)
    return { min = min, max = max, step = step, SetLabelFormatter = function(self, side, fn) self.fmt = fn end }
  end,
  CreateDropdown = function(cat, setting, optionsFn, tooltip)
    local i = initializer("dropdown", { setting = setting, options = optionsFn }); cat.inits[#cat.inits + 1] = i; return i
  end,
  CreateControlTextContainer = function()
    local c = { data = {} }
    function c:Add(value, label) self.data[#self.data + 1] = { value = value, label = label } end
    function c:GetData() return self.data end
    return c
  end,
  OpenToCategory = function(id) registered.opened = id end,
}
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
CreateSettingsListSectionHeaderInitializer = function(name) return initializer("header", { name = name }) end
CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip)
  return initializer("button", { name = name, buttonText = buttonText, onClick = onClick })
end
-- Key bindings registered by Bindings.xml, in the order the client lists them.
local BINDINGS = { "MOVEFORWARD", "HEADER_ULTIMATE", "CLICK UltimateTargetButton:LeftButton", "ULTIMATE_REFRESH",
  "CLICK UltimateQuestItem1:LeftButton", "CLICK UltimateQuestItem2:LeftButton",
  "CLICK UltimateQuestItem3:LeftButton", "CLICK UltimateQuestItem4:LeftButton" }
GetNumBindings = function() return #BINDINGS end
GetBinding = function(i) return BINDINGS[i], "ADDONS" end
CreateKeybindingEntryInitializer = function(bindingIndex, search)
  return initializer("keybinding", { bindingIndex = bindingIndex })
end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }

__boot(nil, {})

local function catByName(name)
  for _, c in ipairs(registered.categories) do if c.name == name then return c end end
end

describe("Settings panel", function()
  it("boots and builds every page without swallowed errors", function()
    assertEq(ns.errorCount, 0, "errors: " .. tostring(ns.lastError))
    assertTrue(#catByName("Quest Targeting").inits > 20, "quest targeting page populated")
  end)
  it("test_panel_registers_all_categories", function()
    local root = catByName("Ultimate")
    assertTrue(root ~= nil, "root category")
    assertEq(registered.addon[1], root, "registered as an AddOn category")
    for _, name in ipairs({ "Targeting", "Quest Targeting", "Rare Scanner", "Quest Items", "Lists & Priorities" }) do
      local c = catByName(name)
      assertTrue(c ~= nil and c.parent == root, "subcategory " .. name)
    end
    for _, key in ipairs({ "questTargeting", "rareScanner", "questItems" }) do
      assertTrue(registered.settings["ULTIMATE_MODULE_" .. key] ~= nil, "module toggle " .. key)
    end
  end)
  it("test_checkbox_writes_db_and_fires_event", function()
    local fired
    ns:On("ULT_SETTING_CHANGED", "t", function(_, path) fired = path end)
    local s = registered.settings["ULTIMATE_questTargeting_filters_hideGrey"]
    assertTrue(s ~= nil, "setting registered with a plain variable name")
    assertEq(s:GetValue(), true)
    s:SetValue(false)
    assertEq(ns.db.questTargeting.filters.hideGrey, false)
    assertEq(fired, "questTargeting.filters.hideGrey")
    assertEq(s.default, true, "default comes from module defaults")
    ns:Off("ULT_SETTING_CHANGED", "t")
  end)
  it("module toggle enables and disables the module", function()
    local s = registered.settings["ULTIMATE_MODULE_rareScanner"]
    s:SetValue(false)
    assertFalse(ns.Modules:IsActive("rareScanner"))
    s:SetValue(true)
    assertTrue(ns.Modules:IsActive("rareScanner"))
  end)
  it("dropdowns map option indexes to stored values", function()
    local s = registered.settings["ULTIMATE_questItems_mode"]
    assertEq(s.varType, "number")
    local idx = s:GetValue()
    assertEq(idx, 1, "relevant is option 1")
    s:SetValue(2)
    assertEq(ns.db.questItems.mode, "always")
    s:SetValue(1)
  end)
  it("ranking priority slots swap criteria", function()
    local slot1 = registered.settings["ULTIMATE_RANK_1"]
    local slot3 = registered.settings["ULTIMATE_RANK_3"]
    assertTrue(slot1 ~= nil and slot3 ~= nil)
    local crit = ns.db.targeting.ranking
    assertEq(crit[1].id, "pinned")
    slot1:SetValue(3) -- option 3 = "remaining" (1=none, 2=pinned, 3=remaining...) resolved through the list below
    local names = {}
    for _, c in ipairs(ns.db.targeting.ranking) do names[#names + 1] = c.id end
    assertEq(ns.db.targeting.ranking[1].id, ns.SettingsPanel.RANK_CHOICES[3].id)
    assertTrue(ns.db.targeting.ranking[1].enabled)
    slot1:SetValue(1) -- none disables slot 1
    assertFalse(ns.db.targeting.ranking[1].enabled)
  end)
  it("opens to the root category", function()
    ns.OpenSettings()
    assertEq(registered.opened, catByName("Ultimate"):GetID())
  end)
end)

describe("Settings review fixes", function()
  it("does not offer a tagged-mob toggle that has no effect", function()
    assertNil(registered.settings["ULTIMATE_questTargeting_filters_hideTapped"])
  end)
end)

describe("Key binding rows", function()
  local function category(name)
    for _, c in ipairs(registered.categories) do if c.name == name then return c end end
  end
  local function keyRows(cat)
    local out = {}
    for _, init in ipairs(cat.inits) do
      if init.kind == "keybinding" then out[#out + 1] = BINDINGS[init.data.bindingIndex] end
    end
    return out
  end
  it("Targeting page has Blizzard's own key binding row for the target key", function()
    local rows = keyRows(category(ns.L.TARGETING))
    assertEq(rows, { "CLICK UltimateTargetButton:LeftButton", "ULTIMATE_REFRESH" })
  end)
  it("Quest Items page has a key row per bindable item button", function()
    local rows = keyRows(category(ns.L.MODULE_QUEST_ITEMS))
    assertEq(#rows, 4)
    assertEq(rows[1], "CLICK UltimateQuestItem1:LeftButton")
  end)
  it("no longer offers the action-bar macro", function()
    for _, init in ipairs(category(ns.L.TARGETING).inits) do
      assertTrue(init.kind ~= "button" or init.data.name ~= "Action bar macro", "macro button removed")
    end
  end)
end)
