local ADDON, ns = ...
local L = ns.L
local B = ns.SettingsBuilder

-- Options > AddOns > Ultimate. Root page: feature toggles + general options. One subcategory per
-- feature, one for the shared Targeting service, and a canvas page for lists and quest priorities.
local Panel = {}
ns.SettingsPanel = Panel

Panel.RANK_CHOICES = {
  { id = nil, label = L.RANK_NONE },
  { id = "pinned", label = L.RANK_PINNED },
  { id = "level", label = L.RANK_LEVEL },
  { id = "remaining", label = L.RANK_REMAINING },
  { id = "health", label = L.RANK_HEALTH },
  { id = "count", label = L.RANK_COUNT },
}

local function fmtSeconds(v) return string.format("%.1f s", v) end
local function fmtInt(v) return string.format("%d", v) end
local function fmtPercent(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
local function fmtLevels(v) return v > 0 and string.format("+%d", v) or tostring(v) end

function Panel.SoundChoices()
  local out = {}
  for _, s in ipairs(ns.Sounds.Catalog()) do out[#out + 1] = { value = s.key, label = s.label } end
  return out
end

Panel.CHANNELS = {
  { value = "Master", label = L.CHANNEL_MASTER },
  { value = "SFX", label = L.CHANNEL_SFX },
  { value = "Dialog", label = L.CHANNEL_DIALOG },
  { value = "Ambience", label = L.CHANNEL_AMBIENCE },
}
Panel.ORIENTATIONS = {
  { value = "HORIZONTAL", label = L.HORIZONTAL },
  { value = "VERTICAL", label = L.VERTICAL },
}

local RAID_ICONS = { L.NONE, L.ICON_STAR, L.ICON_CIRCLE, L.ICON_DIAMOND, L.ICON_TRIANGLE, L.ICON_MOON,
  L.ICON_SQUARE, L.ICON_CROSS, L.ICON_SKULL }

-- A sound dropdown plus a "Preview" button row.
function Panel.SoundRow(ctx, path, label, channelPath)
  ctx:Dropdown(path, label, Panel.SoundChoices)
  ctx:Button("", L.PREVIEW, function() ns.Sounds.Play(B.get(path), B.get(channelPath)) end)
end

local function buildRoot(ctx)
  ctx:Header(L.SECTION_FEATURES)
  for def in ns.Modules:Iterate() do
    local key = def.key
    ctx:CheckboxFn("MODULE_" .. key, def.name, def.description, def.defaultEnabled ~= false,
      function() return ns.Modules:IsEnabled(key) end,
      function(v) ns.Modules:SetEnabled(key, v) end)
  end
  ctx:Header(L.SECTION_GENERAL)
  ctx:CheckboxFn("MINIMAP", L.MINIMAP_BUTTON, L.MINIMAP_BUTTON_TIP, true,
    function() return not ns.db.core.minimap.hide end,
    function(v) B.set("core.minimap.hide", not v) end)
  ctx:Checkbox("core.lockAll", L.LOCK_ALL, L.LOCK_ALL_TIP)
  ctx:Button(L.BAR_POSITIONS, L.RESET, function() ns:Fire("ULT_RESET_POSITIONS") end, L.BAR_POSITIONS_TIP)
  ctx:Slider("core.scanInterval", L.SCAN_INTERVAL, 0.2, 2, 0.1, fmtSeconds, L.SCAN_INTERVAL_TIP)
  ctx:Checkbox("core.debug", L.DEBUG, L.DEBUG_TIP)
  local scopes = { { value = "char", label = L.SCOPE_CHAR }, { value = "account", label = L.SCOPE_ACCOUNT } }
  ctx:DropdownFn("SCOPE", L.SCOPE, L.SCOPE_TIP, function() return scopes end,
    function() return ns.global.scope == "account" and 2 or 1 end,
    function(i)
      local v = scopes[i] and scopes[i].value or "account"
      if v ~= ns.global.scope then
        ns.global.scope = v
        if StaticPopup_Show then StaticPopup_Show("ULTIMATE_RELOAD") end
      end
    end, 2)
end

local function rankSlot(ctx, i)
  local choices = Panel.RANK_CHOICES
  ctx:DropdownFn("RANK_" .. i, string.format(L.RANK_SLOT, i), L.RANK_SLOT_TIP, function() return choices end,
    function()
      local c = ns.db.targeting.ranking[i]
      if not c or not c.enabled then return 1 end
      for idx, ch in ipairs(choices) do if ch.id == c.id then return idx end end
      return 1
    end,
    function(choice)
      local crit = ns.db.targeting.ranking
      if not crit[i] then return end
      if choice == 1 or not choices[choice] then
        crit[i].enabled = false
      else
        local id = choices[choice].id
        for j, c in ipairs(crit) do
          if c.id == id then crit[i], crit[j] = crit[j], crit[i]; break end
        end
        crit[i].enabled = true
      end
      ns:Fire("ULT_SETTING_CHANGED", "targeting.ranking")
    end, 1)
end

local function buildTargeting(ctx)
  ctx:Header(L.SECTION_KEY)
  ctx:Keybinding("CLICK UltimateTargetButton:LeftButton", L.KEY_BINDING)
  ctx:Keybinding("ULTIMATE_REFRESH", BINDING_NAME_ULTIMATE_REFRESH)
  ctx:Checkbox("targeting.autoArm", L.AUTO_ARM, L.AUTO_ARM_TIP)
  ctx:Checkbox("targeting.stopInCombat", L.STOP_IN_COMBAT, L.STOP_IN_COMBAT_TIP)
  ctx:Slider("targeting.fallbacks", L.FALLBACKS, 0, 4, 1, fmtInt, L.FALLBACKS_TIP)
  ctx:DropdownFn("targeting_marker", L.RAID_MARKER, L.RAID_MARKER_TIP,
    function()
      local out = {}
      for i, label in ipairs(RAID_ICONS) do out[i] = { value = i - 1, label = label } end
      return out
    end,
    function() return (ns.db.targeting.marker or 0) + 1 end,
    function(i) B.set("targeting.marker", i - 1) end, 1)
  ctx:Checkbox("targeting.markerSoloOnly", L.MARKER_SOLO, L.MARKER_SOLO_TIP)

  ctx:Header(L.SECTION_PRIORITY)
  ctx:Checkbox("targeting.rareFirst", L.RARE_FIRST, L.RARE_FIRST_TIP)
  for i = 1, #ns.db.targeting.ranking do rankSlot(ctx, i) end
  ctx:CheckboxFn("RANK_LEVEL_DESC", L.HIGHEST_LEVEL_FIRST, L.HIGHEST_LEVEL_FIRST_TIP, false,
    function()
      for _, c in ipairs(ns.db.targeting.ranking) do if c.id == "level" then return c.desc and true or false end end
      return false
    end,
    function(v)
      for _, c in ipairs(ns.db.targeting.ranking) do if c.id == "level" then c.desc = v and true or false end end
      ns:Fire("ULT_SETTING_CHANGED", "targeting.ranking")
    end)

  ctx:Header(L.SECTION_BAR)
  ctx:Checkbox("targeting.bar.enabled", L.SHOW_BAR, L.SHOW_BAR_TIP)
  ctx:Checkbox("targeting.bar.portraits", L.BAR_PORTRAITS, L.BAR_PORTRAITS_TIP)
  ctx:Slider("targeting.bar.max", L.MAX_BUTTONS, 1, 24, 1, fmtInt)
  ctx:Slider("targeting.bar.perRow", L.PER_ROW, 1, 12, 1, fmtInt, L.PER_ROW_TIP)
  ctx:Dropdown("targeting.bar.orientation", L.ORIENTATION, Panel.ORIENTATIONS)
  ctx:Slider("targeting.bar.scale", L.SCALE, 0.5, 2, 0.05, fmtPercent)
  ctx:Checkbox("targeting.bar.locked", L.LOCK_BAR, L.LOCK_BAR_TIP)

  ctx:Header(L.SECTION_MARKERS)
  ctx:Checkbox("targeting.markers.enabled", L.SHOW_MARKERS, L.SHOW_MARKERS_TIP)
  ctx:Slider("targeting.markers.size", L.MARKER_SIZE, 16, 96, 2, fmtInt)
  ctx:Slider("targeting.markers.offset", L.MARKER_OFFSET, -20, 80, 1, fmtInt)
  ctx:Dropdown("targeting.markers.colorMode", L.MARKER_COLOR, {
    { value = "difficulty", label = L.COLOR_DIFFICULTY }, { value = "gold", label = L.COLOR_GOLD } })
  ctx:Dropdown("targeting.markers.anim", L.MARKER_ANIM, {
    { value = "bob", label = L.ANIM_BOB }, { value = "pulse", label = L.ANIM_PULSE }, { value = "none", label = L.NONE } })
  ctx:Slider("targeting.markers.animDistance", L.MARKER_ANIM_DISTANCE, 2, 30, 1, fmtInt, L.MARKER_ANIM_DISTANCE_TIP)
  ctx:Slider("targeting.markers.animTime", L.MARKER_ANIM_TIME, 0.2, 2, 0.1, fmtSeconds, L.MARKER_ANIM_TIME_TIP)
  ctx:Slider("targeting.markers.pulseScale", L.MARKER_PULSE_SCALE, 1.05, 1.5, 0.05, fmtPercent, L.MARKER_PULSE_SCALE_TIP)
  ctx:Checkbox("targeting.markers.topOnly", L.MARKER_TOP_ONLY, L.MARKER_TOP_ONLY_TIP)
end

Panel.fmt = { seconds = fmtSeconds, int = fmtInt, percent = fmtPercent, levels = fmtLevels }

function Panel:Register()
  if self.root or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
  local root, layout = Settings.RegisterVerticalLayoutCategory(L.ADDON_TITLE)
  self.root = root
  buildRoot(B.New(root, layout))

  local cat, sub = Settings.RegisterVerticalLayoutSubcategory(root, L.TARGETING)
  buildTargeting(B.New(cat, sub))

  for def in ns.Modules:Iterate() do
    if def.BuildSettings then
      local c, l = Settings.RegisterVerticalLayoutSubcategory(root, def.name)
      ns.SafeCall(def.BuildSettings, B.New(c, l))
    end
  end

  if ns.ListsPage then ns.SafeCall(ns.ListsPage.Register, ns.ListsPage, root) end
  Settings.RegisterAddOnCategory(root)
end

function ns.OpenSettings()
  if InCombatLockdown() then ns:Print(L.SETTINGS_IN_COMBAT); return end
  if Panel.root and Settings and Settings.OpenToCategory then Settings.OpenToCategory(Panel.root:GetID()) end
end

function Ultimate_OnCompartmentClick() ns.OpenSettings() end

if StaticPopupDialogs then
  StaticPopupDialogs.ULTIMATE_RELOAD = {
    text = L.RELOAD_PROMPT, button1 = L.RELOAD, button2 = L.LATER,
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
end

ns:On("ULT_MODULES_STARTED", Panel, function() Panel:Register() end)
