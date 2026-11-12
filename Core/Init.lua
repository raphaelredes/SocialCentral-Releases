local ADDON_NAME, ns = ...

local L = ns.L
ns.name = ADDON_NAME
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "0.2.1"
if ns.version:find("^@") then ns.version = "0.2.1" end
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
        theme = "dark",            -- "dark" | "native"
        whoMode = "silent_ui",     -- "silent_ui" | "chat_filter"
        whoCooldown = 6,           -- seconds between /who hardware-event requests
        nearbyRetentionMin = 15,   -- minutes to keep passive nearby sightings
        sortBy = "status",         -- "status" | "name" | "recent"
        alerts = {
            chat = true,
            sound = false,
        },
        minimap = {
            hide = false,
            angle = 215,
            lock = false,
        },
        versionCheck = true,       -- passive DBM-style peer version check (rate-limited)
        clanSync = false,          -- opt-in for clan guild addon messages (status/events/signups)
    },
    window = {
        point = nil,
        width = 760,
        height = 500,
    },
    watchlist = {},                -- [scopeKey] = { [id] = entry }
    alts = {},                     -- [charKey] = snapshot
    clan = {},                     -- [guildScopeKey] = { myTag, myNote, peers, events }
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
    elseif cmd == "config" or cmd == "settings" then
        if ns.Settings and ns.Settings.Open then
            ns.Settings:Open()
        end
    else
        if ns.UI and ns.UI.Toggle then
            ns.UI:Toggle()
        end
    end
end

ns.RegisterEvent(boot, "ADDON_LOADED", function(_, _, loaded)
    if loaded ~= ADDON_NAME then return end
    SocialCentralDB = SocialCentralDB or {}
    SocialCentralCharDB = SocialCentralCharDB or {}
    ApplyDefaults(SocialCentralDB, DEFAULTS)
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

-- Addon Compartment integration (WoW: Forever / modern minimap menu).
function SocialCentral_OnAddonCompartmentClick()
    if ns.UI and ns.UI.Toggle then ns.UI:Toggle() end
end

function SocialCentral_OnAddonCompartmentEnter(_, owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("|cff58a6ffSocial|rCentral")
    GameTooltip:AddLine(L["Click to open SocialCentral."], 0.85, 0.88, 0.92, true)
    GameTooltip:Show()
end

function SocialCentral_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("SetItemRef", function(_, link)
        if ns.Safe and ns.Safe.IsSecret and ns.Safe.IsSecret(link) then return end
        if type(link) == "string" and link:find("addon:SCentral:update", 1, true) then
            if ns.UI and ns.UI.OpenUpdateModal then
                ns.UI:OpenUpdateModal()
            end
        end
    end)
end
