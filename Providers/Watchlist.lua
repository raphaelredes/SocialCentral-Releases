local _, ns = ...

local L = ns.L
local Safe = ns.Safe
local Compat = ns.Compat
local Store = ns.Store

-- Custom Watchlist with Blizzard-safe /who querying:
--   1. Hardware-event compliant: SendWho is only invoked inside direct user clicks/slash runs.
--   2. Combat-safe: /who is refused during InCombatLockdown() to eliminate UI taint risks.
--   3. Dual silent mode:
--        - "silent_ui" (default): borrows WHO_LIST_UPDATE from FriendsFrame ONLY outside combat
--          when FriendsFrame is closed, and always restores on WHO_LIST_UPDATE, timeout, or OnShow.
--        - "chat_filter": uses SetWhoToUi(false) and filters CHAT_MSG_SYSTEM without touching FriendsFrame.
local Watchlist = {
    lastWhoSentAt = 0,
    backoffUntil = 0,
    pending = nil,        -- { id, firstName, surname, displayName, mode, token }
    friendsBorrowed = false,
    needsFriendsRestore = false,
    onShowHooked = false,
    chatFilterActive = false,
    tokenCounter = 0,
}

ns.Watchlist = Watchlist
table.insert(ns.modules, Watchlist)

local function GetCooldownSeconds()
    local val = ns.db and ns.db.settings and ns.db.settings.whoCooldown
    return math.max(5, tonumber(val) or 6)
end

local function GetWhoMode()
    local mode = ns.db and ns.db.settings and ns.db.settings.whoMode
    if mode == "chat_filter" then return "chat_filter" end
    return "silent_ui"
end

local function RestoreFriendsFrameEvent()
    if not (Watchlist.friendsBorrowed or Watchlist.needsFriendsRestore) or not FriendsFrame then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        -- Defer RegisterEvent until combat ends to guarantee zero UI taint risk.
        Watchlist.friendsBorrowed = false
        Watchlist.needsFriendsRestore = true
        return
    end
    Watchlist.friendsBorrowed = false
    Watchlist.needsFriendsRestore = false
    pcall(FriendsFrame.RegisterEvent, FriendsFrame, "WHO_LIST_UPDATE")
end

local function AddChatFilter(fn)
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        pcall(ChatFrameUtil.AddMessageEventFilter, "CHAT_MSG_SYSTEM", fn)
    elseif ChatFrame_AddMessageEventFilter then
        pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_SYSTEM", fn)
    end
end

local function RemoveChatFilter(fn)
    if ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter then
        pcall(ChatFrameUtil.RemoveMessageEventFilter, "CHAT_MSG_SYSTEM", fn)
    elseif ChatFrame_RemoveMessageEventFilter then
        pcall(ChatFrame_RemoveMessageEventFilter, "CHAT_MSG_SYSTEM", fn)
    end
end

local function SystemChatFilter(_, _, msg)
    if not Watchlist.pending or Watchlist.pending.mode ~= "chat_filter" then
        return false
    end
    local clean = Safe.String(msg)
    if not clean then return false end

    -- Only match genuine /who output formats so unrelated system messages stay visible.
    local playerLink = clean:match("^|Hplayer:([^|]+)|h%[.-%]:")
    if playerLink then
        local parsed = Compat.ParseCharacterName(playerLink)
        if parsed then
            Watchlist.pending.chatMatches = Watchlist.pending.chatMatches or {}
            table.insert(Watchlist.pending.chatMatches, {
                parsed = parsed,
                rawLine = clean,
            })
        end
        return true
    end

    -- Suppress trailing /who summary line ("0 players total" / "Total: 0 jogadores") during active query.
    local lower = clean:lower()
    local looksLikeWhoSummary = clean:find("%d+") and (lower:find("total") or lower:find("player") or lower:find("jogador") or lower:find("jugador"))
    if looksLikeWhoSummary then
        Watchlist.pending.sawSummary = true
        C_Timer.After(0.05, function()
            if Watchlist.pending and Watchlist.pending.mode == "chat_filter" then
                Watchlist:FinishChatFilterQuery()
            end
        end)
        return true
    end

    return false
end

