local _, ns = ...

local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })
local Compat = ns.Compat
local Theme = ns.Theme

-- Compact, 100%-opaque, movable floating notification pill for incoming SCentral1 addon messages.
-- Security & performance guarantees:
--   - Uses standard non-secure BackdropTemplate frames (zero UI taint; clickable in combat, navigation defers safely).
--   - Attaches OnUpdate timer only while shown (0ms idle CPU when hidden).
--   - Zero global leaks; all positioning persists via Theme:MakeMovable.
local Toast = {
    frame = nil,
    activeItem = nil,
    queue = {},
    elapsedShown = 0,
    hooksInitialized = false,
}

local TOAST_WIDTH = 316
local TOAST_H_DEFAULT = 58
local TOAST_H_INVITE = 84
local AUTO_DISMISS_SEC = 7.0
local MAX_QUEUE = 8
local ICON_TEX = "Interface\\AddOns\\SocialCentral\\Media\\icon"

local KIND_RGB = {
    DIRECT      = { 0.25, 0.72, 0.45 },
    ROOM        = { 0.35, 0.65, 1.00 },
    RMI         = { 0.35, 0.65, 1.00 },
    ALLIANCE    = { 0.80, 0.56, 1.00 },
    CLAN_LFG    = { 0.96, 0.78, 0.24 },
    CLAN_EVENT  = { 0.96, 0.78, 0.24 },
    CLAN_SIGNUP = { 0.35, 0.85, 0.55 },
    SCOUT       = { 0.96, 0.28, 0.28 },
    WORLDBUFF   = { 0.98, 0.62, 0.22 },
    FRIEND_ONLINE = { 0.32, 0.84, 0.56 },
}

local function FormatCooldownKey(item)
    if item.threadKey and item.threadKey ~= "" then
        return item.threadKey
    end
    return tostring(item.kind or "MSG") .. ":" .. tostring(item.sender or "?")
end

local function ApplyToastTheme()
    local f = Toast.frame
    if not f then return end
    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(f, "window")
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

local function RenderItem(item)
    local f = Toast.frame
    if not f or not item then return end

    local isInvite = (item.kind == "RMI" and item.roomId and item.roomId ~= "")
    f:SetSize(TOAST_WIDTH, isInvite and TOAST_H_INVITE or TOAST_H_DEFAULT)

    local rgb = KIND_RGB[item.kind] or KIND_RGB.DIRECT
    if f.accentBar then
        f.accentBar:SetColorTexture(rgb[1], rgb[2], rgb[3], 1.0)
    end
    if f.progressFill then
        f.progressFill:SetColorTexture(rgb[1], rgb[2], rgb[3], 0.85)
        f.progressFill:SetWidth(TOAST_WIDTH - 12)
    end

    local sourceTag = item.sourceTag or "SocialCentral"
    local hex = (item.senderClass and Compat and Compat.ClassHex) and Compat.ClassHex(item.senderClass) or "|cffffffff"
    local senderText = hex .. tostring(item.sender or "?") .. "|r"
    local mult = (item.coalescedCount and item.coalescedCount > 1) and (" |cff9da7b5(x" .. tostring(item.coalescedCount) .. ")|r") or ""
    f.titleLbl:SetText(string.format("|cff%02x%02x%02x%s|r · %s%s", math.floor(rgb[1] * 255), math.floor(rgb[2] * 255), math.floor(rgb[3] * 255), sourceTag, senderText, mult))

    local bodyText = tostring(item.text or "")
    if isInvite then
        bodyText = string.format(L["Invite to room: %s"], bodyText)
    end
    f.bodyLbl:SetText(bodyText)

    local qLen = #Toast.queue
    if qLen > 0 then
        f.queueLbl:SetText("+" .. tostring(qLen))
        f.queueLbl:Show()
    else
        f.queueLbl:SetText("")
        f.queueLbl:Hide()
    end

    if isInvite then
        f.actionRow:Show()
        f.bodyLbl:ClearAllPoints()
        f.bodyLbl:SetPoint("TOPLEFT", f.titleLbl, "BOTTOMLEFT", 0, -2)
        f.bodyLbl:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    else
        f.actionRow:Hide()
        f.bodyLbl:ClearAllPoints()
        f.bodyLbl:SetPoint("TOPLEFT", f.titleLbl, "BOTTOMLEFT", 0, -4)
        f.bodyLbl:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    end

    ApplyToastTheme()
    Toast.elapsedShown = 0
    f:SetScript("OnUpdate", function(_, dt)
        if not Toast.activeItem then
            f:SetScript("OnUpdate", nil)
            f:Hide()
            return
        end
        if f:IsMouseOver() then
            return
        end
        Toast.elapsedShown = Toast.elapsedShown + (dt or 0)
        local remainingFrac = math.max(0, 1 - (Toast.elapsedShown / AUTO_DISMISS_SEC))
        if f.progressFill then
            f.progressFill:SetWidth(math.max(1, (TOAST_WIDTH - 12) * remainingFrac))
        end
        if Toast.elapsedShown >= AUTO_DISMISS_SEC then
            Toast:AdvanceOrHide(true)
        end
    end)
    f:Show()
