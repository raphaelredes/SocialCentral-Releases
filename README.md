# SocialCentral

<p align="center">
  <img src="Assets/SocialCentral-logo.png" alt="SocialCentral Official Emblem" width="140" />
</p>

Unified social, community, guild, LFG, world buffs, alts inventory, and compliant watchlist suite built exclusively for **World of Warcraft: Forever** (`Interface: 16001`).

## Features
- **Native Integration Across Official WoW Windows (`O`, `I`, `J`, `C`, `M`):** Docks cleanly via native side-tabs inside **Social (`O`)** (Watchlist, Social, Friendly Nearby, Conversations, Group), **Group Finder (`I`)** (5 illustrated category banners, 4-role header, Browse Groups with Guild/Ally/Friends/Global Chat filters), **Guild (`J`)** (Hero overview, Roster + History, Events, Diplomacy, Professions & Lockouts), **Character (`C`)** (2D Equipment/Bags/Bank + Right-Side Dossier & Gold), and **World Map (`M`)** (minimalist pins & corner summary badge).
- **Unified Friends Directory & Friend Online Alerts:** Unites online & offline **WoW Character Friends**, **Battle.net Friends** (WoW Forever, other realms/games, Launcher/App & Offline), and online **Guildmates** in one deduplicated view with Favorites (`*`), per-player **Notification Bell / Muted Bell** icons and direct action controls on every name in window `O`, Social Folders, Linked Alts, Source/Folder/Offline filters, Smart/Name/Level/Last Seen sorting, Pending Battle.net Invite Accept/Decline banner, combat-safe `+ Friend` / Remove Friend modals, native WoW & Battle.net Friend Note editing, privacy-safe `lastSeen` (never saving BattleTag or Real ID), and configurable **Friend Online Alerts** (enabled for All Friends by default with Toast + optional sound & clickable chat link, 8s login grace, and 120s anti-spam cooldown).
- **Multi-Layer Addon Notification System (`NotificationToast` & Badges):** Stacked, 100%-opaque movable Toast pills with custom medallion artwork, anti-overlap docking below the Radar pill, 1-click `[Reset Position]`, ultra-short sonar ping audio cues, multi-toast unified drag repositioning, queue/coalescing, hover-pause, 1-click navigation (safely deferred during combat), inline Room Invite Accept/Decline buttons (20s window), `/sc toast ...` preview commands, Minimap left-click chooser (Main Window vs Settings), `FlashClientIcon()` taskbar pulse, clickable `[SC ...]` chat links, `[off]` NACK feedback on disabled direct chat, opt-in Guild Event/Signup alerts, live `[SC]` / recent `[SC*]` peer badges, and unread counter pills on the Minimap and `O` / `J` side-tabs.
- **Compliant Watchlist (`/who`) & Two-Word Name Normalization:** Track characters (`FirstName Surname`) outside your Blizzard friends list with automatic Guild/Friends sync, smart `/who` cooldown conservation for confirmed-online friends, Favorites (`*`), online chat/sound alerts, combat/popup guards, and hardware-event `/who` queries (`>= 5s` cooldown) that avoid opening unwanted Blizzard windows.
- **Guild Hub, Native Game Hierarchy, Diplomacy & Target Radar HUD (`SCentral1`):** Shared Guild Status Tags, Event Calls with T/H/D role slots, Guild **Hierarchy** ladder (`#0..#N` real in-game ranks with Guild Leader-only default Diplomacy & customizable delegation, native promote/demote/rank-assign context actions), full Online + Offline Guild Roster sorted by Online & Level descending with Presence/Rank/Class/Status filters, Guild Roster Change History (`Joined`, `Left`, `Rank`), Guild/Ally/Enemy Diplomacy tracking, streamlined floating **Target Radar HUD** (class crest pill + 1-click `[X]` + secure `/targetexact` macro click + 3-button action drawer + `[Reset Position]`), prominent uppercase nameplate relationship badges (`MESMA GUILDA` / `GUILDA ALIADA` / `GUILDA INIMIGA` / `WATCHLIST` / `AMIGO`), animated red downward arrow over your active/focused target nameplate with 1-time `Shift + V` / `V` tutorial, and rate-limited opt-in guild sync (`clanSync`).
- **World Buffs Tracker, Cooldowns, Analytics & Guild Sync:** Event-driven aura timers with instant expiry scheduling, incoming city drop banners (Onyxia 6h, Nefarian 8h, Rend Blackhand / Might of Stormwind 3h, Zandalar without false cooldown, Songflower 25m Felwood pick, Darkmoon Faire week + Sayge 4h `/played`), observed Peak Hour drop windows, opt-in guild drop/catch-up sync (`WB`/`WBR`/`WBC`), World Map (`M`) interactive pins, and low-timer expiry alerts.
- **Account-Wide Alt 2D Inventory & Item Tooltips:** Splits Equipped, Bags, and Bank items on the left with a full Character Dossier (all primary/secondary professions, live Hearthstone cooldown readiness, Unclaimed Mail expiry monitor, rested XP, low bag space highlights, gold, server gold total) on the right, plus alt item counts appended cleanly onto `GameTooltip` & `ItemRefTooltip`.
- **Social Reputation Flags, Player Tooltips & Right-Click Unit Menus:** Tag players as **`Good Partner (+)`** or **`Flag: Avoid`** with notes, Linked Mains, Recent Companions, and custom Folders; see notes, Watchlist tags, Red Flags, Recent Companions, passive `[SocialCentral · Registered]` peer indicators, Friend Notes, and Allied/Enemy Guild tags on player tooltips; access quick actions and **confirmed-only** SocialCentral chat entries directly from Blizzard's right-click unit menus.
- **Group Finder (`I`) & Global Chat LFG Bulletin:** Replicates Forever's native LFG cards while letting you switch between `All (Guild/Allies/Friends)`, `Same Guild`, `Allied Guilds`, `Friends / Watchlist`, and passive `Global Chat LFG` public channel scan.
- **Unified Conversations, Official 1-Click Chat, Private Rooms & Chat Copy:** Smart Social (`O`) side-tab routing & **Unread** filter/badges, unified Battle.net + Character whisper threads (`FirstName Surname` compliant), 1-click hardware-event official Blizzard chat submission (`WHISPER` / `BN_WHISPER` / `GUILD` / `PARTY` / `RAID` / `INSTANCE_CHAT`) with instant draft recovery on offline/ignored bounces and fallback `/w` pre-fill, 60-day persistent peer registry with silent Battle.net login discovery, 1-shot incoming whisper upgrade, and passive guild P2P discovery digests, verified `[SC]` location pings, zero-delay `[SC]` chat window echo, per-thread `Mute`, and 1-click **Copy** modal.
- **Friendly Nearby Radar:** Passively detects friendly players via nameplates, soft-targets, party/raid targets, and chat while failing closed on hostile PvP units.
- **Blizzard Official vs Modern Themes & Three Languages:** Instant live theme switching, `[?]` help button beside every control, dual-counter Minimap button, and automatic/manual **English**, **Português (`ptBR`/`ptPT`)**, and **Español (`esES`/`esMX`)** localization.

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
