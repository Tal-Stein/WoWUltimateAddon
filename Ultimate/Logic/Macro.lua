local ADDON, ns = ...

-- Targeting macro text (pure). Targeting is by name; this builds the secure button's macrotext.
local Macro = {}
ns.Macro = Macro

Macro.MAX_BYTES = 255
local EMPTY = "/cleartarget [dead]"

local function join(lines) return table.concat(lines, "\n") end

-- Raid marker line for a hostile live target, or nil for 0/off. Blizzard's /tm: "!" sets the
-- marker without toggling it off when it is already there.
function Macro.markerLine(marker)
  if (marker or 0) <= 0 then return nil end
  return "/tm [exists,harm,nodead] !" .. marker
end

-- names: ranked names; cursor: index of the primary name; opts: { stopInCombat, fallbacks, marker }
function Macro.build(names, cursor, opts)
  local clean = {}
  for _, n in ipairs(names) do
    local s = ns.Units.sanitizeName(n)
    if s then clean[#clean + 1] = s end
  end
  local count = #clean
  if count == 0 then return EMPTY end
  cursor = (cursor and cursor >= 1 and cursor <= count) and cursor or 1

  local head = {}
  if opts.stopInCombat then head[#head + 1] = "/stopmacro [combat,exists,harm,nodead]" end
  head[#head + 1] = "/cleartarget [dead][help]"
  head[#head + 1] = "/targetexact " .. clean[cursor]

  local fallbacks = {}
  local maxFallbacks = math.min(opts.fallbacks or 0, count - 1)
  for i = 1, maxFallbacks do
    local idx = ((cursor - 1 + i) % count) + 1
    fallbacks[#fallbacks + 1] = "/targetexact [noexists] " .. clean[idx]
  end

  local marker = Macro.markerLine(opts.marker)

  local function assemble()
    local lines = {}
    for _, l in ipairs(head) do lines[#lines + 1] = l end
    for _, l in ipairs(fallbacks) do lines[#lines + 1] = l end
    if marker then lines[#lines + 1] = marker end
    return join(lines)
  end

  local text = assemble()
  while #text > Macro.MAX_BYTES and #fallbacks > 0 do
    table.remove(fallbacks)
    text = assemble()
  end
  if #text > Macro.MAX_BYTES and marker then
    marker = nil
    text = assemble()
  end
  if #text > Macro.MAX_BYTES and opts.stopInCombat then
    table.remove(head, 1)
    text = assemble()
  end
  if #text > Macro.MAX_BYTES then
    text = string.sub(text, 1, Macro.MAX_BYTES)
  end
  return text
end

-- Cursor over the ranked names: pressing the key again moves to the next name.
local Cursor = {}
Cursor.__index = Cursor
Macro.Cursor = Cursor

function Cursor.new() return setmetatable({ names = {}, index = 1 }, Cursor) end

function Cursor:set(names)
  local oldTop = self.names[1]
  self.names = names or {}
  if self.names[1] ~= oldTop or self.index > #self.names then self.index = 1 end
end

function Cursor:current() return self.index end

function Cursor:currentName() return self.names[self.index] end

function Cursor:onTargetName(name)
  if #self.names < 2 or name == nil or name ~= self.names[self.index] then return false end
  self.index = (self.index % #self.names) + 1
  return true
end

function Cursor:reset() self.index = 1 end
