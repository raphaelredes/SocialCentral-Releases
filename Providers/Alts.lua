local _, ns = ...

local Safe = ns.Safe
local Compat = ns.Compat
local L = ns.L

-- Records snapshots of the player's own characters across logins (WoW: Forever FirstName + Surname aware).
local Alts = {}
ns.Alts = Alts
table.insert(ns.modules, Alts)

local function ApplyAuthorSurname(author, guid)
    if not (ns.db and ns.db.alts) then return end
    local myGuid = Safe.String(Safe.Call(UnitGUID, "player"))
    local cleanGuid = Safe.String(guid)
    local cleanAuthor = Safe.String(author)
    if not (myGuid and cleanGuid and cleanGuid == myGuid and cleanAuthor) then return end

    local key = Compat.CharacterKey()
    local rec = ns.db.alts[key]
    if not rec then
        Alts:Snapshot()
        rec = ns.db.alts[key]
    end
    if not rec or rec.userSetSurname then return end

    local parsed = Compat.ParseForeverFullName(cleanAuthor)
    if parsed and parsed.surname and parsed.firstName:lower() == (rec.firstName or rec.name or ""):lower() then
        if rec.surname ~= parsed.surname or rec.fullName ~= parsed.fullName then
            rec.firstName = parsed.firstName
            rec.surname = parsed.surname
            rec.fullName = parsed.fullName
            if Compat.CacheForeverFullName then
                Compat.CacheForeverFullName(myGuid, rec.fullName, rec.firstName)
            end
            ns:Emit("ALTS_UPDATED")
        end
    end
end

local EQUIP_SLOT_COUNT = 19
local BAG_IDS = { 0, 1, 2, 3, 4 }
local BANK_BAG_IDS = { -1, 5, 6, 7, 8, 9, 10, 11 }
local MAX_CONTAINER_ITEMS = 220

local SECONDARY_PROF_PATTERNS = {
    "first aid", "primeiros socorros", "primeros auxilios",
    "cooking", "culinaria", "culinária", "cocina",
    "fishing", "pescaria", "pesca",
    "archaeology", "arqueologia", "arqueología",
}

local function IsSecondarySkillName(skillName)
    if type(skillName) ~= "string" then return false end
    local low = skillName:lower()
    for _, pat in ipairs(SECONDARY_PROF_PATTERNS) do
        if low:find(pat, 1, true) then
            return true
        end
    end
    return false
end

local function SnapshotProfessions(prevProfs)
    local out = {}
    local seen = {}
    if GetProfessions and GetProfessionInfo then
        local okP, p1, p2, p3, p4, p5, p6 = pcall(GetProfessions)
        if okP then
            local slots = {
                Safe.Value(p1),
                Safe.Value(p2),
                Safe.Value(p3),
                Safe.Value(p4),
                Safe.Value(p5),
                Safe.Value(p6),
            }
            for idx = 1, 6 do
                local pId = slots[idx]
                if pId then
                    local ok, name, icon, rank, maxRank = pcall(GetProfessionInfo, pId)
                    name = ok and Safe.String(name) or nil
                    if name and name ~= "" and not seen[name:lower()] then
                        seen[name:lower()] = true
                        out[#out + 1] = {
                            name = name,
                            rank = Safe.Number(rank) or 0,
                            maxRank = Safe.Number(maxRank) or 0,
                            icon = Safe.Value(icon),
                            isPrimary = (idx <= 2),
                        }
                    end
                end
            end
        end
    end

    if GetNumSkillLines and GetSkillLineInfo then
        local count = Safe.Number(Safe.Call(GetNumSkillLines)) or 0
        local currentHeader = ""
        for i = 1, count do
            local ok, sName, isHeader, _, sRank, _, _, sMaxRank, isAbandonable = pcall(GetSkillLineInfo, i)
            if ok then
                sName = Safe.String(sName)
                if Safe.Value(isHeader) then
                    currentHeader = sName and sName:lower() or ""
                elseif sName and sName ~= "" and not seen[sName:lower()] then
                    local inProfHeader = currentHeader:find("profiss", 1, true)
                        or currentHeader:find("profession", 1, true)
                        or currentHeader:find("profesion", 1, true)
                    local abandonable = (Safe.Value(isAbandonable) == true) or (Safe.Number(isAbandonable) == 1)
                    local secondary = IsSecondarySkillName(sName)
                    if inProfHeader or abandonable or secondary then
                        seen[sName:lower()] = true
                        out[#out + 1] = {
                            name = sName,
                            rank = Safe.Number(sRank) or 0,
                            maxRank = Safe.Number(sMaxRank) or 0,
                            isPrimary = (abandonable or (inProfHeader and not secondary)) and true or false,
                        }
                    end
                end
            end
        end
    end

    if #out == 0 and type(prevProfs) == "table" and #prevProfs > 0 then
        return prevProfs
    end
    return out
