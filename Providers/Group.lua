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
}

ns.Group = Group
table.insert(ns.modules, Group)

local scanQueued = false

function Group:GetChannelName()
    if not (IsInGroup and Safe.Value(IsInGroup())) then
        return nil
    end
    if LE_PARTY_CATEGORY_INSTANCE and Safe.Value(IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and Safe.Value(IsInRaid()) then
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
    local inGroup = IsInGroup and Safe.Value(IsInGroup()) == true
    if not inGroup then
        self.members = {}
        self.readyCheckActive = false
        self.readyStates = {}
        ns:Emit("GROUP_UPDATED")
        return
    end

    local inRaid = IsInRaid and Safe.Value(IsInRaid()) == true
    local numMembers = Safe.Number(Safe.Call(GetNumGroupMembers)) or 0
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

    local seen = {}
    for _, unit in ipairs(unitTokens) do
        if UnitExists and Safe.Value(UnitExists(unit)) == true then
            local rawName = Safe.String(Safe.Call(GetUnitName, unit, true)) or Safe.String(Safe.Call(UnitName, unit))
            local guid = Safe.String(Safe.Call(UnitGUID, unit))
            local parsed = rawName and Compat.ParseCharacterName(rawName)
            if parsed and not seen[parsed.lookupKey] then
                seen[parsed.lookupKey] = true
                local _, classFile = Safe.Call(UnitClass, unit)
                classFile = Safe.String(classFile)
                local level = Safe.Number(Safe.Call(UnitLevel, unit))
                local role = NormalizeRole(Safe.String(Safe.Call(UnitGroupRolesAssigned, unit)))
                local online = not UnitIsConnected or Safe.Value(UnitIsConnected(unit)) ~= false
                local isLeader = UnitIsGroupLeader and Safe.Value(UnitIsGroupLeader(unit)) == true
                local isMe = Compat.IsMe(rawName, guid)

                local item = {
                    unit = unit,
                    guid = guid,
                    displayName = parsed.displayName,
                    lookupKey = parsed.lookupKey,
                    classFile = classFile,
                    level = (level and level > 0) and level or nil,
                    role = role,
                    online = online,
                    isLeader = isLeader,
                    isMe = isMe,
                    ready = self.readyStates[parsed.lookupKey],
                    zone = currentZone,
                }
                table.insert(nextList, item)

                if not isMe and Store and Store.RecordCompanion then
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

    local roleRank = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }
    table.sort(nextList, function(a, b)
        if a.isLeader ~= b.isLeader then return a.isLeader end
        local ra, rb = roleRank[a.role] or 4, roleRank[b.role] or 4
        if ra ~= rb then return ra < rb end
        return (a.displayName or "") < (b.displayName or "")
    end)

    self.members = nextList
    ns:Emit("GROUP_UPDATED")
end

function Group:GetMembers()
    return self.members or {}
end

function Group:GetSummaryCounts()
    local counts = { total = 0, TANK = 0, HEALER = 0, DAMAGER = 0, NONE = 0, online = 0 }
    for _, m in ipairs(self.members or {}) do
        counts.total = counts.total + 1
        if m.online then counts.online = counts.online + 1 end
        counts[m.role or "NONE"] = (counts[m.role or "NONE"] or 0) + 1
    end
    return counts
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
    if not (IsInGroup and Safe.Value(IsInGroup())) then
        ns:Print(L["You are not in a group."])
        return false
    end
    local canLead = (UnitIsGroupLeader and Safe.Value(UnitIsGroupLeader("player"))) or
        (UnitIsGroupAssistant and Safe.Value(UnitIsGroupAssistant("player")))
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
    if not (UnitIsGroupLeader and Safe.Value(UnitIsGroupLeader("player"))) then
        ns:Print(L["Only the group leader can promote another member."])
        return false
    end
    if unit and PromoteToLeader then
        pcall(PromoteToLeader, unit)
        return true
    end
    return false
end

function Group:OpenGroupChatAnnouncement()
    local slash = self:GetChannelSlash()
    if not slash then
        ns:Print(L["You are not in a group."])
        return false
    end
    local counts = self:GetSummaryCounts()
    local zone = Compat.CurrentZoneName()
    local draft = string.format(
        "%s%s: %d (%dT / %dH / %dD)%s",
        slash,
        L["Group"],
        counts.total,
        counts.TANK,
        counts.HEALER,
        counts.DAMAGER,
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

function Group:Init()
    for _, ev in ipairs({
        "PLAYER_ENTERING_WORLD",
        "GROUP_ROSTER_UPDATE",
        "PARTY_LEADER_CHANGED",
        "UNIT_CONNECTION",
        "ROLE_CHANGED_INFORM",
    }) do
        ns.RegisterEvent(self, ev, QueueScan)
    end

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
