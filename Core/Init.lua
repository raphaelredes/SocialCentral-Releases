local ADDON_NAME, ns = ...

local L = ns.L
ns.name = ADDON_NAME
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "0.2.17"
if ns.version == "" or ns.version:find("^@") then ns.version = "0.2.17" end
ns.sessionStartedAt = ns.sessionStartedAt or time()
ns.RELEASE_REPO = "raphaelredes/SocialCentral-Releases"
ns.RELEASE_URL = "https://github.com/" .. ns.RELEASE_REPO .. "/releases/latest"

ns.modules = {}
ns.listeners = {}

function ns:Print(fmt, ...)
    local text = select("#", ...) > 0 and fmt:format(...) or tostring(fmt)
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
            lock = false,
        },
        minimapLeftClickAction = "smart", -- "smart" (unread chat or main hub) | "hub" | "menu"
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
        chatSoundWhispers = true,   -- chime on Character & Battle.net whispers
        chatSoundRooms = true,      -- chime on Addon Private Chat Room messages & invites
        chatSoundAlliance = true,   -- chime on Alliance chat addon messages
        chatSoundGuild = false,     -- Guild / Officer chat sound muted by default
        chatSoundGroup = false,     -- Party / Raid / Instance chat sound muted by default
        chatMirrorChannels = true,  -- mirror native WoW Guild/Party/Raid channels inside Conversations
        chatChannelUnread = false,  -- opt-in: allow mirrored WoW channels to increment unread badges
        chatMutedThreads = {},      -- per-conversation mute map [threadKey] = true
        chatHistoryLimit = 30,      -- local lines kept per character conversation thread
        addonDirectChat = true,     -- enable verified 1-on-1 SocialCentral direct chat & peer handshake
        chatDirectOfficialSend = true, -- send official /w, Battle.net, and guild/group replies in 1 click from Conversations (hardware-event only)
        addonMsgToast = true,       -- show compact floating toast pill when addon messages arrive
        addonMsgChatEcho = true,    -- echo clickable [SC] summary line to Blizzard chat windows for incoming addon messages
        addonMsgChatEchoSent = true, -- echo sent [SC] addon messages into Blizzard chat windows immediately
        addonChatFrames = { [1] = true }, -- [chatFrameIndex 1..10] Blizzard chat tabs showing [SC] addon chat (1 = General)
        addonMsgTaskbarFlash = true, -- pulse game taskbar icon on incoming addon messages
        addonMsgMinimapBadge = true, -- display compact unread counter badge on Minimap button
        addonMsgTabBadges = true,   -- display compact unread badges on Social (O) & Guild (J) side-tabs
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
        spotterPromptAnswered = true, -- keep HUD clutter-free without unsolicited confirmation popups
        spotterLockHUD = false,     -- lock target HUD position against accidental dragging
        spotterNameplateArrow = true, -- show animated red arrow above focused/selected target nameplate when visible
        spotterNameplateBadges = true, -- show lightweight stance tags above visible tracked player nameplates
        spotterNameplateTargetHighlight = true, -- highlight selected target overhead name & info cleanly above nameplate
        altsWorldScope = "pool", -- "pool" | "all" | "world:<PvP|PvE|RP-PvE|RP-PvP|RP>" | "pool:<realmPool>"
        spotterPlateTutorialShown = false, -- show one-time nameplate tutorial (Shift+V / V) on first radar sighting
        spotterRadarTutorialShown = false, -- show one-time target radar proximity tutorial on first radar tracking
        spotterV2Migrated = false,  -- one-time migration from legacy deactivated spotter defaults
        worldBuffsAlerts = true,    -- notify when a Classic World Buff is announced by an NPC
        worldBuffsSound = true,     -- audio chime on incoming World Buff drop announcement
        worldBuffsMapPins = true,   -- show minimalist World Buff pins & hover summary on World Map (M)
        embedSocialWindow = true,   -- integrate SocialCentral side-tab inside Social / Friends (O)
        embedLfgWindow = true,      -- integrate Clans & Allies LFG tab inside Group Finder (I)
        embedGuildWindow = true,    -- integrate Guild Hub & Diplomacy side-tab inside Communities / Guild (J)
        embedCharacterWindow = true, -- integrate My Alts side-tab inside Character window (C)
        embedWorldMap = true,       -- integrate World Buffs badge & pins inside World Map (M)
        hideGuildFeaturesWhenNoGuild = true, -- automatically hide guild tabs/options when current character has no guild
        moduleWatchlistEnabled = true, -- master toggle for Watchlist module
        moduleNearbyEnabled = true,    -- master toggle for Friendly Nearby passive module
        moduleChatEnabled = true,      -- master toggle for Conversations & Addon Chat module
        moduleGroupEnabled = true,     -- master toggle for Group & Recent Companions module
        doNotDisturb = false,          -- non-destructive master pause for all popups & alert chimes
        autoSilenceInInstances = false, -- automatically pause social popups/chimes inside dungeons, raids & BGs
        spotterScoutAlert = true,   -- notify on shared Scout sighting alerts from guildmates
        tooltipItemAlts = true,     -- show alt bag/bank/equipped item counts inside item tooltips
        tooltipPlayerNotes = true,  -- show Social Card notes, red flags & companion context inside player tooltips
        globalChatLfgScan = true,   -- passively index dungeon/raid LFG posts from public chat channels
        lfgAutoApplyDraft = true,   -- pre-fill your Level, Class & Role when whispering LFG posts
        lfgAntiSpam = true,         -- filter WTS/GDKP/boost spam from public LFG channels
        lfgHideAvoidEnemy = false,  -- hide LFG posts from Avoid-flagged or Enemy Guild leaders
        lfgBrowseCategory = "ALL",  -- last chosen Browse category ("ALL" | "DUNGEONS" | "RAIDS" | "QUESTS" | "PVP" | "CUSTOM")
        lfgBrowseSource = "ALL",    -- last chosen Browse source filter
        lfgBrowseRole = "MINE",     -- last chosen Browse role filter ("MINE" by default)
        lfgBrowseSuitableLevel = true, -- filter activities & groups to character level by default
        lfgBrowseSelectedActivities = {}, -- [catId] = { [actKey] = true } persisted checked activities
        groupAvoidAlert = true,     -- warn in chat and toast if an Avoided player enters your party or raid
        clanAutoCloseFullLfg = true, -- auto-close own Guild Dungeon LFM when party reaches 5 members
        worldBuffsExpiryAlert = true, -- warn out of combat when an active World Buff has < 5 minutes left
    },
    window = {
        point = nil,
        width = 790,
        height = 520,
    },
    windowPositions = {},            -- [windowKey] = { dx, dy } center-normalized positions across all frames
    watchlist = {},                -- [scopeKey] = { [id] = entry }
    alts = {},                     -- [charKey] = snapshot
    itemCatalog = {},              -- [itemID] = "name\ticon\tquality\tclassID\tsubClassID" shared across all alts
    clan = {},                     -- [guildScopeKey] = { myTag, myNote, myProf1, myProf2, myCraftNote, peers, events }
    socialMeta = {},               -- [scopeKey] = { [lookupKey] = { folder, mainName, note, flag, favorite } }
    friendPresence = {},           -- [scopeKey] = { [lookupKey] = { lastSeen, lastArea, lastClass, lastLevel, favorite } } (strictly zero BattleTag/Real ID)
    recentCompanions = {},         -- [scopeKey] = { [lookupKey] = { name, classFile, level, zone, role, lastSeen } }
    locationShareAllow = {},       -- [scopeKey] = { [lookupKey] = true } permanently approved live map-tracking peers (char keys only, zero BattleTag/Real ID)
    chatHistory = {},              -- [scopeKey] = { [threadKey] = { ... } }
    chatRooms = {},                -- [scopeKey] = { [roomId] = { id, name, owner, scope, members } }
    addonPeers = {},               -- [scopeKey] = { [lookupKey] = { displayName, version, lastSeenAt } } (strictly WoW char names, zero Real ID)
    worldBuffsDrops = {},          -- [realmPool] = { [buffId] = timestamp }
    worldBuffsHistory = {},        -- [realmPool] = { [buffId] = { [hour0..23] = count } }
    worldBuffsPersonal = {},       -- [charKey] = { saygeAt = ts, saygePlayed = playedSec }
    instanceRuns = {},             -- [i] = { sig, name, instType, enteredAt, charName, classFile }
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

