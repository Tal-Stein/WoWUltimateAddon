local ns = __ns
local IR = ns.ItemRelevance

describe("ItemRelevance.shouldShow", function()
  local base = { pinned = false, questID = 1, npcNames = { Murloc = true }, questZoneMatch = false }
  local function item(over)
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    for k, v in pairs(over or {}) do t[k] = v end
    return t
  end
  it("test_items_modes", function()
    assertTrue(IR.shouldShow(item(), {}, "always"), "always mode")
    assertFalse(IR.shouldShow(item(), {}, "relevant"), "nothing relevant")
    assertTrue(IR.shouldShow(item({ pinned = true }), {}, "relevant"), "pinned")
    assertTrue(IR.shouldShow(item(), { inQuestArea = true }, "relevant"), "quest area")
    assertTrue(IR.shouldShow(item({ questZoneMatch = true }), {}, "relevant"), "zone")
    assertTrue(IR.shouldShow(item(), { targetName = "Murloc" }, "relevant"), "target")
    assertFalse(IR.shouldShow(item(), { targetName = "Wolf" }, "relevant"), "other target")
  end)
end)
