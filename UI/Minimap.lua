local _, ns = ...

local L = ns.L
local Compat = ns.Compat

local MinimapBtn = {}
ns.Minimap = MinimapBtn

local RING_TEX = 136430
local BG_TEX = 136467
local HIGHLIGHT_TEX = 136477
local ICON_TEX = "Interface\\AddOns\\SocialCentral\\Media\\icon"
local ICON_BELL_OFF = "Interface\\AddOns\\SocialCentral\\Media\\bell-off"
local RADIUS_OFFSET = 8

local button
local ldbObject
local BADGE_CATEGORY_ORDER = { "whisper", "group", "guild", "bnet", "room" }
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
    local angleDeg = (cfg and cfg.angle) or 215
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

local function SetIconPressed(pressed)
    if not button or not button.icon then
        return
    end
    local inset = pressed and 0.04 or 0.0
    button.icon:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
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

    local isBlizz = ns.Theme and ns.Theme.GetThemeName and ns.Theme:GetThemeName() == "blizzard"
    local designLabel = isBlizz and L["Blizzard Official"] or L["Modern Theme"]
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
            local shownSenders = 0
            for _, item in ipairs(summary.senders) do
                if shownSenders >= 4 then break end
                local toneKey = (ns.Theme and ns.Theme.GetChatToneForKind) and ns.Theme:GetChatToneForKind(item.kind) or "whisper"
                local spec = (ns.Theme and ns.Theme.GetChatToneSpec) and ns.Theme:GetChatToneSpec(toneKey)
                local ac = (spec and spec.accent) or { 1.0, 0.50, 1.0 }
                tt:AddDoubleLine("  " .. tostring(item.title or ""), tostring(item.unread or 0), 0.86, 0.90, 0.96, ac[1], ac[2], ac[3])
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
    local clickMode = (ns.db and ns.db.settings and ns.db.settings.minimapLeftClickAction) or "smart"
    local leftHint = (clickMode == "menu") and L["Left-click: choose Main Window or Settings"]
        or (clickMode == "hub" and L["Left-click: open Main Window"] or L["Left-click: open Unread Chat or Main Window"])
    local extraLines = { leftHint }
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
    local limit = math.min(#recList, 20)
    for i = 1, limit do
        local it = recList[i]
        if it then
            local tsStr = it.ts and date("%H:%M", it.ts) or ""
            local src = tostring(it.sourceTag or "?")
            local who = tostring(it.sender or "?")
            local rawSnip = tostring(it.text or ""):gsub("[\r\n|]+", " ")
            local snip = (#rawSnip > 36) and (CutUtf8ForMenu(rawSnip, 33) .. "...") or rawSnip
            local lbl = string.format("[%s] %s · %s: %s", tsStr, src, who, snip)
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
        local function SetTimedDnd(durSec, untilLeave)
            if Compat and Compat.SetDoNotDisturb then
                Compat.SetDoNotDisturb(true, durSec, untilLeave)
            elseif ns.db and ns.db.settings then
                ns.db.settings.doNotDisturb = true
                ns:Emit("SETTINGS_UPDATED")
                if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
            end
        end
        dndSub:CreateButton(L["For 30 minutes"], function() SetTimedDnd(1800, false) end)
        dndSub:CreateButton(L["For 1 hour"], function() SetTimedDnd(3600, false) end)
        dndSub:CreateButton(L["Until leaving instance"], function() SetTimedDnd(nil, true) end)
        dndSub:CreateButton(L["Until I turn it off"], function() SetTimedDnd(nil, false) end)
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
                end)
            end
            root:CreateDivider()
            BuildRecentNotificationsSubmenu(root)
            BuildDoNotDisturbMenuSection(root)
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
                        { key = "quickReplyNotifyWhisper", label = L["Quick Reply notifications: Whispers & SocialCentral Chat"], def = true },
                        { key = "quickReplyNotifyBNet", label = L["Quick Reply notifications: Battle.net Messages"], def = true },
                        { key = "quickReplyNotifyParty", label = L["Quick Reply notifications: Party / Instance Chat"], def = true },
                        { key = "quickReplyNotifyRaid", label = L["Quick Reply notifications: Raid Chat"], def = false },
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
                    end
                end)
            end
            root:CreateCheckbox(L["Lock minimap button"], function()
                return ns.db and ns.db.settings and ns.db.settings.minimap and ns.db.settings.minimap.lock
            end, function()
                if ns.db and ns.db.settings and ns.db.settings.minimap then
                    ns.db.settings.minimap.lock = not ns.db.settings.minimap.lock
                end
            end)
            root:CreateCheckbox(L["Show minimap button"], function()
                return not (ns.db and ns.db.settings and ns.db.settings.minimap and ns.db.settings.minimap.hide)
            end, function()
                if ns.db and ns.db.settings and ns.db.settings.minimap then
                    ns.db.settings.minimap.hide = not ns.db.settings.minimap.hide
                    MinimapBtn:Update()
                end
            end)
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
                self.previewCounts.guild = nil
                for k, rec in pairs(self.previewCountsByThread) do
                    if type(rec) == "table" and (rec.cat == "group" or rec.cat == "guild") then
                        self.previewCountsByThread[k] = nil
                    end
                end
            end

            for _, cat in ipairs(BADGE_CATEGORY_ORDER) do
                local pv = (self.previewCounts[cat] or 0) + ((self.testPreviewCounts and self.testPreviewCounts[cat]) or 0)
                if pv > 0 then
                    if cat == "group" or cat == "guild" or counts[cat] == 0 then
                        counts[cat] = counts[cat] + pv
                    end
                end
            end
            for k, rec in pairs(self.previewCountsByThread) do
                if type(rec) == "table" and (rec.count or 0) > 0 and rec.cat and counts[rec.cat] ~= nil then
                    local threadTracked = ns.Chat and ns.Chat.threads and ns.Chat.threads[k] and (ns.Chat.threads[k].unread or 0) > 0
                    if not threadTracked and (rec.cat == "group" or rec.cat == "guild" or counts[rec.cat] == 0) then
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
    for i = 1, 5 do
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
    for i = n + 1, 5 do
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
    else
        anglesDeg = { -90, -18, 54, 126, 198 }
        stepDeg = 72
        baseR = 30
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
    local delta = math.min(dt or 0, 0.05)
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
    local hadAny = next(self.previewCounts) ~= nil or next(self.testPreviewCounts) ~= nil or next(self.previewCountsByThread) ~= nil or self.testCounts ~= nil
    wipe(self.previewCounts)
    wipe(self.testPreviewCounts)
    wipe(self.previewCountsByThread)
    if hadAny then
        return true
    end
    return false
end

local function UpdateBadge(forceFusionAnim)
    local items, totalCount, tones, fullSig, toneSig = BadgeCluster:CollectActiveCategories()
    BadgeCluster.activeItems = items
    BadgeCluster.activeTones = tones
    BadgeCluster.totalCount = totalCount

    local showNumBadge = not (ns.db and ns.db.settings and ns.db.settings.addonMsgMinimapBadge == false)
    local style = BadgeCluster:GetStyle()
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

    if button and button.overlayRing then
        local spotterEnabled = not (ns.db and ns.db.settings and ns.db.settings.spotterEnabled == false)
        if totalCount > 0 then
            if #items == 1 and ns.Theme and ns.Theme.GetChatToneSpec then
                local ac = ns.Theme:GetChatToneSpec(items[1].tone).accent
                button.overlayRing:SetVertexColor(ac[1], ac[2], ac[3])
            else
                button.overlayRing:SetVertexColor(1.0, 0.86, 0.34)
            end
        elseif spotterEnabled and ns.Spotter and select(1, ns.Spotter:GetCounts()) > 0 then
            button.overlayRing:SetVertexColor(0.96, 0.28, 0.28)
        else
            button.overlayRing:SetVertexColor(1, 1, 1)
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
    if BadgeCluster:ClearSessionPreviewCounts() then
        BadgeCluster.testCounts = nil
        UpdateBadge(false)
    end
    local clickMode = (ns.db and ns.db.settings and ns.db.settings.minimapLeftClickAction) or "smart"
    if clickMode == "menu" then
        OpenLeftClickMenu(anchor or button)
        return
    end
    local chatModOn = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("chat")
    local s = ns.db and ns.db.settings
    local qrEnabled = (not s) or s.quickReplyEnabled ~= false
    if chatModOn and ns.Chat and qrEnabled and ns.QuickReply and ns.Chat.HasQuickReplyPending and ns.Chat:HasQuickReplyPending() then
        if ns.QuickReply:OpenLatest() then
            return
        end
    end
    if clickMode == "smart" and chatModOn and ns.Chat then
        local unreadCount = (ns.Chat.GetUnreadDirectCount and ns.Chat:GetUnreadDirectCount())
            or (ns.Chat.GetTotalUnread and ns.Chat:GetTotalUnread(false))
            or 0
        if unreadCount > 0 then
            local unreadThreads = ns.Chat.GetThreadsList and ns.Chat:GetThreadsList("unread") or {}
            local topThread = unreadThreads[1]
            if topThread and topThread.key and ns.NavigateToModule then
                ns:NavigateToModule("chat", { threadKey = topThread.key })
                return
            end
            OpenViaOfficialOrHub("chat")
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
        if ns.Compat and ns.Compat.IsModuleEnabled and not ns.Compat.IsModuleEnabled("watchlist") then
            ns:Print("%s", L["This module is disabled in Settings."])
            return
        end
        if ns.Watchlist then
            ns.Watchlist:CheckNext()
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

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetPoint("CENTER")
    background:SetTexture(BG_TEX)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON_TEX)
    button.icon = icon
    SetIconPressed(false)

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(50, 50)
    overlay:SetPoint("TOPLEFT")
    overlay:SetTexture(RING_TEX)
    button.overlayRing = overlay

    local pulseFrame = CreateFrame("Frame", nil, button)
    pulseFrame:SetAllPoints(button)
    pulseFrame:EnableMouse(false)
    pulseFrame:SetFrameLevel((button:GetFrameLevel() or 8) + 4)
    local pulseGlow = pulseFrame:CreateTexture(nil, "OVERLAY", nil, 4)
    pulseGlow:SetSize(44, 44)
    pulseGlow:SetPoint("CENTER", button, "CENTER", 0, 0)
    pulseGlow:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\toast-glow")
    pulseGlow:SetBlendMode("ADD")
    pulseGlow:SetAlpha(0)
    pulseGlow:Hide()
    button.pulseFrame = pulseFrame
    button.pulseGlow = pulseGlow

    local Theme = ns.Theme
    if Theme and Theme.CreateCounterBadge then
        local badge = Theme:CreateCounterBadge(button, {
            height = 26,
            maxNum = 99,
            haloAlpha = 0.52,
            minFontSize = 15,
            maxFontSize = 20,
            fontScaleOffset = 1,
        })
        badge:SetPoint("CENTER", button, "CENTER", 0, -21)
        badge:SetFrameLevel((button:GetFrameLevel() or 8) + 8)
        button.msgBadgeFrame = badge
        button.badge = badge.text
    else
        local badgeFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
        badgeFrame:SetSize(25, 25)
        badgeFrame:SetPoint("CENTER", button, "CENTER", 0, -21)
        badgeFrame:SetFrameLevel((button:GetFrameLevel() or 8) + 8)
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
        button.msgBadgeFrame = badgeFrame
        button.badge = badgeText
    end

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

    button:SetScript("OnDragStart", function(self)
        if ns.db and ns.db.settings and ns.db.settings.minimap and ns.db.settings.minimap.lock then
            return
        end
        GameTooltip:Hide()
        self:LockHighlight()
        SetIconPressed(true)
        self:SetScript("OnUpdate", function(selfBtn)
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
            end
            UpdatePosition()
        end)
    end)

    button:SetScript("OnDragStop", StopMinimapButtonDrag)
    button:HookScript("OnHide", StopMinimapButtonDrag)

    button:SetScript("OnEnter", function(self)
        BadgeCluster:SetHovered(true)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        PopulateTooltip(GameTooltip)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        BadgeCluster:SetHovered(false)
        GameTooltip:Hide()
    end)
