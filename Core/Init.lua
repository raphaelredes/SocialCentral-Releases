local ADDON_NAME, ns = ...

local L = ns.L
ns.name = ADDON_NAME
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "0.2.32"
if ns.version == "" or ns.version:find("^@") then ns.version = "0.2.32" end
ns.sessionStartedAt = ns.sessionStartedAt or time()
ns.RELEASE_REPO = "raphaelredes/SocialCentral-Releases"
ns.RELEASE_URL = "https://github.com/" .. ns.RELEASE_REPO .. "/releases/latest"

ns.modules = {}
ns.listeners = {}

local lastPrintText = nil
local lastPrintAt = 0

function ns:Print(fmt, ...)
    local text = select("#", ...) > 0 and fmt:format(...) or tostring(fmt)
    if text:sub(1, 2) ~= "  " then
        local now = (GetTime and GetTime()) or 0
        if lastPrintText == text and (now - lastPrintAt) < 3.0 then
            return
        end
        lastPrintText = text
        lastPrintAt = now
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff58a6ffSocialCentral|r: " .. text)
    end
end

-- Simple pub/sub so providers notify UI without tight coupling.
function ns:On(eventName, callback)
    if not ns.listeners[eventName] then ns.listeners[eventName] = {} end
    table.insert(ns.listeners[eventName], callback)
end

function ns:Emit(eventName, ...)
    local list = ns.listeners[eventName]
    if not list then return end
    for _, cb in ipairs(list) do
        local ok, err = pcall(cb, ...)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end

-- Safe Blizzard event dispatcher: pcall on RegisterEvent prevents fatal errors
-- if a future patch removes or renames an optional event.
local eventFrame = CreateFrame("Frame")
ns._eventFrame = eventFrame
local eventHandlers = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for owner, fn in pairs(list) do
        local ok, err = pcall(fn, owner, event, ...)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end)

function ns.RegisterEvent(owner, event, fn)
    if not eventHandlers[event] then
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then return false end
        eventHandlers[event] = {}
    end
    eventHandlers[event][owner] = fn
    return true
end

function ns.UnregisterEvent(owner, event)
    local list = eventHandlers[event]
    if not list then return end
    list[owner] = nil
    if next(list) == nil then
        eventHandlers[event] = nil
        pcall(eventFrame.UnregisterEvent, eventFrame, event)
    end
end

