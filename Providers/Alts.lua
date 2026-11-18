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
        return equip, true
    end
    if type(dirtySlots) ~= "table" or next(dirtySlots) == nil then
        return prevEquip, false
    end
    local out = {}
    for k, v in pairs(prevEquip) do
        out[k] = v
    end
    for slotId in pairs(dirtySlots) do
        if type(slotId) == "number" and slotId >= 1 and slotId <= EQUIP_SLOT_COUNT then
            out[slotId] = ReadEquipSlot(slotId)
        end
    end
    return out, true
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

local function SnapshotBagsIncremental(prevAlt, dirtyBags, isFull, ownerKey)
    Alts._bagContainerCache = Alts._bagContainerCache or {}
    local cacheValid = (not isFull) and Alts._bagCacheValid and (Alts._bagCacheOwner == ownerKey)
    if cacheValid and type(prevAlt) == "table" and type(prevAlt.bags) == "table" and type(dirtyBags) == "table" and next(dirtyBags) == nil then
        return prevAlt.bags, prevAlt.bagFree or 0, prevAlt.bagTotal or 0, false
    end

    local bags = {}
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
                if #bags >= MAX_CONTAINER_ITEMS then break end
                bags[#bags + 1] = bagCache.items[i]
            end
        end
    end
    Alts._bagCacheValid = true
    Alts._bagCacheOwner = ownerKey
    return bags, bagFree, bagTotal, true
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
    -- Region and ruleset come from the character's realm pool (e.g. "camwowus1realmpvp").
    local pool = tostring(altEntry.realmPool or Compat.RealmPool(Compat.Realm()) or ""):lower()
    local region = pool:match("^camwow(%a%a)%d*") or "us"
    local ruleset = pool:match("realm(%a+)$") or "pvp"
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
            bank = bItems
            bankFree = bFree
            bankTotal = bTot
            bankUpdatedAt = time()
            bankChanged = true
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
    ns.db.alts[key] = {
        name = name,
        firstName = resolved and resolved.firstName or name,
        surname = resolved and resolved.surname or nil,
        fullName = resolved and resolved.fullName or name,
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
        zone = currentZone or "",
        bindLocation = bindLocation or "",
        hearthReadyAt = hearthReadyAt,
        professions = professions,
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
        _itemSeq = nextItemSeq,
        lastActive = time(),
    }

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

local function CompareAltOwners(a, b)
    local curKey = CurrentAltKey()
    local aCur = (a.key == curKey or a.altKey == curKey)
    local bCur = (b.key == curKey or b.altKey == curKey)
    if aCur ~= bCur then return aCur end
    if a.total ~= b.total then return a.total > b.total end
    return (a.displayName or "") < (b.displayName or "")
end

function Alts:RebuildItemIndex(factionFilter)
    local index = {}
    local alts = ns.Store and ns.Store.GetAltsList and ns.Store:GetAltsList() or {}
    local curKey = CurrentAltKey()
    local wantFaction = factionFilter
    if wantFaction == nil then
        wantFaction = Compat.PlayerFaction and Compat.PlayerFaction() or nil
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
            local stamp = alt.lastActive or alt.updatedAt or 0
            local itemSeq = tonumber(alt._itemSeq) or 0
            local cached = buckets[alt.key]
            local perItem

            if cached and cached.updatedAt == stamp and cached.itemSeq == itemSeq and cached.displayName == displayName and cached.classFile == classFile and (alt.key ~= curKey or itemSeq > 0) then
                perItem = cached.perItem
            else
                perItem = {}

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

                buckets[alt.key] = {
                    updatedAt = stamp,
                    itemSeq = itemSeq,
                    displayName = displayName,
                    classFile = classFile,
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

    self._itemIndexFaction = wantFaction
    self.itemIndex = index
    return index
end

function Alts:GetItemOwners(itemID, factionFilter)
    local numId = tonumber(itemID)
    if not numId or numId <= 0 then return nil end
    local wantFaction = factionFilter
    if wantFaction == nil then
        wantFaction = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    end
    if not self.itemIndex or self._itemIndexFaction ~= wantFaction or self._itemIndexBuilt == false then
        self:RebuildItemIndex(wantFaction)
    end
    return self.itemIndex and self.itemIndex[numId]
end

function Alts:GetAccountItemTotal(itemID, factionFilter)
    local owners = self:GetItemOwners(itemID, factionFilter)
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
    if id and id > 0 and C_Item and C_Item.GetItemNameByID then
        local ok, iName = pcall(C_Item.GetItemNameByID, id)
        local clean = ok and Safe.String(iName) or nil
        if clean and clean ~= "" then
            return clean
        end
    end
    if id and id > 0 then
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

--- Search items across all recorded characters on the current realm pool.
function Alts:SearchAllItems(queryText, excludeAltKey, sourceFilter, factionFilter)
    local q = Compat.Trim and Compat.Trim(queryText or "") or tostring(queryText or "")
    local qLow = q:lower()
    local src = sourceFilter or "all"
    local alts = ns.Store and ns.Store.GetAltsList and ns.Store:GetAltsList() or {}
    local curKey = CurrentAltKey()
    local wantFaction = factionFilter
    if wantFaction == nil then
        wantFaction = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    end
    local groups = {}

    local function ItemMatches(item)
        if qLow == "" then return true end
        local iName = Alts:ResolveItemName(item):lower()
        return iName:find(qLow, 1, true) ~= nil
    end

    for _, alt in ipairs(alts) do
        local sameFac = (not wantFaction) or (not alt.faction) or (alt.faction == wantFaction)
        if type(alt) == "table" and alt.key ~= excludeAltKey and sameFac then
            local matched = {}
            if (src == "all" or src == "all_alts" or src == "equip") and type(alt.equipment) == "table" then
                for slotId = 1, EQUIP_SLOT_COUNT do
                    local entry = alt.equipment[slotId]
                    if entry and (entry.icon or entry.itemID or entry.link) and ItemMatches(entry) then
                        matched[#matched + 1] = {
                            itemID = entry.itemID,
                            link = entry.link,
                            name = entry.name,
                            icon = entry.icon,
                            quality = entry.quality,
                            count = 1,
                            _isEquip = true,
                            _slotId = slotId,
                            _locLabel = L["Equipped"],
                        }
                    end
                end
            end
            if (src == "all" or src == "all_alts" or src == "bags") and type(alt.bags) == "table" then
                for _, entry in ipairs(alt.bags) do
                    if ItemMatches(entry) then
                        matched[#matched + 1] = {
                            itemID = entry.itemID,
                            link = entry.link,
                            name = entry.name,
                            icon = entry.icon,
                            quality = entry.quality,
                            count = entry.count or 1,
                            _locLabel = L["Bags"],
                        }
                    end
                end
            end
            if (src == "all" or src == "all_alts" or src == "bank") and type(alt.bank) == "table" then
                for _, entry in ipairs(alt.bank) do
                    if ItemMatches(entry) then
                        matched[#matched + 1] = {
                            itemID = entry.itemID,
                            link = entry.link,
                            name = entry.name,
                            icon = entry.icon,
                            quality = entry.quality,
                            count = entry.count or 1,
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
                    isCurrent = (alt.key == curKey),
                    items = matched,
                }
            end
        end
    end
    return groups
end

local itemTooltipRegistered = false

local function AppendAltItemTooltip(tooltip, data)
    if not tooltip or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if ns.db and ns.db.settings and (ns.db.settings.embedCharacterWindow == false or ns.db.settings.tooltipItemAlts == false) then return end

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
                local alts = ns.Store and ns.Store.GetAltsList and ns.Store:GetAltsList() or {}
                local pendingAlts = {}
                for _, alt in ipairs(alts) do
                    if type(alt) == "table" and alt.key ~= myAltKey and alt.hasMail and alt.mailSince then
                        local ageDays = math.floor((nowTs - alt.mailSince) / 86400)
                        if ageDays >= 7 then
                            pendingAlts[#pendingAlts + 1] = ("%s (%dd+)"):format(alt.fullName or alt.name or "Alt", ageDays)
                        end
                    end
                end
                if #pendingAlts > 0 then
                    ns:Print(string.format(L["Mail Reminder: Unclaimed mail detected earlier on: %s."], table.concat(pendingAlts, ", ")))
                end
            end)
        end
    end)

    for _, mailEvent in ipairs({
        "UPDATE_PENDING_MAIL",
        "MAIL_SHOW",
        "MAIL_CLOSED",
    }) do
        ns.RegisterEvent(self, mailEvent, function()
            self:QueueSnapshot(false, 0.6)
        end)
    end

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

    for _, skillEvent in ipairs({ "SKILL_LINES_CHANGED", "TRADE_SKILL_UPDATE" }) do
        ns.RegisterEvent(self, skillEvent, function()
            self._dirtyProfs = true
            self:QueueSnapshot(false, 1.5)
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
end
