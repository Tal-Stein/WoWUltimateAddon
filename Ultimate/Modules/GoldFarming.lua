local ADDON, ns = ...
local L = ns.L
local FM = ns.Farming
local FS = ns.FarmSources

-- Gold Farming: grades zones on the world map by what your gathering professions earn there.
--   Continent maps  each zone you can gather in is tinted with the game's own zone highlight in
--                   its grade's color; a panel beside the map lists the best zones for you and
--                   details the zone under the cursor.
--   Zone maps       pins on every node you can gather; the panel details the zone.
-- The toggle sits in the world map's own filter menu. Numbers come from Services/FarmSources.lua.
local G = {}
ns.GoldFarming = G

G.COLORS = {
  excellent = { 1, 0.82, 0 },
  good = { 0.25, 0.9, 0.25 },
  fair = { 0.45, 0.7, 1 },
  poor = { 0.6, 0.6, 0.6 },
}
local SHADE_ALPHA = 0.45
local PIN_SIZE = 12
local PANEL_LINES = 9
local BEST_ZONES = 7
local OLD_SCAN_DAYS = 3
local HOVER_EVERY = 0.1
local ICONS = {
  herbalism = "Interface\\Icons\\INV_Misc_Flower_02",   -- Find Herbs
  mining = "Interface\\Icons\\Spell_Nature_Earthquake", -- Find Minerals
}
-- Points inside a zone's bounding box to try, center first, when looking for a spot on the zone.
local PROBES = { { .5, .5 }, { .4, .5 }, { .6, .5 }, { .5, .4 }, { .5, .6 }, { .3, .3 }, { .7, .3 }, { .3, .7 }, { .7, .7 } }

G.highlights, G.labels, G.pins = {}, {}, {}

local function o() return ns.db.farming end
local function active() return ns.Modules:IsActive("farming") and o().showOnMap end
local function mapTypes() return Enum and Enum.UIMapType or { Continent = 2, Zone = 3 } end

local function mapName(id)
  local info = C_Map and ns.Safe.read(C_Map.GetMapInfo, id)
  return info and info.name or tostring(id)
end

local function colorize(text, c)
  return string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, text)
end

local function gradeText(grade)
  return grade and colorize(L["FARM_GRADE_" .. grade], G.COLORS[grade]) or ""
end

local function money(copper)
  if type(GetCoinTextureString) == "function" then return GetCoinTextureString(copper) end
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then return string.format("%dg %ds %dc", g, s, c) end
  if s > 0 then return string.format("%ds %dc", s, c) end
  return string.format("%dc", c)
end

local function area(mapID)
  if not (C_Map and C_Map.GetMapWorldSize) then return nil end
  local ok, w, h = pcall(C_Map.GetMapWorldSize, mapID)
  if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w * h end
end

------------------------------------------------------------------------------
-- Scores
------------------------------------------------------------------------------
-- Minutes to a zone's center at your current run speed, straight-line; 0 in the zone you're in.
-- nil when your position isn't known or the zone is on another continent.
function G.TravelMinutes(mapID)
  local here = C_Map and ns.Safe.read(C_Map.GetBestMapForUnit, "player")
  if here == mapID then return 0 end
  if not (UnitPosition and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, py, px, _, instance = pcall(UnitPosition, "player")
  if not ok or type(py) ~= "number" or ns.Safe.isSecret(py) then return nil end
  local ok2, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0.5, 0.5))
  if not ok2 or not pos or (instance and continent ~= instance) then return nil end
  local zy, zx = pos:GetXY()
  local speed = 7
  if GetUnitSpeed then
    local ok3, _, run = pcall(GetUnitSpeed, "player")
    if ok3 and type(run) == "number" and run > 0 then speed = run end
  end
  return math.sqrt((zy - py) ^ 2 + (zx - px) ^ 2) / speed / 60
end

