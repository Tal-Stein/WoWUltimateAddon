local ADDON, ns = ...

-- Whether a quest item button should be shown (pure).
--   item: { pinned, questID, npcNames = {[name]=true}, questZoneMatch }
--   ctx:  { targetName, inQuestArea }
--   mode: "always" | "relevant"
local ItemRelevance = {}
ns.ItemRelevance = ItemRelevance

function ItemRelevance.shouldShow(item, ctx, mode)
  if mode == "always" then return true end
  if item.pinned then return true end
  if ctx.inQuestArea then return true end
  if item.questZoneMatch then return true end
  if ctx.targetName and item.npcNames and item.npcNames[ctx.targetName] then return true end
  return false
end
