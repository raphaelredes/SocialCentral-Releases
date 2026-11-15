# SocialCentral

<p align="center">
  <img src="Assets/SocialCentral-logo.png" alt="SocialCentral Official Emblem" width="140" />
</p>

Unified social, community, guild, LFG, world buffs, alts inventory, and compliant watchlist suite built exclusively for **World of Warcraft: Forever** (`Interface: 16001`).

## Features
- **Native Integration Across Official WoW Windows (`O`, `I`, `J`, `C`, `M`):** Docks cleanly via native side-tabs inside **Social (`O`)** (Watchlist, Social, Friendly Nearby, Conversations, Group), **Group Finder (`I`)** (5 illustrated category banners, 4-role header, Browse Groups with Guild/Ally/Friends/Global Chat filters), **Guild (`J`)** (Hero overview, Roster + History, Events, Diplomacy, Professions & Lockouts), **Character (`C`)** (2D Equipment/Bags/Bank + Right-Side Dossier & Gold), and **World Map (`M`)** (minimalist pins & corner summary badge).
- **Compliant Watchlist (`/who`) & Two-Word Name Normalization:** Track characters (`FirstName Surname`) outside your Blizzard friends list with automatic Guild/Friends sync, Favorites (`*`), online chat/sound alerts, combat/popup guards, and hardware-event `/who` queries (`>= 5s` cooldown) that avoid opening unwanted Blizzard windows.
- **Guild Hub, Diplomacy, Target Radar HUD & Opt-In Sync (`SCentral1`):** Shared Guild Status Tags, Event Calls with T/H/D role slots, Guild Roster Change History (`Joined`, `Left`, `Rank`), Guild/Ally/Enemy Diplomacy tracking, minimalist floating **Target Radar HUD** (360° arrow pill + secure `/targetexact` macro click + action drawer), and rate-limited opt-in guild sync (`clanSync`).
- **World Buffs Tracker, Cooldowns, Analytics & Guild Sync:** Live aura countdowns, incoming city drop banners (Onyxia 6h, Nefarian 8h, Rend Blackhand / Might of Stormwind 3h, Zandalar without false cooldown, Songflower 25m Felwood pick, Darkmoon Faire week + Sayge 4h `/played`), observed Peak Hour drop windows, opt-in guild drop sharing, and World Map (`M`) interactive pins.
- **Account-Wide Alt 2D Inventory & Item Tooltips:** Splits Equipped, Bags, and Bank items on the left with a full Character Dossier (all primary/secondary professions, hearthstone, gold, server gold total) on the right, plus alt item counts appended cleanly onto `GameTooltip` & `ItemRefTooltip`.
- **Social Reputation Flags, Player Tooltips & Right-Click Unit Menus:** Tag players as **`Good Partner (+)`** or **`Flag: Avoid`** with notes, Linked Mains, and custom Folders; see notes, Watchlist tags, Red Flags, and Recent Companions on player tooltips; access quick actions directly from Blizzard's right-click unit menus.
- **Group Finder (`I`) & Global Chat LFG Bulletin:** Replicates Forever's native LFG cards while letting you switch between `All (Guild/Allies/Friends)`, `Same Guild`, `Allied Guilds`, `Friends / Watchlist`, and passive `Global Chat LFG` public channel scan.
- **Conversations, Private Rooms & Chat Copy:** Clean inbox for Character/BNet Whispers and Addon Private Rooms with verified `[SC]` location pings, per-thread `Mute`, and 1-click **Copy** modal.
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