local function viewContext()
  return {
    minutes = G.TravelMinutes,
    levels = function(mapID)
      if not (C_Map and C_Map.GetMapLevels) then return nil end
      local ok, lo, hi = pcall(C_Map.GetMapLevels, mapID)
      if ok and type(lo) == "number" and type(hi) == "number" and lo > 0 then return lo, hi end
    end,
    level = ns.Safe.read(UnitLevel, "player"),
  }
end

local function view() return o().view or "best" end

-- Scores are worked out again only after something they depend on changed (G.Invalidate: map
-- opened, skills, prices, kills, settings); browsing the map just redraws.
G.dirty = true
function G.Invalidate() G.dirty = true end

function G.Score()
  if G.dirty or not G.scores then
    G.dirty = false
    G.skills = FS.Skills()
    G.scores = FM.ScoreZones(FS.Zones(), ns.GatherNodes, G.skills, FS.Price, area,
      o().includeMobs ~= false and FS.Mobs(G.skills) or nil)
    G.byMap = {}
    for _, z in ipairs(G.scores) do G.byMap[z.mapID] = z end
  end
  G.viewList = FM.View(G.scores, view(), viewContext())
  G.inView = {}
  for _, z in ipairs(G.viewList) do G.inView[z.mapID] = z end
end

------------------------------------------------------------------------------
-- Panel beside the map
------------------------------------------------------------------------------
local function profLine()
  local parts = {}
  for _, prof in ipairs({ "herbalism", "mining", "skinning" }) do
    if G.skills[prof] then parts[#parts + 1] = L["PROF_" .. prof] .. " " .. G.skills[prof] end
  end
  return table.concat(parts, "  ·  ")
end

-- "50c per kill · 1g/hr (12 kills)"
local function mobValueText(perKill, kills)
  local text = string.format(L.FARM_PER_KILL, money(perKill))
  local hour = FM.PerHour(perKill, ns.KillLog.Pace())
  if hour then text = text .. "  ·  " .. string.format(L.FARM_PER_HOUR, money(hour)) end
  return text .. "  |cff808080(" .. string.format(L.FARM_KILLS, kills) .. ")|r"
end
G.MobValueText = mobValueText

local function entryLine(e)
  if e.kind == "mob" then return e.name .. "  " .. mobValueText(e.price, e.kills) end
  local text = string.format(L.FARM_NODE_COUNT, e.count, e.name)
  if e.status == "unknown" then
    text = text .. "  |cff808080(" .. L.FARM_SKILL_UNKNOWN .. ")|r"
  end
  if e.price then
    text = text .. "  " .. money(e.price)
    if e.source == "vendor" then
      text = text .. " |cff808080(" .. L.FARM_VENDOR .. ")|r"
    elseif e.age and e.age > OLD_SCAN_DAYS then
      text = text .. " |cff808080(" .. string.format(L.FARM_SCAN_AGE, e.age) .. ")|r"
    end
  else
    text = text .. "  |cff808080" .. L.FARM_NO_PRICE .. "|r"
  end
  return text
end

local function panelLines()
  local lines = {}
  local zoneID = (G.mapType == mapTypes().Zone) and G.mapID or G.hover
  if next(G.skills) == nil and #G.scores == 0 then
    lines[1] = L.MODULE_FARMING
    lines[2] = L.FARM_NO_PROFESSION
  elseif zoneID then
    local z = G.byMap[zoneID]
    lines[1] = mapName(zoneID) .. (z and z.grade and ("  " .. gradeText(z.grade)) or "")
    if not z then
      lines[2] = L.FARM_NOTHING
    else
      for _, e in ipairs(z.entries) do
        if #lines >= PANEL_LINES then break end
        lines[#lines + 1] = entryLine(e)
      end
    end
  else
    lines[1] = L["FARM_VIEW_" .. view()]
    lines[2] = profLine()
    local shown = 0
    for _, z in ipairs(G.viewList) do
      if shown >= BEST_ZONES then break end
      shown = shown + 1
      local where = ""
      if z.minutes then
        where = "  |cff808080" .. (z.minutes < 0.5 and L.FARM_HERE or
          string.format(L.FARM_MINUTES, math.max(1, math.floor(z.minutes + 0.5)))) .. "|r"
      elseif z.minLevel then
        where = string.format("  |cff808080(%d-%d)|r", z.minLevel, z.maxLevel)
      end
      lines[#lines + 1] = gradeText(z.grade) .. "  " .. mapName(z.mapID) .. where ..
        "  |cff808080" .. z.entries[1].name .. "|r"
    end
    if shown == 0 then
      local anyGraded = false
      for _, z in ipairs(G.scores) do if z.grade then anyGraded = true end end
      lines[#lines + 1] = anyGraded and L["FARM_EMPTY_" .. view()]
        or (#G.scores > 0 and L.FARM_NO_PRICES or L.FARM_NOTHING)
    end
  end
  return lines
end

------------------------------------------------------------------------------
-- Gold goal (per character, UltimateCharDB.farmGoal in copper)
------------------------------------------------------------------------------
local function goal() return type(UltimateCharDB) == "table" and UltimateCharDB.farmGoal or nil end

-- Your best timed rate among the mobs on show: copper per hour and the mob's name.
local function bestRate(zones)
  local best, name
  for _, z in ipairs(zones) do
    for _, e in ipairs(z.entries or {}) do
      local h = e.kind == "mob" and FM.PerHour(e.price, ns.KillLog.Pace())
      if h and (not best or h > best) then best, name = h, e.name end
    end
  end
  return best, name
end

local function goalLine()
  local target = goal()
  if not target then return nil end
  local zoneID = (G.mapType == mapTypes().Zone) and G.mapID or G.hover
  local zones = zoneID and G.byMap[zoneID] and { G.byMap[zoneID] } or G.viewList or {}
  local rate, mob = bestRate(zones)
  local g = FM.Goal(target, ns.Safe.read(GetMoney), rate)
  local text = string.format(L.FARM_GOAL_LINE, money(target), money(g.left))
  if g.hours then text = text .. "  |cff808080" .. string.format(L.FARM_GOAL_TIME, FM.FormatHours(g.hours), mob) .. "|r" end
  return text
end

function G.CheckGoal()
  local target = goal()
  if not target then return end
  if FM.Goal(target, ns.Safe.read(GetMoney)).reached then
    UltimateCharDB.farmGoal = nil
    ns:Print(L.FARM_GOAL_REACHED)
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 then pcall(PlaySound, SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01) end
  end
  G.RenderPanel()
end

function G.AcceptGoal(copper)
  if type(UltimateCharDB) ~= "table" or type(copper) ~= "number" or copper <= 0 then return end
  if copper <= (ns.Safe.read(GetMoney) or 0) then
    ns:Print(L.FARM_GOAL_ALREADY)
    return
  end
  UltimateCharDB.farmGoal = copper
  G.RenderPanel()
end

-- Our own small dialog with the game's money box (writing StaticPopupDialogs taints the shared
-- popups). Enter accepts, Escape closes.
local function goalFrame()
  if G.goalFrame then return G.goalFrame end
  local f = CreateFrame("Frame", "UltimateFarmGoalFrame", UIParent, "TooltipBackdropTemplate")
  f:SetSize(280, 108)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)
  f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.text:SetPoint("TOP", f, "TOP", 0, -16)
  f.text:SetText(L.FARM_GOAL_PROMPT)
  f.money = CreateFrame("Frame", "UltimateFarmGoalMoney", f, "MoneyInputFrameTemplate")
  f.money:SetPoint("TOP", f.text, "BOTTOM", 12, -12)
  local function accept()
    G.AcceptGoal(MoneyInputFrame_GetCopper and ns.Safe.read(MoneyInputFrame_GetCopper, f.money))
    f:Hide()
  end
  f.ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.ok:SetSize(110, 22)
  f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 14)
  f.ok:SetText(ACCEPT or "Accept")
  f.ok:SetScript("OnClick", accept)
  f.cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.cancel:SetSize(110, 22)
  f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 14)
  f.cancel:SetText(CANCEL or "Cancel")
  f.cancel:SetScript("OnClick", function() f:Hide() end)
  for _, key in ipairs({ "gold", "silver", "copper" }) do
    local box = f.money[key]
    if box and box.HookScript then box:HookScript("OnEnterPressed", accept) end
  end
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "UltimateFarmGoalFrame") end
  f:Hide()
  G.goalFrame = f
  return f
