local ADDON_NAME, ns = ...
local L = ns.L
local Safe = ns.Safe
local Compat = ns.Compat

local LootRoll = {
    activeRolls = {},
    rollOrder = {},
    recentRolls = {},
    maxRecent = 24,
}
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

local EQUIP_LOC_SLOTS = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_BODY = { 4 },
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
    INVTYPE_RANGED = { 16, 18 },
    INVTYPE_RANGEDRIGHT = { 16, 18 },
    INVTYPE_THROWN = { 16, 18 },
    INVTYPE_RELIC = { 18 },
}

local STAT_ORDER = {
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
}

local function ExtractItemIdFromLink(itemLink)
    if type(itemLink) ~= "string" then return nil end
    local idStr = itemLink:match("Hitem:(%d+)")
    return idStr and tonumber(idStr) or nil
end

local function EscapeLuaPattern(text)
    return (text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function FormatGlobalToPattern(globalFmt, defaultOrder)
    if type(globalFmt) ~= "string" or globalFmt == "" then return nil, defaultOrder end
    local actualOrder = {}
    local seqIdx = 0
    local token = globalFmt:gsub("%%(%d*)%$?([sd])", function(posStr)
        seqIdx = seqIdx + 1
        local idx = tonumber(posStr) or seqIdx
        local fieldName = defaultOrder and defaultOrder[idx] or ("cap" .. tostring(#actualOrder + 1))
        actualOrder[#actualOrder + 1] = fieldName
        if fieldName == "roll" then
            return "\2"
        end
        return "\1"
    end)
    token = EscapeLuaPattern(token)
    token = token:gsub("\2", "(%%d+)")
    token = token:gsub("\1", "(.+)")
    return "^" .. token .. "$", actualOrder
end

local function BuildLootPatterns(self)
    if self._lootPatterns then return self._lootPatterns end
    local defs = {
        { key = "LOOT_ROLL_ROLLED_NEED", mode = "ROLLED", choice = "NEED", order = { "roll", "link", "player" } },
        { key = "LOOT_ROLL_ROLLED_GREED", mode = "ROLLED", choice = "GREED", order = { "roll", "link", "player" } },
        { key = "LOOT_ROLL_ROLLED_DISENCHANT", mode = "ROLLED", choice = "DE", order = { "roll", "link", "player" } },
        { key = "LOOT_ROLL_ROLLED_NEED_SELF", mode = "ROLLED_SELF", choice = "NEED", order = { "roll", "link" } },
        { key = "LOOT_ROLL_ROLLED_GREED_SELF", mode = "ROLLED_SELF", choice = "GREED", order = { "roll", "link" } },
        { key = "LOOT_ROLL_ROLLED_DISENCHANT_SELF", mode = "ROLLED_SELF", choice = "DE", order = { "roll", "link" } },
        { key = "LOOT_ROLL_NEED", mode = "PICK", choice = "NEED", order = { "player", "link" } },
        { key = "LOOT_ROLL_GREED", mode = "PICK", choice = "GREED", order = { "player", "link" } },
        { key = "LOOT_ROLL_DISENCHANT", mode = "PICK", choice = "DE", order = { "player", "link" } },
        { key = "LOOT_ROLL_PASSED", mode = "PICK", choice = "PASS", order = { "player", "link" } },
        { key = "LOOT_ROLL_PASSED_AUTO", mode = "PICK", choice = "PASS", order = { "player", "link" } },
        { key = "LOOT_ROLL_PASSED_AUTO_FEMALE", mode = "PICK", choice = "PASS", order = { "player", "link" } },
        { key = "LOOT_ROLL_NEED_SELF", mode = "PICK_SELF", choice = "NEED", order = { "link" } },
        { key = "LOOT_ROLL_GREED_SELF", mode = "PICK_SELF", choice = "GREED", order = { "link" } },
        { key = "LOOT_ROLL_DISENCHANT_SELF", mode = "PICK_SELF", choice = "DE", order = { "link" } },
        { key = "LOOT_ROLL_PASSED_SELF", mode = "PICK_SELF", choice = "PASS", order = { "link" } },
        { key = "LOOT_ROLL_WON", mode = "WON", choice = "WON", order = { "player", "link" } },
        { key = "LOOT_ROLL_YOU_WON", mode = "WON_SELF", choice = "WON", order = { "link" } },
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
                order = resolvedOrder,
            }
        end
    end
    self._lootPatterns = out
    return out
end

local function LookupGroupMemberClass(displayName, lk)
    if Compat and Compat.IsInGroup and not Compat.IsInGroup() then return nil end
    local num = (GetNumGroupMembers and Safe.Number(GetNumGroupMembers())) or 0
    local prefix = (Compat and Compat.IsInRaid and Compat.IsInRaid()) and "raid" or "party"
    local myName = UnitName and Safe.String(UnitName("player"))
    if myName and (Compat and Compat.IsMe and Compat.IsMe(displayName)) then
        local _, cls = UnitClass("player")
        return Safe.String(cls)
    end
    for i = 1, num do
        local unit = (prefix == "party" and i == num) and "player" or (prefix .. i)
        if UnitExists and UnitExists(unit) then
            local full = (Compat and Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName(unit)) or Safe.String(UnitName(unit))
            if full then
                local unitLk = Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(full)
                if (lk and unitLk == lk) or (displayName and full == displayName) then
                    local _, cls = UnitClass(unit)
                    return Safe.String(cls)
                end
            end
        end
    end
    return nil
end

local function FriendlyStatLabel(statKey)
    local globalLbl = _G[statKey]
    if type(globalLbl) == "string" and globalLbl ~= "" then
        return globalLbl
    end
    local stripped = tostring(statKey or ""):gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_", " ")
    return stripped
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

function LootRoll:IsEnabled()
    return (ns.db and ns.db.settings and ns.db.settings.lootRollHelperEnabled == true) and true or false
end

function LootRoll:HasAnsweredPrompt()
    return (ns.db and ns.db.settings and ns.db.settings.lootRollPromptAnswered == true) and true or false
end

function LootRoll:SetEnabledFromPrompt(enabled)
    if ns.db and ns.db.settings then
        ns.db.settings.lootRollPromptAnswered = true
        ns.db.settings.lootRollHelperEnabled = enabled and true or false
    end
    if SocialCentralDB and SocialCentralDB.settings then
        SocialCentralDB.settings.lootRollPromptAnswered = true
        SocialCentralDB.settings.lootRollHelperEnabled = enabled and true or false
    end
    ns:Emit("LOOT_ROLL_UPDATED")
end

function LootRoll:GetRollChoiceLabel(choice)
    if choice == "NEED" then return L["Need (Roll)"] end
    if choice == "GREED" then return L["Greed"] end
    if choice == "DE" then return L["Disenchant"] end
    if choice == "PASS" then return L["Pass"] end
    if choice == "WON" then return L["Won"] end
    return "?"
end

function LootRoll:GetChoiceColor(choice)
    return CHOICE_COLORS[choice] or "|cffd0d7de"
end

function LootRoll:BuildComparison(itemLink, itemID)
    local ref = itemLink or itemID
    if not ref then
        return { isEquippable = false, diffs = {} }
    end
    local _, _, _, equipLoc = nil, nil, nil, nil
    if CItemInstantFn then
        local okI, rId, _, _, rLoc = pcall(CItemInstantFn, ref)
        if okI then
            itemID = itemID or Safe.Number(rId)
            equipLoc = Safe.String(rLoc)
        end
    end
    local candIlvl = GetSafeDetailedIlvl(itemLink or itemID)
    local slotList = equipLoc and EQUIP_LOC_SLOTS[equipLoc] or nil
    if not slotList or #slotList == 0 then
        return {
            isEquippable = false,
            candidateILvl = candIlvl,
            equipLoc = equipLoc,
            diffs = {},
        }
    end

    local targetSlot = slotList[1]
    local equippedLink = nil
    local equippedIlvl = 0
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

    local candStats = GetSafeItemStats(itemLink) or {}
    local eqStats = (equippedLink and GetSafeItemStats(equippedLink)) or {}
    local seenKeys = {}
    for k in pairs(candStats) do seenKeys[k] = true end
    for k in pairs(eqStats) do seenKeys[k] = true end

    local diffs = {}
    for statKey in pairs(seenKeys) do
        local cVal = tonumber(candStats[statKey]) or 0
        local eVal = tonumber(eqStats[statKey]) or 0
        local delta = cVal - eVal
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

    return {
        isEquippable = true,
        slotId = targetSlot,
        equipLoc = equipLoc,
        equippedLink = equippedLink,
        equippedILvl = equippedIlvl,
        candidateILvl = candIlvl,
        ilvlDiff = (candIlvl > 0) and (candIlvl - equippedIlvl) or 0,
        isEmptySlot = (not equippedLink or equippedLink == ""),
        diffs = diffs,
    }
end

function LootRoll:GetRollByID(rollID)
    return self.activeRolls[rollID] or self.recentRolls[rollID]
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
            if remMs ~= nil and remMs <= 0 and not rec.myChoice then
                rec.expired = true
            end
            if not rec.expired and (not rec.hideAfterAt or nowMono < rec.hideAfterAt) then
                table.insert(out, 1, rec)
            else
                self.activeRolls[rId] = nil
                table.remove(self.rollOrder, i)
            end
        else
            table.remove(self.rollOrder, i)
        end
    end
    return out
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
        local map = { [0] = "PASS", [1] = "NEED", [2] = "GREED", [3] = "DE" }
        rec.myChoice = map[rollType] or "PASS"
        local me = (Compat and Compat.MyFullName and Compat.MyFullName()) or Safe.String(UnitName and UnitName("player")) or L["You"]
        local lk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(me)) or "__self__"
        local _, myCls = UnitClass("player")
        local myRoll = (rec.isSimulated and rec.myChoice ~= "PASS") and math.random(18, 99) or nil
        rec.choices[lk] = {
            name = me,
            classFile = Safe.String(myCls),
            choice = rec.myChoice,
            roll = myRoll,
            updatedAt = time(),
            isMe = true,
        }
        rec.hideAfterAt = (GetTime and GetTime() or 0) + (rec.isSimulated and 8.0 or 12.0)
        if rec.isSimulated and C_Timer and C_Timer.After then
            local simRec = rec
            C_Timer.After(1.3, function()
                if not simRec or simRec.expired then return end
                local bestEntry, bestScore = nil, -1
                local prio = { NEED = 300, GREED = 200, DE = 100, PASS = 0 }
                for _, ch in pairs(simRec.choices or {}) do
                    if type(ch) == "table" and ch.choice and ch.choice ~= "PASS" then
                        if not ch.roll then ch.roll = math.random(12, 97) end
                        local sc = (prio[ch.choice] or 0) + (tonumber(ch.roll) or 0)
                        if sc > bestScore then
                            bestScore = sc
                            bestEntry = ch
                        end
                    end
                end
                if bestEntry then
                    bestEntry.won = true
                    ns:Emit("LOOT_ROLL_UPDATED", simRec.rollID)
                end
            end)
        end
        ns:Emit("LOOT_ROLL_UPDATED")
    end
    return ok
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

function LootRoll:FindMatchingRollRecord(itemLink)
    local itemID = ExtractItemIdFromLink(itemLink)
    local best, bestAt = nil, -1
    for _, rec in pairs(self.activeRolls) do
        if rec and ((itemID and rec.itemID == itemID) or (itemLink and rec.link == itemLink)) then
            if (rec.createdAt or 0) > bestAt then
                best = rec
                bestAt = rec.createdAt or 0
            end
        end
    end
    if best then return best end
    for _, rec in pairs(self.recentRolls) do
        if rec and ((itemID and rec.itemID == itemID) or (itemLink and rec.link == itemLink)) then
            if (rec.createdAt or 0) > bestAt then
                best = rec
                bestAt = rec.createdAt or 0
            end
        end
    end
    return best
end

function LootRoll:OnStartLootRoll(rollID, rollTime)
    local rId = Safe.Number(rollID)
    if not rId or not GetLootRollItemInfo then return end
    local ok, tex, name, count, quality, bop, canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed, reasonDisenchant = pcall(GetLootRollItemInfo, rId)
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
    local rec = existing or {
        rollID = rId,
        createdAt = nowWall,
        choices = {},
    }
    rec.texture = Safe.Value(tex)
    rec.name = cleanName
    rec.count = math.max(1, Safe.Number(count) or 1)
    rec.quality = Safe.Number(quality) or 1
    rec.bindOnPickUp = (Safe.Value(bop) == true)
    rec.canNeed = (Safe.Value(canNeed) == true)
    rec.canGreed = (Safe.Value(canGreed) == true)
    rec.canDisenchant = (Safe.Value(canDisenchant) == true)
    rec.reasonNeed = Safe.String(reasonNeed)
    rec.reasonGreed = Safe.String(reasonGreed)
    rec.reasonDisenchant = Safe.String(reasonDisenchant)
    rec.link = link
    rec.itemID = itemID
    rec.durationSec = durSec
    rec.comparison = self:BuildComparison(link, itemID)

    if not existing then
        self.activeRolls[rId] = rec
        self.recentRolls[rId] = rec
        self.rollOrder[#self.rollOrder + 1] = rId
        self:PruneRecentRolls()
    end

    if not self:HasAnsweredPrompt() then
        ns:Emit("LOOT_ROLL_FIRST_PROMPT", rec)
    elseif self:IsEnabled() then
        ns:Emit("LOOT_ROLL_UPDATED", rId)
    end
end

function LootRoll:OnCancelLootRoll(rollID)
    local rId = Safe.Number(rollID)
    if not rId then return end
    local rec = self.activeRolls[rId]
    if rec then
        local nowMono = GetTime and GetTime() or 0
        if rec.myChoice then
            rec.hideAfterAt = math.max(rec.hideAfterAt or 0, nowMono + 10.0)
        else
            rec.hideAfterAt = nowMono + 1.5
        end
        if self:IsEnabled() then
            ns:Emit("LOOT_ROLL_UPDATED", rId)
        end
    end
end

function LootRoll:OnChatMsgLoot(rawMsg)
    if not (self:IsEnabled() or not self:HasAnsweredPrompt()) then
        if next(self.activeRolls) == nil then return end
    end
    local msg = Safe.String(rawMsg)
    if not msg or msg == "" then return end
    local patterns = BuildLootPatterns(self)
    for _, pat in ipairs(patterns) do
        local c1, c2, c3 = msg:match(pat.pattern)
        if c1 then
            local caps = { c1, c2, c3 }
            local parsed = {}
            for i, field in ipairs(pat.order) do
                parsed[field] = caps[i]
            end
            local link = parsed.link
            local rec = link and self:FindMatchingRollRecord(link) or nil
            if rec then
                local playerRaw = parsed.player
                if pat.mode == "PICK_SELF" or pat.mode == "ROLLED_SELF" or pat.mode == "WON_SELF" then
                    playerRaw = (Compat and Compat.MyFullName and Compat.MyFullName()) or Safe.String(UnitName and UnitName("player")) or L["You"]
                end
                local dispName = playerRaw or "?"
                local lk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(dispName)) or dispName:lower()
                local cls = LookupGroupMemberClass(dispName, lk)
                local prev = rec.choices[lk] or { name = dispName, classFile = cls }
                prev.name = dispName
                prev.classFile = prev.classFile or cls
                prev.updatedAt = time()
                if pat.choice == "WON" then
                    prev.won = true
                    if not prev.choice then prev.choice = "NEED" end
                    local nowMono = GetTime and GetTime() or 0
                    if rec.hideAfterAt then
                        rec.hideAfterAt = math.min(rec.hideAfterAt, nowMono + 5.0)
                    else
                        rec.hideAfterAt = nowMono + 5.0
                    end
                else
                    prev.choice = pat.choice
                end
                if parsed.roll and tonumber(parsed.roll) then
                    prev.roll = tonumber(parsed.roll)
                end
                rec.choices[lk] = prev
                if self:IsEnabled() then
                    ns:Emit("LOOT_ROLL_UPDATED", rec.rollID)
                end
            end
            break
        end
    end
end

function LootRoll:Init()
    ns.RegisterEvent(self, "START_LOOT_ROLL", function(_, _, rollID, rollTime)
        self:OnStartLootRoll(rollID, rollTime)
    end)
    ns.RegisterEvent(self, "CANCEL_LOOT_ROLL", function(_, _, rollID)
        self:OnCancelLootRoll(rollID)
    end)
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function(_, _, itemID, success)
        if not success or next(self.activeRolls) == nil then return end
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
                if rec.isSimulated or (not rec.comparison or #rec.comparison.diffs == 0) then
                    rec.comparison = self:BuildComparison(rec.link, rec.itemID)
                end
                touched = true
            end
        end
        if touched and self:IsEnabled() then
            ns:Emit("LOOT_ROLL_UPDATED")
        end
    end)
    ns.RegisterEvent(self, "CHAT_MSG_LOOT", function(_, _, msg)
        self:OnChatMsgLoot(msg)
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
            if self:IsEnabled() then
                ns:Emit("LOOT_ROLL_UPDATED")
            end
        end
    end)
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
    if removed then
        ns:Emit("LOOT_ROLL_UPDATED")
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

    local function BuildSimRecord(rollId, itemId, fallbackName, canDE)
        if CItemReqLoadFn then pcall(CItemReqLoadFn, itemId) end
        local iName, iQual, iTex = ResolveSafeItemMeta(itemId)
        local iLink = "item:" .. tostring(itemId)
        local rec = {
            rollID = rollId,
            isSimulated = true,
            simExpiresAt = nowMono + 55,
            createdAt = nowWall,
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
        rec.comparison = self:BuildComparison(rec.link, rec.itemID)
        return rec
    end

    local r1 = BuildSimRecord(-9001, 19384, "Master Dragonslayer's Ring", true)
    local r2 = BuildSimRecord(-9002, 19375, "Mish'undare, Circlet of the Mind Flayer", false)
    for _, rec in ipairs({ r1, r2 }) do
        self.activeRolls[rec.rollID] = rec
        self.recentRolls[rec.rollID] = rec
        self.rollOrder[#self.rollOrder + 1] = rec.rollID
    end

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
            if self:IsEnabled() then
                ns:Emit("LOOT_ROLL_UPDATED", targetRec.rollID)
            end
        end
        C_Timer.After(0.7, function() SimPick(r1, "Kaelen", "WARRIOR", "NEED") end)
        C_Timer.After(1.5, function() SimPick(r1, "Lyra", "PRIEST", "PASS") end)
        C_Timer.After(2.3, function() SimPick(r1, "Thorn", "HUNTER", "GREED") end)
        C_Timer.After(1.1, function() SimPick(r2, "Lyra", "PRIEST", "NEED") end)
        C_Timer.After(2.0, function() SimPick(r2, "Thorn", "HUNTER", "PASS") end)
    end

    if mode == "prompt" or mode == "first" then
        if ns.db and ns.db.settings then
            ns.db.settings.lootRollPromptAnswered = false
        end
        if SocialCentralDB and SocialCentralDB.settings then
            SocialCentralDB.settings.lootRollPromptAnswered = false
        end
        ns:Emit("LOOT_ROLL_FIRST_PROMPT", r1)
    elseif not self:HasAnsweredPrompt() then
        ns:Emit("LOOT_ROLL_FIRST_PROMPT", r1)
    else
        if not self:IsEnabled() then
            self:SetEnabledFromPrompt(true)
        end
        ns:Emit("LOOT_ROLL_UPDATED", r1.rollID)
    end
    ns:Print("%s", L["Simulated Group Loot Roll started (visual test — no real items rolled)."])
    return true
end
