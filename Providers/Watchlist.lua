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
    pending = nil,        -- { id, firstName, surname, displayName, mode, token, silent }
    friendsBorrowed = false,
    needsFriendsRestore = false,
    suppressedWhoFrames = {},
    lfgWasShownBeforeWho = false,
    friendsWasShownBeforeWho = false,
    suppressPopupUntil = 0,
    onShowHooked = false,
    lfgOnShowHooked = false,
    whoOnShowHooked = false,
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

local function SafeHideFrame(f)
    if not f or (InCombatLockdown and InCombatLockdown()) then return end
    if HideUIPanel and f == _G.LFGParentFrame then
        pcall(HideUIPanel, f)
    end
    if f.IsShown and f:IsShown() and f.Hide then
        pcall(f.Hide, f)
    end
end

local function CollectWhoListeningFrames(root, depth, out, seen)
    if not root or (depth or 0) <= 0 or seen[root] then return end
    seen[root] = true
    if root.IsEventRegistered and root.UnregisterEvent and root.RegisterEvent then
        local ok, reg = pcall(root.IsEventRegistered, root, "WHO_LIST_UPDATE")
        if ok and reg then
            out[#out + 1] = root
        end
    end
    if root.GetChildren then
        local okC, children = pcall(function() return { root:GetChildren() } end)
        if okC and type(children) == "table" then
            for _, child in ipairs(children) do
                CollectWhoListeningFrames(child, (depth or 1) - 1, out, seen)
            end
        end
    end
end

local function RestoreFriendsFrameEvent()
    if not (Watchlist.friendsBorrowed or Watchlist.needsFriendsRestore) then
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
    for _, f in ipairs(Watchlist.suppressedWhoFrames or {}) do
        if f and f.RegisterEvent then
            pcall(f.RegisterEvent, f, "WHO_LIST_UPDATE")
        end
    end
    Watchlist.suppressedWhoFrames = {}
    if _G.FriendsFrame and _G.FriendsFrame.RegisterEvent then
        pcall(_G.FriendsFrame.RegisterEvent, _G.FriendsFrame, "WHO_LIST_UPDATE")
    end
    if not Watchlist.lfgWasShownBeforeWho and (GetTime() < (Watchlist.suppressPopupUntil or 0) or Watchlist.pending) then
        SafeHideFrame(_G.LFGParentFrame)
    end
end

local function SuppressWhoUiFrames()
    if InCombatLockdown and InCombatLockdown() then return end
    Watchlist.lfgWasShownBeforeWho = (_G.LFGParentFrame and _G.LFGParentFrame.IsShown and _G.LFGParentFrame:IsShown()) == true
    Watchlist.friendsWasShownBeforeWho = (_G.FriendsFrame and _G.FriendsFrame.IsShown and _G.FriendsFrame:IsShown()) == true

    if _G.FriendsFrame and not Watchlist.onShowHooked then
        Watchlist.onShowHooked = true
        _G.FriendsFrame:HookScript("OnShow", function()
            RestoreFriendsFrameEvent()
        end)
    end
    if _G.LFGParentFrame and not Watchlist.lfgOnShowHooked then
        Watchlist.lfgOnShowHooked = true
        _G.LFGParentFrame:HookScript("OnShow", function(selfLfg)
            if not (InCombatLockdown and InCombatLockdown()) and not Watchlist.lfgWasShownBeforeWho then
                if (Watchlist.pending and Watchlist.pending.mode == "silent_ui") or (GetTime() < (Watchlist.suppressPopupUntil or 0)) then
                    SafeHideFrame(selfLfg)
                end
            end
        end)
    end
    if _G.WhoFrame and not Watchlist.whoOnShowHooked then
        Watchlist.whoOnShowHooked = true
        _G.WhoFrame:HookScript("OnShow", function(selfWho)
            if not (InCombatLockdown and InCombatLockdown()) and not Watchlist.lfgWasShownBeforeWho then
                if (Watchlist.pending and Watchlist.pending.mode == "silent_ui") or (GetTime() < (Watchlist.suppressPopupUntil or 0)) then
                    SafeHideFrame(selfWho)
                    SafeHideFrame(_G.LFGParentFrame)
                end
            end
        end)
    end

    local list, seen = {}, {}
    for _, root in ipairs({ _G.FriendsFrame, _G.WhoFrame, _G.LFGParentFrame, _G.WhoListingFrame, _G.WhoListScrollFrame }) do
        if root then
            CollectWhoListeningFrames(root, 3, list, seen)
        end
    end
    Watchlist.suppressedWhoFrames = {}
    for _, f in ipairs(list) do
        local ok = pcall(f.UnregisterEvent, f, "WHO_LIST_UPDATE")
        if ok then
            Watchlist.suppressedWhoFrames[#Watchlist.suppressedWhoFrames + 1] = f
            Watchlist.friendsBorrowed = true
        end
    end
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
        local hasSurname = type(targetEntry.surname) == "string" and targetEntry.surname ~= ""
        if totalCount and totalCount >= 50 and not hasSurname then
            targetEntry.status = "unknown"
            targetEntry.truncatedWarning = true
            if not pending.silent then
                ns:Print(L["50+ matches found for '%s'; add surname for accuracy."]:format(targetEntry.displayName))
            end
        else
            targetEntry.status = "offline"
            targetEntry.truncatedWarning = nil
        end
    end

    Watchlist.suppressPopupUntil = GetTime() + 0.35
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
function Watchlist:CheckEntry(id, silent)
    local list = Store:GetWatchlistTable()
    local entry = list[id]
    if not entry then return false, "missing" end

    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat then
        if not silent then
            ns:Print(L["/who paused during combat to prevent UI taint."])
        end
        return false, "combat"
    end

    local remaining = self:GetCooldownRemaining()
    if remaining > 0 then
        if not silent then
            ns:Print(L["/who cooldown active (%ds remaining)."]:format(remaining))
        end
        return false, "cooldown", remaining
    end

    if self.pending then
        return false, "busy"
    end

    if not (C_FriendList and C_FriendList.SendWho and C_FriendList.SetWhoToUi) then
        return false, "unavailable"
    end

    if (not entry.surname or entry.surname == "") and entry.displayName and (entry.displayName:find(" ") or entry.displayName:find("-")) then
        local normalized = Compat.ParseCharacterName(entry.displayName)
        if normalized then
            entry.firstName = normalized.firstName
            entry.surname = normalized.surname
            entry.displayName = normalized.displayName
        end
    end

    local cleanFirst = (entry.firstName or ""):gsub('["\\%*%?%c|]', "")
    if #cleanFirst < 2 then
        return false, "invalid"
    end

    local rawFull = (entry.surname and entry.surname ~= "") and (cleanFirst .. " " .. entry.surname) or (entry.displayName or cleanFirst)
    local cleanQuery = rawFull:gsub('["\\%*%?%c|]', "")
    if #cleanQuery < 2 then
        cleanQuery = cleanFirst
    end

    self.tokenCounter = self.tokenCounter + 1
    local token = self.tokenCounter
    local mode = GetWhoMode()

    self.pending = {
        id = entry.id,
        displayName = entry.displayName,
        mode = mode,
        token = token,
        silent = silent == true,
    }
    self.lastWhoSentAt = GetTime()
    self.suppressPopupUntil = GetTime() + 4.0

    if mode == "silent_ui" then
        SuppressWhoUiFrames()
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

    local query = ('n-"%s"'):format(cleanQuery)
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
                local wasSilent = Watchlist.pending.silent
                Watchlist.backoffUntil = GetTime() + 10
                Watchlist.suppressPopupUntil = GetTime() + 0.35
                CleanupPending()
                if not wasSilent then
                    ns:Print(L["Check skipped: /who response timed out or was throttled."])
                end
                ns:Emit("WATCHLIST_UPDATED")
            end
        end
    end)

    ns:Emit("WATCHLIST_UPDATED")
    return true
end

-- Picks the entry needing verification most urgently (never checked first, then oldest check).
function Watchlist:CheckNext(silent)
    local entries = self:GetEntries()
    if #entries == 0 then
        if not silent then
            ns:Print(L["Watchlist is empty."])
        end
        return false, "empty"
    end

    table.sort(entries, function(a, b)
        local ca = a.lastChecked or 0
        local cb = b.lastChecked or 0
        if ca ~= cb then return ca < cb end
        return (a.addedAt or 0) < (b.addedAt or 0)
    end)

    return self:CheckEntry(entries[1].id, silent)
end

-- Automatically checks the next non-friend/non-guild (or stale) Watchlist entry from a genuine hardware click.
function Watchlist:AutoCheckNextFromHardwareClick(preferredId)
    if ns.Social and ns.Social.Scan then
        pcall(ns.Social.Scan, ns.Social)
    end

    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat or self.pending or self:GetCooldownRemaining() > 0 then
        return false
    end

    local now = time()
    if preferredId then
        local list = Store:GetWatchlistTable()
        local pref = list[preferredId]
        if pref and ((pref.status == "unknown") or not pref.lastChecked or (now - pref.lastChecked) >= 30) then
            return self:CheckEntry(pref.id, true)
        end
    end

    local entries = self:GetEntries()
    if #entries == 0 then return false end

    local best = nil
    local bestScore = -1
    for _, entry in ipairs(entries) do
        local age = entry.lastChecked and (now - entry.lastChecked) or 999999
        local isFriendOrGuild = (entry.source == "friend" or entry.source == "guild" or entry.source == "bnet")
        if entry.status == "unknown" or (not isFriendOrGuild and age >= 45) or (isFriendOrGuild and age >= 120) then
            local score = age + ((entry.status == "unknown") and 1000000 or 0)
            if score > bestScore then
                bestScore = score
                best = entry
            end
        end
    end

    if best then
        return self:CheckEntry(best.id, true)
    end
    return false
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

local tooltipHooksRegistered = false
local unitMenusRegistered = false

local function AppendPlayerTooltipLines(tooltip)
    if not tooltip or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if ns.db and ns.db.settings and ns.db.settings.tooltipPlayerNotes == false then return end

    local unit
    if tooltip.GetUnit then
        local ok, _, u = pcall(tooltip.GetUnit, tooltip)
        if ok and u then
            unit = Safe.String(u)
        end
    end
    if not unit or not (UnitIsPlayer and Safe.Bool(Safe.Call(UnitIsPlayer, unit)) == true) then
        return
    end

    local fullName, parsed = Compat.ResolveUnitFullName(unit)
    local unitGuid = UnitGUID and Safe.String(Safe.Call(UnitGUID, unit))
    if not fullName or fullName == "" or Compat.IsMe(fullName, unitGuid) then
        return
    end

    local lookupKey = (parsed and parsed.lookupKey) or fullName:lower()
    if not lookupKey or tooltip._scPlayerKey == lookupKey then
        return
    end

    local meta = Store and (Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(fullName) or Store:GetSocialMeta(fullName))
    local wl = Watchlist:GetEntry(fullName)
    if wl then
        if wl.guid and unitGuid and wl.guid ~= unitGuid then
            wl = nil
        elseif wl.surname and wl.surname ~= "" and parsed and parsed.surname and parsed.surname ~= ""
            and wl.surname:lower() ~= parsed.surname:lower() then
            wl = nil
        elseif parsed and parsed.surname and parsed.surname ~= "" and (not wl.surname or wl.surname == "") then
            -- Never match FirstName-only Watchlist rows when tooltip belongs to a different Forever Surname unless GUID confirms.
            if not (wl.guid and unitGuid and wl.guid == unitGuid) then
                wl = nil
            end
        end
    end
    local comp = Store and Store.GetRecentCompanion and Store:GetRecentCompanion(fullName)
    local isPeer = ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(lookupKey)

    if not meta and not wl and not comp and not isPeer then
        return
    end

    tooltip._scPlayerKey = lookupKey
    tooltip:AddLine(" ")

    if meta and meta.flag == "AVOID" then
        tooltip:AddLine("|cffff4d4d[!] " .. L["FLAGGED: AVOID (SocialCentral)"] .. "|r", 1.0, 0.32, 0.32)
    elseif meta and meta.flag == "GOOD" then
        tooltip:AddLine("|cff3fb950[+] " .. L["Recommended Partner (SocialCentral)"] .. "|r", 0.25, 0.88, 0.48)
    end

    if wl then
        local wlText = "|cffffa633[" .. L["Watchlist"] .. "]|r"
        if wl.note and wl.note ~= "" then
            wlText = wlText .. " " .. wl.note
        end
        tooltip:AddLine(wlText, 1.0, 0.82, 0.42, true)
    end

    if meta then
        if meta.mainName and meta.mainName ~= "" then
            tooltip:AddDoubleLine(L["Main"], meta.mainName, 0.68, 0.78, 0.90, 0.88, 0.94, 1.0)
        end
        if meta.folder and meta.folder ~= "" then
            tooltip:AddDoubleLine(L["Folder"], meta.folder, 0.68, 0.78, 0.90, 0.75, 0.88, 0.96)
        end
        if meta.note and meta.note ~= "" and (not wl or wl.note ~= meta.note) then
            tooltip:AddLine(L["Note"] .. ": " .. meta.note, 1.0, 0.90, 0.48, true)
        end
    end

    if comp and comp.lastSeen then
        local runsSuffix = (comp.runs and comp.runs > 1) and (" (x" .. comp.runs .. ")") or ""
        local compText = L["Recent companion: %s (%s)"]:format(
            comp.zone or L["Unknown"],
            Compat.FormatRelativeTime(comp.lastSeen, L)
        ) .. runsSuffix
        tooltip:AddLine(compText, 0.55, 0.80, 1.0, true)
    end

    if isPeer then
        tooltip:AddLine("|cff3fb950[SocialCentral]|r", 0.30, 0.88, 0.48)
    end

    pcall(tooltip.Show, tooltip)
end

local function RegisterPlayerTooltipIntegration()
    if tooltipHooksRegistered then return end
    tooltipHooksRegistered = true

    local function ClearTipKey(tip)
        if tip then
            tip._scPlayerKey = nil
        end
    end
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tip and tip.HookScript then
            if tip:HasScript("OnTooltipCleared") then
                tip:HookScript("OnTooltipCleared", ClearTipKey)
            end
            if tip:HasScript("OnHide") then
                tip:HookScript("OnHide", ClearTipKey)
            end
        end
    end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tooltip)
            AppendPlayerTooltipLines(tooltip)
        end)
    elseif GameTooltip and GameTooltip.HookScript and GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", AppendPlayerTooltipLines)
    end
