local _, ns = ...

local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })
local Safe = ns.Safe
local Compat = ns.Compat
local Store = ns.Store

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local ICON_TEX = "Interface\\AddOns\\SocialCentral\\Media\\icon"
local STAR_TEX = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t"

local LFG = {
    askedByKey = {},
    _lastRoleCheckAt = 0,
}

ns.LFG = LFG
table.insert(ns.modules, LFG)

LFG.CLASSIC_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

LFG.PLAYSTYLES = {
    { key = "Learning", labelKey = "Learning", enumName = "Learning" },
    { key = "FunRelaxed", labelKey = "Relaxed", enumName = "FunRelaxed" },
    { key = "FunSerious", labelKey = "Competitive", enumName = "FunSerious" },
    { key = "Expert", labelKey = "Carry Offered", enumName = "Expert" },
}

LFG.SOLO_SORT_ORDERS = {
    { id = "newest", labelKey = "Newest First" },
    { id = "oldest", labelKey = "Oldest First" },
    { id = "level_desc", labelKey = "Highest Level" },
    { id = "level_asc", labelKey = "Lowest Level" },
    { id = "class", labelKey = "Class" },
}

local MAX_PRESETS = 24
local MAX_PRESET_NAME_LEN = 24

local function TrimText(txt)
    if type(txt) ~= "string" then return "" end
    return txt:match("^%s*(.-)%s*$") or ""
end

local function CopyBoolSet(src)
    local out = {}
    if type(src) == "table" then
        for k, v in pairs(src) do
            if type(k) == "string" and v == true then
                out[k] = true
            end
        end
    end
    return out
end

local function CountBoolSet(tbl)
    if type(tbl) ~= "table" then return 0 end
    local c = 0
    for _, v in pairs(tbl) do
        if v == true then c = c + 1 end
    end
    return c
end

local function EmitBrowseChanged()
    ns:Emit("LFG_BROWSE_STATE_CHANGED")
end

function LFG:GetCharState()
    if type(SocialCentralCharDB) ~= "table" then
        SocialCentralCharDB = {}
    end
    if type(SocialCentralCharDB.lfg) ~= "table" then
        SocialCentralCharDB.lfg = {}
    end
    local st = SocialCentralCharDB.lfg
    if type(st.favoriteActivities) ~= "table" then st.favoriteActivities = {} end
    if st.listingType ~= "ALL" and st.listingType ~= "GROUPS" and st.listingType ~= "SOLO" then
        st.listingType = "ALL"
    end
    if type(st.roleStates) ~= "table" then
        st.roleStates = { TANK = 0, HEALER = 0, DPS = 0 }
    end
    for _, r in ipairs({ "TANK", "HEALER", "DPS" }) do
        local v = tonumber(st.roleStates[r]) or 0
        if v ~= 0 and v ~= 1 and v ~= 2 then v = 0 end
        st.roleStates[r] = v
    end
    if type(st.groupExcludedClasses) ~= "table" then st.groupExcludedClasses = {} end
    if type(st.soloRoles) ~= "table" then
        st.soloRoles = { TANK = true, HEALER = true, DPS = true }
    else
        for _, r in ipairs({ "TANK", "HEALER", "DPS" }) do
            st.soloRoles[r] = (st.soloRoles[r] ~= false)
        end
    end
    if type(st.soloClasses) ~= "table" then st.soloClasses = {} end
    st.soloMinLevel = math.max(0, math.min(999, math.floor(tonumber(st.soloMinLevel) or 0)))
    st.soloMaxLevel = math.max(0, math.min(999, math.floor(tonumber(st.soloMaxLevel) or 0)))
    if st.soloSortOrder ~= "newest" and st.soloSortOrder ~= "oldest"
        and st.soloSortOrder ~= "level_desc" and st.soloSortOrder ~= "level_asc"
        and st.soloSortOrder ~= "class"
    then
        st.soloSortOrder = "newest"
    end
    if type(st.playstyles) ~= "table" then st.playstyles = {} end
    if type(st.languages) ~= "table" then st.languages = {} end
    return st
end

function LFG:GetMyClassFile()
    local _, cf = Safe.Call(UnitClass, "player")
    return Safe.String(cf)
end

function LFG:GetClassName(classFile)
    if type(classFile) ~= "string" or classFile == "" then return "?" end
    local loc = _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[classFile]
    if type(loc) == "string" and loc ~= "" then
        return loc
    end
    return classFile:sub(1, 1) .. classFile:sub(2):lower()
end

function LFG:GetPlaystyleEnumValue(key)
    local gp = _G.Enum and _G.Enum.LFGEntryGeneralPlaystyle
    if not gp then return nil end
    return gp[key]
end

function LFG:GetPlaystyleLabel(key)
    local val = self:GetPlaystyleEnumValue(key)
    if val ~= nil and type(_G.GetGeneralPlaystyleString) == "function" then
        local ok, txt = pcall(_G.GetGeneralPlaystyleString, val)
        if ok and type(txt) == "string" and txt ~= "" then
            return txt
        end
    end
    for _, ps in ipairs(LFG.PLAYSTYLES) do
        if ps.key == key then
            return L[ps.labelKey]
        end
    end
    return tostring(key or "")
end

function LFG:ResolvePlaystyle(enumVal)
    local val = Safe.Number(enumVal)
    if not val or val <= 0 then return nil, nil end
    local gp = _G.Enum and _G.Enum.LFGEntryGeneralPlaystyle
    local matchedKey = nil
    if gp then
        for _, ps in ipairs(LFG.PLAYSTYLES) do
            if gp[ps.enumName] == val then
                matchedKey = ps.key
                break
            end
        end
    end
    local lbl = nil
    if type(_G.GetGeneralPlaystyleString) == "function" then
        local ok, txt = pcall(_G.GetGeneralPlaystyleString, val)
        if ok and type(txt) == "string" and txt ~= "" then
            lbl = txt
        end
    end
    if (not lbl or lbl == "") and matchedKey then
        lbl = self:GetPlaystyleLabel(matchedKey)
    end
    return matchedKey, lbl
end

