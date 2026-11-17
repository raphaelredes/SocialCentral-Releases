local _, ns = ...

local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })
local Safe = ns.Safe
local Compat = ns.Compat
local Store = ns.Store
local Theme = ns.Theme

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local ICON_TEX = "Interface\\AddOns\\SocialCentral\\Media\\icon"

local LFGFrameTab = {
    sideTab = nil,
    subPanel = nil,
    active = false,
    hooked = false,
    viewMode = "categories",     -- "categories" | "activities" | "browse"
    activeCategory = "DUNGEONS", -- "DUNGEONS" | "RAIDS" | "QUESTS" | "PVP" | "CUSTOM"
    roles = { TANK = false, HEALER = false, DPS = false, GUIDE = false },
    rolesInitialized = false,
    listingMode = "LFG",         -- "LFG" | "LFM"
    playstyle = "NONE",          -- "NONE" | "NORMAL" | "FAST" | "FULL"
    showAllLevels = false,
    broadcastMode = "ALL",       -- "ALL" | "GCHAT" | "CLAN"
    selectedActivities = {},     -- activityId -> true
    commentText = "",
    composerRole = "ANY",
    composerMode = "LFG",
    categoryFilter = "ALL",      -- "ALL" | "DUNGEONS" | "RAIDS" | "QUESTS" | "PVP" | "CUSTOM"
    sourceFilter = "ALL",        -- "ALL" | "CLAN" | "ALLY" | "FRIENDS"
    dungeonsOnly = false,
    composerOpen = false,
    selectedKey = nil,
    selectedItem = nil,
    query = "",
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
        { id = "dng_thanes", labelKey = "Hall of Thanes", minLvl = 13, maxLvl = 20 },
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
    { id = "ALL", labelKey = "Clan & Allied Clans" },
    { id = "OFFICIAL", labelKey = "Clan, Allies + Official LFG" },
    { id = "GCHAT", labelKey = "Clan, Allies + Guild Chat (/g)" },
    { id = "CLAN", labelKey = "My Clan Only" },
}

local SOURCE_FILTERS = {
    { id = "ALL", labelKey = "All", dropdownKey = "Filter: All" },
    { id = "CLAN", labelKey = "Same Clan", dropdownKey = "Filter: Same Clan" },
    { id = "ALLY", labelKey = "Allied Clans", dropdownKey = "Filter: Allied Clans" },
    { id = "FRIENDS", labelKey = "Friends / Watchlist", dropdownKey = "Filter: Friends & Watchlist" },
    { id = "PUBLIC_CHAT", labelKey = "Global Chat LFG", dropdownKey = "Filter: Global Chat LFG" },
}

local function GetCategoryLabel(catId)
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
    return L["Clan & Allied Clans"]
end

local function GetSourceFilterDropdownLabel(sourceId)
    for _, opt in ipairs(SOURCE_FILTERS) do
        if opt.id == sourceId then
            return L[opt.dropdownKey]
        end
    end
    return L["Filter: All"]
end

local function GetItemIdentityKey(item)
    if not item then return nil end
    return tostring(item.sourceType or "LFG") .. ":" .. tostring(item.eventId or item.lookupKey or item.displayName or "?")
end

local function GetActivityLockout(item, cachedLocks)
    if not (item and type(cachedLocks) == "table" and #cachedLocks > 0) then
        return nil
    end
    local hay = ((item.activity or "") .. " " .. (item.note or "")):lower()
    if #hay < 3 then return nil end
    for _, lk in ipairs(cachedLocks) do
        if type(lk) == "table" and lk.locked and not lk.extended then
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
    if catId == "DUNGEONS" then
        return item and item.isDungeon == true
    end
    local hay = (
        (item and item.activity or "") .. " " ..
        (item and item.note or "") .. " " ..
        (item and item.sourceType or "")
    ):lower()
    if catId == "RAIDS" then
        return hay:find("raid") ~= nil or hay:find("raide") ~= nil or hay:find("banda") ~= nil
            or hay:find("molten") ~= nil or hay:find("nucleo") ~= nil or hay:find("núcleo") ~= nil
            or hay:find("onyx") ~= nil or hay:find("bwl") ~= nil or hay:find("covil") ~= nil
            or hay:find("guarida") ~= nil or hay:find("naxx") ~= nil or hay:find("zg") ~= nil
            or hay:find("zul") ~= nil or hay:find("aq20") ~= nil or hay:find("aq40") ~= nil
            or hay:find("ahn'qiraj") ~= nil or hay:find("boss") ~= nil or hay:find("chefe") ~= nil
            or hay:find("jefe") ~= nil
    elseif catId == "QUESTS" then
        return hay:find("quest") ~= nil or hay:find("miss") ~= nil or hay:find("mision") ~= nil
            or hay:find("zona") ~= nil or hay:find("zone") ~= nil or hay:find("area") ~= nil
            or hay:find("área") ~= nil or hay:find("level") ~= nil or hay:find("farm") ~= nil
            or hay:find("grind") ~= nil or hay:find("elite") ~= nil
    elseif catId == "PVP" then
        return hay:find("pvp") ~= nil or hay:find("jcj") ~= nil or hay:find("arena") ~= nil
            or hay:find("bg") ~= nil or hay:find("wsg") ~= nil or hay:find("ab") ~= nil
            or hay:find("av") ~= nil or hay:find("batalha") ~= nil or hay:find("batalla") ~= nil
            or hay:find("battle") ~= nil or hay:find("warsong") ~= nil or hay:find("arathi") ~= nil
            or hay:find("alterac") ~= nil or hay:find("patrulha") ~= nil or hay:find("scout") ~= nil
    elseif catId == "CUSTOM" then
        return not (item and item.isDungeon == true)
    end
    return true
end

local function HasAtlas(name)
    return ns.Theme and ns.Theme.HasAtlas and ns.Theme:HasAtlas(name)
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
    if root.GetChildren then
        local children = { root:GetChildren() }
        for i = 1, #children do
            local childMax = MaxHierarchyLevel(children[i], (depth or 1) - 1)
            if childMax > maxLvl then
                maxLvl = childMax
            end
        end
    end
    return maxLvl
end

local function IsCombatLocked()
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
end

local function RoleShortLabel(roleId)
    if roleId == "TANK" then return L["Tank"] end
    if roleId == "HEALER" then return L["Healer"] end
    if roleId == "DPS" then return L["DPS"] end
    return L["Any"]
end

local function GetNativeLfgSubFrames()
    return {
        _G.LFGListingFrame,
        _G.LFGBrowseFrame,
        _G.LFGWhoListFrame,
    }
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

local function UpdateSideTabBadge(tab, count)
    if not tab then return end
    local showBadges = not (ns.db and ns.db.settings and ns.db.settings.addonMsgTabBadges == false)
    local n = tonumber(count) or 0
    if not showBadges or n <= 0 then
        if tab.scUnreadBadge then
            tab.scUnreadBadge:Hide()
        end
        return
    end
    if not tab.scUnreadBadge then
        local b = CreateFrame("Frame", nil, tab, "BackdropTemplate")
        b:SetSize(18, 15)
        b:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -2, 3)
        b:SetFrameLevel((tab:GetFrameLevel() or 60) + 4)
        b:EnableMouse(false)
        if b.SetBackdrop then
            b:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            b:SetBackdropColor(0.86, 0.16, 0.22, 1.0)
            b:SetBackdropBorderColor(0.08, 0.10, 0.14, 1.0)
        end
        local txt = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        txt:SetPoint("CENTER", 0, 0)
        txt:SetTextColor(1, 1, 1)
        b.text = txt
        tab.scUnreadBadge = b
    end
    local lbl = n > 99 and "99+" or tostring(n)
    tab.scUnreadBadge.text:SetText(lbl)
    local bw = (n > 99 and 26) or (n > 9 and 22) or 18
    tab.scUnreadBadge:SetSize(bw, 15)
    tab.scUnreadBadge:SetFrameLevel((tab:GetFrameLevel() or 60) + 4)
    tab.scUnreadBadge:Show()
end

local function UpdateSideTabVisual(tab, isSelected)
    if not tab then return end
    if tab.selectedTex then
        tab.selectedTex:SetShown(isSelected == true)
    end
    if tab._useCommonSideTab and tab.bgTex then
        if isSelected and HasAtlas("common-sidetab-selected") then
            tab.bgTex:SetAtlas("common-sidetab-selected", true)
        elseif HasAtlas("common-sidetab") then
            tab.bgTex:SetAtlas("common-sidetab", true)
        end
    end
    if tab.SetChecked then
        pcall(tab.SetChecked, tab, isSelected == true)
    end
end

local function CreateRightSideTab(parent, name, lastNative, tooltipTitle, tooltipDesc, onClickFn)
    if not parent then return nil end

    local tab = CreateFrame("CheckButton", name, parent)
    local w, h = 55, 60
    if lastNative and lastNative.GetSize then
        local tw, th = lastNative:GetSize()
        if tw and tw > 0 and th and th > 0 then
            w, h = tw, th
        end
    end
    tab:SetSize(w, h)
    local lastLvl = (lastNative and lastNative.GetFrameLevel and lastNative:GetFrameLevel()) or 20
    tab:SetFrameLevel(math.max(60, lastLvl + 2))

    local useCommon = (w >= 44) and HasAtlas("common-sidetab")
    tab._useCommonSideTab = useCommon

    if useCommon then
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAtlas("common-sidetab", true)
        bg:SetPoint("CENTER")
        tab.bgTex = bg

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

    tab:SetScript("OnClick", onClickFn)
    tab:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tooltipTitle, 0.35, 0.72, 1.0)
        if tooltipDesc and tooltipDesc ~= "" then
            GameTooltip:AddLine(tooltipDesc, 0.85, 0.88, 0.92, true)
        end
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return tab
end

