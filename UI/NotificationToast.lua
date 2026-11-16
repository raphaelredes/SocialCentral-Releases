local _, ns = ...

local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })
local Compat = ns.Compat
local Theme = ns.Theme

-- Compact, 100%-opaque, movable floating notification stack for incoming SCentral1 addon messages.
-- Security & performance guarantees:
--   - Uses standard non-secure BackdropTemplate frames (zero UI taint; clickable in combat, navigation defers safely).
--   - Attaches single shared OnUpdate timer only while shown (0ms idle CPU when hidden).
--   - Zero global leaks; all positioning persists via Theme:MakeMovable on anchorFrame.
--   - Multi-toast stacking: notifications stack vertically with longer duration items on top and shorter items below.
local Toast = {
    anchorFrame = nil,
    framePool = {},
    activeItems = {},
    queue = {},
    hooksInitialized = false,
}

local TOAST_WIDTH = 396
local TOAST_H_DEFAULT = 64
local TOAST_H_INVITE = 94
local MAX_VISIBLE_TOASTS = 4
local MAX_QUEUE = 12

local AUTO_DISMISS_INVITE_SEC = 20.0
local AUTO_DISMISS_BUFF_SEC = 14.0
local AUTO_DISMISS_DEFAULT_SEC = 10.0
local AUTO_DISMISS_FRIEND_SEC = 8.0

local ICON_DEFAULT = "Interface\\AddOns\\SocialCentral\\Media\\icon"
local ICON_MAIL    = "Interface\\AddOns\\SocialCentral\\Media\\toast-mail"
local ICON_PARTY   = "Interface\\AddOns\\SocialCentral\\Media\\toast-party"
local ICON_ONLINE  = "Interface\\AddOns\\SocialCentral\\Media\\toast-online"
local ICON_GLOW    = "Interface\\AddOns\\SocialCentral\\Media\\toast-glow"
local WHITE8X8     = "Interface\\Buttons\\WHITE8X8"

local toastGradColorA = CreateColor and CreateColor(1, 1, 1, 1) or nil
local toastGradColorB = CreateColor and CreateColor(1, 1, 1, 1) or nil

local function ApplyTexGradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    if not tex then return end
    if tex.SetGradient and toastGradColorA and toastGradColorB then
        tex:SetTexture(WHITE8X8)
        tex:SetVertexColor(1, 1, 1, 1)
        toastGradColorA:SetRGBA(r1, g1, b1, a1)
        toastGradColorB:SetRGBA(r2, g2, b2, a2)
        pcall(tex.SetGradient, tex, orient, toastGradColorA, toastGradColorB)
    else
        tex:SetColorTexture((r1 + r2) * 0.5, (g1 + g2) * 0.5, (b1 + b2) * 0.5, (a1 + a2) * 0.5)
    end
end

local KIND_RGB = {
    DIRECT           = { 0.25, 0.78, 0.52 },
    ROOM             = { 0.35, 0.70, 1.00 },
    RMI              = { 0.32, 0.72, 1.00 },
    ALLIANCE         = { 0.80, 0.56, 1.00 },
    CLAN_LFG         = { 0.96, 0.78, 0.24 },
    CLAN_EVENT       = { 0.96, 0.78, 0.24 },
    CLAN_SIGNUP      = { 0.35, 0.85, 0.55 },
    SCOUT            = { 0.96, 0.28, 0.28 },
    WORLDBUFF        = { 0.98, 0.62, 0.22 },
    FRIEND_ONLINE    = { 0.28, 0.92, 0.50 },
    WATCHLIST_ONLINE = { 0.36, 0.94, 0.48 },
}

local function ResolveIconForKind(kind)
    if kind == "FRIEND_ONLINE" or kind == "WATCHLIST_ONLINE" then
        return ICON_ONLINE
    elseif kind == "RMI" or kind == "CLAN_LFG" then
        return ICON_PARTY
    elseif kind == "WORLDBUFF" or kind == "SCOUT" then
        return ICON_DEFAULT
    end
    return ICON_MAIL