end

function Toast:AdvanceOrHide(advanceQueue)
    if advanceQueue and #Toast.queue > 0 then
        Toast.activeItem = table.remove(Toast.queue, 1)
        RenderItem(Toast.activeItem)
        return
    end
    Toast.activeItem = nil
    if Toast.frame then
        Toast.frame:SetScript("OnUpdate", nil)
        Toast.frame:Hide()
    end
end

local function EnsureToastFrame()
    if Toast.frame then
        return Toast.frame
    end

    local f = CreateFrame("Button", "SocialCentralNotificationToast", UIParent, "BackdropTemplate")
    f:SetSize(TOAST_WIDTH, TOAST_H_DEFAULT)
    f:SetPoint("TOP", UIParent, "TOP", 0, -110)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(180)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:Hide()

    local accentBar = f:CreateTexture(nil, "OVERLAY")
    accentBar:SetWidth(3)
    accentBar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -6)
    accentBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 5, 6)
    f.accentBar = accentBar

    local iconTex = f:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(22, 22)
    iconTex:SetPoint("TOPLEFT", f, "TOPLEFT", 13, -11)
    iconTex:SetTexture(ICON_TEX)
    f.iconTex = iconTex

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    closeBtn:SetFrameLevel((f:GetFrameLevel() or 180) + 10)
    closeBtn:SetScript("OnClick", function()
        Toast:AdvanceOrHide(true)
    end)
    f.closeBtn = closeBtn

    local queueLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    queueLbl:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    queueLbl:SetJustifyH("RIGHT")
    queueLbl:Hide()
    f.queueLbl = queueLbl

    local titleLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleLbl:SetPoint("TOPLEFT", iconTex, "TOPRIGHT", 8, 1)
    titleLbl:SetPoint("RIGHT", queueLbl, "LEFT", -4, 0)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetWordWrap(false)
    f.titleLbl = titleLbl

    local bodyLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bodyLbl:SetPoint("TOPLEFT", titleLbl, "BOTTOMLEFT", 0, -4)
    bodyLbl:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    bodyLbl:SetJustifyH("LEFT")
    bodyLbl:SetWordWrap(false)
    f.bodyLbl = bodyLbl

    local actionRow = CreateFrame("Frame", nil, f)
    actionRow:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 42, 7)
    actionRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 7)
    actionRow:SetHeight(22)
    actionRow:Hide()
    f.actionRow = actionRow

    local acceptBtn = Theme:CreateButton(actionRow, 92, 20, L["Accept"], "primary")
    Theme:AutoFitButton(acceptBtn, 76, 14, 130)
    acceptBtn:SetPoint("LEFT", actionRow, "LEFT", 0, 0)
    acceptBtn:SetScript("OnClick", function()
        local item = Toast.activeItem
        if not (item and item.roomId and ns.Chat and ns.Chat.AcceptRoomInvite) then
            return
        end
        local rId = item.roomId
        ns.Chat:AcceptRoomInvite(rId)
        wipe(Toast.queue)
        Toast:AdvanceOrHide(false)
        if ns.NavigateToModule then
            ns:NavigateToModule("chat", { threadKey = "room:" .. rId })
        end
    end)
    f.acceptBtn = acceptBtn

    local declineBtn = Theme:CreateButton(actionRow, 92, 20, L["Decline"], "default")
    Theme:AutoFitButton(declineBtn, 76, 14, 130)
    declineBtn:SetPoint("LEFT", acceptBtn, "RIGHT", 6, 0)
    declineBtn:SetScript("OnClick", function()
        local item = Toast.activeItem
        if item and item.roomId and ns.Chat and ns.Chat.DeclineRoomInvite then
            ns.Chat:DeclineRoomInvite(item.roomId)
        end
        Toast:AdvanceOrHide(true)
    end)
    f.declineBtn = declineBtn

    local progressFill = f:CreateTexture(nil, "OVERLAY")
    progressFill:SetHeight(2)
    progressFill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 3)
    progressFill:SetWidth(TOAST_WIDTH - 12)
    f.progressFill = progressFill

    f:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            wipe(Toast.queue)
            Toast:AdvanceOrHide(false)
            return
        end
        local item = Toast.activeItem
        Toast:AdvanceOrHide(false)
        NavigateForItem(item)
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
        self:SetScript("OnUpdate", nil)
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)

    f:HookScript("OnDragStart", function(self)
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)

    if Theme and Theme.MakeMovable then
        Theme:MakeMovable(f, {
            key = "notification_toast",
            anchor = "TOP",
            combatLock = false,
            onReset = function(win)
                win:ClearAllPoints()
                win:SetPoint("TOP", UIParent, "TOP", 0, -110)
            end,
        })
    end

    Toast.frame = f
    ApplyToastTheme()
    return f