end

--- Return the live SocialCentral minimap button frame (or nil if not built yet).
function MinimapBtn:GetButton()
    return button
end

--- Trigger a brief luminous pulse on the SC minimap icon when a message preview emerges or returns.
function MinimapBtn:PulseArrival(r, g, b)
    if not (button and button:IsShown() and button.pulseFrame and button.pulseGlow) then
        return
    end
    local pf = button.pulseFrame
    local pg = button.pulseGlow
    pg:SetVertexColor(r or 0.98, g or 0.82, b or 0.28, 1)
    pg:SetSize(36, 36)
    pg:SetAlpha(0.05)
    pg:Show()
    local elapsed = 0
    local dur = 0.45
    pf:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + (dt or 0)
        local p = elapsed / dur
        if not button:IsShown() or p >= 1 then
            pg:SetAlpha(0)
            pg:Hide()
            self:SetScript("OnUpdate", nil)
            return
        end
        local alpha = (p < 0.30) and ((p / 0.30) * 0.85) or ((1 - ((p - 0.30) / 0.70)) * 0.85)
        local sz = 36 + (18 * p)
        pg:SetSize(sz, sz)
        pg:SetAlpha(math.max(0, math.min(1, alpha)))
    end)
end

--- Create or refresh visibility, shape position, and badge count of the minimap button.
function MinimapBtn:Update()
    EnsureButton()
    UpdateBadge()
    local hide = ns.db and ns.db.settings and ns.db.settings.minimap and ns.db.settings.minimap.hide
    if hide then
        button:Hide()
    else
        UpdatePosition()
        button:Show()
    end
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
        if cleanTone == "party" or cleanTone == "raid" then cleanTone = "group" end
        if cleanTone ~= "whisper" and cleanTone ~= "group" and cleanTone ~= "guild" and cleanTone ~= "bnet" and cleanTone ~= "room" then
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
    local cat
    if catRaw == "BN_WHISPER" then
        cat = "bnet"
    elseif catRaw == "GUILD" or catRaw == "OFFICER" then
        cat = "guild"
    elseif catRaw == "GROUP" or catRaw == "PARTY" or catRaw == "RAID" or catRaw == "INSTANCE_CHAT" then
        cat = "group"
    elseif catRaw == "ROOM" or catRaw == "ALLIANCE" then
        cat = "room"
    else
        cat = "whisper"
    end
    if item.isTestPreview or item.id and tostring(item.id):sub(1, 8) == "test:mp:" then
        BadgeCluster.testPreviewCounts[cat] = (BadgeCluster.testPreviewCounts[cat] or 0) + 1
        UpdateBadge(true)
    elseif cat == "group" or cat == "guild" then
        local s = ns.db and ns.db.settings
        local mirroredTracked = s and s.chatMirrorChannels == true and s.chatChannelUnread == true
        local qrOn = s and s.quickReplyEnabled ~= false
        local qrKind = item.channelKind or ((cat == "guild") and "GUILD" or "PARTY")
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
            else
                BadgeCluster.previewCounts[cat] = (BadgeCluster.previewCounts[cat] or 0) + 1
            end
            UpdateBadge(true)
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
    elseif kind == "GROUP" or kind == "PARTY" or kind == "RAID" or kind == "INSTANCE_CHAT" then
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
    elseif category == "GROUP" or category == "PARTY" or category == "RAID" or category == "INSTANCE_CHAT" then
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

for _, ev in ipairs({ "CHAT_UPDATED", "CLAN_UPDATED", "SPOTTER_UPDATED", "SETTINGS_CHANGED", "SETTINGS_UPDATED", "ADDON_MESSAGE_NOTIFY" }) do
    ns:On(ev, UpdateBadge)
end

-- ============================================================================
-- Minimap Message Preview Capsule & First-Time Interactive Setup Prompt
-- ============================================================================
-- Displays a compact, 100%-opaque animated preview pill vertically centered on
-- the left side of the Minimap showing the sender's character icon and opening
-- words, then smoothly closes and glides back into the SC minimap icon.
-- Zero taint, 0ms idle CPU (OnUpdate detached whenever idle).
local MsgPreview = {
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

local MP_POS_KEY = "minimap_msg_preview"

local MP_WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local MP_PORTRAIT_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local MP_CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local MP_BNET_TEX = "Interface\\ChatFrame\\UI-ChatIcon-BattleNet"
local MP_MAIL_TEX = "Interface\\AddOns\\SocialCentral\\Media\\toast-mail"
local MP_PARTY_TEX = "Interface\\AddOns\\SocialCentral\\Media\\toast-party"
local MP_GLOW_TEX = "Interface\\AddOns\\SocialCentral\\Media\\toast-glow"

local MP_COLLAPSED_W = 34
local MP_COLLAPSED_H = 34
local MP_MIN_W = 198
local MP_MAX_W = 278
local MP_HEIGHT = 54
local MP_SLOT_GAP = 6
local MP_SLOT_PITCH = MP_HEIGHT + MP_SLOT_GAP
local MP_MAX_SLOTS_CAP = 3
local MP_REST_GAP = 30
local MP_EXPAND_DUR = 0.30
local MP_COLLAPSE_DUR = 0.38
local MP_MAX_QUEUE = 12
local MP_LOGIN_GRACE = 6.0

local mpGradA = CreateColor and CreateColor(1, 1, 1, 1) or nil
local mpGradB = CreateColor and CreateColor(1, 1, 1, 1) or nil

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
    if tex.SetGradient and mpGradA and mpGradB then
        tex:SetTexture(MP_WHITE8X8)
        tex:SetVertexColor(1, 1, 1, 1)
        mpGradA:SetRGBA(r1, g1, b1, a1)
        mpGradB:SetRGBA(r2, g2, b2, a2)
        pcall(tex.SetGradient, tex, orient, mpGradA, mpGradB)
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
    elseif ck == "ROOM" then return (item.roomTitle and item.roomTitle ~= "") and item.roomTitle or L["Private Room"]
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
        local n = (Compat.GetNumGroupMembers and Compat.GetNumGroupMembers()) or 0
        for i = 1, math.min(n, 40) do
            local u = "raid" .. tostring(i)
            if MpUnitMatchesSender(u, tGuid, tLk, tFirstLow) then
                return u
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
        iconTex:SetTexCoord(0.05, 0.95, 0.05, 0.95)
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
    local saved = ns.db and type(ns.db.windowPositions) == "table" and ns.db.windowPositions[MP_POS_KEY]
    if type(saved) == "table" and type(saved.dx) == "number" and type(saved.dy) == "number" then
        local uiW = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1280
        local uiH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 720
        return MpClampCenterToScreen((uiW * 0.5) + saved.dx, (uiH * 0.5) + saved.dy)
    end
    return nil, nil
end

local function MpHasCustomPosition()
    local saved = ns.db and type(ns.db.windowPositions) == "table" and ns.db.windowPositions[MP_POS_KEY]
    return type(saved) == "table" and type(saved.dx) == "number" and type(saved.dy) == "number"
end

local function MpSaveCustomCenter(cx, cy)
    if not ns.db then return end
    if type(ns.db.windowPositions) ~= "table" then
        ns.db.windowPositions = {}
    end
    local uiW = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1280
    local uiH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 720
    local ccx, ccy = MpClampCenterToScreen(cx, cy)
    ns.db.windowPositions[MP_POS_KEY] = {
        dx = math.floor((ccx - (uiW * 0.5)) + 0.5),
        dy = math.floor((ccy - (uiH * 0.5)) + 0.5),
    }
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
    else
        side = (mmLeft >= (MP_MAX_W + MP_REST_GAP + 12)) and "LEFT" or "RIGHT"
        restEdgeX = (side == "LEFT") and (mmLeft - MP_REST_GAP) or (mmRight + MP_REST_GAP)
        restCenterY = mmCenterY
    end

    local startEdgeX, startCenterY
    if button and button:IsShown() and button.GetCenter then
        local bx, by = button:GetCenter()
        local bScale = button:GetEffectiveScale() or 1
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

local function MpApplyThemeToPreview(f)
    if not f then return end
    local Theme = ns.Theme
    local shell = f.pillShell or f
    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(shell, "surface")
    end
    local spec = f._toneSpec or (Theme and Theme.GetChatToneSpec and Theme:GetChatToneSpec(f._toneKey or "whisper"))
    if shell._solidOpaqueBg then
        local bot = (spec and spec.cardBgBot) or { 0.14, 0.05, 0.15, 1.0 }
        shell._solidOpaqueBg:SetVertexColor(bot[1], bot[2], bot[3], 1.0)
    end
    if shell.SetBackdropColor and spec and spec.cardBgBot then
        shell:SetBackdropColor(spec.cardBgBot[1], spec.cardBgBot[2], spec.cardBgBot[3], 1.0)
    end
    if f.bgAmbient and spec and spec.cardBgTop and spec.cardBgBot then
        MpApplyGradient(
            f.bgAmbient, "VERTICAL",
            spec.cardBgBot[1], spec.cardBgBot[2], spec.cardBgBot[3], 1.0,
            spec.cardBgTop[1], spec.cardBgTop[2], spec.cardBgTop[3], 1.0
        )
    end
    if spec and spec.cardBorder and shell.SetBackdropBorderColor then
        local cb = spec.cardBorder
        shell:SetBackdropBorderColor(cb[1], cb[2], cb[3], 1.0)
    elseif f._accentRgb and shell.SetBackdropBorderColor then
        local r, g, b = f._accentRgb[1], f._accentRgb[2], f._accentRgb[3]
        shell:SetBackdropBorderColor(r * 0.65 + 0.16, g * 0.65 + 0.16, b * 0.65 + 0.16, 1.0)
    end
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

local function MpOpenReplyChat(item)
    if not item then return end
    if MpIsInCombat() then
        ns:Print("%s", L["Will open right after combat ends."])
        return
    end
    if item.category == "BN_WHISPER" and Compat and Compat.BNetWhisper then
        Compat.BNetWhisper(item.bnetName or item.sender, item.senderCharName)
    elseif item.category == "WHISPER" and Compat and Compat.Whisper then
        Compat.Whisper(item.senderCharName or item.sender)
    elseif item.replySlash and ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, item.replySlash)
    elseif item.threadKey and ns.NavigateToModule then
        ns:NavigateToModule("chat", { threadKey = item.threadKey })
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
        if qrEnabled and ns.QuickReply and ns.QuickReply.OpenThread and ns.QuickReply:OpenThread(item.threadKey, true) then
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
    if f.progressFill then
        MpApplyGradient(f.progressFill, "HORIZONTAL", rgb[1] * 0.65, rgb[2] * 0.65, rgb[3] * 0.65, 0.94, math.min(1, rgb[1] + 0.22), math.min(1, rgb[2] + 0.22), math.min(1, rgb[3] + 0.22), 1.0)
    end

    local hex = (item.senderClass and Compat and Compat.ClassHex) and Compat.ClassHex(item.senderClass) or "|cffffffff"
    local chanTag = MpChannelLabel(item)
    local chanHex = string.format("|cff%02x%02x%02x", math.floor(rgb[1] * 255), math.floor(rgb[2] * 255), math.floor(rgb[3] * 255))
    local mult = (item.coalescedCount and item.coalescedCount > 1) and (" |cff9da7b5(x" .. tostring(item.coalescedCount) .. ")|r") or ""
    local senderDisp = tostring(item.sender or "?")
    f.senderLbl:SetText(hex .. senderDisp .. "|r " .. chanHex .. "· " .. chanTag .. "|r" .. mult)

    local snippet, fullClean = MpCleanPreviewText(item.text)
    item._fullClean = fullClean
    item._snippet = snippet
    f.previewLbl:SetText(snippet)

    local showQ = (f._showQueueCount or 0)
    if showQ > 0 then
        f.queueLbl:SetText("+" .. tostring(showQ))
        f.queueLbl:Show()
    else
        f.queueLbl:SetText("")
        f.queueLbl:Hide()
    end
    if f.senderLbl and f.contentClip then
        f.senderLbl:ClearAllPoints()
        f.senderLbl:SetPoint("TOPLEFT", f.contentClip, "TOPLEFT", 0, -1)
        f.senderLbl:SetPoint("TOPRIGHT", f.contentClip, "TOPRIGHT", (showQ > 0) and -24 or -2, -1)
    end

    -- Compute sleek dynamic pill width so short pings stay compact while longer snippets stay legible
    local nameW = (f.senderLbl.GetUnboundedStringWidth and f.senderLbl:GetUnboundedStringWidth()) or (f.senderLbl.GetStringWidth and f.senderLbl:GetStringWidth()) or 110
    local bodyW = (f.previewLbl.GetUnboundedStringWidth and f.previewLbl:GetUnboundedStringWidth()) or (f.previewLbl.GetStringWidth and f.previewLbl:GetStringWidth()) or 130
    local idealTextW = math.max(nameW + (showQ > 0 and 22 or 4), math.min(bodyW, 206))
    local computedW = MpClamp(math.ceil(48 + idealTextW + 46), MP_MIN_W, MP_MAX_W)

    MpApplyThemeToPreview(f)
    return computedW
