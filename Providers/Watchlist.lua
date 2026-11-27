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
    _sessionBNetWatched = {}, -- session-only BNet friend watch slots before a WoW char name is observed (never saved to SavedVariables)
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
    if not IsSafeWhoFrame(root) then
        return
    end
    if not IsOwnAddonWhoFrame(root) and root.IsEventRegistered and root.UnregisterEvent and root.RegisterEvent then
        local ok, reg = pcall(root.IsEventRegistered, root, "WHO_LIST_UPDATE")
        if ok and reg then
            out[#out + 1] = root
        end
    end
    if depth > 1 and root.GetChildren then
        local nextDepth = depth - 1
        local function ScanChildrenVararg(...)
            local n = select("#", ...)
            for ci = 1, n do
                local child = select(ci, ...)
                if child then
                    CollectWhoListeningFrames(child, nextDepth, out, seen)
                end
            end
        end
        ScanChildrenVararg(root:GetChildren())
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

    local whoRootNames = {
        "FriendsFrame",
        "WhoFrame",
        "LFGParentFrame",
        "LFGWhoListFrame",
        "LFGListingFrame",
        "LFGBrowseFrame",
        "WhoListingFrame",
        "WhoListScrollFrame",
    }
    for i = 1, #whoRootNames do
        local root = _G[whoRootNames[i]]
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

local whoChatPatterns = nil

local function FormatTemplateToWhoPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local out, order, i, n = { "^" }, {}, 1, 0
    while i <= #fmt do
        local spec = fmt:match("^%%%d*%$?[sd]", i)
        if spec then
            n = n + 1
            local pos = spec:match("^%%(%d+)%$")
            order[#order + 1] = pos and tonumber(pos) or n
            out[#out + 1] = (spec:sub(-1) == "d") and "(%d+)" or "(.-)"
            i = i + #spec
        elseif fmt:sub(i, i + 1) == "%%" then
            out[#out + 1] = "%%"
            i = i + 2
        else
            local c = fmt:sub(i, i)
            out[#out + 1] = c:find("[%(%)%.%+%-%*%?%[%]%^%$%%]") and ("%" .. c) or c
            i = i + 1
        end
    end
    out[#out + 1] = "$"
    return table.concat(out), order
end

local function EnsureWhoChatPatterns()
    if whoChatPatterns then return whoChatPatterns end
    whoChatPatterns = {}
    for _, gName in ipairs({ "WHO_LIST_GUILD_FORMAT", "WHO_LIST_FORMAT" }) do
        local pat, ord = FormatTemplateToWhoPattern(_G[gName])
        if pat then
            whoChatPatterns[#whoChatPatterns + 1] = {
                pattern = pat,
                order = ord,
                hasGuild = (gName == "WHO_LIST_GUILD_FORMAT"),
            }
        end
    end
    return whoChatPatterns
end

local function MatchClassTokenAtEnd(raceClassText)
    if type(raceClassText) ~= "string" or raceClassText == "" then return nil end
    local direct = Compat.ClassFileFromLocalized and Compat.ClassFileFromLocalized(raceClassText)
    if direct then return direct end
    local bestToken, bestLen = nil, nil
    for _, tbl in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE or {}, _G.LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
        if type(tbl) == "table" then
            for token, locName in pairs(tbl) do
                if type(locName) == "string" and #locName > 0 then
                    if (raceClassText == locName or raceClassText:sub(-(#locName + 1)) == " " .. locName)
                        and (not bestLen or #locName > bestLen)
                    then
                        bestToken, bestLen = token, #locName
                    end
                end
            end
        end
    end
    return bestToken
end

local function ParseWhoSystemLine(clean)
    if type(clean) ~= "string" or clean == "" then return nil end
    for _, p in ipairs(EnsureWhoChatPatterns()) do
        local caps = { clean:match(p.pattern) }
        if #caps > 0 then
            local args = {}
            for j, idx in ipairs(p.order) do
                args[idx] = caps[j]
            end
            local rawName = args[1] or args[2]
            local parsed = rawName and Compat.ParseCharacterName(rawName)
            if parsed then
                local raceClass = ((args[4] or "") .. " " .. (args[5] or "")):gsub("^%s+", "")
                return {
                    parsed = parsed,
                    level = tonumber(args[3]),
                    classFile = MatchClassTokenAtEnd(raceClass),
                    guild = p.hasGuild and (args[6] or "") or "",
                    area = p.hasGuild and args[7] or args[6],
                    rawLine = clean,
                }
            end
        end
    end
    local playerLink, rest = clean:match("^|Hplayer:([^|]+)|h%[.-%]|?h?:%s*(.*)$")
    if not playerLink then
        playerLink = clean:match("^|Hplayer:([^|]+)|h%[.-%]:")
    end
    if playerLink then
        local parsed = Compat.ParseCharacterName(playerLink)
        if parsed then
            local lvl = rest and tonumber(rest:match("(%d+)")) or nil
            local guild = rest and rest:match("<([^>]+)>") or nil
            local area = rest and rest:match("%-%s*([^%-]+)$") or nil
            if area then area = Compat.Trim and Compat.Trim(area) or area end
            return {
                parsed = parsed,
                level = lvl,
                guild = guild or "",
                area = area,
                rawLine = clean,
            }
        end
    end
    return nil
end

local function SystemChatFilter(_, _, msg)
    if not Watchlist.pending then
        return false
    end
    local clean = Safe.String(msg)
    if not clean then return false end

    -- Match genuine /who output formats (both in chat_filter and silent_ui when server routes < 3 results to chat).
    local whoMatch = ParseWhoSystemLine(clean)
    if whoMatch and whoMatch.parsed then
        Watchlist.pending.chatMatches = Watchlist.pending.chatMatches or {}
        local dup = false
        for _, existing in ipairs(Watchlist.pending.chatMatches) do
            if existing.parsed and existing.parsed.lookupKey == whoMatch.parsed.lookupKey then
                dup = true
                if whoMatch.level and whoMatch.level > 0 then existing.level = whoMatch.level end
                if whoMatch.classFile then existing.classFile = whoMatch.classFile end
                if whoMatch.area and whoMatch.area ~= "" then existing.area = whoMatch.area end
                if whoMatch.guild and whoMatch.guild ~= "" then existing.guild = whoMatch.guild end
                break
            end
        end
        if not dup then
            table.insert(Watchlist.pending.chatMatches, whoMatch)
        end
        return true
    end

    -- Suppress trailing /who summary line ("0 players total" / "Total: 0 jogadores") during active query.
    local lower = clean:lower()
    local looksLikeWhoSummary = clean:find("%d+") and (lower:find("total") or lower:find("player") or lower:find("jogador") or lower:find("jugador") or lower:find("encontrad") or lower:find("pessoa"))
    if looksLikeWhoSummary then
        Watchlist.pending.sawSummary = true
        local pendingTok = Watchlist.pending.token
        C_Timer.After(0.06, function()
            if Watchlist.pending and Watchlist.pending.token == pendingTok then
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

function Watchlist:Add(rawName, note, opts)
    local parsed = Compat.ParseCharacterName(rawName)
    if not parsed or #(parsed.firstName or "") < 2 then return false, "invalid" end

    opts = type(opts) == "table" and opts or {}
    local list = Store:GetWatchlistTable()
    if list[parsed.lookupKey] then
        if opts.watchAllAlts and not list[parsed.lookupKey].watchAllAlts then
            list[parsed.lookupKey].watchAllAlts = true
            ns:Emit("WATCHLIST_UPDATED")
            return true, list[parsed.lookupKey]
        end
        if not opts.silent then
            ns:Print(L["%s is already on your Watchlist."]:format(parsed.displayName))
        end
        return false, "duplicate"
    end

    local cleanNote = Compat.CleanInput(note or "") or ""
    local dirEntry = ns.Social and ns.Social.GetDirectoryEntry and ns.Social:GetDirectoryEntry(parsed.lookupKey)
    if dirEntry and dirEntry.displayName and dirEntry.displayName ~= "" then
        local dirParsed = Compat.ParseCharacterName(dirEntry.displayName)
        if dirParsed and dirParsed.lookupKey == parsed.lookupKey then
            parsed = dirParsed
        end
    end
    local initStatus = "unknown"
    if dirEntry then
        if dirEntry.online and (dirEntry.bnetState == "wow_forever" or (dirEntry.sources and (dirEntry.sources.friend or dirEntry.sources.guild))) then
            initStatus = "online"
        elseif (not dirEntry.online) and (dirEntry.sources and (dirEntry.sources.friend or dirEntry.sources.guild)) then
            initStatus = "offline"
        end
    end

    local trackAlts = (opts.watchAllAlts == true) or (dirEntry and dirEntry.sources and dirEntry.sources.bnet == true) or nil
    list[parsed.lookupKey] = {
        id = parsed.lookupKey,
        displayName = parsed.displayName,
        firstName = parsed.firstName,
        surname = parsed.surname,
        note = cleanNote,
        group = (type(opts.group) == "string" and opts.group ~= "") and opts.group or nil,
        favorite = (opts.favorite == true) and true or nil,
        watchAllAlts = trackAlts,
        status = initStatus,
        source = (initStatus == "online" and dirEntry and dirEntry.sources)
            and ((dirEntry.sources.friend and "friend") or (dirEntry.sources.guild and "guild") or (dirEntry.sources.bnet and "bnet"))
            or nil,
        level = dirEntry and dirEntry.level or nil,
        classFile = dirEntry and dirEntry.classFile or nil,
        area = dirEntry and dirEntry.area or nil,
        guild = dirEntry and dirEntry.guild or nil,
        guid = dirEntry and dirEntry.guid or nil,
        lastChecked = (initStatus ~= "unknown" and dirEntry) and time() or nil,
        lastSeen = (initStatus == "online") and time() or (dirEntry and dirEntry.lastSeen) or nil,
        addedAt = time(),
    }

    if initStatus ~= "online" and ns.Chat and ns.Chat.QueuePresenceProbe then
        ns.Chat:QueuePresenceProbe(parsed.lookupKey, parsed.displayName, true)
    end

    if not opts.silent then
        if trackAlts then
            ns:Print(L["Added %s to your Watchlist (tracking all Battle.net / linked alts)."]:format(parsed.displayName))
        else
            ns:Print(L["Added %s to your Watchlist."]:format(parsed.displayName))
        end
    end
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

local function LinkKnownCharsPairwise(primaryKey, charsMap)
    if not (primaryKey and type(charsMap) == "table" and Store and Store.RecordObservedAltPair) then
        return
    end
    for altKey in pairs(charsMap) do
        if type(altKey) == "string" and altKey ~= "" and altKey ~= primaryKey then
            Store:RecordObservedAltPair(primaryKey, altKey)
        end
    end
end

--- Builds an O(N) map [bnetAccountID] = watchlistEntryId for fast picker rendering (avoids O(N^2) rescans).
function Watchlist:BuildWatchedBNetMap(bList)
    local out = {}
    if type(self._sessionBNetWatched) == "table" then
        for accId, sess in pairs(self._sessionBNetWatched) do
            if type(sess) == "table" and sess.id then
                out[accId] = sess.id
            end
        end
    end
    local list = Store:GetWatchlistTable()
    if type(list) ~= "table" or next(list) == nil then
        return out
    end
    if type(bList) == "table" then
        for i = 1, #bList do
            local bf = bList[i]
            local accId = bf and bf.bnetAccountID
            if accId and not out[accId] then
                if bf.lookupKey and list[bf.lookupKey] then
                    out[accId] = bf.lookupKey
                elseif bf.activeLookupKey and list[bf.activeLookupKey] then
                    out[accId] = bf.activeLookupKey
                elseif type(bf.knownChars) == "table" then
                    for ck in pairs(bf.knownChars) do
                        if list[ck] then
                            out[accId] = ck
                            break
                        end
                    end
                end
            end
        end
    end
    if ns.Social and ns.Social.GetBNetLinkInfo then
        for wlKey, wlEntry in pairs(list) do
            if type(wlEntry) == "table" then
                local bInfo = ns.Social:GetBNetLinkInfo(wlEntry.id or wlKey)
                if bInfo and bInfo.bnetAccountID and not out[bInfo.bnetAccountID] then
                    out[bInfo.bnetAccountID] = wlKey
                end
            end
        end
    end
    return out
end

function Watchlist:RemoveBNetAccount(bnetAccId)
    if not bnetAccId then
        return false
    end
    local isW, wlId = self:IsBNetAccountWatched(bnetAccId)
    if not (isW and wlId) then
        return false
    end
    return self:Remove(wlId)
end

function Watchlist:IsBNetAccountWatched(bnetAccId)
    if not bnetAccId then
        return false, nil, nil
    end
    if self._sessionBNetWatched and self._sessionBNetWatched[bnetAccId] then
        local sess = self._sessionBNetWatched[bnetAccId]
        return true, sess.id, sess
    end
    local list = Store:GetWatchlistTable()
    if type(list) ~= "table" or next(list) == nil then
        return false, nil, nil
    end
    local friends = (ns.Social and ns.Social.GetBNetFriendsList) and ns.Social:GetBNetFriendsList() or {}
    local targetItem
    for _, bf in ipairs(friends) do
        if bf.bnetAccountID == bnetAccId then
            targetItem = bf
            break
        end
    end
    if targetItem then
        if targetItem.lookupKey and list[targetItem.lookupKey] then
            return true, targetItem.lookupKey, list[targetItem.lookupKey]
        end
        if targetItem.activeLookupKey and list[targetItem.activeLookupKey] then
            return true, targetItem.activeLookupKey, list[targetItem.activeLookupKey]
        end
        if type(targetItem.knownChars) == "table" then
            for ck in pairs(targetItem.knownChars) do
                if list[ck] then
                    return true, ck, list[ck]
                end
            end
        end
    end
    for wlKey, wlEntry in pairs(list) do
        if type(wlEntry) == "table" and ns.Social and ns.Social.GetBNetLinkInfo then
            local bInfo = ns.Social:GetBNetLinkInfo(wlEntry.id or wlKey)
            if bInfo and bInfo.bnetAccountID == bnetAccId then
                return true, wlKey, wlEntry
            end
        end
    end
    return false, nil, nil
end

function Watchlist:AddBNetAccount(bnetItem)
    if type(bnetItem) ~= "table" then
        return false, "invalid"
    end
    local accId = bnetItem.bnetAccountID
    local bnetName = bnetItem.bnetName or bnetItem.displayName or "Battle.net"
    local list = Store:GetWatchlistTable()

    local primaryName = bnetItem.activeDisplayName
        or ((bnetItem.hasCharacterName ~= false and bnetItem.displayName and not tostring(bnetItem.displayName):find("#", 1, true) and not tostring(bnetItem.displayName):find("|K", 1, true)) and bnetItem.displayName or nil)
    if not primaryName and type(bnetItem.knownChars) == "table" then
        for _, disp in pairs(bnetItem.knownChars) do
            if type(disp) == "string" and disp ~= "" then
                primaryName = disp
                break
            end
        end
    end

    local already, existingKey, existingEntry = self:IsBNetAccountWatched(accId)
    if already and existingEntry then
        if existingEntry.isSessionBNet and primaryName then
            return self:PromoteSessionBNetAccount(accId, primaryName, bnetItem)
        end
        if not existingEntry.isSessionBNet then
            existingEntry.watchAllAlts = true
            LinkKnownCharsPairwise(existingKey, bnetItem.knownChars)
            ns:Print(L["%s now tracks all Battle.net & linked characters."]:format(existingEntry.displayName or bnetName))
            ns:Emit("WATCHLIST_UPDATED")
            return true, existingEntry
        end
        ns:Print(L["%s is already on your Watchlist."]:format(bnetName))
        return false, "duplicate"
    end

    if primaryName then
        local parsedPrimary = Compat.ParseCharacterName and Compat.ParseCharacterName(primaryName)
        local primaryKey = parsedPrimary and parsedPrimary.lookupKey or nil
        if primaryKey and Store.GetAllLinkedCharacters then
            for _, altRec in ipairs(Store:GetAllLinkedCharacters(primaryKey)) do
                if altRec and altRec.lookupKey and list[altRec.lookupKey] then
                    local altEntry = list[altRec.lookupKey]
                    altEntry.watchAllAlts = true
                    LinkKnownCharsPairwise(altRec.lookupKey, bnetItem.knownChars)
                    Store:RecordObservedAltPair(altRec.lookupKey, primaryKey)
                    if bnetItem.activeLookupKey and bnetItem.activeDisplayName and bnetItem.activeLookupKey ~= altRec.lookupKey then
                        altEntry.activeAltLookup = bnetItem.activeLookupKey
                        altEntry.activeAltName = bnetItem.activeDisplayName
                        altEntry.activeAltClass = bnetItem.classFile
                        altEntry.activeAltLevel = bnetItem.level
                        altEntry.status = "online"
                        altEntry.source = "bnet"
                        altEntry.lastSeen = time()
                    end
                    ns:Print(L["%s now tracks all Battle.net & linked characters."]:format(altEntry.displayName or primaryName))
                    ns:Emit("WATCHLIST_UPDATED")
                    return true, altEntry
                end
            end
        end
        local ok, entry = self:Add(primaryName, nil, { watchAllAlts = true })
        if ok and entry then
            LinkKnownCharsPairwise(entry.id, bnetItem.knownChars)
            if accId then
                self._sessionBNetWatched[accId] = nil
            end
            return true, entry
        end
        return ok, entry
    end

    if not accId then
        ns:Print(L["Could not add this Battle.net account right now."])
        return false, "invalid"
    end
    local sessId = "bnet_session:" .. tostring(accId)
    self._sessionBNetWatched[accId] = {
        id = sessId,
        bnetAccountID = accId,
        displayName = bnetName,
        bnetName = bnetName,
        isSessionBNet = true,
        watchAllAlts = true,
        online = bnetItem.online == true,
        bnetState = bnetItem.bnetState or "offline",
        richPresence = bnetItem.richPresence,
        clientProgram = bnetItem.clientProgram,
        status = (bnetItem.online == true) and "online" or "offline",
        source = "bnet",
        addedAt = time(),
        lastSeen = (bnetItem.online == true) and time() or nil,
    }
    ns:Print(L["Added Battle.net friend %s for this session. As soon as they log into WoW on any character, it will stay saved permanently across all their alts."]:format(bnetName))
    ns:Emit("WATCHLIST_UPDATED")
    return true, self._sessionBNetWatched[accId]
end

function Watchlist:PromoteSessionBNetAccount(bnetAccId, charDisplayName, obsData)
    local sess = bnetAccId and self._sessionBNetWatched and self._sessionBNetWatched[bnetAccId]
    if not sess or not charDisplayName or charDisplayName == "" then
        return false, nil
    end
    self._sessionBNetWatched[bnetAccId] = nil
    local ok, entry = self:Add(charDisplayName, sess.note, {
        watchAllAlts = true,
        silent = true,
        group = sess.group,
        favorite = sess.favorite == true,
    })
    if not ok then
        entry = self:GetEntry(charDisplayName)
        if entry then
            entry.watchAllAlts = true
        end
    end
    if entry and type(obsData) == "table" then
        entry.status = "online"
        entry.source = "bnet"
        entry.lastSeen = time()
        if obsData.classFile then entry.classFile = obsData.classFile end
        if obsData.level and obsData.level > 0 then entry.level = obsData.level end
        if obsData.area and obsData.area ~= "" then entry.area = obsData.area end
        if obsData.guid and obsData.guid ~= "" then entry.guid = obsData.guid end
    end
    ns:Emit("WATCHLIST_UPDATED")
    return entry ~= nil, entry
end

function Watchlist:ToggleWatchAllAlts(id)
    local entry = self:GetEntry(id)
    if not entry or entry.isSessionBNet then
        return false
    end
    local nextVal = not (entry.watchAllAlts == true)
    entry.watchAllAlts = nextVal and true or nil
    if not nextVal then
        entry.activeAltLookup = nil
        entry.activeAltName = nil
        entry.activeAltClass = nil
        entry.activeAltLevel = nil
    end
    ns:Emit("WATCHLIST_UPDATED")
    return nextVal
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
    local storeDirty = (Store and Store._wlIndexDirty) == true
    if Watchlist._wlIndexDirty or storeDirty or Watchlist._wlIndexedTbl ~= list or type(idx) ~= "table" then
        idx = {}
        for _, e in pairs(list) do
            if type(e) == "table" then
                if e.id and not idx[e.id] then idx[e.id] = e end
                if e.lookupKey and not idx[e.lookupKey] then idx[e.lookupKey] = e end
                if e.displayName then
                    local dl = e.displayName:lower()
                    if not idx[dl] then idx[dl] = e end
                end
                if e.firstName and (not e.surname or e.surname == "") then
                    local fl = e.firstName:lower()
                    if not idx[fl] then idx[fl] = e end
                end
            end
        end
        Watchlist._wlFastIndex = idx
        Watchlist._wlIndexedTbl = list
        Watchlist._wlIndexDirty = false
        if storeDirty and Store then
            Store._wlIndexDirty = false
            -- Clear Store's auxiliary table so SyncWatchlistObservation still rebuilds its own caches next pass.
            Store._wlNoSurnameByFirst = nil
        end
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
    local hit = (parsed and parsed.lookupKey and idx[parsed.lookupKey]) or idx[low]
    if hit and hit.id and list[hit.id] == hit then
        return hit
    elseif hit then
        Watchlist._wlIndexDirty = true
        idx = EnsureWatchlistFastIndex(list)
        local retry = (parsed and parsed.lookupKey and idx[parsed.lookupKey]) or idx[low]
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
    if type(id) == "string" and id:sub(1, 13) == "bnet_session:" then
        local accNum = tonumber(id:sub(14))
        local sess = accNum and self._sessionBNetWatched and self._sessionBNetWatched[accNum]
        if sess then
            self._sessionBNetWatched[accNum] = nil
            ns:Print(L["Removed %s from your Watchlist."]:format(sess.displayName or "Battle.net"))
            ns:Emit("WATCHLIST_UPDATED")
            return true
        end
    end
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
    local curFav = (entry.favorite == true) or (Store.IsSocialFavorite and Store:IsSocialFavorite(id) == true)
    local nextFav = not curFav
    entry.favorite = nextFav
    if Store and Store.SetSocialFavorite then
        Store:SetSocialFavorite(id, nextFav)
    else
        ns:Emit("WATCHLIST_UPDATED")
    end
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
local STALE_UNKNOWN_OFFLINE_SECONDS = 900
local INIT_STALE_ONLINE_SECONDS = 180

local function IsRosterConfirmedOnline(socRow)
    if type(socRow) ~= "table" or socRow.online ~= true then
        return false
    end
    if socRow.friendOnline == true or socRow.guildOnline == true then
        return true
    end
    if socRow.bnetOnline == true and socRow.bnetState == "wow_forever" then
        return true
    end
    return false
end

local function IsEntryLiveConfirmed(entry, now)
    if type(entry) ~= "table" then return false end
    local socRow = Store and Store.socialByLookup and entry.id and Store.socialByLookup[entry.id]
    if IsRosterConfirmedOnline(socRow) then
        return true
    end
    if entry.activeAltLookup and Store and Store.socialByLookup and IsRosterConfirmedOnline(Store.socialByLookup[entry.activeAltLookup]) then
        return true
    end
    local isConnGrp = Compat.IsInMyGroupConnected or Compat.IsInMyGroup
    if isConnGrp and isConnGrp(entry.activeAltName or entry.displayName, entry.guid) then
        return true
    end
    local nearbyRow = Store and Store.nearby and entry.id and Store.nearby[entry.id]
    if nearbyRow and (now - (nearbyRow.lastSeen or 0)) <= 180 then
        return true
    end
    if entry.activeAltLookup and Store and Store.nearby and Store.nearby[entry.activeAltLookup] and (now - (Store.nearby[entry.activeAltLookup].lastSeen or 0)) <= 180 then
        return true
    end
    return false
end

function Watchlist:ExpireStaleOnlineEntries(silentEmit)
    if ns.DemoShowcase and ns.DemoShowcase.IsActive and ns.DemoShowcase:IsActive() then return false end
    local list = Store:GetWatchlistTable()
    if type(list) ~= "table" or next(list) == nil then
        return false
    end
    local now = time()
    local changed = false
    for _, entry in pairs(list) do
        if type(entry) == "table" and not entry.isSessionBNet then
            if entry.status == "online" then
                if not IsEntryLiveConfirmed(entry, now) then
                    if entry.source == "friend" or entry.source == "guild" or entry.source == "bnet" then
                        entry.source = nil
                    end
                    local lastConfirm = entry.lastSeen or entry.lastChecked or 0
                    local age = now - lastConfirm
                    if age >= STALE_UNKNOWN_OFFLINE_SECONDS then
                        entry.status = "offline"
                        entry._expiredOnline = nil
                        entry._staleSettled = true
                        changed = true
                    elseif age >= STALE_ONLINE_SECONDS then
                        entry.status = "unknown"
                        entry._expiredOnline = true
                        changed = true
                        if ns.Chat and ns.Chat.QueuePresenceProbe and entry.id and entry.displayName then
                            ns.Chat:QueuePresenceProbe(entry.id, entry.displayName, true)
                        end
                    end
                end
            elseif entry.status == "unknown" then
                if not IsEntryLiveConfirmed(entry, now) then
                    local lastConfirm = entry.lastSeen or entry.lastChecked or 0
                    if lastConfirm > 0 and (now - lastConfirm) >= STALE_UNKNOWN_OFFLINE_SECONDS then
                        entry.status = "offline"
                        entry._expiredOnline = nil
                        entry._staleSettled = true
                        changed = true
                    end
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
            include = (entry.favorite == true) or (Store.IsSocialFavorite and Store:IsSocialFavorite(entry.id) == true)
        elseif groupFilter and groupFilter ~= "all" then
            include = entry.group == groupFilter
        end
        if include then
            table.insert(out, entry)
        end
    end
    if self._sessionBNetWatched and next(self._sessionBNetWatched) ~= nil then
        local liveBNet = {}
        if ns.Social and ns.Social.GetBNetFriendsList then
            for _, bf in ipairs(ns.Social:GetBNetFriendsList()) do
                liveBNet[bf.bnetAccountID] = bf
            end
        end
        for accId, sess in pairs(self._sessionBNetWatched) do
            local bf = liveBNet[accId]
            if bf then
                sess.online = bf.online == true
                sess.bnetState = bf.bnetState or sess.bnetState
                sess.richPresence = bf.richPresence
                sess.bnetName = bf.bnetName or sess.bnetName
                sess.displayName = bf.bnetName or sess.displayName
                sess.status = (bf.online == true) and "online" or "offline"
                if bf.online == true then sess.lastSeen = time() end
            end
            local include = true
            if groupFilter == "__fav" then
                include = (sess.favorite == true)
            elseif groupFilter and groupFilter ~= "all" then
                include = sess.group == groupFilter
            end
            if include then
                table.insert(out, sess)
            end
        end
    end

    local mode = sortBy or (ns.db and ns.db.settings and ns.db.settings.sortBy) or "status"
    table.sort(out, function(a, b)
        local favA = ((a.favorite == true) or (Store.IsSocialFavorite and Store:IsSocialFavorite(a.id) == true)) and 1 or 0
        local favB = ((b.favorite == true) or (Store.IsSocialFavorite and Store:IsSocialFavorite(b.id) == true)) and 1 or 0
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
    if (not entry.surname or entry.surname == "") and entry.firstName and candidateParsed.firstName
        and entry.firstName:lower() == candidateParsed.firstName:lower()
    then
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

    if ns.Social and ns.Social.GetBNetFriendsList then
        for _, bf in ipairs(ns.Social:GetBNetFriendsList()) do
            if not self:IsBNetAccountWatched(bf.bnetAccountID) then
                local bn = bf.bnetName or ""
                local disp = bf.activeDisplayName or bf.displayName or bn
                local bnLow = bn:lower()
                local dLow = disp:lower()
                if (bnLow ~= "" and bnLow:find(qLow, 1, true)) or (dLow ~= "" and dLow:find(qLow, 1, true)) then
                    local bKey = "bnet_acc:" .. tostring(bf.bnetAccountID)
                    candidates[bKey] = {
                        _isBNetAccountCandidate = true,
                        bnetAccountID = bf.bnetAccountID,
                        bnetName = bn,
                        displayName = (bf.activeDisplayName and (bf.activeDisplayName .. " (" .. bn .. ")")) or bn,
                        lookupKey = bf.lookupKey or bKey,
                        hasCharacterName = bf.hasCharacterName,
                        activeLookupKey = bf.activeLookupKey,
                        activeDisplayName = bf.activeDisplayName,
                        knownChars = bf.knownChars,
                        classFile = bf.classFile,
                        level = bf.level,
                        online = bf.online == true,
                        bnetState = bf.bnetState,
                        richPresence = bf.richPresence,
                        clientProgram = bf.clientProgram,
                        sourceLabel = "Battle.net · " .. (L["All Alts"] or "All Alts"),
                        score = (bf.online and 110 or 75),
                    }
                end
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
                local isDirectMatch = parsed and MatchEntry(entry, parsed)
                local isAltMatch = false
                if not isDirectMatch and parsed and entry.watchAllAlts == true and Store and Store.GetAllLinkedCharacters then
                    for _, altRec in ipairs(Store:GetAllLinkedCharacters(entry.id or listKey)) do
                        if altRec and altRec.lookupKey == parsed.lookupKey then
                            isAltMatch = true
                            break
                        end
                    end
                end
                if parsed and (isDirectMatch or isAltMatch) then
                    local prevStatus = entry.status
                    local wasExpired = (entry._expiredOnline == true)
                    local hasSurname = type(entry.surname) == "string" and entry.surname ~= ""
                    local candidateOnly = isDirectMatch and (not hasSurname) and parsed.surname and parsed.surname ~= ""
                    entry.status = "online"
                    entry._expiredOnline = nil
                    entry._needsWhoEnrich = nil
                    entry.source = "who"
                    entry.lastChecked = now
                    entry.lastSeen = now
                    entry.truncatedWarning = nil
                    entry.ambiguousChoices = nil
                    if isAltMatch then
                        entry.activeAltLookup = parsed.lookupKey
                        entry.activeAltName = parsed.displayName
                        if m.classFile then entry.activeAltClass = m.classFile end
                        if m.level and m.level > 0 then entry.activeAltLevel = m.level end
                    else
                        entry.activeAltLookup = nil
                        entry.activeAltName = nil
                        entry.activeAltClass = nil
                        entry.activeAltLevel = nil
                        if m.level and m.level > 0 then entry.level = m.level end
                        if m.classFile then entry.classFile = m.classFile end
                    end
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
                        ns.Clan:QueueCooperativeSighting(parsed.displayName, (not isAltMatch) and entry.guid or nil, m.level, m.classFile, m.guild, m.area)
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
            if IsRosterConfirmedOnline(socRow) then
                targetEntry.status = "online"
                targetEntry._expiredOnline = nil
            elseif pending.probedAltKey and pending.probedAltKey ~= targetEntry.id and targetEntry.status == "online" and targetEntry.activeAltLookup ~= pending.probedAltKey then
                -- Keep current online state if another alt is already confirmed active.
                targetEntry._expiredOnline = nil
            else
                if pending.probedAltKey and targetEntry.activeAltLookup == pending.probedAltKey then
                    targetEntry.activeAltLookup = nil
                    targetEntry.activeAltName = nil
                    targetEntry.activeAltClass = nil
                    targetEntry.activeAltLevel = nil
                end
                targetEntry.status = "offline"
                targetEntry._expiredOnline = nil
                targetEntry._needsWhoEnrich = nil
            end
            targetEntry.truncatedWarning = nil
        end
    end

    if Watchlist.pending and Watchlist.pending.mode == "silent_ui" then
        Watchlist.suppressPopupUntil = GetTime() + 0.35
    end
    CleanupPending(true)
    if Store and Store.RecordLiveUnitObservation then
        for _, m in ipairs(matches) do
            local p = m and m.parsed
            if p and p.displayName and ((m.level and m.level > 0) or (m.area and m.area ~= "")) then
                Store:RecordLiveUnitObservation(p.displayName, {
                    level = m.level,
                    classFile = m.classFile,
                    area = m.area,
                    guild = m.guild,
                    source = "who",
                })
            end
        end
    end
    if ns.Social and ns.Social.QueueScan then
        ns.Social:QueueScan(0.15)
    end
    ns:Emit("WATCHLIST_UPDATED")
    if disambiguateTarget then
        local pickLink = "|Haddon:SCentral:wldisambig:" .. tostring(disambiguateTarget.id) .. "|h|cff58a6ff[" .. L["Choose"] .. "]|r|h"
        ns:Print("%s %s", L["Multiple characters match '%s'; select the exact FirstName Surname:"]:format(disambiguateTarget.displayName), pickLink)
        ns:Emit("WATCHLIST_DISAMBIGUATE", disambiguateTarget.id)
    end
end

function Watchlist:FinishChatFilterQuery()
    if not self.pending then return end
    local results = {}
    for _, item in ipairs(self.pending.chatMatches or {}) do
        table.insert(results, {
            parsed = item.parsed,
            level = item.level,
            classFile = item.classFile,
            area = item.area,
            guild = item.guild,
        })
    end
    self:ApplyWhoResults(results, #results)
end

-- Shared single C_FriendList.SendWho hardware-event dispatcher (never invoked from timers/passive events).
local function DispatchHardwareWho(self, targetId, probedAltKey, queryDisplay, fallbackSurname, fallbackFirst, silent, entry)
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

    local queryParsed = Compat.ParseCharacterName and Compat.ParseCharacterName(queryDisplay)
    local cleanFirst = ((queryParsed and queryParsed.firstName) or fallbackFirst or ""):gsub('["\\%*%?%c|]', "")
    if #cleanFirst < 2 then
        return false, "invalid"
    end

    local qSurname = (queryParsed and queryParsed.surname) or fallbackSurname or nil
    local rawFull = (qSurname and qSurname ~= "") and (cleanFirst .. " " .. qSurname) or (queryDisplay or cleanFirst)
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
        id = targetId,
        probedAltKey = probedAltKey,
        displayName = queryDisplay,
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
    end
    self.chatFilterActive = true
    AddChatFilter(SystemChatFilter)

    local query = ('n-"%s"'):format(cleanQuery)
    local sentOk = pcall(C_FriendList.SendWho, query)
    if sentOk then
        if entry then
            entry._lastWhoCheckedAt = time()
        end
        if ns.Chat and ns.Chat.RecordOutboundOrigin then
            ns.Chat:RecordOutboundOrigin("WHO", "WHO", cleanQuery, "SocialCentral")
        end
    end
    if not sentOk then
        CleanupPending()
        return false, "send_failed"
    end

    -- Safety timeout in case server silently throttles the query; back off extra 10s.
    C_Timer.After(3.5, function()
        if Watchlist.pending and Watchlist.pending.token == token then
            if Watchlist.pending.chatMatches and #Watchlist.pending.chatMatches > 0 then
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

-- Must ONLY be called directly inside a hardware event (button click, slash command, keybind).
function Watchlist:CheckEntry(id, silent, forceWho)
    local list = Store:GetWatchlistTable()
    local entry = list[id]
    if not entry then return false, "missing" end

    if (not silent or forceWho) and ns.Social and ns.Social.RequestRosters then
        ns.Social:RequestRosters(true)
    end

    local socRow = Store.socialByLookup and Store.socialByLookup[entry.id]
    if (not forceWho) and IsRosterConfirmedOnline(socRow) then
        local src = (socRow.bnetOnline and socRow.bnetState == "wow_forever" and "bnet")
            or (socRow.friendOnline and "friend")
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

    if (not entry.surname or entry.surname == "") and entry.displayName and (entry.displayName:find(" ") or entry.displayName:find("-")) then
        local normalized = Compat.ParseCharacterName(entry.displayName)
        if normalized then
            entry.firstName = normalized.firstName
            entry.surname = normalized.surname
            entry.displayName = normalized.displayName
        end
    end

    local queryDisplay = entry.displayName
    local probedAltKey = entry.id
    if entry.status == "online" and entry.activeAltName and entry.activeAltName ~= "" then
        queryDisplay = entry.activeAltName
        probedAltKey = entry.activeAltLookup or entry.id
    elseif entry.watchAllAlts == true and entry.status ~= "online" and Store and Store.GetAllLinkedCharacters then
        local linked = Store:GetAllLinkedCharacters(entry.id)
        if type(linked) == "table" and #linked > 0 then
            local pool = { { lookupKey = entry.id, displayName = entry.displayName } }
            for _, altRec in ipairs(linked) do
                if altRec and altRec.displayName and altRec.lookupKey and altRec.lookupKey ~= entry.id then
                    pool[#pool + 1] = altRec
                end
            end
            if #pool > 1 then
                local idx = ((entry._whoAltCursor or 0) % #pool) + 1
                entry._whoAltCursor = idx
                queryDisplay = pool[idx].displayName
                probedAltKey = pool[idx].lookupKey
            end
        end
    end

    local fallbackSurname = (probedAltKey == entry.id) and entry.surname or nil
    return DispatchHardwareWho(self, entry.id, probedAltKey, queryDisplay, fallbackSurname, entry.firstName, silent, entry)
end

-- Must ONLY be called directly inside a hardware event (Social / Nearby context click).
function Watchlist:CheckCharacter(rawName, silent)
    if type(rawName) ~= "string" or rawName == "" then return false, "invalid" end
    if ns.Social and ns.Social.RequestRosters then
        ns.Social:RequestRosters(true)
    end
    local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(rawName)
    local lookupKey = parsed and parsed.lookupKey or nil
    local existing = lookupKey and self.GetEntry and self:GetEntry(lookupKey) or nil
    if existing then
        return self:CheckEntry(existing.id, silent, true)
    end
    local disp = (parsed and parsed.displayName) or rawName
    return DispatchHardwareWho(self, lookupKey or disp:lower(), lookupKey, disp, parsed and parsed.surname or nil, parsed and parsed.firstName or nil, silent, nil)
end

-- Expected Information Gain (VOI) priority for /who checks (unknown & active favorites first, O(M) single pass).
local function ComputeWatchlistCheckPriority(entry, now)
    if type(entry) ~= "table" or entry.isSessionBNet then return -1 end
    local socRow = Store and Store.socialByLookup and entry.id and Store.socialByLookup[entry.id]
    if IsRosterConfirmedOnline(socRow) then
        return -1
    end
    if entry.activeAltLookup and Store and Store.socialByLookup and IsRosterConfirmedOnline(Store.socialByLookup[entry.activeAltLookup]) then
        return -1
    end
    local dirRow = Store and Store.socialDirectoryByLookup and entry.id and Store.socialDirectoryByLookup[entry.id]
    local isGuildOff = Store and Store.guildOfflineByLookup and entry.id and Store.guildOfflineByLookup[entry.id] == true
    -- Battle.net being offline never confirms a character is offline in WoW (players may Appear Offline / Invisible on BNet).
    local isPassiveKnown = isGuildOff or (dirRow ~= nil and dirRow.sources ~= nil and (dirRow.sources.friend == true or dirRow.sources.guild == true))
    local age = entry.lastChecked and math.max(0, now - entry.lastChecked) or 999999
    local isUnknown = (entry.status == "unknown")
    local needsEnrich = (entry.status == "online" and entry._needsWhoEnrich == true)
    local isUnverifiedOnline = (entry.status == "online")
    if not isUnknown and not needsEnrich then
        local minAge = isUnverifiedOnline and 20 or (isPassiveKnown and 120 or 30)
        if age < minAge then
            return -1
        end
    end
    local favMult = (entry.favorite == true) and 1.8 or 1.0
    local seenAge = entry.lastSeen and math.max(0, now - entry.lastSeen) or (14 * 86400)
    local activePrior = 1.0 + (0.5 / (1 + (seenAge / 86400)))
    local passivePenalty = isPassiveKnown and 0.15 or 1.0
    local base = isUnknown and (1000000 + (entry._expiredOnline and 50000 or 0) + math.min(age, 86400))
        or (needsEnrich and (850000 + math.min(age, 86400)))
        or (isUnverifiedOnline and (50000 + math.min(age, 86400)) or (math.min(age, 86400) * 0.35))
    return base * favMult * activePrior * passivePenalty
end

-- Picks the entry needing verification most urgently; when all entries are online in Social/Friends/Guild,
-- refreshes rosters and runs a safe /who on the stalest online character so levels/zones stay accurate.
function Watchlist:CheckNext(silent)
    if ns.Social and ns.Social.RequestRosters then
        ns.Social:RequestRosters(true)
    end
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
    local oldestOnlineFallback, oldestOnlineWhoAt, oldestOnlineChecked, oldestOnlineAdded = nil, nil, nil, nil
    for _, entry in ipairs(entries) do
        if not entry.isSessionBNet then
            local socRow = Store and Store.socialByLookup and entry.id and Store.socialByLookup[entry.id]
            local altRow = (entry.activeAltLookup and Store and Store.socialByLookup) and Store.socialByLookup[entry.activeAltLookup] or nil
            local isPassiveOnline = IsRosterConfirmedOnline(socRow) or IsRosterConfirmedOnline(altRow)
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
            else
                local wAt = entry._lastWhoCheckedAt or 0
                local lc = entry.lastChecked or 0
                local aa = entry.addedAt or 0
                if (not oldestOnlineFallback) or wAt < oldestOnlineWhoAt
                    or (wAt == oldestOnlineWhoAt and (lc < oldestOnlineChecked or (lc == oldestOnlineChecked and aa < oldestOnlineAdded)))
                then
                    oldestOnlineFallback = entry
                    oldestOnlineWhoAt = wAt
                    oldestOnlineChecked = lc
                    oldestOnlineAdded = aa
                end
            end
        end
    end

    if needCount == 0 then
        if oldestOnlineFallback then
            return self:CheckEntry(oldestOnlineFallback.id, silent, true)
        end
        if not silent then
            ns:Print(L["All %d Watchlist players are already confirmed online via Friends or Guild."]:format(#entries))
        end
        ns:Emit("WATCHLIST_UPDATED")
        return true, "passive_ok"
    end

    local chosen = best or oldestFallback
    return chosen and self:CheckEntry(chosen.id, silent, true) or false
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

    if Watchlist.pending and type(Watchlist.pending.chatMatches) == "table" then
        for _, cm in ipairs(Watchlist.pending.chatMatches) do
            if cm and cm.parsed then
                local seen = false
                for _, m in ipairs(matches) do
                    if m.parsed and m.parsed.lookupKey == cm.parsed.lookupKey then
                        seen = true
                        if (not m.level or m.level <= 0) and cm.level then m.level = cm.level end
                        if not m.classFile and cm.classFile then m.classFile = cm.classFile end
                        if (not m.area or m.area == "") and cm.area then m.area = cm.area end
                        if (not m.guild or m.guild == "") and cm.guild then m.guild = cm.guild end
                        break
                    end
                end
                if not seen then
                    matches[#matches + 1] = {
                        parsed = cm.parsed,
                        level = cm.level,
                        classFile = cm.classFile,
                        area = cm.area,
                        guild = cm.guild or "",
                    }
                end
            end
        end
        if #matches > totalCount then
            totalCount = #matches
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
    local acctIgn = Store and Store.GetAccountIgnore and Store:GetAccountIgnore(lookupKey) or nil
    local noteMain = (not (meta and meta.mainName and meta.mainName ~= "") and dirEntry and dirEntry.guildNote and Compat.ExtractMainFromGuildNote)
        and Compat.ExtractMainFromGuildNote(dirEntry.guildNote) or nil
    local socProf = (lookupKey and ns.Clan and ns.Clan.GetPlayerSocialProfile) and ns.Clan:GetPlayerSocialProfile(lookupKey) or nil

    if not meta and not noteMain and not acctIgn and not wl and not comp and not isPeer and not savedPeer and not guildStance and not linkedAlts and not nativeNote and not activeLfg and not socProf then
        return
    end

    tooltip._scPlayerKey = lookupKey
    tooltip:AddLine(" ")

    if acctIgn then
        local rLbl = Store.FormatIgnoreReason and Store:FormatIgnoreReason(acctIgn.reason, L) or (acctIgn.reason or "")
        local remLbl = Store.FormatIgnoreRemaining and Store:FormatIgnoreRemaining(acctIgn.expiresAt, L) or ""
        local ignLine = "|cffff4d4d[!] " .. L["ACCOUNT IGNORED"] .. " (" .. rLbl .. (remLbl ~= "" and (" · " .. remLbl) or "") .. ")|r"
        tooltip:AddLine(ignLine, 1.0, 0.30, 0.30)
        if acctIgn.note and acctIgn.note ~= "" and (not meta or meta.note ~= acctIgn.note) then
            tooltip:AddLine(L["Note"] .. ": " .. acctIgn.note, 1.0, 0.72, 0.50, true)
        end
    elseif meta and meta.flag == "AVOID" then
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

    if meta and meta.nickname and meta.nickname ~= "" then
        tooltip:AddDoubleLine(L["Nickname"], "|cffffd24d" .. meta.nickname .. "|r", 0.68, 0.78, 0.90, 1.0, 0.85, 0.35)
    end

    local resolvedMain = (meta and meta.mainName and meta.mainName ~= "" and meta.mainName) or noteMain
    if resolvedMain and resolvedMain ~= "" then
        tooltip:AddDoubleLine(L["Main"], resolvedMain, 0.68, 0.78, 0.90, 0.88, 0.94, 1.0)
    end

    if meta then
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
    if socProf then
        local spParts = {}
        if socProf.role and socProf.role ~= "" then spParts[#spParts + 1] = socProf.role end
        if socProf.availability and socProf.availability ~= "" then
            local availLabels = { OPEN = L["Open to Groups"], QUEST = L["Questing"], BUSY = L["Busy"] }
            spParts[#spParts + 1] = availLabels[socProf.availability] or socProf.availability
        end
        if socProf.langs and socProf.langs ~= "" then spParts[#spParts + 1] = socProf.langs end
        if socProf.hours and socProf.hours ~= "" then spParts[#spParts + 1] = socProf.hours end
        if #spParts > 0 then
            tooltip:AddLine("|cff6ec1e4" .. L["Social Profile"] .. ":|r " .. table.concat(spParts, " · "), 0.85, 0.92, 0.98, true)
        end
        if socProf.bio and socProf.bio ~= "" then
            tooltip:AddLine("  " .. socProf.bio, 0.78, 0.84, 0.90, true)
        end
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
        if existingEntry then
            local entryHasSur = existingEntry.surname and existingEntry.surname ~= ""
            local targetHasSur = parsed.surname and parsed.surname ~= ""
            if entryHasSur and targetHasSur and existingEntry.surname:lower() ~= parsed.surname:lower() then
                existingEntry = nil
            elseif (entryHasSur ~= targetHasSur) and not (existingEntry.guid and rawGuid and existingEntry.guid == rawGuid) then
                existingEntry = nil
            end
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
                if ns.Chat and ns.Chat.OpenPreferredConversation then
                    ns.Chat:OpenPreferredConversation({
                        targetName = parsed.displayName,
                        lookupKey = parsed.lookupKey,
                        bnetAccountID = bnId,
                        scConfirmed = true,
                    })
                elseif ns.NavigateToModule then
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

        local isAcctIgn = Store and Store.IsAccountIgnored and Store:IsAccountIgnored(parsed.lookupKey or parsed.displayName)
        local ignLabel = isAcctIgn and ("|cffff4d4d[x]|r " .. L["Edit Account Ignore..."]) or L["Account Ignore..."]
        rootDescription:CreateButton(ignLabel, function()
            if ns.SocialPanels and ns.SocialPanels.OpenAccountIgnoreModal then
                ns.SocialPanels:OpenAccountIgnoreModal(parsed.displayName, parsed.lookupKey)
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

local popupAlertBanner = nil
local popupAlertHideSeq = 0

local function HideOfficialPopupAlertBanner()
    popupAlertHideSeq = popupAlertHideSeq + 1
    if popupAlertBanner then
        popupAlertBanner:Hide()
    end
end

local function EnsureOfficialPopupAlertBanner()
    if popupAlertBanner then
        return popupAlertBanner
    end
    local f = CreateFrame("Frame", "SocialCentralPopupAlertBanner", UIParent, "BackdropTemplate")
    f:Hide()
    f:SetSize(380, 62)
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:EnableMouse(true)
    if ns.Theme and ns.Theme.PrepareTopOverlayModal then
        ns.Theme:PrepareTopOverlayModal(f, 920)
    else
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(920)
        f:SetToplevel(true)
    end
    local solidBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetAllPoints()
    solidBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    solidBg:SetVertexColor(0.16, 0.04, 0.05, 1.0)
    f._solidOpaqueBg = solidBg
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        f:SetBackdropColor(0.16, 0.04, 0.05, 1.0)
        f:SetBackdropBorderColor(0.95, 0.25, 0.25, 1.0)
    end
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "SocialCentralPopupAlertBanner")
    end

    local closeBtn = (ns.Theme and ns.Theme.CreateButton) and ns.Theme:CreateButton(f, 20, 20, "X", "default") or CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", HideOfficialPopupAlertBanner)
    f.closeBtn = closeBtn

    local quickBtn = (ns.Theme and ns.Theme.CreateOfficialQuickButton) and ns.Theme:CreateOfficialQuickButton(f, {
        name = "SocialCentralPopupAlertQuickBtn",
        size = 18,
        title = L["Preventive Popup Alerts"],
        tooltipAnchor = "ANCHOR_RIGHT",
        getStatusState = function()
            local s = ns.db and ns.db.settings
            if s and s.socialOfficialPopupAlerts == false then return "off" end
            return "active"
        end,
        getTooltipLines = function()
            return {
                L["Displays a warning banner when an Ignored or Avoid-flagged player sends an official Invite, Trade, or Duel."],
            }
        end,
        buildMenu = function(root)
            root:CreateTitle("SocialCentral — " .. L["Preventive Popup Alerts"])
            if root.CreateCheckbox then
                root:CreateCheckbox(L["Warn on official Invite, Trade & Duel popups"], function()
                    return not ns.db or not ns.db.settings or ns.db.settings.socialOfficialPopupAlerts ~= false
                end, function()
                    if ns.db and ns.db.settings then
                        ns.db.settings.socialOfficialPopupAlerts = not (ns.db.settings.socialOfficialPopupAlerts ~= false)
                        if ns.db.settings.socialOfficialPopupAlerts == false then
                            HideOfficialPopupAlertBanner()
                        end
                    end
                    ns:Emit("SETTINGS_UPDATED")
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                end)
            end
            if root.CreateDivider then root:CreateDivider() end
            root:CreateButton(L["Disable in this window"], function()
                if ns.db and ns.db.settings then
                    ns.db.settings.socialOfficialPopupAlerts = false
                end
                HideOfficialPopupAlertBanner()
                ns:Emit("SETTINGS_UPDATED")
                if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                ns:Print("%s", L["Disabled in this window. Re-enable anytime in Settings (/sc)."])
            end)
            root:CreateButton(L["Settings"], function()
                if ns.Settings and ns.Settings.Open then ns.Settings:Open("general") end
            end)
        end,
    }) or nil
    if quickBtn then
        quickBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
        f.quickBtn = quickBtn
    end

    local titleFs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -8)
    titleFs:SetPoint("RIGHT", quickBtn or closeBtn, "LEFT", -6, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetWordWrap(false)
    f.titleFs = titleFs

    local detailFs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -4)
    detailFs:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8)
    detailFs:SetJustifyH("LEFT")
    detailFs:SetJustifyV("TOP")
    detailFs:SetWordWrap(true)
    f.detailFs = detailFs

    popupAlertBanner = f
    return f
end

local function CheckOfficialPopupAlert(rawName, contextKind)
    if ns.db and ns.db.settings and ns.db.settings.socialOfficialPopupAlerts == false then
        return
    end
    local cleanRaw = Safe.String(rawName)
    if not cleanRaw or cleanRaw == "" then return end
    local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(cleanRaw)
    local disp = (parsed and parsed.displayName) or cleanRaw
    local lk = (parsed and parsed.lookupKey) or cleanRaw:lower()
    if Compat.IsMe and Compat.IsMe(disp) then return end

    local acctIgn = Store and Store.GetAccountIgnore and Store:GetAccountIgnore(lk) or nil
    local sMeta = Store and ((Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(lk)) or (Store.GetSocialMeta and Store:GetSocialMeta(lk))) or nil
    local isAvoid = (sMeta and sMeta.flag == "AVOID") == true
    if not acctIgn and not isAvoid then
        return
    end

    local ctxLabel = (contextKind == "TRADE" and L["Trade Request"])
        or (contextKind == "DUEL" and L["Duel Request"])
        or L["Party Invite"]
    local reasonStr
    if acctIgn then
        local rLbl = Store.FormatIgnoreReason and Store:FormatIgnoreReason(acctIgn.reason, L) or L["Account Ignore"]
        reasonStr = L["ACCOUNT IGNORED"] .. " (" .. rLbl .. ")" .. ((acctIgn.note and acctIgn.note ~= "") and (" — " .. acctIgn.note) or "")
    else
        reasonStr = L["FLAGGED: AVOID (SocialCentral)"] .. ((sMeta and sMeta.note and sMeta.note ~= "") and (" — " .. sMeta.note) or "")
    end

    ns:Print("|cffff4d4d[! %s]|r %s: %s", ctxLabel, disp, reasonStr)
    local nowSoundMono = (GetTime and GetTime()) or time()
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING and not (Compat.IsFocusSilenced and Compat.IsFocusSilenced()) and (nowSoundMono - (Watchlist._lastPopupAlertSoundAt or 0)) >= 3.0 then
        Watchlist._lastPopupAlertSoundAt = nowSoundMono
        pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
    end

    local banner = EnsureOfficialPopupAlertBanner()
    banner.titleFs:SetText("|cffff5555[!] " .. ctxLabel .. ": " .. disp .. "|r")
    banner.detailFs:SetText("|cffffd24d" .. reasonStr .. "|r")
    banner:ClearAllPoints()
    if contextKind == "TRADE" and _G.TradeFrame and _G.TradeFrame.IsShown and _G.TradeFrame:IsShown() then
        banner:SetPoint("BOTTOM", _G.TradeFrame, "TOP", 0, 8)
    elseif _G.StaticPopup1 and _G.StaticPopup1.IsShown and _G.StaticPopup1:IsShown() then
        banner:SetPoint("BOTTOM", _G.StaticPopup1, "TOP", 0, 8)
    else
        banner:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
    if banner.closeBtn and ns.Theme and ns.Theme.StyleButton then
        ns.Theme:StyleButton(banner.closeBtn, "default")
    end
    if banner.quickBtn and banner.quickBtn.RefreshTheme then
        banner.quickBtn:RefreshTheme()
    end
    banner:Show()
    banner:Raise()

    popupAlertHideSeq = popupAlertHideSeq + 1
    local mySeq = popupAlertHideSeq
    if C_Timer and C_Timer.After then
        C_Timer.After(14, function()
            if popupAlertHideSeq == mySeq and popupAlertBanner then
                popupAlertBanner:Hide()
            end
        end)
    end
end

function Watchlist:NormalizeStoredEntries()
    -- Normalize stored Watchlist entries (Forever FirstName Surname capitalization & clear stale truncation/online flags).
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
                local age = now - lastConfirm
                if age >= STALE_UNKNOWN_OFFLINE_SECONDS then
                    entry.status = "offline"
                    entry._expiredOnline = nil
                    entry._staleSettled = true
                    if entry.source == "friend" or entry.source == "guild" or entry.source == "bnet" then
                        entry.source = nil
                    end
                elseif age >= INIT_STALE_ONLINE_SECONDS then
                    entry.status = "unknown"
                    entry._expiredOnline = true
                    if entry.source == "friend" or entry.source == "guild" or entry.source == "bnet" then
                        entry.source = nil
                    end
                end
            elseif entry.status == "offline" then
                entry._expiredOnline = nil
                if entry.source == "bnet" then
                    entry.source = nil
                end
            elseif entry.status == "unknown" then
                local lastConfirm = entry.lastSeen or entry.lastChecked or 0
                if lastConfirm > 0 and (now - lastConfirm) >= STALE_UNKNOWN_OFFLINE_SECONDS then
                    entry.status = "offline"
                    entry._expiredOnline = nil
                    entry._staleSettled = true
                end
            end
        end
    end
    Watchlist._wlIndexDirty = true
    if Store and Store.InvalidateWatchlistIndex then Store:InvalidateWatchlistIndex() end
end

function Watchlist:Init()
    self:NormalizeStoredEntries()

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

    ns.RegisterEvent(self, "PARTY_INVITE_REQUEST", function(_, _, inviterName)
        CheckOfficialPopupAlert(inviterName, "INVITE")
    end)
    ns.RegisterEvent(self, "PARTY_INVITE_CANCEL", HideOfficialPopupAlertBanner)
    ns.RegisterEvent(self, "DUEL_REQUESTED", function(_, _, challengerName)
        CheckOfficialPopupAlert(challengerName, "DUEL")
    end)
    ns.RegisterEvent(self, "DUEL_FINISHED", HideOfficialPopupAlertBanner)
    ns.RegisterEvent(self, "TRADE_SHOW", function()
        local npcResolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName("NPC")
        local trader = (npcResolved and npcResolved.fullName) or (UnitName and Safe.String(Safe.Call(UnitName, "NPC")))
        CheckOfficialPopupAlert(trader, "TRADE")
    end)
    ns.RegisterEvent(self, "TRADE_CLOSED", HideOfficialPopupAlertBanner)
end
