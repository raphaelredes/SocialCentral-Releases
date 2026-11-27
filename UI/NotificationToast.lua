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
    recentHistory = {},
    activeIndex = 1,
    tutorialDialog = nil,
    pendingTutorial = false,
    hooksInitialized = false,
}

local TOAST_WIDTH = 316
local TOAST_H_DEFAULT = 56
local TOAST_H_INVITE = 84
local NAV_H = 22
local MAX_NAV_NUMS = 5
local PAGE_SIZE = 4
local MAX_VISIBLE_TOASTS = 1
local MAX_QUEUE = 15
local MAX_RECENT_HISTORY = 25
local DEFAULT_TOAST_DURATION_SEC = 6.0

local function GetConfiguredToastDuration()
    local raw = ns.db and ns.db.settings and tonumber(ns.db.settings.toastDuration)
    if not raw or raw ~= raw then
        return DEFAULT_TOAST_DURATION_SEC
    end
    return math.max(3, math.min(15, math.floor(raw + 0.5)))
end

local ICON_DEFAULT = "Interface\\AddOns\\SocialCentral\\Media\\icon"
local ICON_MAIL    = "Interface\\AddOns\\SocialCentral\\Media\\toast-mail"
local ICON_PARTY   = "Interface\\AddOns\\SocialCentral\\Media\\toast-party"
local ICON_ONLINE  = "Interface\\AddOns\\SocialCentral\\Media\\toast-online"
local ICON_GLOW    = "Interface\\AddOns\\SocialCentral\\Media\\toast-glow"
local ICON_BELL_OFF = "Interface\\AddOns\\SocialCentral\\Media\\bell-off"
local ICON_CLASS_CREST = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local PORTRAIT_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local WHITE8X8     = "Interface\\Buttons\\WHITE8X8"

local function ApplyTexGradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    if not tex then return end
    if Theme and Theme.ApplySafeGradient then
        Theme:ApplySafeGradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    else
        tex:SetColorTexture((r1 + r2) * 0.5, (g1 + g2) * 0.5, (b1 + b2) * 0.5, (a1 + a2) * 0.5)
    end
end

local KIND_RGB = {
    WHISPER          = { 1.00, 0.50, 1.00 },
    DIRECT           = { 1.00, 0.50, 1.00 },
    BN_WHISPER       = { 0.10, 0.82, 1.00 },
    PARTY            = { 0.48, 0.68, 1.00 },
    GROUP            = { 0.48, 0.68, 1.00 },
    RAID             = { 1.00, 0.54, 0.18 },
    GUILD            = { 0.28, 0.94, 0.40 },
    OFFICER          = { 0.28, 0.94, 0.40 },
    ROOM             = { 0.74, 0.50, 1.00 },
    RMI              = { 0.74, 0.50, 1.00 },
    ALLIANCE         = { 0.74, 0.50, 1.00 },
    CLAN_LFG         = { 0.48, 0.68, 1.00 },
    CLAN_EVENT       = { 0.28, 0.94, 0.40 },
    CLAN_SIGNUP      = { 0.28, 0.94, 0.40 },
    SCOUT            = { 0.96, 0.28, 0.28 },
    WORLDBUFF        = { 0.98, 0.62, 0.22 },
    FRIEND_ONLINE    = { 0.28, 0.92, 0.52 },
    FRIEND_OFFLINE   = { 0.62, 0.66, 0.72 },
    WATCHLIST_ONLINE = { 0.40, 0.94, 0.48 },
    AVOID_ALERT      = { 1.00, 0.30, 0.30 },
    MENTION          = { 1.00, 0.80, 0.24 },
    FOCUS_SUMMARY    = { 0.35, 0.78, 1.00 },
    VERSION_UPDATE   = { 1.00, 0.78, 0.20 },
}

local function ResolveIconForKind(kind)
    if kind == "FRIEND_ONLINE" or kind == "FRIEND_OFFLINE" or kind == "WATCHLIST_ONLINE" then
        return ICON_ONLINE
    elseif kind == "RMI" or kind == "CLAN_LFG" then
        return ICON_PARTY
    elseif kind == "WORLDBUFF" or kind == "SCOUT" or kind == "AVOID_ALERT" or kind == "VERSION_UPDATE" then
        return ICON_DEFAULT
    end
    return ICON_MAIL
end

local function ApplyCircleMask(parent, tex, size)
    if not (parent and parent.CreateMaskTexture and tex) then return end
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(size, size)
    mask:SetPoint("CENTER", tex, "CENTER", 0, 0)
    tex:AddMaskTexture(mask)
end

local function GetToastTooltipHint(item)
    if not item then
        return L["Right-click: options | Drag: move"]
    end
    local k = item.kind
    local action
    if k == "FRIEND_ONLINE" or k == "FRIEND_OFFLINE" then
        action = L["Click: view in Social"]
    elseif k == "WATCHLIST_ONLINE" then
        action = L["Click: view in Watchlist"]
    elseif k == "AVOID_ALERT" then
        action = L["Click: open Group"]
    elseif k == "WORLDBUFF" then
        action = L["Click: view World Buffs"]
    elseif k == "CLAN_EVENT" or k == "CLAN_SIGNUP" then
        action = L["Click: view Guild Events"]
    elseif k == "CLAN_LFG" then
        action = L["Click: open Group Finder"]
    elseif k == "SCOUT" then
        action = L["Click: open Radar"]
    elseif k == "VERSION_UPDATE" then
        action = L["Click: open update link"]
    else
        action = L["Click: open conversation"]
    end
    return action .. " · " .. L["Right-click: options | Drag: move"]
end

local function FormatCooldownKey(item)
    if item.kind == "MENTION" then
        return "MENTION:" .. tostring(item.threadKey or item.sender or "?")
    end
    if item.threadKey and item.threadKey ~= "" then
        return item.threadKey
    end
    return tostring(item.kind or "MSG") .. ":" .. tostring(item.sender or "?")
end

local function RecordRecentNotification(item)
    if type(item) ~= "table" or item.isTest then return end
    if item.kind == "FOCUS_SUMMARY" then return end
    local cKey = FormatCooldownKey(item)
    local nowTs = item.ts or time()
    for i, rec in ipairs(Toast.recentHistory) do
        if rec.cKey == cKey then
            rec.text = item.text or rec.text
            rec.sender = item.sender or rec.sender
            rec.senderClass = item.senderClass or rec.senderClass
            rec.sourceTag = item.sourceTag or rec.sourceTag
            rec.ts = nowTs
            rec.coalescedCount = (rec.coalescedCount or 1) + 1
            if i > 1 then
                table.remove(Toast.recentHistory, i)
                table.insert(Toast.recentHistory, 1, rec)
            end
            return
        end
    end
    local copy = {}
    for k, v in pairs(item) do
        copy[k] = v
    end
    copy.cKey = cKey
    copy.ts = nowTs
    copy.coalescedCount = 1
    table.insert(Toast.recentHistory, 1, copy)
    while #Toast.recentHistory > MAX_RECENT_HISTORY do
        table.remove(Toast.recentHistory, #Toast.recentHistory)
    end
end

local function ApplyToastNavBarTheme(navBar, p)
    if not navBar or not p then return end
    local isBlizz = Theme and Theme.IsBlizzard and Theme:IsBlizzard(p)
    if navBar.bg then
        if isBlizz then
            navBar.bg:SetColorTexture(0.08, 0.07, 0.06, 0.92)
        else
            local ib = p.insetBg or { 0.05, 0.06, 0.08 }
            navBar.bg:SetColorTexture(ib[1], ib[2], ib[3], 0.92)
        end
    end
    if navBar.div then
        local sb = p.surfaceBorder or { 0.30, 0.30, 0.30 }
        navBar.div:SetColorTexture(sb[1], sb[2], sb[3], 0.55)
    end
    if navBar.countFs then
        local muted = p.textMuted or { 0.65, 0.70, 0.78 }
        navBar.countFs:SetTextColor(muted[1], muted[2], muted[3])
    end
    if navBar.prevPageBtn then Theme:StyleButton(navBar.prevPageBtn, "default") end
    if navBar.prevBtn then Theme:StyleButton(navBar.prevBtn, "default") end
    if navBar.nextBtn then Theme:StyleButton(navBar.nextBtn, "default") end
    if navBar.nextPageBtn then Theme:StyleButton(navBar.nextPageBtn, "default") end
    if navBar.numBtns then
        for _, btn in ipairs(navBar.numBtns) do
            Theme:StyleButton(btn, btn._isActive and "primary" or "default")
            Theme:SetButtonActive(btn, btn._isActive == true, btn._isActive and "primary" or "default")
        end
    end
end

local function ApplyToastThemeToFrame(f, forceTheme)
    if not f then return end
    local p = Theme and Theme.GetPalette and Theme:GetPalette()
    local palKey = (p and p.key) or "dark"
    local themeDirty = (forceTheme == true) or (f._appliedPalKey ~= palKey)
    local borderKey = tostring(f._lastGradKind or "DIRECT") .. ":" .. palKey

    if themeDirty then
        f._appliedPalKey = palKey
        if Theme and Theme.ApplyBackdrop then
            Theme:ApplyBackdrop(f, "window")
        end
        if p then
            local isWarm = (p.key == "blizzard" or p.key == "native")
            if f.topBevel then
                if isWarm then
                    f.topBevel:SetColorTexture(1, 0.90, 0.68, 0.18)
                else
                    f.topBevel:SetColorTexture(0.65, 0.85, 1.0, 0.16)
                end
            end
            if f.progressTrack then
                local pt = p.insetBg or { 0.05, 0.06, 0.09 }
                f.progressTrack:SetColorTexture(pt[1], pt[2], pt[3], 0.90)
            end
            if f.bodyLbl then
                f.bodyLbl:SetTextColor(p.text[1], p.text[2], p.text[3])
            end
            if f.navBar then
                ApplyToastNavBarTheme(f.navBar, p)
            end
            if f.closeBtn and Theme.StyleButton then
                Theme:StyleButton(f.closeBtn, "default")
            end
            if f.muteNotifBtn and Theme.StyleButton then
                Theme:StyleButton(f.muteNotifBtn, "default")
            end
            if f.acceptBtn and Theme.StyleButton then
                Theme:StyleButton(f.acceptBtn, "primary")
            end
            if f.declineBtn and Theme.StyleButton then
                Theme:StyleButton(f.declineBtn, "default")
            end
            if f.buffAnnounceBtn and Theme.StyleButton then
                Theme:StyleButton(f.buffAnnounceBtn, "primary")
            end
            if f.markReadBtn and Theme.StyleButton then
                Theme:StyleButton(f.markReadBtn, "default")
            end
            if f.helpBtn and f.helpBtn.RefreshTheme then
                f.helpBtn:RefreshTheme()
            end
        end
    end

    if (themeDirty or f._appliedBorderKey ~= borderKey) and f._kindRgb and f.SetBackdropBorderColor then
        f._appliedBorderKey = borderKey
        local r, g, b = f._kindRgb[1], f._kindRgb[2], f._kindRgb[3]
        f:SetBackdropBorderColor(r * 0.58 + 0.16, g * 0.58 + 0.16, b * 0.58 + 0.16, 1.0)
    end
end

local function NavigateForItem(item)
    if not item then return end
    local k = item.kind
    if k == "VERSION_UPDATE" then
        if ns.UI and ns.UI.OpenUpdateModal then
            ns.UI:OpenUpdateModal()
        end
    elseif k == "SCOUT" then
        if ns.SpotterHUD and ns.SpotterHUD.Show then
            ns.SpotterHUD:Show(true)
        elseif ns.NavigateToModule then
            ns:NavigateToModule("clan")
        end
    elseif k == "WORLDBUFF" then
        if ns.NavigateToModule then
            ns:NavigateToModule("buffs")
        end
    elseif k == "FRIEND_ONLINE" or k == "FRIEND_OFFLINE" then
        if ns.NavigateToModule then
            ns:NavigateToModule("social", { socialSearch = "" })
        end
    elseif k == "AVOID_ALERT" then
        if ns.NavigateToModule then
            ns:NavigateToModule("group")
        end
    elseif k == "WATCHLIST_ONLINE" then
        if ns.NavigateToModule then
            ns:NavigateToModule("watchlist", { watchlistSearch = "" })
        end
    elseif k == "CLAN_EVENT" or k == "CLAN_SIGNUP" then
        if ns.NavigateToModule then
            ns:NavigateToModule("clan", { clanRightView = "events", eventId = item.eventId })
        end
    elseif k == "CLAN_LFG" then
        if ns.NavigateToModule then
            ns:NavigateToModule("lfg", { clanRightView = "browse", lfgSelectKey = item.lookupKey })
        end
    elseif k == "RMI" then
        if ns.NavigateToModule then
            ns:NavigateToModule("chat", { pendingRoomId = item.roomId })
        end
    elseif k == "MENTION" then
        if ns.NavigateToModule then
            ns:NavigateToModule("chat", { threadKey = item.threadKey or "mentions:radar" })
        end
    elseif k == "FOCUS_SUMMARY" then
        if ns.QuickReply and ns.QuickReply.OpenLatest and ns.QuickReply:OpenLatest(true) then
            return
        end
        if ns.NavigateToModule then
            ns:NavigateToModule("chat")
        end
    else
        local s = ns.db and ns.db.settings
        local qrEnabled = (not s) or s.quickReplyEnabled ~= false
        if qrEnabled and item.threadKey and ns.QuickReply and ns.QuickReply.OpenThread and ns.QuickReply:OpenThread(item.threadKey, true) then
            return
        end
        if ns.NavigateToModule then
            ns:NavigateToModule("chat", { threadKey = item.threadKey })
        end
    end
end

function Toast:RecordRecentItem(item)
    RecordRecentNotification(item)
end

function Toast:GetRecentHistory()
    return self.recentHistory
end

function Toast:ClearRecentHistory()
    wipe(self.recentHistory)
end

function Toast:ActivateHistoryItem(item)
    if item then
        NavigateForItem(item)
    end
end

local function HasSavedCustomToastPosition()
    if Theme and Theme.HasSavedWindowPosition then
        return Theme:HasSavedWindowPosition("notification_toast")
    end
    local posTbl = ns.db and ns.db.windowPositions
    local saved = type(posTbl) == "table" and posTbl["notification_toast"] or nil
    return type(saved) == "table" and saved.dx ~= nil and saved.dy ~= nil
end

local function GetToastAnchorMode()
    local m = ns.db and ns.db.settings and ns.db.settings.msgPreviewAnchor
    if m == "chat_side" or m == "chat_top" then
        return m
    end
    return "minimap"
end

local function PositionToastAnchorBelowChat(anchor)
    if not anchor then return end
    anchor:ClearAllPoints()
    local uiW = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1280
    local uiH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 720
    local anchorScale = (anchor.GetEffectiveScale and anchor:GetEffectiveScale()) or 1
    if anchorScale <= 0 then anchorScale = 1 end
    local mode = GetToastAnchorMode()

    if mode == "minimap" and Minimap and Minimap:IsShown() and Minimap.GetLeft and Minimap.GetCenter then
        local mmScale = Minimap:GetEffectiveScale() or 1
        local ratio = mmScale / anchorScale
        local mmLeft = Minimap:GetLeft()
        local mmRight = Minimap:GetRight()
        local _, mmCy = Minimap:GetCenter()
        if mmLeft and mmRight and mmCy then
            local ml = mmLeft * ratio
            local mr = mmRight * ratio
            local mcy = mmCy * ratio
            local cx
            if ml >= (TOAST_WIDTH + 24) then
                cx = ml - (TOAST_WIDTH * 0.5) - 16
            else
                cx = math.min(uiW - (TOAST_WIDTH * 0.5) - 12, mr + (TOAST_WIDTH * 0.5) + 16)
            end
            local topY = math.max(160, math.min(uiH - 24, mcy - 54))
            anchor:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, topY)
            return
        end
    end

    local cf = (_G.ChatFrame1Background and _G.ChatFrame1Background.GetLeft and _G.ChatFrame1Background) or _G.ChatFrame1
    if cf and cf.GetLeft and cf.GetRight and cf.GetBottom and cf.GetTop then
        local cfScale = (cf.GetEffectiveScale and cf:GetEffectiveScale()) or 1
        local ratio = cfScale / anchorScale
        local cLeft = cf:GetLeft()
        local cRight = cf:GetRight()
        local cBottom = cf:GetBottom()
        local cTop = cf:GetTop()
        if cLeft and cRight and cBottom and cTop and cRight > cLeft then
            local cl = cLeft * ratio
            local cr = cRight * ratio
            local cb = cBottom * ratio
            local ct = cTop * ratio
            if mode == "chat_side" then
                local cx
                if (uiW - cr) >= (TOAST_WIDTH + 24) or ((cl + cr) * 0.5) < (uiW * 0.5) then
                    cx = cr + (TOAST_WIDTH * 0.5) + 14
                else
                    cx = math.max((TOAST_WIDTH * 0.5) + 12, cl - (TOAST_WIDTH * 0.5) - 14)
                end
                local topY = math.max(150, math.min(uiH - 24, ct - 12))
                anchor:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, topY)
                return
            elseif mode == "chat_top" then
                local tabRef = _G.GeneralDockManager or _G.ChatFrame1Tab
                local tabTop = 0
                if tabRef and tabRef.GetTop and tabRef.IsShown and tabRef:IsShown() then
                    local trScale = (tabRef.GetEffectiveScale and tabRef:GetEffectiveScale()) or 1
                    local tt = tabRef:GetTop()
                    if tt then
                        tabTop = tt * (trScale / anchorScale)
                    end
                end
                local cx = math.max((TOAST_WIDTH * 0.5) + 12, math.min(uiW - (TOAST_WIDTH * 0.5) - 12, cl + (TOAST_WIDTH * 0.5)))
                local topY = math.min(uiH - 20, math.max(ct, tabTop) + 96)
                anchor:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, topY)
                return
            end
            local cx = (cl + cr) * 0.5
            local minX = (TOAST_WIDTH * 0.5) + 12
            if cx < minX then cx = minX end
            local topY = cb - 36
            local eb = _G.ChatFrame1EditBox
            if eb and eb.GetBottom then
                local ebBot = eb:GetBottom()
                if ebBot and ebBot < cBottom and ebBot >= (cBottom - 56) then
                    topY = (ebBot * ratio) - 6
                end
            end
            topY = math.max(96, topY)
            anchor:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, topY)
            return
        end
    end
    anchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 42, 112)