function LFG:GetLanguageLabel(code)
    if type(code) ~= "string" or code == "" then return "?" end
    local up = code:upper()
    local candidates = {
        "LFG_LIST_LANGUAGE_" .. up,
        "LOCALE_DISPLAY_NAME_" .. up,
        up,
    }
    if up == "ENGB" then
        candidates[#candidates + 1] = "LFG_LIST_LANGUAGE_ENUS"
    elseif up == "PTPT" then
        candidates[#candidates + 1] = "LFG_LIST_LANGUAGE_PTBR"
    end
    for _, gName in ipairs(candidates) do
        local gVal = _G[gName]
        if type(gVal) == "string" and gVal ~= "" then
            return gVal
        end
    end
    return up
end

function LFG:GetAvailableLanguages()
    local out, seen = {}, {}
    if not (C_LFGList and C_LFGList.GetAvailableLanguageSearchFilter) then
        return out
    end
    local ok, raw = pcall(C_LFGList.GetAvailableLanguageSearchFilter)
    if not (ok and type(raw) == "table") then
        return out
    end
    for _, code in ipairs(raw) do
        local c = Safe.String(code)
        if c and c ~= "" and not seen[c] then
            seen[c] = true
            out[#out + 1] = c
        end
    end
    return out
end

function LFG:GetLockedLanguages()
    local locked = {}
    if not (C_LFGList and C_LFGList.GetDefaultLanguageSearchFilter) then
        return locked
    end
    local ok, raw = pcall(C_LFGList.GetDefaultLanguageSearchFilter)
    if ok and type(raw) == "table" then
        for code, val in pairs(raw) do
            if type(code) == "string" and val == true then
                locked[code] = true
            end
        end
    end
    return locked
end

function LFG:IsLanguageSelected(code)
    local locked = self:GetLockedLanguages()
    if locked[code] then return true end
    local st = self:GetCharState()
    return st.languages[code] == true
end

function LFG:ToggleLanguage(code)
    local locked = self:GetLockedLanguages()
    if locked[code] then return false end
    local st = self:GetCharState()
    if st.languages[code] then
        st.languages[code] = nil
    else
        st.languages[code] = true
    end
    EmitBrowseChanged()
    return true
end

function LFG:SetAllLanguages(selectAll)
    local st = self:GetCharState()
    local offered = self:GetAvailableLanguages()
    local locked = self:GetLockedLanguages()
    for _, code in ipairs(offered) do
        if not locked[code] then
            st.languages[code] = selectAll and true or nil
        end
    end
    EmitBrowseChanged()
end

function LFG:BuildLanguageSearchFilter()
    local st = self:GetCharState()
    local offered = self:GetAvailableLanguages()
    if #offered == 0 then
        return nil
    end
    local locked = self:GetLockedLanguages()
    local hasNonDefault = false
    local filter = {}
    for _, code in ipairs(offered) do
        if locked[code] then
            filter[code] = true
        elseif st.languages[code] == true then
            filter[code] = true
            hasNonDefault = true
        end
    end
    if not hasNonDefault then
        return nil
    end
    return filter
end

function LFG:GetPrimarySpecName()
    if GetSpecialization and GetSpecializationInfo then
        local specIdx = Safe.Number(Safe.Call(GetSpecialization))
        if specIdx and specIdx > 0 then
            local ok, _, sName = pcall(GetSpecializationInfo, specIdx)
            local clean = ok and Safe.String(sName) or nil
            if clean and clean ~= "" then
                return clean
            end
        end
    end
    if GetNumTalentTabs and GetTalentTabInfo then
        local numTabs = Safe.Number(Safe.Call(GetNumTalentTabs)) or 0
        local bestPts, bestTabName = 0, ""
        for t = 1, numTabs do
            local okT, tName, _, ptsSpent = pcall(GetTalentTabInfo, t)
            if okT then
                local cleanName = Safe.String(tName)
                local pts = Safe.Number(ptsSpent) or 0
                if pts > bestPts and cleanName and cleanName ~= "" then
                    bestPts = pts
                    bestTabName = cleanName
                end
            end
        end
        if bestPts > 0 and bestTabName ~= "" then
            return bestTabName
        end
    end
    if C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup and C_SpecializationInfo.GetCombatConfigIDForSpecGroup and C_Traits then
        local specGroup = Safe.Number(Safe.Call(C_SpecializationInfo.GetActiveSpecGroup))
        local configID = specGroup and Safe.Number(Safe.Call(C_SpecializationInfo.GetCombatConfigIDForSpecGroup, specGroup))
        local cfg = configID and C_Traits.GetConfigInfo and Safe.Call(C_Traits.GetConfigInfo, configID)
        local treeID = (type(cfg) == "table" and type(cfg.treeIDs) == "table") and Safe.Number(cfg.treeIDs[1])
        local dispInfos = (treeID and C_Traits.GetGroupDisplayInfoByTreeID) and Safe.Call(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
        if type(dispInfos) == "table" and #dispInfos > 0 and C_Traits.GetGroupCurrencyInfo then
            local gids = {}
            for _, d in ipairs(dispInfos) do
                if type(d) == "table" and d.groupID then
                    gids[#gids + 1] = d.groupID
                end
            end
            local curInfos = (#gids > 0) and Safe.Call(C_Traits.GetGroupCurrencyInfo, configID, gids)
            local spentByGid = {}
            if type(curInfos) == "table" then
                for _, ci in ipairs(curInfos) do
                    local c1 = type(ci) == "table" and type(ci.currencyInfos) == "table" and ci.currencyInfos[1]
                    if ci.traitNodeGroupID and type(c1) == "table" then
                        spentByGid[ci.traitNodeGroupID] = Safe.Number(c1.spent) or 0
                    end
                end
            end
            local bestName, bestSpent = "", 0
            for _, d in ipairs(dispInfos) do
                if type(d) == "table" and d.groupID then
                    local sp = spentByGid[d.groupID] or 0
                    if sp > bestSpent and type(d.displayName) == "string" and d.displayName ~= "" then
                        bestSpent = sp
                        bestName = Safe.String(d.displayName) or ""
                    end
                end
            end
            return bestName
        end
    end
    return ""
end

local function FavoriteKeyFor(key, officialId)
    local nid = Safe.Number(officialId)
    if nid and nid > 0 then
        return "off_" .. tostring(nid), nid
    end
    if type(key) == "string" and key ~= "" then
        return key, nil
    end
    return nil, nil
end

function LFG:IsFavoriteActivity(key, officialId)
    local st = self:GetCharState()
    local favs = st.favoriteActivities
    local fKey, nid = FavoriteKeyFor(key, officialId)
    if fKey and favs[fKey] == true then return true end
    if key and favs[key] == true then return true end
    if nid and favs[nid] == true then return true end
    return false
end

function LFG:ToggleFavoriteActivity(key, officialId)
    local st = self:GetCharState()
    local favs = st.favoriteActivities
    local fKey, nid = FavoriteKeyFor(key, officialId)
    if not fKey then return false end
    local was = self:IsFavoriteActivity(key, officialId)
    if was then
        favs[fKey] = nil
        if key then favs[key] = nil end
        if nid then favs[nid] = nil end
    else
        favs[fKey] = true
    end
    EmitBrowseChanged()
    return not was
end

function LFG:AskKeyFor(item)
    if not item then return nil end
    local pg = Safe.String(item.partyGUID)
    if pg and pg ~= "" then return "pg:" .. pg end
    if type(item.lookupKey) == "string" and item.lookupKey ~= "" then
        return "lk:" .. item.lookupKey
    end
    return nil
end

function LFG:MarkAsked(item)
    local k = self:AskKeyFor(item)
    if not k then return end
    self.askedByKey[k] = true
    if type(item.lookupKey) == "string" and item.lookupKey ~= "" then
        self.askedByKey["lk:" .. item.lookupKey] = true
    end
    EmitBrowseChanged()
end

function LFG:IsAsked(item)
    if not item or item.isSelf then return false end
    local pg = Safe.String(item.partyGUID)
    if pg and pg ~= "" and self.askedByKey["pg:" .. pg] == true then
        return true
    end
    if type(item.lookupKey) == "string" and item.lookupKey ~= "" and self.askedByKey["lk:" .. item.lookupKey] == true then
        return true
    end
    return false
end

local function ClearLegacyBrowseRoleFilter()
    if ns.LFGFrameTab and ns.LFGFrameTab.roleFilter and ns.LFGFrameTab.roleFilter ~= "ALL" then
        ns.LFGFrameTab.roleFilter = "ALL"
    end
    if ns.db and ns.db.settings then
        if ns.db.settings.lfgBrowseRole and ns.db.settings.lfgBrowseRole ~= "ALL" then
            ns.db.settings.lfgBrowseRole = "ALL"
        end
        if ns.db.settings.lfgBrowseRoleV2 and ns.db.settings.lfgBrowseRoleV2 ~= "ALL" then
            ns.db.settings.lfgBrowseRoleV2 = "ALL"
        end
    end
end

function LFG:GetListingType()
    return self:GetCharState().listingType
end

function LFG:SetListingType(kind)
    if kind ~= "ALL" and kind ~= "GROUPS" and kind ~= "SOLO" then kind = "ALL" end
    self:GetCharState().listingType = kind
    if kind == "SOLO" then
        ClearLegacyBrowseRoleFilter()
    end
    EmitBrowseChanged()
end

function LFG:GetRoleState(role)
    return self:GetCharState().roleStates[role] or 0
end

function LFG:SetRoleState(role, val)
    if role ~= "TANK" and role ~= "HEALER" and role ~= "DPS" then return end
    val = (val == 1 or val == 2) and val or 0
    self:GetCharState().roleStates[role] = val
    ClearLegacyBrowseRoleFilter()
    EmitBrowseChanged()
end

function LFG:CycleRoleState(role)
    local cur = self:GetRoleState(role)
    self:SetRoleState(role, (cur + 1) % 3)
end

function LFG:IsGroupClassExcluded(classFile)
    return self:GetCharState().groupExcludedClasses[classFile] == true
end

function LFG:ToggleGroupClassExcluded(classFile)
    local st = self:GetCharState()
    st.groupExcludedClasses[classFile] = not (st.groupExcludedClasses[classFile] == true) and true or nil
    EmitBrowseChanged()
end

function LFG:ClearGroupClassExcluded()
    wipe(self:GetCharState().groupExcludedClasses)
    EmitBrowseChanged()
end

function LFG:GetSoloRoleAllowed(roleKey)
    local sr = self:GetCharState().soloRoles
    return sr and (sr[roleKey] ~= false) or false
end

function LFG:SetSoloRoleAllowed(roleKey, allowed)
    if roleKey ~= "TANK" and roleKey ~= "HEALER" and roleKey ~= "DPS" then return end
    self:GetCharState().soloRoles[roleKey] = (allowed == true)
    ClearLegacyBrowseRoleFilter()
    EmitBrowseChanged()
end

function LFG:ToggleSoloRoleAllowed(roleKey)
    self:SetSoloRoleAllowed(roleKey, not self:GetSoloRoleAllowed(roleKey))
end

local function CountSelectedSoloClasses()
    local c = 0
    for _, cf in ipairs(LFG.CLASSIC_CLASSES) do
        if LFG:IsSoloClassSelected(cf) then
            c = c + 1
        end
    end
    return c
end

local function FirstSelectedSoloClass()
    for _, cf in ipairs(LFG.CLASSIC_CLASSES) do
        if LFG:IsSoloClassSelected(cf) then
            return cf
        end
    end
    return nil
end

local function SnapshotSoloClasses(st)
    local out = {}
    for _, cf in ipairs(LFG.CLASSIC_CLASSES) do
        out[cf] = (not st.soloClasses) or (st.soloClasses[cf] ~= false)
    end
    return out
end

local function RestoreSoloClassesFromPreset(srcClasses)
    local out = {}
    if type(srcClasses) ~= "table" or next(srcClasses) == nil then
        return out
    end
    local hasFalse = false
    for _, v in pairs(srcClasses) do
        if v == false then
            hasFalse = true
            break
        end
    end
    if hasFalse then
        for _, cf in ipairs(LFG.CLASSIC_CLASSES) do
            out[cf] = (srcClasses[cf] ~= false)
        end
    else
        for _, cf in ipairs(LFG.CLASSIC_CLASSES) do
            out[cf] = (srcClasses[cf] == true)
        end
    end
    return out
end

function LFG:IsSoloClassSelected(classFile)
    local sc = self:GetCharState().soloClasses
    if not sc then return true end
    return sc[classFile] ~= false
end

function LFG:ToggleSoloClass(classFile)
    local st = self:GetCharState()
    st.soloClasses[classFile] = not self:IsSoloClassSelected(classFile)
    EmitBrowseChanged()
end

function LFG:SetAllSoloClasses(flag)
    local st = self:GetCharState()
    local on = (flag == true)
    for _, cf in ipairs(LFG.CLASSIC_CLASSES) do
        st.soloClasses[cf] = on
    end
    EmitBrowseChanged()
end

local SOLO_ARCHETYPE_CLASSES = {
    TANKS = { WARRIOR = true, PALADIN = true, DRUID = true },
    HEALERS = { PRIEST = true, PALADIN = true, SHAMAN = true, DRUID = true },
    CASTERS = { MAGE = true, WARLOCK = true, PRIEST = true, SHAMAN = true, DRUID = true },
    MELEE = { WARRIOR = true, ROGUE = true, HUNTER = true, PALADIN = true, SHAMAN = true, DRUID = true },
}

function LFG:SetSoloClassesArchetype(archetypeId)
    if archetypeId == "ALL" then
        self:SetAllSoloClasses(true)
        return
    elseif archetypeId == "NONE" then
        self:SetAllSoloClasses(false)
        return
    end
    local tbl = SOLO_ARCHETYPE_CLASSES[archetypeId]
    if not tbl then return end
    local st = self:GetCharState()
    for _, cf in ipairs(LFG.CLASSIC_CLASSES) do
        st.soloClasses[cf] = (tbl[cf] == true)
    end
    EmitBrowseChanged()
end

function LFG:GetSoloLevelRange()
    local st = self:GetCharState()
    return st.soloMinLevel or 0, st.soloMaxLevel or 0
end

function LFG:SetSoloLevelRange(minL, maxL)
    local st = self:GetCharState()
    local lo = math.max(0, math.min(999, math.floor(tonumber(minL) or 0)))
    local hi = math.max(0, math.min(999, math.floor(tonumber(maxL) or 0)))
    if lo > 0 and hi > 0 and lo > hi then
        lo = hi
    end
    st.soloMinLevel = lo
    st.soloMaxLevel = hi
    EmitBrowseChanged()
end

function LFG:ApplyRelativeSoloLevelRange(delta)
    local d = tonumber(delta) or 0
    if d <= 0 then
        self:SetSoloLevelRange(0, 0)
        return
    end
    local lvl = Safe.Number(Safe.Call(UnitLevel, "player")) or 60
    self:SetSoloLevelRange(math.max(1, lvl - d), math.min(255, lvl + d))
end

function LFG:GetSoloSortOrder()
    return self:GetCharState().soloSortOrder or "newest"
end

function LFG:SetSoloSortOrder(orderId)
    self:GetCharState().soloSortOrder = orderId or "newest"
    EmitBrowseChanged()
end

function LFG:IsPlaystyleSelected(key)
    return self:GetCharState().playstyles[key] == true
end

function LFG:TogglePlaystyle(key)
    local st = self:GetCharState()
    st.playstyles[key] = not (st.playstyles[key] == true) and true or nil
    EmitBrowseChanged()
end

function LFG:ResetAdvancedFilters()
    local st = self:GetCharState()
    st.listingType = "ALL"
    st.roleStates = { TANK = 0, HEALER = 0, DPS = 0 }
    wipe(st.groupExcludedClasses)
    st.soloRoles = { TANK = true, HEALER = true, DPS = true }
    wipe(st.soloClasses)
    st.soloMinLevel = 0
    st.soloMaxLevel = 0
    st.soloSortOrder = "newest"
    wipe(st.playstyles)
    wipe(st.languages)
    ClearLegacyBrowseRoleFilter()
    EmitBrowseChanged()
end

local function SnapshotPresetState(st)
    return {
        listingType = st.listingType or "ALL",
        roleStates = {
            TANK = st.roleStates and st.roleStates.TANK or 0,
            HEALER = st.roleStates and st.roleStates.HEALER or 0,
            DPS = st.roleStates and st.roleStates.DPS or 0,
        },
        groupExcludedClasses = CopyBoolSet(st.groupExcludedClasses),
        soloRoles = {
            TANK = (not st.soloRoles) or (st.soloRoles.TANK ~= false),
            HEALER = (not st.soloRoles) or (st.soloRoles.HEALER ~= false),
            DPS = (not st.soloRoles) or (st.soloRoles.DPS ~= false),
        },
        soloClasses = SnapshotSoloClasses(st),
        soloMinLevel = st.soloMinLevel or 0,
        soloMaxLevel = st.soloMaxLevel or 0,
        soloSortOrder = st.soloSortOrder or "newest",
        playstyles = CopyBoolSet(st.playstyles),
        languages = CopyBoolSet(st.languages),
    }
end

function LFG:GetPresets()
    local raw = ns.db and ns.db.lfgPresets
    local out, seen = {}, {}
    if type(raw) ~= "table" then return out end
    for _, p in ipairs(raw) do
        if type(p) == "table" and type(p.name) == "string" and type(p.state) == "table" then
            local nm = TrimText(p.name)
            if nm ~= "" and not seen[nm] then
                seen[nm] = true
                out[#out + 1] = { name = nm, state = p.state }
            end
        end
    end
    return out
end

function LFG:SavePreset(rawName)
    local name = TrimText(rawName)
    if name == "" then return false, "empty" end
    local len = strlenutf8 and strlenutf8(name) or #name
    if len > MAX_PRESET_NAME_LEN then return false, "long" end
    local list = self:GetPresets()
    local exists = false
    for idx, p in ipairs(list) do
        if p.name == name then
            table.remove(list, idx)
            exists = true
            break
        end
    end
    if not exists and #list >= MAX_PRESETS then
        return false, "full"
    end
    list[#list + 1] = { name = name, state = SnapshotPresetState(self:GetCharState()) }
    if ns.db then
        ns.db.lfgPresets = list
    end
    EmitBrowseChanged()
    return true, exists
end

function LFG:ApplyPreset(name)
    for _, p in ipairs(self:GetPresets()) do
        if p.name == name then
            local st = self:GetCharState()
            local src = p.state
            st.listingType = (src.listingType == "GROUPS" or src.listingType == "SOLO") and src.listingType or "ALL"
            st.roleStates = {
                TANK = src.roleStates and (tonumber(src.roleStates.TANK) or 0) or 0,
                HEALER = src.roleStates and (tonumber(src.roleStates.HEALER) or 0) or 0,
                DPS = src.roleStates and (tonumber(src.roleStates.DPS) or 0) or 0,
            }
            st.groupExcludedClasses = CopyBoolSet(src.groupExcludedClasses)
            st.soloRoles = {
                TANK = (not src.soloRoles) or (src.soloRoles.TANK ~= false),
                HEALER = (not src.soloRoles) or (src.soloRoles.HEALER ~= false),
                DPS = (not src.soloRoles) or (src.soloRoles.DPS ~= false),
            }
            st.soloClasses = RestoreSoloClassesFromPreset(src.soloClasses)
            st.soloMinLevel = tonumber(src.soloMinLevel) or 0
            st.soloMaxLevel = tonumber(src.soloMaxLevel) or 0
            st.soloSortOrder = src.soloSortOrder or "newest"
            st.playstyles = CopyBoolSet(src.playstyles)
            st.languages = CopyBoolSet(src.languages)
            EmitBrowseChanged()
            return true
        end
    end
    return false
end

function LFG:DeletePreset(name)
    local list = self:GetPresets()
    for idx, p in ipairs(list) do
        if p.name == name then
            table.remove(list, idx)
            if ns.db then ns.db.lfgPresets = list end
            EmitBrowseChanged()
            return true
        end
    end
    return false
end

local function SoloOffersRole(item, roleKey)
    if type(item.soloRoles) == "table" and (item.soloRoles.TANK or item.soloRoles.HEALER or item.soloRoles.DPS) then
        return item.soloRoles[roleKey] == true
    end
    if item.role == "TANK" or item.role == "HEALER" or item.role == "DPS" then
        return item.role == roleKey
    end
    return true
end

function LFG:MatchesAdvancedFilters(item)
    if not item then return false end
    if item.isSelf then return true end
    local st = self:GetCharState()
    local isSolo = (item.mode == "LFG" and item.sourceType ~= "EVENT")

    if st.listingType == "GROUPS" and isSolo then
        return false
    elseif st.listingType == "SOLO" and not isSolo then
        return false
    end

    local rs = st.roleStates
    if isSolo then
        local sr = st.soloRoles or { TANK = true, HEALER = true, DPS = true }
        local allowT = (sr.TANK ~= false)
        local allowH = (sr.HEALER ~= false)
        local allowD = (sr.DPS ~= false)
        if not (allowT and allowH and allowD) then
            if not (allowT or allowH or allowD) then
                return false
            end
            local okRole = false
            if allowT and SoloOffersRole(item, "TANK") then okRole = true end
            if not okRole and allowH and SoloOffersRole(item, "HEALER") then okRole = true end
            if not okRole and allowD and SoloOffersRole(item, "DPS") then okRole = true end
            if not okRole then return false end
        end

        local sClsCnt = CountSelectedSoloClasses()
        if sClsCnt == 0 then
            return false
        elseif sClsCnt < #LFG.CLASSIC_CLASSES and item.classFile and item.classFile ~= "" then
            if not self:IsSoloClassSelected(item.classFile) then
                return false
            end
        end

        local minL = st.soloMinLevel or 0
        local maxL = st.soloMaxLevel or 0
        if minL > 0 and maxL > 0 and minL > maxL then minL = maxL end
        local pLvl = Safe.Number(item.level)
        if pLvl and pLvl > 0 then
            if minL > 0 and pLvl < minL then return false end
            if maxL > 0 and pLvl > maxL then return false end
        end
    else
        local maxM = Safe.Number(item.maxMembers) or ((item.categoryKind == "RAIDS") and 40 or 5)
        local isRaidGroup = maxM > 5
        local hasStructuredCounts = (item.filledT ~= nil or item.filledH ~= nil or item.filledD ~= nil)
        local hasNeeds = (item.needT ~= nil or item.needH ~= nil or item.needD ~= nil)
        local rolePairs = {
            { rk = "TANK", filled = item.filledT, need = item.needT },
            { rk = "HEALER", filled = item.filledH, need = item.needH },
            { rk = "DPS", filled = item.filledD, need = item.needD },
        }
        for _, rp in ipairs(rolePairs) do
            local want = rs[rp.rk] or 0
            if want == 1 then
                if isRaidGroup then
                    if hasNeeds and rp.need ~= nil then
                        if (rp.need or 0) <= 0 then return false end
                    elseif item.numMembers and maxM > 0 and item.numMembers >= maxM then
                        return false
                    end
                elseif hasNeeds and rp.need ~= nil then
                    if (rp.need or 0) <= 0 then return false end
                elseif hasStructuredCounts and rp.filled ~= nil then
                    local cap = (rp.rk == "DPS") and 3 or 1
                    if (rp.filled or 0) >= cap then return false end
                end
            elseif want == 2 then
                if hasStructuredCounts and rp.filled ~= nil then
                    if (rp.filled or 0) < 1 then return false end
                end
            end
        end

        local exCnt = CountBoolSet(st.groupExcludedClasses)
        if exCnt > 0 and exCnt < #LFG.CLASSIC_CLASSES then
            if type(item.memberClassSet) == "table" and next(item.memberClassSet) ~= nil then
                for cf, excluded in pairs(st.groupExcludedClasses) do
                    if excluded and item.memberClassSet[cf] == true then
                        return false
                    end
                end
            elseif item.classFile and item.classFile ~= "" and st.groupExcludedClasses[item.classFile] == true then
                return false
            end
        end
    end

    local psCnt = CountBoolSet(st.playstyles)
    if psCnt > 0 and psCnt < #LFG.PLAYSTYLES and item.playstyleKey and item.playstyleKey ~= "" then
        if st.playstyles[item.playstyleKey] ~= true then
            return false
        end
    end

    return true
end

function LFG:CountActiveAdvancedFilters()
    local st = self:GetCharState()
    local n = 0
    if st.listingType ~= "ALL" then n = n + 1 end
    for _, rk in ipairs({ "TANK", "HEALER", "DPS" }) do
        if (st.roleStates[rk] or 0) > 0 then n = n + 1 end
    end
    local exCnt = CountBoolSet(st.groupExcludedClasses)
    if exCnt > 0 and exCnt < #LFG.CLASSIC_CLASSES then n = n + 1 end
    local sr = st.soloRoles or {}
    local srCount = (sr.TANK ~= false and 1 or 0) + (sr.HEALER ~= false and 1 or 0) + (sr.DPS ~= false and 1 or 0)
    if srCount < 3 then n = n + 1 end
    local scCnt = CountSelectedSoloClasses()
    if scCnt < #LFG.CLASSIC_CLASSES then n = n + 1 end
    if (st.soloMinLevel or 0) > 0 or (st.soloMaxLevel or 0) > 0 then n = n + 1 end
    local psCnt = CountBoolSet(st.playstyles)
    if psCnt > 0 and psCnt < #LFG.PLAYSTYLES then n = n + 1 end
    if self:BuildLanguageSearchFilter() ~= nil then n = n + 1 end
    return n
end

function LFG:GetActiveFilterChips()
    local st = self:GetCharState()
    local chips = {}
    if st.listingType == "GROUPS" then
        chips[#chips + 1] = {
            id = "type",
            label = L["Groups Only"],
            onClear = function() LFG:SetListingType("ALL") end,
        }
    elseif st.listingType == "SOLO" then
        chips[#chips + 1] = {
            id = "type",
            label = L["Looking (LFG)"],
            onClear = function() LFG:SetListingType("ALL") end,
        }
    end
    for _, rInfo in ipairs({
        { k = "TANK", lbl = L["Tank"] },
        { k = "HEALER", lbl = L["Healer"] },
        { k = "DPS", lbl = L["DPS"] },
    }) do
        local v = st.roleStates[rInfo.k] or 0
        if v == 1 then
            local rk = rInfo.k
            chips[#chips + 1] = {
                id = "role_" .. rk,
                label = "+ " .. rInfo.lbl,
                onClear = function() LFG:SetRoleState(rk, 0) end,
            }
        elseif v == 2 then
            local rk = rInfo.k
            chips[#chips + 1] = {
                id = "role_" .. rk,
                label = "= " .. rInfo.lbl,
                onClear = function() LFG:SetRoleState(rk, 0) end,
            }
        end
    end
    local exCnt = CountBoolSet(st.groupExcludedClasses)
    if exCnt > 0 and exCnt < #LFG.CLASSIC_CLASSES then
        local myCf = self:GetMyClassFile()
        local lbl
        if exCnt == 1 and myCf and st.groupExcludedClasses[myCf] then
            lbl = L["No %s"]:format(self:GetClassName(myCf))
        elseif exCnt == 1 then
            local onlyCf = next(st.groupExcludedClasses)
            lbl = L["No %s"]:format(self:GetClassName(onlyCf))
        else
            lbl = L["No %d classes"]:format(exCnt)
        end
        chips[#chips + 1] = {
            id = "excl",
            label = lbl,
            onClear = function() LFG:ClearGroupClassExcluded() end,
        }
    end
    local sr = st.soloRoles or {}
    local srT, srH, srD = (sr.TANK ~= false), (sr.HEALER ~= false), (sr.DPS ~= false)
    if not (srT and srH and srD) then
        local roleNames = {}
        if srT then roleNames[#roleNames + 1] = L["Tank"] end
        if srH then roleNames[#roleNames + 1] = L["Heal"] end
        if srD then roleNames[#roleNames + 1] = L["DPS"] end
        chips[#chips + 1] = {
            id = "solo_roles",
            label = (#roleNames > 0) and L["LFG: %s"]:format(table.concat(roleNames, "/")) or L["LFG: None"],
            onClear = function()
                local curSr = LFG:GetCharState().soloRoles
                curSr.TANK, curSr.HEALER, curSr.DPS = true, true, true
                EmitBrowseChanged()
            end,
        }
    end
    local scCnt = CountSelectedSoloClasses()
    if scCnt < #LFG.CLASSIC_CLASSES then
        local lbl
        if scCnt == 0 then
            lbl = L["LFG: No classes"]
        elseif scCnt == 1 then
            lbl = L["LFG: %s"]:format(self:GetClassName(FirstSelectedSoloClass()))
        else
            lbl = L["LFG: %d classes"]:format(scCnt)
        end
        chips[#chips + 1] = {
            id = "solo_cls",
            label = lbl,
            onClear = function() LFG:SetAllSoloClasses(true) end,
        }
    end
    local minL, maxL = self:GetSoloLevelRange()
    if minL > 0 or maxL > 0 then
        local lbl = (minL > 0 and maxL > 0) and string.format("%s %d-%d", L["Lv"], minL, maxL)
            or (minL > 0 and string.format("%s %d+", L["Lv"], minL) or string.format("%s <=%d", L["Lv"], maxL))
        chips[#chips + 1] = {
            id = "solo_lvl",
            label = lbl,
            onClear = function() LFG:SetSoloLevelRange(0, 0) end,
        }
    end
    local psCnt = CountBoolSet(st.playstyles)
    if psCnt > 0 and psCnt < #LFG.PLAYSTYLES then
        local lbl = (psCnt == 1) and self:GetPlaystyleLabel(next(st.playstyles)) or L["%d playstyles"]:format(psCnt)
        chips[#chips + 1] = {
            id = "playstyle",
            label = lbl,
            onClear = function()
                wipe(LFG:GetCharState().playstyles)
                EmitBrowseChanged()
            end,
        }
    end
    if self:BuildLanguageSearchFilter() ~= nil then
        local extraLangs = {}
        local locked = self:GetLockedLanguages()
        for code, v in pairs(st.languages) do
            if v and not locked[code] then
                extraLangs[#extraLangs + 1] = code
            end
        end
        chips[#chips + 1] = {
            id = "langs",
            label = L["+%d lang"]:format(#extraLangs),
            onClear = function() LFG:SetAllLanguages(false) end,
        }
    end
    return chips
end

local function ItemRelationWeight(item)
    if item.isSelf then return 0 end
    if item._isAvoidFlag or item.hasAvoidSignup or item.isEnemyGuild then return 90 end
    if item.isFriend or item.isWatchlist or item.hasFriendOrWatchlistSignup then return 10 end
    if item.isClan then return 20 end
    if item.isAllied then return 30 end
    if item._isGoodFlag or item.hasGoodPartnerSignup or item.isCompanion then return 40 end
    return 50
end

function LFG:SortRows(rows)
    if type(rows) ~= "table" or #rows <= 1 then return rows end
    local soloOrder = self:GetSoloSortOrder()
    table.sort(rows, function(a, b)
        local wa, wb = ItemRelationWeight(a), ItemRelationWeight(b)
        if wa ~= wb then return wa < wb end
        local aSolo = (a.mode == "LFG" and a.sourceType ~= "EVENT")
        local bSolo = (b.mode == "LFG" and b.sourceType ~= "EVENT")
        if aSolo ~= bSolo then
            return not aSolo
        end
        if aSolo and bSolo then
            if soloOrder == "oldest" then
                local oa, ob = a.searchOrder or 0, b.searchOrder or 0
                if oa ~= ob then return oa > ob end
                local ua, ub = a.updatedAt or 0, b.updatedAt or 0
                if ua ~= ub then return ua < ub end
            elseif soloOrder == "level_desc" then
                local la, lb = a.level or 0, b.level or 0
                if la ~= lb then return la > lb end
                local ua, ub = a.updatedAt or 0, b.updatedAt or 0
                if ua ~= ub then return ua > ub end
            elseif soloOrder == "level_asc" then
                local la, lb = a.level or 999, b.level or 999
                if la ~= lb then return la < lb end
                local ua, ub = a.updatedAt or 0, b.updatedAt or 0
                if ua ~= ub then return ua > ub end
            elseif soloOrder == "class" then
                local ca, cb = a.classFile or "ZZZ", b.classFile or "ZZZ"
                if ca ~= cb then return ca < cb end
                local la, lb = a.level or 0, b.level or 0
                if la ~= lb then return la > lb end
            else
                local oa, ob = a.searchOrder or 999999, b.searchOrder or 999999
                if oa ~= ob then return oa < ob end
                local ua, ub = a.updatedAt or 0, b.updatedAt or 0
                if ua ~= ub then return ua > ub end
            end
        else
            local ua, ub = a.updatedAt or 0, b.updatedAt or 0
            if ua ~= ub then return ua > ub end
        end
        return tostring(a.displayName or "") < tostring(b.displayName or "")
    end)
    return rows
end

local reverseLocaleMap = nil

local function GetReverseLocaleMap()
    if reverseLocaleMap then return reverseLocaleMap end
    reverseLocaleMap = {}
    if type(ns.L) == "table" then
        for engKey, locVal in pairs(ns.L) do
            if type(engKey) == "string" and type(locVal) == "string" and locVal ~= "" then
                local low = TrimText(locVal):lower()
                if #low >= 3 and #engKey <= 160 and not reverseLocaleMap[low] then
                    reverseLocaleMap[low] = engKey
                end
            end
        end
    end
    return reverseLocaleMap
end

local function TranslateLocalizedActivityToEnglish(rawName)
    if type(rawName) ~= "string" or rawName == "" then return "" end
    local rMap = GetReverseLocaleMap()
    local clean = TrimText(rawName)
    local exact = rMap[clean:lower()]
    if exact and exact ~= "" then
        return exact
    end
    local base, suffix = clean:match("^(.-)%s+%-%s+(.+)$")
    if base and suffix then
        local engBase = rMap[TrimText(base):lower()] or TrimText(base)
        return engBase .. " (" .. TrimText(suffix) .. ")"
    end
    local parenBase, parenWing = clean:match("^(.-)%s*%(([^)]+)%)%s*$")
    if parenBase and parenWing then
        local engBase = rMap[TrimText(parenBase):lower()] or TrimText(parenBase)
        return engBase .. " (" .. TrimText(parenWing) .. ")"
    end
    return clean
end

local function JoinDisplayList(names, maxCount)
    if type(names) ~= "table" or #names == 0 then return "" end
    local limit = maxCount and math.min(#names, maxCount) or #names
    if limit == 1 then return names[1] end
    return table.concat(names, " / ", 1, limit)
end

function LFG:ResolveEnglishActivitiesText(activityIds, intersectWithTicked, maxNames)
    if type(activityIds) ~= "table" or #activityIds == 0 then return "" end
    local chosen = {}
    if intersectWithTicked and ns.LFGFrameTab and ns.LFGFrameTab.GetSelectedOfficialActivityIds then
        local ticked = ns.LFGFrameTab:GetSelectedOfficialActivityIds()
        if type(ticked) == "table" and #ticked > 0 then
            local set = {}
            for _, id in ipairs(ticked) do set[id] = true end
            for _, id in ipairs(activityIds) do
                if set[id] then chosen[#chosen + 1] = id end
            end
        end
    end
    if #chosen == 0 then chosen = activityIds end

    local engNames, seen = {}, {}
    for _, aid in ipairs(chosen) do
        local info = (ns.Clan and ns.Clan.GetCachedOfficialActivityInfo)
            and ns.Clan:GetCachedOfficialActivityInfo(aid)
            or (C_LFGList and C_LFGList.GetActivityInfoTable and Safe.Call(C_LFGList.GetActivityInfoTable, aid))
        local catId = type(info) == "table" and Safe.Number(info.categoryID)
        local kind = (ns.Clan and ns.Clan.GetOfficialCategoryKind) and ns.Clan:GetOfficialCategoryKind(catId, nil, info) or nil
        if type(info) == "table" then
            local raw = Safe.String(info.shortName) or Safe.String(info.fullName)
            local eng = raw and TranslateLocalizedActivityToEnglish(raw) or ""
            if eng ~= "" and not seen[eng] then
                seen[eng] = true
                engNames[#engNames + 1] = eng
            end
        end
    end
    return JoinDisplayList(engNames, maxNames)
end

local function SubstituteTemplateTokens(tmpl, vars)
    local out = tmpl
    local tokens = {
        { "{level}", vars.level },
        { "{class}", vars.classLoc },
        { "{spec}", vars.spec },
        { "{role}", vars.role },
        { "{ilvl}", vars.ilvlPart },
        { "{activity}", vars.activity },
        { "{activity_en}", vars.activityEn },
    }
    for _, tk in ipairs(tokens) do
        local rep = tk[2] or ""
        out = out:gsub(tk[1], function() return rep end)
    end
    out = out:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    return out
end

local function ResolveTemplateRoleLabel()
    local ft = ns.LFGFrameTab
    local r = ft and ft.roles
    if type(r) == "table" then
        local parts = {}
        if r.TANK then parts[#parts + 1] = L["Tank"] end
        if r.HEALER then parts[#parts + 1] = L["Healer"] end
        if r.DPS then parts[#parts + 1] = L["DPS"] end
        if #parts > 0 then
            return table.concat(parts, " / ")
        end
    end
    local roleToken = (ns.Clan and ns.Clan.GetMySpecAndRole) and select(1, ns.Clan:GetMySpecAndRole()) or nil
    if roleToken == "TANK" then return L["Tank"] end
    if roleToken == "HEALER" then return L["Healer"] end
    return L["DPS"]
end

function LFG:FormatApplyMessage(item, tmplOverride, allowWhenDisabled)
    local s = ns.db and ns.db.settings
    if not allowWhenDisabled and s and s.lfgAutoApplyDraft == false then
        return nil
    end
    local tmpl = tmplOverride
    if tmpl == nil then
        tmpl = (s and type(s.lfgWhisperTemplate) == "string") and s.lfgWhisperTemplate or ""
    end
    local baseRole = ResolveTemplateRoleLabel()
    local sum = (ns.Clan and ns.Clan.GetPlayerGameSummary) and ns.Clan:GetPlayerGameSummary() or nil
    local ilvlVal = (sum and (sum.avgItemLevel or 0) > 0) and tostring(sum.avgItemLevel) or ""
    local ilvlPart = (ilvlVal ~= "") and ("iLvl " .. ilvlVal) or ""
    local lvlNum = Safe.Number(Safe.Call(UnitLevel, "player")) or 0
    local lvlStr = (lvlNum > 0) and tostring(lvlNum) or "60"
    local rawClassLoc = Safe.Call(UnitClass, "player")
    local classLoc = Safe.String(rawClassLoc) or ""
    local spec = self:GetPrimarySpecName()
    local actStr = item and (item._canonicalActivityLabel or (item.activity and item.activity ~= "" and item.activity)) or L["Dungeon"]
    local activityEn = (item and type(item.activityIds) == "table" and self:ResolveEnglishActivitiesText(item.activityIds, true, 3)) or ""
    if activityEn == "" then activityEn = TranslateLocalizedActivityToEnglish(actStr) end
    if activityEn == "" then activityEn = actStr end

    if type(tmpl) == "string" and tmpl:find("%S") then
        local msg = SubstituteTemplateTokens(tmpl, {
            level = lvlStr,
            classLoc = classLoc,
            spec = spec,
            role = baseRole,
            ilvlPart = ilvlPart,
            activity = actStr,
            activityEn = activityEn,
        })
        if msg ~= "" then return msg end
    end

    local roleFull = (ilvlPart ~= "") and (baseRole .. " · " .. ilvlPart) or baseRole
    local classWithSpec = (spec ~= "" and classLoc ~= "") and (classLoc .. " " .. spec) or classLoc
    if lvlNum > 0 and classWithSpec ~= "" then
        return string.format(L["Hi! Lv %d %s (%s) available for %s"], lvlNum, classWithSpec, roleFull, actStr)
    end
    return string.format(L["Hi! Available (%s) for %s"], roleFull, actStr)
end

function LFG:FormatInviteMessage(item, tmplOverride, allowWhenDisabled)
    local s = ns.db and ns.db.settings
    if not allowWhenDisabled and s and s.lfgInviteAutoWhisper == false then
        return nil
    end
    local inGroup = Compat.IsInGroup and Compat.IsInGroup()
    if not allowWhenDisabled and inGroup and Compat.IsGroupLeader and not Compat.IsGroupLeader() then
        return nil
    end
    local tmpl = tmplOverride
    if tmpl == nil then
        tmpl = (s and type(s.lfgInviteWhisperTemplate) == "string" and s.lfgInviteWhisperTemplate ~= "")
            and s.lfgInviteWhisperTemplate
            or "Hi! Inviting you to our {activity_en} group!"
    end
    if type(tmpl) ~= "string" or not tmpl:find("%S") then
        return nil
    end

    local actIds = nil
    if C_LFGList and C_LFGList.HasActiveEntryInfo and Safe.Value(Safe.Call(C_LFGList.HasActiveEntryInfo)) == true and C_LFGList.GetActiveEntryInfo then
        local entry = Safe.Call(C_LFGList.GetActiveEntryInfo)
        if type(entry) == "table" and type(entry.activityIDs) == "table" and #entry.activityIDs > 0 then
            actIds = entry.activityIDs
        end
    end
    if (not actIds or #actIds == 0) and ns.LFGFrameTab and ns.LFGFrameTab.GetSelectedOfficialActivityIds then
        actIds = ns.LFGFrameTab:GetSelectedOfficialActivityIds()
    end

    local activityEn = (type(actIds) == "table" and #actIds > 0) and self:ResolveEnglishActivitiesText(actIds, false, 6) or ""
    local actStr = activityEn
    if actStr == "" and item and type(item.activity) == "string" and item.activity ~= "" then
        actStr = item.activity
        activityEn = TranslateLocalizedActivityToEnglish(item.activity)
    end
    if actStr == "" then
        return nil
    end

    local sum = (ns.Clan and ns.Clan.GetPlayerGameSummary) and ns.Clan:GetPlayerGameSummary() or nil
    local ilvlVal = (sum and (sum.avgItemLevel or 0) > 0) and tostring(sum.avgItemLevel) or ""
    local ilvlPart = (ilvlVal ~= "") and ("iLvl " .. ilvlVal) or ""
    local msg = SubstituteTemplateTokens(tmpl, {
        level = tostring(Safe.Number(Safe.Call(UnitLevel, "player")) or 60),
        classLoc = Safe.String(Safe.Call(UnitClass, "player")) or "",
        spec = self:GetPrimarySpecName(),
        role = ResolveTemplateRoleLabel(),
        ilvlPart = ilvlPart,
        activity = actStr,
        activityEn = (activityEn ~= "") and activityEn or actStr,
    })
    return (msg ~= "") and msg or nil
end

function LFG:ExecuteRowAction(item, isHardwareEvent)
    if not item then return false end
    local combat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if item.isSelf then
        if combat then
            ns:Print("%s", L["Unavailable during combat."])
            return false
        end
        if ns.Clan and ns.Clan.ClearMyLFG then
            ns.Clan:ClearMyLFG(isHardwareEvent == true)
        end
        if ns.LFGFrameTab and ns.LFGFrameTab.HandleOwnListingRemoved then
            ns.LFGFrameTab:HandleOwnListingRemoved()
        end
        EmitBrowseChanged()
        return true
    end

    if item.secretLeaderName ~= nil or item.isUnknownLeader == true then
        if ns.LFGFrameTab and ns.LFGFrameTab.HideSubPanel then
            ns.LFGFrameTab:HideSubPanel(true)
        end
        return false
    end

    local targetName = item.displayName or item.lookupKey
    if not targetName or targetName == "" then return false end
    local rKey = item.lookupKey or targetName
    local bInfo = (ns.Social and ns.Social.GetBNetLinkInfo) and ns.Social:GetBNetLinkInfo(rKey) or nil
    local bnetAccId = item.bnetAccountID or (bInfo and bInfo.bnetAccountID)
    local bnetName = item.bnetName or (bInfo and bInfo.bnetName)
    local isCrossFac = (item.sameFaction == false) or (bInfo and bInfo.sameFaction == false)
    local isSolo = (item.mode == "LFG" and item.sourceType ~= "EVENT")

    if isSolo then
        if combat then
            ns:Print("%s", L["Unavailable during combat."])
            return false
        end
        if Compat.Invite then
            Compat.Invite(targetName, bnetAccId)
        end
        local invMsg = self:FormatInviteMessage(item)
        if invMsg and ns.Chat and ns.Chat.SendDirectLfgWhisper then
            ns.Chat:SendDirectLfgWhisper(targetName, invMsg, isHardwareEvent == true, true)
        end
        return true
    end

    self:MarkAsked(item)
    local draft = self:FormatApplyMessage(item)
    local addonAllowed = (not Compat or not Compat.IsOfficialChatMode or not Compat.IsOfficialChatMode())
        and (not Compat or not Compat.IsModuleEnabled or Compat.IsModuleEnabled("chat"))
    local scConfirmed = addonAllowed and ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(rKey, bnetAccId)
    if scConfirmed and ns.Chat and ns.Chat.OpenPreferredConversation then
        return ns.Chat:OpenPreferredConversation({
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
    end
    if isCrossFac and bnetName and Compat.BNetWhisper then
        return Compat.BNetWhisper(bnetName, targetName, draft)
    end
    if draft and isHardwareEvent == true and ns.Chat and ns.Chat.SendDirectLfgWhisper then
        return ns.Chat:SendDirectLfgWhisper(targetName, draft, true, false)
    end
    if Compat.Whisper then
        return Compat.Whisper(targetName, draft)
    end
    return false
end

function LFG:TriggerRoleCheck()
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print("%s", L["Unavailable during combat."])
        return false
    end
    if not (Compat.IsInGroup and Compat.IsInGroup()) then
        ns:Print("%s", L["You are not in a group."])
        return false
    end
    local canLead = (Compat.IsGroupLeader and Compat.IsGroupLeader("player"))
        or (Compat.IsGroupAssistant and Compat.IsGroupAssistant("player"))
    if not canLead then
        ns:Print("%s", L["Only the group leader or assistant can start a Role Check."])
        return false
    end
    local now = GetTime and GetTime() or 0
    if (now - (self._lastRoleCheckAt or 0)) < 2.0 then
        return false
    end
    self._lastRoleCheckAt = now
    if InitiateRolePoll then
        pcall(InitiateRolePoll)
        return true
    end
    return false
end

local function PrepareModalShell(name, w, h, posKey)
    local Theme = ns.Theme
    local m = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    m:Hide()
    m:SetSize(w, h)
    m:SetPoint("CENTER")
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    if Theme and Theme.MakeMovable then
        Theme:MakeMovable(m, { key = posKey, clampToScreen = true })
    end
    if type(_G.UISpecialFrames) == "table" then
        local exists = false
        for _, n in ipairs(_G.UISpecialFrames) do
            if n == name then exists = true; break end
        end
        if not exists then table.insert(_G.UISpecialFrames, name) end
    end
    local bg = m:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(m)
    bg:SetTexture(WHITE8X8)
    bg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    m._solidOpaqueBg = bg
    return m
end

local function RefreshModalChrome(m)
    if not m then return end
    local Theme = ns.Theme
    if Theme and Theme.PrepareTopOverlayModal then
        Theme:PrepareTopOverlayModal(m, 860)
    else
        m:SetParent(UIParent)
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(860)
        if m.SetToplevel then m:SetToplevel(true) end
    end
    local p = Theme and Theme.GetPalette and Theme:GetPalette() or nil
    if m._solidOpaqueBg then
        local wBg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
        m._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
    end
    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(m, "window", p)
    end
    if m.helpBtn and m.helpBtn.RefreshTheme then m.helpBtn:RefreshTheme() end
end

function LFG:OpenSavePresetModal(onSaved)
    local Theme = ns.Theme
    if not Theme then return end
    local m = self._savePresetModal
    if not m then
        m = PrepareModalShell("SocialCentralLFGSavePresetModal", 380, 168, "lfg_save_preset")
        local titleFs = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        titleFs:SetPoint("TOPLEFT", 16, -14)
        titleFs:SetText(L["Save Filter Preset"])
        m.titleFs = titleFs

        local closeBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        closeBtn:SetPoint("TOPRIGHT", -12, -12)
        closeBtn:SetScript("OnClick", function() m:Hide() end)
        m.closeBtn = closeBtn

        local helpBtn = Theme:CreateHelpButton(
            m,
            L["Help: Save Filter Preset"],
            L["Saves your current LFG role, class exclusion, level range, playstyle, and language filters under a reusable name shared across all characters."],
            L["Enter a name (up to %d characters) and click Save. Reusing an existing name overwrites that preset."]:format(MAX_PRESET_NAME_LEN),
            16,
            { target = m }
        )
        helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
        m.helpBtn = helpBtn

        local input = Theme:CreateEditBox(m, {
            height = 24,
            maxLetters = MAX_PRESET_NAME_LEN,
            clearButton = true,
            placeholder = L["Preset name (max %d chars)..."]:format(MAX_PRESET_NAME_LEN),
        })
        input:SetPoint("TOPLEFT", 16, -50)
        input:SetPoint("TOPRIGHT", -16, -50)
        input:SetScript("OnEscapePressed", function() m:Hide() end)
        m.input = input

        local warnFs = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        warnFs:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 2, -6)
        warnFs:SetPoint("TOPRIGHT", input, "BOTTOMRIGHT", -2, -6)
        warnFs:SetJustifyH("LEFT")
        warnFs:SetTextColor(1.0, 0.35, 0.35)
        warnFs:SetText("")
        m.warnFs = warnFs

        local saveBtn = Theme:CreateButton(m, 96, 24, L["Save"], "primary")
        saveBtn:SetPoint("BOTTOMRIGHT", -14, 14)
        m.saveBtn = saveBtn

        local cancelBtn = Theme:CreateButton(m, 88, 24, L["Cancel"], "default")
        cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
        cancelBtn:SetScript("OnClick", function() m:Hide() end)
        m.cancelBtn = cancelBtn

        local function ValidateInput()
            local txt = TrimText(input:GetText() or "")
            local isDup = false
            for _, p in ipairs(LFG:GetPresets()) do
                if p.name == txt then isDup = true; break end
            end
            if txt == "" then
                warnFs:SetText("")
                saveBtn:SetEnabled(false)
            elseif (not isDup) and (#LFG:GetPresets() >= MAX_PRESETS) then
                warnFs:SetText(L["Maximum of %d presets reached. Overwrite or delete one first."]:format(MAX_PRESETS))
                saveBtn:SetEnabled(false)
            elseif isDup then
                warnFs:SetText(L["A preset with this name already exists and will be overwritten."])
                saveBtn:SetEnabled(true)
            else
                warnFs:SetText("")
                saveBtn:SetEnabled(true)
            end
        end
        input:HookScript("OnTextChanged", ValidateInput)
        m.ValidateInput = ValidateInput

        local function DoSave()
            local ok = LFG:SavePreset(input:GetText() or "")
            if ok then
                m:Hide()
                if m._onSaved then m._onSaved() end
            end
        end
        saveBtn:SetScript("OnClick", DoSave)
        input:SetScript("OnEnterPressed", DoSave)
        self._savePresetModal = m
    end

    m._onSaved = onSaved
    RefreshModalChrome(m)
    Theme:StyleButton(m.closeBtn, "default")
    Theme:StyleButton(m.saveBtn, "primary")
    Theme:StyleButton(m.cancelBtn, "default")
    if m.input and Theme.StyleEditBox then Theme:StyleEditBox(m.input) end
    m.input:SetText("")
    m.ValidateInput()
    m:Show()
    if m.Raise then m:Raise() end
    m.input:SetFocus()
end

function LFG:OpenSoloLevelModal(onChanged)
    local Theme = ns.Theme
    if not Theme then return end
    local m = self._soloLevelModal
    if not m then
        m = PrepareModalShell("SocialCentralLFGSoloLevelModal", 336, 158, "lfg_solo_level")
        local titleFs = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        titleFs:SetPoint("TOPLEFT", 16, -14)
        titleFs:SetText(L["Players Looking Level Range"])
        m.titleFs = titleFs

        local closeBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        closeBtn:SetPoint("TOPRIGHT", -12, -12)
        closeBtn:SetScript("OnClick", function() m:Hide() end)
        m.closeBtn = closeBtn

        local helpBtn = Theme:CreateHelpButton(
            m,
            L["Help: Players Looking Level Range"],
            L["Filters players looking for groups (LFG) by minimum and maximum character level without hiding group listings."],
            L["Leave either box empty (or 0) for no limit on that side, then click Apply."],
            16,
            { target = m }
        )
        helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
        m.helpBtn = helpBtn

        local minLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        minLbl:SetPoint("TOPLEFT", 16, -54)
        minLbl:SetText(L["Min Lv:"])

        local minBox = Theme:CreateEditBox(m, { height = 24, maxLetters = 3, numeric = true, placeholder = "1" })
        minBox:SetPoint("LEFT", minLbl, "RIGHT", 6, 0)
        minBox:SetWidth(58)
        m.minBox = minBox

        local maxLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        maxLbl:SetPoint("LEFT", minBox, "RIGHT", 14, 0)
        maxLbl:SetText(L["Max Lv:"])

        local maxBox = Theme:CreateEditBox(m, { height = 24, maxLetters = 3, numeric = true, placeholder = "60" })
        maxBox:SetPoint("LEFT", maxLbl, "RIGHT", 6, 0)
        maxBox:SetWidth(58)
        m.maxBox = maxBox

        local clearBtn = Theme:CreateButton(m, 76, 24, L["Clear"], "default")
        clearBtn:SetPoint("BOTTOMLEFT", 14, 14)
        clearBtn:SetScript("OnClick", function()
            LFG:SetSoloLevelRange(0, 0)
            m:Hide()
            if m._onChanged then m._onChanged() end
        end)
        m.clearBtn = clearBtn

        local applyBtn = Theme:CreateButton(m, 88, 24, L["Apply"], "primary")
        applyBtn:SetPoint("BOTTOMRIGHT", -14, 14)
        local function DoApply()
            LFG:SetSoloLevelRange(tonumber(minBox:GetText()) or 0, tonumber(maxBox:GetText()) or 0)
            m:Hide()
            if m._onChanged then m._onChanged() end
        end
        applyBtn:SetScript("OnClick", DoApply)
        minBox:SetScript("OnEnterPressed", DoApply)
        maxBox:SetScript("OnEnterPressed", DoApply)
        minBox:SetScript("OnEscapePressed", function() m:Hide() end)
        maxBox:SetScript("OnEscapePressed", function() m:Hide() end)
        m.applyBtn = applyBtn

        self._soloLevelModal = m
    end

    m._onChanged = onChanged
    RefreshModalChrome(m)
    Theme:StyleButton(m.closeBtn, "default")
    Theme:StyleButton(m.clearBtn, "default")
    Theme:StyleButton(m.applyBtn, "primary")
    if Theme.StyleEditBox then
        Theme:StyleEditBox(m.minBox)
        Theme:StyleEditBox(m.maxBox)
    end
    local minL, maxL = self:GetSoloLevelRange()
    m.minBox:SetText((minL > 0) and tostring(minL) or "")
    m.maxBox:SetText((maxL > 0) and tostring(maxL) or "")
    m:Show()
    if m.Raise then m:Raise() end
    m.minBox:SetFocus()
end

local function ClassMenuLabel(cf)
    local Theme = ns.Theme
    local name = LFG:GetClassName(cf)
    local atlas = "groupfinder-icon-class-" .. cf:lower()
    if Theme and Theme.HasAtlas and Theme:HasAtlas(atlas) and CreateAtlasMarkup then
        return CreateAtlasMarkup(atlas, 14, 14) .. " " .. name
    end
    return name
end

function LFG:PopulateAdvancedFiltersMenu(root, onChanged)
    if not root then return end
    local function Changed()
        if onChanged then onChanged() end
    end

    if root.CreateTitle then root:CreateTitle(L["Listing Type"]) end
    for _, tDef in ipairs({
        { id = "ALL", label = L["All"] },
        { id = "GROUPS", label = L["Groups (LFM)"] },
        { id = "SOLO", label = L["Looking (LFG)"] },
    }) do
        local tid = tDef.id
        if root.CreateRadio then
            root:CreateRadio(tDef.label, function()
                return LFG:GetListingType() == tid
            end, function()
                LFG:SetListingType(tid)
                Changed()
            end)
        else
            root:CreateButton(tDef.label, function()
                LFG:SetListingType(tid)
                Changed()
            end)
        end
    end

    if root.CreateDivider then root:CreateDivider() end
    if root.CreateTitle then root:CreateTitle(L["Group & Role Filters"]) end

    local roleChoices = {
        { val = 0, label = L["Any"] },
        { val = 1, label = "+ " .. L["Needs Slot"] },
        { val = 2, label = "= " .. L["Already Has"] },
    }
    for _, rDef in ipairs({
        { rk = "TANK", label = L["Tank"] },
        { rk = "HEALER", label = L["Healer"] },
        { rk = "DPS", label = L["DPS"] },
    }) do
        local curV = LFG:GetRoleState(rDef.rk)
        local badge = (curV == 1 and " |cff3fb950[+]|r") or (curV == 2 and " |cff58a6ff[=]|r") or ""
        local rSub = root:CreateButton(rDef.label .. badge)
        if rSub and rSub.CreateRadio then
            for _, rc in ipairs(roleChoices) do
                local targetRk, targetV = rDef.rk, rc.val
                rSub:CreateRadio(rc.label, function()
                    return LFG:GetRoleState(targetRk) == targetV
                end, function()
                    LFG:SetRoleState(targetRk, targetV)
                    Changed()
                end)
            end
        end
    end

    local exCnt = CountBoolSet(LFG:GetCharState().groupExcludedClasses)
    local exclSub = root:CreateButton((exCnt > 0) and (L["Exclude Classes in Group"] .. " (" .. exCnt .. ")") or L["Exclude Classes in Group"])
    if exclSub then
        local myCf = LFG:GetMyClassFile()
        if myCf then
            if exclSub.CreateCheckbox then
                exclSub:CreateCheckbox("|cffffd24d" .. L["Exclude My Class"] .. " (" .. LFG:GetClassName(myCf) .. ")|r", function()
                    return LFG:IsGroupClassExcluded(myCf)
                end, function()
                    LFG:ToggleGroupClassExcluded(myCf)
                    Changed()
                end)
            end
        end
        exclSub:CreateButton(L["Clear"], function()
            LFG:ClearGroupClassExcluded()
            Changed()
        end)
        if exclSub.CreateDivider then exclSub:CreateDivider() end
        for _, cf in ipairs(LFG.CLASSIC_CLASSES) do
            local classKey = cf
            if exclSub.CreateCheckbox then
                exclSub:CreateCheckbox(ClassMenuLabel(classKey), function()
                    return LFG:IsGroupClassExcluded(classKey)
                end, function()
                    LFG:ToggleGroupClassExcluded(classKey)
                    Changed()
                end)
            end
        end
    end

    local soloSub = root:CreateButton(L["Players Looking (Class, Level, Sort)"])
    if soloSub then
        if soloSub.CreateTitle then soloSub:CreateTitle(L["Roles"]) end
        if soloSub.CreateCheckbox then
            for _, rDef in ipairs({
                { rk = "TANK", label = L["Tank"] },
                { rk = "HEALER", label = L["Heal"] },
                { rk = "DPS", label = L["DPS"] },
            }) do
                local targetRk = rDef.rk
                soloSub:CreateCheckbox(rDef.label, function()
                    return LFG:GetSoloRoleAllowed(targetRk)
                end, function()
                    LFG:ToggleSoloRoleAllowed(targetRk)
                    Changed()
                end)
            end
        end
        if soloSub.CreateDivider then soloSub:CreateDivider() end
        soloSub:CreateButton(L["Select All"], function()
            LFG:SetAllSoloClasses(true)
            Changed()
        end)
        soloSub:CreateButton(L["Unselect All"], function()
            LFG:SetAllSoloClasses(false)
            Changed()
        end)
        for _, cf in ipairs(LFG.CLASSIC_CLASSES) do
            local classKey = cf
            if soloSub.CreateCheckbox then
                soloSub:CreateCheckbox(ClassMenuLabel(classKey), function()
                    return LFG:IsSoloClassSelected(classKey)
                end, function()
                    LFG:ToggleSoloClass(classKey)
                    Changed()
                end)
            end
        end
        if soloSub.CreateDivider then soloSub:CreateDivider() end
        local minL, maxL = LFG:GetSoloLevelRange()
        local lvlSuffix = (minL > 0 or maxL > 0) and (" (" .. tostring(minL) .. "-" .. tostring(maxL > 0 and maxL or 60) .. ")") or ""
        soloSub:CreateButton(L["Level Range (Min-Max)..."] .. lvlSuffix, function()
            LFG:OpenSoloLevelModal(Changed)
        end)
        local sortSub = soloSub:CreateButton(L["Sort Players By"])
        if sortSub and sortSub.CreateRadio then
            for _, sOpt in ipairs(LFG.SOLO_SORT_ORDERS) do
                local sid = sOpt.id
                sortSub:CreateRadio(L[sOpt.labelKey], function()
                    return LFG:GetSoloSortOrder() == sid
                end, function()
                    LFG:SetSoloSortOrder(sid)
                    Changed()
                end)
            end
        end
    end

    local psSub = root:CreateButton(L["Playstyle"])
    if psSub and psSub.CreateCheckbox then
        for _, ps in ipairs(LFG.PLAYSTYLES) do
            local pKey = ps.key
            psSub:CreateCheckbox(LFG:GetPlaystyleLabel(pKey), function()
                return LFG:IsPlaystyleSelected(pKey)
            end, function()
                LFG:TogglePlaystyle(pKey)
                Changed()
            end)
        end
    end

    local langs = LFG:GetAvailableLanguages()
    local locked = LFG:GetLockedLanguages()
    local langSub = root:CreateButton(L["Search Languages"])
    if langSub then
        langSub:CreateButton(L["Select All"], function()
            LFG:SetAllLanguages(true)
            Changed()
        end)
        langSub:CreateButton(L["Unselect All"], function()
            LFG:SetAllLanguages(false)
            Changed()
        end)
        if langSub.CreateDivider then langSub:CreateDivider() end
        if #langs == 0 then
            local emptyBtn = langSub:CreateButton(L["No extra languages reported by server."], function() end)
            if emptyBtn and emptyBtn.SetEnabled then pcall(emptyBtn.SetEnabled, emptyBtn, false) end
        else
            for _, code in ipairs(langs) do
                local c = code
                local lbl = LFG:GetLanguageLabel(c)
                if locked[c] then
                    lbl = lbl .. " |cff9da7b5(" .. L["Locked"] .. ")|r"
                end
                if langSub.CreateCheckbox then
                    local cb = langSub:CreateCheckbox(lbl, function()
                        return LFG:IsLanguageSelected(c)
                    end, function()
                        LFG:ToggleLanguage(c)
                        Changed()
                    end)
                    if locked[c] and cb and cb.SetEnabled then
                        pcall(cb.SetEnabled, cb, false)
                    end
                end
            end
        end
    end

    local presets = LFG:GetPresets()
    local preSub = root:CreateButton((#presets > 0) and (L["My Filter Presets"] .. " (" .. #presets .. ")") or L["My Filter Presets"])
    if preSub then
        preSub:CreateButton(L["Save Current Filters..."], function()
            LFG:OpenSavePresetModal(Changed)
        end)
        if #presets > 0 then
            if preSub.CreateDivider then preSub:CreateDivider() end
            for _, p in ipairs(presets) do
                local pName = p.name
                preSub:CreateButton(pName, function()
                    LFG:ApplyPreset(pName)
                    Changed()
                end)
            end
            if preSub.CreateDivider then preSub:CreateDivider() end
            local delSub = preSub:CreateButton(L["Delete Preset"])
            if delSub then
                for _, p in ipairs(presets) do
                    local pName = p.name
                    delSub:CreateButton(pName, function()
                        LFG:DeletePreset(pName)
                        Changed()
                    end)
                end
            end
        end
    end

    if root.CreateDivider then root:CreateDivider() end
    root:CreateButton(L["Reset Advanced Filters"], function()
        LFG:ResetAdvancedFilters()
        Changed()
    end)
end

function LFG:NotifySideDrawerChange(triggerOfficial)
    local tab = self._sideDrawerHost or ns.LFGFrameTab
    if tab then
        tab._hasSearchedThisSession = true
        if tab.SaveBrowseFilters then tab:SaveBrowseFilters() end
        if triggerOfficial and tab.TriggerOfficialBrowseSearch then
            tab:TriggerOfficialBrowseSearch(true)
        end
        if tab.RefreshData then tab:RefreshData() end
    end
    self:RefreshSideDrawer(tab)
    ns:Emit("LFG_BROWSE_STATE_CHANGED")
end

local DRAWER_CLASS_ORDER = {
    "WARRIOR", "PALADIN", "PRIEST", "SHAMAN",
    "DRUID", "ROGUE", "MAGE", "WARLOCK", "HUNTER",
}

local function Utf8ShortTag(text, maxChars)
    if type(text) ~= "string" or text == "" then return "?" end
    local i, count, n = 1, 0, #text
    local limit = maxChars or 3
    while i <= n and count < limit do
        local b = text:byte(i)
        if b < 128 then
            i = i + 1
        elseif b >= 240 then
            i = i + 4
        elseif b >= 224 then
            i = i + 3
        else
            i = i + 2
        end
        count = count + 1
    end
    return text:sub(1, math.max(1, i - 1))
end

local function SetDrawerRoleIcon(tex, roleId)
    if not tex then return end
    tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
    if roleId == "TANK" then
        tex:SetTexCoord(2 / 64, 17 / 64, 24 / 64, 39 / 64)
    elseif roleId == "HEALER" then
        tex:SetTexCoord(22 / 64, 37 / 64, 3 / 64, 18 / 64)
    else
        tex:SetTexCoord(22 / 64, 37 / 64, 24 / 64, 39 / 64)
    end
end

local function SetDrawerClassIcon(tex, classFile)
    if not (tex and classFile and classFile ~= "") then return end
    local Theme = ns.Theme
    local slug = classFile:lower()
    local atlas = "groupfinder-icon-class-" .. slug
    if Theme and Theme.HasAtlas and Theme:HasAtlas(atlas) then
        tex:SetAtlas(atlas, false)
        tex:SetTexCoord(0, 1, 0, 1)
    elseif _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[classFile] then
        local tc = _G.CLASS_ICON_TCOORDS[classFile]
        tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    end
end

local function OpenGroupQuestsContextMenu(anchorBtn)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local tab = LFG._sideDrawerHost or ns.LFGFrameTab
    local gQuests = (ns.Clan and ns.Clan.GetActiveGroupQuests) and ns.Clan:GetActiveGroupQuests() or {}
    MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        root:CreateTitle(L["Active Group Quests"])
        if #gQuests == 0 then
            local noneBtn = root:CreateButton(L["No group quests currently in your quest log."], function() end)
            if noneBtn and noneBtn.SetEnabled then pcall(noneBtn.SetEnabled, noneBtn, false) end
            return
        end
        for _, q in ipairs(gQuests) do
            local grp = (q.suggestedGroup and q.suggestedGroup >= 2) and (" · G" .. q.suggestedGroup) or ""
            root:CreateButton(("[%d%s] %s"):format(q.level or 0, grp, q.title or "?"), function()
                if not tab then return end
                tab._hasSearchedThisSession = true
                tab.categoryFilter = "ALL"
                if tab.browseActivityFilter then wipe(tab.browseActivityFilter) end
                tab.query = q.title or ""
                if tab.controls and tab.controls.searchBox then
                    tab.controls.searchBox:SetText(tab.query)
                end
                LFG:NotifySideDrawerChange(true)
            end)
        end
    end)
end

local function OpenExcludeClassesContextMenu(anchorBtn)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        root:CreateTitle(L["Exclude Classes in Group"])
        local myCf = LFG:GetMyClassFile()
        if myCf and myCf ~= "" and root.CreateCheckbox then
            root:CreateCheckbox("|cffffd24d" .. L["Exclude My Class"] .. " (" .. LFG:GetClassName(myCf) .. ")|r", function()
                return LFG:IsGroupClassExcluded(myCf)
            end, function()
                LFG:ToggleGroupClassExcluded(myCf)
                LFG:NotifySideDrawerChange(false)
            end)
        end
        root:CreateButton(L["Clear"], function()
            LFG:ClearGroupClassExcluded()
            LFG:NotifySideDrawerChange(false)
        end)
        if root.CreateDivider then root:CreateDivider() end
        for _, cf in ipairs(DRAWER_CLASS_ORDER) do
            local classKey = cf
            if root.CreateCheckbox then
                root:CreateCheckbox(ClassMenuLabel(classKey), function()
                    return LFG:IsGroupClassExcluded(classKey)
                end, function()
                    LFG:ToggleGroupClassExcluded(classKey)
                    LFG:NotifySideDrawerChange(false)
                end)
            end
        end
    end)
end

local function OpenSoloSortContextMenu(anchorBtn)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        root:CreateTitle(L["Sort Players By"])
        for _, ord in ipairs(LFG.SOLO_SORT_ORDERS) do
            local oid = ord.id
            root:CreateRadio(L[ord.labelKey], function()
                return LFG:GetSoloSortOrder() == oid
            end, function()
                LFG:SetSoloSortOrder(oid)
                LFG:NotifySideDrawerChange(false)
            end)
        end
    end)
end

local function OpenLanguagesContextMenu(anchorBtn)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local langs = LFG:GetAvailableLanguages()
    local locked = LFG:GetLockedLanguages()
    MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        root:CreateTitle(L["Search Languages"])
        root:CreateButton(L["Select All"], function()
            LFG:SetAllLanguages(true)
            LFG:NotifySideDrawerChange(true)
        end)
        root:CreateButton(L["Unselect All"], function()
            LFG:SetAllLanguages(false)
            LFG:NotifySideDrawerChange(true)
        end)
        if root.CreateDivider then root:CreateDivider() end
        if #langs == 0 then
            local emptyBtn = root:CreateButton(L["No extra languages reported by server."], function() end)
            if emptyBtn and emptyBtn.SetEnabled then pcall(emptyBtn.SetEnabled, emptyBtn, false) end
        elseif root.CreateCheckbox then
            for _, code in ipairs(langs) do
                local c = code
                local lbl = LFG:GetLanguageLabel(c)
                if locked[c] then lbl = lbl .. " |cff9da7b5(" .. L["Locked"] .. ")|r" end
                local cb = root:CreateCheckbox(lbl, function()
                    return LFG:IsLanguageSelected(c)
                end, function()
                    LFG:ToggleLanguage(c)
                    LFG:NotifySideDrawerChange(true)
                end)
                if locked[c] and cb and cb.SetEnabled then pcall(cb.SetEnabled, cb, false) end
            end
        end
    end)
end

local function OpenPresetsContextMenu(anchorBtn)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local presets = LFG:GetPresets()
    MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        root:CreateTitle(L["My Filter Presets"])
        root:CreateButton(L["Save Current Filters..."], function()
            LFG:OpenSavePresetModal(function() LFG:NotifySideDrawerChange(false) end)
        end)
        if #presets > 0 then
            if root.CreateDivider then root:CreateDivider() end
            for _, p in ipairs(presets) do
                local pName = p.name
                root:CreateButton(pName, function()
                    LFG:ApplyPreset(pName)
                    LFG:NotifySideDrawerChange(true)
                end)
            end
            if root.CreateDivider then root:CreateDivider() end
            local delSub = root:CreateButton(L["Delete Preset"])
            if delSub then
                for _, p in ipairs(presets) do
                    local pName = p.name
                    delSub:CreateButton(pName, function()
                        LFG:DeletePreset(pName)
                        LFG:NotifySideDrawerChange(false)
                    end)
                end
            end
        end
    end)
end

local function SelectDrawerMode(drawer, modeKey)
    local Theme = ns.Theme
    drawer._activeTab = (modeKey == "social") and "social" or "official"
    if drawer.officialTab then drawer.officialTab:SetShown(drawer._activeTab == "official") end
    if drawer.socialTab then drawer.socialTab:SetShown(drawer._activeTab == "social") end
    if Theme and Theme.StyleButton and drawer.navTabBtns then
        for key, btn in pairs(drawer.navTabBtns) do
            Theme:StyleButton(btn, (key == drawer._activeTab) and "primary" or "default")
        end
    end
end

local DRAWER_W = 564
local DRAWER_H = 554

local INLINE_ROLE_ICONS = {
    TANK   = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:15:15:0:0:64:64:2:17:24:39|t ",
    HEALER = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:15:15:0:0:64:64:22:37:3:18|t ",
    DPS    = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:15:15:0:0:64:64:22:37:24:39|t ",
}

local function SetDrawerBtnFont(btn, fontObj)
    if btn and btn.label and btn.label.SetFontObject then
        btn.label:SetFontObject(fontObj or _G.GameFontHighlight or _G.GameFontHighlightSmall)
    end
end

local function BuildDrawerHeader(drawer)
    local Theme = ns.Theme
    local hdr = CreateFrame("Frame", nil, drawer)
    hdr:SetPoint("TOPLEFT", drawer, "TOPLEFT", 8, -8)
    hdr:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", -8, -8)
    hdr:SetHeight(30)
    drawer.header = hdr

    local logo = hdr:CreateTexture(nil, "ARTWORK")
    logo:SetSize(22, 22)
    logo:SetPoint("LEFT", hdr, "LEFT", 4, 0)
    logo:SetTexture(ICON_TEX)

    local closeBtn = Theme:CreateButton(hdr, 26, 24, "X", "default")
    SetDrawerBtnFont(closeBtn, _G.GameFontNormal)
    closeBtn:SetPoint("RIGHT", hdr, "RIGHT", -2, 0)
    closeBtn:SetScript("OnClick", function()
        if ns.db and ns.db.settings then
            ns.db.settings.lfgSideDrawerOpen = false
        end
        LFG:HideSideDrawer()
        if ns.LFGFrameTab and ns.LFGFrameTab.RefreshData then
            ns.LFGFrameTab:RefreshData()
        end
    end)
    drawer.closeBtn = closeBtn

    local helpBtn = Theme:CreateHelpButton(
        hdr,
        L["Help: SocialCentral Filter Center"],
        L["Smart 2-mode filter panel designed for SocialCentral: Official Search (100% official Blizzard game filters for everyone on the realm) and Guild & Addon (exclusive tools synced with your Guild, Allies, Friends, Watchlist, and SocialCentral users)."],
        L["Use Official Search to pick your goal, set group role open/filled slots directly, protect against loot competition with No My Class, filter recruiting players by role, level (±3/±5), or class archetype, and switch to Guild & Addon anytime for source filters, Favorites, Ratings, and Whisper Templates."],
        18,
        { target = drawer }
    )
    helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    drawer.helpBtn = helpBtn

    local badgeFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    badgeFs:SetPoint("RIGHT", helpBtn, "LEFT", -8, 0)
    badgeFs:SetJustifyH("RIGHT")
    drawer.badgeFs = badgeFs

    local titleFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFs:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    titleFs:SetPoint("RIGHT", badgeFs, "LEFT", -8, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetWordWrap(false)
    titleFs:SetText(L["SocialCentral Filter Center"])
    drawer.titleFs = titleFs

    local tabBar = CreateFrame("Frame", nil, drawer)
    tabBar:SetPoint("TOPLEFT", drawer, "TOPLEFT", 8, -40)
    tabBar:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", -8, -40)
    tabBar:SetHeight(32)

    drawer.navTabBtns = {}
    local modeDefs = {
        { key = "official", label = L["Official Search"] .. " |cff6ec1e4[" .. L["Blizzard"] .. "]|r", w = 271, x = 0 },
        { key = "social",   label = L["Guild & Addon"] .. " |cff3fb950[" .. L["Exclusive"] .. "]|r",  w = 271, x = 277 },
    }
    for _, md in ipairs(modeDefs) do
        local tb = Theme:CreateButton(tabBar, md.w, 28, md.label, "default")
        SetDrawerBtnFont(tb, _G.GameFontNormal)
        tb:SetPoint("TOPLEFT", tabBar, "TOPLEFT", md.x, -2)
        tb:SetScript("OnClick", function()
            SelectDrawerMode(drawer, md.key)
            LFG:RefreshSideDrawer()
        end)
        drawer.navTabBtns[md.key] = tb
    end
end

local function BuildDrawerOfficialMode(drawer, parent)
    local Theme = ns.Theme
    local m1 = CreateFrame("Frame", nil, parent)
    m1:SetAllPoints(parent)
    drawer.officialTab = m1

    -- Card 1: Goal & Quick Actions
    local c1 = CreateFrame("Frame", nil, m1, "BackdropTemplate")
    c1:SetPoint("TOPLEFT", m1, "TOPLEFT", 0, -4)
    c1:SetPoint("TOPRIGHT", m1, "TOPRIGHT", 0, -4)
    c1:SetHeight(76)
    drawer.goalCard = c1

    drawer.intentBtns = {}
    for ii, idf in ipairs({
        { id = "ALL",    lbl = L["Show All"] },
        { id = "GROUPS", lbl = L["Join a Group"] },
        { id = "SOLO",   lbl = L["Recruit Players"] },
    }) do
        local b = Theme:CreateButton(c1, 174, 28, idf.lbl, "default")
        SetDrawerBtnFont(b, _G.GameFontNormal)
        b._typeId = idf.id
        b:SetPoint("TOPLEFT", c1, "TOPLEFT", 6 + ((ii - 1) * 181), -8)
        b:SetScript("OnClick", function()
            LFG:SetListingType(idf.id)
            LFG:NotifySideDrawerChange(false)
        end)
        drawer.intentBtns[ii] = b
    end

    local searchBtn = Theme:CreateButton(c1, 78, 26, L["Search"], "primary")
    SetDrawerBtnFont(searchBtn, _G.GameFontHighlight)
    searchBtn:SetPoint("TOPLEFT", c1, "TOPLEFT", 6, -42)
    searchBtn:SetScript("OnClick", function() LFG:NotifySideDrawerChange(true) end)
    drawer.searchBtn = searchBtn

    local preBtn = Theme:CreateButton(c1, 134, 26, L["Presets"], "default")
    SetDrawerBtnFont(preBtn, _G.GameFontHighlight)
    preBtn:SetPoint("LEFT", searchBtn, "RIGHT", 6, 0)
    preBtn:SetScript("OnClick", function(selfBtn) OpenPresetsContextMenu(selfBtn) end)
    drawer.preBtn = preBtn

    local resetBtn = Theme:CreateButton(c1, 78, 26, L["Reset"], "danger")
    SetDrawerBtnFont(resetBtn, _G.GameFontHighlight)
    resetBtn:SetPoint("LEFT", preBtn, "RIGHT", 6, 0)
    resetBtn:SetScript("OnClick", function()
        LFG:ResetAdvancedFilters()
        LFG:NotifySideDrawerChange(false)
    end)
    drawer.resetBtn = resetBtn

    local roleCheckBtn = Theme:CreateButton(c1, 122, 26, L["Role Check"], "default")
    SetDrawerBtnFont(roleCheckBtn, _G.GameFontHighlight)
    roleCheckBtn:SetPoint("LEFT", resetBtn, "RIGHT", 6, 0)
    roleCheckBtn:SetScript("OnClick", function() LFG:TriggerRoleCheck() end)
    roleCheckBtn:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Initiate Role Check"], 1.0, 0.82, 0.0)
        GameTooltip:AddLine(L["Triggers Blizzard's native group role poll for all party or raid members."], 0.88, 0.90, 0.94, true)
        GameTooltip:Show()
    end)
    roleCheckBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    drawer.roleCheckBtn = roleCheckBtn

    local questBtn = Theme:CreateButton(c1, 96, 26, L["Quests (%d)"]:format(0), "default")
    SetDrawerBtnFont(questBtn, _G.GameFontHighlight)
    questBtn:SetPoint("TOPRIGHT", c1, "TOPRIGHT", -6, -42)
    questBtn:SetScript("OnClick", function(selfBtn) OpenGroupQuestsContextMenu(selfBtn) end)
    questBtn:Hide()
    drawer.questBtn = questBtn

    -- Card 2: Visual Group Composition Matrix + Loot Competition Shield
    local c2 = CreateFrame("Frame", nil, m1, "BackdropTemplate")
    c2:SetPoint("TOPLEFT", m1, "TOPLEFT", 0, -86)
    c2:SetPoint("TOPRIGHT", m1, "TOPRIGHT", 0, -86)
    c2:SetHeight(128)
    drawer.compCard = c2

    local c2Title = c2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c2Title:SetPoint("TOPLEFT", 8, -7)
    c2Title:SetText(L["Group Composition (LFM)"])

    drawer.roleMatrixCards = {}
    for ri, rDef in ipairs({
        { rk = "TANK",   lbl = L["Tank"] },
        { rk = "HEALER", lbl = L["Healer"] },
        { rk = "DPS",    lbl = L["DPS"] },
    }) do
        local rc = CreateFrame("Frame", nil, c2, "BackdropTemplate")
        rc:SetSize(174, 62)
        rc:SetPoint("TOPLEFT", c2, "TOPLEFT", 6 + ((ri - 1) * 181), -27)
        local rIco = rc:CreateTexture(nil, "ARTWORK")
        rIco:SetSize(20, 20)
        rIco:SetPoint("TOPLEFT", rc, "TOPLEFT", 8, -6)
        SetDrawerRoleIcon(rIco, rDef.rk)
        local rFs = rc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rFs:SetPoint("LEFT", rIco, "RIGHT", 6, 0)
        rFs:SetText(rDef.lbl)
        rc._roleId = rDef.rk
        rc.segBtns = {}
        local segDefs = {
            { val = 0, lbl = L["All"] },
            { val = 1, lbl = L["Need"] },
            { val = 2, lbl = L["Has"] },
        }
        for si, sd in ipairs(segDefs) do
            local sb = Theme:CreateButton(rc, 52, 24, sd.lbl, "default")
            SetDrawerBtnFont(sb, _G.GameFontHighlight)
            sb._segVal = sd.val
            sb:SetPoint("TOPLEFT", rc, "TOPLEFT", 5 + ((si - 1) * 56), -32)
            local rk = rDef.rk
            local targetV = sd.val
            sb:SetScript("OnClick", function()
                LFG:SetRoleState(rk, targetV)
                LFG:NotifySideDrawerChange(false)
            end)
            rc.segBtns[si] = sb
        end
        drawer.roleMatrixCards[ri] = rc
    end

    local avoidMyClsBtn = Theme:CreateButton(c2, 264, 26, L["No My Class"], "default")
    SetDrawerBtnFont(avoidMyClsBtn, _G.GameFontHighlight)
    avoidMyClsBtn:SetPoint("TOPLEFT", c2, "TOPLEFT", 6, -95)
    avoidMyClsBtn:SetScript("OnClick", function()
        local myCf = LFG:GetMyClassFile()
        if myCf and myCf ~= "" then
            LFG:ToggleGroupClassExcluded(myCf)
            LFG:NotifySideDrawerChange(false)
        end
    end)
    drawer.avoidMyClsBtn = avoidMyClsBtn

    local exclDropBtn = Theme:CreateButton(c2, 264, 26, L["Exclude Other Classes..."], "default")
    SetDrawerBtnFont(exclDropBtn, _G.GameFontHighlight)
    exclDropBtn:SetPoint("TOPRIGHT", c2, "TOPRIGHT", -6, -95)
    exclDropBtn:SetScript("OnClick", function(selfBtn) OpenExcludeClassesContextMenu(selfBtn) end)
    drawer.exclDropBtn = exclDropBtn

    -- Card 3: Smart Player Recruiting
    local c3 = CreateFrame("Frame", nil, m1, "BackdropTemplate")
    c3:SetPoint("TOPLEFT", m1, "TOPLEFT", 0, -220)
    c3:SetPoint("TOPRIGHT", m1, "TOPRIGHT", 0, -220)
    c3:SetHeight(140)
    drawer.recruitCard = c3

    local c3Title = c3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c3Title:SetPoint("TOPLEFT", 8, -7)
    c3Title:SetText(L["Recruit Players (LFG)"])

    drawer.soloRoleBtns = {}
    for ri, sr in ipairs({
        { rk = "TANK",   lbl = L["Tank"], x = 6,   w = 88 },
        { rk = "HEALER", lbl = L["Heal"], x = 99,  w = 78 },
        { rk = "DPS",    lbl = L["DPS"],  x = 182, w = 70 },
    }) do
        local rb = Theme:CreateButton(c3, sr.w, 26, (INLINE_ROLE_ICONS[sr.rk] or "") .. sr.lbl, "default")
        SetDrawerBtnFont(rb, _G.GameFontHighlight)
        rb._roleId = sr.rk
        rb._baseLabel = sr.lbl
        rb:SetPoint("TOPLEFT", c3, "TOPLEFT", sr.x, -27)
        rb:SetScript("OnClick", function()
            LFG:ToggleSoloRoleAllowed(sr.rk)
            LFG:NotifySideDrawerChange(false)
        end)
        drawer.soloRoleBtns[ri] = rb
    end

    drawer.lvlChipBtns = {}
    for li, ld in ipairs({
        { delta = 0, lbl = L["All"], x = 262, w = 56 },
        { delta = 3, lbl = "±3",     x = 323, w = 40 },
        { delta = 5, lbl = "±5",     x = 368, w = 40 },
    }) do
        local lb = Theme:CreateButton(c3, ld.w, 26, ld.lbl, "default")
        SetDrawerBtnFont(lb, _G.GameFontHighlight)
        lb._delta = ld.delta
        lb:SetPoint("TOPLEFT", c3, "TOPLEFT", ld.x, -27)
        lb:SetScript("OnClick", function()
            LFG:ApplyRelativeSoloLevelRange(ld.delta)
            LFG:NotifySideDrawerChange(false)
        end)
        drawer.lvlChipBtns[li] = lb
    end

    local minBox = Theme:CreateEditBox(c3, { height = 26, font = _G.GameFontHighlight, maxLetters = 3, numeric = true, placeholder = "1" })
    minBox:SetWidth(56)
    minBox:SetPoint("TOPLEFT", c3, "TOPLEFT", 416, -27)
    drawer.soloMinBox = minBox

    local dashFs = c3:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dashFs:SetPoint("LEFT", minBox, "RIGHT", 4, 0)
    dashFs:SetText("-")

    local maxBox = Theme:CreateEditBox(c3, { height = 26, font = _G.GameFontHighlight, maxLetters = 3, numeric = true, placeholder = "60" })
    maxBox:SetWidth(56)
    maxBox:SetPoint("LEFT", dashFs, "RIGHT", 4, 0)
    drawer.soloMaxBox = maxBox

    local function CommitLevels()
        if minBox._scSyncing or maxBox._scSyncing then return end
        local nMin = tonumber(minBox:GetText()) or 0
        local nMax = tonumber(maxBox:GetText()) or 0
        local curMin, curMax = LFG:GetSoloLevelRange()
        if nMin ~= curMin or nMax ~= curMax then
            LFG:SetSoloLevelRange(nMin, nMax)
            LFG:NotifySideDrawerChange(false)
        end
    end
    minBox:SetScript("OnEnterPressed", function(sb) sb:ClearFocus(); CommitLevels() end)
    maxBox:SetScript("OnEnterPressed", function(sb) sb:ClearFocus(); CommitLevels() end)
    minBox:SetScript("OnEditFocusLost", CommitLevels)
    maxBox:SetScript("OnEditFocusLost", CommitLevels)
    minBox:SetScript("OnEscapePressed", function(sb) sb:ClearFocus() end)
    maxBox:SetScript("OnEscapePressed", function(sb) sb:ClearFocus() end)

    drawer.archBtns = {}
    for ai, ad in ipairs({
        { id = "ALL",     lbl = L["All"] },
        { id = "TANKS",   lbl = L["Tanks"] },
        { id = "HEALERS", lbl = L["Healers"] },
        { id = "CASTERS", lbl = L["Casters"] },
        { id = "MELEE",   lbl = L["Melee"] },
        { id = "NONE",    lbl = L["None"] },
    }) do
        local ab = Theme:CreateButton(c3, 84, 24, ad.lbl, "default")
        SetDrawerBtnFont(ab, _G.GameFontHighlight)
        ab._archId = ad.id
        ab:SetPoint("TOPLEFT", c3, "TOPLEFT", 6 + ((ai - 1) * 90), -58)
        ab:SetScript("OnClick", function()
            LFG:SetSoloClassesArchetype(ad.id)
            LFG:NotifySideDrawerChange(false)
        end)
        drawer.archBtns[ai] = ab
    end

    drawer.classCrests = {}
    for ci, cf in ipairs(DRAWER_CLASS_ORDER) do
        local cb = CreateFrame("Button", nil, c3, "BackdropTemplate")
        cb:SetSize(55, 44)
        cb:SetPoint("TOPLEFT", c3, "TOPLEFT", 6 + ((ci - 1) * 60), -88)
        cb._classFile = cf
        local hl = cb:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1.0, 0.85, 0.35, 0.22)
        local ico = cb:CreateTexture(nil, "ARTWORK")
        ico:SetSize(24, 24)
        ico:SetPoint("TOP", cb, "TOP", 0, -4)
        SetDrawerClassIcon(ico, cf)
        cb.Icon = ico
        local tagFs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        tagFs:SetPoint("BOTTOM", cb, "BOTTOM", 0, 3)
        tagFs:SetJustifyH("CENTER")
        tagFs:SetText(Utf8ShortTag(LFG:GetClassName(cf), 3))
        cb.TagFs = tagFs
        cb:SetScript("OnClick", function()
            LFG:ToggleSoloClass(cf)
            LFG:NotifySideDrawerChange(false)
        end)
        cb:SetScript("OnEnter", function(selfBtn)
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:AddLine(LFG:GetClassName(cf), 1.0, 0.82, 0.0)
            GameTooltip:AddLine(L["Click to include or exclude this class when recruiting players."], 0.88, 0.90, 0.94, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        drawer.classCrests[ci] = cb
    end

    -- Card 4: Playstyle, Languages, Sort & Official Rules
    local c4 = CreateFrame("Frame", nil, m1, "BackdropTemplate")
    c4:SetPoint("TOPLEFT", m1, "TOPLEFT", 0, -366)
    c4:SetPoint("TOPRIGHT", m1, "TOPRIGHT", 0, -366)
    c4:SetHeight(68)
    drawer.miscCard = c4

    local shortPlay = {
        Learning = L["Learning"],
        FunRelaxed = L["Relaxed"],
        FunSerious = L["Competitive"],
        Expert = L["Carry"],
    }
    drawer.playBtns = {}
    for pi, ps in ipairs(LFG.PLAYSTYLES) do
        local pb = Theme:CreateButton(c4, 129, 26, shortPlay[ps.key] or L[ps.labelKey], "default")
        SetDrawerBtnFont(pb, _G.GameFontHighlight)
        pb._playKey = ps.key
        pb:SetPoint("TOPLEFT", c4, "TOPLEFT", 6 + ((pi - 1) * 135), -7)
        pb:SetScript("OnClick", function()
            LFG:TogglePlaystyle(ps.key)
            LFG:NotifySideDrawerChange(false)
        end)
        pb:SetScript("OnEnter", function(selfBtn)
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:AddLine(LFG:GetPlaystyleLabel(ps.key), 1.0, 0.82, 0.0)
            GameTooltip:AddLine(L["Filter listings matching this group playstyle."], 0.88, 0.90, 0.94, true)
            GameTooltip:Show()
        end)
        pb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        drawer.playBtns[pi] = pb
    end

    local langBtn = Theme:CreateButton(c4, 129, 26, L["Languages"], "default")
    SetDrawerBtnFont(langBtn, _G.GameFontHighlight)
    langBtn:SetPoint("TOPLEFT", c4, "TOPLEFT", 6, -37)
    langBtn:SetScript("OnClick", function(selfBtn) OpenLanguagesContextMenu(selfBtn) end)
    drawer.langBtn = langBtn

    local soloSortBtn = Theme:CreateButton(c4, 129, 26, L["Sort"], "default")
    SetDrawerBtnFont(soloSortBtn, _G.GameFontHighlight)
    soloSortBtn:SetPoint("LEFT", langBtn, "RIGHT", 6, 0)
    soloSortBtn:SetScript("OnClick", function(selfBtn) OpenSoloSortContextMenu(selfBtn) end)
    drawer.soloSortBtn = soloSortBtn

    local hideFullBtn = Theme:CreateButton(c4, 129, 26, L["Hide Full"], "default")
    SetDrawerBtnFont(hideFullBtn, _G.GameFontHighlight)
    hideFullBtn:SetPoint("LEFT", soloSortBtn, "RIGHT", 6, 0)
    hideFullBtn:SetScript("OnClick", function()
        if ns.db and ns.db.settings then
            ns.db.settings.lfgHideFullGroups = not (ns.db.settings.lfgHideFullGroups ~= false)
            if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
            LFG:NotifySideDrawerChange(false)
        end
    end)
    drawer.hideFullBtn = hideFullBtn

    local suitLevelBtn = Theme:CreateButton(c4, 129, 26, L["My Level"], "default")
    SetDrawerBtnFont(suitLevelBtn, _G.GameFontHighlight)
    suitLevelBtn:SetPoint("LEFT", hideFullBtn, "RIGHT", 6, 0)
    suitLevelBtn:SetScript("OnClick", function()
        local tab = LFG._sideDrawerHost or ns.LFGFrameTab
        if not tab then return end
        tab._hasSearchedThisSession = true
        tab.suitableLevelOnly = not (tab.suitableLevelOnly == true)
        if tab.suitableLevelOnly and tab.ApplyIdealActivitiesForCategory then
            tab:ApplyIdealActivitiesForCategory(tab.categoryFilter, true)
        elseif tab.browseActivityFilter then
            wipe(tab.browseActivityFilter)
        end
        LFG:NotifySideDrawerChange(true)
    end)
    drawer.suitLevelBtn = suitLevelBtn

    local foot = CreateFrame("Frame", nil, m1, "BackdropTemplate")
    foot:SetPoint("BOTTOMLEFT", m1, "BOTTOMLEFT", 0, 2)
    foot:SetPoint("BOTTOMRIGHT", m1, "BOTTOMRIGHT", 0, 2)
    foot:SetHeight(26)
    drawer.offFooter = foot
    local footFs = foot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footFs:SetPoint("LEFT", 8, 0)
    footFs:SetPoint("RIGHT", -8, 0)
    footFs:SetJustifyH("LEFT")
    footFs:SetWordWrap(false)
    footFs:SetText("|cff6ec1e4[" .. L["Official Blizzard"] .. "]|r " .. L["100% official game filters — works with all players on the realm."])
end

local function BuildDrawerSocialMode(drawer, parent)
    local Theme = ns.Theme
    local m2 = CreateFrame("Frame", nil, parent)
    m2:SetAllPoints(parent)
    m2:Hide()
    drawer.socialTab = m2

    local banner = CreateFrame("Frame", nil, m2, "BackdropTemplate")
    banner:SetPoint("TOPLEFT", m2, "TOPLEFT", 0, -4)
    banner:SetPoint("TOPRIGHT", m2, "TOPRIGHT", 0, -4)
    banner:SetHeight(40)
    drawer.socialBanner = banner
    local banFs = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    banFs:SetPoint("TOPLEFT", 8, -4)
    banFs:SetPoint("BOTTOMRIGHT", -8, 4)
    banFs:SetJustifyH("LEFT")
    banFs:SetJustifyV("MIDDLE")
    banFs:SetWordWrap(true)
    banFs:SetText("|cff3fb950[" .. L["Guild & Addon Only"] .. "]|r " .. L["Exclusive SocialCentral tools — synced with your Guild, Allied Guilds, Friends, Watchlist, and other addon users."])

    local srcCard = CreateFrame("Frame", nil, m2, "BackdropTemplate")
    srcCard:SetPoint("TOPLEFT", m2, "TOPLEFT", 0, -50)
    srcCard:SetPoint("TOPRIGHT", m2, "TOPRIGHT", 0, -50)
    srcCard:SetHeight(128)
    drawer.srcCard = srcCard

    local srcHdr = srcCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    srcHdr:SetPoint("TOPLEFT", 8, -7)
    srcHdr:SetText(L["Search Sources (Official vs Guild / Addon)"])

    local srcDefs = {
        { id = "ALL",         label = L["All (Official + Guild)"] },
        { id = "OFFICIAL",    label = L["Official Only"] .. " |cff6ec1e4[" .. L["Official"] .. "]|r" },
        { id = "CLAN",        label = L["My Guild"] .. " |cffffd24d[" .. L["Guild/Addon"] .. "]|r" },
        { id = "SC_USERS",    label = L["Addon Users Only"] .. " |cff3fb950[" .. L["Addon"] .. "]|r" },
        { id = "FRIENDS",     label = L["Friends & Watchlist"] .. " |cffd2a8ff[" .. L["Addon"] .. "]|r" },
        { id = "PUBLIC_CHAT", label = L["Global Chat / LFG"] .. " |cffb8c0cc[" .. L["Chat"] .. "]|r" },
    }
    drawer.srcBtns = {}
    for si, sd in ipairs(srcDefs) do
        local col = (si - 1) % 2
        local rowIdx = math.floor((si - 1) / 2)
        local sb = Theme:CreateButton(srcCard, 264, 28, sd.label, "default")
        SetDrawerBtnFont(sb, _G.GameFontHighlight)
        sb._srcId = sd.id
        sb:SetPoint("TOPLEFT", srcCard, "TOPLEFT", 6 + (col * 272), -29 - (rowIdx * 32))
        sb:SetScript("OnClick", function()
            local tab = LFG._sideDrawerHost or ns.LFGFrameTab
            if not tab then return end
            tab._hasSearchedThisSession = true
            tab.sourceFilter = sd.id
            if tab.SaveBrowseFilters then tab:SaveBrowseFilters() end
            if tab.RefreshData then tab:RefreshData() end
            LFG:RefreshSideDrawer(tab)
            ns:Emit("LFG_BROWSE_STATE_CHANGED")
        end)
        drawer.srcBtns[si] = sb
    end

    local favCard = CreateFrame("Frame", nil, m2, "BackdropTemplate")
    favCard:SetPoint("TOPLEFT", m2, "TOPLEFT", 0, -184)
    favCard:SetPoint("TOPRIGHT", m2, "TOPRIGHT", 0, -184)
    favCard:SetHeight(86)
    drawer.favCard = favCard

    local favTitle = favCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    favTitle:SetPoint("TOPLEFT", 8, -7)
    favTitle:SetText(STAR_TEX .. " " .. L["Favorite Activities"] .. " |cff3fb950[SocialCentral]|r")

    local favManageBtn = Theme:CreateButton(favCard, 156, 24, L["Manage Favorites"], "default")
    SetDrawerBtnFont(favManageBtn, _G.GameFontHighlight)
    Theme:AutoFitButton(favManageBtn, 128, 16, 196)
    favManageBtn:SetPoint("TOPRIGHT", -6, -5)
    favManageBtn:SetScript("OnClick", function(selfBtn)
        local tab = LFG._sideDrawerHost or ns.LFGFrameTab
        if not (MenuUtil and MenuUtil.CreateContextMenu and tab and tab.GetBrowseActivityOptions) then return end
        local cat = (tab.categoryFilter and tab.categoryFilter ~= "ALL") and tab.categoryFilter or "DUNGEONS"
        local opts = tab:GetBrowseActivityOptions(cat)
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            root:CreateTitle((tab.GetCategoryLabel and tab:GetCategoryLabel(cat)) or L["Favorite Activities"])
            for _, opt in ipairs(opts) do
                if root.CreateCheckbox then
                    root:CreateCheckbox(opt.label, function()
                        return LFG:IsFavoriteActivity(opt.key, opt.officialId)
                    end, function()
                        LFG:ToggleFavoriteActivity(opt.key, opt.officialId)
                        if tab.InvalidateBrowseActivityCache then tab:InvalidateBrowseActivityCache() end
                        LFG:NotifySideDrawerChange(false)
                    end)
                end
            end
        end)
    end)
    drawer.favManageBtn = favManageBtn

    local favEmptyFs = favCard:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    favEmptyFs:SetPoint("TOPLEFT", 8, -32)
    favEmptyFs:SetPoint("BOTTOMRIGHT", -8, 6)
    favEmptyFs:SetJustifyH("LEFT")
    favEmptyFs:SetJustifyV("MIDDLE")
    favEmptyFs:SetWordWrap(true)
    favEmptyFs:SetText(L["Click Manage Favorites to pin favorite dungeons here."])
    drawer.favEmptyFs = favEmptyFs

    drawer.favPills = {}
    for fi = 1, 4 do
        local col = (fi - 1) % 2
        local rowIdx = math.floor((fi - 1) / 2)
        local fb = Theme:CreateButton(favCard, 262, 24, "", "default")
        SetDrawerBtnFont(fb, _G.GameFontHighlight)
        fb:SetPoint("TOPLEFT", favCard, "TOPLEFT", 8 + (col * 270), -32 - (rowIdx * 26))
        fb:Hide()
        drawer.favPills[fi] = fb
    end

    local orgCard = CreateFrame("Frame", nil, m2, "BackdropTemplate")
    orgCard:SetPoint("TOPLEFT", m2, "TOPLEFT", 0, -276)
    orgCard:SetPoint("TOPRIGHT", m2, "TOPRIGHT", 0, -276)
    orgCard:SetHeight(116)
    drawer.orgCard = orgCard

    local orgHdr = orgCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    orgHdr:SetPoint("TOPLEFT", 8, -7)
    orgHdr:SetText(L["Organization & Safety"] .. " |cff3fb950[SocialCentral]|r")

    local orgDefs = {
        { id = "sep",   lbl = L["Separate Groups & Players"], w = 264, x = 6,   y = -29, fn = function()
            if ns.db and ns.db.settings then
                ns.db.settings.lfgSplitGroupsAndPlayers = not (ns.db.settings.lfgSplitGroupsAndPlayers ~= false)
            end
        end },
        { id = "bul",   lbl = L["Group by Dungeon (Bulletin)"], w = 264, x = 278, y = -29, fn = function()
            if ns.db and ns.db.settings then
                local curBull = (ns.db.settings.lfgSplitGroupsAndPlayers == false) and (ns.db.settings.lfgBulletinMode ~= false)
                local targetBull = not curBull
                ns.db.settings.lfgBulletinMode = targetBull
                ns.db.settings.lfgSplitGroupsAndPlayers = not targetBull
            end
        end },
        { id = "saved", lbl = L["Hide Saved Lockouts"], w = 264, x = 6,   y = -58, fn = function()
            if ns.db and ns.db.settings then
                ns.db.settings.lfgHideSavedLockouts = not (ns.db.settings.lfgHideSavedLockouts == true)
            end
        end },
        { id = "avoid", lbl = L["Hide Avoid / Enemy"], w = 264, x = 278, y = -58, fn = function()
            if ns.db and ns.db.settings then
                ns.db.settings.lfgHideAvoidEnemy = not (ns.db.settings.lfgHideAvoidEnemy == true)
            end
        end },
        { id = "cls",   lbl = L["Show member class icons"], w = 264, x = 6,   y = -87, fn = function()
            if ns.db and ns.db.settings then
                ns.db.settings.lfgShowClassIconsOnRows = not (ns.db.settings.lfgShowClassIconsOnRows ~= false)
            end
        end },
        { id = "autoopen", lbl = L["Auto-open on Listing"], w = 264, x = 278, y = -87, fn = function()
            if ns.db and ns.db.settings then
                ns.db.settings.lfgAutoOpenOnList = not (ns.db.settings.lfgAutoOpenOnList ~= false)
            end
        end },
    }
    drawer.orgBtns = {}
    for oi, od in ipairs(orgDefs) do
        local ob = Theme:CreateButton(orgCard, od.w, 26, od.lbl, "default")
        SetDrawerBtnFont(ob, _G.GameFontHighlight)
        ob._orgId = od.id
        ob:SetPoint("TOPLEFT", orgCard, "TOPLEFT", od.x, od.y)
        ob:SetScript("OnClick", function()
            od.fn()
            if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
            LFG:NotifySideDrawerChange(false)
        end)
        drawer.orgBtns[oi] = ob
    end

    local rateCard = CreateFrame("Frame", nil, m2, "BackdropTemplate")
    rateCard:SetPoint("TOPLEFT", m2, "TOPLEFT", 0, -398)
    rateCard:SetPoint("TOPRIGHT", m2, "TOPRIGHT", 0, -398)
    rateCard:SetPoint("BOTTOM", m2, "BOTTOM", 0, 4)
    drawer.rateCard = rateCard

    local rateHdr = rateCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rateHdr:SetPoint("TOPLEFT", 8, -8)
    rateHdr:SetText(L["Whispers & Player Ratings"] .. " |cff3fb950[SocialCentral]|r")

    local rateSummaryFs = rateCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rateSummaryFs:SetPoint("TOPRIGHT", -8, -8)
    rateSummaryFs:SetJustifyH("RIGHT")
    drawer.rateSummaryFs = rateSummaryFs

    local tplModalBtn = Theme:CreateButton(rateCard, 264, 28, L["Whisper Templates (/w)..."], "default")
    SetDrawerBtnFont(tplModalBtn, _G.GameFontHighlight)
    tplModalBtn:SetPoint("BOTTOMLEFT", rateCard, "BOTTOMLEFT", 6, 8)
    tplModalBtn:SetScript("OnClick", function()
        if ns.LFGFrameTab and ns.LFGFrameTab.OpenWhisperTemplateModal then
            ns.LFGFrameTab:OpenWhisperTemplateModal()
        end
    end)
    drawer.tplModalBtn = tplModalBtn

    local openRatingsBtn = Theme:CreateButton(rateCard, 264, 28, L["Open Recent & Ratings"], "default")
    SetDrawerBtnFont(openRatingsBtn, _G.GameFontHighlight)
    openRatingsBtn:SetPoint("BOTTOMRIGHT", rateCard, "BOTTOMRIGHT", -6, 8)
    openRatingsBtn:SetScript("OnClick", function()
        if ns.UI and ns.UI.OpenGroupRecentView then
            ns.UI:OpenGroupRecentView()
        elseif ns.UI and ns.UI.OpenTab then
            ns.UI:OpenTab("group")
        end
    end)
    drawer.openRatingsBtn = openRatingsBtn
end

local function RefreshDrawerOfficialMode(d, tab)
    local Theme = ns.Theme
    if Theme and Theme.ApplyBackdrop then
        for _, card in ipairs({ d.goalCard, d.compCard, d.recruitCard, d.miscCard }) do
            if card then Theme:ApplyBackdrop(card, "surface") end
        end
        if d.offFooter then Theme:ApplyBackdrop(d.offFooter, "inset") end
        for _, rc in ipairs(d.roleMatrixCards or {}) do
            Theme:ApplyBackdrop(rc, "inset")
        end
    end
    local curType = LFG:GetListingType()
    if Theme and Theme.StyleButton then
        for _, ib in ipairs(d.intentBtns or {}) do
            Theme:StyleButton(ib, (ib._typeId == curType) and "primary" or "default")
        end
        Theme:StyleButton(d.searchBtn, "primary")
        Theme:StyleButton(d.preBtn, "default")
        Theme:SetButtonText(d.preBtn, (#LFG:GetPresets() > 0) and (L["Presets"] .. " (" .. #LFG:GetPresets() .. ")") or L["Presets"])
        Theme:StyleButton(d.resetBtn, "danger")
        Theme:StyleButton(d.roleCheckBtn, "default")
    end

    local gQuests = (ns.Clan and ns.Clan.GetActiveGroupQuests) and ns.Clan:GetActiveGroupQuests() or {}
    if d.questBtn then
        if #gQuests > 0 then
            if Theme then
                Theme:SetButtonText(d.questBtn, L["Quests (%d)"]:format(#gQuests))
                Theme:StyleButton(d.questBtn, "default")
            end
            d.questBtn:Show()
        else
            d.questBtn:Hide()
        end
    end

    for _, rc in ipairs(d.roleMatrixCards or {}) do
        local stVal = LFG:GetRoleState(rc._roleId)
        for _, sb in ipairs(rc.segBtns or {}) do
            local isSel = (sb._segVal == stVal)
            if Theme and Theme.StyleButton then
                Theme:StyleButton(sb, isSel and "primary" or "default")
            end
            if sb.SetBackdropBorderColor and isSel then
                if stVal == 1 then
                    sb:SetBackdropBorderColor(0.28, 0.92, 0.50, 0.98)
                elseif stVal == 2 then
                    sb:SetBackdropBorderColor(1.0, 0.82, 0.24, 0.98)
                end
            end
        end
    end

    local myCf = LFG:GetMyClassFile()
    local exclMine = (myCf ~= "" and LFG:IsGroupClassExcluded(myCf))
    local exCnt = CountBoolSet(LFG:GetCharState().groupExcludedClasses)
    if Theme then
        if d.avoidMyClsBtn then
            local myLoc = (myCf ~= "") and LFG:GetClassName(myCf) or ""
            local avTxt = (myLoc ~= "") and L["No My Class (%s)"]:format(myLoc) or L["No My Class"]
            Theme:SetButtonText(d.avoidMyClsBtn, avTxt)
            Theme:StyleButton(d.avoidMyClsBtn, exclMine and "danger" or "default")
        end
        if d.exclDropBtn then
            local eLbl = L["Exclude Other Classes..."]
            if exCnt == 1 then
                eLbl = L["No %s"]:format(LFG:GetClassName(next(LFG:GetCharState().groupExcludedClasses)))
            elseif exCnt > 1 then
                eLbl = L["No %d classes"]:format(exCnt)
            end
            Theme:SetButtonText(d.exclDropBtn, eLbl)
            Theme:StyleButton(d.exclDropBtn, (exCnt > 0 and exCnt < #LFG.CLASSIC_CLASSES) and "danger" or "default")
        end
    end

    for _, rb in ipairs(d.soloRoleBtns or {}) do
        if Theme and Theme.StyleButton then
            Theme:StyleButton(rb, LFG:GetSoloRoleAllowed(rb._roleId) and "primary" or "default")
        end
    end

    local minL, maxL = LFG:GetSoloLevelRange()
    local myLvl = Safe.Number(Safe.Call(UnitLevel, "player")) or 60
    for _, lb in ipairs(d.lvlChipBtns or {}) do
        local active = false
        if lb._delta == 0 then
            active = (minL == 0 and maxL == 0)
        else
            active = (minL == math.max(1, myLvl - lb._delta)) and (maxL == math.min(255, myLvl + lb._delta))
        end
        if Theme and Theme.StyleButton then
            Theme:StyleButton(lb, active and "primary" or "default")
        end
    end
    if Theme and Theme.StyleEditBox then
        Theme:StyleEditBox(d.soloMinBox)
        Theme:StyleEditBox(d.soloMaxBox)
    end
    if d.soloMinBox and d.soloMinBox.HasFocus and not d.soloMinBox:HasFocus() then
        d.soloMinBox._scSyncing = true
        d.soloMinBox:SetText((minL > 0) and tostring(minL) or "")
        d.soloMinBox._scSyncing = false
    end
    if d.soloMaxBox and d.soloMaxBox.HasFocus and not d.soloMaxBox:HasFocus() then
        d.soloMaxBox._scSyncing = true
        d.soloMaxBox:SetText((maxL > 0) and tostring(maxL) or "")
        d.soloMaxBox._scSyncing = false
    end

    local selClsCnt = CountSelectedSoloClasses()
    for _, ab in ipairs(d.archBtns or {}) do
        local isArch = false
        if ab._archId == "ALL" then
            isArch = (selClsCnt == #LFG.CLASSIC_CLASSES)
        elseif ab._archId == "NONE" then
            isArch = (selClsCnt == 0)
        else
            local tbl = SOLO_ARCHETYPE_CLASSES[ab._archId]
            if tbl then
                isArch = true
                for _, cf in ipairs(LFG.CLASSIC_CLASSES) do
                    if (LFG:IsSoloClassSelected(cf) == true) ~= (tbl[cf] == true) then
                        isArch = false
                        break
                    end
                end
            end
        end
        if Theme and Theme.StyleButton then
            Theme:StyleButton(ab, isArch and "primary" or "default")
        end
    end

    for _, cb in ipairs(d.classCrests or {}) do
        local cf = cb._classFile
        local isSel = LFG:IsSoloClassSelected(cf)
        if Theme and Theme.ApplyBackdrop then
            Theme:ApplyBackdrop(cb, "inset")
        end
        if cb.Icon then
            cb.Icon:SetDesaturated(not isSel)
            cb.Icon:SetAlpha(isSel and 1.0 or 0.28)
        end
        local cc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[cf]
        if cb.TagFs then
            if isSel and cc then
                cb.TagFs:SetTextColor(cc.r or 1, cc.g or 0.85, cc.b or 0.35, 1)
            elseif isSel then
                cb.TagFs:SetTextColor(1, 0.85, 0.35, 1)
            else
                cb.TagFs:SetTextColor(0.45, 0.48, 0.54, 0.85)
            end
        end
        if cb.SetBackdropBorderColor then
            if isSel and cc then
                cb:SetBackdropBorderColor(cc.r or 1, cc.g or 0.82, cc.b or 0.25, 0.95)
            elseif isSel then
                cb:SetBackdropBorderColor(0.95, 0.80, 0.28, 0.95)
            else
                cb:SetBackdropBorderColor(0.28, 0.24, 0.20, 0.40)
            end
        end
    end

    if Theme and Theme.StyleButton then
        for _, pb in ipairs(d.playBtns or {}) do
            Theme:StyleButton(pb, LFG:IsPlaystyleSelected(pb._playKey) and "primary" or "default")
        end
        local langs = LFG:GetAvailableLanguages()
        local locked = LFG:GetLockedLanguages()
        local langCnt = 0
        for _, c in ipairs(langs) do
            if (not locked[c]) and LFG:IsLanguageSelected(c) then langCnt = langCnt + 1 end
        end
        Theme:SetButtonText(d.langBtn, (langCnt > 0) and (L["Languages"] .. " (" .. langCnt .. ")") or L["Languages"])
        Theme:StyleButton(d.langBtn, (langCnt > 0) and "primary" or "default")

        local curSort = LFG:GetSoloSortOrder()
        for _, ord in ipairs(LFG.SOLO_SORT_ORDERS) do
            if ord.id == curSort then
                Theme:SetButtonText(d.soloSortBtn, L[ord.labelKey])
                break
            end
        end
        Theme:StyleButton(d.soloSortBtn, "default")

        local sCfg = ns.db and ns.db.settings
        Theme:StyleButton(d.hideFullBtn, ((not sCfg) or sCfg.lfgHideFullGroups ~= false) and "primary" or "default")
        Theme:StyleButton(d.suitLevelBtn, (tab and tab.suitableLevelOnly == true) and "primary" or "default")
    end

    local inGroup = Compat.IsInGroup and Compat.IsInGroup()
    local canLead = inGroup and ((Compat.IsGroupLeader and Compat.IsGroupLeader("player")) or (Compat.IsGroupAssistant and Compat.IsGroupAssistant("player")))
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    d.roleCheckBtn:SetEnabled((canLead == true) and (not inCombat))
    if d.compCard then
        d.compCard:SetAlpha((curType == "SOLO") and 0.58 or 1.0)
    end
    if d.recruitCard then
        d.recruitCard:SetAlpha((curType == "GROUPS") and 0.58 or 1.0)
    end
end

local function RefreshDrawerSocialMode(d, tab)
    local Theme = ns.Theme
    if Theme and Theme.ApplyBackdrop then
        if d.socialBanner then Theme:ApplyBackdrop(d.socialBanner, "inset") end
        for _, card in ipairs({ d.srcCard, d.favCard, d.orgCard, d.rateCard }) do
            if card then Theme:ApplyBackdrop(card, "surface") end
        end
    end
    local curSrc = (tab and tab.sourceFilter) or "ALL"
    if Theme and Theme.StyleButton then
        for _, sb in ipairs(d.srcBtns or {}) do
            Theme:StyleButton(sb, (sb._srcId == curSrc) and "primary" or "default")
        end
        Theme:StyleButton(d.favManageBtn, "default")
        Theme:StyleButton(d.tplModalBtn, "default")
        Theme:StyleButton(d.openRatingsBtn, "default")
    end

    local cat = (tab and tab.categoryFilter) or "ALL"
    local favOpts, seenFav = {}, {}
    if tab and tab.GetBrowseActivityOptions then
        local catsToScan = (cat ~= "ALL") and { cat } or { "DUNGEONS", "RAIDS", "QUESTS", "PVP", "CUSTOM" }
        for _, cId in ipairs(catsToScan) do
            local opts = tab:GetBrowseActivityOptions(cId)
            for _, opt in ipairs(opts) do
                if (opt.isFavorite or LFG:IsFavoriteActivity(opt.key, opt.officialId)) and not seenFav[opt.key] then
                    seenFav[opt.key] = true
                    favOpts[#favOpts + 1] = opt
                    if #favOpts >= 4 then break end
                end
            end
            if #favOpts >= 4 then break end
        end
    end
    d.favEmptyFs:SetShown(#favOpts == 0)
    for fi = 1, 4 do
        local fb = d.favPills[fi]
        local opt = favOpts[fi]
        if fb and opt and Theme then
            local isSel = (tab and tab.browseActivityFilter and tab.browseActivityFilter[opt.key] ~= nil)
            local lbl = opt.label or "?"
            if #lbl > 34 then lbl = lbl:sub(1, 32) .. ".." end
            Theme:SetButtonText(fb, STAR_TEX .. " " .. lbl)
            Theme:StyleButton(fb, isSel and "primary" or "default")
            fb:SetScript("OnClick", function()
                if not tab then return end
                tab._hasSearchedThisSession = true
                if tab.browseActivityFilter[opt.key] then
                    tab.browseActivityFilter[opt.key] = nil
                else
                    tab.browseActivityFilter[opt.key] = opt
                end
                LFG:NotifySideDrawerChange(true)
            end)
            fb:Show()
        elseif fb then
            fb:Hide()
        end
    end

    local sCfg = ns.db and ns.db.settings
    local isSplit = (not sCfg) or sCfg.lfgSplitGroupsAndPlayers ~= false
    local isBull = (not isSplit) and ((not sCfg) or sCfg.lfgBulletinMode ~= false)
    local orgActive = {
        sep = isSplit,
        bul = isBull,
        saved = (sCfg and sCfg.lfgHideSavedLockouts == true) == true,
        avoid = (sCfg and sCfg.lfgHideAvoidEnemy == true) == true,
        cls = ((not sCfg) or sCfg.lfgShowClassIconsOnRows ~= false),
        autoopen = ((not sCfg) or sCfg.lfgAutoOpenOnList ~= false),
    }
    if Theme and Theme.StyleButton then
        for _, ob in ipairs(d.orgBtns or {}) do
            Theme:StyleButton(ob, orgActive[ob._orgId] and "primary" or "default")
        end
    end

    local goodCnt, avoidCnt = 0, 0
    local mTbl = (Store and Store.GetSocialMetaTable) and Store:GetSocialMetaTable() or nil
    if type(mTbl) == "table" then
        for _, meta in pairs(mTbl) do
            if type(meta) == "table" then
                if meta.flag == "GOOD" then goodCnt = goodCnt + 1
                elseif meta.flag == "AVOID" then avoidCnt = avoidCnt + 1 end
            end
        end
    end
    if d.rateSummaryFs then
        d.rateSummaryFs:SetText(L["Rated: %s Good · %s Avoid"]:format("|cff3fb950" .. goodCnt .. "|r", "|cffff4d4d" .. avoidCnt .. "|r"))
    end
end

function LFG:GetSideDrawer()
    local d = self._sideDrawer
    if d then return d end
    local Theme = ns.Theme
    if not Theme then return nil end

    d = CreateFrame("Frame", "SocialCentralLFGSideDrawer", UIParent, "BackdropTemplate")
    d:Hide()
    d:SetSize(DRAWER_W, DRAWER_H)
    d:SetClampedToScreen(true)
    d:EnableMouse(true)
    table.insert(UISpecialFrames, "SocialCentralLFGSideDrawer")

    local bg = d:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(d)
    bg:SetTexture(WHITE8X8)
    bg:SetVertexColor(0.08, 0.075, 0.07, 1.0)
    d._solidOpaqueBg = bg

    local container = CreateFrame("Frame", nil, d)
    container:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -76)
    container:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -8, 8)
    d.container = container

    BuildDrawerHeader(d)
    BuildDrawerOfficialMode(d, container)
    BuildDrawerSocialMode(d, container)
    SelectDrawerMode(d, "official")

    self._sideDrawer = d
    return d
end

function LFG:IsSideDrawerShown()
    return (self._sideDrawer and self._sideDrawer.IsShown and self._sideDrawer:IsShown()) == true
end

function LFG:PositionSideDrawer(hostTab)
    local d = self._sideDrawer
    if not d then return false end
    local tab = hostTab or self._sideDrawerHost or ns.LFGFrameTab
    self._sideDrawerHost = tab
    local subPanel = tab and tab.subPanel
    local lfgHost = _G.LFGParentFrame
    local useLfgHost = (subPanel ~= nil and lfgHost ~= nil and subPanel:GetParent() == lfgHost and lfgHost.IsShown and lfgHost:IsShown() and subPanel.IsShown and subPanel:IsShown())
    local mainFrame = _G.SocialCentralFrame
    local anchorHost = nil
    if useLfgHost then
        anchorHost = lfgHost
        if not lfgHost._scSideDrawerMoveHooked and type(lfgHost.StopMovingOrSizing) == "function" and hooksecurefunc then
            lfgHost._scSideDrawerMoveHooked = true
            hooksecurefunc(lfgHost, "StopMovingOrSizing", function()
                if LFG:IsSideDrawerShown() then
                    LFG:PositionSideDrawer(LFG._sideDrawerHost)
                end
            end)
        end
    elseif tab and tab.standaloneHost and tab.standaloneHost.IsShown and tab.standaloneHost:IsShown() then
        anchorHost = tab.standaloneHost
    elseif subPanel and subPanel.IsShown and subPanel:IsShown() then
        anchorHost = subPanel
    elseif mainFrame and mainFrame.IsShown and mainFrame:IsShown() then
        anchorHost = mainFrame
        if not mainFrame._scSideDrawerMoveHooked and type(mainFrame.StopMovingOrSizing) == "function" and hooksecurefunc then
            mainFrame._scSideDrawerMoveHooked = true
            hooksecurefunc(mainFrame, "StopMovingOrSizing", function()
                if LFG:IsSideDrawerShown() then
                    LFG:PositionSideDrawer(LFG._sideDrawerHost)
                end
            end)
        end
    end
    if not anchorHost then
        d:Hide()
        return false
    end
    local rightGap = 4
    if useLfgHost then
        rightGap = 62
        local sideTab = (tab and tab.sideTab) or _G.SocialCentralLFGSideTab
        if sideTab and sideTab.IsShown and sideTab:IsShown() and sideTab.GetRight and anchorHost.GetRight then
            local tabRight = sideTab:GetRight()
            local hostR = anchorHost:GetRight()
            if tabRight and hostR and tabRight > hostR then
                rightGap = math.max(rightGap, math.ceil(tabRight - hostR) + 6)
            end
        end
    end
    local topOff = useLfgHost and -2 or 0
    local uiW = (_G.UIParent and _G.UIParent.GetWidth and _G.UIParent:GetWidth()) or 1280
    local hostRight = (anchorHost.GetRight and anchorHost:GetRight()) or 0
    local flipLeft = (hostRight + rightGap + DRAWER_W) > (uiW - 8)

    d:ClearAllPoints()
    d:SetSize(DRAWER_W, DRAWER_H)
    if flipLeft then
        d:SetPoint("TOPRIGHT", anchorHost, "TOPLEFT", -4, topOff)
    else
        d:SetPoint("TOPLEFT", anchorHost, "TOPRIGHT", rightGap, topOff)
    end
    local strata = (anchorHost.GetFrameStrata and anchorHost:GetFrameStrata()) or "MEDIUM"
    d:SetFrameStrata(strata)
    local baseBodyLvl = (tab and tab.controls and tab.controls.body and tab.controls.body.GetFrameLevel and tab.controls.body:GetFrameLevel())
        or ((anchorHost.GetFrameLevel and anchorHost:GetFrameLevel()) or 10)
    d:SetFrameLevel(math.min(4500, baseBodyLvl + 20))
    return true
end

function LFG:RefreshSideDrawer(hostTab)
    local d = self._sideDrawer
    if not (d and d:IsShown()) then return end
    local Theme = ns.Theme
    local tab = hostTab or self._sideDrawerHost or ns.LFGFrameTab
    self._sideDrawerHost = tab

    local p = Theme and Theme.GetPalette and Theme:GetPalette() or nil
    if d._solidOpaqueBg then
        local wBg = (p and p.windowBg) or { 0.08, 0.075, 0.07, 1.0 }
        d._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
    end
    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(d, "window", p)
    end
    if d.titleFs then
        local gc = (p and (p.textGold or p.accent)) or { 1.0, 0.82, 0.25 }
        d.titleFs:SetTextColor(gc[1], gc[2], gc[3])
    end
    local advCnt = self:CountActiveAdvancedFilters()
    if d.badgeFs then
        d.badgeFs:SetText(advCnt > 0 and ("|cff3fb950" .. L["%d filters"]:format(advCnt) .. "|r") or "")
    end
    if Theme and Theme.StyleButton then
        Theme:StyleButton(d.closeBtn, "default")
    end
    if d.helpBtn and d.helpBtn.RefreshTheme then d.helpBtn:RefreshTheme() end
    SelectDrawerMode(d, d._activeTab or "official")

    RefreshDrawerOfficialMode(d, tab)
    RefreshDrawerSocialMode(d, tab)

    if Theme and Theme.SyncSubtreeLayers then
        Theme:SyncSubtreeLayers(d, 10)
    end
end

function LFG:ShowSideDrawer(hostTab)
    local d = self:GetSideDrawer()
    if not d then return end
    self._sideDrawerHost = hostTab or self._sideDrawerHost or ns.LFGFrameTab
    if not self:PositionSideDrawer(self._sideDrawerHost) then
        return
    end
    d:Show()
    if d.Raise then
        d:Raise()
    end
    self:RefreshSideDrawer(self._sideDrawerHost)
end

function LFG:HideSideDrawer()
    if self._sideDrawer and self._sideDrawer.IsShown and self._sideDrawer:IsShown() then
        self._sideDrawer:Hide()
    end
end

function LFG:ToggleSideDrawer(hostTab)
    if self:IsSideDrawerShown() then
        self:HideSideDrawer()
    else
        self:ShowSideDrawer(hostTab)
    end
    if ns.db and ns.db.settings then
        ns.db.settings.lfgSideDrawerOpen = self:IsSideDrawerShown()
    end
    if ns.LFGFrameTab and ns.LFGFrameTab.RefreshData then
        ns.LFGFrameTab:RefreshData()
    end
end

function LFG:Init()
    self:GetCharState()
    local Theme = ns.Theme
    if Theme and Theme.RegisterListener then
        Theme:RegisterListener(function()
            if LFG:IsSideDrawerShown() then
                LFG:RefreshSideDrawer()
            end
        end)
    end
end