end

function G.SetGoal()
  local f = goalFrame()
  if MoneyInputFrame_ResetMoney then pcall(MoneyInputFrame_ResetMoney, f.money) end
  f:Show()
end

function G.RenderPanel()
  local panel = G.panel
  if not panel then return end
  if not active() or not G.scores then panel:Hide(); return end
  local lines = panelLines()
  local gl = goalLine()
  if gl then lines[#lines + 1] = gl end
  local width = 0
  for i, fs in ipairs(panel.lines) do
    fs:SetText(lines[i] or "")
    fs:SetShown(lines[i] ~= nil)
    local w = lines[i] and fs.GetStringWidth and fs:GetStringWidth()
    if type(w) == "number" and w > width then width = w end
  end
  panel:SetSize(math.max(width, 160) + 20, 14 + 16 + (#lines - 1) * 14)
  panel:Show()
end

local function buildPanel(parent)
  local f = CreateFrame("Frame", "UltimateFarmPanel", parent, "TooltipBackdropTemplate")
  f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 8)
  local level = parent.GetFrameLevel and parent:GetFrameLevel()
  if type(level) == "number" then f:SetFrameLevel(level + 100) end
  f:EnableMouse(true)
  f.lines = {}
  for i = 1, PANEL_LINES + 1 do -- the last for the gold goal
    local fs = f:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontNormal" or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", 10, i == 1 and -8 or (-10 - 16 - (i - 2) * 14))
    f.lines[i] = fs
  end
  f:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then G.ShowMenu(self) end
  end)
  f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L.FARM_PANEL_HINT, 1, 1, 1)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f:Hide()
  return f