end

local function ResolveItemVisuals(itemRef, icon, quality, link)
    if itemRef and C_Item then
        if not icon and C_Item.GetItemIconByID then
            local ok, fileID = pcall(C_Item.GetItemIconByID, itemRef)
            if ok and Safe.Value(fileID) then
                icon = Safe.Value(fileID)
            end
        end
        if not quality and C_Item.GetItemQualityByID then
            local ok, itemQual = pcall(C_Item.GetItemQualityByID, itemRef)
            if ok and Safe.Number(itemQual) then
                quality = Safe.Number(itemQual)
            end
        end
    end
    return icon, quality or 1, link
end

local function SnapshotEquipment()
    local equip = {}
    for slotId = 1, EQUIP_SLOT_COUNT do
        local itemID = Safe.Number(Safe.Call(GetInventoryItemID, "player", slotId))
        local link = Safe.String(Safe.Call(GetInventoryItemLink, "player", slotId))
        local icon = Safe.Value(Safe.Call(GetInventoryItemTexture, "player", slotId))
        local quality = Safe.Number(Safe.Call(GetInventoryItemQuality, "player", slotId))
        if itemID or link then
            icon, quality, link = ResolveItemVisuals(link or itemID, icon, quality, link)
            equip[slotId] = {
                itemID = itemID,
                link = link,
                icon = icon,
                quality = quality or 1,
            }
        end
    end
    return equip
end

local function SnapshotContainerRange(bagList)
    local items = {}
    local freeSlots = 0
    local totalSlots = 0

    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
    local getItemInfo = C_Container and C_Container.GetContainerItemInfo
    local legacyGetItemInfo = _G.GetContainerItemInfo
    local getLegacyLink = _G.GetContainerItemLink

    if not getNumSlots then
        return items, freeSlots, totalSlots
    end

    for _, bagId in ipairs(bagList) do
        local okNum, numSlots = pcall(getNumSlots, bagId)
        numSlots = okNum and Safe.Number(numSlots) or 0
        if numSlots and numSlots > 0 then
            totalSlots = totalSlots + numSlots
            for slotId = 1, numSlots do
                local icon, count, quality, link, itemID
                if getItemInfo then
                    local okInfo, info, r2, _, r4, _, _, r7, _, _, r10 = pcall(getItemInfo, bagId, slotId)
                    if okInfo and type(info) == "table" then
                        icon = Safe.Value(info.iconFileID)
                        count = Safe.Number(info.stackCount) or 1
                        quality = Safe.Number(info.quality)
                        link = Safe.String(info.hyperlink)
                        itemID = Safe.Number(info.itemID)
                    elseif okInfo and info ~= nil and type(info) ~= "table" then
                        icon = Safe.Value(info)
                        count = Safe.Number(r2) or 1
                        quality = Safe.Number(r4)
                        link = Safe.String(r7)
                        itemID = Safe.Number(r10)
                    end
                end
                if not icon and not link and not itemID and legacyGetItemInfo then
                    local okLegacy, lTex, lCnt, _, lQual, _, _, lLink, _, _, lId = pcall(legacyGetItemInfo, bagId, slotId)
                    if okLegacy and (lTex or lLink or lId) then
                        icon = Safe.Value(lTex)
                        count = Safe.Number(lCnt) or 1
                        quality = Safe.Number(lQual)
                        link = Safe.String(lLink)
                        itemID = Safe.Number(lId)
                    end
                end
                if not link and getLegacyLink then
                    link = Safe.String(Safe.Call(getLegacyLink, bagId, slotId))
                end

                if icon or link or itemID then
                    icon, quality, link = ResolveItemVisuals(link or itemID, icon, quality, link)
                    if #items < MAX_CONTAINER_ITEMS then
                        items[#items + 1] = {
                            bag = bagId,
                            slot = slotId,
                            itemID = itemID,
                            link = link,
                            icon = icon,
                            count = (count and count > 1) and count or 1,
                            quality = quality or 1,
                        }
                    end
                else
                    freeSlots = freeSlots + 1
                end
            end
        end
    end

    return items, freeSlots, totalSlots