local DEFAULTS = {
    settings = {
        theme = "blizzard",         -- "blizzard" (default) | "dark" (modern optional) | "native"
        themeChosen = false,        -- first-run visual design picker completed
        language = "auto",          -- "auto" | "enUS" | "ptBR" | "esES"
        whoMode = "silent_ui",      -- "silent_ui" | "chat_filter"
        whoCooldown = 6,            -- seconds between /who hardware-event requests
        nearbyRetentionMin = 15,    -- minutes to keep passive nearby sightings
        sortBy = "status",          -- "status" | "name" | "recent"
        socialSortBy = "smart",     -- "smart" | "name" | "level" | "lastSeen"
        socialShowOffline = true,   -- show offline Character/BNet friends in Social directory
        watchlistShowOffline = true, -- show offline players in Watchlist directory
        chatShowOffline = true,      -- show offline direct threads in Conversations directory
        compactListRows = false,     -- compact 1-line rows in Watchlist/Social/Nearby/Guild lists
        friendOnlineAlertMode = "all", -- "all" | "favorites" | "off"
        friendOnlineAlertToast = true,       -- show compact floating toast when friends come online
        friendOnlineAlertChat = false,       -- optional extra chat summary line on friend login
        friendOnlineAlertSound = true,       -- subtle audio chime when friend online toast fires
        friendOfflineAlertToast = true,      -- show compact floating toast when friends log off / disconnect
        friendOfflineAlertChat = false,      -- optional extra chat summary line on friend logoff
        friendAlertAllMigrated = false,      -- one-time default upgrade from v0.2.9 favorites-only mode
        alerts = {
            chat = true,
            toast = true,
            sound = false,
        },
        minimap = {
            hide = false,
            angle = 215,
            anglesByRes = {},
            lock = false,
        },
        minimapLeftClickAction = "smart", -- "smart" (Quick Reply -> Main Hub -> Close All) | "hub" | "menu"
        streamerMode = false,       -- opt-in privacy mode masking BattleTags/Real IDs & sensitive message previews
        chatModifierQuickActions = true, -- Alt+Click player names to Invite, Ctrl+Click for Social Card
        versionCheck = true,        -- passive DBM-style peer version check (rate-limited)
        clanSync = false,           -- opt-in for clan guild addon messages (status/events/signups/lfg)
        guildChatFinder = false,    -- opt-in passive /g LFM line detector (read-only, zero auto-reply)
        clanLfgAlertEnabled = true,  -- alert when a guild/allied/official peer looks for a dungeon/group
        clanLfgAlertDungeonsOnly = true, -- notify specifically for Dungeon / M+ group searches
        clanLfgAlertNearLevel = true, -- filter group alerts to ±5 levels around the player
        clanLfgAlertFilter = "",     -- optional comma-separated dungeon keywords
        clanLfgAlertSound = true,    -- sound chime when a Clan Dungeon LFG alert triggers
        clanEventAlertEnabled = false, -- opt-in alert when a guildmate posts a new Guild Event
        clanSignupAlertEnabled = true, -- alert event creator when guildmates sign up or decline
        clanEventReminders = true,   -- show 15m and 5m notifications before confirmed Guild/Calendar events
        autoStatusInstance = false, -- opt-in contextual activity tag out-of-combat
        chatSound = true,           -- master chime toggle for direct/room conversations
        chatSoundCooldown = 6,      -- minimum seconds between message notification sounds (default 6s, anti-spam floor >= 3s)
        chatSoundCooldownDefault6Migrated = false, -- one-time upgrade from initial 3s default to 6s default
        chatSoundWhispers = true,   -- chime on Character & Battle.net whispers
        chatSoundRooms = true,      -- chime on Addon Private Chat Room messages & invites
        chatSoundAlliance = true,   -- chime on Alliance chat addon messages
        chatSoundGuild = false,     -- Guild / Officer chat sound muted by default
        chatSoundGroup = false,     -- Party / Raid / Instance chat sound muted by default
        chatMirrorChannels = true,  -- mirror native WoW Guild/Party/Raid channels inside Conversations
        chatChannelUnread = false,  -- opt-in: allow mirrored WoW channels to increment unread badges
        chatMutedThreads = {},      -- per-conversation mute map [threadKey] = true
        chatMutedThreadRules = {},  -- optional expiry rules for timed/instance tab mutes [threadKey] = { untilTs | untilLeaveInstance }
        chatHistoryLimit = 300,     -- local lines kept per character conversation thread (0 to 2000)
        guildChatHistorySave = true, -- persist Guild & Officer chat history locally across /reload and logins (toggleable)
        guildChatHistoryLimit = 300, -- saved Guild & Officer lines retained per channel (50 to 2000, default 300)
        generalChatHistorySave = true, -- persist General, Private Rooms, Alliance & Mentions history across /reload and logins
        groupChatHistorySave = true, -- persist Party, Raid & Instance chat history across /reload and logins
        generalChatHistoryLimit = 300, -- saved lines per General, Room, Group, Alliance & Mentions thread (50 to 2000, default 300)
        historyLimitsExpandedV2Migrated = false, -- one-time upgrade expanding default saved history limits with 100MB account text cap
        addonDirectChat = true,     -- enable verified 1-on-1 SocialCentral direct chat & peer handshake
        chatDirectOfficialSend = true, -- send official /w, Battle.net, and guild/group replies in 1 click from Conversations (hardware-event only)
        chatGroupReconnectSync = true, -- auto-sync missed group chat messages after disconnect/reconnect (0ms idle CPU)
        mentionAlertsEnabled = true, -- Mentions & Custom Keyword Radar in chat
        mentionSound = true,        -- play subtle chime on mention/keyword match
        mentionNicknames = "",      -- comma-separated personal nicknames / alt names
        mentionKeywords = "",       -- comma-separated custom keywords to watch in chat
        mentionWatchGuild = true,   -- monitor Guild & Officer chat for mentions/keywords
        mentionWatchGroup = true,   -- monitor Party, Raid & Instance chat for mentions/keywords
        mentionWatchSayYell = true, -- monitor Say & Yell for mentions/keywords
        mentionWatchPublic = true,  -- monitor Public channels (Trade/General/World/LFG) for mentions/keywords
        accountIgnoreHideChat = true, -- hide official WoW chat messages from Account-Ignored players
        chatAntiSpamEnabled = false, -- opt-in public chat Anti-Spam Shield (RMT/gold-sellers/boost spam)
        chatAntiSpamBlockFlood = true, -- block repeated identical public messages by strangers within 45s
        chatAntiSpamKeywords = "",  -- optional comma-separated custom blocked words for Anti-Spam Shield
        chatClickableUrls = true,   -- make Discord & web URLs clickable to open the Copy Link dialog
        embedOfficialChat = true,   -- master toggle for Official Chat (ChatFrame) enhancements & quick [SC] button
        chatUiMode = nil,           -- nil (prompt once) | "addon" (SocialCentral chat replaces Official Chat) | "official" (Official WoW Chat only)
        officialChatQuickButton = true, -- show standardized quick [SC] control button beside Official Chat
        officialChatShortcutButton = true, -- show SocialCentral shortcut & unread badge button beside Official Chat (mirrors Minimap button)
        chatButtonLock = false,     -- lock Official Chat SocialCentral shortcut button against dragging
        chatButtonCustomPos = nil,  -- legacy flat position (auto-migrated into chatButtonPositionsByRes)
        chatButtonPositionsByRes = {}, -- per-resolution saved positions for Official Chat SocialCentral button
        officialChatShortChannels = true, -- shorten verbose public channel labels in official chat
        officialChatSenderTags = true, -- append cached [Lv], [Main], [+]/[Avoid] tags in official chat
        officialChatEditHistory = true, -- preserve typed EditBox lines across reloads (never saves BattleTags)
        officialChatFastScroll = true, -- Shift+Wheel top/bottom & Ctrl+Wheel fast page scroll in official chat
        chatErrorOriginTags = true, -- append correlated [Origin: Addon] tags to leaked yellow system errors in Official Chat
        embedLfgMirrorBar = true,   -- show bottom SocialCentral mirror bar on Group Finder (I) Official Tab 1
        embedMailPicker = true,     -- show Alts quick-picker & [SC] toggle inside Blizzard SendMailFrame
        embedProfessionWindow = true, -- passively catalog learned recipes & show [SC] toggle on official Profession windows
        tooltipRecipeAlts = true,   -- show Craftable by Alt / Recipe known / Guild crafter inside item tooltips
        guildRecipeReply = true,    -- answer on-demand CRQ recipe queries from guildmates when Clan Sync is on
        addonMsgToast = false,      -- opt-in floating toast pill for text addon messages (Minimap Previews handle chats cleanly without duplicating)
        toastDuration = 6,          -- seconds each notification toast stays visible before disappearing (default 6s)
        toastTutorialShown = false, -- one-time account-wide tutorial shown when first notification toast appears
        tutorialDismissAll = false, -- disable automatic first-time Chromie prompts across all areas (manual [?] still works)
        lootRollPromptAnswered = false, -- whether player answered first-roll activation prompt
        lootRollHelperEnabled = false, -- show SocialCentral Group Loot Roll mini-window with live picks & gear comparison
        lootRollHideOfficial = true, -- hide Blizzard's default GroupLootFrame bars when SocialCentral's roll window is active
        lootRollWinnerBanner = false, -- retired top-of-screen winner banner (winners appear on roll card, notification popup & local chat)
        lootRollWinnerSound = true, -- play subtle celebratory chime when a group loot roll winner is announced
        lootRollWinnerToast = true, -- show epic celebration splash at top of screen when you win a group drop
        lootRollWinnerChatAnnounce = true, -- print local clickable winner summary to main chat when a group drop is won
        lootRollResultsButtonMode = "when_enabled", -- "when_enabled" | "always" | "hidden" fixed floating Roll Results button
        lootRollResultsButtonLock = false, -- lock fixed floating Roll Results button position against accidental drag
        lootRollCardLock = false, -- lock active Group Loot Roll card position against accidental drag
        lootRollDisplayMode = "tabbed", -- "tabbed" | "stacked" active Group Loot Roll layout
        lootRollAutoHideWithQuickBar = false, -- hide standalone floating dice button when Quick Access Bar already shows Roll Results
        lootRollShowTooltipsCompare = true, -- automatically attach equipped comparison tooltips when hovering roll items
        lootRollTrackChatRolls = true, -- track group/raid /roll (1-100) rounds inside the Roll Results window
        toastBelowChatMigrated = false, -- one-time migration placing default toast position directly below ChatFrame1
        addonMsgChatEcho = true,    -- echo clickable [SC] summary line to Blizzard chat windows for incoming addon messages
        addonMsgChatEchoSent = true, -- echo sent [SC] addon messages into Blizzard chat windows immediately
        addonChatFrames = { [1] = true }, -- [chatFrameIndex 1..10] Blizzard chat tabs showing [SC] addon chat (1 = General)
        addonMsgTaskbarFlash = true, -- pulse game taskbar icon on incoming addon messages
        addonMsgMinimapBadge = true, -- display compact unread counter badge on Minimap button
        minimapBadgeStyle = "fusion", -- "fusion" (multi-color circle under SC icon + hover split) | "separate" (orbital numbers around SC icon)
        addonMsgTabBadges = true,   -- display compact unread badges on Social (O) & Guild (J) side-tabs
        msgPreviewEnabled = true,       -- show compact animated message preview capsule beside Minimap or Official Chat
        msgPreviewAnchor = "minimap",   -- "minimap" (beside Minimap) | "chat_side" (beside Official Chat) | "chat_top" (above Official Chat)
        msgPreviewPromptAnswered = true, -- never hijack first whisper with a blocking setup dialog (setup still available manually)
        msgPreviewWhispers = true,      -- show minimap previews for Character Whispers & Direct Addon chat
        msgPreviewBNet = true,          -- show minimap previews for Battle.net friends messages
        msgPreviewGroup = false,        -- show minimap previews for Party / Raid / Instance messages
        msgPreviewGuild = false,        -- show minimap previews for Guild / Officer messages
        msgPreviewRooms = true,         -- show minimap previews for SocialCentral Private Rooms & Alliance chat
        msgPreviewSilenceDungeons = true, -- auto-hide minimap previews inside Dungeons / Scenarios
        msgPreviewSilenceRaids = true,  -- auto-hide minimap previews inside Raids
        msgPreviewSilencePvP = true,    -- auto-hide minimap previews inside Battlegrounds & Arenas
        msgPreviewSilenceCombat = true, -- retract & hold message previews and popups while actively in combat
        msgPreviewDuration = 6,         -- seconds to display preview before retracting back into SC icon (default 6s)
        quickReplyEnabled = true,       -- clicking Minimap icon with pending message notifications opens compact Quick Reply popup
        quickReplyDockToChat = true,    -- snap Quick Reply directly over Blizzard ChatFrame1 matching its exact size & position
        quickReplyLocked = false,       -- lock Quick Reply window position against accidental drags (user-toggleable via header padlock or Settings)
        quickReplyLockMode = nil,       -- "unlocked" | "pos_locked" (lock move, allow resize) | "full_locked"
        chatQuickRepliesByContext = {}, -- per-context quick replies (local, defense, party, raid, guild)
        quickReplyHotkeys = {},         -- user-configured keyboard shortcuts to send a quick phrase to a chosen chat
        abilityChatMacros = {},         -- user-configured spell+chat macros (1-click drag to action bar, combat-safe)
        quickReplyEnterOpen = true,     -- press ENTER when pending notifications/drafts exist to open Quick Reply over Blizzard chat
        quickReplyAutoClose = false,    -- stay always visible by default; opt-in auto-close on inactivity while preserving typed draft
        quickReplyAutoCloseDelay = 10,  -- seconds before Quick Reply auto-closes when auto-close is enabled (default 10s)
        quickReplyIdleFade = true,      -- fade Quick Reply to transparent after inactivity while staying visible
        quickReplyFadeDelay = 15,       -- seconds of inactivity before Quick Reply becomes transparent (default 15s)
        quickReplyFade15Migrated = false, -- one-time upgrade tightening default idle fade from 30s to 15s
        quickReplyFadeInCombat = false, -- opt-in: hide Quick Reply and pass clicks through during combat (off by default)
        quickReplyAlwaysShowV1Migrated = false, -- one-time upgrade enabling always-open Quick Reply + 15s idle transparency
        quickReplyDungeonAutoMode = true, -- auto-open persistent Quick Reply (over Official Chat or dragged spot) in Dungeons & Raids
        quickReplySlashOpen = true, -- auto-open/switch Quick Reply when typing /p, /g, /o, /ra, /i, /al, /r, /w (+ Space)
        quickReplyCtrlWCloseTab = true, -- close active unpinned Quick Reply tab with Ctrl+W when CTRL-W has no external keybind
        quickReplyShowPingsBar = true,  -- show/hide the bottom 1-click Quick Replies chip bar inside Quick Reply
        quickReplyFontSize = 0,         -- chat viewport font size override (0 = inherit ChatFontNormal default; 11..16 = explicit pt)
        chatHubFontSize = 0,            -- Conversations hub chat viewport font size override (0 = inherit ChatFontNormal; 11..16 = explicit pt)
        quickReplyTutorialShown = false, -- one-time account-wide Quick Reply walkthrough tutorial shown on first view
        officialHideGroup = false,      -- opt-in: hide Party/Raid/Instance chat in Blizzard Official Chat while keeping in SocialCentral
        officialHideGuild = false,      -- opt-in: hide Guild/Officer chat in Blizzard Official Chat while keeping in SocialCentral
        officialHideWhispers = false,   -- opt-in: hide Whispers & Battle.net in Blizzard Official Chat while keeping in SocialCentral
        quickReplyNotifyWhisper = true, -- include Whispers & SocialCentral Direct Chat in Quick Reply notifications
        quickReplyNotifyBNet = true,    -- include Battle.net messages in Quick Reply notifications
        quickReplyNotifyParty = true,   -- include Party / Instance chat in Quick Reply notifications
        quickReplyNotifyRaid = true,    -- include Raid chat in Quick Reply & orange Raid Minimap notifications
        quickReplyNotifyRaidMigrated = false, -- one-time upgrade enabling Raid Minimap & Quick Reply notifications
        quickReplyNotifyGuild = false,  -- include Guild / Officer chat in Quick Reply notifications
        quickReplyNotifySay = false,    -- opt-in: include Say & Yell in Quick Reply unread notifications / Enter shortcut
        quickReplyRecordSay = true,     -- record nearby Say & Yell session logs in Quick Reply tabs & Quick History
        generalFeedFilters = {          -- per-category display/capture toggles for General (ch:general) right-click menu
            loot = true,
            achievement = true,
            monster = true,
            system = true,
            public = true,
            sayYell = true,
        },
        msgPreviewMaxVisible = 3,       -- max simultaneous minimap preview rows (1..3); extras wait in FIFO queue
        msgPreviewDefault6Migrated = false, -- one-time upgrade from initial 5s default to 6s default
        spotterEnabled = true,      -- lightweight event-driven radar (0ms idle CPU)
        spotterNotifyEnemy = true,  -- chat + banner notification when Enemy Clan player appears
        spotterNotifyAlly = true,   -- chat + banner notification when Ally Clan player appears
        spotterNotifySameClan = false, -- default off to keep screen uncluttered (user can opt back in)
        spotterNotifyWatchlist = true, -- directional radar notification when a Watchlist player appears nearby
        spotterNotifyFriends = true,   -- directional radar notification when a Friend appears nearby
        spotterNotifyBlocked = true,   -- alert when a Blocked/Ignore or Avoid-flagged player appears nearby
        spotterIgnoreGroup = true,     -- ignore current party/raid members from automatic radar popups
        spotterSound = true,        -- subtle chime when an Enemy/Ally/Watchlist player appears
        spotterAutoShowHUD = true,  -- auto-open floating HUD pill on flagged sighting (out of combat)
        spotterToastDuration = 10,  -- seconds each Target Radar target toast stays visible before auto-dismissing (default 10s)
        spotterPromptAnswered = true, -- keep HUD clutter-free without unsolicited confirmation popups
        spotterLockHUD = false,     -- lock target HUD position against accidental dragging
        spotterNameplateArrow = true, -- show animated red arrow above focused/selected target nameplate when visible
        spotterNameplateBadges = true, -- show lightweight stance tags above visible tracked player nameplates
        spotterNameplateTargetHighlight = true, -- highlight selected target overhead name & info cleanly above nameplate
        altsWorldScope = "pool", -- "pool" | "all" | "world:<PvP|PvE|RP-PvE|RP-PvP|RP>" | "pool:<realmPool>"
        spotterPlateTutorialShown = false, -- show one-time nameplate tutorial (Shift+V / V) on first radar sighting
        spotterRadarTutorialShown = false, -- show one-time target radar proximity tutorial on first radar tracking
        spotterV2Migrated = false,  -- one-time migration from legacy deactivated spotter defaults
        gatherHighlightEnabled = false, -- opt-in: highlight nearby herbs, ore veins, fish & treasures via official Soft-Target + plate sparkles
        gatherHighlightEnhanceRange = true, -- use official Soft-Target interact icons/cone & restore original CVars on disable
        gatherHighlightOutline = true, -- enable official outline highlight on nearby objects when gather highlight is on
        gatherHighlightNameplateGlow = true, -- show animated high-contrast sparkle halo & label over targeted collectible node
        gatherHighlightFloatBeacon = true, -- show non-blocking top indicator capsule when a collectible is detected in front
        gatherHighlightQuickButton = true, -- show compact movable toggle button to switch Collectibles Highlight ON/OFF in 1 click
        gatherHighlightQuickButtonLock = false, -- lock position of the floating Collectibles Highlight button
        flightMapTimesEnabled = true, -- display estimated/recorded flight duration directly inside the Flight Map tooltip alongside location & cost
        quickBarEnabled = true, -- show customizable floating Quick Access Bar (5-10 buttons, Horizontal/Vertical)
        quickBarOrientation = "horizontal", -- "horizontal" | "vertical"
        quickBarLocked = false, -- lock Quick Access Bar position
        quickBarButtons = { "hub", "quick_reply", "gather_sparkles", "radar", "loot_rolls", "dnd", "settings" },
        gatherHighlightSound = false, -- optional subtle chime when spotting a collectible node
        gatherHighlightPromptAnswered = false, -- true once user answered the Minimap tracking prompt or toggled manually
        gatherHighlightTutorialShown = false, -- one-time Chromie explanation of Collectibles Highlight & native Interact Key
        gatherInteractTipExplained = false, -- one-time Chromie bubble triggered when Blizzard's yellow Interact Key tip appears
        gatherHighlightSavedCVars = nil, -- snapshot of original user CVars restored automatically when feature is turned off
        embedSocialWindow = true,   -- integrate SocialCentral side-tab inside Social / Friends (O)
        embedLfgWindow = true,      -- integrate Clans & Allies LFG tab inside Group Finder (I)
        embedGuildWindow = true,    -- integrate Guild Hub & Diplomacy side-tab inside Communities / Guild (J)
        embedCharacterWindow = true, -- integrate My Alts side-tab inside Character window (C)
        shortcutAutoOpenAddon = {
            O = false, -- Social / Friends (O)
            I = false, -- Group Finder (I)
            J = false, -- Guild / Communities (J)
            C = false, -- Character / My Alts (C)
        },
        shortcutPromptAnswered = {
            O = false,
            I = false,
            J = false,
            C = false,
        },
        hideGuildFeaturesWhenNoGuild = true, -- automatically hide guild tabs/options when current character has no guild
        moduleWatchlistEnabled = true, -- master toggle for Watchlist module
        moduleNearbyEnabled = true,    -- master toggle for Friendly Nearby passive module
        moduleChatEnabled = true,      -- master toggle for Conversations & Addon Chat module
        moduleGroupEnabled = true,     -- master toggle for Group & Recent Companions module
        doNotDisturb = false,          -- non-destructive master pause for all popups & alert chimes
        autoSilenceInInstances = false, -- automatically pause social popups/chimes inside dungeons, raids & BGs
        focusAllowFavorites = true,    -- allow Favorite (★) players through Focus Mode & Do Not Disturb
        syncGameDnd = true,            -- automatically treat WoW /dnd (Busy) status as Focus Mode
        dndUntil = 0,                  -- epoch timestamp when timed Do Not Disturb auto-clears (0 = no timer)
        dndUntilLeaveInstance = false, -- auto-clear Do Not Disturb upon leaving the current instance
        dndUntilLeaveGroup = false,    -- auto-clear Do Not Disturb upon leaving the current party/raid group
        focusUpgradeV1Migrated = false, -- one-time upgrade to single-surface notifications & combat hold defaults
        spotterScoutAlert = true,   -- notify on shared Scout sighting alerts from guildmates
        flightMapTimesEnabled = true, -- show estimated & recorded durations in Flight Map tooltip
        flightTimerBarEnabled = true, -- show live flight arrival countdown bar at the top of the screen
        tooltipItemAlts = true,     -- show alt bag/bank/equipped item counts inside item tooltips
        tooltipPlayerNotes = true,  -- show Social Card notes, red flags & companion context inside player tooltips
        globalChatLfgScan = true,   -- passively index dungeon/raid LFG posts from public chat channels
        lfgAutoApplyDraft = true,   -- pre-fill your Level, Class & Role when whispering LFG posts
        lfgAntiSpam = true,         -- filter WTS/GDKP/boost spam from public LFG channels
        lfgHideAvoidEnemy = false,  -- hide LFG posts from Avoid-flagged or Enemy Guild leaders
        lfgBulletinMode = true,     -- group LFG browse results under collapsible canonical Dungeon/Raid headers
        lfgSideDrawerOpen = true,   -- remember whether the docked Filters & Tools side panel auto-opens beside Group Finder (I)
        lfgAutoOpenOnList = true,   -- automatically switch to SocialCentral Group Finder + Filter Center right after creating/updating an Official LFG listing
        lfgSplitGroupsAndPlayers = true, -- organize browse rows into collapsible Groups (LFM) and Players Looking (LFG) sections
        lfgHideSavedLockouts = false, -- hide dungeons/raids where the active character is already saved
        lfgHideFullGroups = true,   -- hide groups that are already 5/5 or have 0 open slots for your filtered role
        lfgWatchersEnabled = true,  -- print clickable Official Chat alerts when watched dungeons/keywords appear
        lfgWatchedActivities = {},  -- [canonicalKey] = displayLabel for active Dungeon/Raid Watchers
        lfgWhisperTemplate = "",    -- optional custom LFG apply whisper template ({level}, {class}, {role}, {spec}, {ilvl}, {activity}, {activity_en})
        lfgInviteAutoWhisper = true, -- automatically whisper solo LFG players when clicking Invite (+)
        lfgInviteWhisperTemplate = "Hi! Inviting you to our {activity_en} group!", -- customizable invite whisper template ({activity_en}, {activity})
        lfgShowClassIconsOnRows = true, -- show up to 5 member class icons inline on LFG group rows
        lfgBrowseCategory = "ALL",  -- last chosen Browse category ("ALL" | "DUNGEONS" | "RAIDS" | "QUESTS" | "PVP" | "CUSTOM")
        lfgBrowseSource = "ALL",    -- last chosen Browse source filter
        lfgBrowseRole = "ALL",      -- last chosen Browse role filter ("ALL" by default; Tri-State Filter Center manages roles)
        lfgBrowseSuitableLevel = true, -- filter activities & groups to character level by default
        lfgBrowseSelectedActivities = {}, -- [catId] = { [actKey] = true } persisted checked activities
        officialLfgSyncMode = "GUILD_ALLIES", -- "GUILD_ALLIES" | "GUILD_ONLY" | "OFF"
        groupAvoidAlert = true,     -- warn in chat and toast if an Avoided player enters your party or raid
        dungeonRunLogEnabled = true, -- passively record started dungeon/raid groups, teammates & run duration (zero CLEU)
        dungeonLogPromptShown = false, -- one-time account-wide reminder after finishing the first dungeon or raid
        clanAutoCloseFullLfg = true, -- auto-close own Guild Dungeon LFM when party reaches 5 members
        clanRosterHistoryLimit = 150, -- max guild roster join/leave/rank entries retained (25..1000)
        socialGroupByFolder = true,  -- organize O -> Social into collapsible colored folder sections
        socialCollapsedSections = {}, -- persisted [tabId] = { [sectionKey] = bool } collapse state (section keys only, zero personal data)
        socialOfficialPopupAlerts = true, -- show warning banner on official Invite, Trade & Duel popups from Ignored/Avoid players
        clanOfficialGreenWall = true, -- mirror Alliance Guild chat into Blizzard Official Chat (ChatFrame1)
        groupReadyCheckAudit = true,  -- show missing Raid/Dungeon buff audit alert on Blizzard Ready Check
    },
    window = {
        point = nil,
        width = 790,
        height = 520,
    },
    windowPositions = {},            -- legacy fallback [windowKey] = { dx, dy }
    windowPositionsByRes = {},       -- [resKey] = { [windowKey] = { anchor, dx, dy, width, height } } per-resolution saved positions & sizes
    accountTutorials = {},           -- [tutorialKey] = true account-wide one-time tutorial completion flags (never repeated on alts)
    accountIgnores = {},             -- [lookupKey] = { name, reason, note, addedAt, expiresAt, hideChat } unlimited account-wide ignores (zero BattleTag/Real ID)
    watchlist = {},                -- [scopeKey] = { [id] = entry }
    alts = {},                     -- [charKey] = snapshot
    itemCatalog = {},              -- [itemID] = "name\ticon\tquality\tclassID\tsubClassID" shared across all alts
    flightTimes = {},              -- [srcNodeID][dstNodeID] = recorded base flight seconds (account-wide, zero personal data)
    recipeCatalog = {},            -- [recipeKey] = "name\tprofCode\tprofDisplay\titemID\tspellID\tquality\ticon\treagents" shared across alts
    guildRecipes = {},             -- [guildScopeKey] = bounded observed guildmate recipe matches (character names only)
    clan = {},                     -- [guildScopeKey] = { myTag, myNote, myProf1, myProf2, myCraftNote, peers, events }
    socialMeta = {},               -- [scopeKey] = { [lookupKey] = { folder, mainName, note, flag, favorite } }
    friendPresence = {},           -- [scopeKey] = { [lookupKey] = { lastSeen, lastArea, lastClass, lastLevel, favorite } } (strictly zero BattleTag/Real ID)
    mySocialProfile = {
        enabled = false,
        role = "DPS",
        availability = "OPEN",
        langs = "PT/EN",
        hours = "",
        bio = "",
    },
    socialProfiles = {},           -- [scopeKey] = { [lookupKey] = { role, availability, langs, hours, bio, updatedAt } }
    recentCompanions = {},         -- [scopeKey] = { [lookupKey] = { name, classFile, level, zone, role, lastSeen } }
    locationShareAllow = {},       -- [scopeKey] = { [lookupKey] = true } permanently approved live map-tracking peers (char keys only, zero BattleTag/Real ID)
    chatHistory = {},              -- [scopeKey] = { [threadKey] = { ... } }
    chatEditHistory = {},          -- bounded persistent official EditBox typed lines (never stores BattleTags/Real IDs)
    chatRooms = {},                -- [scopeKey] = { [roomId] = { id, name, owner, scope, members } }
    addonPeers = {},               -- [scopeKey] = { [lookupKey] = { displayName, version, lastSeenAt } } (strictly WoW char names, zero Real ID)
    worldBuffsDrops = {},          -- [realmPool] = { [buffId] = timestamp }
    worldBuffsHistory = {},        -- [realmPool] = { [buffId] = { [hour0..23] = count } }
    worldBuffsPersonal = {},       -- [charKey] = { saygeAt = ts, saygePlayed = playedSec }
    instanceRuns = {},             -- [i] = { sig, name, instType, enteredAt, charName, classFile }
    dungeonHistory = {},           -- [i] = { id, z, t, st, en, dur, bk, bn, er, ch, cl, rl, m = { ... } } (capped at 80 runs)
    lootRollHistory = {},          -- [i] = { id, rollID, ts, zone, charName, ... } persistent group loot roll results (capped at 80)
    lfgPresets = {},               -- [i] = { name, state } account-wide saved LFG filter presets (max 20)
}

