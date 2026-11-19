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
        self._avoidNotified = {}
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

    local raidMetaByLookup = {}
    if inRaid and GetRaidRosterInfo then
        for rIdx = 1, numMembers do
            local okR, rName, _, rSub, _, _, _, _, _, rDead, rCombatRole, rIsML = pcall(GetRaidRosterInfo, rIdx)
            if okR and rName then
                local cleanRName = Safe.String(rName)
                local rParsed = cleanRName and Compat.ParseCharacterName(cleanRName)
                if rParsed and rParsed.lookupKey then
                    local cleanRole = Safe.String(rCombatRole)
                    if cleanRole ~= "MAINTANK" and cleanRole ~= "MAINASSIST" then
                        cleanRole = nil
                    end
                    raidMetaByLookup[rParsed.lookupKey] = {
                        subgroup = Safe.Number(rSub) or 1,
                        isDead = (rDead == true),
                        combatRole = cleanRole,
                        isML = (rIsML == true),
                    }
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
                local rMeta = raidMetaByLookup[parsed.lookupKey]
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
                    ready = self.readyStates[parsed.lookupKey],
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
                            if meta and meta.flag == "AVOID" then
                                self._avoidNotified[alertKey] = true
                                local noteText = (meta.note and meta.note ~= "") and (L["Note: %s"]:format(meta.note)) or L["In your group! Flagged as Avoid."]
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
        if a.isLeader ~= b.isLeader then return a.isLeader end
        if (a.subgroup or 1) ~= (b.subgroup or 1) then return (a.subgroup or 1) < (b.subgroup or 1) end
        local ra, rb = roleRank[a.role] or 4, roleRank[b.role] or 4
        if ra ~= rb then return ra < rb end
        return (a.displayName or "") < (b.displayName or "")
    end)

    self.members = nextList
    self._compCache = nil
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
        local needT = math.max(0, 1 - (counts.TANK or 0))
        local needH = math.max(0, 1 - (counts.HEALER or 0))
        local needD = math.max(0, 3 - (counts.DAMAGER or 0))
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
    for _, rec in ipairs(all) do
        local isCurrent = inGroupKeys[rec.lookupKey] == true
        if not q or ((rec.displayName or "") .. " " .. (rec.zone or "")):lower():find(q, 1, true) then
            local copy = {}
            for k, v in pairs(rec) do copy[k] = v end
            copy.inCurrentGroup = isCurrent
            table.insert(out, copy)
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
    if ns.db then
        ns.db._lastInstanceActiveSig = nil
    end
    self._activeInstanceSig = nil
    ns:Print(L["Dungeon instances have been reset."])
    ns:Emit("GROUP_UPDATED")
    ns:Emit("CLAN_UPDATED")
    return true
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
    end)
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

    ns.RegisterEvent(self, "READY_CHECK", function()
        Group.readyCheckActive = true
        Group.readyStates = {}
        QueueScan()
    end)

    ns.RegisterEvent(self, "READY_CHECK_CONFIRM", function(_, _, unit, confirm)
        local rawName = unit and Safe.String(Safe.Call(UnitName, unit))
        local parsed = rawName and Compat.ParseCharacterName(rawName)
        if parsed then
            Group.readyStates[parsed.lookupKey] = Safe.Value(confirm) == true
            QueueScan()
        end
    end)

    ns.RegisterEvent(self, "READY_CHECK_FINISHED", function()
        Group.readyCheckActive = false
        QueueScan()
    end)

    C_Timer.After(1.5, QueueScan)
end
