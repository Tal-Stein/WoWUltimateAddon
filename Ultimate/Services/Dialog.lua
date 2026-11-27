local ADDON, ns = ...

-- A small dialog of Ultimate's own, in the game's tooltip-and-button look. Ultimate never writes
-- StaticPopupDialogs: an add-on's entry there taints the shared popup frames, and later Blizzard
-- popups can then fail with "Interface action failed because of an AddOn".
--   ns.Dialog.Show(key, text, spec)
--     spec.accept  { label, fn }    first button (OKAY when no label)
--     spec.cancel  label | false    closes it (CANCEL when nil, no button when false)
--     spec.alt     { label, fn }    an optional third button
local Dialog = {}
ns.Dialog = Dialog

local function button(f)
  local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  b:SetSize(110, 22)
  b:SetScript("OnClick", function(self)
    local fn = self.fn
    f:Hide()
    if fn then fn() end
  end)
  return b
end

local function build()
  local f = CreateFrame("Frame", "UltimateDialog", UIParent, "TooltipBackdropTemplate")
  f:SetSize(380, 96)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)
  f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
  f.text:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -16)
  f.ok, f.cancel, f.alt = button(f), button(f), button(f)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "UltimateDialog") end -- Escape closes
  f:Hide()
  return f
end

function Dialog.Show(key, text, spec)
  spec = spec or {}
  Dialog.frame = Dialog.frame or build()
  local f = Dialog.frame
  f.key = key
  f.text:SetText(text)
  local shown = {}
  local accept = spec.accept or {}
  f.ok:SetText(accept.label or OKAY or "Okay")
  f.ok.fn = accept.fn
  shown[#shown + 1] = f.ok
  if spec.cancel ~= false then
    f.cancel:SetText(spec.cancel or CANCEL or "Cancel")
    f.cancel.fn = nil
    shown[#shown + 1] = f.cancel
  end
  f.cancel:SetShown(spec.cancel ~= false)
  if spec.alt then
    f.alt:SetText(spec.alt.label)
    f.alt.fn = spec.alt.fn
    shown[#shown + 1] = f.alt
  end
  f.alt:SetShown(spec.alt ~= nil)
  -- Buttons centered in a row along the bottom.
  local width = #shown * 110 + (#shown - 1) * 8
  for i, b in ipairs(shown) do
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", f, "BOTTOM", -width / 2 + (i - 1) * 118, 14)
  end
  local h = f.text.GetStringHeight and f.text:GetStringHeight()
  if type(h) == "number" and h > 0 then f:SetHeight(h + 66) end
  f:Show()
end