local function DeepCopyValue(val)
    if type(val) ~= "table" then
        return val
    end
    local copy = {}
    for k, v in pairs(val) do
        copy[k] = DeepCopyValue(v)
    end
    return copy
end

local USER_MAP_SETTING_KEYS = {
    chatMutedThreads = true,
    chatMutedThreadRules = true,
    lfgWatchedActivities = true,
    lfgBrowseSelectedActivities = true,
    chatQuickReplies = true,
    chatQuickRepliesByContext = true,
    quickReplyHotkeys = true,
    abilityChatMacros = true,
    chatButtonPositionsByRes = true,
    quickBarButtons = true,
    addonChatFrames = true,
    socialCollapsedSections = true,
}

local function ApplyDefaults(target, defaults, shallowMapKeys)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if shallowMapKeys and shallowMapKeys[k] then
                if target[k] == nil then
                    target[k] = DeepCopyValue(v)
                end
            else
                if type(target[k]) ~= "table" then target[k] = {} end
                ApplyDefaults(target[k], v)
            end
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

local function SyncRuntimeProfileVisuals()
    for _, ev in ipairs({ "SETTINGS_UPDATED", "CLAN_UPDATED", "CHAT_UPDATED", "WATCHLIST_UPDATED", "NEARBY_UPDATED", "SOCIAL_UPDATED" }) do
        ns:Emit(ev)
    end
    if ns.Theme and ns.Theme.NotifyChanged then
        pcall(ns.Theme.NotifyChanged, ns.Theme)
    end
    if ns.Minimap and ns.Minimap.Update then
        pcall(ns.Minimap.Update, ns.Minimap)
    end
    if ns.Settings and ns.Settings.Refresh then
        pcall(ns.Settings.Refresh, ns.Settings)
    end
    if ns.UI and ns.UI.QueueRefresh then
        ns.UI:QueueRefresh(false)
    end
end

local boot = {}