local function ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

local function SyncRuntimeProfileVisuals()
    for _, ev in ipairs({ "SETTINGS_UPDATED", "CLAN_UPDATED", "CHAT_UPDATED", "WATCHLIST_UPDATED", "NEARBY_UPDATED", "WORLD_BUFFS_UPDATED", "SOCIAL_UPDATED" }) do
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
    elseif cmd == "buffs" or cmd == "buff" or cmd == "wbuffs" then
        if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("buffs") then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        if rest == "report" or rest == "share" or rest == "chat" then
            if ns.WorldBuffs and ns.WorldBuffs.OpenChatAnnouncement then
                ns.WorldBuffs:OpenChatAnnouncement()
            end
        else
            if ns.WorldBuffs and ns.WorldBuffs.PrintActiveBuffs then
                ns.WorldBuffs:PrintActiveBuffs()
            end
            if ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
                ns.LFGFrameTab:OpenOfficialModule("buffs")
            elseif ns.UI and ns.UI.OpenTab then
                ns.UI:OpenTab("buffs")
            end
        end
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
            if ns.ConversationsFrameTab and ns.ConversationsFrameTab.OpenOfficialModule then
                ns.ConversationsFrameTab:OpenOfficialModule("alliance")
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
    elseif cmd == "resetpos" or cmd == "reset" then
        if ns.Theme and ns.Theme.ResetAllWindowPositions then
            ns.Theme:ResetAllWindowPositions()
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
        if ModOn("group") then ns:Print("  |cffffd200/sc group|r — %s", L["Open Group"]) end
        if ModOn("buffs") then ns:Print("  |cffffd200/sc buffs|r — %s", L["World Buffs"]) end
        if ModOn("clan") then ns:Print("  |cffffd200/sc clan|r — %s", L["Open Clan"]) end
        ns:Print("  |cffffd200/sc hub|r — %s", L["Unified Hub (/sc hub)"])
        if ModOn("radar") then ns:Print("  |cffffd200/sc radar|r — %s", L["Target Radar"]) end
        ns:Print("  |cffffd200/sc toast [invite|friend|watchlist|buff|queue|clear]|r — %s", L["Test Notification Toast"])
        if ModOn("watchlist") then
            ns:Print("  |cffffd200/sc add <name>|r — %s", L["Add to Watchlist"])
            ns:Print("  |cffffd200/sc check [name]|r — %s", L["Check Watchlist character"])
        end
        ns:Print("  |cffffd200/sc resetpos|r — %s", L["Reset Window Positions"])
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

