local ADDON_NAME, ns = ...
local L = ns.L
local Safe = ns.Safe
local Compat = ns.Compat

local LootRoll = {
    activeRolls = {},
    rollOrder = {},
    recentRolls = {},
    simHistory = {},
    chatRollSessions = {},
    lastGroupRollItem = nil,
    unreadResultsCount = 0,
    maxRecent = 40,
    maxHistory = 80,
    maxChatRollSessions = 20,
    _lastWinSoundAt = 0,
    _inDungeonOrRaid = false,
    _postRunVisibleUntil = nil,
    _postRunHideTok = 0,
}
local POST_RUN_VISIBLE_SEC = 180
ns.LootRoll = LootRoll
table.insert(ns.modules, LootRoll)

-- Avoid banned legacy globals directly by resolving C_Item APIs safely.
local CItemStatsFn = C_Item and C_Item.GetItemStats
local CItemInstantFn = C_Item and C_Item.GetItemInfoInstant
local CItemNameFn = C_Item and C_Item.GetItemNameByID
local CItemIconFn = C_Item and C_Item.GetItemIconByID
local CItemQualityFn = C_Item and C_Item.GetItemQualityByID
local CItemDetailIlvlFn = C_Item and C_Item.GetDetailedItemLevelInfo
local CItemReqLoadFn = C_Item and C_Item.RequestLoadItemDataByID
local CItemCountFn = C_Item and C_Item.GetItemCount
local CItemUniquenessFn = C_Item and C_Item.GetItemUniquenessByID

local function LowerUtf8Safe(text)
    if type(text) ~= "string" then return "" end
    if Compat and Compat.LowerUtf8 then
        return Compat.LowerUtf8(text)
    end
    return text:lower()
end

local EQUIP_LOC_SLOTS = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_SHIELD = { 17 },
    INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}

-- Classic / Forever class armor & weapon proficiency matrix (zero tooltip scans).
local CLASS_MAX_ARMOR = {
    MAGE = 1,
    PRIEST = 1,
    WARLOCK = 1,
    ROGUE = 2,
    DRUID = 2,
    HUNTER = 3,
    SHAMAN = 3,
    WARRIOR = 4,
    PALADIN = 4,
}
local CLASS_SHIELD_OK = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local CLASS_RELIC_SUBCLASS = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN", [10] = "DEATHKNIGHT" }
local CLASS_WEAPON_PROF = {
    WARRIOR = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true, [16] = true, [18] = true, [20] = true },
    PALADIN = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [20] = true },
    HUNTER = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true, [16] = true, [18] = true, [20] = true },
    ROGUE = { [0] = true, [2] = true, [3] = true, [4] = true, [7] = true, [13] = true, [15] = true, [16] = true, [18] = true, [20] = true },
    PRIEST = { [4] = true, [10] = true, [15] = true, [19] = true, [20] = true },
    SHAMAN = { [0] = true, [1] = true, [4] = true, [5] = true, [10] = true, [13] = true, [15] = true, [20] = true },
    MAGE = { [7] = true, [10] = true, [15] = true, [19] = true, [20] = true },
    WARLOCK = { [7] = true, [10] = true, [15] = true, [19] = true, [20] = true },
    DRUID = { [4] = true, [5] = true, [6] = true, [10] = true, [13] = true, [15] = true, [20] = true },
}

local function CanPlayerDualWield(classFile, playerLevel)
    if classFile == "ROGUE" then
        return (playerLevel or 1) >= 10
    elseif classFile == "WARRIOR" or classFile == "HUNTER" then
        if IsSpellKnown and Safe.Bool(Safe.Call(IsSpellKnown, 674)) == true then
            return true
        end
        return (playerLevel or 1) >= 20
    elseif classFile == "SHAMAN" then
        if IsSpellKnown and (Safe.Bool(Safe.Call(IsSpellKnown, 30798)) == true or Safe.Bool(Safe.Call(IsSpellKnown, 674)) == true) then
            return true
        end
        return false
    end
    return false
end

local function EvaluateItemUsability(classID, subClassID, equipLoc)
    local pCls
    if UnitClass then
        local _, rawCls = UnitClass("player")
        pCls = Safe.String(rawCls)
    end
    local pLvl = (UnitLevel and Safe.Number(Safe.Call(UnitLevel, "player"))) or 60
    if not pCls or pCls == "" then
        return true, false, nil
    end
    if classID == 4 then
        -- Cloaks are armor subClass 1 (Cloth) but usable and optimal by every class.
        if equipLoc == "INVTYPE_CLOAK" or subClassID == 0 or subClassID == nil then
            return true, false, nil
        end
        if subClassID == 6 then
            if CLASS_SHIELD_OK[pCls] then
                return true, false, nil
            end
            return false, false, L["Cannot equip"]
        end
        if CLASS_RELIC_SUBCLASS[subClassID] then
            if CLASS_RELIC_SUBCLASS[subClassID] == pCls then
                return true, false, nil
            end
            return false, false, L["Wrong class"]
        end
        if subClassID >= 1 and subClassID <= 4 then
            local maxArmor = CLASS_MAX_ARMOR[pCls] or 4
            local curMax = maxArmor
            if (pCls == "HUNTER" or pCls == "SHAMAN") and pLvl < 40 then
                curMax = 2
            elseif (pCls == "WARRIOR" or pCls == "PALADIN") and pLvl < 40 then
                curMax = 3
            end
            if subClassID > curMax then
                if subClassID <= maxArmor then
                    return false, false, L["Unlocks at Lv 40"]
                end
                return false, false, L["Cannot equip"]
            end
            if subClassID < curMax and curMax >= 3 then
                -- Cloth on Mail/Plate or Leather on Plate: equippable, but flag as lighter armor tier
                if (curMax == 4 and subClassID <= 2) or (curMax == 3 and subClassID == 1) then
                    return true, true, L["Lighter armor"]
                end
            end
            return true, false, nil
        end
    elseif classID == 2 then
        if subClassID == 20 then
            return true, false, nil -- Fishing pole
        end
        local profMap = CLASS_WEAPON_PROF[pCls]
        if profMap and subClassID ~= nil and not profMap[subClassID] then
            return false, false, L["Cannot equip"]
        end
    end
    return true, false, nil
end

local function DecodeIneligibleReason(rawCode, deSkillRequired)
    local num = Safe.Number(rawCode)
    if num and num > 0 then
        local gKey = "LOOT_ROLL_INELIGIBLE_REASON" .. tostring(num)
        local gTxt = Safe.String(_G[gKey])
        if gTxt and gTxt ~= "" then
            if num == 4 and deSkillRequired and deSkillRequired > 0 and gTxt:find("%%d") then
                local okFmt, res = pcall(string.format, gTxt, deSkillRequired)
                if okFmt and type(res) == "string" then
                    return res
                end
            end
            return gTxt
        end
    end
    local str = Safe.String(rawCode)
    if str and str ~= "" and not str:match("^%d+$") then
        return str
    end
    return nil
end

local function GetSlotDisplayLabel(slotId, equipLoc)
    if slotId == 11 then return L["Ring 1"] end
    if slotId == 12 then return L["Ring 2"] end
    if slotId == 13 then return L["Trinket 1"] end
    if slotId == 14 then return L["Trinket 2"] end
    if slotId == 16 and equipLoc == "INVTYPE_WEAPON" then return L["Main Hand"] end
    if slotId == 17 and equipLoc == "INVTYPE_WEAPON" then return L["Off Hand"] end
    return nil
end

local STAT_ORDER = {
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 0,
    RESISTANCE0_NAME = 1,
    ITEM_MOD_ARMOR_SHORT = 1,
    ITEM_MOD_STAMINA_SHORT = 2,
    ITEM_MOD_STRENGTH_SHORT = 3,
    ITEM_MOD_AGILITY_SHORT = 4,
    ITEM_MOD_INTELLECT_SHORT = 5,
    ITEM_MOD_SPIRIT_SHORT = 6,
    ITEM_MOD_ATTACK_POWER_SHORT = 7,
    ITEM_MOD_SPELL_POWER_SHORT = 8,
    ITEM_MOD_CRIT_RATING_SHORT = 9,
    ITEM_MOD_HASTE_RATING_SHORT = 10,
    ITEM_MOD_HIT_RATING_SHORT = 11,
    ITEM_MOD_EXPERTISE_RATING_SHORT = 12,
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = 13,
    ITEM_MOD_MASTERY_RATING_SHORT = 14,
    ITEM_MOD_VERSATILITY = 15,
    ITEM_MOD_DODGE_RATING_SHORT = 16,
    ITEM_MOD_PARRY_RATING_SHORT = 17,
    ITEM_MOD_BLOCK_RATING_SHORT = 18,
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 19,
    ITEM_MOD_RESILIENCE_RATING_SHORT = 20,
}

local CHOICE_COLORS = {
    NEED = "|cff47ef66",
    GREED = "|cffffd24d",
    DE = "|cffc084fc",
    PASS = "|cff8b949e",
    WON = "|cff58a6ff",
    MASTER = "|cffff9f43",
}

local CHOICE_PRIORITY = {
    MASTER = 4,
    NEED = 3,
    GREED = 2,
    DE = 2,
    PASS = 1,
}

local function ResolveSafeItemMeta(itemId)
    local iName = CItemNameFn and Safe.String(Safe.Call(CItemNameFn, itemId)) or nil
    local iQual = CItemQualityFn and Safe.Number(Safe.Call(CItemQualityFn, itemId)) or nil
    local iTex = CItemIconFn and Safe.Value(Safe.Call(CItemIconFn, itemId)) or nil
    if (not iTex) and CItemInstantFn then
        local okIns, _, _, _, _, txIns = pcall(CItemInstantFn, itemId)
        if okIns then
            iTex = Safe.Value(txIns)
        end
    end
    return iName, iQual, iTex
end

local function GetSafeItemInstantInfo(itemRef)
    if not itemRef or not CItemInstantFn then
        return nil, nil, nil, nil, nil, nil, nil
    end
    local ok, id, iType, iSubType, iLoc, iTex, cId, scId = pcall(CItemInstantFn, itemRef)
    if not ok then
        return nil, nil, nil, nil, nil, nil, nil
    end
    return Safe.Number(id), Safe.String(iType), Safe.String(iSubType), Safe.String(iLoc), Safe.Value(iTex), Safe.Number(cId), Safe.Number(scId)
end

local function GetSafeOwnedCount(itemID)
    if not itemID then return 0 end
    local fn = CItemCountFn or _G.GetItemCount
    if not fn then return 0 end
    local ok, cnt = pcall(fn, itemID, true)
    if ok then
        return Safe.Number(cnt) or 0
    end
    return 0
end

local function ExtractItemIdFromLink(itemLink)
    if type(itemLink) ~= "string" then return nil end
    local idStr = itemLink:match("Hitem:(%d+)")
    if not idStr then
        idStr = itemLink:match("^item:(%d+)")
    end
    return idStr and tonumber(idStr) or nil
end

local function EscapeLuaPattern(text)
    return (text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function ExtractFirstItemLink(msg)
    if type(msg) ~= "string" then return nil end
    return msg:match("(|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h.-|h|r)")
        or msg:match("(|cn[^|]+:|Hitem:[^|]+|h.-|h|r)")
        or msg:match("(|Hitem:[^|]+|h.-|h)")
end

local function IsSelfPronounToken(name)
    if type(name) ~= "string" or name == "" then return false end
    if _G.YOU and name == _G.YOU then return true end
    local low = LowerUtf8Safe(name)
    return low == "you" or low == "você" or low == "voce" or low == "tú" or low == "tu"
end

local function ResolveSafeInstanceContext()
    if not IsInInstance then
        return false, nil, nil
    end
    local ok, inInst, instType = pcall(IsInInstance)
    if not ok or Safe.Value(inInst) ~= true then
        return false, nil, nil
    end
    local cleanType = Safe.String(instType)
    if cleanType ~= "party" and cleanType ~= "raid" then
        return false, cleanType, nil
    end
    local instName = nil
    if GetInstanceInfo then
        local okInfo, rawName = pcall(GetInstanceInfo)
        if okInfo then
            instName = Safe.String(rawName)
        end
    end
    if (not instName or instName == "") and Compat and Compat.CurrentZoneName then
        instName = Compat.CurrentZoneName()
    end
    return true, cleanType, instName or ""
end

local function NormalizePlayerToken(name)
    if type(name) ~= "string" then return name end
    local s = name
    local hp = s:match("|Hplayer:([^:|]+)")
    if hp and hp ~= "" then
        s = hp
    end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^|]+:", ""):gsub("|r", "")
    s = s:gsub("%[", ""):gsub("%]", "")
    return (s:gsub("^%s+", ""):gsub("[%s%.%!%,]+$", ""))
end

local function ResolveForeverDisplayName(rawName, guid)
    if type(rawName) ~= "string" or rawName == "" then return rawName end
    if Compat and Compat.ParseForeverFullName then
        local pf = Compat.ParseForeverFullName(rawName)
        if pf and pf.fullName and pf.fullName ~= "" then
            -- If bare firstName, check LookupForeverFullName / Group.members for full surname
            if (not pf.surname or pf.surname == "") then
                if Compat.LookupForeverFullName then
                    local looked = Compat.LookupForeverFullName(pf.firstName, guid)
                    if looked and looked.fullName and looked.fullName ~= "" then
                        return looked.fullName
                    end
                end
                if ns.Group and type(ns.Group.members) == "table" then
                    local fLow = LowerUtf8Safe(pf.firstName)
                    local foundFull, foundCount = nil, 0
                    for _, m in ipairs(ns.Group.members) do
                        local mName = type(m) == "table" and (m.fullName or m.displayName or m.name) or nil
                        if type(mName) == "string" and mName ~= "" then
                            local mpf = Compat.ParseForeverFullName(mName)
                            if mpf and LowerUtf8Safe(mpf.firstName or "") == fLow then
                                if guid and m.guid and m.guid == guid then
                                    return mpf.fullName or mName
                                end
                                foundFull = mpf.fullName or mName
                                foundCount = foundCount + 1
                            end
                        end
                    end
                    if foundCount == 1 and foundFull then
                        return foundFull
                    end
                end
            end
            return pf.fullName
        end
    end
    return rawName
end