end

function Alts:GetArmoryURL(altEntry)
    if not altEntry then return nil end
    local full = altEntry.fullName or altEntry.name or ""
    full = full:gsub("^%s+", ""):gsub("%s+$", "")
    if full == "" then return nil end
    local slug = full:gsub("%s+", "-")
    return "https://armorywowforever.com/c/forever/us/pvp/" .. slug
end

function Alts:Snapshot(includeBank)
    if not (ns.db and ns.db.alts) then return end
    local name = Safe.String(Safe.Call(UnitName, "player"))
    if not name then return end

    local key = Compat.CharacterKey()
    local prev = ns.db.alts[key]
    local prevFull = (type(prev) == "table") and prev.fullName or nil
    local userSet = (type(prev) == "table") and (prev.userSetSurname == true) or false

    local resolved
    if userSet and type(prev) == "table" and prev.surname and prev.surname ~= "" then
        local baseParsed = Compat.ParseForeverFullName(name)
        local first = (baseParsed and baseParsed.firstName) or name
        resolved = {
            firstName = first,
            surname = prev.surname,
            fullName = first .. " " .. prev.surname,
        }
    else
        resolved = Compat.ResolvePlayerFullName(prevFull) or Compat.ParseForeverFullName(name)
    end

    local className, classFile = Safe.Call(UnitClass, "player")
    local raceName, raceFile = Safe.Call(UnitRace, "player")
    local sex = Safe.Number(Safe.Call(UnitSex, "player"))
    local myGuid = Safe.String(Safe.Call(UnitGUID, "player"))
    local bindLocation = Safe.String(Safe.Call(GetBindLocation))
    if (not bindLocation or bindLocation == "") and type(prev) == "table" then
        bindLocation = prev.bindLocation
    end
    local professions = SnapshotProfessions(type(prev) == "table" and prev.professions or nil)
    local level = Safe.Number(Safe.Call(UnitLevel, "player")) or (type(prev) == "table" and prev.level) or 1
    local xp = Safe.Number(Safe.Call(UnitXP, "player")) or 0
    local xpMax = Safe.Number(Safe.Call(UnitXPMax, "player")) or 0
    if xpMax <= 1 and type(prev) == "table" and (prev.xpMax or 0) > 1 then
        xp = prev.xp or xp
        xpMax = prev.xpMax
    elseif xpMax <= 0 then
        xpMax = 1
    end
    local rested = Safe.Number(Safe.Call(GetXPExhaustion)) or 0
    local money = Safe.Number(Safe.Call(GetMoney)) or 0
    if money == 0 and type(prev) == "table" and (prev.money or 0) > 0 then
        money = prev.money
    end
    local guild = Safe.String(Safe.Call(GetGuildInfo, "player"))
    if (not guild or guild == "") and ns.Store and ns.Store.guildInfo and ns.Store.guildInfo.name then
        guild = ns.Store.guildInfo.name
    end
    if (not guild or guild == "") and type(prev) == "table" and prev.guild and prev.guild ~= "" and Safe.Value(IsInGuild and IsInGuild()) == true then
        guild = prev.guild
    end
    guild = guild or ""
    local faction = Compat.PlayerFaction()

    local avgTotal, avgEquipped
    if GetAverageItemLevel then
        local ok, tot, eq = pcall(GetAverageItemLevel)
        if ok then
            avgTotal = Safe.Number(tot)
            avgEquipped = Safe.Number(eq)
        end
    end
    local itemLevel = (avgEquipped and avgEquipped > 0 and math.floor(avgEquipped))
        or (avgTotal and avgTotal > 0 and math.floor(avgTotal))
        or (prev and prev.itemLevel)
        or nil

    local equipment = SnapshotEquipment()
    local bags, bagFree, bagTotal = SnapshotContainerRange(BAG_IDS)
    local bank = type(prev) == "table" and prev.bank or nil
    local bankFree = type(prev) == "table" and prev.bankFree or 0
    local bankTotal = type(prev) == "table" and prev.bankTotal or 0
    local bankUpdatedAt = type(prev) == "table" and prev.bankUpdatedAt or nil
    if includeBank then
        local bItems, bFree, bTot = SnapshotContainerRange(BANK_BAG_IDS)
        if bTot > 0 then
            bank = bItems
            bankFree = bFree
            bankTotal = bTot
            bankUpdatedAt = time()
        end
    end

    ns.db.alts[key] = {
        name = name,
        firstName = resolved and resolved.firstName or name,
        surname = resolved and resolved.surname or nil,
        fullName = resolved and resolved.fullName or name,
        userSetSurname = userSet and (resolved and resolved.surname ~= nil) or false,
        realmPool = Compat.RealmPool(Compat.Realm()),
        faction = faction,
        className = Safe.String(className) or (type(prev) == "table" and prev.className or nil),
        classFile = Safe.String(classFile),
        raceName = Safe.String(raceName),
        raceFile = Safe.String(raceFile),
        sex = sex,
        guid = myGuid or (type(prev) == "table" and prev.guid or nil),
        level = level,
        itemLevel = itemLevel,
        xp = xp,
        xpMax = xpMax,
        rested = rested,
        money = money,
        zone = Compat.CurrentZoneName(),
        bindLocation = bindLocation or "",
        professions = professions,
        guild = guild,
        equipment = equipment,
        bags = bags,
        bagFree = bagFree,
        bagTotal = bagTotal,
        bank = bank,
        bankFree = bankFree,
        bankTotal = bankTotal,
        bankUpdatedAt = bankUpdatedAt,
        lastActive = time(),
    }

    if resolved and resolved.surname and resolved.fullName and Compat.CacheForeverFullName then
        Compat.CacheForeverFullName(myGuid, resolved.fullName, resolved.firstName)
    end

    self.itemIndex = nil
    ns:Emit("ALTS_UPDATED")