end

function G.ShowMenu(owner)
  ns.Menu.Show(owner, {
    title = L.MODULE_FARMING,
    items = function(root)
      for _, v in ipairs(FM.VIEWS) do
        root:CreateRadio(L["FARM_VIEW_" .. v], function() return view() == v end,
          function() ns.Menu.Set("farming.view", v) end, v)
      end
      root:CreateDivider()
      root:CreateButton(L.FARM_GOAL_SET, G.SetGoal)
      if goal() then
        root:CreateButton(L.FARM_GOAL_CLEAR, function()
          UltimateCharDB.farmGoal = nil
          G.RenderPanel()
        end)
      end
    end,
    hide = { label = L.FARM_MENU_HIDE, fn = function()
      ns.Menu.Set("farming.showOnMap", false)
      ns:Print(L.FARM_HIDDEN)
    end },
  })
end

------------------------------------------------------------------------------
-- Zone shading (continent maps)
------------------------------------------------------------------------------
local function canvasSize()
  local c = G.canvas
  local w, h = c.GetWidth and c:GetWidth(), c.GetHeight and c:GetHeight()
  return type(w) == "number" and w or 0, type(h) == "number" and h or 0
end

-- A point inside the zone, on the continent map (0-1), or nil.
local function spotOn(mapID, childID)
  local l, r, t, b = C_Map.GetMapRectOnMap(childID, mapID)
  if not (l and r and t and b) then return nil end
  for _, p in ipairs(PROBES) do
    local x, y = l + (r - l) * p[1], t + (b - t) * p[2]
    local info = ns.Safe.read(C_Map.GetMapInfoAtPosition, mapID, x, y)
    if info and info.mapID == childID then return x, y end
  end