local function DiscoverRightSideTabs(parentFrame, excludeTab, namedKeys)
    local found = {}
    if not parentFrame then return found end

    if namedKeys then
        local pRight = parentFrame.GetRight and parentFrame:GetRight()
        for _, key in ipairs(namedKeys) do
            local tab = parentFrame[key]
            if tab and tab ~= excludeTab and tab.IsShown and tab:IsShown() then
                local tLeft = tab.GetLeft and tab:GetLeft()
                local tW = (tab.GetWidth and tab:GetWidth()) or 0
                if not pRight or (tLeft and tLeft >= (pRight - 14) and tW <= 80) then
                    found[#found + 1] = tab
                end
            end
        end
        if #found > 0 then
            table.sort(found, function(a, b)
                return ((a.GetTop and a:GetTop()) or 0) > ((b.GetTop and b:GetTop()) or 0)
            end)
            return found
        end
    end

    if parentFrame.socialTabPool and parentFrame.socialTabPool.EnumerateActive then
        for tab in parentFrame.socialTabPool:EnumerateActive() do
            if tab and tab ~= excludeTab and tab.IsShown and tab:IsShown() then
                found[#found + 1] = tab
            end
        end
        if #found > 0 then
            table.sort(found, function(a, b)
                return ((a.GetTop and a:GetTop()) or 0) > ((b.GetTop and b:GetTop()) or 0)
            end)
            return found
        end
    end

    if parentFrame.ModeTabs and parentFrame.ModeTabs.Tabs then
        for _, tab in ipairs(parentFrame.ModeTabs.Tabs) do
            if tab and tab ~= excludeTab and tab.IsShown and tab:IsShown() then
                found[#found + 1] = tab
            end
        end
        if #found > 0 then
            table.sort(found, function(a, b)
                return ((a.GetTop and a:GetTop()) or 0) > ((b.GetTop and b:GetTop()) or 0)
            end)
            return found
        end
    end

    local pRight = parentFrame.GetRight and parentFrame:GetRight()
    if parentFrame.GetChildren then
        for _, child in ipairs({ parentFrame:GetChildren() }) do
            if child ~= excludeTab and child ~= LFGFrameTab.subPanel and child.IsShown and child:IsShown() then
                local w = (child.GetWidth and child:GetWidth()) or 0
                local cLeft = child.GetLeft and child:GetLeft()
                local looksLikeTab = (child.Icon or child.NormalTexture or (pRight and cLeft and cLeft >= (pRight - 14) and w >= 24 and w <= 72))
                if looksLikeTab and (child.HasScript and (child:HasScript("OnClick") or child:HasScript("OnMouseUp"))) then
                    found[#found + 1] = child
                end
            end
        end
        table.sort(found, function(a, b)
            return ((a.GetTop and a:GetTop()) or 0) > ((b.GetTop and b:GetTop()) or 0)
        end)
    end
    return found
end

local function MeasureTabGap(nativeTabs, fallbackGap)
    if #nativeTabs >= 2 then
        local b1 = nativeTabs[1].GetBottom and nativeTabs[1]:GetBottom()
        local t2 = nativeTabs[2].GetTop and nativeTabs[2]:GetTop()
        if b1 and t2 then
            local measured = t2 - b1
            if measured <= 0 and measured >= -36 then
                return measured
            end
        end
    end
    return fallbackGap or -2
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

local function SetNativeTabsCheckedFalse()
    local parentFrame = _G.LFGParentFrame
    if not parentFrame then return end
    for _, tab in ipairs(DiscoverNativeSideTabs(parentFrame)) do
        if tab.SetChecked then
            pcall(tab.SetChecked, tab, false)
        end
    end
end

local function ElevateTree(root, targetLevel, depth)
    if not root or (depth or 0) <= 0 then return end
    if root.SetFrameLevel and root.GetFrameLevel then
        local cur = root:GetFrameLevel() or 1
        if cur < targetLevel then
            pcall(root.SetFrameLevel, root, targetLevel)
        end
    end
    if root.GetChildren then
        local children = { root:GetChildren() }
        for i = 1, #children do
            ElevateTree(children[i], targetLevel + 1, (depth or 1) - 1)
        end
    end
end

local function ElevateLfgParentControls()
    local parent = _G.LFGParentFrame
    local panel = LFGFrameTab.subPanel
    if not parent or not panel then return end
    local minControlLevel = math.max(
        MaxHierarchyLevel(panel, 4) + 25,
        (panel:GetFrameLevel() or 10) + 40,
        560
    )
    if panel.PortraitContainer and panel.PortraitContainer.Hide then
        panel.PortraitContainer:Hide()
    end
    local chromeFrames = {
        parent.PortraitContainer,
        parent.PortraitOverlay,
        _G.LFGParentFramePortraitFrame,
    }
    for _, f in ipairs(chromeFrames) do
        if f then
            ElevateTree(f, minControlLevel, 3)
        end
    end
    local closeBtn = parent.CloseButton or _G.LFGParentFrameCloseButton
    if closeBtn then
        ElevateTree(closeBtn, minControlLevel + 14, 2)
    end
    for _, tab in ipairs(DiscoverNativeSideTabs(parent)) do
        ElevateTree(tab, minControlLevel + 6, 2)
    end
    if LFGFrameTab.sideTab then
        ElevateTree(LFGFrameTab.sideTab, minControlLevel + 6, 2)
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

local function HarvestLfgListingArt(forceRefresh)
    if lfgArtCache and next(lfgArtCache.banners) ~= nil then
        if not forceRefresh or next(lfgArtCache.roles) ~= nil then
            return lfgArtCache
        end
    end
    local cache = lfgArtCache or { roles = {}, banners = {} }
    if forceRefresh then
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
                    for _, iconField in ipairs({ child.Icon, child.RoleIcon, child.Texture }) do
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
                for _, labelField in ipairs({ child.Label, child.Name, child.Text, child.Title }) do
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
                    for _, texField in ipairs({ frm.Background, frm.Cover, frm.Icon, frm.Texture, frm.Art, frm.Image, frm.Bg }) do
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

function LFGFrameTab:InitDefaultRoles()
    if self.rolesInitialized then return end
    self.rolesInitialized = true
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
    self.roles.GUIDE = false
    self.composerRole = roleId
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

function LFGFrameTab:GetFilteredCategoryActivities(catId, showAll)
    local source = CURATED_ACTIVITIES[catId or self.activeCategory or "DUNGEONS"] or CURATED_ACTIVITIES.DUNGEONS
    local out = {}
    if showAll then
        for i = 1, #source do
            out[#out + 1] = source[i]
        end
        return out
    end
    local lvl = ns.Safe and ns.Safe.Number(UnitLevel and UnitLevel("player")) or 60
    if lvl <= 0 then lvl = 60 end
    for i = 1, #source do
        local act = source[i]
        if lvl >= (act.minLvl or 1) and lvl <= (act.maxLvl or 60) then
            out[#out + 1] = act
        end
    end
    if #out == 0 then
        for i = 1, #source do
            out[#out + 1] = source[i]
        end
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

function LFGFrameTab:GetSelectedActivitiesSummary()
    local names = {}
    local activeItems = CURATED_ACTIVITIES[self.activeCategory or "DUNGEONS"] or {}
    for i = 1, #activeItems do
        local act = activeItems[i]
        if self.selectedActivities[act.id] then
            names[#names + 1] = L[act.labelKey]
        end
    end
    if #names == 0 then
        for _, cat in ipairs(LISTING_CATEGORIES) do
            local list = CURATED_ACTIVITIES[cat.id] or {}
            for i = 1, #list do
                if self.selectedActivities[list[i].id] then
                    names[#names + 1] = L[list[i].labelKey]
                end
            end
        end
    end
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

function LFGFrameTab:HasSelfActiveListing()
    if not (ns.Clan and ns.Clan.GetClanLFGList) then
        return false
    end
    local ok, items = pcall(ns.Clan.GetClanLFGList, ns.Clan, nil, false, "ALL")
    if ok and type(items) == "table" then
        for i = 1, #items do
            if items[i] and items[i].isSelf then
                return true
            end
        end
    end
    return false
end

function LFGFrameTab:UpdateRoleControls()
    local c = self.controls
    if not (c and c.roleButtons) then return end
    for _, rb in ipairs(c.roleButtons) do
        local active = self.roles[rb.roleId] == true
        if rb.check then
            rb.check:SetChecked(active)
        end
        if rb.swirl then
            rb.swirl:SetAlpha(active and 1.0 or 0.25)
        end
        if rb.ringGlow then
            rb.ringGlow:SetShown(active)
        end
        if rb.icon then
            local tc = rb.iconTint
            if tc then
                rb.icon:SetVertexColor(tc[1], tc[2], tc[3], active and 1.0 or 0.90)
            else
                rb.icon:SetVertexColor(1.0, 1.0, 1.0, active and 1.0 or 0.90)
            end
        end
    end
end

function LFGFrameTab:UpdateViewLayout()
    local c = self.controls
    if not c then return end
    local mode = self.viewMode or "categories"
    local isBrowse = (mode == "browse")
    local isCats = (mode == "categories")
    local isActs = (mode == "activities")

    if c.headerBg then
        c.headerBg:SetHeight(isBrowse and 57 or 75)
    end
    local topOffset = isBrowse and -78 or -96
    if c.headerSep then
        c.headerSep:ClearAllPoints()
        c.headerSep:SetPoint("TOPLEFT", c.artFrame, "TOPLEFT", 3, topOffset)
        c.headerSep:SetPoint("TOPRIGHT", c.artFrame, "TOPRIGHT", -4, topOffset)
    end
    if c.bgArt then
        c.bgArt:ClearAllPoints()
        c.bgArt:SetPoint("TOPLEFT", c.artFrame, "TOPLEFT", 3, topOffset)
        c.bgArt:SetPoint("BOTTOMRIGHT", c.artFrame, "BOTTOMRIGHT", -4, 3)
    end
    if c.insideFrame then
        c.insideFrame:ClearAllPoints()
        c.insideFrame:SetPoint("TOPLEFT", c.artFrame, "TOPLEFT", 3, topOffset)
        c.insideFrame:SetPoint("BOTTOMRIGHT", c.artFrame, "BOTTOMRIGHT", -4, 3)
    end

    if c.browseHeader then c.browseHeader:SetShown(isBrowse) end
    if c.roleHeader then c.roleHeader:SetShown(not isBrowse) end
    if c.categoryView then c.categoryView:SetShown(isCats) end
    if c.activityView then c.activityView:SetShown(isActs) end
    if self.list and self.list.container then
        self.list.container:SetShown(isBrowse)
    end
    if c.composerBar then
        c.composerBar:SetShown(false)
    end

    if isBrowse and self.list and self.list.container and c.body then
        self.list.container:ClearAllPoints()
        self.list.container:SetPoint("TOPLEFT", c.body, "TOPLEFT", 12, -84)
        self.list.container:SetPoint("BOTTOMRIGHT", c.body, "BOTTOMRIGHT", -12, 42)
    end

    if c.sendMsgBtn then c.sendMsgBtn:SetShown(isBrowse) end
    if c.inviteBtn then c.inviteBtn:SetShown(isBrowse) end
    if c.listGroupBtn then c.listGroupBtn:SetShown(isBrowse) end
    if c.browseGroupsBtn then c.browseGroupsBtn:SetShown(isCats) end
    if c.backBtn then c.backBtn:SetShown(isActs) end
    if c.listSelfBtn then c.listSelfBtn:SetShown(not isBrowse) end

    local hasListing = self:HasSelfActiveListing()
    if c.unlistBtn then
        c.unlistBtn:SetShown((not isBrowse) and hasListing)
    end

    if c.listHelpBtn and c.body then
        c.listHelpBtn:ClearAllPoints()
        if isBrowse and c.listGroupBtn then
            c.listHelpBtn:SetPoint("LEFT", c.listGroupBtn, "RIGHT", 4, 0)
        elseif c.listSelfBtn then
            c.listHelpBtn:SetPoint("RIGHT", c.listSelfBtn, "LEFT", -6, 0)
        end
    end

    self:UpdateRoleControls()
    self:UpdateBottomButtons(hasListing)
end

function LFGFrameTab:UpdateComposerLayout()
    self:UpdateViewLayout()
end

local function ResolveLfgInviteTarget(item)
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
    local sel = self.selectedItem
    local canAct = (sel ~= nil) and (sel.isSelf ~= true) and not combat
    if c.sendMsgBtn and c.sendMsgBtn.SetEnabled then
        c.sendMsgBtn:SetEnabled(canAct)
    end
    local canInviteSel = canAct and ResolveLfgInviteTarget(sel)
    if c.inviteBtn and c.inviteBtn.SetEnabled then
        c.inviteBtn:SetEnabled(canInviteSel)
    end

    local hasRole = self:HasAnySelectedRole()
    local hasAct = self:HasAnySelectedActivity()
    local canList = (self.viewMode == "activities") and hasRole and hasAct and not combat
    if c.listSelfBtn and c.listSelfBtn.SetEnabled then
        c.listSelfBtn:SetEnabled(canList)
    end
    local hasListing = (hasSelfListingOverride ~= nil) and hasSelfListingOverride or self:HasSelfActiveListing()
    if c.unlistBtn and c.unlistBtn.SetEnabled then
        c.unlistBtn:SetEnabled(hasListing and not combat)
    end
end

function LFGFrameTab:ShowSubPanel()
    if ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled("I") then
        return
    end
    if IsCombatLocked() then
        ns:Print(L["Target Radar"] .. ": " .. L["Unavailable during combat."])
        return
    end
    if not _G.LFGParentFrame then return end
    if ns.UI and ns.UI.CloseEmbeddedIfHost then
        ns.UI:CloseEmbeddedIfHost(_G.LFGParentFrame)
    end
    self:InitDefaultRoles()
    if not self.subPanel then
        self:BuildSubPanel()
    end
    if not self.subPanel then return end

    local refreshedArt = HarvestLfgListingArt(true)

    for _, sub in ipairs(GetNativeLfgSubFrames()) do
        if sub and sub.Hide then
            sub:Hide()
        end
    end
    SetNativeTabsCheckedFalse()

    if self.controls and self.controls.categoryButtons then
        for _, catBtn in ipairs(self.controls.categoryButtons) do
            if catBtn and catBtn.ApplyBannerArt then
                catBtn:ApplyBannerArt(refreshedArt)
            end
        end
    end

    if self.subPanel.SetTitle then
        pcall(self.subPanel.SetTitle, self.subPanel, (_G.LOOKING_FOR_GROUP or L["Looking for Group"]))
    elseif self.subPanel.TitleContainer and self.subPanel.TitleContainer.TitleText then
        pcall(self.subPanel.TitleContainer.TitleText.SetText, self.subPanel.TitleContainer.TitleText, (_G.LOOKING_FOR_GROUP or L["Looking for Group"]))
    end
    if self.subPanel.PortraitContainer and self.subPanel.PortraitContainer.Hide then
        self.subPanel.PortraitContainer:Hide()
    end

    if _G.LFGParentFrame.SetTitle then
        pcall(_G.LFGParentFrame.SetTitle, _G.LFGParentFrame, (_G.LOOKING_FOR_GROUP or L["Looking for Group"]))
    elseif _G.LFGParentFrameTitleText then
        pcall(_G.LFGParentFrameTitleText.SetText, _G.LFGParentFrameTitleText, (_G.LOOKING_FOR_GROUP or L["Looking for Group"]))
    end

    self.active = true
    self.subPanel:Show()
    ElevateLfgParentControls()
    self:UpdateTabSelectionVisual()
    self:UpdateViewLayout()
    self:RefreshData()
end

function LFGFrameTab:HideSubPanel(restoreNative)
    self.active = false
    if self.subPanel then
        self.subPanel:Hide()
    end
    self:UpdateTabSelectionVisual()

    if restoreNative and _G.LFGParentFrame then
        local selectedTab = _G.LFGParentFrame.selectedTab or 1
        local subs = GetNativeLfgSubFrames()
        for i, sub in ipairs(subs) do
            if sub and sub.SetShown then
                sub:SetShown(i == selectedTab)
            end
        end
        if _G.LFGParentFrame.UpdateTabs then
            pcall(_G.LFGParentFrame.UpdateTabs, _G.LFGParentFrame)
        end
    end
end

function LFGFrameTab:ToggleSubPanel()
    if self.active and self.subPanel and self.subPanel:IsShown() then
        self:HideSubPanel(true)
    else
        self:ShowSubPanel()
    end
end

function LFGFrameTab:RefreshTheme()
    local panel = self.subPanel
    if not panel then return end
    local p = Theme:GetPalette()

    if panel._solidOpaqueBg then
        local wBg = p.windowBg or { 0.08, 0.075, 0.07, 1.0 }
        panel._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
        panel._solidOpaqueBg:Show()
    end
    if panel._useBackdropFallback then
        Theme:ApplyBackdrop(panel, "window", p)
    end

    local c = self.controls
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
    self:UpdateViewLayout()
end

local function BuildLfgApplyDraft(item)
    if ns.db and ns.db.settings and ns.db.settings.lfgAutoApplyDraft == false then
        return nil
    end
    local roleId = (LFGFrameTab.GetPrimaryListingRole and LFGFrameTab:GetPrimaryListingRole()) or "DPS"
    local roleName = (roleId == "TANK" and L["Tank"]) or (roleId == "HEALER" and L["Healer"]) or L["DPS"]
    local lvl = (UnitLevel and ns.Safe and ns.Safe.Number(ns.Safe.Call(UnitLevel, "player"))) or 0
    local classLoc = UnitClass and ns.Safe and ns.Safe.String(ns.Safe.Call(UnitClass, "player")) or ""
    local act = item and item.activity and item.activity ~= "" and item.activity or nil
    if lvl > 0 and classLoc ~= "" then
        if act then
            return string.format(L["Hi! Lv %d %s (%s) available for %s"], lvl, classLoc, roleName, act)
        end
        return string.format(L["Hi! Lv %d %s (%s) available!"], lvl, classLoc, roleName)
    end
    return act and string.format(L["Hi! Available (%s) for %s"], roleName, act) or nil
end

local function OpenPlayerWhisper(item)
    if not item or item.isSelf then return end
    local targetName = item.displayName or item.lookupKey
    if not targetName or targetName == "" then return end
    local draft = BuildLfgApplyDraft(item)
    local rKey = item.lookupKey or targetName
    local bInfo = ns.Social and ns.Social.GetBNetLinkInfo and ns.Social:GetBNetLinkInfo(rKey)
    local isCrossFac = (item.sameFaction == false) or (bInfo and bInfo.sameFaction == false)
    local bnetName = item.bnetName or (bInfo and bInfo.bnetName)
    local scConfirmed = ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(rKey, item.bnetAccountID or (bInfo and bInfo.bnetAccountID))
    if scConfirmed and ns.Chat and ns.Chat.OpenDirectConversation then
        ns.Chat:OpenDirectConversation({
            targetName = targetName,
            classFile = item.classFile,
            autoProbe = true,
            openUI = true,
            draftText = draft,
        })
        LFGFrameTab:OpenOfficialModule("chat")
    elseif isCrossFac and bnetName and Compat.BNetWhisper then
        Compat.BNetWhisper(bnetName, targetName, draft)
    elseif Compat.Whisper then
        Compat.Whisper(targetName, draft)
    end
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
        if dd.SetDefaultText then
            pcall(dd.SetDefaultText, dd, getTextFn())
        end
        if dd.SetSelectionText then
            pcall(dd.SetSelectionText, dd, function()
                return getTextFn()
            end)
        end
        pcall(dd.SetupMenu, dd, function(_, root)
            buildMenuFn(root)
        end)
        function dd:RefreshDropdownLabel()
            local txt = getTextFn()
            if self.SetDefaultText then
                pcall(self.SetDefaultText, self, txt)
            end
            if not (self.IsMenuOpen and self:IsMenuOpen()) and self.GenerateMenu then
                pcall(self.GenerateMenu, self)
            elseif self.OverrideText then
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
        self._label:SetText(getTextFn())
    end
    btn:RefreshDropdownLabel()
    return btn
end

local function OpenLfgRowContextMenu(anchor, item)
    if not (MenuUtil and MenuUtil.CreateContextMenu and item) then return end
    local targetName = item.displayName or item.lookupKey
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle(targetName or L["Clan & Allied LFG"])
        if item.isSelf then
            root:CreateButton(L["Unlist"], function()
                if ns.Clan and ns.Clan.ClearMyLFG then
                    ns.Clan:ClearMyLFG()
                end
                LFGFrameTab:RefreshData()
            end)
        end
        if targetName and not item.isSelf then
            local canInviteLfg, invTarget, invBnetId, isCrossFac, bnetName = ResolveLfgInviteTarget(item)
            root:CreateButton(L["Whisper"], function()
                OpenPlayerWhisper(item)
            end)
            root:CreateButton(L["Quick Apply (/w)"], function()
                local draft = BuildLfgApplyDraft(item)
                if isCrossFac and bnetName and Compat.BNetWhisper then
                    Compat.BNetWhisper(bnetName, targetName, draft)
                elseif Compat.Whisper then
                    Compat.Whisper(targetName, draft)
                end
            end)
            if canInviteLfg then
                root:CreateButton(L["Invite to Group"], function()
                    if Compat.Invite then Compat.Invite(invTarget, invBnetId) end
                end)
            end
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
        end
    end)
end

local function SyncRowSelectionVisuals()
    local list = LFGFrameTab.list
    if not (list and list.rows) then return end
    local selKey = LFGFrameTab.selectedKey
    for _, row in ipairs(list.rows) do
        if row and row.SelectedTex and row:IsShown() then
            local rowKey = GetItemIdentityKey(row._item)
            row.SelectedTex:SetShown(selKey ~= nil and rowKey == selKey)
        end
    end
    LFGFrameTab:UpdateBottomButtons()
end

local ROLE_ATLAS_CANDIDATES = {
    TANK = { "groupfinder-icon-role-large-tank", "groupfinder-icon-role-styled-tank" },
    HEALER = { "groupfinder-icon-role-large-healer", "groupfinder-icon-role-styled-healer" },
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
    row:SetHeight(52)
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
    row.partyIcon:SetSize(16, 16)
    row.partyIcon:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -10)
    if HasAtlas("groupfinder-icon-leader") then
        row.partyIcon:SetAtlas("groupfinder-icon-leader", false)
    else
        row.partyIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    end

    row.nameFs = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.nameFs:SetPoint("TOPLEFT", row, "TOPLEFT", 28, -9)
    row.nameFs:SetJustifyH("LEFT")
    row.nameFs:SetWordWrap(false)

    row.levelFs = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.levelFs:SetPoint("BOTTOMLEFT", row.nameFs, "BOTTOMRIGHT", 5, 0)
    row.levelFs:SetJustifyH("LEFT")
    row.levelFs:SetWordWrap(false)

    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetSize(18, 18)
    row.classIcon:SetPoint("LEFT", row.levelFs, "RIGHT", 4, 0)
    row.classIcon:Hide()

    row.badgeFs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.badgeFs:SetPoint("LEFT", row.classIcon, "RIGHT", 4, 0)
    row.badgeFs:SetPoint("RIGHT", row, "RIGHT", -84, 0)
    row.badgeFs:SetJustifyH("LEFT")
    row.badgeFs:SetWordWrap(false)

    -- Right-aligned native DataDisplay 3-Role cluster
    row.dpsIcon = row:CreateTexture(nil, "ARTWORK")
    row.dpsIcon:SetSize(22, 22)
    row.dpsIcon:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    SetRoleSlotTexture(row.dpsIcon, "DPS")

    row.healerIcon = row:CreateTexture(nil, "ARTWORK")
    row.healerIcon:SetSize(22, 22)
    row.healerIcon:SetPoint("RIGHT", row.dpsIcon, "LEFT", -2, 0)
    SetRoleSlotTexture(row.healerIcon, "HEALER")

    row.tankIcon = row:CreateTexture(nil, "ARTWORK")
    row.tankIcon:SetSize(22, 22)
    row.tankIcon:SetPoint("RIGHT", row.healerIcon, "LEFT", -2, 0)
    SetRoleSlotTexture(row.tankIcon, "TANK")

    row.activityFs = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.activityFs:SetPoint("TOPLEFT", row.nameFs, "BOTTOMLEFT", 0, -4)
    row.activityFs:SetPoint("RIGHT", row.tankIcon, "LEFT", -8, 0)
    row.activityFs:SetJustifyH("LEFT")
    row.activityFs:SetWordWrap(false)

    row._scSep = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row._scSep:SetHeight(1)
    row._scSep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 0)
    row._scSep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 0)
    row._scSep:SetColorTexture(0.68, 0.56, 0.28, 0.16)

    row:SetScript("OnClick", function(selfRow, btn)
        local it = selfRow._item
        if not it then return end
        LFGFrameTab.selectedKey = GetItemIdentityKey(it)
        LFGFrameTab.selectedItem = it
        SyncRowSelectionVisuals()
        LFGFrameTab:UpdateBottomButtons()
        if btn == "RightButton" then
            OpenLfgRowContextMenu(selfRow, it)
        end
    end)

    row:SetScript("OnDoubleClick", function(selfRow, btn)
        if btn ~= "LeftButton" then return end
        local it = selfRow._item
        if not it or it.isSelf then return end
        OpenPlayerWhisper(it)
    end)

    row:SetScript("OnEnter", function(selfRow)
        local it = selfRow._item
        if not it then return end
        GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
        GameTooltip:AddLine(it.displayName or "?", 1, 1, 1)
        if it.guild and it.guild ~= "" then
            GameTooltip:AddLine("<" .. it.guild .. ">", 0.55, 0.85, 1.0)
        end
        if it.activity and it.activity ~= "" then
            GameTooltip:AddLine(it.activity, 0.35, 0.90, 0.55, true)
        end
        if it.note and it.note ~= "" then
            GameTooltip:AddLine(it.note, 0.85, 0.85, 0.85, true)
        end
        if it.hasFriendOrWatchlistSignup and it.friendOrWatchlistNames and it.friendOrWatchlistNames ~= "" then
            GameTooltip:AddLine(L["In group"] .. ": " .. it.friendOrWatchlistNames, 1.0, 0.72, 0.30, true)
        end
        if it._lockoutInfo then
            local lk = it._lockoutInfo
            local prog = (lk.numEncounters and lk.numEncounters > 0) and string.format("%d/%d", lk.encounterProgress or 0, lk.numEncounters) or L["Saved"]
            local resetStr = (Compat.FormatDurationShort and Compat.FormatDurationShort(lk.reset or 0)) or ""
            GameTooltip:AddLine(string.format(L["Saved Lockout: %s (%s · %s)"], lk.name or "?", prog, resetStr), 1.0, 0.62, 0.24, true)
        end
        GameTooltip:AddLine(L["Double-click: Whisper  |  Right-click: More actions"], 0.60, 0.66, 0.74)
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

local function UpdateLfgRow(row, item, _, palette)
    row._item = item
    if row.nativeBgTex then
        Theme:ApplyBackdrop(row, "none", palette)
    else
        Theme:ApplyBackdrop(row, "row", palette)
    end

    local isLeaderOrGroup = (item.mode == "LFM" or item.sourceType == "EVENT")
    if row._lastLeaderMode ~= isLeaderOrGroup then
        row._lastLeaderMode = isLeaderOrGroup
        row.partyIcon:SetShown(isLeaderOrGroup)
        row.nameFs:ClearAllPoints()
        if isLeaderOrGroup then
            row.nameFs:SetPoint("TOPLEFT", row, "TOPLEFT", 28, -9)
        else
            row.nameFs:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -9)
        end
    end

    local sMeta = Store and (Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(item.lookupKey or item.displayName) or Store:GetSocialMeta(item.lookupKey or item.displayName))
    local flagPrefix = ""
    if sMeta and sMeta.flag == "AVOID" then
        flagPrefix = "|cffff4d4d[!]|r "
    elseif sMeta and sMeta.flag == "GOOD" then
        flagPrefix = "|cff3fb950[+]|r "
    end

    local classHex = Compat.ClassHex and Compat.ClassHex(item.classFile) or "|cffffd200"
    local keyTag = (item.keyLvl and item.keyLvl > 0) and (" |cffd2a8ff+" .. item.keyLvl .. "|r") or ""
    row.nameFs:SetText(string.format("%s%s%s|r%s", flagPrefix, classHex, item.displayName or "?", keyTag))
    row.nameFs:SetWidth(math.min(152, math.max(46, row.nameFs:GetStringWidth() or 110)))

    local lvlPart = (item.level and item.level > 0) and ("Nv " .. item.level) or item.mode
    row.levelFs:SetText(lvlPart or "")

    local classSlug = type(item.classFile) == "string" and item.classFile:lower() or nil
    local classAtlas = classSlug and ("groupfinder-icon-class-" .. classSlug) or nil
    row.classIcon:ClearAllPoints()
    row.badgeFs:ClearAllPoints()
    if classAtlas and HasAtlas(classAtlas) then
        row.classIcon:SetAtlas(classAtlas, false)
        row.classIcon:SetPoint("LEFT", row.levelFs, "RIGHT", 4, 0)
        row.classIcon:Show()
        row.badgeFs:SetPoint("LEFT", row.classIcon, "RIGHT", 4, 0)
    else
        row.classIcon:Hide()
        row.badgeFs:SetPoint("LEFT", row.levelFs, "RIGHT", 4, 0)
    end
    row.badgeFs:SetPoint("RIGHT", row.tankIcon, "LEFT", -6, 0)

    local badges = ""
    if sMeta and sMeta.flag == "AVOID" then
        badges = badges .. "|cffff4d4d[" .. L["AVOID"] .. "]|r "
    end
    if item._lockoutInfo then
        local lk = item._lockoutInfo
        local lockProg = (lk.numEncounters and lk.numEncounters > 0)
            and string.format("%s %d/%d", L["LOCKED"], lk.encounterProgress or 0, lk.numEncounters)
            or L["LOCKED"]
        badges = badges .. "|cffff9b3d[" .. lockProg .. "]|r "
    end
    if item.sourceType == "PUBLIC_CHAT" then
        badges = badges .. "|cffb48eff[" .. L["Global Chat"] .. "]|r "
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
    if item.isOfficial then
        badges = badges .. "|cff58a6ff[" .. L["Official LFG"] .. "]|r "
    end
    if item.isAllied then
        local gShort = (item.guild and item.guild ~= "") and (" " .. item.guild) or ""
        badges = badges .. "|cff40d973[" .. L["ALLY"] .. gShort .. "]|r "
    elseif item.isClan then
        badges = badges .. "|cfffacc3d[" .. L["CLAN"] .. "]|r "
    end
    if item.isWatchlist or item.hasFriendOrWatchlistSignup then
        badges = badges .. "|cffffa633[" .. L["WATCHLIST"] .. "]|r"
    elseif item.isFriend then
        badges = badges .. "|cff59c7ff[" .. L["FRIEND"] .. "]|r"
    end
    row.badgeFs:SetText(badges)

    local actTxt = item.activity or L["Dungeon"]
    local modeTag = (item.mode == "LFM") and "|cff3fb950[LFM]|r " or "|cff58a6ff[LFG]|r "
    local notePart = (item.note and item.note ~= "") and (" — " .. item.note) or ""
    local friendNote = (item.hasFriendOrWatchlistSignup and item.friendOrWatchlistNames and item.friendOrWatchlistNames ~= "")
        and (" |cffffa633(" .. L["In group"] .. ": " .. item.friendOrWatchlistNames .. ")|r") or ""
    row.activityFs:SetText(modeTag .. "|cffe0d4b0" .. actTxt .. "|r|cffb8c0cc" .. notePart .. "|r" .. friendNote)

    local role = item.role or "ANY"
    local showAll = (role == "ANY" or role == "" or item.sourceType == "EVENT")
    row.tankIcon:SetAlpha((showAll or role == "TANK") and 1.0 or 0.25)
    row.healerIcon:SetAlpha((showAll or role == "HEALER") and 1.0 or 0.25)
    row.dpsIcon:SetAlpha((showAll or role == "DPS") and 1.0 or 0.25)

    local selKey = LFGFrameTab.selectedKey
    local isSel = (selKey ~= nil) and (GetItemIdentityKey(item) == selKey)
    row.SelectedTex:SetShown(isSel)
end

local ROLE_CIRCLE_DEFS = {
    { id = "TANK",   labelKey = "Tank",          x = 44,  glass = { 0.08, 0.24, 0.50 }, glow = { 0.16, 0.48, 0.98 }, badge = false },
    { id = "HEALER", labelKey = "Healer",        x = 106, glass = { 0.07, 0.34, 0.26 }, glow = { 0.18, 0.88, 0.42 }, badge = false },
    { id = "DPS",    labelKey = "DPS",           x = 168, glass = { 0.42, 0.10, 0.10 }, glow = { 0.92, 0.22, 0.18 }, badge = false },
    { id = "GUIDE",  labelKey = "Dungeon Guide", x = 246, glass = { 0.09, 0.22, 0.18 }, glow = { 0.20, 0.82, 0.46 }, badge = true  },
}

local function CreateRoleCircleButton(parent, def, artInfo)
    local roleArt = artInfo and artInfo.roles and artInfo.roles[def.id]
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(52, 52)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", def.x, -27)

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

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("LEFT", btn, "LEFT", 16, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", -16, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(L[catDef.labelKey])
    label:SetTextColor(1.0, 0.82, 0.0)
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 0.95)
    btn.label = label

    btn:SetScript("OnClick", function()
        LFGFrameTab.activeCategory = catDef.id
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
    row.nameLabel:SetText(L[act.labelKey])
    row.lvlLabel:SetText("(" .. tostring(act.minLvl or 1) .. " - " .. tostring(act.maxLvl or 60) .. ")")
end

function LFGFrameTab:SubmitListing()
    if IsCombatLocked() then
        ns:Print(L["Target Radar"] .. ": " .. L["Unavailable during combat."])
        return
    end
    if not (self:HasAnySelectedRole() and self:HasAnySelectedActivity()) then
        return
    end

    local mode = (self.listingMode == "LFM") and "LFM" or "LFG"
    local role = self:GetPrimaryListingRole()
    local activity = self:GetSelectedActivitiesSummary()
    local noteParts = {}

    if self.playstyle == "NORMAL" or self.playstyle == "FAST" or self.playstyle == "FULL" then
        noteParts[#noteParts + 1] = GetPlaystyleLabel(self.playstyle)
    end
    local roleTag = self:GetSelectedRolesNoteTag()
    if roleTag ~= "" then
        noteParts[#noteParts + 1] = roleTag
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

    if ns.Clan and ns.Clan.PostLFG then
        ns.Clan:PostLFG(mode, role, activity, 0, note, self.broadcastMode == "CLAN")
    end
    if self.broadcastMode == "GCHAT" and ns.Clan and ns.Clan.OpenGuildChatLFG then
        ns.Clan:OpenGuildChatLFG(mode, role, activity, 0, note)
    elseif self.broadcastMode == "OFFICIAL" and ns.Clan and ns.Clan.OpenOfficialLfgForGuild then
        self.categoryFilter = "ALL"
        self.viewMode = "browse"
        self:RefreshData()
        ns.Clan:OpenOfficialLfgForGuild(activity, note, mode)
        return
    end

    self.categoryFilter = "ALL"
    self.viewMode = "browse"
    self:RefreshData()
end

function LFGFrameTab:RefreshData()
    if not (self.active and self.subPanel and self.subPanel:IsShown()) then
        return
    end
    local c = self.controls
    local mode = self.viewMode or "categories"

    if mode == "categories" then
        self:UpdateViewLayout()
        return
    elseif mode == "activities" then
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
            c.masterCatLabel:SetText(GetCategoryLabel(self.activeCategory))
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
        return
    end

    self.dungeonsOnly = (self.categoryFilter == "DUNGEONS")
    if c.catDropdown and c.catDropdown.RefreshDropdownLabel then
        c.catDropdown:RefreshDropdownLabel()
    end
    if c.filterDropdown and c.filterDropdown.RefreshDropdownLabel then
        c.filterDropdown:RefreshDropdownLabel()
    end

    if not (self.list and self.list.SetData) then return end
    local rawRows = (ns.Clan and ns.Clan.GetClanLFGList)
        and ns.Clan:GetClanLFGList(self.query, self.dungeonsOnly, self.sourceFilter)
        or {}

    local hideAvoidEnemy = ns.db and ns.db.settings and ns.db.settings.lfgHideAvoidEnemy == true
    local activeLockouts = (ns.Clan and ns.Clan.GetSavedLockouts) and ns.Clan:GetSavedLockouts(true) or {}

    local rows = {}
    local foundSelected = nil
    for _, item in ipairs(rawRows) do
        local suppressed = false
        if hideAvoidEnemy and not item.isSelf then
            local lkKey = item.lookupKey or item.displayName
            local sMeta = Store and (Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(lkKey) or (Store.GetSocialMeta and Store:GetSocialMeta(lkKey)))
            if sMeta and sMeta.flag == "AVOID" then
                suppressed = true
            elseif item.guild and item.guild ~= "" and ns.Spotter and ns.Spotter.ClassifyGuild and ns.Spotter:ClassifyGuild(item.guild) == "ENEMY" then
                suppressed = true
            end
        end
        if (not suppressed) and MatchesCategoryFilter(item, self.categoryFilter) then
            item._lockoutInfo = GetActivityLockout(item, activeLockouts)
            rows[#rows + 1] = item
            if self.selectedKey and GetItemIdentityKey(item) == self.selectedKey then
                foundSelected = item
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

    local emptyMsg
    if self.sourceFilter == "FRIENDS" then
        emptyMsg = L["No groups from Friends or Watchlist right now."]
    elseif self.sourceFilter == "ALLY" then
        emptyMsg = L["No Allied Clan groups detected yet."]
    elseif self.categoryFilter == "ALL" and (not self.query or self.query == "") then
        emptyMsg = L["Select a category or filter above to browse groups from your Clan, Allied Clans, Friends, and Watchlist, or click 'List Group' below to post your group."]
    else
        emptyMsg = L["No active Clan or Allied group listings yet."]
    end

    self:UpdateViewLayout()
    self.list:SetData(rows, emptyMsg, false)
    self:UpdateBottomButtons()
end

function LFGFrameTab:BuildSubPanel()
    local parent = _G.LFGParentFrame
    if self.subPanel or not parent then return end

    local artInfo = HarvestLfgListingArt(true)

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
    if panel.PortraitContainer and panel.PortraitContainer.Hide then
        panel.PortraitContainer:Hide()
    end
    if panel.SetTitle then
        pcall(panel.SetTitle, panel, (_G.LOOKING_FOR_GROUP or L["Looking for Group"]))
    elseif panel.TitleContainer and panel.TitleContainer.TitleText then
        pcall(panel.TitleContainer.TitleText.SetText, panel.TitleContainer.TitleText, (_G.LOOKING_FOR_GROUP or L["Looking for Group"]))
    end
    panel:Hide()

    -- Mandatory 100% Opaque Solid Backing Quads (Rule #12) preserving NineSlice & brown stone TitleBg
    local titleBacking = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
    titleBacking:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -2)
    titleBacking:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -4, -21)
    titleBacking:SetTexture(WHITE8X8)
    titleBacking:SetVertexColor(0.12, 0.10, 0.08, 1.0)
    panel._titleOpaqueBg = titleBacking

    local opaqueBg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
    opaqueBg:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -21)
    opaqueBg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 3)
    opaqueBg:SetTexture(WHITE8X8)
    opaqueBg:SetVertexColor(0.08, 0.075, 0.07, 1.0)
    panel._solidOpaqueBg = opaqueBg

    -- Native Forever artwork frame strictly INSIDE LFGParentFrame's NineSlice/TitleBar/Portrait chrome
    local artFrame = CreateFrame("Frame", nil, panel)
    artFrame:SetAllPoints(panel)
    artFrame:SetFrameLevel((panel:GetFrameLevel() or 2) + 1)
    self.controls.artFrame = artFrame

    local bgArt = artFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgArt:SetPoint("TOPLEFT", artFrame, "TOPLEFT", 3, -96)
    bgArt:SetPoint("BOTTOMRIGHT", artFrame, "BOTTOMRIGHT", -4, 3)
    if HasAtlas("groupfinder-background") then
        bgArt:SetAtlas("groupfinder-background", false)
    else
        bgArt:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble")
        bgArt:SetVertexColor(0.22, 0.21, 0.19, 1.0)
    end
    self.controls.bgArt = bgArt

    local headerBg = artFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
    headerBg:SetPoint("TOPLEFT", artFrame, "TOPLEFT", 3, -21)
    headerBg:SetPoint("TOPRIGHT", artFrame, "TOPRIGHT", -4, -21)
    headerBg:SetHeight(75)
    if HasAtlas("groupfinder-Stat-StoneBG") then
        headerBg:SetAtlas("groupfinder-Stat-StoneBG", false)
    else
        headerBg:SetTexture(WHITE8X8)
        headerBg:SetVertexColor(0.14, 0.13, 0.11, 1.0)
    end
    self.controls.headerBg = headerBg

    local headerSep = artFrame:CreateTexture(nil, "ARTWORK", nil, 2)
    headerSep:SetHeight(1)
    headerSep:SetPoint("TOPLEFT", artFrame, "TOPLEFT", 3, -96)
    headerSep:SetPoint("TOPRIGHT", artFrame, "TOPRIGHT", -4, -96)
    headerSep:SetTexture(WHITE8X8)
    headerSep:SetVertexColor(0.45, 0.35, 0.18, 0.85)
    self.controls.headerSep = headerSep

    local insideFrame = artFrame:CreateTexture(nil, "ARTWORK", nil, 1)
    insideFrame:SetPoint("TOPLEFT", artFrame, "TOPLEFT", 3, -96)
    insideFrame:SetPoint("BOTTOMRIGHT", artFrame, "BOTTOMRIGHT", -4, 3)
    if HasAtlas("common-insideframe") then
        insideFrame:SetAtlas("common-insideframe", false)
    else
        insideFrame:Hide()
    end
    self.controls.insideFrame = insideFrame

    -- Interactive controls container cleanly inside LFGParentFrame chrome (under 500+)
    local body = CreateFrame("Frame", nil, panel)
    body:SetAllPoints(panel)
    body:SetFrameLevel((panel:GetFrameLevel() or 2) + 4)
    self.controls.body = body

    -- 1) Browse Header Strip (y = -21..-78): Category Dropdown + Filter Dropdown + Refresh + [?]
    local browseHeader = CreateFrame("Frame", nil, body)
    browseHeader:SetAllPoints(body)
    browseHeader:Hide()
    self.controls.browseHeader = browseHeader

    local catDropdown = CreateNativeDropdown(
        browseHeader,
        "SocialCentralLFGCategoryDropdown",
        138,
        24,
        function()
            return GetCategoryLabel(LFGFrameTab.categoryFilter)
        end,
        function(root)
            if root.CreateTitle then
                root:CreateTitle(L["Category"])
            end
            for _, opt in ipairs(CATEGORY_OPTIONS) do
                AddDropdownMenuChoice(root, L[opt.labelKey], function()
                    return LFGFrameTab.categoryFilter == opt.id
                end, function()
                    LFGFrameTab.categoryFilter = opt.id
                    LFGFrameTab:RefreshData()
                end)
            end
        end
    )
    catDropdown:SetPoint("TOPLEFT", browseHeader, "TOPLEFT", 62, -37)
    self.controls.catDropdown = catDropdown

    local filterDropdown = CreateNativeDropdown(
        browseHeader,
        "SocialCentralLFGFilterDropdown",
        158,
        24,
        function()
            return GetSourceFilterDropdownLabel(LFGFrameTab.sourceFilter)
        end,
        function(root)
            if root.CreateTitle then
                root:CreateTitle(L["Clans & Allies LFG"])
            end
            for _, opt in ipairs(SOURCE_FILTERS) do
                AddDropdownMenuChoice(root, L[opt.dropdownKey], function()
                    return LFGFrameTab.sourceFilter == opt.id
                end, function()
                    LFGFrameTab.sourceFilter = opt.id
                    LFGFrameTab:RefreshData()
                end)
            end
            if root.CreateDivider then root:CreateDivider() end
            if root.CreateCheckbox then
                root:CreateCheckbox(L["Hide Avoid / Enemy"], function()
                    return ns.db and ns.db.settings and ns.db.settings.lfgHideAvoidEnemy == true
                end, function()
                    if ns.db and ns.db.settings then
                        ns.db.settings.lfgHideAvoidEnemy = not (ns.db.settings.lfgHideAvoidEnemy == true)
                        LFGFrameTab:RefreshData()
                    end
                end)
            end
            root:CreateButton(L["List Group"], function()
                LFGFrameTab.viewMode = "categories"
                LFGFrameTab:RefreshData()
            end)
            if LFGFrameTab.query and LFGFrameTab.query ~= "" then
                root:CreateButton(L["Clear Keyword Filter"], function()
                    LFGFrameTab.query = ""
                    LFGFrameTab:RefreshData()
                end)
            end
            root:CreateButton(L["My Group"], function()
                LFGFrameTab:OpenOfficialModule("group")
            end)
        end
    )
    filterDropdown:SetPoint("LEFT", catDropdown, "RIGHT", 6, 0)
    self.controls.filterDropdown = filterDropdown

    local refreshBtn = CreateFrame("Button", "SocialCentralLFGRefreshButton", browseHeader)
    refreshBtn:SetSize(30, 30)
    refreshBtn:SetPoint("LEFT", filterDropdown, "RIGHT", 6, 0)
    refreshBtn:SetNormalTexture("Interface\\Buttons\\UI-SquareButton-Up")
    refreshBtn:SetPushedTexture("Interface\\Buttons\\UI-SquareButton-Down")
    refreshBtn:SetDisabledTexture("Interface\\Buttons\\UI-SquareButton-Disabled")
    local refHl = refreshBtn:CreateTexture(nil, "HIGHLIGHT")
    refHl:SetAllPoints()
    refHl:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    refHl:SetBlendMode("ADD")
    local refIcon = refreshBtn:CreateTexture(nil, "ARTWORK", nil, 5)
    refIcon:SetSize(16, 16)
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
        if ns.Social and ns.Social.RequestRosters then
            ns.Social:RequestRosters(false)
        end
        LFGFrameTab:RefreshData()
    end)
    self.controls.refreshBtn = refreshBtn

    local helpBtn = Theme:CreateHelpButton(
        browseHeader,
        L["Help: Integrated Clan & Allies LFG"],
        L["Searches groups across your Clan, Allied Guilds (Clan Diplomacy), Friends, and Watchlist inside Blizzard's Looking for Group window."],
        L["Filter by All, Same Clan, Allied Clans, or Friends / Watchlist (including groups they signed up for). Right-click any listing to whisper, invite, or Track on Radar."]
    )
    helpBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 6, 0)

    -- 2) Native Forever 4-Role Circle Header Strip (y = -21..-96) matching LFGListingFrame
    local roleHeader = CreateFrame("Frame", nil, body)
    roleHeader:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    roleHeader:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    roleHeader:SetHeight(98)
    self.controls.roleHeader = roleHeader

    local divider = roleHeader:CreateTexture(nil, "ARTWORK", nil, 2)
    divider:SetSize(2, 74)
    divider:SetPoint("TOPLEFT", roleHeader, "TOPLEFT", 231, -22)
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
        L["Select a listing above to send a whisper or invite to group."]
    )
    roleHelpBtn:SetPoint("TOPRIGHT", roleHeader, "TOPRIGHT", -6, -24)
    self.controls.roleHelpBtn = roleHelpBtn

    -- 3) View A: Category Selection Banners (Masmorras, Raides, Missoes, Campos de Batalha, Guilda & Personalizado)
    local categoryView = CreateFrame("Frame", nil, body)
    categoryView:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -102)
    categoryView:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -10, 42)
    self.controls.categoryView = categoryView

    local categoryButtons = {}
    for idx, catDef in ipairs(LISTING_CATEGORIES) do
        categoryButtons[#categoryButtons + 1] = CreateCategoryBannerButton(categoryView, catDef, idx, artInfo)
    end
    self.controls.categoryButtons = categoryButtons

    -- 4) View B: Activity Checklist, Playstyle, Notes & Broadcast View
    local activityView = CreateFrame("Frame", nil, body)
    activityView:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -102)
    activityView:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 42)
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
    allLevelsLbl:SetPoint("RIGHT", allLevelsCheck, "LEFT", -2, 0)
    allLevelsLbl:SetWidth(116)
    allLevelsLbl:SetJustifyH("RIGHT")
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
    function actList:Render()
        if origActRender then
            origActRender(self)
        end
        local needsScroll = (self.thumb and self.thumb.IsShown and self.thumb:IsShown()) == true
        if self.track and self.track.SetShown then
            self.track:SetShown(needsScroll)
        end
        for _, ch in ipairs({ self.container:GetChildren() }) do
            if ch ~= self.viewport and ch ~= self.track and ch.GetObjectType and ch:GetObjectType() == "Button" then
                ch:SetShown(needsScroll)
            end
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
            for _, opt in ipairs(BROADCAST_OPTIONS) do
                AddDropdownMenuChoice(root, L[opt.labelKey], function()
                    return LFGFrameTab.broadcastMode == opt.id
                end, function()
                    LFGFrameTab.broadcastMode = opt.id
                    LFGFrameTab:RefreshData()
                end)
            end
        end
    )
    broadcastDropdown:SetPoint("BOTTOMRIGHT", activityView, "BOTTOMRIGHT", -6, 4)
    self.controls.broadcastDropdown = broadcastDropdown

    local broadcastLbl = activityView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    broadcastLbl:SetPoint("RIGHT", broadcastDropdown, "LEFT", -8, 0)
    broadcastLbl:SetJustifyH("RIGHT")
    broadcastLbl:SetText(L["Broadcast to"])
    broadcastLbl:SetTextColor(1.0, 0.82, 0.0)

    -- 5) View C: Scrollable Native Browse List over groupfinder-background cliff illustration
    local list = Theme:CreateScrollList(body, 52, CreateLfgRow, UpdateLfgRow)
    list.container:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -84)
    list.container:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 42)
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
        Theme:ApplyBackdrop(self.container, "none")
        if self.emptyLabel then
            self.emptyLabel:SetTextColor(0.86, 0.84, 0.78)
        end
    end

    local origListRender = list.Render
    function list:Render()
        if origListRender then
            origListRender(self)
        end
        if self.emptyLabel then
            self.emptyLabel:SetTextColor(0.86, 0.84, 0.78)
        end
        local needsScroll = (self.thumb and self.thumb.IsShown and self.thumb:IsShown()) == true
        if self.track and self.track.SetShown then
            self.track:SetShown(needsScroll)
        end
        for _, ch in ipairs({ self.container:GetChildren() }) do
            if ch ~= self.viewport and ch ~= self.track and ch.GetObjectType and ch:GetObjectType() == "Button" then
                ch:SetShown(needsScroll)
            end
        end
    end
    self.list = list

    -- 6) Unified Native Bottom Action Bar shared cleanly across Categories / Activities / Browse
    local sendMsgBtn = CreateNativeButton(body, nil, 126, 24, L["Send Message"])
    AutoFitNativeButton(sendMsgBtn, 110, 20, 146)
    sendMsgBtn:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 14, 11)
    sendMsgBtn:SetScript("OnClick", function()
        if LFGFrameTab.selectedItem then
            OpenPlayerWhisper(LFGFrameTab.selectedItem)
        end
    end)
    self.controls.sendMsgBtn = sendMsgBtn

    local inviteBtn = CreateNativeButton(body, nil, 118, 24, L["Invite"])
    AutoFitNativeButton(inviteBtn, 104, 20, 140)
    inviteBtn:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -14, 11)
    inviteBtn:SetScript("OnClick", function()
        local sel = LFGFrameTab.selectedItem
        local canInviteLfg, invTarget, invBnetId = ResolveLfgInviteTarget(sel)
        if canInviteLfg and Compat.Invite then
            Compat.Invite(invTarget, invBnetId)
        end
    end)
    self.controls.inviteBtn = inviteBtn

    local listGroupBtn = CreateNativeButton(body, nil, 108, 24, L["List Group"])
    AutoFitNativeButton(listGroupBtn, 96, 18, 130)
    listGroupBtn:SetPoint("BOTTOM", body, "BOTTOM", -10, 11)
    listGroupBtn:SetScript("OnClick", function()
        LFGFrameTab.viewMode = "categories"
        LFGFrameTab:RefreshData()
    end)
    self.controls.listGroupBtn = listGroupBtn

    local browseGroupsBtn = CreateNativeButton(body, nil, 124, 24, L["Browse Groups"])
    AutoFitNativeButton(browseGroupsBtn, 108, 20, 152)
    browseGroupsBtn:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 14, 11)
    browseGroupsBtn:SetScript("OnClick", function()
        LFGFrameTab.viewMode = "browse"
        LFGFrameTab:RefreshData()
    end)
    self.controls.browseGroupsBtn = browseGroupsBtn

    local backBtn = CreateNativeButton(body, nil, 106, 24, L["Back"])
    AutoFitNativeButton(backBtn, 92, 18, 124)
    backBtn:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 14, 11)
    backBtn:SetScript("OnClick", function()
        LFGFrameTab.viewMode = "categories"
        LFGFrameTab:RefreshData()
    end)
    self.controls.backBtn = backBtn

    local listSelfBtn = CreateNativeButton(body, nil, 114, 24, L["List Self"])
    AutoFitNativeButton(listSelfBtn, 100, 18, 134)
    listSelfBtn:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -14, 11)
    listSelfBtn:SetScript("OnClick", function()
        LFGFrameTab:SubmitListing()
    end)
    self.controls.listSelfBtn = listSelfBtn

    local unlistBtn = CreateNativeButton(body, nil, 86, 24, L["Unlist"])
    AutoFitNativeButton(unlistBtn, 72, 16, 106)
    unlistBtn:SetPoint("BOTTOM", body, "BOTTOM", 0, 11)
    unlistBtn:SetScript("OnClick", function()
        if ns.Clan and ns.Clan.ClearMyLFG then
            ns.Clan:ClearMyLFG()
        end
        LFGFrameTab:RefreshData()
    end)
    self.controls.unlistBtn = unlistBtn

    local listHelpBtn = Theme:CreateHelpButton(
        body,
        L["Help: Quick LFG Post"],
        L["Quickly broadcasts your LFG/LFM group listing to your Clan and Allied Clans without leaving the Group Finder window."],
        L["Select a listing above to send a whisper or invite to group."]
    )
    listHelpBtn:SetPoint("RIGHT", listSelfBtn, "LEFT", -6, 0)
    self.controls.listHelpBtn = listHelpBtn

    self.subPanel = panel
    self:UpdateViewLayout()
    self:RefreshTheme()
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
            end
        )
    end

    local gapY = MeasureTabGap(nativeTabs, -2)
    self.sideTab:ClearAllPoints()
    self.sideTab:SetPoint("TOPLEFT", lastNative, "BOTTOMLEFT", 0, gapY)
    self.sideTab:Show()
    ElevateLfgParentControls()
    self:UpdateTabSelectionVisual()

    local function HookTabControl(ctrl)
        if not ctrl or ctrl._scHookedClick then return end
        ctrl._scHookedClick = true
        if ctrl.HasScript and ctrl:HasScript("OnClick") then
            ctrl:HookScript("OnClick", function()
                if LFGFrameTab.active then
                    LFGFrameTab:HideSubPanel(false)
                end
                if ns.UI and ns.UI.CloseEmbeddedIfHost and _G.LFGParentFrame then
                    ns.UI:CloseEmbeddedIfHost(_G.LFGParentFrame)
                end
            end)
        end
        if ctrl.HasScript and ctrl:HasScript("OnMouseUp") then
            ctrl:HookScript("OnMouseUp", function(_, btn)
                if btn == "LeftButton" then
                    if LFGFrameTab.active and IsAnyNativeSubFrameShown() then
                        LFGFrameTab:HideSubPanel(false)
                    end
                    if ns.UI and ns.UI.CloseEmbeddedIfHost and _G.LFGParentFrame then
                        ns.UI:CloseEmbeddedIfHost(_G.LFGParentFrame)
                    end
                end
            end)
        end
    end

    for _, nTab in ipairs(nativeTabs) do
        HookTabControl(nTab)
    end
    for _, key in ipairs({ "Tab1", "Tab2", "Tab3" }) do
        HookTabControl(parent[key])
    end
