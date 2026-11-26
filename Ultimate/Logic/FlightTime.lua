local ADDON, ns = ...

-- Flight time arithmetic. A table maps [from node ID][to node ID] = seconds; tables are given
-- in order of trust (your own timed flights first, then the shipped data).
local FT = {}
ns.FlightTime = FT

local function find(tables, a, b)
  for _, t in ipairs(tables) do
    local row = t[a]
    if row and row[b] then return row[b] end
  end
end

-- One flight a -> b: the direct time in any table, else the reverse flight's.
local function leg(tables, a, b)
  return find(tables, a, b) or find(tables, b, a)
end

-- Seconds from src to dest, or nil. hops ({ {from, to}, ... }) is the route the flight master
-- shows; its legs are added up when the whole route isn't known.
function FT.Route(tables, src, dest, hops)
  if not src or not dest then return nil end
  local t = leg(tables, src, dest)
  if t then return t end
  if not hops or #hops == 0 then return nil end
  local total = 0
  for _, h in ipairs(hops) do
    local s = h[1] and h[2] and leg(tables, h[1], h[2])
    if not s then return nil end
    total = total + s
  end
  return total
end

-- "2:31", or "1:02:05" past an hour. Partial seconds round up, so 0:00 means arrived.
function FT.Format(seconds)
  local s = math.max(0, math.ceil((seconds or 0) - 1e-3))
  local h, m = math.floor(s / 3600), math.floor(s % 3600 / 60)
  s = s % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
  return string.format("%d:%02d", m, s)
end