end

local function EnsureAnchorFrame()
    if Toast.anchorFrame then
        return Toast.anchorFrame
    end

    local anchor = CreateFrame("Frame", "SocialCentralNotificationToastAnchor", UIParent)
    anchor:SetSize(TOAST_WIDTH, 1)
    PositionToastAnchorBelowChat(anchor)
    anchor:SetFrameStrata("DIALOG")
    anchor:SetFrameLevel(179)
    anchor:SetClampedToScreen(true)

    if Theme and Theme.MakeMovable then
        Theme:MakeMovable(anchor, {
            key = "notification_toast",
            anchor = "TOP",
            combatLock = false,
            onStop = function()
                if Toast.LayoutStack then
                    Toast:LayoutStack()
                end
            end,
            onReset = function(win)
                PositionToastAnchorBelowChat(win)
                if Toast.LayoutStack then
                    Toast:LayoutStack()
                end
            end,
        })
    end
    if not HasSavedCustomToastPosition() then
        PositionToastAnchorBelowChat(anchor)
    end

    Toast.anchorFrame = anchor
    if Theme and Theme.RegisterViewportListener then
        Theme:RegisterViewportListener("notification_toast", function()
            if Toast.anchorFrame then
                if not Theme:RestoreWindowPosition(Toast.anchorFrame, "notification_toast", false, { anchor = "TOP" }) then
                    PositionToastAnchorBelowChat(Toast.anchorFrame)
                end
                if Toast.LayoutStack then
                    Toast:LayoutStack()
                end
            end
        end)
    end
    return anchor
end

function Toast:RefreshAnchorMode()
    if self.anchorFrame and not HasSavedCustomToastPosition() then
        PositionToastAnchorBelowChat(self.anchorFrame)
        if self.LayoutStack then
            self:LayoutStack()
        end
    end
end