end

local function FormatCooldownKey(item)
    if item.threadKey and item.threadKey ~= "" then
        return item.threadKey
    end
    return tostring(item.kind or "MSG") .. ":" .. tostring(item.sender or "?")
end

local function ApplyToastThemeToFrame(f)
    if not f then return end
    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(f, "window")
    end
    if f._kindRgb and f.SetBackdropBorderColor then
        local r, g, b = f._kindRgb[1], f._kindRgb[2], f._kindRgb[3]
        -- Blend category accent with warm metallic gold for an epic RPG card border
        f:SetBackdropBorderColor(r * 0.60 + 0.36, g * 0.60 + 0.28, b * 0.60 + 0.12, 1.0)
    end
    local p = Theme and Theme.GetPalette and Theme:GetPalette()
    if p then
        if f.bodyLbl then
            f.bodyLbl:SetTextColor(p.text[1], p.text[2], p.text[3])
        end
        if f.queueLbl then
            f.queueLbl:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
        end
        if f.acceptBtn and Theme.StyleButton then
            Theme:StyleButton(f.acceptBtn, "primary")
        end
        if f.declineBtn and Theme.StyleButton then
            Theme:StyleButton(f.declineBtn, "default")
        end
    end
end

local function NavigateForItem(item)
    if not item then return end
    local k = item.kind
    if k == "SCOUT" then
        if ns.SpotterHUD and ns.SpotterHUD.Show then
            ns.SpotterHUD:Show(true)
        elseif ns.NavigateToModule then
            ns:NavigateToModule("clan")
        end
    elseif k == "WORLDBUFF" then
        if ns.NavigateToModule then
            ns:NavigateToModule("buffs")
        end
    elseif k == "FRIEND_ONLINE" then
        if ns.NavigateToModule then
            ns:NavigateToModule("social", { socialSearch = item.searchHint or "" })
        end
    elseif k == "WATCHLIST_ONLINE" then
        if ns.NavigateToModule then
            ns:NavigateToModule("watchlist", { watchlistSearch = item.searchHint or "" })
        end
    elseif k == "CLAN_EVENT" or k == "CLAN_SIGNUP" then
        if ns.NavigateToModule then
            ns:NavigateToModule("clan", { clanRightView = "events", eventId = item.eventId })
        end
    elseif k == "CLAN_LFG" then
        if ns.NavigateToModule then
            ns:NavigateToModule("lfg", { clanRightView = "lfg" })
        end
    elseif k == "RMI" then
        if ns.NavigateToModule then
            ns:NavigateToModule("chat", { pendingRoomId = item.roomId })
        end
    else
        if ns.NavigateToModule then
            ns:NavigateToModule("chat", { threadKey = item.threadKey })
        end
    end
end

local function EnsureAnchorFrame()
    if Toast.anchorFrame then
        return Toast.anchorFrame
    end

    local anchor = CreateFrame("Frame", "SocialCentralNotificationToastAnchor", UIParent)
    anchor:SetSize(TOAST_WIDTH, 1)
    anchor:SetPoint("TOP", UIParent, "TOP", 0, -110)
    anchor:SetFrameStrata("DIALOG")
    anchor:SetFrameLevel(179)
    anchor:SetClampedToScreen(true)

    if Theme and Theme.MakeMovable then
        Theme:MakeMovable(anchor, {
            key = "notification_toast",
            anchor = "TOP",
            combatLock = false,
            onReset = function(win)
                win:ClearAllPoints()
                win:SetPoint("TOP", UIParent, "TOP", 0, -110)
                if Toast.LayoutStack then
                    Toast:LayoutStack()
                end
            end,
        })
    end

    Toast.anchorFrame = anchor
    return anchor
end

