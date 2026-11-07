local ns = __ns
local L = ns.L

Minimap = CreateFrame("Frame", "Minimap", UIParent)
AddonCompartmentFrame = CreateFrame("Frame", "AddonCompartmentFrame", UIParent)
local opened = 0
local tooltipLines = {}
GameTooltip = CreateFrame("Frame", "GameTooltip", UIParent)
function GameTooltip:SetText(t) tooltipLines = { t } end
function GameTooltip:AddLine(t) tooltipLines[#tooltipLines + 1] = t end

__boot(nil, {})
ns.OpenSettings = function() opened = opened + 1 end

describe("Minimap button", function()
  local MB = ns.MinimapButton
  it("sits on the minimap", function()
    assertTrue(MB.button ~= nil)
    assertTrue(MB.button:GetParent() == Minimap)
    assertTrue(MB.button:IsShown())
  end)
  it("left- and right-click both open settings", function()
    MB.button:GetScript("OnClick")(MB.button, "LeftButton")
    MB.button:GetScript("OnClick")(MB.button, "RightButton")
    assertEq(opened, 2)
  end)
  it("tooltip names the add-on and says what a click does", function()
    MB.button:GetScript("OnEnter")(MB.button)
    assertEq(tooltipLines, { L.ADDON_TITLE, L.MINIMAP_CLICK })
  end)
  it("places itself by angle and can be hidden", function()
    ns.db.core.minimap.angle = 90
    MB:Place()
    local p = MB.button.point
    assertEq(p[1], "CENTER")
    assertTrue(math.abs(p[4]) < 0.001, "x = 0 at 90 degrees")
    assertTrue(p[5] > 0, "y above center")
    ns.db.core.minimap.hide = true
    ns:Fire("ULT_SETTING_CHANGED", "core.minimap.hide")
    assertFalse(MB.button:IsShown())
    ns.db.core.minimap.hide = false
    ns:Fire("ULT_SETTING_CHANGED", "core.minimap.hide")
    assertTrue(MB.button:IsShown())
  end)
  it("centers the icon and background on clients with the AddOns compartment", function()
    local b = MB.button
    assertEq(b.icon.point, { "CENTER" })
    assertEq(b.background.point, { "CENTER" })
    assertEq(b.border.point, { "TOPLEFT" })
  end)
end)