local function RemoveActiveToastAt(i)
    local curIdx = Toast.activeIndex or 1
    local removedActive = (i == curIdx)
    table.remove(Toast.activeItems, i)
    if i < curIdx then
        Toast.activeIndex = math.max(1, curIdx - 1)
    elseif curIdx > #Toast.activeItems then
        Toast.activeIndex = math.max(1, #Toast.activeItems)
    end
    return removedActive
end

local function PruneActiveToasts(predicateFn)
    local removedAny = false
    local removedActive = false
    for i = #Toast.activeItems, 1, -1 do
        local cur = Toast.activeItems[i]
        if predicateFn(cur) then
            if Toast.confirmPopup and Toast.confirmPopup:IsShown() and Toast.confirmPopup._targetItem == cur then
                Toast.confirmPopup:Hide()
            end
            if RemoveActiveToastAt(i) then
                removedActive = true
            end
            removedAny = true
        end
    end
    return removedAny, removedActive
end

local function DrainToastQueueAndResetElapsed(removedActive)
    while #Toast.queue > 0 and #Toast.activeItems < MAX_QUEUE do
        local nextItem = table.remove(Toast.queue, 1)
        table.insert(Toast.activeItems, nextItem)
    end
    if removedActive then
        local nextActive = Toast.activeItems[Toast.activeIndex or 1]
        if nextActive then
            nextActive.elapsed = 0
        end
    end
end

local function PrepareToastDragStart(f)
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == f then
        GameTooltip:Hide()
    end
    local anchor = Toast.anchorFrame
    if not (f and anchor) then return end
    local _, relTo = f:GetPoint(1)
    if relTo ~= anchor then
        local fx = f.GetCenter and f:GetCenter() or nil
        local fTop = f.GetTop and f:GetTop() or nil
        if fx and fTop and UIParent then
            anchor:ClearAllPoints()
            anchor:SetPoint("TOP", UIParent, "BOTTOMLEFT", fx, fTop)
        end
        f:ClearAllPoints()
        f:SetPoint("TOP", anchor, "TOP", 0, 0)
    end
end

local function SelectToastIndex(idx)
    local total = #Toast.activeItems
    if total == 0 then return end
    local clamped = math.max(1, math.min(idx or 1, total))
    Toast.activeIndex = clamped
    local cur = Toast.activeItems[clamped]
    if cur then
        cur.elapsed = 0
    end
    Toast:LayoutStack()
end

local function CycleToastNotification(delta)
    local total = #Toast.activeItems
    if total <= 1 then return end
    local cur = Toast.activeIndex or 1
    local nextIdx = ((cur - 1 + (delta or 1)) % total) + 1
    SelectToastIndex(nextIdx)
end

local function CycleToastPage(pageDelta)
    local total = #Toast.activeItems
    if total <= MAX_NAV_NUMS then return end
    local totalPages = math.ceil(total / PAGE_SIZE)
    local curPage = math.floor(((Toast.activeIndex or 1) - 1) / PAGE_SIZE) + 1
    local nextPage = ((curPage - 1 + (pageDelta or 1)) % totalPages) + 1
    local nextIdx = (nextPage - 1) * PAGE_SIZE + 1
    SelectToastIndex(math.min(total, nextIdx))
end

local function BuildToastNavBar(f)
    local navBar = CreateFrame("Frame", nil, f)
    navBar:SetHeight(NAV_H)
    navBar:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -3)
    navBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -46, -3)
    navBar:SetFrameLevel(math.max((f:GetFrameLevel() or 180) + 10, 190))
    if navBar.SetClipsChildren then
        navBar:SetClipsChildren(true)
    end

    local bg = navBar:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAllPoints()
    navBar.bg = bg

    local div = navBar:CreateTexture(nil, "BORDER", nil, 1)
    div:SetHeight(1)
    div:SetPoint("BOTTOMLEFT", navBar, "BOTTOMLEFT", 0, 0)
    div:SetPoint("BOTTOMRIGHT", navBar, "BOTTOMRIGHT", 0, 0)
    navBar.div = div

    navBar:EnableMouse(true)
    navBar:EnableMouseWheel(true)
    navBar:SetScript("OnMouseWheel", function(_, delta)
        CycleToastNotification(delta > 0 and -1 or 1)
    end)
    navBar:SetScript("OnEnter", function(selfBar)
        if GameTooltip and selfBar._totalCount and selfBar._totalCount > 1 then
            GameTooltip:SetOwner(selfBar, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(string.format(L["Notification %d of %d"], selfBar._activeIdx or 1, selfBar._totalCount), 1, 0.85, 0.35)
            GameTooltip:AddLine(L["Left-click: Open  |  Right-click: Options  |  Wheel: Cycle"], 0.80, 0.85, 0.92, true)
            GameTooltip:Show()
        end
    end)
    navBar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local function makeNavArrowBtn(w, text, tipText, onClickFn)
        local b = Theme:CreateButton(navBar, w, 17, text, "default")
        b:RegisterForClicks("AnyUp")
        b:SetScript("OnClick", onClickFn)
        b:SetScript("OnEnter", function(selfBtn)
            if GameTooltip then
                GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
                GameTooltip:SetText(tipText, 1, 0.9, 0.55)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        return b
    end

    navBar.prevPageBtn = makeNavArrowBtn(22, "<<", L["Previous notifications page"], function()
        CycleToastPage(-1)
    end)
    navBar.prevBtn = makeNavArrowBtn(20, "<", L["Previous notification"], function()
        CycleToastNotification(-1)
    end)

    local numBtns = {}
    for i = 1, MAX_NAV_NUMS do
        local b = Theme:CreateButton(navBar, 23, 17, tostring(i), "default")
        b:RegisterForClicks("AnyUp")
        local pip = b:CreateTexture(nil, "OVERLAY", nil, 4)
        pip:SetHeight(2)
        pip:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 1)
        pip:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 1)
        pip:SetColorTexture(0.98, 0.80, 0.24, 0.95)
        b._kindPip = pip
        b:SetScript("OnClick", function(selfBtn)
            if selfBtn._targetIdx then
                SelectToastIndex(selfBtn._targetIdx)
            end
        end)
        b:SetScript("OnEnter", function(selfBtn)
            local idx = selfBtn._targetIdx
            if not (idx and GameTooltip) then return end
            local cand = selfBtn._entryItem
            local streamerOn = Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            local src = (cand and cand.sourceTag) or selfBtn._entrySource or "SocialCentral"
            if streamerOn and cand and cand.kind == "ROOM" then
                src = L["Private Room"]
            end
            local sender = tostring((cand and cand.sender) or selfBtn._entrySender or "?")
            if streamerOn and ((cand and (cand.bnetAccountID ~= nil or cand.kind == "BN_WHISPER")) or sender:find("#", 1, true)) and Compat.MaskStreamerBNetName then
                sender = Compat.MaskStreamerBNetName(sender)
            end
            local clsHex = (cand and cand.senderClass and Compat and Compat.ClassHex) and Compat.ClassHex(cand.senderClass) or "|cffffffff"
            GameTooltip:AddLine(string.format("#%d · [%s] %s%s|r", idx, src, clsHex, sender), 1, 0.88, 0.38)
            local bodyTxt = tostring((cand and cand.text) or selfBtn._entryText or "")
            local cKind = cand and cand.kind
            if streamerOn and (cKind == "DIRECT" or cKind == "ROOM" or cKind == "INVITE" or cKind == "WHISPER" or cKind == "BN_WHISPER" or cKind == "RMI") then
                bodyTxt = L["[Hidden in Streamer Mode]"]
            elseif cKind == "RMI" and bodyTxt ~= "" then
                bodyTxt = string.format(L["Invite to room: %s"], bodyTxt)
            end
            if bodyTxt ~= "" then
                GameTooltip:AddLine(bodyTxt, 0.88, 0.92, 0.96, true)
            end
            GameTooltip:AddLine(string.format(L["Click to view notification #%d"], idx), 0.65, 0.75, 0.88, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        b:Hide()
        numBtns[i] = b
    end
    navBar.numBtns = numBtns

    navBar.nextBtn = makeNavArrowBtn(20, ">", L["Next notification"], function()
        CycleToastNotification(1)
    end)
    navBar.nextPageBtn = makeNavArrowBtn(22, ">>", L["Next notifications page"], function()
        CycleToastPage(1)
    end)

    local countFs = navBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if Theme and Theme.ApplyReadableCounterFont then
        Theme:ApplyReadableCounterFont(countFs, 13, 15, -1, true)
    end
    countFs:SetPoint("RIGHT", navBar, "RIGHT", -4, 0)
    countFs:SetJustifyH("RIGHT")
    navBar.countFs = countFs

    navBar:HookScript("OnDragStart", function()
        PrepareToastDragStart(f)
    end)

    if Theme and Theme.AttachDragHandle and Toast.anchorFrame then
        Theme:AttachDragHandle(navBar, Toast.anchorFrame)
    end

    navBar:Hide()
    return navBar
end

local function UpdateToastNavBar(f, allItems, activeIdx, totalCount, p)
    local navBar = f and f.navBar
    if not navBar or not totalCount or totalCount <= 1 then
        if navBar then
            navBar._activeIdx = nil
            navBar._totalCount = nil
            navBar:Hide()
        end
        return false
    end

    local idx = math.max(1, math.min(activeIdx or 1, totalCount))
    navBar._activeIdx = idx
    navBar._totalCount = totalCount

    if navBar._lastCountActive ~= idx or navBar._lastCountTotal ~= totalCount then
        navBar._lastCountActive = idx
        navBar._lastCountTotal = totalCount
        navBar.countFs:SetText(string.format("%d/%d", idx, totalCount))
    end

    local paged = (totalCount > MAX_NAV_NUMS)
    local curPage = paged and (math.floor((idx - 1) / PAGE_SIZE) + 1) or 1
    local startIdx = paged and ((curPage - 1) * PAGE_SIZE + 1) or 1
    local maxSlots = paged and PAGE_SIZE or MAX_NAV_NUMS
    local visibleCount = math.min(maxSlots, totalCount - startIdx + 1)
    if visibleCount < 1 then visibleCount = 1 end

    local prevAnchor
    local layoutDirty = (navBar._lastPaged ~= paged) or (navBar._lastVisCount ~= visibleCount)
    if layoutDirty then
        navBar._lastPaged = paged
        navBar._lastVisCount = visibleCount

        navBar.prevPageBtn:ClearAllPoints()
        if paged then
            navBar.prevPageBtn:SetPoint("LEFT", navBar, "LEFT", 3, 1)
            navBar.prevPageBtn:Show()
            prevAnchor = navBar.prevPageBtn
        else
            navBar.prevPageBtn:Hide()
        end

        navBar.prevBtn:ClearAllPoints()
        if prevAnchor then
            navBar.prevBtn:SetPoint("LEFT", prevAnchor, "RIGHT", 2, 0)
        else
            navBar.prevBtn:SetPoint("LEFT", navBar, "LEFT", 3, 1)
        end
        prevAnchor = navBar.prevBtn
    else
        prevAnchor = navBar.prevBtn
    end

    for i = 1, MAX_NAV_NUMS do
        local btn = navBar.numBtns[i]
        if i <= visibleCount then
            local tIdx = startIdx + i - 1
            local cand = allItems and allItems[tIdx] or nil
            local wantW = (tIdx >= 100) and 25 or 23
            local isActive = (tIdx == idx)
            local gradKey = (cand and cand.avoidWarning and "SCOUT") or (cand and cand.kind) or "DIRECT"
            local kRgb = KIND_RGB[gradKey] or KIND_RGB.DIRECT

            if layoutDirty or btn._lastLeftAnchor ~= prevAnchor then
                btn._lastLeftAnchor = prevAnchor
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", prevAnchor, "RIGHT", 2, 0)
            end
            if btn._lastWidth ~= wantW then
                btn._lastWidth = wantW
                btn:SetWidth(wantW)
            end
            if btn._targetIdx ~= tIdx then
                btn._targetIdx = tIdx
                Theme:SetButtonText(btn, tostring(tIdx))
            end
            if btn._isActive ~= isActive or btn._activePalKey ~= (p and p.key or "dark") then
                btn._isActive = isActive
                btn._activePalKey = p and p.key or "dark"
                Theme:StyleButton(btn, isActive and "primary" or "default")
                Theme:SetButtonActive(btn, isActive, isActive and "primary" or "default")
            end
            btn._kindPip:SetColorTexture(kRgb[1], kRgb[2], kRgb[3], isActive and 1.0 or 0.72)
            btn._entryItem = cand
            btn._entrySource = cand and cand.sourceTag or "SocialCentral"
            btn._entrySender = cand and cand.sender or "?"
            btn._entryText = cand and cand.text or ""
            if not btn:IsShown() then
                btn:Show()
            end
            prevAnchor = btn
        else
            btn._targetIdx = nil
            btn._entryItem = nil
            btn._entrySource = nil
            btn._entrySender = nil
            btn._entryText = nil
            if btn:IsShown() then
                btn:Hide()
            end
        end
    end

    if layoutDirty or navBar._lastNextAnchor ~= prevAnchor then
        navBar._lastNextAnchor = prevAnchor
        navBar.nextBtn:ClearAllPoints()
        navBar.nextBtn:SetPoint("LEFT", prevAnchor, "RIGHT", 2, 0)

        navBar.nextPageBtn:ClearAllPoints()
        if paged then
            navBar.nextPageBtn:SetPoint("LEFT", navBar.nextBtn, "RIGHT", 2, 0)
            navBar.nextPageBtn:Show()
        else
            navBar.nextPageBtn:Hide()
        end
    end

    navBar:Show()
    return true
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

    -- Left 3px vertical category accent strip matching the compact Target HUD pill
    local leftBar = f:CreateTexture(nil, "OVERLAY", nil, 2)
    leftBar:SetWidth(3)
    leftBar:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
    leftBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 3, 3)
    leftBar:SetColorTexture(0.28, 0.85, 0.62, 1.0)
    f.leftBar = leftBar

    -- Soft horizontal category ambient wash radiating softly from the emblem
    local bgAmbient = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    bgAmbient:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    bgAmbient:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    f.bgAmbient = bgAmbient

    -- Crisp header tint band for clear visual hierarchy
    local headerWash = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    headerWash:SetHeight(20)
    headerWash:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    headerWash:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    f.headerWash = headerWash

    -- Brief additive arrival sheen (fades out over 0.35s on spawn)
    local arrivalSheen = f:CreateTexture(nil, "ARTWORK", nil, 3)
    arrivalSheen:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    arrivalSheen:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    arrivalSheen:SetTexture(ICON_GLOW)
    arrivalSheen:SetBlendMode("ADD")
    arrivalSheen:SetVertexColor(1, 1, 1, 0)
    arrivalSheen:Hide()
    f.arrivalSheen = arrivalSheen

    -- Subtle inner top metallic bevel
    local topBevel = f:CreateTexture(nil, "BORDER", nil, 1)
    topBevel:SetHeight(1)
    topBevel:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -3)
    topBevel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -3)
    topBevel:SetColorTexture(1, 0.90, 0.68, 0.16)
    f.topBevel = topBevel

    local hoverHighlight = f:CreateTexture(nil, "HIGHLIGHT")
    hoverHighlight:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
    hoverHighlight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    hoverHighlight:SetColorTexture(1, 0.94, 0.78, 0.06)

    f.navBar = BuildToastNavBar(f)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        CycleToastNotification(delta > 0 and -1 or 1)
    end)

    -- Heraldic Circular Emblem on Left (x = 11..47)
    local iconBadge = CreateFrame("Frame", nil, f)
    iconBadge:SetSize(36, 36)
    iconBadge:SetPoint("TOPLEFT", f, "TOPLEFT", 11, -10)
    iconBadge:EnableMouse(false)
    f.iconBadge = iconBadge

    local iconHalo = iconBadge:CreateTexture(nil, "BACKGROUND", nil, 1)
    iconHalo:SetSize(50, 50)
    iconHalo:SetPoint("CENTER")
    iconHalo:SetTexture(ICON_GLOW)
    iconHalo:SetVertexColor(0.35, 0.75, 1.0, 0.38)
    f.iconHalo = iconHalo

    local iconRing = iconBadge:CreateTexture(nil, "ARTWORK", nil, 0)
    iconRing:SetSize(36, 36)
    iconRing:SetPoint("CENTER")
    iconRing:SetTexture(WHITE8X8)
    iconRing:SetVertexColor(0.35, 0.75, 1.0, 0.92)
    ApplyCircleMask(iconBadge, iconRing, 36)
    f.iconRing = iconRing

    local iconCore = iconBadge:CreateTexture(nil, "ARTWORK", nil, 1)
    iconCore:SetSize(32, 32)
    iconCore:SetPoint("CENTER")
    iconCore:SetTexture(WHITE8X8)
    iconCore:SetVertexColor(0.06, 0.08, 0.12, 1.0)
    ApplyCircleMask(iconBadge, iconCore, 32)

    local iconTex = iconBadge:CreateTexture(nil, "OVERLAY", nil, 2)
    iconTex:SetSize(26, 26)
    iconTex:SetPoint("CENTER")
    iconTex:SetTexture(ICON_DEFAULT)
    ApplyCircleMask(iconBadge, iconTex, 26)
    f.iconTex = iconTex

    local closeBtn = Theme:CreateButton(f, 18, 18, "X", "default")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeBtn:SetFrameLevel(f:GetFrameLevel() + 10)
    closeBtn:SetHitRectInsets(-1, -4, -4, -2)
    closeBtn:SetScript("OnClick", function()
        if f.itemData then
            Toast:DismissItem(f.itemData)
        end
    end)
    f.closeBtn = closeBtn

    if Theme and Theme.CreateHelpButton then
        local helpBtn = Theme:CreateHelpButton(
            f,
            L["Floating Notifications & Pagination"],
            L["Notification Toasts appear beside your Minimap or chat window showing 1 alert at a time so your screen stays clean. Each notification disappears automatically after %ds (configurable in Settings -> Notifications)."]:format(math.floor(GetConfiguredToastDuration() + 0.5)),
            L["Quick Actions: Left-click to open, hover to pause the countdown, drag to reposition anywhere, or right-click / click the bell to silence."],
            18,
            { target = f }
        )
        helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
        helpBtn:SetFrameLevel(f:GetFrameLevel() + 10)
        helpBtn:SetScript("OnClick", function()
            if GameTooltip then GameTooltip:Hide() end
            Toast:ShowTutorial(true)
        end)
        f.helpBtn = helpBtn
    end

    local muteNotifBtn = Theme:CreateButton(f, 18, 18, "", "default")
    muteNotifBtn:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
    muteNotifBtn:SetFrameLevel(f:GetFrameLevel() + 10)
    muteNotifBtn:SetHitRectInsets(-3, -3, -4, -4)
    local muteIco = muteNotifBtn:CreateTexture(nil, "OVERLAY")
    muteIco:SetSize(15, 15)
    muteIco:SetPoint("CENTER")
    muteIco:SetTexture(ICON_BELL_OFF)
    muteIco:SetVertexColor(0.95, 0.72, 0.35)
    muteNotifBtn.ico = muteIco
    muteNotifBtn:SetScript("OnClick", function()
        if f.itemData then
            Toast:ShowConfirmDisablePopup(f, f.itemData)
        end
    end)
    muteNotifBtn:SetScript("OnEnter", function(selfBtn)
        if GameTooltip then
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
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

    local markReadBtn = Theme:CreateButton(f, 26, 18, L["ok"], "default")
    Theme:AutoFitButton(markReadBtn, 26, 10, 54)
    markReadBtn:SetPoint("RIGHT", muteNotifBtn, "LEFT", -3, 0)
    markReadBtn:SetFrameLevel(f:GetFrameLevel() + 10)
    markReadBtn:SetScript("OnClick", function()
        local cur = f.itemData
        if cur then
            if cur.threadKey and ns.Chat and ns.Chat.MarkThreadRead then
                ns.Chat:MarkThreadRead(cur.threadKey)
            end
            Toast:DismissItem(cur)
        end
    end)
    markReadBtn:SetScript("OnEnter", function(selfBtn)
        if GameTooltip then
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:SetText(L["Mark Read"])
            GameTooltip:Show()
        end
    end)
    markReadBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    markReadBtn:Hide()
    f.markReadBtn = markReadBtn

    -- Left-aligned text stack directly beside circular emblem
    local titleLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 54, -8)
    titleLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -8)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetWordWrap(false)
    f.titleLbl = titleLbl

    local titleRule = f:CreateTexture(nil, "BORDER", nil, 2)
    titleRule:SetHeight(1)
    titleRule:SetPoint("TOPLEFT", f, "TOPLEFT", 54, -23)
    titleRule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -23)
    f.titleRule = titleRule

    local bodyLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bodyLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 54, -27)
    bodyLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -27)
    bodyLbl:SetJustifyH("LEFT")
    bodyLbl:SetWordWrap(true)
    if bodyLbl.SetSpacing then
        bodyLbl:SetSpacing(2)
    end
    if bodyLbl.SetMaxLines then
        bodyLbl:SetMaxLines(3)
    end
    f.bodyLbl = bodyLbl

    local actionRow = CreateFrame("Frame", nil, f)
    actionRow:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 54, 9)
    actionRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 9)
    actionRow:SetHeight(22)
    actionRow:SetFrameLevel(f:GetFrameLevel() + 8)
    actionRow:Hide()
    f.actionRow = actionRow

    local acceptBtn = Theme:CreateButton(actionRow, 82, 20, L["Accept"], "primary")
    Theme:AutoFitButton(acceptBtn, 72, 12, 108)
    acceptBtn:SetPoint("LEFT", actionRow, "LEFT", 0, 0)
    acceptBtn:SetFrameLevel(f:GetFrameLevel() + 10)
    acceptBtn:RegisterForClicks("LeftButtonUp")
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

    local declineBtn = Theme:CreateButton(actionRow, 82, 20, L["Decline"], "default")
    Theme:AutoFitButton(declineBtn, 72, 12, 108)
    declineBtn:SetPoint("LEFT", acceptBtn, "RIGHT", 6, 0)
    declineBtn:SetFrameLevel(f:GetFrameLevel() + 10)
    declineBtn:RegisterForClicks("LeftButtonUp")
    declineBtn:SetScript("OnClick", function()
        local item = f.itemData
        if item and item.roomId and item.roomId ~= "test-room-preview" and ns.Chat and ns.Chat.DeclineRoomInvite then
            ns.Chat:DeclineRoomInvite(item.roomId)
        end
        Toast:DismissItem(item)
    end)
    f.declineBtn = declineBtn

    local buffAnnounceBtn = Theme:CreateButton(actionRow, 146, 20, L["Post in Chat"], "primary")
    Theme:AutoFitButton(buffAnnounceBtn, 120, 16, 210)
    buffAnnounceBtn:SetPoint("LEFT", actionRow, "LEFT", 0, 0)
    buffAnnounceBtn:SetFrameLevel(f:GetFrameLevel() + 10)
    buffAnnounceBtn:EnableMouse(true)
    buffAnnounceBtn:RegisterForClicks("LeftButtonUp")
    buffAnnounceBtn:SetScript("OnClick", function()
        local item = f.itemData
        if item and item.kind == "CLAN_LFG" then
            if ns.LFGFrameTab and ns.LFGFrameTab.QuickApplyToPlayer then
                ns.LFGFrameTab:QuickApplyToPlayer(item.sender, item.lookupKey, item.activity)
            end
            Toast:DismissItem(item)
            return
        end
        if item then
            Toast:DismissItem(item)
        end
    end)
    buffAnnounceBtn:Hide()
    f.buffAnnounceBtn = buffAnnounceBtn

    -- Clean edge-to-edge 2px bottom progress hairline
    local progressTrack = f:CreateTexture(nil, "BORDER", nil, 2)
    progressTrack:SetHeight(2)
    progressTrack:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 3)
    progressTrack:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 3)
    progressTrack:SetColorTexture(0.05, 0.06, 0.09, 0.85)
    f.progressTrack = progressTrack

    local progressFill = f:CreateTexture(nil, "OVERLAY", nil, 1)
    progressFill:SetHeight(2)
    progressFill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 3)
    progressFill:SetWidth(TOAST_WIDTH - 8)
    f.progressFill = progressFill

    local progressTip = f:CreateTexture(nil, "OVERLAY", nil, 3)
    progressTip:SetSize(8, 6)
    progressTip:SetPoint("CENTER", progressFill, "RIGHT", 0, 0)
    progressTip:SetTexture(ICON_GLOW)
    progressTip:SetBlendMode("ADD")
    progressTip:SetVertexColor(1.0, 0.94, 0.72, 0.85)
    f.progressTip = progressTip

    f:SetScript("OnClick", function(self, mouseButton)
        if Toast.anchorFrame and (Toast.anchorFrame._scDragging or (Toast.anchorFrame._scJustDraggedAt and GetTime and (GetTime() - Toast.anchorFrame._scJustDraggedAt) < 0.25)) then
            return
        end
        local curItem = self.itemData
        if not curItem then return end
        if mouseButton == "RightButton" then
            if MenuUtil and MenuUtil.CreateContextMenu then
                local menuSender = tostring(curItem.sender or "SocialCentral")
                if Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()
                    and (curItem.bnetAccountID ~= nil or curItem.kind == "BN_WHISPER" or menuSender:find("#", 1, true))
                    and Compat.MaskStreamerBNetName
                then
                    menuSender = Compat.MaskStreamerBNetName(menuSender)
                end
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(menuSender)
                    if curItem.kind ~= "RMI" then
                        root:CreateButton(L["Open"], function()
                            Toast:DismissItem(curItem)
                            NavigateForItem(curItem)
                        end)
                    end
                    if curItem.threadKey and ns.Chat and ns.Chat.MarkThreadRead then
                        root:CreateButton(L["Mark Read"], function()
                            ns.Chat:MarkThreadRead(curItem.threadKey)
                            Toast:DismissItem(curItem)
                        end)
                    end
                    if curItem.threadKey and ns.Chat and (ns.Chat.PopulateThreadMuteMenu or ns.Chat.ToggleThreadMuted) then
                        root:CreateDivider()
                        if ns.Chat.PopulateThreadMuteMenu then
                            local muteSub = root:CreateButton(L["Silence Notifications"])
                            ns.Chat:PopulateThreadMuteMenu(muteSub, curItem.threadKey, menuSender, function(mutedNow)
                                if mutedNow then
                                    Toast:DismissItem(curItem)
                                end
                            end)
                        else
                            local isMuted = ns.Chat.IsThreadMuted and ns.Chat:IsThreadMuted(curItem.threadKey)
                            root:CreateButton(isMuted and L["Unmute Conversation"] or L["Mute Conversation"], function()
                                ns.Chat:ToggleThreadMuted(curItem.threadKey)
                                Toast:DismissItem(curItem)
                            end)
                        end
                    end
                    root:CreateDivider()
                    local posSub = root:CreateButton(L["Notification & Preview Position"])
                    if posSub and posSub.CreateRadio then
                        for _, opt in ipairs({
                            { id = "minimap", label = L["Beside Minimap"] },
                            { id = "chat_side", label = L["Beside Official Chat"] },
                            { id = "chat_top", label = L["Above Official Chat"] },
                        }) do
                            posSub:CreateRadio(opt.label, function()
                                return GetToastAnchorMode() == opt.id
                            end, function()
                                if ns.Minimap and ns.Minimap.SetPreviewAnchorMode then
                                    ns.Minimap:SetPreviewAnchorMode(opt.id)
                                end
                            end)
                        end
                    end
                    root:CreateButton(L["Reset Position"], function()
                        if Theme and Theme.ResetWindowPosition then
                            Theme:ResetWindowPosition("notification_toast")
                        end
                    end)
                    root:CreateButton(L["Configure Notifications..."], function()
                        if ns.Settings and ns.Settings.Open then
                            ns.Settings:Open("notifications", "toast")
                        end
                    end)
                    if curItem.kind ~= "FOCUS_SUMMARY" then
                        root:CreateButton(L["Silence this notification"], function()
                            Toast:ShowConfirmDisablePopup(self, curItem)
                        end)
                    end
                    root:CreateDivider()
                    root:CreateButton(L["Dismiss"], function()
                        Toast:DismissItem(curItem)
                    end)
                end)
                return
            end
            Toast:DismissItem(curItem)
            return
        end
        if curItem.kind ~= "RMI" then
            Toast:DismissItem(curItem)
        end
        NavigateForItem(curItem)
    end)

    f:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        local cur = self.itemData
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        if cur then
            local gradKey = (cur.avoidWarning and "SCOUT") or cur.kind or "DIRECT"
            local rgb = KIND_RGB[gradKey] or KIND_RGB.DIRECT
            local streamerOn = Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()
            local hex = (cur.senderClass and Compat and Compat.ClassHex) and Compat.ClassHex(cur.senderClass) or "|cffffffff"
            local senderDisp = tostring(cur.sender or "?")
            if streamerOn and (cur.bnetAccountID ~= nil or cur.kind == "BN_WHISPER" or senderDisp:find("#", 1, true)) then
                senderDisp = Compat.MaskStreamerBNetName(senderDisp)
            end
            local tipSrc = tostring(cur.sourceTag or "SocialCentral")
            if streamerOn and cur.kind == "ROOM" then
                tipSrc = L["Private Room"]
            end
            GameTooltip:AddDoubleLine(hex .. senderDisp .. "|r", tipSrc, 1, 1, 1, rgb[1], rgb[2], rgb[3])
            local rawBody = tostring(cur.text or "")
            if streamerOn and (cur.kind == "DIRECT" or cur.kind == "ROOM" or cur.kind == "INVITE" or cur.kind == "WHISPER" or cur.kind == "BN_WHISPER" or cur.kind == "RMI") then
                rawBody = L["[Hidden in Streamer Mode]"]
            elseif cur.kind == "RMI" then
                rawBody = string.format(L["Invite to room: %s"], rawBody)
            end
            if rawBody ~= "" then
                GameTooltip:AddLine(rawBody, 0.94, 0.96, 0.99, true)
            end
            GameTooltip:AddLine(" ")
        end
        GameTooltip:AddLine(GetToastTooltipHint(cur), 0.72, 0.78, 0.86, true)
        GameTooltip:Show()
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
        PrepareToastDragStart(self)
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