end

local function RegisterUnitContextMenus()
    if unitMenusRegistered or not (Menu and Menu.ModifyMenu) then return end
    unitMenusRegistered = true

    local menuTags = {
        "MENU_UNIT_PLAYER",
        "MENU_UNIT_PARTY",
        "MENU_UNIT_RAID_PLAYER",
        "MENU_UNIT_FRIEND",
        "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
        "MENU_UNIT_CHAT_PLAYER",
    }

    local function InjectMenu(_, rootDescription, contextData)
        if type(contextData) ~= "table" or not rootDescription then return end
        local rawUnit = Safe.String(contextData.unit)
        local rawName = Safe.String(contextData.name)
        local resolvedName, parsed

        if rawUnit and UnitIsPlayer and Safe.Bool(Safe.Call(UnitIsPlayer, rawUnit)) == true then
            resolvedName, parsed = Compat.ResolveUnitFullName(rawUnit)
        elseif rawName and rawName ~= "" then
            if rawUnit and UnitIsPlayer and Safe.Bool(Safe.Call(UnitIsPlayer, rawUnit)) == false then
                return
            end
            parsed = Compat.ParseCharacterName(rawName)
            resolvedName = parsed and parsed.displayName or rawName
        end

        if not parsed or not resolvedName or Compat.IsMe(resolvedName) then
            return
        end

        local curMeta = Store and Store.GetSocialMeta and Store:GetSocialMeta(parsed.displayName)
        local isWatched = Watchlist:IsWatched(parsed.displayName)
        local existingEntry = isWatched and Watchlist:GetEntry(parsed.displayName) or nil
        if existingEntry and parsed.surname and existingEntry.surname and existingEntry.surname:lower() ~= parsed.surname:lower() then
            isWatched = false
            existingEntry = nil
        end

        rootDescription:CreateDivider()
        rootDescription:CreateTitle("SocialCentral")

        if isWatched and existingEntry then
            rootDescription:CreateButton(L["Remove from Watchlist"], function()
                Watchlist:Remove(existingEntry.id)
            end)
        else
            rootDescription:CreateButton("+ " .. L["Add to Watchlist"], function()
                Watchlist:Add(parsed.displayName)
            end)
        end

        rootDescription:CreateButton(L["Edit Social Card"], function()
            if ns.SocialPanels and ns.SocialPanels.OpenSocialMetaModal then
                ns.SocialPanels:OpenSocialMetaModal(parsed.displayName, parsed.lookupKey)
            end
        end)

        local goodLabel = (curMeta and curMeta.flag == "GOOD") and ("|cff3fb950[x]|r " .. L["Good Partner (+)"]) or L["Good Partner (+)"]
        rootDescription:CreateButton(goodLabel, function()
            if Store and Store.SetSocialFlag then
                Store:SetSocialFlag(parsed.displayName, "GOOD")
            end
        end)

        local avoidLabel = (curMeta and curMeta.flag == "AVOID") and ("|cffff4d4d[x]|r " .. L["Flag: Avoid"]) or L["Flag: Avoid"]
        rootDescription:CreateButton(avoidLabel, function()
            if Store and Store.SetSocialFlag then
                Store:SetSocialFlag(parsed.displayName, "AVOID")
            end
        end)

        if ns.SpotterHUD and ns.SpotterHUD.TrackEntry then
            rootDescription:CreateButton(L["Track on Radar"], function()
                ns.SpotterHUD:TrackEntry({
                    displayName = parsed.displayName,
                    lookupKey = parsed.lookupKey,
                }, "SOCIAL")
            end)
        end
    end

    for _, tag in ipairs(menuTags) do
        pcall(Menu.ModifyMenu, tag, InjectMenu)
    end
end

function Watchlist:Init()
    -- Normalize stored Watchlist entries (Forever FirstName Surname format & clear stale truncation flags).
    for _, entry in pairs(Store:GetWatchlistTable()) do
        if type(entry) == "table" and entry.displayName then
            local p = Compat.ParseCharacterName(entry.displayName)
            if p then
                entry.firstName = p.firstName
                entry.surname = p.surname
                entry.displayName = p.displayName
            end
            if entry.surname and entry.surname ~= "" then
                entry.truncatedWarning = nil
            end
        end
    end

    RegisterPlayerTooltipIntegration()
    RegisterUnitContextMenus()

    ns.RegisterEvent(self, "WHO_LIST_UPDATE", OnWhoListUpdate)
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        -- Ensure FriendsFrame / LFGParentFrame event is never left borrowed entering combat.
        RestoreFriendsFrameEvent()
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        RestoreFriendsFrameEvent()
    end)
end
