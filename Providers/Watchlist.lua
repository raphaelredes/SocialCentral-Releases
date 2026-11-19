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
    whoListOnShowHooked = false,
    whoOnShowHooked = false,
    restoreSeq = 0,
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

local function IsSafeWhoFrame(f)
    if not f then return false end
    if f.IsForbidden then
        local ok, forb = pcall(f.IsForbidden, f)
        if not ok or forb then return false end
    end
    if f.IsProtected then
        local ok, prot = pcall(f.IsProtected, f)
        if not ok or prot then return false end
    end
    return true
end

local function SafeHideFrame(f)
    if not f or (InCombatLockdown and InCombatLockdown()) then return end
    if not IsSafeWhoFrame(f) then return end
    if f.IsShown and f:IsShown() and f.Hide then
        pcall(f.Hide, f)
    end
end

local function IsOwnAddonWhoFrame(f)
    if not f then return true end
    if f == _G.UIParent or (ns and ns._eventFrame and f == ns._eventFrame) then
        return true
    end
    local okName, fName = pcall(f.GetName, f)
    if okName and type(fName) == "string" and fName:find("^SocialCentral") then
        return true
    end
    return false
end

local function CollectWhoListeningFrames(root, depth, out, seen)
    if not root or (depth or 0) <= 0 or seen[root] then return end
    seen[root] = true
    if not IsOwnAddonWhoFrame(root) and root.IsEventRegistered and root.UnregisterEvent and root.RegisterEvent then
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
    Watchlist.restoreSeq = (Watchlist.restoreSeq or 0) + 1
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
        if f and IsSafeWhoFrame(f) and f.RegisterEvent then
            pcall(f.RegisterEvent, f, "WHO_LIST_UPDATE")
        end
    end
    Watchlist.suppressedWhoFrames = {}
    if _G.FriendsFrame and IsSafeWhoFrame(_G.FriendsFrame) and _G.FriendsFrame.RegisterEvent then
        pcall(_G.FriendsFrame.RegisterEvent, _G.FriendsFrame, "WHO_LIST_UPDATE")
    end
    if _G.LFGWhoListFrame and IsSafeWhoFrame(_G.LFGWhoListFrame) and _G.LFGWhoListFrame.RegisterEvent then
        pcall(_G.LFGWhoListFrame.RegisterEvent, _G.LFGWhoListFrame, "WHO_LIST_UPDATE")
    end
    if not Watchlist.lfgWasShownBeforeWho and (GetTime() < (Watchlist.suppressPopupUntil or 0) or Watchlist.pending) then
        SafeHideFrame(_G.LFGParentFrame)
    end
end

local function ScheduleRestoreFriendsFrameEvent()
    if InCombatLockdown and InCombatLockdown() then
        RestoreFriendsFrameEvent()
        return
    end
    if not (Watchlist.friendsBorrowed or Watchlist.needsFriendsRestore) then
        return
    end
    Watchlist.restoreSeq = (Watchlist.restoreSeq or 0) + 1
    local seq = Watchlist.restoreSeq
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            if Watchlist.restoreSeq == seq and not Watchlist.pending then
                RestoreFriendsFrameEvent()
            end
        end)
    else
        RestoreFriendsFrameEvent()
    end
end