local function RenderItemOnFrame(f, item, showNav)
    if not f or not item then return end
    f.itemData = item

    local isInvite = (item.kind == "RMI" and item.roomId and item.roomId ~= "")
    local isLfgAction = (item.kind == "CLAN_LFG" and item.sender and item.sender ~= "")
    local hasActionRow = isInvite or isLfgAction
    local navOffset = showNav and NAV_H or 0
    f:SetWidth(TOAST_WIDTH)

    local gradKey = (item.avoidWarning and "SCOUT") or item.kind or "DIRECT"
    local rgb = KIND_RGB[gradKey] or KIND_RGB.DIRECT
    f._kindRgb = rgb

    if f._lastGradKind ~= gradKey then
        f._lastGradKind = gradKey
        if f.leftBar then
            f.leftBar:SetColorTexture(rgb[1], rgb[2], rgb[3], 1.0)
        end
        if f.bgAmbient then
            ApplyTexGradient(f.bgAmbient, "HORIZONTAL", rgb[1] * 0.24, rgb[2] * 0.24, rgb[3] * 0.24, 0.58, rgb[1] * 0.10, rgb[2] * 0.10, rgb[3] * 0.10, 0.22)
        end
        if f.headerWash then
            ApplyTexGradient(f.headerWash, "HORIZONTAL", rgb[1] * 0.34, rgb[2] * 0.34, rgb[3] * 0.34, 0.42, rgb[1] * 0.12, rgb[2] * 0.12, rgb[3] * 0.12, 0.08)
        end
        if f.titleRule then
            ApplyTexGradient(f.titleRule, "HORIZONTAL", rgb[1] * 0.7 + 0.25, rgb[2] * 0.7 + 0.25, rgb[3] * 0.7 + 0.25, 0.52, rgb[1], rgb[2], rgb[3], 0.0)
        end
        if f.iconHalo then
            f.iconHalo:SetVertexColor(rgb[1], rgb[2], rgb[3], 0.38)
        end
        if f.progressFill then
            ApplyTexGradient(f.progressFill, "HORIZONTAL", rgb[1] * 0.65, rgb[2] * 0.65, rgb[3] * 0.65, 0.90, math.min(1, rgb[1] + 0.25), math.min(1, rgb[2] + 0.25), math.min(1, rgb[3] + 0.25), 1.0)
        end
        if f.progressTip then
            f.progressTip:SetVertexColor(math.min(1, rgb[1] + 0.30), math.min(1, rgb[2] + 0.30), math.min(1, rgb[3] + 0.30), 0.90)
        end
    end
    if f.iconRing then
        local ringR, ringG, ringB = rgb[1], rgb[2], rgb[3]
        if item.senderClass and Compat and Compat.ClassColor then
            local cr, cg, cb = Compat.ClassColor(item.senderClass)
            if cr and cg and cb then
                ringR, ringG, ringB = cr, cg, cb
            end
        end
        f.iconRing:SetVertexColor(ringR, ringG, ringB, 0.94)
    end
    local customTex = (type(item.customIcon) == "string" or type(item.customIcon) == "number") and item.customIcon or nil
    local clsCoords = (not customTex) and item.senderClass and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[item.senderClass] or nil
    local iconKey = tostring(item.kind or "DIRECT") .. ":" .. tostring(customTex or (clsCoords and ("cls:" .. tostring(item.senderClass)) or ""))
    if f._lastIconKind ~= iconKey then
        f._lastIconKind = iconKey
        if f.iconTex then
            if customTex then
                f.iconTex:SetTexture(customTex)
                f.iconTex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
            elseif clsCoords then
                f.iconTex:SetTexture(ICON_CLASS_CREST)
                f.iconTex:SetTexCoord(clsCoords[1] + 0.025, clsCoords[2] - 0.025, clsCoords[3] + 0.025, clsCoords[4] - 0.025)
            else
                f.iconTex:SetTexture(ResolveIconForKind(item.kind))
                f.iconTex:SetTexCoord(0, 1, 0, 1)
            end
        end
    end
    if f.arrivalSheen then
        local el = item.elapsed or 0
        if el < 0.35 then
            f.arrivalSheen:SetVertexColor(rgb[1] * 0.5 + 0.5, rgb[2] * 0.5 + 0.5, rgb[3] * 0.5 + 0.5, (1 - (el / 0.35)) * 0.24)
            f.arrivalSheen:Show()
        else
            f.arrivalSheen:Hide()
        end
    end

    local cfgDur = GetConfiguredToastDuration()
    local totalDur = math.max(cfgDur, tonumber(item.minDuration) or 0)
    item.totalDuration = totalDur
    if f.helpBtn and Theme and Theme.SetHelpButtonInfo and f._lastHelpDur ~= cfgDur then
        f._lastHelpDur = cfgDur
        Theme:SetHelpButtonInfo(
            f.helpBtn,
            L["Floating Notifications & Pagination"],
            L["Notification Toasts appear beside your Minimap or chat window showing 1 alert at a time so your screen stays clean. Each notification disappears automatically after %ds (configurable in Settings -> Notifications)."]:format(math.floor(cfgDur + 0.5)),
            L["Quick Actions: Left-click to open, hover to pause the countdown, drag to reposition anywhere, or right-click / click the bell to silence."],
            { target = f }
        )
    end
    if f.progressFill then
        local remainingFrac = math.max(0, 1 - ((item.elapsed or 0) / totalDur))
        local newW = math.max(1, (TOAST_WIDTH - 8) * remainingFrac)
        if f._lastProgressW ~= newW then
            f._lastProgressW = newW
            f.progressFill:SetWidth(newW)
        end
    end

    local streamerOn = Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()
    local sourceTag = item.sourceTag or "SocialCentral"
    if streamerOn and item.kind == "ROOM" then
        sourceTag = L["Private Room"]
    end
    local hex = (item.senderClass and Compat and Compat.ClassHex) and Compat.ClassHex(item.senderClass) or "|cffffffff"
    local senderRaw = tostring(item.sender or "?")
    if streamerOn and (item.bnetAccountID ~= nil or item.kind == "BN_WHISPER" or senderRaw:find("#", 1, true)) then
        senderRaw = Compat.MaskStreamerBNetName(senderRaw)
    end
    local senderText = hex .. senderRaw .. "|r"
    local mult = (item.coalescedCount and item.coalescedCount > 1) and (" |cff9da7b5(x" .. tostring(item.coalescedCount) .. ")|r") or ""
    f.titleLbl:SetText(string.format("|cff%02x%02x%02x%s|r  ·  %s%s", math.floor(rgb[1] * 255), math.floor(rgb[2] * 255), math.floor(rgb[3] * 255), sourceTag, senderText, mult))

    local bodyText = tostring(item.text or "")
    if streamerOn and (item.kind == "DIRECT" or item.kind == "ROOM" or item.kind == "INVITE" or item.kind == "WHISPER" or item.kind == "BN_WHISPER" or item.kind == "RMI") then
        bodyText = "|cff9da7b5" .. L["[Hidden in Streamer Mode]"] .. "|r"
    elseif isInvite then
        bodyText = string.format(L["Invite to room: %s"], bodyText)
    elseif item.countdownUntil then
        local remSec = math.max(0, math.ceil(item.countdownUntil - (GetTime and GetTime() or 0)))
        item._lastShownSec = remSec
        bodyText = (remSec > 0) and L["Dropping in ~%ds!"]:format(remSec) or L["World Buff should be active now!"]
    end
    f.bodyLbl:SetText(bodyText)

    local canMuteItem = (item.kind ~= "FOCUS_SUMMARY")
    local showQuickRead = (not hasActionRow) and item.threadKey and item.threadKey ~= "" and ns.Chat and ns.Chat.MarkThreadRead
    local layoutSig = tostring(showNav) .. ":" .. tostring(canMuteItem) .. ":" .. tostring(showQuickRead == true) .. ":" .. tostring(hasActionRow)
    if f._layoutSig ~= layoutSig then
        f._layoutSig = layoutSig
        if f.iconBadge then
            f.iconBadge:ClearAllPoints()
            f.iconBadge:SetPoint("TOPLEFT", f, "TOPLEFT", 11, -(9 + navOffset))
        end
        if f.closeBtn then
            f.closeBtn:ClearAllPoints()
            f.closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -4)
        end
        local topAnchorRight = f.helpBtn or f.closeBtn
        if f.muteNotifBtn then
            f.muteNotifBtn:SetShown(canMuteItem)
            f.muteNotifBtn:ClearAllPoints()
            if showNav then
                f.muteNotifBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -(4 + navOffset))
            else
                f.muteNotifBtn:SetPoint("RIGHT", topAnchorRight, "LEFT", -3, 0)
            end
        end
        if f.markReadBtn then
            f.markReadBtn:ClearAllPoints()
            if canMuteItem and f.muteNotifBtn then
                f.markReadBtn:SetPoint("RIGHT", f.muteNotifBtn, "LEFT", -3, 0)
            elseif showNav then
                f.markReadBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -(4 + navOffset))
            else
                f.markReadBtn:SetPoint("RIGHT", topAnchorRight, "LEFT", -3, 0)
            end
            f.markReadBtn:SetShown(showQuickRead == true)
        end
        if f.headerWash then
            f.headerWash:ClearAllPoints()
            f.headerWash:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -(4 + navOffset))
            f.headerWash:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -(4 + navOffset))
        end

        local rightPad = showNav and (canMuteItem and -29 or -8) or (canMuteItem and -70 or -48)
        if showQuickRead then
            local mrW = math.ceil((f.markReadBtn and (f.markReadBtn._scAutoFitW or f.markReadBtn:GetWidth())) or 26)
            rightPad = rightPad - (mrW + 5)
        end
        f.titleLbl:ClearAllPoints()
        f.titleLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 55, -(8 + navOffset))
        f.titleLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", rightPad, -(8 + navOffset))

        if f.titleRule then
            f.titleRule:ClearAllPoints()
            f.titleRule:SetPoint("TOPLEFT", f, "TOPLEFT", 55, -(23 + navOffset))
            f.titleRule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -(23 + navOffset))
        end
        if f.bodyLbl then
            f.bodyLbl:ClearAllPoints()
            f.bodyLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 55, -(26 + navOffset))
            f.bodyLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -(26 + navOffset))
        end
    end

    local measuredBodyH = (f.bodyLbl.GetStringHeight and f.bodyLbl:GetStringHeight()) or 13
    local minH = (hasActionRow and TOAST_H_INVITE or TOAST_H_DEFAULT) + navOffset
    local bottomReserve = hasActionRow and 37 or 11
    local finalH = math.max(minH, math.ceil(27 + navOffset + measuredBodyH + bottomReserve))
    if f._lastToastH ~= finalH then
        f._lastToastH = finalH
        f:SetSize(TOAST_WIDTH, finalH)
    end

    if isInvite then
        Theme:SetButtonText(f.acceptBtn, L["Accept"])
        Theme:AutoFitButton(f.acceptBtn, 72, 12, 108)
        f.acceptBtn:ClearAllPoints()
        f.acceptBtn:SetPoint("LEFT", f.actionRow, "LEFT", 0, 0)
        f.acceptBtn:Show()
        Theme:SetButtonText(f.declineBtn, L["Decline"])
        Theme:AutoFitButton(f.declineBtn, 72, 12, 108)
        f.declineBtn:ClearAllPoints()
        f.declineBtn:SetPoint("LEFT", f.acceptBtn, "RIGHT", 6, 0)
        f.declineBtn:Show()
        if f.buffAnnounceBtn then f.buffAnnounceBtn:Hide() end
        f.actionRow:Show()
    elseif isLfgAction then
        f.acceptBtn:Hide()
        f.declineBtn:Hide()
        if f.buffAnnounceBtn then
            Theme:SetButtonText(f.buffAnnounceBtn, L["Quick Apply (/w)"])
            Theme:AutoFitButton(f.buffAnnounceBtn, 120, 16, 210)
            f.buffAnnounceBtn:Show()
        end
        f.actionRow:Show()
    else
        f.actionRow:Hide()
    end

    ApplyToastThemeToFrame(f)
