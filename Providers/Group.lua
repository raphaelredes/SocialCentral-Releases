local _, ns = ...

local L = ns.L
local Safe = ns.Safe
local Compat = ns.Compat
local Store = ns.Store

-- Tracks active Party, Raid, and Instance groups plus Recent Companions history.
-- Respects 16001 / 12.x Secret Values, InCombatLockdown(), and hardware-event rules.
local Group = {
    members = {},
    readyStates = {},
    readyStatesByGuid = {},
    readyCheckActive = false,
    memberInstanceCaps = {},
}

ns.Group = Group
table.insert(ns.modules, Group)

local scanQueued = false

function Group:GetChannelName()
    if not Compat.IsInGroup() then
        return nil
    end
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup and Safe.Value(IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) then
        return "INSTANCE_CHAT"
    end
    if Compat.IsInRaid() then
        return "RAID"
    end
    return "PARTY"
end

function Group:GetChannelSlash()
    local ch = self:GetChannelName()
    if ch == "INSTANCE_CHAT" then
        return "/i "
    elseif ch == "RAID" then
        return "/ra "
    elseif ch == "PARTY" then
        return "/p "
    end
    return nil
end

local function NormalizeRole(rawRole)
    if rawRole == "TANK" or rawRole == "HEALER" or rawRole == "DAMAGER" then
        return rawRole
    end
    return "NONE"
end