end

-- The game's own zone highlight (what it shows under the mouse), placed like
-- MapHighlightPinMixin:Refresh does, tinted.
local function shade(i, mapID, x, y, color)
  local ok, fileDataID, atlasID, tpx, tpy, tx, ty, sx, sy = pcall(C_Map.GetMapHighlightInfoAtPosition, mapID, x, y)
  if not ok then return false end
  local tex = G.highlights[i]
  if not tex then
    tex = G.overlay:CreateTexture(nil, "ARTWORK")
    tex:SetBlendMode("ADD")
    G.highlights[i] = tex
  end
  local w, h = canvasSize()
  tex:ClearAllPoints()
  tex:SetTexCoord(0, tpx or 1, 0, tpy or 1)
  if atlasID then
    tex:SetAtlas(atlasID, true, "TRILINEAR")
    tex:SetPoint("CENTER", G.overlay, "CENTER", ((sx + 0.5 * tx) - 0.5) * w, -((sy + 0.5 * ty) - 0.5) * h)
  elseif fileDataID and fileDataID > 0 and tx and tx > 0 and ty and ty > 0 then
    tex:SetTexture(fileDataID, nil, nil, "TRILINEAR")
    tex:SetSize(tx * w, ty * h)
    tex:SetPoint("TOPLEFT", G.overlay, "TOPLEFT", sx * w, -sy * h)
  else
    tex:Hide()
    return false
  end
  tex:SetVertexColor(color[1], color[2], color[3])
  tex:SetAlpha(SHADE_ALPHA)
  tex:Show()
  return true
end

local function label(i, x, y, grade)
  local fs = G.labels[i]
  if not fs then
    fs = G.overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    G.labels[i] = fs
  end
  local w, h = canvasSize()
  fs:ClearAllPoints()
  fs:SetPoint("CENTER", G.overlay, "TOPLEFT", x * w, -y * h)
  fs:SetText(gradeText(grade))
  fs:Show()
end

local function shadeContinent(mapID)
  local n = 0
  for _, child in ipairs(ns.Safe.read(C_Map.GetMapChildrenInfo, mapID, mapTypes().Zone) or {}) do
    local z = G.inView[child.mapID]
    if z and z.grade then
      local x, y = spotOn(mapID, child.mapID)
      if x then
        n = n + 1
        if shade(n, mapID, x, y, G.COLORS[z.grade]) then label(n, x, y, z.grade) else n = n - 1 end
      end
    end
  end
end

------------------------------------------------------------------------------
-- Node pins (zone maps)
------------------------------------------------------------------------------
local function pinEnter(self)
  local e = self.entry
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(self.node, 1, 1, 1)
  local node = ns.GatherNodes[self.node]
  if node.skill then
    GameTooltip:AddLine(string.format(L.FARM_SKILL, L["PROF_" .. node.prof], node.skill), 1, 0.82, 0)
  else
    GameTooltip:AddLine(L.FARM_SKILL_UNKNOWN, 0.5, 0.5, 0.5)
  end
  if e and e.price then
    GameTooltip:AddLine(money(e.price) .. (e.source == "vendor" and (" (" .. L.FARM_VENDOR .. ")") or ""), 1, 1, 1)
  end
  GameTooltip:Show()
end

local function pinLeave() GameTooltip:Hide() end

local function pin(i)
  local p = G.pins[i]
  if not p then
    p = CreateFrame("Button", nil, G.overlay)
    p:SetSize(PIN_SIZE, PIN_SIZE)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetAllPoints(p)
    p:SetScript("OnEnter", pinEnter)
    p:SetScript("OnLeave", pinLeave)
    G.pins[i] = p
  end
  return p
end