end

local function MpApplySlotVisuals(slot, moveP, sizeP, frameAlpha, scAlpha, senderAlpha, contentAlpha)
    local f = slot and slot.frame
    if not f then return end
    local side, startEdgeX, startCenterY, restEdgeX, restCenterY, flightDist = MpComputeAnchorCoords(f)
    MsgPreview.sideMode = side
    slot.lastFlightDist = flightDist

    local targetRestY = restCenterY + (slot.curOffsetY or 0)
    local arcLift = 0
    if moveP > 0.001 and moveP < 0.999 and (flightDist or 0) > 300 then
        arcLift = math.sin(moveP * math.pi) * MpClamp((flightDist - 300) / 900, 0, 1) * 28
    end
    local curEdgeX = startEdgeX + (restEdgeX - startEdgeX) * moveP
    local curCenterY = startCenterY + (targetRestY - startCenterY) * moveP + arcLift
    local targetW = slot.targetW or MP_MIN_W
    local curW = MP_COLLAPSED_W + (targetW - MP_COLLAPSED_W) * sizeP
    local curH = MP_COLLAPSED_H + (MP_HEIGHT - MP_COLLAPSED_H) * sizeP

    f:ClearAllPoints()
    if side == "LEFT" then
        f:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", curEdgeX, curCenterY)
    else
        f:SetPoint("LEFT", UIParent, "BOTTOMLEFT", curEdgeX, curCenterY)
    end
    f:SetSize(curW, curH)
    f:SetAlpha(MpClamp(frameAlpha, 0, 1))

    if f.pillShell then
        local shellAlpha = MpClamp((sizeP - 0.08) / 0.34, 0, 1)
        f.pillShell:SetAlpha(shellAlpha)
        f.pillShell:SetShown(shellAlpha > 0.01)
    end
    if f.sideBar then
        if f._lastSideBarMode ~= side then
            f._lastSideBarMode = side
            f.sideBar:ClearAllPoints()
            if side == "LEFT" then
                f.sideBar:SetPoint("TOPRIGHT", f.pillShell or f, "TOPRIGHT", -2, -2)
                f.sideBar:SetPoint("BOTTOMRIGHT", f.pillShell or f, "BOTTOMRIGHT", -2, 2)
            else
                f.sideBar:SetPoint("TOPLEFT", f.pillShell or f, "TOPLEFT", 2, -2)
                f.sideBar:SetPoint("BOTTOMLEFT", f.pillShell or f, "BOTTOMLEFT", 2, 2)
            end
        end
        f.sideBar:SetAlpha(MpClamp(sizeP, 0, 1))
    end
    if f.avatarBox then
        local leftPad = 8 * sizeP
        f.avatarBox:ClearAllPoints()
        f.avatarBox:SetPoint("LEFT", f, "LEFT", leftPad, 0)
    end
    if f.scIconTex then
        local sa = MpClamp(scAlpha, 0, 1)
        f.scIconTex:SetAlpha(sa)
        f.scIconTex:SetShown(sa > 0.01)
    end
    if f.senderIconTex then
        local ia = MpClamp(senderAlpha, 0, 1)
        f.senderIconTex:SetAlpha(ia)
        f.senderIconTex:SetShown(ia > 0.01)
    end
    if f.classPipFrame then
        f.classPipFrame:SetAlpha(MpClamp(senderAlpha, 0, 1))
    end
    if f.contentClip then
        local ca = MpClamp(contentAlpha, 0, 1)
        f.contentClip:SetAlpha(ca)
        f.contentClip:SetShown(ca > 0.01 and curW > 76)
    end
    if f.closeBtn then
        local ca = MpClamp(contentAlpha, 0, 1)
        f.closeBtn:SetAlpha(ca)
        f.closeBtn:SetShown(ca > 0.20 and curW > 96)
    end
    if f.muteNotifBtn then
        local ca = MpClamp(contentAlpha, 0, 1)
        f.muteNotifBtn:SetAlpha(ca)
        f.muteNotifBtn:SetShown(ca > 0.20 and curW > 116)
    end
    if f.progressTrack and f.progressFill then
        local pa = MpClamp(contentAlpha, 0, 1)
        f.progressTrack:SetAlpha(pa * 0.85)
        f.progressFill:SetAlpha(pa)
        f.progressTrack:SetShown(pa > 0.15 and curW > 80)
        f.progressFill:SetShown(pa > 0.15 and curW > 80)
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
                    f.senderLbl:SetPoint("TOPRIGHT", f.contentClip, "TOPRIGHT", (wantQ > 0) and -24 or -2, -1)
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
    if type(MsgPreview.dragCenterX) == "number" and type(MsgPreview.dragCenterY) == "number" then
        MpSaveCustomCenter(MsgPreview.dragCenterX, MsgPreview.dragCenterY)
    end
    MsgPreview.dragCenterX = nil
    MsgPreview.dragCenterY = nil
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

    -- Rectangular 100%-opaque pill shell that expands smoothly behind the circular emblem
    local pillShell = CreateFrame("Frame", nil, f, "BackdropTemplate")
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
    bgAmbient:SetPoint("TOPLEFT", pillShell, "TOPLEFT", 2, -2)
    bgAmbient:SetPoint("BOTTOMRIGHT", pillShell, "BOTTOMRIGHT", -2, 2)
    f.bgAmbient = bgAmbient

    local sideBar = pillShell:CreateTexture(nil, "OVERLAY", nil, 2)
    sideBar:SetWidth(3)
    sideBar:SetPoint("TOPRIGHT", pillShell, "TOPRIGHT", -2, -2)
    sideBar:SetPoint("BOTTOMRIGHT", pillShell, "BOTTOMRIGHT", -2, 2)
    sideBar:SetColorTexture(0.96, 0.52, 0.96, 1.0)
    f.sideBar = sideBar

    local topBevel = pillShell:CreateTexture(nil, "BORDER", nil, 1)
    topBevel:SetHeight(1)
    topBevel:SetPoint("TOPLEFT", pillShell, "TOPLEFT", 4, -2)
    topBevel:SetPoint("TOPRIGHT", pillShell, "TOPRIGHT", -4, -2)
    topBevel:SetColorTexture(1, 0.90, 0.68, 0.16)

    local hoverHl = pillShell:CreateTexture(nil, "OVERLAY", nil, 3)
    hoverHl:SetPoint("TOPLEFT", pillShell, "TOPLEFT", 2, -2)
    hoverHl:SetPoint("BOTTOMRIGHT", pillShell, "BOTTOMRIGHT", -2, 2)
    hoverHl:SetColorTexture(1, 0.95, 0.80, 0.07)
    hoverHl:Hide()
    f.hoverHl = hoverHl

    -- Circular Sender Avatar / SC Morph Emblem (34x34)
    local avatarBox = CreateFrame("Frame", nil, f)
    avatarBox:SetSize(34, 34)
    avatarBox:SetPoint("LEFT", f, "LEFT", 0, 0)
    avatarBox:EnableMouse(false)
    avatarBox:SetFrameLevel(f:GetFrameLevel() + 5)
    f.avatarBox = avatarBox

    local avatarHalo = avatarBox:CreateTexture(nil, "BACKGROUND", nil, 1)
    avatarHalo:SetSize(44, 44)
    avatarHalo:SetPoint("CENTER")
    avatarHalo:SetTexture(MP_GLOW_TEX)
    avatarHalo:SetVertexColor(0.96, 0.52, 0.96, 0.34)
    f.avatarHalo = avatarHalo

    local avatarRing = avatarBox:CreateTexture(nil, "ARTWORK", nil, 0)
    avatarRing:SetSize(34, 34)
    avatarRing:SetPoint("CENTER")
    avatarRing:SetTexture(MP_WHITE8X8)
    avatarRing:SetVertexColor(0.96, 0.52, 0.96, 0.94)
    MpApplyCircleMask(avatarBox, avatarRing, 34)
    f.avatarRing = avatarRing

    local avatarCore = avatarBox:CreateTexture(nil, "ARTWORK", nil, 1)
    avatarCore:SetSize(30, 30)
    avatarCore:SetPoint("CENTER")
    avatarCore:SetTexture(MP_WHITE8X8)
    avatarCore:SetVertexColor(0.06, 0.08, 0.12, 1.0)
    MpApplyCircleMask(avatarBox, avatarCore, 30)

    local senderIconTex = avatarBox:CreateTexture(nil, "OVERLAY", nil, 2)
    senderIconTex:SetSize(28, 28)
    senderIconTex:SetPoint("CENTER")
    senderIconTex:SetTexture(MP_MAIL_TEX)
    MpApplyCircleMask(avatarBox, senderIconTex, 28)
    f.senderIconTex = senderIconTex

    local scIconTex = avatarBox:CreateTexture(nil, "OVERLAY", nil, 3)
    scIconTex:SetSize(22, 22)
    scIconTex:SetPoint("CENTER")
    scIconTex:SetTexture(ICON_TEX)
    MpApplyCircleMask(avatarBox, scIconTex, 22)
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
    contentClip:SetPoint("TOPLEFT", f, "TOPLEFT", 48, -6)
    contentClip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -44, 6)
    contentClip:EnableMouse(false)
    contentClip:SetFrameLevel(f:GetFrameLevel() + 3)
    if contentClip.SetClipsChildren then contentClip:SetClipsChildren(true) end
    f.contentClip = contentClip

    local queueLbl = contentClip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if ns.Theme and ns.Theme.ApplyReadableCounterFont then
        ns.Theme:ApplyReadableCounterFont(queueLbl, 14, 17, 0, true)
    end
    queueLbl:SetTextColor(1.0, 0.88, 0.34)
    queueLbl:SetPoint("TOPRIGHT", contentClip, "TOPRIGHT", -1, 0)
    queueLbl:SetJustifyH("RIGHT")
    queueLbl:Hide()
    f.queueLbl = queueLbl

    local senderLbl = contentClip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    senderLbl:SetPoint("TOPLEFT", contentClip, "TOPLEFT", 0, -1)
    senderLbl:SetPoint("TOPRIGHT", contentClip, "TOPRIGHT", -2, -1)
    senderLbl:SetJustifyH("LEFT")
    senderLbl:SetWordWrap(false)
    f.senderLbl = senderLbl

    local previewLbl = contentClip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewLbl:SetPoint("TOPLEFT", senderLbl, "BOTTOMLEFT", 0, -2)
    previewLbl:SetPoint("BOTTOMRIGHT", contentClip, "BOTTOMRIGHT", 0, 1)
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
    muteIco:SetSize(11, 11)
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

    f:SetScript("OnDragStart", function(self)
        local slot = self._slot
        if not slot or slot.phase == "COLLAPSE" then return end
        local side, _, _, restEdgeX, restCenterY = MpComputeAnchorCoords(self)
        local cardW = MpClamp((slot and slot.targetW) or (self.GetWidth and self:GetWidth()) or MP_MAX_W, MP_MIN_W, MP_MAX_W)
        local curCenterX = (side == "LEFT") and (restEdgeX - (cardW * 0.5)) or (restEdgeX + (cardW * 0.5))
        local curCenterY = restCenterY
        local cx, cy = GetCursorPosition()
        local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if uiScale <= 0 then uiScale = 1 end
        MsgPreview.draggingStack = true
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
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(tostring(cur.sender or "SocialCentral"))
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
                    root:CreateButton(MpCategoryDisableLabel(cur.category), function()
                        slot.menuPauseUntil = 0
                        if MsgPreview.ShowConfirmMutePopup then
                            MsgPreview:ShowConfirmMutePopup(self, cur)
                        end
                    end)
                    root:CreateButton(L["Configure Previews..."], function()
                        slot.menuPauseUntil = 0
                        if ns.Settings and ns.Settings.Open then
                            ns.Settings:Open("notifications")
                        end
                    end)
                    root:CreateButton(L["Move Preview Position"], function()
                        slot.menuPauseUntil = 0
                        if MsgPreview.ShowAnchorMover then
                            MsgPreview:ShowAnchorMover()
                        end
                    end)
                    if MpHasCustomPosition() then
                        root:CreateButton(L["Reset Preview Position"], function()
                            slot.menuPauseUntil = 0
                            if MsgPreview.ResetPosition then
                                MsgPreview:ResetPosition()
                            end
                        end)
                    end
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
        local ownerAnchor = (MsgPreview.sideMode == "LEFT") and "ANCHOR_BOTTOMLEFT" or "ANCHOR_BOTTOMRIGHT"
        GameTooltip:SetOwner(self, ownerAnchor)
        GameTooltip:ClearLines()
        GameTooltip:AddDoubleLine(hex .. tostring(cur.sender or "?") .. "|r", MpChannelLabel(cur), 1, 1, 1, rgb[1], rgb[2], rgb[3])
        if cur._fullClean and cur._fullClean ~= "" then
            GameTooltip:AddLine(cur._fullClean, 0.94, 0.96, 0.99, true)
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
        if MsgPreview.draggingStack then
            MpFinishStackDrag()
        end
        if self.hoverHl then self.hoverHl:Hide() end
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)

    MpApplyThemeToPreview(f)
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
    local targetW = MpRenderItemContent(f, item)
    local slot = {
        frame = f,
        item = item,
        phase = "EXPAND",
        phaseTime = 0,
        holdElapsed = 0,
        targetW = targetW,
        curOffsetY = initialY,
        menuPauseUntil = 0,
    }
    f._slot = slot
    table.insert(MsgPreview.activeSlots, slot)
    MpSyncQueueBadges()

    local rgb = MpChannelRGB(item)
    MinimapBtn:PulseArrival(rgb[1], rgb[2], rgb[3])
    MpApplySlotVisuals(slot, 0, 0, 0.05, 1, 0, 0)
    f:Show()

    local drv = MpEnsureDriverFrame()
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
    local delta = math.min(dt or 0, 0.05)
    local active = MsgPreview.activeSlots
    if #active == 0 then
        MpStopAllIdle()
        return
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
    local totalCount = #active
    local finishedIndices = nil

    for idx, slot in ipairs(active) do
        local f = slot.frame
        -- Smoothly glide non-collapsing slots vertically whenever a slot above closes or a new slot joins below
        if slot.phase ~= "COLLAPSE" then
            local desiredY = MpDesiredSlotOffsetY(idx, totalCount)
            local diff = desiredY - (slot.curOffsetY or desiredY)
            if math.abs(diff) > 0.35 then
                slot.curOffsetY = (slot.curOffsetY or desiredY) + diff * math.min(1, delta * 14)
            else
                slot.curOffsetY = desiredY
            end
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
            MpApplySlotVisuals(slot, moveP, sizeP, frameAlpha, scAlpha, senderAlpha, contentAlpha)
            if t >= 1 then
                slot.phase = "HOLD"
                slot.phaseTime = 0
                slot.holdElapsed = 0
                MpApplySlotVisuals(slot, 1, 1, 1, 0, 1, 1)
                if f and f.progressFill then
                    f.progressFill:SetWidth(math.max(1, (slot.targetW or MP_MIN_W) - 11))
                end
            end
        elseif slot.phase == "HOLD" then
            MpApplySlotVisuals(slot, 1, 1, 1, 0, 1, 1)
            local menuPaused = nowMono < (slot.menuPauseUntil or 0)
            local hovered = f and (f:IsMouseOver() or (f.closeBtn and f.closeBtn:IsMouseOver()) or (f.muteNotifBtn and f.muteNotifBtn:IsMouseOver()))
            local totalDur = (slot.item and slot.item.duration) or MpGetHoldDuration()

            if not setupOpen and not moverOpen and not confirmOpen and not MsgPreview.draggingStack and not hovered and not menuPaused then
                slot.holdElapsed = slot.holdElapsed + delta
                local remFrac = MpClamp(1 - (slot.holdElapsed / totalDur), 0, 1)
                if f and f.progressFill then
                    f.progressFill:SetWidth(math.max(1, ((slot.targetW or MP_MIN_W) - 11) * remFrac))
                end
                if slot.holdElapsed >= totalDur then
                    slot.phase = "COLLAPSE"
                    slot.phaseTime = 0
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
            MpApplySlotVisuals(slot, moveP, sizeP, frameAlpha, scAlpha, senderAlpha, contentAlpha)
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
        if #active == 0 then
            MpStopAllIdle()
        end
    end