local function CleanupPending()
    local wasSilentUi = Watchlist.pending and Watchlist.pending.mode == "silent_ui"
    RestoreFriendsFrameEvent()
    if wasSilentUi then
        if C_FriendList and C_FriendList.SetWhoToUi then
            pcall(C_FriendList.SetWhoToUi, false)
        elseif SetWhoToUI then
            pcall(SetWhoToUI, 0)
        end
    end
    if Watchlist.chatFilterActive then
        Watchlist.chatFilterActive = false
        RemoveChatFilter(SystemChatFilter)
    end
    Watchlist.pending = nil
end

function Watchlist:GetCooldownRemaining()
    local now = GetTime()
    local cd = GetCooldownSeconds()
    local elapsed = now - (self.lastWhoSentAt or 0)
    local standardRem = math.max(0, cd - elapsed)
    local backoffRem = math.max(0, (self.backoffUntil or 0) - now)
    local rem = math.max(standardRem, backoffRem)
    if rem <= 0 then return 0 end
    return math.ceil(rem)
end

function Watchlist:IsBusy()
    return self.pending ~= nil
end

function Watchlist:Add(rawName, note)
    local parsed = Compat.ParseCharacterName(rawName)
    if not parsed or #(parsed.firstName or "") < 2 then return false, "invalid" end

    local list = Store:GetWatchlistTable()
    if list[parsed.lookupKey] then
        ns:Print(L["%s is already on your Watchlist."]:format(parsed.displayName))
        return false, "duplicate"
    end

    local cleanNote = Compat.CleanInput(note or "") or ""
    list[parsed.lookupKey] = {
        id = parsed.lookupKey,
        displayName = parsed.displayName,
        firstName = parsed.firstName,
        surname = parsed.surname,
        note = cleanNote,
        status = "unknown",
        source = nil,
        level = nil,
        classFile = nil,
        area = nil,
        guild = nil,
        lastChecked = nil,
        lastSeen = nil,
        addedAt = time(),
    }

    ns:Print(L["Added %s to your Watchlist."]:format(parsed.displayName))
    ns:Emit("WATCHLIST_UPDATED")
    return true, list[parsed.lookupKey]
end

function Watchlist:AddTarget()
    local isPlayer = Safe.Value(Safe.Call(UnitIsPlayer, "target"))
    if isPlayer ~= true then
        ns:Print(L["Select a valid player target first."])
        return false
    end

    local rawName = Safe.String(Safe.Call(UnitName, "target"))
    local guid = Safe.String(Safe.Call(UnitGUID, "target"))
    if not rawName or Compat.IsMe(rawName, guid) then
        ns:Print(L["Select a valid player target first."])
        return false
    end

    local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName("target", guid)
    local fullName = resolved and resolved.fullName or rawName
    local ok, entry = self:Add(fullName)
    if not ok then
        entry = self:GetEntry(fullName)
    end
    if entry then
        entry.guid = guid or entry.guid
        local _, classFile = Safe.Call(UnitClass, "target")
        if classFile then entry.classFile = Safe.String(classFile) end
        local lvl = Safe.Number(Safe.Call(UnitLevel, "target"))
        if lvl and lvl > 0 then entry.level = lvl end
        local area = Compat.CurrentZoneName()
        if area and area ~= "" then entry.area = area end
        if GetGuildInfo then
            local gOk, gName = pcall(GetGuildInfo, "target")
            if gOk and gName then entry.guild = Safe.String(gName) end
        end
        entry.status = "online"
        entry.source = "target"
        entry.lastSeen = time()
        ns:Emit("WATCHLIST_UPDATED")
        return true
    end
    return ok
end

function Watchlist:GetEntry(nameOrKey)
    if not nameOrKey then return nil end
    local list = Store:GetWatchlistTable()
    if list[nameOrKey] then return list[nameOrKey] end
    local parsed = Compat.ParseCharacterName(nameOrKey)
    if parsed and list[parsed.lookupKey] then
        return list[parsed.lookupKey]
    end
    local low = tostring(nameOrKey):lower()
    for _, e in pairs(list) do
        if e.id == low or (e.lookupKey and e.lookupKey == low)
            or (e.displayName and e.displayName:lower() == low)
            or (e.firstName and e.firstName:lower() == low) then
            return e
        end
    end
    return nil