end

function LFGFrameTab:AttachHooks()
    local parent = _G.LFGParentFrame
    if self.hooked or not parent then return end
    self.hooked = true

    parent:HookScript("OnShow", function()
        if LFGFrameTab.active and IsAnyNativeSubFrameShown() then
            LFGFrameTab:HideSubPanel(false)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                LFGFrameTab:EnsureSideTab()
            end)
        else
            LFGFrameTab:EnsureSideTab()
        end
    end)

    parent:HookScript("OnHide", function()
        LFGFrameTab:HideSubPanel(false)
    end)

    if hooksecurefunc and type(parent.UpdateTabs) == "function" and not parent._scHookedUpdateTabs then
        parent._scHookedUpdateTabs = true
        hooksecurefunc(parent, "UpdateTabs", function()
            LFGFrameTab:EnsureSideTab()
            if not LFGFrameTab.active then return end
            if IsAnyNativeSubFrameShown() then
                LFGFrameTab:HideSubPanel(false)
            else
                SetNativeTabsCheckedFalse()
                LFGFrameTab:UpdateTabSelectionVisual()
            end
        end)
    end

    if _G.LFGListingFrame and _G.LFGListingFrame.HookScript and not _G.LFGListingFrame._scArtHooked then
        _G.LFGListingFrame._scArtHooked = true
        _G.LFGListingFrame:HookScript("OnShow", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
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
                local socialUnread = ns.Chat and ((ns.Chat.GetUnreadDirectCount and ns.Chat:GetUnreadDirectCount()) or (ns.Chat.GetTotalUnread and ns.Chat:GetTotalUnread(false))) or 0
                local targetTab = (socialUnread > 0) and "chat" or "watchlist"
                if ns.UI then
                    ns.UI:OpenEmbedded(parent, { "watchlist", "social", "nearby", "chat" }, targetTab)
                end
                if targetTab == "watchlist" and ns.Watchlist and ns.Watchlist.AutoCheckNextFromHardwareClick then
                    ns.Watchlist:AutoCheckNextFromHardwareClick()
                end
            end
        )
        self.socialTab:SetScript("OnEnter", function(selfBtn)
            GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["SocialCentral: Watchlist, Social & Chat"], 0.35, 0.72, 1.0)
            local summary = ns.Chat and ns.Chat.GetUnreadSummary and ns.Chat:GetUnreadSummary()
            local unreadDirect = summary and summary.totalDirect or 0
            if unreadDirect > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine(L["Unread Messages (Direct)"], tostring(unreadDirect), 1.0, 0.42, 0.42, 1.0, 0.85, 0.35)
                if summary.senders then
                    local shown = 0
                    for _, item in ipairs(summary.senders) do
                        if shown >= 5 then break end
                        GameTooltip:AddDoubleLine("  " .. tostring(item.title or "?"), tostring(item.unread or 0), 0.90, 0.94, 0.98, 1.0, 0.42, 0.42)
                        shown = shown + 1
                    end
                end
                if (summary.invites or 0) > 0 then
                    GameTooltip:AddDoubleLine("  " .. L["Room Invite"], tostring(summary.invites), 0.58, 0.88, 0.98, 1.0, 0.85, 0.35)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Click to open Conversations"], 0.40, 0.92, 0.55, true)
            else
                GameTooltip:AddLine(L["View Watchlist (/who), Social folders, Battle.net/Guild friends, and Nearby players right inside Blizzard's Social window."], 0.85, 0.88, 0.92, true)
                if ns.Watchlist and ns.Watchlist.GetStats then
                    local on = ns.Watchlist:GetStats()
                    local socOnline = ns.Social and ns.Social.GetCount and ns.Social:GetCount("all") or 0
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddDoubleLine(L["Watchlist"] .. " (" .. L["Online"] .. ")", tostring(on or 0), 0.78, 0.84, 0.92, 0.40, 0.92, 0.55)
                    GameTooltip:AddDoubleLine(L["Social"] .. " (" .. L["Online"] .. ")", tostring(socOnline or 0), 0.78, 0.84, 0.92, 0.58, 0.88, 0.98)
                end
            end
            GameTooltip:Show()
        end)
    end

    self.socialTab:ClearAllPoints()
    if lastNative then
        local gapY = MeasureTabGap(nativeTabs, -2)
        self.socialTab:SetPoint("TOPLEFT", lastNative, "BOTTOMLEFT", 0, gapY)
        if not self.socialTab._nativeTabsHooked then
            self.socialTab._nativeTabsHooked = true
            for _, nt in ipairs(nativeTabs) do
                if nt.HasScript and nt:HasScript("OnClick") then
                    nt:HookScript("OnClick", function()
                        if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
                    end)
                end
            end
        end
    else
        self.socialTab:SetPoint("TOPLEFT", parent, "TOPRIGHT", -2, -240)
    end
    self.socialTab:Show()
    self:SyncAllEmbeddedTabStates()
