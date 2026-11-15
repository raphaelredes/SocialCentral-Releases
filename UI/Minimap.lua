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

    local sndLabel, sr, sg, sb = GetChatSoundLabel()
    tt:AddDoubleLine(L["Chat Sounds"], sndLabel, 0.78, 0.84, 0.92, sr, sg, sb)

    tt:AddLine(" ")

    local watchOn, watchOff, watchUnk = 0, 0, 0
    if ns.Watchlist then
        watchOn, watchOff, watchUnk = ns.Watchlist:GetStats()
        tt:AddDoubleLine(
            L["Watchlist"],
            string.format("%s: %d  |  %s: %d  |  %s: %d", L["Online"], watchOn, L["Offline"], watchOff, L["Unchecked"], watchUnk),
            0.88, 0.92, 0.98, 0.90, 0.92, 0.96
        )
    end

    if ns.Social then
        local guildCount = #ns.Social:GetList("guild")
        local friendCount = #ns.Social:GetList("friend")
        local bnetCount = #ns.Social:GetList("bnet")
        tt:AddDoubleLine(
            L["Social"],
            string.format("%s: %d  |  %s: %d  |  %s: %d", L["Guild"], guildCount, L["Friends"], friendCount, "BNet", bnetCount),
            0.88, 0.92, 0.98, 0.72, 0.85, 0.98
        )
    end

    if ns.Nearby then
        tt:AddDoubleLine(L["Nearby"], tostring(#ns.Nearby:GetList()), 0.88, 0.92, 0.98, 0.35, 0.80, 1.0)
    end

    if ns.Spotter then
        local eCount, aCount, sCount, totalCount = ns.Spotter:GetCounts()
        if totalCount > 0 then
            tt:AddDoubleLine(
                L["Target Radar"],
                string.format("|cfff54747E:%d|r  |cff40d973A:%d|r  |cfffacc3dC:%d|r", eCount, aCount, sCount),
                0.88, 0.92, 0.98, 1, 1, 1
            )
        end
    end

    local grpCount = ns.Group and #ns.Group:GetMembers() or 0
    if grpCount > 0 then
        tt:AddDoubleLine(L["Group"], tostring(grpCount), 0.78, 0.84, 0.92, 0.45, 0.80, 1.0)
    end

    if ns.Watchlist and watchOn > 0 then
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

    local summary = ns.Chat and ns.Chat.GetUnreadSummary and ns.Chat:GetUnreadSummary()
    local unreadDirect = summary and summary.totalDirect or (ns.Chat and ns.Chat:GetTotalUnread() or 0)
    local mirrorUnread = summary and summary.channels or 0

    if unreadDirect > 0 or mirrorUnread > 0 then
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
    tt:AddLine(L["Left-click: open settings\nAlt+Click: toggle Target Radar\nCtrl+Click: open Conversations\nShift+Click: check next /who\nRight-click: quick menu\nDrag: move button"], 0.75, 0.80, 0.88, true)
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
            root:CreateButton(L["Looking for Group (I)"], function()
                OpenViaOfficialOrHub("lfg")
            end)
            root:CreateButton(L["Social & Watchlist (O)"], function()
                OpenViaOfficialOrHub("watchlist")
            end)
            root:CreateButton(L["Clan Hub & Diplomacy (J)"], function()
                OpenViaOfficialOrHub("clan")
            end)
            root:CreateButton(L["My Alts (C)"], function()
                OpenViaOfficialOrHub("alts")
            end)
            root:CreateButton(L["Conversations (Chat)"], function()
                OpenViaOfficialOrHub("chat")
            end)
            root:CreateButton(L["World Buffs (M)"], function()
                OpenViaOfficialOrHub("buffs")
            end)
            root:CreateButton(L["Open Unified Hub"], function()
                if ns.UI and ns.UI.ShowHub then
                    ns.UI:ShowHub()
                elseif ns.UI then
                    ns.UI:Toggle()
                end
            end)
            root:CreateDivider()
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
            root:CreateButton(L["Check Next"], function()
                if ns.Watchlist then ns.Watchlist:CheckNext() end
            end)
            if ns.Chat and ns.Chat.GetTotalUnread and ns.Chat:GetTotalUnread(true) > 0 then
                root:CreateButton(L["Mark All Conversations Read"], function()
                    if ns.Chat and ns.Chat.MarkAllRead then
                        ns.Chat:MarkAllRead()
                    end
                end)
            end
            root:CreateDivider()
            root:CreateCheckbox(L["Mute All Chat Sounds"], function()
                return ns.db and ns.db.settings and ns.db.settings.chatSound == false
            end, function()
                if ns.db and ns.db.settings then
                    ns.db.settings.chatSound = (ns.db.settings.chatSound == false)
                    ns:Emit("CHAT_UPDATED")
                end
            end)
            root:CreateCheckbox(L["Online alerts for Watchlist"], function()
                return ns.db and ns.db.settings and ns.db.settings.alerts and ns.db.settings.alerts.chat
            end, function()
                if ns.db and ns.db.settings and ns.db.settings.alerts then
                    ns.db.settings.alerts.chat = not ns.db.settings.alerts.chat
                end
            end)
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
                if ns.Theme and ns.Theme.ResetAllWindowPositions then ns.Theme:ResetAllWindowPositions() end
            end)
        end)
    elseif ns.Settings then
        ns.Settings:Open()
    end
end

local function UpdateBadge()
    local summary = ns.Chat and ns.Chat.GetUnreadSummary and ns.Chat:GetUnreadSummary()
    local unreadDirect = summary and summary.totalDirect or (ns.Chat and ns.Chat:GetTotalUnread() or 0)

    if button and button.badge then
        button.badge:Hide()
        button.badge:SetText("")
    end

    if button and button.msgBadgeFrame then
        button.msgBadgeFrame:Hide()
    end

    if button and button.overlayRing then
        if unreadDirect > 0 then
            button.overlayRing:SetVertexColor(1.0, 0.85, 0.22)
        elseif ns.Spotter and select(1, ns.Spotter:GetCounts()) > 0 then
            button.overlayRing:SetVertexColor(0.96, 0.28, 0.28)
        else
            button.overlayRing:SetVertexColor(1, 1, 1)
        end
    end

    if ldbObject then
        ldbObject.text = "SocialCentral"
    end
end

local function HandleMinimapClick(anchor, mouseButton)
    if mouseButton == "RightButton" then
        if GameTooltip then GameTooltip:Hide() end
        OpenContextMenu(anchor)
    elseif IsAltKeyDown and IsAltKeyDown() then
        if ns.SpotterHUD and ns.SpotterHUD.Toggle then
            ns.SpotterHUD:Toggle()
        end
    elseif IsControlKeyDown and IsControlKeyDown() then
        OpenViaOfficialOrHub("chat")
    elseif IsShiftKeyDown and IsShiftKeyDown() then
        if ns.Watchlist then
            ns.Watchlist:CheckNext()
        end
    elseif ns.Settings and ns.Settings.Toggle then
        ns.Settings:Toggle()
    elseif ns.Settings and ns.Settings.Open then
        ns.Settings:Open()
    elseif ns.UI then
        ns.UI:Toggle()
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

for _, ev in ipairs({ "WATCHLIST_UPDATED", "SOCIAL_UPDATED", "NEARBY_UPDATED", "GROUP_UPDATED", "CHAT_UPDATED", "CLAN_UPDATED", "SPOTTER_UPDATED", "SETTINGS_CHANGED" }) do
    ns:On(ev, UpdateBadge)
end
