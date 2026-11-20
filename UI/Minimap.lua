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
local BADGE_CATEGORY_ORDER = { "whisper", "group", "guild", "bnet", "room" }
local BadgeCluster = {
    testCounts = nil,
    previewCounts = {},
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

        for _, cat in ipairs(BADGE_CATEGORY_ORDER) do
            local pv = self.previewCounts[cat] or 0
            if pv > 0 then
                if cat == "group" or cat == "guild" or counts[cat] == 0 then
                    counts[cat] = counts[cat] + pv
                end
            end
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
    local hadAny = next(self.previewCounts) ~= nil or self.testCounts ~= nil
    wipe(self.previewCounts)
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
        UpdateBadge(false)
    end)

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
        if p >= 1 then
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
        BadgeCluster.previewCounts[cat] = (BadgeCluster.previewCounts[cat] or 0) + 1
        UpdateBadge(true)
    elseif cat == "group" or cat == "guild" then
        local s = ns.db and ns.db.settings
        local mirroredTracked = s and s.chatMirrorChannels == true and s.chatChannelUnread == true
        if not mirroredTracked then
            BadgeCluster.previewCounts[cat] = (BadgeCluster.previewCounts[cat] or 0) + 1
            UpdateBadge(true)
        end
    end
end

function MinimapBtn:ClearPreviewCounts()
    if BadgeCluster:ClearSessionPreviewCounts() then
        BadgeCluster.testCounts = nil
        UpdateBadge(false)
    end
end

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

local function MpShouldSilenceForContext()
    local s = ns.db and ns.db.settings
    if not s then return true end
    if Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("chat") then
        return true
    end
    if Compat and Compat.IsFocusSilenced and Compat.IsFocusSilenced() then
        return true
    end
    if s.msgPreviewSilenceCombat == true and MpIsInCombat() then
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
        if customX >= (uiW * 0.5) then
            side = "LEFT"
            restEdgeX = customX + (MP_MAX_W * 0.5)
        else
            side = "RIGHT"
            restEdgeX = customX - (MP_MAX_W * 0.5)
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
    if item.threadKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[item.threadKey] and ns.NavigateToModule then
        ns:NavigateToModule("chat", { threadKey = item.threadKey })
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
    local computedW = MpClamp(math.ceil(48 + idealTextW + 26), MP_MIN_W, MP_MAX_W)

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
    contentClip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 6)
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
    closeBtn:SetHitRectInsets(-4, -4, -4, -4)
    closeBtn:SetScript("OnClick", function()
        if f._slot then
            MpBeginCollapseSlot(f._slot)
        end
    end)
    f.closeBtn = closeBtn

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
        local curCenterX = (side == "LEFT") and (restEdgeX - (MP_MAX_W * 0.5)) or (restEdgeX + (MP_MAX_W * 0.5))
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
                            ns.Chat:MarkThreadRead(cur.threadKey)
                            MpBeginCollapseSlot(slot)
                        end)
                    end
                    root:CreateDivider()
                    root:CreateButton(MpCategoryDisableLabel(cur.category), function()
                        slot.menuPauseUntil = 0
                        MpDisableCategory(cur.category)
                        MpBeginCollapseSlot(slot)
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
            local hovered = f and (f:IsMouseOver() or (f.closeBtn and f.closeBtn:IsMouseOver()))
            local totalDur = (slot.item and slot.item.duration) or MpGetHoldDuration()

            if not setupOpen and not moverOpen and not MsgPreview.draggingStack and not hovered and not menuPaused then
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
                MinimapBtn:PulseArrival(rgb[1], rgb[2], rgb[3])
                MinimapBtn:NotePreviewFolded(doneSlot.item)
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
    copy.coalescedCount = 1

    if not forceShow then
        local cKey = MpCoalesceKey(copy)
        for _, slot in ipairs(self.activeSlots) do
            if slot.phase ~= "COLLAPSE" and MpCoalesceKey(slot.item) == cKey then
                slot.item.text = copy.text
                slot.item.sender = copy.sender or slot.item.sender
                slot.item.senderClass = copy.senderClass or slot.item.senderClass
                slot.item.coalescedCount = (slot.item.coalescedCount or 1) + 1
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
                qItem.coalescedCount = (qItem.coalescedCount or 1) + 1
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
            else
                C_Timer.After(delaySec, function()
                    if MsgPreview._queueTestGen == gen then
                        MsgPreview:PushItem(MpBuildSampleItem(kindArg, idxArg), true)
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
end

function MsgPreview:OnIncomingMessage(payload)
    if type(payload) ~= "table" then return end
    local s = ns.db and ns.db.settings
    if not s then return end
    if Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("chat") then
        return
    end
    if s.doNotDisturb == true then
        return
    end

    local nowMono = GetTime and GetTime() or 0
    if (nowMono - (self.loginAt or 0)) < MP_LOGIN_GRACE then
        return
    end

    local promptDone = (ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("msgPreviewPromptAnswered")) or (s.msgPreviewPromptAnswered == true)
    if not promptDone then
        if self.sessionPromptDismissed then
            return
        end
        if self.setupModal and self.setupModal:IsShown() then
            return
        end
        if MpIsInCombat() then
            self.pendingPromptItem = payload
            return
        end
        self:ShowFirstTimePrompt(payload, false)
        return
    end

    if s.msgPreviewEnabled == false then
        return
    end
    if MpShouldSilenceForContext() then
        return
    end
    if not MpIsCategoryEnabled(payload.category) then
        return
    end

    self:PushItem(payload, false)
end

function MsgPreview:Init()
    if self.initialized then return end
    self.initialized = true
    self.loginAt = (GetTime and GetTime()) or 0

    ns:On("INCOMING_MESSAGE_PREVIEW", function(payload)
        MsgPreview:OnIncomingMessage(payload)
    end)

    ns:On("CHAT_UPDATED", function()
        if not (ns.UI and ns.UI.IsChatThreadVisible) then return end
        for _, slot in ipairs(MsgPreview.activeSlots) do
            if slot.item and slot.item.threadKey and ns.UI:IsChatThreadVisible(slot.item.threadKey) then
                MpBeginCollapseSlot(slot)
            end
        end
    end)

    local function RevalidateVisibility()
        local s = ns.db and ns.db.settings
        if not s then return end
        local setupOpen = MsgPreview.setupModal and MsgPreview.setupModal:IsShown()
        if setupOpen then return end
        if s.msgPreviewEnabled == false or MpShouldSilenceForContext() then
            if #MsgPreview.activeSlots > 0 then
                MpBeginCollapseAll(true)
            else
                wipe(MsgPreview.queue)
            end
        else
            -- If user increased maxVisible live while items are queued, promote immediately!
            MpPromoteFromQueue()
        end
    end

    ns:On("SETTINGS_UPDATED", RevalidateVisibility)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", RevalidateVisibility)
    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", RevalidateVisibility)
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        local s = ns.db and ns.db.settings
        if s and s.msgPreviewSilenceCombat == true then
            RevalidateVisibility()
        end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if MsgPreview.pendingPromptItem then
            local item = MsgPreview.pendingPromptItem
            MsgPreview.pendingPromptItem = nil
            local s = ns.db and ns.db.settings
            local promptDone = (ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("msgPreviewPromptAnswered")) or (s and s.msgPreviewPromptAnswered == true)
            if s and not promptDone and not MsgPreview.sessionPromptDismissed and s.doNotDisturb ~= true then
                MsgPreview:ShowFirstTimePrompt(item, false)
            end
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