end

function MsgPreview:PushItem(item, forceShow)
    if type(item) ~= "table" then return end
    local snippet = MpCleanPreviewText(item.text)
    if not snippet or snippet == "" then return end

    local copy = {}
    for k, v in pairs(item) do
        copy[k] = v
    end
    copy.coalescedCount = (type(item.coalescedCount) == "number" and item.coalescedCount > 1) and item.coalescedCount or 1

    if not forceShow then
        local cKey = MpCoalesceKey(copy)
        for _, slot in ipairs(self.activeSlots) do
            if slot.phase ~= "COLLAPSE" and MpCoalesceKey(slot.item) == cKey then
                slot.item.text = copy.text
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
    local _, myClass = ns.Safe and ns.Safe.Call(UnitClass, "player") or nil
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
            id = "test:mp:group:" .. tostring(idx),
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
        sender = (idx == 1) and myName or ("Thalor Valen #" .. tostring(idx)),
        senderCharName = (idx == 1) and myName or "Thalor Valen",
        senderGuid = (idx == 1) and myGuid or nil,
        senderClass = (idx == 1) and (myClass or "ROGUE") or "ROGUE",
        text = L["Hey! Saw you online — want to group up for a dungeon?"],
        priority = 2,
        isTestPreview = (idx == 1),
    }
end

function MsgPreview:ShowFirstTimePrompt(sampleItem, fromManualTrigger)
    if not fromManualTrigger and MpIsInCombat() then
        self.pendingPromptItem = sampleItem
        return
    end
    local Theme = ns.Theme
    local m = self.setupModal
    if not m then
        m = CreateFrame("Frame", "SocialCentralMsgPreviewSetupModal", UIParent, "BackdropTemplate")
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

        local btnEnable = Theme:CreateButton(m, 184, 26, L["Enable Previews"], "primary")
        Theme:AutoFitButton(btnEnable, 146, 20, 214)
        btnEnable:SetPoint("BOTTOMRIGHT", -16, 34)
        m.btnEnable = btnEnable

        local btnDisable = Theme:CreateButton(m, 174, 26, L["No, Disable"], "default")
        Theme:AutoFitButton(btnDisable, 136, 20, 204)
        btnDisable:SetPoint("RIGHT", btnEnable, "LEFT", -10, 0)
        m.btnDisable = btnDisable

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
    m.cbCombat:SetChecked(s and s.msgPreviewSilenceCombat == true or false)
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
        Theme:StyleButton(m.btnEnable, "primary")
        Theme:StyleButton(m.btnDisable, "default")
        if Theme.SyncButtonLayers then
            Theme:SyncButtonLayers(m.closeBtn)
            Theme:SyncButtonLayers(m.btnEnable)
            Theme:SyncButtonLayers(m.btnDisable)
            if m.helpBtn then Theme:SyncButtonLayers(m.helpBtn) end
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

