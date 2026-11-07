local ADDON, ns = ...

-- Pure: positions for `n` equal cells in a padded panel with a title band.
-- layout(n, o) -> { cols, rows, width, height, cells = { {x, y} } }  (TOPLEFT offsets, y <= 0)
--   o: { perRow, vertical, cellW, cellH, gapX, gapY, pad, top, minWidth }
--   Horizontal fills rows left to right; vertical fills columns top to bottom. When minWidth is
--   wider than the cells need, the cells are centred. n = 0 keeps one empty cell of room.
local G = {}
ns.Grid = G

function G.layout(n, o)
  local per = math.max(1, math.floor(o.perRow or 6))
  local slots = math.max(n, 1)
  local long = math.min(slots, per)
  local short = math.ceil(slots / per)
  local cols, rows = long, short
  if o.vertical then cols, rows = short, long end

  local cellsW = cols * o.cellW + (cols - 1) * o.gapX
  local cellsH = rows * o.cellH + (rows - 1) * o.gapY
  local width = math.max(cellsW + 2 * o.pad, o.minWidth or 0)
  local height = o.top + cellsH + o.pad
  local left = o.pad + (width - 2 * o.pad - cellsW) / 2

  local cells = {}
  for i = 1, n do
    local a, b = (i - 1) % per, math.floor((i - 1) / per)
    local col, row = a, b
    if o.vertical then col, row = b, a end
    cells[i] = { x = left + col * (o.cellW + o.gapX), y = -(o.top + row * (o.cellH + o.gapY)) }
  end
  return { cols = cols, rows = rows, width = width, height = height, cells = cells }
end
