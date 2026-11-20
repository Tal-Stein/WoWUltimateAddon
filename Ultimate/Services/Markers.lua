local ADDON, ns = ...
local UI = ns.UI

-- Overhead markers: a large animated quest icon above each relevant, untagged mob's nameplate.
-- Purely visual (not secure), so it updates in combat too.
local M = { pool = {}, active = {} }
ns.Markers = M

local QUEST_ATLASES = { "QuestNormal", "UI-QuestPoi-QuestNumber-SuperTracked" }
local RARE_ATLASES = { "VignetteKill", "nameplates-icon-elite-silver" }

local function pickAtlas(list)
  if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
  for _, atlas in ipairs(list) do
    local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
    if ok and info then return atlas end
  end
end

local questAtlas, rareAtlas
local function art(tex, rare)
  if questAtlas == nil then questAtlas = pickAtlas(QUEST_ATLASES) or false end
  if rareAtlas == nil then rareAtlas = pickAtlas(RARE_ATLASES) or false end
  local atlas = rare and rareAtlas or questAtlas
  if atlas then
    tex:SetAtlas(atlas)
  else
    tex:SetTexture(rare and UI.ICON_RARE or UI.ICON_QUEST)
  end
end

local function opts() return ns.db.targeting.markers end

local function build()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetFrameStrata("HIGH")
  f.tex = f:CreateTexture(nil, "OVERLAY")
  f.tex:SetAllPoints()
  -- Move in sub-pixel steps; snapped to the pixel grid a short bob is only a few visible positions.
  if f.tex.SetSnapToPixelGrid then f.tex:SetSnapToPixelGrid(false) end
  if f.tex.SetTexelSnappingBias then f.tex:SetTexelSnappingBias(0) end
  -- Bob: Blizzard's bobbing-arrow pattern (Azerite power arrow) - a repeating eased move up,
  -- then the same move down, so the loop never turns around mid-animation.
  f.bob = f:CreateAnimationGroup()
  f.bob:SetLooping("REPEAT")
  f.up = f.bob:CreateAnimation("Translation")
  f.up:SetSmoothing("IN_OUT"); f.up:SetOrder(1)
  f.down = f.bob:CreateAnimation("Translation")
  f.down:SetSmoothing("IN_OUT"); f.down:SetOrder(1)
  -- Pulse: grow and shrink back.
  f.pulse = f:CreateAnimationGroup()
  f.pulse:SetLooping("BOUNCE")
  f.grow = f.pulse:CreateAnimation("Scale")
  f.grow:SetSmoothing("IN_OUT")
  return f
end

-- Set the animations' path and timing from the settings (only while stopped).
local function configure(f, o)
  local dist, time, scale = o.animDistance or 16, o.animTime or 0.8, o.pulseScale or 1.15
  f.up:SetOffset(0, dist); f.up:SetDuration(time)
  f.down:SetOffset(0, -dist); f.down:SetDuration(time); f.down:SetStartDelay(time)
  f.grow:SetScale(scale, scale); f.grow:SetDuration(time)
end

local function stopAnims(f)
  f.bob:Stop(); f.pulse:Stop()
  f.anim, f.animMode = nil, nil
end

local function acquire()
  local f = table.remove(M.pool) or build()
  return f
end

local function release(f)
  stopAnims(f)
  f:Hide()
  f:ClearAllPoints()
  f.plate = nil
  M.pool[#M.pool + 1] = f
end

local function style(f, top, rare, level)
  local o = opts()
  local size = o.size or 40
  if top or rare then size = math.floor(size * 1.4) end
  f.markerSize = size
  f.isRare = rare
  f:SetSize(size, size)
  art(f.tex, rare)
  local c
  if rare then
    c = { r = 0.85, g = 0.85, b = 0.95 }
  elseif o.colorMode == "difficulty" then
    c = UI.DifficultyColor(level)
  else
    c = UI.NormalColor()
  end
  f.tex:SetVertexColor(c.r, c.g, c.b)
  f:SetAlpha(top and 1 or 0.8)
  -- style() runs on every scan (every 0.5s); restarting the loop each time made it jump back to
  -- its start mid-bounce. Only (re)start when the animation style changes.
  local group = (o.anim == "bob" and f.bob) or (o.anim == "pulse" and f.pulse) or nil
  local mode = table.concat({ tostring(o.anim), tostring(o.animDistance), tostring(o.animTime),
    tostring(o.pulseScale) }, "/")
  if f.animMode == mode and (group == nil or group:IsPlaying()) then return end
  stopAnims(f)
  configure(f, o)
  f.animMode, f.anim = mode, group
  if group then group:Play() end
end

function M:Update(ranked, byName)
  local wanted = {}
  local o = opts()
  if o.enabled then
    for i, name in ipairs(ranked or {}) do
      if o.topOnly and i > 1 then break end
      local c = byName[name]
      for _, mob in ipairs(c and c.mobs or {}) do
        if mob.plate and not mob.tapped then
          wanted[mob.plate] = { top = i == 1, rare = c.kind == "rare" or c.isRare, level = mob.level or c.level }
        end
      end
    end
  end
  for plate, f in pairs(self.active) do
    if not wanted[plate] then
      release(f)
      self.active[plate] = nil
    end
  end
  for plate, w in pairs(wanted) do
    local f = self.active[plate]
    if not f then
      f = acquire()
      local ok = pcall(f.SetPoint, f, "BOTTOM", plate, "TOP", 0, o.offset or 10)
      if ok then
        f.plate = plate
        self.active[plate] = f
        f:Show()
      else
        release(f)
        f = nil
      end
    end
    if f then style(f, w.top, w.rare, w.level) end
  end
end

function M:ForPlate(plate) return self.active[plate] end

function M:ActiveCount()
  local n = 0
  for _ in pairs(self.active) do n = n + 1 end
  return n
end

ns:On("ULT_TARGETS_CHANGED", M, function(_, ranked, byName) M:Update(ranked, byName) end)
ns:On("ULT_SETTING_CHANGED", M, function(_, path)
  if path and path:find("^targeting%.markers") then
    -- Re-anchor everything so offset/size changes apply.
    for plate, f in pairs(M.active) do release(f); M.active[plate] = nil end
    M:Update(ns.Targeting.ranked, ns.Targeting.byName)
  end
end)