function MsgPreview:ResetPosition()
    if ns.db and type(ns.db.windowPositions) == "table" then
        ns.db.windowPositions[MP_POS_KEY] = nil
    end
    self.draggingStack = false
    self.dragCenterX = nil
    self.dragCenterY = nil
    self:SyncAnchorMoverPosition()
    for _, slot in ipairs(self.activeSlots) do
        if slot.phase == "HOLD" then
            MpApplySlotVisuals(slot, 1, 1, 1, 0, 1, 1)
        end
    end
    ns:Print("%s", L["Message preview position reset beside Minimap."])
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
        if ctrlBar.SetBackdrop then
            ctrlBar:SetBackdrop({
                bgFile = MP_WHITE8X8,
                edgeFile = MP_WHITE8X8,
                edgeSize = 1,
            })
            ctrlBar:SetBackdropColor(0.08, 0.09, 0.12, 1.0)
            ctrlBar:SetBackdropBorderColor(0.92, 0.74, 0.24, 1.0)
        end

        local doneBtn = Theme and Theme:CreateButton(ctrlBar, 82, 22, L["Done"], "primary") or CreateFrame("Button", nil, ctrlBar)
        doneBtn:SetPoint("LEFT", ctrlBar, "LEFT", 6, 0)
        doneBtn:SetScript("OnClick", function()
            MsgPreview:HideAnchorMover(true)
        end)

        local testBtn = Theme and Theme:CreateButton(ctrlBar, 88, 22, L["Test Queue (4)"], "default") or CreateFrame("Button", nil, ctrlBar)
        if Theme and Theme.AutoFitButton then
            Theme:AutoFitButton(testBtn, 78, 12, 108)
        end
        testBtn:SetPoint("CENTER", ctrlBar, "CENTER", 0, 0)
        testBtn:SetScript("OnClick", function()
            MsgPreview:HideAnchorMover(false)
            MsgPreview:ShowTestPreview("queue")
        end)

        local resetBtn = Theme and Theme:CreateButton(ctrlBar, 74, 22, L["Reset"], "default") or CreateFrame("Button", nil, ctrlBar)
        resetBtn:SetPoint("RIGHT", ctrlBar, "RIGHT", -6, 0)
        resetBtn:SetScript("OnClick", function()
            MsgPreview:ResetPosition()
        end)

        m.ctrlBar = ctrlBar
        m.doneBtn = doneBtn
        m.testBtn = testBtn
        m.resetBtn = resetBtn

        m:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        m:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local cx, cy = self:GetCenter()
            if cx and cy then
                MpSaveCustomCenter(cx, cy)
            end
            MsgPreview:SyncAnchorMoverPosition()
        end)
        m:SetScript("OnHide", function(self)
            if self.StopMovingOrSizing then
                pcall(self.StopMovingOrSizing, self)
            end
        end)

        self.anchorMover = m
    end

    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(m, "window")
        if m.SetBackdropBorderColor then
            m:SetBackdropBorderColor(0.96, 0.78, 0.26, 1.0)
        end
    end
    if Theme and Theme.StyleButton then
        Theme:StyleButton(m.doneBtn, "primary")
        Theme:StyleButton(m.testBtn, "default")
        Theme:StyleButton(m.resetBtn, "default")
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
            MinimapBtn:SetTestBadgeMix({ whisper = 1, group = 1, guild = 1 })
        elseif arg == "all" or arg == "5" then
            MinimapBtn:SetTestBadgeMix({ whisper = 2, group = 1, guild = 2, bnet = 1, room = 1 })
        elseif arg:find("whisper", 1, true) or arg:find("pink", 1, true) or arg:find("rosa", 1, true) then
            MinimapBtn:SetTestBadgeCount(tonumber(arg:match("(%d+)")) or 2, "whisper")
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
            if num and num >= 3 then
                local wCnt = math.max(1, math.floor(num / 3))
                local gCnt = math.max(1, math.floor((num - wCnt) / 2))
                local cCnt = math.max(1, num - wCnt - gCnt)
                MinimapBtn:SetTestBadgeMix({ whisper = wCnt, group = gCnt, guild = cCnt })
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
    local cycleIdx = ((self.testCounter - 1) % 4) + 1
    if v == "" then
        local cycleKinds = { "whisper", "bnet", "group", "guild" }
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
        local cleanText = MpCleanPreviewText(payload.text)
        if cleanText and cleanText ~= "" then
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
            Theme:MakeMovable(pop, { key = "modal_msg_preview_confirm" })
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
            local function activateDnd(durSec, untilLeave)
                pop:Hide()
                if Compat and Compat.SetDoNotDisturb then
                    Compat.SetDoNotDisturb(true, durSec, untilLeave)
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
                    root:CreateButton(L["For 30 minutes"], function() activateDnd(1800, false) end)
                    root:CreateButton(L["For 1 hour"], function() activateDnd(3600, false) end)
                    root:CreateButton(L["Until leaving instance"], function() activateDnd(nil, true) end)
                    root:CreateButton(L["Until I turn it off"], function() activateDnd(nil, false) end)
                end)
            else
                activateDnd(nil, false)
            end
        end)
        pop.dndBtn = dndBtn

        pop:SetScript("OnHide", function(selfPop)
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
        Theme:AutoFitButton(pop.playerBtn, 74, 12, 118)
        pop.playerBtn:ClearAllPoints()
        pop.playerBtn:SetPoint("LEFT", pop.confirmBtn, "RIGHT", 6, 0)
        pop.playerBtn:SetScript("OnClick", function()
            pop:Hide()
            spec.playerMuteFn()
        end)
        pop.playerBtn:Show()
        Theme:SetButtonText(pop.confirmBtn, L["Disable All"])
        Theme:AutoFitButton(pop.confirmBtn, 84, 12, 108)
        Theme:AutoFitButton(pop.cancelBtn, 68, 12, 86)
        local neededW = (pop.confirmBtn:GetWidth() or 92) + (pop.playerBtn:GetWidth() or 88) + (pop.cancelBtn:GetWidth() or 74) + 38
        pop:SetWidth(math.max(296, math.min(350, neededW)))
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
        if not (ns.UI and ns.UI.IsChatThreadVisible) then return end
        for _, slot in ipairs(MsgPreview.activeSlots) do
            if slot.item and slot.item.threadKey and ns.UI:IsChatThreadVisible(slot.item.threadKey) then
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
        local s = ns.db and ns.db.settings
        if not s or s.msgPreviewSilenceCombat ~= false then
            HoldActiveAndQueueForCombat()
        end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
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
                MpApplyThemeToPreview(f)
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
                ns.Theme:StyleButton(sm.btnEnable, "primary")
                ns.Theme:StyleButton(sm.btnDisable, "default")
            end
        end)
    end
end

ns.MinimapPreview = MsgPreview
table.insert(ns.modules, MsgPreview)

------------------------------------------------------------------------
-- Compact Quick Reply Popup (Design 10 — Minimap Notification Reply)
------------------------------------------------------------------------
local QuickReply = {
    frame = nil,
    activeKey = nil,
    hasTyped = false,
    hasSentInSession = false,
    openedAt = 0,
    idleCountdown = nil,
    lastInputAt = 0,
    lastStatusState = "",
    lastStatusSec = 0,
    lastStatusDraft = false,
    suppressDraftSave = false,
}

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

function QuickReply:SaveCurrentDraft()
    if self.suppressDraftSave or not self.frame or not self.activeKey or not ns.Chat or not ns.Chat.SetQuickReplyDraft then
        return
    end
    local txt = self.frame.inputBox and self.frame.inputBox:GetText() or ""
    ns.Chat:SetQuickReplyDraft(self.activeKey, txt)
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

function QuickReply:ApplyTheme()
    local f = self.frame
    if not f or not ns.Theme then return end
    local p = ns.Theme:GetPalette()
    if f._solidOpaqueBg then
        local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
        f._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
    end
    ns.Theme:ApplyBackdrop(f, "window", p)
    ns.Theme:ApplyBackdrop(f.header, "surface", p)
    ns.Theme:ApplyBackdrop(f.msgBg, "inset", p)
    ns.Theme:StyleButton(f.btnInvite, "default")
    ns.Theme:StyleButton(f.btnWatch, "default")
    ns.Theme:StyleButton(f.btnExpand, "default")
    ns.Theme:StyleButton(f.btnClose, "default")
    ns.Theme:StyleButton(f.btnSend, "primary")
    if f.btnAllQuickReplies then
        ns.Theme:StyleButton(f.btnAllQuickReplies, "default")
    end
    if f.btnRaidMark then
        ns.Theme:StyleButton(f.btnRaidMark, "default")
    end
    if f.btnScrollBottom then
        ns.Theme:StyleButton(f.btnScrollBottom, "default")
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
    QuickReply.historyIdx = nil
    QuickReply._historyDraft = nil
end

function QuickReply:SendInstantReply(rawMsg)
    if not self.activeKey or not ns.Chat then return false end
    local clean = ns.Compat and ns.Compat.Trim and ns.Compat.Trim(rawMsg) or rawMsg
    if not clean or clean == "" then return false end
    local sent = ns.Chat:SendOrOpenReply(self.activeKey, clean, true)
    if sent ~= false then
        PushQuickReplyHistory(clean)
        if ns.Chat.MarkThreadRead then
            ns.Chat:MarkThreadRead(self.activeKey)
        end
        self.hasSentInSession = true
        self.lastInputAt = GetTime()
        self.idleCountdown = nil
        self.lastStatusState = ""
        self:Refresh()
        UpdateBadge(false)
        return true
    end
    return false
end

local function BuildQuickReplyPingsBar(f, Theme)
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 32)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 32)
    bar:SetHeight(20)
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
        local list = ns.Chat.GetQuickReplies and ns.Chat:GetQuickReplies() or {}
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            root:CreateTitle(L["Quick Replies"])
            for _, tpl in ipairs(list) do
                local exp = (ns.Chat.ExpandQuickReplyText and ns.Chat:ExpandQuickReplyText(tpl)) or tpl
                root:CreateButton(exp, function()
                    QuickReply:SendInstantReply(exp)
                end)
            end
            if ns.Chat.GetCategorizedQuickReplies then
                root:CreateDivider()
                for _, cat in ipairs(ns.Chat:GetCategorizedQuickReplies()) do
                    local cSub = root:CreateButton(cat.title)
                    for _, cTpl in ipairs(cat.items) do
                        local exp = (ns.Chat.ExpandQuickReplyText and ns.Chat:ExpandQuickReplyText(cTpl)) or cTpl
                        cSub:CreateButton(exp, function()
                            QuickReply:SendInstantReply(exp)
                        end)
                    end
                end
            end
        end)
    end)
    f.btnAllQuickReplies = btnAll

    local btnRaidMark = Theme:CreateButton(bar, 22, 19, "", "default")
    btnRaidMark:SetPoint("RIGHT", btnAll, "LEFT", -4, 0)
    Theme:ConfigureIconButton(btnRaidMark, 22, 19, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", {
        size = 13,
        title = L["Raid Target Icons ({rt1}..{rt8})"],
        desc = L["Insert a raid target marker into your message."],
    })
    btnRaidMark:SetScript("OnClick", function(selfBtn)
        if Theme.OpenRaidMarkPickerMenu and f.inputBox then
            Theme:OpenRaidMarkPickerMenu(selfBtn, f.inputBox)
        end
    end)
    f.btnRaidMark = btnRaidMark

    f.pingBtns = {}
    for i = 1, 3 do
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

