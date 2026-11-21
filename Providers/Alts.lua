local _, ns = ...

local Safe = ns.Safe
local Compat = ns.Compat
local L = ns.L

-- Records snapshots of the player's own characters across logins (WoW: Forever FirstName + Surname aware).
local Alts = {}
ns.Alts = Alts
table.insert(ns.modules, Alts)

local cachedMyGuid
local mySurnameConfirmed = false
local surnameChatRegistered = false

local function CurrentAltKey()
    if ns.Store and ns.Store.GetCurrentAltKey then
        return ns.Store:GetCurrentAltKey()
    end
    return Compat.CharacterKey and Compat.CharacterKey() or nil
end

local SURNAME_CHAT_EVENTS = {
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_WHISPER",
}

local function UnregisterSurnameChatEvents()
    if not surnameChatRegistered then return end
    surnameChatRegistered = false
    for _, chatEv in ipairs(SURNAME_CHAT_EVENTS) do
        ns.UnregisterEvent(Alts, chatEv)
    end
end

local function ApplyAuthorSurname(author, guid)
    if mySurnameConfirmed then
        UnregisterSurnameChatEvents()
        return
    end
    if not (ns.db and ns.db.alts) then return end
    if not cachedMyGuid then
        cachedMyGuid = Safe.String(Safe.Call(UnitGUID, "player"))
    end
    local cleanGuid = Safe.String(guid)
    if not (cachedMyGuid and cleanGuid and cleanGuid == cachedMyGuid) then return end
    local cleanAuthor = Safe.String(author)
    if not cleanAuthor then return end

    local key = CurrentAltKey()
    local rec = key and ns.db.alts[key]
    if not rec then
        Alts:Snapshot()
        rec = key and ns.db.alts[key]
    end
    if not rec then return end

    local parsed = Compat.ParseForeverFullName(cleanAuthor)
    if parsed and parsed.surname and parsed.firstName:lower() == (rec.firstName or rec.name or ""):lower() then
        if rec.surname ~= parsed.surname or rec.fullName ~= parsed.fullName then
            rec.firstName = parsed.firstName
            rec.surname = parsed.surname
            rec.fullName = parsed.fullName
            if Compat.CacheForeverFullName then
                Compat.CacheForeverFullName(cachedMyGuid, rec.fullName, rec.firstName)
            end
            ns:Emit("ALTS_UPDATED")
        end
        mySurnameConfirmed = true
        UnregisterSurnameChatEvents()
    end
end

local EQUIP_SLOT_COUNT = 19
local BAG_IDS = { 0, 1, 2, 3, 4 }
local BANK_BAG_IDS = { -1, 5, 6, 7, 8, 9, 10, 11 }
local MAX_CONTAINER_ITEMS = 260

local SECONDARY_PROF_PATTERNS = {
    "first aid", "primeiros socorros", "primeros auxilios",
    "cooking", "culinaria", "culinária", "cocina",
    "fishing", "pescaria", "pesca",
}

local CLASS_REAGENT_ITEMS = {
    WARLOCK = { [6265] = "Soul Shards" },
    SHAMAN  = { [17030] = "Ankh", [17058] = "Fish Oil", [17057] = "Shiny Fish Scales" },
    MAGE    = { [17031] = "Rune of Teleportation", [17032] = "Rune of Portals", [17020] = "Arcane Powder" },
    PRIEST  = { [17029] = "Sacred Candle", [17028] = "Holy Candle" },
    DRUID   = { [17026] = "Wild Thornroot", [17038] = "Ironwood Seed" },
    PALADIN = { [17033] = "Symbol of Divinity", [21177] = "Symbol of Kings" },
    ROGUE   = { [5140] = "Flash Powder", [5530] = "Blinding Powder", [5060] = "Thieves' Tools" },
}

local catalogParsedCache = {}
local catalogCacheCount = 0

local function ExtractLinkDisplayName(link)
    if type(link) ~= "string" then return "" end
    return link:match("%[(.-)%]") or ""
end