function Toast:EnsureFrame(index)
    if self.framePool[index] then
        return self.framePool[index]
    end

    EnsureAnchorFrame()

    local f = CreateFrame("Button", "SocialCentralNotificationToast" .. tostring(index), UIParent, "BackdropTemplate")
    f:SetSize(TOAST_WIDTH, TOAST_H_DEFAULT)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(180 + index * 2)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetClampedToScreen(true)
    f.toastIndex = index
    f:Hide()

    -- Textured Blizzard carved slate backdrop layered over 100%-opaque base
    if Theme and Theme.HasAtlas and Theme:HasAtlas("groupfinder-background") then
        local stoneBg = f:CreateTexture(nil, "BACKGROUND", nil, -4)
        stoneBg:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -5)
        stoneBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 5)
        stoneBg:SetAtlas("groupfinder-background", false)
        stoneBg:SetVertexColor(0.32, 0.34, 0.40, 0.45)
        f.stoneBg = stoneBg
    end

    -- Soft horizontal category ambient wash radiating from left medallion (zero sharp lines)
    local bgAmbient = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    bgAmbient:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -5)
    bgAmbient:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 5)
    f.bgAmbient = bgAmbient

    -- Subtle metallic top bevel highlight
    local topBevel = f:CreateTexture(nil, "BORDER", nil, 1)
    topBevel:SetHeight(1)
    topBevel:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -5)
    topBevel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -5)
    topBevel:SetColorTexture(1, 0.90, 0.68, 0.14)
    f.topBevel = topBevel

    local hoverHighlight = f:CreateTexture(nil, "HIGHLIGHT")
    hoverHighlight:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -5)
    hoverHighlight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 5)
    hoverHighlight:SetColorTexture(1, 0.92, 0.72, 0.05)

    -- Left Medallion Slot (x = 12..58, safely separated from centered x = 64 text margin)
    local iconBadge = CreateFrame("Frame", nil, f)
    iconBadge:SetSize(46, 46)
    iconBadge:SetPoint("LEFT", f, "LEFT", 12, 1)
    iconBadge:EnableMouse(false)
    f.iconBadge = iconBadge

    -- Silky Gaussian radial bloom behind medallion (no hard clipped circle edge)
    local iconHalo = iconBadge:CreateTexture(nil, "ARTWORK", nil, 0)
    iconHalo:SetSize(64, 64)
    iconHalo:SetPoint("CENTER")
    iconHalo:SetTexture(ICON_GLOW)
    iconHalo:SetVertexColor(0.35, 0.75, 1.0, 0.55)
    f.iconHalo = iconHalo

    local iconTex = iconBadge:CreateTexture(nil, "OVERLAY", nil, 2)
    iconTex:SetSize(42, 42)
    iconTex:SetPoint("CENTER")
    iconTex:SetTexture(ICON_DEFAULT)
    f.iconTex = iconTex

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    closeBtn:SetFrameLevel(f:GetFrameLevel() + 10)
    closeBtn:SetScript("OnClick", function()
        if f.itemData then
            Toast:DismissItem(f.itemData)
        end
    end)
    f.closeBtn = closeBtn

    local queueLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    queueLbl:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
    queueLbl:SetJustifyH("RIGHT")
    queueLbl:Hide()
    f.queueLbl = queueLbl

    -- Symmetric centered content region (x = 64..width-64): guarantees geometric centering & zero overlap
    local titleLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 64, -10)
    titleLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -64, -10)
    titleLbl:SetJustifyH("CENTER")
    titleLbl:SetWordWrap(false)
    f.titleLbl = titleLbl

    -- Tapered centered flourish line strictly beneath the title
    local titleFlourishL = f:CreateTexture(nil, "BORDER", nil, 2)
    titleFlourishL:SetSize(96, 1)
    titleFlourishL:SetPoint("TOPRIGHT", f, "TOP", 0, -27)
    f.titleFlourishL = titleFlourishL

    local titleFlourishR = f:CreateTexture(nil, "BORDER", nil, 2)
    titleFlourishR:SetSize(96, 1)
    titleFlourishR:SetPoint("TOPLEFT", f, "TOP", 0, -27)
    f.titleFlourishR = titleFlourishR

    local bodyLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bodyLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 64, -32)
    bodyLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -64, -32)
    bodyLbl:SetJustifyH("CENTER")
    bodyLbl:SetWordWrap(true)
    if bodyLbl.SetSpacing then
        bodyLbl:SetSpacing(2)
    end
    if bodyLbl.SetMaxLines then
        bodyLbl:SetMaxLines(3)
    end
    f.bodyLbl = bodyLbl

    -- Action row with centered Accept and Decline buttons aligned to text column
    local actionRow = CreateFrame("Frame", nil, f)
    actionRow:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 64, 12)
    actionRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -64, 12)
    actionRow:SetHeight(22)
    actionRow:Hide()
    f.actionRow = actionRow

    local acceptBtn = Theme:CreateButton(actionRow, 96, 20, L["Accept"], "primary")
    Theme:AutoFitButton(acceptBtn, 84, 14, 114)
    acceptBtn:SetPoint("CENTER", actionRow, "CENTER", -56, 0)
    acceptBtn:SetScript("OnClick", function()
        local item = f.itemData
        if not item then return end
        local rId = item.roomId
        if rId and rId ~= "test-room-preview" and ns.Chat and ns.Chat.AcceptRoomInvite then
            ns.Chat:AcceptRoomInvite(rId)
        end
        Toast:DismissItem(item)
        if rId and rId ~= "test-room-preview" and ns.NavigateToModule then
            ns:NavigateToModule("chat", { threadKey = "room:" .. rId })
        end
    end)
    f.acceptBtn = acceptBtn

    local declineBtn = Theme:CreateButton(actionRow, 96, 20, L["Decline"], "default")
    Theme:AutoFitButton(declineBtn, 84, 14, 114)
    declineBtn:SetPoint("CENTER", actionRow, "CENTER", 56, 0)
    declineBtn:SetScript("OnClick", function()
        local item = f.itemData
        if item and item.roomId and item.roomId ~= "test-room-preview" and ns.Chat and ns.Chat.DeclineRoomInvite then
            ns.Chat:DeclineRoomInvite(item.roomId)
        end
        Toast:DismissItem(item)
    end)
    f.declineBtn = declineBtn

    -- Sleek recessed 2px timer bar cleanly inset inside bottom frame
    local progressTrack = f:CreateTexture(nil, "BORDER", nil, 2)
    progressTrack:SetHeight(2)
    progressTrack:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 6)
    progressTrack:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 6)
    progressTrack:SetColorTexture(0.04, 0.05, 0.07, 0.90)
    f.progressTrack = progressTrack

    local progressFill = f:CreateTexture(nil, "OVERLAY", nil, 1)
    progressFill:SetHeight(2)
    progressFill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 6)
    progressFill:SetWidth(TOAST_WIDTH - 24)
    f.progressFill = progressFill

    f:SetScript("OnClick", function(self, mouseButton)
        local curItem = self.itemData
        if not curItem then return end
        if mouseButton == "RightButton" then
            Toast:DismissItem(curItem)
            return
        end
        Toast:DismissItem(curItem)
        NavigateForItem(curItem)
    end)

    f:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("|cff58a6ffSocialCentral|r")
            GameTooltip:AddLine(L["Click to open conversation | Right-click to dismiss | Drag to move"], 0.85, 0.88, 0.92, true)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    f:HookScript("OnHide", function(self)
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)

    f:HookScript("OnDragStart", function(self)
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)

    -- Attach drag handle so dragging ANY toast moves the whole stack together
    if Theme and Theme.AttachDragHandle then
        Theme:AttachDragHandle(f, self.anchorFrame)
    end

    ApplyToastThemeToFrame(f)
    self.framePool[index] = f

    if index == 1 then
        self.frame = f
    end

    return f
