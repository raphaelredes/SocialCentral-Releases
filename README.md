# SocialCentral

Unified social, community, clan, and compliant watchlist addon built specifically for **World of Warcraft: Forever** (`Interface: 16001`).

## Features
- **Custom Watchlist (`/who`):** Track specific characters (`Name` or `Name-Surname`) outside your native Blizzard friends list with Groups/Tags, Favorites (`*`), Sort selector, online chat/sound alerts, and 1-click manual `+ /who` checks (`Name` or `/sc check Name`).
- **Live Social Hub:** View online Guild members, character Friends, and Battle.net friends in one searchable list with quick Whisper / Invite actions.
- **Friendly Nearby Radar:** Passively records friendly players seen via nameplates, target/mouseover, group, and chat (respecting `16001` secret-value protections and failing closed against hostile PvP units).
- **Account Alts & Total Gold:** Tracks your own characters across logins (level, zone, rested XP, gold, last active timestamp, plus total gold sum).
- **Clan Hub:** Shared Guild activity Status Tags (`LFG`, `M+`, `Raid`, `PvP`, etc.), Guild Event Calls, Dungeon/Raid role Signups (`Tank` / `Healer` / `DPS` / `Maybe`), and Peer Roster via opt-in `SCentral1` addon messages.
- **LibDBIcon-Style Minimap Button & In-Game Help (`?`):** Dynamic online counter badge, square/round minimap support, Shift+Click quick `/who`, Right-click quick menu, optional LDB broker support, and a `?` help button beside every option.
- **Three Languages Automatically:** Follows your World of Warcraft Game Options in **English**, **Português (`ptBR`/`ptPT`)**, and **Español (`esES`/`esMX`)**.

## Slash Commands
- `/sc` or `/socialcentral` — Toggle main window
- `/sc add <Name[-Surname]>` — Add a character to your Watchlist
- `/sc check <Name[-Surname]>` (or `/sc who <Name>`) — Add (if new) and run one safe `/who` check outside combat
- `/sc check` — Check the oldest Watchlist entry
- `/sc update` — Open GitHub Releases / Updater link modal
- `/sc config` — Open SocialCentral Settings

## Updating via Public GitHub Releases
In-game DBM-style peer detection notifies you in chat if a friend/guildmate runs a newer released version, with a clickable link to our public releases repo (`raphaelredes/SocialCentral-Releases`).
On Windows, you can check GitHub and install the latest verified `.zip` automatically:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\update-socialcentral.ps1
```

## Blizzard Policy & Security Compliance
- **Official-Account Safe:** Audited against Blizzard's official UI Add-On Development Policy (see [SECURITY_POLICY.md](SECURITY_POLICY.md) and mandatory project rules in [AGENTS.md](AGENTS.md)).
- 100% free, visible open-source Lua (no ads, no paywalls, no in-game donation prompts, no obfuscation, no HTTP inside WoW Lua).
- Strict hardware-event `/who` compliance, combat lockdown guards, Secret Value (`issecretvalue`) checks, and opt-in `Clan` rate limits.