end

function Toast:SortActiveItems()
    -- Preserve arrival order so pagination (1/N) stays stable and predictable.
end

function Toast:ShowTutorial(forceShow)
    local alreadyShown = (ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("toastTutorialShown"))
        or (ns.db and ns.db.settings and ns.db.settings.toastTutorialShown == true)
    if not forceShow and alreadyShown then
        return
    end
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        self.pendingTutorial = true
        return
    end
    self.pendingTutorial = false
    if ns.SetAccountTutorialShown then
        ns:SetAccountTutorialShown("toastTutorialShown", true)
    elseif ns.db and ns.db.settings then
        ns.db.settings.toastTutorialShown = true
    end
    if not (Theme and Theme.ShowNpcGuide) then
        return
    end
    local function ResolveActiveToastFrame()
        if Toast.framePool then
            for _, f in ipairs(Toast.framePool) do
                if f and f.IsShown and f:IsShown() then
                    return f
                end
            end
        end
        return nil
    end
    local durSecText = math.floor(GetConfiguredToastDuration() + 0.5)
    self.tutorialDialog = Theme:ShowNpcGuide({
        key = "toast",
        doneLabel = L["Got it, don't show again"],
        defaultTarget = ResolveActiveToastFrame,
        steps = {
            {
                title = L["Floating Notifications"],
                text = L["Popups auto-hide in %ds. Click opens · Hover pauses · Drag moves."]:format(durSecText),
            },
            {
                title = L["Quick Controls"],
                text = L["Use < > or mouse wheel to switch alerts. Right-click to mute or adjust."],
            },
        },
    })
end

function Toast:ShowTutorialIfNeeded()
    local alreadyShown = (ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("toastTutorialShown"))
        or (ns.db and ns.db.settings and ns.db.settings.toastTutorialShown == true)
    if alreadyShown then return end
    if Theme and Theme.PromptWindowTutorial then
        local function ResolveActiveToastFrame()
            if Toast.framePool then
                for _, f in ipairs(Toast.framePool) do
                    if f and f.IsShown and f:IsShown() then
                        return f
                    end
                end
            end
            return nil
        end
        local durSecText = math.floor(GetConfiguredToastDuration() + 0.5)
        Theme:PromptWindowTutorial({
            tutorialKey = "toastTutorialShown",
            title = L["Floating Notifications"],
            guideSpec = {
                key = "toast",
                doneLabel = L["Got it, don't show again"],
                defaultTarget = ResolveActiveToastFrame,
                isAnchorVisible = function()
                    return ResolveActiveToastFrame() ~= nil
                end,
                steps = {
                    {
                        title = L["Floating Notifications"],
                        text = L["Popups auto-hide in %ds. Click opens · Hover pauses · Drag moves."]:format(durSecText),
                    },
                    {
                        title = L["Quick Controls"],
                        text = L["Use < > or mouse wheel to switch alerts. Right-click to mute or adjust."],
                    },
                },
            },
            isWindowVisible = function()
                return ResolveActiveToastFrame() ~= nil
            end,
            onSkip = function()
                if ns.SetAccountTutorialShown then
                    ns:SetAccountTutorialShown("toastTutorialShown", true)
                elseif ns.db and ns.db.settings then
                    ns.db.settings.toastTutorialShown = true
                end
            end,
        })
        return
    end
    self:ShowTutorial(false)
end

