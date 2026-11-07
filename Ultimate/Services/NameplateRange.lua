local ADDON, ns = ...
local L = ns.L

-- Nameplate range: the add-on only sees a mob once it has a nameplate, and the client creates
-- nameplates within the nameplateMaxDistance setting. Classic offers this as a 20-41 yard slider;
-- Forever's settings leave it out, but it is an ordinary client setting add-ons may set.
-- We set it, remember the player's previous value to restore when turned off, and accept
-- whatever the client allows (if it caps the value, we say so once and leave it there).
local R = {}
ns.NameplateRange = R

local CVAR = "nameplateMaxDistance"

local function o() return ns.db.targeting.range end

local function current()
  local v = GetCVar and ns.Safe.read(GetCVar, CVAR)
  return type(v) == "string" and v or (type(v) == "number" and tostring(v)) or nil
end

function R:Apply()
  local opts = o()
  if current() == nil then
    if not self.unavailableNoticed then
      self.unavailableNoticed = true
      ns:Print(L.RANGE_UNAVAILABLE)
    end
    return
  end
  ns.Combat:Run("cvar.nameplateRange", function()
    if opts.enabled then
      if opts.original == nil then opts.original = current() end
      local want = opts.yards or 41
      SetCVar(CVAR, tostring(want))
      local got = tonumber(current())
      if got and got < want then
        if R.cappedNoticeFor ~= want then
          R.cappedNoticeFor = want
          ns:Print(string.format(L.RANGE_CAPPED, got))
        end
      else
        R.cappedNoticeFor = nil
      end
    elseif opts.original ~= nil then
      SetCVar(CVAR, opts.original)
      opts.original = nil
    end
  end)
end

ns:On("PLAYER_LOGIN", R, function() R:Apply() end)
ns:On("ULT_SETTING_CHANGED", R, function(_, path)
  if path and path:find("^targeting%.range") then R:Apply() end
end)