local function pinZone(mapID)
  if not o().showPins then return end
  local z = G.byMap[mapID]
  local entries = {}
  for _, e in ipairs(z and z.entries or {}) do entries[e.name] = e end
  local w, h = canvasSize()
  local n = 0
  for _, s in ipairs(FS.Spawns(mapID)) do
    local e = entries[s.name]
    if e then
      n = n + 1
      local p = pin(n)
      p.node, p.entry = s.name, e
      p.icon:SetTexture(ICONS[e.prof])
      p:ClearAllPoints()
      p:SetPoint("CENTER", G.overlay, "TOPLEFT", s.x * w, -s.y * h)
      p:Show()
    end
  end
end

------------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------------
local function clear()
  for _, t in ipairs(G.highlights) do t:Hide() end
  for _, t in ipairs(G.labels) do t:Hide() end
  for _, p in ipairs(G.pins) do p:Hide() end
end

function G.Refresh()
  if not G.attached then return end
  clear()
  G.hover = nil
  if not active() or not WorldMapFrame:IsShown() then
    if G.panel then G.panel:Hide() end
    return
  end
  G.Score()
  local mapID = WorldMapFrame:GetMapID()
  local info = mapID and ns.Safe.read(C_Map.GetMapInfo, mapID)
  G.mapID, G.mapType = mapID, info and info.mapType
  if G.mapType == mapTypes().Continent then
    shadeContinent(mapID)
  elseif G.mapType == mapTypes().Zone then
    pinZone(mapID)
  end
  G.RenderPanel()
end

-- The zone under the cursor on a continent map, detailed in the panel.
function G.UpdateHover()
  if not G.attached or not active() or not G.scores or G.mapType ~= mapTypes().Continent then return end
  local hover
  local focus = WorldMapFrame.IsCanvasMouseFocus and WorldMapFrame:IsCanvasMouseFocus()
  if focus ~= false then
    local x, y = WorldMapFrame:GetNormalizedCursorPosition()
    local info = x and y and ns.Safe.read(C_Map.GetMapInfoAtPosition, G.mapID, x, y)
    if info and G.byMap[info.mapID] then hover = info.mapID end
  end
  if hover ~= G.hover then
    G.hover = hover
    G.RenderPanel()
  end
end

function G.Attach()
  if G.attached or type(WorldMapFrame) ~= "table" or not WorldMapFrame.GetCanvas then return end
  local canvas = WorldMapFrame:GetCanvas()
  if not canvas then return end
  G.attached, G.canvas = true, canvas
  local overlay = CreateFrame("Frame", nil, canvas)
  overlay:SetAllPoints(canvas)
  G.overlay = overlay
  local elapsed = 0
  overlay:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed >= HOVER_EVERY then elapsed = 0; G.UpdateHover() end
  end)
  overlay:SetScript("OnSizeChanged", function() G.Refresh() end)
  G.panel = buildPanel(WorldMapFrame.ScrollContainer or WorldMapFrame)
  hooksecurefunc(WorldMapFrame, "OnMapChanged", function() G.Refresh() end)
  WorldMapFrame:HookScript("OnShow", function() G.Invalidate(); G.Refresh() end)
  WorldMapFrame:HookScript("OnHide", function() if G.panel then G.panel:Hide() end end)
  G.Refresh()
end

-- The world map's own filter menu (the magnifying glass at its top).
local function installMapMenu()
  local menu = _G.Menu
  if G.menuInstalled or type(menu) ~= "table" or type(menu.ModifyMenu) ~= "function" then return end
  G.menuInstalled = true
  menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, root)
    if not ns.Modules:IsActive("farming") then return end
    root:CreateDivider()
    root:CreateTitle(ADDON)
    root:CreateCheckbox(L.FARM_MAP_TOGGLE, function() return o().showOnMap and true or false end,
      function() ns.Menu.Set("farming.showOnMap", not o().showOnMap) end)
  end)
end

