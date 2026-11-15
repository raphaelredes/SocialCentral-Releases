local ADDON_NAME, ns = ...

local L = ns.L
ns.name = ADDON_NAME
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "0.2.8"
if ns.version == "" or ns.version:find("^@") then ns.version = "0.2.8" end
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
        alerts = {
            chat = true,
            sound = false,
        },
        minimap = {
            hide = false,
            angle = 215,
            lock = false,
        },
        versionCheck = true,        -- passive DBM-style peer version check (rate-limited)
        clanSync = false,           -- opt-in for clan guild addon messages (status/events/signups/lfg)
        guildChatFinder = false,    -- opt-in passive /g LFM line detector (read-only, zero auto-reply)
        clanLfgAlertEnabled = false, -- opt-in alert when a clan member looks for a dungeon/group
        clanLfgAlertDungeonsOnly = true, -- notify specifically for Dungeon / M+ group searches
        clanLfgAlertFilter = "",     -- optional comma-separated dungeon keywords
        clanLfgAlertSound = true,    -- sound chime when a Clan Dungeon LFG alert triggers
        autoStatusInstance = false, -- opt-in contextual activity tag out-of-combat
        chatSound = true,           -- master chime toggle for direct/room conversations
        chatSoundWhispers = true,   -- chime on Character & Battle.net whispers
        chatSoundRooms = true,      -- chime on Addon Private Chat Room messages & invites
        chatSoundGuild = false,     -- Guild / Officer chat sound muted by default
        chatSoundGroup = false,     -- Party / Raid / Instance chat sound muted by default
        chatMirrorChannels = true,  -- mirror native WoW Guild/Party/Raid channels inside Conversations
        chatChannelUnread = false,  -- opt-in: allow mirrored WoW channels to increment unread badges
        chatMutedThreads = {},      -- per-conversation mute map [threadKey] = true
        chatHistoryLimit = 30,      -- local lines kept per character conversation thread
        addonDirectChat = true,     -- enable verified 1-on-1 SocialCentral direct chat & peer handshake
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
        spotterNameplateBadges = false, -- default off to keep world nameplates uncluttered (user can opt in)
        spotterV2Migrated = false,  -- one-time migration from legacy deactivated spotter defaults
        worldBuffsAlerts = true,    -- notify when a Classic World Buff is announced by an NPC
        worldBuffsSound = true,     -- audio chime on incoming World Buff drop announcement
        worldBuffsMapPins = true,   -- show minimalist World Buff pins & hover summary on World Map (M)
        tooltipItemAlts = true,     -- show alt bag/bank/equipped item counts inside item tooltips
        tooltipPlayerNotes = true,  -- show Social Card notes, red flags & companion context inside player tooltips
        globalChatLfgScan = true,   -- passively index dungeon/raid LFG posts from public chat channels
    },
    window = {
        point = nil,
        width = 790,
        height = 520,
    },
    windowPositions = {},            -- [windowKey] = { dx, dy } center-normalized positions across all frames
    watchlist = {},                -- [scopeKey] = { [id] = entry }
    alts = {},                     -- [charKey] = snapshot
    clan = {},                     -- [guildScopeKey] = { myTag, myNote, myProf1, myProf2, myCraftNote, peers, events }
    socialMeta = {},               -- [scopeKey] = { [lookupKey] = { folder, mainName, note, flag } }
    recentCompanions = {},         -- [scopeKey] = { [lookupKey] = { name, classFile, level, zone, role, lastSeen } }
    chatHistory = {},              -- [scopeKey] = { [threadKey] = { ... } }
    chatRooms = {},                -- [scopeKey] = { [roomId] = { id, name, owner, scope, members } }
    addonPeers = {},               -- [scopeKey] = { [lookupKey] = { displayName, version, lastSeenAt } } (strictly WoW char names, zero Real ID)
    worldBuffsDrops = {},          -- [realmPool] = { [buffId] = timestamp }
    worldBuffsHistory = {},        -- [realmPool] = { [buffId] = { [hour0..23] = count } }
    worldBuffsPersonal = {},       -- [charKey] = { saygeAt = ts, saygePlayed = playedSec }
}

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

local boot = {}

local function HandleSlash(raw)
    local msg = (raw or ""):match("^%s*(.-)%s*$")
    local cmd, rest = msg:match("^(%S+)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()

    if cmd == "add" and rest ~= "" then
        if ns.Watchlist and ns.Watchlist.Add then
            ns.Watchlist:Add(rest)
        end
    elseif (cmd == "check" or cmd == "who") and rest ~= "" then
        if ns.Watchlist and ns.Watchlist.AddAndCheck then
            ns.Watchlist:AddAndCheck(rest)
        end
    elseif cmd == "check" or cmd == "who" then
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
        if ns.SpotterHUD and ns.SpotterHUD.Toggle then
            ns.SpotterHUD:Toggle()
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
        ns:Print("|cff58a6ffSocialCentral|r v%s", ns.version or "0.0.0")
        ns:Print("  |cffffd200/sc|r — %s", L["Settings"])
        ns:Print("  |cffffd200/sc lfg|r — %s", L["Looking for Group (I)"])
        ns:Print("  |cffffd200/sc chat|r — %s", L["Open Conversations"])
        ns:Print("  |cffffd200/sc group|r — %s", L["Open Group"])
        ns:Print("  |cffffd200/sc buffs|r — %s", L["World Buffs"])
        ns:Print("  |cffffd200/sc clan|r — %s", L["Open Clan"])
        ns:Print("  |cffffd200/sc hub|r — %s", L["Unified Hub (/sc hub)"])
        ns:Print("  |cffffd200/sc radar|r — %s", L["Target Radar"])
        ns:Print("  |cffffd200/sc add <name>|r — %s", L["Add to Watchlist"])
        ns:Print("  |cffffd200/sc check [name]|r — %s", L["Check Next"])
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
    ns.db = SocialCentralDB
    ns.charDb = SocialCentralCharDB
    ns.UnregisterEvent(boot, "ADDON_LOADED")
end)

