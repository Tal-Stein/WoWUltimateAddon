local ADDON, ns = ...

-- Thin wrapper over Blizzard's Settings API (vertical layout + proxy settings) so every option
-- uses Blizzard's own checkboxes, sliders, dropdowns and buttons. Values live in ns.db at a
-- dotted path; every change fires ULT_SETTING_CHANGED(path).
-- Registration data stays plain (strings/numbers), which the Forever client requires.
local B = {}
ns.SettingsBuilder = B

local Ctx = {}
Ctx.__index = Ctx

function B.New(category, layout) return setmetatable({ cat = category, layout = layout }, Ctx) end

local function varName(path) return (string.gsub(path, "%.", "_")) end
local function get(path) return (ns.Tables.getPath(ns.db, path)) end
local function default(path) return (ns.Tables.getPath(ns.DB.defaults, path)) end
local function set(path, value)
  ns.Tables.setPath(ns.db, path, value)
  ns:Fire("ULT_SETTING_CHANGED", path)
end
B.get, B.set = get, set

function Ctx:Header(text)
  self.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

function Ctx:Proxy(var, kind, label, defaultValue, getter, setter)
  return Settings.RegisterProxySetting(self.cat, "ULTIMATE_" .. var, Settings.VarType[kind], label,
    defaultValue, getter, setter)
end

function Ctx:CheckboxFn(var, label, tooltip, defaultValue, getter, setter)
  local setting = self:Proxy(var, "Boolean", label, defaultValue, getter, setter)
  return Settings.CreateCheckbox(self.cat, setting, tooltip)
end

function Ctx:Checkbox(path, label, tooltip)
  return self:CheckboxFn(varName(path), label, tooltip, default(path) and true or false,
    function() return get(path) and true or false end,
    function(v) set(path, v and true or false) end)
end

function Ctx:Slider(path, label, min, max, step, fmt, tooltip)
  local setting = self:Proxy(varName(path), "Number", label, default(path) or min,
    function() return get(path) or min end,
    function(v) set(path, v) end)
  local options = Settings.CreateSliderOptions(min, max, step)
  if fmt and MinimalSliderWithSteppersMixin then
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
  end
  return Settings.CreateSlider(self.cat, setting, options, tooltip)
end

-- Dropdown whose stored value is one of choices[i].value; the Settings value is the index.
function Ctx:DropdownFn(var, label, tooltip, choicesFn, getter, setter, defaultIndex)
  local setting = self:Proxy(var, "Number", label, defaultIndex or 1, getter, setter)
  return Settings.CreateDropdown(self.cat, setting, function()
    local container = Settings.CreateControlTextContainer()
    for i, c in ipairs(choicesFn()) do container:Add(i, c.label) end
    return container:GetData()
  end, tooltip)
end

local function indexOf(choices, value)
  for i, c in ipairs(choices) do if c.value == value then return i end end
  return 1
end

function Ctx:Dropdown(path, label, choices, tooltip)
  local function list() return type(choices) == "function" and choices() or choices end
  return self:DropdownFn(varName(path), label, tooltip, list,
    function() return indexOf(list(), get(path)) end,
    function(i)
      local c = list()[i]
      if c then set(path, c.value) end
    end,
    indexOf(list(), default(path)))
end

-- Blizzard's own key binding row (the one on Options > Key Bindings) for a Bindings.xml command.
-- The Settings panel saves bindings when it closes. Falls back to a button that opens Key Bindings.
local function bindingIndex(command)
  if not (GetNumBindings and GetBinding) then return nil end
  for i = 1, GetNumBindings() do
    if GetBinding(i) == command then return i end
  end
end

function Ctx:Keybinding(command, fallbackLabel)
  local index = bindingIndex(command)
  if index and CreateKeybindingEntryInitializer then
    local init = CreateKeybindingEntryInitializer(index, true)
    self.layout:AddInitializer(init)
    return init
  end
  return self:Button(fallbackLabel, KEY_BINDINGS or "Key Bindings", function()
    if Settings.KEYBINDINGS_CATEGORY_ID then Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID) end
  end)
end

function Ctx:Button(label, buttonText, onClick, tooltip)
  local init = CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true)
  self.layout:AddInitializer(init)
  return init
end
