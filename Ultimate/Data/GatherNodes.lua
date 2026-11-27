local ADDON, ns = ...

-- Gathering nodes by their in-game name: the profession that gathers them, the skill it takes
-- and the item they give (its price stands for the node's value). These are game facts
-- (required skill levels, ore and herb item IDs); where nodes stand comes from Questie's
-- Forever database or GatherMate2 at runtime (Services/FarmSources.lua), never from here.
-- Forever adds nodes of its own; until their skill and item are known they're listed without.
ns.GatherNodes = {
  -- Herbalism
  ["Peacebloom"] = { prof = "herbalism", skill = 1, item = 2447 },
  ["Silverleaf"] = { prof = "herbalism", skill = 1, item = 765 },
  ["Earthroot"] = { prof = "herbalism", skill = 15, item = 2449 },
  ["Mageroyal"] = { prof = "herbalism", skill = 50, item = 785 },
  ["Briarthorn"] = { prof = "herbalism", skill = 70, item = 2450 },
  ["Stranglekelp"] = { prof = "herbalism", skill = 85, item = 3820 },
  ["Bruiseweed"] = { prof = "herbalism", skill = 100, item = 2453 },
  ["Wild Steelbloom"] = { prof = "herbalism", skill = 115, item = 3355 },
  ["Grave Moss"] = { prof = "herbalism", skill = 120, item = 3369 },
  ["Kingsblood"] = { prof = "herbalism", skill = 125, item = 3356 },
  ["Liferoot"] = { prof = "herbalism", skill = 150, item = 3357 },
  ["Fadeleaf"] = { prof = "herbalism", skill = 160, item = 3818 },
  ["Goldthorn"] = { prof = "herbalism", skill = 170, item = 3821 },
  ["Khadgar's Whisker"] = { prof = "herbalism", skill = 185, item = 3358 },
  ["Wintersbite"] = { prof = "herbalism", skill = 195, item = 3819 },
  ["Firebloom"] = { prof = "herbalism", skill = 205, item = 4625 },
  ["Purple Lotus"] = { prof = "herbalism", skill = 210, item = 8831 },
  ["Arthas' Tears"] = { prof = "herbalism", skill = 220, item = 8836 },
  ["Sungrass"] = { prof = "herbalism", skill = 230, item = 8838 },
  ["Blindweed"] = { prof = "herbalism", skill = 235, item = 8839 },
  ["Ghost Mushroom"] = { prof = "herbalism", skill = 245, item = 8845 },
  ["Gromsblood"] = { prof = "herbalism", skill = 250, item = 8846 },
  ["Golden Sansam"] = { prof = "herbalism", skill = 260, item = 13464 },
  ["Dreamfoil"] = { prof = "herbalism", skill = 270, item = 13463 },
  ["Mountain Silversage"] = { prof = "herbalism", skill = 280, item = 13465 },
  ["Plaguebloom"] = { prof = "herbalism", skill = 285, item = 13466 },
  ["Icecap"] = { prof = "herbalism", skill = 290, item = 13467 },
  ["Black Lotus"] = { prof = "herbalism", skill = 300, item = 13468 },
  ["Demonsage"] = { prof = "herbalism" },   -- Forever
  ["Marefoil"] = { prof = "herbalism" },    -- Forever

  -- Mining
  ["Copper Vein"] = { prof = "mining", skill = 1, item = 2770 },
  ["Tin Vein"] = { prof = "mining", skill = 65, item = 2771 },
  ["Incendicite Mineral Vein"] = { prof = "mining", skill = 65, item = 3340 },
  ["Silver Vein"] = { prof = "mining", skill = 75, item = 2775 },
  ["Ooze Covered Silver Vein"] = { prof = "mining", skill = 75, item = 2775 },
  ["Lesser Bloodstone Deposit"] = { prof = "mining", skill = 75, item = 4278 },
  ["Iron Deposit"] = { prof = "mining", skill = 125, item = 2772 },
  ["Indurium Mineral Vein"] = { prof = "mining", skill = 150, item = 5833 },
  ["Gold Vein"] = { prof = "mining", skill = 155, item = 2776 },
  ["Ooze Covered Gold Vein"] = { prof = "mining", skill = 155, item = 2776 },
  ["Mithril Deposit"] = { prof = "mining", skill = 175, item = 3858 },
  ["Ooze Covered Mithril Deposit"] = { prof = "mining", skill = 175, item = 3858 },
  ["Truesilver Deposit"] = { prof = "mining", skill = 230, item = 7911 },
  ["Ooze Covered Truesilver Deposit"] = { prof = "mining", skill = 230, item = 7911 },
  ["Dark Iron Deposit"] = { prof = "mining", skill = 230, item = 11370 },
  ["Small Thorium Vein"] = { prof = "mining", skill = 245, item = 10620 },
  ["Ooze Covered Thorium Vein"] = { prof = "mining", skill = 245, item = 10620 },
  ["Rich Thorium Vein"] = { prof = "mining", skill = 275, item = 10620 },
  ["Ooze Covered Rich Thorium Vein"] = { prof = "mining", skill = 275, item = 10620 },
  ["Hakkari Thorium Vein"] = { prof = "mining", skill = 275, item = 10620 },
  ["Heavy Thorium Vein"] = { prof = "mining" }, -- Forever
}

-- Skill line IDs (C_SkillInfo) of the professions this reads.
ns.GatherSkillLines = { herbalism = 182, mining = 186, skinning = 393, fishing = 356 }

-- Bumped whenever this file changes, so cached node counts rebuild (Services/FarmSources.lua).
ns.GatherNodesVersion = 1
