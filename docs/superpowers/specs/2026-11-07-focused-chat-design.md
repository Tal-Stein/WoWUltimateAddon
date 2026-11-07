# Focused Chat — design

**Status:** approved layout (owner picked "all tabs in main dock" and named it "Focused"). The
rest of this note covers calls made by Claude; they are marked *(call)*.

## Intent
Keep the chat that matters apart from the noise around the player. Social and world chatter
(say, yell, emotes, General/Trade channels) stays in **General**. The chats the owner marks as
*focused* go to a combined **Focused** tab. Each focused category can also get **its own tab**,
for catching up on one conversation, such as guild chat only.

## What the owner sees
- Real Blizzard chat tabs in the main chat dock: `General | Combat Log | Focused | Whispers |
  Party | Raid | Guild …`. They have Blizzard's fonts, links, scrolling, tab flashing on new
  messages, and the tab right-click menu.
- `/ult` → **Focused Chat** has one row per category with two checkboxes: **Focused** and
  **Own tab**. There are also options for **Remove focused chats from General** and **Copy recent
  history into new tabs**, and an **Apply** button that asks for a `/reload`.

## Categories and their message groups
| Category | Groups | Focused by default | Own tab by default |
|---|---|---|---|
| Whispers | WHISPER, BN_WHISPER | yes | yes |
| Party | PARTY, PARTY_LEADER | yes | yes |
| Raid | RAID, RAID_LEADER, RAID_WARNING | yes | yes |
| Instance | INSTANCE_CHAT, INSTANCE_CHAT_LEADER | yes | no |
| Guild | GUILD, GUILD_DISCORD | yes | yes |
| Officer | OFFICER | yes | no |
| Say & Yell | SAY, YELL | no | no |
| Emotes | EMOTE | no | no |

A category's groups are filtered to those this client defines in `ChatTypeGroup` *(call)*.

## How it works (taint-safe by construction)
Chat text can be secret on this client. Add-on code that writes Blizzard's live chat-frame
state can taint the chat handler and break chat (see WoWUIBugs #876). So the add-on **only
changes the saved chat-window configuration** through the client functions Blizzard's own
chat settings use:
- `SetChatWindowName`, `SetChatWindowShown`, `SetChatWindowDocked`
- `AddChatWindowMessages` / `RemoveChatWindowMessages`
- `SetChatWindowSize`

Then it reloads the UI. At load, Blizzard rebuilds every window from that configuration with
its own code (`UPDATE_CHAT_WINDOWS` → `GetChatWindowInfo` / `GetChatWindowMessages`).

- **Planning** is a pure function: current windows plus settings in, list of actions out. It is
  fully unit-tested.
- **Ownership:** the add-on remembers which window names it created or adopted
  (`ownedNames`). It only hides windows it owns, and only restores to General the groups it
  removed from General (`removedFromGeneral`) *(call)*.
- **Window slots:** new tabs use free windows above the client's reserved ones
  (`C_ChatInfo.GetNumReservedChatWindows`). If slots run out, the remaining tabs are skipped
  and the owner is told *(call)*.
- **History:** there is no server history API for these chats, and a reload clears chat
  windows. Just before the reload, the add-on reads the lines currently in the chat windows
  (`GetMessageInfo`, whose 5th value is the chat type id). It keeps the lines that belong to
  each **newly created** tab, up to 200 per tab, skipping secret lines. It saves them and adds
  them back into those tabs after the reload, under an "Earlier messages" divider. This is the
  same idea as Blizzard's own copying of whisper history into a popped-out window. "As far back
  as reachable" is therefore this session's chat *(call)*.
- **Turning the feature off** hides the owned tabs, gives General its groups back, and asks
  for a reload.
- **Right-click rule:** the tabs keep Blizzard's own tab menu. Ultimate adds nothing to it,
  because changing chat tabs is what risks tainting chat *(call)*.

## Not doing
- No custom chat frame, no chat filters, no hooks on chat frames or the edit box.
- No guild history from Communities (`C_Club`) for now. It is a possible later addition, once
  it is confirmed in game.