function Toast:LayoutStack()
    EnsureAnchorFrame()

    while #self.queue > 0 and #self.activeItems < MAX_QUEUE do
        local nextItem = table.remove(self.queue, 1)
        table.insert(self.activeItems, nextItem)
    end

    local totalCount = #self.activeItems
    if totalCount == 0 then
        self.activeIndex = 1
        for _, f in ipairs(self.framePool) do
            f.itemData = nil
            if f.navBar then f.navBar:Hide() end
            f:Hide()
        end
        if self.anchorFrame then
            self.anchorFrame:SetScript("OnUpdate", nil)
        end
        return
    end

    if (self.activeIndex or 1) > totalCount then
        self.activeIndex = totalCount
    elseif (self.activeIndex or 1) < 1 then
        self.activeIndex = 1
    end

    local hudRef = (_G.SocialCentralSpotterFrame and _G.SocialCentralSpotterFrame.IsShown and _G.SocialCentralSpotterFrame:IsShown() and _G.SocialCentralSpotterFrame)
        or (_G.SocialCentralSpotterCombatArrow and _G.SocialCentralSpotterCombatArrow.IsShown and _G.SocialCentralSpotterCombatArrow:IsShown() and _G.SocialCentralSpotterCombatArrow)
        or nil
    local isDragging = self.anchorFrame and self.anchorFrame._scDragging == true
    local hasCustomPos = HasSavedCustomToastPosition()
    local shouldAnchorToHud = false
    if not isDragging and not hasCustomPos and hudRef and self.anchorFrame and self.anchorFrame.GetCenter and hudRef.GetCenter then
        local ax, ay = self.anchorFrame:GetCenter()
        local hx, hy = hudRef:GetCenter()
        if ax and hx and ay and hy and math.abs(ax - hx) < (TOAST_WIDTH * 0.85) and math.abs(ay - hy) < 96 then
            shouldAnchorToHud = true
        end
    end

    local f = self:EnsureFrame(1)
    for idx = 2, #self.framePool do
        local extraF = self.framePool[idx]
        if extraF then
            extraF.itemData = nil
            extraF:Hide()
        end
    end

    local activeIdx = self.activeIndex or 1
    local item = self.activeItems[activeIdx]
    local inCombat = ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) == true
    local sCfg = ns.db and ns.db.settings
    local silenceCombat = (not sCfg) or sCfg.msgPreviewSilenceCombat ~= false
    if inCombat and silenceCombat then
        if item and item.kind ~= "AVOID_ALERT" then
            local avoidIdx = nil
            for i = 1, totalCount do
                local it = self.activeItems[i]
                if it and it.kind == "AVOID_ALERT" then
                    avoidIdx = i
                    break
                end
            end
            if avoidIdx then
                activeIdx = avoidIdx
                self.activeIndex = avoidIdx
                item = self.activeItems[avoidIdx]
            else
                f:Hide()
                if self.anchorFrame then
                    self.anchorFrame:SetScript("OnUpdate", nil)
                end
                return
            end
        end
    end
    local showNav = totalCount > 1

    f:ClearAllPoints()
    if shouldAnchorToHud and hudRef then
        local hudBottom = (hudRef.GetBottom and hudRef:GetBottom()) or 120
        if hudBottom < 92 then
            f:SetPoint("TOPLEFT", hudRef, "TOPRIGHT", 8, 0)
        else
            f:SetPoint("TOP", hudRef, "BOTTOM", 0, -6)
        end
    else
        f:SetPoint("TOP", self.anchorFrame, "TOP", 0, 0)
    end

    local p = Theme and Theme.GetPalette and Theme:GetPalette() or nil
    UpdateToastNavBar(f, self.activeItems, activeIdx, totalCount, p)
    RenderItemOnFrame(f, item, showNav)
    f:Show()

    self:ShowTutorialIfNeeded()

    -- Single shared OnUpdate ticker (20 Hz) to drive progress bar and auto-dismiss 1 notification every N seconds
    self._tickAccum = 0
    if not Toast._tickerFn then
        Toast._tickerFn = function(_, dt)
            Toast._tickAccum = (Toast._tickAccum or 0) + (dt or 0)
            if Toast._tickAccum < 0.05 then
                return
            end
            local delta = Toast._tickAccum
            Toast._tickAccum = 0

            local countNow = #Toast.activeItems
            if countNow == 0 then
                Toast.anchorFrame:SetScript("OnUpdate", nil)
                return
            end

            local idx = Toast.activeIndex or 1
            if idx > countNow then
                idx = countNow
                Toast.activeIndex = idx
            elseif idx < 1 then
                idx = 1
                Toast.activeIndex = 1
            end

            local it = Toast.activeItems[idx]
            local card = Toast.framePool[1]
            if not it or not card then return end

            local confirmOpen = Toast.confirmPopup and Toast.confirmPopup:IsShown()
            local tutorialOpen = Toast.tutorialDialog and Toast.tutorialDialog:IsShown()
            local isHovered = confirmOpen or tutorialOpen
                or (card:IsShown() and (card:IsMouseOver() or (card.navBar and card.navBar:IsShown() and card.navBar:IsMouseOver())))

            if it.countdownUntil and card:IsShown() and card.bodyLbl then
                local remSec = math.max(0, math.ceil(it.countdownUntil - (GetTime and GetTime() or 0)))
                if it._lastShownSec ~= remSec then
                    it._lastShownSec = remSec
                    card.bodyLbl:SetText((remSec > 0) and L["Dropping in ~%ds!"]:format(remSec) or L["World Buff should be active now!"])
                end
            end

            if not isHovered and card:IsShown() then
                it.elapsed = (it.elapsed or 0) + delta
                local totalDur = math.max(GetConfiguredToastDuration(), tonumber(it.minDuration) or 0)
                it.totalDuration = totalDur
                local remainingFrac = math.max(0, 1 - (it.elapsed / totalDur))

                if card:IsShown() and card.arrivalSheen then
                    if it.elapsed < 0.35 then
                        local rgb = card._kindRgb or KIND_RGB.DIRECT
                        card.arrivalSheen:SetVertexColor(rgb[1] * 0.5 + 0.5, rgb[2] * 0.5 + 0.5, rgb[3] * 0.5 + 0.5, (1 - (it.elapsed / 0.35)) * 0.24)
                        if not card.arrivalSheen:IsShown() then
                            card.arrivalSheen:Show()
                        end
                    elseif card.arrivalSheen:IsShown() then
                        card.arrivalSheen:Hide()
                    end
                end

                if card:IsShown() and card.progressFill then
                    local newW = math.max(1, (TOAST_WIDTH - 8) * remainingFrac)
                    if math.abs((card._lastProgressW or -99) - newW) >= 0.5 then
                        card._lastProgressW = newW
                        card.progressFill:SetWidth(newW)
                    end
                end

                if it.elapsed >= totalDur then
                    local removedActive = RemoveActiveToastAt(idx)
                    DrainToastQueueAndResetElapsed(removedActive)
                    Toast:LayoutStack()
                end
            end
        end
    end
    if not self.anchorFrame:GetScript("OnUpdate") then
        self.anchorFrame:SetScript("OnUpdate", Toast._tickerFn)
    end
end

local function DescribeDisableTarget(item)
    if not item then return nil end
    local k = item.kind
    local itemId = type(item.id) == "string" and item.id or ""

    local function EmitDisabledFeedback(label, kindMatchesFn)
        ns:Emit("SETTINGS_UPDATED")
        if ns.Settings and ns.Settings.Refresh then
            ns.Settings:Refresh()
        end
        if ns.UI and ns.UI.QueueRefresh then
            ns.UI:QueueRefresh(false)
        end
        for i = #Toast.queue, 1, -1 do
            if kindMatchesFn(Toast.queue[i]) then
                table.remove(Toast.queue, i)
            end
        end
        local _, removedActive = PruneActiveToasts(kindMatchesFn)
        DrainToastQueueAndResetElapsed(removedActive)
        Toast:SortActiveItems()
        Toast:LayoutStack()
        ns:Print("|cff9da7b5%s|r %s", label, L["disabled. Re-enable anytime in Settings -> Notifications."])
    end

    local playerMuteLabel, playerMuteFn
    local safeSenderName = tostring(item.sender or "?")
    if Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()
        and (item.bnetAccountID ~= nil or k == "BN_WHISPER" or safeSenderName:find("#", 1, true))
        and Compat.MaskStreamerBNetName
    then
        safeSenderName = Compat.MaskStreamerBNetName(safeSenderName)
    end
    if (k == "FRIEND_ONLINE" or k == "FRIEND_OFFLINE" or k == "WATCHLIST_ONLINE") and (item.lookupKey or item.bnetAccountID) and ns.Store and ns.Store.SetPlayerNotifyMuted then
        playerMuteLabel = L["Only %s"]:format(safeSenderName)
        playerMuteFn = function()
            ns.Store:SetPlayerNotifyMuted(item.lookupKey, true, item.bnetAccountID)
            ns:Emit("SOCIAL_UPDATED")
            ns:Emit("WATCHLIST_UPDATED")
            local targetLk = item.lookupKey
            local targetBn = item.bnetAccountID
            local function MatchesMutedPlayer(it)
                if not it then return false end
                if it == item or (item.id and it.id == item.id) then return true end
                if targetLk and targetLk ~= "" and it.lookupKey == targetLk then return true end
                if targetBn and it.bnetAccountID and it.bnetAccountID == targetBn then return true end
                return false
            end
            for i = #Toast.queue, 1, -1 do
                if MatchesMutedPlayer(Toast.queue[i]) then
                    table.remove(Toast.queue, i)
                end
            end
            local _, removedActive = PruneActiveToasts(MatchesMutedPlayer)
            DrainToastQueueAndResetElapsed(removedActive)
            Toast:LayoutStack()
            if ns.UI and ns.UI.QueueRefresh then ns.UI:QueueRefresh(false) end
            ns:Print(L["Notifications muted for %s."]:format(safeSenderName))
        end
    elseif item.threadKey and item.threadKey ~= "" and ns.Chat and ns.Chat.ToggleThreadMuted then
        local isMuted = ns.Chat.IsThreadMuted and ns.Chat:IsThreadMuted(item.threadKey)
        if not isMuted then
            playerMuteLabel = L["Only %s"]:format(safeSenderName)
            playerMuteFn = function()
                ns.Chat:ToggleThreadMuted(item.threadKey)
                Toast:DismissItem(item)
                ns:Print(L["Notifications muted for %s."]:format(safeSenderName))
            end
        end
    end

    if k == "FRIEND_ONLINE" then
        return {
            label = L["Friend Online Alerts"],
            desc = L["Stop notifying when friends connect to WoW."],
            playerMuteLabel = playerMuteLabel,
            playerMuteFn = playerMuteFn,
            disableFn = function()
                if ns.db and ns.db.settings then
                    ns.db.settings.friendOnlineAlertToast = false
                    ns.db.settings.friendOnlineAlertChat = false
                end
                EmitDisabledFeedback(L["Friend Online Alerts"], function(it) return it and it.kind == "FRIEND_ONLINE" end)
            end,
        }
    elseif k == "FRIEND_OFFLINE" then
        return {
            label = L["Friend Offline Alerts"],
            desc = L["Stop notifying when friends disconnect from WoW."],
            playerMuteLabel = playerMuteLabel,
            playerMuteFn = playerMuteFn,
            disableFn = function()
                if ns.db and ns.db.settings then
                    ns.db.settings.friendOfflineAlertToast = false
                    ns.db.settings.friendOfflineAlertChat = false
                end
                EmitDisabledFeedback(L["Friend Offline Alerts"], function(it) return it and it.kind == "FRIEND_OFFLINE" end)
            end,
        }
    elseif k == "WATCHLIST_ONLINE" then
        return {
            label = L["Watchlist Online Alerts"],
            desc = L["Stop notifying when Watchlist players come online."],
            playerMuteLabel = playerMuteLabel,
            playerMuteFn = playerMuteFn,
            disableFn = function()
                if ns.db and ns.db.settings and ns.db.settings.alerts then
                    ns.db.settings.alerts.toast = false
                    ns.db.settings.alerts.chat = false
                end
                EmitDisabledFeedback(L["Watchlist Online Alerts"], function(it) return it and it.kind == "WATCHLIST_ONLINE" end)
            end,
        }
    elseif k == "WORLDBUFF" then
        if itemId:sub(1, 6) == "wbexp:" then
            return {
                label = L["World Buff Expiry Warning"],
                desc = L["Stop warning when an active World Buff has under 5m left."],
                disableFn = function()
                    if ns.db and ns.db.settings then
                        ns.db.settings.worldBuffsExpiryAlert = false
                    end
                    EmitDisabledFeedback(L["World Buff Expiry Warning"], function(it) return it and it.kind == "WORLDBUFF" and type(it.id) == "string" and it.id:sub(1, 6) == "wbexp:" end)
                end,
            }
        end
        return {
            label = L["World Buff Drop Alerts"],
            desc = L["Stop notifying when Classic World Buffs are announced or synced."],
            disableFn = function()
                if ns.db and ns.db.settings then
                    ns.db.settings.worldBuffsAlerts = false
                end
                EmitDisabledFeedback(L["World Buff Drop Alerts"], function(it) return it and it.kind == "WORLDBUFF" and not (type(it.id) == "string" and it.id:sub(1, 6) == "wbexp:") end)
            end,
        }
    elseif k == "CLAN_LFG" then
        if itemId:sub(1, 9) == "lfgwatch:" then
            return {
                label = L["LFG Watchers in Official Chat"],
                desc = L["Stop notifying when Watched Dungeon or Raid groups appear."],
                disableFn = function()
                    if ns.db and ns.db.settings then
                        ns.db.settings.lfgWatchersEnabled = false
                    end
                    if ns.Clan and ns.Clan.SyncOfficialLfgEvents then
                        ns.Clan:SyncOfficialLfgEvents()
                    end
                    EmitDisabledFeedback(L["LFG Watchers in Official Chat"], function(it) return it and it.kind == "CLAN_LFG" and type(it.id) == "string" and it.id:sub(1, 9) == "lfgwatch:" end)
                end,
            }
        end
        return {
            label = L["Clan Dungeon Alerts"],
            desc = L["Stop notifying when guildmates look for a Dungeon / Group."],
            disableFn = function()
                if ns.db and ns.db.settings then
                    ns.db.settings.clanLfgAlertEnabled = false
                end
                EmitDisabledFeedback(L["Clan Dungeon Alerts"], function(it) return it and it.kind == "CLAN_LFG" and not (type(it.id) == "string" and it.id:sub(1, 9) == "lfgwatch:") end)
            end,
        }
    elseif k == "CLAN_EVENT" then
        if itemId:sub(1, 6) == "evrem:" then
            return {
                label = L["Guild Event Reminders"],
                desc = L["Stop showing 15m and 5m reminders before Guild & Calendar events."],
                disableFn = function()
                    if ns.db and ns.db.settings then
                        ns.db.settings.clanEventReminders = false
                    end
                    EmitDisabledFeedback(L["Guild Event Reminders"], function(it) return it and it.kind == "CLAN_EVENT" and type(it.id) == "string" and it.id:sub(1, 6) == "evrem:" end)
                end,
            }
        end
        return {
            label = L["Guild Event Alerts"],
            desc = L["Stop notifying when guildmates post new Guild Events."],
            disableFn = function()
                if ns.db and ns.db.settings then
                    ns.db.settings.clanEventAlertEnabled = false
                end
                EmitDisabledFeedback(L["Guild Event Alerts"], function(it) return it and it.kind == "CLAN_EVENT" and not (type(it.id) == "string" and it.id:sub(1, 6) == "evrem:") end)
            end,
        }
    elseif k == "CLAN_SIGNUP" then
        return {
            label = L["Guild Signup Alerts"],
            desc = L["Stop notifying when guildmates sign up to your Events."],
            disableFn = function()
                if ns.db and ns.db.settings then
                    ns.db.settings.clanSignupAlertEnabled = false
                end
                EmitDisabledFeedback(L["Guild Signup Alerts"], function(it) return it and it.kind == "CLAN_SIGNUP" end)
            end,
        }
    elseif k == "SCOUT" then
        return {
            label = L["Guild Scout Alerts"],
            desc = L["Stop notifying on Scout sightings shared by guildmates."],
            disableFn = function()
                if ns.db and ns.db.settings then
                    ns.db.settings.spotterScoutAlert = false
                end
                EmitDisabledFeedback(L["Guild Scout Alerts"], function(it) return it and it.kind == "SCOUT" end)
            end,
        }
    elseif k == "AVOID_ALERT" then
        return {
            label = L["Group Avoid Warnings"],
            desc = L["Stop warning when an Avoid-flagged player enters your group."],
            disableFn = function()
                if ns.db and ns.db.settings then
                    ns.db.settings.groupAvoidAlert = false
                end
                EmitDisabledFeedback(L["Group Avoid Warnings"], function(it) return it and it.kind == "AVOID_ALERT" end)
            end,
        }
    elseif k == "MENTION" then
        return {
            label = L["Mentions & Keywords Radar"],
            desc = L["Stop alerting when your name, nickname, or custom keywords appear in chat."],
            playerMuteLabel = playerMuteLabel,
            playerMuteFn = playerMuteFn,
            disableFn = function()
                if ns.db and ns.db.settings then
                    ns.db.settings.mentionAlertsEnabled = false
                end
                EmitDisabledFeedback(L["Mentions & Keywords Radar"], function(it) return it and it.kind == "MENTION" end)
            end,
        }
    elseif k == "VERSION_UPDATE" then
        return {
            label = L["Addon Update Alerts"],
            desc = L["Stop checking or alerting when peers run a newer addon version."],
            disableFn = function()
                if ns.db and ns.db.settings then
                    ns.db.settings.versionCheck = false
                end
                EmitDisabledFeedback(L["Addon Update Alerts"], function(it) return it and it.kind == "VERSION_UPDATE" end)
            end,
        }
    else
        return {
            label = L["Floating Message Popups"],
            desc = L["Stop showing floating popups for addon messages (conversations still appear in Chat)."],
            playerMuteLabel = playerMuteLabel,
            playerMuteFn = playerMuteFn,
            disableFn = function()
                if ns.db and ns.db.settings then
                    ns.db.settings.addonMsgToast = false
                end
                EmitDisabledFeedback(L["Floating Message Popups"], function(it)
                    if not it then return false end
                    local ik = it.kind
                    return ik == "DIRECT" or ik == "ROOM" or ik == "RMI" or ik == "ALLIANCE"
                        or ik == "WHISPER" or ik == "BN_WHISPER" or ik == "PARTY"
                        or ik == "GROUP" or ik == "RAID" or ik == "GUILD" or ik == "OFFICER"
                end)
            end,
        }
    end
