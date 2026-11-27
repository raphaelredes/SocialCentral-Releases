local _, ns = ...

local L = ns.L
local Compat = ns.Compat

local MinimapBtn = {}
local MsgPreview = {}
local QuickReply = {}
ns.Minimap = MinimapBtn

local RING_TEX = 136430
local BG_TEX = 136467
local HIGHLIGHT_TEX = 136477
local ICON_TEX = "Interface\\AddOns\\SocialCentral\\Media\\icon"
local ICON_BELL_ON = "Interface\\AddOns\\SocialCentral\\Media\\bell-on"
local ICON_BELL_OFF = "Interface\\AddOns\\SocialCentral\\Media\\bell-off"
local ICON_LOCK_CLOSED = "Interface\\AddOns\\SocialCentral\\Media\\lock-closed"
local ICON_LOCK_OPEN = "Interface\\AddOns\\SocialCentral\\Media\\lock-open"
local ICON_ARROW_UP = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up"
local ICON_ARROW_DOWN = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"
local QR_WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local RADIUS_OFFSET = 8

local button
local chatButton
local chatHooksInstalled = false
local ldbObject
local BADGE_CATEGORY_ORDER = { "whisper", "group", "raid", "guild", "bnet", "room" }
local BadgeCluster = {
    testCounts = nil,
    previewCounts = {},
    testPreviewCounts = {},
    previewCountsByThread = {},
    satBadges = {},
    driver = nil,
    phase = "IDLE",
    phaseTime = 0,
    hovered = false,
    activeItems = {},
    activeTones = {},
    totalCount = 0,
    orbitCoords = {},
    lastToneSig = "",
    lastFullSig = "",
    lastTotal = 0,
    fusionY = -21,
}

local MINIMAP_SHAPES = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function UpdatePosition()
    if not button or not Minimap then
        return
    end
    local cfg = ns.db and ns.db.settings and ns.db.settings.minimap
    local angleDeg = 215
    if type(cfg) == "table" then
        local resKey = ns.Theme and ns.Theme.GetScreenProfileKey and ns.Theme:GetScreenProfileKey()
        if resKey then
            if type(cfg.anglesByRes) ~= "table" then
                cfg.anglesByRes = {}
            end
            if type(cfg.anglesByRes[resKey]) == "number" then
                angleDeg = cfg.anglesByRes[resKey]
            elseif next(cfg.anglesByRes) == nil and type(cfg.angle) == "number" then
                cfg.anglesByRes[resKey] = cfg.angle
                angleDeg = cfg.angle
            else
                local uw, uh = ns.Theme:GetScreenDimensions()
                local matched = nil
                for k, v in pairs(cfg.anglesByRes) do
                    if type(k) == "string" and type(v) == "number" then
                        local bw, bh = k:match("^(%d+)x(%d+)$")
                        if bw and bh and math.abs(tonumber(bw) - uw) <= 24 and math.abs(tonumber(bh) - uh) <= 24 then
                            matched = v
                            break
                        end
                    end
                end
                angleDeg = matched or 215
            end
        else
            angleDeg = cfg.angle or 215
        end
    end
    local rad = math.rad(angleDeg)
    local x = math.cos(rad)
    local y = math.sin(rad)
    local q = 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end

    local shape = (GetMinimapShape and GetMinimapShape()) or "ROUND"
    local quad = MINIMAP_SHAPES[shape] or MINIMAP_SHAPES["ROUND"]
    local w = (Minimap:GetWidth() or 140) * 0.5 + RADIUS_OFFSET
    local h = (Minimap:GetHeight() or 140) * 0.5 + RADIUS_OFFSET

    if quad[q] then
        x = x * w
        y = y * h
    else
        local diagW = math.sqrt(2 * (w ^ 2)) - 10
        local diagH = math.sqrt(2 * (h ^ 2)) - 10
        x = math.max(-w, math.min(x * diagW, w))
        y = math.max(-h, math.min(y * diagH, h))
    end

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function IsOfficialChatShortcutEnabled()
    local s = ns.db and ns.db.settings
    return not (s and s.officialChatShortcutButton == false)
end

local function GetSavedChatButtonPosition()
    local s = ns.db and ns.db.settings
    if type(s) ~= "table" then
        return nil
    end
    local byRes = s.chatButtonPositionsByRes
    if type(s.chatButtonCustomPos) == "table" and tonumber(s.chatButtonCustomPos.x) and tonumber(s.chatButtonCustomPos.y) then
        if type(byRes) ~= "table" then
            byRes = {}
            s.chatButtonPositionsByRes = byRes
        end
        local resKey = ns.Theme and ns.Theme.GetScreenProfileKey and ns.Theme:GetScreenProfileKey()
        if resKey and byRes[resKey] == nil then
            byRes[resKey] = {
                point = s.chatButtonCustomPos.point or "CENTER",
                relPoint = s.chatButtonCustomPos.relPoint or s.chatButtonCustomPos.point or "CENTER",
                x = tonumber(s.chatButtonCustomPos.x),
                y = tonumber(s.chatButtonCustomPos.y),
            }
        end
        s.chatButtonCustomPos = nil
    end
    if type(byRes) == "table" and ns.Theme and ns.Theme.ResolveResolutionBucket then
        local pos = ns.Theme:ResolveResolutionBucket(byRes, false)
        if type(pos) == "table" and tonumber(pos.x) and tonumber(pos.y) then
            return pos
        end
    end
    return nil
end

local function SaveChatButtonPosition(posRec)
    local s = ns.db and ns.db.settings
    if not (type(s) == "table" and type(posRec) == "table" and tonumber(posRec.x) and tonumber(posRec.y)) then
        return
    end
    s.chatButtonCustomPos = nil
    if type(s.chatButtonPositionsByRes) ~= "table" then
        s.chatButtonPositionsByRes = {}
    end
    local resKey = ns.Theme and ns.Theme.GetScreenProfileKey and ns.Theme:GetScreenProfileKey()
    if resKey then
        s.chatButtonPositionsByRes[resKey] = posRec
    end
end

local function ClearSavedChatButtonPositionForCurrentRes()
    local s = ns.db and ns.db.settings
    if type(s) == "table" then
        s.chatButtonCustomPos = nil
        if type(s.chatButtonPositionsByRes) == "table" and ns.Theme and ns.Theme.ResolveResolutionBucket then
            local _, matchedKey, isNeighbor = ns.Theme:ResolveResolutionBucket(s.chatButtonPositionsByRes, false)
            if matchedKey and not isNeighbor then
                s.chatButtonPositionsByRes[matchedKey] = nil
            end
        end
    end
    if ns.Theme and ns.Theme.ClearSavedWindowPosition then
        ns.Theme:ClearSavedWindowPosition("official_chat_button", true)
    end
end

local function HasCustomChatButtonPosition()
    if GetSavedChatButtonPosition() ~= nil then
        return true
    end
    return (ns.Theme and ns.Theme.HasSavedWindowPosition and ns.Theme:HasSavedWindowPosition("official_chat_button")) == true
end

local function UpdateChatButtonPosition()
    if not chatButton or chatButton._scDragging then
        return
    end
    local cf = _G.ChatFrame1
    if not cf then
        return
    end
    local rail = _G.ChatFrame1ButtonFrame
    local restoredCustom = false
    local customPos = GetSavedChatButtonPosition()
    if customPos then
        chatButton:ClearAllPoints()
        chatButton:SetPoint(
            customPos.point or "CENTER",
            UIParent,
            customPos.relPoint or customPos.point or "CENTER",
            tonumber(customPos.x),
            tonumber(customPos.y)
        )
        restoredCustom = true
    elseif ns.Theme and ns.Theme.HasSavedWindowPosition and ns.Theme:HasSavedWindowPosition("official_chat_button") and ns.Theme.RestoreWindowPosition then
        chatButton._scLocked = false
        restoredCustom = ns.Theme:RestoreWindowPosition(chatButton, "official_chat_button", false) == true
    end
    if not restoredCustom then
        chatButton:ClearAllPoints()
        if rail and rail.IsShown and rail:IsShown() then
            chatButton:SetPoint("BOTTOM", rail, "TOP", 0, 4)
        else
            local leftPos = cf.GetLeft and cf:GetLeft()
            if leftPos and leftPos >= 34 then
                chatButton:SetPoint("BOTTOMRIGHT", cf, "TOPLEFT", -4, 4)
            elseif _G.ChatFrame1Tab then
                chatButton:SetPoint("LEFT", _G.ChatFrame1Tab, "RIGHT", 6, 0)
            else
                chatButton:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", 2, 26)
            end
        end
    end
    chatButton._scLocked = (ns.db and ns.db.settings and ns.db.settings.chatButtonLock == true)
    local refLvl = (rail and rail.IsShown and rail:IsShown() and rail.GetFrameLevel and rail:GetFrameLevel())
        or (cf.GetFrameLevel and cf:GetFrameLevel()) or 1
    chatButton:SetFrameStrata("MEDIUM")
    chatButton:SetFrameLevel(math.min(9500, math.max(8, refLvl + 10)))
    if chatButton.msgBadgeFrame then
        chatButton.msgBadgeFrame:ClearAllPoints()
        chatButton.msgBadgeFrame:SetPoint("CENTER", chatButton, "TOPRIGHT", -2, -2)
        chatButton.msgBadgeFrame:SetFrameLevel((chatButton:GetFrameLevel() or 8) + 8)
    end
end

local function SetIconPressed(pressed, targetBtn)
    local b = targetBtn or button
    if not b or not b.icon then
        return
    end
    local inset = pressed and 0.04 or 0.0
    b.icon:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
end

local function GetChatSoundLabel()
    local s = ns.db and ns.db.settings
    if not s or s.chatSound == false then
        return L["All Muted"], 0.96, 0.45, 0.45
    end
    if s.chatSoundGuild or s.chatSoundGroup then
        return L["Whispers + Channels"], 0.98, 0.82, 0.35
    end
    return L["Whispers & Rooms (Guild off)"], 0.58, 0.88, 0.98
end

local function PopulateTooltip(tt)
    tt:ClearLines()
    tt:AddDoubleLine("SocialCentral", "v" .. (ns.version or "0.0.0"), 0.25, 0.72, 0.98, 0.65, 0.70, 0.78)

    local remoteVer = ns.Clan and ns.Clan.latestRemoteVersion
    if remoteVer and remoteVer ~= "" and remoteVer ~= ns.version then
        tt:AddDoubleLine(L["Update Available"], "v" .. tostring(remoteVer), 1.0, 0.82, 0.0, 0.35, 0.95, 0.55)
    end

    local curTheme = ns.Theme and ns.Theme.GetThemeName and ns.Theme:GetThemeName() or "dark"
    local designLabel = (curTheme == "blizzard" and L["Blizzard Official"])
        or (curTheme == "native" and L["Classic Gold"])
        or L["Modern Theme"]
    local langLabel = ns.activeLangLabel or "English"
    tt:AddDoubleLine(L["Theme"], designLabel .. " | " .. langLabel, 0.78, 0.84, 0.92, 0.88, 0.92, 0.98)

    local focusReason = ns.Compat and ns.Compat.GetFocusSilenceReason and ns.Compat.GetFocusSilenceReason()
    if focusReason == "dnd" then
        local sCfg = ns.db and ns.db.settings
        local extra = ""
        if sCfg and type(sCfg.dndUntil) == "number" and sCfg.dndUntil > time() then
            extra = " (" .. tostring(math.max(1, math.ceil((sCfg.dndUntil - time()) / 60))) .. "m)"
        elseif sCfg and sCfg.dndUntilLeaveInstance == true then
            extra = " (" .. L["Until leaving instance"] .. ")"
        elseif sCfg and sCfg.dndUntilLeaveGroup == true then
            extra = " (" .. L["Until leaving group"] .. ")"
        end
        tt:AddDoubleLine(L["Focus Mode"], L["Do Not Disturb (Active)"] .. extra, 0.78, 0.84, 0.92, 1.0, 0.65, 0.24)
    elseif focusReason == "game_dnd" then
        tt:AddDoubleLine(L["Focus Mode"], L["WoW /dnd (Busy)"], 0.78, 0.84, 0.92, 1.0, 0.55, 0.25)
    elseif focusReason == "instance" then
        tt:AddDoubleLine(L["Focus Mode"], L["Silenced in Instance"], 0.78, 0.84, 0.92, 1.0, 0.78, 0.30)
    end

    local watchOnMod = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("watchlist")
    local socOnMod = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("social")
    local clanOnMod = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("clan")
    local nearbyOnMod = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("nearby")
    local chatOnMod = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("chat")
    local radarOnMod = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("radar")
    local groupOnMod = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("group")

    if chatOnMod then
        local sndLabel, sr, sg, sb = GetChatSoundLabel()
        tt:AddDoubleLine(L["Chat Sounds"], sndLabel, 0.78, 0.84, 0.92, sr, sg, sb)
    end

    tt:AddLine(" ")

    local watchOn, watchOff, watchUnk = 0, 0, 0
    if watchOnMod and ns.Watchlist then
        watchOn, watchOff, watchUnk = ns.Watchlist:GetStats()
        tt:AddDoubleLine(
            L["Watchlist"],
            string.format("%s: %d  |  %s: %d  |  %s: %d", L["Online"], watchOn, L["Offline"], watchOff, L["Unchecked"], watchUnk),
            0.88, 0.92, 0.98, 0.90, 0.92, 0.96
        )
    end

    if socOnMod and ns.Social and ns.Social.GetCount then
        local friendCount = ns.Social:GetCount("friend")
        local bnetCount = ns.Social:GetCount("bnet")
        if clanOnMod then
            local guildCount = ns.Social:GetCount("guild")
            tt:AddDoubleLine(
                L["Social"],
                string.format("%s: %d  |  %s: %d  |  %s: %d", L["Guild"], guildCount, L["Friends"], friendCount, "BNet", bnetCount),
                0.88, 0.92, 0.98, 0.72, 0.85, 0.98
            )
        else
            tt:AddDoubleLine(
                L["Social"],
                string.format("%s: %d  |  %s: %d", L["Friends"], friendCount, "BNet", bnetCount),
                0.88, 0.92, 0.98, 0.72, 0.85, 0.98
            )
        end
    end

    if nearbyOnMod and ns.Nearby and ns.Nearby.GetCount then
        tt:AddDoubleLine(L["Nearby"], tostring(ns.Nearby:GetCount()), 0.88, 0.92, 0.98, 0.35, 0.80, 1.0)
    end

    if radarOnMod and ns.Spotter then
        local eCount, aCount, sCount, totalCount = ns.Spotter:GetCounts()
        if totalCount > 0 then
            tt:AddDoubleLine(
                L["Target Radar"],
                string.format("|cfff54747E:%d|r  |cff40d973A:%d|r  |cfffacc3dC:%d|r", eCount, aCount, sCount),
                0.88, 0.92, 0.98, 1, 1, 1
            )
        end
    end

    local grpCount = (groupOnMod and ns.Group and #ns.Group:GetMembers()) or 0
    if grpCount > 0 then
        tt:AddDoubleLine(L["Group"], tostring(grpCount), 0.78, 0.84, 0.92, 0.45, 0.80, 1.0)
    end

    local lfgOnMod = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("lfg")
    if lfgOnMod and ns.Clan and ns.Clan.GetTrustedLFGBreakdown then
        local bd = ns.Clan:GetTrustedLFGBreakdown()
        if bd and (bd.total or 0) > 0 then
            tt:AddDoubleLine(L["Clans & Allies LFG"], tostring(bd.total), 0.78, 0.84, 0.92, 0.25, 0.92, 0.55)
        end
    end
    if groupOnMod and ns.Group and ns.Group.GetHourlyInstanceStatus then
        local st = ns.Group:GetHourlyInstanceStatus()
        local usedH, maxH = st and st.used or 0, st and st.max or 5
        tt:AddDoubleLine(L["Instances (1h)"], string.format("%d/%d", usedH, maxH), 0.78, 0.84, 0.92, usedH >= maxH and 1.0 or 0.72, usedH >= maxH and 0.35 or 0.88, usedH >= maxH and 0.35 or 0.96)
    end

    if watchOnMod and ns.Watchlist and watchOn > 0 then
        tt:AddLine(" ")
        local shown = 0
        for _, entry in ipairs(ns.Watchlist:GetEntries("all", "status")) do
            if entry.status == "online" and shown < 5 then
                local r, g, b = Compat.ClassColor(entry.classFile)
                local isFav = (entry.favorite == true) or (ns.Store and ns.Store.IsSocialFavorite and ns.Store:IsSocialFavorite(entry.id) == true)
                local star = isFav and ((Compat.FavoriteStarMarkup and Compat.FavoriteStarMarkup(12)) or "* ") or ""
                local area = (entry.area and entry.area ~= "") and entry.area or L["Online"]
                tt:AddDoubleLine(star .. (entry.displayName or ""), area, r, g, b, 0.70, 0.75, 0.82)
                shown = shown + 1
            end
        end
    end

    local summary = chatOnMod and ns.Chat and ns.Chat.GetUnreadSummary and ns.Chat:GetUnreadSummary()
    local unreadDirect = summary and summary.totalDirect or (chatOnMod and ns.Chat and ns.Chat:GetTotalUnread() or 0)
    local mirrorUnread = summary and summary.channels or 0
    local clanOnMod = Compat.IsModuleEnabled("clan")
    local clanNotifs = (clanOnMod and ns.Clan and ns.Clan.GetNotificationCount and ns.Clan:GetNotificationCount()) or 0

    local activeItems, activeTotal = BadgeCluster:CollectActiveCategories()
    if activeTotal > 0 then
        tt:AddLine(" ")
        local catLabels = {
            whisper = L["Whispers"],
            bnet = "Battle.net",
            group = L["Group"],
            raid = L["Raid"],
            guild = L["Guild"],
            room = L["Private Rooms"],
        }
        for _, catItem in ipairs(activeItems) do
            local spec = ns.Theme and ns.Theme.GetChatToneSpec and ns.Theme:GetChatToneSpec(catItem.tone)
            local ac = (spec and spec.accent) or { 1.0, 0.85, 0.35 }
            local lbl = catLabels[catItem.tone] or catItem.tone
            tt:AddDoubleLine(lbl, tostring(catItem.count), ac[1], ac[2], ac[3], ac[1], ac[2], ac[3])
        end
    end

    if chatOnMod and (unreadDirect > 0 or mirrorUnread > 0) then
        if activeTotal == 0 then
            tt:AddLine(" ")
        end
        if unreadDirect > 0 and summary and summary.senders and #summary.senders > 0 then
            local streamerOn = Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()
            local shownSenders = 0
            for _, item in ipairs(summary.senders) do
                if shownSenders >= 4 then break end
                local toneKey = (ns.Theme and ns.Theme.GetChatToneForKind) and ns.Theme:GetChatToneForKind(item.kind) or "whisper"
                local spec = (ns.Theme and ns.Theme.GetChatToneSpec) and ns.Theme:GetChatToneSpec(toneKey)
                local ac = (spec and spec.accent) or { 1.0, 0.50, 1.0 }
                local sTitle = tostring(item.title or "")
                if streamerOn then
                    if item.kind == "ROOM" then
                        sTitle = L["Private Room"]
                    elseif (item.kind == "BN_WHISPER" or sTitle:find("#", 1, true)) and Compat.MaskStreamerBNetName then
                        sTitle = Compat.MaskStreamerBNetName(sTitle)
                    end
                end
                tt:AddDoubleLine("  " .. sTitle, tostring(item.unread or 0), 0.86, 0.90, 0.96, ac[1], ac[2], ac[3])
                shownSenders = shownSenders + 1
            end
        end
        if clanNotifs > 0 and activeTotal == 0 then
            tt:AddDoubleLine(L["Guild Alerts"], tostring(clanNotifs), 0.28, 0.94, 0.40, 0.28, 0.94, 0.40)
        end
    end
    if chatOnMod and ns.Chat and ns.Chat.GetQuickReplyDraftCount then
        local draftCount = ns.Chat:GetQuickReplyDraftCount()
        if draftCount > 0 then
            tt:AddLine(L["Saved draft (%d) — Click to resume"]:format(draftCount), 1.0, 0.84, 0.30)
        end
    end

    tt:AddLine(" ")
    local activeModeLbl = (Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode())
        and L["Official WoW Chat"]
        or L["SocialCentral Chat (Quick Reply)"]
    tt:AddDoubleLine(L["Exclusive Chat Mode"], activeModeLbl, 0.78, 0.84, 0.92, 0.98, 0.82, 0.35)

    local clickMode = (ns.db and ns.db.settings and ns.db.settings.minimapLeftClickAction) or "smart"
    local leftHint
    if Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode() then
        leftHint = L["Left-click: open Main Window"]
    else
        leftHint = (clickMode == "menu") and L["Left-click: choose Main Window or Settings"]
            or (clickMode == "hub" and L["Left-click: open Main Window"] or L["Left-click: toggle Quick Reply"])
    end
    local extraLines = {
        leftHint,
        L["Shift+Click: toggle Main Window"],
    }
    if radarOnMod then extraLines[#extraLines + 1] = L["Alt+Click: toggle Target Radar"] end
    if chatOnMod then extraLines[#extraLines + 1] = L["Ctrl+Click: open Conversations"] end
    extraLines[#extraLines + 1] = L["Right-click: quick menu"]
    extraLines[#extraLines + 1] = L["Drag: move button"]
    tt:AddLine(table.concat(extraLines, "\n"), 0.75, 0.80, 0.88, true)
end

function MinimapBtn:PopulateSummaryTooltip(tt)
    if tt then
        PopulateTooltip(tt)
    end
end

local function OpenViaOfficialOrHub(modId)
    if ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
        ns.LFGFrameTab:OpenOfficialModule(modId)
    elseif ns.UI and ns.UI.OpenTab then
        ns.UI:OpenTab(modId)
    end
end

local function CutUtf8ForMenu(str, maxBytes)
    if type(str) ~= "string" then return "" end
    if #str <= maxBytes then return str end
    if maxBytes <= 0 then return "" end
    local cut = maxBytes
    local nextB = str:byte(cut + 1)
    if nextB and nextB >= 128 and nextB <= 191 then
        while cut > 0 and (str:byte(cut) or 0) >= 128 and (str:byte(cut) or 0) <= 191 do
            cut = cut - 1
        end
        if cut > 0 and (str:byte(cut) or 0) >= 192 then
            cut = cut - 1
        end
    end
    return str:sub(1, cut)
end

local function BuildRecentNotificationsSubmenu(root)
    local toastMod = ns.NotificationToast
    if not (toastMod and toastMod.GetRecentHistory) then return end
    local recList = toastMod:GetRecentHistory() or {}
    local recTitle = (#recList > 0)
        and string.format("%s (%d)", L["Recent Notifications"], #recList)
        or L["Recent Notifications"]
    local recSub = root:CreateButton(recTitle)
    if not (recSub and recSub.CreateButton) then return end
    if #recList == 0 then
        recSub:CreateTitle(L["No recent notifications."])
        return
    end
    local streamerOn = Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()
    local limit = math.min(#recList, 20)
    for i = 1, limit do
        local it = recList[i]
        if it then
            local tsStr = it.ts and date("%H:%M", it.ts) or ""
            local src = tostring(it.sourceTag or "?")
            if streamerOn and it.kind == "ROOM" then
                src = L["Private Room"]
            end
            local whoRaw = tostring(it.sender or "?")
            if streamerOn and (it.bnetAccountID ~= nil or it.kind == "BN_WHISPER" or whoRaw:find("#", 1, true)) and Compat.MaskStreamerBNetName then
                whoRaw = Compat.MaskStreamerBNetName(whoRaw)
            end
            local whoHex = (it.senderClass and Compat and Compat.ClassHex) and Compat.ClassHex(it.senderClass) or "|cffffffff"
            local isPrivKind = (it.kind == "WHISPER" or it.kind == "BN_WHISPER" or it.kind == "DIRECT" or it.kind == "ROOM" or it.kind == "RMI")
            local rawSnip
            if streamerOn and isPrivKind then
                rawSnip = L["[Hidden in Streamer Mode]"]
            else
                rawSnip = tostring(it.text or "")
                    :gsub("|c%x%x%x%x%x%x%x%x|H.-|h(.-)|h|r", "%1")
                    :gsub("|H.-|h(.-)|h", "%1")
                    :gsub("|T.-|t", "")
                    :gsub("|A.-|a", "")
                    :gsub("|c%x%x%x%x%x%x%x%x", "")
                    :gsub("|r", "")
                    :gsub("[\r\n|]+", " ")
                    :gsub("%s+", " ")
                    :match("^%s*(.-)%s*$") or ""
                if it.kind == "RMI" and rawSnip ~= "" then
                    rawSnip = string.format(L["Invite to room: %s"], rawSnip)
                end
            end
            local snip = (#rawSnip > 38) and (CutUtf8ForMenu(rawSnip, 35) .. "...") or rawSnip
            local mult = (it.coalescedCount and it.coalescedCount > 1) and (" |cff9da7b5(x" .. tostring(it.coalescedCount) .. ")|r") or ""
            local lbl = string.format("|cff9da7b5[%s]|r %s · %s%s|r%s: %s", tsStr, src, whoHex, whoRaw, mult, snip)
            recSub:CreateButton(lbl, function()
                if toastMod.ActivateHistoryItem then
                    toastMod:ActivateHistoryItem(it)
                end
            end)
        end
    end
    recSub:CreateDivider()
    recSub:CreateButton(L["Clear History"], function()
        if toastMod.ClearRecentHistory then
            toastMod:ClearRecentHistory()
        end
    end)
end

local function BuildDoNotDisturbMenuSection(root)
    root:CreateCheckbox(L["Do Not Disturb"], function()
        return ns.db and ns.db.settings and ns.db.settings.doNotDisturb == true
    end, function()
        local cur = ns.db and ns.db.settings and ns.db.settings.doNotDisturb == true
        if Compat and Compat.SetDoNotDisturb then
            Compat.SetDoNotDisturb(not cur)
        elseif ns.db and ns.db.settings then
            ns.db.settings.doNotDisturb = not cur
            ns:Emit("SETTINGS_UPDATED")
            if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
        end
    end)
    local dndSub = root:CreateButton(L["Focus Mode Timer"])
    if dndSub and dndSub.CreateButton then
        local function SetTimedDnd(durSec, untilLeaveInst, untilLeaveGrp)
            if Compat and Compat.SetDoNotDisturb then
                Compat.SetDoNotDisturb(true, durSec, untilLeaveInst, untilLeaveGrp)
            elseif ns.db and ns.db.settings then
                ns.db.settings.doNotDisturb = true
                ns:Emit("SETTINGS_UPDATED")
                if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
            end
        end
        dndSub:CreateButton(L["For 15 minutes"], function() SetTimedDnd(900, false, false) end)
        dndSub:CreateButton(L["For 30 minutes"], function() SetTimedDnd(1800, false, false) end)
        dndSub:CreateButton(L["For 1 hour"], function() SetTimedDnd(3600, false, false) end)
        dndSub:CreateButton(L["For 2 hours"], function() SetTimedDnd(7200, false, false) end)
        dndSub:CreateButton(L["Until leaving instance"], function() SetTimedDnd(nil, true, false) end)
        dndSub:CreateButton(L["Until leaving group"], function() SetTimedDnd(nil, false, true) end)
        dndSub:CreateButton(L["Until I turn it off"], function() SetTimedDnd(nil, false, false) end)
        if ns.db and ns.db.settings and ns.db.settings.doNotDisturb == true then
            dndSub:CreateDivider()
            dndSub:CreateButton(L["Turn Off Do Not Disturb"], function()
                if Compat and Compat.SetDoNotDisturb then
                    Compat.SetDoNotDisturb(false)
                elseif ns.db and ns.db.settings then
                    ns.db.settings.doNotDisturb = false
                    ns:Emit("SETTINGS_UPDATED")
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                end
            end)
        end
    end
end

local function OpenContextMenu(anchor)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(anchor, function(_, root)
            root:CreateTitle("SocialCentral")
            root:CreateTitle(L["Exclusive Chat Mode"])
            root:CreateRadio(L["SocialCentral Chat (Quick Reply)"], function()
                return not (Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode())
            end, function()
                MinimapBtn:SetChatUiMode("addon")
            end)
            root:CreateRadio(L["Official WoW Chat"], function()
                return (Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode()) == true
            end, function()
                MinimapBtn:SetChatUiMode("official")
            end)
            root:CreateDivider()
            root:CreateButton(L["Settings"], function()
                if ns.Settings and ns.Settings.Toggle then
                    ns.Settings:Toggle()
                elseif ns.Settings and ns.Settings.Open then
                    ns.Settings:Open()
                end
            end)
            root:CreateDivider()
            if not ns.Compat or not ns.Compat.IsWindowIntegrationEnabled or ns.Compat.IsWindowIntegrationEnabled("I") then
                root:CreateButton(L["Looking for Group (I)"], function()
                    OpenViaOfficialOrHub("lfg")
                end)
                root:CreateButton(L["Broadcast Current Group"], function()
                    if ns.Clan and ns.Clan.PostSmartGroupFormation then
                        local okPost, reason = ns.Clan:PostSmartGroupFormation()
                        if not okPost and reason == "needs_activity" then
                            if ns.LFGFrameTab then
                                ns.LFGFrameTab.viewMode = "categories"
                            end
                            OpenViaOfficialOrHub("lfg")
                            ns:Print("%s", L["Select the dungeon or activity you want to broadcast to Guild & Allies."])
                        end
                    end
                end)
                root:CreateButton(L["Reset Dungeon Instances"], function()
                    if ns.UI and ns.UI.ConfirmResetInstances then
                        ns.UI:ConfirmResetInstances()
                    elseif ns.Group and ns.Group.ResetDungeonInstances then
                        ns.Group:ResetDungeonInstances()
                    end
                end)
            end
            if not ns.Compat or not ns.Compat.IsWindowIntegrationEnabled or ns.Compat.IsWindowIntegrationEnabled("O") then
                root:CreateButton(L["Social & Watchlist (O)"], function()
                    OpenViaOfficialOrHub("watchlist")
                end)
            end
            if not ns.Compat or not ns.Compat.IsWindowIntegrationEnabled or ns.Compat.IsWindowIntegrationEnabled("J") then
                root:CreateButton(L["Clan Hub & Diplomacy (J)"], function()
                    OpenViaOfficialOrHub("clan")
                end)
            end
            if not ns.Compat or not ns.Compat.IsWindowIntegrationEnabled or ns.Compat.IsWindowIntegrationEnabled("C") then
                root:CreateButton(L["My Alts (C)"], function()
                    OpenViaOfficialOrHub("alts")
                end)
            end
            if not ns.Compat or not ns.Compat.IsModuleEnabled or ns.Compat.IsModuleEnabled("chat") then
                root:CreateButton(L["Conversations (Chat)"], function()
                    OpenViaOfficialOrHub("chat")
                end)
                if ns.QuickReply and ns.QuickReply.OpenPreviewOrLatest and not (Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode()) then
                    root:CreateButton(L["Open Quick Reply"], function()
                        ns.QuickReply:OpenPreviewOrLatest()
                    end)
                end
            end
            root:CreateButton(L["Open Main Window"], function()
                if ns.UI and ns.UI.ShowHub then
                    ns.UI:ShowHub()
                elseif ns.UI then
                    ns.UI:Toggle()
                end
            end)
            root:CreateDivider()
            if not ns.Compat or not ns.Compat.IsModuleEnabled or ns.Compat.IsModuleEnabled("radar") then
                local radarLabel = L["Target Radar"]
                if ns.Spotter then
                    local _, _, _, totalCount = ns.Spotter:GetCounts()
                    if totalCount > 0 then
                        radarLabel = string.format("%s (%d)", L["Target Radar"], totalCount)
                    end
                end
                root:CreateButton(radarLabel, function()
                    if ns.SpotterHUD and ns.SpotterHUD.Toggle then ns.SpotterHUD:Toggle() end
                end)
            end
            local chatModOn = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("chat")
            local watchModOn = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("watchlist")
            if chatModOn and ns.Chat and ns.Chat.GetTotalUnread and ns.Chat:GetTotalUnread(true) > 0 then
                root:CreateButton(L["Mark All Conversations Read"], function()
                    if ns.Chat and ns.Chat.MarkAllRead then
                        ns.Chat:MarkAllRead()
                    end
                    if MinimapBtn and MinimapBtn.ClearPreviewCounts then
                        MinimapBtn:ClearPreviewCounts()
                    end
                    if ns.Clan and ns.Clan.ClearNotificationCount then
                        ns.Clan:ClearNotificationCount()
                    end
                end)
            end
            root:CreateDivider()
            BuildRecentNotificationsSubmenu(root)
            BuildDoNotDisturbMenuSection(root)
            root:CreateCheckbox(L["Streamer / Privacy Mode"], function()
                return ns.db and ns.db.settings and ns.db.settings.streamerMode == true
            end, function()
                if ns.db and ns.db.settings then
                    ns.db.settings.streamerMode = not (ns.db.settings.streamerMode == true)
                    ns:Emit("SETTINGS_UPDATED")
                    ns:Emit("SOCIAL_UPDATED")
                    ns:Emit("CHAT_UPDATED")
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                end
            end)
            if chatModOn then
                local clanModOn = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("clan")
                local function BindSettingCheckbox(subMenu, key, label, defaultTrue, opts)
                    subMenu:CreateCheckbox(label, function()
                        local s = ns.db and ns.db.settings
                        if not s then return defaultTrue == true end
                        if defaultTrue then
                            return s[key] ~= false
                        end
                        return s[key] == true
                    end, function()
                        local s = ns.db and ns.db.settings
                        if not s then return end
                        local cur = defaultTrue and (s[key] ~= false) or (s[key] == true)
                        s[key] = not cur
                        if s[key] == true and ns.Chat and ns.Chat.UnmuteChannelKeysForSetting then
                            ns.Chat:UnmuteChannelKeysForSetting(key)
                        end
                        if key == "quickReplyDockToChat" and ns.QuickReply then
                            if s[key] == true and ns.QuickReply.SnapOverOfficialChat then
                                ns.QuickReply:SnapOverOfficialChat()
                            elseif ns.QuickReply.SyncDockGeometry then
                                ns.QuickReply:SyncDockGeometry()
                                if ns.QuickReply.UpdateDockButton then
                                    ns.QuickReply:UpdateDockButton()
                                end
                            end
                        elseif key == "quickReplyLocked" and ns.QuickReply and ns.QuickReply.ApplyLockState then
                            ns.QuickReply:ApplyLockState()
                        end
                        if opts and opts.previewPrompt then
                            s.msgPreviewPromptAnswered = true
                        end
                        if opts and opts.invalidateUnread and ns.Chat and ns.Chat.InvalidateUnreadCache then
                            ns.Chat:InvalidateUnreadCache()
                        end
                        ns:Emit((opts and opts.emit) or "SETTINGS_UPDATED")
                        if opts and opts.alsoSettingsEmit then
                            ns:Emit("SETTINGS_UPDATED")
                        end
                        if ns.Settings and ns.Settings.Refresh then
                            ns.Settings:Refresh()
                        end
                    end)
                end

                root:CreateCheckbox(L["Minimap Message Previews"], function()
                    return ns.db and ns.db.settings and ns.db.settings.msgPreviewEnabled ~= false
                end, function()
                    if ns.db and ns.db.settings then
                        ns.db.settings.msgPreviewEnabled = not (ns.db.settings.msgPreviewEnabled ~= false)
                        ns.db.settings.msgPreviewPromptAnswered = true
                        ns:Emit("SETTINGS_UPDATED")
                        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                    end
                end)

                local msgNotifySub = root:CreateButton(L["Message Notifications (By Type)"])
                if msgNotifySub and msgNotifySub.CreateCheckbox then
                    msgNotifySub:CreateTitle(L["Minimap Message Previews"])
                    local previewItems = {
                        { key = "msgPreviewWhispers", label = L["Show previews for Whispers & SocialCentral Direct Chat"], def = true },
                        { key = "msgPreviewBNet", label = L["Show previews for Battle.net Friends"], def = true },
                        { key = "msgPreviewRooms", label = L["Show previews for Private Rooms & Alliance Chat"], def = true },
                        { key = "msgPreviewGroup", label = L["Show previews for Group Chat (Party / Raid / Instance)"], def = false },
                        { key = "msgPreviewGuild", label = L["Show previews for Guild & Officer Chat"], def = false, clan = true },
                    }
                    for _, item in ipairs(previewItems) do
                        if not item.clan or clanModOn then
                            BindSettingCheckbox(msgNotifySub, item.key, item.label, item.def, { previewPrompt = true })
                        end
                    end
                    msgNotifySub:CreateDivider()
                    msgNotifySub:CreateTitle(L["Quick Reply Popup (Minimap)"])
                    local qrItems = {
                        { key = "quickReplyDockToChat", label = L["Dock Quick Reply over Official WoW Chat (exact size)"], def = true },
                        { key = "quickReplyLocked", label = L["Lock Quick Reply window position"], def = false },
                        { key = "quickReplyEnterOpen", label = L["Open Quick Reply on ENTER when messages are pending"], def = true },
                        { key = "quickReplyCtrlWCloseTab", label = L["Close unpinned Quick Reply tabs with Ctrl+W (if unbound)"], def = true },
                        { key = "quickReplyNotifyWhisper", label = L["Quick Reply notifications: Whispers & SocialCentral Chat"], def = true },
                        { key = "quickReplyNotifyBNet", label = L["Quick Reply notifications: Battle.net Messages"], def = true },
                        { key = "quickReplyNotifyParty", label = L["Quick Reply notifications: Party / Instance Chat"], def = true },
                        { key = "quickReplyNotifyRaid", label = L["Quick Reply notifications: Raid Chat"], def = true },
                        { key = "quickReplyNotifyGuild", label = L["Quick Reply notifications: Guild & Officer Chat"], def = false, clan = true },
                    }
                    for _, item in ipairs(qrItems) do
                        if not item.clan or clanModOn then
                            BindSettingCheckbox(msgNotifySub, item.key, item.label, item.def, { invalidateUnread = true, emit = "CHAT_UPDATED", alsoSettingsEmit = true })
                        end
                    end
                    msgNotifySub:CreateDivider()
                    msgNotifySub:CreateTitle(L["Floating Message Popups"])
                    BindSettingCheckbox(msgNotifySub, "addonMsgToast", L["Floating Message Popups"], false)
                    BindSettingCheckbox(msgNotifySub, "mentionAlertsEnabled", L["Mentions & Keywords Radar"], true, { emit = "CHAT_UPDATED", alsoSettingsEmit = true })
                    msgNotifySub:CreateDivider()
                    msgNotifySub:CreateTitle(L["Auto-Hide Previews In:"])
                    for _, ctxItem in ipairs({
                        { key = "msgPreviewSilenceDungeons", label = L["Dungeons"], def = true },
                        { key = "msgPreviewSilenceRaids", label = L["Raids"], def = true },
                        { key = "msgPreviewSilencePvP", label = L["Battlegrounds & Arenas"], def = true },
                        { key = "msgPreviewSilenceCombat", label = L["In Combat"], def = true },
                    }) do
                        BindSettingCheckbox(msgNotifySub, ctxItem.key, ctxItem.label, ctxItem.def, { previewPrompt = true })
                    end
                end

                root:CreateCheckbox(L["Mute All Chat Sounds"], function()
                    return ns.db and ns.db.settings and ns.db.settings.chatSound == false
                end, function()
                    if ns.db and ns.db.settings then
                        ns.db.settings.chatSound = (ns.db.settings.chatSound == false)
                        ns:Emit("SETTINGS_UPDATED")
                        ns:Emit("CHAT_UPDATED")
                        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                    end
                end)

                local soundSub = root:CreateButton(L["Chat Sounds (By Type)"])
                if soundSub and soundSub.CreateCheckbox then
                    BindSettingCheckbox(soundSub, "chatSound", L["Master: Enable Chat Sound Alerts"], true, { emit = "CHAT_UPDATED", alsoSettingsEmit = true })
                    soundSub:CreateDivider()
                    for _, sItem in ipairs({
                        { key = "chatSoundWhispers", label = L["Play chime on Whispers & Battle.net"], def = true },
                        { key = "chatSoundRooms", label = L["Play chime on SocialCentral Private Rooms"], def = true },
                        { key = "chatSoundAlliance", label = L["Play chime on Alliance Chat messages"], def = true, clan = true },
                        { key = "chatSoundGuild", label = L["Play chime on Guild & Officer chat (off by default)"], def = false, clan = true },
                        { key = "chatSoundGroup", label = L["Play chime on Party / Raid / Instance chat (off by default)"], def = false },
                    }) do
                        if not sItem.clan or clanModOn then
                            BindSettingCheckbox(soundSub, sItem.key, sItem.label, sItem.def, { emit = "CHAT_UPDATED", alsoSettingsEmit = true })
                        end
                    end
                end
            end
            if watchModOn then
                root:CreateCheckbox(L["Online alerts for Watchlist"], function()
                    return ns.db and ns.db.settings and ns.db.settings.alerts and ns.db.settings.alerts.chat
                end, function()
                    if ns.db and ns.db.settings and ns.db.settings.alerts then
                        ns.db.settings.alerts.chat = not ns.db.settings.alerts.chat
                        ns:Emit("SETTINGS_UPDATED")
                        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                    end
                end)
            end
            root:CreateCheckbox(L["Lock minimap button"], function()
                return ns.db and ns.db.settings and ns.db.settings.minimap and ns.db.settings.minimap.lock
            end, function()
                if ns.db and ns.db.settings and ns.db.settings.minimap then
                    ns.db.settings.minimap.lock = not ns.db.settings.minimap.lock
                    ns:Emit("SETTINGS_UPDATED")
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                end
            end)
            root:CreateCheckbox(L["Show minimap button"], function()
                return not (ns.db and ns.db.settings and ns.db.settings.minimap and ns.db.settings.minimap.hide)
            end, function()
                if ns.db and ns.db.settings and ns.db.settings.minimap then
                    ns.db.settings.minimap.hide = not ns.db.settings.minimap.hide
                    MinimapBtn:Update()
                    ns:Emit("SETTINGS_UPDATED")
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                end
            end)
            if Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode() and ns.LFGFrameTab and ns.LFGFrameTab.PopulateOfficialChatMenu then
                local offSub = root:CreateButton(L["Official Chat Features"])
                if offSub then
                    ns.LFGFrameTab:PopulateOfficialChatMenu(offSub)
                end
            end
            root:CreateCheckbox(L["Show shortcut button beside Official Chat"], function()
                return not (ns.db and ns.db.settings and ns.db.settings.officialChatShortcutButton == false)
            end, function()
                if ns.db and ns.db.settings then
                    ns.db.settings.officialChatShortcutButton = not (ns.db.settings.officialChatShortcutButton ~= false)
                    MinimapBtn:Update()
                    ns:Emit("SETTINGS_UPDATED")
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                end
            end)
            root:CreateCheckbox(L["Lock Official Chat button"], function()
                return ns.db and ns.db.settings and ns.db.settings.chatButtonLock == true
            end, function()
                if ns.db and ns.db.settings then
                    ns.db.settings.chatButtonLock = not (ns.db.settings.chatButtonLock == true)
                    if chatButton then
                        chatButton._scLocked = (ns.db.settings.chatButtonLock == true)
                    end
                    UpdateChatButtonPosition()
                    ns:Emit("SETTINGS_UPDATED")
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                end
            end)
            if HasCustomChatButtonPosition() then
                root:CreateButton(L["Reset Official Chat button position"], function()
                    ClearSavedChatButtonPositionForCurrentRes()
                    UpdateChatButtonPosition()
                    ns:Print("%s", L["Position reset to default."])
                end)
            end
            local posSub = root:CreateButton(L["Notification & Preview Position"])
            if posSub and posSub.CreateRadio then
                local curMode = (MinimapBtn.GetPreviewAnchorMode and MinimapBtn:GetPreviewAnchorMode()) or "minimap"
                for _, opt in ipairs({
                    { id = "minimap", label = L["Beside Minimap"] },
                    { id = "chat_side", label = L["Beside Official Chat"] },
                    { id = "chat_top", label = L["Above Official Chat"] },
                }) do
                    posSub:CreateRadio(opt.label, function()
                        return ((MinimapBtn.GetPreviewAnchorMode and MinimapBtn:GetPreviewAnchorMode()) or curMode) == opt.id
                    end, function()
                        if MinimapBtn.SetPreviewAnchorMode then
                            MinimapBtn:SetPreviewAnchorMode(opt.id)
                        end
                    end)
                end
            elseif posSub and posSub.CreateCheckbox then
                for _, opt in ipairs({
                    { id = "minimap", label = L["Beside Minimap"] },
                    { id = "chat_side", label = L["Beside Official Chat"] },
                    { id = "chat_top", label = L["Above Official Chat"] },
                }) do
                    posSub:CreateCheckbox(opt.label, function()
                        return ((MinimapBtn.GetPreviewAnchorMode and MinimapBtn:GetPreviewAnchorMode()) or "minimap") == opt.id
                    end, function()
                        if MinimapBtn.SetPreviewAnchorMode then
                            MinimapBtn:SetPreviewAnchorMode(opt.id)
                        end
                    end)
                end
            end
            if not (ns.Compat and ns.Compat.IsModuleEnabled and ns.Compat.IsModuleEnabled("group") == false) then
                local rollSub = root:CreateButton(L["Group Loot Roll"])
                if rollSub and rollSub.CreateButton then
                    rollSub:CreateButton(L["Open Roll Results"], function()
                        if ns.LootRollUI and ns.LootRollUI.OpenResultsWindow then
                            ns.LootRollUI:OpenResultsWindow()
                        end
                    end)
                    local activeRolls = (ns.LootRoll and ns.LootRoll.GetActiveCount and ns.LootRoll:GetActiveCount()) or 0
                    if activeRolls > 0 then
                        rollSub:CreateButton(string.format("%s (%d)", L["Show Active Roll Card"], activeRolls), function()
                            if ns.LootRollUI and ns.LootRollUI.ShowActiveRollCard then
                                ns.LootRollUI:ShowActiveRollCard()
                            end
                        end)
                    end
                    if rollSub.CreateDivider then rollSub:CreateDivider() end
                    if rollSub.CreateCheckbox then
                        rollSub:CreateCheckbox(L["Enable SocialCentral Group Loot Roll window"], function()
                            return ns.db and ns.db.settings and ns.db.settings.lootRollHelperEnabled == true
                        end, function()
                            local nextVal = not (ns.db and ns.db.settings and ns.db.settings.lootRollHelperEnabled == true)
                            if ns.db and ns.db.settings then
                                ns.db.settings.lootRollPromptAnswered = true
                                ns.db.settings.lootRollHelperEnabled = nextVal
                            end
                            if SocialCentralDB and SocialCentralDB.settings then
                                SocialCentralDB.settings.lootRollPromptAnswered = true
                                SocialCentralDB.settings.lootRollHelperEnabled = nextVal
                            end
                            if ns.Emit then
                                ns:Emit("SETTINGS_UPDATED")
                                ns:Emit("LOOT_ROLL_UPDATED")
                            end
                            if ns.LootRollUI and ns.LootRollUI.SyncResultsButton then
                                ns.LootRollUI:SyncResultsButton()
                            end
                        end)
                        rollSub:CreateCheckbox(L["Hide official WoW roll bar while active"], function()
                            return not ns.db or not ns.db.settings or ns.db.settings.lootRollHideOfficial ~= false
                        end, function()
                            local nextVal = not (not ns.db or not ns.db.settings or ns.db.settings.lootRollHideOfficial ~= false)
                            if ns.db and ns.db.settings then
                                ns.db.settings.lootRollHideOfficial = nextVal
                            end
                            if SocialCentralDB and SocialCentralDB.settings then
                                SocialCentralDB.settings.lootRollHideOfficial = nextVal
                            end
                            if ns.Emit then ns:Emit("SETTINGS_UPDATED") end
                        end)
                        rollSub:CreateCheckbox(L["Epic Win Celebration"], function()
                            return not ns.db or not ns.db.settings or ns.db.settings.lootRollWinnerToast ~= false
                        end, function()
                            local nextVal = not (not ns.db or not ns.db.settings or ns.db.settings.lootRollWinnerToast ~= false)
                            if ns.db and ns.db.settings then
                                ns.db.settings.lootRollWinnerToast = nextVal
                            end
                            if SocialCentralDB and SocialCentralDB.settings then
                                SocialCentralDB.settings.lootRollWinnerToast = nextVal
                            end
                            if ns.Emit then ns:Emit("SETTINGS_UPDATED") end
                        end)
                        rollSub:CreateCheckbox(L["Announce Winners in Local Chat"], function()
                            return not ns.db or not ns.db.settings or ns.db.settings.lootRollWinnerChatAnnounce ~= false
                        end, function()
                            local nextVal = not (not ns.db or not ns.db.settings or ns.db.settings.lootRollWinnerChatAnnounce ~= false)
                            if ns.db and ns.db.settings then
                                ns.db.settings.lootRollWinnerChatAnnounce = nextVal
                            end
                            if SocialCentralDB and SocialCentralDB.settings then
                                SocialCentralDB.settings.lootRollWinnerChatAnnounce = nextVal
                            end
                            if ns.Emit then ns:Emit("SETTINGS_UPDATED") end
                        end)
                        local layoutSub = rollSub:CreateButton(L["Roll Card Layout"])
                        if layoutSub and layoutSub.CreateRadio then
                            for _, opt in ipairs({
                                { id = "tabbed", label = L["Single Tabbed Card (Detailed)"] },
                                { id = "stacked", label = L["Stacked Multi-Drop Cards (Compact)"] },
                            }) do
                                local mId = opt.id
                                layoutSub:CreateRadio(opt.label, function()
                                    return ((ns.db and ns.db.settings and ns.db.settings.lootRollDisplayMode) or "tabbed") == mId
                                end, function()
                                    if ns.db and ns.db.settings then
                                        ns.db.settings.lootRollDisplayMode = mId
                                    end
                                    if SocialCentralDB and SocialCentralDB.settings then
                                        SocialCentralDB.settings.lootRollDisplayMode = mId
                                    end
                                    if ns.Emit then
                                        ns:Emit("SETTINGS_UPDATED")
                                        ns:Emit("LOOT_ROLL_UPDATED")
                                    end
                                end)
                            end
                        end
                        local visSub = rollSub:CreateButton(L["Button Visibility"])
                        if visSub and visSub.CreateRadio then
                            for _, opt in ipairs({
                                { id = "when_enabled", label = L["During dungeon/raid (+3 min after)"] },
                                { id = "always", label = L["Always visible"] },
                                { id = "hidden", label = L["Hide button"] },
                            }) do
                                local mId = opt.id
                                visSub:CreateRadio(opt.label, function()
                                    return ((ns.db and ns.db.settings and ns.db.settings.lootRollResultsButtonMode) or "when_enabled") == mId
                                end, function()
                                    if ns.db and ns.db.settings then
                                        ns.db.settings.lootRollResultsButtonMode = mId
                                    end
                                    if SocialCentralDB and SocialCentralDB.settings then
                                        SocialCentralDB.settings.lootRollResultsButtonMode = mId
                                    end
                                    if ns.LootRollUI and ns.LootRollUI.SyncResultsButton then
                                        ns.LootRollUI:SyncResultsButton()
                                    end
                                    if ns.Emit then
                                        ns:Emit("SETTINGS_UPDATED")
                                        ns:Emit("LOOT_ROLL_UPDATED")
                                    end
                                end)
                            end
                        end
                    end
                end
            end
            root:CreateDivider()
            local qbSub = root:CreateButton(L["Quick Access Bar"])
            if qbSub and qbSub.CreateButton then
                if qbSub.CreateCheckbox then
                    qbSub:CreateCheckbox(L["Show Quick Access Bar"], function()
                        return not (ns.db and ns.db.settings and ns.db.settings.quickBarEnabled == false)
                    end, function()
                        if ns.QuickBar and ns.QuickBar.SetEnabled then
                            local cur = not (ns.db and ns.db.settings and ns.db.settings.quickBarEnabled == false)
                            ns.QuickBar:SetEnabled(not cur)
                        end
                    end)
                end
                if qbSub.CreateRadio then
                    qbSub:CreateRadio(L["Horizontal"], function()
                        return (not ns.QuickBar or not ns.QuickBar.GetOrientation) or ns.QuickBar:GetOrientation() == "horizontal"
                    end, function()
                        if ns.QuickBar and ns.QuickBar.SetOrientation then ns.QuickBar:SetOrientation("horizontal") end
                    end)
                    qbSub:CreateRadio(L["Vertical"], function()
                        return ns.QuickBar and ns.QuickBar.GetOrientation and ns.QuickBar:GetOrientation() == "vertical"
                    end, function()
                        if ns.QuickBar and ns.QuickBar.SetOrientation then ns.QuickBar:SetOrientation("vertical") end
                    end)
                end
                qbSub:CreateButton(L["Customize Buttons (5-10)..."], function()
                    if ns.QuickBar and ns.QuickBar.OpenCustomizeModal then
                        ns.QuickBar:OpenCustomizeModal()
                    end
                end)
            end
            root:CreateDivider()
            root:CreateButton(L["GitHub Releases / Updater"], function()
                if ns.Theme and ns.Theme.ShowUpdatePopup then
                    ns.Theme:ShowUpdatePopup(ns.version, ns.Clan and ns.Clan.latestRemoteVersion, ns.RELEASE_URL)
                end
            end)
            root:CreateButton(L["Reset Window Positions"], function()
                if ns.UI and ns.UI.OpenConfirmModal then
                    ns.UI:OpenConfirmModal({
                        title = L["Reset All Window Positions"],
                        message = L["Are you sure you want to reset all SocialCentral window positions to defaults?"],
                        confirmText = L["Reset"],
                        confirmVariant = "danger",
                        onConfirm = function()
                            if ns.Theme and ns.Theme.ResetAllWindowPositions then ns.Theme:ResetAllWindowPositions() end
                        end,
                    })
                elseif ns.Theme and ns.Theme.ResetAllWindowPositions then
                    ns.Theme:ResetAllWindowPositions()
                end
            end)
        end)
    elseif ns.Settings then
        ns.Settings:Open()
    end
end

local function ClampUnit(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function EaseOutCubicUnit(t)
    local inv = 1 - ClampUnit(t)
    return 1 - (inv * inv * inv)
end

local function EaseInOutCubicUnit(t)
    local p = ClampUnit(t)
    if p < 0.5 then
        return 4 * p * p * p
    end
    local f = -2 * p + 2
    return 1 - ((f * f * f) * 0.5)
end

local function EaseOutBackUnit(t)
    local p = ClampUnit(t) - 1
    return 1 + 2.15 * (p * p * p) + 1.15 * (p * p)
end

function BadgeCluster:GetStyle()
    local s = ns.db and ns.db.settings
    if s and s.minimapBadgeStyle == "separate" then
        return "separate"
    end
    return "fusion"
end

function BadgeCluster:ComputeFusionY()
    if button and button.GetBottom then
        local bot = button:GetBottom()
        if type(bot) == "number" and bot < 42 then
            self.fusionY = 21
            return 21
        end
    end
    self.fusionY = -21
    return -21
end

function BadgeCluster:CollectActiveCategories()
    local counts = {
        whisper = 0,
        bnet = 0,
        group = 0,
        raid = 0,
        guild = 0,
        room = 0,
    }

    if type(self.testCounts) == "table" then
        for _, cat in ipairs(BADGE_CATEGORY_ORDER) do
            counts[cat] = math.max(0, math.floor(tonumber(self.testCounts[cat]) or 0))
        end
    else
        local chatModOn = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("chat")
        if chatModOn and ns.Chat then
            local summary = ns.Chat.GetUnreadSummary and ns.Chat:GetUnreadSummary()
            if summary and type(summary.byCategory) == "table" then
                counts.whisper = summary.byCategory.whisper or 0
                counts.bnet = summary.byCategory.bnet or 0
                counts.group = summary.byCategory.group or 0
                counts.raid = summary.byCategory.raid or 0
                counts.guild = summary.byCategory.guild or 0
                counts.room = summary.byCategory.room or 0
            elseif ns.Chat.GetUnreadDirectCount then
                counts.whisper = ns.Chat:GetUnreadDirectCount() or 0
            elseif ns.Chat.GetTotalUnread then
                counts.whisper = ns.Chat:GetTotalUnread(false) or 0
            end
        end

        local clanOn = (not Compat or not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("clan")
        local clanNotifs = (clanOn and ns.Clan and ns.Clan.GetNotificationCount and ns.Clan:GetNotificationCount()) or 0
        counts.guild = counts.guild + clanNotifs

        if chatModOn then
            local s = ns.db and ns.db.settings
            local mirroredTracked = s and s.chatMirrorChannels == true and s.chatChannelUnread == true
            if mirroredTracked then
                self.previewCounts.group = nil
                self.previewCounts.raid = nil
                self.previewCounts.guild = nil
                for k, rec in pairs(self.previewCountsByThread) do
                    if type(rec) == "table" and (rec.cat == "group" or rec.cat == "raid" or rec.cat == "guild") then
                        self.previewCountsByThread[k] = nil
                    end
                end
            end

            for _, cat in ipairs(BADGE_CATEGORY_ORDER) do
                local pv = (self.previewCounts[cat] or 0) + ((self.testPreviewCounts and self.testPreviewCounts[cat]) or 0)
                if pv > 0 then
                    if cat == "group" or cat == "raid" or cat == "guild" or counts[cat] == 0 then
                        counts[cat] = counts[cat] + pv
                    end
                end
            end
            for k, rec in pairs(self.previewCountsByThread) do
                if type(rec) == "table" and (rec.count or 0) > 0 and rec.cat and counts[rec.cat] ~= nil then
                    local threadTracked = ns.Chat and ns.Chat.threads and ns.Chat.threads[k] and (ns.Chat.threads[k].unread or 0) > 0
                    if not threadTracked and (rec.cat == "group" or rec.cat == "raid" or rec.cat == "guild" or counts[rec.cat] == 0) then
                        counts[rec.cat] = counts[rec.cat] + rec.count
                    end
                end
            end
        else
            wipe(self.previewCounts)
            wipe(self.testPreviewCounts)
            wipe(self.previewCountsByThread)
        end
    end

    local items = {}
    local tones = {}
    local total = 0
    local sigParts = {}
    for _, cat in ipairs(BADGE_CATEGORY_ORDER) do
        local c = counts[cat] or 0
        if c > 0 then
            items[#items + 1] = { tone = cat, count = c }
            tones[#tones + 1] = cat
            total = total + c
            sigParts[#sigParts + 1] = cat .. ":" .. tostring(c)
        end
    end
    return items, total, tones, table.concat(sigParts, ","), table.concat(tones, ",")
end

function BadgeCluster:EnsureSatellite(index)
    local sat = self.satBadges[index]
    if sat then
        return sat
    end
    if not button then return nil end
    local Theme = ns.Theme
    if Theme and Theme.CreateCounterBadge then
        sat = Theme:CreateCounterBadge(button, {
            height = 22,
            maxNum = 99,
            haloAlpha = 0.42,
            minFontSize = 14,
            maxFontSize = 17,
            fontScaleOffset = 0,
        })
        sat:SetFrameLevel((button:GetFrameLevel() or 8) + 9)
        self.satBadges[index] = sat
        return sat
    end
    return nil
end

function BadgeCluster:HideAllSatellites()
    for i = 1, 6 do
        local sat = self.satBadges[i]
        if sat then
            sat:SetCount(0)
            sat:SetScale(1)
            sat:SetAlpha(1)
            sat:Hide()
        end
    end
end

function BadgeCluster:StopDriver()
    self._driveAccum = 0
    if self.driver then
        self.driver:SetScript("OnUpdate", nil)
    end
end

function BadgeCluster:ComputeOrbitalLayout(items)
    wipe(self.orbitCoords)
    local n = #items
    if n < 2 or not button then
        return
    end

    local maxSpan = 23
    for i = 1, n do
        local sat = self:EnsureSatellite(i)
        if sat then
            sat:SetCount(items[i].count, items[i].tone)
            sat:SetFrameLevel((button:GetFrameLevel() or 8) + 9)
            local sw = sat:GetWidth() or 22
            local sh = sat:GetHeight() or 22
            if sw > maxSpan then maxSpan = sw end
            if sh > maxSpan then maxSpan = sh end
        end
    end
    for i = n + 1, 6 do
        local sat = self.satBadges[i]
        if sat then
            sat:SetCount(0)
            sat:Hide()
        end
    end

    local anglesDeg, stepDeg, baseR
    if n == 2 then
        anglesDeg = { -126, -54 }
        stepDeg = 72
        baseR = 26
    elseif n == 3 then
        anglesDeg = { -156, -90, -24 }
        stepDeg = 66
        baseR = 28
    elseif n == 4 then
        anglesDeg = { -195, -125, -55, 15 }
        stepDeg = 70
        baseR = 29
    elseif n == 5 then
        anglesDeg = { -90, -18, 54, 126, 198 }
        stepDeg = 72
        baseR = 30
    else
        anglesDeg = { -90, -30, 30, 90, 150, 210 }
        stepDeg = 60
        baseR = 32
    end

    local flipUp = (self.fusionY or -21) > 0
    local stepRad = math.rad(stepDeg)
    local minR = (maxSpan + 5) / (2 * math.sin(stepRad * 0.5))
    local radius = math.max(baseR, math.min(44, minR))

    for i = 1, n do
        local deg = anglesDeg[i] or (-90 + (i - 1) * stepDeg)
        if flipUp then
            deg = -deg
        end
        local rad = math.rad(deg)
        self.orbitCoords[i] = {
            x = math.cos(rad) * radius,
            y = math.sin(rad) * radius,
            angle = rad,
            r = radius,
        }
    end
end

function BadgeCluster:PlaceSatellite(i, x, y, scale, alpha)
    local sat = self.satBadges[i]
    if not sat or not button then return end
    sat:ClearAllPoints()
    sat:SetPoint("CENTER", button, "CENTER", x, y)
    sat:SetScale(math.max(0.35, scale or 1))
    sat:SetAlpha(ClampUnit(alpha or 1))
    sat:Show()
end

function BadgeCluster:AnchorMainOrb()
    if not (button and button.msgBadgeFrame) then return end
    local fy = self:ComputeFusionY()
    if self._lastAnchoredFusionY == fy and self._lastAnchoredParent == button then
        return
    end
    self._lastAnchoredFusionY = fy
    self._lastAnchoredParent = button
    button.msgBadgeFrame:ClearAllPoints()
    button.msgBadgeFrame:SetPoint("CENTER", button, "CENTER", 0, fy)
    button.msgBadgeFrame:SetFrameLevel((button:GetFrameLevel() or 8) + 8)
end

function BadgeCluster:FinishFusion(triggerBurst)
    self:HideAllSatellites()
    self.phase = "FUSED"
    self.phaseTime = 0
    self:StopDriver()
    if not (button and button.msgBadgeFrame) then return end
    self:AnchorMainOrb()
    button.msgBadgeFrame:SetAlpha(1)
    if button.msgBadgeFrame.SetCountMulti then
        button.msgBadgeFrame:SetCountMulti(self.totalCount, self.activeTones, triggerBurst == true)
    elseif button.msgBadgeFrame.SetCount then
        button.msgBadgeFrame:SetCount(self.totalCount, self.activeTones[1] or "whisper")
    end
    if triggerBurst and MinimapBtn.PulseArrival then
        MinimapBtn:PulseArrival(1.0, 0.86, 0.42)
    end
end

function BadgeCluster:Drive(_, dt)
    self._driveAccum = (self._driveAccum or 0) + (dt or 0)
    if self._driveAccum < 0.033 then
        return
    end
    local delta = math.min(self._driveAccum, 0.06)
    self._driveAccum = 0
    local n = #self.activeItems
    if not button or n < 2 or not button:IsShown() then
        self:StopDriver()
        return
    end

    local fy = self.fusionY or -21
    self.phaseTime = (self.phaseTime or 0) + delta

    if self.phase == "ORBIT_HOLD" then
        local holdDur = 0.88
        local popP = ClampUnit(self.phaseTime / 0.28)
        local easePos = EaseOutBackUnit(popP)
        local alpha = ClampUnit(self.phaseTime / 0.16)
        local floatPhase = math.max(0, self.phaseTime - 0.28)
        for i = 1, n do
            local c = self.orbitCoords[i]
            if c then
                local bob = (popP >= 1) and (math.sin(floatPhase * 5.2 + i * 1.4) * 1.3) or 0
                local sx = c.x * easePos
                local sy = fy + (c.y - fy) * easePos + bob
                self:PlaceSatellite(i, sx, sy, 0.55 + 0.45 * EaseOutCubicUnit(popP), alpha)
            end
        end
        if button.msgBadgeFrame and button.msgBadgeFrame:IsShown() then
            button.msgBadgeFrame:SetAlpha(0.18)
        end
        if self.phaseTime >= holdDur then
            if self.hovered then
                self.phase = "HOVER_OPEN"
                self.phaseTime = 0
                for i = 1, n do
                    local c = self.orbitCoords[i]
                    if c then self:PlaceSatellite(i, c.x, c.y, 1, 1) end
                end
                self:StopDriver()
            else
                self.phase = "CONVERGE"
                self.phaseTime = 0
            end
        end
    elseif self.phase == "CONVERGE" or self.phase == "HOVER_IN" then
        local dur = (self.phase == "HOVER_IN") and 0.34 or 0.62
        local t = ClampUnit(self.phaseTime / dur)
        local p = EaseInOutCubicUnit(t)
        local swirlStrength = (self.phase == "HOVER_IN") and 0.42 or 0.78
        for i = 1, n do
            local c = self.orbitCoords[i]
            if c then
                local dx0 = c.x
                local dy0 = c.y - fy
                local dist0 = math.sqrt(dx0 * dx0 + dy0 * dy0)
                local ang0 = math.atan2(dy0, dx0)
                local curR = dist0 * (1 - p)
                local curAng = ang0 + swirlStrength * p * (1 - 0.32 * p)
                local x = math.cos(curAng) * curR
                local y = fy + math.sin(curAng) * curR
                local sc = 1 - 0.50 * p
                local a = (p < 0.72) and 1 or (1 - ((p - 0.72) / 0.28))
                self:PlaceSatellite(i, x, y, sc, a)
            end
        end
        if button.msgBadgeFrame and button.msgBadgeFrame:IsShown() then
            local orbA = (p < 0.65) and 0.16 or (0.16 + 0.84 * ((p - 0.65) / 0.35))
            button.msgBadgeFrame:SetAlpha(orbA)
        end
        if t >= 1 then
            self:FinishFusion(self.phase == "CONVERGE")
        end
    elseif self.phase == "HOVER_OUT" then
        local dur = 0.22
        local t = ClampUnit(self.phaseTime / dur)
        local p = EaseOutCubicUnit(t)
        for i = 1, n do
            local c = self.orbitCoords[i]
            if c then
                local x = c.x * p
                local y = fy + (c.y - fy) * p
                self:PlaceSatellite(i, x, y, 0.58 + 0.42 * p, p)
            end
        end
        if button.msgBadgeFrame and button.msgBadgeFrame:IsShown() then
            button.msgBadgeFrame:SetAlpha(1 - 0.86 * p)
        end
        if t >= 1 then
            self.phase = "HOVER_OPEN"
            self.phaseTime = 0
            if button.msgBadgeFrame then
                button.msgBadgeFrame:SetAlpha(0.14)
            end
            self:StopDriver()
        end
    else
        self:StopDriver()
    end
end

function BadgeCluster:StartDriver()
    if not self.driver then
        self.driver = CreateFrame("Frame", nil, UIParent)
    end
    if not self.driver:GetScript("OnUpdate") then
        self.driver:SetScript("OnUpdate", function(drv, dt)
            BadgeCluster:Drive(drv, dt)
        end)
    end
end

function BadgeCluster:StartFusionSequence()
    if not button or #self.activeItems < 2 then return end
    self:ComputeFusionY()
    self:ComputeOrbitalLayout(self.activeItems)
    self:AnchorMainOrb()
    if button.msgBadgeFrame and button.msgBadgeFrame.SetCountMulti then
        button.msgBadgeFrame:SetCountMulti(self.totalCount, self.activeTones, false)
        button.msgBadgeFrame:SetAlpha(0.18)
    end
    self.phase = "ORBIT_HOLD"
    self.phaseTime = 0
    self:StartDriver()
end

function BadgeCluster:SetHovered(isHovered)
    local want = isHovered == true
    if self.hovered == want then
        return
    end
    self.hovered = want
    if self:GetStyle() ~= "fusion" or #self.activeItems < 2 then
        return
    end
    if not (button and button:IsShown()) then
        return
    end
    local showNumBadge = not (ns.db and ns.db.settings and ns.db.settings.addonMsgMinimapBadge == false)
    if not showNumBadge then
        return
    end
    if want then
        if self.phase == "FUSED" or self.phase == "CONVERGE" or self.phase == "HOVER_IN" then
            self:ComputeFusionY()
            self:ComputeOrbitalLayout(self.activeItems)
            self.phase = "HOVER_OUT"
            self.phaseTime = 0
            self:StartDriver()
        end
    else
        if self.phase == "HOVER_OPEN" or self.phase == "HOVER_OUT" then
            self.phase = "HOVER_IN"
            self.phaseTime = 0
            self:StartDriver()
        end
    end
end

function BadgeCluster:ClearSessionPreviewCounts()
    local hadAny = next(self.previewCounts) ~= nil or next(self.testPreviewCounts) ~= nil or next(self.previewCountsByThread) ~= nil or self.testCounts ~= nil or self.lastPreviewThreadKey ~= nil
    wipe(self.previewCounts)
    wipe(self.testPreviewCounts)
    wipe(self.previewCountsByThread)
    self.lastPreviewThreadKey = nil
    if hadAny then
        return true
    end
    return false
end

local function UpdateBadge(forceFusionAnim)
    local items, totalCount, tones, fullSig, toneSig = BadgeCluster:CollectActiveCategories()
    local showNumBadge = not (ns.db and ns.db.settings and ns.db.settings.addonMsgMinimapBadge == false)
    local style = BadgeCluster:GetStyle()
    local spotterEnabled = not (ns.db and ns.db.settings and ns.db.settings.spotterEnabled == false)
    local hasSpotterHit = (totalCount == 0) and spotterEnabled and ns.Spotter and (select(1, ns.Spotter:GetCounts()) > 0) or false
    local showChatBtn = chatButton and IsOfficialChatShortcutEnabled() and _G.ChatFrame1 and _G.ChatFrame1.IsShown and _G.ChatFrame1:IsShown() and true or false
    local combinedSig = fullSig .. "|" .. tostring(showNumBadge) .. "|" .. style .. "|" .. tostring(hasSpotterHit) .. "|" .. tostring(showChatBtn) .. "|" .. tostring(BadgeCluster.hovered == true)
    if not forceFusionAnim and BadgeCluster._lastCombinedSig == combinedSig and (not showChatBtn or (chatButton and chatButton:IsShown())) then
        return
    end
    BadgeCluster._lastCombinedSig = combinedSig
    BadgeCluster.activeItems = items
    BadgeCluster.activeTones = tones
    BadgeCluster.totalCount = totalCount

    local prevToneSig = BadgeCluster.lastToneSig or ""
    local prevTotal = BadgeCluster.lastTotal or 0
    local shouldTriggerFusion = forceFusionAnim == true
        or (totalCount > prevTotal and #items >= 2)
        or (toneSig ~= prevToneSig and #items >= 2)

    BadgeCluster.lastToneSig = toneSig
    BadgeCluster.lastFullSig = fullSig
    BadgeCluster.lastTotal = totalCount

    if button and button.msgBadgeFrame then
        BadgeCluster:AnchorMainOrb()
        if not showNumBadge or totalCount <= 0 then
            BadgeCluster:StopDriver()
            BadgeCluster:HideAllSatellites()
            BadgeCluster.phase = "IDLE"
            if button.msgBadgeFrame.SetCount then
                button.msgBadgeFrame:SetCount(0)
            else
                button.msgBadgeFrame:Hide()
                if button.badge then
                    button.badge:Hide()
                    button.badge:SetText("")
                end
            end
        elseif #items == 1 then
            BadgeCluster:StopDriver()
            BadgeCluster:HideAllSatellites()
            BadgeCluster.phase = "FUSED"
            button.msgBadgeFrame:SetAlpha(1)
            local singleTone = items[1].tone
            if button.msgBadgeFrame.SetCount then
                button.msgBadgeFrame:SetCount(totalCount, singleTone)
            elseif button.badge then
                local label = totalCount > 99 and "99+" or tostring(totalCount)
                if ns.Theme and ns.Theme.ApplyReadableCounterFont then
                    ns.Theme:ApplyReadableCounterFont(button.badge, 15, 20, 1, true)
                end
                button.badge:SetText(label)
                button.msgBadgeFrame:SetWidth(totalCount > 99 and 38 or (totalCount > 9 and 31 or 24))
                button.msgBadgeFrame:Show()
                button.badge:Show()
            end
        elseif style == "separate" then
            BadgeCluster:StopDriver()
            if button.msgBadgeFrame.SetCount then
                button.msgBadgeFrame:SetCount(0)
            else
                button.msgBadgeFrame:Hide()
            end
            BadgeCluster:ComputeFusionY()
            BadgeCluster:ComputeOrbitalLayout(items)
            for i = 1, #items do
                local c = BadgeCluster.orbitCoords[i]
                if c then
                    BadgeCluster:PlaceSatellite(i, c.x, c.y, 1, 1)
                end
            end
            BadgeCluster.phase = "SEPARATE"
        else
            -- Fusion mode with 2+ distinct active chat categories
            if shouldTriggerFusion and button:IsShown() then
                BadgeCluster:StartFusionSequence()
            elseif BadgeCluster.hovered and (BadgeCluster.phase == "HOVER_OPEN" or BadgeCluster.phase == "HOVER_OUT") then
                BadgeCluster:ComputeFusionY()
                BadgeCluster:ComputeOrbitalLayout(items)
                for i = 1, #items do
                    local c = BadgeCluster.orbitCoords[i]
                    if c then
                        BadgeCluster:PlaceSatellite(i, c.x, c.y, 1, 1)
                    end
                end
            elseif BadgeCluster.phase ~= "ORBIT_HOLD" and BadgeCluster.phase ~= "CONVERGE" then
                BadgeCluster:FinishFusion(false)
            else
                BadgeCluster:ComputeOrbitalLayout(items)
            end
        end
    end

    local ringR, ringG, ringB = 1, 1, 1
    if totalCount > 0 then
        if #items == 1 and ns.Theme and ns.Theme.GetChatToneSpec then
            local ac = ns.Theme:GetChatToneSpec(items[1].tone).accent
            ringR, ringG, ringB = ac[1], ac[2], ac[3]
        else
            ringR, ringG, ringB = 1.0, 0.86, 0.34
        end
    elseif hasSpotterHit then
        ringR, ringG, ringB = 0.96, 0.28, 0.28
    end

    local ringSig = string.format("%.2f:%.2f:%.2f", ringR, ringG, ringB)
    if button and button.overlayRing then
        if button._lastRingSig ~= ringSig then
            button._lastRingSig = ringSig
            button.overlayRing:SetVertexColor(ringR, ringG, ringB)
        end
    end

    if chatButton then
        if showChatBtn then
            if not chatButton:IsShown() or not chatButton._scPositionedOnce then
                chatButton._scPositionedOnce = true
                UpdateChatButtonPosition()
            end
            chatButton:Show()
        else
            chatButton:Hide()
        end
        if chatButton.msgBadgeFrame then
            if not showNumBadge or totalCount <= 0 then
                if chatButton.msgBadgeFrame.SetCount then
                    chatButton.msgBadgeFrame:SetCount(0)
                else
                    chatButton.msgBadgeFrame:Hide()
                    if chatButton.badge then
                        chatButton.badge:Hide()
                        chatButton.badge:SetText("")
                    end
                end
            elseif #items == 1 then
                chatButton.msgBadgeFrame:SetAlpha(1)
                if chatButton.msgBadgeFrame.SetCount then
                    chatButton.msgBadgeFrame:SetCount(totalCount, items[1].tone)
                elseif chatButton.badge then
                    local label = totalCount > 99 and "99+" or tostring(totalCount)
                    if ns.Theme and ns.Theme.ApplyReadableCounterFont then
                        ns.Theme:ApplyReadableCounterFont(chatButton.badge, 15, 20, 1, true)
                    end
                    chatButton.badge:SetText(label)
                    chatButton.msgBadgeFrame:SetWidth(totalCount > 99 and 38 or (totalCount > 9 and 31 or 24))
                    chatButton.msgBadgeFrame:Show()
                    chatButton.badge:Show()
                end
            else
                chatButton.msgBadgeFrame:SetAlpha(1)
                if chatButton.msgBadgeFrame.SetCountMulti then
                    chatButton.msgBadgeFrame:SetCountMulti(totalCount, tones, shouldTriggerFusion == true)
                elseif chatButton.msgBadgeFrame.SetCount then
                    chatButton.msgBadgeFrame:SetCount(totalCount, items[1].tone)
                end
            end
        end
        if chatButton.overlayRing and chatButton._lastRingSig ~= ringSig then
            chatButton._lastRingSig = ringSig
            chatButton.overlayRing:SetVertexColor(ringR, ringG, ringB)
        end
    end

    if ldbObject then
        ldbObject.text = totalCount > 0 and ("SocialCentral (" .. tostring(totalCount) .. ")") or "SocialCentral"
    end
end

local leftChooserFrame

local function OpenMainWindowFromMinimap()
    MinimapBtn:ClearPreviewCounts()
    if ns.UI and ns.UI.ShowHub then
        ns.UI:ShowHub()
    elseif ns.UI and ns.UI.Toggle then
        ns.UI:Toggle()
    end
end

local function OpenSettingsFromMinimap()
    if ns.Settings and ns.Settings.Toggle then
        ns.Settings:Toggle()
    elseif ns.Settings and ns.Settings.Open then
        ns.Settings:Open()
    end
end

local function OpenLeftClickMenu(anchor)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(anchor, function(_, root)
            root:CreateTitle("SocialCentral")
            root:CreateButton(L["Open Main Window"], OpenMainWindowFromMinimap)
            root:CreateButton(L["Open Settings"], OpenSettingsFromMinimap)
        end)
        return
    end

    if not leftChooserFrame then
        local f = CreateFrame("Frame", "SocialCentralMinimapLeftChooser", UIParent, "BackdropTemplate")
        f:SetSize(188, 86)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(160)
        f:EnableMouse(true)
        f:SetClampedToScreen(true)
        table.insert(UISpecialFrames, "SocialCentralMinimapLeftChooser")
        if ns.Theme and ns.Theme.MakeMovable then
            ns.Theme:MakeMovable(f, { key = "minimap_left_chooser" })
        end

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetPoint("TOPRIGHT", -12, -10)
        title:SetJustifyH("CENTER")
        title:SetText("SocialCentral")
        f.title = title

        local btnMain = ns.Theme and ns.Theme:CreateButton(f, 164, 24, L["Open Main Window"], "primary")
        btnMain:SetPoint("TOP", title, "BOTTOM", 0, -6)
        btnMain:SetScript("OnClick", function()
            f:Hide()
            OpenMainWindowFromMinimap()
        end)
        f.btnMain = btnMain

        local btnSettings = ns.Theme and ns.Theme:CreateButton(f, 164, 24, L["Open Settings"], "default")
        btnSettings:SetPoint("TOP", btnMain, "BOTTOM", 0, -4)
        btnSettings:SetScript("OnClick", function()
            f:Hide()
            OpenSettingsFromMinimap()
        end)
        f.btnSettings = btnSettings

        if ns.Theme and ns.Theme.CreateHelpButton then
            local chooserHelp = ns.Theme:CreateHelpButton(
                f,
                L["Help: Minimap Button Shortcuts"],
                L["Provides quick access to Quick Reply, the Main SocialCentral Hub, Settings, and contextual alerts right beside your Minimap or Official Chat."],
                L["Use Left-Click to toggle Quick Reply, Shift+Click to open the Main Window, Alt+Click for Target Radar, Ctrl+Click for Conversations, Right-Click for quick toggles, or Drag to move."],
                16,
                { target = f }
            )
            chooserHelp:SetPoint("TOPRIGHT", -6, -7)
            f.helpBtn = chooserHelp
        end

        f:Hide()
        leftChooserFrame = f
    end

    if leftChooserFrame:IsShown() then
        leftChooserFrame:Hide()
        return
    end

    if ns.Theme and ns.Theme.ApplyBackdrop then
        ns.Theme:ApplyBackdrop(leftChooserFrame, "window")
        ns.Theme:StyleButton(leftChooserFrame.btnMain, "primary")
        ns.Theme:StyleButton(leftChooserFrame.btnSettings, "default")
        if leftChooserFrame.helpBtn and leftChooserFrame.helpBtn.RefreshTheme then
            leftChooserFrame.helpBtn:RefreshTheme()
        end
    end
    leftChooserFrame:ClearAllPoints()
    if anchor and anchor.GetCenter then
        leftChooserFrame:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", -2, -2)
    else
        leftChooserFrame:SetPoint("CENTER")
    end
    leftChooserFrame:Show()
end

function MinimapBtn:PerformSmartLeftClick(anchor)
    local lastPreviewKey = BadgeCluster.lastPreviewThreadKey
    if BadgeCluster:ClearSessionPreviewCounts() then
        BadgeCluster.testCounts = nil
        UpdateBadge(false)
    end
    if Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode() then
        OpenMainWindowFromMinimap()
        return
    end
    local clickMode = (ns.db and ns.db.settings and ns.db.settings.minimapLeftClickAction) or "smart"
    if clickMode == "menu" then
        OpenLeftClickMenu(anchor or button)
        return
    end
    if clickMode == "hub" then
        OpenMainWindowFromMinimap()
        return
    end
    local chatModOn = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("chat")
    local s = ns.db and ns.db.settings
    local qrEnabled = (not s) or s.quickReplyEnabled ~= false
    local qrOpen = ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown() == true

    if qrOpen then
        if chatModOn and ns.Chat and qrEnabled and ns.QuickReply then
            local unreadJumpKey = (ns.QuickReply.GetFirstPendingActionKey and ns.QuickReply:GetFirstPendingActionKey(true)) or nil
            if (not unreadJumpKey) and lastPreviewKey and ns.Chat.threads and ns.Chat.threads[lastPreviewKey] then
                unreadJumpKey = lastPreviewKey
            end
            if unreadJumpKey and unreadJumpKey ~= ns.QuickReply.activeKey and ns.QuickReply.OpenThread then
                ns.QuickReply:OpenThread(unreadJumpKey, false)
                return
            end
        end
        if ns.QuickReply and ns.QuickReply.frame then
            if ns.QuickReply.SaveCurrentDraft then
                ns.QuickReply:SaveCurrentDraft()
            end
            ns.QuickReply._manualClosePending = true
            ns.QuickReply.frame:Hide()
        end
        return
    end

    if chatModOn and ns.Chat and qrEnabled and ns.QuickReply then
        if ns.QuickReply.OpenPreviewOrLatest and ns.QuickReply:OpenPreviewOrLatest(lastPreviewKey) then
            return
        elseif ns.QuickReply.OpenLatest and ns.QuickReply:OpenLatest(true) then
            return
        end
    end
    OpenMainWindowFromMinimap()
end

local function HandleMinimapClick(anchor, mouseButton)
    if mouseButton == "RightButton" then
        if leftChooserFrame and leftChooserFrame:IsShown() then leftChooserFrame:Hide() end
        if GameTooltip then GameTooltip:Hide() end
        OpenContextMenu(anchor)
    elseif IsAltKeyDown and IsAltKeyDown() then
        if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("radar") then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        if ns.SpotterHUD and ns.SpotterHUD.Toggle then
            ns.SpotterHUD:Toggle()
        end
    elseif IsControlKeyDown and IsControlKeyDown() then
        if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("chat") then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        OpenViaOfficialOrHub("chat")
    elseif IsShiftKeyDown and IsShiftKeyDown() then
        if GameTooltip then GameTooltip:Hide() end
        MinimapBtn:ClearPreviewCounts()
        if ns.UI and ns.UI.IsMainVisible and ns.UI:IsMainVisible() then
            if ns.UI.Hide then
                ns.UI:Hide()
            elseif ns.UI.Toggle then
                ns.UI:Toggle()
            end
        else
            OpenMainWindowFromMinimap()
        end
    else
        if GameTooltip then GameTooltip:Hide() end
        MinimapBtn:PerformSmartLeftClick(anchor)
    end
end

local function RegisterBroker()
    if ldbObject then
        return
    end
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    if ldb and ldb.NewDataObject then
        ldbObject = ldb:NewDataObject("SocialCentral", {
            type = "data source",
            text = "SocialCentral",
            icon = ICON_TEX,
            OnClick = function(self, mouseButton)
                HandleMinimapClick(self, mouseButton)
            end,
            OnTooltipShow = function(tt)
                if tt then PopulateTooltip(tt) end
            end,
        })
    end
end

local function InitShortcutVisuals(targetBtn, badgeRelPoint, badgeX, badgeY)
    local background = targetBtn:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetPoint("CENTER")
    background:SetTexture(BG_TEX)

    local icon = targetBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON_TEX)
    targetBtn.icon = icon
    SetIconPressed(false, targetBtn)

    local overlay = targetBtn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(50, 50)
    overlay:SetPoint("TOPLEFT")
    overlay:SetTexture(RING_TEX)
    targetBtn.overlayRing = overlay

    local pulseFrame = CreateFrame("Frame", nil, targetBtn)
    pulseFrame:SetAllPoints(targetBtn)
    pulseFrame:EnableMouse(false)
    pulseFrame:SetFrameLevel((targetBtn:GetFrameLevel() or 8) + 4)
    local pulseGlow = pulseFrame:CreateTexture(nil, "OVERLAY", nil, 4)
    pulseGlow:SetSize(42, 42)
    pulseGlow:SetPoint("CENTER", targetBtn, "CENTER", 0, 0)
    pulseGlow:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\toast-glow")
    pulseGlow:SetBlendMode("ADD")
    pulseGlow:SetAlpha(0)
    pulseGlow:Hide()
    targetBtn.pulseFrame = pulseFrame
    targetBtn.pulseGlow = pulseGlow

    if pulseGlow.CreateAnimationGroup then
        local okAg, ag = pcall(pulseGlow.CreateAnimationGroup, pulseGlow)
        if okAg and ag then
            local okS, sc = pcall(ag.CreateAnimation, ag, "Scale")
            if okS and sc then
                if sc.SetScaleFrom then pcall(sc.SetScaleFrom, sc, 0.90, 0.90) end
                if sc.SetScaleTo then pcall(sc.SetScaleTo, sc, 1.48, 1.48) end
                if sc.SetOrigin then pcall(sc.SetOrigin, sc, "CENTER", 0, 0) end
                if sc.SetDuration then sc:SetDuration(0.42) end
                if sc.SetSmoothing then sc:SetSmoothing("OUT") end
            end
            local okA1, a1 = pcall(ag.CreateAnimation, ag, "Alpha")
            if okA1 and a1 then
                if a1.SetOrder then a1:SetOrder(1) end
                if a1.SetFromAlpha then a1:SetFromAlpha(0.05) end
                if a1.SetToAlpha then a1:SetToAlpha(0.88) end
                if a1.SetDuration then a1:SetDuration(0.12) end
            end
            local okA2, a2 = pcall(ag.CreateAnimation, ag, "Alpha")
            if okA2 and a2 then
                if a2.SetOrder then a2:SetOrder(2) end
                if a2.SetFromAlpha then a2:SetFromAlpha(0.88) end
                if a2.SetToAlpha then a2:SetToAlpha(0.0) end
                if a2.SetDuration then a2:SetDuration(0.30) end
                if a2.SetSmoothing then a2:SetSmoothing("OUT") end
            end
            ag:SetScript("OnFinished", function()
                pulseGlow:SetAlpha(0)
                pulseGlow:Hide()
            end)
            targetBtn.pulseAg = ag
        end
    end

    local Theme = ns.Theme
    if Theme and Theme.CreateCounterBadge then
        local badge = Theme:CreateCounterBadge(targetBtn, {
            height = 26,
            maxNum = 99,
            haloAlpha = 0.52,
            minFontSize = 15,
            maxFontSize = 20,
            fontScaleOffset = 1,
        })
        badge:SetPoint("CENTER", targetBtn, badgeRelPoint or "CENTER", badgeX or 0, badgeY or -21)
        badge:SetFrameLevel((targetBtn:GetFrameLevel() or 8) + 8)
        targetBtn.msgBadgeFrame = badge
        targetBtn.badge = badge.text
    else
        local badgeFrame = CreateFrame("Frame", nil, targetBtn, "BackdropTemplate")
        badgeFrame:SetSize(25, 25)
        badgeFrame:SetPoint("CENTER", targetBtn, badgeRelPoint or "CENTER", badgeX or 0, badgeY or -21)
        badgeFrame:SetFrameLevel((targetBtn:GetFrameLevel() or 8) + 8)
        if badgeFrame.SetBackdrop then
            badgeFrame:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            badgeFrame:SetBackdropColor(0.84, 0.24, 0.80, 1.0)
            badgeFrame:SetBackdropBorderColor(0.08, 0.08, 0.10, 1.0)
        end
        badgeFrame:Hide()

        local badgeText = badgeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if Theme and Theme.ApplyReadableCounterFont then
            Theme:ApplyReadableCounterFont(badgeText, 15, 20, 1, true)
        end
        badgeText:SetPoint("CENTER", 0, 0)
        badgeText:SetTextColor(1, 1, 1)
        targetBtn.msgBadgeFrame = badgeFrame
        targetBtn.badge = badgeText
    end
end

local function EnsureButton()
    if button then
        return
    end

    RegisterBroker()

    button = CreateFrame("Button", "SocialCentralMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(math.max(8, (Minimap:GetFrameLevel() or 0) + 8))
    button:SetHighlightTexture(HIGHLIGHT_TEX)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    InitShortcutVisuals(button, "CENTER", 0, -21)

    local function StopMinimapButtonDrag(selfBtn)
        selfBtn:UnlockHighlight()
        SetIconPressed(false)
        if selfBtn:GetScript("OnUpdate") then
            selfBtn:SetScript("OnUpdate", nil)
            UpdateBadge(false)
        end
    end

    button:SetScript("OnMouseDown", function() SetIconPressed(true) end)
    button:SetScript("OnMouseUp", function(self, mouseBtn)
        SetIconPressed(false)
        if mouseBtn == "LeftButton" and self:GetScript("OnUpdate") then
            StopMinimapButtonDrag(self)
        end
    end)

    button:SetScript("OnClick", function(self, mouseButton)
        HandleMinimapClick(self, mouseButton)
    end)

    button._dragUpdateFn = function(selfBtn)
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            StopMinimapButtonDrag(selfBtn)
            return
        end
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale() or 1
        if not mx or not my then
            return
        end
        local deg = math.deg(math.atan2((cy / scale) - my, (cx / scale) - mx)) % 360
        if ns.db and ns.db.settings and ns.db.settings.minimap then
            ns.db.settings.minimap.angle = deg
            local resKey = ns.Theme and ns.Theme.GetScreenProfileKey and ns.Theme:GetScreenProfileKey()
            if resKey then
                if type(ns.db.settings.minimap.anglesByRes) ~= "table" then
                    ns.db.settings.minimap.anglesByRes = {}
                end
                ns.db.settings.minimap.anglesByRes[resKey] = deg
            end
        end
        UpdatePosition()
    end

    button:SetScript("OnDragStart", function(self)
        if ns.db and ns.db.settings and ns.db.settings.minimap and ns.db.settings.minimap.lock then
            return
        end
        GameTooltip:Hide()
        self:LockHighlight()
        SetIconPressed(true)
        self:SetScript("OnUpdate", self._dragUpdateFn)
    end)

    button:SetScript("OnDragStop", StopMinimapButtonDrag)
    button:HookScript("OnHide", StopMinimapButtonDrag)

    button:SetScript("OnEnter", function(self)
        BadgeCluster:SetHovered(true)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            PopulateTooltip(GameTooltip)
            GameTooltip:Show()
        end
    end)

    button:SetScript("OnLeave", function(self)
        BadgeCluster:SetHovered(false)
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)
end

local function EnsureChatButton()
    if chatButton then
        return chatButton
    end
    local parent = UIParent
    if not parent then
        return nil
    end
    chatButton = CreateFrame("Button", "SocialCentralChatShortcutButton", parent)
    chatButton:SetSize(31, 31)
    chatButton:SetFrameStrata("MEDIUM")
    chatButton:EnableMouse(true)
    chatButton:SetMovable(true)
    chatButton:SetClampedToScreen(true)
    if chatButton.SetDontSavePosition then
        pcall(chatButton.SetDontSavePosition, chatButton, true)
    end
    if chatButton.SetUserPlaced then
        pcall(chatButton.SetUserPlaced, chatButton, false)
    end
    chatButton:SetHighlightTexture(HIGHLIGHT_TEX)
    chatButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    chatButton:RegisterForDrag("LeftButton")

    InitShortcutVisuals(chatButton, "TOPRIGHT", -2, -2)

    local function StopChatButtonDrag(selfBtn)
        selfBtn:UnlockHighlight()
        SetIconPressed(false, selfBtn)
        if selfBtn.StopMovingOrSizing then
            pcall(selfBtn.StopMovingOrSizing, selfBtn)
        end
        if not selfBtn._scDragging then
            return
        end
        selfBtn._scDragging = false
        selfBtn._scJustDraggedAt = (GetTime and GetTime()) or 0

        local pt, relTo, relPt, xOfs, yOfs = selfBtn:GetPoint(1)
        if type(pt) == "string" and tonumber(xOfs) and tonumber(yOfs) and (relTo == nil or relTo == UIParent) then
            SaveChatButtonPosition({
                point = pt,
                relPoint = relPt or pt,
                x = math.floor(tonumber(xOfs) + 0.5),
                y = math.floor(tonumber(yOfs) + 0.5),
            })
        else
            local cx, cy = selfBtn:GetCenter()
            local ux, uy
            if UIParent then
                ux, uy = UIParent:GetCenter()
            end
            if cx and cy and ux and uy and cx == cx and cy == cy then
                local winScale = (selfBtn.GetEffectiveScale and selfBtn:GetEffectiveScale()) or 1
                local uiScale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
                local scale = (uiScale > 0) and (winScale / uiScale) or 1
                if scale <= 0 then scale = 1 end
                SaveChatButtonPosition({
                    point = "CENTER",
                    relPoint = "CENTER",
                    x = math.floor(((cx * scale - ux) / scale) + 0.5),
                    y = math.floor(((cy * scale - uy) / scale) + 0.5),
                })
            end
        end
        if selfBtn.msgBadgeFrame then
            selfBtn.msgBadgeFrame:ClearAllPoints()
            selfBtn.msgBadgeFrame:SetPoint("CENTER", selfBtn, "TOPRIGHT", -2, -2)
            selfBtn.msgBadgeFrame:SetFrameLevel((selfBtn:GetFrameLevel() or 8) + 8)
        end
    end

    local function StartChatButtonDrag(selfBtn)
        if ns.db and ns.db.settings and ns.db.settings.chatButtonLock == true then
            return
        end
        if GameTooltip then GameTooltip:Hide() end
        selfBtn:SetMovable(true)
        selfBtn:SetClampedToScreen(true)
        selfBtn:LockHighlight()
        SetIconPressed(true, selfBtn)
        selfBtn._scDragging = true
        local ok = pcall(selfBtn.StartMoving, selfBtn)
        if not ok then
            selfBtn._scDragging = false
            selfBtn:UnlockHighlight()
            SetIconPressed(false, selfBtn)
        end
    end

    chatButton:SetScript("OnMouseDown", function(selfBtn)
        SetIconPressed(true, selfBtn)
    end)
    chatButton:SetScript("OnMouseUp", function(selfBtn, mouseBtn)
        SetIconPressed(false, selfBtn)
        if mouseBtn == "LeftButton" and selfBtn._scDragging then
            StopChatButtonDrag(selfBtn)
        end
    end)
    chatButton:SetScript("OnDragStart", StartChatButtonDrag)
    chatButton:SetScript("OnDragStop", StopChatButtonDrag)
    chatButton:HookScript("OnHide", StopChatButtonDrag)
    chatButton:SetScript("OnClick", function(selfBtn, mouseButton)
        if selfBtn._scJustDraggedAt and GetTime and (GetTime() - selfBtn._scJustDraggedAt) < 0.25 then
            return
        end
        HandleMinimapClick(selfBtn, mouseButton)
    end)
    chatButton:SetScript("OnEnter", function(selfBtn)
        if GameTooltip then
            GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
            PopulateTooltip(GameTooltip)
            GameTooltip:Show()
        end
    end)
    chatButton:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(selfBtn) then
            GameTooltip:Hide()
        end
    end)
    if ns.Theme and ns.Theme.RegisterViewportListener then
        ns.Theme:RegisterViewportListener("official_chat_button", UpdateChatButtonPosition)
    end
    chatButton:Hide()
    return chatButton
end

local function ShortcutFallbackPulseOnUpdate(self, dt)
    self._pulseAccum = (self._pulseAccum or 0) + (dt or 0)
    if self._pulseAccum < 0.033 then return end
    self._pulseElapsed = (self._pulseElapsed or 0) + self._pulseAccum
    self._pulseAccum = 0
    local p = self._pulseElapsed / 0.42
    local pg = self._pulseGlowRef
    local targetBtn = self._pulseTargetRef
    if not (targetBtn and targetBtn:IsShown()) or p >= 1 then
        if pg then
            pg:SetAlpha(0)
            pg:Hide()
        end
        self:SetScript("OnUpdate", nil)
        return
    end
    if pg then
        local alpha = (p < 0.28) and ((p / 0.28) * 0.85) or ((1 - ((p - 0.28) / 0.72)) * 0.85)
        local sz = math.floor(36 + (18 * p) + 0.5)
        pg:SetSize(sz, sz)
        pg:SetAlpha(math.max(0, math.min(1, alpha)))
    end
end

local function PulseOneShortcut(targetBtn, r, g, b)
    if not (targetBtn and targetBtn:IsShown() and targetBtn.pulseFrame and targetBtn.pulseGlow) then
        return
    end
    local pg = targetBtn.pulseGlow
    pg:SetVertexColor(r or 0.98, g or 0.82, b or 0.28, 1)
    if targetBtn.pulseAg then
        pcall(targetBtn.pulseAg.Stop, targetBtn.pulseAg)
        pg:SetAlpha(1)
        pg:Show()
        pcall(targetBtn.pulseAg.Play, targetBtn.pulseAg)
        return
    end
    local pf = targetBtn.pulseFrame
    pg:SetSize(36, 36)
    pg:SetAlpha(0.05)
    pg:Show()
    pf._pulseElapsed = 0
    pf._pulseAccum = 0
    pf._pulseGlowRef = pg
    pf._pulseTargetRef = targetBtn
    if not pf:GetScript("OnUpdate") then
        pf:SetScript("OnUpdate", ShortcutFallbackPulseOnUpdate)
    end
end

--- Return the live SocialCentral minimap button frame (or nil if not built yet).
function MinimapBtn:GetButton()
    return button
end

function MinimapBtn:GetChatButton()
    return chatButton
end

--- Trigger a brief luminous pulse on the SC icon when a message preview emerges or returns.
function MinimapBtn:PulseArrival(r, g, b)
    PulseOneShortcut(button, r, g, b)
    PulseOneShortcut(chatButton, r, g, b)
end

--- Create or refresh visibility, shape position, and badge count of the minimap & official chat shortcut buttons.
function MinimapBtn:Update()
    EnsureButton()
    EnsureChatButton()
    UpdateBadge()
    local hide = ns.db and ns.db.settings and ns.db.settings.minimap and ns.db.settings.minimap.hide
    if hide then
        button:Hide()
    else
        UpdatePosition()
        button:Show()
    end
    if chatButton then
        local cf = _G.ChatFrame1
        local showChatBtn = IsOfficialChatShortcutEnabled() and cf and cf.IsShown and cf:IsShown()
        if showChatBtn then
            UpdateChatButtonPosition()
            chatButton:Show()
        else
            chatButton:Hide()
        end
        if not chatHooksInstalled and cf and cf.HookScript then
            chatHooksInstalled = true
            local function SyncChatAnchor()
                if not chatButton then return end
                local showNow = IsOfficialChatShortcutEnabled() and _G.ChatFrame1 and _G.ChatFrame1:IsShown()
                if showNow then
                    UpdateChatButtonPosition()
                    chatButton:Show()
                else
                    chatButton:Hide()
                end
                if ns.LFGFrameTab and ns.LFGFrameTab.RefreshOfficialChatQuickButton then
                    ns.LFGFrameTab:RefreshOfficialChatQuickButton()
                end
                if QuickReply and QuickReply.frame and QuickReply.frame:IsShown() and QuickReply.SyncDockGeometry then
                    QuickReply:SyncDockGeometry()
                end
                if ns.NotificationToast and ns.NotificationToast.RefreshAnchorMode then
                    ns.NotificationToast:RefreshAnchorMode()
                end
                if MsgPreview and MsgPreview.SyncAnchorMoverPosition then
                    MsgPreview:SyncAnchorMoverPosition()
                end
            end
            cf:HookScript("OnShow", SyncChatAnchor)
            cf:HookScript("OnHide", SyncChatAnchor)
            cf:HookScript("OnSizeChanged", SyncChatAnchor)
            if type(cf.StopMovingOrSizing) == "function" and hooksecurefunc then
                hooksecurefunc(cf, "StopMovingOrSizing", SyncChatAnchor)
            end
            if _G.ChatFrame1ButtonFrame and _G.ChatFrame1ButtonFrame.HookScript then
                _G.ChatFrame1ButtonFrame:HookScript("OnShow", SyncChatAnchor)
                _G.ChatFrame1ButtonFrame:HookScript("OnHide", SyncChatAnchor)
            end
        end
    end
    if ns.LFGFrameTab and ns.LFGFrameTab.RefreshOfficialChatQuickButton then
        ns.LFGFrameTab:RefreshOfficialChatQuickButton()
    end
end

local function SetOfficialSurfaceFrameHidden(fr, hidden, allowMouseToggle)
    if not fr then return end
    local wantAlpha = hidden and 0 or 1
    if fr.SetAlpha then
        local curAlpha = fr.GetAlpha and fr:GetAlpha() or nil
        if curAlpha == nil or math.abs(curAlpha - wantAlpha) > 0.005 then
            pcall(fr.SetAlpha, fr, wantAlpha)
        end
    end
    if allowMouseToggle and fr.EnableMouse then
        local isProt = fr.IsProtected and fr:IsProtected()
        if not isProt then
            local wantMouse = not hidden
            local curMouse = fr.IsMouseEnabled and fr:IsMouseEnabled()
            if curMouse == nil or curMouse ~= wantMouse then
                pcall(fr.EnableMouse, fr, wantMouse)
            end
        end
    end
end

local OFFICIAL_CHAT_NAMED_FRAME_KEYS = {
    "GeneralDockManager",
    "GeneralDockManagerScrollFrame",
    "ChatFrameMenuButton",
    "ChatFrameChannelButton",
    "QuickJoinToastButton",
    "FriendsMicroButton",
    "ChatFrameToggleVoiceDeafenButton",
    "ChatFrameToggleVoiceMuteButton",
    "VoiceActivityManager",
}

function MinimapBtn:ApplyExclusiveChatMode()
    local chosen = Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode()
    if not chosen then
        return
    end
    local hideOfficial = Compat and Compat.IsAddonChatMode and Compat.IsAddonChatMode()
    local inCombat = (InCombatLockdown and InCombatLockdown()) or false
    local allowMouse = not inCombat
    if inCombat and hideOfficial then
        self._pendingExclusiveChatApply = true
    elseif not inCombat then
        self._pendingExclusiveChatApply = false
    end

    for i = 1, #OFFICIAL_CHAT_NAMED_FRAME_KEYS do
        SetOfficialSurfaceFrameHidden(_G[OFFICIAL_CHAT_NAMED_FRAME_KEYS[i]], hideOfficial, allowMouse)
    end
    for i = 1, 10 do
        local cf = _G["ChatFrame" .. i]
        local tab = _G["ChatFrame" .. i .. "Tab"]
        local bg = _G["ChatFrame" .. i .. "Background"]
        local bf = _G["ChatFrame" .. i .. "ButtonFrame"]
        local eb = _G["ChatFrame" .. i .. "EditBox"] or (cf and cf.editBox)
        SetOfficialSurfaceFrameHidden(cf, hideOfficial, allowMouse)
        SetOfficialSurfaceFrameHidden(tab, hideOfficial, allowMouse)
        SetOfficialSurfaceFrameHidden(bg, hideOfficial, false)
        SetOfficialSurfaceFrameHidden(bf, hideOfficial, allowMouse)
        SetOfficialSurfaceFrameHidden(_G["ChatFrame" .. i .. "ResizeButton"], hideOfficial, allowMouse)
        SetOfficialSurfaceFrameHidden(_G["ChatFrame" .. i .. "BottomButton"], hideOfficial, allowMouse)
        SetOfficialSurfaceFrameHidden(_G["ChatFrame" .. i .. "UpButton"], hideOfficial, allowMouse)
        SetOfficialSurfaceFrameHidden(_G["ChatFrame" .. i .. "DownButton"], hideOfficial, allowMouse)
        if cf then
            SetOfficialSurfaceFrameHidden(cf.Background, hideOfficial, false)
            SetOfficialSurfaceFrameHidden(cf.ScrollBar, hideOfficial, allowMouse)
            SetOfficialSurfaceFrameHidden(cf.ScrollToBottomButton, hideOfficial, allowMouse)
            SetOfficialSurfaceFrameHidden(cf.buttonFrame, hideOfficial, allowMouse)
        end
        if eb then
            if eb.SetIgnoreParentAlpha then
                pcall(eb.SetIgnoreParentAlpha, eb, true)
            end
            if not hideOfficial then
                eb._scDockedToQr = false
                eb._scPreDockedToQr = false
                if QuickReply and QuickReply.RestoreOfficialEditBoxFull then
                    QuickReply:RestoreOfficialEditBoxFull(eb)
                else
                    if eb._scOrigPoints and #eb._scOrigPoints > 0 and not inCombat and eb.ClearAllPoints then
                        pcall(eb.ClearAllPoints, eb)
                        for _, pt in ipairs(eb._scOrigPoints) do
                            if pt[1] then pcall(eb.SetPoint, eb, pt[1], pt[2], pt[3], pt[4], pt[5]) end
                        end
                    end
                    if eb._scOrigStrata and not inCombat and eb.SetFrameStrata then
                        pcall(eb.SetFrameStrata, eb, eb._scOrigStrata)
                    end
                end
                SetOfficialSurfaceFrameHidden(eb, false, allowMouse)
            elseif eb.HasFocus and eb:HasFocus() then
                QuickReply:ShowActiveOfficialEditBox(eb)
            elseif eb == _G.ChatFrame1EditBox and QuickReply.frame and QuickReply.frame:IsShown() and QuickReply.IsOfficialOnlyThread and QuickReply:IsOfficialOnlyThread() then
                QuickReply:DockOfficialEditBox(eb, false)
            elseif eb._scDockedToQr or eb._scPreDockedToQr
                or (eb._scDockedSkin and eb._scDockedSkin:IsShown())
                or (eb.IsShown and eb:IsShown())
                or ((eb.GetAlpha and eb:GetAlpha() or 0) > 0.005)
            then
                QuickReply:HideTemporaryOfficialEditBox(eb)
            end
            if not eb._scExclHooked and eb.HookScript then
                eb._scExclHooked = true
                eb:HookScript("OnEnter", function(selfEb)
                    if selfEb._scDockedToQr then
                        if QuickReply.InvalidateFocusVisuals then QuickReply:InvalidateFocusVisuals() end
                        QuickReply:UpdateFocusVisuals()
                    end
                end)
                eb:HookScript("OnLeave", function(selfEb)
                    if selfEb._scDockedToQr then
                        if QuickReply.InvalidateFocusVisuals then QuickReply:InvalidateFocusVisuals() end
                        QuickReply:UpdateFocusVisuals()
                    end
                end)
                eb:HookScript("OnTextChanged", function(selfEb)
                    if selfEb._scDockedToQr or (selfEb.HasFocus and selfEb:HasFocus()) then
                        local nowT = (GetTime and GetTime()) or 0
                        QuickReply.interactedOutside = false
                        QuickReply.lastInputAt = nowT
                        QuickReply._lastOpaqueActivityAt = nowT
                        QuickReply.idleCountdown = nil
                    end
                end)
                eb:HookScript("OnKeyDown", function(selfEb, key)
                    if (selfEb._scDockedToQr or (selfEb.HasFocus and selfEb:HasFocus())) and key ~= "ESCAPE" then
                        local nowT = (GetTime and GetTime()) or 0
                        QuickReply.interactedOutside = false
                        QuickReply.lastInputAt = nowT
                        QuickReply._lastOpaqueActivityAt = nowT
                        QuickReply.idleCountdown = nil
                        if key == "W" and IsControlKeyDown and IsControlKeyDown()
                            and (not (IsShiftKeyDown and IsShiftKeyDown()))
                            and (not (IsAltKeyDown and IsAltKeyDown()))
                            and QuickReply.CloseActiveUnpinnedTabByCtrlW
                        then
                            QuickReply:CloseActiveUnpinnedTabByCtrlW()
                        end
                    end
                end)
                eb:HookScript("OnMouseDown", function(selfEb)
                    if not (Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode()) then
                        return
                    end
                    if not (QuickReply.frame and QuickReply.frame:IsShown() and QuickReply.IsOfficialOnlyThread and QuickReply:IsOfficialOnlyThread()) then
                        return
                    end
                    local nowT = (GetTime and GetTime()) or 0
                    QuickReply.interactedOutside = false
                    QuickReply.lastInputAt = nowT
                    QuickReply._lastOpaqueActivityAt = nowT
                    QuickReply.idleCountdown = nil
                    if (selfEb.HasFocus and selfEb:HasFocus()) or (InCombatLockdown and InCombatLockdown()) then
                        return
                    end
                    local gTarget = (ns.Chat and ns.Chat.GetGeneralTargetInfo) and ns.Chat:GetGeneralTargetInfo() or nil
                    local wantType = (gTarget and gTarget.channelId and "CHANNEL")
                        or (gTarget and gTarget.isYell and "YELL")
                        or "SAY"
                    local curType = (selfEb.GetChatType and selfEb:GetChatType())
                        or (selfEb.GetAttribute and selfEb:GetAttribute("chatType"))
                        or nil
                    local curChan = (selfEb.GetChannelTarget and selfEb:GetChannelTarget())
                        or (selfEb.GetAttribute and selfEb:GetAttribute("channelTarget"))
                        or nil
                    local headerObj = selfEb.header or (selfEb.GetName and selfEb:GetName() and _G[selfEb:GetName() .. "Header"]) or nil
                    local hdrTxt = (headerObj and headerObj.GetText and ns.Safe and ns.Safe.String(headerObj:GetText())) or ""
                    local mismatch = (curType ~= wantType)
                        or (wantType == "CHANNEL" and tonumber(curChan) ~= tonumber(gTarget and gTarget.channelId))
                        or (hdrTxt == "")
                    if mismatch then
                        QuickReply:ActivateDockedOfficialInput()
                    end
                end)
                eb:HookScript("OnEditFocusGained", function(selfEb)
                    if Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode() then
                        if selfEb == _G.ChatFrame1EditBox and QuickReply.frame and QuickReply.frame:IsShown() then
                            local nowT = (GetTime and GetTime()) or 0
                            QuickReply._dockedOfficialInputActive = true
                            QuickReply._allowTempOfficialEditUntil = nowT + 120
                            QuickReply.interactedOutside = false
                            QuickReply.lastInputAt = nowT
                            QuickReply._lastOpaqueActivityAt = nowT
                            QuickReply.idleCountdown = nil
                            if QuickReply.ElevateToForeground then
                                QuickReply:ElevateToForeground()
                            end
                            QuickReply:ShowActiveOfficialEditBox(selfEb)
                            if QuickReply.ApplyCombatFadeStep then
                                QuickReply:ApplyCombatFadeStep(0, true)
                            end
                            if QuickReply.UpdateFocusVisuals then
                                QuickReply:UpdateFocusVisuals()
                            end
                            if QuickReply.WakeOnUpdate then
                                QuickReply:WakeOnUpdate()
                            end
                        end
                        if QuickReply.SyncEnterBinding then
                            QuickReply:SyncEnterBinding()
                        end
                        if QuickReply.SyncQuickReplyHotkeys then
                            QuickReply:SyncQuickReplyHotkeys()
                        end
                    end
                end)
                eb:HookScript("OnEditFocusLost", function(selfEb)
                    if not QuickReply._redirectingBlizzCombatChat then
                        QuickReply._allowTempOfficialEditUntil = nil
                    end
                    if Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode() then
                        local nowT = (GetTime and GetTime()) or 0
                        if not QuickReply.interactedOutside then
                            QuickReply.lastInputAt = nowT
                        end
                        QuickReply._lastOpaqueActivityAt = nowT
                        QuickReply._dockedOfficialInputActive = false
                        QuickReply._dockedOfficialFallbackHint = false
                        if not QuickReply._redirectingBlizzCombatChat then
                            QuickReply._allowTempOfficialEditUntil = nil
                        end
                        if QuickReply.frame and QuickReply.frame.statusText and QuickReply.lastStatusState ~= "combat_blocked" then
                            QuickReply.frame.statusText:SetText("")
                        end
                        local stayDocked = (selfEb == _G.ChatFrame1EditBox)
                            and QuickReply.frame and QuickReply.frame:IsShown()
                            and QuickReply.IsOfficialOnlyThread and QuickReply:IsOfficialOnlyThread()
                        if stayDocked then
                            QuickReply._refocusInputAfterBlizzSend = false
                            QuickReply:DockOfficialEditBox(selfEb, false)
                            if C_Timer and C_Timer.After and not QuickReply._ebFocusLostStayQueued then
                                QuickReply._ebFocusLostStayQueued = true
                                QuickReply._ebFocusLostTarget = selfEb
                                if not QuickReply._ebFocusLostStayFn then
                                    QuickReply._ebFocusLostStayFn = function()
                                        QuickReply._ebFocusLostStayQueued = false
                                        local tEb = QuickReply._ebFocusLostTarget
                                        if tEb and QuickReply.frame and QuickReply.frame:IsShown()
                                            and QuickReply.IsOfficialOnlyThread and QuickReply:IsOfficialOnlyThread()
                                            and not (tEb.HasFocus and tEb:HasFocus())
                                        then
                                            QuickReply:DockOfficialEditBox(tEb, false)
                                        end
                                        if QuickReply.ApplyCombatFadeStep then
                                            QuickReply:ApplyCombatFadeStep(0.016, false)
                                        end
                                        if QuickReply.UpdateFocusVisuals then
                                            QuickReply:UpdateFocusVisuals()
                                        end
                                        if QuickReply.SyncEnterBinding then
                                            QuickReply:SyncEnterBinding()
                                        end
                                        if QuickReply.SyncQuickReplyHotkeys then
                                            QuickReply:SyncQuickReplyHotkeys()
                                        end
                                    end
                                end
                                C_Timer.After(0, QuickReply._ebFocusLostStayFn)
                            end
                        else
                            QuickReply._refocusInputAfterBlizzSend = false
                            QuickReply:HideTemporaryOfficialEditBox(selfEb)
                            if QuickReply.UpdateFocusVisuals then
                                QuickReply:UpdateFocusVisuals()
                            end
                            if QuickReply.SyncEnterBinding then
                                QuickReply:SyncEnterBinding()
                            end
                            if C_Timer and C_Timer.After and not QuickReply._ebFocusLostHideQueued then
                                QuickReply._ebFocusLostHideQueued = true
                                if not QuickReply._ebFocusLostHideFn then
                                    QuickReply._ebFocusLostHideFn = function()
                                        QuickReply._ebFocusLostHideQueued = false
                                        if QuickReply.UpdateFocusVisuals then
                                            QuickReply:UpdateFocusVisuals()
                                        end
                                        if QuickReply.SyncEnterBinding then
                                            QuickReply:SyncEnterBinding()
                                        end
                                    end
                                end
                                C_Timer.After(0, QuickReply._ebFocusLostHideFn)
                            end
                        end
                    end
                end)
                eb:HookScript("OnHide", function(selfEb)
                    if QuickReply._hidingDockedOfficial then
                        return
                    end
                    if selfEb == _G.ChatFrame1EditBox
                        and Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode()
                        and Compat.IsAddonChatMode and Compat.IsAddonChatMode()
                        and QuickReply.frame and QuickReply.frame:IsShown()
                        and QuickReply.IsOfficialOnlyThread and QuickReply:IsOfficialOnlyThread()
                        and not (InCombatLockdown and InCombatLockdown())
                        and C_Timer and C_Timer.After
                    then
                        local nowT = (GetTime and GetTime()) or 0
                        if (nowT - (QuickReply._ebRedockWindowAt or 0)) > 1.0 then
                            QuickReply._ebRedockWindowAt = nowT
                            QuickReply._ebRedockCount = 0
                        end
                        QuickReply._ebRedockCount = (QuickReply._ebRedockCount or 0) + 1
                        if QuickReply._ebRedockCount > 6 or QuickReply._ebRedockQueued then
                            return
                        end
                        QuickReply._ebRedockQueued = true
                        QuickReply._ebRedockTarget = selfEb
                        if not QuickReply._ebRedockFn then
                            QuickReply._ebRedockFn = function()
                                QuickReply._ebRedockQueued = false
                                local tEb = QuickReply._ebRedockTarget
                                if tEb and not QuickReply._hidingDockedOfficial
                                    and QuickReply.frame and QuickReply.frame:IsShown()
                                    and QuickReply.IsOfficialOnlyThread and QuickReply:IsOfficialOnlyThread()
                                    and not (InCombatLockdown and InCombatLockdown())
                                then
                                    QuickReply:DockOfficialEditBox(tEb, tEb.HasFocus and tEb:HasFocus() == true)
                                end
                            end
                        end
                        C_Timer.After(0, QuickReply._ebRedockFn)
                    end
                end)
            end
        end
    end

    if not self._exclusiveOfficialHooks then
        self._exclusiveOfficialHooks = true
        local function RunEnforceLater()
            MinimapBtn._exclusiveEnforceQueued = false
            if Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode() then
                MinimapBtn:ApplyExclusiveChatMode()
            end
        end
        local function EnforceLater()
            if C_Timer and C_Timer.After then
                if MinimapBtn._exclusiveEnforceQueued then return end
                MinimapBtn._exclusiveEnforceQueued = true
                C_Timer.After(0, RunEnforceLater)
            end
        end
        if hooksecurefunc then
            if type(_G.FCF_FadeInChatFrame) == "function" then
                hooksecurefunc("FCF_FadeInChatFrame", function(cf)
                    if Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode() then
                        SetOfficialSurfaceFrameHidden(cf, true, not (InCombatLockdown and InCombatLockdown()))
                    end
                end)
            end
            if type(_G.FCFDock_UpdateTabs) == "function" then
                hooksecurefunc("FCFDock_UpdateTabs", EnforceLater)
            end
            if type(_G.FCF_OpenTemporaryWindow) == "function" then
                hooksecurefunc("FCF_OpenTemporaryWindow", EnforceLater)
            end
        end
        if _G.GeneralDockManager and _G.GeneralDockManager.HookScript then
            _G.GeneralDockManager:HookScript("OnShow", EnforceLater)
        end
        if _G.QuickJoinToastButton and _G.QuickJoinToastButton.HookScript then
            _G.QuickJoinToastButton:HookScript("OnShow", EnforceLater)
        end
    end

    if hideOfficial == false then
        if QuickReply then
            if QuickReply.HideWhispersDropdown then QuickReply:HideWhispersDropdown() end
            if QuickReply.frame and QuickReply.frame:IsShown() then
                QuickReply._manualClosePending = true
                QuickReply.frame:Hide()
            end
            if QuickReply._combatLogFrame and QuickReply._combatLogFrame:IsShown() then
                QuickReply._combatLogFrame:Hide()
            end
        end
    end
    if QuickReply and QuickReply.SyncEnterBinding then
        QuickReply:SyncEnterBinding()
    end
end

function MinimapBtn:SetChatUiMode(mode, silentPrint)
    if not (ns.db and ns.db.settings) then return end
    local targetMode = (mode == "official") and "official" or "addon"
    ns.db.settings.chatUiMode = targetMode
    if SocialCentralDB and SocialCentralDB.settings then
        SocialCentralDB.settings.chatUiMode = targetMode
    end
    if SocialCentralCharDB and SocialCentralCharDB.settings then
        SocialCentralCharDB.settings.chatUiMode = targetMode
    end
    self:ApplyExclusiveChatMode()
    if targetMode == "official" then
        if ns.UI and ns.UI.IsChatTabVisible and ns.UI:IsChatTabVisible() then
            if ns.UI.ShowHub then
                ns.UI:ShowHub("watchlist")
            elseif ns.UI.OpenTab then
                ns.UI:OpenTab("watchlist")
            end
        end
        if not silentPrint then
            ns:Print("%s", L["Switched to Official WoW Chat (SocialCentral Chat disabled)."])
        end
    else
        if QuickReply and not (InCombatLockdown and InCombatLockdown()) then
            QuickReply._closedManuallyPersistent = false
            if QuickReply.OpenPreviewOrLatest then
                if not QuickReply:OpenPreviewOrLatest() and QuickReply.OpenThread then
                    QuickReply:OpenThread("ch:general", false)
                end
            elseif QuickReply.OpenThread then
                QuickReply:OpenThread("ch:general", false)
            end
        end
        if not silentPrint then
            ns:Print("%s", L["Switched to SocialCentral Chat (Official WoW Chat hidden)."])
        end
    end
    self:Update()
    ns:Emit("SETTINGS_UPDATED")
    ns:Emit("CHAT_UPDATED")
    if ns.Settings and ns.Settings.Refresh then
        ns.Settings:Refresh()
    end
    if ns.UI and ns.UI.QueueRefresh then
        ns.UI:QueueRefresh(true)
    end
end

function MinimapBtn:ShowChatModePrompt(forceShow)
    if (not forceShow) and Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        self._pendingChatModePrompt = true
        return
    end
    self._pendingChatModePrompt = false
    local Theme = ns.Theme
    if not Theme then return end
    if not self._chatModePromptFrame then
        local mf = CreateFrame("Frame", "SocialCentralChatModePrompt", UIParent, "BackdropTemplate")
        mf:Hide()
        mf:SetSize(460, 224)
        mf:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        mf:SetClampedToScreen(true)
        Theme:PrepareTopOverlayModal(mf, 860)

        local hdr = CreateFrame("Frame", nil, mf)
        hdr:SetPoint("TOPLEFT", 12, -10)
        hdr:SetPoint("TOPRIGHT", -12, -10)
        hdr:SetHeight(24)

        local hIco = hdr:CreateTexture(nil, "ARTWORK")
        hIco:SetSize(16, 16)
        hIco:SetPoint("LEFT", hdr, "LEFT", 0, 0)
        hIco:SetTexture(ICON_TEX)

        local helpBtn = Theme:CreateHelpButton(
            hdr,
            L["Help: Exclusive Chat Mode"],
            L["Forces an exclusive choice between SocialCentral Chat (Quick Reply & Conversations, hiding Blizzard Official Chat) or Official WoW Chat (hiding and disabling all addon chat)."],
            L["Right-click the Minimap or chat emblem icon at any time to switch modes instantly without reloading."],
            16
        )
        helpBtn:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)

        local titleFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleFs:SetPoint("LEFT", hIco, "RIGHT", 6, 0)
        titleFs:SetPoint("RIGHT", helpBtn, "LEFT", -6, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        titleFs:SetText("SocialCentral — " .. L["Choose Your Chat Mode"])

        Theme:MakeMovable(mf, { key = "chat_mode_prompt", skipAutoRestore = true, handles = { hdr, mf } })
        Theme:ApplyBackdrop(mf, "window", Theme:GetPalette())

        local introFs = mf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        introFs:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 2, -6)
        introFs:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", -2, -6)
        introFs:SetJustifyH("LEFT")
        introFs:SetWordWrap(true)
        introFs:SetText(L["Choose between SocialCentral Chat or Blizzard Official Chat. Only one stays active at a time — choosing one hides and disables the other."])

        local leftCard = CreateFrame("Frame", nil, mf, "BackdropTemplate")
        leftCard:SetPoint("TOPLEFT", introFs, "BOTTOMLEFT", 0, -10)
        leftCard:SetSize(210, 114)
        Theme:ApplyBackdrop(leftCard, "inset")
        local lDesc = leftCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lDesc:SetPoint("TOPLEFT", 8, -8)
        lDesc:SetPoint("TOPRIGHT", -8, -8)
        lDesc:SetJustifyH("LEFT")
        lDesc:SetWordWrap(true)
        lDesc:SetText(L["Replaces Blizzard Chat with SocialCentral's unified General tab, Party/Guild tabs, Whisper drawer, and Log Viewer. Official Chat is hidden."])
        local btnAddon = Theme:CreateButton(leftCard, 192, 24, L["Use SocialCentral Chat"], "primary")
        Theme:AutoFitButton(btnAddon, 150, 14, 196)
        btnAddon:SetPoint("BOTTOM", leftCard, "BOTTOM", 0, 8)
        btnAddon:SetScript("OnClick", function()
            mf:Hide()
            MinimapBtn:SetChatUiMode("addon")
        end)

        local rightCard = CreateFrame("Frame", nil, mf, "BackdropTemplate")
        rightCard:SetPoint("TOPRIGHT", introFs, "BOTTOMRIGHT", 0, -10)
        rightCard:SetSize(210, 114)
        Theme:ApplyBackdrop(rightCard, "inset")
        local rDesc = rightCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rDesc:SetPoint("TOPLEFT", 8, -8)
        rDesc:SetPoint("TOPRIGHT", -8, -8)
        rDesc:SetJustifyH("LEFT")
        rDesc:SetWordWrap(true)
        rDesc:SetText(L["Keeps standard WoW Chat and hides/disables all addon chat. Clicking the SocialCentral icon opens the Main Window directly."])
        local btnOfficial = Theme:CreateButton(rightCard, 192, 24, L["Use Official WoW Chat"], "default")
        Theme:AutoFitButton(btnOfficial, 150, 14, 196)
        btnOfficial:SetPoint("BOTTOM", rightCard, "BOTTOM", 0, 8)
        btnOfficial:SetScript("OnClick", function()
            mf:Hide()
            MinimapBtn:SetChatUiMode("official")
        end)

        local footFs = mf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        footFs:SetPoint("BOTTOMLEFT", mf, "BOTTOMLEFT", 14, 10)
        footFs:SetPoint("BOTTOMRIGHT", mf, "BOTTOMRIGHT", -14, 10)
        footFs:SetJustifyH("CENTER")
        footFs:SetWordWrap(true)
        footFs:SetText(L["You can switch modes anytime by right-clicking the Minimap icon or in Settings."])

        mf._leftCard = leftCard
        mf._rightCard = rightCard
        mf._btnAddon = btnAddon
        mf._btnOfficial = btnOfficial
        mf._helpBtn = helpBtn
        self._chatModePromptFrame = mf
    end
    local pFrame = self._chatModePromptFrame
    Theme:PrepareTopOverlayModal(pFrame, 860)
    local p = Theme:GetPalette()
    if pFrame._solidOpaqueBg and p then
        local bg = p.windowBg or { 0.08, 0.08, 0.09, 1.0 }
        pFrame._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
    end
    Theme:ApplyBackdrop(pFrame, "window", p)
    if pFrame._leftCard then Theme:ApplyBackdrop(pFrame._leftCard, "inset", p) end
    if pFrame._rightCard then Theme:ApplyBackdrop(pFrame._rightCard, "inset", p) end
    if pFrame._btnAddon then Theme:StyleButton(pFrame._btnAddon, "primary") end
    if pFrame._btnOfficial then Theme:StyleButton(pFrame._btnOfficial, "default") end
    if pFrame._helpBtn and pFrame._helpBtn.RefreshTheme then pFrame._helpBtn:RefreshTheme() end
    if Theme.SyncSubtreeLayers then Theme:SyncSubtreeLayers(pFrame, 8) end
    pFrame:ClearAllPoints()
    pFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    pFrame:Show()
    if pFrame.Raise then pFrame:Raise() end
end

function MinimapBtn:MaybeShowChatModePrompt()
    if Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() then
        self:ApplyExclusiveChatMode()
        return
    end
    self:ShowChatModePrompt(false)
end

function MinimapBtn:SetTestBadgeCount(count, tone)
    local n = math.floor(tonumber(count) or 0)
    if n <= 0 then
        BadgeCluster.testCounts = nil
        wipe(BadgeCluster.previewCounts)
        wipe(BadgeCluster.testPreviewCounts)
    else
        local cleanTone = type(tone) == "string" and tone:lower() or "whisper"
        if cleanTone == "alert" or cleanTone == "direct" then cleanTone = "whisper" end
        if cleanTone == "party" then cleanTone = "group" end
        if cleanTone ~= "whisper" and cleanTone ~= "group" and cleanTone ~= "raid" and cleanTone ~= "guild" and cleanTone ~= "bnet" and cleanTone ~= "room" then
            cleanTone = "whisper"
        end
        BadgeCluster.testCounts = { [cleanTone] = n }
    end
    UpdateBadge(false)
end

function MinimapBtn:SetTestBadgeMix(mixTable)
    if type(mixTable) ~= "table" then
        BadgeCluster.testCounts = nil
        wipe(BadgeCluster.previewCounts)
        wipe(BadgeCluster.testPreviewCounts)
        UpdateBadge(false)
        return
    end
    BadgeCluster.testCounts = {}
    for _, cat in ipairs(BADGE_CATEGORY_ORDER) do
        local v = math.floor(tonumber(mixTable[cat]) or 0)
        if v > 0 then
            BadgeCluster.testCounts[cat] = v
        end
    end
    UpdateBadge(true)
end

function MinimapBtn:NotePreviewFolded(item)
    if type(item) ~= "table" then return end
    local catRaw = item.category or item.channelKind or "WHISPER"
    local chKindRaw = item.channelKind or catRaw
    local cat
    if catRaw == "BN_WHISPER" or chKindRaw == "BN_WHISPER" then
        cat = "bnet"
    elseif catRaw == "GUILD" or chKindRaw == "GUILD" or chKindRaw == "OFFICER" then
        cat = "guild"
    elseif chKindRaw == "RAID" or catRaw == "RAID" then
        cat = "raid"
    elseif catRaw == "GROUP" or chKindRaw == "PARTY" or chKindRaw == "INSTANCE_CHAT" then
        cat = "group"
    elseif catRaw == "ROOM" or chKindRaw == "ROOM" or chKindRaw == "ALLIANCE" then
        cat = "room"
    else
        cat = "whisper"
    end
    if item.isTestPreview or item.id and tostring(item.id):sub(1, 8) == "test:mp:" then
        BadgeCluster.testPreviewCounts[cat] = (BadgeCluster.testPreviewCounts[cat] or 0) + 1
        UpdateBadge(true)
    elseif cat == "group" or cat == "raid" or cat == "guild" then
        local s = ns.db and ns.db.settings
        local mirroredTracked = s and s.chatMirrorChannels == true and s.chatChannelUnread == true
        local qrOn = s and s.quickReplyEnabled ~= false
        local qrKind = item.channelKind or ((cat == "guild") and "GUILD" or ((cat == "raid") and "RAID" or "PARTY"))
        local qrTracked = qrOn and ns.Chat and ns.Chat.IsQuickReplyKindEnabled and ns.Chat:IsQuickReplyKindEnabled(qrKind)
        if not mirroredTracked and not qrTracked then
            local tKey = item.threadKey or item.channelKey
            if tKey and tKey ~= "" then
                local rec = BadgeCluster.previewCountsByThread[tKey]
                if not rec then
                    rec = { cat = cat, count = 0 }
                    BadgeCluster.previewCountsByThread[tKey] = rec
                end
                rec.count = (rec.count or 0) + 1
                BadgeCluster.lastPreviewThreadKey = tKey
            else
                BadgeCluster.previewCounts[cat] = (BadgeCluster.previewCounts[cat] or 0) + 1
            end
            UpdateBadge(true)
        end
    elseif not item.isTestPreview then
        local tKey = item.threadKey or item.channelKey
        if tKey and tKey ~= "" and tKey ~= "ch:general" and tKey ~= "mentions:radar" and tKey ~= "notes:self" then
            BadgeCluster.lastPreviewThreadKey = tKey
        end
    end
end

function MinimapBtn:ClearPreviewCountsForThread(threadKey, channelKey, kind)
    local changed = false
    if threadKey and BadgeCluster.previewCountsByThread[threadKey] then
        BadgeCluster.previewCountsByThread[threadKey] = nil
        changed = true
    end
    if channelKey and BadgeCluster.previewCountsByThread[channelKey] then
        BadgeCluster.previewCountsByThread[channelKey] = nil
        changed = true
    end
    local cat
    if kind == "BN_WHISPER" then
        cat = "bnet"
    elseif kind == "GUILD" or kind == "OFFICER" then
        cat = "guild"
    elseif kind == "RAID" then
        cat = "raid"
    elseif kind == "GROUP" or kind == "PARTY" or kind == "INSTANCE_CHAT" then
        cat = "group"
    elseif kind == "ROOM" or kind == "ALLIANCE" then
        cat = "room"
    elseif kind == "WHISPER" then
        cat = "whisper"
    end
    if cat and not BadgeCluster.testCounts then
        if (BadgeCluster.previewCounts[cat] or 0) > 0 then
            BadgeCluster.previewCounts[cat] = nil
            changed = true
        end
        if (BadgeCluster.testPreviewCounts[cat] or 0) > 0 then
            BadgeCluster.testPreviewCounts[cat] = nil
            changed = true
        end
    end
    if changed then
        UpdateBadge(false)
    end
end

function MinimapBtn:ClearPreviewCountsForCategory(category)
    local cat
    if category == "BN_WHISPER" then
        cat = "bnet"
    elseif category == "GUILD" or category == "OFFICER" then
        cat = "guild"
    elseif category == "RAID" then
        cat = "raid"
    elseif category == "GROUP" or category == "PARTY" or category == "INSTANCE_CHAT" then
        cat = "group"
    elseif category == "ROOM" or category == "ALLIANCE" then
        cat = "room"
    elseif category == "WHISPER" then
        cat = "whisper"
    end
    if not cat then return end
    local changed = false
    if (BadgeCluster.previewCounts[cat] or 0) > 0 then
        BadgeCluster.previewCounts[cat] = nil
        changed = true
    end
    if (BadgeCluster.testPreviewCounts[cat] or 0) > 0 then
        BadgeCluster.testPreviewCounts[cat] = nil
        changed = true
    end
    for k, rec in pairs(BadgeCluster.previewCountsByThread) do
        if type(rec) == "table" and rec.cat == cat then
            BadgeCluster.previewCountsByThread[k] = nil
            changed = true
        end
    end
    if changed then
        UpdateBadge(false)
    end
end

function MinimapBtn:ClearPreviewCounts()
    if BadgeCluster:ClearSessionPreviewCounts() then
        BadgeCluster.testCounts = nil
        UpdateBadge(false)
    end
end

ns:On("CHAT_THREAD_READ", function(info)
    if type(info) == "table" then
        MinimapBtn:ClearPreviewCountsForThread(info.threadKey, info.channelKey, info.kind)
    elseif type(info) == "string" then
        MinimapBtn:ClearPreviewCountsForThread(info, info, nil)
    end
    UpdateBadge(false)
end)

for _, ev in ipairs({ "CHAT_UPDATED", "CLAN_UPDATED", "SETTINGS_UPDATED", "ADDON_MESSAGE_NOTIFY" }) do
    ns:On(ev, UpdateBadge)
end
ns:On("SPOTTER_UPDATED", function()
    if (BadgeCluster.totalCount or 0) == 0 then
        UpdateBadge()
    end
end)

-- ============================================================================
-- Minimap Message Preview Capsule & First-Time Interactive Setup Prompt
-- ============================================================================
-- Displays a compact, 100%-opaque animated preview pill vertically centered on
-- the left side of the Minimap showing the sender's character icon and opening
-- words, then smoothly closes and glides back into the SC minimap icon.
-- Zero taint, 0ms idle CPU (OnUpdate detached whenever idle).
do
    local mpInit = {
        driverFrame = nil,
        framePool = {},
        activeSlots = {}, -- ordered top (oldest) -> bottom (newest), up to msgPreviewMaxVisible (1..3)
        setupModal = nil,
        anchorMover = nil,
        draggingStack = false,
        dragOffX = 0,
        dragOffY = 0,
        dragCenterX = nil,
        dragCenterY = nil,
        queue = {},
        combatHeldQueue = {},
        sideMode = "LEFT", -- "LEFT" (flush right edge) | "RIGHT" (flush left edge)
        pendingPromptItem = nil,
        sessionPromptDismissed = false,
        testCounter = 0,
        loginAt = (GetTime and GetTime()) or 0,
        initialized = false,
    }
    for k, v in pairs(mpInit) do
        MsgPreview[k] = v
    end
end

local MP_POS_KEY = "minimap_msg_preview"

local MP_WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local MP_PORTRAIT_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local MP_CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local MP_BNET_TEX = "Interface\\ChatFrame\\UI-ChatIcon-BattleNet"
local MP_MAIL_TEX = "Interface\\AddOns\\SocialCentral\\Media\\toast-mail"
local MP_PARTY_TEX = "Interface\\AddOns\\SocialCentral\\Media\\toast-party"
local MP_GLOW_TEX = "Interface\\AddOns\\SocialCentral\\Media\\toast-glow"

local MP_COLLAPSED_W = 36
local MP_COLLAPSED_H = 36
local MP_MIN_W = 214
local MP_MAX_W = 304
local MP_HEIGHT = 58
local MP_SLOT_GAP = 8
local MP_SLOT_PITCH = MP_HEIGHT + MP_SLOT_GAP
local MP_MAX_SLOTS_CAP = 3
local MP_REST_GAP = 30
local MP_EXPAND_DUR = 0.28
local MP_COLLAPSE_DUR = 0.34
local MP_MAX_QUEUE = 12
local MP_LOGIN_GRACE = 6.0

local MP_CHANNEL_RGB = {
    WHISPER       = { 1.00, 0.50, 1.00 },
    DIRECT        = { 1.00, 0.50, 1.00 },
    BN_WHISPER    = { 0.10, 0.82, 1.00 },
    PARTY         = { 0.48, 0.68, 1.00 },
    GROUP         = { 0.48, 0.68, 1.00 },
    RAID          = { 1.00, 0.54, 0.18 },
    INSTANCE_CHAT = { 1.00, 0.54, 0.18 },
    GUILD         = { 0.28, 0.94, 0.40 },
    OFFICER       = { 0.28, 0.94, 0.40 },
    ROOM          = { 0.74, 0.50, 1.00 },
    ALLIANCE      = { 0.74, 0.50, 1.00 },
}

local MP_RACE_ATLAS_SLUG = {
    Human = "human",
    Dwarf = "dwarf",
    NightElf = "nightelf",
    Gnome = "gnome",
    Draenei = "draenei",
    Orc = "orc",
    Scourge = "undead",
    Undead = "undead",
    Tauren = "tauren",
    Troll = "troll",
    BloodElf = "bloodelf",
    HighElf = "highelf",
    Goblin = "goblin",
}

local function MpClamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function MpEaseOutCubic(t)
    local inv = 1 - MpClamp(t, 0, 1)
    return 1 - (inv * inv * inv)
end

local function MpEaseInOutCubic(t)
    local p = MpClamp(t, 0, 1)
    if p < 0.5 then
        return 4 * p * p * p
    end
    local f = -2 * p + 2
    return 1 - ((f * f * f) * 0.5)
end

local function MpApplyCircleMask(parent, tex, size)
    if not (parent and parent.CreateMaskTexture and tex) then return end
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(MP_PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(size, size)
    mask:SetPoint("CENTER", tex, "CENTER", 0, 0)
    tex:AddMaskTexture(mask)
end

local function MpApplyGradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    if not tex then return end
    if ns.Theme and ns.Theme.ApplySafeGradient then
        ns.Theme:ApplySafeGradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    else
        tex:SetColorTexture((r1 + r2) * 0.5, (g1 + g2) * 0.5, (b1 + b2) * 0.5, (a1 + a2) * 0.5)
    end
end

local function MpSafeUtf8Truncate(str, maxBytes)
    if type(str) ~= "string" or #str <= maxBytes then
        return str or ""
    end
    local cut = maxBytes
    while cut > 1 do
        local nextB = str:byte(cut + 1)
        if nextB and nextB >= 128 and nextB < 192 then
            cut = cut - 1
        else
            break
        end
    end
    local slice = str:sub(1, cut)
    local wordCut = slice:match("^(.*)%s+%S*$")
    if wordCut and #wordCut >= math.floor(maxBytes * 0.55) then
        slice = wordCut
    end
    return slice .. "..."
end

local function MpCleanPreviewText(rawText)
    if ns.Safe and ns.Safe.IsSecret and ns.Safe.IsSecret(rawText) then
        return "", ""
    end
    local s = tostring(rawText or "")
    -- Preserve readable hyperlink labels (e.g. [Thunderfury]) while removing raw escape sequences
    s = s:gsub("|c%x%x%x%x%x%x%x%x|H.-|h(.-)|h|r", "%1")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|A.-|a", "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("[%c]+", " ")
    s = s:gsub("%s+", " ")
    s = s:match("^%s*(.-)%s*$") or ""
    local fullClean = MpSafeUtf8Truncate(s, 240)
    local snippet = MpSafeUtf8Truncate(s, 72)
    return snippet, fullClean
end

local function MpChannelLabel(item)
    if not item then return L["Whisper"] end
    local ck = item.channelKind or item.category
    if ck == "BN_WHISPER" then return "Battle.net"
    elseif ck == "DIRECT" then return L["Direct Addon"]
    elseif ck == "WHISPER" then return L["Whisper"]
    elseif ck == "PARTY" then return L["Party"]
    elseif ck == "RAID" then return L["Raid"]
    elseif ck == "INSTANCE_CHAT" then return L["Instance"]
    elseif ck == "GUILD" then return L["Guild"]
    elseif ck == "OFFICER" then return L["Officer"]
    elseif ck == "ALLIANCE" then return L["Alliance"]
    elseif ck == "ROOM" then
        if Compat and Compat.IsStreamerMode and Compat.IsStreamerMode() then
            return L["Private Room"]
        end
        return (item.roomTitle and item.roomTitle ~= "") and item.roomTitle or L["Private Room"]
    end
    return L["Whisper"]
end

local function MpChannelRGB(item)
    local ck = item and (item.channelKind or item.category) or "WHISPER"
    return MP_CHANNEL_RGB[ck] or MP_CHANNEL_RGB.WHISPER
end

local function MpCoalesceKey(item)
    if not item then return "" end
    if item.threadKey and item.threadKey ~= "" then
        return item.threadKey .. "|" .. tostring(item.sender or "")
    end
    return tostring(item.category or "MSG") .. "|" .. tostring(item.sender or "")
end

local function MpIsInCombat()
    return ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) == true
end

local function MpGetHoldDuration()
    local s = ns.db and ns.db.settings
    local d = (s and ns.Safe and ns.Safe.Number(s.msgPreviewDuration)) or 6
    return MpClamp(d, 3, 12)
end

local function MpGetMaxVisible()
    local s = ns.db and ns.db.settings
    local m = (s and ns.Safe and ns.Safe.Number(s.msgPreviewMaxVisible)) or 3
    return MpClamp(math.floor(m + 0.5), 1, MP_MAX_SLOTS_CAP)
end

local function MpDesiredSlotOffsetY(slotIdx, totalSlots)
    return (((totalSlots + 1) * 0.5) - slotIdx) * MP_SLOT_PITCH
end

local function MpEnqueueCombatHold(item)
    if type(item) ~= "table" or item.isTestPreview then return end
    local cKey = MpCoalesceKey(item)
    for _, held in ipairs(MsgPreview.combatHeldQueue) do
        if MpCoalesceKey(held) == cKey then
            held.text = item.text or held.text
            held._snippet = item._snippet
            held._fullClean = item._fullClean
            held.sender = item.sender or held.sender
            held.senderClass = item.senderClass or held.senderClass
            held.coalescedCount = (held.coalescedCount or 1) + (item.coalescedCount or 1)
            return
        end
    end
    local copy = {}
    for k, v in pairs(item) do
        copy[k] = v
    end
    copy.coalescedCount = (type(item.coalescedCount) == "number" and item.coalescedCount > 1) and item.coalescedCount or 1
    table.insert(MsgPreview.combatHeldQueue, copy)
    while #MsgPreview.combatHeldQueue > MP_MAX_QUEUE do
        table.remove(MsgPreview.combatHeldQueue, 1)
    end
end

local function MpShouldSilenceForContext(item)
    local s = ns.db and ns.db.settings
    if not s then return true end
    if Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("chat") then
        return true
    end
    if s.msgPreviewSilenceCombat ~= false and MpIsInCombat() then
        return true
    end
    local senderRef = item and (item.lookupKey or item.senderCharName or item.sender) or nil
    local bnId = item and item.bnetAccountID or nil
    local isFav = item and Compat and Compat.IsSenderFavorite and s.focusAllowFavorites ~= false and Compat.IsSenderFavorite(senderRef, bnId)
    if isFav then
        return false
    end
    if Compat and Compat.IsFocusSilenced and Compat.IsFocusSilenced(senderRef, bnId) then
        return true
    end
    if IsInInstance then
        local ok, inInst, instType = pcall(IsInInstance)
        if ok and ns.Safe and ns.Safe.Value(inInst) == true then
            local it = ns.Safe.String(instType)
            if (it == "party" or it == "scenario") and s.msgPreviewSilenceDungeons ~= false then
                return true
            elseif it == "raid" and s.msgPreviewSilenceRaids ~= false then
                return true
            elseif (it == "pvp" or it == "arena") and s.msgPreviewSilencePvP ~= false then
                return true
            end
        end
    end
    return false
end

local function MpIsCategoryEnabled(cat)
    local s = ns.db and ns.db.settings
    if not s then return false end
    if cat == "WHISPER" then
        return s.msgPreviewWhispers ~= false
    elseif cat == "BN_WHISPER" then
        return s.msgPreviewBNet ~= false
    elseif cat == "GROUP" then
        return s.msgPreviewGroup == true
    elseif cat == "GUILD" then
        return s.msgPreviewGuild == true
    elseif cat == "ROOM" then
        return s.msgPreviewRooms ~= false
    end
    return false
end

local function MpUnitMatchesSender(unit, targetGuid, targetLk, targetFirstLow)
    if not (unit and UnitExists and ns.Safe) then return false end
    if ns.Safe.Value(ns.Safe.Call(UnitExists, unit)) ~= true then return false end
    if ns.Safe.Value(ns.Safe.Call(UnitIsPlayer, unit)) ~= true then return false end
    if ns.Safe.Value(ns.Safe.Call(UnitIsVisible, unit)) ~= true then return false end
    local uGuid = ns.Safe.String(ns.Safe.Call(UnitGUID, unit))
    if targetGuid and uGuid then
        return uGuid == targetGuid
    end
    if not targetLk and not targetFirstLow then return false end
    local resolved = Compat and Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(unit, uGuid, nil, true)
    if resolved then
        if targetLk and resolved.lookupKey and resolved.lookupKey == targetLk then
            return true
        end
        if targetFirstLow and resolved.firstName and resolved.firstName:lower() == targetFirstLow and not (targetLk and targetLk:find(" ", 1, true)) then
            return true
        end
    end
    return false
end

local function MpFindVisibleSenderUnit(item)
    if not item then return nil end
    local tGuid = item.senderGuid
    local charName = item.senderCharName or item.sender
    local tLk, tFirst
    if charName and not tostring(charName):find("|K", 1, true) and Compat and Compat.ParseCharacterFields then
        tLk, tFirst = Compat.ParseCharacterFields(charName)
    end
    local tFirstLow = tFirst and tFirst:lower() or nil
    if not tGuid and not tLk and not tFirstLow then return nil end

    if item.isTestPreview == true and MpUnitMatchesSender("player", tGuid, tLk, tFirstLow) then
        return "player"
    end
    for _, u in ipairs({ "target", "focus", "mouseover" }) do
        if MpUnitMatchesSender(u, tGuid, tLk, tFirstLow) then
            return u
        end
    end
    if Compat and Compat.IsInRaid and Compat.IsInRaid() then
        if tGuid and UnitIsVisible and UnitGUID then
            local n = (Compat.GetNumGroupMembers and Compat.GetNumGroupMembers()) or 0
            for i = 1, math.min(n, 40) do
                local u = "raid" .. tostring(i)
                if UnitIsVisible(u) and ns.Safe and ns.Safe.String(ns.Safe.Call(UnitGUID, u)) == tGuid then
                    return u
                end
            end
        end
    elseif Compat and Compat.IsInGroup and Compat.IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. tostring(i)
            if MpUnitMatchesSender(u, tGuid, tLk, tFirstLow) then
                return u
            end
        end
    end
    return nil
end

local function MpResolveSenderAvatar(item, iconTex, classPipFrame, classPipTex)
    if not iconTex then return nil end
    iconTex:SetTexture(nil)
    iconTex:SetTexCoord(0, 1, 0, 1)
    if classPipFrame then classPipFrame:Hide() end

    local classFile = item and item.senderClass
    local engRace, sex
    if item and item.senderGuid and GetPlayerInfoByGUID then
        local ok, _, gClass, _, gRace, gSex = pcall(GetPlayerInfoByGUID, item.senderGuid)
        if ok then
            if not classFile then classFile = ns.Safe and ns.Safe.String(gClass) end
            engRace = ns.Safe and ns.Safe.String(gRace)
            sex = ns.Safe and ns.Safe.Number(gSex)
        end
    end

    local function ShowClassPip()
        if not (classPipFrame and classPipTex and classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]) then
            if classPipFrame then classPipFrame:Hide() end
            return
        end
        local cc = CLASS_ICON_TCOORDS[classFile]
        classPipTex:SetTexture(MP_CLASS_TEX)
        classPipTex:SetTexCoord(cc[1] + 0.025, cc[2] - 0.025, cc[3] + 0.025, cc[4] - 0.025)
        classPipFrame:Show()
    end

    -- Tier 1: Live 2D character portrait when sender is currently visible in world / party / raid
    local liveUnit = MpFindVisibleSenderUnit(item)
    if liveUnit and SetPortraitTexture then
        local okP = pcall(SetPortraitTexture, iconTex, liveUnit)
        if okP then
            iconTex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
            ShowClassPip()
            return classFile
        end
    end

    -- Tier 2: Race + Gender portrait atlas if available on this Forever client build
    if engRace and sex and ns.Theme and ns.Theme.HasAtlas then
        local rSlug = MP_RACE_ATLAS_SLUG[engRace] or engRace:lower():gsub("%s+", "")
        local gSlug = (sex == 3) and "female" or "male"
        local atlas = "raceicon-" .. rSlug .. "-" .. gSlug
        if not ns.Theme:HasAtlas(atlas) then
            atlas = "raceicon128-" .. rSlug .. "-" .. gSlug
        end
        if ns.Theme:HasAtlas(atlas) then
            iconTex:SetTexCoord(0, 1, 0, 1)
            local okA = pcall(iconTex.SetAtlas, iconTex, atlas, false)
            if okA then
                ShowClassPip()
                return classFile
            end
        end
    end

    -- Tier 3: Crisp Class Crest Icon (works globally for whispers, guild, group, BNet WoW chars)
    if classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile] then
        local cc = CLASS_ICON_TCOORDS[classFile]
        iconTex:SetTexture(MP_CLASS_TEX)
        iconTex:SetTexCoord(cc[1] + 0.025, cc[2] - 0.025, cc[3] + 0.025, cc[4] - 0.025)
        return classFile
    end

    -- Tier 4: Official Battle.net icon for BNet friends not on a known WoW character
    if item and (item.category == "BN_WHISPER" or item.bnetAccountID) then
        iconTex:SetTexture(MP_BNET_TEX)
        iconTex:SetTexCoord(0.14, 0.86, 0.14, 0.86)
        return nil
    end

    -- Tier 5: Clean channel emblem fallback
    if item and item.category == "GROUP" then
        iconTex:SetTexture(MP_PARTY_TEX)
    else
        iconTex:SetTexture(MP_MAIL_TEX)
    end
    iconTex:SetTexCoord(0.04, 0.96, 0.04, 0.96)
    return nil
end

local function MpClampCenterToScreen(cx, cy)
    local uiW = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1280
    local uiH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 720
    local halfW = (MP_MAX_W * 0.5) + 12
    local halfH = (MP_HEIGHT * 1.5) + MP_SLOT_GAP + 14
    return MpClamp(cx or (uiW * 0.5), halfW, math.max(halfW, uiW - halfW)),
           MpClamp(cy or (uiH * 0.5), halfH, math.max(halfH, uiH - halfH))
end

local function MpGetSavedCustomCenter()
    if MsgPreview.draggingStack and type(MsgPreview.dragCenterX) == "number" and type(MsgPreview.dragCenterY) == "number" then
        return MpClampCenterToScreen(MsgPreview.dragCenterX, MsgPreview.dragCenterY)
    end
    local saved = ns.Theme and ns.Theme.GetSavedWindowPosition and ns.Theme:GetSavedWindowPosition(MP_POS_KEY)
        or (ns.db and type(ns.db.windowPositions) == "table" and ns.db.windowPositions[MP_POS_KEY])
    if type(saved) == "table" and type(saved.dx) == "number" and type(saved.dy) == "number" then
        local uiW = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1280
        local uiH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 720
        return MpClampCenterToScreen((uiW * 0.5) + saved.dx, (uiH * 0.5) + saved.dy)
    end
    return nil, nil
end

local function MpHasCustomPosition()
    if ns.Theme and ns.Theme.HasSavedWindowPosition then
        return ns.Theme:HasSavedWindowPosition(MP_POS_KEY)
    end
    local saved = ns.db and type(ns.db.windowPositions) == "table" and ns.db.windowPositions[MP_POS_KEY]
    return type(saved) == "table" and type(saved.dx) == "number" and type(saved.dy) == "number"
end

local function MpSaveCustomCenter(cx, cy)
    if not ns.db then return end
    local uiW = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1280
    local uiH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 720
    local ccx, ccy = MpClampCenterToScreen(cx, cy)
    local payload = {
        anchor = "CENTER",
        dx = math.floor((ccx - (uiW * 0.5)) + 0.5),
        dy = math.floor((ccy - (uiH * 0.5)) + 0.5),
    }
    if ns.Theme and ns.Theme.SetSavedWindowPosition then
        ns.Theme:SetSavedWindowPosition(MP_POS_KEY, payload)
    else
        if type(ns.db.windowPositions) ~= "table" then
            ns.db.windowPositions = {}
        end
        ns.db.windowPositions[MP_POS_KEY] = payload
    end
    return ccx, ccy
end

local function MpGetExpandDuration(flightDist)
    local extra = MpClamp(((flightDist or 0) - 260) / 1400, 0, 1) * 0.24
    return MP_EXPAND_DUR + extra
end

local function MpGetCollapseDuration(flightDist)
    local extra = MpClamp(((flightDist or 0) - 260) / 1400, 0, 1) * 0.26
    return MP_COLLAPSE_DUR + extra
end

local function MpGetAnchorMode()
    local m = ns.db and ns.db.settings and ns.db.settings.msgPreviewAnchor
    if m == "chat_side" or m == "chat_top" then
        return m
    end
    return "minimap"
end

local function MpComputeAnchorCoords(frame)
    local uiW = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1280
    local uiH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 720
    local pillScale = (frame and frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    if pillScale <= 0 then pillScale = 1 end

    local mmLeft, mmRight, mmCenterY
    if Minimap and Minimap:IsShown() and Minimap.GetLeft and Minimap.GetCenter then
        local mmScale = Minimap:GetEffectiveScale() or 1
        local ratio = mmScale / pillScale
        local l = Minimap:GetLeft()
        local r = Minimap:GetRight()
        local _, cy = Minimap:GetCenter()
        if l and r and cy then
            mmLeft = l * ratio
            mmRight = r * ratio
            mmCenterY = cy * ratio
        end
    end
    if not mmLeft then
        mmLeft = uiW - 210
        mmRight = uiW - 30
        mmCenterY = uiH - 120
    end

    local anchorMode = MpGetAnchorMode()
    local side, restEdgeX, restCenterY
    local customX, customY = MpGetSavedCustomCenter()
    if customX and customY then
        local cardW = MpClamp(
            (frame and frame._slot and frame._slot.targetW) or (frame and frame.GetWidth and frame:GetWidth()) or MP_MAX_W,
            MP_MIN_W,
            MP_MAX_W
        )
        if customX >= (uiW * 0.5) then
            side = "LEFT"
            restEdgeX = customX + (cardW * 0.5)
        else
            side = "RIGHT"
            restEdgeX = customX - (cardW * 0.5)
        end
        restCenterY = customY
    elseif anchorMode == "chat_side" or anchorMode == "chat_top" then
        local cf = (_G.ChatFrame1Background and _G.ChatFrame1Background.GetLeft and _G.ChatFrame1Background) or _G.ChatFrame1
        local cfLeft, cfRight, cfTop = 32, 430, 220
        if cf and cf.GetLeft and cf.GetRight and cf.GetTop then
            local cfScale = (cf.GetEffectiveScale and cf:GetEffectiveScale()) or 1
            local ratio = cfScale / pillScale
            local l, r, t = cf:GetLeft(), cf:GetRight(), cf:GetTop()
            if l and r and t then
                cfLeft = l * ratio
                cfRight = r * ratio
                cfTop = t * ratio
            end
        end
        if anchorMode == "chat_top" then
            local tabRef = _G.GeneralDockManager or _G.ChatFrame1Tab
            local tabTop = 0
            if tabRef and tabRef.GetTop and tabRef.IsShown and tabRef:IsShown() then
                local trScale = (tabRef.GetEffectiveScale and tabRef:GetEffectiveScale()) or 1
                local tt = tabRef:GetTop()
                if tt then
                    tabTop = tt * (trScale / pillScale)
                end
            end
            local baseTop = math.max(cfTop, tabTop)
            side = "RIGHT"
            restEdgeX = MpClamp(cfLeft, 16, math.max(16, uiW - MP_MAX_W - 16))
            restCenterY = MpClamp(baseTop + 36, 110, uiH - 68)
        else
            if (uiW - cfRight) >= (MP_MAX_W + MP_REST_GAP + 14) or ((cfLeft + cfRight) * 0.5) < (uiW * 0.5) then
                side = "RIGHT"
                restEdgeX = cfRight + MP_REST_GAP + 6
            else
                side = "LEFT"
                restEdgeX = cfLeft - MP_REST_GAP - 6
            end
            restCenterY = MpClamp(cfTop - 34, 96, uiH - 80)
        end
    else
        side = (mmLeft >= (MP_MAX_W + MP_REST_GAP + 12)) and "LEFT" or "RIGHT"
        restEdgeX = (side == "LEFT") and (mmLeft - MP_REST_GAP) or (mmRight + MP_REST_GAP)
        restCenterY = mmCenterY
    end

    local startBtn = (anchorMode ~= "minimap" and chatButton and chatButton:IsShown()) and chatButton
        or ((button and button:IsShown()) and button or (chatButton and chatButton:IsShown() and chatButton or nil))
    local startEdgeX, startCenterY
    if startBtn and startBtn.GetCenter then
        local bx, by = startBtn:GetCenter()
        local bScale = startBtn:GetEffectiveScale() or 1
        if bx and by then
            local bRatio = bScale / pillScale
            local scX = bx * bRatio
            local scY = by * bRatio
            startEdgeX = (side == "LEFT") and (scX + (MP_COLLAPSED_W * 0.5)) or (scX - (MP_COLLAPSED_W * 0.5))
            startCenterY = scY
        end
    end
    if not startEdgeX then
        startEdgeX = (side == "LEFT") and (mmLeft - 6) or (mmRight + 6)
        startCenterY = mmCenterY
    end

    local fdx = restEdgeX - startEdgeX
    local fdy = restCenterY - startCenterY
    local flightDist = math.sqrt((fdx * fdx) + (fdy * fdy))

    return side, startEdgeX, startCenterY, restEdgeX, restCenterY, flightDist
end

local function MpApplyThemeToPreview(f, forceTheme)
    if not f then return end
    local Theme = ns.Theme
    local shell = f.pillShell or f
    local p = Theme and Theme.GetPalette and Theme:GetPalette() or nil
    local palKey = (p and p.key) or "dark"
    local toneKey = f._toneKey or "whisper"
    local palDirty = (forceTheme == true) or (f._appliedPalKey ~= palKey)
    local toneDirty = palDirty or (f._appliedToneKey ~= toneKey)

    if not toneDirty then
        return
    end
    f._appliedPalKey = palKey
    f._appliedToneKey = toneKey

    local spec = f._toneSpec or (Theme and Theme.GetChatToneSpec and Theme:GetChatToneSpec(toneKey))
    if shell._solidOpaqueBg then
        local bot = (spec and spec.cardBgBot) or { 0.12, 0.06, 0.14, 1.0 }
        shell._solidOpaqueBg:SetVertexColor(bot[1], bot[2], bot[3], 1.0)
    end
    if f.bgAmbient and spec and spec.cardBgTop and spec.cardBgBot then
        MpApplyGradient(
            f.bgAmbient, "VERTICAL",
            spec.cardBgBot[1], spec.cardBgBot[2], spec.cardBgBot[3], 1.0,
            spec.cardBgTop[1], spec.cardBgTop[2], spec.cardBgTop[3], 1.0
        )
    end
    local rgb = f._accentRgb or (spec and spec.accent) or { 0.96, 0.52, 0.96 }
    if f.headerWash then
        MpApplyGradient(
            f.headerWash, "HORIZONTAL",
            rgb[1] * 0.34, rgb[2] * 0.34, rgb[3] * 0.34, 0.44,
            rgb[1] * 0.10, rgb[2] * 0.10, rgb[3] * 0.10, 0.06
        )
    end
    if f.headerRule then
        MpApplyGradient(
            f.headerRule, "HORIZONTAL",
            rgb[1] * 0.72 + 0.24, rgb[2] * 0.72 + 0.24, rgb[3] * 0.72 + 0.24, 0.55,
            rgb[1], rgb[2], rgb[3], 0.0
        )
    end
    local br, bg, bb, ba = 0.38, 0.42, 0.50, 1.0
    if spec and spec.cardBorder then
        br, bg, bb, ba = spec.cardBorder[1], spec.cardBorder[2], spec.cardBorder[3], spec.cardBorder[4] or 1.0
    elseif f._accentRgb then
        local r, g, b = f._accentRgb[1], f._accentRgb[2], f._accentRgb[3]
        br, bg, bb = r * 0.65 + 0.16, g * 0.65 + 0.16, b * 0.65 + 0.16
    end
    if shell.borders then
        for _, edge in ipairs(shell.borders) do
            edge:SetColorTexture(br, bg, bb, ba)
        end
    end
    if f.topBevel then
        local isWarm = (palKey == "blizzard" or palKey == "native")
        if isWarm then
            f.topBevel:SetColorTexture(1, 0.92, 0.70, 0.20)
        else
            f.topBevel:SetColorTexture(0.70, 0.88, 1.0, 0.18)
        end
    end

    if palDirty then
        if f.previewLbl then
            f.previewLbl:SetTextColor(0.97, 0.98, 1.00)
        end
        if f.queueLbl then
            f.queueLbl:SetTextColor(1.00, 0.88, 0.34)
        end
        if f.closeBtn and Theme and Theme.StyleButton then
            Theme:StyleButton(f.closeBtn, "default")
            if Theme.SyncButtonLayers then
                Theme:SyncButtonLayers(f.closeBtn)
            end
        end
        if f.muteNotifBtn and Theme and Theme.StyleButton then
            Theme:StyleButton(f.muteNotifBtn, "default")
            if Theme.SyncButtonLayers then
                Theme:SyncButtonLayers(f.muteNotifBtn)
            end
        end
    end
end

local function MpOpenReplyChat(item)
    if not item then return end
    local officialOnly = Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode()
    local s = ns.db and ns.db.settings
    local qrEnabled = (not s) or s.quickReplyEnabled ~= false
    if (not officialOnly) and qrEnabled and item.threadKey and ns.QuickReply and ns.QuickReply.OpenThread then
        if ns.QuickReply:OpenThread(item.threadKey, true) then
            return
        end
    end
    if (not officialOnly) and item.threadKey and ns.NavigateToModule then
        ns:NavigateToModule("chat", { threadKey = item.threadKey, focusInput = true })
        return
    end
    if MpIsInCombat() then
        ns:Print("%s", L["Unavailable during combat."])
        return
    end
    if item.category == "BN_WHISPER" and Compat and Compat.BNetWhisper then
        Compat.BNetWhisper(item.bnetName or item.sender, item.senderCharName)
    elseif item.category == "WHISPER" and Compat and Compat.Whisper then
        Compat.Whisper(item.senderCharName or item.sender)
    elseif item.replySlash and ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, item.replySlash)
    elseif item.threadKey and ns.NavigateToModule then
        ns:NavigateToModule("chat", { threadKey = item.threadKey, focusInput = true })
    end
end

local function MpHandlePrimaryClick(item)
    if not item then return end
    MinimapBtn:ClearPreviewCounts()
    if IsShiftKeyDown and IsShiftKeyDown() then
        MpOpenReplyChat(item)
        return
    end
    if item.threadKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[item.threadKey] then
        local s = ns.db and ns.db.settings
        local qrEnabled = (not s) or s.quickReplyEnabled ~= false
        if qrEnabled and ns.QuickReply and ns.QuickReply.OpenThread and ns.QuickReply:OpenThread(item.threadKey, false) then
            return
        end
        if ns.NavigateToModule then
            ns:NavigateToModule("chat", { threadKey = item.threadKey })
        end
    else
        MpOpenReplyChat(item)
    end
end

local function MpDisableCategory(category)
    local s = ns.db and ns.db.settings
    if not s then return end
    s.msgPreviewPromptAnswered = true
    if category == "WHISPER" then
        s.msgPreviewWhispers = false
    elseif category == "BN_WHISPER" then
        s.msgPreviewBNet = false
    elseif category == "GROUP" then
        s.msgPreviewGroup = false
    elseif category == "GUILD" then
        s.msgPreviewGuild = false
    elseif category == "ROOM" then
        s.msgPreviewRooms = false
    end
    ns:Emit("SETTINGS_UPDATED")
    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
end

local function MpCategoryDisableLabel(category)
    if category == "WHISPER" then return L["Disable Whisper Previews"]
    elseif category == "BN_WHISPER" then return L["Disable Battle.net Previews"]
    elseif category == "GROUP" then return L["Disable Group Previews"]
    elseif category == "GUILD" then return L["Disable Guild Previews"]
    elseif category == "ROOM" then return L["Disable Room Previews"]
    end
    return L["Disable Minimap Message Previews"]
end

local function MpRenderItemContent(f, item)
    if not (f and item) then return end
    local Theme = ns.Theme
    local ck = item.channelKind or item.category or "WHISPER"
    local toneKey = (Theme and Theme.GetChatToneForKind) and Theme:GetChatToneForKind(ck) or "whisper"
    local toneSpec = (Theme and Theme.GetChatToneSpec) and Theme:GetChatToneSpec(toneKey) or nil
    local rgb = (toneSpec and toneSpec.accent) or MpChannelRGB(item)
    f._toneKey = toneKey
    f._toneSpec = toneSpec
    f._accentRgb = rgb

    local resolvedClass = MpResolveSenderAvatar(item, f.senderIconTex, f.classPipFrame, f.classPipTex)
    if resolvedClass and not item.senderClass then
        item.senderClass = resolvedClass
    end

    local ringR, ringG, ringB = rgb[1], rgb[2], rgb[3]
    if item.senderClass and Compat and Compat.ClassColor then
        local cr, cg, cb = Compat.ClassColor(item.senderClass)
        if cr and cg and cb then
            ringR, ringG, ringB = cr, cg, cb
        end
    end
    if f.avatarRing then
        f.avatarRing:SetVertexColor(ringR, ringG, ringB, 0.94)
    end
    if f.avatarHalo then
        f.avatarHalo:SetVertexColor(rgb[1], rgb[2], rgb[3], 0.42)
    end
    if f.sideBar then
        f.sideBar:SetColorTexture(rgb[1], rgb[2], rgb[3], 1.0)
    end
    if f.progressFill and f._lastProgTone ~= toneKey then
        f._lastProgTone = toneKey
        MpApplyGradient(f.progressFill, "HORIZONTAL", rgb[1] * 0.65, rgb[2] * 0.65, rgb[3] * 0.65, 0.94, math.min(1, rgb[1] + 0.22), math.min(1, rgb[2] + 0.22), math.min(1, rgb[3] + 0.22), 1.0)
        if f.progressTip then
            f.progressTip:SetVertexColor(math.min(1, rgb[1] + 0.32), math.min(1, rgb[2] + 0.32), math.min(1, rgb[3] + 0.32), 0.92)
        end
    end

    local streamerOn = Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()
    local hex = (item.senderClass and Compat and Compat.ClassHex) and Compat.ClassHex(item.senderClass) or "|cffffffff"
    local chanTag = MpChannelLabel(item)
    local chanHex = string.format("|cff%02x%02x%02x", math.floor(rgb[1] * 255), math.floor(rgb[2] * 255), math.floor(rgb[3] * 255))
    local mult = (item.coalescedCount and item.coalescedCount > 1) and (" |cff9da7b5(x" .. tostring(item.coalescedCount) .. ")|r") or ""
    local senderDisp = tostring(item.sender or "?")
    if streamerOn and (item.category == "BN_WHISPER" or item.bnetAccountID ~= nil or senderDisp:find("#", 1, true)) then
        senderDisp = Compat.MaskStreamerBNetName(senderDisp)
    end
    f.senderLbl:SetText(hex .. senderDisp .. "|r " .. chanHex .. "· " .. chanTag .. "|r" .. mult)

    local snippet, fullClean
    if streamerOn and (item.category == "WHISPER" or item.category == "BN_WHISPER" or item.category == "ROOM") then
        snippet = "|cff9da7b5" .. L["[Hidden in Streamer Mode]"] .. "|r"
        fullClean = L["[Hidden in Streamer Mode]"]
    elseif item._snippet and item._fullClean then
        snippet, fullClean = item._snippet, item._fullClean
    else
        snippet, fullClean = MpCleanPreviewText(item.text)
        item._fullClean = fullClean
        item._snippet = snippet
    end
    f.previewLbl:SetText(snippet)

    local showQ = (f._showQueueCount or 0)
    if showQ > 0 then
        f.queueLbl:SetText("+" .. tostring(showQ))
        f.queueLbl:Show()
    else
        f.queueLbl:SetText("")
        f.queueLbl:Hide()
    end

    -- Compute sleek dynamic pill width so short pings stay compact while longer snippets stay legible
    local nameW = (f.senderLbl.GetUnboundedStringWidth and f.senderLbl:GetUnboundedStringWidth()) or (f.senderLbl.GetStringWidth and f.senderLbl:GetStringWidth()) or 110
    local bodyW = (f.previewLbl.GetUnboundedStringWidth and f.previewLbl:GetUnboundedStringWidth()) or (f.previewLbl.GetStringWidth and f.previewLbl:GetStringWidth()) or 130
    local idealTextW = math.max(nameW + (showQ > 0 and 24 or 4) + 36, math.min(bodyW, 240))
    local computedW = MpClamp(math.ceil(50 + idealTextW + 14), MP_MIN_W, MP_MAX_W)
    -- Pin fixed wrap width once at spawn so EXPAND/COLLAPSE clip width changes never re-wrap preview text per frame.
    local headerTextW = math.max(48, computedW - 98 - ((showQ > 0) and 24 or 0))
    local bodyTextW = math.max(96, computedW - 64)
    if f.senderLbl and f.senderLbl.SetWidth then
        f.senderLbl:SetWidth(headerTextW)
    end
    if f.previewLbl and f.previewLbl.SetWidth then
        f.previewLbl:SetWidth(bodyTextW)
    end

    MpApplyThemeToPreview(f)
    return computedW
end

local function MpApplySlotVisuals(slot, moveP, sizeP, frameAlpha, scAlpha, senderAlpha, contentAlpha, flashAlpha)
    local f = slot and slot.frame
    if not f then return end
    local coords = slot._coords
    if MsgPreview.draggingStack or not coords then
        local side, sX, sY, rX, rY, fDist = MpComputeAnchorCoords(f)
        coords = slot._coords or {}
        coords.side = side
        coords.startEdgeX = sX
        coords.startCenterY = sY
        coords.restEdgeX = rX
        coords.restCenterY = rY
        coords.flightDist = fDist
        slot._coords = coords
    end
    local side = coords.side
    local startEdgeX = coords.startEdgeX
    local startCenterY = coords.startCenterY
    local restEdgeX = coords.restEdgeX
    local restCenterY = coords.restCenterY
    local flightDist = coords.flightDist
    MsgPreview.sideMode = side
    slot.lastFlightDist = flightDist

    local targetRestY = restCenterY + (slot.curOffsetY or 0)
    local arcLift = 0
    if moveP > 0.001 and moveP < 0.999 and (flightDist or 0) > 300 then
        arcLift = math.sin(moveP * math.pi) * MpClamp((flightDist - 300) / 900, 0, 1) * 28
    end
    local curEdgeX = math.floor((startEdgeX + (restEdgeX - startEdgeX) * moveP) + 0.5)
    local curCenterY = math.floor((startCenterY + (targetRestY - startCenterY) * moveP + arcLift) + 0.5)
    local targetW = slot.targetW or MP_MIN_W
    local curW = math.floor((MP_COLLAPSED_W + (targetW - MP_COLLAPSED_W) * sizeP) + 0.5)
    local curH = math.floor((MP_COLLAPSED_H + (MP_HEIGHT - MP_COLLAPSED_H) * sizeP) + 0.5)

    if f._lastSide ~= side or f._lastEdgeX ~= curEdgeX or f._lastCenterY ~= curCenterY then
        f._lastSide = side
        f._lastEdgeX = curEdgeX
        f._lastCenterY = curCenterY
        f:ClearAllPoints()
        if side == "LEFT" then
            f:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", curEdgeX, curCenterY)
        else
            f:SetPoint("LEFT", UIParent, "BOTTOMLEFT", curEdgeX, curCenterY)
        end
    end
    if f._lastW ~= curW or f._lastH ~= curH then
        f._lastW = curW
        f._lastH = curH
        f:SetSize(curW, curH)
    end
    local qFrameA = math.floor(MpClamp(frameAlpha, 0, 1) * 50 + 0.5) * 0.02
    if f._lastFrameA ~= qFrameA then
        f._lastFrameA = qFrameA
        f:SetAlpha(qFrameA)
    end

    if f.pillShell then
        local shellAlpha = math.floor(MpClamp((sizeP - 0.08) / 0.34, 0, 1) * 50 + 0.5) * 0.02
        if f._lastShellA ~= shellAlpha then
            f._lastShellA = shellAlpha
            f.pillShell:SetAlpha(shellAlpha)
            local wantShow = (shellAlpha > 0.01)
            if f._lastShellVis ~= wantShow then
                f._lastShellVis = wantShow
                f.pillShell:SetShown(wantShow)
            end
        end
    end
    if f.sideBar then
        if f._lastSideBarMode ~= side then
            f._lastSideBarMode = side
            f.sideBar:ClearAllPoints()
            if side == "LEFT" then
                f.sideBar:SetPoint("TOPRIGHT", f.pillShell or f, "TOPRIGHT", -1, -1)
                f.sideBar:SetPoint("BOTTOMRIGHT", f.pillShell or f, "BOTTOMRIGHT", -1, 1)
            else
                f.sideBar:SetPoint("TOPLEFT", f.pillShell or f, "TOPLEFT", 1, -1)
                f.sideBar:SetPoint("BOTTOMLEFT", f.pillShell or f, "BOTTOMLEFT", 1, 1)
            end
        end
        local qBarA = math.floor(MpClamp(sizeP, 0, 1) * 50 + 0.5) * 0.02
        if f._lastBarA ~= qBarA then
            f._lastBarA = qBarA
            f.sideBar:SetAlpha(qBarA)
        end
    end
    if f.avatarBox then
        local leftPad = math.floor((9 * sizeP) + 0.5)
        if f._lastAvatarPad ~= leftPad then
            f._lastAvatarPad = leftPad
            f.avatarBox:ClearAllPoints()
            f.avatarBox:SetPoint("LEFT", f, "LEFT", leftPad, 0)
        end
    end
    if f.scIconTex then
        local sa = math.floor(MpClamp(scAlpha, 0, 1) * 50 + 0.5) * 0.02
        if f._lastScA ~= sa then
            f._lastScA = sa
            f.scIconTex:SetAlpha(sa)
            local wantShow = (sa > 0.01)
            if f._lastScVis ~= wantShow then
                f._lastScVis = wantShow
                f.scIconTex:SetShown(wantShow)
            end
        end
    end
    if f.senderIconTex then
        local ia = math.floor(MpClamp(senderAlpha, 0, 1) * 50 + 0.5) * 0.02
        if f._lastSenderA ~= ia then
            f._lastSenderA = ia
            f.senderIconTex:SetAlpha(ia)
            local wantShow = (ia > 0.01)
            if f._lastSenderVis ~= wantShow then
                f._lastSenderVis = wantShow
                f.senderIconTex:SetShown(wantShow)
            end
            if f.classPipFrame then
                f.classPipFrame:SetAlpha(ia)
            end
        end
    end
    if f.arrivalFlash then
        local fa = math.floor(MpClamp(flashAlpha or 0, 0, 1) * 50 + 0.5) * 0.02
        if f._lastFlashA ~= fa then
            f._lastFlashA = fa
            local wantShow = (fa > 0.01)
            if wantShow then
                local rgb = f._accentRgb or { 1, 0.9, 0.6 }
                f.arrivalFlash:SetVertexColor(rgb[1] * 0.45 + 0.55, rgb[2] * 0.45 + 0.55, rgb[3] * 0.45 + 0.55, fa)
                if not f._lastFlashVis then
                    f._lastFlashVis = true
                    f.arrivalFlash:Show()
                end
            elseif f._lastFlashVis ~= false then
                f._lastFlashVis = false
                f.arrivalFlash:Hide()
            end
        end
    end
    local ca = math.floor(MpClamp(contentAlpha, 0, 1) * 50 + 0.5) * 0.02
    local wantClip = (ca > 0.01 and curW > 76)
    local wantClose = (ca > 0.20 and curW > 96)
    local wantMute = (ca > 0.20 and curW > 116)
    local wantProg = (ca > 0.15 and curW > 80)
    if f._lastContentA ~= ca or f._lastWantClip ~= wantClip or f._lastWantClose ~= wantClose or f._lastWantMute ~= wantMute or f._lastWantProg ~= wantProg then
        f._lastContentA = ca
        f._lastWantClip = wantClip
        f._lastWantClose = wantClose
        f._lastWantMute = wantMute
        f._lastWantProg = wantProg
        if f.contentClip then
            f.contentClip:SetAlpha(ca)
            f.contentClip:SetShown(wantClip)
        end
        if f.closeBtn then
            f.closeBtn:SetAlpha(ca)
            f.closeBtn:SetShown(wantClose)
        end
        if f.muteNotifBtn then
            f.muteNotifBtn:SetAlpha(ca)
            f.muteNotifBtn:SetShown(wantMute)
        end
        if f.progressTrack and f.progressFill then
            f.progressTrack:SetAlpha(ca * 0.85)
            f.progressFill:SetAlpha(ca)
            f.progressTrack:SetShown(wantProg)
            f.progressFill:SetShown(wantProg)
            if f.progressTip then
                f.progressTip:SetAlpha(ca)
                f.progressTip:SetShown(wantProg)
            end
        end
    end
end

local function MpSyncQueueBadges()
    local qCount = #MsgPreview.queue
    local count = #MsgPreview.activeSlots
    for i, slot in ipairs(MsgPreview.activeSlots) do
        local f = slot.frame
        if f then
            local wantQ = (i == count) and qCount or 0
            if f._showQueueCount ~= wantQ then
                f._showQueueCount = wantQ
                if wantQ > 0 then
                    f.queueLbl:SetText("+" .. tostring(wantQ))
                    f.queueLbl:Show()
                else
                    f.queueLbl:SetText("")
                    f.queueLbl:Hide()
                end
                if f.senderLbl and f.contentClip then
                    f.senderLbl:ClearAllPoints()
                    f.senderLbl:SetPoint("TOPLEFT", f.contentClip, "TOPLEFT", 0, -1)
                    local headerW = math.max(48, (slot.targetW or f:GetWidth() or MP_MAX_W) - 98 - ((wantQ > 0) and 24 or 0))
                    if f.senderLbl.SetWidth then
                        f.senderLbl:SetWidth(headerW)
                    end
                end
            end
        end
    end
end

local function MpEnsureDriverFrame()
    if not MsgPreview.driverFrame then
        MsgPreview.driverFrame = CreateFrame("Frame", nil, UIParent)
    end
    return MsgPreview.driverFrame
end

local function MpStopAllIdle()
    for _, slot in ipairs(MsgPreview.activeSlots) do
        if slot.frame then
            slot.frame._slot = nil
            slot.frame:Hide()
        end
    end
    wipe(MsgPreview.activeSlots)
    for _, f in ipairs(MsgPreview.framePool) do
        f._slot = nil
        f:Hide()
    end
    if MsgPreview.driverFrame then
        MsgPreview.driverFrame:SetScript("OnUpdate", nil)
    end
end

local function MpBeginCollapseSlot(slot)
    if not slot or slot.phase == "COLLAPSE" then return end
    slot.phase = "COLLAPSE"
    slot.phaseTime = 0
end

local function MpBeginCollapseAll(clearQueue)
    if clearQueue then
        wipe(MsgPreview.queue)
    end
    if #MsgPreview.activeSlots == 0 then
        MpStopAllIdle()
        return
    end
    for _, slot in ipairs(MsgPreview.activeSlots) do
        MpBeginCollapseSlot(slot)
    end
end

local function MpFinishStackDrag()
    if not MsgPreview.draggingStack then
        return
    end
    MsgPreview.draggingStack = false
    MsgPreview._dragFrame = nil
    if type(MsgPreview.dragCenterX) == "number" and type(MsgPreview.dragCenterY) == "number" then
        MpSaveCustomCenter(MsgPreview.dragCenterX, MsgPreview.dragCenterY)
    end
    MsgPreview.dragCenterX = nil
    MsgPreview.dragCenterY = nil
    for _, slot in ipairs(MsgPreview.activeSlots) do
        slot._coords = nil
    end
    if MsgPreview.anchorMover and MsgPreview.anchorMover:IsShown() and MsgPreview.SyncAnchorMoverPosition then
        MsgPreview:SyncAnchorMoverPosition()
    end
end

local function MpEnsureSlotFrame(poolIdx)
    if MsgPreview.framePool[poolIdx] then
        return MsgPreview.framePool[poolIdx]
    end
    local Theme = ns.Theme
    local f = CreateFrame("Button", "SocialCentralMinimapMsgPreview" .. tostring(poolIdx), UIParent)
    f:SetSize(MP_COLLAPSED_W, MP_COLLAPSED_H)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(186 + (poolIdx - 1) * 12)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    if f.SetClipsChildren then f:SetClipsChildren(false) end
    f:Hide()

    -- Lightweight 100%-opaque pill shell (4 crisp 1px edge textures -> zero NineSlice rebuild stutter during expand/collapse)
    local pillShell = CreateFrame("Frame", nil, f)
    pillShell:SetAllPoints(f)
    pillShell:SetFrameLevel(f:GetFrameLevel() + 1)
    pillShell:EnableMouse(false)
    f.pillShell = pillShell

    local solidBg = pillShell:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetAllPoints(pillShell)
    solidBg:SetTexture(MP_WHITE8X8)
    solidBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    pillShell._solidOpaqueBg = solidBg
    f._solidOpaqueBg = solidBg

    local bgAmbient = pillShell:CreateTexture(nil, "BACKGROUND", nil, -2)
    bgAmbient:SetPoint("TOPLEFT", pillShell, "TOPLEFT", 1, -1)
    bgAmbient:SetPoint("BOTTOMRIGHT", pillShell, "BOTTOMRIGHT", -1, 1)
    f.bgAmbient = bgAmbient

    local headerWash = pillShell:CreateTexture(nil, "BACKGROUND", nil, -1)
    headerWash:SetHeight(19)
    headerWash:SetPoint("TOPLEFT", pillShell, "TOPLEFT", 1, -1)
    headerWash:SetPoint("TOPRIGHT", pillShell, "TOPRIGHT", -1, -1)
    f.headerWash = headerWash

    local bTop = pillShell:CreateTexture(nil, "BORDER", nil, 3)
    bTop:SetHeight(1)
    bTop:SetPoint("TOPLEFT", pillShell, "TOPLEFT", 0, 0)
    bTop:SetPoint("TOPRIGHT", pillShell, "TOPRIGHT", 0, 0)
    local bBot = pillShell:CreateTexture(nil, "BORDER", nil, 3)
    bBot:SetHeight(1)
    bBot:SetPoint("BOTTOMLEFT", pillShell, "BOTTOMLEFT", 0, 0)
    bBot:SetPoint("BOTTOMRIGHT", pillShell, "BOTTOMRIGHT", 0, 0)
    local bLeft = pillShell:CreateTexture(nil, "BORDER", nil, 3)
    bLeft:SetWidth(1)
    bLeft:SetPoint("TOPLEFT", pillShell, "TOPLEFT", 0, 0)
    bLeft:SetPoint("BOTTOMLEFT", pillShell, "BOTTOMLEFT", 0, 0)
    local bRight = pillShell:CreateTexture(nil, "BORDER", nil, 3)
    bRight:SetWidth(1)
    bRight:SetPoint("TOPRIGHT", pillShell, "TOPRIGHT", 0, 0)
    bRight:SetPoint("BOTTOMRIGHT", pillShell, "BOTTOMRIGHT", 0, 0)
    pillShell.borders = { bTop, bBot, bLeft, bRight }

    local sideBar = pillShell:CreateTexture(nil, "OVERLAY", nil, 2)
    sideBar:SetWidth(3)
    sideBar:SetPoint("TOPRIGHT", pillShell, "TOPRIGHT", -1, -1)
    sideBar:SetPoint("BOTTOMRIGHT", pillShell, "BOTTOMRIGHT", -1, 1)
    sideBar:SetColorTexture(0.96, 0.52, 0.96, 1.0)
    f.sideBar = sideBar

    local topBevel = pillShell:CreateTexture(nil, "BORDER", nil, 1)
    topBevel:SetHeight(1)
    topBevel:SetPoint("TOPLEFT", pillShell, "TOPLEFT", 4, -1)
    topBevel:SetPoint("TOPRIGHT", pillShell, "TOPRIGHT", -4, -1)
    topBevel:SetColorTexture(1, 0.90, 0.68, 0.18)
    f.topBevel = topBevel

    local arrivalFlash = pillShell:CreateTexture(nil, "OVERLAY", nil, 4)
    arrivalFlash:SetPoint("TOPLEFT", pillShell, "TOPLEFT", 1, -1)
    arrivalFlash:SetPoint("BOTTOMRIGHT", pillShell, "BOTTOMRIGHT", -1, 1)
    arrivalFlash:SetTexture(MP_GLOW_TEX)
    arrivalFlash:SetBlendMode("ADD")
    arrivalFlash:SetVertexColor(1, 1, 1, 0)
    arrivalFlash:Hide()
    f.arrivalFlash = arrivalFlash

    local hoverHl = pillShell:CreateTexture(nil, "OVERLAY", nil, 3)
    hoverHl:SetPoint("TOPLEFT", pillShell, "TOPLEFT", 1, -1)
    hoverHl:SetPoint("BOTTOMRIGHT", pillShell, "BOTTOMRIGHT", -1, 1)
    hoverHl:SetColorTexture(1, 0.95, 0.80, 0.07)
    hoverHl:Hide()
    f.hoverHl = hoverHl

    -- Heraldic Circular Sender Avatar / SC Morph Emblem (36x36)
    local avatarBox = CreateFrame("Frame", nil, f)
    avatarBox:SetSize(36, 36)
    avatarBox:SetPoint("LEFT", f, "LEFT", 0, 0)
    avatarBox:EnableMouse(false)
    avatarBox:SetFrameLevel(f:GetFrameLevel() + 5)
    f.avatarBox = avatarBox

    local avatarHalo = avatarBox:CreateTexture(nil, "BACKGROUND", nil, 1)
    avatarHalo:SetSize(48, 48)
    avatarHalo:SetPoint("CENTER")
    avatarHalo:SetTexture(MP_GLOW_TEX)
    avatarHalo:SetVertexColor(0.96, 0.52, 0.96, 0.36)
    f.avatarHalo = avatarHalo

    local avatarRing = avatarBox:CreateTexture(nil, "ARTWORK", nil, 0)
    avatarRing:SetSize(36, 36)
    avatarRing:SetPoint("CENTER")
    avatarRing:SetTexture(MP_WHITE8X8)
    avatarRing:SetVertexColor(0.96, 0.52, 0.96, 0.94)
    MpApplyCircleMask(avatarBox, avatarRing, 36)
    f.avatarRing = avatarRing

    local avatarCore = avatarBox:CreateTexture(nil, "ARTWORK", nil, 1)
    avatarCore:SetSize(32, 32)
    avatarCore:SetPoint("CENTER")
    avatarCore:SetTexture(MP_WHITE8X8)
    avatarCore:SetVertexColor(0.06, 0.08, 0.12, 1.0)
    MpApplyCircleMask(avatarBox, avatarCore, 32)

    local senderIconTex = avatarBox:CreateTexture(nil, "OVERLAY", nil, 2)
    senderIconTex:SetSize(30, 30)
    senderIconTex:SetPoint("CENTER")
    senderIconTex:SetTexture(MP_MAIL_TEX)
    MpApplyCircleMask(avatarBox, senderIconTex, 30)
    f.senderIconTex = senderIconTex

    local scIconTex = avatarBox:CreateTexture(nil, "OVERLAY", nil, 3)
    scIconTex:SetSize(23, 23)
    scIconTex:SetPoint("CENTER")
    scIconTex:SetTexture(ICON_TEX)
    MpApplyCircleMask(avatarBox, scIconTex, 23)
    scIconTex:SetAlpha(0)
    scIconTex:Hide()
    f.scIconTex = scIconTex

    local classPipFrame = CreateFrame("Frame", nil, avatarBox)
    classPipFrame:SetSize(14, 14)
    classPipFrame:SetPoint("BOTTOMRIGHT", avatarBox, "BOTTOMRIGHT", 2, -2)
    classPipFrame:SetFrameLevel(avatarBox:GetFrameLevel() + 4)
    classPipFrame:EnableMouse(false)
    local pipRing = classPipFrame:CreateTexture(nil, "ARTWORK", nil, 0)
    pipRing:SetSize(14, 14)
    pipRing:SetPoint("CENTER")
    pipRing:SetTexture(MP_WHITE8X8)
    pipRing:SetVertexColor(0.10, 0.11, 0.14, 1.0)
    MpApplyCircleMask(classPipFrame, pipRing, 14)
    local classPipTex = classPipFrame:CreateTexture(nil, "OVERLAY", nil, 2)
    classPipTex:SetSize(12, 12)
    classPipTex:SetPoint("CENTER")
    classPipTex:SetTexture(MP_CLASS_TEX)
    MpApplyCircleMask(classPipFrame, classPipTex, 12)
    classPipFrame:Hide()
    f.classPipFrame = classPipFrame
    f.classPipTex = classPipTex

    -- Clipped text viewport so text never squishes or overflows during expand/collapse
    local contentClip = CreateFrame("Frame", nil, f)
    contentClip:SetPoint("TOPLEFT", f, "TOPLEFT", 50, -5)
    contentClip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 5)
    contentClip:EnableMouse(false)
    contentClip:SetFrameLevel(f:GetFrameLevel() + 3)
    if contentClip.SetClipsChildren then contentClip:SetClipsChildren(true) end
    f.contentClip = contentClip

    local queueLbl = contentClip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if ns.Theme and ns.Theme.ApplyReadableCounterFont then
        ns.Theme:ApplyReadableCounterFont(queueLbl, 14, 17, 0, true)
    end
    queueLbl:SetTextColor(1.0, 0.88, 0.34)
    queueLbl:SetPoint("TOPRIGHT", contentClip, "TOPRIGHT", -36, 0)
    queueLbl:SetJustifyH("RIGHT")
    queueLbl:Hide()
    f.queueLbl = queueLbl

    local senderLbl = contentClip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    senderLbl:SetPoint("TOPLEFT", contentClip, "TOPLEFT", 0, -1)
    senderLbl:SetJustifyH("LEFT")
    senderLbl:SetWordWrap(false)
    f.senderLbl = senderLbl

    local headerRule = contentClip:CreateTexture(nil, "BORDER", nil, 2)
    headerRule:SetHeight(1)
    headerRule:SetPoint("TOPLEFT", contentClip, "TOPLEFT", 0, -15)
    headerRule:SetPoint("TOPRIGHT", contentClip, "TOPRIGHT", -36, -15)
    f.headerRule = headerRule

    local previewLbl = contentClip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewLbl:SetPoint("TOPLEFT", contentClip, "TOPLEFT", 0, -18)
    previewLbl:SetHeight(30)
    previewLbl:SetJustifyH("LEFT")
    previewLbl:SetJustifyV("TOP")
    previewLbl:SetWordWrap(true)
    if previewLbl.SetMaxLines then previewLbl:SetMaxLines(2) end
    if previewLbl.SetSpacing then previewLbl:SetSpacing(1) end
    f.previewLbl = previewLbl

    local closeBtn = Theme and Theme:CreateButton(f, 16, 16, "X", "default") or CreateFrame("Button", nil, f)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -5)
    closeBtn:SetFrameLevel(f:GetFrameLevel() + 8)
    closeBtn:SetHitRectInsets(-3, -4, -4, -4)
    closeBtn:SetScript("OnClick", function()
        if f._slot then
            MpBeginCollapseSlot(f._slot)
        end
    end)
    f.closeBtn = closeBtn

    local muteNotifBtn = Theme and Theme:CreateButton(f, 16, 16, "", "default") or CreateFrame("Button", nil, f)
    muteNotifBtn:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
    muteNotifBtn:SetFrameLevel(f:GetFrameLevel() + 8)
    muteNotifBtn:SetHitRectInsets(-3, -2, -4, -4)
    local muteIco = muteNotifBtn:CreateTexture(nil, "OVERLAY", nil, 3)
    muteIco:SetSize(14, 14)
    muteIco:SetPoint("CENTER")
    muteIco:SetTexture(ICON_BELL_OFF)
    muteIco:SetVertexColor(0.95, 0.72, 0.35)
    muteNotifBtn.ico = muteIco
    muteNotifBtn:SetScript("OnClick", function()
        local cur = f._slot and f._slot.item
        if cur and MsgPreview.ShowConfirmMutePopup then
            MsgPreview:ShowConfirmMutePopup(f, cur)
        end
    end)
    muteNotifBtn:SetScript("OnEnter", function(selfBtn)
        if GameTooltip then
            local ownerAnchor = (MsgPreview.sideMode == "LEFT") and "ANCHOR_TOPLEFT" or "ANCHOR_TOPRIGHT"
            GameTooltip:SetOwner(selfBtn, ownerAnchor)
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["Silence this notification"], 1, 0.85, 0.35)
            GameTooltip:AddLine(L["Click to disable this notification (asks confirmation nearby to prevent misclicks)."], 0.85, 0.88, 0.92, true)
            GameTooltip:Show()
        end
    end)
    muteNotifBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.muteNotifBtn = muteNotifBtn

    local progressTrack = pillShell:CreateTexture(nil, "BORDER", nil, 2)
    progressTrack:SetHeight(2)
    progressTrack:SetPoint("BOTTOMLEFT", pillShell, "BOTTOMLEFT", 4, 2)
    progressTrack:SetPoint("BOTTOMRIGHT", pillShell, "BOTTOMRIGHT", -5, 2)
    progressTrack:SetColorTexture(0.05, 0.06, 0.09, 0.85)
    f.progressTrack = progressTrack

    local progressFill = pillShell:CreateTexture(nil, "OVERLAY", nil, 2)
    progressFill:SetHeight(2)
    progressFill:SetPoint("BOTTOMLEFT", pillShell, "BOTTOMLEFT", 4, 2)
    progressFill:SetWidth(MP_MIN_W - 12)
    f.progressFill = progressFill

    local progressTip = pillShell:CreateTexture(nil, "OVERLAY", nil, 4)
    progressTip:SetSize(7, 6)
    progressTip:SetPoint("CENTER", progressFill, "RIGHT", 0, 0)
    progressTip:SetTexture(MP_GLOW_TEX)
    progressTip:SetBlendMode("ADD")
    progressTip:SetVertexColor(1, 0.94, 0.72, 0.90)
    f.progressTip = progressTip

    f:SetScript("OnDragStart", function(self)
        local slot = self._slot
        if not slot or slot.phase == "COLLAPSE" then return end
        local side, _, _, restEdgeX, restCenterY = MpComputeAnchorCoords(self)
        local cardW = MpClamp((slot and slot.targetW) or (self.GetWidth and self:GetWidth()) or MP_MAX_W, MP_MIN_W, MP_MAX_W)
        local curCenterX = (side == "LEFT") and (restEdgeX - (cardW * 0.5)) or (restEdgeX + (cardW * 0.5))
        local curCenterY = restCenterY + (slot.curOffsetY or 0)
        local cx, cy = GetCursorPosition()
        local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if uiScale <= 0 then uiScale = 1 end
        MsgPreview.draggingStack = true
        MsgPreview._dragFrame = self
        MsgPreview.dragOffX = curCenterX - (cx / uiScale)
        MsgPreview.dragOffY = curCenterY - (cy / uiScale)
        MsgPreview.dragCenterX = curCenterX
        MsgPreview.dragCenterY = curCenterY
        self._wasDragged = true
        if GameTooltip then GameTooltip:Hide() end
    end)

    f:SetScript("OnDragStop", function()
        MpFinishStackDrag()
    end)

    f:SetScript("OnClick", function(self, mouseButton)
        if self._wasDragged then
            self._wasDragged = nil
            return
        end
        local slot = self._slot
        local cur = slot and slot.item
        if not cur then return end
        if mouseButton == "RightButton" then
            if MenuUtil and MenuUtil.CreateContextMenu then
                slot.menuPauseUntil = (GetTime and GetTime() or 0) + 8
                local menuSender = tostring(cur.sender or "SocialCentral")
                if Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()
                    and (cur.category == "BN_WHISPER" or cur.bnetAccountID ~= nil or menuSender:find("#", 1, true))
                    and Compat.MaskStreamerBNetName
                then
                    menuSender = Compat.MaskStreamerBNetName(menuSender)
                end
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(menuSender)
                    if cur.threadKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[cur.threadKey] then
                        root:CreateButton(L["Open Conversation"], function()
                            slot.menuPauseUntil = 0
                            MpBeginCollapseSlot(slot)
                            ns:NavigateToModule("chat", { threadKey = cur.threadKey })
                        end)
                    end
                    root:CreateButton(L["Quick Reply in Chat"], function()
                        slot.menuPauseUntil = 0
                        MpBeginCollapseSlot(slot)
                        MpOpenReplyChat(cur)
                    end)
                    if cur.threadKey and ns.Chat and ns.Chat.MarkThreadRead then
                        root:CreateButton(L["Mark Read"], function()
                            slot.menuPauseUntil = 0
                            slot._readDismissed = true
                            ns.Chat:MarkThreadRead(cur.threadKey)
                            MpBeginCollapseSlot(slot)
                        end)
                    end
                    root:CreateDivider()
                    if cur.threadKey and ns.Chat and ns.Chat.PopulateThreadMuteMenu then
                        local muteSub = root:CreateButton(L["Silence Notifications"])
                        ns.Chat:PopulateThreadMuteMenu(muteSub, cur.threadKey, menuSender, function(mutedNow)
                            slot.menuPauseUntil = 0
                            if mutedNow then
                                slot._readDismissed = true
                                MpBeginCollapseSlot(slot)
                            end
                        end)
                    end
                    root:CreateButton(MpCategoryDisableLabel(cur.category), function()
                        slot.menuPauseUntil = 0
                        if MsgPreview.ShowConfirmMutePopup then
                            MsgPreview:ShowConfirmMutePopup(self, cur)
                        end
                    end)
                    root:CreateButton(L["Configure Previews..."], function()
                        slot.menuPauseUntil = 0
                        if ns.Settings and ns.Settings.Open then
                            ns.Settings:Open("notifications", "msgpreview")
                        end
                    end)
                    root:CreateButton(L["Move Preview Position"], function()
                        slot.menuPauseUntil = 0
                        if MsgPreview.ShowAnchorMover then
                            MsgPreview:ShowAnchorMover()
                        end
                    end)
                    local posSub = root:CreateButton(L["Notification & Preview Position"])
                    if posSub and posSub.CreateRadio then
                        for _, opt in ipairs({
                            { id = "minimap", label = L["Beside Minimap"] },
                            { id = "chat_side", label = L["Beside Official Chat"] },
                            { id = "chat_top", label = L["Above Official Chat"] },
                        }) do
                            posSub:CreateRadio(opt.label, function()
                                return MpGetAnchorMode() == opt.id
                            end, function()
                                slot.menuPauseUntil = 0
                                if MinimapBtn.SetPreviewAnchorMode then
                                    MinimapBtn:SetPreviewAnchorMode(opt.id)
                                end
                            end)
                        end
                    end
                    if MpHasCustomPosition() then
                        root:CreateButton(L["Reset Preview Position"], function()
                            slot.menuPauseUntil = 0
                            if MsgPreview.ResetPosition then
                                MsgPreview:ResetPosition()
                            end
                        end)
                    end
                    root:CreateDivider()
                    root:CreateButton(L["Dismiss"], function()
                        slot.menuPauseUntil = 0
                        MpBeginCollapseSlot(slot)
                    end)
                end)
                return
            end
            MpBeginCollapseSlot(slot)
            return
        end
        MpBeginCollapseSlot(slot)
        MpHandlePrimaryClick(cur)
    end)

    f:SetScript("OnEnter", function(self)
        if self.hoverHl then self.hoverHl:Show() end
        local slot = self._slot
        local cur = slot and slot.item
        if not (cur and GameTooltip) then return end
        local rgb = MpChannelRGB(cur)
        local hex = (cur.senderClass and Compat and Compat.ClassHex) and Compat.ClassHex(cur.senderClass) or "|cffffffff"
        local streamerOn = Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()
        local tipSender = tostring(cur.sender or "?")
        if streamerOn and (cur.category == "BN_WHISPER" or cur.bnetAccountID ~= nil or tipSender:find("#", 1, true)) and Compat.MaskStreamerBNetName then
            tipSender = Compat.MaskStreamerBNetName(tipSender)
        end
        local tipBody = cur._fullClean
        if streamerOn and (cur.category == "WHISPER" or cur.category == "BN_WHISPER" or cur.category == "ROOM") then
            tipBody = L["[Hidden in Streamer Mode]"]
        end
        local ownerAnchor = (MsgPreview.sideMode == "LEFT") and "ANCHOR_BOTTOMLEFT" or "ANCHOR_BOTTOMRIGHT"
        GameTooltip:SetOwner(self, ownerAnchor)
        GameTooltip:ClearLines()
        GameTooltip:AddDoubleLine(hex .. tipSender .. "|r", MpChannelLabel(cur), 1, 1, 1, rgb[1], rgb[2], rgb[3])
        if tipBody and tipBody ~= "" then
            GameTooltip:AddLine(tipBody, 0.94, 0.96, 0.99, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Left-click: open conversation  |  Shift+Click: quick reply\nDrag: move previews anywhere  |  Right-click: options"], 0.72, 0.78, 0.86, true)
        GameTooltip:Show()
    end)

    f:SetScript("OnLeave", function(self)
        if self.hoverHl then self.hoverHl:Hide() end
        if GameTooltip then GameTooltip:Hide() end
    end)

    f:HookScript("OnHide", function(self)
        self._wasDragged = nil
        if MsgPreview.draggingStack and MsgPreview._dragFrame == self then
            MpFinishStackDrag()
        end
        if self.hoverHl then self.hoverHl:Hide() end
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)

    MpApplyThemeToPreview(f, true)
    MsgPreview.framePool[poolIdx] = f
    return f
end

local function MpAcquireFreeFrame()
    for i = 1, MP_MAX_SLOTS_CAP do
        local f = MpEnsureSlotFrame(i)
        if not f._slot then
            return f
        end
    end
    return nil
end

local function MpSpawnSlot(item)
    if not item then return false end
    local f = MpAcquireFreeFrame()
    if not f then return false end

    local nextCount = #MsgPreview.activeSlots + 1
    local initialY = MpDesiredSlotOffsetY(nextCount, nextCount)
    f._showQueueCount = 0
    f._lastSide = nil
    f._lastEdgeX = nil
    f._lastCenterY = nil
    f._lastW = nil
    f._lastH = nil
    f._lastFrameA = nil
    f._lastShellA = nil
    f._lastShellVis = nil
    f._lastBarA = nil
    f._lastAvatarPad = nil
    f._lastScA = nil
    f._lastScVis = nil
    f._lastSenderA = nil
    f._lastSenderVis = nil
    f._lastFlashA = nil
    f._lastFlashVis = nil
    f._lastContentA = nil
    f._lastWantClip = nil
    f._lastWantClose = nil
    f._lastWantMute = nil
    f._lastWantProg = nil

    local targetW = MpRenderItemContent(f, item)
    local side, sX, sY, rX, rY, fDist = MpComputeAnchorCoords(f)
    local slot = {
        frame = f,
        item = item,
        phase = "EXPAND",
        phaseTime = 0,
        holdElapsed = 0,
        targetW = targetW,
        curOffsetY = initialY,
        menuPauseUntil = 0,
        _coords = {
            side = side,
            startEdgeX = sX,
            startCenterY = sY,
            restEdgeX = rX,
            restCenterY = rY,
            flightDist = fDist,
        },
    }
    f._slot = slot
    for _, prevSlot in ipairs(MsgPreview.activeSlots) do
        if prevSlot then
            prevSlot._holdVisualsSettled = nil
        end
    end
    table.insert(MsgPreview.activeSlots, slot)
    MpSyncQueueBadges()

    local rgb = MpChannelRGB(item)
    MinimapBtn:PulseArrival(rgb[1], rgb[2], rgb[3])
    MpApplySlotVisuals(slot, 0, 0, 0.05, 1, 0, 0, 0)
    f:Show()

    local drv = MpEnsureDriverFrame()
    MsgPreview._holdAccum = 0
    MsgPreview._animAccum = 0
    if not drv:GetScript("OnUpdate") and MsgPreview._driveAllSlots then
        drv:SetScript("OnUpdate", MsgPreview._driveAllSlots)
    end
    return true
end

local function MpPromoteFromQueue()
    local maxVis = MpGetMaxVisible()
    while #MsgPreview.queue > 0 and #MsgPreview.activeSlots < maxVis do
        local nextItem = table.remove(MsgPreview.queue, 1)
        if not MpSpawnSlot(nextItem) then
            table.insert(MsgPreview.queue, 1, nextItem)
            break
        end
    end
    MpSyncQueueBadges()
end

function MsgPreview._driveAllSlots(_, dt)
    local rawDt = dt or 0
    local active = MsgPreview.activeSlots
    if #active == 0 then
        MsgPreview._holdAccum = 0
        MsgPreview._animAccum = 0
        MpStopAllIdle()
        return
    end

    local totalCount = #active
    local allStationaryHold = not MsgPreview.draggingStack
    if allStationaryHold then
        for idx, slot in ipairs(active) do
            if slot.phase ~= "HOLD" or (not slot._holdVisualsSettled) then
                allStationaryHold = false
                break
            end
            local desiredY = MpDesiredSlotOffsetY(idx, totalCount)
            if math.abs(desiredY - (slot.curOffsetY or desiredY)) > 0.35 then
                allStationaryHold = false
                break
            end
        end
    end
    local delta
    if allStationaryHold then
        MsgPreview._animAccum = 0
        MsgPreview._holdAccum = (MsgPreview._holdAccum or 0) + rawDt
        if MsgPreview._holdAccum < 0.066 then
            return
        end
        delta = math.min(MsgPreview._holdAccum, 0.12)
        MsgPreview._holdAccum = 0
    else
        MsgPreview._holdAccum = 0
        MsgPreview._animAccum = (MsgPreview._animAccum or 0) + rawDt
        if not MsgPreview.draggingStack and MsgPreview._animAccum < 0.033 then
            return
        end
        delta = math.min(MsgPreview._animAccum, 0.066)
        MsgPreview._animAccum = 0
    end

    local setupOpen = MsgPreview.setupModal and MsgPreview.setupModal:IsShown()
    local moverOpen = MsgPreview.anchorMover and MsgPreview.anchorMover:IsShown()
    local confirmOpen = MsgPreview.confirmPopup and MsgPreview.confirmPopup:IsShown()
    if MsgPreview.draggingStack then
        if not (IsMouseButtonDown and IsMouseButtonDown("LeftButton")) then
            MpFinishStackDrag()
        else
            local cx, cy = GetCursorPosition()
            local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            if uiScale <= 0 then uiScale = 1 end
            MsgPreview.dragCenterX, MsgPreview.dragCenterY = MpClampCenterToScreen((cx / uiScale) + (MsgPreview.dragOffX or 0), (cy / uiScale) + (MsgPreview.dragOffY or 0))
        end
    end
    local nowMono = GetTime and GetTime() or 0
    local finishedIndices = nil

    for idx, slot in ipairs(active) do
        local f = slot.frame
        -- Smoothly glide non-collapsing slots vertically whenever a slot above closes or a new slot joins below
        local yChanged = false
        if slot.phase ~= "COLLAPSE" then
            local desiredY = MpDesiredSlotOffsetY(idx, totalCount)
            local prevY = slot.curOffsetY or desiredY
            local diff = desiredY - prevY
            if math.abs(diff) > 0.35 then
                slot.curOffsetY = prevY + diff * math.min(1, delta * 14)
                yChanged = true
            elseif slot.curOffsetY ~= desiredY then
                slot.curOffsetY = desiredY
                yChanged = true
            elseif slot._coords and f and f._lastCenterY then
                local expectedCenterY = math.floor((slot._coords.restCenterY + desiredY) + 0.5)
                if f._lastCenterY ~= expectedCenterY then
                    yChanged = true
                end
            end
        end
        if yChanged then
            slot._holdVisualsSettled = nil
        end

        if slot.phase == "EXPAND" then
            slot.phaseTime = slot.phaseTime + delta
            local expDur = MpGetExpandDuration(slot.lastFlightDist)
            local t = MpClamp(slot.phaseTime / expDur, 0, 1)
            local moveP = MpEaseOutCubic(MpClamp(t / 0.72, 0, 1))
            local sizeP = MpEaseOutCubic(MpClamp((t - 0.14) / 0.86, 0, 1))
            local frameAlpha = MpClamp(t / 0.22, 0, 1)
            local scAlpha = 1 - MpClamp((t - 0.10) / 0.38, 0, 1)
            local senderAlpha = MpClamp((t - 0.18) / 0.40, 0, 1)
            local contentAlpha = MpClamp((t - 0.42) / 0.58, 0, 1)
            local flashAlpha = (t > 0.16) and (math.sin(((t - 0.16) / 0.84) * math.pi) * 0.24) or 0
            MpApplySlotVisuals(slot, moveP, sizeP, frameAlpha, scAlpha, senderAlpha, contentAlpha, flashAlpha)
            if t >= 1 then
                slot.phase = "HOLD"
                slot.phaseTime = 0
                slot.holdElapsed = 0
                slot._holdVisualsSettled = nil
                slot._lastHoldProgW = nil
                MpApplySlotVisuals(slot, 1, 1, 1, 0, 1, 1, 0)
                if f and f.progressFill then
                    f.progressFill:SetWidth(math.max(1, (slot.targetW or MP_MIN_W) - 11))
                end
            end
        elseif slot.phase == "HOLD" then
            if (not slot._holdVisualsSettled) or MsgPreview.draggingStack then
                slot._holdVisualsSettled = true
                MpApplySlotVisuals(slot, 1, 1, 1, 0, 1, 1, 0)
            end
            local menuPaused = nowMono < (slot.menuPauseUntil or 0)
            local hovered = f and (f:IsMouseOver() or (f.closeBtn and f.closeBtn:IsMouseOver()) or (f.muteNotifBtn and f.muteNotifBtn:IsMouseOver()))
            local totalDur = (slot.item and slot.item.duration) or MpGetHoldDuration()

            if not setupOpen and not moverOpen and not confirmOpen and not MsgPreview.draggingStack and not hovered and not menuPaused then
                slot.holdElapsed = slot.holdElapsed + delta
                local remFrac = MpClamp(1 - (slot.holdElapsed / totalDur), 0, 1)
                if f and f.progressFill then
                    local pw = math.max(1, ((slot.targetW or MP_MIN_W) - 11) * remFrac)
                    if math.abs((slot._lastHoldProgW or -99) - pw) >= 0.5 then
                        slot._lastHoldProgW = pw
                        f.progressFill:SetWidth(pw)
                    end
                end
                if slot.holdElapsed >= totalDur then
                    slot.phase = "COLLAPSE"
                    slot.phaseTime = 0
                    slot._holdVisualsSettled = nil
                end
            end
        elseif slot.phase == "COLLAPSE" then
            slot.phaseTime = slot.phaseTime + delta
            local colDur = MpGetCollapseDuration(slot.lastFlightDist)
            local t = MpClamp(slot.phaseTime / colDur, 0, 1)
            local contentAlpha = 1 - MpClamp(t / 0.28, 0, 1)
            local sizeP = 1 - MpEaseInOutCubic(MpClamp(t / 0.56, 0, 1))
            local senderAlpha = 1 - MpClamp((t - 0.26) / 0.28, 0, 1)
            local scAlpha = MpClamp((t - 0.34) / 0.24, 0, 1)
            local moveP = 1 - MpEaseInOutCubic(MpClamp((t - 0.44) / 0.56, 0, 1))
            local frameAlpha = 1 - MpClamp((t - 0.80) / 0.20, 0, 1)
            MpApplySlotVisuals(slot, moveP, sizeP, frameAlpha, scAlpha, senderAlpha, contentAlpha, 0)
            if t >= 1 then
                finishedIndices = finishedIndices or {}
                finishedIndices[#finishedIndices + 1] = idx
            end
        end
    end

    if finishedIndices then
        for i = #finishedIndices, 1, -1 do
            local rmIdx = finishedIndices[i]
            local doneSlot = table.remove(active, rmIdx)
            if doneSlot then
                local rgb = MpChannelRGB(doneSlot.item)
                if doneSlot.frame then
                    doneSlot.frame._slot = nil
                    doneSlot.frame:Hide()
                end
                if not doneSlot._readDismissed then
                    MinimapBtn:PulseArrival(rgb[1], rgb[2], rgb[3])
                    MinimapBtn:NotePreviewFolded(doneSlot.item)
                end
            end
        end
        MpPromoteFromQueue()
        for _, remSlot in ipairs(active) do
            if remSlot then
                remSlot._holdVisualsSettled = nil
            end
        end
        if #active == 0 then
            MpStopAllIdle()
        end
    end
end

function MsgPreview:PushItem(item, forceShow)
    if type(item) ~= "table" then return end
    local snippet, fullClean
    if item._snippet and item._fullClean then
        snippet, fullClean = item._snippet, item._fullClean
    else
        snippet, fullClean = MpCleanPreviewText(item.text)
    end
    if not snippet or snippet == "" then return end

    local copy = {}
    for k, v in pairs(item) do
        copy[k] = v
    end
    copy._snippet = snippet
    copy._fullClean = fullClean
    copy.coalescedCount = (type(item.coalescedCount) == "number" and item.coalescedCount > 1) and item.coalescedCount or 1

    if not forceShow then
        local cKey = MpCoalesceKey(copy)
        for _, slot in ipairs(self.activeSlots) do
            if slot.phase ~= "COLLAPSE" and MpCoalesceKey(slot.item) == cKey then
                slot.item.text = copy.text
                slot.item._snippet = copy._snippet
                slot.item._fullClean = copy._fullClean
                slot.item.sender = copy.sender or slot.item.sender
                slot.item.senderClass = copy.senderClass or slot.item.senderClass
                slot.item.coalescedCount = (slot.item.coalescedCount or 1) + copy.coalescedCount
                slot.holdElapsed = 0
                if slot.frame and slot.frame:IsShown() then
                    slot.targetW = MpRenderItemContent(slot.frame, slot.item)
                    if slot.phase == "HOLD" then
                        MpApplySlotVisuals(slot, 1, 1, 1, 0, 1, 1)
                        if slot.frame.progressFill then
                            slot.frame.progressFill:SetWidth(math.max(1, (slot.targetW or MP_MIN_W) - 11))
                        end
                    end
                end
                return
            end
        end

        for _, qItem in ipairs(self.queue) do
            if MpCoalesceKey(qItem) == cKey then
                qItem.text = copy.text
                qItem._snippet = copy._snippet
                qItem._fullClean = copy._fullClean
                qItem.sender = copy.sender or qItem.sender
                qItem.senderClass = copy.senderClass or qItem.senderClass
                qItem.coalescedCount = (qItem.coalescedCount or 1) + copy.coalescedCount
                return
            end
        end
    end

    local maxVis = MpGetMaxVisible()
    if #self.activeSlots < maxVis then
        if MpSpawnSlot(copy) then
            return
        end
    end

    -- Slot limit reached (e.g. 3 visible): enqueue FIFO so 4th+ smoothly rises up once top preview expires!
    if (copy.priority or 1) >= 2 and not forceShow then
        local inserted = false
        for i, qItem in ipairs(self.queue) do
            if (qItem.priority or 1) < 2 then
                table.insert(self.queue, i, copy)
                inserted = true
                break
            end
        end
        if not inserted then
            table.insert(self.queue, copy)
        end
    else
        table.insert(self.queue, copy)
    end
    while #self.queue > MP_MAX_QUEUE do
        table.remove(self.queue, #self.queue)
    end
    MpSyncQueueBadges()
end

function MsgPreview:Dismiss(instant)
    wipe(self.queue)
    if instant then
        MpStopAllIdle()
    else
        MpBeginCollapseAll(true)
    end
end

local function MpBuildSampleItem(variant, sampleIdx)
    local resolvedSelf = Compat and Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myName = (resolvedSelf and resolvedSelf.fullName) or (ns.Safe and ns.Safe.String(ns.Safe.Call(UnitName, "player"))) or "SocialCentral"
    local myClass = nil
    if ns.Safe and ns.Safe.Call then
        local _, rawCls = ns.Safe.Call(UnitClass, "player")
        myClass = rawCls
    end
    local myGuid = ns.Safe and ns.Safe.String(ns.Safe.Call(UnitGUID, "player")) or nil
    local v = type(variant) == "string" and variant:lower():match("^%s*(.-)%s*$") or ""
    local idx = sampleIdx or 1

    if v == "bnet" or v == "battlenet" then
        return {
            id = "test:mp:bnet:" .. tostring(idx),
            category = "BN_WHISPER",
            channelKind = "BN_WHISPER",
            sender = (idx == 1) and myName or "Lyra Dawn",
            senderCharName = (idx == 1) and myName or "Lyra Dawn",
            senderGuid = (idx == 1) and myGuid or nil,
            senderClass = (idx == 1) and (myClass or "MAGE") or "MAGE",
            text = L["Hey! Free for a quick dungeon run right now?"],
            priority = 2,
            isTestPreview = (idx == 1),
        }
    elseif v == "group" or v == "party" or v == "raid" then
        return {
            id = (v == "raid" and "test:mp:raid:" or "test:mp:group:") .. tostring(idx),
            category = "GROUP",
            channelKind = (v == "raid") and "RAID" or "PARTY",
            sender = (idx == 1) and myName or "Kael Ironfist",
            senderCharName = (idx == 1) and myName or "Kael Ironfist",
            senderGuid = (idx == 1) and myGuid or nil,
            senderClass = (idx == 1) and (myClass or "WARRIOR") or "WARRIOR",
            text = L["Ready check! Summoning everyone at the dungeon entrance."],
            replySlash = (v == "raid") and "/ra " or "/p ",
            priority = 1,
            isTestPreview = (idx == 1),
        }
    elseif v == "guild" then
        return {
            id = "test:mp:guild:" .. tostring(idx),
            category = "GUILD",
            channelKind = "GUILD",
            sender = (idx == 1) and myName or "Mira Vale",
            senderCharName = (idx == 1) and myName or "Mira Vale",
            senderGuid = (idx == 1) and myGuid or nil,
            senderClass = (idx == 1) and (myClass or "PRIEST") or "PRIEST",
            text = L["Anyone in the guild need Stratholme or Scholomance?"],
            replySlash = "/g ",
            priority = 1,
            isTestPreview = (idx == 1),
        }
    elseif v == "room" or v == "alliance" then
        return {
            id = "test:mp:room:" .. tostring(idx),
            category = "ROOM",
            channelKind = (v == "alliance") and "ALLIANCE" or "ROOM",
            sender = (idx == 1) and myName or "Arden Light",
            senderCharName = (idx == 1) and myName or "Arden Light",
            senderGuid = (idx == 1) and myGuid or nil,
            senderClass = (idx == 1) and (myClass or "PALADIN") or "PALADIN",
            roomTitle = L["Private Room"],
            text = L["Meeting in town in 5 minutes before heading out!"],
            priority = 1,
            isTestPreview = (idx == 1),
        }
    end
    return {
        id = "test:mp:whisper:" .. tostring(idx),
        category = "WHISPER",
        channelKind = "WHISPER",
        sender = (idx == 1) and myName or ("Thalor Valen " .. tostring(idx)),
        senderCharName = (idx == 1) and myName or "Thalor Valen",
        senderGuid = (idx == 1) and myGuid or nil,
        senderClass = (idx == 1) and (myClass or "ROGUE") or "ROGUE",
        text = L["Hey! Saw you online — want to group up for a dungeon?"],
        priority = 2,
        isTestPreview = (idx == 1),
    }
end

function MsgPreview:ShowFirstTimePrompt(sampleItem, fromManualTrigger)
    if MpIsInCombat() then
        self.pendingPromptItem = sampleItem or true
        return
    end
    local Theme = ns.Theme
    local m = self.setupModal
    if not m then
        m = CreateFrame("Frame", "SocialCentralMsgPreviewSetupModal", UIParent, "BackdropTemplate")
        m:Hide()
        m:SetSize(486, 344)
        m:SetPoint("CENTER")
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(865)
        m:SetToplevel(true)
        m:EnableMouse(true)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        if Theme and Theme.MakeMovable then
            Theme:MakeMovable(m, { key = "modal_msg_preview_setup" })
        end
        if type(UISpecialFrames) == "table" then
            table.insert(UISpecialFrames, "SocialCentralMsgPreviewSetupModal")
        end

        local solidBg = m:CreateTexture(nil, "BACKGROUND", nil, -8)
        solidBg:SetAllPoints(m)
        solidBg:SetTexture(MP_WHITE8X8)
        solidBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
        m._solidOpaqueBg = solidBg

        local ico = m:CreateTexture(nil, "OVERLAY")
        ico:SetSize(18, 18)
        ico:SetPoint("TOPLEFT", 14, -12)
        ico:SetTexture(ICON_TEX)

        local closeBtn = Theme and Theme:CreateButton(m, 22, 20, "X", "default")
        closeBtn:SetPoint("TOPRIGHT", -10, -10)
        closeBtn:SetScript("OnClick", function()
            MsgPreview.sessionPromptDismissed = true
            m:Hide()
            local holdDur = MpGetHoldDuration()
            for _, slot in ipairs(MsgPreview.activeSlots) do
                if slot.phase == "HOLD" then
                    slot.holdElapsed = math.max(0, holdDur - 2.0)
                end
            end
        end)
        m.closeBtn = closeBtn

        local helpBtn = Theme and Theme:CreateHelpButton(
            m,
            L["Help: Minimap Message Preview Setup"],
            L["Shows a compact animated preview with the sender's icon and opening words on the left side of your Minimap whenever a matching message arrives, then closes back into the SC icon."],
            L["Choose which message types should trigger previews and whether to automatically silence them inside Dungeons, Raids, Battlegrounds, or Combat. You can change this anytime in Settings -> Notifications."]
        )
        if helpBtn then
            helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
            m.helpBtn = helpBtn
        end

        local titleFs = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        titleFs:SetPoint("LEFT", ico, "RIGHT", 8, 0)
        titleFs:SetPoint("RIGHT", helpBtn or closeBtn, "LEFT", -6, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        titleFs:SetText(L["Minimap Message Previews"])
        m.titleFs = titleFs

        local bodyFs = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        bodyFs:SetPoint("TOPLEFT", 16, -40)
        bodyFs:SetPoint("TOPRIGHT", -16, -40)
        bodyFs:SetJustifyH("LEFT")
        bodyFs:SetWordWrap(true)
        bodyFs:SetText(L["You received a message! Would you like SocialCentral to briefly expand a message preview with the sender's icon beside the Minimap? Choose which channels to show:"])
        m.bodyFs = bodyFs

        local chanBox = CreateFrame("Frame", nil, m, "BackdropTemplate")
        chanBox:SetPoint("TOPLEFT", 16, -96)
        chanBox:SetPoint("TOPRIGHT", -16, -96)
        chanBox:SetHeight(82)
        m.chanBox = chanBox

        local function MakeModalCheck(parent, xOff, yOff, labelText, widthLim)
            local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, yOff)
            local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            lbl:SetWidth(widthLim or 190)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(true)
            lbl:SetText(labelText)
            cb.lbl = lbl
            return cb
        end

        m.cbWhispers = MakeModalCheck(chanBox, 8, -8, L["Whispers & Direct Chat"], 186)
        m.cbBNet = MakeModalCheck(chanBox, 232, -8, L["Battle.net Friends"], 186)
        m.cbGroup = MakeModalCheck(chanBox, 8, -36, L["Group / Raid Chat"], 186)
        m.cbGuild = MakeModalCheck(chanBox, 232, -36, L["Guild / Officer Chat"], 186)

        local chanWarnFs = chanBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        chanWarnFs:SetPoint("BOTTOMLEFT", 12, 6)
        chanWarnFs:SetPoint("BOTTOMRIGHT", -12, 6)
        chanWarnFs:SetJustifyH("LEFT")
        chanWarnFs:SetWordWrap(false)
        chanWarnFs:SetText(L["Select at least one channel above, or click 'No, Disable'."])
        chanWarnFs:Hide()
        m.chanWarnFs = chanWarnFs

        local ctxBox = CreateFrame("Frame", nil, m, "BackdropTemplate")
        ctxBox:SetPoint("TOPLEFT", chanBox, "BOTTOMLEFT", 0, -8)
        ctxBox:SetPoint("TOPRIGHT", chanBox, "BOTTOMRIGHT", 0, -8)
        ctxBox:SetHeight(64)
        m.ctxBox = ctxBox

        m.cbInst = MakeModalCheck(ctxBox, 8, -8, L["Do not show inside Dungeons, Raids & Battlegrounds"], 408)
        m.cbCombat = MakeModalCheck(ctxBox, 8, -36, L["Do not show while in combat"], 408)

        local btnSettings = Theme:CreateButton(m, 114, 26, L["More Settings..."], "default")
        Theme:AutoFitButton(btnSettings, 96, 16, 150)
        btnSettings:SetPoint("BOTTOMLEFT", 16, 34)
        m.btnSettings = btnSettings

        local btnEnable = Theme:CreateButton(m, 168, 26, L["Enable Previews"], "primary")
        Theme:AutoFitButton(btnEnable, 134, 18, 200)
        btnEnable:SetPoint("BOTTOMRIGHT", -16, 34)
        m.btnEnable = btnEnable

        local btnDisable = Theme:CreateButton(m, 144, 26, L["No, Disable"], "default")
        Theme:AutoFitButton(btnDisable, 116, 16, 180)
        btnDisable:SetPoint("RIGHT", btnEnable, "LEFT", -8, 0)
        m.btnDisable = btnDisable

        btnSettings:SetScript("OnClick", function()
            m:Hide()
            if ns.Settings and ns.Settings.Open then
                ns.Settings:Open("notifications", "msgpreview")
            end
        end)

        local function SyncEnableState()
            local anyOn = (m.cbWhispers:GetChecked() == true)
                or (m.cbBNet:GetChecked() == true)
                or (m.cbGroup:GetChecked() == true)
                or (m.cbGuild:GetChecked() == true)
            btnEnable:SetEnabled(anyOn)
            btnEnable:SetAlpha(anyOn and 1.0 or 0.45)
            chanWarnFs:SetShown(not anyOn)
        end
        for _, cb in ipairs({ m.cbWhispers, m.cbBNet, m.cbGroup, m.cbGuild }) do
            cb:SetScript("OnClick", SyncEnableState)
        end
        m.SyncEnableState = SyncEnableState

        btnEnable:SetScript("OnClick", function()
            local s = ns.db and ns.db.settings
            if s then
                s.msgPreviewEnabled = true
                s.msgPreviewPromptAnswered = true
                if ns.SetAccountTutorialShown then
                    ns:SetAccountTutorialShown("msgPreviewPromptAnswered", true)
                end
                s.msgPreviewWhispers = (m.cbWhispers:GetChecked() == true)
                s.msgPreviewBNet = (m.cbBNet:GetChecked() == true)
                s.msgPreviewGroup = (m.cbGroup:GetChecked() == true)
                s.msgPreviewGuild = (m.cbGuild:GetChecked() == true)
                if ns.Chat and ns.Chat.UnmuteChannelKeysForSetting then
                    if s.msgPreviewGroup then
                        ns.Chat:UnmuteChannelKeysForSetting("msgPreviewGroup")
                    end
                    if s.msgPreviewGuild then
                        ns.Chat:UnmuteChannelKeysForSetting("msgPreviewGuild")
                    end
                end
                local instOff = (m.cbInst:GetChecked() == true)
                s.msgPreviewSilenceDungeons = instOff
                s.msgPreviewSilenceRaids = instOff
                s.msgPreviewSilencePvP = instOff
                s.msgPreviewSilenceCombat = (m.cbCombat:GetChecked() == true)
            end
            MsgPreview.sessionPromptDismissed = false
            m:Hide()
            ns:Emit("SETTINGS_UPDATED")
            if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
            ns:Print("%s", L["Minimap Message Previews enabled! Change channels or dungeon/raid filters anytime in Settings -> Notifications."])
            local holdDur = MpGetHoldDuration()
            for _, slot in ipairs(MsgPreview.activeSlots) do
                if slot.phase == "HOLD" then
                    slot.holdElapsed = math.max(0, holdDur - 2.2)
                end
            end
        end)

        btnDisable:SetScript("OnClick", function()
            local s = ns.db and ns.db.settings
            if s then
                s.msgPreviewEnabled = false
                s.msgPreviewPromptAnswered = true
                if ns.SetAccountTutorialShown then
                    ns:SetAccountTutorialShown("msgPreviewPromptAnswered", true)
                end
            end
            MsgPreview.sessionPromptDismissed = false
            m:Hide()
            MpBeginCollapseAll(true)
            ns:Emit("SETTINGS_UPDATED")
            if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
            ns:Print("%s", L["Minimap Message Previews disabled. You can re-enable them anytime in Settings -> Notifications."])
        end)

        local tipFs = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tipFs:SetPoint("BOTTOMLEFT", 16, 12)
        tipFs:SetPoint("BOTTOMRIGHT", -16, 12)
        tipFs:SetJustifyH("LEFT")
        tipFs:SetWordWrap(false)
        tipFs:SetText(L["You can customize channels, duration, and dungeon/raid rules anytime in Settings -> Notifications."])
        m.tipFs = tipFs

        self.setupModal = m
    end

    local s = ns.db and ns.db.settings
    m.cbWhispers:SetChecked((not s) or s.msgPreviewWhispers ~= false)
    m.cbBNet:SetChecked((not s) or s.msgPreviewBNet ~= false)
    m.cbGroup:SetChecked(s and s.msgPreviewGroup == true or false)
    m.cbGuild:SetChecked(s and s.msgPreviewGuild == true or false)
    local instChecked = (not s) or (s.msgPreviewSilenceDungeons ~= false) or (s.msgPreviewSilenceRaids ~= false)
    m.cbInst:SetChecked(instChecked)
    m.cbCombat:SetChecked((not s) or (s.msgPreviewSilenceCombat ~= false))
    if m.SyncEnableState then m.SyncEnableState() end

    local p = Theme and Theme.GetPalette and Theme:GetPalette()
    if Theme and Theme.PrepareTopOverlayModal then
        Theme:PrepareTopOverlayModal(m, 865)
    else
        m:SetParent(UIParent)
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(865)
        m:SetToplevel(true)
    end
    if m._solidOpaqueBg then
        local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
        m._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
    end
    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(m, "window", p)
        Theme:ApplyBackdrop(m.chanBox, "surface", p)
        Theme:ApplyBackdrop(m.ctxBox, "surface", p)
    end
    local baseLvl = (m.GetFrameLevel and m:GetFrameLevel()) or 865
    if m.chanBox then m.chanBox:SetFrameLevel(baseLvl + 2) end
    if m.ctxBox then m.ctxBox:SetFrameLevel(baseLvl + 2) end
    if Theme and Theme.StyleButton then
        Theme:StyleButton(m.closeBtn, "default")
        if m.btnSettings then Theme:StyleButton(m.btnSettings, "default") end
        Theme:StyleButton(m.btnEnable, "primary")
        Theme:StyleButton(m.btnDisable, "default")
        if Theme.SyncButtonLayers then
            Theme:SyncButtonLayers(m.closeBtn)
            if m.btnSettings then Theme:SyncButtonLayers(m.btnSettings) end
            Theme:SyncButtonLayers(m.btnEnable)
            Theme:SyncButtonLayers(m.btnDisable)
            if m.helpBtn then
                if m.helpBtn.RefreshTheme then m.helpBtn:RefreshTheme() end
                Theme:SyncButtonLayers(m.helpBtn)
            end
        end
    end

    -- Show the live preview right beside the Minimap (paused while modal is open) so the player sees it immediately
    if #self.activeSlots == 0 then
        self:PushItem(sampleItem or MpBuildSampleItem("whisper", 1), true)
    end

    m:Show()
    if m.Raise then m:Raise() end
end

function MsgPreview:SyncAnchorMoverPosition()
    local m = self.anchorMover
    if not m then return end
    local uiW = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1280
    local uiH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 720
    local side, _, _, restEdgeX, restCenterY = MpComputeAnchorCoords(m)
    local cx = (side == "LEFT") and (restEdgeX - (MP_MAX_W * 0.5)) or (restEdgeX + (MP_MAX_W * 0.5))
    local cy = restCenterY
    cx, cy = MpClampCenterToScreen(cx, cy)
    m:ClearAllPoints()
    m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
    if m.ctrlBar then
        m.ctrlBar:ClearAllPoints()
        if cy < 135 then
            m.ctrlBar:SetPoint("BOTTOM", m, "TOP", 0, 4)
        else
            m.ctrlBar:SetPoint("TOP", m, "BOTTOM", 0, -4)
        end
    end
end

function MsgPreview:ResetPosition(silent)
    if ns.Theme and ns.Theme.ClearSavedWindowPosition then
        ns.Theme:ClearSavedWindowPosition(MP_POS_KEY, true)
    elseif ns.db and type(ns.db.windowPositions) == "table" then
        ns.db.windowPositions[MP_POS_KEY] = nil
    end
    self.draggingStack = false
    self.dragCenterX = nil
    self.dragCenterY = nil
    self:SyncAnchorMoverPosition()
    for _, slot in ipairs(self.activeSlots) do
        slot._coords = nil
        if slot.phase == "HOLD" then
            MpApplySlotVisuals(slot, 1, 1, 1, 0, 1, 1, 0)
        end
    end
    if not silent then
        local mMode = MpGetAnchorMode()
        if mMode == "chat_side" then
            ns:Print("%s", L["Message preview position reset beside Official Chat."])
        elseif mMode == "chat_top" then
            ns:Print("%s", L["Message preview position reset above Official Chat."])
        else
            ns:Print("%s", L["Message preview position reset beside Minimap."])
        end
    end
end

function MinimapBtn:GetPreviewAnchorMode()
    return MpGetAnchorMode()
end

function MinimapBtn:SetPreviewAnchorMode(mode)
    local clean = (mode == "chat_side" or mode == "chat_top") and mode or "minimap"
    if ns.db and ns.db.settings then
        ns.db.settings.msgPreviewAnchor = clean
    end
    if ns.Theme and ns.Theme.ClearSavedWindowPosition then
        ns.Theme:ClearSavedWindowPosition(MP_POS_KEY, true)
        ns.Theme:ClearSavedWindowPosition("notification_toast", true)
    elseif ns.db and type(ns.db.windowPositions) == "table" then
        ns.db.windowPositions[MP_POS_KEY] = nil
        ns.db.windowPositions["notification_toast"] = nil
    end
    MsgPreview:ResetPosition(true)
    if ns.NotificationToast and ns.NotificationToast.RefreshAnchorMode then
        ns.NotificationToast:RefreshAnchorMode()
    end
    ns:Emit("SETTINGS_UPDATED")
    if ns.Settings and ns.Settings.Refresh then
        ns.Settings:Refresh()
    end
end

function MsgPreview:HideAnchorMover(runQuickDemo)
    if self.anchorMover then
        self.anchorMover:Hide()
    end
    if runQuickDemo and #self.activeSlots == 0 then
        self:ShowTestPreview("whisper")
    end
end

function MsgPreview:ShowAnchorMover()
    local Theme = ns.Theme
    local m = self.anchorMover
    if not m then
        local totalH = (MP_HEIGHT * MP_MAX_SLOTS_CAP) + (MP_SLOT_GAP * (MP_MAX_SLOTS_CAP - 1))
        m = CreateFrame("Frame", "SocialCentralMsgPreviewAnchor", UIParent, "BackdropTemplate")
        m:Hide()
        m:SetSize(MP_MAX_W, totalH)
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(235)
        m:SetToplevel(true)
        m:SetMovable(true)
        m:EnableMouse(true)
        m:SetClampedToScreen(true)
        m:RegisterForDrag("LeftButton")
        if type(UISpecialFrames) == "table" then
            table.insert(UISpecialFrames, "SocialCentralMsgPreviewAnchor")
        end

        local solidBg = m:CreateTexture(nil, "BACKGROUND", nil, -8)
        solidBg:SetAllPoints(m)
        solidBg:SetTexture(MP_WHITE8X8)
        solidBg:SetVertexColor(0.08, 0.09, 0.12, 1.0)
        m._solidOpaqueBg = solidBg

        local slotSpecs = {
            { tone = "whisper", label = "1 · " .. L["Whisper"] },
            { tone = "group",   label = "2 · " .. L["Group"] },
            { tone = "guild",   label = "3 · " .. L["Guild"] .. "  (+N)" },
        }
        m.slotCards = {}
        for i = 1, MP_MAX_SLOTS_CAP do
            local sp = slotSpecs[i]
            local toneSpec = Theme and Theme.GetChatToneSpec and Theme:GetChatToneSpec(sp.tone)
            local card = CreateFrame("Frame", nil, m, "BackdropTemplate")
            card:SetSize(MP_MAX_W - 6, MP_HEIGHT - 2)
            card:SetPoint("TOP", m, "TOP", 0, -((i - 1) * MP_SLOT_PITCH) - 1)
            card:EnableMouse(false)
            card:SetFrameLevel(m:GetFrameLevel() + 2)
            if card.SetBackdrop then
                card:SetBackdrop({
                    bgFile = MP_WHITE8X8,
                    edgeFile = MP_WHITE8X8,
                    edgeSize = 1,
                })
                local bgc = (toneSpec and toneSpec.cardBgTop) or { 0.16, 0.16, 0.22, 1.0 }
                local bdc = (toneSpec and toneSpec.cardBorder) or { 0.90, 0.74, 0.26, 1.0 }
                card:SetBackdropColor(bgc[1], bgc[2], bgc[3], 1.0)
                card:SetBackdropBorderColor(bdc[1], bdc[2], bdc[3], 1.0)
            end
            local bar = card:CreateTexture(nil, "OVERLAY", nil, 2)
            bar:SetWidth(3)
            bar:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
            bar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 1)
            local ac = (toneSpec and toneSpec.accent) or { 1, 0.85, 0.35 }
            bar:SetColorTexture(ac[1], ac[2], ac[3], 1.0)

            local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -9)
            title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -9)
            title:SetJustifyH("LEFT")
            title:SetTextColor(1, 0.95, 0.82)
            title:SetText(sp.label)

            local hint = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            hint:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 9)
            hint:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 9)
            hint:SetJustifyH("LEFT")
            hint:SetTextColor(0.90, 0.93, 0.98)
            hint:SetText(i == 2 and L["Drag anywhere on screen"] or L["Returns to SC Minimap icon"])
            m.slotCards[i] = card
        end

        local ctrlBar = CreateFrame("Frame", nil, m, "BackdropTemplate")
        ctrlBar:SetSize(MP_MAX_W, 30)
        ctrlBar:SetPoint("TOP", m, "BOTTOM", 0, -4)
        ctrlBar:SetFrameLevel(m:GetFrameLevel() + 4)
        local barBg = ctrlBar:CreateTexture(nil, "BACKGROUND", nil, -8)
        barBg:SetAllPoints(ctrlBar)
        barBg:SetTexture(MP_WHITE8X8)
        barBg:SetVertexColor(0.08, 0.09, 0.12, 1.0)
        ctrlBar._solidOpaqueBg = barBg
        if Theme and Theme.ApplyBackdrop then
            Theme:ApplyBackdrop(ctrlBar, "surface")
        elseif ctrlBar.SetBackdrop then
            ctrlBar:SetBackdrop({
                bgFile = MP_WHITE8X8,
                edgeFile = MP_WHITE8X8,
                edgeSize = 1,
            })
            ctrlBar:SetBackdropColor(0.08, 0.09, 0.12, 1.0)
            ctrlBar:SetBackdropBorderColor(0.92, 0.74, 0.24, 1.0)
        end

        local doneBtn = Theme and Theme:CreateButton(ctrlBar, 74, 22, L["Done"], "primary") or CreateFrame("Button", nil, ctrlBar)
        if Theme and Theme.AutoFitButton then
            Theme:AutoFitButton(doneBtn, 62, 10, 80)
        end
        doneBtn:SetPoint("LEFT", ctrlBar, "LEFT", 6, 0)
        doneBtn:SetScript("OnClick", function()
            MsgPreview:HideAnchorMover(true)
        end)

        local testBtn = Theme and Theme:CreateButton(ctrlBar, 84, 22, L["Test Queue (4)"], "default") or CreateFrame("Button", nil, ctrlBar)
        if Theme and Theme.AutoFitButton then
            Theme:AutoFitButton(testBtn, 72, 10, 96)
        end
        testBtn:SetPoint("CENTER", ctrlBar, "CENTER", 0, 0)
        testBtn:SetScript("OnClick", function()
            MsgPreview:HideAnchorMover(false)
            MsgPreview:ShowTestPreview("queue")
        end)

        local resetBtn = Theme and Theme:CreateButton(ctrlBar, 60, 22, L["Reset"], "default") or CreateFrame("Button", nil, ctrlBar)
        if Theme and Theme.AutoFitButton then
            Theme:AutoFitButton(resetBtn, 52, 8, 66)
        end
        resetBtn:SetPoint("RIGHT", ctrlBar, "RIGHT", -28, 0)
        resetBtn:SetScript("OnClick", function()
            MsgPreview:ResetPosition()
        end)

        if Theme and Theme.CreateHelpButton then
            local moverHelp = Theme:CreateHelpButton(
                ctrlBar,
                L["Help: Minimap Message Previews"],
                L["Shows up to 3 compact animated cards beside your chosen screen position whenever Whispers, Party, Raid, Guild, or Room messages arrive."],
                L["Drag the preview block anywhere, click 'Test Queue (4)' to preview stacking, click 'Done' when finished, or click 'Reset' to snap back next to the Minimap icon."],
                18,
                { target = m }
            )
            moverHelp:SetPoint("RIGHT", ctrlBar, "RIGHT", -6, 0)
            m.helpBtn = moverHelp
        end

        testBtn:ClearAllPoints()
        testBtn:SetPoint("LEFT", doneBtn, "RIGHT", 6, 0)

        m.ctrlBar = ctrlBar
        m.doneBtn = doneBtn
        m.testBtn = testBtn
        m.resetBtn = resetBtn

        if Theme and Theme.MakeMovable then
            Theme:MakeMovable(m, {
                skipAutoRestore = true,
                handles = { ctrlBar },
                onStop = function(selfMover)
                    local cx, cy = selfMover:GetCenter()
                    if cx and cy then
                        MpSaveCustomCenter(cx, cy)
                    end
                    MsgPreview:SyncAnchorMoverPosition()
                end,
            })
        end

        self.anchorMover = m
    end

    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(m, "window")
        if m.ctrlBar then
            Theme:ApplyBackdrop(m.ctrlBar, "surface")
        end
        if m.SetBackdropBorderColor then
            m:SetBackdropBorderColor(0.96, 0.78, 0.26, 1.0)
        end
    end
    if Theme and Theme.StyleButton then
        Theme:StyleButton(m.doneBtn, "primary")
        Theme:StyleButton(m.testBtn, "default")
        Theme:StyleButton(m.resetBtn, "default")
        if m.helpBtn and m.helpBtn.RefreshTheme then
            m.helpBtn:RefreshTheme()
        end
        if Theme.SyncButtonLayers then
            Theme:SyncButtonLayers(m.doneBtn)
            Theme:SyncButtonLayers(m.testBtn)
            Theme:SyncButtonLayers(m.resetBtn)
        end
    end

    self:SyncAnchorMoverPosition()
    m:Show()
    if m.Raise then m:Raise() end
end

function MsgPreview:ToggleAnchorMover()
    if self.anchorMover and self.anchorMover:IsShown() then
        self:HideAnchorMover(false)
    else
        self:ShowAnchorMover()
    end
end

function MsgPreview:ShowTestPreview(variant)
    local v = type(variant) == "string" and variant:lower():match("^%s*(.-)%s*$") or ""
    if v == "move" or v == "anchor" or v == "pos" or v == "position" or v == "mover" then
        self:ToggleAnchorMover()
        return
    end
    if v == "resetpos" or v == "reset" then
        self:ResetPosition()
        return
    end
    if v == "clear" or v == "hide" or v == "dismiss" then
        self._queueTestGen = (self._queueTestGen or 0) + 1
        MinimapBtn:SetTestBadgeCount(0)
        self:HideAnchorMover(false)
        self:Dismiss(false)
        return
    end
    if v:sub(1, 5) == "badge" then
        local arg = v:sub(6):match("^%s*(.-)%s*$") or ""
        if arg == "0" or arg == "off" or arg == "clear" then
            MinimapBtn:SetTestBadgeCount(0)
        elseif arg == "" or arg == "fusion" or arg == "mix" or arg == "rgb" then
            MinimapBtn:SetTestBadgeMix({ whisper = 1, group = 1, raid = 1, guild = 1 })
        elseif arg == "all" or arg == "5" or arg == "6" then
            MinimapBtn:SetTestBadgeMix({ whisper = 2, group = 1, raid = 1, guild = 2, bnet = 1, room = 1 })
        elseif arg:find("whisper", 1, true) or arg:find("pink", 1, true) or arg:find("rosa", 1, true) then
            MinimapBtn:SetTestBadgeCount(tonumber(arg:match("(%d+)")) or 2, "whisper")
        elseif arg:find("raid", 1, true) or arg:find("raide", 1, true) or arg:find("banda", 1, true) or arg:find("orange", 1, true) or arg:find("laranja", 1, true) then
            MinimapBtn:SetTestBadgeCount(tonumber(arg:match("(%d+)")) or 2, "raid")
        elseif arg:find("group", 1, true) or arg:find("party", 1, true) or arg:find("blue", 1, true) or arg:find("azul", 1, true) then
            MinimapBtn:SetTestBadgeCount(tonumber(arg:match("(%d+)")) or 2, "group")
        elseif arg:find("guild", 1, true) or arg:find("green", 1, true) or arg:find("verde", 1, true) then
            MinimapBtn:SetTestBadgeCount(tonumber(arg:match("(%d+)")) or 2, "guild")
        elseif arg:find("bnet", 1, true) or arg:find("cyan", 1, true) then
            MinimapBtn:SetTestBadgeCount(tonumber(arg:match("(%d+)")) or 2, "bnet")
        elseif arg:find("room", 1, true) or arg:find("sala", 1, true) then
            MinimapBtn:SetTestBadgeCount(tonumber(arg:match("(%d+)")) or 2, "room")
        else
            local num = tonumber(arg:match("(%d+)"))
            if num and num >= 4 then
                local wCnt = math.max(1, math.floor(num / 4))
                local rCnt = math.max(1, math.floor((num - wCnt) / 3))
                local gCnt = math.max(1, math.floor((num - wCnt - rCnt) / 2))
                local cCnt = math.max(1, num - wCnt - rCnt - gCnt)
                MinimapBtn:SetTestBadgeMix({ whisper = wCnt, group = gCnt, raid = rCnt, guild = cCnt })
            elseif num and num == 3 then
                MinimapBtn:SetTestBadgeMix({ whisper = 1, group = 1, raid = 1 })
            elseif num and num == 2 then
                MinimapBtn:SetTestBadgeMix({ whisper = 1, guild = 1 })
            else
                MinimapBtn:SetTestBadgeCount(num or 1, "whisper")
            end
        end
        return
    end
    if v == "setup" or v == "prompt" or v == "wizard" then
        self:ShowFirstTimePrompt(MpBuildSampleItem("whisper", 1), true)
        return
    end
    if v == "queue" or v == "multi" or v == "stack" or v == "4" then
        self._queueTestGen = (self._queueTestGen or 0) + 1
        local gen = self._queueTestGen
        self:Dismiss(true)
        local specs = {
            { "whisper", 1, 0.00 },
            { "bnet", 2, 0.55 },
            { "group", 3, 1.10 },
            { "guild", 4, 1.65 },
        }
        for _, sp in ipairs(specs) do
            local kindArg, idxArg, delaySec = sp[1], sp[2], sp[3]
            if delaySec <= 0 or not (C_Timer and C_Timer.After) then
                self:PushItem(MpBuildSampleItem(kindArg, idxArg), true)
                if ns.Chat and ns.Chat.PlayMessageNotificationSound then
                    ns.Chat:PlayMessageNotificationSound("WHISPER", nil, false, "test_preview", "test")
                end
            else
                C_Timer.After(delaySec, function()
                    if MsgPreview._queueTestGen == gen then
                        MsgPreview:PushItem(MpBuildSampleItem(kindArg, idxArg), true)
                        if ns.Chat and ns.Chat.PlayMessageNotificationSound then
                            ns.Chat:PlayMessageNotificationSound("WHISPER", nil, false, "test_preview", "test")
                        end
                    end
                end)
            end
        end
        return
    end
    self.testCounter = (self.testCounter or 0) + 1
    local cycleIdx = ((self.testCounter - 1) % 5) + 1
    if v == "" then
        local cycleKinds = { "whisper", "bnet", "group", "raid", "guild" }
        v = cycleKinds[cycleIdx]
    end
    self:PushItem(MpBuildSampleItem(v, cycleIdx), true)
    if ns.Chat and ns.Chat.PlayMessageNotificationSound then
        ns.Chat:PlayMessageNotificationSound("WHISPER", nil, false, "test_preview", "test")
    end
end

function MsgPreview:OnIncomingMessage(payload)
    if type(payload) ~= "table" then return end
    local s = ns.db and ns.db.settings
    if not s then return end
    if Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("chat") then
        return
    end
    if not MpIsCategoryEnabled(payload.category) then
        return
    end

    local nowMono = GetTime and GetTime() or 0
    if (nowMono - (self.loginAt or 0)) < MP_LOGIN_GRACE then
        return
    end

    if not payload.isTestPreview and ns.NotificationToast and ns.NotificationToast.RecordRecentItem then
        local cleanSnippet, cleanText = MpCleanPreviewText(payload.text)
        if cleanText and cleanText ~= "" then
            payload._snippet = cleanSnippet
            payload._fullClean = cleanText
            ns.NotificationToast:RecordRecentItem({
                id = payload.id,
                kind = payload.channelKind or payload.category or "DIRECT",
                sourceTag = MpChannelLabel(payload),
                sender = tostring(payload.sender or "?"),
                senderClass = payload.senderClass,
                lookupKey = payload.lookupKey,
                bnetAccountID = payload.bnetAccountID,
                threadKey = payload.threadKey,
                roomId = payload.roomId,
                text = cleanText,
                ts = payload.ts or time(),
            })
        end
    end

    if s.msgPreviewEnabled == false then
        return
    end
    if s.msgPreviewSilenceCombat ~= false and MpIsInCombat() then
        MpEnqueueCombatHold(payload)
        return
    end
    if MpShouldSilenceForContext(payload) then
        return
    end

    self:PushItem(payload, false)
end

local function MpDescribeMuteTarget(item)
    if not item then return nil end
    local cat = item.category or "WHISPER"
    local label = MpCategoryDisableLabel(cat)
    local desc
    if cat == "WHISPER" then
        desc = L["Stop showing minimap message previews for Whispers and Direct Chat."]
    elseif cat == "BN_WHISPER" then
        desc = L["Stop showing minimap message previews for Battle.net Friends."]
    elseif cat == "GROUP" then
        desc = L["Stop showing minimap message previews for Party, Raid, and Instance chat."]
    elseif cat == "GUILD" then
        desc = L["Stop showing minimap message previews for Guild and Officer chat."]
    elseif cat == "ROOM" then
        desc = L["Stop showing minimap message previews for Private Rooms and Alliance Chat."]
    else
        desc = L["Stop showing minimap message previews for Whispers and Direct Chat."]
    end

    local playerMuteLabel, playerMuteFn
    local tKey = item.threadKey or item.channelKey
    if tKey and tKey ~= "" and ns.Chat and ns.Chat.ToggleThreadMuted then
        local isMuted = ns.Chat.IsThreadMuted and ns.Chat:IsThreadMuted(tKey)
        if not isMuted then
            local senderName = tostring(item.sender or "?")
            if Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()
                and (cat == "BN_WHISPER" or item.bnetAccountID ~= nil or senderName:find("#", 1, true))
                and Compat.MaskStreamerBNetName
            then
                senderName = Compat.MaskStreamerBNetName(senderName)
            end
            playerMuteLabel = L["Only %s"]:format(senderName)
            playerMuteFn = function()
                ns.Chat:ToggleThreadMuted(tKey)
                MsgPreview:DismissByThread(tKey, tKey, item.bnetAccountID)
                MinimapBtn:ClearPreviewCountsForThread(tKey, tKey, item.channelKind or item.category)
                ns:Print(L["Notifications muted for %s."]:format(senderName))
            end
        end
    end

    return {
        label = label,
        desc = desc,
        playerMuteLabel = playerMuteLabel,
        playerMuteFn = playerMuteFn,
        disableFn = function()
            MpDisableCategory(cat)
            MinimapBtn:ClearPreviewCountsForCategory(cat)
            for i = #MsgPreview.queue, 1, -1 do
                if MsgPreview.queue[i] and MsgPreview.queue[i].category == cat then
                    table.remove(MsgPreview.queue, i)
                end
            end
            for _, slot in ipairs(MsgPreview.activeSlots) do
                if slot.item and slot.item.category == cat then
                    slot._readDismissed = true
                    MpBeginCollapseSlot(slot)
                end
            end
            MpSyncQueueBadges()
            ns:Print("|cff9da7b5%s|r %s", label, L["disabled. Re-enable anytime in Settings -> Notifications."])
        end,
    }
end

function MsgPreview:ShowConfirmMutePopup(anchorCard, item)
    if not item then return end
    local Theme = ns.Theme
    if not Theme then return end
    local spec = MpDescribeMuteTarget(item)
    if not spec then return end

    if not self.confirmPopup then
        local pop = CreateFrame("Frame", "SocialCentralMsgPreviewConfirmPopup", UIParent, "BackdropTemplate")
        pop:Hide()
        pop:SetSize(296, 134)
        if Theme.PrepareTopOverlayModal then
            Theme:PrepareTopOverlayModal(pop, 855)
        else
            pop:SetFrameStrata("FULLSCREEN_DIALOG")
            pop:SetFrameLevel(855)
            pop:SetToplevel(true)
            pop:SetClampedToScreen(true)
        end
        pop:EnableMouse(true)
        if Theme and Theme.MakeMovable then
            Theme:MakeMovable(pop, { key = "modal_msg_preview_confirm", skipAutoRestore = true })
        end
        if pop.SetPropagateKeyboardInput then
            pop:SetPropagateKeyboardInput(true)
        end

        local solidBg = pop:CreateTexture(nil, "BACKGROUND", nil, -8)
        solidBg:SetAllPoints()
        solidBg:SetTexture(MP_WHITE8X8)
        solidBg:SetVertexColor(0.06, 0.06, 0.08, 1.0)
        pop._solidOpaqueBg = solidBg

        local ico = pop:CreateTexture(nil, "OVERLAY")
        ico:SetSize(16, 16)
        ico:SetPoint("TOPLEFT", 12, -11)
        ico:SetTexture(ICON_BELL_OFF)
        ico:SetVertexColor(1.0, 0.72, 0.30)

        local title = pop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", ico, "RIGHT", 6, 0)
        title:SetPoint("RIGHT", pop, "RIGHT", -28, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["Disable this notification?"])
        pop.titleLbl = title

        local xBtn = Theme:CreateButton(pop, 18, 18, "X", "default")
        xBtn:SetPoint("TOPRIGHT", -6, -7)
        xBtn:SetScript("OnClick", function() pop:Hide() end)
        pop.xBtn = xBtn

        if Theme and Theme.CreateHelpButton then
            local hBtn = Theme:CreateHelpButton(
                pop,
                L["Disable this notification?"],
                L["Lets you turn off just this alert category, mute the individual sender, or pause all SocialCentral alerts briefly with Do Not Disturb."],
                L["Re-enable any silenced alert anytime in Settings -> Notifications."],
                18,
                { target = pop }
            )
            hBtn:SetPoint("RIGHT", xBtn, "LEFT", -3, 0)
            pop.helpBtn = hBtn
            title:SetPoint("RIGHT", hBtn, "LEFT", -6, 0)
        end

        local subLbl = pop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subLbl:SetPoint("TOPLEFT", 12, -31)
        subLbl:SetPoint("TOPRIGHT", -12, -31)
        subLbl:SetJustifyH("LEFT")
        subLbl:SetWordWrap(true)
        pop.subLbl = subLbl

        local confirmBtn = Theme:CreateButton(pop, 108, 22, L["Disable"], "primary")
        confirmBtn:SetPoint("BOTTOMLEFT", 12, 36)
        pop.confirmBtn = confirmBtn

        local playerBtn = Theme:CreateButton(pop, 108, 22, "", "default")
        playerBtn:SetPoint("LEFT", confirmBtn, "RIGHT", 6, 0)
        pop.playerBtn = playerBtn

        local cancelBtn = Theme:CreateButton(pop, 84, 22, L["Cancel"], "default")
        cancelBtn:SetPoint("BOTTOMRIGHT", -12, 36)
        cancelBtn:SetScript("OnClick", function() pop:Hide() end)
        pop.cancelBtn = cancelBtn

        local dndBtn = Theme:CreateButton(pop, 264, 20, L["Pause All (Do Not Disturb)"], "default")
        dndBtn:SetPoint("BOTTOMLEFT", 12, 10)
        dndBtn:SetPoint("BOTTOMRIGHT", -12, 10)
        dndBtn:SetScript("OnClick", function(selfBtn)
            local function activateDnd(durSec, untilLeaveInst, untilLeaveGrp)
                pop:Hide()
                if Compat and Compat.SetDoNotDisturb then
                    Compat.SetDoNotDisturb(true, durSec, untilLeaveInst, untilLeaveGrp)
                elseif ns.db and ns.db.settings then
                    ns.db.settings.doNotDisturb = true
                    ns:Emit("SETTINGS_UPDATED")
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                end
                ns:Print("%s", L["Do Not Disturb active — popups & chimes paused."])
            end
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                    root:CreateTitle(L["Do Not Disturb"])
                    root:CreateButton(L["For 15 minutes"], function() activateDnd(900, false, false) end)
                    root:CreateButton(L["For 30 minutes"], function() activateDnd(1800, false, false) end)
                    root:CreateButton(L["For 1 hour"], function() activateDnd(3600, false, false) end)
                    root:CreateButton(L["For 2 hours"], function() activateDnd(7200, false, false) end)
                    root:CreateButton(L["Until leaving instance"], function() activateDnd(nil, true, false) end)
                    root:CreateButton(L["Until leaving group"], function() activateDnd(nil, false, true) end)
                    root:CreateButton(L["Until I turn it off"], function() activateDnd(nil, false, false) end)
                end)
            else
                activateDnd(nil, false, false)
            end
        end)
        pop.dndBtn = dndBtn

        pop:HookScript("OnHide", function(selfPop)
            selfPop._targetItem = nil
        end)
        if _G.UISpecialFrames then
            table.insert(_G.UISpecialFrames, "SocialCentralMsgPreviewConfirmPopup")
        end

        self.confirmPopup = pop
    end

    local pop = self.confirmPopup
    pop._targetItem = item
    local p = Theme.GetPalette and Theme:GetPalette()
    if Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(pop, "window", p)
    end
    if p then
        if pop._solidOpaqueBg then
            local wb = p.windowBg or { 0.06, 0.06, 0.08, 1.0 }
            pop._solidOpaqueBg:SetVertexColor(wb[1], wb[2], wb[3], 1.0)
        end
        Theme:StyleButton(pop.xBtn, "default")
        Theme:StyleButton(pop.confirmBtn, "primary")
        Theme:StyleButton(pop.playerBtn, "default")
        Theme:StyleButton(pop.cancelBtn, "default")
        if pop.helpBtn and pop.helpBtn.RefreshTheme then
            pop.helpBtn:RefreshTheme()
        end
    end

    local showDndBtn = not (ns.db and ns.db.settings and ns.db.settings.doNotDisturb == true)
    if pop.dndBtn then
        if p then Theme:StyleButton(pop.dndBtn, "default") end
        pop.dndBtn:SetShown(showDndBtn)
    end
    local extraBottom = showDndBtn and 26 or 0
    pop.confirmBtn:ClearAllPoints()
    pop.confirmBtn:SetPoint("BOTTOMLEFT", 12, 10 + extraBottom)
    pop.cancelBtn:ClearAllPoints()
    pop.cancelBtn:SetPoint("BOTTOMRIGHT", -12, 10 + extraBottom)

    pop.confirmBtn:SetScript("OnClick", function()
        pop:Hide()
        if spec.disableFn then
            spec.disableFn()
        end
    end)

    if spec.playerMuteFn and spec.playerMuteLabel then
        Theme:SetButtonText(pop.playerBtn, spec.playerMuteLabel)
        Theme:AutoFitButton(pop.playerBtn, 78, 14, 155)
        pop.playerBtn:ClearAllPoints()
        pop.playerBtn:SetPoint("LEFT", pop.confirmBtn, "RIGHT", 6, 0)
        pop.playerBtn:SetScript("OnClick", function()
            pop:Hide()
            spec.playerMuteFn()
        end)
        pop.playerBtn:Show()
        Theme:SetButtonText(pop.confirmBtn, L["Disable All"])
        Theme:AutoFitButton(pop.confirmBtn, 84, 14, 134)
        Theme:AutoFitButton(pop.cancelBtn, 70, 14, 108)
        local neededW = (pop.confirmBtn:GetWidth() or 92) + (pop.playerBtn:GetWidth() or 96) + (pop.cancelBtn:GetWidth() or 78) + 42
        pop:SetWidth(math.max(304, math.min(448, neededW)))
    else
        pop.playerBtn:Hide()
        Theme:SetButtonText(pop.confirmBtn, L["Disable"])
        Theme:AutoFitButton(pop.confirmBtn, 96, 14, 140)
        Theme:AutoFitButton(pop.cancelBtn, 80, 14, 110)
        pop:SetWidth(296)
    end

    pop.subLbl:SetText(("|cffffd24d%s|r\n|cffd2d9e4%s|r"):format(spec.label or "", spec.desc or ""))
    local textH = (pop.subLbl.GetStringHeight and pop.subLbl:GetStringHeight()) or 32
    pop:SetHeight(math.max(108 + extraBottom, math.ceil(36 + textH + 44 + extraBottom)))

    pop:ClearAllPoints()
    local ref = (anchorCard and anchorCard.IsShown and anchorCard:IsShown() and anchorCard) or button
    if ref and ref.GetLeft and UIParent and UIParent.GetWidth then
        local uiW = UIParent:GetWidth() or 1280
        local popW = pop:GetWidth() or 296
        local left = ref:GetLeft() or (uiW * 0.5)
        local right = ref:GetRight() or (uiW * 0.6)
        if left >= (popW + 14) then
            pop:SetPoint("TOPRIGHT", ref, "TOPLEFT", -8, 0)
        elseif (uiW - right) >= (popW + 14) then
            pop:SetPoint("TOPLEFT", ref, "TOPRIGHT", 8, 0)
        else
            pop:SetPoint("TOP", ref, "BOTTOM", 0, -6)
        end
    else
        pop:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    if Theme.PrepareTopOverlayModal then
        Theme:PrepareTopOverlayModal(pop, 855)
    end
    if Theme.SyncSubtreeLayers then
        Theme:SyncSubtreeLayers(pop, 8)
    end
    pop:Show()
    pop:Raise()
end

function MsgPreview:DismissByThread(threadKey, channelKey, bnetAccountID)
    if not (threadKey or channelKey or bnetAccountID) then return end
    local function Matches(it)
        if not it then return false end
        if threadKey and (it.threadKey == threadKey or it.channelKey == threadKey) then
            return true
        end
        if channelKey and (it.threadKey == channelKey or it.channelKey == channelKey) then
            return true
        end
        if bnetAccountID and it.bnetAccountID and it.bnetAccountID == bnetAccountID then
            return true
        end
        return false
    end

    local qChanged = false
    for i = #self.queue, 1, -1 do
        if Matches(self.queue[i]) then
            table.remove(self.queue, i)
            qChanged = true
        end
    end
    for i = #self.combatHeldQueue, 1, -1 do
        if Matches(self.combatHeldQueue[i]) then
            table.remove(self.combatHeldQueue, i)
        end
    end
    for _, slot in ipairs(self.activeSlots) do
        if Matches(slot.item) then
            slot._readDismissed = true
            MpBeginCollapseSlot(slot)
        end
    end
    if qChanged then
        MpSyncQueueBadges()
    end
end

function MsgPreview:Init()
    if self.initialized then return end
    self.initialized = true
    self.loginAt = (GetTime and GetTime()) or 0

    ns:On("INCOMING_MESSAGE_PREVIEW", function(payload)
        MsgPreview:OnIncomingMessage(payload)
    end)

    ns:On("CHAT_THREAD_READ", function(info)
        if type(info) == "table" then
            MsgPreview:DismissByThread(info.threadKey, info.channelKey, info.bnetAccountID)
        elseif type(info) == "string" then
            MsgPreview:DismissByThread(info, info, nil)
        end
    end)

    ns:On("CHAT_UPDATED", function()
        if #MsgPreview.activeSlots == 0 then return end
        for _, slot in ipairs(MsgPreview.activeSlots) do
            local tk = slot.item and slot.item.threadKey
            if tk and ((ns.UI and ns.UI.IsChatThreadVisible and ns.UI:IsChatThreadVisible(tk))
                or (QuickReply and QuickReply.IsViewingThread and QuickReply:IsViewingThread(tk)))
            then
                slot._readDismissed = true
                MpBeginCollapseSlot(slot)
            end
        end
    end)

    local function HoldActiveAndQueueForCombat()
        for _, slot in ipairs(MsgPreview.activeSlots) do
            if slot.phase ~= "COLLAPSE" and not slot._readDismissed and slot.item and not slot.item.isTestPreview then
                MpEnqueueCombatHold(slot.item)
                slot._readDismissed = true
            end
        end
        for _, qItem in ipairs(MsgPreview.queue) do
            if qItem and not qItem.isTestPreview then
                MpEnqueueCombatHold(qItem)
            end
        end
        if #MsgPreview.activeSlots > 0 then
            MpBeginCollapseAll(true)
        else
            wipe(MsgPreview.queue)
        end
    end

    local function RevalidateVisibility()
        for _, slot in ipairs(MsgPreview.activeSlots) do
            slot._coords = nil
        end
        local s = ns.db and ns.db.settings
        if not s then return end
        local setupOpen = MsgPreview.setupModal and MsgPreview.setupModal:IsShown()
        if setupOpen then return end
        if s.msgPreviewEnabled == false then
            wipe(MsgPreview.combatHeldQueue)
            if #MsgPreview.activeSlots > 0 then
                for _, slot in ipairs(MsgPreview.activeSlots) do
                    slot._readDismissed = true
                end
                MpBeginCollapseAll(true)
            else
                wipe(MsgPreview.queue)
            end
            return
        end
        if s.msgPreviewSilenceCombat ~= false and MpIsInCombat() then
            HoldActiveAndQueueForCombat()
            return
        end
        local qChanged = false
        for i = #MsgPreview.queue, 1, -1 do
            if MpShouldSilenceForContext(MsgPreview.queue[i]) then
                table.remove(MsgPreview.queue, i)
                qChanged = true
            end
        end
        for _, slot in ipairs(MsgPreview.activeSlots) do
            if slot.item and MpShouldSilenceForContext(slot.item) then
                slot._readDismissed = true
                MpBeginCollapseSlot(slot)
            elseif slot.item and slot.phase ~= "COLLAPSE" and slot.frame and slot.frame:IsShown() then
                slot.targetW = MpRenderItemContent(slot.frame, slot.item)
                if slot.phase == "HOLD" then
                    MpApplySlotVisuals(slot, 1, 1, 1, 0, 1, 1)
                end
            end
        end
        if qChanged then
            MpSyncQueueBadges()
        end
        MpPromoteFromQueue()
    end

    ns:On("SETTINGS_UPDATED", RevalidateVisibility)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", RevalidateVisibility)
    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", RevalidateVisibility)
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        if MsgPreview.confirmPopup and MsgPreview.confirmPopup:IsShown() then
            MsgPreview.confirmPopup:Hide()
        end
        if MsgPreview.setupModal and MsgPreview.setupModal:IsShown() then
            MsgPreview.pendingPromptItem = MsgPreview.pendingPromptItem or true
            MsgPreview.setupModal:Hide()
        end
        local s = ns.db and ns.db.settings
        if not s or s.msgPreviewSilenceCombat ~= false then
            HoldActiveAndQueueForCombat()
        end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if MsgPreview.pendingPromptItem then
            local pItem = MsgPreview.pendingPromptItem
            MsgPreview.pendingPromptItem = nil
            if C_Timer and C_Timer.After then
                C_Timer.After(1.8, function()
                    if not MpIsInCombat() then
                        MsgPreview:ShowFirstTimePrompt(type(pItem) == "table" and pItem or nil, true)
                    end
                end)
            end
        end
        local s = ns.db and ns.db.settings
        if s and s.msgPreviewEnabled ~= false and #MsgPreview.combatHeldQueue > 0 then
            local pending = MsgPreview.combatHeldQueue
            MsgPreview.combatHeldQueue = {}
            for _, heldItem in ipairs(pending) do
                if heldItem and MpIsCategoryEnabled(heldItem.category) and not MpShouldSilenceForContext(heldItem) then
                    local t = heldItem.threadKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[heldItem.threadKey] or nil
                    local isDirectOrRoom = t and (t.kind == "WHISPER" or t.kind == "BN_WHISPER" or t.kind == "ROOM" or t.kind == "ALLIANCE")
                    if (not t) or (not isDirectOrRoom) or ((t.unread or 0) > 0) then
                        MsgPreview:PushItem(heldItem, false)
                    end
                end
            end
        else
            wipe(MsgPreview.combatHeldQueue)
        end
    end)

    if ns.Theme and ns.Theme.RegisterListener then
        ns.Theme:RegisterListener(function()
            for _, f in ipairs(MsgPreview.framePool) do
                MpApplyThemeToPreview(f, true)
            end
            local sm = MsgPreview.setupModal
            if sm and sm:IsShown() then
                local p = ns.Theme:GetPalette()
                if sm._solidOpaqueBg then
                    local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
                    sm._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
                end
                ns.Theme:ApplyBackdrop(sm, "window", p)
                ns.Theme:ApplyBackdrop(sm.chanBox, "surface", p)
                ns.Theme:ApplyBackdrop(sm.ctxBox, "surface", p)
                ns.Theme:StyleButton(sm.closeBtn, "default")
                if sm.btnSettings then ns.Theme:StyleButton(sm.btnSettings, "default") end
                ns.Theme:StyleButton(sm.btnEnable, "primary")
                ns.Theme:StyleButton(sm.btnDisable, "default")
                if sm.helpBtn and sm.helpBtn.RefreshTheme then sm.helpBtn:RefreshTheme() end
            end
            local am = MsgPreview.anchorMover
            if am and am:IsShown() then
                local p = ns.Theme:GetPalette()
                ns.Theme:ApplyBackdrop(am, "window", p)
                if am.SetBackdropBorderColor then
                    am:SetBackdropBorderColor(0.96, 0.78, 0.26, 1.0)
                end
                if am.ctrlBar then ns.Theme:ApplyBackdrop(am.ctrlBar, "surface", p) end
                if am.doneBtn then ns.Theme:StyleButton(am.doneBtn, "primary") end
                if am.testBtn then ns.Theme:StyleButton(am.testBtn, "default") end
                if am.resetBtn then ns.Theme:StyleButton(am.resetBtn, "default") end
                if am.helpBtn and am.helpBtn.RefreshTheme then am.helpBtn:RefreshTheme() end
            end
            local cp = MsgPreview.confirmPopup
            if cp and cp:IsShown() then
                local p = ns.Theme:GetPalette()
                if cp._solidOpaqueBg then
                    local bg = (p and p.windowBg) or { 0.06, 0.06, 0.08, 1.0 }
                    cp._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
                end
                ns.Theme:ApplyBackdrop(cp, "window", p)
                ns.Theme:StyleButton(cp.xBtn, "default")
                ns.Theme:StyleButton(cp.confirmBtn, "primary")
                ns.Theme:StyleButton(cp.playerBtn, "default")
                ns.Theme:StyleButton(cp.cancelBtn, "default")
                if cp.dndBtn then ns.Theme:StyleButton(cp.dndBtn, "default") end
                if cp.helpBtn and cp.helpBtn.RefreshTheme then cp.helpBtn:RefreshTheme() end
            end
        end)
    end
end

ns.MinimapPreview = MsgPreview
table.insert(ns.modules, MsgPreview)

------------------------------------------------------------------------
-- Compact Quick Reply Popup (Design 10 — Minimap Notification Reply)
------------------------------------------------------------------------
do
    local qrInit = {
        frame = nil,
        activeKey = nil,
        hasTyped = false,
        hasSentInSession = false,
        interactedOutside = false,
        _ownMenuOpen = false,
        _menuActionPicked = false,
        _userDraggedThisOpen = false,
        _enterBtn = nil,
        _enterBindPending = false,
        chipsPage = 1,
        _chipsFollowActive = true,
        openedAt = 0,
        idleCountdown = nil,
        lastInputAt = 0,
        lastStatusState = "",
        lastStatusSec = 0,
        lastStatusDraft = false,
        suppressDraftSave = false,
        RECENT_SEND_WINDOW_SEC = 1800,
        _lastSentThreadKey = nil,
        _lastSentAt = 0,
        _recentSendTimerSeq = 0,
        _lastSubmitAt = 0,
    }
    for k, v in pairs(qrInit) do
        QuickReply[k] = v
    end
end

local function IsTemporaryOfficialEditAllowed()
    return QuickReply and QuickReply._allowTempOfficialEditUntil
        and GetTime and GetTime() < QuickReply._allowTempOfficialEditUntil
end

function QuickReply:PrepareTemporaryOfficialEditBox(seconds)
    self._allowTempOfficialEditUntil = (GetTime and GetTime() or 0) + (tonumber(seconds) or 25)
    self._dockedOfficialFallbackHint = true
    self._refocusInputAfterBlizzSend = false
end

local function GetOfficialEditBoxHeaderText(eb)
    if not eb then return "" end
    local hObj = eb.header or (eb.GetName and eb:GetName() and _G[eb:GetName() .. "Header"]) or nil
    if hObj and hObj.GetText then
        local raw = hObj:GetText()
        if ns.Safe and ns.Safe.String then
            return ns.Safe.String(raw) or ""
        end
        return (type(raw) == "string") and raw or ""
    end
    return ""
end

function QuickReply:IsOfficialOnlyThread(thread)
    if not (Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode()) then
        return false
    end
    local t = thread or (self.activeKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[self.activeKey])
    if not t then
        return false
    end
    if t.key == "ch:general" or t.kind == "GENERAL" then
        local gTarget = (ns.Chat and ns.Chat.GetGeneralTargetInfo) and ns.Chat:GetGeneralTargetInfo() or nil
        if gTarget and gTarget.clubId and gTarget.streamId then
            return false
        end
        return true
    end
    if t.kind == "LOCAL_SAY" or t.kind == "LOCAL_YELL" then
        return true
    end
    if t.kind == "PUB_CHANNEL" and not (t.clubId and t.streamId) then
        return true
    end
    return false
end

function QuickReply:IsDockedOfficialFocused()
    local eb = self._activeDockedSkinEb
        or (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
        or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
        or nil
    return (eb ~= nil and eb.HasFocus and eb:HasFocus() == true) == true
end

function QuickReply:ResolveOfficialPrefixColor(thread, fallbackTone)
    local fbR = (fallbackTone and fallbackTone[1]) or 0.85
    local fbG = (fallbackTone and fallbackTone[2]) or 0.72
    local fbB = (fallbackTone and fallbackTone[3]) or 0.36
    local cti = _G.ChatTypeInfo
    if type(cti) ~= "table" or not thread then
        return fbR, fbG, fbB
    end
    local chatType = nil
    local kind = thread.kind
    if kind == "PARTY" then
        chatType = "PARTY"
    elseif kind == "RAID" then
        chatType = "RAID"
    elseif kind == "INSTANCE_CHAT" then
        chatType = "INSTANCE_CHAT"
    elseif kind == "GUILD" then
        chatType = "GUILD"
    elseif kind == "OFFICER" then
        chatType = "OFFICER"
    elseif kind == "WHISPER" then
        chatType = "WHISPER"
    elseif kind == "BN_WHISPER" then
        chatType = "BN_WHISPER"
    elseif kind == "GENERAL" then
        local gTarget = (ns.Chat and ns.Chat.GetGeneralTargetInfo) and ns.Chat:GetGeneralTargetInfo() or nil
        if gTarget and gTarget.channelId then
            chatType = "CHANNEL" .. tostring(gTarget.channelId)
        elseif gTarget and gTarget.isYell then
            chatType = "YELL"
        else
            chatType = "SAY"
        end
    end
    local info = chatType and cti[chatType] or nil
    if (not info) and chatType and chatType:sub(1, 7) == "CHANNEL" then
        info = cti["CHANNEL"]
    end
    if type(info) == "table" and info.r and info.g and info.b then
        return info.r, info.g, info.b
    end
    return fbR, fbG, fbB
end

QuickReply._GENERAL_TONE_THREAD = QuickReply._GENERAL_TONE_THREAD or { kind = "GENERAL" }
QuickReply._DEF_IN_BG = QuickReply._DEF_IN_BG or { 0.03, 0.03, 0.04, 1.0 }
QuickReply._DEF_MUTED = QuickReply._DEF_MUTED or { 0.52, 0.56, 0.64, 0.85 }

function QuickReply:InvalidateFocusVisuals()
    self._focusDimR = nil
    self._focusDimG = nil
    self._focusDimB = nil
    self._focusDimHover = nil
    local eb = self._activeDockedSkinEb or _G.ChatFrame1EditBox
    if eb and eb._scDockedSkin then
        eb._scDockedSkin._scSkinPalKey = nil
    end
end

function QuickReply:SyncInputStyleToOfficial(force)
    local f = self.frame
    if not f then
        return
    end
    local eb1 = _G.ChatFrame1EditBox
    local skin = eb1 and eb1._scDockedSkin or nil
    local hasRest = (skin and skin._restingLabel ~= nil) and true or false
    if (not force) and self._officialInputStyleSynced and self._officialInputStyleHasRest == hasRest then
        return
    end
    local hdr1 = eb1 and (eb1.header or _G.ChatFrame1EditBoxHeader) or nil
    local hFont, hSize, hFlags = nil, nil, nil
    if hdr1 and hdr1.GetFont then
        local okF, fp, fs, ff = pcall(hdr1.GetFont, hdr1)
        if okF and type(fp) == "string" and fp ~= "" and type(fs) == "number" and fs > 0 then
            hFont, hSize, hFlags = fp, fs, ff or ""
        end
    end
    local eFont, eSize, eFlags = nil, nil, nil
    if eb1 and eb1.GetFont then
        local okE, fp, fs, ff = pcall(eb1.GetFont, eb1)
        if okE and type(fp) == "string" and fp ~= "" and type(fs) == "number" and fs > 0 then
            eFont, eSize, eFlags = fp, fs, ff or ""
        end
    end
    if (not hFont) and _G.ChatFontNormal and _G.ChatFontNormal.GetFont then
        local okC, fp, fs, ff = pcall(_G.ChatFontNormal.GetFont, _G.ChatFontNormal)
        if okC and type(fp) == "string" and fp ~= "" and type(fs) == "number" and fs > 0 then
            hFont, hSize, hFlags = fp, fs, ff or ""
        end
    end
    if not eFont then
        eFont, eSize, eFlags = hFont, hSize, hFlags
    end
    local hx, hy = 10, 0
    if hdr1 and hdr1.GetPoint then
        local okP, pt, _, _, ox, oy = pcall(hdr1.GetPoint, hdr1, 1)
        if okP and type(ox) == "number" and (pt == "LEFT" or pt == "TOPLEFT" or pt == "BOTTOMLEFT") then
            hx = math.max(9, math.min(16, math.floor(ox + 0.5)))
            if type(oy) == "number" then
                hy = math.max(-3, math.min(3, math.floor(oy + 0.5)))
            end
        end
    end
    local sx, sy = 1, -1
    local sr, sg, sb, sa = 0, 0, 0, 1
    if hdr1 and hdr1.GetShadowOffset then
        local okSo, ox, oy = pcall(hdr1.GetShadowOffset, hdr1)
        if okSo and type(ox) == "number" and type(oy) == "number" then
            sx, sy = ox, oy
        end
    end
    if hdr1 and hdr1.GetShadowColor then
        local okSc, cr, cg, cb, ca = pcall(hdr1.GetShadowColor, hdr1)
        if okSc and type(cr) == "number" then
            sr, sg, sb, sa = cr, cg or 0, cb or 0, ca or 1
        end
    end
    self._officialInputStyleSynced = true
    self._officialInputStyleHasRest = hasRest
    local sig = tostring(hFont or "") .. ":" .. tostring(hSize or 0) .. ":" .. tostring(hFlags or "")
        .. "|" .. tostring(eFont or "") .. ":" .. tostring(eSize or 0) .. ":" .. tostring(eFlags or "")
        .. "|" .. tostring(hx) .. "," .. tostring(hy) .. "|" .. (hasRest and "1" or "0")
    if (not force) and self._officialInputStyleSig == sig then
        return
    end
    self._officialInputStyleSig = sig
    if f.inputPrefixFs then
        if hFont and f.inputPrefixFs.SetFont then
            pcall(f.inputPrefixFs.SetFont, f.inputPrefixFs, hFont, hSize, hFlags)
        elseif _G.ChatFontNormal and f.inputPrefixFs.SetFontObject then
            pcall(f.inputPrefixFs.SetFontObject, f.inputPrefixFs, _G.ChatFontNormal)
        end
        if f.inputPrefixFs.SetShadowOffset then pcall(f.inputPrefixFs.SetShadowOffset, f.inputPrefixFs, sx, sy) end
        if f.inputPrefixFs.SetShadowColor then pcall(f.inputPrefixFs.SetShadowColor, f.inputPrefixFs, sr, sg, sb, sa) end
        if f.inputWrap then
            f.inputPrefixFs:ClearAllPoints()
            f.inputPrefixFs:SetPoint("LEFT", f.inputWrap, "LEFT", hx, hy)
        end
    end
    if f.inputBox and eFont and f.inputBox.SetFont then
        pcall(f.inputBox.SetFont, f.inputBox, eFont, eSize, eFlags)
        if f.inputBox.SetShadowOffset then pcall(f.inputBox.SetShadowOffset, f.inputBox, sx, sy) end
        if f.inputBox.SetShadowColor then pcall(f.inputBox.SetShadowColor, f.inputBox, sr, sg, sb, sa) end
    end
    if skin and skin._restingLabel then
        local rl = skin._restingLabel
        if hFont and rl.SetFont then
            pcall(rl.SetFont, rl, hFont, hSize, hFlags)
        elseif _G.ChatFontNormal and rl.SetFontObject then
            pcall(rl.SetFontObject, rl, _G.ChatFontNormal)
        end
        if rl.SetShadowOffset then pcall(rl.SetShadowOffset, rl, sx, sy) end
        if rl.SetShadowColor then pcall(rl.SetShadowColor, rl, sr, sg, sb, sa) end
        rl:ClearAllPoints()
        rl:SetPoint("LEFT", skin, "LEFT", hx, hy)
    end
end

local function SyncDockedOfficialSkinColors(eb)
    if not (eb and eb._scDockedSkin and eb._scDockedSkin:IsShown()) then
        return
    end
    local skin = eb._scDockedSkin
    local p = ns.Theme and ns.Theme.GetPalette and ns.Theme:GetPalette() or nil
    local palKey = (p and p.key) or "dark"
    local tone = QuickReply and QuickReply._activeToneRgb
    local r = (tone and tone[1]) or 0.85
    local g = (tone and tone[2]) or 0.72
    local b = (tone and tone[3]) or 0.36
    local hasFocus = (eb.HasFocus and eb:HasFocus() == true) == true
    local hov = (not hasFocus) and ((eb.IsMouseOver and eb:IsMouseOver() == true) == true) or false
    local br = hasFocus and (QuickReply._focusBorderR or math.min(1, r + (1 - r) * 0.25)) or -1
    local bg = hasFocus and (QuickReply._focusBorderG or math.min(1, g + (1 - g) * 0.25)) or -1
    local bb = hasFocus and (QuickReply._focusBorderB or math.min(1, b + (1 - b) * 0.25)) or -1
    local gTarget = (not hasFocus) and (ns.Chat and ns.Chat.GetGeneralTargetInfo) and ns.Chat:GetGeneralTargetInfo() or nil
    local gKey = (not hasFocus) and ((gTarget and gTarget.channelId) or (gTarget and gTarget.isYell and "Y") or "S") or ""
    if skin._scSkinPalKey == palKey
        and skin._scSkinFocus == hasFocus
        and skin._scSkinHov == hov
        and skin._scSkinTR == r and skin._scSkinTG == g and skin._scSkinTB == b
        and skin._scSkinBR == br and skin._scSkinBG == bg and skin._scSkinBB == bb
        and skin._scSkinGKey == gKey
    then
        return
    end
    skin._scSkinPalKey = palKey
    skin._scSkinFocus = hasFocus
    skin._scSkinHov = hov
    skin._scSkinTR, skin._scSkinTG, skin._scSkinTB = r, g, b
    skin._scSkinBR, skin._scSkinBG, skin._scSkinBB = br, bg, bb
    skin._scSkinGKey = gKey

    if ns.Theme and ns.Theme.ApplyBackdrop then
        ns.Theme:ApplyBackdrop(skin, "inset", p)
    end
    local inBg = (p and p.inputBg) or QuickReply._DEF_IN_BG
    if hasFocus then
        if skin.SetBackdropColor then
            skin:SetBackdropColor(r * 0.11 + 0.05, g * 0.11 + 0.05, b * 0.11 + 0.05, 1.0)
        end
        if skin.SetBackdropBorderColor then
            skin:SetBackdropBorderColor(br, bg, bb, 1.0)
        end
        if skin._solidBg then
            skin._solidBg:SetVertexColor(r * 0.11 + 0.05, g * 0.11 + 0.05, b * 0.11 + 0.05, 1.0)
        end
    else
        local mult = hov and 0.48 or 0.28
        if skin.SetBackdropColor then
            skin:SetBackdropColor(inBg[1], inBg[2], inBg[3], 1.0)
        end
        if skin.SetBackdropBorderColor then
            skin:SetBackdropBorderColor(math.min(1, 0.22 + r * mult), math.min(1, 0.23 + g * mult), math.min(1, 0.26 + b * mult), 0.95)
        end
        if skin._solidBg then
            skin._solidBg:SetVertexColor(inBg[1], inBg[2], inBg[3], 1.0)
        end
    end
    if skin._restingLabel then
        if not hasFocus then
            local pfx = (gTarget and gTarget.channelId and ("/" .. tostring(gTarget.channelId) .. ":"))
                or (gTarget and gTarget.isYell and (L["Yell"] .. ":"))
                or (L["Say"] .. ":")
            local pr, pg, pb = QuickReply:ResolveOfficialPrefixColor(QuickReply._GENERAL_TONE_THREAD, tone)
            skin._restingLabel:SetText(pfx)
            skin._restingLabel:SetTextColor(pr, pg, pb, 1.0)
            skin._restingLabel:Show()
            if skin._restingPlaceholder then
                local mc = (p and p.textMuted) or QuickReply._DEF_MUTED
                local phTxt = (QuickReply.BuildInputPlaceholder and QuickReply:BuildInputPlaceholder(QuickReply._GENERAL_TONE_THREAD, L["General"], gTarget))
                    or L["Click here to type..."]
                skin._restingPlaceholder:SetText(phTxt)
                skin._restingPlaceholder:SetTextColor(mc[1] or 0.52, mc[2] or 0.56, mc[3] or 0.64, 0.72)
                skin._restingPlaceholder:Show()
            end
            if skin._enterHint then
                skin._enterHint:SetShown((QuickReply.frame and QuickReply.frame:GetWidth() or 444) >= 340)
            end
        else
            skin._restingLabel:Hide()
            if skin._restingPlaceholder then
                skin._restingPlaceholder:Hide()
            end
            if skin._enterHint then
                skin._enterHint:Hide()
            end
        end
    end
end

local function ApplyDockedOfficialEditSkin(eb)
    if not (eb and QuickReply and QuickReply.frame) then
        return
    end
    if not eb._scOrigTexAlphas then
        eb._scOrigTexAlphas = {}
        local okR, regions = pcall(function() return { eb:GetRegions() } end)
        if okR and type(regions) == "table" then
            for _, reg in ipairs(regions) do
                if reg and reg.GetObjectType and reg:GetObjectType() == "Texture" and reg.GetAlpha and reg.SetAlpha then
                    eb._scOrigTexAlphas[reg] = reg:GetAlpha() or 1
                end
            end
        end
        local namedParts = {
            "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight",
            "left", "mid", "right", "focusLeft", "focusMid", "focusRight",
            "NineSlice", "Background", "BG",
        }
        local ebName = eb.GetName and eb:GetName() or nil
        for _, key in ipairs(namedParts) do
            local obj = eb[key] or (ebName and _G[ebName .. key]) or nil
            if obj and obj.GetAlpha and obj.SetAlpha and eb._scOrigTexAlphas[obj] == nil then
                eb._scOrigTexAlphas[obj] = obj:GetAlpha() or 1
            end
        end
    end
    if not eb._scOrigTexHidden then
        eb._scOrigTexHidden = true
        for obj in pairs(eb._scOrigTexAlphas) do
            if obj and obj.SetAlpha then
                pcall(obj.SetAlpha, obj, 0)
            end
        end
    end

    if not eb._scOrigHeight and eb.GetHeight then
        local h = eb:GetHeight()
        if h and h > 0 then
            eb._scOrigHeight = h
        end
    end
    if not eb._scOrigInsets and eb.GetTextInsets then
        local okI, l, r, t, b = pcall(eb.GetTextInsets, eb)
        if okI then
            eb._scOrigInsets = { l or 0, r or 0, t or 0, b or 0 }
        end
    end
    if not (InCombatLockdown and InCombatLockdown()) and not eb._scDockedSizingApplied then
        eb._scDockedSizingApplied = true
        if eb.SetHeight then
            pcall(eb.SetHeight, eb, 24)
        end
        if eb.GetTextInsets and eb.SetTextInsets then
            local okI, l, r = pcall(eb.GetTextInsets, eb)
            if okI then
                pcall(eb.SetTextInsets, eb, math.max(10, l or 10), math.max(10, r or 10), 0, 0)
            end
        end
    end

    if not eb._scDockedSkin then
        local skin = CreateFrame("Frame", nil, QuickReply.frame, "BackdropTemplate")
        skin:EnableMouse(false)
        local solidBg = skin:CreateTexture(nil, "BACKGROUND", nil, -8)
        solidBg:SetPoint("TOPLEFT", skin, "TOPLEFT", 1, -1)
        solidBg:SetPoint("BOTTOMRIGHT", skin, "BOTTOMRIGHT", -1, 1)
        solidBg:SetTexture(QR_WHITE8X8)
        solidBg:SetVertexColor(0.03, 0.03, 0.04, 1.0)
        skin._solidBg = solidBg
        local restLbl = skin:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        restLbl:SetPoint("LEFT", skin, "LEFT", 10, 0)
        restLbl:SetJustifyH("LEFT")
        restLbl:SetWordWrap(false)
        restLbl:Hide()
        skin._restingLabel = restLbl
        local enterHint = skin:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        enterHint:SetPoint("RIGHT", skin, "RIGHT", -9, 0)
        enterHint:SetJustifyH("RIGHT")
        enterHint:SetWordWrap(false)
        enterHint:SetText("ENTER")
        enterHint:SetTextColor(0.46, 0.52, 0.60, 0.65)
        skin._enterHint = enterHint
        local restPh = skin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        restPh:SetPoint("LEFT", restLbl, "RIGHT", 6, 0)
        restPh:SetPoint("RIGHT", enterHint, "LEFT", -6, 0)
        restPh:SetJustifyH("LEFT")
        restPh:SetWordWrap(false)
        restPh:Hide()
        skin._restingPlaceholder = restPh
        skin:Hide()
        eb._scDockedSkin = skin
    end
    local skin = eb._scDockedSkin
    local inCombatNow = (InCombatLockdown and InCombatLockdown()) or false
    local ebProt = (eb.IsProtected and eb:IsProtected()) == true
    local baseStrata = (QuickReply.frame.GetFrameStrata and QuickReply.frame:GetFrameStrata()) or "DIALOG"
    local baseLevel = (QuickReply.frame.GetFrameLevel and QuickReply.frame:GetFrameLevel()) or 320
    local skinStrata = baseStrata
    local skinLevel = baseLevel + 6
    if inCombatNow and ebProt then
        local liveEbStrata = eb.GetFrameStrata and eb:GetFrameStrata() or nil
        local liveEbLevel = eb.GetFrameLevel and eb:GetFrameLevel() or nil
        if liveEbStrata then
            skinStrata = liveEbStrata
        end
        if liveEbLevel and liveEbLevel > 1 then
            skinLevel = math.max(1, math.min(skinLevel, liveEbLevel - 2))
        end
    end
    if not skin._scAnchoredToQr then
        skin._scAnchoredToQr = true
        skin:ClearAllPoints()
        skin:SetPoint("BOTTOMLEFT", QuickReply.frame, "BOTTOMLEFT", 6, 6)
        skin:SetPoint("BOTTOMRIGHT", QuickReply.frame, "BOTTOMRIGHT", -6, 6)
        skin:SetHeight(24)
    end
    if (skin.GetFrameStrata and skin:GetFrameStrata()) ~= skinStrata then
        skin:SetFrameStrata(skinStrata)
    end
    if (skin.GetFrameLevel and skin:GetFrameLevel()) ~= skinLevel then
        skin:SetFrameLevel(skinLevel)
    end
    if not skin:IsShown() then
        skin:Show()
    end
    QuickReply:SyncInputStyleToOfficial(false)
    SyncDockedOfficialSkinColors(eb)
    QuickReply._activeDockedSkinEb = eb
end

local function RestoreDockedOfficialEditSkin(eb, keepPreDockLayout)
    if QuickReply._activeDockedSkinEb == eb then
        QuickReply._activeDockedSkinEb = nil
    end
    if not eb then return end
    eb._scOrigTexHidden = nil
    eb._scDockedSizingApplied = nil
    eb._scDockAppliedStrata = nil
    eb._scDockAppliedLevel = nil
    if eb._scDockedSkin then
        eb._scDockedSkin._scSkinPalKey = nil
        eb._scDockedSkin:Hide()
    end
    if keepPreDockLayout then
        return
    end
    if type(eb._scOrigTexAlphas) == "table" then
        for obj, origA in pairs(eb._scOrigTexAlphas) do
            if obj and obj.SetAlpha then
                pcall(obj.SetAlpha, obj, origA or 1)
            end
        end
    end
    if not (InCombatLockdown and InCombatLockdown()) then
        if eb._scOrigHeight and eb.SetHeight then
            pcall(eb.SetHeight, eb, eb._scOrigHeight)
        end
        if eb._scOrigInsets and eb.SetTextInsets then
            pcall(eb.SetTextInsets, eb, eb._scOrigInsets[1], eb._scOrigInsets[2], eb._scOrigInsets[3], eb._scOrigInsets[4])
        end
    end
end

function QuickReply:RestoreOfficialEditBoxFull(eb)
    if not eb then return end
    RestoreDockedOfficialEditSkin(eb, false)
    eb._scDockedToQr = false
    eb._scPreDockedToQr = false
    if not (InCombatLockdown and InCombatLockdown()) then
        if eb._scOrigPoints and #eb._scOrigPoints > 0 and eb.ClearAllPoints then
            pcall(eb.ClearAllPoints, eb)
            for _, pt in ipairs(eb._scOrigPoints) do
                if pt[1] then
                    pcall(eb.SetPoint, eb, pt[1], pt[2], pt[3], pt[4], pt[5])
                end
            end
        end
        if eb._scOrigStrata and eb.SetFrameStrata then
            pcall(eb.SetFrameStrata, eb, eb._scOrigStrata)
        end
        if eb._scOrigLevel and eb.SetFrameLevel then
            pcall(eb.SetFrameLevel, eb, eb._scOrigLevel)
        end
    end
end

function QuickReply:PreDockOfficialEditBoxAnchor(targetEb)
    local eb = targetEb or _G.ChatFrame1EditBox
    if not (eb and eb == _G.ChatFrame1EditBox and QuickReply.frame) then
        return false
    end
    if not (Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode()) then
        return false
    end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or false
    local isProt = (eb.IsProtected and eb:IsProtected()) == true
    if inCombat and isProt then
        return eb._scPreDockedToQr == true
    end
    if not eb._scOrigPoints and eb.GetNumPoints then
        local pts = {}
        for pIdx = 1, eb:GetNumPoints() do
            pts[pIdx] = { eb:GetPoint(pIdx) }
        end
        if #pts > 0 then
            eb._scOrigPoints = pts
        end
        eb._scOrigStrata = eb.GetFrameStrata and eb:GetFrameStrata() or nil
        eb._scOrigLevel = eb.GetFrameLevel and eb:GetFrameLevel() or nil
    end
    if not eb._scOrigHeight and eb.GetHeight then
        local h = eb:GetHeight()
        if h and h > 0 then
            eb._scOrigHeight = h
        end
    end
    if not eb._scOrigInsets and eb.GetTextInsets then
        local okI, l, r, t, b = pcall(eb.GetTextInsets, eb)
        if okI then
            eb._scOrigInsets = { l or 0, r or 0, t or 0, b or 0 }
        end
    end
    if eb.SetIgnoreParentAlpha then
        pcall(eb.SetIgnoreParentAlpha, eb, true)
    end
    local hdrObj = eb.header or (eb.GetName and eb:GetName() and _G[eb:GetName() .. "Header"]) or nil
    if hdrObj and hdrObj.SetIgnoreParentAlpha then
        pcall(hdrObj.SetIgnoreParentAlpha, hdrObj, true)
    end
    pcall(eb.ClearAllPoints, eb)
    pcall(eb.SetPoint, eb, "BOTTOMLEFT", QuickReply.frame, "BOTTOMLEFT", 6, 6)
    pcall(eb.SetPoint, eb, "BOTTOMRIGHT", QuickReply.frame, "BOTTOMRIGHT", -6, 6)
    if eb.SetHeight then
        pcall(eb.SetHeight, eb, 24)
    end
    local baseStrata = (QuickReply.frame.GetFrameStrata and QuickReply.frame:GetFrameStrata()) or "DIALOG"
    local baseLevel = (QuickReply.frame.GetFrameLevel and QuickReply.frame:GetFrameLevel()) or 320
    local preStrata = (baseStrata == "LOW") and "DIALOG" or baseStrata
    local preLevel = (preStrata == "DIALOG") and math.max(344, baseLevel + 24) or (baseLevel + 24)
    if eb.SetFrameStrata then
        pcall(eb.SetFrameStrata, eb, preStrata)
    end
    if eb.SetFrameLevel then
        pcall(eb.SetFrameLevel, eb, preLevel)
    end
    eb._scPreDockedToQr = true
    return true
end

function QuickReply:DockOfficialEditBox(targetEb, isFocused)
    local eb = targetEb
        or (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
        or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
        or _G.ChatFrame1EditBox
    if not eb then return end
    local isOfficialTab = (self.IsOfficialOnlyThread and self:IsOfficialOnlyThread()) == true
    local qrShown = (QuickReply.frame and QuickReply.frame:IsShown()) == true
    if QuickReply.frame and (isFocused or isOfficialTab) then
        if QuickReply.frame.inputWrap then
            QuickReply.frame.inputWrap:Hide()
        end
        if QuickReply.frame.inputBox then
            QuickReply.frame.inputBox:SetAlpha(0)
            QuickReply.frame.inputBox:Hide()
        end
        if QuickReply.frame.btnSend then
            QuickReply.frame.btnSend:Hide()
        end
    end
    if eb.SetIgnoreParentAlpha then
        pcall(eb.SetIgnoreParentAlpha, eb, true)
    end
    local hdrObj = eb.header or (eb.GetName and eb:GetName() and _G[eb:GetName() .. "Header"]) or nil
    if hdrObj and hdrObj.SetIgnoreParentAlpha then
        pcall(hdrObj.SetIgnoreParentAlpha, hdrObj, true)
    end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or false
    local isProt = (eb.IsProtected and eb:IsProtected()) == true
    local baseStrata = (QuickReply.frame and QuickReply.frame.GetFrameStrata and QuickReply.frame:GetFrameStrata()) or "DIALOG"
    local baseLevel = (QuickReply.frame and QuickReply.frame.GetFrameLevel and QuickReply.frame:GetFrameLevel()) or 320
    local focusedStrata = (baseStrata == "DIALOG" and isFocused) and "FULLSCREEN_DIALOG" or baseStrata
    local isAddonMode = (Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode()) == true
    if not inCombat then
        if not eb._scOrigPoints and eb.GetNumPoints then
            local pts = {}
            for pIdx = 1, eb:GetNumPoints() do
                pts[pIdx] = { eb:GetPoint(pIdx) }
            end
            if #pts > 0 then
                eb._scOrigPoints = pts
            end
            eb._scOrigStrata = eb.GetFrameStrata and eb:GetFrameStrata() or nil
            eb._scOrigLevel = eb.GetFrameLevel and eb:GetFrameLevel() or nil
        end
        if isAddonMode then
            if qrShown then
                if not eb._scDockedToQr then
                    pcall(eb.ClearAllPoints, eb)
                    pcall(eb.SetPoint, eb, "BOTTOMLEFT", QuickReply.frame, "BOTTOMLEFT", 6, 6)
                    pcall(eb.SetPoint, eb, "BOTTOMRIGHT", QuickReply.frame, "BOTTOMRIGHT", -6, 6)
                    eb._scDockedToQr = true
                    eb._scPreDockedToQr = true
                end
                ApplyDockedOfficialEditSkin(eb)
                if eb.SetFrameStrata and ((eb.GetFrameStrata and eb:GetFrameStrata()) ~= focusedStrata) then
                    pcall(eb.SetFrameStrata, eb, focusedStrata)
                end
                local wantLevel = baseLevel + 24
                if eb.SetFrameLevel and ((eb.GetFrameLevel and eb:GetFrameLevel()) ~= wantLevel) then
                    pcall(eb.SetFrameLevel, eb, wantLevel)
                end
                if isFocused and eb.Raise then
                    pcall(eb.Raise, eb)
                end
            else
                if eb.SetFrameStrata then
                    pcall(eb.SetFrameStrata, eb, "FULLSCREEN_DIALOG")
                end
                if eb.SetFrameLevel then
                    pcall(eb.SetFrameLevel, eb, 9200)
                end
            end
        end
        if eb.EnableMouse and not isProt then
            local wantMouse = not (self._mousePassThrough == true)
            if eb._scDockAppliedMouse ~= wantMouse then
                eb._scDockAppliedMouse = wantMouse
                pcall(eb.EnableMouse, eb, wantMouse)
            end
        end
        if eb.Show and not (eb.IsShown and eb:IsShown()) then
            pcall(eb.Show, eb)
        end
        if (not isFocused) and eb.HasFocus and eb:HasFocus() and eb.ClearFocus then
            pcall(eb.ClearFocus, eb)
        end
    elseif qrShown and isAddonMode and (eb._scDockedToQr or eb._scPreDockedToQr or not isProt) then
        if not isProt then
            if not (eb._scDockedToQr or eb._scPreDockedToQr) then
                self:PreDockOfficialEditBoxAnchor(eb)
            end
            if eb.SetHeight and not eb._scDockedSizingApplied then
                pcall(eb.SetHeight, eb, 24)
            end
            local wantCombatStrata = isFocused and "FULLSCREEN_DIALOG" or focusedStrata
            if eb.SetFrameStrata and ((eb.GetFrameStrata and eb:GetFrameStrata()) ~= wantCombatStrata) then
                pcall(eb.SetFrameStrata, eb, wantCombatStrata)
            end
            local wantLevel = baseLevel + 24
            if eb.SetFrameLevel and ((eb.GetFrameLevel and eb:GetFrameLevel()) ~= wantLevel) then
                pcall(eb.SetFrameLevel, eb, wantLevel)
            end
            if isFocused and eb.Raise then
                pcall(eb.Raise, eb)
            end
        end
        eb._scDockedToQr = true
        eb._scPreDockedToQr = true
        ApplyDockedOfficialEditSkin(eb)
    elseif isFocused then
        RestoreDockedOfficialEditSkin(eb, false)
        if not isProt then
            if eb.SetFrameStrata then
                pcall(eb.SetFrameStrata, eb, "FULLSCREEN_DIALOG")
            end
            if eb.SetFrameLevel then
                pcall(eb.SetFrameLevel, eb, 9200)
            end
            if eb.Raise then
                pcall(eb.Raise, eb)
            end
        end
    end
    local targetAlpha = isFocused and 1.0 or 0.01
    if eb.SetAlpha then
        local curA = eb.GetAlpha and eb:GetAlpha() or nil
        if curA == nil or math.abs(curA - targetAlpha) > 0.005 then
            pcall(eb.SetAlpha, eb, targetAlpha)
        end
    end
    if not (eb._scDockedSkin and eb._scDockedSkin:IsShown()) then
        SyncDockedOfficialSkinColors(eb)
    end
end

function QuickReply:ShowActiveOfficialEditBox(targetEb)
    local nowT = (GetTime and GetTime()) or 0
    local isNewDock = (targetEb == nil) or (targetEb._scDockedToQr ~= true)
    if isNewDock or self.interactedOutside then
        self._lastProgrammaticFocusAt = nowT
        self.interactedOutside = false
    end
    self:DockOfficialEditBox(targetEb, true)
    self:ElevateToForeground()
    if self.InvalidateFocusVisuals then
        self:InvalidateFocusVisuals()
    end
    if self.UpdateFocusVisuals then
        self:UpdateFocusVisuals()
    end
    if self.WakeOnUpdate then
        self:WakeOnUpdate()
    end
end

function QuickReply:HideTemporaryOfficialEditBox(eb)
    self._hidingDockedOfficial = true
    local wasDocked = (eb ~= nil) and (eb._scDockedToQr == true or (eb._scDockedSkin and eb._scDockedSkin:IsShown()) == true)
    local isAddonMode = (Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode()) == true
    local qrShown = (self.frame and self.frame:IsShown()) == true
    local keepPreDocked = isAddonMode and qrShown and (eb == _G.ChatFrame1EditBox)
    RestoreDockedOfficialEditSkin(eb, keepPreDocked)
    local isOfficialTab = qrShown and self:IsOfficialOnlyThread()
    if QuickReply.frame and (wasDocked or eb == _G.ChatFrame1EditBox or eb == nil) then
        if QuickReply.frame.inputWrap then
            QuickReply.frame.inputWrap:SetShown(not isOfficialTab)
        end
        if QuickReply.frame.inputBox then
            if isOfficialTab then
                QuickReply.frame.inputBox:SetAlpha(0)
                QuickReply.frame.inputBox:Hide()
            else
                QuickReply.frame.inputBox:SetAlpha(1)
                QuickReply.frame.inputBox:Show()
                if QuickReply.frame.inputBox.UpdatePlaceholder then
                    QuickReply.frame.inputBox:UpdatePlaceholder()
                end
            end
        end
        if QuickReply.frame.btnSend then
            QuickReply.frame.btnSend:Hide()
        end
        QuickReply:InvalidateFocusVisuals()
        if QuickReply.UpdateFocusVisuals then
            QuickReply:UpdateFocusVisuals()
        end
    end
    if not eb then
        self._hidingDockedOfficial = false
        return
    end
    eb._scDockedToQr = false
    eb._scDockAppliedMouse = nil
    if eb.SetIgnoreParentAlpha then
        pcall(eb.SetIgnoreParentAlpha, eb, true)
    end
    if eb.SetAlpha then
        pcall(eb.SetAlpha, eb, 0)
    end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or false
    local isProt = (eb.IsProtected and eb:IsProtected()) == true
    if keepPreDocked then
        if not inCombat then
            self:PreDockOfficialEditBoxAnchor(eb)
        end
        if not isProt then
            if eb.EnableMouse then
                pcall(eb.EnableMouse, eb, false)
            end
            if eb.IsShown and eb:IsShown() and eb.Hide then
                pcall(eb.Hide, eb)
            end
        end
    elseif not inCombat then
        eb._scPreDockedToQr = false
        if eb.EnableMouse and not isProt then
            pcall(eb.EnableMouse, eb, false)
        end
        if eb._scOrigPoints and #eb._scOrigPoints > 0 and eb.ClearAllPoints then
            pcall(eb.ClearAllPoints, eb)
            for _, pt in ipairs(eb._scOrigPoints) do
                if pt[1] then
                    pcall(eb.SetPoint, eb, pt[1], pt[2], pt[3], pt[4], pt[5])
                end
            end
        end
        if eb._scOrigStrata and eb.SetFrameStrata then
            pcall(eb.SetFrameStrata, eb, eb._scOrigStrata)
        end
        if eb._scOrigLevel and eb.SetFrameLevel then
            pcall(eb.SetFrameLevel, eb, eb._scOrigLevel)
        end
        if eb.IsShown and eb:IsShown() and eb.Hide and not isProt then
            pcall(eb.Hide, eb)
        end
    end
    self._hidingDockedOfficial = false
end

function QuickReply:UpdateInputSurfaceForActiveThread()
    local f = self.frame
    if not (f and f:IsShown()) then
        return
    end
    local eb1 = _G.ChatFrame1EditBox
    local isAddonMode = (Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode()) == true
    local eb1Focused = isAddonMode and eb1 and eb1.HasFocus and (eb1:HasFocus() == true)
    if self:IsOfficialOnlyThread() or eb1Focused then
        if f.inputWrap then
            f.inputWrap:Hide()
        end
        if f.inputBox then
            f.inputBox:SetAlpha(0)
            f.inputBox:Hide()
        end
        if f.btnSend then
            f.btnSend:Hide()
        end
        self:DockOfficialEditBox(eb1, eb1Focused or self:IsDockedOfficialFocused())
    else
        if self._activeDockedSkinEb or self._dockedOfficialInputActive then
            self:DeactivateDockedOfficialInput()
        elseif isAddonMode and eb1 and not (InCombatLockdown and InCombatLockdown()) then
            self:PreDockOfficialEditBoxAnchor(eb1)
            if eb1.SetAlpha then pcall(eb1.SetAlpha, eb1, 0) end
            if not (eb1.IsProtected and eb1:IsProtected()) then
                if eb1.EnableMouse then pcall(eb1.EnableMouse, eb1, false) end
                if eb1.IsShown and eb1:IsShown() and eb1.Hide then pcall(eb1.Hide, eb1) end
            end
        end
        if f.inputWrap then
            f.inputWrap:Show()
        end
        if f.inputBox then
            f.inputBox:SetAlpha(1)
            f.inputBox:Show()
            if f.inputBox.UpdatePlaceholder then
                f.inputBox:UpdatePlaceholder()
            end
        end
        if f.btnSend then
            f.btnSend:Hide()
        end
    end
end

function QuickReply:ShouldUseDockedOfficialInput(thread)
    return self:IsOfficialOnlyThread(thread)
end

function QuickReply:ActivateDockedOfficialInput(draftText, exactRawOpenLine)
    if not self:IsOfficialOnlyThread() and type(exactRawOpenLine) ~= "string" then
        return false
    end
    if not (Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode()) then
        return false
    end
    local openStr
    if type(exactRawOpenLine) == "string" and exactRawOpenLine ~= "" then
        openStr = exactRawOpenLine
    else
        local gTarget = (ns.Chat and ns.Chat.GetGeneralTargetInfo) and ns.Chat:GetGeneralTargetInfo() or nil
        local prefix = (gTarget and gTarget.slash) or "/s "
        local cleanDraft = (type(draftText) == "string" and draftText ~= "") and draftText or ""
        local curEb = _G.ChatFrame1EditBox
        local wantType = (gTarget and gTarget.channelId and "CHANNEL")
            or (gTarget and gTarget.isYell and "YELL")
            or "SAY"
        local curType = curEb and ((curEb.GetChatType and curEb:GetChatType()) or (curEb.GetAttribute and curEb:GetAttribute("chatType"))) or nil
        local curChan = curEb and ((curEb.GetChannelTarget and curEb:GetChannelTarget()) or (curEb.GetAttribute and curEb:GetAttribute("channelTarget"))) or nil
        local curHdr = curEb and GetOfficialEditBoxHeaderText(curEb) or ""
        local alreadyMatched = (cleanDraft == "")
            and (curType == wantType)
            and (wantType ~= "CHANNEL" or tonumber(curChan) == tonumber(gTarget and gTarget.channelId))
            and (curHdr ~= "")
        openStr = alreadyMatched and "" or (prefix .. cleanDraft)
    end
    self._suppressBlizzSlashRedirectUntil = (GetTime and GetTime() or 0) + 0.6
    self._dockedOfficialInputActive = true
    self._dockedOfficialFallbackHint = false
    self._refocusInputAfterBlizzSend = false
    self._allowTempOfficialEditUntil = (GetTime and GetTime() or 0) + 120
    if self.frame and self.frame.inputBox and self.frame.inputBox.HasFocus and self.frame.inputBox:HasFocus() and self.frame.inputBox.ClearFocus then
        pcall(self.frame.inputBox.ClearFocus, self.frame.inputBox)
    end
    local ok = false
    if _G.ChatFrameUtil and _G.ChatFrameUtil.OpenChat then
        ok = pcall(_G.ChatFrameUtil.OpenChat, openStr)
    elseif _G.ChatFrame_OpenChat then
        ok = pcall(_G.ChatFrame_OpenChat, openStr)
    end
    if not ok then
        self._dockedOfficialInputActive = false
        self._allowTempOfficialEditUntil = nil
        return false
    end
    local activeEb = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
        or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
        or _G.ChatFrame1EditBox
    if activeEb and _G.ChatEdit_ParseText and openStr ~= "/" then
        pcall(_G.ChatEdit_ParseText, activeEb, 0)
    end
    if activeEb and openStr == "/" and activeEb.SetCursorPosition then
        pcall(activeEb.SetCursorPosition, activeEb, 1)
    end
    self:ShowActiveOfficialEditBox(activeEb)
    self:SyncEnterBinding()
    if self.UpdateFocusVisuals then
        self:UpdateFocusVisuals()
    end
    return true
end

function QuickReply:DeactivateDockedOfficialInput()
    self._hidingDockedOfficial = true
    self._dockedOfficialInputActive = false
    self._dockedOfficialFallbackHint = false
    self._allowTempOfficialEditUntil = nil
    self._refocusInputAfterBlizzSend = false
    local activeEb = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
        or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
        or self._activeDockedSkinEb
        or _G.ChatFrame1EditBox
    if activeEb and ((activeEb.HasFocus and activeEb:HasFocus()) or (activeEb.IsVisible and activeEb:IsVisible())) then
        if _G.ChatFrameUtil and _G.ChatFrameUtil.DeactivateChat then
            pcall(_G.ChatFrameUtil.DeactivateChat, activeEb)
        elseif _G.ChatEdit_DeactivateChat then
            pcall(_G.ChatEdit_DeactivateChat, activeEb)
        end
    end
    self:HideTemporaryOfficialEditBox(activeEb or _G.ChatFrame1EditBox)
    self._hidingDockedOfficial = false
end

function QuickReply:TruncateUtf8(raw, maxBytes)
    local s = tostring(raw or "")
    if #s <= maxBytes then
        return s
    end
    local cut = maxBytes
    while cut > 1 do
        local b = string.byte(s, cut + 1)
        if not b or b < 128 or b >= 192 then
            break
        end
        cut = cut - 1
    end
    return s:sub(1, cut) .. "."
end

function QuickReply:IsViewingThread(threadKey)
    return self.frame ~= nil and self.frame:IsShown() and threadKey ~= nil and self.activeKey == threadKey
end

function QuickReply:IsWritableThreadKey(threadKey)
    return type(threadKey) == "string"
        and threadKey ~= ""
        and threadKey ~= "mentions:radar"
        and ns.Chat ~= nil
        and ns.Chat.threads ~= nil
        and ns.Chat.threads[threadKey] ~= nil
end

function QuickReply:RecordRecentSentThread(threadKey)
    if type(threadKey) ~= "string" or threadKey == "" or threadKey == "mentions:radar" then
        return
    end
    self._lastSentThreadKey = threadKey
    self._lastDestinationKey = threadKey
    self._lastSentAt = (GetTime and GetTime()) or 0
    if _G.ChatFrame1EditBox then
        _G.ChatFrame1EditBox._scExplicitSayAt = nil
    end
    if ns.charDb then
        ns.charDb.lastQuickReplyThreadKey = threadKey
    end
    self._manualTabSwitchKey = nil
    self._recentSendTimerSeq = (self._recentSendTimerSeq or 0) + 1
    local seq = self._recentSendTimerSeq
    if C_Timer and C_Timer.After then
        local ttl = (self.RECENT_SEND_WINDOW_SEC or 300) + 0.5
        C_Timer.After(ttl, function()
            if QuickReply._recentSendTimerSeq == seq and QuickReply.SyncEnterBinding then
                QuickReply:SyncEnterBinding()
            end
        end)
    end
    if self.SyncBlizzardStickyChannelForThread then
        self:SyncBlizzardStickyChannelForThread(threadKey)
    end
    if self.SyncEnterBinding then
        self:SyncEnterBinding()
    end
end

function QuickReply:HasRecentSentSession()
    local key = self._lastSentThreadKey
    if type(key) ~= "string" or key == "" then
        return false
    end
    if not (ns.Chat and ns.Chat.threads and ns.Chat.threads[key]) then
        return false
    end
    local elapsed = ((GetTime and GetTime()) or 0) - (self._lastSentAt or 0)
    return elapsed >= 0 and elapsed <= (self.RECENT_SEND_WINDOW_SEC or 300)
end

function QuickReply:GetPreservedThreadKey()
    if self:IsWritableThreadKey(self.activeKey) then
        return self.activeKey
    end
    if self:IsWritableThreadKey(self._lastDestinationKey) then
        return self._lastDestinationKey
    end
    local savedDest = ns.charDb and ns.charDb.lastQuickReplyThreadKey or nil
    if self:IsWritableThreadKey(savedDest) then
        return savedDest
    end
    if self:HasRecentSentSession() then
        return self._lastSentThreadKey
    end
    return nil
end

function QuickReply:GetFirstPendingActionKey(unreadOnly)
    if not (ns.Chat and ns.Chat.GetQuickReplyThreads) then
        return nil
    end
    local pending = ns.Chat:GetQuickReplyThreads()
    local bestUnreadKey, bestUnreadAt = nil, -1
    local bestDraftKey, bestDraftAt = nil, -1
    for _, item in ipairs(pending) do
        if item and item.key and item.key ~= "ch:general" then
            local ts = tonumber(item.lastAt) or 0
            if (item.unread or 0) > 0 then
                if ts >= bestUnreadAt then
                    bestUnreadAt = ts
                    bestUnreadKey = item.key
                end
            elseif (not unreadOnly) and item.hasDraft == true then
                if ts >= bestDraftAt then
                    bestDraftAt = ts
                    bestDraftKey = item.key
                end
            end
        end
    end
    return bestUnreadKey or (not unreadOnly and bestDraftKey or nil)
end

function QuickReply:GetEnterTargetThreadKey()
    if self.frame and self.frame:IsShown() and self:IsWritableThreadKey(self.activeKey) then
        return self.activeKey
    end
    if self:IsWritableThreadKey(self._lastDestinationKey) then
        return self._lastDestinationKey
    end
    local savedDest = ns.charDb and ns.charDb.lastQuickReplyThreadKey or nil
    if self:IsWritableThreadKey(savedDest) then
        return savedDest
    end
    if self:HasRecentSentSession() then
        return self._lastSentThreadKey
    end
    if self:IsWritableThreadKey(self.activeKey) then
        return self.activeKey
    end
    return self:GetFirstPendingActionKey() or (self:IsWritableThreadKey("ch:general") and "ch:general" or nil)
end

function QuickReply:CanRouteThreadToOfficialChat(threadKey)
    if not self:IsWritableThreadKey(threadKey) then
        return false, nil
    end
    local t = ns.Chat and ns.Chat.threads and ns.Chat.threads[threadKey] or nil
    if not t then
        return false, nil
    end
    if threadKey == "notes:self" or threadKey == "mentions:radar" or threadKey == "ch:alliance" or threadKey:sub(1, 5) == "room:" then
        return false, nil
    end
    if threadKey == "ch:general" then
        local gTarget = (ns.Chat and ns.Chat.GetGeneralTargetInfo) and ns.Chat:GetGeneralTargetInfo() or nil
        if gTarget and (gTarget.channelId or gTarget.isYell) then
            return true, "ch:general"
        end
        return false, "ch:general"
    end
    if threadKey == "ch:party" then
        local inGrp = (Compat and Compat.IsInGroup and Compat.IsInGroup()) or (_G.IsInGroup and ns.Safe and ns.Safe.Value(_G.IsInGroup()) == true)
        local inRaid = (Compat and Compat.IsInRaid and Compat.IsInRaid()) or (_G.IsInRaid and ns.Safe and ns.Safe.Value(_G.IsInRaid()) == true)
        if inGrp == true and inRaid ~= true then
            return true, "ch:party"
        end
        if inRaid == true then
            if ns.Chat and ns.Chat.EnsureStaticChannelThread then
                ns.Chat:EnsureStaticChannelThread("ch:raid")
            end
            return true, "ch:raid"
        end
        return false, nil
    end
    if threadKey == "ch:instance" then
        local inInst = (_G.IsInGroup and _G.LE_PARTY_CATEGORY_INSTANCE and ns.Safe and ns.Safe.Value(_G.IsInGroup(_G.LE_PARTY_CATEGORY_INSTANCE)) == true) == true
        if inInst then
            return true, "ch:instance"
        end
        local inGrp = (Compat and Compat.IsInGroup and Compat.IsInGroup()) or (_G.IsInGroup and ns.Safe and ns.Safe.Value(_G.IsInGroup()) == true)
        local inRaid = (Compat and Compat.IsInRaid and Compat.IsInRaid()) or (_G.IsInRaid and ns.Safe and ns.Safe.Value(_G.IsInRaid()) == true)
        if inGrp == true and inRaid ~= true then
            return true, "ch:party"
        end
        return false, nil
    end
    if threadKey == "ch:raid" then
        local inRaid = (Compat and Compat.IsInRaid and Compat.IsInRaid()) or (_G.IsInRaid and ns.Safe and ns.Safe.Value(_G.IsInRaid()) == true)
        return (inRaid == true), (inRaid == true) and "ch:raid" or nil
    end
    if threadKey == "ch:guild" then
        local inGuild = (Compat and Compat.IsInGuild and Compat.IsInGuild()) or (_G.IsInGuild and ns.Safe and ns.Safe.Value(_G.IsInGuild()) == true)
        return (inGuild == true), (inGuild == true) and "ch:guild" or nil
    end
    if threadKey == "ch:officer" then
        local inGuild = (Compat and Compat.IsInGuild and Compat.IsInGuild()) or (_G.IsInGuild and ns.Safe and ns.Safe.Value(_G.IsInGuild()) == true)
        local canOff = (_G.C_GuildInfo and _G.C_GuildInfo.CanViewOfficerNote and _G.C_GuildInfo.CanViewOfficerNote() == true)
            or (_G.CanViewOfficerNote and _G.CanViewOfficerNote() == true)
        local okOff = (inGuild == true) and (canOff == true)
        return okOff, okOff and "ch:officer" or nil
    end
    if t.kind == "PUB_CHANNEL" and t.channelId and ns.Chat and ns.Chat.GetOfficialChannelInfo then
        if ns.Chat:GetOfficialChannelInfo(t.channelId) then
            return true, threadKey
        end
        return false, nil
    end
    if t.kind == "WHISPER" and type(t.targetName) == "string" and t.targetName ~= "" then
        return true, threadKey
    end
    if t.kind == "BN_WHISPER" and (t.bnetAccountID ~= nil or (type(t.bnetName) == "string" and t.bnetName ~= "")) then
        return true, threadKey
    end
    return false, nil
end

function QuickReply:ThreadMatchesBlizzardChannel(eb, threadKey)
    if not (eb and type(threadKey) == "string" and threadKey ~= "") then
        return false
    end
    local cType = (eb.GetChatType and ns.Safe and ns.Safe.String(eb:GetChatType()))
        or (eb.GetAttribute and ns.Safe and ns.Safe.String(eb:GetAttribute("chatType")))
        or nil
    if not cType then
        return false
    end
    local t = ns.Chat and ns.Chat.threads and ns.Chat.threads[threadKey] or nil
    if not t then
        return false
    end
    if threadKey == "ch:party" then
        return cType == "PARTY"
    elseif threadKey == "ch:instance" then
        return cType == "INSTANCE_CHAT" or cType == "BATTLEGROUND"
    elseif threadKey == "ch:raid" then
        return cType == "RAID" or cType == "RAID_WARNING"
    elseif threadKey == "ch:guild" then
        return cType == "GUILD"
    elseif threadKey == "ch:officer" then
        return cType == "OFFICER"
    elseif threadKey == "ch:general" then
        local gTarget = (ns.Chat and ns.Chat.GetGeneralTargetInfo) and ns.Chat:GetGeneralTargetInfo() or nil
        if gTarget and gTarget.channelId then
            local chanTgt = (eb.GetChannelTarget and ns.Safe and ns.Safe.Number(eb:GetChannelTarget()))
                or (eb.GetAttribute and ns.Safe and ns.Safe.Number(eb:GetAttribute("channelTarget")))
                or nil
            return cType == "CHANNEL" and chanTgt == tonumber(gTarget.channelId)
        elseif gTarget and gTarget.isYell then
            return cType == "YELL"
        end
        return cType == "SAY"
    elseif t.kind == "PUB_CHANNEL" and t.channelId then
        local chanTgt = (eb.GetChannelTarget and ns.Safe and ns.Safe.Number(eb:GetChannelTarget()))
            or (eb.GetAttribute and ns.Safe and ns.Safe.Number(eb:GetAttribute("channelTarget")))
            or nil
        return cType == "CHANNEL" and chanTgt == tonumber(t.channelId)
    elseif t.kind == "WHISPER" and t.targetName then
        if cType ~= "WHISPER" then
            return false
        end
        local tellTgt = (eb.GetTellTarget and ns.Safe and ns.Safe.String(eb:GetTellTarget()))
            or (eb.GetAttribute and ns.Safe and ns.Safe.String(eb:GetAttribute("tellTarget")))
            or ""
        local cleanTgt = (Compat and Compat.FormatForeverTarget and Compat.FormatForeverTarget(tellTgt)) or tellTgt
        local wantTgt = (Compat and Compat.FormatForeverTarget and Compat.FormatForeverTarget(t.targetName)) or t.targetName
        return type(cleanTgt) == "string" and type(wantTgt) == "string" and cleanTgt:lower() == wantTgt:lower()
    elseif t.kind == "BN_WHISPER" then
        return cType == "BN_WHISPER"
    end
    return false
end

local COMBAT_STICKY_KIND_BY_THREAD = {
    ["ch:party"] = "PARTY",
    ["ch:raid"] = "RAID",
    ["ch:instance"] = "INSTANCE_CHAT",
    ["ch:guild"] = "GUILD",
    ["ch:officer"] = "OFFICER",
}

function QuickReply:SyncBlizzardStickyChannelForThread(preferredKey)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return false
    end
    if not (Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode()) then
        return false
    end
    local eb = _G.ChatFrame1EditBox or (_G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.editBox) or nil
    if not eb then
        return false
    end
    if eb._scDockedToQr or (eb.IsShown and eb:IsShown()) or (eb.HasFocus and eb:HasFocus()) then
        return false
    end
    if eb.IsProtected and eb:IsProtected() then
        return false
    end
    local resolvedKey = nil
    if type(preferredKey) == "string" and preferredKey ~= "" and preferredKey ~= "ch:general" then
        local okPref, realPref = self:CanRouteThreadToOfficialChat(preferredKey)
        if okPref and realPref then
            resolvedKey = realPref
        end
    end
    if not resolvedKey then
        resolvedKey = self:ResolveCombatOfficialThreadKey()
    end
    local wantKind = resolvedKey and COMBAT_STICKY_KIND_BY_THREAD[resolvedKey] or nil
    if not wantKind then
        return false
    end
    if type(eb.SetChatType) == "function" then
        pcall(eb.SetChatType, eb, wantKind)
    end
    if eb.SetAttribute then
        pcall(eb.SetAttribute, eb, "chatType", wantKind)
        pcall(eb.SetAttribute, eb, "stickyType", wantKind)
    end
    if type(eb.UpdateHeader) == "function" then
        pcall(eb.UpdateHeader, eb)
    elseif _G.ChatFrameUtil and type(_G.ChatFrameUtil.UpdateHeader) == "function" then
        pcall(_G.ChatFrameUtil.UpdateHeader, eb)
    elseif _G.ChatEdit_UpdateHeader then
        pcall(_G.ChatEdit_UpdateHeader, eb)
    end
    return true
end

function QuickReply:ResolveCombatOfficialThreadKey()
    local cands = {}
    local function AddCand(k)
        if type(k) == "string" and k ~= "" then
            cands[#cands + 1] = k
        end
    end
    if self.frame and self.frame:IsShown() then
        if self.activeKey == "ch:general" then
            local canNonSay, resolvedGen = self:CanRouteThreadToOfficialChat("ch:general")
            if canNonSay and resolvedGen then
                return resolvedGen
            end
            return nil
        end
        AddCand(self.activeKey)
    end
    AddCand(self:GetEnterTargetThreadKey())
    AddCand(self:GetPreservedThreadKey())
    AddCand(self._lastSentThreadKey)
    AddCand(self._lastDestinationKey)
    AddCand(ns.charDb and ns.charDb.lastQuickReplyThreadKey or nil)
    -- When selected/recent tab is no longer routable (e.g., Party selected with no active group,
    -- Personal Notes, or SC Room), fall back to live group/raid/instance, open tabs, Guild, or channel General.
    AddCand("ch:instance")
    AddCand("ch:raid")
    AddCand("ch:party")
    AddCand(self:GetFirstPendingActionKey())
    if ns.Chat and ns.Chat.GetQuickReplyThreads then
        for _, item in ipairs(ns.Chat:GetQuickReplyThreads()) do
            if item and item.key and item.key ~= "ch:general" then
                AddCand(item.key)
            end
        end
    end
    AddCand("ch:guild")
    AddCand("ch:officer")
    AddCand("ch:general")

    local seen = {}
    for _, k in ipairs(cands) do
        if not seen[k] then
            seen[k] = true
            local ok, resolved = self:CanRouteThreadToOfficialChat(k)
            if ok and resolved then
                return resolved
            end
        end
    end
    return nil
end

function QuickReply:SaveCurrentDraft()
    if self.suppressDraftSave or not self.frame or not self.activeKey or not ns.Chat or not ns.Chat.SetQuickReplyDraft then
        return
    end
    local txt = self.frame.inputBox and self.frame.inputBox:GetText() or ""
    ns.Chat:SetQuickReplyDraft(self.activeKey, txt)
end

function QuickReply:GetAutoCloseSettings()
    local s = ns.db and ns.db.settings
    local enabled = (s ~= nil) and (s.quickReplyAutoClose == true)
    local delay = tonumber(s and s.quickReplyAutoCloseDelay) or 10
    if delay < 3 then
        delay = 3
    elseif delay > 120 then
        delay = 120
    else
        delay = math.floor(delay + 0.5)
    end
    return enabled, delay
end

function QuickReply:GetFadeDelaySettings()
    local s = ns.db and ns.db.settings
    local enabled = (not s) or (s.quickReplyIdleFade ~= false)
    local raw = s and tonumber(s.quickReplyFadeDelay)
    local delay = (raw ~= nil) and raw or 15
    if delay <= 0 then
        return false, 0
    elseif delay < 3 then
        delay = 3
    elseif delay > 120 then
        delay = 120
    else
        delay = math.floor(delay + 0.5)
    end
    return enabled, delay
end

function QuickReply:IsDungeonPersistentMode()
    local s = ns.db and ns.db.settings
    local qrOn = (not ns.Compat or not ns.Compat.IsModuleEnabled or ns.Compat.IsModuleEnabled("chat"))
        and ((not s) or s.quickReplyEnabled ~= false)
    if not qrOn then
        return false
    end
    if s and s.quickReplyDungeonAutoMode == false then
        return false
    end
    local inInst = (ns.Chat and ns.Chat._IsInDungeonOrRaid and ns.Chat:_IsInDungeonOrRaid()) == true
    if not inInst then
        return false
    end
    if self._closedManuallyInDungeon == true then
        return false
    end
    return true
end

function QuickReply:SyncEscapeCloseRegistration()
    if type(UISpecialFrames) ~= "table" then
        return
    end
    local frameName = "SocialCentralQuickReplyFrame"
    if self:IsPersistentOpenMode() then
        for i = #UISpecialFrames, 1, -1 do
            if UISpecialFrames[i] == frameName then
                table.remove(UISpecialFrames, i)
            end
        end
        return
    end
    for i = 1, #UISpecialFrames do
        if UISpecialFrames[i] == frameName then
            return
        end
    end
    table.insert(UISpecialFrames, frameName)
end

function QuickReply:IsPersistentOpenMode()
    local autoCloseOn = self:GetAutoCloseSettings()
    if not autoCloseOn then
        return true
    end
    if self:IsDungeonPersistentMode() then
        return true
    end
    return false
end

function QuickReply:ShouldFadeInCombat()
    local f = self.frame
    if not (f and f:IsShown()) then
        return false
    end
    if f._scDragging then
        return false
    end
    if f.inputBox and f.inputBox.HasFocus and f.inputBox:HasFocus() then
        return false
    end
    if self:IsDockedOfficialFocused() then
        return false
    end
    local s = ns.db and ns.db.settings
    if not (s and s.quickReplyFadeInCombat == true) then
        return false
    end
    local inCombat = (InCombatLockdown and InCombatLockdown() == true)
        or (UnitAffectingCombat and UnitAffectingCombat("player") == true)
    return inCombat == true
end

function QuickReply:SetCombatMousePassThrough(passThrough)
    local f = self.frame
    if not f then
        self._mousePassThrough = false
        return
    end
    local wantPass = passThrough == true
    if wantPass and ((f.inputBox and f.inputBox.HasFocus and f.inputBox:HasFocus()) or self:IsDockedOfficialFocused()) then
        wantPass = false
    end
    if self._mousePassThrough == wantPass then
        return
    end
    self._mousePassThrough = wantPass
    local mouseOn = not wantPass
    local singleTargets = {
        f, f.header, f.infoBar, f.chipsBar, f.msgBg, f.msgFrame, f.quickPingsBar, f.inputWrap, f.inputBox,
        f.btnClose, f.btnHelp, f.btnLock, f.btnDock, f.btnExpand, f.btnHistory, f.btnCombatLog, f.btnNewChat, f.btnHeaderUnread,
        f.avatarBtn, f.btnMute, f.btnWatch, f.btnInvite, f.btnCard, f.btnGenChannel, f.btnGenFilter, f.btnMsgSearch, f.btnThreadOpts,
        f.btnAutoClose, f.btnWhispers, f.chipsPrevBtn, f.chipsNextBtn, f.btnScrollBottom, f.btnAllQuickReplies, f.btnSend,
        f.msgSearchBar, f.msgSearchBox, f.msgSearchCloseBtn, f.msgScrollThumb,
    }
    for _, obj in ipairs(singleTargets) do
        if obj and obj.EnableMouse then
            pcall(obj.EnableMouse, obj, mouseOn)
        end
    end
    if self._activeDockedSkinEb and self._activeDockedSkinEb._scDockedToQr
        and not (InCombatLockdown and InCombatLockdown())
        and self._activeDockedSkinEb.EnableMouse
        and not (self._activeDockedSkinEb.IsProtected and self._activeDockedSkinEb:IsProtected())
    then
        pcall(self._activeDockedSkinEb.EnableMouse, self._activeDockedSkinEb, mouseOn)
    end
    if f.chips then
        for _, cBtn in ipairs(f.chips) do
            if cBtn and cBtn.EnableMouse then pcall(cBtn.EnableMouse, cBtn, mouseOn) end
        end
    end
    if f.pingBtns then
        for _, pBtn in ipairs(f.pingBtns) do
            if pBtn and pBtn.EnableMouse then pcall(pBtn.EnableMouse, pBtn, mouseOn) end
        end
    end
    if f.msgFrame and f.msgFrame.EnableMouseWheel then
        pcall(f.msgFrame.EnableMouseWheel, f.msgFrame, mouseOn)
    end
    if f.chipsBar and f.chipsBar.EnableMouseWheel then
        pcall(f.chipsBar.EnableMouseWheel, f.chipsBar, mouseOn)
    end
    if wantPass then
        self:ReleaseKeyboardFocus()
        if GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() then
            local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
            if owner then
                for _, obj in ipairs(singleTargets) do
                    if owner == obj then
                        GameTooltip:Hide()
                        break
                    end
                end
            end
        end
    end
end

local function ShouldQuickReplyBeFullyOpaque(selfObj, f)
    local mgr = _G.Menu and _G.Menu.GetManager and _G.Menu.GetManager() or nil
    if (selfObj._ownMenuOpen and mgr and mgr.IsAnyMenuOpen and mgr:IsAnyMenuOpen() == true)
        or selfObj:IsWhispersDropdownShown()
        or (selfObj._closeConfirmModal and selfObj._closeConfirmModal:IsShown())
        or (selfObj.tutorialDialog and selfObj.tutorialDialog:IsShown())
        or (ns.Theme and ns.Theme.IsNpcGuideShown and ns.Theme:IsNpcGuideShown("quick_reply"))
    then
        return true
    end
    if (f.inputBox and f.inputBox.HasFocus and f.inputBox:HasFocus())
        or (f.msgSearchBox and f.msgSearchBox.HasFocus and f.msgSearchBox:HasFocus())
    then
        return true
    end
    if selfObj.IsDockedOfficialFocused and selfObj:IsDockedOfficialFocused() then
        return true
    end
    local now = _G.GetTime and _G.GetTime() or 0
    if (selfObj._activeDockedSkinEb and selfObj._activeDockedSkinEb._scDockedToQr
            and selfObj._activeDockedSkinEb.IsMouseOver and selfObj._activeDockedSkinEb:IsMouseOver())
        or (f.IsMouseOver and f:IsMouseOver())
        or (f.msgFrame and f.msgFrame._scHoveredHyperlink ~= nil)
        or (_G.GameTooltip and f.msgFrame and _G.GameTooltip.IsOwned and _G.GameTooltip:IsOwned(f.msgFrame))
    then
        selfObj._lastOpaqueActivityAt = now
        return true
    end
    if f._scDragging or f._scSizing then
        selfObj._lastOpaqueActivityAt = now
        return true
    end
    local fadeEnabled, fadeDelay = selfObj:GetFadeDelaySettings()
    if not fadeEnabled then
        return true
    end
    local lastAct = math.max(selfObj._lastOpaqueActivityAt or 0, selfObj._lastInteractAt or 0, selfObj.lastInputAt or 0, selfObj.openedAt or 0)
    if (now - lastAct) < fadeDelay then
        return true
    end
    return false
end

local function SetQrForegroundAlpha(obj, alpha)
    if not obj then
        return
    end
    if obj.SetIgnoreParentAlpha then
        pcall(obj.SetIgnoreParentAlpha, obj, true)
    end
    if obj.SetAlpha then
        pcall(obj.SetAlpha, obj, alpha)
    end
end

local function ApplyQuickReplyForegroundAlpha(selfObj, f, contentAlpha, isOfficialTab, backdropAlpha)
    local fgRegions = f._scQrFgRegions
    if not fgRegions then
        fgRegions = {
            f.dragGrip1, f.dragGrip2, f.toolbarLabel, f.btnHeaderUnread,
            f.btnAutoClose, f.btnNewChat, f.btnCombatLog, f.btnHistory, f.btnExpand,
            f.btnDock, f.btnLock, f.btnHelp, f.btnClose,
            f.toneBar, f.icoRim, f.icoBg, f.classIco, f.statusDot,
            f.titleText, f.subText, f.statusText,
            f.btnGenChannel, f.btnGenFilter, f.btnMsgSearch, f.btnThreadOpts,
            f.btnCard, f.btnMute, f.btnMentionCfg, f.btnWatch, f.btnInvite,
            f.chipsBar, f.msgSearchBar, f.stickyHeader, f.msgFrame, f.msgScrollTrack, f.msgEmptyLabel, f.btnScrollBottom, f.inlineNotice,
            f.quickPingsBar, f.inputPrefixFs, f.inputEnterHint, f.charCounter,
        }
        f._scQrFgRegions = fgRegions
    end
    for i = 1, #fgRegions do
        SetQrForegroundAlpha(fgRegions[i], contentAlpha)
    end
    if f.stickyHeader then
        local bgFade = tonumber(backdropAlpha) or contentAlpha
        if f.stickyHeader.bgTex and f.stickyHeader.bgTex.SetAlpha then
            pcall(f.stickyHeader.bgTex.SetAlpha, f.stickyHeader.bgTex, bgFade)
        end
        if f.stickyHeader.bottomLine and f.stickyHeader.bottomLine.SetAlpha then
            pcall(f.stickyHeader.bottomLine.SetAlpha, f.stickyHeader.bottomLine, math.max(0.25, bgFade))
        end
    end
    if f.inputBox and f.inputBox.IsShown and f.inputBox:IsShown() and not isOfficialTab then
        SetQrForegroundAlpha(f.inputBox, contentAlpha)
    end
    local dockedEb = selfObj._activeDockedSkinEb
    local skin = dockedEb and dockedEb._scDockedSkin or nil
    if skin then
        SetQrForegroundAlpha(skin._restingLabel, contentAlpha)
        SetQrForegroundAlpha(skin._restingPlaceholder, contentAlpha)
        SetQrForegroundAlpha(skin._enterHint, contentAlpha)
    end
end

function QuickReply:ApplyCombatFadeStep(elapsed, instant)
    local f = self.frame
    if not f then
        return
    end
    local fadeActive = self:ShouldFadeInCombat()
    self._combatFaded = fadeActive
    if self._lastPassThroughState ~= fadeActive then
        self._lastPassThroughState = fadeActive
        self:SetCombatMousePassThrough(fadeActive)
    end
    local targetAlpha = 1.0
    if fadeActive then
        targetAlpha = 0.0
    elseif not ShouldQuickReplyBeFullyOpaque(self, f) then
        targetAlpha = 0.36
    end
    self._combatFadeTargetAlpha = targetAlpha
    local cur = tonumber(self._combatFadeAlpha)
    if cur == nil then
        cur = targetAlpha
    end
    if instant or not elapsed or elapsed <= 0 then
        cur = targetAlpha
    elseif math.abs(cur - targetAlpha) <= 0.01 then
        cur = targetAlpha
    else
        local speed = (cur < targetAlpha) and 7.0 or (fadeActive and 5.5 or 0.35)
        local step = math.min(0.12, math.max(0.005, elapsed * speed))
        if cur < targetAlpha then
            cur = math.min(targetAlpha, cur + step)
        else
            cur = math.max(targetAlpha, cur - step)
        end
    end
    self._combatFadeAnimating = fadeActive or (math.abs(cur - targetAlpha) > 0.01)
    if self._combatFadeAnimating and self.WakeOnUpdate then
        self:WakeOnUpdate()
    end
    self._combatFadeAlpha = cur
    local contentAlpha
    if fadeActive then
        contentAlpha = (cur <= 0.01) and 0.0 or math.min(1.0, cur * (0.88 / 0.36))
    else
        local t = math.max(0.0, math.min(1.0, (cur - 0.36) / 0.64))
        contentAlpha = 0.88 + 0.12 * t
    end
    local dockedEb = self._activeDockedSkinEb
    local curSkin = dockedEb and dockedEb._scDockedSkin or nil
    local isOfficialTab = (self.IsOfficialOnlyThread and self:IsOfficialOnlyThread()) == true
    if self._lastAppliedQrAlpha ~= cur or self._lastAppliedQrContentAlpha ~= contentAlpha or self._lastAppliedQrSkin ~= curSkin or self._lastAppliedQrOfficial ~= isOfficialTab then
        self._lastAppliedQrAlpha = cur
        self._lastAppliedQrContentAlpha = contentAlpha
        self._lastAppliedQrSkin = curSkin
        self._lastAppliedQrOfficial = isOfficialTab
        if f.SetAlpha then
            f:SetAlpha(cur)
        end
        ApplyQuickReplyForegroundAlpha(self, f, contentAlpha, isOfficialTab, cur)
    end
    if dockedEb and dockedEb._scDockedToQr and dockedEb.SetAlpha then
        local ebAlpha = (dockedEb.HasFocus and dockedEb:HasFocus()) and 1.0 or (fadeActive and 0 or 0.01)
        if self._lastAppliedEbAlpha ~= ebAlpha then
            self._lastAppliedEbAlpha = ebAlpha
            pcall(dockedEb.SetAlpha, dockedEb, ebAlpha)
        end
    else
        self._lastAppliedEbAlpha = nil
    end
end

function QuickReply:SyncInstanceAutoMode(allowOpen)
    local s = ns.db and ns.db.settings
    local qrOn = (not ns.Compat or not ns.Compat.IsModuleEnabled or ns.Compat.IsModuleEnabled("chat"))
        and ((not s) or s.quickReplyEnabled ~= false)
    local autoCloseOn = self:GetAutoCloseSettings()
    local alwaysOpenOn = qrOn and (not autoCloseOn)
    local chatModeChosen = (not ns.Compat or not ns.Compat.HasChosenChatUiMode or ns.Compat.HasChosenChatUiMode())
    local dungeonAutoOn = qrOn and ((not s) or s.quickReplyDungeonAutoMode ~= false)
    local inInst = (ns.Chat and ns.Chat._IsInDungeonOrRaid and ns.Chat:_IsInDungeonOrRaid()) == true

    local wasInInst = self._wasInDungeonOrRaid == true
    self._wasInDungeonOrRaid = inInst

    local function OpenPersistentDefault()
        if not (allowOpen and chatModeChosen and ns.Chat) then
            return false
        end
        local openKey = self:GetPreservedThreadKey() or self:GetFirstPendingActionKey() or "ch:general"
        if not (ns.Chat.threads and ns.Chat.threads[openKey]) and ns.Chat.EnsureStaticChannelThread then
            ns.Chat:EnsureStaticChannelThread("ch:general")
            openKey = "ch:general"
        end
        if not (ns.Chat.threads and ns.Chat.threads[openKey]) then
            return false
        end
        self._openingByPersistentAuto = true
        local ok = self:OpenThread(openKey, false)
        self._openingByPersistentAuto = false
        return ok
    end

    if not inInst then
        local openedAuto = self._openedByDungeonAuto == true
        self._dungeonAutoActive = false
        self._closedManuallyInDungeon = false
        self._openedByDungeonAuto = false
        if ns.Chat then
            ns.Chat._dungeonAutoChannelKey = nil
        end
        self:SyncEscapeCloseRegistration()
        if wasInInst and openedAuto and self.frame and self.frame:IsShown() and autoCloseOn then
            self:SaveCurrentDraft()
            self.frame:Hide()
            return
        end
        if self.frame and self.frame:IsShown() then
            self:UpdateAutoCloseButton()
            self:ApplyCombatFadeStep(0, true)
            if wasInInst then
                self:Refresh()
            end
        elseif alwaysOpenOn and not self._closedManuallyPersistent then
            OpenPersistentDefault()
        end
        return
    end

    if not dungeonAutoOn then
        self._dungeonAutoActive = false
        if ns.Chat then
            ns.Chat._dungeonAutoChannelKey = nil
        end
        self:SyncEscapeCloseRegistration()
        if self.frame and self.frame:IsShown() then
            self:UpdateAutoCloseButton()
            self:ApplyCombatFadeStep(0, true)
            self:Refresh()
        elseif alwaysOpenOn and not self._closedManuallyPersistent then
            OpenPersistentDefault()
        end
        return
    end

    if not wasInInst then
        self._closedManuallyInDungeon = false
    end

    local recKey = (ns.Chat and ns.Chat.GetRecommendedInstanceThreadKey and ns.Chat:GetRecommendedInstanceThreadKey()) or "ch:party"
    if ns.Chat then
        ns.Chat._dungeonAutoChannelKey = recKey
        if ns.Chat.EnsureStaticChannelThread then
            ns.Chat:EnsureStaticChannelThread(recKey)
        end
    end

    if self._closedManuallyInDungeon then
        self:SyncEscapeCloseRegistration()
        return
    end

    self._dungeonAutoActive = true
    self:SyncEscapeCloseRegistration()
    if self.frame and self.frame:IsShown() then
        if (not wasInInst) and allowOpen and recKey and self.activeKey ~= recKey then
            local box = self.frame.inputBox
            local isTyping = box and box.HasFocus and box:HasFocus() == true
            if not isTyping then
                self:SaveCurrentDraft()
                self:SelectThread(recKey, false)
            end
        end
        self:UpdateAutoCloseButton()
        self:ApplyCombatFadeStep(0, true)
        self:Refresh()
        return
    end

    if allowOpen and ns.Chat then
        local openKey = ((not wasInInst) and recKey) or self:GetPreservedThreadKey() or recKey
        self._openedByDungeonAuto = true
        self._openingByDungeonAuto = true
        local ok = self:OpenThread(openKey, false)
        self._openingByDungeonAuto = false
        if not ok then
            self._openedByDungeonAuto = false
        end
    end
end

function QuickReply:UpdateFocusVisuals(nowSec)
    local f = self.frame
    if not f then
        return
    end
    local box = f.inputBox
    local tourDemoFocused = nil
    local gKey, gStep = nil, nil
    if ns.Theme and ns.Theme.GetActiveNpcGuideStep then
        gKey, gStep = ns.Theme:GetActiveNpcGuideStep()
    end
    if gKey == "quick_reply" then
        if gStep == 1 then
            local cycleIdx = (math.floor((nowSec or (GetTime and GetTime()) or 0) / 1.0) % 6) + 1
            local cycleTones = { "whisper", "group", "raid", "guild", "bnet", "room" }
            local dSpec = ns.Theme and ns.Theme.GetChatToneSpec and ns.Theme:GetChatToneSpec(cycleTones[cycleIdx])
            if dSpec and dSpec.accent then
                self._activeToneRgb = dSpec.accent
                tourDemoFocused = true
            end
        elseif gStep == 4 then
            tourDemoFocused = ((math.floor((nowSec or (GetTime and GetTime()) or 0) / 1.35) % 2) == 0)
        end
    else
        local t = self.activeKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[self.activeKey]
        if t and ns.Theme and ns.Theme.GetChatToneForKind and ns.Theme.GetChatToneSpec then
            local realSpec = ns.Theme:GetChatToneSpec(ns.Theme:GetChatToneForKind(t.kind))
            if realSpec and realSpec.accent then
                self._activeToneRgb = realSpec.accent
            end
        end
    end

    local tone = self._activeToneRgb
    local r = (tone and tone[1]) or 1.00
    local g = (tone and tone[2]) or 0.50
    local b = (tone and tone[3]) or 1.00

    local dockedOfficialFocus = self:IsDockedOfficialFocused()
    local keybdOn = dockedOfficialFocus or (box and ((not box.IsKeyboardEnabled) or (box:IsKeyboardEnabled() == true)))
    local hasFocus = dockedOfficialFocus or ((not self:IsOfficialOnlyThread()) and box and box.HasFocus and (box:HasFocus() == true))
    local isFocused = (tourDemoFocused ~= nil) and tourDemoFocused or (f:IsShown() and hasFocus and keybdOn)

    local t = nowSec or (GetTime and GetTime()) or 0
    local edges = f._focusBorderEdges
    local halo = f._focusHaloLayer

    if isFocused then
        if self._focusActiveShown
            and self._focusAnimNextAt and t < self._focusAnimNextAt
            and self._focusAnimToneR == r and self._focusAnimToneG == g and self._focusAnimToneB == b
        then
            return
        end
        self._focusAnimNextAt = t + 0.05
        self._focusAnimToneR = r
        self._focusAnimToneG = g
        self._focusAnimToneB = b
        self._focusActiveShown = true
        self._focusDimR = nil
        self._focusDimG = nil
        self._focusDimB = nil
        self._focusDimHover = nil
        local wave = 0.5 + 0.5 * math.sin(t * 4.8)
        local lift = 0.22 + 0.28 * wave
        local br = r + (1 - r) * lift
        local bg = g + (1 - g) * lift
        local bb = b + (1 - b) * lift
        local coreAlpha = 0.88 + 0.12 * wave

        if f.SetBackdropBorderColor then
            f:SetBackdropBorderColor(br, bg, bb, 1.0)
        end
        if f.toneBar and f.toneBar.SetColorTexture then
            f.toneBar:SetColorTexture(br, bg, bb, 1.0)
        end
        if edges then
            edges:SetAlpha(1)
            edges.top:SetColorTexture(br, bg, bb, coreAlpha)
            edges.bottom:SetColorTexture(br, bg, bb, coreAlpha)
            edges.left:SetColorTexture(br, bg, bb, coreAlpha)
            edges.right:SetColorTexture(br, bg, bb, coreAlpha)
            edges.top:Show()
            edges.bottom:Show()
            edges.left:Show()
            edges.right:Show()

            if edges.shimmerTop and edges.shimmerBot then
                local fw = math.max(80, f:GetWidth() or 444)
                local sw = math.max(48, math.floor(fw * 0.24))
                local travel = fw - sw
                local prog = (t * 0.72) % 1.0
                local sx = math.floor(prog * travel + 0.5)
                local sxRev = math.floor((1.0 - prog) * travel + 0.5)
                if edges._lastSw ~= sw then
                    edges._lastSw = sw
                    edges.shimmerTop:SetWidth(sw)
                    edges.shimmerBot:SetWidth(sw)
                end
                if math.abs((edges._lastSx or -99) - sx) >= 2 then
                    edges._lastSx = sx
                    edges.shimmerTop:ClearAllPoints()
                    edges.shimmerTop:SetPoint("TOPLEFT", f, "TOPLEFT", sx, 0)
                    edges.shimmerBot:ClearAllPoints()
                    edges.shimmerBot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", sxRev, 0)
                end
                edges.shimmerTop:SetColorTexture(1, 1, 1, 0.55 + 0.35 * wave)
                edges.shimmerTop:Show()
                edges.shimmerBot:SetColorTexture(1, 1, 1, 0.55 + 0.35 * wave)
                edges.shimmerBot:Show()
            end
        end
        if halo then
            local ha = 0.34 + 0.34 * wave
            halo:SetAlpha(1)
            halo.top:SetColorTexture(r, g, b, ha)
            halo.bottom:SetColorTexture(r, g, b, ha)
            halo.left:SetColorTexture(r, g, b, ha)
            halo.right:SetColorTexture(r, g, b, ha)
            halo:Show()
        end
        local inputWrapTarget = f.inputWrap or box
        self._focusBorderR, self._focusBorderG, self._focusBorderB = br, bg, bb
        if inputWrapTarget and inputWrapTarget.SetBackdropBorderColor then
            inputWrapTarget._scInputStyleSig = nil
            inputWrapTarget:SetBackdropBorderColor(br, bg, bb, 1.0)
            inputWrapTarget:SetBackdropColor(r * 0.11 + 0.05, g * 0.11 + 0.05, b * 0.11 + 0.05, 1.0)
            if inputWrapTarget._solidBg then
                inputWrapTarget._solidBg:SetVertexColor(r * 0.11 + 0.05, g * 0.11 + 0.05, b * 0.11 + 0.05, 1.0)
            end
        end
    else
        self._focusActiveShown = false
        self._focusAnimNextAt = nil
        local inputWrapTarget = f.inputWrap or box
        local hov = ((box and box._scHovered == true) or (f.inputWrap and f.inputWrap.IsMouseOver and f.inputWrap:IsMouseOver() == true)) == true
        if self._focusDimR == r and self._focusDimG == g and self._focusDimB == b and self._focusDimHover == hov and not (inputWrapTarget and inputWrapTarget._scInputStyleSig ~= nil) then
            return
        end
        self._focusDimR = r
        self._focusDimG = g
        self._focusDimB = b
        self._focusDimHover = hov
        local dr = 0.19 + r * 0.10
        local dg = 0.20 + g * 0.10
        local db = 0.23 + b * 0.10
        if f.SetBackdropBorderColor then
            f:SetBackdropBorderColor(dr, dg, db, 0.90)
        end
        if f.toneBar and f.toneBar.SetColorTexture then
            f.toneBar:SetColorTexture(r * 0.45, g * 0.45, b * 0.45, 0.55)
        end
        if edges then
            edges.top:SetColorTexture(dr, dg, db, 0.72)
            edges.bottom:SetColorTexture(dr, dg, db, 0.72)
            edges.left:SetColorTexture(dr, dg, db, 0.72)
            edges.right:SetColorTexture(dr, dg, db, 0.72)
            if edges.shimmerTop then edges.shimmerTop:Hide() end
            if edges.shimmerBot then edges.shimmerBot:Hide() end
        end
        if halo then
            halo:Hide()
        end
        if inputWrapTarget and inputWrapTarget.SetBackdropBorderColor then
            inputWrapTarget._scInputStyleSig = nil
            local mult = hov and 0.48 or 0.28
            inputWrapTarget:SetBackdropBorderColor(
                math.min(1, 0.22 + r * mult),
                math.min(1, 0.23 + g * mult),
                math.min(1, 0.26 + b * mult),
                0.95
            )
            local pal = ns.Theme and ns.Theme.GetPalette and ns.Theme:GetPalette() or nil
            local inBg = (pal and pal.inputBg) or QuickReply._DEF_IN_BG
            inputWrapTarget:SetBackdropColor(inBg[1], inBg[2], inBg[3], 1.0)
            if inputWrapTarget._solidBg then
                inputWrapTarget._solidBg:SetVertexColor(inBg[1], inBg[2], inBg[3], 1.0)
            end
        end
    end
    if QuickReply._activeDockedSkinEb then
        SyncDockedOfficialSkinColors(QuickReply._activeDockedSkinEb)
    end
end

local QUICK_REPLY_GAME_PANEL_NAMES = {
    "QuestFrame", "GossipFrame", "MerchantFrame", "ClassTrainerFrame",
    "BankFrame", "MailFrame", "AuctionFrame", "AuctionHouseFrame",
    "TradeFrame", "ItemTextFrame", "PetitionFrame", "TabardFrame",
    "GuildRegistrarFrame", "LootFrame", "WorldMapFrame", "CharacterFrame",
    "SpellBookFrame", "QuestLogFrame", "FriendsFrame", "CommunitiesFrame",
    "LFGParentFrame", "PVEFrame", "GameMenuFrame", "SettingsPanel",
    "InterfaceOptionsFrame", "StaticPopup1", "StaticPopup2",
    "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2",
    "ContainerFrame3", "ContainerFrame4", "ContainerFrame5", "ContainerFrame6",
    "SocialCentralFrame",
}

function QuickReply:IsInputFocused()
    local f = self.frame
    if not f then return false end
    if (f.inputBox and f.inputBox.HasFocus and f.inputBox:HasFocus())
        or (f.msgSearchBox and f.msgSearchBox.HasFocus and f.msgSearchBox:HasFocus())
    then
        return true
    end
    if self.IsDockedOfficialFocused and self:IsDockedOfficialFocused() then
        return true
    end
    return false
end

QuickReply._uiPanelSlots = QuickReply._uiPanelSlots or { "left", "center", "right", "doublewide", "fullscreen" }

function QuickReply:IsAnyBlizzardGamePanelOpen()
    if _G.GetUIPanel then
        local slots = self._uiPanelSlots
        for i = 1, #slots do
            local pFrame = _G.GetUIPanel(slots[i])
            if pFrame and pFrame.IsShown and pFrame:IsShown() then
                return true
            end
        end
    end
    for i = 1, #QUICK_REPLY_GAME_PANEL_NAMES do
        local gf = _G[QUICK_REPLY_GAME_PANEL_NAMES[i]]
        if gf and gf.IsShown and gf:IsShown() then
            return true
        end
    end
    return false
end

function QuickReply:ApplySmartZOrder()
    local f = self.frame
    if not f then return end
    local yielded = (self._yieldedToGameUI == true)
    local eb = self._activeDockedSkinEb or _G.ChatFrame1EditBox
    local inCombatNow = (InCombatLockdown and InCombatLockdown()) or false
    local ebDocked = (eb and (eb._scDockedToQr or eb._scPreDockedToQr)) == true
    local ebProt = ebDocked and (eb.IsProtected and eb:IsProtected()) == true
    local ebFocused = ebDocked and (eb.HasFocus and eb:HasFocus() == true) == true
    local strata = yielded and "LOW" or ((self:IsInputFocused() and self:IsAnyBlizzardGamePanelOpen()) and "FULLSCREEN_DIALOG" or "DIALOG")
    local baseLevel = yielded and 220 or 320
    if inCombatNow and ebProt and ebFocused then
        local liveEbStrata = eb.GetFrameStrata and eb:GetFrameStrata() or nil
        if liveEbStrata == "DIALOG" or liveEbStrata == "HIGH" or liveEbStrata == "MEDIUM" then
            strata = liveEbStrata
        end
        local liveEbLevel = eb.GetFrameLevel and eb:GetFrameLevel() or nil
        if liveEbLevel and liveEbLevel > 10 then
            baseLevel = math.min(baseLevel, liveEbLevel - 10)
        end
    end
    if f.GetFrameStrata and f:GetFrameStrata() ~= strata and f.SetFrameStrata then
        f:SetFrameStrata(strata)
    end
    if f.GetFrameLevel and f:GetFrameLevel() ~= baseLevel and f.SetFrameLevel then
        f:SetFrameLevel(baseLevel)
    end
    if f._focusHaloLayer and f._focusHaloLayer.SetFrameLevel then
        f._focusHaloLayer:SetFrameLevel(math.max(1, baseLevel - 1))
    end
    if f._focusBorderEdges and f._focusBorderEdges.SetFrameLevel then
        f._focusBorderEdges:SetFrameLevel(baseLevel + 12)
    end
    if type(f._scResizeGrips) == "table" then
        for _, g in ipairs(f._scResizeGrips) do
            if g and g.SetFrameLevel then
                g:SetFrameLevel(baseLevel + 18)
            end
        end
    end
    if ebDocked then
        local ebStrata = (not yielded and ebFocused) and "FULLSCREEN_DIALOG" or strata
        if (not inCombatNow) or (not ebProt) then
            if eb.SetFrameStrata then pcall(eb.SetFrameStrata, eb, ebStrata) end
            if eb.SetFrameLevel then pcall(eb.SetFrameLevel, eb, baseLevel + 24) end
        end
        if eb._scDockedSkin then
            local skinStrata = strata
            local skinLevel = baseLevel + 6
            if inCombatNow and ebProt then
                local liveEbStrata = eb.GetFrameStrata and eb:GetFrameStrata() or nil
                local liveEbLevel = eb.GetFrameLevel and eb:GetFrameLevel() or nil
                if liveEbStrata then skinStrata = liveEbStrata end
                if liveEbLevel and liveEbLevel > 1 then
                    skinLevel = math.max(1, math.min(skinLevel, liveEbLevel - 2))
                end
            end
            if eb._scDockedSkin.SetFrameStrata then eb._scDockedSkin:SetFrameStrata(skinStrata) end
            if eb._scDockedSkin.SetFrameLevel then eb._scDockedSkin:SetFrameLevel(skinLevel) end
        end
    end
    if not yielded and f:IsShown() and f.Raise then
        f:Raise()
    end
end

function QuickReply:ElevateToForeground()
    self._yieldedToGameUI = false
    self:ApplySmartZOrder()
end

function QuickReply:YieldToGameUI(forceIfPanelOpen)
    if self:IsInputFocused() then
        return false
    end
    if forceIfPanelOpen and not self:IsAnyBlizzardGamePanelOpen() then
        self._yieldedToGameUI = false
        self:ApplySmartZOrder()
        return false
    end
    self._yieldedToGameUI = true
    self:ApplySmartZOrder()
    return true
end

function QuickReply:YieldToGameUIIfPanelOpen()
    if self:IsInputFocused() then
        return false
    end
    if self:IsAnyBlizzardGamePanelOpen() then
        self._yieldedToGameUI = true
        self:ApplySmartZOrder()
        return true
    end
    if self._yieldedToGameUI then
        self._yieldedToGameUI = false
        self:ApplySmartZOrder()
    end
    return false
end

function QuickReply:InstallSmartZOrderHooks()
    if self._smartZOrderHooked then
        return
    end
    self._smartZOrderHooked = true
    local function OnPanelOpened()
        if not (QuickReply.frame and QuickReply.frame:IsShown()) then return end
        if not QuickReply:IsInputFocused() then
            QuickReply:YieldToGameUI(false)
        end
    end
    local function OnPanelClosed()
        if not (QuickReply.frame and QuickReply.frame:IsShown()) then return end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if QuickReply.frame and QuickReply.frame:IsShown() then
                    if not QuickReply:IsAnyBlizzardGamePanelOpen() then
                        QuickReply:ElevateToForeground()
                    end
                end
            end)
        elseif not QuickReply:IsAnyBlizzardGamePanelOpen() then
            QuickReply:ElevateToForeground()
        end
    end
    if hooksecurefunc then
        if type(_G.ShowUIPanel) == "function" then
            pcall(hooksecurefunc, "ShowUIPanel", OnPanelOpened)
        end
        if type(_G.HideUIPanel) == "function" then
            pcall(hooksecurefunc, "HideUIPanel", OnPanelClosed)
        end
    end
    for _, evName in ipairs({
        "QUEST_DETAIL", "QUEST_GREETING", "QUEST_PROGRESS", "QUEST_COMPLETE",
        "GOSSIP_SHOW", "MERCHANT_SHOW", "MAIL_SHOW", "BANKFRAME_OPENED",
        "TRADE_SHOW", "TRAINER_SHOW", "TAXIMAP_OPENED", "AUCTION_HOUSE_SHOW", "LOOT_OPENED",
    }) do
        ns.RegisterEvent(self, evName, OnPanelOpened)
    end
    for _, evName in ipairs({
        "QUEST_FINISHED", "GOSSIP_CLOSED", "MERCHANT_CLOSED", "MAIL_CLOSED",
        "BANKFRAME_CLOSED", "TRADE_CLOSED", "TRAINER_CLOSED", "TAXIMAP_CLOSED",
        "AUCTION_HOUSE_CLOSED", "LOOT_CLOSED",
    }) do
        ns.RegisterEvent(self, evName, OnPanelClosed)
    end
    for _, gName in ipairs({
        "WorldMapFrame", "GameMenuFrame", "SettingsPanel", "ContainerFrameCombinedBags",
        "ContainerFrame1", "ContainerFrame2", "ContainerFrame3", "ContainerFrame4", "ContainerFrame5", "ContainerFrame6",
        "SocialCentralFrame",
    }) do
        local gf = _G[gName]
        if gf and gf.HookScript and not gf._scQrZHooked then
            gf._scQrZHooked = true
            pcall(gf.HookScript, gf, "OnShow", OnPanelOpened)
            pcall(gf.HookScript, gf, "OnHide", OnPanelClosed)
        end
    end
end

function QuickReply:FocusInputBox(initialText)
    local focusAt = (GetTime and GetTime()) or 0
    self._lastProgrammaticFocusAt = focusAt
    self:ElevateToForeground()
    self:SnapshotMouseButtonState()
    self._focusEnsureSeq = (self._focusEnsureSeq or 0) + 1
    local focusSeq = self._focusEnsureSeq
    local f = self.frame
    if not (f and f.inputBox) then
        return false
    end
    if self:IsOfficialOnlyThread() then
        local existing = (type(initialText) == "string" and initialText ~= "") and initialText or ""
        if self:ActivateDockedOfficialInput(existing) then
            self.interactedOutside = false
            self.lastInputAt = focusAt
            self._lastOpaqueActivityAt = focusAt
            self.idleCountdown = nil
            return true
        end
        local dockedEb = self._activeDockedSkinEb or _G.ChatFrame1EditBox
        if dockedEb and dockedEb._scDockedToQr and dockedEb.SetFocus then
            pcall(dockedEb.SetFocus, dockedEb)
            self.interactedOutside = false
            self.lastInputAt = focusAt
            self._lastOpaqueActivityAt = focusAt
            self.idleCountdown = nil
            self:ElevateToForeground()
            self:UpdateFocusVisuals()
            return true
        end
        return false
    end
    local box = f.inputBox
    self:SetCombatMousePassThrough(false)
    if box.Enable and box.IsEnabled and not box:IsEnabled() then
        pcall(box.Enable, box)
    end
    if not box:IsShown() then
        box:Show()
    end
    box:SetAlpha(1)
    if box.EnableKeyboard then
        pcall(box.EnableKeyboard, box, true)
    end
    if box.SetFocus then
        pcall(box.SetFocus, box)
    end
    self:ApplyCombatFadeStep(0, true)
    self.interactedOutside = false
    self.lastInputAt = focusAt
    self._lastOpaqueActivityAt = focusAt
    self.idleCountdown = nil
    if box.placeholder and (box:GetText() or "") == "" then
        box.placeholder:SetText((self.frame and self.frame._lastInputPlaceholder) or L["Type a quick reply..."])
    end
    self:ElevateToForeground()
    self:UpdateFocusVisuals()
    if self.WakeOnUpdate then
        self:WakeOnUpdate()
    end
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, function()
            if not (self.frame and self.frame:IsShown() and self._focusEnsureSeq == focusSeq) then
                return
            end
            if self.interactedOutside or self:IsOfficialOnlyThread() then
                return
            end
            local curFocus = _G.GetCurrentKeyBoardFocus and _G.GetCurrentKeyBoardFocus() or nil
            if curFocus and curFocus ~= box then
                pcall(box.SetFocus, box)
            end
            if box.EnableKeyboard then
                pcall(box.EnableKeyboard, box, true)
            end
            if (not box.HasFocus or not box:HasFocus()) and box.SetFocus then
                pcall(box.SetFocus, box)
            end
            self:ElevateToForeground()
            self:SnapshotMouseButtonState()
            self:UpdateFocusVisuals()
        end)
    end
    return true
end

function QuickReply:ReleaseKeyboardFocus(preserveOfficial)
    self._focusEnsureSeq = (self._focusEnsureSeq or 0) + 1
    local f = self.frame
    if not f or not f.inputBox then
        return
    end
    self:SaveCurrentDraft()
    if (not preserveOfficial) and self:IsDockedOfficialFocused() then
        local eb = self._activeDockedSkinEb
            or (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
            or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
            or _G.ChatFrame1EditBox
        if eb then
            if _G.ChatFrameUtil and _G.ChatFrameUtil.DeactivateChat then
                pcall(_G.ChatFrameUtil.DeactivateChat, eb)
            elseif _G.ChatEdit_DeactivateChat then
                pcall(_G.ChatEdit_DeactivateChat, eb)
            elseif eb.ClearFocus then
                pcall(eb.ClearFocus, eb)
            end
        end
    end
    if f.inputBox.HasFocus and f.inputBox:HasFocus() and f.inputBox.ClearFocus then
        pcall(f.inputBox.ClearFocus, f.inputBox)
    end
    if f.inputBox.EnableKeyboard then
        pcall(f.inputBox.EnableKeyboard, f.inputBox, false)
    end
    if f.inputBox.placeholder and (f.inputBox:GetText() or "") == "" then
        f.inputBox.placeholder:SetText(f._lastInputPlaceholder or L["Click here to type..."])
    end
    self:UpdateFocusVisuals()
    self:YieldToGameUIIfPanelOpen()
    if self.SyncEnterBinding then
        self:SyncEnterBinding()
    end
end

local QUICK_REPLY_MOUSE_BUTTONS = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5" }

function QuickReply:MarkOutsideInteraction()
    if not (self.frame and self.frame:IsShown()) then
        return
    end
    if self:IsInputFocused() then
        self:ReleaseKeyboardFocus()
    end
    self.interactedOutside = true
    self.lastInputAt = 0
    if not self._yieldedToGameUI then
        self:YieldToGameUIIfPanelOpen()
    end
end

function QuickReply:SnapshotMouseButtonState()
    if not IsMouseButtonDown then
        return
    end
    self._mouseDownPrev = self._mouseDownPrev or {}
    for _, btnName in ipairs(QUICK_REPLY_MOUSE_BUTTONS) do
        local ok, down = pcall(IsMouseButtonDown, btnName)
        self._mouseDownPrev[btnName] = (ok and down == true) and true or false
    end
end

function QuickReply:CheckExternalMouseButtons()
    local f = self.frame
    if not (f and f:IsShown() and IsMouseButtonDown) then
        return
    end
    self._mouseDownPrev = self._mouseDownPrev or {}
    local overFrame = (not self._yieldedToGameUI) and (f.IsMouseOver and f:IsMouseOver()) == true
    if (not overFrame) and self._activeDockedSkinEb and self._activeDockedSkinEb._scDockedToQr
        and self._activeDockedSkinEb.IsMouseOver and self._activeDockedSkinEb:IsMouseOver()
    then
        overFrame = true
    end
    if (not overFrame) and self._combatLogFrame and self._combatLogFrame:IsShown() and self._combatLogFrame.IsMouseOver and self._combatLogFrame:IsMouseOver() then
        overFrame = true
    end
    if (not overFrame) and _G.SocialCentralHelpPopup and _G.SocialCentralHelpPopup:IsShown() and _G.SocialCentralHelpPopup.IsMouseOver and _G.SocialCentralHelpPopup:IsMouseOver() then
        overFrame = true
    end
    if (not overFrame) and self._closeConfirmModal and self._closeConfirmModal:IsShown() and self._closeConfirmModal.IsMouseOver and self._closeConfirmModal:IsMouseOver() then
        overFrame = true
    end
    local mgr = Menu and Menu.GetManager and Menu.GetManager() or nil
    local menuOpen = ((self._ownMenuOpen and mgr and mgr.IsAnyMenuOpen and mgr:IsAnyMenuOpen()) == true)
        or (self.IsWhispersDropdownShown and self:IsWhispersDropdownShown() == true)
        or ((self._closeConfirmModal and self._closeConfirmModal:IsShown()) == true)
    local shiftLinkHeld = ((IsShiftKeyDown and IsShiftKeyDown() == true) or (IsModifiedClick and IsModifiedClick("CHATLINK") == true)) == true
    local justFocused = self._lastProgrammaticFocusAt and (((GetTime and GetTime()) or 0) - self._lastProgrammaticFocusAt) < 0.25
    for _, btnName in ipairs(QUICK_REPLY_MOUSE_BUTTONS) do
        local ok, down = pcall(IsMouseButtonDown, btnName)
        local isDown = (ok and down == true)
        local wasDown = self._mouseDownPrev[btnName] == true
        self._mouseDownPrev[btnName] = isDown
        if isDown and not wasDown and not justFocused then
            if btnName == "LeftButton" and shiftLinkHeld then
                local nowT = (GetTime and GetTime()) or 0
                self.interactedOutside = false
                self.lastInputAt = nowT
                self._lastOpaqueActivityAt = nowT
                self.idleCountdown = nil
            elseif btnName == "MiddleButton" or btnName == "Button4" or btnName == "Button5" then
                self:MarkOutsideInteraction()
            elseif not overFrame and not menuOpen then
                self:MarkOutsideInteraction()
            end
        end
    end
end

function QuickReply:GetLockMode()
    local s = ns.db and ns.db.settings
    if not s then return "unlocked" end
    local m = s.quickReplyLockMode
    if m == "unlocked" or m == "pos_locked" or m == "full_locked" then
        return m
    end
    if s.quickReplyLocked == true then
        return "full_locked"
    end
    return "unlocked"
end

function QuickReply:IsLocked()
    return self:GetLockMode() ~= "unlocked"
end

function QuickReply:IsResizeLocked()
    return self:GetLockMode() == "full_locked"
end

QuickReply._LOCK_COL_UNLOCK = QuickReply._LOCK_COL_UNLOCK or { 0.38, 0.96, 0.60 }
QuickReply._LOCK_COL_POS = QuickReply._LOCK_COL_POS or { 0.38, 0.84, 1.00 }
QuickReply._LOCK_COL_FULL = QuickReply._LOCK_COL_FULL or { 1.0, 0.84, 0.34 }
QuickReply._LOCK_ACT_POS = QuickReply._LOCK_ACT_POS or { 0.32, 0.76, 0.98 }
QuickReply._LOCK_ACT_FULL = QuickReply._LOCK_ACT_FULL or { 0.98, 0.68, 0.22 }
QuickReply._DOCK_COL_ON = QuickReply._DOCK_COL_ON or { 0.45, 0.85, 1.0 }
QuickReply._DOCK_COL_OFF = QuickReply._DOCK_COL_OFF or { 0.78, 0.82, 0.88 }

function QuickReply:ApplyLockState()
    local mode = self:GetLockMode()
    local locked = (mode ~= "unlocked")
    local resizeLocked = (mode == "full_locked")
    local f = self.frame
    if f then
        local modeChanged = (f._scAppliedLockMode ~= mode)
        f._scAppliedLockMode = mode
        f._scLocked = locked
        f._scResizeLocked = resizeLocked
        if resizeLocked and f._scStopResize then
            f:_scStopResize(false)
        end
        if modeChanged then
            if type(f._scResizeGrips) == "table" then
                for _, g in ipairs(f._scResizeGrips) do
                    if g and g.SetShown then
                        g:SetShown(not resizeLocked)
                    end
                end
            end
            if f._scSizeCornerIcon then
                f._scSizeCornerIcon:SetShown(not resizeLocked)
            end
        end
        if locked and f._scDragging and f._scEndDrag then
            f:_scEndDrag()
        elseif not locked then
            if f._scDragging and (not IsMouseButtonDown or not IsMouseButtonDown("LeftButton")) then
                f._scDragging = false
            end
            if not self._mousePassThrough and ns.Theme and ns.Theme.AttachDragHandle then
                if modeChanged or not f._scDragHandlesReady then
                    f._scDragHandlesReady = true
                    pcall(f.EnableMouse, f, true)
                    if f.header then ns.Theme:AttachDragHandle(f.header, f) end
                    if f.infoBar then ns.Theme:AttachDragHandle(f.infoBar, f) end
                    if f.chipsBar then ns.Theme:AttachDragHandle(f.chipsBar, f) end
                    if f.msgBg then ns.Theme:AttachDragHandle(f.msgBg, f) end
                    if f.msgFrame then ns.Theme:AttachDragHandle(f.msgFrame, f) end
                    if f.quickPingsBar then ns.Theme:AttachDragHandle(f.quickPingsBar, f) end
                end
            end
        end
        if modeChanged then
            if f.dragGrip1 then
                if locked then
                    f.dragGrip1:SetVertexColor(0.55, 0.62, 0.72, 0.30)
                else
                    f.dragGrip1:SetVertexColor(0.35, 0.95, 0.55, 0.85)
                end
            end
            if f.dragGrip2 then
                if locked then
                    f.dragGrip2:SetVertexColor(0.55, 0.62, 0.72, 0.20)
                else
                    f.dragGrip2:SetVertexColor(0.35, 0.95, 0.55, 0.55)
                end
            end
        end
        if f.btnLock and ns.Theme then
            local themeKey = (ns.Theme.GetThemeName and ns.Theme:GetThemeName()) or "blizzard"
            local lockSig = mode .. ":" .. themeKey
            if f.btnLock._scLockBtnSig ~= lockSig then
                f.btnLock._scLockBtnSig = lockSig
                local iconCol = QuickReply._LOCK_COL_UNLOCK
                if mode == "pos_locked" then
                    iconCol = QuickReply._LOCK_COL_POS
                elseif mode == "full_locked" then
                    iconCol = QuickReply._LOCK_COL_FULL
                end
                local opts = f.btnLock._scLockCfgOpts
                if not opts then
                    opts = { size = 17, toggle = true, keepColorWhenInactive = true, tooltipFn = f._lockTooltipFn }
                    f.btnLock._scLockCfgOpts = opts
                end
                opts.active = locked
                opts.activeColor = (mode == "pos_locked") and QuickReply._LOCK_ACT_POS or QuickReply._LOCK_ACT_FULL
                opts.color = iconCol
                ns.Theme:ConfigureIconButton(
                    f.btnLock, 20, 20,
                    locked and ICON_LOCK_CLOSED or ICON_LOCK_OPEN,
                    opts
                )
            end
        end
    end
    return locked
end

function QuickReply:ToggleLock()
    if ns.db and ns.db.settings then
        local cur = self:GetLockMode()
        local nxt = (cur == "unlocked" and "pos_locked")
            or (cur == "pos_locked" and "full_locked")
            or "unlocked"
        ns.db.settings.quickReplyLockMode = nxt
        ns.db.settings.quickReplyLocked = (nxt ~= "unlocked")
    end
    local locked = self:ApplyLockState()
    local mode = self:GetLockMode()
    if GameTooltip and self.frame then
        if self.frame.btnLock and GameTooltip:IsOwned(self.frame.btnLock) and self.frame._lockTooltipFn then
            local tTitle, tDesc = self.frame._lockTooltipFn()
            GameTooltip:SetOwner(self.frame.btnLock, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(tTitle or "", 1.0, 0.85, 0.25, true)
            if tDesc and tDesc ~= "" then
                GameTooltip:AddLine(tDesc, 0.88, 0.92, 0.96, true)
            end
            GameTooltip:Show()
        elseif self.frame.header and GameTooltip:IsOwned(self.frame.header) then
            GameTooltip:SetOwner(self.frame.header, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["Quick Reply"], 1.0, 0.85, 0.25, true)
            if mode == "pos_locked" then
                GameTooltip:AddLine(L["Position Locked (Resizable) — Drag edges up, down, or sideways to resize."], 0.45, 0.85, 1.0, true)
            elseif locked then
                GameTooltip:AddLine(L["Locked — Click the Padlock button to unlock movement"], 0.95, 0.78, 0.32, true)
            else
                GameTooltip:AddLine(L["Drag title bar or window anywhere to move"], 0.62, 0.70, 0.80, true)
            end
            GameTooltip:Show()
        end
    end
    if ns.Emit then
        ns:Emit("CHAT_UPDATED")
        ns:Emit("SETTINGS_UPDATED")
    end
    if ns.Settings and ns.Settings.Refresh then
        ns.Settings:Refresh()
    end
    return locked
end

function QuickReply:IsDockedOverChat()
    local s = ns.db and ns.db.settings
    local dockOn = (not s) or (s.quickReplyDockToChat ~= false)
    local hasSavedPos = (ns.Theme and ns.Theme.HasSavedWindowPosition and ns.Theme:HasSavedWindowPosition("quickReply")) == true
    return dockOn and not hasSavedPos
end

function QuickReply:UpdateDockButton()
    local f = self.frame
    if not (f and f.btnDock and ns.Theme) then
        return
    end
    local docked = self:IsDockedOverChat()
    local themeKey = (ns.Theme.GetThemeName and ns.Theme:GetThemeName()) or "blizzard"
    local dockSig = (docked and "1:" or "0:") .. themeKey
    if f.btnDock._scDockBtnSig == dockSig then
        return
    end
    f.btnDock._scDockBtnSig = dockSig
    ns.Theme:SetButtonActive(f.btnDock, docked, "default")
    local opts = f.btnDock._scDockCfgOpts
    if not opts then
        opts = { size = 16, tooltipFn = f._dockTooltipFn }
        f.btnDock._scDockCfgOpts = opts
    end
    opts.color = docked and QuickReply._DOCK_COL_ON or QuickReply._DOCK_COL_OFF
    ns.Theme:ConfigureIconButton(
        f.btnDock, 20, 20,
        "Interface\\Icons\\INV_Misc_Map_01",
        opts
    )
end

function QuickReply:SnapOverOfficialChat()
    if ns.db and ns.db.settings then
        ns.db.settings.quickReplyDockToChat = true
    end
    self._userDraggedThisOpen = false
    if ns.Theme and ns.Theme.ClearSavedWindowPosition then
        ns.Theme:ClearSavedWindowPosition("quickReply", true)
    end
    self:HideWhispersDropdown()
    self:SyncDockGeometry()
    self:UpdateWhispersButton()
    self:UpdateDockButton()
    if self.frame and self.frame:IsShown() then
        self:Refresh()
    end
    if ns.Emit then
        ns:Emit("CHAT_UPDATED")
        ns:Emit("SETTINGS_UPDATED")
    end
    if ns.Settings and ns.Settings.Refresh then
        ns.Settings:Refresh()
    end
end

function QuickReply:IsCombatLogPopupActive(wantKind)
    local pop = self._combatLogFrame
    if not (pop and pop:IsShown()) then
        return false
    end
    local isWorld = (pop._logTab == "world")
    if wantKind == "world" then
        return isWorld
    elseif wantKind == "combat" then
        return not isWorld
    end
    return true
end

function QuickReply:RefreshCombatLogFrame()
    local pop = self._combatLogFrame
    if not (pop and pop:IsShown() and pop.msgFrame) then
        return
    end
    local logTab = (pop._logTab == "world") and "world" or "combat"
    local isWorld = (logTab == "world")
    if pop.icon then
        pop.icon:SetTexture(isWorld and "Interface\\Icons\\INV_Misc_Note_01" or "Interface\\Icons\\Ability_DualWield")
        pop.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if pop.title then
        pop.title:SetText(isWorld and L["World Log"] or L["Combat Log"])
    end
    if pop._modeBtns and ns.Theme then
        for tk, tBtn in pairs(pop._modeBtns) do
            local isSel = (tk == logTab)
            ns.Theme:StyleButton(tBtn, isSel and "primary" or "default")
            ns.Theme:SetButtonActive(tBtn, isSel, isSel and "primary" or "default")
        end
    end
    local filterKind = isWorld and (pop._worldFilterKind or "all") or (pop._filterKind or "all")
    local filterSet = isWorld and pop._worldFilterBtns or pop._combatFilterBtns
    if pop._combatFilterHolder then pop._combatFilterHolder:SetShown(not isWorld) end
    if pop._worldFilterHolder then pop._worldFilterHolder:SetShown(isWorld) end
    if filterSet and ns.Theme then
        for fk, fBtn in pairs(filterSet) do
            ns.Theme:StyleButton(fBtn, (fk == filterKind) and "primary" or "default")
            ns.Theme:SetButtonActive(fBtn, fk == filterKind, (fk == filterKind) and "primary" or "default")
        end
    end
    local entries = {}
    if ns.Chat then
        if isWorld and ns.Chat.GetWorldLogEntries then
            entries = ns.Chat:GetWorldLogEntries(filterKind) or {}
        elseif (not isWorld) and ns.Chat.GetCombatLogEntries then
            entries = ns.Chat:GetCombatLogEntries(filterKind) or {}
        end
    end
    if pop.countText then
        pop.countText:SetText(string.format("(%d)", #entries))
    end
    local msgFrame = pop.msgFrame
    local wasAtBottom = (not msgFrame.AtBottom) or (msgFrame:AtBottom() ~= false)
    local prevScroll = ((not wasAtBottom) and msgFrame.GetScrollOffset) and (msgFrame:GetScrollOffset() or 0) or 0
    msgFrame:Clear()
    if #entries == 0 then
        if isWorld then
            msgFrame:AddMessage("|cff9da7b5" .. L["No world log events captured yet this session."] .. "|r")
            msgFrame:AddMessage("|cff7f8a9c" .. L["Loot, crafting, XP, achievements, and system notices appear here automatically (keeping General focused on conversations)."] .. "|r")
        else
            msgFrame:AddMessage("|cff9da7b5" .. L["No combat log events captured yet this session."] .. "|r")
            msgFrame:AddMessage("|cff7f8a9c" .. L["Damage, healing, and deaths appear here automatically as combat occurs (kept in this button instead of a chat tab)."] .. "|r")
        end
    else
        local startIdx = math.max(1, #entries - 149)
        for i = startIdx, #entries do
            local item = entries[i]
            if type(item) == "table" and item.text then
                local tsStr = item.ts and date("%H:%M:%S", item.ts) or ""
                local tsPart = (tsStr ~= "") and ("|cff6e7681[" .. tsStr .. "]|r ") or ""
                msgFrame:AddMessage(tsPart .. item.text, item.r or 0.92, item.g or 0.88, item.b or 0.78)
            end
        end
    end
    if (not wasAtBottom) and prevScroll > 0 and msgFrame.SetScrollOffset then
        msgFrame:SetScrollOffset(prevScroll)
    else
        msgFrame:ScrollToBottom()
    end
    if pop.btnScrollBottom then
        local atBotNow = (not msgFrame.AtBottom) or (msgFrame:AtBottom() ~= false)
        pop.btnScrollBottom:SetShown(not atBotNow)
    end
end

function QuickReply:EnsureCombatLogFrame()
    if self._combatLogFrame then
        return self._combatLogFrame
    end
    local Theme = ns.Theme
    local pop = CreateFrame("Frame", "SocialCentralCombatLogFrame", UIParent, "BackdropTemplate")
    pop:Hide()
    pop:SetSize(460, 310)
    pop:SetFrameStrata("DIALOG")
    pop:SetFrameLevel(330)
    pop:SetToplevel(true)
    pop:EnableMouse(true)
    pop:SetClampedToScreen(true)
    pop:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    table.insert(UISpecialFrames, "SocialCentralCombatLogFrame")

    local solidBg = pop:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetAllPoints()
    solidBg:SetTexture(MP_WHITE8X8)
    solidBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    pop._solidOpaqueBg = solidBg

    local hdr = CreateFrame("Frame", nil, pop, "BackdropTemplate")
    hdr:SetPoint("TOPLEFT", pop, "TOPLEFT", 6, -6)
    hdr:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -6, -6)
    hdr:SetHeight(30)
    hdr:EnableMouse(true)
    pop.header = hdr

    local icon = hdr:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", hdr, "LEFT", 8, 0)
    icon:SetTexture("Interface\\Icons\\Ability_DualWield")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pop.icon = icon

    local title = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetWordWrap(false)
    title:SetText(L["Combat Log"])
    pop.title = title

    local countText = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("LEFT", title, "RIGHT", 6, 0)
    countText:SetJustifyH("LEFT")
    countText:SetWordWrap(false)
    countText:SetText("(0)")
    pop.countText = countText

    local btnClose = Theme:CreateButton(hdr, 20, 20, "X", "default")
    btnClose:SetPoint("RIGHT", hdr, "RIGHT", -4, 0)
    btnClose:SetScript("OnClick", function()
        pop:Hide()
    end)
    pop.btnClose = btnClose

    local btnHelp = Theme:CreateHelpButton(
        hdr,
        L["Logs (Combat & World)"],
        L["What it does: Separates Combat Log activity and World Log activity (loot, crafting, XP, achievements, and system notices) into two clean tabs so General chat stays focused on conversations."],
        L["How to use it: Switch between Combat Log and World Log at the top, filter each log with the buttons below, click Clear to reset the open tab, or drag the title bar/corner."],
        18
    )
    btnHelp:SetPoint("RIGHT", btnClose, "LEFT", -3, 0)
    pop.btnHelp = btnHelp

    local btnClear = Theme:CreateButton(hdr, 54, 20, L["Clear"], "default")
    btnClear:SetPoint("RIGHT", btnHelp, "LEFT", -4, 0)
    Theme:AutoFitButton(btnClear, 48, 12, 86)
    countText:SetPoint("RIGHT", btnClear, "LEFT", -6, 0)
    btnClear:SetScript("OnClick", function()
        if ns.Chat then
            if pop._logTab == "world" and ns.Chat.ClearWorldLogEntries then
                ns.Chat:ClearWorldLogEntries()
            elseif ns.Chat.ClearCombatLogEntries then
                ns.Chat:ClearCombatLogEntries()
            end
        end
        QuickReply:RefreshCombatLogFrame()
    end)
    pop.btnClear = btnClear

    -- Mode Switcher Tabs: Combat Log | World Log
    local modeBar = CreateFrame("Frame", nil, pop)
    modeBar:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -4)
    modeBar:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", 0, -4)
    modeBar:SetHeight(22)
    pop.modeBar = modeBar
    pop._logTab = "combat"
    pop._modeBtns = {}

    local combatTabBtn = Theme:CreateButton(modeBar, 140, 21, L["Combat Log"], "primary")
    Theme:AutoFitButton(combatTabBtn, 112, 16, 200)
    combatTabBtn:SetPoint("LEFT", modeBar, "LEFT", 0, 0)
    combatTabBtn:SetScript("OnClick", function()
        pop._logTab = "combat"
        QuickReply:RefreshCombatLogFrame()
    end)
    pop._modeBtns.combat = combatTabBtn

    local worldTabBtn = Theme:CreateButton(modeBar, 140, 21, L["World Log"], "default")
    Theme:AutoFitButton(worldTabBtn, 112, 16, 200)
    worldTabBtn:SetPoint("LEFT", combatTabBtn, "RIGHT", 6, 0)
    worldTabBtn:SetScript("OnClick", function()
        pop._logTab = "world"
        QuickReply:RefreshCombatLogFrame()
    end)
    pop._modeBtns.world = worldTabBtn

    local filterBar = CreateFrame("Frame", nil, pop)
    filterBar:SetPoint("TOPLEFT", modeBar, "BOTTOMLEFT", 0, -4)
    filterBar:SetPoint("TOPRIGHT", modeBar, "BOTTOMRIGHT", 0, -4)
    filterBar:SetHeight(22)
    pop.filterBar = filterBar
    pop._filterKind = "all"
    pop._worldFilterKind = "all"
    pop._combatFilterBtns = {}
    pop._worldFilterBtns = {}

    local combatFilterHolder = CreateFrame("Frame", nil, filterBar)
    combatFilterHolder:SetAllPoints(filterBar)
    pop._combatFilterHolder = combatFilterHolder

    local combatFilterDefs = {
        { key = "all", label = L["All"] },
        { key = "damage", label = L["Damage"] },
        { key = "healing", label = L["Healing"] },
        { key = "kills", label = L["Kills & Misc"] },
    }
    local prevC = nil
    for _, fd in ipairs(combatFilterDefs) do
        local fb = Theme:CreateButton(combatFilterHolder, 70, 20, fd.label, "default")
        Theme:AutoFitButton(fb, 46, 14, 130)
        if not prevC then
            fb:SetPoint("LEFT", combatFilterHolder, "LEFT", 0, 0)
        else
            fb:SetPoint("LEFT", prevC, "RIGHT", 4, 0)
        end
        fb:SetScript("OnClick", function()
            pop._filterKind = fd.key
            QuickReply:RefreshCombatLogFrame()
        end)
        pop._combatFilterBtns[fd.key] = fb
        prevC = fb
    end

    local worldFilterHolder = CreateFrame("Frame", nil, filterBar)
    worldFilterHolder:SetAllPoints(filterBar)
    worldFilterHolder:Hide()
    pop._worldFilterHolder = worldFilterHolder

    local worldFilterDefs = {
        { key = "all", label = L["All"] },
        { key = "loot", label = L["Loot"] },
        { key = "craft", label = L["Crafting"] },
        { key = "progress", label = L["Progress"] },
        { key = "system", label = L["System"] },
    }
    local prevW = nil
    for _, fd in ipairs(worldFilterDefs) do
        local fb = Theme:CreateButton(worldFilterHolder, 70, 20, fd.label, "default")
        Theme:AutoFitButton(fb, 42, 10, 112)
        if not prevW then
            fb:SetPoint("LEFT", worldFilterHolder, "LEFT", 0, 0)
        else
            fb:SetPoint("LEFT", prevW, "RIGHT", 4, 0)
        end
        fb:SetScript("OnClick", function()
            pop._worldFilterKind = fd.key
            QuickReply:RefreshCombatLogFrame()
        end)
        pop._worldFilterBtns[fd.key] = fb
        prevW = fb
    end

    local msgBg = CreateFrame("Frame", nil, pop, "BackdropTemplate")
    msgBg:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -4)
    msgBg:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -6, 6)
    pop.msgBg = msgBg

    local msgFrame = CreateFrame("ScrollingMessageFrame", nil, msgBg)
    msgFrame:SetClipsChildren(true)
    msgFrame:SetPoint("TOPLEFT", msgBg, "TOPLEFT", 7, -6)
    msgFrame:SetPoint("BOTTOMRIGHT", msgBg, "BOTTOMRIGHT", -7, 6)
    msgFrame:SetFontObject(_G.ChatFontNormal or "GameFontHighlightSmall")
    msgFrame:SetJustifyH("LEFT")
    if msgFrame.SetSpacing then msgFrame:SetSpacing(2) end
    if msgFrame.SetIndentedWordWrap then msgFrame:SetIndentedWordWrap(true) end
    if msgFrame.SetInsertMode then msgFrame:SetInsertMode("BOTTOM") end
    msgFrame:SetFading(false)
    msgFrame:SetMaxLines(400)
    msgFrame:EnableMouse(true)
    if msgFrame.SetHyperlinksEnabled then msgFrame:SetHyperlinksEnabled(true) end
    msgFrame.EnableMouseWheel(msgFrame, true)
    pop.msgFrame = msgFrame
    QuickReply:AttachMsgFrameHandlers(pop, msgFrame, Theme)

    local btnScrollBottom = Theme:CreateButton(msgBg, 22, 20, "", "default")
    Theme:ConfigureIconButton(btnScrollBottom, 22, 20, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", {
        size = 16,
        color = { 0.95, 0.88, 0.72 },
        title = L["Jump to latest messages"],
    })
    btnScrollBottom:SetPoint("BOTTOMRIGHT", msgFrame, "BOTTOMRIGHT", -2, 2)
    btnScrollBottom:SetFrameLevel((msgFrame:GetFrameLevel() or 2) + 5)
    btnScrollBottom:Hide()
    btnScrollBottom:SetScript("OnClick", function()
        msgFrame:ScrollToBottom()
        btnScrollBottom:Hide()
    end)
    pop.btnScrollBottom = btnScrollBottom

    msgFrame:SetScript("OnMouseWheel", function(selfMsg, delta)
        if delta > 0 then
            selfMsg:ScrollUp()
        else
            selfMsg:ScrollDown()
        end
        local atBot = selfMsg.AtBottom and selfMsg:AtBottom()
        btnScrollBottom:SetShown(atBot == false)
    end)

    if pop.SetResizable then pop:SetResizable(true) end
    if pop.SetResizeBounds then
        pop:SetResizeBounds(396, 200, 760, 620)
    elseif pop.SetMinResize then
        pop:SetMinResize(396, 200)
        if pop.SetMaxResize then pop:SetMaxResize(760, 620) end
    end
    local clResizeGrip = CreateFrame("Button", nil, pop)
    clResizeGrip:SetSize(16, 16)
    clResizeGrip:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -3, 3)
    clResizeGrip:SetFrameLevel((msgBg:GetFrameLevel() or 3) + 12)
    clResizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    clResizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    clResizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    clResizeGrip:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" and pop.StartSizing and not pop._scDragging then
            pop:SetResizable(true)
            if pop.SetResizeBounds then
                pop:SetResizeBounds(396, 200, 760, 620)
            elseif pop.SetMinResize then
                pop:SetMinResize(396, 200)
                if pop.SetMaxResize then pop:SetMaxResize(760, 620) end
            end
            local left, top = pop:GetLeft(), pop:GetTop()
            if left and top then
                pop:ClearAllPoints()
                pop:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
            pop._clSizing = true
            pop:StartSizing("BOTTOMRIGHT")
        end
    end)
    clResizeGrip:SetScript("OnMouseUp", function()
        if pop._clSizing and pop.StopMovingOrSizing then
            pop._clSizing = false
            pop:StopMovingOrSizing()
            local uw = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1280
            local uh = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 720
            local maxW = math.min(760, math.max(396, math.floor(uw - 16)))
            local maxH = math.min(620, math.max(200, math.floor(uh - 16)))
            local curW = math.floor((pop:GetWidth() or 460) + 0.5)
            local curH = math.floor((pop:GetHeight() or 310) + 0.5)
            local clampedW = math.max(396, math.min(maxW, curW))
            local clampedH = math.max(200, math.min(maxH, curH))
            if clampedW ~= curW or clampedH ~= curH then
                pop:SetSize(clampedW, clampedH)
            end
            if ns.Theme and ns.Theme.SaveWindowSize then
                ns.Theme:SaveWindowSize("quickReplyCombatLog", clampedW, clampedH)
            end
            if pop._scSavePosition then
                pop._scSavePosition()
            end
            if ns.Theme and ns.Theme.RestoreWindowPosition then
                ns.Theme:RestoreWindowPosition(pop, "quickReplyCombatLog", false, { allowLockedRestore = true })
            end
        end
    end)

    if Theme and Theme.MakeMovable then
        Theme:MakeMovable(pop, {
            key = "quickReplyCombatLog",
            skipAutoRestore = true,
            handles = { hdr, modeBar, filterBar, msgBg, msgFrame },
        })
    end

    pop:HookScript("OnShow", function()
        if ns.Theme and ns.Theme.GetSavedWindowSize then
            local sw, sh = ns.Theme:GetSavedWindowSize("quickReplyCombatLog")
            if sw and sh then
                pop:SetSize(math.max(396, math.min(760, sw)), math.max(200, math.min(620, sh)))
            end
        end
        QuickReply:RefreshCombatLogFrame()
        if QuickReply.frame and QuickReply.frame.btnCombatLog and ns.Theme then
            ns.Theme:SetButtonActive(QuickReply.frame.btnCombatLog, true, "default")
        end
    end)
    pop:HookScript("OnHide", function()
        if QuickReply.frame and QuickReply.frame.btnCombatLog and ns.Theme then
            ns.Theme:SetButtonActive(QuickReply.frame.btnCombatLog, false, "default")
        end
        if ns.Chat and ns.Chat.ClearCombatLogBufferSilent then
            ns.Chat:ClearCombatLogBufferSilent()
        end
    end)

    self._combatLogFrame = pop
    self:ApplyCombatLogTheme()
    return pop
end

function QuickReply:ApplyCombatLogTheme()
    local pop = self._combatLogFrame
    if not (pop and ns.Theme) then
        return
    end
    local p = ns.Theme:GetPalette()
    if pop._solidOpaqueBg then
        local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
        pop._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
    end
    ns.Theme:ApplyBackdrop(pop, "window", p)
    ns.Theme:ApplyBackdrop(pop.header, "surface", p)
    ns.Theme:ApplyBackdrop(pop.msgBg, "inset", p)
    ns.Theme:StyleButton(pop.btnClose, "default")
    ns.Theme:StyleButton(pop.btnClear, "default")
    if pop.btnHelp and pop.btnHelp.RefreshTheme then
        pop.btnHelp:RefreshTheme()
    end
    if pop.title and p then
        local gc = p.textGold or p.accent or { 1.0, 0.85, 0.30 }
        pop.title:SetTextColor(gc[1], gc[2], gc[3])
    end
    if pop.countText and p and p.textMuted then
        pop.countText:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
    end
    if pop.btnScrollBottom then
        ns.Theme:StyleButton(pop.btnScrollBottom, "default")
    end
    if pop._modeBtns then
        local curTab = (pop._logTab == "world") and "world" or "combat"
        for k, tb in pairs(pop._modeBtns) do
            ns.Theme:StyleButton(tb, (k == curTab) and "primary" or "default")
        end
    end
    if pop._combatFilterBtns then
        local activeKind = pop._filterKind or "all"
        for k, fb in pairs(pop._combatFilterBtns) do
            ns.Theme:StyleButton(fb, (k == activeKind) and "primary" or "default")
        end
    end
    if pop._worldFilterBtns then
        local activeWorld = pop._worldFilterKind or "all"
        for k, fb in pairs(pop._worldFilterBtns) do
            ns.Theme:StyleButton(fb, (k == activeWorld) and "primary" or "default")
        end
    end
end

function QuickReply:ToggleCombatLogFrame()
    if Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode() then
        return false
    end
    local pop = self:EnsureCombatLogFrame()
    if pop:IsShown() then
        pop:Hide()
        return false
    end
    local restored = ns.Theme and ns.Theme.RestoreWindowPosition and ns.Theme:RestoreWindowPosition(pop, "quickReplyCombatLog", false, { allowLockedRestore = true })
    if not restored and self.frame and self.frame:IsShown() then
        local qrW = self.frame:GetWidth() or 440
        pop:SetWidth(math.max(360, math.min(520, qrW)))
        pop:ClearAllPoints()
        local topY = self.frame:GetTop() or 300
        local uh = (_G.UIParent and _G.UIParent:GetHeight()) or 720
        if (topY + 300) <= (uh - 16) then
            pop:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", 0, 8)
        else
            pop:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMRIGHT", 8, 0)
        end
    elseif not restored then
        pop:ClearAllPoints()
        pop:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 80)
    end
    pop:Show()
    pop:Raise()
    self:RefreshCombatLogFrame()
    if ns.Theme and ns.Theme.PromptWindowTutorial then
        ns.Theme:PromptWindowTutorial({
            tutorialKey = "winPrompt_combatLog",
            title = L["Logs (Combat & World)"],
            guideSpec = {
                key = "combat_log_win",
                title = L["Logs (Combat & World)"],
                defaultTarget = pop,
                isAnchorVisible = function() return pop:IsShown() end,
                steps = {
                    {
                        title = L["Logs (Combat & World)"],
                        text = L["What it does: Separates Combat Log activity and World Log activity (loot, crafting, XP, achievements, and system notices) into two clean tabs so General chat stays focused on conversations."],
                        target = pop.modeBar or pop,
                    },
                    {
                        title = L["Logs (Combat & World)"],
                        text = L["How to use it: Switch between Combat Log and World Log at the top, filter each log with the buttons below, click Clear to reset the open tab, or drag the title bar/corner."],
                        target = pop.filterBar or pop,
                    },
                },
            },
            isWindowVisible = function() return pop:IsShown() end,
        })
    end
    return true
end

function QuickReply:UpdateAutoCloseButton()
    local f = self.frame
    if not (f and f.btnAutoClose and ns.Theme) then
        return
    end
    local enabled, delay = self:GetAutoCloseSettings()
    local fadeEnabled, fadeDelay = self:GetFadeDelaySettings()
    local persistOpen = self:IsPersistentOpenMode()
    local w = f:GetWidth() or 444
    local ultraCompact = (w < 365)
    local compactHdr = (w < 540)
    local themeKey = (ns.Theme.GetThemeName and ns.Theme:GetThemeName()) or "blizzard"
    local acSig = (enabled and "1" or "0") .. ":" .. tostring(delay) .. ":" .. (fadeEnabled and "1" or "0") .. ":" .. tostring(fadeDelay) .. ":" .. (persistOpen and "1" or "0") .. ":" .. (ultraCompact and "U" or (compactHdr and "C" or "F")) .. ":" .. themeKey
    if f.btnAutoClose._scAcSig == acSig then
        return
    end
    f.btnAutoClose._scAcSig = acSig
    local label
    if not enabled then
        if fadeEnabled then
            label = ultraCompact and (tostring(fadeDelay) .. "s") or (compactHdr and L["Fade: %ds"]:format(fadeDelay) or L["Transparent: %ds"]:format(fadeDelay))
        else
            label = ultraCompact and "100%" or (compactHdr and L["Opaque"] or L["Always Open (Opaque)"])
        end
    elseif persistOpen then
        label = ultraCompact and "DG" or (compactHdr and L["Raid/DG"] or L["Dungeon: Stay Open"])
    else
        label = ultraCompact and (tostring(delay) .. "s") or (compactHdr and L["Auto: %ds"]:format(delay) or L["Auto-close: %d seconds"]:format(delay))
    end
    ns.Theme:SetButtonText(f.btnAutoClose, label)
    local minW = ultraCompact and 34 or (compactHdr and 56 or 96)
    local maxW = ultraCompact and 54 or (compactHdr and 108 or 192)
    ns.Theme:AutoFitButton(f.btnAutoClose, minW, ultraCompact and 12 or 16, maxW)
end

function QuickReply:SyncDockGeometry()
    local f = self.frame
    if not f then
        return
    end
    if self._userDraggedThisOpen or f._scDragging or f._scSizing then
        return
    end
    local s = ns.db and ns.db.settings
    local dockOn = (not s) or (s.quickReplyDockToChat ~= false)
    local hasSavedPos = (ns.Theme and ns.Theme.HasSavedWindowPosition and ns.Theme:HasSavedWindowPosition("quickReply")) == true
    local savedW, savedH
    if ns.Theme and ns.Theme.GetSavedWindowSize then
        savedW, savedH = ns.Theme:GetSavedWindowSize("quickReply")
    end
    local uw = (_G.UIParent and _G.UIParent.GetWidth and _G.UIParent:GetWidth()) or 1280
    local uh = (_G.UIParent and _G.UIParent.GetHeight and _G.UIParent:GetHeight()) or 720
    local refW, refH, refX, refY = nil, nil, nil, nil
    if dockOn then
        local bgRef = _G.ChatFrame1Background
        local cfRef = _G.ChatFrame1
        local ref = (bgRef and bgRef.IsShown and bgRef:IsShown() and (bgRef:GetWidth() or 0) > 100 and (bgRef:GetHeight() or 0) > 50 and bgRef)
            or (cfRef and cfRef.IsShown and cfRef:IsShown() and (cfRef:GetWidth() or 0) > 100 and (cfRef:GetHeight() or 0) > 50 and cfRef)
            or cfRef
        if ref and ref.GetLeft and ref.GetBottom and ref.GetWidth and ref.GetHeight then
            local cfLeft = ref:GetLeft()
            local cfBottom = ref:GetBottom()
            local cfW = ref:GetWidth()
            local cfH = ref:GetHeight()
            if cfLeft and cfBottom and cfW and cfH and cfW > 50 and cfH > 50 then
                local scale = (ref.GetEffectiveScale and _G.UIParent and _G.UIParent.GetEffectiveScale)
                    and ((ref:GetEffectiveScale() or 1) / (_G.UIParent:GetEffectiveScale() or 1))
                    or 1
                if not scale or scale <= 0 then scale = 1 end
                refW = math.max(360, math.floor(cfW * scale + 0.5))
                local tallerDefault = math.min(math.max(268, math.floor(cfH * scale + 64 + 0.5)), math.max(268, math.floor(uh - (cfBottom * scale) - 18)))
                refH = tallerDefault
                refX = math.floor(cfLeft * scale + 0.5)
                refY = math.floor(cfBottom * scale + 0.5)
            end
        end
    end

    local useW = (savedW and savedW >= 350) and math.min(savedW, uw - 16) or nil
    local useH = (savedH and savedH >= 210) and math.min(savedH, uh - 16) or nil

    if dockOn and refW and refH and not hasSavedPos then
        local finalW = useW or refW
        local finalH = useH or refH
        local changed = (f._scDockMode ~= "dock")
            or (f._scDockW ~= finalW) or (f._scDockH ~= finalH)
            or (f._scDockX ~= refX) or (f._scDockY ~= refY)
        if changed then
            f._scDockMode = "dock"
            f._scDockW, f._scDockH, f._scDockX, f._scDockY = finalW, finalH, refX, refY
            f:SetSize(finalW, finalH)
            f:ClearAllPoints()
            f:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", refX, refY)
            if f.header then
                f.header:SetHeight(finalH < 250 and 23 or 25)
            end
            if f.infoBar then
                f.infoBar:SetHeight(finalH < 250 and 29 or 32)
            end
            if f.chipsBar then
                f.chipsBar:SetHeight(finalH < 250 and 19 or 21)
            end
        end
        self:UpdateDockButton()
        self:ApplyLockState()
        return
    end

    local defW = useW or (dockOn and refW) or math.min(444, math.max(350, math.floor(uw - 32)))
    local defH = useH or (dockOn and refH) or math.min(380, math.max(268, math.floor(uh - 32)))
    local freeChanged = (f._scDockMode ~= "free") or (f._scDockW ~= defW) or (f._scDockH ~= defH) or (f._scDockHasSaved ~= hasSavedPos)
    if freeChanged then
        f._scDockMode = "free"
        f._scDockW, f._scDockH, f._scDockHasSaved = defW, defH, hasSavedPos
        f:SetSize(defW, defH)
        if f.header then
            f.header:SetHeight(defH < 250 and 23 or 25)
        end
        if f.infoBar then
            f.infoBar:SetHeight(defH < 250 and 29 or 32)
        end
        if f.chipsBar then
            f.chipsBar:SetHeight(defH < 250 and 19 or 21)
        end
        local restored = ns.Theme and ns.Theme.RestoreWindowPosition and ns.Theme:RestoreWindowPosition(f, "quickReply", false, { allowLockedRestore = true })
        if not restored then
            f:ClearAllPoints()
            f:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
        end
    end
    self:UpdateDockButton()
    self:ApplyLockState()
end

function QuickReply:EnsureEnterTriggerButton()
    if self._enterBtn then
        return self._enterBtn
    end
    local btn = CreateFrame("Button", "SocialCentralQuickReplyEnterBtn", UIParent)
    btn:SetSize(1, 1)
    btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
    btn:RegisterForClicks("AnyDown")
    btn:SetScript("OnClick", function()
        local nowMono = (GetTime and GetTime()) or 0
        local kbFocus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() or nil
        if kbFocus then
            if QuickReply.frame and QuickReply.frame.inputBox and kbFocus == QuickReply.frame.inputBox then
                if QuickReply._submitQuickReplyFn then
                    QuickReply._submitQuickReplyFn()
                end
                return
            end
            if (not kbFocus.IsVisible) or kbFocus:IsVisible() then
                return
            end
        end
        local s = ns.db and ns.db.settings
        if s and (s.quickReplyEnabled == false or s.quickReplyEnterOpen == false) then
            return
        end
        if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("chat") then
            return
        end
        if ns.Compat and ns.Compat.IsOfficialChatMode and ns.Compat.IsOfficialChatMode() then
            return
        end
        QuickReply._lastEnterFocusAt = nowMono
        if QuickReply.frame and QuickReply.frame:IsShown() then
            local targetKey = QuickReply:IsWritableThreadKey(QuickReply.activeKey) and QuickReply.activeKey
                or QuickReply:GetEnterTargetThreadKey()
            if targetKey and targetKey ~= QuickReply.activeKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[targetKey] then
                QuickReply:SelectThread(targetKey, true)
            else
                QuickReply:FocusInputBox()
            end
            return
        end
        local enterKey = QuickReply:GetEnterTargetThreadKey()
        if enterKey and QuickReply.OpenThread and QuickReply:OpenThread(enterKey, true) then
            return
        end
        if not QuickReply:OpenLatest(false, true, true) and QuickReply.OpenThread then
            QuickReply:OpenThread("ch:general", true)
        end
    end)
    self._enterBtn = btn
    return btn
end

function QuickReply:EnsureSlashTriggerButton()
    if self._slashBtn then
        return self._slashBtn
    end
    local btn = CreateFrame("Button", "SocialCentralQuickReplySlashBtn", UIParent)
    btn:SetSize(1, 1)
    btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
    btn:RegisterForClicks("AnyDown")
    btn:SetScript("OnClick", function()
        if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() ~= nil then
            return
        end
        if ns.Compat and ns.Compat.IsOfficialChatMode and ns.Compat.IsOfficialChatMode() then
            return
        end
        local chatModOn = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("chat")
        if not chatModOn then
            return
        end
        local targetKey = QuickReply.activeKey
        if not (QuickReply.frame and QuickReply.frame:IsShown() and targetKey) then
            targetKey = QuickReply:GetEnterTargetThreadKey()
                or QuickReply:GetPreservedThreadKey()
                or QuickReply:GetFirstPendingActionKey()
                or "ch:general"
        end
        if not targetKey or targetKey == "mentions:radar" or not (ns.Chat and ns.Chat.threads and ns.Chat.threads[targetKey]) then
            targetKey = "ch:general"
        end
        local targetT = ns.Chat and ns.Chat.threads and ns.Chat.threads[targetKey]
        if QuickReply:ShouldUseDockedOfficialInput(targetT) then
            local opened = false
            if QuickReply.frame and QuickReply.frame:IsShown() then
                opened = true
            elseif QuickReply.OpenThread then
                opened = QuickReply:OpenThread(targetKey, false)
            end
            if opened then
                QuickReply:ActivateDockedOfficialInput(nil, "/")
            end
            return
        end
        local opened = false
        if QuickReply.frame and QuickReply.frame:IsShown() then
            opened = QuickReply:SelectThread(targetKey, true)
        elseif QuickReply.OpenThread then
            opened = QuickReply:OpenThread(targetKey, true)
        end
        if opened and QuickReply.frame and QuickReply.frame.inputBox then
            local ib = QuickReply.frame.inputBox
            QuickReply.suppressDraftSave = true
            ib:SetText("/")
            if ib.UpdatePlaceholder then ib:UpdatePlaceholder() end
            if ib.SetCursorPosition then ib:SetCursorPosition(1) end
            QuickReply.suppressDraftSave = false
            QuickReply:FocusInputBox()
            if ib.SetCursorPosition then ib:SetCursorPosition(1) end
        end
    end)
    self._slashBtn = btn
    return btn
end

function QuickReply:EnsureEnterStateDriver()
    if self._enterStateDriver then
        return self._enterStateDriver
    end
    if _G.RegisterStateDriver then
        local okDrv, drv = pcall(CreateFrame, "Frame", nil, UIParent, "SecureHandlerStateTemplate")
        if okDrv and drv and drv.SetAttribute then
            drv:Hide()
            pcall(drv.SetAttribute, drv, "_onstate-combat", [[
                if newstate == 1 then
                    self:ClearBindings()
                end
            ]])
            pcall(_G.RegisterStateDriver, drv, "combat", "[combat] 1; 0")
            self._enterStateDriver = drv
            return drv
        end
    end
    return nil
end

function QuickReply:_BeginOwnBindingMutation()
    self._syncingBindingsDepth = (self._syncingBindingsDepth or 0) + 1
    self._syncingBindings = true
    self._suppressOwnUpdateBindings = true
    self._lastOwnBindingMutationAt = (GetTime and GetTime()) or 0
end

function QuickReply:_EndOwnBindingMutation()
    local d = (self._syncingBindingsDepth or 1) - 1
    if d <= 0 then
        self._syncingBindingsDepth = 0
        self._syncingBindings = false
        self._lastOwnBindingMutationAt = (GetTime and GetTime()) or 0
        if not self._clearBindingSuppressFn then
            self._clearBindingSuppressFn = function()
                QuickReply._clearBindingSuppressQueued = false
                if (QuickReply._syncingBindingsDepth or 0) <= 0 then
                    QuickReply._suppressOwnUpdateBindings = false
                end
            end
        end
        if _G.C_Timer and _G.C_Timer.After then
            if not self._clearBindingSuppressQueued then
                self._clearBindingSuppressQueued = true
                _G.C_Timer.After(0, self._clearBindingSuppressFn)
            end
        else
            self._suppressOwnUpdateBindings = false
        end
    else
        self._syncingBindingsDepth = d
    end
end

function QuickReply:InvalidateBindingCaches()
    self._appliedEnterBindSig = nil
    self._appliedCtrlWBindSig = nil
    self._appliedHotkeyBindSig = nil
end

function QuickReply:SyncEnterBinding()
    if InCombatLockdown and InCombatLockdown() then
        self._enterBindPending = true
        return
    end
    self._enterBindPending = false
    local btn = self:EnsureEnterTriggerButton()
    local slashBtn = self:EnsureSlashTriggerButton()
    if not btn then
        return
    end
    local bindOwner = self:EnsureEnterStateDriver() or btn

    local wantNone = false
    if ns.Compat and ns.Compat.IsOfficialChatMode and ns.Compat.IsOfficialChatMode() then
        wantNone = true
    elseif ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("chat") then
        wantNone = true
    end
    local s = ns.db and ns.db.settings
    if s and s.quickReplyEnabled == false then
        wantNone = true
    end

    local ownInput = self.frame and self.frame.inputBox or nil
    local kbFocus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() or nil
    local needFocusRetry = false
    if not wantNone then
        if kbFocus and kbFocus ~= ownInput and ((not kbFocus.IsVisible) or kbFocus:IsVisible()) then
            wantNone = true
            needFocusRetry = true
        else
            local blizzWin = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
                or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
                or nil
            if blizzWin and blizzWin.HasFocus and blizzWin:HasFocus() then
                wantNone = true
                needFocusRetry = true
            end
        end
    end

    if needFocusRetry then
        if not self._retryEnterBindFn then
            self._retryEnterBindFn = function()
                QuickReply._enterRetryQueued = false
                if QuickReply.SyncEnterBinding then
                    QuickReply:SyncEnterBinding()
                end
            end
        end
        if not self._enterRetryQueued and _G.C_Timer and _G.C_Timer.After then
            self._enterRetryQueued = true
            _G.C_Timer.After(0.20, self._retryEnterBindFn)
        end
    end

    local enterAllowed = (not wantNone) and ((not s) or (s.quickReplyEnterOpen ~= false))
    local slashAllowed = (not wantNone) and ((not s) or (s.quickReplySlashOpen ~= false))
    local addonOnlyMode = (not wantNone) and ((ns.Compat and ns.Compat.HasChosenChatUiMode and ns.Compat.HasChosenChatUiMode() and ns.Compat.IsAddonChatMode and ns.Compat.IsAddonChatMode()) == true)
    local wantSlash = addonOnlyMode and (slashBtn ~= nil) and slashAllowed and (not kbFocus)

    local k1, k2 = "", ""
    local s1, s2 = "", ""
    local desiredSig
    if (not enterAllowed and not wantSlash) or (not SetOverrideBindingClick) then
        desiredSig = "NONE"
    else
        if enterAllowed and GetBindingKey then
            local rk1, rk2 = GetBindingKey("OPENCHAT")
            if type(rk1) == "string" then k1 = rk1 end
            if type(rk2) == "string" then k2 = rk2 end
        end
        if wantSlash and GetBindingKey then
            local rs1, rs2 = GetBindingKey("OPENCHATSLASH")
            if type(rs1) == "string" then s1 = rs1 end
            if type(rs2) == "string" then s2 = rs2 end
        end
        desiredSig = (enterAllowed and "E:" or "_:") .. k1 .. "," .. k2 .. "|" .. (wantSlash and "S:" or "_:") .. s1 .. "," .. s2
    end

    if self._appliedEnterBindSig == desiredSig then
        return
    end
    self._appliedEnterBindSig = desiredSig

    self:_BeginOwnBindingMutation()
    if ClearOverrideBindings then
        pcall(ClearOverrideBindings, bindOwner)
        pcall(ClearOverrideBindings, btn)
        if slashBtn then
            pcall(ClearOverrideBindings, slashBtn)
        end
    end
    if desiredSig ~= "NONE" and SetOverrideBindingClick then
        if enterAllowed then
            local boundEnter = false
            if k1 ~= "" then
                pcall(SetOverrideBindingClick, bindOwner, false, k1, "SocialCentralQuickReplyEnterBtn", "LeftButton")
                if k1 == "ENTER" then boundEnter = true end
            end
            if k2 ~= "" then
                pcall(SetOverrideBindingClick, bindOwner, false, k2, "SocialCentralQuickReplyEnterBtn", "LeftButton")
                if k2 == "ENTER" then boundEnter = true end
            end
            if not boundEnter then
                pcall(SetOverrideBindingClick, bindOwner, false, "ENTER", "SocialCentralQuickReplyEnterBtn", "LeftButton")
            end
        end
        -- Only intercept slash globally when no input box already holds keyboard focus so typing '/' inside Grupo/Guilda/Whisper never drops.
        if wantSlash then
            if s1 ~= "" then
                pcall(SetOverrideBindingClick, bindOwner, false, s1, "SocialCentralQuickReplySlashBtn", "LeftButton")
            end
            if s2 ~= "" then
                pcall(SetOverrideBindingClick, bindOwner, false, s2, "SocialCentralQuickReplySlashBtn", "LeftButton")
            end
            pcall(SetOverrideBindingClick, bindOwner, false, "/", "SocialCentralQuickReplySlashBtn", "LeftButton")
            pcall(SetOverrideBindingClick, bindOwner, false, "NUMPADDIVIDE", "SocialCentralQuickReplySlashBtn", "LeftButton")
        end
    end
    self:_EndOwnBindingMutation()
end

function QuickReply:CanInviteThread(thread)
    if not thread or not ns.Compat then
        return false, nil
    end
    if thread.kind ~= "WHISPER" and thread.kind ~= "BN_WHISPER" then
        return false, nil
    end
    local target = thread.targetName or thread.title
    if not target or target == "" then
        return false, nil
    end
    if ns.Compat.IsMe and ns.Compat.IsMe(target, thread.guid) then
        return false, nil
    end
    if ns.Compat.IsInMyGroup and ns.Compat.IsInMyGroup(target, thread.guid) then
        return false, nil
    end
    local lookup = thread.lookupKey or target
    local dirRow = (lookup and ns.Store and ns.Store.socialDirectoryByLookup) and ns.Store.socialDirectoryByLookup[lookup] or nil
    local bInfo = (lookup and ns.Social and ns.Social.GetBNetLinkInfo) and ns.Social:GetBNetLinkInfo(lookup) or nil
    if (dirRow and dirRow.sameFaction == false) or (bInfo and bInfo.sameFaction == false) then
        return false, nil
    end
    if (dirRow and dirRow.samePool == false) or (bInfo and bInfo.samePool == false) then
        return false, nil
    end
    return true, target, thread.bnetAccountID or (bInfo and bInfo.bnetAccountID)
end

local function OpenQuickReplyMuteMenu(anchorBtn, threadKey, threadTitle)
    if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Chat and ns.Chat.PopulateThreadMuteMenu and threadKey) then
        return
    end
    local tObj = ns.Chat.threads and ns.Chat.threads[threadKey]
    local titleStr = threadTitle or (tObj and (tObj.title or tObj.targetName)) or threadKey
    if ns.Compat and ns.Compat.IsStreamerMode and ns.Compat.IsStreamerMode()
        and ((tObj and tObj.kind == "BN_WHISPER") or tostring(titleStr):find("#", 1, true))
        and ns.Compat.MaskStreamerBNetName
    then
        titleStr = ns.Compat.MaskStreamerBNetName(titleStr)
    end
    QuickReply._ownMenuOpen = true
    QuickReply._menuActionPicked = false
    MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        root:CreateTitle(L["Silence Notifications"] .. ": " .. titleStr)
        ns.Chat:PopulateThreadMuteMenu(root, threadKey, titleStr, function()
            QuickReply._menuActionPicked = true
            UpdateBadge(false)
            if QuickReply.frame and QuickReply.frame:IsShown() then
                QuickReply:Refresh()
            end
        end)
    end)
end

function QuickReply:CloseTabNow(threadKey)
    if not (threadKey and ns.Chat and ns.Chat.CloseQuickReplyTab) then
        return false
    end
    if threadKey == "ch:general" or threadKey == "notes:self" or threadKey == "mentions:radar" then
        return false
    end
    local wasActive = (self.activeKey == threadKey)
    local ok = ns.Chat:CloseQuickReplyTab(threadKey)
    if not ok then
        return false
    end
    if wasActive then
        local fallbackKey = "ch:general"
        local remaining = ns.Chat.GetQuickReplyThreads and ns.Chat:GetQuickReplyThreads() or {}
        if remaining[1] and remaining[1].key then
            fallbackKey = remaining[1].key
        end
        if ns.Chat.threads and not ns.Chat.threads[fallbackKey] and next(ns.Chat.threads) then
            for _, it in ipairs(remaining) do
                if it.key and ns.Chat.threads[it.key] then
                    fallbackKey = it.key
                    break
                end
            end
        end
        if ns.Chat.threads and ns.Chat.threads[fallbackKey] then
            self:SelectThread(fallbackKey, false)
        else
            self.activeKey = nil
            if self.frame and self.frame.inputBox then
                self.suppressDraftSave = true
                self.frame.inputBox:SetText("")
                self.suppressDraftSave = false
            end
            self:Refresh()
        end
    else
        if self.frame and self.frame:IsShown() then
            self:Refresh()
        end
    end
    self.interactedOutside = false
    self.lastInputAt = GetTime()
    self.idleCountdown = nil
    UpdateBadge(false)
    return true
end

function QuickReply:OpenClosePinnedTabConfirm(threadKey, threadTitle)
    local f = self.frame
    local Theme = ns.Theme
    if not (f and f:IsShown() and Theme and threadKey) then
        return
    end
    if not self._closeConfirmModal then
        local m = CreateFrame("Frame", "SocialCentralQuickReplyCloseConfirm", UIParent, "BackdropTemplate")
        m:Hide()
        m:SetSize(296, 136)
        m:SetClampedToScreen(true)
        table.insert(UISpecialFrames, "SocialCentralQuickReplyCloseConfirm")
        Theme:PrepareTopOverlayModal(m, 865)

        local hdr = CreateFrame("Frame", nil, m)
        hdr:SetPoint("TOPLEFT", 10, -8)
        hdr:SetPoint("TOPRIGHT", -10, -8)
        hdr:SetHeight(22)

        local closeBtn = Theme:CreateButton(hdr, 20, 18, "X", "default")
        closeBtn:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
        closeBtn:SetScript("OnClick", function() m:Hide() end)
        m.closeBtn = closeBtn

        local helpBtn = Theme:CreateHelpButton(
            hdr,
            L["Help: Close Pinned Tab"],
            L["Confirming closes this pinned tab from the Quick Reply bar and removes its pin, while keeping your saved conversation history intact."],
            L["Click Confirm to unpin and close the tab, or Cancel to keep it pinned in Quick Reply."],
            16
        )
        helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
        m.helpBtn = helpBtn

        local titleFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleFs:SetPoint("LEFT", hdr, "LEFT", 2, 0)
        titleFs:SetPoint("RIGHT", helpBtn, "LEFT", -6, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        titleFs:SetText(L["Close Pinned Tab?"])
        m.titleFs = titleFs

        local bodyFs = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bodyFs:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 4, -8)
        bodyFs:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", -4, -8)
        bodyFs:SetJustifyH("CENTER")
        bodyFs:SetWordWrap(true)
        m.bodyFs = bodyFs

        local confirmBtn = Theme:CreateButton(m, 114, 24, L["Confirm"], "primary")
        local cW = Theme:AutoFitButton(confirmBtn, 100, 18, 154)
        confirmBtn:SetScript("OnClick", function()
            local targetKey = m._targetKey
            m:Hide()
            if targetKey then
                QuickReply:CloseTabNow(targetKey)
            end
        end)
        local cancelBtn = Theme:CreateButton(m, 114, 24, L["Cancel"], "default")
        local kW = Theme:AutoFitButton(cancelBtn, 100, 18, 154)
        cancelBtn:SetScript("OnClick", function()
            m:Hide()
            QuickReply.interactedOutside = false
            QuickReply.lastInputAt = GetTime()
            QuickReply.idleCountdown = nil
        end)
        local pairGap = 10
        local needW = math.max(304, cW + kW + pairGap + 40)
        m:SetWidth(needW)
        confirmBtn:SetPoint("BOTTOMRIGHT", m, "BOTTOM", -5, 12)
        m.confirmBtn = confirmBtn
        cancelBtn:SetPoint("BOTTOMLEFT", m, "BOTTOM", 5, 12)
        m.cancelBtn = cancelBtn

        m:HookScript("OnShow", function()
            QuickReply.interactedOutside = false
            QuickReply.lastInputAt = GetTime()
            QuickReply.idleCountdown = nil
        end)
        self._closeConfirmModal = m
    end

    local mod = self._closeConfirmModal
    mod._targetKey = threadKey
    local tObj = ns.Chat and ns.Chat.threads and ns.Chat.threads[threadKey]
    local dispTitle = threadTitle or (tObj and (tObj.title or tObj.targetName)) or threadKey
    if ns.Compat and ns.Compat.IsStreamerMode and ns.Compat.IsStreamerMode()
        and ((tObj and tObj.kind == "BN_WHISPER") or tostring(dispTitle):find("#", 1, true))
        and ns.Compat.MaskStreamerBNetName
    then
        dispTitle = ns.Compat.MaskStreamerBNetName(dispTitle)
    end
    mod.bodyFs:SetText(string.format(L["%s is pinned in Quick Reply. Closing this tab will also unpin it. Close anyway?"], "|cffffd24d" .. tostring(dispTitle) .. "|r"))
    local bodyH = math.ceil((mod.bodyFs.GetStringHeight and mod.bodyFs:GetStringHeight()) or 40)
    mod:SetHeight(math.max(132, bodyH + 86))

    local p = Theme.GetPalette and Theme:GetPalette() or nil
    Theme:ApplyBackdrop(mod, "window", p)
    if mod.closeBtn then Theme:StyleButton(mod.closeBtn, "default") end
    if mod.confirmBtn then Theme:StyleButton(mod.confirmBtn, "primary") end
    if mod.cancelBtn then Theme:StyleButton(mod.cancelBtn, "default") end
    if mod.helpBtn and mod.helpBtn.RefreshTheme then mod.helpBtn:RefreshTheme() end
    if mod._solidOpaqueBg then
        local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
        mod._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
    end
    mod:ClearAllPoints()
    mod:SetPoint("CENTER", f, "CENTER", 0, 0)
    Theme:PrepareTopOverlayModal(mod, 865)
    mod:Show()
    if mod.Raise then
        mod:Raise()
    end
end

function QuickReply:RequestCloseTab(threadKey, threadTitle)
    if not threadKey or threadKey == "ch:general" or threadKey == "notes:self" or threadKey == "mentions:radar" then
        return false
    end
    local isPinned = ns.Chat and ns.Chat.IsQuickReplyPinned and ns.Chat:IsQuickReplyPinned(threadKey) == true
    if isPinned then
        self:OpenClosePinnedTabConfirm(threadKey, threadTitle)
        return true
    end
    return self:CloseTabNow(threadKey)
end

local function OpenQuickReplyPinsMenu(anchorBtn, threadKey, threadTitle)
    if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Chat) then
        return
    end
    QuickReply._ownMenuOpen = true
    QuickReply._menuActionPicked = false
    MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        if threadKey == "ch:general" then
            root:CreateTitle(L["General"] .. " (" .. L["Always Fixed"] .. ")")
            if ns.Chat.AttachGeneralFilterSubmenu then
                ns.Chat:AttachGeneralFilterSubmenu(root, function()
                    QuickReply._menuActionPicked = true
                    QuickReply._forceMsgRebuild = true
                    if QuickReply.frame and QuickReply.frame:IsShown() then
                        QuickReply:Refresh()
                    end
                end)
                root:CreateDivider()
            end
            if ns.Chat.GetJoinedOfficialChannels then
                root:CreateTitle(L["Send Channel inside General (/s, /y, /1, /2, /3...)"])
                local gTarget = ns.Chat.GetGeneralTargetInfo and ns.Chat:GetGeneralTargetInfo() or nil
                root:CreateRadio("/s · " .. L["Say"], function()
                    return not (gTarget and (gTarget.channelId or gTarget.isYell))
                end, function()
                    QuickReply._menuActionPicked = true
                    if ns.Chat.SetGeneralTargetChannel then ns.Chat:SetGeneralTargetChannel(nil) end
                    if QuickReply.frame and QuickReply.frame:IsShown() then
                        QuickReply:Refresh()
                        if QuickReply.activeKey == "ch:general" and QuickReply.SyncBlizzardStickyChannelForThread then
                            QuickReply:SyncBlizzardStickyChannelForThread("ch:general")
                        end
                        QuickReply:ReleaseKeyboardFocus(false)
                    end
                end)
                root:CreateRadio("/y · " .. L["Yell"], function()
                    return (gTarget and gTarget.isYell) == true
                end, function()
                    QuickReply._menuActionPicked = true
                    if ns.Chat.SetGeneralTargetChannel then ns.Chat:SetGeneralTargetChannel("yell") end
                    if QuickReply.frame and QuickReply.frame:IsShown() then
                        QuickReply:Refresh()
                        if QuickReply.activeKey == "ch:general" and QuickReply.SyncBlizzardStickyChannelForThread then
                            QuickReply:SyncBlizzardStickyChannelForThread("ch:general")
                        end
                        QuickReply:ReleaseKeyboardFocus(false)
                    end
                end)
                for _, ch in ipairs(ns.Chat:GetJoinedOfficialChannels()) do
                    root:CreateRadio("/" .. tostring(ch.id) .. " · " .. ch.name, function()
                        return (gTarget and gTarget.channelId == ch.id) == true
                    end, function()
                        QuickReply._menuActionPicked = true
                        if ns.Chat.SetGeneralTargetChannel then ns.Chat:SetGeneralTargetChannel(ch.id) end
                        if QuickReply.frame and QuickReply.frame:IsShown() then
                            QuickReply:Refresh()
                            if QuickReply.activeKey == "ch:general" and QuickReply.SyncBlizzardStickyChannelForThread then
                                QuickReply:SyncBlizzardStickyChannelForThread("ch:general")
                            end
                            QuickReply:ReleaseKeyboardFocus(false)
                        end
                    end)
                end
            end
            root:CreateDivider()
        elseif threadKey == "mentions:radar" then
            root:CreateTitle(L["Mentions & Keywords Radar"])
            if ns.SocialPanels and ns.SocialPanels.OpenMentionKeywordsModal then
                root:CreateButton(L["Keywords"] .. "...", function()
                    QuickReply._menuActionPicked = true
                    ns.SocialPanels:OpenMentionKeywordsModal()
                end)
            end
            if ns.Chat.PopulateThreadMuteMenu then
                local muteSub = root:CreateButton(L["Silence Notifications"])
                ns.Chat:PopulateThreadMuteMenu(muteSub, threadKey, L["Mentions"], function()
                    QuickReply._menuActionPicked = true
                    UpdateBadge(false)
                    if QuickReply.frame and QuickReply.frame:IsShown() then
                        QuickReply:Refresh()
                    end
                end)
            end
            local mObj = ns.Chat.threads and ns.Chat.threads[threadKey]
            if mObj and type(mObj.messages) == "table" and #mObj.messages > 0 and ns.Chat.ClearHistory then
                root:CreateButton(L["Clear"], function()
                    QuickReply._menuActionPicked = true
                    if ns.UI and ns.UI.OpenConfirmModal then
                        ns.UI:OpenConfirmModal({
                            title = L["Clear"],
                            message = L["Are you sure you want to clear all messages in '%s'?"]:format(L["Mentions"]),
                            confirmText = L["Clear"],
                            onConfirm = function()
                                if ns.Chat and ns.Chat.ClearHistory then
                                    ns.Chat:ClearHistory(threadKey)
                                end
                            end,
                        })
                    else
                        ns.Chat:ClearHistory(threadKey)
                    end
                end)
            end
            root:CreateDivider()
        elseif threadKey and threadKey ~= "notes:self" and threadKey ~= "mentions:radar" and ns.Chat.ToggleQuickReplyPinned then
            local tObj = ns.Chat.threads and ns.Chat.threads[threadKey]
            local titleStr = threadTitle or (tObj and (tObj.title or tObj.targetName)) or threadKey
            if ns.Compat and ns.Compat.IsStreamerMode and ns.Compat.IsStreamerMode()
                and ((tObj and tObj.kind == "BN_WHISPER") or tostring(titleStr):find("#", 1, true))
                and ns.Compat.MaskStreamerBNetName
            then
                titleStr = ns.Compat.MaskStreamerBNetName(titleStr)
            end
            root:CreateTitle(titleStr)
            if ns.Chat.PopulateThreadMuteMenu then
                local muteSub = root:CreateButton(L["Silence Notifications"])
                ns.Chat:PopulateThreadMuteMenu(muteSub, threadKey, titleStr, function()
                    QuickReply._menuActionPicked = true
                    UpdateBadge(false)
                    if QuickReply.frame and QuickReply.frame:IsShown() then
                        QuickReply:Refresh()
                    end
                end)
            end
            local isPinned = ns.Chat.IsQuickReplyPinned and ns.Chat:IsQuickReplyPinned(threadKey)
            root:CreateButton(isPinned and L["Unpin from Quick Reply"] or L["Pin in Quick Reply"], function()
                QuickReply._menuActionPicked = true
                ns.Chat:ToggleQuickReplyPinned(threadKey)
                if QuickReply.frame and QuickReply.frame:IsShown() then
                    QuickReply:Refresh()
                end
            end)
            root:CreateButton(L["Close Tab"], function()
                QuickReply._menuActionPicked = true
                QuickReply:RequestCloseTab(threadKey, titleStr)
            end)
            if tObj and (tObj.unread or 0) > 0 and ns.Chat.MarkThreadRead then
                root:CreateButton(L["Mark Read"], function()
                    QuickReply._menuActionPicked = true
                    ns.Chat:MarkThreadRead(threadKey)
                    UpdateBadge(false)
                    if QuickReply.frame and QuickReply.frame:IsShown() then
                        QuickReply:Refresh()
                    end
                end)
            end
            local curDraft = ns.Chat.GetQuickReplyDraft and ns.Chat:GetQuickReplyDraft(threadKey)
            if curDraft and curDraft ~= "" and ns.Chat.SetQuickReplyDraft then
                root:CreateButton(L["Clear Draft"], function()
                    QuickReply._menuActionPicked = true
                    ns.Chat:SetQuickReplyDraft(threadKey, "")
                    if QuickReply.activeKey == threadKey and QuickReply.frame and QuickReply.frame.inputBox then
                        QuickReply.suppressDraftSave = true
                        QuickReply.frame.inputBox:SetText("")
                        QuickReply.suppressDraftSave = false
                    end
                    UpdateBadge(false)
                    if QuickReply.frame and QuickReply.frame:IsShown() then
                        QuickReply:Refresh()
                    end
                end)
            end
            root:CreateDivider()
        end
        local pendingList = ns.Chat.GetQuickReplyThreads and ns.Chat:GetQuickReplyThreads() or {}
        local unreadTabsCount = 0
        for _, it in ipairs(pendingList) do
            if (it.unread or 0) > 0 then
                unreadTabsCount = unreadTabsCount + 1
            end
        end
        if unreadTabsCount >= 2 and ns.Chat.MarkAllQuickReplyRead then
            root:CreateButton(L["Mark All Read"], function()
                QuickReply._menuActionPicked = true
                ns.Chat:MarkAllQuickReplyRead()
                UpdateBadge(false)
                if QuickReply.frame and QuickReply.frame:IsShown() then
                    QuickReply:Refresh()
                end
            end)
            root:CreateDivider()
        end
        root:CreateTitle(L["Pin Channel Tabs"])
        local inGuild = false
        if ns.Compat and ns.Compat.ShouldShowGuildFeatures then
            inGuild = ns.Compat.ShouldShowGuildFeatures() == true
        elseif ns.Compat and ns.Compat.IsInGuild then
            inGuild = ns.Compat.IsInGuild() == true
        end
        local isAllianceAuth = inGuild and ns.Clan and ns.Clan.IsMemberAllianceAuthorized and ns.Clan:IsMemberAllianceAuthorized()
        local channels = {
            { key = "ch:guild", label = L["Guild"], visible = inGuild or (ns.Chat.threads["ch:guild"] and #(ns.Chat.threads["ch:guild"].messages or {}) > 0) },
            { key = "ch:officer", label = L["Officer"], visible = inGuild or (ns.Chat.threads["ch:officer"] and #(ns.Chat.threads["ch:officer"].messages or {}) > 0) },
            { key = "ch:party", label = L["Party"], visible = true },
            { key = "ch:raid", label = L["Raid"], visible = true },
            { key = "ch:instance", label = L["Instance"], visible = true },
            { key = "ch:alliance", label = L["Alliance"], visible = isAllianceAuth or (ns.Chat.threads["ch:alliance"] and #(ns.Chat.threads["ch:alliance"].messages or {}) > 0) },
        }
        for _, ch in ipairs(channels) do
            if ch.visible then
                root:CreateCheckbox(ch.label, function()
                    return ns.Chat.IsQuickReplyPinned and ns.Chat:IsQuickReplyPinned(ch.key) == true
                end, function()
                    QuickReply._menuActionPicked = true
                    if ns.Chat.ToggleQuickReplyPinned then
                        ns.Chat:ToggleQuickReplyPinned(ch.key)
                    end
                    if QuickReply.frame and QuickReply.frame:IsShown() then
                        QuickReply:Refresh()
                    end
                end)
            end
        end
    end)
end

local function OpenQuickReplyHistoryMenu(anchorBtn)
    if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Chat and ns.Chat.threads) then
        return
    end
    QuickReply._ownMenuOpen = true
    QuickReply._menuActionPicked = false

    local streamerOn = Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()
    local allRows = ns.Chat.GetThreadsList and ns.Chat:GetThreadsList("all") or {}
    local seenKeys = {}
    local merged = {}
    for _, item in ipairs(allRows) do
        if type(item) == "table" and item.key then
            local msgsCount = tonumber(item.count) or 0
            local hasActivity = msgsCount > 0 or (tonumber(item.lastAt) or 0) > 0
            if hasActivity then
                seenKeys[item.key] = true
                merged[#merged + 1] = item
            end
        end
    end
    for key, t in pairs(ns.Chat.threads) do
        if not seenKeys[key] and type(t) == "table" and key:sub(1, 3) == "ch:" and type(t.messages) == "table" and #t.messages > 0 then
            local k = t.kind
            if k ~= "GUILD" and k ~= "OFFICER" and k ~= "PARTY" and k ~= "RAID" and k ~= "INSTANCE_CHAT" and k ~= "ALLIANCE" then
                local lastMsg = t.messages[#t.messages]
                seenKeys[key] = true
                merged[#merged + 1] = {
                    key = key,
                    kind = k or "CHANNEL",
                    title = t.title or key:sub(4),
                    unread = (not (ns.Chat.IsThreadMuted and ns.Chat:IsThreadMuted(key))) and (t.unread or 0) or 0,
                    lastAt = tonumber(t.lastAt) or 0,
                    preview = lastMsg and lastMsg.text or "",
                    count = #t.messages,
                    classFile = t.classFile,
                }
            end
        end
    end

    local function SortByRecent(a, b)
        local at = tonumber(a.lastAt) or 0
        local bt = tonumber(b.lastAt) or 0
        if at ~= bt then
            return at > bt
        end
        return tostring(a.key or "") < tostring(b.key or "")
    end
    table.sort(merged, SortByRecent)

    local buckets = {
        all = merged,
        whispers = {},
        bnet = {},
        group = {},
        guild = {},
        rooms = {},
        channels = {},
        mentions = {},
    }
    for _, item in ipairs(merged) do
        local k = item.kind
        if k == "WHISPER" then
            buckets.whispers[#buckets.whispers + 1] = item
        elseif k == "BN_WHISPER" then
            buckets.bnet[#buckets.bnet + 1] = item
        elseif k == "PARTY" or k == "RAID" or k == "INSTANCE_CHAT" then
            buckets.group[#buckets.group + 1] = item
        elseif k == "GUILD" or k == "OFFICER" or k == "ALLIANCE" then
            buckets.guild[#buckets.guild + 1] = item
        elseif k == "ROOM" then
            buckets.rooms[#buckets.rooms + 1] = item
        elseif k == "MENTIONS" or k == "NOTES" or item.key == "mentions:radar" or item.key == "notes:self" then
            buckets.mentions[#buckets.mentions + 1] = item
        else
            buckets.channels[#buckets.channels + 1] = item
        end
    end

    local function PopulateHistorySubmenu(subMenu, list)
        local limit = math.min(#list, 16)
        for i = 1, limit do
            local entry = list[i]
            local dispTitle = tostring(entry.title or entry.key or "?")
            if streamerOn and (entry.kind == "BN_WHISPER" or dispTitle:find("#", 1, true)) and Compat.MaskStreamerBNetName then
                dispTitle = Compat.MaskStreamerBNetName(dispTitle)
            end
            local toneKey = (ns.Theme and ns.Theme.GetChatToneForKind) and ns.Theme:GetChatToneForKind(entry.kind) or "whisper"
            local spec = (ns.Theme and ns.Theme.GetChatToneSpec) and ns.Theme:GetChatToneSpec(toneKey)
            local hex = (entry.classFile and Compat and Compat.ClassHex) and Compat.ClassHex(entry.classFile) or (spec and spec.hex) or "|cffffffff"
            local countStr = (tonumber(entry.count) or 0) > 0 and (" |cff9da7b5(" .. tostring(entry.count) .. ")|r") or ""
            local unreadStr = (tonumber(entry.unread) or 0) > 0 and (" |cff4ade80[" .. tostring(entry.unread) .. "]|r") or ""
            local snip = tostring(entry.preview or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("[%c]+", " ")
            snip = QuickReply:TruncateUtf8(snip, 28)
            if streamerOn and (entry.kind == "WHISPER" or entry.kind == "BN_WHISPER" or entry.kind == "ROOM") then
                snip = ""
            end
            local snipStr = (snip ~= "") and (" |cff7d8590- " .. snip .. "|r") or ""
            subMenu:CreateButton(hex .. dispTitle .. "|r" .. countStr .. unreadStr .. snipStr, function()
                QuickReply._menuActionPicked = true
                QuickReply:SaveCurrentDraft()
                QuickReply:OpenThread(entry.key, false)
            end)
        end
        if #list > limit then
            subMenu:CreateDivider()
            subMenu:CreateButton(L["Open Full History Search..."], function()
                QuickReply._menuActionPicked = true
                QuickReply:SaveCurrentDraft()
                if QuickReply.frame then QuickReply.frame:Hide() end
                if ns.NavigateToModule then
                    ns:NavigateToModule("chat")
                elseif ns.UI and ns.UI.ShowHub then
                    ns.UI:ShowHub("chat")
                end
            end)
        end
    end

    MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        root:CreateTitle(L["Message History (By Type)"])
        local categories = {
            { id = "all", label = L["All Recent"] },
            { id = "whispers", label = L["Whispers"] },
            { id = "bnet", label = "Battle.net" },
            { id = "group", label = L["Group / Raid / Instance"] },
            { id = "guild", label = L["Guild / Officer / Alliance"] },
            { id = "rooms", label = L["Private Rooms"] },
            { id = "channels", label = L["Public Channels"] },
            { id = "mentions", label = L["Mentions & Notes"] },
        }
        local anyShown = false
        for _, cat in ipairs(categories) do
            local list = buckets[cat.id]
            if list and #list > 0 then
                anyShown = true
                local sub = root:CreateButton(string.format("%s |cff9da7b5(%d)|r", cat.label, #list))
                if sub then
                    PopulateHistorySubmenu(sub, list)
                end
            end
        end
        if not anyShown then
            local emptyBtn = root:CreateButton("|cff8b949e" .. L["No saved message history yet."] .. "|r", function() end)
            if emptyBtn and emptyBtn.SetEnabled then
                emptyBtn:SetEnabled(false)
            end
        end
        root:CreateDivider()
        root:CreateButton(L["Open Full History Search..."], function()
            QuickReply._menuActionPicked = true
            QuickReply:SaveCurrentDraft()
            if QuickReply.frame then QuickReply.frame:Hide() end
            if ns.NavigateToModule then
                ns:NavigateToModule("chat")
            elseif ns.UI and ns.UI.ShowHub then
                ns.UI:ShowHub("chat")
            end
        end)
    end)
end

function QuickReply:IsWhispersDropdownShown()
    return (self._whispersDropdown and self._whispersDropdown.IsShown and self._whispersDropdown:IsShown()) == true
end

function QuickReply:HideWhispersDropdown()
    if self._whispersDropdown and self._whispersDropdown.IsShown and self._whispersDropdown:IsShown() then
        self._whispersDropdown:Hide()
    end
end

function QuickReply:ShouldWhispersDropdownOpenUp()
    local f = self.frame
    local uiH = (_G.UIParent and _G.UIParent.GetHeight and _G.UIParent:GetHeight()) or 768
    if f and f.GetCenter then
        local _, fCy = f:GetCenter()
        if fCy then
            return fCy < (uiH * 0.50)
        end
    end
    return true
end

function QuickReply:CollectRecentWhispers(maxCount)
    local out = {}
    local unreadTotal = 0
    if not (ns.Chat and ns.Chat.GetThreadsList) then
        return out, unreadTotal
    end
    local allRows = ns.Chat:GetThreadsList("all") or {}
    for _, item in ipairs(allRows) do
        if type(item) == "table" and (item.kind == "WHISPER" or item.kind == "BN_WHISPER") then
            local msgsCount = tonumber(item.count) or 0
            local lastAt = tonumber(item.lastAt) or 0
            if msgsCount > 0 or lastAt > 0 then
                out[#out + 1] = item
                local isMuted = ns.Chat.IsThreadMuted and ns.Chat:IsThreadMuted(item.key) == true
                if not isMuted then
                    unreadTotal = unreadTotal + (tonumber(item.unread) or 0)
                end
            end
        end
    end
    table.sort(out, function(a, b)
        local at = tonumber(a.lastAt) or 0
        local bt = tonumber(b.lastAt) or 0
        if at ~= bt then
            return at > bt
        end
        return tostring(a.key or "") < tostring(b.key or "")
    end)
    local cap = maxCount or 10
    if #out > cap then
        for i = #out, cap + 1, -1 do
            out[i] = nil
        end
    end
    return out, unreadTotal
end

function QuickReply:IsSlashAutoOpenEnabled()
    local s = ns.db and ns.db.settings
    return (not s) or (s.quickReplyEnabled ~= false and s.quickReplySlashOpen ~= false)
end

function QuickReply:ResolveLiveSlashThread(rawSlash, blizzChatType, blizzTellTarget, allowLocalWhisperAndSay, blizzChannelTarget, fromLiveTyping)
    local tok = (type(rawSlash) == "string") and rawSlash:match("^%s*(/[%a%d]+)") or nil
    local up = tok and tok:upper() or ""
    if up == "" and blizzChatType ~= "CHANNEL" then
        return nil
    end
    if not ns.Chat then
        return nil
    end

    local numChanStr = up:match("^/(%d+)$")
    if numChanStr or blizzChatType == "CHANNEL" then
        local cid = tonumber(numChanStr) or tonumber(blizzChannelTarget)
        if cid and ns.Chat.SetGeneralTargetChannel and ns.Chat.GetOfficialChannelInfo and ns.Chat:GetOfficialChannelInfo(cid) then
            ns.Chat:SetGeneralTargetChannel(cid)
            return "ch:general"
        end
        return nil
    end

    if up == "/P" or up == "/PARTY" or up == "/GRUPO" then
        if ns.Chat.EnsureStaticChannelThread then
            local t = ns.Chat:EnsureStaticChannelThread("ch:party")
            return t and t.key or "ch:party"
        end
        return nil
    elseif up == "/RA" or up == "/RAID" or up == "/RAIDE" or up == "/BANDA" then
        if ((Compat and Compat.IsInRaid and Compat.IsInRaid()) or blizzChatType == "RAID") and ns.Chat.EnsureStaticChannelThread then
            local t = ns.Chat:EnsureStaticChannelThread("ch:raid")
            return t and t.key or "ch:raid"
        end
        return nil
    elseif up == "/I" or up == "/INSTANCE" or up == "/INSTANCIA" or up == "/BG" then
        local inInst = (_G.IsInGroup and _G.LE_PARTY_CATEGORY_INSTANCE and _G.IsInGroup(_G.LE_PARTY_CATEGORY_INSTANCE)) == true
        if (inInst or blizzChatType == "INSTANCE_CHAT" or blizzChatType == "BATTLEGROUND") and ns.Chat.EnsureStaticChannelThread then
            local t = ns.Chat:EnsureStaticChannelThread("ch:instance")
            return t and t.key or "ch:instance"
        end
        return nil
    elseif up == "/G" or up == "/GUILD" or up == "/GUILDA" or up == "/H" or up == "/HERMANDAD" then
        if ((Compat and Compat.IsInGuild and Compat.IsInGuild()) or blizzChatType == "GUILD") and ns.Chat.EnsureStaticChannelThread then
            local t = ns.Chat:EnsureStaticChannelThread("ch:guild")
            return t and t.key or "ch:guild"
        end
        return nil
    elseif up == "/O" or up == "/OFFICER" or up == "/OFICIAL" then
        local inGuild = Compat and Compat.IsInGuild and Compat.IsInGuild() == true
        local canOff = (blizzChatType == "OFFICER")
            or (_G.C_GuildInfo and _G.C_GuildInfo.CanViewOfficerNote and _G.C_GuildInfo.CanViewOfficerNote())
            or (_G.CanViewOfficerNote and _G.CanViewOfficerNote())
        if ((inGuild and canOff) or blizzChatType == "OFFICER") and ns.Chat.EnsureStaticChannelThread then
            local t = ns.Chat:EnsureStaticChannelThread("ch:officer")
            return t and t.key or "ch:officer"
        end
        return nil
    elseif up == "/AL" or up == "/ALI" or up == "/ALLY" or up == "/ALIANCA" or up == "/ALIANZA" then
        local canAlly = ns.Clan and ns.Clan.IsMemberAllianceAuthorized and ns.Clan:IsMemberAllianceAuthorized()
        if canAlly and ns.Chat.EnsureStaticChannelThread then
            local t = ns.Chat:EnsureStaticChannelThread("ch:alliance")
            return t and t.key or "ch:alliance"
        end
        return nil
    elseif (up == "/S" or up == "/SAY" or up == "/DIZER" or up == "/DECIR") then
        if (allowLocalWhisperAndSay or (QuickReply.frame and QuickReply.frame:IsShown())) and ns.Chat.SetGeneralTargetChannel then
            ns.Chat:SetGeneralTargetChannel(nil)
            return "ch:general"
        end
        return nil
    elseif (up == "/Y" or up == "/YELL" or up == "/GRITAR") then
        if (allowLocalWhisperAndSay or (QuickReply.frame and QuickReply.frame:IsShown())) and ns.Chat.SetGeneralTargetChannel then
            ns.Chat:SetGeneralTargetChannel("yell")
            return "ch:general"
        end
        return nil
    elseif up == "/R" or up == "/REPLY" or up == "/W" or up == "/WHISPER" or up == "/T" or up == "/TELL" then
        if blizzChatType == "WHISPER" and type(blizzTellTarget) == "string" and blizzTellTarget ~= "" and ns.Chat.EnsureWhisperThread then
            local wt = ns.Chat:EnsureWhisperThread(blizzTellTarget)
            return wt and wt.key or nil
        elseif blizzChatType == "BN_WHISPER" and type(blizzTellTarget) == "string" and blizzTellTarget ~= "" and type(ns.Chat.threads) == "table" then
            local wantLow = blizzTellTarget:lower()
            for tKey, tr in pairs(ns.Chat.threads) do
                if type(tr) == "table" and tr.kind == "BN_WHISPER" then
                    local t1 = type(tr.title) == "string" and tr.title:lower() or ""
                    local t2 = type(tr.targetName) == "string" and tr.targetName:lower() or ""
                    local t3 = type(tr.bnetName) == "string" and tr.bnetName:lower() or ""
                    if t1 == wantLow or t2 == wantLow or t3 == wantLow then
                        return tKey
                    end
                end
            end
            for _, row in ipairs(self:CollectRecentWhispers(10)) do
                if row.kind == "BN_WHISPER" then
                    return row.key
                end
            end
            return nil
        elseif up == "/R" or up == "/REPLY" then
            local recent = self:CollectRecentWhispers(1)
            return recent[1] and recent[1].key or nil
        elseif allowLocalWhisperAndSay and type(rawSlash) == "string" and ns.Chat.EnsureWhisperThread then
            local w1, w2, after2 = rawSlash:match("^%s*/[%a]+%s+(%S+)%s+(%S+)%s+(.*)$")
            if w1 and w2 then
                local cand2 = w1 .. " " .. w2
                local lk2 = (Compat and Compat.ParseCharacterFields and select(1, Compat.ParseCharacterFields(cand2))) or cand2:lower()
                local known2 = (ns.Chat.threads and ns.Chat.threads["w:" .. lk2] ~= nil)
                    or (ns.Store and ns.Store.socialDirectoryByLookup and ns.Store.socialDirectoryByLookup[lk2] ~= nil)
                    or (Compat and Compat.LookupForeverFullName and Compat.LookupForeverFullName(cand2) ~= nil)
                local looksTwoWordCap = (not fromLiveTyping)
                    and w1:match("^[A-Z][a-z]+$") ~= nil and w2:match("^[A-Z][a-z]+$") ~= nil
                    and after2 and after2 ~= ""
                if known2 or looksTwoWordCap then
                    local wt2 = ns.Chat:EnsureWhisperThread(cand2)
                    if wt2 and wt2.key then
                        return wt2.key, after2 or ""
                    end
                end
            end
            if not fromLiveTyping then
                local tgt, afterTgt = rawSlash:match("^%s*/[%a]+%s+(%S+)%s+(.*)$")
                if tgt and tgt ~= "" then
                    local wt = ns.Chat:EnsureWhisperThread(tgt)
                    if wt and wt.key then
                        return wt.key, afterTgt or ""
                    end
                end
            end
        end
        return nil
    end

    return nil
end

function QuickReply:RedirectBlizzardEditBoxToThread(editBox, targetKey, restText)
    if not (editBox and targetKey) then
        return false
    end
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return false
    end
    editBox._scPendingSlash = nil
    editBox._scPendingSlashAt = nil
    if editBox._scRedirecting then
        return false
    end
    editBox._scRedirecting = true
    if editBox.SetText then
        pcall(editBox.SetText, editBox, "")
    end

    local savedRest = (type(restText) == "string" and restText ~= "" and restText:sub(1, 1) ~= "/") and restText or ""
    local function FinishRedirect()
        if editBox then
            editBox._scRedirecting = nil
        end
        if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
            return
        end
        if editBox and editBox.GetText then
            local lateTxt = (ns.Safe and ns.Safe.String(editBox:GetText())) or ""
            if lateTxt ~= "" and lateTxt:sub(1, 1) ~= "/" then
                if savedRest == "" then
                    savedRest = lateTxt
                elseif lateTxt ~= savedRest then
                    savedRest = savedRest .. lateTxt
                end
            end
        end
        if editBox and editBox.SetText then
            pcall(editBox.SetText, editBox, "")
        end
        if _G.ChatFrameUtil and _G.ChatFrameUtil.DeactivateChat then
            pcall(_G.ChatFrameUtil.DeactivateChat, editBox)
        elseif _G.ChatEdit_DeactivateChat then
            pcall(_G.ChatEdit_DeactivateChat, editBox)
        elseif editBox and editBox.Deactivate then
            pcall(editBox.Deactivate, editBox)
        end
        if editBox then
            if editBox.HasFocus and editBox:HasFocus() and editBox.ClearFocus then
                pcall(editBox.ClearFocus, editBox)
            end
            if editBox.IsShown and editBox:IsShown() and editBox.Hide then
                pcall(editBox.Hide, editBox)
            end
        end
        QuickReply:OpenThread(targetKey, true, savedRest)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, FinishRedirect)
    else
        FinishRedirect()
    end
    return true
end

function QuickReply:HandleBlizzardEditBoxSlashTrigger(editBox)
    if not editBox or editBox._scRedirecting then
        return
    end
    if (not QuickReply._redirectingBlizzCombatChat) and editBox.HasFocus and editBox:HasFocus() then
        local liveTxt = (editBox.GetText and ns.Safe and ns.Safe.String(editBox:GetText())) or ""
        if liveTxt:match("^%s*/[%a%d]+") then
            local nowSlash = (GetTime and GetTime()) or 0
            local lowSlash = liveTxt:match("^%s*(/[%a%d]+)")
            local upSlash = lowSlash and lowSlash:upper() or ""
            if not IsTemporaryOfficialEditAllowed() then
                editBox._scLastManualBlizzSwitchAt = nowSlash
                if upSlash == "/S" or upSlash == "/SAY" or upSlash == "/DIZER" or upSlash == "/DECIR" then
                    editBox._scExplicitSayAt = nowSlash
                else
                    editBox._scExplicitSayAt = nil
                end
            end
        end
    end
    if Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode() then
        return
    end
    if (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player"))
        or (not self:IsSlashAutoOpenEnabled())
        or ((GetTime and GetTime() or 0) < (self._suppressBlizzSlashRedirectUntil or 0))
    then
        editBox._scPendingSlash = nil
        editBox._scPendingSlashAt = nil
        return
    end
    if editBox.HasFocus and not editBox:HasFocus() then
        return
    end
    local curTxt = (editBox.GetText and ns.Safe and ns.Safe.String(editBox:GetText())) or ""
    local now = (GetTime and GetTime()) or 0

    -- Never intercept while the user is still typing ANY slash command without Space yet
    -- (so /r -> /reload, /p -> /played, /g -> /gm, /i -> /invite, /ra -> /random always work).
    if curTxt:match("^%s*/[^%s]*$") then
        if curTxt:match("^%s*/[%a%d]+$") then
            editBox._scPendingSlash = curTxt
            editBox._scPendingSlashAt = now
        else
            editBox._scPendingSlash = nil
            editBox._scPendingSlashAt = nil
        end
        return
    end

    local prevSlash = editBox._scPendingSlash
    local prevAt = editBox._scPendingSlashAt or 0
    local cand = nil
    if curTxt:match("^%s*/[%a%d]+%s") then
        cand = curTxt
    elseif (not curTxt:match("^%s*/")) and type(prevSlash) == "string" and prevSlash ~= "" and (now - prevAt) <= 8.0 then
        cand = prevSlash
    end
    if not cand then
        if not curTxt:match("^%s*/") then
            editBox._scPendingSlash = nil
            editBox._scPendingSlashAt = nil
        end
        return
    end
    local cType = (editBox.GetChatType and editBox:GetChatType())
        or (editBox.GetAttribute and editBox:GetAttribute("chatType"))
        or nil
    local tellTgt = (editBox.GetTellTarget and editBox:GetTellTarget())
        or (editBox.GetAttribute and editBox:GetAttribute("tellTarget"))
        or nil
    local chanTgt = (editBox.GetChannelTarget and editBox:GetChannelTarget())
        or (editBox.GetAttribute and editBox:GetAttribute("channelTarget"))
        or nil
    local upTok = (cand:match("^%s*(/[%a%d]+)") or ""):upper()
    if (upTok == "/W" or upTok == "/WHISPER" or upTok == "/T" or upTok == "/TELL") and curTxt:match("^%s*/") then
        editBox._scPendingSlash = curTxt
        editBox._scPendingSlashAt = now
        return
    end
    editBox._scPendingSlash = nil
    editBox._scPendingSlashAt = nil
    local tKey = self:ResolveLiveSlashThread(cand, cType, tellTgt, nil, chanTgt)
    if tKey then
        if tKey == "ch:general" and self.frame and self.frame:IsShown() and self.activeKey == "ch:general" and self._dockedOfficialInputActive then
            self:Refresh()
            return
        end
        local rem = curTxt
        if rem:match("^%s*/[%a%d]+%s+(.*)$") then
            rem = rem:match("^%s*/[%a%d]+%s+(.*)$") or ""
        elseif rem:sub(1, 1) == "/" then
            rem = ""
        end
        self:RedirectBlizzardEditBoxToThread(editBox, tKey, rem)
    end
end

function QuickReply:HookBlizzardEditBoxForSlash(eb)
    if not (eb and eb.HookScript) or eb._scSlashRedirectHooked then
        return
    end
    eb._scSlashRedirectHooked = true
    eb:HookScript("OnShow", function()
        QuickReply:SyncEnterBinding()
    end)
    eb:HookScript("OnHide", function()
        if C_Timer and C_Timer.After then
            if not QuickReply._syncEnterOnHideQueued then
                QuickReply._syncEnterOnHideQueued = true
                if not QuickReply._syncEnterOnHideFn then
                    QuickReply._syncEnterOnHideFn = function()
                        QuickReply._syncEnterOnHideQueued = false
                        QuickReply:SyncEnterBinding()
                    end
                end
                C_Timer.After(0, QuickReply._syncEnterOnHideFn)
            end
        else
            QuickReply:SyncEnterBinding()
        end
    end)
    eb:HookScript("OnTextChanged", function(selfEb, isUserInput)
        if (InCombatLockdown and InCombatLockdown())
            or (UnitAffectingCombat and UnitAffectingCombat("player"))
            or (not QuickReply:IsSlashAutoOpenEnabled())
            or ((GetTime and GetTime() or 0) < (QuickReply._suppressBlizzSlashRedirectUntil or 0))
            or selfEb._scRedirecting
        then
            selfEb._scPendingSlash = nil
            selfEb._scPendingSlashAt = nil
            return
        end
        if selfEb.HasFocus and not selfEb:HasFocus() then
            return
        end
        local txt = (ns.Safe and ns.Safe.String(selfEb:GetText())) or ""
        local slashTok, restTxt = txt:match("^%s*(/[%a%d]+)%s+(.*)$")
        if slashTok then
            if isUserInput ~= false then
                local upTok = slashTok:upper()
                if upTok == "/R" or upTok == "/REPLY" or upTok == "/W" or upTok == "/WHISPER" or upTok == "/T" or upTok == "/TELL" then
                    selfEb._scPendingSlash = txt
                    selfEb._scPendingSlashAt = (GetTime and GetTime()) or 0
                    return
                end
                local tKey = QuickReply:ResolveLiveSlashThread(slashTok, nil, nil)
                if tKey then
                    if tKey == "ch:general" and QuickReply.frame and QuickReply.frame:IsShown() and QuickReply.activeKey == "ch:general" and QuickReply._dockedOfficialInputActive then
                        QuickReply:Refresh()
                        return
                    end
                    QuickReply:RedirectBlizzardEditBoxToThread(selfEb, tKey, restTxt)
                    return
                end
                selfEb._scPendingSlash = nil
                selfEb._scPendingSlashAt = nil
            end
        elseif txt:match("^%s*/[%a%d]+$") then
            selfEb._scPendingSlash = txt
            selfEb._scPendingSlashAt = (GetTime and GetTime()) or 0
        elseif txt == "" then
            if isUserInput == true then
                selfEb._scPendingSlash = nil
                selfEb._scPendingSlashAt = nil
            end
        else
            selfEb._scPendingSlash = nil
            selfEb._scPendingSlashAt = nil
        end
    end)
    eb:HookScript("OnSpacePressed", function(selfEb)
        QuickReply:HandleBlizzardEditBoxSlashTrigger(selfEb)
    end)
    eb:HookScript("OnEditFocusLost", function(selfEb)
        selfEb._scPendingSlash = nil
        selfEb._scPendingSlashAt = nil
    end)
    eb:HookScript("OnHide", function(selfEb)
        selfEb._scPendingSlash = nil
        selfEb._scPendingSlashAt = nil
        if not QuickReply._redirectingBlizzCombatChat then
            QuickReply._allowTempOfficialEditUntil = nil
        end
    end)
    if type(eb.ParseText) == "function" and hooksecurefunc then
        hooksecurefunc(eb, "ParseText", function(selfEb, send)
            if send == 0 then
                QuickReply:HandleBlizzardEditBoxSlashTrigger(selfEb)
            end
        end)
    end
end

function QuickReply:UpdateWhispersButton()
    local f = self.frame
    if not (f and f.btnWhispers and ns.Theme) then
        return
    end
    local unreadTotal = 0
    if ns.Chat and ns.Chat.GetQuickWhisperUnreadCount then
        unreadTotal = ns.Chat:GetQuickWhisperUnreadCount()
    else
        local _, fallbackUnread = self:CollectRecentWhispers(10)
        unreadTotal = fallbackUnread or 0
    end
    local openUp = self:ShouldWhispersDropdownOpenUp()
    local isDropShown = self:IsWhispersDropdownShown()
    local themeKey = (ns.Theme.GetThemeName and ns.Theme:GetThemeName()) or "blizzard"
    local isActive = isDropShown or (unreadTotal > 0)
    if f.btnWhispers._scWhispUnread == unreadTotal
        and f.btnWhispers._scWhispUp == openUp
        and f.btnWhispers._scWhispAct == isActive
        and f.btnWhispers._scWhispTheme == themeKey
    then
        return
    end
    f.btnWhispers._scWhispUnread = unreadTotal
    f.btnWhispers._scWhispUp = openUp
    f.btnWhispers._scWhispAct = isActive
    f.btnWhispers._scWhispTheme = themeKey
    local arrowTex = openUp and ICON_ARROW_UP or ICON_ARROW_DOWN
    local arrowTag = "|T" .. arrowTex .. ":12:12:0:-1|t"
    local badgeStr = (unreadTotal > 0) and (" |cff4ade80(" .. tostring(unreadTotal) .. ")|r") or ""
    ns.Theme:SetButtonText(f.btnWhispers, L["Whispers"] .. badgeStr .. " " .. arrowTag)
    ns.Theme:AutoFitButton(f.btnWhispers, 76, 16, 136)
    ns.Theme:StyleButton(f.btnWhispers, isActive and "primary" or "default")
end

function QuickReply:EnsureWhispersDropdown()
    if self._whispersDropdown then
        return self._whispersDropdown
    end
    local Theme = ns.Theme
    local pop = CreateFrame("Frame", "SocialCentralQuickReplyWhispersPopup", UIParent, "BackdropTemplate")
    pop:Hide()
    pop:SetSize(292, 94)
    pop:SetClampedToScreen(true)
    pop:SetFrameStrata("FULLSCREEN_DIALOG")
    pop:SetFrameLevel(860)
    pop:SetToplevel(true)
    pop:EnableMouse(true)

    if _G.UISpecialFrames then
        local seenSpec = false
        for _, v in ipairs(_G.UISpecialFrames) do
            if v == "SocialCentralQuickReplyWhispersPopup" then
                seenSpec = true
                break
            end
        end
        if not seenSpec then
            table.insert(_G.UISpecialFrames, "SocialCentralQuickReplyWhispersPopup")
        end
    end

    local bg = pop:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(pop)
    bg:SetTexture(QR_WHITE8X8)
    bg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    pop._solidOpaqueBg = bg

    local titleFs = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleFs:SetPoint("TOPLEFT", pop, "TOPLEFT", 10, -8)
    titleFs:SetText(L["Recent Whispers"])
    pop.titleFs = titleFs

    local countFs = pop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countFs:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -10, -8)
    countFs:SetJustifyH("RIGHT")
    pop.countFs = countFs

    local topRule = pop:CreateTexture(nil, "BORDER", nil, 1)
    topRule:SetHeight(1)
    topRule:SetPoint("TOPLEFT", pop, "TOPLEFT", 8, -23)
    topRule:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -8, -23)
    topRule:SetColorTexture(0.75, 0.62, 0.30, 0.35)
    pop.topRule = topRule

    local botRule = pop:CreateTexture(nil, "BORDER", nil, 1)
    botRule:SetHeight(1)
    botRule:SetPoint("BOTTOMLEFT", pop, "BOTTOMLEFT", 8, 32)
    botRule:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -8, 32)
    botRule:SetColorTexture(0.75, 0.62, 0.30, 0.28)
    pop.botRule = botRule

    local emptyFs = pop:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyFs:SetPoint("TOPLEFT", pop, "TOPLEFT", 10, -32)
    emptyFs:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -10, -32)
    emptyFs:SetJustifyH("LEFT")
    emptyFs:SetWordWrap(true)
    emptyFs:SetText(L["No recent whispers yet."])
    pop.emptyFs = emptyFs

    pop.rows = {}
    for i = 1, 10 do
        local row = CreateFrame("Button", nil, pop)
        row:SetSize(280, 26)
        row:SetPoint("TOPLEFT", pop, "TOPLEFT", 6, -28 - ((i - 1) * 27))
        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints(row)
        row.bg = rowBg

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(row)
        hl:SetColorTexture(1.0, 0.85, 0.35, 0.18)

        local snipFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        snipFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        snipFs:SetWidth(104)
        snipFs:SetJustifyH("RIGHT")
        snipFs:SetWordWrap(false)
        row.snipFs = snipFs

        local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameFs:SetPoint("LEFT", row, "LEFT", 8, 0)
        nameFs:SetPoint("RIGHT", snipFs, "LEFT", -6, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(false)
        row.nameFs = nameFs

        row:SetScript("OnClick", function(selfRow)
            local entry = selfRow._entry
            if not (entry and entry.key) then return end
            QuickReply:SaveCurrentDraft()
            QuickReply:HideWhispersDropdown()
            QuickReply:OpenThread(entry.key, false)
        end)
        row:SetScript("OnEnter", function(selfRow)
            local entry = selfRow._entry
            if not (entry and GameTooltip) then return end
            GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            local rightStamp = (entry.lastAt and entry.lastAt > 0 and Compat and Compat.FormatRelativeTime)
                and Compat.FormatRelativeTime(entry.lastAt, L)
                or ""
            GameTooltip:AddDoubleLine(selfRow._tipTitle or "?", rightStamp, 1.0, 0.85, 0.25, 0.65, 0.72, 0.80)
            if selfRow._tipSub and selfRow._tipSub ~= "" then
                GameTooltip:AddLine(selfRow._tipSub, 0.90, 0.93, 0.97, true)
            end
            GameTooltip:AddLine(L["Click to open conversation"], 0.45, 0.85, 1.0, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        row:Hide()
        pop.rows[i] = row
    end

    local newChatDropBtn = Theme:CreateButton(pop, 28, 22, "+", "primary")
    newChatDropBtn:SetPoint("BOTTOMLEFT", pop, "BOTTOMLEFT", 6, 6)
    newChatDropBtn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["New 1-on-1 Chat"], 1.0, 0.85, 0.25)
        GameTooltip:AddLine(L["Open a 1-on-1 conversation with a friend, guildmate, target, or character name."], 0.90, 0.93, 0.96, true)
        GameTooltip:Show()
    end)
    newChatDropBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    newChatDropBtn:SetScript("OnClick", function()
        QuickReply:HideWhispersDropdown()
        if ns.SocialPanels and ns.SocialPanels.OpenNewDirectChatModal then
            ns.SocialPanels:OpenNewDirectChatModal({
                onOpened = function(newKey)
                    if newKey then
                        QuickReply:OpenThread(newKey, true)
                    end
                end,
            })
        end
    end)
    pop.newChatDropBtn = newChatDropBtn

    local openAllBtn = Theme:CreateButton(pop, 248, 22, L["Open All Whispers..."], "default")
    openAllBtn:SetPoint("LEFT", newChatDropBtn, "RIGHT", 4, 0)
    openAllBtn:SetPoint("RIGHT", pop, "RIGHT", -6, 0)
    openAllBtn:SetScript("OnClick", function()
        QuickReply:SaveCurrentDraft()
        QuickReply:HideWhispersDropdown()
        if QuickReply.frame then QuickReply.frame:Hide() end
        local navOpts = { chatFilter = "whispers" }
        if ns.NavigateToModule then
            ns:NavigateToModule("chat", navOpts)
        elseif ns.UI then
            if ns.UI.SetChatNavigation then
                ns.UI:SetChatNavigation(navOpts)
            end
            if ns.UI.ShowHub then
                ns.UI:ShowHub("chat")
            end
        end
    end)
    pop.openAllBtn = openAllBtn

    pop:HookScript("OnHide", function()
        QuickReply:UpdateWhispersButton()
    end)

    self._whispersDropdown = pop
    return pop
end

function QuickReply:ToggleWhispersDropdown(anchorBtn)
    if self:IsWhispersDropdownShown() then
        self:HideWhispersDropdown()
        return
    end
    local pop = self:EnsureWhispersDropdown()
    local Theme = ns.Theme
    local p = Theme and Theme.GetPalette and Theme:GetPalette() or nil
    if pop._solidOpaqueBg then
        local wBg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
        pop._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
    end
    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(pop, "window", p)
    end
    if pop.titleFs then
        local gc = (p and (p.textGold or p.accent)) or { 1.0, 0.82, 0.25 }
        pop.titleFs:SetTextColor(gc[1], gc[2], gc[3])
    end
    if Theme and Theme.StyleButton and pop.openAllBtn then
        Theme:StyleButton(pop.openAllBtn, "default")
    end
    if Theme and Theme.StyleButton and pop.newChatDropBtn then
        Theme:StyleButton(pop.newChatDropBtn, "primary")
    end

    local streamerOn = Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()
    local list, unreadTotal = self:CollectRecentWhispers(10)
    if pop.countFs then
        if unreadTotal > 0 then
            pop.countFs:SetText("|cff4ade80" .. tostring(unreadTotal) .. " " .. L["Unread"] .. "|r")
        elseif #list > 0 then
            pop.countFs:SetText("|cff9da7b5" .. tostring(#list) .. "|r")
        else
            pop.countFs:SetText("")
        end
    end
    if pop.emptyFs then
        pop.emptyFs:SetShown(#list == 0)
    end

    for i = 1, 10 do
        local row = pop.rows[i]
        local entry = list[i]
        if row and entry then
            row._entry = entry
            local isCur = (entry.key == self.activeKey)
            local dispTitle = tostring(entry.title or entry.key or "?")
            if streamerOn and (entry.kind == "BN_WHISPER" or dispTitle:find("#", 1, true)) and Compat.MaskStreamerBNetName then
                dispTitle = Compat.MaskStreamerBNetName(dispTitle)
            end
            local toneKey = (Theme and Theme.GetChatToneForKind) and Theme:GetChatToneForKind(entry.kind) or "whisper"
            local spec = (Theme and Theme.GetChatToneSpec) and Theme:GetChatToneSpec(toneKey)
            local hex = (entry.classFile and Compat and Compat.ClassHex) and Compat.ClassHex(entry.classFile) or (spec and spec.hex) or "|cffffffff"
            local isMuted = (ns.Chat and ns.Chat.IsThreadMuted and ns.Chat:IsThreadMuted(entry.key) == true)
            local muteTag = isMuted and ("|T" .. ICON_BELL_OFF .. ":11:11:0:-1|t ") or ""
            local unreadNum = (not isMuted) and (tonumber(entry.unread) or 0) or 0
            local unreadTag = (unreadNum > 0) and (" |cff4ade80[" .. tostring(unreadNum) .. "]|r") or ""
            row.nameFs:SetText(muteTag .. hex .. dispTitle .. "|r" .. unreadTag)

            local rawClean = tostring(entry.preview or "")
                :gsub("|c%x%x%x%x%x%x%x%x|H.-|h(.-)|h|r", "%1")
                :gsub("|H.-|h(.-)|h", "%1")
                :gsub("|c%x%x%x%x%x%x%x%x", "")
                :gsub("|r", "")
                :gsub("|T.-|t", "")
                :gsub("|A.-|a", "")
                :gsub("[%c]+", " ")
                :gsub("%s+", " ")
                :match("^%s*(.-)%s*$") or ""
            local relTxt = (entry.lastAt and entry.lastAt > 0 and Compat and Compat.FormatRelativeTime)
                and Compat.FormatRelativeTime(entry.lastAt, L)
                or ""
            local snipMax = (relTxt ~= "") and 14 or 22
            local snip = self:TruncateUtf8(rawClean, snipMax)
            local fullTip = self:TruncateUtf8(rawClean, 180)
            if streamerOn then
                snip = ""
                fullTip = L["[Hidden in Streamer Mode]"]
            end
            if relTxt ~= "" and snip ~= "" then
                row.snipFs:SetText("|cff8b949e" .. snip .. "|r |cff6e7681· " .. relTxt .. "|r")
            elseif relTxt ~= "" then
                row.snipFs:SetText("|cff6e7681" .. relTxt .. "|r")
            elseif snip ~= "" then
                row.snipFs:SetText("|cff8b949e" .. snip .. "|r")
            else
                row.snipFs:SetText("")
            end
            row._tipTitle = hex .. dispTitle .. "|r" .. ((unreadNum > 0) and (" |cff4ade80(" .. tostring(unreadNum) .. ")|r") or "")
            row._tipSub = fullTip

            if isCur then
                row.bg:SetColorTexture(0.22, 0.36, 0.24, 0.55)
            elseif i % 2 == 1 then
                row.bg:SetColorTexture(1.0, 1.0, 1.0, 0.04)
            else
                row.bg:SetColorTexture(0.0, 0.0, 0.0, 0.16)
            end
            row:Show()
        elseif row then
            row._entry = nil
            row:Hide()
        end
    end

    local popW = 292
    local popH = (#list > 0) and (28 + (#list * 27) + 34) or 94
    pop:SetSize(popW, popH)

    local openUp = self:ShouldWhispersDropdownOpenUp()
    local uiH = (_G.UIParent and _G.UIParent.GetHeight and _G.UIParent:GetHeight()) or 768
    local aTop = (anchorBtn and anchorBtn.GetTop and anchorBtn:GetTop()) or (uiH * 0.5)
    local aBot = (anchorBtn and anchorBtn.GetBottom and anchorBtn:GetBottom()) or (uiH * 0.5)
    if openUp and (aTop + popH + 8) > uiH and (aBot - popH - 8) >= 4 then
        openUp = false
    elseif (not openUp) and (aBot - popH - 8) < 4 and (aTop + popH + 8) <= uiH then
        openUp = true
    end

    pop:ClearAllPoints()
    if openUp then
        pop:SetPoint("BOTTOMRIGHT", anchorBtn or self.frame, "TOPRIGHT", 0, 4)
    else
        pop:SetPoint("TOPRIGHT", anchorBtn or self.frame, "BOTTOMRIGHT", 0, -4)
    end
    pop:SetFrameStrata("FULLSCREEN_DIALOG")
    pop:SetFrameLevel(860)
    pop:Show()
    if pop.Raise then
        pop:Raise()
    end
    if Theme and Theme.SyncSubtreeLayers then
        Theme:SyncSubtreeLayers(pop, 10)
    end
    self.interactedOutside = false
    self.lastInputAt = GetTime()
    self.idleCountdown = nil
    self:UpdateWhispersButton()
end

function QuickReply:EnsureChipButton(idx)
    local f = self.frame
    if not (f and f.chipsBar and ns.Theme) then
        return nil
    end
    f.chips = f.chips or {}
    if f.chips[idx] then
        return f.chips[idx]
    end
    local cBtn = ns.Theme:CreateButton(f.chipsBar, 64, 19, "", "default")
    cBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    local chipTone = cBtn:CreateTexture(nil, "OVERLAY", nil, 3)
    chipTone:SetHeight(2)
    chipTone:SetPoint("BOTTOMLEFT", cBtn, "BOTTOMLEFT", 2, 1)
    chipTone:SetPoint("BOTTOMRIGHT", cBtn, "BOTTOMRIGHT", -2, 1)
    chipTone:SetTexture(MP_WHITE8X8)
    chipTone:SetVertexColor(0.55, 0.65, 0.78, 0.35)
    cBtn._toneRule = chipTone
    local pinRule = cBtn:CreateTexture(nil, "OVERLAY", nil, 3)
    pinRule:SetHeight(2)
    pinRule:SetWidth(12)
    pinRule:SetPoint("TOP", cBtn, "TOP", 0, -1)
    pinRule:SetTexture(MP_WHITE8X8)
    pinRule:SetVertexColor(1.0, 0.82, 0.25, 0.85)
    pinRule:Hide()
    cBtn._pinRule = pinRule
    cBtn:Hide()
    cBtn:SetScript("OnClick", function(selfBtn, mouseBtn)
        if mouseBtn == "RightButton" and selfBtn._threadKey then
            OpenQuickReplyPinsMenu(selfBtn, selfBtn._threadKey, selfBtn._fullChipTitle)
            return
        end
        if mouseBtn == "MiddleButton" and selfBtn._threadKey and ns.Chat then
            if (selfBtn._chipUnread or 0) > 0 and ns.Chat.MarkThreadRead then
                ns.Chat:MarkThreadRead(selfBtn._threadKey)
            elseif selfBtn._chipHasDraft and ns.Chat.SetQuickReplyDraft then
                ns.Chat:SetQuickReplyDraft(selfBtn._threadKey, "")
                if QuickReply.activeKey == selfBtn._threadKey and QuickReply.frame and QuickReply.frame.inputBox then
                    QuickReply.suppressDraftSave = true
                    QuickReply.frame.inputBox:SetText("")
                    QuickReply.suppressDraftSave = false
                end
            end
            UpdateBadge(false)
            QuickReply:Refresh()
            return
        end
        if selfBtn._threadKey then
            QuickReply._manualTabSwitchKey = selfBtn._threadKey
            QuickReply:SaveCurrentDraft()
            QuickReply:SelectThread(selfBtn._threadKey, false)
        end
    end)
    cBtn:SetScript("OnEnter", function(selfBtn)
        if not (GameTooltip and selfBtn._fullChipTitle) then
            return
        end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(selfBtn._fullChipTitle, 1.0, 0.85, 0.25, true)
        if selfBtn._chipMuted and ns.Chat and ns.Chat.FormatThreadMuteStatus and selfBtn._threadKey then
            local mTxt = ns.Chat:FormatThreadMuteStatus(selfBtn._threadKey)
            if mTxt then
                GameTooltip:AddLine(mTxt, 0.96, 0.58, 0.28, true)
            end
        end
        if selfBtn._threadKey == "ch:general" then
            GameTooltip:AddLine(L["Always fixed first tab: Say, Yell, Emotes, World, Loot & Public Channels (/1, /2, /3...) · Right-click to choose send channel or filter which notifications appear."], 0.65, 0.72, 0.82, true)
        elseif selfBtn._threadKey == "notes:self" then
            GameTooltip:AddLine(L["Saved privately on this character · Never sent to chat"], 0.65, 0.72, 0.82, true)
        elseif selfBtn._threadKey == "mentions:radar" then
            GameTooltip:AddLine(L["Your name & monitored keywords across chat"], 0.65, 0.72, 0.82, true)
            GameTooltip:AddLine(L["Click a sender name above to reply, or click 'Keywords' to configure."], 0.45, 0.85, 1.0, true)
        else
            if selfBtn._chipUnread and selfBtn._chipUnread > 0 then
                GameTooltip:AddLine(L["%d unread"]:format(selfBtn._chipUnread), 0.45, 0.85, 1.0)
            elseif selfBtn._chipHasDraft then
                GameTooltip:AddLine(L["Draft saved"], 1.0, 0.84, 0.30)
            elseif selfBtn._chipPinned then
                GameTooltip:AddLine(L["Pinned in Quick Reply"], 1.0, 0.84, 0.30)
            end
            GameTooltip:AddLine(L["Right-click: Silence, pin or close tab · Middle-click: Clear unread/draft"], 0.65, 0.72, 0.82, true)
        end
        GameTooltip:Show()
    end)
    cBtn:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then
            GameTooltip:Hide()
        end
    end)
    f.chips[idx] = cBtn
    return cBtn
end

function QuickReply:ApplyTheme()
    local f = self.frame
    if not f or not ns.Theme then return end
    local p = ns.Theme:GetPalette()
    if f._solidOpaqueBg then
        local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
        f._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
    end
    ns.Theme:ApplyBackdrop(f, "window", p)
    ns.Theme:ApplyBackdrop(f.header, "header", p)
    if f.infoBar then
        ns.Theme:ApplyBackdrop(f.infoBar, "surface", p)
    end
    if f.msgBg then
        ns.Theme:ApplyBackdrop(f.msgBg, "inset", p)
    end
    if f.msgFrame and f.msgBg and f.msgFrame.SetFrameLevel then
        f.msgFrame:SetFrameLevel((f.msgBg:GetFrameLevel() or 2) + 2)
    end
    if f.stickyHeader and f.msgBg and f.stickyHeader.SetFrameLevel then
        f.stickyHeader:SetFrameLevel((f.msgBg:GetFrameLevel() or 2) + 4)
        self:SyncStickySectionHeader(f, p)
    end
    if f.inlineNotice then
        ns.Theme:ApplyBackdrop(f.inlineNotice, "surface", p)
        if f.inlineNotice.SetBackdropBorderColor then
            f.inlineNotice:SetBackdropBorderColor(0.95, 0.42, 0.30, 0.95)
        end
        if f.inlineNotice._solidBg then
            local sBg = (p and p.surfaceBg) or { 0.11, 0.10, 0.10, 1.0 }
            f.inlineNotice._solidBg:SetVertexColor(sBg[1], sBg[2], sBg[3], 1.0)
        end
    end
    if f.inputWrap then
        ns.Theme:ApplyBackdrop(f.inputWrap, "inset", p)
        if f.inputWrap._solidBg then
            local inBg = (p and p.inputBg) or { 0.03, 0.03, 0.04, 1.0 }
            f.inputWrap._solidBg:SetVertexColor(inBg[1], inBg[2], inBg[3], 1.0)
        end
    end
    if f.btnAutoClose then
        ns.Theme:StyleButton(f.btnAutoClose, "default")
    end
    ns.Theme:StyleButton(f.btnInvite, "default")
    ns.Theme:StyleButton(f.btnWatch, "default")
    if f.btnLock then
        ns.Theme:StyleButton(f.btnLock, "default")
        self:ApplyLockState()
    end
    if f.btnDock then
        ns.Theme:StyleButton(f.btnDock, "default")
        self:UpdateDockButton()
    end
    if f.btnExpand then
        ns.Theme:StyleButton(f.btnExpand, "default")
    end
    if f.btnHistory then
        ns.Theme:StyleButton(f.btnHistory, "default")
    end
    if f.btnCombatLog then
        ns.Theme:StyleButton(f.btnCombatLog, "default")
    end
    self:ApplyCombatLogTheme()
    if f.btnHelp and ns.Theme then
        if f.btnHelp.RefreshTheme then
            f.btnHelp:RefreshTheme()
        else
            ns.Theme:StyleButton(f.btnHelp, "ghost")
        end
    end
    if f.btnMute then
        ns.Theme:StyleButton(f.btnMute, "default")
    end
    if f.btnMentionCfg then
        ns.Theme:StyleButton(f.btnMentionCfg, "primary")
    end
    ns.Theme:StyleButton(f.btnClose, "default")
    if f.btnScrollBottom then
        ns.Theme:StyleButton(f.btnScrollBottom, "default")
    end
    self._lastHeaderToneR = nil
    ns.Theme:StyleButton(f.btnSend, "primary")
    if f.btnAllQuickReplies then
        ns.Theme:StyleButton(f.btnAllQuickReplies, "default")
    end
    if f.btnNewChat then
        ns.Theme:StyleButton(f.btnNewChat, "default")
    end
    if f.btnHeaderUnread then
        ns.Theme:StyleButton(f.btnHeaderUnread, "default")
    end
    if f.btnGenChannel then
        ns.Theme:StyleButton(f.btnGenChannel, "default")
    end
    if f.btnGenFilter then
        ns.Theme:StyleButton(f.btnGenFilter, "default")
    end
    if f.btnMsgSearch then
        ns.Theme:StyleButton(f.btnMsgSearch, "default")
    end
    if f.btnThreadOpts then
        ns.Theme:StyleButton(f.btnThreadOpts, "default")
    end
    if f.btnCard then
        ns.Theme:StyleButton(f.btnCard, "default")
    end
    if f.msgSearchBar then
        ns.Theme:ApplyBackdrop(f.msgSearchBar, "surface", p)
        if f.msgSearchBox and ns.Theme.StyleEditBox then
            ns.Theme:StyleEditBox(f.msgSearchBox)
        end
        if f.msgSearchCloseBtn then
            ns.Theme:StyleButton(f.msgSearchCloseBtn, "default")
        end
    end
    if f.msgEmptyLabel and p and p.textMuted then
        f.msgEmptyLabel:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3], 0.85)
    end
    if f.hdrSep1 then
        local sepCol = (p and p.border) or { 0.45, 0.42, 0.36 }
        f.hdrSep1:SetVertexColor(sepCol[1] or 0.45, sepCol[2] or 0.42, sepCol[3] or 0.36, 0.45)
    end
    if f.hdrSep2 then
        local sepCol = (p and p.border) or { 0.45, 0.42, 0.36 }
        f.hdrSep2:SetVertexColor(sepCol[1] or 0.45, sepCol[2] or 0.42, sepCol[3] or 0.36, 0.45)
    end
    if f.btnWhispers then
        self:UpdateWhispersButton()
    end
    if self:IsWhispersDropdownShown() then
        local wp = self._whispersDropdown
        if wp._solidOpaqueBg then
            local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
            wp._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
        end
        ns.Theme:ApplyBackdrop(wp, "window", p)
        if wp.titleFs and p then
            local gc = p.textGold or p.accent or { 1.0, 0.85, 0.30 }
            wp.titleFs:SetTextColor(gc[1], gc[2], gc[3])
        end
        if wp.openAllBtn then
            ns.Theme:StyleButton(wp.openAllBtn, "default")
        end
    end
    if self._closeConfirmModal and self._closeConfirmModal:IsShown() then
        local cm = self._closeConfirmModal
        ns.Theme:ApplyBackdrop(cm, "window", p)
        if cm._solidOpaqueBg then
            local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
            cm._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
        end
        if cm.closeBtn then ns.Theme:StyleButton(cm.closeBtn, "default") end
        if cm.confirmBtn then ns.Theme:StyleButton(cm.confirmBtn, "primary") end
        if cm.cancelBtn then ns.Theme:StyleButton(cm.cancelBtn, "default") end
        if cm.helpBtn and cm.helpBtn.RefreshTheme then cm.helpBtn:RefreshTheme() end
    end
    if self._configModal and self._configModal.ApplyTheme then
        self._configModal:ApplyTheme()
    end
    if f.chipsPrevBtn then
        ns.Theme:StyleButton(f.chipsPrevBtn, "default")
    end
    if f.chipsNextBtn then
        ns.Theme:StyleButton(f.chipsNextBtn, "default")
    end
    if f.pingBtns then
        for _, pBtn in ipairs(f.pingBtns) do
            ns.Theme:StyleButton(pBtn, "default")
        end
    end
    if f.chips then
        for _, cBtn in ipairs(f.chips) do
            ns.Theme:StyleButton(cBtn, "default")
        end
    end
    self:InvalidateFocusVisuals()
    self:UpdateFocusVisuals()
    if self.tutorialDialog and self.tutorialDialog.ApplyTheme then
        self.tutorialDialog:ApplyTheme()
    end
end

local QUICK_REPLY_TUTORIAL_STEPS = {
    {
        titleKey = "Colors & ENTER",
        target = "frame",
        badgesKey = "TOUR_COLOR_BADGES",
        captionKey = "Border color = active chat. Click tabs freely; press ENTER or click the box to type. Sending releases focus.",
    },
    {
        titleKey = "General & Channels",
        target = "tabs",
        badgesKey = "TOUR_TABS_BADGES",
        captionKey = "General combines /s, /y, loot & channels. Click the Channel or Filters buttons on the header (or right-click) anytime.",
    },
    {
        titleKey = "Quick Replies & Links",
        target = "input",
        badgesKey = "TOUR_INPUT_BADGES",
        captionKey = "Click '...' for custom phrases & macros. Shift+Click links items · Ctrl+Click previews.",
    },
    {
        titleKey = "Lock & Position",
        target = "frame",
        badgesKey = "TOUR_FOCUS_BADGES",
        captionKey = "Padlock locks or enables edge resize. Map icon snaps cleanly over Official Chat.",
    },
    {
        titleKey = "Header Controls",
        target = "auto_close",
        badgesKey = "TOUR_HEADER_BADGES",
        captionKey = "+: New Chat · Swords: Logs · Clock: History · Search & Options on the bar · Timer: idle fade & combat hide.",
    },
}

local function FormatQuickReplyTourBadges(badgesKey)
    if badgesKey == "TOUR_COLOR_BADGES" then
        return "|cffc8dcfa" .. L["General"] .. "|r  ·  |cffff7fff" .. L["Whisper"] .. "|r  ·  |cff7aaeff" .. L["Group"] .. "|r  ·  |cffff8a2e" .. L["Raid"] .. "|r  ·  |cff47ef66" .. L["Guild"] .. "|r  ·  |cff1ad1ffBNet|r  ·  |cffbd80ff" .. L["Private Rooms"] .. "|r  ·  |cffffffff" .. L["Say"] .. "|r  ·  |cffff4d4d" .. L["Yell"] .. "|r"
    elseif badgesKey == "TOUR_TABS_BADGES" then
        return "|cffc8dcfa[" .. L["General"] .. " #1]|r   ·   |cffffd24d[Tab / Shift+Tab]|r   ·   |cff58a6ff[" .. L["Right-Click Tab"] .. "]|r"
    elseif badgesKey == "TOUR_INPUT_BADGES" then
        return "|cff3fb950[Enter]|r " .. L["Send"] .. "   ·   |cff58a6ff[Shift+Click]|r " .. L["Link Item"] .. "   ·   |cffff9f40[Ctrl+Click]|r " .. L["Try On"] .. "   ·   |cffffd24d[... " .. L["Quick Replies"] .. "]|r"
    elseif badgesKey == "TOUR_FOCUS_BADGES" then
        local onTex = (FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online")
        local offTex = (FRIENDS_TEXTURE_OFFLINE or "Interface\\FriendsFrame\\StatusIcon-Offline")
        return "|T" .. onTex .. ":12:12:0:0|t |cff3fb950" .. L["Lit = Typing"] .. "|r    |T" .. offTex .. ":12:12:0:0|t |cff8b949e" .. L["Dark = Game Keys Free"] .. "|r"
    elseif badgesKey == "TOUR_HEADER_BADGES" then
        local fadeEn, fadeSec = QuickReply:GetFadeDelaySettings()
        local fadeLbl = fadeEn and L["Transparent: %ds"]:format(fadeSec or 15) or L["Always Open (Opaque)"]
        return "|cffff9f40[" .. L["Combat Log"] .. "]|r   ·   |cffffd24d[" .. L["Padlock / Map"] .. "]|r   ·   |cff3fb950[" .. fadeLbl .. "]|r"
    end
    return ""
end

local function MarkQuickReplyTutorialDone()
    if ns.SetAccountTutorialShown then
        ns:SetAccountTutorialShown("quickReplyTutorialShown", true)
    elseif ns.db and ns.db.settings then
        ns.db.settings.quickReplyTutorialShown = true
    end
end

local function IsQuickReplyTutorialDone()
    if ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("quickReplyTutorialShown") then
        return true
    end
    if ns.db and ns.db.settings and ns.db.settings.quickReplyTutorialShown == true then
        return true
    end
    return false
end

local function ResolveQuickReplyTourTarget(targetKind)
    local qr = QuickReply.frame
    if not (qr and qr:IsShown()) then
        return nil
    end
    if targetKind == "tabs" then
        return (qr.chipsBar and qr.chipsBar:IsShown()) and qr.chipsBar or qr.infoBar
    elseif targetKind == "input" then
        local dockedSkin = QuickReply._activeDockedSkinEb and QuickReply._activeDockedSkinEb._scDockedSkin
        local inputTarget = (dockedSkin and dockedSkin:IsShown()) and dockedSkin or (qr.inputWrap and qr.inputWrap:IsShown() and qr.inputWrap) or qr.inputBox
        return { qr.quickPingsBar, inputTarget }
    elseif targetKind == "auto_close" then
        return { qr.btnAutoClose, qr.btnNewChat, qr.btnCombatLog, qr.btnHistory, qr.btnExpand, qr.btnDock, qr.btnLock, qr.btnHelp }
    end
    return qr
end

function QuickReply:ShowTutorial(forceShow)
    if (not forceShow) and IsQuickReplyTutorialDone() then
        return
    end
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        if not forceShow then
            self.pendingTutorial = true
        end
        return
    end
    self.pendingTutorial = false
    if not (ns.Theme and ns.Theme.ShowNpcGuide) then
        return
    end
    if not forceShow then
        MarkQuickReplyTutorialDone()
    end

    local guideSteps = {}
    for _, st in ipairs(QUICK_REPLY_TUTORIAL_STEPS) do
        local badgesTxt = FormatQuickReplyTourBadges(st.badgesKey)
        local bodyTxt = (badgesTxt ~= "" and (badgesTxt .. "\n\n") or "") .. (L[st.captionKey] or st.captionKey)
        local tgtKind = st.target
        guideSteps[#guideSteps + 1] = {
            title = L[st.titleKey] or st.titleKey,
            text = bodyTxt,
            target = function()
                return ResolveQuickReplyTourTarget(tgtKind)
            end,
        }
    end

    self.tutorialDialog = ns.Theme:ShowNpcGuide({
        key = "quick_reply",
        doneLabel = L["Got it!"],
        steps = guideSteps,
        isAnchorVisible = function()
            return QuickReply.frame ~= nil and QuickReply.frame:IsShown() == true
        end,
        onComplete = MarkQuickReplyTutorialDone,
        onClose = function()
            MarkQuickReplyTutorialDone()
            if QuickReply.frame and QuickReply.frame:IsShown() then
                QuickReply:ReleaseKeyboardFocus(true)
                if QuickReply.SyncEnterBinding then
                    QuickReply:SyncEnterBinding()
                end
            end
            QuickReply:UpdateFocusVisuals()
        end,
    })
end

function QuickReply:ShowTutorialIfNeeded()
    if IsQuickReplyTutorialDone() then
        return
    end
    if ns.Theme and ns.Theme.PromptWindowTutorial then
        local guideSteps = {}
        for _, st in ipairs(QUICK_REPLY_TUTORIAL_STEPS) do
            local badgesTxt = FormatQuickReplyTourBadges(st.badgesKey)
            local bodyTxt = (badgesTxt ~= "" and (badgesTxt .. "\n\n") or "") .. (L[st.captionKey] or st.captionKey)
            local tgtKind = st.target
            guideSteps[#guideSteps + 1] = {
                title = L[st.titleKey] or st.titleKey,
                text = bodyTxt,
                target = function()
                    return ResolveQuickReplyTourTarget(tgtKind)
                end,
            }
        end
        ns.Theme:PromptWindowTutorial({
            tutorialKey = "quickReplyTutorialShown",
            title = L["Quick Reply"],
            guideSpec = {
                key = "quick_reply",
                doneLabel = L["Got it!"],
                steps = guideSteps,
                isAnchorVisible = function()
                    return QuickReply.frame ~= nil and QuickReply.frame:IsShown() == true
                end,
                onComplete = MarkQuickReplyTutorialDone,
                onClose = function()
                    MarkQuickReplyTutorialDone()
                    if QuickReply.frame and QuickReply.frame:IsShown() then
                        QuickReply:ReleaseKeyboardFocus(true)
                        if QuickReply.SyncEnterBinding then
                            QuickReply:SyncEnterBinding()
                        end
                    end
                    QuickReply:UpdateFocusVisuals()
                end,
            },
            isWindowVisible = function()
                return QuickReply.frame ~= nil and QuickReply.frame:IsShown() == true
            end,
            onSkip = MarkQuickReplyTutorialDone,
        })
        return
    end
    self:ShowTutorial(false)
end

local function PushQuickReplyHistory(text)
    if type(text) ~= "string" or text == "" then return end
    QuickReply.sentHistory = QuickReply.sentHistory or {}
    local hist = QuickReply.sentHistory
    if hist[#hist] ~= text then
        hist[#hist + 1] = text
        if #hist > 25 then
            table.remove(hist, 1)
        end
    end
    if ns.Chat and ns.Chat.RecordSentInputHistory then
        ns.Chat:RecordSentInputHistory(text)
    end
    QuickReply.historyIdx = nil
    QuickReply._historyDraft = nil
end

function QuickReply:PushHistoryLine(text)
    PushQuickReplyHistory(text)
end

function QuickReply:ClearDraftAndInput()
    local f = self.frame
    self.suppressDraftSave = true
    if f and f.inputBox then
        f.inputBox:SetText("")
    end
    self.suppressDraftSave = false
    if self.activeKey and ns.Chat and ns.Chat.SetQuickReplyDraft then
        ns.Chat:SetQuickReplyDraft(self.activeKey, "")
    end
    self.hasTyped = false
    self.lastInputAt = GetTime()
    self.idleCountdown = nil
    self.lastStatusState = ""
end

function QuickReply:ShowInlineNotice(msgText)
    local f = self.frame
    if not (f and f.inlineNotice and f.inlineNotice._txt) then
        if msgText and msgText ~= "" then
            ns:Print("%s", msgText)
        end
        return
    end
    local notice = f.inlineNotice
    notice._seq = (notice._seq or 0) + 1
    local seq = notice._seq
    notice._txt:SetText(msgText or "")
    local p = ns.Theme and ns.Theme.GetPalette and ns.Theme:GetPalette() or nil
    if ns.Theme and ns.Theme.ApplyBackdrop then
        ns.Theme:ApplyBackdrop(notice, "surface", p)
    end
    if notice.SetBackdropBorderColor then
        notice:SetBackdropBorderColor(0.95, 0.42, 0.30, 0.95)
    end
    if notice._solidBg then
        local sBg = (p and p.surfaceBg) or { 0.11, 0.10, 0.10, 1.0 }
        notice._solidBg:SetVertexColor(sBg[1], sBg[2], sBg[3], 1.0)
    end
    if f.msgFrame then
        notice:SetFrameLevel((f.msgFrame:GetFrameLevel() or 2) + 8)
    end
    notice:Show()
    if notice.Raise then notice:Raise() end
    if C_Timer and C_Timer.After then
        C_Timer.After(3.2, function()
            if f.inlineNotice and f.inlineNotice._seq == seq then
                f.inlineNotice:Hide()
            end
        end)
    end
end

function QuickReply:SendInstantReply(rawMsg)
    if not self.activeKey or not ns.Chat then return false end
    local clean = ns.Compat and ns.Compat.Trim and ns.Compat.Trim(rawMsg) or rawMsg
    if not clean or clean == "" then return false end
    local sent, sendMode = ns.Chat:SendOrOpenReply(self.activeKey, clean, true)
    if sent == false and sendMode == "not_in_group" then
        self:ClearDraftAndInput()
        self:Refresh()
        self:ShowInlineNotice(L["There is no active group at the moment."])
        return false
    end
    if sent ~= false then
        PushQuickReplyHistory(clean)
        if ns.Chat.MarkThreadRead then
            ns.Chat:MarkThreadRead(self.activeKey)
        end
        self.hasSentInSession = true
        self.interactedOutside = false
        self.lastInputAt = GetTime()
        self.idleCountdown = nil
        self.lastStatusState = ""
        local blizzActive = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
            or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
            or nil
        if blizzActive and blizzActive.HasFocus and blizzActive:HasFocus() then
            self:Refresh()
            self:ShowActiveOfficialEditBox(blizzActive)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if blizzActive and blizzActive.HasFocus and blizzActive:HasFocus()
                        and QuickReply.frame and QuickReply.frame:IsShown()
                    then
                        QuickReply:ShowActiveOfficialEditBox(blizzActive)
                    end
                end)
            end
            if sendMode == "prefilled" and self.frame and self.frame.statusText then
                self.lastStatusState = "blizz_confirm"
                self.frame.statusText:SetText("|cff7aaeff" .. L["Press Enter in Official Chat"] .. "|r")
                if self.frame._syncTitleRightFn then self.frame._syncTitleRightFn(self.frame) end
            end
        else
            self:Refresh()
            self:ReleaseKeyboardFocus(false)
            if self.SyncEnterBinding then
                self:SyncEnterBinding()
            end
        end
        UpdateBadge(false)
        return true
    end
    return false
end

local function BuildQuickReplyPingsBar(f, Theme)
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 32)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 32)
    bar:SetHeight(19)
    f.quickPingsBar = bar

    local btnAll = Theme:CreateButton(bar, 24, 19, "...", "default")
    btnAll:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    btnAll:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["Quick Replies"], 1.0, 0.85, 0.25)
        GameTooltip:AddLine(L["Send a saved message in 1 click or save the current text as a new template."], 0.85, 0.88, 0.92, true)
        GameTooltip:Show()
    end)
    btnAll:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    btnAll:SetScript("OnClick", function(selfBtn)
        if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Chat) then return end
        local curKey = QuickReply.activeKey
        local ctxId = ns.Chat.ResolveQuickReplyContext and ns.Chat:ResolveQuickReplyContext(curKey) or "whisper"
        local list = ns.Chat.GetQuickReplies and ns.Chat:GetQuickReplies(curKey) or {}
        local curTxt = (ns.Compat and ns.Compat.CleanInput and f.inputBox) and ns.Compat.CleanInput(f.inputBox:GetText() or "") or ""
        QuickReply._ownMenuOpen = true
        QuickReply._menuActionPicked = false
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            local ctxTitle = L["Quick Replies"]
            if ns.Chat.GetQuickReplyContexts then
                for _, c in ipairs(ns.Chat:GetQuickReplyContexts()) do
                    if c.id == ctxId then
                        ctxTitle = L["Quick Replies"] .. " — " .. c.label
                        break
                    end
                end
            end
            root:CreateTitle(ctxTitle)
            for _, tpl in ipairs(list) do
                local exp = (ns.Chat.ExpandQuickReplyText and ns.Chat:ExpandQuickReplyText(tpl)) or tpl
                root:CreateButton(exp, function()
                    QuickReply._menuActionPicked = true
                    QuickReply:SendInstantReply(exp)
                end)
            end
            if ns.Chat.GetPortalDestinationsForPlayer then
                local portals = ns.Chat:GetPortalDestinationsForPlayer()
                if #portals > 0 then
                    root:CreateDivider()
                    local pSub = root:CreateButton(L["Portal Requests (City)"])
                    for _, pt in ipairs(portals) do
                        pSub:CreateButton(pt.text, function()
                            QuickReply._menuActionPicked = true
                            QuickReply:SendInstantReply(pt.text)
                        end)
                    end
                end
            end
            if ns.Chat.GetJoinedOfficialChannels then
                local pubList = ns.Chat:GetJoinedOfficialChannels()
                local chSub = root:CreateButton(L["Switch Channel inside General (/s, /y, /1, /2, /3...)"])
                chSub:CreateButton("/s · " .. L["Say"], function()
                    QuickReply._menuActionPicked = true
                    if ns.Chat.SetGeneralTargetChannel then ns.Chat:SetGeneralTargetChannel(nil) end
                    QuickReply:SaveCurrentDraft()
                    QuickReply:OpenThread("ch:general", false)
                end)
                chSub:CreateButton("/y · " .. L["Yell"], function()
                    QuickReply._menuActionPicked = true
                    if ns.Chat.SetGeneralTargetChannel then ns.Chat:SetGeneralTargetChannel("yell") end
                    QuickReply:SaveCurrentDraft()
                    QuickReply:OpenThread("ch:general", false)
                end)
                for _, ch in ipairs(pubList) do
                    chSub:CreateButton("/" .. tostring(ch.id) .. " · " .. ch.name, function()
                        QuickReply._menuActionPicked = true
                        if ns.Chat.SetGeneralTargetChannel then
                            ns.Chat:SetGeneralTargetChannel(ch.id)
                        end
                        QuickReply:SaveCurrentDraft()
                        QuickReply:OpenThread("ch:general", false)
                    end)
                end
            end
            if ns.Chat.GetCategorizedQuickReplies then
                root:CreateDivider()
                for _, cat in ipairs(ns.Chat:GetCategorizedQuickReplies()) do
                    local cSub = root:CreateButton(cat.title)
                    for _, cTpl in ipairs(cat.items) do
                        local exp = (ns.Chat.ExpandQuickReplyText and ns.Chat:ExpandQuickReplyText(cTpl)) or cTpl
                        cSub:CreateButton(exp, function()
                            QuickReply._menuActionPicked = true
                            QuickReply:SendInstantReply(exp)
                        end)
                    end
                end
            end
            root:CreateDivider()
            if curTxt and curTxt ~= "" and ns.Chat.AddQuickReply then
                root:CreateButton("+ " .. L["Save current text as Quick Reply"], function()
                    QuickReply._menuActionPicked = true
                    ns.Chat:AddQuickReply(curTxt, curKey)
                    QuickReply:Refresh()
                end)
            end
            local pingsOn = (not ns.db or not ns.db.settings) or (ns.db.settings.quickReplyShowPingsBar ~= false)
            root:CreateButton(pingsOn and L["Hide Quick Replies Bar"] or L["Show Quick Replies Bar"], function()
                QuickReply._menuActionPicked = true
                if ns.db and ns.db.settings then
                    ns.db.settings.quickReplyShowPingsBar = not pingsOn
                end
                if ns.Emit then ns:Emit("SETTINGS_UPDATED") end
                QuickReply:Refresh()
            end)
            root:CreateButton(L["Customize Replies & Shortcuts..."], function()
                QuickReply._menuActionPicked = true
                if QuickReply.OpenConfigModal then
                    QuickReply:OpenConfigModal()
                end
            end)
        end)
    end)
    f.btnAllQuickReplies = btnAll

    f.pingBtns = {}
    for i = 1, 4 do
        local pBtn = Theme:CreateButton(bar, 88, 19, "", "default")
        pBtn:Hide()
        pBtn:SetScript("OnClick", function(selfBtn)
            if selfBtn._pingFullText then
                QuickReply:SendInstantReply(selfBtn._pingFullText)
            end
        end)
        pBtn:SetScript("OnEnter", function(selfBtn)
            if not (GameTooltip and selfBtn._pingFullText) then return end
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:SetText(L["Quick Replies"], 1.0, 0.85, 0.25)
            GameTooltip:AddLine(selfBtn._pingFullText, 0.92, 0.95, 0.98, true)
            GameTooltip:Show()
        end)
        pBtn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        f.pingBtns[i] = pBtn
    end
end

local function FitQuickPingLabel(pBtn, fullText, maxBtnW)
    local fs = pBtn and (pBtn.label or (pBtn.GetFontString and pBtn:GetFontString()) or pBtn._scLabel)
    local cand = tostring(fullText or ""):gsub("%s+$", "")
    if cand == "" then return nil, 0 end
    if fs and fs.SetText and ns.Theme and ns.Theme.MeasureTextWidth then
        fs:SetText(cand)
        pBtn._scMeasuredText = nil
        local rawW = math.ceil((ns.Theme:MeasureTextWidth(pBtn) or (#cand * 6.5)) + 14)
        if rawW <= maxBtnW then
            return cand, rawW
        end
        local trimmed = cand
        while true do
            local nextTrim = trimmed:match("^(.*)%s+[^%s]+$")
            if not nextTrim or nextTrim == "" then
                return nil, 0
            end
            trimmed = nextTrim
            if trimmed:find("%s") or #trimmed >= 10 then
                local disp = trimmed .. "..."
                fs:SetText(disp)
                pBtn._scMeasuredText = nil
                local testW = math.ceil((ns.Theme:MeasureTextWidth(pBtn) or (#disp * 6.5)) + 14)
                if testW <= maxBtnW then
                    return disp, testW
                end
            end
        end
    end
    ns.Theme:SetButtonText(pBtn, cand)
    local rawW = math.ceil(((fs and fs.GetStringWidth and fs:GetStringWidth()) or (#cand * 6.5)) + 14)
    if rawW <= maxBtnW then
        return cand, rawW
    end
    local trimmed = cand
    while true do
        local nextTrim = trimmed:match("^(.*)%s+[^%s]+$")
        if not nextTrim or nextTrim == "" then
            return nil, 0
        end
        trimmed = nextTrim
        if trimmed:find("%s") or #trimmed >= 10 then
            local disp = trimmed .. "..."
            ns.Theme:SetButtonText(pBtn, disp)
            local testW = math.ceil(((fs and fs.GetStringWidth and fs:GetStringWidth()) or (#disp * 6.5)) + 14)
            if testW <= maxBtnW then
                return disp, testW
            end
        end
    end
end

local function RefreshQuickReplyPingsBar(f, t)
    if not (f and f.quickPingsBar) then return end
    local showSetting = (not ns.db or not ns.db.settings) or (ns.db.settings.quickReplyShowPingsBar ~= false)
    local allowPings = showSetting and (t.kind ~= "NOTES" and t.kind ~= "MENTIONS")
    local numMsgPts = (f.msgBg and f.msgBg.GetNumPoints and f.msgBg:GetNumPoints()) or 0
    if f._lastPingBottomAllow ~= allowPings or numMsgPts < 2 then
        f._lastPingBottomAllow = allowPings
        f.quickPingsBar:SetShown(allowPings)
        if QuickReply.UpdateMsgBgAnchors then
            QuickReply:UpdateMsgBgAnchors(f)
        elseif f.msgBg then
            f.msgBg:ClearAllPoints()
            f.msgBg:SetPoint("TOPLEFT", f.chipsBar, "BOTTOMLEFT", 0, -3)
            f.msgBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, allowPings and 54 or 33)
            f._scMsgBgAnchorsReady = true
        end
    end
    if not allowPings then return end
    local list = (ns.Chat and ns.Chat.GetQuickReplies) and ns.Chat:GetQuickReplies(t and t.key or QuickReply.activeKey) or {}
    local availW = math.max(60, math.floor((f:GetWidth() or 430) - 12) - 28)
    local palKey = (ns.Theme and ns.Theme.GetPalette and ns.Theme:GetPalette().key) or "dark"
    local expandedList = f._qrExpandedPingScratch or {}
    f._qrExpandedPingScratch = expandedList
    local listCount = math.min(#list, 6)
    local cacheSame = (f._qrPingsAvailW == availW) and (f._qrPingsPalKey == palKey) and (f._qrPingsCount == listCount)
    for i = 1, listCount do
        local rawTpl = list[i]
        local exp = (rawTpl and rawTpl ~= "" and ns.Chat and ns.Chat.ExpandQuickReplyText) and ns.Chat:ExpandQuickReplyText(rawTpl) or rawTpl or ""
        if cacheSame and expandedList[i] ~= exp then
            cacheSame = false
        end
        expandedList[i] = exp
    end
    for i = listCount + 1, #expandedList do
        expandedList[i] = nil
    end
    if cacheSame then
        return
    end
    f._qrPingsAvailW = availW
    f._qrPingsPalKey = palKey
    f._qrPingsCount = listCount
    local cx = 0
    local btnIdx = 0
    for i = 1, listCount do
        if btnIdx >= #f.pingBtns then break end
        local expanded = expandedList[i]
        if expanded and expanded ~= "" then
            local remainingW = availW - cx
            if remainingW >= 54 then
                local pBtn = f.pingBtns[btnIdx + 1]
                local perCap = (availW < 360) and 140 or 185
                local disp, bw = FitQuickPingLabel(pBtn, expanded, math.min(perCap, remainingW))
                if disp and bw >= 44 and (cx + bw) <= availW then
                    btnIdx = btnIdx + 1
                    pBtn._pingFullText = expanded
                    ns.Theme:SetButtonText(pBtn, disp)
                    if math.abs((pBtn:GetWidth() or 0) - bw) >= 1 then
                        pBtn:SetWidth(bw)
                    end
                    pBtn:ClearAllPoints()
                    pBtn:SetPoint("LEFT", f.quickPingsBar, "LEFT", cx, 0)
                    pBtn:Show()
                    cx = cx + bw + 4
                end
            end
        end
    end
    for k = btnIdx + 1, #f.pingBtns do
        local pBtn = f.pingBtns[k]
        if pBtn then
            pBtn._pingFullText = nil
            pBtn:Hide()
        end
    end
end

local function OpenQuickReplyMessageActionsMenu(msgFrame, idx)
    local k = QuickReply.activeKey
    local t = k and ns.Chat and ns.Chat.threads and ns.Chat.threads[k]
    local msgs = (ns.Chat and ns.Chat.GetThreadMessages and ns.Chat:GetThreadMessages(k)) or (t and t.messages)
    local entry = idx and msgs and msgs[idx]
    if not (entry and MenuUtil and MenuUtil.CreateContextMenu) then return end
    local rawPlain = tostring(entry.text or ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    local senderLbl = entry.sender or (t and t.title) or "?"
    if ns.Compat and ns.Compat.IsStreamerMode and ns.Compat.IsStreamerMode()
        and ((t and t.kind == "BN_WHISPER") or tostring(senderLbl):find("#", 1, true))
        and ns.Compat.MaskStreamerBNetName
    then
        senderLbl = ns.Compat.MaskStreamerBNetName(senderLbl)
    end
    QuickReply._ownMenuOpen = true
    QuickReply._menuActionPicked = false
    MenuUtil.CreateContextMenu(msgFrame, function(_, root)
        root:CreateTitle(senderLbl)
        if not (t and t.kind == "MENTIONS") then
            root:CreateButton(L["Quote Reply"], function()
                QuickReply._menuActionPicked = true
                local snippet = QuickReply:TruncateUtf8(rawPlain, 45)
                local quote = string.format("> %s: \"%s\" ", senderLbl, snippet)
                if QuickReply:IsOfficialOnlyThread() then
                    QuickReply:ActivateDockedOfficialInput(quote)
                    return
                end
                local box = QuickReply.frame and QuickReply.frame.inputBox
                if not box then return end
                box:SetText(quote)
                if box.SetCursorPosition then box:SetCursorPosition(#quote) end
                QuickReply:FocusInputBox()
            end)
        end
        if k ~= "notes:self" and ns.Chat and ns.Chat.SavePersonalNote then
            root:CreateButton(L["Save to Personal Notes"], function()
                QuickReply._menuActionPicked = true
                ns.Chat:SavePersonalNote("[" .. senderLbl .. "] " .. rawPlain)
                ns:Print("%s", L["Saved to Personal Notes."])
            end)
        end
        root:CreateButton(L["Copy Message"], function()
            QuickReply._menuActionPicked = true
            if ns.UI and ns.UI.OpenCopyModal then
                ns.UI:OpenCopyModal(senderLbl .. ": " .. rawPlain, L["Copy Message"], L["Press Ctrl+C to copy this message."])
            end
        end)
    end)
end

local function OpenQuickReplySenderMenu(msgFrame, who)
    if not (who and who ~= "" and MenuUtil and MenuUtil.CreateContextMenu) then return end
    local parsed = ns.Compat and ns.Compat.ParseCharacterName and ns.Compat.ParseCharacterName(who)
    local cleanName = (parsed and parsed.displayName) or who
    local lk = (parsed and parsed.lookupKey) or cleanName:lower()
    QuickReply._ownMenuOpen = true
    QuickReply._menuActionPicked = false
    MenuUtil.CreateContextMenu(msgFrame, function(_, root)
        root:CreateTitle(cleanName)
        root:CreateButton(L["Whisper in Quick Reply"], function()
            QuickReply._menuActionPicked = true
            if ns.Chat and ns.Chat.EnsureWhisperThread then
                local wt = ns.Chat:EnsureWhisperThread(cleanName)
                if wt and wt.key then
                    QuickReply._manualTabSwitchKey = wt.key
                    QuickReply:SaveCurrentDraft()
                    QuickReply:SelectThread(wt.key, true)
                    return
                end
            end
            if ns.Compat and ns.Compat.Whisper then
                ns.Compat.Whisper(cleanName)
            end
        end)
        if not (ns.Compat and ns.Compat.IsMe and ns.Compat.IsMe(cleanName)) then
            root:CreateButton(L["Invite to Group"], function()
                QuickReply._menuActionPicked = true
                if ns.Compat and ns.Compat.Invite then
                    ns.Compat.Invite(cleanName)
                end
            end)
            if ns.Watchlist and ns.Watchlist.Add and not (ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(lk)) then
                root:CreateButton("+ " .. L["Watchlist"], function()
                    QuickReply._menuActionPicked = true
                    ns.Watchlist:Add(cleanName)
                    QuickReply:Refresh()
                end)
            end
            if ns.SocialPanels and ns.SocialPanels.OpenSocialMetaModal then
                root:CreateButton(L["Edit Social Card"], function()
                    QuickReply._menuActionPicked = true
                    ns.SocialPanels:OpenSocialMetaModal(cleanName, lk, { displayName = cleanName, lookupKey = lk })
                end)
            end
        end
        root:CreateButton(L["Copy Name"], function()
            QuickReply._menuActionPicked = true
            if ns.UI and ns.UI.OpenCopyModal then
                ns.UI:OpenCopyModal(cleanName, L["Copy Name"])
            end
        end)
    end)
end

local QUICK_REPLY_AUTOCLOSE_PRESETS = { 5, 10, 15, 20, 30, 45, 60 }
local QUICK_REPLY_FADE_PRESETS = { 5, 10, 15, 20, 30, 45, 60, 90, 120 }

local function ApplyQuickReplyFadeOption(enabled, delaySec)
    if not (ns.db and ns.db.settings) then
        return
    end
    ns.db.settings.quickReplyIdleFade = enabled and true or false
    if delaySec then
        ns.db.settings.quickReplyFadeDelay = delaySec
    end
    QuickReply._menuActionPicked = true
    QuickReply._lastOpaqueActivityAt = (GetTime and GetTime()) or 0
    QuickReply:UpdateAutoCloseButton()
    QuickReply:ApplyCombatFadeStep(0, true)
    if ns.Emit then
        ns:Emit("SETTINGS_UPDATED")
    end
end

local function ApplyQuickReplyAutoCloseOption(enabled, delaySec)
    if not (ns.db and ns.db.settings) then
        return
    end
    ns.db.settings.quickReplyAutoClose = enabled and true or false
    if delaySec then
        ns.db.settings.quickReplyAutoCloseDelay = delaySec
    end
    if not enabled then
        QuickReply._closedManuallyPersistent = false
    end
    QuickReply._menuActionPicked = true
    QuickReply.idleCountdown = nil
    QuickReply.lastStatusState = ""
    QuickReply:SyncEscapeCloseRegistration()
    QuickReply:UpdateAutoCloseButton()
    QuickReply:Refresh()
    if ns.Emit then
        ns:Emit("SETTINGS_UPDATED")
    end
end

local function OpenQuickReplyAutoCloseMenu(anchorBtn)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        return
    end
    QuickReply._ownMenuOpen = true
    QuickReply._menuActionPicked = false
    MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        root:CreateTitle(L["Transparency After Inactivity"])
        local addRadio = root.CreateRadio or root.CreateCheckbox
        for _, sec in ipairs(QUICK_REPLY_FADE_PRESETS) do
            local lbl = (sec == 15) and L["%d seconds (Default)"]:format(sec) or L["%d seconds"]:format(sec)
            if addRadio then
                addRadio(root, lbl, function()
                    local fEn, fSec = QuickReply:GetFadeDelaySettings()
                    return fEn and fSec == sec
                end, function()
                    ApplyQuickReplyFadeOption(true, sec)
                end)
            else
                root:CreateButton(lbl, function()
                    ApplyQuickReplyFadeOption(true, sec)
                end)
            end
        end
        local opaqueLbl = L["Never become transparent (always opaque)"]
        if addRadio then
            addRadio(root, opaqueLbl, function()
                local fEn = QuickReply:GetFadeDelaySettings()
                return not fEn
            end, function()
                ApplyQuickReplyFadeOption(false)
            end)
        else
            root:CreateButton(opaqueLbl, function()
                ApplyQuickReplyFadeOption(false)
            end)
        end
        root:CreateDivider()
        root:CreateTitle(L["Window Visibility & Auto-Close"])
        local keepOpenLbl = L["Always show Quick Reply (Default)"]
        if addRadio then
            addRadio(root, keepOpenLbl, function()
                local curEn = QuickReply:GetAutoCloseSettings()
                return not curEn
            end, function()
                ApplyQuickReplyAutoCloseOption(false)
            end)
        else
            root:CreateButton(keepOpenLbl, function()
                ApplyQuickReplyAutoCloseOption(false)
            end)
        end
        local autoSub = root:CreateButton(L["Auto-close after inactivity..."])
        if autoSub then
            local subRadio = autoSub.CreateRadio or autoSub.CreateCheckbox
            for _, sec in ipairs(QUICK_REPLY_AUTOCLOSE_PRESETS) do
                local lbl = (sec == 10) and L["%d seconds (Default)"]:format(sec) or L["%d seconds"]:format(sec)
                if subRadio then
                    subRadio(autoSub, lbl, function()
                        local curEn, curSec = QuickReply:GetAutoCloseSettings()
                        return curEn and curSec == sec
                    end, function()
                        ApplyQuickReplyAutoCloseOption(true, sec)
                    end)
                else
                    autoSub:CreateButton(lbl, function()
                        ApplyQuickReplyAutoCloseOption(true, sec)
                    end)
                end
            end
        end
        root:CreateDivider()
        root:CreateCheckbox(L["Hide Quick Reply during combat"], function()
            return (ns.db and ns.db.settings and ns.db.settings.quickReplyFadeInCombat == true) or false
        end, function()
            if ns.db and ns.db.settings then
                ns.db.settings.quickReplyFadeInCombat = not (ns.db.settings.quickReplyFadeInCombat == true)
                QuickReply._menuActionPicked = true
                QuickReply:ApplyCombatFadeStep(0, true)
                if ns.Emit then ns:Emit("SETTINGS_UPDATED") end
            end
        end)
        root:CreateCheckbox(L["Auto-open in Dungeons & Raids"], function()
            return not ns.db or not ns.db.settings or ns.db.settings.quickReplyDungeonAutoMode ~= false
        end, function()
            if ns.db and ns.db.settings then
                local nextVal = not (ns.db.settings.quickReplyDungeonAutoMode ~= false)
                ns.db.settings.quickReplyDungeonAutoMode = nextVal
                QuickReply._menuActionPicked = true
                if nextVal then
                    QuickReply._closedManuallyInDungeon = false
                end
                QuickReply:SyncInstanceAutoMode(nextVal)
                if ns.Emit then ns:Emit("SETTINGS_UPDATED") end
            end
        end)
        local s = ns.db and ns.db.settings
        local dockOn = (not s) or (s.quickReplyDockToChat ~= false)
        local hasSavedPos = ns.Theme and ns.Theme.HasSavedWindowPosition and ns.Theme:HasSavedWindowPosition("quickReply")
        if dockOn and hasSavedPos and ns.Theme.ResetWindowPosition then
            root:CreateDivider()
            root:CreateButton(L["Snap back to Official Chat"], function()
                QuickReply._menuActionPicked = true
                QuickReply._userDraggedThisOpen = false
                ns.Theme:ResetWindowPosition("quickReply", true)
                QuickReply:HideWhispersDropdown()
                QuickReply:SyncDockGeometry()
                QuickReply:UpdateWhispersButton()
            end)
        end
    end)
end

function QuickReply:AttachMsgFrameHandlers(f, msgFrame, Theme)
    if Theme and Theme.ShowHyperlinkTooltip then
        msgFrame:SetScript("OnHyperlinkEnter", function(selfMsg, link)
            Theme:ShowHyperlinkTooltip(selfMsg, link)
        end)
        msgFrame:SetScript("OnHyperlinkLeave", function(selfMsg)
            Theme:HideHyperlinkTooltip(selfMsg)
        end)
    end
    msgFrame:SetScript("OnHyperlinkClick", function(selfMsg, link, text, button)
        if type(link) ~= "string" then return end
        if link:find("addon:SCentral:url:", 1, true) then
            local encoded = link:match("addon:SCentral:url:([^|]+)")
            if encoded and encoded ~= "" and ns.UI and ns.UI.OpenCopyModal then
                local decoded = (ns.Chat and ns.Chat.DecodeUrlLink) and ns.Chat:DecodeUrlLink(encoded) or encoded
                ns.UI:OpenCopyModal(decoded, L["Copy Link"], L["Press Ctrl+C to copy this link to your clipboard."])
            end
        elseif link:find("addon:SCentral:lootroll:", 1, true) then
            local rollResultId = link:match("addon:SCentral:lootroll:([^|]+)")
            if ns.LootRollUI and ns.LootRollUI.OpenResultsWindow then
                ns.LootRollUI:OpenResultsWindow((rollResultId and rollResultId ~= "") and rollResultId or nil)
            end
        elseif link:find("addon:SCentral:grp:", 1, true) then
            local idxStr, tKey = link:match("addon:SCentral:grp:(%d+):([^|]+)")
            if idxStr and tKey and Theme and Theme.OpenGroupSnapshotMenu then
                QuickReply._ownMenuOpen = true
                QuickReply._menuActionPicked = true
                Theme:OpenGroupSnapshotMenu(selfMsg, tKey, tonumber(idxStr))
            end
        elseif link:find("addon:SCentral:guildact:", 1, true) then
            local idxStr, tKey = link:match("addon:SCentral:guildact:(%d+):([^|]+)")
            if idxStr and tKey and ns.Chat and ns.Chat.HandleGuildMilestoneHyperlink then
                ns.Chat:HandleGuildMilestoneHyperlink(tKey, tonumber(idxStr), button, function(prefillTxt)
                    if f and f.inputBox and not QuickReply:IsOfficialOnlyThread() then
                        f.inputBox:SetText(prefillTxt)
                        if f.inputBox.SetCursorPosition then f.inputBox:SetCursorPosition(#prefillTxt) end
                        if f.inputBox.SetFocus then f.inputBox:SetFocus() end
                    elseif ns.Chat and ns.Chat.OpenOfficialChatForThread then
                        ns.Chat:OpenOfficialChatForThread(tKey, prefillTxt, false)
                    end
                end)
            end
        elseif link:find("addon:SCentral:msgact:", 1, true) then
            local idx = tonumber(link:match("addon:SCentral:msgact:(%d+)"))
            OpenQuickReplyMessageActionsMenu(selfMsg, idx)
        elseif link:find("addon:SCentral:w:", 1, true) then
            local who = link:match("addon:SCentral:w:([^|]+)")
            if who and who ~= "" then
                if button == "RightButton" then
                    OpenQuickReplySenderMenu(selfMsg, who)
                elseif button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() and not (IsAltKeyDown and IsAltKeyDown()) and not (IsControlKeyDown and IsControlKeyDown()) then
                    local parsed = ns.Compat and ns.Compat.ParseCharacterName and ns.Compat.ParseCharacterName(who)
                    local disp = (parsed and parsed.displayName) or who
                    local typingTarget = QuickReply:IsDockedOfficialFocused()
                        and ((_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
                            or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
                            or _G.ChatFrame1EditBox)
                        or (f.inputBox and f.inputBox.HasFocus and f.inputBox:HasFocus() and f.inputBox)
                        or nil
                    if typingTarget and typingTarget.Insert then
                        local cur = (typingTarget.GetText and typingTarget:GetText()) or ""
                        local ins = (cur ~= "" and cur:sub(-1) ~= " " and " " or "") .. disp .. " "
                        pcall(typingTarget.Insert, typingTarget, ins)
                    elseif ns.Chat and ns.Chat.ExecuteSlashCommand then
                        ns.Chat:ExecuteSlashCommand('/who n-"' .. disp .. '"', true)
                    end
                elseif button == "LeftButton" and IsAltKeyDown and IsAltKeyDown() and not (IsControlKeyDown and IsControlKeyDown()) and not (IsShiftKeyDown and IsShiftKeyDown()) and (not ns.db or not ns.db.settings or ns.db.settings.chatModifierQuickActions ~= false) then
                    if InCombatLockdown and InCombatLockdown() then
                        ns:Print("%s", L["Unavailable during combat."])
                    elseif ns.Compat and ns.Compat.Invite then
                        ns.Compat.Invite(who)
                    end
                elseif button == "LeftButton" and IsControlKeyDown and IsControlKeyDown() and not (IsAltKeyDown and IsAltKeyDown()) and not (IsShiftKeyDown and IsShiftKeyDown()) and (not ns.db or not ns.db.settings or ns.db.settings.chatModifierQuickActions ~= false) then
                    local parsed = ns.Compat and ns.Compat.ParseCharacterName and ns.Compat.ParseCharacterName(who)
                    local disp = (parsed and parsed.displayName) or who
                    local lk = (parsed and parsed.lookupKey) or disp:lower()
                    if ns.SocialPanels and ns.SocialPanels.OpenSocialMetaModal then
                        ns.SocialPanels:OpenSocialMetaModal(disp, lk, { displayName = disp, lookupKey = lk })
                    end
                elseif ns.Chat and ns.Chat.EnsureWhisperThread then
                    local wt = ns.Chat:EnsureWhisperThread(who)
                    if wt and wt.key then
                        if wt.key ~= QuickReply.activeKey then
                            QuickReply._manualTabSwitchKey = wt.key
                            QuickReply:SaveCurrentDraft()
                            QuickReply:SelectThread(wt.key, true)
                        else
                            QuickReply:FocusInputBox()
                        end
                    end
                elseif ns.Compat and ns.Compat.Whisper then
                    ns.Compat.Whisper(who)
                end
            end
        elseif Theme and Theme.HandleGameHyperlinkClick then
            Theme:HandleGameHyperlinkClick(link, text, button, selfMsg, f.inputBox)
        end
    end)
end

function QuickReply:UpdateMsgBgAnchors(f)
    if not (f and f.msgBg) then
        return
    end
    local allowPings = (f._lastPingBottomAllow ~= false)
    local searchOpen = (f.msgSearchBar and f.msgSearchBar:IsShown()) == true
    local topRef = searchOpen and f.msgSearchBar or f.chipsBar
    f.msgBg:ClearAllPoints()
    if topRef then
        f.msgBg:SetPoint("TOPLEFT", topRef, "BOTTOMLEFT", 0, -3)
    else
        f.msgBg:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -96)
    end
    f.msgBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, allowPings and 54 or 33)
    f._scMsgBgAnchorsReady = true
end

function QuickReply:UpdateMsgScrollbar(f)
    if not (f and f.msgFrame and f.msgScrollTrack and f.msgScrollThumb) then
        return
    end
    local mf = f.msgFrame
    local numMsgs = (mf.GetNumMessages and mf:GetNumMessages()) or 0
    local maxRange = 0
    if mf.GetMaxScrollRange then
        local okR, rng = pcall(mf.GetMaxScrollRange, mf)
        if okR and type(rng) == "number" and rng > 0 then
            maxRange = rng
        end
    elseif numMsgs > 10 then
        maxRange = numMsgs - 10
    end
    local off = (mf.GetScrollOffset and mf:GetScrollOffset()) or 0
    if maxRange <= 0 and off <= 0 then
        f.msgScrollTrack:Hide()
        return
    end
    local trackH = f.msgScrollTrack:GetHeight() or 0
    if trackH < 18 then
        f.msgScrollTrack:Hide()
        return
    end
    local effMax = math.max(1, maxRange, off)
    f.msgScrollTrack:Show()
    local visLines = (mf.GetNumVisibleLines and mf:GetNumVisibleLines()) or 11
    local totalEst = math.max(effMax + visLines, 1)
    local thumbH = math.max(16, math.min(trackH, math.floor(trackH * (visLines / totalEst) + 0.5)))
    if math.abs((f.msgScrollThumb:GetHeight() or 0) - thumbH) >= 1 then
        f.msgScrollThumb:SetHeight(thumbH)
    end
    local travel = math.max(0, trackH - thumbH)
    local fracFromTop = 1.0 - math.max(0.0, math.min(1.0, off / effMax))
    local yOff = -math.floor(fracFromTop * travel + 0.5)
    f.msgScrollThumb:ClearAllPoints()
    f.msgScrollThumb:SetPoint("TOP", f.msgScrollTrack, "TOP", 0, yOff)
end

function QuickReply:SyncStickySectionHeader(f, palette)
    local frame = f or self.frame
    if not (frame and frame.stickyHeader and frame.msgFrame and frame.msgBg) then
        return
    end
    local t = self.activeKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[self.activeKey]
    local qActive = ((self._searchQuery or "") ~= "")
    local msgCount = (t and type(t.messages) == "table") and #t.messages or 0
    local isGroupThread = (t ~= nil) and (t.kind == "PARTY" or t.kind == "RAID" or t.kind == "INSTANCE_CHAT")
    local wantShow = false
    if t and msgCount > 0 and (not qActive) and ns.Theme and ns.Theme.SyncStickySectionBar then
        local pal = palette or ns.Theme:GetPalette()
        wantShow = ns.Theme:SyncStickySectionBar(frame.stickyHeader, frame.msgFrame, frame._msgTrackState, isGroupThread, pal)
        if wantShow and self._combatFadeAlpha ~= nil then
            if frame.stickyHeader.bgTex and frame.stickyHeader.bgTex.SetAlpha then
                pcall(frame.stickyHeader.bgTex.SetAlpha, frame.stickyHeader.bgTex, self._combatFadeAlpha)
            end
            if frame.stickyHeader.bottomLine and frame.stickyHeader.bottomLine.SetAlpha then
                pcall(frame.stickyHeader.bottomLine.SetAlpha, frame.stickyHeader.bottomLine, math.max(0.25, self._combatFadeAlpha))
            end
        end
    else
        frame.stickyHeader._activeSec = nil
        frame.stickyHeader:Hide()
    end
    if frame._scStickyShown ~= wantShow then
        frame._scStickyShown = wantShow
        frame.msgFrame:ClearAllPoints()
        frame.msgFrame:SetPoint("TOPLEFT", frame.msgBg, "TOPLEFT", 8, wantShow and -26 or -6)
        frame.msgFrame:SetPoint("BOTTOMRIGHT", frame.msgBg, "BOTTOMRIGHT", -12, 6)
        self:UpdateMsgScrollbar(frame)
    end
end

function QuickReply:ToggleMsgSearchBar(forceOpen)
    local f = self.frame
    if not (f and f.msgSearchBar) then
        return
    end
    local wantShow = (forceOpen ~= nil) and (forceOpen == true) or (not f.msgSearchBar:IsShown())
    if wantShow then
        f.msgSearchBar:Show()
        self:UpdateMsgBgAnchors(f)
        if f.msgSearchBox and f.msgSearchBox.SetFocus then
            f.msgSearchBox:SetFocus()
        end
    else
        self._searchQuery = ""
        if f.msgSearchBox then
            if f.msgSearchBox.ClearFocus then f.msgSearchBox:ClearFocus() end
            f.msgSearchBox:SetText("")
        end
        if f.msgSearchMatchFs then
            f.msgSearchMatchFs:SetText("")
        end
        f.msgSearchBar:Hide()
        self:UpdateMsgBgAnchors(f)
    end
    self._forceMsgRebuild = true
    self:Refresh()
end

function QuickReply:CopyActiveThreadLog()
    local k = self.activeKey
    local act = k and ns.Chat and ns.Chat.threads and ns.Chat.threads[k]
    if not (act and type(act.messages) == "table" and #act.messages > 0) then
        return
    end
    local buf = {}
    local isGeneralCopy = (k == "ch:general")
    local streamerOn = (Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()) == true
    for _, entry in ipairs(act.messages) do
        if (not isGeneralCopy) or (not ns.Chat.IsGeneralEntryVisible) or ns.Chat:IsGeneralEntryVisible(entry) then
            local ts = entry.ts and entry.ts > 0 and date("[%H:%M] ", entry.ts) or ""
            local rawTxt = tostring(entry.text or "")
            rawTxt = rawTxt:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
            local shortSender = entry.sender or ""
            if streamerOn and (act.kind == "BN_WHISPER" or tostring(shortSender):find("#", 1, true)) and Compat.MaskStreamerBNetName then
                shortSender = Compat.MaskStreamerBNetName(shortSender)
            end
            buf[#buf + 1] = ts .. shortSender .. ": " .. rawTxt
        end
    end
    if ns.UI and ns.UI.OpenCopyModal then
        local copyTitle = act.title or k
        if streamerOn then
            if act.kind == "ROOM" then
                copyTitle = L["Private Room"]
            elseif (act.kind == "BN_WHISPER" or tostring(copyTitle):find("#", 1, true)) and Compat.MaskStreamerBNetName then
                copyTitle = Compat.MaskStreamerBNetName(copyTitle)
            end
        end
        ns.UI:OpenCopyModal(table.concat(buf, "\n"), L["Copy Chat: %s"]:format(copyTitle), L["Press Ctrl+C to copy the conversation log to clipboard."])
    end
end

function QuickReply:OpenGeneralChannelMenu(anchorBtn)
    if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Chat and ns.Chat.GetJoinedOfficialChannels) then
        return
    end
    self._ownMenuOpen = true
    self._menuActionPicked = false
    MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        root:CreateTitle(L["Send Channel inside General (/s, /y, /1, /2, /3...)"])
        local gTarget = ns.Chat.GetGeneralTargetInfo and ns.Chat:GetGeneralTargetInfo() or nil
        root:CreateRadio("/s · " .. L["Say"], function()
            return not (gTarget and (gTarget.channelId or gTarget.isYell))
        end, function()
            QuickReply._menuActionPicked = true
            if ns.Chat.SetGeneralTargetChannel then ns.Chat:SetGeneralTargetChannel(nil) end
            if QuickReply.frame and QuickReply.frame:IsShown() then
                QuickReply:Refresh()
                if QuickReply.activeKey == "ch:general" and QuickReply.SyncBlizzardStickyChannelForThread then
                    QuickReply:SyncBlizzardStickyChannelForThread("ch:general")
                end
                QuickReply:ReleaseKeyboardFocus(false)
            end
        end)
        root:CreateRadio("/y · " .. L["Yell"], function()
            return (gTarget and gTarget.isYell) == true
        end, function()
            QuickReply._menuActionPicked = true
            if ns.Chat.SetGeneralTargetChannel then ns.Chat:SetGeneralTargetChannel("yell") end
            if QuickReply.frame and QuickReply.frame:IsShown() then
                QuickReply:Refresh()
                if QuickReply.activeKey == "ch:general" and QuickReply.SyncBlizzardStickyChannelForThread then
                    QuickReply:SyncBlizzardStickyChannelForThread("ch:general")
                end
                QuickReply:ReleaseKeyboardFocus(false)
            end
        end)
        for _, ch in ipairs(ns.Chat:GetJoinedOfficialChannels()) do
            root:CreateRadio("/" .. tostring(ch.id) .. " · " .. ch.name, function()
                return (gTarget and gTarget.channelId == ch.id) == true
            end, function()
                QuickReply._menuActionPicked = true
                if ns.Chat.SetGeneralTargetChannel then ns.Chat:SetGeneralTargetChannel(ch.id) end
                if QuickReply.frame and QuickReply.frame:IsShown() then
                    QuickReply:Refresh()
                    if QuickReply.activeKey == "ch:general" and QuickReply.SyncBlizzardStickyChannelForThread then
                        QuickReply:SyncBlizzardStickyChannelForThread("ch:general")
                    end
                    QuickReply:ReleaseKeyboardFocus(false)
                end
            end)
        end
    end)
end

function QuickReply:OpenGeneralFilterMenu(anchorBtn)
    if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Chat and ns.Chat.AttachGeneralFilterSubmenu) then
        return
    end
    self._ownMenuOpen = true
    self._menuActionPicked = false
    MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        root:CreateTitle(L["Filter General"])
        ns.Chat:AttachGeneralFilterSubmenu(root, function()
            QuickReply._menuActionPicked = true
            QuickReply._forceMsgRebuild = true
            if QuickReply.frame and QuickReply.frame:IsShown() then
                QuickReply:Refresh()
            end
        end)
    end)
end

function QuickReply:ApplyChatFontSize()
    local f = self.frame
    if not (f and f.msgFrame) then return end
    local sz = (ns.db and ns.db.settings and tonumber(ns.db.settings.quickReplyFontSize)) or 0
    if sz >= 11 and sz <= 18 then
        if not self._defaultMsgFontPath and _G.ChatFontNormal and _G.ChatFontNormal.GetFont then
            local p, s, fl = _G.ChatFontNormal:GetFont()
            self._defaultMsgFontPath = p
            self._defaultMsgFontSize = s
            self._defaultMsgFontFlags = fl
        end
        local fontPath = self._defaultMsgFontPath or ((f.msgFrame.GetFont and f.msgFrame:GetFont()) or "Fonts\\FRIZQT__.TTF")
        local fontFlags = self._defaultMsgFontFlags or ""
        if f.msgFrame.SetFont then
            f.msgFrame:SetFont(fontPath, sz, fontFlags)
        end
    elseif self._defaultMsgFontPath and self._defaultMsgFontSize and f.msgFrame.SetFont then
        f.msgFrame:SetFont(self._defaultMsgFontPath, self._defaultMsgFontSize, self._defaultMsgFontFlags or "")
    elseif f.msgFrame.SetFontObject then
        f.msgFrame:SetFontObject(_G.ChatFontNormal or "GameFontHighlightSmall")
    end
    if f.msgFrame.SetShadowColor then
        f.msgFrame:SetShadowColor(0, 0, 0, 0.95)
    end
    if f.msgFrame.SetShadowOffset then
        f.msgFrame:SetShadowOffset(1, -1)
    end
end

function QuickReply:BuildInputPlaceholder(t, titleStr, gTarget)
    if not t then
        return L["Type a quick reply..."]
    end
    if t.kind == "MENTIONS" then
        return L["Click a sender name above to reply, or click 'Keywords' to configure."]
    elseif t.kind == "NOTES" then
        return L["Write a personal note..."]
    elseif t.kind == "GENERAL" then
        local chTok = (gTarget and gTarget.channelId and ("/" .. tostring(gTarget.channelId)))
            or (gTarget and gTarget.isYell and "/y")
            or "/s"
        return string.format(L["Speak in %s..."], chTok)
    elseif t.kind == "PUB_CHANNEL" then
        return string.format(L["Speak in %s..."], "/" .. tostring(t.channelId or "?"))
    end
    local cleanTitle = self:TruncateUtf8(tostring(titleStr or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), 22)
    if cleanTitle ~= "" then
        return string.format(L["Message %s..."], cleanTitle)
    end
    return L["Type a quick reply..."]
end

function QuickReply:SyncScrollBottomPill(f, resetCount)
    f = f or self.frame
    if not (f and f.btnScrollBottom and f.msgFrame) then return end
    local atBot = (not f.msgFrame.AtBottom) or (f.msgFrame:AtBottom() ~= false)
    if resetCount or atBot then
        f._scrollUnreadNew = 0
    end
    local n = f._scrollUnreadNew or 0
    local wantTxt = (n > 0) and ("v " .. L["Latest"] .. " |cff4ade80(" .. tostring(n) .. ")|r") or ("v " .. L["Latest"])
    if f.btnScrollBottom._scLastPillTxt ~= wantTxt then
        f.btnScrollBottom._scLastPillTxt = wantTxt
        if ns.Theme and ns.Theme.SetButtonText and ns.Theme.AutoFitButton then
            ns.Theme:SetButtonText(f.btnScrollBottom, wantTxt)
            ns.Theme:AutoFitButton(f.btnScrollBottom, 60, 12, 140)
        end
    end
    f.btnScrollBottom:SetShown(not atBot)
end

function QuickReply:OpenThreadOptionsMenu(anchorBtn)
    if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Chat) then
        return
    end
    local k = self.activeKey
    local t = k and ns.Chat.threads and ns.Chat.threads[k]
    if not (k and t) then
        return
    end
    self._ownMenuOpen = true
    self._menuActionPicked = false
    MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        local titleStr = (self.frame and self.frame._headerMeta and self.frame._headerMeta.tooltipTitle) or t.title or k
        root:CreateTitle(titleStr)
        root:CreateButton((self.frame and self.frame.msgSearchBar and self.frame.msgSearchBar:IsShown()) and (L["Search"] .. " (X)") or L["Search messages..."], function()
            QuickReply._menuActionPicked = true
            QuickReply:ToggleMsgSearchBar()
        end)
        if type(t.messages) == "table" and #t.messages > 0 then
            root:CreateButton(L["Copy Conversation"], function()
                QuickReply._menuActionPicked = true
                QuickReply:CopyActiveThreadLog()
            end)
        end
        local pingsOn = (not ns.db or not ns.db.settings) or (ns.db.settings.quickReplyShowPingsBar ~= false)
        root:CreateCheckbox(L["Show Quick Replies Bar"], function()
            return (not ns.db or not ns.db.settings) or (ns.db.settings.quickReplyShowPingsBar ~= false)
        end, function()
            QuickReply._menuActionPicked = true
            if ns.db and ns.db.settings then
                ns.db.settings.quickReplyShowPingsBar = not pingsOn
            end
            if ns.Emit then ns:Emit("SETTINGS_UPDATED") end
            QuickReply:Refresh()
        end)
        local fontSub = root:CreateButton(L["Font Size"])
        local fontOpts = {
            { val = 0, label = L["Default"] },
            { val = 11, label = L["Small"] .. " (11)" },
            { val = 13, label = L["Medium"] .. " (13)" },
            { val = 14, label = L["Large"] .. " (14)" },
            { val = 16, label = L["Extra Large"] .. " (16)" },
        }
        for _, fOpt in ipairs(fontOpts) do
            fontSub:CreateRadio(fOpt.label, function()
                local cur = (ns.db and ns.db.settings and tonumber(ns.db.settings.quickReplyFontSize)) or 0
                return cur == fOpt.val
            end, function()
                QuickReply._menuActionPicked = true
                if ns.db and ns.db.settings then
                    ns.db.settings.quickReplyFontSize = fOpt.val
                end
                QuickReply:ApplyChatFontSize()
                QuickReply._forceMsgRebuild = true
                QuickReply:Refresh()
            end)
        end
        if k == "ch:general" and ns.Chat.AttachGeneralFilterSubmenu then
            root:CreateDivider()
            ns.Chat:AttachGeneralFilterSubmenu(root, function()
                QuickReply._menuActionPicked = true
                QuickReply._forceMsgRebuild = true
                QuickReply:Refresh()
            end)
        end
        if k ~= "ch:general" and k ~= "notes:self" and k ~= "mentions:radar" and ns.Chat.ToggleQuickReplyPinned then
            root:CreateDivider()
            local isPinned = ns.Chat.IsQuickReplyPinned and ns.Chat:IsQuickReplyPinned(k) == true
            root:CreateButton(isPinned and L["Unpin from Quick Reply"] or L["Pin in Quick Reply"], function()
                QuickReply._menuActionPicked = true
                ns.Chat:ToggleQuickReplyPinned(k)
                QuickReply:Refresh()
            end)
            root:CreateButton(L["Close Tab"], function()
                QuickReply._menuActionPicked = true
                QuickReply:RequestCloseTab(k, titleStr)
            end)
        end
        if type(t.messages) == "table" and #t.messages > 0 and ns.Chat.ClearHistory then
            root:CreateDivider()
            root:CreateButton("|cfff54747" .. L["Clear Active Chat"] .. "|r", function()
                QuickReply._menuActionPicked = true
                if ns.UI and ns.UI.OpenConfirmModal then
                    ns.UI:OpenConfirmModal({
                        title = L["Clear Active Chat"],
                        message = L["Are you sure you want to clear all messages in '%s'?"]:format(titleStr),
                        confirmText = L["Clear"],
                        onConfirm = function()
                            if ns.Chat and ns.Chat.ClearHistory then
                                ns.Chat:ClearHistory(k)
                                QuickReply:Refresh()
                            end
                        end,
                    })
                else
                    ns.Chat:ClearHistory(k)
                    QuickReply:Refresh()
                end
            end)
        end
    end)
end

function QuickReply:BuildHeaderExtras(f, Theme)
    local hdr = f.header
    if not hdr then return end
    local sep1 = hdr:CreateTexture(nil, "ARTWORK", nil, 2)
    sep1:SetSize(1, 14)
    sep1:SetTexture(MP_WHITE8X8)
    sep1:SetVertexColor(0.48, 0.45, 0.38, 0.45)
    f.hdrSep1 = sep1

    local sep2 = hdr:CreateTexture(nil, "ARTWORK", nil, 2)
    sep2:SetSize(1, 14)
    sep2:SetTexture(MP_WHITE8X8)
    sep2:SetVertexColor(0.48, 0.45, 0.38, 0.45)
    f.hdrSep2 = sep2

    local btnNewChat = Theme:CreateButton(hdr, 20, 20, "", "default")
    Theme:ConfigureIconButton(btnNewChat, 20, 20, "Interface\\PaperDollInfoFrame\\Character-Plus", {
        size = 15,
        color = { 0.45, 0.95, 0.55 },
        title = L["New 1-on-1 Chat"],
        desc = L["Open a 1-on-1 conversation with a friend, guildmate, target, or character name."],
    })
    btnNewChat:SetScript("OnClick", function()
        QuickReply:HideWhispersDropdown()
        if ns.SocialPanels and ns.SocialPanels.OpenNewDirectChatModal then
            ns.SocialPanels:OpenNewDirectChatModal({
                onOpened = function(newKey)
                    if newKey then
                        QuickReply:OpenThread(newKey, true)
                    end
                end,
            })
        end
    end)
    f.btnNewChat = btnNewChat

    local btnHeaderUnread = Theme:CreateButton(hdr, 34, 18, "", "default")
    btnHeaderUnread:Hide()
    btnHeaderUnread:SetScript("OnClick", function()
        if not ns.Chat then return end
        local pending = ns.Chat.GetQuickReplyThreads and ns.Chat:GetQuickReplyThreads() or {}
        for _, item in ipairs(pending) do
            if item.key ~= QuickReply.activeKey and (item.unread or 0) > 0 and not item.muted then
                QuickReply:SaveCurrentDraft()
                QuickReply:SelectThread(item.key, false)
                return
            end
        end
    end)
    btnHeaderUnread:SetScript("OnEnter", function(selfBtn)
        if not (GameTooltip and (selfBtn._otherUnread or 0) > 0) then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["Unread"], 0.35, 0.95, 0.55)
        GameTooltip:AddLine(string.format(L["%d unread in other tabs — click to jump"], selfBtn._otherUnread or 0), 0.90, 0.93, 0.96, true)
        GameTooltip:Show()
    end)
    btnHeaderUnread:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)
    f.btnHeaderUnread = btnHeaderUnread
end

function QuickReply:LayoutHeaderBar(f)
    local hdr = f and f.header
    if not hdr then return end
    local winW = math.floor((f:GetWidth() or 444) + 0.5)
    -- Right-to-left groups: [Help][Close] | [AutoClose][Dock][Lock] | [NewChat][CombatLog][History][Expand]
    if f.hdrSep2 and f.btnHelp and f.btnLock and f.btnDock and f.btnAutoClose and f.hdrSep1 and f.btnExpand and f.btnHistory and f.btnCombatLog and f.btnNewChat then
        if not f._scHeaderGrouped then
            f._scHeaderGrouped = true
            f.btnClose:ClearAllPoints()
            f.btnClose:SetPoint("RIGHT", hdr, "RIGHT", -4, 0)
            f.btnHelp:ClearAllPoints()
            f.btnHelp:SetPoint("RIGHT", f.btnClose, "LEFT", -2, 0)

            f.hdrSep2:ClearAllPoints()
            f.hdrSep2:SetPoint("RIGHT", f.btnHelp, "LEFT", -4, 0)

            f.btnLock:ClearAllPoints()
            f.btnLock:SetPoint("RIGHT", f.hdrSep2, "LEFT", -4, 0)
            f.btnDock:ClearAllPoints()
            f.btnDock:SetPoint("RIGHT", f.btnLock, "LEFT", -2, 0)
            f.btnAutoClose:ClearAllPoints()
            f.btnAutoClose:SetPoint("RIGHT", f.btnDock, "LEFT", -3, 0)

            f.hdrSep1:ClearAllPoints()
            f.hdrSep1:SetPoint("RIGHT", f.btnAutoClose, "LEFT", -4, 0)

            f.btnExpand:ClearAllPoints()
            f.btnExpand:SetPoint("RIGHT", f.hdrSep1, "LEFT", -4, 0)
            f.btnHistory:ClearAllPoints()
            f.btnHistory:SetPoint("RIGHT", f.btnExpand, "LEFT", -2, 0)
            f.btnCombatLog:ClearAllPoints()
            f.btnCombatLog:SetPoint("RIGHT", f.btnHistory, "LEFT", -2, 0)
            f.btnNewChat:ClearAllPoints()
            f.btnNewChat:SetPoint("RIGHT", f.btnCombatLog, "LEFT", -2, 0)
        end
    end

    local otherUnread = 0
    if ns.Chat and ns.Chat.GetQuickReplyThreads then
        local pending = ns.Chat:GetQuickReplyThreads()
        for _, item in ipairs(pending) do
            if item.key ~= self.activeKey and not item.muted and (item.unread or 0) > 0 then
                otherUnread = otherUnread + (item.unread or 0)
            end
        end
    end
    local rightUsed = 18
    local hdrChildren = f._hdrChildrenScratch
    if not hdrChildren then
        hdrChildren = { f.btnClose, f.btnHelp, f.btnLock, f.btnDock, f.btnAutoClose, f.btnExpand, f.btnHistory, f.btnCombatLog, f.btnNewChat }
        f._hdrChildrenScratch = hdrChildren
    end
    for i = 1, #hdrChildren do
        local hc = hdrChildren[i]
        if hc and hc:IsShown() then
            rightUsed = rightUsed + math.ceil(hc._scAutoFitW or hc:GetWidth() or 20) + 2
        end
    end
    local leftAvail = math.max(0, winW - 24 - rightUsed)
    if f.btnHeaderUnread then
        if otherUnread > 0 and leftAvail >= 32 then
            if f.btnHeaderUnread._otherUnread ~= otherUnread then
                f.btnHeaderUnread._otherUnread = otherUnread
                ns.Theme:SetButtonText(f.btnHeaderUnread, "|cff4ade80+" .. tostring(otherUnread) .. "|r")
                ns.Theme:AutoFitButton(f.btnHeaderUnread, 28, 10, 48)
                if f.btnHeaderUnread.SetBackdropBorderColor then
                    f.btnHeaderUnread:SetBackdropBorderColor(0.28, 0.85, 0.45, 0.85)
                end
            end
            f.btnHeaderUnread:Show()
            leftAvail = leftAvail - math.ceil(f.btnHeaderUnread._scAutoFitW or f.btnHeaderUnread:GetWidth() or 30) - 4
        else
            f.btnHeaderUnread._otherUnread = 0
            f.btnHeaderUnread:Hide()
        end
    end
    if f.toolbarLabel and f.dragGrip2 then
        local wantBrand = (leftAvail >= 52) and L["SC Chat"] or "SC"
        if f.toolbarLabel._scLastBrand ~= wantBrand then
            f.toolbarLabel._scLastBrand = wantBrand
            f.toolbarLabel:SetText(wantBrand)
        end
        f.toolbarLabel:SetShown(leftAvail >= 22)
        f.toolbarLabel:ClearAllPoints()
        f.toolbarLabel:SetPoint("LEFT", f.dragGrip2, "RIGHT", 6, 0)
        if f.btnHeaderUnread and f.btnHeaderUnread:IsShown() then
            f.btnHeaderUnread:ClearAllPoints()
            if f.toolbarLabel:IsShown() then
                f.toolbarLabel:SetWidth(math.min(54, math.max(18, leftAvail)))
                f.btnHeaderUnread:SetPoint("LEFT", f.toolbarLabel, "RIGHT", 4, 0)
            else
                f.btnHeaderUnread:SetPoint("LEFT", f.dragGrip2, "RIGHT", 6, 0)
            end
        elseif f.btnNewChat then
            f.toolbarLabel:SetPoint("RIGHT", f.btnNewChat, "LEFT", -4, 0)
        end
    end
end

function QuickReply:BuildInfoBarExtras(f, Theme)
    local infoBar = f.infoBar
    if not infoBar then return end

    local avatarBtn = CreateFrame("Button", nil, infoBar)
    avatarBtn:SetPoint("TOPLEFT", f.icoRim, "TOPLEFT", 0, 0)
    avatarBtn:SetPoint("BOTTOMRIGHT", f.icoRim, "BOTTOMRIGHT", 0, 0)
    avatarBtn:SetFrameLevel((infoBar:GetFrameLevel() or 2) + 4)
    local avHl = avatarBtn:CreateTexture(nil, "HIGHLIGHT")
    avHl:SetAllPoints()
    avHl:SetColorTexture(1, 0.90, 0.55, 0.20)
    avatarBtn:SetScript("OnClick", function()
        local t = QuickReply.activeKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[QuickReply.activeKey]
        if not (t and (t.kind == "WHISPER" or t.kind == "BN_WHISPER")) then return end
        local rawTarget = t.targetName or t.bnetName or t.title
        local parsed = rawTarget and ns.Compat and ns.Compat.ParseCharacterName and ns.Compat.ParseCharacterName(rawTarget)
        local lk = (parsed and parsed.lookupKey) or t.lookupKey or rawTarget
        local disp = (parsed and parsed.displayName) or rawTarget
        local ctx = (t.bnetAccountID and { lookupKey = lk, bnetAccountID = t.bnetAccountID, bnetName = t.bnetName, sources = { bnet = true } }) or nil
        if ns.SocialPanels and ns.SocialPanels.OpenSocialMetaModal and (disp or ctx) then
            ns.SocialPanels:OpenSocialMetaModal(disp, lk, ctx)
        end
    end)
    avatarBtn:SetScript("OnEnter", function(selfBtn)
        local t = QuickReply.activeKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[QuickReply.activeKey]
        if not (t and (t.kind == "WHISPER" or t.kind == "BN_WHISPER") and GameTooltip) then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["Social Card & Notes"], 1.0, 0.85, 0.25)
        GameTooltip:AddLine(L["Open Social Card, folders, alts, and friend notes for this player."], 0.90, 0.93, 0.96, true)
        GameTooltip:Show()
    end)
    avatarBtn:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)
    f.avatarBtn = avatarBtn

    local btnThreadOpts = Theme:CreateButton(infoBar, 20, 20, "", "default")
    Theme:ConfigureIconButton(btnThreadOpts, 20, 20, "Interface\\Buttons\\UI-OptionsButton", {
        size = 15,
        color = { 0.92, 0.85, 0.72 },
        title = L["Conversation Actions"],
        desc = L["Copy, search, pin, silence, clear, or toggle Quick Replies Bar."],
    })
    btnThreadOpts:SetScript("OnClick", function(selfBtn)
        QuickReply:OpenThreadOptionsMenu(selfBtn)
    end)
    f.btnThreadOpts = btnThreadOpts

    local btnMsgSearch = Theme:CreateButton(infoBar, 52, 20, L["Search"], "default")
    Theme:AutoFitButton(btnMsgSearch, 44, 12, 74)
    btnMsgSearch:SetScript("OnClick", function()
        QuickReply:ToggleMsgSearchBar()
    end)
    btnMsgSearch:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["Search messages..."], 1.0, 0.85, 0.25)
        GameTooltip:AddLine(L["Filter messages in this conversation"] .. " (Ctrl+F)", 0.90, 0.93, 0.96, true)
        GameTooltip:Show()
    end)
    btnMsgSearch:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)
    f.btnMsgSearch = btnMsgSearch

    local btnCard = Theme:CreateButton(infoBar, 20, 20, "", "default")
    Theme:ConfigureIconButton(btnCard, 20, 20, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", {
        size = 15,
        color = { 1.0, 0.85, 0.35 },
        title = L["Social Card & Notes"],
        desc = L["Open Social Card, folders, alts, and friend notes for this player."],
    })
    btnCard:SetScript("OnClick", function()
        avatarBtn:Click()
    end)
    btnCard:Hide()
    f.btnCard = btnCard

    local btnGenFilter = Theme:CreateButton(infoBar, 56, 20, L["Filters"], "default")
    Theme:AutoFitButton(btnGenFilter, 44, 12, 76)
    btnGenFilter:SetScript("OnClick", function(selfBtn)
        QuickReply:OpenGeneralFilterMenu(selfBtn)
    end)
    btnGenFilter:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["Filter General"], 1.0, 0.85, 0.25)
        GameTooltip:AddLine(L["Click to filter which messages appear in General"], 0.90, 0.93, 0.96, true)
        GameTooltip:Show()
    end)
    btnGenFilter:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)
    btnGenFilter:Hide()
    f.btnGenFilter = btnGenFilter

    local btnGenChannel = Theme:CreateButton(infoBar, 52, 20, "/s", "default")
    Theme:AutoFitButton(btnGenChannel, 38, 12, 82)
    btnGenChannel:SetScript("OnClick", function(selfBtn)
        QuickReply:OpenGeneralChannelMenu(selfBtn)
    end)
    btnGenChannel:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["Switch Channel"], 1.0, 0.85, 0.25)
        GameTooltip:AddLine(L["Click to switch send channel (/s, /y, /1, /2, /3...)"], 0.90, 0.93, 0.96, true)
        GameTooltip:Show()
    end)
    btnGenChannel:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)
    btnGenChannel:Hide()
    f.btnGenChannel = btnGenChannel
end

function QuickReply:LayoutInfoBarActions(f, state)
    if not (f and f.infoBar) then return end
    local winW = math.floor((f:GetWidth() or 444) + 0.5)
    local isGen = (state.isGeneral == true)
    local showSearchPill = (isGen and (winW >= 425)) or ((not isGen) and (winW >= 375))
    local showCardBtn = (state.isPlayer == true) and (winW >= 395)

    if f.btnThreadOpts then f.btnThreadOpts:SetShown(true) end
    if f.btnMsgSearch then
        f.btnMsgSearch:SetShown(showSearchPill)
        if showSearchPill then
            local searchActive = ((f.msgSearchBar and f.msgSearchBar:IsShown()) == true) or ((self._searchQuery or "") ~= "")
            ns.Theme:SetButtonActive(f.btnMsgSearch, searchActive, "default")
        end
    end
    if f.btnCard then f.btnCard:SetShown(showCardBtn) end
    if f.btnGenFilter then
        f.btnGenFilter:SetShown(isGen)
        if isGen then
            local gf = ns.db and ns.db.settings and ns.db.settings.generalFeedFilters
            local anyOff = gf and (gf.loot == false or gf.achievement == false or gf.monster == false or gf.system == false or gf.public == false)
            ns.Theme:SetButtonActive(f.btnGenFilter, anyOff == true, "default")
        end
    end
    if f.btnGenChannel then
        f.btnGenChannel:SetShown(isGen)
        if isGen then
            local gT = ns.Chat and ns.Chat.GetGeneralTargetInfo and ns.Chat:GetGeneralTargetInfo() or nil
            local chLbl = (gT and gT.channelId and ("/" .. tostring(gT.channelId)))
                or (gT and gT.isYell and "/y")
                or "/s"
            local chText = chLbl .. " v"
            if f.btnGenChannel._scChTxt ~= chText then
                f.btnGenChannel._scChTxt = chText
                ns.Theme:SetButtonText(f.btnGenChannel, chText)
                ns.Theme:AutoFitButton(f.btnGenChannel, 38, 12, 72)
            end
            if f.btnGenChannel.SetBackdropBorderColor and state.toneRgb then
                f.btnGenChannel:SetBackdropBorderColor(state.toneRgb[1], state.toneRgb[2], state.toneRgb[3], 0.85)
            end
        end
    end

    local order = f._infoBtnOrderScratch
    if not order then
        order = {}
        f._infoBtnOrderScratch = order
    else
        wipe(order)
    end
    if f.btnThreadOpts and f.btnThreadOpts:IsShown() then order[#order + 1] = f.btnThreadOpts end
    if f.btnMute and state.canMute and f.btnMute:IsShown() then order[#order + 1] = f.btnMute end
    if f.btnMentionCfg and state.isMentions and f.btnMentionCfg:IsShown() then order[#order + 1] = f.btnMentionCfg end
    if f.btnMsgSearch and f.btnMsgSearch:IsShown() then order[#order + 1] = f.btnMsgSearch end
    if f.btnGenFilter and f.btnGenFilter:IsShown() then order[#order + 1] = f.btnGenFilter end
    if f.btnGenChannel and f.btnGenChannel:IsShown() then order[#order + 1] = f.btnGenChannel end
    if f.btnCard and f.btnCard:IsShown() then order[#order + 1] = f.btnCard end
    if f.btnWatch and state.canWatch and f.btnWatch:IsShown() then order[#order + 1] = f.btnWatch end
    if f.btnInvite and state.canInvite and f.btnInvite:IsShown() then order[#order + 1] = f.btnInvite end

    local sig = ""
    for i = 1, #order do
        sig = sig .. tostring(order[i]:GetWidth() or 20) .. ":"
    end
    sig = sig .. tostring(#order) .. ":" .. tostring(winW)
    if f._scInfoOrderSig ~= sig then
        f._scInfoOrderSig = sig
        local prev
        for i = 1, #order do
            local b = order[i]
            b:ClearAllPoints()
            if not prev then
                b:SetPoint("RIGHT", f.infoBar, "RIGHT", -6, 0)
            else
                b:SetPoint("RIGHT", prev, "LEFT", -3, 0)
            end
            prev = b
        end
        f._infoLeftmostBtn = prev
    end
end

function QuickReply:BuildMsgViewportExtras(f, Theme)
    local topGlow = f.msgBg:CreateTexture(nil, "BACKGROUND", nil, 1)
    topGlow:SetPoint("TOPLEFT", f.msgBg, "TOPLEFT", 1, -1)
    topGlow:SetPoint("TOPRIGHT", f.msgBg, "TOPRIGHT", -1, -1)
    topGlow:SetHeight(14)
    topGlow:SetTexture(QR_WHITE8X8)
    topGlow:SetVertexColor(0.20, 0.30, 0.40, 0.08)
    f.msgTopGlow = topGlow

    if Theme and Theme.CreateStickySectionBar then
        local stickyHeader = Theme:CreateStickySectionBar(f.msgBg, function()
            QuickReply:SyncScrollBottomPill(f, false)
            QuickReply:UpdateMsgScrollbar(f)
            QuickReply:SyncStickySectionHeader(f)
        end)
        if stickyHeader then
            stickyHeader:SetPoint("TOPLEFT", f.msgBg, "TOPLEFT", 2, -2)
            stickyHeader:SetPoint("TOPRIGHT", f.msgBg, "TOPRIGHT", -2, -2)
            stickyHeader:SetFrameLevel((f.msgFrame:GetFrameLevel() or 2) + 4)
            f.stickyHeader = stickyHeader
        end
    end

    local sBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    sBar:SetPoint("TOPLEFT", f.chipsBar, "BOTTOMLEFT", 0, -3)
    sBar:SetPoint("TOPRIGHT", f.chipsBar, "BOTTOMRIGHT", 0, -3)
    sBar:SetHeight(24)
    sBar:EnableMouse(true)
    Theme:ApplyBackdrop(sBar, "surface")
    sBar:Hide()
    f.msgSearchBar = sBar

    local closeBtn = Theme:CreateButton(sBar, 20, 19, "X", "default")
    closeBtn:SetPoint("RIGHT", sBar, "RIGHT", -4, 0)
    closeBtn:SetScript("OnClick", function()
        QuickReply:ToggleMsgSearchBar(false)
    end)
    f.msgSearchCloseBtn = closeBtn

    local matchFs = sBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    matchFs:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    matchFs:SetJustifyH("RIGHT")
    matchFs:SetWordWrap(false)
    matchFs:SetText("")
    f.msgSearchMatchFs = matchFs

    local sBox = Theme:CreateEditBox(sBar, {
        height = 19,
        maxLetters = 80,
        clearButton = true,
        placeholder = L["Search messages..."],
    })
    sBox:SetPoint("LEFT", sBar, "LEFT", 4, 0)
    sBox:SetPoint("RIGHT", matchFs, "LEFT", -6, 0)
    sBox:SetScript("OnEscapePressed", function()
        QuickReply:ToggleMsgSearchBar(false)
    end)
    sBox:HookScript("OnTextChanged", function(selfBox)
        local txt = selfBox:GetText() or ""
        if (QuickReply._searchQuery or "") ~= txt then
            QuickReply._searchQuery = txt
            QuickReply._forceMsgRebuild = true
            QuickReply:Refresh()
        end
    end)
    f.msgSearchBox = sBox

    -- Sleek 4px vertical scrollbar on right edge of msgBg
    local track = CreateFrame("Frame", nil, f.msgBg)
    track:SetWidth(4)
    track:SetPoint("TOPLEFT", f.msgFrame, "TOPRIGHT", 3, -2)
    track:SetPoint("BOTTOMLEFT", f.msgFrame, "BOTTOMRIGHT", 3, 2)
    track:SetFrameLevel((f.msgFrame:GetFrameLevel() or 2) + 4)
    local tBg = track:CreateTexture(nil, "BACKGROUND")
    tBg:SetAllPoints()
    tBg:SetTexture(QR_WHITE8X8)
    tBg:SetVertexColor(1, 1, 1, 0.08)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(4)
    thumb:SetHeight(22)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints()
    thumbTex:SetTexture(QR_WHITE8X8)
    thumbTex:SetVertexColor(0.85, 0.72, 0.35, 0.65)
    thumb._tex = thumbTex
    track:Hide()
    f.msgScrollTrack = track
    f.msgScrollThumb = thumb

    thumb:SetScript("OnMouseDown", function(_, mouseBtn)
        if mouseBtn ~= "LeftButton" then return end
        local _, curY = GetCursorPosition()
        local scale = track:GetEffectiveScale() or 1
        local startY = curY / scale
        local startOff = (f.msgFrame.GetScrollOffset and f.msgFrame:GetScrollOffset()) or 0
        local maxR = (f.msgFrame.GetMaxScrollRange and f.msgFrame:GetMaxScrollRange()) or math.max(1, ((f.msgFrame.GetNumMessages and f.msgFrame:GetNumMessages()) or 10) - 10)
        local trackH = math.max(18, track:GetHeight() or 100)
        local travel = math.max(1, trackH - (thumb:GetHeight() or 22))
        thumb._dragging = true
        thumb:SetScript("OnUpdate", function()
            if not thumb._dragging or not IsMouseButtonDown("LeftButton") then
                thumb._dragging = false
                thumb:SetScript("OnUpdate", nil)
                return
            end
            local _, cy = GetCursorPosition()
            local dy = (cy / scale) - startY
            local newOff = math.max(0, math.min(maxR, math.floor(startOff + (dy / travel) * maxR + 0.5)))
            if f.msgFrame.SetScrollOffset then
                f.msgFrame:SetScrollOffset(newOff)
            end
            QuickReply:SyncScrollBottomPill(f, false)
            QuickReply:UpdateMsgScrollbar(f)
            QuickReply:SyncStickySectionHeader(f)
        end)
    end)

    -- Empty state prompt (top-left aligned, matching search/chat reading axis and clear of bottom notices)
    local emptyLbl = f.msgBg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyLbl:SetPoint("TOPLEFT", f.msgBg, "TOPLEFT", 10, -12)
    emptyLbl:SetPoint("TOPRIGHT", f.msgBg, "TOPRIGHT", -16, -12)
    emptyLbl:SetJustifyH("LEFT")
    emptyLbl:SetWordWrap(true)
    emptyLbl:SetText(L["No messages yet — press ENTER or click below to type."])
    emptyLbl:Hide()
    f.msgEmptyLabel = emptyLbl
end

function QuickReply:EnsureFrame()
    if self.frame then
        return self.frame
    end
    local Theme = ns.Theme
    local f = CreateFrame("Frame", "SocialCentralQuickReplyFrame", UIParent, "BackdropTemplate")
    f:Hide()
    f:SetSize(444, 380)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(320)
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetResizable(true)
    if f.EnableKeyboard then
        pcall(f.EnableKeyboard, f, false)
    end
    f:SetClampedToScreen(true)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    table.insert(UISpecialFrames, "SocialCentralQuickReplyFrame")
    self:SyncEscapeCloseRegistration()

    local solidBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetAllPoints()
    solidBg:SetTexture(MP_WHITE8X8)
    solidBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    f._solidOpaqueBg = solidBg

    -- Full-perimeter outer glow halo + crisp animated focus border edges (non-interactive, follows active chat tone)
    local haloLayer = CreateFrame("Frame", nil, f)
    haloLayer:SetPoint("TOPLEFT", f, "TOPLEFT", -4, 4)
    haloLayer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -4)
    haloLayer:SetFrameLevel(math.max(1, (f:GetFrameLevel() or 320) - 1))
    haloLayer:EnableMouse(false)
    local hTop = haloLayer:CreateTexture(nil, "BACKGROUND", nil, -1)
    hTop:SetPoint("TOPLEFT", haloLayer, "TOPLEFT", 2, 0)
    hTop:SetPoint("TOPRIGHT", haloLayer, "TOPRIGHT", -2, 0)
    hTop:SetHeight(5)
    hTop:SetBlendMode("ADD")
    local hBot = haloLayer:CreateTexture(nil, "BACKGROUND", nil, -1)
    hBot:SetPoint("BOTTOMLEFT", haloLayer, "BOTTOMLEFT", 2, 0)
    hBot:SetPoint("BOTTOMRIGHT", haloLayer, "BOTTOMRIGHT", -2, 0)
    hBot:SetHeight(5)
    hBot:SetBlendMode("ADD")
    local hLeft = haloLayer:CreateTexture(nil, "BACKGROUND", nil, -1)
    hLeft:SetPoint("TOPLEFT", haloLayer, "TOPLEFT", 0, -2)
    hLeft:SetPoint("BOTTOMLEFT", haloLayer, "BOTTOMLEFT", 0, 2)
    hLeft:SetWidth(5)
    hLeft:SetBlendMode("ADD")
    local hRight = haloLayer:CreateTexture(nil, "BACKGROUND", nil, -1)
    hRight:SetPoint("TOPRIGHT", haloLayer, "TOPRIGHT", 0, -2)
    hRight:SetPoint("BOTTOMRIGHT", haloLayer, "BOTTOMRIGHT", 0, 2)
    hRight:SetWidth(5)
    hRight:SetBlendMode("ADD")
    haloLayer.top = hTop
    haloLayer.bottom = hBot
    haloLayer.left = hLeft
    haloLayer.right = hRight
    haloLayer:Hide()
    f._focusHaloLayer = haloLayer

    local borderLayer = CreateFrame("Frame", nil, f)
    borderLayer:SetAllPoints(f)
    borderLayer:SetFrameLevel((f:GetFrameLevel() or 320) + 12)
    borderLayer:EnableMouse(false)
    local bTop = borderLayer:CreateTexture(nil, "OVERLAY", nil, 5)
    bTop:SetPoint("TOPLEFT", borderLayer, "TOPLEFT", 0, 0)
    bTop:SetPoint("TOPRIGHT", borderLayer, "TOPRIGHT", 0, 0)
    bTop:SetHeight(2)
    local bBot = borderLayer:CreateTexture(nil, "OVERLAY", nil, 5)
    bBot:SetPoint("BOTTOMLEFT", borderLayer, "BOTTOMLEFT", 0, 0)
    bBot:SetPoint("BOTTOMRIGHT", borderLayer, "BOTTOMRIGHT", 0, 0)
    bBot:SetHeight(2)
    local bLeft = borderLayer:CreateTexture(nil, "OVERLAY", nil, 5)
    bLeft:SetPoint("TOPLEFT", borderLayer, "TOPLEFT", 0, 0)
    bLeft:SetPoint("BOTTOMLEFT", borderLayer, "BOTTOMLEFT", 0, 0)
    bLeft:SetWidth(2)
    local bRight = borderLayer:CreateTexture(nil, "OVERLAY", nil, 5)
    bRight:SetPoint("TOPRIGHT", borderLayer, "TOPRIGHT", 0, 0)
    bRight:SetPoint("BOTTOMRIGHT", borderLayer, "BOTTOMRIGHT", 0, 0)
    bRight:SetWidth(2)
    local shimmerTop = borderLayer:CreateTexture(nil, "OVERLAY", nil, 6)
    shimmerTop:SetHeight(2)
    shimmerTop:SetBlendMode("ADD")
    shimmerTop:Hide()
    local shimmerBot = borderLayer:CreateTexture(nil, "OVERLAY", nil, 6)
    shimmerBot:SetHeight(2)
    shimmerBot:SetBlendMode("ADD")
    shimmerBot:Hide()
    borderLayer.top = bTop
    borderLayer.bottom = bBot
    borderLayer.left = bLeft
    borderLayer.right = bRight
    borderLayer.shimmerTop = shimmerTop
    borderLayer.shimmerBot = shimmerBot
    f._focusBorderEdges = borderLayer

    -- Top action & drag bar (separated cleanly from player info so names never clip)
    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    header:SetHeight(26)
    header:EnableMouse(true)
    f.header = header

    local gripTex1 = header:CreateTexture(nil, "ARTWORK", nil, 2)
    gripTex1:SetSize(2, 12)
    gripTex1:SetPoint("LEFT", header, "LEFT", 6, 0)
    gripTex1:SetTexture(MP_WHITE8X8)
    gripTex1:SetVertexColor(0.55, 0.62, 0.72, 0.55)
    f.dragGrip1 = gripTex1

    local gripTex2 = header:CreateTexture(nil, "ARTWORK", nil, 2)
    gripTex2:SetSize(2, 12)
    gripTex2:SetPoint("LEFT", gripTex1, "RIGHT", 2, 0)
    gripTex2:SetTexture(MP_WHITE8X8)
    gripTex2:SetVertexColor(0.55, 0.62, 0.72, 0.35)
    f.dragGrip2 = gripTex2

    header:HookScript("OnEnter", function(selfHdr)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfHdr, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Quick Reply"], 1.0, 0.85, 0.25, true)
        local mode = QuickReply:GetLockMode()
        if mode == "pos_locked" then
            GameTooltip:AddLine(L["Position Locked (Resizable) — Drag edges up, down, or sideways to resize."], 0.45, 0.85, 1.0, true)
        elseif mode == "full_locked" then
            GameTooltip:AddLine(L["Locked — Click the Padlock button to unlock movement"], 0.95, 0.78, 0.32, true)
        else
            GameTooltip:AddLine(L["Drag title bar or window anywhere to move"], 0.62, 0.70, 0.80, true)
        end
        GameTooltip:Show()
    end)
    header:HookScript("OnLeave", function(selfHdr)
        if GameTooltip and GameTooltip:IsOwned(selfHdr) then
            GameTooltip:Hide()
        end
    end)

    local btnClose = Theme:CreateButton(header, 20, 20, "X", "default")
    btnClose:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    btnClose:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["Close"], 1.0, 0.85, 0.25)
        if QuickReply:IsPersistentOpenMode() then
            GameTooltip:AddLine(L["Always Open: ESC releases typing focus and keeps this window visible. Click X to close until reopened."], 0.72, 0.78, 0.86, true)
        else
            GameTooltip:AddLine("ESC", 0.72, 0.78, 0.86)
        end
        GameTooltip:Show()
    end)
    btnClose:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then
            GameTooltip:Hide()
        end
    end)
    btnClose:SetScript("OnClick", function()
        QuickReply:SaveCurrentDraft()
        QuickReply._manualClosePending = true
        f:Hide()
    end)
    f.btnClose = btnClose

    local btnHelp = Theme:CreateHelpButton(
        header,
        L["Quick Reply Guide"],
        L["General keeps Say, Yell, Emotes & Public Channels unified; use the Channel and Filters pills to switch /s, /y, /1 or filter feeds, '+' to start a whisper, Search to filter messages, and Options to copy or customize."] .. "\n\n" .. L["Sticky bar shows the group or day at the top of the message list — click it to jump straight to the start of that block, or right-click a group bar for teammate actions."],
        L["Click '?' anytime to reopen Chromie's step-by-step Quick Reply tour."],
        20
    )
    btnHelp:SetPoint("RIGHT", btnClose, "LEFT", -2, 0)
    btnHelp:SetScript("OnClick", function()
        if GameTooltip then GameTooltip:Hide() end
        QuickReply:ShowTutorial(true)
    end)
    f.btnHelp = btnHelp

    local function QuickReplyLockTooltipFn()
        local mode = QuickReply:GetLockMode()
        if mode == "pos_locked" then
            return L["Quick Reply: Position Locked (Resizable)"], L["Window cannot be dragged by mistake, but you can resize it up, down, or sideways by dragging any edge. Click to fully lock."]
        elseif mode == "full_locked" then
            return L["Quick Reply: Fully Locked"], L["Movement and resizing are both locked. Click to unlock."]
        end
        return L["Quick Reply: Unlocked"], L["Drag the title bar to move or any edge/corner to resize. Click to lock position (keeping resize enabled)."]
    end
    f._lockTooltipFn = QuickReplyLockTooltipFn

    local btnLock = Theme:CreateButton(header, 20, 20, "", "default")
    btnLock:SetPoint("RIGHT", btnHelp, "LEFT", -2, 0)
    btnLock:SetScript("OnClick", function()
        QuickReply:ToggleLock()
    end)
    f.btnLock = btnLock

    local function QuickReplyDockTooltipFn()
        if QuickReply:IsDockedOverChat() then
            return L["Place over Official Chat"], L["Currently docked directly over Blizzard's Official Chat. Drag Quick Reply (while unlocked) to move it freely anywhere else."]
        end
        return L["Place over Official Chat"], L["Click to snap Quick Reply directly back over Blizzard's Official Chat window (matching its exact size)."]
    end
    f._dockTooltipFn = QuickReplyDockTooltipFn

    local btnDock = Theme:CreateButton(header, 20, 20, "", "default")
    btnDock:SetPoint("RIGHT", btnLock, "LEFT", -2, 0)
    btnDock:SetScript("OnClick", function()
        QuickReply:SnapOverOfficialChat()
    end)
    f.btnDock = btnDock

    local btnExpand = Theme:CreateButton(header, 20, 20, "", "default")
    btnExpand:SetPoint("RIGHT", btnDock, "LEFT", -2, 0)
    Theme:ConfigureIconButton(btnExpand, 20, 20, "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", {
        size = 16,
        color = { 0.40, 0.74, 1.0 },
        title = L["Open full conversation"],
    })
    btnExpand:SetScript("OnClick", function()
        QuickReply:SaveCurrentDraft()
        local k = QuickReply.activeKey
        f:Hide()
        if k and ns.NavigateToModule then
            ns:NavigateToModule("chat", { threadKey = k })
        elseif ns.UI and ns.UI.ShowHub then
            ns.UI:ShowHub("chat")
        end
    end)
    f.btnExpand = btnExpand

    local btnHistory = Theme:CreateButton(header, 20, 20, "", "default")
    btnHistory:SetPoint("RIGHT", btnExpand, "LEFT", -2, 0)
    Theme:ConfigureIconButton(btnHistory, 20, 20, "Interface\\Icons\\INV_Misc_PocketWatch_01", {
        size = 16,
        color = { 0.96, 0.84, 0.45 },
        title = L["Quick History"],
        desc = L["Browse saved conversation history by message type (Whispers, Battle.net, Group, Guild, Rooms, Channels)."],
    })
    btnHistory:SetScript("OnClick", function(selfBtn)
        OpenQuickReplyHistoryMenu(selfBtn)
    end)
    f.btnHistory = btnHistory

    local btnCombatLog = Theme:CreateButton(header, 20, 20, "", "default")
    btnCombatLog:SetPoint("RIGHT", btnHistory, "LEFT", -2, 0)
    Theme:ConfigureIconButton(btnCombatLog, 20, 20, "Interface\\Icons\\Ability_DualWield", {
        size = 16,
        color = { 0.96, 0.56, 0.36 },
        title = L["Logs (Combat & World)"],
        desc = L["Open Combat Log and World Log (loot, crafting, XP, achievements, and system notices) in one dedicated panel so General stays focused on conversations."],
    })
    btnCombatLog:SetScript("OnClick", function()
        QuickReply:ToggleCombatLogFrame()
    end)
    f.btnCombatLog = btnCombatLog

    header:HookScript("OnMouseUp", function(selfHdr, mouseBtn)
        if mouseBtn == "RightButton" then
            OpenQuickReplyPinsMenu(selfHdr, QuickReply.activeKey, f._headerMeta and f._headerMeta.tooltipTitle)
        end
    end)

    local btnAutoClose = Theme:CreateButton(header, 100, 20, "", "default")
    btnAutoClose:SetPoint("RIGHT", btnCombatLog, "LEFT", -3, 0)
    btnAutoClose:SetScript("OnClick", function(selfBtn)
        OpenQuickReplyAutoCloseMenu(selfBtn)
    end)
    btnAutoClose:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        local enabled, delay = QuickReply:GetAutoCloseSettings()
        local fadeEnabled, fadeDelay = QuickReply:GetFadeDelaySettings()
        local hideInCombat = (ns.db and ns.db.settings and ns.db.settings.quickReplyFadeInCombat == true) or false
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Visibility & Transparency"], 1.0, 0.85, 0.25, true)
        if not enabled then
            if fadeEnabled then
                GameTooltip:AddLine(L["Stays visible at all times and becomes transparent after %d seconds of inactivity (returns to 100%% on hover, click, or typing)."]:format(fadeDelay), 0.90, 0.93, 0.96, true)
            else
                GameTooltip:AddLine(L["Stays visible and fully opaque at all times until you close it manually with X."], 0.90, 0.93, 0.96, true)
            end
        elseif QuickReply:IsPersistentOpenMode() then
            GameTooltip:AddLine(L["Dungeon/Raid Mode: Stays open even if you press ESC or click outside, and only closes when you click X or turn off Dungeon Mode."], 0.90, 0.93, 0.96, true)
        else
            GameTooltip:AddLine(L["Closes this window automatically after %d seconds of inactivity or when you interact outside it (your typed draft is preserved)."]:format(delay), 0.90, 0.93, 0.96, true)
        end
        if hideInCombat then
            GameTooltip:AddLine(L["Combat hiding: ON (disappears during combat until it ends or you press ENTER)."], 0.96, 0.78, 0.35, true)
        else
            GameTooltip:AddLine(L["Combat hiding: OFF (stays visible during combat)."], 0.62, 0.70, 0.80, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click to set transparency seconds, auto-close, or combat hiding."], 0.45, 0.85, 1.0, true)
        GameTooltip:Show()
    end)
    btnAutoClose:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then
            GameTooltip:Hide()
        end
    end)
    f.btnAutoClose = btnAutoClose

    local toolbarLabel = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toolbarLabel:SetPoint("LEFT", gripTex2, "RIGHT", 6, 0)
    toolbarLabel:SetPoint("RIGHT", btnAutoClose, "LEFT", -6, 0)
    toolbarLabel:SetJustifyH("LEFT")
    toolbarLabel:SetWordWrap(false)
    toolbarLabel:SetTextColor(0.68, 0.75, 0.86, 0.88)
    toolbarLabel:SetText("SC")
    f.toolbarLabel = toolbarLabel

    QuickReply:BuildHeaderExtras(f, Theme)
    QuickReply:LayoutHeaderBar(f)

    -- Dedicated full-width player / channel info bar (separate from top action buttons)
    local infoBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    infoBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    infoBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -3)
    infoBar:SetHeight(34)
    infoBar:EnableMouse(true)
    f.infoBar = infoBar

    local infoWash = infoBar:CreateTexture(nil, "BACKGROUND", nil, 1)
    infoWash:SetPoint("TOPLEFT", infoBar, "TOPLEFT", 2, -2)
    infoWash:SetPoint("BOTTOMRIGHT", infoBar, "BOTTOMRIGHT", -2, 2)
    infoWash:SetTexture(MP_WHITE8X8)
    infoWash:SetVertexColor(0.25, 0.65, 0.45, 0.10)
    f.infoWash = infoWash

    local infoRule = infoBar:CreateTexture(nil, "OVERLAY", nil, 2)
    infoRule:SetHeight(1)
    infoRule:SetPoint("BOTTOMLEFT", infoBar, "BOTTOMLEFT", 2, 1)
    infoRule:SetPoint("BOTTOMRIGHT", infoBar, "BOTTOMRIGHT", -2, 1)
    infoRule:SetTexture(MP_WHITE8X8)
    infoRule:SetVertexColor(0.40, 0.80, 0.55, 0.55)
    f.infoRule = infoRule

    local toneBar = infoBar:CreateTexture(nil, "ARTWORK", nil, 2)
    toneBar:SetWidth(3)
    toneBar:SetPoint("TOPLEFT", infoBar, "TOPLEFT", 2, -3)
    toneBar:SetPoint("BOTTOMLEFT", infoBar, "BOTTOMLEFT", 2, 3)
    toneBar:SetTexture(MP_WHITE8X8)
    f.toneBar = toneBar

    local icoRim = infoBar:CreateTexture(nil, "ARTWORK", nil, 1)
    icoRim:SetSize(26, 26)
    icoRim:SetPoint("LEFT", toneBar, "RIGHT", 5, 0)
    icoRim:SetTexture(MP_WHITE8X8)
    icoRim:SetVertexColor(0.35, 0.45, 0.55, 0.55)
    f.icoRim = icoRim

    local icoBg = infoBar:CreateTexture(nil, "ARTWORK", nil, 2)
    icoBg:SetSize(24, 24)
    icoBg:SetPoint("CENTER", icoRim, "CENTER", 0, 0)
    icoBg:SetTexture(MP_WHITE8X8)
    icoBg:SetVertexColor(0.06, 0.06, 0.08, 0.96)
    f.icoBg = icoBg

    local classIco = infoBar:CreateTexture(nil, "ARTWORK", nil, 3)
    classIco:SetSize(22, 22)
    classIco:SetPoint("CENTER", icoRim, "CENTER", 0, 0)
    f.classIco = classIco

    local statusDot = infoBar:CreateTexture(nil, "OVERLAY", nil, 4)
    statusDot:SetSize(10, 10)
    statusDot:SetPoint("BOTTOMRIGHT", classIco, "BOTTOMRIGHT", 2, -2)
    statusDot:Hide()
    f.statusDot = statusDot

    local function QuickReplyMuteTooltipFn()
        local statusTxt = (QuickReply.activeKey and ns.Chat and ns.Chat.FormatThreadMuteStatus)
            and ns.Chat:FormatThreadMuteStatus(QuickReply.activeKey)
            or nil
        if statusTxt then
            return L["Notifications Muted"], statusTxt .. "\n" .. L["Click to unmute or change duration."]
        end
        return L["Silence Notifications"], L["Silence this tab for 5, 10, 30 minutes, until leaving a dungeon/raid, or permanently."]
    end

    local btnMute = Theme:CreateButton(infoBar, 20, 20, "", "default")
    btnMute:SetPoint("RIGHT", infoBar, "RIGHT", -6, 0)
    Theme:ConfigureIconButton(btnMute, 20, 20, ICON_BELL_ON, {
        size = 16,
        color = { 0.85, 0.88, 0.94 },
        tooltipFn = QuickReplyMuteTooltipFn,
    })
    btnMute:SetScript("OnClick", function(selfBtn)
        if QuickReply.activeKey then
            OpenQuickReplyMuteMenu(selfBtn, QuickReply.activeKey, f._headerMeta and f._headerMeta.tooltipTitle)
        end
    end)
    f._muteTooltipFn = QuickReplyMuteTooltipFn
    f.btnMute = btnMute

    local btnMentionCfg = Theme:CreateButton(infoBar, 20, 20, "", "primary")
    btnMentionCfg:SetPoint("RIGHT", btnMute, "LEFT", -2, 0)
    Theme:ConfigureIconButton(btnMentionCfg, 20, 20, "Interface\\Icons\\INV_Letter_15", {
        size = 15,
        texCoord = { 0.08, 0.92, 0.08, 0.92 },
        title = L["Keywords"],
        desc = L["Mentions & Keywords Radar"],
    })
    btnMentionCfg:SetScript("OnClick", function()
        if ns.SocialPanels and ns.SocialPanels.OpenMentionKeywordsModal then
            ns.SocialPanels:OpenMentionKeywordsModal()
        end
    end)
    btnMentionCfg:Hide()
    f.btnMentionCfg = btnMentionCfg

    local btnWatch = Theme:CreateButton(infoBar, 20, 20, "", "default")
    btnWatch:SetPoint("RIGHT", btnMute, "LEFT", -2, 0)
    Theme:ConfigureIconButton(btnWatch, 20, 20, "Interface\\Icons\\INV_Misc_Spyglass_03", {
        size = 16,
        title = "+ " .. L["Watchlist"],
        desc = L["Track login alerts, zone updates, and status via safe /who."],
    })
    btnWatch:SetScript("OnClick", function()
        local t = QuickReply.activeKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[QuickReply.activeKey]
        if not (t and ns.Watchlist) then return end
        local target = t.targetName or t.title
        local key = t.lookupKey or target
        if key and ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(key) then
            return
        end
        if target and target ~= "" then
            ns.Watchlist:Add(target)
            QuickReply:Refresh()
        end
    end)
    f.btnWatch = btnWatch

    local btnInvite = Theme:CreateButton(infoBar, 20, 20, "", "default")
    btnInvite:SetPoint("RIGHT", btnWatch, "LEFT", -2, 0)
    Theme:ConfigureIconButton(btnInvite, 20, 20, "Interface\\PaperDollInfoFrame\\Character-Plus", {
        size = 16,
        color = { 0.45, 0.95, 0.55 },
        title = L["Invite to Group"],
    })
    btnInvite:SetScript("OnClick", function()
        local t = QuickReply.activeKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[QuickReply.activeKey]
        local ok, target, bnetId = QuickReply:CanInviteThread(t)
        if ok and target and ns.Compat and ns.Compat.Invite then
            ns.Compat.Invite(target, bnetId)
        end
    end)
    f.btnInvite = btnInvite

    QuickReply:BuildInfoBarExtras(f, Theme)

    local statusText = infoBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPRIGHT", infoBar, "TOPRIGHT", -8, -2)
    statusText:SetJustifyH("RIGHT")
    statusText:SetWordWrap(false)
    statusText:SetText("")
    f.statusText = statusText

    local titleText = infoBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", icoRim, "TOPRIGHT", 7, 1)
    titleText:SetPoint("RIGHT", infoBar, "RIGHT", -8, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    f.titleText = titleText

    local subText = infoBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subText:SetPoint("BOTTOMLEFT", icoRim, "BOTTOMRIGHT", 7, -1)
    subText:SetPoint("RIGHT", infoBar, "RIGHT", -8, 0)
    subText:SetJustifyH("LEFT")
    subText:SetWordWrap(false)
    f.subText = subText

    infoBar:HookScript("OnEnter", function(selfInfo)
        local hm = f._headerMeta
        if not (hm and GameTooltip) then return end
        GameTooltip:SetOwner(selfInfo, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(hm.tooltipTitle or "?", 1.0, 0.85, 0.25, true)
        if hm.channelLabel and hm.channelLabel ~= "" then
            GameTooltip:AddDoubleLine(L["Chat"], hm.channelLabel, 0.72, 0.78, 0.86, hm.accentR or 0.90, hm.accentG or 0.90, hm.accentB or 0.95)
        end
        if hm.statusLabel and hm.statusLabel ~= "" then
            GameTooltip:AddDoubleLine(L["Status"], hm.statusLabel, 0.72, 0.78, 0.86, hm.statusR or 0.85, hm.statusG or 0.88, hm.statusB or 0.92)
        end
        if hm.level and hm.level > 0 then
            local clsDesc = hm.classLocalized and (hm.classLocalized .. " · ") or ""
            GameTooltip:AddDoubleLine(L["Class"], clsDesc .. L["Lv %d"]:format(hm.level), 0.72, 0.78, 0.86, 0.92, 0.94, 0.98)
        elseif hm.classLocalized and hm.classLocalized ~= "" then
            GameTooltip:AddDoubleLine(L["Class"], hm.classLocalized, 0.72, 0.78, 0.86, 0.92, 0.94, 0.98)
        end
        if hm.zone and hm.zone ~= "" then
            GameTooltip:AddDoubleLine(L["Zone"], hm.zone, 0.72, 0.78, 0.86, 0.90, 0.93, 0.96)
        end
        if hm.guild and hm.guild ~= "" then
            GameTooltip:AddDoubleLine(L["Guild"], "<" .. hm.guild .. ">", 0.72, 0.78, 0.86, 0.35, 0.88, 0.50)
        end
        if hm.relText and hm.relText ~= "" then
            GameTooltip:AddDoubleLine(L["Social"], hm.relText, 0.72, 0.78, 0.86, 0.45, 0.82, 1.0)
        end
        if hm.flagLabel and hm.flagLabel ~= "" then
            GameTooltip:AddDoubleLine(L["Status"], hm.flagLabel, 0.72, 0.78, 0.86, hm.flagR or 0.4, hm.flagG or 0.9, hm.flagB or 0.5)
        end
        if hm.noteText and hm.noteText ~= "" then
            GameTooltip:AddDoubleLine(L["Note"], hm.noteText, 0.72, 0.78, 0.86, 1.0, 0.90, 0.55)
        end
        if QuickReply.activeKey == "ch:general" then
            GameTooltip:AddLine(L["Right-click here or on General to filter notifications or switch /s, /y, /1, /2, /3..."], 0.65, 0.78, 0.92, true)
        elseif QuickReply.activeKey == "ch:party" or QuickReply.activeKey == "ch:raid" or QuickReply.activeKey == "ch:instance" then
            GameTooltip:AddLine(L["Messages are separated by day and group session — click any group header or hover any timestamp to see date and teammates."], 0.65, 0.78, 0.92, true)
        end
        GameTooltip:AddLine(L["Click the sticky bar above messages to jump to the start of a group or day block; hover · or timestamps for exact time and actions."], 0.65, 0.78, 0.92, true)
        GameTooltip:Show()
    end)
    infoBar:HookScript("OnLeave", function(selfInfo)
        if GameTooltip and GameTooltip:IsOwned(selfInfo) then
            GameTooltip:Hide()
        end
    end)
    infoBar:HookScript("OnMouseUp", function(selfInfo, mouseBtn)
        if mouseBtn == "RightButton" then
            OpenQuickReplyPinsMenu(selfInfo, QuickReply.activeKey, f._headerMeta and f._headerMeta.tooltipTitle)
        end
    end)

    -- Pending notification / draft chips bar (auto-fit & paginated, shown when >= 2 threads pending)
    local chipsBar = CreateFrame("Frame", nil, f)
    chipsBar:SetPoint("TOPLEFT", infoBar, "BOTTOMLEFT", 0, -3)
    chipsBar:SetPoint("TOPRIGHT", infoBar, "BOTTOMRIGHT", 0, -3)
    chipsBar:SetHeight(22)
    chipsBar:EnableMouseWheel(true)
    chipsBar:Hide()
    f.chipsBar = chipsBar
    f.chips = {}
    for i = 1, 6 do
        QuickReply:EnsureChipButton(i)
    end

    local btnWhispers = Theme:CreateButton(chipsBar, 94, 19, L["Whispers"], "default")
    Theme:AutoFitButton(btnWhispers, 82, 14, 134)
    btnWhispers:SetPoint("RIGHT", chipsBar, "RIGHT", 0, 0)
    btnWhispers:SetScript("OnClick", function(selfBtn)
        QuickReply:ToggleWhispersDropdown(selfBtn)
    end)
    btnWhispers:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Recent Whispers"], 1.0, 0.85, 0.25)
        GameTooltip:AddLine(L["Choose a recent Whisper or Battle.net conversation (opens upward when Quick Reply is low on screen, downward when high)."], 0.90, 0.93, 0.96, true)
        GameTooltip:Show()
    end)
    btnWhispers:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.btnWhispers = btnWhispers

    local chipsNextBtn = Theme:CreateButton(chipsBar, 20, 19, ">", "default")
    chipsNextBtn:SetPoint("RIGHT", btnWhispers, "LEFT", -4, 0)
    chipsNextBtn:SetScript("OnClick", function()
        QuickReply.chipsPage = (QuickReply.chipsPage or 1) + 1
        QuickReply._chipsFollowActive = false
        QuickReply:Refresh()
    end)
    chipsNextBtn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["Next tabs page"], 1.0, 0.85, 0.25)
        GameTooltip:Show()
    end)
    chipsNextBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    chipsNextBtn:Hide()
    f.chipsNextBtn = chipsNextBtn

    local chipsPageText = chipsBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chipsPageText:SetPoint("RIGHT", chipsNextBtn, "LEFT", -4, 0)
    chipsPageText:SetWidth(36)
    chipsPageText:SetJustifyH("CENTER")
    chipsPageText:SetText("1/1")
    chipsPageText:Hide()
    f.chipsPageText = chipsPageText

    local chipsPrevBtn = Theme:CreateButton(chipsBar, 20, 19, "<", "default")
    chipsPrevBtn:SetPoint("RIGHT", chipsPageText, "LEFT", -4, 0)
    chipsPrevBtn:SetScript("OnClick", function()
        QuickReply.chipsPage = math.max(1, (QuickReply.chipsPage or 1) - 1)
        QuickReply._chipsFollowActive = false
        QuickReply:Refresh()
    end)
    chipsPrevBtn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["Previous tabs page"], 1.0, 0.85, 0.25)
        GameTooltip:Show()
    end)
    chipsPrevBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    chipsPrevBtn:Hide()
    f.chipsPrevBtn = chipsPrevBtn

    chipsBar:SetScript("OnMouseWheel", function(_, delta)
        if delta > 0 then
            QuickReply.chipsPage = math.max(1, (QuickReply.chipsPage or 1) - 1)
        else
            QuickReply.chipsPage = (QuickReply.chipsPage or 1) + 1
        end
        QuickReply._chipsFollowActive = false
        QuickReply:Refresh()
    end)

    -- Messages viewport
    local msgBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    msgBg:SetPoint("TOPLEFT", chipsBar, "BOTTOMLEFT", 0, -3)
    msgBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 54)
    f.msgBg = msgBg

    local msgFrame = CreateFrame("ScrollingMessageFrame", nil, msgBg)
    msgFrame:SetFrameLevel((msgBg:GetFrameLevel() or 2) + 2)
    msgFrame:SetClipsChildren(true)
    msgFrame:SetPoint("TOPLEFT", msgBg, "TOPLEFT", 8, -6)
    msgFrame:SetPoint("BOTTOMRIGHT", msgBg, "BOTTOMRIGHT", -12, 6)
    msgFrame:SetFontObject(_G.ChatFontNormal or "GameFontHighlightSmall")
    msgFrame:SetJustifyH("LEFT")
    if msgFrame.SetShadowColor then
        msgFrame:SetShadowColor(0, 0, 0, 0.95)
    end
    if msgFrame.SetShadowOffset then
        msgFrame:SetShadowOffset(1, -1)
    end
    if msgFrame.SetSpacing then
        msgFrame:SetSpacing(3)
    end
    if msgFrame.SetIndentedWordWrap then
        msgFrame:SetIndentedWordWrap(true)
    end
    if msgFrame.SetInsertMode then
        msgFrame:SetInsertMode("BOTTOM")
    end
    msgFrame:SetFading(false)
    msgFrame:SetMaxLines(260)
    msgFrame:EnableMouse(true)
    if msgFrame.SetHyperlinksEnabled then
        msgFrame:SetHyperlinksEnabled(true)
    end
    msgFrame:EnableMouseWheel(true)
    f.msgFrame = msgFrame

    local btnScrollBottom = Theme:CreateButton(msgBg, 74, 20, "v " .. L["Latest"], "default")
    Theme:AutoFitButton(btnScrollBottom, 60, 12, 118)
    btnScrollBottom._scLastPillTxt = "v " .. L["Latest"]
    btnScrollBottom:SetPoint("BOTTOMRIGHT", msgFrame, "BOTTOMRIGHT", -4, 4)
    btnScrollBottom:SetFrameLevel((msgFrame:GetFrameLevel() or 2) + 5)
    btnScrollBottom:Hide()
    btnScrollBottom:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["Jump to latest messages"], 1.0, 0.85, 0.25)
        GameTooltip:Show()
    end)
    btnScrollBottom:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)
    btnScrollBottom:SetScript("OnClick", function()
        if msgFrame.ScrollToBottom then
            msgFrame:ScrollToBottom()
        end
        QuickReply:SyncScrollBottomPill(f, true)
        QuickReply:UpdateMsgScrollbar(f)
        QuickReply:SyncStickySectionHeader(f)
    end)
    f.btnScrollBottom = btnScrollBottom

    local inlineNotice = CreateFrame("Frame", nil, msgBg, "BackdropTemplate")
    inlineNotice:SetHeight(24)
    inlineNotice:SetPoint("BOTTOMLEFT", msgBg, "BOTTOMLEFT", 6, 5)
    inlineNotice:SetPoint("BOTTOMRIGHT", msgBg, "BOTTOMRIGHT", -6, 5)
    inlineNotice:SetFrameLevel((msgFrame:GetFrameLevel() or 2) + 8)
    local nSolid = inlineNotice:CreateTexture(nil, "BACKGROUND", nil, -8)
    nSolid:SetAllPoints()
    nSolid:SetTexture(QR_WHITE8X8)
    nSolid:SetVertexColor(0.11, 0.10, 0.10, 1.0)
    inlineNotice._solidBg = nSolid
    local nAccent = inlineNotice:CreateTexture(nil, "OVERLAY", nil, 1)
    nAccent:SetWidth(3)
    nAccent:SetPoint("TOPLEFT", inlineNotice, "TOPLEFT", 1, -2)
    nAccent:SetPoint("BOTTOMLEFT", inlineNotice, "BOTTOMLEFT", 1, 2)
    nAccent:SetTexture(QR_WHITE8X8)
    nAccent:SetVertexColor(0.95, 0.42, 0.30, 1.0)
    local nIco = inlineNotice:CreateTexture(nil, "OVERLAY", nil, 2)
    nIco:SetSize(14, 14)
    nIco:SetPoint("LEFT", nAccent, "RIGHT", 6, 0)
    nIco:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    local nTxt = inlineNotice:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nTxt:SetPoint("LEFT", nIco, "RIGHT", 6, 0)
    nTxt:SetPoint("RIGHT", inlineNotice, "RIGHT", -8, 0)
    nTxt:SetJustifyH("LEFT")
    nTxt:SetWordWrap(false)
    nTxt:SetTextColor(1.0, 0.88, 0.72)
    inlineNotice._txt = nTxt
    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(inlineNotice, "surface")
    end
    inlineNotice:Hide()
    f.inlineNotice = inlineNotice
    f:HookScript("OnHide", function()
        if f.inlineNotice then
            f.inlineNotice:Hide()
        end
    end)

    msgFrame:SetScript("OnMouseWheel", function(selfMsg, delta)
        if IsShiftKeyDown and IsShiftKeyDown() then
            if delta > 0 and selfMsg.ScrollToTop then
                selfMsg:ScrollToTop()
            elseif delta < 0 and selfMsg.ScrollToBottom then
                selfMsg:ScrollToBottom()
            end
        elseif IsControlKeyDown and IsControlKeyDown() then
            for _ = 1, 4 do
                if delta > 0 and selfMsg.PageUp then
                    selfMsg:PageUp()
                elseif delta < 0 and selfMsg.PageDown then
                    selfMsg:PageDown()
                elseif delta > 0 then
                    selfMsg:ScrollUp()
                else
                    selfMsg:ScrollDown()
                end
            end
        else
            if delta > 0 then
                selfMsg:ScrollUp()
            else
                selfMsg:ScrollDown()
            end
        end
        local nowT = GetTime()
        QuickReply.interactedOutside = false
        QuickReply._lastInteractAt = nowT
        QuickReply.lastInputAt = nowT
        QuickReply._lastOpaqueActivityAt = nowT
        QuickReply.idleCountdown = nil
        QuickReply:SyncScrollBottomPill(f, false)
        QuickReply:UpdateMsgScrollbar(f)
        QuickReply:SyncStickySectionHeader(f)
    end)
    f:HookScript("OnMouseDown", function()
        local nowT = GetTime()
        QuickReply.interactedOutside = false
        QuickReply._lastInteractAt = nowT
        QuickReply.lastInputAt = nowT
        QuickReply._lastOpaqueActivityAt = nowT
        QuickReply:ApplyCombatFadeStep(0, true)
    end)
    f:HookScript("OnEnter", function()
        local nowT = GetTime()
        QuickReply._lastInteractAt = nowT
        QuickReply._lastOpaqueActivityAt = nowT
        QuickReply:ApplyCombatFadeStep(0.016, false)
    end)
    QuickReply:AttachMsgFrameHandlers(f, msgFrame, Theme)
    QuickReply:BuildMsgViewportExtras(f, Theme)

    BuildQuickReplyPingsBar(f, Theme)

    if Theme and Theme.MakeMovable then
        Theme:MakeMovable(f, {
            key = "quickReply",
            skipAutoRestore = true,
            handles = { header, infoBar, chipsBar, f.msgSearchBar, msgBg, msgFrame, f.quickPingsBar },
            onStart = function()
                QuickReply:HideWhispersDropdown()
            end,
            onStop = function()
                QuickReply._userDraggedThisOpen = true
                if ns.db and ns.db.settings and ns.db.settings.quickReplyDockToChat ~= false then
                    ns.db.settings.quickReplyDockToChat = false
                end
                QuickReply:UpdateDockButton()
                QuickReply:UpdateWhispersButton()
                if ns.Emit then
                    ns:Emit("SETTINGS_UPDATED")
                end
                if ns.Settings and ns.Settings.Refresh then
                    ns.Settings:Refresh()
                end
            end,
            onReset = function()
                QuickReply:SnapOverOfficialChat()
            end,
        })
    end

    -- Footer: Sleek full-width channel-prefixed input bar (prefix FontString cleanly separated from EditBox area)
    local btnSend = CreateFrame("Button", nil, f)
    btnSend:SetSize(1, 1)
    btnSend:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    btnSend:Hide()
    f.btnSend = btnSend

    local inputWrap = CreateFrame("Frame", nil, f, "BackdropTemplate")
    inputWrap:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 6)
    inputWrap:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    inputWrap:SetHeight(24)
    inputWrap:EnableMouse(true)
    local wrapSolid = inputWrap:CreateTexture(nil, "BACKGROUND", nil, -8)
    wrapSolid:SetPoint("TOPLEFT", inputWrap, "TOPLEFT", 1, -1)
    wrapSolid:SetPoint("BOTTOMRIGHT", inputWrap, "BOTTOMRIGHT", -1, 1)
    wrapSolid:SetTexture(QR_WHITE8X8)
    wrapSolid:SetVertexColor(0.03, 0.03, 0.04, 1.0)
    inputWrap._solidBg = wrapSolid
    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(inputWrap, "inset")
    end
    f.inputWrap = inputWrap

    local inputPrefixFs = inputWrap:CreateFontString(nil, "OVERLAY", _G.ChatFontNormal and "ChatFontNormal" or "GameFontHighlight")
    inputPrefixFs:SetPoint("LEFT", inputWrap, "LEFT", 10, 0)
    inputPrefixFs:SetJustifyH("LEFT")
    inputPrefixFs:SetWordWrap(false)
    inputPrefixFs:SetText("")
    f.inputPrefixFs = inputPrefixFs

    local inputBox = Theme:CreateEditBox(inputWrap, {
        name = "SocialCentralQuickReplyInput",
        width = 240,
        height = 22,
        maxLetters = 255,
        insertLinkMode = "full",
        placeholder = L["Type a quick reply..."],
    })
    inputBox._scNoBackdrop = true
    inputBox._scInputStyleSig = nil
    if inputBox.SetBackdrop then
        inputBox:SetBackdrop(nil)
    end
    inputBox:SetTextInsets(2, 7, 1, 1)
    if inputBox.placeholder then
        inputBox.placeholder:ClearAllPoints()
        inputBox.placeholder:SetPoint("LEFT", inputBox, "LEFT", 2, 0)
        inputBox.placeholder:SetPoint("RIGHT", inputBox, "RIGHT", -7, 0)
    end
    if inputBox.SetAltArrowKeyMode then
        inputBox:SetAltArrowKeyMode(false)
    end
    if inputBox.EnableKeyboard then
        pcall(inputBox.EnableKeyboard, inputBox, false)
    end
    inputBox:ClearAllPoints()
    inputBox:SetPoint("TOP", inputWrap, "TOP", 0, -1)
    inputBox:SetPoint("BOTTOM", inputWrap, "BOTTOM", 0, 1)
    inputBox:SetPoint("LEFT", inputPrefixFs, "RIGHT", 5, 0)
    inputBox:SetPoint("RIGHT", inputWrap, "RIGHT", -3, 0)
    f.inputBox = inputBox

    local charCounter = inputWrap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charCounter:SetPoint("RIGHT", inputWrap, "RIGHT", -6, 0)
    charCounter:SetJustifyH("RIGHT")
    charCounter:Hide()
    f.charCounter = charCounter

    local inputEnterHint = inputWrap:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    inputEnterHint:SetPoint("RIGHT", inputWrap, "RIGHT", -9, 0)
    inputEnterHint:SetJustifyH("RIGHT")
    inputEnterHint:SetWordWrap(false)
    inputEnterHint:SetText("ENTER")
    inputEnterHint:SetTextColor(0.46, 0.52, 0.60, 0.65)
    f.inputEnterHint = inputEnterHint

    local function UpdateQuickReplyCharCounter()
        local curKey = QuickReply.activeKey
        local curT = curKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[curKey]
        if (not curT) or curT.kind == "MENTIONS" or QuickReply:IsOfficialOnlyThread(curT) then
            charCounter:Hide()
            if f.inputEnterHint then f.inputEnterHint:Hide() end
            if inputBox.SetTextInsets then inputBox:SetTextInsets(2, 7, 1, 1) end
            return
        end
        local len = #(inputBox:GetText() or "")
        local pSt = (curKey and ns.Chat and ns.Chat.GetPeerAddonState) and ns.Chat:GetPeerAddonState(curKey) or nil
        local isAddonPacket = (curT.kind == "ROOM" or curKey == "ch:alliance" or (pSt and pSt.verified == true))
        local maxChars = isAddonPacket and 180 or 255
        if len >= (maxChars - 65) then
            if inputBox.SetTextInsets then inputBox:SetTextInsets(2, 52, 1, 1) end
            charCounter:SetText(string.format("%d/%d", len, maxChars))
            if len > maxChars then
                charCounter:SetTextColor(1.0, 0.35, 0.35)
            elseif len >= (maxChars - 20) then
                charCounter:SetTextColor(1.0, 0.72, 0.25)
            else
                charCounter:SetTextColor(0.65, 0.72, 0.80)
            end
            charCounter:Show()
            if f.inputEnterHint then f.inputEnterHint:Hide() end
        else
            local showHint = (len == 0) and ((f:GetWidth() or 444) >= 340) and (curT.kind ~= "MENTIONS")
            if inputBox.SetTextInsets then inputBox:SetTextInsets(2, showHint and 52 or 7, 1, 1) end
            charCounter:Hide()
            if f.inputEnterHint then
                f.inputEnterHint:SetShown(showHint)
            end
        end
    end
    f._updateCharCounterFn = UpdateQuickReplyCharCounter

    inputWrap:SetScript("OnMouseDown", function()
        QuickReply:FocusInputBox()
    end)
    inputWrap:SetScript("OnEnter", function()
        QuickReply:InvalidateFocusVisuals()
        QuickReply:UpdateFocusVisuals()
    end)
    inputWrap:SetScript("OnLeave", function()
        QuickReply:InvalidateFocusVisuals()
        QuickReply:UpdateFocusVisuals()
    end)

    inputBox:HookScript("OnEnter", function()
        QuickReply:InvalidateFocusVisuals()
        QuickReply:UpdateFocusVisuals()
    end)
    inputBox:HookScript("OnLeave", function()
        QuickReply:InvalidateFocusVisuals()
        QuickReply:UpdateFocusVisuals()
    end)

    inputBox:HookScript("OnMouseDown", function(selfBox)
        QuickReply:FocusInputBox()
    end)
    inputBox:HookScript("OnEditFocusGained", function(selfBox)
        if selfBox.EnableKeyboard then
            pcall(selfBox.EnableKeyboard, selfBox, true)
        end
        QuickReply:SetCombatMousePassThrough(false)
        QuickReply:ApplyCombatFadeStep(0, true)
        QuickReply:ElevateToForeground()
        if selfBox.placeholder and (selfBox:GetText() or "") == "" then
            selfBox.placeholder:SetText((QuickReply.frame and QuickReply.frame._lastInputPlaceholder) or L["Type a quick reply..."])
        end
        QuickReply.interactedOutside = false
        QuickReply.lastInputAt = GetTime()
        QuickReply._lastOpaqueActivityAt = QuickReply.lastInputAt
        QuickReply.idleCountdown = nil
        QuickReply:UpdateFocusVisuals()
        QuickReply:SyncEnterBinding()
    QuickReply:SyncQuickReplyHotkeys()
    end)
    inputBox:HookScript("OnEditFocusLost", function(selfBox)
        if selfBox.EnableKeyboard then
            pcall(selfBox.EnableKeyboard, selfBox, false)
        end
        if selfBox.placeholder and (selfBox:GetText() or "") == "" then
            selfBox.placeholder:SetText((QuickReply.frame and QuickReply.frame._lastInputPlaceholder) or L["Click here to type..."])
        end
        QuickReply._lastOpaqueActivityAt = GetTime()
        QuickReply:SaveCurrentDraft()
        QuickReply:UpdateFocusVisuals()
        QuickReply:ApplyCombatFadeStep(0.016, false)
        QuickReply:SyncEnterBinding()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if QuickReply.SyncEnterBinding then
                    QuickReply:SyncEnterBinding()
                end
            end)
        end
        QuickReply:SyncQuickReplyHotkeys()
    end)
    if inputBox.HookScript then
        pcall(inputBox.HookScript, inputBox, "OnKeyDown", function(_, key)
            if key ~= "ESCAPE" then
                QuickReply.interactedOutside = false
                QuickReply.lastInputAt = GetTime()
                QuickReply._lastOpaqueActivityAt = QuickReply.lastInputAt
                QuickReply.idleCountdown = nil
                if key == "W" and IsControlKeyDown and IsControlKeyDown()
                    and (not (IsShiftKeyDown and IsShiftKeyDown()))
                    and (not (IsAltKeyDown and IsAltKeyDown()))
                    and QuickReply.CloseActiveUnpinnedTabByCtrlW
                then
                    QuickReply:CloseActiveUnpinnedTabByCtrlW()
                elseif key == "F" and IsControlKeyDown and IsControlKeyDown()
                    and (not (IsShiftKeyDown and IsShiftKeyDown()))
                    and (not (IsAltKeyDown and IsAltKeyDown()))
                    and QuickReply.ToggleMsgSearchBar
                then
                    QuickReply:ToggleMsgSearchBar(true)
                end
            end
        end)
    end

    local function SubmitQuickReply()
        if not ns.Chat then return end
        local nowMono = (GetTime and GetTime()) or 0
        if (nowMono - (QuickReply._lastSubmitAt or 0)) < 0.05 then
            return
        end
        QuickReply._lastSubmitAt = nowMono
        local raw = inputBox:GetText() or ""
        local clean = ns.Compat and ns.Compat.Trim and ns.Compat.Trim(raw) or raw
        if clean == "" then
            QuickReply:ReleaseKeyboardFocus(true)
            if QuickReply.SyncEnterBinding then
                QuickReply:SyncEnterBinding()
            end
            return
        end
        if ns.Chat.IsSlashCommandText and ns.Chat:IsSlashCommandText(clean) then
            local okSlash, slashReason = ns.Chat:ExecuteSlashCommand(clean, true)
            if okSlash then
                PushQuickReplyHistory(clean)
                QuickReply.suppressDraftSave = true
                inputBox:SetText("")
                QuickReply.suppressDraftSave = false
                if QuickReply.activeKey then
                    ns.Chat:SetQuickReplyDraft(QuickReply.activeKey, "")
                end
                QuickReply.lastInputAt = GetTime()
                QuickReply.idleCountdown = nil
                QuickReply.lastStatusState = ""
                QuickReply:ReleaseKeyboardFocus(slashReason == "slash_prefilled")
                if QuickReply.SyncEnterBinding then
                    QuickReply:SyncEnterBinding()
                end
            elseif slashReason == "not_in_group" then
                QuickReply:ClearDraftAndInput()
                QuickReply:Refresh()
                QuickReply:ReleaseKeyboardFocus(false)
                if QuickReply.SyncEnterBinding then
                    QuickReply:SyncEnterBinding()
                end
                QuickReply:ShowInlineNotice(L["There is no active group at the moment."])
            end
            return
        end
        if not QuickReply.activeKey then return end
        local sent, sendMode = ns.Chat:SendOrOpenReply(QuickReply.activeKey, clean, true)
        if sent ~= false then
            local blizzActive = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
                or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
                or nil
            local blizzFocused = (blizzActive and blizzActive.HasFocus and blizzActive:HasFocus() == true) == true
            if sendMode == "prefilled" and not blizzFocused then
                QuickReply._combatBlockedUntil = (GetTime and GetTime() or 0) + 2.5
                QuickReply.lastStatusState = "combat_blocked"
                if f.statusText then
                    f.statusText:SetText("|cffffb347" .. L["Unavailable during combat."] .. "|r")
                    if f._syncTitleRightFn then f._syncTitleRightFn(f) end
                end
                if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
                    QuickReply:ReleaseKeyboardFocus(false)
                end
                return
            end
            PushQuickReplyHistory(clean)
            QuickReply.suppressDraftSave = true
            inputBox:SetText("")
            QuickReply.suppressDraftSave = false
            ns.Chat:SetQuickReplyDraft(QuickReply.activeKey, "")
            ns.Chat:MarkThreadRead(QuickReply.activeKey)
            QuickReply.hasTyped = true
            QuickReply.hasSentInSession = true
            QuickReply.interactedOutside = false
            QuickReply.lastInputAt = GetTime()
            QuickReply._lastOpaqueActivityAt = QuickReply.lastInputAt
            QuickReply.idleCountdown = nil
            QuickReply.lastStatusState = ""
            QuickReply:Refresh()
            UpdateBadge(false)
            if blizzFocused then
                QuickReply:SyncEnterBinding()
                QuickReply:ApplyCombatFadeStep(0.016, false)
                if sendMode == "prefilled" and f.statusText then
                    QuickReply.lastStatusState = "blizz_confirm"
                    f.statusText:SetText("|cff7aaeff" .. L["Press Enter in Official Chat"] .. "|r")
                    if f._syncTitleRightFn then f._syncTitleRightFn(f) end
                end
            else
                QuickReply:ReleaseKeyboardFocus(false)
                if QuickReply.SyncEnterBinding then
                    QuickReply:SyncEnterBinding()
                end
            end
        elseif sendMode == "not_in_group" then
            QuickReply:ClearDraftAndInput()
            QuickReply:Refresh()
            QuickReply:ReleaseKeyboardFocus(false)
            if QuickReply.SyncEnterBinding then
                QuickReply:SyncEnterBinding()
            end
            QuickReply:ShowInlineNotice(L["There is no active group at the moment."])
        elseif ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) and f.statusText then
            QuickReply._combatBlockedUntil = (GetTime and GetTime() or 0) + 2.5
            QuickReply.lastStatusState = "combat_blocked"
            f.statusText:SetText("|cffffb347" .. L["Unavailable during combat."] .. "|r")
            if f._syncTitleRightFn then f._syncTitleRightFn(f) end
        end
    end
    QuickReply._submitQuickReplyFn = SubmitQuickReply

    pcall(inputBox.SetScript, inputBox, "OnArrowPressed", function(selfBox, key)
        if key ~= "UP" and key ~= "DOWN" then return end
        local hist = QuickReply.sentHistory
        if (not hist or #hist == 0) and ns.Chat and ns.Chat.GetSentInputHistory then
            local saved = ns.Chat:GetSentInputHistory()
            if type(saved) == "table" and #saved > 0 then
                QuickReply.sentHistory = QuickReply.sentHistory or {}
                hist = QuickReply.sentHistory
                local startI = math.max(1, #saved - 24)
                for si = startI, #saved do
                    hist[#hist + 1] = saved[si]
                end
            end
        end
        if not (hist and #hist > 0) then return end
        QuickReply._historyNav = true
        if key == "UP" then
            if QuickReply.historyIdx == nil then
                QuickReply._historyDraft = selfBox:GetText() or ""
                QuickReply.historyIdx = #hist
            elseif QuickReply.historyIdx > 1 then
                QuickReply.historyIdx = QuickReply.historyIdx - 1
            end
            local val = hist[QuickReply.historyIdx] or ""
            selfBox:SetText(val)
            if selfBox.SetCursorPosition then selfBox:SetCursorPosition(#val) end
        elseif key == "DOWN" and QuickReply.historyIdx ~= nil then
            if QuickReply.historyIdx < #hist then
                QuickReply.historyIdx = QuickReply.historyIdx + 1
                local val = hist[QuickReply.historyIdx] or ""
                selfBox:SetText(val)
                if selfBox.SetCursorPosition then selfBox:SetCursorPosition(#val) end
            else
                local restore = QuickReply._historyDraft or ""
                QuickReply.historyIdx = nil
                QuickReply._historyDraft = nil
                selfBox:SetText(restore)
                if selfBox.SetCursorPosition then selfBox:SetCursorPosition(#restore) end
            end
        end
        QuickReply._historyNav = false
    end)

    btnSend:SetScript("OnClick", SubmitQuickReply)
    inputBox:SetScript("OnEnterPressed", function()
        local nowMono = (GetTime and GetTime()) or 0
        if (nowMono - (QuickReply._lastEnterFocusAt or 0)) < 0.08 then
            return
        end
        SubmitQuickReply()
    end)
    inputBox:SetScript("OnTabPressed", function()
        if not (ns.Chat and ns.Chat.GetQuickReplyThreads) then return end
        local pending = ns.Chat:GetQuickReplyThreads()
        if type(pending) ~= "table" or #pending < 2 then return end
        local curIdx = 1
        for i, item in ipairs(pending) do
            if item.key == QuickReply.activeKey then
                curIdx = i
                break
            end
        end
        local step = (IsShiftKeyDown and IsShiftKeyDown()) and -1 or 1
        local nextIdx = ((curIdx - 1 + step) % #pending) + 1
        local nextItem = pending[nextIdx]
        if nextItem and nextItem.key and nextItem.key ~= QuickReply.activeKey then
            QuickReply:SaveCurrentDraft()
            QuickReply:SelectThread(nextItem.key, true)
        end
    end)
    inputBox:SetScript("OnEscapePressed", function()
        QuickReply:SaveCurrentDraft()
        QuickReply:ReleaseKeyboardFocus()
        if QuickReply:IsPersistentOpenMode() then
            return
        end
        QuickReply._manualClosePending = true
        f:Hide()
    end)
    inputBox:HookScript("OnTextChanged", function(selfBox)
        if not QuickReply.suppressDraftSave then
            if not QuickReply._historyNav then
                QuickReply.historyIdx = nil
                QuickReply._historyDraft = nil
            end
            local txt = selfBox:GetText() or ""
            if selfBox.HasFocus and selfBox:HasFocus() and QuickReply:IsSlashAutoOpenEnabled() then
                local slashTok, restTxt = txt:match("^%s*(/[%a%d]+)%s+(.*)$")
                if slashTok then
                    local targetKey, overrideRest = QuickReply:ResolveLiveSlashThread(txt, nil, nil, true, nil, true)
                    if targetKey then
                        local finalRest = (overrideRest ~= nil) and overrideRest or (restTxt or "")
                        if QuickReply.activeKey and ns.Chat and ns.Chat.SetQuickReplyDraft then
                            ns.Chat:SetQuickReplyDraft(QuickReply.activeKey, "")
                        end
                        QuickReply:SelectThread(targetKey, true, finalRest)
                        return
                    end
                end
            end
            if txt ~= "" then
                QuickReply.hasTyped = true
            elseif not QuickReply.hasSentInSession then
                QuickReply.hasTyped = false
            end
            QuickReply.lastInputAt = GetTime()
            QuickReply.idleCountdown = nil
            QuickReply.lastStatusState = ""
            QuickReply:SaveCurrentDraft()
        end
        if f._updateCharCounterFn then
            f._updateCharCounterFn()
        end
    end)

    local function SyncQuickReplyTitleRightAnchor(selfFrame)
        if not (selfFrame and selfFrame.titleText and selfFrame.subText and selfFrame.infoBar) then return end
        local infoLeftBtn = selfFrame._infoLeftmostBtn
        if not (infoLeftBtn and infoLeftBtn.IsShown and infoLeftBtn:IsShown()) then
            infoLeftBtn = nil
            if selfFrame.btnInvite and selfFrame.btnInvite:IsShown() then
                infoLeftBtn = selfFrame.btnInvite
            elseif selfFrame.btnWatch and selfFrame.btnWatch:IsShown() then
                infoLeftBtn = selfFrame.btnWatch
            elseif selfFrame.btnCard and selfFrame.btnCard:IsShown() then
                infoLeftBtn = selfFrame.btnCard
            elseif selfFrame.btnGenChannel and selfFrame.btnGenChannel:IsShown() then
                infoLeftBtn = selfFrame.btnGenChannel
            elseif selfFrame.btnGenFilter and selfFrame.btnGenFilter:IsShown() then
                infoLeftBtn = selfFrame.btnGenFilter
            elseif selfFrame.btnMsgSearch and selfFrame.btnMsgSearch:IsShown() then
                infoLeftBtn = selfFrame.btnMsgSearch
            elseif selfFrame.btnMentionCfg and selfFrame.btnMentionCfg:IsShown() then
                infoLeftBtn = selfFrame.btnMentionCfg
            elseif selfFrame.btnMute and selfFrame.btnMute:IsShown() then
                infoLeftBtn = selfFrame.btnMute
            elseif selfFrame.btnThreadOpts and selfFrame.btnThreadOpts:IsShown() then
                infoLeftBtn = selfFrame.btnThreadOpts
            end
        end
        local st = selfFrame.statusText and selfFrame.statusText:GetText() or ""
        local hasStatus = (st ~= "")
        if selfFrame._scTitleAnchorBtn == infoLeftBtn and selfFrame._scTitleAnchorHasStatus == hasStatus then
            return
        end
        selfFrame._scTitleAnchorBtn = infoLeftBtn
        selfFrame._scTitleAnchorHasStatus = hasStatus
        if selfFrame.statusText then
            selfFrame.statusText:ClearAllPoints()
            if infoLeftBtn then
                selfFrame.statusText:SetPoint("RIGHT", infoLeftBtn, "LEFT", -6, 6)
            else
                selfFrame.statusText:SetPoint("TOPRIGHT", selfFrame.infoBar, "TOPRIGHT", -8, -2)
            end
        end
        local leftAnchor = selfFrame.icoRim or selfFrame.classIco
        selfFrame.titleText:ClearAllPoints()
        selfFrame.titleText:SetPoint("TOPLEFT", leftAnchor, "TOPRIGHT", 7, 1)
        if hasStatus and selfFrame.statusText then
            selfFrame.titleText:SetPoint("RIGHT", selfFrame.statusText, "LEFT", -6, 0)
        elseif infoLeftBtn then
            selfFrame.titleText:SetPoint("RIGHT", infoLeftBtn, "LEFT", -6, 0)
        else
            selfFrame.titleText:SetPoint("RIGHT", selfFrame.infoBar, "RIGHT", -8, 0)
        end
        selfFrame.subText:ClearAllPoints()
        selfFrame.subText:SetPoint("BOTTOMLEFT", leftAnchor, "BOTTOMRIGHT", 7, -1)
        if infoLeftBtn then
            selfFrame.subText:SetPoint("RIGHT", infoLeftBtn, "LEFT", -6, 0)
        else
            selfFrame.subText:SetPoint("RIGHT", selfFrame.infoBar, "RIGHT", -8, 0)
        end
    end
    f._syncTitleRightFn = SyncQuickReplyTitleRightAnchor

    -- Configurable inactivity auto-close ticker (zero per-frame GC via scalar memoization, detached on hide)
    local function SetStatusMemo(selfFrame, stateKey, secVal, draftFlag, formattedText)
        if QuickReply.lastStatusState ~= stateKey
            or QuickReply.lastStatusSec ~= secVal
            or QuickReply.lastStatusDraft ~= draftFlag
        then
            QuickReply.lastStatusState = stateKey
            QuickReply.lastStatusSec = secVal
            QuickReply.lastStatusDraft = draftFlag
            if selfFrame.statusText then
                selfFrame.statusText:SetText(formattedText)
            end
            SyncQuickReplyTitleRightAnchor(selfFrame)
        end
    end

    local function QuickReplyOnUpdate(selfFrame, elapsed)
        local now = GetTime()
        local dt = elapsed or 0
        local isFocusedNow = QuickReply:IsInputFocused()
        local isAutoCloseMode = not QuickReply:IsPersistentOpenMode()
        QuickReply._qrFadeAccum = (QuickReply._qrFadeAccum or 0) + dt
        QuickReply._qrPollAccum = (QuickReply._qrPollAccum or 0) + dt
        local shouldPoll = isFocusedNow or isAutoCloseMode or (QuickReply._qrPollAccum >= 0.08)

        if QuickReply._combatFadeAnimating or isFocusedNow or shouldPoll then
            local fadeDt = QuickReply._qrFadeAccum
            QuickReply._qrFadeAccum = 0
            QuickReply:ApplyCombatFadeStep(fadeDt, false)
        end

        if not QuickReply._combatFaded and (isFocusedNow or isAutoCloseMode or QuickReply._dockedOfficialFallbackHint == true) then
            QuickReply:CheckExternalMouseButtons()
        end
        if isFocusedNow or shouldPoll then
            QuickReply:UpdateFocusVisuals(now)
        end
        if not shouldPoll and not isFocusedNow then
            return
        end
        QuickReply._qrPollAccum = 0

        local curTxt = (not QuickReply:IsOfficialOnlyThread()) and (inputBox:GetText() or "") or ""
        local hasDraft = curTxt ~= ""
        local blizzActiveNow = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
            or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
            or QuickReply._activeDockedSkinEb
            or nil
        local blizzFocusedNow = (blizzActiveNow and blizzActiveNow.HasFocus and blizzActiveNow:HasFocus() == true) == true
        local waitingBlizzConfirm = blizzFocusedNow
            and QuickReply._dockedOfficialFallbackHint == true
            and QuickReply._allowTempOfficialEditUntil and now < QuickReply._allowTempOfficialEditUntil
        if waitingBlizzConfirm then
            QuickReply.idleCountdown = nil
            SetStatusMemo(selfFrame, "blizz_confirm", 0, hasDraft, "|cff7aaeff" .. L["Press Enter in Official Chat"] .. "|r")
            return
        end
        if QuickReply._combatBlockedUntil and now < QuickReply._combatBlockedUntil then
            QuickReply.idleCountdown = nil
            SetStatusMemo(selfFrame, "combat_blocked", 0, hasDraft, "|cffffb347" .. L["Unavailable during combat."] .. "|r")
            return
        end
        local dockedTypingNow = blizzFocusedNow and QuickReply._dockedOfficialInputActive == true
        local autoCloseOn, delaySec = QuickReply:GetAutoCloseSettings()
        if QuickReply:IsPersistentOpenMode() then
            QuickReply.idleCountdown = nil
            if dockedTypingNow then
                if QuickReply.lastStatusState ~= "off" then
                    SetStatusMemo(selfFrame, "off", 0, false, "")
                end
            elseif hasDraft then
                SetStatusMemo(selfFrame, "draft_off", 0, true, "|cffffd24d* " .. L["Draft"] .. "|r")
            elseif QuickReply.lastStatusState ~= "off" then
                SetStatusMemo(selfFrame, "off", 0, false, "")
            end
            -- Zero-CPU idle sleep: when settled and unfocused in persistent mode, detach OnUpdate completely
            -- and wake via events (hover/click/focus/message/combat) or a single timer for idle fade.
            local guideActive = (ns.Theme and ns.Theme.IsNpcGuideShown and ns.Theme:IsNpcGuideShown("quick_reply")) == true
            if (not isFocusedNow) and (not dockedTypingNow) and (not QuickReply._combatFadeAnimating)
                and (not selfFrame._scDragging) and (not selfFrame._scSizing) and (not guideActive)
            then
                local hoveringNow = (selfFrame.IsMouseOver and selfFrame:IsMouseOver() == true)
                local fadeOn, fadeDelay = QuickReply:GetFadeDelaySettings()
                if fadeOn and (not hoveringNow) and (not QuickReply._combatFaded) and (QuickReply._combatFadeTargetAlpha or 1.0) > 0.5 then
                    local lastAct = math.max(QuickReply._lastOpaqueActivityAt or 0, QuickReply._lastInteractAt or 0, QuickReply.lastInputAt or 0, QuickReply.openedAt or 0)
                    local rem = fadeDelay - (now - lastAct)
                    if rem > 0.05 and C_Timer and C_Timer.After then
                        local wantWakeAt = now + rem
                        QuickReply._idleWakeTargetAt = wantWakeAt
                        if (not QuickReply._idleWakeNextScheduledAt)
                            or (wantWakeAt > QuickReply._idleWakeNextScheduledAt + 0.15)
                            or (wantWakeAt < QuickReply._idleWakeNextScheduledAt - 0.25)
                            or (now >= QuickReply._idleWakeNextScheduledAt)
                        then
                            if QuickReply._idleWakeHandle and QuickReply._idleWakeHandle.Cancel then
                                QuickReply._idleWakeHandle:Cancel()
                                QuickReply._idleWakeHandle = nil
                            end
                            QuickReply._idleWakeNextScheduledAt = wantWakeAt + 0.06
                            if not QuickReply._idleWakeTimerFn then
                                QuickReply._idleWakeTimerFn = function()
                                    QuickReply._idleWakeHandle = nil
                                    local tNow = (GetTime and GetTime()) or 0
                                    if QuickReply.frame and QuickReply.frame:IsShown()
                                        and QuickReply._idleWakeTargetAt
                                        and (not QuickReply._combatFaded)
                                        and tNow >= (QuickReply._idleWakeTargetAt - 0.05)
                                    then
                                        QuickReply._idleWakeTargetAt = nil
                                        QuickReply._idleWakeNextScheduledAt = nil
                                        QuickReply:WakeOnUpdate()
                                    end
                                end
                            end
                            if C_Timer.NewTimer then
                                QuickReply._idleWakeHandle = C_Timer.NewTimer(rem + 0.06, QuickReply._idleWakeTimerFn)
                            else
                                C_Timer.After(rem + 0.06, QuickReply._idleWakeTimerFn)
                            end
                        end
                        selfFrame:SetScript("OnUpdate", nil)
                        return
                    end
                elseif not hoveringNow then
                    if QuickReply._idleWakeHandle and QuickReply._idleWakeHandle.Cancel then
                        QuickReply._idleWakeHandle:Cancel()
                        QuickReply._idleWakeHandle = nil
                    end
                    QuickReply._idleWakeTargetAt = nil
                    QuickReply._idleWakeNextScheduledAt = nil
                    selfFrame:SetScript("OnUpdate", nil)
                    if (QuickReply._refreshesSinceGc or 0) >= 8 and ns.RequestIdleGcStep then
                        QuickReply._refreshesSinceGc = 0
                        ns:RequestIdleGcStep(100, 1.5)
                    end
                    return
                end
            end
            return
        end
        local mgr = Menu and Menu.GetManager and Menu.GetManager() or nil
        local menuOpen = (QuickReply._ownMenuOpen and mgr and mgr.IsAnyMenuOpen and mgr:IsAnyMenuOpen() == true)
            or QuickReply:IsWhispersDropdownShown()
            or ((QuickReply._closeConfirmModal and QuickReply._closeConfirmModal:IsShown()) == true)
        if QuickReply._ownMenuOpen and not (mgr and mgr.IsAnyMenuOpen and mgr:IsAnyMenuOpen() == true) then
            QuickReply._ownMenuOpen = false
        end
        local tutorialOpen = (QuickReply.tutorialDialog and QuickReply.tutorialDialog:IsShown() == true)
            or (ns.Theme and ns.Theme.IsNpcGuideShown and ns.Theme:IsNpcGuideShown("quick_reply"))
        local lastActivity = math.max(QuickReply.lastInputAt or 0, QuickReply.openedAt or 0)
        local keybdOn = (not inputBox.IsKeyboardEnabled) or (inputBox:IsKeyboardEnabled() == true)
        local activelyTyping = dockedTypingNow or (inputBox:HasFocus() and keybdOn and (now - (QuickReply.lastInputAt or 0)) < 2.0)
        local canAutoClose = (QuickReply.interactedOutside == true) or ((now - lastActivity) >= 2.0)
        local hovering = (selfFrame:IsMouseOver()
            or (QuickReply._activeDockedSkinEb and QuickReply._activeDockedSkinEb._scDockedToQr and QuickReply._activeDockedSkinEb.IsMouseOver and QuickReply._activeDockedSkinEb:IsMouseOver())
            or (f.msgFrame and f.msgFrame._scHoveredHyperlink ~= nil)
            or (GameTooltip and f.msgFrame and GameTooltip:IsOwned(f.msgFrame)))
            and not (InCombatLockdown and InCombatLockdown())
        if selfFrame._scDragging or selfFrame._scSizing or menuOpen or tutorialOpen or (not canAutoClose) or activelyTyping or hovering then
            QuickReply.idleCountdown = nil
            if hasDraft then
                SetStatusMemo(selfFrame, "draft", 0, true, "|cffffd24d* " .. L["Draft"] .. "|r")
            elseif QuickReply.lastStatusState ~= "idle" then
                SetStatusMemo(selfFrame, "idle", 0, false, "")
            end
            return
        end
        local cd = QuickReply.idleCountdown
        if cd == nil or cd > delaySec then
            cd = delaySec
        end
        QuickReply.idleCountdown = cd - elapsed
        if QuickReply.idleCountdown <= 0 then
            QuickReply:ReleaseKeyboardFocus()
            QuickReply.idleCountdown = nil
            QuickReply.lastStatusState = ""
            selfFrame:Hide()
            UpdateBadge(false)
            return
        end
        local sec = math.ceil(QuickReply.idleCountdown)
        if hasDraft then
            SetStatusMemo(selfFrame, "tick_draft", sec, true, "|cff9da7b5" .. L["Closing in %ds"]:format(sec) .. "|r · |cffffd24d* " .. L["Draft"] .. "|r")
        else
            SetStatusMemo(selfFrame, "tick", sec, false, "|cff9da7b5" .. L["Closing in %ds"]:format(sec) .. "|r")
        end
    end

    QuickReply._onUpdateFn = QuickReplyOnUpdate
    function QuickReply:WakeOnUpdate()
        local qrF = self.frame
        if qrF and qrF:IsShown() and self._onUpdateFn and not qrF:GetScript("OnUpdate") then
            qrF:SetScript("OnUpdate", self._onUpdateFn)
        end
    end
    f:HookScript("OnEnter", function()
        QuickReply:WakeOnUpdate()
    end)
    f:HookScript("OnLeave", function()
        QuickReply:WakeOnUpdate()
    end)
    if f.msgFrame and f.msgFrame.HookScript then
        f.msgFrame:HookScript("OnEnter", function() QuickReply:WakeOnUpdate() end)
        f.msgFrame:HookScript("OnLeave", function() QuickReply:WakeOnUpdate() end)
    end
    if inputBox and inputBox.HookScript then
        inputBox:HookScript("OnEditFocusGained", function() QuickReply:WakeOnUpdate() end)
        inputBox:HookScript("OnEditFocusLost", function() QuickReply:WakeOnUpdate() end)
    end

    f:HookScript("OnShow", function(selfFrame)
        QuickReply._userDraggedThisOpen = false
        QuickReply._officialInputStyleSynced = nil
        QuickReply._ebRedockCount = 0
        QuickReply:HideWhispersDropdown()
        QuickReply:SyncDockGeometry()
        QuickReply:UpdateWhispersButton()
        if selfFrame.btnScrollBottom and selfFrame.msgFrame then
            selfFrame.btnScrollBottom:SetFrameLevel((selfFrame.msgFrame:GetFrameLevel() or 2) + 5)
        end
        QuickReply.idleCountdown = nil
        QuickReply.hasSentInSession = false
        QuickReply.interactedOutside = false
        QuickReply._ownMenuOpen = false
        QuickReply.openedAt = GetTime()
        local isAutoOpen = (QuickReply._openingByDungeonAuto or QuickReply._openingByPersistentAuto) == true
        QuickReply._lastInteractAt = isAutoOpen and 0 or QuickReply.openedAt
        QuickReply.lastStatusState = ""
        QuickReply.lastStatusSec = 0
        QuickReply.lastStatusDraft = false
        QuickReply.lastInputAt = QuickReply._lastInteractAt
        QuickReply._lastOpaqueActivityAt = QuickReply.openedAt
        if isAutoOpen and InCombatLockdown and InCombatLockdown() then
            QuickReply:ReleaseKeyboardFocus()
        end
        QuickReply:ApplyCombatFadeStep(0, true)
        QuickReply:SnapshotMouseButtonState()
        QuickReply:SyncEscapeCloseRegistration()
        QuickReply:UpdateAutoCloseButton()
        QuickReply:LayoutHeaderBar(selfFrame)
        QuickReply:ApplyLockState()
        QuickReply:UpdateDockButton()
        QuickReply:UpdateInputSurfaceForActiveThread()
        QuickReply:SyncEnterBinding()
        QuickReply:SyncQuickReplyHotkeys()
        if isAutoOpen and QuickReply:IsAnyBlizzardGamePanelOpen() then
            QuickReply:YieldToGameUI(true)
        else
            QuickReply:ElevateToForeground()
        end
        selfFrame:SetScript("OnUpdate", QuickReplyOnUpdate)
        if not isAutoOpen then
            QuickReply:ShowTutorialIfNeeded()
        end
    end)
    f:HookScript("OnHide", function(selfFrame)
        QuickReply:HideWhispersDropdown()
        if QuickReply._dockedOfficialInputActive or QuickReply._activeDockedSkinEb or (_G.ChatFrame1EditBox and (_G.ChatFrame1EditBox._scDockedToQr or _G.ChatFrame1EditBox._scPreDockedToQr)) then
            QuickReply:DeactivateDockedOfficialInput()
        end
        if QuickReply._closeConfirmModal and QuickReply._closeConfirmModal:IsShown() then
            QuickReply._closeConfirmModal:Hide()
        end
        selfFrame:SetScript("OnUpdate", nil)
        QuickReply:SetCombatMousePassThrough(false)
        QuickReply._combatFadeAlpha = 1.0
        QuickReply._combatFaded = false
        QuickReply._lastAppliedQrAlpha = nil
        QuickReply._lastAppliedEbAlpha = nil
        QuickReply._lastPassThroughState = nil
        QuickReply._focusDimR = nil
        QuickReply._focusDimG = nil
        QuickReply._focusDimB = nil
        QuickReply._focusDimHover = nil
        QuickReply._qrPollAccum = 0
        QuickReply._qrFadeAccum = 0
        QuickReply._combatFadeAnimating = false
        QuickReply._allowTempOfficialEditUntil = nil
        if selfFrame.btnSend then
            selfFrame.btnSend:Hide()
        end
        if selfFrame.SetAlpha then
            selfFrame:SetAlpha(1.0)
        end
        if QuickReply._manualClosePending then
            QuickReply._manualClosePending = false
            QuickReply._closedManuallyPersistent = true
            if ns.Chat and ns.Chat._IsInDungeonOrRaid and ns.Chat:_IsInDungeonOrRaid() then
                QuickReply._closedManuallyInDungeon = true
                QuickReply._dungeonAutoActive = false
            end
        end
        QuickReply:SyncEscapeCloseRegistration()
        QuickReply:ReleaseKeyboardFocus()
        if QuickReply.activeKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[QuickReply.activeKey] then
            local closedT = ns.Chat.threads[QuickReply.activeKey]
            closedT.lastReadBannerTs = nil
            closedT.lastReadBannerEntry = nil
        end
        QuickReply.idleCountdown = nil
        QuickReply.interactedOutside = false
        QuickReply._ownMenuOpen = false
        QuickReply._userDraggedThisOpen = false
        QuickReply.lastStatusState = ""
        QuickReply.lastStatusSec = 0
        QuickReply.lastStatusDraft = false
        UpdateBadge(false)
        QuickReply:SyncEnterBinding()
    QuickReply:SyncQuickReplyHotkeys()
        if QuickReply.tutorialDialog and QuickReply.tutorialDialog:IsShown() then
            QuickReply.tutorialDialog:Hide()
        end
        if ns.Theme and ns.Theme.HideNpcGuide then
            ns.Theme:HideNpcGuide("quick_reply")
        end
        if ns.RequestIdleGcStep then
            ns:RequestIdleGcStep(120, 1.0)
        end
    end)

    local function ApplyResizeBounds()
        local uw = (_G.UIParent and _G.UIParent.GetWidth and _G.UIParent:GetWidth()) or 1280
        local uh = (_G.UIParent and _G.UIParent.GetHeight and _G.UIParent:GetHeight()) or 720
        local minW, minH = 350, 210
        local maxW = math.max(minW, math.min(780, math.floor(uw - 16)))
        local maxH = math.max(minH, math.min(680, math.floor(uh - 16)))
        if f.SetResizeBounds then
            pcall(f.SetResizeBounds, f, minW, minH, maxW, maxH)
        elseif f.SetMinResize then
            pcall(f.SetMinResize, f, minW, minH)
            if f.SetMaxResize then pcall(f.SetMaxResize, f, maxW, maxH) end
        end
        return minW, minH, maxW, maxH
    end

    local function StopQrResize(saveResult)
        if f._scSizeWatch then
            f._scSizeWatch:SetScript("OnUpdate", nil)
            f._scSizeWatch:Hide()
        end
        if not f._scSizing then
            return
        end
        f._scSizing = false
        pcall(f.StopMovingOrSizing, f)
        local minW, minH, maxW, maxH = ApplyResizeBounds()
        local curW = math.floor((f:GetWidth() or 444) + 0.5)
        local curH = math.floor((f:GetHeight() or 380) + 0.5)
        local clampedW = math.max(minW, math.min(maxW, curW))
        local clampedH = math.max(minH, math.min(maxH, curH))
        if clampedW ~= curW or clampedH ~= curH then
            f:SetSize(clampedW, clampedH)
        end
        if saveResult then
            QuickReply._userDraggedThisOpen = true
            if Theme and Theme.SaveWindowSize then
                Theme:SaveWindowSize("quickReply", clampedW, clampedH)
            end
            if f._scSavePosition then
                f._scSavePosition()
            end
            if Theme and Theme.RestoreWindowPosition then
                Theme:RestoreWindowPosition(f, "quickReply", false, { allowLockedRestore = true })
            end
        end
        if f.header then f.header:SetHeight(clampedH < 250 and 23 or 25) end
        if f.infoBar then f.infoBar:SetHeight(clampedH < 250 and 29 or 32) end
        if f.chipsBar then f.chipsBar:SetHeight(clampedH < 250 and 19 or 21) end
        QuickReply:UpdateDockButton()
        QuickReply:UpdateAutoCloseButton()
        QuickReply:LayoutHeaderBar(f)
        QuickReply:UpdateWhispersButton()
        if QuickReply._lastResizeMsgW ~= clampedW then
            QuickReply._lastResizeMsgW = clampedW
            QuickReply._forceMsgRebuild = true
        end
        QuickReply:Refresh()
    end
    f._scStopResize = StopQrResize

    local function BeginQrResize(point)
        if QuickReply:IsResizeLocked() or f._scDragging then
            return
        end
        if f._scSizing then
            StopQrResize(false)
        end
        f:SetResizable(true)
        ApplyResizeBounds()
        local left, right, top, bottom = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
        if (point == "TOP" or point == "TOPRIGHT") and left and bottom then
            f:ClearAllPoints()
            f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        elseif point == "TOPLEFT" and right and bottom then
            f:ClearAllPoints()
            f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", right, bottom)
        elseif (point == "BOTTOMLEFT" or point == "LEFT") and right and top then
            f:ClearAllPoints()
            f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
        elseif left and top then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        if f.Raise then pcall(f.Raise, f) end
        f._scSizing = true
        local ok = pcall(f.StartSizing, f, point)
        if not ok then
            f._scSizing = false
            return
        end
        if not f._scSizeWatch then
            local sw = CreateFrame("Frame", nil, f)
            sw:Hide()
            f._scSizeWatch = sw
        end
        f._scSizeWatch:Show()
        f._scSizeWatch:SetScript("OnUpdate", function()
            if not f._scSizing then
                f._scSizeWatch:SetScript("OnUpdate", nil)
                f._scSizeWatch:Hide()
                return
            end
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                StopQrResize(true)
                return
            end
            local curW = math.floor((f:GetWidth() or 0) + 0.5)
            local curH = math.floor((f:GetHeight() or 0) + 0.5)
            if curW > 0 and (math.abs(curW - (f._lastLiveResizeW or 0)) >= 10 or math.abs(curH - (f._lastLiveResizeH or 0)) >= 12) then
                f._lastLiveResizeW = curW
                f._lastLiveResizeH = curH
                if f.header then f.header:SetHeight(curH < 250 and 23 or 25) end
                if f.infoBar then f.infoBar:SetHeight(curH < 250 and 29 or 32) end
                if f.chipsBar then f.chipsBar:SetHeight(curH < 250 and 19 or 21) end
                QuickReply:UpdateAutoCloseButton()
                QuickReply:LayoutHeaderBar(f)
                QuickReply:UpdateMsgScrollbar(f)
                local t = QuickReply.activeKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[QuickReply.activeKey]
                if t then
                    RefreshQuickReplyPingsBar(f, t)
                end
            end
        end)
    end

    f._scResizeGrips = {}
    local gripDefs = {
        { pt = "TOP", a1 = "TOPLEFT", x1 = 10, y1 = 2, a2 = "TOPRIGHT", x2 = -10, y2 = 2, h = 6 },
        { pt = "BOTTOM", a1 = "BOTTOMLEFT", x1 = 10, y1 = -2, a2 = "BOTTOMRIGHT", x2 = -10, y2 = -2, h = 6 },
        { pt = "LEFT", a1 = "TOPLEFT", x1 = -2, y1 = -10, a2 = "BOTTOMLEFT", x2 = -2, y2 = 10, w = 6 },
        { pt = "RIGHT", a1 = "TOPRIGHT", x1 = 2, y1 = -10, a2 = "BOTTOMRIGHT", x2 = 2, y2 = 10, w = 6 },
        { pt = "TOPLEFT", a1 = "TOPLEFT", x1 = -2, y1 = 2, w = 12, h = 12 },
        { pt = "TOPRIGHT", a1 = "TOPRIGHT", x1 = 2, y1 = 2, w = 12, h = 12 },
        { pt = "BOTTOMLEFT", a1 = "BOTTOMLEFT", x1 = -2, y1 = -2, w = 12, h = 12 },
        { pt = "BOTTOMRIGHT", a1 = "BOTTOMRIGHT", x1 = 2, y1 = -2, w = 12, h = 12, corner = true },
    }
    for _, gd in ipairs(gripDefs) do
        local g = CreateFrame("Button", nil, f)
        g:SetFrameLevel((f:GetFrameLevel() or 320) + 18)
        g:SetPoint(gd.a1, f, gd.a1, gd.x1, gd.y1)
        if gd.a2 then
            g:SetPoint(gd.a2, f, gd.a2, gd.x2, gd.y2)
        end
        if gd.w then g:SetWidth(gd.w) end
        if gd.h then g:SetHeight(gd.h) end
        local hl = g:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.95, 0.80, 0.35, 0.25)
        if gd.corner then
            g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
            g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
            g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
            f._scSizeCornerIcon = g:GetNormalTexture()
        end
        local resizePoint = gd.pt
        g:SetScript("OnMouseDown", function(_, btn)
            QuickReply:ElevateToForeground()
            if btn == "LeftButton" then
                BeginQrResize(resizePoint)
            end
        end)
        g:SetScript("OnMouseUp", function(_, btn)
            if btn == "LeftButton" then
                StopQrResize(true)
            end
        end)
        f._scResizeGrips[#f._scResizeGrips + 1] = g
    end

    QuickReply:InstallSmartZOrderHooks()
    local function AttachElevateOnMouseDown(w)
        if w and w.HookScript and not w._scQrElevateHooked then
            w._scQrElevateHooked = true
            pcall(w.HookScript, w, "OnMouseDown", function()
                QuickReply:ElevateToForeground()
            end)
        end
    end
    AttachElevateOnMouseDown(f)
    AttachElevateOnMouseDown(f.header)
    AttachElevateOnMouseDown(f.infoBar)
    AttachElevateOnMouseDown(f.chipsBar)
    AttachElevateOnMouseDown(f.msgBg)
    AttachElevateOnMouseDown(f.msgFrame)
    AttachElevateOnMouseDown(f.pingsBar)
    AttachElevateOnMouseDown(f.inputWrap)
    AttachElevateOnMouseDown(f.inputBox)
    AttachElevateOnMouseDown(f.btnWhispers)
    AttachElevateOnMouseDown(f.btnSend)
    if type(f.chips) == "table" then
        for _, cBtn in ipairs(f.chips) do
            AttachElevateOnMouseDown(cBtn)
        end
    end

    self.frame = f
    self:ApplyTheme()
    self:ApplyLockState()
    return f
end

function QuickReply:SelectThread(threadKey, focusInput, initialText)
    if not threadKey or not ns.Chat or not ns.Chat.threads then
        return false
    end
    local t = ns.Chat.threads[threadKey]
    if not t then
        return false
    end
    if not self:ShouldUseDockedOfficialInput(t) then
        self:DeactivateDockedOfficialInput()
    end
    if ns.Chat._quickReplyClosedMsgCounts then
        ns.Chat._quickReplyClosedMsgCounts[threadKey] = nil
    end
    local f = self:EnsureFrame()
    if self.activeKey and self.activeKey ~= threadKey and ns.Chat.threads[self.activeKey] then
        local prevT = ns.Chat.threads[self.activeKey]
        prevT.lastReadBannerTs = nil
        prevT.lastReadBannerEntry = nil
    end
    if self.activeKey ~= threadKey and ((self._searchQuery or "") ~= "" or (f.msgSearchBar and f.msgSearchBar:IsShown())) then
        self._searchQuery = ""
        if f.msgSearchBox then f.msgSearchBox:SetText("") end
        if f.msgSearchBar then f.msgSearchBar:Hide() end
        self:UpdateMsgBgAnchors(f)
    end
    self.activeKey = threadKey
    if (not self._openingByDungeonAuto) and (not self._openingByPersistentAuto) and threadKey ~= "mentions:radar" then
        self._lastDestinationKey = threadKey
        self._lastManualSelectAt = (GetTime and GetTime()) or 0
        if _G.ChatFrame1EditBox then
            _G.ChatFrame1EditBox._scExplicitSayAt = nil
        end
        if ns.charDb then
            ns.charDb.lastQuickReplyThreadKey = threadKey
        end
    end
    self._chipsFollowActive = true
    self.historyIdx = nil
    self._historyDraft = nil
    if ns.Chat.MarkThreadRead then
        ns.Chat:MarkThreadRead(threadKey)
    end
    local hasInitial = type(initialText) == "string" and initialText ~= ""
    local draft = hasInitial and initialText or (ns.Chat.GetQuickReplyDraft and ns.Chat:GetQuickReplyDraft(threadKey) or "")
    self.suppressDraftSave = true
    f.inputBox:SetText(draft or "")
    if f.inputBox.UpdatePlaceholder then
        f.inputBox:UpdatePlaceholder()
    end
    self.suppressDraftSave = false
    if hasInitial and ns.Chat.SetQuickReplyDraft then
        ns.Chat:SetQuickReplyDraft(threadKey, draft)
    end
    self.hasTyped = (draft ~= nil and draft ~= "")
    self.hasSentInSession = false
    self.interactedOutside = false
    local isAutoOpen = (self._openingByDungeonAuto or self._openingByPersistentAuto) == true
    self.openedAt = GetTime()
    self._lastInteractAt = isAutoOpen and 0 or self.openedAt
    self.lastInputAt = self._lastInteractAt
    self.idleCountdown = nil
    self:Refresh()
    if focusInput and f.inputBox and not isAutoOpen then
        self:FocusInputBox(hasInitial and initialText or nil)
    else
        self:ReleaseKeyboardFocus()
    end
    if self.SyncBlizzardStickyChannelForThread then
        self:SyncBlizzardStickyChannelForThread(threadKey)
    end
    UpdateBadge(false)
    return true
end

local function LayoutQuickReplyChipsBar(f, pending)
    QuickReply:UpdateWhispersButton()
    local showChips = type(pending) == "table" and #pending >= 1
    f.chipsBar:Show()
    if f.msgBg and (not f._scMsgBgAnchorsReady or (f.msgBg.GetNumPoints and f.msgBg:GetNumPoints() < 2)) then
        if QuickReply.UpdateMsgBgAnchors then
            QuickReply:UpdateMsgBgAnchors(f)
        else
            f._scMsgBgAnchorsReady = true
            local allowPings = (f._lastPingBottomAllow ~= false)
            f.msgBg:ClearAllPoints()
            f.msgBg:SetPoint("TOPLEFT", f.chipsBar, "BOTTOMLEFT", 0, -3)
            f.msgBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, allowPings and 54 or 33)
        end
    end
    if not showChips then
        if f.chipsPrevBtn then f.chipsPrevBtn:Hide() end
        if f.chipsNextBtn then f.chipsNextBtn:Hide() end
        if f.chipsPageText then f.chipsPageText:Hide() end
        if f.chips then
            for i = 1, #f.chips do
                f.chips[i]:Hide()
            end
        end
        return
    end

    local whispW = (f.btnWhispers and math.floor((f.btnWhispers._scAutoFitW or f.btnWhispers:GetWidth() or 86) + 0.5)) or 0
    local barW = math.max(96, math.floor((f:GetWidth() or 430) - 12) - whispW - 6)
    local chipCapW = (#pending >= 3) and math.min(barW, 152) or barW
    local widths = f._chipWidthsScratch
    if not widths then
        widths = {}
        f._chipWidthsScratch = widths
    else
        wipe(widths)
    end
    local totalW = 0
    local streamerOn = (ns.Compat and ns.Compat.IsStreamerMode and ns.Compat.IsStreamerMode()) == true
    local activeKeyNow = QuickReply.activeKey
    for i = 1, #pending do
        local item = pending[i]
        local btn = QuickReply:EnsureChipButton(i)
        if btn then
            local fullName = item.title or "?"
            if streamerOn
                and (item.kind == "BN_WHISPER" or tostring(fullName):find("#", 1, true))
                and ns.Compat.MaskStreamerBNetName
            then
                fullName = ns.Compat.MaskStreamerBNetName(fullName)
            end
            local isSelChip = (item.key == activeKeyNow)
            local itemUnread = item.unread or 0
            local itemDraft = item.hasDraft == true
            local itemPin = item.pinned == true
            local itemAlways = item.isAlwaysFirst == true
            local itemMuted = item.muted == true
            local needTextUpdate = (btn._fullChipTitle ~= fullName)
                or (btn._chipUnread ~= itemUnread)
                or (btn._chipHasDraft ~= itemDraft)
                or (btn._chipPinned ~= itemPin)
                or (btn._chipAlwaysFirst ~= itemAlways)
                or (btn._chipMuted ~= itemMuted)
            btn._threadKey = item.key
            btn._fullChipTitle = fullName
            btn._chipUnread = itemUnread
            btn._chipHasDraft = itemDraft
            btn._chipPinned = itemPin
            btn._chipAlwaysFirst = itemAlways
            btn._chipMuted = itemMuted
            if needTextUpdate then
                local mutePrefix = itemMuted and ("|T" .. ICON_BELL_OFF .. ":11:11:0:-1|t ") or ""
                local suffix = (itemUnread > 0) and (" |cff4ade80(" .. itemUnread .. ")|r") or (itemDraft and " |cffffd24d*|r" or "")
                ns.Theme:SetButtonText(btn, mutePrefix .. fullName .. suffix)
            end
            if btn._pinRule then
                btn._pinRule:SetShown(itemPin and not itemAlways)
            end
            if btn._scActive ~= isSelChip or needTextUpdate then
                ns.Theme:SetButtonActive(btn, isSelChip, "default")
            end
            if btn._toneRule then
                local thrObj = item.key and ns.Chat and ns.Chat.threads and ns.Chat.threads[item.key]
                local cKind = (thrObj and thrObj.kind) or item.kind or "WHISPER"
                local hasTabUnread = (itemUnread > 0 and not itemMuted)
                if btn._scToneRuleKind ~= cKind or btn._scToneRuleSel ~= isSelChip or btn._scToneRuleUnread ~= hasTabUnread then
                    btn._scToneRuleKind = cKind
                    btn._scToneRuleSel = isSelChip
                    btn._scToneRuleUnread = hasTabUnread
                    local cToneKey = ns.Theme and ns.Theme.GetChatToneForKind and ns.Theme:GetChatToneForKind(cKind)
                    local cToneSpec = cToneKey and ns.Theme.GetChatToneSpec and ns.Theme:GetChatToneSpec(cToneKey)
                    local cAcc = (cToneSpec and cToneSpec.accent) or QuickReply._DEF_MUTED
                    btn._toneRule:SetHeight(isSelChip and 3 or 2)
                    btn._toneRule:SetVertexColor(cAcc[1], cAcc[2], cAcc[3], isSelChip and 1.0 or (hasTabUnread and 0.82 or 0.45))
                end
            end
            if needTextUpdate or btn._scLastChipCapW ~= chipCapW or not btn._scAutoFitW then
                btn._scLastChipCapW = chipCapW
                ns.Theme:AutoFitButton(btn, 44, 14, chipCapW)
            end
            local bw = math.floor((btn._scAutoFitW or btn:GetWidth() or 60) + 0.5)
            widths[i] = bw
            totalW = totalW + bw + ((i > 1) and 4 or 0)
        end
    end

    for i = #pending + 1, #(f.chips or {}) do
        local oldBtn = f.chips[i]
        if oldBtn:IsShown() then
            oldBtn:Hide()
            oldBtn._scLastChipX = nil
        end
    end

    if totalW <= barW then
        QuickReply.chipsPage = 1
        QuickReply._chipsFollowActive = false
        if f.chipsPrevBtn and f.chipsPrevBtn:IsShown() then f.chipsPrevBtn:Hide() end
        if f.chipsNextBtn and f.chipsNextBtn:IsShown() then f.chipsNextBtn:Hide() end
        if f.chipsPageText and f.chipsPageText:IsShown() then f.chipsPageText:Hide() end
        local cx = 0
        for i = 1, #pending do
            local btn = f.chips[i]
            if btn then
                if btn._scLastChipX ~= cx or not btn:IsShown() then
                    btn._scLastChipX = cx
                    btn:ClearAllPoints()
                    btn:SetPoint("LEFT", f.chipsBar, "LEFT", cx, 0)
                    btn:Show()
                end
                cx = cx + (widths[i] or 60) + 4
            end
        end
        return
    end

    local navW = 92
    local availW = math.max(96, barW - navW)
    local pages = f._chipPagesScratch
    if not pages then
        pages = {}
        f._chipPagesScratch = pages
    end
    local pagePool = f._chipPageSubPool
    if not pagePool then
        pagePool = {}
        f._chipPageSubPool = pagePool
    end
    local numPages = 0
    local function AcquirePageList()
        numPages = numPages + 1
        local pl = pagePool[numPages]
        if not pl then
            pl = {}
            pagePool[numPages] = pl
        else
            wipe(pl)
        end
        pages[numPages] = pl
        return pl
    end
    local curPageList = AcquirePageList()
    local curW = 0
    local activePageIdx = nil
    for i = 1, #pending do
        local btn = f.chips[i]
        local bw = widths[i] or 60
        if btn and bw > availW then
            btn._scLastChipCapW = availW
            ns.Theme:AutoFitButton(btn, 44, 14, availW)
            bw = math.floor((btn._scAutoFitW or btn:GetWidth() or availW) + 0.5)
            widths[i] = bw
        end
        local needed = (#curPageList > 0) and (4 + bw) or bw
        if #curPageList > 0 and (curW + needed) > availW then
            curPageList = AcquirePageList()
            curPageList[1] = i
            curW = bw
        else
            curPageList[#curPageList + 1] = i
            curW = curW + needed
        end
        if pending[i].key == activeKeyNow then
            activePageIdx = numPages
        end
    end
    for pClear = numPages + 1, #pages do
        pages[pClear] = nil
    end

    if QuickReply._chipsFollowActive and activePageIdx then
        QuickReply.chipsPage = activePageIdx
    end
    QuickReply._chipsFollowActive = false

    local pageCount = math.max(1, numPages)
    local pageIdx = math.max(1, math.min(pageCount, QuickReply.chipsPage or 1))
    QuickReply.chipsPage = pageIdx

    for i = 1, #pending do
        if f.chips[i] then
            f.chips[i]:Hide()
            f.chips[i]._scLastChipX = nil
        end
    end

    local cx = 0
    local showList = pages[pageIdx]
    if showList then
        for _, idx in ipairs(showList) do
            local btn = f.chips[idx]
            if btn then
                btn._scLastChipX = cx
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", f.chipsBar, "LEFT", cx, 0)
                btn:Show()
                cx = cx + (widths[idx] or 60) + 4
            end
        end
    end

    if f.chipsPageText then
        f.chipsPageText:SetText(string.format("%d/%d", pageIdx, pageCount))
        f.chipsPageText:Show()
    end
    if f.chipsPrevBtn then
        f.chipsPrevBtn:SetEnabled(pageIdx > 1)
        f.chipsPrevBtn:Show()
    end
    if f.chipsNextBtn then
        f.chipsNextBtn:SetEnabled(pageIdx < pageCount)
        f.chipsNextBtn:Show()
    end
end

function QuickReply:Refresh()
    local f = self.frame
    if not f or not f:IsShown() or not ns.Chat then
        return
    end
    local t = self.activeKey and ns.Chat.threads and ns.Chat.threads[self.activeKey]
    if not t then
        return
    end
    self._refreshesSinceGc = (self._refreshesSinceGc or 0) + 1

    -- Tone & rich player/channel header summary
    local gTarget = (t.kind == "GENERAL" and ns.Chat and ns.Chat.GetGeneralTargetInfo) and ns.Chat:GetGeneralTargetInfo() or nil
    local effectiveKind = (gTarget and ((gTarget.channelId and "PUB_CHANNEL") or (gTarget.isYell and "LOCAL_YELL"))) or t.kind
    local toneKey = ns.Theme and ns.Theme.GetChatToneForKind and ns.Theme:GetChatToneForKind(effectiveKind) or "whisper"
    local toneSpec = ns.Theme and ns.Theme.GetChatToneSpec and ns.Theme:GetChatToneSpec(toneKey)
    local tc = (toneSpec and toneSpec.accent) or QuickReply._DEF_MUTED
    local tcHex = (toneSpec and toneSpec.hex) or "|cffffd24d"
    self._activeToneRgb = tc
    if self._lastHeaderToneR ~= tc[1] or self._lastHeaderToneG ~= tc[2] or self._lastHeaderToneB ~= tc[3] then
        self._lastHeaderToneR, self._lastHeaderToneG, self._lastHeaderToneB = tc[1], tc[2], tc[3]
        f.toneBar:SetColorTexture(tc[1], tc[2], tc[3], 0.95)
        if f.icoRim then
            f.icoRim:SetVertexColor(tc[1], tc[2], tc[3], 0.58)
        end
        if f.dragGrip1 then
            f.dragGrip1:SetVertexColor(tc[1], tc[2], tc[3], 0.75)
        end
        if f.dragGrip2 then
            f.dragGrip2:SetVertexColor(tc[1], tc[2], tc[3], 0.40)
        end
        if f.infoWash then
            if ns.Theme and ns.Theme.ApplySafeGradient then
                ns.Theme:ApplySafeGradient(f.infoWash, "HORIZONTAL", tc[1], tc[2], tc[3], 0.16, tc[1], tc[2], tc[3], 0.00)
            else
                f.infoWash:SetColorTexture(tc[1], tc[2], tc[3], 0.08)
            end
        end
        if f.infoRule then
            if ns.Theme and ns.Theme.ApplySafeGradient then
                ns.Theme:ApplySafeGradient(f.infoRule, "HORIZONTAL", tc[1], tc[2], tc[3], 0.65, tc[1], tc[2], tc[3], 0.12)
            else
                f.infoRule:SetColorTexture(tc[1], tc[2], tc[3], 0.45)
            end
        end
        if f.btnScrollBottom and f.btnScrollBottom.SetBackdropBorderColor then
            f.btnScrollBottom:SetBackdropBorderColor(tc[1], tc[2], tc[3], 0.85)
        end
        if f.msgScrollThumb and f.msgScrollThumb._tex then
            f.msgScrollThumb._tex:SetVertexColor(tc[1], tc[2], tc[3], 0.72)
        end
        if f.msgTopGlow then
            if ns.Theme and ns.Theme.ApplySafeGradient then
                ns.Theme:ApplySafeGradient(f.msgTopGlow, "VERTICAL", tc[1], tc[2], tc[3], 0.00, tc[1], tc[2], tc[3], 0.14)
            else
                f.msgTopGlow:SetColorTexture(tc[1], tc[2], tc[3], 0.05)
            end
        end
    end
    self:ApplyChatFontSize()

    local isPlayerThread = (t.kind == "WHISPER" or t.kind == "BN_WHISPER")
    local livePubInfo = (t.kind == "PUB_CHANNEL" and t.channelId and ns.Chat and ns.Chat.GetOfficialChannelInfo)
        and ns.Chat:GetOfficialChannelInfo(t.channelId)
        or nil
    local titleStr = (gTarget and gTarget.channelId and (L["General"] .. " · " .. gTarget.title))
        or (gTarget and gTarget.isYell and (L["General"] .. " · " .. L["Yell"]))
        or (livePubInfo and livePubInfo.title)
        or t.title or t.targetName or self.activeKey
    if ns.Compat and ns.Compat.IsStreamerMode and ns.Compat.IsStreamerMode() and (t.kind == "BN_WHISPER" or tostring(titleStr):find("#", 1, true)) then
        titleStr = ns.Compat.MaskStreamerBNetName(titleStr)
    end
    local lk = t.lookupKey
    if (not lk or lk == "") and ns.Compat and ns.Compat.ParseCharacterFields then
        lk = ns.Compat.ParseCharacterFields(t.targetName or titleStr)
    end
    local sRow = (lk and ns.Store and ((ns.Store.socialByLookup and ns.Store.socialByLookup[lk])
        or (ns.Store.socialDirectoryByLookup and ns.Store.socialDirectoryByLookup[lk]))) or nil
    local wl = (lk and ns.Watchlist and ns.Watchlist.GetEntry) and ns.Watchlist:GetEntry(lk) or nil
    local meta = (lk and ns.Store) and ((ns.Store.GetResolvedSocialMeta and ns.Store:GetResolvedSocialMeta(lk)) or (ns.Store.GetSocialMeta and ns.Store:GetSocialMeta(lk))) or nil

    local classFile = t.classFile or (sRow and sRow.classFile) or (wl and wl.classFile)
    local level = (sRow and sRow.level and sRow.level > 0 and sRow.level)
        or (wl and wl.level and wl.level > 0 and wl.level)
        or (t.level and t.level > 0 and t.level)
        or (ns.Chat and ns.Chat.ResolvePlayerLevel and ns.Chat:ResolvePlayerLevel(lk, t.targetName or titleStr, t.guid, t.bnetAccountID))
        or 0
    if t._hydrated == false and ns.Chat and ns.Chat.EnsureThreadHydrated then
        ns.Chat:EnsureThreadHydrated(t)
    end
    if level <= 0 and type(t.messages) == "table" then
        for i = #t.messages, 1, -1 do
            local tm = t.messages[i]
            if type(tm) == "table" and tm.incoming and not tm.isStatusNotice then
                local tmLvl = tonumber(tm.senderLevel)
                if tmLvl and tmLvl > 0 then
                    level = math.floor(tmLvl)
                    break
                end
            end
        end
    end
    if isPlayerThread and level > 0 then
        t.level = level
    end
    local zone = (sRow and sRow.area) or (wl and wl.area) or ""
    local guild = (sRow and sRow.guild) or (wl and wl.guild) or ""
    local faction = t.faction or (sRow and sRow.faction)
        or (ns.Compat and ns.Compat.ResolveCharacterFaction and ns.Compat.ResolveCharacterFaction(t.targetName or titleStr, nil, t.bnetAccountID))
    local isFav = (lk and ns.Store and ns.Store.IsSocialFavorite and ns.Store:IsSocialFavorite(lk)) == true
    local isBNet = (t.kind == "BN_WHISPER") or (sRow and sRow.sources and sRow.sources.bnet == true) or (t.bnetAccountID ~= nil)
    local isSC = (lk and ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(lk)) == true
    local isFriend = (sRow and sRow.sources and sRow.sources.friend == true) == true
    local isGuildSrc = (sRow and sRow.sources and sRow.sources.guild == true) == true
    local isRecentlySeen = (lk and ns.Chat and ns.Chat.seenOnlineChars and ns.Chat.seenOnlineChars[lk]
        and (time() - ns.Chat.seenOnlineChars[lk]) <= 900
        and not (ns.Chat.sessionOfflineChars and ns.Chat.sessionOfflineChars[lk])) == true
    local isOnline = (sRow and sRow.online == true)
        or (wl and wl.status == "online")
        or isRecentlySeen
        or (ns.Compat and ns.Compat.IsInMyGroup and ns.Compat.IsInMyGroup(t.targetName or titleStr or lk)) == true
    local isAfk = (sRow and sRow.afk == true) == true
    local isDnd = (sRow and sRow.dnd == true) == true

    if ns.Theme and ns.Theme.ResolveThreadIcon then
        local icoTex, icoTc, ir, ig, ib = ns.Theme:ResolveThreadIcon(t.kind, isPlayerThread and classFile or nil, gTarget)
        f.classIco:SetTexture(icoTex)
        if icoTc then
            f.classIco:SetTexCoord(icoTc[1], icoTc[2], icoTc[3], icoTc[4])
        else
            f.classIco:SetTexCoord(0, 1, 0, 1)
        end
        f.classIco:SetVertexColor(ir or 1, ig or 1, ib or 1, 1)
    else
        local clsCoords = (isPlayerThread and classFile and CLASS_ICON_TCOORDS) and CLASS_ICON_TCOORDS[classFile] or nil
        if clsCoords then
            f.classIco:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            f.classIco:SetTexCoord(clsCoords[1] + 0.03, clsCoords[2] - 0.03, clsCoords[3] + 0.03, clsCoords[4] - 0.03)
        else
            f.classIco:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
            f.classIco:SetTexCoord(0.15, 0.85, 0.15, 0.85)
        end
        f.classIco:SetVertexColor(1, 1, 1, 1)
    end

    if isPlayerThread then
        if isDnd then
            f.statusDot:SetTexture(FRIENDS_TEXTURE_DND or "Interface\\FriendsFrame\\StatusIcon-DnD")
        elseif isAfk then
            f.statusDot:SetTexture(FRIENDS_TEXTURE_AFK or "Interface\\FriendsFrame\\StatusIcon-Away")
        elseif isOnline then
            f.statusDot:SetTexture(FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online")
        else
            f.statusDot:SetTexture(FRIENDS_TEXTURE_OFFLINE or "Interface\\FriendsFrame\\StatusIcon-Offline")
        end
        f.statusDot:Show()
    else
        f.statusDot:Hide()
    end

    local line1Parts = f._line1PartsScratch
    if not line1Parts then
        line1Parts = {}
        f._line1PartsScratch = line1Parts
    else
        wipe(line1Parts)
    end
    if isFav and ns.Compat and ns.Compat.FavoriteStarMarkup then
        line1Parts[#line1Parts + 1] = ns.Compat.FavoriteStarMarkup(12)
    end
    if isPlayerThread and faction and ns.Compat and ns.Compat.FactionIconMarkup then
        local facM = ns.Compat.FactionIconMarkup(faction, 13)
        if facM and facM ~= "" then
            line1Parts[#line1Parts + 1] = facM
        end
    end
    local coloredName = (classFile and ns.Compat and ns.Compat.ClassHex)
        and (ns.Compat.ClassHex(classFile) .. titleStr .. "|r")
        or (tcHex .. titleStr .. "|r")
    line1Parts[#line1Parts + 1] = coloredName
    if isPlayerThread and level > 0 then
        line1Parts[#line1Parts + 1] = "|cff9da7b5[" .. L["Lv."] .. tostring(level) .. "]|r"
    end
    if isPlayerThread and isBNet and ns.Compat and ns.Compat.BNetIconMarkup then
        line1Parts[#line1Parts + 1] = ns.Compat.BNetIconMarkup(12)
    end
    if isPlayerThread and isSC and ns.Compat and ns.Compat.AddonIconMarkup then
        line1Parts[#line1Parts + 1] = ns.Compat.AddonIconMarkup(true, 12)
    end
    if isPlayerThread and (isAfk or isDnd) and ns.Compat and ns.Compat.StatusIconMarkup then
        local stM = ns.Compat.StatusIconMarkup(isDnd and "dnd" or "afk", 12)
        if stM and stM ~= "" then
            line1Parts[#line1Parts + 1] = stM
        end
    end
    f.titleText:SetText(table.concat(line1Parts, " "))

    local chanLabel = L["Whisper"]
    if t.kind == "BN_WHISPER" then chanLabel = L["Battle.net"]
    elseif t.kind == "GUILD" then
        local gName = (ns.Store and ns.Store.guildInfo and ns.Store.guildInfo.name)
            or (ns.Safe and _G.GetGuildInfo and ns.Safe.String(ns.Safe.Call(_G.GetGuildInfo, "player")))
            or nil
        local gOnline = (ns.Store and ns.Store.guildInfo and tonumber(ns.Store.guildInfo.onlineCount)) or nil
        if (not gOnline or gOnline <= 0) and GetNumGuildMembers then
            local okGm, _, onlineRaw = pcall(GetNumGuildMembers)
            if okGm and ns.Safe and ns.Safe.Number then
                gOnline = ns.Safe.Number(onlineRaw)
            end
        end
        local baseGuild = (gName and gName ~= "") and ("<" .. gName .. ">") or L["Guild Chat"]
        chanLabel = (gOnline and gOnline > 0) and (baseGuild .. " · " .. tostring(gOnline) .. " " .. L["Online"]) or baseGuild
    elseif t.kind == "OFFICER" then
        local gName = (ns.Store and ns.Store.guildInfo and ns.Store.guildInfo.name)
            or (ns.Safe and _G.GetGuildInfo and ns.Safe.String(ns.Safe.Call(_G.GetGuildInfo, "player")))
            or nil
        chanLabel = (gName and gName ~= "") and ("<" .. gName .. "> · " .. L["Officer Channel"]) or L["Officer Channel"]
    elseif t.kind == "ALLIANCE" then chanLabel = L["Allied Guilds Chat"]
    elseif t.kind == "NOTES" then chanLabel = L["Saved privately on this character · Never sent to chat"]
    elseif t.kind == "MENTIONS" then chanLabel = L["Your name & monitored keywords across chat"]
    elseif t.kind == "PARTY" then
        local inGrp = (ns.Compat and ns.Compat.IsInGroup and ns.Compat.IsInGroup()) == true
        local inRaid = (ns.Compat and ns.Compat.IsInRaid and ns.Compat.IsInRaid()) == true
        if inGrp and not inRaid then
            local cnt = (_G.GetNumGroupMembers and tonumber(_G.GetNumGroupMembers())) or 0
            chanLabel = string.format(L["%d players in group"], math.max(1, cnt))
        else
            chanLabel = L["No active group · Type /p + Space to open or browse history"]
        end
    elseif t.kind == "RAID" then
        local inRaid = (ns.Compat and ns.Compat.IsInRaid and ns.Compat.IsInRaid()) == true
        if inRaid then
            local cnt = (_G.GetNumGroupMembers and tonumber(_G.GetNumGroupMembers())) or 0
            chanLabel = string.format(L["%d players in raid"], math.max(1, cnt))
        else
            chanLabel = L["Raid"] .. " · " .. L["Not in a raid"]
        end
    elseif t.kind == "INSTANCE_CHAT" then chanLabel = L["Instance"]
    elseif t.kind == "LOCAL_SAY" then chanLabel = L["Say"]
    elseif t.kind == "LOCAL_YELL" then chanLabel = L["Yell"]
    elseif t.kind == "ROOM" then chanLabel = L["Private Room"] .. " [SC]"
    elseif t.kind == "GENERAL" then
        if gTarget and gTarget.channelId then
            local curZone = (ns.Compat and ns.Compat.CurrentZoneName and ns.Compat.CurrentZoneName()) or ""
            local zoneSuffix = (curZone ~= "" and not gTarget.name:find(curZone, 1, true)) and (" · " .. curZone) or ""
            chanLabel = string.format(L["Channel /%s · Sending to %s%s"], tostring(gTarget.channelId), gTarget.name, zoneSuffix)
        else
            chanLabel = L["Say, Yell, Loot & Public Channels"]
        end
    elseif t.kind == "PUB_CHANNEL" then
        local pubName = (livePubInfo and livePubInfo.name) or t.channelName or L["Channel"]
        local curZone = (ns.Compat and ns.Compat.CurrentZoneName and ns.Compat.CurrentZoneName()) or ""
        local zoneSuffix = (curZone ~= "" and not pubName:find(curZone, 1, true)) and (" · " .. curZone) or ""
        chanLabel = string.format(L["Channel /%s · Sending to %s%s"], tostring(t.channelId or "?"), pubName, zoneSuffix)
    end

    local subParts = f._subPartsScratch
    if not subParts then
        subParts = {}
        f._subPartsScratch = subParts
    else
        wipe(subParts)
    end
    subParts[1] = tcHex .. chanLabel .. "|r"
    if isPlayerThread and zone ~= "" then
        subParts[#subParts + 1] = "|cffc8d1de" .. zone .. "|r"
    end
    if isPlayerThread and guild ~= "" then
        subParts[#subParts + 1] = "|cff7ee787<" .. guild .. ">|r"
    end
    local noteShown = nil
    local flagLabel = nil
    local flagR, flagG, flagB = 0.4, 0.9, 0.5
    if meta and meta.flag == "AVOID" then
        subParts[#subParts + 1] = "|cfff54747" .. L["AVOID"] .. "|r"
        flagLabel = L["AVOID"]
        flagR, flagG, flagB = 0.96, 0.35, 0.35
    elseif meta and meta.flag == "GOOD" then
        subParts[#subParts + 1] = "|cff3fb950+|r"
        flagLabel = L["Good Partner (+)"]
        flagR, flagG, flagB = 0.25, 0.88, 0.45
    end
    local rawNote = (meta and meta.nickname and meta.nickname ~= "" and meta.nickname)
        or (meta and meta.note and meta.note ~= "" and meta.note)
        or (wl and wl.note and wl.note ~= "" and wl.note)
        or nil
    if rawNote then
        noteShown = self:TruncateUtf8(rawNote, 28)
        subParts[#subParts + 1] = "|cffffd24d" .. noteShown .. "|r"
    end
    f.subText:SetText(table.concat(subParts, " · "))

    local statusLbl, stR, stG, stB = L["Offline"], 0.65, 0.68, 0.74
    if not isPlayerThread then
        statusLbl, stR, stG, stB = L["Online"], 0.30, 0.90, 0.50
    elseif isDnd then
        statusLbl, stR, stG, stB = L["DND"], 0.96, 0.35, 0.35
    elseif isAfk then
        statusLbl, stR, stG, stB = L["AFK"], 0.98, 0.78, 0.25
    elseif isOnline then
        statusLbl, stR, stG, stB = L["Online"], 0.30, 0.90, 0.50
    end
    local relParts = f._relPartsScratch
    if not relParts then
        relParts = {}
        f._relPartsScratch = relParts
    else
        wipe(relParts)
    end
    if isFriend then relParts[#relParts + 1] = L["Friends"] end
    if isBNet then relParts[#relParts + 1] = L["Battle.net"] end
    if isGuildSrc then relParts[#relParts + 1] = L["Guild"] end
    if wl then relParts[#relParts + 1] = L["Watchlist"] end
    if isSC then relParts[#relParts + 1] = L["SocialCentral [SC]"] end
    local hm = f._headerMeta
    if not hm then
        hm = {}
        f._headerMeta = hm
    end
    hm.tooltipTitle = coloredName
    hm.channelLabel = chanLabel
    hm.accentR = tc[1]
    hm.accentG = tc[2]
    hm.accentB = tc[3]
    hm.statusLabel = isPlayerThread and statusLbl or nil
    hm.statusR = stR
    hm.statusG = stG
    hm.statusB = stB
    hm.level = isPlayerThread and level or 0
    hm.classLocalized = (classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or nil
    hm.zone = isPlayerThread and zone or ""
    hm.guild = isPlayerThread and guild or ""
    hm.relText = isPlayerThread and table.concat(relParts, ", ") or ""
    hm.flagLabel = flagLabel
    hm.flagR = flagR
    hm.flagG = flagG
    hm.flagB = flagB
    hm.noteText = rawNote and self:TruncateUtf8(rawNote, 60) or ""

    -- Action buttons (Invite + Watchlist)
    local curThemeKey = (ns.Theme and ns.Theme.GetThemeName and ns.Theme:GetThemeName()) or "blizzard"
    local canInv = self:CanInviteThread(t)
    f.btnInvite:SetShown(canInv == true)

    local watchKey = t.lookupKey or t.targetName
    local canWatch = isPlayerThread and watchKey ~= nil and watchKey ~= "" and ns.Watchlist ~= nil
    f.btnWatch:SetShown(canWatch)
    if canWatch then
        local watched = ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(watchKey)
        local wSig = (watched and "1:" or "0:") .. curThemeKey
        if f.btnWatch._scWatchSig ~= wSig then
            f.btnWatch._scWatchSig = wSig
            f.btnWatch:SetEnabled(not watched)
            ns.Theme:SetButtonActive(f.btnWatch, watched == true, "default")
            ns.Theme:ConfigureIconButton(
                f.btnWatch,
                20,
                20,
                watched and "Interface\\RAIDFRAME\\ReadyCheck-Ready" or "Interface\\Icons\\INV_Misc_Spyglass_03",
                {
                    size = 16,
                    disabled = watched == true,
                    title = watched and L["Watched"] or ("+ " .. L["Watchlist"]),
                    desc = watched and L["Already monitored on your Watchlist."] or L["Track login alerts, zone updates, and status via safe /who."],
                }
            )
        end
    end

    self:ApplyLockState()
    self:UpdateDockButton()
    if f.btnCombatLog and ns.Theme then
        ns.Theme:SetButtonActive(f.btnCombatLog, (self._combatLogFrame and self._combatLogFrame:IsShown()) == true, "default")
    end

    self:UpdateAutoCloseButton()
    self:LayoutHeaderBar(f)
    if f.infoBar then
        local canMuteCur = self.activeKey ~= nil and self.activeKey ~= "notes:self" and self.activeKey ~= "ch:general"
        if f.btnMute then
            f.btnMute:SetShown(canMuteCur)
            if canMuteCur then
                local isCurMuted = (ns.Chat.IsThreadMuted and ns.Chat:IsThreadMuted(self.activeKey)) == true
                local mSig = (isCurMuted and "1:" or "0:") .. curThemeKey
                if f.btnMute._scMuteSig ~= mSig then
                    f.btnMute._scMuteSig = mSig
                    ns.Theme:SetButtonActive(f.btnMute, isCurMuted, "default")
                    ns.Theme:ConfigureIconButton(
                        f.btnMute,
                        20,
                        20,
                        isCurMuted and ICON_BELL_OFF or ICON_BELL_ON,
                        {
                            size = 16,
                            color = isCurMuted and { 0.96, 0.58, 0.28 } or { 0.85, 0.88, 0.94 },
                            tooltipFn = f._muteTooltipFn,
                        }
                    )
                end
            end
        end
        if f.btnMentionCfg then
            f.btnMentionCfg:SetShown(t.kind == "MENTIONS")
        end
        self:LayoutInfoBarActions(f, {
            isGeneral = (t.kind == "GENERAL" or self.activeKey == "ch:general"),
            isPlayer = isPlayerThread,
            isMentions = (t.kind == "MENTIONS"),
            canMute = canMuteCur,
            canWatch = canWatch,
            canInvite = (canInv == true),
            toneRgb = tc,
        })
        if f._syncTitleRightFn then
            f._syncTitleRightFn(f)
        else
            f.titleText:ClearAllPoints()
            f.titleText:SetPoint("TOPLEFT", f.classIco, "TOPRIGHT", 7, -1)
            f.titleText:SetPoint("RIGHT", f.infoBar, "RIGHT", -8, 0)
            f.subText:ClearAllPoints()
            f.subText:SetPoint("BOTTOMLEFT", f.classIco, "BOTTOMRIGHT", 7, 1)
            f.subText:SetPoint("RIGHT", f.infoBar, "RIGHT", -8, 0)
        end
    end

    -- Chips bar (pending notifications + drafts + current thread)
    local pending = ns.Chat.GetQuickReplyThreads and ns.Chat:GetQuickReplyThreads() or {}
    local hasActiveInList = false
    for _, p in ipairs(pending) do
        if p.key == self.activeKey then
            hasActiveInList = true
            break
        end
    end
    if not hasActiveInList then
        local isActPinned = ns.Chat.IsQuickReplyPinned and ns.Chat:IsQuickReplyPinned(self.activeKey) == true
        local isActMuted = ns.Chat.IsThreadMuted and ns.Chat:IsThreadMuted(self.activeKey) == true
        local insertIdx = (pending[1] and pending[1].key == "ch:general") and 2 or 1
        local actRec = f._activePendingRec
        if not actRec then
            actRec = {}
            f._activePendingRec = actRec
        end
        actRec.key = self.activeKey
        actRec.title = titleStr
        actRec.kind = t.kind
        actRec.unread = 0
        actRec.hasDraft = (f.inputBox:GetText() or "") ~= ""
        actRec.pinned = isActPinned
        actRec.muted = isActMuted
        actRec.isAlwaysFirst = (self.activeKey == "ch:general")
        table.insert(pending, insertIdx, actRec)
    end

    LayoutQuickReplyChipsBar(f, pending)
    RefreshQuickReplyPingsBar(f, t)
    self:UpdateInputSurfaceForActiveThread()
    self:SyncInputStyleToOfficial(false)
    if (not self:IsOfficialOnlyThread(t)) and f.inputPrefixFs and f.inputBox and f.inputWrap then
        local pfx = ""
        if t.kind == "GENERAL" then
            if gTarget and gTarget.channelId then
                pfx = "/" .. tostring(gTarget.channelId) .. ":"
            elseif gTarget and gTarget.isYell then
                pfx = L["Yell"] .. ":"
            else
                pfx = L["Say"] .. ":"
            end
        elseif t.kind == "PARTY" then
            pfx = L["Party"] .. ":"
        elseif t.kind == "RAID" then
            pfx = L["Raid"] .. ":"
        elseif t.kind == "INSTANCE_CHAT" then
            pfx = L["Instance"] .. ":"
        elseif t.kind == "GUILD" then
            pfx = L["Guild"] .. ":"
        elseif t.kind == "OFFICER" then
            pfx = L["Officer"] .. ":"
        elseif t.kind == "ALLIANCE" then
            pfx = L["Alliance"] .. ":"
        elseif t.kind == "NOTES" then
            pfx = L["Note"] .. ":"
        elseif t.kind == "MENTIONS" then
            pfx = ""
        else
            pfx = self:TruncateUtf8(titleStr or "", 16) .. ":"
        end
        local pr, pg, pb = self:ResolveOfficialPrefixColor(t, tc)
        f.inputPrefixFs:SetWidth(0)
        f.inputPrefixFs:SetText(pfx)
        f.inputPrefixFs:SetTextColor(pr, pg, pb, 1.0)
        f.inputPrefixFs:SetShown(pfx ~= "")
        if pfx ~= "" then
            local rawPw = f.inputPrefixFs:GetStringWidth() or 0
            if rawPw > 148 then
                f.inputPrefixFs:SetWidth(148)
            end
        end
        f.inputBox:ClearAllPoints()
        f.inputBox:SetPoint("TOP", f.inputWrap, "TOP", 0, -1)
        f.inputBox:SetPoint("BOTTOM", f.inputWrap, "BOTTOM", 0, 1)
        if pfx ~= "" then
            f.inputBox:SetPoint("LEFT", f.inputPrefixFs, "RIGHT", 4, 0)
        else
            f.inputBox:SetPoint("LEFT", f.inputWrap, "LEFT", 10, 0)
        end
        f.inputBox:SetPoint("RIGHT", f.inputWrap, "RIGHT", -3, 0)
        f.inputBox:SetTextInsets(2, 52, 0, 0)
        if f.inputBox.placeholder then
            f.inputBox.placeholder:ClearAllPoints()
            f.inputBox.placeholder:SetPoint("LEFT", f.inputBox, "LEFT", 2, 0)
            f.inputBox.placeholder:SetPoint("RIGHT", f.inputBox, "RIGHT", -52, 0)
            local phTxt = self:BuildInputPlaceholder(t, titleStr, gTarget)
            f._lastInputPlaceholder = phTxt
            if t.kind == "MENTIONS" or (f.inputBox:GetText() or "") == "" then
                f.inputBox.placeholder:SetText(phTxt)
            end
        end
    end
    if f._updateCharCounterFn then
        f._updateCharCounterFn()
    end
    self:UpdateFocusVisuals()
    if f.inputBox then f.inputBox:SetEnabled((not self:IsOfficialOnlyThread(t)) and t.kind ~= "MENTIONS") end
    if f.btnSend then f.btnSend:SetEnabled(false) end

    -- Populate latest messages incrementally whenever new lines append to the active thread.
    local msgs = ns.Chat.GetThreadMessages and ns.Chat:GetThreadMessages(self.activeKey) or t.messages or {}
    local msgCount = #msgs
    local sameThread = (self._renderedThreadKey == self.activeKey)
    local prevMsgCount = self._renderedMsgCount or 0
    local unreadTargetEntry = t.lastReadBannerEntry or t.firstUnreadEntry
    local unreadTargetTs = t.lastReadBannerTs or t.firstUnreadTs
    local clickableUrls = (not ns.db or not ns.db.settings or ns.db.settings.chatClickableUrls ~= false)
    local streamerNow = (ns.Compat and ns.Compat.IsStreamerMode and ns.Compat.IsStreamerMode()) == true
    local curGuildActionRev = (ns.Chat and ns.Chat._guildActionRev) or 0
    local isGeneralThread = (self.activeKey == "ch:general" or t.kind == "GENERAL")
    local genFilterSig = (isGeneralThread and ns.Chat and ns.Chat.GetGeneralFilterSignature)
        and ns.Chat:GetGeneralFilterSignature() or ""
    local rawSearchQ = self._searchQuery or ""
    local qFold = (rawSearchQ ~= "") and ((ns.Chat and ns.Chat.FoldSearchText) and ns.Chat:FoldSearchText(rawSearchQ) or rawSearchQ:lower()) or ""
    local delivSig = ""
    if msgCount > 0 then
        local scanStart = math.max(1, msgCount - 7)
        for di = scanStart, msgCount do
            local dm = msgs[di]
            if type(dm) == "table" and not dm.incoming and dm.viaAddon then
                delivSig = delivSig .. di .. ":" .. tostring(dm.deliveryState or "") .. ";"
            end
        end
    end
    local curRenderedMsgs = (f.msgFrame.GetNumMessages and f.msgFrame:GetNumMessages()) or 0

    local filterChangedNow = isGeneralThread and (self._renderedGeneralFilterSig ~= genFilterSig)
    local incrementalStart = nil
    local noMsgChange = false
    if sameThread and not self._forceMsgRebuild and self._renderedGeneralFilterSig == genFilterSig and (self._renderedSearchFold or "") == qFold and msgCount == 0 and prevMsgCount == 0 and curRenderedMsgs == 0 then
        noMsgChange = true
    elseif sameThread
        and not self._forceMsgRebuild
        and (self._renderedSearchFold or "") == qFold
        and qFold == ""
        and msgCount > 0
        and prevMsgCount > 0
        and curRenderedMsgs > 0
        and self._renderedUnreadTarget == unreadTargetEntry
        and self._renderedClickableUrls == clickableUrls
        and self._renderedStreamerMode == streamerNow
        and self._renderedDelivSig == delivSig
        and self._renderedGuildActionRev == curGuildActionRev
        and self._renderedGeneralFilterSig == genFilterSig
    then
        if msgCount == prevMsgCount and self._renderedMsgFirst == msgs[1] and self._renderedMsgLast == msgs[msgCount] then
            noMsgChange = true
        elseif not self._showingEmptyGeneralHint then
            if msgCount > prevMsgCount and self._renderedMsgFirst == msgs[1] and self._renderedMsgLast == msgs[prevMsgCount] then
                incrementalStart = prevMsgCount + 1
            elseif self._renderedMsgLast and msgCount >= prevMsgCount then
                for backIdx = msgCount, math.max(1, msgCount - 10), -1 do
                    if msgs[backIdx] == self._renderedMsgLast then
                        if backIdx == msgCount then
                            noMsgChange = true
                        else
                            incrementalStart = backIdx + 1
                        end
                        break
                    end
                end
            end
        end
    end

    if not noMsgChange then
        local canIncrementalAppend = (incrementalStart ~= nil and incrementalStart <= msgCount)
        local wasAtBottom = (not f.msgFrame.AtBottom) or (f.msgFrame:AtBottom() ~= false)
        local deltaAdded = canIncrementalAppend and (msgCount - incrementalStart + 1) or math.max(0, msgCount - prevMsgCount)
        local prevScroll = ((sameThread and (not filterChangedNow) and (not wasAtBottom) and f.msgFrame.GetScrollOffset) and (f.msgFrame:GetScrollOffset() or 0) or 0)
        if not sameThread then
            f._scrollUnreadNew = 0
        elseif (not wasAtBottom) and deltaAdded > 0 then
            f._scrollUnreadNew = (f._scrollUnreadNew or 0) + deltaAdded
        end
        if prevScroll > 0 and deltaAdded > 0 then
            prevScroll = prevScroll + deltaAdded
        end

        self._renderedThreadKey = self.activeKey
        self._renderedMsgCount = msgCount
        self._renderedMsgFirst = msgs[1]
        self._renderedMsgLast = (msgCount > 0) and msgs[msgCount] or nil
        self._renderedUnreadTarget = unreadTargetEntry
        self._renderedClickableUrls = clickableUrls
        self._renderedStreamerMode = streamerNow
        self._renderedDelivSig = delivSig
        self._renderedGuildActionRev = curGuildActionRev
        self._renderedGeneralFilterSig = genFilterSig
        self._renderedSearchFold = qFold
        self._forceMsgRebuild = nil

        if not canIncrementalAppend then
            f.msgFrame:Clear()
            self._showingEmptyGeneralHint = nil
            self._renderedLastDayKey = nil
            self._renderedLastDateLabel = nil
            self._renderedLastGroupSessKey = nil
            self._renderedLastMsgTs = nil
            self._renderedBannerShown = nil
            self._renderedLastSenderKey = nil
            self._renderedLastSenderTs = nil
            self._renderedLastSenderTextX = nil
        end

        local trackState = nil
        if qFold == "" and ns.Chat and ns.Chat.BeginTrackedMessageRender then
            trackState = ns.Chat:BeginTrackedMessageRender(f._msgTrackState, f.msgFrame, canIncrementalAppend)
            f._msgTrackState = trackState
        else
            f._msgTrackState = nil
        end
        local function AddQrLine(txt, r, g, b)
            if trackState and ns.Chat and ns.Chat.AddTrackedMessage then
                return ns.Chat:AddTrackedMessage(f.msgFrame, trackState, txt, r, g, b)
            end
            f.msgFrame:AddMessage(txt, r, g, b)
            return (f.msgFrame.GetNumMessages and f.msgFrame:GetNumMessages()) or 0
        end

        local startIdx = canIncrementalAppend and incrementalStart or ((qFold ~= "") and 1 or math.max(1, msgCount - 149))
        local visIdx = nil
        local iterCount = math.max(0, msgCount - startIdx + 1)
        if qFold ~= "" then
            self._qrSearchVisScratch = self._qrSearchVisScratch or {}
            wipe(self._qrSearchVisScratch)
            local foldFn = ns.Chat and ns.Chat.FoldSearchText
            local scanStart = math.max(1, msgCount - 399)
            for sIdx = scanStart, msgCount do
                local sm = msgs[sIdx]
                if type(sm) == "table" and sm.text and ((not isGeneralThread) or (not ns.Chat) or (not ns.Chat.IsGeneralEntryVisible) or ns.Chat:IsGeneralEntryVisible(sm)) then
                    local hay = (sm.sender or "") .. " " .. (sm.rawText or sm.text or "")
                    local hayFold = foldFn and foldFn(ns.Chat, hay) or hay:lower()
                    if hayFold:find(qFold, 1, true) then
                        self._qrSearchVisScratch[#self._qrSearchVisScratch + 1] = sIdx
                    end
                end
            end
            visIdx = self._qrSearchVisScratch
            iterCount = #visIdx
            if f.msgSearchMatchFs then
                f.msgSearchMatchFs:SetText(string.format(L["%d matches"], iterCount))
            end
        else
            if f.msgSearchMatchFs then
                f.msgSearchMatchFs:SetText("")
            end
            if isGeneralThread and (not canIncrementalAppend) and ns.Chat and ns.Chat.CollectGeneralVisibleIndices then
                self._genVisIdxScratch = self._genVisIdxScratch or {}
                visIdx = ns.Chat:CollectGeneralVisibleIndices(msgs, 150, self._genVisIdxScratch)
                iterCount = #visIdx
            end
        end
        if f.msgEmptyLabel then
            if qFold ~= "" and iterCount == 0 then
                f.msgEmptyLabel:SetText(string.format(L["No messages match '%s'"], rawSearchQ))
                f.msgEmptyLabel:Show()
            elseif msgCount == 0 then
                f.msgEmptyLabel:SetText(L["No messages yet — press ENTER or click below to type."])
                f.msgEmptyLabel:Show()
            else
                f.msgEmptyLabel:Hide()
            end
        end
        if isGeneralThread and (not canIncrementalAppend) and qFold == "" and msgCount > 0 and iterCount == 0 then
            self._showingEmptyGeneralHint = true
            AddQrLine("|cff7f8a9c" .. L["All current messages in General are hidden by your tab filters. Right-click the General tab to customize."] .. "|r")
        elseif iterCount > 0 then
            self._showingEmptyGeneralHint = nil
            local grpRenderMap = ((t.kind == "PARTY" or t.kind == "RAID" or t.kind == "INSTANCE_CHAT") and ns.Chat and ns.Chat.GetThreadGroupRenderMap)
                and ns.Chat:GetThreadGroupRenderMap(t)
                or nil

            local todayKey = date("%Y-%m-%d")
            local yesterdayKey = date("%Y-%m-%d", time() - 86400)
            local lastDayKey = canIncrementalAppend and self._renderedLastDayKey or nil
            local lastDateLabel = canIncrementalAppend and self._renderedLastDateLabel or nil
            local lastGroupSessKey = canIncrementalAppend and self._renderedLastGroupSessKey or nil
            local lastMsgTs = canIncrementalAppend and self._renderedLastMsgTs or nil
            local bannerShown = canIncrementalAppend and (self._renderedBannerShown == true) or false
            local lastSenderKey = canIncrementalAppend and self._renderedLastSenderKey or nil
            local lastSenderTs = canIncrementalAppend and self._renderedLastSenderTs or nil
            local lastSenderTextX = canIncrementalAppend and self._renderedLastSenderTextX or nil
            for step = 1, iterCount do
                local i = visIdx and visIdx[step] or (startIdx + step - 1)
                local m = msgs[i]
                if type(m) == "table" and m.text and ((not isGeneralThread) or (not ns.Chat) or (not ns.Chat.IsGeneralEntryVisible) or ns.Chat:IsGeneralEntryVisible(m)) then
                    local mTs = tonumber(m.ts) or 0
                    local showedBreakLine = false
                    local gInfo = (not m.isStatusNotice and m.groupRosterId and grpRenderMap and grpRenderMap[m.groupRosterId]) or nil
                    local mGrpSess = gInfo and gInfo.sessKey or nil
                    if mTs > 0 then
                        local dKey = date("%Y-%m-%d", mTs)
                        if dKey ~= lastDayKey then
                            lastDayKey = dKey
                            local dLabel = (dKey == todayKey and L["Today"])
                                or (dKey == yesterdayKey and L["Yesterday"])
                                or date("%d/%m/%Y", mTs)
                            lastDateLabel = dLabel
                            local dLine = AddQrLine("|cff7f8a9c— " .. dLabel .. "|r")
                            showedBreakLine = true
                            if trackState and (not mGrpSess) and ns.Chat and ns.Chat.RecordTrackedSection then
                                ns.Chat:RecordTrackedSection(trackState, {
                                    kind = "DATE",
                                    stepId = i,
                                    bannerLineIdx = dLine,
                                    firstMsgLineIdx = dLine + 1,
                                    label = "|cff9db0c9" .. dLabel .. "|r",
                                    plainTitle = dLabel,
                                    rgb = { 0.50, 0.58, 0.68 },
                                })
                            end
                        end
                    end
                    if mGrpSess and mGrpSess ~= lastGroupSessKey then
                        lastGroupSessKey = mGrpSess
                        local grpBanner = ns.Chat and ns.Chat.FormatGroupSessionBanner and ns.Chat:FormatGroupSessionBanner(self.activeKey, i, gInfo, mTs)
                        if grpBanner then
                            local gLine = AddQrLine(grpBanner)
                            showedBreakLine = true
                            if trackState and ns.Chat and ns.Chat.RecordTrackedSection then
                                local gLbl = ns.Chat.FormatGroupSessionLabel and ns.Chat:FormatGroupSessionLabel(gInfo, mTs)
                                ns.Chat:RecordTrackedSection(trackState, {
                                    kind = "GROUP",
                                    stepId = i,
                                    bannerLineIdx = gLine,
                                    firstMsgLineIdx = gLine + 1,
                                    threadKey = self.activeKey,
                                    msgIdx = i,
                                    sessKey = mGrpSess,
                                    label = gLbl and gLbl.colored or grpBanner,
                                    plainTitle = gLbl and gLbl.label or grpBanner,
                                    rgb = gLbl and gLbl.rgb or { 0.48, 0.68, 1.0 },
                                })
                            end
                        end
                    elseif mGrpSess and mGrpSess == lastGroupSessKey and trackState and ns.Chat and ns.Chat.RefreshTrackedGroupSectionLabel then
                        ns.Chat:RefreshTrackedGroupSectionLabel(trackState, mGrpSess, gInfo, mTs)
                    elseif (not mGrpSess) and lastGroupSessKey ~= nil and not m.isStatusNotice then
                        lastGroupSessKey = nil
                    end
                    if (not showedBreakLine) and lastMsgTs and mTs > 0 and (mTs - lastMsgTs) >= 7200 and not m.isStatusNotice then
                        local clockTxt = date("%H:%M", mTs)
                        local iLine = AddQrLine("|cff6e7681— " .. clockTxt .. "|r")
                        showedBreakLine = true
                        if trackState and (not mGrpSess) and ns.Chat and ns.Chat.RecordTrackedSection then
                            local combLabel = (lastDateLabel and (lastDateLabel .. " · " .. clockTxt)) or clockTxt
                            ns.Chat:RecordTrackedSection(trackState, {
                                kind = "DATE",
                                stepId = i,
                                bannerLineIdx = iLine,
                                firstMsgLineIdx = iLine + 1,
                                label = "|cff9db0c9" .. combLabel .. "|r",
                                plainTitle = combLabel,
                                rgb = { 0.50, 0.58, 0.68 },
                            })
                        end
                    end
                    if mTs > 0 then
                        lastMsgTs = mTs
                    end
                    if (t.kind ~= "GENERAL") and not bannerShown and m.incoming and ((unreadTargetEntry and m == unreadTargetEntry) or (not unreadTargetEntry and unreadTargetTs and m.ts and m.ts >= unreadTargetTs)) then
                        bannerShown = true
                        showedBreakLine = true
                        AddQrLine("|cffffd24d» |r|cffffe89a" .. L["New Messages"] .. "|r")
                    end
                    local curSenderKey = nil
                    if (qFold == "") and (not isGeneralThread) and (t.kind ~= "NOTES") and (t.kind ~= "MENTIONS")
                        and (not m.isStatusNotice) and (not m.isSystem) and (not m.noSenderColon) and (not m.guildEventKind)
                    then
                        if m.incoming then
                            curSenderKey = "in:" .. tostring(m.senderCharName or m.sender or "?")
                        else
                            curSenderKey = "me:" .. tostring(m.targetChar or "")
                        end
                    end
                    local isSameAuthorGroup = (curSenderKey ~= nil) and (not showedBreakLine)
                        and (lastSenderKey == curSenderKey)
                        and (mTs > 0) and ((lastSenderTs or 0) > 0) and ((mTs - lastSenderTs) <= 120)
                    local tsPart
                    if ns.Chat and ns.Chat.BuildMessageTimestampPrefix then
                        tsPart = ns.Chat:BuildMessageTimestampPrefix(m.ts, i, self.activeKey, m.isStatusNotice, isSameAuthorGroup, lastSenderTs, f.msgFrame, lastSenderTextX)
                    else
                        local tsColor = isSameAuthorGroup and "|cff545c67" or "|cff6e7681"
                        local tsStr = m.ts and date("%H:%M", m.ts) or ""
                        local tsLink = (tsStr ~= "")
                            and (m.isStatusNotice and (tsColor .. "[" .. tsStr .. "]|r ") or ("|Haddon:SCentral:msgact:" .. tostring(i) .. ":" .. tostring(self.activeKey) .. "|h" .. tsColor .. "[" .. tsStr .. "]|r|h "))
                            or ""
                        tsPart = isSameAuthorGroup and (tsLink .. "|cff586069·|r ") or tsLink
                    end
                    local genTagPart = (m.generalTag and m.generalTag ~= "") and (m.generalTag .. " ") or ""
                    local senderHex = (m.classFile and ns.Compat and ns.Compat.ClassHex and ns.Compat.ClassHex(m.classFile)) or "|cffffd24d"
                    local senderLbl
                    if m.incoming and not m.isStatusNotice then
                        local mLvl = (tonumber(m.senderLevel) and tonumber(m.senderLevel) > 0 and math.floor(tonumber(m.senderLevel)))
                            or (ns.Chat and ns.Chat.ResolvePlayerLevel and ns.Chat:ResolvePlayerLevel(nil, m.senderCharName or m.sender, m.senderGuid, isPlayerThread and t.bnetAccountID or nil, true))
                            or (isPlayerThread and level > 0 and level)
                            or 0
                        if mLvl > 0 then
                            m.senderLevel = mLvl
                        end
                        local lvlTag = (mLvl > 0 and not (isPlayerThread and level > 0 and mLvl == level))
                            and (" |cff7f8a9c[" .. L["Lv."] .. tostring(mLvl) .. "]|r")
                            or ""
                        local cleanWho = tostring(m.senderCharName or m.sender or "?"):gsub("^<[^>]+>%s*", ""):gsub("[|\r\n]", "")
                        local dispSenderRaw = tostring(m.sender or "?")
                        if ns.Compat and ns.Compat.IsStreamerMode and ns.Compat.IsStreamerMode()
                            and (t.kind == "BN_WHISPER" or dispSenderRaw:find("#", 1, true))
                            and ns.Compat.MaskStreamerBNetName
                        then
                            dispSenderRaw = ns.Compat.MaskStreamerBNetName(dispSenderRaw)
                        end
                        local coloredSender = senderHex .. dispSenderRaw .. "|r"
                        local clickableSender = (cleanWho ~= "" and cleanWho ~= "?" and not cleanWho:find("#", 1, true))
                            and ("|Haddon:SCentral:w:" .. cleanWho .. "|h" .. coloredSender .. "|h")
                            or coloredSender
                        senderLbl = clickableSender .. lvlTag
                    elseif m.incoming then
                        senderLbl = senderHex .. tostring(m.sender or "?") .. "|r"
                    else
                        senderLbl = "|cff8cc2ff" .. L["You"] .. "|r"
                    end
                    local bodyTxt = tostring((t.kind == "MENTIONS" and m.rawText) or m.text)
                    if ns.Chat and ns.Chat.FormatRaidTargetTokens then
                        bodyTxt = ns.Chat:FormatRaidTargetTokens(bodyTxt)
                    end
                    if clickableUrls and ns.Chat and ns.Chat.LinkifyUrls then
                        bodyTxt = ns.Chat:LinkifyUrls(bodyTxt)
                    end
                    if m.incoming and not m.isStatusNotice and ns.Chat and ns.Chat.HighlightMentionsInline then
                        bodyTxt = ns.Chat:HighlightMentionsInline(bodyTxt, (t.kind == "MENTIONS") and nil or t.kind, m.mentionTerm)
                    end
                    local mentionBadges = ""
                    if t.kind == "MENTIONS" then
                        local chTag = m.mentionChannel and ("|cff8ab4f8[" .. m.mentionChannel .. "]|r ") or ""
                        local kwTag = m.mentionTerm and ("|cffffd24d[" .. m.mentionTerm .. "]|r ") or ""
                        mentionBadges = chTag .. kwTag
                    end
                    local tickPart = ""
                    if not m.incoming and m.viaAddon and t.kind ~= "ROOM" then
                        if m.deliveryState == "delivered" then
                            tickPart = " |cff3fb950[" .. L["ok"] .. "]|r"
                        elseif m.deliveryState == "off" or m.deliveryState == "declined" then
                            tickPart = " |cfff54747[" .. L["off"] .. "]|r"
                        else
                            tickPart = " |cff9da7b5[" .. L["sent"] .. "]|r"
                        end
                    end
                    if m.guildEventKind and ns.Chat and ns.Chat.FormatGuildEventDisplayLine then
                        local guildLine = ns.Chat:FormatGuildEventDisplayLine(m, i, self.activeKey, tsPart)
                        if guildLine then
                            AddQrLine(guildLine)
                        end
                    elseif m.noSenderColon then
                        AddQrLine(tsPart .. genTagPart .. bodyTxt, 0.93, 0.95, 0.98)
                    elseif isSameAuthorGroup then
                        AddQrLine(tsPart .. mentionBadges .. bodyTxt .. tickPart, 0.93, 0.95, 0.98)
                    else
                        local headPrefix = tsPart .. genTagPart .. mentionBadges .. senderLbl .. ": "
                        AddQrLine(headPrefix .. bodyTxt .. tickPart, 0.93, 0.95, 0.98)
                        if curSenderKey and ns.Chat and ns.Chat.MeasureMessagePrefixWidth then
                            lastSenderTextX = ns.Chat:MeasureMessagePrefixWidth(f.msgFrame, headPrefix)
                        else
                            lastSenderTextX = nil
                        end
                    end
                    if curSenderKey then
                        lastSenderKey = curSenderKey
                        if mTs > 0 then lastSenderTs = mTs end
                    else
                        lastSenderKey = nil
                        lastSenderTs = nil
                        lastSenderTextX = nil
                    end
                end
            end
            self._renderedLastDayKey = lastDayKey
            self._renderedLastDateLabel = lastDateLabel
            self._renderedLastGroupSessKey = lastGroupSessKey
            self._renderedLastMsgTs = lastMsgTs
            self._renderedBannerShown = bannerShown
            self._renderedLastSenderKey = lastSenderKey
            self._renderedLastSenderTs = lastSenderTs
            self._renderedLastSenderTextX = lastSenderTextX
        end
        if sameThread and (not wasAtBottom) and prevScroll > 0 and f.msgFrame.SetScrollOffset then
            f.msgFrame:SetScrollOffset(prevScroll)
        else
            f.msgFrame:ScrollToBottom()
        end
        self:SyncScrollBottomPill(f, false)
    end
    self:SyncStickySectionHeader(f)
    self:UpdateMsgScrollbar(f)
end

function QuickReply:OpenThread(threadKey, focusInput, initialText)
    if Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode() then
        return false
    end
    if not threadKey or not ns.Chat or not ns.Chat.threads or not ns.Chat.threads[threadKey] then
        return false
    end
    if not self._openingByDungeonAuto and not self._openingByPersistentAuto then
        self._closedManuallyPersistent = false
        self._closedManuallyInDungeon = false
        self._openedByDungeonAuto = false
    end
    if self:IsDungeonPersistentMode() then
        self._dungeonAutoActive = true
        self:SyncEscapeCloseRegistration()
    end
    local f = self:EnsureFrame()
    self._userDraggedThisOpen = false
    self:SyncDockGeometry()
    f:Show()
    if (self._openingByDungeonAuto or self._openingByPersistentAuto) and self:IsAnyBlizzardGamePanelOpen() then
        self:YieldToGameUI(true)
    else
        self:ElevateToForeground()
    end
    return self:SelectThread(threadKey, focusInput ~= false, initialText)
end

function QuickReply:OpenLatest(preferPending, preferRecentSent, focusInput)
    if Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode() then
        return false
    end
    if not ns.Chat then
        return false
    end
    local targetKey = nil
    if preferPending then
        targetKey = self:GetFirstPendingActionKey()
    elseif preferRecentSent then
        targetKey = self:GetEnterTargetThreadKey()
    end
    if not targetKey then
        targetKey = self:GetPreservedThreadKey()
    end
    if not targetKey then
        targetKey = self:GetFirstPendingActionKey()
    end
    if not targetKey and not preferRecentSent and ns.Chat.GetQuickReplyThreads then
        local pending = ns.Chat:GetQuickReplyThreads()
        if pending[1] and pending[1].key then
            targetKey = pending[1].key
        end
    end
    if not targetKey then
        return false
    end
    self._closedManuallyPersistent = false
    self._closedManuallyInDungeon = false
    self._openedByDungeonAuto = false
    if self:IsDungeonPersistentMode() then
        self._dungeonAutoActive = true
        self:SyncEscapeCloseRegistration()
    end
    local f = self:EnsureFrame()
    self._userDraggedThisOpen = false
    self:SyncDockGeometry()
    f:Show()
    self:ElevateToForeground()
    return self:SelectThread(targetKey, focusInput == true)
end

function QuickReply:OpenPreviewOrLatest(preferredPreviewKey, focusInput)
    if Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode() then
        return false
    end
    if preferredPreviewKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[preferredPreviewKey] then
        local unreadOnlyKey = self:GetFirstPendingActionKey(true)
        if not unreadOnlyKey then
            return self:OpenThread(preferredPreviewKey, focusInput == true)
        end
    end
    if self:OpenLatest(true, false, focusInput == true) then
        return true
    end
    if not ns.Chat then
        return false
    end
    local targetKey = self:GetPreservedThreadKey()
    if not targetKey and ns.Chat.GetThreadsList then
        local list = ns.Chat:GetThreadsList("all") or {}
        if list[1] and list[1].key then
            targetKey = list[1].key
        end
    end
    if not targetKey and ns.Chat.EnsurePersonalNotesThread then
        local nt = ns.Chat:EnsurePersonalNotesThread()
        if nt and nt.key then
            targetKey = nt.key
        end
    end
    if not targetKey then
        return false
    end
    self._closedManuallyPersistent = false
    self._closedManuallyInDungeon = false
    self._openedByDungeonAuto = false
    if self:IsDungeonPersistentMode() then
        self._dungeonAutoActive = true
        self:SyncEscapeCloseRegistration()
    end
    local f = self:EnsureFrame()
    self._userDraggedThisOpen = false
    self:SyncDockGeometry()
    f:Show()
    self:ElevateToForeground()
    return self:SelectThread(targetKey, focusInput == true)
end

function QuickReply:ResolveHotkeyTargetKey(targetSpec)
    if not ns.Chat then return nil end
    if targetSpec == "active" then
        return self.activeKey or "ch:general"
    elseif targetSpec == "last_whisper" then
        local recent = self:CollectRecentWhispers(1)
        return recent[1] and recent[1].key or nil
    elseif type(targetSpec) == "string" and targetSpec:sub(1, 7) == "ch:pub:" then
        local cid = tonumber(targetSpec:sub(8))
        if cid and ns.Chat.SetGeneralTargetChannel and ns.Chat.GetOfficialChannelInfo and ns.Chat:GetOfficialChannelInfo(cid) then
            ns.Chat:SetGeneralTargetChannel(cid)
            return "ch:general"
        end
        return nil
    elseif targetSpec == "ch:say" then
        if ns.Chat.SetGeneralTargetChannel then
            ns.Chat:SetGeneralTargetChannel(nil)
        end
        return "ch:general"
    elseif targetSpec == "ch:yell" then
        if ns.Chat.SetGeneralTargetChannel then
            ns.Chat:SetGeneralTargetChannel("yell")
        end
        return "ch:general"
    elseif type(targetSpec) == "string" and targetSpec:sub(1, 3) == "ch:" then
        local st = ns.Chat.EnsureStaticChannelThread and ns.Chat:EnsureStaticChannelThread(targetSpec)
        return st and st.key or targetSpec
    end
    return self.activeKey or "ch:general"
end

function QuickReply:TriggerHotkeyIndex(idx)
    if not ns.Chat or not ns.Chat.GetQuickReplyHotkeys then return end
    local list = ns.Chat:GetQuickReplyHotkeys()
    local rec = list and list[idx]
    if not (rec and rec.enabled ~= false and rec.text and rec.text ~= "") then return end
    local targetKey = self:ResolveHotkeyTargetKey(rec.target or "active")
    if not targetKey then return end
    local msg = ns.Chat.ExpandQuickReplyText and ns.Chat:ExpandQuickReplyText(rec.text) or rec.text
    local sent, sendMode = ns.Chat:SendOrOpenReply(targetKey, msg, true)
    if sent == false and sendMode == "not_in_group" then
        if self.frame and self.frame:IsShown() then
            self:ClearDraftAndInput()
            self:Refresh()
            self:ShowInlineNotice(L["There is no active group at the moment."])
        else
            ns:Print("%s", L["There is no active group at the moment."])
        end
    end
end

function QuickReply:IsCtrlWCloseTabEnabled()
    local s = ns.db and ns.db.settings
    return (not s) or (s.quickReplyCtrlWCloseTab ~= false)
end

function QuickReply:HasExternalCtrlWBinding()
    if _G.GetBindingAction then
        local ok1, act1 = pcall(_G.GetBindingAction, "CTRL-W", true)
        if ok1 and type(act1) == "string" and act1 ~= "" and not act1:find("SocialCentralQRCtrlWBtn", 1, true) then
            return true
        end
        local ok2, act2 = pcall(_G.GetBindingAction, "CTRL-W", false)
        if ok2 and type(act2) == "string" and act2 ~= "" and not act2:find("SocialCentralQRCtrlWBtn", 1, true) then
            return true
        end
    end
    if ns.Chat and ns.Chat.GetQuickReplyHotkeys then
        local list = ns.Chat:GetQuickReplyHotkeys() or {}
        for i = 1, math.min(12, #list) do
            local rec = list[i]
            if rec and rec.enabled ~= false and type(rec.key) == "string" and rec.key:upper() == "CTRL-W" then
                return true
            end
        end
    end
    if ns.Chat and ns.Chat.GetAbilityChatMacros then
        local mList = ns.Chat:GetAbilityChatMacros() or {}
        for i = 1, math.min(12, #mList) do
            local rec = mList[i]
            if rec and rec.enabled ~= false and type(rec.key) == "string" and rec.key:upper() == "CTRL-W" and rec.spellName and rec.spellName ~= "" then
                return true
            end
        end
    end
    return false
end

function QuickReply:CloseActiveUnpinnedTabByCtrlW()
    local nowMono = (GetTime and GetTime()) or 0
    if (nowMono - (self._lastCtrlWAt or 0)) < 0.08 then
        return false
    end
    self._lastCtrlWAt = nowMono
    if not self:IsCtrlWCloseTabEnabled() then
        return false
    end
    if not (self.frame and self.frame:IsShown() and self.activeKey) then
        return false
    end
    if self:HasExternalCtrlWBinding() then
        return false
    end
    local ownInput = self.frame.inputBox
    local kbFocus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() or nil
    if kbFocus and kbFocus ~= ownInput and not (self.IsDockedOfficialFocused and self:IsDockedOfficialFocused()) then
        if (not kbFocus.IsVisible) or kbFocus:IsVisible() then
            return false
        end
    end
    local key = self.activeKey
    local isFixedCore = (key == "ch:general" or key == "notes:self" or key == "mentions:radar")
    local isUserPinned = ns.Chat and ns.Chat.IsQuickReplyPinned and ns.Chat:IsQuickReplyPinned(key) == true
    if isFixedCore or isUserPinned then
        if self.ShowInlineNotice then
            if key == "ch:general" then
                self:ShowInlineNotice(L["The General tab is permanently pinned and cannot be closed."])
            elseif isFixedCore then
                self:ShowInlineNotice(L["This core tab is permanently pinned and cannot be closed."])
            else
                self:ShowInlineNotice(L["Pinned tab — unpin to close with Ctrl+W."])
            end
        end
        return false
    end
    local hadFocus = self.IsInputFocused and self:IsInputFocused() == true
    local closed = self:CloseTabNow(key)
    if closed and not hadFocus and self.ReleaseKeyboardFocus then
        self:ReleaseKeyboardFocus(false)
    end
    return closed
end

function QuickReply:SyncCtrlWBinding()
    if InCombatLockdown and InCombatLockdown() then
        self._hotkeysBindPending = true
        return
    end
    local wantCtrlW = true
    if not self:IsCtrlWCloseTabEnabled() then
        wantCtrlW = false
    elseif ns.Compat and ns.Compat.IsOfficialChatMode and ns.Compat.IsOfficialChatMode() then
        wantCtrlW = false
    else
        local chatModOn = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("chat")
        local s = ns.db and ns.db.settings
        if not chatModOn or (s and s.quickReplyEnabled == false) then
            wantCtrlW = false
        elseif not (self.frame and self.frame:IsShown()) then
            wantCtrlW = false
        else
            local ownInput = self.frame.inputBox
            local kbFocus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() or nil
            if kbFocus and kbFocus ~= ownInput and not (self.IsDockedOfficialFocused and self:IsDockedOfficialFocused()) then
                if (not kbFocus.IsVisible) or kbFocus:IsVisible() then
                    wantCtrlW = false
                end
            end
            if wantCtrlW and self:HasExternalCtrlWBinding() then
                wantCtrlW = false
            end
        end
    end

    local desiredSig = (wantCtrlW and SetOverrideBindingClick) and "CTRL-W" or "NONE"
    if self._appliedCtrlWBindSig == desiredSig then
        return
    end
    self._appliedCtrlWBindSig = desiredSig

    if not self._ctrlWOwner then
        self._ctrlWOwner = CreateFrame("Frame", nil, UIParent)
    end
    self:_BeginOwnBindingMutation()
    if ClearOverrideBindings then
        pcall(ClearOverrideBindings, self._ctrlWOwner)
    end
    if desiredSig == "CTRL-W" then
        if not self._ctrlWBtn then
            local cBtn = CreateFrame("Button", "SocialCentralQRCtrlWBtn", UIParent)
            cBtn:SetSize(1, 1)
            cBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -130, 130)
            cBtn:RegisterForClicks("AnyUp")
            cBtn:SetScript("OnClick", function()
                QuickReply:CloseActiveUnpinnedTabByCtrlW()
            end)
            self._ctrlWBtn = cBtn
        end
        if SetOverrideBindingClick then
            pcall(SetOverrideBindingClick, self._ctrlWOwner, false, "CTRL-W", "SocialCentralQRCtrlWBtn", "LeftButton")
        end
    end
    self:_EndOwnBindingMutation()
end

function QuickReply:SyncQuickReplyHotkeys()
    if InCombatLockdown and InCombatLockdown() then
        self._hotkeysBindPending = true
        return
    end
    self._hotkeysBindPending = false
    self:SyncCtrlWBinding()

    local blocked = false
    if self.frame and self.frame:IsShown() and self.frame.inputBox and self.frame.inputBox.HasFocus and self.frame.inputBox:HasFocus() then
        blocked = true
    elseif GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() ~= nil then
        blocked = true
    else
        local blizzWin = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
            or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
            or nil
        if blizzWin and blizzWin.HasFocus and blizzWin:HasFocus() then
            blocked = true
        end
    end
    local chatModOn = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("chat")
    if not (chatModOn and SetOverrideBindingClick and ns.Chat and ns.Chat.GetQuickReplyHotkeys) then
        blocked = true
    end

    local desiredSig = "NONE"
    local list = nil
    local mList = nil
    if not blocked then
        list = ns.Chat:GetQuickReplyHotkeys()
        local sigParts = self._hotkeySigBuf
        if not sigParts then
            sigParts = {}
            self._hotkeySigBuf = sigParts
        else
            for k = #sigParts, 1, -1 do
                sigParts[k] = nil
            end
        end
        local nParts = 0
        if type(list) == "table" then
            for i = 1, math.min(12, #list) do
                local rec = list[i]
                if rec and rec.enabled ~= false and type(rec.key) == "string" and rec.key ~= "" then
                    nParts = nParts + 1
                    sigParts[nParts] = "H" .. tostring(i) .. "=" .. rec.key
                end
            end
        end
        if ns.Chat.GetAbilityChatMacros and ns.Chat.BuildAbilityMacroBody then
            mList = ns.Chat:GetAbilityChatMacros()
            if type(mList) == "table" then
                for i = 1, math.min(12, #mList) do
                    local rec = mList[i]
                    if rec and rec.enabled ~= false and type(rec.key) == "string" and rec.key ~= "" and rec.spellName and rec.spellName ~= "" then
                        nParts = nParts + 1
                        sigParts[nParts] = "M" .. tostring(i) .. "=" .. rec.key .. ":" .. tostring(rec.spellName) .. ":" .. tostring(rec.channelSlash or "") .. ":" .. tostring(rec.message or "")
                    end
                end
            end
        end
        if nParts > 0 then
            desiredSig = table.concat(sigParts, "|")
        end
    end

    if self._appliedHotkeyBindSig == desiredSig then
        return
    end
    self._appliedHotkeyBindSig = desiredSig

    self._hotkeyBtns = self._hotkeyBtns or {}
    if not self._hotkeyOwner then
        self._hotkeyOwner = CreateFrame("Frame", nil, UIParent)
    end
    self:_BeginOwnBindingMutation()
    if ClearOverrideBindings then
        pcall(ClearOverrideBindings, self._hotkeyOwner)
    end
    if desiredSig ~= "NONE" then
        if type(list) == "table" then
            for i = 1, math.min(12, #list) do
                local rec = list[i]
                if rec and rec.enabled ~= false and type(rec.key) == "string" and rec.key ~= "" then
                    local bName = "SocialCentralQRHotkeyBtn" .. tostring(i)
                    local btn = self._hotkeyBtns[i]
                    if not btn then
                        btn = CreateFrame("Button", bName, UIParent)
                        btn:SetSize(1, 1)
                        btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -120, 120)
                        btn:RegisterForClicks("AnyUp")
                        local slotIdx = i
                        btn:SetScript("OnClick", function()
                            QuickReply:TriggerHotkeyIndex(slotIdx)
                        end)
                        self._hotkeyBtns[i] = btn
                    end
                    pcall(SetOverrideBindingClick, self._hotkeyOwner, false, rec.key, bName, "LeftButton")
                end
            end
        end
        if type(mList) == "table" and ns.Chat and ns.Chat.BuildAbilityMacroBody then
            self._abilityMacroBtns = self._abilityMacroBtns or {}
            for i = 1, math.min(12, #mList) do
                local rec = mList[i]
                if rec and rec.enabled ~= false and type(rec.key) == "string" and rec.key ~= "" and rec.spellName and rec.spellName ~= "" then
                    local bName = "SocialCentralAbilityMacroBtn" .. tostring(i)
                    local btn = self._abilityMacroBtns[i]
                    if not btn then
                        btn = CreateFrame("Button", bName, UIParent, "SecureActionButtonTemplate")
                        btn:SetSize(1, 1)
                        btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -140, 140)
                        btn:RegisterForClicks("AnyUp")
                        btn:SetAttribute("useOnKeyDown", false)
                        btn:SetAttribute("type", "macro")
                        self._abilityMacroBtns[i] = btn
                    end
                    local macroTxt = ns.Chat:BuildAbilityMacroBody(rec.spellName, rec.channelSlash, rec.message)
                    btn:SetAttribute("macrotext", macroTxt)
                    pcall(SetOverrideBindingClick, self._hotkeyOwner, false, rec.key, bName, "LeftButton")
                end
            end
        end
    end
    self:_EndOwnBindingMutation()
end

function QuickReply:OpenConfigModal(initialTab)
    local Theme = ns.Theme
    if not (Theme and ns.Chat) then return end
    if not self._configModal then
        local m = CreateFrame("Frame", "SocialCentralQuickReplyConfigModal", UIParent, "BackdropTemplate")
        m:Hide()
        m:SetSize(548, 448)
        m:SetPoint("CENTER")
        table.insert(UISpecialFrames, "SocialCentralQuickReplyConfigModal")
        Theme:PrepareTopOverlayModal(m, 855)

        local hdr = CreateFrame("Frame", nil, m)
        hdr:SetPoint("TOPLEFT", 12, -10)
        hdr:SetPoint("TOPRIGHT", -12, -10)
        hdr:SetHeight(24)
        local titleFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleFs:SetPoint("LEFT", hdr, "LEFT", 0, 0)
        titleFs:SetText(L["Quick Replies, Shortcuts & Ability Macros"])
        m.titleFs = titleFs

        local closeBtn = Theme:CreateButton(hdr, 22, 20, "X", "default")
        closeBtn:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
        closeBtn:SetScript("OnClick", function() m:Hide() end)
        m.closeBtn = closeBtn

        local helpBtn = Theme:CreateHelpButton(
            hdr,
            L["Quick Replies & Shortcuts Guide"],
            L["Customize quick-reply templates per channel (including city portals in /1 and /2), create 1-click Ability+Chat macros you can assign in WoW Macros & Keybindings (works in combat!), or bind standalone keyboard shortcuts."],
            L["Switch between 'Quick Replies' and 'Shortcuts & Abilities', fill the fields, and click Save Macro or Copy so you can place it on your action bars."],
            18
        )
        helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
        m.helpBtn = helpBtn
        titleFs:SetPoint("RIGHT", helpBtn, "LEFT", -6, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)

        Theme:MakeMovable(m, {
            key = "qrConfigModal",
            skipAutoRestore = true,
            handles = { hdr, m },
        })

        local tabReplies = Theme:CreateButton(m, 160, 22, L["Quick Replies"], "primary")
        Theme:AutoFitButton(tabReplies, 140, 18, 220)
        tabReplies:SetPoint("TOPLEFT", m, "TOPLEFT", 14, -40)
        local tabKeys = Theme:CreateButton(m, 190, 22, L["Shortcuts & Abilities"], "default")
        Theme:AutoFitButton(tabKeys, 160, 18, 250)
        tabKeys:SetPoint("LEFT", tabReplies, "RIGHT", 6, 0)

        local panelReplies = CreateFrame("Frame", nil, m)
        panelReplies:SetPoint("TOPLEFT", m, "TOPLEFT", 14, -68)
        panelReplies:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -14, 14)

        local panelKeys = CreateFrame("Frame", nil, m)
        panelKeys:SetPoint("TOPLEFT", m, "TOPLEFT", 14, -68)
        panelKeys:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -14, 14)
        panelKeys:Hide()

        -- Panel 1: Context Quick Replies
        m._selCtx = ns.Chat:ResolveQuickReplyContext(QuickReply.activeKey)
        local ctxBtns = {}
        local contexts = ns.Chat:GetQuickReplyContexts()
        local cx, cy = 0, 0
        for i, ctx in ipairs(contexts) do
            local cb = Theme:CreateButton(panelReplies, 168, 20, ctx.label, "default")
            Theme:AutoFitButton(cb, 148, 12, 170)
            cb:SetPoint("TOPLEFT", panelReplies, "TOPLEFT", cx, cy)
            cb._ctxId = ctx.id
            cb:SetScript("OnClick", function()
                m._selCtx = ctx.id
                m:RefreshModal()
            end)
            ctxBtns[i] = cb
            cx = cx + 174
            if i % 3 == 0 then
                cx = 0
                cy = cy - 24
            end
        end

        local listHint = panelReplies:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        listHint:SetPoint("TOPLEFT", panelReplies, "TOPLEFT", 0, -50)
        listHint:SetPoint("TOPRIGHT", panelReplies, "TOPRIGHT", 0, -50)
        listHint:SetJustifyH("LEFT")
        listHint:SetWordWrap(true)
        listHint:SetText(L["Placeholders: {zone}, {level}, {class} (in /1 and /2, city portals appear automatically)"])

        local replyRows = {}
        for i = 1, 8 do
            local row = CreateFrame("Frame", nil, panelReplies)
            row:SetSize(520, 24)
            row:SetPoint("TOPLEFT", panelReplies, "TOPLEFT", 0, -72 - ((i - 1) * 26))
            local rBg = row:CreateTexture(nil, "BACKGROUND")
            rBg:SetAllPoints()
            rBg:SetColorTexture(1, 1, 1, (i % 2 == 1) and 0.04 or 0.02)
            local delB = Theme:CreateButton(row, 22, 20, "X", "danger")
            delB:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            local txtFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            txtFs:SetPoint("LEFT", row, "LEFT", 6, 0)
            txtFs:SetPoint("RIGHT", delB, "LEFT", -6, 0)
            txtFs:SetJustifyH("LEFT")
            txtFs:SetWordWrap(false)
            delB:SetScript("OnClick", function()
                ns.Chat:RemoveQuickReplyForContext(m._selCtx, i)
                m:RefreshModal()
                QuickReply:Refresh()
            end)
            row.txtFs = txtFs
            row.delB = delB
            replyRows[i] = row
        end

        local resetReplyBtn = Theme:CreateButton(panelReplies, 84, 22, L["Reset"], "default")
        Theme:AutoFitButton(resetReplyBtn, 76, 14, 136)
        resetReplyBtn:SetPoint("BOTTOMRIGHT", panelReplies, "BOTTOMRIGHT", 0, 2)
        local addReplyBtn = Theme:CreateButton(panelReplies, 88, 22, "+ " .. L["Add"], "primary")
        Theme:AutoFitButton(addReplyBtn, 80, 14, 136)
        addReplyBtn:SetPoint("RIGHT", resetReplyBtn, "LEFT", -4, 0)
        local addReplyBox = Theme:CreateEditBox(panelReplies, { width = 280, height = 22, maxLetters = 160, placeholder = L["Add custom phrase (supports {zone})..."] })
        addReplyBox:SetPoint("BOTTOMLEFT", panelReplies, "BOTTOMLEFT", 0, 2)
        addReplyBox:SetPoint("RIGHT", addReplyBtn, "LEFT", -6, 0)

        local function SubmitNewReply()
            local txt = addReplyBox:GetText() or ""
            if ns.Chat:AddQuickReplyForContext(m._selCtx, txt) then
                addReplyBox:SetText("")
                m:RefreshModal()
                QuickReply:Refresh()
            end
        end
        addReplyBtn:SetScript("OnClick", SubmitNewReply)
        addReplyBox:SetScript("OnEnterPressed", SubmitNewReply)
        resetReplyBtn:SetScript("OnClick", function()
            ns.Chat:ResetQuickRepliesForContext(m._selCtx)
            m:RefreshModal()
            QuickReply:Refresh()
        end)

        -- Panel 2: Ability + Chat Macros & Direct Hotkeys
        local macTitle = panelKeys:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        macTitle:SetPoint("TOPLEFT", panelKeys, "TOPLEFT", 0, -2)
        macTitle:SetText("|cffffd24d" .. L["Ability + Chat Shortcut (Same Keybind, Works in Combat)"] .. "|r")

        m._macKey = ""
        local macKeyBtn = Theme:CreateButton(panelKeys, 114, 22, L["Set Key..."], "default")
        Theme:AutoFitButton(macKeyBtn, 100, 14, 152)
        macKeyBtn:SetPoint("TOPLEFT", panelKeys, "TOPLEFT", 0, -20)
        macKeyBtn:EnableKeyboard(false)
        macKeyBtn:SetScript("OnClick", function(selfBtn)
            Theme:SetButtonText(selfBtn, L["Press a key..."])
            selfBtn:EnableKeyboard(true)
            selfBtn:SetScript("OnKeyDown", function(_, key)
                if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
                    return
                end
                selfBtn:EnableKeyboard(false)
                selfBtn:SetScript("OnKeyDown", nil)
                if key == "ESCAPE" then
                    m._macKey = ""
                    Theme:SetButtonText(selfBtn, L["Set Key..."])
                    return
                end
                local mods = ""
                if IsAltKeyDown and IsAltKeyDown() then mods = mods .. "ALT-" end
                if IsControlKeyDown and IsControlKeyDown() then mods = mods .. "CTRL-" end
                if IsShiftKeyDown and IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                m._macKey = mods .. tostring(key)
                Theme:SetButtonText(selfBtn, m._macKey)
            end)
        end)

        local spellBox = Theme:CreateEditBox(panelKeys, { width = 160, height = 22, maxLetters = 80, placeholder = L["Spell or ability name..."] })
        spellBox:SetPoint("LEFT", macKeyBtn, "RIGHT", 6, 0)

        m._macroChanSlash = "/p"
        local macChanBtn = Theme:CreateButton(panelKeys, 116, 22, "/p (" .. L["Party"] .. ")", "default")
        Theme:AutoFitButton(macChanBtn, 108, 14, 165)
        macChanBtn:SetPoint("TOPRIGHT", panelKeys, "TOPRIGHT", 0, -20)

        local pickSpellBtn = Theme:CreateButton(panelKeys, 90, 22, L["Spells..."], "default")
        Theme:AutoFitButton(pickSpellBtn, 78, 14, 130)
        pickSpellBtn:SetPoint("RIGHT", macChanBtn, "LEFT", -6, 0)
        pickSpellBtn:SetScript("OnClick", function(selfBtn)
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                root:CreateTitle(L["Choose Learned Ability"])
                if root.SetScrollMode then
                    pcall(root.SetScrollMode, root, 340)
                end
                local seen = {}
                local tabs = {}
                local flatSpells = {}
                if _G.C_SpellBook and _G.C_SpellBook.GetNumSpellBookSkillLines and _G.C_SpellBook.GetSpellBookSkillLineInfo and _G.C_SpellBook.GetSpellBookItemName then
                    local bank = (_G.Enum and _G.Enum.SpellBookSpellBank and _G.Enum.SpellBookSpellBank.Player) or 0
                    local lines = _G.C_SpellBook.GetNumSpellBookSkillLines() or 0
                    for li = 1, lines do
                        local info = _G.C_SpellBook.GetSpellBookSkillLineInfo(li)
                        if info and info.numSpellBookItems and info.itemIndexOffset then
                            local tabSpells = {}
                            for si = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                                local sName = _G.C_SpellBook.GetSpellBookItemName(si, bank)
                                local isPass = _G.C_SpellBook.IsSpellBookItemPassive and _G.C_SpellBook.IsSpellBookItemPassive(si, bank)
                                if type(sName) == "string" and sName ~= "" and not isPass and not seen[sName] then
                                    seen[sName] = true
                                    tabSpells[#tabSpells + 1] = sName
                                    flatSpells[#flatSpells + 1] = sName
                                end
                            end
                            if #tabSpells > 0 then
                                table.sort(tabSpells, function(a, b) return a < b end)
                                local tabLabel = (type(info.name) == "string" and info.name ~= "") and info.name or L["Choose Learned Ability"]
                                tabs[#tabs + 1] = { name = tabLabel, spells = tabSpells }
                            end
                        end
                    end
                elseif _G.GetSpellBookItemName then
                    local bookSpell = _G.BOOKTYPE_SPELL or "spell"
                    for si = 1, 240 do
                        local sName = _G.GetSpellBookItemName(si, bookSpell)
                        local isPass = _G.IsPassiveSpell and _G.IsPassiveSpell(si, bookSpell)
                        if not sName then break end
                        if type(sName) == "string" and sName ~= "" and not isPass and not seen[sName] then
                            seen[sName] = true
                            flatSpells[#flatSpells + 1] = sName
                        end
                    end
                    if #flatSpells > 0 then
                        table.sort(flatSpells, function(a, b) return a < b end)
                    end
                end
                if #tabs >= 2 then
                    for _, tabInfo in ipairs(tabs) do
                        local sub = root:CreateButton(tabInfo.name)
                        if sub and sub.SetScrollMode then
                            pcall(sub.SetScrollMode, sub, 320)
                        end
                        for _, sName in ipairs(tabInfo.spells) do
                            local capName = sName
                            sub:CreateButton(capName, function()
                                spellBox:SetText(capName)
                            end)
                        end
                    end
                elseif #flatSpells > 0 then
                    if #tabs == 1 then
                        flatSpells = tabs[1].spells
                    end
                    for _, sName in ipairs(flatSpells) do
                        local capName = sName
                        root:CreateButton(capName, function()
                            spellBox:SetText(capName)
                        end)
                    end
                else
                    root:CreateTitle(L["Type ability name in the box."])
                end
            end)
        end)
        spellBox:ClearAllPoints()
        spellBox:SetPoint("LEFT", macKeyBtn, "RIGHT", 6, 0)
        spellBox:SetPoint("RIGHT", pickSpellBtn, "LEFT", -6, 0)
        local macChanChoices = {
            { slash = "/p", label = "/p (" .. L["Party"] .. ")" },
            { slash = "/ra", label = "/ra (" .. L["Raid"] .. ")" },
            { slash = "/i", label = "/i (" .. L["Instance"] .. ")" },
            { slash = "/g", label = "/g (" .. L["Guild"] .. ")" },
            { slash = "/s", label = "/s (" .. L["Say"] .. ")" },
            { slash = "/y", label = "/y (" .. L["Yell"] .. ")" },
            { slash = "/1", label = "/1 (" .. L["General"] .. ")" },
            { slash = "/2", label = "/2 (" .. L["Trade"] .. ")" },
            { slash = "/3", label = "/3 (" .. L["Defense"] .. ")" },
        }
        macChanBtn:SetScript("OnClick", function(selfBtn)
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                for _, ch in ipairs(macChanChoices) do
                    root:CreateButton(ch.label, function()
                        m._macroChanSlash = ch.slash
                        Theme:SetButtonText(macChanBtn, ch.label)
                    end)
                end
            end)
        end)

        local saveMacBtn = Theme:CreateButton(panelKeys, 128, 22, "+ " .. L["Save"], "primary")
        Theme:AutoFitButton(saveMacBtn, 96, 14, 154)
        saveMacBtn:SetPoint("TOPRIGHT", panelKeys, "TOPRIGHT", 0, -46)

        local macMsgBox = Theme:CreateEditBox(panelKeys, { width = 326, height = 22, maxLetters = 160, placeholder = L["Message to say when casting (supports {spell})..."] })
        macMsgBox:SetPoint("TOPLEFT", panelKeys, "TOPLEFT", 0, -46)
        macMsgBox:SetPoint("RIGHT", saveMacBtn, "LEFT", -6, 0)
        saveMacBtn:SetScript("OnClick", function()
            local ok, resOrErr = ns.Chat:SaveAndSyncAbilityChatMacro({
                key = m._macKey,
                spellName = spellBox:GetText(),
                channelSlash = m._macroChanSlash,
                message = macMsgBox:GetText(),
            })
            if ok then
                m._macKey = ""
                Theme:SetButtonText(macKeyBtn, L["Set Key..."])
                spellBox:SetText("")
                macMsgBox:SetText("")
                QuickReply:SyncQuickReplyHotkeys()
                m:RefreshModal()
            elseif resOrErr == "combat" then
                ns:Print(L["Leave combat to edit ability shortcuts."])
            end
        end)

        local macRows = {}
        for i = 1, 4 do
            local row = CreateFrame("Frame", nil, panelKeys)
            row:SetSize(520, 22)
            row:SetPoint("TOPLEFT", panelKeys, "TOPLEFT", 0, -72 - ((i - 1) * 24))
            local rBg = row:CreateTexture(nil, "BACKGROUND")
            rBg:SetAllPoints()
            rBg:SetColorTexture(1, 1, 1, (i % 2 == 1) and 0.04 or 0.02)
            local delB = Theme:CreateButton(row, 22, 19, "X", "danger")
            delB:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            local copyB = Theme:CreateButton(row, 60, 19, L["Copy"], "default")
            Theme:AutoFitButton(copyB, 56, 12, 100)
            copyB:SetPoint("RIGHT", delB, "LEFT", -4, 0)
            local txtFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            txtFs:SetPoint("LEFT", row, "LEFT", 6, 0)
            txtFs:SetPoint("RIGHT", copyB, "LEFT", -6, 0)
            txtFs:SetJustifyH("LEFT")
            txtFs:SetWordWrap(false)
            copyB:SetScript("OnClick", function()
                local list = ns.Chat:GetAbilityChatMacros()
                local rec = list[i]
                if rec and ns.UI and ns.UI.OpenCopyModal then
                    local body = ns.Chat:BuildAbilityMacroBody(rec.spellName, rec.channelSlash, rec.message)
                    ns.UI:OpenCopyModal(body, L["Copy Macro"], L["Press Ctrl+C to copy this macro into Blizzard's Macro window if you prefer placing it on an action bar slot."])
                end
            end)
            delB:SetScript("OnClick", function()
                ns.Chat:RemoveAbilityChatMacro(i)
                QuickReply:SyncQuickReplyHotkeys()
                m:RefreshModal()
            end)
            row.txtFs = txtFs
            row.delB = delB
            row.copyB = copyB
            macRows[i] = row
        end

        -- Section B: Direct Hotkeys
        local hkTitle = panelKeys:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hkTitle:SetPoint("TOPLEFT", panelKeys, "TOPLEFT", 0, -176)
        hkTitle:SetText("|cff6ec1e4" .. L["Direct Quick-Reply Keyboard Shortcuts (Out of Combat)"] .. "|r")

        m._hkKey = ""
        m._hkTarget = "active"
        local keyCapBtn = Theme:CreateButton(panelKeys, 114, 22, L["Set Key..."], "default")
        Theme:AutoFitButton(keyCapBtn, 104, 14, 154)
        keyCapBtn:SetPoint("TOPLEFT", panelKeys, "TOPLEFT", 0, -194)
        keyCapBtn:EnableKeyboard(false)
        keyCapBtn:SetScript("OnClick", function(selfBtn)
            Theme:SetButtonText(selfBtn, L["Press a key..."])
            selfBtn:EnableKeyboard(true)
            selfBtn:SetScript("OnKeyDown", function(_, key)
                if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
                    return
                end
                selfBtn:EnableKeyboard(false)
                selfBtn:SetScript("OnKeyDown", nil)
                if key == "ESCAPE" then
                    m._hkKey = ""
                    Theme:SetButtonText(selfBtn, L["Set Key..."])
                    return
                end
                local mods = ""
                if IsAltKeyDown and IsAltKeyDown() then mods = mods .. "ALT-" end
                if IsControlKeyDown and IsControlKeyDown() then mods = mods .. "CTRL-" end
                if IsShiftKeyDown and IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                m._hkKey = mods .. tostring(key)
                Theme:SetButtonText(selfBtn, m._hkKey)
            end)
        end)

        local hkTargetChoices = {
            { id = "active", label = L["Active Tab"] },
            { id = "ch:party", label = "/p (" .. L["Party"] .. ")" },
            { id = "ch:raid", label = "/ra (" .. L["Raid"] .. ")" },
            { id = "ch:guild", label = "/g (" .. L["Guild"] .. ")" },
            { id = "ch:pub:1", label = "/1 (" .. L["General"] .. ")" },
            { id = "ch:pub:2", label = "/2 (" .. L["Trade"] .. ")" },
            { id = "ch:pub:3", label = "/3 (" .. L["Defense"] .. ")" },
            { id = "last_whisper", label = L["Last Whisper"] },
        }
        local hkTargetBtn = Theme:CreateButton(panelKeys, 128, 22, L["Active Tab"], "default")
        Theme:AutoFitButton(hkTargetBtn, 118, 14, 178)
        hkTargetBtn:SetPoint("LEFT", keyCapBtn, "RIGHT", 6, 0)
        hkTargetBtn:SetScript("OnClick", function(selfBtn)
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                for _, tc in ipairs(hkTargetChoices) do
                    root:CreateButton(tc.label, function()
                        m._hkTarget = tc.id
                        Theme:SetButtonText(hkTargetBtn, tc.label)
                    end)
                end
            end)
        end)

        local saveHkBtn = Theme:CreateButton(panelKeys, 88, 22, "+ " .. L["Save"], "primary")
        Theme:AutoFitButton(saveHkBtn, 84, 14, 142)
        saveHkBtn:SetPoint("TOPRIGHT", panelKeys, "TOPRIGHT", 0, -220)

        local hkMsgBox = Theme:CreateEditBox(panelKeys, { width = 374, height = 22, maxLetters = 160, placeholder = L["Quick phrase to send on keypress..."] })
        hkMsgBox:SetPoint("TOPLEFT", panelKeys, "TOPLEFT", 0, -220)
        hkMsgBox:SetPoint("RIGHT", saveHkBtn, "LEFT", -6, 0)
        saveHkBtn:SetScript("OnClick", function()
            if ns.Chat:SaveQuickReplyHotkey({ key = m._hkKey, target = m._hkTarget, text = hkMsgBox:GetText() }) then
                m._hkKey = ""
                Theme:SetButtonText(keyCapBtn, L["Set Key..."])
                hkMsgBox:SetText("")
                QuickReply:SyncQuickReplyHotkeys()
                m:RefreshModal()
            end
        end)

        local hkRows = {}
        for i = 1, 4 do
            local row = CreateFrame("Frame", nil, panelKeys)
            row:SetSize(520, 22)
            row:SetPoint("TOPLEFT", panelKeys, "TOPLEFT", 0, -248 - ((i - 1) * 24))
            local rBg = row:CreateTexture(nil, "BACKGROUND")
            rBg:SetAllPoints()
            rBg:SetColorTexture(1, 1, 1, (i % 2 == 1) and 0.04 or 0.02)
            local delB = Theme:CreateButton(row, 22, 19, "X", "danger")
            delB:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            local txtFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            txtFs:SetPoint("LEFT", row, "LEFT", 6, 0)
            txtFs:SetPoint("RIGHT", delB, "LEFT", -6, 0)
            txtFs:SetJustifyH("LEFT")
            txtFs:SetWordWrap(false)
            delB:SetScript("OnClick", function()
                ns.Chat:RemoveQuickReplyHotkey(i)
                QuickReply:SyncQuickReplyHotkeys()
                m:RefreshModal()
            end)
            row.txtFs = txtFs
            row.delB = delB
            hkRows[i] = row
        end

        local macEmptyFs = panelKeys:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        macEmptyFs:SetPoint("TOPLEFT", panelKeys, "TOPLEFT", 4, -84)
        macEmptyFs:SetPoint("TOPRIGHT", panelKeys, "TOPRIGHT", -4, -84)
        macEmptyFs:SetJustifyH("LEFT")
        macEmptyFs:SetWordWrap(true)
        macEmptyFs:SetText(L["No saved shortcuts yet — fill the fields above and click + Save."])

        local hkEmptyFs = panelKeys:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hkEmptyFs:SetPoint("TOPLEFT", panelKeys, "TOPLEFT", 4, -260)
        hkEmptyFs:SetPoint("TOPRIGHT", panelKeys, "TOPRIGHT", -4, -260)
        hkEmptyFs:SetJustifyH("LEFT")
        hkEmptyFs:SetWordWrap(true)
        hkEmptyFs:SetText(L["No saved shortcuts yet — fill the fields above and click + Save."])

        local hkTargetLabels = {}
        for _, tc in ipairs(hkTargetChoices) do
            hkTargetLabels[tc.id] = tc.label
        end

        m:HookScript("OnHide", function()
            if macKeyBtn then
                macKeyBtn:EnableKeyboard(false)
                macKeyBtn:SetScript("OnKeyDown", nil)
                Theme:SetButtonText(macKeyBtn, (m._macKey and m._macKey ~= "") and m._macKey or L["Set Key..."])
            end
            if keyCapBtn then
                keyCapBtn:EnableKeyboard(false)
                keyCapBtn:SetScript("OnKeyDown", nil)
                Theme:SetButtonText(keyCapBtn, (m._hkKey and m._hkKey ~= "") and m._hkKey or L["Set Key..."])
            end
        end)

        function m:ApplyTheme()
            local p = Theme.GetPalette and Theme:GetPalette() or nil
            Theme:ApplyBackdrop(m, "window", p)
            if m._solidOpaqueBg then
                local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
                m._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
            end
            if m.titleFs and p then
                local gc = p.textGold or p.accent or { 1.0, 0.85, 0.30 }
                m.titleFs:SetTextColor(gc[1], gc[2], gc[3])
            end
            Theme:StyleButton(closeBtn, "default")
            if helpBtn and helpBtn.RefreshTheme then helpBtn:RefreshTheme() end
            Theme:StyleButton(addReplyBtn, "primary")
            Theme:StyleButton(resetReplyBtn, "default")
            Theme:StyleButton(macKeyBtn, "default")
            Theme:StyleButton(pickSpellBtn, "default")
            Theme:StyleButton(macChanBtn, "default")
            Theme:StyleButton(saveMacBtn, "primary")
            Theme:StyleButton(keyCapBtn, "default")
            Theme:StyleButton(hkTargetBtn, "default")
            Theme:StyleButton(saveHkBtn, "primary")
            for _, r in ipairs(replyRows) do
                if r.delB then Theme:StyleButton(r.delB, "danger") end
            end
            for _, r in ipairs(macRows) do
                if r.delB then Theme:StyleButton(r.delB, "danger") end
                if r.copyB then Theme:StyleButton(r.copyB, "default") end
            end
            for _, r in ipairs(hkRows) do
                if r.delB then Theme:StyleButton(r.delB, "danger") end
            end
            local isRep = (m._activeTab ~= "keys")
            Theme:StyleButton(tabReplies, isRep and "primary" or "default")
            Theme:StyleButton(tabKeys, (not isRep) and "primary" or "default")
            for _, cb in ipairs(ctxBtns) do
                Theme:StyleButton(cb, (cb._ctxId == m._selCtx) and "primary" or "default")
            end
        end

        function m:SelectTab(tabName)
            m._activeTab = tabName or "replies"
            local isRep = (m._activeTab == "replies")
            panelReplies:SetShown(isRep)
            panelKeys:SetShown(not isRep)
            Theme:StyleButton(tabReplies, isRep and "primary" or "default")
            Theme:StyleButton(tabKeys, (not isRep) and "primary" or "default")
            m:RefreshModal()
        end
        tabReplies:SetScript("OnClick", function() m:SelectTab("replies") end)
        tabKeys:SetScript("OnClick", function() m:SelectTab("keys") end)

        function m:RefreshModal()
            for _, cb in ipairs(ctxBtns) do
                Theme:StyleButton(cb, (cb._ctxId == m._selCtx) and "primary" or "default")
            end
            local rList = ns.Chat:GetQuickRepliesForContext(m._selCtx)
            for i = 1, #replyRows do
                local r = replyRows[i]
                local txt = rList[i]
                if txt then
                    r.txtFs:SetText(txt)
                    r:Show()
                else
                    r:Hide()
                end
            end
            local mList = ns.Chat:GetAbilityChatMacros()
            for i = 1, #macRows do
                local r = macRows[i]
                local rec = mList[i]
                if rec then
                    local keyTag = (rec.key and rec.key ~= "") and ("|cff6ec1e4[" .. tostring(rec.key) .. "]|r ") or ""
                    r.txtFs:SetText(keyTag .. "|cffffd24d" .. tostring(rec.spellName) .. "|r -> " .. tostring(rec.channelSlash) .. ": " .. tostring(rec.message))
                    r:Show()
                else
                    r:Hide()
                end
            end
            macEmptyFs:SetShown(#mList == 0)
            local kList = ns.Chat:GetQuickReplyHotkeys()
            for i = 1, #hkRows do
                local r = hkRows[i]
                local rec = kList[i]
                if rec then
                    local tgtLbl = hkTargetLabels[rec.target] or tostring(rec.target or L["Active Tab"])
                    r.txtFs:SetText("|cff6ec1e4[" .. tostring(rec.key) .. "]|r |cff9da7b5(" .. tgtLbl .. ")|r -> " .. tostring(rec.text))
                    r:Show()
                else
                    r:Hide()
                end
            end
            hkEmptyFs:SetShown(#kList == 0)
        end

        self._configModal = m
    end

    local mod = self._configModal
    mod._selCtx = ns.Chat:ResolveQuickReplyContext(QuickReply.activeKey)
    Theme:PrepareTopOverlayModal(mod, 855)
    if mod.ApplyTheme then
        mod:ApplyTheme()
    end
    mod:SelectTab(initialTab or "replies")
    if Theme.SyncSubtreeLayers then
        Theme:SyncSubtreeLayers(mod, 8)
    end
    mod:Show()
    mod:Raise()
    if Theme.PromptWindowTutorial then
        Theme:PromptWindowTutorial({
            tutorialKey = "winPrompt_qrConfig",
            title = L["Quick Replies & Shortcuts"],
            guideSpec = {
                key = "qr_config",
                title = L["Quick Replies & Shortcuts Guide"],
                steps = {
                    {
                        title = L["Quick Replies & Shortcuts Guide"],
                        text = L["Edit channel phrases or create 1-click Ability+Chat combat macros."],
                        target = mod,
                    },
                },
            },
            isWindowVisible = function() return mod:IsShown() end,
        })
    end
end

function QuickReply:Init()
    QuickReply:InstallSmartZOrderHooks()
    local function RunCoalescedRefreshIfShown()
        QuickReply._qrCoalescePending = false
        local needDock = QuickReply._qrNeedDockSync == true
        QuickReply._qrNeedDockSync = false
        if QuickReply.frame and QuickReply.frame:IsShown() then
            if needDock then
                QuickReply:SyncDockGeometry()
            end
            QuickReply:ApplyCombatFadeStep(0.016, false)
            QuickReply:Refresh()
            if (QuickReply._combatFadeAnimating or QuickReply:IsInputFocused() or (not QuickReply:IsPersistentOpenMode())) and QuickReply.WakeOnUpdate then
                QuickReply:WakeOnUpdate()
            end
        end
        QuickReply:SyncEnterBinding()
        QuickReply:SyncQuickReplyHotkeys()
    end
    local function RefreshIfShown(needDockSync)
        if needDockSync then
            QuickReply._qrNeedDockSync = true
        end
        if not (QuickReply.frame and QuickReply.frame:IsShown()) then
            QuickReply:SyncEnterBinding()
            QuickReply:SyncQuickReplyHotkeys()
            return
        end
        if QuickReply._qrCoalescePending then
            return
        end
        QuickReply._qrCoalescePending = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.06, RunCoalescedRefreshIfShown)
        else
            RunCoalescedRefreshIfShown()
        end
    end
    local function RefreshIfActiveKindMatches(includeGuild, includeGroup)
        if not (QuickReply.frame and QuickReply.frame:IsShown()) then
            return
        end
        local activeT = QuickReply.activeKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[QuickReply.activeKey]
        if not activeT then
            return
        end
        local k = activeT.kind
        if k == "WHISPER" or k == "BN_WHISPER"
            or (includeGuild and (k == "GUILD" or k == "OFFICER"))
            or (includeGroup and (k == "PARTY" or k == "RAID" or k == "INSTANCE_CHAT"))
        then
            RefreshIfShown(false)
        end
    end
    local function MarkOutsideInteraction()
        QuickReply:MarkOutsideInteraction()
    end
    local function HandleGlobalMouseEvent(btnName, isMouseUp)
        local f = QuickReply.frame
        if not (f and f:IsShown()) then
            return
        end
        local nowMono = (GetTime and GetTime()) or 0
        if QuickReply._lastProgrammaticFocusAt and (nowMono - QuickReply._lastProgrammaticFocusAt) < (isMouseUp and 0.35 or 0.15) then
            return
        end
        if (QuickReply.tutorialDialog and QuickReply.tutorialDialog:IsShown() and QuickReply.tutorialDialog.IsMouseOver and QuickReply.tutorialDialog:IsMouseOver())
            or (QuickReply._closeConfirmModal and QuickReply._closeConfirmModal:IsShown() and QuickReply._closeConfirmModal.IsMouseOver and QuickReply._closeConfirmModal:IsMouseOver())
            or (_G.SocialCentralHelpPopup and _G.SocialCentralHelpPopup:IsShown() and _G.SocialCentralHelpPopup.IsMouseOver and _G.SocialCentralHelpPopup:IsMouseOver())
            or (QuickReply._combatLogFrame and QuickReply._combatLogFrame:IsShown() and QuickReply._combatLogFrame.IsMouseOver and QuickReply._combatLogFrame:IsMouseOver())
            or (QuickReply._configModal and QuickReply._configModal:IsShown() and QuickReply._configModal.IsMouseOver and QuickReply._configModal:IsMouseOver()) then
            return
        end
        local isOverMainQr = (not QuickReply._yieldedToGameUI) and ((f.IsMouseOver and f:IsMouseOver()) == true
            or (QuickReply._activeDockedSkinEb and QuickReply._activeDockedSkinEb._scDockedToQr and QuickReply._activeDockedSkinEb.IsMouseOver and QuickReply._activeDockedSkinEb:IsMouseOver() == true))
        if (not isOverMainQr)
            and QuickReply:IsPersistentOpenMode()
            and (not QuickReply:IsInputFocused())
            and (not QuickReply:IsWhispersDropdownShown())
            and (not QuickReply._ownMenuOpen)
        then
            return
        end
        if QuickReply.WakeOnUpdate then QuickReply:WakeOnUpdate() end
        if btnName == "LeftButton" and ((IsShiftKeyDown and IsShiftKeyDown() == true) or (IsModifiedClick and IsModifiedClick("CHATLINK") == true)) then
            local nowT = (GetTime and GetTime()) or 0
            QuickReply.interactedOutside = false
            QuickReply.lastInputAt = nowT
            QuickReply._lastOpaqueActivityAt = nowT
            QuickReply.idleCountdown = nil
            return
        end
        if (btnName == "Button4" or btnName == "Button5") or (btnName == "MiddleButton" and not isOverMainQr) then
            QuickReply:MarkOutsideInteraction()
            return
        end
        if isOverMainQr then
            QuickReply.interactedOutside = false
            QuickReply.lastInputAt = GetTime()
            QuickReply.idleCountdown = nil
            QuickReply:ElevateToForeground()
            return
        end
        if QuickReply:IsWhispersDropdownShown() then
            local pop = QuickReply._whispersDropdown
            if (pop and pop.IsMouseOver and pop:IsMouseOver())
                or (f.btnWhispers and f.btnWhispers.IsMouseOver and f.btnWhispers:IsMouseOver())
            then
                QuickReply.interactedOutside = false
                QuickReply.lastInputAt = GetTime()
                QuickReply.idleCountdown = nil
                return
            end
            QuickReply:HideWhispersDropdown()
        end
        QuickReply:ReleaseKeyboardFocus()
        local mgr = Menu and Menu.GetManager and Menu.GetManager() or nil
        if QuickReply._ownMenuOpen and mgr and mgr.IsAnyMenuOpen and mgr:IsAnyMenuOpen() then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.08, function()
                    if not (QuickReply.frame and QuickReply.frame:IsShown()) then
                        return
                    end
                    local mNow = Menu and Menu.GetManager and Menu.GetManager() or nil
                    if mNow and mNow.IsAnyMenuOpen and mNow:IsAnyMenuOpen() then
                        return
                    end
                    QuickReply._ownMenuOpen = false
                    if QuickReply._menuActionPicked then
                        QuickReply._menuActionPicked = false
                        return
                    end
                    if not (QuickReply.frame.IsMouseOver and QuickReply.frame:IsMouseOver()) then
                        MarkOutsideInteraction()
                    end
                end)
            end
            return
        end
        MarkOutsideInteraction()
    end
    ns:On("CHAT_UPDATED", function()
        RefreshIfShown(false)
    end)
    ns:On("COMBAT_LOG_UPDATED", function()
        if QuickReply._combatLogFrame and QuickReply._combatLogFrame:IsShown() then
            QuickReply:RefreshCombatLogFrame()
        end
    end)
    ns:On("SOCIAL_UPDATED", function()
        RefreshIfActiveKindMatches(true, false)
    end)
    ns:On("NEARBY_UPDATED", function()
        RefreshIfActiveKindMatches(false, false)
    end)
    ns:On("WATCHLIST_UPDATED", function()
        RefreshIfActiveKindMatches(false, false)
    end)
    ns:On("GROUP_UPDATED", function()
        RefreshIfActiveKindMatches(false, true)
    end)
    ns:On("SETTINGS_UPDATED", function()
        QuickReply._officialInputStyleSynced = nil
        RefreshIfShown(true)
        QuickReply:SyncQuickReplyHotkeys()
    end)
    ns:On("CHAT_HOTKEYS_UPDATED", function()
        QuickReply:SyncQuickReplyHotkeys()
    end)
    ns:On("CHAT_THREAD_READ", function(info)
        local k = type(info) == "table" and info.threadKey or info
        if QuickReply.frame and QuickReply.frame:IsShown() and k == QuickReply.activeKey then
            QuickReply:Refresh()
        end
        QuickReply:SyncEnterBinding()
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if _G.ChatFrame1EditBox then
            _G.ChatFrame1EditBox._scExplicitSayAt = nil
            local dockedOfficialNow = QuickReply.frame and QuickReply.frame:IsShown() and QuickReply:IsOfficialOnlyThread()
            local ebFocusedNow = (_G.ChatFrame1EditBox.HasFocus and _G.ChatFrame1EditBox:HasFocus() == true) == true
            if (not dockedOfficialNow) and (not ebFocusedNow)
                and (_G.ChatFrame1EditBox._scDockedToQr or _G.ChatFrame1EditBox._scOrigPoints or (_G.ChatFrame1EditBox._scDockedSkin and _G.ChatFrame1EditBox._scDockedSkin:IsShown()))
            then
                QuickReply:HideTemporaryOfficialEditBox(_G.ChatFrame1EditBox)
            end
        end
        if QuickReply.frame and QuickReply.frame:IsShown() then
            QuickReply:UpdateInputSurfaceForActiveThread()
        end
        if QuickReply.SyncBlizzardStickyChannelForThread then
            QuickReply:SyncBlizzardStickyChannelForThread(QuickReply.activeKey)
        end
        QuickReply:ApplyCombatFadeStep(0.05, false)
        QuickReply:InvalidateBindingCaches()
        QuickReply:SyncEnterBinding()
        QuickReply:SyncQuickReplyHotkeys()
        if MinimapBtn._pendingExclusiveChatApply then
            MinimapBtn:ApplyExclusiveChatMode()
        end
        if MinimapBtn._pendingChatModePrompt then
            MinimapBtn:MaybeShowChatModePrompt()
        end
        if QuickReply.pendingTutorial and QuickReply.frame and QuickReply.frame:IsShown() then
            QuickReply:ShowTutorial(false)
        end
    end)
    ns.RegisterEvent(self, "UPDATE_BINDINGS", function()
        if QuickReply._syncingBindings or QuickReply._suppressOwnUpdateBindings then
            return
        end
        local nowT = (GetTime and GetTime()) or 0
        if (nowT - (QuickReply._lastOwnBindingMutationAt or 0)) < 0.08 then
            return
        end
        QuickReply:InvalidateBindingCaches()
        QuickReply:SyncEnterBinding()
        QuickReply:SyncQuickReplyHotkeys()
    end)
    ns.RegisterEvent(self, "GLOBAL_MOUSE_DOWN", function(_, _, btnName)
        HandleGlobalMouseEvent(btnName, false)
    end)
    ns.RegisterEvent(self, "GLOBAL_MOUSE_UP", function(_, _, btnName)
        HandleGlobalMouseEvent(btnName, true)
    end)
    if _G.WorldFrame and _G.WorldFrame.HookScript and not QuickReply._worldMouseHooked then
        QuickReply._worldMouseHooked = true
        pcall(_G.WorldFrame.HookScript, _G.WorldFrame, "OnMouseDown", function(_, btnName)
            HandleGlobalMouseEvent(btnName, false)
        end)
        pcall(_G.WorldFrame.HookScript, _G.WorldFrame, "OnMouseUp", function(_, btnName)
            HandleGlobalMouseEvent(btnName, true)
        end)
    end
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        QuickReply:HideWhispersDropdown()
        MarkOutsideInteraction()
        QuickReply:ApplyCombatFadeStep(0, false)
    end)
    local function ScheduleInstanceSync()
        QuickReply:SyncInstanceAutoMode(true)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.6, function()
                QuickReply:SyncInstanceAutoMode(true)
            end)
            C_Timer.After(2.0, function()
                QuickReply:SyncInstanceAutoMode(true)
            end)
        end
    end
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", ScheduleInstanceSync)
    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", ScheduleInstanceSync)
    ns.RegisterEvent(self, "GROUP_ROSTER_UPDATE", ScheduleInstanceSync)
    ns.RegisterEvent(self, "PLAYER_DIFFICULTY_CHANGED", ScheduleInstanceSync)
    ns.RegisterEvent(self, "PLAYER_STARTED_MOVING", MarkOutsideInteraction)
    if not QuickReply._playerCastFrame then
        local castF = CreateFrame("Frame")
        if castF.RegisterUnitEvent then
            castF:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
        else
            castF:RegisterEvent("UNIT_SPELLCAST_SENT")
        end
        castF:SetScript("OnEvent", function(_, _, unit)
            local cleanUnit = (ns.Safe and ns.Safe.String) and ns.Safe.String(unit) or nil
            if cleanUnit == "player" then
                MarkOutsideInteraction()
            end
        end)
        QuickReply._playerCastFrame = castF
    end
    local function KeepDockedOfficialEditVisuals(eb)
        if not (eb and eb == _G.ChatFrame1EditBox and QuickReply.frame and QuickReply.frame:IsShown()) then
            return
        end
        local nowT = (GetTime and GetTime()) or 0
        QuickReply._dockedOfficialInputActive = true
        QuickReply._allowTempOfficialEditUntil = nowT + 120
        QuickReply._lastProgrammaticFocusAt = nowT
        QuickReply.interactedOutside = false
        QuickReply.lastInputAt = nowT
        QuickReply._lastOpaqueActivityAt = nowT
        QuickReply.idleCountdown = nil
        QuickReply:ShowActiveOfficialEditBox(eb)
        if QuickReply.ApplyCombatFadeStep then
            QuickReply:ApplyCombatFadeStep(0, true)
        end
        if QuickReply.UpdateFocusVisuals then
            QuickReply:UpdateFocusVisuals()
        end
        if QuickReply.WakeOnUpdate then
            QuickReply:WakeOnUpdate()
        end
    end
    local function HandleActivatedBlizzardEditBox(eb, fromOpenChatHook, rawOpenText)
        if not eb then return end
        QuickReply:HookBlizzardEditBoxForSlash(eb)
        if fromOpenChatHook then
            QuickReply._lastProgrammaticFocusAt = (GetTime and GetTime()) or 0
        end
        local inCombatNow = ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) == true
        if inCombatNow and eb.SetAlpha and eb.GetAlpha and (eb:GetAlpha() or 1) < 0.99 then
            pcall(eb.SetAlpha, eb, 1.0)
        end
        local isAddonMode = (Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode()) == true
        local qrShown = (QuickReply.frame and QuickReply.frame:IsShown()) == true
        if QuickReply._redirectingBlizzCombatChat then
            if isAddonMode and qrShown and eb == _G.ChatFrame1EditBox then
                KeepDockedOfficialEditVisuals(eb)
            end
            QuickReply:ReleaseKeyboardFocus(true)
            return
        end
        if (not inCombatNow) and (
            QuickReply._dockedOfficialInputActive
            or eb._scDockedToQr
            or IsTemporaryOfficialEditAllowed()
            or (isAddonMode and qrShown and QuickReply:IsOfficialOnlyThread())
        ) then
            if isAddonMode and qrShown and eb == _G.ChatFrame1EditBox and (eb.HasFocus and eb:HasFocus()) then
                KeepDockedOfficialEditVisuals(eb)
            end
            QuickReply:ReleaseKeyboardFocus(true)
            return
        end
        local cType = (eb.GetChatType and ns.Safe and ns.Safe.String(eb:GetChatType()))
            or (eb.GetAttribute and ns.Safe and ns.Safe.String(eb:GetAttribute("chatType")))
            or nil
        local tellTgt = (eb.GetTellTarget and ns.Safe and ns.Safe.String(eb:GetTellTarget()))
            or (eb.GetAttribute and ns.Safe and ns.Safe.String(eb:GetAttribute("tellTarget")))
            or nil
        local curTxt = (eb.GetText and ns.Safe and ns.Safe.String(eb:GetText())) or ""
        if isAddonMode and not inCombatNow then
            if (cType == "WHISPER" or cType == "BN_WHISPER") and type(tellTgt) == "string" and tellTgt ~= "" and curTxt == "" then
                local wKey = QuickReply:ResolveLiveSlashThread("/w", cType, tellTgt, true)
                if wKey then
                    if _G.ChatFrameUtil and _G.ChatFrameUtil.DeactivateChat then
                        pcall(_G.ChatFrameUtil.DeactivateChat, eb)
                    elseif _G.ChatEdit_DeactivateChat then
                        pcall(_G.ChatEdit_DeactivateChat, eb)
                    end
                    QuickReply:HideTemporaryOfficialEditBox(eb)
                    QuickReply:OpenThread(wKey, true)
                    return
                end
            end
            if curTxt == "/" or curTxt:sub(1, 1) == "/" or (cType == "SAY" and not IsTemporaryOfficialEditAllowed()) then
                local openKey = (qrShown and QuickReply:IsWritableThreadKey(QuickReply.activeKey) and QuickReply.activeKey)
                    or QuickReply:GetEnterTargetThreadKey()
                    or QuickReply:GetPreservedThreadKey()
                    or QuickReply:GetFirstPendingActionKey()
                    or "ch:general"
                if not openKey or openKey == "mentions:radar" or not (ns.Chat and ns.Chat.threads and ns.Chat.threads[openKey]) then
                    openKey = "ch:general"
                end
                if not qrShown then
                    QuickReply:OpenThread(openKey, false)
                elseif QuickReply.activeKey ~= openKey then
                    QuickReply:SelectThread(openKey, false)
                end
                if QuickReply:ShouldUseDockedOfficialInput(ns.Chat and ns.Chat.threads and ns.Chat.threads[openKey]) then
                    KeepDockedOfficialEditVisuals(eb)
                    return
                elseif QuickReply.frame and QuickReply.frame.inputBox then
                    if _G.ChatFrameUtil and _G.ChatFrameUtil.DeactivateChat then
                        pcall(_G.ChatFrameUtil.DeactivateChat, eb)
                    elseif _G.ChatEdit_DeactivateChat then
                        pcall(_G.ChatEdit_DeactivateChat, eb)
                    end
                    QuickReply:HideTemporaryOfficialEditBox(eb)
                    local rescueTxt = curTxt or ""
                    local existingDraft = QuickReply.frame.inputBox:GetText() or ""
                    local finalTxt = (rescueTxt ~= "") and ((existingDraft ~= "" and existingDraft ~= rescueTxt) and (existingDraft .. rescueTxt) or rescueTxt) or existingDraft
                    QuickReply.suppressDraftSave = true
                    QuickReply.frame.inputBox:SetText(finalTxt)
                    if QuickReply.frame.inputBox.UpdatePlaceholder then QuickReply.frame.inputBox:UpdatePlaceholder() end
                    QuickReply.suppressDraftSave = false
                    QuickReply:FocusInputBox()
                    if QuickReply.frame.inputBox.SetCursorPosition then
                        QuickReply.frame.inputBox:SetCursorPosition(#finalTxt)
                    end
                    if QuickReply.SyncEnterBinding then
                        QuickReply:SyncEnterBinding()
                    end
                    return
                end
            end
        elseif inCombatNow and (isAddonMode or qrShown or QuickReply:HasRecentSentSession()) then
            if type(rawOpenText) == "string" and rawOpenText:sub(1, 1) == "/" then
                if cType == "SAY" then
                    eb._scExplicitSayAt = (GetTime and GetTime()) or 0
                elseif cType and cType ~= "" then
                    eb._scExplicitSayAt = nil
                    eb._scLastManualBlizzSwitchAt = (GetTime and GetTime()) or 0
                end
                if qrShown then
                    if isAddonMode and eb == _G.ChatFrame1EditBox then
                        KeepDockedOfficialEditVisuals(eb)
                    end
                    QuickReply:ReleaseKeyboardFocus(true)
                end
                return
            end
            if curTxt:sub(1, 1) ~= "/" then
                local combatTargetKey = QuickReply:ResolveCombatOfficialThreadKey()
                if combatTargetKey and ns.Chat and ns.Chat.OpenOfficialChatForThread and (not QuickReply:ThreadMatchesBlizzardChannel(eb, combatTargetKey)) then
                    local lastQrActivity = math.max(QuickReply._lastSentAt or 0, QuickReply.openedAt or 0, QuickReply._lastManualSelectAt or 0)
                    local isSayFallback = (cType == nil or cType == "SAY")
                    local explicitSay = isSayFallback and eb._scExplicitSayAt and (eb._scExplicitSayAt >= lastQrActivity)
                    local manualOther = (not isSayFallback) and ((eb._scLastManualBlizzSwitchAt or 0) > (QuickReply._lastManualSelectAt or 0))
                    if (not explicitSay) and (not manualOther) then
                        QuickReply._redirectingBlizzCombatChat = true
                        local okCall, okOpen = pcall(ns.Chat.OpenOfficialChatForThread, ns.Chat, combatTargetKey, curTxt, true)
                        QuickReply._redirectingBlizzCombatChat = false
                        QuickReply._refocusInputAfterBlizzSend = false
                        if okCall and okOpen then
                            if isAddonMode and qrShown and eb == _G.ChatFrame1EditBox then
                                KeepDockedOfficialEditVisuals(eb)
                            else
                                QuickReply._allowTempOfficialEditUntil = nil
                            end
                            QuickReply:ReleaseKeyboardFocus(true)
                            return
                        end
                    end
                end
            end
            if isAddonMode and qrShown and eb == _G.ChatFrame1EditBox then
                KeepDockedOfficialEditVisuals(eb)
                QuickReply:ReleaseKeyboardFocus(true)
                return
            end
        end
        if qrShown then
            QuickReply:ReleaseKeyboardFocus(true)
            QuickReply.interactedOutside = true
            QuickReply.lastInputAt = 0
        end
    end
    local function HandleUpdatedBlizzardEditHeader(eb)
        if eb and eb == _G.ChatFrame1EditBox
            and (eb._scDockedToQr or QuickReply._dockedOfficialInputActive)
            and QuickReply.frame and QuickReply.frame:IsShown()
            and Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode()
            and Compat.IsAddonChatMode and Compat.IsAddonChatMode()
        then
            if type(eb._scOrigTexAlphas) == "table" then
                for obj in pairs(eb._scOrigTexAlphas) do
                    if obj and obj.SetAlpha then
                        local curA = obj.GetAlpha and obj:GetAlpha() or 1
                        if curA > 0.005 then
                            pcall(obj.SetAlpha, obj, 0)
                        end
                    end
                end
            end
            SyncDockedOfficialSkinColors(eb)
        end
    end
    if type(_G.FCF_SetChatWindowFontSize) == "function" and type(hooksecurefunc) == "function" and not QuickReply._chatFontHooked then
        QuickReply._chatFontHooked = true
        hooksecurefunc("FCF_SetChatWindowFontSize", function()
            QuickReply._officialInputStyleSynced = nil
            if QuickReply.frame and QuickReply.frame:IsShown() then
                QuickReply:SyncInputStyleToOfficial(true)
            end
        end)
    end
    if type(_G.ChatEdit_UpdateHeader) == "function" and not QuickReply._chatEditUpdateHdrHooked then
        QuickReply._chatEditUpdateHdrHooked = true
        hooksecurefunc("ChatEdit_UpdateHeader", HandleUpdatedBlizzardEditHeader)
    end
    if type(_G.ChatFrameEditBoxMixin) == "table" and type(_G.ChatFrameEditBoxMixin.UpdateHeader) == "function" and not QuickReply._chatMixinUpdateHdrHooked then
        QuickReply._chatMixinUpdateHdrHooked = true
        hooksecurefunc(_G.ChatFrameEditBoxMixin, "UpdateHeader", HandleUpdatedBlizzardEditHeader)
    end
    if _G.ChatFrameUtil and type(_G.ChatFrameUtil.ActivateChat) == "function" and not QuickReply._chatUtilActivateHooked then
        QuickReply._chatUtilActivateHooked = true
        hooksecurefunc(_G.ChatFrameUtil, "ActivateChat", function(eb)
            HandleActivatedBlizzardEditBox(eb, false, nil)
        end)
    end
    if type(_G.ChatEdit_ActivateChat) == "function" and not QuickReply._chatEditHooked then
        QuickReply._chatEditHooked = true
        hooksecurefunc("ChatEdit_ActivateChat", function(eb)
            HandleActivatedBlizzardEditBox(eb, false, nil)
        end)
    end
    if type(_G.ChatFrameEditBoxMixin) == "table" and type(_G.ChatFrameEditBoxMixin.ActivateChat) == "function" and not QuickReply._chatMixinActivateHooked then
        QuickReply._chatMixinActivateHooked = true
        hooksecurefunc(_G.ChatFrameEditBoxMixin, "ActivateChat", function(eb)
            HandleActivatedBlizzardEditBox(eb, false, nil)
        end)
    end
    local function HandlePostOpenChat(textArg)
        local activeEb = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
            or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
            or _G.ChatFrame1EditBox
            or nil
        if activeEb then
            HandleActivatedBlizzardEditBox(activeEb, true, type(textArg) == "string" and textArg or nil)
        end
    end
    if _G.ChatFrameUtil and type(_G.ChatFrameUtil.OpenChat) == "function" and not QuickReply._chatUtilOpenChatHooked then
        QuickReply._chatUtilOpenChatHooked = true
        hooksecurefunc(_G.ChatFrameUtil, "OpenChat", HandlePostOpenChat)
    end
    if type(_G.ChatFrame_OpenChat) == "function" and not QuickReply._chatOpenChatHooked then
        QuickReply._chatOpenChatHooked = true
        hooksecurefunc("ChatFrame_OpenChat", HandlePostOpenChat)
    end
    for i = 1, 10 do
        QuickReply:HookBlizzardEditBoxForSlash(_G["ChatFrame" .. i .. "EditBox"])
        local cf = _G["ChatFrame" .. i]
        if cf and cf.editBox then
            QuickReply:HookBlizzardEditBoxForSlash(cf.editBox)
        end
    end
    if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.editBox then
        QuickReply:HookBlizzardEditBoxForSlash(_G.DEFAULT_CHAT_FRAME.editBox)
    end
    if _G.ChatFrameUtil and type(_G.ChatFrameUtil.GetLastActiveWindow) == "function" then
        QuickReply:HookBlizzardEditBoxForSlash(_G.ChatFrameUtil.GetLastActiveWindow())
    end
    if type(_G.ChatEdit_GetLastActiveWindow) == "function" then
        QuickReply:HookBlizzardEditBoxForSlash(_G.ChatEdit_GetLastActiveWindow())
    end
    if type(_G.ChatFrameEditBoxMixin) == "table" and type(_G.ChatFrameEditBoxMixin.ParseText) == "function" and not QuickReply._chatMixinParseHooked then
        QuickReply._chatMixinParseHooked = true
        hooksecurefunc(_G.ChatFrameEditBoxMixin, "ParseText", function(editBox, send)
            if send == 0 then
                QuickReply:HandleBlizzardEditBoxSlashTrigger(editBox)
            end
        end)
    end
    if type(_G.ChatEdit_ParseText) == "function" and not QuickReply._chatParseHooked then
        QuickReply._chatParseHooked = true
        hooksecurefunc("ChatEdit_ParseText", function(editBox, send)
            if send == 0 then
                QuickReply:HandleBlizzardEditBoxSlashTrigger(editBox)
            end
        end)
    end
    if ns.Theme and ns.Theme.RegisterListener then
        ns.Theme:RegisterListener(function()
            QuickReply:ApplyTheme()
            local p = ns.Theme:GetPalette()
            if MinimapBtn._chatModePromptFrame and MinimapBtn._chatModePromptFrame:IsShown() then
                local mf = MinimapBtn._chatModePromptFrame
                if mf._solidOpaqueBg and p then
                    local bg = p.windowBg or { 0.08, 0.08, 0.09, 1.0 }
                    mf._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
                end
                ns.Theme:ApplyBackdrop(mf, "window", p)
                if mf._leftCard then ns.Theme:ApplyBackdrop(mf._leftCard, "inset", p) end
                if mf._rightCard then ns.Theme:ApplyBackdrop(mf._rightCard, "inset", p) end
                if mf._btnAddon then ns.Theme:StyleButton(mf._btnAddon, "primary") end
                if mf._btnOfficial then ns.Theme:StyleButton(mf._btnOfficial, "default") end
                if mf._helpBtn and mf._helpBtn.RefreshTheme then mf._helpBtn:RefreshTheme() end
            end
            if QuickReply._configModal and QuickReply._configModal:IsShown() then
                local cm = QuickReply._configModal
                if cm.ApplyTheme then
                    cm:ApplyTheme()
                else
                    ns.Theme:ApplyBackdrop(cm, "window", p)
                end
                if cm.RefreshModal then cm:RefreshModal() end
            end
        end)
    end
    if ns.Theme and ns.Theme.RegisterViewportListener then
        ns.Theme:RegisterViewportListener("minimap_btn", UpdatePosition)
        ns.Theme:RegisterViewportListener("minimap_preview", function()
            MsgPreview:SyncAnchorMoverPosition()
            if type(MsgPreview.activeSlots) == "table" then
                for _, slot in ipairs(MsgPreview.activeSlots) do
                    if slot.phase == "HOLD" then
                        MpApplySlotVisuals(slot, 1, 1, 1, 0, 1, 1)
                    end
                end
            end
        end)
        ns.Theme:RegisterViewportListener("quick_reply", function()
            QuickReply:HideWhispersDropdown()
            QuickReply:SyncDockGeometry()
            QuickReply:UpdateWhispersButton()
        end)
    end
    if Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() then
        MinimapBtn:ApplyExclusiveChatMode()
    end
    QuickReply:SyncEnterBinding()
    QuickReply:SyncQuickReplyHotkeys()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function()
            if Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() then
                MinimapBtn:ApplyExclusiveChatMode()
            end
            QuickReply:SyncEnterBinding()
        end)
        C_Timer.After(1.1, function()
            MinimapBtn:ApplyExclusiveChatMode()
            MinimapBtn:MaybeShowChatModePrompt()
            QuickReply:SyncInstanceAutoMode(true)
        end)
    end
end

ns.QuickReply = QuickReply
table.insert(ns.modules, QuickReply)
