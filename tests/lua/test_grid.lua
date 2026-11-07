local ns = __ns
local G = ns.Grid

-- cell 40x50, gaps 4/6, padding 8, title band 20, min width 0
local base = { cellW = 40, cellH = 50, gapX = 4, gapY = 6, pad = 8, top = 20, minWidth = 0 }
local function opts(over)
  local t = {}
  for k, v in pairs(base) do t[k] = v end
  for k, v in pairs(over or {}) do t[k] = v end
  return t
end

describe("Grid.layout", function()
  it("fills rows left to right and wraps", function()
    local g = G.layout(8, opts({ perRow = 6 }))
    assertEq(g.cols, 6)
    assertEq(g.rows, 2)
    assertEq(g.cells[1], { x = 8, y = -20 })
    assertEq(g.cells[2], { x = 52, y = -20 })
    assertEq(g.cells[7], { x = 8, y = -76 }, "wraps to the second row, same left edge")
    assertEq(g.width, 8 + 6 * 40 + 5 * 4 + 8)
    assertEq(g.height, 20 + 2 * 50 + 6 + 8)
  end)
  it("vertical fills columns top to bottom", function()
    local g = G.layout(4, opts({ perRow = 3, vertical = true }))
    assertEq(g.cols, 2)
    assertEq(g.rows, 3)
    assertEq(g.cells[3], { x = 8, y = -20 - 2 * 56 })
    assertEq(g.cells[4], { x = 52, y = -20 })
  end)
  it("a short single row does not reserve empty columns", function()
    local g = G.layout(2, opts({ perRow = 6 }))
    assertEq(g.cols, 2)
    assertEq(g.width, 8 + 2 * 40 + 4 + 8)
  end)
  it("centres the grid when the minimum width is larger", function()
    local g = G.layout(1, opts({ perRow = 6, minWidth = 100 }))
    assertEq(g.width, 100)
    assertEq(g.cells[1].x, (100 - 40) / 2)
  end)
  it("keeps one empty cell of room when there is nothing to show", function()
    local g = G.layout(0, opts({ perRow = 6 }))
    assertEq(g.cols, 1)
    assertEq(g.rows, 1)
    assertEq(#g.cells, 0)
    assertEq(g.width, 8 + 40 + 8)
  end)
  it("every cell lies inside the frame", function()
    for n = 1, 24 do
      for _, vertical in ipairs({ false, true }) do
        local g = G.layout(n, opts({ perRow = 5, vertical = vertical, minWidth = 120 }))
        for i, c in ipairs(g.cells) do
          assertTrue(c.x >= 8 and c.x + 40 <= g.width - 8 + 1e-9, "x in bounds n=" .. n .. " i=" .. i)
          assertTrue(-c.y >= 20 and -c.y + 50 <= g.height - 8 + 1e-9, "y in bounds n=" .. n .. " i=" .. i)
        end
      end
    end
  end)
end)