end

function LFGFrameTab:AttachSocialUI()
    local parent = _G.SocialUIFrame or _G.FriendsFrame
    if self.socialHooked or not parent then return end
    self.socialHooked = true

    parent:HookScript("OnShow", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() LFGFrameTab:EnsureSocialSideTab() end)
        else
            LFGFrameTab:EnsureSocialSideTab()
        end
    end)

    if hooksecurefunc then
        if type(parent.SelectTab) == "function" then
            hooksecurefunc(parent, "SelectTab", function()
                if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
            end)
        end
        if type(parent.ResetTabs) == "function" then
            hooksecurefunc(parent, "ResetTabs", function()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function() LFGFrameTab:EnsureSocialSideTab() end)
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
            end
        )
    end

    local maxLvl = math.max(520, (lastNative and lastNative.GetFrameLevel and lastNative:GetFrameLevel() or 510) + 2)
    self.guildTab:SetFrameLevel(maxLvl)
    self.guildTab:ClearAllPoints()
    if lastNative then
        local defaultGap = (self.guildTab:GetWidth() or 32) < 44 and -20 or -2
        local gapY = MeasureTabGap(nativeTabs, defaultGap)
        self.guildTab:SetPoint("TOPLEFT", lastNative, "BOTTOMLEFT", 0, gapY)
        -- Hook every native tab individually as guild-only tabs can appear dynamically when switching clubs.
        for _, nt in ipairs(nativeTabs) do
            if nt.HasScript and nt:HasScript("OnClick") and not nt._scGuildCloseHooked then
                nt._scGuildCloseHooked = true
                nt:HookScript("OnClick", function(clickedTab)
                    parent._scLastNativeTab = clickedTab
                    if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
                end)
            end
        end
    else
        self.guildTab:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, -240)
    end
    self.guildTab:Show()
    self:SyncAllEmbeddedTabStates()