local function HandleSlash(raw)
    local msg = (raw or ""):match("^%s*(.-)%s*$")
    local cmd, rest = msg:match("^(%S+)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()

    if cmd == "add" and rest ~= "" then
        if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("watchlist") then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        if ns.Watchlist and ns.Watchlist.Add then
            ns.Watchlist:Add(rest)
        end
    elseif (cmd == "check" or cmd == "who") and rest ~= "" then
        if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("watchlist") then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        if ns.Watchlist and ns.Watchlist.AddAndCheck then
            ns.Watchlist:AddAndCheck(rest)
        end
    elseif cmd == "check" or cmd == "who" then
        if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("watchlist") then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        if ns.Watchlist and ns.Watchlist.CheckNext then
            ns.Watchlist:CheckNext()
        end
    elseif cmd == "update" or cmd == "version" then
        if ns.UI and ns.UI.OpenUpdateModal then
            ns.UI:OpenUpdateModal()
        end
    elseif cmd == "chat" or cmd == "rooms" then
        if ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
            ns.LFGFrameTab:OpenOfficialModule(cmd)
        elseif ns.UI and ns.UI.OpenTab then
            ns.UI:OpenTab("chat")
        end
    elseif cmd == "group" or cmd == "instance" then
        if ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
            ns.LFGFrameTab:OpenOfficialModule("group")
        elseif ns.UI and ns.UI.OpenTab then
            ns.UI:OpenTab("group")
        end
    elseif cmd == "watchlist" or cmd == "social" or cmd == "nearby" or cmd == "alts" then
        if ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
            ns.LFGFrameTab:OpenOfficialModule(cmd)
        elseif ns.UI and ns.UI.OpenTab then
            ns.UI:OpenTab(cmd)
        end
    elseif cmd == "recipes" or cmd == "recipe" or cmd == "crafts" or cmd == "receitas" or cmd == "receita" then
        if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("alts") then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        ns:NavigateToModule("alts", {
            altSubTab = "items",
            altBagSource = "recipes",
            altAllAlts = true,
            altSearch = rest or "",
        })
    elseif cmd == "al" or cmd == "alliance" then
        if ns.Compat and ns.Compat.IsModuleEnabled and (not ns.Compat.IsModuleEnabled("clan") or not ns.Compat.IsModuleEnabled("chat")) then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        if rest and rest ~= "" then
            if ns.Chat and ns.Chat.SendAllianceMessage then
                ns.Chat:SendAllianceMessage(rest)
            end
        else
            if ns.Chat and ns.Chat.EnsureStaticChannelThread then
                ns.Chat:EnsureStaticChannelThread("ch:alliance")
            end
            local qrEnabled = (not ns.db or not ns.db.settings or ns.db.settings.quickReplyEnabled ~= false)
            if qrEnabled and ns.QuickReply and ns.QuickReply.OpenThread and ns.QuickReply:OpenThread("ch:alliance", true) then
                return
            end
            if ns.Chat and ns.Chat.SetActiveThread then
                ns.Chat:SetActiveThread("ch:alliance")
            end
            if ns.UI and ns.UI.ShowHub then
                if ns.UI.SetChatNavigation then
                    ns.UI:SetChatNavigation({ chatThreadKey = "ch:alliance" })
                end
                ns.UI:ShowHub("chat")
            elseif ns.UI and ns.UI.OpenTab then
                ns.UI:OpenTab("chat")
            end
        end
    elseif cmd == "clan" or cmd == "lfg" or cmd == "diplomacy" then
        if ns.Clan and ns.Clan.SetPreferredRightView and cmd == "diplomacy" then
            ns.Clan:SetPreferredRightView("diplomacy")
        end
        if ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
            ns.LFGFrameTab:OpenOfficialModule(cmd)
        elseif ns.UI and ns.UI.OpenTab then
            ns.UI:OpenTab("clan")
        end
    elseif cmd == "hub" or cmd == "window" then
        if ns.UI and ns.UI.ShowHub then
            ns.UI:ShowHub()
        elseif ns.UI and ns.UI.Toggle then
            ns.UI:Toggle()
        end
    elseif cmd == "radar" or cmd == "spotter" or cmd == "targets" then
        if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("radar") then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        if ns.SpotterHUD and ns.SpotterHUD.Toggle then
            ns.SpotterHUD:Toggle()
        end
    elseif cmd == "toast" or cmd == "test" or cmd == "notify" then
        if rest == "radar" or rest == "hud" or rest == "spotter" then
            if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("radar") then
                ns:Print("%s", L["This module is disabled in Settings."])
                return
            end
            if ns.SpotterHUD and ns.SpotterHUD.Toggle then
                ns.SpotterHUD:Toggle()
            end
        elseif ns.NotificationToast and ns.NotificationToast.ShowTestNotification then
            ns.NotificationToast:ShowTestNotification(rest)
        end
    elseif cmd == "preview" or cmd == "msgpreview" then
        if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("chat") then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        if ns.MinimapPreview and ns.MinimapPreview.ShowTestPreview then
            ns.MinimapPreview:ShowTestPreview(rest)
        end
    elseif cmd == "mentions" or cmd == "keywords" then
        if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("chat") then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        if rest == "config" or rest == "edit" then
            if ns.SocialPanels and ns.SocialPanels.OpenMentionKeywordsModal then
                ns.SocialPanels:OpenMentionKeywordsModal()
            end
        elseif rest == "test" then
            if ns.Chat and ns.Chat.TriggerTestMention then
                ns.Chat:TriggerTestMention()
            end
        else
            ns:NavigateToModule("chat", { threadKey = "mentions:radar" })
        end
    elseif cmd == "rolls" or cmd == "rollresults" or cmd == "lootresults" then
        if ns.LootRollUI and ns.LootRollUI.OpenResultsWindow then
            ns.LootRollUI:OpenResultsWindow()
        elseif ns.LootRoll and ns.LootRoll.RunPreviewSimulation then
            ns.LootRoll:RunPreviewSimulation("")
        end
    elseif cmd == "roll" or cmd == "lootroll" or cmd == "needroll" then
        local sub = type(rest) == "string" and rest:lower():match("^%s*(%S*)") or ""
        if sub == "" or sub == "results" or sub == "history" or sub == "res" then
            if ns.LootRollUI and ns.LootRollUI.OpenResultsWindow then
                ns.LootRollUI:OpenResultsWindow()
            end
        elseif sub == "button" or sub == "btn" then
            if ns.LootRollUI and ns.LootRollUI.ToggleResultsButtonVisibility then
                ns.LootRollUI:ToggleResultsButtonVisibility()
            end
        elseif sub == "preview" or sub == "test" or sub == "sim" then
            if ns.LootRoll and ns.LootRoll.RunPreviewSimulation then
                ns.LootRoll:RunPreviewSimulation("")
            end
        elseif ns.LootRoll and ns.LootRoll.RunPreviewSimulation then
            ns.LootRoll:RunPreviewSimulation(rest)
        end
    elseif cmd == "ignore" or cmd == "block" then
        if ns.SocialPanels and ns.SocialPanels.OpenAccountIgnoreModal then
            local targetName = (rest and rest ~= "") and rest or nil
            if not targetName and UnitExists and UnitIsPlayer and UnitExists("target") and UnitIsPlayer("target") then
                local resolved = ns.Compat and ns.Compat.ResolveUnitFullName and ns.Compat.ResolveUnitFullName("target", nil, nil, true)
                targetName = (resolved and resolved.fullName) or (UnitName and ns.Safe and ns.Safe.String(ns.Safe.Call(UnitName, "target")))
            end
            ns.SocialPanels:OpenAccountIgnoreModal(targetName, targetName)
        end
    elseif cmd == "spam" or cmd == "filtered" then
        if ns.SocialPanels and ns.SocialPanels.OpenFilteredChatModal then
            ns.SocialPanels:OpenFilteredChatModal()
        end
    elseif cmd == "export" or cmd == "import" or cmd == "backup" then
        if ns.SocialPanels and ns.SocialPanels.OpenSocialExportImportModal then
            ns.SocialPanels:OpenSocialExportImportModal(cmd == "import")
        end
    elseif cmd == "copychat" or cmd == "copy" then
        if ns.Chat and ns.Chat.OpenCopyOfficialChat then
            ns.Chat:OpenCopyOfficialChat(tonumber(rest))
        end
    elseif cmd == "runs" or cmd == "dungeons" or cmd == "masmorras" or cmd == "historico" then
        if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("group") then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        if ns.UI and ns.UI.OpenGroupRunsView then
            ns.UI:OpenGroupRunsView()
        elseif ns.UI and ns.UI.ShowHub then
            ns.UI:ShowHub("group")
        end
    elseif cmd == "quickreply" or cmd == "qr" then
        if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("chat") then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        if ns.QuickReply and ns.QuickReply.OpenPreviewOrLatest then
            ns.QuickReply:OpenPreviewOrLatest()
        end
    elseif cmd == "bar" or cmd == "quickbar" or cmd == "barra" then
        if ns.QuickBar then
            local sub = type(rest) == "string" and rest:lower():match("^%s*(%S*)") or ""
            if sub == "config" or sub == "custom" or sub == "edit" then
                ns.QuickBar:OpenCustomizeModal()
            elseif sub == "rotate" or sub == "flip" or sub == "v" or sub == "h" then
                ns.QuickBar:ToggleOrientation()
            else
                local curOn = not (ns.db and ns.db.settings and ns.db.settings.quickBarEnabled == false)
                ns.QuickBar:SetEnabled(not curOn)
            end
        end
    elseif cmd == "resetpos" or cmd == "reset" then
        if ns.Theme and ns.Theme.ResetAllWindowPositions then
            ns.Theme:ResetAllWindowPositions()
        end
    elseif cmd == "demo" or cmd == "showcase" or cmd == "cleardemo" then
        local sub = (cmd == "cleardemo") and "clear" or (type(rest) == "string" and rest:lower():match("^%s*(%S*)") or "")
        if not (ns.DemoShowcase and ns.DemoShowcase.Enable) then
            ns:Print("|cffffb833%s|r", L["Restart World of Warcraft completely to load Demo Mode."])
            return
        end
        if sub == "clear" or sub == "off" or sub == "hide" or sub == "reset" or sub == "stop" or sub == "limpar" then
            ns.DemoShowcase:Clear()
        elseif sub == "toggle" then
            ns.DemoShowcase:Toggle()
        else
            ns.DemoShowcase:Enable()
        end
    elseif cmd == "config" or cmd == "settings" then
        if ns.Settings and ns.Settings.Toggle then
            ns.Settings:Toggle()
        elseif ns.Settings and ns.Settings.Open then
            ns.Settings:Open()
        end
    elseif cmd == "help" or cmd == "?" then
        local function ModOn(m)
            return not (ns.Compat and ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled(m)
        end
        ns:Print("|cff58a6ffSocialCentral|r v%s", ns.version or "0.0.0")
        ns:Print("  |cffffd200/sc|r — %s", L["Settings"])
        if ModOn("lfg") then ns:Print("  |cffffd200/sc lfg|r — %s", L["Looking for Group (I)"]) end
        if ModOn("chat") then ns:Print("  |cffffd200/sc chat|r — %s", L["Open Conversations"]) end
        if ModOn("clan") then ns:Print("  |cffffd200/al <msg>|r — %s", L["Alliance / Clan Chat"]) end
        if ModOn("group") then
            ns:Print("  |cffffd200/sc group|r — %s", L["Open Group"])
            ns:Print("  |cffffd200/sc runs|r — %s", L["Dungeon & Raid Log"])
        end
        if ModOn("clan") then ns:Print("  |cffffd200/sc clan|r — %s", L["Open Clan"]) end
        if ModOn("alts") then ns:Print("  |cffffd200/sc recipes [item]|r — %s", L["Search Alt & Guild Recipes"]) end
        ns:Print("  |cffffd200/sc hub|r — %s", L["Unified Hub (/sc hub)"])
        ns:Print("  |cffffd200/sc bar [config|rotate]|r — %s", L["Quick Access Bar"])
        if ModOn("radar") then ns:Print("  |cffffd200/sc radar|r — %s", L["Target Radar"]) end
        ns:Print("  |cffffd200/sc toast [invite|friend|watchlist|buff|queue|clear]|r — %s", L["Test Notification Toast"])
        if ModOn("chat") then
            ns:Print("  |cffffd200/sc preview [whisper|bnet|group|guild|room|queue|setup|clear]|r — %s", L["Test Minimap Preview"])
            ns:Print("  |cffffd200/sc mentions [config|test]|r — %s", L["Mentions & Keywords Radar"])
            ns:Print("  |cffffd200/sc spam|r — %s", L["Filtered Chat Log"])
        end
        ns:Print("  |cffffd200/sc roll [winner|results|prompt|clear]|r — %s", L["Test Group Loot Roll"])
        ns:Print("  |cffffd200/sc rolls|r — %s", L["Open Loot Roll Results"])
        ns:Print("  |cffffd200/sc copychat [N]|r — %s", L["Copy Official Chat"])
        ns:Print("  |cffffd200/sc ignore [name]|r — %s", L["Account Ignore"])
        ns:Print("  |cffffd200/sc export|r — %s", L["Export / Import Social Data"])
        if ModOn("watchlist") then
            ns:Print("  |cffffd200/sc add <name>|r — %s", L["Add to Watchlist"])
            ns:Print("  |cffffd200/sc check [name]|r — %s", L["Check Watchlist character"])
        end
        ns:Print("  |cffffd200/sc resetpos|r — %s", L["Reset Window Positions"])
        ns:Print("  |cffffd200/sc demo [clear]|r — %s", L["Populate or clear hypothetical demo data across all windows"])
    else
        if ns.Settings and ns.Settings.Toggle then
            ns.Settings:Toggle()
        elseif ns.Settings and ns.Settings.Open then
            ns.Settings:Open()
        elseif ns.UI and ns.UI.Toggle then
            ns.UI:Toggle()
        end
    end
end

local ACCOUNT_TUTORIAL_KEYS = {
    "toastTutorialShown",
    "spotterPlateTutorialShown",
    "spotterRadarTutorialShown",
    "gatherHighlightTutorialShown",
    "gatherInteractTipExplained",
    "gatherSparkleTradeoffShown",
    "gatherClassicSparkleNoticeAck",
    "gatherSparkleBtnIntroAck",
    "gatherSoftDetectIntroAck",
    "quickBarIntroAck",
    "quickReplyTutorialShown",
    "msgPreviewPromptAnswered",
    "themeChosen",
    "dungeonLogPromptShown",
}

local function SyncAccountWideTutorialFlags()
    if type(SocialCentralDB) ~= "table" then return end
    if type(SocialCentralDB.accountTutorials) ~= "table" then
        SocialCentralDB.accountTutorials = {}
    end
    local acctTut = SocialCentralDB.accountTutorials
    local acctSet = ns._accountSettings or (type(SocialCentralDB.settings) == "table" and SocialCentralDB.settings) or nil
    local charSet = (type(SocialCentralCharDB) == "table" and type(SocialCentralCharDB.settings) == "table") and SocialCentralCharDB.settings or nil
    local liveSet = (ns.db and type(ns.db.settings) == "table") and ns.db.settings or nil

    for i = 1, #ACCOUNT_TUTORIAL_KEYS do
        local k = ACCOUNT_TUTORIAL_KEYS[i]
        local done = (acctTut[k] == true)
            or (acctSet and acctSet[k] == true)
            or (charSet and charSet[k] == true)
            or (liveSet and liveSet[k] == true)
        if done then
            acctTut[k] = true
            if acctSet then acctSet[k] = true end
            if charSet then charSet[k] = true end
            if liveSet then liveSet[k] = true end
        end
    end

    if type(acctTut.shortcutPromptAnswered) ~= "table" then
        acctTut.shortcutPromptAnswered = {}
    end
    for _, wk in ipairs({ "O", "I", "J", "C" }) do
        local wDone = (acctTut.shortcutPromptAnswered[wk] == true)
            or (acctSet and type(acctSet.shortcutPromptAnswered) == "table" and acctSet.shortcutPromptAnswered[wk] == true)
            or (charSet and type(charSet.shortcutPromptAnswered) == "table" and charSet.shortcutPromptAnswered[wk] == true)
            or (liveSet and type(liveSet.shortcutPromptAnswered) == "table" and liveSet.shortcutPromptAnswered[wk] == true)
        if wDone then
            acctTut.shortcutPromptAnswered[wk] = true
            if acctSet then
                if type(acctSet.shortcutPromptAnswered) ~= "table" then acctSet.shortcutPromptAnswered = {} end
                acctSet.shortcutPromptAnswered[wk] = true
            end
            if charSet then
                if type(charSet.shortcutPromptAnswered) ~= "table" then charSet.shortcutPromptAnswered = {} end
                charSet.shortcutPromptAnswered[wk] = true
            end
            if liveSet then
                if type(liveSet.shortcutPromptAnswered) ~= "table" then liveSet.shortcutPromptAnswered = {} end
                liveSet.shortcutPromptAnswered[wk] = true
            end
        end
    end
end

function ns:IsAccountTutorialShown(key)
    if not key then return false end
    if SocialCentralDB and type(SocialCentralDB.accountTutorials) == "table" and SocialCentralDB.accountTutorials[key] == true then
        return true
    end
    if ns._accountSettings and ns._accountSettings[key] == true then
        return true
    end
    if ns.db and ns.db.settings and ns.db.settings[key] == true then
        return true
    end
    return false
end

function ns:SetAccountTutorialShown(key, shown)
    if not key then return end
    local val = (shown ~= false) and true or false
    if SocialCentralDB then
        if type(SocialCentralDB.accountTutorials) ~= "table" then
            SocialCentralDB.accountTutorials = {}
        end
        SocialCentralDB.accountTutorials[key] = val
    end
    if ns._accountSettings then
        ns._accountSettings[key] = val
    end
    if SocialCentralCharDB and type(SocialCentralCharDB.settings) == "table" then
        SocialCentralCharDB.settings[key] = val
    end
    if ns.db and ns.db.settings then
        ns.db.settings[key] = val
    end
end

ns.RegisterEvent(boot, "ADDON_LOADED", function(_, _, loaded)
    if loaded ~= ADDON_NAME then return end
    SocialCentralDB = SocialCentralDB or {}
    SocialCentralCharDB = SocialCentralCharDB or {}
    if type(SocialCentralCharDB.lfg) ~= "table" then
        SocialCentralCharDB.lfg = {}
    end
    ApplyDefaults(SocialCentralDB, DEFAULTS)
    if SocialCentralDB.settings and SocialCentralDB.settings.spotterV2Migrated ~= true then
        -- One-time upgrade from previously deactivated 0.2.7 Target Radar defaults; user toggles persist afterwards.
        SocialCentralDB.settings.spotterEnabled = true
        SocialCentralDB.settings.spotterAutoShowHUD = true
        SocialCentralDB.settings.spotterPromptAnswered = true
        SocialCentralDB.settings.spotterV2Migrated = true
    end
    if SocialCentralDB.settings and SocialCentralDB.settings.friendAlertAllMigrated ~= true then
        -- Upgrade v0.2.9 default "favorites" -> "all" once so login toasts appear unless user mutes/disables manually.
        if SocialCentralDB.settings.friendOnlineAlertMode == "favorites" then
            SocialCentralDB.settings.friendOnlineAlertMode = "all"
        end
        if SocialCentralDB.settings.friendOnlineAlertToast == nil then
            SocialCentralDB.settings.friendOnlineAlertToast = true
        end
        if type(SocialCentralDB.settings.alerts) == "table" and SocialCentralDB.settings.alerts.toast == nil then
            SocialCentralDB.settings.alerts.toast = true
        end
        SocialCentralDB.settings.friendAlertAllMigrated = true
    end
    if SocialCentralDB.settings and SocialCentralDB.settings.msgPreviewDefault6Migrated ~= true then
        if SocialCentralDB.settings.msgPreviewDuration == 5 then
            SocialCentralDB.settings.msgPreviewDuration = 6
        end
        SocialCentralDB.settings.msgPreviewDefault6Migrated = true
    end
    if SocialCentralDB.settings and SocialCentralDB.settings.chatSoundCooldownDefault6Migrated ~= true then
        if SocialCentralDB.settings.chatSoundCooldown == 3 then
            SocialCentralDB.settings.chatSoundCooldown = 6
        end
        SocialCentralDB.settings.chatSoundCooldownDefault6Migrated = true
    end
    if SocialCentralDB.settings and SocialCentralDB.settings.toastBelowChatMigrated ~= true then
        if type(SocialCentralDB.windowPositions) == "table" then
            SocialCentralDB.windowPositions["notification_toast"] = nil
        end
        SocialCentralDB.settings.toastBelowChatMigrated = true
    end
    if SocialCentralDB.settings and SocialCentralDB.settings.focusUpgradeV1Migrated ~= true then
        if SocialCentralDB.settings.addonMsgToast == true then
            SocialCentralDB.settings.addonMsgToast = false
        end
        if SocialCentralDB.settings.msgPreviewSilenceCombat == false then
            SocialCentralDB.settings.msgPreviewSilenceCombat = true
        end
        SocialCentralDB.settings.msgPreviewPromptAnswered = true
        SocialCentralDB.settings.focusUpgradeV1Migrated = true
    end
    if SocialCentralDB.settings and SocialCentralDB.settings.quickReplyNotifyRaidMigrated ~= true then
        if SocialCentralDB.settings.quickReplyNotifyRaid == false then
            SocialCentralDB.settings.quickReplyNotifyRaid = true
        end
        SocialCentralDB.settings.quickReplyNotifyRaidMigrated = true
    end
    if SocialCentralDB.settings and SocialCentralDB.settings.quickReplyAlwaysShowV1Migrated ~= true then
        SocialCentralDB.settings.quickReplyAutoClose = false
        SocialCentralDB.settings.quickReplyIdleFade = true
        if tonumber(SocialCentralDB.settings.quickReplyFadeDelay) == nil then
            SocialCentralDB.settings.quickReplyFadeDelay = 15
        end
        SocialCentralDB.settings.quickReplyFadeInCombat = false
        SocialCentralDB.settings.quickReplyAlwaysShowV1Migrated = true
    end
    if SocialCentralDB.settings and SocialCentralDB.settings.quickReplyFade15Migrated ~= true then
        if tonumber(SocialCentralDB.settings.quickReplyFadeDelay) == 30 then
            SocialCentralDB.settings.quickReplyFadeDelay = 15
        end
        SocialCentralDB.settings.quickReplyFade15Migrated = true
    end
    if SocialCentralDB.settings and SocialCentralDB.settings.lfgFilterCenterRoleResetV1 ~= true then
        if SocialCentralDB.settings.lfgBrowseRole == "MINE" then
            SocialCentralDB.settings.lfgBrowseRole = "ALL"
        end
        if SocialCentralDB.settings.lfgBrowseRoleV2 == "MINE" then
            SocialCentralDB.settings.lfgBrowseRoleV2 = "ALL"
        end
        if SocialCentralCharDB and type(SocialCentralCharDB.settings) == "table" then
            if SocialCentralCharDB.settings.lfgBrowseRole == "MINE" then
                SocialCentralCharDB.settings.lfgBrowseRole = "ALL"
            end
            if SocialCentralCharDB.settings.lfgBrowseRoleV2 == "MINE" then
                SocialCentralCharDB.settings.lfgBrowseRoleV2 = "ALL"
            end
        end
        SocialCentralDB.settings.lfgFilterCenterRoleResetV1 = true
    end
    if SocialCentralDB.settings and SocialCentralDB.settings.historyLimitsExpandedV2Migrated ~= true then
        if SocialCentralDB.settings.chatHistoryLimit == 100 then
            SocialCentralDB.settings.chatHistoryLimit = 300
        end
        if SocialCentralDB.settings.guildChatHistoryLimit == 125 then
            SocialCentralDB.settings.guildChatHistoryLimit = 300
        end
        if SocialCentralDB.settings.generalChatHistoryLimit == 150 then
            SocialCentralDB.settings.generalChatHistoryLimit = 300
        end
        if SocialCentralDB.settings.clanRosterHistoryLimit == 50 then
            SocialCentralDB.settings.clanRosterHistoryLimit = 150
        end
        SocialCentralDB.settings.historyLimitsExpandedV2Migrated = true
    end
    if SocialCentralDB.settings and SocialCentralDB.settings.lootRollHideOfficialV1Migrated ~= true then
        SocialCentralDB.settings.lootRollHideOfficial = true
        SocialCentralDB.settings.lootRollWinnerBanner = false
        SocialCentralDB.settings.lootRollHideOfficialV1Migrated = true
    end
    ns._accountSettings = SocialCentralDB.settings
    if SocialCentralCharDB.useCharProfile == true then
        if type(SocialCentralCharDB.settings) ~= "table" then
            SocialCentralCharDB.settings = DeepCopyValue(ns._accountSettings or DEFAULTS.settings)
        else
            ApplyDefaults(SocialCentralCharDB.settings, ns._accountSettings or DEFAULTS.settings, USER_MAP_SETTING_KEYS)
            if SocialCentralCharDB.settings.msgPreviewDefault6Migrated ~= true then
                if SocialCentralCharDB.settings.msgPreviewDuration == 5 then
                    SocialCentralCharDB.settings.msgPreviewDuration = 6
                end
                SocialCentralCharDB.settings.msgPreviewDefault6Migrated = true
            end
            if SocialCentralCharDB.settings.chatSoundCooldownDefault6Migrated ~= true then
                if SocialCentralCharDB.settings.chatSoundCooldown == 3 then
                    SocialCentralCharDB.settings.chatSoundCooldown = 6
                end
                SocialCentralCharDB.settings.chatSoundCooldownDefault6Migrated = true
            end
            if SocialCentralCharDB.settings.focusUpgradeV1Migrated ~= true then
                if SocialCentralCharDB.settings.addonMsgToast == true then
                    SocialCentralCharDB.settings.addonMsgToast = false
                end
                if SocialCentralCharDB.settings.msgPreviewSilenceCombat == false then
                    SocialCentralCharDB.settings.msgPreviewSilenceCombat = true
                end
                SocialCentralCharDB.settings.msgPreviewPromptAnswered = true
                SocialCentralCharDB.settings.focusUpgradeV1Migrated = true
            end
            if SocialCentralCharDB.settings.quickReplyNotifyRaidMigrated ~= true then
                if SocialCentralCharDB.settings.quickReplyNotifyRaid == false then
                    SocialCentralCharDB.settings.quickReplyNotifyRaid = true
                end
                SocialCentralCharDB.settings.quickReplyNotifyRaidMigrated = true
            end
            if SocialCentralCharDB.settings.quickReplyAlwaysShowV1Migrated ~= true then
                SocialCentralCharDB.settings.quickReplyAutoClose = false
                SocialCentralCharDB.settings.quickReplyIdleFade = true
                if tonumber(SocialCentralCharDB.settings.quickReplyFadeDelay) == nil then
                    SocialCentralCharDB.settings.quickReplyFadeDelay = 15
                end
                SocialCentralCharDB.settings.quickReplyFadeInCombat = false
                SocialCentralCharDB.settings.quickReplyAlwaysShowV1Migrated = true
            end
            if SocialCentralCharDB.settings.quickReplyFade15Migrated ~= true then
                if tonumber(SocialCentralCharDB.settings.quickReplyFadeDelay) == 30 then
                    SocialCentralCharDB.settings.quickReplyFadeDelay = 15
                end
                SocialCentralCharDB.settings.quickReplyFade15Migrated = true
            end
            if SocialCentralCharDB.settings.lfgFilterCenterRoleResetV1 ~= true then
                if SocialCentralCharDB.settings.lfgBrowseRole == "MINE" then
                    SocialCentralCharDB.settings.lfgBrowseRole = "ALL"
                end
                if SocialCentralCharDB.settings.lfgBrowseRoleV2 == "MINE" then
                    SocialCentralCharDB.settings.lfgBrowseRoleV2 = "ALL"
                end
                SocialCentralCharDB.settings.lfgFilterCenterRoleResetV1 = true
            end
            if SocialCentralCharDB.settings.historyLimitsExpandedV2Migrated ~= true then
                if SocialCentralCharDB.settings.chatHistoryLimit == 100 then
                    SocialCentralCharDB.settings.chatHistoryLimit = 300
                end
                if SocialCentralCharDB.settings.guildChatHistoryLimit == 125 then
                    SocialCentralCharDB.settings.guildChatHistoryLimit = 300
                end
                if SocialCentralCharDB.settings.generalChatHistoryLimit == 150 then
                    SocialCentralCharDB.settings.generalChatHistoryLimit = 300
                end
                if SocialCentralCharDB.settings.clanRosterHistoryLimit == 50 then
                    SocialCentralCharDB.settings.clanRosterHistoryLimit = 150
                end
                SocialCentralCharDB.settings.historyLimitsExpandedV2Migrated = true
            end
            if SocialCentralCharDB.settings.lootRollHideOfficialV1Migrated ~= true then
                SocialCentralCharDB.settings.lootRollHideOfficial = true
                SocialCentralCharDB.settings.lootRollWinnerBanner = false
                SocialCentralCharDB.settings.lootRollHideOfficialV1Migrated = true
            end
        end
        SocialCentralDB.settings = SocialCentralCharDB.settings
    end
    ns.db = SocialCentralDB
    ns.charDb = SocialCentralCharDB
    SyncAccountWideTutorialFlags()
    ns.UnregisterEvent(boot, "ADDON_LOADED")
end)

function ns:IsCharProfileEnabled()
    return (SocialCentralCharDB and SocialCentralCharDB.useCharProfile == true) or false
end

function ns:SetCharProfileEnabled(enabled)
    SocialCentralCharDB = SocialCentralCharDB or {}
    local useChar = enabled and true or false
    SocialCentralCharDB.useCharProfile = useChar
    if useChar then
        if type(SocialCentralCharDB.settings) ~= "table" or next(SocialCentralCharDB.settings) == nil then
            SocialCentralCharDB.settings = DeepCopyValue(ns._accountSettings or DEFAULTS.settings)
        else
            ApplyDefaults(SocialCentralCharDB.settings, ns._accountSettings or DEFAULTS.settings, USER_MAP_SETTING_KEYS)
        end
        if ns.db then
            ns.db.settings = SocialCentralCharDB.settings
        end
    else
        if ns.db and ns._accountSettings then
            ns.db.settings = ns._accountSettings
        end
    end
    SyncRuntimeProfileVisuals()
end

function ns:CopyAccountSettingsToChar()
    if not ns:IsCharProfileEnabled() then
        return false
    end
    SocialCentralCharDB = SocialCentralCharDB or {}
    local src = ns._accountSettings or DEFAULTS.settings
    SocialCentralCharDB.settings = DeepCopyValue(src)
    ApplyDefaults(SocialCentralCharDB.settings, DEFAULTS.settings, USER_MAP_SETTING_KEYS)
    if ns.db then
        ns.db.settings = SocialCentralCharDB.settings
    end
    SyncRuntimeProfileVisuals()
    return true
end

function ns:ResetCurrentSettingsToDefaults()
    local fresh = DeepCopyValue(DEFAULTS.settings)
    -- Keep one-time legacy migrations marked complete so user choices after a reset are never reverted on reload.
    fresh.spotterV2Migrated = true
    fresh.friendAlertAllMigrated = true
    fresh.msgPreviewDefault6Migrated = true
    fresh.chatSoundCooldownDefault6Migrated = true
    fresh.toastBelowChatMigrated = true
    fresh.focusUpgradeV1Migrated = true
    fresh.quickReplyNotifyRaidMigrated = true
    fresh.quickReplyAlwaysShowV1Migrated = true
    fresh.quickReplyFade15Migrated = true
    fresh.lfgFilterCenterRoleResetV1 = true
    fresh.historyLimitsExpandedV2Migrated = true
    fresh.lootRollHideOfficialV1Migrated = true
    if ns:IsCharProfileEnabled() then
        SocialCentralCharDB = SocialCentralCharDB or {}
        SocialCentralCharDB.settings = fresh
        if ns.db then
            ns.db.settings = SocialCentralCharDB.settings
        end
    else
        if SocialCentralDB then
            SocialCentralDB.settings = fresh
        end
        ns._accountSettings = fresh
        if ns.db then
            ns.db.settings = fresh
        end
    end
    SyncRuntimeProfileVisuals()
    return true
end

ns.RegisterEvent(boot, "PLAYER_LOGOUT", function()
    if ns.DemoShowcase and ns.DemoShowcase.IsActive and ns.DemoShowcase:IsActive() then
        pcall(ns.DemoShowcase.Clear, ns.DemoShowcase, true)
    end
    SyncAccountWideTutorialFlags()
    if ns._accountSettings and SocialCentralDB then
        SocialCentralDB.settings = ns._accountSettings
    end
end)

ns.RegisterEvent(boot, "PLAYER_LOGIN", function()
    if ns.Store and ns.Store.NormalizeLegacyRealmScopes then
        pcall(ns.Store.NormalizeLegacyRealmScopes, ns.Store)
    end
    if ns.Store and ns.Store.MigrateLegacyFavorites then
        pcall(ns.Store.MigrateLegacyFavorites, ns.Store)
    end
    for _, mod in ipairs(ns.modules) do
        if type(mod.Init) == "function" then
            local ok, err = pcall(mod.Init, mod)
            if not ok and geterrorhandler then geterrorhandler()(err) end
        end
    end

    SLASH_SOCIALCENTRAL1 = "/sc"
    SLASH_SOCIALCENTRAL2 = "/socialcentral"
    SlashCmdList.SOCIALCENTRAL = HandleSlash

    SLASH_SOCIALCENTRAL_AL1 = "/al"
    SLASH_SOCIALCENTRAL_AL2 = "/ali"
    SLASH_SOCIALCENTRAL_AL3 = "/ally"
    SlashCmdList.SOCIALCENTRAL_AL = function(msg)
        local text = msg and msg:match("^%s*(.-)%s*$") or ""
        HandleSlash("al " .. text)
    end

    if ns.Settings and ns.Settings.Register then
        pcall(ns.Settings.Register, ns.Settings)
    end
    if ns.Minimap and ns.Minimap.Update then
        pcall(ns.Minimap.Update, ns.Minimap)
    end

    if ns.SetupOfficialChatConfigToggle then
        ns:SetupOfficialChatConfigToggle()
    end
    if ns.Compat and ns.Compat.InitFocusWatcher then
        pcall(ns.Compat.InitFocusWatcher)
    end
    ns._bootScopeKey = ns.Compat and ns.Compat.ScopeKey and ns.Compat.ScopeKey() or nil

    ns.UnregisterEvent(boot, "PLAYER_LOGIN")
end)

local officialChatToggleHooked = false
local officialChatConfigBtn = nil

local function RefreshOfficialChatToggleState()
    local btn = officialChatConfigBtn
    local cfg = _G.ChatConfigFrame
    if not (btn and cfg and cfg:IsShown()) then return end
    local chatFrame = cfg.chatFrame or _G.SELECTED_CHAT_FRAME or _G.DEFAULT_CHAT_FRAME
    local chatID = (chatFrame and chatFrame.GetID and tonumber(chatFrame:GetID())) or 1
    if chatID < 1 or chatID > 10 then
        btn:Hide()
        return
    end
    btn._scChatID = chatID
    local tabLabel = (chatFrame and chatFrame.name and chatFrame.name ~= "") and tostring(chatFrame.name)
        or (GetChatWindowInfo and select(1, GetChatWindowInfo(chatID)))
        or tostring(chatID)
    local framesTbl = ns.db and ns.db.settings and ns.db.settings.addonChatFrames
    local checked
    if type(framesTbl) ~= "table" then
        checked = (chatID == 1)
    else
        checked = (framesTbl[chatID] == true)
    end
    btn:SetChecked(checked and true or false)
    if btn.Text then
        btn.Text:SetText(string.format(L["[SC] Addon Chat (%s)"], tabLabel))
    end
    btn:Show()
end

function ns:RefreshOfficialChatConfigToggle()
    RefreshOfficialChatToggleState()
end

function ns:SetupOfficialChatConfigToggle()
    if officialChatToggleHooked then return true end
    local cfg = _G.ChatConfigFrame
    if not cfg then
        if not self._scWaitingBlizzChatConfig then
            self._scWaitingBlizzChatConfig = true
            local waitHost = {}
            ns.RegisterEvent(waitHost, "ADDON_LOADED", function(_, _, loaded)
                if loaded == "Blizzard_ChatConfig" or _G.ChatConfigFrame then
                    ns.UnregisterEvent(waitHost, "ADDON_LOADED")
                    ns:SetupOfficialChatConfigToggle()
                end
            end)
        end
        return false
    end

    officialChatToggleHooked = true
    -- Standalone non-secure CheckButton attached cleanly onto ChatConfigFrame (never mutates Blizzard's CHAT_CONFIG_CHAT_LEFT secure arrays).
    if not officialChatConfigBtn and not (InCombatLockdown and InCombatLockdown()) then
        local btn = CreateFrame("CheckButton", "SocialCentralOfficialChatTabToggle", cfg, "UICheckButtonTemplate")
        btn:SetSize(22, 22)
        if _G.ChatConfigFrameDefaultButton then
            btn:SetPoint("LEFT", _G.ChatConfigFrameDefaultButton, "RIGHT", 16, 0)
        else
            btn:SetPoint("BOTTOM", cfg, "BOTTOM", -40, 14)
        end
        local txt = btn.Text or _G[btn:GetName() .. "Text"]
        if txt then
            btn.Text = txt
            txt:SetFontObject(GameFontNormalSmall)
            txt:SetTextColor(0.35, 0.78, 1.0)
            txt:ClearAllPoints()
            txt:SetPoint("LEFT", btn, "RIGHT", 3, 0)
            txt:SetText(L["[SC] Addon Chat"])
        end
        btn:SetScript("OnClick", function(self)
            local cid = self._scChatID or 1
            if ns.db and ns.db.settings then
                if type(ns.db.settings.addonChatFrames) ~= "table" then
                    ns.db.settings.addonChatFrames = { [1] = true }
                end
                ns.db.settings.addonChatFrames[cid] = self:GetChecked() and true or false
                ns:Emit("SETTINGS_UPDATED")
            end
        end)
        btn:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["SocialCentral Addon Chat Display"], 0.35, 0.78, 1.0)
            GameTooltip:AddLine(L["Show direct & room [SC] addon messages inside this Blizzard chat tab immediately as they arrive or are sent."], 0.85, 0.88, 0.92, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        officialChatConfigBtn = btn
    end

    if cfg.HookScript then
        cfg:HookScript("OnShow", RefreshOfficialChatToggleState)
    end
    if type(_G.ChatConfig_UpdateCheckboxes) == "function" then
        hooksecurefunc("ChatConfig_UpdateCheckboxes", RefreshOfficialChatToggleState)
    end
    RefreshOfficialChatToggleState()
    return true
end

local lastIdleGcAt = 0
local idleGcQueued = false

function ns:RequestIdleGcStep(steps, delay)
    if type(collectgarbage) ~= "function" or not (C_Timer and C_Timer.After) then
        return
    end
    local now = (GetTime and GetTime()) or 0
    if lastIdleGcAt > 0 and (now - lastIdleGcAt) < 60.0 then
        return
    end
    if idleGcQueued then
        return
    end
    idleGcQueued = true
    local stepBudget = math.max(40, math.min(140, tonumber(steps) or 100))
    C_Timer.After(tonumber(delay) or 1.2, function()
        idleGcQueued = false
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if inCombat then
            return
        end
        lastIdleGcAt = (GetTime and GetTime()) or 0
        pcall(collectgarbage, "step", stepBudget)
    end)
end

ns.RegisterEvent(boot, "PLAYER_ENTERING_WORLD", function()
    ns.UnregisterEvent(boot, "PLAYER_ENTERING_WORLD")
    if ns.Compat and ns.Compat.InvalidateRealmCache then
        ns.Compat.InvalidateRealmCache()
    end
    if ns.Store and ns.Store.InvalidateScopeCaches then
        ns.Store:InvalidateScopeCaches()
    end
    local liveScope = ns.Compat and ns.Compat.ScopeKey and ns.Compat.ScopeKey() or nil
    if liveScope and liveScope ~= "" and liveScope ~= ns._bootScopeKey then
        ns._bootScopeKey = liveScope
        if ns.Store and ns.Store.NormalizeLegacyRealmScopes then
            pcall(ns.Store.NormalizeLegacyRealmScopes, ns.Store)
        end
        if ns.Chat and ns.Chat.LoadSavedHistory then
            pcall(ns.Chat.LoadSavedHistory, ns.Chat)
        end
        if ns.Watchlist and ns.Watchlist.NormalizeStoredEntries then
            pcall(ns.Watchlist.NormalizeStoredEntries, ns.Watchlist)
        end
        for _, ev in ipairs({ "WATCHLIST_UPDATED", "CHAT_UPDATED", "SOCIAL_UPDATED", "CLAN_UPDATED" }) do
            ns:Emit(ev)
        end
    end
    if ns.Compat and ns.Compat.SyncRosterForeverNames then
        ns.Compat.SyncRosterForeverNames(false, true)
    end
    if C_Timer and C_Timer.After and type(collectgarbage) == "function" then
        C_Timer.After(9.0, function()
            if not (InCombatLockdown and InCombatLockdown()) then
                lastIdleGcAt = (GetTime and GetTime()) or 0
                pcall(collectgarbage, "step", 140)
            end
        end)
    end
    if ns.db and ns.db.settings and not ns.db.settings.themeChosen then
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if not inCombat and ns.Theme and ns.Theme.ShowThemeWelcomePicker then
            ns.Theme:ShowThemeWelcomePicker()
        end
    end
end)

-- Addon Compartment integration (WoW: Forever / modern minimap menu).
function SocialCentral_OnAddonCompartmentClick(_, mouseInput)
    local btnName = type(mouseInput) == "table" and mouseInput.buttonName or mouseInput
    if btnName == "RightButton" then
        if ns.Settings and ns.Settings.Toggle then
            ns.Settings:Toggle()
        elseif ns.Settings and ns.Settings.Open then
            ns.Settings:Open()
        end
        return
    end
    if ns.Minimap and ns.Minimap.PerformSmartLeftClick then
        ns.Minimap:PerformSmartLeftClick()
    elseif ns.UI and ns.UI.ShowHub then
        ns.UI:ShowHub()
    elseif ns.Settings and ns.Settings.Toggle then
        ns.Settings:Toggle()
    end
end

function SocialCentral_OnAddonCompartmentEnter(_, owner)
    if ns.Minimap and ns.Minimap.PopulateSummaryTooltip then
        GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
        ns.Minimap:PopulateSummaryTooltip(GameTooltip)
        GameTooltip:Show()
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("|cff58a6ffSocial|rCentral")
    GameTooltip:AddLine(L["Click to open SocialCentral."], 0.85, 0.88, 0.92, true)
    GameTooltip:Show()
end

function SocialCentral_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

local navRegenHost = {}
local pendingNavigation = nil
local pendingCombatTasks = {}
local pendingCombatTaskSeq = 0

--- Run a non-protected UI/UX callback right away outside combat, or defer silently once until combat ends.
function ns:RunAfterCombat(actionId, fn, noticeText)
    if type(fn) ~= "function" then return false end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if not inCombat then
        local ok, err = pcall(fn)
        if not ok and geterrorhandler then geterrorhandler()(err) end
        return ok
    end
    local key
    if actionId ~= nil and actionId ~= "" then
        key = tostring(actionId)
    else
        pendingCombatTaskSeq = pendingCombatTaskSeq + 1
        key = "task_" .. tostring(pendingCombatTaskSeq)
    end
    local alreadyQueued = (pendingCombatTasks[key] ~= nil)
    pendingCombatTasks[key] = fn
    if (not alreadyQueued) and type(noticeText) == "string" and noticeText ~= "" then
        ns:Print("%s", noticeText)
    end
    return false
end

--- Navigate to a SocialCentral module safely, deferring official Blizzard frame opens if currently in combat.
function ns:NavigateToModule(modName, opts)
    opts = opts or {}
    if (modName == "chat" or modName == "rooms") and ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("chat") then
        ns:Print("%s", L["This module is disabled in Settings."])
        return false
    end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat and (modName == "settings" or modName == "lfg") then
        local alreadySame = (pendingNavigation and pendingNavigation.mod == modName)
        pendingNavigation = { mod = modName, opts = opts }
        if not alreadySame then
            ns:Print("%s", L["Will open right after combat ends."])
        end
        return false
    end

    if not inCombat then
        pendingNavigation = nil
    end
    if (opts.socialFilter or opts.socialSearch or opts.watchlistSearch ~= nil) and ns.UI and ns.UI.SetSocialNavigation then
        ns.UI:SetSocialNavigation(opts)
    end
    if (opts.chatFilter or opts.chatThreadKey or opts.threadKey) and ns.UI and ns.UI.SetChatNavigation then
        ns.UI:SetChatNavigation({
            chatFilter = opts.chatFilter,
            chatThreadKey = opts.chatThreadKey or opts.threadKey,
            focusInput = opts.focusInput == true,
        })
    end
    if (opts.altSubTab or opts.altBagSource or opts.altSearch ~= nil or opts.altAllAlts ~= nil or opts.altViewMode) and ns.UI and ns.UI.SetAltsNavigation then
        ns.UI:SetAltsNavigation(opts)
    end
    if opts.clanProfQuery ~= nil and ns.UI and ns.UI.SetClanProfessionQuery then
        ns.UI:SetClanProfessionQuery(opts.clanProfQuery)
    end
    if (opts.clanRightView == "browse" or opts.clanRightView == "lfg") and modName == "lfg" and ns.LFGFrameTab then
        ns.LFGFrameTab.viewMode = "browse"
        if opts.lfgSelectKey and opts.lfgSelectKey ~= "" then
            ns.LFGFrameTab.pendingSelectKey = opts.lfgSelectKey
            ns.LFGFrameTab.sourceFilter = "ALL"
            ns.LFGFrameTab.categoryFilter = "ALL"
            ns.LFGFrameTab.suitableLevelOnly = false
            ns.LFGFrameTab.query = ""
            if type(ns.LFGFrameTab.browseActivityFilter) == "table" then
                wipe(ns.LFGFrameTab.browseActivityFilter)
            end
            if ns.LFG and ns.LFG.ResetAdvancedFilters then
                ns.LFG:ResetAdvancedFilters()
            end
        end
    elseif opts.clanRightView and ns.Clan and ns.Clan.SetPreferredRightView then
        ns.Clan:SetPreferredRightView(opts.clanRightView)
    end
    if opts.pendingRoomId and not opts.threadKey and ns.Chat and ns.Chat.SetActiveThread and ns.Chat.GetRoom and ns.Chat:GetRoom(opts.pendingRoomId) then
        ns.Chat:SetActiveThread("room:" .. tostring(opts.pendingRoomId))
    end
    if opts.threadKey and ns.Chat and ns.Chat.SetActiveThread then
        if opts.focusInput then
            ns.Chat.focusInputPending = true
        end
        ns.Chat:SetActiveThread(opts.threadKey)
    elseif (opts.targetName or opts.bnetAccountID) and ns.Chat and ns.Chat.OpenDirectConversation then
        ns.Chat.focusInputPending = true
        ns.Chat:OpenDirectConversation({
            targetName = opts.targetName,
            bnetAccountID = opts.bnetAccountID,
            bnetName = opts.bnetName,
            draftText = opts.draftText,
        })
    end

    if (modName == "clan" or modName == "lfg") and ns.Clan and ns.Clan.ClearNotificationCount then
        ns.Clan:ClearNotificationCount()
    end

    if (not inCombat) and ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
        ns.LFGFrameTab:OpenOfficialModule(modName, true)
    elseif ns.UI and ns.UI.ShowHub and inCombat then
        ns.UI:ShowHub(modName)
    elseif ns.UI and ns.UI.OpenTab then
        ns.UI:OpenTab(modName)
    end
    return true
end

ns.RegisterEvent(navRegenHost, "PLAYER_REGEN_ENABLED", function()
    if pendingNavigation then
        local job = pendingNavigation
        pendingNavigation = nil
        ns:NavigateToModule(job.mod, job.opts)
    end
    if next(pendingCombatTasks) ~= nil then
        local queued = {}
        for k, fn in pairs(pendingCombatTasks) do
            queued[k] = fn
            pendingCombatTasks[k] = nil
        end
        local doneKeys = {}
        for k, fn in pairs(queued) do
            if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
                for rk, rfn in pairs(queued) do
                    if not doneKeys[rk] and pendingCombatTasks[rk] == nil then
                        pendingCombatTasks[rk] = rfn
                    end
                end
                break
            end
            doneKeys[k] = true
            local ok, err = pcall(fn)
            if not ok and geterrorhandler then geterrorhandler()(err) end
        end
    end
end)

if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("SetItemRef", function(_, link, _, button)
        if ns.Safe and ns.Safe.IsSecret and ns.Safe.IsSecret(link) then return end
        if type(link) ~= "string" then return end
        if link:sub(1, 7) == "player:" then
            local s = ns.db and ns.db.settings
            if s and s.chatModifierQuickActions == false then return end
            if button ~= "LeftButton" then return end
            local isAlt = IsAltKeyDown and IsAltKeyDown()
            local isCtrl = IsControlKeyDown and IsControlKeyDown()
            local isShift = IsShiftKeyDown and IsShiftKeyDown()
            if isShift then return end
            local rawTarget = link:match("^player:([^:]+)")
            if not rawTarget or rawTarget == "" then return end
            if isAlt and not isCtrl then
                if InCombatLockdown and InCombatLockdown() then
                    ns:Print("%s", L["Unavailable during combat."])
                    return
                end
                if ns.Compat and ns.Compat.Invite then
                    ns.Compat.Invite(rawTarget)
                end
                if _G.ChatEdit_GetActiveWindow and _G.ChatEdit_DeactivateChat then
                    local eb = _G.ChatEdit_GetActiveWindow()
                    if eb and eb.GetText then
                        local ebTxt = eb:GetText() or ""
                        if ebTxt == "" or ebTxt:match("^/[wW]%s+%S+%s*$") then
                            eb:SetText("")
                            pcall(_G.ChatEdit_DeactivateChat, eb)
                        end
                    end
                end
            elseif isCtrl and not isAlt then
                local parsed = ns.Compat and ns.Compat.ParseCharacterName and ns.Compat.ParseCharacterName(rawTarget)
                local disp = (parsed and parsed.displayName) or rawTarget
                local lk = (parsed and parsed.lookupKey) or disp:lower()
                if ns.SocialPanels and ns.SocialPanels.OpenSocialMetaModal then
                    ns.SocialPanels:OpenSocialMetaModal(disp, lk, { displayName = disp, lookupKey = lk })
                end
            end
            return
        end
        if link:find("addon:SCentral:update", 1, true) then
            if ns.UI and ns.UI.OpenUpdateModal then
                ns.UI:OpenUpdateModal()
            end
        elseif link:find("addon:SCentral:lfgapply:", 1, true) then
            if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("lfg") then
                ns:Print("%s", L["This module is disabled in Settings."])
                return
            end
            local payload = link:match("addon:SCentral:lfgapply:([^|]+)")
            if payload and payload ~= "" then
                local who, act = payload:match("^([^:]+):(.*)$")
                who = who or payload
                if ns.LFGFrameTab and ns.LFGFrameTab.QuickApplyToPlayer then
                    ns.LFGFrameTab:QuickApplyToPlayer(who, nil, (act and act ~= "") and act or nil)
                elseif ns.Compat and ns.Compat.Whisper then
                    ns.Compat.Whisper(who)
                end
            end
        elseif link:find("addon:SCentral:clanlfg", 1, true) then
            if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("lfg") then
                ns:Print("%s", L["This module is disabled in Settings."])
                return
            end
            local lfgKey = link:match("addon:SCentral:clanlfg:([^|]+)")
            ns:NavigateToModule("lfg", { clanRightView = "browse", lfgSelectKey = lfgKey })
        elseif link:find("addon:SCentral:clanevt:", 1, true) then
            if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("clan") then
                ns:Print("%s", L["This module is disabled in Settings."])
                return
            end
            local eventId = link:match("addon:SCentral:clanevt:([^|]+)")
            ns:NavigateToModule("clan", { clanRightView = "events", eventId = eventId })
        elseif link:find("addon:SCentral:diplomacy", 1, true) then
            if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("clan") then
                ns:Print("%s", L["This module is disabled in Settings."])
                return
            end
            ns:NavigateToModule("diplomacy", { clanRightView = "diplomacy" })
        elseif link:find("addon:SCentral:spotter", 1, true) then
            if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("radar") then
                ns:Print("%s", L["This module is disabled in Settings."])
                return
            end
            if ns.SpotterHUD and ns.SpotterHUD.Show then
                ns.SpotterHUD:Show(true)
            end
        elseif link:find("addon:SCentral:target:", 1, true) then
            if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("radar") then
                ns:Print("%s", L["This module is disabled in Settings."])
                return
            end
            local targetKey = link:match("addon:SCentral:target:([^|]+)")
            if targetKey and targetKey ~= "" and ns.Spotter and ns.Spotter.FocusTarget then
                ns.Spotter:FocusTarget(targetKey)
            end
        elseif link:find("addon:SCentral:thread:", 1, true) then
            local threadKey = link:match("addon:SCentral:thread:([^|]+)")
            if threadKey and threadKey ~= "" then
                ns:NavigateToModule("chat", { threadKey = threadKey })
            end
        elseif link:find("addon:SCentral:social:", 1, true) then
            local who = link:match("addon:SCentral:social:([^|]+)")
            ns:NavigateToModule("social", { socialSearch = who or "" })
        elseif link:find("addon:SCentral:wldisambig:", 1, true) then
            local entryId = link:match("addon:SCentral:wldisambig:([^|]+)")
            if entryId and ns.UI and ns.UI.OpenWatchlistDisambiguation then
                ns:RunAfterCombat("watchlist_disambig", function()
                    ns:NavigateToModule("watchlist")
                    ns.UI:OpenWatchlistDisambiguation(entryId)
                end, L["Will finish right after combat ends."])
            end
        elseif link:find("addon:SCentral:delnote:", 1, true) then
            local noteId = link:match("addon:SCentral:delnote:([^|]+)")
            if noteId and noteId ~= "" and ns.Chat and ns.Chat.DeletePersonalNote then
                ns.Chat:DeletePersonalNote(noteId)
            end
        elseif link:find("addon:SCentral:url:", 1, true) then
            local encoded = link:match("addon:SCentral:url:([^|]+)")
            if encoded and encoded ~= "" and ns.UI and ns.UI.OpenCopyModal then
                local decoded = (ns.Chat and ns.Chat.DecodeUrlLink) and ns.Chat:DecodeUrlLink(encoded) or encoded
                ns.UI:OpenCopyModal(decoded, L["Copy Link"], L["Press Ctrl+C to copy this link to your clipboard."])
            end
        elseif link:find("addon:SCentral:mentions", 1, true) then
            if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("chat") then
                ns:Print("%s", L["This module is disabled in Settings."])
                return
            end
            ns:NavigateToModule("chat", { threadKey = "mentions:radar" })
        elseif link:find("addon:SCentral:whisper:", 1, true) then
            local target = link:match("addon:SCentral:whisper:([^|]+)")
            if target and target ~= "" and ns.Compat and ns.Compat.Whisper then
                ns.Compat.Whisper(target)
            end
        elseif link:find("addon:SCentral:lootroll:", 1, true) then
            local rollResultId = link:match("addon:SCentral:lootroll:([^|]+)")
            if ns.LootRollUI and ns.LootRollUI.OpenResultsWindow then
                ns.LootRollUI:OpenResultsWindow(rollResultId ~= "" and rollResultId or nil)
            end
        elseif link:find("addon:SCentral:buffaudit", 1, true) then
            if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("group") then
                ns:Print("%s", L["This module is disabled in Settings."])
                return
            end
            if ns.Group and ns.Group.OpenMissingBuffsDraft then
                ns.Group:OpenMissingBuffsDraft()
            end
        elseif link:find("addon:SCentral:room:", 1, true) then
            local roomId = link:match("addon:SCentral:room:([^|]+)")
            if roomId and roomId ~= "" then
                local room = ns.Chat and ns.Chat.GetRoom and ns.Chat:GetRoom(roomId)
                if room and room.joined then
                    ns:NavigateToModule("chat", { threadKey = "room:" .. roomId })
                else
                    ns:NavigateToModule("chat", { pendingRoomId = roomId })
                end
            end
        else
            local who = link:match("addon:SCentral:w:([^|]+)")
            if who and who ~= "" then
                local lookup = ns.Compat and ns.Compat.ParseCharacterFields and ns.Compat.ParseCharacterFields(who)
                    or (ns.Compat and ns.Compat.LowerUtf8 and ns.Compat.LowerUtf8(who))
                    or who:lower()
                local bInfo = ns.Social and ns.Social.GetBNetLinkInfo and lookup and ns.Social:GetBNetLinkInfo(lookup)
                local bnetAccId = bInfo and bInfo.bnetAccountID or nil
                local bnetName = bInfo and bInfo.bnetName or nil
                local addonAllowed = (not ns.Compat or not ns.Compat.IsOfficialChatMode or not ns.Compat.IsOfficialChatMode())
                    and (not ns.Compat or not ns.Compat.IsModuleEnabled or ns.Compat.IsModuleEnabled("chat"))
                local scConfirmed = addonAllowed and ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(who, bnetAccId)
                if scConfirmed and ns.Chat and ns.Chat.OpenPreferredConversation then
                    ns.Chat:OpenPreferredConversation({
                        targetName = who,
                        lookupKey = lookup,
                        bnetAccountID = bnetAccId,
                        bnetName = bnetName,
                        scConfirmed = true,
                    })
                elseif ns.Compat and ns.Compat.Whisper then
                    ns.Compat.Whisper(who)
                end
            end
        end
    end)
end