ns.RegisterEvent(boot, "ADDON_LOADED", function(_, _, loaded)
    if loaded ~= ADDON_NAME then return end
    SocialCentralDB = SocialCentralDB or {}
    SocialCentralCharDB = SocialCentralCharDB or {}
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
    ns._accountSettings = SocialCentralDB.settings
    if SocialCentralCharDB.useCharProfile == true then
        if type(SocialCentralCharDB.settings) ~= "table" then
            SocialCentralCharDB.settings = DeepCopyValue(ns._accountSettings or DEFAULTS.settings)
        else
            ApplyDefaults(SocialCentralCharDB.settings, ns._accountSettings or DEFAULTS.settings)
        end
        SocialCentralDB.settings = SocialCentralCharDB.settings
    end
    ns.db = SocialCentralDB
    ns.charDb = SocialCentralCharDB
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
            ApplyDefaults(SocialCentralCharDB.settings, ns._accountSettings or DEFAULTS.settings)
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
    ApplyDefaults(SocialCentralCharDB.settings, DEFAULTS.settings)
    if ns.db then
        ns.db.settings = SocialCentralCharDB.settings
    end
    SyncRuntimeProfileVisuals()
    return true
end

function ns:ResetCurrentSettingsToDefaults()
    local fresh = DeepCopyValue(DEFAULTS.settings)
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
    if ns._accountSettings and SocialCentralDB then
        SocialCentralDB.settings = ns._accountSettings
    end
end)