end

function LFGFrameTab:AttachCommunitiesUI()
    local parent = _G.CommunitiesFrame or _G.GuildFrame
    if self.guildHooked or not parent then return end
    self.guildHooked = true

    parent:HookScript("OnShow", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() LFGFrameTab:EnsureGuildSideTab() end)
        else
            LFGFrameTab:EnsureGuildSideTab()
        end
    end)

    if hooksecurefunc then
        if type(parent.SetDisplayMode) == "function" then
            hooksecurefunc(parent, "SetDisplayMode", function()
                if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function() LFGFrameTab:EnsureGuildSideTab() end)
                end
            end)
        end
        if type(parent.OnClubSelected) == "function" then
            hooksecurefunc(parent, "OnClubSelected", function()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function() LFGFrameTab:EnsureGuildSideTab() end)
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
function LFGFrameTab:EnsureCharacterSideTab()
    local parent = _G.CharacterFrame
    if not parent then return end
    if ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled("C") then
        if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
        if self.charTab then self.charTab:Hide() end
        return
    end

    local nativeTabs = DiscoverRightSideTabs(parent, self.charTab)
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
            end
        )
    end

    self.charTab:ClearAllPoints()
    if lastNative then
        local gapY = MeasureTabGap(nativeTabs, -2)
        self.charTab:SetPoint("TOPLEFT", lastNative, "BOTTOMLEFT", 0, gapY)
        for _, nt in ipairs(nativeTabs) do
            if not nt._scCharCloseHooked and nt.HasScript and nt:HasScript("OnClick") then
                nt._scCharCloseHooked = true
                nt:HookScript("OnClick", function()
                    if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
                end)
            end
        end
    else
        self.charTab:SetPoint("TOPLEFT", parent, "TOPRIGHT", -2, -260)
    end
    self.charTab:Show()
    self:SyncAllEmbeddedTabStates()
