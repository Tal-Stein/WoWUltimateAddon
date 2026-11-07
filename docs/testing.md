# In-game verification checklist

The offline tests (`python tests/run.py`) cover the logic, the combat queue and the settings
wiring against stubs. Everything below can only be confirmed in the real Forever client.
Work through it once after installing, with `/ult debug` on so errors show in chat.

## Setup
1. Deploy: `powershell -ExecutionPolicy Bypass -File scripts/deploy.ps1`.
2. Log in. The character select AddOns list shows **Ultimate**, and it needs Questie and
   QuestieDB to be enabled.
3. Nothing errors at login. With `/ult debug` on, no red "Ultimate error" lines appear.

## Settings
- [ ] Options → AddOns → **Ultimate** exists. Its subpages are: Targeting, Quest Targeting,
      Rare Scanner, Quest Items, Lists & Priorities.
- [ ] Checkboxes, sliders and dropdowns change values, and the values survive `/reload`.
- [ ] The "Preview sound" buttons play the selected sounds.
- [ ] Lists & Priorities shows your quests. Pin and Ignore stick. Adding and removing names
      works, and "Add target" adds your current target.
- [ ] `/ult` opens the page. The AddOn compartment entry (minimap AddOns button) opens it too,
      if Forever has the compartment.

## Quest Targeting
- [ ] If enemy nameplates are off, a prompt offers to turn them on about 5 s after login.
- [ ] `/ult scan` lists the indexed quest mobs and the nearby ones, with a reason for each.
      It says "Quest database: Questie".
- [ ] **Item quests** ("collect 8 Gold Dust"): the mobs that drop the item are listed.
      Mobs the database misses show up after their tooltip has been seen.
- [ ] Bind Key Bindings → AddOns → "Target next quest mob". Pressing it targets the top quest
      mob nearby.
- [ ] Pressing it again with another quest mob name nearby moves to the next name.
- [ ] *Verify:* when several mobs share a name, does pressing again rotate among them?
      (spec §13)
- [ ] In combat, while fighting a live enemy, the key doesn't swap targets ("Keep my target
      in combat").
- [ ] "Create macro" makes an **UltTarget** general macro that works from an action bar.
- [ ] The target bar shows one button per quest mob name. The level is colored grey, green,
      yellow, orange or red, and hovering shows quest progress. Clicking targets.
- [ ] The bar can be dragged while unlocked, and stays put while locked or with "Lock all
      bars" on.
- [ ] Overhead markers appear above quest mobs, bigger above the top one. Size, height, color
      and animation settings apply. *Verify* which atlas art Forever shows (spec §13).
- [ ] Mobs tagged by someone else get no marker and no alert, and the key skips their name
      when no untagged mob of that name is visible.
- [ ] A raid marker (when set) lands on the target the key picks, and only while solo by
      default. *Verify* that `/tm` exists on Forever.
- [ ] Alert sounds: regular, elite and boss quest mobs each play their own sound. Level-based
      sounds work when that option is enabled. The same mob doesn't repeat inside the cooldown.

## Minimap button
- [ ] A spyglass button sits on the minimap edge. Clicking opens settings. Dragging moves it
      around the edge, and the position survives `/reload`. "Show minimap button" in settings
      hides it.

## Rare Scanner
- [ ] A rare's nameplate gives a "RARE: …" warning and a sound, and the rare goes to the front
      of the target bar (when set to First).
- [ ] A tagged rare alerts with "(tagged)" but gets no button.
- [ ] Watch-list names behave like rares.
- [ ] `/ult scan` lists the rares seen this session.

## Quest Items
- [ ] With "Only when relevant", a quest's usable item appears in that quest's zone, or when
      you target one of its mobs.
- [ ] With "Always while in bags", every usable quest item appears.
- [ ] Clicking uses the item. Shift-click pins it (star) without using it. Dragging puts it on
      an action bar.
- [ ] Right-clicking an item button or the bar's title opens a menu: Always show this item,
      Lock bar, show mode, Hide quest item bar, Settings. Right-click never uses the item.
      "Hide" turns off Quest Items, and a chat line says where to turn it back on.
- [ ] Item icons, borders and cooldown spirals are centred in their buttons, and so are the
      target bar's.
- [ ] Bind "Use quest item 1" and press it.
- [ ] Cooldown spirals and counts update.
- [ ] *Verify* that `C_QuestLog.IsOnMap` exists on Forever. If it doesn't, the zone match
      still works.

## Combat safety (must never fail)
- [ ] Enter combat while quest mobs appear and disappear, and while looting quest items. There
      is never an "Interface action failed because of an AddOn" message. The bar and item bar
      catch up after combat.

## Secret values (spec §13)
- [ ] Out of combat, mob levels, classifications and tagged state read correctly.
      `/ult scan` shows levels rather than `??` for normal mobs.