end

local function RenderItemOnFrame(f, item, remainingQueueCount)
    if not f or not item then return end
    f.itemData = item

    local isInvite = (item.kind == "RMI" and item.roomId and item.roomId ~= "")
    f:SetWidth(TOAST_WIDTH)

    local gradKey = item.kind or "DIRECT"
    local rgb = KIND_RGB[gradKey] or KIND_RGB.DIRECT
    f._kindRgb = rgb

    if f._lastGradKind ~= gradKey then
        f._lastGradKind = gradKey
        if f.bgAmbient then
            ApplyTexGradient(f.bgAmbient, "HORIZONTAL", rgb[1] * 0.24, rgb[2] * 0.24, rgb[3] * 0.24, 0.45, 0.0, 0.0, 0.0, 0.0)
        end
        if f.titleFlourishL then
            ApplyTexGradient(f.titleFlourishL, "HORIZONTAL", rgb[1], rgb[2], rgb[3], 0.0, rgb[1] * 0.65 + 0.32, rgb[2] * 0.65 + 0.28, rgb[3] * 0.65 + 0.14, 0.65)
        end
        if f.titleFlourishR then
            ApplyTexGradient(f.titleFlourishR, "HORIZONTAL", rgb[1] * 0.65 + 0.32, rgb[2] * 0.65 + 0.28, rgb[3] * 0.65 + 0.14, 0.65, rgb[1], rgb[2], rgb[3], 0.0)
        end
        if f.iconTex then
            f.iconTex:SetTexture(ResolveIconForKind(item.kind))
        end
        if f.iconHalo then
            local haloAlpha = (item.kind == "FRIEND_ONLINE" or item.kind == "WATCHLIST_ONLINE") and 0.68 or 0.42
            f.iconHalo:SetVertexColor(rgb[1], rgb[2], rgb[3], haloAlpha)
        end
        if f.progressFill then
            ApplyTexGradient(f.progressFill, "HORIZONTAL", rgb[1] * 0.55, rgb[2] * 0.55, rgb[3] * 0.55, 0.85, math.min(1, rgb[1] + 0.30), math.min(1, rgb[2] + 0.30), math.min(1, rgb[3] + 0.30), 1.0)
        end
    end
    if f.progressFill then
        local remainingFrac = math.max(0, 1 - ((item.elapsed or 0) / (item.totalDuration or AUTO_DISMISS_DEFAULT_SEC)))
        local newW = math.max(1, (TOAST_WIDTH - 24) * remainingFrac)
        if f._lastProgressW ~= newW then
            f._lastProgressW = newW
            f.progressFill:SetWidth(newW)
        end
    end

    local sourceTag = item.sourceTag or "SocialCentral"
    local hex = (item.senderClass and Compat and Compat.ClassHex) and Compat.ClassHex(item.senderClass) or "|cffffffff"
    local senderText = hex .. tostring(item.sender or "?") .. "|r"
    local mult = (item.coalescedCount and item.coalescedCount > 1) and (" |cff9da7b5(x" .. tostring(item.coalescedCount) .. ")|r") or ""
    f.titleLbl:SetText(string.format("|cff%02x%02x%02x%s|r  ·  %s%s", math.floor(rgb[1] * 255), math.floor(rgb[2] * 255), math.floor(rgb[3] * 255), sourceTag, senderText, mult))

    local bodyText = tostring(item.text or "")
    if isInvite then
        bodyText = string.format(L["Invite to room: %s"], bodyText)
    end
    f.bodyLbl:SetText(bodyText)

    local measuredBodyH = (f.bodyLbl.GetStringHeight and f.bodyLbl:GetStringHeight()) or 14
    local minH = isInvite and TOAST_H_INVITE or TOAST_H_DEFAULT
    local bottomReserve = isInvite and 42 or 15
    local finalH = math.max(minH, math.ceil(32 + measuredBodyH + bottomReserve))
    f:SetSize(TOAST_WIDTH, finalH)

    if remainingQueueCount and remainingQueueCount > 0 then
        f.queueLbl:SetText("+" .. tostring(remainingQueueCount))
        f.queueLbl:Show()
    else
        f.queueLbl:SetText("")
        f.queueLbl:Hide()
    end

    if isInvite then
        f.actionRow:Show()
    else
        f.actionRow:Hide()
    end

    ApplyToastThemeToFrame(f)