end

function LFGFrameTab:AttachCharacterUI()
    local parent = _G.CharacterFrame
    if self.charHooked or not parent then return end
    self.charHooked = true

    parent:HookScript("OnShow", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() LFGFrameTab:EnsureCharacterSideTab() end)
        else
            LFGFrameTab:EnsureCharacterSideTab()
        end
    end)

    if hooksecurefunc then
        if type(parent.ShowSubFrame) == "function" then
            hooksecurefunc(parent, "ShowSubFrame", function()
                if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
            end)
        end
        if type(parent.UpdateTabLayout) == "function" then
            hooksecurefunc(parent, "UpdateTabLayout", function()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function() LFGFrameTab:EnsureCharacterSideTab() end)
                end
            end)
        end
        if type(_G.CharacterFrameTab_OnClick) == "function" then
            hooksecurefunc("CharacterFrameTab_OnClick", function()
                if ns.UI then ns.UI:CloseEmbeddedIfHost(parent) end
            end)
        end
    end

    if parent.IsShown and parent:IsShown() then
        self:EnsureCharacterSideTab()
    end
end

-- ChatFrame1 floating overlay button removed by design; Private & Alliance Chat stays docked inside Social ('O').
function LFGFrameTab:AttachChatButton()
    if _G.SocialCentralChatButton and _G.SocialCentralChatButton.Hide then
        _G.SocialCentralChatButton:Hide()
    end
    self.chatBtn = nil
    self.chatHooked = true
end

-- ============================================================================
-- Official Game Window Integration #6: WorldMapFrame ('M') -> World Buffs Pins & Mouseover Pill
-- ============================================================================
local WORLD_BUFF_ICON_FALLBACK = 134153 -- Inv_Misc_Head_Dragon_01

-- Classic / Forever World Buff locations mapped to verified uiMapIDs.
-- Dire Maul North's three tribute buffs share one grouped Feralas pin to avoid overlapping icons.
local WORLD_BUFF_MAP_PINS = {
    {
        key = "dragonslayer_sw",
        mapID = 1453, -- Stormwind City
        x = 0.635,
        y = 0.718,
        faction = "Alliance",
        label = L["Stormwind — Valley of Heroes"],
        buffIds = { "dragonslayer" },
        continent = { [1415] = { 0.435, 0.742 }, [947] = { 0.652, 0.674 } },
    },
    {
        key = "stormwind_keep",
        mapID = 1453, -- Stormwind City
        x = 0.755,
        y = 0.312,
        faction = "Alliance",
        label = L["Stormwind — Keep"],
        buffIds = { "stormwind" },
        continent = { [1415] = { 0.449, 0.728 }, [947] = { 0.660, 0.668 } },
    },
    {
        key = "dragonslayer_org",
        mapID = 1454, -- Orgrimmar
        x = 0.518,
        y = 0.822,
        faction = "Horde",
        label = L["Orgrimmar — Valley of Strength"],
        buffIds = { "dragonslayer" },
        continent = { [1414] = { 0.578, 0.465 }, [947] = { 0.316, 0.478 } },
    },
    {
        key = "warchief_org",
        mapID = 1454, -- Orgrimmar
        x = 0.342,
        y = 0.382,
        faction = "Horde",
        label = L["Orgrimmar — Grommash Hold"],
        buffIds = { "warchief" },
        continent = { [1414] = { 0.562, 0.434 }, [947] = { 0.308, 0.456 } },
    },
    {
        key = "warchief_barrens",
        mapID = 1413, -- The Barrens
        x = 0.519,
        y = 0.304,
        faction = "Horde",
        label = L["The Barrens — The Crossroads"],
        buffIds = { "warchief" },
        continent = { [1414] = { 0.525, 0.518 }, [947] = { 0.289, 0.510 } },
    },
    {
        key = "zandalar_stv",
        mapID = 1434, -- Stranglethorn Vale
        x = 0.154,
        y = 0.160,
        faction = "Both",
        label = L["Stranglethorn Vale — Yojamba Isle"],
        buffIds = { "zandalar" },
        continent = { [1415] = { 0.405, 0.858 }, [947] = { 0.635, 0.752 } },
    },
    {
        key = "songflower_felwood",
        mapID = 1448, -- Felwood
        x = 0.506,
        y = 0.568,
        faction = "Both",
        label = L["Felwood — Songflower Glade"],
        buffIds = { "songflower" },
        continent = { [1414] = { 0.472, 0.295 }, [947] = { 0.258, 0.362 } },
    },
    {
        key = "dm_feralas",
        mapID = 1444, -- Feralas
        x = 0.625,
        y = 0.249,
        faction = "Both",
        label = L["Feralas — Dire Maul North"],
        buffIds = { "dm_moldar", "dm_fengus", "dm_slipkik" },
        continent = { [1414] = { 0.408, 0.658 }, [947] = { 0.219, 0.602 } },
    },
    {
        key = "dmf_elwynn",
        mapID = 1429, -- Elwynn Forest
        x = 0.418,
        y = 0.692,
        faction = "Both",
        label = L["Elwynn Forest — Goldshire"],
        buffIds = { "dmf" },
        continent = { [1415] = { 0.456, 0.774 }, [947] = { 0.665, 0.695 } },
    },
    {
        key = "dmf_mulgore",
        mapID = 1412, -- Mulgore
        x = 0.370,
        y = 0.375,
        faction = "Both",
        label = L["Mulgore — Thunder Bluff"],
        buffIds = { "dmf" },
        continent = { [1414] = { 0.440, 0.558 }, [947] = { 0.240, 0.535 } },
    },
    {
        key = "silithyst_silithus",
        mapID = 1451, -- Silithus
        x = 0.525,
        y = 0.655,
        faction = "Both",
        label = L["Silithus — Silithyst Field"],
        buffIds = { "silithyst" },
        continent = { [1414] = { 0.422, 0.858 }, [947] = { 0.226, 0.735 } },
    },
}

local function GetPlayerFactionSafe()
    local f = ns.Compat and ns.Compat.PlayerFaction and ns.Compat.PlayerFaction()
    if f == "Alliance" or f == "Horde" then
        return f
    end
    return "Both"
end

local function AreWorldMapPinsEnabled()
    return not (ns.db and ns.db.settings and ns.db.settings.worldBuffsMapPins == false)
end

local function GetWorldBuffLookup()
    local defById = {}
    local activeById = {}
    local activeList = {}
    if ns.WorldBuffs and ns.WorldBuffs.GetDefinitions then
        for _, def in ipairs(ns.WorldBuffs:GetDefinitions()) do
            defById[def.id] = def
        end
    end
    if ns.WorldBuffs and ns.WorldBuffs.GetActiveBuffs then
        local active = ns.WorldBuffs:GetActiveBuffs()
        if type(active) == "table" then
            activeList = active
            for _, entry in ipairs(active) do
                if entry.def and entry.def.id then
                    activeById[entry.def.id] = entry
                end
            end
        end
    end
    return defById, activeById, activeList
end

local function ProjectWorldMapCoord(pinDef, targetMapID)
    if not targetMapID then return nil, nil end
    if pinDef.mapID == targetMapID then
        return pinDef.x, pinDef.y
    end
    local cache = pinDef._projCache
    if cache then
        local hit = cache[targetMapID]
        if hit ~= nil then
            if hit == false then return nil, nil end
            return hit[1], hit[2]
        end
    else
        cache = {}
        pinDef._projCache = cache
    end
    local px, py
    if C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        local ok1, inst, worldPos = pcall(C_Map.GetWorldPosFromMapPos, pinDef.mapID, CreateVector2D(pinDef.x, pinDef.y))
        if ok1 and inst and worldPos then
            local ok2, outMapID, outPos = pcall(C_Map.GetMapPosFromWorldPos, inst, worldPos, targetMapID)
            if ok2 and outMapID == targetMapID and outPos then
                if outPos.GetXY then
                    px, py = outPos:GetXY()
                else
                    px, py = outPos.x, outPos.y
                end
                if not (type(px) == "number" and type(py) == "number" and px >= 0.01 and px <= 0.99 and py >= 0.01 and py <= 0.99) then
                    px, py = nil, nil
                end
            end
        end
    end
    if not px then
        local fallback = pinDef.continent and pinDef.continent[targetMapID]
        if fallback then
            px, py = fallback[1], fallback[2]
        end
    end
    if px and py then
        cache[targetMapID] = { px, py }
        return px, py
    end
    cache[targetMapID] = false
    return nil, nil
end

local function GetPinAggregateStatus(pinDef, defById, activeById)
    local primaryDef = nil
    local hasActive = false
    local hasReady = false
    local hasCooldown = false
    local activeIcon = nil

    for _, buffId in ipairs(pinDef.buffIds) do
        local def = defById[buffId]
        if def then
            if not primaryDef then primaryDef = def end
            local active = activeById[buffId]
            if active then
                hasActive = true
                if not activeIcon and active.icon then
                    activeIcon = active.icon
                end
            elseif ns.WorldBuffs and ns.WorldBuffs.GetDropCooldownStatus then
                local cd = ns.WorldBuffs:GetDropCooldownStatus(def)
                if cd then
                    if cd.status == "READY" then
                        hasReady = true
                    elseif cd.status == "COOLDOWN" then
                        hasCooldown = true
                    end
                end
            end
        end
    end

    local icon = activeIcon or (primaryDef and primaryDef.icon) or WORLD_BUFF_ICON_FALLBACK
    local state = "IDLE"
    if hasActive then
        state = "ACTIVE"
    elseif hasReady then
        state = "READY"
    elseif hasCooldown then
        state = "COOLDOWN"
    end
    return state, icon, primaryDef
end