end

function Toast:ShowConfirmDisablePopup(anchorToast, item)
    if not item then return end
    local spec = DescribeDisableTarget(item)
    if not spec then return end

    if not self.confirmPopup then
        local pop = CreateFrame("Frame", "SocialCentralToastConfirmPopup", UIParent, "BackdropTemplate")
        pop:Hide()
        pop:SetSize(288, 134)
        pop:SetFrameStrata("DIALOG")
        pop:SetFrameLevel(240)
        pop:SetClampedToScreen(true)
        pop:EnableMouse(true)
        if pop.SetPropagateKeyboardInput then
            pop:SetPropagateKeyboardInput(true)
        end

        local solidBg = pop:CreateTexture(nil, "BACKGROUND", nil, -8)
        solidBg:SetAllPoints()
        solidBg:SetTexture(WHITE8X8)
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

        if Theme and Theme.MakeMovable then
            Theme:MakeMovable(pop, { key = "toastConfirmPopup", skipAutoRestore = true })
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
            table.insert(_G.UISpecialFrames, "SocialCentralToastConfirmPopup")
        end

        self.confirmPopup = pop
    end

    local pop = self.confirmPopup
    pop._targetItem = item
    if Theme and Theme.PrepareTopOverlayModal then
        Theme:PrepareTopOverlayModal(pop, 885)
    end
    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(pop, "window")
    end
    local p = Theme and Theme.GetPalette and Theme:GetPalette()
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
        pop:SetWidth(math.max(296, math.min(448, neededW)))
    else
        pop.playerBtn:Hide()
        Theme:SetButtonText(pop.confirmBtn, L["Disable"])
        Theme:AutoFitButton(pop.confirmBtn, 96, 14, 140)
        Theme:AutoFitButton(pop.cancelBtn, 80, 14, 110)
        pop:SetWidth(288)
    end

    pop.subLbl:SetText(("|cffffd24d%s|r\n|cffd2d9e4%s|r"):format(spec.label or "", spec.desc or ""))
    local textH = (pop.subLbl.GetStringHeight and pop.subLbl:GetStringHeight()) or 32
    pop:SetHeight(math.max(108 + extraBottom, math.ceil(36 + textH + 44 + extraBottom)))

    pop:ClearAllPoints()
    local ref = (anchorToast and anchorToast.IsShown and anchorToast:IsShown() and anchorToast) or self.anchorFrame
    if ref and ref.GetCenter and UIParent and UIParent.GetWidth then
        local uiW = UIParent:GetWidth() or 1280
        local popW = pop:GetWidth() or 288
        local right = (ref.GetRight and ref:GetRight()) or (uiW * 0.6)
        local left = (ref.GetLeft and ref:GetLeft()) or (uiW * 0.4)
        if (uiW - right) >= (popW + 12) then
            pop:SetPoint("TOPLEFT", ref, "TOPRIGHT", 8, 0)
        elseif left >= (popW + 12) then
            pop:SetPoint("TOPRIGHT", ref, "TOPLEFT", -8, 0)
        else
            pop:SetPoint("TOP", ref, "BOTTOM", 0, -6)
        end
    else
        pop:SetPoint("TOP", UIParent, "TOP", 0, -170)
    end
    if Theme and Theme.SyncSubtreeLayers then
        Theme:SyncSubtreeLayers(pop, 8)
    end
    pop:Show()
    pop:Raise()
end

function Toast:DismissItem(item)
    if not item then return end
    if self.confirmPopup and self.confirmPopup:IsShown() and self.confirmPopup._targetItem == item then
        self.confirmPopup:Hide()
    end
    local removedActive = false
    for i, it in ipairs(self.activeItems) do
        if it == item or (it.id and it.id == item.id) then
            removedActive = RemoveActiveToastAt(i)
            break
        end
    end

    DrainToastQueueAndResetElapsed(removedActive)

    self:LayoutStack()
end

function Toast:DismissAll()
    if self.confirmPopup and self.confirmPopup:IsShown() then
        self.confirmPopup:Hide()
    end
    wipe(self.queue)
    wipe(self.activeItems)
    self.activeIndex = 1
    self:LayoutStack()
end