end

function Watchlist:IsWatched(nameOrKey)
    return self:GetEntry(nameOrKey) ~= nil
end

function Watchlist:Remove(id)
    local list = Store:GetWatchlistTable()
    local entry = list[id] or self:GetEntry(id)
    if not entry then return false end
    local realId = entry.id or id
    local displayName = entry.displayName or realId
    list[realId] = nil
    list[id] = nil
    ns:Print(L["Removed %s from your Watchlist."]:format(displayName))
    ns:Emit("WATCHLIST_UPDATED")
    return true
end

function Watchlist:SetNote(id, note)
    local list = Store:GetWatchlistTable()
    local entry = list[id]
    if not entry then return false end
    entry.note = Compat.CleanInput(note or "") or ""
    ns:Emit("WATCHLIST_UPDATED")
    return true
end

function Watchlist:ToggleFavorite(id)
    local list = Store:GetWatchlistTable()
    local entry = list[id]
    if not entry then return false end
    entry.favorite = not entry.favorite
    ns:Emit("WATCHLIST_UPDATED")
    return true
end

function Watchlist:SetGroup(id, groupName)
    local list = Store:GetWatchlistTable()
    local entry = list[id]
    if not entry then return false end
    local clean = Compat.CleanInput(groupName or "")
    entry.group = clean
    ns:Emit("WATCHLIST_UPDATED")
    return true
end

function Watchlist:GetGroups()
    local seen = {}
    local out = {}
    for _, entry in pairs(Store:GetWatchlistTable()) do
        if type(entry.group) == "string" and entry.group ~= "" and not seen[entry.group] then
            seen[entry.group] = true
            table.insert(out, entry.group)
        end
    end
    table.sort(out)
    return out
end

function Watchlist:PinToFriends(id)
    local list = Store:GetWatchlistTable()
    local entry = list[id] or self:GetEntry(id)
    if not entry then return false end
    if C_FriendList and C_FriendList.AddFriend then
        pcall(C_FriendList.AddFriend, entry.displayName, entry.note or "")
        return true
    elseif AddFriend then
        pcall(AddFriend, entry.displayName)
        return true
    end
    return false
end

function Watchlist:GetEntries(groupFilter, sortBy)
    local list = Store:GetWatchlistTable()
    local out = {}
    for _, entry in pairs(list) do
        local include = true
        if groupFilter == "__fav" then
            include = entry.favorite == true
        elseif groupFilter and groupFilter ~= "all" then
            include = entry.group == groupFilter
        end
        if include then
            table.insert(out, entry)
        end
    end

    local mode = sortBy or (ns.db and ns.db.settings and ns.db.settings.sortBy) or "status"
    table.sort(out, function(a, b)
        local favA = a.favorite and 1 or 0
        local favB = b.favorite and 1 or 0
        if favA ~= favB then return favA > favB end

        if mode == "recent" then
            local recA = a.lastSeen or a.lastChecked or 0
            local recB = b.lastSeen or b.lastChecked or 0
            if recA ~= recB then return recA > recB end
        elseif mode == "status" then
            local rankA = a.status == "online" and 3 or (a.status == "offline" and 2 or 1)
            local rankB = b.status == "online" and 3 or (b.status == "offline" and 2 or 1)
            if rankA ~= rankB then return rankA > rankB end
        end
        return (a.displayName or "") < (b.displayName or "")
    end)
    return out
end

function Watchlist:GetStats()
    local online, offline, unknown = 0, 0, 0
    for _, entry in pairs(Store:GetWatchlistTable()) do
        if entry.status == "online" then
            online = online + 1
        elseif entry.status == "offline" then
            offline = offline + 1
        else
            unknown = unknown + 1
        end
    end
    return online, offline, unknown
end

local function MatchEntry(entry, candidateParsed)
    if entry.id == candidateParsed.lookupKey then return true end
    if not entry.surname and entry.firstName:lower() == candidateParsed.firstName:lower() then
        return true
    end
    return false
end