-- A mob's tooltip: what killing it has been worth to you.
local function onUnitTooltip(tooltip, data)
  if not ns.Modules:IsActive("farming") or o().unitTooltip == false then return end
  if type(tooltip) ~= "table" or type(tooltip.AddLine) ~= "function" then return end
  local guid = data and data.guid
  if ns.Safe.isSecret(guid) then return end
  local npcID = ns.Units.npcIdFromGuid(guid)
  local stat = npcID and ns.KillLog.Stats()[npcID]
  local v = stat and FM.MobValue(stat, FS.Price, FS.Skills())
  if not v or v.kills < FM.MIN_KILLS or v.perKill <= 0 then return end
  tooltip:AddLine(mobValueText(v.perKill, v.kills), 1, 0.82, 0)
end

local tooltipHooked = false
local function installTooltip()
  if tooltipHooked then return end
  local tdp = TooltipDataProcessor
  local kind = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
  if type(tdp) ~= "table" or type(tdp.AddTooltipPostCall) ~= "function" or not kind then return end
  tooltipHooked = true
  tdp.AddTooltipPostCall(kind, onUnitTooltip)
end

local pricesHooked = false
G.def = ns.Modules:Register({
  key = "farming",
  name = L.MODULE_FARMING,
  description = L.MODULE_FARMING_DESC,
  defaults = { showOnMap = true, showPins = true, recordKills = true, unitTooltip = true, includeMobs = true, view = "best" },
  OnEnable = function()
    ns.KillLog.Start()
    installMapMenu()
    installTooltip()
    if not pricesHooked then
      pricesHooked = true
      FS.OnPricesChanged(function() G.Invalidate(); G.Refresh() end)
    end
    ns:On("SKILL_LINES_CHANGED", G, function() G.Invalidate(); G.Refresh() end)
    ns:On("ULT_FARM_DATA", G, function() G.Invalidate() end)
    ns:On("PLAYER_MONEY", G, function() G.CheckGoal() end)
    ns:On("ULT_SETTING_CHANGED", G, function(_, path)
      if path and path:find("^farming") then G.Invalidate(); G.Refresh() end
    end)
    ns:On("ADDON_LOADED", G, function(_, name) if name == "Blizzard_WorldMap" then G.Attach() end end)
    G.Attach()
    G.Refresh()
  end,
  OnDisable = function()
    ns.KillLog.Stop()
    ns:OffAll(G)
    G.Refresh()
  end,
})

function G.def.BuildSettings(ctx)
  local s = FS.Status()
  local parts = {}
  if s.questie then parts[#parts + 1] = string.format(L.FARM_SRC_QUESTIE, s.questie) end
  if s.gathermate then parts[#parts + 1] = L.FARM_SRC_GATHERMATE end
  parts[#parts + 1] = s.auctionator and L.FARM_SRC_AUCTIONATOR or L.FARM_SRC_VENDOR
  ctx:Header(string.format(L.FARM_SOURCES, table.concat(parts, ", ")))
  ctx:Checkbox("farming.showOnMap", L.FARM_SHOW_MAP, L.FARM_SHOW_MAP_TIP)
  ctx:Checkbox("farming.showPins", L.FARM_SHOW_PINS, L.FARM_SHOW_PINS_TIP)
  local views = {}
  for _, v in ipairs(FM.VIEWS) do views[#views + 1] = { value = v, label = L["FARM_VIEW_" .. v] } end
  ctx:Dropdown("farming.view", L.FARM_VIEW, views, L.FARM_VIEW_TIP)
  ctx:Checkbox("farming.recordKills", L.FARM_RECORD, L.FARM_RECORD_TIP)
  ctx:Checkbox("farming.includeMobs", L.FARM_INCLUDE_MOBS, L.FARM_INCLUDE_MOBS_TIP)
  ctx:Checkbox("farming.unitTooltip", L.FARM_UNIT_TOOLTIP, L.FARM_UNIT_TOOLTIP_TIP)
end
