local ADDON, ns = ...

-- How much a quest reward improves on what the player wears, scored by GearQuestForever's
-- class/spec stat weights (GearQuest.Compare:ScoreItemStats). Without that add-on, or while an
-- item isn't cached yet, the answer is "unknown" rather than a guess.
local GV = {}
ns.GearValue = GV

local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 },
  INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
  INVTYPE_HOLDABLE = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_RANGED = { 18 },
  INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local function scorer()
  local gq = GearQuest
  local cmp = type(gq) == "table" and type(gq.Compare) == "table" and gq.Compare or nil
  return cmp and type(cmp.ScoreItemStats) == "function" and cmp or nil
end

function GV.available() return scorer() ~= nil end

-- nil while the item isn't loaded yet; otherwise GearQuestForever's score, where 0 is a real
-- answer (it scores the base item, so random-suffix gear can come out at 0).
-- Forever's client namespaces the item API; the old global can be missing.
local function itemInfo(item)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return ns.Safe.read(fn, item)
end

local function score(cmp, itemId)
  if not itemInfo(itemId) then return nil end
  local ok, s = pcall(cmp.ScoreItemStats, cmp, { itemId = itemId })
  return ok and type(s) == "number" and s or 0
end

local function instant(link)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if type(fn) ~= "function" then return nil end
  local ok, id, _, _, equipLoc = pcall(fn, link)
  if ok then return id, equipLoc end
  return nil
end

-- itemLinks: reward links. Returns { link, newScore, oldScore } for the biggest gain,
-- false when no reward is equippable, nil + reason when it can't be known yet:
-- "noscorer" (GearQuestForever missing) or "loading" (item info not loaded yet).
function GV:BestUpgrade(itemLinks)
  local best, sawGear = nil, false
  local cmp = scorer()
  for _, link in ipairs(itemLinks or {}) do
    local id, equipLoc = instant(link)
    local slots = id and SLOTS[equipLoc]
    if slots then
      sawGear = true
      if not cmp then return nil, "noscorer" end
      local new = score(cmp, id)
      if not new then return nil, "loading" end
      local old
      for _, slot in ipairs(slots) do
        local eq = ns.Safe.read(GetInventoryItemID, "player", slot)
        local s = 0
        if eq then
          s = score(cmp, eq)
          if not s then return nil, "loading" end
        end
        if old == nil or s < old then old = s end
      end
      local ratio = old > 0 and new / old or math.huge
      if not best or ratio > best.ratio then
        best = { link = link, newScore = new, oldScore = old, ratio = ratio }
      end
    end
  end
  if not sawGear then return false end
  return best
end