ns.RegisterEvent(boot, "PLAYER_LOGIN", function()
    for _, mod in ipairs(ns.modules) do
        if type(mod.Init) == "function" then
            local ok, err = pcall(mod.Init, mod)
            if not ok and geterrorhandler then geterrorhandler()(err) end
        end
    end

    SLASH_SOCIALCENTRAL1 = "/sc"
    SLASH_SOCIALCENTRAL2 = "/socialcentral"
    SlashCmdList.SOCIALCENTRAL = HandleSlash

    if ns.Settings and ns.Settings.Register then
        pcall(ns.Settings.Register, ns.Settings)
    end
    if ns.Minimap and ns.Minimap.Update then
        pcall(ns.Minimap.Update, ns.Minimap)
    end

    ns.UnregisterEvent(boot, "PLAYER_LOGIN")
end)

ns.RegisterEvent(boot, "PLAYER_ENTERING_WORLD", function()
    ns.UnregisterEvent(boot, "PLAYER_ENTERING_WORLD")
    if ns.Compat and ns.Compat.SyncRosterForeverNames then
        ns.Compat.SyncRosterForeverNames()
    end
    if ns.db and ns.db.settings and not ns.db.settings.themeChosen then
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if not inCombat and ns.Theme and ns.Theme.ShowThemeWelcomePicker then
            ns.Theme:ShowThemeWelcomePicker()
        end
    end
end)

-- Addon Compartment integration (WoW: Forever / modern minimap menu).
function SocialCentral_OnAddonCompartmentClick()
    if ns.Settings and ns.Settings.Toggle then
        ns.Settings:Toggle()
    elseif ns.Settings and ns.Settings.Open then
        ns.Settings:Open()
    elseif ns.UI and ns.UI.Toggle then
        ns.UI:Toggle()
    end
end

function SocialCentral_OnAddonCompartmentEnter(_, owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("|cff58a6ffSocial|rCentral")
    GameTooltip:AddLine(L["Click to open SocialCentral settings."], 0.85, 0.88, 0.92, true)
    GameTooltip:Show()
end

function SocialCentral_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("SetItemRef", function(_, link)
        if ns.Safe and ns.Safe.IsSecret and ns.Safe.IsSecret(link) then return end
        if type(link) ~= "string" then return end
        if link:find("addon:SCentral:update", 1, true) then
            if ns.UI and ns.UI.OpenUpdateModal then
                ns.UI:OpenUpdateModal()
            end
        elseif link:find("addon:SCentral:clanlfg", 1, true) then
            if ns.Clan and ns.Clan.SetPreferredRightView then
                ns.Clan:SetPreferredRightView("lfg")
            end
            if ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
                ns.LFGFrameTab:OpenOfficialModule("lfg")
            elseif ns.UI and ns.UI.OpenTab then
                ns.UI:OpenTab("clan")
            end
        elseif link:find("addon:SCentral:diplomacy", 1, true) then
            if ns.Clan and ns.Clan.SetPreferredRightView then
                ns.Clan:SetPreferredRightView("diplomacy")
            end
            if ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
                ns.LFGFrameTab:OpenOfficialModule("diplomacy")
            elseif ns.UI and ns.UI.OpenTab then
                ns.UI:OpenTab("clan")
            end
        elseif link:find("addon:SCentral:spotter", 1, true) then
            if ns.SpotterHUD and ns.SpotterHUD.Show then
                ns.SpotterHUD:Show(true)
            end
        elseif link:find("addon:SCentral:target:", 1, true) then
            local targetKey = link:match("addon:SCentral:target:([^|]+)")
            if targetKey and targetKey ~= "" and ns.Spotter and ns.Spotter.FocusTarget then
                ns.Spotter:FocusTarget(targetKey)
            end
        else
            local who = link:match("addon:SCentral:w:([^|]+)")
            if who and who ~= "" then
                if ns.Chat and ns.Chat.OpenDirectConversation then
                    ns.Chat:OpenDirectConversation({ targetName = who })
                    if ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
                        ns.LFGFrameTab:OpenOfficialModule("chat")
                    elseif ns.UI and ns.UI.OpenTab then
                        ns.UI:OpenTab("chat")
                    end
                elseif ns.Compat and ns.Compat.Whisper then
                    ns.Compat.Whisper(who)
                end
            end
        end
    end)
end