local function ShowWorldBuffPinTooltip(pinBtn)
    local pinDef = pinBtn.pinDef
    if not pinDef or not GameTooltip then return end
    local defById, activeById = GetWorldBuffLookup()

    GameTooltip:SetOwner(pinBtn, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(pinDef.label or "", 1.0, 0.84, 0.25)

    for _, buffId in ipairs(pinDef.buffIds) do
        local def = defById[buffId]
        if def then
            local active = activeById[buffId]
            local cd = ns.WorldBuffs and ns.WorldBuffs.GetDropCooldownStatus and ns.WorldBuffs:GetDropCooldownStatus(def)
            local rightText, rr, rg, rb
            if active then
                local rem = active.remaining and active.remaining > 0 and ns.WorldBuffs:FormatDuration(active.remaining) or L["Active"]
                rightText = L["Active: %s"]:format(rem)
                rr, rg, rb = 0.25, 0.95, 0.45
            else
                if cd and cd.status == "READY" then
                    rightText = L["Ready"]
                    rr, rg, rb = 1.0, 0.82, 0.18
                elseif cd and cd.status == "COOLDOWN" then
                    rightText = cd.text or "?"
                    rr, rg, rb = 0.95, 0.62, 0.22
                elseif cd and cd.status == "NO_COOLDOWN" then
                    rightText = L["No server cooldown"]
                    rr, rg, rb = 0.45, 0.85, 0.95
                elseif cd and cd.status == "SCHEDULED" then
                    rightText = cd.text or L["Scheduled"]
                    rr, rg, rb = 0.72, 0.82, 0.96
                elseif def.yellDelay and def.yellDelay > 0 then
                    rightText = L["Awaiting drop yell"]
                    rr, rg, rb = 0.65, 0.68, 0.74
                else
                    rightText = L["Open-world pickup"]
                    rr, rg, rb = 0.58, 0.78, 0.95
                end
            end
            GameTooltip:AddDoubleLine(def.name or buffId, rightText, 0.95, 0.95, 0.98, rr, rg, rb)
            if cd and cd.onyStatus and cd.nefStatus then
                GameTooltip:AddDoubleLine("  Onyxia (6h)", cd.onyStatus.text or "?", 0.72, 0.78, 0.86, 0.88, 0.90, 0.96)
                GameTooltip:AddDoubleLine("  Nefarian (8h)", cd.nefStatus.text or "?", 0.72, 0.78, 0.86, 0.88, 0.90, 0.96)
            elseif cd and cd.status == "NO_COOLDOWN" and cd.text then
                GameTooltip:AddLine("  " .. cd.text, 0.68, 0.84, 0.94, true)
            elseif active and cd and cd.text and (cd.status == "COOLDOWN" or cd.status == "READY") then
                GameTooltip:AddLine("  " .. cd.text, 0.82, 0.80, 0.64, true)
            end
            if cd and cd.peakText and cd.peakText ~= "" then
                GameTooltip:AddLine("  " .. cd.peakText, 0.55, 0.88, 0.72, true)
            end
            if def.effect and def.effect ~= "" then
                GameTooltip:AddLine("  " .. def.effect, 0.78, 0.84, 0.90, true)
            end
            if def.source and def.source ~= "" then
                GameTooltip:AddLine("  " .. def.source, 0.62, 0.66, 0.72, true)
            end
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Left-click: Report in chat"], 0.45, 0.85, 1.0)
    if pinBtn.canZoomZone then
        GameTooltip:AddLine(L["Right-click: Zoom to zone"], 0.45, 0.85, 1.0)
    end
    GameTooltip:Show()
end

local function ShowWorldBuffsPillTooltip(anchor)
    if not GameTooltip then return end
    local defById, activeById, activeList = GetWorldBuffLookup()
    local playerFaction = GetPlayerFactionSafe()

    GameTooltip:SetOwner(anchor, "ANCHOR_BOTTOMLEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(L["SocialCentral: World Buffs"], 0.35, 0.78, 1.0)

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Active World Buffs"], 1.0, 0.84, 0.28)
    if #activeList > 0 then
        for _, entry in ipairs(activeList) do
            local def = entry.def
            local rem = entry.remaining and entry.remaining > 0 and ns.WorldBuffs:FormatDuration(entry.remaining) or L["Active"]
            GameTooltip:AddDoubleLine(entry.name or (def and def.name) or "Buff", rem, 0.25, 0.95, 0.45, 0.75, 1.0, 0.82)
        end
    else
        GameTooltip:AddLine(L["No active world buffs on this character."], 0.65, 0.68, 0.74)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Capital Drop Cooldowns"], 1.0, 0.84, 0.28)
    local openWorld = {}
    if ns.WorldBuffs and ns.WorldBuffs.GetDefinitions then
        for _, def in ipairs(ns.WorldBuffs:GetDefinitions()) do
            if def.faction == "Both" or def.faction == playerFaction or playerFaction == "Both" then
                if (def.cooldown and def.cooldown > 0) or def.id == "zandalar" then
                    local cd = ns.WorldBuffs:GetDropCooldownStatus(def)
                    local st, r, g, b
                    if activeById[def.id] then
                        local aRem = activeById[def.id].remaining
                        st = L["Active: %s"]:format(aRem and aRem > 0 and ns.WorldBuffs:FormatDuration(aRem) or L["Active"])
                        r, g, b = 0.25, 0.95, 0.45
                    elseif cd and cd.status == "READY" then
                        st = L["Ready"]
                        r, g, b = 1.0, 0.82, 0.18
                    elseif cd and cd.status == "COOLDOWN" then
                        st = cd.text or "?"
                        r, g, b = 0.95, 0.62, 0.22
                    elseif cd and cd.status == "NO_COOLDOWN" then
                        st = L["No server cooldown"]
                        r, g, b = 0.45, 0.85, 0.95
                    elseif cd and cd.status == "SCHEDULED" then
                        st = cd.text or L["Scheduled"]
                        r, g, b = 0.72, 0.82, 0.96
                    elseif def.yellDelay and def.yellDelay > 0 then
                        st = L["Awaiting drop yell"]
                        r, g, b = 0.65, 0.68, 0.74
                    else
                        st = L["Open-world pickup"]
                        r, g, b = 0.62, 0.76, 0.90
                    end
                    GameTooltip:AddDoubleLine(def.name or def.id, st, 0.92, 0.94, 0.98, r, g, b)
                    if cd and cd.peakText and cd.peakText ~= "" then
                        GameTooltip:AddLine("  " .. cd.peakText, 0.55, 0.88, 0.72, true)
                    end
                else
                    openWorld[#openWorld + 1] = def
                end
            end
        end
    end

    if #openWorld > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Open-World & Tribute Buffs"], 1.0, 0.84, 0.28)
        for _, def in ipairs(openWorld) do
            local active = activeById[def.id]
            local st, r, g, b
            if active then
                local aRem = active.remaining
                st = aRem and aRem > 0 and ns.WorldBuffs:FormatDuration(aRem) or L["Active"]
                r, g, b = 0.25, 0.95, 0.45
            else
                st = L["Open-world pickup"]
                r, g, b = 0.62, 0.76, 0.90
            end
            GameTooltip:AddDoubleLine(def.name or def.id, st, 0.92, 0.94, 0.98, r, g, b)
        end
    end

    GameTooltip:AddLine(" ")
    local syncEnabled = ns.db and ns.db.settings and ns.db.settings.clanSync == true
    local syncState = syncEnabled and L["Enabled (Guild)"] or L["Local only"]
    GameTooltip:AddDoubleLine(L["Guild Buff Sync"], syncState, 0.72, 0.76, 0.82, syncEnabled and 0.30 or 0.75, syncEnabled and 0.92 or 0.68, syncEnabled and 0.50 or 0.50)
    local pinState = AreWorldMapPinsEnabled() and L["Shown"] or L["Hidden"]
    GameTooltip:AddDoubleLine(L["Map pins"], pinState, 0.72, 0.76, 0.82, AreWorldMapPinsEnabled() and 0.30 or 0.75, AreWorldMapPinsEnabled() and 0.92 or 0.45, AreWorldMapPinsEnabled() and 0.50 or 0.45)
    GameTooltip:AddLine(L["Left-click: Report in chat"], 0.45, 0.85, 1.0)
    GameTooltip:AddLine(L["Shift+Click: Open full Buffs window"], 0.45, 0.85, 1.0)
    GameTooltip:AddLine(L["Right-click: Toggle map pins"], 0.45, 0.85, 1.0)
    GameTooltip:Show()
end

local function AcquireWorldBuffPin(canvas, idx)
    LFGFrameTab.mapPins = LFGFrameTab.mapPins or {}
    local pin = LFGFrameTab.mapPins[idx]
    if pin then return pin end

    pin = CreateFrame("Button", "SocialCentralWorldMapBuffPin" .. idx, canvas, "BackdropTemplate")
    pin:SetSize(22, 22)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetFrameLevel(2050)

    local solidBg = pin:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetAllPoints()
    solidBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    solidBg:SetVertexColor(0.06, 0.05, 0.04, 1.0)
    pin._solidOpaqueBg = solidBg

    if pin.SetBackdrop then
        pin:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        pin:SetBackdropColor(0.06, 0.05, 0.04, 1.0)
        pin:SetBackdropBorderColor(0.76, 0.62, 0.28, 1.0)
    end

    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetPoint("TOPLEFT", pin, "TOPLEFT", 2, -2)
    pin.icon:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -2, 2)
    pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    pin.activeDot = pin:CreateTexture(nil, "OVERLAY")
    pin.activeDot:SetSize(8, 8)
    pin.activeDot:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", 1, -1)
    pin.activeDot:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
    pin.activeDot:Hide()

    pin:SetScript("OnEnter", function(selfPin)
        ShowWorldBuffPinTooltip(selfPin)
    end)
    pin:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    pin:SetScript("OnClick", function(selfPin, button)
        if not selfPin.pinDef then return end
        if button == "RightButton" then
            if selfPin.canZoomZone and _G.WorldMapFrame and _G.WorldMapFrame.SetMapID and not (InCombatLockdown and InCombatLockdown()) then
                pcall(_G.WorldMapFrame.SetMapID, _G.WorldMapFrame, selfPin.pinDef.mapID)
            end
            return
        end
        if IsShiftKeyDown and IsShiftKeyDown() then
            if ns.UI and ns.UI.ShowHub then
                ns.UI:ShowHub("buffs")
            end
            return
        end
        local defById, activeById = GetWorldBuffLookup()
        local chosenDef = nil
        for _, buffId in ipairs(selfPin.pinDef.buffIds) do
            if activeById[buffId] and defById[buffId] then
                chosenDef = defById[buffId]
                break
            end
            if not chosenDef and defById[buffId] then
                chosenDef = defById[buffId]
            end
        end
        if chosenDef and ns.WorldBuffs and ns.WorldBuffs.OpenIndividualBuffAnnouncement then
            ns.WorldBuffs:OpenIndividualBuffAnnouncement(chosenDef)
        elseif ns.WorldBuffs and ns.WorldBuffs.OpenChatAnnouncement then
            ns.WorldBuffs:OpenChatAnnouncement()
        end
    end)

    LFGFrameTab.mapPins[idx] = pin
    return pin
end

function LFGFrameTab:RefreshWorldMapBuffs()
    local mapFrame = _G.WorldMapFrame
    if ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled("M") then
        if self.mapPill then self.mapPill:Hide() end
        if self.mapPins then
            for _, p in ipairs(self.mapPins) do
                p:Hide()
            end
        end
        return
    end
    if self.mapPill then self.mapPill:Show() end
    if not (mapFrame and mapFrame.IsShown and mapFrame:IsShown()) then return end

    local defById, activeById, activeList = GetWorldBuffLookup()
    local playerFaction = GetPlayerFactionSafe()
    local pinsEnabled = AreWorldMapPinsEnabled()

    -- 1. Refresh compact corner badge/pill inside ScrollContainer
    local pill = self.mapPill
    if pill then
        local activeCount = #activeList
        if activeCount > 0 then
            pill.label:SetText(("%s (%d)"):format(L["World Buffs"], activeCount))
            pill.label:SetTextColor(0.38, 0.95, 0.52, 1)
        else
            pill.label:SetText(L["World Buffs"])
            pill.label:SetTextColor(1.0, 0.84, 0.30, 1)
        end

        local shownIcons = 0
        for i = 1, 5 do
            local slot = pill.miniIcons[i]
            local entry = activeList[i]
            if slot and entry then
                slot.tex:SetTexture(entry.icon or WORLD_BUFF_ICON_FALLBACK)
                slot:Show()
                shownIcons = shownIcons + 1
            elseif slot then
                slot:Hide()
            end
        end

        local lblWidth = pill.label:GetStringWidth() or 78
        local iconsWidth = shownIcons > 0 and (shownIcons * 17 + 4) or 0
        local totalWidth = math.max(128, math.min(268, math.ceil(26 + lblWidth + iconsWidth + 24)))
        pill:SetWidth(totalWidth)
        pill.emblem:SetTexture((activeList[1] and activeList[1].icon) or WORLD_BUFF_ICON_FALLBACK)
        if pill.SetBackdropBorderColor then
            if activeCount > 0 then
                pill:SetBackdropBorderColor(0.28, 0.82, 0.42, 1.0)
            else
                pill:SetBackdropBorderColor(0.72, 0.58, 0.25, 1.0)
            end
        end
    end

    -- 2. Refresh World Map Canvas Pins
    if self.mapPins then
        for _, p in ipairs(self.mapPins) do
            p:Hide()
        end
    end
    if not pinsEnabled or not mapFrame:IsShown() then return end

    local canvas = mapFrame.GetCanvas and mapFrame:GetCanvas()
    local currentMapID = mapFrame.GetMapID and mapFrame:GetMapID()
    if not canvas or not currentMapID then return end

    local cw, ch = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    if cw < 40 or ch < 40 then return end

    local isZoneMap = (currentMapID ~= 947 and currentMapID ~= 1414 and currentMapID ~= 1415)
    local pinSize = isZoneMap and 22 or 18
    local pinLevel = math.max(2050, (canvas:GetFrameLevel() or 2000) + 45)
    local idx = 0

    local dmfStatus = ns.WorldBuffs and ns.WorldBuffs.GetDarkmoonFaireStatus and ns.WorldBuffs:GetDarkmoonFaireStatus() or nil
    local activeDmfKey = nil
    if dmfStatus and dmfStatus.isActive then
        local t = date("*t", (GetServerTime and GetServerTime()) or time())
        activeDmfKey = (t and ((t.month or 1) % 2 == 1)) and "dmf_mulgore" or "dmf_elwynn"
    end

    for _, pinDef in ipairs(WORLD_BUFF_MAP_PINS) do
        local isDmfPin = (pinDef.key == "dmf_elwynn" or pinDef.key == "dmf_mulgore")
        local dmfVisible = (not isDmfPin) or (activeDmfKey == pinDef.key)
        if dmfVisible and (pinDef.faction == "Both" or pinDef.faction == playerFaction or playerFaction == "Both") then
            local px, py = ProjectWorldMapCoord(pinDef, currentMapID)
            if px and py then
                idx = idx + 1
                local pin = AcquireWorldBuffPin(canvas, idx)
                local state, icon = GetPinAggregateStatus(pinDef, defById, activeById)
                pin:SetParent(canvas)
                pin:SetSize(pinSize, pinSize)
                pin:SetFrameLevel(pinLevel)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", px * cw, -py * ch)
                pin.pinDef = pinDef
                pin.canZoomZone = (pinDef.mapID ~= currentMapID)
                pin.icon:SetTexture(icon)

                if state == "ACTIVE" then
                    if pin.SetBackdropBorderColor then pin:SetBackdropBorderColor(0.22, 0.92, 0.40, 1.0) end
                    pin.activeDot:Show()
                elseif state == "READY" then
                    if pin.SetBackdropBorderColor then pin:SetBackdropBorderColor(1.0, 0.84, 0.16, 1.0) end
                    pin.activeDot:Hide()
                elseif state == "COOLDOWN" then
                    if pin.SetBackdropBorderColor then pin:SetBackdropBorderColor(0.92, 0.56, 0.18, 1.0) end
                    pin.activeDot:Hide()
                else
                    if pin.SetBackdropBorderColor then pin:SetBackdropBorderColor(0.72, 0.58, 0.26, 1.0) end
                    pin.activeDot:Hide()
                end
                pin:Show()
            end
        end
    end
end

function LFGFrameTab:AttachWorldMapButton()
    local mapFrame = _G.WorldMapFrame
    if self.mapHooked or not mapFrame then return end
    if ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled("M") then
        return
    end
    self.mapHooked = true

    local container = (mapFrame.ScrollContainer) or mapFrame
    local pill = CreateFrame("Button", "SocialCentralWorldMapBuffsPill", container, "BackdropTemplate")
    pill:SetSize(148, 26)
    pill:SetPoint("TOPRIGHT", container, "TOPRIGHT", -10, -10)
    pill:SetFrameLevel(math.max(MaxHierarchyLevel(container, 2) + 30, 2550))
    pill:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local solidBg = pill:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetAllPoints()
    solidBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    solidBg:SetVertexColor(0.06, 0.05, 0.04, 1.0)
    pill._solidOpaqueBg = solidBg

    if pill.SetBackdrop then
        pill:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 12, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        pill:SetBackdropColor(0.06, 0.05, 0.04, 1.0)
        pill:SetBackdropBorderColor(0.72, 0.58, 0.25, 1.0)
    end

    local pillBevel = pill:CreateTexture(nil, "BORDER", nil, 1)
    pillBevel:SetHeight(1)
    pillBevel:SetPoint("TOPLEFT", pill, "TOPLEFT", 6, -3)
    pillBevel:SetPoint("TOPRIGHT", pill, "TOPRIGHT", -6, -3)
    pillBevel:SetColorTexture(1.0, 0.86, 0.42, 0.28)
    pill._topBevel = pillBevel

    pill.emblem = pill:CreateTexture(nil, "ARTWORK")
    pill.emblem:SetSize(16, 16)
    pill.emblem:SetPoint("LEFT", pill, "LEFT", 6, 0)
    pill.emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pill.emblem:SetTexture(WORLD_BUFF_ICON_FALLBACK)

    pill.label = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pill.label:SetPoint("LEFT", pill.emblem, "RIGHT", 5, 0)
    pill.label:SetText(L["World Buffs"])

    local wbHelp = Theme:CreateHelpButton(
        pill,
        L["Help: World Buffs on World Map"],
        L["Displays an official-style summary badge and interactive zone pins for Classic/Forever World Buffs directly on the World Map."],
        L["Hover pins or the badge for live timers and cooldowns. Left-click to report in chat, Shift-click to open the full tracker, or Right-click the badge to toggle map pins."]
    )
    wbHelp:SetPoint("RIGHT", pill, "RIGHT", -4, 0)

    pill.miniIcons = {}
    for i = 1, 5 do
        local slot = CreateFrame("Frame", nil, pill)
        slot:SetSize(15, 15)
        if i == 1 then
            slot:SetPoint("RIGHT", wbHelp, "LEFT", -4, 0)
        else
            slot:SetPoint("RIGHT", pill.miniIcons[i - 1], "LEFT", -2, 0)
        end
        slot.border = slot:CreateTexture(nil, "BACKGROUND")
        slot.border:SetAllPoints()
        slot.border:SetTexture("Interface\\Buttons\\WHITE8X8")
        slot.border:SetVertexColor(0.24, 0.85, 0.42, 1.0)

        slot.tex = slot:CreateTexture(nil, "ARTWORK")
        slot.tex:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
        slot.tex:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
        slot.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot:Hide()
        pill.miniIcons[i] = slot
    end

    pill:SetScript("OnEnter", function(selfPill)
        ShowWorldBuffsPillTooltip(selfPill)
    end)
    pill:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    pill:SetScript("OnClick", function(selfPill, button)
        if button == "RightButton" then
            if ns.db and ns.db.settings then
                ns.db.settings.worldBuffsMapPins = not AreWorldMapPinsEnabled()
            end
            LFGFrameTab:RefreshWorldMapBuffs()
            ShowWorldBuffsPillTooltip(selfPill)
            if ns.Settings and ns.Settings.Refresh then
                ns.Settings:Refresh()
            end
            return
        end
        if IsShiftKeyDown and IsShiftKeyDown() then
            if ns.UI and ns.UI.ShowHub then
                ns.UI:ShowHub("buffs")
            end
            return
        end
        if ns.WorldBuffs and ns.WorldBuffs.OpenChatAnnouncement then
            ns.WorldBuffs:OpenChatAnnouncement()
        end
    end)

    local mapBuffRefreshPending = false
    local function ScheduleMapBuffRefresh()
        if not (_G.WorldMapFrame and _G.WorldMapFrame.IsShown and _G.WorldMapFrame:IsShown()) then
            return
        end
        if mapBuffRefreshPending then
            return
        end
        mapBuffRefreshPending = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                mapBuffRefreshPending = false
                if _G.WorldMapFrame and _G.WorldMapFrame.IsShown and _G.WorldMapFrame:IsShown() then
                    LFGFrameTab:RefreshWorldMapBuffs()
                end
            end)
        else
            mapBuffRefreshPending = false
            LFGFrameTab:RefreshWorldMapBuffs()
        end
    end

    if mapFrame.HookScript then
        mapFrame:HookScript("OnShow", ScheduleMapBuffRefresh)
        mapFrame:HookScript("OnHide", function()
            if LFGFrameTab.mapPins then
                for _, p in ipairs(LFGFrameTab.mapPins) do
                    p:Hide()
                end
            end
        end)
        mapFrame:HookScript("OnSizeChanged", ScheduleMapBuffRefresh)
    end
    local canvas = mapFrame.GetCanvas and mapFrame:GetCanvas()
    if canvas and canvas.HookScript then
        canvas:HookScript("OnSizeChanged", ScheduleMapBuffRefresh)
    end
    if hooksecurefunc then
        if type(mapFrame.OnMapChanged) == "function" then
            hooksecurefunc(mapFrame, "OnMapChanged", ScheduleMapBuffRefresh)
        end
        if type(mapFrame.SetMapID) == "function" then
            hooksecurefunc(mapFrame, "SetMapID", ScheduleMapBuffRefresh)
        end
        if mapFrame.BorderFrame and mapFrame.BorderFrame.MaximizeMinimizeFrame then
            local mm = mapFrame.BorderFrame.MaximizeMinimizeFrame
            if type(mm.Maximize) == "function" then
                hooksecurefunc(mm, "Maximize", ScheduleMapBuffRefresh)
            end
            if type(mm.Minimize) == "function" then
                hooksecurefunc(mm, "Minimize", ScheduleMapBuffRefresh)
            end
        end
    end

    self.mapPill = pill
    self:RefreshWorldMapBuffs()
end

local function SyncHostNativeTabs(parentFrame, scTab, isEmbeddedActive, namedKeys)
    if not parentFrame then return end
    local nativeTabs = DiscoverRightSideTabs(parentFrame, scTab, namedKeys)
    if isEmbeddedActive then
        for _, nt in ipairs(nativeTabs) do
            if nt.GetChecked then
                local ok, checked = pcall(nt.GetChecked, nt)
                if ok and checked then
                    parentFrame._scLastNativeTab = nt
                end
            end
            if nt.SetChecked then
                pcall(nt.SetChecked, nt, false)
            end
        end
    elseif parentFrame._scLastNativeTab then
        local anyChecked = false
        for _, nt in ipairs(nativeTabs) do
            if nt.GetChecked then
                local ok, checked = pcall(nt.GetChecked, nt)
                if ok and checked then
                    anyChecked = true
                    break
                end
            end
        end
        if not anyChecked and parentFrame._scLastNativeTab.SetChecked then
            pcall(parentFrame._scLastNativeTab.SetChecked, parentFrame._scLastNativeTab, true)
        end
        parentFrame._scLastNativeTab = nil
    end
end

local function OpenSocialUIModule(targetTab, fallbackToChatFrame, forceKeepOpen)
    local sf = _G.SocialUIFrame or _G.FriendsFrame
    if not (sf and sf:IsShown()) then
        if _G.ToggleFriendsFrame then
            pcall(_G.ToggleFriendsFrame, 1)
        end
        if not (sf and sf:IsShown()) and _G.ShowUIPanel and sf then
            pcall(_G.ShowUIPanel, sf)
        end
        if not (sf and sf:IsShown()) and sf and sf.Show then
            pcall(sf.Show, sf)
        end
    end
    local function ShowSoc()
        LFGFrameTab:AttachSocialUI()
        LFGFrameTab:EnsureSocialSideTab()
        local host = _G.SocialUIFrame or _G.FriendsFrame
        if host and host:IsShown() and ns.UI and ns.UI.OpenEmbedded then
            ns.UI:OpenEmbedded(host, { "watchlist", "social", "nearby", "chat" }, targetTab, forceKeepOpen ~= false)
        elseif ns.UI and ns.UI.ShowHub then
            ns.UI:ShowHub(targetTab)
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, ShowSoc) else ShowSoc() end
end