end

--- Display or coalesce an incoming addon notification item inside the floating toast pill.
function Toast:PushNotification(item)
    if type(item) ~= "table" then return end
    local s = ns.db and ns.db.settings
    if item.kind == "FRIEND_ONLINE" then
        if s and s.friendOnlineAlertToast == false then
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

    EnsureToastFrame()
    local cKey = FormatCooldownKey(item)

    if self.activeItem and FormatCooldownKey(self.activeItem) == cKey then
        self.activeItem.text = item.text
        self.activeItem.sender = item.sender or self.activeItem.sender
        self.activeItem.senderClass = item.senderClass or self.activeItem.senderClass
        self.activeItem.coalescedCount = (self.activeItem.coalescedCount or 1) + 1
        RenderItem(self.activeItem)
        return
    end

    for _, queued in ipairs(self.queue) do
        if FormatCooldownKey(queued) == cKey then
            queued.text = item.text
            queued.sender = item.sender or queued.sender
            queued.senderClass = item.senderClass or queued.senderClass
            queued.coalescedCount = (queued.coalescedCount or 1) + 1
            if self.activeItem then
                RenderItem(self.activeItem)
            end
            return
        end
    end

    local entry = {}
    for k, v in pairs(item) do
        entry[k] = v
    end
    entry.coalescedCount = 1

    if not self.activeItem then
        self.activeItem = entry
        RenderItem(self.activeItem)
        return
    end

    if #self.queue < MAX_QUEUE then
        table.insert(self.queue, entry)
    else
        self.queue[#self.queue] = entry
    end
    RenderItem(self.activeItem)
end

--- Preview a sample toast notification directly from Settings for layout positioning & sound testing.
function Toast:ShowTestNotification()
    local resolvedSelf = Compat and Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myName = (resolvedSelf and resolvedSelf.fullName) or (ns.Safe and ns.Safe.String(ns.Safe.Call(UnitName, "player"))) or "SocialCentral"
    local _, myClass = ns.Safe and ns.Safe.Call(UnitClass, "player") or UnitClass("player")
    EnsureToastFrame()
    self.activeItem = {
        id = "test:" .. tostring(time()),
        kind = "DIRECT",
        sourceTag = L["Direct Addon"],
        sender = myName,
        senderClass = myClass,
        text = L["Sample addon notification toast — drag anywhere to reposition!"],
        threadKey = ns.Chat and ns.Chat.activeThreadKey or nil,
        ts = time(),
        priority = 2,
        coalescedCount = 1,
    }
    RenderItem(self.activeItem)
    if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then
        pcall(PlaySound, SOUNDKIT.TELL_MESSAGE, "Master")
    end
end

function Toast:DismissAll()
    wipe(self.queue)
    self:AdvanceOrHide(false)
end

function Toast:Init()
    if self.hooksInitialized then return end
    self.hooksInitialized = true

    ns:On("ADDON_MESSAGE_NOTIFY", function(payload)
        Toast:PushNotification(payload)
    end)

    ns:On("CHAT_UPDATED", function()
        -- Automatically hide an active toast if the player opened and read that exact thread elsewhere.
        local cur = Toast.activeItem
        if cur and cur.threadKey and ns.UI and ns.UI.IsChatThreadVisible and ns.UI:IsChatThreadVisible(cur.threadKey) then
            Toast:AdvanceOrHide(true)
        end
    end)

    if Theme and Theme.RegisterListener then
        Theme:RegisterListener(function()
            if Toast.frame then
                ApplyToastTheme()
            end
        end)
    end
end

ns.NotificationToast = Toast
table.insert(ns.modules, Toast)
