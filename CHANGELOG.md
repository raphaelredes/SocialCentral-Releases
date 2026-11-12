# Changelog

All notable changes to **SocialCentral** are documented in this file.
Versioning follows Semantic Versioning (`MAJOR.MINOR.PATCH`). Per project policy, regular updates increment the second decimal (`PATCH`, e.g., `0.2.0` -> `0.2.1`).

## [0.2.1] - 2026-11-12
### Added
- **Official AddOn Icon (`Media\icon.tga` & `Assets\SocialCentral-logo.png`):** Custom stylized Warcraft social medallion (`128x128` 32-bit RGBA TGA) wired into `## IconTexture`, Addon Compartment, LibDBIcon/Minimap button, and the Main Window title header.
- **Second-Decimal Versioning Rule:** Persisted mandatory `PATCH` (`0.X.(Y+1)`) bumping policy in `AGENTS.md` and distribution scripts.

## [0.2.0] - 2026-11-12
### Added
- **Clan Hub (Guild Interactions):** Shared Clan status tags (`LFG`, `M+`, `Raid`, `PvP`, `Leveling`, `Crafting`, `Busy`), Guild Event Calls creation, and Dungeon/Raid role signups (`Tank`, `Healer`, `DPS`, `Maybe`, `Decline`) synced over `SCentral1` strictly under opt-in (`clanSync`), rate limits (`>= 5s`), and combat/messaging lockdown guards.
- **Standardized `?` Help Buttons:** Added interactive `?` help buttons (`What it does` + `How to use` on hover tooltip and click popup) next to every option in Settings and every interactive feature bar in the main window.
- **One-Click Manual `/who` Check (`+ /who` & `/sc check <Name>`):** Type a character name manually and run a single hardware-event-compliant `/who` lookup cleanly without leaving Combat/Cooldown safety rules.
- **DBM-Style In-Game Version Detection & Public GitHub Updater:** Passive rate-limited peer version announcement/detection (`SCentral1` `VH`/`VR`, configurable in Settings) with localized chat notification + clickable hyperlink opening a `Ctrl+C` modal for `https://github.com/raphaelredes/SocialCentral-Releases/releases/latest`, paired with Windows updater script `scripts/update-socialcentral.ps1`.
- **Enforced Trilingual Parity:** Automated compliance check validating 100% translation parity across English (`enUS`/`enGB`), Portuguese (`ptBR`/`ptPT`), and Spanish (`esES`/`esMX`) synced with WoW game language settings.

## [0.1.0] - 2026-11-12
### Added
- Unified Watchlist (`/who` hardware-event compliant with silent UI / chat filter modes), Live Social Roster (Guild, Character Friends, Battle.net), Friendly-only Nearby Sightings, Account Alts tracker with Total Gold, LibDBIcon-grade Minimap button, and fail-closed Blizzard safety verification gate.