end

--- Lightweight O(1) update for currency, XP, level, and zone without scanning containers or skills.
function Alts:UpdateScalars()
    if not (ns.db and ns.db.alts) then return end
    local key = Compat.CharacterKey()
    local rec = ns.db.alts[key]
    if type(rec) ~= "table" then
        self:QueueSnapshot(false, 0.5)
        return
    end

    local level = Safe.Number(Safe.Call(UnitLevel, "player"))
    if level and level > 0 then rec.level = level end
    local xp = Safe.Number(Safe.Call(UnitXP, "player"))
    local xpMax = Safe.Number(Safe.Call(UnitXPMax, "player"))
    if xp then rec.xp = xp end
    if xpMax and xpMax > 0 then rec.xpMax = xpMax end
    local rested = Safe.Number(Safe.Call(GetXPExhaustion))
    if rested ~= nil then rec.rested = rested end
    local money = Safe.Number(Safe.Call(GetMoney))
    if money and money > 0 then rec.money = money end
    rec.zone = Compat.CurrentZoneName()
    rec.lastActive = time()

    if ns.UI and ns.UI.IsAltsVisible and ns.UI:IsAltsVisible() then
        ns:Emit("ALTS_UPDATED")
    end
end

--- Debounced full alt snapshot so rapid bag/equipment/skill events coalesce cleanly.
function Alts:QueueSnapshot(includeBank, delay)
    if includeBank then
        self._pendingIncludeBank = true
    end
    if self._snapshotQueued then return end
    self._snapshotQueued = true
    local waitSec = tonumber(delay) or 1.5
    if C_Timer and C_Timer.After then
        C_Timer.After(waitSec, function()
            Alts._snapshotQueued = false
            local doBank = Alts._pendingIncludeBank == true
            Alts._pendingIncludeBank = false
            Alts:Snapshot(doBank)
        end)
    else
        self._snapshotQueued = false
        local doBank = self._pendingIncludeBank == true
        self._pendingIncludeBank = false
        self:Snapshot(doBank)
    end
end

local function ExtractItemID(item)
    if type(item) ~= "table" then return nil end
    local id = tonumber(item.itemID)
    if id and id > 0 then return id end
    if type(item.link) == "string" then
        id = tonumber(item.link:match("item:(%d+)"))
        if id and id > 0 then return id end
    end
    return nil
end