end

function Toast:SortActiveItems()
    -- Sort active items: longer total duration on top, shorter below.
    table.sort(self.activeItems, function(a, b)
        local durA = a.totalDuration or AUTO_DISMISS_DEFAULT_SEC
        local durB = b.totalDuration or AUTO_DISMISS_DEFAULT_SEC
        if durA ~= durB then
            return durA > durB
        end
        return (a.createdAt or 0) < (b.createdAt or 0)
    end)
end

function Toast:LayoutStack()
    EnsureAnchorFrame()

    if #self.activeItems == 0 then
        for _, f in ipairs(self.framePool) do
            f.itemData = nil
            f:Hide()
        end
        if self.anchorFrame then
            self.anchorFrame:SetScript("OnUpdate", nil)
        end
        return
    end

    local count = math.min(#self.activeItems, MAX_VISIBLE_TOASTS)
    for i = 1, MAX_VISIBLE_TOASTS do
        local f = self:EnsureFrame(i)
        if i <= count then
            local item = self.activeItems[i]
            local extraInQueue = (i == count) and #self.queue or 0
            f:ClearAllPoints()
            if i == 1 then
                f:SetPoint("TOP", self.anchorFrame, "TOP", 0, 0)
            else
                local prev = self.framePool[i - 1]
                f:SetPoint("TOP", prev, "BOTTOM", 0, -6)
            end
            RenderItemOnFrame(f, item, extraInQueue)
            f:Show()
        else
            f.itemData = nil
            f:Hide()
        end
    end

    -- Single shared OnUpdate ticker to drive progress bars and auto-dismiss cleanly
    self.anchorFrame:SetScript("OnUpdate", function(_, dt)
        if #Toast.activeItems == 0 then
            Toast.anchorFrame:SetScript("OnUpdate", nil)
            return
        end

        local needsLayout = false
        local delta = dt or 0

        for i = #Toast.activeItems, 1, -1 do
            local it = Toast.activeItems[i]
            local f = Toast.framePool[i]
            local isHovered = f and f:IsShown() and f:IsMouseOver()

            if not isHovered then
                it.elapsed = (it.elapsed or 0) + delta
                local totalDur = it.totalDuration or AUTO_DISMISS_DEFAULT_SEC
                local remainingFrac = math.max(0, 1 - (it.elapsed / totalDur))

                if f and f:IsShown() and f.progressFill then
                    f.progressFill:SetWidth(math.max(1, (TOAST_WIDTH - 24) * remainingFrac))
                end

                if it.elapsed >= totalDur then
                    table.remove(Toast.activeItems, i)
                    needsLayout = true
                end
            end
        end

        if needsLayout then
            while #Toast.queue > 0 and #Toast.activeItems < MAX_VISIBLE_TOASTS do
                local nextItem = table.remove(Toast.queue, 1)
                table.insert(Toast.activeItems, nextItem)
            end
            Toast:SortActiveItems()
            Toast:LayoutStack()
        end
    end)
end

function Toast:DismissItem(item)
    if not item then return end
    for i, it in ipairs(self.activeItems) do
        if it == item or (it.id and it.id == item.id) then
            table.remove(self.activeItems, i)
            break
        end
    end

    while #self.queue > 0 and #self.activeItems < MAX_VISIBLE_TOASTS do
        local nextItem = table.remove(self.queue, 1)
        table.insert(self.activeItems, nextItem)
    end

    self:SortActiveItems()
    self:LayoutStack()
end

function Toast:DismissAll()
    wipe(self.queue)
    wipe(self.activeItems)
    self:LayoutStack()
end

--- Display or coalesce an incoming addon notification item inside the floating toast stack.
function Toast:PushNotification(item)
    if type(item) ~= "table" then return end
    local s = ns.db and ns.db.settings
    if item.kind == "FRIEND_ONLINE" then
        if s and s.friendOnlineAlertToast == false then
            return
        end
    elseif item.kind == "WATCHLIST_ONLINE" then
        if s and s.alerts and s.alerts.toast == false then
            return
        end
    else
        if s and s.addonMsgTaskbarFlash ~= false and (item.priority or 1) >= 2 and FlashClientIcon then
            pcall(FlashClientIcon)
        end
        if s and s.addonMsgToast == false then
            return
        end
    end

    local cKey = FormatCooldownKey(item)

    -- Check for coalescing in active items
    for _, active in ipairs(self.activeItems) do
        if FormatCooldownKey(active) == cKey then
            active.text = item.text
            active.sender = item.sender or active.sender
            active.senderClass = item.senderClass or active.senderClass
            active.coalescedCount = (active.coalescedCount or 1) + 1
            active.elapsed = 0
            self:LayoutStack()
            return
        end
    end

    -- Check for coalescing in queued items
    for _, queued in ipairs(self.queue) do
        if FormatCooldownKey(queued) == cKey then
            queued.text = item.text
            queued.sender = item.sender or queued.sender
            queued.senderClass = item.senderClass or queued.senderClass
            queued.coalescedCount = (queued.coalescedCount or 1) + 1
            return
        end
    end

    local entry = {}
    for k, v in pairs(item) do
        entry[k] = v
    end
    entry.coalescedCount = 1
    entry.elapsed = 0
    entry.createdAt = time()

    local isInvite = (entry.kind == "RMI" and entry.roomId and entry.roomId ~= "")
    if not entry.totalDuration then
        if isInvite then
            entry.totalDuration = AUTO_DISMISS_INVITE_SEC
        elseif entry.kind == "WORLDBUFF" then
            entry.totalDuration = AUTO_DISMISS_BUFF_SEC
        elseif entry.kind == "FRIEND_ONLINE" or entry.kind == "WATCHLIST_ONLINE" then
            entry.totalDuration = AUTO_DISMISS_FRIEND_SEC
        else
            entry.totalDuration = AUTO_DISMISS_DEFAULT_SEC
        end
    end

    if #self.activeItems < MAX_VISIBLE_TOASTS then
        table.insert(self.activeItems, entry)
        self:SortActiveItems()
        self:LayoutStack()
    else
        if #self.queue < MAX_QUEUE then
            table.insert(self.queue, entry)
        else
            self.queue[#self.queue] = entry
        end
        self:LayoutStack()
    end
end

--- Preview sample toast notifications directly from Settings or '/sc toast' for layout positioning & sound testing.
function Toast:ShowTestNotification(variant)
    local v = type(variant) == "string" and variant:lower():match("^%s*(.-)%s*$") or ""
    if v == "clear" or v == "dismiss" or v == "hide" or v == "reset" then
        self:DismissAll()
        return
    end

    local resolvedSelf = Compat and Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myName = (resolvedSelf and resolvedSelf.fullName) or (ns.Safe and ns.Safe.String(ns.Safe.Call(UnitName, "player"))) or "SocialCentral"
    local _, myClass = ns.Safe and ns.Safe.Call(UnitClass, "player") or UnitClass("player")
    local now = time()

    if v == "invite" or v == "room" then
        self:PushNotification({
            id = "test:invite:" .. tostring(now),
            kind = "RMI",
            roomId = "test-room-preview",
            sourceTag = L["Room Invite"],
            sender = myName,
            senderClass = myClass or "MAGE",
            text = "Dungeon & Raid Social",
            priority = 2,
            totalDuration = AUTO_DISMISS_INVITE_SEC,
        })
    elseif v == "friend" then
        self:PushNotification({
            id = "test:friend:" .. tostring(now),
            kind = "FRIEND_ONLINE",
            sourceTag = L["Friend"],
            sender = myName,
            senderClass = myClass or "WARRIOR",
            text = L["Online"],
            priority = 1,
            totalDuration = AUTO_DISMISS_FRIEND_SEC,
        })
    elseif v == "watchlist" then
        self:PushNotification({
            id = "test:watchlist:" .. tostring(now),
            kind = "WATCHLIST_ONLINE",
            sourceTag = L["Watchlist"],
            sender = myName,
            senderClass = myClass or "ROGUE",
            text = L["Online"],
            priority = 2,
            totalDuration = AUTO_DISMISS_FRIEND_SEC,
        })
    elseif v == "buff" or v == "buffs" then
        self:PushNotification({
            id = "test:buff:" .. tostring(now),
            kind = "WORLDBUFF",
            sourceTag = L["World Buffs"],
            sender = "Rallying Cry of the Dragonslayer",
            senderClass = nil,
            text = "~15s",
            priority = 2,
            totalDuration = AUTO_DISMISS_BUFF_SEC,
        })
    elseif v == "queue" or v == "multi" or v == "stack" then
        wipe(self.queue)
        wipe(self.activeItems)
        -- Push items with different durations: 20s (Invite), 10s (Direct), 8s (Friend)
        -- They will automatically be sorted with longest (Invite) on top and shortest on bottom!
        self:PushNotification({
            id = "test:invite:" .. tostring(now),
            kind = "RMI",
            roomId = "test-room-preview",
            sourceTag = L["Room Invite"],
            sender = myName,
            senderClass = myClass or "MAGE",
            text = "Dungeon & Raid Social",
            priority = 2,
            totalDuration = AUTO_DISMISS_INVITE_SEC,
        })
        self:PushNotification({
            id = "test:direct:" .. tostring(now),
            kind = "DIRECT",
            sourceTag = L["Direct Addon"],
            sender = myName,
            senderClass = myClass,
            text = L["Sample addon notification toast — drag anywhere to reposition!"],
            priority = 2,
            totalDuration = AUTO_DISMISS_DEFAULT_SEC,
        })
        self:PushNotification({
            id = "test:friend:" .. tostring(now),
            kind = "FRIEND_ONLINE",
            sourceTag = L["Friend"],
            sender = myName,
            senderClass = myClass or "WARRIOR",
            text = L["Online"],
            priority = 1,
            totalDuration = AUTO_DISMISS_FRIEND_SEC,
        })
    else
        self:PushNotification({
            id = "test:direct:" .. tostring(now),
            kind = "DIRECT",
            sourceTag = L["Direct Addon"],
            sender = myName,
            senderClass = myClass,
            text = L["Sample addon notification toast — drag anywhere to reposition!"],
            threadKey = ns.Chat and ns.Chat.activeThreadKey or nil,
            priority = 2,
            totalDuration = AUTO_DISMISS_DEFAULT_SEC,
        })
    end

    if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then
        pcall(PlaySound, SOUNDKIT.TELL_MESSAGE, "Master")
    end
end

function Toast:Init()
    if self.hooksInitialized then return end
    self.hooksInitialized = true

    EnsureAnchorFrame()

    ns:On("ADDON_MESSAGE_NOTIFY", function(payload)
        Toast:PushNotification(payload)
    end)

    ns:On("CHAT_UPDATED", function()
        -- Automatically dismiss any active toast if the player opened and read that exact thread elsewhere.
        for i = #Toast.activeItems, 1, -1 do
            local cur = Toast.activeItems[i]
            if cur and cur.threadKey and ns.UI and ns.UI.IsChatThreadVisible and ns.UI:IsChatThreadVisible(cur.threadKey) then
                Toast:DismissItem(cur)
            end
        end
    end)

    if Theme and Theme.RegisterListener then
        Theme:RegisterListener(function()
            for _, f in ipairs(Toast.framePool) do
                ApplyToastThemeToFrame(f)
            end
        end)
    end
end

ns.NotificationToast = Toast
table.insert(ns.modules, Toast)
