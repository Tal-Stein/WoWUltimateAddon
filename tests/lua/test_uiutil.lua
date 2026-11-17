local ns = __ns

__boot(nil, {})

describe("UI.MakeMovable", function()
  it("finishes a drag that ends in combat only after combat, without blocked calls", function()
    local frame = CreateFrame("Frame", "UltTestMovable", UIParent)
    frame.secure = true -- has secure children, so moving it in combat is blocked
    local stops = 0
    function frame:StopMovingOrSizing()
      if __inCombat then error("ACTION_BLOCKED StopMovingOrSizing") end
      stops = stops + 1
    end
    local handle = CreateFrame("Frame", nil, frame)
    local store = {}
    ns.UI.MakeMovable(frame, handle, store, function() return false end, { "CENTER", "CENTER", 0, 0 })
    handle:GetScript("OnDragStart")(handle)
    __inCombat = true
    handle:GetScript("OnDragStop")(handle) -- must not raise
    assertEq(stops, 0, "nothing protected touched in combat")
    __inCombat = false
    __fire("PLAYER_REGEN_ENABLED")
    assertEq(stops, 1, "drop completed after combat")
  end)
end)