ns.RegisterEvent(boot, "PLAYER_LOGIN", function()
    if ns.Store and ns.Store.NormalizeLegacyRealmScopes then
        pcall(ns.Store.NormalizeLegacyRealmScopes, ns.Store)
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
    local checked = (type(framesTbl) ~= "table") and (chatID == 1) or (framesTbl[chatID] == true)
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
                ns:Emit("SETTINGS_CHANGED")
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
    if lastIdleGcAt > 0 and (now - lastIdleGcAt) < 18.0 then
        return
    end
    if idleGcQueued then
        return
    end
    idleGcQueued = true
    local stepBudget = math.max(80, math.min(600, tonumber(steps) or 250))
    C_Timer.After(tonumber(delay) or 0.6, function()
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
    if ns.Compat and ns.Compat.SyncRosterForeverNames then
        ns.Compat.SyncRosterForeverNames(false, true)
    end
    if C_Timer and C_Timer.After and type(collectgarbage) == "function" then
        C_Timer.After(4.5, function()
            if not (InCombatLockdown and InCombatLockdown()) then
                lastIdleGcAt = (GetTime and GetTime()) or 0
                pcall(collectgarbage, "step", 450)
            end
        end)
        C_Timer.After(11.0, function()
            if not (InCombatLockdown and InCombatLockdown()) then
                lastIdleGcAt = (GetTime and GetTime()) or 0
                pcall(collectgarbage, "step", 350)
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

--- Run a non-protected UI/UX callback right away outside combat, or defer once until combat ends.
function ns:RunAfterCombat(actionId, fn, noticeText)
    if type(fn) ~= "function" then return false end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if not inCombat then
        local ok, err = pcall(fn)
        if not ok and geterrorhandler then geterrorhandler()(err) end
        return ok
    end
    local key = tostring(actionId or ("task_" .. tostring(#pendingCombatTasks + 1)))
    pendingCombatTasks[key] = fn
    if noticeText ~= false then
        ns:Print("%s", (type(noticeText) == "string" and noticeText ~= "") and noticeText or L["Will finish right after combat ends."])
    end
    return false
end

--- Navigate to a SocialCentral module safely, deferring official Blizzard frame opens if currently in combat.
function ns:NavigateToModule(modName, opts)
    opts = opts or {}
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat then
        local alreadySame = (pendingNavigation and pendingNavigation.mod == modName)
        pendingNavigation = { mod = modName, opts = opts }
        if not alreadySame then
            ns:Print("%s", L["Will open right after combat ends."])
        end
        return false
    end

    pendingNavigation = nil
    if (opts.socialFilter or opts.socialSearch or opts.watchlistSearch ~= nil) and ns.UI and ns.UI.SetSocialNavigation then
        ns.UI:SetSocialNavigation(opts)
    end
    if (opts.clanRightView == "browse" or opts.clanRightView == "lfg") and modName == "lfg" and ns.LFGFrameTab then
        ns.LFGFrameTab.viewMode = "browse"
        if opts.lfgSelectKey and opts.lfgSelectKey ~= "" then
            ns.LFGFrameTab.pendingSelectKey = opts.lfgSelectKey
            ns.LFGFrameTab.sourceFilter = "ALL"
        end
    elseif opts.clanRightView and ns.Clan and ns.Clan.SetPreferredRightView then
        ns.Clan:SetPreferredRightView(opts.clanRightView)
    end
    if opts.pendingRoomId and not opts.threadKey and ns.Chat and ns.Chat.SetActiveThread and ns.Chat.GetRoom and ns.Chat:GetRoom(opts.pendingRoomId) then
        ns.Chat:SetActiveThread("room:" .. tostring(opts.pendingRoomId))
    end
    if opts.threadKey and ns.Chat and ns.Chat.SetActiveThread then
        ns.Chat:SetActiveThread(opts.threadKey)
    elseif (opts.targetName or opts.bnetAccountID) and ns.Chat and ns.Chat.OpenDirectConversation then
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

    if ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
        ns.LFGFrameTab:OpenOfficialModule(modName, true)
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
        for _, fn in pairs(queued) do
            if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
                break
            end
            local ok, err = pcall(fn)
            if not ok and geterrorhandler then geterrorhandler()(err) end
        end
    end
end)

if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("SetItemRef", function(_, link)
        if ns.Safe and ns.Safe.IsSecret and ns.Safe.IsSecret(link) then return end
        if type(link) ~= "string" then return end
        if link:find("addon:SCentral:update", 1, true) then
            if ns.UI and ns.UI.OpenUpdateModal then
                ns.UI:OpenUpdateModal()
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
        elseif link:find("addon:SCentral:buffs", 1, true) then
            if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("buffs") then
                ns:Print("%s", L["This module is disabled in Settings."])
                return
            end
            ns:NavigateToModule("buffs")
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
                end)
            end
        elseif link:find("addon:SCentral:delnote:", 1, true) then
            local noteId = link:match("addon:SCentral:delnote:([^|]+)")
            if noteId and noteId ~= "" and ns.Chat and ns.Chat.DeletePersonalNote then
                ns.Chat:DeletePersonalNote(noteId)
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
                local lookup = ns.Compat and ns.Compat.ParseCharacterFields and ns.Compat.ParseCharacterFields(who) or who:lower()
                local bInfo = ns.Social and ns.Social.GetBNetLinkInfo and lookup and ns.Social:GetBNetLinkInfo(lookup)
                local bnetAccId = bInfo and bInfo.bnetAccountID or nil
                local bnetName = bInfo and bInfo.bnetName or nil
                local scConfirmed = ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(who, bnetAccId)
                if scConfirmed and ns.Chat and ns.Chat.OpenDirectConversation then
                    ns:NavigateToModule("chat", {
                        targetName = who,
                        bnetAccountID = bnetAccId,
                        bnetName = bnetName,
                    })
                elseif ns.Compat and ns.Compat.Whisper then
                    ns.Compat.Whisper(who)
                end
            end
        end
    end)
end
