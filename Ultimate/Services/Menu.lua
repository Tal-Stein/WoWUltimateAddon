local ADDON, ns = ...
local L = ns.L

-- Shared right-click menu for every Ultimate control (Blizzard's MenuUtil context menu), so they
-- all offer the same basics in the same order:
--   title, control-specific entries, Lock (movable controls), Hide, Settings.
-- Show(owner, spec)
--   spec.title     menu title
--   spec.items     function(root) adding control-specific entries (optional)
--   spec.lock      { get = fn() -> bool, set = fn(bool) } (optional)
--   spec.hide      { label = text, fn = fn() } (optional)
local Menu = {}
ns.Menu = Menu

local function openSettings() if ns.OpenSettings then ns.OpenSettings() end end

function Menu.Show(owner, spec)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    openSettings()
    return
  end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(spec.title)
    if spec.items then spec.items(root) end
    if spec.lock then
      root:CreateCheckbox(L.LOCK_BAR, function() return spec.lock.get() and true or false end,
        function() spec.lock.set(not spec.lock.get()) end)
    end
    root:CreateDivider()
    if spec.hide then root:CreateButton(spec.hide.label, spec.hide.fn) end
    root:CreateButton(L.OPEN_SETTINGS, openSettings)
  end)
end

-- Set a dotted ns.db path and announce it, like the Settings panel does.
function Menu.Set(path, value)
  ns.Tables.setPath(ns.db, path, value)
  ns:Fire("ULT_SETTING_CHANGED", path)
end
