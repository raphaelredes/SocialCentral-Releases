local _, ns = ...

local L = ns.L
local Compat = ns.Compat

local MinimapBtn = {}
ns.Minimap = MinimapBtn

local RING_TEX = 136430
local BG_TEX = 136467
local HIGHLIGHT_TEX = 136477
local ICON_TEX = "Interface\\AddOns\\SocialCentral\\Media\\icon"
local RADIUS_OFFSET = 8

local button
local ldbObject

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
        tt:AddDoubleLine(L["Focus Mode"], L["Do Not Disturb (Active)"], 0.78, 0.84, 0.92, 1.0, 0.65, 0.24)
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
                local star = entry.favorite and "* " or ""
                local area = (entry.area and entry.area ~= "") and entry.area or L["Online"]
                tt:AddDoubleLine(star .. (entry.displayName or ""), area, r, g, b, 0.70, 0.75, 0.82)
                shown = shown + 1
            end
        end
    end

    local summary = chatOnMod and ns.Chat and ns.Chat.GetUnreadSummary and ns.Chat:GetUnreadSummary()
    local unreadDirect = summary and summary.totalDirect or (chatOnMod and ns.Chat and ns.Chat:GetTotalUnread() or 0)
    local mirrorUnread = summary and summary.channels or 0

    if chatOnMod and (unreadDirect > 0 or mirrorUnread > 0) then
        tt:AddLine(" ")
        if unreadDirect > 0 then
            local msgCount = (summary and (summary.direct + summary.rooms)) or unreadDirect
            local invCount = summary and summary.invites or 0
            local rightSummary = invCount > 0
                and string.format(L["%d msg | %d room invite(s)"], msgCount, invCount)
                or tostring(unreadDirect)
            tt:AddDoubleLine(L["Unread Messages (Direct)"], rightSummary, 0.98, 0.86, 0.32, 0.35, 0.95, 0.55)
            if summary and summary.senders then
                local shownSenders = 0
                for _, item in ipairs(summary.senders) do
                    if shownSenders >= 4 then break end
                    tt:AddDoubleLine("  " .. tostring(item.title or ""), tostring(item.unread or 0), 0.82, 0.88, 0.96, 0.35, 0.95, 0.55)
                    shownSenders = shownSenders + 1
                end
            end
        end
        if mirrorUnread > 0 then
            tt:AddDoubleLine(L["Guild/Group Mirror Unread"], tostring(mirrorUnread), 0.62, 0.66, 0.74, 0.62, 0.66, 0.74)
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
            if not ns.Compat or not ns.Compat.IsWindowIntegrationEnabled or ns.Compat.IsWindowIntegrationEnabled("M") then
                root:CreateButton(L["World Buffs (M)"], function()
                    OpenViaOfficialOrHub("buffs")
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
            root:CreateCheckbox(L["Do Not Disturb"], function()
                return ns.db and ns.db.settings and ns.db.settings.doNotDisturb == true
            end, function()
                if ns.db and ns.db.settings then
                    ns.db.settings.doNotDisturb = not (ns.db.settings.doNotDisturb == true)
                    ns:Emit("SETTINGS_UPDATED")
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                end
            end)
            if chatModOn then
                root:CreateCheckbox(L["Mute All Chat Sounds"], function()
                    return ns.db and ns.db.settings and ns.db.settings.chatSound == false
                end, function()
                    if ns.db and ns.db.settings then
                        ns.db.settings.chatSound = (ns.db.settings.chatSound == false)
                        ns:Emit("CHAT_UPDATED")
                    end
                end)
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

local function UpdateBadge()
    local unreadDirect = 0
    local chatModOn = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("chat")
    if chatModOn and ns.Chat then
        if ns.Chat.GetUnreadDirectCount then
            unreadDirect = ns.Chat:GetUnreadDirectCount() or 0
        elseif ns.Chat.GetTotalUnread then
            unreadDirect = ns.Chat:GetTotalUnread(false) or 0
        end
    end

    local showNumBadge = not (ns.db and ns.db.settings and ns.db.settings.addonMsgMinimapBadge == false)
    if button and button.msgBadgeFrame and button.badge then
        if showNumBadge and unreadDirect > 0 then
            local label = unreadDirect > 9 and "9+" or tostring(unreadDirect)
            button.badge:SetText(label)
            button.msgBadgeFrame:SetWidth(unreadDirect > 9 and 20 or 15)
            button.msgBadgeFrame:Show()
            button.badge:Show()
        else
            button.badge:Hide()
            button.badge:SetText("")
            button.msgBadgeFrame:Hide()
        end
    end

    if button and button.overlayRing then
        local spotterEnabled = not (ns.db and ns.db.settings and ns.db.settings.spotterEnabled == false)
        if unreadDirect > 0 then
            button.overlayRing:SetVertexColor(1.0, 0.85, 0.22)
        elseif spotterEnabled and ns.Spotter and select(1, ns.Spotter:GetCounts()) > 0 then
            button.overlayRing:SetVertexColor(0.96, 0.28, 0.28)
        else
            button.overlayRing:SetVertexColor(1, 1, 1)
        end
    end

    if ldbObject then
        ldbObject.text = unreadDirect > 0 and ("SocialCentral (" .. tostring(unreadDirect) .. ")") or "SocialCentral"
    end
end

local leftChooserFrame

local function OpenMainWindowFromMinimap()
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
    local clickMode = (ns.db and ns.db.settings and ns.db.settings.minimapLeftClickAction) or "smart"
    if clickMode == "menu" then
        OpenLeftClickMenu(anchor or button)
        return
    end
    local chatModOn = (not ns.Compat or not ns.Compat.IsModuleEnabled) or ns.Compat.IsModuleEnabled("chat")
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

    local badgeFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
    badgeFrame:SetSize(15, 14)
    badgeFrame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -2)
    badgeFrame:SetFrameLevel((button:GetFrameLevel() or 8) + 6)
    if badgeFrame.SetBackdrop then
        badgeFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        badgeFrame:SetBackdropColor(0.84, 0.18, 0.22, 1.0)
        badgeFrame:SetBackdropBorderColor(0.08, 0.10, 0.14, 1.0)
    end
    badgeFrame:Hide()

    local badgeText = badgeFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    badgeText:SetPoint("CENTER", 0, 0)
    badgeText:SetTextColor(1, 1, 1)
    button.msgBadgeFrame = badgeFrame
    button.badge = badgeText

    button:SetScript("OnMouseDown", function() SetIconPressed(true) end)
    button:SetScript("OnMouseUp", function() SetIconPressed(false) end)

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
        self:SetScript("OnUpdate", function()
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

    button:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        SetIconPressed(false)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        PopulateTooltip(GameTooltip)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
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

for _, ev in ipairs({ "CHAT_UPDATED", "SPOTTER_UPDATED", "SETTINGS_CHANGED", "SETTINGS_UPDATED", "ADDON_MESSAGE_NOTIFY" }) do
    ns:On(ev, UpdateBadge)
end
