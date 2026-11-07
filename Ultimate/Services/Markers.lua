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
  f.anim = f:CreateAnimationGroup()
  f.anim:SetLooping("BOUNCE")
  f.move = f.anim:CreateAnimation("Translation")
  f.move:SetDuration(0.6)
  f.move:SetSmoothing("IN_OUT")
  f.scale = f.anim:CreateAnimation("Scale")
  f.scale:SetDuration(0.6)
  f.scale:SetSmoothing("IN_OUT")
  return f
end

local function acquire()
  local f = table.remove(M.pool) or build()
  return f
end

local function release(f)
  if f.anim then f.anim:Stop() end
  f:Hide()
  f:ClearAllPoints()
  f.plate = nil
  f.animMode = nil
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
  if f.animMode == o.anim and (f.anim:IsPlaying() or (o.anim ~= "bob" and o.anim ~= "pulse")) then return end
  f.animMode = o.anim
  f.anim:Stop()
  if o.anim == "bob" then
    f.move:SetOffset(0, 6); f.scale:SetScale(1, 1)
    f.anim:Play()
  elseif o.anim == "pulse" then
    f.move:SetOffset(0, 0); f.scale:SetScale(1.15, 1.15)
    f.anim:Play()
  end
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
