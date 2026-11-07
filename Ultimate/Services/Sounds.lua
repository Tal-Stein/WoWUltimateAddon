local ADDON, ns = ...
local L = ns.L

-- Built-in game sounds offered in every alert dropdown. Kit names come from SOUNDKIT when the
-- client has them, with the classic numeric IDs as fallback.
local Sounds = {}
ns.Sounds = Sounds

local RAW = {
  { "none", "SOUND_NONE" },
  { "mapping", "SOUND_MAP_PING", "MAP_PING", 3175 },
  { "raidwarning", "SOUND_RAID_WARNING", "RAID_WARNING", 8959 },
  { "readycheck", "SOUND_READY_CHECK", "READY_CHECK", 8960 },
  { "questadded", "SOUND_QUEST", "IG_QUEST_LIST_OPEN", 875 },
  { "alarm", "SOUND_ALARM", "ALARM_CLOCK_WARNING_3", 12889 },
  { "toast", "SOUND_TOAST", "UI_BNET_TOAST", 18019 },
  { "levelup", "SOUND_LEVEL_UP", "LEVELUP", 888 },
  { "pvpqueue", "SOUND_PVP_QUEUE", "PVP_THROUGH_QUEUE", 8459 },
  { "auction", "SOUND_AUCTION", "AUCTION_WINDOW_OPEN", 5274 },
  { "whisper", "SOUND_WHISPER", "TELL_MESSAGE", 3081 },
}

function Sounds.Catalog()
  local list = {}
  for _, r in ipairs(RAW) do
    local kit = r[3] and ((SOUNDKIT and SOUNDKIT[r[3]]) or r[4]) or nil
    list[#list + 1] = { key = r[1], label = L[r[2]], kit = kit }
  end
  return list
end

function Sounds.Kit(key)
  for _, s in ipairs(Sounds.Catalog()) do
    if s.key == key then return s.kit end
  end
end

function Sounds.Play(key, channel)
  local kit = Sounds.Kit(key)
  if not kit or not PlaySound then return false end
  ns.SafeCall(PlaySound, kit, channel or "Master")
  return true
end
