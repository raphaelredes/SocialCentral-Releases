# SocialCentral

<p align="center">
  <img src="Assets/SocialCentral-logo.png" alt="SocialCentral Official Emblem" width="140" />
</p>

Unified social, community, clan, and compliant watchlist addon built specifically for **World of Warcraft: Forever** (`Interface: 16001`).

## Features
- **Custom Watchlist (`/who`):** Track specific characters (`Name` or `Name-Surname`) outside your native Blizzard friends list with Groups/Tags, Favorites (`*`), Sort selector, online chat/sound alerts, and 1-click manual `+ /who` checks (`Name` or `/sc check Name`).
- **Live Social Hub:** View online Guild members, character Friends, and Battle.net friends in one searchable list with quick Whisper / Invite actions.
- **Friendly Nearby Radar:** Passively records friendly players seen via nameplates, target/mouseover, group, and chat (respecting `16001` secret-value protections and failing closed against hostile PvP units).
- **Account Alts & Total Gold:** Tracks your own characters across logins (level, zone, rested XP, gold, last active timestamp, plus total gold sum).
- **Clan Hub & Guild LFG:** Shared Guild activity Status Tags (`LFG`, `M+`, `Raid`, `PvP`, etc.), Event Calls with role slots (`T/H/D` & `Min Lv`), LFG filters, 1-click applicant invites, Guild Professions directory (`PRF`), opt-in passive `/g` LFM detector, and opt-in instance auto-Busy status via `SCentral1`.
- **Group / Instance Hub & Recent Companions:** Live Party, Raid, and Instance roster (`T/H/D` role summary, Leader & Ready Check badges), Ready Check & Promote actions, safe group chat announcement, plus a 7-day Recent Companions directory.
- **Conversations & Private Rooms (`v0.2.4`):** Focused addon messenger inbox for Character Whispers, Battle.net whispers, and **Addon Private Chat Rooms** (`SCentral1` `RMI`/`RMJ`/`RM`), plus optional manual `Temp Channel` (`/join`). Native WoW Guild/Group channels stay silent and un-mirrored unless explicitly opted-in under Settings, with per-channel sound toggles, per-thread `Mute`, and clean Direct Unread tracking without storing BattleTags/Real IDs or calling restricted chat automation APIs.
- **Social Folders & Main Linking:** Tag contacts with custom Folders, linked Main characters, and notes across Social, Watchlist, Group, and Chat.
- **Selectable UI Design (Blizzard Official Default vs Modern Theme):** Defaults to **Blizzard Official** (authentic classic WoW Portrait medallion window, dark smoked marble inset panel, scrollbar arrows, crimson primary CTAs & pewter metallic buttons) with a first-run visual Theme Picker comparing **Blizzard Official** and optional **Modern Theme** side-by-side, switchable anytime without `/reload`.
- **LibDBIcon-Style Minimap Button & In-Game Help (`?`):** Dual counter badges (Watchlist/Social online count + dedicated top-right Direct Unread badge excluding Guild spam), detailed per-sender unread tooltip, `Ctrl+Click` direct chat shortcut, `Shift+Click` quick `/who`, Right-click quick menu (`Mark All Read`, `Mute All Chat Sounds`, tab shortcuts), optional LDB broker support, and a `?` help button beside every option.
- **Three Languages (Auto or Manual Override):** Follows your World of Warcraft Game Options automatically or lets you manually switch between **English**, **Português (`ptBR`/`ptPT`)**, and **Español (`esES`/`esMX`)** in Settings.

## Slash Commands
- `/sc` or `/socialcentral` — Toggle main window
- `/sc chat` / `/sc group` / `/sc clan` — Jump directly to Conversations, Group, or Clan tab
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
