local ns = __ns
StaticPopupDialogs = {}
__boot(nil, {})
local D = ns.Dialog

describe("Ultimate's own dialog", function()
  it("shows the text and runs the first button's action", function()
    local ran = false
    D.Show("t", "Reload now?", { accept = { label = "Reload", fn = function() ran = true end }, cancel = "Later" })
    local f = D.frame
    assertTrue(f.shown)
    assertEq(f.text:GetText(), "Reload now?")
    assertEq(f.ok:GetText(), "Reload")
    assertEq(f.cancel:GetText(), "Later")
    assertFalse(f.alt.shown)
    f.ok:GetScript("OnClick")(f.ok)
    assertTrue(ran)
    assertFalse(f.shown)
  end)
  it("can have a third button, or only one", function()
    local alt = false
    D.Show("t", "?", { accept = { label = "Yes" }, cancel = "No", alt = { label = "Never", fn = function() alt = true end } })
    assertTrue(D.frame.alt.shown)
    D.frame.alt:GetScript("OnClick")(D.frame.alt)
    assertTrue(alt)
    D.Show("t", "Note", { cancel = false })
    assertFalse(D.frame.cancel.shown)
  end)
  it("never touches the game's shared popups", function()
    assertNil(next(StaticPopupDialogs))
  end)
end)