function Alts:RebuildItemIndex()
    local index = {}
    local alts = Store and Store.GetAltsList and Store:GetAltsList() or {}
    for _, alt in ipairs(alts) do
        local displayName = alt.fullName or alt.name or alt.key or "?"
        local classFile = alt.classFile
        local perItem = {}

        local function AddBucket(list, field)
            if type(list) ~= "table" then return end
            for _, item in pairs(list) do
                local itemID = ExtractItemID(item)
                if itemID then
                    local rec = perItem[itemID]
                    if not rec then
                        rec = {
                            altKey = alt.key,
                            displayName = displayName,
                            classFile = classFile,
                            equipped = 0,
                            bags = 0,
                            bank = 0,
                            total = 0,
                        }
                        perItem[itemID] = rec
                    end
                    local qty = math.max(1, tonumber(item.count) or 1)
                    rec[field] = rec[field] + qty
                    rec.total = rec.total + qty
                end
            end
        end

        AddBucket(alt.equipment, "equipped")
        AddBucket(alt.bags, "bags")
        AddBucket(alt.bank, "bank")

        for itemID, rec in pairs(perItem) do
            index[itemID] = index[itemID] or {}
            table.insert(index[itemID], rec)
        end
    end

    local curKey = Compat.CharacterKey()
    for _, owners in pairs(index) do
        table.sort(owners, function(a, b)
            local aCur = (a.altKey == curKey)
            local bCur = (b.altKey == curKey)
            if aCur ~= bCur then return aCur end
            if a.total ~= b.total then return a.total > b.total end
            return (a.displayName or "") < (b.displayName or "")
        end)
    end

    self.itemIndex = index
    return index
end

function Alts:GetItemOwners(itemID)
    local numId = tonumber(itemID)
    if not numId or numId <= 0 then return nil end
    if not self.itemIndex then
        self:RebuildItemIndex()
    end
    return self.itemIndex and self.itemIndex[numId]
end

local itemTooltipRegistered = false

local function AppendAltItemTooltip(tooltip, data)
    if not tooltip or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if ns.db and ns.db.settings and ns.db.settings.tooltipItemAlts == false then return end

    local itemID = (type(data) == "table" and tonumber(data.id)) or nil
    if (not itemID or itemID <= 0) and tooltip.GetItem then
        local ok, _, link = pcall(tooltip.GetItem, tooltip)
        if ok and link then
            local cleanLink = Safe.String(link)
            itemID = cleanLink and tonumber(cleanLink:match("item:(%d+)")) or nil
        end
    end
    local nowT = GetTime and GetTime() or 0
    if not itemID or itemID <= 0 or tooltip._scAltItemId == itemID or (tooltip._scAltLastId == itemID and (nowT - (tooltip._scAltLastAt or 0)) < 0.05) then
        return
    end
    tooltip._scAltLastId = itemID
    tooltip._scAltLastAt = nowT

    local owners = Alts:GetItemOwners(itemID)
    if not owners or #owners == 0 then
        return
    end

    tooltip._scAltItemId = itemID
    tooltip:AddLine(" ")

    local grandTotal = 0
    local shown = 0
    for _, o in ipairs(owners) do
        grandTotal = grandTotal + (o.total or 0)
        if shown < 8 then
            shown = shown + 1
            local hex = Compat.ClassHex(o.classFile)
            local locParts = {}
            if (o.equipped or 0) > 0 then
                table.insert(locParts, L["Eq: %d"]:format(o.equipped))
            end
            if (o.bags or 0) > 0 then
                table.insert(locParts, L["Bags: %d"]:format(o.bags))
            end
            if (o.bank or 0) > 0 then
                table.insert(locParts, L["Bank: %d"]:format(o.bank))
            end
            local rightTxt = ("|cffffffff%d|r |cff9da7b5(%s)|r"):format(o.total or 0, table.concat(locParts, ", "))
            tooltip:AddDoubleLine(hex .. (o.displayName or "?") .. "|r", rightTxt)
        end
    end
    if #owners > 8 then
        tooltip:AddLine("|cff9da7b5" .. L["+%d more characters..."]:format(#owners - 8) .. "|r")
    end
    if #owners > 1 or grandTotal > (owners[1].total or 0) then
        tooltip:AddDoubleLine("|cff9da7b5" .. L["Total (Account)"] .. "|r", "|cffffd24d" .. grandTotal .. "|r")
    end
    pcall(tooltip.Show, tooltip)
end

local function RegisterItemTooltipIntegration()
    if itemTooltipRegistered then return end
    itemTooltipRegistered = true

    local function ClearItemTip(tip)
        if tip then
            tip._scAltItemId = nil
        end
    end
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tip and tip.HookScript then
            if tip:HasScript("OnTooltipCleared") then
                tip:HookScript("OnTooltipCleared", ClearItemTip)
            end
            if tip:HasScript("OnHide") then
                tip:HookScript("OnHide", ClearItemTip)
            end
        end
    end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip, data)
            AppendAltItemTooltip(tooltip, data)
        end)
    else
        for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tip and tip.HookScript and tip:HasScript("OnTooltipSetItem") then
                tip:HookScript("OnTooltipSetItem", function(t)
                    AppendAltItemTooltip(t, nil)
                end)
            end
        end
    end