function Group:Scan()
    local nextList = {}
    local inGroup = Compat.IsInGroup()
    if not inGroup then
        self.members = {}
        self.readyCheckActive = false
        self.readyStates = {}
        self.readyStatesByGuid = {}
        self._avoidNotified = {}
        if self.OnActiveRunRosterUpdated then
            self:OnActiveRunRosterUpdated(false)
        end
        ns:Emit("GROUP_UPDATED")
        return
    end

    local inRaid = Compat.IsInRaid()
    local numMembers = Compat.GetNumGroupMembers()
    local currentZone = Compat.CurrentZoneName()

    local unitTokens = {}
    if inRaid then
        for i = 1, numMembers do
            unitTokens[#unitTokens + 1] = "raid" .. i
        end
    else
        unitTokens[#unitTokens + 1] = "player"
        for i = 1, math.max(0, numMembers - 1) do
            unitTokens[#unitTokens + 1] = "party" .. i
        end
    end

    local prevByGuid = {}
    if self.members then
        for _, m in ipairs(self.members) do
            if m.guid and m.displayName and m.displayName:find("%s") then
                prevByGuid[m.guid] = m.displayName
            end
        end
    end

    local raidMetaByIndex = {}
    local raidMetaByLookup = {}
    if inRaid and GetRaidRosterInfo then
        for rIdx = 1, numMembers do
            local okR, rName, _, rSub, _, _, _, _, _, rDead, rCombatRole, rIsML = pcall(GetRaidRosterInfo, rIdx)
            if okR and (rName or rSub) then
                local cleanRole = Safe.String(rCombatRole)
                if cleanRole ~= "MAINTANK" and cleanRole ~= "MAINASSIST" then
                    cleanRole = nil
                end
                local metaEntry = {
                    subgroup = Safe.Number(rSub) or 1,
                    isDead = (Safe.Value(rDead) == true),
                    combatRole = cleanRole,
                    isML = (Safe.Value(rIsML) == true),
                }
                raidMetaByIndex[rIdx] = metaEntry
                local cleanRName = rName and Safe.String(rName)
                local rParsed = cleanRName and Compat.ParseCharacterName(cleanRName)
                if rParsed and rParsed.lookupKey then
                    raidMetaByLookup[rParsed.lookupKey] = metaEntry
                end
            end
        end
    end

    local myInst = self:GetHourlyInstanceStatus()
    local nowCaps = time()
    local seen = {}
    for idx, unit in ipairs(unitTokens) do
        if UnitExists and Safe.Value(UnitExists(unit)) == true then
            local guid = Safe.String(Safe.Call(UnitGUID, unit))
            local existingName = guid and prevByGuid[guid] or nil
            local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(unit, guid, existingName)
            local rawName = (resolved and resolved.fullName)
                or Safe.String(Safe.Call(GetUnitName, unit, true))
                or Safe.String(Safe.Call(UnitName, unit))
            local parsed = rawName and Compat.ParseCharacterName(rawName)
            if parsed and not seen[parsed.lookupKey] then
                seen[parsed.lookupKey] = true
                if guid and Compat.CacheForeverFullName then
                    Compat.CacheForeverFullName(guid, parsed.displayName, parsed.firstName)
                end
                local _, classFile = Safe.Call(UnitClass, unit)
                classFile = Safe.String(classFile)
                local level = Safe.Number(Safe.Call(UnitLevel, unit))
                local role = NormalizeRole(Safe.String(Safe.Call(UnitGroupRolesAssigned, unit)))
                local online = not UnitIsConnected or Safe.Value(UnitIsConnected(unit)) ~= false
                local unitDead = (UnitIsDeadOrGhost and Safe.Value(Safe.Call(UnitIsDeadOrGhost, unit)) == true) or false
                local rMeta = (inRaid and raidMetaByIndex[idx]) or raidMetaByLookup[parsed.lookupKey]
                local subgroup = (rMeta and rMeta.subgroup) or 1
                local isDead = (rMeta and rMeta.isDead) or unitDead
                local raidRole = rMeta and rMeta.combatRole or nil
                local isML = (rMeta and rMeta.isML == true) or false
                local isLeader = Compat.IsGroupLeader(unit)
                local isAssistant = (not isLeader) and (Compat.IsGroupAssistant and Compat.IsGroupAssistant(unit)) or false
                local isMe = Compat.IsMe(rawName, guid)
                local capRec = (not isMe) and self.memberInstanceCaps and self.memberInstanceCaps[parsed.lookupKey]
                local instUsed = isMe and (myInst and myInst.used or 0)
                    or ((capRec and (nowCaps - (capRec.updatedAt or 0)) <= 3600) and capRec.used or nil)
                local instMax = (capRec and capRec.max) or (myInst and myInst.max) or 5
                local readyVal = (guid and self.readyStatesByGuid) and self.readyStatesByGuid[guid]
                if readyVal == nil then
                    readyVal = self.readyStates[parsed.lookupKey]
                end

                local item = {
                    unit = unit,
                    guid = guid,
                    displayName = parsed.displayName,
                    lookupKey = parsed.lookupKey,
                    classFile = classFile,
                    level = (level and level > 0) and level or nil,
                    role = role,
                    online = online,
                    isDead = isDead,
                    subgroup = subgroup,
                    raidRole = raidRole,
                    isML = isML,
                    isLeader = isLeader,
                    isAssistant = isAssistant,
                    isMe = isMe,
                    ready = readyVal,
                    zone = currentZone,
                    instanceUsed = instUsed,
                    instanceMax = instMax,
                }
                table.insert(nextList, item)

                if not isMe then
                    local s = ns.db and ns.db.settings
                    if (not s) or (s.groupAvoidAlert ~= false) then
                        self._avoidNotified = self._avoidNotified or {}
                        local alertKey = guid or parsed.lookupKey
                        if not self._avoidNotified[alertKey] then
                            local meta = Store and Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(parsed.lookupKey)
                            local ignRec = Store and Store.GetAccountIgnore and Store:GetAccountIgnore(parsed.lookupKey)
                            if (meta and meta.flag == "AVOID") or ignRec then
                                self._avoidNotified[alertKey] = true
                                local noteText
                                if ignRec then
                                    local rLbl = Store.FormatIgnoreReason and Store:FormatIgnoreReason(ignRec.reason, L) or (ignRec.reason or "")
                                    if ignRec.note and ignRec.note ~= "" then
                                        noteText = string.format("%s (%s): %s", L["Account Ignore"], rLbl, ignRec.note)
                                    else
                                        noteText = string.format("%s (%s)", L["Account Ignore"], rLbl)
                                    end
                                else
                                    noteText = (meta and meta.note and meta.note ~= "") and (L["Note: %s"]:format(meta.note)) or L["In your group! Flagged as Avoid."]
                                end
                                ns:Print("|cffff4d4d[!] %s:|r %s (%s) — %s", L["Avoid Warning"], parsed.displayName, item.role or "", noteText)
                                if PlaySound and SOUNDKIT and (SOUNDKIT.RAID_WARNING or 8959) then
                                    pcall(PlaySound, SOUNDKIT.RAID_WARNING or 8959, "Master")
                                end
                                ns:Emit("ADDON_MESSAGE_NOTIFY", {
                                    id = "avoid:" .. alertKey,
                                    kind = "AVOID_ALERT",
                                    sourceTag = L["Avoid Warning"],
                                    sender = parsed.displayName,
                                    text = noteText,
                                    ts = time(),
                                    priority = 2,
                                    totalDuration = 12.0,
                                })
                            end
                        end
                    end
                end

                local groupModOn = not (ns.db and ns.db.settings and ns.db.settings.moduleGroupEnabled == false)
                if groupModOn and not isMe and Store and Store.RecordCompanion then
                    local compKey = guid or parsed.lookupKey
                    local compSig = tostring(role or "") .. "|" .. tostring(currentZone or "") .. "|" .. tostring(item.level or 0)
                    local nowComp = GetTime and GetTime() or 0
                    local sentMap = self._companionSentAt
                    if not sentMap or (self._companionSentCount or 0) >= 250 then
                        sentMap = {}
                        self._companionSentAt = sentMap
                        self._companionSentCount = 0
                    end
                    local prevSent = compKey and sentMap[compKey]
                    if not prevSent or prevSent.sig ~= compSig or (nowComp - prevSent.at) >= 120 then
                        if compKey then
                            if not prevSent then
                                self._companionSentCount = (self._companionSentCount or 0) + 1
                            end
                            sentMap[compKey] = { at = nowComp, sig = compSig }
                        end
                        Store:RecordCompanion({
                            displayName = parsed.displayName,
                            guid = guid,
                            classFile = classFile,
                            level = item.level,
                            role = role,
                            zone = currentZone,
                        })
                    end
                end
            end
        end
    end

    local roleRank = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }
    table.sort(nextList, function(a, b)
        local aLead = (a.isLeader == true)
        local bLead = (b.isLeader == true)
        if aLead ~= bLead then return aLead end
        if (a.subgroup or 1) ~= (b.subgroup or 1) then return (a.subgroup or 1) < (b.subgroup or 1) end
        local ra, rb = roleRank[a.role] or 4, roleRank[b.role] or 4
        if ra ~= rb then return ra < rb end
        return (a.displayName or "") < (b.displayName or "")
    end)

    self.members = nextList
    self._compCache = nil
    if self.OnActiveRunRosterUpdated then
        self:OnActiveRunRosterUpdated(true)
    end
    if Compat.IsInGroup() and ns.Clan and ns.Clan.BroadcastGroupInstanceCap then
        ns.Clan:BroadcastGroupInstanceCap(myInst and myInst.used or 0, myInst and myInst.max or 5)
    end
    ns:Emit("GROUP_UPDATED")
end

function Group:ReceiveMemberInstanceCap(lookupKey, used, max)
    if type(lookupKey) ~= "string" or lookupKey == "" then return end
    self.memberInstanceCaps = self.memberInstanceCaps or {}
    local cleanUsed = math.max(0, math.min(30, tonumber(used) or 0))
    local cleanMax = math.max(1, math.min(30, tonumber(max) or 5))
    self.memberInstanceCaps[lookupKey] = {
        used = cleanUsed,
        max = cleanMax,
        updatedAt = time(),
    }
    if type(self.members) == "table" then
        for i = 1, #self.members do
            local m = self.members[i]
            if m and m.lookupKey == lookupKey then
                m.instanceUsed = cleanUsed
                m.instanceMax = cleanMax
            end
        end
    end
    ns:Emit("GROUP_UPDATED")
end

function Group:GetMembers()
    return self.members or {}
end

function Group:GetSummaryCounts()
    local counts = { total = 0, TANK = 0, HEALER = 0, DAMAGER = 0, NONE = 0, online = 0, dead = 0 }
    for _, m in ipairs(self.members or {}) do
        counts.total = counts.total + 1
        if m.online ~= false then counts.online = counts.online + 1 end
        if m.isDead then counts.dead = counts.dead + 1 end
        counts[m.role or "NONE"] = (counts[m.role or "NONE"] or 0) + 1
    end
    return counts
end

local ALL_CLASSIC_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

function Group:GetCompositionAnalysis()
    if self._compCache then
        return self._compCache
    end
    local counts = self:GetSummaryCounts()
    local classCounts = {}
    for _, cf in ipairs(ALL_CLASSIC_CLASSES) do
        classCounts[cf] = 0
    end
    local subgroups = {}
    for g = 1, 8 do
        subgroups[g] = {
            index = g,
            members = {},
            TANK = 0,
            HEALER = 0,
            DAMAGER = 0,
            NONE = 0,
            hasShaman = false,
            hasPaladin = false,
            hasWarrior = false,
            hasDruid = false,
            hasPriest = false,
        }
    end
    local scUsers, avoidCount, goodCount, maxSubgroup = 0, 0, 0, 1
    for _, m in ipairs(self.members or {}) do
        local cf = m.classFile
        if cf and classCounts[cf] ~= nil then
            classCounts[cf] = classCounts[cf] + 1
        end
        local sgIdx = math.max(1, math.min(8, tonumber(m.subgroup) or 1))
        if sgIdx > maxSubgroup then maxSubgroup = sgIdx end
        local sg = subgroups[sgIdx]
        sg.members[#sg.members + 1] = m
        local rKey = m.role or "NONE"
        sg[rKey] = (sg[rKey] or 0) + 1
        if cf == "SHAMAN" then sg.hasShaman = true
        elseif cf == "PALADIN" then sg.hasPaladin = true
        elseif cf == "WARRIOR" then sg.hasWarrior = true
        elseif cf == "DRUID" then sg.hasDruid = true
        elseif cf == "PRIEST" then sg.hasPriest = true end

        if not m.isMe then
            if ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(m.lookupKey or m.displayName) then
                scUsers = scUsers + 1
            end
            local meta = Store and (Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(m.lookupKey or m.displayName) or Store:GetSocialMeta(m.lookupKey or m.displayName))
            if meta and meta.flag == "AVOID" then
                avoidCount = avoidCount + 1
            elseif meta and meta.flag == "GOOD" then
                goodCount = goodCount + 1
            end
        end
    end

    local resCount = (classCounts.PRIEST or 0) + (classCounts.PALADIN or 0) + (classCounts.SHAMAN or 0) + (classCounts.DRUID or 0)
    local bresCount = (classCounts.DRUID or 0) + (classCounts.WARLOCK or 0)
    local utilities = {
        resurrection = resCount,
        battleRes = bresCount,
        fortitude = classCounts.PRIEST or 0,
        intellect = classCounts.MAGE or 0,
        mark = classCounts.DRUID or 0,
        shout = classCounts.WARRIOR or 0,
        blessings = classCounts.PALADIN or 0,
        totems = classCounts.SHAMAN or 0,
        warlock = classCounts.WARLOCK or 0,
        hunter = classCounts.HUNTER or 0,
        rogue = classCounts.ROGUE or 0,
        dispelMagic = (classCounts.PRIEST or 0) + (classCounts.PALADIN or 0),
        dispelCurse = (classCounts.MAGE or 0) + (classCounts.DRUID or 0),
        dispelPoison = (classCounts.DRUID or 0) + (classCounts.PALADIN or 0) + (classCounts.SHAMAN or 0),
        dispelDisease = (classCounts.PRIEST or 0) + (classCounts.PALADIN or 0) + (classCounts.SHAMAN or 0),
    }

    local myFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    local missingClasses = {}
    for _, cf in ipairs(ALL_CLASSIC_CLASSES) do
        local skipOpp = (myFac == "Alliance" and cf == "SHAMAN") or (myFac == "Horde" and cf == "PALADIN")
        if not skipOpp and (classCounts[cf] or 0) == 0 then
            missingClasses[#missingClasses + 1] = cf
        end
    end

    local missingRolesText = ""
    if counts.total > 0 and counts.total < 5 and not (Compat.IsInRaid and Compat.IsInRaid()) then
        local openSlots = math.max(0, 5 - counts.total)
        local rawNeedT = math.max(0, 1 - (counts.TANK or 0))
        local rawNeedH = math.max(0, 1 - (counts.HEALER or 0))
        local rawNeedD = math.max(0, 3 - (counts.DAMAGER or 0))
        local needT = math.min(rawNeedT, openSlots)
        openSlots = openSlots - needT
        local needH = math.min(rawNeedH, openSlots)
        openSlots = openSlots - needH
        local needD = math.min(rawNeedD, openSlots)
        local parts = {}
        if needT > 0 then parts[#parts + 1] = needT .. "T" end
        if needH > 0 then parts[#parts + 1] = needH .. "H" end
        if needD > 0 then parts[#parts + 1] = needD .. "D" end
        if #parts > 0 then
            missingRolesText = table.concat(parts, " ")
        end
    end

    self._compCache = {
        counts = counts,
        classCounts = classCounts,
        subgroups = subgroups,
        maxSubgroup = maxSubgroup,
        utilities = utilities,
        missingClasses = missingClasses,
        missingRolesText = missingRolesText,
        scUsers = scUsers,
        avoidCount = avoidCount,
        goodCount = goodCount,
        inRaid = (Compat.IsInRaid and Compat.IsInRaid()) == true,
    }
    return self._compCache
end

function Group:GetRecentCompanions(query)
    if not (Store and Store.GetRecentCompanionsList) then return {} end
    local all = Store:GetRecentCompanionsList()
    local inGroupKeys = {}
    for _, m in ipairs(self.members or {}) do
        inGroupKeys[m.lookupKey] = true
    end

    local q = type(query) == "string" and query ~= "" and query:lower() or nil
    local out = {}
    local seenKeys = {}
    for _, rec in ipairs(all) do
        local isCurrent = inGroupKeys[rec.lookupKey] == true
        if rec.lookupKey then seenKeys[rec.lookupKey] = true end
        if not q or ((rec.displayName or "") .. " " .. (rec.zone or "")):lower():find(q, 1, true) then
            local copy = {}
            for k, v in pairs(rec) do copy[k] = v end
            copy.inCurrentGroup = isCurrent
            table.insert(out, copy)
        end
    end

    -- Passively merge Blizzard's cached Recent Allies (read-only GetRecentAllies only; never TryRequestRecentAlliesData)
    if C_RecentAllies and C_RecentAllies.GetRecentAllies then
        local okAllies, allies = pcall(C_RecentAllies.GetRecentAllies)
        if okAllies and type(allies) == "table" then
            for _, ally in ipairs(allies) do
                local ch = type(ally) == "table" and ally.characterData
                if type(ch) == "table" then
                    local rawName = Safe.String(ch.fullName) or Safe.String(ch.name)
                    if rawName and rawName ~= "" and Compat.ParseCharacterName then
                        local parsed = Compat.ParseCharacterName(rawName)
                        if parsed and parsed.lookupKey and not seenKeys[parsed.lookupKey] and not (Compat.IsMe and Compat.IsMe(parsed.displayName)) then
                            seenKeys[parsed.lookupKey] = true
                            local inter = type(ally.interactionData) == "table" and type(ally.interactionData.interactions) == "table" and ally.interactionData.interactions[1] or nil
                            local zone = inter and type(inter.contextData) == "table" and Safe.String(inter.contextData.locationName) or ""
                            local ts = inter and Safe.Number(inter.timestamp) or nil
                            local classID = Safe.Number(ch.classID)
                            local classInfo = (classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo) and Safe.Call(C_CreatureInfo.GetClassInfo, classID) or nil
                            local cf = type(classInfo) == "table" and Safe.String(classInfo.classFile) or nil
                            local lvl = Safe.Number(ch.level)
                            if not q or (parsed.displayName .. " " .. zone):lower():find(q, 1, true) then
                                table.insert(out, {
                                    displayName = parsed.displayName,
                                    lookupKey = parsed.lookupKey,
                                    guid = Safe.String(ch.guid),
                                    classFile = cf,
                                    level = (lvl and lvl > 0) and lvl or nil,
                                    zone = zone,
                                    lastSeen = ts,
                                    runs = 1,
                                    inCurrentGroup = (inGroupKeys[parsed.lookupKey] == true),
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end

function Group:StartReadyCheck()
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print(L["In Combat"])
        return false
    end
    if not Compat.IsInGroup() then
        ns:Print(L["You are not in a group."])
        return false
    end
    local canLead = Compat.IsGroupLeader("player") or Compat.IsGroupAssistant("player")
    if not canLead then
        ns:Print(L["Only the group leader or assistant can start a Ready Check."])
        return false
    end
    if DoReadyCheck then
        pcall(DoReadyCheck)
        return true
    end
    return false
end

function Group:PromoteMember(unit)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print(L["In Combat"])
        return false
    end
    if not Compat.IsGroupLeader("player") then
        ns:Print(L["Only the group leader can promote another member."])
        return false
    end
    if unit and PromoteToLeader then
        pcall(PromoteToLeader, unit)
        return true
    end
    return false
end

function Group:ToggleAssistant(unit)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print(L["In Combat"])
        return false
    end
    if not (Compat.IsGroupLeader("player") and Compat.IsInRaid() and unit) then
        return false
    end
    local isAssist = UnitIsGroupAssistant and Safe.Value(Safe.Call(UnitIsGroupAssistant, unit)) == true
    if isAssist and DemoteAssistant then
        pcall(DemoteAssistant, unit)
        return true
    elseif not isAssist and PromoteToAssistant then
        pcall(PromoteToAssistant, unit)
        return true
    end
    return false
end

function Group:GetReadyCheckProgress()
    if not self.readyCheckActive then return 0, 0, 0, 0 end
    local okCount, noCount, pendCount, total = 0, 0, 0, 0
    for _, m in ipairs(self.members or {}) do
        total = total + 1
        if m.ready == true then
            okCount = okCount + 1
        elseif m.ready == false then
            noCount = noCount + 1
        else
            pendCount = pendCount + 1
        end
    end
    return okCount, noCount, pendCount, total
end

function Group:LeaveGroup()
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print(L["In Combat"])
        return false
    end
    if not Compat.IsInGroup() then
        ns:Print(L["You are not in a group."])
        return false
    end
    return Compat.LeaveGroup()
end

local function PruneInstanceRuns(runs, now)
    local kept = {}
    if type(runs) ~= "table" then return kept end
    for i = 1, #runs do
        local r = runs[i]
        if type(r) == "table" and r.enteredAt and (now - r.enteredAt) < 86400 then
            kept[#kept + 1] = r
            if #kept >= 30 then
                break
            end
        end
    end
    return kept
end

function Group:RecordCurrentInstanceEntry()
    if not ns.db then return end
    if type(ns.db.instanceRuns) ~= "table" then
        ns.db.instanceRuns = {}
    end
    local inInst, instType = Safe.Call(IsInInstance)
    instType = Safe.String(instType)
    if inInst ~= true or (instType ~= "party" and instType ~= "raid") then
        self._activeInstanceSig = nil
        ns.db._lastInstanceActiveSig = nil
        return
    end

    local instName, mapIdNum
    if GetInstanceInfo then
        local okInfo, rawName, _, _, _, _, _, _, rawMapId = pcall(GetInstanceInfo)
        if okInfo then
            instName = Safe.String(rawName)
            mapIdNum = Safe.Number(rawMapId)
        end
    end
    instName = (instName and instName ~= "") and instName or Compat.CurrentZoneName() or L["Instance"]
    local sig = tostring(instType) .. ":" .. tostring(mapIdNum or instName)
    if self._activeInstanceSig == sig then
        return
    end

    local now = time()
    local runs = PruneInstanceRuns(ns.db.instanceRuns, now)
    ns.db.instanceRuns = runs

    local latest = runs[1]
    if ns.db._lastInstanceActiveSig == sig and latest and latest.sig == sig and (now - (latest.enteredAt or 0)) <= 900 then
        self._activeInstanceSig = sig
        return
    end

    self._activeInstanceSig = sig
    ns.db._lastInstanceActiveSig = sig

    local resolvedSelf = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myName = (resolvedSelf and resolvedSelf.fullName) or Safe.String(Safe.Call(UnitName, "player")) or "Player"
    local _, myClass = Safe.Call(UnitClass, "player")
    myClass = Safe.String(myClass)

    table.insert(runs, 1, {
        sig = sig,
        name = instName,
        instType = instType,
        enteredAt = now,
        charName = myName,
        classFile = myClass,
    })
    while #runs > 30 do
        table.remove(runs)
    end

    if Compat.IsInGroup() and ns.Clan and ns.Clan.BroadcastGroupInstanceCap then
        local st = self:GetHourlyInstanceStatus()
        ns.Clan:BroadcastGroupInstanceCap(st and st.used or 0, st and st.max or 5)
    end

    ns:Emit("GROUP_UPDATED")
    ns:Emit("CLAN_UPDATED")
end

function Group:GetHourlyInstanceStatus()
    local now = time()
    local runs = PruneInstanceRuns(ns.db and ns.db.instanceRuns, now)
    if ns.db then
        ns.db.instanceRuns = runs
    end
    local hourlyEntries = {}
    for i = 1, #runs do
        local r = runs[i]
        if (now - (r.enteredAt or 0)) < 3600 then
            hourlyEntries[#hourlyEntries + 1] = r
        end
    end
    local usedHourly = #hourlyEntries
    local maxHourly = 5
    local nextSlotSecs = 0
    if usedHourly >= maxHourly then
        local refEntry = hourlyEntries[maxHourly]
        nextSlotSecs = math.max(0, 3600 - (now - (refEntry.enteredAt or now)))
    elseif usedHourly > 0 then
        local oldestEntry = hourlyEntries[usedHourly]
        nextSlotSecs = math.max(0, 3600 - (now - (oldestEntry.enteredAt or now)))
    end
    return {
        used = usedHourly,
        max = maxHourly,
        nextSlotSecs = nextSlotSecs,
        recent24h = #runs,
        lastRun = runs[1],
        runs = runs,
    }
end

function Group:AppendInstanceHistoryTooltip(tt)
    if not tt then return end
    local st = self:GetHourlyInstanceStatus()
    local usedH = st and st.used or 0
    local maxH = st and st.max or 5
    if tt.NumLines and tt:NumLines() > 0 then
        tt:AddLine(" ")
    end
    local r = (usedH >= maxH) and 1.0 or ((usedH == maxH - 1) and 1.0 or 0.35)
    local g = (usedH >= maxH) and 0.35 or ((usedH == maxH - 1) and 0.72 or 0.92)
    local b = (usedH >= maxH) and 0.35 or ((usedH == maxH - 1) and 0.25 or 0.55)
    tt:AddDoubleLine(L["Instance Limit (1h)"], string.format("%d/%d", usedH, maxH), 1.0, 0.82, 0.0, r, g, b)
    if usedH > 0 and (st.nextSlotSecs or 0) > 0 and ns.Clan and ns.Clan.FormatResetDuration then
        tt:AddLine(L["Next slot frees in %s"]:format(ns.Clan:FormatResetDuration(st.nextSlotSecs)), 1.0, 0.68, 0.28, true)
    end
    local runs = st and st.runs
    if type(runs) == "table" and #runs > 0 then
        local now = time()
        tt:AddLine(L["Recent Instances (24h): %d"]:format(#runs), 0.72, 0.80, 0.90)
        local limit = math.min(6, #runs)
        for i = 1, limit do
            local entry = runs[i]
            if type(entry) == "table" then
                local hex = (Compat.ClassHex and Compat.ClassHex(entry.classFile)) or "|cffffffff"
                local leftTxt = hex .. (entry.charName or "?") .. "|r · " .. (entry.name or "?")
                local rel = (Compat.FormatRelativeTime and Compat.FormatRelativeTime(entry.enteredAt, L)) or ""
                if (now - (entry.enteredAt or 0)) < 3600 and ns.Clan and ns.Clan.FormatResetDuration then
                    local freesIn = ns.Clan:FormatResetDuration(3600 - (now - (entry.enteredAt or 0)))
                    rel = (rel ~= "" and (rel .. " ") or "") .. "(" .. freesIn .. ")"
                end
                tt:AddDoubleLine(leftTxt, rel, 0.92, 0.94, 0.96, 0.72, 0.78, 0.86)
            end
        end
    end
end

function Group:ResetDungeonInstances()
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print(L["In Combat"])
        return false
    end
    local inInst = Safe.Value(Safe.Call(IsInInstance)) == true
    if inInst then
        ns:Print(L["You must be outside the instance to reset dungeons."])
        return false
    end
    if Compat.IsInGroup() and not Compat.IsGroupLeader("player") then
        ns:Print(L["Only the group leader can reset instances."])
        return false
    end
    for _, m in ipairs(self.members or {}) do
        if not m.isMe then
            if (m.instanceUsed or 0) >= 5 then
                ns:Print(L["Warning: %s is at %d/%d hourly instances!"]:format(m.displayName or "?", m.instanceUsed or 5, m.instanceMax or 5))
            end
            if m.online == false then
                ns:Print(L["Note: %s is currently offline while resetting instances."]:format(m.displayName or "?"))
            end
        end
    end
    if ResetInstances then
        pcall(ResetInstances)
    end
    if self._activeRun and self._activeRun.started and self.FinalizeActiveDungeonRun then
        self:FinalizeActiveDungeonRun("instance_reset", false)
    end
    if ns.db then
        ns.db._lastInstanceActiveSig = nil
    end
    self._activeInstanceSig = nil
    ns:Print(L["Dungeon instances have been reset."])
    ns:Emit("GROUP_UPDATED")
    ns:Emit("CLAN_UPDATED")
    return true
end

-- ============================================================================
-- Dungeon & Raid Group Run History (Event-Driven, Zero CLEU, Zero Polling)
-- ============================================================================
local MAX_DUNGEON_HISTORY = 120
local MAX_RUN_MEMBERS = 40
local MAX_RUN_BOSSES = 15
local EXIT_GRACE_SECONDS = 45
local LEAVE_GRACE_SECONDS = 12
local MIN_VALID_RUN_SECONDS = 15

local DUNGEON_ACCENT_MAP = {
    ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a",
    ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Ä"] = "a",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
    ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i",
    ["Í"] = "i", ["Ì"] = "i", ["Î"] = "i", ["Ï"] = "i",
    ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o",
    ["Ó"] = "o", ["Ò"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ö"] = "o",
    ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
    ["Ú"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
    ["ç"] = "c", ["Ç"] = "c",
    ["ñ"] = "n", ["Ñ"] = "n",
}

local function FoldDungeonSearchText(s)
    if type(s) ~= "string" or s == "" then return "" end
    local out = s:gsub("[\194-\244][\128-\191]+", DUNGEON_ACCENT_MAP)
    return out:lower()
end

local function IsInPartyOrRaidInstanceNow()
    local inInst, instType = Safe.Call(IsInInstance)
    instType = Safe.String(instType)
    if inInst == true and (instType == "party" or instType == "raid") then
        local instName, diffIdNum, diffName, maxPlayers, mapIdNum
        if GetInstanceInfo then
            local okInfo, rawName, _, rawDiffId, rawDiffName, rawMaxPlayers, _, _, rawMapId = pcall(GetInstanceInfo)
            if okInfo then
                instName = Safe.String(rawName)
                diffIdNum = Safe.Number(rawDiffId)
                diffName = Safe.String(rawDiffName)
                maxPlayers = Safe.Number(rawMaxPlayers)
                mapIdNum = Safe.Number(rawMapId)
            end
        end
        instName = (instName and instName ~= "") and instName or Compat.CurrentZoneName() or L["Instance"]
        return true, instType, instName, mapIdNum, diffIdNum, diffName, maxPlayers
    end
    return false, nil, nil, nil, nil, nil, nil
end

local function LookupMemberGuildShort(unit, lookupKey)
    if unit and GetGuildInfo then
        local gName = Safe.String(Safe.Call(GetGuildInfo, unit))
        if gName and gName ~= "" then
            return gName
        end
    end
    if lookupKey and ns.Store and ns.Store.socialByLookup then
        local row = ns.Store.socialByLookup[lookupKey]
        local g = row and ((row.guild and row.guild ~= "" and row.guild) or (row.guildName and row.guildName ~= "" and row.guildName))
        if g then
            return g
        end
    end
    return nil
end

local DM_METRIC_DEFS = {
    { field = "dmg", psField = "dps", enumKey = "DamageDone", fallback = 0 },
    { field = "heal", psField = "hps", enumKey = "HealingDone", fallback = 2 },
    { field = "tkn", enumKey = "DamageTaken", fallback = 7 },
    { field = "intr", enumKey = "Interrupts", fallback = 5 },
    { field = "disp", enumKey = "Dispels", fallback = 6 },
    { field = "d", enumKey = "Deaths", fallback = nil },
}

local function IsNativeDamageMeterAvailable()
    if not (C_DamageMeter and type(C_DamageMeter.GetCombatSessionFromType) == "function") then
        return false
    end
    if type(C_DamageMeter.IsDamageMeterAvailable) == "function" then
        local ok, avail = pcall(C_DamageMeter.IsDamageMeterAvailable)
        if not ok or Safe.Value(avail) == false then
            return false
        end
    end
    return true
end

local function DeepCopyMetricsMap(srcMap)
    local copy = {}
    if type(srcMap) ~= "table" then return copy end
    for k, rec in pairs(srcMap) do
        if type(rec) == "table" then
            local c = {}
            if rec.guid then c.guid = rec.guid end
            if rec.name then c.name = rec.name end
            if rec.classFile then c.classFile = rec.classFile end
            for i = 1, #DM_METRIC_DEFS do
                local f = DM_METRIC_DEFS[i].field
                if rec[f] ~= nil then
                    c[f] = rec[f]
                end
            end
            copy[k] = c
        end
    end
    return copy
end

local function ResolveDamageMeterSourceKey(run, src)
    if type(src) ~= "table" then return nil end
    local isLocal = Safe.Value(src.isLocalPlayer) == true
    local guid = Safe.String(src.sourceGUID)
    local rawName = Safe.String(src.name) or Safe.String(src.unitName)
    local cls = Safe.String(src.classFilename) or Safe.String(src.unitClassFilename)

    if isLocal or (guid and run and run.myGuid and guid == run.myGuid) then
        if run and run.myKey then
            return run.myKey, run.myName or rawName, cls or run.myClass, guid
        end
    end
    if guid and run and run.guidToKey and run.guidToKey[guid] then
        local gk = run.guidToKey[guid]
        local mem = run.membersByKey and run.membersByKey[gk]
        return gk, (mem and mem.n) or rawName, cls or (mem and mem.c), guid
    end
    local parsed = (rawName and rawName ~= "" and Compat.ParseCharacterName) and Compat.ParseCharacterName(rawName) or nil
    if guid and Compat.LookupForeverFullName then
        local looked = Compat.LookupForeverFullName(guid, parsed and parsed.firstName or nil, false)
        if looked and looked.fullName and Compat.ParseCharacterName then
            local lp = Compat.ParseCharacterName(looked.fullName)
            if lp and lp.lookupKey then
                parsed = lp
            end
        end
    end
    if parsed and parsed.lookupKey then
        if run and run.membersByKey and run.membersByKey[parsed.lookupKey] then
            local mem = run.membersByKey[parsed.lookupKey]
            return parsed.lookupKey, mem.n or parsed.displayName, cls or mem.c, guid
        end
        if run and run.firstToKey and parsed.firstName then
            local fk = run.firstToKey[parsed.firstName:lower()]
            if fk then
                local guidConflict = false
                if guid and guid ~= "" and run.guidToKey then
                    for g, k in pairs(run.guidToKey) do
                        if k == fk and g ~= guid then
                            guidConflict = true
                            break
                        end
                    end
                end
                if not guidConflict then
                    local mem = run.membersByKey and run.membersByKey[fk]
                    return fk, (mem and mem.n) or parsed.displayName, cls or (mem and mem.c), guid
                end
            end
        end
        return parsed.lookupKey, parsed.displayName, cls, guid
    end
    return nil
end

local function ReadDamageMeterSessionByKey(run, sessionType)
    if not IsNativeDamageMeterAvailable() then
        return nil
    end
    local dmTypes = Enum and Enum.DamageMeterType
    local out = {}
    local maxDurationSec = 0
    local sessionId = nil
    for i = 1, #DM_METRIC_DEFS do
        local def = DM_METRIC_DEFS[i]
        local dmType = (dmTypes and dmTypes[def.enumKey] ~= nil) and dmTypes[def.enumKey] or ((not dmTypes) and def.fallback or nil)
        if dmType ~= nil then
            local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, dmType)
            if ok and type(session) == "table" and type(session.combatSources) == "table" then
                if sessionId == nil then
                    sessionId = Safe.Number(session.sessionID) or Safe.String(session.sessionID) or Safe.Number(session.startTime)
                end
                local sDur = Safe.Number(session.durationSeconds)
                if sDur and sDur > maxDurationSec then
                    maxDurationSec = sDur
                end
                local seenInMetric = {}
                for _, src in ipairs(session.combatSources) do
                    local key, dispName, cls, guid = ResolveDamageMeterSourceKey(run, src)
                    if key then
                        local amt = math.max(0, math.floor((Safe.Number(src.totalAmount) or 0) + 0.5))
                        local ps = math.max(0, math.floor((Safe.Number(src.amountPerSecond) or 0) + 0.5))
                        if not seenInMetric[key] then
                            seenInMetric[key] = true
                            local rec = out[key]
                            if not rec then
                                rec = { name = dispName, classFile = cls, guid = (guid and guid ~= "") and guid or nil }
                                out[key] = rec
                            elseif (not rec.guid) and guid and guid ~= "" then
                                rec.guid = guid
                            end
                            rec[def.field] = math.max(rec[def.field] or 0, amt)
                            if def.psField and ps > 0 then
                                rec[def.psField] = math.max(rec[def.psField] or 0, ps)
                            end
                        end
                    end
                end
            end
        end
    end
    return out, maxDurationSec, sessionId
end

local function ReconcileDamageMeterKeys(run)
    if not run then return end
    local validCanonical = {}
    local guidMap = {}
    local firstCounts = {}
    local unambiguousFirst = {}

    local function registerFirst(displayName, canonicalKey)
        if not (displayName and canonicalKey and Compat.ParseCharacterName) then return end
        local p = Compat.ParseCharacterName(displayName)
        local fl = p and p.firstName and p.firstName:lower()
        if not (fl and fl ~= "") then return end
        local c = (firstCounts[fl] or 0) + 1
        firstCounts[fl] = c
        if c == 1 then
            unambiguousFirst[fl] = canonicalKey
        else
            unambiguousFirst[fl] = nil
        end
    end

    if run.myKey then
        validCanonical[run.myKey] = true
        registerFirst(run.myName or run.myKey, run.myKey)
        if run.myGuid then
            guidMap[run.myGuid] = run.myKey
        end
    end
    for k, mem in pairs(run.membersByKey or {}) do
        validCanonical[k] = true
        if k ~= run.myKey then
            registerFirst((mem and mem.n) or k, k)
        end
    end
    for g, k in pairs(run.guidToKey or {}) do
        if g and k then
            guidMap[g] = k
        end
    end

    local dmTables = {
        run.dmBaselineByKey,
        run.dmResetAccumByKey,
        run.dmLiveByKey,
        run.dmLastOverallByKey,
        run.dmPullAccumByKey,
    }
    for tIdx = 1, #dmTables do
        local tbl = dmTables[tIdx]
        if type(tbl) == "table" then
            local moves = {}
            for oldK, rec in pairs(tbl) do
                if not validCanonical[oldK] and type(rec) == "table" then
                    local newK = rec.guid and guidMap[rec.guid] or nil
                    if not newK and type(oldK) == "string" and not oldK:find("-", 1, true) and not oldK:find(" ", 1, true) then
                        newK = unambiguousFirst[oldK:lower()]
                    end
                    if newK and newK ~= oldK then
                        moves[#moves + 1] = { oldK = oldK, newK = newK }
                    end
                end
            end
            for mIdx = 1, #moves do
                local mv = moves[mIdx]
                local srcRec = tbl[mv.oldK]
                local dstRec = tbl[mv.newK]
                if srcRec then
                    if not dstRec then
                        tbl[mv.newK] = srcRec
                    else
                        if srcRec.guid and not dstRec.guid then dstRec.guid = srcRec.guid end
                        if srcRec.name and not dstRec.name then dstRec.name = srcRec.name end
                        if srcRec.classFile and not dstRec.classFile then dstRec.classFile = srcRec.classFile end
                        for i = 1, #DM_METRIC_DEFS do
                            local f = DM_METRIC_DEFS[i].field
                            if srcRec[f] ~= nil then
                                dstRec[f] = math.max(dstRec[f] or 0, srcRec[f])
                            end
                        end
                    end
                    tbl[mv.oldK] = nil
                end
            end
        end
    end
end

local function FoldDungeonRunOverallIntoReset(run)
    if not run then return end
    run.dmResetAccumByKey = run.dmResetAccumByKey or {}
    for k, live in pairs(run.dmLiveByKey or {}) do
        local ra = run.dmResetAccumByKey[k]
        if not ra then
            ra = {}
            run.dmResetAccumByKey[k] = ra
        end
        if live.guid and not ra.guid then ra.guid = live.guid end
        for i = 1, #DM_METRIC_DEFS do
            local f = DM_METRIC_DEFS[i].field
            ra[f] = math.max(ra[f] or 0, live[f] or 0)
        end
    end
    run.dmOverallDurResetAccum = math.max(run.dmOverallDurResetAccum or 0, run.dmOverallDurLive or 0)
    run.dmBaselineByKey = {}
    run.dmLastOverallByKey = {}
    run.dmOverallDurBase = 0
    run.dmLastOverallDur = 0
end

local function SnapshotDungeonRunDamageMeterBaseline(run)
    if not run then return end
    local sessOverall = (Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Overall) or 0
    local baseMap, baseDur = ReadDamageMeterSessionByKey(run, sessOverall)
    run.dmBaselineByKey = baseMap or {}
    run.dmLastOverallByKey = DeepCopyMetricsMap(baseMap)
    run.dmResetAccumByKey = run.dmResetAccumByKey or {}
    run.dmLiveByKey = run.dmLiveByKey or {}
    run.dmOverallDurBase = baseDur or 0
    run.dmLastOverallDur = baseDur or 0
    run.dmOverallDurResetAccum = run.dmOverallDurResetAccum or 0
    run.dmOverallDurLive = run.dmOverallDurLive or 0
    run.dmPullAccumByKey = run.dmPullAccumByKey or {}
    run.dmPullDurAccum = run.dmPullDurAccum or 0
    run.dmLastCurrentSessionSig = nil
    run.dmBaselineCaptured = true
end

local function UpdateDungeonRunDamageMeter(run, isPullEnd)
    if not (run and run.started and IsNativeDamageMeterAvailable()) then
        return
    end
    if not run.dmBaselineCaptured then
        SnapshotDungeonRunDamageMeterBaseline(run)
    end
    local sessOverall = (Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Overall) or 0
    local sessCurrent = (Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current) or 1
    local overallNow, overallDur = ReadDamageMeterSessionByKey(run, sessOverall)
    local overallHasData = (overallNow ~= nil and next(overallNow) ~= nil)

    run.dmLiveByKey = run.dmLiveByKey or {}

    if overallHasData then
        local sessionReset = false
        if (run.dmLastOverallDur or 0) > 1 and (overallDur or 0) > 0 and overallDur < (run.dmLastOverallDur - 1) then
            sessionReset = true
        elseif run.dmLastOverallByKey then
            for k, ov in pairs(overallNow) do
                local prev = run.dmLastOverallByKey[k]
                if prev then
                    for i = 1, #DM_METRIC_DEFS do
                        local f = DM_METRIC_DEFS[i].field
                        local curV = ov[f] or 0
                        local prevV = prev[f] or 0
                        if curV > 0 and prevV > 0 and curV < (prevV - 1) then
                            sessionReset = true
                            break
                        end
                    end
                end
                if sessionReset then break end
            end
        end
        if sessionReset then
            FoldDungeonRunOverallIntoReset(run)
        end

        if (overallDur or 0) > 0 then
            local durBase = run.dmOverallDurBase or 0
            local durDelta = (overallDur >= durBase) and (overallDur - durBase) or overallDur
            run.dmOverallDurLive = math.max(run.dmOverallDurLive or 0, (run.dmOverallDurResetAccum or 0) + durDelta)
            run.dmLastOverallDur = overallDur
        end

        local allKeys = {}
        for k in pairs(overallNow) do allKeys[k] = true end
        for k in pairs(run.dmResetAccumByKey or {}) do allKeys[k] = true end
        for k in pairs(run.dmLiveByKey) do allKeys[k] = true end

        run.dmLastOverallByKey = run.dmLastOverallByKey or {}
        for k in pairs(allKeys) do
            local ov = overallNow[k]
            local bs = run.dmBaselineByKey and run.dmBaselineByKey[k]
            local ra = run.dmResetAccumByKey and run.dmResetAccumByKey[k]
            local live = run.dmLiveByKey[k]
            if not live then
                live = {}
                run.dmLiveByKey[k] = live
            end
            local lastOv = run.dmLastOverallByKey[k]
            if not lastOv then
                lastOv = {}
                run.dmLastOverallByKey[k] = lastOv
            end
            if ov and ov.guid then
                live.guid = ov.guid
                lastOv.guid = ov.guid
            elseif bs and bs.guid and not live.guid then
                live.guid = bs.guid
            elseif ra and ra.guid and not live.guid then
                live.guid = ra.guid
            end
            for i = 1, #DM_METRIC_DEFS do
                local f = DM_METRIC_DEFS[i].field
                local curOv = (ov and ov[f]) or 0
                local baseOv = (bs and bs[f]) or 0
                if curOv > (lastOv[f] or 0) or (ov and curOv > 0) then
                    lastOv[f] = curOv
                end
                local ovDelta = (curOv >= baseOv) and (curOv - baseOv) or curOv
                local fromOverall = ((ra and ra[f]) or 0) + ovDelta
                live[f] = math.max(live[f] or 0, fromOverall)
            end
        end
        return
    end

    if isPullEnd and run.lastPullMetered ~= (run.pulls or 0) then
        run.lastPullMetered = run.pulls or 0
        local currNow, currDur, currSessId = ReadDamageMeterSessionByKey(run, sessCurrent)
        if currNow and next(currNow) ~= nil then
            local parts = { tostring(currSessId or ""), string.format("%.2f", currDur or 0) }
            local sortedKeys = {}
            for k in pairs(currNow) do
                sortedKeys[#sortedKeys + 1] = k
            end
            table.sort(sortedKeys)
            for idx = 1, #sortedKeys do
                local k = sortedKeys[idx]
                local vals = currNow[k]
                parts[#parts + 1] = k .. ":" .. tostring(vals.dmg or 0) .. ":" .. tostring(vals.heal or 0) .. ":" .. tostring(vals.tkn or 0)
            end
            local sig = table.concat(parts, "|")
            if sig ~= run.dmLastCurrentSessionSig then
                run.dmLastCurrentSessionSig = sig
                if currDur and currDur > 0 then
                    run.dmPullDurAccum = (run.dmPullDurAccum or 0) + currDur
                end
                run.dmPullAccumByKey = run.dmPullAccumByKey or {}
                for k, vals in pairs(currNow) do
                    local pa = run.dmPullAccumByKey[k]
                    if not pa then
                        pa = {}
                        run.dmPullAccumByKey[k] = pa
                    end
                    if vals.guid and not pa.guid then
                        pa.guid = vals.guid
                    end
                    for i = 1, #DM_METRIC_DEFS do
                        local f = DM_METRIC_DEFS[i].field
                        pa[f] = (pa[f] or 0) + (vals[f] or 0)
                    end
                end
            end
        end
        for k, pa in pairs(run.dmPullAccumByKey or {}) do
            local ra = run.dmResetAccumByKey and run.dmResetAccumByKey[k]
            local live = run.dmLiveByKey[k]
            if not live then
                live = {}
                run.dmLiveByKey[k] = live
            end
            if pa.guid and not live.guid then
                live.guid = pa.guid
            end
            for i = 1, #DM_METRIC_DEFS do
                local f = DM_METRIC_DEFS[i].field
                local fromPulls = ((ra and ra[f]) or 0) + (pa[f] or 0)
                live[f] = math.max(live[f] or 0, fromPulls)
            end
        end
    end
end

local function OnDungeonRunDamageMeterReset()
    local run = Group._activeRun
    if not run then return end
    if not run.started then
        run.dmBaselineByKey = {}
        run.dmLastOverallByKey = {}
        run.dmResetAccumByKey = {}
        run.dmLiveByKey = {}
        run.dmOverallDurBase = 0
        run.dmLastOverallDur = 0
        run.dmOverallDurResetAccum = 0
        run.dmOverallDurLive = 0
        run.dmPullAccumByKey = {}
        run.dmPullDurAccum = 0
        run.dmLastCurrentSessionSig = nil
        run.dmBaselineCaptured = true
        return
    end
    FoldDungeonRunOverallIntoReset(run)
    run.dmPullAccumByKey = {}
    run.dmPullDurAccum = 0
    run.dmLastCurrentSessionSig = nil
end

function Group:FormatCompactNumber(n)
    local val = Safe.Number(n) or 0
    if val >= 1000000 then
        return string.format("%.2fM", val / 1000000)
    elseif val >= 10000 then
        return string.format("%.1fK", val / 1000)
    elseif val >= 1000 then
        return string.format("%.2fK", val / 1000)
    end
    return tostring(math.floor(val + 0.5))
end

function Group:FormatCopperCompact(copper)
    local total = math.max(0, math.floor(Safe.Number(copper) or 0))
    if total == 0 then return "0c" end
    local g = math.floor(total / 10000)
    local s = math.floor((total % 10000) / 100)
    local c = total % 100
    if g > 0 then
        return string.format("%dg %ds", g, s)
    elseif s > 0 then
        return string.format("%ds %dc", s, c)
    end
    return string.format("%dc", c)
end

function Group:CheckDungeonRunDeaths(targetUnit)
    local run = self._activeRun
    if not (run and run.started) then return end
    local inInst = IsInPartyOrRaidInstanceNow()
    if not inInst then return end

    local units = {}
    if type(targetUnit) == "string" and targetUnit ~= "" then
        units[1] = targetUnit
    else
        local inRaid = Compat.IsInRaid and Compat.IsInRaid()
        if inRaid then
            local num = Compat.GetNumGroupMembers and Compat.GetNumGroupMembers() or 0
            for i = 1, math.min(num, 40) do
                units[#units + 1] = "raid" .. i
            end
        else
            units[1] = "player"
            for i = 1, 4 do
                units[#units + 1] = "party" .. i
            end
        end
    end

    run.deadStateByKey = run.deadStateByKey or {}
    run.lastDeathAtByKey = run.lastDeathAtByKey or {}
    local now = time()
    local newlyDied = false

    for i = 1, #units do
        local u = units[i]
        if UnitExists and Safe.Value(UnitExists(u)) == true and (not UnitIsConnected or Safe.Value(UnitIsConnected(u)) ~= false) then
            local isDead = (UnitIsDeadOrGhost and Safe.Value(Safe.Call(UnitIsDeadOrGhost, u)) == true)
                and not (UnitIsFeignDeath and Safe.Value(Safe.Call(UnitIsFeignDeath, u)) == true)
            local key = nil
            if u == "player" then
                key = run.myKey
            else
                local guid = Safe.String(Safe.Call(UnitGUID, u))
                if guid and run.guidToKey and run.guidToKey[guid] then
                    key = run.guidToKey[guid]
                else
                    local rawN = Safe.String(Safe.Call(UnitName, u))
                    local parsed = rawN and Compat.ParseCharacterName and Compat.ParseCharacterName(rawN)
                    if parsed then
                        key = (run.membersByKey and run.membersByKey[parsed.lookupKey]) and parsed.lookupKey
                            or (parsed.firstName and run.firstToKey and run.firstToKey[parsed.firstName:lower()])
                            or parsed.lookupKey
                    end
                end
            end
            if key then
                if isDead and not run.deadStateByKey[key] and (now - (run.lastDeathAtByKey[key] or 0)) >= 4 then
                    run.lastDeathAtByKey[key] = now
                    run.totalDeaths = (run.totalDeaths or 0) + 1
                    newlyDied = true
                    if key == run.myKey then
                        run.myDeaths = (run.myDeaths or 0) + 1
                    elseif run.membersByKey and run.membersByKey[key] then
                        run.membersByKey[key].deaths = (run.membersByKey[key].deaths or 0) + 1
                    end
                end
                run.deadStateByKey[key] = isDead
            end
        end
    end

    if newlyDied and (now - (run.lastWipeAt or 0)) >= 25 then
        local presentCount, aliveCount = 0, 0
        local inRaid = Compat.IsInRaid and Compat.IsInRaid()
        local checkUnits = {}
        if inRaid then
            local num = Compat.GetNumGroupMembers and Compat.GetNumGroupMembers() or 0
            for i = 1, math.min(num, 40) do
                checkUnits[#checkUnits + 1] = "raid" .. i
            end
        else
            checkUnits[1] = "player"
            for i = 1, 4 do
                checkUnits[#checkUnits + 1] = "party" .. i
            end
        end
        for i = 1, #checkUnits do
            local cu = checkUnits[i]
            if UnitExists and Safe.Value(UnitExists(cu)) == true and (not UnitIsConnected or Safe.Value(UnitIsConnected(cu)) ~= false) then
                presentCount = presentCount + 1
                local cDead = (UnitIsDeadOrGhost and Safe.Value(Safe.Call(UnitIsDeadOrGhost, cu)) == true)
                    and not (UnitIsFeignDeath and Safe.Value(Safe.Call(UnitIsFeignDeath, cu)) == true)
                if not cDead then
                    aliveCount = aliveCount + 1
                end
            end
        end
        if presentCount >= 2 and aliveCount == 0 then
            run.wipes = (run.wipes or 0) + 1
            run.lastWipeAt = now
        end
    end
end

function Group:OnDungeonRunXpUpdate(newLevelFromEvent)
    local run = self._activeRun
    if not (run and run.started) then return end
    local curLvl = Safe.Number(newLevelFromEvent) or Safe.Number(Safe.Call(UnitLevel, "player")) or run.lastLevel or 0
    if curLvl > (run.lastLevel or curLvl) then
        run.levelsGained = (run.levelsGained or 0) + (curLvl - run.lastLevel)
        run.lastLevel = curLvl
        run._xpRolloverPending = true
    end
    if newLevelFromEvent ~= nil then
        -- Wait for PLAYER_XP_UPDATE so UnitXP("player") reflects the post-levelup bar cleanly.
        return
    end
    local curXp = Safe.Number(Safe.Call(UnitXP, "player")) or 0
    local curMax = Safe.Number(Safe.Call(UnitXPMax, "player")) or 0
    if run._xpRolloverPending and curXp <= (run.lastXp or curXp) then
        local prevRemain = math.max(0, (run.lastXpMax or 0) - (run.lastXp or 0))
        run.xpGained = (run.xpGained or 0) + prevRemain + curXp
        run._xpRolloverPending = nil
        run.lastXp = curXp
        run.lastXpMax = curMax
    elseif curXp > (run.lastXp or curXp) then
        run.xpGained = (run.xpGained or 0) + (curXp - run.lastXp)
        run.lastXp = curXp
        run.lastXpMax = curMax
    elseif curMax > 0 and curMax ~= run.lastXpMax then
        run.lastXpMax = curMax
    end
end

function Group:OnDungeonRunMoneyUpdate()
    local run = self._activeRun
    if not (run and run.started) then return end
    local curMoney = GetMoney and Safe.Number(Safe.Call(GetMoney)) or nil
    if curMoney == nil then return end
    if run.lastMoney and curMoney > run.lastMoney then
        run.moneyGained = (run.moneyGained or 0) + (curMoney - run.lastMoney)
    end
    run.lastMoney = curMoney
end

function Group:OnDungeonRunLootEvent(itemMsgOrLink, looterName, isEncounterLoot, itemIdHint)
    local run = self._activeRun
    if not (run and run.started) then return end
    run.loot = run.loot or {}
    if #run.loot >= 8 then return end

    local itemID = Safe.Number(itemIdHint)
    local itemName, linkQuality
    if type(itemMsgOrLink) == "string" and itemMsgOrLink:find("|Hitem:", 1, true) then
        if not itemID then
            itemID = tonumber(itemMsgOrLink:match("|Hitem:(%d+)"))
        end
        itemName = itemMsgOrLink:match("%[([^%]]+)%]")
        local colorHex = itemMsgOrLink:match("|cff(%x%x%x%x%x%x)|Hitem:")
        if colorHex then
            local low = colorHex:lower()
            if low == "ff8000" then linkQuality = 5
            elseif low == "a335ee" then linkQuality = 4
            elseif low == "0070dd" then linkQuality = 3
            elseif low == "1eff00" then linkQuality = 2
            end
        end
    end
    if not itemID or itemID <= 0 then return end

    local q = linkQuality
    if not q and C_Item and C_Item.GetItemQualityByID then
        q = Safe.Number(Safe.Call(C_Item.GetItemQualityByID, itemID))
    end
    q = q or 1
    if q < 2 then return end
    if not isEncounterLoot and q == 2 and #run.loot >= 4 then
        return
    end

    if (not itemName or itemName == "") and C_Item and C_Item.GetItemNameByID then
        itemName = Safe.String(Safe.Call(C_Item.GetItemNameByID, itemID))
    end
    if not itemName or itemName == "" then return end

    local cleanWho = Safe.String(looterName)
    if cleanWho and cleanWho ~= "" and Compat.ParseCharacterName then
        local pw = Compat.ParseCharacterName(cleanWho)
        cleanWho = pw and pw.displayName or cleanWho
    else
        cleanWho = nil
    end

    run.lootSeen = run.lootSeen or {}
    local seenKey = tostring(itemID) .. ":" .. (cleanWho or "")
    if run.lootSeen[seenKey] then return end
    run.lootSeen[seenKey] = true

    run.loot[#run.loot + 1] = {
        id = itemID,
        n = itemName,
        q = q,
        w = cleanWho,
    }
end

function Group:IsDungeonRunLogEnabled()
    if Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("group") then
        return false
    end
    if ns.db and ns.db.settings and ns.db.settings.dungeonRunLogEnabled == false then
        return false
    end
    return true
end

function Group:GetDungeonHistoryTable()
    if type(SocialCentralDB) ~= "table" then
        return {}
    end
    if type(SocialCentralDB.dungeonHistory) ~= "table" then
        SocialCentralDB.dungeonHistory = {}
    end
    return SocialCentralDB.dungeonHistory
end

function Group:FormatRunDuration(totalSec)
    local sec = math.max(0, math.floor(tonumber(totalSec) or 0))
    local hrs = math.floor(sec / 3600)
    local mins = math.floor((sec % 3600) / 60)
    local rem = sec % 60
    if hrs > 0 then
        return string.format("%dh %02dm %02ds", hrs, mins, rem)
    elseif mins > 0 then
        return string.format("%dm %02ds", mins, rem)
    end
    return string.format("%ds", rem)
end

function Group:GetRunEndReasonLabel(reasonCode)
    if reasonCode == "member_left" then
        return L["Member left group"]
    elseif reasonCode == "left_group" then
        return L["Left group"]
    elseif reasonCode == "exited_instance" then
        return L["Exited instance"]
    elseif reasonCode == "zone_change" then
        return L["Entered another instance"]
    elseif reasonCode == "instance_reset" then
        return L["Instance reset"]
    elseif reasonCode == "logout" then
        return L["Session ended"]
    end
    return L["Completed"]
end

function Group:GetDungeonHistoryCount()
    local hist = self:GetDungeonHistoryTable()
    return #hist
end

function Group:GetActiveDungeonRunSummary()
    local run = self._activeRun
    if not run then return nil end
    local count = 0
    for _ in pairs(run.membersByKey or {}) do
        count = count + 1
    end
    local totalDmg = 0
    for _, dm in pairs(run.dmLiveByKey or {}) do
        totalDmg = totalDmg + (dm.dmg or 0)
    end
    return {
        zone = run.zone,
        instType = run.instType,
        difficultyName = run.difficultyName,
        started = run.started == true,
        startedAt = run.startedAt,
        elapsed = run.started and math.max(0, time() - (run.startedAt or time())) or 0,
        bossKills = run.bossKills or 0,
        pulls = run.pulls or 0,
        dmg = totalDmg,
        memberCount = math.max(1, count + 1, run.peakSize or (count + 1)),
    }
end

function Group:GetDungeonHistory(query, filterMode)
    local hist = self:GetDungeonHistoryTable()
    local q = FoldDungeonSearchText(Compat.Trim and Compat.Trim(query or "") or (query or ""))
    local mode = filterMode or "ALL"
    local myCharKey = nil
    if mode == "CHAR" then
        local resolvedSelf = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
        local myDisp = (resolvedSelf and resolvedSelf.fullName) or Safe.String(Safe.Call(UnitName, "player"))
        local parsedSelf = myDisp and Compat.ParseCharacterName and Compat.ParseCharacterName(myDisp)
        myCharKey = parsedSelf and parsedSelf.lookupKey or nil
    end
    local out = {}
    for i = 1, #hist do
        local rec = hist[i]
        if type(rec) == "table" then
            local passMode = true
            if mode == "DUNGEON" then
                passMode = (rec.t ~= "raid")
            elseif mode == "RAID" then
                passMode = (rec.t == "raid")
            elseif mode == "CHAR" and myCharKey then
                passMode = (rec.ck == myCharKey)
            end
            if passMode then
                if q == "" then
                    out[#out + 1] = rec
                else
                    local matched = FoldDungeonSearchText(rec.z or ""):find(q, 1, true) ~= nil
                        or FoldDungeonSearchText(rec.ch or ""):find(q, 1, true) ~= nil
                        or FoldDungeonSearchText(rec.bn or ""):find(q, 1, true) ~= nil
                        or (rec.diff and FoldDungeonSearchText(rec.diff):find(q, 1, true) ~= nil)
                    if not matched and type(rec.bs) == "table" then
                        for bIdx = 1, #rec.bs do
                            if FoldDungeonSearchText(rec.bs[bIdx] or ""):find(q, 1, true) then
                                matched = true
                                break
                            end
                        end
                    end
                    if not matched and type(rec.m) == "table" then
                        for mIdx = 1, #rec.m do
                            local mm = rec.m[mIdx]
                            if mm and (FoldDungeonSearchText(mm.n or ""):find(q, 1, true)
                                or (mm.g and FoldDungeonSearchText(mm.g):find(q, 1, true)))
                            then
                                matched = true
                                break
                            end
                        end
                    end
                    if not matched and type(rec.loot) == "table" then
                        for lIdx = 1, #rec.loot do
                            local it = rec.loot[lIdx]
                            if it and FoldDungeonSearchText(it.n or ""):find(q, 1, true) then
                                matched = true
                                break
                            end
                        end
                    end
                    if matched then
                        out[#out + 1] = rec
                    end
                end
            end
        end
    end
    return out
end

function Group:DeleteDungeonRun(runId)
    if not runId then return false end
    local hist = self:GetDungeonHistoryTable()
    for i = #hist, 1, -1 do
        if hist[i] and hist[i].id == runId then
            table.remove(hist, i)
            ns:Emit("DUNGEON_HISTORY_UPDATED")
            ns:Emit("GROUP_UPDATED")
            return true
        end
    end
    return false
end

function Group:ClearDungeonHistory()
    local hist = self:GetDungeonHistoryTable()
    if #hist == 0 then return false end
    wipe(hist)
    ns:Emit("DUNGEON_HISTORY_UPDATED")
    ns:Emit("GROUP_UPDATED")
    return true
end

function Group:CaptureActiveRunMembers(isInitial)
    local run = self._activeRun
    if not run then return end
    run.membersByKey = run.membersByKey or {}
    run.presentKeys = run.presentKeys or {}
    run.guidToKey = run.guidToKey or {}
    run.firstToKey = run.firstToKey or {}

    local liveKeys = {}
    local liveCount = 0
    local joinedNew = false
    for _, m in ipairs(self.members or {}) do
        if m and m.lookupKey then
            liveCount = liveCount + 1
            liveKeys[m.lookupKey] = true
            if m.guid then
                run.guidToKey[m.guid] = m.lookupKey
            end
            local parsedMem = m.displayName and Compat.ParseCharacterName and Compat.ParseCharacterName(m.displayName)
            if parsedMem and parsedMem.firstName then
                local fl = parsedMem.firstName:lower()
                if not run.firstToKey[fl] then
                    run.firstToKey[fl] = m.lookupKey
                end
            end
            if m.isMe then
                run.myName = m.displayName or run.myName
                run.myKey = m.lookupKey or run.myKey
                run.myClass = m.classFile or run.myClass
                run.myLevel = m.level or run.myLevel
                run.myRole = m.role or run.myRole
                run.myGuid = m.guid or run.myGuid
            else
                local rec = run.membersByKey[m.lookupKey]
                local gName = LookupMemberGuildShort(m.unit, m.lookupKey)
                if not rec then
                    local memberCount = 0
                    for _ in pairs(run.membersByKey) do memberCount = memberCount + 1 end
                    if memberCount < MAX_RUN_MEMBERS then
                        run.membersByKey[m.lookupKey] = {
                            n = m.displayName or m.lookupKey,
                            k = m.lookupKey,
                            c = m.classFile,
                            r = m.role,
                            l = m.level,
                            g = gName,
                            j = (not isInitial and run.started) and true or nil,
                            lv = nil,
                        }
                        if not isInitial and run.started then
                            joinedNew = true
                        end
                    end
                else
                    if m.displayName and (not rec.n or (m.displayName:find("%s") and not rec.n:find("%s"))) then
                        rec.n = m.displayName
                    end
                    if m.classFile and not rec.c then rec.c = m.classFile end
                    if m.role and m.role ~= "NONE" then rec.r = m.role end
                    if m.level and m.level > (rec.l or 0) then rec.l = m.level end
                    if gName and not rec.g then rec.g = gName end
                    rec.lv = nil
                end
            end
        end
    end

    if not isInitial and run.started then
        local leftNow = 0
        for prevKey in pairs(run.presentKeys) do
            if not liveKeys[prevKey] and prevKey ~= run.myKey then
                leftNow = leftNow + 1
                local rec = run.membersByKey[prevKey]
                if rec then
                    rec.lv = true
                end
            end
        end
        if joinedNew then
            -- Group replaced a leaver and kept going: clear pending leave marker.
            run.pendingLeaveAt = nil
            run.leftSinceCombat = 0
            run._leaveSeq = (run._leaveSeq or 0) + 1
        elseif leftNow > 0 then
            local now = time()
            run.pendingLeaveAt = run.pendingLeaveAt or now
            run.leftSinceCombat = (run.leftSinceCombat or 0) + leftNow
            local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
            if run.exitedAt then
                self:FinalizeActiveDungeonRun("member_left", false)
                return
            elseif not inCombat then
                local isSmallLeft
                if run.instType == "raid" then
                    local raidDisbandThreshold = math.max(3, math.floor((run.peakSize or liveCount) / 2))
                    isSmallLeft = (liveCount <= 2) or ((run.leftSinceCombat or 0) >= raidDisbandThreshold)
                else
                    isSmallLeft = (liveCount <= 2) or ((run.leftSinceCombat or 0) >= 2)
                end
                if isSmallLeft then
                    run._leaveSeq = (run._leaveSeq or 0) + 1
                    local lSeq = run._leaveSeq
                    if C_Timer and C_Timer.After then
                        C_Timer.After(LEAVE_GRACE_SECONDS, function()
                            local cur = Group._activeRun
                            if cur == run and cur._leaveSeq == lSeq and cur.started and cur.pendingLeaveAt then
                                local stillCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
                                if not stillCombat then
                                    Group:FinalizeActiveDungeonRun("member_left", false)
                                end
                            end
                        end)
                    end
                end
            end
        end
    end

    run.presentKeys = liveKeys
    if liveCount > (run.peakSize or 0) then
        run.peakSize = liveCount
    end
    ReconcileDamageMeterKeys(run)
end

function Group:FinalizeActiveDungeonRun(reason, silent)
    local run = self._activeRun
    self._activeRun = nil
    if not run or not run.started or not self:IsDungeonRunLogEnabled() then
        return false
    end

    local now = time()
    if run.inCombatNow and run.combatStartedAt then
        run.combatSeconds = (run.combatSeconds or 0) + math.max(1, now - run.combatStartedAt)
        run.inCombatNow = false
        run.combatStartedAt = nil
    end

    local resolvedSelf = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myName = run.myName or (resolvedSelf and resolvedSelf.fullName) or Safe.String(Safe.Call(UnitName, "player")) or "Player"
    local parsedSelf = Compat.ParseCharacterName and Compat.ParseCharacterName(myName)
    local myKey = run.myKey or (parsedSelf and parsedSelf.lookupKey)
    if myKey and not run.myKey then
        run.myKey = myKey
    end
    if myName and not run.myName then
        run.myName = myName
    end

    UpdateDungeonRunDamageMeter(run, true)
    ReconcileDamageMeterKeys(run)

    local startedAt = run.startedAt or run.enteredAt or now
    local endedAt
    local endReason = reason or "completed"
    if run.pendingLeaveAt and run.pendingLeaveAt >= (run.lastCombatAt or startedAt) then
        endedAt = run.pendingLeaveAt
        endReason = "member_left"
    elseif run.exitedAt and run.exitedAt >= startedAt then
        endedAt = run.exitedAt
        endReason = (reason == "left_group") and "left_group" or (reason or "exited_instance")
    else
        endedAt = now
    end

    local duration = math.max(1, endedAt - startedAt)
    local bossKills = run.bossKills or 0
    if duration < MIN_VALID_RUN_SECONDS and bossKills == 0 then
        return false
    end

    local dmDur = math.floor((run.dmOverallDurLive or 0) + 0.5)
    local combatDur
    if dmDur > 0 then
        combatDur = math.max(1, dmDur)
    elseif (run.combatSeconds or 0) > 0 then
        combatDur = math.max(1, run.combatSeconds)
    elseif (run.dmPullDurAccum or 0) > 0 then
        combatDur = math.max(1, math.floor(run.dmPullDurAccum + 0.5))
    else
        combatDur = duration
    end

    local dmLive = run.dmLiveByKey or {}
    local memberList = {}
    local roleRank = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }
    for _, m in pairs(run.membersByKey or {}) do
        local mDm = m.k and dmLive[m.k]
        if m.deaths and m.deaths > 0 then
            m.d = m.deaths
        end
        m.deaths = nil
        if mDm then
            if (mDm.dmg or 0) > 0 then
                m.dmg = mDm.dmg
                m.dps = math.floor((mDm.dmg / combatDur) + 0.5)
            end
            if (mDm.heal or 0) > 0 then
                m.heal = mDm.heal
                m.hps = math.floor((mDm.heal / combatDur) + 0.5)
            end
            if (mDm.tkn or 0) > 0 then m.tkn = mDm.tkn end
            if (mDm.intr or 0) > 0 then m.intr = mDm.intr end
            if (mDm.disp or 0) > 0 then m.disp = mDm.disp end
            if (mDm.d or 0) > (m.d or 0) then m.d = mDm.d end
        end
        memberList[#memberList + 1] = m
    end
    table.sort(memberList, function(a, b)
        local ra, rb = roleRank[a.r or "NONE"] or 4, roleRank[b.r or "NONE"] or 4
        if ra ~= rb then return ra < rb end
        return (a.n or "") < (b.n or "")
    end)
    while #memberList > MAX_RUN_MEMBERS do
        table.remove(memberList)
    end

    local _, rawMyClass = Safe.Call(UnitClass, "player")
    local myClass = run.myClass or Safe.String(rawMyClass)
    local myLevel = run.myLevel or Safe.Number(Safe.Call(UnitLevel, "player"))
    local realmPool = (Compat.RealmPool and Compat.RealmPool()) or ""

    local myDm = myKey and dmLive[myKey] or nil
    local totalDmg = (myDm and myDm.dmg) or 0
    local totalHeal = (myDm and myDm.heal) or 0
    local totalTaken = (myDm and myDm.tkn) or 0
    local totalIntr = (myDm and myDm.intr) or 0
    local totalDisp = (myDm and myDm.disp) or 0
    local sumDeaths = math.max(run.myDeaths or 0, (myDm and myDm.d) or 0)

    for _, m in ipairs(memberList) do
        totalDmg = totalDmg + (m.dmg or 0)
        totalHeal = totalHeal + (m.heal or 0)
        totalTaken = totalTaken + (m.tkn or 0)
        totalIntr = totalIntr + (m.intr or 0)
        totalDisp = totalDisp + (m.disp or 0)
        sumDeaths = sumDeaths + (m.d or 0)
    end
    local totalDeaths = math.max(run.totalDeaths or 0, sumDeaths)

    local dmSummary = nil
    if totalDmg > 0 or totalHeal > 0 or totalTaken > 0 or totalIntr > 0 or totalDisp > 0 then
        local myDmg = (myDm and myDm.dmg) or 0
        local myHeal = (myDm and myDm.heal) or 0
        dmSummary = {
            dmg = totalDmg,
            dps = math.floor((totalDmg / combatDur) + 0.5),
            heal = totalHeal,
            hps = math.floor((totalHeal / combatDur) + 0.5),
            tkn = totalTaken,
            intr = totalIntr,
            disp = totalDisp,
            myDmg = myDmg,
            myDps = (myDmg > 0) and math.floor((myDmg / combatDur) + 0.5) or 0,
            myHeal = myHeal,
            myHps = (myHeal > 0) and math.floor((myHeal / combatDur) + 0.5) or 0,
            myTkn = (myDm and myDm.tkn) or 0,
            myIntr = (myDm and myDm.intr) or 0,
            myDisp = (myDm and myDm.disp) or 0,
            myD = math.max(run.myDeaths or 0, (myDm and myDm.d) or 0),
            myRole = run.myRole,
        }
    end

    local rec = {
        id = tostring(startedAt) .. "-" .. tostring(math.random(1000, 9999)),
        z = run.zone or L["Instance"],
        t = run.instType or "party",
        diff = (run.difficultyName and run.difficultyName ~= "") and run.difficultyName or nil,
        st = startedAt,
        en = endedAt,
        dur = duration,
        cdur = (dmDur > 0 or (run.combatSeconds or 0) > 0) and combatDur or nil,
        pulls = (run.pulls and run.pulls > 0) and run.pulls or nil,
        bk = bossKills,
        bn = run.lastBossName,
        bs = (type(run.bosses) == "table" and #run.bosses > 0) and run.bosses or nil,
        wipes = (run.wipes and run.wipes > 0) and run.wipes or nil,
        dth = (totalDeaths > 0) and totalDeaths or nil,
        xp = (run.xpGained and run.xpGained > 0) and run.xpGained or nil,
        lvup = (run.levelsGained and run.levelsGained > 0) and run.levelsGained or nil,
        gold = (run.moneyGained and run.moneyGained > 0) and run.moneyGained or nil,
        loot = (type(run.loot) == "table" and #run.loot > 0) and run.loot or nil,
        dm = dmSummary,
        er = endReason,
        ch = myName,
        ck = myKey,
        cl = myClass,
        clv = myLevel,
        rl = realmPool,
        sz = math.max(#memberList + 1, run.peakSize or (#memberList + 1)),
        m = memberList,
    }

    local hist = self:GetDungeonHistoryTable()
    table.insert(hist, 1, rec)
    while #hist > MAX_DUNGEON_HISTORY do
        table.remove(hist)
    end

    ns:Emit("DUNGEON_HISTORY_UPDATED")
    ns:Emit("GROUP_UPDATED")

    if not silent then
        local durTxt = self:FormatRunDuration(duration)
        local kindLbl = (rec.t == "raid") and L["Raid"] or L["Dungeon"]
        ns:Print(L["%s logged: %s — %s (%d members). View in /sc runs"]:format(kindLbl, rec.z, durTxt, rec.sz))

        local promptShown = ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("dungeonLogPromptShown")
        if not promptShown and ns.SocialPanels and ns.SocialPanels.ShowDungeonLogFirstRunPrompt then
            local showFn = function()
                if ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("dungeonLogPromptShown") then
                    return
                end
                if ns.SocialPanels and ns.SocialPanels.ShowDungeonLogFirstRunPrompt then
                    ns.SocialPanels:ShowDungeonLogFirstRunPrompt(rec)
                end
            end
            if ns.RunAfterCombat then
                ns:RunAfterCombat("dungeon_log_first_prompt", showFn, false)
            else
                showFn()
            end
        end
    end

    return true, rec.id
end

local function SavePendingDungeonRunForReload(run, savedRecId)
    if type(SocialCentralCharDB) ~= "table" or not (run and run.started and savedRecId) then
        return
    end
    local membersCopy = {}
    for k, m in pairs(run.membersByKey or {}) do
        if type(m) == "table" then
            local dCount = m.deaths or m.d
            membersCopy[k] = {
                n = m.n,
                k = m.k,
                c = m.c,
                r = m.r,
                l = m.l,
                g = m.g,
                j = m.j,
                lv = m.lv,
                deaths = (dCount and dCount > 0) and dCount or nil,
            }
        end
    end
    local bossesCopy = {}
    for i = 1, #(run.bosses or {}) do
        bossesCopy[i] = run.bosses[i]
    end
    local lootCopy = {}
    for i = 1, #(run.loot or {}) do
        local it = run.loot[i]
        if type(it) == "table" then
            lootCopy[#lootCopy + 1] = { id = it.id, n = it.n, q = it.q, w = it.w }
        end
    end
    SocialCentralCharDB._pendingDungeonRun = {
        savedRecId = savedRecId,
        savedAt = time(),
        sig = run.sig,
        zone = run.zone,
        instType = run.instType,
        difficultyName = run.difficultyName,
        maxPlayers = run.maxPlayers,
        enteredAt = run.enteredAt,
        startedAt = run.startedAt,
        lastCombatAt = run.lastCombatAt,
        combatSeconds = run.combatSeconds or 0,
        pulls = run.pulls or 0,
        lastPullMetered = run.lastPullMetered,
        wipes = run.wipes or 0,
        totalDeaths = run.totalDeaths or 0,
        myDeaths = run.myDeaths or 0,
        xpGained = run.xpGained or 0,
        levelsGained = run.levelsGained or 0,
        moneyGained = run.moneyGained or 0,
        bossKills = run.bossKills or 0,
        lastBossName = run.lastBossName,
        bosses = bossesCopy,
        loot = lootCopy,
        membersByKey = membersCopy,
        myName = run.myName,
        myKey = run.myKey,
        myClass = run.myClass,
        myLevel = run.myLevel,
        myRole = run.myRole,
        myGuid = run.myGuid,
        peakSize = run.peakSize or 0,
        dmBaselineByKey = DeepCopyMetricsMap(run.dmBaselineByKey),
        dmResetAccumByKey = DeepCopyMetricsMap(run.dmResetAccumByKey),
        dmLiveByKey = DeepCopyMetricsMap(run.dmLiveByKey),
        dmLastOverallByKey = DeepCopyMetricsMap(run.dmLastOverallByKey),
        dmPullAccumByKey = DeepCopyMetricsMap(run.dmPullAccumByKey),
        dmOverallDurBase = run.dmOverallDurBase or 0,
        dmOverallDurResetAccum = run.dmOverallDurResetAccum or 0,
        dmOverallDurLive = run.dmOverallDurLive or 0,
        dmLastOverallDur = run.dmLastOverallDur or 0,
        dmPullDurAccum = run.dmPullDurAccum or 0,
        dmLastCurrentSessionSig = run.dmLastCurrentSessionSig,
    }
end

local function TryResumePendingDungeonRun(sig, instName, instType, diffName, maxPlayers)
    if type(SocialCentralCharDB) ~= "table" then return false end
    local pending = SocialCentralCharDB._pendingDungeonRun
    if type(pending) ~= "table" then return false end
    local now = time()
    if pending.sig ~= sig or (now - (pending.savedAt or 0)) > 1200 then
        SocialCentralCharDB._pendingDungeonRun = nil
        return false
    end

    if pending.savedRecId then
        local hist = Group:GetDungeonHistoryTable()
        for i = #hist, 1, -1 do
            if hist[i] and hist[i].id == pending.savedRecId then
                table.remove(hist, i)
                ns:Emit("DUNGEON_HISTORY_UPDATED")
                break
            end
        end
    end

    local bossSeen = {}
    local bosses = {}
    for i = 1, #(pending.bosses or {}) do
        local bn = pending.bosses[i]
        if bn and not bossSeen[bn] then
            bossSeen[bn] = true
            bosses[#bosses + 1] = bn
        end
    end

    local lootSeen = {}
    local loot = {}
    for i = 1, #(pending.loot or {}) do
        local it = pending.loot[i]
        if type(it) == "table" and it.id and it.n then
            local sk = tostring(it.id) .. ":" .. (it.w or "")
            if not lootSeen[sk] then
                lootSeen[sk] = true
                loot[#loot + 1] = { id = it.id, n = it.n, q = it.q, w = it.w }
            end
        end
    end

    local members = {}
    for k, m in pairs(pending.membersByKey or {}) do
        if type(m) == "table" then
            members[k] = {
                n = m.n,
                k = m.k,
                c = m.c,
                r = m.r,
                l = m.l,
                g = m.g,
                j = m.j,
                lv = m.lv,
                deaths = m.deaths,
            }
        end
    end

    Group._activeRun = {
        sig = sig,
        zone = (instName and instName ~= "") and instName or pending.zone,
        instType = instType or pending.instType,
        difficultyName = (diffName and diffName ~= "") and diffName or pending.difficultyName,
        maxPlayers = maxPlayers or pending.maxPlayers,
        enteredAt = pending.enteredAt or now,
        started = true,
        startedAt = pending.startedAt or pending.enteredAt or now,
        lastCombatAt = pending.lastCombatAt or now,
        combatSeconds = pending.combatSeconds or 0,
        combatStartedAt = nil,
        inCombatNow = false,
        pulls = pending.pulls or 0,
        lastPullMetered = pending.lastPullMetered,
        wipes = pending.wipes or 0,
        lastWipeAt = 0,
        totalDeaths = pending.totalDeaths or 0,
        myDeaths = pending.myDeaths or 0,
        deadStateByKey = {},
        lastDeathAtByKey = {},
        xpGained = pending.xpGained or 0,
        levelsGained = pending.levelsGained or 0,
        lastXp = Safe.Number(Safe.Call(UnitXP, "player")) or 0,
        lastXpMax = Safe.Number(Safe.Call(UnitXPMax, "player")) or 0,
        lastLevel = Safe.Number(Safe.Call(UnitLevel, "player")) or 0,
        moneyGained = pending.moneyGained or 0,
        lastMoney = Safe.Number(GetMoney and Safe.Call(GetMoney)) or 0,
        loot = loot,
        lootSeen = lootSeen,
        guidToKey = {},
        firstToKey = {},
        myName = pending.myName,
        myKey = pending.myKey,
        myClass = pending.myClass,
        myLevel = pending.myLevel,
        myRole = pending.myRole,
        myGuid = pending.myGuid or (UnitGUID and Safe.String(Safe.Call(UnitGUID, "player")) or nil),
        exitedAt = nil,
        pendingLeaveAt = nil,
        leftSinceCombat = 0,
        bossKills = pending.bossKills or 0,
        lastBossName = pending.lastBossName,
        bosses = bosses,
        bossSeen = bossSeen,
        membersByKey = members,
        presentKeys = {},
        peakSize = pending.peakSize or 0,
        _exitSeq = 0,
        _leaveSeq = 0,
        dmBaselineCaptured = true,
        dmBaselineByKey = DeepCopyMetricsMap(pending.dmBaselineByKey),
        dmResetAccumByKey = DeepCopyMetricsMap(pending.dmResetAccumByKey),
        dmLiveByKey = DeepCopyMetricsMap(pending.dmLiveByKey),
        dmLastOverallByKey = DeepCopyMetricsMap(pending.dmLastOverallByKey),
        dmPullAccumByKey = DeepCopyMetricsMap(pending.dmPullAccumByKey),
        dmOverallDurBase = pending.dmOverallDurBase or 0,
        dmOverallDurResetAccum = pending.dmOverallDurResetAccum or 0,
        dmOverallDurLive = pending.dmOverallDurLive or 0,
        dmLastOverallDur = pending.dmLastOverallDur or 0,
        dmPullDurAccum = pending.dmPullDurAccum or 0,
        dmLastCurrentSessionSig = pending.dmLastCurrentSessionSig,
    }
    SocialCentralCharDB._pendingDungeonRun = nil

    Group:CaptureActiveRunMembers(false)
    for _, mem in ipairs(Group.members or {}) do
        if mem and mem.isDead == true and mem.lookupKey then
            Group._activeRun.deadStateByKey[mem.lookupKey] = true
        end
    end
    UpdateDungeonRunDamageMeter(Group._activeRun, false)
    ns:Emit("GROUP_UPDATED")
    return true
end

function Group:CheckActiveDungeonRunZone()
    if not self:IsDungeonRunLogEnabled() then
        self._activeRun = nil
        return
    end
    local inInst, instType, instName, mapId, _, diffName, maxPlayers = IsInPartyOrRaidInstanceNow()
    local inGroup = Compat.IsInGroup()
    local run = self._activeRun

    if inInst and inGroup then
        local sig = tostring(instType) .. ":" .. tostring(mapId or instName)
        if run and run.sig == sig then
            -- Returned to same instance (e.g. after corpse run or quick summon): cancel pending exit finalize.
            run.exitedAt = nil
            run._exitSeq = (run._exitSeq or 0) + 1
            if diffName and diffName ~= "" and (not run.difficultyName or run.difficultyName == "") then
                run.difficultyName = diffName
            end
            self:CaptureActiveRunMembers(false)
            return
        end
        if run and run.started then
            self:FinalizeActiveDungeonRun("zone_change", false)
        end
        if TryResumePendingDungeonRun(sig, instName, instType, diffName, maxPlayers) then
            return
        end
        self._activeRun = {
            sig = sig,
            zone = instName,
            instType = instType,
            difficultyName = diffName,
            maxPlayers = maxPlayers,
            enteredAt = time(),
            started = false,
            startedAt = nil,
            lastCombatAt = nil,
            combatSeconds = 0,
            combatStartedAt = nil,
            inCombatNow = false,
            pulls = 0,
            wipes = 0,
            lastWipeAt = 0,
            totalDeaths = 0,
            myDeaths = 0,
            deadStateByKey = {},
            lastDeathAtByKey = {},
            xpGained = 0,
            levelsGained = 0,
            lastXp = Safe.Number(Safe.Call(UnitXP, "player")) or 0,
            lastXpMax = Safe.Number(Safe.Call(UnitXPMax, "player")) or 0,
            lastLevel = Safe.Number(Safe.Call(UnitLevel, "player")) or 0,
            moneyGained = 0,
            lastMoney = Safe.Number(GetMoney and Safe.Call(GetMoney)) or 0,
            loot = {},
            lootSeen = {},
            guidToKey = {},
            firstToKey = {},
            myGuid = UnitGUID and Safe.String(Safe.Call(UnitGUID, "player")) or nil,
            exitedAt = nil,
            pendingLeaveAt = nil,
            leftSinceCombat = 0,
            bossKills = 0,
            lastBossName = nil,
            bosses = {},
            bossSeen = {},
            membersByKey = {},
            presentKeys = {},
            peakSize = 0,
            _exitSeq = 0,
            _leaveSeq = 0,
        }
        self:CaptureActiveRunMembers(true)
        SnapshotDungeonRunDamageMeterBaseline(self._activeRun)
        return
    end

    if not run then
        if type(SocialCentralCharDB) == "table" and type(SocialCentralCharDB._pendingDungeonRun) == "table" then
            local pending = SocialCentralCharDB._pendingDungeonRun
            local isDeadOrGhost = UnitIsDeadOrGhost and Safe.Value(Safe.Call(UnitIsDeadOrGhost, "player")) == true
            if (not inGroup) or ((not isDeadOrGhost) and (time() - (pending.savedAt or 0)) > 30) then
                SocialCentralCharDB._pendingDungeonRun = nil
            elseif (not isDeadOrGhost) and C_Timer and C_Timer.After and not pending._cleanupTimerArmed then
                pending._cleanupTimerArmed = true
                C_Timer.After(32, function()
                    if not Group._activeRun then
                        Group:CheckActiveDungeonRunZone()
                    end
                end)
            end
        end
        return
    end

    if not run.started then
        -- Never pulled an enemy inside the dungeon: discard silently.
        self._activeRun = nil
        return
    end

    if not inGroup then
        self:FinalizeActiveDungeonRun("left_group", false)
        return
    end

    -- Still in group, stepped outside the instance: ignore corpse runs (ghost/dead)!
    local isDeadOrGhost = UnitIsDeadOrGhost and Safe.Value(Safe.Call(UnitIsDeadOrGhost, "player")) == true
    if isDeadOrGhost then
        return
    end

    run.exitedAt = run.exitedAt or time()
    if run.pendingLeaveAt then
        self:FinalizeActiveDungeonRun("member_left", false)
        return
    end
    run._exitSeq = (run._exitSeq or 0) + 1
    local eSeq = run._exitSeq
    if C_Timer and C_Timer.After then
        C_Timer.After(EXIT_GRACE_SECONDS, function()
            local cur = Group._activeRun
            if cur == run and cur._exitSeq == eSeq and cur.started and cur.exitedAt then
                local backIn = IsInPartyOrRaidInstanceNow()
                if not backIn then
                    Group:FinalizeActiveDungeonRun("exited_instance", false)
                end
            end
        end)
    end
end

function Group:OnActiveRunRosterUpdated(inGroupNow)
    local run = self._activeRun
    if not run then
        if not inGroupNow then
            if type(SocialCentralCharDB) == "table" and type(SocialCentralCharDB._pendingDungeonRun) == "table" then
                if (time() - (SocialCentralCharDB._pendingDungeonRun.savedAt or 0)) > 30 then
                    SocialCentralCharDB._pendingDungeonRun = nil
                end
            end
            return
        end
        if self:IsDungeonRunLogEnabled() then
            local inInst = IsInPartyOrRaidInstanceNow()
            if inInst then
                self:CheckActiveDungeonRunZone()
            end
        end
        return
    end
    if not inGroupNow then
        if run.started then
            self:FinalizeActiveDungeonRun("left_group", false)
        else
            self._activeRun = nil
        end
        return
    end
    self:CaptureActiveRunMembers(false)
end

function Group:OnDungeonRunCombatStart()
    if not self:IsDungeonRunLogEnabled() then return end
    local run = self._activeRun
    if not run then
        if Compat.IsInGroup() then
            local inInst = IsInPartyOrRaidInstanceNow()
            if inInst then
                self:CheckActiveDungeonRunZone()
                run = self._activeRun
            end
        end
        if not run then return end
    end
    local inInst = IsInPartyOrRaidInstanceNow()
    if not inInst then return end

    local now = time()
    run.exitedAt = nil
    run._exitSeq = (run._exitSeq or 0) + 1
    run.pendingLeaveAt = nil
    run.leftSinceCombat = 0
    run._leaveSeq = (run._leaveSeq or 0) + 1

    if not run.dmBaselineCaptured then
        SnapshotDungeonRunDamageMeterBaseline(run)
    end

    if not run.started then
        run.started = true
        run.startedAt = now
        run.lastXp = Safe.Number(Safe.Call(UnitXP, "player")) or run.lastXp or 0
        run.lastXpMax = Safe.Number(Safe.Call(UnitXPMax, "player")) or run.lastXpMax or 0
        run.lastLevel = Safe.Number(Safe.Call(UnitLevel, "player")) or run.lastLevel or 0
        run.lastMoney = Safe.Number(GetMoney and Safe.Call(GetMoney)) or run.lastMoney or 0
        self:CaptureActiveRunMembers(false)
    end

    if not run.inCombatNow then
        run.inCombatNow = true
        run.combatStartedAt = now
        run.pulls = (run.pulls or 0) + 1
    end
    ns:Emit("GROUP_UPDATED")
end

function Group:OnDungeonRunCombatEnd()
    local run = self._activeRun
    if not (run and run.started) then return end
    local now = time()
    if run.inCombatNow and run.combatStartedAt then
        run.combatSeconds = (run.combatSeconds or 0) + math.max(1, now - run.combatStartedAt)
        run.inCombatNow = false
        run.combatStartedAt = nil
    end
    if not run.exitedAt then
        run.lastCombatAt = now
    end
    UpdateDungeonRunDamageMeter(run, true)
    self:CheckDungeonRunDeaths()
    ns:Emit("GROUP_UPDATED")
end

function Group:OnDungeonRunEncounterStart(encName)
    self:OnDungeonRunCombatStart()
    local run = self._activeRun
    if run and encName and encName ~= "" then
        run.currentEncounter = encName
    end
end

function Group:OnDungeonRunEncounterEnd(encName, success)
    local run = self._activeRun
    if not run then return end
    local now = time()
    local okKill = Safe.Number(success) == 1
    if not okKill then
        if run.started and (now - (run.lastWipeAt or 0)) >= 15 then
            run.wipes = (run.wipes or 0) + 1
            run.lastWipeAt = now
        end
        UpdateDungeonRunDamageMeter(run, false)
        ns:Emit("GROUP_UPDATED")
        return
    end
    if not run.started then
        run.started = true
        run.startedAt = run.enteredAt or now
    end
    run.lastCombatAt = now
    run.lastBossAt = now
    run.bossKills = (run.bossKills or 0) + 1
    local cleanBoss = Safe.String(encName) or run.currentEncounter
    if cleanBoss and cleanBoss ~= "" then
        run.lastBossName = cleanBoss
        if not run.bossSeen[cleanBoss] and #(run.bosses or {}) < MAX_RUN_BOSSES then
            run.bossSeen[cleanBoss] = true
            run.bosses[#run.bosses + 1] = cleanBoss
        end
    end
    UpdateDungeonRunDamageMeter(run, false)
    ns:Emit("GROUP_UPDATED")
end

function Group:OpenGroupChatAnnouncement()
    local slash = self:GetChannelSlash()
    if not slash then
        ns:Print(L["You are not in a group."])
        return false
    end
    local comp = self:GetCompositionAnalysis()
    local counts = comp and comp.counts or self:GetSummaryCounts()
    local zone = Compat.CurrentZoneName()
    local cap = (Compat.IsInRaid and Compat.IsInRaid()) and 40 or 5
    local missPart = (comp and comp.missingRolesText and comp.missingRolesText ~= "")
        and (" (" .. L["Need"] .. ": " .. comp.missingRolesText .. ")")
        or ""
    local draft = string.format(
        "%s%s [%d/%d]: %dT / %dH / %dD%s%s",
        slash,
        L["Group"],
        counts.total,
        cap,
        counts.TANK,
        counts.HEALER,
        counts.DAMAGER,
        missPart,
        (zone and zone ~= "") and (" - " .. zone) or ""
    )
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        pcall(ChatFrameUtil.OpenChat, draft)
        return true
    elseif ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, draft)
        return true
    end
    return false
end

local RAID_BUFF_SPELLS = {
    FORT = {
        [1243] = true, [1244] = true, [1245] = true, [2791] = true,
        [10937] = true, [10938] = true, [21562] = true, [21564] = true,
    },
    INT = {
        [1459] = true, [1460] = true, [1461] = true, [10156] = true,
        [10157] = true, [23028] = true,
    },
    MOTW = {
        [1126] = true, [5232] = true, [6756] = true, [5234] = true,
        [8907] = true, [9884] = true, [9885] = true, [21849] = true, [21850] = true,
    },
}

local MANA_CLASSES = {
    PRIEST = true, MAGE = true, WARLOCK = true, DRUID = true,
    PALADIN = true, SHAMAN = true, HUNTER = true,
}

local function UnitHasTrackedBuff(unit, buffKey)
    if not (C_UnitAuras and (C_UnitAuras.GetAuraDataByIndex or C_UnitAuras.GetBuffDataByIndex)) then
        return true
    end
    local spellMap = RAID_BUFF_SPELLS[buffKey]
    for idx = 1, 40 do
        local ok, aura
        if C_UnitAuras.GetAuraDataByIndex then
            ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, idx, "HELPFUL")
        else
            ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, unit, idx)
        end
        if not ok or not aura then
            break
        end
        local sid = Safe.Number(aura.spellId)
        if sid and spellMap and spellMap[sid] then
            return true
        end
        local nm = Safe.String(aura.name)
        if nm and nm ~= "" then
            local low = nm:lower()
            if buffKey == "FORT" and (low:find("fortitude", 1, true) or low:find("entereza", 1, true)) then
                return true
            elseif buffKey == "INT" and (low:find("intellect", 1, true) or low:find("brilliance", 1, true) or low:find("intelecto", 1, true) or low:find("brilho", 1, true)) then
                return true
            elseif buffKey == "MOTW" and (low:find("wild", 1, true) or low:find("selvagem", 1, true) or low:find("salvaje", 1, true)) then
                return true
            end
        end
    end
    return false
end

function Group:GetMissingRaidBuffsAudit()
    local units = { "player" }
    local inRaid = Compat.IsInRaid and Compat.IsInRaid()
    if inRaid then
        local total = GetNumGroupMembers and Safe.Number(Safe.Call(GetNumGroupMembers)) or 0
        units = {}
        for i = 1, math.min(total, 40) do
            units[#units + 1] = "raid" .. i
        end
    elseif IsInGroup and Safe.Call(IsInGroup) == true then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists and UnitExists(u) then
                units[#units + 1] = u
            end
        end
    else
        return { missingCount = 0, detailLines = {}, summaryText = "" }
    end

    local hasPriest, hasMage, hasDruid = false, false, false
    local roster = {}
    for _, u in ipairs(units) do
        if UnitExists and UnitExists(u) and UnitIsConnected and Safe.Call(UnitIsConnected, u) == true then
            local _, cls = Safe.Call(UnitClass, u)
            cls = Safe.String(cls)
            local rawName = Safe.String(Safe.Call(UnitName, u))
            local resolved = rawName and Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(u, nil, rawName, true)
            local disp = (resolved and resolved.fullName) or rawName or "?"
            if cls == "PRIEST" then hasPriest = true end
            if cls == "MAGE" then hasMage = true end
            if cls == "DRUID" then hasDruid = true end
            local isDead = UnitIsDeadOrGhost and Safe.Call(UnitIsDeadOrGhost, u) == true
            if not isDead then
                roster[#roster + 1] = { unit = u, name = disp, classFile = cls }
            end
        end
    end

    local missFort, missInt, missMotw = {}, {}, {}
    for _, m in ipairs(roster) do
        if hasPriest and not UnitHasTrackedBuff(m.unit, "FORT") then
            missFort[#missFort + 1] = m.name
        end
        if hasMage and MANA_CLASSES[m.classFile] and not UnitHasTrackedBuff(m.unit, "INT") then
            missInt[#missInt + 1] = m.name
        end
        if hasDruid and not UnitHasTrackedBuff(m.unit, "MOTW") then
            missMotw[#missMotw + 1] = m.name
        end
    end

    local detailLines = {}
    local draftParts = {}
    local totalMiss = 0
    local function pushMiss(lbl, list)
        if #list > 0 then
            totalMiss = totalMiss + #list
            local joined = table.concat(list, ", ")
            if #list > 6 then
                joined = table.concat({ list[1], list[2], list[3], list[4], list[5] }, ", ") .. " (+" .. tostring(#list - 5) .. ")"
            end
            detailLines[#detailLines + 1] = { buff = lbl, count = #list, players = joined }
            draftParts[#draftParts + 1] = lbl .. " (" .. tostring(#list) .. ": " .. joined .. ")"
        end
    end
    pushMiss(L["Fortitude"], missFort)
    pushMiss(L["Arcane Intellect"], missInt)
    pushMiss(L["Mark of the Wild"], missMotw)

    local summary = ""
    if #draftParts > 0 then
        summary = L["Missing Buffs"] .. ": " .. table.concat(draftParts, " | ")
        if #summary > 235 then
            summary = summary:sub(1, 232) .. "..."
        end
    end
    return {
        missingCount = totalMiss,
        detailLines = detailLines,
        summaryText = summary,
    }
end

local WORLD_BUFF_DEFS = {
    { id = "DRAG", labelKey = "Dragonslayer", spells = { [22888] = true }, terms = { "dragonslayer", "mata-drag", "matadrag", "oni" } },
    { id = "ZAND", labelKey = "Zandalar", spells = { [24425] = true }, terms = { "zandalar" } },
    { id = "SONG", labelKey = "Songflower", spells = { [15366] = true }, terms = { "songflower", "flor-da-can", "flor de can" } },
    { id = "WARCHIEF", labelKey = "Warchief", spells = { [16609] = true }, terms = { "warchief", "chefe guerreiro", "jefe de guerra" } },
    { id = "DM", labelKey = "Dire Maul", spells = { [22817] = true, [22818] = true, [22820] = true }, terms = { "fengus", "mol'dar", "slip'kik" } },
    { id = "DMF", labelKey = "Darkmoon", spells = { [23768] = true, [23766] = true, [23767] = true, [23769] = true, [23735] = true, [23736] = true, [23737] = true, [23738] = true }, terms = { "sayge" } },
    { id = "BOON", labelKey = "Chronoboon", spells = { [349981] = true }, terms = { "chronoboon", "cronobon", "supercharged chronoboon" }, isBoon = true },
}

local function ScanUnitWorldBuffs(unit)
    if not (C_UnitAuras and (C_UnitAuras.GetAuraDataByIndex or C_UnitAuras.GetBuffDataByIndex)) then
        return 0, false, {}
    end
    local seen = {}
    local activeLabels = {}
    local hasBoon = false
    for idx = 1, 40 do
        local ok, aura
        if C_UnitAuras.GetAuraDataByIndex then
            ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, idx, "HELPFUL")
        else
            ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, unit, idx)
        end
        if not ok or not aura then
            break
        end
        local sid = Safe.Number(aura.spellId)
        local nm = Safe.String(aura.name)
        local low = nm and nm:lower() or nil
        for _, def in ipairs(WORLD_BUFF_DEFS) do
            if not seen[def.id] then
                local matched = (sid and def.spells[sid] == true) or false
                if (not matched) and low and low ~= "" then
                    for _, term in ipairs(def.terms) do
                        if low:find(term, 1, true) then
                            matched = true
                            break
                        end
                    end
                end
                if matched then
                    seen[def.id] = true
                    if def.isBoon then
                        hasBoon = true
                    else
                        activeLabels[#activeLabels + 1] = L[def.labelKey]
                    end
                end
            end
        end
    end
    return #activeLabels, hasBoon, activeLabels
end

function Group:GetWorldBuffsAudit()
    local units = { "player" }
    local inRaid = Compat.IsInRaid and Compat.IsInRaid()
    if inRaid then
        local total = GetNumGroupMembers and Safe.Number(Safe.Call(GetNumGroupMembers)) or 0
        units = {}
        for i = 1, math.min(total, 40) do
            units[#units + 1] = "raid" .. i
        end
    elseif IsInGroup and Safe.Call(IsInGroup) == true then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists and UnitExists(u) then
                units[#units + 1] = u
            end
        end
    else
        return { totalMembers = 0, withActiveCount = 0, withBoonCount = 0, rows = {} }
    end

    local rows = {}
    local withActive, withBoon = 0, 0
    for _, u in ipairs(units) do
        if UnitExists and UnitExists(u) and UnitIsConnected and Safe.Call(UnitIsConnected, u) == true then
            local _, cls = Safe.Call(UnitClass, u)
            cls = Safe.String(cls)
            local rawName = Safe.String(Safe.Call(UnitName, u))
            local resolved = rawName and Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(u, nil, rawName, true)
            local disp = (resolved and resolved.fullName) or rawName or "?"
            local activeCnt, hasBoon, labels = ScanUnitWorldBuffs(u)
            if activeCnt > 0 then withActive = withActive + 1 end
            if hasBoon then withBoon = withBoon + 1 end
            rows[#rows + 1] = {
                name = disp,
                classFile = cls,
                activeCount = activeCnt,
                hasBoon = hasBoon,
                buffsText = (#labels > 0) and table.concat(labels, ", ") or "",
            }
        end
    end
    table.sort(rows, function(a, b)
        if (a.activeCount or 0) ~= (b.activeCount or 0) then
            return (a.activeCount or 0) > (b.activeCount or 0)
        end
        if (a.hasBoon == true) ~= (b.hasBoon == true) then
            return a.hasBoon == true
        end
        return tostring(a.name or "") < tostring(b.name or "")
    end)
    return {
        totalMembers = #rows,
        withActiveCount = withActive,
        withBoonCount = withBoon,
        rows = rows,
    }
end

function Group:OpenMissingBuffsDraft()
    local slash = self:GetChannelSlash()
    if not slash then
        ns:Print("%s", L["You are not in a group."])
        return false
    end
    local audit = self:GetMissingRaidBuffsAudit()
    if not audit or audit.missingCount == 0 or audit.summaryText == "" then
        ns:Print("%s", L["All covered raid buffs are already active on everyone!"])
        return false
    end
    local fullDraft = slash .. audit.summaryText
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        pcall(ChatFrameUtil.OpenChat, fullDraft)
        return true
    elseif ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, fullDraft)
        return true
    end
    return false
end

local function QueueScan()
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(0.25, function()
        scanQueued = false
        Group:Scan()
    end)
end

local instanceCheckQueued = false
local function QueueInstanceEntryCheck()
    if instanceCheckQueued then return end
    instanceCheckQueued = true
    C_Timer.After(1.5, function()
        instanceCheckQueued = false
        Group:RecordCurrentInstanceEntry()
        Group:CheckActiveDungeonRunZone()
    end)
end

local resetSuccessPattern = nil
local function IsInstanceResetSystemMessage(msg)
    if type(msg) ~= "string" or msg == "" then return false end
    if not resetSuccessPattern and type(_G.INSTANCE_RESET_SUCCESS) == "string" and _G.INSTANCE_RESET_SUCCESS ~= "" then
        local esc = _G.INSTANCE_RESET_SUCCESS:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        resetSuccessPattern = "^" .. esc:gsub("%%%%s", ".+") .. "$"
    end
    if resetSuccessPattern and msg:find(resetSuccessPattern) then
        return true
    end
    return false
end

function Group:Init()
    for _, ev in ipairs({
        "GROUP_ROSTER_UPDATE",
        "PARTY_MEMBERS_CHANGED",
        "RAID_ROSTER_UPDATE",
        "PARTY_LEADER_CHANGED",
        "UNIT_CONNECTION",
        "ROLE_CHANGED_INFORM",
    }) do
        ns.RegisterEvent(self, ev, QueueScan)
    end

    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        QueueScan()
        QueueInstanceEntryCheck()
    end)

    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", QueueInstanceEntryCheck)

    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        Group:OnDungeonRunCombatStart()
    end)

    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        Group:OnDungeonRunCombatEnd()
    end)

    ns.RegisterEvent(self, "ENCOUNTER_START", function(_, _, _, encName)
        Group:OnDungeonRunEncounterStart(Safe.String(encName))
    end)

    ns.RegisterEvent(self, "ENCOUNTER_END", function(_, _, _, encName, _, _, success)
        Group:OnDungeonRunEncounterEnd(Safe.String(encName), success)
    end)

    ns.RegisterEvent(self, "CHAT_MSG_SYSTEM", function(_, _, rawMsg)
        if not (Group._activeRun and Group._activeRun.started) then
            return
        end
        local cleanMsg = Safe.String(rawMsg)
        if cleanMsg and IsInstanceResetSystemMessage(cleanMsg) then
            Group:FinalizeActiveDungeonRun("instance_reset", false)
        end
    end)

    ns.RegisterEvent(self, "PLAYER_LOGOUT", function()
        local activeRun = Group._activeRun
        if activeRun and activeRun.started then
            local ok, savedRecId = Group:FinalizeActiveDungeonRun("logout", true)
            if ok and savedRecId then
                SavePendingDungeonRunForReload(activeRun, savedRecId)
            end
        end
    end)

    ns.RegisterEvent(self, "PLAYER_DEAD", function()
        if Group._activeRun and Group._activeRun.started then
            Group:CheckDungeonRunDeaths("player")
        end
    end)

    ns.RegisterEvent(self, "UNIT_FLAGS", function(_, _, unit)
        if not (Group._activeRun and Group._activeRun.started) then
            return
        end
        if type(unit) ~= "string" then return end
        if unit == "player" or unit:sub(1, 5) == "party" or unit:sub(1, 4) == "raid" then
            Group:CheckDungeonRunDeaths(unit)
        end
    end)

    ns.RegisterEvent(self, "PLAYER_XP_UPDATE", function()
        if Group._activeRun and Group._activeRun.started then
            Group:OnDungeonRunXpUpdate(nil)
        end
    end)

    ns.RegisterEvent(self, "PLAYER_LEVEL_UP", function(_, _, newLevel)
        if Group._activeRun and Group._activeRun.started then
            Group:OnDungeonRunXpUpdate(newLevel)
        end
    end)

    ns.RegisterEvent(self, "PLAYER_MONEY", function()
        if Group._activeRun and Group._activeRun.started then
            Group:OnDungeonRunMoneyUpdate()
        end
    end)

    ns.RegisterEvent(self, "ENCOUNTER_LOOT_RECEIVED", function(_, _, _, itemID, itemLink, _, playerName)
        if Group._activeRun and Group._activeRun.started then
            Group:OnDungeonRunLootEvent(Safe.String(itemLink), Safe.String(playerName), true, itemID)
        end
    end)

    ns.RegisterEvent(self, "CHAT_MSG_LOOT", function(_, _, rawMsg, looterName)
        if not (Group._activeRun and Group._activeRun.started) then
            return
        end
        local cleanMsg = Safe.String(rawMsg)
        if cleanMsg and cleanMsg:find("|Hitem:", 1, true) then
            Group:OnDungeonRunLootEvent(cleanMsg, Safe.String(looterName), false, nil)
        end
    end)

    ns.RegisterEvent(self, "DAMAGE_METER_COMBAT_SESSION_UPDATED", function()
        if Group._activeRun and Group._activeRun.started then
            UpdateDungeonRunDamageMeter(Group._activeRun, false)
        end
    end)

    ns.RegisterEvent(self, "DAMAGE_METER_RESET", function()
        OnDungeonRunDamageMeterReset()
    end)

    ns.RegisterEvent(self, "READY_CHECK", function()
        Group.readyCheckActive = true
        Group.readyStates = {}
        Group.readyStatesByGuid = {}
        QueueScan()
        local s = ns.db and ns.db.settings
        local modOn = (not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("group")
        if modOn and (not s or s.groupReadyCheckAudit ~= false) then
            local audit = Group:GetMissingRaidBuffsAudit()
            if audit and audit.missingCount > 0 and audit.summaryText ~= "" then
                ns:Print("|cffffd24d[%s]|r %s  |Haddon:SCentral:buffaudit|h|cff58a6ff[%s]|r|h",
                    L["Ready Check"],
                    audit.summaryText,
                    L["Announce Missing Buffs"])
            end
        end
    end)

    ns.RegisterEvent(self, "READY_CHECK_CONFIRM", function(_, _, unit, confirm)
        if not unit then return end
        local guid = Safe.String(Safe.Call(UnitGUID, unit))
        local existingName = nil
        if Group.members then
            for i = 1, #Group.members do
                local m = Group.members[i]
                if m and ((guid and m.guid == guid) or m.unit == unit) and m.displayName then
                    existingName = m.displayName
                    break
                end
            end
        end
        local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(unit, guid, existingName, true)
        local rawName = (resolved and resolved.fullName)
            or Safe.String(Safe.Call(GetUnitName, unit, true))
            or Safe.String(Safe.Call(UnitName, unit))
        local parsed = rawName and Compat.ParseCharacterName(rawName)
        local isReady = Safe.Value(confirm) == true
        Group.readyStatesByGuid = Group.readyStatesByGuid or {}
        if guid then
            Group.readyStatesByGuid[guid] = isReady
        end
        if parsed and parsed.lookupKey then
            Group.readyStates[parsed.lookupKey] = isReady
        end
        if guid or (parsed and parsed.lookupKey) then
            QueueScan()
        end
    end)

    ns.RegisterEvent(self, "READY_CHECK_FINISHED", function()
        Group.readyCheckActive = false
        QueueScan()
    end)

    C_Timer.After(1.5, QueueScan)
end