function Watchlist:ApplyWhoResults(matches, totalCount)
    local pending = self.pending
    if not pending then return end

    local list = Store:GetWatchlistTable()
    local now = time()
    local matchedTarget = false

    for _, m in ipairs(matches) do
        local parsed = m.parsed
        if parsed then
            for _, entry in pairs(list) do
                if MatchEntry(entry, parsed) then
                    local prevStatus = entry.status
                    entry.status = "online"
                    entry.source = "who"
                    entry.lastChecked = now
                    entry.lastSeen = now
                    entry.truncatedWarning = nil
                    if m.level and m.level > 0 then entry.level = m.level end
                    if m.classFile then entry.classFile = m.classFile end
                    if m.area and m.area ~= "" then entry.area = m.area end
                    if m.guild and m.guild ~= "" then entry.guild = m.guild end
                    if parsed.surname and parsed.surname ~= "" and not entry.surname then
                        local oldId = entry.id
                        entry.surname = parsed.surname
                        entry.displayName = parsed.displayName
                        entry.id = parsed.lookupKey
                        if oldId ~= entry.id then
                            list[entry.id] = entry
                            list[oldId] = nil
                        end
                        if Compat.CacheForeverFullName then
                            Compat.CacheForeverFullName(nil, parsed.displayName, parsed.firstName)
                        end
                    end
                    if prevStatus ~= "online" then
                        Store:NotifyWatchlistOnline(entry)
                    end
                    if entry.id == pending.id then
                        matchedTarget = true
                    end
                end
            end
        end
    end

    local targetEntry = list[pending.id]
    if targetEntry and not matchedTarget then
        targetEntry.lastChecked = now
        if totalCount and totalCount >= 50 then
            targetEntry.status = "unknown"
            targetEntry.truncatedWarning = true
            ns:Print(L["50+ matches found for '%s'; add surname for accuracy."]:format(targetEntry.displayName))
        else
            targetEntry.status = "offline"
            targetEntry.truncatedWarning = nil
        end
    end

    CleanupPending()
    ns:Emit("WATCHLIST_UPDATED")
end