--- Display or coalesce an incoming addon notification item inside the single paginated floating toast below chat.
function Toast:PushNotification(item)
    if type(item) ~= "table" then return end
    local s = ns.db and ns.db.settings
    local itemId = type(item.id) == "string" and item.id or ""
    if item.kind ~= "AVOID_ALERT" and item.kind ~= "FOCUS_SUMMARY" and not item.isTest
        and Compat and Compat.IsFocusSilenced and Compat.IsFocusSilenced(item.lookupKey or item.sender, item.bnetAccountID)
    then
        return
    end
    if not item.isTest then
        if item.kind == "FRIEND_ONLINE" then
            if s and s.friendOnlineAlertToast == false then
                return
            end
        elseif item.kind == "FRIEND_OFFLINE" then
            if s and s.friendOfflineAlertToast == false then
                return
            end
        elseif item.kind == "AVOID_ALERT" then
            if s and s.groupAvoidAlert == false then
                return
            end
        elseif item.kind == "WATCHLIST_ONLINE" then
            if s and (s.moduleWatchlistEnabled == false or (s.alerts and s.alerts.toast == false)) then
                return
            end
        elseif item.kind == "WORLDBUFF" then
            if s and s.embedWorldMap == false then return end
            if itemId:sub(1, 6) == "wbexp:" then
                if s and s.worldBuffsExpiryAlert == false then return end
            else
                if s and s.worldBuffsAlerts == false then return end
            end
        elseif item.kind == "CLAN_LFG" then
            if itemId:sub(1, 9) == "lfgwatch:" then
                if Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("lfg") then return end
                if s and s.lfgWatchersEnabled == false then return end
            else
                if Compat and Compat.IsWindowIntegrationEnabled and not Compat.IsWindowIntegrationEnabled("J") then return end
                if s and s.clanLfgAlertEnabled == false then
                    return
                end
            end
        elseif item.kind == "CLAN_EVENT" then
            if itemId:sub(1, 6) == "evrem:" then
                if s and s.clanEventReminders == false then return end
            else
                if Compat and Compat.IsWindowIntegrationEnabled and not Compat.IsWindowIntegrationEnabled("J") then return end
                if s and s.clanEventAlertEnabled == false then return end
            end
        elseif item.kind == "CLAN_SIGNUP" then
            if Compat and Compat.IsWindowIntegrationEnabled and not Compat.IsWindowIntegrationEnabled("J") then return end
            if s and s.clanSignupAlertEnabled == false then
                return
            end
        elseif item.kind == "SCOUT" then
            if Compat and Compat.IsWindowIntegrationEnabled and not Compat.IsWindowIntegrationEnabled("J") then return end
            if s and s.spotterScoutAlert == false then
                return
            end
        elseif item.kind == "VERSION_UPDATE" then
            if s and s.versionCheck == false then
                return
            end
        elseif item.kind == "FOCUS_SUMMARY" then
            -- Focus Mode end summary appears once when Focus Mode ends.
        elseif item.kind == "MENTION" then
            if s and (s.moduleChatEnabled == false or s.mentionAlertsEnabled == false) then
                return
            end
        elseif item.kind == "RMI" then
            if s and s.moduleChatEnabled == false then
                return
            end
            if s and s.addonMsgTaskbarFlash ~= false and (item.priority or 1) >= 2 and FlashClientIcon then
                pcall(FlashClientIcon)
            end
        else
            if s and s.moduleChatEnabled == false then
                return
            end
            if s and s.addonMsgTaskbarFlash ~= false and (item.priority or 1) >= 2 and FlashClientIcon then
                pcall(FlashClientIcon)
            end
            if not (s and s.addonMsgToast == true) then
                return
            end
        end
    end

    RecordRecentNotification(item)

    local cKey = FormatCooldownKey(item)

    -- Check for coalescing in active items
    for _, active in ipairs(self.activeItems) do
        if FormatCooldownKey(active) == cKey then
            active.text = item.text
            active.sender = item.sender or active.sender
            active.senderClass = item.senderClass or active.senderClass
            active.sourceTag = item.sourceTag or active.sourceTag
            if type(item.minDuration) == "number" and item.minDuration > (tonumber(active.minDuration) or 0) then
                active.minDuration = item.minDuration
            end
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
            queued.sourceTag = item.sourceTag or queued.sourceTag
            if type(item.minDuration) == "number" and item.minDuration > (tonumber(queued.minDuration) or 0) then
                queued.minDuration = item.minDuration
            end
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
    local cfgDur = GetConfiguredToastDuration()
    if type(item.minDuration) == "number" and item.minDuration > 0 then
        entry.minDuration = item.minDuration
    elseif type(item.totalDuration) == "number" and item.totalDuration > cfgDur and not item.isTest then
        entry.minDuration = item.totalDuration
    end
    entry.totalDuration = math.max(cfgDur, tonumber(entry.minDuration) or 0)

    if #self.activeItems < MAX_QUEUE then
        table.insert(self.activeItems, entry)
        if #self.activeItems == 1 then
            self.activeIndex = 1
        elseif entry.kind == "AVOID_ALERT" then
            self.activeIndex = #self.activeItems
        end
    else
        if #self.queue < MAX_QUEUE then
            table.insert(self.queue, entry)
        else
            self.queue[#self.queue] = entry
        end
        if entry.kind == "AVOID_ALERT" then
            self.activeItems[#self.activeItems] = entry
            self.activeIndex = #self.activeItems
        end
    end
    self:LayoutStack()
end

--- Preview sample toast notifications directly from Settings or '/sc toast' for layout positioning & sound testing.
function Toast:ShowTestNotification(variant)
    local v = type(variant) == "string" and variant:lower():match("^%s*(.-)%s*$") or ""
    if v == "clear" or v == "dismiss" or v == "hide" or v == "reset" then
        self:DismissAll()
        return
    elseif v == "tutorial" or v == "help" then
        self:ShowTutorial(true)
        return
    end

    local resolvedSelf = Compat and Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myName = (resolvedSelf and resolvedSelf.fullName) or (ns.Safe and ns.Safe.String(ns.Safe.Call(UnitName, "player"))) or "SocialCentral"
    local _, myClass
    if ns.Safe and ns.Safe.Call then
        _, myClass = ns.Safe.Call(UnitClass, "player")
    elseif UnitClass then
        _, myClass = UnitClass("player")
    end
    local now = time()
    local cfgDur = GetConfiguredToastDuration()

    if v == "invite" or v == "room" then
        self:PushNotification({
            id = "test:invite:" .. tostring(now),
            kind = "RMI",
            roomId = "test-room-preview",
            sourceTag = L["Room Invite"],
            sender = myName,
            senderClass = myClass or "MAGE",
            text = L["Dungeon & Raid Social"],
            priority = 2,
            totalDuration = cfgDur,
            isTest = true,
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
            totalDuration = cfgDur,
            isTest = true,
        })
    elseif v == "offline" then
        self:PushNotification({
            id = "test:off:" .. tostring(now),
            kind = "FRIEND_OFFLINE",
            sourceTag = L["Friend Offline"],
            sender = myName,
            senderClass = myClass or "WARRIOR",
            text = L["Disconnected"],
            priority = 1,
            totalDuration = cfgDur,
            isTest = true,
        })
    elseif v == "avoid" then
        self:PushNotification({
            id = "test:avoid:" .. tostring(now),
            kind = "AVOID_ALERT",
            sourceTag = L["Avoid Warning"],
            sender = myName,
            senderClass = myClass or "ROGUE",
            text = L["In your group! Flagged as Avoid."],
            priority = 2,
            totalDuration = cfgDur,
            isTest = true,
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
            totalDuration = cfgDur,
            isTest = true,
        })
    elseif v == "buff" or v == "buffs" then
        self:PushNotification({
            id = "test:buff:" .. tostring(now),
            kind = "WORLDBUFF",
            sourceTag = L["World Buffs"],
            sender = L["Rallying Cry of the Dragonslayer"],
            senderClass = nil,
            text = "~15s",
            priority = 2,
            totalDuration = cfgDur,
            isTest = true,
        })
    elseif v == "queue" or v == "multi" or v == "stack" or v == "page" then
        wipe(self.queue)
        wipe(self.activeItems)
        self.activeIndex = 1
        self:PushNotification({
            id = "test:direct:" .. tostring(now),
            kind = "DIRECT",
            sourceTag = L["Direct Addon"],
            sender = myName,
            senderClass = myClass,
            text = L["Sample addon notification toast — drag anywhere to reposition!"],
            priority = 2,
            totalDuration = cfgDur,
            isTest = true,
        })
        self:PushNotification({
            id = "test:invite:" .. tostring(now),
            kind = "RMI",
            roomId = "test-room-preview",
            sourceTag = L["Room Invite"],
            sender = myName,
            senderClass = myClass or "MAGE",
            text = L["Dungeon & Raid Social"],
            priority = 2,
            totalDuration = cfgDur,
            isTest = true,
        })
        self:PushNotification({
            id = "test:friend:" .. tostring(now),
            kind = "FRIEND_ONLINE",
            sourceTag = L["Friend"],
            sender = myName,
            senderClass = myClass or "WARRIOR",
            text = L["Online"],
            priority = 1,
            totalDuration = cfgDur,
            isTest = true,
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
            totalDuration = cfgDur,
            isTest = true,
        })
    end

    if PlaySound and SOUNDKIT then
        local pingSound = SOUNDKIT.MAP_PING or 3175
        pcall(PlaySound, pingSound, "Master")
    end
end

function Toast:Init()
    if self.hooksInitialized then return end
    self.hooksInitialized = true

    EnsureAnchorFrame()

    ns:On("ADDON_MESSAGE_NOTIFY", function(payload)
        Toast:PushNotification(payload)
    end)

    ns:On("DISMISS_TOAST_PREFIX", function(prefix)
        if type(prefix) ~= "string" or prefix == "" then return end
        local pLen = #prefix
        for i = #Toast.queue, 1, -1 do
            local q = Toast.queue[i]
            if q and type(q.id) == "string" and q.id:sub(1, pLen) == prefix then
                table.remove(Toast.queue, i)
            end
        end
        local changed, removedActive = PruneActiveToasts(function(it)
            return it and type(it.id) == "string" and it.id:sub(1, pLen) == prefix
        end)
        if changed then
            DrainToastQueueAndResetElapsed(removedActive)
            Toast:LayoutStack()
        end
    end)

    ns:On("CHAT_THREAD_READ", function(info)
        local tKey = type(info) == "table" and info.threadKey or (type(info) == "string" and info) or nil
        local cKey = type(info) == "table" and info.channelKey or tKey
        local bnId = type(info) == "table" and info.bnetAccountID or nil
        if not (tKey or cKey or bnId) then return end
        local function Matches(it)
            if not it then return false end
            if tKey and it.threadKey == tKey then return true end
            if cKey and it.threadKey == cKey then return true end
            if bnId and it.bnetAccountID and it.bnetAccountID == bnId then return true end
            return false
        end
        for i = #Toast.queue, 1, -1 do
            if Matches(Toast.queue[i]) then
                table.remove(Toast.queue, i)
            end
        end
        local changed, removedActive = PruneActiveToasts(Matches)
        if changed then
            DrainToastQueueAndResetElapsed(removedActive)
            Toast:LayoutStack()
        end
    end)

    ns:On("CHAT_UPDATED", function()
        if #Toast.activeItems == 0 and #Toast.queue == 0 then return end
        -- Automatically dismiss any active or queued toast if the player opened and read that exact thread elsewhere.
        local function IsThreadReadVisible(cur)
            if not (cur and cur.threadKey) then return false end
            if ns.UI and ns.UI.IsChatThreadVisible and ns.UI:IsChatThreadVisible(cur.threadKey) then
                return true
            end
            if ns.QuickReply and ns.QuickReply.IsViewingThread and ns.QuickReply:IsViewingThread(cur.threadKey) then
                return true
            end
            return false
        end
        for i = #Toast.queue, 1, -1 do
            if IsThreadReadVisible(Toast.queue[i]) then
                table.remove(Toast.queue, i)
            end
        end
        local changed, removedActive = PruneActiveToasts(IsThreadReadVisible)
        if changed then
            DrainToastQueueAndResetElapsed(removedActive)
            Toast:LayoutStack()
        end
    end)

    local function PruneForSettingsOrInstance()
        local s = ns.db and ns.db.settings
        if not s then return end
        local function ShouldPrune(it)
            if not it then return false end
            if it.kind ~= "AVOID_ALERT" and it.kind ~= "FOCUS_SUMMARY" and not it.isTest
                and Compat and Compat.IsFocusSilenced and Compat.IsFocusSilenced(it.lookupKey or it.sender, it.bnetAccountID)
            then
                return true
            end
            if it.kind == "WORLDBUFF" then
                if s.embedWorldMap == false then return true end
                if tostring(it.id or ""):sub(1, 6) == "wbexp:" then
                    if s.worldBuffsExpiryAlert == false then return true end
                elseif s.worldBuffsAlerts == false then
                    return true
                end
            end
            if it.kind == "FRIEND_ONLINE" and (s.friendOnlineAlertToast == false or (s.friendOnlineAlertMode == "off" and it.sourceTag ~= L["Guild"])) then return true end
            if it.kind == "FRIEND_OFFLINE" and (s.friendOfflineAlertToast == false or (s.friendOnlineAlertMode == "off" and it.sourceTag ~= L["Guild"])) then return true end
            if it.kind == "WATCHLIST_ONLINE" and (s.moduleWatchlistEnabled == false or (s.alerts and s.alerts.toast == false)) then return true end
            if it.kind == "MENTION" and (s.moduleChatEnabled == false or s.mentionAlertsEnabled == false) then return true end
            if it.kind == "AVOID_ALERT" and s.groupAvoidAlert == false then return true end
            if it.kind == "VERSION_UPDATE" and s.versionCheck == false then return true end
            if (it.kind == "DIRECT" or it.kind == "ROOM" or it.kind == "RMI" or it.kind == "ALLIANCE" or it.kind == "WHISPER" or it.kind == "BN_WHISPER" or it.kind == "PARTY" or it.kind == "GROUP" or it.kind == "RAID" or it.kind == "GUILD" or it.kind == "OFFICER") and s.moduleChatEnabled == false then return true end
            local isLfgWatcher = (it.kind == "CLAN_LFG" and tostring(it.id or ""):sub(1, 9) == "lfgwatch:")
            if isLfgWatcher then
                if (Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("lfg")) or s.lfgWatchersEnabled == false then
                    return true
                end
            else
                if (it.kind == "CLAN_LFG" or it.kind == "CLAN_SIGNUP" or it.kind == "SCOUT" or (it.kind == "CLAN_EVENT" and tostring(it.id or ""):sub(1, 6) ~= "evrem:"))
                    and Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("clan") then
                    return true
                end
                if it.kind == "CLAN_LFG" and s.clanLfgAlertEnabled == false then return true end
            end
            if it.kind == "CLAN_SIGNUP" and s.clanSignupAlertEnabled == false then return true end
            if it.kind == "SCOUT" and s.spotterScoutAlert == false then return true end
            if it.kind == "CLAN_EVENT" then
                if tostring(it.id or ""):sub(1, 6) == "evrem:" then
                    if s.clanEventReminders == false then return true end
                elseif s.clanEventAlertEnabled == false then
                    return true
                end
            end
            return false
        end
        for i = #Toast.queue, 1, -1 do
            if ShouldPrune(Toast.queue[i]) then table.remove(Toast.queue, i) end
        end
        local changed, removedActive = PruneActiveToasts(ShouldPrune)
        if changed then
            DrainToastQueueAndResetElapsed(removedActive)
            Toast:LayoutStack()
        end
    end

    ns:On("SETTINGS_UPDATED", function()
        Toast:RefreshAnchorMode()
        PruneForSettingsOrInstance()
        if #Toast.activeItems > 0 then
            Toast:LayoutStack()
        end
    end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        if Toast.anchorFrame and not HasSavedCustomToastPosition() then
            PositionToastAnchorBelowChat(Toast.anchorFrame)
        end
        PruneForSettingsOrInstance()
        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
    end)
    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", function()
        PruneForSettingsOrInstance()
        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        if Toast.confirmPopup and Toast.confirmPopup:IsShown() then
            Toast.confirmPopup:Hide()
        end
        local sCfg = ns.db and ns.db.settings
        if (not sCfg or sCfg.msgPreviewSilenceCombat ~= false) and #Toast.activeItems > 0 then
            Toast:LayoutStack()
        end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if Toast.pendingTutorial then
            Toast:ShowTutorialIfNeeded()
        end
        local nowMono = (GetTime and GetTime()) or 0
        local function IsStaleWorldBuff(it)
            return it and it.kind == "WORLDBUFF" and type(it.countdownUntil) == "number" and (nowMono - it.countdownUntil) > 30
        end
        for i = #Toast.queue, 1, -1 do
            if IsStaleWorldBuff(Toast.queue[i]) then
                table.remove(Toast.queue, i)
            end
        end
        local staleChanged, staleRemovedActive = PruneActiveToasts(IsStaleWorldBuff)
        if staleChanged then
            DrainToastQueueAndResetElapsed(staleRemovedActive)
        end
        if #Toast.activeItems > 0 or staleChanged then
            Toast:LayoutStack()
        end
    end)

    if Theme and Theme.RegisterListener then
        Theme:RegisterListener(function()
            for _, f in ipairs(Toast.framePool) do
                ApplyToastThemeToFrame(f, true)
            end
            local pop = Toast.confirmPopup
            if pop and pop:IsShown() then
                Theme:ApplyBackdrop(pop, "window")
                local p = Theme:GetPalette()
                if p and pop._solidOpaqueBg then
                    local wb = p.windowBg or { 0.06, 0.06, 0.08, 1.0 }
                    pop._solidOpaqueBg:SetVertexColor(wb[1], wb[2], wb[3], 1.0)
                end
                Theme:StyleButton(pop.xBtn, "default")
                Theme:StyleButton(pop.confirmBtn, "primary")
                Theme:StyleButton(pop.playerBtn, "default")
                Theme:StyleButton(pop.cancelBtn, "default")
                if pop.dndBtn then Theme:StyleButton(pop.dndBtn, "default") end
                if pop.helpBtn and pop.helpBtn.RefreshTheme then pop.helpBtn:RefreshTheme() end
            end
        end)
    end
end

ns.NotificationToast = Toast
table.insert(ns.modules, Toast)