function LFGFrameTab:SyncAllEmbeddedTabStates()
    if self.socialTab then
        local socialHost = _G.SocialUIFrame or _G.FriendsFrame
        local shown = socialHost and socialHost.IsShown and socialHost:IsShown()
        local active = ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(socialHost)
        local socialUnread = ns.Chat and ((ns.Chat.GetUnreadDirectCount and ns.Chat:GetUnreadDirectCount()) or (ns.Chat.GetTotalUnread and ns.Chat:GetTotalUnread(false))) or 0
        if shown or active then
            UpdateSideTabVisual(self.socialTab, active)
            UpdateSideTabBadge(self.socialTab, socialUnread)
            if shown then
                SyncHostNativeTabs(socialHost, self.socialTab, active, nil)
            end
        end
    end
    if self.guildTab then
        local guildHost = _G.CommunitiesFrame or _G.GuildFrame
        local shown = guildHost and guildHost.IsShown and guildHost:IsShown()
        local active = ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(guildHost)
        local guildUnread = (ns.Clan and ns.Clan.GetNotificationCount and ns.Clan:GetNotificationCount()) or 0
        if shown or active then
            UpdateSideTabVisual(self.guildTab, active)
            UpdateSideTabBadge(self.guildTab, active and 0 or guildUnread)
            if shown then
                SyncHostNativeTabs(guildHost, self.guildTab, active, COMMUNITIES_NATIVE_TABS)
            end
        end
    end
    if self.charTab then
        local charHost = _G.CharacterFrame
        local shown = charHost and charHost.IsShown and charHost:IsShown()
        local active = ns.UI and ns.UI.IsEmbeddedFor and ns.UI:IsEmbeddedFor(charHost)
        if shown or active then
            UpdateSideTabVisual(self.charTab, active)
            if shown then
                SyncHostNativeTabs(charHost, self.charTab, active, { "Tab1", "Tab2", "Tab3", "Tab4" })
            end
        end
    end
    if self.mapPill and _G.WorldMapFrame and _G.WorldMapFrame.IsShown and _G.WorldMapFrame:IsShown() then
        self:RefreshWorldMapBuffs()
    end
end

function LFGFrameTab:OpenOfficialModule(moduleId, forceKeepOpen)
    if IsCombatLocked() then
        ns:Print("%s", L["Unavailable during combat."])
        return
    end
    local mod = (moduleId or ""):lower()

    if (mod == "clan" or mod == "diplomacy") and ns.Compat and ns.Compat.ShouldShowGuildFeatures and not ns.Compat.ShouldShowGuildFeatures() then
        ns:Print("%s", L["Your character is not currently in a guild."])
        return
    end
    if ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled(mod) then
        if mod == "lfg" then
            ns:Print("%s", L["Group Finder (I) integration is disabled in Settings."])
            return
        end
        if ns.UI and ns.UI.ShowHub then
            ns.UI:ShowHub(mod == "diplomacy" and "clan" or mod)
            return
        end
    end

    if mod == "lfg" then
        if not (_G.LFGParentFrame and _G.LFGParentFrame:IsShown()) then
            if _G.ToggleLFGParentFrame then
                pcall(_G.ToggleLFGParentFrame)
            elseif _G.LFGVanilla_ToggleFrame then
                pcall(_G.LFGVanilla_ToggleFrame)
            elseif _G.LFGVanilla_ShowFrame then
                pcall(_G.LFGVanilla_ShowFrame)
            end
        end
        local function ShowLfg()
            LFGFrameTab:AttachHooks()
            LFGFrameTab:EnsureSideTab()
            LFGFrameTab:ShowSubPanel()
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, ShowLfg) else ShowLfg() end
        return
    end

    if mod == "group" then
        if not (_G.LFGParentFrame and _G.LFGParentFrame:IsShown()) then
            if _G.ToggleLFGParentFrame then
                pcall(_G.ToggleLFGParentFrame)
            elseif _G.LFGVanilla_ToggleFrame then
                pcall(_G.LFGVanilla_ToggleFrame)
            end
        end
        local function ShowGrp()
            if LFGFrameTab.HideSubPanel then
                LFGFrameTab:HideSubPanel(false)
            end
            local h = _G.LFGParentFrame
            if h and h:IsShown() and ns.UI and ns.UI.OpenEmbedded then
                ns.UI:OpenEmbedded(h, { "group" }, "group")
            elseif ns.UI and ns.UI.ShowHub then
                ns.UI:ShowHub("group")
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, ShowGrp) else ShowGrp() end
        return
    end

    if mod == "watchlist" or mod == "social" or mod == "nearby" then
        OpenSocialUIModule(mod, false)
        return
    end

    if mod == "clan" or mod == "diplomacy" then
        if mod == "diplomacy" and ns.Clan and ns.Clan.SetPreferredRightView then
            ns.Clan:SetPreferredRightView("diplomacy")
        end
        local cf = _G.CommunitiesFrame or _G.GuildFrame
        if not (cf and cf:IsShown()) then
            if _G.ToggleGuildFrame then
                pcall(_G.ToggleGuildFrame)
            elseif _G.ToggleCommunitiesFrame then
                pcall(_G.ToggleCommunitiesFrame)
            end
        end
        local function ShowClan()
            LFGFrameTab:AttachCommunitiesUI()
            LFGFrameTab:EnsureGuildSideTab()
            local host = _G.CommunitiesFrame or _G.GuildFrame
            if host and host:IsShown() and ns.UI and ns.UI.OpenEmbedded then
                ns.UI:OpenEmbedded(host, { "clan" }, "clan", forceKeepOpen)
            elseif ns.UI and ns.UI.ShowHub then
                ns.UI:ShowHub("clan")
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, ShowClan) else ShowClan() end
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
        OpenSocialUIModule("chat", true, forceKeepOpen)
        return
    end

    if mod == "buffs" then
        if not (_G.WorldMapFrame and _G.WorldMapFrame:IsShown()) and _G.ToggleWorldMap then
            pcall(_G.ToggleWorldMap)
        end
        local function ShowBuffs()
            LFGFrameTab:AttachWorldMapButton()
            LFGFrameTab:RefreshWorldMapBuffs()
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, ShowBuffs) else ShowBuffs() end
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

    local function RefreshIfOpen()
        if LFGFrameTab.active and LFGFrameTab.subPanel and LFGFrameTab.subPanel:IsShown() then
            LFGFrameTab:RefreshData()
        end
    end

    ns:On("CLAN_UPDATED", RefreshIfOpen)
    ns:On("CLAN_DIPLOMACY_UPDATED", RefreshIfOpen)
    ns:On("SOCIAL_UPDATED", RefreshIfOpen)
    ns:On("WATCHLIST_UPDATED", RefreshIfOpen)
    local function SyncEmbeddedIfAnyHostShown()
        local socialHost = _G.SocialUIFrame or _G.FriendsFrame
        local guildHost = _G.CommunitiesFrame or _G.GuildFrame
        local charHost = _G.CharacterFrame
        local mapHost = _G.WorldMapFrame
        if (socialHost and socialHost.IsShown and socialHost:IsShown())
            or (guildHost and guildHost.IsShown and guildHost:IsShown())
            or (charHost and charHost.IsShown and charHost:IsShown())
            or (mapHost and mapHost.IsShown and mapHost:IsShown())
        then
            LFGFrameTab:SyncAllEmbeddedTabStates()
        end
    end

    ns:On("CHAT_UPDATED", SyncEmbeddedIfAnyHostShown)
    ns:On("CLAN_UPDATED", SyncEmbeddedIfAnyHostShown)
    ns:On("ADDON_MESSAGE_NOTIFY", SyncEmbeddedIfAnyHostShown)
    ns:On("WORLD_BUFFS_UPDATED", function()
        if _G.WorldMapFrame and _G.WorldMapFrame.IsShown and _G.WorldMapFrame:IsShown() then
            LFGFrameTab:RefreshWorldMapBuffs()
        end
    end)

    local tryAttachPending = false
    local function TryAttachAll()
        tryAttachPending = false
        LFGFrameTab:AttachHooks()
        LFGFrameTab:AttachSocialUI()
        LFGFrameTab:AttachCommunitiesUI()
        LFGFrameTab:AttachCharacterUI()
        LFGFrameTab:AttachWorldMapButton()
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
        if _G.WorldMapFrame and _G.WorldMapFrame:IsShown() then
            LFGFrameTab:RefreshWorldMapBuffs()
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
        then
            QueueTryAttachAll()
        end
    end)

    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
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