local function SuppressWhoUiFrames()
    if InCombatLockdown and InCombatLockdown() then return end
    Watchlist.restoreSeq = (Watchlist.restoreSeq or 0) + 1
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
    if _G.LFGWhoListFrame and not Watchlist.whoListOnShowHooked then
        Watchlist.whoListOnShowHooked = true
        _G.LFGWhoListFrame:HookScript("OnShow", function(selfWhoList)
            if not (InCombatLockdown and InCombatLockdown()) and not Watchlist.lfgWasShownBeforeWho then
                if (Watchlist.pending and Watchlist.pending.mode == "silent_ui") or (GetTime() < (Watchlist.suppressPopupUntil or 0)) then
                    SafeHideFrame(selfWhoList)
                    SafeHideFrame(_G.LFGParentFrame)
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
    local suppressedSet = {}
    Watchlist.suppressedWhoFrames = Watchlist.suppressedWhoFrames or {}
    for _, existing in ipairs(Watchlist.suppressedWhoFrames) do
        suppressedSet[existing] = true
    end

    for _, root in ipairs({
        _G.FriendsFrame,
        _G.WhoFrame,
        _G.LFGParentFrame,
        _G.LFGWhoListFrame,
        _G.LFGListingFrame,
        _G.LFGBrowseFrame,
        _G.WhoListingFrame,
        _G.WhoListScrollFrame,
    }) do
        if root then
            CollectWhoListeningFrames(root, 5, list, seen)
        end
    end
    if GetFramesRegisteredForEvent then
        local okReg, regFrames = pcall(function()
            return { GetFramesRegisteredForEvent("WHO_LIST_UPDATE") }
        end)
        if okReg and type(regFrames) == "table" then
            for _, f in ipairs(regFrames) do
                if f and not seen[f] and not IsOwnAddonWhoFrame(f) then
                    seen[f] = true
                    list[#list + 1] = f
                end
            end
        end
    end

    for _, f in ipairs(list) do
        if IsSafeWhoFrame(f) and f.UnregisterEvent then
            local ok = pcall(f.UnregisterEvent, f, "WHO_LIST_UPDATE")
            if ok then
                if not suppressedSet[f] then
                    suppressedSet[f] = true
                    Watchlist.suppressedWhoFrames[#Watchlist.suppressedWhoFrames + 1] = f
                end
                Watchlist.friendsBorrowed = true
            end
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
    local looksLikeWhoSummary = clean:find("%d+") and (lower:find("total") or lower:find("player") or lower:find("jogador") or lower:find("jugador") or lower:find("encontrad") or lower:find("pessoa"))
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

local function CleanupPending(preserveSuppress)
    local pending = Watchlist.pending
    local wasSilentUi = pending and pending.mode == "silent_ui"
    local prevWhoToUi = pending and pending.prevWhoToUi
    Watchlist.pending = nil
    if preserveSuppress and wasSilentUi then
        if not Watchlist.lfgWasShownBeforeWho then
            SafeHideFrame(_G.LFGWhoListFrame)
            SafeHideFrame(_G.LFGParentFrame)
        end
        ScheduleRestoreFriendsFrameEvent()
    else
        Watchlist.suppressPopupUntil = 0
        RestoreFriendsFrameEvent()
    end
    if wasSilentUi and prevWhoToUi ~= nil then
        if C_FriendList and C_FriendList.SetWhoToUi then
            pcall(C_FriendList.SetWhoToUi, prevWhoToUi == true)
        elseif SetWhoToUI then
            pcall(SetWhoToUI, prevWhoToUi == true and 1 or 0)
        end
    elseif wasSilentUi then
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
    local dirEntry = ns.Social and ns.Social.GetDirectoryEntry and ns.Social:GetDirectoryEntry(parsed.lookupKey)
    local initStatus = "unknown"
    if dirEntry then
        if dirEntry.online and (dirEntry.bnetState == "wow_forever" or (dirEntry.sources and (dirEntry.sources.friend or dirEntry.sources.guild))) then
            initStatus = "online"
        elseif (not dirEntry.online) or (dirEntry.sources and (dirEntry.sources.friend or dirEntry.sources.guild)) then
            initStatus = "offline"
        end
    end

    list[parsed.lookupKey] = {
        id = parsed.lookupKey,
        displayName = parsed.displayName,
        firstName = parsed.firstName,
        surname = parsed.surname,
        note = cleanNote,
        status = initStatus,
        source = (initStatus == "online" and dirEntry and dirEntry.sources)
            and ((dirEntry.sources.friend and "friend") or (dirEntry.sources.guild and "guild") or (dirEntry.sources.bnet and "bnet"))
            or nil,
        level = dirEntry and dirEntry.level or nil,
        classFile = dirEntry and dirEntry.classFile or nil,
        area = dirEntry and dirEntry.area or nil,
        guild = dirEntry and dirEntry.guild or nil,
        guid = dirEntry and dirEntry.guid or nil,
        lastChecked = dirEntry and time() or nil,
        lastSeen = (initStatus == "online") and time() or (dirEntry and dirEntry.lastSeen) or nil,
        addedAt = time(),
    }

    ns:Print(L["Added %s to your Watchlist."]:format(parsed.displayName))
    Watchlist._wlIndexDirty = true
    if Store and Store.InvalidateWatchlistIndex then Store:InvalidateWatchlistIndex() end
    if ns.Spotter and ns.Spotter.TrackPlayer then
        ns.Spotter:TrackPlayer(
            parsed.displayName,
            dirEntry and dirEntry.guild or nil,
            dirEntry and dirEntry.classFile or nil,
            dirEntry and dirEntry.level or nil,
            dirEntry and dirEntry.guid or nil,
            "WATCHLIST"
        )
    end
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

local function EnsureWatchlistFastIndex(list)
    local idx = Watchlist._wlFastIndex
    if Watchlist._wlIndexDirty or Watchlist._wlIndexedTbl ~= list or type(idx) ~= "table" then
        idx = {}
        for _, e in pairs(list) do
            if type(e) == "table" then
                if e.id and not idx[e.id] then idx[e.id] = e end
                if e.lookupKey and not idx[e.lookupKey] then idx[e.lookupKey] = e end
                if e.displayName then
                    local dl = e.displayName:lower()
                    if not idx[dl] then idx[dl] = e end
                end
                if e.firstName then
                    local fl = e.firstName:lower()
                    if not idx[fl] then idx[fl] = e end
                end
            end
        end
        Watchlist._wlFastIndex = idx
        Watchlist._wlIndexedTbl = list
        Watchlist._wlIndexDirty = false
    end
    return idx
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
    if list[low] then return list[low] end
    local idx = EnsureWatchlistFastIndex(list)
    local hit = idx[low]
    if hit and hit.id and list[hit.id] == hit then
        return hit
    elseif hit then
        Watchlist._wlIndexDirty = true
        idx = EnsureWatchlistFastIndex(list)
        local retry = idx[low]
        if retry and retry.id and list[retry.id] == retry then
            return retry
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
    Watchlist._wlIndexDirty = true
    if Store and Store.InvalidateWatchlistIndex then Store:InvalidateWatchlistIndex() end
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

local STALE_ONLINE_SECONDS = 300
local INIT_STALE_ONLINE_SECONDS = 180

local function IsEntryLiveConfirmed(entry, now)
    if type(entry) ~= "table" then return false end
    local socRow = Store and Store.socialByLookup and entry.id and Store.socialByLookup[entry.id]
    if socRow and socRow.online == true then
        return true
    end
    if Compat.IsInMyGroup and Compat.IsInMyGroup(entry.displayName, entry.guid) then
        return true
    end
    local nearbyRow = Store and Store.nearby and entry.id and Store.nearby[entry.id]
    if nearbyRow and (now - (nearbyRow.lastSeen or 0)) <= 180 then
        return true
    end
    return false
end

function Watchlist:ExpireStaleOnlineEntries(silentEmit)
    local list = Store:GetWatchlistTable()
    if type(list) ~= "table" or next(list) == nil then
        return false
    end
    local now = time()
    local changed = false
    for _, entry in pairs(list) do
        if type(entry) == "table" and entry.status == "online" then
            if not IsEntryLiveConfirmed(entry, now) then
                if entry.source == "friend" or entry.source == "guild" or entry.source == "bnet" then
                    entry.source = nil
                end
                local lastConfirm = entry.lastSeen or entry.lastChecked or 0
                if (now - lastConfirm) >= STALE_ONLINE_SECONDS then
                    entry.status = "unknown"
                    entry._expiredOnline = true
                    changed = true
                end
            end
        end
    end
    if changed and not silentEmit then
        ns:Emit("WATCHLIST_UPDATED")
    end
    return changed
end

function Watchlist:GetEntries(groupFilter, sortBy)
    self:ExpireStaleOnlineEntries(true)
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
    self:ExpireStaleOnlineEntries(true)
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

function Watchlist:ResolveDisambiguation(entryId, chosenFullName, choiceMeta)
    if not entryId or not chosenFullName then return false end
    local list = Store:GetWatchlistTable()
    local entry = list[entryId] or self:GetEntry(entryId)
    if not entry then return false end
    local parsed = Compat.ParseCharacterName(chosenFullName)
    if not parsed then return false end

    local oldId = entry.id or entryId
    local now = time()
    entry.firstName = parsed.firstName
    entry.surname = parsed.surname
    entry.displayName = parsed.displayName
    entry.id = parsed.lookupKey
    entry.observedCandidate = nil
    entry.ambiguousChoices = nil
    entry.truncatedWarning = nil
    entry.lastChecked = now
    if type(choiceMeta) == "table" then
        entry.status = "online"
        entry.source = "who"
        entry.lastSeen = now
        if choiceMeta.level and choiceMeta.level > 0 then entry.level = choiceMeta.level end
        if choiceMeta.classFile then entry.classFile = choiceMeta.classFile end
        if choiceMeta.area and choiceMeta.area ~= "" then entry.area = choiceMeta.area end
        if choiceMeta.guild and choiceMeta.guild ~= "" then entry.guild = choiceMeta.guild end
    end

    if Compat.CacheForeverFullName then
        Compat.CacheForeverFullName(entry.guid, parsed.displayName, parsed.firstName)
    end

    if oldId ~= parsed.lookupKey then
        local existing = list[parsed.lookupKey]
        if existing and existing ~= entry then
            existing.favorite = existing.favorite or entry.favorite
            if (not existing.note or existing.note == "") and entry.note and entry.note ~= "" then
                existing.note = entry.note
            end
            existing.status = entry.status or existing.status
            existing.source = entry.source or existing.source
            existing.lastChecked = entry.lastChecked or existing.lastChecked
            existing.lastSeen = entry.lastSeen or existing.lastSeen
            if entry.level and entry.level > 0 then existing.level = entry.level end
            if entry.classFile then existing.classFile = entry.classFile end
            if entry.area and entry.area ~= "" then existing.area = entry.area end
            if entry.guild and entry.guild ~= "" then existing.guild = entry.guild end
        else
            list[parsed.lookupKey] = entry
        end
        list[oldId] = nil
        list[entryId] = nil
    end

    Watchlist._wlIndexDirty = true
    if Store and Store.InvalidateWatchlistIndex then
        Store:InvalidateWatchlistIndex()
    end
    ns:Print(L["Watchlist updated to exact character: %s"]:format(parsed.displayName))
    ns:Emit("WATCHLIST_UPDATED")
    return true
end

function Watchlist:GetNameSuggestions(queryText, maxResults)
    local q = (Compat.CleanInput and Compat.CleanInput(queryText or "")) or tostring(queryText or "")
    q = Compat.Trim and Compat.Trim(q) or q:match("^%s*(.-)%s*$")
    if #q < 2 then return {} end

    local qLow = q:lower()
    local limit = tonumber(maxResults) or 6
    local list = Store:GetWatchlistTable()
    local candidates = {}

    local function Consider(displayName, classFile, level, online, guild, srcLabel, priorityBase)
        local parsed = displayName and Compat.ParseCharacterName and Compat.ParseCharacterName(displayName)
        if not parsed or not parsed.lookupKey then return end
        if Compat.IsMe and Compat.IsMe(parsed.displayName) then return end
        if list[parsed.lookupKey] then return end

        local dLow = parsed.displayName:lower()
        local fLow = (parsed.firstName or ""):lower()
        local sLow = (parsed.surname or ""):lower()
        local startsFirst = fLow:sub(1, #qLow) == qLow
        local startsFull = dLow:sub(1, #qLow) == qLow
        local startsSurname = sLow ~= "" and sLow:sub(1, #qLow) == qLow
        local containsAny = dLow:find(qLow, 1, true) ~= nil
        if not (startsFirst or startsFull or startsSurname or containsAny) then
            return
        end

        local score = priorityBase or 10
        if parsed.surname and parsed.surname ~= "" then score = score + 40 end
        if online then score = score + 25 end
        if startsFull then score = score + 35 elseif startsFirst or startsSurname then score = score + 20 end
        local aff = (Store and Store.GetPlayerAffinityScore) and Store:GetPlayerAffinityScore(parsed.lookupKey) or 0
        if aff <= -500 then
            return
        end
        score = score + math.max(0, math.min(120, math.floor(aff * 0.4)))

        local existing = candidates[parsed.lookupKey]
        if existing then
            if score > existing.score then existing.score = score end
            if not existing.classFile and classFile then existing.classFile = classFile end
            if (not existing.level or existing.level <= 0) and level and level > 0 then existing.level = level end
            if (not existing.guild or existing.guild == "") and guild and guild ~= "" then existing.guild = guild end
            if online then existing.online = true end
            return
        end
        candidates[parsed.lookupKey] = {
            displayName = parsed.displayName,
            firstName = parsed.firstName,
            surname = parsed.surname,
            lookupKey = parsed.lookupKey,
            classFile = classFile,
            level = (level and level > 0) and level or nil,
            online = online == true,
            guild = (guild and guild ~= "") and guild or nil,
            sourceLabel = srcLabel,
            score = score,
        }
    end

    if Store and type(Store.socialDirectory) == "table" then
        for _, row in pairs(Store.socialDirectory) do
            if type(row) == "table" and row.samePool ~= false and row.hasCharacterName ~= false and row.displayName then
                local src = (row.sources and row.sources.friend and L["Friend"])
                    or (row.sources and row.sources.guild and L["Guild"])
                    or (row.sources and row.sources.bnet and "Battle.net")
                    or L["Social"]
                Consider(row.displayName, row.classFile, row.level, row.online, row.guild, src, 50)
            end
        end
    end
    if Store and type(Store.nearby) == "table" then
        for _, row in pairs(Store.nearby) do
            if type(row) == "table" and row.displayName then
                Consider(row.displayName, row.classFile, row.level, true, row.guild, L["Nearby"], 30)
            end
        end
    end
    if Store and Store.GetRecentCompanionsList then
        for _, comp in ipairs(Store:GetRecentCompanionsList()) do
            if type(comp) == "table" and (comp.displayName or comp.name) then
                Consider(comp.displayName or comp.name, comp.classFile, comp.level, false, nil, L["Recent"], 20)
            end
        end
    end

    local out = {}
    for _, item in pairs(candidates) do
        out[#out + 1] = item
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return (a.displayName or "") < (b.displayName or "")
    end)
    while #out > limit do
        table.remove(out)
    end
    return out
end

function Watchlist:ApplyWhoResults(matches, totalCount)
    local pending = self.pending
    if not pending then return end

    local list = Store:GetWatchlistTable()
    local now = time()
    local matchedTarget = false
    local toRekey
    local disambiguateTarget

    for listKey, entry in pairs(list) do
        local firstCandidates = {}
        local seenKeys = {}
        for _, m in ipairs(matches) do
            local parsed = m.parsed
            if parsed and MatchEntry(entry, parsed) then
                if (not entry.surname or entry.surname == "") and not seenKeys[parsed.lookupKey] then
                    seenKeys[parsed.lookupKey] = true
                    firstCandidates[#firstCandidates + 1] = {
                        fullName = parsed.displayName,
                        lookupKey = parsed.lookupKey,
                        parsed = parsed,
                        level = m.level,
                        classFile = m.classFile,
                        area = m.area,
                        guild = m.guild,
                    }
                end
            end
        end

        local isMultiFirstCollision = (not entry.surname or entry.surname == "") and #firstCandidates > 1
        local isPendingTarget = (entry.id == pending.id or listKey == pending.id)

        if isMultiFirstCollision then
            entry.status = "online"
            entry.source = "who"
            entry.lastChecked = now
            entry.lastSeen = now
            entry.truncatedWarning = true
            entry.ambiguousChoices = {}
            for i = 1, math.min(8, #firstCandidates) do
                local c = firstCandidates[i]
                entry.ambiguousChoices[i] = {
                    fullName = c.fullName,
                    lookupKey = c.lookupKey,
                    level = c.level,
                    classFile = c.classFile,
                    area = c.area,
                    guild = c.guild,
                }
            end
            if isPendingTarget then
                matchedTarget = true
                disambiguateTarget = entry
            end
        else
            for _, m in ipairs(matches) do
                local parsed = m.parsed
                if parsed and MatchEntry(entry, parsed) then
                    local prevStatus = entry.status
                    local wasExpired = (entry._expiredOnline == true)
                    local hasSurname = type(entry.surname) == "string" and entry.surname ~= ""
                    local candidateOnly = (not hasSurname) and parsed.surname and parsed.surname ~= ""
                    entry.status = "online"
                    entry._expiredOnline = nil
                    entry.source = "who"
                    entry.lastChecked = now
                    entry.lastSeen = now
                    entry.truncatedWarning = nil
                    entry.ambiguousChoices = nil
                    if m.level and m.level > 0 then entry.level = m.level end
                    if m.classFile then entry.classFile = m.classFile end
                    if m.area and m.area ~= "" then entry.area = m.area end
                    if m.guild and m.guild ~= "" then entry.guild = m.guild end
                    if candidateOnly then
                        entry.observedCandidate = parsed.displayName
                        if Compat.CacheForeverFullName then
                            Compat.CacheForeverFullName(nil, parsed.displayName, parsed.firstName)
                        end
                    elseif prevStatus ~= "online" and not wasExpired then
                        Store:NotifyWatchlistOnline(entry)
                    end
                    if not candidateOnly and parsed.surname and parsed.surname ~= "" and ns.Clan and ns.Clan.QueueCooperativeSighting then
                        ns.Clan:QueueCooperativeSighting(parsed.displayName, entry.guid, m.level, m.classFile, m.guild, m.area)
                    end
                    if isPendingTarget then
                        matchedTarget = true
                    end
                end
            end
        end
    end

    if toRekey then
        for _, item in ipairs(toRekey) do
            local existing = list[item.newId]
            local src = item.entry
            if existing and existing ~= src then
                existing.favorite = existing.favorite or src.favorite
                if (not existing.note or existing.note == "") and src.note and src.note ~= "" then
                    existing.note = src.note
                end
                existing.status = src.status or existing.status
                existing.source = src.source or existing.source
                existing.lastChecked = src.lastChecked or existing.lastChecked
                existing.lastSeen = src.lastSeen or existing.lastSeen
                if src.level and src.level > 0 then existing.level = src.level end
                if src.classFile then existing.classFile = src.classFile end
                if src.area and src.area ~= "" then existing.area = src.area end
                if src.guild and src.guild ~= "" then existing.guild = src.guild end
            else
                list[item.newId] = src
            end
            if item.oldId ~= item.newId then list[item.oldId] = nil end
            if item.listKey ~= item.newId then list[item.listKey] = nil end
        end
        Watchlist._wlIndexDirty = true
        if Store and Store.InvalidateWatchlistIndex then
            Store:InvalidateWatchlistIndex()
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
            local socRow = Store.socialByLookup and Store.socialByLookup[pending.id]
            if socRow and socRow.online == true then
                targetEntry.status = "online"
                targetEntry._expiredOnline = nil
            else
                targetEntry.status = "offline"
                targetEntry._expiredOnline = nil
            end
            targetEntry.truncatedWarning = nil
        end
    end

    if Watchlist.pending and Watchlist.pending.mode == "silent_ui" then
        Watchlist.suppressPopupUntil = GetTime() + 0.35
    end
    CleanupPending(true)
    ns:Emit("WATCHLIST_UPDATED")
    if disambiguateTarget then
        local pickLink = "|Haddon:SCentral:wldisambig:" .. tostring(disambiguateTarget.id) .. "|h|cff58a6ff[" .. L["Choose"] .. "]|r|h"
        ns:Print("%s %s", L["Multiple characters match '%s'; select the exact FirstName Surname:"]:format(disambiguateTarget.displayName), pickLink)
        ns:Emit("WATCHLIST_DISAMBIGUATE", disambiguateTarget.id)
    end
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

    local socRow = Store.socialByLookup and Store.socialByLookup[entry.id]
    if socRow and socRow.online == true then
        local src = (socRow.sources and socRow.sources.bnet and "bnet")
            or (socRow.sources and socRow.sources.friend and "friend")
            or "guild"
        Store:SyncWatchlistObservation(entry.displayName, {
            online = true,
            level = socRow.level,
            classFile = socRow.classFile,
            area = socRow.area,
            guildName = socRow.guild,
            guild = socRow.guild,
            source = src,
        }, { suppressAlert = true })
        return true, "social_online"
    end

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

    local prevWhoToUi = nil
    if mode == "silent_ui" then
        if C_FriendList and C_FriendList.GetWhoToUi then
            local okW, curW = pcall(C_FriendList.GetWhoToUi)
            if okW then prevWhoToUi = (curW == true) end
        end
    end

    self.pending = {
        id = entry.id,
        displayName = entry.displayName,
        mode = mode,
        prevWhoToUi = prevWhoToUi,
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
                if Watchlist.pending.mode == "silent_ui" then
                    Watchlist.suppressPopupUntil = GetTime() + 0.35
                end
                CleanupPending(true)
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

-- Expected Information Gain (VOI) priority for /who checks (unknown & active favorites first, O(M) single pass).
local function ComputeWatchlistCheckPriority(entry, now)
    if type(entry) ~= "table" then return -1 end
    local socRow = Store and Store.socialByLookup and entry.id and Store.socialByLookup[entry.id]
    if socRow and socRow.online == true then
        return -1
    end
    local dirRow = Store and Store.socialDirectoryByLookup and entry.id and Store.socialDirectoryByLookup[entry.id]
    local isPassiveKnown = (socRow ~= nil) or (dirRow ~= nil and dirRow.online == true)
    local age = entry.lastChecked and math.max(0, now - entry.lastChecked) or 999999
    local isUnknown = (entry.status == "unknown")
    local isUnverifiedOnline = (entry.status == "online")
    if not isUnknown then
        local minAge = isUnverifiedOnline and 20 or (isPassiveKnown and 120 or 45)
        if age < minAge then
            return -1
        end
    end
    local favMult = (entry.favorite == true) and 1.8 or 1.0
    local seenAge = entry.lastSeen and math.max(0, now - entry.lastSeen) or (14 * 86400)
    local activePrior = 1.0 + (0.5 / (1 + (seenAge / 86400)))
    local passivePenalty = isPassiveKnown and 0.15 or 1.0
    local base = isUnknown and (1000000 + (entry._expiredOnline and 50000 or 0) + math.min(age, 86400))
        or (isUnverifiedOnline and (50000 + math.min(age, 86400)) or age)
    return base * favMult * activePrior * passivePenalty
end

-- Picks the entry needing verification most urgently, skipping Friends/Guildmates already confirmed online in Social.
function Watchlist:CheckNext(silent)
    if ns.Social and ns.Social.Scan then
        pcall(ns.Social.Scan, ns.Social)
    end
    local entries = self:GetEntries()
    if #entries == 0 then
        if not silent then
            ns:Print(L["Watchlist is empty."])
        end
        return false, "empty"
    end

    local now = time()
    local needCount = 0
    local best, bestPrio = nil, -1
    local oldestFallback, oldestChecked, oldestAdded = nil, nil, nil
    for _, entry in ipairs(entries) do
        local socRow = Store and Store.socialByLookup and entry.id and Store.socialByLookup[entry.id]
        local isPassiveOnline = (socRow ~= nil and socRow.online == true)
        if not isPassiveOnline then
            needCount = needCount + 1
            local prio = ComputeWatchlistCheckPriority(entry, now)
            if prio > bestPrio then
                bestPrio = prio
                best = entry
            end
            local lc = entry.lastChecked or 0
            local aa = entry.addedAt or 0
            if (not oldestFallback) or lc < oldestChecked or (lc == oldestChecked and aa < oldestAdded) then
                oldestFallback = entry
                oldestChecked = lc
                oldestAdded = aa
            end
        end
    end

    if needCount == 0 then
        if not silent then
            ns:Print(L["All %d Watchlist players are already confirmed online via Friends or Guild."]:format(#entries))
        end
        ns:Emit("WATCHLIST_UPDATED")
        return true, "passive_ok"
    end

    local chosen = best or oldestFallback
    return chosen and self:CheckEntry(chosen.id, silent) or false
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

    local best, bestScore = nil, -1
    for _, entry in ipairs(entries) do
        local prio = ComputeWatchlistCheckPriority(entry, now)
        if prio > bestScore then
            bestScore = prio
            best = entry
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
        local ok, n, t = pcall(C_FriendList.GetNumWhoResults)
        if ok then
            numResults, totalCount = n, t
        end
    elseif GetNumWhoResults then
        local ok, n, t = pcall(GetNumWhoResults)
        if ok then
            numResults, totalCount = n, t
        end
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
            local ok, name, guild, level, _, classLoc, zone, classFileName = pcall(GetWhoInfo, i)
            name = ok and Safe.String(name) or nil
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

local function AppendPlayerTooltipLines(tooltip, isLegacyHook)
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

    local unitGuid = UnitGUID and Safe.String(Safe.Call(UnitGUID, unit))
    local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(unit, unitGuid, nil, true)
    local fullName = (resolved and resolved.fullName) or (UnitName and Safe.String(Safe.Call(UnitName, unit)))
    local parsed = fullName and Compat.ParseCharacterName and Compat.ParseCharacterName(fullName)
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
    local linkedAlts = Store and Store.GetLinkedAltsForCharacter and Store:GetLinkedAltsForCharacter(fullName)
    local dirEntry = ns.Social and ns.Social.GetDirectoryEntry and ns.Social:GetDirectoryEntry(lookupKey) or nil
    local nativeNote = (dirEntry and ((dirEntry.friendNote and dirEntry.friendNote ~= "" and dirEntry.friendNote)
        or (dirEntry.bnetNote and dirEntry.bnetNote ~= "" and dirEntry.bnetNote))) or nil
    local isPeer = ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(lookupKey)
    local savedPeer = (not isPeer) and ns.Chat and ns.Chat.GetSavedPeerRecord and ns.Chat:GetSavedPeerRecord(lookupKey) or nil
    local unitGuild = GetGuildInfo and Safe.String(Safe.Call(GetGuildInfo, unit))
    local guildStance = (unitGuild and unitGuild ~= "" and ns.Clan and ns.Clan.LookupGuildStance)
        and ns.Clan:LookupGuildStance(unitGuild) or nil
    if guildStance ~= "ENEMY" and guildStance ~= "ALLY" then
        guildStance = nil
    end
    local activeLfg = (ns.Clan and ns.Clan.GetActiveLfgForPlayer) and ns.Clan:GetActiveLfgForPlayer(lookupKey) or nil

    if not meta and not wl and not comp and not isPeer and not savedPeer and not guildStance and not linkedAlts and not nativeNote and not activeLfg then
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

    if nativeNote and (not meta or meta.note ~= nativeNote) and (not wl or wl.note ~= nativeNote) then
        tooltip:AddLine(L["Friend Note"] .. ": " .. nativeNote, 0.72, 0.88, 1.0, true)
    end

    if type(linkedAlts) == "table" and #linkedAlts > 0 then
        tooltip:AddDoubleLine(L["Known Alts"], table.concat(linkedAlts, ", "), 0.68, 0.78, 0.90, 0.80, 0.92, 1.0)
    end

    if comp and comp.lastSeen and (not Compat.IsModuleEnabled or Compat.IsModuleEnabled("group")) then
        local runsSuffix = (comp.runs and comp.runs > 1) and (" (x" .. comp.runs .. ")") or ""
        local compText = L["Recent companion: %s (%s)"]:format(
            comp.zone or L["Unknown"],
            Compat.FormatRelativeTime(comp.lastSeen, L)
        ) .. runsSuffix
        tooltip:AddLine(compText, 0.55, 0.80, 1.0, true)
    end

    if not (Compat.IsModuleEnabled and not Compat.IsModuleEnabled("clan")) then
        if guildStance == "ENEMY" then
            tooltip:AddLine("|cffff4d4d[" .. L["ENEMY"] .. "]|r <" .. unitGuild .. ">", 1.0, 0.35, 0.35)
        elseif guildStance == "ALLY" then
            tooltip:AddLine("|cff49c6ff[" .. L["ALLY"] .. "]|r <" .. unitGuild .. ">", 0.35, 0.78, 1.0)
        end
    end

    if isPeer then
        tooltip:AddLine("|cff3fb950[SocialCentral]|r", 0.30, 0.88, 0.48)
    elseif savedPeer then
        tooltip:AddLine("|cff58a6ff[SocialCentral · " .. L["Registered"] .. "]|r", 0.35, 0.65, 1.0)
    end
    if activeLfg then
        tooltip:AddLine("|cff3fb950[" .. tostring(activeLfg.mode or "LFG") .. "]|r " .. tostring(activeLfg.activity or L["Group"]), 0.35, 0.92, 0.55, true)
    end

    if isLegacyHook then
        pcall(tooltip.Show, tooltip)
    end
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
            AppendPlayerTooltipLines(tooltip, false)
        end)
    elseif GameTooltip and GameTooltip.HookScript and GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", function(t)
            AppendPlayerTooltipLines(t, true)
        end)
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

        local rawGuid = rawUnit and UnitGUID and Safe.String(Safe.Call(UnitGUID, rawUnit))
        if rawUnit and UnitIsPlayer and Safe.Bool(Safe.Call(UnitIsPlayer, rawUnit)) == true then
            local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(rawUnit, rawGuid, rawName, true)
            resolvedName = (resolved and resolved.fullName) or rawName or (UnitName and Safe.String(Safe.Call(UnitName, rawUnit)))
            parsed = resolvedName and Compat.ParseCharacterName and Compat.ParseCharacterName(resolvedName)
        elseif rawName and rawName ~= "" then
            if rawUnit and UnitIsPlayer and Safe.Bool(Safe.Call(UnitIsPlayer, rawUnit)) == false then
                return
            end
            parsed = Compat.ParseCharacterName(rawName)
            resolvedName = parsed and parsed.displayName or rawName
        end

        if not parsed or not resolvedName or Compat.IsMe(resolvedName, rawGuid) then
            return
        end

        local curMeta = Store and (Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(parsed.lookupKey or parsed.displayName) or (Store.GetSocialMeta and Store:GetSocialMeta(parsed.displayName)))
        local existingEntry = Watchlist:GetEntry(parsed.displayName)
        if existingEntry and parsed.surname and existingEntry.surname and existingEntry.surname:lower() ~= parsed.surname:lower() then
            existingEntry = nil
        end
        local isWatched = existingEntry ~= nil

        local bnId = contextData and Safe.Number(contextData.bnetIDAccount)
        local scConfirmed = ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(parsed.lookupKey or parsed.displayName, bnId)

        rootDescription:CreateDivider()
        rootDescription:CreateTitle("SocialCentral (" .. parsed.displayName .. ")")

        local chatModOn = (not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("chat")
        local watchModOn = (not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("watchlist")
        local radarModOn = (not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("radar")

        if scConfirmed and chatModOn then
            rootDescription:CreateButton(L["Message in SocialCentral"], function()
                if ns.NavigateToModule then
                    ns:NavigateToModule("chat", {
                        targetName = parsed.displayName,
                        bnetAccountID = bnId,
                    })
                end
            end)
        end

        if watchModOn then
            if isWatched and existingEntry then
                rootDescription:CreateButton(L["Remove from Watchlist"], function()
                    Watchlist:Remove(existingEntry.id)
                end)
            else
                rootDescription:CreateButton("+ " .. L["Add to Watchlist"], function()
                    Watchlist:Add(parsed.displayName)
                end)
            end
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

        if radarModOn and ns.SpotterHUD and ns.SpotterHUD.TrackEntry then
            local isTracked = ns.Spotter and ns.Spotter.IsPlayerTracked and ns.Spotter:IsPlayerTracked(parsed.displayName)
            if isTracked and ns.Spotter and ns.Spotter.UntrackPlayer then
                rootDescription:CreateButton(L["Untrack from Radar"], function()
                    ns.Spotter:UntrackPlayer(parsed.displayName)
                end)
            else
                rootDescription:CreateButton(L["Track on Radar"], function()
                    ns.SpotterHUD:TrackEntry({
                        displayName = parsed.displayName,
                        lookupKey = parsed.lookupKey,
                    }, "SOCIAL")
                end)
            end
        end
    end

    for _, tag in ipairs(menuTags) do
        pcall(Menu.ModifyMenu, tag, InjectMenu)
    end
end

function Watchlist:Init()
    -- Normalize stored Watchlist entries (Forever FirstName Surname format & clear stale truncation/online flags).
    local now = time()
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
            if entry.status == "online" then
                local lastConfirm = entry.lastSeen or entry.lastChecked or 0
                if (now - lastConfirm) >= INIT_STALE_ONLINE_SECONDS then
                    entry.status = "unknown"
                    entry._expiredOnline = true
                    if entry.source == "friend" or entry.source == "guild" or entry.source == "bnet" then
                        entry.source = nil
                    end
                end
            elseif entry.status == "offline" then
                entry._expiredOnline = nil
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