end

function Alts:SetSurname(altKey, rawSurname)
    if not (ns.db and ns.db.alts and altKey and ns.db.alts[altKey]) then
        return false
    end
    local rec = ns.db.alts[altKey]
    local first = rec.firstName or rec.name or Safe.String(Safe.Call(UnitName, "player")) or ""
    local cleaned = Compat.CleanInput(rawSurname)
    if cleaned then
        -- Accept either "Surname" or "FirstName Surname"; store the Forever surname token cleanly.
        local firstLower = first:lower()
        local parsed = Compat.ParseForeverFullName(cleaned)
        local surnameToken
        if parsed and parsed.surname and parsed.firstName:lower() == firstLower then
            surnameToken = parsed.surname
        else
            surnameToken = cleaned:match("^([^%s%-]+)")
        end
        if not surnameToken or surnameToken == "" then
            return false
        end
        rec.firstName = first
        rec.surname = surnameToken
        rec.fullName = first .. " " .. surnameToken
        rec.userSetSurname = true
        if altKey == Compat.CharacterKey() and Compat.CacheForeverFullName then
            local myGuid = Safe.String(Safe.Call(UnitGUID, "player"))
            Compat.CacheForeverFullName(myGuid, rec.fullName, rec.firstName)
        end
    else
        rec.firstName = first
        rec.surname = nil
        rec.fullName = first
        rec.userSetSurname = false
    end
    ns:Emit("ALTS_UPDATED")
    return true
end

function Alts:RemoveAlt(altKey)
    if not (ns.db and ns.db.alts and altKey) then return false end
    if altKey == Compat.CharacterKey() then
        ns:Print(L["Cannot remove the currently logged-in character."])
        return false
    end
    if ns.db.alts[altKey] then
        ns.db.alts[altKey] = nil
        self.itemIndex = nil
        ns:Emit("ALTS_UPDATED")
        return true
    end
    return false
end

function Alts:Init()
    RegisterItemTooltipIntegration()
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        if ns.db and ns.db.alts and not ns.db.alts[Compat.CharacterKey()] then
            self:Snapshot(false)
        else
            self:QueueSnapshot(false, 1.5)
        end
    end)

    for _, scalarEvent in ipairs({
        "PLAYER_XP_UPDATE",
        "UPDATE_EXHAUSTION",
        "PLAYER_MONEY",
        "ZONE_CHANGED_NEW_AREA",
    }) do
        ns.RegisterEvent(self, scalarEvent, function()
            self:UpdateScalars()
        end)
    end

    ns.RegisterEvent(self, "PLAYER_LEVEL_UP", function()
        self:QueueSnapshot(false, 1.0)
    end)

    ns.RegisterEvent(self, "PLAYER_GUILD_UPDATE", function(_, _, unit)
        if not unit or unit == "player" then
            self:QueueSnapshot(false, 1.5)
        end
    end)

    for _, itemEvent in ipairs({
        "PLAYER_EQUIPMENT_CHANGED",
        "BAG_UPDATE_DELAYED",
        "SKILL_LINES_CHANGED",
        "TRADE_SKILL_UPDATE",
        "PLAYER_AVG_ITEM_LEVEL_UPDATE",
    }) do
        ns.RegisterEvent(self, itemEvent, function()
            self:QueueSnapshot(false, 1.5)
        end)
    end

    for _, bankEvent in ipairs({
        "BANKFRAME_OPENED",
        "PLAYERBANKSLOTS_CHANGED",
    }) do
        ns.RegisterEvent(self, bankEvent, function()
            self:QueueSnapshot(true, 0.4)
        end)
    end

    for _, chatEvent in ipairs({
        "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID",
        "CHAT_MSG_SAY",
        "CHAT_MSG_YELL",
        "CHAT_MSG_WHISPER",
    }) do
        ns.RegisterEvent(self, chatEvent, function(_, _, text, author, ...)
            local guid = select(10, ...)
            ApplyAuthorSurname(author, guid)
        end)
    end
end