local function CompactItemLinkStr(link)
    if type(link) ~= "string" or link == "" then return nil end
    local raw = link:match("|H(item:[^|]+)|h") or link:match("^(item:[^|]+)")
    if not raw then return nil end
    local f = { strsplit(":", raw) }
    local hasMod = false
    for idx = 3, 8 do
        if f[idx] and f[idx] ~= "" and f[idx] ~= "0" then
            hasMod = true
            break
        end
    end
    if not hasMod then
        local modsMask = f[12]
        local numBonus = tonumber(f[14]) or 0
        if (modsMask and modsMask ~= "" and modsMask ~= "0") or numBonus > 0 then
            hasMod = true
        end
    end
    if not hasMod then
        return nil
    end
    while #f > 2 and (f[#f] == "" or f[#f]:find("^Player%-")) do
        f[#f] = nil
    end
    return table.concat(f, ":")
end

local function CatalogUpsert(itemID, link, name, icon, quality)
    local id = tonumber(itemID)
    if not id or id <= 0 then
        if type(link) == "string" then
            id = tonumber(link:match("item:(%d+)"))
        end
    end
    if not id or id <= 0 then return nil end

    local catalog = ns.db and ns.db.itemCatalog
    local existingRaw = catalog and catalog[id]
    local cName, cIcon, cQual, cClass, cSub, cEquip
    if type(existingRaw) == "string" and existingRaw ~= "" then
        local p1, p2, p3, p4, p5, p6 = strsplit("\t", existingRaw)
        cName = p1 ~= "" and p1 or nil
        cIcon = tonumber(p2) or (p2 ~= "" and p2 or nil)
        cQual = tonumber(p3)
        cClass = tonumber(p4)
        cSub = tonumber(p5)
        cEquip = (p6 and p6 ~= "") and p6 or nil
    end

    local resolvedName = (type(name) == "string" and name ~= "") and name or ExtractLinkDisplayName(link)
    if (not resolvedName or resolvedName == "") and not cName and C_Item and C_Item.GetItemNameByID then
        local okN, iName = pcall(C_Item.GetItemNameByID, id)
        local cleanN = okN and Safe.String(iName) or nil
        if cleanN and cleanN ~= "" then resolvedName = cleanN end
    end
    local finalName = resolvedName or cName or ""
    finalName = finalName:gsub("[\t\r\n]+", " ")

    local needInstant = (cClass == nil) or (not icon and not cIcon)
    local instIcon, classID, subClassID, equipLoc = cIcon, cClass, cSub, cEquip
    if needInstant and GetItemInfoInstant then
        local okI, _, _, _, eqLoc, fIcon, cId, sId = pcall(GetItemInfoInstant, link or id)
        if okI then
            equipLoc = Safe.String(eqLoc) or equipLoc
            instIcon = Safe.Value(fIcon) or instIcon
            classID = Safe.Number(cId) or classID
            subClassID = Safe.Number(sId) or subClassID
        end
    end

    local finalIcon = icon or instIcon or cIcon
    if not finalIcon and C_Item and C_Item.GetItemIconByID then
        local okIc, fID = pcall(C_Item.GetItemIconByID, id)
        if okIc and Safe.Value(fID) then finalIcon = Safe.Value(fID) end
    end

    local finalQual = quality or cQual
    if not finalQual and C_Item and C_Item.GetItemQualityByID then
        local okQ, qVal = pcall(C_Item.GetItemQualityByID, id)
        if okQ and Safe.Number(qVal) then finalQual = Safe.Number(qVal) end
    end
    finalQual = finalQual or 1

    if catalog and (not existingRaw or (finalName ~= "" and not cName) or (cClass == nil and classID ~= nil)) then
        local packed = table.concat({
            finalName,
            tostring(finalIcon or ""),
            tostring(finalQual),
            tostring(classID or ""),
            tostring(subClassID or ""),
            tostring(equipLoc or ""),
        }, "\t")
        if packed ~= existingRaw then
            catalog[id] = packed
            catalogParsedCache[id] = nil
        end
    end
    return id, finalName, finalIcon, finalQual, classID, subClassID, equipLoc
end

local function CatalogLookup(itemID)
    local id = tonumber(itemID)
    if not id or id <= 0 then return nil end
    local cached = catalogParsedCache[id]
    if cached then
        return cached[1], cached[2], cached[3], cached[4], cached[5], cached[6]
    end
    local catalog = ns.db and ns.db.itemCatalog
    local raw = catalog and catalog[id]
    if type(raw) ~= "string" or raw == "" then
        return nil
    end
    local p1, p2, p3, p4, p5, p6 = strsplit("\t", raw)
    local name = (p1 and p1 ~= "") and p1 or nil
    local icon = tonumber(p2) or ((p2 and p2 ~= "") and p2 or nil)
    local qual = tonumber(p3)
    local cls = tonumber(p4)
    local sub = tonumber(p5)
    local eq = (p6 and p6 ~= "") and p6 or nil
    if catalogCacheCount >= 1200 then
        wipe(catalogParsedCache)
        catalogCacheCount = 0
    end
    catalogParsedCache[id] = { name, icon, qual, cls, sub, eq }
    catalogCacheCount = catalogCacheCount + 1
    return name, icon, qual, cls, sub, eq
end

local function BuildPackedSlotString(itemID, count, itemStr)
    local cnt = math.max(1, tonumber(count) or 1)
    if itemStr and itemStr ~= "" then
        return string.format("%d\t%d\t%s", itemID, cnt, itemStr:gsub("[\r\n]", ""))
    elseif cnt > 1 then
        return string.format("%d\t%d", itemID, cnt)
    end
    return tostring(itemID)
end

local function PackRawItem(raw)
    if type(raw) == "string" then
        return raw
    end
    if type(raw) ~= "table" then return nil end
    local id = tonumber(raw.itemID)
    if not id or id <= 0 then
        id = type(raw.link) == "string" and tonumber(raw.link:match("item:(%d+)")) or nil
    end
    if not id or id <= 0 then
        return raw
    end
    CatalogUpsert(id, raw.link, raw.name, raw.icon, raw.quality)
    local customStr = CompactItemLinkStr(raw.link)
    return BuildPackedSlotString(id, raw.count or 1, customStr)
end

local function PackContainerList(rawItems)
    if type(rawItems) ~= "table" then return {}, "" end
    local packed = {}
    local mergedPlainIdx = {}
    for _, raw in ipairs(rawItems) do
        if type(raw) == "string" then
            local p1, p2, p3 = strsplit("\t", raw)
            local id = tonumber(p1)
            local cnt = math.max(1, tonumber(p2) or 1)
            local itemStr = (p3 and p3 ~= "") and p3 or nil
            if id and not itemStr then
                local existingIdx = mergedPlainIdx[id]
                if existingIdx then
                    local ep1, ep2 = strsplit("\t", packed[existingIdx])
                    packed[existingIdx] = BuildPackedSlotString(id, (tonumber(ep2) or 1) + cnt, nil)
                else
                    local idx = #packed + 1
                    packed[idx] = BuildPackedSlotString(id, cnt, nil)
                    mergedPlainIdx[id] = idx
                end
            else
                packed[#packed + 1] = raw
            end
        elseif type(raw) == "table" then
            local id = tonumber(raw.itemID) or (type(raw.link) == "string" and tonumber(raw.link:match("item:(%d+)")))
            if id and id > 0 then
                CatalogUpsert(id, raw.link, raw.name, raw.icon, raw.quality)
                local customStr = CompactItemLinkStr(raw.link)
                local cnt = math.max(1, tonumber(raw.count) or 1)
                if not customStr then
                    local existingIdx = mergedPlainIdx[id]
                    if existingIdx then
                        local _, ep2 = strsplit("\t", packed[existingIdx])
                        packed[existingIdx] = BuildPackedSlotString(id, (tonumber(ep2) or 1) + cnt, nil)
                    else
                        local idx = #packed + 1
                        packed[idx] = BuildPackedSlotString(id, cnt, nil)
                        mergedPlainIdx[id] = idx
                    end
                else
                    packed[#packed + 1] = BuildPackedSlotString(id, cnt, customStr)
                end
            else
                packed[#packed + 1] = raw
            end
        end
    end
    return packed, table.concat(packed, "\n")
end

local function BuildEquipDigest(equipTbl)
    if type(equipTbl) ~= "table" then return "" end
    local parts = {}
    for slotId = 1, EQUIP_SLOT_COUNT do
        local v = equipTbl[slotId]
        if type(v) == "string" then
            parts[slotId] = v
        elseif type(v) == "table" then
            parts[slotId] = tostring(PackRawItem(v) or "")
        else
            parts[slotId] = ""
        end
    end
    return table.concat(parts, "\n")
end

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

    local skillCount = GetNumSkillLines and (Safe.Number(Safe.Call(GetNumSkillLines)) or 0) or 0
    if #out == 0 and skillCount == 0 and type(prevProfs) == "table" and #prevProfs > 0 then
        return prevProfs
    end
    return out
end

local function SnapshotLockouts(prevLockouts)
    local out = {}
    local now = time()
    if GetNumSavedInstances and GetSavedInstanceInfo then
        local count = Safe.Number(Safe.Call(GetNumSavedInstances)) or 0
        for i = 1, count do
            local ok, name, id, reset, _, locked, extended, _, isRaid, _, difficultyName, numEncounters, encounterProgress = pcall(GetSavedInstanceInfo, i)
            if ok then
                name = Safe.String(name)
                local cleanReset = Safe.Number(reset) or 0
                local isLocked = Safe.Value(locked) == true
                local isExt = Safe.Value(extended) == true
                if name and name ~= "" and (isLocked or isExt or cleanReset > 0) then
                    out[#out + 1] = {
                        name = name,
                        id = Safe.Number(id) or 0,
                        reset = cleanReset,
                        expiresAt = (cleanReset > 0) and (now + cleanReset) or 0,
                        locked = isLocked,
                        extended = isExt,
                        isRaid = Safe.Value(isRaid) == true,
                        difficultyName = Safe.String(difficultyName) or "",
                        numEncounters = Safe.Number(numEncounters) or 0,
                        encounterProgress = Safe.Number(encounterProgress) or 0,
                    }
                end
            end
        end
    end
    if #out == 0 and not Alts._instanceInfoReady and type(prevLockouts) == "table" then
        for _, lk in ipairs(prevLockouts) do
            if type(lk) == "table" and (lk.expiresAt or 0) > now then
                out[#out + 1] = lk
            end
        end
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

local function ReadEquipSlot(slotId)
    local itemID = Safe.Number(Safe.Call(GetInventoryItemID, "player", slotId))
    local link = Safe.String(Safe.Call(GetInventoryItemLink, "player", slotId))
    local icon = Safe.Value(Safe.Call(GetInventoryItemTexture, "player", slotId))
    local quality = Safe.Number(Safe.Call(GetInventoryItemQuality, "player", slotId))
    if itemID or link then
        icon, quality, link = ResolveItemVisuals(link or itemID, icon, quality, link)
        local id = CatalogUpsert(itemID, link, nil, icon, quality)
        if id then
            return BuildPackedSlotString(id, 1, CompactItemLinkStr(link))
        end
        return {
            itemID = itemID,
            link = link,
            icon = icon,
            quality = quality or 1,
        }
    end
    return nil
end

local function SnapshotEquipment()
    local equip = {}
    for slotId = 1, EQUIP_SLOT_COUNT do
        local slotRec = ReadEquipSlot(slotId)
        if slotRec then
            equip[slotId] = slotRec
        end
    end
    return equip
end

local function SnapshotEquipmentDelta(prevEquip, dirtySlots, isFull, ownerKey)
    if isFull or type(prevEquip) ~= "table" or not Alts._equipCacheValid or Alts._equipCacheOwner ~= ownerKey then
        local equip = SnapshotEquipment()
        Alts._equipCacheValid = true
        Alts._equipCacheOwner = ownerKey
        local changed = true
        if type(prevEquip) == "table" and BuildEquipDigest(equip) == BuildEquipDigest(prevEquip) then
            changed = false
        end
        return equip, changed
    end
    if type(dirtySlots) ~= "table" or next(dirtySlots) == nil then
        return prevEquip, false
    end
    local out = {}
    for k, v in pairs(prevEquip) do
        out[k] = PackRawItem(v) or v
    end
    for slotId in pairs(dirtySlots) do
        if type(slotId) == "number" and slotId >= 1 and slotId <= EQUIP_SLOT_COUNT then
            out[slotId] = ReadEquipSlot(slotId)
        end
    end
    local changed = BuildEquipDigest(out) ~= BuildEquipDigest(prevEquip)
    return out, changed
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
                        local id = CatalogUpsert(itemID, link, nil, icon, quality)
                        if id then
                            items[#items + 1] = BuildPackedSlotString(id, count or 1, CompactItemLinkStr(link))
                        else
                            items[#items + 1] = {
                                itemID = itemID,
                                link = link,
                                icon = icon,
                                count = (count and count > 1) and count or 1,
                                quality = quality or 1,
                            }
                        end
                    end
                else
                    freeSlots = freeSlots + 1
                end
            end
        end
    end

    return items, freeSlots, totalSlots
end

local function SnapshotBagsIncremental(prevAlt, dirtyBags, isFull, ownerKey)
    Alts._bagContainerCache = Alts._bagContainerCache or {}
    local cacheValid = (not isFull) and Alts._bagCacheValid and (Alts._bagCacheOwner == ownerKey)
    if cacheValid and type(prevAlt) == "table" and type(prevAlt.bags) == "table" and type(dirtyBags) == "table" and next(dirtyBags) == nil then
        return prevAlt.bags, prevAlt.bagFree or 0, prevAlt.bagTotal or 0, false, prevAlt._bagsSig
    end

    local rawBags = {}
    local bagFree = 0
    local bagTotal = 0
    for _, bagId in ipairs(BAG_IDS) do
        local bagCache = Alts._bagContainerCache[bagId]
        if (not cacheValid) or (not bagCache) or (dirtyBags and dirtyBags[bagId]) then
            local bItems, bFree, bTot = SnapshotContainerRange({ bagId })
            bagCache = {
                items = bItems,
                free = bFree,
                total = bTot,
            }
            Alts._bagContainerCache[bagId] = bagCache
        end
        bagFree = bagFree + (bagCache.free or 0)
        bagTotal = bagTotal + (bagCache.total or 0)
        if type(bagCache.items) == "table" then
            for i = 1, #bagCache.items do
                if #rawBags >= MAX_CONTAINER_ITEMS then break end
                rawBags[#rawBags + 1] = bagCache.items[i]
            end
        end
    end
    local bags, bagsSig = PackContainerList(rawBags)
    Alts._bagCacheValid = true
    Alts._bagCacheOwner = ownerKey
    local prevSig = (type(prevAlt) == "table") and (prevAlt._bagsSig or (type(prevAlt.bags) == "table" and select(2, PackContainerList(prevAlt.bags)))) or nil
    local changed = (bagsSig ~= prevSig) or (bagFree ~= (prevAlt and prevAlt.bagFree)) or (bagTotal ~= (prevAlt and prevAlt.bagTotal))
    if not changed and type(prevAlt) == "table" and type(prevAlt.bags) == "table" and type(prevAlt.bags[1]) ~= "table" then
        return prevAlt.bags, bagFree, bagTotal, false, bagsSig
    end
    return bags, bagFree, bagTotal, true, bagsSig
end

function Alts:GetHearthstoneStatus(altData)
    local isCurrent = (not altData) or (altData.key == CurrentAltKey())
    if isCurrent then
        local getItemCd = (C_Container and C_Container.GetItemCooldown) or _G.GetItemCooldown
        local getItemCnt = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
        if getItemCd then
            local hasHs = (not getItemCnt) or (Safe.Number(Safe.Call(getItemCnt, 6948)) or 0) > 0
            if hasHs then
                local okCd, st, dur = pcall(getItemCd, 6948)
                st = okCd and Safe.Number(st) or nil
                dur = okCd and Safe.Number(dur) or nil
                if st and dur and st > 0 and dur > 1.5 then
                    local nowClock = (GetTime and GetTime()) or 0
                    local rem = (st + dur) - nowClock
                    if rem > 1 then
                        return time() + math.ceil(rem), math.ceil(rem)
                    end
                end
                return 0, 0
            end
        end
        return nil, nil
    end

    if type(altData.hearthReadyAt) == "number" then
        local rem = math.max(0, altData.hearthReadyAt - time())
        return altData.hearthReadyAt, rem
    end
    return nil, nil
end

function Alts:GetArmoryURL(altEntry)
    if not altEntry then return nil end
    local full = altEntry.fullName or altEntry.name or ""
    full = full:gsub("^%s+", ""):gsub("%s+$", "")
    if full == "" then return nil end
    local slug = full:gsub("%s+", "-")
    slug = slug:gsub("[^%w%-]", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end)
    -- Region and ruleset come from the character's realm pool / world type (e.g. "camwowus1realmpvp").
    local pool = tostring(altEntry.realmPool or altEntry.realmName or Compat.RealmPool(Compat.Realm()) or ""):lower()
    local region = pool:match("^camwow(%a%a)%d*") or "us"
    local wt = type(altEntry.worldType) == "string" and altEntry.worldType:lower() or ""
    local ruleset = ((wt:find("pve", 1, true) or wt:find("normal", 1, true)) and "pve")
        or (wt:find("pvp", 1, true) and "pvp")
        or ((pool:find("pve", 1, true) or pool:find("normal", 1, true)) and "pve")
        or (pool:find("pvp", 1, true) and "pvp")
        or pool:match("realm(%a+)$")
        or "pvp"
    if region ~= "us" and region ~= "eu" then region = "us" end
    return "https://armorywowforever.com/c/forever/" .. region .. "/" .. ruleset .. "/" .. slug
end

function Alts:Snapshot(includeBank, force)
    if not (ns.db and ns.db.alts) then return end
    local monoNow = GetTime and GetTime() or 0
    if not includeBank and not force and self._lastSnapshotAt and (monoNow - self._lastSnapshotAt) < 0.5 then
        return
    end
    local name = Safe.String(Safe.Call(UnitName, "player"))
    if not name then return end

    local key = CurrentAltKey()
    if not key then return end
    local prev = ns.db.alts[key]
    local prevFull = (type(prev) == "table") and prev.fullName or nil
    local resolved = Compat.ResolvePlayerFullName(prevFull) or Compat.ParseForeverFullName(name)

    local className, classFile = Safe.Call(UnitClass, "player")
    local raceName, raceFile = Safe.Call(UnitRace, "player")
    local sex = Safe.Number(Safe.Call(UnitSex, "player"))
    local myGuid = Safe.String(Safe.Call(UnitGUID, "player"))
    local bindLocation = Safe.String(Safe.Call(GetBindLocation))
    if (not bindLocation or bindLocation == "") and type(prev) == "table" then
        bindLocation = prev.bindLocation
    end
    local isOwnerMatch = (self._snapshotOwnerKey == key)
    self._snapshotOwnerKey = key

    local fullProfs = force or (not isOwnerMatch) or (self._dirtyProfs ~= false) or type(prev) ~= "table" or type(prev.professions) ~= "table" or #prev.professions == 0
    local professions = fullProfs and SnapshotProfessions(type(prev) == "table" and prev.professions or nil) or prev.professions
    self._dirtyProfs = false
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

    local dirtyEquip = self._dirtyEquipSlots
    self._dirtyEquipSlots = {}
    local fullEquip = force or (not isOwnerMatch) or (self._dirtyEquipAll == true)
    self._dirtyEquipAll = false
    local equipment, equipChanged = SnapshotEquipmentDelta(type(prev) == "table" and prev.equipment or nil, dirtyEquip, fullEquip, key)

    local dirtyBags = self._dirtyBags
    self._dirtyBags = {}
    local fullBags = force or (not isOwnerMatch) or (self._dirtyBagsAll == true)
    self._dirtyBagsAll = false
    local bags, bagFree, bagTotal, bagsChanged = SnapshotBagsIncremental(prev, dirtyBags, fullBags, key)
    local bank = type(prev) == "table" and prev.bank or nil
    local bankFree = type(prev) == "table" and prev.bankFree or 0
    local bankTotal = type(prev) == "table" and prev.bankTotal or 0
    local bankUpdatedAt = type(prev) == "table" and prev.bankUpdatedAt or nil
    local bankChanged = false
    if includeBank then
        local bankBags = {}
        for i = 1, #BANK_BAG_IDS do
            bankBags[i] = BANK_BAG_IDS[i]
        end
        local getNum = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
        if getNum then
            local reagentBag = REAGENTBANK_CONTAINER
            local okR, rSlots = reagentBag and pcall(getNum, reagentBag)
            if okR and (Safe.Number(rSlots) or 0) > 0 then
                bankBags[#bankBags + 1] = reagentBag
            end
        end
        local bItems, bFree, bTot = SnapshotContainerRange(bankBags)
        if bTot > 0 then
            local bankPacked, bankSig = PackContainerList(bItems)
            local prevBankSig = (type(prev) == "table" and type(prev.bank) == "table") and select(2, PackContainerList(prev.bank)) or nil
            bankChanged = (bankSig ~= prevBankSig) or (bFree ~= bankFree) or (bTot ~= bankTotal)
            bank = bankPacked
            bankFree = bFree
            bankTotal = bTot
            bankUpdatedAt = time()
        end
    end

    local currentZone = Compat.CurrentZoneName()
    if (not currentZone or currentZone == "") and type(prev) == "table" and prev.zone and prev.zone ~= "" then
        currentZone = prev.zone
    end
    local fullLocks = force or (not isOwnerMatch) or (self._dirtyLocks ~= false) or type(prev) ~= "table" or type(prev.lockouts) ~= "table"
    local lockouts = fullLocks and SnapshotLockouts(prev and prev.lockouts) or prev.lockouts
    self._dirtyLocks = false
    local hasNewMail = (HasNewMail and Safe.Value(Safe.Call(HasNewMail)) == true) or false
    local mailSenders = nil
    local mailSince = nil
    if hasNewMail then
        if GetLatestThreeSenders then
            local okM, s1, s2, s3 = pcall(GetLatestThreeSenders)
            if okM then
                local list = {}
                for _, rawS in ipairs({ s1, s2, s3 }) do
                    local cleanS = Safe.String(rawS)
                    if cleanS and cleanS ~= "" then
                        list[#list + 1] = cleanS
                    end
                end
                if #list > 0 then
                    mailSenders = list
                end
            end
        end
        if not mailSenders and type(prev) == "table" and type(prev.mailSenders) == "table" then
            mailSenders = prev.mailSenders
        end
        mailSince = (type(prev) == "table" and prev.hasMail and prev.mailSince) or time()
    end
    local hearthReadyAt = self:GetHearthstoneStatus(nil)
    local nextItemSeq = (type(prev) == "table" and tonumber(prev._itemSeq)) or 0
    local itemsChanged = (equipChanged or bagsChanged or bankChanged or type(prev) ~= "table") and true or false
    if itemsChanged then
        nextItemSeq = nextItemSeq + 1
    end
    local wasResting = (IsResting and Safe.Value(Safe.Call(IsResting)) == true) or false
    local durPct = nil
    if GetInventoryItemDurability then
        local dCur, dMax = 0, 0
        for slotId = 1, EQUIP_SLOT_COUNT do
            local okD, cVal, mVal = pcall(GetInventoryItemDurability, slotId)
            cVal = okD and Safe.Number(cVal) or nil
            mVal = okD and Safe.Number(mVal) or nil
            if cVal and mVal and mVal > 0 then
                dCur = dCur + cVal
                dMax = dMax + mVal
            end
        end
        if dMax > 0 then
            durPct = math.floor((dCur / dMax) * 100 + 0.5)
        end
    end
    local prevValidRealm = type(prev) == "table" and prev.realmName and (not Compat.LooksLikeServerRealm or Compat.LooksLikeServerRealm(prev.realmName))
    local liveRealm = Compat.Realm()
    local liveValid = type(liveRealm) == "string" and liveRealm ~= "" and (not Compat.LooksLikeServerRealm or Compat.LooksLikeServerRealm(liveRealm))
    local realmNorm = (liveValid and liveRealm) or (prevValidRealm and prev.realmName) or liveRealm
    local liveRaw = GetRealmName and Safe.String(Safe.Call(GetRealmName)) or nil
    local realmRaw = (liveRaw and (not Compat.LooksLikeServerRealm or Compat.LooksLikeServerRealm(liveRaw))) and liveRaw
        or (type(prev) == "table" and prev.realmRaw)
        or liveRaw
    local worldType = (Compat.DetectWorldType and Compat.DetectWorldType(realmNorm, realmRaw))
        or (type(prev) == "table" and prev.worldType)
        or nil
    local realmPool = Compat.RealmPool(realmNorm)
    local resolvedFirst = (resolved and resolved.firstName) or (type(prev) == "table" and prev.firstName) or name
    local resolvedSurname = (resolved and resolved.surname)
    if (not resolvedSurname or resolvedSurname == "") and type(prev) == "table" and type(prev.surname) == "string" and prev.surname ~= ""
        and type(prev.firstName or prev.name) == "string" and (prev.firstName or prev.name):lower() == tostring(resolvedFirst or name):lower()
    then
        resolvedSurname = prev.surname
    end
    local resolvedFull = (resolvedSurname and resolvedSurname ~= "") and (tostring(resolvedFirst or name) .. " " .. resolvedSurname)
        or (resolved and resolved.fullName)
        or name
    ns.db.alts[key] = {
        name = name,
        firstName = resolvedFirst,
        surname = resolvedSurname,
        fullName = resolvedFull,
        realmName = realmNorm,
        realmRaw = realmRaw,
        worldType = worldType,
        realmPool = realmPool,
        faction = faction,
        className = Safe.String(className) or (type(prev) == "table" and prev.className or nil),
        classFile = Safe.String(classFile),
        raceName = Safe.String(raceName),
        raceFile = Safe.String(raceFile),
        sex = sex,
        guid = myGuid or (type(prev) == "table" and prev.guid or nil),
        level = level,
        itemLevel = itemLevel,
        durabilityPct = durPct,
        xp = xp,
        xpMax = xpMax,
        rested = rested,
        wasResting = wasResting,
        money = money,
        zone = currentZone or "",
        bindLocation = bindLocation or "",
        hearthReadyAt = hearthReadyAt,
        professions = professions,
        craftCooldowns = type(prev) == "table" and prev.craftCooldowns or nil,
        lockouts = lockouts,
        guild = guild,
        equipment = equipment,
        bags = bags,
        bagFree = bagFree,
        bagTotal = bagTotal,
        bank = bank,
        bankFree = bankFree,
        bankTotal = bankTotal,
        bankUpdatedAt = bankUpdatedAt,
        hasMail = hasNewMail,
        mailSenders = mailSenders,
        mailSince = mailSince,
        firstSeen = (type(prev) == "table" and prev.firstSeen) or time(),
        _itemSeq = nextItemSeq,
        lastActive = time(),
    }

    if self._dupAltsCleanedForKey ~= key and ns.Store and ns.Store.CleanupDuplicateSameWorldAlts then
        self._dupAltsCleanedForKey = key
        ns.Store:CleanupDuplicateSameWorldAlts(key, myGuid, resolved and resolved.fullName or name, realmPool, worldType)
    end

    if resolved and resolved.surname and resolved.fullName and Compat.CacheForeverFullName then
        Compat.CacheForeverFullName(myGuid, resolved.fullName, resolved.firstName)
    end

    self._lastSnapshotAt = GetTime and GetTime() or 0
    if itemsChanged then
        self.itemIndex = nil
    end
    ns:Emit("ALTS_UPDATED")
end

--- Lightweight O(1) update for currency, XP, level, and zone without scanning containers or skills.
function Alts:UpdateScalars()
    if ns.db and ns.db.settings and ns.db.settings.embedCharacterWindow == false then return end
    if not (ns.db and ns.db.alts) then return end
    local key = CurrentAltKey()
    local rec = key and ns.db.alts[key]
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
    if IsResting then
        rec.wasResting = (Safe.Value(Safe.Call(IsResting)) == true) or false
    end
    local money = Safe.Number(Safe.Call(GetMoney))
    if money and money >= 0 then rec.money = money end
    local currentZone = Compat.CurrentZoneName()
    if currentZone and currentZone ~= "" then
        rec.zone = currentZone
    end
    if HasNewMail then
        local hasNew = Safe.Value(Safe.Call(HasNewMail)) == true
        rec.hasMail = hasNew
        if hasNew then
            rec.mailSince = rec.mailSince or time()
            if (not rec.mailSenders or #rec.mailSenders == 0) and GetLatestThreeSenders then
                local okM, s1, s2, s3 = pcall(GetLatestThreeSenders)
                if okM then
                    local list = {}
                    for _, rawS in ipairs({ s1, s2, s3 }) do
                        local cleanS = Safe.String(rawS)
                        if cleanS and cleanS ~= "" then
                            list[#list + 1] = cleanS
                        end
                    end
                    if #list > 0 then
                        rec.mailSenders = list
                    end
                end
            end
        else
            rec.mailSince = nil
            rec.mailSenders = nil
        end
    end
    rec.lastActive = time()

    if ns.UI and ns.UI.IsAltsVisible and ns.UI:IsAltsVisible() then
        ns:Emit("ALTS_UPDATED")
    end
end

--- Debounced full alt snapshot so rapid bag/equipment/skill events coalesce cleanly.
function Alts:QueueSnapshot(includeBank, delay)
    if ns.db and ns.db.settings and ns.db.settings.embedCharacterWindow == false then
        return
    end
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

local function BuildDisplayHyperlink(itemID, itemStr, name, quality)
    local rawStr = (type(itemStr) == "string" and itemStr ~= "") and itemStr or (itemID and ("item:" .. tostring(itemID)))
    if not rawStr then return nil end
    local q = tonumber(quality) or 1
    local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    local hex = (qc and qc.hex) or "|cffffffff"
    local disp = (type(name) == "string" and name ~= "") and name or ("Item #" .. tostring(itemID or "?"))
    return hex .. "|H" .. rawStr .. "|h[" .. disp .. "]|h|r"
end

function Alts:ParseItemRaw(entry)
    if type(entry) == "string" then
        local p1, p2, p3 = strsplit("\t", entry)
        local id = tonumber(p1)
        if not id or id <= 0 then return nil end
        local cnt = math.max(1, tonumber(p2) or 1)
        local itemStr = (p3 and p3 ~= "") and p3 or nil
        local name, icon, quality, classID, subClassID, equipLoc = CatalogLookup(id)
        if not name or not icon or classID == nil then
            local _, cName, cIcon, cQual, cCls, cSub, cEq = CatalogUpsert(id, itemStr, name, icon, quality)
            name = name or cName
            icon = icon or cIcon
            quality = quality or cQual
            classID = classID or cCls
            subClassID = subClassID or cSub
            equipLoc = equipLoc or cEq
        end
        return id, cnt, itemStr, name, icon, quality or 1, classID, subClassID, equipLoc
    elseif type(entry) == "table" then
        local id = tonumber(entry.itemID)
        if not id or id <= 0 then
            id = type(entry.link) == "string" and tonumber(entry.link:match("item:(%d+)")) or nil
        end
        local cnt = math.max(1, tonumber(entry.count) or 1)
        local name = (type(entry.name) == "string" and entry.name ~= "") and entry.name or ExtractLinkDisplayName(entry.link)
        local icon = entry.icon
        local quality = entry.quality
        local classID, subClassID, equipLoc
        if id and id > 0 then
            local cName, cIcon, cQual, cCls, cSub, cEq = CatalogLookup(id)
            if not cName or cCls == nil then
                local _, uName, uIcon, uQual, uCls, uSub, uEq = CatalogUpsert(id, entry.link, name, icon, quality)
                cName, cIcon, cQual, cCls, cSub, cEq = uName, uIcon, uQual, uCls, uSub, uEq
            end
            name = (name ~= "" and name) or cName
            icon = icon or cIcon
            quality = quality or cQual
            classID, subClassID, equipLoc = cCls, cSub, cEq
        end
        return id, cnt, entry.link, name, icon, quality or 1, classID, subClassID, equipLoc
    end
    return nil
end

function Alts:UnpackItem(entry, locLabel, slotId)
    local id, cnt, rawLink, name, icon, quality, classID, subClassID, equipLoc = self:ParseItemRaw(entry)
    if not id and type(entry) ~= "table" then return nil end
    local fullLink = (type(rawLink) == "string" and rawLink:find("|Hitem:", 1, true))
        and rawLink
        or BuildDisplayHyperlink(id, rawLink, name, quality)
    return {
        itemID = id,
        link = fullLink,
        name = name,
        icon = icon,
        quality = quality or 1,
        count = cnt or 1,
        classID = classID,
        subClassID = subClassID,
        equipLoc = equipLoc,
        _isEquip = slotId ~= nil or nil,
        _slotId = slotId,
        _locLabel = locLabel,
    }
end

local function MatchItemFilters(itemCat, minQuality, quality, classID, subClassID, equipLoc)
    if minQuality and minQuality > 0 and (quality or 1) < minQuality then
        return false
    end
    if not itemCat or itemCat == "all" then
        return true
    end
    local c = tonumber(classID)
    local eq = (type(equipLoc) == "string" and equipLoc ~= "")
    if itemCat == "equip" then
        return eq or c == 2 or c == 4
    elseif itemCat == "consumable" then
        return c == 0
    elseif itemCat == "trade" then
        return c == 7 or c == 9
    elseif itemCat == "other" then
        return not (eq or c == 2 or c == 4 or c == 0 or c == 7 or c == 9)
    end
    return true
end

function Alts:GetEstimatedRested(altData)
    if type(altData) ~= "table" then
        return 0, false, 0, false, 0
    end
    local lvl = tonumber(altData.level) or 0
    if lvl >= 60 then
        return 0, false, 0, false, 0
    end
    local curKey = CurrentAltKey()
    local xpMax = math.max(1, tonumber(altData.xpMax) or 1)
    if altData.key == curKey then
        local liveRested = Safe.Number(Safe.Call(GetXPExhaustion))
        local val = (liveRested ~= nil) and liveRested or (tonumber(altData.rested) or 0)
        local pct = math.min(150, math.floor((val / xpMax) * 100 + 0.5))
        local restingNow = (IsResting and Safe.Value(Safe.Call(IsResting)) == true) or (altData.wasResting == true)
        return pct, false, 0, restingNow, pct
    end
    local baseRested = math.max(0, tonumber(altData.rested) or 0)
    local recordedPct = math.min(150, math.floor((baseRested / xpMax) * 100 + 0.5))
    local lastTs = tonumber(altData.lastActive) or time()
    local elapsed = math.max(0, time() - lastTs)
    local wasResting = (altData.wasResting == true)
    -- WoW Classic/Forever Rested XP accumulation: 5% level per 8h in Inn/City, 4x slower outdoors.
    local ratePerSec = wasResting and ((xpMax * 0.05) / 28800) or ((xpMax * 0.05) / 115200)
    local maxRested = xpMax * 1.5
    local estRested = math.min(maxRested, baseRested + (elapsed * ratePerSec))
    local estPct = math.min(150, math.floor((estRested / xpMax) * 100 + 0.5))
    local remRested = math.max(0, maxRested - estRested)
    local etaSec = (remRested > 1 and ratePerSec > 0) and math.ceil(remRested / ratePerSec) or 0
    return estPct, (elapsed >= 1800 and estPct > recordedPct), etaSec, wasResting, recordedPct
end

function Alts:GetCraftCooldowns(altData)
    if type(altData) ~= "table" or type(altData.craftCooldowns) ~= "table" then
        return {}
    end
    local now = time()
    local out = {}
    for _, cd in ipairs(altData.craftCooldowns) do
        if type(cd) == "table" and cd.name and cd.name ~= "" then
            local readyAt = tonumber(cd.readyAt) or 0
            local rem = math.max(0, readyAt - now)
            if (now - readyAt) <= (7 * 86400) then
                out[#out + 1] = {
                    name = cd.name,
                    prof = cd.prof or "",
                    readyAt = readyAt,
                    remaining = rem,
                    isReady = rem == 0,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.isReady ~= b.isReady then return a.isReady end
        return (a.remaining or 0) < (b.remaining or 0)
    end)
    return out
end

function Alts:HasReadyCraftCooldown(altData)
    if type(altData) ~= "table" or type(altData.craftCooldowns) ~= "table" then
        return false
    end
    local now = time()
    for _, cd in ipairs(altData.craftCooldowns) do
        if type(cd) == "table" and (tonumber(cd.readyAt) or 0) > 0 then
            local readyAt = tonumber(cd.readyAt)
            if readyAt <= now and (now - readyAt) <= (7 * 86400) then
                return true
            end
        end
    end
    return false
end

local RECIPE_FOLD_MAP = {
    ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Ä"] = "a",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i", ["Í"] = "i", ["Ì"] = "i", ["Î"] = "i", ["Ï"] = "i",
    ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o", ["Ó"] = "o", ["Ò"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ö"] = "o",
    ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["Ú"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
    ["ç"] = "c", ["Ç"] = "c", ["ñ"] = "n", ["Ñ"] = "n",
}

local function FoldRecipeText(str)
    if type(str) ~= "string" or str == "" then return "" end
    local s = str:gsub("[%z\1-\127\194-\244][\128-\191]*", function(ch)
        return RECIPE_FOLD_MAP[ch] or ch
    end)
    s = s:lower():gsub("[%p]+", " "):gsub("%s+", " ")
    return Compat.Trim and Compat.Trim(s) or s:match("^%s*(.-)%s*$")
end

local function NormalizeRecipeLookupName(folded)
    if not folded or folded == "" then return "" end
    local s = folded:gsub("^encantamento d[aeo] ", "encantar "):gsub("^encantamento ", "encantar "):gsub("^encantamiento d[aeo] ", "encantar "):gsub("^encantamiento ", "encantar ")
    s = s:gsub("^formula ", ""):gsub("^recipe ", ""):gsub("^receita ", ""):gsub("^receta ", ""):gsub("^plans ", ""):gsub("^projeto ", ""):gsub("^pattern ", ""):gsub("^molde ", ""):gsub("^schematic ", ""):gsub("^esquema ", ""):gsub("^design ", ""):gsub("^desenho ", "")
    return Compat.Trim and Compat.Trim(s) or s:match("^%s*(.-)%s*$")
end

local function NormalizeTradeProfCode(rawName)
    if type(rawName) ~= "string" or rawName == "" then return "OTHER" end
    local f = FoldRecipeText(rawName)
    if f:find("alch", 1, true) or f:find("alquim", 1, true) then return "ALCHEMY"
    elseif f:find("blacksmith", 1, true) or f:find("ferraria", 1, true) or f:find("herrer", 1, true) then return "BLACKSMITHING"
    elseif f:find("enchant", 1, true) or f:find("encant", 1, true) then return "ENCHANTING"
    elseif f:find("engineer", 1, true) or f:find("engenh", 1, true) or f:find("ingenier", 1, true) then return "ENGINEERING"
    elseif f:find("leatherwork", 1, true) or f:find("courar", 1, true) or f:find("peleter", 1, true) then return "LEATHERWORKING"
    elseif f:find("tailor", 1, true) or f:find("alfaiat", 1, true) or f:find("sastr", 1, true) then return "TAILORING"
    elseif f:find("cook", 1, true) or f:find("culin", 1, true) or f:find("cocin", 1, true) then return "COOKING"
    elseif f:find("first aid", 1, true) or f:find("primeiros socorros", 1, true) or f:find("primeros auxilios", 1, true) then return "FIRST_AID"
    elseif f:find("jewelcraft", 1, true) or f:find("joalher", 1, true) or f:find("joyer", 1, true) then return "JEWELCRAFTING"
    elseif f:find("inscrip", 1, true) or f:find("escriv", 1, true) then return "INSCRIPTION"
    elseif f:find("min", 1, true) or f:find("smelt", 1, true) or f:find("fundic", 1, true) then return "MINING"
    elseif f:find("fish", 1, true) or f:find("pesc", 1, true) then return "FISHING"
    elseif f:find("herb", 1, true) or f:find("herbor", 1, true) then return "HERBALISM"
    end
    return f:upper():gsub("%s+", "_")
end

local RECIPE_SUBCLASS_TO_PROF = {
    [1] = "LEATHERWORKING",
    [2] = "TAILORING",
    [3] = "ENGINEERING",
    [4] = "BLACKSMITHING",
    [5] = "COOKING",
    [6] = "ALCHEMY",
    [7] = "FIRST_AID",
    [8] = "ENCHANTING",
    [9] = "FISHING",
    [10] = "JEWELCRAFTING",
    [11] = "INSCRIPTION",
}

local recipeCatalogCache = {}
local recipeCatalogCacheCount = 0

local function ParseRecipeCatalogRaw(rKey, raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    local cached = recipeCatalogCache[rKey]
    if cached and cached._raw == raw then
        return cached
    end
    local p1, p2, p3, p4, p5, p6, p7, p8 = strsplit("\t", raw)
    local obj = {
        _raw = raw,
        key = rKey,
        name = (p1 and p1 ~= "") and p1 or rKey,
        profCode = (p2 and p2 ~= "") and p2 or "OTHER",
        profDisp = (p3 and p3 ~= "") and p3 or "",
        itemID = tonumber(p4),
        spellID = tonumber(p5),
        quality = tonumber(p6) or 1,
        icon = tonumber(p7) or ((p7 and p7 ~= "") and p7 or nil),
        reagentsStr = (p8 and p8 ~= "") and p8 or nil,
    }
    if recipeCatalogCacheCount >= 2000 then
        wipe(recipeCatalogCache)
        recipeCatalogCacheCount = 0
    end
    recipeCatalogCache[rKey] = obj
    recipeCatalogCacheCount = recipeCatalogCacheCount + 1
    return obj
end

local function RecipeCatalogUpsert(rKey, name, profCode, profDisp, itemID, spellID, quality, icon, reagentsStr)
    if not (ns.db and rKey and rKey ~= "") then return nil end
    ns.db.recipeCatalog = ns.db.recipeCatalog or {}
    local existing = ns.db.recipeCatalog[rKey]
    local prev = existing and ParseRecipeCatalogRaw(rKey, existing) or nil
    local fName = ((type(name) == "string" and name ~= "") and name or (prev and prev.name) or ""):gsub("[\t\r\n]+", " ")
    if fName == "" then return nil end
    local fCode = (type(profCode) == "string" and profCode ~= "") and profCode or (prev and prev.profCode) or "OTHER"
    local fProf = ((type(profDisp) == "string" and profDisp ~= "") and profDisp or (prev and prev.profDisp) or ""):gsub("[\t\r\n]+", " ")
    local fItem = tonumber(itemID) or (prev and prev.itemID)
    local fSpell = tonumber(spellID) or (prev and prev.spellID)
    local fQual = tonumber(quality) or (prev and prev.quality) or 1
    local fIcon = icon or (prev and prev.icon)
    if not fIcon and fItem and C_Item and C_Item.GetItemIconByID then
        local okIc, idIc = pcall(C_Item.GetItemIconByID, fItem)
        if okIc and Safe.Value(idIc) then fIcon = Safe.Value(idIc) end
    end
    if not fQual and fItem and C_Item and C_Item.GetItemQualityByID then
        local okQ, qVal = pcall(C_Item.GetItemQualityByID, fItem)
        if okQ and Safe.Number(qVal) then fQual = Safe.Number(qVal) end
    end
    local fReag = (type(reagentsStr) == "string" and reagentsStr ~= "") and reagentsStr:gsub("[\t\r\n]+", "") or (prev and prev.reagentsStr) or ""

    if existing and prev and prev.name == fName and prev.profCode == fCode and (prev.icon or "") == (fIcon or "")
        and (prev.reagentsStr or "") == fReag and prev.itemID == fItem and prev.spellID == fSpell
    then
        return rKey
    end
    local packed = table.concat({
        fName,
        fCode,
        fProf,
        tostring(fItem or ""),
        tostring(fSpell or ""),
        tostring(fQual or 1),
        tostring(fIcon or ""),
        fReag,
    }, "\t")
    if packed ~= existing then
        ns.db.recipeCatalog[rKey] = packed
        recipeCatalogCache[rKey] = nil
    end
    return rKey
end

local function FormatReagentsSummary(reagentsStr)
    if type(reagentsStr) ~= "string" or reagentsStr == "" then return nil end
    local parts = {}
    for pair in reagentsStr:gmatch("[^,]+") do
        local ridStr, qtyStr = pair:match("^(%d+):(%d+)$")
        local rid = tonumber(ridStr)
        local qty = tonumber(qtyStr) or 1
        if rid and rid > 0 then
            local rName = CatalogLookup(rid)
            if (not rName or rName == "") and C_Item and C_Item.GetItemNameByID then
                local okN, iN = pcall(C_Item.GetItemNameByID, rid)
                rName = okN and Safe.String(iN) or nil
            end
            parts[#parts + 1] = ("%dx %s"):format(qty, (rName and rName ~= "") and rName or ("#" .. tostring(rid)))
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

local function CompareRecipeAltEntries(a, b)
    local curKey = CurrentAltKey()
    local aCur = (a.altKey == curKey)
    local bCur = (b.altKey == curKey)
    if aCur ~= bCur then return aCur end
    return (a.displayName or ""):lower() < (b.displayName or ""):lower()
end

function Alts:GetRecipeIndex(worldScope, factionFilter)
    local wantScope = (Compat.NormalizeWorldScope and Compat.NormalizeWorldScope(worldScope))
        or ((ns.db and ns.db.settings and Compat.NormalizeWorldScope and Compat.NormalizeWorldScope(ns.db.settings.altsWorldScope)))
        or ((worldScope == "all") and "all" or "pool")
    local wantFac = factionFilter
    if wantFac == nil then
        wantFac = Compat.PlayerFaction and Compat.PlayerFaction() or "ALL"
    end
    local sig = tostring(self._recipeSeq or 0) .. "|" .. tostring(wantScope) .. "|" .. tostring(wantFac)
    if self._recipeIndexCache and self._recipeIndexSig == sig then
        return self._recipeIndexCache
    end

    local byItemID = {}
    local bySpellID = {}
    local byFoldedName = {}
    local byProfCode = {}
    local altProfs = {}
    local totalCount = 0
    local uniqueKeys = {}

    local alts = (ns.Store and ns.Store.GetAltsList) and ns.Store:GetAltsList(wantScope) or {}
    for _, alt in ipairs(alts) do
        local sameFac = (wantFac == "ALL") or (not wantFac) or (not alt.faction) or (alt.faction == wantFac)
        if type(alt) == "table" and sameFac then
            local disp = alt.fullName or alt.name or alt.key or "?"
            local profMap = {}
            if type(alt.professions) == "table" then
                for _, ap in ipairs(alt.professions) do
                    if type(ap) == "table" and ap.name and ap.name ~= "" then
                        local pc = NormalizeTradeProfCode(ap.name)
                        profMap[pc] = {
                            profCode = pc,
                            profName = ap.name,
                            rank = tonumber(ap.rank) or 0,
                            maxRank = tonumber(ap.maxRank) or 0,
                            hasScanned = false,
                        }
                    end
                end
            end
            if type(alt.recipes) == "table" then
                for profCode, rBucket in pairs(alt.recipes) do
                    local keysStr = type(rBucket) == "table" and rBucket.keys or (type(rBucket) == "string" and rBucket or nil)
                    local pn = (type(rBucket) == "table" and rBucket.pn) or profCode
                    if not profMap[profCode] then
                        profMap[profCode] = {
                            profCode = profCode,
                            profName = pn,
                            rank = (type(rBucket) == "table" and tonumber(rBucket.rank)) or 0,
                            maxRank = 0,
                            hasScanned = true,
                        }
                    else
                        profMap[profCode].hasScanned = true
                        if type(rBucket) == "table" and (tonumber(rBucket.rank) or 0) > 0 then
                            profMap[profCode].rank = tonumber(rBucket.rank)
                        end
                    end
                    if type(keysStr) == "string" and keysStr ~= "" then
                        for rKey in keysStr:gmatch("[^,]+") do
                            local raw = ns.db and ns.db.recipeCatalog and ns.db.recipeCatalog[rKey]
                            local obj = raw and ParseRecipeCatalogRaw(rKey, raw)
                            if obj then
                                totalCount = totalCount + 1
                                uniqueKeys[rKey] = true
                                local entry = {
                                    altKey = alt.key,
                                    displayName = disp,
                                    classFile = alt.classFile,
                                    faction = alt.faction,
                                    worldType = alt.worldType,
                                    profCode = obj.profCode or profCode,
                                    profName = (obj.profDisp ~= "" and obj.profDisp) or pn,
                                    rKey = rKey,
                                    recipeName = obj.name,
                                    itemID = obj.itemID,
                                    spellID = obj.spellID,
                                    quality = obj.quality,
                                    icon = obj.icon,
                                    reagentsStr = obj.reagentsStr,
                                }
                                if entry.itemID and entry.itemID > 0 then
                                    byItemID[entry.itemID] = byItemID[entry.itemID] or {}
                                    byItemID[entry.itemID][#byItemID[entry.itemID] + 1] = entry
                                end
                                if entry.spellID and entry.spellID > 0 then
                                    bySpellID[entry.spellID] = bySpellID[entry.spellID] or {}
                                    bySpellID[entry.spellID][#bySpellID[entry.spellID] + 1] = entry
                                end
                                local fName = NormalizeRecipeLookupName(FoldRecipeText(entry.recipeName))
                                if fName ~= "" then
                                    byFoldedName[fName] = byFoldedName[fName] or {}
                                    byFoldedName[fName][#byFoldedName[fName] + 1] = entry
                                end
                                byProfCode[entry.profCode] = byProfCode[entry.profCode] or {}
                                byProfCode[entry.profCode][#byProfCode[entry.profCode] + 1] = entry
                            end
                        end
                    end
                end
            end
            altProfs[alt.key] = {
                altKey = alt.key,
                displayName = disp,
                classFile = alt.classFile,
                profs = profMap,
            }
        end
    end

    for _, list in pairs(byItemID) do
        if #list > 1 then table.sort(list, CompareRecipeAltEntries) end
    end
    for _, list in pairs(byFoldedName) do
        if #list > 1 then table.sort(list, CompareRecipeAltEntries) end
    end

    local uniqueCount = 0
    for _ in pairs(uniqueKeys) do uniqueCount = uniqueCount + 1 end

    local idx = {
        byItemID = byItemID,
        bySpellID = bySpellID,
        byFoldedName = byFoldedName,
        byProfCode = byProfCode,
        altProfs = altProfs,
        totalInstances = totalCount,
        uniqueCount = uniqueCount,
    }
    self._recipeIndexCache = idx
    self._recipeIndexSig = sig
    return idx
end

function Alts:GetRecipeSummaryStats()
    local curKey = CurrentAltKey()
    local curRec = curKey and ns.db and ns.db.alts and ns.db.alts[curKey]
    local myCount = 0
    if curRec and type(curRec.recipes) == "table" then
        for _, bucket in pairs(curRec.recipes) do
            if type(bucket) == "table" then
                myCount = myCount + (tonumber(bucket.cnt) or 0)
            end
        end
    end
    local idx = self:GetRecipeIndex()
    local altCnt = 0
    for _, ap in pairs(idx.altProfs or {}) do
        for _, pInfo in pairs(ap.profs or {}) do
            if pInfo.hasScanned then
                altCnt = altCnt + 1
                break
            end
        end
    end
    return myCount, (idx.uniqueCount or 0), altCnt
end

function Alts:GetRecipeCrafters(itemID, itemName, worldScope)
    local idx = self:GetRecipeIndex(worldScope)
    local list = (itemID and itemID > 0 and idx.byItemID[itemID]) or nil
    if (not list or #list == 0) and type(itemName) == "string" and itemName ~= "" then
        local fName = NormalizeRecipeLookupName(FoldRecipeText(itemName))
        list = idx.byFoldedName[fName]
    end
    return list or {}
end

function Alts:MatchRecipeScrollItem(itemID, itemName, subClassID, worldScope)
    if type(itemName) ~= "string" or itemName == "" then
        return nil, nil
    end
    local cleanTitle = Compat.Trim and Compat.Trim(itemName) or itemName
    local afterColon = cleanTitle:match("^[^:]+:%s*(.+)$") or cleanTitle
    local fTarget = NormalizeRecipeLookupName(FoldRecipeText(afterColon))
    if fTarget == "" then return nil, nil end

    local targetProf = subClassID and RECIPE_SUBCLASS_TO_PROF[subClassID] or nil
    local idx = self:GetRecipeIndex(worldScope)
    local rawMatches = idx.byFoldedName[fTarget] or {}
    local knownBy, knownSet = {}, {}
    for _, m in ipairs(rawMatches) do
        if (not targetProf or m.profCode == targetProf or m.profCode == "OTHER") and not knownSet[m.altKey] then
            knownSet[m.altKey] = true
            knownBy[#knownBy + 1] = m
        end
    end

    local missingOn = {}
    if targetProf then
        for aKey, aData in pairs(idx.altProfs or {}) do
            local pInfo = aData.profs and aData.profs[targetProf]
            if pInfo and not knownSet[aKey] then
                missingOn[#missingOn + 1] = {
                    altKey = aKey,
                    displayName = aData.displayName,
                    classFile = aData.classFile,
                    profName = pInfo.profName,
                    rank = pInfo.rank or 0,
                    maxRank = pInfo.maxRank or 0,
                    confirmedMissing = (pInfo.hasScanned == true),
                }
            end
        end
        table.sort(missingOn, CompareRecipeAltEntries)
    end
    if #knownBy == 0 and #missingOn == 0 then
        return nil, nil
    end
    return knownBy, missingOn
end

function Alts:MatchMyRecipesForQuery(itemID, queryText, maxCount)
    local curKey = CurrentAltKey()
    local curRec = curKey and ns.db and ns.db.alts and ns.db.alts[curKey]
    if not (curRec and type(curRec.recipes) == "table") then
        return {}
    end
    local cap = math.max(1, math.min(8, tonumber(maxCount) or 4))
    local numId = tonumber(itemID)
    local fQuery = (type(queryText) == "string" and queryText ~= "") and FoldRecipeText(queryText) or ""
    if (not numId or numId <= 0) and fQuery == "" then
        return {}
    end
    local out = {}
    for profCode, bucket in pairs(curRec.recipes) do
        local keysStr = type(bucket) == "table" and bucket.keys or (type(bucket) == "string" and bucket or nil)
        if type(keysStr) == "string" and keysStr ~= "" then
            for rKey in keysStr:gmatch("[^,]+") do
                local raw = ns.db and ns.db.recipeCatalog and ns.db.recipeCatalog[rKey]
                local obj = raw and ParseRecipeCatalogRaw(rKey, raw)
                if obj then
                    local hit = false
                    if numId and numId > 0 and obj.itemID == numId then
                        hit = true
                    elseif fQuery ~= "" and FoldRecipeText(obj.name):find(fQuery, 1, true) then
                        hit = true
                    end
                    if hit then
                        out[#out + 1] = {
                            rKey = rKey,
                            name = obj.name,
                            itemID = obj.itemID,
                            spellID = obj.spellID,
                            profCode = obj.profCode or profCode,
                            profDisp = obj.profDisp,
                        }
                        if #out >= cap then
                            return out
                        end
                    end
                end
            end
        end
    end
    return out
end

function Alts:SearchAllRecipes(queryText, onlyAltKey, factionFilter, worldScope)
    local qFold = FoldRecipeText(queryText or "")
    local alts = (ns.Store and ns.Store.GetAltsList) and ns.Store:GetAltsList(worldScope) or {}
    local curKey = CurrentAltKey()
    local wantFac = factionFilter
    if wantFac == nil then
        wantFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    elseif wantFac == "ALL" then
        wantFac = nil
    end

    local groups = {}
    for _, alt in ipairs(alts) do
        local sameFac = (not wantFac) or (not alt.faction) or (alt.faction == wantFac)
        if type(alt) == "table" and sameFac and (not onlyAltKey or alt.key == onlyAltKey) and type(alt.recipes) == "table" then
            local matched = {}
            local seenKeys = {}
            for profCode, bucket in pairs(alt.recipes) do
                local keysStr = type(bucket) == "table" and bucket.keys or (type(bucket) == "string" and bucket or nil)
                local pn = (type(bucket) == "table" and bucket.pn) or profCode
                if type(keysStr) == "string" and keysStr ~= "" then
                    for rKey in keysStr:gmatch("[^,]+") do
                        if not seenKeys[rKey] then
                            seenKeys[rKey] = true
                            local raw = ns.db and ns.db.recipeCatalog and ns.db.recipeCatalog[rKey]
                            local obj = raw and ParseRecipeCatalogRaw(rKey, raw)
                            if obj then
                                local profLabel = (obj.profDisp ~= "" and obj.profDisp) or pn or profCode
                                local reagTxt = FormatReagentsSummary(obj.reagentsStr)
                                local pass = (qFold == "")
                                    or FoldRecipeText(obj.name):find(qFold, 1, true)
                                    or FoldRecipeText(profLabel):find(qFold, 1, true)
                                    or (reagTxt and FoldRecipeText(reagTxt):find(qFold, 1, true))
                                if pass then
                                    local link = obj.itemID and BuildDisplayHyperlink(obj.itemID, nil, obj.name, obj.quality) or nil
                                    local ic = obj.icon
                                    if not ic and obj.itemID and C_Item and C_Item.GetItemIconByID then
                                        local okIc, idIc = pcall(C_Item.GetItemIconByID, obj.itemID)
                                        if okIc and Safe.Value(idIc) then ic = Safe.Value(idIc) end
                                    end
                                    matched[#matched + 1] = {
                                        itemID = obj.itemID,
                                        spellID = obj.spellID,
                                        link = link,
                                        name = obj.name,
                                        icon = ic or "Interface\\Icons\\INV_Misc_Note_01",
                                        quality = obj.quality or 1,
                                        count = 1,
                                        _isRecipe = true,
                                        _recipeKey = rKey,
                                        _profCode = profCode,
                                        _profName = profLabel,
                                        _reagentsSummary = reagTxt,
                                        _locLabel = profLabel,
                                    }
                                end
                            end
                        end
                    end
                end
            end
            if #matched > 0 then
                table.sort(matched, function(a, b)
                    if (a._profName or "") ~= (b._profName or "") then
                        return (a._profName or "") < (b._profName or "")
                    end
                    return (a.name or "") < (b.name or "")
                end)
                groups[#groups + 1] = {
                    altKey = alt.key,
                    displayName = alt.fullName or alt.name or alt.key or "?",
                    classFile = alt.classFile,
                    faction = alt.faction,
                    worldType = alt.worldType,
                    realmName = alt.realmName,
                    realmPool = alt.realmPool,
                    isCurrent = (alt.key == curKey),
                    items = matched,
                }
            end
        end
    end
    return groups
end

function Alts:ScanLearnedRecipes(isCraftFrame)
    if ns.db and ns.db.settings and ns.db.settings.embedProfessionWindow == false then
        return false
    end
    local key = CurrentAltKey()
    local rec = key and ns.db and ns.db.alts and ns.db.alts[key]
    if type(rec) ~= "table" then return false end

    local profName, profRank, profMax = nil, 0, 0
    local capturedKeys = {}
    local seenNew = {}
    local isPartialScan = false

    local function PushRecipe(rKey)
        if rKey and not seenNew[rKey] then
            seenNew[rKey] = true
            capturedKeys[#capturedKeys + 1] = rKey
        end
    end

    if (not isCraftFrame) and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo then
        if C_TradeSkillUI.GetChildProfessionInfo then
            local okP, pInfo = pcall(C_TradeSkillUI.GetChildProfessionInfo)
            if okP and type(pInfo) == "table" then
                profName = Safe.String(pInfo.professionName)
                profRank = Safe.Number(pInfo.skillLevel) or 0
                profMax = Safe.Number(pInfo.maxSkillLevel) or 0
            end
        end
        if (not profName or profName == "") and GetTradeSkillLine then
            local p1, p2, p3 = Safe.Call(GetTradeSkillLine)
            profName = Safe.String(p1)
            profRank = Safe.Number(p2) or profRank
            profMax = Safe.Number(p3) or profMax
        end
        local profCode = NormalizeTradeProfCode(profName or "")
        local okIds, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
        if okIds and type(ids) == "table" and profName and profName ~= "" and profName ~= "UNKNOWN" then
            for i = 1, math.min(#ids, 900) do
                local rid = ids[i]
                local okInfo, rInfo = pcall(C_TradeSkillUI.GetRecipeInfo, rid)
                if okInfo and type(rInfo) == "table" and rInfo.learned == true then
                    local rName = Safe.String(rInfo.name)
                    if rName and rName ~= "" then
                        local outItemID, icon, qual = nil, Safe.Value(rInfo.icon), 1
                        local reagentsParts = {}
                        if C_TradeSkillUI.GetRecipeSchematic then
                            local okS, schem = pcall(C_TradeSkillUI.GetRecipeSchematic, rid, false)
                            if okS and type(schem) == "table" then
                                outItemID = Safe.Number(schem.outputItemID)
                                icon = icon or Safe.Value(schem.icon)
                                if type(schem.reagentSlotSchematics) == "table" then
                                    for rs = 1, math.min(#schem.reagentSlotSchematics, 6) do
                                        local slot = schem.reagentSlotSchematics[rs]
                                        local rFirst = slot and type(slot.reagents) == "table" and slot.reagents[1]
                                        local reagId = rFirst and Safe.Number(rFirst.itemID)
                                        local qty = slot and Safe.Number(slot.quantityRequired) or 1
                                        if reagId and reagId > 0 then
                                            CatalogUpsert(reagId)
                                            reagentsParts[#reagentsParts + 1] = tostring(reagId) .. ":" .. tostring(math.max(1, qty))
                                        end
                                    end
                                end
                            end
                        end
                        if (not outItemID or outItemID <= 0) and C_TradeSkillUI.GetRecipeItemLink then
                            local okL, rLink = pcall(C_TradeSkillUI.GetRecipeItemLink, rid)
                            local cleanL = okL and Safe.String(rLink) or nil
                            outItemID = cleanL and tonumber(cleanL:match("item:(%d+)")) or outItemID
                        end
                        if outItemID and outItemID > 0 then
                            local _, _, cIc, cQl = CatalogUpsert(outItemID, nil, rName, icon, nil)
                            icon = icon or cIc
                            qual = cQl or 1
                        end
                        local spId = Safe.Number(rInfo.recipeID) or Safe.Number(rid)
                        local rKey = (outItemID and outItemID > 0 and ("i:" .. outItemID))
                            or (spId and spId > 0 and ("s:" .. spId))
                            or ("n:" .. FoldRecipeText(rName):sub(1, 38))
                        PushRecipe(RecipeCatalogUpsert(rKey, rName, profCode, profName, outItemID, spId, qual, icon, table.concat(reagentsParts, ",")))
                    end
                end
            end
        end
    end

    if (not isCraftFrame) and #capturedKeys == 0 and GetNumTradeSkills and GetTradeSkillInfo then
        local p1, p2, p3 = Safe.Call(GetTradeSkillLine)
        profName = Safe.String(p1)
        profRank = Safe.Number(p2) or 0
        profMax = Safe.Number(p3) or 0
        local profCode = NormalizeTradeProfCode(profName or "")
        if GetTradeSkillItemNameFilter then
            local nf = Safe.String(Safe.Call(GetTradeSkillItemNameFilter))
            if nf and nf ~= "" then isPartialScan = true end
        end
        if profName and profName ~= "" and profName ~= "UNKNOWN" then
            local numSkills = Safe.Number(Safe.Call(GetNumTradeSkills)) or 0
            for i = 1, math.min(numSkills, 900) do
                local okI, sName, sType, _, isExpanded = pcall(GetTradeSkillInfo, i)
                if okI then
                    if sType == "header" or sType == "subheader" then
                        if not isExpanded then isPartialScan = true end
                    else
                        sName = Safe.String(sName)
                        if sName and sName ~= "" then
                            local outLink = GetTradeSkillItemLink and Safe.String(Safe.Call(GetTradeSkillItemLink, i)) or nil
                            local recLink = GetTradeSkillRecipeLink and Safe.String(Safe.Call(GetTradeSkillRecipeLink, i)) or nil
                            local outItemID = outLink and tonumber(outLink:match("item:(%d+)")) or nil
                            local spId = recLink and (tonumber(recLink:match("enchant:(%d+)")) or tonumber(recLink:match("spell:(%d+)"))) or nil
                            local icon = GetTradeSkillIcon and Safe.Value(Safe.Call(GetTradeSkillIcon, i)) or nil
                            local qual = 1
                            if outItemID and outItemID > 0 then
                                local _, _, cIc, cQl = CatalogUpsert(outItemID, outLink, sName, icon, nil)
                                icon = icon or cIc
                                qual = cQl or 1
                            end
                            local reagentsParts = {}
                            if GetTradeSkillNumReagents and GetTradeSkillReagentItemLink then
                                local numR = Safe.Number(Safe.Call(GetTradeSkillNumReagents, i)) or 0
                                for rIdx = 1, math.min(numR, 6) do
                                    local rl = Safe.String(Safe.Call(GetTradeSkillReagentItemLink, i, rIdx))
                                    local rId = rl and tonumber(rl:match("item:(%d+)")) or nil
                                    local _, _, qty = GetTradeSkillReagentInfo and Safe.Call(GetTradeSkillReagentInfo, i, rIdx)
                                    qty = Safe.Number(qty) or 1
                                    if rId and rId > 0 then
                                        CatalogUpsert(rId, rl)
                                        reagentsParts[#reagentsParts + 1] = tostring(rId) .. ":" .. tostring(math.max(1, qty))
                                    end
                                end
                            end
                            local rKey = (outItemID and outItemID > 0 and ("i:" .. outItemID))
                                or (spId and spId > 0 and ("s:" .. spId))
                                or ("n:" .. FoldRecipeText(sName):sub(1, 38))
                            PushRecipe(RecipeCatalogUpsert(rKey, sName, profCode, profName, outItemID, spId, qual, icon, table.concat(reagentsParts, ",")))
                        end
                    end
                end
            end
        end
    end

    if isCraftFrame and GetNumCrafts and GetCraftInfo then
        local cLine, cRank, cMax = GetCraftDisplaySkillLine and Safe.Call(GetCraftDisplaySkillLine)
        profName = Safe.String(cLine) or profName
        profRank = Safe.Number(cRank) or profRank
        profMax = Safe.Number(cMax) or profMax
        local profCode = NormalizeTradeProfCode(profName or "ENCHANTING")
        if profName and profName ~= "" and profName ~= "UNKNOWN" then
            local numCrafts = Safe.Number(Safe.Call(GetNumCrafts)) or 0
            for i = 1, math.min(numCrafts, 700) do
                local okC, cName, _, cType = pcall(GetCraftInfo, i)
                if okC and cType ~= "header" then
                    cName = Safe.String(cName)
                    if cName and cName ~= "" then
                        local outLink = GetCraftItemLink and Safe.String(Safe.Call(GetCraftItemLink, i)) or nil
                        local recLink = GetCraftRecipeLink and Safe.String(Safe.Call(GetCraftRecipeLink, i)) or nil
                        local outItemID = outLink and tonumber(outLink:match("item:(%d+)")) or nil
                        local spId = recLink and (tonumber(recLink:match("enchant:(%d+)")) or tonumber(recLink:match("spell:(%d+)"))) or nil
                        local icon = GetCraftIcon and Safe.Value(Safe.Call(GetCraftIcon, i)) or nil
                        local qual = 1
                        if outItemID and outItemID > 0 then
                            local _, _, cIc, cQl = CatalogUpsert(outItemID, outLink, cName, icon, nil)
                            icon = icon or cIc
                            qual = cQl or 1
                        end
                        local reagentsParts = {}
                        if GetCraftNumReagents and GetCraftReagentItemLink then
                            local numR = Safe.Number(Safe.Call(GetCraftNumReagents, i)) or 0
                            for rIdx = 1, math.min(numR, 6) do
                                local rl = Safe.String(Safe.Call(GetCraftReagentItemLink, i, rIdx))
                                local rId = rl and tonumber(rl:match("item:(%d+)")) or nil
                                local _, _, qty = GetCraftReagentInfo and Safe.Call(GetCraftReagentInfo, i, rIdx)
                                qty = Safe.Number(qty) or 1
                                if rId and rId > 0 then
                                    CatalogUpsert(rId, rl)
                                    reagentsParts[#reagentsParts + 1] = tostring(rId) .. ":" .. tostring(math.max(1, qty))
                                end
                            end
                        end
                        local rKey = (outItemID and outItemID > 0 and ("i:" .. outItemID))
                            or (spId and spId > 0 and ("s:" .. spId))
                            or ("n:" .. FoldRecipeText(cName):sub(1, 38))
                        PushRecipe(RecipeCatalogUpsert(rKey, cName, profCode, profName, outItemID, spId, qual, icon, table.concat(reagentsParts, ",")))
                    end
                end
            end
        end
    end

    if not profName or profName == "" or profName == "UNKNOWN" or #capturedKeys == 0 then
        return false
    end

    local profCode = NormalizeTradeProfCode(profName)
    rec.recipes = rec.recipes or {}
    local prevBucket = rec.recipes[profCode]
    local prevStr = type(prevBucket) == "table" and prevBucket.keys or ""
    if isPartialScan and prevStr ~= "" then
        for oldKey in prevStr:gmatch("[^,]+") do
            PushRecipe(oldKey)
        end
    end

    table.sort(capturedKeys)
    local joined = table.concat(capturedKeys, ",")
    local changed = (prevStr ~= joined)
    rec.recipes[profCode] = {
        pn = profName,
        rank = profRank or 0,
        maxRank = profMax or 0,
        keys = joined,
        cnt = #capturedKeys,
        updatedAt = time(),
    }
    if changed then
        self._recipeSeq = (self._recipeSeq or 0) + 1
        self._recipeIndexCache = nil
        ns:Emit("ALTS_UPDATED")
    end
    return true
end

function Alts:ScanTradeSkillCooldowns()
    if ns.db and ns.db.settings and ns.db.settings.embedCharacterWindow == false then return end
    local key = CurrentAltKey()
    local rec = key and ns.db and ns.db.alts and ns.db.alts[key]
    if type(rec) ~= "table" then return end

    local now = time()
    local profName
    local foundMap = {}
    local sharedBuckets = {}

    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeCooldown then
        if C_TradeSkillUI.GetChildProfessionInfo then
            local okP, pInfo = pcall(C_TradeSkillUI.GetChildProfessionInfo)
            if okP and type(pInfo) == "table" then
                profName = Safe.String(pInfo.professionName)
            end
        end
        if not profName and GetTradeSkillLine then
            profName = Safe.String(Safe.Call(GetTradeSkillLine))
        end
        local okIds, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
        if okIds and type(ids) == "table" then
            for i = 1, math.min(#ids, 600) do
                local rid = ids[i]
                local okCd, rem = pcall(C_TradeSkillUI.GetRecipeCooldown, rid)
                rem = okCd and Safe.Number(rem) or nil
                if rem and rem > 60 then
                    local okInfo, rInfo = C_TradeSkillUI.GetRecipeInfo and pcall(C_TradeSkillUI.GetRecipeInfo, rid)
                    local rName = (okInfo and type(rInfo) == "table") and Safe.String(rInfo.name) or nil
                    if rName and rName ~= "" then
                        local readyAt = now + math.floor(rem + 0.5)
                        local bucket = (profName or "Trade") .. ":" .. tostring(math.floor(readyAt / 15))
                        sharedBuckets[bucket] = (sharedBuckets[bucket] or 0) + 1
                        if not foundMap[bucket] then
                            foundMap[bucket] = { name = rName, prof = profName or "", readyAt = readyAt, count = 1 }
                        else
                            foundMap[bucket].count = sharedBuckets[bucket]
                            local low = rName:lower()
                            if low:find("transmut", 1, true) then
                                foundMap[bucket].isTransmute = true
                            end
                        end
                    end
                end
            end
        end
    end

    if next(foundMap) == nil and GetNumTradeSkills and GetTradeSkillInfo and GetTradeSkillCooldown then
        if not profName and GetTradeSkillLine then
            profName = Safe.String(Safe.Call(GetTradeSkillLine))
        end
        local numSkills = Safe.Number(Safe.Call(GetNumTradeSkills)) or 0
        for i = 1, math.min(numSkills, 600) do
            local okI, sName, sType = pcall(GetTradeSkillInfo, i)
            if okI and sType ~= "header" then
                sName = Safe.String(sName)
                local okCd, rem = pcall(GetTradeSkillCooldown, i)
                rem = okCd and Safe.Number(rem) or nil
                if sName and sName ~= "" and rem and rem > 60 then
                    local readyAt = now + math.floor(rem + 0.5)
                    local bucket = (profName or "Trade") .. ":" .. tostring(math.floor(readyAt / 15))
                    sharedBuckets[bucket] = (sharedBuckets[bucket] or 0) + 1
                    if not foundMap[bucket] then
                        foundMap[bucket] = { name = sName, prof = profName or "", readyAt = readyAt, count = 1 }
                    else
                        foundMap[bucket].count = sharedBuckets[bucket]
                        if sName:lower():find("transmut", 1, true) then
                            foundMap[bucket].isTransmute = true
                        end
                    end
                end
            end
        end
    end

    if not profName or profName == "" or profName == "UNKNOWN" then
        return
    end

    local nextList = {}
    if type(rec.craftCooldowns) == "table" then
        for _, oldCd in ipairs(rec.craftCooldowns) do
            if type(oldCd) == "table" and oldCd.prof ~= profName and (now - (tonumber(oldCd.readyAt) or 0)) <= (7 * 86400) then
                nextList[#nextList + 1] = oldCd
            end
        end
    end
    for _, item in pairs(foundMap) do
        local label = item.name
        if (item.count or 1) > 1 and item.isTransmute then
            label = L["Transmutation"]
        elseif (item.count or 1) > 2 then
            label = string.format("%s (+%d)", item.name, item.count - 1)
        end
        nextList[#nextList + 1] = {
            name = label,
            prof = profName,
            readyAt = item.readyAt,
        }
    end
    while #nextList > 12 do
        table.remove(nextList)
    end
    rec.craftCooldowns = (#nextList > 0) and nextList or nil
    if ns.UI and ns.UI.IsAltsVisible and ns.UI:IsAltsVisible() then
        ns:Emit("ALTS_UPDATED")
    end
end

function Alts:GetClassSuppliesSummary(altData)
    if type(altData) ~= "table" or type(altData.bags) ~= "table" then
        return nil
    end
    local cls = altData.classFile
    local counts = {}
    local labels = {}
    local ammoTotal = 0
    local wantMap = cls and CLASS_REAGENT_ITEMS[cls] or nil
    if cls ~= "HUNTER" and not wantMap then
        return nil
    end
    for _, entry in ipairs(altData.bags) do
        local id, cnt, _, name, _, _, classID = self:ParseItemRaw(entry)
        if id then
            if cls == "HUNTER" and tonumber(classID) == 6 then
                ammoTotal = ammoTotal + (cnt or 1)
            elseif wantMap and wantMap[id] then
                counts[id] = (counts[id] or 0) + (cnt or 1)
                if not labels[id] then
                    labels[id] = (name and name ~= "") and name or L[wantMap[id]]
                end
            end
        end
    end
    local parts = {}
    if ammoTotal > 0 then
        parts[#parts + 1] = string.format("%s: %d", L["Ammo"], ammoTotal)
    end
    for id, qty in pairs(counts) do
        parts[#parts + 1] = string.format("%s: %d", labels[id] or "?", qty)
    end
    if #parts == 0 then return nil end
    table.sort(parts)
    return table.concat(parts, " · ")
end

function Alts:CompactSavedAlts()
    if not (ns.db and ns.db.alts) then return end
    ns.db.itemCatalog = ns.db.itemCatalog or {}
    local usedIds = {}
    local anyChanged = false
    for _, alt in pairs(ns.db.alts) do
        if type(alt) == "table" then
            if type(alt.equipment) == "table" then
                for slotId, item in pairs(alt.equipment) do
                    local packed = PackRawItem(item)
                    if packed ~= item then
                        alt.equipment[slotId] = packed
                        anyChanged = true
                    end
                    local id = self:ParseItemRaw(alt.equipment[slotId])
                    if id then usedIds[id] = true end
                end
            end
            for _, field in ipairs({ "bags", "bank" }) do
                local list = alt[field]
                if type(list) == "table" then
                    local needsPack = false
                    for _, item in ipairs(list) do
                        if type(item) == "table" then
                            needsPack = true
                            break
                        end
                    end
                    if needsPack then
                        local packed = PackContainerList(list)
                        alt[field] = packed
                        anyChanged = true
                    end
                    for _, item in ipairs(alt[field]) do
                        local id = self:ParseItemRaw(item)
                        if id then usedIds[id] = true end
                    end
                end
            end
        end
    end
    if type(ns.db.recipeCatalog) == "table" then
        local usedRecipeKeys = {}
        for _, alt in pairs(ns.db.alts) do
            if type(alt) == "table" and type(alt.recipes) == "table" then
                for _, bucket in pairs(alt.recipes) do
                    local kStr = type(bucket) == "table" and bucket.keys or (type(bucket) == "string" and bucket or nil)
                    if type(kStr) == "string" and kStr ~= "" then
                        for rk in kStr:gmatch("[^,]+") do
                            usedRecipeKeys[rk] = true
                        end
                    end
                end
            end
        end
        for rk, rRaw in pairs(ns.db.recipeCatalog) do
            if not usedRecipeKeys[rk] then
                ns.db.recipeCatalog[rk] = nil
                recipeCatalogCache[rk] = nil
            else
                local rObj = ParseRecipeCatalogRaw(rk, rRaw)
                if rObj then
                    if rObj.itemID and rObj.itemID > 0 then usedIds[rObj.itemID] = true end
                    if type(rObj.reagentsStr) == "string" and rObj.reagentsStr ~= "" then
                        for ridStr in rObj.reagentsStr:gmatch("(%d+):%d+") do
                            local rId = tonumber(ridStr)
                            if rId and rId > 0 then usedIds[rId] = true end
                        end
                    end
                end
            end
        end
    end
    for cid in pairs(ns.db.itemCatalog) do
        if not usedIds[cid] then
            ns.db.itemCatalog[cid] = nil
        end
    end
    if anyChanged then
        self._itemIndexBuilt = false
        self.itemIndex = nil
    end
end

local function CompareAltOwners(a, b)
    local curKey = CurrentAltKey()
    local aCur = (a.key == curKey or a.altKey == curKey)
    local bCur = (b.key == curKey or b.altKey == curKey)
    if aCur ~= bCur then return aCur end
    if a.total ~= b.total then return a.total > b.total end
    return (a.displayName or "") < (b.displayName or "")
end

function Alts:RebuildItemIndex(factionFilter, worldScope)
    local index = {}
    local scopeArg = (Compat.NormalizeWorldScope and Compat.NormalizeWorldScope(worldScope))
        or ((worldScope == "all") and "all" or "pool")
    local alts = ns.Store and ns.Store.GetAltsList and ns.Store:GetAltsList(scopeArg) or {}
    local curKey = CurrentAltKey()
    local wantFaction = factionFilter
    if wantFaction == nil then
        wantFaction = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    elseif wantFaction == "ALL" then
        wantFaction = nil
    end
    local buckets = self._altBuckets
    if type(buckets) ~= "table" or self._itemIndexBuilt == false then
        buckets = {}
        self._altBuckets = buckets
        self._itemIndexBuilt = true
    end

    local liveKeys = {}
    for _, alt in ipairs(alts) do
        local sameFac = (not wantFaction) or (not alt.faction) or (alt.faction == wantFaction)
        if sameFac then
            liveKeys[alt.key] = true
            local displayName = alt.fullName or alt.name or alt.key or "?"
            local classFile = alt.classFile
            local itemSeq = tonumber(alt._itemSeq) or 0
            local cached = buckets[alt.key]
            local perItem

            if cached
                and cached.itemSeq == itemSeq
                and cached.meta
                and cached.meta.displayName == displayName
                and cached.meta.classFile == classFile
                and cached.meta.worldType == alt.worldType
                and cached.meta.realmPool == alt.realmPool
                and (alt.key ~= curKey or itemSeq > 0)
            then
                perItem = cached.perItem
            else
                perItem = {}
                local altMeta = {
                    altKey = alt.key,
                    displayName = displayName,
                    classFile = classFile,
                    faction = alt.faction,
                    worldType = alt.worldType,
                    realmName = alt.realmName,
                    realmPool = alt.realmPool,
                }
                local metaMT = { __index = altMeta }

                local function AddBucket(list, field)
                    if type(list) ~= "table" then return end
                    for _, item in pairs(list) do
                        local itemID, qty = Alts:ParseItemRaw(item)
                        if itemID then
                            local rec = perItem[itemID]
                            if not rec then
                                rec = setmetatable({
                                    equipped = 0,
                                    bags = 0,
                                    bank = 0,
                                    total = 0,
                                }, metaMT)
                                perItem[itemID] = rec
                            end
                            local nQty = math.max(1, tonumber(qty) or 1)
                            rec[field] = rec[field] + nQty
                            rec.total = rec.total + nQty
                        end
                    end
                end

                AddBucket(alt.equipment, "equipped")
                AddBucket(alt.bags, "bags")
                AddBucket(alt.bank, "bank")

                buckets[alt.key] = {
                    itemSeq = itemSeq,
                    meta = altMeta,
                    perItem = perItem,
                }
            end

            for itemID, rec in pairs(perItem) do
                local owners = index[itemID]
                if not owners then
                    owners = {}
                    index[itemID] = owners
                end
                owners[#owners + 1] = rec
            end
        end
    end

    for k in pairs(buckets) do
        if not liveKeys[k] then
            buckets[k] = nil
        end
    end

    for _, owners in pairs(index) do
        if #owners > 1 then
            table.sort(owners, CompareAltOwners)
        end
    end

    self._itemIndexScope = scopeArg
    self._itemIndexFaction = wantFaction or "ALL"
    self.itemIndex = index
    return index
end

function Alts:GetItemOwners(itemID, factionFilter, worldScope)
    local numId = tonumber(itemID)
    if not numId or numId <= 0 then return nil end
    local wantScope = worldScope
    if wantScope == nil then
        local rawSet = ns.db and ns.db.settings and ns.db.settings.altsWorldScope
        wantScope = (Compat.NormalizeWorldScope and Compat.NormalizeWorldScope(rawSet))
            or ((rawSet == "all") and "all" or "pool")
    elseif Compat.NormalizeWorldScope then
        wantScope = Compat.NormalizeWorldScope(wantScope)
    end
    local wantFaction = factionFilter
    if wantFaction == nil then
        wantFaction = Compat.PlayerFaction and Compat.PlayerFaction() or "ALL"
    end
    local cacheFac = (wantFaction == "ALL" or not wantFaction) and "ALL" or wantFaction
    if not self.itemIndex or self._itemIndexFaction ~= cacheFac or self._itemIndexScope ~= wantScope or self._itemIndexBuilt == false then
        self:RebuildItemIndex(wantFaction, wantScope)
    end
    return self.itemIndex and self.itemIndex[numId]
end

function Alts:GetAccountItemTotal(itemID, factionFilter, worldScope)
    local owners = self:GetItemOwners(itemID, factionFilter, worldScope)
    if not owners then return 0 end
    local total = 0
    for _, o in ipairs(owners) do
        total = total + (o.total or 0)
    end
    return total
end

local function ExtractItemDisplayName(link)
    if type(link) ~= "string" then return "" end
    return link:match("%[(.-)%]") or ""
end

function Alts:ResolveItemName(item)
    if type(item) ~= "table" then return "" end
    local fromLink = ExtractItemDisplayName(item.link)
    if fromLink ~= "" then return fromLink end
    if type(item.name) == "string" and item.name ~= "" then return item.name end
    local id = tonumber(item.itemID)
    if id and id > 0 then
        local cName = CatalogLookup(id)
        if cName and cName ~= "" then return cName end
        if C_Item and C_Item.GetItemNameByID then
            local ok, iName = pcall(C_Item.GetItemNameByID, id)
            local clean = ok and Safe.String(iName) or nil
            if clean and clean ~= "" then
                return clean
            end
        end
        return "Item #" .. tostring(id)
    end
    return ""
end

function Alts:GetLockouts(altData)
    if type(altData) ~= "table" then return {} end
    local now = time()
    local curKey = CurrentAltKey()
    local raw = (altData.key == curKey) and SnapshotLockouts(altData.lockouts) or altData.lockouts
    local out = {}
    if type(raw) ~= "table" then return out end
    for _, lk in ipairs(raw) do
        if type(lk) == "table" then
            local rem
            if altData.key == curKey then
                rem = tonumber(lk.reset) or 0
            elseif (lk.expiresAt or 0) > now then
                rem = math.max(0, (lk.expiresAt or 0) - now)
            end
            if rem ~= nil and (rem > 0 or lk.locked or lk.extended) then
                out[#out + 1] = {
                    name = lk.name or "?",
                    id = lk.id or 0,
                    reset = rem,
                    locked = lk.locked == true,
                    extended = lk.extended == true,
                    isRaid = lk.isRaid == true,
                    difficultyName = lk.difficultyName or "",
                    numEncounters = lk.numEncounters or 0,
                    encounterProgress = lk.encounterProgress or 0,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        return (a.reset or 0) < (b.reset or 0)
    end)
    return out
end

function Alts:GetMailStatus(altData)
    if type(altData) ~= "table" or not altData.hasMail then
        return false, 0, 30, nil
    end
    local ageDays = 0
    if type(altData.mailSince) == "number" and altData.mailSince > 0 then
        ageDays = math.floor(math.max(0, time() - altData.mailSince) / 86400)
    end
    local remDays = math.max(0, 30 - ageDays)
    return true, ageDays, remDays, altData.mailSenders
end

--- Search items across recorded characters on the current realm pool (or all Forever worlds).
function Alts:SearchAllItems(queryText, excludeAltKey, sourceFilter, factionFilter, worldScope, opts)
    local q = Compat.Trim and Compat.Trim(queryText or "") or tostring(queryText or "")
    local qLow = q:lower()
    local src = sourceFilter or "all"
    local alts = ns.Store and ns.Store.GetAltsList and ns.Store:GetAltsList(worldScope) or {}
    local curKey = CurrentAltKey()
    local wantFaction = factionFilter
    if wantFaction == nil then
        wantFaction = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    elseif wantFaction == "ALL" then
        wantFaction = nil
    end
    local itemCat = type(opts) == "table" and opts.itemCat or "all"
    local minQuality = type(opts) == "table" and tonumber(opts.minQuality) or 0
    local groups = {}

    local function EntryMatches(entry)
        local id, cnt, rawLink, name, icon, quality, classID, subClassID, equipLoc = self:ParseItemRaw(entry)
        if not id and type(entry) ~= "table" then return false end
        if not MatchItemFilters(itemCat, minQuality, quality, classID, subClassID, equipLoc) then
            return false
        end
        if qLow ~= "" then
            local nm = (name and name ~= "") and name or (id and ("Item #" .. tostring(id)) or "")
            if not nm:lower():find(qLow, 1, true) then
                return false
            end
        end
        return true, id, cnt, rawLink, name, icon, quality, classID, subClassID, equipLoc
    end

    for _, alt in ipairs(alts) do
        local sameFac = (not wantFaction) or (not alt.faction) or (alt.faction == wantFaction)
        if type(alt) == "table" and alt.key ~= excludeAltKey and sameFac then
            local matched = {}
            if (src == "all" or src == "all_alts" or src == "equip") and type(alt.equipment) == "table" then
                for slotId = 1, EQUIP_SLOT_COUNT do
                    local entry = alt.equipment[slotId]
                    if entry then
                        local ok, id, _, rawLink, name, icon, quality, classID, subClassID, equipLoc = EntryMatches(entry)
                        if ok then
                            matched[#matched + 1] = {
                                itemID = id,
                                link = (type(rawLink) == "string" and rawLink:find("|Hitem:", 1, true)) and rawLink or BuildDisplayHyperlink(id, rawLink, name, quality),
                                name = name,
                                icon = icon,
                                quality = quality or 1,
                                count = 1,
                                classID = classID,
                                subClassID = subClassID,
                                equipLoc = equipLoc,
                                _isEquip = true,
                                _slotId = slotId,
                                _locLabel = L["Equipped"],
                            }
                        end
                    end
                end
            end
            if (src == "all" or src == "all_alts" or src == "bags") and type(alt.bags) == "table" then
                for _, entry in ipairs(alt.bags) do
                    local ok, id, cnt, rawLink, name, icon, quality, classID, subClassID, equipLoc = EntryMatches(entry)
                    if ok then
                        matched[#matched + 1] = {
                            itemID = id,
                            link = (type(rawLink) == "string" and rawLink:find("|Hitem:", 1, true)) and rawLink or BuildDisplayHyperlink(id, rawLink, name, quality),
                            name = name,
                            icon = icon,
                            quality = quality or 1,
                            count = cnt or 1,
                            classID = classID,
                            subClassID = subClassID,
                            equipLoc = equipLoc,
                            _locLabel = L["Bags"],
                        }
                    end
                end
            end
            if (src == "all" or src == "all_alts" or src == "bank") and type(alt.bank) == "table" then
                for _, entry in ipairs(alt.bank) do
                    local ok, id, cnt, rawLink, name, icon, quality, classID, subClassID, equipLoc = EntryMatches(entry)
                    if ok then
                        matched[#matched + 1] = {
                            itemID = id,
                            link = (type(rawLink) == "string" and rawLink:find("|Hitem:", 1, true)) and rawLink or BuildDisplayHyperlink(id, rawLink, name, quality),
                            name = name,
                            icon = icon,
                            quality = quality or 1,
                            count = cnt or 1,
                            classID = classID,
                            subClassID = subClassID,
                            equipLoc = equipLoc,
                            _locLabel = L["Bank"],
                        }
                    end
                end
            end
            if #matched > 0 then
                groups[#groups + 1] = {
                    altKey = alt.key,
                    displayName = alt.fullName or alt.name or alt.key or "?",
                    classFile = alt.classFile,
                    faction = alt.faction,
                    worldType = alt.worldType,
                    realmName = alt.realmName,
                    realmPool = alt.realmPool,
                    isCurrent = (alt.key == curKey),
                    items = matched,
                }
            end
        end
    end
    return groups
end

local itemTooltipRegistered = false

local function AppendAltItemTooltip(tooltip, data, isLegacyHook)
    if not tooltip or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local st = ns.db and ns.db.settings
    local showOwnCounts = not st or (st.embedCharacterWindow ~= false and st.tooltipItemAlts ~= false)
    local showRecipesTip = not st or (st.tooltipRecipeAlts ~= false)
    if not showOwnCounts and not showRecipesTip then return end

    local itemID = (type(data) == "table" and tonumber(data.id)) or nil
    local tipItemName, tipLink = nil, nil
    if tooltip.GetItem then
        local ok, gName, gLink = pcall(tooltip.GetItem, tooltip)
        if ok then
            tipItemName = Safe.String(gName)
            tipLink = Safe.String(gLink)
            if (not itemID or itemID <= 0) and tipLink then
                itemID = tonumber(tipLink:match("item:(%d+)")) or nil
            end
        end
    end
    if (not tipItemName or tipItemName == "") and tooltip.GetName then
        local tName = tooltip:GetName()
        local fs1 = tName and _G[tName .. "TextLeft1"]
        if fs1 and fs1.GetText then
            tipItemName = Safe.String(fs1:GetText())
        end
    end
    if not itemID or itemID <= 0 or tooltip._scAltItemId == itemID then
        return
    end
    if (not tipItemName or tipItemName == "") and C_Item and C_Item.GetItemNameByID then
        local okN, iN = pcall(C_Item.GetItemNameByID, itemID)
        tipItemName = okN and Safe.String(iN) or nil
    end

    local rawScope = st and st.altsWorldScope
    local worldScope = (Compat.NormalizeWorldScope and Compat.NormalizeWorldScope(rawScope))
        or ((rawScope == "all") and "all" or "pool")
    local owners = showOwnCounts and Alts:GetItemOwners(itemID, nil, worldScope) or nil

    local crafters, guildCrafters, scrollKnown, scrollMissing = nil, nil, nil, nil
    if showRecipesTip then
        local _, _, _, classID, subClassID = CatalogLookup(itemID)
        if classID == nil and GetItemInfoInstant then
            local okI, _, _, _, _, _, cId, sId = pcall(GetItemInfoInstant, tipLink or itemID)
            if okI then
                classID = Safe.Number(cId)
                subClassID = Safe.Number(sId)
            end
        end
        if classID == 9 then
            scrollKnown, scrollMissing = Alts:MatchRecipeScrollItem(itemID, tipItemName, subClassID, worldScope)
        else
            local foundAlts = Alts:GetRecipeCrafters(itemID, tipItemName, worldScope)
            if foundAlts and #foundAlts > 0 then
                crafters = foundAlts
            end
            if ns.Clan and ns.Clan.GetCachedRecipeCrafters then
                local gList = ns.Clan:GetCachedRecipeCrafters(itemID, tipItemName)
                if gList and #gList > 0 then
                    guildCrafters = gList
                end
            end
        end
    end

    local hasOwners = owners and #owners > 0
    local hasRecipesInfo = (crafters and #crafters > 0)
        or (guildCrafters and #guildCrafters > 0)
        or (scrollKnown and #scrollKnown > 0)
        or (scrollMissing and #scrollMissing > 0)

    if not hasOwners and not hasRecipesInfo then
        tooltip._scAltItemId = itemID
        return
    end

    tooltip._scAltItemId = itemID
    tooltip:AddLine(" ")

    local curPool = (worldScope ~= "pool" and Compat.RealmPool) and Compat.RealmPool(Compat.Realm()) or nil
    local curWorld = (worldScope ~= "pool" and Compat.DetectWorldType) and Compat.DetectWorldType(Compat.Realm()) or nil
    if hasOwners then
        local grandTotal = 0
        local shown = 0
        for _, o in ipairs(owners) do
            grandTotal = grandTotal + (o.total or 0)
            if shown < 8 then
                shown = shown + 1
                local hex = Compat.ClassHex(o.classFile)
                local wTag = ""
                if worldScope ~= "pool" then
                    local oWorld, oPool, oLbl
                    if Compat.GetAltWorldInfo then
                        oWorld, oPool, oLbl = Compat.GetAltWorldInfo(o)
                    else
                        oPool = o.realmName and Compat.RealmPool and Compat.RealmPool(o.realmName) or o.realmPool
                        oWorld = o.worldType or (Compat.DetectWorldType and Compat.DetectWorldType(o.realmName or o.realmPool))
                        oLbl = oWorld or o.realmName
                    end
                    if (oPool and curPool and oPool ~= curPool) or (oWorld and curWorld and oWorld ~= curWorld) then
                        local wtLabel = oLbl or "?"
                        local wtCol = (oWorld == "PvP" or oWorld == "RP-PvP") and "|cffd29922" or "|cff58a6ff"
                        wTag = " " .. wtCol .. "[" .. wtLabel .. "]|r"
                    end
                end
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
                tooltip:AddDoubleLine(hex .. (o.displayName or "?") .. "|r" .. wTag, rightTxt)
            end
        end
        if #owners > 8 then
            tooltip:AddLine("|cff9da7b5" .. L["+%d more characters..."]:format(#owners - 8) .. "|r")
        end
        if #owners > 1 or grandTotal > (owners[1].total or 0) then
            tooltip:AddDoubleLine("|cff9da7b5" .. L["Total (Account)"] .. "|r", "|cffffd24d" .. grandTotal .. "|r")
        end
    end

    if crafters and #crafters > 0 then
        local cParts = {}
        for i = 1, math.min(#crafters, 5) do
            local cr = crafters[i]
            local hex = Compat.ClassHex(cr.classFile)
            local pSuffix = (cr.profName and cr.profName ~= "") and (" (" .. cr.profName .. ")") or ""
            cParts[#cParts + 1] = hex .. (cr.displayName or "?") .. "|r|cff9da7b5" .. pSuffix .. "|r"
        end
        if #crafters > 5 then
            cParts[#cParts + 1] = "|cff9da7b5+" .. tostring(#crafters - 5) .. "|r"
        end
        tooltip:AddLine("|cff3fb950" .. L["Craftable by Alt"] .. ":|r " .. table.concat(cParts, ", "), 0.90, 0.96, 0.92, true)
    end

    if guildCrafters and #guildCrafters > 0 then
        local gParts = {}
        for i = 1, math.min(#guildCrafters, 5) do
            local gc = guildCrafters[i]
            local pSuffix = (gc.profName and gc.profName ~= "") and (" (" .. gc.profName .. ")") or ""
            gParts[#gParts + 1] = "|cff58a6ff" .. (gc.displayName or "?") .. "|r|cff9da7b5" .. pSuffix .. "|r"
        end
        if #guildCrafters > 5 then
            gParts[#gParts + 1] = "|cff9da7b5+" .. tostring(#guildCrafters - 5) .. "|r"
        end
        tooltip:AddLine("|cff58a6ff" .. L["In Guild"] .. ":|r " .. table.concat(gParts, ", "), 0.86, 0.93, 1.0, true)
    end

    if scrollKnown and #scrollKnown > 0 then
        local kParts = {}
        for i = 1, math.min(#scrollKnown, 5) do
            local kr = scrollKnown[i]
            local hex = Compat.ClassHex(kr.classFile)
            kParts[#kParts + 1] = hex .. (kr.displayName or "?") .. "|r"
        end
        tooltip:AddLine("|cff3fb950" .. L["Recipe already known by"] .. ":|r " .. table.concat(kParts, ", "), 0.72, 0.96, 0.78, true)
    end

    if scrollMissing and #scrollMissing > 0 then
        local mParts = {}
        for i = 1, math.min(#scrollMissing, 5) do
            local mr = scrollMissing[i]
            local hex = Compat.ClassHex(mr.classFile)
            local rankTxt = ((mr.rank or 0) > 0) and (" " .. tostring(mr.rank)) or ""
            local statusHint = mr.confirmedMissing
                and (" (" .. (mr.profName or "") .. rankTxt .. ")")
                or (" (" .. (mr.profName or "") .. " · " .. L["open window to verify"] .. ")")
            mParts[#mParts + 1] = hex .. (mr.displayName or "?") .. "|r|cff9da7b5" .. statusHint .. "|r"
        end
        tooltip:AddLine("|cffffd24d" .. L["Can still be learned by"] .. ":|r " .. table.concat(mParts, ", "), 1.0, 0.90, 0.55, true)
    end

    if isLegacyHook then
        pcall(tooltip.Show, tooltip)
    end
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
            AppendAltItemTooltip(tooltip, data, false)
        end)
    else
        for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tip and tip.HookScript and tip:HasScript("OnTooltipSetItem") then
                tip:HookScript("OnTooltipSetItem", function(t)
                    AppendAltItemTooltip(t, nil, true)
                end)
            end
        end
    end
end

local mailPickerBtn, mailQuickBtn

local function EnsureMailRecipientPicker()
    local mailComposeFrame = _G["SendMailFrame"]
    local recipientInput = _G["SendMailNameEditBox"]
    if not (mailComposeFrame and recipientInput) then return end
    local s = ns.db and ns.db.settings
    if s and (s.embedCharacterWindow == false or s.embedMailPicker == false) then
        if mailPickerBtn then mailPickerBtn:Hide() end
        if mailQuickBtn then mailQuickBtn:Hide() end
        return
    end
    if not mailPickerBtn and ns.Theme and ns.Theme.CreateButton then
        local btn = ns.Theme:CreateButton(mailComposeFrame, 78, 18, L["Alts"] .. " v", "default")
        btn:SetFrameLevel(math.max(10, (mailComposeFrame:GetFrameLevel() or 1) + 12))
        btn:SetPoint("BOTTOMRIGHT", recipientInput, "TOPRIGHT", -22, 3)
        btn:SetScript("OnEnter", function(selfBtn)
            if not GameTooltip then return end
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["Quick Select Alt Recipient"], 1, 0.88, 0.35, true)
            GameTooltip:AddLine(L["Pick one of your saved characters on this world & faction to fill the recipient field in 1 click."], 0.85, 0.88, 0.94, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(selfBtn)
            if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
        end)
        btn:SetScript("OnClick", function(selfBtn)
            if InCombatLockdown and InCombatLockdown() then return end
            local myKey = CurrentAltKey()
            local myFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
            local rawAlts = (ns.Store and ns.Store.GetAltsList) and ns.Store:GetAltsList("pool") or {}
            local candidates = {}
            for _, alt in ipairs(rawAlts) do
                if type(alt) == "table" and alt.key ~= myKey and (not myFac or not alt.faction or alt.faction == myFac) then
                    candidates[#candidates + 1] = alt
                end
            end
            table.sort(candidates, function(a, b)
                return (a.fullName or a.name or ""):lower() < (b.fullName or b.name or ""):lower()
            end)
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                    root:CreateTitle(L["My Alts"])
                    if #candidates == 0 then
                        root:CreateTitle("|cff8d98a6" .. L["No other saved characters on this world & faction."] .. "|r")
                        return
                    end
                    for _, alt in ipairs(candidates) do
                        local targetName = alt.fullName or alt.name or ""
                        local hex = Compat.ClassHex(alt.classFile)
                        local mailTag = alt.hasMail and (" |cffffd24d[" .. L["Mailbox"] .. "]|r") or ""
                        local lvlTxt = L["Lv %d"]:format(tonumber(alt.level) or 0)
                        local lbl = ("%s%s|r |cffc6ceda(%s)|r%s"):format(hex, targetName, lvlTxt, mailTag)
                        root:CreateButton(lbl, function()
                            if recipientInput and recipientInput.SetText and targetName ~= "" then
                                recipientInput:SetText(targetName)
                                local subjBox = _G["SendMailSubjectEditBox"]
                                if subjBox and subjBox.SetFocus then
                                    pcall(subjBox.SetFocus, subjBox)
                                elseif recipientInput.ClearFocus then
                                    pcall(recipientInput.ClearFocus, recipientInput)
                                end
                            end
                        end)
                    end
                end)
            end
        end)
        mailPickerBtn = btn
    end
    if not mailQuickBtn and mailPickerBtn and ns.Theme and ns.Theme.CreateOfficialQuickButton then
        local qBtn = ns.Theme:CreateOfficialQuickButton(mailComposeFrame, {
            name = "SocialCentralMailQuickBtn",
            size = 18,
            title = L["Official Mailbox (Alts)"],
            tooltipAnchor = "ANCHOR_TOP",
            getStatusState = function()
                local curS = ns.db and ns.db.settings
                if curS and (curS.embedCharacterWindow == false or curS.embedMailPicker == false) then
                    return "off"
                end
                return "active"
            end,
            getTooltipLines = function()
                return {
                    L["Quick Select Alt Recipient attached to Blizzard's Mailbox."],
                }
            end,
            buildMenu = function(root)
                root:CreateTitle("SocialCentral — " .. L["Official Mailbox (Alts)"])
                root:CreateButton(L["Disable in this window"], function()
                    if ns.db and ns.db.settings then
                        ns.db.settings.embedMailPicker = false
                    end
                    EnsureMailRecipientPicker()
                    ns:Emit("SETTINGS_UPDATED")
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                    ns:Print("%s", L["Disabled in this window. Re-enable anytime in Settings (/sc)."])
                end)
                root:CreateButton(L["Settings"], function()
                    if ns.Settings and ns.Settings.Open then ns.Settings:Open("overview") end
                end)
            end,
        })
        qBtn:SetFrameLevel(math.max(12, (mailComposeFrame:GetFrameLevel() or 1) + 14))
        qBtn:SetPoint("BOTTOMRIGHT", recipientInput, "TOPRIGHT", 0, 3)
        mailQuickBtn = qBtn
    end
    if mailPickerBtn then
        if ns.Theme and ns.Theme.AutoFitButton then
            ns.Theme:AutoFitButton(mailPickerBtn, 62, 12, 118)
            mailPickerBtn:SetHeight(18)
        end
        mailPickerBtn:Show()
    end
    if mailQuickBtn then
        if mailQuickBtn.RefreshTheme then mailQuickBtn:RefreshTheme() end
        mailQuickBtn:Show()
    end
end

function Alts:RemoveAlt(altKey)
    if not (ns.db and ns.db.alts and altKey) then return false end
    if altKey == CurrentAltKey() then
        ns:Print(L["Cannot remove the currently logged-in character."])
        return false
    end
    if ns.db.alts[altKey] then
        ns.db.alts[altKey] = nil
        if self._altBuckets then
            self._altBuckets[altKey] = nil
        end
        self.itemIndex = nil
        ns:Emit("ALTS_UPDATED")
        return true
    end
    return false
end

function Alts:Init()
    RegisterItemTooltipIntegration()
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        if ns.db and ns.db.settings and ns.db.settings.embedCharacterWindow == false then
            return
        end
        local curKey = CurrentAltKey()
        if ns.db and ns.db.alts and curKey and not ns.db.alts[curKey] then
            self:Snapshot(false)
        else
            self:QueueSnapshot(false, 1.5)
        end
        if not self._compactedSavedOnce and C_Timer and C_Timer.After then
            self._compactedSavedOnce = true
            C_Timer.After(2.5, function()
                Alts:CompactSavedAlts()
            end)
        end
        if RequestRaidInfo and not self._raidInfoRequested and C_Timer and C_Timer.After then
            self._raidInfoRequested = true
            C_Timer.After(3.0, function()
                pcall(RequestRaidInfo)
            end)
        end
        if not self._mailExpiryWarned and C_Timer and C_Timer.After then
            self._mailExpiryWarned = true
            C_Timer.After(6.5, function()
                local myAltKey = CurrentAltKey()
                local nowTs = time()
                local alts = ns.Store and ns.Store.GetAltsList and ns.Store:GetAltsList("all") or {}
                local curPool = Compat.RealmPool and Compat.RealmPool(Compat.Realm()) or nil
                local curWorld = Compat.DetectWorldType and Compat.DetectWorldType(Compat.Realm()) or nil
                local pendingAlts = {}
                for _, alt in ipairs(alts) do
                    if type(alt) == "table" and alt.key ~= myAltKey and alt.hasMail and alt.mailSince then
                        local ageDays = math.floor((nowTs - alt.mailSince) / 86400)
                        if ageDays >= 7 then
                            local altPool = (alt.realmName and Compat.RealmPool and Compat.RealmPool(alt.realmName)) or alt.realmPool
                            local altWorld = alt.worldType or (Compat.DetectWorldType and Compat.DetectWorldType(alt.realmName or alt.realmPool))
                            local worldSuffix = ((altPool and curPool and altPool ~= curPool) or (altWorld and curWorld and altWorld ~= curWorld))
                                and (" [" .. tostring(altWorld or alt.realmName or "?") .. "]") or ""
                            pendingAlts[#pendingAlts + 1] = ("%s%s (%dd+)"):format(alt.fullName or alt.name or "Alt", worldSuffix, ageDays)
                        end
                    end
                end
                if #pendingAlts > 0 then
                    ns:Print(string.format(L["Mail Reminder: Unclaimed mail detected earlier on: %s."], table.concat(pendingAlts, ", ")))
                end
            end)
        end
    end)

    ns.RegisterEvent(self, "MAIL_SHOW", function()
        EnsureMailRecipientPicker()
        self:QueueSnapshot(false, 0.6)
    end)

    for _, mailEvent in ipairs({
        "UPDATE_PENDING_MAIL",
        "MAIL_CLOSED",
    }) do
        ns.RegisterEvent(self, mailEvent, function()
            self:QueueSnapshot(false, 0.6)
        end)
    end

    for _, scalarEvent in ipairs({
        "PLAYER_XP_UPDATE",
        "UPDATE_EXHAUSTION",
        "PLAYER_UPDATE_RESTING",
        "PLAYER_MONEY",
        "ZONE_CHANGED_NEW_AREA",
    }) do
        ns.RegisterEvent(self, scalarEvent, function()
            self:UpdateScalars()
        end)
    end

    ns.RegisterEvent(self, "PLAYER_LEVEL_UP", function()
        self._dirtyLocks = true
        self:QueueSnapshot(false, 1.0)
    end)

    ns.RegisterEvent(self, "PLAYER_GUILD_UPDATE", function(_, _, unit)
        if not unit or unit == "player" then
            self:QueueSnapshot(false, 1.5)
        end
    end)

    ns.RegisterEvent(self, "PLAYER_EQUIPMENT_CHANGED", function(_, _, slotId)
        local sid = tonumber(slotId)
        if sid and sid >= 1 and sid <= EQUIP_SLOT_COUNT then
            self._dirtyEquipSlots = self._dirtyEquipSlots or {}
            self._dirtyEquipSlots[sid] = true
        else
            self._dirtyEquipAll = true
        end
        self:QueueSnapshot(false, 0.8)
    end)

    ns.RegisterEvent(self, "PLAYER_AVG_ITEM_LEVEL_UPDATE", function()
        self:QueueSnapshot(false, 1.0)
    end)

    ns.RegisterEvent(self, "SKILL_LINES_CHANGED", function()
        self._dirtyProfs = true
        self:QueueSnapshot(false, 1.5)
    end)

    for _, tsEvent in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE" }) do
        local isCraft = (tsEvent == "CRAFT_SHOW" or tsEvent == "CRAFT_UPDATE")
        ns.RegisterEvent(self, tsEvent, function()
            self._dirtyProfs = true
            self:QueueSnapshot(false, 1.5)
            if not self._cdScanQueued and C_Timer and C_Timer.After then
                self._cdScanQueued = true
                C_Timer.After(0.45, function()
                    Alts._cdScanQueued = false
                    Alts:ScanTradeSkillCooldowns()
                    Alts:ScanLearnedRecipes(isCraft)
                    if ns.LFGFrameTab and ns.LFGFrameTab.AttachProfessionButton then
                        ns.LFGFrameTab:AttachProfessionButton()
                    end
                end)
            else
                self:ScanTradeSkillCooldowns()
                self:ScanLearnedRecipes(isCraft)
                if ns.LFGFrameTab and ns.LFGFrameTab.AttachProfessionButton then
                    ns.LFGFrameTab:AttachProfessionButton()
                end
            end
        end)
    end

    ns.RegisterEvent(self, "BAG_UPDATE", function(_, _, bagId)
        if ns.db and ns.db.settings and ns.db.settings.embedCharacterWindow == false then
            return
        end
        self._sawBagUpdateEvent = true
        local b = tonumber(bagId)
        if b and b >= 0 and b <= 4 then
            self._dirtyBags = self._dirtyBags or {}
            self._dirtyBags[b] = true
        elseif b == nil then
            self._dirtyBagsAll = true
        end
    end)

    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function()
        if ns.db and ns.db.settings and ns.db.settings.embedCharacterWindow == false then
            return
        end
        if not self._sawBagUpdateEvent then
            self._dirtyBagsAll = true
        end
        local bankShown = (self._bankOpen == true) or (_G.BankFrame and _G.BankFrame.IsShown and _G.BankFrame:IsShown())
        self:QueueSnapshot(bankShown == true, bankShown and 0.4 or 1.5)
    end)

    ns.RegisterEvent(self, "GUILD_ROSTER_UPDATE", function()
        if mySurnameConfirmed or not (ns.db and ns.db.alts) then return end
        local key = CurrentAltKey()
        local rec = key and ns.db.alts[key]
        if type(rec) ~= "table" then return end
        if rec.userSetSurname ~= nil then rec.userSetSurname = nil end
        local resolved = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName(rec.fullName)
        if resolved and resolved.surname and resolved.fullName and resolved.fullName ~= rec.fullName then
            rec.firstName = resolved.firstName or rec.firstName
            rec.surname = resolved.surname
            rec.fullName = resolved.fullName
            mySurnameConfirmed = true
            UnregisterSurnameChatEvents()
            self.itemIndex = nil
            ns:Emit("ALTS_UPDATED")
        end
    end)

    ns.RegisterEvent(self, "UPDATE_INSTANCE_INFO", function()
        self._instanceInfoReady = true
        self._dirtyLocks = true
        self:QueueSnapshot(false, 0.8)
    end)

    ns.RegisterEvent(self, "BANKFRAME_OPENED", function()
        self._bankOpen = true
        self:QueueSnapshot(true, 0.25)
    end)

    ns.RegisterEvent(self, "BANKFRAME_CLOSED", function()
        self._bankOpen = false
    end)

    for _, bankEvent in ipairs({
        "PLAYERBANKSLOTS_CHANGED",
        "PLAYERREAGENTBANKSLOTS_CHANGED",
        "REAGENTBANK_UPDATE",
        "BANK_TABS_CHANGED",
    }) do
        ns.RegisterEvent(self, bankEvent, function()
            self:QueueSnapshot(true, 0.4)
        end)
    end

    ns.RegisterEvent(self, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, _, interactionType)
        local bankerType = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
        if bankerType and interactionType == bankerType then
            self._bankOpen = true
            self:QueueSnapshot(true, 0.35)
        end
    end)

    ns.RegisterEvent(self, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, _, interactionType)
        local bankerType = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
        if bankerType and interactionType == bankerType then
            self._bankOpen = false
        end
    end)

    local key = CurrentAltKey()
    local rec = key and ns.db and ns.db.alts and ns.db.alts[key]
    if rec and rec.surname and rec.surname ~= "" then
        mySurnameConfirmed = true
    end

    if not mySurnameConfirmed then
        surnameChatRegistered = true
        for _, chatEvent in ipairs(SURNAME_CHAT_EVENTS) do
            ns.RegisterEvent(self, chatEvent, function(_, _, text, author, ...)
                local guid = select(10, ...)
                ApplyAuthorSurname(author, guid)
            end)
        end
    end

    ns:On("SETTINGS_UPDATED", function()
        if _G["MailFrame"] and _G["MailFrame"].IsShown and _G["MailFrame"]:IsShown() then
            EnsureMailRecipientPicker()
        elseif ns.db and ns.db.settings and (ns.db.settings.embedCharacterWindow == false or ns.db.settings.embedMailPicker == false) then
            if mailPickerBtn then mailPickerBtn:Hide() end
            if mailQuickBtn then mailQuickBtn:Hide() end
        end
    end)
end