local function RefreshQuickReplyPingsBar(f, t)
    if not (f and f.quickPingsBar) then return end
    local allowPings = (t.kind ~= "NOTES" and t.kind ~= "MENTIONS")
    f.quickPingsBar:SetShown(allowPings)
    local stY = allowPings and 54 or 30
    if f.statusText then
        f.statusText:ClearAllPoints()
        f.statusText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, stY)
        f.statusText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, stY)
    end
    f.msgBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, allowPings and 68 or 44)
    if not allowPings then return end
    local list = (ns.Chat and ns.Chat.GetQuickReplies) and ns.Chat:GetQuickReplies() or {}
    local availW = (f:GetWidth() or 396) - 12 - 54
    local cx = 0
    for i = 1, #f.pingBtns do
        local pBtn = f.pingBtns[i]
        local rawTpl = list[i]
        if rawTpl and rawTpl ~= "" then
            local expanded = (ns.Chat and ns.Chat.ExpandQuickReplyText) and ns.Chat:ExpandQuickReplyText(rawTpl) or rawTpl
            pBtn._pingFullText = expanded
            ns.Theme:SetButtonText(pBtn, QuickReply:TruncateUtf8(expanded, 16))
            ns.Theme:AutoFitButton(pBtn, 48, 10, 108)
            local bw = math.floor((pBtn._scAutoFitW or pBtn:GetWidth() or 70) + 0.5)
            if (cx + bw) <= availW then
                pBtn:ClearAllPoints()
                pBtn:SetPoint("LEFT", f.quickPingsBar, "LEFT", cx, 0)
                pBtn:Show()
                cx = cx + bw + 4
            else
                pBtn:Hide()
            end
        else
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
    MenuUtil.CreateContextMenu(msgFrame, function(_, root)
        root:CreateTitle(senderLbl)
        root:CreateButton(L["Quote Reply"], function()
            local box = QuickReply.frame and QuickReply.frame.inputBox
            if not box then return end
            local snippet = (#rawPlain > 45) and (rawPlain:sub(1, 42) .. "...") or rawPlain
            local quote = string.format("> %s: \"%s\" ", senderLbl, snippet)
            box:SetText(quote)
            if box.SetCursorPosition then box:SetCursorPosition(#quote) end
            if box.SetFocus and not (InCombatLockdown and InCombatLockdown()) then pcall(box.SetFocus, box) end
        end)
        if k ~= "notes:self" and ns.Chat and ns.Chat.SavePersonalNote then
            root:CreateButton(L["Save to Personal Notes"], function()
                ns.Chat:SavePersonalNote("[" .. senderLbl .. "] " .. rawPlain)
                ns:Print("%s", L["Saved to Personal Notes."])
            end)
        end
        root:CreateButton(L["Copy Message"], function()
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
    MenuUtil.CreateContextMenu(msgFrame, function(_, root)
        root:CreateTitle(cleanName)
        root:CreateButton(L["Whisper in Quick Reply"], function()
            if ns.Chat and ns.Chat.EnsureWhisperThread then
                local wt = ns.Chat:EnsureWhisperThread(cleanName)
                if wt and wt.key then
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
                if ns.Compat and ns.Compat.Invite then
                    ns.Compat.Invite(cleanName)
                end
            end)
            if ns.Watchlist and ns.Watchlist.Add and not (ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(lk)) then
                root:CreateButton("+ " .. L["Watchlist"], function()
                    ns.Watchlist:Add(cleanName)
                    QuickReply:Refresh()
                end)
            end
            if ns.SocialPanels and ns.SocialPanels.OpenSocialMetaModal then
                root:CreateButton(L["Edit Social Card"], function()
                    ns.SocialPanels:OpenSocialMetaModal(cleanName, lk, { displayName = cleanName, lookupKey = lk })
                end)
            end
        end
        root:CreateButton(L["Copy Name"], function()
            if ns.UI and ns.UI.OpenCopyModal then
                ns.UI:OpenCopyModal(cleanName, L["Copy Name"])
            end
        end)
    end)
end

local function AttachQuickReplyMsgFrameHandlers(f, msgFrame, Theme)
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
        elseif link:find("addon:SCentral:msgact:", 1, true) then
            local idx = tonumber(link:match("addon:SCentral:msgact:(%d+)"))
            OpenQuickReplyMessageActionsMenu(selfMsg, idx)
        elseif link:find("addon:SCentral:w:", 1, true) then
            local who = link:match("addon:SCentral:w:([^|]+)")
            if who and who ~= "" then
                if button == "RightButton" then
                    OpenQuickReplySenderMenu(selfMsg, who)
                elseif ns.Chat and ns.Chat.EnsureWhisperThread then
                    local wt = ns.Chat:EnsureWhisperThread(who)
                    if wt and wt.key then
                        if wt.key ~= QuickReply.activeKey then
                            QuickReply:SaveCurrentDraft()
                            QuickReply:SelectThread(wt.key, true)
                        elseif f.inputBox and f.inputBox.SetFocus and not (InCombatLockdown and InCombatLockdown()) then
                            pcall(f.inputBox.SetFocus, f.inputBox)
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

function QuickReply:EnsureFrame()
    if self.frame then
        return self.frame
    end
    local Theme = ns.Theme
    local f = CreateFrame("Frame", "SocialCentralQuickReplyFrame", UIParent, "BackdropTemplate")
    f:Hide()
    f:SetSize(396, 320)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(320)
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    table.insert(UISpecialFrames, "SocialCentralQuickReplyFrame")

    local solidBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetAllPoints()
    solidBg:SetTexture(MP_WHITE8X8)
    solidBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    f._solidOpaqueBg = solidBg

    -- Header bar (draggable handle)
    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    header:SetHeight(42)
    header:EnableMouse(true)
    f.header = header

    local toneBar = header:CreateTexture(nil, "ARTWORK", nil, 2)
    toneBar:SetWidth(3)
    toneBar:SetPoint("TOPLEFT", header, "TOPLEFT", 2, -4)
    toneBar:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 2, 4)
    toneBar:SetTexture(MP_WHITE8X8)
    f.toneBar = toneBar

    local classIco = header:CreateTexture(nil, "ARTWORK", nil, 2)
    classIco:SetSize(24, 24)
    classIco:SetPoint("LEFT", toneBar, "RIGHT", 6, 0)
    f.classIco = classIco

    local statusDot = header:CreateTexture(nil, "OVERLAY", nil, 4)
    statusDot:SetSize(10, 10)
    statusDot:SetPoint("BOTTOMRIGHT", classIco, "BOTTOMRIGHT", 2, -2)
    statusDot:Hide()
    f.statusDot = statusDot

    header:HookScript("OnEnter", function(selfHdr)
        local hm = f._headerMeta
        if not (hm and GameTooltip) then return end
        GameTooltip:SetOwner(selfHdr, "ANCHOR_TOP")
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
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Drag anywhere on screen"], 0.62, 0.70, 0.80, true)
        GameTooltip:Show()
    end)
    header:HookScript("OnLeave", function(selfHdr)
        if GameTooltip and GameTooltip:IsOwned(selfHdr) then
            GameTooltip:Hide()
        end
    end)

    local btnClose = Theme:CreateButton(header, 22, 20, "", "default")
    btnClose:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    Theme:ConfigureIconButton(btnClose, 22, 20, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", {
        size = 12,
        color = { 0.95, 0.65, 0.65 },
        title = L["Close"],
        desc = "ESC",
    })
    btnClose:SetScript("OnClick", function()
        QuickReply:SaveCurrentDraft()
        f:Hide()
    end)
    f.btnClose = btnClose

    local btnExpand = Theme:CreateButton(header, 24, 20, "", "default")
    btnExpand:SetPoint("RIGHT", btnClose, "LEFT", -4, 0)
    Theme:ConfigureIconButton(btnExpand, 24, 20, "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", {
        size = 14,
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

    local btnWatch = Theme:CreateButton(header, 24, 20, "", "default")
    btnWatch:SetPoint("RIGHT", btnExpand, "LEFT", -4, 0)
    Theme:ConfigureIconButton(btnWatch, 24, 20, "Interface\\Icons\\INV_Misc_Spyglass_03", {
        size = 14,
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

    local btnInvite = Theme:CreateButton(header, 24, 20, "", "default")
    btnInvite:SetPoint("RIGHT", btnWatch, "LEFT", -4, 0)
    Theme:ConfigureIconButton(btnInvite, 24, 20, "Interface\\PaperDollInfoFrame\\Character-Plus", {
        size = 14,
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

    local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", classIco, "TOPRIGHT", 7, -1)
    titleText:SetPoint("RIGHT", btnInvite, "LEFT", -6, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    f.titleText = titleText

    local subText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subText:SetPoint("BOTTOMLEFT", classIco, "BOTTOMRIGHT", 7, 1)
    subText:SetPoint("RIGHT", btnInvite, "LEFT", -6, 0)
    subText:SetJustifyH("LEFT")
    subText:SetWordWrap(false)
    f.subText = subText

    -- Pending notification / draft chips bar (shown when >= 2 threads pending)
    local chipsBar = CreateFrame("Frame", nil, f)
    chipsBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    chipsBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
    chipsBar:SetHeight(22)
    chipsBar:Hide()
    f.chipsBar = chipsBar
    f.chips = {}
    for i = 1, 5 do
        local cBtn = Theme:CreateButton(chipsBar, 64, 19, "", "default")
        cBtn:Hide()
        cBtn:SetScript("OnClick", function(selfBtn)
            if selfBtn._threadKey then
                QuickReply:SaveCurrentDraft()
                QuickReply:SelectThread(selfBtn._threadKey, true)
            end
        end)
        f.chips[i] = cBtn
    end

    -- Messages viewport
    local msgBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    msgBg:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -5)
    msgBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 68)
    f.msgBg = msgBg

    local msgFrame = CreateFrame("ScrollingMessageFrame", nil, msgBg)
    msgFrame:SetClipsChildren(true)
    msgFrame:SetPoint("TOPLEFT", msgBg, "TOPLEFT", 7, -6)
    msgFrame:SetPoint("BOTTOMRIGHT", msgBg, "BOTTOMRIGHT", -7, 6)
    msgFrame:SetFontObject(_G.ChatFontNormal or "GameFontHighlightSmall")
    msgFrame:SetJustifyH("LEFT")
    if msgFrame.SetSpacing then
        msgFrame:SetSpacing(2)
    end
    if msgFrame.SetIndentedWordWrap then
        msgFrame:SetIndentedWordWrap(true)
    end
    if msgFrame.SetInsertMode then
        msgFrame:SetInsertMode("BOTTOM")
    end
    msgFrame:SetFading(false)
    msgFrame:SetMaxLines(60)
    msgFrame:EnableMouse(true)
    if msgFrame.SetHyperlinksEnabled then
        msgFrame:SetHyperlinksEnabled(true)
    end
    msgFrame:EnableMouseWheel(true)
    f.msgFrame = msgFrame

    local btnScrollBottom = Theme:CreateButton(msgBg, 22, 20, "", "default")
    Theme:ConfigureIconButton(btnScrollBottom, 22, 20, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", {
        size = 14,
        color = { 0.95, 0.88, 0.72 },
        title = L["Jump to latest messages"],
    })
    btnScrollBottom:SetPoint("BOTTOMRIGHT", msgFrame, "BOTTOMRIGHT", -2, 2)
    btnScrollBottom:SetFrameLevel((msgFrame:GetFrameLevel() or 2) + 5)
    btnScrollBottom:Hide()
    btnScrollBottom:SetScript("OnClick", function()
        if msgFrame.ScrollToBottom then
            msgFrame:ScrollToBottom()
        end
        btnScrollBottom:Hide()
    end)
    f.btnScrollBottom = btnScrollBottom

    msgFrame:SetScript("OnMouseWheel", function(selfMsg, delta)
        if delta > 0 then
            selfMsg:ScrollUp()
        else
            selfMsg:ScrollDown()
        end
        local atBot = selfMsg.AtBottom and selfMsg:AtBottom()
        btnScrollBottom:SetShown(atBot == false)
    end)
    AttachQuickReplyMsgFrameHandlers(f, msgFrame, Theme)

    -- Status / countdown micro-label above quick-reply pings & input
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 54)
    statusText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 54)
    statusText:SetJustifyH("RIGHT")
    statusText:SetText("")
    f.statusText = statusText

    BuildQuickReplyPingsBar(f, Theme)

    if Theme and Theme.MakeMovable then
        Theme:MakeMovable(f, {
            key = "quickReply",
            handles = { header, chipsBar, msgBg, msgFrame, f.quickPingsBar, f },
        })
    end

    -- Footer: Input + Send
    local btnSend = Theme:CreateButton(f, 64, 22, L["Send"], "primary")
    btnSend:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    Theme:AutoFitButton(btnSend, 54, 14, 82)
    f.btnSend = btnSend

    local inputBox = Theme:CreateEditBox(f, {
        name = "SocialCentralQuickReplyInput",
        width = 240,
        height = 22,
        maxLetters = 255,
        insertLinkMode = "full",
        placeholder = L["Type a quick reply..."],
    })
    if inputBox.SetAltArrowKeyMode then
        inputBox:SetAltArrowKeyMode(false)
    end
    inputBox:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 6)
    inputBox:SetPoint("RIGHT", btnSend, "LEFT", -6, 0)
    f.inputBox = inputBox

    local function SubmitQuickReply()
        if not QuickReply.activeKey or not ns.Chat then return end
        local raw = inputBox:GetText() or ""
        local clean = ns.Compat and ns.Compat.Trim and ns.Compat.Trim(raw) or raw
        if clean == "" then return end
        local sent = ns.Chat:SendOrOpenReply(QuickReply.activeKey, clean, true)
        if sent ~= false then
            PushQuickReplyHistory(clean)
            QuickReply.suppressDraftSave = true
            inputBox:SetText("")
            QuickReply.suppressDraftSave = false
            ns.Chat:SetQuickReplyDraft(QuickReply.activeKey, "")
            ns.Chat:MarkThreadRead(QuickReply.activeKey)
            QuickReply.hasTyped = true
            QuickReply.hasSentInSession = true
            QuickReply.lastInputAt = GetTime()
            QuickReply.idleCountdown = nil
            QuickReply.lastStatusState = ""
            QuickReply:Refresh()
            UpdateBadge(false)
        end
    end

    pcall(inputBox.SetScript, inputBox, "OnArrowPressed", function(selfBox, key)
        local hist = QuickReply.sentHistory
        if not (hist and #hist > 0) then return end
        if key ~= "UP" and key ~= "DOWN" then return end
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
    inputBox:SetScript("OnEnterPressed", function(selfBox)
        SubmitQuickReply()
        selfBox:SetFocus()
    end)
    inputBox:SetScript("OnEscapePressed", function(selfBox)
        QuickReply:SaveCurrentDraft()
        selfBox:ClearFocus()
        f:Hide()
    end)
    inputBox:HookScript("OnTextChanged", function(selfBox)
        if not QuickReply.suppressDraftSave then
            if not QuickReply._historyNav then
                QuickReply.historyIdx = nil
                QuickReply._historyDraft = nil
            end
            local txt = selfBox:GetText() or ""
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
    end)

    -- 10-second inactivity auto-close ticker (zero per-frame GC via scalar memoization, detached on hide)
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
        end
    end

    local function QuickReplyOnUpdate(selfFrame, elapsed)
        local s = ns.db and ns.db.settings
        local curTxt = inputBox:GetText() or ""
        local hasDraft = curTxt ~= ""
        if hasDraft then
            QuickReply.idleCountdown = nil
            SetStatusMemo(selfFrame, "draft", 0, true, "|cffffd24d" .. L["Draft saved"] .. "|r")
            return
        end
        if not s or s.quickReplyAutoClose == false then
            QuickReply.idleCountdown = nil
            if QuickReply.lastStatusState ~= "off" then
                SetStatusMemo(selfFrame, "off", 0, false, "")
            end
            return
        end
        local now = GetTime()
        local canAutoClose = (QuickReply.hasSentInSession == true) or ((now - (QuickReply.openedAt or now)) >= 5.0)
        local activelyTyping = (inputBox:HasFocus() and (now - (QuickReply.lastInputAt or 0)) < 3.0)
        local hovering = (selfFrame:IsMouseOver() or (f.msgFrame and f.msgFrame._scHoveredHyperlink ~= nil) or (GameTooltip and f.msgFrame and GameTooltip:IsOwned(f.msgFrame)))
            and not (InCombatLockdown and InCombatLockdown())
        if selfFrame._scDragging or (not canAutoClose) or activelyTyping or hovering then
            QuickReply.idleCountdown = nil
            if QuickReply.lastStatusState ~= "idle" then
                SetStatusMemo(selfFrame, "idle", 0, false, "")
            end
            return
        end
        QuickReply.idleCountdown = (QuickReply.idleCountdown or 10.0) - elapsed
        if QuickReply.idleCountdown <= 0 then
            QuickReply:SaveCurrentDraft()
            QuickReply.idleCountdown = nil
            QuickReply.lastStatusState = ""
            selfFrame:Hide()
            UpdateBadge(false)
            return
        end
        local sec = math.ceil(QuickReply.idleCountdown)
        SetStatusMemo(selfFrame, "tick", sec, false, "|cff9da7b5" .. L["Closing in %ds"]:format(sec) .. "|r")
    end

    f:HookScript("OnShow", function(selfFrame)
        if ns.Theme and ns.Theme.RestoreWindowPosition then
            ns.Theme:RestoreWindowPosition(selfFrame, "quickReply", false)
        end
        if selfFrame.btnScrollBottom and selfFrame.msgFrame then
            selfFrame.btnScrollBottom:SetFrameLevel((selfFrame.msgFrame:GetFrameLevel() or 2) + 5)
        end
        QuickReply.idleCountdown = nil
        QuickReply.hasSentInSession = false
        QuickReply.openedAt = GetTime()
        QuickReply.lastStatusState = ""
        QuickReply.lastStatusSec = 0
        QuickReply.lastStatusDraft = false
        QuickReply.lastInputAt = GetTime()
        selfFrame:SetScript("OnUpdate", QuickReplyOnUpdate)
    end)
    f:HookScript("OnHide", function(selfFrame)
        selfFrame:SetScript("OnUpdate", nil)
        QuickReply:SaveCurrentDraft()
        if QuickReply.activeKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[QuickReply.activeKey] then
            local closedT = ns.Chat.threads[QuickReply.activeKey]
            closedT.lastReadBannerTs = nil
            closedT.lastReadBannerEntry = nil
        end
        QuickReply.idleCountdown = nil
        QuickReply.lastStatusState = ""
        QuickReply.lastStatusSec = 0
        QuickReply.lastStatusDraft = false
        UpdateBadge(false)
    end)

    self.frame = f
    self:ApplyTheme()
    return f
end

function QuickReply:SelectThread(threadKey, focusInput)
    if not threadKey or not ns.Chat or not ns.Chat.threads then
        return false
    end
    local t = ns.Chat.threads[threadKey]
    if not t then
        return false
    end
    local f = self:EnsureFrame()
    if self.activeKey and self.activeKey ~= threadKey and ns.Chat.threads[self.activeKey] then
        local prevT = ns.Chat.threads[self.activeKey]
        prevT.lastReadBannerTs = nil
        prevT.lastReadBannerEntry = nil
    end
    self.activeKey = threadKey
    self.historyIdx = nil
    self._historyDraft = nil
    if ns.Chat.MarkThreadRead then
        ns.Chat:MarkThreadRead(threadKey)
    end
    local draft = ns.Chat.GetQuickReplyDraft and ns.Chat:GetQuickReplyDraft(threadKey) or ""
    self.suppressDraftSave = true
    f.inputBox:SetText(draft or "")
    if f.inputBox.UpdatePlaceholder then
        f.inputBox:UpdatePlaceholder()
    end
    self.suppressDraftSave = false
    self.hasTyped = (draft ~= nil and draft ~= "")
    self.hasSentInSession = false
    self.openedAt = GetTime()
    self.lastInputAt = GetTime()
    self.idleCountdown = nil
    self:Refresh()
    if focusInput and f.inputBox and not (InCombatLockdown and InCombatLockdown()) then
        f.inputBox:SetFocus()
    end
    UpdateBadge(false)
    return true
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

    -- Tone & rich player/channel header summary
    local toneKey = ns.Theme and ns.Theme.GetChatToneForKind and ns.Theme:GetChatToneForKind(t.kind) or "whisper"
    local toneSpec = ns.Theme and ns.Theme.GetChatToneSpec and ns.Theme:GetChatToneSpec(toneKey)
    local tc = (toneSpec and toneSpec.accent) or { 0.85, 0.72, 0.36 }
    local tcHex = (toneSpec and toneSpec.hex) or "|cffffd24d"
    f.toneBar:SetColorTexture(tc[1], tc[2], tc[3], 0.95)

    local isPlayerThread = (t.kind == "WHISPER" or t.kind == "BN_WHISPER")
    local titleStr = t.title or t.targetName or self.activeKey
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
    local isOnline = (sRow and sRow.online == true)
        or (wl and wl.status == "online")
        or (ns.Compat and ns.Compat.IsInMyGroup and ns.Compat.IsInMyGroup(t.targetName or titleStr or lk)) == true
    local isAfk = (sRow and sRow.afk == true) == true
    local isDnd = (sRow and sRow.dnd == true) == true

    local clsCoords = (isPlayerThread and classFile and CLASS_ICON_TCOORDS) and CLASS_ICON_TCOORDS[classFile] or nil
    if clsCoords then
        f.classIco:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        f.classIco:SetTexCoord(clsCoords[1] + 0.02, clsCoords[2] - 0.02, clsCoords[3] + 0.02, clsCoords[4] - 0.02)
    elseif t.kind == "BN_WHISPER" then
        f.classIco:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-BattleNet")
        f.classIco:SetTexCoord(0, 1, 0, 1)
    elseif t.kind == "GUILD" or t.kind == "OFFICER" or t.kind == "ALLIANCE" then
        f.classIco:SetTexture("Interface\\GossipFrame\\TabardGossipIcon")
        f.classIco:SetTexCoord(0, 1, 0, 1)
    elseif t.kind == "PARTY" or t.kind == "RAID" or t.kind == "INSTANCE_CHAT" then
        f.classIco:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        f.classIco:SetTexCoord(0, 1, 0, 1)
    elseif t.kind == "ROOM" then
        f.classIco:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\icon")
        f.classIco:SetTexCoord(0, 1, 0, 1)
    else
        f.classIco:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
        f.classIco:SetTexCoord(0, 1, 0, 1)
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

    local line1Parts = {}
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
        line1Parts[#line1Parts + 1] = ns.Compat.AddonIconMarkup(12)
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
    elseif t.kind == "GUILD" then chanLabel = L["Guild"]
    elseif t.kind == "OFFICER" then chanLabel = L["Officer"]
    elseif t.kind == "ALLIANCE" then chanLabel = L["Alliance"]
    elseif t.kind == "PARTY" then chanLabel = L["Group"]
    elseif t.kind == "RAID" then chanLabel = L["Raid"]
    elseif t.kind == "INSTANCE_CHAT" then chanLabel = L["Instance"]
    elseif t.kind == "ROOM" then chanLabel = L["Private Room"]
    end

    local subParts = { tcHex .. chanLabel .. "|r" }
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
    local relParts = {}
    if isFriend then relParts[#relParts + 1] = L["Friends"] end
    if isBNet then relParts[#relParts + 1] = L["Battle.net"] end
    if isGuildSrc then relParts[#relParts + 1] = L["Guild"] end
    if wl then relParts[#relParts + 1] = L["Watchlist"] end
    if isSC then relParts[#relParts + 1] = L["SocialCentral [SC]"] end
    f._headerMeta = {
        tooltipTitle = coloredName,
        channelLabel = chanLabel,
        accentR = tc[1],
        accentG = tc[2],
        accentB = tc[3],
        statusLabel = isPlayerThread and statusLbl or nil,
        statusR = stR,
        statusG = stG,
        statusB = stB,
        level = isPlayerThread and level or 0,
        classLocalized = (classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or nil,
        zone = isPlayerThread and zone or "",
        guild = isPlayerThread and guild or "",
        relText = isPlayerThread and table.concat(relParts, ", ") or "",
        flagLabel = flagLabel,
        flagR = flagR,
        flagG = flagG,
        flagB = flagB,
        noteText = rawNote and self:TruncateUtf8(rawNote, 60) or "",
    }

    -- Action buttons (Invite + Watchlist)
    local canInv = self:CanInviteThread(t)
    f.btnInvite:SetShown(canInv == true)

    local watchKey = t.lookupKey or t.targetName
    local canWatch = isPlayerThread and watchKey ~= nil and watchKey ~= "" and ns.Watchlist ~= nil
    f.btnWatch:SetShown(canWatch)
    if canWatch then
        local watched = ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(watchKey)
        f.btnWatch:SetEnabled(not watched)
        ns.Theme:SetButtonActive(f.btnWatch, watched == true, "default")
        ns.Theme:ConfigureIconButton(
            f.btnWatch,
            24,
            20,
            watched and "Interface\\RAIDFRAME\\ReadyCheck-Ready" or "Interface\\Icons\\INV_Misc_Spyglass_03",
            {
                size = 14,
                disabled = watched == true,
                title = watched and L["Watched"] or ("+ " .. L["Watchlist"]),
                desc = watched and L["Already monitored on your Watchlist."] or L["Track login alerts, zone updates, and status via safe /who."],
            }
        )
    end

    local leftRef = f.btnExpand
    if f.btnWatch:IsShown() then
        f.btnWatch:ClearAllPoints()
        f.btnWatch:SetPoint("RIGHT", leftRef, "LEFT", -4, 0)
        leftRef = f.btnWatch
    end
    if f.btnInvite:IsShown() then
        f.btnInvite:ClearAllPoints()
        f.btnInvite:SetPoint("RIGHT", leftRef, "LEFT", -4, 0)
        leftRef = f.btnInvite
    end
    f.titleText:ClearAllPoints()
    f.titleText:SetPoint("TOPLEFT", f.classIco, "TOPRIGHT", 7, -1)
    f.titleText:SetPoint("RIGHT", leftRef, "LEFT", -6, 0)
    f.subText:ClearAllPoints()
    f.subText:SetPoint("BOTTOMLEFT", f.classIco, "BOTTOMRIGHT", 7, 1)
    f.subText:SetPoint("RIGHT", leftRef, "LEFT", -6, 0)

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
        table.insert(pending, 1, {
            key = self.activeKey,
            title = titleStr,
            kind = t.kind,
            unread = 0,
            hasDraft = (f.inputBox:GetText() or "") ~= "",
        })
    end

    local showChips = #pending >= 2
    f.chipsBar:SetShown(showChips)
    f.msgBg:ClearAllPoints()
    if showChips then
        f.msgBg:SetPoint("TOPLEFT", f.chipsBar, "BOTTOMLEFT", 0, -4)
        local cx = 0
        local maxW = (f:GetWidth() or 360) - 14
        for i = 1, #f.chips do
            local btn = f.chips[i]
            local item = pending[i]
            if item then
                btn._threadKey = item.key
                local shortName = self:TruncateUtf8(item.title or "?", 11)
                local suffix = (item.unread and item.unread > 0) and (" (" .. item.unread .. ")") or (item.hasDraft and " *" or "")
                ns.Theme:SetButtonText(btn, shortName .. suffix)
                ns.Theme:SetButtonActive(btn, item.key == self.activeKey, "default")
                ns.Theme:AutoFitButton(btn, 44, 10, 96)
                local bw = math.floor((btn._scAutoFitW or btn:GetWidth() or 60) + 0.5)
                if (cx + bw) <= maxW then
                    btn:ClearAllPoints()
                    btn:SetPoint("LEFT", f.chipsBar, "LEFT", cx, 0)
                    btn:Show()
                    cx = cx + bw + 4
                else
                    btn:Hide()
                end
            else
                btn:Hide()
            end
        end
    else
        f.msgBg:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -5)
    end
    RefreshQuickReplyPingsBar(f, t)
    if f.inputBox then f.inputBox:SetEnabled(t.kind ~= "MENTIONS") end
    if f.btnSend then f.btnSend:SetEnabled(t.kind ~= "MENTIONS") end

    -- Populate latest messages (preserving scroll offset if scrolled up on the same thread)
    local msgs = ns.Chat.GetThreadMessages and ns.Chat:GetThreadMessages(self.activeKey) or t.messages or {}
    local startIdx = math.max(1, #msgs - 49)
    local sameThread = (self._renderedThreadKey == self.activeKey)
    local wasAtBottom = (not f.msgFrame.AtBottom) or (f.msgFrame:AtBottom() ~= false)
    local prevScroll = (sameThread and (not wasAtBottom) and f.msgFrame.GetScrollOffset) and (f.msgFrame:GetScrollOffset() or 0) or 0
    local prevMsgCount = self._renderedMsgCount or 0
    if sameThread and (not wasAtBottom) and #msgs > prevMsgCount and prevScroll > 0 then
        prevScroll = prevScroll + (#msgs - prevMsgCount)
    end
    self._renderedThreadKey = self.activeKey
    self._renderedMsgCount = #msgs
    f.msgFrame:Clear()

    local unreadTargetEntry = t.lastReadBannerEntry or t.firstUnreadEntry
    local unreadTargetTs = t.lastReadBannerTs or t.firstUnreadTs
    local bannerShown = false
    for i = startIdx, #msgs do
        local m = msgs[i]
        if type(m) == "table" and m.text then
            if not bannerShown and m.incoming and ((unreadTargetEntry and m == unreadTargetEntry) or (not unreadTargetEntry and unreadTargetTs and m.ts and m.ts >= unreadTargetTs)) then
                bannerShown = true
                f.msgFrame:AddMessage("|cffffd24d—— " .. L["New Messages"] .. " ——|r")
            end
            local tsStr = m.ts and date("%H:%M", m.ts) or ""
            local tsPart = (tsStr ~= "")
                and (m.isStatusNotice and ("|cff6e7681[" .. tsStr .. "]|r ") or ("|Haddon:SCentral:msgact:" .. tostring(i) .. "|h|cff6e7681[" .. tsStr .. "]|r|h "))
                or ""
            local senderHex = (m.classFile and ns.Compat and ns.Compat.ClassHex and ns.Compat.ClassHex(m.classFile)) or "|cffffd24d"
            local senderLbl
            if m.incoming and not m.isStatusNotice then
                local mLvl = (tonumber(m.senderLevel) and tonumber(m.senderLevel) > 0 and math.floor(tonumber(m.senderLevel)))
                    or (ns.Chat and ns.Chat.ResolvePlayerLevel and ns.Chat:ResolvePlayerLevel(nil, m.senderCharName or m.sender, m.senderGuid, isPlayerThread and t.bnetAccountID or nil))
                    or (isPlayerThread and level > 0 and level)
                    or 0
                if mLvl > 0 then
                    m.senderLevel = mLvl
                end
                local lvlTag = (mLvl > 0) and (" |cff9da7b5[" .. L["Lv."] .. tostring(mLvl) .. "]|r") or ""
                local cleanWho = tostring(m.senderCharName or m.sender or "?"):gsub("^<[^>]+>%s*", ""):gsub("[|\r\n]", "")
                local coloredSender = senderHex .. tostring(m.sender or "?") .. "|r"
                local clickableSender = (cleanWho ~= "" and cleanWho ~= "?" and not cleanWho:find("#", 1, true))
                    and ("|Haddon:SCentral:w:" .. cleanWho .. "|h" .. coloredSender .. "|h")
                    or coloredSender
                senderLbl = clickableSender .. lvlTag
            elseif m.incoming then
                senderLbl = senderHex .. tostring(m.sender or "?") .. "|r"
            else
                senderLbl = "|cff8cc2ff" .. L["You"] .. "|r"
            end
            local bodyTxt = tostring(m.text)
            if ns.Chat and ns.Chat.FormatRaidTargetTokens then
                bodyTxt = ns.Chat:FormatRaidTargetTokens(bodyTxt)
            end
            if (not ns.db or not ns.db.settings or ns.db.settings.chatClickableUrls ~= false) and ns.Chat and ns.Chat.LinkifyUrls then
                bodyTxt = ns.Chat:LinkifyUrls(bodyTxt)
            end
            f.msgFrame:AddMessage(tsPart .. senderLbl .. ": " .. bodyTxt)
        end
    end
    if sameThread and (not wasAtBottom) and prevScroll > 0 and f.msgFrame.SetScrollOffset then
        f.msgFrame:SetScrollOffset(prevScroll)
    else
        f.msgFrame:ScrollToBottom()
    end
    if f.btnScrollBottom then
        local atBotNow = (not f.msgFrame.AtBottom) or (f.msgFrame:AtBottom() ~= false)
        f.btnScrollBottom:SetShown(not atBotNow)
    end
end

function QuickReply:OpenThread(threadKey, focusInput)
    if not threadKey or not ns.Chat or not ns.Chat.threads or not ns.Chat.threads[threadKey] then
        return false
    end
    local f = self:EnsureFrame()
    if ns.Theme and ns.Theme.RestoreWindowPosition then
        ns.Theme:RestoreWindowPosition(f, "quickReply", false)
    end
    f:Show()
    f:Raise()
    return self:SelectThread(threadKey, focusInput ~= false)
end

function QuickReply:OpenLatest()
    if not ns.Chat or not ns.Chat.GetQuickReplyThreads then
        return false
    end
    local pending = ns.Chat:GetQuickReplyThreads()
    local target = pending[1]
    if not target or not target.key then
        return false
    end
    local f = self:EnsureFrame()
    if ns.Theme and ns.Theme.RestoreWindowPosition then
        ns.Theme:RestoreWindowPosition(f, "quickReply", false)
    end
    f:Show()
    f:Raise()
    return self:SelectThread(target.key, true)
end

function QuickReply:OpenPreviewOrLatest()
    if self:OpenLatest() then
        return true
    end
    if not ns.Chat then
        return false
    end
    local targetKey = nil
    if ns.Chat.GetThreadsList then
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
    local f = self:EnsureFrame()
    if ns.Theme and ns.Theme.RestoreWindowPosition then
        ns.Theme:RestoreWindowPosition(f, "quickReply", false)
    end
    f:Show()
    f:Raise()
    return self:SelectThread(targetKey, true)
end

function QuickReply:OnInit()
    local function RefreshIfShown()
        if QuickReply.frame and QuickReply.frame:IsShown() then
            QuickReply:Refresh()
        end
    end
    ns:On("CHAT_UPDATED", RefreshIfShown)
    ns:On("SOCIAL_UPDATED", RefreshIfShown)
    ns:On("NEARBY_UPDATED", RefreshIfShown)
    ns:On("WATCHLIST_UPDATED", RefreshIfShown)
    ns:On("GROUP_UPDATED", RefreshIfShown)
    ns:On("CHAT_THREAD_READ", function(info)
        local k = type(info) == "table" and info.threadKey or info
        if QuickReply.frame and QuickReply.frame:IsShown() and k == QuickReply.activeKey then
            QuickReply:Refresh()
        end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        if QuickReply.frame and QuickReply.frame:IsShown() and QuickReply.frame.inputBox and QuickReply.frame.inputBox:HasFocus() then
            QuickReply:SaveCurrentDraft()
            QuickReply.frame.inputBox:ClearFocus()
        end
    end)
    if ns.Theme and ns.Theme.RegisterListener then
        ns.Theme:RegisterListener(function()
            QuickReply:ApplyTheme()
        end)
    end
end

ns.QuickReply = QuickReply
table.insert(ns.modules, QuickReply)
