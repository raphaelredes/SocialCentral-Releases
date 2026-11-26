local _, ns = ...

local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })
local Safe = ns.Safe
local Compat = ns.Compat
local Store = ns.Store
local Theme = ns.Theme

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local ICON_TEX = "Interface\\AddOns\\SocialCentral\\Media\\icon"
local STAR_TEX = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t"

local LFGFrameTab = {
    sideTab = nil,
    subPanel = nil,
    active = false,
    hooked = false,
    viewMode = "browse",         -- "browse" | "categories" | "activities"
    activeCategory = "DUNGEONS", -- "DUNGEONS" | "RAIDS" | "QUESTS" | "PVP" | "CUSTOM"
    roles = { TANK = false, HEALER = false, DPS = false, GUIDE = false },
    rolesInitialized = false,
    listingMode = "LFG",         -- "LFG" | "LFM"
    playstyle = "NONE",          -- "NONE" | "NORMAL" | "FAST" | "FULL"
    showAllLevels = false,
    broadcastMode = "ALL",       -- "ALL" | "CLAN" | "GCHAT" | "OFFICIAL"
    _suppressNativeTakeoverUntil = 0,
    selectedActivities = {},     -- activityId -> true
    commentText = "",
    composerRole = "ANY",
    composerMode = "LFG",
    categoryFilter = "ALL",      -- "ALL" | "DUNGEONS" | "RAIDS" | "QUESTS" | "PVP" | "CUSTOM"
    sourceFilter = "ALL",        -- "ALL" | "TRUSTED" | "CLAN" | "ALLY" | "FRIENDS" | "SC_USERS" | "PUBLIC_CHAT"
    roleFilter = "ALL",          -- "ALL" | "MINE" | "TANK" | "HEALER" | "DPS"
    browseActivityFilter = {},   -- key -> { key, officialId, label, labelLower, shortLower }
    suitableLevelOnly = true,    -- pre-selected by default like official LFG
    _hasSearchedThisSession = false, -- stays false until player picks a filter or clicks search/refresh in current session
    _filtersLoadedFromDb = false,
    dungeonsOnly = false,
    composerOpen = false,
    pendingSelectKey = nil,
    selectedKey = nil,
    selectedItem = nil,
    query = "",
    collapsedBuckets = {},
    list = nil,
    activityList = nil,
    controls = {},
    socialTab = nil,
    socialHooked = false,
    guildTab = nil,
    guildHooked = false,
    charTab = nil,
    charHooked = false,
    chatBtn = nil,
    chatHooked = false,
    mapBtn = nil,
    mapSideTab = nil,
    mapHooked = false,
}

ns.LFGFrameTab = LFGFrameTab
table.insert(ns.modules, LFGFrameTab)

local CATEGORY_OPTIONS = {
    { id = "ALL", labelKey = "All Categories" },
    { id = "DUNGEONS", labelKey = "Dungeons" },
    { id = "RAIDS", labelKey = "Raids" },
    { id = "QUESTS", labelKey = "Quests & Zones" },
    { id = "PVP", labelKey = "Battlegrounds & PvP" },
    { id = "CUSTOM", labelKey = "Custom" },
}

local LISTING_CATEGORIES = {
    {
        id = "DUNGEONS",
        labelKey = "Dungeons",
        atlas = "groupfinder-button-dungeons",
        fallbackTex = "Interface\\LFGFrame\\UI-LFG-BACKGROUND-DUNGEONS",
        tint = { 0.48, 0.44, 0.38 },
    },
    {
        id = "RAIDS",
        labelKey = "Raids",
        atlas = "groupfinder-button-raids",
        fallbackTex = "Interface\\EncounterJournal\\UI-EJ-Boss-Ragnaros",
        tint = { 0.62, 0.28, 0.22 },
    },
    {
        id = "QUESTS",
        labelKey = "Quests & Zones",
        atlas = "groupfinder-button-questing",
        fallbackTex = "Interface\\LFGFrame\\UI-LFG-BACKGROUND-QUESTING",
        tint = { 0.36, 0.45, 0.58 },
    },
    {
        id = "PVP",
        labelKey = "Battlegrounds & PvP",
        atlas = "groupfinder-button-battlegrounds",
        fallbackTex = "Interface\\LFGFrame\\UI-LFG-BACKGROUND-PVP",
        tint = { 0.56, 0.42, 0.30 },
    },
    {
        id = "CUSTOM",
        labelKey = "Clan, Alliance & Custom",
        atlas = "groupfinder-button-custom",
        fallbackTex = "Interface\\LFGFrame\\UI-LFG-BACKGROUND-CUSTOM",
        tint = { 0.24, 0.46, 0.40 },
    },
}

local CURATED_ACTIVITIES = {
    DUNGEONS = {
        { id = "dng_rfc", labelKey = "Ragefire Chasm", minLvl = 13, maxLvl = 18 },
        { id = "dng_thanes", labelKey = "Hall of Thanes", minLvl = 13, maxLvl = 18 },
        { id = "dng_lordaeron", labelKey = "Ruins of Lordaeron", minLvl = 15, maxLvl = 22 },
        { id = "dng_wc", labelKey = "Wailing Caverns", minLvl = 15, maxLvl = 24 },
        { id = "dng_dm", labelKey = "The Deadmines", minLvl = 17, maxLvl = 26 },
        { id = "dng_sfk", labelKey = "Shadowfang Keep", minLvl = 22, maxLvl = 30 },
        { id = "dng_bfd", labelKey = "Blackfathom Deeps", minLvl = 24, maxLvl = 32 },
        { id = "dng_stocks", labelKey = "The Stockade", minLvl = 24, maxLvl = 32 },
        { id = "dng_gnomer", labelKey = "Gnomeregan", minLvl = 29, maxLvl = 38 },
        { id = "dng_rfk", labelKey = "Razorfen Kraul", minLvl = 29, maxLvl = 38 },
        { id = "dng_sm", labelKey = "Scarlet Monastery", minLvl = 34, maxLvl = 45 },
        { id = "dng_rfd", labelKey = "Razorfen Downs", minLvl = 37, maxLvl = 46 },
        { id = "dng_uld", labelKey = "Uldaman", minLvl = 41, maxLvl = 51 },
        { id = "dng_zf", labelKey = "Zul'Farrak", minLvl = 44, maxLvl = 54 },
        { id = "dng_mara", labelKey = "Maraudon", minLvl = 46, maxLvl = 55 },
        { id = "dng_st", labelKey = "Sunken Temple", minLvl = 50, maxLvl = 60 },
        { id = "dng_brd", labelKey = "Blackrock Depths", minLvl = 52, maxLvl = 60 },
        { id = "dng_lbrs", labelKey = "Lower Blackrock Spire", minLvl = 55, maxLvl = 60 },
        { id = "dng_dm_east", labelKey = "Dire Maul", minLvl = 56, maxLvl = 60 },
        { id = "dng_ubrs", labelKey = "Upper Blackrock Spire", minLvl = 58, maxLvl = 60 },
        { id = "dng_strat", labelKey = "Stratholme", minLvl = 58, maxLvl = 60 },
        { id = "dng_scholo", labelKey = "Scholomance", minLvl = 58, maxLvl = 60 },
    },
    RAIDS = {
        { id = "raid_zg", labelKey = "Zul'Gurub", minLvl = 60, maxLvl = 60 },
        { id = "raid_aq20", labelKey = "Ruins of Ahn'Qiraj (AQ20)", minLvl = 60, maxLvl = 60 },
        { id = "raid_mc", labelKey = "Molten Core", minLvl = 60, maxLvl = 60 },
        { id = "raid_ony", labelKey = "Onyxia's Lair", minLvl = 60, maxLvl = 60 },
        { id = "raid_bwl", labelKey = "Blackwing Lair", minLvl = 60, maxLvl = 60 },
        { id = "raid_aq40", labelKey = "Temple of Ahn'Qiraj (AQ40)", minLvl = 60, maxLvl = 60 },
        { id = "raid_naxx", labelKey = "Naxxramas", minLvl = 60, maxLvl = 60 },
        { id = "raid_wb", labelKey = "World Bosses (Azuregos / Kazzak / Dragons)", minLvl = 60, maxLvl = 60 },
    },
    QUESTS = {
        { id = "q_elite", labelKey = "Elite & Group Quests", minLvl = 1, maxLvl = 60 },
        { id = "q_zone", labelKey = "Zone Leveling & Grinding", minLvl = 1, maxLvl = 60 },
        { id = "q_dng", labelKey = "Dungeon Quests Run", minLvl = 13, maxLvl = 60 },
    },
    PVP = {
        { id = "pvp_wsg", labelKey = "Warsong Gulch", minLvl = 10, maxLvl = 60 },
        { id = "pvp_ab", labelKey = "Arathi Basin", minLvl = 20, maxLvl = 60 },
        { id = "pvp_av", labelKey = "Alterac Valley", minLvl = 51, maxLvl = 60 },
        { id = "pvp_world", labelKey = "World PvP & Clan Scout Squad", minLvl = 1, maxLvl = 60 },
    },
    CUSTOM = {
        { id = "sc_event", labelKey = "Clan Scheduled Event", minLvl = 1, maxLvl = 60 },
        { id = "sc_alliance", labelKey = "Cross-Guild Alliance Group", minLvl = 1, maxLvl = 60 },
        { id = "sc_friends", labelKey = "Friends & Watchlist Group", minLvl = 1, maxLvl = 60 },
        { id = "sc_buffs", labelKey = "World Buffs Coordination", minLvl = 1, maxLvl = 60 },
        { id = "sc_prof", labelKey = "Professions & Crafting Order", minLvl = 1, maxLvl = 60 },
    },
}

local LISTING_MODES = {
    { id = "LFG", labelKey = "Mode: LFG (Join)" },
    { id = "LFM", labelKey = "Mode: LFM (Recruit)" },
}

local PLAYSTYLE_OPTIONS = {
    { id = "NONE", labelKey = "Select Playstyle (...)" },
    { id = "NORMAL", labelKey = "Playstyle: Normal" },
    { id = "FAST", labelKey = "Playstyle: Fast / Speedrun" },
    { id = "FULL", labelKey = "Playstyle: Full Clear / Quests" },
}

local BROADCAST_OPTIONS = {
    { id = "ALL", labelKey = "Clan & Allies Only (Private)" },
    { id = "CLAN", labelKey = "My Clan Only (Private)" },
    { id = "GCHAT", labelKey = "Private + Guild Chat (/g)" },
    { id = "OFFICIAL", labelKey = "Official LFG + Clan & Allies (Official Tab)" },
}

local OFFICIAL_MIRROR_OPTIONS = {
    { id = "GUILD_ALLIES", labelKey = "Mirror: Guild & Allies" },
    { id = "GUILD_ONLY", labelKey = "Mirror: My Guild Only" },
    { id = "OFF", labelKey = "Official Only (No Mirror)" },
}

local SOURCE_FILTERS = {
    { id = "ALL", labelKey = "All", dropdownKey = "Filter: All" },
    { id = "OFFICIAL", labelKey = "Official Only", dropdownKey = "Filter: Official Blizzard Only" },
    { id = "TRUSTED", labelKey = "Trusted Network", dropdownKey = "Filter: Trusted Network" },
    { id = "FRIENDS", labelKey = "Friends / Watchlist", dropdownKey = "Filter: Friends & Watchlist" },
    { id = "CLAN", labelKey = "Same Clan", dropdownKey = "Filter: Same Clan" },
    { id = "ALLY", labelKey = "Allied Clans", dropdownKey = "Filter: Allied Clans" },
    { id = "SC_USERS", labelKey = "SocialCentral [SC]", dropdownKey = "Filter: SocialCentral [SC]" },
    { id = "PUBLIC_CHAT", labelKey = "Global Chat LFG", dropdownKey = "Filter: Global Chat LFG" },
}

local function GetCategoryLabel(catId, shortMode)
    if shortMode and catId == "ALL" then
        return L["All Cat."]
    end
    for _, opt in ipairs(CATEGORY_OPTIONS) do
        if opt.id == catId then
            return L[opt.labelKey]
        end
    end
    for _, opt in ipairs(LISTING_CATEGORIES) do
        if opt.id == catId then
            return L[opt.labelKey]
        end
    end
    return L["Category"]
end

local function GetListingModeLabel(modeId)
    for _, opt in ipairs(LISTING_MODES) do
        if opt.id == modeId then
            return L[opt.labelKey]
        end
    end
    return L["Mode: LFG (Join)"]
end

local function GetPlaystyleLabel(styleId)
    for _, opt in ipairs(PLAYSTYLE_OPTIONS) do
        if opt.id == styleId then
            return L[opt.labelKey]
        end
    end
    return L["Select Playstyle (...)"]
end

local function GetBroadcastLabel(modeId)
    for _, opt in ipairs(BROADCAST_OPTIONS) do
        if opt.id == modeId then
            return L[opt.labelKey]
        end
    end
    return L["Clan & Allies Only (Private)"]
end

local function GetOfficialMirrorLabel(modeId)
    for _, opt in ipairs(OFFICIAL_MIRROR_OPTIONS) do
        if opt.id == modeId then
            return L[opt.labelKey]
        end
    end
    return L["Mirror: Guild & Allies"]
end

local function RoleShortLabel(roleId)
    if roleId == "TANK" then return L["Tank"] end
    if roleId == "HEALER" then return L["Healer"] end
    if roleId == "DPS" then return L["DPS"] end
    if roleId == "MINE" then return L["My Roles"] end
    return L["Any"]
end

local function GetSourceFilterDropdownLabel(sourceId)
    local shortSource = L["All"]
    for _, opt in ipairs(SOURCE_FILTERS) do
        if opt.id == sourceId then
            shortSource = L[opt.labelKey]
            break
        end
    end
    local rf = LFGFrameTab.roleFilter
    local baseLabel
    if rf == "TANK" or rf == "HEALER" or rf == "DPS" or rf == "MINE" then
        baseLabel = shortSource .. " · " .. RoleShortLabel(rf)
    else
        baseLabel = shortSource .. " · " .. L["Any"]
    end
    local advCount = (ns.LFG and ns.LFG.CountActiveAdvancedFilters) and ns.LFG:CountActiveAdvancedFilters() or 0
    if advCount > 0 then
        return baseLabel .. " (" .. tostring(advCount) .. ")"
    end
    return baseLabel
end

local function GetItemIdentityKey(item)
    if not item then return nil end
    return tostring(item.sourceType or "LFG") .. ":" .. tostring(item.eventId or item.lookupKey or item.displayName or "?")
end

local function GetActivityLockout(item, cachedLocks)
    if not (item and type(cachedLocks) == "table" and #cachedLocks > 0) then
        return nil
    end
    local hay = ((item.activity or "") .. " " .. (item.activityAllNames or "") .. " " .. (item.note or "")):lower()
    if #hay < 3 then return nil end
    for _, lk in ipairs(cachedLocks) do
        if type(lk) == "table" and (lk.locked or lk.extended) then
            local inst = lk.name and tostring(lk.name):lower()
            if inst and #inst >= 4 then
                if hay:find(inst, 1, true) then
                    return lk
                end
                local shortInst = inst:gsub("^the ", ""):gsub("^o ", ""):gsub("^a ", "")
                if #shortInst >= 5 and hay:find(shortInst, 1, true) then
                    return lk
                end
            end
        end
    end
    return nil
end

local function MatchesCategoryFilter(item, catId)
    if not catId or catId == "ALL" then
        return true
    end
    if item and item.categoryKind and item.categoryKind ~= "" then
        return item.categoryKind == catId
    end
    if catId == "DUNGEONS" then
        return item and item.isDungeon == true
    end
    local hay = (
        (item and item.activity or "") .. " " ..
        (item and item.activityAllNames or "") .. " " ..
        (item and item.note or "") .. " " ..
        (item and item.sourceType or "")
    ):lower()
    if catId == "RAIDS" then
        local hasZulRaid = ((hay:find("%f[%w]zul%f[%W]") ~= nil) and not hay:find("farrak", 1, true))
            or (hay:find("zul'gurub", 1, true) ~= nil)
            or (hay:find("zulgurub", 1, true) ~= nil)
        return hay:find("raid") ~= nil or hay:find("raide") ~= nil or hay:find("banda") ~= nil
            or hay:find("molten") ~= nil or hay:find("nucleo") ~= nil or hay:find("núcleo") ~= nil
            or hay:find("onyx") ~= nil or hay:find("bwl") ~= nil or hay:find("covil") ~= nil
            or hay:find("guarida") ~= nil or hay:find("naxx") ~= nil or hay:find("%f[%w]zg%f[%W]") ~= nil
            or hasZulRaid or hay:find("aq20") ~= nil or hay:find("aq40") ~= nil
            or hay:find("ahn'qiraj") ~= nil or hay:find("boss") ~= nil or hay:find("chefe") ~= nil
            or hay:find("jefe") ~= nil
    elseif catId == "QUESTS" then
        local hasMissQuest = hay:find("%f[%w]miss%f[%W]") ~= nil
            or hay:find("missao", 1, true) ~= nil or hay:find("missão", 1, true) ~= nil
            or hay:find("missoes", 1, true) ~= nil or hay:find("missões", 1, true) ~= nil
            or hay:find("mision", 1, true) ~= nil or hay:find("misión", 1, true) ~= nil
        return hay:find("quest") ~= nil or hasMissQuest
            or hay:find("zona") ~= nil or hay:find("zone") ~= nil or hay:find("area") ~= nil
            or hay:find("área") ~= nil or hay:find("level") ~= nil or hay:find("farm") ~= nil
            or hay:find("grind") ~= nil or hay:find("elite") ~= nil
    elseif catId == "PVP" then
        return hay:find("pvp") ~= nil or hay:find("jcj") ~= nil or hay:find("arena") ~= nil
            or hay:find("%f[%w]bgs?%f[%W]") ~= nil or hay:find("%f[%w]wsg%f[%W]") ~= nil or hay:find("%f[%w]ab%f[%W]") ~= nil
            or hay:find("%f[%w]av%f[%W]") ~= nil or hay:find("batalha") ~= nil or hay:find("batalla") ~= nil
            or hay:find("battle") ~= nil or hay:find("warsong") ~= nil or hay:find("arathi") ~= nil
            or hay:find("alterac") ~= nil or hay:find("patrulha") ~= nil or hay:find("scout") ~= nil
    elseif catId == "CUSTOM" then
        return not (item and item.isDungeon == true)
    end
    return true
end

local function CheckActivityLevelSuitability(item)
    if not item then return true, false end
    local myLvl = (ns.Safe and ns.Safe.Number(UnitLevel and UnitLevel("player"))) or 60
    if myLvl <= 0 then myLvl = 60 end

    if item.minActLvl and item.minActLvl > 0 and item.maxActLvl and item.maxActLvl > 0 then
        local minL = item.minActLvl - 2
        local maxL = item.maxActLvl + 4
        return (myLvl >= minL and myLvl <= maxL), true
    end

    local hay = ((item.activity or "") .. " " .. (item.activityAllNames or "") .. " " .. (item.note or "")):lower()
    if hay ~= "" then
        for _, cat in ipairs({ "DUNGEONS", "RAIDS", "PVP" }) do
            local list = CURATED_ACTIVITIES[cat]
            if list then
                for i = 1, #list do
                    local act = list[i]
                    local matchedAct = false
                    for _, rawLbl in ipairs({ L[act.labelKey], act.labelKey }) do
                        if type(rawLbl) == "string" and #rawLbl >= 4 then
                            local lowLbl = rawLbl:lower()
                            local shortLbl = lowLbl:match("^([^(]+)")
                            shortLbl = shortLbl and shortLbl:match("^%s*(.-)%s*$") or lowLbl
                            if hay:find(lowLbl, 1, true) or (#shortLbl >= 4 and hay:find(shortLbl, 1, true)) then
                                matchedAct = true
                                break
                            end
                        end
                    end
                    if matchedAct then
                        local minL = (act.minLvl or 1) - 2
                        local maxL = (act.maxLvl or 60) + 4
                        return (myLvl >= minL and myLvl <= maxL), true
                    end
                end
            end
        end
    end

    if item.level and item.level > 0 then
        local near = (myLvl >= 58 and item.level >= 55) or math.abs(item.level - myLvl) <= 6
        return near, true
    end
    return true, false
end

local browseActivityOptionsCache = {}
local browseActivityOptionsCacheLvl = nil
local browseActivityOptionsBuiltAt = 0

local function GetBrowseActivityOptions(catId)
    if not catId or catId == "ALL" then
        return {}
    end
    local myLvl = (ns.Safe and ns.Safe.Number(UnitLevel and UnitLevel("player"))) or 60
    if myLvl <= 0 then myLvl = 60 end
    local nowClock = GetTime and GetTime() or 0
    if browseActivityOptionsCacheLvl ~= myLvl then
        wipe(browseActivityOptionsCache)
        browseActivityOptionsCacheLvl = myLvl
    end
    local cached = browseActivityOptionsCache[catId]
    if cached and #cached > 0 and (nowClock - (cached._builtAt or 0)) < 120 then
        return cached
    end

    local merged = {}
    local seenName = {}

    local function CleanBase(s)
        local low = (type(s) == "string") and s:lower() or ""
        local short = low:match("^([^(]+)")
        return (short or low):match("^%s*(.-)%s*$")
    end

    if ns.Clan and ns.Clan.GetOfficialActivitiesForKind then
        local offList = ns.Clan:GetOfficialActivitiesForKind(catId)
        for i = 1, #offList do
            local o = offList[i]
            local base = CleanBase(o.shortLabel or o.label)
            local baseFull = CleanBase(o.label)
            if o.officialId then
                if base ~= "" then seenName[base] = true end
                if baseFull ~= "" then seenName[baseFull] = true end
                local minL = o.minLvl
                local maxL = o.maxLvl
                if (not minL or minL <= 0) and ns.Clan.ResolveActivityLevelRange then
                    minL, maxL = ns.Clan:ResolveActivityLevelRange(nil, o.label, catId)
                end
                local hasRange = (minL ~= nil and minL > 0 and maxL ~= nil and maxL >= minL)
                local suitable = (not hasRange) or (myLvl >= minL and myLvl <= maxL)
                merged[#merged + 1] = {
                    key = "off_" .. tostring(o.officialId),
                    officialId = o.officialId,
                    label = o.label,
                    labelLower = (o.label or ""):lower(),
                    shortLower = (base ~= "" and base or baseFull),
                    minLvl = hasRange and minL or nil,
                    maxLvl = hasRange and maxL or nil,
                    isSuitable = suitable,
                    hasKnownRange = hasRange,
                }
            end
        end
    end

    local curated = CURATED_ACTIVITIES[catId] or {}
    for i = 1, #curated do
        local c = curated[i]
        local lbl = L[c.labelKey] or c.labelKey
        local base = CleanBase(lbl)
        local altBase = CleanBase(c.labelKey)
        if not seenName[base] and not seenName[altBase] then
            seenName[base] = true
            local minL = c.minLvl
            local maxL = c.maxLvl
            if (not minL or minL <= 0) and ns.Clan and ns.Clan.ResolveActivityLevelRange then
                minL, maxL = ns.Clan:ResolveActivityLevelRange(nil, lbl, catId)
            end
            local hasRange = (minL ~= nil and minL > 0 and maxL ~= nil and maxL >= minL and not (minL <= 1 and maxL >= 60))
            local suitable = (not hasRange) or (myLvl >= minL and myLvl <= maxL)
            merged[#merged + 1] = {
                key = c.id,
                officialId = nil,
                label = lbl,
                labelLower = lbl:lower(),
                shortLower = base,
                minLvl = hasRange and minL or nil,
                maxLvl = hasRange and maxL or nil,
                isSuitable = suitable,
                hasKnownRange = hasRange,
            }
        end
    end
    for i = 1, #merged do
        local m = merged[i]
        m.isFavorite = (ns.LFG and ns.LFG.IsFavoriteActivity and ns.LFG:IsFavoriteActivity(m.key, m.officialId)) == true
    end
    table.sort(merged, function(a, b)
        local af = (a.isFavorite == true)
        local bf = (b.isFavorite == true)
        if af ~= bf then
            return af
        end
        local am = a.minLvl or 999
        local bm = b.minLvl or 999
        if am ~= bm then
            return am < bm
        end
        return (a.label or "") < (b.label or "")
    end)
    local suitableCount = 0
    for i = 1, #merged do
        if merged[i].hasKnownRange and merged[i].isSuitable then
            suitableCount = suitableCount + 1
        end
    end
    merged._suitableCount = suitableCount
    merged._builtAt = nowClock
    browseActivityOptionsCache[catId] = merged
    return merged
end

function LFGFrameTab:InvalidateBrowseActivityCache()
    wipe(browseActivityOptionsCache)
end

function LFGFrameTab:GetBrowseActivityOptions(catId)
    return GetBrowseActivityOptions(catId)
end

local ACTIVITY_ALIAS_RULES = {
    { keys = { "ragefire", "caverna ignea", "cavernas igneas", "simas igneas" }, aliases = { "rfc", "ci", "ragefire" } },
    { keys = { "thanes" }, aliases = { "thanes", "thane" } },
    { keys = { "wailing", "ululante", "lamentos" }, aliases = { "wc", "cu", "wailing" } },
    { keys = { "deadmines", "minas mortas", "minas de la muerte" }, aliases = { "dm", "vc", "mm", "deadmines" } },
    { keys = { "shadowfang", "presa negra", "colmillo oscuro" }, aliases = { "sfk", "shadowfang" } },
    { keys = { "blackfathom", "profundezas negras", "brazanegra" }, aliases = { "bfd", "blackfathom" } },
    { keys = { "stockade", "carcere", "mazmorras de ventormenta" }, aliases = { "stocks", "stock", "carcere" } },
    { keys = { "gnomeregan" }, aliases = { "gnomer", "gnom" } },
    { keys = { "razorfen kraul", "urzal dos tuscos", "horado rajacieno" }, aliases = { "rfk", "kraul" } },
    { keys = { "monastery", "monasterio" }, aliases = { "sm", "arm", "cath", "lib", "gy", "monastery" } },
    { keys = { "razorfen downs", "urzal dos mortos", "zahurda" }, aliases = { "rfd", "downs" } },
    { keys = { "uldaman" }, aliases = { "ulda", "uld" } },
    { keys = { "zul'farrak", "zulfarrak" }, aliases = { "zf" } },
    { keys = { "maraudon" }, aliases = { "mara" } },
    { keys = { "sunken", "submerso", "sumergido" }, aliases = { "st", "atal" } },
    { keys = { "blackrock depths", "profundidades de rocha negra", "abismo" }, aliases = { "brd" } },
    { keys = { "lower blackrock", "pico da rocha negra inferior" }, aliases = { "lbrs" } },
    { keys = { "upper blackrock", "pico da rocha negra superior" }, aliases = { "ubrs" } },
    { keys = { "dire maul", "gladio cruel", "la masacre" }, aliases = { "dme", "dmw", "dmn", "dire" } },
    { keys = { "stratholme" }, aliases = { "strat" } },
    { keys = { "scholomance" }, aliases = { "scholo" } },
}

local foldLfgTextCache = {}
local foldLfgTextCount = 0

local function FoldLfgLookupText(s)
    if type(s) ~= "string" then return "" end
    local cached = foldLfgTextCache[s]
    if cached ~= nil then
        return cached
    end
    local lowerStr = (Compat and Compat.LowerUtf8) and Compat.LowerUtf8(s) or s:lower()
    local folded = lowerStr
        :gsub("á", "a"):gsub("à", "a"):gsub("ã", "a"):gsub("â", "a")
        :gsub("é", "e"):gsub("ê", "e"):gsub("í", "i")
        :gsub("ó", "o"):gsub("ô", "o"):gsub("õ", "o")
        :gsub("ú", "u"):gsub("ç", "c"):gsub("ñ", "n")
    if foldLfgTextCount >= 300 then
        wipe(foldLfgTextCache)
        foldLfgTextCount = 0
    end
    if #s <= 140 then
        foldLfgTextCache[s] = folded
        foldLfgTextCount = foldLfgTextCount + 1
    end
    return folded
end

local function MatchesBrowseActivityFilter(item)
    local sel = LFGFrameTab.browseActivityFilter
    if type(sel) ~= "table" or next(sel) == nil then
        return true
    end
    if type(item and item.activityIds) == "table" then
        for _, entry in pairs(sel) do
            if entry and entry.officialId then
                for i = 1, #item.activityIds do
                    if item.activityIds[i] == entry.officialId then
                        return true
                    end
                end
            end
        end
    end
    local hasActivityIds = (type(item and item.activityIds) == "table" and #item.activityIds > 0)
    local rawHay = hasActivityIds
        and ((item and item.activity or "") .. " " .. (item and item.activityAllNames or ""))
        or ((item and item.activity or "") .. " " .. (item and item.activityAllNames or "") .. " " .. (item and item.note or ""))
    local hay = FoldLfgLookupText(rawHay)
    if hay ~= "" then
        for _, entry in pairs(sel) do
            if entry then
                if entry.labelLower and #entry.labelLower >= 4 and hay:find(FoldLfgLookupText(entry.labelLower), 1, true) then
                    return true
                end
                if entry.shortLower and #entry.shortLower >= 4 and hay:find(FoldLfgLookupText(entry.shortLower), 1, true) then
                    return true
                end
                local foldedEntry = FoldLfgLookupText((entry.labelLower or "") .. " " .. (entry.shortLower or ""))
                for r = 1, #ACTIVITY_ALIAS_RULES do
                    local rule = ACTIVITY_ALIAS_RULES[r]
                    local hasKey = false
                    for k = 1, #rule.keys do
                        if foldedEntry:find(rule.keys[k], 1, true) then
                            hasKey = true
                            break
                        end
                    end
                    if hasKey then
                        for a = 1, #rule.aliases do
                            if hay:find("%f[%w]" .. rule.aliases[a] .. "%f[%W]") then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

local CATEGORY_SORT_ORDER = {
    DUNGEONS = 1,
    RAIDS = 2,
    QUESTS = 3,
    PVP = 4,
    CUSTOM = 5,
}

local CANONICAL_SEARCH_ORDER = { "DUNGEONS", "RAIDS", "PVP", "QUESTS", "CUSTOM" }

local function ResolveCanonicalActivityBucket(item)
    if not item then
        return "misc:other", L["Custom"], 999, 999, 6
    end
    if item._canonicalBucketKey and item._canonicalActivityLabel then
        return item._canonicalBucketKey, item._canonicalActivityLabel, item._canonicalMinLvl or 999, item._canonicalMaxLvl or 999, item._canonicalCatOrder or 6
    end

    local prefCat = item.categoryKind
    local catsToCheck
    if prefCat and CATEGORY_SORT_ORDER[prefCat] then
        catsToCheck = { prefCat }
        for i = 1, #CANONICAL_SEARCH_ORDER do
            if CANONICAL_SEARCH_ORDER[i] ~= prefCat then
                catsToCheck[#catsToCheck + 1] = CANONICAL_SEARCH_ORDER[i]
            end
        end
    else
        catsToCheck = CANONICAL_SEARCH_ORDER
    end

    local matchedKey, matchedLabel, minL, maxL, catOrd

    if type(item.activityIds) == "table" and #item.activityIds > 0 then
        local firstAid = item.activityIds[1]
        for ci = 1, #catsToCheck do
            local catId = catsToCheck[ci]
            local opts = GetBrowseActivityOptions(catId)
            for oi = 1, #opts do
                local opt = opts[oi]
                if opt.officialId == firstAid then
                    matchedKey = opt.key
                    matchedLabel = opt.label
                    minL = opt.minLvl
                    maxL = opt.maxLvl
                    catOrd = CATEGORY_SORT_ORDER[catId] or 6
                    break
                end
            end
            if matchedKey then break end
        end
    end

    if not matchedKey then
        local hay = FoldLfgLookupText((item.activity or "") .. " " .. (item.activityAllNames or "") .. " " .. (item.note or ""))
        if hay ~= "" then
            for ri = 1, #ACTIVITY_ALIAS_RULES do
                local rule = ACTIVITY_ALIAS_RULES[ri]
                local hitAlias = false
                for ai = 1, #rule.aliases do
                    if hay:find("%f[%w]" .. rule.aliases[ai] .. "%f[%W]") then
                        hitAlias = true
                        break
                    end
                end
                if hitAlias then
                    for ci = 1, #catsToCheck do
                        local catId = catsToCheck[ci]
                        local opts = GetBrowseActivityOptions(catId)
                        for oi = 1, #opts do
                            local opt = opts[oi]
                            local foldedOpt = FoldLfgLookupText((opt.labelLower or "") .. " " .. (opt.shortLower or ""))
                            for ki = 1, #rule.keys do
                                if foldedOpt:find(rule.keys[ki], 1, true) then
                                    matchedKey = opt.key
                                    matchedLabel = opt.label
                                    minL = opt.minLvl
                                    maxL = opt.maxLvl
                                    catOrd = CATEGORY_SORT_ORDER[catId] or 6
                                    break
                                end
                            end
                            if matchedKey then break end
                        end
                        if matchedKey then break end
                    end
                end
                if matchedKey then break end
            end
        end

        if not matchedKey and hay ~= "" then
            for ci = 1, #catsToCheck do
                local catId = catsToCheck[ci]
                local opts = GetBrowseActivityOptions(catId)
                for oi = 1, #opts do
                    local opt = opts[oi]
                    local lblF = FoldLfgLookupText(opt.labelLower or "")
                    local shortF = FoldLfgLookupText(opt.shortLower or "")
                    if (#lblF >= 4 and hay:find(lblF, 1, true)) or (#shortF >= 4 and hay:find(shortF, 1, true)) then
                        matchedKey = opt.key
                        matchedLabel = opt.label
                        minL = opt.minLvl
                        maxL = opt.maxLvl
                        catOrd = CATEGORY_SORT_ORDER[catId] or 6
                        break
                    end
                end
                if matchedKey then break end
            end
        end
    end

    if not matchedKey then
        local rawAct = (type(item.activity) == "string" and item.activity ~= "") and item.activity or GetCategoryLabel(prefCat or "CUSTOM")
        local cleanFallback = rawAct:gsub("^%[[^%]]+%]%s*", "")
        if cleanFallback == "" then cleanFallback = rawAct end
        if #cleanFallback > 42 then cleanFallback = cleanFallback:sub(1, 39) .. "..." end
        local foldedFb = FoldLfgLookupText(cleanFallback)
        if item.sourceType == "PUBLIC_CHAT" then
            matchedKey = "cat:" .. tostring(prefCat or "CHAT") .. ":other"
            matchedLabel = L["Public LFG & Zone Chat"]
        else
            matchedKey = "misc:" .. (foldedFb ~= "" and foldedFb or tostring(prefCat or "custom"))
            matchedLabel = cleanFallback
        end
        minL = item.minActLvl or item.level or 999
        maxL = item.maxActLvl or item.level or 999
        catOrd = CATEGORY_SORT_ORDER[prefCat] or 6
    end

    if minL and minL > 0 and minL < 900 and (not item.minActLvl or item.minActLvl <= 0) then
        item.minActLvl = minL
    end
    if maxL and maxL > 0 and maxL < 900 and (not item.maxActLvl or item.maxActLvl <= 0) then
        item.maxActLvl = maxL
    end
    item._canonicalBucketKey = matchedKey
    item._canonicalActivityLabel = matchedLabel
    item._canonicalMinLvl = minL or 999
    item._canonicalMaxLvl = maxL or 999
    item._canonicalCatOrder = catOrd or 6
    return matchedKey, matchedLabel, item._canonicalMinLvl, item._canonicalMaxLvl, item._canonicalCatOrder
end

function LFGFrameTab:ResolveItemCanonicalBucket(item)
    if not item then return nil, nil end
    return ResolveCanonicalActivityBucket(item)
end

function LFGFrameTab:GetWatchedActivitiesCount()
    local w = ns.db and ns.db.settings and ns.db.settings.lfgWatchedActivities
    if type(w) ~= "table" then return 0 end
    local cnt = 0
    for _, v in pairs(w) do
        if v then cnt = cnt + 1 end
    end
    return cnt
end

function LFGFrameTab:IsActivityWatched(bucketKey, fallbackLabel)
    local w = ns.db and ns.db.settings and ns.db.settings.lfgWatchedActivities
    if type(w) ~= "table" then return false end
    if bucketKey and w[bucketKey] then
        return true
    end
    if type(fallbackLabel) == "string" and fallbackLabel ~= "" then
        local folded = FoldLfgLookupText(fallbackLabel)
        for _, v in pairs(w) do
            if type(v) == "string" and FoldLfgLookupText(v) == folded then
                return true
            end
        end
    end
    return false
end

function LFGFrameTab:ToggleActivityWatched(bucketKey, label)
    local key = bucketKey or (type(label) == "string" and label ~= "" and ("lbl:" .. FoldLfgLookupText(label)) or nil)
    if not key or key == "" then return false end
    local s = ns.db and ns.db.settings
    if not s then return false end
    if type(s.lfgWatchedActivities) ~= "table" then
        s.lfgWatchedActivities = {}
    end
    local disp = (type(label) == "string" and label ~= "") and label or key
    if s.lfgWatchedActivities[key] then
        s.lfgWatchedActivities[key] = nil
        ns:Print("%s", string.format(L["LFG Watcher stopped for %s."], disp))
        self:RefreshData()
        ns:Emit("LFG_BROWSE_STATE_CHANGED")
        return false
    end
    s.lfgWatchedActivities[key] = disp
    s.lfgWatchersEnabled = true
    ns:Print("%s", string.format(L["LFG Watcher active in Official Chat for %s."], disp))
    self:RefreshData()
    ns:Emit("LFG_BROWSE_STATE_CHANGED")
    return true
end

function LFGFrameTab:ConfirmClearWatchedActivities()
    if self:GetWatchedActivitiesCount() == 0 then
        return
    end
    local function doClear()
        local s = ns.db and ns.db.settings
        if s and type(s.lfgWatchedActivities) == "table" then
            wipe(s.lfgWatchedActivities)
        end
        LFGFrameTab:RefreshData()
        ns:Emit("LFG_BROWSE_STATE_CHANGED")
        ns:Print("%s", L["Cleared all watched LFG dungeons and raids."])
    end
    if ns.UI and ns.UI.OpenConfirmModal then
        ns.UI:OpenConfirmModal({
            title = L["Clear All Watchers"],
            message = L["Remove all watched dungeons and raids from your Official Chat LFG alerts?"],
            confirmText = L["Clear"],
            confirmVariant = "danger",
            onConfirm = doClear,
        })
    else
        doClear()
    end
end

function LFGFrameTab:ApplyIdealActivitiesForCategory(catId, clearIfEmpty)
    wipe(self.browseActivityFilter)
    if not catId or catId == "ALL" then return 0 end
    local opts = GetBrowseActivityOptions(catId)
    local cnt = 0
    for i = 1, #opts do
        local opt = opts[i]
        if opt.hasKnownRange and opt.isSuitable then
            self.browseActivityFilter[opt.key] = opt
            cnt = cnt + 1
        end
    end
    if cnt == 0 and not clearIfEmpty then
        wipe(self.browseActivityFilter)
    end
    return cnt
end

function LFGFrameTab:SaveBrowseFilters()
    local s = ns.db and ns.db.settings
    if type(s) ~= "table" then return end
    s.lfgBrowseCategory = self.categoryFilter or "ALL"
    s.lfgBrowseSource = self.sourceFilter or "ALL"
    s.lfgBrowseRole = self.roleFilter or "ALL"
    s.lfgBrowseRoleV2 = self.roleFilter or "ALL"
    s.lfgBrowseSuitableLevel = (self.suitableLevelOnly ~= false)
    s.lfgBrowseSelectedActivities = type(s.lfgBrowseSelectedActivities) == "table" and s.lfgBrowseSelectedActivities or {}
    local cat = self.categoryFilter
    if cat and cat ~= "ALL" then
        local keys = {}
        local hasAny = false
        for k, v in pairs(self.browseActivityFilter or {}) do
            if v then
                keys[k] = true
                hasAny = true
            end
        end
        s.lfgBrowseSelectedActivities[cat] = hasAny and keys or false
    end
end

function LFGFrameTab:LoadSavedBrowseFilters(force)
    if self._filtersLoadedFromDb and not force then return end
    self._filtersLoadedFromDb = true
    local s = ns.db and ns.db.settings
    if type(s) ~= "table" then return end
    if type(s.lfgBrowseCategory) == "string" and s.lfgBrowseCategory ~= "" then
        self.categoryFilter = s.lfgBrowseCategory
    end
    if type(s.lfgBrowseSource) == "string" and s.lfgBrowseSource ~= "" then
        self.sourceFilter = s.lfgBrowseSource
    else
        self.sourceFilter = "ALL"
    end
    if type(s.lfgBrowseRoleV2) == "string" and s.lfgBrowseRoleV2 ~= "" then
        self.roleFilter = s.lfgBrowseRoleV2
    else
        self.roleFilter = "ALL"
    end
    self.suitableLevelOnly = (s.lfgBrowseSuitableLevel ~= false)
    wipe(self.browseActivityFilter)
    local cat = self.categoryFilter
    if cat and cat ~= "ALL" then
        local savedMap = type(s.lfgBrowseSelectedActivities) == "table" and s.lfgBrowseSelectedActivities[cat] or nil
        if type(savedMap) == "table" then
            local opts = GetBrowseActivityOptions(cat)
            for i = 1, #opts do
                if savedMap[opts[i].key] then
                    self.browseActivityFilter[opts[i].key] = opts[i]
                end
            end
        elseif savedMap == nil and self.suitableLevelOnly then
            self:ApplyIdealActivitiesForCategory(cat, true)
        end
    end
end

function LFGFrameTab:GetSelectedOfficialActivityIds()
    local ids = {}
    for _, entry in pairs(self.browseActivityFilter or {}) do
        if entry and entry.officialId then
            ids[#ids + 1] = entry.officialId
        end
    end
    return ids
end

function LFGFrameTab:HandleOwnListingRemoved()
    self._syncedActiveListingSig = nil
    if self._autoFilteredByActiveListing then
        self._autoFilteredByActiveListing = false
        if self.suitableLevelOnly then
            self:ApplyIdealActivitiesForCategory(self.categoryFilter, true)
        else
            wipe(self.browseActivityFilter)
        end
        self:SaveBrowseFilters()
    end
    self.selectedKey = nil
    self.selectedItem = nil
    if ns.Clan and ns.Clan.ScanOfficialLfgResults then
        ns.Clan:ScanOfficialLfgResults(true)
    end
    self:RefreshData()
end

function LFGFrameTab:SyncBrowseFilterToActiveListing(forceOverride, preferredIds, preferredCat)
    local ids = {}
    local seen = {}
    local activeCat = preferredCat

    if type(preferredIds) == "table" and #preferredIds > 0 then
        for i = 1, #preferredIds do
            local nid = Safe.Number(preferredIds[i])
            if nid and nid > 0 and not seen[nid] then
                seen[nid] = true
                ids[#ids + 1] = nid
            end
        end
    else
        if C_LFGList and C_LFGList.HasActiveEntryInfo and Safe.Value(Safe.Call(C_LFGList.HasActiveEntryInfo)) == true and C_LFGList.GetActiveEntryInfo then
            local aInfo = Safe.Call(C_LFGList.GetActiveEntryInfo)
            if type(aInfo) == "table" then
                if type(aInfo.activityIDs) == "table" then
                    for i = 1, #aInfo.activityIDs do
                        local nid = Safe.Number(aInfo.activityIDs[i])
                        if nid and nid > 0 and not seen[nid] then
                            seen[nid] = true
                            ids[#ids + 1] = nid
                        end
                    end
                else
                    local sid = Safe.Number(aInfo.activityID)
                    if sid and sid > 0 then
                        seen[sid] = true
                        ids[1] = sid
                    end
                end
            end
        end

        local selfItem = (#ids == 0 and self.GetSelfActiveListing) and self:GetSelfActiveListing() or nil
        if #ids == 0 and selfItem then
            if type(selfItem.activityIds) == "table" then
                for i = 1, #selfItem.activityIds do
                    local nid = Safe.Number(selfItem.activityIds[i])
                    if nid and nid > 0 and not seen[nid] then
                        seen[nid] = true
                        ids[#ids + 1] = nid
                    end
                end
            end
            activeCat = activeCat or selfItem.categoryKind
        end
    end

    if #ids == 0 then
        self._syncedActiveListingSig = nil
        self._autoFilteredByActiveListing = false
        return false, nil, nil
    end

    table.sort(ids)
    if not activeCat then
        for _, catDef in ipairs(LISTING_CATEGORIES) do
            local opts = GetBrowseActivityOptions(catDef.id)
            for i = 1, #opts do
                if opts[i].officialId == ids[1] then
                    activeCat = catDef.id
                    break
                end
            end
            if activeCat then break end
        end
    end
    if (not activeCat or activeCat == "ALL") and C_LFGList and C_LFGList.GetActivityInfoTable then
        local aTbl = Safe.Call(C_LFGList.GetActivityInfoTable, ids[1])
        local cId = type(aTbl) == "table" and Safe.Number(aTbl.categoryID) or nil
        if cId then
            if cId == 2 then activeCat = "DUNGEONS"
            elseif cId == 114 or cId == 3 then activeCat = "RAIDS"
            elseif cId == 116 or cId == 1 then activeCat = "QUESTS"
            elseif cId == 118 or cId == 7 or cId == 8 or cId == 9 then activeCat = "PVP"
            elseif cId == 120 or cId == 6 then activeCat = "CUSTOM"
            end
        end
    end
    activeCat = activeCat or "DUNGEONS"

    local idParts = {}
    for i = 1, #ids do
        idParts[i] = tostring(ids[i])
    end
    local sig = activeCat .. ":" .. table.concat(idParts, ",")
    if not forceOverride and self._syncedActiveListingSig == sig then
        return false, activeCat, ids
    end

    self._syncedActiveListingSig = sig
    self._autoFilteredByActiveListing = true
    self.categoryFilter = activeCat
    wipe(self.browseActivityFilter)
    local catOpts = GetBrowseActivityOptions(activeCat)
    for i = 1, #catOpts do
        local o = catOpts[i]
        if o.officialId and seen[o.officialId] then
            self.browseActivityFilter[o.key] = o
        end
    end
    if next(self.browseActivityFilter) == nil and C_LFGList and C_LFGList.GetActivityInfoTable then
        for i = 1, #ids do
            local aid = ids[i]
            local aTbl = Safe.Call(C_LFGList.GetActivityInfoTable, aid)
            local lbl = type(aTbl) == "table" and (Safe.String(aTbl.fullName) or Safe.String(aTbl.shortName)) or ("#" .. tostring(aid))
            local key = "off_" .. tostring(aid)
            local shortLbl = (type(aTbl) == "table" and Safe.String(aTbl.shortName)) or lbl
            self.browseActivityFilter[key] = {
                key = key,
                officialId = aid,
                label = lbl,
                labelLower = lbl:lower(),
                shortLower = shortLbl:lower(),
                isSuitable = true,
                hasKnownRange = false,
            }
        end
    end
    self._hasSearchedThisSession = true
    return true, activeCat, ids
end

function LFGFrameTab:TriggerOfficialBrowseSearch(forceIgnoreCooldown)
    if not (ns.Clan and ns.Clan.SearchOfficialLfg) then
        return false
    end
    local ids = self:GetSelectedOfficialActivityIds()
    return ns.Clan:SearchOfficialLfg(self.categoryFilter, ids, forceIgnoreCooldown)
end

function LFGFrameTab:GetBrowseActivityDropdownLabel()
    local sel = self.browseActivityFilter
    local names = {}
    for _, entry in pairs(sel or {}) do
        if entry and entry.label then
            names[#names + 1] = entry.label
        end
    end
    if #names == 0 then
        if not self.categoryFilter or self.categoryFilter == "ALL" then
            return L["All Activities"]
        end
        local catLbl = GetCategoryLabel(self.categoryFilter)
        return L["All in %s"]:format(catLbl)
    end
    if #names == 1 then
        return names[1]
    end
    local opts = GetBrowseActivityOptions(self.categoryFilter)
    local suitableCnt = opts and opts._suitableCount or 0
    if self.suitableLevelOnly and suitableCnt > 0 and #names == suitableCnt then
        return L["Ideal (%d)"]:format(#names)
    end
    return names[1] .. " (+" .. tostring(#names - 1) .. ")"
end

local function HasAtlas(name)
    return ns.Theme and ns.Theme.HasAtlas and ns.Theme:HasAtlas(name)
end

local function IterVarargChildren(fn, ...)
    local n = select("#", ...)
    for i = 1, n do
        local ch = select(i, ...)
        if ch then
            fn(ch)
        end
    end
end

local function ForEachChildNode(node, fn)
    if not node or not node.GetChildren or not fn then
        return
    end
    if Compat and Compat.ForEachChild then
        Compat.ForEachChild(node, fn)
    else
        IterVarargChildren(fn, node:GetChildren())
    end
end

local function MaxHierarchyLevel(root, depth)
    local maxLvl = 0
    if not root or (depth or 0) <= 0 then
        return maxLvl
    end
    if root.GetFrameLevel then
        local lvl = root:GetFrameLevel() or 0
        if lvl > maxLvl then
            maxLvl = lvl
        end
    end
    local nextDepth = (depth or 1) - 1
    if nextDepth > 0 and root.GetChildren then
        ForEachChildNode(root, function(child)
            local childMax = MaxHierarchyLevel(child, nextDepth)
            if childMax > maxLvl then
                maxLvl = childMax
            end
        end)
    end
    return maxLvl
end

local function IsCombatLocked()
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
end

local function GetNativeLfgSubFrames()
    local subs = {
        _G.LFGListingFrame,
        _G.LFGBrowseFrame,
        _G.LFGWhoListFrame,
    }
    local tab4 = _G.LFGParentFrameTab4
    if tab4 and tab4.subFrame then
        subs[#subs + 1] = tab4.subFrame
    end
    return subs
end

local function HideNativeLfgSubFrames()
    if _G.LFGParentFrame and ns.UI and ns.UI.HideEmbeddedHostSubframes then
        ns.UI:HideEmbeddedHostSubframes(_G.LFGParentFrame)
    end
    for _, sub in ipairs(GetNativeLfgSubFrames()) do
        if sub and sub.Hide then
            local canTouch = true
            if sub.IsForbidden then
                local okF, forb = pcall(sub.IsForbidden, sub)
                if not okF or forb then canTouch = false end
            end
            if canTouch and sub.IsProtected then
                local okP, prot = pcall(sub.IsProtected, sub)
                if not okP or prot then canTouch = false end
            end
            if canTouch then
                pcall(sub.Hide, sub)
            end
        end
    end
end

local function StyleNativeButton(btn, isActive)
    if not btn then return end
    if btn.LockHighlight and btn.UnlockHighlight then
        if isActive then
            btn:LockHighlight()
        else
            btn:UnlockHighlight()
        end
    end
    local fs = (btn.GetFontString and btn:GetFontString()) or btn.Text
    if fs and fs.SetTextColor then
        if isActive then
            fs:SetTextColor(1.0, 0.85, 0.25)
        else
            fs:SetTextColor(1.0, 0.82, 0.0)
        end
    end
    if btn._scActiveBg then
        btn._scActiveBg:SetShown(isActive == true)
    end
end

local function CreateNativeButton(parent, name, width, height, text)
    local ok, btn = pcall(CreateFrame, "Button", name, parent, "UIPanelButtonTemplate")
    if not ok or not btn then
        btn = Theme:CreateButton(parent, width, height, text, "default")
        return btn
    end
    btn:SetSize(width, height)
    btn:SetText(text or "")
    local bg = btn:CreateTexture(nil, "OVERLAY")
    bg:SetPoint("TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", -2, 2)
    bg:SetColorTexture(1.0, 0.82, 0.15, 0.16)
    bg:Hide()
    btn._scActiveBg = bg
    local fs = (btn.GetFontString and btn:GetFontString()) or btn.Text
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", btn, "LEFT", 6, 0)
        fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
        fs:SetWordWrap(false)
    end
    if btn.SetClipsChildren then
        btn:SetClipsChildren(true)
    end
    if btn.SetMotionScriptsWhileDisabled then
        pcall(btn.SetMotionScriptsWhileDisabled, btn, true)
    end
    return btn
end

local function AutoFitNativeButton(btn, minW, pad, maxW)
    if not btn then return 0 end
    local fs = (btn.GetFontString and btn:GetFontString()) or btn.Text
    local textW = 0
    if fs then
        textW = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
    end
    local w = math.max(minW or 40, math.ceil(textW + (pad or 18)))
    if maxW then
        w = math.min(maxW, w)
    end
    btn:SetWidth(w)
    return w
end

local function UpdateSideTabBadge(tab, count, tone)
    if not tab then return end
    local showBadges = not (ns.db and ns.db.settings and ns.db.settings.addonMsgTabBadges == false)
    local n = math.floor(tonumber(count) or 0)
    if not showBadges or n <= 0 then
        if tab.scUnreadBadge then
            if tab.scUnreadBadge.SetCount then
                tab.scUnreadBadge:SetCount(0)
            else
                tab.scUnreadBadge:Hide()
            end
        end
        return
    end
    if not tab.scUnreadBadge then
        if Theme and Theme.CreateCounterBadge then
            local b = Theme:CreateCounterBadge(tab, {
                height = 22,
                maxNum = 99,
                haloAlpha = 0.42,
                minFontSize = 14,
                maxFontSize = 17,
                fontScaleOffset = 0,
            })
            b:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 2)
            b:SetFrameLevel((tab:GetFrameLevel() or 60) + 6)
            tab.scUnreadBadge = b
        else
            local b = CreateFrame("Frame", nil, tab, "BackdropTemplate")
            b:SetSize(22, 22)
            b:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 2)
            b:SetFrameLevel((tab:GetFrameLevel() or 60) + 6)
            b:EnableMouse(false)
            if b.SetBackdrop then
                b:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = 1,
                })
                b:SetBackdropColor(0.84, 0.14, 0.18, 1.0)
                b:SetBackdropBorderColor(0.08, 0.08, 0.10, 1.0)
            end
            local txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            if Theme and Theme.ApplyReadableCounterFont then
                Theme:ApplyReadableCounterFont(txt, 14, 17, 0, true)
            end
            txt:SetPoint("CENTER", 0, 0)
            txt:SetTextColor(1, 1, 1)
            b.text = txt
            tab.scUnreadBadge = b
        end
    end
    tab.scUnreadBadge:SetFrameLevel((tab:GetFrameLevel() or 60) + 6)
    if type(tone) == "table" and #tone >= 2 and tab.scUnreadBadge.SetCountMulti then
        tab.scUnreadBadge:SetCountMulti(n, tone, false)
    elseif tab.scUnreadBadge.SetCount then
        local singleTone = (type(tone) == "table" and tone[1]) or tone or "whisper"
        tab.scUnreadBadge:SetCount(n, singleTone)
    else
        local lbl = n > 99 and "99+" or tostring(n)
        if Theme and Theme.ApplyReadableCounterFont then
            Theme:ApplyReadableCounterFont(tab.scUnreadBadge.text, 14, 17, 0, true)
        end
        tab.scUnreadBadge.text:SetText(lbl)
        local bw = (n > 99 and 36) or (n > 9 and 30) or 22
        tab.scUnreadBadge:SetSize(bw, 22)
        tab.scUnreadBadge:Show()
    end
end

local function UpdateSideTabVisual(tab, isSelected)
    if not tab then return end
    if tab.selectedTex then
        tab.selectedTex:SetShown(isSelected == true)
    end
    if tab.SetChecked then
        pcall(tab.SetChecked, tab, isSelected == true)
    end
end

local function CreateRightSideTab(parent, name, lastNative, tooltipTitle, tooltipDesc, onClickFn, winSettingKey)
    if not parent then return nil end

    local tab = CreateFrame("CheckButton", name, parent)
    local w, h = 55, 60
    if lastNative and lastNative.GetSize then
        local tw, th = lastNative:GetSize()
        if tw and tw >= 24 and tw <= 84 and th and th >= 24 and th <= 96 then
            w, h = tw, th
        end
    end
    tab:SetSize(w, h)
    tab:EnableMouse(true)
    if tab.SetEnabled then
        pcall(tab.SetEnabled, tab, true)
    end
    if tab.SetHitRectInsets then
        tab:SetHitRectInsets(0, 0, 0, 0)
    end
    local lastLvl = (lastNative and lastNative.GetFrameLevel and lastNative:GetFrameLevel()) or 20
    tab:SetFrameLevel(math.min(9500, math.max(600, lastLvl + 35)))

    local useCommon = (w >= 44) and HasAtlas("common-sidetab")
    tab._useCommonSideTab = useCommon

    if useCommon then
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAtlas("common-sidetab", true)
        bg:SetPoint("CENTER")
        tab.bgTex = bg

        if bg.GetSize then
            local bgW, bgH = bg:GetSize()
            if bgW and bgW > w and bgW <= 84 then w = bgW end
            if bgH and bgH > h and bgH <= 96 then h = bgH end
        end
        tab:SetSize(w, h)

        local icon = tab:CreateTexture(nil, "ARTWORK", nil, 1)
        icon:SetTexture(ICON_TEX)
        icon:SetSize(30, 30)
        icon:SetPoint("CENTER", -3, 0)
        icon:SetTexCoord(0.03125, 0.96875, 0.03125, 0.96875)
        if HasAtlas("common-sidetab-mask") then
            local mask = tab:CreateMaskTexture()
            mask:SetAtlas("common-sidetab-mask", true)
            mask:SetPoint("CENTER")
            icon:AddMaskTexture(mask)
            tab.maskTex = mask
        end
        tab.iconTex = icon

        local hl = tab:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAtlas("common-sidetab-hover", true)
        hl:SetBlendMode("ADD")
        hl:SetPoint("CENTER")

        local selectedTex = tab:CreateTexture(nil, "OVERLAY")
        if HasAtlas("common-sidetab-selected") then
            selectedTex:SetAtlas("common-sidetab-selected", true)
        else
            selectedTex:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        end
        selectedTex:SetBlendMode("ADD")
        selectedTex:SetPoint("CENTER")
        selectedTex:Hide()
        tab.selectedTex = selectedTex
    else
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
        bg:SetSize(64, 64)
        bg:SetPoint("TOPLEFT", -3, 11)
        tab.bgTex = bg

        local icon = tab:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(ICON_TEX)
        icon:SetPoint("TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", -2, 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tab.iconTex = icon

        local hl = tab:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hl:SetBlendMode("ADD")
        hl:SetAllPoints()

        local selectedTex = tab:CreateTexture(nil, "OVERLAY")
        selectedTex:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        selectedTex:SetBlendMode("ADD")
        selectedTex:SetAllPoints()
        selectedTex:Hide()
        tab.selectedTex = selectedTex
    end

    tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tab:SetScript("OnClick", function(selfBtn, mouseBtn)
        if mouseBtn == "RightButton" and MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                root:CreateTitle("SocialCentral")
                if winSettingKey == "embedLfgWindow" then
                    local canManageLfg = (not Compat.CanManageGroupListing) or Compat.CanManageGroupListing()
                    root:CreateButton(L["Browse Groups"], function()
                        if IsCombatLocked() then
                            ns:Print("%s", L["Unavailable during combat."])
                            return
                        end
                        LFGFrameTab.viewMode = "browse"
                        LFGFrameTab:ShowSubPanel()
                    end)
                    root:CreateButton(L["List Group"], function()
                        if IsCombatLocked() then
                            ns:Print("%s", L["Unavailable during combat."])
                            return
                        end
                        LFGFrameTab.viewMode = "categories"
                        LFGFrameTab:ShowSubPanel()
                    end)
                    local bcBtn = root:CreateButton(canManageLfg and L["Broadcast Current Group"] or L["Broadcast Current Group (Leader Only)"], function()
                        if IsCombatLocked() then
                            ns:Print("%s", L["Unavailable during combat."])
                            return
                        end
                        local okPost, reason = false, nil
                        if ns.Clan and ns.Clan.PostSmartGroupFormation then
                            okPost, reason = ns.Clan:PostSmartGroupFormation()
                        end
                        if okPost == false and reason == "not_leader" then
                            return
                        end
                        if not okPost and reason == "needs_activity" then
                            LFGFrameTab.viewMode = "categories"
                            LFGFrameTab:ShowSubPanel()
                            ns:Print("%s", L["Select the dungeon or activity you want to broadcast to Guild & Allies."])
                            return
                        end
                        LFGFrameTab.viewMode = "browse"
                        LFGFrameTab.sourceFilter = "ALL"
                        LFGFrameTab:ShowSubPanel()
                    end)
                    if bcBtn and bcBtn.SetEnabled and not canManageLfg then
                        pcall(bcBtn.SetEnabled, bcBtn, false)
                    end
                    root:CreateButton(L["Trusted Network"], function()
                        if IsCombatLocked() then
                            ns:Print("%s", L["Unavailable during combat."])
                            return
                        end
                        LFGFrameTab.viewMode = "browse"
                        LFGFrameTab.sourceFilter = "TRUSTED"
                        LFGFrameTab:ShowSubPanel()
                    end)
                    if LFGFrameTab.HasSelfActiveListing and LFGFrameTab:HasSelfActiveListing() then
                        root:CreateButton(L["Unlist"], function()
                            if ns.Clan and ns.Clan.ClearMyLFG then
                                ns.Clan:ClearMyLFG()
                            end
                            LFGFrameTab:RefreshData()
                        end)
                    end
                    root:CreateButton(L["Reset Instances"], function()
                        if ns.UI and ns.UI.ConfirmResetInstances then
                            ns.UI:ConfirmResetInstances()
                        elseif ns.Group and ns.Group.ResetDungeonInstances then
                            ns.Group:ResetDungeonInstances()
                        end
                    end)
                    root:CreateDivider()
                end
                if winSettingKey then
                    root:CreateButton(L["Disable in this window"], function()
                        if ns.db and ns.db.settings then
                            ns.db.settings[winSettingKey] = false
                        end
                        if winSettingKey == "embedLfgWindow" and LFGFrameTab.HideSubPanel then
                            LFGFrameTab:HideSubPanel(false)
                            local listingTab = (_G.LFGParentFrame and _G.LFGParentFrame.ListingTab) or _G.LFGParentFrameTab1
                            if listingTab and listingTab.Click then
                                pcall(listingTab.Click, listingTab)
                            end
                        elseif winSettingKey == "embedSocialWindow" and ns.UI and ns.UI.CloseEmbeddedIfHost then
                            ns.UI:CloseEmbeddedIfHost(_G.SocialUIFrame or _G.FriendsFrame)
                            if _G.FriendsFrameTab1 and _G.FriendsFrameTab1.Click then
                                pcall(_G.FriendsFrameTab1.Click, _G.FriendsFrameTab1)
                            end
                        elseif winSettingKey == "embedGuildWindow" and ns.UI and ns.UI.CloseEmbeddedIfHost then
                            ns.UI:CloseEmbeddedIfHost(_G.CommunitiesFrame or _G.GuildFrame)
                        elseif winSettingKey == "embedCharacterWindow" and ns.UI and ns.UI.CloseEmbeddedIfHost then
                            ns.UI:CloseEmbeddedIfHost(_G.CharacterFrame)
                            if _G.CharacterFrameTab1 and _G.CharacterFrameTab1.Click then
                                pcall(_G.CharacterFrameTab1.Click, _G.CharacterFrameTab1)
                            end
                        end
                        ns:Emit("SETTINGS_UPDATED")
                        ns:Emit("CLAN_UPDATED")
                        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                        if ns.UI and ns.UI.QueueRefresh then ns.UI:QueueRefresh(false) end
                        ns:Print("%s", L["Disabled in this window. Re-enable anytime in Settings (/sc)."])
                    end)
                end
                root:CreateButton(L["Settings"], function()
                    if ns.Settings and ns.Settings.Open then ns.Settings:Open() end
                end)
            end)
            return
        end
        if onClickFn then
            onClickFn(selfBtn, mouseBtn)
        end
    end)
    tab:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tooltipTitle, 0.35, 0.72, 1.0)
        if tooltipDesc and tooltipDesc ~= "" then
            GameTooltip:AddLine(tooltipDesc, 0.85, 0.88, 0.92, true)
        end
        GameTooltip:AddLine(L["Right-click: quick options"], 0.65, 0.72, 0.80, true)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return tab
end

local function IsSafeUiObj(obj)
    if not obj then return false end
    if obj.IsForbidden then
        local okF, forb = pcall(obj.IsForbidden, obj)
        if not okF or forb then return false end
    end
    if obj.IsProtected then
        local okP, prot = pcall(obj.IsProtected, obj)
        if not okP or prot then return false end
    end
    return true
end

local function DiscoverRightSideTabs(parentFrame, excludeTab, namedKeys)
    local found = {}
    if not parentFrame then return found end
    local seen = {}
    local pRight = parentFrame.GetRight and parentFrame:GetRight()

    local function IsExcludedChromeOrAddon(tab)
        if not tab or tab == excludeTab or tab == LFGFrameTab.subPanel then
            return true
        end
        local name = tab.GetName and tab:GetName() or ""
        if name ~= "" and (name:find("SocialCentral", 1, true) or name:find("Close", 1, true)) then
            return true
        end
        return false
    end

    local function IsOnRightEdge(tab)
        if not pRight then
            return true
        end
        local tLeft = tab.GetLeft and tab:GetLeft()
        local tW = (tab.GetWidth and tab:GetWidth()) or 0
        local tH = (tab.GetHeight and tab:GetHeight()) or 0
        return tLeft ~= nil
            and tLeft >= (pRight - 38)
            and tW >= 20 and tW <= 84
            and (tH == 0 or (tH >= 24 and tH <= 96))
    end

    local function AddFound(tab, requireRightEdge)
        if not tab or seen[tab] or not IsSafeUiObj(tab) or IsExcludedChromeOrAddon(tab) then
            return
        end
        if not (tab.IsShown and tab:IsShown()) then
            return
        end
        if requireRightEdge and not IsOnRightEdge(tab) then
            return
        end
        seen[tab] = true
        found[#found + 1] = tab
    end

    if namedKeys then
        for _, key in ipairs(namedKeys) do
            AddFound(parentFrame[key], true)
        end
    end

    for _, poolKey in ipairs({ "TabPool", "tabPool", "socialTabPool" }) do
        local pool = parentFrame[poolKey]
        if pool and pool.EnumerateActive then
            for tab in pool:EnumerateActive() do
                AddFound(tab, false)
            end
        end
    end

    for _, listKey in ipairs({ "SideTabs", "Tabs" }) do
        local tbl = parentFrame[listKey]
        if type(tbl) == "table" then
            for _, tab in ipairs(tbl) do
                AddFound(tab, listKey == "Tabs")
            end
        end
    end

    if parentFrame.ModeTabs and type(parentFrame.ModeTabs.Tabs) == "table" then
        for _, tab in ipairs(parentFrame.ModeTabs.Tabs) do
            AddFound(tab, false)
        end
    end

    local pName = parentFrame.GetName and parentFrame:GetName() or ""
    local globalPrefixes = { pName .. "Tab", pName .. "SideTab" }
    if parentFrame == _G.CharacterFrame then
        globalPrefixes[#globalPrefixes + 1] = "CharacterFrameTab"
        globalPrefixes[#globalPrefixes + 1] = "CharacterFrameSideTab"
    elseif parentFrame == _G.SocialUIFrame or parentFrame == _G.FriendsFrame then
        globalPrefixes[#globalPrefixes + 1] = "FriendsFrameTab"
        globalPrefixes[#globalPrefixes + 1] = "FriendsTabHeaderTab"
    elseif parentFrame == _G.LFGParentFrame then
        globalPrefixes[#globalPrefixes + 1] = "LFGParentFrameTab"
    end
    for _, prefix in ipairs(globalPrefixes) do
        if prefix ~= "Tab" and prefix ~= "SideTab" then
            for idx = 1, 8 do
                local gTab = _G[prefix .. idx]
                if gTab then
                    AddFound(gTab, true)
                end
            end
        end
    end

    local function ScanRightEdgeChildren(node, depth)
        if not node or depth <= 0 or not IsSafeUiObj(node) or not node.GetChildren then
            return
        end
        local function VisitRightChild(child)
            if IsSafeUiObj(child) and not IsExcludedChromeOrAddon(child) and (not child.IsShown or child:IsShown()) then
                local hasScript = child.HasScript and (child:HasScript("OnClick") or child:HasScript("OnMouseUp") or child:HasScript("OnMouseDown"))
                if hasScript and IsOnRightEdge(child) then
                    AddFound(child, false)
                end
                ScanRightEdgeChildren(child, depth - 1)
            end
        end
        if Compat and Compat.ForEachChild then
            Compat.ForEachChild(node, VisitRightChild)
        else
            local function LoopChildren(n, ...)
                for i = 1, n do
                    VisitRightChild(select(i, ...))
                end
            end
            LoopChildren(select("#", node:GetChildren()), node:GetChildren())
        end
    end
    ScanRightEdgeChildren(parentFrame, 3)

    -- Prune nested sub-controls whose parent/ancestor is already a discovered outer tab
    -- so lastNative is always a real outer side-tab button.
    local filtered = {}
    for _, cand in ipairs(found) do
        local isNestedChild = false
        local anc = cand.GetParent and cand:GetParent() or nil
        local hops = 0
        while anc and anc ~= parentFrame and hops < 4 do
            if seen[anc] then
                isNestedChild = true
                break
            end
            anc = anc.GetParent and anc:GetParent() or nil
            hops = hops + 1
        end
        if not isNestedChild then
            filtered[#filtered + 1] = cand
        end
    end

    table.sort(filtered, function(a, b)
        return ((a.GetTop and a:GetTop()) or 0) > ((b.GetTop and b:GetTop()) or 0)
    end)
    return filtered
end

local function MeasureTabGap(nativeTabs, fallbackGap, isCommonTab)
    local minAllowed = isCommonTab and -16 or -36
    if #nativeTabs >= 2 then
        for i = #nativeTabs - 1, 1, -1 do
            local b1 = nativeTabs[i].GetBottom and nativeTabs[i]:GetBottom()
            local t2 = nativeTabs[i + 1].GetTop and nativeTabs[i + 1]:GetTop()
            if b1 and t2 then
                local measured = t2 - b1
                if measured <= 2 and measured >= minAllowed then
                    return math.min(0, measured)
                end
            end
        end
    end
    return fallbackGap or -2
end

local SIDE_TAB_STRATA_RANK = {
    BACKGROUND = 1,
    LOW = 2,
    MEDIUM = 3,
    HIGH = 4,
}

local function ResolveSideTabStrata(parentFrame, nativeTabs)
    local best = "MEDIUM"
    local bestRank = 0
    local function Consider(obj)
        if not obj or not obj.GetFrameStrata then return end
        local ok, s = pcall(obj.GetFrameStrata, obj)
        if ok and type(s) == "string" then
            local r = SIDE_TAB_STRATA_RANK[s]
            if r and r > bestRank then
                bestRank = r
                best = s
            end
        end
    end
    Consider(parentFrame)
    if type(nativeTabs) == "table" then
        for _, nt in ipairs(nativeTabs) do
            Consider(nt)
        end
    end
    return best
end

local function IsAddonSideTabFrame(obj, excludeTab)
    if not obj then return false end
    if obj == excludeTab
        or obj == LFGFrameTab.sideTab
        or obj == LFGFrameTab.socialTab
        or obj == LFGFrameTab.guildTab
        or obj == LFGFrameTab.charTab
        or obj == LFGFrameTab.mapSideTab
    then
        return true
    end
    local name = obj.GetName and obj:GetName() or ""
    if name ~= "" and name:find("SocialCentral", 1, true) and name:find("SideTab", 1, true) then
        return true
    end
    return false
end

local function ComputeSideTabTargetLevel(parentFrame, tab, nativeTabs, minBaseLevel)
    local maxOtherLvl = (parentFrame and parentFrame.GetFrameLevel and parentFrame:GetFrameLevel()) or 1
    local function ConsiderLevel(lvl)
        if type(lvl) == "number" and lvl > maxOtherLvl then
            maxOtherLvl = lvl
        end
    end
    if parentFrame then
        for _, chromePart in pairs({
            parentFrame.NineSlice,
            parentFrame.BorderFrame,
            parentFrame.TitleContainer,
            parentFrame.PortraitContainer,
            parentFrame.PortraitOverlay,
        }) do
            if chromePart and IsSafeUiObj(chromePart) then
                ConsiderLevel(MaxHierarchyLevel(chromePart, 2))
            end
        end
        if type(nativeTabs) == "table" then
            for _, nt in ipairs(nativeTabs) do
                if nt and not IsAddonSideTabFrame(nt, tab) and IsSafeUiObj(nt) then
                    ConsiderLevel(MaxHierarchyLevel(nt, 3))
                end
            end
        end
        local pRight = parentFrame.GetRight and parentFrame:GetRight() or nil
        if parentFrame.GetChildren then
            ForEachChildNode(parentFrame, function(child)
                if child and not IsAddonSideTabFrame(child, tab) and IsSafeUiObj(child) and (not child.IsShown or child:IsShown()) then
                    local cLeft = child.GetLeft and child:GetLeft()
                    if pRight and cLeft and cLeft >= (pRight - 42) then
                        ConsiderLevel(MaxHierarchyLevel(child, 3))
                    elseif child.GetFrameLevel then
                        ConsiderLevel(child:GetFrameLevel() or 0)
                    end
                end
            end)
        end
    end
    return math.min(9500, math.max(minBaseLevel or 600, maxOtherLvl + 35))
end

local function SyncRightSideTabHitboxAndLayer(parentFrame, tab, nativeTabs, minBaseLevel)
    if not parentFrame or not tab then return end
    local lastNative = type(nativeTabs) == "table" and nativeTabs[#nativeTabs] or nil
    local w, h = tab:GetWidth() or 55, tab:GetHeight() or 60
    if lastNative and lastNative.GetSize then
        local tw, th = lastNative:GetSize()
        if tw and tw >= 24 and tw <= 84 and th and th >= 24 and th <= 96 then
            w, h = tw, th
        end
    end
    if tab._useCommonSideTab and tab.bgTex and tab.bgTex.GetSize then
        local bgW, bgH = tab.bgTex:GetSize()
        if bgW and bgW > w and bgW <= 84 then w = bgW end
        if bgH and bgH > h and bgH <= 96 then h = bgH end
    end
    if w >= 24 and h >= 24 then
        local rw = math.floor(w + 0.5)
        local rh = math.floor(h + 0.5)
        if math.abs((tab:GetWidth() or 0) - rw) >= 1 or math.abs((tab:GetHeight() or 0) - rh) >= 1 then
            tab:SetSize(rw, rh)
        end
    end
    if tab.IsMouseEnabled and not tab:IsMouseEnabled() then
        tab:EnableMouse(true)
    elseif not tab._scMouseHitInit then
        tab._scMouseHitInit = true
        tab:EnableMouse(true)
    end
    if tab.SetEnabled and tab.IsEnabled and not tab:IsEnabled() then
        pcall(tab.SetEnabled, tab, true)
    end
    if tab.SetHitRectInsets and not tab._scHitRectInit then
        tab._scHitRectInit = true
        tab:SetHitRectInsets(0, 0, 0, 0)
    end
    local desiredStrata = ResolveSideTabStrata(parentFrame, nativeTabs)
    if tab.SetFrameStrata and tab.GetFrameStrata and tab:GetFrameStrata() ~= desiredStrata then
        pcall(tab.SetFrameStrata, tab, desiredStrata)
    end
    if tab.SetFrameLevel then
        local desiredLvl = ComputeSideTabTargetLevel(parentFrame, tab, nativeTabs, minBaseLevel)
        if (tab:GetFrameLevel() or 0) ~= desiredLvl then
            pcall(tab.SetFrameLevel, tab, desiredLvl)
        end
    end
    if tab.scUnreadBadge then
        if tab.scUnreadBadge.EnableMouse and (not tab.scUnreadBadge.IsMouseEnabled or tab.scUnreadBadge:IsMouseEnabled()) then
            tab.scUnreadBadge:EnableMouse(false)
        end
        if tab.scUnreadBadge.SetFrameLevel then
            local badgeLvl = math.min(9600, (tab:GetFrameLevel() or 600) + 6)
            if (tab.scUnreadBadge:GetFrameLevel() or 0) ~= badgeLvl then
                tab.scUnreadBadge:SetFrameLevel(badgeLvl)
            end
        end
    end
end

local function DiscoverNativeSideTabs(parentFrame)
    return DiscoverRightSideTabs(parentFrame, LFGFrameTab.sideTab, { "ListingTab", "BrowsingTab", "WhoListingTab" })
end

local function IsAnyNativeSubFrameShown()
    for _, sub in ipairs(GetNativeLfgSubFrames()) do
        if sub and sub.IsShown and sub:IsShown() then
            return true
        end
    end
    return false
end

local NATIVE_TAB_SELECTED_FIELDS = {
    "CheckedTexture",
    "SelectedTexture",
    "ActiveTexture",
    "SelectionTexture",
    "SelectedOverlay",
    "ActiveOverlay",
    "Selected",
    "TabSelected",
    "BorderSelected",
    "SelectedGlow",
    "HighlightSelected",
    "Check",
}

-- Dim only selection/checked textures visually (never logical SetChecked(false)) so 2nd-press shortcut toggles close Blizzard windows cleanly.
local function DimNativeTabSelectionVisual(nt, shouldDim)
    if not nt or not IsSafeUiObj(nt) then return end
    if not shouldDim then
        if type(nt._scDimmedTexAlphas) == "table" then
            for tex, origAlpha in pairs(nt._scDimmedTexAlphas) do
                if tex and IsSafeUiObj(tex) and tex.SetAlpha then
                    pcall(tex.SetAlpha, tex, origAlpha or 1)
                end
                nt._scDimmedTexAlphas[tex] = nil
            end
        end
        nt._scWasDisabledByBlizz = nil
        ForEachChildNode(nt, function(sub)
            if IsSafeUiObj(sub) then
                sub._scWasDisabledByBlizz = nil
            end
        end)
        nt._scSelectionDimmed = nil
        return
    end

    if nt.IsEnabled and nt.SetEnabled then
        local okE, isEnabled = pcall(nt.IsEnabled, nt)
        if okE and not isEnabled then
            nt._scWasDisabledByBlizz = true
            pcall(nt.SetEnabled, nt, true)
        end
    end
    ForEachChildNode(nt, function(sub)
        if IsSafeUiObj(sub) and sub.IsEnabled and sub.SetEnabled then
            local okSE, subEn = pcall(sub.IsEnabled, sub)
            if okSE and not subEn then
                sub._scWasDisabledByBlizz = true
                pcall(sub.SetEnabled, sub, true)
            end
        end
    end)

    local neverDim = {
        [nt.Icon or false] = true,
        [nt.icon or false] = true,
        [nt.IconTexture or false] = true,
        [nt.Portrait or false] = true,
        [nt.NormalTexture or false] = true,
        [nt.PushedTexture or false] = true,
        [nt.HighlightTexture or false] = true,
        [nt.DisabledTexture or false] = true,
        [nt.Background or false] = true,
        [nt.Bg or false] = true,
        [nt.bgTex or false] = true,
    }
    for _, getterName in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if nt[getterName] then
            local okG, tex = pcall(nt[getterName], nt)
            if okG and tex then
                neverDim[tex] = true
            end
        end
    end

    nt._scDimmedTexAlphas = nt._scDimmedTexAlphas or {}
    local saved = nt._scDimmedTexAlphas

    local function DimTex(tex, allowNeverDimBypass)
        if not tex or not IsSafeUiObj(tex) or not tex.SetAlpha then return end
        if not allowNeverDimBypass and neverDim[tex] then return end
        if tex.GetObjectType and tex:GetObjectType() ~= "Texture" then return end
        if not allowNeverDimBypass and tex.IsShown then
            local okS, shown = pcall(tex.IsShown, tex)
            if okS and not shown then return end
        end
        if saved[tex] == nil then
            local curA = 1
            if tex.GetAlpha then
                local okA, a = pcall(tex.GetAlpha, tex)
                if okA and type(a) == "number" then
                    curA = a
                end
            end
            if curA <= 0.01 then
                return
            end
            saved[tex] = curA
        end
        pcall(tex.SetAlpha, tex, 0)
    end

    if nt.GetCheckedTexture then
        local okC, checkedTex = pcall(nt.GetCheckedTexture, nt)
        if okC and checkedTex then
            DimTex(checkedTex, true)
        end
    end
    for _, field in ipairs(NATIVE_TAB_SELECTED_FIELDS) do
        if nt[field] then
            DimTex(nt[field], false)
        end
    end
    if nt.GetRegions then
        for _, reg in ipairs({ nt:GetRegions() }) do
            if reg and not neverDim[reg] and reg.GetObjectType and reg:GetObjectType() == "Texture" then
                local matched = false
                if reg.GetAtlas then
                    local okAt, atlas = pcall(reg.GetAtlas, reg)
                    if okAt and type(atlas) == "string" and atlas ~= "" then
                        local low = atlas:lower()
                        if not low:find("hover", 1, true)
                            and not low:find("mask", 1, true)
                            and not low:find("inactive", 1, true)
                            and not low:find("deselect", 1, true)
                            and (low:find("selected", 1, true) or low:find("checked", 1, true) or low:find("active", 1, true))
                        then
                            matched = true
                        end
                    end
                end
                if not matched and reg.GetTexture then
                    local okTx, texPath = pcall(reg.GetTexture, reg)
                    if okTx and type(texPath) == "string" and texPath ~= "" then
                        local low = texPath:lower()
                        if not low:find("hover", 1, true)
                            and not low:find("mask", 1, true)
                            and not low:find("inactive", 1, true)
                            and (low:find("checkbuttonhilight", 1, true) or low:find("selected", 1, true) or low:find("active", 1, true))
                        then
                            matched = true
                        end
                    end
                end
                if matched then
                    DimTex(reg, false)
                end
            end
        end
    end
    nt._scSelectionDimmed = true
end

local function SyncHostNativeTabs(parentFrame, scTab, isEmbeddedActive, namedKeys)
    if not parentFrame then return end
    local nativeTabs = DiscoverRightSideTabs(parentFrame, scTab, namedKeys)
    if isEmbeddedActive then
        parentFrame._scDimmedNativeTabs = parentFrame._scDimmedNativeTabs or {}
        for _, nt in ipairs(nativeTabs) do
            if IsSafeUiObj(nt) then
                DimNativeTabSelectionVisual(nt, true)
                parentFrame._scDimmedNativeTabs[nt] = true
            end
        end
    else
        for _, nt in ipairs(nativeTabs) do
            if IsSafeUiObj(nt) then
                DimNativeTabSelectionVisual(nt, false)
            end
        end
        if type(parentFrame._scDimmedNativeTabs) == "table" then
            for nt in pairs(parentFrame._scDimmedNativeTabs) do
                DimNativeTabSelectionVisual(nt, false)
                parentFrame._scDimmedNativeTabs[nt] = nil
            end
        end
    end
end

local function EnsureClickedNativeTabRemainsChecked(parentFrame, clickedTab, excludeScTab, namedKeys)
    if not (clickedTab and IsSafeUiObj(clickedTab) and clickedTab.GetChecked and clickedTab.SetChecked) then
        return
    end
    local okC, isChecked = pcall(clickedTab.GetChecked, clickedTab)
    if not okC or isChecked then
        return
    end
    local anyOtherChecked = false
    for _, nt in ipairs(DiscoverRightSideTabs(parentFrame, excludeScTab, namedKeys)) do
        if nt ~= clickedTab and IsSafeUiObj(nt) and nt.GetChecked then
            local okO, otherChecked = pcall(nt.GetChecked, nt)
            if okO and otherChecked then
                anyOtherChecked = true
                break
            end
        end
    end
    if not anyOtherChecked then
        pcall(clickedTab.SetChecked, clickedTab, true)
    end
end

local function HookNativeHostTab(parentFrame, nt, excludeScTab, namedKeys, isLfgHost)
    if not parentFrame or not nt then
        return
    end
    local function HookOne(ctrl)
        if not ctrl or ctrl == excludeScTab or not IsSafeUiObj(ctrl) or ctrl._scNativeHostHooked then
            return
        end
        ctrl._scNativeHostHooked = true
        if ctrl.HasScript and ctrl:HasScript("OnMouseDown") then
            ctrl:HookScript("OnMouseDown", function(_, mouseBtn)
                if mouseBtn and mouseBtn ~= "LeftButton" then
                    return
                end
                parentFrame._scLastNativeTab = nt
                if parentFrame == _G.CharacterFrame and ns.UI and ns.UI.ReleaseAlphaHiddenCharacterSubframesForTabClick then
                    ns.UI:ReleaseAlphaHiddenCharacterSubframesForTabClick()
                end
                if isLfgHost and LFGFrameTab.active then
                    LFGFrameTab:HideSubPanel(false)
                end
                if ns.UI and ns.UI.CloseEmbeddedIfHost then
                    ns.UI:CloseEmbeddedIfHost(parentFrame)
                end
                SyncHostNativeTabs(parentFrame, excludeScTab, false, namedKeys)
            end)
        end
        if ctrl.HasScript and ctrl:HasScript("OnClick") then
            ctrl:HookScript("OnClick", function(clickedTab)
                parentFrame._scLastNativeTab = nt
                if isLfgHost and LFGFrameTab.active then
                    LFGFrameTab:HideSubPanel(false)
                    local seq = LFGFrameTab._transitionSeq
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            if LFGFrameTab._transitionSeq == seq and not LFGFrameTab.active and _G.LFGParentFrame and _G.LFGParentFrame:IsShown() and not IsAnyNativeSubFrameShown() then
                                LFGFrameTab:HideSubPanel(true)
                            end
                        end)
                    end
                end
                if ns.UI and ns.UI.CloseEmbeddedIfHost then
                    ns.UI:CloseEmbeddedIfHost(parentFrame)
                end
                if not (isLfgHost and LFGFrameTab.active) and not (ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(parentFrame)) then
                    EnsureClickedNativeTabRemainsChecked(parentFrame, clickedTab, excludeScTab, namedKeys)
                end
            end)
        end
        if ctrl.HasScript and ctrl:HasScript("OnMouseUp") then
            ctrl:HookScript("OnMouseUp", function(clickedTab, mouseBtn)
                if mouseBtn and mouseBtn ~= "LeftButton" then
                    return
                end
                if isLfgHost and LFGFrameTab.active and IsAnyNativeSubFrameShown() then
                    LFGFrameTab:HideSubPanel(false)
                end
                if ns.UI and ns.UI.CloseEmbeddedIfHost then
                    ns.UI:CloseEmbeddedIfHost(parentFrame)
                end
                if not (isLfgHost and LFGFrameTab.active) and not (ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(parentFrame)) then
                    EnsureClickedNativeTabRemainsChecked(parentFrame, clickedTab, excludeScTab, namedKeys)
                end
            end)
        end
    end

    HookOne(nt)
    ForEachChildNode(nt, function(sub)
        if sub ~= excludeScTab and sub.HasScript and (sub:HasScript("OnClick") or sub:HasScript("OnMouseDown") or sub:HasScript("OnMouseUp")) then
            HookOne(sub)
        end
    end)
end

local function SetNativeTabsCheckedFalse()
    local parentFrame = _G.LFGParentFrame
    if not parentFrame then return end
    SyncHostNativeTabs(parentFrame, LFGFrameTab.sideTab, true, { "ListingTab", "BrowsingTab", "WhoListingTab" })
end

local function ElevateTree(root, targetLevel, depth)
    if not root or (depth or 0) <= 0 or not IsSafeUiObj(root) then return end
    local capped = math.min(9600, targetLevel or 1)
    if root.SetFrameLevel and root.GetFrameLevel then
        local cur = root:GetFrameLevel() or 1
        if cur < capped then
            pcall(root.SetFrameLevel, root, capped)
        end
    end
    local nextDepth = (depth or 1) - 1
    if nextDepth > 0 and root.GetChildren then
        ForEachChildNode(root, function(child)
            ElevateTree(child, capped + 1, nextDepth)
        end)
    end
end

local function CollectLfgCloseButtonCandidates(parent)
    local found = {}
    local seen = {}
    local function Add(btn)
        if btn and not seen[btn] then
            seen[btn] = true
            found[#found + 1] = btn
        end
    end
    Add(parent.CloseButton)
    if parent.TitleContainer then
        Add(parent.TitleContainer.CloseButton)
    end
    Add(_G.LFGParentFrameCloseButton)
    Add(_G.LFGParentFrameTitleContainerCloseButton)

    local hRight = parent.GetRight and parent:GetRight() or nil
    local hTop = parent.GetTop and parent:GetTop() or nil
    local function ScanForClose(node, depth)
        if not node or (depth or 0) <= 0 or not node.GetChildren then return end
        ForEachChildNode(node, function(ch)
            if ch ~= LFGFrameTab.subPanel and ch ~= _G.SocialCentralLFGSubPanel then
                local isForb = false
                if ch.IsForbidden then
                    local okF, fVal = pcall(ch.IsForbidden, ch)
                    isForb = (not okF) or (fVal == true)
                end
                if not isForb then
                    local cName = ch.GetName and ch:GetName() or ""
                    local oType = ch.GetObjectType and ch:GetObjectType() or ""
                    if oType == "Button" then
                        if cName:find("Close") then
                            Add(ch)
                        elseif hRight and hTop and ch.GetRight and ch.GetTop and ch.GetWidth and ch.GetHeight then
                            local cr, ct = ch:GetRight(), ch:GetTop()
                            local cw, chH = ch:GetWidth() or 0, ch:GetHeight() or 0
                            if cr and ct and cr >= (hRight - 42) and ct >= (hTop - 42) and cw > 10 and cw <= 44 and chH > 10 and chH <= 44 then
                                Add(ch)
                            end
                        end
                    end
                    ScanForClose(ch, depth - 1)
                end
            end
        end)
    end
    ScanForClose(parent, 3)
    return found
end

local function DisableFrameMouseTree(root, depth)
    if not root or (depth or 0) <= 0 then return end
    if root.EnableMouse then
        pcall(root.EnableMouse, root, false)
    end
    if root.EnableMouseWheel then
        pcall(root.EnableMouseWheel, root, false)
    end
    if (depth or 0) > 1 and root.GetChildren then
        ForEachChildNode(root, function(ch)
            DisableFrameMouseTree(ch, depth - 1)
        end)
    end
end

local function SyncSubPanelTemplateChrome(panel, useLfgHost)
    if not panel then return end
    local pName = panel.GetName and panel:GetName() or nil
    for _, dup in pairs({
        panel.PortraitContainer,
        panel.PortraitOverlay,
        panel.TitleContainer,
        panel.CloseButton,
        pName and _G[pName .. "PortraitContainer"] or nil,
        pName and _G[pName .. "PortraitFrame"] or nil,
        pName and _G[pName .. "Portrait"] or nil,
        pName and _G[pName .. "TitleContainer"] or nil,
        pName and _G[pName .. "TitleText"] or nil,
    }) do
        if dup and dup.Hide then
            pcall(dup.Hide, dup)
        end
    end

    for _, chromePart in pairs({
        panel.NineSlice,
        panel.Bg,
        panel.TopTileStreaks,
        panel.TitleBg,
    }) do
        if chromePart then
            if useLfgHost then
                if chromePart.Show then
                    pcall(chromePart.Show, chromePart)
                end
                if chromePart == panel.NineSlice then
                    DisableFrameMouseTree(chromePart, 3)
                end
            elseif chromePart.Hide then
                pcall(chromePart.Hide, chromePart)
            end
        end
    end
end

local function ElevateLfgParentControls()
    local parent = _G.LFGParentFrame
    local panel = LFGFrameTab.subPanel
    if not parent or not panel then return end
    if not (LFGFrameTab.active and panel:GetParent() == parent) then return end
    local minControlLevel = math.min(9200, math.max(
        MaxHierarchyLevel(panel, 4) + 20,
        (panel:GetFrameLevel() or 6) + 30
    ))
    local chromeFrames = {
        parent.NineSlice,
        parent.BorderFrame,
        parent.TitleContainer,
        parent.PortraitContainer,
        parent.PortraitOverlay,
        _G.LFGParentFramePortraitFrame,
    }
    for _, f in pairs(chromeFrames) do
        if f then
            local targetL = (f == parent.NineSlice or f == parent.BorderFrame) and (minControlLevel + 2) or (minControlLevel + 8)
            ElevateTree(f, targetL, 4)
        end
    end
    for _, closeBtn in ipairs(CollectLfgCloseButtonCandidates(parent)) do
        ElevateTree(closeBtn, minControlLevel + 28, 2)
        if closeBtn.IsProtected then
            local okP, prot = pcall(closeBtn.IsProtected, closeBtn)
            if okP and not prot and closeBtn.Show then
                pcall(closeBtn.Show, closeBtn)
            end
        end
    end
    for _, tab in ipairs(DiscoverNativeSideTabs(parent)) do
        ElevateTree(tab, minControlLevel + 10, 2)
    end
    if LFGFrameTab.sideTab then
        ElevateTree(LFGFrameTab.sideTab, minControlLevel + 35, 2)
        if LFGFrameTab.sideTab.SetHitRectInsets then
            LFGFrameTab.sideTab:SetHitRectInsets(0, 0, 0, 0)
        end
    end
end

function LFGFrameTab:UpdateTabSelectionVisual()
    UpdateSideTabVisual(self.sideTab, self.active == true)
end

local lfgArtCache = nil

local function ApplyTexSpec(tex, spec, fallbackAtlas, fallbackTex, l, r, t, b)
    if not tex then return end
    if spec and spec.atlas and HasAtlas(spec.atlas) then
        tex:SetAtlas(spec.atlas, false)
        tex:SetTexCoord(0, 1, 0, 1)
        return true
    elseif spec and spec.texture then
        tex:SetTexture(spec.texture)
        if spec.texCoord then
            tex:SetTexCoord(unpack(spec.texCoord))
        else
            tex:SetTexCoord(0, 1, 0, 1)
        end
        return true
    elseif fallbackAtlas and HasAtlas(fallbackAtlas) then
        tex:SetAtlas(fallbackAtlas, false)
        tex:SetTexCoord(0, 1, 0, 1)
        return true
    elseif fallbackTex then
        tex:SetTexture(fallbackTex)
        tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
        return true
    end
    return false
end

local lfgLastArtHarvestAt = 0

local function HarvestLfgListingArt(forceRefresh)
    if lfgArtCache and next(lfgArtCache.banners) ~= nil then
        if not forceRefresh or next(lfgArtCache.roles) ~= nil then
            return lfgArtCache
        end
    end
    local nowClock = GetTime and GetTime() or 0
    if lfgArtCache and next(lfgArtCache.roles) ~= nil and lfgLastArtHarvestAt > 0 and (nowClock - lfgLastArtHarvestAt) < 15.0 then
        return lfgArtCache
    end
    lfgLastArtHarvestAt = nowClock
    local cache = lfgArtCache or { roles = {}, banners = {} }
    if forceRefresh and next(cache.banners) == nil then
        cache.banners = {}
    end
    lfgArtCache = cache

    local listing = _G.LFGListingFrame
    if not listing or not listing.GetChildren then
        return cache
    end

    local function captureTexture(region)
        if not region or not region.GetObjectType or region:GetObjectType() ~= "Texture" then
            return nil
        end
        local okAtlas, atlas = pcall(region.GetAtlas, region)
        if okAtlas and type(atlas) == "string" and atlas ~= "" and HasAtlas(atlas) then
            return { atlas = atlas }
        end
        local okTex, texPath = pcall(region.GetTexture, region)
        if okTex and texPath and texPath ~= "" then
            local okCoords, coords = pcall(function() return { region:GetTexCoord() } end)
            return {
                texture = texPath,
                texCoord = (okCoords and coords and #coords >= 4) and coords or nil,
            }
        end
        return nil
    end

    local function classifyBannerText(textStr)
        if textStr:find("masmor") or textStr:find("dungeon") or textStr:find("mazmor") then
            return "DUNGEONS"
        elseif textStr:find("raid") or textStr:find("raide") or textStr:find("banda") then
            return "RAIDS"
        elseif textStr:find("miss") or textStr:find("quest") or textStr:find("misi") then
            return "QUESTS"
        elseif textStr:find("campo") or textStr:find("battle") or textStr:find("pvp") then
            return "PVP"
        elseif textStr:find("person") or textStr:find("custom") then
            return "CUSTOM"
        end
        return nil
    end

    local function scanContainer(root, depth)
        if not root or (depth or 0) <= 0 or not root.GetChildren then return end
        for _, child in ipairs({ root:GetChildren() }) do
            local objType = child.GetObjectType and child:GetObjectType()
            local w = (child.GetWidth and child:GetWidth()) or 0
            local h = (child.GetHeight and child:GetHeight()) or 0

            -- Discover explicit Role circle textures cleanly (Forever uses Button or CheckButton)
            if (objType == "Button" or objType == "CheckButton") and w >= 32 and w <= 96 and h >= 32 and h <= 96 then
                local childName = (child.GetName and child:GetName()) or ""
                local lowName = childName:lower()
                local roleKey = nil
                if lowName:find("tank") or child == (root.TankButton) or child == (listing.TankButton) then
                    roleKey = "TANK"
                elseif lowName:find("heal") or child == (root.HealerButton) or child == (listing.HealerButton) then
                    roleKey = "HEALER"
                elseif lowName:find("dps") or lowName:find("damage") or child == (root.DPSButton) or child == (listing.DPSButton) then
                    roleKey = "DPS"
                elseif lowName:find("guide") or lowName:find("newplayer") or child == (root.NewPlayerFriendlyButton) or child == (root.GuideButton) or child == (listing.NewPlayerFriendlyButton) then
                    roleKey = "GUIDE"
                end
                if roleKey and not cache.roles[roleKey] and child.GetRegions then
                    local info = {}
                    for _, reg in ipairs({ child:GetRegions() }) do
                        local spec = captureTexture(reg)
                        if spec then
                            local hint = ((spec.atlas or tostring(spec.texture or ""))):lower()
                            if hint:find("murloc") or hint:find("newcomer") or hint:find("baby") then
                                info.badge = spec
                            elseif hint:find("background") or hint:find("swirl") or hint:find("glow") then
                                info.swirl = info.swirl or spec
                            elseif (hint:find("role") or hint:find("shield") or hint:find("sword") or hint:find("heal") or hint:find("flag") or hint:find("guide") or hint:find("newplayer"))
                                and not hint:find("eye")
                            then
                                info.icon = info.icon or spec
                            end
                        end
                    end
                    for _, iconField in pairs({ child.Icon, child.RoleIcon, child.Texture }) do
                        if iconField then
                            local iconSpec = captureTexture(iconField)
                            if iconSpec then
                                local hint = ((iconSpec.atlas or tostring(iconSpec.texture or ""))):lower()
                                if not hint:find("eye") then
                                    info.icon = iconSpec
                                    break
                                end
                            end
                        end
                    end
                    if child.Background or child.Swirl then
                        info.swirl = captureTexture(child.Background or child.Swirl) or info.swirl
                    end
                    cache.roles[roleKey] = info
                end
            end

            -- Discover illustrated category banners inside CategorySelection / ScrollBox (including nested child frames)
            if (objType == "Button" or objType == "CheckButton" or (child.Label or child.Name or child.Text or child.Cover or child.Background)) and child.GetRegions then
                local textStr = ""
                for _, labelField in pairs({ child.Label, child.Name, child.Text, child.Title }) do
                    if labelField and labelField.GetText then
                        local okT, txt = pcall(labelField.GetText, labelField)
                        if okT and type(txt) == "string" and txt ~= "" then
                            textStr = textStr .. " " .. txt:lower()
                        end
                    end
                end
                local candidateTextures = {}
                local function collectRegions(frm, rDepth)
                    if not frm or (rDepth or 0) <= 0 then return end
                    if frm.GetRegions then
                        for _, reg in ipairs({ frm:GetRegions() }) do
                            if reg.GetObjectType and reg:GetObjectType() == "FontString" then
                                local okT, txt = pcall(reg.GetText, reg)
                                if okT and type(txt) == "string" and txt ~= "" then
                                    textStr = textStr .. " " .. txt:lower()
                                end
                            else
                                candidateTextures[#candidateTextures + 1] = reg
                            end
                        end
                    end
                    for _, texField in pairs({ frm.Background, frm.Cover, frm.Icon, frm.Texture, frm.Art, frm.Image, frm.Bg }) do
                        if texField then
                            candidateTextures[#candidateTextures + 1] = texField
                        end
                    end
                    if (rDepth or 0) > 1 and frm.GetChildren then
                        for _, subCh in ipairs({ frm:GetChildren() }) do
                            collectRegions(subCh, (rDepth or 1) - 1)
                        end
                    end
                end
                collectRegions(child, 2)

                local catKey = classifyBannerText(textStr)
                if catKey then
                    local bestBg = nil
                    local bestScore = -1
                    for _, reg in ipairs(candidateTextures) do
                        local spec = captureTexture(reg)
                        if spec then
                            local hint = ((spec.atlas or tostring(spec.texture or ""))):lower()
                            local isNoise = hint:find("highlight")
                                or hint:find("hover")
                                or hint:find("check")
                                or hint:find("border")
                                or hint:find("nine")
                                or hint:find("arrow")
                                or hint:find("mask")
                                or hint:find("shadow")
                                or hint:find("common-button-list", 1, true)
                                or hint:find("white8x8", 1, true)
                                or hint:find("solid", 1, true)
                                or hint:find("backdrop", 1, true)
                                or hint:find("uipanel", 1, true)
                                or hint:find("scroll", 1, true)
                                or hint:find("thumb", 1, true)
                            if not isNoise then
                                local rw = (reg.GetWidth and reg:GetWidth()) or 0
                                local rh = (reg.GetHeight and reg:GetHeight()) or 0
                                local score = (rw * rh)
                                if hint:find("groupfinder-button", 1, true)
                                    or hint:find("groupfinder-background", 1, true)
                                    or hint:find("ui-lfg-background", 1, true)
                                    or hint:find("dungeon")
                                    or hint:find("quest")
                                    or hint:find("battle")
                                    or hint:find("pvp")
                                    or hint:find("custom")
                                    or hint:find("raid")
                                then
                                    score = score + 100000
                                end
                                if score > bestScore then
                                    bestScore = score
                                    bestBg = spec
                                end
                            end
                        end
                    end
                    if bestBg and not cache.banners[catKey] then
                        cache.banners[catKey] = bestBg
                    end
                end
            end

            scanContainer(child, (depth or 1) - 1)
        end
    end

    pcall(scanContainer, listing, 5)
    return cache
end

function LFGFrameTab:ApplyRecommendedRoles(preserveGuide)
    local rec = (ns.Clan and ns.Clan.GetRecommendedRolesForCharacter) and ns.Clan:GetRecommendedRolesForCharacter() or nil
    if rec and type(rec.recommended) == "table" then
        self.roles.TANK = rec.recommended.TANK == true
        self.roles.HEALER = rec.recommended.HEALER == true
        self.roles.DPS = rec.recommended.DPS == true
        if not preserveGuide then
            self.roles.GUIDE = false
        end
        self.composerRole = rec.primaryRole or self:GetPrimaryListingRole()
        self._roleRecCache = rec
        return rec
    end
    local roleId = "DPS"
    if ns.Clan and ns.Clan.GetMySpecAndRole then
        local ok, detected = pcall(ns.Clan.GetMySpecAndRole, ns.Clan)
        if ok and (detected == "TANK" or detected == "HEALER" or detected == "DPS") then
            roleId = detected
        end
    end
    self.roles.TANK = (roleId == "TANK")
    self.roles.HEALER = (roleId == "HEALER")
    self.roles.DPS = (roleId == "DPS")
    if not preserveGuide then
        self.roles.GUIDE = false
    end
    self.composerRole = roleId
    return nil
end

local function ReadOfficialSoloRoles()
    if (Compat.IsInGroup and Compat.IsInGroup()) or not C_LFGListRoles then
        return nil
    end
    local fn = C_LFGListRoles.GetRoles or C_LFGListRoles.GetSavedRoles
    if not fn then return nil end
    local r1, r2, r3 = Safe.Call(fn)
    local isT, isH, isD
    if type(r1) == "table" then
        isT = (Safe.Value(r1.tank) == true)
        isH = (Safe.Value(r1.healer) == true)
        isD = (Safe.Value(r1.dps) == true)
    elseif r1 ~= nil or r2 ~= nil or r3 ~= nil then
        isT = (r1 == true)
        isH = (r2 == true)
        isD = (r3 == true)
    else
        return nil
    end
    if isT or isH or isD then
        return { TANK = (isT == true), HEALER = (isH == true), DPS = (isD == true) }
    end
    return nil
end

function LFGFrameTab:InitDefaultRoles()
    if self.rolesInitialized then return end
    self.rolesInitialized = true
    local offRoles = ReadOfficialSoloRoles()
    if offRoles then
        self.roles.TANK = offRoles.TANK
        self.roles.HEALER = offRoles.HEALER
        self.roles.DPS = offRoles.DPS
        self.roles.GUIDE = false
        self.composerRole = self:GetPrimaryListingRole()
        return
    end
    self:ApplyRecommendedRoles(false)
end

function LFGFrameTab:HasAnySelectedRole()
    return self.roles.TANK == true or self.roles.HEALER == true or self.roles.DPS == true or self.roles.GUIDE == true
end

function LFGFrameTab:GetPrimaryListingRole()
    local r = self.roles
    local combatCount = (r.TANK and 1 or 0) + (r.HEALER and 1 or 0) + (r.DPS and 1 or 0)
    if combatCount == 1 then
        if r.TANK then return "TANK" end
        if r.HEALER then return "HEALER" end
        if r.DPS then return "DPS" end
    end
    return "ANY"
end

function LFGFrameTab:GetSelectedRolesNoteTag()
    local parts = {}
    local r = self.roles
    local combatCount = (r.TANK and 1 or 0) + (r.HEALER and 1 or 0) + (r.DPS and 1 or 0)
    if combatCount > 1 then
        if r.TANK then parts[#parts + 1] = L["Tank"] end
        if r.HEALER then parts[#parts + 1] = L["Healer"] end
        if r.DPS then parts[#parts + 1] = L["DPS"] end
    end
    if r.GUIDE then
        parts[#parts + 1] = L["Dungeon Guide"]
    end
    if #parts == 0 then
        return ""
    end
    return "[" .. table.concat(parts, "/") .. "]"
end

local function NormalizeActivityKey(text)
    if type(text) ~= "string" then return "" end
    local s = text:lower()
        :gsub("á", "a"):gsub("à", "a"):gsub("ã", "a"):gsub("â", "a")
        :gsub("é", "e"):gsub("ê", "e")
        :gsub("í", "i")
        :gsub("ó", "o"):gsub("ô", "o"):gsub("õ", "o")
        :gsub("ú", "u"):gsub("ç", "c")
        :gsub("'", ""):gsub("`", "")
    local short = s:match("^([^(]+)")
    return (short or s):match("^%s*(.-)%s*$")
end

local function ResolveActivityDisplayName(act)
    if type(act) ~= "table" then return "" end
    return act.summaryLabel or act.directLabel or (act.labelKey and L[act.labelKey]) or ""
end

function LFGFrameTab:GetFilteredCategoryActivities(catId, showAll)
    local targetCat = catId or self.activeCategory or "DUNGEONS"
    local source = CURATED_ACTIVITIES[targetCat] or CURATED_ACTIVITIES.DUNGEONS
    local merged = {}
    local seenNorm = {}
    local offNormMap = {}

    if targetCat == "QUESTS" and ns.Clan and ns.Clan.GetActiveGroupQuests then
        local gQuests = ns.Clan:GetActiveGroupQuests()
        for i = 1, #gQuests do
            local q = gQuests[i]
            local grpTag = (q.suggestedGroup and q.suggestedGroup >= 2)
                and L["[Quest · Group %d]"]:format(q.suggestedGroup)
                or (q.tagName and q.tagName ~= "" and ("[" .. q.tagName .. "]") or L["[Group Quest]"])
            local zonePart = (q.zone and q.zone ~= "") and (" — " .. q.zone) or ""
            merged[#merged + 1] = {
                id = "qlog_" .. tostring((q.questID and q.questID > 0) and q.questID or i),
                directLabel = grpTag .. " " .. q.title .. zonePart,
                summaryLabel = q.title,
                minLvl = (q.level and q.level > 0) and q.level or 1,
                maxLvl = (q.level and q.level > 0) and q.level or 60,
                isQuestEntry = true,
                questTitle = q.title,
                suggestedGroup = q.suggestedGroup or 0,
                zone = q.zone or "",
            }
        end
    end

    if ns.Clan and ns.Clan.GetOfficialActivitiesForKind then
        local offList = ns.Clan:GetOfficialActivitiesForKind(targetCat)
        local seenOffId = {}
        for i = 1, #offList do
            local o = offList[i]
            local oid = o and o.officialId
            if oid and not seenOffId[oid] then
                seenOffId[oid] = true
                local nFull = NormalizeActivityKey(o.label)
                local nShort = NormalizeActivityKey(o.shortLabel)
                local baseKey = (nShort ~= "" and nShort) or nFull
                if baseKey ~= "" then
                    seenNorm[baseKey] = true
                    offNormMap[baseKey] = oid
                end
                if nFull ~= "" then
                    seenNorm[nFull] = true
                    offNormMap[nFull] = oid
                end
                local minL = o.minLvl or 1
                local maxL = o.maxLvl or 60
                if (minL <= 1 and maxL >= 60) and ns.Clan.ResolveActivityLevelRange then
                    local rMin, rMax = ns.Clan:ResolveActivityLevelRange(nil, o.label, targetCat)
                    if rMin and rMax then
                        minL, maxL = rMin, rMax
                    end
                end
                merged[#merged + 1] = {
                    id = "off_" .. tostring(oid),
                    officialId = oid,
                    directLabel = o.label,
                    summaryLabel = o.shortLabel or o.label,
                    engLabel = o.label,
                    minLvl = minL or 1,
                    maxLvl = maxL or 60,
                    isOfficialActivity = true,
                }
            end
        end
    end

    for i = 1, #source do
        local act = source[i]
        local locLabel = (act.labelKey and L[act.labelKey]) or ""
        local nLoc = NormalizeActivityKey(locLabel)
        local nEng = NormalizeActivityKey(act.labelKey or "")
        local matchedOfficial = seenNorm[nLoc] or seenNorm[nEng]
        if not matchedOfficial and nLoc ~= "" then
            for seenKey, _ in pairs(offNormMap) do
                if (nLoc ~= "" and (seenKey == nLoc or seenKey:find(nLoc, 1, true) or nLoc:find(seenKey, 1, true)))
                    or (nEng ~= "" and (seenKey == nEng or seenKey:find(nEng, 1, true) or nEng:find(seenKey, 1, true)))
                then
                    matchedOfficial = true
                    break
                end
            end
        end
        if not matchedOfficial then
            if nLoc ~= "" then seenNorm[nLoc] = true end
            if nEng ~= "" then seenNorm[nEng] = true end
            merged[#merged + 1] = act
        end
    end

    if showAll then
        return merged
    end

    local out = {}
    local lvl = ns.Safe and ns.Safe.Number(UnitLevel and UnitLevel("player")) or 60
    if lvl <= 0 then lvl = 60 end
    for i = 1, #merged do
        local act = merged[i]
        if act.isQuestEntry then
            out[#out + 1] = act
        end
    end
    local baseCount = #out
    for i = 1, #merged do
        local act = merged[i]
        if not act.isQuestEntry and lvl >= (act.minLvl or 1) and lvl <= (act.maxLvl or 60) then
            out[#out + 1] = act
        end
    end
    if #out == baseCount and targetCat == "DUNGEONS" then
        -- Include upcoming entry dungeons (+4 levels, e.g. RFC/Hall of Thanes at Lv 12) before showing Lv 60 raids.
        for i = 1, #merged do
            local act = merged[i]
            if not act.isQuestEntry and (lvl + 4) >= (act.minLvl or 1) and lvl <= (act.maxLvl or 60) then
                out[#out + 1] = act
            end
        end
    end
    if #out == baseCount then
        return merged
    end
    return out
end

function LFGFrameTab:HasAnySelectedActivity()
    local items = self:GetFilteredCategoryActivities(self.activeCategory, self.showAllLevels)
    local count = 0
    for i = 1, #items do
        if self.selectedActivities[items[i].id] then
            count = count + 1
        end
    end
    if count > 0 then
        return true, count
    end
    for _, v in pairs(self.selectedActivities) do
        if v then
            count = count + 1
        end
    end
    return count > 0, count
end

function LFGFrameTab:CollectSelectedActivitiesMeta()
    local names = {}
    local officialIds = {}
    local seenIds = {}
    local selectedItems = {}
    local maxCap = (_G.Constants and _G.Constants.LFGConstsExposed and _G.Constants.LFGConstsExposed.GROUP_FINDER_MAX_ACTIVITY_CAPACITY) or 16

    local function PushAct(act)
        local disp = ResolveActivityDisplayName(act)
        if disp ~= "" then
            names[#names + 1] = disp
        end
        local oid = ns.Safe and ns.Safe.Number(act.officialId) or nil
        if oid and oid > 0 and not seenIds[oid] and #officialIds < maxCap then
            seenIds[oid] = true
            officialIds[#officialIds + 1] = oid
        end
        selectedItems[#selectedItems + 1] = {
            officialId = oid,
            label = disp,
            summaryLabel = act.summaryLabel,
            engLabel = act.engLabel or act.labelKey,
            zone = act.zone,
        }
    end

    local activeItems = self:GetFilteredCategoryActivities(self.activeCategory, true)
    for i = 1, #activeItems do
        local act = activeItems[i]
        if self.selectedActivities[act.id] then
            PushAct(act)
        end
    end
    if #names == 0 then
        for _, cat in ipairs(LISTING_CATEGORIES) do
            local list = CURATED_ACTIVITIES[cat.id] or {}
            for i = 1, #list do
                if self.selectedActivities[list[i].id] then
                    PushAct(list[i])
                end
            end
        end
    end
    return {
        names = names,
        officialIds = officialIds,
        selectedItems = selectedItems,
    }
end

function LFGFrameTab:GetSelectedActivitiesSummary()
    local meta = self:CollectSelectedActivitiesMeta()
    local names = meta.names
    if #names == 0 then
        return GetCategoryLabel(self.activeCategory or "DUNGEONS")
    end
    if #names <= 2 then
        local txt = table.concat(names, ", ")
        if #txt <= 72 then return txt end
    end
    local extra = #names - 1
    local head = names[1]
    if #head > 54 then
        head = head:sub(1, 51) .. "..."
    end
    if extra > 0 then
        return head .. " (+" .. tostring(extra) .. ")"
    end
    return head
end

function LFGFrameTab:GetSelfActiveListing()
    if not (ns.Clan and ns.Clan.GetClanLFGList) then
        return nil
    end
    local ok, items = pcall(ns.Clan.GetClanLFGList, ns.Clan, nil, false, "ALL")
    if ok and type(items) == "table" then
        for i = 1, #items do
            if items[i] and items[i].isSelf then
                return items[i]
            end
        end
    end
    return nil
end

function LFGFrameTab:HasSelfActiveListing()
    return self:GetSelfActiveListing() ~= nil
end

function LFGFrameTab:StartEditListing(item)
    local target = item or self:GetSelfActiveListing()
    local inGroup = Compat.IsInGroup and Compat.IsInGroup()
    local activeEntry = (C_LFGList and C_LFGList.HasActiveEntryInfo and Safe.Value(Safe.Call(C_LFGList.HasActiveEntryInfo)) == true and C_LFGList.GetActiveEntryInfo)
        and Safe.Call(C_LFGList.GetActiveEntryInfo)
        or nil

    if type(activeEntry) == "table" and ((not target) or target.isOfficial == true) then
        self:SwitchToOfficialListingTab(nil)
        return
    end

    if not target and type(activeEntry) ~= "table" then
        self.listingMode = inGroup and "LFM" or "LFG"
        self.viewMode = "categories"
        self:RefreshData()
        return
    end
    self.listingMode = (target and target.mode == "LFM") and "LFM" or (inGroup and "LFM" or "LFG")

    local syncedRolesFromOfficial = false
    local offRoles = ReadOfficialSoloRoles()
    if offRoles then
        self.roles.TANK = offRoles.TANK
        self.roles.HEALER = offRoles.HEALER
        self.roles.DPS = offRoles.DPS
        syncedRolesFromOfficial = true
    end
    if not syncedRolesFromOfficial then
        if target and type(target.soloRoles) == "table" and (target.soloRoles.TANK or target.soloRoles.HEALER or target.soloRoles.DPS) then
            self.roles.TANK = (target.soloRoles.TANK == true)
            self.roles.HEALER = (target.soloRoles.HEALER == true)
            self.roles.DPS = (target.soloRoles.DPS == true)
        elseif target and (target.role == "TANK" or target.role == "HEALER" or target.role == "DPS") then
            self.roles.TANK = (target.role == "TANK")
            self.roles.HEALER = (target.role == "HEALER")
            self.roles.DPS = (target.role == "DPS")
        else
            self:InitDefaultRoles()
        end
    end
    if type(activeEntry) == "table" and activeEntry.newPlayerFriendly ~= nil then
        self.roles.GUIDE = (activeEntry.newPlayerFriendly == true)
    elseif target and target.newPlayerFriendly ~= nil then
        self.roles.GUIDE = (target.newPlayerFriendly == true)
    end

    local officialIdSet = {}
    if target and type(target.activityIds) == "table" then
        for i = 1, #target.activityIds do
            local nid = Safe.Number(target.activityIds[i])
            if nid then officialIdSet[nid] = true end
        end
    end
    if type(activeEntry) == "table" and type(activeEntry.activityIDs) == "table" then
        for i = 1, #activeEntry.activityIDs do
            local nid = Safe.Number(activeEntry.activityIDs[i])
            if nid then officialIdSet[nid] = true end
        end
    end

    local catId = target and target.categoryKind
    local actHay = ((target and (target.activityAllNames or target.activity) or "") .. " " .. (target and target.note or "")):lower()
    if (not catId or catId == "ALL" or not CURATED_ACTIVITIES[catId]) and next(officialIdSet) ~= nil then
        local firstAid = next(officialIdSet)
        if firstAid then
            for _, cat in ipairs(LISTING_CATEGORIES) do
                if ns.Clan and ns.Clan.GetOfficialActivitiesForKind then
                    local offCat = ns.Clan:GetOfficialActivitiesForKind(cat.id)
                    for i = 1, #offCat do
                        if offCat[i].officialId == firstAid then
                            catId = cat.id
                            break
                        end
                    end
                end
                if catId then break end
            end
        end
    end
    if not catId or catId == "ALL" or not CURATED_ACTIVITIES[catId] then
        if target and target.isDungeon then
            catId = "DUNGEONS"
        else
            catId = nil
            for _, cat in ipairs(LISTING_CATEGORIES) do
                for _, act in ipairs(CURATED_ACTIVITIES[cat.id] or {}) do
                    local lbl = act.labelKey and L[act.labelKey] and L[act.labelKey]:lower()
                    local eng = act.labelKey and act.labelKey:lower() or ""
                    if (lbl and actHay:find(lbl, 1, true)) or (eng ~= "" and actHay:find(eng, 1, true)) then
                        catId = cat.id
                        break
                    end
                end
                if catId then break end
            end
            catId = catId or "DUNGEONS"
        end
    end
    self.activeCategory = catId
    wipe(self.selectedActivities)
    local allItems = self:GetFilteredCategoryActivities(catId, true)
    local matchedAny = false
    if next(officialIdSet) ~= nil then
        for i = 1, #allItems do
            local act = allItems[i]
            if act.officialId and officialIdSet[act.officialId] then
                self.selectedActivities[act.id] = true
                matchedAny = true
            end
        end
    end
    if not matchedAny then
        for i = 1, #allItems do
            local act = allItems[i]
            local lbl = ResolveActivityDisplayName(act):lower()
            local eng = (act.engLabel or act.labelKey or ""):lower()
            if (lbl ~= "" and actHay:find(lbl, 1, true)) or (eng ~= "" and actHay:find(eng, 1, true)) then
                self.selectedActivities[act.id] = true
                matchedAny = true
            end
        end
    end
    if not matchedAny and allItems[1] and target and target.sourceType == "TAG" then
        self.selectedActivities[allItems[1].id] = true
    end

    local rawNote = (target and target.note) or (type(activeEntry) == "table" and Safe.String(activeEntry.comment)) or ""
    if rawNote == "" and target and target.sourceType == "TAG" and target.activity and target.activity ~= L["LFG (Looking for Group)"] then
        rawNote = target.activity
    end
    self.commentText = rawNote
    if self.controls and self.controls.commentBox and self.controls.commentBox.SetText then
        self.controls.commentBox:SetText(rawNote)
    end
    self._editingListing = true
    self.viewMode = "activities"
    self:RefreshData()
end

function LFGFrameTab:UpdateRoleControls()
    local c = self.controls
    if not (c and c.roleButtons) then return end
    local rec = (ns.Clan and ns.Clan.GetRecommendedRolesForCharacter) and ns.Clan:GetRecommendedRolesForCharacter() or self._roleRecCache
    self._roleRecCache = rec
    for _, rb in ipairs(c.roleButtons) do
        local active = self.roles[rb.roleId] == true
        local capable = (rb.roleId == "GUIDE") or (not rec) or (not rec.capable) or (rec.capable[rb.roleId] == true)
        if rb.check then
            rb.check:SetChecked(active)
        end
        if rb.swirl then
            rb.swirl:SetAlpha(active and 1.0 or (capable and 0.25 or 0.08))
        end
        if rb.ringGlow then
            rb.ringGlow:SetShown(active)
        end
        if rb.icon then
            rb.icon:SetDesaturated((not active) and (not capable))
            local tc = rb.iconTint
            local inactiveAlpha = capable and 0.90 or 0.38
            if tc then
                rb.icon:SetVertexColor(tc[1], tc[2], tc[3], active and 1.0 or inactiveAlpha)
            else
                rb.icon:SetVertexColor(1.0, 1.0, 1.0, active and 1.0 or inactiveAlpha)
            end
        end
    end
    if c.roleSuggestLbl and rec then
        c.roleSuggestLbl:SetText("|cff3fb950" .. L["Suggested for %s"]:format(rec.whoDesc or "") .. ":|r |cffffd24d" .. (rec.rolesLabel or L["DPS"]) .. "|r")
    end
end

local function FormatLeaderOnlyMessage(leaderName)
    if leaderName and leaderName ~= "" then
        return L["Only the party leader (%s) can list or broadcast this group."]:format(leaderName)
    end
    return L["Only the party leader can list or broadcast this group."]
end

local function UpdateLeaderRestrictionTexts(c)
    if not c then return end
    local leaderName = Compat.GetGroupLeaderName and Compat.GetGroupLeaderName()
    if c.leaderNoticeBody then
        if leaderName and leaderName ~= "" then
            c.leaderNoticeBody:SetText(L["You are currently in a party led by %s. By Blizzard rules, only the party leader can create, edit, or advertise group listings and invite members.\n\nWhat you can do right now:\n• Click 'Browse Groups' below to view active Guild, Allies & Friends groups (read-only and whisper).\n• Ask the leader to broadcast the group or promote you, or leave the party to list solo."]:format(leaderName))
        else
            c.leaderNoticeBody:SetText(L["You are currently in a party and another player is the leader. By Blizzard rules, only the group leader can create, edit, or advertise group listings and invite members.\n\nWhat you can do right now:\n• Click 'Browse Groups' below to view active Guild, Allies & Friends groups (read-only and whisper).\n• Ask the leader to broadcast the group or promote you, or leave the party to list solo."])
        end
    end
    if c.leaderBrowseLabel then
        if leaderName and leaderName ~= "" then
            c.leaderBrowseLabel:SetText(L["Member mode (Leader: %s) — Only the leader can list or invite; you can browse and whisper."]:format(leaderName))
        else
            c.leaderBrowseLabel:SetText(L["Member mode — Only the leader can list or invite; you can browse and whisper."])
        end
    end
end

local function ApplySubPanelChromeLayout(c, useLfgHost, topOffset, hdrHeight)
    if not (c and c.artFrame) then return end
    local p = Theme:GetPalette()
    local isBlizz = Theme:IsBlizzard(p)
    local pKey = (p and p.key) or "blizzard"
    local chromeSig = pKey .. ":" .. (useLfgHost and "H:" or "S:") .. tostring(topOffset or 0) .. ":" .. tostring(hdrHeight or 0)
    if c.artFrame._scChromeSig == chromeSig then
        return
    end
    c.artFrame._scChromeSig = chromeSig
    local bgLeft = useLfgHost and 4 or 3
    local bgRight = useLfgHost and -4 or -3
    local bgTop = useLfgHost and -21 or -2
    local bgBottom = useLfgHost and 4 or 3
    local leftPad = useLfgHost and 5 or 3
    local rightPad = useLfgHost and -5 or -3
    local topPad = useLfgHost and -22 or -2
    local insideLeft = useLfgHost and 6 or 3
    local insideRight = useLfgHost and -6 or -3
    local footerTop = 28
    local artParent = LFGFrameTab.subPanel or c.artFrame

    if c.solidOpaqueBg then
        local wBg = (p and p.windowBg) or { 0.08, 0.075, 0.07, 1.0 }
        c.solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
        c.solidOpaqueBg:ClearAllPoints()
        c.solidOpaqueBg:SetPoint("TOPLEFT", artParent, "TOPLEFT", bgLeft, bgTop)
        c.solidOpaqueBg:SetPoint("BOTTOMRIGHT", artParent, "BOTTOMRIGHT", bgRight, bgBottom)
    end
    if c.headerBg then
        c.headerBg:ClearAllPoints()
        c.headerBg:SetPoint("TOPLEFT", c.artFrame, "TOPLEFT", leftPad, topPad)
        c.headerBg:SetPoint("TOPRIGHT", c.artFrame, "TOPRIGHT", rightPad, topPad)
        if hdrHeight then
            c.headerBg:SetHeight(hdrHeight)
        end
        if isBlizz and HasAtlas("groupfinder-Stat-StoneBG") then
            c.headerBg:SetAtlas("groupfinder-Stat-StoneBG", false)
            c.headerBg:SetVertexColor(1, 1, 1, 1)
        else
            c.headerBg:SetTexture(WHITE8X8)
            local hb = (p and p.headerBg) or { 0.12, 0.13, 0.16, 1.0 }
            c.headerBg:SetVertexColor(hb[1], hb[2], hb[3], 1.0)
        end
    end
    if c.headerSep then
        c.headerSep:ClearAllPoints()
        c.headerSep:SetPoint("TOPLEFT", c.artFrame, "TOPLEFT", leftPad, topOffset)
        c.headerSep:SetPoint("TOPRIGHT", c.artFrame, "TOPRIGHT", rightPad, topOffset)
        if isBlizz then
            c.headerSep:SetVertexColor(0.45, 0.35, 0.18, 0.85)
        else
            local br = (p and p.surfaceBorder) or { 0.22, 0.30, 0.42, 0.85 }
            c.headerSep:SetVertexColor(br[1], br[2], br[3], 0.85)
        end
    end
    if c.bgArt then
        c.bgArt:ClearAllPoints()
        c.bgArt:SetPoint("TOPLEFT", c.artFrame, "TOPLEFT", leftPad, topOffset)
        c.bgArt:SetPoint("BOTTOMRIGHT", c.artFrame, "BOTTOMRIGHT", rightPad, footerTop)
        if isBlizz and HasAtlas("groupfinder-background") then
            c.bgArt:SetAtlas("groupfinder-background", false)
            c.bgArt:SetVertexColor(1, 1, 1, 1)
        else
            c.bgArt:SetTexture(WHITE8X8)
            local ib = (p and p.insetBg) or { 0.05, 0.06, 0.08, 1.0 }
            c.bgArt:SetVertexColor(ib[1], ib[2], ib[3], 1.0)
        end
    end
    if c.insideFrame then
        c.insideFrame:ClearAllPoints()
        c.insideFrame:SetPoint("TOPLEFT", c.artFrame, "TOPLEFT", insideLeft, topOffset)
        c.insideFrame:SetPoint("BOTTOMRIGHT", c.artFrame, "BOTTOMRIGHT", insideRight, footerTop)
        c.insideFrame:SetShown(isBlizz and HasAtlas("common-insideframe"))
    end
end

local function SyncActionButtonsVisibility(c, isBrowse, isCats, isActs, hasListing, canManage, isNonLeaderMember, selfSelected)
    for _, btn in pairs({
        c.sendMsgBtn,
        c.inviteBtn,
        c.listGroupBtn,
        c.browseGroupsBtn,
        c.backBtn,
        c.listSelfBtn,
        c.unlistBtn,
        c.listHelpBtn,
    }) do
        if btn and btn.Hide then
            btn:Hide()
        end
    end

    if isBrowse then
        if c.sendMsgBtn then c.sendMsgBtn:Show() end
        if c.inviteBtn then c.inviteBtn:Show() end
        if c.listGroupBtn and not selfSelected then
            c.listGroupBtn:Show()
        end
        return
    end

    if isCats then
        if c.browseGroupsBtn then
            c.browseGroupsBtn:Show()
            StyleNativeButton(c.browseGroupsBtn, isNonLeaderMember == true)
        end
        if hasListing and canManage then
            if c.listGroupBtn then c.listGroupBtn:Show() end
            if c.unlistBtn then c.unlistBtn:Show() end
        end
        return
    end

    if isActs and c.backBtn then
        c.backBtn:Show()
    end
    if c.listSelfBtn then
        c.listSelfBtn:Show()
    end
    if c.unlistBtn and hasListing and canManage then
        c.unlistBtn:Show()
    end
    if c.listHelpBtn and c.body then
        c.listHelpBtn:ClearAllPoints()
        if c.listSelfBtn then
            c.listHelpBtn:SetPoint("RIGHT", c.listSelfBtn, "LEFT", -4, 0)
        end
        c.listHelpBtn:Show()
    end
end

function LFGFrameTab:UpdateViewLayout()
    local c = self.controls
    if not c then return end
    local canManage = (not Compat.CanManageGroupListing) or Compat.CanManageGroupListing()
    local isNonLeaderMember = not canManage
    local mode = self.viewMode or "categories"
    if isNonLeaderMember and mode == "activities" then
        self.viewMode = "categories"
        mode = "categories"
    end
    local isBrowse = (mode == "browse")
    local isCats = (mode == "categories")
    local isActs = (mode == "activities")

    local hdrHeight = 58
    local topOffset = -80
    local listTop = -81
    if isBrowse then
        hdrHeight = 58
        topOffset = -80
        listTop = -81
    else
        hdrHeight = 76
        topOffset = -98
        listTop = -100
    end

    local useLfgHost = (self.subPanel ~= nil) and (_G.LFGParentFrame ~= nil) and (self.subPanel:GetParent() == _G.LFGParentFrame)
    ApplySubPanelChromeLayout(c, useLfgHost, topOffset, hdrHeight)

    if c.browseHeader then
        c.browseHeader:SetShown(isBrowse)
        if c.catDropdown then
            c.catDropdown:ClearAllPoints()
            c.catDropdown:SetPoint("TOPLEFT", c.browseHeader, "TOPLEFT", useLfgHost and 62 or 10, -24)
        end
    end
    if c.activityDropdown and isBrowse then
        c.activityDropdown:Show()
    end
    if c.roleHeader then c.roleHeader:SetShown(not isBrowse) end
    if c.categoryView then c.categoryView:SetShown(isCats) end
    if c.activityView then c.activityView:SetShown(isActs) end
    if isNonLeaderMember then
        UpdateLeaderRestrictionTexts(c)
    end
    local selfListing = self:GetSelfActiveListing()
    local hasListing = (selfListing ~= nil)
    if c.officialListCtaBtn then
        c.officialListCtaBtn:SetShown(isCats and canManage)
        if c.officialListCtaBtn.SetEnabled then
            c.officialListCtaBtn:SetEnabled(canManage and not IsCombatLocked())
        end
    end
    if c.officialListHelpBtn then
        c.officialListHelpBtn:SetShown(isCats and canManage)
    end
    if c.categoryGuideLbl then
        c.categoryGuideLbl:SetShown(isCats and canManage)
        if isCats and canManage then
            c.categoryGuideLbl:ClearAllPoints()
            c.categoryGuideLbl:SetPoint("TOPLEFT", c.categoryView, "TOPLEFT", 12, -31)
            c.categoryGuideLbl:SetPoint("TOPRIGHT", c.categoryView, "TOPRIGHT", -12, -31)
            if hasListing then
                c.categoryGuideLbl:SetText("|cff3fb950" .. L["Your listing is active — edit, delete, or pick a category below."] .. "|r")
            else
                c.categoryGuideLbl:SetText("|cffffd24d" .. L["Or create a PRIVATE listing (Guild, Allies & Friends only — hidden from public LFG):"] .. "|r")
            end
        end
    end
    if c.categoryButtons then
        local catStartY = (isCats and canManage) and -48 or -8
        for idx, catBtn in ipairs(c.categoryButtons) do
            if catBtn then
                if catBtn.SetShown then
                    catBtn:SetShown(canManage)
                end
                if canManage then
                    catBtn:ClearAllPoints()
                    catBtn:SetPoint("TOPLEFT", c.categoryView, "TOPLEFT", 10, catStartY - ((idx - 1) * 40))
                    catBtn:SetPoint("TOPRIGHT", c.categoryView, "TOPRIGHT", -10, catStartY - ((idx - 1) * 40))
                    catBtn:SetHeight(37)
                end
            end
        end
    end
    if c.leaderNoticePanel then
        c.leaderNoticePanel:SetShown(isCats and isNonLeaderMember)
    end
    if c.leaderBrowseBar then
        c.leaderBrowseBar:SetShown(isBrowse and isNonLeaderMember)
        if isBrowse and isNonLeaderMember and c.body then
            c.leaderBrowseBar:ClearAllPoints()
            c.leaderBrowseBar:SetPoint("TOPLEFT", c.body, "TOPLEFT", 12, listTop)
            c.leaderBrowseBar:SetPoint("TOPRIGHT", c.body, "TOPRIGHT", -12, listTop)
        end
    end
    if self.list and self.list.container then
        self.list.container:SetShown(isBrowse)
    end
    if c.composerBar then
        c.composerBar:SetShown(false)
    end

    if isBrowse and self.list and self.list.container and c.body then
        local browseOffset = isNonLeaderMember and (listTop - 25) or listTop
        if self.list.container._scBrowseOffset ~= browseOffset then
            self.list.container._scBrowseOffset = browseOffset
            self.list.container:ClearAllPoints()
            self.list.container:SetPoint("TOPLEFT", c.body, "TOPLEFT", 12, browseOffset)
            self.list.container:SetPoint("BOTTOMRIGHT", c.body, "BOTTOMRIGHT", -12, 32)
        end
    end

    if ns.LFG then
        if not isBrowse then
            if ns.LFG.HideSideDrawer then ns.LFG:HideSideDrawer() end
        else
            local wantDrawer = self.active and self.subPanel and self.subPanel:IsShown()
                and (not IsCombatLocked())
                and ((not ns.db) or (not ns.db.settings) or (ns.db.settings.lfgSideDrawerOpen ~= false))
            if wantDrawer and ns.LFG.ShowSideDrawer and (not (ns.LFG.IsSideDrawerShown and ns.LFG:IsSideDrawerShown())) then
                ns.LFG:ShowSideDrawer(self)
            elseif ns.LFG.IsSideDrawerShown and ns.LFG:IsSideDrawerShown() then
                if ns.LFG.PositionSideDrawer then ns.LFG:PositionSideDrawer(self) end
                if ns.LFG.RefreshSideDrawer then ns.LFG:RefreshSideDrawer(self) end
            end
        end
    end

    if c.quickSourceButtons and self.UpdateQuickFilterVisuals then
        self:UpdateQuickFilterVisuals()
    end

    local selfSelected = isBrowse and (self.selectedItem ~= nil) and (self.selectedItem.isSelf == true)
    SyncActionButtonsVisibility(c, isBrowse, isCats, isActs, hasListing, canManage, isNonLeaderMember, selfSelected)

    self:UpdateRoleControls()
    self:UpdateBottomButtons(hasListing)
end

function LFGFrameTab:UpdateComposerLayout()
    self:UpdateViewLayout()
end

local function ResolveLfgInviteTarget(item)
    if Compat.CanInviteToGroup and not Compat.CanInviteToGroup() then
        return false, nil, nil, false, nil
    end
    if not item or item.isSelf then
        return false, nil, nil, false, nil
    end
    local targetName = item.displayName or item.lookupKey
    if not targetName or targetName == "" then
        return false, nil, nil, false, nil
    end
    local rKey = item.lookupKey or targetName
    local bInfo = (ns.Social and ns.Social.GetBNetLinkInfo) and ns.Social:GetBNetLinkInfo(rKey) or nil
    local bnetAccId = item.bnetAccountID or (bInfo and bInfo.bnetAccountID)
    local bnetName = item.bnetName or (bInfo and bInfo.bnetName)
    local isCrossFac = (item.sameFaction == false) or (bInfo and bInfo.sameFaction == false)
    local isMe = (Compat.IsMe and Compat.IsMe(targetName, item.guid)) == true
    local inGroup = (Compat.IsInMyGroup and Compat.IsInMyGroup(targetName, item.guid)) == true
    local canInvite = (not isMe)
        and (not inGroup)
        and (not isCrossFac)
        and (item.online ~= false)
        and (item.hasCharacterName ~= false)
    return canInvite, targetName, bnetAccId, isCrossFac, bnetName
end

function LFGFrameTab:UpdateBottomButtons(hasSelfListingOverride)
    local c = self.controls
    if not c then return end
    local combat = IsCombatLocked()
    local inGroup = Compat.IsInGroup and Compat.IsInGroup()
    local canManage = (not Compat.CanManageGroupListing) or Compat.CanManageGroupListing()
    local canInviteGroup = (not Compat.CanInviteToGroup) or Compat.CanInviteToGroup()
    local leaderName = (not canManage or not canInviteGroup) and Compat.GetGroupLeaderName and Compat.GetGroupLeaderName() or nil
    local sel = self.selectedItem
    local selfSelected = (self.viewMode == "browse") and (sel ~= nil) and (sel.isSelf == true)
    local hasListing
    if hasSelfListingOverride ~= nil then
        hasListing = hasSelfListingOverride
    else
        hasListing = self:HasSelfActiveListing()
    end

    if c.sendMsgBtn then
        if selfSelected then
            c.sendMsgBtn:SetText(L["Edit Listing"])
            AutoFitNativeButton(c.sendMsgBtn, 96, 16, 152)
            if c.sendMsgBtn.SetEnabled then
                c.sendMsgBtn:SetEnabled(not combat)
            end
        else
            c.sendMsgBtn:SetText(L["Send Message"])
            AutoFitNativeButton(c.sendMsgBtn, 96, 16, 152)
            local canAct = (sel ~= nil) and (sel.isSelf ~= true) and (sel.secretLeaderName == nil) and (sel.isUnknownLeader ~= true) and not combat
            if c.sendMsgBtn.SetEnabled then
                c.sendMsgBtn:SetEnabled(canAct)
            end
        end
    end

    if c.inviteBtn then
        if selfSelected then
            c.inviteBtn:SetText(L["Delete Listing"])
            AutoFitNativeButton(c.inviteBtn, 90, 14, 140)
            c.inviteBtn._scNonLeaderInvite = false
            c.inviteBtn._scLeaderName = nil
            if c.inviteBtn.SetEnabled then
                c.inviteBtn:SetEnabled(not combat)
            end
        else
            c.inviteBtn:SetText(L["Invite"])
            AutoFitNativeButton(c.inviteBtn, 78, 14, 112)
            local canAct = (sel ~= nil) and (sel.isSelf ~= true) and (sel.secretLeaderName == nil) and (sel.isUnknownLeader ~= true) and not combat
            local canInviteSel = canAct and canInviteGroup and ResolveLfgInviteTarget(sel)
            c.inviteBtn._scNonLeaderInvite = not canInviteGroup
            c.inviteBtn._scLeaderName = leaderName
            if c.inviteBtn.SetEnabled then
                c.inviteBtn:SetEnabled(canInviteSel)
            end
        end
    end

    local bodyW = (c.body and c.body.GetWidth and c.body:GetWidth()) or 350
    local narrowBottom = (bodyW > 0 and bodyW < 420)
    if c.backBtn then
        AutoFitNativeButton(c.backBtn, narrowBottom and 66 or 92, narrowBottom and 12 or 18, narrowBottom and 82 or 124)
    end
    if c.browseGroupsBtn then
        AutoFitNativeButton(c.browseGroupsBtn, narrowBottom and 88 or 108, narrowBottom and 14 or 20, narrowBottom and 118 or 152)
    end
    if c.listGroupBtn then
        local ctaLabel = hasListing and L["Edit Listing"] or (inGroup and L["List Group"] or L["List Self"])
        c.listGroupBtn:SetText(ctaLabel)
        AutoFitNativeButton(c.listGroupBtn, narrowBottom and 76 or 88, narrowBottom and 12 or 16, narrowBottom and 104 or 134)
        c.listGroupBtn:ClearAllPoints()
        if self.viewMode == "categories" then
            if hasListing and canManage and c.browseGroupsBtn then
                c.listGroupBtn:SetPoint("LEFT", c.browseGroupsBtn, "RIGHT", 6, 0)
            else
                c.listGroupBtn:SetPoint("BOTTOMRIGHT", c.body, "BOTTOMRIGHT", -10, 5)
            end
        else
            c.listGroupBtn:SetPoint("BOTTOM", c.body, "BOTTOM", 12, 5)
        end
        c.listGroupBtn._scNonLeader = not canManage
        c.listGroupBtn._scLeaderName = leaderName
        if c.listGroupBtn.SetEnabled then
            c.listGroupBtn:SetEnabled(canManage and not combat)
        end
    end

    local hasRole = self:HasAnySelectedRole()
    local hasAct = self:HasAnySelectedActivity()
    local isOfficialBroadcast = (self.broadcastMode == "OFFICIAL")
    local canList = canManage and (self.viewMode == "activities") and (isOfficialBroadcast or (hasRole and hasAct)) and not combat
    if c.listSelfBtn then
        local postLabel
        if isOfficialBroadcast then
            postLabel = L["Open Official Tab"]
        elseif hasListing then
            postLabel = L["Update Listing"]
        elseif self.listingMode == "LFM" then
            postLabel = L["List Group"]
        else
            postLabel = L["List Self"]
        end
        c.listSelfBtn:SetText(postLabel)
        AutoFitNativeButton(c.listSelfBtn, narrowBottom and 84 or 100, narrowBottom and 12 or 18, narrowBottom and 116 or 158)
        c.listSelfBtn._scNonLeader = not canManage
        c.listSelfBtn._scLeaderName = leaderName
        c.listSelfBtn._scNeedsSelection = (not isOfficialBroadcast) and canManage and (self.viewMode == "activities") and (not hasRole or not hasAct)
        if c.listSelfBtn.SetEnabled then
            c.listSelfBtn:SetEnabled(canList)
        end
    end
    if c.unlistBtn then
        c.unlistBtn:SetText(L["Delete Listing"])
        AutoFitNativeButton(c.unlistBtn, narrowBottom and 76 or 86, narrowBottom and 12 or 16, narrowBottom and 98 or 132)
        c.unlistBtn:ClearAllPoints()
        if self.viewMode == "categories" then
            c.unlistBtn:SetPoint("BOTTOMRIGHT", c.body, "BOTTOMRIGHT", -10, 5)
        elseif c.listHelpBtn and c.listSelfBtn then
            c.unlistBtn:SetPoint("RIGHT", c.listHelpBtn, "LEFT", -6, 0)
        else
            c.unlistBtn:SetPoint("BOTTOM", c.body, "BOTTOM", -8, 5)
        end
        if c.unlistBtn.SetEnabled then
            c.unlistBtn:SetEnabled(canManage and hasListing and not combat)
        end
    end
end

local function EnsureStandaloneLfgHost()
    if LFGFrameTab.standaloneHost then
        return LFGFrameTab.standaloneHost
    end
    local w, h = 700, 526
    local lfgHost = _G.LFGParentFrame
    if lfgHost and lfgHost.GetWidth and lfgHost.GetHeight then
        local lw, lh = lfgHost:GetWidth() or 0, lfgHost:GetHeight() or 0
        if lw >= 560 and lh >= 400 then
            w, h = lw, math.max(526, lh + 24)
        end
    end
    local host = CreateFrame("Frame", "SocialCentralLFGStandaloneHost", UIParent, "BackdropTemplate")
    host:SetSize(w, h)
    host:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    host:SetFrameStrata("DIALOG")
    host:SetFrameLevel(520)
    if host.SetToplevel then
        host:SetToplevel(true)
    end
    host:EnableMouse(true)
    if host.SetClampedToScreen then
        host:SetClampedToScreen(true)
    end

    local sBg = host:CreateTexture(nil, "BACKGROUND", nil, -8)
    sBg:SetAllPoints(host)
    sBg:SetTexture(WHITE8X8)
    sBg:SetVertexColor(0.08, 0.075, 0.07, 1.0)
    host._solidOpaqueBg = sBg

    Theme:ApplyBackdrop(host, "window")
    if Theme.MakeMovable then
        Theme:MakeMovable(host, { key = "standalone_lfg" })
    end
    host:Hide()
    if type(UISpecialFrames) == "table" then
        local exists = false
        for _, nm in ipairs(UISpecialFrames) do
            if nm == "SocialCentralLFGStandaloneHost" then
                exists = true
                break
            end
        end
        if not exists then
            table.insert(UISpecialFrames, "SocialCentralLFGStandaloneHost")
        end
    end

    local headerBar = CreateFrame("Frame", nil, host)
    headerBar:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -2)
    headerBar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -2, -2)
    headerBar:SetHeight(24)
    local hBg = headerBar:CreateTexture(nil, "BACKGROUND", nil, -6)
    hBg:SetAllPoints()
    hBg:SetTexture(WHITE8X8)
    hBg:SetVertexColor(0.14, 0.11, 0.08, 1.0)
    headerBar._bg = hBg
    local hLine = headerBar:CreateTexture(nil, "ARTWORK", nil, 1)
    hLine:SetHeight(1)
    hLine:SetPoint("BOTTOMLEFT", headerBar, "BOTTOMLEFT", 0, 0)
    hLine:SetPoint("BOTTOMRIGHT", headerBar, "BOTTOMRIGHT", 0, 0)
    hLine:SetTexture(WHITE8X8)
    hLine:SetVertexColor(0.65, 0.50, 0.22, 0.85)
    host.headerBar = headerBar

    local hIcon = headerBar:CreateTexture(nil, "ARTWORK", nil, 2)
    hIcon:SetSize(16, 16)
    hIcon:SetPoint("LEFT", headerBar, "LEFT", 8, 0)
    hIcon:SetTexture(ICON_TEX)

    local closeBtn = Theme:CreateButton(host, 22, 18, "X", "default")
    closeBtn:SetPoint("TOPRIGHT", host, "TOPRIGHT", -6, -5)
    closeBtn:SetFrameLevel(host:GetFrameLevel() + 100)
    closeBtn:SetScript("OnClick", function()
        host:Hide()
    end)
    host.closeBtn = closeBtn

    local helpBtn = Theme:CreateHelpButton(
        headerBar,
        L["Help: Integrated Clan & Allies LFG"],
        L["Searches groups across Blizzard's Official Group Finder, Global Chat, Guild, Allied Guilds, Friends, and Watchlist inside one unified window."],
        L["Use Category, Activities, and Filters » to open the SocialCentral Filter Center side panel, or click any row's right button to Ask to Join or Invite."],
        16,
        { target = headerBar }
    )
    helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    host.helpBtn = helpBtn

    local hTitle = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hTitle:SetPoint("LEFT", hIcon, "RIGHT", 6, 0)
    hTitle:SetPoint("RIGHT", helpBtn, "LEFT", -6, 0)
    hTitle:SetJustifyH("LEFT")
    hTitle:SetWordWrap(false)
    hTitle:SetText(L["Clans & Allies LFG (Standalone Window)"])
    host.titleText = hTitle
    if Theme.AttachDragHandle then
        Theme:AttachDragHandle(headerBar, host)
    end

    host:HookScript("OnHide", function()
        if ns.LFG and ns.LFG.HideSideDrawer then
            ns.LFG:HideSideDrawer()
        end
        if LFGFrameTab.subPanel and LFGFrameTab.subPanel:GetParent() == host then
            LFGFrameTab.subPanel:Hide()
            LFGFrameTab.active = false
            LFGFrameTab:UpdateTabSelectionVisual()
            LFGFrameTab:SyncAllEmbeddedTabStates()
            if ns.RequestIdleGcStep then
                ns:RequestIdleGcStep(220, 0.8)
            end
        end
    end)

    LFGFrameTab.standaloneHost = host
    return host
end

function LFGFrameTab:EnsureStandaloneLfgHost()
    return EnsureStandaloneLfgHost()
end

function LFGFrameTab:ShowSubPanel(customHost)
    if type(customHost) == "boolean" then
        customHost = nil
    end
    if (not customHost) and ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled("I") then
        return
    end
    if IsCombatLocked() then
        ns:Print(L["Looking for Group (I)"] .. ": " .. L["Unavailable during combat."])
        return
    end
    local lfgHost = _G.LFGParentFrame
    local useLfgHost = (not customHost) and lfgHost and lfgHost.IsShown and lfgHost:IsShown()
    local targetHost = useLfgHost and lfgHost or (customHost or EnsureStandaloneLfgHost())
    if not targetHost then return end

    local wasActive = (self.active == true)
    self._transitionSeq = (self._transitionSeq or 0) + 1
    local seq = self._transitionSeq

    if useLfgHost and ns.UI and ns.UI.CloseEmbeddedIfHost then
        ns.UI:CloseEmbeddedIfHost(lfgHost)
    end
    self:InitDefaultRoles()
    if ns.Clan and ns.Clan.SyncOfficialActiveLfg then
        ns.Clan:SyncOfficialActiveLfg()
    end
    self:LoadSavedBrowseFilters(false)
    if self:SyncBrowseFilterToActiveListing(false) then
        self:SaveBrowseFilters()
    end
    if not self.subPanel then
        self:BuildSubPanel(targetHost)
    end
    if not self.subPanel then return end

    local refreshedArt = HarvestLfgListingArt(true)

    if useLfgHost then
        if self.standaloneHost and self.standaloneHost:IsShown() then
            self.standaloneHost:Hide()
        end
        if self.subPanel:GetParent() ~= lfgHost then
            self.subPanel:SetParent(lfgHost)
        end
        SyncSubPanelTemplateChrome(self.subPanel, true)
        self.subPanel:ClearAllPoints()
        self.subPanel:SetAllPoints(lfgHost)
        local subLvl = math.max(2, ((lfgHost.GetFrameLevel and lfgHost:GetFrameLevel()) or 1) + 5)
        self.subPanel:SetFrameLevel(subLvl)
        if self.controls and self.controls.artFrame then
            self.controls.artFrame:SetFrameLevel(subLvl + 1)
        end
        local nineLvl = (self.subPanel.NineSlice and MaxHierarchyLevel(self.subPanel.NineSlice, 3)) or subLvl
        if self.controls and self.controls.body then
            self.controls.body:SetFrameLevel(math.min(4500, math.max(subLvl + 4, nineLvl + 2)))
            if Theme and Theme.SyncSubtreeLayers then
                Theme:SyncSubtreeLayers(self.controls.body, 10)
            end
        end
        HideNativeLfgSubFrames()
        SetNativeTabsCheckedFalse()
    else
        SyncSubPanelTemplateChrome(self.subPanel, false)
        local p = Theme:GetPalette()
        if targetHost._solidOpaqueBg then
            local wBg = p.windowBg or { 0.08, 0.075, 0.07, 1.0 }
            targetHost._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
        end
        Theme:ApplyBackdrop(targetHost, "window", p)
        if targetHost.headerBar and targetHost.headerBar._bg then
            if p and p.key == "blizzard" then
                targetHost.headerBar._bg:SetVertexColor(0.18, 0.14, 0.09, 1.0)
            elseif p and p.key == "native" then
                targetHost.headerBar._bg:SetVertexColor(0.13, 0.11, 0.09, 1.0)
            else
                targetHost.headerBar._bg:SetVertexColor(0.12, 0.13, 0.16, 1.0)
            end
        end
        if targetHost.closeBtn then
            Theme:StyleButton(targetHost.closeBtn, "default")
        end
        if self.subPanel._titleLabel then
            self.subPanel._titleLabel:Hide()
        end
        if targetHost == LFGFrameTab.standaloneHost then
            targetHost:SetFrameStrata("DIALOG")
            if targetHost.SetToplevel then
                targetHost:SetToplevel(true)
            end
        end
        targetHost:Show()
        if targetHost.Raise then
            targetHost:Raise()
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if targetHost and targetHost:IsShown() and targetHost.Raise then
                    targetHost:Raise()
                end
            end)
        end
        if self.subPanel:GetParent() ~= targetHost then
            self.subPanel:SetParent(targetHost)
        end
        self.subPanel:ClearAllPoints()
        local topHostOffset = targetHost.headerBar and -26 or -2
        self.subPanel:SetPoint("TOPLEFT", targetHost, "TOPLEFT", 2, topHostOffset)
        self.subPanel:SetPoint("BOTTOMRIGHT", targetHost, "BOTTOMRIGHT", -2, 2)
        local subLvl = (targetHost:GetFrameLevel() or 520) + 10
        self.subPanel:SetFrameLevel(subLvl)
        if self.controls and self.controls.artFrame then
            self.controls.artFrame:SetFrameLevel(subLvl + 1)
        end
        if self.controls and self.controls.body then
            self.controls.body:SetFrameLevel(subLvl + 4)
            if Theme and Theme.SyncSubtreeLayers then
                Theme:SyncSubtreeLayers(self.controls.body, 10)
            end
        end
        if targetHost.headerBar then
            targetHost.headerBar:SetFrameLevel(subLvl + 50)
        end
        if targetHost.closeBtn then
            targetHost.closeBtn:SetFrameLevel(subLvl + 90)
        end
    end

    if self.controls and self.controls.categoryButtons then
        for _, catBtn in ipairs(self.controls.categoryButtons) do
            if catBtn and catBtn.ApplyBannerArt then
                catBtn:ApplyBannerArt(refreshedArt)
            end
        end
    end

    if useLfgHost then
        local titleStr = (_G.LOOKING_FOR_GROUP or L["Looking for Group"])
        if lfgHost.SetTitle then
            pcall(lfgHost.SetTitle, lfgHost, titleStr)
        elseif _G.LFGParentFrameTitleText then
            pcall(_G.LFGParentFrameTitleText.SetText, _G.LFGParentFrameTitleText, titleStr)
        end
        local nativeTitleFs = (lfgHost.TitleContainer and lfgHost.TitleContainer.TitleText)
            or _G.LFGParentFrameTitleText
            or (lfgHost.GetTitleText and lfgHost:GetTitleText())
        local nativeInContainer = nativeTitleFs and nativeTitleFs.GetParent and lfgHost.TitleContainer
            and (nativeTitleFs:GetParent() == lfgHost.TitleContainer)
        if self.subPanel._titleLabel then
            self.subPanel._titleLabel:SetText(titleStr)
            self.subPanel._titleLabel:SetShown(not nativeInContainer)
        end
    end

    self.active = true
    self._hasSearchedThisSession = true
    if ns.Clan and ns.Clan.MarkLfgUiActive then
        ns.Clan:MarkLfgUiActive()
    end
    self.subPanel:Show()
    if ns.Clan and ns.Clan.ScanOfficialLfgResults then
        ns.Clan:ScanOfficialLfgResults(true)
    end
    local hasFreshOfficial = false
    if ns.Clan and type(ns.Clan.officialLfgCache) == "table" then
        local nowSec = time()
        for _, rec in pairs(ns.Clan.officialLfgCache) do
            if type(rec) == "table" and (nowSec - (rec.updatedAt or 0)) <= 15 then
                local isOwn = Compat and Compat.IsMe and Compat.IsMe(rec.displayName or rec.lookupKey)
                if not isOwn then
                    hasFreshOfficial = true
                    break
                end
            end
        end
    end
    if not hasFreshOfficial then
        self:TriggerOfficialBrowseSearch(false)
    end
    if self._hasSearchedThisSession and ns.Clan and ns.Clan.RequestExternalLFGCatchup then
        ns.Clan:RequestExternalLFGCatchup()
    end
    if useLfgHost then
        SyncSubPanelTemplateChrome(self.subPanel, true)
        ElevateLfgParentControls()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if LFGFrameTab._transitionSeq ~= seq or not LFGFrameTab.active then
                    return
                end
                if not (_G.LFGParentFrame and _G.LFGParentFrame:IsShown() and LFGFrameTab.subPanel and LFGFrameTab.subPanel:IsShown()) then
                    return
                end
                SyncSubPanelTemplateChrome(LFGFrameTab.subPanel, true)
                HideNativeLfgSubFrames()
                SetNativeTabsCheckedFalse()
                ElevateLfgParentControls()
                LFGFrameTab:UpdateViewLayout()
                LFGFrameTab:UpdateTabSelectionVisual()
                LFGFrameTab:SyncAllEmbeddedTabStates()
            end)
        end
    end
    self:UpdateTabSelectionVisual()
    self:UpdateViewLayout()
    self:RefreshData()
    self:SyncAllEmbeddedTabStates()
    if Theme and Theme.PromptWindowTutorial then
        local function TriggerLfgPrompt()
            if LFGFrameTab.active ~= true or not (LFGFrameTab.subPanel and LFGFrameTab.subPanel:IsVisible()) then
                return
            end
            Theme:PromptWindowTutorial({
                tutorialKey = "winPrompt_lfg",
                title = L["Group Finder (LFG)"],
                guideSpec = {
                    key = "lfg_tab",
                    title = L["Group Finder (LFG)"],
                    defaultTarget = useLfgHost and LFGFrameTab.subPanel or (LFGFrameTab.standaloneHost or LFGFrameTab.subPanel),
                    isAnchorVisible = function() return LFGFrameTab.active == true and LFGFrameTab.subPanel ~= nil and LFGFrameTab.subPanel:IsVisible() == true end,
                    steps = {
                        {
                            title = L["Browse & Mirror LFG"],
                            text = L["Switch between Browse (Official + Guild/Allies groups) and My Listing, filter by dungeon/role/favorites, or apply with your customizable Whisper template."],
                            target = function() return (LFGFrameTab.controls and LFGFrameTab.controls.body) or LFGFrameTab.standaloneHost or LFGFrameTab.subPanel end,
                        },
                    },
                },
                isWindowVisible = function() return LFGFrameTab.active == true and LFGFrameTab.subPanel ~= nil and LFGFrameTab.subPanel:IsVisible() == true end,
            })
        end
        if (not useLfgHost) and C_Timer and C_Timer.After then
            C_Timer.After(0.05, TriggerLfgPrompt)
        else
            TriggerLfgPrompt()
        end
    end
end

function LFGFrameTab:HideSubPanel(restoreNative)
    self._transitionSeq = (self._transitionSeq or 0) + 1
    self.active = false
    if ns.LFG and ns.LFG.HideSideDrawer then
        ns.LFG:HideSideDrawer()
    end
    if self.subPanel then
        self.subPanel:Hide()
    end
    if not restoreNative and self.standaloneHost and self.standaloneHost:IsShown() then
        self.standaloneHost:Hide()
    end
    self:UpdateTabSelectionVisual()

    local lfgHost = _G.LFGParentFrame
    if lfgHost and not self.active and not (ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(lfgHost)) then
        if ns.UI and ns.UI.RestoreEmbeddedHostUI then
            ns.UI:RestoreEmbeddedHostUI(lfgHost)
        end
        local selectedTab = lfgHost.selectedTab or 1
        local subs = GetNativeLfgSubFrames()
        local shownOne = false
        for i, sub in ipairs(subs) do
            if sub and IsSafeUiObj(sub) and sub.SetShown then
                local shouldShow = (i == selectedTab)
                pcall(sub.SetShown, sub, shouldShow)
                if shouldShow then
                    shownOne = true
                end
            end
        end
        if not shownOne and _G.LFGListingFrame and IsSafeUiObj(_G.LFGListingFrame) and _G.LFGListingFrame.Show then
            pcall(_G.LFGListingFrame.Show, _G.LFGListingFrame)
        end
        if (restoreNative or lfgHost:IsShown()) and lfgHost.UpdateTabs then
            pcall(lfgHost.UpdateTabs, lfgHost)
        end
    end
    self:SyncAllEmbeddedTabStates()
    if ns.RequestIdleGcStep then
        ns:RequestIdleGcStep(220, 0.8)
    end
end

function LFGFrameTab:HandleOfficialActiveEntryUpdate(created)
    local isActive = (C_LFGList and C_LFGList.HasActiveEntryInfo and Safe.Value(Safe.Call(C_LFGList.HasActiveEntryInfo))) == true
    local wasActive = (self._hadOfficialActiveEntry == true)
    self._hadOfficialActiveEntry = isActive
    if not isActive then
        return false
    end
    if IsCombatLocked() then
        return false
    end
    if ns.db and ns.db.settings and ns.db.settings.lfgAutoOpenOnList == false then
        return false
    end
    if Compat.IsWindowIntegrationEnabled and not Compat.IsWindowIntegrationEnabled("I") then
        return false
    end
    local lfgHost = _G.LFGParentFrame
    if not (lfgHost and lfgHost.IsShown and lfgHost:IsShown()) then
        return false
    end
    local now = (GetTime and GetTime()) or 0
    local listingTabShown = (_G.LFGListingFrame and _G.LFGListingFrame.IsShown and _G.LFGListingFrame:IsShown()) == true
    local wasListingTabRecent = listingTabShown or ((now - (self._lastListingTabShownAt or 0)) <= 2.5)
    local shouldAutoOpen = (created == true) or (not wasActive) or wasListingTabRecent
    if not shouldAutoOpen then
        return false
    end

    self._suppressNativeTakeoverUntil = now + 1.4
    self._autoOpenOnListSeq = (self._autoOpenOnListSeq or 0) + 1
    local seq = self._autoOpenOnListSeq
    local function RunAutoOpen()
        if LFGFrameTab._autoOpenOnListSeq ~= seq or IsCombatLocked() then
            return
        end
        local host = _G.LFGParentFrame
        if not (host and host.IsShown and host:IsShown()) then
            return
        end
        if not (C_LFGList and C_LFGList.HasActiveEntryInfo and Safe.Value(Safe.Call(C_LFGList.HasActiveEntryInfo)) == true) then
            return
        end
        if ns.Clan and ns.Clan.SyncOfficialActiveLfg then
            ns.Clan:SyncOfficialActiveLfg()
        end
        LFGFrameTab:LoadSavedBrowseFilters(false)
        LFGFrameTab:SyncBrowseFilterToActiveListing(true)
        LFGFrameTab:SaveBrowseFilters()
        if ns.LFG and ns.LFG.GetListingType and ns.LFG.SetListingType then
            local inGrp = (Compat.IsInGroup and Compat.IsInGroup()) == true
            local curType = ns.LFG:GetListingType()
            if (not inGrp) and curType == "SOLO" then
                ns.LFG:SetListingType("ALL")
            elseif inGrp and curType == "GROUPS" then
                ns.LFG:SetListingType("ALL")
            end
        end
        LFGFrameTab.viewMode = "browse"
        LFGFrameTab._hasSearchedThisSession = true
        LFGFrameTab._suppressNativeTakeoverUntil = ((GetTime and GetTime()) or 0) + 1.25
        LFGFrameTab:ShowSubPanel()
        LFGFrameTab:TriggerOfficialBrowseSearch(true)
        ns:Emit("LFG_BROWSE_STATE_CHANGED")
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.06, RunAutoOpen)
    else
        RunAutoOpen()
    end
    return true
end

function LFGFrameTab:SwitchToOfficialListingTab(preferredSyncMode)
    if IsCombatLocked() then
        ns:Print("%s", L["Unavailable during combat."])
        return false
    end
    if preferredSyncMode == "GUILD_ALLIES" or preferredSyncMode == "GUILD_ONLY" or preferredSyncMode == "OFF" then
        if ns.Clan and ns.Clan.SetOfficialLfgSyncMode then
            ns.Clan:SetOfficialLfgSyncMode(preferredSyncMode)
        elseif ns.db and ns.db.settings then
            ns.db.settings.officialLfgSyncMode = preferredSyncMode
        end
    end
    if not (Compat.IsInGroup and Compat.IsInGroup()) and C_LFGListRoles and C_LFGListRoles.SetRoles and self:HasAnySelectedRole() then
        pcall(C_LFGListRoles.SetRoles, {
            tank = self.roles.TANK == true,
            healer = self.roles.HEALER == true,
            dps = self.roles.DPS == true,
        })
    end
    self._officialRedirectTipUntil = (GetTime and GetTime() or 0) + 14

    local lfgHost = _G.LFGParentFrame
    if lfgHost and lfgHost.IsShown and lfgHost:IsShown() then
        self._transitionSeq = (self._transitionSeq or 0) + 1
        self.active = false
        if ns.LFG and ns.LFG.HideSideDrawer then
            ns.LFG:HideSideDrawer()
        end
        if self.subPanel then
            self.subPanel:Hide()
        end
        if self.standaloneHost and self.standaloneHost:IsShown() then
            self.standaloneHost:Hide()
        end
        SyncHostNativeTabs(lfgHost, self.sideTab, false, { "ListingTab", "BrowsingTab", "WhoListingTab" })
        local listingTab = lfgHost.ListingTab or _G.LFGParentFrameTab1
        if listingTab and listingTab.Click then
            pcall(listingTab.Click, listingTab)
        end
        if not (_G.LFGListingFrame and _G.LFGListingFrame.IsShown and _G.LFGListingFrame:IsShown()) then
            lfgHost.selectedTab = 1
            local subs = GetNativeLfgSubFrames()
            for i, sub in ipairs(subs) do
                if sub and IsSafeUiObj(sub) and sub.SetShown then
                    pcall(sub.SetShown, sub, i == 1)
                end
            end
            if lfgHost.UpdateTabs then
                pcall(lfgHost.UpdateTabs, lfgHost)
            end
        end
        self:UpdateTabSelectionVisual()
        self:SyncAllEmbeddedTabStates()
        self:UpdateNativeBridgeBar()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if _G.LFGParentFrame and _G.LFGParentFrame:IsShown() then
                    LFGFrameTab:UpdateTabSelectionVisual()
                    LFGFrameTab:SyncAllEmbeddedTabStates()
                    LFGFrameTab:UpdateNativeBridgeBar()
                end
            end)
        end
        ns:Print("%s", L["Official LFG tab opened: select your activities and click Blizzard's List button — SocialCentral will mirror it automatically."])
        return true
    end

    ns:Print("%s", L["Press 'I' to open Blizzard's Group Finder (Listing tab) — SocialCentral will mirror your Official listing automatically."])
    return false
end

function LFGFrameTab:ToggleSubPanel()
    if self.active and self.subPanel and self.subPanel:IsShown() then
        self:HideSubPanel(true)
    else
        self:ShowSubPanel()
    end
end

function LFGFrameTab:RefreshTheme()
    local p = Theme:GetPalette()
    if self.standaloneHost then
        if self.standaloneHost._solidOpaqueBg then
            local wBg = p.windowBg or { 0.08, 0.075, 0.07, 1.0 }
            self.standaloneHost._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
        end
        Theme:ApplyBackdrop(self.standaloneHost, "window", p)
        if self.standaloneHost.headerBar and self.standaloneHost.headerBar._bg then
            local hBg = p.headerBg or { 0.12, 0.13, 0.16, 1.0 }
            self.standaloneHost.headerBar._bg:SetVertexColor(hBg[1], hBg[2], hBg[3], 1.0)
        end
        if self.standaloneHost.closeBtn then
            Theme:StyleButton(self.standaloneHost.closeBtn, "default")
        end
    end
    local panel = self.subPanel
    if not panel then
        if self.nativeBridgeBar then
            local wBg = p.windowBg or { 0.08, 0.075, 0.07, 1.0 }
            if self.nativeBridgeBar._solidOpaqueBg then
                self.nativeBridgeBar._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
            end
            Theme:ApplyBackdrop(self.nativeBridgeBar, "surface", p)
        end
        return
    end

    if panel._solidOpaqueBg then
        local wBg = p.windowBg or { 0.08, 0.075, 0.07, 1.0 }
        panel._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
        panel._solidOpaqueBg:Show()
    end
    if panel._useBackdropFallback then
        Theme:ApplyBackdrop(panel, "window", p)
    end

    local c = self.controls
    if c.artFrame then
        c.artFrame._scChromeSig = nil
    end
    if c.leaderNoticePanel and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(c.leaderNoticePanel, "surface", p)
    end
    if c.leaderBrowseBar and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(c.leaderBrowseBar, "surface", p)
    end
    if c.listGroupBtn then
        StyleNativeButton(c.listGroupBtn, false)
    end
    if c.commentBackdrop and Theme.ApplyInputBackdrop then
        Theme:ApplyInputBackdrop(c.commentBackdrop)
    end
    if c.searchBox and Theme.StyleEditBox and not c.searchBox._isNativeSearchBox then
        Theme:StyleEditBox(c.searchBox)
    end
    if self.activityList and self.activityList.RefreshTheme then
        self.activityList:RefreshTheme()
        Theme:ApplyBackdrop(self.activityList.container, "none")
    end
    if self.list and self.list.RefreshTheme then
        self.list:RefreshTheme()
        Theme:ApplyBackdrop(self.list.container, "none")
    end
    if self.nativeBridgeBar then
        local wBg = p.windowBg or { 0.08, 0.075, 0.07, 1.0 }
        if self.nativeBridgeBar._solidOpaqueBg then
            self.nativeBridgeBar._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
        end
        Theme:ApplyBackdrop(self.nativeBridgeBar, "surface", p)
    end
    if self.UpdateQuickMicroBarVisuals then
        self:UpdateQuickMicroBarVisuals()
    end
    self:UpdateViewLayout()
end

local function FormatLfgTemplateText(templateText, activityName, allowDefaultWhenAutoOff, itemOrIds)
    if ns.LFG and ns.LFG.FormatApplyMessage then
        local stub = type(itemOrIds) == "table" and itemOrIds or { activity = activityName }
        return ns.LFG:FormatApplyMessage(stub, templateText, allowDefaultWhenAutoOff)
    end
    local roleId = (LFGFrameTab.GetPrimaryListingRole and LFGFrameTab:GetPrimaryListingRole()) or "DPS"
    local baseRole = (roleId == "TANK" and L["Tank"]) or (roleId == "HEALER" and L["Healer"]) or L["DPS"]
    local sum = ns.Clan and ns.Clan.GetPlayerGameSummary and ns.Clan:GetPlayerGameSummary() or nil
    local ilvlVal = (sum and (sum.avgItemLevel or 0) > 0) and tostring(sum.avgItemLevel) or ""
    local ilvlPart = (ilvlVal ~= "") and ("iLvl " .. ilvlVal) or ""
    local lvlNum = (UnitLevel and ns.Safe and ns.Safe.Number(ns.Safe.Call(UnitLevel, "player"))) or 0
    local lvlStr = (lvlNum > 0) and tostring(lvlNum) or "60"
    local classLoc = UnitClass and ns.Safe and ns.Safe.String(ns.Safe.Call(UnitClass, "player")) or ""
    local actStr = (type(activityName) == "string" and activityName ~= "") and activityName or L["Dungeon"]

    if type(templateText) == "string" and templateText:match("%S") then
        local msg = templateText
        msg = msg:gsub("{level}", function() return lvlStr end)
        msg = msg:gsub("{class}", function() return classLoc end)
        msg = msg:gsub("{role}", function() return baseRole end)
        msg = msg:gsub("{ilvl}", function() return ilvlPart end)
        msg = msg:gsub("{activity}", function() return actStr end)
        msg = msg:gsub("{spec}", function() return baseRole end)
        msg = msg:gsub("{activity_en}", function() return actStr end)
        msg = msg:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
        if msg ~= "" then
            return msg
        end
    end

    local roleFull = (ilvlPart ~= "") and (baseRole .. " · " .. ilvlPart) or baseRole
    if lvlNum > 0 and classLoc ~= "" then
        if activityName and activityName ~= "" then
            return string.format(L["Hi! Lv %d %s (%s) available for %s"], lvlNum, classLoc, roleFull, activityName)
        end
        return string.format(L["Hi! Lv %d %s (%s) available!"], lvlNum, classLoc, roleFull)
    end
    if activityName and activityName ~= "" then
        return string.format(L["Hi! Available (%s) for %s"], roleFull, activityName)
    end
    return allowDefaultWhenAutoOff and L["Hi! Available!"] or nil
end

local function BuildLfgApplyDraft(item)
    if ns.LFG and ns.LFG.FormatApplyMessage then
        return ns.LFG:FormatApplyMessage(item, nil, false)
    end
    if ns.db and ns.db.settings and ns.db.settings.lfgAutoApplyDraft == false then
        return nil
    end
    local tmpl = ns.db and ns.db.settings and ns.db.settings.lfgWhisperTemplate or ""
    local act = item and (item._canonicalActivityLabel or (item.activity and item.activity ~= "" and item.activity)) or nil
    return FormatLfgTemplateText(tmpl, act, false, item)
end

function LFGFrameTab:FormatApplyDraftPreview(tmplOverride, sampleActivity)
    local rawTmpl = tmplOverride
    if rawTmpl == nil then
        rawTmpl = ns.db and ns.db.settings and ns.db.settings.lfgWhisperTemplate or ""
    end
    return FormatLfgTemplateText(rawTmpl, sampleActivity or L["The Deadmines"], true, {
        activity = sampleActivity or L["The Deadmines"],
        activityIds = { 796 },
    }) or ""
end

function LFGFrameTab:OpenWhisperTemplateModal()
    if IsCombatLocked() then
        ns:Print("%s", L["Unavailable during combat."])
        return
    end
    local m = self._whisperTemplateModal
    if not m then
        m = CreateFrame("Frame", "SocialCentralLFGWhisperTemplateModal", UIParent, "BackdropTemplate")
        m:Hide()
        m:SetSize(486, 424)
        m:SetPoint("CENTER")
        m:SetClampedToScreen(true)
        m:EnableMouse(true)
        if Theme.MakeMovable then
            Theme:MakeMovable(m, { clampToScreen = true })
        end
        if _G.UISpecialFrames then
            local found = false
            for _, n in ipairs(_G.UISpecialFrames) do
                if n == "SocialCentralLFGWhisperTemplateModal" then found = true break end
            end
            if not found then
                table.insert(_G.UISpecialFrames, "SocialCentralLFGWhisperTemplateModal")
            end
        end

        local bg = m:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetAllPoints(m)
        bg:SetTexture(WHITE8X8)
        bg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
        m._solidOpaqueBg = bg

        local titleFs = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        titleFs:SetPoint("TOPLEFT", 16, -14)
        titleFs:SetPoint("RIGHT", m, "RIGHT", -40, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetText(L["Apply & Invite Whisper Templates (/w)"])
        m.titleFs = titleFs

        local closeBtn = Theme:CreateButton(m, 24, 22, "X", "default")
        closeBtn:SetPoint("TOPRIGHT", -12, -12)
        closeBtn:SetScript("OnClick", function() m:Hide() end)
        m.closeBtn = closeBtn

        local helpBtn = Theme:CreateHelpButton(
            m,
            L["Help: Apply & Invite Whisper Templates (/w)"],
            L["Customizes both messages used across Group Finder (I) and Main Window -> Group -> Find Groups: your Apply message when contacting leaders and the optional Invite whisper sent when inviting solo players."],
            L["Available tokens: {level}, {class}, {role}, {spec} (primary specialization), {ilvl}, {activity} (game language), and {activity_en} (English activity name for international realms). Click a preset or leave Apply blank for the built-in greeting."],
            16,
            { target = m }
        )
        helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)

        local hintFs = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hintFs:SetPoint("TOPLEFT", 16, -42)
        hintFs:SetPoint("TOPRIGHT", -16, -42)
        hintFs:SetJustifyH("LEFT")
        hintFs:SetWordWrap(true)
        hintFs:SetTextColor(0.84, 0.88, 0.94)
        hintFs:SetText(L["Variables: {level}, {class}, {role}, {spec}, {ilvl}, {activity}, {activity_en}"])
        m.hintFs = hintFs

        local applySecLbl = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        applySecLbl:SetPoint("TOPLEFT", 16, -74)
        applySecLbl:SetText(L["Apply to Group Whisper:"])
        m.applySecLbl = applySecLbl

        local inputBox = Theme:CreateEditBox(m, {
            height = 26,
            maxLetters = 160,
            clearButton = true,
            placeholder = L["Leave blank to use the built-in Level/Class/Role draft..."],
        })
        inputBox:SetPoint("TOPLEFT", 16, -92)
        inputBox:SetPoint("TOPRIGHT", -16, -92)
        inputBox:SetScript("OnEscapePressed", function() m:Hide() end)
        m.inputBox = inputBox

        local function RefreshPreview()
            local preview = LFGFrameTab:FormatApplyDraftPreview(m.inputBox:GetText() or "", L["The Deadmines"])
            m.previewText:SetText(preview)
            if m.invitePreviewText then
                local invPrev = (ns.LFG and ns.LFG.FormatInviteMessage)
                    and ns.LFG:FormatInviteMessage({ activity = L["The Deadmines"], activityIds = { 796 } }, m.inviteBox:GetText() or "", true)
                    or (m.inviteBox:GetText() or "")
                m.invitePreviewText:SetText(invPrev)
            end
        end
        inputBox:HookScript("OnTextChanged", RefreshPreview)

        local presetLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        presetLbl:SetPoint("TOPLEFT", inputBox, "BOTTOMLEFT", 0, -8)
        presetLbl:SetTextColor(0.75, 0.80, 0.88)
        presetLbl:SetText(L["Quick Presets:"])

        local presets = {
            { lbl = L["Standard"], tmpl = "" },
            { lbl = L["Spec + EN"], tmpl = "{level} {spec} {class} ({role}) for {activity_en}" },
            { lbl = L["With Gear / iLvl"], tmpl = "Hi! {level} {spec} {class} ({role} {ilvl}) for {activity}" },
        }
        m.presetBtns = {}
        local prevPreset = nil
        for _, pr in ipairs(presets) do
            local b = Theme:CreateButton(m, 120, 22, pr.lbl, "default")
            Theme:AutoFitButton(b, 92, 16, 154)
            if not prevPreset then
                b:SetPoint("TOPLEFT", presetLbl, "BOTTOMLEFT", 0, -5)
            else
                b:SetPoint("LEFT", prevPreset, "RIGHT", 6, 0)
            end
            b:SetScript("OnClick", function()
                m.inputBox:SetText(pr.tmpl)
                RefreshPreview()
            end)
            m.presetBtns[#m.presetBtns + 1] = b
            prevPreset = b
        end

        local previewBox = CreateFrame("Frame", nil, m, "BackdropTemplate")
        previewBox:SetPoint("TOPLEFT", m.presetBtns[1], "BOTTOMLEFT", 0, -8)
        previewBox:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        previewBox:SetHeight(48)
        m.previewBox = previewBox

        local previewTitle = previewBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        previewTitle:SetPoint("TOPLEFT", 10, -6)
        previewTitle:SetText(L["Apply Live Preview:"])
        m.previewTitle = previewTitle

        local previewText = previewBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        previewText:SetPoint("TOPLEFT", previewTitle, "BOTTOMLEFT", 0, -3)
        previewText:SetPoint("BOTTOMRIGHT", -10, 5)
        previewText:SetJustifyH("LEFT")
        previewText:SetJustifyV("TOP")
        previewText:SetWordWrap(true)
        previewText:SetTextColor(0.95, 0.85, 0.45)
        m.previewText = previewText

        local autoCb = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
        autoCb:SetSize(22, 22)
        autoCb:SetPoint("TOPLEFT", previewBox, "BOTTOMLEFT", -2, -6)
        autoCb:SetScript("OnClick", function(selfCheck)
            if ns.db and ns.db.settings then
                ns.db.settings.lfgAutoApplyDraft = (selfCheck:GetChecked() == true)
            end
        end)
        m.autoCb = autoCb

        local autoLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        autoLbl:SetPoint("LEFT", autoCb, "RIGHT", 4, 0)
        autoLbl:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        autoLbl:SetJustifyH("LEFT")
        autoLbl:SetText(L["Pre-fill Apply draft automatically in Group Finder & Find Groups"])

        local invCb = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
        invCb:SetSize(22, 22)
        invCb:SetPoint("TOPLEFT", autoCb, "BOTTOMLEFT", 0, -4)
        invCb:SetScript("OnClick", function(selfCheck)
            if ns.db and ns.db.settings then
                ns.db.settings.lfgInviteAutoWhisper = (selfCheck:GetChecked() == true)
            end
        end)
        m.invCb = invCb

        local invLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        invLbl:SetPoint("LEFT", invCb, "RIGHT", 4, 0)
        invLbl:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        invLbl:SetJustifyH("LEFT")
        invLbl:SetText(L["Auto-whisper when inviting solo LFG players:"])

        local inviteBox = Theme:CreateEditBox(m, {
            height = 24,
            maxLetters = 160,
            clearButton = true,
            placeholder = L["e.g. Hi! Inviting you to our {activity_en} group!"],
        })
        inviteBox:SetPoint("TOPLEFT", invCb, "BOTTOMLEFT", 2, -4)
        inviteBox:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        inviteBox:SetScript("OnEscapePressed", function() m:Hide() end)
        inviteBox:HookScript("OnTextChanged", RefreshPreview)
        m.inviteBox = inviteBox

        local invitePreviewText = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        invitePreviewText:SetPoint("TOPLEFT", inviteBox, "BOTTOMLEFT", 2, -5)
        invitePreviewText:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        invitePreviewText:SetJustifyH("LEFT")
        invitePreviewText:SetWordWrap(true)
        invitePreviewText:SetTextColor(0.55, 0.90, 0.65)
        m.invitePreviewText = invitePreviewText

        local saveBtn = Theme:CreateButton(m, 110, 24, L["Save"], "primary")
        Theme:AutoFitButton(saveBtn, 96, 20, 140)
        saveBtn:SetPoint("BOTTOMRIGHT", -14, 14)
        saveBtn:SetScript("OnClick", function()
            if ns.db and ns.db.settings then
                local clean = (m.inputBox:GetText() or ""):gsub("[|\r\n]", " "):match("^%s*(.-)%s*$") or ""
                local cleanInv = (m.inviteBox:GetText() or ""):gsub("[|\r\n]", " "):match("^%s*(.-)%s*$") or ""
                ns.db.settings.lfgWhisperTemplate = clean
                ns.db.settings.lfgAutoApplyDraft = (m.autoCb:GetChecked() == true)
                ns.db.settings.lfgInviteAutoWhisper = (m.invCb:GetChecked() == true)
                if cleanInv ~= "" then
                    ns.db.settings.lfgInviteWhisperTemplate = cleanInv
                else
                    ns.db.settings.lfgInviteWhisperTemplate = "Hi! Inviting you to our {activity_en} group!"
                end
            end
            m:Hide()
            if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
            ns:Print("%s", L["Saved LFG Whisper Templates."])
        end)
        m.saveBtn = saveBtn

        local cancelBtn = Theme:CreateButton(m, 96, 24, L["Cancel"], "default")
        Theme:AutoFitButton(cancelBtn, 86, 18, 128)
        cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
        cancelBtn:SetScript("OnClick", function() m:Hide() end)
        m.cancelBtn = cancelBtn

        local resetBtn = Theme:CreateButton(m, 116, 24, L["Reset Default"], "default")
        Theme:AutoFitButton(resetBtn, 96, 18, 148)
        resetBtn:SetPoint("BOTTOMLEFT", 14, 14)
        resetBtn:SetScript("OnClick", function()
            m.inputBox:SetText("")
            m.inviteBox:SetText("Hi! Inviting you to our {activity_en} group!")
            RefreshPreview()
        end)
        m.resetBtn = resetBtn

        self._whisperTemplateModal = m
    end

    if Theme.PrepareTopOverlayModal then
        Theme:PrepareTopOverlayModal(m, 860)
    else
        m:SetParent(UIParent)
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(860)
        m:SetToplevel(true)
    end
    local p = Theme:GetPalette()
    if m._solidOpaqueBg then
        local wBg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
        m._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
    end
    Theme:ApplyBackdrop(m, "window", p)
    if m.previewBox then
        Theme:ApplyBackdrop(m.previewBox, "surface", p)
    end
    if m.inputBox and Theme.StyleEditBox then
        Theme:StyleEditBox(m.inputBox)
    end
    if m.inviteBox and Theme.StyleEditBox then
        Theme:StyleEditBox(m.inviteBox)
    end
    if m.previewTitle then
        local c = p and (p.textGold or p.accent) or { 1.0, 0.82, 0.25 }
        m.previewTitle:SetTextColor(c[1], c[2], c[3])
    end
    if m.applySecLbl then
        local c = p and (p.textGold or p.accent) or { 1.0, 0.82, 0.25 }
        m.applySecLbl:SetTextColor(c[1], c[2], c[3])
    end
    Theme:StyleButton(m.closeBtn, "default")
    Theme:StyleButton(m.saveBtn, "primary")
    Theme:StyleButton(m.cancelBtn, "default")
    Theme:StyleButton(m.resetBtn, "default")
    for _, b in ipairs(m.presetBtns or {}) do
        Theme:StyleButton(b, "default")
    end

    local s = ns.db and ns.db.settings
    m.autoCb:SetChecked(not s or s.lfgAutoApplyDraft ~= false)
    m.invCb:SetChecked(not s or s.lfgInviteAutoWhisper ~= false)
    m.inputBox:SetText((s and type(s.lfgWhisperTemplate) == "string") and s.lfgWhisperTemplate or "")
    m.inviteBox:SetText((s and type(s.lfgInviteWhisperTemplate) == "string" and s.lfgInviteWhisperTemplate ~= "") and s.lfgInviteWhisperTemplate or "Hi! Inviting you to our {activity_en} group!")
    m.previewText:SetText(self:FormatApplyDraftPreview(m.inputBox:GetText() or "", L["The Deadmines"]))
    if m.invitePreviewText then
        local invPrev = (ns.LFG and ns.LFG.FormatInviteMessage)
            and ns.LFG:FormatInviteMessage({ activity = L["The Deadmines"], activityIds = { 796 } }, m.inviteBox:GetText() or "", true)
            or (m.inviteBox:GetText() or "")
        m.invitePreviewText:SetText(invPrev)
    end
    m:Show()
    if m.Raise then m:Raise() end
end

local function OpenPlayerWhisper(item)
    if not item or item.isSelf then return end
    local targetName = item.displayName or item.lookupKey
    if not targetName or targetName == "" then return end
    local draft = BuildLfgApplyDraft(item)
    if item.mode ~= "LFG" and item.sourceType ~= "EVENT" and ns.LFG and ns.LFG.MarkAsked then
        ns.LFG:MarkAsked(item)
    end
    local rKey = item.lookupKey or targetName
    local bInfo = ns.Social and ns.Social.GetBNetLinkInfo and ns.Social:GetBNetLinkInfo(rKey)
    local isCrossFac = (item.sameFaction == false) or (bInfo and bInfo.sameFaction == false)
    local bnetName = item.bnetName or (bInfo and bInfo.bnetName)
    local bnetAccId = item.bnetAccountID or (bInfo and bInfo.bnetAccountID)
    local addonAllowed = (not Compat or not Compat.IsOfficialChatMode or not Compat.IsOfficialChatMode())
        and (not Compat or not Compat.IsModuleEnabled or Compat.IsModuleEnabled("chat"))
    local scConfirmed = addonAllowed and ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(rKey, bnetAccId)
    if scConfirmed and ns.Chat and ns.Chat.OpenPreferredConversation then
        ns.Chat:OpenPreferredConversation({
            targetName = targetName,
            lookupKey = rKey,
            bnetAccountID = bnetAccId,
            bnetName = bnetName,
            classFile = item.classFile,
            draftText = draft,
            isCrossFaction = isCrossFac,
            autoProbe = true,
            scConfirmed = true,
        })
    elseif isCrossFac and bnetName and Compat.BNetWhisper then
        Compat.BNetWhisper(bnetName, targetName, draft)
    elseif Compat.Whisper then
        Compat.Whisper(targetName, draft)
    end
end

function LFGFrameTab:QuickApplyToPlayer(targetName, lookupKey, activity)
    if not targetName or targetName == "" then return end
    if (not lookupKey or lookupKey == "") and Compat.ParseCharacterFields then
        lookupKey = Compat.ParseCharacterFields(targetName)
    end
    local matchedItem = nil
    if lookupKey and ns.Clan and ns.Clan.GetClanLFGList then
        for _, it in ipairs(ns.Clan:GetClanLFGList(nil, false, "ALL") or {}) do
            if it and not it.isSelf and it.lookupKey == lookupKey then
                matchedItem = it
                break
            end
        end
    end
    OpenPlayerWhisper(matchedItem or {
        lookupKey = lookupKey or targetName:lower(),
        displayName = targetName,
        activity = activity,
    })
end

local function AddDropdownMenuChoice(root, label, isSelectedFn, onSelectFn)
    if root.CreateRadio then
        root:CreateRadio(label, isSelectedFn, function()
            onSelectFn()
        end)
    else
        local prefix = isSelectedFn() and "|cff00ff00* |r" or "  "
        root:CreateButton(prefix .. label, function()
            onSelectFn()
        end)
    end
end

local function CreateNativeDropdown(parent, name, width, height, getTextFn, buildMenuFn)
    local ok, dd = pcall(CreateFrame, "DropdownButton", name, parent, "WowStyle1DropdownTemplate")
    if ok and dd and dd.SetupMenu then
        dd:SetSize(width, height or 24)
        local initTxt = getTextFn()
        if dd.SetDefaultText then
            pcall(dd.SetDefaultText, dd, initTxt)
        end
        if dd.SetSelectionText then
            pcall(dd.SetSelectionText, dd, function()
                return getTextFn()
            end)
        end
        pcall(dd.SetupMenu, dd, function(_, root)
            buildMenuFn(root)
        end)
        dd._scLastLabelText = initTxt
        function dd:RefreshDropdownLabel()
            local txt = getTextFn()
            if self._scLastLabelText == txt then
                return
            end
            self._scLastLabelText = txt
            if self.SetDefaultText then
                pcall(self.SetDefaultText, self, txt)
            end
            -- Never invoke GenerateMenu() during label sync: rebuilding Blizzard Menu trees & closures on every data refresh causes multi-MB heap growth.
            if self.OverrideText then
                pcall(self.OverrideText, self, txt)
            elseif self.Text and self.Text.SetText then
                self.Text:SetText(txt)
            end
        end
        return dd
    end

    local btn = CreateFrame("Button", name, parent, "BackdropTemplate")
    btn:SetSize(width, height or 22)
    Theme:ApplyBackdrop(btn, "inset")
    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", btn, "LEFT", 8, 0)
    lbl:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    btn._label = lbl

    local arrow = btn:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(16, 16)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -3, 0)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")

    btn:SetScript("OnClick", function(selfBtn)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                buildMenuFn(root)
            end)
        end
    end)
    function btn:RefreshDropdownLabel()
        local txt = getTextFn()
        if self._scLastLabelText == txt then
            return
        end
        self._scLastLabelText = txt
        self._label:SetText(txt)
    end
    btn:RefreshDropdownLabel()
    return btn
end

local function OpenBulletinHeaderMenu(anchor, headerItem)
    if not (MenuUtil and MenuUtil.CreateContextMenu and headerItem) then return end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        local lbl = headerItem.bucketLabel or L["Dungeon"]
        root:CreateTitle(lbl)
        if not headerItem.isSectionHeader then
            local isW = LFGFrameTab:IsActivityWatched(headerItem.bucketKey, lbl)
            root:CreateButton(isW and ("|cff3fb950[x]|r " .. L["Watch This Dungeon in Official Chat"]) or L["Watch This Dungeon in Official Chat"], function()
                LFGFrameTab:ToggleActivityWatched(headerItem.bucketKey, lbl)
            end)
            root:CreateButton(L["Filter Only This Activity"], function()
                LFGFrameTab._hasSearchedThisSession = true
                local applied = false
                for _, catId in ipairs(CANONICAL_SEARCH_ORDER) do
                    local opts = GetBrowseActivityOptions(catId)
                    for i = 1, #opts do
                        if opts[i].key == headerItem.bucketKey then
                            LFGFrameTab.categoryFilter = catId
                            wipe(LFGFrameTab.browseActivityFilter)
                            LFGFrameTab.browseActivityFilter[opts[i].key] = opts[i]
                            applied = true
                            break
                        end
                    end
                    if applied then break end
                end
                if not applied then
                    LFGFrameTab.query = lbl
                    if LFGFrameTab.controls and LFGFrameTab.controls.searchBox then
                        LFGFrameTab.controls.searchBox:SetText(lbl)
                    end
                end
                LFGFrameTab.collapsedBuckets[headerItem.bucketKey] = nil
                LFGFrameTab:SaveBrowseFilters()
                LFGFrameTab:TriggerOfficialBrowseSearch(true)
                LFGFrameTab:RefreshData()
                ns:Emit("LFG_BROWSE_STATE_CHANGED")
            end)
        end
        root:CreateButton(headerItem.isCollapsed and L["Expand Section"] or L["Collapse Section"], function()
            LFGFrameTab.collapsedBuckets[headerItem.bucketKey] = not LFGFrameTab.collapsedBuckets[headerItem.bucketKey]
            LFGFrameTab:RefreshData()
            ns:Emit("LFG_BROWSE_STATE_CHANGED")
        end)
        root:CreateDivider()
        root:CreateButton(L["Expand All Sections"], function()
            wipe(LFGFrameTab.collapsedBuckets)
            LFGFrameTab:RefreshData()
            ns:Emit("LFG_BROWSE_STATE_CHANGED")
        end)
        root:CreateButton(L["Collapse All Sections"], function()
            local rowsSrc = nil
            if LFGFrameTab.subPanel and LFGFrameTab.subPanel:IsShown() and LFGFrameTab.list and type(LFGFrameTab.list.items) == "table" then
                rowsSrc = LFGFrameTab.list.items
            elseif LFGFrameTab.GetSharedBrowseData then
                rowsSrc = LFGFrameTab:GetSharedBrowseData()
            end
            if type(rowsSrc) == "table" then
                for _, rowItem in ipairs(rowsSrc) do
                    if rowItem and rowItem._isBulletinHeader and rowItem.bucketKey then
                        LFGFrameTab.collapsedBuckets[rowItem.bucketKey] = true
                    end
                end
            end
            LFGFrameTab:RefreshData()
            ns:Emit("LFG_BROWSE_STATE_CHANGED")
        end)
        if LFGFrameTab:GetWatchedActivitiesCount() > 0 then
            root:CreateDivider()
            root:CreateButton(L["Clear All Watchers"], function()
                LFGFrameTab:ConfirmClearWatchedActivities()
            end)
        end
    end)
end

local function OpenLfgRowContextMenu(anchor, item)
    if not (MenuUtil and MenuUtil.CreateContextMenu and item) then return end
    if item._isBulletinHeader then
        OpenBulletinHeaderMenu(anchor, item)
        return
    end
    local targetName = item.displayName or item.lookupKey
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        if item.isSelf then
            root:CreateTitle((targetName or L["You"]) .. " (" .. L["You"] .. ")")
            root:CreateButton(L["Edit Listing"], function()
                LFGFrameTab:StartEditListing(item)
            end)
            root:CreateButton(L["Delete Listing"], function()
                if ns.Clan and ns.Clan.ClearMyLFG then
                    ns.Clan:ClearMyLFG(true)
                    ns:Print("%s", L["Your listing has been removed."])
                end
                LFGFrameTab:HandleOwnListingRemoved()
            end)
            return
        end
        if item.secretLeaderName ~= nil or item.isUnknownLeader == true then
            root:CreateTitle(item.activity or L["Official LFG"])
            root:CreateButton(L["Native LFG"], function()
                if LFGFrameTab.subPanel and LFGFrameTab.subPanel:IsShown() then
                    LFGFrameTab:HideSubPanel(true)
                elseif _G.LFGParentFrame and _G.LFGParentFrame:IsShown() then
                    if ns.UI and ns.UI.CloseEmbeddedIfHost then ns.UI:CloseEmbeddedIfHost(_G.LFGParentFrame) end
                else
                    ns:Print("%s", L["Press I to open Blizzard's Group Finder and apply directly on the official Browse tab."])
                end
            end)
            return
        end
        root:CreateTitle(targetName or L["Clan & Allied LFG"])
        if targetName then
            local canInviteLfg, invTarget, invBnetId, isCrossFac, bnetName = ResolveLfgInviteTarget(item)
            root:CreateButton(L["Whisper"], function()
                OpenPlayerWhisper(item)
            end)
            root:CreateButton(L["Quick Apply (/w)"], function()
                if ns.LFG and ns.LFG.MarkAsked then
                    ns.LFG:MarkAsked(item)
                end
                local draft = BuildLfgApplyDraft(item)
                if isCrossFac and bnetName and Compat.BNetWhisper then
                    Compat.BNetWhisper(bnetName, targetName, draft)
                elseif Compat.Whisper then
                    Compat.Whisper(targetName, draft)
                end
            end)
            if canInviteLfg then
                root:CreateButton(L["Invite to Group"], function()
                    if ns.LFG and ns.LFG.ExecuteRowAction and item.mode == "LFG" then
                        ns.LFG:ExecuteRowAction(item, true)
                    elseif Compat.Invite then
                        Compat.Invite(invTarget, invBnetId)
                    end
                end)
            end
            local bKey, bLbl = ResolveCanonicalActivityBucket(item)
            if bKey and bLbl then
                local isW = LFGFrameTab:IsActivityWatched(bKey, bLbl)
                root:CreateButton(isW and ("|cff3fb950[x]|r " .. L["Watch This Dungeon in Official Chat"]) or L["Watch This Dungeon in Official Chat"], function()
                    LFGFrameTab:ToggleActivityWatched(bKey, bLbl)
                end)
            end
            root:CreateButton(L["Edit Apply Whisper Template (/w)..."], function()
                LFGFrameTab:OpenWhisperTemplateModal()
            end)
            local isTracked = ns.Spotter and ns.Spotter.IsPlayerTracked and ns.Spotter:IsPlayerTracked(targetName, item.guid)
            if isTracked and ns.Spotter and ns.Spotter.UntrackPlayer then
                root:CreateButton(L["Untrack from Radar"], function()
                    ns.Spotter:UntrackPlayer(targetName, item.guid)
                end)
            else
                root:CreateButton(L["Track on Radar"], function()
                    if ns.Spotter and ns.Spotter.TrackPlayer then
                        local hintStance = item.isWatchlist and "WATCHLIST"
                            or (item.isFriend and "FRIEND")
                            or (item.isAllied and "ALLY")
                            or (item.isClan and "SAME")
                            or "WATCHLIST"
                        ns.Spotter:TrackPlayer(targetName, item.guild, item.classFile, item.level, item.guid, hintStance)
                    end
                end)
            end
            if not item.isWatchlist and ns.Watchlist and ns.Watchlist.Add then
                root:CreateButton(L["Add to Watchlist"], function()
                    ns.Watchlist:Add(targetName, item.activity or L["Clans & Allies LFG"])
                end)
            end
            root:CreateDivider()
            if ns.SocialPanels and ns.SocialPanels.OpenSocialMetaModal then
                root:CreateButton(L["Edit Social Card"], function()
                    ns.SocialPanels:OpenSocialMetaModal(targetName, item.lookupKey or targetName)
                end)
            end
            if Store and Store.SetSocialFlag then
                local curMeta = Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(item.lookupKey or targetName)
                local goodLbl = (curMeta and curMeta.flag == "GOOD") and ("|cff3fb950[x]|r " .. L["Good Partner (+)"]) or L["Good Partner (+)"]
                local avoidLbl = (curMeta and curMeta.flag == "AVOID") and ("|cffff4d4d[x]|r " .. L["Flag: Avoid"]) or L["Flag: Avoid"]
                root:CreateButton(goodLbl, function()
                    Store:SetSocialFlag(item.lookupKey or targetName, "GOOD")
                end)
                root:CreateButton(avoidLbl, function()
                    Store:SetSocialFlag(item.lookupKey or targetName, "AVOID")
                end)
            end
            if item.isOfficial or item.sourceType == "OFFICIAL_LFG" then
                root:CreateDivider()
                root:CreateButton(L["Native LFG"], function()
                    if LFGFrameTab.subPanel and LFGFrameTab.subPanel:IsShown() then
                        LFGFrameTab:HideSubPanel(true)
                    elseif _G.LFGParentFrame and _G.LFGParentFrame:IsShown() then
                        if ns.UI and ns.UI.CloseEmbeddedIfHost then ns.UI:CloseEmbeddedIfHost(_G.LFGParentFrame) end
                    else
                        ns:Print("%s", L["Press I to open Blizzard's Group Finder and apply directly on the official Browse tab."])
                    end
                end)
            end
        end
    end)
end

local function SyncRowSelectionVisuals()
    local list = LFGFrameTab.list
    if not (list and list.rows) then return end
    local selKey = LFGFrameTab.selectedKey
    for _, row in ipairs(list.rows) do
        if row and row.SelectedTex and row:IsShown() then
            if row._item and row._item._isBulletinHeader then
                row.SelectedTex:Hide()
            else
                local rowKey = GetItemIdentityKey(row._item)
                row.SelectedTex:SetShown(selKey ~= nil and rowKey == selKey)
            end
        end
    end
    LFGFrameTab:UpdateBottomButtons()
end

local function IsItemFullForBrowse(item, roleFilter)
    if not item or item.isSelf then
        return false
    end
    if item.mode ~= "LFM" or item.sourceType == "EVENT" then
        return false
    end
    local rf = roleFilter or "ALL"
    if rf == "ANY" then rf = "ALL" end
    if item.maxMembers and item.maxMembers > 0 and item.numMembers and item.numMembers >= item.maxMembers then
        return true
    end
    if (not item.maxMembers) and item.categoryKind == "DUNGEONS" and (item.numMembers or 0) >= 5 then
        return true
    end
    if item.needT == nil and item.needH == nil and item.needD == nil then
        return false
    end
    local nT = math.max(0, item.needT or 0)
    local nH = math.max(0, item.needH or 0)
    local nD = math.max(0, item.needD or 0)
    if nT == 0 and nH == 0 and nD == 0 then
        return true
    end
    if rf == "TANK" and nT == 0 then
        return true
    elseif rf == "HEALER" and nH == 0 then
        return true
    elseif rf == "DPS" and nD == 0 then
        return true
    elseif rf == "MINE" then
        local rec = (ns.Clan and ns.Clan.GetRecommendedRolesForCharacter) and ns.Clan:GetRecommendedRolesForCharacter() or nil
        local r = rec and rec.recommended
        if r then
            local canFit = (r.TANK == true and nT > 0) or (r.HEALER == true and nH > 0) or (r.DPS == true and nD > 0)
            if not canFit then
                return true
            end
        end
    end
    return false
end

local function BuildBulletinBoardRows(filteredRows, collapsedBuckets, pendingItem)
    local bucketsByKey = {}
    local bucketList = {}
    local collapsed = type(collapsedBuckets) == "table" and collapsedBuckets or {}
    for _, item in ipairs(filteredRows) do
        local bKey, bLabel, bMin, bMax, bCatOrd = ResolveCanonicalActivityBucket(item)
        if pendingItem and item == pendingItem and bKey then
            collapsed[bKey] = nil
        end
        local b = bucketsByKey[bKey]
        if not b then
            b = {
                bucketKey = bKey,
                bucketLabel = bLabel or L["Custom"],
                minLvl = bMin or 999,
                maxLvl = bMax or 999,
                catOrder = bCatOrd or 6,
                items = {},
                trustedCount = 0,
                watchCount = 0,
                clanCount = 0,
                allyCount = 0,
                enemyCount = 0,
                avoidCount = 0,
                needT = 0,
                needH = 0,
                needD = 0,
                selfHere = false,
                lockoutInfo = nil,
                isWatched = LFGFrameTab:IsActivityWatched(bKey, bLabel),
            }
            bucketsByKey[bKey] = b
            bucketList[#bucketList + 1] = b
        end
        b.items[#b.items + 1] = item
        if item.isSelf == true then
            b.selfHere = true
        end
        if not b.lockoutInfo and item._lockoutInfo then
            b.lockoutInfo = item._lockoutInfo
        end
        if item.isTrusted or item.sourceType == "CLAN" or item.sourceType == "ALLY" or item.sourceType == "FRIEND" or item.sourceType == "EVENT" or item._isGoodFlag then
            b.trustedCount = b.trustedCount + 1
        end
        if item.isWatchlist or item.hasFriendOrWatchlistSignup then
            b.watchCount = b.watchCount + 1
        end
        if item.isClan then
            b.clanCount = b.clanCount + 1
        end
        if item.isAllied then
            b.allyCount = b.allyCount + 1
        end
        if item.isEnemyGuild then
            b.enemyCount = b.enemyCount + 1
        end
        local itemAvoidMeta = (not item.hasAvoidSignup and not item._isAvoidFlag and Store)
            and ((Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(item.lookupKey or item.displayName))
                or (Store.GetSocialMeta and Store:GetSocialMeta(item.lookupKey or item.displayName))) or nil
        if item._isAvoidFlag or item.hasAvoidSignup or (itemAvoidMeta and itemAvoidMeta.flag == "AVOID") then
            b.avoidCount = b.avoidCount + 1
        end
        if item.mode == "LFM" and item.sourceType ~= "EVENT" then
            b.needT = b.needT + math.max(0, item.needT or 0)
            b.needH = b.needH + math.max(0, item.needH or 0)
            b.needD = b.needD + math.max(0, item.needD or 0)
        end
    end

    table.sort(bucketList, function(a, b)
        if a.selfHere ~= b.selfHere then return a.selfHere end
        if a.isWatched ~= b.isWatched then return a.isWatched end
        if a.catOrder ~= b.catOrder then return a.catOrder < b.catOrder end
        if a.minLvl ~= b.minLvl then return a.minLvl < b.minLvl end
        return tostring(a.bucketLabel or "") < tostring(b.bucketLabel or "")
    end)

    local out = {}
    for bi = 1, #bucketList do
        local b = bucketList[bi]
        local isCollapsed = (collapsed[b.bucketKey] == true)
        out[#out + 1] = {
            _isBulletinHeader = true,
            bucketKey = b.bucketKey,
            bucketLabel = b.bucketLabel,
            minLvl = b.minLvl,
            maxLvl = b.maxLvl,
            catOrder = b.catOrder,
            groupCount = #b.items,
            trustedCount = b.trustedCount,
            watchCount = b.watchCount,
            clanCount = b.clanCount,
            allyCount = b.allyCount,
            enemyCount = b.enemyCount,
            avoidCount = b.avoidCount,
            needT = b.needT,
            needH = b.needH,
            needD = b.needD,
            isWatched = b.isWatched,
            isCollapsed = isCollapsed,
            _lockoutInfo = b.lockoutInfo,
        }
        if not isCollapsed then
            for ii = 1, #b.items do
                out[#out + 1] = b.items[ii]
            end
        end
    end
    return out
end

local function BuildGroupedTypeSectionRows(filteredRows, collapsedBuckets, pendingItem)
    local groupItems, playerItems = {}, {}
    local needT, needH, needD = 0, 0, 0
    local collapsed = type(collapsedBuckets) == "table" and collapsedBuckets or {}
    for _, item in ipairs(filteredRows) do
        if item.mode == "LFG" and item.sourceType ~= "EVENT" then
            playerItems[#playerItems + 1] = item
            if pendingItem and item == pendingItem then
                collapsed["__sec_players"] = nil
            end
        else
            groupItems[#groupItems + 1] = item
            needT = needT + math.max(0, item.needT or 0)
            needH = needH + math.max(0, item.needH or 0)
            needD = needD + math.max(0, item.needD or 0)
            if pendingItem and item == pendingItem then
                collapsed["__sec_groups"] = nil
            end
        end
    end
    local out = {}
    if #groupItems > 0 then
        local isCol = (collapsed["__sec_groups"] == true)
        out[#out + 1] = {
            _isBulletinHeader = true,
            isSectionHeader = true,
            sectionKind = "GROUPS",
            bucketKey = "__sec_groups",
            bucketLabel = L["Groups"],
            groupCount = #groupItems,
            needT = needT,
            needH = needH,
            needD = needD,
            isCollapsed = isCol,
        }
        if not isCol then
            for i = 1, #groupItems do out[#out + 1] = groupItems[i] end
        end
    end
    if #playerItems > 0 then
        local isCol = (collapsed["__sec_players"] == true)
        out[#out + 1] = {
            _isBulletinHeader = true,
            isSectionHeader = true,
            sectionKind = "PLAYERS",
            bucketKey = "__sec_players",
            bucketLabel = L["Players Looking"],
            groupCount = #playerItems,
            isCollapsed = isCol,
        }
        if not isCol then
            for i = 1, #playerItems do out[#out + 1] = playerItems[i] end
        end
    end
    return out
end

local function AppendLfgMembersTooltip(tooltip, it)
    if not (tooltip and type(it) == "table") then return end
    if it.guildMemberNames and it.guildMemberNames ~= "" then
        tooltip:AddLine(L["Guild in group"] .. ": " .. it.guildMemberNames, 1.0, 0.82, 0.25, true)
    elseif (it.numGuildMates or 0) > 0 then
        tooltip:AddLine(L["Guild in group"] .. ": " .. tostring(it.numGuildMates), 1.0, 0.82, 0.25)
    end
    if it.alliedMemberNames and it.alliedMemberNames ~= "" then
        tooltip:AddLine(L["Allies in group"] .. ": " .. it.alliedMemberNames, 0.30, 0.92, 0.52, true)
    end
    if it.friendMemberNames and it.friendMemberNames ~= "" then
        tooltip:AddLine(L["Friends in group"] .. ": " .. it.friendMemberNames, 0.45, 0.82, 1.0, true)
    elseif ((it.numBNetFriends or 0) + (it.numCharFriends or 0)) > 0 then
        tooltip:AddLine(L["Friends in group"] .. ": " .. tostring((it.numBNetFriends or 0) + (it.numCharFriends or 0)), 0.45, 0.82, 1.0)
    end
    local wNames = (it.watchlistMemberNames and it.watchlistMemberNames ~= "") and it.watchlistMemberNames or it.friendOrWatchlistNames
    if wNames and wNames ~= "" then
        tooltip:AddLine(L["In group"] .. ": " .. wNames, 1.0, 0.72, 0.30, true)
    end
    if it.hasGoodPartnerSignup and it.goodPartnerNames and it.goodPartnerNames ~= "" then
        tooltip:AddLine(L["Good Partner (+)"] .. ": " .. it.goodPartnerNames, 0.25, 0.92, 0.50, true)
    end
    if it.hasAvoidSignup and it.avoidSignupNames and it.avoidSignupNames ~= "" then
        tooltip:AddLine(L["Avoid in group"] .. ": " .. it.avoidSignupNames, 1.0, 0.35, 0.35, true)
    end
    if it.enemyGuildNames and it.enemyGuildNames ~= "" then
        tooltip:AddLine(L["Enemy guild in group"] .. ": " .. it.enemyGuildNames, 1.0, 0.32, 0.32, true)
    end
    if it.newPlayerFriendly then
        tooltip:AddLine(L["New Player Friendly"], 0.28, 0.95, 0.42)
    end
    if type(it.members) == "table" and #it.members > 0 then
        tooltip:AddLine(" ")
        tooltip:AddLine(L["Group Members"] .. ":", 0.86, 0.78, 0.52)
        for mi = 1, math.min(#it.members, 12) do
            local m = it.members[mi]
            if type(m) == "table" and m.name then
                local hex = (Compat.ClassHex and m.classFile and Compat.ClassHex(m.classFile)) or "|cffe8ecf2"
                local leadStr = m.isLeader and "|cffffd200*|r " or ""
                local lvlStr = (m.level and m.level > 0) and (" " .. L["Lv %d"]:format(m.level)) or ""
                local rTag = ""
                if m.role == "TANK" then rTag = " [T]"
                elseif m.role == "HEALER" then rTag = " [H]"
                elseif m.role == "DAMAGER" or m.role == "DPS" then rTag = " [D]" end
                local sTag = m.tag and (" |cffffd24d[" .. m.tag .. "]|r") or ""
                tooltip:AddLine(string.format("  %s%s%s|r|cff9aa6b8%s%s|r%s", leadStr, hex, m.name, lvlStr, rTag, sTag), 0.92, 0.94, 0.98)
            end
        end
    end
end

local ROLE_ATLAS_CANDIDATES = {
    TANK = { "groupfinder-icon-role-large-tank", "groupfinder-icon-role-styled-tank" },
    HEALER = { "groupfinder-icon-role-large-heal", "groupfinder-icon-role-large-healer", "groupfinder-icon-role-styled-healer" },
    DPS = { "groupfinder-icon-role-large-dps", "groupfinder-icon-role-styled-dps" },
}

local function SetRoleSlotTexture(tex, roleId, fallbackTex)
    if not tex then return end
    local candidates = ROLE_ATLAS_CANDIDATES[roleId]
    if candidates then
        for _, atlasName in ipairs(candidates) do
            if HasAtlas(atlasName) then
                tex:SetAtlas(atlasName, false)
                tex:SetTexCoord(0, 1, 0, 1)
                return
            end
        end
    end
    tex:SetTexture(fallbackTex or "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
    if roleId == "TANK" then
        tex:SetTexCoord(2 / 64, 17 / 64, 24 / 64, 39 / 64)
    elseif roleId == "HEALER" then
        tex:SetTexCoord(22 / 64, 37 / 64, 3 / 64, 18 / 64)
    else
        tex:SetTexCoord(22 / 64, 37 / 64, 24 / 64, 39 / 64)
    end
end

local function CreateLfgRow(parent)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(68)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    if HasAtlas("groupfinder-highlightbar") then
        local bgTex = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        bgTex:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -2)
        bgTex:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 0)
        bgTex:SetAtlas("groupfinder-highlightbar", false)
        row.nativeBgTex = bgTex
    elseif HasAtlas("common-button-list-large") then
        local bgTex = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        bgTex:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -2)
        bgTex:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 0)
        bgTex:SetAtlas("common-button-list-large", false)
        row.nativeBgTex = bgTex
    end

    row.SelfTex = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.SelfTex:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -3)
    row.SelfTex:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 1)
    if HasAtlas("groupfinder-highlightbar-green") then
        row.SelfTex:SetAtlas("groupfinder-highlightbar-green", false)
        row.SelfTex:SetAlpha(0.32)
    else
        row.SelfTex:SetColorTexture(0.18, 0.72, 0.36, 0.14)
    end
    row.SelfTex:Hide()

    row.headerAccentTex = row:CreateTexture(nil, "BACKGROUND", nil, 3)
    row.headerAccentTex:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -3)
    row.headerAccentTex:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 1)
    row.headerAccentTex:SetColorTexture(0.20, 0.15, 0.08, 0.90)
    row.headerAccentTex:Hide()

    row.relStripe = row:CreateTexture(nil, "OVERLAY", nil, 3)
    row.relStripe:SetWidth(3)
    row.relStripe:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -2)
    row.relStripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 2)
    row.relStripe:Hide()

    row.SelectedTex = row:CreateTexture(nil, "OVERLAY", nil, 2)
    row.SelectedTex:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -3)
    row.SelectedTex:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 1)
    if HasAtlas("groupfinder-highlightbar-yellow") then
        row.SelectedTex:SetAtlas("groupfinder-highlightbar-yellow", false)
        row.SelectedTex:SetBlendMode("ADD")
    else
        row.SelectedTex:SetColorTexture(1.0, 0.82, 0.15, 0.28)
    end
    row.SelectedTex:Hide()

    if row.SelectedTex then
        row.SelectedTex:SetDrawLayer("OVERLAY", 2)
    end
    row.zebraTex = row:CreateTexture(nil, "BACKGROUND", nil, 0)
    row.zebraTex:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -2)
    row.zebraTex:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 1)
    row.zebraTex:SetColorTexture(0.11, 0.10, 0.09, 0.24)
    row.zebraTex:Hide()

    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -3)
    row.hl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 1)
    if HasAtlas("groupfinder-highlightbar-blue") then
        row.hl:SetAtlas("groupfinder-highlightbar-blue", false)
        row.hl:SetBlendMode("ADD")
    else
        row.hl:SetColorTexture(0.35, 0.72, 1.0, 0.22)
    end

    row.partyIcon = row:CreateTexture(nil, "ARTWORK")
    row.partyIcon:SetSize(19, 19)
    row.partyIcon:SetPoint("TOPLEFT", row, "TOPLEFT", 9, -8)
    if HasAtlas("groupfinder-icon-leader") then
        row.partyIcon:SetAtlas("groupfinder-icon-leader", false)
    else
        row.partyIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    end

    row.nameFs = row:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    row.nameFs:SetPoint("TOPLEFT", row, "TOPLEFT", 31, -8)
    row.nameFs:SetJustifyH("LEFT")
    row.nameFs:SetWordWrap(false)

    row.levelFs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.levelFs:SetPoint("BOTTOMLEFT", row.nameFs, "BOTTOMRIGHT", 6, 1)
    row.levelFs:SetJustifyH("LEFT")
    row.levelFs:SetWordWrap(false)
    row.levelFs:SetTextColor(0.86, 0.90, 0.95, 1)

    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetSize(20, 20)
    row.classIcon:SetPoint("LEFT", row.levelFs, "RIGHT", 5, 0)
    row.classIcon:Hide()

    row.infoBadges = {}
    for bi = 1, 6 do
        local bf = CreateFrame("Frame", nil, row)
        bf:SetSize(15, 15)
        bf:SetFrameLevel((row:GetFrameLevel() or 2) + 2)
        bf:EnableMouse(true)
        if bf.SetMouseClickEnabled then
            pcall(bf.SetMouseClickEnabled, bf, false)
        else
            bf:SetScript("OnMouseUp", function(_, btn)
                local onClick = row:GetScript("OnClick")
                if onClick then onClick(row, btn) end
            end)
        end
        local bTex = bf:CreateTexture(nil, "ARTWORK", nil, 4)
        bTex:SetAllPoints(bf)
        bf.tex = bTex
        bf:SetScript("OnEnter", function(selfBadge)
            if not selfBadge._tipTitle then return end
            GameTooltip:SetOwner(selfBadge, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            local tc = selfBadge._tipColor or { 1.0, 0.82, 0.25 }
            GameTooltip:SetText(selfBadge._tipTitle, tc[1], tc[2], tc[3])
            if selfBadge._tipDesc and selfBadge._tipDesc ~= "" then
                GameTooltip:AddLine(selfBadge._tipDesc, 0.90, 0.92, 0.96, true)
            end
            GameTooltip:Show()
        end)
        bf:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        bf:Hide()
        row.infoBadges[bi] = bf
    end

    row.badgeFs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.badgeFs:SetPoint("LEFT", row.classIcon, "RIGHT", 4, 0)
    row.badgeFs:SetPoint("RIGHT", row, "RIGHT", -110, 0)
    row.badgeFs:SetJustifyH("LEFT")
    row.badgeFs:SetWordWrap(false)

    -- Rightmost 1-click row action button (Ask-to-Join + green check / Invite / Delist)
    row.actionBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
    row.actionBtn:SetSize(32, 32)
    row.actionBtn:SetFrameLevel((row:GetFrameLevel() or 2) + 3)
    row.actionBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(row.actionBtn, "inset")
    end
    local actHl = row.actionBtn:CreateTexture(nil, "HIGHLIGHT")
    actHl:SetAllPoints()
    actHl:SetColorTexture(1.0, 0.85, 0.25, 0.24)
    local actIcon = row.actionBtn:CreateTexture(nil, "ARTWORK")
    actIcon:SetSize(20, 20)
    actIcon:SetPoint("CENTER")
    row.actionBtn.Icon = actIcon
    local actCheck = row.actionBtn:CreateTexture(nil, "OVERLAY")
    actCheck:SetSize(14, 14)
    actCheck:SetPoint("BOTTOMRIGHT", row.actionBtn, "BOTTOMRIGHT", 2, -2)
    if HasAtlas("groupfinder-icon-greencheckmark") then
        actCheck:SetAtlas("groupfinder-icon-greencheckmark", false)
    else
        actCheck:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    end
    actCheck:Hide()
    row.actionBtn.Check = actCheck
    row.actionBtn:SetScript("OnClick", function(selfBtn)
        local r = selfBtn:GetParent()
        local it = r and r._item
        if not it or it._isBulletinHeader then return end
        if it.secretLeaderName ~= nil or it.isUnknownLeader == true then
            if LFGFrameTab.subPanel and LFGFrameTab.subPanel:IsShown() then
                LFGFrameTab:HideSubPanel(true)
            elseif _G.LFGParentFrame and _G.LFGParentFrame:IsShown() then
                if ns.UI and ns.UI.CloseEmbeddedIfHost then ns.UI:CloseEmbeddedIfHost(_G.LFGParentFrame) end
            else
                ns:Print("%s", L["Press I to open Blizzard's Group Finder and apply directly on the official Browse tab."])
            end
            return
        end
        if ns.LFG and ns.LFG.ExecuteRowAction then
            ns.LFG:ExecuteRowAction(it, true)
            LFGFrameTab:RefreshData()
            ns:Emit("LFG_BROWSE_STATE_CHANGED")
        end
    end)
    row.actionBtn:SetScript("OnEnter", function(selfBtn)
        local r = selfBtn:GetParent()
        local it = r and r._item
        if not it then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if it.isSelf then
            GameTooltip:SetText(L["Delist Listing"], 1.0, 0.35, 0.35)
        elseif it.secretLeaderName ~= nil or it.isUnknownLeader == true then
            GameTooltip:SetText(L["Open Official LFG Window"], 1.0, 0.82, 0.25)
        elseif it.mode == "LFG" and it.sourceType ~= "EVENT" then
            GameTooltip:SetText(L["Invite to Group"], 0.35, 0.92, 0.50)
            if ns.db and ns.db.settings and ns.db.settings.lfgInviteAutoWhisper ~= false then
                GameTooltip:AddLine(L["Invites and sends your invite whisper template."], 0.85, 0.90, 0.95, true)
            end
        elseif ns.LFG and ns.LFG.IsAsked and ns.LFG:IsAsked(it) then
            GameTooltip:SetText(L["Asked to Join"], 0.35, 0.92, 0.50)
            GameTooltip:AddLine(L["You already whispered this group in this session. Click to message again."], 0.85, 0.90, 0.95, true)
        else
            GameTooltip:SetText(L["Ask to Join (/w)"], 1.0, 0.85, 0.25)
            GameTooltip:AddLine(L["Sends or prepares your Apply Whisper Template right now."], 0.85, 0.90, 0.95, true)
        end
        GameTooltip:Show()
    end)
    row.actionBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Right-aligned native Role Slot Pool (Line 1, fixed grid centers left of actionBtn)
    row.roleIcons = {}
    for ri = 5, 1, -1 do
        local ico = row:CreateTexture(nil, "ARTWORK")
        ico:SetSize(24, 24)
        ico:SetPoint("CENTER", row.actionBtn, "LEFT", -16 - ((5 - ri) * 24), 19)
        row.roleIcons[ri] = ico
    end
    row.tankIcon = row.roleIcons[1]
    row.healerIcon = row.roleIcons[2]
    row.dpsIcon = row.roleIcons[5]

    -- Right-aligned Member Class Icons (Line 3 right side, left of actionBtn)
    row.memberClassIcons = {}
    local prevClsIcon = nil
    for ci = 1, 5 do
        local cIco = row:CreateTexture(nil, "ARTWORK")
        cIco:SetSize(18, 18)
        if not prevClsIcon then
            cIco:SetPoint("RIGHT", row.actionBtn, "LEFT", -6, -20)
        else
            cIco:SetPoint("RIGHT", prevClsIcon, "LEFT", -3, 0)
        end
        cIco:Hide()
        row.memberClassIcons[ci] = cIco
        prevClsIcon = cIco
    end

    row.activityFs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    if row.activityFs.SetFontObject and _G.GameFontHighlightMedium then
        row.activityFs:SetFontObject(_G.GameFontHighlightMedium)
    end
    row.activityFs:SetPoint("TOPLEFT", row.nameFs, "BOTTOMLEFT", 0, -7)
    row.activityFs:SetPoint("RIGHT", row.actionBtn, "LEFT", -8, 0)
    row.activityFs:SetJustifyH("LEFT")
    row.activityFs:SetWordWrap(false)

    row.metaFs = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.metaFs:SetPoint("TOPLEFT", row.activityFs, "BOTTOMLEFT", 0, -4)
    row.metaFs:SetPoint("RIGHT", row.actionBtn, "LEFT", -8, 0)
    row.metaFs:SetJustifyH("LEFT")
    row.metaFs:SetWordWrap(false)

    row:SetScript("OnClick", function(selfRow, btn)
        local it = selfRow._item
        if not it then return end
        if it._isBulletinHeader then
            if btn == "RightButton" then
                OpenBulletinHeaderMenu(selfRow, it)
            else
                LFGFrameTab.collapsedBuckets[it.bucketKey] = not LFGFrameTab.collapsedBuckets[it.bucketKey]
                LFGFrameTab:RefreshData()
                ns:Emit("LFG_BROWSE_STATE_CHANGED")
            end
            return
        end
        LFGFrameTab.selectedKey = GetItemIdentityKey(it)
        LFGFrameTab.selectedItem = it
        SyncRowSelectionVisuals()
        local scParent = selfRow:GetParent()
        if scParent and scParent.GetChildren then
            local function SyncSib(sibling)
                if sibling and sibling._item and sibling.SelectedTex then
                    sibling.SelectedTex:SetShown(GetItemIdentityKey(sibling._item) == LFGFrameTab.selectedKey)
                end
            end
            if Compat and Compat.ForEachChild then
                Compat.ForEachChild(scParent, SyncSib)
            else
                local function LoopSib(n, ...)
                    for i = 1, n do SyncSib(select(i, ...)) end
                end
                LoopSib(select("#", scParent:GetChildren()), scParent:GetChildren())
            end
        end
        LFGFrameTab:UpdateBottomButtons()
        if btn == "RightButton" then
            OpenLfgRowContextMenu(selfRow, it)
        end
    end)

    row:SetScript("OnDoubleClick", function(selfRow, btn)
        if btn ~= "LeftButton" then return end
        local it = selfRow._item
        if not it or it._isBulletinHeader then return end
        if it.isSelf then
            LFGFrameTab:StartEditListing(it)
            return
        end
        if it.secretLeaderName ~= nil or it.isUnknownLeader == true then
            if LFGFrameTab.subPanel and LFGFrameTab.subPanel:IsShown() then
                LFGFrameTab:HideSubPanel(true)
            elseif _G.LFGParentFrame and _G.LFGParentFrame:IsShown() then
                if ns.UI and ns.UI.CloseEmbeddedIfHost then ns.UI:CloseEmbeddedIfHost(_G.LFGParentFrame) end
            else
                ns:Print("%s", L["Press I to open Blizzard's Group Finder and apply directly on the official Browse tab."])
            end
            return
        end
        OpenPlayerWhisper(it)
    end)

    row:SetScript("OnEnter", function(selfRow)
        local it = selfRow._item
        if not it then return end
        if it._isBulletinHeader then
            GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            local lvlSpan = (it.minLvl and it.minLvl < 900 and it.maxLvl and it.maxLvl < 900)
                and string.format(" [%d-%d]", it.minLvl, it.maxLvl) or ""
            GameTooltip:AddLine((it.bucketLabel or L["Dungeon"]) .. lvlSpan, 1.0, 0.82, 0.25)
            local gLbl = (it.groupCount == 1) and L["%d group"]:format(1) or L["%d groups"]:format(it.groupCount or 0)
            GameTooltip:AddLine(gLbl, 0.35, 0.90, 0.55)
            if (it.needT or 0) > 0 or (it.needH or 0) > 0 or (it.needD or 0) > 0 then
                GameTooltip:AddLine(string.format("%s: %d %s · %d %s · %d %s", L["Open Slots"], it.needT or 0, L["Tank"], it.needH or 0, L["Healer"], it.needD or 0, L["DPS"]), 0.85, 0.90, 0.96)
            end
            if it.isWatched then
                GameTooltip:AddLine(L["Watched in Official Chat — matching groups print clickable alerts directly in chat."], 0.35, 0.92, 0.55, true)
            end
            if it._lockoutInfo then
                local lk = it._lockoutInfo
                local prog = (lk.numEncounters and lk.numEncounters > 0) and string.format("%d/%d", lk.encounterProgress or 0, lk.numEncounters) or L["Saved"]
                GameTooltip:AddLine(string.format(L["Saved Lockout: %s (%s · %s)"], lk.name or "?", prog, ""), 1.0, 0.62, 0.24, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Click: Expand / Collapse  |  Right-click: Watch in Chat"], 0.65, 0.72, 0.80, true)
            GameTooltip:Show()
            return
        end
        GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if it.secretLeaderName ~= nil then
            GameTooltip:AddLine(it.secretLeaderName, 1, 1, 1)
        else
            local cHex = (Compat.ClassHex and it.classFile and Compat.ClassHex(it.classFile)) or "|cffffd200"
            local lvlSuffix = (it.level and it.level > 0) and (" |cffb8c0cc" .. L["Lv %d"]:format(it.level) .. "|r") or ""
            GameTooltip:AddLine(cHex .. (it.displayName or "?") .. "|r" .. lvlSuffix, 1, 1, 1)
        end
        if it.guild and it.guild ~= "" then
            GameTooltip:AddLine("<" .. it.guild .. ">", 0.55, 0.85, 1.0)
        end
        local tags = {}
        local tipMeta = Store and ((Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(it.lookupKey or it.displayName))
            or (Store.GetSocialMeta and Store:GetSocialMeta(it.lookupKey or it.displayName))) or nil
        if (tipMeta and tipMeta.flag == "AVOID") or it._isAvoidFlag or it.hasAvoidSignup then
            tags[#tags + 1] = L["AVOID"]
        end
        if it.isEnemyGuild then tags[#tags + 1] = L["Enemy Guild"] end
        if it.isWatchlist or it.hasFriendOrWatchlistSignup then tags[#tags + 1] = L["WATCHLIST"] end
        if it.isFriend then tags[#tags + 1] = L["FRIEND"] end
        if it.isAllied then tags[#tags + 1] = L["Allied Guild"] elseif it.isClan then tags[#tags + 1] = L["Guild Member"] end
        if it.sourceType == "PUBLIC_CHAT" then tags[#tags + 1] = L["Global Chat"] end
        if it.hasAddon then tags[#tags + 1] = "SocialCentral [SC]" end
        if #tags > 0 then
            GameTooltip:AddLine(table.concat(tags, " · "), 1.0, 0.82, 0.25, true)
        end
        if it.activityAllNames and it.activityAllNames ~= "" and it.activityAllNames ~= it.activity then
            GameTooltip:AddLine(it.activityAllNames, 0.35, 0.90, 0.55, true)
        elseif it.activity and it.activity ~= "" then
            GameTooltip:AddLine(it.activity, 0.35, 0.90, 0.55, true)
        end
        if it.numMembers and it.numMembers > 0 then
            local mTxt = (it.maxMembers and it.maxMembers > 0)
                and string.format(L["Members: %d/%d"], it.numMembers, it.maxMembers)
                or string.format(L["Members: %d"], it.numMembers)
            if it.needT ~= nil or it.needH ~= nil or it.needD ~= nil then
                local needParts = {}
                if (it.needT or 0) > 0 then needParts[#needParts + 1] = string.format("%d %s", it.needT, L["Tank"]) end
                if (it.needH or 0) > 0 then needParts[#needParts + 1] = string.format("%d %s", it.needH, L["Healer"]) end
                if (it.needD or 0) > 0 then needParts[#needParts + 1] = string.format("%d %s", it.needD, L["DPS"]) end
                if #needParts > 0 then
                    mTxt = mTxt .. "  ·  " .. table.concat(needParts, ", ")
                end
            end
            GameTooltip:AddLine(mTxt, 0.85, 0.90, 0.98)
        end
        if it.note and it.note ~= "" then
            GameTooltip:AddLine(it.note, 0.85, 0.85, 0.85, true)
        end
        if it.voiceChat and it.voiceChat ~= "" then
            GameTooltip:AddLine(string.format("%s: %s", _G.VOICE_CHAT or L["Voice Chat"], it.voiceChat), 0.85, 0.88, 0.94, true)
        end
        if it.ilvl and it.ilvl > 0 then
            GameTooltip:AddLine(L["Item Level: %d"]:format(it.ilvl), 1.0, 0.85, 0.35)
        end
        if it.area and it.area ~= "" and it.mode == "LFG" then
            GameTooltip:AddLine(L["Location"] .. ": " .. it.area, 0.72, 0.84, 0.96)
        end
        if it.playstyleLabel and it.playstyleLabel ~= "" then
            GameTooltip:AddLine(L["Playstyle"] .. ": " .. it.playstyleLabel, 0.78, 0.84, 0.90)
        end
        AppendLfgMembersTooltip(GameTooltip, it)
        if it._idealLevel then
            GameTooltip:AddLine(L["Suitable for your level"], 0.25, 0.92, 0.50)
        end
        if it._lockoutInfo then
            local lk = it._lockoutInfo
            local prog = (lk.numEncounters and lk.numEncounters > 0) and string.format("%d/%d", lk.encounterProgress or 0, lk.numEncounters) or L["Saved"]
            local resetStr = (Compat.FormatDurationShort and Compat.FormatDurationShort(lk.reset or 0)) or ""
            GameTooltip:AddLine(string.format(L["Saved Lockout: %s (%s · %s)"], lk.name or "?", prog, resetStr), 1.0, 0.62, 0.24, true)
        end
        if it.isCompanion then
            GameTooltip:AddLine(L["Recent companion (%d runs)"]:format(it.companionRuns or 1), 0.43, 0.76, 0.90, true)
        end
        GameTooltip:AddLine(L["Double-click: Whisper  |  Right-click: More actions"], 0.60, 0.66, 0.74)
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

local TC_FULL = { 0, 1, 0, 1 }
local TC_FRIEND = { 0.12, 0.88, 0.12, 0.88 }
local TC_FLAG = { 0.15, 0.85, 0.10, 0.90 }
local TINT_CLAN = { 1.0, 0.82, 0.25 }
local TINT_ALLY = { 0.30, 0.92, 0.52 }
local TINT_FRIEND = { 0.45, 0.82, 1.0 }
local TINT_WATCH = { 1.0, 0.72, 0.25 }
local TINT_GOOD = { 0.25, 0.95, 0.50 }
local TINT_AVOID = { 1.0, 0.30, 0.30 }
local TINT_AVOID_TIP = { 1.0, 0.35, 0.35 }
local TINT_GUIDE = { 0.28, 0.95, 0.42 }
local TINT_WHITE = { 1.0, 1.0, 1.0 }
local TINT_SC_TIP = { 0.35, 0.90, 0.55 }

local lfgBadgePool = { {}, {}, {}, {}, {}, {} }
local lfgSoloListScratch = {}
local lfgRaidSlots = { "TANK", "HEALER", "DPS" }
local lfgSlotRoles = { "TANK", "HEALER", "DPS", "DPS", "DPS" }
local lfgSlotFilledScratch = { false, false, false, false, false }
local lfgFillPriorityOrder = { 3, 4, 5, 1, 2 }

local function PushBadgeSpec(count, atlas, tex, tc, tint, title, desc, tipColor)
    if count >= 6 then return count end
    local idx = count + 1
    local slot = lfgBadgePool[idx]
    slot.atlas = atlas
    slot.tex = tex
    slot.tc = tc
    slot.tint = tint
    slot.title = title
    slot.desc = desc
    slot.tipColor = tipColor
    return idx
end

local function BuildLfgRowBadgeSpecs(item, sMeta)
    local cnt = 0
    local gGuildDesc = (item.guild and item.guild ~= "") and ("<" .. item.guild .. ">") or ""
    if (sMeta and sMeta.flag == "AVOID") or item._isAvoidFlag or item.hasAvoidSignup then
        local avDesc = (item.avoidSignupNames and item.avoidSignupNames ~= "") and item.avoidSignupNames
            or (item.displayName or "")
        cnt = PushBadgeSpec(cnt, nil, "Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull", TC_FULL, TINT_AVOID, L["Avoid Warning"], avDesc, TINT_AVOID_TIP)
    end
    if item.isEnemyGuild then
        local egDesc = (item.enemyGuildNames and item.enemyGuildNames ~= "") and item.enemyGuildNames or gGuildDesc
        cnt = PushBadgeSpec(cnt, nil, "Interface\\GossipFrame\\BattleMasterGossipIcon", TC_FULL, TINT_AVOID, L["Enemy Guild"], egDesc, TINT_AVOID_TIP)
    end
    if item.isWatchlist or item.hasFriendOrWatchlistSignup then
        local rawW = (item.watchlistMemberNames and item.watchlistMemberNames ~= "") and item.watchlistMemberNames or item.friendOrWatchlistNames
        local wDesc = (rawW and rawW ~= "") and (L["In group"] .. ": " .. rawW) or ""
        cnt = PushBadgeSpec(cnt, nil, "Interface\\AddOns\\SocialCentral\\Media\\bell-on", TC_FULL, TINT_WATCH, L["WATCHLIST"], wDesc, TINT_WATCH)
    end
    if item.isClan then
        local gDesc = (item.guildMemberNames and item.guildMemberNames ~= "") and item.guildMemberNames
            or ((item.numGuildMates or 0) > 0 and (L["Guild in group"] .. ": " .. tostring(item.numGuildMates)) or gGuildDesc)
        cnt = PushBadgeSpec(cnt, nil, "Interface\\GossipFrame\\TabardGossipIcon", TC_FULL, TINT_CLAN, L["Guild Member"], gDesc, TINT_CLAN)
    end
    if item.isAllied then
        local aDesc = (item.alliedMemberNames and item.alliedMemberNames ~= "") and item.alliedMemberNames or gGuildDesc
        cnt = PushBadgeSpec(cnt, nil, "Interface\\GossipFrame\\TabardGossipIcon", TC_FULL, TINT_ALLY, L["Allied Guild"], aDesc, TINT_ALLY)
    end
    if item.isFriend then
        local totalFriends = (item.numBNetFriends or 0) + (item.numCharFriends or 0)
        local fDesc = (item.friendMemberNames and item.friendMemberNames ~= "") and item.friendMemberNames
            or (totalFriends > 0 and (L["Friends in group"] .. ": " .. tostring(totalFriends)) or "")
        cnt = PushBadgeSpec(cnt, nil, "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", TC_FRIEND, TINT_FRIEND, L["FRIEND"], fDesc, TINT_FRIEND)
    end
    if (sMeta and sMeta.flag == "GOOD") or item.hasGoodPartnerSignup or item.isCompanion then
        local gpDesc = (item.goodPartnerNames and item.goodPartnerNames ~= "") and item.goodPartnerNames
            or (item.isCompanion and L["Recent companion (%d runs)"]:format(item.companionRuns or 1) or "")
        cnt = PushBadgeSpec(cnt, nil, "Interface\\Buttons\\UI-CheckBox-Check", TC_FULL, TINT_GOOD, L["Good Partner (+)"], gpDesc, TINT_GOOD)
    end
    if item.newPlayerFriendly and cnt < 6 then
        local npAtlas = HasAtlas("groupfinder-icon-role-large-newplayer") and "groupfinder-icon-role-large-newplayer"
            or (HasAtlas("groupfinder-icon-role-large-guide") and "groupfinder-icon-role-large-guide")
            or (HasAtlas("communities-chat-icon-flag") and "communities-chat-icon-flag")
            or nil
        cnt = PushBadgeSpec(cnt, npAtlas, "Interface\\WorldStateFrame\\AllianceFlag", TC_FLAG, TINT_GUIDE, L["New Player Friendly"], L["Dungeon Guide"], TINT_GUIDE)
    end
    if item.hasAddon and cnt < 6 then
        cnt = PushBadgeSpec(cnt, nil, "Interface\\AddOns\\SocialCentral\\Media\\icon", TC_FULL, TINT_WHITE, L["Uses SocialCentral [SC]"], "", TINT_SC_TIP)
    end
    return lfgBadgePool, cnt
end

local function UpdateLfgRow(row, item, idx, palette)
    row._item = item
    if row.nativeBgTex then
        Theme:ApplyBackdrop(row, "none", palette)
    else
        Theme:ApplyBackdrop(row, "row", palette)
    end
    if row.zebraTex then
        row.zebraTex:SetShown((not (item and item._isBulletinHeader)) and ((idx or 0) % 2 == 1))
    end
    if item and item._isBulletinHeader then
        if row.headerAccentTex then
            row.headerAccentTex:Show()
        end
        if row.relStripe then
            if (item.avoidCount or 0) > 0 or (item.enemyCount or 0) > 0 then
                row.relStripe:SetColorTexture(0.95, 0.25, 0.25, 0.95)
                row.relStripe:Show()
            elseif (item.watchCount or 0) > 0 then
                row.relStripe:SetColorTexture(1.0, 0.70, 0.24, 0.95)
                row.relStripe:Show()
            elseif (item.clanCount or 0) > 0 then
                row.relStripe:SetColorTexture(1.0, 0.82, 0.25, 0.92)
                row.relStripe:Show()
            elseif (item.allyCount or 0) > 0 then
                row.relStripe:SetColorTexture(0.28, 0.90, 0.50, 0.92)
                row.relStripe:Show()
            else
                row.relStripe:Hide()
            end
        end
        if row.SelfTex then
            row.SelfTex:Hide()
        end
        if row.SelectedTex then
            row.SelectedTex:Hide()
        end
        if row.actionBtn then
            row.actionBtn:Hide()
        end
        if row.memberClassIcons then
            for ci = 1, 5 do
                if row.memberClassIcons[ci] then row.memberClassIcons[ci]:Hide() end
            end
        end
        row._lastLeaderMode = "HEADER"
        row._scBadgeAnchorSig = "HEADER"
        row.partyIcon:Hide()
        row.classIcon:Hide()
        row.levelFs:SetText("")
        if row.metaFs then row.metaFs:SetText("") end
        for ri = 1, 5 do
            if row.roleIcons[ri] then
                row.roleIcons[ri]:Hide()
            end
        end
        for bi = 1, 6 do
            if row.infoBadges[bi] then
                row.infoBadges[bi]._tipTitle = nil
                row.infoBadges[bi]:Hide()
            end
        end

        row.badgeFs:ClearAllPoints()
        row.badgeFs:SetFontObject(GameFontHighlight)
        row.badgeFs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -10)
        row.badgeFs:SetWidth(112)
        row.badgeFs:SetJustifyH("RIGHT")
        local cnt = item.groupCount or 0
        local isPlayersSec = (item.isSectionHeader == true and item.sectionKind == "PLAYERS")
        local cntText
        if isPlayersSec then
            cntText = (cnt == 1) and L["%d player"]:format(cnt) or L["%d players"]:format(cnt)
        else
            cntText = (cnt == 1) and L["%d group"]:format(cnt) or L["%d groups"]:format(cnt)
        end
        row.badgeFs:SetText((isPlayersSec and "|cff6ec1e4" or "|cff3fb950") .. cntText .. "|r")

        row.nameFs:ClearAllPoints()
        row.nameFs:SetWidth(0)
        row.nameFs:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -12)
        row.nameFs:SetPoint("RIGHT", row.badgeFs, "LEFT", -6, 0)
        if isPlayersSec then
            row.nameFs:SetTextColor(0.43, 0.76, 0.90, 1)
        else
            row.nameFs:SetTextColor(1.0, 0.85, 0.30, 1)
        end
        local arrowStr = item.isCollapsed and "|cffffd24d[+]|r " or "|cffffd24d[-]|r "
        local lvlSpan = (item.minLvl and item.minLvl < 900 and item.maxLvl and item.maxLvl < 900)
            and (" |cff9da7b5[" .. tostring(item.minLvl) .. "-" .. tostring(item.maxLvl) .. "]|r") or ""
        local watchTag = item.isWatched and (" |cff3fb950[" .. L["Watched"] .. "]|r") or ""
        local lockTag = item._lockoutInfo and (" |cffff9b3d[" .. L["Saved"] .. "]|r") or ""
        row.nameFs:SetText(arrowStr .. (item.bucketLabel or L["Dungeon"]) .. lvlSpan .. watchTag .. lockTag)

        row.activityFs:ClearAllPoints()
        row.activityFs:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -40)
        row.activityFs:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        row.activityFs:SetJustifyH("LEFT")
        if item.isSectionHeader then
            if isPlayersSec then
                row.activityFs:SetText("|cff90b4d8" .. L["Individual players looking for a group"] .. "|r")
            elseif (item.needT or 0) > 0 or (item.needH or 0) > 0 or (item.needD or 0) > 0 then
                row.activityFs:SetText(string.format("|cffb8c0cc%s: %dT · %dH · %dD|r", L["Open Slots"], item.needT or 0, item.needH or 0, item.needD or 0))
            else
                row.activityFs:SetText("|cffb8c0cc" .. L["Formed groups looking for members"] .. "|r")
            end
            return
        end
        local metaParts = {}
        if (item.avoidCount or 0) > 0 then
            metaParts[#metaParts + 1] = "|cffff4d4d" .. L["AVOID"] .. ": " .. tostring(item.avoidCount) .. "|r"
        end
        if (item.enemyCount or 0) > 0 then
            metaParts[#metaParts + 1] = "|cffff5555" .. L["Enemy"] .. ": " .. tostring(item.enemyCount) .. "|r"
        end
        if (item.watchCount or 0) > 0 then
            metaParts[#metaParts + 1] = "|cffffb347" .. L["Watchlist"] .. ": " .. tostring(item.watchCount) .. "|r"
        end
        if (item.clanCount or 0) > 0 then
            metaParts[#metaParts + 1] = "|cffffd24d" .. L["Guild"] .. ": " .. tostring(item.clanCount) .. "|r"
        end
        if (item.allyCount or 0) > 0 then
            metaParts[#metaParts + 1] = "|cff4de680" .. L["Ally"] .. ": " .. tostring(item.allyCount) .. "|r"
        end
        if (item.trustedCount or 0) > 0 and (item.watchCount or 0) == 0 and (item.clanCount or 0) == 0 and (item.allyCount or 0) == 0 then
            metaParts[#metaParts + 1] = "|cff72c6ff" .. L["Trusted: %d"]:format(item.trustedCount) .. "|r"
        end
        if (item.needT or 0) > 0 or (item.needH or 0) > 0 or (item.needD or 0) > 0 then
            metaParts[#metaParts + 1] = string.format("%s: %dT · %dH · %dD", L["Open Slots"], item.needT or 0, item.needH or 0, item.needD or 0)
        end
        if #metaParts == 0 then
            metaParts[1] = item.isCollapsed and L["Click to show groups · Right-click to Watch"] or L["Click to collapse · Right-click to Watch"]
        end
        row.activityFs:SetText("|cffb8c0cc" .. table.concat(metaParts, "  ·  ") .. "|r")
        return
    end

    if row.headerAccentTex then
        row.headerAccentTex:Hide()
    end
    if row.SelfTex then
        row.SelfTex:SetShown(item.isSelf == true)
    end

    local isLeaderOrGroup = (item.mode == "LFM" or item.sourceType == "EVENT")
    if row._lastLeaderMode ~= isLeaderOrGroup then
        row._lastLeaderMode = isLeaderOrGroup
        row.partyIcon:SetShown(isLeaderOrGroup)
        row.nameFs:ClearAllPoints()
        if isLeaderOrGroup then
            row.nameFs:SetPoint("TOPLEFT", row, "TOPLEFT", 31, -8)
        else
            row.nameFs:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -8)
        end
    end

    -- Configure right-side Role Icons + Action Button first so line-1 width bounds never collide.
    local isSoloLfg = (item.mode == "LFG" and item.sourceType ~= "EVENT")
    local isRaidLike = (item.categoryKind == "RAIDS")
        or ((item.maxMembers or 0) > 5)
        or (item.categoryKind == "PVP")
    local anchorRoleIcon = row.roleIcons[isRaidLike and 3 or 1]
    local roleBlockW = ((isRaidLike and 3 or 5) * 24) + 42

    if row.actionBtn then
        row.actionBtn:Show()
        if Theme and Theme.ApplyBackdrop then
            Theme:ApplyBackdrop(row.actionBtn, "inset", palette)
        end
        if item.isSelf then
            row.actionBtn.Icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            row.actionBtn.Icon:SetTexCoord(0, 1, 0, 1)
            row.actionBtn.Icon:SetVertexColor(1.0, 0.35, 0.35, 1.0)
            if row.actionBtn.SetBackdropBorderColor then
                row.actionBtn:SetBackdropBorderColor(0.95, 0.28, 0.28, 0.92)
            end
            row.actionBtn.Check:Hide()
        elseif item.secretLeaderName ~= nil or item.isUnknownLeader == true then
            row.actionBtn.Icon:SetTexture("Interface\\GossipFrame\\BattleMasterGossipIcon")
            row.actionBtn.Icon:SetTexCoord(0, 1, 0, 1)
            row.actionBtn.Icon:SetVertexColor(0.95, 0.82, 0.35, 1.0)
            if row.actionBtn.SetBackdropBorderColor then
                row.actionBtn:SetBackdropBorderColor(0.90, 0.72, 0.25, 0.85)
            end
            row.actionBtn.Check:Hide()
        elseif isSoloLfg then
            row.actionBtn.Icon:SetTexture("Interface\\PaperDollInfoFrame\\Character-Plus")
            row.actionBtn.Icon:SetTexCoord(0, 1, 0, 1)
            row.actionBtn.Icon:SetVertexColor(0.35, 0.95, 0.45, 1.0)
            if row.actionBtn.SetBackdropBorderColor then
                row.actionBtn:SetBackdropBorderColor(0.28, 0.88, 0.45, 0.90)
            end
            row.actionBtn.Check:Hide()
        else
            local wasAsked = (ns.LFG and ns.LFG.IsAsked and ns.LFG:IsAsked(item)) == true
            row.actionBtn.Icon:SetTexture("Interface\\GossipFrame\\PetitionGossipIcon")
            row.actionBtn.Icon:SetTexCoord(0, 1, 0, 1)
            row.actionBtn.Icon:SetVertexColor(wasAsked and 0.45 or 1.0, wasAsked and 0.95 or 0.86, wasAsked and 0.55 or 0.40, 1.0)
            if row.actionBtn.SetBackdropBorderColor then
                if wasAsked then
                    row.actionBtn:SetBackdropBorderColor(0.28, 0.92, 0.48, 0.95)
                else
                    row.actionBtn:SetBackdropBorderColor(0.76, 0.60, 0.24, 0.85)
                end
            end
            row.actionBtn.Check:SetShown(wasAsked)
        end
    end

    local showClassIcons = (not ns.db or not ns.db.settings or ns.db.settings.lfgShowClassIconsOnRows ~= false)
        and (not isSoloLfg)
        and type(item.memberClasses) == "table"
        and #item.memberClasses > 0
    local firstClassAnchor = nil
    if row.memberClassIcons then
        for ci = 1, 5 do
            local cTex = row.memberClassIcons[ci]
            local cf = showClassIcons and item.memberClasses[ci] or nil
            if cTex and cf and cf ~= "" then
                local cSlug = cf:lower()
                local cAtlas = "groupfinder-icon-class-" .. cSlug
                if HasAtlas(cAtlas) then
                    cTex:SetAtlas(cAtlas, false)
                    cTex:SetTexCoord(0, 1, 0, 1)
                elseif _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[cf] then
                    local tc = _G.CLASS_ICON_TCOORDS[cf]
                    cTex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                    cTex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
                end
                cTex:Show()
                firstClassAnchor = cTex
            elseif cTex then
                cTex:Hide()
            end
        end
    end

    if isSoloLfg then
        local soloList = lfgSoloListScratch
        wipe(soloList)
        if type(item.soloRoles) == "table" and (item.soloRoles.TANK or item.soloRoles.HEALER or item.soloRoles.DPS) then
            if item.soloRoles.TANK then soloList[#soloList + 1] = "TANK" end
            if item.soloRoles.HEALER then soloList[#soloList + 1] = "HEALER" end
            if item.soloRoles.DPS then soloList[#soloList + 1] = "DPS" end
        elseif item.role == "TANK" or item.role == "HEALER" or item.role == "DPS" then
            soloList[1] = item.role
        else
            soloList[1] = "TANK"
            soloList[2] = "HEALER"
            soloList[3] = "DPS"
        end
        local soloCount = #soloList
        local startSlot = 6 - soloCount
        for ri = 1, startSlot - 1 do
            if row.roleIcons[ri] then row.roleIcons[ri]:Hide() end
        end
        for offset = 1, soloCount do
            local ico = row.roleIcons[startSlot + offset - 1]
            ico:SetSize(24, 24)
            SetRoleSlotTexture(ico, soloList[offset])
            ico:SetDesaturated(false)
            ico:SetAlpha(1.0)
            ico:Show()
        end
        anchorRoleIcon = row.roleIcons[startSlot] or row.roleIcons[5]
        roleBlockW = (soloCount * 24) + 42
    elseif isRaidLike then
        for ri = 1, 2 do
            if row.roleIcons[ri] then row.roleIcons[ri]:Hide() end
        end
        for offset = 1, 3 do
            local ico = row.roleIcons[2 + offset]
            local rType = lfgRaidSlots[offset]
            ico:SetSize(24, 24)
            SetRoleSlotTexture(ico, rType)
            local openSlot = true
            if item.needT ~= nil or item.needH ~= nil or item.needD ~= nil then
                if rType == "TANK" then openSlot = (item.needT or 0) > 0
                elseif rType == "HEALER" then openSlot = (item.needH or 0) > 0
                else openSlot = (item.needD or 0) > 0 end
            else
                local role = item.role or "ANY"
                openSlot = (role == "ANY" or role == "" or role == rType)
            end
            ico:SetDesaturated(not openSlot)
            ico:SetAlpha(openSlot and 1.0 or 0.28)
            ico:Show()
        end
    else
        local slotFilled = lfgSlotFilledScratch
        for s = 1, 5 do
            slotFilled[s] = false
        end
        local totalNum = item.numMembers or 0
        if totalNum >= 5 or (item.needT == 0 and item.needH == 0 and item.needD == 0) then
            for s = 1, 5 do slotFilled[s] = true end
        elseif item.filledT ~= nil or item.filledH ~= nil or item.filledD ~= nil or item.filledNoRole ~= nil then
            local curT = item.filledT or 0
            local curH = item.filledH or 0
            local rawD = item.filledD or 0
            local curD = math.min(3, rawD)
            local curNo = item.filledNoRole or 0
            if curT >= 1 then slotFilled[1] = true end
            if curH >= 1 then slotFilled[2] = true end
            for d = 1, curD do
                slotFilled[2 + d] = true
            end
            local overflow = math.max(0, curT - 1) + math.max(0, curH - 1) + math.max(0, rawD - 3)
            local remNo = curNo + overflow
            for oi = 1, #lfgFillPriorityOrder do
                if remNo <= 0 then break end
                local orderIdx = lfgFillPriorityOrder[oi]
                if not slotFilled[orderIdx] then
                    slotFilled[orderIdx] = true
                    remNo = remNo - 1
                end
            end
        elseif item.needT ~= nil or item.needH ~= nil or item.needD ~= nil then
            slotFilled[1] = (item.needT or 0) <= 0
            slotFilled[2] = (item.needH or 0) <= 0
            local filledD = math.max(0, 3 - math.max(0, math.min(3, item.needD or 0)))
            for d = 1, filledD do
                slotFilled[2 + d] = true
            end
        elseif totalNum > 0 then
            local rem = math.min(5, totalNum)
            for oi = 1, #lfgFillPriorityOrder do
                if rem <= 0 then break end
                local orderIdx = lfgFillPriorityOrder[oi]
                slotFilled[orderIdx] = true
                rem = rem - 1
            end
        end

        for s = 1, 5 do
            local ico = row.roleIcons[s]
            local isFilled = slotFilled[s] == true
            if isFilled then
                ico:SetSize(24, 24)
                SetRoleSlotTexture(ico, lfgSlotRoles[s])
                ico:SetDesaturated(false)
                ico:SetAlpha(1.0)
            elseif HasAtlas("groupfinder-icon-emptyslot") then
                ico:SetAtlas("groupfinder-icon-emptyslot", false)
                ico:SetTexCoord(0, 1, 0, 1)
                ico:SetSize(14, 14)
                ico:SetDesaturated(false)
                ico:SetAlpha(0.78)
            else
                ico:SetSize(21, 21)
                SetRoleSlotTexture(ico, lfgSlotRoles[s])
                ico:SetDesaturated(true)
                ico:SetAlpha(0.24)
            end
            ico:Show()
        end
    end

    local sMeta = Store and (Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(item.lookupKey or item.displayName) or Store:GetSocialMeta(item.lookupKey or item.displayName))
    local flagPrefix = ""
    if sMeta and sMeta.flag == "AVOID" then
        flagPrefix = "|cffff4d4d[!]|r "
    elseif sMeta and sMeta.flag == "GOOD" then
        flagPrefix = "|cff3fb950[+]|r "
    end

    if item.secretLeaderName ~= nil then
        local cc = item.classFile and (_G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[item.classFile])
        if cc then
            row.nameFs:SetTextColor(cc.r or 1, cc.g or 0.82, cc.b or 0, 1)
        else
            row.nameFs:SetTextColor(1, 0.82, 0, 1)
        end
        row.nameFs:SetText(item.secretLeaderName)
    else
        row.nameFs:SetTextColor(1, 1, 1, 1)
        local classHex = Compat.ClassHex and Compat.ClassHex(item.classFile) or "|cffffd200"
        local dispLeader = item.displayName or "?"
        if dispLeader == L["Official LFG"] or (item.isUnknownLeader and dispLeader == "?") then
            local locClass = item.classFile and _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[item.classFile]
            dispLeader = (locClass and locClass ~= "") and (locClass .. " (" .. L["Leader"] .. ")") or L["Leader"]
        end
        local keyTag = (item.keyLvl and item.keyLvl > 0) and (" |cffd2a8ff+" .. item.keyLvl .. "|r") or ""
        local selfTag = item.isSelf and (" |cff3fb950(" .. L["You"] .. ")|r") or ""
        row.nameFs:SetText(string.format("%s%s%s|r%s%s", flagPrefix, classHex, dispLeader, keyTag, selfTag))
    end

    local lvlPart = (item.level and item.level > 0) and L["Lv %d"]:format(item.level) or ""
    if item._idealLevel and lvlPart ~= "" then
        lvlPart = "|cff3fb950" .. lvlPart .. "|r"
    end

    local rowW = (row.GetWidth and row:GetWidth()) or 0
    if rowW < 180 then rowW = 314 end
    local isNarrow = (rowW < 380)
    row.levelFs:SetText((rowW < 250) and "" or lvlPart)

    local classSlug = type(item.classFile) == "string" and item.classFile:lower() or nil
    local classAtlas = classSlug and ("groupfinder-icon-class-" .. classSlug) or nil
    local hasClassIcon = (rowW >= 220) and (classAtlas and HasAtlas(classAtlas)) and true or false
    if row.classIcon then
        local cSize = isNarrow and 14 or 18
        if row._scClassIconSize ~= cSize then
            row._scClassIconSize = cSize
            row.classIcon:SetSize(cSize, cSize)
        end
    end
    local badgeSpecs, numBadges = BuildLfgRowBadgeSpecs(item, sMeta)

    local leftStart = isLeaderOrGroup and 31 or 12
    local lvlW = (rowW >= 250 and lvlPart ~= "") and ((row.levelFs:GetStringWidth() or 36) + 7) or 0
    local clsW = hasClassIcon and (isNarrow and 18 or 22) or 0
    local badgesW = (numBadges > 0) and (numBadges * 17 + 6) or 0
    local extraTagW = ((sMeta and sMeta.flag == "AVOID") or item.hasAvoidSignup or item.isEnemyGuild or item._lockoutInfo) and 48 or 0
    local maxNameW = math.max(isNarrow and 84 or 96, math.min(isNarrow and 220 or 240, rowW - leftStart - roleBlockW - lvlW - clsW - badgesW - extraTagW - (isNarrow and 6 or 8)))
    row.nameFs:SetWidth(0)
    local nameStrW = (row.nameFs.GetUnboundedStringWidth and row.nameFs:GetUnboundedStringWidth())
        or row.nameFs:GetStringWidth()
        or 96
    row.nameFs:SetWidth(math.min(maxNameW, math.max(42, nameStrW)))

    local lastAnchor = (rowW >= 250 and lvlPart ~= "") and row.levelFs or row.nameFs
    local rowAnchorSig = (isNarrow and "NARROW:" or "WIDE:")
        .. (((not isNarrow) and lvlPart ~= "") and "L:" or "N:")
        .. (hasClassIcon and "C:" or "0:")
        .. tostring(numBadges) .. ":" .. tostring(anchorRoleIcon) .. ":" .. tostring(firstClassAnchor)
    local needAnchorReset = (row._scBadgeAnchorSig ~= rowAnchorSig)
    row._scBadgeAnchorSig = rowAnchorSig

    if hasClassIcon then
        if row._lastClassAtlas ~= classAtlas then
            row._lastClassAtlas = classAtlas
            row.classIcon:SetAtlas(classAtlas, false)
        end
        if needAnchorReset then
            row.classIcon:ClearAllPoints()
            row.classIcon:SetPoint("LEFT", lastAnchor, "RIGHT", 4, 0)
        end
        row.classIcon:Show()
        lastAnchor = row.classIcon
    else
        row.classIcon:Hide()
    end

    for bi = 1, 6 do
        local bf = row.infoBadges[bi]
        local sp = (bi <= numBadges) and badgeSpecs[bi] or nil
        if bf and sp then
            if needAnchorReset then
                bf:ClearAllPoints()
                bf:SetPoint("LEFT", lastAnchor, "RIGHT", (bi == 1) and 4 or 2, 0)
            end
            if sp.atlas and HasAtlas(sp.atlas) then
                bf.tex:SetTexCoord(0, 1, 0, 1)
                bf.tex:SetAtlas(sp.atlas, false)
            else
                bf.tex:SetTexture(sp.tex)
                bf.tex:SetTexCoord(sp.tc[1], sp.tc[2], sp.tc[3], sp.tc[4])
            end
            bf.tex:SetVertexColor(sp.tint[1], sp.tint[2], sp.tint[3], 1.0)
            bf._tipTitle = sp.title
            bf._tipDesc = sp.desc
            bf._tipColor = sp.tipColor
            bf:Show()
            lastAnchor = bf
        elseif bf then
            bf._tipTitle = nil
            bf:Hide()
        end
    end

    if needAnchorReset then
        row.badgeFs:ClearAllPoints()
        row.badgeFs:SetFontObject(GameFontHighlightSmall)
        row.badgeFs:SetWidth(0)
        row.badgeFs:SetJustifyH("LEFT")
        row.badgeFs:SetPoint("LEFT", lastAnchor, "RIGHT", 4, 0)
        row.badgeFs:SetPoint("RIGHT", anchorRoleIcon, "LEFT", -6, 0)
        row.activityFs:ClearAllPoints()
        row.activityFs:SetJustifyH("LEFT")
        row.activityFs:SetPoint("TOPLEFT", row.nameFs, "BOTTOMLEFT", 0, -7)
        row.activityFs:SetPoint("RIGHT", row.actionBtn or anchorRoleIcon, "LEFT", -8, 0)
        if row.metaFs then
            row.metaFs:ClearAllPoints()
            row.metaFs:SetJustifyH("LEFT")
            row.metaFs:SetPoint("TOPLEFT", row.activityFs, "BOTTOMLEFT", 0, -4)
            row.metaFs:SetPoint("RIGHT", firstClassAnchor or row.actionBtn or anchorRoleIcon, "LEFT", -8, 0)
        end
    end

    local isAvoidRow = (sMeta and sMeta.flag == "AVOID") or item._isAvoidFlag or item.hasAvoidSignup
    local isGoodRow = (sMeta and sMeta.flag == "GOOD") or item._isGoodFlag or item.hasGoodPartnerSignup
    local isWatchRow = item.isWatchlist or item.hasFriendOrWatchlistSignup
    if row.relStripe then
        if isAvoidRow then
            row.relStripe:SetColorTexture(0.98, 0.24, 0.24, 0.96)
            row.relStripe:Show()
        elseif item.isEnemyGuild then
            row.relStripe:SetColorTexture(0.92, 0.30, 0.22, 0.94)
            row.relStripe:Show()
        elseif isWatchRow then
            row.relStripe:SetColorTexture(1.0, 0.70, 0.24, 0.95)
            row.relStripe:Show()
        elseif isGoodRow then
            row.relStripe:SetColorTexture(0.25, 0.90, 0.45, 0.92)
            row.relStripe:Show()
        elseif item.isClan then
            row.relStripe:SetColorTexture(1.0, 0.82, 0.25, 0.92)
            row.relStripe:Show()
        elseif item.isAllied then
            row.relStripe:SetColorTexture(0.28, 0.90, 0.50, 0.92)
            row.relStripe:Show()
        elseif item.isFriend then
            row.relStripe:SetColorTexture(0.38, 0.78, 1.0, 0.90)
            row.relStripe:Show()
        else
            row.relStripe:Hide()
        end
    end

    local badges = ""
    if sMeta and sMeta.flag == "AVOID" then
        badges = badges .. "|cffff4d4d[" .. L["AVOID"] .. "]|r "
    elseif item.hasAvoidSignup then
        badges = badges .. "|cffff4d4d[!" .. L["AVOID"] .. "]|r "
    end
    if item.isEnemyGuild then
        badges = badges .. "|cffff5555[" .. L["Enemy"] .. "]|r "
    end
    if item.hasGoodPartnerSignup then
        badges = badges .. "|cff3fb950[+" .. L["PARTNER"] .. "]|r "
    end
    if item._lockoutInfo then
        local lk = item._lockoutInfo
        local lockProg = (lk.numEncounters and lk.numEncounters > 0)
            and string.format("%s %d/%d", L["LOCKED"], lk.encounterProgress or 0, lk.numEncounters)
            or L["LOCKED"]
        badges = badges .. "|cffff9b3d[" .. lockProg .. "]|r "
    end
    if item.sourceType == "PUBLIC_CHAT" then
        local rawKw = ns.db and ns.db.settings and ns.db.settings.clanLfgAlertFilter
        if type(rawKw) == "string" and rawKw ~= "" then
            local haystack = ((item.activity or "") .. " " .. (item.note or "")):lower()
            for kw in rawKw:gmatch("([^,]+)") do
                local trimmed = kw:match("^%s*(.-)%s*$"):lower()
                if trimmed ~= "" and haystack:find(trimmed, 1, true) then
                    badges = badges .. "|cff3fb950[" .. L["MATCH"] .. "]|r "
                    break
                end
            end
        end
    end
    if item.isCompanion then
        badges = badges .. "|cff6ec1e4[" .. L["PARTNER"] .. "]|r"
    end
    row.badgeFs:SetText(badges)

    local actTxt = item._displayActivity or item.activity or L["Dungeon"]
    local modeTag
    if isSoloLfg then
        modeTag = "|cff58a6ff[" .. L["Looking"] .. "]|r "
    elseif item.numMembers and item.numMembers > 0 then
        local capStr = (item.maxMembers and item.maxMembers > 0)
            and string.format("%d/%d", item.numMembers, item.maxMembers)
            or tostring(item.numMembers)
        modeTag = "|cff3fb950[" .. L["LFM"] .. " " .. capStr .. "]|r "
    else
        modeTag = "|cff3fb950[" .. L["LFM"] .. "]|r "
    end
    local relPills = ""
    if isWatchRow then
        relPills = relPills .. "|cffffb347[" .. L["Watchlist"] .. "]|r "
    end
    if item.isClan then
        relPills = relPills .. "|cffffd24d[" .. L["Guild"] .. "]|r "
    elseif item.isAllied then
        relPills = relPills .. "|cff4de680[" .. L["Ally"] .. "]|r "
    elseif item.hasAddon == true and not item.isSelf then
        relPills = relPills .. "|cff6ec1e4[" .. L["Addon"] .. "]|r "
    end
    if item.isEnemyGuild then
        relPills = relPills .. "|cffff5555[" .. L["Enemy"] .. "]|r "
    end
    if isAvoidRow then
        relPills = relPills .. "|cffff4d4d[" .. L["AVOID"] .. "]|r "
    end
    local narrowLvlPart = (isNarrow and lvlPart ~= "") and ("  |cff9da7b5·|r " .. lvlPart) or ""
    local areaPart = (isSoloLfg and item.area and item.area ~= "") and (" |cff90b4d8(" .. item.area .. ")|r") or ""
    row.activityFs:SetText("|cffede6d6" .. actTxt .. "|r" .. narrowLvlPart .. areaPart)
    if row.metaFs then
        local playPart = (item.playstyleLabel and item.playstyleLabel ~= "") and ("|cff4de680" .. item.playstyleLabel .. "|r ") or ""
        local notePart = (item.note and item.note ~= "") and (" — " .. item.note) or ""
        local friendNote = (item.hasFriendOrWatchlistSignup and item.friendOrWatchlistNames and item.friendOrWatchlistNames ~= "")
            and (" |cffffa633(" .. L["In group"] .. ": " .. item.friendOrWatchlistNames .. ")|r") or ""
        row.metaFs:SetText(playPart .. modeTag .. relPills .. "|cffb8c0cc" .. notePart .. "|r" .. friendNote)
    end

    local selKey = LFGFrameTab.selectedKey
    local isSel = (selKey ~= nil) and (GetItemIdentityKey(item) == selKey)
    row.SelectedTex:SetShown(isSel)
end

LFGFrameTab.CreateSharedLfgRow = CreateLfgRow
LFGFrameTab.UpdateSharedLfgRow = UpdateLfgRow

local ROLE_CIRCLE_DEFS = {
    { id = "TANK",   labelKey = "Tank",          x = 56,  glass = { 0.08, 0.24, 0.50 }, glow = { 0.16, 0.48, 0.98 }, badge = false },
    { id = "HEALER", labelKey = "Healer",        x = 114, glass = { 0.07, 0.34, 0.26 }, glow = { 0.18, 0.88, 0.42 }, badge = false },
    { id = "DPS",    labelKey = "DPS",           x = 172, glass = { 0.42, 0.10, 0.10 }, glow = { 0.92, 0.22, 0.18 }, badge = false },
    { id = "GUIDE",  labelKey = "Dungeon Guide", x = 248, glass = { 0.09, 0.22, 0.18 }, glow = { 0.20, 0.82, 0.46 }, badge = true  },
}

local function CreateRoleCircleButton(parent, def, artInfo)
    local roleArt = artInfo and artInfo.roles and artInfo.roles[def.id]
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(52, 52)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", def.x, -23)

    -- Soft radial swirl aura matching selected role color
    local swirl = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    swirl:SetSize(72, 72)
    swirl:SetPoint("CENTER", btn, "CENTER", 0, 0)
    if roleArt and roleArt.swirl then
        ApplyTexSpec(swirl, roleArt.swirl, nil, nil)
    else
        swirl:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        swirl:SetVertexColor(def.glow[1], def.glow[2], def.glow[3], 0.38)
    end
    swirl:SetBlendMode("ADD")
    local swirlMask = btn:CreateMaskTexture()
    swirlMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    swirlMask:SetSize(66, 66)
    swirlMask:SetPoint("CENTER", btn, "CENTER", 0, 0)
    swirl:AddMaskTexture(swirlMask)
    btn.swirl = swirl

    -- Colored glass dome interior masked cleanly with Blizzard portrait alpha mask
    local disc = btn:CreateTexture(nil, "BORDER", nil, 1)
    disc:SetSize(44, 44)
    disc:SetPoint("CENTER", btn, "CENTER", 0, 0)
    disc:SetTexture(WHITE8X8)
    disc:SetVertexColor(def.glass[1], def.glass[2], def.glass[3], 0.96)
    local mask = btn:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(44, 44)
    mask:SetPoint("CENTER", btn, "CENTER", 0, 0)
    disc:AddMaskTexture(mask)

    -- Active colored perimeter ring
    local ringGlow = btn:CreateTexture(nil, "BORDER", nil, 2)
    ringGlow:SetSize(54, 54)
    ringGlow:SetPoint("CENTER", btn, "CENTER", 0, 0)
    ringGlow:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    ringGlow:SetVertexColor(def.glow[1], def.glow[2], def.glow[3], 0.85)
    ringGlow:Hide()
    btn.ringGlow = ringGlow

    -- Metallic bezel ring around circular slot
    local ring = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    ring:SetSize(52, 52)
    ring:SetPoint("CENTER", btn, "CENTER", 0, 0)
    if HasAtlas("Artifacts-PerkRing-Final") then
        ring:SetAtlas("Artifacts-PerkRing-Final", false)
    elseif HasAtlas("common-ring-gold") then
        ring:SetAtlas("common-ring-gold", false)
    else
        ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        ring:SetSize(84, 84)
        ring:ClearAllPoints()
        ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
    end
    ring:SetVertexColor(0.88, 0.80, 0.66, 1.0)

    -- Center Role Icon (Large bold Shield / Cross / Sword / Green Flag matching Forever 16001)
    local icon = btn:CreateTexture(nil, "ARTWORK", nil, 3)
    if def.id == "GUIDE" then
        icon:SetSize(34, 34)
    else
        icon:SetSize(40, 40)
    end
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local iconTint = nil
    if roleArt and roleArt.icon and def.id ~= "GUIDE" then
        ApplyTexSpec(icon, roleArt.icon, nil, nil)
    elseif def.id == "GUIDE" then
        if roleArt and roleArt.icon then
            ApplyTexSpec(icon, roleArt.icon, nil, nil)
        elseif HasAtlas("groupfinder-icon-role-large-newplayer") then
            icon:SetAtlas("groupfinder-icon-role-large-newplayer", false)
        elseif HasAtlas("groupfinder-icon-role-large-guide") then
            icon:SetAtlas("groupfinder-icon-role-large-guide", false)
        elseif HasAtlas("communities-chat-icon-flag") then
            icon:SetAtlas("communities-chat-icon-flag", false)
            iconTint = { 0.28, 0.92, 0.38 }
            icon:SetVertexColor(0.28, 0.92, 0.38, 1.0)
        else
            icon:SetTexture("Interface\\WorldStateFrame\\AllianceFlag")
            icon:SetTexCoord(0.15, 0.85, 0.10, 0.90)
            iconTint = { 0.28, 0.95, 0.40 }
            icon:SetVertexColor(0.28, 0.95, 0.40, 1.0)
        end
    else
        SetRoleSlotTexture(icon, def.id, "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
    end
    btn.icon = icon

    -- Small top-right newcomer murloc badge on Dungeon Guide circle
    if def.badge then
        local badge = btn:CreateTexture(nil, "OVERLAY", nil, 4)
        badge:SetSize(18, 18)
        badge:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 4, 3)
        if roleArt and roleArt.badge then
            ApplyTexSpec(badge, roleArt.badge, nil, nil)
        elseif HasAtlas("newplayerchat-chaticon-newcomer") then
            badge:SetAtlas("newplayerchat-chaticon-newcomer", false)
        else
            badge:SetTexture("Interface\\Icons\\INV_Misc_Head_Murloc_01")
            badge:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        btn.badge = badge
    end

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetSize(50, 50)
    hl:SetPoint("CENTER", btn, "CENTER", 0, 0)
    hl:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    hl:SetVertexColor(1.0, 0.85, 0.35, 0.45)
    hl:SetBlendMode("ADD")

    -- Bottom-left dark bordered checkbutton matching Forever's LFGListingFrame
    local checkBg = btn:CreateTexture(nil, "OVERLAY", nil, 1)
    checkBg:SetSize(14, 14)
    checkBg:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -2, -1)
    checkBg:SetTexture(WHITE8X8)
    checkBg:SetVertexColor(0.06, 0.05, 0.04, 0.95)

    local check = CreateFrame("CheckButton", nil, btn, "UICheckButtonTemplate")
    check:SetSize(20, 20)
    check:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -5, -4)
    check:SetFrameLevel(btn:GetFrameLevel() + 3)

    local function toggleRole()
        LFGFrameTab.roles[def.id] = not (LFGFrameTab.roles[def.id] == true)
        LFGFrameTab.composerRole = LFGFrameTab:GetPrimaryListingRole()
        LFGFrameTab:UpdateViewLayout()
    end

    btn:SetScript("OnClick", toggleRole)
    check:SetScript("OnClick", toggleRole)
    btn:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:SetText(L[def.labelKey], 1.0, 0.82, 0.0)
        if def.id == "GUIDE" then
            GameTooltip:AddLine(L["Indicates that you are willing to guide new players through the group activity."], 0.9, 0.9, 0.9, true)
        elseif ns.Clan and ns.Clan.GetRecommendedRolesForCharacter then
            local rec = ns.Clan:GetRecommendedRolesForCharacter()
            if rec and rec.recommended and rec.recommended[def.id] then
                GameTooltip:AddLine("|cff3fb950" .. L["Suggested for %s"]:format(rec.whoDesc or "") .. "|r", 0.35, 0.92, 0.55, true)
            elseif rec and rec.capable and not rec.capable[def.id] then
                GameTooltip:AddLine(rec.classLoc or "", 0.65, 0.68, 0.74, true)
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return {
        roleId = def.id,
        button = btn,
        check = check,
        swirl = swirl,
        ringGlow = ringGlow,
        icon = icon,
        iconTint = iconTint,
    }
end

local BANNER_ATLAS_CANDIDATES = {
    DUNGEONS = { "groupfinder-button-dungeons", "groupfinder-background-dungeons", "lfg-button-dungeons" },
    RAIDS = { "groupfinder-button-raids", "groupfinder-background-raids", "groupfinder-button-scenarios", "groupfinder-button-dungeons" },
    QUESTS = { "groupfinder-button-questing", "groupfinder-background-questing", "groupfinder-button-quests" },
    PVP = { "groupfinder-button-battlegrounds", "groupfinder-background-battlegrounds", "groupfinder-button-pvp" },
    CUSTOM = { "groupfinder-button-custom", "groupfinder-background-custom" },
}

local function CreateCategoryBannerButton(parent, catDef, index, artInfo)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(44)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -8 - ((index - 1) * 49))
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -8 - ((index - 1) * 49))

    -- Outer metallic button base BEHIND the illustrated artwork
    local frameBg = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
    frameBg:SetAllPoints(btn)
    if HasAtlas("common-button-list-large") then
        frameBg:SetAtlas("common-button-list-large", false)
    else
        frameBg:SetTexture(WHITE8X8)
        frameBg:SetVertexColor(0.11, 0.10, 0.09, 1.0)
    end

    -- Illustrated category art background (drawn cleanly ABOVE frameBg)
    local artTex = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
    artTex:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    artTex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)

    function btn:ApplyBannerArt(latestArt)
        local harvested = latestArt and latestArt.banners and latestArt.banners[catDef.id]
        if harvested then
            ApplyTexSpec(artTex, harvested, nil, nil)
            if catDef.id == "RAIDS" then
                artTex:SetVertexColor(0.98, 0.62, 0.54, 1.0)
            else
                artTex:SetVertexColor(0.98, 0.98, 0.98, 1.0)
            end
            return
        end
        local candidates = BANNER_ATLAS_CANDIDATES[catDef.id]
        if candidates then
            for _, aName in ipairs(candidates) do
                if HasAtlas(aName) then
                    artTex:SetAtlas(aName, false)
                    artTex:SetTexCoord(0, 1, 0, 1)
                    if catDef.id == "RAIDS" and aName ~= "groupfinder-button-raids" then
                        artTex:SetVertexColor(0.96, 0.56, 0.48, 1.0)
                    else
                        artTex:SetVertexColor(0.98, 0.98, 0.98, 1.0)
                    end
                    return
                end
            end
        end
        if HasAtlas("groupfinder-background") then
            artTex:SetAtlas("groupfinder-background", false)
            artTex:SetTexCoord(0.05, 0.95, 0.15 + ((index - 1) * 0.12) % 0.4, 0.45 + ((index - 1) * 0.12) % 0.4)
            artTex:SetVertexColor(math.min(1, catDef.tint[1] * 1.35), math.min(1, catDef.tint[2] * 1.35), math.min(1, catDef.tint[3] * 1.35), 1.0)
        else
            artTex:SetTexture(catDef.fallbackTex or "Interface\\FrameGeneral\\UI-Background-Marble")
            artTex:SetTexCoord(0.05, 0.95, 0.25, 0.72)
            artTex:SetVertexColor(catDef.tint[1], catDef.tint[2], catDef.tint[3], 1.0)
        end
    end
    btn:ApplyBannerArt(artInfo)

    -- Subtle left-to-right dark gradient scrim so title pops while artwork shines on the right
    local scrim = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    scrim:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    scrim:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    scrim:SetTexture(WHITE8X8)
    if scrim.SetGradient and CreateColor then
        pcall(scrim.SetGradient, scrim, "HORIZONTAL", CreateColor(0.02, 0.02, 0.02, 0.78), CreateColor(0.02, 0.02, 0.02, 0.04))
    else
        scrim:SetVertexColor(0.03, 0.03, 0.03, 0.36)
    end

    -- Hollow metallic bezel border around the button (leaves artwork 100% visible)
    btn:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropBorderColor(0.62, 0.54, 0.40, 0.94)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn)
    if HasAtlas("common-button-list-large-hover") then
        hl:SetAtlas("common-button-list-large-hover", false)
    else
        hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    end
    hl:SetBlendMode("ADD")

    local countFs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countFs:SetPoint("RIGHT", btn, "RIGHT", -14, 0)
    countFs:SetJustifyH("RIGHT")
    countFs:SetWordWrap(false)
    countFs:SetShadowOffset(1, -1)
    countFs:SetShadowColor(0, 0, 0, 0.95)
    btn.countFs = countFs
    btn._catId = catDef.id

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("LEFT", btn, "LEFT", 16, 0)
    label:SetPoint("RIGHT", countFs, "LEFT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(L[catDef.labelKey])
    label:SetTextColor(1.0, 0.82, 0.0)
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 0.95)
    btn.label = label

    btn:SetScript("OnClick", function()
        local inGroup = Compat.IsInGroup and Compat.IsInGroup()
        LFGFrameTab.activeCategory = catDef.id
        LFGFrameTab.listingMode = inGroup and "LFM" or "LFG"
        if not LFGFrameTab:HasAnySelectedActivity() and LFGFrameTab.browseActivityFilter and next(LFGFrameTab.browseActivityFilter) ~= nil then
            local opts = LFGFrameTab:GetFilteredCategoryActivities(catDef.id, LFGFrameTab.showAllLevels)
            for i = 1, #opts do
                local opt = opts[i]
                local lbl = ResolveActivityDisplayName(opt):lower()
                for _, fOpt in pairs(LFGFrameTab.browseActivityFilter) do
                    if (opt.officialId and fOpt and fOpt.officialId == opt.officialId)
                        or (fOpt and fOpt.labelLower and lbl == fOpt.labelLower)
                    then
                        LFGFrameTab.selectedActivities[opt.id] = true
                        break
                    end
                end
            end
        end
        LFGFrameTab.viewMode = "activities"
        LFGFrameTab:RefreshData()
    end)

    return btn
end

local function CreateActivityRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(22)

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1.0, 0.82, 0.25, 0.14)

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetSize(20, 20)
    check:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.check = check

    local lvlLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lvlLabel:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    lvlLabel:SetJustifyH("RIGHT")
    lvlLabel:SetTextColor(1.0, 0.82, 0.0)
    row.lvlLabel = lvlLabel

    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("LEFT", check, "RIGHT", 4, 0)
    nameLabel:SetPoint("RIGHT", lvlLabel, "LEFT", -6, 0)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetWordWrap(false)
    nameLabel:SetTextColor(1.0, 0.82, 0.0)
    row.nameLabel = nameLabel

    local function toggleAct()
        local act = row._act
        if not act then return end
        local nextVal = not (LFGFrameTab.selectedActivities[act.id] == true)
        LFGFrameTab.selectedActivities[act.id] = nextVal or nil
        LFGFrameTab:RefreshData()
    end

    row:SetScript("OnClick", toggleAct)
    check:SetScript("OnClick", toggleAct)
    return row
end

local function UpdateActivityRow(row, act)
    row._act = act
    row.check:SetChecked(LFGFrameTab.selectedActivities[act.id] == true)
    local actTitle
    if act.isQuestEntry then
        actTitle = act.directLabel or ""
        row.nameLabel:SetTextColor(0.45, 0.88, 1.0)
    elseif act.directLabel then
        actTitle = act.directLabel
        row.nameLabel:SetTextColor(1.0, 0.82, 0.0)
    else
        actTitle = (act.labelKey and L[act.labelKey]) or ""
        row.nameLabel:SetTextColor(1.0, 0.82, 0.0)
    end
    local locks = LFGFrameTab._cachedActivityLockouts
    if locks and #locks > 0 then
        local lk = GetActivityLockout({
            activity = actTitle,
            activityIds = act.officialId and { act.officialId } or nil,
        }, locks)
        if lk then
            actTitle = actTitle .. " |cffff9b3d[" .. L["Saved"] .. "]|r"
        end
    end
    row.nameLabel:SetText(actTitle)

    local minL = tonumber(act.minLvl) or 1
    local maxL = tonumber(act.maxLvl) or 60
    local myLvl = (ns.Safe and ns.Safe.Number(UnitLevel and UnitLevel("player"))) or 60
    if myLvl <= 0 then myLvl = 60 end
    if myLvl >= minL and myLvl <= maxL then
        row.lvlLabel:SetTextColor(0.30, 0.92, 0.50)
    elseif minL > myLvl then
        row.lvlLabel:SetTextColor(1.0, 0.60, 0.24)
    else
        row.lvlLabel:SetTextColor(0.58, 0.62, 0.68)
    end
    row.lvlLabel:SetText("(" .. tostring(minL) .. " - " .. tostring(maxL) .. ")")
end

local function KeepAddonTabOverNativeRedirect(seq)
    if LFGFrameTab._transitionSeq ~= seq or not LFGFrameTab.active then
        return
    end
    if not (_G.LFGParentFrame and _G.LFGParentFrame:IsShown() and LFGFrameTab.subPanel and LFGFrameTab.subPanel:IsShown()) then
        return
    end
    HideNativeLfgSubFrames()
    SetNativeTabsCheckedFalse()
    ElevateLfgParentControls()
    LFGFrameTab:UpdateTabSelectionVisual()
    LFGFrameTab:RefreshData()
end

function LFGFrameTab:SubmitListing()
    if IsCombatLocked() then
        ns:Print(L["Looking for Group (I)"] .. ": " .. L["Unavailable during combat."])
        return
    end
    if Compat.IsInGroup and Compat.IsInGroup() and Compat.CanManageGroupListing and not Compat.CanManageGroupListing() then
        local leaderName = Compat.GetGroupLeaderName and Compat.GetGroupLeaderName()
        ns:Print("%s", FormatLeaderOnlyMessage(leaderName))
        self.viewMode = "categories"
        self:RefreshData()
        return
    end
    if self.broadcastMode == "OFFICIAL" then
        self:SwitchToOfficialListingTab("GUILD_ALLIES")
        return
    end
    if not (self:HasAnySelectedRole() and self:HasAnySelectedActivity()) then
        return
    end

    local mode = (self.listingMode == "LFM") and "LFM" or "LFG"
    local role = self:GetPrimaryListingRole()
    local actMeta = self:CollectSelectedActivitiesMeta()
    local activity = self:GetSelectedActivitiesSummary()
    local noteParts = {}

    if self.playstyle == "NORMAL" or self.playstyle == "FAST" or self.playstyle == "FULL" then
        noteParts[#noteParts + 1] = GetPlaystyleLabel(self.playstyle)
    end
    local roleTag = self:GetSelectedRolesNoteTag()
    if roleTag ~= "" then
        noteParts[#noteParts + 1] = roleTag
    end
    if mode == "LFM" and Compat.IsInGroup and Compat.IsInGroup() and not (Compat.IsInRaid and Compat.IsInRaid()) and ns.Group and ns.Group.GetSummaryCounts then
        local gCounts = ns.Group:GetSummaryCounts()
        if gCounts and (gCounts.total or 0) >= 1 and (gCounts.total or 0) < 5 then
            noteParts[#noteParts + 1] = ("[%d/5]"):format(gCounts.total)
        end
    end
    local rawComment = (self.controls.commentBox and self.controls.commentBox:GetText()) or self.commentText or ""
    rawComment = rawComment:match("^%s*(.-)%s*$")
    if rawComment ~= "" then
        noteParts[#noteParts + 1] = rawComment
    end
    if self.broadcastMode == "CLAN" then
        noteParts[#noteParts + 1] = "[" .. L["Same Clan"] .. "]"
    end

    local note = table.concat(noteParts, " "):gsub("[|\r\n]", " ")
    if #note > 80 then
        note = note:sub(1, 77) .. "..."
    end

    local postOk, postRes = false, nil
    if ns.Clan and ns.Clan.PostLFG then
        postOk, postRes = ns.Clan:PostLFG(mode, role, activity, 0, note, self.broadcastMode == "CLAN", self.activeCategory == "DUNGEONS")
    end
    if postOk and type(postRes) == "table" then
        postRes.isOfficial = nil
        postRes.activityIds = (#actMeta.officialIds > 0) and actMeta.officialIds or nil
        postRes.activityAllNames = (#actMeta.names > 0) and table.concat(actMeta.names, ", ") or activity
        postRes.categoryKind = self.activeCategory
        postRes.newPlayerFriendly = (self.roles.GUIDE == true)
        postRes.soloRoles = (mode == "LFG") and {
            TANK = self.roles.TANK == true,
            HEALER = self.roles.HEALER == true,
            DPS = self.roles.DPS == true,
        } or nil
    end

    self._editingListing = nil
    self._hasSearchedThisSession = true
    if postOk and type(postRes) == "table" then
        self.pendingSelectKey = "LFG:" .. tostring(postRes.lookupKey or postRes.displayName or "")
    end

    if self.broadcastMode == "GCHAT" and ns.Clan and ns.Clan.OpenGuildChatLFG then
        ns.Clan:OpenGuildChatLFG(mode, role, activity, 0, note)
    end

    if postOk then
        ns:Print(L["Your private listing (%s) is now active in SocialCentral."]:format(activity))
    end

    if type(actMeta.officialIds) == "table" and #actMeta.officialIds > 0 then
        self:SyncBrowseFilterToActiveListing(true, actMeta.officialIds, self.activeCategory)
        self:SaveBrowseFilters()
    else
        self._syncedActiveListingSig = nil
        self._autoFilteredByActiveListing = false
        self.categoryFilter = self.activeCategory or "ALL"
        wipe(self.browseActivityFilter)
        self:SaveBrowseFilters()
    end
    self._hasSearchedThisSession = true
    self.viewMode = "browse"
    self:RefreshData()
end

function LFGFrameTab:ComputeBrowseRows()
    if self.LoadSavedBrowseFilters and not self._filtersLoadedFromDb then
        self:LoadSavedBrowseFilters(false)
    end
    self.dungeonsOnly = (self.categoryFilter == "DUNGEONS")
    if not self._hasSearchedThisSession then
        self.selectedKey = nil
        self.selectedItem = nil
        return {}, L["Select a filter above or click Refresh to search active groups in this session."], nil
    end

    local sCfg = ns.db and ns.db.settings
    local advRoleActive = (ns.LFG ~= nil) and (
        (ns.LFG.GetRoleState and (ns.LFG:GetRoleState("TANK") ~= 0 or ns.LFG:GetRoleState("HEALER") ~= 0 or ns.LFG:GetRoleState("DPS") ~= 0))
        or (ns.LFG.GetListingType and ns.LFG:GetListingType() == "SOLO")
    )
    local effectiveRoleFilter = advRoleActive and "ALL" or self.roleFilter
    local rawRows = (ns.Clan and ns.Clan.GetClanLFGList)
        and ns.Clan:GetClanLFGList(self.query, self.dungeonsOnly, self.sourceFilter, effectiveRoleFilter)
        or {}

    local hideAvoidEnemy = sCfg and sCfg.lfgHideAvoidEnemy == true
    local hideSavedLockouts = sCfg and sCfg.lfgHideSavedLockouts == true
    local hideFullGroups = (not sCfg) or sCfg.lfgHideFullGroups ~= false
    local useTypeSections = (not sCfg) or sCfg.lfgSplitGroupsAndPlayers ~= false
    local useBulletin = (not sCfg) or sCfg.lfgBulletinMode ~= false
    local activeLockouts = (ns.Clan and ns.Clan.GetSavedLockouts) and ns.Clan:GetSavedLockouts(true) or {}

    local rows = {}
    local foundSelected = nil
    local foundPendingItem = nil
    local foundPendingIdx = nil
    local pendingTarget = self.pendingSelectKey
    self.pendingSelectKey = nil
    for _, item in ipairs(rawRows) do
        local suppressed = false
        local lkKey = item.lookupKey or item.displayName
        local sMeta = Store and (Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(lkKey) or (Store.GetSocialMeta and Store:GetSocialMeta(lkKey)))
        item._isGoodFlag = (sMeta and sMeta.flag == "GOOD") == true
        if hideAvoidEnemy and not item.isSelf then
            if (sMeta and sMeta.flag == "AVOID") or item.hasAvoidSignup == true or item.isEnemyGuild == true then
                suppressed = true
            end
        end
        item._lockoutInfo = GetActivityLockout(item, activeLockouts)
        if not suppressed and hideSavedLockouts and not item.isSelf and item._lockoutInfo ~= nil then
            suppressed = true
        end
        if not suppressed and hideFullGroups and IsItemFullForBrowse(item, effectiveRoleFilter) then
            suppressed = true
        end
        local suitOk, knownRange = CheckActivityLevelSuitability(item)
        item._idealLevel = (knownRange and suitOk) == true
        local isFavItem = false
        if ns.LFG and ns.LFG.IsFavoriteActivity then
            local bKey, bLbl = ResolveCanonicalActivityBucket(item)
            local firstActId = (type(item.activityIds) == "table" and item.activityIds[1]) or item.activityId
            isFavItem = ns.LFG:IsFavoriteActivity(bKey or bLbl, firstActId) == true
        end
        if self.suitableLevelOnly and knownRange and not suitOk and not item.isSelf and not isFavItem and next(self.browseActivityFilter or {}) == nil then
            suppressed = true
        end
        if (not suppressed) and ns.LFG and ns.LFG.MatchesAdvancedFilters and not ns.LFG:MatchesAdvancedFilters(item) then
            suppressed = true
        end
        if (not suppressed) and MatchesCategoryFilter(item, self.categoryFilter) and MatchesBrowseActivityFilter(item) then
            item._displayActivity = nil
            if next(self.browseActivityFilter or {}) ~= nil and type(item.activityIds) == "table" and #item.activityIds > 1 then
                for _, entry in pairs(self.browseActivityFilter) do
                    if entry and entry.officialId then
                        local matched = false
                        for ai = 1, #item.activityIds do
                            if item.activityIds[ai] == entry.officialId then
                                matched = true
                                break
                            end
                        end
                        if matched then
                            item._displayActivity = (entry.label or item.activity or "") .. " (+" .. tostring(#item.activityIds - 1) .. ")"
                            break
                        end
                    end
                end
            end
            rows[#rows + 1] = item
            local idKey = GetItemIdentityKey(item)
            if pendingTarget and not foundPendingItem and (item.lookupKey == pendingTarget or idKey == pendingTarget) then
                self.selectedKey = idKey
                foundPendingItem = item
                foundPendingIdx = #rows
                foundSelected = item
            elseif self.selectedKey and idKey == self.selectedKey then
                foundSelected = item
            end
        end
    end

    if #rows > 0 and ns.LFG and ns.LFG.SortRows then
        ns.LFG:SortRows(rows)
    end

    if useTypeSections and #rows > 0 then
        rows = BuildGroupedTypeSectionRows(rows, self.collapsedBuckets, foundPendingItem)
        if foundPendingItem then
            foundPendingIdx = nil
            for ri = 1, #rows do
                if rows[ri] == foundPendingItem then
                    foundPendingIdx = ri
                    break
                end
            end
        end
    elseif useBulletin and #rows > 0 then
        rows = BuildBulletinBoardRows(rows, self.collapsedBuckets, foundPendingItem)
        if foundPendingItem then
            foundPendingIdx = nil
            for ri = 1, #rows do
                if rows[ri] == foundPendingItem then
                    foundPendingIdx = ri
                    break
                end
            end
        end
    end
    if self.selectedKey then
        if foundSelected then
            self.selectedItem = foundSelected
        else
            self.selectedKey = nil
            self.selectedItem = nil
        end
    end

    local isSearchingOfficial = ns.Clan and (ns.Clan._officialSearchPendingUntil or 0) > GetTime()
    local myCharLvl = (ns.Safe and ns.Safe.Number(UnitLevel and UnitLevel("player"))) or 60
    local emptyMsg
    if isSearchingOfficial and #rows == 0 then
        emptyMsg = L["Searching official Blizzard, guild & public groups..."]
    elseif self.sourceFilter == "OFFICIAL" then
        emptyMsg = L["No official Blizzard Group Finder listings detected yet."]
    elseif self.sourceFilter == "FRIENDS" then
        emptyMsg = L["No groups from Friends or Watchlist right now."]
    elseif self.sourceFilter == "ALLY" then
        emptyMsg = L["No Allied Clan groups detected yet."]
    elseif self.sourceFilter == "TRUSTED" then
        emptyMsg = L["No groups from Guild, Allies, Friends, or Recent Companions right now."]
    elseif self.sourceFilter == "SC_USERS" then
        emptyMsg = L["No active SocialCentral [SC] group listings detected right now."]
    elseif self.categoryFilter == "ALL" and (not self.query or self.query == "") then
        emptyMsg = L["Select a category or filter above to browse groups from everyone, Friends, Guild, and Allies — or click 'List Group' below to post."]
    elseif #rows == 0 and myCharLvl > 0 and myCharLvl < 13 and self.categoryFilter == "DUNGEONS" then
        emptyMsg = L["Your character is Lv %d — first dungeons (Ragefire Chasm / Hall of Thanes) start at Lv 13.\n\nSwitch Category to 'All Categories' or 'Quests & Zones', uncheck 'My Level', or use '/LookingForGroup' to see all groups now."]:format(myCharLvl)
    else
        emptyMsg = L["No groups found matching your filters yet. Try loosening role/level filters or click Refresh."]
    end

    return rows, emptyMsg, foundPendingIdx
end

function LFGFrameTab:GetSharedBrowseData()
    local rows, emptyMsg = self:ComputeBrowseRows()
    return rows, emptyMsg
end

function LFGFrameTab:UpdateQuickMicroBarVisuals()
    local c = self.controls
    if not c then return end
    if c.roleChipBtns then
        for _, rb in ipairs(c.roleChipBtns) do
            local st = (ns.LFG and ns.LFG.GetRoleState) and ns.LFG:GetRoleState(rb._roleId) or 0
            if Theme and Theme.ApplyBackdrop then
                Theme:ApplyBackdrop(rb, "inset")
            end
            if rb.fillTex then
                if st == 1 then
                    rb.fillTex:SetColorTexture(0.10, 0.36, 0.20, 0.85)
                    rb.fillTex:Show()
                elseif st == 2 then
                    rb.fillTex:SetColorTexture(0.36, 0.27, 0.08, 0.85)
                    rb.fillTex:Show()
                else
                    rb.fillTex:Hide()
                end
            end
            if rb.labelFs then
                if st == 1 then
                    rb.labelFs:SetText("|cff56f07e+|r |cffffffff" .. rb._roleLabel .. "|r")
                elseif st == 2 then
                    rb.labelFs:SetText("|cffffd24d=|r |cffffffff" .. rb._roleLabel .. "|r")
                else
                    rb.labelFs:SetText("|cffc2c8d2" .. rb._roleLabel .. "|r")
                end
            end
            if rb.Icon then
                rb.Icon:SetDesaturated(false)
                rb.Icon:SetAlpha(st > 0 and 1.0 or 0.84)
            end
            if rb.SetBackdropBorderColor then
                if st == 1 then
                    rb:SetBackdropBorderColor(0.26, 0.92, 0.48, 0.98)
                elseif st == 2 then
                    rb:SetBackdropBorderColor(1.0, 0.80, 0.25, 0.98)
                else
                    rb:SetBackdropBorderColor(0.44, 0.38, 0.30, 0.65)
                end
            end
        end
    end
    if c.drawerToggleBtn then
        local isOpen = (ns.LFG and ns.LFG.IsSideDrawerShown and ns.LFG:IsSideDrawerShown()) == true
        local advCnt = (ns.LFG and ns.LFG.CountActiveAdvancedFilters) and ns.LFG:CountActiveAdvancedFilters() or 0
        local dLbl
        if isOpen then
            dLbl = "|cff3fb950« " .. L["Close"] .. "|r"
        elseif advCnt > 0 then
            dLbl = L["Panel"] .. " (" .. advCnt .. ") »"
        else
            dLbl = L["Filters »"]
        end
        if c.drawerToggleBtn.SetText then c.drawerToggleBtn:SetText(dLbl) end
        AutoFitNativeButton(c.drawerToggleBtn, 84, 10, 106)
        StyleNativeButton(c.drawerToggleBtn, isOpen or advCnt > 0)
    end
end

function LFGFrameTab:RefreshData()
    if not (self.active and self.subPanel and self.subPanel:IsShown()) then
        return
    end
    local c = self.controls
    local mode = self.viewMode or "categories"

    if mode == "categories" then
        self:UpdateViewLayout()
        if c and c.categoryButtons then
            local allRows = (ns.Clan and ns.Clan.GetClanLFGList) and ns.Clan:GetClanLFGList(nil, false, "ALL", "ALL") or {}
            local gQuests = (ns.Clan and ns.Clan.GetActiveGroupQuests) and ns.Clan:GetActiveGroupQuests() or {}
            for _, catBtn in ipairs(c.categoryButtons) do
                if catBtn and catBtn.countFs and catBtn._catId then
                    local cnt = 0
                    for ri = 1, #allRows do
                        if MatchesCategoryFilter(allRows[ri], catBtn._catId) then
                            cnt = cnt + 1
                        end
                    end
                    local parts = {}
                    if catBtn._catId == "QUESTS" and #gQuests > 0 then
                        parts[#parts + 1] = "|cff72c6ff" .. L["Group Quests (%d)"]:format(#gQuests) .. "|r"
                    end
                    if cnt > 0 then
                        local gLbl = (cnt == 1) and L["%d group"]:format(cnt) or L["%d groups"]:format(cnt)
                        parts[#parts + 1] = "|cff3fb950" .. gLbl .. "|r"
                    end
                    catBtn.countFs:SetText(table.concat(parts, "  ·  "))
                end
            end
        end
        self:SyncAllEmbeddedTabStates()
        return
    elseif mode == "activities" then
        self._cachedActivityLockouts = (ns.Clan and ns.Clan.GetSavedLockouts) and ns.Clan:GetSavedLockouts(true) or {}
        if c.modeDropdown and c.modeDropdown.RefreshDropdownLabel then
            c.modeDropdown:RefreshDropdownLabel()
        end
        if c.playstyleDropdown and c.playstyleDropdown.RefreshDropdownLabel then
            c.playstyleDropdown:RefreshDropdownLabel()
        end
        if c.broadcastDropdown and c.broadcastDropdown.RefreshDropdownLabel then
            c.broadcastDropdown:RefreshDropdownLabel()
        end
        if c.allLevelsCheck then
            c.allLevelsCheck:SetChecked(self.showAllLevels == true)
        end
        if c.masterCatLabel then
            local _, selCount = self:HasAnySelectedActivity()
            local baseLbl = GetCategoryLabel(self.activeCategory)
            c.masterCatLabel:SetText((selCount and selCount > 0) and (baseLbl .. " |cff3fb950(" .. tostring(selCount) .. ")|r") or baseLbl)
        end

        local items = self:GetFilteredCategoryActivities(self.activeCategory, self.showAllLevels)
        local allChecked = (#items > 0)
        for i = 1, #items do
            if not self.selectedActivities[items[i].id] then
                allChecked = false
                break
            end
        end
        if c.masterCatCheck then
            c.masterCatCheck:SetChecked(allChecked)
        end
        if self.activityList and self.activityList.SetData then
            self.activityList:SetData(items, nil, false)
        end
        self:UpdateViewLayout()
        self:SyncAllEmbeddedTabStates()
        return
    end

    if self:SyncBrowseFilterToActiveListing(false) then
        self:SaveBrowseFilters()
        self:TriggerOfficialBrowseSearch(false)
    end
    self.dungeonsOnly = (self.categoryFilter == "DUNGEONS")
    if c.catDropdown and c.catDropdown.RefreshDropdownLabel then
        c.catDropdown:RefreshDropdownLabel()
    end
    if c.filterDropdown and c.filterDropdown.RefreshDropdownLabel then
        c.filterDropdown:RefreshDropdownLabel()
    end
    if c.activityDropdown and c.activityDropdown.RefreshDropdownLabel then
        c.activityDropdown:RefreshDropdownLabel()
    end
    if c.suitLevelBtn then
        StyleNativeButton(c.suitLevelBtn, self.suitableLevelOnly == true)
    end
    local sCfg = ns.db and ns.db.settings
    if c.bulletinToggleBtn then
        StyleNativeButton(c.bulletinToggleBtn, (sCfg ~= nil) and (sCfg.lfgSplitGroupsAndPlayers == false) and (sCfg.lfgBulletinMode ~= false))
    end
    if c.browseQuickBtn and c.browseQuickBtn.RefreshTheme then
        c.browseQuickBtn:RefreshTheme()
    end
    if self.UpdateQuickFilterVisuals then
        self:UpdateQuickFilterVisuals()
    end
    if self.UpdateQuickMicroBarVisuals then
        self:UpdateQuickMicroBarVisuals()
    end
    if ns.LFG and ns.LFG.IsSideDrawerShown and ns.LFG:IsSideDrawerShown() and ns.LFG.RefreshSideDrawer then
        ns.LFG:RefreshSideDrawer(self)
    end
    if c.searchBox and c.searchBox.HasFocus and not c.searchBox:HasFocus() then
        local qTxt = self.query or ""
        if (c.searchBox:GetText() or "") ~= qTxt then
            c.searchBox:SetText(qTxt)
        end
    end

    if not (self.list and self.list.SetData) then return end

    local rows, emptyMsg, foundPendingIdx = self:ComputeBrowseRows()
    self:UpdateViewLayout()
    if foundPendingIdx and self.list then
        self.list.offset = math.max(0, foundPendingIdx - 1) * (self.list.rowHeight or 68)
    end
    self.list:SetData(rows, emptyMsg, false)
    SyncRowSelectionVisuals()
    self:SyncAllEmbeddedTabStates()
end

function LFGFrameTab:UpdateQuickFilterVisuals()
end

local function PopulateWatchedActivitiesSubmenu(watchSub)
    if not watchSub then return end
    if watchSub.CreateTitle then
        watchSub:CreateTitle(L["LFG Watchers in Official Chat"])
    end
    local primary = {}
    local others = {}
    local seen = {}
    local cats = { "DUNGEONS", "RAIDS" }
    for ci = 1, #cats do
        local opts = GetBrowseActivityOptions(cats[ci])
        for oi = 1, #opts do
            local opt = opts[oi]
            if opt and opt.key and not seen[opt.key] then
                seen[opt.key] = true
                local isW = LFGFrameTab:IsActivityWatched(opt.key, opt.label)
                if isW or opt.isSuitable then
                    primary[#primary + 1] = opt
                else
                    others[#others + 1] = opt
                end
            end
        end
    end

    local function addWatcherChoice(menuParent, opt)
        local key = opt.key
        local lbl = opt.label
        local lvlTxt = (opt.hasKnownRange and opt.minLvl and opt.maxLvl)
            and string.format(" |cff9da7b5[%d-%d]|r", opt.minLvl, opt.maxLvl)
            or ""
        if menuParent.CreateCheckbox then
            menuParent:CreateCheckbox(lbl .. lvlTxt, function()
                return LFGFrameTab:IsActivityWatched(key, lbl)
            end, function()
                LFGFrameTab:ToggleActivityWatched(key, lbl)
            end)
        else
            menuParent:CreateButton(lbl .. lvlTxt, function()
                LFGFrameTab:ToggleActivityWatched(key, lbl)
            end)
        end
    end

    for i = 1, #primary do
        addWatcherChoice(watchSub, primary[i])
    end
    if #others > 0 then
        local allSub = watchSub:CreateButton(L["All Dungeons & Raids"])
        for i = 1, #others do
            addWatcherChoice(allSub, others[i])
        end
    end
    if watchSub.CreateDivider then watchSub:CreateDivider() end
    watchSub:CreateButton(L["Clear All Watchers"], function()
        LFGFrameTab:ConfirmClearWatchedActivities()
    end)
end

local function GetLfgQuickStatusState()
    local s = ns.db and ns.db.settings
    if s and s.embedLfgWindow == false then return "off" end
    if s and s.embedLfgMirrorBar == false then return "partial" end
    return "active"
end

local function GetLfgQuickTooltipLines()
    local s = ns.db and ns.db.settings
    local mirrorOn = not s or s.embedLfgMirrorBar ~= false
    local bullOn = (s ~= nil) and (s.lfgSplitGroupsAndPlayers == false) and (s.lfgBulletinMode ~= false)
    local watchOn = not s or s.lfgWatchersEnabled ~= false
    local watchCnt = LFGFrameTab:GetWatchedActivitiesCount()
    return {
        { left = L["Tab 1 Mirror Bar"], right = mirrorOn and ("|cff3fb950" .. L["On"] .. "|r") or ("|cff8b949e" .. L["Off"] .. "|r") },
        { left = L["Bulletin Board Mode"], right = bullOn and ("|cff3fb950" .. L["On"] .. "|r") or ("|cff8b949e" .. L["Off"] .. "|r") },
        { left = L["LFG Watchers in Official Chat"], right = watchOn and ("|cff3fb950" .. L["On"] .. " (" .. tostring(watchCnt) .. ")|r") or ("|cff8b949e" .. L["Off"] .. "|r") },
        L["Right-click or click to configure SocialCentral LFG features or disable Group Finder (I) integration."],
    }
end

local function BuildLfgQuickOptionsMenu(root, includeMirrorOption)
    if root.CreateTitle then
        root:CreateTitle("SocialCentral — " .. L["Group Finder (I)"])
    end
    if root.CreateCheckbox then
        root:CreateCheckbox(L["Group by Dungeon (Bulletin Board)"], function()
            local s = ns.db and ns.db.settings
            return (s ~= nil) and (s.lfgSplitGroupsAndPlayers == false) and (s.lfgBulletinMode ~= false)
        end, function()
            if ns.db and ns.db.settings then
                LFGFrameTab._hasSearchedThisSession = true
                local curBull = (ns.db.settings.lfgSplitGroupsAndPlayers == false) and (ns.db.settings.lfgBulletinMode ~= false)
                local targetBull = not curBull
                ns.db.settings.lfgBulletinMode = targetBull
                ns.db.settings.lfgSplitGroupsAndPlayers = not targetBull
                LFGFrameTab:RefreshData()
                if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                ns:Emit("LFG_BROWSE_STATE_CHANGED")
            end
        end)
        root:CreateCheckbox(L["Hide Full Groups"], function()
            local s = ns.db and ns.db.settings
            return (not s) or s.lfgHideFullGroups ~= false
        end, function()
            if ns.db and ns.db.settings then
                LFGFrameTab._hasSearchedThisSession = true
                ns.db.settings.lfgHideFullGroups = not (ns.db.settings.lfgHideFullGroups ~= false)
                LFGFrameTab:RefreshData()
                if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                ns:Emit("LFG_BROWSE_STATE_CHANGED")
            end
        end)
        root:CreateCheckbox(L["Hide Saved Lockouts"], function()
            local s = ns.db and ns.db.settings
            return s and s.lfgHideSavedLockouts == true
        end, function()
            if ns.db and ns.db.settings then
                LFGFrameTab._hasSearchedThisSession = true
                ns.db.settings.lfgHideSavedLockouts = not (ns.db.settings.lfgHideSavedLockouts == true)
                LFGFrameTab:RefreshData()
                if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                ns:Emit("LFG_BROWSE_STATE_CHANGED")
            end
        end)
        root:CreateCheckbox(L["Hide Avoid / Enemy"], function()
            local s = ns.db and ns.db.settings
            return s and s.lfgHideAvoidEnemy == true
        end, function()
            if ns.db and ns.db.settings then
                LFGFrameTab._hasSearchedThisSession = true
                ns.db.settings.lfgHideAvoidEnemy = not (ns.db.settings.lfgHideAvoidEnemy == true)
                LFGFrameTab:RefreshData()
                if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                ns:Emit("LFG_BROWSE_STATE_CHANGED")
            end
        end)
        root:CreateCheckbox(L["LFG Watchers in Official Chat"], function()
            local s = ns.db and ns.db.settings
            return (not s) or s.lfgWatchersEnabled ~= false
        end, function()
            if ns.db and ns.db.settings then
                ns.db.settings.lfgWatchersEnabled = not (ns.db.settings.lfgWatchersEnabled ~= false)
                if ns.Clan and ns.Clan.SyncOfficialLfgEvents then
                    ns.Clan:SyncOfficialLfgEvents()
                end
                LFGFrameTab:RefreshData()
                if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                ns:Emit("LFG_BROWSE_STATE_CHANGED")
            end
        end)
    end
    local watchSub = root:CreateButton(L["Watched Dungeons (%d)"]:format(LFGFrameTab:GetWatchedActivitiesCount()))
    PopulateWatchedActivitiesSubmenu(watchSub)
    root:CreateButton(L["Edit Apply Whisper Template (/w)..."], function()
        LFGFrameTab:OpenWhisperTemplateModal()
    end)
    if includeMirrorOption and root.CreateCheckbox then
        if root.CreateDivider then root:CreateDivider() end
        root:CreateCheckbox(L["Show Official Tab 1 Mirror Bar"], function()
            local s = ns.db and ns.db.settings
            return not s or s.embedLfgMirrorBar ~= false
        end, function()
            if ns.db and ns.db.settings then
                ns.db.settings.embedLfgMirrorBar = not (ns.db.settings.embedLfgMirrorBar ~= false)
            end
            LFGFrameTab:UpdateNativeBridgeBar()
            LFGFrameTab:RefreshData()
            if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
        end)
    end
    if root.CreateDivider then root:CreateDivider() end
    root:CreateButton(L["Disable in this window"], function()
        if ns.db and ns.db.settings then
            ns.db.settings.embedLfgWindow = false
        end
        LFGFrameTab:HideSubPanel(false)
        LFGFrameTab:UpdateNativeBridgeBar()
        ns:Emit("SETTINGS_UPDATED")
        ns:Emit("CLAN_UPDATED")
        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
        ns:Print("%s", L["Disabled in this window. Re-enable anytime in Settings (/sc)."])
    end)
    root:CreateButton(L["Settings"], function()
        if ns.Settings and ns.Settings.Open then ns.Settings:Open() end
    end)
end

function LFGFrameTab:PopulateCategoryMenu(root, onChanged)
    if not root then return end
    if root.CreateTitle then
        root:CreateTitle(L["Category"])
    end
    for _, opt in ipairs(CATEGORY_OPTIONS) do
        AddDropdownMenuChoice(root, L[opt.labelKey], function()
            return LFGFrameTab.categoryFilter == opt.id
        end, function()
            LFGFrameTab._hasSearchedThisSession = true
            LFGFrameTab.categoryFilter = opt.id
            wipe(LFGFrameTab.browseActivityFilter)
            local s = ns.db and ns.db.settings
            local savedMap = s and type(s.lfgBrowseSelectedActivities) == "table" and s.lfgBrowseSelectedActivities[opt.id] or nil
            if opt.id ~= "ALL" then
                if type(savedMap) == "table" then
                    local opts = GetBrowseActivityOptions(opt.id)
                    for i = 1, #opts do
                        if savedMap[opts[i].key] then
                            LFGFrameTab.browseActivityFilter[opts[i].key] = opts[i]
                        end
                    end
                elseif savedMap == nil and LFGFrameTab.suitableLevelOnly then
                    LFGFrameTab:ApplyIdealActivitiesForCategory(opt.id, true)
                end
            end
            LFGFrameTab:SaveBrowseFilters()
            LFGFrameTab:TriggerOfficialBrowseSearch(true)
            LFGFrameTab:RefreshData()
            ns:Emit("LFG_BROWSE_STATE_CHANGED")
            if onChanged then onChanged() end
        end)
    end
end

function LFGFrameTab:PopulateActivityMenu(root, onChanged)
    if not root then return end
    local function FireChange()
        LFGFrameTab:SaveBrowseFilters()
        LFGFrameTab:TriggerOfficialBrowseSearch(true)
        LFGFrameTab:RefreshData()
        ns:Emit("LFG_BROWSE_STATE_CHANGED")
        if onChanged then onChanged() end
    end
    local catLbl = GetCategoryLabel(LFGFrameTab.categoryFilter)
    if root.CreateTitle then
        root:CreateTitle(catLbl)
    end
    local hasOfficialActive = C_LFGList and C_LFGList.HasActiveEntryInfo and Safe.Value(Safe.Call(C_LFGList.HasActiveEntryInfo)) == true
    if hasOfficialActive or LFGFrameTab:HasSelfActiveListing() then
        root:CreateButton(L["My Active Listing"], function()
            LFGFrameTab._hasSearchedThisSession = true
            LFGFrameTab:SyncBrowseFilterToActiveListing(true)
            FireChange()
        end)
    end
    local myLvl = (ns.Safe and ns.Safe.Number(UnitLevel and UnitLevel("player"))) or 60
    if myLvl > 0 and LFGFrameTab.categoryFilter ~= "ALL" then
        root:CreateButton(L["Select Ideal for Lv %d"]:format(myLvl), function()
            LFGFrameTab._hasSearchedThisSession = true
            LFGFrameTab.suitableLevelOnly = true
            LFGFrameTab:ApplyIdealActivitiesForCategory(LFGFrameTab.categoryFilter, true)
            FireChange()
        end)
    end
    root:CreateButton(L["Clear Activity Filter (All)"], function()
        LFGFrameTab._hasSearchedThisSession = true
        wipe(LFGFrameTab.browseActivityFilter)
        FireChange()
    end)
    if root.CreateCheckbox then
        root:CreateCheckbox(L["Show All Levels"], function()
            return LFGFrameTab.suitableLevelOnly == false
        end, function()
            LFGFrameTab._hasSearchedThisSession = true
            LFGFrameTab.suitableLevelOnly = not (LFGFrameTab.suitableLevelOnly == true)
            if not LFGFrameTab.suitableLevelOnly then
                wipe(LFGFrameTab.browseActivityFilter)
            else
                LFGFrameTab:ApplyIdealActivitiesForCategory(LFGFrameTab.categoryFilter, true)
            end
            FireChange()
        end)
    end
    local watchSub = root:CreateButton(L["Watched Dungeons (%d)"]:format(LFGFrameTab:GetWatchedActivitiesCount()))
    PopulateWatchedActivitiesSubmenu(watchSub)
    local opts = GetBrowseActivityOptions(LFGFrameTab.categoryFilter)
    if #opts > 0 then
        local favSub = root:CreateButton(STAR_TEX .. " " .. L["Favorite Activities"])
        if favSub then
            if favSub.CreateTitle then favSub:CreateTitle(catLbl) end
            for fi = 1, #opts do
                local fOpt = opts[fi]
                if favSub.CreateCheckbox then
                    favSub:CreateCheckbox(fOpt.label, function()
                        return (ns.LFG and ns.LFG.IsFavoriteActivity and ns.LFG:IsFavoriteActivity(fOpt.key, fOpt.officialId)) == true
                    end, function()
                        if ns.LFG and ns.LFG.ToggleFavoriteActivity then
                            ns.LFG:ToggleFavoriteActivity(fOpt.key, fOpt.officialId)
                            LFGFrameTab:InvalidateBrowseActivityCache()
                            FireChange()
                        end
                    end)
                else
                    AddDropdownMenuChoice(favSub, fOpt.label, function()
                        return (ns.LFG and ns.LFG.IsFavoriteActivity and ns.LFG:IsFavoriteActivity(fOpt.key, fOpt.officialId)) == true
                    end, function()
                        if ns.LFG and ns.LFG.ToggleFavoriteActivity then
                            ns.LFG:ToggleFavoriteActivity(fOpt.key, fOpt.officialId)
                            LFGFrameTab:InvalidateBrowseActivityCache()
                            FireChange()
                        end
                    end)
                end
            end
        end
    end
    if root.CreateDivider then root:CreateDivider() end
    for i = 1, #opts do
        local opt = opts[i]
        local isFav = (opt.isFavorite == true) or (ns.LFG and ns.LFG.IsFavoriteActivity and ns.LFG:IsFavoriteActivity(opt.key, opt.officialId)) == true
        if not LFGFrameTab.suitableLevelOnly or opt.isSuitable or isFav then
            local lvlTxt = (opt.hasKnownRange and opt.minLvl and opt.maxLvl)
                and string.format(" [%d-%d]", opt.minLvl, opt.maxLvl)
                or ""
            local itemLbl = (opt.hasKnownRange and opt.isSuitable)
                and ("|cff3fb950" .. opt.label .. lvlTxt .. "|r")
                or (opt.label .. "|cff9da7b5" .. lvlTxt .. "|r")
            if isFav then
                itemLbl = STAR_TEX .. " " .. itemLbl
            end
            if LFGFrameTab:IsActivityWatched(opt.key, opt.label) then
                itemLbl = itemLbl .. " |cff3fb950[" .. L["Watched"] .. "]|r"
            end
            local key = opt.key
            if root.CreateCheckbox then
                root:CreateCheckbox(itemLbl, function()
                    return LFGFrameTab.browseActivityFilter[key] ~= nil
                end, function()
                    LFGFrameTab._hasSearchedThisSession = true
                    if LFGFrameTab.browseActivityFilter[key] then
                        LFGFrameTab.browseActivityFilter[key] = nil
                    else
                        LFGFrameTab.browseActivityFilter[key] = opt
                    end
                    FireChange()
                end)
            else
                AddDropdownMenuChoice(root, itemLbl, function()
                    return LFGFrameTab.browseActivityFilter[key] ~= nil
                end, function()
                    LFGFrameTab._hasSearchedThisSession = true
                    if LFGFrameTab.browseActivityFilter[key] then
                        LFGFrameTab.browseActivityFilter[key] = nil
                    else
                        LFGFrameTab.browseActivityFilter[key] = opt
                    end
                    FireChange()
                end)
            end
        end
    end
end

function LFGFrameTab:GetCategoryLabel(catId, compact)
    return GetCategoryLabel(catId, compact)
end

function LFGFrameTab:GetBrowseFilterDropdownLabel()
    return GetSourceFilterDropdownLabel(self.sourceFilter)
end

function LFGFrameTab:PopulateBrowseFilterMenu(root, onChanged)
    if not root then return end
    local function EmitAndRefresh(triggerOfficial)
        LFGFrameTab._hasSearchedThisSession = true
        LFGFrameTab:SaveBrowseFilters()
        if triggerOfficial then
            LFGFrameTab:TriggerOfficialBrowseSearch(true)
        end
        LFGFrameTab:RefreshData()
        ns:Emit("LFG_BROWSE_STATE_CHANGED")
        if onChanged then onChanged() end
    end
    if root.CreateTitle then
        root:CreateTitle(L["Clans & Allies LFG"])
    end
    local showGuildOpts = (not ns.Compat or not ns.Compat.ShouldShowGuildFeatures) or ns.Compat.ShouldShowGuildFeatures()
    for _, opt in ipairs(SOURCE_FILTERS) do
        if (opt.id ~= "CLAN" and opt.id ~= "ALLY") or showGuildOpts then
            AddDropdownMenuChoice(root, L[opt.dropdownKey], function()
                return LFGFrameTab.sourceFilter == opt.id
            end, function()
                LFGFrameTab.sourceFilter = opt.id
                EmitAndRefresh(true)
            end)
        end
    end
    if root.CreateDivider then root:CreateDivider() end
    if root.CreateTitle then root:CreateTitle(L["Filter by Role"]) end
    local recRoles = (ns.Clan and ns.Clan.GetRecommendedRolesForCharacter) and ns.Clan:GetRecommendedRolesForCharacter() or nil
    local roleChoices = {
        { id = "ALL", label = L["All Roles"] },
    }
    if recRoles then
        roleChoices[#roleChoices + 1] = {
            id = "MINE",
            label = "|cff3fb950" .. L["My Class/Race Roles"] .. "|r (" .. (recRoles.rolesLabel or L["DPS"]) .. ")",
        }
    end
    for _, baseOpt in ipairs({
        { id = "TANK", label = L["Tank"] },
        { id = "HEALER", label = L["Healer"] },
        { id = "DPS", label = L["DPS"] },
    }) do
        local lbl = baseOpt.label
        if recRoles and recRoles.recommended and recRoles.recommended[baseOpt.id] then
            lbl = lbl .. " |cff3fb950(" .. L["Recommended"] .. ")|r"
        end
        roleChoices[#roleChoices + 1] = { id = baseOpt.id, label = lbl }
    end
    for _, rOpt in ipairs(roleChoices) do
        local rid = rOpt.id
        AddDropdownMenuChoice(root, rOpt.label, function()
            return LFGFrameTab.roleFilter == rid
        end, function()
            LFGFrameTab.roleFilter = rid
            EmitAndRefresh(false)
        end)
    end
    if root.CreateDivider then root:CreateDivider() end
    if root.CreateCheckbox then
        root:CreateCheckbox(L["Group by Dungeon (Bulletin Board)"], function()
            local s = ns.db and ns.db.settings
            return (s ~= nil) and (s.lfgSplitGroupsAndPlayers == false) and (s.lfgBulletinMode ~= false)
        end, function()
            if ns.db and ns.db.settings then
                local curBull = (ns.db.settings.lfgSplitGroupsAndPlayers == false) and (ns.db.settings.lfgBulletinMode ~= false)
                local targetBull = not curBull
                ns.db.settings.lfgBulletinMode = targetBull
                ns.db.settings.lfgSplitGroupsAndPlayers = not targetBull
                EmitAndRefresh(false)
                if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
            end
        end)
        root:CreateCheckbox(L["Hide Full Groups"], function()
            local s = ns.db and ns.db.settings
            return (not s) or s.lfgHideFullGroups ~= false
        end, function()
            if ns.db and ns.db.settings then
                ns.db.settings.lfgHideFullGroups = not (ns.db.settings.lfgHideFullGroups ~= false)
                EmitAndRefresh(false)
                if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
            end
        end)
        root:CreateCheckbox(L["Hide Saved Lockouts"], function()
            return ns.db and ns.db.settings and ns.db.settings.lfgHideSavedLockouts == true
        end, function()
            if ns.db and ns.db.settings then
                ns.db.settings.lfgHideSavedLockouts = not (ns.db.settings.lfgHideSavedLockouts == true)
                EmitAndRefresh(false)
                if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
            end
        end)
        root:CreateCheckbox(L["Suitable for My Level"], function()
            return LFGFrameTab.suitableLevelOnly == true
        end, function()
            LFGFrameTab.suitableLevelOnly = not (LFGFrameTab.suitableLevelOnly == true)
            if LFGFrameTab.suitableLevelOnly then
                if LFGFrameTab.categoryFilter ~= "ALL" and next(LFGFrameTab.browseActivityFilter) == nil then
                    LFGFrameTab:ApplyIdealActivitiesForCategory(LFGFrameTab.categoryFilter, true)
                end
            else
                wipe(LFGFrameTab.browseActivityFilter)
            end
            EmitAndRefresh(false)
        end)
        root:CreateCheckbox(L["Hide Avoid / Enemy"], function()
            return ns.db and ns.db.settings and ns.db.settings.lfgHideAvoidEnemy == true
        end, function()
            if ns.db and ns.db.settings then
                ns.db.settings.lfgHideAvoidEnemy = not (ns.db.settings.lfgHideAvoidEnemy == true)
                EmitAndRefresh(false)
            end
        end)
    end
    root:CreateButton(L["Edit Apply Whisper Template (/w)..."], function()
        LFGFrameTab:OpenWhisperTemplateModal()
    end)
    root:CreateButton(L["List Group"], function()
        if onChanged then
            LFGFrameTab:OpenOfficialModule("lfg")
        else
            LFGFrameTab.viewMode = "categories"
            LFGFrameTab:RefreshData()
        end
    end)
    local canManageMenu = (not Compat.CanManageGroupListing) or Compat.CanManageGroupListing()
    local bcMenuBtn = root:CreateButton(canManageMenu and L["Broadcast Current Group"] or L["Broadcast Current Group (Leader Only)"], function()
        if ns.Clan and ns.Clan.PostSmartGroupFormation then
            local okPost, reason = ns.Clan:PostSmartGroupFormation()
            if not okPost and reason == "needs_activity" then
                if onChanged then
                    LFGFrameTab:OpenOfficialModule("lfg")
                else
                    LFGFrameTab.viewMode = "categories"
                    LFGFrameTab:RefreshData()
                end
                ns:Print("%s", L["Select the dungeon or activity you want to broadcast to Guild & Allies."])
            end
        end
    end)
    if bcMenuBtn and bcMenuBtn.SetEnabled and not canManageMenu then
        pcall(bcMenuBtn.SetEnabled, bcMenuBtn, false)
    end
    root:CreateButton(L["Reset Instances"], function()
        if ns.UI and ns.UI.ConfirmResetInstances then
            ns.UI:ConfirmResetInstances()
        elseif ns.Group and ns.Group.ResetDungeonInstances then
            ns.Group:ResetDungeonInstances()
        end
    end)
    if LFGFrameTab.query and LFGFrameTab.query ~= "" then
        root:CreateButton(L["Clear Keyword Filter"], function()
            LFGFrameTab.query = ""
            if LFGFrameTab.controls and LFGFrameTab.controls.searchBox then
                LFGFrameTab.controls.searchBox:SetText("")
            end
            EmitAndRefresh(false)
        end)
    end
    if ns.LFG and ns.LFG.PopulateAdvancedFiltersMenu then
        if root.CreateDivider then root:CreateDivider() end
        ns.LFG:PopulateAdvancedFiltersMenu(root, function()
            EmitAndRefresh(true)
        end)
        if root.CreateDivider then root:CreateDivider() end
    end
    root:CreateButton(L["My Group"], function()
        LFGFrameTab:OpenOfficialModule("group")
    end)
end

local function CreateBrowseHeaderControls(selfObj, body)
    local browseHeader = CreateFrame("Frame", nil, body)
    browseHeader:SetAllPoints(body)
    browseHeader:Hide()
    selfObj.controls.browseHeader = browseHeader

    local catDropdown = CreateNativeDropdown(
        browseHeader,
        "SocialCentralLFGCategoryDropdown",
        114,
        24,
        function()
            return GetCategoryLabel(LFGFrameTab.categoryFilter, true)
        end,
        function(root)
            LFGFrameTab:PopulateCategoryMenu(root)
        end
    )
    catDropdown:SetPoint("TOPLEFT", browseHeader, "TOPLEFT", 62, -24)
    selfObj.controls.catDropdown = catDropdown

    local helpBtn = Theme:CreateHelpButton(
        browseHeader,
        L["Help: Integrated Clan & Allies LFG"],
        L["Large, clear Group Finder list displaying Groups ([LFM]) and Players Looking ([Looking]) in separate collapsible sections, paired with SocialCentral's 2-mode Filter Center side panel (Official Search vs Guild & Addon)."],
        L["Pick Category and Activities at the top, type keywords, or use the Filter Center side panel via Filters » (Official Search for Blizzard filters, Guild & Addon for Guild/Addon/Favorites/Whispers) — it auto-closes when switching Blizzard tabs."],
        16,
        { target = browseHeader }
    )
    helpBtn:SetPoint("TOPRIGHT", browseHeader, "TOPRIGHT", -10, -27)

    local browseQuickBtn = Theme.CreateOfficialQuickButton and Theme:CreateOfficialQuickButton(browseHeader, {
        name = "SocialCentralLFGBrowseQuickBtn",
        size = 18,
        title = L["Group Finder (I)"],
        tooltipAnchor = "ANCHOR_RIGHT",
        getStatusState = GetLfgQuickStatusState,
        getTooltipLines = GetLfgQuickTooltipLines,
        buildMenu = function(root)
            BuildLfgQuickOptionsMenu(root, true)
        end,
    })
    if browseQuickBtn then
        browseQuickBtn:SetPoint("RIGHT", helpBtn, "LEFT", -4, 0)
        selfObj.controls.browseQuickBtn = browseQuickBtn
    end

    local refreshBtn = CreateFrame("Button", "SocialCentralLFGRefreshButton", browseHeader)
    refreshBtn:SetSize(26, 26)
    refreshBtn:SetPoint("RIGHT", browseQuickBtn or helpBtn, "LEFT", -4, 0)
    refreshBtn:SetNormalTexture("Interface\\Buttons\\UI-SquareButton-Up")
    refreshBtn:SetPushedTexture("Interface\\Buttons\\UI-SquareButton-Down")
    refreshBtn:SetDisabledTexture("Interface\\Buttons\\UI-SquareButton-Disabled")
    local refHl = refreshBtn:CreateTexture(nil, "HIGHLIGHT")
    refHl:SetAllPoints()
    refHl:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    refHl:SetBlendMode("ADD")
    local refIcon = refreshBtn:CreateTexture(nil, "ARTWORK", nil, 5)
    refIcon:SetSize(15, 15)
    refIcon:SetPoint("CENTER", refreshBtn, "CENTER", -1, 0)
    refIcon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    refreshBtn.Icon = refIcon
    refreshBtn:SetScript("OnMouseDown", function(selfBtn)
        selfBtn.Icon:SetPoint("CENTER", selfBtn, "CENTER", -2, -1)
    end)
    refreshBtn:SetScript("OnMouseUp", function(selfBtn)
        selfBtn.Icon:SetPoint("CENTER", selfBtn, "CENTER", -1, 0)
    end)
    refreshBtn:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Refresh"], 1, 1, 1)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    refreshBtn:SetScript("OnClick", function()
        LFGFrameTab._hasSearchedThisSession = true
        if ns.Social and ns.Social.RequestRosters then
            ns.Social:RequestRosters(false)
        end
        if ns.Clan and ns.Clan.RequestExternalLFGCatchup then
            ns.Clan:RequestExternalLFGCatchup()
        end
        LFGFrameTab:TriggerOfficialBrowseSearch(true)
        LFGFrameTab:RefreshData()
    end)
    selfObj.controls.refreshBtn = refreshBtn

    local activityDropdown = CreateNativeDropdown(
        browseHeader,
        "SocialCentralLFGBrowseActivityDropdown",
        120,
        24,
        function()
            return LFGFrameTab:GetBrowseActivityDropdownLabel()
        end,
        function(root)
            LFGFrameTab:PopulateActivityMenu(root)
        end
    )
    activityDropdown:SetPoint("LEFT", catDropdown, "RIGHT", 4, 0)
    activityDropdown:SetPoint("RIGHT", refreshBtn, "LEFT", -4, 0)
    selfObj.controls.activityDropdown = activityDropdown

    local drawerToggleBtn = CreateNativeButton(browseHeader, nil, 96, 23, L["Filters »"])
    AutoFitNativeButton(drawerToggleBtn, 86, 16, 132)
    drawerToggleBtn:SetPoint("TOPRIGHT", browseHeader, "TOPRIGHT", -12, -52)
    drawerToggleBtn:SetScript("OnClick", function()
        if ns.LFG and ns.LFG.ToggleSideDrawer then
            ns.LFG:ToggleSideDrawer(LFGFrameTab)
        end
    end)
    drawerToggleBtn:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["SocialCentral Filter Center"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Opens or closes SocialCentral's 2-mode side panel (Official Search vs Guild & Addon). Automatically closes on other Blizzard tabs."], 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    drawerToggleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    selfObj.controls.drawerToggleBtn = drawerToggleBtn

    local searchBox = Theme:CreateEditBox(browseHeader, {
        height = 23,
        clearButton = true,
        placeholder = L["Search dungeon, raid, or player..."],
    })
    searchBox:SetPoint("TOPLEFT", browseHeader, "TOPLEFT", 62, -52)
    searchBox:SetPoint("RIGHT", drawerToggleBtn, "LEFT", -6, 0)
    searchBox:SetScript("OnEscapePressed", function(selfBox)
        selfBox:ClearFocus()
    end)
    searchBox:HookScript("OnTextChanged", function(selfBox)
        local txt = selfBox:GetText() or ""
        if LFGFrameTab.query == txt then return end
        LFGFrameTab.query = txt
        if txt ~= "" then
            LFGFrameTab._hasSearchedThisSession = true
        end
        LFGFrameTab._searchToken = (LFGFrameTab._searchToken or 0) + 1
        local tok = LFGFrameTab._searchToken
        if C_Timer and C_Timer.After then
            C_Timer.After(0.12, function()
                if LFGFrameTab._searchToken == tok then
                    LFGFrameTab:RefreshData()
                    ns:Emit("LFG_BROWSE_STATE_CHANGED")
                end
            end)
        else
            LFGFrameTab:RefreshData()
            ns:Emit("LFG_BROWSE_STATE_CHANGED")
        end
    end)
    selfObj.controls.searchBox = searchBox

    selfObj:UpdateQuickMicroBarVisuals()
end

local function CreateLeaderNoticePanel(categoryView, controls)
    local box = CreateFrame("Frame", nil, categoryView, "BackdropTemplate")
    box:SetPoint("TOPLEFT", categoryView, "TOPLEFT", 12, -16)
    box:SetPoint("TOPRIGHT", categoryView, "TOPRIGHT", -12, -16)
    box:SetHeight(212)
    Theme:ApplyBackdrop(box, "surface")
    box:Hide()

    local icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -14)
    icon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")

    local noticeHelpBtn = Theme.CreateHelpButton and Theme:CreateHelpButton(
        box,
        L["Only the group leader can manage group listings."],
        L["In a party or raid, Blizzard only lets the group leader publish or edit Group Finder listings."],
        L["You can switch to Browse anytime to find groups, whisper players, or ask the leader to publish."],
        18,
        { target = box }
    ) or nil
    if noticeHelpBtn then
        noticeHelpBtn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -12)
        controls.leaderNoticeHelpBtn = noticeHelpBtn
    end

    local title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetPoint("RIGHT", noticeHelpBtn or box, noticeHelpBtn and "LEFT" or "RIGHT", noticeHelpBtn and -6 or -14, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(true)
    title:SetTextColor(1.0, 0.82, 0.20)
    title:SetText(L["Only the group leader can manage group listings."])

    local desc = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
    desc:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -14, 12)
    desc:SetJustifyH("LEFT")
    desc:SetJustifyV("TOP")
    desc:SetWordWrap(true)
    desc:SetTextColor(0.92, 0.90, 0.84)

    controls.leaderNoticePanel = box
    controls.leaderNoticeTitle = title
    controls.leaderNoticeBody = desc
end

local function CreateLeaderBrowseBar(body, controls)
    local bar = CreateFrame("Frame", nil, body, "BackdropTemplate")
    bar:SetHeight(22)
    Theme:ApplyBackdrop(bar, "surface")
    bar:EnableMouse(true)
    bar:Hide()

    local ico = bar:CreateTexture(nil, "ARTWORK")
    ico:SetSize(14, 14)
    ico:SetPoint("LEFT", bar, "LEFT", 6, 0)
    ico:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")

    local lbl = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", ico, "RIGHT", 5, 0)
    lbl:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetTextColor(1.0, 0.85, 0.35)

    bar:SetScript("OnEnter", function(selfBar)
        local leaderName = Compat.GetGroupLeaderName and Compat.GetGroupLeaderName()
        GameTooltip:SetOwner(selfBar, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Only the group leader can manage group listings."], 1.0, 0.82, 0.20, true)
        GameTooltip:AddLine(" ")
        if leaderName and leaderName ~= "" then
            GameTooltip:AddLine(L["Member mode (Leader: %s) — Only the leader can list or invite; you can browse and whisper."]:format(leaderName), 0.90, 0.92, 0.96, true)
        else
            GameTooltip:AddLine(L["Member mode — Only the leader can list or invite; you can browse and whisper."], 0.90, 0.92, 0.96, true)
        end
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    controls.leaderBrowseBar = bar
    controls.leaderBrowseLabel = lbl
end

local function AttachNonLeaderButtonTooltip(btn, titleText, normalHint, mode)
    if not btn then return end
    btn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        local blocked = (mode == "invite") and selfBtn._scNonLeaderInvite or selfBtn._scNonLeader
        local needsSel = (mode == "listing") and (selfBtn._scNeedsSelection == true)
        if not blocked and not needsSel and not normalHint then
            return
        end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(titleText, 1.0, 0.82, 0.0)
        if normalHint and normalHint ~= "" then
            GameTooltip:AddLine(normalHint, 0.88, 0.90, 0.94, true)
        end
        if blocked then
            GameTooltip:AddLine(" ")
            if mode == "invite" then
                GameTooltip:AddLine(L["Only the group leader can invite players into this party."], 1.0, 0.45, 0.35, true)
            else
                GameTooltip:AddLine(FormatLeaderOnlyMessage(selfBtn._scLeaderName), 1.0, 0.45, 0.35, true)
            end
        elseif needsSel then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Select at least one role above and one activity in the list to publish."], 1.0, 0.65, 0.25, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function BuildSubPanelChromeArt(controls, panel, useLfgHost)
    local opaqueBg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
    opaqueBg:SetTexture(WHITE8X8)
    opaqueBg:SetVertexColor(0.08, 0.075, 0.07, 1.0)
    panel._solidOpaqueBg = opaqueBg
    controls.solidOpaqueBg = opaqueBg

    local artFrame = CreateFrame("Frame", nil, panel)
    artFrame:SetAllPoints(panel)
    artFrame:SetFrameLevel((panel:GetFrameLevel() or 2) + 1)
    controls.artFrame = artFrame

    local bgArt = artFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    if HasAtlas("groupfinder-background") then
        bgArt:SetAtlas("groupfinder-background", false)
    else
        bgArt:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble")
        bgArt:SetVertexColor(0.22, 0.21, 0.19, 1.0)
    end
    controls.bgArt = bgArt

    local headerBg = artFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
    headerBg:SetHeight(75)
    if HasAtlas("groupfinder-Stat-StoneBG") then
        headerBg:SetAtlas("groupfinder-Stat-StoneBG", false)
    else
        headerBg:SetTexture(WHITE8X8)
        headerBg:SetVertexColor(0.14, 0.13, 0.11, 1.0)
    end
    controls.headerBg = headerBg

    local headerSep = artFrame:CreateTexture(nil, "ARTWORK", nil, 2)
    headerSep:SetHeight(1)
    headerSep:SetTexture(WHITE8X8)
    headerSep:SetVertexColor(0.45, 0.35, 0.18, 0.85)
    controls.headerSep = headerSep

    local insideFrame = artFrame:CreateTexture(nil, "ARTWORK", nil, 1)
    if HasAtlas("common-insideframe") then
        insideFrame:SetAtlas("common-insideframe", false)
    else
        insideFrame:Hide()
    end
    controls.insideFrame = insideFrame

    ApplySubPanelChromeLayout(controls, useLfgHost, -98, 76)
end

function LFGFrameTab:BuildSubPanel(hostFrame)
    local parent = hostFrame or _G.LFGParentFrame or EnsureStandaloneLfgHost()
    if self.subPanel or not parent then return end

    local artInfo = HarvestLfgListingArt(true)
    local useLfgHost = (_G.LFGParentFrame ~= nil and parent == _G.LFGParentFrame)

    local okTpl, panel = pcall(CreateFrame, "Frame", "SocialCentralLFGSubPanel", parent, "PortraitFrameTemplateNoCloseButton")
    if not okTpl or not panel then
        panel = CreateFrame("Frame", "SocialCentralLFGSubPanel", parent)
    end
    panel:ClearAllPoints()
    panel:SetAllPoints(parent)
    panel:SetFrameLevel(math.max(2, ((parent.GetFrameLevel and parent:GetFrameLevel()) or 1) + 5))
    panel:EnableMouse(true)
    if panel.SetClipsChildren then
        panel:SetClipsChildren(false)
    end
    if useLfgHost and not panel.NineSlice and not panel.TitleBg then
        panel._useBackdropFallback = true
    end
    SyncSubPanelTemplateChrome(panel, useLfgHost)
    panel:Hide()

    self.subPanel = panel
    panel:HookScript("OnHide", function()
        if ns.LFG and ns.LFG.HideSideDrawer then
            ns.LFG:HideSideDrawer()
        end
    end)
    BuildSubPanelChromeArt(self.controls, panel, useLfgHost)

    -- Interactive controls container cleanly inside LFGParentFrame chrome
    local nineLvl = (panel.NineSlice and MaxHierarchyLevel(panel.NineSlice, 3)) or (panel:GetFrameLevel() or 2)
    local body = CreateFrame("Frame", nil, panel)
    body:SetAllPoints(panel)
    body:SetFrameLevel(math.max((panel:GetFrameLevel() or 2) + 4, nineLvl + 2))
    self.controls.body = body

    local titleLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 42, -3)
    titleLabel:SetPoint("BOTTOMRIGHT", body, "TOPRIGHT", -34, -20)
    titleLabel:SetJustifyH("CENTER")
    titleLabel:SetJustifyV("MIDDLE")
    titleLabel:SetWordWrap(false)
    titleLabel:SetTextColor(1.0, 0.82, 0.0)
    titleLabel:Hide()
    panel._titleLabel = titleLabel

    -- 1) Browse Header Strip: Category + Filter + Search + Quick Source Bar + Dynamic Activity Sub-Filter
    CreateBrowseHeaderControls(self, body)

    -- 2) Native Forever 4-Role Circle Header Strip (y = -21..-96) matching LFGListingFrame
    local roleHeader = CreateFrame("Frame", nil, body)
    roleHeader:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    roleHeader:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    roleHeader:SetHeight(98)
    roleHeader:Hide()
    self.controls.roleHeader = roleHeader

    local divider = roleHeader:CreateTexture(nil, "ARTWORK", nil, 2)
    divider:SetSize(2, 74)
    divider:SetPoint("TOPLEFT", roleHeader, "TOPLEFT", 235, -22)
    divider:SetColorTexture(0.24, 0.18, 0.12, 0.95)

    local roleButtons = {}
    for _, def in ipairs(ROLE_CIRCLE_DEFS) do
        roleButtons[#roleButtons + 1] = CreateRoleCircleButton(roleHeader, def, artInfo)
    end
    self.controls.roleButtons = roleButtons

    local roleHelpBtn = Theme:CreateHelpButton(
        roleHeader,
        L["Help: Quick LFG Post"],
        L["Quickly broadcasts your LFG/LFM group listing to your Clan and Allied Clans without leaving the Group Finder window."],
        L["Pick the roles you want to perform or fill, then click Auto-Select anytime to match your current spec and continue to activities."]
    )
    roleHelpBtn:SetPoint("TOPRIGHT", roleHeader, "TOPRIGHT", -8, -25)
    self.controls.roleHelpBtn = roleHelpBtn

    local autoRoleBtn = CreateNativeButton(roleHeader, nil, 86, 16, L["Auto-Select"])
    AutoFitNativeButton(autoRoleBtn, 86, 16, 148)
    autoRoleBtn:SetPoint("TOPRIGHT", roleHeader, "TOPRIGHT", -8, -79)
    autoRoleBtn:SetScript("OnClick", function()
        LFGFrameTab:ApplyRecommendedRoles(true)
        LFGFrameTab:UpdateViewLayout()
    end)
    self.controls.autoRoleBtn = autoRoleBtn

    local roleSuggestLbl = roleHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    roleSuggestLbl:SetPoint("TOPLEFT", roleHeader, "TOPLEFT", 54, -81)
    roleSuggestLbl:SetPoint("TOPRIGHT", autoRoleBtn, "TOPLEFT", -6, -2)
    roleSuggestLbl:SetHeight(14)
    roleSuggestLbl:SetJustifyH("LEFT")
    roleSuggestLbl:SetWordWrap(false)
    self.controls.roleSuggestLbl = roleSuggestLbl

    -- 3) View A: Category Selection Banners (Masmorras, Raides, Missoes, Campos de Batalha, Guilda & Personalizado)
    local categoryView = CreateFrame("Frame", nil, body)
    categoryView:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -102)
    categoryView:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -10, 35)
    categoryView:Hide()
    self.controls.categoryView = categoryView

    local officialListCtaBtn = CreateNativeButton(categoryView, nil, 256, 24, L["List in Official LFG (+ Guild & Allies)"])
    officialListCtaBtn:SetPoint("TOPLEFT", categoryView, "TOPLEFT", 10, -3)
    officialListCtaBtn:SetPoint("TOPRIGHT", categoryView, "TOPRIGHT", -32, -3)
    officialListCtaBtn:SetScript("OnClick", function()
        LFGFrameTab:SwitchToOfficialListingTab("GUILD_ALLIES")
    end)
    StyleNativeButton(officialListCtaBtn, true)
    self.controls.officialListCtaBtn = officialListCtaBtn

    local officialListHelpBtn = Theme:CreateHelpButton(
        categoryView,
        L["Help: Official LFG + SocialCentral Mirror"],
        L["Blizzard restricts public Group Finder creation to the native Official tab (Tab 1). Clicking here switches you there with your roles ready."],
        L["Once you click Blizzard's List button on Tab 1, SocialCentral automatically mirrors your Official listing to Guild, Allies & Friends."],
        16,
        { target = officialListCtaBtn }
    )
    officialListHelpBtn:SetPoint("LEFT", officialListCtaBtn, "RIGHT", 4, 0)
    self.controls.officialListHelpBtn = officialListHelpBtn

    local categoryGuideLbl = categoryView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    categoryGuideLbl:SetPoint("TOPLEFT", categoryView, "TOPLEFT", 12, -31)
    categoryGuideLbl:SetPoint("TOPRIGHT", categoryView, "TOPRIGHT", -12, -31)
    categoryGuideLbl:SetJustifyH("CENTER")
    categoryGuideLbl:SetWordWrap(false)
    self.controls.categoryGuideLbl = categoryGuideLbl

    local categoryButtons = {}
    for idx, catDef in ipairs(LISTING_CATEGORIES) do
        categoryButtons[#categoryButtons + 1] = CreateCategoryBannerButton(categoryView, catDef, idx, artInfo)
    end
    self.controls.categoryButtons = categoryButtons
    CreateLeaderNoticePanel(categoryView, self.controls)
    CreateLeaderBrowseBar(body, self.controls)

    -- 4) View B: Activity Checklist, Playstyle, Notes & Broadcast View
    local activityView = CreateFrame("Frame", nil, body)
    activityView:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -102)
    activityView:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 35)
    activityView:Hide()
    self.controls.activityView = activityView

    local playstyleDropdown = CreateNativeDropdown(
        activityView,
        "SocialCentralLFGPlaystyleDropdown",
        176,
        24,
        function()
            return GetPlaystyleLabel(LFGFrameTab.playstyle)
        end,
        function(root)
            for _, opt in ipairs(PLAYSTYLE_OPTIONS) do
                AddDropdownMenuChoice(root, L[opt.labelKey], function()
                    return LFGFrameTab.playstyle == opt.id
                end, function()
                    LFGFrameTab.playstyle = opt.id
                    LFGFrameTab:RefreshData()
                end)
            end
        end
    )
    playstyleDropdown:SetPoint("TOPLEFT", activityView, "TOPLEFT", 6, -8)
    self.controls.playstyleDropdown = playstyleDropdown

    local allLevelsCheck = CreateFrame("CheckButton", nil, activityView, "UICheckButtonTemplate")
    allLevelsCheck:SetSize(22, 22)
    allLevelsCheck:SetPoint("TOPRIGHT", activityView, "TOPRIGHT", -4, -9)
    allLevelsCheck:SetScript("OnClick", function(selfCheck)
        LFGFrameTab.showAllLevels = (selfCheck:GetChecked() == true)
        LFGFrameTab:RefreshData()
    end)
    self.controls.allLevelsCheck = allLevelsCheck

    local allLevelsLbl = activityView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    allLevelsLbl:SetPoint("LEFT", playstyleDropdown, "RIGHT", 4, 0)
    allLevelsLbl:SetPoint("RIGHT", allLevelsCheck, "LEFT", -2, 0)
    allLevelsLbl:SetJustifyH("RIGHT")
    allLevelsLbl:SetWordWrap(false)
    allLevelsLbl:SetText(L["All Level Ranges"])
    allLevelsLbl:SetTextColor(1.0, 0.82, 0.0)

    local masterCatCheck = CreateFrame("CheckButton", nil, activityView, "UICheckButtonTemplate")
    masterCatCheck:SetSize(20, 20)
    masterCatCheck:SetPoint("TOPLEFT", activityView, "TOPLEFT", 8, -40)
    masterCatCheck:SetScript("OnClick", function(selfCheck)
        local targetState = (selfCheck:GetChecked() == true) and true or nil
        local items = LFGFrameTab:GetFilteredCategoryActivities(LFGFrameTab.activeCategory, LFGFrameTab.showAllLevels)
        for i = 1, #items do
            LFGFrameTab.selectedActivities[items[i].id] = targetState
        end
        LFGFrameTab:RefreshData()
    end)
    self.controls.masterCatCheck = masterCatCheck

    local modeDropdown = CreateNativeDropdown(
        activityView,
        "SocialCentralLFGModeDropdown",
        136,
        22,
        function()
            return GetListingModeLabel(LFGFrameTab.listingMode)
        end,
        function(root)
            for _, opt in ipairs(LISTING_MODES) do
                AddDropdownMenuChoice(root, L[opt.labelKey], function()
                    return LFGFrameTab.listingMode == opt.id
                end, function()
                    LFGFrameTab.listingMode = opt.id
                    LFGFrameTab:RefreshData()
                end)
            end
        end
    )
    modeDropdown:SetPoint("TOPRIGHT", activityView, "TOPRIGHT", -4, -39)
    self.controls.modeDropdown = modeDropdown

    local masterCatLabel = activityView:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    masterCatLabel:SetPoint("LEFT", masterCatCheck, "RIGHT", 4, 0)
    masterCatLabel:SetPoint("RIGHT", modeDropdown, "LEFT", -6, 0)
    masterCatLabel:SetJustifyH("LEFT")
    masterCatLabel:SetWordWrap(false)
    masterCatLabel:SetText(L["Dungeons"])
    masterCatLabel:SetTextColor(1.0, 0.82, 0.0)
    self.controls.masterCatLabel = masterCatLabel

    local actList = Theme:CreateScrollList(activityView, 22, CreateActivityRow, UpdateActivityRow)
    actList.container:SetPoint("TOPLEFT", activityView, "TOPLEFT", 18, -62)
    actList.container:SetPoint("BOTTOMRIGHT", activityView, "BOTTOMRIGHT", -4, 98)
    Theme:ApplyBackdrop(actList.container, "none")
    local origActRender = actList.Render
    local function ShowButtonChild(ch)
        if ch ~= actList.viewport and ch ~= actList.track and ch.GetObjectType and ch:GetObjectType() == "Button" then
            ch:SetShown(actList._needsScroll)
        end
    end
    function actList:Render()
        if origActRender then
            origActRender(self)
        end
        local needsScroll = (self.thumb and self.thumb.IsShown and self.thumb:IsShown()) == true
        self._needsScroll = needsScroll
        if self.track and self.track.SetShown then
            self.track:SetShown(needsScroll)
        end
        if Compat.ForEachChild then
            Compat.ForEachChild(self.container, ShowButtonChild)
        end
    end
    self.activityList = actList

    local commentBackdrop = CreateFrame("Frame", nil, activityView, "BackdropTemplate")
    commentBackdrop:SetPoint("BOTTOMLEFT", activityView, "BOTTOMLEFT", 6, 34)
    commentBackdrop:SetPoint("BOTTOMRIGHT", activityView, "BOTTOMRIGHT", -6, 34)
    commentBackdrop:SetHeight(56)
    if Theme.ApplyInputBackdrop then
        Theme:ApplyInputBackdrop(commentBackdrop)
    else
        commentBackdrop:SetBackdrop({
            bgFile = WHITE8X8,
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        commentBackdrop:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
        commentBackdrop:SetBackdropBorderColor(0.45, 0.42, 0.36, 0.9)
    end
    self.controls.commentBackdrop = commentBackdrop

    local commentBox = CreateFrame("EditBox", nil, commentBackdrop)
    commentBox:SetPoint("TOPLEFT", commentBackdrop, "TOPLEFT", 8, -6)
    commentBox:SetPoint("BOTTOMRIGHT", commentBackdrop, "BOTTOMRIGHT", -8, 6)
    commentBox:SetMultiLine(true)
    commentBox:SetAutoFocus(false)
    commentBox:SetMaxLetters(90)
    commentBox:SetFontObject(ChatFontNormal)
    commentBox:SetTextColor(1.0, 1.0, 1.0)
    local commentPlaceholder = commentBackdrop:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    commentPlaceholder:SetPoint("TOPLEFT", commentBox, "TOPLEFT", 1, -1)
    commentPlaceholder:SetPoint("TOPRIGHT", commentBox, "TOPRIGHT", -1, -1)
    commentPlaceholder:SetJustifyH("LEFT")
    commentPlaceholder:SetText(L["More details about the group (optional)"])
    commentBox:SetScript("OnTextChanged", function(selfBox)
        local txt = selfBox:GetText() or ""
        LFGFrameTab.commentText = txt
        commentPlaceholder:SetShown(txt == "")
    end)
    commentBox:SetScript("OnEscapePressed", function(selfBox)
        selfBox:ClearFocus()
    end)
    self.controls.commentBox = commentBox

    local broadcastDropdown = CreateNativeDropdown(
        activityView,
        "SocialCentralLFGBroadcastDropdown",
        176,
        24,
        function()
            return GetBroadcastLabel(LFGFrameTab.broadcastMode)
        end,
        function(root)
            local showGuildOpts = (not ns.Compat or not ns.Compat.ShouldShowGuildFeatures) or ns.Compat.ShouldShowGuildFeatures()
            for _, opt in ipairs(BROADCAST_OPTIONS) do
                if (opt.id ~= "CLAN" and opt.id ~= "GCHAT") or showGuildOpts then
                    AddDropdownMenuChoice(root, L[opt.labelKey], function()
                        return LFGFrameTab.broadcastMode == opt.id
                    end, function()
                        LFGFrameTab.broadcastMode = opt.id
                        LFGFrameTab:RefreshData()
                    end)
                end
            end
        end
    )
    broadcastDropdown:SetPoint("BOTTOMRIGHT", activityView, "BOTTOMRIGHT", -6, 4)
    self.controls.broadcastDropdown = broadcastDropdown

    local broadcastLbl = activityView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    broadcastLbl:SetPoint("LEFT", activityView, "BOTTOMLEFT", 6, 16)
    broadcastLbl:SetPoint("RIGHT", broadcastDropdown, "LEFT", -6, 0)
    broadcastLbl:SetJustifyH("RIGHT")
    broadcastLbl:SetWordWrap(false)
    broadcastLbl:SetText(L["Broadcast to"])
    broadcastLbl:SetTextColor(1.0, 0.82, 0.0)

    -- 5) View C: Scrollable Native Browse List over groupfinder-background cliff illustration
    local list = Theme:CreateScrollList(body, 76, CreateLfgRow, UpdateLfgRow)
    list.container:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -81)
    list.container:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 32)
    list.container:Hide()
    if list.viewport and list.viewport.SetClipsChildren then
        list.viewport:SetClipsChildren(true)
    end
    Theme:ApplyBackdrop(list.container, "none")

    if list.emptyLabel then
        list.emptyLabel:ClearAllPoints()
        list.emptyLabel:SetPoint("TOP", list.viewport, "TOP", 0, -48)
        list.emptyLabel:SetWidth(308)
        list.emptyLabel:SetFontObject(GameFontNormal)
        list.emptyLabel:SetJustifyH("CENTER")
        list.emptyLabel:SetWordWrap(true)
    end

    local origListRefreshTheme = list.RefreshTheme
    function list:RefreshTheme()
        if origListRefreshTheme then
            origListRefreshTheme(self)
        end
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(self.container, "none")
        if self.emptyLabel and p and p.textMuted then
            self.emptyLabel:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
        end
    end

    local origListRender = list.Render
    local function ShowListButtonChild(ch)
        if ch ~= list.viewport and ch ~= list.track and ch.GetObjectType and ch:GetObjectType() == "Button" then
            ch:SetShown(list._needsScroll)
        end
    end
    function list:Render()
        if origListRender then
            origListRender(self)
        end
        local p = Theme:GetPalette()
        if self.emptyLabel and p and p.textMuted then
            self.emptyLabel:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
        end
        local needsScroll = (self.thumb and self.thumb.IsShown and self.thumb:IsShown()) == true
        self._needsScroll = needsScroll
        if self.track and self.track.SetShown then
            self.track:SetShown(needsScroll)
        end
        if Compat.ForEachChild then
            Compat.ForEachChild(self.container, ShowListButtonChild)
        end
    end
    self.list = list

    -- 6) Unified Native Bottom Action Bar shared cleanly across Categories / Activities / Browse
    local sendMsgBtn = CreateNativeButton(body, nil, 136, 21, L["Send Message"])
    AutoFitNativeButton(sendMsgBtn, 96, 16, 156)
    sendMsgBtn:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 10, 5)
    sendMsgBtn:SetScript("OnClick", function()
        local sel = LFGFrameTab.selectedItem
        if not sel then return end
        if sel.isSelf then
            LFGFrameTab:StartEditListing(sel)
            return
        end
        OpenPlayerWhisper(sel)
    end)
    sendMsgBtn:Hide()
    self.controls.sendMsgBtn = sendMsgBtn

    local inviteBtn = CreateNativeButton(body, nil, 96, 21, L["Invite"])
    AutoFitNativeButton(inviteBtn, 78, 14, 112)
    inviteBtn:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -10, 5)
    inviteBtn:SetScript("OnClick", function()
        local sel = LFGFrameTab.selectedItem
        if sel and sel.isSelf then
            if ns.Clan and ns.Clan.ClearMyLFG then
                ns.Clan:ClearMyLFG(true)
            end
            if C_LFGList and C_LFGList.HasActiveEntryInfo and Safe.Value(Safe.Call(C_LFGList.HasActiveEntryInfo)) == true then
                ns:Print("%s", L["Click Blizzard's Remove button on the Official Listing tab to end your public listing."])
                LFGFrameTab:SwitchToOfficialListingTab(nil)
                return
            end
            ns:Print("%s", L["Your listing has been removed."])
            LFGFrameTab:HandleOwnListingRemoved()
            return
        end
        if sel and ns.LFG and ns.LFG.ExecuteRowAction and sel.mode == "LFG" and sel.sourceType ~= "EVENT" then
            ns.LFG:ExecuteRowAction(sel, true)
            LFGFrameTab:RefreshData()
            return
        end
        local canInviteLfg, invTarget, invBnetId = ResolveLfgInviteTarget(sel)
        if canInviteLfg and Compat.Invite then
            Compat.Invite(invTarget, invBnetId)
        end
    end)
    AttachNonLeaderButtonTooltip(inviteBtn, L["Invite"], nil, "invite")
    inviteBtn:Hide()
    self.controls.inviteBtn = inviteBtn

    local listGroupBtn = CreateNativeButton(body, nil, 102, 21, L["List Self"])
    AutoFitNativeButton(listGroupBtn, 86, 14, 134)
    listGroupBtn:SetPoint("BOTTOM", body, "BOTTOM", 12, 5)
    listGroupBtn:SetScript("OnClick", function()
        local selfListing = LFGFrameTab:GetSelfActiveListing()
        if selfListing then
            LFGFrameTab:StartEditListing(selfListing)
        else
            local inGroup = Compat.IsInGroup and Compat.IsInGroup()
            LFGFrameTab.listingMode = inGroup and "LFM" or "LFG"
            LFGFrameTab.viewMode = "categories"
            LFGFrameTab:RefreshData()
        end
    end)
    AttachNonLeaderButtonTooltip(listGroupBtn, L["List Self"], nil, "listing")
    listGroupBtn:Hide()
    self.controls.listGroupBtn = listGroupBtn

    local browseGroupsBtn = CreateNativeButton(body, nil, 124, 21, L["Browse Groups"])
    AutoFitNativeButton(browseGroupsBtn, 108, 20, 152)
    browseGroupsBtn:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 10, 5)
    browseGroupsBtn:SetScript("OnClick", function()
        LFGFrameTab:LoadSavedBrowseFilters(false)
        LFGFrameTab:SyncBrowseFilterToActiveListing(false)
        LFGFrameTab._hasSearchedThisSession = true
        LFGFrameTab.viewMode = "browse"
        LFGFrameTab:TriggerOfficialBrowseSearch(false)
        LFGFrameTab:RefreshData()
    end)
    browseGroupsBtn:Hide()
    self.controls.browseGroupsBtn = browseGroupsBtn

    local backBtn = CreateNativeButton(body, nil, 106, 21, L["Back"])
    AutoFitNativeButton(backBtn, 92, 18, 124)
    backBtn:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 10, 5)
    backBtn:SetScript("OnClick", function()
        LFGFrameTab.viewMode = "categories"
        LFGFrameTab:RefreshData()
    end)
    backBtn:Hide()
    self.controls.backBtn = backBtn

    local listSelfBtn = CreateNativeButton(body, nil, 114, 21, L["List Self"])
    AutoFitNativeButton(listSelfBtn, 100, 18, 146)
    listSelfBtn:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -10, 5)
    listSelfBtn:SetScript("OnClick", function()
        LFGFrameTab:SubmitListing()
    end)
    AttachNonLeaderButtonTooltip(listSelfBtn, L["List Self"], nil, "listing")
    listSelfBtn:Hide()
    self.controls.listSelfBtn = listSelfBtn

    local unlistBtn = CreateNativeButton(body, nil, 90, 21, L["Delete Listing"])
    AutoFitNativeButton(unlistBtn, 86, 16, 132)
    unlistBtn:SetPoint("BOTTOM", body, "BOTTOM", -8, 5)
    unlistBtn:SetScript("OnClick", function()
        if ns.Clan and ns.Clan.ClearMyLFG then
            ns.Clan:ClearMyLFG(true)
        end
        if C_LFGList and C_LFGList.HasActiveEntryInfo and Safe.Value(Safe.Call(C_LFGList.HasActiveEntryInfo)) == true then
            ns:Print("%s", L["Click Blizzard's Remove button on the Official Listing tab to end your public listing."])
            LFGFrameTab:SwitchToOfficialListingTab(nil)
            return
        end
        ns:Print("%s", L["Your listing has been removed."])
        LFGFrameTab:HandleOwnListingRemoved()
    end)
    unlistBtn:Hide()
    self.controls.unlistBtn = unlistBtn

    local listHelpBtn = Theme:CreateHelpButton(
        body,
        L["Help: Quick LFG Post"],
        L["Quickly broadcasts your LFG/LFM group listing to your Clan and Allied Clans without leaving the Group Finder window."],
        L["Check one or more activities above and click List Self (or use Official LFG on Tab 1) to publish your group or solo search."]
    )
    listHelpBtn:SetPoint("RIGHT", listSelfBtn, "LEFT", -6, 0)
    listHelpBtn:Hide()
    self.controls.listHelpBtn = listHelpBtn

    self:UpdateViewLayout()
    self:RefreshTheme()
end

function LFGFrameTab:EnsureNativeBridgeBar()
    local parent = _G.LFGParentFrame
    if not parent then return nil end
    if ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled("I") then
        if self.nativeBridgeBar then
            self.nativeBridgeBar:Hide()
        end
        return nil
    end
    if self.nativeBridgeBar then
        return self.nativeBridgeBar
    end

    local bar = CreateFrame("Frame", "SocialCentralLFGNativeBridgeBar", parent, "BackdropTemplate")
    bar:SetHeight(54)
    bar:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 6, -2)
    bar:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", -6, -2)
    bar:SetFrameLevel(math.max(10, ((parent.GetFrameLevel and parent:GetFrameLevel()) or 1) + 4))
    bar:EnableMouse(true)

    local solidBg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetAllPoints(bar)
    solidBg:SetTexture(WHITE8X8)
    solidBg:SetVertexColor(0.08, 0.075, 0.07, 1.0)
    bar._solidOpaqueBg = solidBg
    Theme:ApplyBackdrop(bar, "window", Theme:GetPalette())

    local helpBtn = Theme:CreateHelpButton(
        bar,
        L["Help: Official LFG + SocialCentral Mirror"],
        L["Auto-Mirror captures listings created on Tab 1 and broadcasts them to your Guild, Allies, and Friends inside SocialCentral."],
        L["Toggle Auto-Mirror here, click Scan to refresh Official LFG listings, or click Share to announce your active listing in Guild chat."],
        16,
        { target = bar }
    )
    helpBtn:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -7, -5)
    bar.helpBtn = helpBtn

    local quickBtn = Theme.CreateOfficialQuickButton and Theme:CreateOfficialQuickButton(bar, {
        name = "SocialCentralLFGMirrorQuickBtn",
        size = 18,
        title = L["Group Finder (I)"],
        tooltipAnchor = "ANCHOR_RIGHT",
        getStatusState = GetLfgQuickStatusState,
        getTooltipLines = GetLfgQuickTooltipLines,
        buildMenu = function(root)
            BuildLfgQuickOptionsMenu(root, true)
        end,
    })
    if quickBtn then
        quickBtn:SetPoint("RIGHT", helpBtn, "LEFT", -4, 0)
        bar.quickBtn = quickBtn
    end

    local statusLbl = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusLbl:SetPoint("TOPLEFT", bar, "TOPLEFT", 10, -7)
    statusLbl:SetPoint("RIGHT", quickBtn or helpBtn, "LEFT", -6, 0)
    statusLbl:SetJustifyH("LEFT")
    statusLbl:SetWordWrap(false)
    bar.statusLbl = statusLbl

    local mirrorDropdown = CreateNativeDropdown(
        bar,
        "SocialCentralOfficialMirrorDropdown",
        136,
        22,
        function()
            local m = (ns.Clan and ns.Clan.GetOfficialLfgSyncMode) and ns.Clan:GetOfficialLfgSyncMode() or "GUILD_ALLIES"
            return GetOfficialMirrorLabel(m)
        end,
        function(root)
            local showGuildOpts = (not ns.Compat or not ns.Compat.ShouldShowGuildFeatures) or ns.Compat.ShouldShowGuildFeatures()
            for _, opt in ipairs(OFFICIAL_MIRROR_OPTIONS) do
                if opt.id ~= "GUILD_ONLY" or showGuildOpts then
                    AddDropdownMenuChoice(root, L[opt.labelKey], function()
                        local cur = (ns.Clan and ns.Clan.GetOfficialLfgSyncMode) and ns.Clan:GetOfficialLfgSyncMode() or "GUILD_ALLIES"
                        return cur == opt.id
                    end, function()
                        if ns.Clan and ns.Clan.SetOfficialLfgSyncMode then
                            ns.Clan:SetOfficialLfgSyncMode(opt.id)
                        end
                        LFGFrameTab:UpdateNativeBridgeBar()
                    end)
                end
            end
        end
    )
    mirrorDropdown:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6, 5)
    bar.mirrorDropdown = mirrorDropdown

    local viewBtn = CreateNativeButton(bar, nil, 100, 20, L["View Groups (%d)"]:format(0))
    AutoFitNativeButton(viewBtn, 96, 16, 152)
    viewBtn:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 5)
    viewBtn:SetScript("OnClick", function()
        if IsCombatLocked() then
            ns:Print("%s", L["Unavailable during combat."])
            return
        end
        if LFGFrameTab.active then
            LFGFrameTab:HideSubPanel(true)
            return
        end
        if ns.Clan and ns.Clan.RequestClanSync and IsInGuild and IsInGuild() then
            ns.Clan:RequestClanSync()
        end
        LFGFrameTab.viewMode = "browse"
        LFGFrameTab:ShowSubPanel()
    end)
    bar.viewBtn = viewBtn

    local shareGchatBtn = CreateNativeButton(bar, nil, 76, 20, L["Chat (/g)"])
    shareGchatBtn:SetPoint("LEFT", mirrorDropdown, "RIGHT", 4, 0)
    shareGchatBtn:SetPoint("RIGHT", viewBtn, "LEFT", -4, 0)
    shareGchatBtn:SetScript("OnClick", function()
        if ns.Clan and ns.Clan.ShareActiveOfficialToGuildChat then
            ns.Clan:ShareActiveOfficialToGuildChat()
        end
    end)
    shareGchatBtn:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Share in Guild Chat (/g)"], 1.0, 0.82, 0.0)
        GameTooltip:AddLine(L["Pre-fills Guild Chat (/g) with your active Official LFG activity and details."], 0.88, 0.90, 0.94, true)
        GameTooltip:Show()
    end)
    shareGchatBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    shareGchatBtn:Hide()
    bar.shareGchatBtn = shareGchatBtn

    local privateListBtn = CreateNativeButton(bar, nil, 76, 20, L["Private [SC]"])
    privateListBtn:SetPoint("LEFT", mirrorDropdown, "RIGHT", 4, 0)
    privateListBtn:SetPoint("RIGHT", viewBtn, "LEFT", -4, 0)
    privateListBtn:SetScript("OnClick", function()
        if IsCombatLocked() then
            ns:Print("%s", L["Unavailable during combat."])
            return
        end
        local inGroup = Compat.IsInGroup and Compat.IsInGroup()
        LFGFrameTab.listingMode = inGroup and "LFM" or "LFG"
        if LFGFrameTab.broadcastMode == "OFFICIAL" then
            LFGFrameTab.broadcastMode = "ALL"
        end
        LFGFrameTab.viewMode = "categories"
        LFGFrameTab:ShowSubPanel()
    end)
    privateListBtn:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Private [SC]"], 1.0, 0.82, 0.0)
        GameTooltip:AddLine(L["Create a private group listing visible only to your Guild, Allied Guilds & Friends (hidden from public LFG)."], 0.88, 0.90, 0.94, true)
        if selfBtn._scNonLeader then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(FormatLeaderOnlyMessage(selfBtn._scLeaderName), 1.0, 0.45, 0.35, true)
        end
        GameTooltip:Show()
    end)
    privateListBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.privateListBtn = privateListBtn

    local postGroupBtn = CreateNativeButton(bar, nil, 136, 20, L["List Official"])
    AutoFitNativeButton(postGroupBtn, 118, 16, 175)
    postGroupBtn:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -8, 5)
    postGroupBtn:SetScript("OnClick", function()
        if IsCombatLocked() then
            ns:Print("%s", L["Unavailable during combat."])
            return
        end
        LFGFrameTab:SwitchToOfficialListingTab(nil)
    end)
    postGroupBtn:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["List Official"], 1.0, 0.82, 0.0)
        GameTooltip:AddLine(L["Switches to Blizzard's Official Listing tab so you can publish your group cleanly while SocialCentral mirrors it to Guild & Allies."], 0.88, 0.90, 0.94, true)
        if selfBtn._scNonLeader then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(FormatLeaderOnlyMessage(selfBtn._scLeaderName), 1.0, 0.45, 0.35, true)
        end
        GameTooltip:Show()
    end)
    postGroupBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    bar.postGroupBtn = postGroupBtn

    bar:SetScript("OnEnter", function(selfBar)
        local bd = (ns.Clan and ns.Clan.GetTrustedLFGBreakdown and ns.Clan:GetTrustedLFGBreakdown()) or { total = 0, clan = 0, ally = 0, friends = 0, sc = 0 }
        GameTooltip:SetOwner(selfBar, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Clans & Allies LFG"], 0.35, 0.72, 1.0)
        GameTooltip:AddDoubleLine(L["Guild"], tostring(bd.clan or 0), 0.78, 0.84, 0.92, 1.0, 0.82, 0.25)
        GameTooltip:AddDoubleLine(L["Allied Clans"], tostring(bd.ally or 0), 0.78, 0.84, 0.92, 0.25, 0.88, 0.48)
        GameTooltip:AddDoubleLine(L["Friends / Watchlist"], tostring(bd.friends or 0), 0.78, 0.84, 0.92, 0.35, 0.78, 1.0)
        GameTooltip:AddDoubleLine(L["SocialCentral [SC]"], tostring(bd.sc or 0), 0.78, 0.84, 0.92, 0.25, 0.88, 0.48)
        if ns.Group and ns.Group.AppendInstanceHistoryTooltip then
            ns.Group:AppendInstanceHistoryTooltip(GameTooltip)
        end
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.nativeBridgeBar = bar
    return bar
end

function LFGFrameTab:UpdateNativeBridgeBar()
    local s = ns.db and ns.db.settings
    if (ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled("I"))
        or (s and s.embedLfgMirrorBar == false)
    then
        if self.nativeBridgeBar then
            self.nativeBridgeBar:Hide()
        end
        return
    end
    local parent = _G.LFGParentFrame
    if self.active == true
        or not (parent and parent.IsShown and parent:IsShown())
        or (ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(parent))
    then
        if self.nativeBridgeBar then
            self.nativeBridgeBar:Hide()
        end
        return
    end
    local bar = self:EnsureNativeBridgeBar()
    if not bar then return end
    if bar.quickBtn and bar.quickBtn.RefreshTheme then
        bar.quickBtn:RefreshTheme()
    end
    bar:Show()

    local bd = (ns.Clan and ns.Clan.GetTrustedLFGBreakdown and ns.Clan:GetTrustedLFGBreakdown()) or { total = 0 }
    local instStat = (ns.Group and ns.Group.GetHourlyInstanceStatus and ns.Group:GetHourlyInstanceStatus()) or { used = 0, max = 5 }
    local tot = bd.total or 0
    local usedH = instStat.used or 0
    local maxH = instStat.max or 5
    local canManage = (not Compat.CanManageGroupListing) or Compat.CanManageGroupListing()
    local combat = IsCombatLocked()
    local isOfficialListingTab = (_G.LFGListingFrame and _G.LFGListingFrame.IsShown and _G.LFGListingFrame:IsShown()) == true
    local hasOfficialActive = C_LFGList and C_LFGList.HasActiveEntryInfo and (Safe.Value(Safe.Call(C_LFGList.HasActiveEntryInfo)) == true)
    local inGuild = IsInGuild and IsInGuild()
    local redirectTipActive = (GetTime and GetTime() or 0) < (self._officialRedirectTipUntil or 0)

    if isOfficialListingTab then
        if redirectTipActive then
            bar.statusLbl:SetText("|cffffd24d" .. L["Select roles & dungeons above, then click Blizzard's List button!"] .. "|r")
        else
            local lfgPart = L["Official + SC: %d groups"]:format(tot)
            local instPart = L["Inst (1h): %d/%d"]:format(usedH, maxH)
            local lfgColor = (tot > 0) and "|cff3fb950" or "|cffd8dde6"
            local instColor = (usedH >= maxH) and "|cffff5555" or ((usedH == maxH - 1) and "|cffffb833" or "|cff9da7b5")
            bar.statusLbl:SetText(lfgColor .. lfgPart .. "|r  ·  " .. instColor .. instPart .. "|r")
        end
        bar.viewBtn:SetText(L["View Groups (%d)"]:format(tot))
        StyleNativeButton(bar.viewBtn, tot > 0)
        AutoFitNativeButton(bar.viewBtn, 72, 10, 98)
        local barW = (bar.GetWidth and bar:GetWidth()) or 326
        local vbW = (bar.viewBtn.GetWidth and bar.viewBtn:GetWidth()) or 90
        local ddW = math.max(106, math.min(138, barW - 12 - vbW - 82))
        bar.viewBtn:ClearAllPoints()
        bar.viewBtn:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 5)

        if bar.mirrorDropdown then
            bar.mirrorDropdown:Show()
            bar.mirrorDropdown:SetWidth(ddW)
            if bar.mirrorDropdown.RefreshDropdownLabel then
                bar.mirrorDropdown:RefreshDropdownLabel()
            end
        end
        if bar.postGroupBtn then
            bar.postGroupBtn:Hide()
        end
        if hasOfficialActive and inGuild then
            if bar.shareGchatBtn then
                bar.shareGchatBtn:Show()
                if bar.shareGchatBtn.SetEnabled then
                    bar.shareGchatBtn:SetEnabled(not combat)
                end
            end
            if bar.privateListBtn then bar.privateListBtn:Hide() end
        else
            if bar.shareGchatBtn then bar.shareGchatBtn:Hide() end
            if bar.privateListBtn then
                bar.privateListBtn:Show()
                bar.privateListBtn._scNonLeader = not canManage
                bar.privateListBtn._scLeaderName = (not canManage and Compat.GetGroupLeaderName) and Compat.GetGroupLeaderName() or nil
                if bar.privateListBtn.SetEnabled then
                    bar.privateListBtn:SetEnabled(canManage and not combat)
                end
            end
        end
    else
        local lfgPart = L["Clan, Allies & Friends LFG: %d"]:format(tot)
        local instPart = L["Instances (1h): %d/%d"]:format(usedH, maxH)
        local lfgColor = (tot > 0) and "|cff3fb950" or "|cffd8dde6"
        local instColor = (usedH >= maxH) and "|cffff5555" or ((usedH == maxH - 1) and "|cffffb833" or "|cff9da7b5")
        bar.statusLbl:SetText(lfgColor .. lfgPart .. "|r  ·  " .. instColor .. instPart .. "|r")

        if bar.mirrorDropdown then bar.mirrorDropdown:Hide() end
        if bar.shareGchatBtn then bar.shareGchatBtn:Hide() end
        if bar.privateListBtn then bar.privateListBtn:Hide() end

        local barW = (bar.GetWidth and bar:GetWidth()) or 326
        local halfCap = math.max(96, math.floor((barW - 22) * 0.5))
        bar.viewBtn:SetText(L["View Groups (%d)"]:format(tot))
        StyleNativeButton(bar.viewBtn, tot > 0)
        AutoFitNativeButton(bar.viewBtn, 96, 12, halfCap)
        bar.viewBtn:ClearAllPoints()
        bar.viewBtn:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, 5)

        if bar.postGroupBtn then
            bar.postGroupBtn:Show()
            bar.postGroupBtn:SetText(L["List Official"])
            bar.postGroupBtn:ClearAllPoints()
            bar.postGroupBtn:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -8, 5)
            bar.postGroupBtn._scNonLeader = not canManage
            bar.postGroupBtn._scLeaderName = (not canManage and Compat.GetGroupLeaderName) and Compat.GetGroupLeaderName() or nil
            if bar.postGroupBtn.SetEnabled then
                bar.postGroupBtn:SetEnabled(canManage and not combat)
            end
            AutoFitNativeButton(bar.postGroupBtn, 96, 12, halfCap)
        end
    end
end

function LFGFrameTab:EnsureSideTab()
    local parent = _G.LFGParentFrame
    if not parent then return end
    if ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled("I") then
        if self.active then
            self:HideSubPanel(false)
        end
        if ns.UI and ns.UI.CloseEmbeddedIfHost then
            ns.UI:CloseEmbeddedIfHost(parent)
        end
        if self.sideTab then
            self.sideTab:Hide()
        end
        if self.nativeBridgeBar then
            self.nativeBridgeBar:Hide()
        end
        return
    end

    local nativeTabs = DiscoverNativeSideTabs(parent)
    if #nativeTabs == 0 then return end

    local lastNative = nativeTabs[#nativeTabs]
    if not self.sideTab then
        self.sideTab = CreateRightSideTab(
            parent,
            "SocialCentralLFGSideTab",
            lastNative,
            L["Clans & Allies LFG"],
            L["Same Clan, Allied Guilds, Friends & Watchlist"],
            function()
                LFGFrameTab:ToggleSubPanel()
            end,
            "embedLfgWindow"
        )
        self.sideTab:SetScript("OnEnter", function(selfBtn)
            local bd = (ns.Clan and ns.Clan.GetTrustedLFGBreakdown and ns.Clan:GetTrustedLFGBreakdown()) or { total = 0, clan = 0, ally = 0, friends = 0, sc = 0 }
            GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["Clans & Allies LFG"], 0.35, 0.72, 1.0)
            GameTooltip:AddLine(L["Same Clan, Allied Guilds, Friends & Watchlist"], 0.85, 0.88, 0.92, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine(L["Guild"], tostring(bd.clan or 0), 0.78, 0.84, 0.92, 1.0, 0.82, 0.25)
            GameTooltip:AddDoubleLine(L["Allied Clans"], tostring(bd.ally or 0), 0.78, 0.84, 0.92, 0.25, 0.88, 0.48)
            GameTooltip:AddDoubleLine(L["Friends / Watchlist"], tostring(bd.friends or 0), 0.78, 0.84, 0.92, 0.35, 0.78, 1.0)
            GameTooltip:AddDoubleLine(L["Recent Companions"], tostring(bd.companions or 0), 0.78, 0.84, 0.92, 0.62, 0.84, 1.0)
            GameTooltip:AddDoubleLine(L["SocialCentral [SC]"], tostring(bd.sc or 0), 0.78, 0.84, 0.92, 0.25, 0.88, 0.48)
            if ns.Group and ns.Group.AppendInstanceHistoryTooltip then
                ns.Group:AppendInstanceHistoryTooltip(GameTooltip)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Right-click: quick options"], 0.65, 0.72, 0.80, true)
            GameTooltip:Show()
        end)
    end

    local gapY = MeasureTabGap(nativeTabs, -2, self.sideTab._useCommonSideTab)
    self.sideTab:ClearAllPoints()
    self.sideTab:SetPoint("TOPLEFT", lastNative, "BOTTOMLEFT", 0, gapY)
    SyncRightSideTabHitboxAndLayer(parent, self.sideTab, nativeTabs, 600)
    self.sideTab:Show()
    ElevateLfgParentControls()
    self:UpdateTabSelectionVisual()
    self:SyncAllEmbeddedTabStates()

    for _, nTab in ipairs(nativeTabs) do
        nTab._scHookedClick = true
        HookNativeHostTab(parent, nTab, self.sideTab, { "ListingTab", "BrowsingTab", "WhoListingTab" }, true)
    end
    for _, key in ipairs({ "ListingTab", "BrowsingTab", "WhoListingTab", "Tab1", "Tab2", "Tab3" }) do
        if parent[key] then
            parent[key]._scHookedClick = true
            HookNativeHostTab(parent, parent[key], self.sideTab, { "ListingTab", "BrowsingTab", "WhoListingTab" }, true)
        end
    end
end

function LFGFrameTab:AttachHooks()
    local parent = _G.LFGParentFrame
    if self.hooked or not parent then return end
    self.hooked = true

    parent:HookScript("OnShow", function()
        if LFGFrameTab.standaloneHost and LFGFrameTab.standaloneHost:IsShown() then
            LFGFrameTab.standaloneHost:Hide()
        end
        if not LFGFrameTab.active and not (ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(parent)) then
            if ns.UI and ns.UI.CloseEmbeddedIfHost then
                ns.UI:CloseEmbeddedIfHost(parent)
            end
            if not IsAnyNativeSubFrameShown() and ns.UI and ns.UI.RestoreEmbeddedHostUI then
                ns.UI:RestoreEmbeddedHostUI(parent)
            end
        elseif LFGFrameTab.active and IsAnyNativeSubFrameShown() then
            LFGFrameTab:HideSubPanel(false)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if parent and parent:IsShown() then
                    LFGFrameTab:EnsureSideTab()
                    LFGFrameTab:HandleOfficialShortcutOpen("I", parent)
                end
            end)
        else
            LFGFrameTab:EnsureSideTab()
            LFGFrameTab:HandleOfficialShortcutOpen("I", parent)
        end
    end)

    parent:HookScript("OnHide", function()
        LFGFrameTab:HideSubPanel(false)
        if ns.RequestIdleGcStep then
            ns:RequestIdleGcStep(250, 0.8)
        end
    end)

    if hooksecurefunc and type(parent.UpdateTabs) == "function" and not parent._scHookedUpdateTabs then
        parent._scHookedUpdateTabs = true
        hooksecurefunc(parent, "UpdateTabs", function()
            LFGFrameTab:EnsureSideTab()
            if LFGFrameTab.active then
                local suppress = (GetTime and GetTime() or 0) < (LFGFrameTab._suppressNativeTakeoverUntil or 0)
                if IsAnyNativeSubFrameShown() then
                    if suppress then
                        HideNativeLfgSubFrames()
                        SetNativeTabsCheckedFalse()
                        ElevateLfgParentControls()
                        LFGFrameTab:UpdateTabSelectionVisual()
                    else
                        LFGFrameTab:HideSubPanel(false)
                    end
                else
                    SetNativeTabsCheckedFalse()
                    LFGFrameTab:UpdateTabSelectionVisual()
                end
            elseif ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(parent) then
                SetNativeTabsCheckedFalse()
                LFGFrameTab:SyncAllEmbeddedTabStates()
            end
        end)
    end

    if _G.LFGBrowseFrame and _G.LFGBrowseFrame.HookScript and not _G.LFGBrowseFrame._scTakeoverHooked then
        _G.LFGBrowseFrame._scTakeoverHooked = true
        _G.LFGBrowseFrame:HookScript("OnShow", function()
            if LFGFrameTab.active and (GetTime and GetTime() or 0) < (LFGFrameTab._suppressNativeTakeoverUntil or 0) then
                local seq = LFGFrameTab._transitionSeq
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if LFGFrameTab._transitionSeq == seq and LFGFrameTab.active and _G.LFGParentFrame and _G.LFGParentFrame:IsShown() then
                            HideNativeLfgSubFrames()
                            SetNativeTabsCheckedFalse()
                            ElevateLfgParentControls()
                            LFGFrameTab:UpdateTabSelectionVisual()
                            LFGFrameTab:RefreshData()
                        end
                    end)
                end
            elseif C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if _G.LFGParentFrame and _G.LFGParentFrame:IsShown() then
                        LFGFrameTab:UpdateNativeBridgeBar()
                    end
                end)
            end
        end)
    end

    if _G.LFGWhoListFrame and _G.LFGWhoListFrame.HookScript and not _G.LFGWhoListFrame._scBridgeHooked then
        _G.LFGWhoListFrame._scBridgeHooked = true
        _G.LFGWhoListFrame:HookScript("OnShow", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if _G.LFGParentFrame and _G.LFGParentFrame:IsShown() then
                        LFGFrameTab:UpdateNativeBridgeBar()
                    end
                end)
            end
        end)
    end

    if _G.LFGListingFrame and _G.LFGListingFrame.HookScript and not _G.LFGListingFrame._scArtHooked then
        _G.LFGListingFrame._scArtHooked = true
        _G.LFGListingFrame:HookScript("OnShow", function()
            LFGFrameTab._lastListingTabShownAt = (GetTime and GetTime()) or 0
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if _G.LFGParentFrame and _G.LFGParentFrame:IsShown() then
                        LFGFrameTab:UpdateNativeBridgeBar()
                    end
                    local refreshedArt = HarvestLfgListingArt(true)
                    if LFGFrameTab.controls and LFGFrameTab.controls.categoryButtons then
                        for _, catBtn in ipairs(LFGFrameTab.controls.categoryButtons) do
                            if catBtn and catBtn.ApplyBannerArt then
                                catBtn:ApplyBannerArt(refreshedArt)
                            end
                        end
                    end
                end)
            end
        end)
        _G.LFGListingFrame:HookScript("OnHide", function()
            LFGFrameTab._lastListingTabShownAt = (GetTime and GetTime()) or 0
        end)
    end

    if parent.IsShown and parent:IsShown() then
        self:EnsureSideTab()
    end
end

-- ============================================================================
-- Official Game Window Transition #2: SocialUIFrame / FriendsFrame ('O')
-- ============================================================================
function LFGFrameTab:EnsureSocialSideTab()
    local parent = _G.SocialUIFrame or _G.FriendsFrame
    if not parent then return end
    if ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled("O") then
        if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
        if self.socialTab then self.socialTab:Hide() end
        return
    end

    local nativeTabs = DiscoverRightSideTabs(parent, self.socialTab)
    local lastNative = nativeTabs[#nativeTabs]

    if not self.socialTab then
        self.socialTab = CreateRightSideTab(
            parent,
            "SocialCentralSocialSideTab",
            lastNative,
            L["SocialCentral: Watchlist, Social & Nearby"],
            L["View Watchlist (/who), Social folders, Battle.net/Guild friends, and Nearby players right inside Blizzard's Social window."],
            function()
                local targetTab
                for _, cand in ipairs({ "watchlist", "social", "nearby" }) do
                    if not ns.Compat or not ns.Compat.IsModuleEnabled or ns.Compat.IsModuleEnabled(cand) then
                        targetTab = cand
                        break
                    end
                end
                targetTab = targetTab or "social"
                if ns.UI then
                    ns.UI:OpenEmbedded(parent, { "watchlist", "social", "nearby" }, targetTab)
                end
            end,
            "embedSocialWindow"
        )
        self.socialTab:SetScript("OnEnter", function(selfBtn)
            GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["SocialCentral: Watchlist, Social & Nearby"], 0.35, 0.72, 1.0)
            GameTooltip:AddLine(L["View Watchlist (/who), Social folders, Battle.net/Guild friends, and Nearby players right inside Blizzard's Social window."], 0.85, 0.88, 0.92, true)
            if ns.Watchlist and ns.Watchlist.GetStats then
                local on = ns.Watchlist:GetStats()
                local socOnline = ns.Social and ns.Social.GetCount and ns.Social:GetCount("all") or 0
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine(L["Watchlist"] .. " (" .. L["Online"] .. ")", tostring(on or 0), 0.78, 0.84, 0.92, 0.40, 0.92, 0.55)
                GameTooltip:AddDoubleLine(L["Social"] .. " (" .. L["Online"] .. ")", tostring(socOnline or 0), 0.78, 0.84, 0.92, 0.58, 0.88, 0.98)
            end
            GameTooltip:Show()
        end)
    end

    self.socialTab:ClearAllPoints()
    if lastNative then
        local gapY = MeasureTabGap(nativeTabs, -2, self.socialTab._useCommonSideTab)
        self.socialTab:SetPoint("TOPLEFT", lastNative, "BOTTOMLEFT", 0, gapY)
        for _, nt in ipairs(nativeTabs) do
            nt._scSocialCloseHooked = true
            HookNativeHostTab(parent, nt, self.socialTab, nil, false)
        end
    else
        self.socialTab:SetPoint("TOPLEFT", parent, "TOPRIGHT", -2, -240)
    end
    for _, tabName in ipairs({
        "FriendsFrameTab1",
        "FriendsFrameTab2",
        "FriendsFrameTab3",
        "FriendsFrameTab4",
        "FriendsTabHeaderTab1",
        "FriendsTabHeaderTab2",
        "FriendsTabHeaderTab3",
    }) do
        local nTab = _G[tabName]
        if nTab then
            nTab._scSocialCloseHooked = true
            HookNativeHostTab(parent, nTab, self.socialTab, nil, false)
        end
    end
    SyncRightSideTabHitboxAndLayer(parent, self.socialTab, nativeTabs, 600)
    self.socialTab:Show()
    self:SyncAllEmbeddedTabStates()
end

function LFGFrameTab:AttachSocialUI()
    local parent = _G.SocialUIFrame or _G.FriendsFrame
    if self.socialHooked or not parent then return end
    self.socialHooked = true

    parent:HookScript("OnShow", function()
        if not (ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(parent)) then
            if ns.UI and ns.UI.CloseEmbeddedIfHost then
                ns.UI:CloseEmbeddedIfHost(parent)
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if parent and parent:IsShown() then
                    LFGFrameTab:EnsureSocialSideTab()
                    LFGFrameTab:HandleOfficialShortcutOpen("O", parent)
                end
            end)
        else
            LFGFrameTab:EnsureSocialSideTab()
            LFGFrameTab:HandleOfficialShortcutOpen("O", parent)
        end
    end)

    if hooksecurefunc then
        for _, methodName in ipairs({ "SelectTab", "SetTab", "OnTabSelected" }) do
            if type(parent[methodName]) == "function" then
                hooksecurefunc(parent, methodName, function()
                    if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            if parent and parent:IsShown() then
                                LFGFrameTab:EnsureSocialSideTab()
                            end
                        end)
                    end
                end)
            end
        end
        if type(parent.ResetTabs) == "function" then
            hooksecurefunc(parent, "ResetTabs", function()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if parent and parent:IsShown() then
                            LFGFrameTab:EnsureSocialSideTab()
                        end
                    end)
                end
            end)
        end
    end

    if parent.IsShown and parent:IsShown() then
        self:EnsureSocialSideTab()
    end
end

-- ============================================================================
-- Official Game Window Transition #3: CommunitiesFrame / GuildFrame ('J')
-- ============================================================================
local COMMUNITIES_NATIVE_TABS = {
    "ChatTab",
    "RosterTab",
    "GuildBenefitsTab",
    "GuildInfoTab",
    "GuildPreferredPlaySettingsTab",
    "PerkRewardsTab",
    "Tab1",
    "Tab2",
    "Tab3",
    "Tab4",
}

function LFGFrameTab:EnsureGuildSideTab()
    local parent = _G.CommunitiesFrame or _G.GuildFrame
    if not parent then return end
    if ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled("J") then
        if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
        if self.guildTab then self.guildTab:Hide() end
        return
    end

    local nativeTabs = DiscoverRightSideTabs(
        parent,
        self.guildTab,
        COMMUNITIES_NATIVE_TABS
    )
    local lastNative = nativeTabs[#nativeTabs]

    if not self.guildTab then
        self.guildTab = CreateRightSideTab(
            parent,
            "SocialCentralGuildSideTab",
            lastNative,
            L["SocialCentral: Clan Hub & Diplomacy"],
            L["Manage Clan Events, Guild Professions, Recruitment, Wall Notices, and Allied Clan Diplomacy inside the Guild window."],
            function()
                if ns.UI then
                    ns.UI:OpenEmbedded(parent, { "clan" }, "clan")
                end
            end,
            "embedGuildWindow"
        )
    end

    self.guildTab:ClearAllPoints()
    if lastNative then
        local defaultGap = (self.guildTab:GetWidth() or 32) < 44 and -20 or -2
        local gapY = MeasureTabGap(nativeTabs, defaultGap, self.guildTab._useCommonSideTab)
        self.guildTab:SetPoint("TOPLEFT", lastNative, "BOTTOMLEFT", 0, gapY)
        -- Hook every native tab individually as guild-only tabs can appear dynamically when switching clubs.
        for _, nt in ipairs(nativeTabs) do
            nt._scGuildCloseHooked = true
            HookNativeHostTab(parent, nt, self.guildTab, COMMUNITIES_NATIVE_TABS, false)
        end
    else
        self.guildTab:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, -240)
    end
    for _, key in ipairs(COMMUNITIES_NATIVE_TABS) do
        local nt = parent[key]
        if nt then
            nt._scGuildCloseHooked = true
            HookNativeHostTab(parent, nt, self.guildTab, COMMUNITIES_NATIVE_TABS, false)
        end
    end
    SyncRightSideTabHitboxAndLayer(parent, self.guildTab, nativeTabs, 600)
    self.guildTab:Show()
    self:SyncAllEmbeddedTabStates()
end

function LFGFrameTab:AttachCommunitiesUI()
    local parent = _G.CommunitiesFrame or _G.GuildFrame
    if self.guildHooked or not parent then return end
    self.guildHooked = true

    parent:HookScript("OnShow", function()
        if not (ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(parent)) then
            if ns.UI and ns.UI.CloseEmbeddedIfHost then
                ns.UI:CloseEmbeddedIfHost(parent)
            end
            if ns.UI and ns.UI.RestoreEmbeddedHostUI then
                ns.UI:RestoreEmbeddedHostUI(parent)
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if parent and parent:IsShown() then
                    LFGFrameTab:EnsureGuildSideTab()
                    C_Timer.After(0.03, function()
                        if parent and parent:IsShown() then
                            LFGFrameTab:HandleOfficialShortcutOpen("J", parent)
                        end
                    end)
                end
            end)
        else
            LFGFrameTab:EnsureGuildSideTab()
            LFGFrameTab:HandleOfficialShortcutOpen("J", parent)
        end
    end)

    if hooksecurefunc then
        for _, methodName in ipairs({ "SetDisplayMode", "SelectTab", "SetTab", "OnTabSelected" }) do
            if type(parent[methodName]) == "function" then
                hooksecurefunc(parent, methodName, function()
                    if ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(parent) and ns.UI.CloseEmbeddedIfHost then
                        ns.UI:CloseEmbeddedIfHost(parent)
                    end
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            if parent and parent:IsShown() then
                                LFGFrameTab:EnsureGuildSideTab()
                            end
                        end)
                    end
                end)
            end
        end
        if type(parent.OnClubSelected) == "function" then
            hooksecurefunc(parent, "OnClubSelected", function()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if parent and parent:IsShown() then
                            LFGFrameTab:EnsureGuildSideTab()
                        end
                    end)
                end
            end)
        end
    end

    if parent.IsShown and parent:IsShown() then
        self:EnsureGuildSideTab()
    end
end

-- ============================================================================
-- Official Game Window Transition #4: CharacterFrame ('C') -> My Alts
-- ============================================================================
local CHARACTER_NATIVE_TABS = {
    "Tab1",
    "Tab2",
    "Tab3",
    "Tab4",
    "Tab5",
    "Tab6",
    "Tab7",
    "Tab8",
}

function LFGFrameTab:EnsureCharacterSideTab()
    local parent = _G.CharacterFrame
    if not parent then return end
    if ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled("C") then
        if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
        if self.charTab then self.charTab:Hide() end
        return
    end

    local nativeTabs = DiscoverRightSideTabs(parent, self.charTab, CHARACTER_NATIVE_TABS)
    local lastNative = nativeTabs[#nativeTabs]

    if not self.charTab then
        self.charTab = CreateRightSideTab(
            parent,
            "SocialCentralAltsSideTab",
            lastNative,
            L["SocialCentral: My Alts"],
            L["Inspect your saved characters, combined gold, levels, equipped gear, bags, and bank inside the Character window."],
            function()
                if ns.UI then
                    ns.UI:OpenEmbedded(parent, { "alts" }, "alts")
                end
            end,
            "embedCharacterWindow"
        )
    end

    self.charTab:ClearAllPoints()
    if lastNative then
        local gapY = MeasureTabGap(nativeTabs, -2, self.charTab._useCommonSideTab)
        self.charTab:SetPoint("TOPLEFT", lastNative, "BOTTOMLEFT", 0, gapY)
        for _, nt in ipairs(nativeTabs) do
            nt._scCharCloseHooked = true
            HookNativeHostTab(parent, nt, self.charTab, CHARACTER_NATIVE_TABS, false)
        end
    else
        self.charTab:SetPoint("TOPLEFT", parent, "TOPRIGHT", -2, -260)
    end
    for _, prefix in ipairs({ "CharacterFrameTab", "CharacterFrameSideTab" }) do
        for idx = 1, 8 do
            local extraTab = _G[prefix .. idx]
            if extraTab then
                extraTab._scCharCloseHooked = true
                HookNativeHostTab(parent, extraTab, self.charTab, CHARACTER_NATIVE_TABS, false)
            end
        end
    end
    SyncRightSideTabHitboxAndLayer(parent, self.charTab, nativeTabs, 600)
    self.charTab:Show()
    self:SyncAllEmbeddedTabStates()
end

function LFGFrameTab:AttachCharacterUI()
    local parent = _G.CharacterFrame
    if self.charHooked or not parent then return end
    self.charHooked = true

    local function QueueEnsureCharTab()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if parent and parent:IsShown() then
                    LFGFrameTab:EnsureCharacterSideTab()
                end
            end)
        elseif parent and parent:IsShown() then
            LFGFrameTab:EnsureCharacterSideTab()
        end
    end

    parent:HookScript("OnShow", function()
        if not (ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(parent)) then
            if ns.UI and ns.UI.CloseEmbeddedIfHost then
                ns.UI:CloseEmbeddedIfHost(parent)
            end
            if ns.UI and ns.UI.RestoreEmbeddedHostUI then
                ns.UI:RestoreEmbeddedHostUI(parent)
            end
            local anyNativeShown = false
            for _, nName in ipairs({ "PaperDollFrame", "ReputationFrame", "TokenFrame", "PetPaperDollFrame", "SkillFrame", "PVPFrame", "HonorFrame", "StatisticsFrame", "CharacterStatisticsFrame" }) do
                local nf = _G[nName]
                if nf and nf.IsShown and nf:IsShown() then
                    anyNativeShown = true
                    break
                end
            end
            if not anyNativeShown and _G.PaperDollFrame then
                for _, coreName in ipairs({ "PaperDollFrame", "CharacterFrameInset", "CharacterFrameInsetRight", "PaperDollSidebarTabs" }) do
                    local sf = _G[coreName]
                    if sf and sf.Show then
                        pcall(sf.Show, sf)
                    end
                end
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if parent and parent:IsShown() then
                    LFGFrameTab:EnsureCharacterSideTab()
                    LFGFrameTab:HandleOfficialShortcutOpen("C", parent)
                end
            end)
        else
            LFGFrameTab:EnsureCharacterSideTab()
            LFGFrameTab:HandleOfficialShortcutOpen("C", parent)
        end
    end)

    if hooksecurefunc then
        for _, methodName in ipairs({ "ShowSubFrame", "SelectTab", "SetTab", "OnTabSelected" }) do
            if type(parent[methodName]) == "function" then
                hooksecurefunc(parent, methodName, function()
                    if ns.UI and ns.UI.ReleaseAlphaHiddenCharacterSubframesForTabClick then
                        ns.UI:ReleaseAlphaHiddenCharacterSubframesForTabClick()
                    end
                    if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
                    QueueEnsureCharTab()
                end)
            end
        end
        for _, layoutMethod in ipairs({ "UpdateTabLayout", "UpdateTabs", "ResetTabs" }) do
            if type(parent[layoutMethod]) == "function" then
                hooksecurefunc(parent, layoutMethod, QueueEnsureCharTab)
            end
        end
        if type(_G.CharacterFrameTab_OnClick) == "function" then
            hooksecurefunc("CharacterFrameTab_OnClick", function()
                if ns.UI and ns.UI.ReleaseAlphaHiddenCharacterSubframesForTabClick then
                    ns.UI:ReleaseAlphaHiddenCharacterSubframesForTabClick()
                end
                if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
                QueueEnsureCharTab()
            end)
        end
        if type(_G.PanelTemplates_SetTab) == "function" then
            hooksecurefunc("PanelTemplates_SetTab", function(targetFrame)
                if targetFrame == parent then
                    if ns.UI and ns.UI.ReleaseAlphaHiddenCharacterSubframesForTabClick then
                        ns.UI:ReleaseAlphaHiddenCharacterSubframesForTabClick()
                    end
                    if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
                    QueueEnsureCharTab()
                end
            end)
        end
    end

    if parent.IsShown and parent:IsShown() then
        self:EnsureCharacterSideTab()
    end
end

local function AnchorOfficialChatQuickBtn(btn)
    if not btn then return end
    local cf = _G.ChatFrame1
    if not cf then return end
    local rail = _G.ChatFrame1ButtonFrame
    local chatShortcut = _G.SocialCentralChatShortcutButton
    btn:ClearAllPoints()
    if chatShortcut and chatShortcut.IsShown and chatShortcut:IsShown() then
        local uiTop = (_G.UIParent and _G.UIParent.GetTop and _G.UIParent:GetTop()) or 720
        local csTop = chatShortcut.GetTop and chatShortcut:GetTop() or 0
        if csTop > 0 and (uiTop - csTop) < 34 then
            btn:SetPoint("LEFT", chatShortcut, "RIGHT", 4, 0)
        else
            btn:SetPoint("BOTTOM", chatShortcut, "TOP", 0, 5)
        end
    elseif rail and rail.IsShown and rail:IsShown() then
        btn:SetPoint("BOTTOM", rail, "TOP", 0, 3)
    else
        local leftPos = cf.GetLeft and cf:GetLeft()
        if leftPos and leftPos >= 26 then
            btn:SetPoint("BOTTOMRIGHT", cf, "TOPLEFT", -3, 2)
        elseif _G.ChatFrame1Tab then
            btn:SetPoint("LEFT", _G.ChatFrame1Tab, "RIGHT", 4, 0)
        else
            btn:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", 2, 24)
        end
    end
    local refLvl = (chatShortcut and chatShortcut.IsShown and chatShortcut:IsShown() and chatShortcut.GetFrameLevel and chatShortcut:GetFrameLevel())
        or (rail and rail.IsShown and rail:IsShown() and rail.GetFrameLevel and rail:GetFrameLevel())
        or (cf.GetFrameLevel and cf:GetFrameLevel()) or 1
    btn:SetFrameLevel(math.min(9500, math.max(10, refLvl + 10)))
end

local function GetOfficialChatQuickState()
    local s = ns.db and ns.db.settings
    if s and s.embedOfficialChat == false then
        return "off"
    end
    if s and (
        s.officialChatShortChannels == false
        or s.officialChatSenderTags == false
        or s.officialChatEditHistory == false
        or s.officialChatFastScroll == false
        or s.chatClickableUrls == false
    ) then
        return "partial"
    end
    return "active"
end

function LFGFrameTab:PopulateOfficialChatMenu(root, opts)
    if not root then return end
    local s = ns.db and ns.db.settings
    local function ToggleChatOpt(key, defaultTrue)
        if not (ns.db and ns.db.settings) then return end
        local cur = defaultTrue and (ns.db.settings[key] ~= false) or (ns.db.settings[key] == true)
        ns.db.settings[key] = not cur
        ns:Emit("SETTINGS_UPDATED")
        ns:Emit("CHAT_UPDATED")
        LFGFrameTab:RefreshOfficialChatQuickButton()
        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
    end

    root:CreateTitle("SocialCentral — " .. L["Official Chat"])
    root:CreateCheckbox(L["Enable Official Chat Enhancements (ChatFrame)"], function()
        return not s or s.embedOfficialChat ~= false
    end, function() ToggleChatOpt("embedOfficialChat", true) end)
    root:CreateDivider()
    root:CreateCheckbox(L["Shorten public channel names"], function()
        return not s or s.officialChatShortChannels ~= false
    end, function() ToggleChatOpt("officialChatShortChannels", true) end)
    root:CreateCheckbox(L["Show [Lv], [Main], [+]/[Avoid] tags"], function()
        return not s or s.officialChatSenderTags ~= false
    end, function() ToggleChatOpt("officialChatSenderTags", true) end)
    root:CreateCheckbox(L["Clickable URLs"], function()
        return not s or s.chatClickableUrls ~= false
    end, function() ToggleChatOpt("chatClickableUrls", true) end)
    root:CreateCheckbox(L["Remember typed chat history (EditBox)"], function()
        return not s or s.officialChatEditHistory ~= false
    end, function() ToggleChatOpt("officialChatEditHistory", true) end)
    root:CreateCheckbox(L["Fast scroll (Shift/Ctrl + Wheel)"], function()
        return not s or s.officialChatFastScroll ~= false
    end, function() ToggleChatOpt("officialChatFastScroll", true) end)
    root:CreateCheckbox(L["Hide Account-Ignored chat"], function()
        return not s or s.accountIgnoreHideChat ~= false
    end, function() ToggleChatOpt("accountIgnoreHideChat", true) end)
    root:CreateCheckbox(L["Public Chat Anti-Spam Shield"], function()
        return s and s.chatAntiSpamEnabled == true
    end, function() ToggleChatOpt("chatAntiSpamEnabled", false) end)
    root:CreateCheckbox(L["Identify error origin in chat"], function()
        return not s or s.chatErrorOriginTags ~= false
    end, function() ToggleChatOpt("chatErrorOriginTags", true) end)
    root:CreateCheckbox(L["Mirror Alliance Chat in Official Chat (/ali)"], function()
        return not s or s.clanOfficialGreenWall ~= false
    end, function() ToggleChatOpt("clanOfficialGreenWall", true) end)
    local hideSub = root:CreateButton(L["Hide in Official Chat (Keep in SC)"])
    if hideSub and hideSub.CreateCheckbox then
        hideSub:CreateCheckbox(L["Group (Party / Raid / Instance)"], function()
            return s and s.officialHideGroup == true
        end, function() ToggleChatOpt("officialHideGroup", false) end)
        hideSub:CreateCheckbox(L["Guild & Officer"], function()
            return s and s.officialHideGuild == true
        end, function() ToggleChatOpt("officialHideGuild", false) end)
        hideSub:CreateCheckbox(L["Whispers & Battle.net"], function()
            return s and s.officialHideWhispers == true
        end, function() ToggleChatOpt("officialHideWhispers", false) end)
    end
    root:CreateCheckbox(L["Dock Quick Reply over Official WoW Chat (exact size)"], function()
        return not s or s.quickReplyDockToChat ~= false
    end, function() ToggleChatOpt("quickReplyDockToChat", true) end)
    root:CreateCheckbox(L["Open Quick Reply on ENTER when messages are pending"], function()
        return not s or s.quickReplyEnterOpen ~= false
    end, function() ToggleChatOpt("quickReplyEnterOpen", true) end)

    root:CreateDivider()
    root:CreateButton(L["Copy Official Chat"], function()
        if ns.Chat and ns.Chat.OpenCopyOfficialChat then
            ns.Chat:OpenCopyOfficialChat(50, 1)
        end
    end)
    root:CreateButton(L["Mentions & Keywords Radar..."], function()
        if ns.SocialPanels and ns.SocialPanels.OpenMentionKeywordsModal then
            ns.SocialPanels:OpenMentionKeywordsModal()
        end
    end)
    local filtCnt = (ns.Chat and ns.Chat.GetFilteredChatCount and ns.Chat:GetFilteredChatCount()) or 0
    local filtLbl = (filtCnt > 0) and (L["Filtered Chat Log"] .. " (" .. filtCnt .. ")") or L["Filtered Chat Log"]
    root:CreateButton(filtLbl, function()
        if ns.SocialPanels and ns.SocialPanels.OpenFilteredChatModal then
            ns.SocialPanels:OpenFilteredChatModal()
        end
    end)

    if opts and opts.includeLegacyHide then
        root:CreateDivider()
        root:CreateButton(L["Hide quick [SC] button here"], function()
            if ns.db and ns.db.settings then
                ns.db.settings.officialChatQuickButton = false
            end
            LFGFrameTab:RefreshOfficialChatQuickButton()
            ns:Emit("SETTINGS_UPDATED")
            if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
            ns:Print("%s", L["Official Chat [SC] button hidden. Re-enable anytime in Settings (/sc)."])
        end)
        root:CreateButton(L["Disable Official Chat Enhancements"], function()
            if ns.db and ns.db.settings then
                ns.db.settings.embedOfficialChat = false
            end
            LFGFrameTab:RefreshOfficialChatQuickButton()
            ns:Emit("SETTINGS_UPDATED")
            ns:Emit("CHAT_UPDATED")
            if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
            ns:Print("%s", L["Official Chat enhancements disabled. Re-enable anytime in Settings (/sc)."])
        end)
        root:CreateButton(L["Settings"], function()
            if ns.Settings and ns.Settings.Open then ns.Settings:Open("general") end
        end)
    end
end

function LFGFrameTab:RefreshOfficialChatQuickButton()
    local btn = self.officialChatBtn
    local s = ns.db and ns.db.settings
    local cf = _G.ChatFrame1
    local unifiedActive = (not s or s.officialChatShortcutButton ~= false) and (_G.SocialCentralChatShortcutButton ~= nil)
    local shouldShow = (not unifiedActive)
        and cf and cf.IsShown and cf:IsShown()
        and (not s or (s.embedOfficialChat ~= false and s.officialChatQuickButton ~= false))
    if not btn then return end
    if shouldShow then
        AnchorOfficialChatQuickBtn(btn)
        if btn.RefreshTheme then btn:RefreshTheme() end
        btn:Show()
    else
        btn:Hide()
    end
end

-- Standardized quick [SC] control button anchored beside ChatFrame1 (never covers chat lines or tabs).
function LFGFrameTab:AttachChatButton()
    if _G.SocialCentralChatButton and _G.SocialCentralChatButton.Hide then
        _G.SocialCentralChatButton:Hide()
    end
    self.chatBtn = nil
    local cf = _G.ChatFrame1
    if not cf then return end

    if not self.officialChatBtn and Theme.CreateOfficialQuickButton then
        local btn = Theme:CreateOfficialQuickButton(_G.UIParent, {
            name = "SocialCentralOfficialChatAnchorBtn",
            size = 20,
            title = L["Official Chat"],
            tooltipAnchor = "ANCHOR_RIGHT",
            getStatusState = GetOfficialChatQuickState,
            getTooltipLines = function()
                local s = ns.db and ns.db.settings
                local onLbl = "|cff3fb950" .. L["On"] .. "|r"
                local offLbl = "|cff8b949e" .. L["Off"] .. "|r"
                return {
                    { left = L["Short Channels"], right = (not s or s.officialChatShortChannels ~= false) and onLbl or offLbl },
                    { left = L["Sender Badges"], right = (not s or s.officialChatSenderTags ~= false) and onLbl or offLbl },
                    { left = L["Clickable URLs"], right = (not s or s.chatClickableUrls ~= false) and onLbl or offLbl },
                    { left = L["EditBox History"], right = (not s or s.officialChatEditHistory ~= false) and onLbl or offLbl },
                    { left = L["Fast Scroll"], right = (not s or s.officialChatFastScroll ~= false) and onLbl or offLbl },
                    { left = L["Anti-Spam Shield"], right = (s and s.chatAntiSpamEnabled == true) and onLbl or offLbl },
                }
            end,
            buildMenu = function(root)
                LFGFrameTab:PopulateOfficialChatMenu(root, { includeLegacyHide = true })
            end,
        })
        btn:SetClampedToScreen(true)
        self.officialChatBtn = btn
    end

    if not self.chatHooked then
        self.chatHooked = true
        if cf.HookScript then
            cf:HookScript("OnShow", function() LFGFrameTab:RefreshOfficialChatQuickButton() end)
            cf:HookScript("OnHide", function() LFGFrameTab:RefreshOfficialChatQuickButton() end)
        end
        if _G.ChatFrame1ButtonFrame and _G.ChatFrame1ButtonFrame.HookScript then
            _G.ChatFrame1ButtonFrame:HookScript("OnShow", function() LFGFrameTab:RefreshOfficialChatQuickButton() end)
            _G.ChatFrame1ButtonFrame:HookScript("OnHide", function() LFGFrameTab:RefreshOfficialChatQuickButton() end)
        end
    end
    self:RefreshOfficialChatQuickButton()
end

-- ============================================================================
-- Official Game Window Integration #5B: Official Profession Window -> Recipe Catalog [SC]
-- ============================================================================
local hookedProfHosts = setmetatable({}, { __mode = "k" })

local function ResolveVisibleProfessionHost()
    for _, gName in ipairs({ "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }) do
        local f = _G[gName]
        if f and f.IsShown and f:IsShown() then
            return f
        end
    end
    return nil
end

local function AnchorProfessionQuickBtn(btn, host)
    if not (btn and host) then return end
    btn:ClearAllPoints()
    local closeRef = host.CloseButton or (host.TitleContainer and host.TitleContainer.CloseButton) or _G[(host:GetName() or "") .. "CloseButton"]
    if closeRef and closeRef.IsShown and closeRef:IsShown() then
        btn:SetPoint("RIGHT", closeRef, "LEFT", -6, 0)
    else
        btn:SetPoint("TOPRIGHT", host, "TOPRIGHT", -32, -6)
    end
    if host.GetFrameStrata then
        local strata = host:GetFrameStrata()
        if strata then btn:SetFrameStrata(strata) end
    end
    local hostLvl = (host.GetFrameLevel and host:GetFrameLevel()) or 1
    btn:SetFrameLevel(math.min(9500, math.max(20, hostLvl + 25)))
end

function LFGFrameTab:RefreshProfessionQuickButton()
    local btn = self.profQuickBtn
    local s = ns.db and ns.db.settings
    local host = ResolveVisibleProfessionHost()
    local shouldShow = (host ~= nil) and (not s or s.embedProfessionWindow ~= false)
    if not btn then
        if shouldShow then
            self:AttachProfessionButton()
        end
        return
    end
    if shouldShow then
        AnchorProfessionQuickBtn(btn, host)
        if btn.RefreshTheme then btn:RefreshTheme() end
        btn:Show()
    else
        btn:Hide()
    end
end

function LFGFrameTab:AttachProfessionButton()
    for _, gName in ipairs({ "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }) do
        local f = _G[gName]
        if f and f.HookScript and not hookedProfHosts[f] then
            hookedProfHosts[f] = true
            f:HookScript("OnShow", function() LFGFrameTab:RefreshProfessionQuickButton() end)
            f:HookScript("OnHide", function() LFGFrameTab:RefreshProfessionQuickButton() end)
        end
    end

    local host = ResolveVisibleProfessionHost()
    if not self.profQuickBtn and host and Theme.CreateOfficialQuickButton then
        local btn = Theme:CreateOfficialQuickButton(_G.UIParent, {
            name = "SocialCentralProfessionQuickBtn",
            size = 20,
            title = L["Official Professions (Recipes)"],
            tooltipAnchor = "ANCHOR_RIGHT",
            getStatusState = function()
                local s = ns.db and ns.db.settings
                if s and s.embedProfessionWindow == false then
                    return "off"
                end
                if s and s.tooltipRecipeAlts == false then
                    return "partial"
                end
                return "active"
            end,
            getTooltipLines = function()
                local myCnt, uniqCnt, altCnt = 0, 0, 0
                if ns.Alts and ns.Alts.GetRecipeSummaryStats then
                    myCnt, uniqCnt, altCnt = ns.Alts:GetRecipeSummaryStats()
                end
                local s = ns.db and ns.db.settings
                local onLbl = "|cff3fb950" .. L["On"] .. "|r"
                local offLbl = "|cff8b949e" .. L["Off"] .. "|r"
                return {
                    { left = L["This Character"], right = L["%d recipes"]:format(myCnt or 0) },
                    { left = L["Account Catalog"], right = L["%d recipes (%d alts)"]:format(uniqCnt or 0, altCnt or 0) },
                    { left = L["Craftable Tooltips"], right = (not s or s.tooltipRecipeAlts ~= false) and onLbl or offLbl },
                    { left = L["Guild Recipe Replies"], right = (not s or s.guildRecipeReply ~= false) and onLbl or offLbl },
                }
            end,
            buildMenu = function(root)
                local s = ns.db and ns.db.settings
                root:CreateTitle("SocialCentral — " .. L["Official Professions (Recipes)"])
                root:CreateCheckbox(L["Show 'Craftable by' in Item Tooltips"], function()
                    return not s or s.tooltipRecipeAlts ~= false
                end, function()
                    if s then s.tooltipRecipeAlts = not (s.tooltipRecipeAlts ~= false) end
                    ns:Emit("SETTINGS_UPDATED")
                    LFGFrameTab:RefreshProfessionQuickButton()
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                end)
                root:CreateCheckbox(L["Answer Guild Recipe Searches"], function()
                    return not s or s.guildRecipeReply ~= false
                end, function()
                    if s then s.guildRecipeReply = not (s.guildRecipeReply ~= false) end
                    ns:Emit("SETTINGS_UPDATED")
                    LFGFrameTab:RefreshProfessionQuickButton()
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                end)

                root:CreateDivider()
                root:CreateButton(L["Search All Alt Recipes (C)..."], function()
                    if ns.NavigateToModule then
                        ns:NavigateToModule("alts", { altSubTab = "items", altBagSource = "recipes", altAllAlts = true })
                    end
                end)
                if not Compat.ShouldShowGuildFeatures or Compat.ShouldShowGuildFeatures() then
                    root:CreateButton(L["Guild Professions & Requests (J)..."], function()
                        if ns.NavigateToModule then
                            ns:NavigateToModule("clan", { clanRightView = "prof" })
                        end
                    end)
                end

                root:CreateDivider()
                root:CreateButton(L["Disable in this window"], function()
                    if s then s.embedProfessionWindow = false end
                    LFGFrameTab:RefreshProfessionQuickButton()
                    ns:Emit("SETTINGS_UPDATED")
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                    ns:Print("%s", L["Disabled in this window. Re-enable anytime in Settings (/sc)."])
                end)
                root:CreateButton(L["Settings"], function()
                    if ns.Settings and ns.Settings.Open then ns.Settings:Open("overview") end
                end)
            end,
        })
        btn:SetClampedToScreen(true)
        self.profQuickBtn = btn
    end
    self:RefreshProfessionQuickButton()
end

-- ============================================================================
local function OpenSocialUIModule(targetTab, fallbackToChatFrame, forceKeepOpen)
    if targetTab ~= "chat" and targetTab ~= "rooms" then
        local sf = _G.SocialUIFrame or _G.FriendsFrame
        local allowEmbed = not (ns.Compat and ns.Compat.IsWindowIntegrationEnabled) or ns.Compat.IsWindowIntegrationEnabled("O")
        if allowEmbed and sf and sf.IsShown and sf:IsShown() then
            LFGFrameTab:AttachSocialUI()
            LFGFrameTab:EnsureSocialSideTab()
            if ns.UI and ns.UI.OpenEmbedded then
                ns.UI:OpenEmbedded(sf, { "watchlist", "social", "nearby" }, targetTab, forceKeepOpen ~= false)
                return
            end
        end
    end
    if ns.UI and ns.UI.ShowHub then
        ns.UI:ShowHub(targetTab)
    end
end

function LFGFrameTab:SyncAllEmbeddedTabStates(forceGeoSync)
    local nowT = (GetTime and GetTime()) or 0
    if self.sideTab then
        local lfgHost = _G.LFGParentFrame
        local shown = lfgHost and lfgHost.IsShown and lfgHost:IsShown()
        local active = self.active == true
        local groupEmbedActive = (ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(lfgHost)) == true
        local anyLfgEmbed = active or groupEmbedActive
        if shown or active then
            UpdateSideTabBadge(self.sideTab, 0, "group")
            if shown then
                self:UpdateNativeBridgeBar()
            end
        end
        if shown or not anyLfgEmbed then
            local sig = (shown and "S:" or "H:") .. (anyLfgEmbed and "A" or "N")
            if not lfgHost or lfgHost._scLastNativeTabSig ~= sig or forceGeoSync then
                if lfgHost then lfgHost._scLastNativeTabSig = sig end
                SyncHostNativeTabs(lfgHost, self.sideTab, anyLfgEmbed, { "ListingTab", "BrowsingTab", "WhoListingTab" })
            end
        end
        if shown and self.sideTab:IsShown() and (forceGeoSync or not self.sideTab._lastGeoSyncAt or (nowT - self.sideTab._lastGeoSyncAt) >= 1.0) then
            self.sideTab._lastGeoSyncAt = nowT
            SyncRightSideTabHitboxAndLayer(lfgHost, self.sideTab, DiscoverNativeSideTabs(lfgHost), 600)
        end
    end
    if self.socialTab then
        local socialHost = _G.SocialUIFrame or _G.FriendsFrame
        local shown = socialHost and socialHost.IsShown and socialHost:IsShown()
        local active = ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(socialHost)
        UpdateSideTabVisual(self.socialTab, active)
        UpdateSideTabBadge(self.socialTab, 0, "whisper")
        if shown or not active then
            local sig = (shown and "S:" or "H:") .. (active and "A" or "N")
            if not socialHost or socialHost._scLastNativeTabSig ~= sig or forceGeoSync then
                if socialHost then socialHost._scLastNativeTabSig = sig end
                SyncHostNativeTabs(socialHost, self.socialTab, active, nil)
            end
        end
        if shown and self.socialTab:IsShown() and (forceGeoSync or not self.socialTab._lastGeoSyncAt or (nowT - self.socialTab._lastGeoSyncAt) >= 1.0) then
            self.socialTab._lastGeoSyncAt = nowT
            SyncRightSideTabHitboxAndLayer(socialHost, self.socialTab, DiscoverRightSideTabs(socialHost, self.socialTab), 600)
        end
    end
    if self.guildTab then
        local guildHost = _G.CommunitiesFrame or _G.GuildFrame
        local shown = guildHost and guildHost.IsShown and guildHost:IsShown()
        local active = ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(guildHost)
        local guildUnread = (ns.Clan and ns.Clan.GetNotificationCount and ns.Clan:GetNotificationCount()) or 0
        UpdateSideTabVisual(self.guildTab, active)
        UpdateSideTabBadge(self.guildTab, active and 0 or guildUnread, "guild")
        if shown or not active then
            local sig = (shown and "S:" or "H:") .. (active and "A" or "N")
            if not guildHost or guildHost._scLastNativeTabSig ~= sig or forceGeoSync then
                if guildHost then guildHost._scLastNativeTabSig = sig end
                SyncHostNativeTabs(guildHost, self.guildTab, active, COMMUNITIES_NATIVE_TABS)
            end
        end
        if shown and self.guildTab:IsShown() and (forceGeoSync or not self.guildTab._lastGeoSyncAt or (nowT - self.guildTab._lastGeoSyncAt) >= 1.0) then
            self.guildTab._lastGeoSyncAt = nowT
            SyncRightSideTabHitboxAndLayer(guildHost, self.guildTab, DiscoverRightSideTabs(guildHost, self.guildTab, COMMUNITIES_NATIVE_TABS), 600)
        end
    end
    if self.charTab then
        local charHost = _G.CharacterFrame
        local shown = charHost and charHost.IsShown and charHost:IsShown()
        local active = ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(charHost)
        UpdateSideTabVisual(self.charTab, active)
        if shown or not active then
            local sig = (shown and "S:" or "H:") .. (active and "A" or "N")
            if not charHost or charHost._scLastNativeTabSig ~= sig or forceGeoSync then
                if charHost then charHost._scLastNativeTabSig = sig end
                SyncHostNativeTabs(charHost, self.charTab, active, CHARACTER_NATIVE_TABS)
            end
        end
        if shown and self.charTab:IsShown() and (forceGeoSync or not self.charTab._lastGeoSyncAt or (nowT - self.charTab._lastGeoSyncAt) >= 1.0) then
            self.charTab._lastGeoSyncAt = nowT
            SyncRightSideTabHitboxAndLayer(charHost, self.charTab, DiscoverRightSideTabs(charHost, self.charTab, CHARACTER_NATIVE_TABS), 600)
        end
    end
end

function LFGFrameTab:GetShortcutWindowMeta(winKey)
    if winKey == "O" then
        return { key = "O", name = L["Social & Friends"] }
    elseif winKey == "I" then
        return { key = "I", name = L["Group Finder"] }
    elseif winKey == "J" then
        return { key = "J", name = L["Guild & Communities"] }
    elseif winKey == "C" then
        return { key = "C", name = L["Character & My Alts"] }
    end
    return nil
end

function LFGFrameTab:IsShortcutEligible(winKey)
    if not self:GetShortcutWindowMeta(winKey) then
        return false
    end
    if ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled(winKey) then
        return false
    end
    if winKey == "O" and ns.Compat and ns.Compat.IsModuleEnabled then
        for _, cand in ipairs({ "watchlist", "social", "nearby" }) do
            if ns.Compat.IsModuleEnabled(cand) then
                return true
            end
        end
        return false
    end
    return true
end

function LFGFrameTab:ActivateAddonTabForShortcut(winKey, hostFrame)
    if IsCombatLocked() or not self:IsShortcutEligible(winKey) then
        return false
    end
    if not (hostFrame and hostFrame.IsShown and hostFrame:IsShown()) then
        return false
    end
    if winKey == "I" then
        if self.active then
            return true
        end
        if ns.Clan and ns.Clan.RequestClanSync and IsInGuild and IsInGuild() then
            ns.Clan:RequestClanSync()
        end
        self.viewMode = "browse"
        self:ShowSubPanel()
        return true
    elseif winKey == "O" then
        if ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(hostFrame) then
            return true
        end
        local targetTab
        for _, cand in ipairs({ "watchlist", "social", "nearby" }) do
            if not ns.Compat or not ns.Compat.IsModuleEnabled or ns.Compat.IsModuleEnabled(cand) then
                targetTab = cand
                break
            end
        end
        if targetTab and ns.UI and ns.UI.OpenEmbedded then
            ns.UI:OpenEmbedded(hostFrame, { "watchlist", "social", "nearby" }, targetTab, true)
            return true
        end
    elseif winKey == "J" then
        if ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(hostFrame) then
            return true
        end
        if ns.UI and ns.UI.OpenEmbedded then
            ns.UI:OpenEmbedded(hostFrame, { "clan" }, "clan", true)
            return true
        end
    elseif winKey == "C" then
        if ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(hostFrame) then
            return true
        end
        if ns.UI and ns.UI.OpenEmbedded then
            ns.UI:OpenEmbedded(hostFrame, { "alts" }, "alts", true)
            return true
        end
    end
    return false
end

function LFGFrameTab:ApplyShortcutAutoOpenChoice(winKey, openAddonDirectly, applyAll, hostFrame)
    if not (ns.db and ns.db.settings) then
        return
    end
    local s = ns.db.settings
    if type(s.shortcutAutoOpenAddon) ~= "table" then
        s.shortcutAutoOpenAddon = {}
    end
    if type(s.shortcutPromptAnswered) ~= "table" then
        s.shortcutPromptAnswered = {}
    end
    self._shortcutPromptDismissed = self._shortcutPromptDismissed or {}

    local function IsSettingEnabledForKey(k)
        if k == "O" then return s.embedSocialWindow ~= false end
        if k == "I" then return s.embedLfgWindow ~= false end
        if k == "J" then return s.embedGuildWindow ~= false end
        if k == "C" then return s.embedCharacterWindow ~= false end
        return false
    end

    local targets = {}
    if applyAll then
        for _, k in ipairs({ "O", "I", "J", "C" }) do
            if IsSettingEnabledForKey(k) or k == winKey then
                targets[#targets + 1] = k
            end
        end
    elseif winKey then
        targets[#targets + 1] = winKey
    end

    local openFlag = (openAddonDirectly == true)
    for _, k in ipairs(targets) do
        s.shortcutAutoOpenAddon[k] = openFlag
        s.shortcutPromptAnswered[k] = true
        self._shortcutPromptDismissed[k] = nil
    end

    local meta = self:GetShortcutWindowMeta(winKey)
    local winLabel = (meta and (meta.name .. " (" .. meta.key .. ")")) or tostring(winKey or "?")
    if applyAll then
        if openFlag then
            ns:Print(L["Saved for all enabled shortcuts (%s): windows will open directly on the SocialCentral tab."]:format(table.concat(targets, ", ")))
        else
            ns:Print(L["Saved for all enabled shortcuts (%s): windows will keep opening on Blizzard's default tab."]:format(table.concat(targets, ", ")))
        end
    else
        if openFlag then
            ns:Print(L["Saved for %s: shortcut will open directly on the SocialCentral tab."]:format(winLabel))
        else
            ns:Print(L["Saved for %s: shortcut will keep opening on Blizzard's default tab."]:format(winLabel))
        end
    end

    ns:Emit("SETTINGS_UPDATED")
    if ns.Settings and ns.Settings.Refresh then
        ns.Settings:Refresh()
    end

    if openFlag and winKey and hostFrame and hostFrame.IsShown and hostFrame:IsShown() and not IsCombatLocked() then
        self:ActivateAddonTabForShortcut(winKey, hostFrame)
    end
end

function LFGFrameTab:ShowShortcutAutoOpenPrompt(winKey, hostFrame)
    if IsCombatLocked() then
        return
    end
    local meta = self:GetShortcutWindowMeta(winKey)
    if not meta then return end

    local m = self._shortcutPromptModal
    if not m then
        m = CreateFrame("Frame", "SocialCentralShortcutPromptModal", UIParent, "BackdropTemplate")
        m:SetSize(486, 278)
        m:SetPoint("CENTER")
        if Theme.PrepareTopOverlayModal then
            Theme:PrepareTopOverlayModal(m, 860)
        else
            m:SetFrameStrata("FULLSCREEN_DIALOG")
            m:SetFrameLevel(860)
            m:SetToplevel(true)
            m:EnableMouse(true)
        end
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        Theme:MakeMovable(m, { key = "modal_shortcut_prompt" })
        if type(UISpecialFrames) == "table" then
            table.insert(UISpecialFrames, "SocialCentralShortcutPromptModal")
        end
        m:RegisterEvent("PLAYER_REGEN_DISABLED")
        m:SetScript("OnEvent", function(selfM, ev)
            if ev == "PLAYER_REGEN_DISABLED" and selfM:IsShown() then
                selfM:Hide()
            end
        end)

        local solidBg = m:CreateTexture(nil, "BACKGROUND", nil, -8)
        solidBg:SetAllPoints(m)
        solidBg:SetTexture(WHITE8X8)
        solidBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
        m._solidOpaqueBg = solidBg

        local icon = m:CreateTexture(nil, "OVERLAY")
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", 14, -12)
        icon:SetTexture(ICON_TEX)

        local closeBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        closeBtn:SetPoint("TOPRIGHT", -10, -10)
        closeBtn:SetScript("OnClick", function()
            if m._winKey then
                LFGFrameTab._shortcutPromptDismissed = LFGFrameTab._shortcutPromptDismissed or {}
                LFGFrameTab._shortcutPromptDismissed[m._winKey] = true
            end
            m:Hide()
        end)
        m.closeBtn = closeBtn

        local helpBtn = Theme:CreateHelpButton(
            m,
            L["Help: Shortcut Auto-Open"],
            L["Lets you choose whether pressing an official game window shortcut (O, I, J, C) jumps straight to the SocialCentral tab or opens Blizzard's default tab."],
            L["Choose whether to apply this preference to only the current shortcut or to all enabled shortcuts, and change it anytime in Settings."],
            16,
            { target = m }
        )
        helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
        m.helpBtn = helpBtn

        local titleFs = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        titleFs:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        titleFs:SetPoint("RIGHT", helpBtn, "LEFT", -6, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        m.titleFs = titleFs

        local bodyFs = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        bodyFs:SetPoint("TOPLEFT", 16, -42)
        bodyFs:SetPoint("TOPRIGHT", -16, -42)
        bodyFs:SetJustifyH("LEFT")
        bodyFs:SetWordWrap(true)
        m.bodyFs = bodyFs

        local scopeBox = CreateFrame("Frame", nil, m, "BackdropTemplate")
        scopeBox:SetPoint("TOPLEFT", bodyFs, "BOTTOMLEFT", 0, -10)
        scopeBox:SetPoint("TOPRIGHT", bodyFs, "BOTTOMRIGHT", 0, -10)
        scopeBox:SetHeight(68)
        m.scopeBox = scopeBox

        local singleCb = CreateFrame("CheckButton", nil, scopeBox, "UICheckButtonTemplate")
        singleCb:SetSize(22, 22)
        singleCb:SetPoint("TOPLEFT", 8, -8)
        local singleLbl = singleCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        singleLbl:SetPoint("LEFT", singleCb, "RIGHT", 4, 0)
        singleLbl:SetPoint("RIGHT", scopeBox, "RIGHT", -10, 0)
        singleLbl:SetJustifyH("LEFT")
        singleLbl:SetWordWrap(true)
        m.singleCb = singleCb
        m.singleLbl = singleLbl

        local allCb = CreateFrame("CheckButton", nil, scopeBox, "UICheckButtonTemplate")
        allCb:SetSize(22, 22)
        allCb:SetPoint("TOPLEFT", singleCb, "BOTTOMLEFT", 0, -6)
        local allLbl = allCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        allLbl:SetPoint("LEFT", allCb, "RIGHT", 4, 0)
        allLbl:SetPoint("RIGHT", scopeBox, "RIGHT", -10, 0)
        allLbl:SetJustifyH("LEFT")
        allLbl:SetWordWrap(true)
        m.allCb = allCb
        m.allLbl = allLbl

        local function SyncScopeChecks()
            local isAll = (m._scope == "ALL")
            singleCb:SetChecked(not isAll)
            allCb:SetChecked(isAll)
        end
        singleCb:SetScript("OnClick", function()
            m._scope = "SINGLE"
            SyncScopeChecks()
        end)
        allCb:SetScript("OnClick", function()
            m._scope = "ALL"
            SyncScopeChecks()
        end)
        m.SyncScopeChecks = SyncScopeChecks

        local btnAddon = Theme:CreateButton(m, 198, 26, L["Open SocialCentral Tab"], "primary")
        Theme:AutoFitButton(btnAddon, 150, 18, 206)
        btnAddon:SetPoint("BOTTOMRIGHT", -16, 32)
        btnAddon:SetScript("OnClick", function()
            local wKey = m._winKey
            local hFrame = m._hostFrame
            local applyAll = (m._scope == "ALL")
            m:Hide()
            LFGFrameTab:ApplyShortcutAutoOpenChoice(wKey, true, applyAll, hFrame)
        end)
        m.btnAddon = btnAddon

        local btnOfficial = Theme:CreateButton(m, 198, 26, L["Keep Blizzard Official Tab"], "default")
        Theme:AutoFitButton(btnOfficial, 150, 18, 206)
        btnOfficial:SetPoint("RIGHT", btnAddon, "LEFT", -10, 0)
        btnOfficial:SetScript("OnClick", function()
            local wKey = m._winKey
            local hFrame = m._hostFrame
            local applyAll = (m._scope == "ALL")
            m:Hide()
            LFGFrameTab:ApplyShortcutAutoOpenChoice(wKey, false, applyAll, hFrame)
        end)
        m.btnOfficial = btnOfficial

        local tipFs = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tipFs:SetPoint("BOTTOMLEFT", 16, 12)
        tipFs:SetPoint("BOTTOMRIGHT", -16, 12)
        tipFs:SetJustifyH("LEFT")
        tipFs:SetWordWrap(false)
        tipFs:SetText(L["You can change this anytime in Settings -> Summary & Windows."])
        m.tipFs = tipFs

        self._shortcutPromptModal = m
    end

    if m:IsShown() and m._winKey == winKey then
        m._hostFrame = hostFrame
        if m.Raise then m:Raise() end
        return
    end

    m._winKey = winKey
    m._hostFrame = hostFrame
    m._scope = "SINGLE"
    if m.SyncScopeChecks then m.SyncScopeChecks() end

    local p = Theme:GetPalette()
    if Theme.PrepareTopOverlayModal then
        Theme:PrepareTopOverlayModal(m, 860)
    else
        m:SetParent(UIParent)
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(860)
        m:SetToplevel(true)
    end
    if m._solidOpaqueBg then
        local wBg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
        m._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
    end
    Theme:ApplyBackdrop(m, "window", p)
    if m.scopeBox then
        Theme:ApplyBackdrop(m.scopeBox, "surface", p)
    end
    Theme:StyleButton(m.closeBtn, "default")
    Theme:StyleButton(m.btnAddon, "primary")
    Theme:StyleButton(m.btnOfficial, "default")

    local eligibleKeys = {}
    for _, k in ipairs({ "O", "I", "J", "C" }) do
        if self:IsShortcutEligible(k) or k == winKey then
            eligibleKeys[#eligibleKeys + 1] = k
        end
    end

    m.titleFs:SetText(string.format(L["Shortcut Behavior — %s (%s)"], meta.name, meta.key))
    m.bodyFs:SetText(string.format(L["You opened %s (%s) with SocialCentral integration enabled.\nWould you like this shortcut to open directly on the SocialCentral tab instead of Blizzard's default tab?"], meta.name, meta.key))
    m.singleLbl:SetText(string.format(L["Apply only to this shortcut (%s)"], meta.key))
    m.allLbl:SetText(string.format(L["Apply to all applicable shortcuts (%s)"], table.concat(eligibleKeys, ", ")))

    m:Show()
    if m.Raise then m:Raise() end
end

function LFGFrameTab:HandleOfficialShortcutOpen(winKey, hostFrame)
    if IsCombatLocked() or not (hostFrame and hostFrame.IsShown and hostFrame:IsShown()) then
        return
    end
    if not self:IsShortcutEligible(winKey) then
        return
    end
    if winKey == "I" and self.active then
        return
    end
    if ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(hostFrame) then
        return
    end
    if winKey == "C" and _G.PaperDollFrame and _G.PaperDollFrame.IsShown and not _G.PaperDollFrame:IsShown() then
        return
    end
    if winKey == "I" and _G.LFGWhoListFrame and _G.LFGWhoListFrame.IsShown and _G.LFGWhoListFrame:IsShown() then
        return
    end

    local s = ns.db and ns.db.settings
    local answered = s and type(s.shortcutPromptAnswered) == "table" and s.shortcutPromptAnswered[winKey] == true
    local autoOpen = s and type(s.shortcutAutoOpenAddon) == "table" and s.shortcutAutoOpenAddon[winKey] == true
    if answered then
        if autoOpen then
            self:ActivateAddonTabForShortcut(winKey, hostFrame)
        end
        return
    end

    if self._shortcutPromptDismissed and self._shortcutPromptDismissed[winKey] then
        return
    end
    self:ShowShortcutAutoOpenPrompt(winKey, hostFrame)
end

function LFGFrameTab:OpenOfficialModule(moduleId, forceKeepOpen)
    if IsCombatLocked() then
        ns:Print("%s", L["Unavailable during combat."])
        return
    end
    local mod = (moduleId or ""):lower()

    if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled(mod) then
        if mod == "clan" or mod == "diplomacy" then
            if ns.Compat.ShouldShowGuildFeatures and not ns.Compat.ShouldShowGuildFeatures() then
                ns:Print("%s", L["Your character is not currently in a guild."])
                return
            end
        end
        ns:Print("%s", L["This module is disabled in Settings."])
        return
    end
    if ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled(mod) then
        if mod == "lfg" then
            ns:Print("%s", L["Group Finder (I) integration is disabled in Settings."])
            return
        elseif mod == "alts" or mod == "buffs" then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        if ns.UI and ns.UI.ShowHub then
            ns.UI:ShowHub(mod == "diplomacy" and "clan" or mod)
            return
        end
    end

    if mod == "lfg" then
        if _G.LFGParentFrame and _G.LFGParentFrame:IsShown() then
            LFGFrameTab:AttachHooks()
            LFGFrameTab:EnsureSideTab()
            LFGFrameTab:ShowSubPanel()
        else
            LFGFrameTab:ShowSubPanel(EnsureStandaloneLfgHost())
        end
        return
    end

    if mod == "group" then
        if ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled("I") then
            if ns.UI and ns.UI.ShowHub then
                ns.UI:ShowHub("group")
            end
            return
        end
        if _G.LFGParentFrame and _G.LFGParentFrame:IsShown() then
            if LFGFrameTab.HideSubPanel then
                LFGFrameTab:HideSubPanel(false)
            end
            if ns.UI and ns.UI.OpenEmbedded then
                ns.UI:OpenEmbedded(_G.LFGParentFrame, { "group" }, "group")
                return
            end
        end
        if ns.UI and ns.UI.ShowHub then
            ns.UI:ShowHub("group")
        end
        return
    end

    if mod == "watchlist" or mod == "social" or mod == "nearby" then
        OpenSocialUIModule(mod, false, forceKeepOpen)
        return
    end

    if mod == "clan" or mod == "diplomacy" then
        if mod == "diplomacy" and ns.Clan and ns.Clan.SetPreferredRightView then
            ns.Clan:SetPreferredRightView("diplomacy")
        end
        local cf = _G.CommunitiesFrame or _G.GuildFrame
        if cf and cf:IsShown() then
            LFGFrameTab:AttachCommunitiesUI()
            LFGFrameTab:EnsureGuildSideTab()
            if ns.UI and ns.UI.OpenEmbedded then
                ns.UI:OpenEmbedded(cf, { "clan" }, "clan", forceKeepOpen)
                return
            end
        end
        if ns.UI and ns.UI.ShowHub then
            ns.UI:ShowHub("clan")
        end
        return
    end

    if mod == "alts" then
        if _G.CharacterFrame and _G.CharacterFrame:IsShown() then
            LFGFrameTab:AttachCharacterUI()
            LFGFrameTab:EnsureCharacterSideTab()
            if ns.UI and ns.UI.OpenEmbedded then
                ns.UI:OpenEmbedded(_G.CharacterFrame, { "alts" }, "alts", forceKeepOpen)
                return
            end
        end
        if ns.UI and ns.UI.ShowHub then
            ns.UI:ShowHub("alts")
        end
        return
    end

    if mod == "chat" or mod == "rooms" then
        if ns.UI and ns.UI.ShowHub then
            ns.UI:ShowHub("chat")
        end
        return
    end

    if ns.UI and ns.UI.ShowHub then
        ns.UI:ShowHub(moduleId)
    end
end

function LFGFrameTab:Init()
    Theme:RegisterListener(function()
        LFGFrameTab:RefreshTheme()
    end)

    local refreshQueued = false
    local syncEmbeddedQueued = false
    local function IsAnyEmbeddedHostShown()
        local lfgHost = _G.LFGParentFrame
        local socialHost = _G.SocialUIFrame or _G.FriendsFrame
        local guildHost = _G.CommunitiesFrame or _G.GuildFrame
        local charHost = _G.CharacterFrame
        return (lfgHost and lfgHost.IsShown and lfgHost:IsShown())
            or (socialHost and socialHost.IsShown and socialHost:IsShown())
            or (guildHost and guildHost.IsShown and guildHost:IsShown())
            or (charHost and charHost.IsShown and charHost:IsShown())
    end
    local function RunCoalescedRefresh()
        refreshQueued = false
        if _G.LFGParentFrame and _G.LFGParentFrame:IsShown() then
            LFGFrameTab:UpdateNativeBridgeBar()
        end
        if LFGFrameTab.active and LFGFrameTab.subPanel and LFGFrameTab.subPanel:IsShown() then
            LFGFrameTab:RefreshData()
        elseif IsAnyEmbeddedHostShown() then
            LFGFrameTab:SyncAllEmbeddedTabStates()
        end
    end
    local function RefreshIfOpen()
        if C_Timer and C_Timer.After then
            if refreshQueued then return end
            refreshQueued = true
            C_Timer.After(0.08, RunCoalescedRefresh)
        else
            RunCoalescedRefresh()
        end
    end

    self._hadOfficialActiveEntry = (C_LFGList and C_LFGList.HasActiveEntryInfo and Safe.Value(Safe.Call(C_LFGList.HasActiveEntryInfo))) == true
    ns:On("CLAN_UPDATED", RefreshIfOpen)
    ns:On("CLAN_DIPLOMACY_UPDATED", RefreshIfOpen)
    ns:On("LFG_BROWSE_STATE_CHANGED", RefreshIfOpen)
    ns:On("SOCIAL_UPDATED", RefreshIfOpen)
    ns:On("WATCHLIST_UPDATED", RefreshIfOpen)
    ns:On("GROUP_UPDATED", RefreshIfOpen)
    ns.RegisterEvent(self, "GROUP_ROSTER_UPDATE", RefreshIfOpen)
    ns.RegisterEvent(self, "PARTY_LEADER_CHANGED", RefreshIfOpen)
    ns.RegisterEvent(self, "LFG_LIST_ACTIVE_ENTRY_UPDATE", function(_, _, created)
        RefreshIfOpen()
        LFGFrameTab:HandleOfficialActiveEntryUpdate(created)
    end)
    local function SyncEmbeddedIfAnyHostShown()
        if IsAnyEmbeddedHostShown() then
            if C_Timer and C_Timer.After then
                if syncEmbeddedQueued then return end
                syncEmbeddedQueued = true
                C_Timer.After(0.14, function()
                    syncEmbeddedQueued = false
                    if IsAnyEmbeddedHostShown() then
                        LFGFrameTab:SyncAllEmbeddedTabStates()
                    end
                end)
            else
                LFGFrameTab:SyncAllEmbeddedTabStates()
            end
        end
    end

    ns:On("CHAT_UPDATED", SyncEmbeddedIfAnyHostShown)
    ns:On("CLAN_UPDATED", SyncEmbeddedIfAnyHostShown)
    ns:On("GROUP_UPDATED", SyncEmbeddedIfAnyHostShown)
    ns:On("SOCIAL_UPDATED", SyncEmbeddedIfAnyHostShown)
    ns:On("WATCHLIST_UPDATED", SyncEmbeddedIfAnyHostShown)
    ns:On("ADDON_MESSAGE_NOTIFY", SyncEmbeddedIfAnyHostShown)

    local tryAttachPending = false
    local function TryAttachAll()
        tryAttachPending = false
        if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
            if ns.RunAfterCombat then
                ns:RunAfterCombat("lfg_try_attach_all", TryAttachAll, false)
            end
            return
        end
        LFGFrameTab:AttachHooks()
        LFGFrameTab:AttachSocialUI()
        LFGFrameTab:AttachCommunitiesUI()
        LFGFrameTab:AttachCharacterUI()
        LFGFrameTab:AttachChatButton()
        LFGFrameTab:AttachProfessionButton()
        if _G.LFGParentFrame and _G.LFGParentFrame.IsShown and _G.LFGParentFrame:IsShown() then
            LFGFrameTab:EnsureSideTab()
        end
        if (_G.SocialUIFrame or _G.FriendsFrame) and (_G.SocialUIFrame or _G.FriendsFrame):IsShown() then
            LFGFrameTab:EnsureSocialSideTab()
        end
        if (_G.CommunitiesFrame or _G.GuildFrame) and (_G.CommunitiesFrame or _G.GuildFrame):IsShown() then
            LFGFrameTab:EnsureGuildSideTab()
        end
        if _G.CharacterFrame and _G.CharacterFrame:IsShown() then
            LFGFrameTab:EnsureCharacterSideTab()
        end
    end
    local function QueueTryAttachAll()
        if tryAttachPending then return end
        tryAttachPending = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0, TryAttachAll)
        else
            TryAttachAll()
        end
    end

    ns:On("SETTINGS_UPDATED", function()
        QueueTryAttachAll()
        SyncEmbeddedIfAnyHostShown()
    end)

    ns.RegisterEvent(self, "PLAYER_GUILD_UPDATE", function(_, _, unit)
        if not unit or unit == "player" then
            QueueTryAttachAll()
            SyncEmbeddedIfAnyHostShown()
        end
    end)

    ns.RegisterEvent(self, "ADDON_LOADED", function(_, _, loadedName)
        if loadedName == "Blizzard_GroupFinder_VanillaStyle"
            or loadedName == "Blizzard_SocialUI"
            or loadedName == "Blizzard_FriendsFrame"
            or loadedName == "Blizzard_Communities"
            or loadedName == "Blizzard_GuildUI"
            or loadedName == "Blizzard_CharacterFrame"
            or loadedName == "Blizzard_UIPanels_Game"
            or loadedName == "Blizzard_WorldMap"
            or loadedName == "Blizzard_TradeSkillUI"
            or loadedName == "Blizzard_Professions"
            or loadedName == "Blizzard_CraftUI"
        then
            QueueTryAttachAll()
        end
    end)

    for _, profEv in ipairs({ "TRADE_SKILL_SHOW", "CRAFT_SHOW" }) do
        ns.RegisterEvent(self, profEv, function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.05, function() LFGFrameTab:AttachProfessionButton() end)
            else
                LFGFrameTab:AttachProfessionButton()
            end
        end)
    end

    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        LFGFrameTab._hadOfficialActiveEntry = (C_LFGList and C_LFGList.HasActiveEntryInfo and Safe.Value(Safe.Call(C_LFGList.HasActiveEntryInfo))) == true
        LFGFrameTab:SyncAllEmbeddedTabStates()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, TryAttachAll)
        else
            TryAttachAll()
        end
    end)

    for _, fnName in ipairs({
        "LFGVanilla_ShowFrame", "LFGVanilla_ToggleFrame", "ToggleLFGParentFrame",
        "ToggleFriendsFrame", "ToggleCommunitiesFrame", "ToggleGuildFrame",
        "ToggleCharacter", "ToggleWorldMap",
    }) do
        if hooksecurefunc and type(_G[fnName]) == "function" then
            hooksecurefunc(fnName, QueueTryAttachAll)
        end
    end

    TryAttachAll()
end