function Watchlist:FinishChatFilterQuery()
    if not self.pending or self.pending.mode ~= "chat_filter" then return end
    local results = {}
    for _, item in ipairs(self.pending.chatMatches or {}) do
        table.insert(results, { parsed = item.parsed })
    end
    self:ApplyWhoResults(results, #results)
end

-- Must ONLY be called directly inside a hardware event (button click, slash command, keybind).
function Watchlist:CheckEntry(id)
    local list = Store:GetWatchlistTable()
    local entry = list[id]
    if not entry then return false, "missing" end

    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat then
        ns:Print(L["/who paused during combat to prevent UI taint."])
        return false, "combat"
    end

    local remaining = self:GetCooldownRemaining()
    if remaining > 0 then
        ns:Print(L["/who cooldown active (%ds remaining)."]:format(remaining))
        return false, "cooldown", remaining
    end

    if self.pending then
        return false, "busy"
    end

    if not (C_FriendList and C_FriendList.SendWho and C_FriendList.SetWhoToUi) then
        return false, "unavailable"
    end

    local cleanFirst = (entry.firstName or ""):gsub('["\\%*%?%c|]', "")
    if #cleanFirst < 2 then
        return false, "invalid"
    end

    self.tokenCounter = self.tokenCounter + 1
    local token = self.tokenCounter
    local mode = GetWhoMode()

    self.pending = {
        id = entry.id,
        displayName = entry.displayName,
        mode = mode,
        token = token,
    }
    self.lastWhoSentAt = GetTime()

    if mode == "silent_ui" then
        if FriendsFrame and not FriendsFrame:IsShown() then
            if not self.onShowHooked then
                self.onShowHooked = true
                FriendsFrame:HookScript("OnShow", RestoreFriendsFrameEvent)
            end
            local ok = pcall(FriendsFrame.UnregisterEvent, FriendsFrame, "WHO_LIST_UPDATE")
            self.friendsBorrowed = ok
        end
        if C_FriendList and C_FriendList.SetWhoToUi then
            pcall(C_FriendList.SetWhoToUi, true)
        elseif SetWhoToUI then
            pcall(SetWhoToUI, 1)
        end
    else
        if C_FriendList and C_FriendList.SetWhoToUi then
            pcall(C_FriendList.SetWhoToUi, false)
        elseif SetWhoToUI then
            pcall(SetWhoToUI, 0)
        end
        self.chatFilterActive = true
        AddChatFilter(SystemChatFilter)
    end

    local query = ('n-"%s"'):format(cleanFirst)
    local sentOk = pcall(C_FriendList.SendWho, query)
    if not sentOk then
        CleanupPending()
        return false, "send_failed"
    end

    -- Safety timeout in case server silently throttles the query; back off extra 10s.
    C_Timer.After(3.5, function()
        if Watchlist.pending and Watchlist.pending.token == token then
            if Watchlist.pending.mode == "chat_filter" and Watchlist.pending.chatMatches and #Watchlist.pending.chatMatches > 0 then
                Watchlist:FinishChatFilterQuery()
            else
                Watchlist.backoffUntil = GetTime() + 10
                CleanupPending()
                ns:Print(L["Check skipped: /who response timed out or was throttled."])
                ns:Emit("WATCHLIST_UPDATED")
            end
        end
    end)

    ns:Emit("WATCHLIST_UPDATED")
    return true
end

-- Picks the entry needing verification most urgently (never checked first, then oldest check).
function Watchlist:CheckNext()
    local entries = self:GetEntries()
    if #entries == 0 then
        ns:Print(L["Watchlist is empty."])
        return false, "empty"
    end

    table.sort(entries, function(a, b)
        local ca = a.lastChecked or 0
        local cb = b.lastChecked or 0
        if ca ~= cb then return ca < cb end
        return (a.addedAt or 0) < (b.addedAt or 0)
    end)

    return self:CheckEntry(entries[1].id)
end

-- Hardware-event convenience: ensures manual typed name is on Watchlist, then runs 1 /who check.
function Watchlist:AddAndCheck(rawName)
    local parsed = Compat.ParseCharacterName(rawName)
    if not parsed or #(parsed.firstName or "") < 2 then
        ns:Print(L["Type a valid character name (at least 2 letters)."])
        return false, "invalid"
    end

    local list = Store:GetWatchlistTable()
    if not list[parsed.lookupKey] then
        self:Add(rawName)
    end
    return self:CheckEntry(parsed.lookupKey)
end

local function OnWhoListUpdate()
    if not Watchlist.pending then return end

    local numResults, totalCount
    if C_FriendList and C_FriendList.GetNumWhoResults then
        numResults, totalCount = C_FriendList.GetNumWhoResults()
    elseif GetNumWhoResults then
        numResults, totalCount = GetNumWhoResults()
    else
        CleanupPending()
        return
    end

    numResults = Safe.Number(numResults) or 0
    totalCount = Safe.Number(totalCount) or numResults

    local matches = {}
    for i = 1, numResults do
        if C_FriendList and C_FriendList.GetWhoInfo then
            local info = Safe.Call(C_FriendList.GetWhoInfo, i)
            if type(info) == "table" then
                local fullName = Safe.String(info.fullName)
                local parsed = fullName and Compat.ParseCharacterName(fullName)
                if parsed then
                    table.insert(matches, {
                        parsed = parsed,
                        level = Safe.Number(info.level),
                        classFile = Safe.String(info.filename) or Compat.ClassFileFromLocalized(Safe.String(info.classStr)),
                        area = Safe.String(info.area),
                        guild = Safe.String(info.fullGuildName) or "",
                    })
                end
            end
        elseif GetWhoInfo then
            local name, guild, level, _, classLoc, zone, classFileName = GetWhoInfo(i)
            name = Safe.String(name)
            local parsed = name and Compat.ParseCharacterName(name)
            if parsed then
                table.insert(matches, {
                    parsed = parsed,
                    level = Safe.Number(level),
                    classFile = Safe.String(classFileName) or Compat.ClassFileFromLocalized(Safe.String(classLoc)),
                    area = Safe.String(zone),
                    guild = Safe.String(guild) or "",
                })
            end
        end
    end

    Watchlist:ApplyWhoResults(matches, totalCount)
end

function Watchlist:Init()
    ns.RegisterEvent(self, "WHO_LIST_UPDATE", OnWhoListUpdate)
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        -- Ensure FriendsFrame event is never left borrowed entering combat.
        RestoreFriendsFrameEvent()
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        RestoreFriendsFrameEvent()
    end)
end
