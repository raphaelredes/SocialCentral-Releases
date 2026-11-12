# Changelog

All notable changes to **SocialCentral** are documented in this file.
Versioning follows Semantic Versioning (`MAJOR.MINOR.PATCH`).

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