local function CaptureCurrentRosterMeta()
    local keys = {}
    local seen = {}
    local function AddUnit(u)
        if not (UnitExists and Safe.Bool(Safe.Call(UnitExists, u)) == true) then return end
        local guid = UnitGUID and Safe.String(Safe.Call(UnitGUID, u)) or nil
        local resolved = Compat and Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(u, guid, nil, true)
        local rawName = (resolved and resolved.fullName) or Safe.String(Safe.Call(UnitName, u))
        if not rawName or rawName == "" then return end
        local disp = ResolveForeverDisplayName(rawName, guid)
        local lk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(disp)) or LowerUtf8Safe(disp)
        if lk and lk ~= "" and not seen[lk] then
            seen[lk] = true
            keys[#keys + 1] = lk
        end
    end
    AddUnit("player")
    if IsInRaid and Safe.Bool(Safe.Call(IsInRaid)) == true then
        local total = GetNumGroupMembers and Safe.Number(Safe.Call(GetNumGroupMembers)) or 0
        for i = 1, math.min(total, 40) do
            AddUnit("raid" .. i)
        end
    elseif IsInGroup and Safe.Bool(Safe.Call(IsInGroup)) == true then
        for i = 1, 4 do
            AddUnit("party" .. i)
        end
    end
    table.sort(keys)
    return table.concat(keys, ","), #keys
end

local function FormatGlobalToPattern(globalFmt, defaultOrder)
    if type(globalFmt) ~= "string" or globalFmt == "" then return nil, defaultOrder end
    local actualOrder = {}
    local strFields = {}
    local numFields = {}
    if defaultOrder then
        for _, f in ipairs(defaultOrder) do
            if f == "roll" or f == "min" or f == "max" or f == "count" then
                numFields[#numFields + 1] = f
            else
                strFields[#strFields + 1] = f
            end
        end
    end

    -- Neutralize Blizzard's leading |HlootHistory:%d|h hyperlink token so its drop ID never becomes a captured roll number.
    local prepared = globalFmt:gsub("|HlootHistory:%%%d*%$?[du]|h", "\5")
    prepared = prepared:gsub("%%%%", "\4")
    local seqIdx = 0
    local strCursor = 0
    local numCursor = 0
    local token = prepared:gsub("%%(%d*)%$?([sdu])", function(posStr, conv)
        seqIdx = seqIdx + 1
        local idx = tonumber(posStr)
        local fieldName
        local isNumConv = (conv == "d" or conv == "u")
        if idx and defaultOrder and defaultOrder[idx] then
            fieldName = defaultOrder[idx]
        elseif isNumConv and defaultOrder then
            numCursor = numCursor + 1
            fieldName = numFields[numCursor] or defaultOrder[seqIdx] or ("num" .. tostring(#actualOrder + 1))
        elseif conv == "s" and defaultOrder then
            strCursor = strCursor + 1
            fieldName = strFields[strCursor] or defaultOrder[seqIdx] or ("cap" .. tostring(#actualOrder + 1))
        else
            fieldName = (defaultOrder and defaultOrder[seqIdx]) or ("cap" .. tostring(#actualOrder + 1))
        end
        local isNumField = (fieldName == "roll" or fieldName == "min" or fieldName == "max" or fieldName == "count")
        if isNumConv and not isNumField then
            numCursor = numCursor + 1
            fieldName = numFields[numCursor] or "roll"
            isNumField = true
        elseif (not isNumConv) and isNumField then
            strCursor = strCursor + 1
            fieldName = strFields[strCursor] or "player"
            isNumField = false
        end
        actualOrder[#actualOrder + 1] = fieldName
        if isNumField then
            return "\2"
        elseif fieldName == "link" then
            return "\3"
        end
        return "\1"
    end)

    token = EscapeLuaPattern(token)
    token = token:gsub("%%%.$", "%%.?")
    token = token:gsub("\5", "|HlootHistory:%%d+|h")
    token = token:gsub("\4", "%%%%")
    token = token:gsub("\2", "(%%d+)")
    token = token:gsub("\3", "(.-|Hitem:[^|]+|h%%[.-%%]|h|?r?)")
    token = token:gsub("\1", "(.+)")
    return "^" .. token .. "%s*$", actualOrder
end

local function BuildLootPatterns(self)
    if self._lootPatterns then return self._lootPatterns end
    -- Self and specific patterns MUST precede generic "%s ..." patterns so "You"/"Você" cannot match a player name.
    local defs = {
        { key = "LOOT_ROLL_ROLLED_NEED_SELF", mode = "ROLLED_SELF", choice = "NEED", order = { "roll", "link" } },
        { key = "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS_SELF", mode = "ROLLED_SELF", choice = "NEED", order = { "roll", "link" } },
        { key = "LOOT_ROLL_ROLLED_GREED_SELF", mode = "ROLLED_SELF", choice = "GREED", order = { "roll", "link" } },
        { key = "LOOT_ROLL_ROLLED_DE_SELF", mode = "ROLLED_SELF", choice = "DE", order = { "roll", "link" } },
        { key = "LOOT_ROLL_ROLLED_DISENCHANT_SELF", mode = "ROLLED_SELF", choice = "DE", order = { "roll", "link" } },
        { key = "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", mode = "ROLLED", choice = "NEED", order = { "roll", "link", "player" } },
        { key = "LOOT_ROLL_ROLLED_NEED", mode = "ROLLED", choice = "NEED", order = { "roll", "link", "player" } },
        { key = "LOOT_ROLL_ROLLED_GREED", mode = "ROLLED", choice = "GREED", order = { "roll", "link", "player" } },
        { key = "LOOT_ROLL_ROLLED_DE", mode = "ROLLED", choice = "DE", order = { "roll", "link", "player" } },
        { key = "LOOT_ROLL_ROLLED_DISENCHANT", mode = "ROLLED", choice = "DE", order = { "roll", "link", "player" } },
        { key = "LOOT_ROLL_YOU_WON_NO_SPAM_NEED_ROLE_BONUS", mode = "WON_SELF", choice = "NEED", isWin = true, order = { "roll", "link" } },
        { key = "LOOT_ROLL_YOU_WON_NO_SPAM_NEED", mode = "WON_SELF", choice = "NEED", isWin = true, order = { "roll", "link" } },
        { key = "LOOT_ROLL_YOU_WON_NO_SPAM_GREED", mode = "WON_SELF", choice = "GREED", isWin = true, order = { "roll", "link" } },
        { key = "LOOT_ROLL_YOU_WON_NO_SPAM_DE", mode = "WON_SELF", choice = "DE", isWin = true, order = { "roll", "link" } },
        { key = "LOOT_ROLL_YOU_WON_NO_SPAM_DISENCHANT", mode = "WON_SELF", choice = "DE", isWin = true, order = { "roll", "link" } },
        { key = "LOOT_ROLL_WON_NO_SPAM_NEED_ROLE_BONUS", mode = "WON", choice = "NEED", isWin = true, order = { "player", "roll", "link" } },
        { key = "LOOT_ROLL_WON_NO_SPAM_NEED", mode = "WON", choice = "NEED", isWin = true, order = { "player", "roll", "link" } },
        { key = "LOOT_ROLL_WON_NO_SPAM_GREED", mode = "WON", choice = "GREED", isWin = true, order = { "player", "roll", "link" } },
        { key = "LOOT_ROLL_WON_NO_SPAM_DE", mode = "WON", choice = "DE", isWin = true, order = { "player", "roll", "link" } },
        { key = "LOOT_ROLL_WON_NO_SPAM_DISENCHANT", mode = "WON", choice = "DE", isWin = true, order = { "player", "roll", "link" } },
        { key = "LOOT_ROLL_YOU_WON", mode = "WON_SELF", choice = "WON", isWin = true, order = { "link" } },
        { key = "LOOT_ROLL_WON", mode = "WON", choice = "WON", isWin = true, order = { "player", "link" } },
        { key = "LOOT_ROLL_ALL_PASSED", mode = "ALL_PASSED", choice = "PASS", order = { "link" } },
        { key = "LOOT_ROLL_NEED_SELF", mode = "PICK_SELF", choice = "NEED", order = { "link" } },
        { key = "LOOT_ROLL_GREED_SELF", mode = "PICK_SELF", choice = "GREED", order = { "link" } },
        { key = "LOOT_ROLL_DISENCHANT_SELF", mode = "PICK_SELF", choice = "DE", order = { "link" } },
        { key = "LOOT_ROLL_PASSED_SELF_AUTO", mode = "PICK_SELF", choice = "PASS", order = { "link" } },
        { key = "LOOT_ROLL_PASSED_SELF", mode = "PICK_SELF", choice = "PASS", order = { "link" } },
        { key = "LOOT_ROLL_NEED", mode = "PICK", choice = "NEED", order = { "player", "link" } },
        { key = "LOOT_ROLL_GREED", mode = "PICK", choice = "GREED", order = { "player", "link" } },
        { key = "LOOT_ROLL_DISENCHANT", mode = "PICK", choice = "DE", order = { "player", "link" } },
        { key = "LOOT_ROLL_PASSED_AUTO", mode = "PICK", choice = "PASS", order = { "player", "link" } },
        { key = "LOOT_ROLL_PASSED_AUTO_FEMALE", mode = "PICK", choice = "PASS", order = { "player", "link" } },
        { key = "LOOT_ROLL_PASSED", mode = "PICK", choice = "PASS", order = { "player", "link" } },
        { key = "LOOT_ITEM_PUSHED_SELF_MULTIPLE", mode = "LOOT_SELF", choice = "WON", isWin = true, order = { "link", "count" } },
        { key = "LOOT_ITEM_PUSHED_SELF", mode = "LOOT_SELF", choice = "WON", isWin = true, order = { "link" } },
        { key = "LOOT_ITEM_SELF_MULTIPLE", mode = "LOOT_SELF", choice = "WON", isWin = true, order = { "link", "count" } },
        { key = "LOOT_ITEM_SELF", mode = "LOOT_SELF", choice = "WON", isWin = true, order = { "link" } },
        { key = "LOOT_ITEM_PUSHED_MULTIPLE", mode = "LOOT", choice = "WON", isWin = true, order = { "player", "link", "count" } },
        { key = "LOOT_ITEM_PUSHED", mode = "LOOT", choice = "WON", isWin = true, order = { "player", "link" } },
        { key = "LOOT_ITEM_MULTIPLE", mode = "LOOT", choice = "WON", isWin = true, order = { "player", "link", "count" } },
        { key = "LOOT_ITEM", mode = "LOOT", choice = "WON", isWin = true, order = { "player", "link" } },
    }
    local out = {}
    for _, def in ipairs(defs) do
        local gVal = _G[def.key]
        local pat, resolvedOrder = FormatGlobalToPattern(Safe.String(gVal), def.order)
        if pat then
            out[#out + 1] = {
                pattern = pat,
                mode = def.mode,
                choice = def.choice,
                isWin = def.isWin == true,
                order = resolvedOrder,
            }
        end
    end
    self._lootPatterns = out
    return out
end

local function BuildRandomRollPattern(self)
    if self._randomRollPat ~= nil then
        return self._randomRollPat or nil, self._randomRollOrder
    end
    local gFmt = Safe.String(_G.RANDOM_ROLL_RESULT)
    if not gFmt or gFmt == "" then
        self._randomRollPat = false
        return nil, nil
    end
    local pat, ord = FormatGlobalToPattern(gFmt, { "player", "roll", "min", "max" })
    if pat then
        self._randomRollPat = pat
        self._randomRollOrder = ord
        return pat, ord
    end
    self._randomRollPat = false
    return nil, nil
end

local function LookupGroupMemberClass(displayName, lk)
    if Compat and Compat.IsMe and displayName and Compat.IsMe(displayName) then
        local _, cls = UnitClass("player")
        return Safe.String(cls)
    end
    -- O(1) Store lookup first
    if lk and ns.Store and ns.Store.socialByLookup and ns.Store.socialByLookup[lk] then
        local sCls = ns.Store.socialByLookup[lk].classFile
        if sCls and sCls ~= "" then return sCls end
    end
    -- Fast Group.members scan (already resolved full names)
    if ns.Group and type(ns.Group.members) == "table" then
        local dispLow = displayName and LowerUtf8Safe(displayName) or nil
        for _, m in ipairs(ns.Group.members) do
            if type(m) == "table" and m.classFile and m.classFile ~= "" then
                local mLk = m.lookupKey or (m.fullName and Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(m.fullName))
                if (lk and mLk == lk) or (dispLow and m.fullName and LowerUtf8Safe(m.fullName) == dispLow) or (dispLow and m.name and LowerUtf8Safe(m.name) == dispLow) then
                    return m.classFile
                end
            end
        end
    end
    -- Safe fallback unit scan
    if Compat and Compat.IsInGroup and Compat.IsInGroup() then
        local num = (GetNumGroupMembers and Safe.Number(Safe.Call(GetNumGroupMembers))) or 0
        local prefix = (Compat and Compat.IsInRaid and Compat.IsInRaid()) and "raid" or "party"
        for i = 1, math.min(num, 40) do
            local unit = (prefix == "party" and i == num) and "player" or (prefix .. i)
            if UnitExists and Safe.Bool(Safe.Call(UnitExists, unit)) == true then
                local res = Compat and Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(unit, nil, nil, true)
                local full = (res and res.fullName) or Safe.String(Safe.Call(UnitName, unit))
                if full then
                    local unitLk = Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(full)
                    if (lk and unitLk == lk) or (displayName and LowerUtf8Safe(full) == LowerUtf8Safe(displayName)) then
                        local _, cls = Safe.Call(UnitClass, unit)
                        return Safe.String(cls)
                    end
                end
            end
        end
    end
    return nil
end

local function ResolveSafeUnitClassByGUID(guid, dispName, lk)
    if type(guid) == "string" and guid ~= "" and _G.GetPlayerInfoByGUID then
        local ok, _, cls = pcall(_G.GetPlayerInfoByGUID, guid)
        if ok then
            local cleanCls = Safe.String(cls)
            if cleanCls and cleanCls ~= "" then
                return cleanCls
            end
        end
    end
    return LookupGroupMemberClass(dispName, lk)
end

local function FriendlyStatLabel(statKey)
    local globalLbl = _G[statKey]
    if type(globalLbl) == "string" and globalLbl ~= "" then
        return globalLbl
    end
    return (tostring(statKey or ""):gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_", " "))
end

local function GetSafeDetailedIlvl(itemRef)
    if not itemRef then return 0 end
    local fn = CItemDetailIlvlFn or _G.GetDetailedItemLevelInfo
    if fn then
        local ok, eff, _, base = pcall(fn, itemRef)
        if ok then
            return Safe.Number(eff) or Safe.Number(base) or 0
        end
    end
    return 0
end

local function GetSafeItemStats(itemRef)
    if not itemRef then return nil end
    local fn = CItemStatsFn or _G.GetItemStats
    if not fn then return nil end
    local ok, tbl = pcall(fn, itemRef)
    if ok and type(tbl) == "table" then
        return tbl
    end
    return nil
end

local function AccumulateItemStats(dst, src)
    if type(src) ~= "table" then return end
    for k, v in pairs(src) do
        local num = tonumber(v) or 0
        if num ~= 0 then
            dst[k] = (dst[k] or 0) + num
        end
    end
end

local function GenerateHistoryId(rec)
    if rec.historyId and rec.historyId ~= "" then
        return rec.historyId
    end
    local ts = tonumber(rec.createdAt) or time()
    local rId = tonumber(rec.rollID) or 0
    local iId = tonumber(rec.itemID) or 0
    local prefix = rec.isSimulated and "sim_" or "roll_"
    rec.historyId = prefix .. tostring(ts) .. "_" .. tostring(rId) .. "_" .. tostring(iId)
    return rec.historyId
end

local function FindChoiceEntryKey(rec, dispName, lk, isSelf)
    if not (rec and rec.choices) then return lk end
    if lk and rec.choices[lk] then return lk end
    local parsed = (Compat and Compat.ParseForeverFullName and type(dispName) == "string") and Compat.ParseForeverFullName(dispName) or nil
    local normLk = (parsed and parsed.fullName and Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(parsed.fullName)) or (type(dispName) == "string" and LowerUtf8Safe(dispName)) or nil
    if normLk and rec.choices[normLk] then return normLk end
    local bareFirst = (parsed and parsed.firstName and (not parsed.surname or parsed.surname == "")) and LowerUtf8Safe(parsed.firstName) or nil
    local isPlayer = isSelf or (Compat and Compat.IsMe and Compat.IsMe(dispName))
    for k, entry in pairs(rec.choices) do
        if type(entry) == "table" then
            if isPlayer and entry.isMe then
                return k
            end
            if type(entry.name) == "string" then
                local eParsed = Compat and Compat.ParseForeverFullName and Compat.ParseForeverFullName(entry.name) or nil
                local eLk = (eParsed and eParsed.fullName and Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(eParsed.fullName)) or LowerUtf8Safe(entry.name)
                if normLk and eLk == normLk then
                    return k
                end
                -- Only match bare FirstName <-> FullName when one side genuinely lacks a surname
                if bareFirst and eParsed and eParsed.firstName and LowerUtf8Safe(eParsed.firstName) == bareFirst then
                    return k
                end
                if parsed and parsed.surname and parsed.surname ~= "" and eParsed and (not eParsed.surname or eParsed.surname == "") and eParsed.firstName and LowerUtf8Safe(eParsed.firstName) == LowerUtf8Safe(parsed.firstName or "") then
                    return k
                end
            end
        end
    end
    return lk or normLk or "?"
end

local function MapModernRollState(stateVal)
    local st = Safe.Number(stateVal)
    if not st then return nil end
    local enumTbl = _G.Enum and _G.Enum.EncounterLootDropRollState
    if type(enumTbl) == "table" then
        if st == enumTbl.NoRoll then return nil end
        if st == enumTbl.NeedMainSpec or st == enumTbl.NeedOffSpec or st == enumTbl.Need then return "NEED" end
        if st == enumTbl.Disenchant then return "DE" end
        if st == enumTbl.Greed or st == enumTbl.Transmog then return "GREED" end
        if st == enumTbl.Pass then return "PASS" end
    end
    if st == 0 or st == 1 then return "NEED" end
    if st == 2 or st == 3 then return "GREED" end
    if st == 5 then return "PASS" end
    if st == 6 then return "DE" end
    return nil
end

function LootRoll:IsEnabled()
    return (ns.db and ns.db.settings and ns.db.settings.lootRollHelperEnabled == true) and true or false
end

function LootRoll:IsHideOfficialEnabled()
    return (not ns.db or not ns.db.settings or ns.db.settings.lootRollHideOfficial ~= false) and true or false
end

function LootRoll:IsWinnerBannerEnabled()
    return false
end

function LootRoll:IsWinnerToastEnabled()
    return (not ns.db or not ns.db.settings or ns.db.settings.lootRollWinnerToast ~= false) and true or false
end

function LootRoll:IsWinnerChatAnnounceEnabled()
    return (not ns.db or not ns.db.settings or ns.db.settings.lootRollWinnerChatAnnounce ~= false) and true or false
end

function LootRoll:HasAnsweredPrompt()
    return (ns.db and ns.db.settings and ns.db.settings.lootRollPromptAnswered == true) and true or false
end

function LootRoll:SetEnabledFromPrompt(enabled, hideOfficial)
    local isOn = enabled and true or false
    if ns.db and ns.db.settings then
        ns.db.settings.lootRollPromptAnswered = true
        ns.db.settings.lootRollHelperEnabled = isOn
        if isOn then
            ns.db.settings.lootRollHideOfficial = (hideOfficial == nil) and true or (hideOfficial and true or false)
        end
    end
    if SocialCentralDB and SocialCentralDB.settings then
        SocialCentralDB.settings.lootRollPromptAnswered = true
        SocialCentralDB.settings.lootRollHelperEnabled = isOn
        if isOn then
            SocialCentralDB.settings.lootRollHideOfficial = (hideOfficial == nil) and true or (hideOfficial and true or false)
        end
    end
    if not isOn then
        for i = #self.rollOrder, 1, -1 do
            local rId = self.rollOrder[i]
            local rec = self.activeRolls[rId]
            if not rec or not rec.isSimulated then
                self.activeRolls[rId] = nil
                table.remove(self.rollOrder, i)
            end
        end
    end
    ns:Emit("SETTINGS_UPDATED")
    if isOn and next(self.activeRolls) ~= nil then
        self:SyncLootHistory()
    end
    ns:Emit("LOOT_ROLL_UPDATED")
end

function LootRoll:GetDisplayMode()
    local m = ns.db and ns.db.settings and ns.db.settings.lootRollDisplayMode
    return (m == "stacked") and "stacked" or "tabbed"
end

function LootRoll:GetRollChoiceLabel(choice)
    if choice == "NEED" then return L["Need (Roll)"] end
    if choice == "GREED" then return L["Greed"] end
    if choice == "DE" then return L["Disenchant"] end
    if choice == "PASS" then return L["Pass"] end
    if choice == "WON" then return L["Won"] end
    if choice == "MASTER" then return L["Master Loot"] end
    return "?"
end

function LootRoll:GetChoiceColor(choice)
    return CHOICE_COLORS[choice] or "|cffd0d7de"
end

function LootRoll:GetChoicePriority(choice, isWon)
    if isWon == true then
        return 4
    end
    return CHOICE_PRIORITY[choice] or 0
end

function LootRoll:SortChoicesList(list)
    if type(list) ~= "table" or #list <= 1 then return list end
    table.sort(list, function(a, b)
        local wa = (a.won == true)
        local wb = (b.won == true)
        if wa ~= wb then
            return wa
        end
        local pa = self:GetChoicePriority(a.choice, wa)
        local pb = self:GetChoicePriority(b.choice, wb)
        if pa ~= pb then
            return pa > pb
        end
        local ra = tonumber(a.roll) or -1
        local rb = tonumber(b.roll) or -1
        if ra ~= rb then
            return ra > rb
        end
        local ma = (a.isMe == true)
        local mb = (b.isMe == true)
        if ma ~= mb then
            return ma
        end
        return tostring(a.name or "") < tostring(b.name or "")
    end)
    return list
end

function LootRoll:ComputeCurrentLeader(rec)
    if not rec then return nil, nil, nil, false end
    if rec.resolved then
        if rec.allPassed then
            return nil, nil, "PASS", false
        end
        return rec.winnerName, rec.winnerRoll, rec.winnerChoice, false
    end
    local bestPrio, bestRoll, bestCount = 0, -1, 0
    local bestEntry = nil
    for _, ch in pairs(rec.choices or {}) do
        if type(ch) == "table" then
            ch.isLeading = false
            if ch.choice and ch.choice ~= "PASS" then
                local pr = self:GetChoicePriority(ch.choice, false)
                local rl = tonumber(ch.roll) or -1
                if pr > bestPrio or (pr == bestPrio and rl > bestRoll) then
                    bestPrio = pr
                    bestRoll = rl
                    bestEntry = ch
                    bestCount = 1
                elseif pr == bestPrio and rl == bestRoll then
                    bestCount = bestCount + 1
                end
            end
        end
    end
    if bestEntry then
        for _, ch in pairs(rec.choices or {}) do
            if type(ch) == "table" and ch.choice and ch.choice ~= "PASS" then
                local pr = self:GetChoicePriority(ch.choice, false)
                local rl = tonumber(ch.roll) or -1
                if pr == bestPrio and rl == bestRoll then
                    ch.isLeading = true
                end
            end
        end
        return bestEntry.name, bestEntry.roll, bestEntry.choice, (bestCount > 1)
    end
    return nil, nil, nil, false
end

function LootRoll:BuildComparison(itemLink, itemID, itemNameHint, slotOverride)
    local ref = itemLink or itemID
    if not ref then
        return { isEquippable = false, diffs = {} }
    end
    local rId, itemType, itemSubType, equipLoc, _, classID, subClassID = GetSafeItemInstantInfo(ref)
    itemID = itemID or rId
    local candIlvl = GetSafeDetailedIlvl(ref)
    local ownedCount = GetSafeOwnedCount(itemID)
    local accountCount = (ns.Alts and ns.Alts.GetAccountItemTotal and itemID) and ns.Alts:GetAccountItemTotal(itemID, nil, "pool") or ownedCount
    if accountCount < ownedCount then accountCount = ownedCount end

    local uniqueOwned = false
    if itemID and ownedCount > 0 and CItemUniquenessFn then
        local okU, _, maxUnique = pcall(CItemUniquenessFn, itemID)
        if okU then
            local maxU = Safe.Number(maxUnique)
            if maxU and maxU > 0 and ownedCount >= maxU then
                uniqueOwned = true
            end
        end
    end

    local recipeKnownByMe = false
    local recipeNeededByMe = false
    local recipeKnownAlts = nil
    local recipeNeededAlts = nil
    if classID == 9 and ns.Alts and ns.Alts.MatchRecipeScrollItem then
        local titleStr = itemNameHint or (itemLink and itemLink:match("%[(.-)%]")) or (itemID and CItemNameFn and Safe.String(Safe.Call(CItemNameFn, itemID)))
        if titleStr and titleStr ~= "" then
            local curAltKey = ns.Store and ns.Store.GetCurrentAltKey and ns.Store:GetCurrentAltKey() or nil
            local knownBy, missingOn = ns.Alts:MatchRecipeScrollItem(itemID, titleStr, subClassID, "pool")
            if type(knownBy) == "table" and #knownBy > 0 then
                recipeKnownAlts = {}
                for _, kb in ipairs(knownBy) do
                    if curAltKey and kb.altKey == curAltKey then
                        recipeKnownByMe = true
                    elseif kb.displayName then
                        recipeKnownAlts[#recipeKnownAlts + 1] = kb.displayName
                    end
                end
            end
            if type(missingOn) == "table" and #missingOn > 0 then
                recipeNeededAlts = {}
                for _, ms in ipairs(missingOn) do
                    if curAltKey and ms.altKey == curAltKey then
                        recipeNeededByMe = true
                    elseif ms.displayName then
                        recipeNeededAlts[#recipeNeededAlts + 1] = ms.displayName
                    end
                end
            end
        end
    end

    local rawSlotList = equipLoc and EQUIP_LOC_SLOTS[equipLoc] or nil
    if not rawSlotList or #rawSlotList == 0 then
        local nonEqVerdict = nil
        if classID == 9 then
            if recipeNeededByMe then
                nonEqVerdict = "RECIPE_YOU"
            elseif recipeNeededAlts and #recipeNeededAlts > 0 then
                nonEqVerdict = "RECIPE_ALT"
            elseif recipeKnownByMe then
                nonEqVerdict = "RECIPE_KNOWN"
            end
        elseif uniqueOwned then
            nonEqVerdict = "UNIQUE_OWNED"
        end
        local smallestBagSlots = nil
        if (equipLoc == "INVTYPE_BAG" or classID == 1) and C_Container and C_Container.GetContainerNumSlots then
            for bagId = 1, 4 do
                local nSlots = Safe.Number(Safe.Call(C_Container.GetContainerNumSlots, bagId)) or 0
                if smallestBagSlots == nil or nSlots < smallestBagSlots then
                    smallestBagSlots = nSlots
                end
            end
        end
        return {
            isEquippable = false,
            canEquip = true,
            verdict = nonEqVerdict,
            uniqueOwned = uniqueOwned,
            smallestBagSlots = smallestBagSlots,
            candidateILvl = candIlvl,
            equipLoc = equipLoc,
            itemType = itemType,
            itemSubType = itemSubType,
            classID = classID,
            subClassID = subClassID,
            ownedCount = ownedCount,
            accountCount = accountCount,
            recipeKnownByMe = recipeKnownByMe,
            recipeNeededByMe = recipeNeededByMe,
            recipeKnownAlts = recipeKnownAlts,
            recipeNeededAlts = recipeNeededAlts,
            diffs = {},
        }
    end

    local pCls
    if UnitClass then
        local _, rawCls = UnitClass("player")
        pCls = Safe.String(rawCls)
    end
    local pLvl = (UnitLevel and Safe.Number(Safe.Call(UnitLevel, "player"))) or 60
    local slotList = rawSlotList
    if equipLoc == "INVTYPE_WEAPON" and not CanPlayerDualWield(pCls, pLvl) then
        slotList = { 16 }
    end

    local canEquip, wrongArmor, unusableReason = EvaluateItemUsability(classID, subClassID, equipLoc)

    local targetSlot = slotList[1]
    local altSlotId = nil
    local equippedLink = nil
    local secondaryLink = nil
    local equippedIlvl = 0
    local vsComboLabel = nil
    local eqStats = {}

    if equipLoc == "INVTYPE_2HWEAPON" then
        local mhLink = GetInventoryItemLink and Safe.String(Safe.Call(GetInventoryItemLink, "player", 16)) or nil
        local ohLink = GetInventoryItemLink and Safe.String(Safe.Call(GetInventoryItemLink, "player", 17)) or nil
        if mhLink == "" then mhLink = nil end
        if ohLink == "" then ohLink = nil end
        equippedLink = mhLink or ohLink
        if mhLink and ohLink then
            secondaryLink = ohLink
            local mhIlvl = GetSafeDetailedIlvl(mhLink)
            local ohIlvl = GetSafeDetailedIlvl(ohLink)
            equippedIlvl = math.floor(((mhIlvl + ohIlvl) * 0.5) + 0.5)
            vsComboLabel = L["Main + Off Hand"]
            AccumulateItemStats(eqStats, GetSafeItemStats(mhLink))
            AccumulateItemStats(eqStats, GetSafeItemStats(ohLink))
        elseif equippedLink then
            equippedIlvl = GetSafeDetailedIlvl(equippedLink)
            AccumulateItemStats(eqStats, GetSafeItemStats(equippedLink))
        end
    else
        local validOverride = nil
        if slotOverride then
            for _, sId in ipairs(slotList) do
                if sId == slotOverride then
                    validOverride = sId
                    break
                end
            end
        end
        if validOverride then
            targetSlot = validOverride
            local lnk = GetInventoryItemLink and Safe.String(Safe.Call(GetInventoryItemLink, "player", validOverride)) or nil
            if lnk and lnk ~= "" then
                equippedLink = lnk
                equippedIlvl = GetSafeDetailedIlvl(lnk)
            else
                equippedLink = nil
                equippedIlvl = 0
            end
        else
            local lowestIlvl = nil
            for _, sId in ipairs(slotList) do
                local lnk = GetInventoryItemLink and Safe.String(Safe.Call(GetInventoryItemLink, "player", sId)) or nil
                if not lnk or lnk == "" then
                    targetSlot = sId
                    equippedLink = nil
                    equippedIlvl = 0
                    break
                else
                    local eIlvl = GetSafeDetailedIlvl(lnk)
                    if lowestIlvl == nil or eIlvl < lowestIlvl then
                        lowestIlvl = eIlvl
                        targetSlot = sId
                        equippedLink = lnk
                        equippedIlvl = eIlvl
                    end
                end
            end
        end
        if #slotList == 2 then
            altSlotId = (targetSlot == slotList[1]) and slotList[2] or slotList[1]
        end
        -- If candidate is a 1H/OffHand/Shield and slot 17 is empty because a 2H weapon sits in slot 16, compare against slot 16.
        if (not equippedLink) and (targetSlot == 17) then
            local mhLink = GetInventoryItemLink and Safe.String(Safe.Call(GetInventoryItemLink, "player", 16)) or nil
            if mhLink and mhLink ~= "" then
                local _, _, _, mhLoc = GetSafeItemInstantInfo(mhLink)
                if mhLoc == "INVTYPE_2HWEAPON" then
                    equippedLink = mhLink
                    equippedIlvl = GetSafeDetailedIlvl(mhLink)
                    vsComboLabel = L["2H Weapon"]
                end
            end
        end
        if equippedLink then
            AccumulateItemStats(eqStats, GetSafeItemStats(equippedLink))
        end
    end

    local candStats = GetSafeItemStats(ref) or {}
    local seenKeys = {}
    for k in pairs(candStats) do seenKeys[k] = true end
    for k in pairs(eqStats) do seenKeys[k] = true end

    local diffs = {}
    for statKey in pairs(seenKeys) do
        local cVal = tonumber(candStats[statKey]) or 0
        local eVal = tonumber(eqStats[statKey]) or 0
        local delta = cVal - eVal
        if statKey == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then
            delta = math.floor(delta * 10 + 0.5) / 10
        end
        if delta ~= 0 then
            diffs[#diffs + 1] = {
                key = statKey,
                label = FriendlyStatLabel(statKey),
                delta = delta,
                candVal = cVal,
                eqVal = eVal,
                order = STAT_ORDER[statKey] or 99,
            }
        end
    end
    table.sort(diffs, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        if (a.delta > 0) ~= (b.delta > 0) then
            return a.delta > 0
        end
        return tostring(a.label) < tostring(b.label)
    end)

    local ilvlDiff = (candIlvl > 0) and (candIlvl - equippedIlvl) or 0
    local isEmptySlot = (not equippedLink or equippedLink == "") and (vsComboLabel == nil)
    local verdict
    if uniqueOwned then
        verdict = "UNIQUE_OWNED"
    elseif not canEquip then
        verdict = "CANNOT_EQUIP"
    elseif wrongArmor then
        verdict = "WRONG_ARMOR"
    elseif isEmptySlot then
        verdict = "EMPTY"
    elseif ilvlDiff > 0 then
        verdict = "UPGRADE"
    elseif ilvlDiff < 0 then
        verdict = "DOWNGRADE"
    else
        verdict = "SIDEGRADE"
    end

    return {
        isEquippable = true,
        canEquip = canEquip,
        wrongArmor = wrongArmor,
        unusableReason = unusableReason,
        uniqueOwned = uniqueOwned,
        verdict = verdict,
        slotId = targetSlot,
        altSlotId = altSlotId,
        slotLabel = GetSlotDisplayLabel(targetSlot, equipLoc),
        equipLoc = equipLoc,
        itemType = itemType,
        itemSubType = itemSubType,
        classID = classID,
        subClassID = subClassID,
        equippedLink = equippedLink,
        secondaryLink = secondaryLink,
        vsComboLabel = vsComboLabel,
        equippedILvl = equippedIlvl,
        candidateILvl = candIlvl,
        ilvlDiff = ilvlDiff,
        isEmptySlot = isEmptySlot,
        ownedCount = ownedCount,
        accountCount = accountCount,
        diffs = diffs,
    }
end

function LootRoll:SwapComparisonSlot(rollID)
    local rec = self.activeRolls[rollID]
    if not (rec and rec.comparison and rec.comparison.altSlotId) then return false end
    rec._compareSlotOverride = rec.comparison.altSlotId
    rec.comparison = self:BuildComparison(rec.link, rec.itemID, rec.name, rec._compareSlotOverride)
    ns:Emit("LOOT_ROLL_UPDATED", rollID)
    return true
end

function LootRoll:SerializeRollRecord(rec)
    if not rec then return nil end
    local hid = GenerateHistoryId(rec)
    local choicesArr = {}
    for _, ch in pairs(rec.choices or {}) do
        if type(ch) == "table" then
            choicesArr[#choicesArr + 1] = {
                n = ch.name or "?",
                c = ch.classFile,
                ch = ch.choice or "PASS",
                r = tonumber(ch.roll),
                w = ch.won == true,
                me = ch.isMe == true,
            }
        end
    end
    table.sort(choicesArr, function(a, b)
        local wa, wb = (a.w == true), (b.w == true)
        if wa ~= wb then return wa end
        local pa = LootRoll:GetChoicePriority(a.ch, wa)
        local pb = LootRoll:GetChoicePriority(b.ch, wb)
        if pa ~= pb then return pa > pb end
        local ra, rb = tonumber(a.r) or -1, tonumber(b.r) or -1
        if ra ~= rb then return ra > rb end
        return tostring(a.n or "") < tostring(b.n or "")
    end)
    return {
        id = hid,
        rollID = rec.rollID,
        lootListID = rec.lootListID,
        ts = rec.resolvedAt or rec.createdAt or time(),
        createdAt = rec.createdAt or time(),
        zone = rec.zone or (Compat and Compat.CurrentZoneName and Compat.CurrentZoneName()) or "",
        bossName = rec.bossName,
        isMasterLoot = rec.isMasterLoot == true and true or nil,
        charName = rec.charName or (Compat and Compat.MyFullName and Compat.MyFullName()) or "",
        charClass = rec.charClass,
        realmPool = rec.realmPool or (Compat and Compat.RealmPool and Compat.RealmPool()) or "",
        runKey = rec.runKey,
        instType = rec.instType,
        groupCount = rec.groupCount,
        rosterSig = rec.rosterSig,
        itemLink = rec.link,
        itemID = rec.itemID,
        name = rec.name or "?",
        quality = rec.quality or 1,
        texture = rec.texture,
        count = rec.count or 1,
        bop = rec.bindOnPickUp == true,
        myChoice = rec.myChoice,
        myRoll = rec.myRoll,
        winnerName = rec.winnerName,
        winnerClass = rec.winnerClass,
        winnerChoice = rec.winnerChoice,
        winnerRoll = rec.winnerRoll,
        wonByMe = rec.winnerIsMe == true,
        allPassed = rec.allPassed == true,
        resolved = rec.resolved == true,
        isSimulated = rec.isSimulated == true and true or nil,
        choices = choicesArr,
    }
end

function LootRoll:CommitRecordToHistory(rec)
    if not rec then return end
    local serialized = self:SerializeRollRecord(rec)
    if not serialized then return end

    local targetList
    if rec.isSimulated then
        targetList = self.simHistory
    else
        if not (SocialCentralDB and type(SocialCentralDB) == "table") then return end
        if type(SocialCentralDB.lootRollHistory) ~= "table" then
            SocialCentralDB.lootRollHistory = {}
        end
        targetList = SocialCentralDB.lootRollHistory
    end

    local foundIdx = nil
    for idx, entry in ipairs(targetList) do
        if type(entry) == "table" and entry.id == serialized.id then
            foundIdx = idx
            break
        end
    end
    if foundIdx then
        targetList[foundIdx] = serialized
    else
        table.insert(targetList, 1, serialized)
    end
    local cap = rec.isSimulated and 12 or self.maxHistory
    while #targetList > cap do
        table.remove(targetList, #targetList)
    end
end

function LootRoll:QueueHistoryCommit(rec, immediate)
    if not rec then return end
    if immediate or rec.isSimulated or not (C_Timer and C_Timer.After) then
        if self._pendingHistoryCommits and rec.rollID then
            self._pendingHistoryCommits[rec.rollID] = nil
        end
        self:CommitRecordToHistory(rec)
        return
    end
    self._pendingHistoryCommits = self._pendingHistoryCommits or {}
    self._pendingHistoryCommits[rec.rollID or rec] = rec
    if not self._historyFlushScheduled then
        self._historyFlushScheduled = true
        C_Timer.After(0.25, function()
            LootRoll:FlushPendingHistoryCommits()
        end)
    end
end

function LootRoll:FlushPendingHistoryCommits()
    self._historyFlushScheduled = nil
    local pending = self._pendingHistoryCommits
    if type(pending) ~= "table" then return end
    for k, rec in pairs(pending) do
        pending[k] = nil
        if rec then
            self:CommitRecordToHistory(rec)
        end
    end
end

function LootRoll:PlayWinnerChime(wonByMe, quality)
    local s = ns.db and ns.db.settings
    if s and s.lootRollWinnerSound == false then return end
    if Compat and Compat.IsFocusSilenced and Compat.IsFocusSilenced() then return end
    local nowMono = GetTime and GetTime() or 0
    if (nowMono - (self._lastWinSoundAt or 0)) < 3.0 then return end
    self._lastWinSoundAt = nowMono
    if PlaySound and SOUNDKIT then
        local sid
        if wonByMe then
            if (tonumber(quality) or 1) >= 5 then
                sid = SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or SOUNDKIT.UI_EPIC_LOOT_TOAST or SOUNDKIT.UI_BONUS_LOOT_ROLL_END or SOUNDKIT.IG_QUEST_LIST_COMPLETE or SOUNDKIT.MAP_PING or 3175
            else
                sid = SOUNDKIT.UI_EPIC_LOOT_TOAST or SOUNDKIT.UI_BONUS_LOOT_ROLL_END or SOUNDKIT.IG_QUEST_LIST_COMPLETE or SOUNDKIT.MAP_PING or 3175
            end
        else
            sid = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.MAP_PING or 3175
        end
        pcall(PlaySound, sid, "Master")
    end
end

local function BuildClickableItemText(rec)
    if not rec then return "?" end
    local raw = rec.link or rec.itemLink
    if type(raw) == "string" and raw:find("|Hitem:", 1, true) then
        return raw
    end
    local q = tonumber(rec.quality) or 1
    local qTbl = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q]
    local qHex = (qTbl and qTbl.hex) or "|cffffffff"
    local iName = tostring(rec.name or "?")
    local itemID = tonumber(rec.itemID)
    if itemID and itemID > 0 then
        return qHex .. "|Hitem:" .. tostring(itemID) .. ":0:0:0:0:0:0:0|h[" .. iName .. "]|h|r"
    end
    return qHex .. "[" .. iName .. "]|r"
end

function LootRoll:FormatChatAllChoicesLine(rec)
    if not rec then return nil end
    local choices = {}
    if type(rec.choices) == "table" then
        for k, ch in pairs(rec.choices) do
            if type(ch) == "table" then
                if type(k) == "number" then
                    choices[#choices + 1] = {
                        n = ch.n or ch.name or "?",
                        c = ch.c or ch.classFile,
                        ch = ch.ch or ch.choice or "PASS",
                        r = ch.r or ch.roll,
                        w = (ch.w == true or ch.won == true),
                    }
                else
                    choices[#choices + 1] = {
                        n = ch.name or ch.n or "?",
                        c = ch.classFile or ch.c,
                        ch = ch.choice or ch.ch or "PASS",
                        r = ch.roll or ch.r,
                        w = (ch.won == true or ch.w == true),
                    }
                end
            end
        end
    end
    if #choices == 0 then return nil end
    table.sort(choices, function(a, b)
        local wa, wb = (a.w == true), (b.w == true)
        if wa ~= wb then return wa end
        local pa = LootRoll:GetChoicePriority(a.ch, wa)
        local pb = LootRoll:GetChoicePriority(b.ch, wb)
        if pa ~= pb then return pa > pb end
        local ra, rb = tonumber(a.r) or -1, tonumber(b.r) or -1
        if ra ~= rb then return ra > rb end
        return tostring(a.n or "") < tostring(b.n or "")
    end)

    local parts = {}
    local lim = math.min(12, #choices)
    for i = 1, lim do
        local ch = choices[i]
        local pName = tostring(ch.n or "?")
        local pHex = (ch.c and Compat and Compat.ClassHex and Compat.ClassHex(ch.c)) or "|cffe6edf3"
        local pChoice = ch.ch or "PASS"
        local cLbl = self:GetRollChoiceLabel(pChoice)
        local cCol = self:GetChoiceColor(pChoice)
        local rPart = ch.r and (" " .. tostring(ch.r)) or ""
        local winCrown = ch.w and "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:0|t" or ""
        parts[#parts + 1] = winCrown .. pHex .. pName .. "|r (" .. cCol .. cLbl .. rPart .. "|r)"
    end
    if #choices > lim then
        parts[#parts + 1] = "+" .. tostring(#choices - lim)
    end
    return "|cff9da7b5" .. L["Choices:"] .. "|r " .. table.concat(parts, ", ")
end

function LootRoll:AnnounceWinnerInChat(rec)
    if not rec or not self:IsWinnerChatAnnounceEnabled() then return end
    local hid = GenerateHistoryId(rec)
    local itemTxt = BuildClickableItemText(rec)
    local qtyTxt = (rec.count and rec.count > 1) and ("x" .. tostring(rec.count) .. " ") or ""
    local resultsTag = "|cff58a6ff|Haddon:SCentral:lootroll:" .. tostring(hid) .. "|h[" .. L["Results"] .. "]|h|r"

    local bodyLine
    if rec.allPassed then
        bodyLine = string.format("|cffffd24d%s:|r %s%s — |cff9da7b5%s|r  %s", L["Loot Roll"], qtyTxt, itemTxt, L["All passed"], resultsTag)
    else
        local wName = tostring(rec.winnerName or "?")
        local wHex = (rec.winnerClass and Compat and Compat.ClassHex and Compat.ClassHex(rec.winnerClass)) or "|cffe6edf3"
        local cLbl = rec.winnerChoice and self:GetRollChoiceLabel(rec.winnerChoice) or L["Won"]
        local rollPart = rec.winnerRoll and (" " .. tostring(rec.winnerRoll)) or ""
        local winTag = rec.winnerIsMe and ("|cffffea70" .. L["YOU WON!"] .. "|r ") or ("|cff47ef66" .. L["Winner"] .. ":|r ")
        local myPart = ""
        if not rec.winnerIsMe and rec.myChoice then
            local myLbl = self:GetRollChoiceLabel(rec.myChoice)
            local myRollStr = rec.myRoll and (" " .. tostring(rec.myRoll)) or ""
            myPart = " |cff9da7b5(" .. L["You"] .. ": " .. myLbl .. myRollStr .. ")|r"
        end
        bodyLine = string.format("|cffffd24d%s:|r %s%s — %s%s%s|r (%s%s)%s  %s", L["Loot Roll"], qtyTxt, itemTxt, winTag, wHex, wName, cLbl, rollPart, myPart, resultsTag)
    end

    local choicesLine = self:FormatChatAllChoicesLine(rec)
    local isAddonMode = Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode()

    local function EmitChatLine(txt)
        -- Write directly to DEFAULT_CHAT_FRAME so rapid identical boss drops are never dropped by ns:Print's 3s dedup.
        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("|cff58a6ffSocialCentral|r: " .. txt)
        elseif ns.Print then
            ns:Print("%s", txt)
        end
        if (not isAddonMode) and ns.Chat and ns.Chat.RecordGeneralMessage then
            ns.Chat:RecordGeneralMessage("LOOT", "SocialCentral", txt, false, nil, "SC", {
                noSenderColon = false,
                isStatusNotice = true,
            })
        end
    end

    EmitChatLine(bodyLine)
    if choicesLine then
        EmitChatLine(choicesLine)
    end
end

function LootRoll:NotifyRollResolved(rec)
    if not rec then return false end
    if not (rec.winnerName or rec.allPassed) then return false end

    local winnerEntry = nil
    for _, ch in pairs(rec.choices or {}) do
        if type(ch) == "table" and ch.won == true then
            winnerEntry = ch
            break
        end
    end
    if winnerEntry then
        rec.winnerName = rec.winnerName or winnerEntry.name
        rec.winnerClass = rec.winnerClass or winnerEntry.classFile
        rec.winnerChoice = rec.winnerChoice or winnerEntry.choice
        rec.winnerRoll = rec.winnerRoll or winnerEntry.roll
        rec.winnerIsMe = (winnerEntry.isMe == true) or (Compat and Compat.IsMe and Compat.IsMe(rec.winnerName)) or false
    elseif rec.winnerName then
        rec.winnerIsMe = (Compat and Compat.IsMe and Compat.IsMe(rec.winnerName)) or false
        if not rec.winnerClass then
            local lk = Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(rec.winnerName)
            rec.winnerClass = LookupGroupMemberClass(rec.winnerName, lk)
        end
    end

    if not rec.resolvedAt then
        rec.resolvedAt = time()
    end
    self:CommitRecordToHistory(rec)

    if rec._winnerNotified then
        return false
    end
    rec._winnerNotified = true
    self.unreadResultsCount = (self.unreadResultsCount or 0) + 1

    self:PlayWinnerChime(rec.winnerIsMe == true, rec.quality)
    ns:Emit("LOOT_ROLL_WINNER", rec)
    ns:Emit("LOOT_ROLL_UPDATED", rec.rollID)

    if self:IsWinnerChatAnnounceEnabled() then
        if rec.isSimulated or not (C_Timer and C_Timer.After) then
            self:AnnounceWinnerInChat(rec)
        else
            -- Wait briefly so C_LootHistory / CHAT_MSG_LOOT can finish attaching final teammate roll numbers before printing summary in General.
            local targetRec = rec
            C_Timer.After(0.45, function()
                if not targetRec or targetRec._chatAnnounced then return end
                self:SyncLootHistory()
                targetRec._chatAnnounced = true
                self:AnnounceWinnerInChat(targetRec)
            end)
        end
    end
    return true
end

function LootRoll:GetRollByID(rollID)
    return self.activeRolls[rollID] or self.recentRolls[rollID]
end

function LootRoll:IsHistoryRecordActive(rec)
    if type(rec) ~= "table" or rec.resolved == true or not rec.rollID then
        return false
    end
    local ar = self.activeRolls[rec.rollID]
    if not ar then return false end
    local arId = ar.historyId or GenerateHistoryId(ar)
    local rId = rec.id or rec.historyId
    return (rId ~= nil and arId == rId)
end

function LootRoll:GetActiveList()
    local out = {}
    local nowMono = GetTime and GetTime() or 0
    for i = #self.rollOrder, 1, -1 do
        local rId = self.rollOrder[i]
        local rec = self.activeRolls[rId]
        if rec then
            local remMs
            if rec.isSimulated then
                remMs = math.max(0, math.floor(((rec.simExpiresAt or 0) - nowMono) * 1000))
            else
                remMs = GetLootRollTimeLeft and Safe.Number(Safe.Call(GetLootRollTimeLeft, rId)) or nil
            end
            if remMs ~= nil and remMs <= 0 and not rec.myChoice and not rec.resolved and not rec.pendingConfirm then
                -- Grace window (3.5s) in case the player voted via Blizzard's official bar and CHAT_MSG_LOOT hasn't arrived yet.
                if not rec._zeroRemSeenAt then
                    rec._zeroRemSeenAt = nowMono
                elseif (nowMono - rec._zeroRemSeenAt) >= 3.5 then
                    rec.expired = true
                end
            elseif remMs and remMs > 0 then
                rec._zeroRemSeenAt = nil
            end
            local withinWait = (not rec.maxWaitAt or nowMono < rec.maxWaitAt)
            local withinHide = (not rec.hideAfterAt or nowMono < rec.hideAfterAt)
            if not rec.expired and withinWait and withinHide then
                out[#out + 1] = rec
            else
                self.activeRolls[rId] = nil
                table.remove(self.rollOrder, i)
            end
        else
            table.remove(self.rollOrder, i)
        end
    end
    local l, r = 1, #out
    while l < r do
        out[l], out[r] = out[r], out[l]
        l = l + 1
        r = r - 1
    end
    return out
end

function LootRoll:GetActiveCount()
    if not self:IsEnabled() then
        return 0
    end
    local count = 0
    local nowMono = GetTime and GetTime() or 0
    for i = #self.rollOrder, 1, -1 do
        local rId = self.rollOrder[i]
        local rec = self.activeRolls[rId]
        if rec then
            local remMs
            if rec.isSimulated then
                remMs = math.max(0, math.floor(((rec.simExpiresAt or 0) - nowMono) * 1000))
            else
                remMs = GetLootRollTimeLeft and Safe.Number(Safe.Call(GetLootRollTimeLeft, rId)) or nil
            end
            if remMs ~= nil and remMs <= 0 and not rec.myChoice and not rec.resolved and not rec.pendingConfirm then
                if not rec._zeroRemSeenAt then
                    rec._zeroRemSeenAt = nowMono
                elseif (nowMono - rec._zeroRemSeenAt) >= 3.5 then
                    rec.expired = true
                end
            elseif remMs and remMs > 0 then
                rec._zeroRemSeenAt = nil
            end
            local withinWait = (not rec.maxWaitAt or nowMono < rec.maxWaitAt)
            local withinHide = (not rec.hideAfterAt or nowMono < rec.hideAfterAt)
            if not rec.expired and withinWait and withinHide then
                count = count + 1
            else
                self.activeRolls[rId] = nil
                table.remove(self.rollOrder, i)
            end
        else
            table.remove(self.rollOrder, i)
        end
    end
    return count
end

--- Returns true when any active tracked loot roll still awaits a choice from the player.
function LootRoll:HasUnvotedActiveRoll()
    if not self:IsEnabled() then
        return false
    end
    for i = #self.rollOrder, 1, -1 do
        local rId = self.rollOrder[i]
        local rec = self.activeRolls[rId]
        if rec and not rec.expired and not rec.myChoice and not rec.resolved then
            return true
        end
    end
    return false
end

function LootRoll:GetUnvotedCount()
    if not self:IsEnabled() then return 0 end
    local cnt = 0
    for i = 1, #self.rollOrder do
        local rec = self.activeRolls[self.rollOrder[i]]
        if rec and not rec.expired and not rec.myChoice and not rec.resolved then
            cnt = cnt + 1
        end
    end
    return cnt
end

function LootRoll:GetUnreadCount()
    return self.unreadResultsCount or 0
end

function LootRoll:MarkResultsRead()
    if (self.unreadResultsCount or 0) > 0 then
        self.unreadResultsCount = 0
        ns:Emit("LOOT_ROLL_RESULTS_READ")
    end
end

function LootRoll:IsInsideDungeonOrRaid()
    local inInst, instType, instName = ResolveSafeInstanceContext()
    return inInst == true, instType, instName
end

function LootRoll:GetPostRunRemainingSec()
    local untilWall = tonumber(self._postRunVisibleUntil)
    if (not untilWall or untilWall <= 0) and type(SocialCentralCharDB) == "table" then
        untilWall = Safe.Number(SocialCentralCharDB._lootRollPostRunUntil)
    end
    if not untilWall or untilWall <= 0 then
        return 0
    end
    local rem = math.floor(untilWall - time())
    if rem <= 0 then
        return 0
    end
    return rem
end

function LootRoll:SchedulePostRunExpiry(secLeft)
    self._postRunHideTok = (self._postRunHideTok or 0) + 1
    local tok = self._postRunHideTok
    local delay = math.max(1, math.floor(tonumber(secLeft) or 0) + 1)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function()
            if LootRoll._postRunHideTok ~= tok then return end
            if LootRoll:GetPostRunRemainingSec() <= 0 then
                LootRoll._postRunVisibleUntil = nil
                if type(SocialCentralCharDB) == "table" then
                    SocialCentralCharDB._lootRollPostRunUntil = nil
                end
                ns:Emit("LOOT_ROLL_VISIBILITY_CHANGED")
            else
                LootRoll:SchedulePostRunExpiry(LootRoll:GetPostRunRemainingSec())
            end
        end)
    end
end

function LootRoll:ResolveCurrentGroupRunMeta(zoneHint)
    local inRunInst, instType, instName = ResolveSafeInstanceContext()
    local curZone = (zoneHint and zoneHint ~= "") and zoneHint
        or ((inRunInst and instName and instName ~= "") and instName)
        or (Compat and Compat.CurrentZoneName and Compat.CurrentZoneName())
        or ""
    local rosterSig, groupCount = CaptureCurrentRosterMeta()
    local activeRun = ns.Group and ns.Group._activeRun
    if activeRun and (activeRun.zone or "") ~= "" then
        local rk = "run:" .. tostring(activeRun.startedAt or activeRun.enteredAt or 0) .. ":" .. tostring(activeRun.zone or curZone)
        return {
            runKey = rk,
            instType = activeRun.instType or instType,
            groupCount = math.max(groupCount or 1, activeRun.peakSize or 1),
            rosterSig = rosterSig,
        }
    end
    local nowWall = time()
    local sess = self._currentRollGroupMeta
    local sameSession = false
    if sess and (nowWall - (sess.lastAt or 0)) <= 2700 then
        if (sess.zone or "") == curZone and (sess.instType or "") == (instType or "") then
            if sess.rosterSig == rosterSig or rosterSig == "" or sess.rosterSig == "" then
                sameSession = true
            else
                -- Consider same group if any non-self teammate overlaps
                local myFull = (Compat and Compat.MyFullName and Compat.MyFullName()) or Safe.String(UnitName and UnitName("player")) or ""
                local myLk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(myFull)) or myFull:lower()
                local oldSet = {}
                for tok in tostring(sess.rosterSig):gmatch("[^,]+") do
                    if tok ~= "" and tok ~= myLk then oldSet[tok] = true end
                end
                local shared = false
                for tok in tostring(rosterSig):gmatch("[^,]+") do
                    if tok ~= "" and tok ~= myLk and oldSet[tok] then
                        shared = true
                        break
                    end
                end
                sameSession = shared
            end
        end
    end
    if not sameSession then
        self._groupSessSeq = (self._groupSessSeq or 0) + 1
        sess = {
            runKey = "grp:" .. tostring(nowWall) .. ":" .. tostring(self._groupSessSeq) .. ":" .. curZone,
            zone = curZone,
            instType = instType,
            rosterSig = rosterSig,
            groupCount = groupCount,
            lastAt = nowWall,
        }
        self._currentRollGroupMeta = sess
    else
        sess.lastAt = nowWall
        if groupCount and groupCount > (sess.groupCount or 0) then
            sess.groupCount = groupCount
        end
        if rosterSig ~= "" then
            sess.rosterSig = rosterSig
        end
    end
    return {
        runKey = sess.runKey,
        instType = sess.instType,
        groupCount = sess.groupCount,
        rosterSig = sess.rosterSig,
    }
end

function LootRoll:UpdateInstancePresence(fromFinalize)
    local inRunInst, instType, instName = ResolveSafeInstanceContext()
    local charDb = (type(SocialCentralCharDB) == "table") and SocialCentralCharDB or nil
    local wasIn = (self._inDungeonOrRaid == true) or (charDb and charDb._lootRollWasInInstance == true)

    if inRunInst then
        self._inDungeonOrRaid = true
        self._activeInstType = instType
        self._activeInstZone = instName
        self._postRunVisibleUntil = nil
        self._postRunHideTok = (self._postRunHideTok or 0) + 1
        if charDb then
            charDb._lootRollWasInInstance = true
            charDb._lootRollPostRunUntil = nil
        end
        ns:Emit("LOOT_ROLL_VISIBILITY_CHANGED")
        return
    end

    self._inDungeonOrRaid = false
    self._activeInstType = nil
    self._activeInstZone = nil

    if wasIn or fromFinalize == true then
        if charDb then
            charDb._lootRollWasInInstance = nil
        end
        local untilWall = time() + POST_RUN_VISIBLE_SEC
        self._postRunVisibleUntil = untilWall
        if charDb then
            charDb._lootRollPostRunUntil = untilWall
        end
        self:SchedulePostRunExpiry(POST_RUN_VISIBLE_SEC)
    else
        local rem = self:GetPostRunRemainingSec()
        if rem > 0 then
            self._postRunVisibleUntil = time() + rem
            self:SchedulePostRunExpiry(rem)
        else
            self._postRunVisibleUntil = nil
            if charDb then
                charDb._lootRollPostRunUntil = nil
            end
        end
    end
    ns:Emit("LOOT_ROLL_VISIBILITY_CHANGED")
end

local function ExtractRecTeammates(rec)
    local set = {}
    local names = {}
    local seenNames = {}
    local myFull = (Compat and Compat.MyFullName and Compat.MyFullName()) or Safe.String(UnitName and UnitName("player")) or ""
    local myLk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(myFull)) or myFull:lower()
    local rCharLk = rec and rec.charName and ((Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(rec.charName)) or rec.charName:lower()) or myLk

    local function AddName(disp, isMeFlag)
        if type(disp) ~= "string" or disp == "" or disp == "?" then return end
        local lk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(disp)) or disp:lower()
        if not seenNames[lk] then
            seenNames[lk] = true
            names[#names + 1] = disp
        end
        if isMeFlag or lk == myLk or lk == rCharLk then
            return
        end
        set[lk] = true
    end

    if type(rec and rec.choices) == "table" then
        for _, ch in pairs(rec.choices) do
            if type(ch) == "table" then
                AddName(ch.n or ch.name, (ch.me == true or ch.isMe == true))
            end
        end
    end
    if type(rec and rec.rosterSig) == "string" and rec.rosterSig ~= "" then
        for tok in rec.rosterSig:gmatch("[^,]+") do
            if tok ~= "" and tok ~= myLk and tok ~= rCharLk then
                set[tok] = true
            end
        end
    end
    return set, names
end

local function AreTeammateSetsCompatible(setA, setB)
    local cntA, cntB = 0, 0
    for _ in pairs(setA) do cntA = cntA + 1 end
    for _ in pairs(setB) do cntB = cntB + 1 end
    if cntA == 0 or cntB == 0 then
        return true
    end
    local shared = 0
    for k in pairs(setA) do
        if setB[k] then
            shared = shared + 1
            break
        end
    end
    if cntA >= 2 and cntB >= 2 and shared == 0 then
        return false
    end
    return true
end

function LootRoll:GetLatestRunRecords(allSorted)
    if type(allSorted) ~= "table" or #allSorted == 0 then
        return {}, {
            zone = "",
            instType = nil,
            ts = nil,
            startedAt = nil,
            total = 0,
            won = 0,
            active = 0,
            allPassed = 0,
            participantCount = 0,
            participants = {},
            isSimulated = false,
        }
    end

    local anchor = allSorted[1]
    local anchorSim = (anchor.isSimulated == true)
    local anchorTs = tonumber(anchor.ts) or tonumber(anchor.createdAt) or 0
    local anchorZone = tostring(anchor.zone or "")
    local anchorChar = tostring(anchor.charName or "")
    local anchorRunKey = type(anchor.runKey) == "string" and anchor.runKey ~= "" and anchor.runKey or nil
    local anchorPeers = ExtractRecTeammates(anchor)

    local runItems = {}
    local participantMap = {}
    local participantList = {}
    local wonCount, activeCount, allPassedCount = 0, 0, 0
    local earliestTs = anchorTs
    local maxGroupHint = tonumber(anchor.groupCount) or 0
    local prevTs = anchorTs

    local function CollectParticipants(rec)
        local _, rawNames = ExtractRecTeammates(rec)
        for _, nm in ipairs(rawNames) do
            local lk = LowerUtf8Safe(nm)
            if not participantMap[lk] then
                participantMap[lk] = true
                participantList[#participantList + 1] = nm
            end
        end
        if type(rec.rosterSig) == "string" and rec.rosterSig ~= "" then
            local sigCount = 0
            for _ in rec.rosterSig:gmatch("[^,]+") do
                sigCount = sigCount + 1
            end
            if sigCount > maxGroupHint then
                maxGroupHint = sigCount
            end
        end
    end

    for _, cand in ipairs(allSorted) do
        local candSim = (cand.isSimulated == true)
        local matches = false
        if candSim == anchorSim then
            local candRunKey = type(cand.runKey) == "string" and cand.runKey ~= "" and cand.runKey or nil
            if anchorRunKey and candRunKey then
                matches = (anchorRunKey == candRunKey)
            elseif not anchorRunKey and not candRunKey then
                local cChar = tostring(cand.charName or "")
                local cZone = tostring(cand.zone or "")
                local cTs = tonumber(cand.ts) or tonumber(cand.createdAt) or 0
                local sameChar = (anchorChar == "" or cChar == "" or anchorChar == cChar)
                local sameZone = (anchorZone == "" or cZone == "" or anchorZone == cZone)
                local gapOk = (prevTs == 0 or cTs == 0 or math.abs(prevTs - cTs) <= 2700)
                local spanOk = (anchorTs == 0 or cTs == 0 or math.abs(anchorTs - cTs) <= 14400)
                if sameChar and sameZone and gapOk and spanOk then
                    local candPeers = ExtractRecTeammates(cand)
                    if AreTeammateSetsCompatible(anchorPeers, candPeers) then
                        matches = true
                        for k in pairs(candPeers) do
                            anchorPeers[k] = true
                        end
                    end
                end
            elseif cand._isActive and not cand.resolved then
                local cZone = tostring(cand.zone or "")
                if anchorZone == "" or cZone == "" or anchorZone == cZone then
                    matches = true
                end
            end
        end

        if matches then
            runItems[#runItems + 1] = cand
            local cTs = tonumber(cand.ts) or tonumber(cand.createdAt) or 0
            if cTs > 0 then
                prevTs = cTs
                if earliestTs == 0 or cTs < earliestTs then
                    earliestTs = cTs
                end
            end
            if cand.wonByMe == true or cand.winnerIsMe == true then
                wonCount = wonCount + 1
            end
            if cand._isActive and not cand.resolved then
                activeCount = activeCount + 1
            end
            if cand.allPassed == true then
                allPassedCount = allPassedCount + 1
            end
            if tonumber(cand.groupCount) and tonumber(cand.groupCount) > maxGroupHint then
                maxGroupHint = tonumber(cand.groupCount)
            end
            CollectParticipants(cand)
        elseif #runItems > 0 and not (cand._isActive and not cand.resolved) then
            -- Contiguous latest cluster ends once we cross into another zone/time/run boundary
            if not anchorRunKey then
                break
            end
        end
    end

    table.sort(participantList)
    local pCount = math.max(#participantList, maxGroupHint)
    return runItems, {
        zone = (anchorZone ~= "") and anchorZone or L["Group"],
        instType = anchor.instType,
        ts = anchorTs,
        startedAt = earliestTs,
        total = #runItems,
        won = wonCount,
        active = activeCount,
        allPassed = allPassedCount,
        participantCount = pCount,
        participants = participantList,
        isSimulated = anchorSim,
    }
end

function LootRoll:GetLatestRunSummary()
    local all = self:GetResultsList({ filter = "ALL", query = "", scope = "all" })
    local _, summary = self:GetLatestRunRecords(all)
    return summary
end

function LootRoll:GetResultsList(opts)
    opts = opts or {}
    local filter = opts.filter or "ALL"
    local scope = opts.scope or "all"
    local qualityMin = tonumber(opts.qualityMin) or 0
    local sortBy = opts.sortBy or "newest"
    local q = type(opts.query) == "string" and LowerUtf8Safe(opts.query):match("^%s*(.-)%s*$") or ""
    local curChar = (Compat and Compat.MyFullName and Compat.MyFullName()) or Safe.String(UnitName and UnitName("player")) or ""
    local curCharLk = (curChar ~= "" and Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(curChar)) or LowerUtf8Safe(curChar)

    local byId = {}
    local merged = {}
    local function ShallowView(src, isActiveFlag)
        local view = {}
        for k, v in pairs(src) do
            if k ~= "_isActive" then
                view[k] = v
            end
        end
        view._isActive = isActiveFlag and true or nil
        return view
    end

    local function AddEntry(entry, isActiveFlag, alreadyFresh)
        if type(entry) ~= "table" then return end
        local eid = entry.id or GenerateHistoryId(entry)
        if byId[eid] then
            if isActiveFlag then
                byId[eid]._isActive = true
            end
            return
        end
        local view = alreadyFresh and entry or ShallowView(entry, isActiveFlag)
        if alreadyFresh then
            view._isActive = isActiveFlag and true or nil
        end
        byId[eid] = view
        merged[#merged + 1] = view
    end

    for _, rId in ipairs(self.rollOrder) do
        local ar = self.activeRolls[rId]
        if ar then
            local ser = self:SerializeRollRecord(ar)
            if ser then
                AddEntry(ser, true, true)
            end
        end
    end
    for _, sr in ipairs(self.simHistory) do
        AddEntry(sr, self:IsHistoryRecordActive(sr), false)
    end
    local saved = SocialCentralDB and SocialCentralDB.lootRollHistory
    if type(saved) == "table" then
        for _, rec in ipairs(saved) do
            AddEntry(rec, self:IsHistoryRecordActive(rec), false)
        end
    end

    table.sort(merged, function(a, b)
        local aa = (a._isActive == true and not a.resolved)
        local ab = (b._isActive == true and not b.resolved)
        if aa ~= ab then return aa end
        local ta = tonumber(a.ts) or tonumber(a.createdAt) or 0
        local tb = tonumber(b.ts) or tonumber(b.createdAt) or 0
        if ta ~= tb then return ta > tb end
        return tostring(a.id or "") > tostring(b.id or "")
    end)

    local pool = merged
    if scope == "latest_run" then
        pool = self:GetLatestRunRecords(merged)
    end

    local out = {}
    for _, rec in ipairs(pool) do
        local passFilter = true
        if filter == "WON_ME" then
            passFilter = (rec.wonByMe == true)
        elseif filter == "MY_ROLLS" then
            passFilter = (rec.myChoice ~= nil and rec.myChoice ~= "PASS")
        elseif filter == "ACTIVE" then
            passFilter = (rec._isActive == true and not rec.resolved)
        elseif filter == "THIS_CHAR" then
            local recCharLk = (type(rec.charName) == "string" and rec.charName ~= "" and Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(rec.charName))
                or LowerUtf8Safe(rec.charName or "")
            passFilter = (curCharLk ~= "" and recCharLk == curCharLk)
        end

        if passFilter and qualityMin > 0 then
            passFilter = ((tonumber(rec.quality) or 1) >= qualityMin)
        end

        if passFilter and q ~= "" then
            local hit = false
            if type(rec.name) == "string" and LowerUtf8Safe(rec.name):find(q, 1, true) then
                hit = true
            elseif type(rec.winnerName) == "string" and LowerUtf8Safe(rec.winnerName):find(q, 1, true) then
                hit = true
            elseif type(rec.zone) == "string" and LowerUtf8Safe(rec.zone):find(q, 1, true) then
                hit = true
            elseif type(rec.bossName) == "string" and LowerUtf8Safe(rec.bossName):find(q, 1, true) then
                hit = true
            elseif type(rec.choices) == "table" then
                for _, ch in ipairs(rec.choices) do
                    if type(ch.n) == "string" and LowerUtf8Safe(ch.n):find(q, 1, true) then
                        hit = true
                        break
                    end
                end
            end
            passFilter = hit
        end

        if passFilter then
            out[#out + 1] = rec
        end
    end

    if sortBy ~= "newest" and #out > 1 then
        table.sort(out, function(a, b)
            local aa = (a._isActive == true and not a.resolved)
            local ab = (b._isActive == true and not b.resolved)
            if aa ~= ab then return aa end
            if sortBy == "quality" then
                local qa, qb = tonumber(a.quality) or 1, tonumber(b.quality) or 1
                if qa ~= qb then return qa > qb end
            elseif sortBy == "roll" then
                local ra, rb = tonumber(a.winnerRoll) or -1, tonumber(b.winnerRoll) or -1
                if ra ~= rb then return ra > rb end
            elseif sortBy == "winner" then
                local wa, wb = LowerUtf8Safe(a.winnerName or "zzz"), LowerUtf8Safe(b.winnerName or "zzz")
                if wa ~= wb then return wa < wb end
            end
            local ta = tonumber(a.ts) or tonumber(a.createdAt) or 0
            local tb = tonumber(b.ts) or tonumber(b.createdAt) or 0
            if ta ~= tb then return ta > tb end
            return tostring(a.id or "") > tostring(b.id or "")
        end)
    end

    return out
end

function LootRoll:GetRunAnalytics(pool)
    local total, wonByMe, myRolls, myRollSum, myRollCount, bestRoll = 0, 0, 0, 0, 0, 0
    local byPlayer = {}
    if type(pool) == "table" then
        for _, rec in ipairs(pool) do
            if type(rec) == "table" then
                total = total + 1
                if rec.wonByMe == true or rec.winnerIsMe == true then
                    wonByMe = wonByMe + 1
                end
                if rec.myChoice and rec.myChoice ~= "PASS" then
                    myRolls = myRolls + 1
                    local mr = tonumber(rec.myRoll)
                    if mr and mr > 0 then
                        myRollSum = myRollSum + mr
                        myRollCount = myRollCount + 1
                        if mr > bestRoll then bestRoll = mr end
                    end
                end
                if rec.winnerName and rec.winnerName ~= "" and not rec.allPassed then
                    local lk = LowerUtf8Safe(rec.winnerName)
                    local entry = byPlayer[lk]
                    if not entry then
                        entry = {
                            name = rec.winnerName,
                            classFile = rec.winnerClass,
                            wins = 0,
                            isMe = (rec.wonByMe == true or rec.winnerIsMe == true),
                        }
                        byPlayer[lk] = entry
                    end
                    entry.wins = entry.wins + 1
                    if not entry.classFile and rec.winnerClass then
                        entry.classFile = rec.winnerClass
                    end
                end
            end
        end
    end
    local perPlayer = {}
    for _, v in pairs(byPlayer) do
        perPlayer[#perPlayer + 1] = v
    end
    table.sort(perPlayer, function(a, b)
        if a.wins ~= b.wins then return a.wins > b.wins end
        if a.isMe ~= b.isMe then return a.isMe end
        return tostring(a.name or "") < tostring(b.name or "")
    end)
    local avgRoll = (myRollCount > 0) and math.floor((myRollSum / myRollCount) + 0.5) or 0
    local winPct = (myRolls > 0) and math.floor((wonByMe * 100 / myRolls) + 0.5) or 0
    return {
        total = total,
        wonByMe = wonByMe,
        myRolls = myRolls,
        winPct = winPct,
        avgRoll = avgRoll,
        bestRoll = bestRoll,
        perPlayer = perPlayer,
    }
end

function LootRoll:GetResultById(idOrRollId)
    if idOrRollId == nil then return nil end
    local numId = tonumber(idOrRollId)
    if numId and self.activeRolls[numId] then
        return self:SerializeRollRecord(self.activeRolls[numId])
    end
    local idStr = tostring(idOrRollId)
    for _, sr in ipairs(self.simHistory) do
        if sr.id == idStr or (numId and sr.rollID == numId) then
            return sr
        end
    end
    local saved = SocialCentralDB and SocialCentralDB.lootRollHistory
    if type(saved) == "table" then
        for _, rec in ipairs(saved) do
            if rec.id == idStr or (numId and rec.rollID == numId) then
                return rec
            end
        end
    end
    if numId and self.recentRolls[numId] then
        return self:SerializeRollRecord(self.recentRolls[numId])
    end
    return nil
end

function LootRoll:GetResultsStats()
    local total, wonByMe = 0, 0
    local seen = {}
    local function CountOne(rec)
        if type(rec) ~= "table" then return end
        local eid = rec.id or GenerateHistoryId(rec)
        if seen[eid] then return end
        seen[eid] = true
        total = total + 1
        if rec.wonByMe == true or rec.winnerIsMe == true then
            wonByMe = wonByMe + 1
        end
    end
    for _, rId in ipairs(self.rollOrder) do
        if self.activeRolls[rId] then
            CountOne(self.activeRolls[rId])
        end
    end
    for _, sr in ipairs(self.simHistory) do CountOne(sr) end
    if SocialCentralDB and type(SocialCentralDB.lootRollHistory) == "table" then
        for _, rec in ipairs(SocialCentralDB.lootRollHistory) do CountOne(rec) end
    end
    return total, wonByMe, (self.unreadResultsCount or 0), self:GetActiveCount()
end

function LootRoll:DeleteResult(historyId)
    if not historyId then return false end
    local removed = false
    for i = #self.simHistory, 1, -1 do
        if self.simHistory[i].id == historyId then
            table.remove(self.simHistory, i)
            removed = true
        end
    end
    local saved = SocialCentralDB and SocialCentralDB.lootRollHistory
    if type(saved) == "table" then
        for i = #saved, 1, -1 do
            if saved[i].id == historyId then
                table.remove(saved, i)
                removed = true
            end
        end
    end
    if removed then
        ns:Emit("LOOT_ROLL_UPDATED")
    end
    return removed
end

function LootRoll:ClearHistory()
    wipe(self.simHistory)
    if SocialCentralDB and type(SocialCentralDB.lootRollHistory) == "table" then
        wipe(SocialCentralDB.lootRollHistory)
    end
    self.unreadResultsCount = 0
    ns:Emit("LOOT_ROLL_UPDATED")
    ns:Emit("LOOT_ROLL_RESULTS_READ")
end

local function SafeAppendChatParts(base, sep, parts, maxBytes)
    maxBytes = maxBytes or 250
    local out = base
    if #parts == 0 then return out end
    local added = 0
    for i = 1, #parts do
        local piece = parts[i]
        local candidate = (added == 0) and (out .. sep .. piece) or (out .. ", " .. piece)
        local remaining = #parts - i
        local tailAllowance = (remaining > 0) and 8 or 0
        if #candidate + tailAllowance <= maxBytes then
            out = candidate
            added = added + 1
        else
            if added > 0 and (#out + 8) <= maxBytes then
                out = out .. ", +" .. tostring(#parts - added)
            end
            break
        end
    end
    return out
end

function LootRoll:FormatWinnerAnnouncementText(rec)
    if not rec then return "" end
    local itemStr = rec.itemLink or rec.link or rec.name or "?"
    if rec.allPassed then
        return string.format("%s — %s", itemStr, L["All passed"])
    elseif rec.winnerName then
        local chLbl = rec.winnerChoice and self:GetRollChoiceLabel(rec.winnerChoice) or L["Won"]
        local rollPart = rec.winnerRoll and (" " .. tostring(rec.winnerRoll)) or ""
        return string.format("%s — %s: %s (%s%s)", itemStr, L["Winner"], rec.winnerName, chLbl, rollPart)
    end
    return string.format("%s — %s", itemStr, L["Roll in progress"])
end

function LootRoll:FormatRollSummaryText(rec)
    if not rec then return "" end
    local header = self:FormatWinnerAnnouncementText(rec)
    local choices = rec.choices
    if type(choices) ~= "table" or #choices == 0 then
        return header
    end
    local parts = {}
    local maxEntries = math.min(10, #choices)
    for i = 1, maxEntries do
        local ch = choices[i]
        local pName = ch.n or ch.name or "?"
        local pChoice = ch.ch or ch.choice or "PASS"
        local pRoll = ch.r or ch.roll
        local lbl = self:GetRollChoiceLabel(pChoice)
        parts[#parts + 1] = pRoll and (pName .. " (" .. lbl .. " " .. tostring(pRoll) .. ")") or (pName .. " (" .. lbl .. ")")
    end
    if #choices > maxEntries then
        parts[#parts + 1] = "+" .. tostring(#choices - maxEntries)
    end
    return SafeAppendChatParts(header, " | ", parts, 250)
end

function LootRoll:FormatChatRollOpenDraft(session)
    local itemStr = (session and session.itemLink) or (session and session.itemName) or nil
    if itemStr then
        return string.format(L["Roll for %s: MS (/roll 100) · OS (/roll 50)"], itemStr)
    end
    return L["Open /roll round: MS (/roll 100) · OS (/roll 50)"]
end

function LootRoll:FormatChatRollTieBreakerDraft(session)
    if not session then return "" end
    local itemStr = session.itemLink or session.itemName or L["Group /roll (1-100)"]
    local names = (type(session.tiedNames) == "table" and #session.tiedNames > 0) and table.concat(session.tiedNames, ", ") or (session.leaderName or "?")
    return string.format(L["TIE (%d) on %s! Re-roll (/roll 100): %s"], tonumber(session.leaderRoll) or 0, itemStr, names)
end

function LootRoll:FormatChatRollWinnerDraft(session)
    if not session then return "" end
    local head = session.itemLink and (session.itemLink .. " — ") or (L["Group /roll (1-100)"] .. " — ")
    if session.leaderName and session.leaderRoll then
        if session.isTied then
            return self:FormatChatRollTieBreakerDraft(session)
        end
        return head .. string.format("%s: %s (%d)", L["Winner"], session.leaderName, session.leaderRoll)
    elseif session.osLeaderName and session.osLeaderRoll then
        return head .. string.format("%s (OS): %s (%d)", L["Winner"], session.osLeaderName, session.osLeaderRoll)
    end
    return head .. L["No valid 1-100 rolls yet"]
end

function LootRoll:FormatChatRollSummaryText(session)
    if not session then return "" end
    local head = session.itemLink and (session.itemLink .. " — ") or (L["Group /roll (1-100)"] .. " — ")
    if session.leaderName and session.leaderRoll then
        local tieStr = session.isTied and (" (" .. L["Tied!"] .. ")") or ""
        head = head .. string.format("%s: %s (%d)%s", L["Highest Roll"], session.leaderName, session.leaderRoll, tieStr)
    elseif session.osLeaderName and session.osLeaderRoll then
        head = head .. string.format("%s (OS): %s (%d)", L["Highest Roll"], session.osLeaderName, session.osLeaderRoll)
    else
        head = head .. L["No valid 1-100 rolls yet"]
    end
    local parts = {}
    local lim = math.min(10, #(session.rolls or {}))
    for i = 1, lim do
        local r = session.rolls[i]
        local tag = ""
        if r.bracket == "OS" then
            tag = string.format(" [OS 1-%d]", r.maxVal or 50)
        elseif not r.isStandard100 then
            tag = string.format(" [%d-%d!]", r.minVal or 1, r.maxVal or 100)
        elseif r.isDuplicate then
            tag = " [dup!]"
        end
        parts[#parts + 1] = string.format("%s: %d%s", r.name or "?", r.roll or 0, tag)
    end
    return SafeAppendChatParts(head, " | ", parts, 250)
end

local function HideBlizzardLootConfirmPopups(rollID)
    if not _G.StaticPopup_Hide then return end
    -- Only close if the active popup belongs to this rollID (avoid touching unrelated dialogs)
    for idx = 1, 4 do
        local pop = _G["StaticPopup" .. idx]
        if pop and pop.IsShown and pop:IsShown() then
            local which = pop.which
            if (which == "CONFIRM_LOOT_ROLL" or which == "CONFIRM_DISENCHANT_ROLL") and (not rollID or pop.data == rollID) then
                pcall(_G.StaticPopup_Hide, which, pop.data)
            end
        end
    end
end

function LootRoll:FinalizeLocalRollSelection(rec, rollType)
    if not rec then return end
    local map = { [0] = "PASS", [1] = "NEED", [2] = "GREED", [3] = "DE" }
    rec.pendingConfirm = nil
    rec.myChoice = map[rollType] or "PASS"
    rec._localMyChoice = rec.myChoice
    local me = (Compat and Compat.MyFullName and Compat.MyFullName()) or Safe.String(UnitName and UnitName("player")) or L["You"]
    local lk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(me)) or "__self__"
    local _, myCls = UnitClass("player")
    local myRoll = (rec.isSimulated and rec.myChoice ~= "PASS") and math.random(18, 99) or nil
    if myRoll then
        rec.myRoll = myRoll
    end
    rec.choices[lk] = {
        name = me,
        classFile = Safe.String(myCls),
        choice = rec.myChoice,
        _confirmedChoice = rec.myChoice,
        roll = myRoll,
        updatedAt = time(),
        isMe = true,
    }
    local nowMono = GetTime and GetTime() or 0
    if rec.isSimulated then
        rec.hideAfterAt = nowMono + 10.0
    else
        rec.maxWaitAt = math.max(rec.maxWaitAt or 0, nowMono + (rec.durationSec or 60) + 14.0)
    end
    self:QueueHistoryCommit(rec, true)
    if rec.isSimulated and C_Timer and C_Timer.After then
        local simRec = rec
        C_Timer.After(1.3, function()
            if not simRec or simRec.expired then return end
            local bestEntry, bestScore = nil, -1
            for _, ch in pairs(simRec.choices or {}) do
                if type(ch) == "table" and ch.choice and ch.choice ~= "PASS" then
                    if not ch.roll then ch.roll = math.random(12, 97) end
                    local sc = (self:GetChoicePriority(ch.choice, false) * 100) + (tonumber(ch.roll) or 0)
                    if sc > bestScore then
                        bestScore = sc
                        bestEntry = ch
                    end
                end
            end
            if bestEntry then
                for _, ch in pairs(simRec.choices or {}) do
                    if type(ch) == "table" and ch ~= bestEntry then
                        ch.won = false
                    end
                end
                bestEntry.won = true
                simRec.resolved = true
                simRec.winnerName = bestEntry.name
                simRec.winnerClass = bestEntry.classFile
                simRec.winnerChoice = bestEntry.choice
                simRec.winnerRoll = bestEntry.roll
            else
                simRec.allPassed = true
                simRec.resolved = true
            end
            self:NotifyRollResolved(simRec)
        end)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0.45, function() self:SyncLootHistory() end)
        C_Timer.After(1.5, function() self:SyncLootHistory() end)
    end
    ns:Emit("LOOT_ROLL_UPDATED", rec.rollID)
end

function LootRoll:OnConfirmLootRoll(rollID, rollType, confirmReason)
    local rId = Safe.Number(rollID)
    local rType = Safe.Number(rollType)
    if not rId or not rType then return end
    local rec = self.activeRolls[rId]
    if not rec or rec.resolved then return end
    local map = { [0] = "PASS", [1] = "NEED", [2] = "GREED", [3] = "DE" }
    -- Roll is awaiting BoP/DE confirmation; keep buttons unlockable if player cancels!
    rec.myChoice = nil
    rec._localMyChoice = nil
    local me = (Compat and Compat.MyFullName and Compat.MyFullName()) or Safe.String(UnitName and UnitName("player")) or ""
    local lk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(me)) or "__self__"
    if rec.choices and rec.choices[lk] and not rec.choices[lk].roll then
        rec.choices[lk] = nil
    end
    rec.pendingConfirm = {
        rollType = rType,
        choice = map[rType] or "NEED",
        confirmReason = Safe.String(confirmReason),
        at = GetTime and GetTime() or 0,
    }
    ns:Emit("LOOT_ROLL_UPDATED", rId)
end

function LootRoll:ConfirmPendingRoll(rollID)
    local rec = self.activeRolls[rollID]
    if not (rec and rec.pendingConfirm) then return false end
    local rType = rec.pendingConfirm.rollType
    local ok = false
    if rec.isSimulated then
        ok = true
    elseif _G.ConfirmLootRoll then
        ok = pcall(_G.ConfirmLootRoll, rollID, rType)
    end
    if ok then
        HideBlizzardLootConfirmPopups(rollID)
        self:FinalizeLocalRollSelection(rec, rType)
    end
    return ok
end

function LootRoll:CancelPendingRoll(rollID)
    local rec = self.activeRolls[rollID]
    if not (rec and rec.pendingConfirm) then return false end
    rec.pendingConfirm = nil
    HideBlizzardLootConfirmPopups(rollID)
    ns:Emit("LOOT_ROLL_UPDATED", rollID)
    return true
end

function LootRoll:SubmitRoll(rollID, rollType)
    local rec = self.activeRolls[rollID]
    if not rec then return false end
    local ok = false
    if rec.isSimulated then
        ok = true
    else
        local fn = _G.RollOnLoot
        if not fn then return false end
        ok = pcall(fn, rollID, rollType)
    end
    if ok then
        -- Real non-Pass rolls on BoP items trigger CONFIRM_LOOT_ROLL; wait for confirmation so canceling never locks buttons!
        if (not rec.isSimulated) and rollType ~= 0 and (rec.bindOnPickUp == true or rec.pendingConfirm ~= nil) then
            if not rec.pendingConfirm then
                local map = { [0] = "PASS", [1] = "NEED", [2] = "GREED", [3] = "DE" }
                rec.pendingConfirm = {
                    rollType = rollType,
                    choice = map[rollType] or "NEED",
                    at = GetTime and GetTime() or 0,
                }
            end
            ns:Emit("LOOT_ROLL_UPDATED", rollID)
            return true
        end
        self:FinalizeLocalRollSelection(rec, rollType)
    end
    return ok
end

-- Explicit hardware-click batch action (never automated): Pass all remaining unvoted, or Greed all remaining non-BoP unusable/downgrade items.
function LootRoll:SubmitBatchUnvoted(mode)
    if not self:IsEnabled() then return 0 end
    local active = self:GetActiveList()
    local acted = 0
    for _, rec in ipairs(active) do
        if rec and not rec.myChoice and not rec.resolved and not rec.pendingConfirm then
            if mode == "PASS_ALL" then
                if self:SubmitRoll(rec.rollID, 0) then
                    acted = acted + 1
                end
            elseif mode == "GREED_UNUSABLE" then
                local comp = rec.comparison
                local isUnusableOrDown = comp and (comp.verdict == "CANNOT_EQUIP" or comp.verdict == "DOWNGRADE" or comp.verdict == "UNIQUE_OWNED" or comp.verdict == "RECIPE_KNOWN")
                if isUnusableOrDown and rec.canGreed and not rec.bindOnPickUp then
                    if self:SubmitRoll(rec.rollID, 2) then
                        acted = acted + 1
                    end
                elseif isUnusableOrDown and not rec.canGreed then
                    if self:SubmitRoll(rec.rollID, 0) then
                        acted = acted + 1
                    end
                end
            end
        end
    end
    return acted
end

function LootRoll:PruneRecentRolls()
    local count = 0
    for _ in pairs(self.recentRolls) do count = count + 1 end
    while count > self.maxRecent do
        local oldestId, oldestAt = nil, nil
        for rId, r in pairs(self.recentRolls) do
            if not self.activeRolls[rId] then
                local st = tonumber(r.createdAt) or 0
                if oldestAt == nil or st < oldestAt then
                    oldestAt = st
                    oldestId = rId
                end
            end
        end
        if oldestId then
            self.recentRolls[oldestId] = nil
            count = count - 1
        else
            break
        end
    end
end

function LootRoll:FindMatchingRollRecord(itemLink, opts)
    local itemID = ExtractItemIdFromLink(itemLink)
    opts = opts or {}
    local isWin = opts.isWin == true
    local pName = opts.playerName and ResolveForeverDisplayName(NormalizePlayerToken(opts.playerName), opts.guid) or nil
    local pLk = pName and ((Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(pName)) or LowerUtf8Safe(pName)) or nil
    local isSelf = opts.isSelf == true
    local nowWall = time()

    local function ScoreCandidate(rec, fromActive)
        if not rec or rec.isSimulated then return -1 end
        local idMatch = (itemID and rec.itemID == itemID)
        local linkMatch = (itemLink and rec.link == itemLink)
        if not idMatch and not linkMatch then return -1 end
        if opts.excludeBoundHistory and opts.encId and opts.listId then
            if rec.encounterID and rec.lootListID and (rec.encounterID ~= opts.encId or rec.lootListID ~= opts.listId) then
                return -1
            end
        end
        if not fromActive and (nowWall - (rec.createdAt or 0)) > 240 then
            return -1
        end
        if opts.isLootFallback and (rec.resolved or (not fromActive and (nowWall - (rec.createdAt or 0)) > 90)) then
            return -1
        end
        local score = fromActive and 1000 or 200
        if linkMatch then score = score + 50 end
        if not rec.resolved then score = score + 400 end
        if isWin and rec.resolved then
            return -1
        end
        local cKey = (pLk or isSelf) and FindChoiceEntryKey(rec, pName or "", pLk, isSelf) or nil
        local existing = cKey and rec.choices and rec.choices[cKey] or nil
        if opts.isLootFallback and next(rec.choices or {}) ~= nil then
            if not existing or existing.choice == "PASS" then
                return -1
            end
        end
        if opts.mode == "ROLLED" or opts.mode == "ROLLED_SELF" then
            if existing and existing.choice == opts.choice and not existing.roll then
                score = score + 250
            elseif not existing then
                score = score + 100
            end
        elseif opts.mode == "PICK" or opts.mode == "PICK_SELF" then
            if existing and not existing._confirmedChoice then
                score = score + 150
            elseif not existing then
                score = score + 250
            end
        elseif isWin and existing and not existing.won and existing.choice ~= "PASS" then
            score = score + 200
        end
        return score
    end

    -- Prefer OLDEST unresolved matching record (FIFO) on equal score so duplicate drops resolve in drop order.
    local best, bestScore, bestAt = nil, -1, nil
    for _, rec in pairs(self.activeRolls) do
        local sc = ScoreCandidate(rec, true)
        local at = rec.createdAt or 0
        if sc >= 0 and (sc > bestScore or (sc == bestScore and (bestAt == nil or at < bestAt))) then
            best = rec
            bestScore = sc
            bestAt = at
        end
    end
    for _, rec in pairs(self.recentRolls) do
        if not self.activeRolls[rec.rollID] then
            local sc = ScoreCandidate(rec, false)
            local at = rec.createdAt or 0
            if sc >= 0 and (sc > bestScore or (sc == bestScore and (bestAt == nil or at < bestAt))) then
                best = rec
                bestScore = sc
                bestAt = at
            end
        end
    end
    return best
end

function LootRoll:GetRecentBossName()
    local nowWall = time()
    if self._lastBossName and self._lastBossName ~= "" and self._lastBossAt and (nowWall - self._lastBossAt) <= 120 then
        return self._lastBossName
    end
    local activeRun = ns.Group and ns.Group._activeRun
    if activeRun and type(activeRun.lastBossName) == "string" and activeRun.lastBossName ~= "" then
        return activeRun.lastBossName
    end
    return nil
end

function LootRoll:OnStartLootRoll(rollID, rollTime)
    local rId = Safe.Number(rollID)
    if not rId or not GetLootRollItemInfo then return end
    local ok, tex, name, count, quality, bop, canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed, reasonDisenchant, deSkillRequired, canTransmog = pcall(GetLootRollItemInfo, rId)
    if not ok then return end
    local cleanName = Safe.String(name)
    if not cleanName or cleanName == "" then return end
    local link = GetLootRollItemLink and Safe.String(Safe.Call(GetLootRollItemLink, rId)) or nil
    local itemID = ExtractItemIdFromLink(link)
    if itemID and CItemReqLoadFn then
        pcall(CItemReqLoadFn, itemID)
    end
    local durSec = math.max(5, math.floor((Safe.Number(rollTime) or 60000) / 1000))
    local nowWall = time()
    local existing = self.activeRolls[rId]
    local myFullName = (Compat and Compat.MyFullName and Compat.MyFullName()) or Safe.String(UnitName and UnitName("player")) or ""
    local _, myCls = UnitClass("player")
    local recZone = (Compat and Compat.CurrentZoneName and Compat.CurrentZoneName()) or ""
    local runMeta = (not existing) and self:ResolveCurrentGroupRunMeta(recZone) or nil
    local rec = existing or {
        rollID = rId,
        createdAt = nowWall,
        zone = recZone,
        bossName = self:GetRecentBossName(),
        charName = myFullName,
        charClass = Safe.String(myCls),
        realmPool = (Compat and Compat.RealmPool and Compat.RealmPool()) or "",
        runKey = runMeta and runMeta.runKey or nil,
        instType = runMeta and runMeta.instType or nil,
        groupCount = runMeta and runMeta.groupCount or nil,
        rosterSig = runMeta and runMeta.rosterSig or nil,
        choices = {},
    }
    local deReqNum = Safe.Number(deSkillRequired)
    rec.texture = Safe.Value(tex)
    rec.name = cleanName
    rec.count = math.max(1, Safe.Number(count) or 1)
    rec.quality = Safe.Number(quality) or 1
    rec.bindOnPickUp = (Safe.Value(bop) == true)
    rec.canNeed = (Safe.Value(canNeed) == true)
    rec.canGreed = (Safe.Value(canGreed) == true)
    rec.canDisenchant = (Safe.Value(canDisenchant) == true)
    rec.canTransmog = (Safe.Value(canTransmog) == true)
    rec.deSkillRequired = deReqNum
    rec.reasonNeed = DecodeIneligibleReason(reasonNeed, deReqNum)
    rec.reasonGreed = DecodeIneligibleReason(reasonGreed, deReqNum)
    rec.reasonDisenchant = DecodeIneligibleReason(reasonDisenchant, deReqNum)
    rec.link = link
    rec.itemID = itemID
    rec.durationSec = durSec
    rec.maxWaitAt = (GetTime and GetTime() or 0) + durSec + 18.0
    rec.comparison = self:BuildComparison(link, itemID, cleanName, rec._compareSlotOverride)
    GenerateHistoryId(rec)

    if not existing then
        self.activeRolls[rId] = rec
        self.recentRolls[rId] = rec
        self.rollOrder[#self.rollOrder + 1] = rId
        self:PruneRecentRolls()
    end
    self:QueueHistoryCommit(rec, true)

    if not self:HasAnsweredPrompt() then
        ns:Emit("LOOT_ROLL_FIRST_PROMPT", rec)
    else
        ns:Emit("LOOT_ROLL_UPDATED", rId)
    end
end

function LootRoll:RecoverActiveRolls()
    local seen = {}
    local recovered = 0
    if _G.GetActiveLootRollIDs then
        local ok, ids = pcall(_G.GetActiveLootRollIDs)
        if ok and type(ids) == "table" then
            for _, rawId in ipairs(ids) do
                local rId = Safe.Number(rawId)
                if rId and rId > 0 and not seen[rId] then
                    seen[rId] = true
                    local remMs = GetLootRollTimeLeft and Safe.Number(Safe.Call(GetLootRollTimeLeft, rId)) or 0
                    if remMs and remMs > 0 and not self.activeRolls[rId] then
                        self:OnStartLootRoll(rId, remMs)
                        recovered = recovered + 1
                    end
                end
            end
        end
    end
    -- Fallback: inspect official GroupLootFrame1..8 safely (read-only) in case GetActiveLootRollIDs is absent.
    local maxFrames = tonumber(_G.NUM_GROUP_LOOT_FRAMES) or 8
    for i = 1, math.min(maxFrames, 8) do
        local gf = _G["GroupLootFrame" .. i]
        if gf then
            local okForb, isForb = pcall(gf.IsForbidden, gf)
            if okForb and not isForb then
                local rId = Safe.Number(gf.rollID)
                if rId and rId > 0 and not seen[rId] and not self.activeRolls[rId] then
                    seen[rId] = true
                    local remMs = GetLootRollTimeLeft and Safe.Number(Safe.Call(GetLootRollTimeLeft, rId)) or 0
                    if remMs and remMs > 0 then
                        self:OnStartLootRoll(rId, remMs)
                        recovered = recovered + 1
                    end
                end
            end
        end
    end
    if recovered > 0 then
        self:SyncLootHistory()
    end
    return recovered
end

function LootRoll:ApplyChoiceUpdate(rec, opts)
    if not (rec and type(opts) == "table") then return false end
    local rawDisp = NormalizePlayerToken(opts.name or "?")
    local isPronounSelf = IsSelfPronounToken(rawDisp)
    local dispName = ResolveForeverDisplayName(rawDisp, opts.guid)
    local isSelf = (opts.isSelf == true) or isPronounSelf or (Compat and Compat.IsMe and Compat.IsMe(dispName, opts.guid))
    if isSelf then
        local myFull = (Compat and Compat.MyFullName and Compat.MyFullName()) or Safe.String(UnitName and UnitName("player"))
        if myFull and myFull ~= "" then
            dispName = myFull
        elseif not dispName or dispName == "?" or dispName == "" or isPronounSelf then
            dispName = L["You"]
        end
    end
    local rawLk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(dispName)) or LowerUtf8Safe(dispName)
    local key = FindChoiceEntryKey(rec, dispName, rawLk, isSelf)
    local prev = rec.choices[key] or {}
    local changed = false

    -- Merge any earlier literal pronoun entry ("você"/"you") if this resolves to the player.
    if isSelf then
        for altKey, altEntry in pairs(rec.choices or {}) do
            if altKey ~= key and type(altEntry) == "table" and (altEntry.isMe or IsSelfPronounToken(altEntry.name or altKey)) then
                if not prev.choice or prev.choice == "PASS" then
                    prev.choice = altEntry.choice or prev.choice
                end
                if not prev._confirmedChoice and altEntry._confirmedChoice then
                    prev._confirmedChoice = altEntry._confirmedChoice
                end
                if not prev.roll and altEntry.roll then
                    prev.roll = altEntry.roll
                end
                rec.choices[altKey] = nil
                changed = true
            end
        end
    end

    local cleanCls = opts.classFile or prev.classFile or ResolveSafeUnitClassByGUID(opts.guid, dispName, key)
    if prev.name ~= dispName and dispName ~= "?" then
        prev.name = dispName
        changed = true
    elseif not prev.name then
        prev.name = dispName
        changed = true
    end
    if cleanCls and prev.classFile ~= cleanCls then
        prev.classFile = cleanCls
        changed = true
    end
    if isSelf and not prev.isMe then
        prev.isMe = true
        changed = true
    end
    if opts.choice and opts.choice ~= "WON" then
        if opts.fromChat == true then
            prev._confirmedChoice = opts.choice
            if prev.choice ~= opts.choice then
                prev.choice = opts.choice
                changed = true
            end
        elseif isSelf and rec._localMyChoice and rec._localMyChoice ~= "PASS" and opts.choice == "GREED" then
            -- Never let stale or ambiguous history downgrade a directly clicked Need/DE choice.
            if prev.choice ~= rec._localMyChoice then
                prev.choice = rec._localMyChoice
                changed = true
            end
        elseif prev._confirmedChoice and (prev._confirmedChoice == "NEED" or prev._confirmedChoice == "DE") and opts.choice == "GREED" then
            -- Preserve chat/local Need or Disenchant if C_LootHistory maps state ambiguously.
        elseif prev.choice ~= opts.choice then
            prev.choice = opts.choice
            changed = true
        end
    elseif not prev.choice then
        prev.choice = (isSelf and rec._localMyChoice) or opts.choice or (opts.isWin and "NEED") or "PASS"
        changed = true
    end
    local rollNum = opts.roll and Safe.Number(opts.roll) or nil
    if rollNum and prev.roll ~= rollNum then
        prev.roll = rollNum
        changed = true
    end
    if isSelf then
        if prev.choice and prev.choice ~= "WON" then
            rec.myChoice = prev.choice
            rec.pendingConfirm = nil
            if rec._cancelledWithoutChoice then
                rec._cancelledWithoutChoice = nil
                rec.hideAfterAt = nil
            end
        end
        if prev.roll then
            rec.myRoll = prev.roll
        end
    end
    local becameResolved = false
    if opts.isWin then
        for ck, ce in pairs(rec.choices or {}) do
            if ck ~= key and type(ce) == "table" and ce.won then
                ce.won = false
                changed = true
            end
        end
        if not prev.won then
            prev.won = true
            changed = true
        end
        rec.allPassed = false
        rec.pendingConfirm = nil
        rec.winnerName = prev.name
        rec.winnerClass = prev.classFile or rec.winnerClass
        rec.winnerChoice = (prev.choice and prev.choice ~= "WON") and prev.choice or rec.winnerChoice
        rec.winnerRoll = prev.roll or rec.winnerRoll
        rec.winnerIsMe = (prev.isMe == true)
        if not rec.resolved then
            rec.resolved = true
            becameResolved = true
        end
        if not rec._resolvedCountdownSet then
            local nowMono = GetTime and GetTime() or 0
            rec._resolvedCountdownSet = true
            rec.hideAfterAt = math.max(nowMono + 9.0, rec.hideAfterAt or 0)
        end
    elseif prev.won == true then
        -- Keep summary winner metadata synced if a late roll choice update clarified prev.choice/prev.roll.
        rec.winnerName = prev.name or rec.winnerName
        rec.winnerClass = prev.classFile or rec.winnerClass
        if prev.choice and prev.choice ~= "WON" then
            rec.winnerChoice = prev.choice
        end
        if prev.roll then
            rec.winnerRoll = prev.roll
        end
    end
    if changed then
        prev.updatedAt = time()
        rec.choices[key] = prev
        self:QueueHistoryCommit(rec, becameResolved or opts.isWin == true)
    end
    if becameResolved or (opts.isWin and not rec._winnerNotified) then
        self:NotifyRollResolved(rec)
    end
    return changed
end

function LootRoll:HasUnresolvedRecentRolls()
    if next(self.activeRolls) ~= nil then
        return true
    end
    local nowWall = time()
    for _, rec in pairs(self.recentRolls) do
        if rec and not rec.isSimulated and (nowWall - (rec.createdAt or 0)) <= 240 then
            if not rec.resolved then
                return true
            end
            -- Allow brief C_LootHistory backfill for recently resolved drops still missing winner/teammate roll numbers.
            if not rec.allPassed and not rec.isMasterLoot and rec.resolvedAt and (nowWall - rec.resolvedAt) <= 12 then
                if not rec.winnerRoll then
                    return true
                end
                for _, ch in pairs(rec.choices or {}) do
                    if type(ch) == "table" and ch.choice and ch.choice ~= "PASS" and not ch.roll then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function LootRoll:SyncLootHistory()
    if not self:HasUnresolvedRecentRolls() then return false end
    local hist = _G.C_LootHistory
    if not hist then return false end
    local anyChanged = false
    local touchedRolls = {}

    local function FindRecForHistory(encId, listId, itemLink, rollIdNum)
        local itemIDHint = itemLink and ExtractItemIdFromLink(itemLink) or nil
        if rollIdNum then
            local cand = self.activeRolls[rollIdNum] or self.recentRolls[rollIdNum]
            if cand and not cand.isSimulated and (not itemIDHint or not cand.itemID or cand.itemID == itemIDHint) then
                return cand
            end
        end
        if encId and listId then
            for _, candidate in pairs(self.activeRolls) do
                if candidate and not candidate.isSimulated and candidate.encounterID == encId and candidate.lootListID == listId
                    and (not itemIDHint or not candidate.itemID or candidate.itemID == itemIDHint)
                then
                    return candidate
                end
            end
            for _, candidate in pairs(self.recentRolls) do
                if candidate and not candidate.isSimulated and candidate.encounterID == encId and candidate.lootListID == listId
                    and (not itemIDHint or not candidate.itemID or candidate.itemID == itemIDHint)
                then
                    return candidate
                end
            end
        end
        if itemLink then
            local matched = self:FindMatchingRollRecord(itemLink, {
                excludeBoundHistory = true,
                encId = encId,
                listId = listId,
            })
            if matched and not matched.isSimulated then
                if encId and not matched.encounterID then
                    matched.encounterID = encId
                end
                if listId and not matched.lootListID then
                    matched.lootListID = listId
                end
                return matched
            end
        end
        return nil
    end

    if hist.GetAllEncounterInfos and hist.GetSortedDropsForEncounter then
        local okEnc, encounters = pcall(hist.GetAllEncounterInfos)
        if okEnc and type(encounters) == "table" then
            local totalEnc = #encounters
            local startIdx = math.max(1, totalEnc - 3)
            for eIdx = totalEnc, startIdx, -1 do
                local enc = encounters[eIdx]
                local encId = enc and Safe.Number(enc.encounterID)
                if encId then
                    local okDrops, drops = pcall(hist.GetSortedDropsForEncounter, encId)
                    if okDrops and type(drops) == "table" then
                        for _, drop in ipairs(drops) do
                            if type(drop) == "table" then
                                local listId = Safe.Number(drop.lootListID)
                                local itemLink = Safe.String(drop.itemHyperlink)
                                local rInfos = drop.rollInfos
                                local dropAllPassed = (Safe.Value(drop.allPassed) == true)
                                local dropWinner = (type(drop.winner) == "table") and drop.winner or nil
                                if (not itemLink or type(rInfos) ~= "table" or #rInfos == 0) and listId and hist.GetSortedInfoForDrop then
                                    local okInfo, dropFull = pcall(hist.GetSortedInfoForDrop, encId, listId)
                                    if okInfo and type(dropFull) == "table" then
                                        if not itemLink then
                                            itemLink = Safe.String(dropFull.itemHyperlink)
                                        end
                                        rInfos = dropFull.rollInfos or dropFull
                                        if Safe.Value(dropFull.allPassed) == true then
                                            dropAllPassed = true
                                        end
                                        if not dropWinner and type(dropFull.winner) == "table" then
                                            dropWinner = dropFull.winner
                                        end
                                    end
                                end
                                local rec = FindRecForHistory(encId, listId, itemLink, nil)
                                if rec then
                                    if type(rInfos) == "table" then
                                        for _, rInfo in ipairs(rInfos) do
                                            if type(rInfo) == "table" then
                                                local mappedChoice = MapModernRollState(rInfo.state)
                                                local rRoll = Safe.Number(rInfo.roll)
                                                local isWin = (Safe.Value(rInfo.isWinner) == true)
                                                if mappedChoice or rRoll or isWin then
                                                    local pName = Safe.String(rInfo.playerName)
                                                    local pGuid = Safe.String(rInfo.playerGUID)
                                                    local pCls = Safe.String(rInfo.playerClass) or ResolveSafeUnitClassByGUID(pGuid, pName, nil)
                                                    local did = self:ApplyChoiceUpdate(rec, {
                                                        name = pName,
                                                        guid = pGuid,
                                                        classFile = pCls,
                                                        choice = mappedChoice,
                                                        roll = rRoll,
                                                        isWin = isWin,
                                                        isSelf = (Safe.Value(rInfo.isSelf) == true),
                                                    })
                                                    if did then
                                                        anyChanged = true
                                                        touchedRolls[rec.rollID] = true
                                                    end
                                                end
                                            end
                                        end
                                    end
                                    if type(dropWinner) == "table" then
                                        local w = dropWinner
                                        local wName = Safe.String(w.playerName)
                                        local wGuid = Safe.String(w.playerGUID)
                                        if wName and wName ~= "" then
                                            local didW = self:ApplyChoiceUpdate(rec, {
                                                name = wName,
                                                guid = wGuid,
                                                classFile = Safe.String(w.playerClass) or ResolveSafeUnitClassByGUID(wGuid, wName, nil),
                                                choice = MapModernRollState(w.state),
                                                roll = Safe.Number(w.roll),
                                                isWin = true,
                                                isSelf = (Safe.Value(w.isSelf) == true),
                                            })
                                            if didW then
                                                anyChanged = true
                                                touchedRolls[rec.rollID] = true
                                            end
                                        end
                                    elseif dropAllPassed and not rec.allPassed then
                                        rec.allPassed = true
                                        rec.resolved = true
                                        if not rec._resolvedCountdownSet then
                                            local nowMono = GetTime and GetTime() or 0
                                            rec._resolvedCountdownSet = true
                                            rec.hideAfterAt = math.max(nowMono + 7.5, rec.hideAfterAt or 0)
                                        end
                                        self:NotifyRollResolved(rec)
                                        anyChanged = true
                                        touchedRolls[rec.rollID] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if hist.GetNumItems and hist.GetItem then
        local okNum, rawCount = pcall(hist.GetNumItems)
        local nItems = okNum and Safe.Number(rawCount) or 0
        local maxScan = math.min(nItems, 30)
        for itemIdx = 1, maxScan do
            local okItem, lRollID, itemLink, numPlayers, isDone, winnerIdx = pcall(hist.GetItem, itemIdx)
            if okItem then
                local rIdNum = Safe.Number(lRollID)
                local cleanLink = Safe.String(itemLink)
                local rec = FindRecForHistory(nil, nil, cleanLink, rIdNum)
                if rec then
                    local pCount = math.min(Safe.Number(numPlayers) or 0, 40)
                    local typeMap = { [0] = "PASS", [1] = "NEED", [2] = "GREED", [3] = "DE" }
                    local sawWinner = false
                    if hist.GetPlayerInfo then
                        for pIdx = 1, pCount do
                            local okP, pName, pClass, rType, rRoll, isWinner, isMe = pcall(hist.GetPlayerInfo, itemIdx, pIdx)
                            if okP then
                                local cName = Safe.String(pName)
                                local cChoice = typeMap[Safe.Number(rType) or -1]
                                local cRoll = Safe.Number(rRoll)
                                local wonFlag = (Safe.Value(isWinner) == true)
                                if wonFlag then sawWinner = true end
                                if cName and (cChoice or cRoll or wonFlag) then
                                    local did = self:ApplyChoiceUpdate(rec, {
                                        name = cName,
                                        classFile = Safe.String(pClass),
                                        choice = cChoice,
                                        roll = cRoll,
                                        isWin = wonFlag,
                                        isSelf = (Safe.Value(isMe) == true),
                                    })
                                    if did then
                                        anyChanged = true
                                        touchedRolls[rec.rollID] = true
                                    end
                                end
                            end
                        end
                    end
                    local doneFlag = (Safe.Value(isDone) == true)
                    local winIdxNum = Safe.Number(winnerIdx)
                    if doneFlag and (not winIdxNum or winIdxNum <= 0) and not sawWinner and not rec.winnerName and not rec.allPassed then
                        rec.allPassed = true
                        rec.resolved = true
                        if not rec._resolvedCountdownSet then
                            local nowMono = GetTime and GetTime() or 0
                            rec._resolvedCountdownSet = true
                            rec.hideAfterAt = math.max(nowMono + 7.5, rec.hideAfterAt or 0)
                        end
                        self:NotifyRollResolved(rec)
                        anyChanged = true
                        touchedRolls[rec.rollID] = true
                    end
                end
            end
        end
    end

    if anyChanged then
        local firstId = next(touchedRolls)
        ns:Emit("LOOT_ROLL_UPDATED", firstId)
    end
    return anyChanged
end

function LootRoll:OnCancelLootRoll(rollID)
    local rId = Safe.Number(rollID)
    if not rId then return end
    local rec = self.activeRolls[rId]
    if rec then
        local nowMono = GetTime and GetTime() or 0
        if rec.pendingConfirm then
            -- Confirmed BoP/DE roll just went through on the server!
            local pendingType = rec.pendingConfirm.rollType
            rec.pendingConfirm = nil
            self:FinalizeLocalRollSelection(rec, pendingType)
            return
        end
        if rec.resolved then
            rec.hideAfterAt = math.max(rec.hideAfterAt or 0, nowMono + 8.0)
        elseif rec.myChoice then
            -- CANCEL_LOOT_ROLL also fires right after our own vote so Blizzard hides its own roll bar; keep tracking teammates.
            rec.maxWaitAt = math.max(rec.maxWaitAt or 0, nowMono + (rec.durationSec or 60) + 12.0)
        else
            -- Might be a vote made directly via Blizzard's bar before CHAT_MSG_LOOT arrives; give a generous window instead of closing immediately.
            rec._cancelledWithoutChoice = true
            rec.hideAfterAt = math.max(rec.hideAfterAt or 0, nowMono + 9.0)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.25, function() self:SyncLootHistory() end)
            C_Timer.After(1.1, function() self:SyncLootHistory() end)
            C_Timer.After(2.8, function() self:SyncLootHistory() end)
        end
        ns:Emit("LOOT_ROLL_UPDATED", rId)
    end
end

local function IsMasterLootActive()
    if _G.GetLootMethod then
        local ok, method = pcall(_G.GetLootMethod)
        if ok and Safe.String(method) == "master" then
            return true
        end
    end
    return false
end

function LootRoll:RecordMasterLootAward(itemLink, itemID, recipientName, recipientClass, quantity, bossNameHint)
    if not (itemLink and recipientName and recipientName ~= "") then return false end
    itemID = itemID or ExtractItemIdFromLink(itemLink)
    local iName, iQual, iTex
    if itemID then
        iName, iQual, iTex = ResolveSafeItemMeta(itemID)
    end
    iQual = iQual or 1
    if iQual < 3 then return false end -- Rare+ boss/Master Loot only
    iName = iName or itemLink:match("%[(.-)%]") or "?"
    local nowWall = time()
    local dispRecip = ResolveForeverDisplayName(NormalizePlayerToken(recipientName))
    local recipLk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(dispRecip)) or LowerUtf8Safe(dispRecip)
    -- Deduplicate if already recorded via ENCOUNTER_LOOT_RECEIVED or roll resolution within 8s
    for _, existing in pairs(self.recentRolls) do
        if existing and not existing.isSimulated and existing.itemID == itemID and (nowWall - (existing.createdAt or 0)) <= 8 then
            if existing.resolved or existing.isMasterLoot then
                return false
            end
        end
    end
    self._syntheticSeq = (self._syntheticSeq or 0) + 1
    local synId = -(600000 + self._syntheticSeq)
    local myFullName = (Compat and Compat.MyFullName and Compat.MyFullName()) or Safe.String(UnitName and UnitName("player")) or ""
    local _, myCls = UnitClass("player")
    local recZone = (Compat and Compat.CurrentZoneName and Compat.CurrentZoneName()) or ""
    local runMeta = self:ResolveCurrentGroupRunMeta(recZone)
    local isMe = (Compat and Compat.IsMe and Compat.IsMe(dispRecip)) == true
    local cls = recipientClass or LookupGroupMemberClass(dispRecip, recipLk)
    local rec = {
        rollID = synId,
        createdAt = nowWall,
        resolvedAt = nowWall,
        zone = recZone,
        bossName = bossNameHint or self:GetRecentBossName(),
        isMasterLoot = true,
        charName = myFullName,
        charClass = Safe.String(myCls),
        realmPool = (Compat and Compat.RealmPool and Compat.RealmPool()) or "",
        runKey = runMeta and runMeta.runKey or nil,
        instType = runMeta and runMeta.instType or nil,
        groupCount = runMeta and runMeta.groupCount or nil,
        rosterSig = runMeta and runMeta.rosterSig or nil,
        name = iName,
        quality = iQual,
        texture = iTex or "Interface\\Icons\\INV_Misc_QuestionMark",
        count = math.max(1, tonumber(quantity) or 1),
        link = itemLink,
        itemID = itemID,
        resolved = true,
        winnerName = dispRecip,
        winnerClass = cls,
        winnerChoice = "MASTER",
        winnerIsMe = isMe,
        myChoice = isMe and "MASTER" or nil,
        choices = {
            [recipLk] = {
                name = dispRecip,
                classFile = cls,
                choice = "MASTER",
                won = true,
                isMe = isMe,
                updatedAt = nowWall,
            },
        },
    }
    GenerateHistoryId(rec)
    self.recentRolls[synId] = rec
    self:PruneRecentRolls()
    self:NotifyRollResolved(rec)
    return true
end

function LootRoll:OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    local nameStr = Safe.String(encounterName)
    if nameStr and nameStr ~= "" then
        self._lastBossName = nameStr
        self._lastBossAt = time()
    end
end

function LootRoll:OnEncounterLootReceived(encounterID, itemID, itemLink, quantity, playerName, classFileName)
    if not self:IsEnabled() then return end
    if not (Compat and Compat.IsInGroup and Compat.IsInGroup()) then return end
    local cleanLink = Safe.String(itemLink)
    local cleanPlayer = Safe.String(playerName)
    if not cleanLink or not cleanPlayer or cleanPlayer == "" then return end
    local idNum = Safe.Number(itemID) or ExtractItemIdFromLink(cleanLink)
    -- Only record as Master Loot / direct boss award if there is no active Group Loot Roll for this item
    local matched = self:FindMatchingRollRecord(cleanLink, { playerName = cleanPlayer, isWin = true })
    if matched then return end
    self:RecordMasterLootAward(cleanLink, idNum, cleanPlayer, Safe.String(classFileName), Safe.Number(quantity) or 1, self:GetRecentBossName())
end

function LootRoll:OnChatMsgLoot(rawMsg, rawGuid)
    local inGroup = Compat and Compat.IsInGroup and Compat.IsInGroup()
    if not self:HasUnresolvedRecentRolls() and next(self.activeRolls) == nil then
        if not inGroup then return end
        if not (self:IsEnabled() or not self:HasAnsweredPrompt()) then
            return
        end
    end
    local msg = Safe.String(rawMsg)
    if not msg or msg == "" or not msg:find("|Hitem:", 1, true) then return end
    local senderGuid = Safe.String(rawGuid)
    local patterns = BuildLootPatterns(self)
    local matched = false
    for _, pat in ipairs(patterns) do
        local c1, c2, c3, c4, c5, c6 = msg:match(pat.pattern)
        if c1 then
            matched = true
            local caps = { c1, c2, c3, c4, c5, c6 }
            local parsed = {}
            for i, field in ipairs(pat.order) do
                parsed[field] = caps[i]
            end
            for i = 1, #caps do
                local v = caps[i]
                if type(v) == "string" then
                    if v:find("Hitem:", 1, true) then
                        parsed.link = v
                        if pat.order[i] == "player" then
                            parsed.player = nil
                        end
                    elseif v:match("^%d+$") and (pat.order[i] ~= "count") then
                        parsed.roll = v
                        if pat.order[i] == "player" then
                            parsed.player = nil
                        end
                    end
                end
            end
            local link = parsed.link or ExtractFirstItemLink(msg)
            local isSelf = (pat.mode == "PICK_SELF" or pat.mode == "ROLLED_SELF" or pat.mode == "WON_SELF" or pat.mode == "LOOT_SELF")
                or (parsed.player and IsSelfPronounToken(NormalizePlayerToken(parsed.player)))
            local isLootFallback = (pat.mode == "LOOT" or pat.mode == "LOOT_SELF")
            local isExplicitWin = (pat.mode == "WON" or pat.mode == "WON_SELF" or pat.mode == "ALL_PASSED")
            local rec = link and self:FindMatchingRollRecord(link, {
                playerName = parsed.player,
                guid = senderGuid,
                isWin = (pat.isWin == true or pat.choice == "WON"),
                isSelf = isSelf,
                isLootFallback = isLootFallback,
                mode = pat.mode,
                choice = pat.choice,
            }) or nil
            if (not rec) and link and isLootFallback and inGroup and IsMasterLootActive() then
                local recipName = isSelf and ((Compat and Compat.MyFullName and Compat.MyFullName()) or Safe.String(UnitName and UnitName("player"))) or parsed.player
                self:RecordMasterLootAward(link, ExtractItemIdFromLink(link), recipName, ResolveSafeUnitClassByGUID(senderGuid, recipName, nil), tonumber(parsed.count) or 1)
                return
            end
            if (not rec) and link and isExplicitWin and inGroup then
                local itemID = ExtractItemIdFromLink(link)
                local iName, iQual, iTex
                if itemID then
                    iName, iQual, iTex = ResolveSafeItemMeta(itemID)
                end
                if not iName then
                    iName = link:match("%[(.-)%]") or "?"
                end
                local nowWall = time()
                self._syntheticSeq = (self._syntheticSeq or 0) + 1
                local synId = -(500000 + self._syntheticSeq)
                local myFullName = (Compat and Compat.MyFullName and Compat.MyFullName()) or Safe.String(UnitName and UnitName("player")) or ""
                local _, myCls = UnitClass("player")
                local recZone = (Compat and Compat.CurrentZoneName and Compat.CurrentZoneName()) or ""
                local runMeta = self:ResolveCurrentGroupRunMeta(recZone)
                rec = {
                    rollID = synId,
                    createdAt = nowWall,
                    zone = recZone,
                    bossName = self:GetRecentBossName(),
                    charName = myFullName,
                    charClass = Safe.String(myCls),
                    realmPool = (Compat and Compat.RealmPool and Compat.RealmPool()) or "",
                    runKey = runMeta and runMeta.runKey or nil,
                    instType = runMeta and runMeta.instType or nil,
                    groupCount = runMeta and runMeta.groupCount or nil,
                    rosterSig = runMeta and runMeta.rosterSig or nil,
                    name = iName,
                    quality = iQual or 1,
                    texture = iTex or "Interface\\Icons\\INV_Misc_QuestionMark",
                    count = 1,
                    link = link,
                    itemID = itemID,
                    choices = {},
                }
                GenerateHistoryId(rec)
                self.recentRolls[synId] = rec
                self:PruneRecentRolls()
            end
            if rec then
                if pat.mode == "ALL_PASSED" then
                    rec.allPassed = true
                    rec.resolved = true
                    if not rec._resolvedCountdownSet then
                        local nowMono = GetTime and GetTime() or 0
                        rec._resolvedCountdownSet = true
                        rec.hideAfterAt = math.max(nowMono + 7.5, rec.hideAfterAt or 0)
                    end
                    self:NotifyRollResolved(rec)
                elseif isLootFallback and rec.resolved then
                    -- Never overwrite an already-resolved roll winner when an item is later traded or pushed.
                    return
                elseif isLootFallback and (time() - (rec.createdAt or 0)) > 120 then
                    return
                else
                    local did = self:ApplyChoiceUpdate(rec, {
                        name = parsed.player,
                        guid = senderGuid,
                        choice = pat.choice,
                        roll = parsed.roll,
                        isWin = pat.isWin == true or pat.choice == "WON",
                        isSelf = isSelf,
                        fromChat = true,
                    })
                    if did then
                        ns:Emit("LOOT_ROLL_UPDATED", rec.rollID)
                    end
                end
            end
            break
        end
    end

    if not matched and self:HasUnresolvedRecentRolls() then
        local link = ExtractFirstItemLink(msg)
        local rec = link and self:FindMatchingRollRecord(link, {}) or nil
        if rec then
            self:SyncLootHistory()
        end
    end
end

local function SaveChatRollSessionsToCharDB(self)
    if type(SocialCentralCharDB) ~= "table" then return end
    local saved = {}
    for _, sess in ipairs(self.chatRollSessions or {}) do
        if type(sess) == "table" and not sess.isSimulated then
            local rollsCopy = {}
            for _, r in ipairs(sess.rolls or {}) do
                rollsCopy[#rollsCopy + 1] = {
                    seq = r.seq,
                    name = r.name,
                    lookupKey = r.lookupKey,
                    classFile = r.classFile,
                    roll = r.roll,
                    minVal = r.minVal,
                    maxVal = r.maxVal,
                    bracket = r.bracket,
                    isStandard100 = r.isStandard100,
                    isDuplicate = r.isDuplicate,
                    isNotInvitedTie = r.isNotInvitedTie,
                    isMe = r.isMe,
                    ts = r.ts,
                }
            end
            saved[#saved + 1] = {
                id = sess.id,
                ts = sess.ts,
                lastRollAt = sess.lastRollAt,
                closed = sess.closed,
                isTieBreaker = sess.isTieBreaker,
                zone = sess.zone,
                runKey = sess.runKey,
                instType = sess.instType,
                itemLink = sess.itemLink,
                itemID = sess.itemID,
                itemName = sess.itemName,
                itemQuality = sess.itemQuality,
                itemTexture = sess.itemTexture,
                allowedPlayers = sess.allowedPlayers,
                rolls = rollsCopy,
            }
            if #saved >= self.maxChatRollSessions then break end
        end
    end
    SocialCentralCharDB.chatRollSessions = saved
end

local function LoadChatRollSessionsFromCharDB(self)
    if type(SocialCentralCharDB) ~= "table" or type(SocialCentralCharDB.chatRollSessions) ~= "table" then return end
    if #self.chatRollSessions > 0 then return end
    for _, raw in ipairs(SocialCentralCharDB.chatRollSessions) do
        if type(raw) == "table" and type(raw.rolls) == "table" then
            local seen = {}
            for _, r in ipairs(raw.rolls) do
                if type(r) == "table" and r.lookupKey then
                    seen[r.lookupKey] = true
                end
            end
            raw.seenPlayers = seen
            self:RecomputeChatRollSessionLeader(raw)
            self.chatRollSessions[#self.chatRollSessions + 1] = raw
            if #self.chatRollSessions >= self.maxChatRollSessions then break end
        end
    end
end

function LootRoll:RecomputeChatRollSessionLeader(sess)
    if not sess or type(sess.rolls) ~= "table" then return end
    local function BracketRank(r)
        if r.isDuplicate or r.isNotInvitedTie then return 0 end
        if r.bracket == "MS" or (r.bracket == nil and r.isStandard100 == true) then return 3 end
        if r.bracket == "OS" then return 2 end
        return 1
    end
    table.sort(sess.rolls, function(a, b)
        local ba, bb = BracketRank(a), BracketRank(b)
        if ba ~= bb then return ba > bb end
        local ra = tonumber(a.roll) or -1
        local rb = tonumber(b.roll) or -1
        if ra ~= rb then return ra > rb end
        return (a.seq or 0) < (b.seq or 0)
    end)

    sess.leaderName = nil
    sess.leaderClass = nil
    sess.leaderRoll = nil
    sess.isTied = false
    sess.tiedNames = nil
    sess.osLeaderName = nil
    sess.osLeaderClass = nil
    sess.osLeaderRoll = nil
    sess.osIsTied = false
    sess.anomalyCount = 0
    sess.dupCount = 0

    local msTop, osTop = nil, nil
    local msTied, osTiedCount = {}, 0
    for _, r in ipairs(sess.rolls) do
        if r.isDuplicate then
            sess.dupCount = sess.dupCount + 1
        end
        if r.bracket == "ANOMALY" or (not r.isStandard100 and r.bracket ~= "OS") or r.isNotInvitedTie then
            sess.anomalyCount = sess.anomalyCount + 1
        end
        local bRank = BracketRank(r)
        if bRank == 3 then
            if not msTop then
                msTop = r
                msTied[1] = r.name or "?"
            elseif r.roll == msTop.roll then
                msTied[#msTied + 1] = r.name or "?"
            end
        elseif bRank == 2 then
            if not osTop then
                osTop = r
                osTiedCount = 1
            elseif r.roll == osTop.roll then
                osTiedCount = osTiedCount + 1
            end
        end
    end

    if msTop then
        sess.leaderName = msTop.name
        sess.leaderClass = msTop.classFile
        sess.leaderRoll = msTop.roll
        sess.isTied = (#msTied > 1)
        if sess.isTied then
            sess.tiedNames = msTied
        end
    end
    if osTop then
        sess.osLeaderName = osTop.name
        sess.osLeaderClass = osTop.classFile
        sess.osLeaderRoll = osTop.roll
        sess.osIsTied = (osTiedCount > 1)
    end
end

function LootRoll:StartNewChatRollRound(itemLink, opts)
    opts = opts or {}
    local cur = self.chatRollSessions[1]
    if cur and not cur.closed then
        cur.closed = true
    end
    local nowWall = time()
    self._chatRollSeq = (self._chatRollSeq or 0) + 1
    local sZone = (Compat and Compat.CurrentZoneName and Compat.CurrentZoneName()) or ""
    local runMeta = self:ResolveCurrentGroupRunMeta(sZone)
    local linkedLink = itemLink
    local linkedId, linkedName, linkedQual, linkedTex = nil, nil, 1, nil
    if type(linkedLink) == "string" and linkedLink:find("Hitem:", 1, true) then
        linkedId = ExtractItemIdFromLink(linkedLink)
        if linkedId then
            linkedName, linkedQual, linkedTex = ResolveSafeItemMeta(linkedId)
        end
        linkedName = linkedName or linkedLink:match("%[(.-)%]") or "?"
    elseif self.lastGroupRollItem and (nowWall - (self.lastGroupRollItem.ts or 0)) <= 45 and not opts.noAutoItem then
        linkedLink = self.lastGroupRollItem.link
        linkedId = self.lastGroupRollItem.itemID
        linkedName = self.lastGroupRollItem.name
        linkedQual = self.lastGroupRollItem.quality or 1
        linkedTex = self.lastGroupRollItem.texture
    end
    local sess = {
        id = "chatroll_" .. tostring(nowWall) .. "_" .. tostring(self._chatRollSeq),
        ts = nowWall,
        lastRollAt = nowWall,
        zone = sZone,
        runKey = runMeta and runMeta.runKey or nil,
        instType = runMeta and runMeta.instType or nil,
        isTieBreaker = opts.isTieBreaker == true and true or nil,
        allowedPlayers = opts.allowedPlayers,
        itemLink = linkedLink,
        itemID = linkedId,
        itemName = linkedName,
        itemQuality = linkedQual or 1,
        itemTexture = linkedTex,
        rolls = {},
        seenPlayers = {},
    }
    table.insert(self.chatRollSessions, 1, sess)
    while #self.chatRollSessions > self.maxChatRollSessions do
        table.remove(self.chatRollSessions, #self.chatRollSessions)
    end
    SaveChatRollSessionsToCharDB(self)
    ns:Emit("LOOT_CHAT_ROLL_UPDATED", sess.id)
    return sess
end

function LootRoll:StartTieBreakerRound(sessionId)
    local src = nil
    for _, s in ipairs(self.chatRollSessions) do
        if s.id == sessionId then
            src = s
            break
        end
    end
    if not (src and src.isTied and type(src.tiedNames) == "table" and #src.tiedNames > 1) then
        return nil
    end
    local allowed = {}
    for _, nm in ipairs(src.tiedNames) do
        local lk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(nm)) or LowerUtf8Safe(nm)
        if lk and lk ~= "" then
            allowed[lk] = nm
        end
    end
    return self:StartNewChatRollRound(src.itemLink, {
        isTieBreaker = true,
        allowedPlayers = allowed,
        noAutoItem = true,
    })
end

function LootRoll:SetChatRollSessionItem(sessionId, itemLink)
    if type(itemLink) ~= "string" or not itemLink:find("Hitem:", 1, true) then return false end
    for _, s in ipairs(self.chatRollSessions) do
        if s.id == sessionId then
            local id = ExtractItemIdFromLink(itemLink)
            local nm, ql, tx
            if id then nm, ql, tx = ResolveSafeItemMeta(id) end
            s.itemLink = itemLink
            s.itemID = id
            s.itemName = nm or itemLink:match("%[(.-)%]") or "?"
            s.itemQuality = ql or 1
            s.itemTexture = tx
            SaveChatRollSessionsToCharDB(self)
            ns:Emit("LOOT_CHAT_ROLL_UPDATED", s.id)
            return true
        end
    end
    return false
end

function LootRoll:DeleteChatRollSession(sessionId)
    for i = #self.chatRollSessions, 1, -1 do
        if self.chatRollSessions[i].id == sessionId then
            table.remove(self.chatRollSessions, i)
            SaveChatRollSessionsToCharDB(self)
            ns:Emit("LOOT_CHAT_ROLL_UPDATED")
            return true
        end
    end
    return false
end

function LootRoll:GetLatestChatRollSessions()
    if #self.chatRollSessions == 0 then
        return {}
    end
    local anchor = self.chatRollSessions[1]
    local anchorRunKey = type(anchor.runKey) == "string" and anchor.runKey ~= "" and anchor.runKey or nil
    local anchorZone = tostring(anchor.zone or "")
    local anchorTs = tonumber(anchor.ts) or 0
    local anchorSim = (anchor.isSimulated == true)
    local out = {}
    local prevTs = anchorTs
    for _, sess in ipairs(self.chatRollSessions) do
        local candSim = (sess.isSimulated == true)
        local okMatch = false
        if candSim == anchorSim then
            local candRunKey = type(sess.runKey) == "string" and sess.runKey ~= "" and sess.runKey or nil
            if anchorRunKey and candRunKey then
                okMatch = (anchorRunKey == candRunKey)
            elseif not anchorRunKey and not candRunKey then
                local cZone = tostring(sess.zone or "")
                local cTs = tonumber(sess.ts) or 0
                local sameZone = (anchorZone == "" or cZone == "" or anchorZone == cZone)
                local gapOk = (prevTs == 0 or cTs == 0 or math.abs(prevTs - cTs) <= 2700)
                local spanOk = (anchorTs == 0 or cTs == 0 or math.abs(anchorTs - cTs) <= 14400)
                okMatch = sameZone and gapOk and spanOk
            end
        end
        if okMatch then
            out[#out + 1] = sess
            local cTs = tonumber(sess.ts) or 0
            if cTs > 0 then prevTs = cTs end
        elseif #out > 0 and not anchorRunKey then
            break
        end
    end
    return out
end

function LootRoll:GetChatRollSessions(query, scope)
    local basePool = (scope == "latest_run") and self:GetLatestChatRollSessions() or self.chatRollSessions
    local q = type(query) == "string" and LowerUtf8Safe(query):match("^%s*(.-)%s*$") or ""
    if q == "" then
        return basePool
    end
    local out = {}
    for _, sess in ipairs(basePool) do
        local hit = (type(sess.itemName) == "string" and LowerUtf8Safe(sess.itemName):find(q, 1, true))
            or (type(sess.leaderName) == "string" and LowerUtf8Safe(sess.leaderName):find(q, 1, true))
            or (type(sess.osLeaderName) == "string" and LowerUtf8Safe(sess.osLeaderName):find(q, 1, true))
        if not hit and type(sess.rolls) == "table" then
            for _, r in ipairs(sess.rolls) do
                if type(r.name) == "string" and LowerUtf8Safe(r.name):find(q, 1, true) then
                    hit = true
                    break
                end
            end
        end
        if hit then
            out[#out + 1] = sess
        end
    end
    return out
end

function LootRoll:ClearChatRollSessions()
    wipe(self.chatRollSessions)
    SaveChatRollSessionsToCharDB(self)
    ns:Emit("LOOT_CHAT_ROLL_UPDATED")
end

function LootRoll:OnGroupChatMessage(rawMsg, rawSender, chatEvent)
    local s = ns.db and ns.db.settings
    if s and s.lootRollTrackChatRolls == false then return end
    if Compat and Compat.IsInGroup and not Compat.IsInGroup() then return end
    local msg = Safe.String(rawMsg)
    if not msg or not msg:find("Hitem:", 1, true) then return end
    local link = ExtractFirstItemLink(msg)
    if not link then return end
    local isAuthoritative = (chatEvent == "CHAT_MSG_RAID_WARNING" or chatEvent == "CHAT_MSG_RAID_LEADER" or chatEvent == "CHAT_MSG_PARTY_LEADER")
    local senderDisp = ResolveForeverDisplayName(Safe.String(rawSender) or "")
    local cur = self.chatRollSessions[1]
    local nowWall = time()
    -- Do not let a casual member's item link hijack an actively rolling round!
    if (not isAuthoritative) and cur and not cur.closed and cur.rolls and #cur.rolls > 0 and (nowWall - (cur.lastRollAt or cur.ts or 0)) <= 18 then
        return
    end
    local itemID = ExtractItemIdFromLink(link)
    local iName, iQual, iTex = nil, nil, nil
    if itemID then
        iName, iQual, iTex = ResolveSafeItemMeta(itemID)
    end
    iName = iName or link:match("%[(.-)%]") or "?"
    self.lastGroupRollItem = {
        link = link,
        itemID = itemID,
        name = iName,
        quality = iQual or 1,
        texture = iTex,
        ts = nowWall,
        sender = senderDisp,
        authoritative = isAuthoritative,
    }
    -- If an empty active waiting round exists with no item bound yet, bind this linked item immediately!
    if cur and not cur.closed and not cur.itemLink and #(cur.rolls or {}) == 0 and (nowWall - (cur.ts or 0)) <= 60 then
        cur.itemLink = link
        cur.itemID = itemID
        cur.itemName = iName
        cur.itemQuality = iQual or 1
        cur.itemTexture = iTex
        SaveChatRollSessionsToCharDB(self)
        ns:Emit("LOOT_CHAT_ROLL_UPDATED", cur.id)
    end
end

function LootRoll:OnChatMsgSystem(rawMsg)
    local s = ns.db and ns.db.settings
    if s and s.lootRollTrackChatRolls == false then return end
    local msg = Safe.String(rawMsg)
    -- O(1) fast-path bailout: every localized RANDOM_ROLL_RESULT contains "(min-max)".
    if not msg or msg == "" or not msg:find("(", 1, true) or not msg:find(")", 1, true) then return end
    local pat, ord = BuildRandomRollPattern(self)
    if not pat then return end
    local c1, c2, c3, c4 = msg:match(pat)
    if not c1 then return end

    local caps = { c1, c2, c3, c4 }
    local parsed = {}
    for i, field in ipairs(ord) do
        parsed[field] = caps[i]
    end
    local rName = ResolveForeverDisplayName(NormalizePlayerToken(parsed.player or ""))
    local rVal = tonumber(parsed.roll)
    local rMin = tonumber(parsed.min) or 1
    local rMax = tonumber(parsed.max) or 100
    if not rName or rName == "" or not rVal then return end

    local inGroup = Compat and Compat.IsInGroup and Compat.IsInGroup()
    local isMe = Compat and Compat.IsMe and Compat.IsMe(rName)
    if isMe then
        local myFull = (Compat and Compat.MyFullName and Compat.MyFullName()) or rName
        if myFull and myFull ~= "" then
            rName = myFull
        end
    end
    if not inGroup and not isMe then
        return
    end

    local nowWall = time()
    local isRaid = Compat and Compat.IsInRaid and Compat.IsInRaid()
    local gapLimit = isRaid and 45 or 25
    local sess = self.chatRollSessions[1]
    local createNew = (not sess) or sess.closed or ((nowWall - (sess.lastRollAt or sess.ts or 0)) > gapLimit)
    if not createNew and self.lastGroupRollItem and (self.lastGroupRollItem.ts or 0) > (sess.ts or 0) and (nowWall - self.lastGroupRollItem.ts) <= 35 then
        if self.lastGroupRollItem.authoritative or #(sess.rolls or {}) == 0 then
            if not sess.itemLink or sess.itemLink ~= self.lastGroupRollItem.link then
                createNew = true
            end
        end
    end

    if createNew then
        local linked = (self.lastGroupRollItem and (nowWall - (self.lastGroupRollItem.ts or 0)) <= 35) and self.lastGroupRollItem or nil
        local sZone = (Compat and Compat.CurrentZoneName and Compat.CurrentZoneName()) or ""
        local runMeta = self:ResolveCurrentGroupRunMeta(sZone)
        self._chatRollSeq = (self._chatRollSeq or 0) + 1
        sess = {
            id = "chatroll_" .. tostring(nowWall) .. "_" .. tostring(self._chatRollSeq),
            ts = nowWall,
            lastRollAt = nowWall,
            zone = sZone,
            runKey = runMeta and runMeta.runKey or nil,
            instType = runMeta and runMeta.instType or nil,
            itemLink = linked and linked.link or nil,
            itemID = linked and linked.itemID or nil,
            itemName = linked and linked.name or nil,
            itemQuality = linked and linked.quality or 1,
            itemTexture = linked and linked.texture or nil,
            rolls = {},
            seenPlayers = {},
        }
        table.insert(self.chatRollSessions, 1, sess)
        while #self.chatRollSessions > self.maxChatRollSessions do
            table.remove(self.chatRollSessions, #self.chatRollSessions)
        end
    end

    sess.lastRollAt = nowWall
    local lk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(rName)) or LowerUtf8Safe(rName)
    local isDup = (sess.seenPlayers[lk] == true)
    sess.seenPlayers[lk] = true
    local isNotInvitedTie = (sess.isTieBreaker == true and type(sess.allowedPlayers) == "table" and sess.allowedPlayers[lk] == nil) and true or nil
    local bracket = "ANOMALY"
    if rMin == 1 and rMax == 100 then
        bracket = "MS"
    elseif rMin == 1 and (rMax == 50 or rMax == 99) then
        bracket = "OS"
    end
    local cls = LookupGroupMemberClass(rName, lk)
    sess.rolls[#sess.rolls + 1] = {
        seq = #sess.rolls + 1,
        name = rName,
        lookupKey = lk,
        classFile = cls,
        roll = rVal,
        minVal = rMin,
        maxVal = rMax,
        bracket = bracket,
        isStandard100 = (bracket == "MS"),
        isDuplicate = isDup,
        isNotInvitedTie = isNotInvitedTie,
        isMe = isMe == true,
        ts = nowWall,
    }
    self:RecomputeChatRollSessionLeader(sess)
    SaveChatRollSessionsToCharDB(self)
    ns:Emit("LOOT_CHAT_ROLL_UPDATED", sess.id)
end

local function SanitizeSavedLootHistory()
    local hist = SocialCentralDB and SocialCentralDB.lootRollHistory
    if type(hist) ~= "table" then return end
    for _, rec in ipairs(hist) do
        if type(rec) == "table" then
            -- Clean up any legacy leaked transient runtime flag from SavedVariables
            rec._isActive = nil
            if type(rec.choices) == "table" then
                local ownerName = (type(rec.charName) == "string" and rec.charName ~= "") and rec.charName or nil
                local selfIdx, pronounIdx = nil, nil
                for i, ch in ipairs(rec.choices) do
                    if type(ch) == "table" then
                        if ch.me == true or (ownerName and ch.n == ownerName) then
                            selfIdx = i
                        elseif IsSelfPronounToken(tostring(ch.n or "")) then
                            pronounIdx = i
                        end
                    end
                end
                if pronounIdx then
                    local pCh = rec.choices[pronounIdx]
                    if selfIdx and selfIdx ~= pronounIdx then
                        local sCh = rec.choices[selfIdx]
                        if pCh.ch == "NEED" and (sCh.ch == "PASS" or sCh.ch == "GREED") then
                            sCh.ch = pCh.ch
                            rec.myChoice = pCh.ch
                        end
                        sCh.me = true
                        if not sCh.r and pCh.r then sCh.r = pCh.r end
                        table.remove(rec.choices, pronounIdx)
                    elseif ownerName then
                        pCh.n = ownerName
                        pCh.me = true
                    end
                end
                -- Ensure at most one winner crown matching rec.winnerName
                if rec.winnerName and not rec.allPassed then
                    for _, ch in ipairs(rec.choices) do
                        if type(ch) == "table" then
                            ch.w = (ch.n == rec.winnerName)
                            if ch.w and ch.ch and ch.ch ~= "WON" then
                                rec.winnerChoice = ch.ch
                                if ch.r then rec.winnerRoll = ch.r end
                            end
                        end
                    end
                end
                table.sort(rec.choices, function(a, b)
                    if type(a) ~= "table" or type(b) ~= "table" then return type(a) == "table" end
                    local wa, wb = (a.w == true), (b.w == true)
                    if wa ~= wb then return wa end
                    local pa = LootRoll:GetChoicePriority(a.ch, wa)
                    local pb = LootRoll:GetChoicePriority(b.ch, wb)
                    if pa ~= pb then return pa > pb end
                    local ra, rb = tonumber(a.r) or -1, tonumber(b.r) or -1
                    if ra ~= rb then return ra > rb end
                    return tostring(a.n or "") < tostring(b.n or "")
                end)
            end
        end
    end
end

local LOOT_HISTORY_EVENTS = {
    "LOOT_HISTORY_UPDATE_DROP",
    "LOOT_HISTORY_UPDATE_ENCOUNTER",
    "LOOT_HISTORY_ONE_HUNDRED_ROLL",
    "LOOT_ROLLS_COMPLETE",
    "LOOT_HISTORY_ROLL_CHANGED",
    "LOOT_HISTORY_ROLL_COMPLETE",
    "LOOT_HISTORY_FULL_UPDATE",
    "LOOT_HISTORY_AUTO_SHOW",
}
local LOOT_GROUP_CHAT_EVENTS = {
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
}

function LootRoll:SyncEventRegistration()
    local s = ns.db and ns.db.settings
    local rollOn = (s ~= nil and s.lootRollHelperEnabled == true)
    local needsPrompt = (not s) or (s.lootRollPromptAnswered ~= true)
    local chatRollOn = (not s) or (s.lootRollTrackChatRolls ~= false)
    local activeLoot = rollOn or needsPrompt

    if activeLoot then
        if not self._lootCoreEventsOn then
            self._lootCoreEventsOn = true
            ns.RegisterEvent(self, "START_LOOT_ROLL", function(_, _, rollID, rollTime)
                self:OnStartLootRoll(rollID, rollTime)
            end)
            ns.RegisterEvent(self, "CANCEL_LOOT_ROLL", function(_, _, rollID)
                self:OnCancelLootRoll(rollID)
            end)
            ns.RegisterEvent(self, "CONFIRM_LOOT_ROLL", function(_, _, rollID, rollType, confirmReason)
                self:OnConfirmLootRoll(rollID, rollType, confirmReason)
            end)
            ns.RegisterEvent(self, "CONFIRM_DISENCHANT_ROLL", function(_, _, rollID, rollType)
                self:OnConfirmLootRoll(rollID, rollType, "DISENCHANT")
            end)
            ns.RegisterEvent(self, "GROUP_ROSTER_UPDATE", function()
                if Compat and Compat.IsInGroup and not Compat.IsInGroup() and next(self.activeRolls) ~= nil then
                    local kept = {}
                    local keptOrder = {}
                    for _, rId in ipairs(self.rollOrder) do
                        local r = self.activeRolls[rId]
                        if r and r.isSimulated then
                            kept[rId] = r
                            keptOrder[#keptOrder + 1] = rId
                        end
                    end
                    self.activeRolls = kept
                    self.rollOrder = keptOrder
                    ns:Emit("LOOT_ROLL_UPDATED")
                end
            end)
        end
    elseif self._lootCoreEventsOn then
        self._lootCoreEventsOn = false
        ns.UnregisterEvent(self, "START_LOOT_ROLL")
        ns.UnregisterEvent(self, "CANCEL_LOOT_ROLL")
        ns.UnregisterEvent(self, "CONFIRM_LOOT_ROLL")
        ns.UnregisterEvent(self, "CONFIRM_DISENCHANT_ROLL")
        ns.UnregisterEvent(self, "GROUP_ROSTER_UPDATE")
    end

    if rollOn then
        if not self._lootDetailEventsOn then
            self._lootDetailEventsOn = true
            for _, ev in ipairs(LOOT_HISTORY_EVENTS) do
                local evName = ev
                ns.RegisterEvent(self, evName, function()
                    self:SyncLootHistory()
                    if (evName == "LOOT_ROLLS_COMPLETE" or evName == "LOOT_HISTORY_ROLL_COMPLETE") and C_Timer and C_Timer.After then
                        C_Timer.After(0.25, function() self:SyncLootHistory() end)
                        C_Timer.After(1.0, function() self:SyncLootHistory() end)
                    end
                end)
            end
            ns.RegisterEvent(self, "LOOT_ITEM_ROLL_WON", function(_, _, itemLink, rollVal, rollType)
                local cleanLink = Safe.String(itemLink)
                local rec = cleanLink and self:FindMatchingRollRecord(cleanLink, { isWin = true, isSelf = true }) or nil
                if rec then
                    local typeMap = { [0] = "PASS", [1] = "NEED", [2] = "GREED", [3] = "DE" }
                    local did = self:ApplyChoiceUpdate(rec, {
                        choice = typeMap[Safe.Number(rollType) or -1] or rec.myChoice or "NEED",
                        roll = Safe.Number(rollVal),
                        isWin = true,
                        isSelf = true,
                    })
                    if did then
                        ns:Emit("LOOT_ROLL_UPDATED", rec.rollID)
                    end
                end
                self:SyncLootHistory()
            end)
            ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function(_, _, itemID, success)
                if Safe.Bool(success) ~= true or next(self.activeRolls) == nil then return end
                local idNum = Safe.Number(itemID)
                if not idNum then return end
                local touched = false
                for _, rec in pairs(self.activeRolls) do
                    if rec and rec.itemID == idNum then
                        if rec.isSimulated then
                            local iName, iQual, iTex = ResolveSafeItemMeta(idNum)
                            if iName and iName ~= "" then rec.name = iName end
                            if iQual then rec.quality = iQual end
                            if iTex then rec.texture = iTex end
                        end
                        if not rec._itemDataLoaded or rec.isSimulated then
                            rec._itemDataLoaded = true
                            rec.comparison = self:BuildComparison(rec.link, rec.itemID, rec.name, rec._compareSlotOverride)
                        end
                        touched = true
                    end
                end
                if touched then
                    ns:Emit("LOOT_ROLL_UPDATED")
                end
            end)
            ns.RegisterEvent(self, "CHAT_MSG_LOOT", function(_, _, msg, _, _, _, _, _, _, _, _, _, _, guid)
                self:OnChatMsgLoot(msg, guid)
            end)
            ns.RegisterEvent(self, "ENCOUNTER_END", function(_, _, encId, encName, diffId, grpSz, suc)
                self:OnEncounterEnd(encId, encName, diffId, grpSz, suc)
            end)
            ns.RegisterEvent(self, "ENCOUNTER_LOOT_RECEIVED", function(_, _, encId, itemId, itemLink, qty, pName, pClass)
                self:OnEncounterLootReceived(encId, itemId, itemLink, qty, pName, pClass)
            end)
        end
    elseif self._lootDetailEventsOn then
        self._lootDetailEventsOn = false
        for _, ev in ipairs(LOOT_HISTORY_EVENTS) do
            ns.UnregisterEvent(self, ev)
        end
        ns.UnregisterEvent(self, "LOOT_ITEM_ROLL_WON")
        ns.UnregisterEvent(self, "GET_ITEM_INFO_RECEIVED")
        ns.UnregisterEvent(self, "CHAT_MSG_LOOT")
        ns.UnregisterEvent(self, "ENCOUNTER_END")
        ns.UnregisterEvent(self, "ENCOUNTER_LOOT_RECEIVED")
    end

    if rollOn or chatRollOn then
        if not self._lootSysEventOn then
            self._lootSysEventOn = true
            ns.RegisterEvent(self, "CHAT_MSG_SYSTEM", function(_, _, msg)
                self:OnChatMsgSystem(msg)
            end)
        end
    elseif self._lootSysEventOn then
        self._lootSysEventOn = false
        ns.UnregisterEvent(self, "CHAT_MSG_SYSTEM")
    end

    if chatRollOn then
        if not self._lootChatRollEventsOn then
            self._lootChatRollEventsOn = true
            for _, chatEv in ipairs(LOOT_GROUP_CHAT_EVENTS) do
                local evName = chatEv
                ns.RegisterEvent(self, evName, function(_, _, msg, sender)
                    self:OnGroupChatMessage(msg, sender, evName)
                end)
            end
        end
    elseif self._lootChatRollEventsOn then
        self._lootChatRollEventsOn = false
        for _, chatEv in ipairs(LOOT_GROUP_CHAT_EVENTS) do
            ns.UnregisterEvent(self, chatEv)
        end
    end
end

function LootRoll:InstallStaticPopupCancelHook()
    if self._staticPopupHooked or not (hooksecurefunc and _G.StaticPopup_OnHide) then return end
    self._staticPopupHooked = true
    hooksecurefunc("StaticPopup_OnHide", function(dialog)
        if not dialog then return end
        local which = dialog.which
        if which ~= "CONFIRM_LOOT_ROLL" and which ~= "CONFIRM_DISENCHANT_ROLL" then return end
        local rId = Safe.Number(dialog.data)
        if not rId then return end
        -- Defer slightly so CANCEL_LOOT_ROLL arrives first if the user clicked Accept; if still pendingConfirm, they clicked Cancel/Esc!
        if C_Timer and C_Timer.After then
            C_Timer.After(0.12, function()
                local rec = LootRoll.activeRolls[rId]
                if rec and rec.pendingConfirm and not rec.myChoice and not rec.resolved then
                    rec.pendingConfirm = nil
                    ns:Emit("LOOT_ROLL_UPDATED", rId)
                end
            end)
        end
    end)
end

function LootRoll:Init()
    SanitizeSavedLootHistory()
    LoadChatRollSessionsFromCharDB(self)
    self:SyncEventRegistration()
    self:InstallStaticPopupCancelHook()
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        LootRoll:UpdateInstancePresence(false)
        LootRoll:RecoverActiveRolls()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.6, function()
                LootRoll:RecoverActiveRolls()
            end)
        end
    end)
    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", function()
        LootRoll:UpdateInstancePresence(false)
    end)
    ns.RegisterEvent(self, "PLAYER_LOGOUT", function()
        LootRoll:FlushPendingHistoryCommits()
        SaveChatRollSessionsToCharDB(LootRoll)
    end)
    ns:On("DUNGEON_HISTORY_UPDATED", function()
        local latest = SocialCentralDB and type(SocialCentralDB.dungeonHistory) == "table" and SocialCentralDB.dungeonHistory[1] or nil
        if latest and latest.er ~= "logout" and latest.en and (time() - tonumber(latest.en)) <= 25 then
            LootRoll:UpdateInstancePresence(true)
        end
    end)
    ns:On("SETTINGS_UPDATED", function()
        LootRoll:SyncEventRegistration()
        if LootRoll:IsEnabled() then
            LootRoll:RecoverActiveRolls()
        end
    end)
    self:UpdateInstancePresence(false)
    self:RecoverActiveRolls()
end

function LootRoll:ClearSimulatedRolls()
    local removed = false
    for i = #self.rollOrder, 1, -1 do
        local rId = self.rollOrder[i]
        local rec = self.activeRolls[rId]
        if rec and rec.isSimulated then
            self.activeRolls[rId] = nil
            self.recentRolls[rId] = nil
            table.remove(self.rollOrder, i)
            removed = true
        end
    end
    if #self.simHistory > 0 then
        wipe(self.simHistory)
        removed = true
    end
    for i = #self.chatRollSessions, 1, -1 do
        if self.chatRollSessions[i].isSimulated then
            table.remove(self.chatRollSessions, i)
            removed = true
        end
    end
    if removed then
        ns:Emit("LOOT_ROLL_UPDATED")
        ns:Emit("LOOT_CHAT_ROLL_UPDATED")
    end
    return removed
end

function LootRoll:RunPreviewSimulation(modeRaw)
    local mode = type(modeRaw) == "string" and modeRaw:lower():match("^%s*(%S*)") or ""
    if mode == "clear" or mode == "hide" or mode == "close" then
        self:ClearSimulatedRolls()
        return true
    end

    self:ClearSimulatedRolls()
    local nowMono = (GetTime and GetTime()) or 0
    local nowWall = time()
    local myFullName = (Compat and Compat.MyFullName and Compat.MyFullName()) or Safe.String(UnitName and UnitName("player")) or L["You"]
    local _, myCls = UnitClass("player")

    local simZone = (Compat and Compat.CurrentZoneName and Compat.CurrentZoneName()) or "Blackwing Lair"
    local simRunKey = "sim:" .. tostring(nowWall) .. ":" .. tostring(simZone)

    local function BuildSimRecord(rollId, itemId, fallbackName, canDE)
        if CItemReqLoadFn then pcall(CItemReqLoadFn, itemId) end
        local iName, iQual, iTex = ResolveSafeItemMeta(itemId)
        local iLink = "item:" .. tostring(itemId)
        local rec = {
            rollID = rollId,
            isSimulated = true,
            simExpiresAt = nowMono + 55,
            createdAt = nowWall,
            zone = simZone,
            runKey = simRunKey,
            instType = "raid",
            groupCount = 4,
            charName = myFullName,
            charClass = Safe.String(myCls),
            durationSec = 55,
            texture = iTex or "Interface\\Icons\\INV_Misc_QuestionMark",
            name = iName or fallbackName,
            count = 1,
            quality = iQual or 4,
            bindOnPickUp = true,
            canNeed = true,
            canGreed = true,
            canDisenchant = canDE == true,
            link = iLink,
            itemID = itemId,
            choices = {},
        }
        rec.comparison = self:BuildComparison(rec.link, rec.itemID, rec.name)
        GenerateHistoryId(rec)
        return rec
    end

    if mode == "winner" or mode == "banner" or mode == "win" then
        local w1 = BuildSimRecord(-9101, 19384, "Master Dragonslayer's Ring", true)
        w1.myChoice = "NEED"
        w1.myRoll = 94
        w1.resolved = true
        w1.winnerName = myFullName
        w1.winnerClass = Safe.String(myCls)
        w1.winnerChoice = "NEED"
        w1.winnerRoll = 94
        w1.winnerIsMe = true
        w1.choices = {
            ["__sim_me"] = { name = myFullName, classFile = Safe.String(myCls), choice = "NEED", roll = 94, won = true, isMe = true, updatedAt = nowWall },
            ["kaelen"] = { name = "Kaelen", classFile = "WARRIOR", choice = "NEED", roll = 78, updatedAt = nowWall },
            ["lyra"] = { name = "Lyra", classFile = "PRIEST", choice = "GREED", roll = 89, updatedAt = nowWall },
            ["thorn"] = { name = "Thorn", classFile = "HUNTER", choice = "PASS", updatedAt = nowWall },
        }
        self:NotifyRollResolved(w1)

        local w2 = BuildSimRecord(-9102, 19375, "Mish'undare, Circlet of the Mind Flayer", false)
        w2.myChoice = "GREED"
        w2.myRoll = 61
        w2.resolved = true
        w2.winnerName = "Lyra"
        w2.winnerClass = "PRIEST"
        w2.winnerChoice = "NEED"
        w2.winnerRoll = 87
        w2.winnerIsMe = false
        w2.choices = {
            ["lyra"] = { name = "Lyra", classFile = "PRIEST", choice = "NEED", roll = 87, won = true, updatedAt = nowWall },
            ["__sim_me"] = { name = myFullName, classFile = Safe.String(myCls), choice = "GREED", roll = 61, isMe = true, updatedAt = nowWall },
            ["thorn"] = { name = "Thorn", classFile = "HUNTER", choice = "DE", roll = 92, updatedAt = nowWall },
        }
        self:NotifyRollResolved(w2)
        ns:Print("%s", L["Simulated Loot Winner Banner triggered."])
        return true
    end

    local r1 = BuildSimRecord(-9001, 19384, "Master Dragonslayer's Ring", true)
    local r2 = BuildSimRecord(-9002, 19375, "Mish'undare, Circlet of the Mind Flayer", false)
    local r3 = BuildSimRecord(-9003, 13493, "Recipe: Greater Arcane Elixir", false)
    for _, rec in ipairs({ r1, r2, r3 }) do
        self.activeRolls[rec.rollID] = rec
        self.recentRolls[rec.rollID] = rec
        self.rollOrder[#self.rollOrder + 1] = rec.rollID
        self:CommitRecordToHistory(rec)
    end

    -- Also seed one sample Group /roll (1-100) session for instant preview inside the Results window
    local crSess = {
        id = "chatroll_sim_" .. tostring(nowWall),
        ts = nowWall,
        lastRollAt = nowWall,
        isSimulated = true,
        zone = simZone,
        runKey = simRunKey,
        itemLink = r1.link,
        itemID = r1.itemID,
        itemName = r1.name,
        itemQuality = r1.quality,
        itemTexture = r1.texture,
        rolls = {
            { seq = 1, name = "Kaelen", classFile = "WARRIOR", roll = 91, minVal = 1, maxVal = 100, isStandard100 = true, ts = nowWall },
            { seq = 2, name = myFullName, classFile = Safe.String(myCls), roll = 76, minVal = 1, maxVal = 100, isStandard100 = true, isMe = true, ts = nowWall },
            { seq = 3, name = "Lyra", classFile = "PRIEST", roll = 43, minVal = 1, maxVal = 100, isStandard100 = true, ts = nowWall },
        },
        seenPlayers = { kaelen = true, lyra = true },
    }
    self:RecomputeChatRollSessionLeader(crSess)
    table.insert(self.chatRollSessions, 1, crSess)
    ns:Emit("LOOT_CHAT_ROLL_UPDATED", crSess.id)

    if C_Timer and C_Timer.After then
        local function SimPick(targetRec, who, cls, choice)
            if not (targetRec and self.activeRolls[targetRec.rollID] == targetRec) then return end
            local rollVal = (choice ~= "PASS") and math.random(15, 96) or nil
            targetRec.choices[who:lower()] = {
                name = who,
                classFile = cls,
                choice = choice,
                roll = rollVal,
                updatedAt = time(),
            }
            self:CommitRecordToHistory(targetRec)
            ns:Emit("LOOT_ROLL_UPDATED", targetRec.rollID)
        end
        C_Timer.After(0.6, function() SimPick(r1, "Kaelen", "WARRIOR", "NEED") end)
        C_Timer.After(1.1, function() SimPick(r1, "Lyra", "PRIEST", "PASS") end)
        C_Timer.After(1.6, function() SimPick(r1, "Thorn", "HUNTER", "GREED") end)
        C_Timer.After(0.9, function() SimPick(r2, "Lyra", "PRIEST", "NEED") end)
        C_Timer.After(1.4, function() SimPick(r2, "Thorn", "HUNTER", "PASS") end)
        C_Timer.After(0.8, function() SimPick(r3, "Lyra", "PRIEST", "NEED") end)
        C_Timer.After(1.3, function() SimPick(r3, "Thorn", "HUNTER", "PASS") end)
        -- Automatically resolve item #3 after 2.4s so /sc roll demonstrates Top Winner Banner, Toast & Chat immediately.
        C_Timer.After(2.4, function()
            if not r3 or r3.expired or r3.resolved or r3.myChoice then return end
            local bestEntry, bestScore = nil, -1
            for _, ch in pairs(r3.choices or {}) do
                if type(ch) == "table" and ch.choice and ch.choice ~= "PASS" then
                    if not ch.roll then ch.roll = math.random(45, 96) end
                    local sc = (self:GetChoicePriority(ch.choice, false) * 100) + (tonumber(ch.roll) or 0)
                    if sc > bestScore then
                        bestScore = sc
                        bestEntry = ch
                    end
                end
            end
            if bestEntry then
                bestEntry.won = true
                r3.resolved = true
                r3.winnerName = bestEntry.name
                r3.winnerClass = bestEntry.classFile
                r3.winnerChoice = bestEntry.choice
                r3.winnerRoll = bestEntry.roll
                r3.hideAfterAt = (GetTime and GetTime() or 0) + 9.0
                self:NotifyRollResolved(r3)
            end
        end)
    end

    if mode == "prompt" or mode == "first" then
        if ns.db and ns.db.settings then
            ns.db.settings.lootRollPromptAnswered = false
        end
        if SocialCentralDB and SocialCentralDB.settings then
            SocialCentralDB.settings.lootRollPromptAnswered = false
        end
        ns:Emit("LOOT_ROLL_FIRST_PROMPT", r1)
    else
        ns:Emit("LOOT_ROLL_UPDATED", r1.rollID)
    end
    ns:Print("%s", L["Simulated Group Loot Roll started (visual test — no real items rolled)."])
    return true
end
