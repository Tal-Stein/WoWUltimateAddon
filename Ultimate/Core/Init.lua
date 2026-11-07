local ADDON, ns = ...

-- Namespace, event bus and guarded dispatch.
ns.name = ADDON
ns.errorCount = 0
ns.handlers = {}

local frame = CreateFrame("Frame")
ns.eventFrame = frame

local function isCustom(event) return string.sub(event, 1, 4) == "ULT_" end

local seenErrors = {}
local function onError(err)
  ns.errorCount = ns.errorCount + 1
  local msg = tostring(err)
  if ns.db and ns.db.core and ns.db.core.debug and not seenErrors[msg] then
    seenErrors[msg] = true
    print("|cffff2020Ultimate error:|r " .. msg)
  end
  return msg
end
ns.onError = onError

-- Call fn(...) and swallow errors (counted, printed once in debug mode).
function ns.SafeCall(fn, ...)
  local args, n = { ... }, select("#", ...)
  return xpcall(function() return fn(unpack(args, 1, n)) end, function(e)
    return onError(debugstack and (tostring(e) .. "\n" .. debugstack(2)) or e)
  end)
end

-- Subscribe owner's handler to an event. Handlers receive (event, ...).
function ns:On(event, owner, fn)
  local list = self.handlers[event]
  if not list then
    list = {}
    self.handlers[event] = list
    if not isCustom(event) then frame:RegisterEvent(event) end
  end
  for _, h in ipairs(list) do
    if h.owner == owner then h.fn = fn; return end
  end
  list[#list + 1] = { owner = owner, fn = fn }
end

function ns:Off(event, owner)
  local list = self.handlers[event]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i].owner == owner then table.remove(list, i) end
  end
  if #list == 0 then
    self.handlers[event] = nil
    if not isCustom(event) then frame:UnregisterEvent(event) end
  end
end

-- Remove every subscription held by owner.
function ns:OffAll(owner)
  local events = {}
  for event in pairs(self.handlers) do events[#events + 1] = event end
  for _, event in ipairs(events) do self:Off(event, owner) end
end

function ns:Fire(event, ...)
  local list = self.handlers[event]
  if not list then return end
  -- Copy so handlers may subscribe/unsubscribe while dispatching.
  local snapshot = {}
  for i, h in ipairs(list) do snapshot[i] = h end
  for _, h in ipairs(snapshot) do ns.SafeCall(h.fn, event, ...) end
end

frame:SetScript("OnEvent", function(_, event, ...) ns:Fire(event, ...) end)

function ns:Print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  print("|cffffd100Ultimate:|r " .. table.concat(parts, " "))
end

function ns:Debug(...)
  if self.db and self.db.core and self.db.core.debug then self:Print(...) end
end
