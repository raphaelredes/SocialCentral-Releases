local _, ns = ...

local L = ns.L
local Safe = ns.Safe
local Compat = ns.Compat
local Store = ns.Store
local Theme = ns.Theme

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"

local UI = {}
ns.UI = UI

local frame
local searchBox
local addBox
local scrollList
local clanPanel
local groupPanel
local chatPanel
local altsPanel
local modalFrame
local disambigModalFrame
local watchSuggestFrame
local eventModalFrame
local clanInfoModalFrame
local diplomacyModalFrame
local clanRightViewFilterDip = "all"
local ticker
local ReflowWatchBar
local ReflowFilterBar
local ReflowClanPanel

local activeTab = "watchlist"
local embeddedState = {
    active = false,
    host = nil,
    allowedSet = nil,
    _seq = 0,
}
local embedContainers = {}

local function ResolveSinglePanelEmbedKey(hostFrame)
    if not hostFrame then
        return nil
    end
    if (_G.CommunitiesFrame and hostFrame == _G.CommunitiesFrame) or (_G.GuildFrame and hostFrame == _G.GuildFrame) then
        return "clan"
    elseif _G.CharacterFrame and hostFrame == _G.CharacterFrame then
        return "alts"
    elseif _G.LFGParentFrame and hostFrame == _G.LFGParentFrame then
        return "group"
    end
    return nil
end

local function IsAnyEmbedContainer(child)
    if not child then return false end
    for _, c in pairs(embedContainers) do
        if c == child then
            return true
        end
    end
    return false
end

local function IsSingleEmbedActive(tabKey)
    local c = tabKey and embedContainers[tabKey]
    return (c and c._active and c:IsShown()) and true or false
end

local function AttachUpdateButtonTooltip(btn)
    if not btn then return end
    btn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        local rv = ns.Clan and ns.Clan.latestRemoteVersion
        GameTooltip:SetOwner(selfBtn, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Update Available"], 1.0, 0.78, 0.20)
        if rv then
            GameTooltip:AddLine(L["Version v%s is available (you have v%s). Click to update!"]:format(rv, ns.version or "0.0.0"), 0.92, 0.94, 0.98, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end
local socialFilter = "all"
local socialFolderFilter = "all"
UI._expandedSocialKey = nil
local collapsedSocialFolders = { social = {}, watchlist = {} }

function UI._GetSocialItemExpandKey(item)
    if not item or item._isSocialFolderHeader or item._isSocialDetailRow then
        return nil
    end
    local key = item.lookupKey or item.bnetAccountID or item.displayName or item.bnetName
    if key == nil or key == "" then
        return nil
    end
    return tostring(key)
end
local watchlistGroupFilter = "all"
local clanEventFilter = "all"
local clanRightView = "peers"
local clanLfgDungeonsOnly = false
local clanLfgSourceFilter = "ALL" -- "ALL" | "CLAN" | "ALLY" | "FRIENDS"
local clanLfgQuery = ""
local clanPeerQuery = ""
local clanPeerStatusFilter = "all"
local clanPeerRankFilter = nil
local clanPeerClassFilter = nil
local clanPeerSortBy = "level_desc"
local clanProfQuery = ""
local clanProfFilter = "ALL"
local clanProfSourceFilter = "ALL"
local clanProfCounts = {}
local searchQuery = ""
local pendingAltsNav = nil

local tabButtons = {}
local tabOrder = {}
local clanRightViewButtons = {}
local themeTargets = {}

function UI:GetFrame()
    return frame
end

function UI:SetSocialNavigation(opts)
    if type(opts) ~= "table" then return end
    if opts.socialFilter and opts.socialFilter ~= "" then
        socialFilter = opts.socialFilter
    end
    local q = opts.socialSearch ~= nil and opts.socialSearch or opts.watchlistSearch
    if q ~= nil then
        local clean = Compat.CleanInput(q) or ""
        searchQuery = clean
        if searchBox and searchBox.SetText then
            searchBox:SetText(clean)
        end
    end
    self:QueueRefresh(true)
end

function UI:SetAltsNavigation(opts)
    if type(opts) ~= "table" then return end
    pendingAltsNav = opts
    if altsPanel and altsPanel.ApplyNavigation then
        altsPanel:ApplyNavigation(opts)
        pendingAltsNav = nil
    end
    self:QueueRefresh(true)
end

function UI:SetChatNavigation(opts)
    if type(opts) ~= "table" then return end
    UI._pendingChatNav = opts
    if chatPanel and chatPanel.ApplyNavigation and frame and frame:IsShown() and activeTab == "chat" then
        chatPanel:ApplyNavigation(opts)
    end
    self:QueueRefresh(true)
end

function UI:SetClanProfessionQuery(q)
    local clean = Compat.CleanInput(q or "") or ""
    clanProfQuery = clean
    clanRightView = "prof"
    if clanPanel and clanPanel.profSearch and clanPanel.profSearch.SetText then
        clanPanel.profSearch:SetText(clean)
    end
    self:QueueRefresh(true)
end

function UI:IsMainVisible()
    return (frame and frame:IsShown()) and true or false
end

function UI:IsChatTabVisible()
    return (frame and frame:IsShown() and activeTab == "chat") and true or false
end

function UI:IsChatThreadVisible(threadKey)
    if not (frame and frame:IsShown() and activeTab == "chat") then
        return false
    end
    if not threadKey then
        return true
    end
    return (ns.Chat and ns.Chat.activeThreadKey == threadKey) and true or false
end

function UI:OpenUpdateModal()
    if Theme and Theme.ShowUpdatePopup then
        Theme:ShowUpdatePopup(ns.version, ns.Clan and ns.Clan.latestRemoteVersion, ns.RELEASE_URL)
    end
end

local function SafeTextMatches(query, ...)
    if not query or query == "" then
        return true
    end
    local q = query:lower()
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and v ~= "" and v:lower():find(q, 1, true) then
            return true
        end
    end
    return false
end

local function IsTabAllowed(tabId)
    if Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled(tabId) then
        return false
    end
    if not (embeddedState.active and embeddedState.allowedSet) then
        return true
    end
    return embeddedState.allowedSet[tabId] == true
end

local HUB_FALLBACK_ORDER = { "watchlist", "social", "clan", "nearby", "alts", "group", "chat" }

local function PickFirstAllowedTab()
    for _, id in ipairs(HUB_FALLBACK_ORDER) do
        if IsTabAllowed(id) then
            return id
        end
    end
    return nil
end

local function IsSingleTabEmbedded()
    if not (embeddedState.active and embeddedState.allowedSet) then
        return false
    end
    local count = 0
    for _, v in pairs(embeddedState.allowedSet) do
        if v == true then
            count = count + 1
            if count > 1 then
                return false
            end
        end
    end
    return count == 1
end

local function GetStandaloneResizeBounds()
    local uw = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1400
    local uh = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 1000
    local minW = math.min(760, math.max(580, math.floor(uw - 24)))
    local minH = math.min(460, math.max(380, math.floor(uh - 24)))
    local maxW = math.max(minW, math.min(1400, math.floor(uw - 24)))
    local maxH = math.max(minH, math.min(1000, math.floor(uh - 24)))
    return minW, minH, maxW, maxH
end

local function GetResponsiveDefaultMainSize()
    local minW, minH, maxW, maxH = GetStandaloneResizeBounds()
    return math.max(minW, math.min(maxW, 790)), math.max(minH, math.min(maxH, 520))
end

local function ApplyStandaloneResizeBounds(targetFrame)
    if not targetFrame then
        return 760, 460, 1400, 1000
    end
    local minW, minH, maxW, maxH = GetStandaloneResizeBounds()
    if targetFrame.SetResizeBounds then
        targetFrame:SetResizeBounds(minW, minH, maxW, maxH)
    elseif targetFrame.SetMinResize then
        targetFrame:SetMinResize(minW, minH)
        targetFrame:SetMaxResize(maxW, maxH)
    end
    return minW, minH, maxW, maxH
end

local function SaveGeometry()
    if embeddedState.active or not frame or frame:GetParent() ~= UIParent then
        return
    end
    if not (ns.db and ns.db.window) then
        return
    end
    local savedCenter = Theme and Theme.GetSavedWindowPosition and Theme:GetSavedWindowPosition("main")
    if type(savedCenter) == "table" and savedCenter.dx ~= nil and savedCenter.dy ~= nil then
        ns.db.window.point = "CENTER"
        ns.db.window.relativePoint = "CENTER"
        ns.db.window.x = math.floor((tonumber(savedCenter.dx) or 0) + 0.5)
        ns.db.window.y = math.floor((tonumber(savedCenter.dy) or 0) + 0.5)
    else
        local point, _, relPoint, x, y = frame:GetPoint(1)
        if point then
            ns.db.window.point = point
            ns.db.window.relativePoint = relPoint
            ns.db.window.x = math.floor((x or 0) + 0.5)
            ns.db.window.y = math.floor((y or 0) + 0.5)
        end
    end
    local minW, minH, maxW, maxH = GetStandaloneResizeBounds()
    local defW, defH = GetResponsiveDefaultMainSize()
    local curW = math.floor((frame:GetWidth() or defW) + 0.5)
    local curH = math.floor((frame:GetHeight() or defH) + 0.5)
    local clampedW = math.max(minW, math.min(maxW, curW))
    local clampedH = math.max(minH, math.min(maxH, curH))
    ns.db.window.width = clampedW
    ns.db.window.height = clampedH
    if Theme and Theme.SaveWindowSize then
        Theme:SaveWindowSize("main", clampedW, clampedH)
    end
end

local function ClearSearchFilter()
    searchQuery = ""
    if searchBox and searchBox.GetText and searchBox:GetText() ~= "" then
        searchBox:SetText("")
    end
end

local function AddHelp(parent, anchorTo, title, whatText, howText, point, relPoint, xOff, yOff, opts)
    if not (Theme and Theme.CreateHelpButton) then
        return nil
    end
    local btn = Theme:CreateHelpButton(parent, title, whatText, howText, 18, opts)
    btn:SetPoint(point or "LEFT", anchorTo, relPoint or "RIGHT", xOff or 6, yOff or 0)
    return btn
end

local function UpdateWhoButtons()
    if not frame or not frame:IsShown() then
        return
    end
    local vBtn = frame.verifyBtn
    if vBtn then
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        local cd = ns.Watchlist and ns.Watchlist.GetCooldownRemaining and ns.Watchlist:GetCooldownRemaining() or 0
        local busy = ns.Watchlist and ns.Watchlist.IsBusy and ns.Watchlist:IsBusy()
        local canClick = (not inCombat) and (not busy) and (cd <= 0)
        if vBtn.SetEnabled then
            vBtn:SetEnabled(canClick)
        end
        if vBtn.ico then
            vBtn.ico:SetDesaturated(not canClick)
            vBtn.ico:SetAlpha(canClick and 1.0 or 0.45)
        end
    end
    if ReflowWatchBar then
        ReflowWatchBar()
    end
end

local function EnsureModal()
    if modalFrame then
        if Theme and Theme.PrepareTopOverlayModal then
            Theme:PrepareTopOverlayModal(modalFrame, 820)
        else
            modalFrame:SetParent(UIParent)
            modalFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            modalFrame:SetFrameLevel(820)
            if modalFrame.SetToplevel then modalFrame:SetToplevel(true) end
        end
        modalFrame:SetHeight(162)
        if modalFrame.input then
            modalFrame.input:Show()
            modalFrame.input:SetMaxLetters(120)
            modalFrame.input:ClearAllPoints()
            modalFrame.input:SetPoint("TOPLEFT", modalFrame, "TOPLEFT", 16, -56)
            modalFrame.input:SetPoint("TOPRIGHT", modalFrame, "TOPRIGHT", -16, -56)
        end
        if modalFrame.btnSave then
            modalFrame.btnSave:Show()
            Theme:SetButtonText(modalFrame.btnSave, L["Save"])
            Theme:AutoFitButton(modalFrame.btnSave, 88, 20)
        end
        if modalFrame.btnCancel then
            Theme:SetButtonText(modalFrame.btnCancel, L["Cancel"])
            Theme:AutoFitButton(modalFrame.btnCancel, 88, 20)
        end
        Theme:ApplyBackdrop(modalFrame, "window")
        Theme:StyleButton(modalFrame.topCloseBtn, "default")
        if modalFrame.helpBtn then
            Theme:StyleButton(modalFrame.helpBtn, "ghost")
        end
        Theme:StyleButton(modalFrame.btnSave, "primary")
        Theme:StyleButton(modalFrame.btnCancel, "default")
        if Theme and Theme.SyncSubtreeLayers then
            Theme:SyncSubtreeLayers(modalFrame, 8)
        end
        return modalFrame
    end

    local m = CreateFrame("Frame", "SocialCentralModal", UIParent, "BackdropTemplate")
    m:SetSize(418, 162)
    m:SetPoint("CENTER")
    if Theme and Theme.PrepareTopOverlayModal then
        Theme:PrepareTopOverlayModal(m, 820)
    else
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(820)
        if m.SetToplevel then m:SetToplevel(true) end
    end
    if m.SetClipsChildren then m:SetClipsChildren(false) end
    m:EnableMouse(true)
    Theme:MakeMovable(m, { key = "modal_generic" })
    m:Hide()
    if type(UISpecialFrames) == "table" then
        local exists = false
        for _, name in ipairs(UISpecialFrames) do
            if name == "SocialCentralModal" then
                exists = true
                break
            end
        end
        if not exists then
            table.insert(UISpecialFrames, "SocialCentralModal")
        end
    end

    local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
    topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
    topCloseBtn:SetScript("OnClick", function()
        m.input:ClearFocus()
        m:Hide()
    end)
    m.topCloseBtn = topCloseBtn

    m.helpBtn = AddHelp(
        m,
        topCloseBtn,
        L["Help: Quick Input"],
        L["Lets you view, edit, or copy text directly from SocialCentral."],
        L["Type or press Ctrl+C in the field below, then use the button at the bottom right."],
        "RIGHT",
        "LEFT",
        -4,
        0,
        { target = m }
    )

    m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    m.title:SetPoint("TOPLEFT", 16, -14)
    m.title:SetPoint("TOPRIGHT", m.helpBtn or topCloseBtn, "LEFT", -6, 0)
    m.title:SetJustifyH("LEFT")
    m.title:SetWordWrap(true)
    if Theme.DecorateSectionHeader then
        Theme:DecorateSectionHeader(m, m.title, 332)
    end

    local input = Theme:CreateEditBox(m, { height = 24, maxLetters = 120 })
    input:SetPoint("TOPLEFT", m, "TOPLEFT", 16, -56)
    input:SetPoint("TOPRIGHT", m, "TOPRIGHT", -16, -56)
    m.input = input

    local btnSave = Theme:CreateButton(m, 92, 24, L["Save"], "primary")
    Theme:AutoFitButton(btnSave, 88, 20)
    btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
    m.btnSave = btnSave

    local btnCancel = Theme:CreateButton(m, 92, 24, L["Cancel"], "default")
    Theme:AutoFitButton(btnCancel, 88, 20)
    btnCancel:SetPoint("RIGHT", btnSave, "LEFT", -8, 0)
    m.btnCancel = btnCancel
    btnCancel:SetScript("OnClick", function()
        input:ClearFocus()
        m:Hide()
    end)

    input:SetScript("OnEscapePressed", function()
        input:ClearFocus()
        m:Hide()
    end)

    Theme:ApplyBackdrop(m, "window")
    Theme:StyleButton(topCloseBtn, "default")
    Theme:StyleButton(btnSave, "primary")
    Theme:StyleButton(btnCancel, "default")

    modalFrame = m
    return m
end

local function OpenNoteModal(entry)
    local m = EnsureModal()
    if Theme.SetHelpButtonInfo then
        Theme:SetHelpButtonInfo(
            m.helpBtn,
            L["Help: Watchlist Character Note"],
            L["Saves a private local note for this player inside your SocialCentral Watchlist so you always remember why you added them."],
            L["Type any reminder (role, craft, trade, run notes) and click Save."],
            { target = m }
        )
    end
    m.title:SetText(L["Enter a character note for %s:"]:format(entry.displayName or ""))
    m.input:SetText(entry.note or "")
    m.btnSave:Show()
    Theme:SetButtonText(m.btnSave, L["Save"])

    local function Commit()
        if ns.Watchlist then
            ns.Watchlist:SetNote(entry.id, m.input:GetText() or "")
        end
        m.input:ClearFocus()
        m:Hide()
    end

    m.btnSave:SetScript("OnClick", Commit)
    m.input:SetScript("OnEnterPressed", Commit)
    m:Show()
    m.input:SetFocus()
    m.input:HighlightText()
end

local function OpenGroupModal(entry)
    local m = EnsureModal()
    if Theme.SetHelpButtonInfo then
        Theme:SetHelpButtonInfo(
            m.helpBtn,
            L["Help: Watchlist Group Tag"],
            L["Assigns a custom category tag so you can organize and filter Watchlist players by team, raid, or activity."],
            L["Enter a tag name like Raid, Dungeons, or Crafters and click Save. Clear the field to remove the tag."],
            { target = m }
        )
    end
    m.title:SetText(L["Enter a group tag for %s (e.g. Raid, M+, Friends):"]:format(entry.displayName or ""))
    m.input:SetText(entry.group or "")
    m.btnSave:Show()
    Theme:SetButtonText(m.btnSave, L["Save"])

    local function Commit()
        if ns.Watchlist then
            ns.Watchlist:SetGroup(entry.id, m.input:GetText() or "")
        end
        m.input:ClearFocus()
        m:Hide()
    end

    m.btnSave:SetScript("OnClick", Commit)
    m.input:SetScript("OnEnterPressed", Commit)
    m:Show()
    m.input:SetFocus()
    m.input:HighlightText()
end

local function OpenCopyModal(name, customTitle, noteText)
    local m = EnsureModal()
    if Theme.SetHelpButtonInfo then
        Theme:SetHelpButtonInfo(
            m.helpBtn,
            L["Help: Copy Text"],
            L["Highlights text or a safe game command so you can copy it cleanly without WoW blocking addon actions."],
            L["Press Ctrl+C while the text is selected, then paste it into chat or outside the game with Ctrl+V."],
            { target = m }
        )
    end
    local head = customTitle or (L["Copy Name"] .. " (Ctrl+C)")
    if noteText and noteText ~= "" then
        m:SetHeight(196)
        m.title:SetText(head .. "\n|cffc6ceda" .. noteText .. "|r")
        m.input:ClearAllPoints()
        m.input:SetPoint("TOPLEFT", m, "TOPLEFT", 16, -92)
        m.input:SetPoint("TOPRIGHT", m, "TOPRIGHT", -16, -92)
    else
        m.title:SetText(head)
    end
    m.input:SetMaxLetters(512)
    m.input:SetText(name or "")
    m.btnSave:Hide()
    if m.btnCancel then
        Theme:SetButtonText(m.btnCancel, L["Close"])
        Theme:AutoFitButton(m.btnCancel, 88, 20)
    end
    m.input:SetScript("OnEnterPressed", function()
        m.input:ClearFocus()
        m:Hide()
    end)
    m:Show()
    if m.Raise then m:Raise() end
    m.input:SetFocus()
    m.input:HighlightText()
end

function UI:OpenCopyModal(text, customTitle, noteText)
    OpenCopyModal(text, customTitle, noteText)
end

function UI:OpenConfirmModal(opts)
    if type(opts) ~= "table" or type(opts.onConfirm) ~= "function" then return end
    local m = UI._confirmModal
    if not m then
        m = CreateFrame("Frame", "SocialCentralConfirmModal", UIParent, "BackdropTemplate")
        m:SetSize(400, 168)
        m:SetPoint("CENTER")
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(840)
        if m.SetToplevel then m:SetToplevel(true) end
        m:EnableMouse(true)
        Theme:MakeMovable(m, { key = "modal_confirm_action" })
        m:Hide()
        if type(UISpecialFrames) == "table" then
            table.insert(UISpecialFrames, "SocialCentralConfirmModal")
        end

        m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        m.title:SetPoint("TOPLEFT", 16, -14)
        m.title:SetPoint("TOPRIGHT", -42, -14)
        m.title:SetJustifyH("LEFT")
        m.title:SetWordWrap(false)

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function() m:Hide() end)
        m.topCloseBtn = topCloseBtn

        m.desc = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        m.desc:SetPoint("TOPLEFT", 16, -46)
        m.desc:SetPoint("TOPRIGHT", -16, -46)
        m.desc:SetJustifyH("LEFT")
        m.desc:SetWordWrap(true)

        m.btnConfirm = Theme:CreateButton(m, 108, 24, L["Remove"], "danger")
        Theme:AutoFitButton(m.btnConfirm, 96, 16, 150)
        m.btnConfirm:SetPoint("BOTTOMRIGHT", -16, 14)

        m.btnCancel = Theme:CreateButton(m, 92, 24, L["Cancel"], "default")
        Theme:AutoFitButton(m.btnCancel, 84, 14, 136)
        m.btnCancel:SetPoint("RIGHT", m.btnConfirm, "LEFT", -8, 0)
        m.btnCancel:SetScript("OnClick", function() m:Hide() end)

        UI._confirmModal = m
    end

    if Theme and Theme.PrepareTopOverlayModal then
        Theme:PrepareTopOverlayModal(m, 840)
    else
        m:SetParent(UIParent)
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(840)
    end
    Theme:ApplyBackdrop(m, "window")
    Theme:StyleButton(m.topCloseBtn, "default")
    Theme:StyleButton(m.btnCancel, "default")
    Theme:SetButtonText(m.btnCancel, L["Cancel"])
    Theme:AutoFitButton(m.btnCancel, 84, 18)

    local variant = opts.confirmVariant or "danger"
    local confirmLabel = opts.confirmText or L["Remove"]
    Theme:SetButtonText(m.btnConfirm, confirmLabel)
    Theme:AutoFitButton(m.btnConfirm, 96, 20)
    Theme:StyleButton(m.btnConfirm, variant)
    if Theme and Theme.SyncSubtreeLayers then
        Theme:SyncSubtreeLayers(m, 8)
    end

    m.title:SetText(opts.title or L["Confirm Action"])
    m.desc:SetText(opts.message or "")
    local descHeight = (m.desc.GetStringHeight and m.desc:GetStringHeight()) or 28
    m:SetHeight(math.max(152, math.min(260, math.floor(descHeight + 104))))

    local fn = opts.onConfirm
    m.btnConfirm:SetScript("OnClick", function()
        m:Hide()
        fn()
    end)
    m:Show()
    if m.Raise then m:Raise() end
end

function UI:ConfirmResetInstances()
    UI:OpenConfirmModal({
        title = L["Reset Instances"],
        message = L["Are you sure you want to reset all dungeon instances now?"],
        confirmText = L["Reset"],
        confirmVariant = "danger",
        onConfirm = function()
            if ns.Group and ns.Group.ResetDungeonInstances then
                ns.Group:ResetDungeonInstances()
            end
        end,
    })
end

local function PrepareTopOverlayModal(m, minLevel)
    if Theme and Theme.PrepareTopOverlayModal then
        Theme:PrepareTopOverlayModal(m, minLevel)
        return
    end
    if not m then return end
    if m.GetParent and m:GetParent() ~= UIParent then
        m:SetParent(UIParent)
    end
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(math.max(minLevel or 840, 820))
    if m.SetToplevel then m:SetToplevel(true) end
    if m.SetClampedToScreen then m:SetClampedToScreen(true) end
    m:EnableMouse(true)
    if not m._solidOpaqueBg and m.CreateTexture then
        local bg = m:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetAllPoints(m)
        bg:SetTexture(WHITE8X8)
        m._solidOpaqueBg = bg
    end
    if m._solidOpaqueBg then
        local pal = Theme and Theme.GetPalette and Theme:GetPalette()
        local wBg = (pal and pal.windowBg) or { 0.08, 0.075, 0.07, 1.0 }
        m._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
    end
    if m.topCloseBtn and m.topCloseBtn.SetFrameLevel then
        m.topCloseBtn:SetFrameLevel((m:GetFrameLevel() or 840) + 12)
    end
    if m.topClose and m.topClose.SetFrameLevel then
        m.topClose:SetFrameLevel((m:GetFrameLevel() or 840) + 12)
    end
end

function UI:OpenWatchlistDisambiguation(entryId)
    if not (ns.Watchlist and entryId) then return end
    local entry = ns.Watchlist:GetEntry(entryId)
    if not entry or type(entry.ambiguousChoices) ~= "table" or #entry.ambiguousChoices == 0 then
        return
    end

    if not disambigModalFrame then
        local m = CreateFrame("Frame", "SocialCentralDisambigModal", UIParent, "BackdropTemplate")
        m:SetSize(410, 260)
        m:SetPoint("CENTER")
        PrepareTopOverlayModal(m, 845)
        Theme:MakeMovable(m, { key = "modal_disambig" })
        m:Hide()
        if type(UISpecialFrames) == "table" then
            table.insert(UISpecialFrames, "SocialCentralDisambigModal")
        end

        m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        m.title:SetPoint("TOPLEFT", 16, -14)
        m.title:SetPoint("TOPRIGHT", -42, -14)
        m.title:SetJustifyH("LEFT")
        m.title:SetWordWrap(true)

        local topClose = Theme:CreateButton(m, 22, 20, "X", "default")
        topClose:SetPoint("TOPRIGHT", -10, -10)
        topClose:SetScript("OnClick", function() m:Hide() end)
        m.topClose = topClose

        m.rows = {}
        for i = 1, 8 do
            local rb = Theme:CreateButton(m, 378, 24, "", "default")
            rb:SetPoint("TOPLEFT", 16, -46 - (i - 1) * 27)
            rb:SetPoint("TOPRIGHT", -16, -46 - (i - 1) * 27)
            rb:SetScript("OnClick", function(selfBtn)
                if selfBtn._choice and m._entryId and ns.Watchlist and ns.Watchlist.ResolveDisambiguation then
                    ns.Watchlist:ResolveDisambiguation(m._entryId, selfBtn._choice.fullName, selfBtn._choice)
                end
                m:Hide()
            end)
            rb:Hide()
            m.rows[i] = rb
        end

        disambigModalFrame = m
    end

    local m = disambigModalFrame
    PrepareTopOverlayModal(m, 845)
    m._entryId = entry.id or entryId
    Theme:ApplyBackdrop(m, "window")
    Theme:StyleButton(m.topClose, "default")
    m.topClose:SetFrameLevel((m:GetFrameLevel() or 125) + 12)
    m.title:SetText(L["Multiple characters match '%s'; select the exact FirstName Surname:"]:format(entry.displayName or entry.firstName or "?"))

    local dirByLookup = ns.Store and ns.Store.socialDirectoryByLookup
    local choices = {}
    for _, c in ipairs(entry.ambiguousChoices) do
        local dirRow = c.lookupKey and dirByLookup and dirByLookup[c.lookupKey]
        local isGuild = (dirRow and dirRow.sources and dirRow.sources.guild == true) or (Compat.IsGuildMember and Compat.IsGuildMember(c.fullName))
        local isFriend = dirRow and dirRow.sources and (dirRow.sources.friend == true or dirRow.sources.bnet == true)
        choices[#choices + 1] = {
            data = c,
            isGuild = isGuild == true,
            isFriend = isFriend == true,
        }
    end
    table.sort(choices, function(a, b)
        if a.isGuild ~= b.isGuild then return a.isGuild end
        if a.isFriend ~= b.isFriend then return a.isFriend end
        return (a.data.level or 0) > (b.data.level or 0)
    end)

    local shown = math.min(#choices, 8)
    for i = 1, 8 do
        local rb = m.rows[i]
        if i <= shown then
            local rec = choices[i]
            local c = rec.data
            rb._choice = c
            local hex = Compat.ClassHex(c.classFile)
            local details = {}
            if rec.isGuild then details[#details + 1] = "|cff40d973[" .. L["Guild"] .. "]|r" end
            if rec.isFriend then details[#details + 1] = "|cff59c7ff[" .. L["Friend"] .. "]|r" end
            if c.level and c.level > 0 then details[#details + 1] = L["Lv %d"]:format(c.level) end
            if c.guild and c.guild ~= "" then details[#details + 1] = "<" .. c.guild .. ">" end
            if c.area and c.area ~= "" then details[#details + 1] = c.area end
            local suffix = (#details > 0) and ("  |cff9da7b5" .. table.concat(details, " · ") .. "|r") or ""
            Theme:StyleButton(rb, "default")
            Theme:SetButtonText(rb, hex .. (c.fullName or "?") .. "|r" .. suffix)
            rb:Show()
        else
            rb._choice = nil
            rb:Hide()
        end
    end
    m:SetHeight(64 + shown * 27)
    m:Show()
    if m.Raise then m:Raise() end
end

local function OpenAddFriendModal()
    local m = EnsureModal()
    if Theme.SetHelpButtonInfo then
        Theme:SetHelpButtonInfo(
            m.helpBtn,
            L["Help: Add WoW Friend"],
            L["Adds a same-faction character directly to your official WoW Friends list (pre-filled if you currently target a friendly player)."],
            L["Enter the character name (including two-word names when applicable) and click Add. Unavailable during combat."],
            { target = m }
        )
    end
    m.title:SetText(L["Add WoW Character Friend (Name or Name Surname):"])
    local prefill = ""
    if UnitExists and UnitExists("target") and UnitIsPlayer and ns.Safe and ns.Safe.Bool(ns.Safe.Call(UnitIsPlayer, "target")) == true then
        local guid = ns.Safe.String(ns.Safe.Call(UnitGUID, "target"))
        local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName("target", guid, nil, true)
        local cand = (resolved and resolved.fullName) or ns.Safe.String(ns.Safe.Call(UnitName, "target"))
        if cand and not Compat.IsMe(cand, guid) then
            prefill = cand
        end
    end
    m.input:SetMaxLetters(48)
    m.input:SetText(prefill)
    Theme:SetButtonText(m.btnSave, L["Add"])
    Theme:AutoFitButton(m.btnSave, 88, 20)

    local function Commit()
        local raw = Compat.Trim(m.input:GetText() or "")
        if raw ~= "" and Compat.AddCharacterFriend then
            local ok = Compat.AddCharacterFriend(raw)
            if not ok then
                ns:Print("%s", L["Cannot modify friends while in combat."])
            end
        end
        m.input:ClearFocus()
        m:Hide()
    end
    m.btnSave:SetScript("OnClick", Commit)
    m.input:SetScript("OnEnterPressed", Commit)
    m:Show()
    m.input:SetFocus()
    if prefill ~= "" then
        m.input:HighlightText()
    end
end

local function OpenNativeFriendNoteModal(item)
    if not item then return end
    local isChar = item.sources and item.sources.friend == true
    local isBNet = item.sources and item.sources.bnet == true and item.bnetAccountID ~= nil
    if not isChar and not isBNet then return end

    local m = EnsureModal()
    if Theme.SetHelpButtonInfo then
        Theme:SetHelpButtonInfo(
            m.helpBtn,
            L["Help: Blizzard Friend Note"],
            L["Updates the official note stored on your WoW or Battle.net Friends list for this contact."],
            L["Type the new note and click Save. Unavailable while you are in combat."],
            { target = m }
        )
    end
    local shownName = item.displayName or item.bnetName or "?"
    if isChar then
        m.title:SetText(L["Edit Blizzard Friend Note for %s:"]:format(shownName))
        m.input:SetMaxLetters(48)
        m.input:SetText(item.friendNote or "")
    else
        m.title:SetText(L["Edit Battle.net Note for %s:"]:format(item.bnetName or shownName))
        m.input:SetMaxLetters(120)
        m.input:SetText(item.bnetNote or "")
    end

    local function Commit()
        local nextNote = m.input:GetText() or ""
        local ok = false
        if isChar and Compat.SetCharacterFriendNote then
            ok = Compat.SetCharacterFriendNote(shownName, nextNote)
        elseif isBNet and Compat.SetBNetFriendNote then
            ok = Compat.SetBNetFriendNote(item.bnetAccountID, nextNote)
        end
        if not ok then
            ns:Print("%s", L["Cannot update Blizzard friend note while in combat."])
        end
        m.input:ClearFocus()
        m:Hide()
    end
    m.btnSave:SetScript("OnClick", Commit)
    m.input:SetScript("OnEnterPressed", Commit)
    m:Show()
    m.input:SetFocus()
    m.input:HighlightText()
end

local function OpenRemoveFriendConfirmModal(item)
    if not (item and item.sources and item.sources.friend) then return end
    local targetName = item.displayName or item.name
    if not targetName or targetName == "" then return end

    local m = EnsureModal()
    if Theme.SetHelpButtonInfo then
        Theme:SetHelpButtonInfo(
            m.helpBtn,
            L["Help: Remove WoW Friend"],
            L["Asks for confirmation before removing this character from your official WoW Friends list."],
            L["Click Remove to confirm or Cancel to keep this friend. Local SocialCentral notes/aliases stay safe unless you remove them too."],
            { target = m }
        )
    end
    m:SetHeight(148)
    m.title:SetText(L["Remove %s from your WoW Character Friends list?"]:format(targetName))
    m.input:ClearFocus()
    m.input:Hide()
    Theme:SetButtonText(m.btnSave, L["Remove"])
    Theme:AutoFitButton(m.btnSave, 92, 20)
    Theme:StyleButton(m.btnSave, "danger")

    m.btnSave:SetScript("OnClick", function()
        if Compat.RemoveCharacterFriend then
            local ok = Compat.RemoveCharacterFriend(targetName)
            if not ok then
                ns:Print("%s", L["Cannot modify friends while in combat."])
            end
        end
        m:Hide()
    end)
    m:Show()
    if m.Raise then m:Raise() end
end

local TAG_LABELS = {
    NONE = L["No Status"],
    LFG = L["LFG (Looking for Group)"],
    MPLUS = L["Dungeons"],
    RAID = L["Raid Ready"],
    PVP = L["PvP / Arena"],
    LEVELING = L["Leveling / Questing"],
    CRAFTING = L["Crafting / Professions"],
    BUSY = L["Busy"],
}

local CAT_LABELS = {
    DUNGEON = L["Dungeons"],
    QUEST = L["Group Quest"],
    RAID = L["Raid"],
    BOSS = L["World Boss"],
    PVP = L["PvP"],
    GUILD = L["Guild Event"],
}

local ROLE_LABELS = {
    TANK = L["Tank"],
    HEALER = L["Healer"],
    DPS = L["DPS"],
    MAYBE = L["Maybe"],
    DECLINE = L["Leave / Decline"],
}

local function OpenClanNoteModal(currentTag, currentNote)
    local m = EnsureModal()
    if Theme.SetHelpButtonInfo then
        Theme:SetHelpButtonInfo(
            m.helpBtn,
            L["Help: Clan Status Note"],
            L["Adds an optional short note next to your current Guild Hub status (such as Looking for Tank or Crafting Enchants)."],
            L["Write a brief message and click Save to share it with online guildmates using Guild Sync."],
            { target = m }
        )
    end
    Theme:ApplyBackdrop(m, "window")
    m.title:SetText(L["Set Clan Status Note (optional):"])
    m.input:SetText(currentNote or "")
    m.btnSave:Show()
    Theme:SetButtonText(m.btnSave, L["Save"])

    local function Commit()
        if ns.Clan then
            ns.Clan:SetMyStatus(currentTag or "LFG", m.input:GetText() or "")
        end
        m.input:ClearFocus()
        m:Hide()
    end

    m.btnSave:SetScript("OnClick", Commit)
    m.input:SetScript("OnEnterPressed", Commit)
    m:Show()
    m.input:SetFocus()
    m.input:HighlightText()
end

local function FlowButtonGroup(container, btnList, gapX, gapY, startY)
    if not container or not btnList or #btnList == 0 then
        return startY or 0
    end
    local avail = math.floor((container:GetWidth() or 0) + 0.5)
    if avail <= 20 then
        avail = 320
    end
    local x, y, rowH = 0, math.floor((startY or 0) + 0.5), 22
    for _, b in ipairs(btnList) do
        if b and b:IsShown() then
            local bw = math.floor((b._scAutoFitW or b:GetWidth() or 60) + 0.5)
            local helpExtra = b._pairedHelp and (math.floor((b._pairedHelp:GetWidth() or 18) + 0.5) + 4) or 0
            local unitW = bw + helpExtra
            if x > 0 and (x + unitW) > avail then
                x = 0
                y = y - (rowH + (gapY or 4))
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
            if b._pairedHelp then
                b._pairedHelp:ClearAllPoints()
                b._pairedHelp:SetPoint("LEFT", b, "RIGHT", 4, 0)
            end
            x = x + unitW + (gapX or 5)
        end
    end
    return math.abs(y) + rowH
end

local function OpenMotdModal()
    local m = EnsureModal()
    if Theme.SetHelpButtonInfo then
        Theme:SetHelpButtonInfo(
            m.helpBtn,
            L["Help: Guild Message of the Day"],
            L["Updates your Guild's official Message of the Day shown whenever guild members log in."],
            L["Edit the announcement text below and click Save (requires guild MOTD permission)."],
            { target = m }
        )
    end
    Theme:ApplyBackdrop(m, "window")
    m.title:SetText(L["Edit Guild Message of the Day (MOTD):"])
    local info = ns.Store and ns.Store.guildInfo
    m.input:SetText((info and info.motd) or "")
    m.btnSave:Show()
    Theme:SetButtonText(m.btnSave, L["Save"])

    local function Commit()
        if ns.Clan then
            ns.Clan:SetGuildMOTD(m.input:GetText() or "")
        end
        m.input:ClearFocus()
        m:Hide()
    end

    m.btnSave:SetScript("OnClick", Commit)
    m.input:SetScript("OnEnterPressed", Commit)
    m:Show()
    m.input:SetFocus()
    m.input:HighlightText()
end

local function OpenGuildInviteModal()
    if ns.Clan and ns.Clan.CanInviteToGuild and not ns.Clan:CanInviteToGuild() then
        ns:Print(L["Your guild rank does not have permission to invite members."])
        return
    end
    local m = EnsureModal()
    if Theme.SetHelpButtonInfo then
        Theme:SetHelpButtonInfo(
            m.helpBtn,
            L["Help: Safe Guild Invite"],
            L["Prepares a safe /ginvite chat command (pre-filled from your current target if friendly and not in your guild)."],
            L["Confirm the player name and click Generate /ginvite, then press Ctrl+C and paste into WoW chat."],
            { target = m }
        )
    end
    Theme:ApplyBackdrop(m, "window")
    m.title:SetText(L["Invite to Guild (Safe /ginvite Command):"])
    local prefill = ""
    if UnitExists and UnitIsPlayer and UnitIsFriend
        and Safe.Value(Safe.Call(UnitExists, "target")) == true
        and Safe.Value(Safe.Call(UnitIsPlayer, "target")) == true
        and Safe.Value(Safe.Call(UnitIsFriend, "player", "target")) == true
        and not (UnitIsUnit and Safe.Value(Safe.Call(UnitIsUnit, "player", "target")) == true)
    then
        local tGuid = Safe.String(Safe.Call(UnitGUID, "target"))
        local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName("target", tGuid, nil, true)
        local tName = (resolved and resolved.fullName) or Safe.String(Safe.Call(UnitName, "target"))
        if tName and tName ~= "" and not (Compat.IsGuildMember and Compat.IsGuildMember(tName, tGuid, tName)) then
            prefill = tName
        end
    end
    m.input:SetText(prefill)
    m.btnSave:Show()
    Theme:SetButtonText(m.btnSave, L["Generate /ginvite"])
    Theme:AutoFitButton(m.btnSave, 112, 20)

    local function Commit()
        local raw = Compat.CleanInput(m.input:GetText() or "")
        if not raw or raw == "" then return end
        local clean = (Compat.FormatForeverTarget and Compat.FormatForeverTarget(raw)) or raw
        if not clean or clean == "" then return end
        local slashTarget = clean:gsub("%s+", "-")
        m.input:ClearFocus()
        m:Hide()
        OpenCopyModal(
            "/ginvite " .. slashTarget,
            L["Guild Invite Command (Ctrl+C)"],
            L["Blizzard blocks addons from sending guild invites directly. Copy the command below (Ctrl+C), paste it in chat (Ctrl+V), and press Enter."]
        )
    end

    m.btnSave:SetScript("OnClick", Commit)
    m.input:SetScript("OnEnterPressed", Commit)
    m:Show()
    m.input:SetFocus()
    if prefill ~= "" then
        m.input:HighlightText()
    end
end

local function OpenPublicNoteModal(memberItem)
    if not memberItem or not memberItem.lookupKey then return end
    local m = EnsureModal()
    if Theme.SetHelpButtonInfo then
        Theme:SetHelpButtonInfo(
            m.helpBtn,
            L["Help: Guild Public Note"],
            L["Edits this member's official Guild Public Note (visible to the entire guild, up to 31 characters)."],
            L["Enter the note and click Save (requires guild permission to edit public notes)."],
            { target = m }
        )
    end
    Theme:ApplyBackdrop(m, "window")
    m.title:SetText(L["Edit Guild Public Note (%s):"]:format(memberItem.displayName or "?"))
    m.input:SetText(memberItem.note or "")
    m.btnSave:Show()
    Theme:SetButtonText(m.btnSave, L["Save"])

    local function Commit()
        if ns.Clan and ns.Clan.SetMemberPublicNote then
            ns.Clan:SetMemberPublicNote(memberItem.lookupKey, m.input:GetText() or "")
        end
        m.input:ClearFocus()
        m:Hide()
    end

    m.btnSave:SetScript("OnClick", Commit)
    m.input:SetScript("OnEnterPressed", Commit)
    m:Show()
    m.input:SetFocus()
    m.input:HighlightText()
end

local function ReflowEventModal()
    if not eventModalFrame or not eventModalFrame._catHolder then return end
    local m = eventModalFrame
    local catsH = FlowButtonGroup(m._catHolder, m._catBtnOrder or {}, 5, 4, 0)
    m._catHolder:SetHeight(math.max(22, catsH))
    local presH = m._presetHolder and FlowButtonGroup(m._presetHolder, m._presetBtns or {}, 5, 4, 0) or 22
    if m._presetHolder then
        m._presetHolder:SetHeight(math.max(22, presH))
    end
end

local function OpenEventModal(prefillTitle, prefillWhen, prefillCat)
    if not eventModalFrame then
        local m = CreateFrame("Frame", "SocialCentralEventModal", UIParent, "BackdropTemplate")
        m:SetSize(536, 472)
        m:SetPoint("CENTER")
        PrepareTopOverlayModal(m, 840)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        Theme:MakeMovable(m, { key = "modal_event" })
        table.insert(UISpecialFrames, "SocialCentralEventModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -36, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["Create Clan Event Call"])

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            if m.titleInput then m.titleInput:ClearFocus() end
            if m.whenInput then m.whenInput:ClearFocus() end
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        m.helpBtn = AddHelp(
            m,
            topCloseBtn,
            L["Help: Create Clan Event Call"],
            L["Schedules a Guild or Allied Clan event with presets, role slots (Tank/Healer/DPS), and optional in-game Blizzard Guild Calendar sync."],
            L["Pick a category or quick preset, enter title & date/time, set slot caps or Alliance sharing, and click Publish Event."],
            "RIGHT",
            "LEFT",
            -4,
            0,
            { target = m }
        )
        title:SetPoint("TOPRIGHT", m.helpBtn or topCloseBtn, "LEFT", -6, 0)

        local catLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        catLbl:SetPoint("TOPLEFT", 16, -42)
        catLbl:SetPoint("TOPRIGHT", -16, -42)
        catLbl:SetJustifyH("LEFT")
        catLbl:SetText(L["Category:"])

        local catHolder = CreateFrame("Frame", nil, m)
        catHolder:SetPoint("TOPLEFT", catLbl, "BOTTOMLEFT", 0, -4)
        catHolder:SetPoint("TOPRIGHT", m, "TOPRIGHT", -16, 0)
        catHolder:SetHeight(24)
        m._catHolder = catHolder

        m._cat = "DUNGEON"
        m._catBtns = {}
        m._catBtnOrder = {}
        local cats = { "DUNGEON", "QUEST", "RAID", "BOSS", "PVP", "GUILD" }
        for _, cId in ipairs(cats) do
            local btn = Theme:CreateButton(catHolder, 72, 22, CAT_LABELS[cId] or cId, "default")
            Theme:AutoFitButton(btn, 58, 12, 130)
            btn:SetScript("OnClick", function()
                m._cat = cId
                for _, item in ipairs(m._catBtns) do
                    Theme:SetButtonActive(item.btn, m._cat == item.id, "default")
                end
            end)
            table.insert(m._catBtns, { id = cId, btn = btn })
            table.insert(m._catBtnOrder, btn)
        end

        local presetLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        presetLbl:SetPoint("TOPLEFT", catHolder, "BOTTOMLEFT", 0, -8)
        presetLbl:SetPoint("TOPRIGHT", m, "TOPRIGHT", -16, 0)
        presetLbl:SetJustifyH("LEFT")
        presetLbl:SetText(L["Quick Activity Presets (from Game / Dungeon):"])

        local presetHolder = CreateFrame("Frame", nil, m)
        presetHolder:SetPoint("TOPLEFT", presetLbl, "BOTTOMLEFT", 0, -4)
        presetHolder:SetPoint("TOPRIGHT", m, "TOPRIGHT", -16, 0)
        presetHolder:SetHeight(24)
        m._presetHolder = presetHolder
        m._presetBtns = {}

        local titleLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        titleLbl:SetPoint("TOPLEFT", presetHolder, "BOTTOMLEFT", 0, -8)
        titleLbl:SetPoint("TOPRIGHT", m, "TOPRIGHT", -16, 0)
        titleLbl:SetJustifyH("LEFT")
        titleLbl:SetWordWrap(false)
        titleLbl:SetText(L["Event Title (e.g. Blackrock Depths, Molten Core):"])

        local titleInput = Theme:CreateEditBox(m, { height = 24, maxLetters = 40 })
        titleInput:SetPoint("TOPLEFT", titleLbl, "BOTTOMLEFT", 0, -4)
        titleInput:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        m.titleInput = titleInput

        local whenLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        whenLbl:SetPoint("TOPLEFT", titleInput, "BOTTOMLEFT", 0, -8)
        whenLbl:SetPoint("TOPRIGHT", m, "TOPRIGHT", -16, 0)
        whenLbl:SetJustifyH("LEFT")
        whenLbl:SetWordWrap(false)
        whenLbl:SetText(L["When (e.g. Now, Today 21:00):"])

        local whenInput = Theme:CreateEditBox(m, { width = 148, height = 24, maxLetters = 24 })
        whenInput:SetPoint("TOPLEFT", whenLbl, "BOTTOMLEFT", 0, -4)
        m.whenInput = whenInput

        m._timeBtns = {}
        local prevTB = whenInput
        for _, tm in ipairs({
            { label = L["Now"], val = L["Now"], h = 20 },
            { label = "20:00", val = "20:00", h = 20 },
            { label = "21:00", val = "21:00", h = 21 },
            { label = "22:00", val = "22:00", h = 22 },
            { label = L["Tomorrow"], val = L["Tomorrow 20:00"], h = 20 },
        }) do
            local tb = Theme:CreateButton(m, 50, 22, tm.label, "default")
            Theme:AutoFitButton(tb, 44, 10, 84)
            tb:SetPoint("LEFT", prevTB, "RIGHT", 4, 0)
            tb:SetScript("OnClick", function()
                whenInput:SetText(tm.val)
                m._calHour = tm.h
            end)
            table.insert(m._timeBtns, tb)
            prevTB = tb
        end

        local slotsLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slotsLbl:SetPoint("TOPLEFT", whenInput, "BOTTOMLEFT", 0, -10)
        slotsLbl:SetPoint("TOPRIGHT", m, "TOPRIGHT", -16, 0)
        slotsLbl:SetJustifyH("LEFT")
        slotsLbl:SetWordWrap(false)
        slotsLbl:SetText(L["Role Slots & Min Level (optional):"])

        local slotsRow = CreateFrame("Frame", nil, m)
        slotsRow:SetPoint("TOPLEFT", slotsLbl, "BOTTOMLEFT", 0, -4)
        slotsRow:SetPoint("TOPRIGHT", m, "TOPRIGHT", -16, 0)
        slotsRow:SetHeight(24)

        local function MakeSmallNumInput(anchorTo, lblText)
            local l = slotsRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if anchorTo then
                l:SetPoint("LEFT", anchorTo, "RIGHT", 12, 0)
            else
                l:SetPoint("LEFT", slotsRow, "LEFT", 0, 0)
            end
            l:SetText(lblText)
            local box = Theme:CreateEditBox(slotsRow, { width = 38, height = 22, numeric = true, maxLetters = 2 })
            box:SetJustifyH("CENTER")
            box:SetPoint("LEFT", l, "RIGHT", 5, 0)
            box:SetScript("OnEscapePressed", function() m:Hide() end)
            return box
        end

        m.tankIn = MakeSmallNumInput(nil, "T:")
        m.healIn = MakeSmallNumInput(m.tankIn, "H:")
        m.dpsIn = MakeSmallNumInput(m.healIn, "D:")
        m.lvlIn = MakeSmallNumInput(m.dpsIn, L["Min Lv:"])

        local roleLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        roleLbl:SetPoint("TOPLEFT", slotsRow, "BOTTOMLEFT", 0, -10)
        roleLbl:SetText(L["My Role:"])
        m._myRole = "DPS"
        m._roleBtns = {}
        local prevRB = roleLbl
        for _, rId in ipairs({ "TANK", "HEALER", "DPS" }) do
            local rb = Theme:CreateButton(m, 64, 20, ROLE_LABELS[rId] or rId, "default")
            Theme:AutoFitButton(rb, 54, 12, 92)
            rb:SetPoint("LEFT", prevRB, "RIGHT", 6, 0)
            rb:SetScript("OnClick", function()
                m._myRole = rId
                for _, item in ipairs(m._roleBtns) do
                    Theme:SetButtonActive(item.btn, m._myRole == item.id, "default")
                end
            end)
            table.insert(m._roleBtns, { id = rId, btn = rb })
            prevRB = rb
        end

        local calCb = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
        calCb:SetSize(22, 22)
        calCb:SetPoint("TOPLEFT", roleLbl, "BOTTOMLEFT", -2, -8)
        local calLbl = calCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        calLbl:SetPoint("LEFT", calCb, "RIGHT", 4, 0)
        calLbl:SetText(L["Also post to WoW Guild Calendar (Officers)"])
        m.calCheck = calCb
        AddHelp(m, calLbl, L["Help: WoW Guild Calendar"], L["Attempts to register a guild signup event in Blizzard's native in-game Calendar if your guild rank allows it."], L["All SocialCentral Clan events sync safely in the addon even without officer calendar permission."])

        local gchatCb = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
        gchatCb:SetSize(22, 22)
        gchatCb:SetPoint("TOPLEFT", calCb, "BOTTOMLEFT", 0, -2)
        local gchatLbl = gchatCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        gchatLbl:SetPoint("LEFT", gchatCb, "RIGHT", 4, 0)
        gchatLbl:SetText(L["Also pre-fill Guild Chat (/g) on Save"])
        m.gchatCheck = gchatCb

        local allyCb = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
        allyCb:SetSize(22, 22)
        allyCb:SetPoint("TOPLEFT", gchatCb, "BOTTOMLEFT", 0, -2)
        local allyLbl = allyCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        allyLbl:SetPoint("LEFT", allyCb, "RIGHT", 4, 0)
        allyLbl:SetText(L["Also share with mutually authorized Allied Guilds"])
        m.allyShareCheck = allyCb
        m.allyShareLbl = allyLbl
        AddHelp(
            m,
            allyLbl,
            L["Help: Shared Allied Guild Events"],
            L["Shares this Event Call and its Tank/Healer/DPS signups with Allied Guilds that have mutually authorized event sharing."],
            L["Requires both your guild leadership (or delegated Alliance Manager) and the Allied Guild's leadership to enable event sharing in Diplomacy."]
        )

        local syncTip = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        syncTip:SetPoint("BOTTOMLEFT", 16, 18)
        syncTip:SetJustifyH("LEFT")
        syncTip:SetWordWrap(true)
        m.syncTip = syncTip

        local btnSave = Theme:CreateButton(m, 96, 24, L["Save"], "primary")
        Theme:AutoFitButton(btnSave, 90, 20)
        btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnSave = btnSave

        local btnCancel = Theme:CreateButton(m, 96, 24, L["Cancel"], "default")
        Theme:AutoFitButton(btnCancel, 90, 20)
        btnCancel:SetPoint("RIGHT", btnSave, "LEFT", -8, 0)
        m.btnCancel = btnCancel
        syncTip:SetPoint("RIGHT", btnCancel, "LEFT", -8, 0)

        btnCancel:SetScript("OnClick", function()
            titleInput:ClearFocus()
            whenInput:ClearFocus()
            m:Hide()
        end)
        titleInput:SetScript("OnEscapePressed", function() m:Hide() end)
        whenInput:SetScript("OnEscapePressed", function() m:Hide() end)

        local function SubmitEvent()
            if ns.Clan then
                local titleStr = titleInput:GetText() or ""
                local whenStr = whenInput:GetText() or ""
                local allowAllies = (not m.allyShareCheck or m.allyShareCheck:GetChecked()) and true or false
                local ok, createdEvt = ns.Clan:CreateEventCall(
                    m._cat,
                    titleStr,
                    whenStr,
                    m.tankIn:GetText(),
                    m.healIn:GetText(),
                    m.dpsIn:GetText(),
                    m.lvlIn:GetText(),
                    m._myRole,
                    allowAllies
                )
                if ok then
                    if m.calCheck and m.calCheck:GetChecked() then
                        local dayOff, calH, calM = 0, (m._calHour or 20), 0
                        if ns.Clan.ParseEventWhenDateTime then
                            local parsedOff, parsedH, parsedM = ns.Clan:ParseEventWhenDateTime(whenStr)
                            dayOff = parsedOff or 0
                            calH = parsedH or calH
                            calM = parsedM or 0
                        else
                            calH = tonumber(whenStr:match("^(%d+)%s*:")) or calH
                        end
                        local calOk, calErr = ns.Clan:PublishGameCalendarEvent(m._cat, titleStr, whenStr, dayOff, calH, calM)
                        if calOk then
                            ns:Print(L["Posted event to both SocialCentral Clan and WoW Guild Calendar."])
                        elseif calErr then
                            ns:Print(calErr)
                        end
                    end
                    local shareGchat = m.gchatCheck and m.gchatCheck:GetChecked()
                    titleInput:ClearFocus()
                    whenInput:ClearFocus()
                    m:Hide()
                    if shareGchat and createdEvt and ns.Clan.ShareEventToGuildChat then
                        ns.Clan:ShareEventToGuildChat(createdEvt)
                    end
                end
            end
        end
        btnSave:SetScript("OnClick", SubmitEvent)
        whenInput:SetScript("OnEnterPressed", SubmitEvent)

        eventModalFrame = m
    end

    -- Refresh dynamic Quick Presets from live Game Summary
    for _, b in ipairs(eventModalFrame._presetBtns) do
        b:Hide()
    end
    wipe(eventModalFrame._presetBtns)
    if ns.Clan then
        local presets = ns.Clan:GetDungeonQuickPresets()
        for idx = 1, math.min(5, #presets) do
            local pr = presets[idx]
            local pb = Theme:CreateButton(eventModalFrame._presetHolder, 90, 20, pr.label, "default")
            Theme:AutoFitButton(pb, 60, 12, 170)
            pb:SetScript("OnClick", function()
                eventModalFrame._cat = pr.category or "DUNGEON"
                eventModalFrame.titleInput:SetText(pr.label)
                if pr.category == "DUNGEON" then
                    if eventModalFrame.tankIn:GetText() == "" then eventModalFrame.tankIn:SetText("1") end
                    if eventModalFrame.healIn:GetText() == "" then eventModalFrame.healIn:SetText("1") end
                    if eventModalFrame.dpsIn:GetText() == "" then eventModalFrame.dpsIn:SetText("3") end
                elseif pr.category == "QUEST" then
                    local sg = tonumber(pr.suggestedGroup) or 0
                    if sg >= 2 and eventModalFrame.dpsIn:GetText() == "" then
                        eventModalFrame.dpsIn:SetText(tostring(sg))
                    end
                elseif pr.category == "RAID" then
                    if eventModalFrame.tankIn:GetText() == "" then eventModalFrame.tankIn:SetText("2") end
                    if eventModalFrame.healIn:GetText() == "" then eventModalFrame.healIn:SetText("4") end
                    if eventModalFrame.dpsIn:GetText() == "" then eventModalFrame.dpsIn:SetText("14") end
                end
                for _, item in ipairs(eventModalFrame._catBtns) do
                    Theme:SetButtonActive(item.btn, eventModalFrame._cat == item.id, "default")
                end
            end)
            table.insert(eventModalFrame._presetBtns, pb)
        end
    end

    PrepareTopOverlayModal(eventModalFrame, 840)
    Theme:ApplyBackdrop(eventModalFrame, "window")
    Theme:StyleButton(eventModalFrame.topCloseBtn, "default")
    Theme:StyleButton(eventModalFrame.btnSave, "primary")
    Theme:StyleButton(eventModalFrame.btnCancel, "default")
    if type(prefillCat) == "string" and CAT_LABELS[prefillCat] then
        eventModalFrame._cat = prefillCat
    end
    for _, item in ipairs(eventModalFrame._catBtns) do
        Theme:StyleButton(item.btn, "default")
        Theme:SetButtonActive(item.btn, eventModalFrame._cat == item.id, "default")
    end
    for _, tb in ipairs(eventModalFrame._timeBtns or {}) do
        Theme:StyleButton(tb, "default")
    end

    local defaultRole = ns.Clan and ns.Clan:GetMySpecAndRole() or "DPS"
    eventModalFrame._myRole = defaultRole
    for _, item in ipairs(eventModalFrame._roleBtns or {}) do
        Theme:StyleButton(item.btn, "default")
        Theme:SetButtonActive(item.btn, eventModalFrame._myRole == item.id, "default")
    end

    local sum = ns.Clan and ns.Clan:GetPlayerGameSummary()
    eventModalFrame.calCheck:SetChecked(false)
    eventModalFrame.calCheck:SetEnabled((sum and sum.canEditCalendar) and true or false)
    if eventModalFrame.gchatCheck then
        eventModalFrame.gchatCheck:SetChecked(false)
    end
    local mutualList = (ns.Clan and ns.Clan.GetMutuallyAuthorizedAlliedGuilds) and ns.Clan:GetMutuallyAuthorizedAlliedGuilds() or {}
    if eventModalFrame.allyShareCheck then
        eventModalFrame.allyShareCheck:SetChecked(true)
    end
    if eventModalFrame.allyShareLbl then
        eventModalFrame.allyShareLbl:SetText(string.format(L["Also share with mutually authorized Allied Guilds (%d active)"], #mutualList))
    end
    if eventModalFrame.syncTip then
        local syncOn = ns.db and ns.db.settings and ns.db.settings.clanSync == true
        eventModalFrame.syncTip:SetText(syncOn
            and ("|cff3fb950" .. L["Guild Sync is ON — shares automatically with [SC] peers."] .. "|r")
            or ("|cffffd24d" .. L["Guild Sync is OFF — saved locally (use '/g' below to announce to everyone)."] .. "|r"))
    end
    eventModalFrame._calHour = 20
    eventModalFrame.titleInput:SetText(type(prefillTitle) == "string" and prefillTitle or "")
    eventModalFrame.whenInput:SetText((type(prefillWhen) == "string" and prefillWhen ~= "") and prefillWhen or L["Now"])
    eventModalFrame.tankIn:SetText("")
    eventModalFrame.healIn:SetText("")
    eventModalFrame.dpsIn:SetText("")
    eventModalFrame.lvlIn:SetText("")
    eventModalFrame:Show()
    if eventModalFrame.Raise then eventModalFrame:Raise() end
    ReflowEventModal()
    eventModalFrame.titleInput:SetFocus()
end

local function OpenClanInfoModal()
    if not clanInfoModalFrame then
        local m = CreateFrame("Frame", "SocialCentralClanInfoModal", UIParent, "BackdropTemplate")
        m:SetSize(590, 424)
        m:SetPoint("CENTER")
        PrepareTopOverlayModal(m, 840)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        Theme:MakeMovable(m, { key = "modal_clan_info" })
        table.insert(UISpecialFrames, "SocialCentralClanInfoModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -36, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["Clan Management & Info"])

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            if m.sumIn then m.sumIn:ClearFocus() end
            if m.schIn then m.schIn:ClearFocus() end
            if m.rulIn then m.rulIn:ClearFocus() end
            if m.conIn then m.conIn:ClearFocus() end
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        m.helpBtn = AddHelp(
            m,
            topCloseBtn,
            L["Help: Clan Management & Info"],
            L["Stores your guild's shared identity card — focus, raid schedule, loot & comms rules, contacts, and who can edit or announce diplomacy."],
            L["Fill out your guild details and click Save to sync them with guildmates who have Guild Sync active."],
            "RIGHT",
            "LEFT",
            -4,
            0,
            { target = m }
        )
        title:SetPoint("TOPRIGHT", m.helpBtn or topCloseBtn, "LEFT", -6, 0)

        local metaLbl = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        metaLbl:SetPoint("TOPLEFT", 16, -40)
        metaLbl:SetPoint("TOPRIGHT", -16, -40)
        metaLbl:SetJustifyH("LEFT")
        metaLbl:SetWordWrap(false)
        m.metaLbl = metaLbl

        local sumLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sumLbl:SetPoint("TOPLEFT", 16, -64)
        sumLbl:SetText(L["Clan Focus / Summary:"])
        local sumIn = Theme:CreateEditBox(m, { height = 26, maxLetters = 160, placeholder = L["e.g. Progression Guild · Dungeons & Raids nightly"] })
        sumIn:SetPoint("TOPLEFT", 16, -82)
        sumIn:SetPoint("TOPRIGHT", -16, -82)
        m.sumIn = sumIn

        local schLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        schLbl:SetPoint("TOPLEFT", 16, -118)
        schLbl:SetText(L["Event Schedule / Core Hours:"])
        local schIn = Theme:CreateEditBox(m, { height = 26, maxLetters = 120, placeholder = L["e.g. Tue/Thu/Sun 20:30 Server Time"] })
        schIn:SetPoint("TOPLEFT", 16, -136)
        schIn:SetPoint("TOPRIGHT", -16, -136)
        m.schIn = schIn

        local rulLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rulLbl:SetPoint("TOPLEFT", 16, -172)
        rulLbl:SetText(L["Clan Rules / Loot & Comms:"])
        local rulIn = Theme:CreateEditBox(m, { height = 26, maxLetters = 160, placeholder = L["e.g. Respect everyone · Discord required for raids"] })
        rulIn:SetPoint("TOPLEFT", 16, -190)
        rulIn:SetPoint("TOPRIGHT", -16, -190)
        m.rulIn = rulIn

        local conLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        conLbl:SetPoint("TOPLEFT", 16, -226)
        conLbl:SetText(L["Officers / Recruitment Contacts:"])
        local conIn = Theme:CreateEditBox(m, { height = 26, maxLetters = 120, placeholder = L["e.g. GM / Raid Lead / Class Officers"] })
        conIn:SetPoint("TOPLEFT", 16, -244)
        conIn:SetPoint("TOPRIGHT", -16, -244)
        m.conIn = conIn

        local editModeLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        editModeLbl:SetPoint("TOPLEFT", 16, -284)
        editModeLbl:SetText(L["Who can edit & broadcast Clan Info / Diplomacy:"])

        m._editMode = "OFFICERS"
        m._modeBtns = {}
        local btnLeader = Theme:CreateButton(m, 140, 22, L["Guild Leader Only"], "default")
        Theme:AutoFitButton(btnLeader, 114, 14, 180)
        btnLeader:SetPoint("TOPLEFT", 16, -304)
        btnLeader:SetScript("OnClick", function()
            if not m._isLeader then return end
            m._editMode = "LEADER"
            Theme:SetButtonActive(btnLeader, true, "default")
            Theme:SetButtonActive(m._btnOff, false, "default")
            Theme:SetButtonActive(m._btnAll, false, "default")
        end)

        local btnOff = Theme:CreateButton(m, 140, 22, L["Officers Only"], "default")
        Theme:AutoFitButton(btnOff, 110, 14, 175)
        btnOff:SetPoint("LEFT", btnLeader, "RIGHT", 8, 0)
        btnOff:SetScript("OnClick", function()
            if not m._isLeader then return end
            m._editMode = "OFFICERS"
            Theme:SetButtonActive(btnLeader, false, "default")
            Theme:SetButtonActive(btnOff, true, "default")
            Theme:SetButtonActive(m._btnAll, false, "default")
        end)

        local btnAll = Theme:CreateButton(m, 154, 22, L["All Guild Members"], "default")
        Theme:AutoFitButton(btnAll, 120, 14, 185)
        btnAll:SetPoint("LEFT", btnOff, "RIGHT", 8, 0)
        btnAll:SetScript("OnClick", function()
            if not m._isLeader then return end
            m._editMode = "ALL"
            Theme:SetButtonActive(btnLeader, false, "default")
            Theme:SetButtonActive(btnOff, false, "default")
            Theme:SetButtonActive(btnAll, true, "default")
        end)
        m._btnLeader = btnLeader
        m._btnOff = btnOff
        m._btnAll = btnAll

        local permNote = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        permNote:SetPoint("TOPLEFT", 16, -334)
        permNote:SetPoint("TOPRIGHT", -16, -334)
        permNote:SetJustifyH("LEFT")
        permNote:SetWordWrap(true)
        permNote:SetText(L["All Clan Info & Diplomacy data stays strictly isolated inside your active guild bucket."])
        m.permNote = permNote

        local btnCancel = Theme:CreateButton(m, 88, 26, L["Close"], "default")
        Theme:AutoFitButton(btnCancel, 80, 14, 130)
        btnCancel:SetPoint("BOTTOMRIGHT", -16, 14)
        btnCancel:SetScript("OnClick", function() m:Hide() end)
        m.btnCancel = btnCancel

        local btnSync = Theme:CreateButton(m, 116, 26, L["Sync Intel"], "default")
        Theme:AutoFitButton(btnSync, 96, 14, 150)
        btnSync:SetPoint("RIGHT", btnCancel, "LEFT", -8, 0)
        btnSync:SetScript("OnClick", function()
            if ns.Clan then
                ns.Clan:RequestIntelSync()
                ns.Clan:BroadcastFullIntel()
            end
        end)
        m.btnSync = btnSync

        local btnSave = Theme:CreateButton(m, 126, 26, L["Save & Broadcast"], "primary")
        Theme:AutoFitButton(btnSave, 110, 16, 175)
        btnSave:SetPoint("RIGHT", btnSync, "LEFT", -8, 0)
        btnSave:SetScript("OnClick", function()
            if not ns.Clan then return end
            if ns.Clan:SaveClanInfo(m.sumIn:GetText(), m.schIn:GetText(), m.rulIn:GetText(), m.conIn:GetText(), m._editMode) then
                m:Hide()
            end
        end)
        m.btnSave = btnSave

        local btnRecruit = Theme:CreateButton(m, 128, 26, L["Recruitment..."], "default")
        Theme:AutoFitButton(btnRecruit, 108, 14, 168)
        btnRecruit:SetPoint("BOTTOMLEFT", 16, 14)
        btnRecruit:SetScript("OnClick", function()
            m:Hide()
            if UI.OpenGuildRecruitmentModal then
                UI:OpenGuildRecruitmentModal()
            end
        end)
        m.btnRecruit = btnRecruit

        clanInfoModalFrame = m
    end

    local info = ns.Clan and ns.Clan:GetClanInfo() or {}
    local pol = ns.Clan and ns.Clan.GetGuildHierarchyPolicy and ns.Clan:GetGuildHierarchyPolicy() or {}
    local canEdit, isOfficer = false, false
    if ns.Clan and ns.Clan.CanEditClanManagement then
        canEdit, isOfficer = ns.Clan:CanEditClanManagement()
    end
    local isLeader = (ns.Clan and ns.Clan.IsGuildLeader and ns.Clan:IsGuildLeader()) == true
    clanInfoModalFrame._isOfficer = isOfficer
    clanInfoModalFrame._isLeader = isLeader
    local curInfoMode = pol.infoMode or ((info.editMode == "ALL") and "ALL" or "OFFICERS")
    clanInfoModalFrame._editMode = curInfoMode

    PrepareTopOverlayModal(clanInfoModalFrame, 840)
    Theme:ApplyBackdrop(clanInfoModalFrame, "window")
    Theme:StyleButton(clanInfoModalFrame.topCloseBtn, "default")
    if clanInfoModalFrame.helpBtn then Theme:StyleButton(clanInfoModalFrame.helpBtn, "ghost") end
    Theme:StyleButton(clanInfoModalFrame.btnCancel, "default")
    Theme:StyleButton(clanInfoModalFrame.btnSync, "default")
    Theme:StyleButton(clanInfoModalFrame.btnSave, "primary")

    local updater = (info.updatedBy and info.updatedBy ~= "") and info.updatedBy or "-"
    local age = (info.updatedAt and info.updatedAt > 0) and Compat.FormatRelativeTime(info.updatedAt, L) or "-"
    local dipAuth = (ns.Clan and ns.Clan.GetDiplomacyAuthoritySummary and ns.Clan:GetDiplomacyAuthoritySummary()) or L["Guild Leader Only"]
    clanInfoModalFrame.metaLbl:SetText(string.format("|cff3fb950[%s]|r  ·  %s: %s (%s)  ·  %s", L["Guild-Isolated Scope"], L["Updated by"], updater, age, L["Diplomacy: %s"]:format(dipAuth)))

    clanInfoModalFrame.sumIn:SetText(info.summary or "")
    clanInfoModalFrame.schIn:SetText(info.schedule or "")
    clanInfoModalFrame.rulIn:SetText(info.rules or "")
    clanInfoModalFrame.conIn:SetText(info.contacts or "")

    for _, box in ipairs({ clanInfoModalFrame.sumIn, clanInfoModalFrame.schIn, clanInfoModalFrame.rulIn, clanInfoModalFrame.conIn }) do
        box:SetEnabled(canEdit)
        box:UpdatePlaceholder()
    end

    Theme:SetButtonActive(clanInfoModalFrame._btnLeader, curInfoMode == "LEADER", "default")
    Theme:SetButtonActive(clanInfoModalFrame._btnOff, curInfoMode == "OFFICERS" or curInfoMode == "RANK", "default")
    Theme:SetButtonActive(clanInfoModalFrame._btnAll, curInfoMode == "ALL", "default")
    clanInfoModalFrame._btnLeader:SetEnabled(isLeader)
    clanInfoModalFrame._btnOff:SetEnabled(isLeader)
    clanInfoModalFrame._btnAll:SetEnabled(isLeader)
    clanInfoModalFrame.btnSave:SetEnabled(canEdit)
    clanInfoModalFrame:Show()
    if clanInfoModalFrame.Raise then clanInfoModalFrame:Raise() end
end

local function OpenDiplomacyModal(prefillGuild, prefillStance, prefillFaction)
    if not diplomacyModalFrame then
        local m = CreateFrame("Frame", "SocialCentralDiplomacyModal", UIParent, "BackdropTemplate")
        m:SetSize(486, 326)
        m:SetPoint("CENTER")
        PrepareTopOverlayModal(m, 840)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        Theme:MakeMovable(m, { key = "modal_diplomacy" })
        table.insert(UISpecialFrames, "SocialCentralDiplomacyModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -36, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["Guild Diplomacy Registry"])

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            if m.guildIn then m.guildIn:ClearFocus() end
            if m.reasonIn then m.reasonIn:ClearFocus() end
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        m.helpBtn = AddHelp(
            m,
            topCloseBtn,
            L["Help: Guild Diplomacy Registry"],
            L["Marks another guild as Ally, Neutral, or Enemy so Spotter HUD alerts, Target Radar, and optional shared Allied Calendars know how to react."],
            L["Type the exact guild name (or click + Target Guild), choose Ally/Neutral/Enemy, add a reason, and click Save."],
            "RIGHT",
            "LEFT",
            -4,
            0,
            { target = m }
        )
        title:SetPoint("TOPRIGHT", m.helpBtn or topCloseBtn, "LEFT", -6, 0)

        local guildLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        guildLbl:SetPoint("TOPLEFT", 16, -46)
        guildLbl:SetText(L["Target Guild Name:"])

        local guildIn = Theme:CreateEditBox(m, { height = 26, maxLetters = 48, placeholder = L["Exact guild name (e.g. Blackhand Clan)"] })
        guildIn:SetPoint("TOPLEFT", 16, -64)
        guildIn:SetPoint("RIGHT", -136, 0)
        m.guildIn = guildIn

        local tgtGuildBtn = Theme:CreateButton(m, 114, 24, L["+ Target Guild"], "default")
        Theme:AutoFitButton(tgtGuildBtn, 96, 12, 122)
        tgtGuildBtn:SetPoint("LEFT", guildIn, "RIGHT", 6, 0)
        tgtGuildBtn:SetScript("OnClick", function()
            local ok, gName = pcall(GetGuildInfo, "target")
            local clean = ok and Safe.String(gName) or nil
            if clean and clean ~= "" then
                guildIn:SetText(clean)
            else
                ns:Print(L["Selected target has no readable guild."])
            end
        end)
        m.tgtGuildBtn = tgtGuildBtn

        local stanceLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        stanceLbl:SetPoint("TOPLEFT", 16, -104)
        stanceLbl:SetText(L["Diplomatic Stance:"])

        m._stance = "ENEMY"
        m._stanceBtns = {}
        local prevS
        for _, def in ipairs({
            { id = "ENEMY", label = L["Enemy Clan"] },
            { id = "ALLY", label = L["Ally Clan"] },
            { id = "NEUTRAL", label = L["Neutral (Clear)"] },
        }) do
            local sb = Theme:CreateButton(m, 112, 22, def.label, def.id == "ENEMY" and "danger" or "default")
            Theme:AutoFitButton(sb, 96, 14, 150)
            if not prevS then
                sb:SetPoint("TOPLEFT", 16, -124)
            else
                sb:SetPoint("LEFT", prevS, "RIGHT", 8, 0)
            end
            sb:SetScript("OnClick", function()
                m._stance = def.id
                for _, item in ipairs(m._stanceBtns) do
                    Theme:SetButtonActive(item.btn, m._stance == item.id, item.id == "ENEMY" and "danger" or "default")
                end
                if m.shareEventsCheck then
                    local canToggleShare = (m._stance == "ALLY") and (m._canShareEvents == true)
                    m.shareEventsCheck:SetEnabled(canToggleShare)
                    if m.shareEventsLbl then
                        m.shareEventsLbl:SetAlpha(canToggleShare and 1.0 or 0.45)
                    end
                end
                if m.btnSave then
                    m.btnSave:SetEnabled((m._canDip == true) or (m._canShareOnly == true and m._stance == "ALLY"))
                end
            end)
            table.insert(m._stanceBtns, { id = def.id, btn = sb })
            prevS = sb
        end

        local reasonLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        reasonLbl:SetPoint("TOPLEFT", 16, -162)
        reasonLbl:SetText(L["Reason / Notes (shared securely within your clan):"])

        local reasonIn = Theme:CreateEditBox(m, { height = 26, maxLetters = 90, placeholder = L["e.g. KoS griefing / Raiding coalition / Trade partner"] })
        reasonIn:SetPoint("TOPLEFT", 16, -180)
        reasonIn:SetPoint("TOPRIGHT", -16, -180)
        m.reasonIn = reasonIn

        local shareCb = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
        shareCb:SetSize(22, 22)
        shareCb:SetPoint("TOPLEFT", 14, -210)
        local shareLbl = shareCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        shareLbl:SetPoint("LEFT", shareCb, "RIGHT", 4, 0)
        shareLbl:SetWidth(392)
        shareLbl:SetJustifyH("LEFT")
        shareLbl:SetWordWrap(true)
        shareLbl:SetText(L["Authorize shared Calendar & Events with this Allied Guild (requires both guilds)"])
        m.shareEventsCheck = shareCb
        m.shareEventsLbl = shareLbl
        AddHelp(
            m,
            shareLbl,
            L["Help: Allied Event Sharing Authorization"],
            L["Authorizes your guild to exchange Event Calls and calendar signups with this Allied Guild."],
            L["Sharing only becomes active after leadership or an appointed manager in BOTH guilds enables this authorization."]
        )

        local tipFs = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tipFs:SetPoint("TOPLEFT", 16, -242)
        tipFs:SetPoint("TOPRIGHT", -16, -242)
        tipFs:SetJustifyH("LEFT")
        tipFs:SetWordWrap(true)
        tipFs:SetText(L["Players from Enemy or Ally clans appearing on your screen will trigger Spotter alerts & Target Radar."])
        m.tipFs = tipFs

        local btnCancel = Theme:CreateButton(m, 88, 26, L["Cancel"], "default")
        Theme:AutoFitButton(btnCancel, 80, 14, 130)
        btnCancel:SetPoint("BOTTOMRIGHT", -16, 14)
        btnCancel:SetScript("OnClick", function() m:Hide() end)
        m.btnCancel = btnCancel

        local btnSave = Theme:CreateButton(m, 122, 26, L["Save & Broadcast"], "primary")
        Theme:AutoFitButton(btnSave, 108, 16, 175)
        btnSave:SetPoint("RIGHT", btnCancel, "LEFT", -8, 0)
        local function CommitDip()
            local allowEvtShare = (m._stance == "ALLY" and m.shareEventsCheck and m.shareEventsCheck:GetChecked()) and true or false
            if ns.Clan and ns.Clan:SetGuildStance(m.guildIn:GetText(), m._stance, m.reasonIn:GetText(), m._prefillFaction, allowEvtShare) then
                m:Hide()
            end
        end
        btnSave:SetScript("OnClick", CommitDip)
        reasonIn:SetScript("OnEnterPressed", CommitDip)
        m.btnSave = btnSave

        diplomacyModalFrame = m
    end

    local canDip, authSummary = true, L["Guild Leader Only"]
    if ns.Clan and ns.Clan.CanManageDiplomacy then
        canDip, authSummary = ns.Clan:CanManageDiplomacy()
    end
    local canShare, shareSummary = canDip, authSummary
    if ns.Clan and ns.Clan.CanManageAlliedEventSharing then
        canShare, shareSummary = ns.Clan:CanManageAlliedEventSharing()
    end

    diplomacyModalFrame._prefillFaction = prefillFaction
    diplomacyModalFrame._stance = (prefillStance == "ALLY" or prefillStance == "NEUTRAL") and prefillStance or "ENEMY"
    local existingEntry = nil
    if prefillGuild and ns.Clan and ns.Clan.LookupGuildStance then
        local _, entry = ns.Clan:LookupGuildStance(prefillGuild)
        existingEntry = entry
    end
    local canShareOnly = (not canDip) and (canShare == true) and (existingEntry ~= nil and existingEntry.stance == "ALLY")
    diplomacyModalFrame._canDip = (canDip == true)
    diplomacyModalFrame._canShareOnly = canShareOnly
    diplomacyModalFrame._canShareEvents = (canDip == true) or (canShare == true)

    PrepareTopOverlayModal(diplomacyModalFrame, 840)
    Theme:ApplyBackdrop(diplomacyModalFrame, "window")
    Theme:StyleButton(diplomacyModalFrame.topCloseBtn, "default")
    if diplomacyModalFrame.helpBtn then Theme:StyleButton(diplomacyModalFrame.helpBtn, "ghost") end
    Theme:StyleButton(diplomacyModalFrame.btnCancel, "default")
    Theme:StyleButton(diplomacyModalFrame.btnSave, "primary")
    Theme:StyleButton(diplomacyModalFrame.tgtGuildBtn, "default")
    for _, item in ipairs(diplomacyModalFrame._stanceBtns) do
        Theme:SetButtonActive(item.btn, diplomacyModalFrame._stance == item.id, item.id == "ENEMY" and "danger" or "default")
        if item.btn.SetEnabled then item.btn:SetEnabled(canDip) end
    end
    diplomacyModalFrame.guildIn:SetText(prefillGuild or "")
    local existingReason = (existingEntry and existingEntry.reason) or ""
    diplomacyModalFrame.reasonIn:SetText(existingReason)
    diplomacyModalFrame.guildIn:SetEnabled(canDip)
    diplomacyModalFrame.reasonIn:SetEnabled(canDip)
    diplomacyModalFrame.tgtGuildBtn:SetEnabled(canDip)
    if diplomacyModalFrame.shareEventsCheck then
        diplomacyModalFrame.shareEventsCheck:SetChecked((existingEntry and existingEntry.shareEvents == true) and true or false)
        local shareEnabled = (diplomacyModalFrame._stance == "ALLY") and (diplomacyModalFrame._canShareEvents == true)
        diplomacyModalFrame.shareEventsCheck:SetEnabled(shareEnabled)
        if diplomacyModalFrame.shareEventsLbl then
            diplomacyModalFrame.shareEventsLbl:SetAlpha(shareEnabled and 1.0 or 0.45)
        end
    end
    diplomacyModalFrame.btnSave:SetEnabled(canDip or (canShareOnly and diplomacyModalFrame._stance == "ALLY"))
    if canDip then
        diplomacyModalFrame.tipFs:SetText("|cff3fb950" .. L["Diplomacy Authority: %s"]:format(authSummary) .. "|r  ·  " .. L["Players from Enemy or Ally clans appearing on your screen will trigger Spotter alerts & Target Radar."])
    elseif canShareOnly then
        diplomacyModalFrame.tipFs:SetText("|cff58a6ff" .. L["Authorized to toggle shared Allied Events only (%s)."]:format(shareSummary) .. "|r")
    else
        diplomacyModalFrame.tipFs:SetText("|cffff6666" .. L["Only guild leaders (%s) can define Allied or Enemy guilds."]:format(authSummary) .. "|r")
    end
    diplomacyModalFrame:Show()
    if diplomacyModalFrame.Raise then diplomacyModalFrame:Raise() end
    if canDip then
        if not prefillGuild or prefillGuild == "" then
            diplomacyModalFrame.guildIn:SetFocus()
        else
            diplomacyModalFrame.reasonIn:SetFocus()
        end
    end
end

function UI:OpenClanInfoModal()
    OpenClanInfoModal()
end

function UI:OpenDiplomacyModal(prefillGuild, prefillStance, prefillFaction)
    OpenDiplomacyModal(prefillGuild, prefillStance, prefillFaction)
end

UI._modals = UI._modals or {}

function UI:OpenClanAbsenceModal()
    local f = UI._modals.clanAbsence
    if not f then
        local m = CreateFrame("Frame", "SocialCentralClanAbsenceModal", UIParent, "BackdropTemplate")
        m:SetSize(380, 210)
        m:SetPoint("CENTER")
        PrepareTopOverlayModal(m, 845)
        Theme:MakeMovable(m, { key = "modal_clan_absence" })
        table.insert(UISpecialFrames, "SocialCentralClanAbsenceModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetText(L["Guild Absence / Vacation"])

        local closeX = Theme:CreateButton(m, 22, 20, "X", "default")
        closeX:SetPoint("TOPRIGHT", -10, -10)
        closeX:SetScript("OnClick", function() m:Hide() end)
        m.closeX = closeX

        m.helpBtn = AddHelp(
            m,
            closeX,
            L["Help: Guild Absence / Vacation"],
            L["Lets guild officers and members know when you will be away and your expected return date so you are not marked inactive."],
            L["Enter your return date and optional reason, then click Save (synced across Guild Hub). Use Clear when you are back."],
            "RIGHT",
            "LEFT",
            -4,
            0,
            { target = m }
        )
        title:SetPoint("TOPRIGHT", m.helpBtn or closeX, "LEFT", -6, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)

        local dateLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dateLbl:SetPoint("TOPLEFT", 16, -46)
        dateLbl:SetText(L["Return Date (e.g. 15/12):"])
        local dateIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 18, placeholder = L["e.g. 15/12 or Next Week"] })
        dateIn:SetPoint("TOPLEFT", 16, -64)
        dateIn:SetPoint("TOPRIGHT", -16, -64)
        m.dateIn = dateIn

        local reasonLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        reasonLbl:SetPoint("TOPLEFT", 16, -98)
        reasonLbl:SetText(L["Reason (optional):"])
        local reasonIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 48, placeholder = L["e.g. Traveling, Work, Exam week"] })
        reasonIn:SetPoint("TOPLEFT", 16, -116)
        reasonIn:SetPoint("TOPRIGHT", -16, -116)
        m.reasonIn = reasonIn

        local btnCancel = Theme:CreateButton(m, 80, 24, L["Close"], "default")
        Theme:AutoFitButton(btnCancel, 76, 14, 126)
        btnCancel:SetPoint("BOTTOMRIGHT", -16, 12)
        btnCancel:SetScript("OnClick", function() m:Hide() end)
        m.btnCancel = btnCancel

        local btnClear = Theme:CreateButton(m, 96, 24, L["Clear"], "danger")
        Theme:AutoFitButton(btnClear, 84, 14, 136)
        btnClear:SetPoint("BOTTOMLEFT", 16, 12)
        btnClear:SetScript("OnClick", function()
            if ns.Clan and ns.Clan.ClearMyAbsence then
                ns.Clan:ClearMyAbsence()
            end
            m:Hide()
        end)
        m.btnClear = btnClear

        local btnSave = Theme:CreateButton(m, 110, 24, L["Save"], "primary")
        btnSave:SetPoint("RIGHT", btnCancel, "LEFT", -8, 0)
        btnSave:SetScript("OnClick", function()
            if ns.Clan and ns.Clan.SetMyAbsence then
                ns.Clan:SetMyAbsence(m.dateIn:GetText(), m.reasonIn:GetText())
            end
            m:Hide()
        end)
        m.btnSave = btnSave

        UI._modals.clanAbsence = m
        f = m
    end

    PrepareTopOverlayModal(f, 845)
    Theme:ApplyBackdrop(f, "window")
    Theme:StyleButton(f.closeX, "default")
    if f.helpBtn then Theme:StyleButton(f.helpBtn, "ghost") end
    Theme:StyleButton(f.btnCancel, "default")
    Theme:StyleButton(f.btnClear, "danger")
    Theme:StyleButton(f.btnSave, "primary")

    local resolvedSelf = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local selfKey = resolvedSelf and resolvedSelf.lookupKey or nil
    local curAbs = (selfKey and ns.Clan and ns.Clan.GetMemberAbsence) and ns.Clan:GetMemberAbsence(selfKey) or nil
    f.dateIn:SetText(curAbs and curAbs.untilDate or "")
    f.reasonIn:SetText(curAbs and curAbs.reason or "")
    f.btnClear:SetShown(curAbs ~= nil)
    f:Show()
    f:Raise()
end

function UI:OpenCreateGuildPollModal(onCreated)
    local f = UI._modals.guildPollCreate
    if not f then
        local m = CreateFrame("Frame", "SocialCentralCreatePollModal", UIParent, "BackdropTemplate")
        m:SetSize(410, 290)
        m:SetPoint("CENTER")
        PrepareTopOverlayModal(m, 855)
        Theme:MakeMovable(m, { key = "modal_create_poll" })
        table.insert(UISpecialFrames, "SocialCentralCreatePollModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetText(L["Create Guild Poll"])

        local closeX = Theme:CreateButton(m, 22, 20, "X", "default")
        closeX:SetPoint("TOPRIGHT", -10, -10)
        closeX:SetScript("OnClick", function() m:Hide() end)
        m.closeX = closeX

        m.helpBtn = AddHelp(
            m,
            closeX,
            L["Help: Create Guild Poll"],
            L["Creates an interactive multi-choice vote synced with online guildmates using Guild Sync."],
            L["Write a question, fill between 2 and 5 answer options, and click Create Poll to publish it."],
            "RIGHT",
            "LEFT",
            -4,
            0,
            { target = m }
        )
        title:SetPoint("TOPRIGHT", m.helpBtn or closeX, "LEFT", -6, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)

        local qLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        qLbl:SetPoint("TOPLEFT", 16, -44)
        qLbl:SetText(L["Question / Title:"])
        local qIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 48, placeholder = L["e.g. Next Raid Night or Loot Rule?"] })
        qIn:SetPoint("TOPLEFT", 16, -62)
        qIn:SetPoint("TOPRIGHT", -16, -62)
        m.qIn = qIn

        local oLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        oLbl:SetPoint("TOPLEFT", 16, -94)
        oLbl:SetText(L["Options (2 to 5 choices):"])
        m.optInputs = {}
        for i = 1, 5 do
            local oy = -112 - ((i - 1) * 27)
            local ob = Theme:CreateEditBox(m, { height = 22, maxLetters = 24, placeholder = L["Option %d"]:format(i) })
            ob:SetPoint("TOPLEFT", 16, oy)
            ob:SetPoint("TOPRIGHT", -16, oy)
            m.optInputs[i] = ob
        end

        local btnCancel = Theme:CreateButton(m, 84, 24, L["Cancel"], "default")
        Theme:AutoFitButton(btnCancel, 78, 14, 126)
        btnCancel:SetPoint("BOTTOMRIGHT", -16, 12)
        btnCancel:SetScript("OnClick", function() m:Hide() end)
        m.btnCancel = btnCancel

        local btnSave = Theme:CreateButton(m, 124, 24, L["Create Poll"], "primary")
        Theme:AutoFitButton(btnSave, 112, 16, 175)
        btnSave:SetPoint("RIGHT", btnCancel, "LEFT", -8, 0)
        btnSave:SetScript("OnClick", function()
            local opts = {}
            for _, ob in ipairs(m.optInputs) do
                local val = Compat.Trim and Compat.Trim(ob:GetText() or "") or (ob:GetText() or "")
                if val ~= "" then opts[#opts + 1] = val end
            end
            if ns.Clan and ns.Clan.CreatePoll and ns.Clan:CreatePoll(m.qIn:GetText(), opts) then
                m:Hide()
                if type(m._onCreated) == "function" then m._onCreated() end
            end
        end)
        m.btnSave = btnSave

        UI._modals.guildPollCreate = m
        f = m
    end
    f._onCreated = onCreated
    PrepareTopOverlayModal(f, 855)
    Theme:ApplyBackdrop(f, "window")
    Theme:StyleButton(f.closeX, "default")
    if f.helpBtn then Theme:StyleButton(f.helpBtn, "ghost") end
    Theme:StyleButton(f.btnCancel, "default")
    Theme:StyleButton(f.btnSave, "primary")
    f.qIn:SetText("")
    for _, ob in ipairs(f.optInputs) do ob:SetText("") end
    f:Show()
    f:Raise()
    f.qIn:SetFocus()
end

function UI:OpenGuildPollsModal()
    local f = UI._modals.guildPolls
    if not f then
        local m = CreateFrame("Frame", "SocialCentralGuildPollsModal", UIParent, "BackdropTemplate")
        m:SetSize(450, 380)
        m:SetPoint("CENTER")
        PrepareTopOverlayModal(m, 845)
        Theme:MakeMovable(m, { key = "modal_guild_polls" })
        table.insert(UISpecialFrames, "SocialCentralGuildPollsModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetText(L["Guild Polls & Voting"])

        local closeX = Theme:CreateButton(m, 22, 20, "X", "default")
        closeX:SetPoint("TOPRIGHT", -10, -10)
        closeX:SetScript("OnClick", function() m:Hide() end)
        m.closeX = closeX

        m.helpBtn = AddHelp(
            m,
            closeX,
            L["Help: Guild Polls & Voting"],
            L["Displays active and closed guild polls so members can cast or change their vote directly in-game."],
            L["Click any option button to vote; officers can also start New Poll or Close / Delete finished votes."],
            "RIGHT",
            "LEFT",
            -4,
            0,
            { target = m }
        )
        title:SetPoint("TOPRIGHT", m.helpBtn or closeX, "LEFT", -6, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)

        local scroll = Theme:CreateScrollList(m, 118, function(rowParent, _, rowHeight)
            local row = CreateFrame("Frame", nil, rowParent, "BackdropTemplate")
            row:SetHeight(rowHeight)
            row.titleLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.titleLbl:SetPoint("TOPLEFT", 8, -6)
            row.titleLbl:SetPoint("TOPRIGHT", -64, -6)
            row.titleLbl:SetJustifyH("LEFT")
            row.titleLbl:SetWordWrap(false)

            row.metaLbl = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.metaLbl:SetPoint("TOPRIGHT", -8, -7)
            row.metaLbl:SetJustifyH("RIGHT")

            row.optBtns = {}
            for oi = 1, 5 do
                local ob = Theme:CreateButton(row, 180, 18, "", "default")
                ob:SetPoint("TOPLEFT", 8 + ((oi % 2 == 1) and 0 or 196), -26 - (math.floor((oi - 1) / 2) * 21))
                ob:Hide()
                row.optBtns[oi] = ob
            end
            row.delBtn = Theme:CreateButton(row, 62, 18, L["Close"], "danger")
            Theme:AutoFitButton(row.delBtn, 58, 12, 104)
            row.delBtn:SetPoint("BOTTOMRIGHT", -8, 6)
            row.delBtn:Hide()
            return row
        end, function(row, item, _, pal)
            Theme:ApplyBackdrop(row, "inset", pal)
            row.titleLbl:SetText((item.closed and "|cff8b949e[" .. L["Closed"] .. "]|r " or "|cffffd24d") .. (item.title or "?") .. "|r")
            row.metaLbl:SetText(L["%d votes"]:format(item.totalVotes or 0))
            for oi, ob in ipairs(row.optBtns) do
                local optTxt = item.options and item.options[oi]
                if optTxt then
                    local cnt = (item.counts and item.counts[oi]) or 0
                    local pct = ((item.totalVotes or 0) > 0) and math.floor((cnt / item.totalVotes) * 100 + 0.5) or 0
                    local mark = (item.myVote == oi) and "|cff3fb950[x]|r " or ""
                    Theme:StyleButton(ob, (item.myVote == oi) and "primary" or "default")
                    Theme:SetButtonText(ob, ("%s%s (%d%%)"):format(mark, optTxt, pct))
                    ob:SetEnabled(not item.closed)
                    ob:SetScript("OnClick", function()
                        if ns.Clan and ns.Clan.VotePoll then
                            ns.Clan:VotePoll(item.id, oi)
                            UI:OpenGuildPollsModal()
                        end
                    end)
                    ob:Show()
                else
                    ob:Hide()
                end
            end
            local canManage = ns.Clan and ns.Clan.CanManagePolls and ns.Clan:CanManagePolls()
            row.delBtn:SetShown(canManage == true)
            if canManage then
                Theme:StyleButton(row.delBtn, "danger")
                Theme:SetButtonText(row.delBtn, item.closed and L["Delete"] or L["Close"])
                row.delBtn:SetScript("OnClick", function()
                    if ns.Clan and ns.Clan.CloseOrDeletePoll then
                        ns.Clan:CloseOrDeletePoll(item.id, item.closed == true)
                        UI:OpenGuildPollsModal()
                    end
                end)
            end
        end)
        scroll.container:SetPoint("TOPLEFT", 12, -40)
        scroll.container:SetPoint("BOTTOMRIGHT", -12, 44)
        m.scroll = scroll

        local btnNew = Theme:CreateButton(m, 130, 24, "+ " .. L["New Poll"], "primary")
        Theme:AutoFitButton(btnNew, 116, 16, 185)
        btnNew:SetPoint("BOTTOMLEFT", 12, 10)
        btnNew:SetScript("OnClick", function()
            UI:OpenCreateGuildPollModal(function()
                if UI._modals.guildPolls and UI._modals.guildPolls:IsShown() then
                    UI:OpenGuildPollsModal()
                end
            end)
        end)
        m.btnNew = btnNew

        local btnClose = Theme:CreateButton(m, 84, 24, L["Close"], "default")
        Theme:AutoFitButton(btnClose, 76, 14, 130)
        btnClose:SetPoint("BOTTOMRIGHT", -12, 10)
        btnClose:SetScript("OnClick", function() m:Hide() end)
        m.btnClose = btnClose

        UI._modals.guildPolls = m
        f = m
    end

    PrepareTopOverlayModal(f, 845)
    Theme:ApplyBackdrop(f, "window")
    Theme:StyleButton(f.closeX, "default")
    Theme:StyleButton(f.btnNew, "primary")
    Theme:StyleButton(f.btnClose, "default")
    f.scroll:RefreshTheme()
    local canCreate = ns.Clan and ns.Clan.CanManagePolls and ns.Clan:CanManagePolls()
    f.btnNew:SetShown(canCreate == true)
    local polls = (ns.Clan and ns.Clan.GetPollsList) and ns.Clan:GetPollsList() or {}
    f.scroll:SetData(polls, L["No active Guild Polls yet."], false)
    f:Show()
    f:Raise()
end

function UI:OpenGuildRecruitmentModal()
    local f = UI._modals.guildRecruit
    if not f then
        local m = CreateFrame("Frame", "SocialCentralGuildRecruitModal", UIParent, "BackdropTemplate")
        m:SetSize(440, 310)
        m:SetPoint("CENTER")
        PrepareTopOverlayModal(m, 845)
        Theme:MakeMovable(m, { key = "modal_guild_recruit" })
        table.insert(UISpecialFrames, "SocialCentralGuildRecruitModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetText(L["Guild Recruitment Card"])

        local closeX = Theme:CreateButton(m, 22, 20, "X", "default")
        closeX:SetPoint("TOPRIGHT", -10, -10)
        closeX:SetScript("OnClick", function() m:Hide() end)
        m.closeX = closeX

        m.helpBtn = AddHelp(
            m,
            closeX,
            L["Help: Guild Recruitment Card"],
            L["Configures your guild's recruitment pitch, needed classes/roles, schedule, and minimum level — plus a quick /2 and /4 ad formatter."],
            L["Officers can toggle recruitment active, edit details and Save; anyone can click Copy /2 /4 Ad to copy a clean formatted post."],
            "RIGHT",
            "LEFT",
            -4,
            0,
            { target = m }
        )
        title:SetPoint("TOPRIGHT", m.helpBtn or closeX, "LEFT", -6, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)

        local recCb = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
        recCb:SetSize(22, 22)
        recCb:SetPoint("TOPLEFT", 14, -42)
        local recLbl = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        recLbl:SetPoint("LEFT", recCb, "RIGHT", 6, 0)
        recLbl:SetText(L["Guild is actively recruiting"])
        m.recCb = recCb

        local rLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rLbl:SetPoint("TOPLEFT", 16, -74)
        rLbl:SetText(L["Needed Roles / Classes:"])
        local rIn = Theme:CreateEditBox(m, { height = 22, maxLetters = 28, placeholder = L["e.g. Healers, Warlocks, Tanks"] })
        rIn:SetPoint("TOPLEFT", 16, -92)
        rIn:SetPoint("TOPRIGHT", -16, -92)
        m.rIn = rIn

        local sLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sLbl:SetPoint("TOPLEFT", 16, -124)
        sLbl:SetText(L["Raid / Activity Schedule:"])
        local sIn = Theme:CreateEditBox(m, { height = 22, maxLetters = 36, placeholder = L["e.g. Tue/Thu 20:30 BRT"] })
        sIn:SetPoint("TOPLEFT", 16, -142)
        sIn:SetPoint("TOPRIGHT", -110, -142)
        m.sIn = sIn

        local lvLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lvLbl:SetPoint("TOPLEFT", sIn, "TOPRIGHT", 10, 18)
        lvLbl:SetText(L["Min Lv:"])
        local lvIn = Theme:CreateEditBox(m, { width = 56, height = 22, numeric = true, maxLetters = 2 })
        lvIn:SetPoint("TOPLEFT", sIn, "TOPRIGHT", 10, 0)
        m.lvIn = lvIn

        local pLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pLbl:SetPoint("TOPLEFT", 16, -174)
        pLbl:SetText(L["Recruitment Pitch:"])
        local pIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 90, placeholder = L["e.g. Friendly PvE/PvP guild clearing MC & BWL!"] })
        pIn:SetPoint("TOPLEFT", 16, -192)
        pIn:SetPoint("TOPRIGHT", -16, -192)
        m.pIn = pIn

        local btnCancel = Theme:CreateButton(m, 80, 24, L["Close"], "default")
        Theme:AutoFitButton(btnCancel, 76, 14, 126)
        btnCancel:SetPoint("BOTTOMRIGHT", -16, 12)
        btnCancel:SetScript("OnClick", function() m:Hide() end)
        m.btnCancel = btnCancel

        local btnCopy = Theme:CreateButton(m, 140, 24, L["Copy /2 /4 Ad"], "default")
        Theme:AutoFitButton(btnCopy, 118, 14, 175)
        btnCopy:SetPoint("BOTTOMLEFT", 16, 12)
        btnCopy:SetScript("OnClick", function()
            if ns.Clan and ns.Clan.FormatGuildRecruitmentAd and UI.OpenCopyModal then
                UI:OpenCopyModal(ns.Clan:FormatGuildRecruitmentAd(), L["Copy Recruitment Ad"], L["Press Ctrl+C to copy and paste into Trade (/2) or World chat."])
            end
        end)
        m.btnCopy = btnCopy

        local btnSave = Theme:CreateButton(m, 118, 24, L["Save"], "primary")
        btnSave:SetPoint("RIGHT", btnCancel, "LEFT", -8, 0)
        btnSave:SetScript("OnClick", function()
            if ns.Clan and ns.Clan.SaveGuildRecruitment then
                ns.Clan:SaveGuildRecruitment(m.recCb:GetChecked(), m.rIn:GetText(), m.sIn:GetText(), m.lvIn:GetText(), m.pIn:GetText())
            end
            m:Hide()
        end)
        m.btnSave = btnSave

        UI._modals.guildRecruit = m
        f = m
    end

    PrepareTopOverlayModal(f, 845)
    Theme:ApplyBackdrop(f, "window")
    Theme:StyleButton(f.closeX, "default")
    if f.helpBtn then Theme:StyleButton(f.helpBtn, "ghost") end
    Theme:StyleButton(f.btnCancel, "default")
    Theme:StyleButton(f.btnCopy, "default")
    Theme:StyleButton(f.btnSave, "primary")

    local rec = (ns.Clan and ns.Clan.GetGuildRecruitment) and ns.Clan:GetGuildRecruitment() or {}
    local canEdit = (ns.Clan and ns.Clan.CanManagePolls and ns.Clan:CanManagePolls()) == true
    f.recCb:SetChecked(rec.recruiting == true)
    f.recCb:SetEnabled(canEdit)
    f.rIn:SetText(rec.roles or "")
    f.rIn:SetEnabled(canEdit)
    f.sIn:SetText(rec.schedule or "")
    f.sIn:SetEnabled(canEdit)
    f.lvIn:SetText(tostring(rec.minLevel or 1))
    f.lvIn:SetEnabled(canEdit)
    f.pIn:SetText(rec.pitch or "")
    f.pIn:SetEnabled(canEdit)
    f.btnSave:SetEnabled(canEdit)
    f:Show()
    f:Raise()
end

function UI:OpenMySocialProfileModal()
    local f = UI._modals.mySocialProfile
    if not f then
        local m = CreateFrame("Frame", "SocialCentralMyProfileModal", UIParent, "BackdropTemplate")
        m:SetSize(430, 325)
        m:SetPoint("CENTER")
        PrepareTopOverlayModal(m, 845)
        Theme:MakeMovable(m, { key = "modal_my_social_profile" })
        table.insert(UISpecialFrames, "SocialCentralMyProfileModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetText(L["My Social Profile (Opt-In)"])

        local closeX = Theme:CreateButton(m, 22, 20, "X", "default")
        closeX:SetPoint("TOPRIGHT", -10, -10)
        closeX:SetScript("OnClick", function() m:Hide() end)
        m.closeX = closeX

        m.helpBtn = AddHelp(
            m,
            closeX,
            L["Help: My Social Profile"],
            L["Shares an optional voluntary badge (main role, play status, languages, schedule, short bio) shown in tooltips for friends and guildmates."],
            L["Check the share option to opt in, fill what you want others to see, and click Save. Uncheck anytime to stay private."],
            "RIGHT",
            "LEFT",
            -4,
            0,
            { target = m }
        )
        title:SetPoint("TOPRIGHT", m.helpBtn or closeX, "LEFT", -6, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)

        local enCb = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
        enCb:SetSize(22, 22)
        enCb:SetPoint("TOPLEFT", 14, -42)
        local enLbl = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        enLbl:SetPoint("LEFT", enCb, "RIGHT", 6, 0)
        enLbl:SetText(L["Share my voluntary Social Profile in tooltips"])
        m.enCb = enCb

        local roleLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        roleLbl:SetPoint("TOPLEFT", 16, -74)
        roleLbl:SetText(L["Main Role:"])
        m._role = "DPS"
        m._roleBtns = {}
        local prevR = roleLbl
        for _, rId in ipairs({ "TANK", "HEALER", "DPS" }) do
            local rb = Theme:CreateButton(m, 72, 20, ROLE_LABELS[rId] or rId, "default")
            rb:SetPoint("LEFT", prevR, "RIGHT", 8, 0)
            rb:SetScript("OnClick", function()
                m._role = rId
                for _, item in ipairs(m._roleBtns) do
                    Theme:SetButtonActive(item.btn, m._role == item.id, "default")
                end
            end)
            m._roleBtns[#m._roleBtns + 1] = { id = rId, btn = rb }
            prevR = rb
        end

        local avLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        avLbl:SetPoint("TOPLEFT", 16, -106)
        avLbl:SetText(L["Status:"])
        m._avail = "OPEN"
        m._availBtns = {}
        local prevA = avLbl
        for _, av in ipairs({
            { id = "OPEN", label = L["Open to Groups"] },
            { id = "QUEST", label = L["Questing"] },
            { id = "BUSY", label = L["Busy"] },
        }) do
            local ab = Theme:CreateButton(m, 96, 20, av.label, "default")
            Theme:AutoFitButton(ab, 70, 12, 125)
            ab:SetPoint("LEFT", prevA, "RIGHT", 6, 0)
            ab:SetScript("OnClick", function()
                m._avail = av.id
                for _, item in ipairs(m._availBtns) do
                    Theme:SetButtonActive(item.btn, m._avail == item.id, "default")
                end
            end)
            m._availBtns[#m._availBtns + 1] = { id = av.id, btn = ab }
            prevA = ab
        end

        local langLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        langLbl:SetPoint("TOPLEFT", 16, -138)
        langLbl:SetText(L["Languages & Play Hours:"])
        local langIn = Theme:CreateEditBox(m, { width = 120, height = 22, maxLetters = 18, placeholder = "PT / EN" })
        langIn:SetPoint("TOPLEFT", 16, -156)
        m.langIn = langIn

        local hrsIn = Theme:CreateEditBox(m, { height = 22, maxLetters = 28, placeholder = L["e.g. Weeknights 20:00-23:00"] })
        hrsIn:SetPoint("LEFT", langIn, "RIGHT", 8, 0)
        hrsIn:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        m.hrsIn = hrsIn

        local bioLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bioLbl:SetPoint("TOPLEFT", 16, -190)
        bioLbl:SetText(L["Short Bio (optional):"])
        local bioIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 70, placeholder = L["e.g. Chill dungeon tank, Discord ready"] })
        bioIn:SetPoint("TOPLEFT", 16, -208)
        bioIn:SetPoint("TOPRIGHT", -16, -208)
        m.bioIn = bioIn

        local btnCancel = Theme:CreateButton(m, 80, 24, L["Close"], "default")
        Theme:AutoFitButton(btnCancel, 76, 14, 126)
        btnCancel:SetPoint("BOTTOMRIGHT", -16, 12)
        btnCancel:SetScript("OnClick", function() m:Hide() end)
        m.btnCancel = btnCancel

        local btnSave = Theme:CreateButton(m, 118, 24, L["Save"], "primary")
        Theme:AutoFitButton(btnSave, 96, 16, 150)
        btnSave:SetPoint("RIGHT", btnCancel, "LEFT", -8, 0)
        btnSave:SetScript("OnClick", function()
            if ns.Clan and ns.Clan.SaveMySocialProfile then
                ns.Clan:SaveMySocialProfile({
                    enabled = m.enCb:GetChecked(),
                    role = m._role,
                    availability = m._avail,
                    langs = m.langIn:GetText(),
                    hours = m.hrsIn:GetText(),
                    bio = m.bioIn:GetText(),
                })
            end
            m:Hide()
        end)
        m.btnSave = btnSave

        UI._modals.mySocialProfile = m
        f = m
    end

    PrepareTopOverlayModal(f, 845)
    Theme:ApplyBackdrop(f, "window")
    Theme:StyleButton(f.closeX, "default")
    if f.helpBtn then Theme:StyleButton(f.helpBtn, "ghost") end
    Theme:StyleButton(f.btnCancel, "default")
    Theme:StyleButton(f.btnSave, "primary")

    local prof = (ns.Clan and ns.Clan.GetMySocialProfile) and ns.Clan:GetMySocialProfile() or {}
    f.enCb:SetChecked(prof.enabled == true)
    f._role = prof.role or "DPS"
    f._avail = prof.availability or "OPEN"
    for _, item in ipairs(f._roleBtns) do
        Theme:SetButtonActive(item.btn, f._role == item.id, "default")
    end
    for _, item in ipairs(f._availBtns) do
        Theme:SetButtonActive(item.btn, f._avail == item.id, "default")
    end
    f.langIn:SetText(prof.langs or "PT/EN")
    f.hrsIn:SetText(prof.hours or "")
    f.bioIn:SetText(prof.bio or "")
    f:Show()
    f:Raise()
end

local allianceModalFrame

local function OpenAllianceManagementModal()
    if not allianceModalFrame then
        local m = CreateFrame("Frame", "SocialCentralAllianceModal", UIParent, "BackdropTemplate")
        m:SetSize(520, 440)
        m:SetPoint("CENTER")
        PrepareTopOverlayModal(m, 840)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        Theme:MakeMovable(m, { key = "modal_alliance_mgmt" })
        table.insert(UISpecialFrames, "SocialCentralAllianceModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -36, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["Alliance Management & Whitelist"])

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            if m.nameIn then m.nameIn:ClearFocus() end
            if m.tokenIn then m.tokenIn:ClearFocus() end
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        local helpBtn = AddHelp(
            m,
            title,
            L["Help: Cross-Guild Alliance"],
            L["Configure private cross-guild communication, shared Alliance chat, and member permissions."],
            L["Only Guild Leaders and appointed Alliance Managers can access this configuration. Toggle access for guild members individually or enable for all."]
        )

        -- Checkbox: Enable Alliance
        local chkEnabled = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
        chkEnabled:SetSize(22, 22)
        chkEnabled:SetPoint("TOPLEFT", 16, -42)
        local chkLabel = chkEnabled:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        chkLabel:SetPoint("LEFT", chkEnabled, "RIGHT", 4, 0)
        chkLabel:SetText(L["Enable Cross-Guild Alliance"])
        m.chkEnabled = chkEnabled

        -- Alliance Name input
        local nameLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameLbl:SetPoint("TOPLEFT", 16, -70)
        nameLbl:SetText(L["Alliance Name:"])
        local nameIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 40, placeholder = L["e.g. Frost Wolf Coalition"] })
        nameIn:SetPoint("TOPLEFT", 16, -86)
        nameIn:SetPoint("TOPRIGHT", -16, -86)
        m.nameIn = nameIn

        -- Alliance Token input
        local tokenLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tokenLbl:SetPoint("TOPLEFT", 16, -114)
        tokenLbl:SetText(L["Alliance Key / Token:"])
        local tokenIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 32, placeholder = L["e.g. FWC-SECRET-TOKEN"] })
        tokenIn:SetPoint("TOPLEFT", 16, -130)
        tokenIn:SetPoint("TOPRIGHT", -16, -130)
        m.tokenIn = tokenIn

        -- Access Mode buttons
        local modeLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        modeLbl:SetPoint("TOPLEFT", 16, -158)
        modeLbl:SetText(L["Access Mode:"])

        m._accessMode = "WHITELIST"
        local btnModeWl = Theme:CreateButton(m, 140, 22, L["Whitelist Only"], "default")
        btnModeWl:SetPoint("TOPLEFT", 16, -174)
        Theme:AutoFitButton(btnModeWl, 110, 14, 180)

        local btnModeAll = Theme:CreateButton(m, 140, 22, L["All Guild Members"], "default")
        btnModeAll:SetPoint("LEFT", btnModeWl, "RIGHT", 8, 0)
        Theme:AutoFitButton(btnModeAll, 110, 14, 180)

        btnModeWl:SetScript("OnClick", function()
            m._accessMode = "WHITELIST"
            Theme:SetButtonActive(btnModeWl, true, "default")
            Theme:SetButtonActive(btnModeAll, false, "default")
            m:RefreshMembers()
        end)
        btnModeAll:SetScript("OnClick", function()
            m._accessMode = "ALL"
            Theme:SetButtonActive(btnModeWl, false, "default")
            Theme:SetButtonActive(btnModeAll, true, "default")
            m:RefreshMembers()
        end)
        m.btnModeWl = btnModeWl
        m.btnModeAll = btnModeAll

        -- Member whitelist section
        local wlTitle = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        wlTitle:SetPoint("TOPLEFT", 16, -202)
        wlTitle:SetText(L["Guild Member Authorization:"])

        local memberHolder = CreateFrame("Frame", nil, m, "BackdropTemplate")
        memberHolder:SetPoint("TOPLEFT", 16, -218)
        memberHolder:SetPoint("BOTTOMRIGHT", -16, 44)
        Theme:ApplyBackdrop(memberHolder, "inset")

        local function CreateMemberRow(parent, _, rHeight)
            local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
            row:SetHeight(rHeight)

            row.nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.nameFs:SetPoint("LEFT", 8, 0)
            row.nameFs:SetWidth(132)
            row.nameFs:SetJustifyH("LEFT")
            row.nameFs:SetWordWrap(false)

            row.metaFs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.metaFs:SetPoint("LEFT", row.nameFs, "RIGHT", 6, 0)
            row.metaFs:SetJustifyH("LEFT")
            row.metaFs:SetWordWrap(false)

            row.btnToggle = Theme:CreateButton(row, 86, 20, L["Alliance Access"], "default")
            Theme:AutoFitButton(row.btnToggle, 70, 12, 110)
            row.btnToggle:SetPoint("RIGHT", -6, 0)
            row.btnToggle:SetScript("OnClick", function()
                local it = row.item
                if it and ns.Clan then
                    ns.Clan:SetMemberAllianceAccess(it.lookupKey, not it.authorized, it.isManager)
                    m:RefreshMembers()
                end
            end)

            row.btnMgr = Theme:CreateButton(row, 76, 20, L["Manager"], "default")
            Theme:AutoFitButton(row.btnMgr, 60, 12, 90)
            row.btnMgr:SetPoint("RIGHT", row.btnToggle, "LEFT", -6, 0)
            row.metaFs:SetPoint("RIGHT", row.btnMgr, "LEFT", -6, 0)
            row.btnMgr:SetScript("OnClick", function()
                local it = row.item
                local canMgr = ns.Clan and ns.Clan.IsGuildLeader and ns.Clan:IsGuildLeader()
                if it and ns.Clan and canMgr then
                    ns.Clan:SetMemberAllianceAccess(it.lookupKey, it.authorized, not it.isManager)
                    m:RefreshMembers()
                end
            end)

            return row
        end

        local function UpdateMemberRow(row, item)
            row.item = item
            local cR, cG, cB = 1, 1, 1
            if item.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[item.classFile] then
                local cc = RAID_CLASS_COLORS[item.classFile]
                cR, cG, cB = cc.r, cc.g, cc.b
            end
            row.nameFs:SetTextColor(cR, cG, cB)
            row.nameFs:SetText(item.displayName or "?")

            local rankTag = (item.rank and item.rank ~= "") and (" · " .. item.rank) or ""
            local lvlTag = item.level and item.level > 0 and L["Lv %d"]:format(item.level) or ""
            row.metaFs:SetText(lvlTag .. rankTag)

            local isAuth = (m._accessMode == "ALL") or item.authorized
            if isAuth then
                Theme:SetButtonText(row.btnToggle, "|cff3fb950" .. L["Alliance Access"] .. "|r")
                Theme:SetButtonActive(row.btnToggle, true, "default")
            else
                Theme:SetButtonText(row.btnToggle, "|cff8b949e" .. L["Alliance Access"] .. "|r")
                Theme:SetButtonActive(row.btnToggle, false, "default")
            end
            row.btnToggle:SetEnabled(m._accessMode == "WHITELIST")

            local isGM = ns.Clan and ns.Clan.IsGuildLeader and ns.Clan:IsGuildLeader()
            row.btnMgr:SetShown(isGM == true)
            if item.isManager then
                Theme:SetButtonText(row.btnMgr, "|cff58a6ff" .. L["Manager"] .. "|r")
                Theme:SetButtonActive(row.btnMgr, true, "default")
            else
                Theme:SetButtonText(row.btnMgr, "|cff8b949e" .. L["Manager"] .. "|r")
                Theme:SetButtonActive(row.btnMgr, false, "default")
            end
        end

        local memberScroll = Theme:CreateScrollList(memberHolder, 26, CreateMemberRow, UpdateMemberRow)
        memberScroll.container:SetAllPoints()
        m.memberScroll = memberScroll

        function m:RefreshMembers()
            if ns.Clan and ns.Clan.GetGuildMembersWithAllianceStatus then
                local list = ns.Clan:GetGuildMembersWithAllianceStatus()
                memberScroll:SetData(list)
            end
        end

        -- Bottom Buttons
        local btnClose = Theme:CreateButton(m, 88, 26, L["Close"], "default")
        Theme:AutoFitButton(btnClose, 80, 14, 130)
        btnClose:SetPoint("BOTTOMRIGHT", -16, 10)
        btnClose:SetScript("OnClick", function()
            if m.nameIn then m.nameIn:ClearFocus() end
            if m.tokenIn then m.tokenIn:ClearFocus() end
            m:Hide()
        end)
        m.btnClose = btnClose

        local btnSave = Theme:CreateButton(m, 140, 26, L["Save Configuration"], "primary")
        Theme:AutoFitButton(btnSave, 110, 16, 180)
        btnSave:SetPoint("RIGHT", btnClose, "LEFT", -8, 0)
        btnSave:SetScript("OnClick", function()
            if not ns.Clan then return end
            local isEnabled = m.chkEnabled:GetChecked() and true or false
            local aName = m.nameIn:GetText() or ""
            local aToken = m.tokenIn:GetText() or ""
            if ns.Clan:SaveAllianceConfig(isEnabled, aName, aToken, m._accessMode) then
                m:Hide()
            end
        end)
        m.btnSave = btnSave

        allianceModalFrame = m
    end

    PrepareTopOverlayModal(allianceModalFrame, 840)
    Theme:ApplyBackdrop(allianceModalFrame, "window")
    Theme:StyleButton(allianceModalFrame.topCloseBtn, "default")
    Theme:StyleButton(allianceModalFrame.btnClose, "default")
    Theme:StyleButton(allianceModalFrame.btnSave, "primary")

    local cfg = ns.Clan and ns.Clan.GetAllianceConfig and ns.Clan:GetAllianceConfig() or {}
    allianceModalFrame.chkEnabled:SetChecked(cfg.enabled == true)
    allianceModalFrame.nameIn:SetText(cfg.name or "")
    allianceModalFrame.tokenIn:SetText(cfg.token or "")
    allianceModalFrame._accessMode = (cfg.accessMode == "ALL") and "ALL" or "WHITELIST"

    Theme:SetButtonActive(allianceModalFrame.btnModeWl, allianceModalFrame._accessMode == "WHITELIST", "default")
    Theme:SetButtonActive(allianceModalFrame.btnModeAll, allianceModalFrame._accessMode == "ALL", "default")

    allianceModalFrame:RefreshMembers()
    allianceModalFrame:Show()
    if allianceModalFrame.Raise then allianceModalFrame:Raise() end
end

function UI:OpenAllianceManagementModal()
    OpenAllianceManagementModal()
end

local BELL_ON_TEX = "Interface\\AddOns\\SocialCentral\\Media\\bell-on"
local BELL_OFF_TEX = "Interface\\AddOns\\SocialCentral\\Media\\bell-off"

local function GetRowNotifyBellState(tab, item)
    if not item or (tab ~= "watchlist" and tab ~= "social") then
        return false, false, nil
    end
    local settings = ns.db and ns.db.settings
    local lookupKey = (tab == "watchlist") and (item.id or item.lookupKey) or item.lookupKey
    local isMuted = ns.Store and ns.Store.IsPlayerNotifyMuted
        and ns.Store:IsPlayerNotifyMuted(lookupKey, (tab == "watchlist") and item or nil, item.bnetAccountID)
        or false

    if tab == "watchlist" then
        local alerts = settings and settings.alerts
        local globalActive = (not alerts) or (alerts.toast ~= false or alerts.chat == true)
        if not globalActive then
            return true, false, L["Watchlist login alerts are disabled globally in Settings."]
        elseif isMuted then
            return true, false, L["Login alerts muted for this player. Click to enable."]
        end
        return true, true, L["Login alerts active for this player. Click to mute."]
    end

    local isFriend = item.sources and (item.sources.friend == true or item.sources.bnet == true)
    local isWatched = lookupKey and ns.Watchlist and ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(lookupKey)
    local isGuildOnly = (not isFriend) and (not isWatched) and (item.sources and item.sources.guild == true)

    if isGuildOnly then
        local guildOn = lookupKey and ns.Store and ns.Store.IsGuildLoginNotifyEnabled and ns.Store:IsGuildLoginNotifyEnabled(lookupKey)
        local alertMode = (settings and settings.friendOnlineAlertMode) or "all"
        local globalActive = (not settings) or (settings.friendOnlineAlertToast ~= false or settings.friendOnlineAlertChat == true)
        if alertMode == "off" or not globalActive then
            return true, false, L["Friend/Guild login alerts are disabled globally in Settings."]
        elseif guildOn and not isMuted then
            return true, true, L["Login alerts active for this guildmate. Click to mute."]
        end
        return true, false, L["Guildmate login alerts are off by default. Click the bell to enable notifications for this player."]
    end

    local alertMode = (settings and settings.friendOnlineAlertMode) or "all"
    local globalActive = (not settings) or (settings.friendOnlineAlertToast ~= false or settings.friendOnlineAlertChat == true)
    if isWatched and settings and settings.alerts and (settings.alerts.toast ~= false or settings.alerts.chat == true) then
        globalActive = true
    end

    if alertMode == "off" or not globalActive then
        return true, false, L["Friend online alerts are disabled globally in Settings."]
    elseif isMuted then
        return true, false, L["Login alerts muted for this player. Click to enable."]
    elseif alertMode == "favorites" then
        local isFav = (lookupKey ~= nil and ns.Store and ns.Store.IsSocialFavorite and ns.Store:IsSocialFavorite(lookupKey)) == true
        if not isFav then
            return true, false, L["Favorites Only mode active in Settings. Click the bell to favorite and enable alerts for this player."]
        end
    end
    return true, true, L["Login alerts active for this player. Click to mute."]
end

local function ToggleRowNotifyBell(tab, item)
    if not item or not ns.Store then return end
    local settings = ns.db and ns.db.settings
    local lookupKey = (tab == "watchlist") and (item.id or item.lookupKey) or item.lookupKey
    local isMuted = ns.Store.IsPlayerNotifyMuted
        and ns.Store:IsPlayerNotifyMuted(lookupKey, (tab == "watchlist") and item or nil, item.bnetAccountID)
        or false

    if tab == "watchlist" then
        local nextMuted = not isMuted
        if ns.Store.SetPlayerNotifyMuted then
            ns.Store:SetPlayerNotifyMuted(lookupKey or item.displayName, nextMuted, item.bnetAccountID)
        end
        if type(item) == "table" then
            item.notifyMuted = nextMuted and true or nil
        end
        UI:QueueRefresh(true)
        return
    end

    local isFriend = item.sources and (item.sources.friend == true or item.sources.bnet == true)
    local isWatched = lookupKey and ns.Watchlist and ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(lookupKey)
    local isGuildOnly = (not isFriend) and (not isWatched) and (item.sources and item.sources.guild == true)

    if isGuildOnly and lookupKey then
        local curGuildOn = ns.Store.IsGuildLoginNotifyEnabled and ns.Store:IsGuildLoginNotifyEnabled(lookupKey)
        if ns.Store.SetGuildLoginNotifyEnabled then
            ns.Store:SetGuildLoginNotifyEnabled(lookupKey, not curGuildOn)
        end
        UI:QueueRefresh(true)
        return
    end

    local alertMode = (settings and settings.friendOnlineAlertMode) or "all"
    if alertMode == "favorites" then
        local isFav = (lookupKey ~= nil and ns.Store.IsSocialFavorite and ns.Store:IsSocialFavorite(lookupKey)) == true
        if not isFav and not isMuted then
            if lookupKey and ns.Store.ToggleSocialFavorite then
                ns.Store:ToggleSocialFavorite(lookupKey)
            end
            UI:QueueRefresh(true)
            return
        end
    end

    if ns.Store.SetPlayerNotifyMuted then
        ns.Store:SetPlayerNotifyMuted(lookupKey or item.displayName, not isMuted, item.bnetAccountID)
    end
    UI:QueueRefresh(true)
end

local function OpenRowMenu(row, item, tabOverride)
    if not (MenuUtil and MenuUtil.CreateContextMenu and item) then
        return
    end
    local tab = tabOverride or item._tab or activeTab
    local targetName = item.displayName or item.name or item.bnetName
    local charKey = item.lookupKey or item.id
    local isFav = (charKey ~= nil and ns.Store and ns.Store.IsSocialFavorite and ns.Store:IsSocialFavorite(charKey)) == true

    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(targetName or "")
        if tab == "watchlist" then
            if not item.isSessionBNet then
                if type(item.ambiguousChoices) == "table" and #item.ambiguousChoices > 1 then
                    root:CreateButton(L["Choose Exact Character..."], function()
                        UI:OpenWatchlistDisambiguation(item.id)
                    end)
                elseif type(item.observedCandidate) == "string" and item.observedCandidate ~= "" then
                    root:CreateButton(L["Confirm: %s"]:format(item.observedCandidate), function()
                        if ns.Watchlist and ns.Watchlist.ResolveDisambiguation then
                            ns.Watchlist:ResolveDisambiguation(item.id, item.observedCandidate)
                        end
                    end)
                end
                root:CreateButton(L["Check"], function()
                    if ns.Watchlist then
                        ns.Watchlist:CheckEntry(item.id, false, true)
                    end
                end)
            end
            root:CreateButton(item.favorite and L["Unfavorite"] or L["Favorite"], function()
                if ns.Watchlist then
                    ns.Watchlist:ToggleFavorite(item.id)
                end
            end)
            root:CreateButton(L["Set Group Tag"], function()
                OpenGroupModal(item)
            end)
            root:CreateButton(L["Edit Note"], function()
                OpenNoteModal(item)
            end)
            if not item.isSessionBNet then
                root:CreateButton(
                    (item.watchAllAlts == true and "|cff3fb950[x]|r " or "") .. L["Track all Battle.net / linked alts"],
                    function()
                        if ns.Watchlist and ns.Watchlist.ToggleWatchAllAlts then
                            ns.Watchlist:ToggleWatchAllAlts(item.id)
                        end
                    end
                )
                root:CreateButton(L["Pin to Character Friends"], function()
                    if ns.Watchlist then
                        ns.Watchlist:PinToFriends(item.id)
                    end
                end)
            end
            local _, bellActive = GetRowNotifyBellState("watchlist", item)
            root:CreateButton(bellActive and L["Mute Login Alerts"] or L["Enable Login Alerts"], function()
                ToggleRowNotifyBell("watchlist", item)
            end)
        elseif tab == "social" or tab == "nearby" then
            if charKey and item.hasCharacterName ~= false and item.samePool ~= false and item.sameFaction ~= false
                and not (Compat.IsMe and Compat.IsMe(targetName, item.guid))
                and ns.Watchlist and ns.Watchlist.CheckCharacter
            then
                root:CreateButton(L["Check"], function()
                    if ns.Watchlist and ns.Watchlist.CheckCharacter then
                        ns.Watchlist:CheckCharacter(targetName, false)
                    end
                end)
            end
            if charKey and not (Compat.IsMe and Compat.IsMe(targetName, item.guid)) then
                local starMark = Compat.FavoriteStarMarkup and Compat.FavoriteStarMarkup(12) or ""
                root:CreateButton(isFav and (starMark .. L["Unfavorite"]) or L["Favorite"], function()
                    if charKey and ns.Store and ns.Store.ToggleSocialFavorite then
                        ns.Store:ToggleSocialFavorite(charKey)
                    end
                    UI:QueueRefresh(false)
                end)
            end
            if tab == "social" and (charKey or (item.sources and item.sources.bnet and item.bnetAccountID)) then
                local _, bellActive = GetRowNotifyBellState("social", item)
                root:CreateButton(bellActive and L["Mute Login Alerts"] or L["Enable Login Alerts"], function()
                    ToggleRowNotifyBell("social", item)
                end)
            end

            local isBNetRow = (tab == "social") and item.sources and item.sources.bnet == true and item.bnetAccountID ~= nil
            if isBNetRow and ns.Watchlist then
                local bWatched, bWlKey, bWlEntry = ns.Watchlist.IsBNetAccountWatched and ns.Watchlist:IsBNetAccountWatched(item.bnetAccountID)
                if bWatched and bWlKey then
                    root:CreateButton(L["Remove from Watchlist"], function()
                        UI:OpenConfirmModal({
                            title = L["Remove from Watchlist"],
                            message = L["Are you sure you want to remove %s from your Watchlist?"]:format((bWlEntry and bWlEntry.displayName) or item.bnetName or targetName or "?"),
                            confirmText = L["Remove"],
                            onConfirm = function()
                                if ns.Watchlist then
                                    ns.Watchlist:Remove(bWlKey)
                                    UI:QueueRefresh(false)
                                end
                            end,
                        })
                    end)
                else
                    root:CreateButton(L["Watch Battle.net Account (All Alts)"], function()
                        if ns.Watchlist and ns.Watchlist.AddBNetAccount then
                            ns.Watchlist:AddBNetAccount(item)
                            UI:QueueRefresh(false)
                        end
                    end)
                end
            elseif charKey or tab == "nearby" then
                local wlLookup = charKey or targetName
                local isWatched = ns.Watchlist and ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(wlLookup)
                if isWatched then
                    root:CreateButton(L["Remove from Watchlist"], function()
                        UI:OpenConfirmModal({
                            title = L["Remove from Watchlist"],
                            message = L["Are you sure you want to remove %s from your Watchlist?"]:format(targetName or wlLookup or "?"),
                            confirmText = L["Remove"],
                            onConfirm = function()
                                if ns.Watchlist then
                                    ns.Watchlist:Remove(wlLookup)
                                    UI:QueueRefresh(false)
                                end
                            end,
                        })
                    end)
                else
                    root:CreateButton(L["Add to Watchlist"], function()
                        if ns.Watchlist then
                            ns.Watchlist:Add(targetName or wlLookup)
                            UI:QueueRefresh(false)
                        end
                    end)
                end
            end

            if tab == "social" and charKey and not (item.sources and item.sources.friend) and item.samePool ~= false and item.sameFaction ~= false then
                root:CreateButton("+ " .. L["Add Character Friend"], function()
                    if Compat.AddCharacterFriend then
                        if not Compat.AddCharacterFriend(targetName) then
                            ns:Print("%s", L["Cannot modify friends while in combat."])
                        end
                    end
                end)
            end
        end

        local isSelfRow = (item.isSelf == true) or (item.isMe == true) or (Compat.IsMe and targetName and Compat.IsMe(targetName, item.guid))
        if targetName and tab ~= "alts" and not isSelfRow then
            if charKey then
                local curMeta = ns.Store and (ns.Store.GetResolvedSocialMeta and ns.Store:GetResolvedSocialMeta(charKey) or (ns.Store.GetSocialMeta and ns.Store:GetSocialMeta(charKey)))
                local goodLabel = (curMeta and curMeta.flag == "GOOD") and ("|cff3fb950[x]|r " .. L["Good Partner (+)"]) or L["Good Partner (+)"]
                root:CreateButton(goodLabel, function()
                    if ns.Store and ns.Store.SetSocialFlag then
                        ns.Store:SetSocialFlag(charKey, "GOOD")
                        UI:QueueRefresh(false)
                    end
                end)
                local avoidLabel = (curMeta and curMeta.flag == "AVOID") and ("|cffff4d4d[x]|r " .. L["Flag: Avoid"]) or L["Flag: Avoid"]
                root:CreateButton(avoidLabel, function()
                    if ns.Store and ns.Store.SetSocialFlag then
                        ns.Store:SetSocialFlag(charKey, "AVOID")
                        UI:QueueRefresh(false)
                    end
                end)
                local isAcctIgn = ns.Store and ns.Store.IsAccountIgnored and ns.Store:IsAccountIgnored(charKey)
                local ignLabel = isAcctIgn and ("|cffff4d4d[x]|r " .. L["Edit Account Ignore..."]) or L["Account Ignore..."]
                root:CreateButton(ignLabel, function()
                    if ns.SocialPanels and ns.SocialPanels.OpenAccountIgnoreModal then
                        ns.SocialPanels:OpenAccountIgnoreModal(targetName, charKey)
                    end
                end)
                if isAcctIgn then
                    root:CreateButton("|cff3fb950" .. L["Unblock"] .. "|r", function()
                        if UI.OpenConfirmModal then
                            UI:OpenConfirmModal({
                                title = L["Unblock"],
                                message = L["Are you sure you want to remove '%s' from your Account Ignore list?"]:format(targetName or charKey),
                                confirmText = L["Unblock"],
                                confirmVariant = "danger",
                                onConfirm = function()
                                    if ns.Store and ns.Store.RemoveAccountIgnore then
                                        ns.Store:RemoveAccountIgnore(charKey, true)
                                    end
                                end,
                            })
                        elseif ns.Store and ns.Store.RemoveAccountIgnore then
                            ns.Store:RemoveAccountIgnore(charKey, true)
                        end
                    end)
                end
            end

            if charKey or (item.sources and item.sources.bnet and item.bnetAccountID) then
                root:CreateButton(L["Edit Social Card"], function()
                    if ns.SocialPanels and ns.SocialPanels.OpenSocialMetaModal then
                        ns.SocialPanels:OpenSocialMetaModal(targetName, charKey or targetName, item)
                    end
                end)
            end

            if tab == "social" and ((item.sources and item.sources.friend) or (item.sources and item.sources.bnet and item.bnetAccountID)) then
                local noteLbl = (item.sources and item.sources.friend) and L["Edit Blizzard Friend Note"] or L["Edit Battle.net Note"]
                root:CreateButton(noteLbl, function()
                    OpenNativeFriendNoteModal(item)
                end)
            end

            root:CreateDivider()
            local bnetInfo = (charKey and ns.Social and ns.Social.GetBNetLinkInfo) and ns.Social:GetBNetLinkInfo(charKey) or nil
            local dirRow = (charKey and ns.Store and ns.Store.socialDirectoryByLookup) and ns.Store.socialDirectoryByLookup[charKey] or nil
            local bnetAccId = item.bnetAccountID or (bnetInfo and bnetInfo.bnetAccountID)
            local bnetName = item.bnetName or (bnetInfo and bnetInfo.bnetName)
            local isCrossFaction = (item.sameFaction == false) or (dirRow and dirRow.sameFaction == false) or (bnetInfo and bnetInfo.sameFaction == false)
            local scConfirmed = ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(charKey or targetName, bnetAccId)
            if scConfirmed and (charKey or (item.sources and item.sources.bnet and bnetAccId)) then
                root:CreateButton(L["Open in SocialCentral Chat"], function()
                    if ns.Chat and ns.Chat.OpenDirectConversation then
                        ns.Chat:OpenDirectConversation({
                            targetName = item.hasCharacterName ~= false and targetName or nil,
                            bnetAccountID = bnetAccId,
                            bnetName = bnetName,
                            classFile = item.classFile,
                            autoProbe = item.online ~= false,
                        })
                        UI:OpenTab("chat")
                    end
                end)
            end
            local whisperLabel = (isCrossFaction and bnetName) and L["Battle.net Whisper"] or L["WoW Whisper (/w)"]
            root:CreateButton(whisperLabel, function()
                if isCrossFaction and bnetName then
                    Compat.BNetWhisper(bnetName, item.hasCharacterName ~= false and targetName or nil)
                elseif tab == "social" and ((item.samePool == false or item.hasCharacterName == false or item.bnetState == "bnet_app" or item.bnetState == "wow_other") and bnetName) then
                    Compat.BNetWhisper(bnetName, item.hasCharacterName ~= false and targetName or nil)
                elseif tab == "social" and not item.online and bnetName then
                    Compat.BNetWhisper(bnetName, item.hasCharacterName ~= false and targetName or nil)
                else
                    Compat.Whisper(targetName)
                end
            end)
            local inGroupNow = (Compat.IsInMyGroup and Compat.IsInMyGroup(targetName, item.guid)) == true
            local canInvite = (item.online ~= false or tab == "watchlist")
                and (not isCrossFaction)
                and (not inGroupNow)
                and (item.samePool ~= false)
                and (item.hasCharacterName ~= false)
                and (not item.bnetState or item.bnetState == "wow_forever" or (item.sources and (item.sources.friend or item.sources.guild)))
            if canInvite then
                root:CreateButton(L["Invite"], function()
                    Compat.Invite(targetName, bnetAccId)
                end)
            end
        end

        if targetName and not isSelfRow and item.hasCharacterName ~= false and item.samePool ~= false and ns.Spotter and ns.Spotter.TrackPlayer then
            if tab == "watchlist" or tab == "social" or tab == "nearby" or tab == "clan" then
                local isTracked = ns.Spotter.IsPlayerTracked and ns.Spotter:IsPlayerTracked(targetName, item.guid)
                if isTracked and ns.Spotter.UntrackPlayer then
                    root:CreateButton(L["Untrack from Radar"], function()
                        ns.Spotter:UntrackPlayer(targetName, item.guid)
                        UI:QueueRefresh(false)
                    end)
                else
                    root:CreateButton(L["Track on Radar"], function()
                        local stanceHint = (tab == "watchlist" or item.isWatchlist) and "WATCHLIST"
                            or ((item.sources and (item.sources.friend or item.sources.bnet)) or item.isFriend) and "FRIEND"
                            or (item.isAllied and "ALLY")
                            or (item.isClan and "SAME")
                            or nil
                        ns.Spotter:TrackPlayer(targetName, item.guild, item.classFile, item.level, item.guid, stanceHint)
                        UI:QueueRefresh(false)
                    end)
                end
            end
        end

        root:CreateButton(L["Copy Name"], function()
            OpenCopyModal(targetName)
        end)

        if item._isGuildRosterRow and charKey and targetName and not Compat.IsMe(targetName, item.guid) and ns.Clan and ns.Clan.GetSelfGuildRank then
            local selfRank = ns.Clan:GetSelfGuildRank()
            local canPromote = selfRank.canPromote and item.rankIndex and item.rankIndex > 1
            local canDemote = selfRank.canDemote and item.rankIndex and item.rankIndex > 0
            local canNote = selfRank.canEditPublicNote
            local canAssign = (selfRank.isGuildLeader or selfRank.canPromote or selfRank.canDemote) and C_GuildInfo and C_GuildInfo.SetGuildRankOrder
            local canAllyMgr = selfRank.isGuildLeader and ns.Clan.SetMemberAllianceAccess
            if canPromote or canDemote or canNote or canAssign or canAllyMgr then
                root:CreateDivider()
                local curRankStr = (item.rankName and item.rankName ~= "") and (" (" .. item.rankName .. ")") or ""
                root:CreateTitle(L["Guild Hierarchy"] .. curRankStr)
                if canPromote then
                    root:CreateButton(L["Promote in Guild"], function()
                        ns.Clan:PromoteMember(charKey, targetName, item.guid)
                    end)
                end
                if canDemote then
                    root:CreateButton(L["Demote in Guild"], function()
                        ns.Clan:DemoteMember(charKey, targetName, item.guid)
                    end)
                end
                if canAssign then
                    local ranks = ns.Clan.GetGuildRanks and ns.Clan:GetGuildRanks() or {}
                    if #ranks > 1 then
                        local assignBtn = root:CreateButton(L["Assign Game Rank"])
                        if assignBtn and assignBtn.CreateButton then
                            for _, rk in ipairs(ranks) do
                                if rk.rankIndex >= 1 then
                                    local rIdx = rk.rankIndex
                                    local rLabel = string.format("#%d %s", rIdx, rk.name)
                                    assignBtn:CreateRadio(rLabel, function()
                                        return item.rankIndex == rIdx
                                    end, function()
                                        ns.Clan:SetMemberRank(charKey, item.guid, rIdx)
                                    end)
                                end
                            end
                        end
                    end
                end
                if canNote then
                    root:CreateButton(L["Edit Public Note"], function()
                        OpenPublicNoteModal(item)
                    end)
                end
                if canAllyMgr then
                    root:CreateButton(L["Alliance"], function()
                        OpenAllianceManagementModal()
                    end)
                end
            end
        end

        if tab == "watchlist" then
            root:CreateDivider()
            root:CreateButton(L["Remove"], function()
                UI:OpenConfirmModal({
                    title = L["Remove from Watchlist"],
                    message = L["Are you sure you want to remove %s from your Watchlist?"]:format(item.displayName or item.name or item.id or "?"),
                    confirmText = L["Remove"],
                    onConfirm = function()
                        if ns.Watchlist then
                            ns.Watchlist:Remove(item.id)
                        end
                    end,
                })
            end)
        elseif tab == "social" and item.sources and item.sources.friend then
            root:CreateDivider()
            root:CreateButton("|cffff5555" .. L["Remove Friend"] .. "|r", function()
                OpenRemoveFriendConfirmModal(item)
            end)
        end
    end)
end

function UI._ComputeRowRightReserve(row, showAct, showInv, showWhisp, showMeta)
    local edgePad = row._lastEdgePad or 8
    local whispGap = row._lastWhispGap or 4
    local hasButtons = showAct or showInv or showWhisp
    local reserve = hasButtons and edgePad or 10
    if showAct and row.btnAction then
        reserve = reserve + math.ceil(row.btnAction:GetWidth() or 70)
    else
        if showInv and row.btnInvite then
            reserve = reserve + math.ceil(row.btnInvite:GetWidth() or 24)
        end
        if showInv and showWhisp then
            reserve = reserve + whispGap
        end
        if showWhisp and row.btnWhisper then
            reserve = reserve + math.ceil(row.btnWhisper:GetWidth() or 24)
        end
    end
    if showMeta and row.metaRight then
        reserve = reserve + (hasButtons and 6 or 0) + math.ceil(row.metaRight:GetWidth() or 0) + 8
    elseif hasButtons then
        reserve = reserve + 8
    end
    return math.max(10, reserve)
end

function UI._ApplyRowTextAnchors(row, textLeftX, rightReservePx, isCompactMode)
    if row.nameText then
        row.nameText:ClearAllPoints()
        if isCompactMode then
            row.nameText:SetPoint("LEFT", row, "LEFT", textLeftX, 0)
        else
            row.nameText:SetPoint("TOPLEFT", textLeftX, -5)
        end
        row.nameText:SetPoint("RIGHT", row, "RIGHT", -rightReservePx, 0)
        row.nameText:Show()
    end
    if row.subText then
        row.subText:ClearAllPoints()
        row.subText:SetPoint("BOTTOMLEFT", textLeftX, 5)
        row.subText:SetPoint("RIGHT", row, "RIGHT", -rightReservePx, 0)
        row.subText:SetShown(not isCompactMode)
    end
end

local function CreateListRow(parent, _, rowHeight)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(rowHeight)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.statusBar = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.statusBar:SetWidth(3)
    row.statusBar:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -4)
    row.statusBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 4)
    row.statusBar:SetColorTexture(0.35, 0.75, 1.0, 0.75)

    row.dot = row:CreateTexture(nil, "ARTWORK", nil, 2)
    row.dot:SetSize(8, 8)
    row.dot:SetPoint("LEFT", 9, 0)
    row.dot:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\dot")
    row.dot._scKeepTexture = true

    row.btnNotifyBell = CreateFrame("Button", nil, row)
    row.btnNotifyBell:SetSize(15, 15)
    row.btnNotifyBell:SetPoint("LEFT", row.dot, "RIGHT", 4, 0)
    row.btnNotifyBell:SetHitRectInsets(-3, -3, -3, -3)
    row.btnNotifyBell.tex = row.btnNotifyBell:CreateTexture(nil, "ARTWORK")
    row.btnNotifyBell.tex:SetAllPoints()
    row.btnNotifyBell:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    row.btnNotifyBell:SetScript("OnClick", function()
        if not row._item then return end
        local tab = row._item._tab or activeTab
        ToggleRowNotifyBell(tab, row._item)
    end)
    row.btnNotifyBell:SetScript("OnEnter", function(selfBell)
        if not row._item or not GameTooltip then return end
        local tab = row._item._tab or activeTab
        local shown, active, tipText = GetRowNotifyBellState(tab, row._item)
        if not shown then return end
        GameTooltip:SetOwner(selfBell, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:SetText(active and L["Login Alerts Active"] or L["Login Alerts Muted"], 1, 1, 1)
        if tipText then
            GameTooltip:AddLine(tipText, 0.85, 0.88, 0.92, true)
        end
        GameTooltip:Show()
    end)
    row.btnNotifyBell:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.btnNotifyBell:Hide()

    row.classIcon = row:CreateTexture(nil, "ARTWORK", nil, 2)
    row.classIcon:SetSize(20, 20)
    row.classIcon:SetPoint("LEFT", row.dot, "RIGHT", 6, 0)
    row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    row.classIcon:Hide()

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.nameText:SetPoint("TOPLEFT", 26, -5)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.subText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.subText:SetPoint("BOTTOMLEFT", 26, 5)
    row.subText:SetJustifyH("LEFT")
    row.subText:SetWordWrap(false)

    row.metaRight = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.metaRight:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.metaRight:SetJustifyH("RIGHT")
    row.metaRight:SetWordWrap(false)
    row.metaRight:Hide()

    function row:_syncHover(hovered)
        local isHov = (hovered == true)
        local wantWhisper = (self._alwaysShowWhisper == true) or ((self._hasHoverWhisper == true) and isHov)
        local wantInvite = (self._alwaysShowInvite == true) or ((self._hasHoverInvite == true) and isHov)
        local hasBtns = (self._hasHoverWhisper == true) or (self._hasHoverInvite == true)
        if self.btnWhisper then
            self.btnWhisper:SetShown(wantWhisper)
        end
        if self.btnInvite then
            self.btnInvite:SetShown(wantInvite)
        end
        local showMeta = (self._hasMetaRight == true) and (not (hasBtns and isHov))
        if self.metaRight then
            self.metaRight:SetShown(showMeta)
        end
        if self._item and not self._item._isSocialFolderHeader and not self._item._isSocialDetailRow then
            local showAct = (self.btnAction and self.btnAction:IsShown()) == true
            local hoverRightReserve = UI._ComputeRowRightReserve(self, showAct, wantInvite and self.btnInvite ~= nil, wantWhisper and self.btnWhisper ~= nil, showMeta and self.metaRight ~= nil)
            if self._lastHoverRightReserve ~= hoverRightReserve then
                self._lastHoverRightReserve = hoverRightReserve
                local textLeftX = self._lastTextLeftX or (24 + (self._lastBellShown and 19 or 0) + (self._lastClassIconShown and 25 or 0))
                UI._ApplyRowTextAnchors(self, textLeftX, hoverRightReserve, self._lastCompactMode == true)
            end
        end
    end

    row.btnRemove = Theme:CreateButton(row, 24, 22, "X", "danger")
    row.btnRemove:SetPoint("RIGHT", -8, 0)

    row.btnInvite = Theme:CreateButton(row, 24, 22, "", "default")
    row.btnInvite.ico = (row.btnInvite._textLayer or row.btnInvite):CreateTexture(nil, "OVERLAY", nil, 2)
    row.btnInvite.ico:SetSize(14, 14)
    row.btnInvite.ico:SetPoint("CENTER")
    row.btnInvite.ico:SetTexture("Interface\\PaperDollInfoFrame\\Character-Plus")
    row.btnInvite.ico:SetVertexColor(0.45, 0.95, 0.55)
    row.btnInvite.ico:Hide()
    row.btnInvite:HookScript("OnEnter", function(selfBtn)
        row:_syncHover(true)
        Theme:ApplyBackdrop(row, "surface", Theme:GetPalette())
        if GameTooltip and selfBtn._scCompactIcon then
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:SetText(L["Invite to Group"], 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    row.btnInvite:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
        if not (row:IsMouseOver() or (row.btnWhisper and row.btnWhisper:IsShown() and row.btnWhisper:IsMouseOver())) then
            row:_syncHover(false)
            Theme:ApplyBackdrop(row, (row._dataIdx and row._dataIdx % 2 == 1) and "row" or "rowAlt", Theme:GetPalette())
        end
    end)

    row.btnWhisper = Theme:CreateButton(row, 24, 22, "", "default")
    row.btnWhisper.ico = (row.btnWhisper._textLayer or row.btnWhisper):CreateTexture(nil, "OVERLAY", nil, 2)
    row.btnWhisper.ico:SetSize(13, 13)
    row.btnWhisper.ico:SetPoint("CENTER")
    row.btnWhisper.ico:SetTexture("Interface\\Icons\\INV_Letter_15")
    row.btnWhisper.ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.btnWhisper.ico:Hide()
    row.btnWhisper:HookScript("OnEnter", function(selfBtn)
        row:_syncHover(true)
        Theme:ApplyBackdrop(row, "surface", Theme:GetPalette())
        if GameTooltip then
            if selfBtn._hasSocialCentral then
                GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(L["Chat in SocialCentral"], 0.25, 0.78, 1.0, true)
                GameTooltip:AddLine(L["Player has SocialCentral installed. Click to open direct conversation."], 0.80, 0.86, 0.94, true)
                GameTooltip:Show()
            elseif selfBtn._scCompactIcon then
                GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(L["Whisper"], 1.0, 0.85, 0.25, true)
                GameTooltip:Show()
            end
        end
    end)
    row.btnWhisper:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
        if not (row:IsMouseOver() or (row.btnInvite and row.btnInvite:IsShown() and row.btnInvite:IsMouseOver())) then
            row:_syncHover(false)
            Theme:ApplyBackdrop(row, (row._dataIdx and row._dataIdx % 2 == 1) and "row" or "rowAlt", Theme:GetPalette())
        end
    end)
    Theme:AutoFitButton(row.btnWhisper, 72, 18)

    row.btnAction = Theme:CreateButton(row, 86, 22, L["Check"], "primary")
    Theme:AutoFitButton(row.btnAction, 70, 18)

    row.btnRemove:SetScript("OnClick", function()
        if not row._item then return end
        local targetItem = row._item
        local tab = targetItem._tab or activeTab
        if tab ~= "alts" and ns.Watchlist then
            UI:OpenConfirmModal({
                title = L["Remove from Watchlist"],
                message = L["Are you sure you want to remove %s from your Watchlist?"]:format(targetItem.displayName or targetItem.name or targetItem.id or "?"),
                confirmText = L["Remove"],
                onConfirm = function()
                    if ns.Watchlist then
                        ns.Watchlist:Remove(targetItem.id)
                    end
                end,
            })
        end
    end)

    row.btnWhisper:SetScript("OnClick", function()
        local item = row._item
        if not item then return end
        local tab = item._tab or activeTab
        local targetDisp = (tab == "watchlist" and item.activeAltName) or item.displayName
        local targetKey = (tab == "watchlist" and item.activeAltLookup) or item.lookupKey or item.id or targetDisp
        local bnetInfo = (targetKey and ns.Social and ns.Social.GetBNetLinkInfo) and ns.Social:GetBNetLinkInfo(targetKey) or nil
        if (not bnetInfo) and tab == "watchlist" and item.id and ns.Social and ns.Social.GetBNetLinkInfo then
            bnetInfo = ns.Social:GetBNetLinkInfo(item.id)
        end
        local dirRow = (targetKey and ns.Store and ns.Store.socialDirectoryByLookup) and ns.Store.socialDirectoryByLookup[targetKey] or nil
        local bnetAccId = item.bnetAccountID or (bnetInfo and bnetInfo.bnetAccountID)
        local bnetName = item.bnetName or (bnetInfo and bnetInfo.bnetName)
        local isCrossFaction = (item.sameFaction == false) or (dirRow and dirRow.sameFaction == false) or (bnetInfo and bnetInfo.sameFaction == false)
        local scConfirmed = ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(targetKey, bnetAccId)
        if scConfirmed and ns.Chat and ns.Chat.OpenDirectConversation then
            ns.Chat:OpenDirectConversation({
                targetName = (item.hasCharacterName ~= false and not item.isSessionBNet) and targetDisp or nil,
                bnetAccountID = bnetAccId,
                bnetName = bnetName,
                classFile = item.activeAltClass or item.classFile,
                autoProbe = item.online ~= false,
            })
            UI:OpenTab("chat")
        elseif ((tab == "social" or (tab == "watchlist" and item.isSessionBNet)) and ((item.samePool == false or item.hasCharacterName == false or item.isSessionBNet or item.bnetState == "bnet_app" or item.bnetState == "wow_other") and bnetName)) then
            Compat.BNetWhisper(bnetName, (item.hasCharacterName ~= false and not item.isSessionBNet) and targetDisp or nil)
        elseif isCrossFaction and bnetName then
            Compat.BNetWhisper(bnetName, (item.hasCharacterName ~= false and not item.isSessionBNet) and targetDisp or nil)
        else
            Compat.Whisper(targetDisp)
        end
    end)

    row.btnInvite:SetScript("OnClick", function()
        local item = row._item
        if not item then return end
        local tab = item._tab or activeTab
        local targetKey = (tab == "watchlist" and item.activeAltLookup) or item.lookupKey or item.id or item.displayName
        local bInfo = (targetKey and ns.Social and ns.Social.GetBNetLinkInfo) and ns.Social:GetBNetLinkInfo(targetKey) or nil
        local bnetAccId = item.bnetAccountID or (bInfo and bInfo.bnetAccountID)
        local target = (tab == "watchlist" and item.activeAltName) or item.displayName or item.name or item.id
        if target then
            Compat.Invite(target, bnetAccId)
        end
    end)

    row.btnAction:SetScript("OnClick", function()
        local item = row._item
        if not item then return end
        local tab = item._tab or activeTab
        if tab == "watchlist" and ns.Watchlist then
            if type(item.ambiguousChoices) == "table" and #item.ambiguousChoices > 1 then
                UI:OpenWatchlistDisambiguation(item.id)
            elseif type(item.observedCandidate) == "string" and item.observedCandidate ~= "" then
                ns.Watchlist:ResolveDisambiguation(item.id, item.observedCandidate)
            else
                ns.Watchlist:CheckEntry(item.id, false, true)
            end
        elseif (tab == "social" or tab == "nearby") and ns.Watchlist then
            if item.sources and item.sources.bnet and item.bnetAccountID and ns.Watchlist.AddBNetAccount then
                ns.Watchlist:AddBNetAccount(item)
            else
                ns.Watchlist:Add(item.displayName or item.lookupKey)
            end
        end
    end)

    row:SetScript("OnClick", function(self, mouseButton)
        if not self._item then return end
        if self._item._isSocialFolderHeader then
            local fk = self._item.folderKey
            if fk and fk ~= "__fav" then
                local tabMap = (activeTab == "watchlist") and collapsedSocialFolders.watchlist or collapsedSocialFolders.social
                local curColl = (tabMap[fk] ~= false)
                tabMap[fk] = not curColl
            end
            UI:Refresh(false)
            return
        end
        if self._item._isSocialDetailRow then
            if mouseButton == "RightButton" and self._item.parentItem then
                OpenRowMenu(self, self._item.parentItem)
            end
            return
        end
        local tab = self._item._tab or activeTab
        if tab == "social" and mouseButton == "LeftButton" then
            local eKey = UI._GetSocialItemExpandKey(self._item)
            if eKey then
                UI._expandedSocialKey = (UI._expandedSocialKey == eKey) and nil or eKey
                UI:Refresh(false)
                return
            end
        end
        if mouseButton == "RightButton" or mouseButton == "LeftButton" then
            OpenRowMenu(self, self._item)
        end
    end)

    row:SetScript("OnEnter", function(self)
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(self, "surface", p)
        if self._syncHover then self:_syncHover(true) end
        if self._item and self._item._isSocialDetailRow then
            return
        end
        if self._item and self._item._isSocialFolderHeader then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self._item.folderLabel or L["Social Folders"], 1.0, 0.84, 0.28)
            GameTooltip:AddLine(string.format(L["%d online / %d total"], self._item.onlineCount or 0, self._item.totalCount or 0), 0.72, 0.88, 1.0)
            GameTooltip:AddLine(L["Click: Expand / Collapse"], 0.45, 0.85, 1.0)
            GameTooltip:Show()
            return
        end
        if self._item then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            local item = self._item
            local tab = item._tab or activeTab
            local titleName = item.fullName or item.displayName or item.name or item.bnetName or ""
            if Compat and Compat.IsStreamerMode and Compat.IsStreamerMode() and (item.bnetAccountID ~= nil or titleName:find("#", 1, true)) and (titleName == item.bnetName or item.hasCharacterName == false) then
                titleName = Compat.MaskStreamerBNetName(titleName)
            end
            GameTooltip:AddLine(titleName, 1, 1, 1)
            local rowKey = item.lookupKey or item.id
            local bnetInfo = (rowKey and ns.Social and ns.Social.GetBNetLinkInfo) and ns.Social:GetBNetLinkInfo(rowKey) or nil
            local bnetDisplay = (item.bnetName and item.bnetName ~= "" and item.bnetName) or (bnetInfo and bnetInfo.bnetName)
            if Compat and Compat.IsStreamerMode and Compat.IsStreamerMode() and bnetDisplay and bnetDisplay ~= "" then
                bnetDisplay = Compat.MaskStreamerBNetName(bnetDisplay)
            end
            if bnetDisplay and bnetDisplay ~= "" and bnetDisplay ~= titleName then
                GameTooltip:AddDoubleLine(L["Battle.net"], bnetDisplay, 0.50, 0.78, 0.98, 0.72, 0.88, 1.0)
            end
            local fac = (item.faction and item.faction ~= "" and item.faction) or (bnetInfo and bnetInfo.faction)
            local sameFac = (item.sameFaction ~= false) and not (bnetInfo and bnetInfo.sameFaction == false)
            if fac and not sameFac then
                local facLoc = (fac == "Alliance") and L["Alliance"] or L["Horde"]
                local rC, gC, bC = (fac == "Alliance") and 0.30 or 1.0, (fac == "Alliance") and 0.62 or 0.30, (fac == "Alliance") and 1.0 or 0.30
                GameTooltip:AddDoubleLine(L["Faction"], facLoc, 0.72, 0.78, 0.86, rC, gC, bC)
            end
            if tab == "watchlist" and bnetInfo then
                if bnetInfo.activeDisplayName and bnetInfo.activeLookupKey ~= rowKey then
                    GameTooltip:AddDoubleLine(L["Online"], bnetInfo.activeDisplayName, 0.28, 0.92, 0.52, 1.0, 0.85, 0.35)
                end
                if bnetInfo.otherChars and #bnetInfo.otherChars > 0 then
                    GameTooltip:AddDoubleLine(L["Alts"], table.concat(bnetInfo.otherChars, ", "), 0.68, 0.78, 0.90, 0.85, 0.92, 1.0)
                end
            end
            if tab == "social" then
                if not item.online then
                    local offStr = item.lastSeen and (L["Offline"] .. " (" .. Compat.FormatRelativeTime(item.lastSeen, L) .. ")") or L["Offline"]
                    GameTooltip:AddLine(offStr, 0.62, 0.66, 0.72)
                elseif item.bnetState == "bnet_app" or item.bnetState == "wow_other" then
                    local statusLbl = item.richPresence or item.clientProgram or L["Battle.net"]
                    GameTooltip:AddLine(statusLbl, 0.44, 0.72, 0.96, true)
                elseif item.dnd then
                    GameTooltip:AddLine(L["Busy"] .. " [DND]", 0.94, 0.40, 0.40)
                elseif item.afk then
                    GameTooltip:AddLine("[AFK]", 0.96, 0.76, 0.22)
                end
                if item.customMessage and item.customMessage ~= "" then
                    GameTooltip:AddLine("\"" .. item.customMessage .. "\"", 0.72, 0.80, 0.92, true)
                end
            end
            if item.area and item.area ~= "" and item.area ~= item.richPresence then
                GameTooltip:AddLine(item.area, 0.78, 0.84, 0.92)
            end
            if item.guild and item.guild ~= "" then
                GameTooltip:AddLine("<" .. item.guild .. ">", 0.35, 0.88, 0.50)
            end
            if tab == "social" and item.lookupKey and ns.Store then
                local meta = (ns.Store.GetResolvedSocialMeta and ns.Store:GetResolvedSocialMeta(item.lookupKey))
                    or (ns.Store.GetSocialMeta and ns.Store:GetSocialMeta(item.lookupKey))
                if meta and meta.mainName and meta.mainName ~= "" then
                    GameTooltip:AddDoubleLine(L["Main"], meta.mainName, 0.68, 0.78, 0.90, 0.85, 0.92, 1.0)
                end
                local alts = ns.Store.GetLinkedAltsForCharacter and ns.Store:GetLinkedAltsForCharacter(item.lookupKey)
                if alts and #alts > 0 then
                    GameTooltip:AddDoubleLine(L["Linked Alts"], table.concat(alts, ", "), 0.68, 0.78, 0.90, 0.78, 0.86, 0.96)
                end
                if meta and meta.note and meta.note ~= "" then
                    GameTooltip:AddLine(L["Social Note:"] .. " " .. meta.note, 0.95, 0.85, 0.45, true)
                end
                if item.friendNote and item.friendNote ~= "" then
                    GameTooltip:AddLine(L["Friend Note"] .. ": " .. item.friendNote, 0.58, 0.82, 0.98, true)
                end
                if item.bnetNote and item.bnetNote ~= "" then
                    GameTooltip:AddLine(L["Battle.net Note"] .. ": " .. item.bnetNote, 0.50, 0.78, 0.98, true)
                end
                if item.guildNote and item.guildNote ~= "" then
                    GameTooltip:AddLine(L["Guild Note"] .. ": " .. item.guildNote, 0.45, 0.88, 0.58, true)
                end
                local comp = ns.Store.GetRecentCompanion and ns.Store:GetRecentCompanion(item.lookupKey)
                if comp then
                    local runsTxt = (comp.runs and comp.runs > 1) and (" (" .. tostring(comp.runs) .. "x)") or ""
                    GameTooltip:AddLine(L["Recent companion: %s (%s)"]:format((comp.zone and comp.zone ~= "") and comp.zone or L["Group"], Compat.FormatRelativeTime(comp.lastSeen, L)) .. runsTxt, 0.62, 0.85, 0.96, true)
                end
            elseif item.note and item.note ~= "" then
                GameTooltip:AddLine(item.note, 0.95, 0.85, 0.45, true)
            end
            if tab == "alts" then
                local curAltKey = (Store and Store.GetCurrentAltKey and Store:GetCurrentAltKey()) or Compat.CharacterKey()
                if item.key == curAltKey then
                    GameTooltip:AddLine(L["Current Character"] .. " — " .. L["Active on this WoW Forever account."], 0.39, 0.89, 0.60, true)
                else
                    GameTooltip:AddLine(L["Alt"] .. " — " .. L["Saved character on this WoW Forever account."], 0.62, 0.66, 0.71, true)
                end
            end
            if item.truncatedWarning then
                GameTooltip:AddLine(L["50+ matches found for '%s'; add surname for accuracy."]:format(item.displayName or item.firstName or ""), 1, 0.45, 0.25, true)
            end
            if tab == "social" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Click: Quick Inspect  |  Right-click: Actions Menu"], 0.45, 0.85, 1.0)
            end
            if _G.FriendsTooltip and _G.FriendsTooltip.IsShown and _G.FriendsTooltip:IsShown() and _G.FriendsTooltip.Hide then
                pcall(_G.FriendsTooltip.Hide, _G.FriendsTooltip)
            end
            GameTooltip:Show()
        end
    end)

    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if (self.btnWhisper and self.btnWhisper:IsShown() and self.btnWhisper:IsMouseOver())
            or (self.btnInvite and self.btnInvite:IsShown() and self.btnInvite:IsMouseOver())
        then
            return
        end
        if self._syncHover then self:_syncHover(false) end
        local p = Theme:GetPalette()
        if self._item and (self._item._isSocialDetailRow or (self._isExpandedSocial == true)) then
            Theme:ApplyBackdrop(self, "surface", p)
            return
        end
        Theme:ApplyBackdrop(self, (self._dataIdx and self._dataIdx % 2 == 1) and "row" or "rowAlt", p)
    end)

    function row:RefreshTheme()
        Theme:StyleButton(self.btnRemove, "danger")
        Theme:StyleButton(self.btnInvite, "default")
        Theme:StyleButton(self.btnWhisper, "default")
        Theme:StyleButton(self.btnAction, self._actionVariant or "primary")
        if self.detailBox then
            Theme:StyleButton(self.detailBox.btnBell, "default")
            Theme:StyleButton(self.detailBox.btnMeta, "default")
            Theme:StyleButton(self.detailBox.btnWatch, "default")
            Theme:StyleButton(self.detailBox.btnMore, "default")
        end
    end

    return row
end

local sublinePartsScratch = {}
local sublineTagsScratch = {}

local function FormatWatchlistSubline(item)
    local parts = sublinePartsScratch
    wipe(parts)
    if item.isSessionBNet then
        parts[#parts + 1] = "Battle.net"
        if item.richPresence and item.richPresence ~= "" then
            parts[#parts + 1] = item.richPresence
        elseif item.online then
            parts[#parts + 1] = L["Online"]
        else
            parts[#parts + 1] = L["Offline"]
        end
        parts[#parts + 1] = L["Session (auto-saves on WoW login)"]
        return table.concat(parts, "  ·  ")
    end
    local lfgInfo = (ns.Clan and ns.Clan.GetActiveLfgForPlayer) and ns.Clan:GetActiveLfgForPlayer(item.activeAltLookup or item.lookupKey or item.id) or nil
    if lfgInfo then
        parts[#parts + 1] = "|cff3fb950[" .. tostring(lfgInfo.mode or "LFG") .. ": " .. tostring(lfgInfo.activity or L["Group"]) .. "]|r"
    end
    if item.status == "online" then
        parts[#parts + 1] = L["Online"]
    elseif item.status == "offline" then
        parts[#parts + 1] = L["Offline"]
    else
        parts[#parts + 1] = L["Unchecked"]
    end

    if item.activeAltName and item.displayName and item.activeAltName ~= item.displayName then
        parts[#parts + 1] = "|cff70b5f9" .. L["Account: %s"]:format(item.displayName) .. "|r"
    end
    if item.area and item.area ~= "" then
        parts[#parts + 1] = item.area
    end
    if item.guild and item.guild ~= "" then
        parts[#parts + 1] = "<" .. item.guild .. ">"
    end
    if item.note and item.note ~= "" then
        parts[#parts + 1] = item.note
    end
    if (not item.surname or item.surname == "") and type(item.observedCandidate) == "string" and item.observedCandidate ~= "" then
        parts[#parts + 1] = "|cffffd24d" .. L["Confirm: %s"]:format(item.observedCandidate) .. "|r"
    end
    if item.status ~= "online" and item.id and ns.Social and ns.Social.GetBNetLinkInfo then
        local bnetInfo = ns.Social:GetBNetLinkInfo(item.id)
        if bnetInfo and bnetInfo.activeDisplayName and bnetInfo.activeLookupKey ~= item.id then
            parts[#parts + 1] = "|cff00b4ff" .. L["Online"] .. ": " .. bnetInfo.activeDisplayName .. "|r"
        end
    end
    local stamp = item.lastSeen or item.lastChecked
    if stamp then
        parts[#parts + 1] = Compat.FormatRelativeTime(stamp, L)
    end
    return table.concat(parts, "  ·  ")
end

local function FormatSocialSubline(item)
    local parts = sublinePartsScratch
    wipe(parts)
    local lfgInfo = (ns.Clan and ns.Clan.GetActiveLfgForPlayer) and ns.Clan:GetActiveLfgForPlayer(item.lookupKey or item.id) or nil
    if lfgInfo then
        parts[#parts + 1] = "|cff3fb950[" .. tostring(lfgInfo.mode or "LFG") .. ": " .. tostring(lfgInfo.activity or L["Group"]) .. "]|r"
    end
    local meta = (item.lookupKey and ns.Store)
        and ((ns.Store.GetResolvedSocialMeta and ns.Store:GetResolvedSocialMeta(item.lookupKey)) or (ns.Store.GetSocialMeta and ns.Store:GetSocialMeta(item.lookupKey)))
        or nil
    if not item.online then
        local seenStr = item.lastSeen and (L["Offline"] .. " · " .. Compat.FormatRelativeTime(item.lastSeen, L)) or L["Offline"]
        parts[#parts + 1] = seenStr
    elseif item.bnetState == "bnet_app" or item.bnetState == "wow_other" then
        local appInfo = item.richPresence or item.clientProgram or item.area
        if appInfo and appInfo ~= "" then
            parts[#parts + 1] = appInfo
        end
    elseif item.area and item.area ~= "" then
        parts[#parts + 1] = item.area
    end
    if item.guild and item.guild ~= "" then
        parts[#parts + 1] = "<" .. item.guild .. ">"
    end
    if meta and meta.folder and meta.folder ~= "" then
        parts[#parts + 1] = "|cffd8b467" .. meta.folder .. "|r"
    end
    local comp = (item.lookupKey and ns.Store and ns.Store.GetRecentCompanion) and ns.Store:GetRecentCompanion(item.lookupKey) or nil
    if comp then
        local runsSuffix = (comp.runs and comp.runs > 1) and (" " .. tostring(comp.runs) .. "x") or ""
        parts[#parts + 1] = "[" .. L["Group"] .. runsSuffix .. "]"
    end
    if #parts == 0 and item.bnetName and item.bnetName ~= item.displayName then
        parts[#parts + 1] = item.bnetName
    end
    return table.concat(parts, "  ·  ")
end

function UI._EnsureSocialDetailBox(row)
    if row.detailBox then
        return row.detailBox
    end
    local box = CreateFrame("Frame", nil, row)
    box:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -2)
    box:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 2)
    box:Hide()

    local noteText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    noteText:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
    noteText:SetPoint("TOPRIGHT", box, "TOPRIGHT", -2, -2)
    noteText:SetJustifyH("LEFT")
    noteText:SetWordWrap(false)
    box.noteText = noteText

    local btnMore = Theme:CreateButton(box, 24, 20, "", "default")
    btnMore:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 1)
    Theme:ConfigureIconButton(btnMore, 24, 20, "Interface\\Buttons\\UI-OptionsButton", {
        size = 14,
        color = { 0.92, 0.85, 0.72 },
        title = L["Actions"],
        desc = L["Open player menu (Favorite, Whisper, Invite, Folder, Watchlist, Ignore)."],
    })
    btnMore:SetScript("OnClick", function(selfBtn)
        local pItem = box._parentItem
        if pItem then
            OpenRowMenu(selfBtn, pItem)
        end
    end)
    box.btnMore = btnMore

    local btnWatch = Theme:CreateButton(box, 24, 20, "", "default")
    btnWatch:SetPoint("RIGHT", btnMore, "LEFT", -4, 0)
    Theme:ConfigureIconButton(btnWatch, 24, 20, "Interface\\Icons\\INV_Misc_Spyglass_03", {
        size = 14,
        title = "+ " .. L["Watchlist"],
        desc = L["Track login alerts, zone updates, and status via safe /who."],
    })
    btnWatch:SetScript("OnClick", function()
        local pItem = box._parentItem
        if not (pItem and ns.Watchlist) then return end
        local key = pItem.lookupKey or pItem.displayName
        if ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(key) then
            return
        end
        ns.Watchlist:Add(pItem.displayName or key)
        UI:Refresh(false)
    end)
    box.btnWatch = btnWatch

    local btnMeta = Theme:CreateButton(box, 24, 20, "", "default")
    btnMeta:SetPoint("RIGHT", btnWatch, "LEFT", -4, 0)
    Theme:ConfigureIconButton(btnMeta, 24, 20, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", {
        size = 14,
        color = { 1.0, 0.85, 0.35 },
        title = L["Folder / Note"],
        desc = L["Open Social Card, folders, alts, and friend notes."],
    })
    btnMeta:SetScript("OnClick", function()
        local pItem = box._parentItem
        if pItem and ns.SocialPanels and ns.SocialPanels.OpenSocialMetaModal then
            ns.SocialPanels:OpenSocialMetaModal(pItem.displayName or pItem.bnetName, pItem.lookupKey or pItem.displayName, pItem)
        end
    end)
    box.btnMeta = btnMeta

    local btnBell = Theme:CreateButton(box, 24, 20, "", "default")
    btnBell:SetPoint("RIGHT", btnMeta, "LEFT", -4, 0)
    Theme:ConfigureIconButton(btnBell, 24, 20, BELL_ON_TEX, {
        size = 14,
        title = L["Alerts"],
    })
    btnBell:SetScript("OnClick", function()
        local pItem = box._parentItem
        if pItem then
            ToggleRowNotifyBell("social", pItem)
        end
    end)
    box.btnBell = btnBell

    local srcText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    srcText:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 2, 4)
    srcText:SetPoint("RIGHT", btnBell, "LEFT", -6, 0)
    srcText:SetJustifyH("LEFT")
    srcText:SetWordWrap(false)
    box.srcText = srcText

    row.detailBox = box
    return box
end

function UI._RenderSocialDetailRow(row, item, palette)
    local pItem = item.parentItem
    local box = UI._EnsureSocialDetailBox(row)
    box._parentItem = pItem
    row._isExpandedSocial = false
    row._lastLeftAnchor = "__detail"
    row._lastRightReserve = nil
    row._lastHoverRightReserve = nil
    row._prevTextLeftX = nil

    if row.btnNotifyBell then row.btnNotifyBell:Hide() end
    if row.metaRight then row.metaRight:SetText(""); row.metaRight:Hide() end
    if row.classIcon then row.classIcon:Hide() end
    if row.dot then row.dot:Hide() end
    if row.nameText then row.nameText:SetText(""); row.nameText:Hide() end
    if row.subText then row.subText:SetText(""); row.subText:Hide() end
    if row.statusBar then
        row.statusBar:SetColorTexture(0.90, 0.74, 0.36, 0.90)
        row.statusBar:SetAlpha(1.0)
    end
    Theme:ApplyBackdrop(row, "surface", palette)

    if not pItem then
        box:Hide()
        return
    end

    local meta = (pItem.lookupKey and ns.Store)
        and ((ns.Store.GetResolvedSocialMeta and ns.Store:GetResolvedSocialMeta(pItem.lookupKey)) or (ns.Store.GetSocialMeta and ns.Store:GetSocialMeta(pItem.lookupKey)))
        or nil
    local noteStr = (meta and meta.note and meta.note ~= "") and meta.note
        or pItem.friendNote or pItem.bnetNote or pItem.guildNote or pItem.note
    if noteStr and noteStr ~= "" then
        box.noteText:SetText("|cffffd24d" .. L["Note"] .. ":|r " .. noteStr)
    else
        box.noteText:SetText("|cff8b949e" .. L["No personal note."] .. "|r")
    end

    local srcParts = sublineTagsScratch
    wipe(srcParts)
    if pItem.bnetName and pItem.bnetName ~= "" then
        local bnDisp = (Compat and Compat.IsStreamerMode and Compat.IsStreamerMode())
            and Compat.MaskStreamerBNetName(pItem.bnetName)
            or pItem.bnetName
        srcParts[#srcParts + 1] = "|cff70b5f9" .. bnDisp .. "|r"
    elseif pItem.sources and pItem.sources.friend then
        srcParts[#srcParts + 1] = L["Friends"]
    end
    if pItem.guild and pItem.guild ~= "" then
        srcParts[#srcParts + 1] = "|cff4ee07a<" .. pItem.guild .. ">|r"
    end
    if meta and meta.mainName and meta.mainName ~= "" then
        srcParts[#srcParts + 1] = L["Main"] .. ": " .. meta.mainName
    end
    box.srcText:SetText(table.concat(srcParts, " · "))

    local showBell, bellActive, bellTip = GetRowNotifyBellState("social", pItem)
    box.btnBell:SetShown(showBell == true)
    if showBell then
        Theme:ConfigureIconButton(box.btnBell, 24, 20, bellActive and BELL_ON_TEX or BELL_OFF_TEX, {
            size = 14,
            title = bellActive and L["Login Alerts Active"] or L["Login Alerts Muted"],
            desc = bellTip,
        })
        Theme:SetButtonActive(box.btnBell, bellActive == true, "default")
    end

    Theme:ConfigureIconButton(box.btnMeta, 24, 20, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", {
        size = 14,
        color = { 1.0, 0.85, 0.35 },
        title = L["Folder / Note"],
        desc = L["Open Social Card, folders, alts, and friend notes."],
    })

    local watchKey = pItem.lookupKey or pItem.displayName
    local canWatch = pItem.hasCharacterName ~= false and watchKey ~= nil and watchKey ~= ""
    local isWatched = canWatch and ns.Watchlist and ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(watchKey)
    box.btnWatch:SetShown(canWatch and ns.Watchlist ~= nil)
    if box.btnWatch:IsShown() then
        box.btnWatch:SetEnabled(not isWatched)
        Theme:ConfigureIconButton(
            box.btnWatch,
            24,
            20,
            isWatched and "Interface\\RAIDFRAME\\ReadyCheck-Ready" or "Interface\\Icons\\INV_Misc_Spyglass_03",
            {
                size = 14,
                disabled = isWatched == true,
                title = isWatched and L["Watched"] or ("+ " .. L["Watchlist"]),
                desc = isWatched and L["Already monitored on your Watchlist."] or L["Track login alerts, zone updates, and status via safe /who."],
            }
        )
        Theme:SetButtonActive(box.btnWatch, isWatched == true, "default")
    end

    box.btnMore:ClearAllPoints()
    box.btnMore:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 1)
    local prevBtn = box.btnMore
    if box.btnWatch:IsShown() then
        box.btnWatch:ClearAllPoints()
        box.btnWatch:SetPoint("RIGHT", prevBtn, "LEFT", -4, 0)
        prevBtn = box.btnWatch
    end
    box.btnMeta:ClearAllPoints()
    box.btnMeta:SetPoint("RIGHT", prevBtn, "LEFT", -4, 0)
    prevBtn = box.btnMeta
    if box.btnBell:IsShown() then
        box.btnBell:ClearAllPoints()
        box.btnBell:SetPoint("RIGHT", prevBtn, "LEFT", -4, 0)
        prevBtn = box.btnBell
    end
    box.srcText:ClearAllPoints()
    box.srcText:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 2, 4)
    box.srcText:SetPoint("RIGHT", prevBtn, "LEFT", -6, 0)
    box:Show()
end

local function SyncRowActionStyle(row, btn, fullLabel, isIconMode, minWhispW, minInvW, btnPad, maxRowBtnW)
    if not btn then return end
    btn._scCompactIcon = isIconMode == true
    if isIconMode then
        btn._scAutoFit = false
        btn:SetSize(24, 22)
        Theme:SetButtonText(btn, "")
        if btn.ico then btn.ico:Show() end
    else
        if btn.ico then btn.ico:Hide() end
        Theme:SetButtonText(btn, fullLabel)
        Theme:AutoFitButton(btn, (btn == row.btnWhisper) and minWhispW or minInvW, btnPad, maxRowBtnW)
    end
end

local function ApplyWhisperButtonPreference(row, btn, isScConfirmed, isCompact, minWhispW, minInvW, btnPad, maxRowBtnW)
    if not btn then return end
    btn._hasSocialCentral = isScConfirmed == true
    if btn.ico then
        if isScConfirmed then
            btn.ico:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\icon.tga")
            btn.ico:SetTexCoord(0, 1, 0, 1)
        else
            btn.ico:SetTexture("Interface\\Icons\\INV_Letter_15")
            btn.ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    Theme:StyleButton(btn, isScConfirmed and "primary" or "default")
    SyncRowActionStyle(row, btn, isScConfirmed and L["Chat"] or L["Whisper"], isCompact, minWhispW, minInvW, btnPad, maxRowBtnW)
end

local function UpdateListRow(row, item, idx, palette)
    row._item = item
    row._dataIdx = idx
    row.subText:SetTextColor(palette.textMuted[1], palette.textMuted[2], palette.textMuted[3])

    local tab = item._tab or activeTab

    row.btnRemove:Hide()
    row.btnInvite:Hide()
    row.btnWhisper:Hide()
    row.btnAction:Hide()
    Theme:ClearButtonIcon(row.btnAction)

    row._hasHoverWhisper = false
    row._hasHoverInvite = false
    row._alwaysShowWhisper = false
    row._alwaysShowInvite = false
    row._hasMetaRight = false
    row._baseRightAnchor = nil
    row._activeRightTarget = nil
    row._isExpandedSocial = false
    if row.detailBox then
        row.detailBox:Hide()
    end
    if row.nameText then
        row.nameText:Show()
    end

    if item._isSocialDetailRow then
        return UI._RenderSocialDetailRow(row, item, palette)
    end

    if item._isSocialFolderHeader then
        if row.btnNotifyBell then row.btnNotifyBell:Hide() end
        if row.metaRight then row.metaRight:SetText(""); row.metaRight:Hide() end
        row._lastCompactMode = nil
        if row.classIcon then
            row.classIcon:SetDesaturated(false)
            row.classIcon:SetAlpha(1.0)
            row.classIcon:Hide()
        end
        if row.dot then row.dot:Hide() end
        if row.statusBar then
            if item.folderKey == "__fav" then
                row.statusBar:SetColorTexture(1.0, 0.78, 0.24, 0.95)
            elseif item.folderKey == "__guild" then
                row.statusBar:SetColorTexture(0.25, 0.82, 0.45, 0.92)
            elseif item.folderKey == "__offline" then
                row.statusBar:SetColorTexture(0.45, 0.50, 0.58, 0.70)
            else
                row.statusBar:SetColorTexture(0.32, 0.74, 0.98, 0.92)
            end
            row.statusBar:SetAlpha(1.0)
        end
        if row._lastLeftAnchor ~= "__folder" then
            row._lastLeftAnchor = "__folder"
            row._lastBellShown = false
            row._lastClassIconShown = false
            row._lastRightReserve = nil
            row._lastHoverRightReserve = nil
            row._prevTextLeftX = nil
            row.nameText:ClearAllPoints()
            row.nameText:SetPoint("LEFT", row, "LEFT", 14, 0)
            row.nameText:SetPoint("RIGHT", row, "RIGHT", -12, 0)
            row.subText:ClearAllPoints()
            row.subText:SetPoint("BOTTOMLEFT", 14, 4)
            row.subText:SetPoint("RIGHT", row, "RIGHT", -12, 0)
        end
        local arrow = item.isCollapsed and "|cffffd24d[+]|r " or "|cffffd24d[-]|r "
        local cntStr
        if item.folderKey == "__offline" or item.folderKey == "__online" then
            cntStr = string.format(" |cff9da7b5(%d)|r", item.totalCount or 0)
        else
            cntStr = string.format(" |cff9da7b5(%d/%d)|r", item.onlineCount or 0, item.totalCount or 0)
        end
        row.nameText:SetAlpha(1.0)
        row.nameText:SetText(arrow .. (item.folderLabel or "") .. cntStr)
        row.subText:SetAlpha(1.0)
        row.subText:SetText("")
        row.subText:Hide()
        return
    end

    local isCompactRows = (ns.db and ns.db.settings and ns.db.settings.compactListRows == true)
    local metaRightText = ""
    local persistentActionBtn = nil

    if row.dot then row.dot:Show() end
    local effClass = (tab == "watchlist" and item.activeAltClass) or item.classFile
    local effLevel = (tab == "watchlist" and item.activeAltLevel) or item.level
    local hex = effClass and Compat.ClassHex(effClass) or ((palette.key == "blizzard" and item.status ~= "offline") and "|cffffd100" or Compat.ClassHex(nil))
    local levelStr = effLevel and effLevel > 0 and (" |cff9da7b5" .. L["Lv %d"]:format(effLevel) .. "|r") or ""

    local showBell, bellActive = GetRowNotifyBellState(tab, item)
    if showBell and row.btnNotifyBell then
        row.btnNotifyBell.tex:SetTexture(bellActive and BELL_ON_TEX or BELL_OFF_TEX)
        row.btnNotifyBell:Show()
    elseif row.btnNotifyBell then
        row.btnNotifyBell:Hide()
    end

    local isRowOffline = (tab == "watchlist" and item.status == "offline") or (tab == "social" and item.online ~= true)
    local classCoords = effClass and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[effClass]
    local showClassIcon = classCoords ~= nil
    local isSocialAvatar = (tab == "social") and (not isCompactRows) and showClassIcon
    if row.btnNotifyBell then
        row.btnNotifyBell:ClearAllPoints()
        row.btnNotifyBell:SetPoint("LEFT", row, "LEFT", isSocialAvatar and 9 or 21, 0)
    end
    if row.classIcon then
        if showClassIcon then
            row.classIcon:SetTexCoord(classCoords[1] + 0.02, classCoords[2] - 0.02, classCoords[3] + 0.02, classCoords[4] - 0.02)
            row.classIcon:SetDesaturated(isRowOffline)
            row.classIcon:SetAlpha(isRowOffline and 0.48 or 1.0)
            row.classIcon:SetSize(isSocialAvatar and 24 or 20, isSocialAvatar and 24 or 20)
            row.classIcon:ClearAllPoints()
            if isSocialAvatar then
                row.classIcon:SetPoint("LEFT", row, "LEFT", showBell and 29 or 10, 0)
            else
                row.classIcon:SetPoint("LEFT", row, "LEFT", showBell and 40 or 23, 0)
            end
            row.classIcon:Show()
        else
            row.classIcon:SetSize(20, 20)
            row.classIcon:SetDesaturated(false)
            row.classIcon:SetAlpha(1.0)
            row.classIcon:Hide()
        end
    end
    if row.dot then
        row.dot:ClearAllPoints()
        if isSocialAvatar and row.classIcon then
            row.dot:SetDrawLayer("OVERLAY", 3)
            row.dot:SetSize(9, 9)
            row.dot:SetPoint("LEFT", row, "LEFT", (showBell and 29 or 10) + 17, -9)
        else
            row.dot:SetDrawLayer("ARTWORK", 2)
            row.dot:SetSize(8, 8)
            row.dot:SetPoint("LEFT", row, "LEFT", 9, 0)
        end
    end
    row.nameText:SetAlpha(isRowOffline and 0.66 or 1.0)
    row.subText:SetAlpha(isRowOffline and 0.60 or 0.94)

    if row.SetClipsChildren then
        row:SetClipsChildren(true)
    end
    local rowW = row:GetWidth() or (frame and frame:GetWidth()) or 760
    local compactRow = rowW > 0 and rowW < 520
    local btnPad = compactRow and 12 or 20
    local btnGap = compactRow and -4 or -6
    local minInvW = compactRow and 24 or 72
    local minWhispW = compactRow and 24 or 80
    local minActW = compactRow and 56 or 72
    local minWatchAddW = compactRow and 74 or 90
    local maxRowBtnW = compactRow and 106 or 155

    local leftMostAnchor
    local itemKey = item.lookupKey or item.id
    local scBadge = (itemKey and ns.Chat and ((ns.Chat.GetLookupKeyAddonBadge and ns.Chat:GetLookupKeyAddonBadge(itemKey)) or (ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(itemKey) and (" " .. (Compat.AddonIconMarkup and Compat.AddonIconMarkup(true, 13) or "|cff3fb950[SC]|r"))))) or ""
    local scConfirmed = (itemKey or item.bnetAccountID) and ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(itemKey or item.displayName, item.bnetAccountID)
    if tab == "watchlist" then
        Theme:ApplyStatusColor(row.dot, item.status or "unknown")
        if row.statusBar then
            Theme:ApplyStatusColor(row.statusBar, item.status or "unknown")
            row.statusBar:SetAlpha((item.status == "online") and 0.90 or ((item.status == "unknown") and 0.45 or 0.25))
        end
        local activeWlKey = item.activeAltLookup or item.id
        local activeWlName = item.activeAltName or item.displayName
        local bnetInfo = (activeWlKey and ns.Social and ns.Social.GetBNetLinkInfo) and ns.Social:GetBNetLinkInfo(activeWlKey) or nil
        if (not bnetInfo) and item.id and ns.Social and ns.Social.GetBNetLinkInfo then
            bnetInfo = ns.Social:GetBNetLinkInfo(item.id)
        end
        local bnetBadge = (item.isSessionBNet or (bnetInfo and bnetInfo.isBNet)) and (" " .. (Compat.BNetIconMarkup and Compat.BNetIconMarkup(14) or "|cff00b4ff[BNet]|r")) or ""
        local altsBadge = (item.watchAllAlts == true) and (" |cff70b5f9[" .. L["All Alts"] .. "]|r") or ""
        local isFav = (item.favorite == true) or (itemKey ~= nil and ns.Store and ns.Store.IsSocialFavorite and ns.Store:IsSocialFavorite(itemKey) == true)
        local star = isFav and (Compat.FavoriteStarMarkup and Compat.FavoriteStarMarkup(13) or "|cffffd24d* |r") or ""
        local grp = (type(item.group) == "string" and item.group ~= "") and (" |cff8ab4f8[" .. item.group .. "]|r") or ""
        local hasAmbig = (not item.isSessionBNet) and type(item.ambiguousChoices) == "table" and #item.ambiguousChoices > 1
        local hasObsCand = (not item.isSessionBNet) and (not hasAmbig) and (not item.surname or item.surname == "") and type(item.observedCandidate) == "string" and item.observedCandidate ~= ""
        local warn = hasAmbig and (" |cffff9b3d[?" .. tostring(#item.ambiguousChoices) .. "]|r")
            or (item.truncatedWarning and " |cffff9b3d[!50+]|r" or "")
        local fac = (bnetInfo and bnetInfo.faction)
            or (not item.isSessionBNet and Compat.ResolveCharacterFaction and Compat.ResolveCharacterFaction(activeWlName or item.displayName, item.guid, item.bnetAccountID))
            or (not item.isSessionBNet and ns.Chat and ns.Chat.GetKnownCharacterFaction and ns.Chat:GetKnownCharacterFaction(activeWlName or item.displayName, item.guid, item.bnetAccountID))
        local facIco = (Compat.FactionIconMarkup and Compat.FactionIconMarkup(fac, 12)) or ""
        local wMeta = (itemKey and not item.isSessionBNet and ns.Store) and ((ns.Store.GetResolvedSocialMeta and ns.Store:GetResolvedSocialMeta(itemKey)) or (ns.Store.GetSocialMeta and ns.Store:GetSocialMeta(itemKey))) or nil
        local wNick = (wMeta and wMeta.nickname and wMeta.nickname ~= "") and (" |cffffd24d(" .. wMeta.nickname .. ")|r") or ""
        local watchSub = FormatWatchlistSubline(item)
        local compactSuffix = (isCompactRows and watchSub ~= "") and ("  |cff9da7b5·  " .. watchSub .. "|r") or ""
        local altTitleSuffix = (item.activeAltName and item.displayName and item.activeAltName ~= item.displayName) and (" |cff9da7b5(" .. item.displayName .. ")|r") or ""
        row.nameText:SetText(star .. facIco .. hex .. (activeWlName or "") .. "|r" .. altTitleSuffix .. wNick .. levelStr .. compactSuffix)
        row.subText:SetText(watchSub)
        metaRightText = grp .. scBadge .. altsBadge .. bnetBadge .. warn

        row.btnRemove:Hide()
        row.btnAction:Hide()
        if item.status == "online" then
            local dirRow = (activeWlKey and ns.Store and ns.Store.socialDirectoryByLookup) and ns.Store.socialDirectoryByLookup[activeWlKey] or nil
            local isSelfWatch = (not item.isSessionBNet) and (Compat.IsMe and Compat.IsMe(activeWlName, item.guid)) == true
            local inGroupWatch = (not item.isSessionBNet) and (Compat.IsInMyGroup and Compat.IsInMyGroup(activeWlName, item.guid)) == true
            local canInviteWatch = (not item.isSessionBNet) and (not isSelfWatch) and (not inGroupWatch) and not ((dirRow and dirRow.sameFaction == false) or (bnetInfo and bnetInfo.sameFaction == false))
            ApplyWhisperButtonPreference(row, row.btnWhisper, scConfirmed, true, minWhispW, minInvW, btnPad, maxRowBtnW)
            row._hasHoverWhisper = true
            row.btnWhisper:ClearAllPoints()
            if canInviteWatch then
                SyncRowActionStyle(row, row.btnInvite, L["Invite"], true, minWhispW, minInvW, btnPad, maxRowBtnW)
                row._hasHoverInvite = true
                row.btnInvite:ClearAllPoints()
                row.btnInvite:SetPoint("RIGHT", compactRow and -5 or -8, 0)
                row.btnWhisper:SetPoint("RIGHT", row.btnInvite, "LEFT", btnGap, 0)
            else
                row.btnInvite:Hide()
                row.btnWhisper:SetPoint("RIGHT", compactRow and -5 or -8, 0)
            end
        else
            row.btnInvite:Hide()
            row.btnWhisper:Hide()
        end
        if hasAmbig or hasObsCand then
            row._actionVariant = "primary"
            Theme:StyleButton(row.btnAction, "primary")
            Theme:SetButtonText(row.btnAction, L["Choose"])
            Theme:SetButtonActive(row.btnAction, false, "primary")
            row.btnAction:SetEnabled(true)
            Theme:AutoFitButton(row.btnAction, compactRow and 62 or 76, btnPad, maxRowBtnW)
            row.btnAction:ClearAllPoints()
            row.btnAction:SetPoint("RIGHT", compactRow and -5 or -8, 0)
            row.btnAction:Show()
            row._hasHoverWhisper = false
            row._hasHoverInvite = false
            persistentActionBtn = row.btnAction
        elseif not item.isSessionBNet and (item.status == "unknown" or item.status == "offline") then
            row._actionVariant = "default"
            Theme:StyleButton(row.btnAction, "default")
            row.btnAction:SetEnabled(true)
            Theme:SetButtonActive(row.btnAction, false, "default")
            if compactRow then
                Theme:ConfigureIconButton(row.btnAction, 24, 22, "Interface\\Buttons\\UI-RefreshButton", {
                    size = 14,
                    title = L["Check"],
                    desc = L["Track login alerts, zone updates, and status via safe /who."],
                })
            else
                Theme:SetButtonText(row.btnAction, L["Check"])
                Theme:AutoFitButton(row.btnAction, 70, btnPad, maxRowBtnW)
            end
            row.btnAction:ClearAllPoints()
            row.btnAction:SetPoint("RIGHT", compactRow and -5 or -8, 0)
            row.btnAction:Show()
            persistentActionBtn = row.btnAction
        end
        leftMostAnchor = persistentActionBtn

    elseif tab == "social" then
        local dotState = "online"
        if not item.online then
            dotState = "offline"
        elseif item.dnd then
            dotState = "busy"
        elseif item.afk then
            dotState = "away"
        elseif item.bnetState == "bnet_app" or item.bnetState == "wow_other" then
            dotState = "app"
        end
        Theme:ApplyStatusColor(row.dot, dotState)
        if row.statusBar then
            Theme:ApplyStatusColor(row.statusBar, dotState)
            row.statusBar:SetAlpha(item.online and 0.90 or 0.22)
        end

        local meta = (item.lookupKey and ns.Store)
            and ((ns.Store.GetResolvedSocialMeta and ns.Store:GetResolvedSocialMeta(item.lookupKey)) or (ns.Store.GetSocialMeta and ns.Store:GetSocialMeta(item.lookupKey)))
            or nil
        local isFav = (item.lookupKey ~= nil and ns.Store and ns.Store.IsSocialFavorite and ns.Store:IsSocialFavorite(item.lookupKey)) == true
        local star = isFav and (Compat.FavoriteStarMarkup and Compat.FavoriteStarMarkup(13) or "|cffffd24d* |r") or ""
        local acctIgn = (item.isAccountIgnored and {
            reason = item.ignoreReason,
            note = item.ignoreNote,
            expiresAt = item.ignoreExpiresAt,
            hideChat = item.ignoreHideChat,
        }) or (item.lookupKey and ns.Store and ns.Store.GetAccountIgnore and ns.Store:GetAccountIgnore(item.lookupKey)) or nil
        local flagBadge = ""
        if acctIgn then
            flagBadge = " " .. (Compat.StatusIconMarkup and Compat.StatusIconMarkup("BLOCK", 13) or ("|cffff4d4d[" .. L["Blocked"] .. "]|r"))
        elseif meta and meta.flag == "GOOD" then
            flagBadge = " " .. (Compat.StatusIconMarkup and Compat.StatusIconMarkup("GOOD", 13) or "|cff3fb950[+]|r")
        elseif meta and meta.flag == "AVOID" then
            flagBadge = " " .. (Compat.StatusIconMarkup and Compat.StatusIconMarkup("AVOID", 13) or "|cffff4d4d[!]|r")
        end

        local flags = ""
        if item.online then
            if item.bnetState == "bnet_app" or item.bnetState == "wow_other" then
                flags = flags .. " " .. (Compat.BNetIconMarkup and Compat.BNetIconMarkup(13) or ("|cff70b5f9[" .. (item.clientProgram or "BNet") .. "]|r"))
            elseif item.sources and item.sources.bnet == true then
                flags = flags .. " " .. (Compat.BNetIconMarkup and Compat.BNetIconMarkup(13) or "|cff00b4ff[BNet]|r")
            end
            if item.afk then flags = flags .. " " .. (Compat.StatusIconMarkup and Compat.StatusIconMarkup("AFK", 13) or "|cffffd24d[AFK]|r") end
            if item.dnd then flags = flags .. " " .. (Compat.StatusIconMarkup and Compat.StatusIconMarkup("DND", 13) or "|cffff6b6b[DND]|r") end
        end

        local fac = item.faction
            or (Compat.ResolveCharacterFaction and Compat.ResolveCharacterFaction(item.lookupKey or item.displayName, item.guid, item.bnetAccountID))
            or (ns.Chat and ns.Chat.GetKnownCharacterFaction and ns.Chat:GetKnownCharacterFaction(item.lookupKey or item.displayName, item.guid, item.bnetAccountID))
        local facIco = (Compat.FactionIconMarkup and Compat.FactionIconMarkup(fac, 12)) or ""
        local nameColor = item.online and hex or "|cff8b949e"
        local displayTitle = item.displayName or item.bnetName or ""
        local sNick = (meta and meta.nickname and meta.nickname ~= "") and (" |cffffd24d(" .. meta.nickname .. ")|r") or ""
        local socialSub
        if item.isAccountIgnored and acctIgn then
            local remStr = (ns.Store and ns.Store.FormatIgnoreRemaining) and ns.Store:FormatIgnoreRemaining(acctIgn.expiresAt, L) or L["Permanent"]
            local chatTag = (acctIgn.hideChat ~= false) and L["Chat hidden"] or L["Chat visible"]
            local notePart = (acctIgn.note and acctIgn.note ~= "") and (" · " .. acctIgn.note) or ""
            socialSub = remStr .. " · " .. chatTag .. notePart
        else
            socialSub = FormatSocialSubline(item)
        end
        local eKey = UI._GetSocialItemExpandKey(item)
        local isExpandedSoc = (UI._expandedSocialKey and eKey and UI._expandedSocialKey == eKey) and true or false
        local expandChev = isExpandedSoc and "|cffffd24dv |r" or "|cff6e7681> |r"
        local compactSuffix = (isCompactRows and socialSub ~= "") and ("  |cff9da7b5·  " .. socialSub .. "|r") or ""
        row.nameText:SetText(expandChev .. star .. facIco .. nameColor .. displayTitle .. "|r" .. sNick .. levelStr .. compactSuffix)
        row.subText:SetText(socialSub)
        metaRightText = flagBadge .. flags .. scBadge

        if isExpandedSoc then
            row._isExpandedSocial = true
            Theme:ApplyBackdrop(row, "surface", palette)
            if row.statusBar then
                row.statusBar:SetColorTexture(0.90, 0.74, 0.36, 0.95)
                row.statusBar:SetAlpha(1.0)
            end
        end

        row.btnAction:Hide()
        local dirRow = (item.lookupKey and ns.Store and ns.Store.socialDirectoryByLookup) and ns.Store.socialDirectoryByLookup[item.lookupKey] or nil
        local bnetInfo = (item.lookupKey and ns.Social and ns.Social.GetBNetLinkInfo) and ns.Social:GetBNetLinkInfo(item.lookupKey) or nil
        local isCrossFacSoc = (item.sameFaction == false) or (dirRow and dirRow.sameFaction == false) or (bnetInfo and bnetInfo.sameFaction == false)
        local isSelfSoc = (item.isSelf == true) or (item.isMe == true) or (Compat.IsMe and Compat.IsMe(displayTitle, item.guid)) == true
        local inGroupSoc = (Compat.IsInMyGroup and Compat.IsInMyGroup(displayTitle, item.guid)) == true
        local canInviteNow = item.online == true
            and (not isSelfSoc)
            and (not inGroupSoc)
            and item.hasCharacterName ~= false
            and item.samePool ~= false
            and (not isCrossFacSoc)
            and (not item.bnetState or item.bnetState == "wow_forever" or (item.sources and (item.sources.friend or item.sources.guild)))
        local canWhisperNow = item.online == true and (not isSelfSoc)

        if canInviteNow then
            SyncRowActionStyle(row, row.btnInvite, L["Invite"], true, minWhispW, minInvW, btnPad, maxRowBtnW)
            ApplyWhisperButtonPreference(row, row.btnWhisper, scConfirmed, true, minWhispW, minInvW, btnPad, maxRowBtnW)
            row._alwaysShowInvite = true
            row._alwaysShowWhisper = true
            row.btnInvite:ClearAllPoints()
            row.btnInvite:SetPoint("RIGHT", compactRow and -5 or -8, 0)
            row.btnWhisper:ClearAllPoints()
            row.btnWhisper:SetPoint("RIGHT", row.btnInvite, "LEFT", -4, 0)
            row.btnInvite:Show()
            row.btnWhisper:Show()
            persistentActionBtn = row.btnWhisper
        elseif canWhisperNow then
            ApplyWhisperButtonPreference(row, row.btnWhisper, scConfirmed, true, minWhispW, minInvW, btnPad, maxRowBtnW)
            row._alwaysShowWhisper = true
            row.btnWhisper:ClearAllPoints()
            row.btnWhisper:SetPoint("RIGHT", compactRow and -5 or -8, 0)
            row.btnWhisper:Show()
            persistentActionBtn = row.btnWhisper
        end
        leftMostAnchor = persistentActionBtn

    elseif tab == "nearby" then
        Theme:ApplyStatusColor(row.dot, "nearby")
        if row.statusBar then
            Theme:ApplyStatusColor(row.statusBar, "nearby")
            row.statusBar:SetAlpha(0.90)
        end
        local isFav = (itemKey ~= nil and ns.Store and ns.Store.IsSocialFavorite and ns.Store:IsSocialFavorite(itemKey)) == true
        local star = isFav and (Compat.FavoriteStarMarkup and Compat.FavoriteStarMarkup(13) or "") or ""
        local fac = item.faction
            or (Compat.ResolveCharacterFaction and Compat.ResolveCharacterFaction(item.lookupKey or item.displayName, item.guid))
            or (ns.Chat and ns.Chat.GetKnownCharacterFaction and ns.Chat:GetKnownCharacterFaction(item.lookupKey or item.displayName, item.guid))
        local facIco = (Compat.FactionIconMarkup and Compat.FactionIconMarkup(fac, 12)) or ""
        local srcLower = type(item.source) == "string" and item.source:lower() or ""
        local srcIconKind = (srcLower == "group" or srcLower == "party" or srcLower == "raid") and "GROUP"
            or ((srcLower == "chat" or srcLower == "whisper" or srcLower == "guild") and "CHAT"
            or (srcLower == "target" and "GOOD" or "WATCH"))
        local srcTag = item.source and (" " .. (Compat.StatusIconMarkup and Compat.StatusIconMarkup(srcIconKind, 13) or ("|cff6ec1e4[" .. item.source .. "]|r"))) or ""
        local subParts = {}
        if item.guild and item.guild ~= "" then table.insert(subParts, "<" .. item.guild .. ">") end
        if item.area and item.area ~= "" then table.insert(subParts, item.area) end
        table.insert(subParts, L["Recent"] .. ": " .. Compat.FormatRelativeTime(item.lastSeen, L))
        local nearSub = table.concat(subParts, "  ·  ")
        local compactSuffix = (isCompactRows and nearSub ~= "") and ("  |cff9da7b5·  " .. nearSub .. "|r") or ""
        row.nameText:SetText(star .. facIco .. hex .. (item.displayName or "") .. "|r" .. levelStr .. compactSuffix)
        row.subText:SetText(nearSub)
        metaRightText = srcTag .. scBadge

        local isWatched = ns.Watchlist and ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(item.lookupKey or item.displayName)
        row.btnAction:Show()
        row.btnAction:ClearAllPoints()
        row.btnAction:SetPoint("RIGHT", compactRow and -5 or -8, 0)
        row._actionVariant = "default"
        Theme:StyleButton(row.btnAction, "default")
        if compactRow then
            row.btnAction:SetEnabled(not isWatched)
            Theme:SetButtonActive(row.btnAction, isWatched == true, "default")
            Theme:ConfigureIconButton(
                row.btnAction,
                24,
                22,
                isWatched and "Interface\\RAIDFRAME\\ReadyCheck-Ready" or "Interface\\Icons\\INV_Misc_Spyglass_03",
                {
                    size = 14,
                    disabled = isWatched == true,
                    title = isWatched and L["Watched"] or ("+ " .. L["Watchlist"]),
                    desc = isWatched and L["Already monitored on your Watchlist."] or L["Track login alerts, zone updates, and status via safe /who."],
                }
            )
        elseif isWatched then
            Theme:SetButtonText(row.btnAction, L["Watched"])
            Theme:SetButtonActive(row.btnAction, true, "default")
            row.btnAction:SetEnabled(false)
            Theme:AutoFitButton(row.btnAction, minWatchAddW, btnPad, maxRowBtnW)
        else
            Theme:SetButtonText(row.btnAction, "+ " .. L["Watchlist"])
            Theme:SetButtonActive(row.btnAction, false, "default")
            row.btnAction:SetEnabled(true)
            Theme:AutoFitButton(row.btnAction, minWatchAddW, btnPad, maxRowBtnW + 10)
        end
        persistentActionBtn = row.btnAction
        leftMostAnchor = row.btnAction

    elseif tab == "alts" then
        local curKey = (Store and Store.GetCurrentAltKey and Store:GetCurrentAltKey()) or Compat.CharacterKey()
        local isCurrent = (item.key == curKey)
        Theme:ApplyStatusColor(row.dot, isCurrent and "online" or "offline")
        if row.statusBar then
            Theme:ApplyStatusColor(row.statusBar, isCurrent and "online" or "offline")
            row.statusBar:SetAlpha(isCurrent and 0.92 or 0.28)
        end
        local fac = item.faction or (Compat.ResolveCharacterFaction and Compat.ResolveCharacterFaction(item.fullName or item.name or item.key))
        local facIco = (Compat.FactionIconMarkup and Compat.FactionIconMarkup(fac, 12)) or ""
        local shownName = item.fullName or item.name or ""
        local roleBadge = isCurrent and (" " .. (Compat.StatusIconMarkup and Compat.StatusIconMarkup("GOOD", 13) or ("|cff63e29a[" .. L["Current Character"] .. "]|r"))) or ""
        local parts = {}
        if item.zone and item.zone ~= "" then table.insert(parts, item.zone) end
        if item.guild and item.guild ~= "" then table.insert(parts, "<" .. item.guild .. ">") end
        table.insert(parts, Compat.FormatMoney(item.money))
        if item.itemLevel and item.itemLevel > 0 then
            table.insert(parts, "iLvl " .. item.itemLevel)
        end
        if (tonumber(item.level) or 0) < 60 and item.rested and item.rested > 0 then
            table.insert(parts, L["Rested"] .. ": " .. tostring(math.floor(item.rested)) .. " XP")
        end
        table.insert(parts, Compat.FormatRelativeTime(item.lastActive, L))
        local altSub = table.concat(parts, "  ·  ")
        local compactSuffix = (isCompactRows and altSub ~= "") and ("  |cff9da7b5·  " .. altSub .. "|r") or ""
        row.nameText:SetText(facIco .. hex .. shownName .. "|r" .. levelStr .. compactSuffix)
        row.subText:SetText(altSub)
        metaRightText = roleBadge

        row.btnAction:Hide()
        row.btnRemove:Hide()
        leftMostAnchor = nil
    end

    local cleanMeta = Compat.Trim and Compat.Trim(metaRightText) or metaRightText
    if row.metaRight then
        if cleanMeta and cleanMeta ~= "" then
            row._hasMetaRight = true
            row.metaRight:SetWidth(0)
            row.metaRight:SetText(cleanMeta)
            row.metaRight:SetWidth(math.min(185, math.max(12, math.ceil((row.metaRight:GetStringWidth() or 0) + 2))))
            row.metaRight:ClearAllPoints()
            if persistentActionBtn then
                row.metaRight:SetPoint("RIGHT", persistentActionBtn, "LEFT", -6, 0)
            else
                row.metaRight:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            end
        else
            row._hasMetaRight = false
            row.metaRight:SetText("")
            row.metaRight:Hide()
        end
    end

    row._lastEdgePad = compactRow and 5 or 8
    row._lastWhispGap = (tab == "social") and 4 or (compactRow and 4 or 6)
    local rightReservePx = UI._ComputeRowRightReserve(
        row,
        (row.btnAction and row.btnAction:IsShown()) == true,
        (row._alwaysShowInvite == true) and (row.btnInvite ~= nil),
        (row._alwaysShowWhisper == true) and (row.btnWhisper ~= nil),
        (row._hasMetaRight == true) and (row.metaRight ~= nil)
    )
    local bellKey = showBell == true
    local classKey = showClassIcon == true
    if row.subText then
        row.subText:SetShown(not isCompactRows)
    end
    local avatarKey = isSocialAvatar == true
    local textLeftX
    if avatarKey then
        textLeftX = bellKey and 61 or 42
    else
        textLeftX = 24 + (bellKey and 19 or 0) + (classKey and 25 or 0)
    end
    row._lastTextLeftX = textLeftX
    if row._lastLeftAnchor ~= "__row" or row._lastRightReserve ~= rightReservePx or row._lastHoverRightReserve ~= rightReservePx or row._prevTextLeftX ~= textLeftX or row._lastBellShown ~= bellKey or row._lastClassIconShown ~= classKey or row._lastCompactMode ~= isCompactRows or row._lastAvatarSocialMode ~= avatarKey then
        row._lastLeftAnchor = "__row"
        row._lastRightReserve = rightReservePx
        row._lastHoverRightReserve = rightReservePx
        row._prevTextLeftX = textLeftX
        row._lastBellShown = bellKey
        row._lastClassIconShown = classKey
        row._lastCompactMode = isCompactRows
        row._lastAvatarSocialMode = avatarKey
        UI._ApplyRowTextAnchors(row, textLeftX, rightReservePx, isCompactRows)
    end
    row._activeRightTarget = nil
    if row._syncHover then
        row:_syncHover(row:IsMouseOver() == true)
    end
end

function UI._BuildGroupedSectionRows(items, collapsedMap, isOnlineFn, classifyFn)
    local customOrder = {}
    local buckets = {}
    local function addToBucket(fKey, fLabel, it, isCustom)
        local b = buckets[fKey]
        if not b then
            b = { folderKey = fKey, folderLabel = fLabel, items = {}, onlineCount = 0, isCustom = isCustom }
            buckets[fKey] = b
            if isCustom then
                customOrder[#customOrder + 1] = b
            end
        end
        b.items[#b.items + 1] = it
        if isOnlineFn(it) then
            b.onlineCount = b.onlineCount + 1
        end
    end

    for _, it in ipairs(items) do
        local fKey, fLabel, isCustom = classifyFn(it)
        addToBucket(fKey, fLabel, it, isCustom)
    end

    table.sort(customOrder, function(a, b)
        return tostring(a.folderLabel or ""):lower() < tostring(b.folderLabel or ""):lower()
    end)

    local ordered = {}
    if buckets["__fav"] then ordered[#ordered + 1] = buckets["__fav"] end
    for i = 1, #customOrder do ordered[#ordered + 1] = customOrder[i] end
    if buckets["__online"] then ordered[#ordered + 1] = buckets["__online"] end
    if buckets["__guild"] then ordered[#ordered + 1] = buckets["__guild"] end
    if buckets["__offline"] then ordered[#ordered + 1] = buckets["__offline"] end

    local forceExpand = (searchQuery ~= nil and searchQuery ~= "")
        or (activeTab == "social" and socialFilter ~= "all")
    local grouped = {}
    for _, b in ipairs(ordered) do
        local isColl = (b.folderKey ~= "__fav") and (not forceExpand) and (collapsedMap[b.folderKey] ~= false)
        grouped[#grouped + 1] = {
            _isSocialFolderHeader = true,
            folderKey = b.folderKey,
            folderLabel = b.folderLabel,
            totalCount = #b.items,
            onlineCount = b.onlineCount,
            isCollapsed = isColl,
        }
        if not isColl then
            for ii = 1, #b.items do
                grouped[#grouped + 1] = b.items[ii]
            end
        end
    end
    return grouped
end

local function BuildFilteredRows()
    local out = {}
    if activeTab == "watchlist" and ns.Watchlist then
        local sortBy = ns.db and ns.db.settings and ns.db.settings.sortBy or "status"
        local showWatchOffline = not (ns.db and ns.db.settings and ns.db.settings.watchlistShowOffline == false)
        for _, entry in ipairs(ns.Watchlist:GetEntries(watchlistGroupFilter, sortBy)) do
            if showWatchOffline or entry.status ~= "offline" then
                local wKey = entry.id or entry.lookupKey
                local wMeta = (wKey and ns.Store)
                    and ((ns.Store.GetResolvedSocialMeta and ns.Store:GetResolvedSocialMeta(wKey)) or (ns.Store.GetSocialMeta and ns.Store:GetSocialMeta(wKey)))
                    or nil
                if SafeTextMatches(searchQuery, entry.displayName, entry.area, entry.guild, entry.note, entry.group, wMeta and wMeta.nickname) then
                    table.insert(out, entry)
                end
            end
        end
    elseif activeTab == "social" and ns.Social then
        local showOffline = not (ns.db and ns.db.settings and ns.db.settings.socialShowOffline == false)
        local sortMode = (ns.db and ns.db.settings and ns.db.settings.socialSortBy) or "smart"
        local items = ns.Social.GetDirectoryList and ns.Social:GetDirectoryList({
            sourceFilter = socialFilter,
            folderFilter = socialFolderFilter,
            showOffline = showOffline,
            sortBy = sortMode,
        }) or ns.Social:GetList(socialFilter)

        for _, item in ipairs(items) do
            local meta = (item.lookupKey and ns.Store)
                and ((ns.Store.GetResolvedSocialMeta and ns.Store:GetResolvedSocialMeta(item.lookupKey)) or (ns.Store.GetSocialMeta and ns.Store:GetSocialMeta(item.lookupKey)))
                or nil
            if SafeTextMatches(
                searchQuery,
                item.displayName,
                item.area,
                item.note,
                item.friendNote,
                item.bnetNote,
                item.guildNote,
                item.guild,
                item.bnetName,
                item.richPresence,
                item.customMessage,
                meta and meta.folder,
                meta and meta.mainName,
                meta and meta.nickname,
                meta and meta.note
            ) then
                table.insert(out, item)
            end
        end
    elseif activeTab == "nearby" and ns.Nearby then
        for _, item in ipairs(ns.Nearby:GetList()) do
            if SafeTextMatches(searchQuery, item.displayName, item.guild, item.area, item.source) then
                table.insert(out, item)
            end
        end
    elseif activeTab == "alts" and ns.Store then
        for _, alt in ipairs(ns.Store:GetAltsList()) do
            if SafeTextMatches(searchQuery, alt.fullName, alt.surname, alt.name, alt.zone, alt.guild, alt.faction) then
                table.insert(out, alt)
            end
        end
    end

    local function InjectExpandedDetail(rows)
        if activeTab ~= "social" or not UI._expandedSocialKey or type(rows) ~= "table" or #rows == 0 then
            return rows
        end
        local res = {}
        for i = 1, #rows do
            local it = rows[i]
            res[#res + 1] = it
            if it and not it._isSocialFolderHeader and not it._isSocialDetailRow then
                local k = UI._GetSocialItemExpandKey(it)
                if k and k == UI._expandedSocialKey then
                    res[#res + 1] = {
                        _isSocialDetailRow = true,
                        _tab = "social",
                        parentItem = it,
                    }
                end
            end
        end
        return res
    end

    if activeTab == "social" and #out > 0 and socialFolderFilter == "all" and socialFilter ~= "blocked"
        and (not ns.db or not ns.db.settings or ns.db.settings.socialGroupByFolder ~= false) then
        local grouped = UI._BuildGroupedSectionRows(out, collapsedSocialFolders.social, function(it)
            return it.online == true
        end, function(it)
            local meta = (it.lookupKey and ns.Store)
                and ((ns.Store.GetResolvedSocialMeta and ns.Store:GetResolvedSocialMeta(it.lookupKey)) or (ns.Store.GetSocialMeta and ns.Store:GetSocialMeta(it.lookupKey)))
                or nil
            local isFav = (it.lookupKey ~= nil and ns.Store and ns.Store.IsSocialFavorite and ns.Store:IsSocialFavorite(it.lookupKey)) == true
            local isFriendOrBNet = it.sources and (it.sources.friend == true or it.sources.bnet == true)
            local isGuild = it.sources and it.sources.guild == true
            if isFav then
                return "__fav", L["Favorites"], false
            elseif meta and type(meta.folder) == "string" and meta.folder ~= "" then
                return "f:" .. meta.folder:lower(), meta.folder, true
            elseif it.online == true and isFriendOrBNet then
                return "__online", L["Online Friends"], false
            elseif isGuild and not isFriendOrBNet then
                return "__guild", L["Guild"], false
            elseif it.online == true then
                return "__online", L["Online Friends"], false
            end
            return "__offline", L["Offline"], false
        end)
        return InjectExpandedDetail(grouped)
    elseif activeTab == "watchlist" and #out > 0 and watchlistGroupFilter == "all" then
        local inGuild = Compat.IsInGuild and Compat.IsInGuild()
        local myGuildInfo = inGuild and ns.Clan and ns.Clan.GetMyGuildInfo and ns.Clan:GetMyGuildInfo() or nil
        local myGuildLower = (myGuildInfo and type(myGuildInfo.name) == "string" and myGuildInfo.name ~= "") and myGuildInfo.name:lower() or ""
        return UI._BuildGroupedSectionRows(out, collapsedSocialFolders.watchlist, function(it)
            return it.status == "online"
        end, function(it)
            local wKey = it.id or it.lookupKey
            local isFav = (it.favorite == true) or (wKey ~= nil and ns.Store and ns.Store.IsSocialFavorite and ns.Store:IsSocialFavorite(wKey) == true)
            local isGuild = inGuild and ((Compat.IsGuildMember and Compat.IsGuildMember(nil, it.guid, it.displayName))
                or (myGuildLower ~= "" and type(it.guild) == "string" and it.guild:lower() == myGuildLower))
            if isFav then
                return "__fav", L["Favorites"], false
            elseif type(it.group) == "string" and it.group ~= "" then
                return "g:" .. it.group:lower(), it.group, true
            elseif it.status == "online" then
                return "__online", L["Online"], false
            elseif isGuild then
                return "__guild", L["Guild"], false
            end
            return "__offline", L["Offline"], false
        end)
    end

    return InjectExpandedDetail(out)
end

local function OpenEventMenu(anchor, evt)
    if not (MenuUtil and MenuUtil.CreateContextMenu and evt and ns.Clan) then
        return
    end
    local sum = ns.Clan:GetSignupSummary(evt)
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle(evt.title or L["Guild Event"])
        for _, roleId in ipairs({ "TANK", "HEALER", "DPS", "MAYBE", "DECLINE" }) do
            local rId = roleId
            root:CreateButton(ROLE_LABELS[rId] or rId, function()
                ns.Clan:SignupEvent(evt.id, rId)
            end)
        end
        if sum and sum.signups and #sum.signups > 0 then
            local firstUninvited = nil
            local uninvitedCount = 0
            local hasOther = false
            for _, s in ipairs(sum.signups) do
                if s.name and not Compat.IsMe(s.name) then
                    hasOther = true
                    if (s.role == "TANK" or s.role == "HEALER" or s.role == "DPS") and not (Compat.IsInMyGroup and Compat.IsInMyGroup(s.name)) then
                        uninvitedCount = uninvitedCount + 1
                        if not firstUninvited then
                            firstUninvited = s
                        end
                    end
                end
            end
            if hasOther then
                root:CreateDivider()
                root:CreateTitle(L["Invite Applicant"])
                if firstUninvited and uninvitedCount > 0 then
                    root:CreateButton(L["Invite Next Applicant (%s · %d left)"]:format(firstUninvited.name, uninvitedCount), function()
                        if Compat.Invite then
                            Compat.Invite(firstUninvited.name)
                        end
                    end)
                end
                for _, s in ipairs(sum.signups) do
                    if s.name and not Compat.IsMe(s.name) then
                        local target = s.name
                        if not (Compat.IsInMyGroup and Compat.IsInMyGroup(target)) then
                            root:CreateButton(L["Invite %s (%s)"]:format(target, ROLE_LABELS[s.role] or s.role), function()
                                Compat.Invite(target)
                            end)
                        end
                        root:CreateButton(L["Whisper %s"]:format(target), function()
                            Compat.Whisper(target)
                        end)
                    end
                end
            end
        end
        local myParsed = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
        local isCreator = (myParsed and evt.creatorKey and myParsed.lookupKey == evt.creatorKey)
            or (myParsed and evt.creator and (myParsed.displayName == evt.creator or myParsed.firstName:lower() == evt.creator:lower()))
        local canManage = (isCreator or ((not evt.isAlliedEvent) and ns.Clan and ns.Clan.CanModerateEvents and ns.Clan:CanModerateEvents())) == true

        root:CreateDivider()
        if canManage then
            root:CreateButton(evt.isOpen == false and L["Reopen Event"] or L["Close Event"], function()
                ns.Clan:ToggleEventOpen(evt.id)
            end)
            if not evt.isAlliedEvent and ns.Clan and ns.Clan.SetEventAlliedSharing then
                local isShared = evt.shareAllies ~= false
                root:CreateButton(isShared and L["Stop Sharing with Allied Guilds"] or L["Share with Authorized Allied Guilds"], function()
                    ns.Clan:SetEventAlliedSharing(evt.id, not isShared)
                end)
            end
            root:CreateButton(L["Reannounce Event"], function()
                ns.Clan:ReannounceEvent(evt.id)
            end)
        end
        root:CreateButton(L["Share in Guild Chat (/g)"], function()
            if ns.Clan and ns.Clan.ShareEventToGuildChat then
                ns.Clan:ShareEventToGuildChat(evt)
            end
        end)
        if not Compat.IsInGroup or not Compat.IsInGroup() or (Compat.CanManageGroupListing and Compat.CanManageGroupListing()) then
            root:CreateButton(L["Broadcast in LFG Finder (I)"], function()
                local role = (ns.Clan and ns.Clan.GetMySpecAndRole and ns.Clan:GetMySpecAndRole()) or "DPS"
                local isDng = evt.category == "DUNGEON"
                if ns.Clan and ns.Clan.PostLFG then
                    ns.Clan:PostLFG("LFM", role, evt.title or L["Guild Event"], 0, evt.whenText or L["Now"], false, isDng)
                end
                if ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
                    ns.LFGFrameTab.viewMode = "browse"
                    ns.LFGFrameTab._hasSearchedThisSession = true
                    ns.LFGFrameTab:OpenOfficialModule("lfg")
                end
            end)
        end
        root:CreateButton(L["Copy Name"], function()
            OpenCopyModal(evt.title or "")
        end)
        if canManage then
            root:CreateButton(L["Cancel / Remove Event"], function()
                UI:OpenConfirmModal({
                    title = L["Cancel / Remove Event"],
                    message = L["Are you sure you want to cancel and remove the event '%s'?"]:format(evt.title or "?"),
                    confirmText = L["Remove"],
                    onConfirm = function()
                        if ns.Clan then ns.Clan:RemoveEvent(evt.id) end
                    end,
                })
            end)
        end
    end)
end

local function CreateEventRow(parent, _, rowHeight)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(rowHeight)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.evtBar = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.evtBar:SetWidth(3)
    row.evtBar:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -4)
    row.evtBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 4)
    row.evtBar:SetColorTexture(0.95, 0.76, 0.24, 0.85)

    row.titleText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.titleText:SetPoint("TOPLEFT", 10, -7)
    row.titleText:SetJustifyH("LEFT")
    row.titleText:SetWordWrap(false)

    row.subText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.subText:SetPoint("BOTTOMLEFT", 10, 7)
    row.subText:SetJustifyH("LEFT")
    row.subText:SetWordWrap(false)

    row.btnDel = Theme:CreateButton(row, 20, 20, "X", "danger")
    row.btnDel:SetPoint("RIGHT", -6, 0)

    row.btnDps = Theme:CreateButton(row, 22, 20, "D", "default")
    row.btnDps:SetPoint("RIGHT", row.btnDel, "LEFT", -4, 0)

    row.btnHeal = Theme:CreateButton(row, 22, 20, "H", "default")
    row.btnHeal:SetPoint("RIGHT", row.btnDps, "LEFT", -4, 0)

    row.btnTank = Theme:CreateButton(row, 22, 20, "T", "default")
    row.btnTank:SetPoint("RIGHT", row.btnHeal, "LEFT", -4, 0)

    row.titleText:SetPoint("RIGHT", row.btnTank, "LEFT", -6, 0)
    row.subText:SetPoint("RIGHT", row.btnTank, "LEFT", -6, 0)

    row.btnTank:SetScript("OnClick", function()
        if row._evt and ns.Clan then
            local role = (row._myRole == "TANK") and "DECLINE" or "TANK"
            ns.Clan:SignupEvent(row._evt.id, role)
        end
    end)
    row.btnHeal:SetScript("OnClick", function()
        if row._evt and ns.Clan then
            local role = (row._myRole == "HEALER") and "DECLINE" or "HEALER"
            ns.Clan:SignupEvent(row._evt.id, role)
        end
    end)
    row.btnDps:SetScript("OnClick", function()
        if row._evt and ns.Clan then
            local role = (row._myRole == "DPS") and "DECLINE" or "DPS"
            ns.Clan:SignupEvent(row._evt.id, role)
        end
    end)
    row.btnDel:SetScript("OnClick", function()
        if row._evt and ns.Clan then
            local evt = row._evt
            UI:OpenConfirmModal({
                title = L["Cancel / Remove Event"],
                message = L["Are you sure you want to cancel and remove the event '%s'?"]:format(evt.title or "?"),
                confirmText = L["Remove"],
                onConfirm = function()
                    if ns.Clan then ns.Clan:RemoveEvent(evt.id) end
                end,
            })
        end
    end)

    row.btnTank:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["Tank"], 1, 1, 1)
            local isSigned = row._myRole == "TANK"
            GameTooltip:AddLine(isSigned and L["Click to cancel signup."] or L["Click to sign up as Tank."], 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
    end)
    row.btnTank:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    row.btnHeal:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["Healer"], 1, 1, 1)
            local isSigned = row._myRole == "HEALER"
            GameTooltip:AddLine(isSigned and L["Click to cancel signup."] or L["Click to sign up as Healer."], 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
    end)
    row.btnHeal:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    row.btnDps:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["DPS"], 1, 1, 1)
            local isSigned = row._myRole == "DPS"
            GameTooltip:AddLine(isSigned and L["Click to cancel signup."] or L["Click to sign up as DPS."], 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
    end)
    row.btnDps:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    row.btnDel:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["Cancel / Remove Event"], 1, 0.35, 0.35)
            GameTooltip:Show()
        end
    end)
    row.btnDel:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    row:SetScript("OnClick", function(self, mouseButton)
        local evt = self._evt
        if not evt then return end
        if evt._isMotdSuggestion then
            if mouseButton == "LeftButton" then
                OpenEventModal(evt.title, evt.whenText, evt.category)
            end
            return
        end
        local isCal = evt._isCalendarEvent or (clanEventFilter == "calendar")
        if isCal then
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(evt.title or L["Calendar"])
                    root:CreateButton(L["Promote to Shared Event Call (+ Signups)"], function()
                        local nowTm = date("*t", time())
                        local mo = evt.month or (nowTm and nowTm.month) or 1
                        local whenPrefill = string.format("%02d/%02d %02d:%02d", evt.monthDay or 1, mo, evt.hour or 20, evt.minute or 0)
                        OpenEventModal(evt.title, whenPrefill, evt.isGuild and "GUILD" or "RAID")
                    end)
                    root:CreateButton(L["WoW Calendar"], function()
                        OpenCopyModal(
                            "/calendar",
                            L["Copy /calendar Command (Ctrl+C)"],
                            L["Blizzard protects direct opening of the Calendar panel from addons. Copy '/calendar' below or click the Calendar icon on your Minimap."]
                        )
                    end)
                end)
            elseif mouseButton == "LeftButton" then
                OpenCopyModal(
                    "/calendar",
                    L["Copy /calendar Command (Ctrl+C)"],
                    L["Blizzard protects direct opening of the Calendar panel from addons. Copy '/calendar' below or click the Calendar icon on your Minimap."]
                )
            end
        elseif mouseButton == "RightButton" then
            OpenEventMenu(self, evt)
        end
    end)

    row:SetScript("OnEnter", function(self)
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(self, "surface", p)
        if self._syncHover then self:_syncHover(true) end
        if self._evt and self._evt._isMotdSuggestion then
            local ev = self._evt
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["MOTD"] .. ": " .. (ev.title or ""), 1.0, 0.85, 0.25, true)
            if ev.motd and ev.motd ~= "" then
                GameTooltip:AddLine(ev.motd, 0.88, 0.90, 0.94, true)
            end
            GameTooltip:AddLine(L["Detected from Guild MOTD — Click to create Event Call"], 0.45, 0.85, 0.55, true)
            GameTooltip:Show()
            return
        end
        if self._evt and (self._evt._isCalendarEvent or (clanEventFilter == "calendar")) then
            local ev = self._evt
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(ev.title or "", 1.0, 0.85, 0.25, true)
            if ev.month then
                GameTooltip:AddLine(string.format("%02d/%02d  ·  %02d:%02d", ev.monthDay or 0, ev.month or 0, ev.hour or 0, ev.minute or 0), 0.78, 0.86, 0.96)
            else
                GameTooltip:AddLine(string.format("%02d  ·  %02d:%02d", ev.monthDay or 0, ev.hour or 0, ev.minute or 0), 0.78, 0.86, 0.96)
            end
            if ev.invitedBy and ev.invitedBy ~= "" then
                GameTooltip:AddLine(L["Host"] .. ": " .. ev.invitedBy, 0.85, 0.88, 0.94)
            end
            GameTooltip:AddLine(L["Click to promote to Shared Event Call or open WoW Calendar"], 0.45, 0.85, 0.55, true)
            GameTooltip:Show()
            return
        end
        if self._evt and ns.Clan then
            local evt = self._evt
            local sum = ns.Clan:GetSignupSummary(evt)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine((CAT_LABELS[evt.category] or evt.category) .. ": " .. (evt.title or ""), 0.35, 0.72, 1.0, true)
            GameTooltip:AddLine((evt.whenText or L["Now"]) .. "  ·  " .. (evt.creator or ""), 0.90, 0.85, 0.55)
            if evt.isAlliedEvent then
                GameTooltip:AddLine(string.format(L["Origin Guild: <%s>"], evt.originGuild or L["Allied Clans"]), 0.25, 0.85, 0.45)
            else
                local mutualAllies = ns.Clan.GetMutuallyAuthorizedAlliedGuilds and ns.Clan:GetMutuallyAuthorizedAlliedGuilds() or {}
                if evt.shareAllies == false then
                    GameTooltip:AddLine(L["Guild-internal event (Allied sharing disabled)"], 0.65, 0.68, 0.75)
                elseif #mutualAllies > 0 then
                    GameTooltip:AddLine(L["Shared with mutually authorized Allied Guilds"], 0.25, 0.85, 0.45)
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Signed Up (%d)"]:format(#sum.signups), 1, 1, 1)
            local myGuildName = (ns.Store and ns.Store.guildInfo and ns.Store.guildInfo.name) or ""
            for _, s in ipairs(sum.signups) do
                local r, g, b = Compat.ClassColor(s.classFile)
                local dispName = s.name or ""
                if s.guild and s.guild ~= "" and (evt.isAlliedEvent or (myGuildName ~= "" and s.guild ~= myGuildName)) then
                    dispName = dispName .. " <" .. s.guild .. ">"
                end
                GameTooltip:AddDoubleLine(dispName, ROLE_LABELS[s.role] or s.role, r, g, b, 0.78, 0.84, 0.92)
            end
            GameTooltip:Show()
        end
    end)

    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if (self.btnWhisper and self.btnWhisper:IsShown() and self.btnWhisper:IsMouseOver())
            or (self.btnInvite and self.btnInvite:IsShown() and self.btnInvite:IsMouseOver())
        then
            return
        end
        if self._syncHover then self:_syncHover(false) end
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(self, (self._dataIdx and self._dataIdx % 2 == 1) and "row" or "rowAlt", p)
    end)

    function row:RefreshTheme()
        Theme:StyleButton(self.btnDel, "danger")
        Theme:StyleButton(self.btnDps, "default")
        Theme:StyleButton(self.btnHeal, "default")
        Theme:StyleButton(self.btnTank, "default")
    end

    return row
end

local function FormatEventSlotStr(prefix, cur, need)
    if need and need > 0 then
        return string.format("%s:%d/%d", prefix, cur or 0, need)
    end
    return string.format("%s:%d", prefix, cur or 0)
end

local function UpdateEventRow(row, evt, idx, palette)
    row._evt = evt
    row._dataIdx = idx
    row.subText:SetTextColor(palette.textMuted[1], palette.textMuted[2], palette.textMuted[3])

    local isMotd = evt._isMotdSuggestion == true
    local isCal = evt._isCalendarEvent or (clanEventFilter == "calendar")
    local barKey = isMotd and "motd" or (isCal and "cal" or (evt.isAlliedEvent and "allied" or ((evt.isOpen == false) and "closed" or "own")))
    if row.evtBar and row._lastBarColorKey ~= barKey then
        row._lastBarColorKey = barKey
        if barKey == "allied" then
            row.evtBar:SetColorTexture(0.25, 0.85, 0.45, 0.92)
        elseif barKey == "cal" then
            row.evtBar:SetColorTexture(0.35, 0.75, 1.0, 0.88)
        elseif barKey == "closed" then
            row.evtBar:SetColorTexture(0.96, 0.28, 0.28, 0.82)
        else
            row.evtBar:SetColorTexture(0.95, 0.76, 0.24, 0.85)
        end
    end
    local calKey = isMotd and "motd" or (isCal and "cal" or "evt")
    if isMotd then
        if row._lastCalMode ~= calKey then
            row._lastCalMode = calKey
            row._lastCanManage = nil
            row.btnTank:Hide()
            row.btnHeal:Hide()
            row.btnDps:Hide()
            row.btnDel:Hide()
            row.titleText:ClearAllPoints()
            row.titleText:SetPoint("TOPLEFT", 10, -7)
            row.titleText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.subText:ClearAllPoints()
            row.subText:SetPoint("BOTTOMLEFT", 10, 7)
            row.subText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        end
        row.titleText:SetText("|cfff2c94c[" .. L["MOTD"] .. "]|r " .. (evt.title or ""))
        row.subText:SetText("|cff58a6ff" .. L["Detected from Guild MOTD — Click to create Event Call"] .. "|r")
        return
    end
    if isCal then
        if row._lastCalMode ~= calKey then
            row._lastCalMode = calKey
            row._lastCanManage = nil
            row.btnTank:Hide()
            row.btnHeal:Hide()
            row.btnDps:Hide()
            row.btnDel:Hide()
            row.titleText:ClearAllPoints()
            row.titleText:SetPoint("TOPLEFT", 10, -7)
            row.titleText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.subText:ClearAllPoints()
            row.subText:SetPoint("BOTTOMLEFT", 10, 7)
            row.subText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        end

        local tag = evt.isGuild and ("|cfff2c94c[" .. L["Calendar"] .. "]|r ") or "|cff9da7b5[Event]|r "
        row.titleText:SetText(tag .. (evt.title or ""))
        local dayLabel = (evt.dayDelta == 0) and L["Today"] or ((evt.dayDelta == 1) and L["Tomorrow"] or string.format(L["Day %d"], evt.monthDay or 0))
        local parts = { string.format("%s %02d:%02d", dayLabel, evt.hour or 0, evt.minute or 0) }
        if evt.invitedBy and evt.invitedBy ~= "" then
            table.insert(parts, evt.invitedBy)
        end
        row.subText:SetText(table.concat(parts, "  ·  "))
        return
    end

    if row._lastCalMode ~= calKey then
        row._lastCalMode = calKey
        row.btnTank:Show()
        row.btnHeal:Show()
        row.btnDps:Show()
        row.titleText:ClearAllPoints()
        row.titleText:SetPoint("TOPLEFT", 10, -7)
        row.titleText:SetPoint("RIGHT", row.btnTank, "LEFT", -6, 0)
        row.subText:ClearAllPoints()
        row.subText:SetPoint("BOTTOMLEFT", 10, 7)
        row.subText:SetPoint("RIGHT", row.btnTank, "LEFT", -6, 0)
    end

    local catLabel = CAT_LABELS[evt.category] or evt.category or ""
    local closedTag = (evt.isOpen == false) and ("|cffff6b6b[" .. L["Closed"] .. "]|r ") or ""
    local allyPrefix = evt.isAlliedEvent and ("|cff40d973[" .. string.format(L["ALLY: %s"], evt.originGuild or L["Ally Clan"]) .. "]|r ") or ""
    local sharedBadge = ""
    if not evt.isAlliedEvent and evt.shareAllies ~= false and ns.Clan and ns.Clan.GetMutuallyAuthorizedAlliedGuilds then
        local mutualAllies = ns.Clan:GetMutuallyAuthorizedAlliedGuilds()
        if mutualAllies and #mutualAllies > 0 then
            sharedBadge = "  |cff40d973[" .. L["+Allies"] .. "]|r"
        end
    end
    row.titleText:SetText(closedTag .. allyPrefix .. "|cff58a6ff[" .. catLabel .. "]|r " .. (evt.title or "") .. sharedBadge)

    local sum = ns.Clan and ns.Clan:GetSignupSummary(evt) or { TANK = 0, HEALER = 0, DPS = 0 }
    local slots = string.format(
        "%s %s %s",
        FormatEventSlotStr("T", sum.TANK, evt.needT),
        FormatEventSlotStr("H", sum.HEALER, evt.needH),
        FormatEventSlotStr("D", sum.DPS, evt.needD)
    )
    local lvlPart = (evt.minLvl and evt.minLvl > 0) and ("  ·  Lv" .. evt.minLvl .. "+") or ""
    row.subText:SetText(string.format("%s  ·  %s  ·  %s%s", evt.whenText or L["Now"], evt.creator or "", slots, lvlPart))

    local myParsed = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    if not myParsed then
        local myName = ns.Safe and ns.Safe.String(ns.Safe.Call(UnitName, "player"))
        myParsed = myName and Compat.ParseCharacterName(myName)
    end
    local mySignup = myParsed and evt.signups and evt.signups[myParsed.lookupKey]
    local myRole = mySignup and mySignup.role or nil
    row._myRole = myRole

    local isCreator = (myParsed and evt.creatorKey and myParsed.lookupKey == evt.creatorKey)
        or (myParsed and evt.creator and (myParsed.displayName == evt.creator or myParsed.firstName:lower() == evt.creator:lower()))
    local canManage = (isCreator or ((not evt.isAlliedEvent) and ns.Clan and ns.Clan.CanModerateEvents and ns.Clan:CanModerateEvents())) == true

    if row._lastCanManage ~= canManage then
        row._lastCanManage = canManage
        if canManage then
            row.btnDel:Show()
            row.btnDps:ClearAllPoints()
            row.btnDps:SetPoint("RIGHT", row.btnDel, "LEFT", -4, 0)
        else
            row.btnDel:Hide()
            row.btnDps:ClearAllPoints()
            row.btnDps:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        end
    end

    Theme:SetButtonActive(row.btnTank, myRole == "TANK", myRole == "TANK" and "primary" or "default")
    Theme:SetButtonActive(row.btnHeal, myRole == "HEALER", myRole == "HEALER" and "primary" or "default")
    Theme:SetButtonActive(row.btnDps, myRole == "DPS", myRole == "DPS" and "primary" or "default")
end

local function FormatClanProfParts(item)
    local pMap = (ns.SocialPanels and ns.SocialPanels.PROF_LABELS) or {}
    local pList = {}
    if item.prof1 and item.prof1 ~= "" and item.prof1 ~= "NONE" then
        local lbl = pMap[item.prof1] or item.prof1
        if item.prof1Rank and item.prof1Rank ~= "" then
            lbl = lbl .. " (" .. item.prof1Rank .. ")"
        end
        table.insert(pList, lbl)
    end
    if item.prof2 and item.prof2 ~= "" and item.prof2 ~= "NONE" then
        local lbl = pMap[item.prof2] or item.prof2
        if item.prof2Rank and item.prof2Rank ~= "" then
            lbl = lbl .. " (" .. item.prof2Rank .. ")"
        end
        table.insert(pList, lbl)
    end
    return pList
end

local PEER_CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local UpdateClanPanel

local function ShortClassLabel(locClass)
    if type(locClass) ~= "string" or locClass == "" then
        return ""
    end
    local out = {}
    for ch in locClass:gmatch("[\1-\127\194-\244][\128-\191]*") do
        out[#out + 1] = ch
        if #out >= 3 then break end
    end
    return table.concat(out)
end

local function CreatePeerRow(parent, _, rowHeight)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(rowHeight)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.statusBar = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.statusBar:SetWidth(3)
    row.statusBar:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -4)
    row.statusBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 4)
    row.statusBar:SetColorTexture(0.35, 0.75, 1.0, 0.80)

    row.dot = row:CreateTexture(nil, "ARTWORK", nil, 2)
    row.dot:SetSize(8, 8)
    row.dot:SetPoint("LEFT", 9, 0)
    row.dot:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\dot")
    row.dot._scKeepTexture = true

    row.classIcon = row:CreateTexture(nil, "ARTWORK", nil, 2)
    row.classIcon:SetSize(20, 20)
    row.classIcon:SetPoint("LEFT", row.dot, "RIGHT", 6, 0)
    row.classIcon:SetTexture(PEER_CLASS_TEX)
    row.classIcon:Hide()

    row.rightText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.rightText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.rightText:SetJustifyH("RIGHT")
    row.rightText:SetWordWrap(false)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.nameText:SetPoint("TOPLEFT", 23, -5)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.subText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.subText:SetPoint("BOTTOMLEFT", 23, 5)
    row.subText:SetJustifyH("LEFT")
    row.subText:SetWordWrap(false)

    row.nameText:SetPoint("RIGHT", -10, 0)
    row.subText:SetPoint("RIGHT", -10, 0)

    row:SetScript("OnClick", function(self, mouseButton)
        if (mouseButton == "RightButton" or mouseButton == "LeftButton") and self._item then
            local view = self._item._clanView or clanRightView
            if view == "diplomacy" then
                if MenuUtil and MenuUtil.CreateContextMenu then
                    local entry = self._item
                    local canDip, authSummary = false, L["Guild Leader Only"]
                    if ns.Clan and ns.Clan.CanManageDiplomacy then
                        canDip, authSummary = ns.Clan:CanManageDiplomacy()
                    end
                    local canShare, shareSummary = canDip, authSummary
                    if ns.Clan and ns.Clan.CanManageAlliedEventSharing then
                        canShare, shareSummary = ns.Clan:CanManageAlliedEventSharing()
                    end
                    MenuUtil.CreateContextMenu(self, function(_, root)
                        root:CreateTitle(entry.name or "?")
                        if entry.stance == "ALLY" and canShare then
                            local st = (ns.Clan and ns.Clan.GetAlliedEventShareState) and ns.Clan:GetAlliedEventShareState(entry.name) or { myApproved = false }
                            root:CreateButton(st.myApproved and L["Revoke Shared Events with Ally"] or L["Authorize Shared Events with Ally"], function()
                                if ns.Clan and ns.Clan.SetAlliedEventSharing then
                                    ns.Clan:SetAlliedEventSharing(entry.name, not st.myApproved)
                                end
                            end)
                            root:CreateButton(L["Send / Refresh Authorization Handshake"], function()
                                if ns.Clan and ns.Clan.SendAlliedEventHandshake then
                                    ns.Clan:SendAlliedEventHandshake(entry.name, true)
                                end
                            end)
                            root:CreateDivider()
                        end
                        if canDip then
                            root:CreateButton(L["Edit Diplomacy Entry"], function()
                                OpenDiplomacyModal(entry.name, entry.stance, entry.faction)
                            end)
                            root:CreateButton(L["Mark Ally"], function()
                                if ns.Clan then ns.Clan:SetGuildStance(entry.name, "ALLY", entry.reason or "", entry.faction) end
                            end)
                            root:CreateButton(L["Mark Enemy"], function()
                                if ns.Clan then ns.Clan:SetGuildStance(entry.name, "ENEMY", entry.reason or "", entry.faction) end
                            end)
                            root:CreateButton(L["Remove Diplomacy Entry"], function()
                                UI:OpenConfirmModal({
                                    title = L["Remove Diplomacy Entry"],
                                    message = L["Are you sure you want to remove <%s> from Guild Diplomacy?"]:format(entry.name or entry.key or "?"),
                                    confirmText = L["Remove"],
                                    onConfirm = function()
                                        if ns.Clan then ns.Clan:RemoveGuildDiplomacy(entry.key) end
                                    end,
                                })
                            end)
                        elseif canShare and entry.stance == "ALLY" then
                            root:CreateTitle("|cff58a6ff" .. L["Authorized to toggle shared Allied Events only (%s)."]:format(shareSummary) .. "|r")
                        else
                            root:CreateTitle("|cff8b949e" .. L["View Only (Leadership Controlled)"] .. "|r")
                            root:CreateTitle("|cff9da7b5" .. L["Diplomacy Authority: %s"]:format(authSummary) .. "|r")
                        end
                        root:CreateDivider()
                        root:CreateButton(L["Sync Intel"], function()
                            if ns.Clan then ns.Clan:BroadcastFullIntel() end
                        end)
                        root:CreateButton(L["Hierarchy & Ranks"], function()
                            clanRightView = "hierarchy"
                            UpdateClanPanel()
                        end)
                    end)
                end
                return
            elseif view == "hierarchy" then
                if MenuUtil and MenuUtil.CreateContextMenu then
                    local rankItem = self._item
                    local isGM = ns.Clan and ns.Clan.IsGuildLeader and ns.Clan:IsGuildLeader()
                    MenuUtil.CreateContextMenu(self, function(_, root)
                        root:CreateTitle(string.format("#%d %s", rankItem.rankIndex or 0, rankItem.name or "?"))
                        if isGM and ns.Clan and ns.Clan.SaveGuildHierarchyPolicy then
                            local rIdx = rankItem.rankIndex or 0
                            root:CreateButton(L["Allow Diplomacy up to this Rank"], function()
                                if rIdx == 0 then
                                    ns.Clan:SaveGuildHierarchyPolicy({ diplomacyMode = "LEADER", diplomacyMaxRank = 0 })
                                else
                                    ns.Clan:SaveGuildHierarchyPolicy({ diplomacyMode = "RANK", diplomacyMaxRank = rIdx })
                                end
                            end)
                            root:CreateButton(L["Allow Guild Info Edit up to this Rank"], function()
                                if rIdx == 0 then
                                    ns.Clan:SaveGuildHierarchyPolicy({ infoMode = "LEADER", infoMaxRank = 0 })
                                else
                                    ns.Clan:SaveGuildHierarchyPolicy({ infoMode = "RANK", infoMaxRank = rIdx })
                                end
                            end)
                            root:CreateButton(L["Allow Event Moderation up to this Rank"], function()
                                if rIdx == 0 then
                                    ns.Clan:SaveGuildHierarchyPolicy({ eventModMode = "LEADER", eventModMaxRank = 0 })
                                else
                                    ns.Clan:SaveGuildHierarchyPolicy({ eventModMode = "RANK", eventModMaxRank = rIdx })
                                end
                            end)
                            root:CreateButton(L["Allow Alliance Chat up to this Rank"], function()
                                ns.Clan:SaveGuildHierarchyPolicy({ allianceMinRank = rIdx })
                            end)
                            root:CreateDivider()
                        end
                        root:CreateButton(L["Filter Roster by this Rank"], function()
                            clanPeerRankFilter = rankItem.rankIndex
                            clanPeerQuery = ""
                            if clanPanel and clanPanel.peerSearch and clanPanel.peerSearch.SetText then
                                clanPanel.peerSearch:SetText("")
                            end
                            clanRightView = "peers"
                            UpdateClanPanel()
                        end)
                    end)
                end
                return
            elseif view == "prof" then
                if MenuUtil and MenuUtil.CreateContextMenu then
                    local entry = self._item
                    MenuUtil.CreateContextMenu(self, function(_, root)
                        local pList = FormatClanProfParts(entry)
                        root:CreateTitle((entry.displayName or "?") .. (#pList > 0 and (" — " .. table.concat(pList, " / ")) or ""))
                        if entry.isSelf then
                            root:CreateButton(L["Edit My Professions & Craft Note"], function()
                                if ns.SocialPanels and ns.SocialPanels.OpenProfessionModal then
                                    ns.SocialPanels:OpenProfessionModal()
                                end
                            end)
                        elseif (not entry.isAlt) and (not entry.isMe) and entry.displayName and not (Compat.IsMe and Compat.IsMe(entry.displayName)) then
                            local qWant = (entry.matchedRecipe and entry.matchedRecipe ~= "") and entry.matchedRecipe or (ns.Clan and ns.Clan._lastProfQuery)
                            local craftTopic = (qWant and qWant ~= "") and qWant or ((#pList > 0) and table.concat(pList, " / ") or L["Profession"])
                            local draftMsg = string.format(L["Hi! Could you craft %s for me?"], craftTopic)
                            root:CreateButton(L["Request Craft (/w)"], function()
                                Compat.Whisper(entry.displayName, draftMsg)
                            end)
                            local profConfirmed = ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(entry.lookupKey or entry.displayName, entry.bnetAccountID)
                            if profConfirmed then
                                root:CreateButton(L["Open in SocialCentral Chat"], function()
                                    if ns.Chat and ns.Chat.OpenDirectConversation then
                                        ns.Chat:OpenDirectConversation({
                                            targetName = entry.displayName,
                                            classFile = entry.classFile,
                                            draftText = draftMsg,
                                            autoProbe = true,
                                        })
                                        UI:OpenTab("chat")
                                    end
                                end)
                            end
                            if entry.online ~= false and not (Compat.IsInMyGroup and Compat.IsInMyGroup(entry.displayName)) then
                                root:CreateButton(L["Invite"], function()
                                    Compat.Invite(entry.displayName, entry.bnetAccountID)
                                end)
                            end
                            local isWatched = ns.Watchlist and ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(entry.lookupKey or entry.displayName)
                            if isWatched then
                                root:CreateButton(L["Remove from Watchlist"], function()
                                    local wlKey = entry.lookupKey or entry.displayName
                                    UI:OpenConfirmModal({
                                        title = L["Remove from Watchlist"],
                                        message = L["Are you sure you want to remove %s from your Watchlist?"]:format(entry.displayName or wlKey or "?"),
                                        confirmText = L["Remove"],
                                        onConfirm = function()
                                            if ns.Watchlist then ns.Watchlist:Remove(wlKey) end
                                        end,
                                    })
                                end)
                            else
                                root:CreateButton(L["Add to Watchlist"], function()
                                    if ns.Watchlist then ns.Watchlist:Add(entry.displayName or entry.lookupKey) end
                                end)
                            end
                        end
                        if entry.displayName then
                            root:CreateButton(L["Copy Name"], function()
                                OpenCopyModal(entry.displayName)
                            end)
                        end
                    end)
                end
                return
            elseif view == "locks" then
                if MenuUtil and MenuUtil.CreateContextMenu then
                    local entry = self._item
                    MenuUtil.CreateContextMenu(self, function(_, root)
                        root:CreateTitle(entry.instanceName or entry.title or L["Locks"])
                        root:CreateButton(L["Refresh Lockouts"], function()
                            if ns.Clan and ns.Clan.RequestLockoutsRefresh then
                                ns.Clan:RequestLockoutsRefresh(true)
                            end
                            UpdateClanPanel()
                        end)
                        if entry.instanceName and entry.instanceName ~= "" then
                            root:CreateButton(L["Copy Name"], function()
                                OpenCopyModal(entry.instanceName)
                            end)
                        end
                    end)
                end
                return
            elseif self._item.displayName then
                self._item._isGuildRosterRow = (view == "peers")
                OpenRowMenu(self, self._item, "social")
            end
        end
    end)

    row:SetScript("OnEnter", function(self)
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(self, "surface", p)
        if self._syncHover then self:_syncHover(true) end
        if self._item then
            local item = self._item
            local view = item._clanView or clanRightView
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if view == "locks" then
                GameTooltip:AddLine(item.title or "", 1.0, 0.85, 0.25, true)
                GameTooltip:AddLine(item.detail or "", 0.80, 0.86, 0.94, true)
                if item._isInstanceCapRow and ns.Group and ns.Group.AppendInstanceHistoryTooltip then
                    ns.Group:AppendInstanceHistoryTooltip(GameTooltip)
                end
                GameTooltip:Show()
                return
            elseif view == "diplomacy" then
                local stLbl = item.stance == "ENEMY" and L["Enemy Clan"] or (item.stance == "ALLY" and L["Ally Clan"] or L["Neutral"])
                GameTooltip:AddLine("<" .. (item.name or "?") .. ">  [" .. stLbl .. "]", 1.0, 0.85, 0.25, true)
                if item.reason and item.reason ~= "" then
                    GameTooltip:AddLine(item.reason, 0.92, 0.94, 0.96, true)
                end
                GameTooltip:AddLine(string.format("%s: %s (%s)", L["Updated by"], item.addedBy or "?", Compat.FormatRelativeTime(item.updatedAt, L)), 0.65, 0.72, 0.82, true)
                GameTooltip:AddLine(L["Right-click to edit stance or remove."], 0.55, 0.82, 0.62, true)
                GameTooltip:Show()
                return
            elseif view == "hierarchy" then
                GameTooltip:AddLine(string.format("#%d  %s", item.rankIndex or 0, item.name or "?"), 1.0, 0.85, 0.25, true)
                GameTooltip:AddLine(string.format("%s: %d/%d %s", L["Members"], item.onlineMembers or 0, item.totalMembers or 0, L["Online"]:lower()), 0.82, 0.90, 0.96)
                if item.permSummary and item.permSummary ~= "" then
                    GameTooltip:AddLine(item.permSummary, 0.55, 0.86, 0.65, true)
                end
                if item.nativeSummary and item.nativeSummary ~= "" then
                    GameTooltip:AddLine(L["Native Rank"] .. ": " .. item.nativeSummary, 0.92, 0.84, 0.45, true)
                end
                GameTooltip:Show()
                return
            end
            GameTooltip:AddLine((item.displayName or "") .. (item.version and ("  (v" .. item.version .. ")") or ""), 1, 1, 1)
            if view == "lfg" then
                local modeStr = (item.mode or "LFG") .. ((item.role and item.role ~= "ANY") and (" · " .. (ROLE_LABELS[item.role] or item.role)) or "")
                GameTooltip:AddLine(modeStr .. " — " .. (item.activity or ""), 0.35, 0.88, 0.55, true)
                if item.note and item.note ~= "" then
                    GameTooltip:AddLine(item.note, 0.90, 0.92, 0.96, true)
                end
            elseif view == "prof" then
                local srcMap = {
                    SELF = L["Current Character (Auto-Detected)"],
                    SC = L["SocialCentral Guild Sync"],
                    NOTE = L["Guild Public Note"],
                    CHAT = L["Guild Chat"],
                    ALT = L["My Alt"],
                }
                if item.sourceTag and srcMap[item.sourceTag] then
                    GameTooltip:AddLine(L["Source"] .. ": " .. srcMap[item.sourceTag], 0.58, 0.78, 0.98)
                end
                local pNames = FormatClanProfParts(item)
                if #pNames > 0 then
                    GameTooltip:AddLine(table.concat(pNames, "  ·  "), 0.35, 0.88, 0.50, true)
                end
                if item.secSummary and item.secSummary ~= "" then
                    GameTooltip:AddLine(L["Secondary"] .. ": " .. item.secSummary, 0.72, 0.84, 0.78, true)
                end
                if item.matchedRecipe and item.matchedRecipe ~= "" then
                    GameTooltip:AddLine(L["Recipe"] .. ": " .. item.matchedRecipe, 0.35, 0.94, 0.56, true)
                end
                if item.matchedRecipeReagents and item.matchedRecipeReagents ~= "" then
                    GameTooltip:AddLine(L["Materials"] .. ": " .. item.matchedRecipeReagents, 0.95, 0.85, 0.45, true)
                end
                if item.recipeCount and item.recipeCount > 0 then
                    GameTooltip:AddLine(L["Cataloged Recipes"] .. ": " .. tostring(item.recipeCount), 0.70, 0.85, 0.98)
                end
                if item.craftNote and item.craftNote ~= "" then
                    GameTooltip:AddLine(L["Craft Note"] .. ": " .. item.craftNote, 0.95, 0.85, 0.45, true)
                end
                if item.guildNote and item.guildNote ~= "" then
                    GameTooltip:AddLine(L["Guild Note"] .. ": " .. item.guildNote, 0.75, 0.82, 0.92, true)
                end
                if item.area and item.area ~= "" then
                    GameTooltip:AddLine(item.area, 0.78, 0.84, 0.92)
                end
                GameTooltip:AddLine(item.isSelf and L["Click to edit your professions or publish Guild Note."] or L["Click to whisper craft request, invite, or copy name."], 0.45, 0.85, 0.55, true)
            elseif view == "gchat" then
                GameTooltip:AddLine(item.text or "", 0.55, 0.85, 1.0, true)
            else
                if item.rankName and item.rankName ~= "" then
                    GameTooltip:AddLine(L["Rank"] .. ": " .. item.rankName, 0.90, 0.82, 0.48)
                end
                local tagLabel = TAG_LABELS[item.tag or "NONE"] or item.tag or ""
                GameTooltip:AddLine(tagLabel .. ((item.note and item.note ~= "") and (" — " .. item.note) or ""), 0.55, 0.85, 1.0, true)
                if item.area and item.area ~= "" then
                    GameTooltip:AddLine(item.area, 0.78, 0.84, 0.92)
                end
                local abs = (item.lookupKey and ns.Clan and ns.Clan.GetMemberAbsence) and ns.Clan:GetMemberAbsence(item.lookupKey) or nil
                if abs then
                    GameTooltip:AddLine(("|cffffb833%s: %s|r%s"):format(L["Absent until"], abs.untilDate, (abs.reason and abs.reason ~= "") and (" — " .. abs.reason) or ""), 1.0, 0.75, 0.30, true)
                end
            end
            GameTooltip:Show()
        end
    end)

    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if (self.btnWhisper and self.btnWhisper:IsShown() and self.btnWhisper:IsMouseOver())
            or (self.btnInvite and self.btnInvite:IsShown() and self.btnInvite:IsMouseOver())
        then
            return
        end
        if self._syncHover then self:_syncHover(false) end
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(self, (self._dataIdx and self._dataIdx % 2 == 1) and "row" or "rowAlt", p)
    end)

    function row:RefreshTheme()
    end

    return row
end

local function SyncPeerRowLayout(row, hasIcon, rightTxt, isCompact)
    local leftX = hasIcon and 46 or 24
    local hasRight = type(rightTxt) == "string" and rightTxt ~= ""
    if row.rightText then
        if hasRight then
            row.rightText:SetText(rightTxt)
            row.rightText:Show()
        else
            row.rightText:SetText("")
            row.rightText:Hide()
        end
    end
    if row._lastPeerLeft ~= leftX or row._lastPeerHasRight ~= hasRight or row._lastPeerCompact ~= (isCompact == true) then
        row._lastPeerLeft = leftX
        row._lastPeerHasRight = hasRight
        row._lastPeerCompact = (isCompact == true)
        row.nameText:ClearAllPoints()
        if isCompact then
            row.nameText:SetPoint("LEFT", row, "LEFT", leftX, 0)
        else
            row.nameText:SetPoint("TOPLEFT", leftX, -5)
        end
        row.subText:ClearAllPoints()
        row.subText:SetPoint("BOTTOMLEFT", leftX, 5)
        if hasRight and row.rightText then
            row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -8, 0)
            row.subText:SetPoint("RIGHT", row.rightText, "LEFT", -8, 0)
        else
            row.nameText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            row.subText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        end
    end
    if row.subText then
        row.subText:SetShown(not (isCompact == true))
    end
end

local function SetPeerClassIcon(row, classFile)
    if not row.classIcon then return false end
    local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if coords then
        row.classIcon:SetTexture(PEER_CLASS_TEX)
        row.classIcon:SetTexCoord(coords[1] + 0.02, coords[2] - 0.02, coords[3] + 0.02, coords[4] - 0.02)
        row.classIcon:Show()
        return true
    end
    row.classIcon:Hide()
    return false
end

local function UpdatePeerRow(row, item, idx, palette)
    row._item = item
    row._dataIdx = idx
    row.subText:SetTextColor(palette.textMuted[1], palette.textMuted[2], palette.textMuted[3])

    row.nameText:SetAlpha(1.0)
    row.subText:SetAlpha(1.0)
    if row.classIcon then
        row.classIcon:SetDesaturated(false)
        row.classIcon:SetAlpha(1.0)
    end

    local view = item._clanView or clanRightView
    if view == "locks" then
        Theme:ApplyStatusColor(row.dot, item.statusColor or "unknown")
        if row.statusBar then
            Theme:ApplyStatusColor(row.statusBar, item.statusColor or "unknown")
            row.statusBar:SetAlpha(0.85)
        end
        SetPeerClassIcon(row, nil)
        SyncPeerRowLayout(row, false, nil)
        row.nameText:SetText(item.title or "")
        row.subText:SetText(item.detail or "")
        return
    elseif view == "diplomacy" then
        local tagHex, stanceLbl
        if item.stance == "ENEMY" then
            row.dot:SetVertexColor(0.96, 0.28, 0.28, 1)
            if row.statusBar then row.statusBar:SetColorTexture(0.96, 0.28, 0.28, 0.90) end
            tagHex = "|cfff54747"
            stanceLbl = L["ENEMY"]
        elseif item.stance == "ALLY" then
            row.dot:SetVertexColor(0.25, 0.85, 0.45, 1)
            if row.statusBar then row.statusBar:SetColorTexture(0.25, 0.85, 0.45, 0.90) end
            tagHex = "|cff40d973"
            stanceLbl = L["ALLY"]
        else
            row.dot:SetVertexColor(0.66, 0.70, 0.78, 1)
            if row.statusBar then row.statusBar:SetColorTexture(0.66, 0.70, 0.78, 0.45) end
            tagHex = "|cffb0b8c4"
            stanceLbl = L["NEUTRAL"]
        end
        SetPeerClassIcon(row, nil)
        local timeTxt = "|cff8b949e" .. Compat.FormatRelativeTime(item.updatedAt, L) .. "|r"
        SyncPeerRowLayout(row, false, timeTxt)
        local facStr = (item.faction and item.faction ~= "") and ("  |cff8b949e(" .. item.faction .. ")|r") or ""
        local evtShareBadge = ""
        local peerByStr = ""
        if item.stance == "ALLY" and ns.Clan and ns.Clan.GetAlliedEventShareState then
            local st = ns.Clan:GetAlliedEventShareState(item.name)
            if st.mutual then
                evtShareBadge = "  |cff40d973[" .. L["Events: Mutual"] .. "]|r"
            elseif st.myApproved and not st.peerApproved then
                evtShareBadge = "  |cffffd24d[" .. L["Events: Awaiting Ally"] .. "]|r"
            elseif not st.myApproved and st.peerApproved then
                evtShareBadge = "  |cff58a6ff[" .. L["Events: Ally Requested!"] .. "]|r"
            else
                evtShareBadge = "  |cff8b949e[" .. L["Events: Internal Only"] .. "]|r"
            end
            if st.peerApproved and st.peerApprovedBy and st.peerApprovedBy ~= "" then
                peerByStr = "  ·  " .. string.format(L["Ally auth: %s"], st.peerApprovedBy)
            end
        end
        row.nameText:SetText(string.format("%s[%s]|r  |cffffffff<%s>|r%s%s", tagHex, stanceLbl, item.name or "?", facStr, evtShareBadge))
        local reasonText = (item.reason and item.reason ~= "") and item.reason or L["No note"]
        row.subText:SetText(string.format("%s  ·  %s: %s%s", reasonText, L["Updated by"], item.addedBy or "?", peerByStr))
        return
    elseif view == "hierarchy" then
        local rIdx = item.rankIndex or 0
        if rIdx == 0 then
            row.dot:SetVertexColor(1.0, 0.82, 0.18, 1.0)
            if row.statusBar then row.statusBar:SetColorTexture(1.0, 0.82, 0.18, 0.95) end
        elseif item.hasAddonAuthority then
            row.dot:SetVertexColor(0.35, 0.75, 1.0, 1.0)
            if row.statusBar then row.statusBar:SetColorTexture(0.35, 0.75, 1.0, 0.90) end
        elseif (item.onlineMembers or 0) > 0 then
            row.dot:SetVertexColor(0.25, 0.85, 0.45, 1.0)
            if row.statusBar then row.statusBar:SetColorTexture(0.25, 0.85, 0.45, 0.80) end
        else
            row.dot:SetVertexColor(0.55, 0.60, 0.68, 1.0)
            if row.statusBar then row.statusBar:SetColorTexture(0.55, 0.60, 0.68, 0.35) end
        end
        SetPeerClassIcon(row, nil)
        local countTxt = string.format("|cff9da7b5%d/%d %s|r", item.onlineMembers or 0, item.totalMembers or 0, L["Online"]:lower())
        SyncPeerRowLayout(row, false, countTxt)
        local selfTag = item.isMyRank and ("  |cff58a6ff[" .. L["You"] .. "]|r") or ""
        local nameColor = (rIdx == 0) and "|cffffd200" or (item.hasAddonAuthority and "|cff6ec1e4" or "|cffffffff")
        row.nameText:SetText(string.format("|cff9da7b5#%d|r %s%s|r%s%s", rIdx, nameColor, item.name or "?", selfTag, item.badgeText or ""))
        row.subText:SetText(item.subSummary or L["No permissions listed (Member rank)"])
        return
    end

    local isOnline = (view == "gchat") or (item.online == true)
    local peerDotState = (view == "gchat" or item.isAlt) and "nearby" or (isOnline and "online" or "offline")
    Theme:ApplyStatusColor(row.dot, peerDotState)
    if row.statusBar then
        Theme:ApplyStatusColor(row.statusBar, peerDotState)
        row.statusBar:SetAlpha((isOnline or view == "gchat" or item.isAlt) and 0.90 or 0.25)
    end

    local hasClassIcon = SetPeerClassIcon(row, item.classFile)

    local hex = item.classFile and Compat.ClassHex(item.classFile) or ((palette.key == "blizzard" and isOnline) and "|cffffd100" or Compat.ClassHex(nil))
    local scIconStr = Compat.AddonIconMarkup and Compat.AddonIconMarkup(true, 13) or "|cff3fb950[SC]|r"
    local scTag = (item.hasAddon and (" " .. scIconStr))
        or (item.lookupKey and ns.Chat and ns.Chat.GetLookupKeyAddonBadge and ns.Chat:GetLookupKeyAddonBadge(item.lookupKey))
        or ((item.lookupKey and ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(item.lookupKey)) and (" " .. scIconStr))
        or ""

    local favPeerKey = item.lookupKey or item.displayName
    local isPeerFav = (not item.isAlt) and favPeerKey and ns.Store and ns.Store.IsSocialFavorite and ns.Store:IsSocialFavorite(favPeerKey) == true
    local peerStar = isPeerFav and (Compat.FavoriteStarMarkup and Compat.FavoriteStarMarkup(13) or "") or ""

    if view == "lfg" then
        SyncPeerRowLayout(row, hasClassIcon, "|cff8b949e" .. Compat.FormatRelativeTime(item.updatedAt, L) .. "|r")
        local modeCol = (item.mode == "LFM") and "|cff58a6ff[LFM]|r" or "|cff3fb950[LFG]|r"
        local roleTag = (item.role and item.role ~= "ANY") and (" [" .. (ROLE_LABELS[item.role] or item.role) .. "]") or ""
        local keyTag = (item.keyLvl and item.keyLvl > 0) and (" |cfff2c94c+" .. item.keyLvl .. "|r") or ""
        local dngBadge = item.isDungeon and " |cff6ec1e4[" .. L["Dungeon"] .. "]|r" or ""
        local srcBadge = ""
        if item.isAllied then
            local gShort = (item.guild and item.guild ~= "") and (" " .. item.guild) or ""
            srcBadge = srcBadge .. " |cff40d973[" .. L["ALLY"] .. gShort .. "]|r"
        end
        if item.isWatchlist or item.hasFriendOrWatchlistSignup then
            srcBadge = srcBadge .. " " .. (Compat.StatusIconMarkup and Compat.StatusIconMarkup("WATCH", 13) or ("|cffffa633[" .. L["WATCHLIST"] .. "]|r"))
        elseif item.isFriend then
            srcBadge = srcBadge .. " " .. (Compat.StatusIconMarkup and Compat.StatusIconMarkup("FRIEND", 13) or ("|cff59c7ff[" .. L["FRIEND"] .. "]|r"))
        end
        row.nameText:SetText(modeCol .. " " .. peerStar .. hex .. (item.displayName or "") .. "|r" .. scTag .. roleTag .. keyTag .. dngBadge .. srcBadge)

        local subParts = sublinePartsScratch
        wipe(subParts)
        if item.activity and item.activity ~= "" then subParts[#subParts + 1] = item.activity end
        if item.ilvl and item.ilvl > 0 then subParts[#subParts + 1] = "iLvl " .. item.ilvl end
        if item.note and item.note ~= "" then subParts[#subParts + 1] = item.note end
        if item.hasFriendOrWatchlistSignup and item.friendOrWatchlistNames and item.friendOrWatchlistNames ~= "" then
            subParts[#subParts + 1] = L["In group"] .. ": " .. item.friendOrWatchlistNames
        end
        row.subText:SetText(table.concat(subParts, "  ·  "))
        return
    elseif view == "prof" then
        local rightArea = (item.area and item.area ~= "") and ("|cff9da7b5" .. item.area .. "|r") or nil
        SyncPeerRowLayout(row, hasClassIcon, rightArea)
        local pList = FormatClanProfParts(item)
        local srcBadge = ""
        if item.isAlt then
            srcBadge = " |cffffd24d[" .. L["Alt"] .. "]|r"
        elseif item.sourceTag == "NOTE" then
            srcBadge = " |cff58a6ff[" .. L["Note"] .. "]|r"
        elseif item.sourceTag == "CHAT" then
            srcBadge = " |cffb589ff[/g]|r"
        elseif item.sourceTag == "SC" and scTag == "" then
            srcBadge = " " .. scIconStr
        end
        local lvlStr = (item.level and item.level > 0) and (" |cff9da7b5[" .. item.level .. "]|r") or ""
        local profTxt = (#pList > 0) and ("  |cff3fb950[" .. table.concat(pList, " / ") .. "]|r") or ""
        row.nameText:SetText(peerStar .. hex .. (item.displayName or "") .. "|r" .. lvlStr .. scTag .. srcBadge .. profTxt)
        local subParts = sublinePartsScratch
        wipe(subParts)
        if item.matchedRecipe and item.matchedRecipe ~= "" then
            subParts[#subParts + 1] = "|cff3fb950[" .. L["Crafts"] .. ": " .. item.matchedRecipe .. "]|r"
        elseif item.recipeCount and item.recipeCount > 0 then
            subParts[#subParts + 1] = "|cff58a6ff" .. L["%d recipes"]:format(item.recipeCount) .. "|r"
        end
        if item.craftNote and item.craftNote ~= "" then subParts[#subParts + 1] = item.craftNote end
        if item.secSummary and item.secSummary ~= "" then subParts[#subParts + 1] = item.secSummary end
        if item.guildNote and item.guildNote ~= "" and item.guildNote ~= item.craftNote then
            subParts[#subParts + 1] = item.guildNote
        end
        if not rightArea and item.isGuild and not item.isAlt then
            subParts[#subParts + 1] = item.online and L["Online"] or L["Offline"]
        end
        if item.updatedAt then
            subParts[#subParts + 1] = Compat.FormatRelativeTime(item.updatedAt, L)
        end
        row.subText:SetText(table.concat(subParts, "  ·  "))
        return
    elseif view == "gchat" then
        SyncPeerRowLayout(row, hasClassIcon, "|cff8b949e" .. Compat.FormatRelativeTime(item.ts, L) .. "|r")
        row.nameText:SetText(peerStar .. hex .. (item.displayName or "") .. "|r  |cff58a6ff[/g LFM]|r")
        row.subText:SetText(item.text or "")
        return
    end

    local areaStr = (isOnline and item.area and item.area ~= "") and ("|cff9da7b5" .. item.area .. "|r")
        or (not isOnline and ("|cff6e7681" .. L["Offline"] .. "|r") or nil)
    local isCompactPeer = (ns.db and ns.db.settings and ns.db.settings.compactListRows == true)
    SyncPeerRowLayout(row, hasClassIcon, areaStr, isCompactPeer)

    local nameCol = isOnline and hex or "|cff8b949e"
    local lvlStr = (item.level and item.level > 0) and (" |cff9da7b5" .. L["Lv %d"]:format(item.level) .. "|r") or ""
    local ver = ""
    if item.version and item.version ~= "" then
        local cmp = (Compat.CompareSemVer and ns.version) and Compat.CompareSemVer(item.version, ns.version) or 0
        if cmp > 0 then
            ver = " |cffffb833[SC v" .. item.version .. "!]|r"
        elseif cmp < 0 then
            ver = " |cff8b949e[SC v" .. item.version .. "]|r"
        else
            ver = " |cff3fb950[SC v" .. item.version .. "]|r"
        end
    elseif item.hasAddon then
        ver = " " .. scIconStr
    else
        ver = scTag
    end
    row.nameText:SetText(peerStar .. nameCol .. (item.displayName or "") .. "|r" .. lvlStr .. ver)

    local sub = sublinePartsScratch
    wipe(sub)
    if item.rankName and item.rankName ~= "" then
        local rColor = (item.rankIndex == 0) and "|cffffd200" or ((item.rankIndex and item.rankIndex <= 2) and "|cff6ec1e4" or "|cff9da7b5")
        sub[#sub + 1] = rColor .. "<" .. item.rankName .. ">|r"
    end
    if item.tag and item.tag ~= "NONE" then
        sub[#sub + 1] = "|cff58a6ff[" .. (TAG_LABELS[item.tag] or item.tag) .. "]|r"
    end
    local pMeta = (item.lookupKey and ns.Store)
        and ((ns.Store.GetResolvedSocialMeta and ns.Store:GetResolvedSocialMeta(item.lookupKey)) or (ns.Store.GetSocialMeta and ns.Store:GetSocialMeta(item.lookupKey)))
        or nil
    local pMain = (pMeta and pMeta.mainName and pMeta.mainName ~= "") and pMeta.mainName
        or (Compat.ExtractMainFromGuildNote and Compat.ExtractMainFromGuildNote(item.note))
        or nil
    if pMain and pMain ~= "" and pMain:lower() ~= tostring(item.displayName or ""):lower() then
        sub[#sub + 1] = "|cff6ec1e4[" .. L["Main"] .. ": " .. pMain .. "]|r"
    end
    local lfgInfo = (item.tag ~= "LFG") and (ns.Clan and ns.Clan.GetActiveLfgForPlayer) and ns.Clan:GetActiveLfgForPlayer(item.lookupKey or item.displayName) or nil
    if lfgInfo then
        sub[#sub + 1] = "|cff3fb950[" .. tostring(lfgInfo.mode or "LFG") .. ": " .. tostring(lfgInfo.activity or L["Group"]) .. "]|r"
    end
    local abs = (item.lookupKey and ns.Clan and ns.Clan.GetMemberAbsence) and ns.Clan:GetMemberAbsence(item.lookupKey) or nil
    if abs then
        sub[#sub + 1] = "|cffffb833[" .. L["Absent"] .. ": " .. tostring(abs.untilDate) .. "]|r"
    end
    if item.note and item.note ~= "" then
        sub[#sub + 1] = item.note
    end
    if #sub == 0 then
        sub[#sub + 1] = isOnline and L["Online"] or Compat.FormatRelativeTime(item.updatedAt, L)
    end
    local peerSub = table.concat(sub, "  ·  ")
    if isCompactPeer and peerSub ~= "" then
        row.nameText:SetText(peerStar .. nameCol .. (item.displayName or "") .. "|r" .. lvlStr .. "  |cff9da7b5·  " .. peerSub .. "|r")
    end
    if row.classIcon then
        row.classIcon:SetDesaturated(not isOnline)
        row.classIcon:SetAlpha(isOnline and 1.0 or 0.48)
    end
    row.nameText:SetAlpha(isOnline and 1.0 or 0.66)
    row.subText:SetAlpha(isOnline and 0.94 or 0.60)
    row.subText:SetText(peerSub)
end

do
    UpdateClanPanel = function()
    if not clanPanel then
        return
    end
    if not clanPanel:IsShown() then
        clanPanel._dirty = true
        return
    end
    clanPanel._dirty = nil
    local prefView = ns.Clan and ns.Clan.ConsumePreferredRightView and ns.Clan:ConsumePreferredRightView()
    if prefView and (prefView == "peers" or prefView == "events" or prefView == "diplomacy" or prefView == "prof" or prefView == "locks" or prefView == "lfg" or prefView == "hierarchy") then
        clanRightView = prefView
    end

    local p = Theme:GetPalette()
    Theme:ApplyBackdrop(clanPanel.sidebar, "inset", p)
    if clanPanel.peersScroll and clanPanel.peersScroll.SetRowHeight then
        local wantPeerH = ((ns.db and ns.db.settings and ns.db.settings.compactListRows == true) and clanRightView == "peers") and 28 or 42
        clanPanel.peersScroll:SetRowHeight(wantPeerH)
    end
    Theme:ApplyBackdrop(clanPanel.mainCard, "inset", p)
    Theme:ApplyBackdrop(clanPanel.bottomBar, "surface", p)
    if clanPanel.guildHeroBar then
        Theme:ApplyBackdrop(clanPanel.guildHeroBar, "header", p)
    end

    local info = ns.Store and ns.Store.guildInfo or {}
    local inGuild = (info.inGuild == true)
    local gameSum = ns.Clan and ns.Clan.GetPlayerGameSummary and ns.Clan:GetPlayerGameSummary() or {}
    if inGuild then
        clanPanel.guildName:SetText(info.name or L["Guild"])
        clanPanel.guildCounts:SetText(string.format("%d / %d %s", info.onlineCount or 0, info.totalCount or 0, L["Online"]:lower()))
        local motd = (info.motd and info.motd ~= "") and info.motd or "-"
        clanPanel.guildMotd:SetText("|cffd8be74" .. L["MOTD"] .. ":|r " .. motd)
    else
        clanPanel.guildName:SetText(L["No guild"])
        local offParts = {}
        if gameSum.level and gameSum.level > 0 then
            table.insert(offParts, "Lv" .. gameSum.level)
        end
        if gameSum.avgItemLevel and gameSum.avgItemLevel > 0 then
            table.insert(offParts, "iLvl " .. gameSum.avgItemLevel)
        end
        if gameSum.zoneName and gameSum.zoneName ~= "" then
            table.insert(offParts, gameSum.zoneName)
        end
        clanPanel.guildCounts:SetText(table.concat(offParts, " · "))
        clanPanel.guildMotd:SetText("")
    end

    local canEditMotd = inGuild and gameSum.canEditMOTD == true
    if clanPanel.motdEditBtn then
        clanPanel.motdEditBtn:SetShown(canEditMotd)
    end
    if clanPanel.guildName and clanPanel.guildHead then
        clanPanel.guildName:ClearAllPoints()
        clanPanel.guildName:SetPoint("LEFT", clanPanel.guildHead, "LEFT", 2, 0)
        if canEditMotd and clanPanel.motdEditBtn then
            clanPanel.guildName:SetPoint("RIGHT", clanPanel.motdEditBtn, "LEFT", -4, 0)
        else
            clanPanel.guildName:SetPoint("RIGHT", clanPanel.guildHead, "RIGHT", -2, 0)
        end
    end

    local syncEnabled = ns.db and ns.db.settings and ns.db.settings.clanSync

    local bucket = ns.Store and ns.Store:GetClanScopeData() or { myTag = "NONE", myNote = "" }
    local tagName = TAG_LABELS[bucket.myTag or "NONE"] or L["No Status"]
    Theme:SetButtonText(clanPanel.statusBtn, L["My Status: %s"]:format(tagName) .. "  v")
    Theme:AutoFitButton(clanPanel.statusBtn, 124, 16, 220)

    local activeNav = clanRightView
    if activeNav == "locks" then activeNav = "prof" end
    if activeNav == "lfg" then activeNav = "peers" end
    for id, b in pairs(clanRightViewButtons) do
        Theme:SetButtonActive(b, inGuild and (activeNav == id), "nav")
        if b.SetEnabled then
            b:SetEnabled(inGuild)
        end
        Theme:StyleButton(b, "nav")
    end
    local canDip, dipAuthSummary = false, L["Guild Leader Only"]
    if inGuild and ns.Clan and ns.Clan.CanManageDiplomacy then
        canDip, dipAuthSummary = ns.Clan:CanManageDiplomacy()
    end
    local isGM = inGuild and ns.Clan and ns.Clan.IsGuildLeader and ns.Clan:IsGuildLeader()
    local canAlly = inGuild and ns.Clan and ns.Clan.CanManageAlliance and ns.Clan:CanManageAlliance()

    for _, gBtn in pairs({
        clanPanel.statusBtn,
        clanPanel.clanInfoBtn,
        clanPanel.guildInviteBtn,
        clanPanel.clanFilterBtn,
        clanPanel.evtFilterBtn,
        clanPanel.evtAllyBtn,
        clanPanel.newEventBtn,
        clanPanel.dipFilterBtn,
        clanPanel.dipAddBtn,
        clanPanel.dipAuthBtn,
        clanPanel.hierDipBtn,
        clanPanel.hierRulesBtn,
        clanPanel.hierAllyBtn,
        clanPanel.profViewBtn,
        clanPanel.profBtn,
        clanPanel.openLfgFinderBtn,
    }) do
        if gBtn and gBtn.SetEnabled then
            local canUse = inGuild
            if gBtn == clanPanel.guildInviteBtn then
                canUse = inGuild and (gameSum.canInviteGuild == true)
                gBtn._scInGuild = inGuild
                gBtn._scCanInvite = canUse
                gBtn._scRankLabel = (info and info.myRankName and info.myRankName ~= "") and info.myRankName or L["Member"]
            elseif gBtn == clanPanel.dipAddBtn then
                canUse = inGuild and (canDip == true)
            elseif gBtn == clanPanel.hierAllyBtn then
                canUse = canAlly == true
            elseif gBtn == clanPanel.profViewBtn or gBtn == clanPanel.profBtn then
                canUse = true
            end
            gBtn:SetEnabled(canUse)
            Theme:StyleButton(gBtn, gBtn._scVariant or "default")
        end
    end
    for _, gBox in ipairs({ clanPanel.peerSearch, clanPanel.profSearch }) do
        if gBox and gBox.SetEnabled then
            local allowBox = inGuild or (gBox == clanPanel.profSearch)
            gBox:SetEnabled(allowBox)
            if not allowBox and gBox.ClearFocus then
                gBox:ClearFocus()
            end
            if gBox.SetAlpha then
                gBox:SetAlpha(allowBox and 1.0 or 0.55)
            end
        end
    end

    if clanPanel.peersToolBar then
        clanPanel.peersToolBar:SetShown(clanRightView == "peers" or clanRightView == "lfg")
        if clanPanel.clanFilterBtn then
            local hasPeerFlt = (clanPeerStatusFilter ~= "all" or clanPeerRankFilter ~= nil or clanPeerClassFilter ~= nil or clanPeerSortBy ~= "level_desc" or clanPeerQuery ~= "")
            Theme:SetIconToggle(clanPanel.clanFilterBtn, hasPeerFlt, { 0.96, 0.76, 0.22 })
        end
    end
    if clanPanel.eventsToolBar then
        clanPanel.eventsToolBar:SetShown(clanRightView == "events")
        if clanPanel.evtFilterBtn then
            Theme:SetIconToggle(clanPanel.evtFilterBtn, clanEventFilter ~= "all", { 0.96, 0.76, 0.22 })
        end
        if clanPanel.evtAllyBtn and ns.Clan then
            local mutAllies = (ns.Clan.GetMutuallyAuthorizedAlliedGuilds and ns.Clan:GetMutuallyAuthorizedAlliedGuilds()) or {}
            Theme:SetIconToggle(clanPanel.evtAllyBtn, #mutAllies > 0, { 0.28, 0.88, 0.45 })
        end
    end
    if clanPanel.profToolBar then
        local isProfMode = (clanRightView == "prof")
        local isLocksMode = (clanRightView == "locks")
        clanPanel.profToolBar:SetShown(isProfMode or isLocksMode)
        if clanPanel.profViewBtn then
            local pvTex = isLocksMode and "Interface\\Icons\\INV_Misc_PocketWatch_01" or "Interface\\Icons\\Trade_BlackSmithing"
            Theme:ConfigureIconButton(clanPanel.profViewBtn, 24, 22, pvTex, {
                size = 14,
                toggle = true,
                active = isLocksMode,
                activeColor = { 0.96, 0.76, 0.22 },
                tooltipFn = function()
                    return (clanRightView == "locks" and L["Locks"] or L["Professions"]), L["Switch between 'Locks' and 'Professions' in the selector or click 'Refresh' to request updated raid lockout timers from the server."]
                end,
            })
        end
        if clanPanel.profFilterBtn then
            clanPanel.profFilterBtn:SetShown(isProfMode)
            if isProfMode then
                Theme:SetIconToggle(clanPanel.profFilterBtn, clanProfFilter ~= "ALL", { 0.96, 0.76, 0.22 })
            end
        end
        if clanPanel.profSourceBtn then
            clanPanel.profSourceBtn:SetShown(isProfMode)
            if isProfMode then
                Theme:SetIconToggle(clanPanel.profSourceBtn, clanProfSourceFilter ~= "ALL", { 0.35, 0.78, 1.0 })
            end
        end
        if clanPanel.profBtn then
            clanPanel.profBtn:SetShown(isProfMode)
            if clanPanel.profBtn._pairedHelp then
                clanPanel.profBtn._pairedHelp:SetShown(isProfMode)
            end
        end
        if clanPanel.profAskGuildBtn then
            clanPanel.profAskGuildBtn:SetShown(isProfMode)
            if clanPanel.profAskGuildBtn._pairedHelp then
                clanPanel.profAskGuildBtn._pairedHelp:SetShown(isProfMode)
            end
        end
        if clanPanel.locksRefreshBtn then
            clanPanel.locksRefreshBtn:SetShown(isLocksMode)
            if clanPanel.locksRefreshBtn._pairedHelp then
                clanPanel.locksRefreshBtn._pairedHelp:SetShown(isLocksMode)
            end
        end
    end
    if clanPanel.dipToolBar then
        clanPanel.dipToolBar:SetShown(clanRightView == "diplomacy")
        if clanPanel.dipFilterBtn then
            local dipCol = clanRightViewFilterDip == "ENEMY" and { 0.96, 0.35, 0.35 } or { 0.28, 0.88, 0.45 }
            Theme:SetIconToggle(clanPanel.dipFilterBtn, clanRightViewFilterDip ~= "all", dipCol)
        end
        if clanPanel.dipAuthBtn then
            Theme:SetButtonText(clanPanel.dipAuthBtn, L["Diplomacy: %s"]:format(dipAuthSummary))
            Theme:SetButtonActive(clanPanel.dipAuthBtn, isGM == true, isGM and "default" or "default")
            Theme:AutoFitButton(clanPanel.dipAuthBtn, 120, 14, 235)
        end
    end
    if clanPanel.hierToolBar then
        clanPanel.hierToolBar:SetShown(clanRightView == "hierarchy")
        if clanPanel.hierDipBtn then
            Theme:SetButtonText(clanPanel.hierDipBtn, L["Diplomacy: %s"]:format(dipAuthSummary) .. "  v")
            Theme:AutoFitButton(clanPanel.hierDipBtn, 130, 14, 240)
        end
        if clanPanel.hierRulesBtn then
            Theme:SetButtonText(clanPanel.hierRulesBtn, L["Hierarchy Rules"] .. "  v")
            Theme:AutoFitButton(clanPanel.hierRulesBtn, 110, 14, 190)
        end
        if clanPanel.hierAllyBtn then
            Theme:AutoFitButton(clanPanel.hierAllyBtn, 72, 12, 130)
        end
    end

    if clanPanel.radarBtn then
        local eCount, aCount, sCount, totalCount = 0, 0, 0, 0
        if ns.Spotter and ns.Spotter.GetCounts then
            eCount, aCount, sCount, totalCount = ns.Spotter:GetCounts()
        end
        local spotEnabled = (ns.db and ns.db.settings and ns.db.settings.spotterEnabled == true) or (totalCount > 0)
        clanPanel.radarBtn:SetShown(spotEnabled)
        if clanPanel.radarHelp then
            clanPanel.radarHelp:SetShown(spotEnabled)
        end
        if spotEnabled then
            if totalCount > 0 then
                Theme:SetButtonText(clanPanel.radarBtn, string.format("%s (%d)", L["Target Radar"], totalCount))
                Theme:SetButtonActive(clanPanel.radarBtn, true, eCount > 0 and "danger" or "primary")
            else
                Theme:SetButtonText(clanPanel.radarBtn, L["Target Radar"])
                Theme:SetButtonActive(clanPanel.radarBtn, false, "default")
            end
            Theme:AutoFitButton(clanPanel.radarBtn, 96, 20, 165)
        end
    end

    local peers = {}
    local scUsers, onlineTotal, totalPeersCount = 0, 0, 0
    local classCounts = {}
    if inGuild and ns.Clan then
        if ns.Clan.GetGuildRosterQuickStats then
            scUsers, onlineTotal, totalPeersCount = ns.Clan:GetGuildRosterQuickStats(classCounts)
        end
        if clanRightView == "peers" or clanRightView == "lfg" then
            local peerOpts = {
                statusFilter = clanPeerStatusFilter,
                rankFilter = clanPeerRankFilter,
                classFilter = clanPeerClassFilter,
                sortBy = clanPeerSortBy,
            }
            if clanPeerQuery ~= "" or clanPeerStatusFilter ~= "all" or clanPeerRankFilter ~= nil or clanPeerClassFilter ~= nil or clanPeerSortBy ~= "level_desc" then
                peers = ns.Clan:GetMergedGuildMembers(clanPeerQuery, peerOpts)
            else
                peers = ns.Clan:GetMergedGuildMembers("", { sortBy = "level_desc" })
            end
        else
            onlineTotal = info.onlineCount or onlineTotal
        end
    end
    if clanPanel.clanFilterBtn then
        local activeFilters = 0
        if clanPeerStatusFilter ~= "all" then activeFilters = activeFilters + 1 end
        if clanPeerRankFilter ~= nil then activeFilters = activeFilters + 1 end
        if clanPeerClassFilter ~= nil then activeFilters = activeFilters + 1 end
        if clanPeerSortBy ~= "level_desc" then activeFilters = activeFilters + 1 end
        clanPanel.clanFilterBtn._scActiveFilterCount = activeFilters
        Theme:SetIconToggle(clanPanel.clanFilterBtn, activeFilters > 0, { 0.96, 0.76, 0.22 })
    end

    if clanPanel.heroSummaryLbl and clanPanel.heroDetailLbl then
        if inGuild then
            local openEvents = ns.Clan and ns.Clan.GetEventsList and #(ns.Clan:GetEventsList("open")) or 0
            local calEvts = ns.Clan and ns.Clan.GetUpcomingCalendarEvents and #(ns.Clan:GetUpcomingCalendarEvents()) or 0
            local totalEvtHero = openEvents + calEvts
            local allies = ns.Clan and ns.Clan.GetDiplomacyList and #(ns.Clan:GetDiplomacyList("ALLY")) or 0
            local enemies = ns.Clan and ns.Clan.GetDiplomacyList and #(ns.Clan:GetDiplomacyList("ENEMY")) or 0
            local allyCfg = ns.Clan and ns.Clan.GetAllianceConfig and ns.Clan:GetAllianceConfig() or nil

            local sumParts = {
                ("|cff3fb950%s: %d/%d|r"):format(L["Online"], info.onlineCount or onlineTotal, info.totalCount or totalPeersCount),
                ("|cff58a6ffSC: %d|r"):format(scUsers),
                ("|cffffd200%s: %d|r"):format(L["Events"], totalEvtHero),
                ("|cff40d973%d %s|r / |cfff54747%d %s|r"):format(allies, L["ALLY"]:lower(), enemies, L["ENEMY"]:lower()),
            }
            if allyCfg and allyCfg.enabled and allyCfg.name and allyCfg.name ~= "" then
                table.insert(sumParts, ("|cff6ec1e4[%s: %s]|r"):format(L["Alliance"], allyCfg.name))
            end
            local remoteVer = ns.Clan and ns.Clan.latestRemoteVersion
            if remoteVer and Compat.CompareSemVer(remoteVer, ns.version or "0.0.0") > 0 then
                table.insert(sumParts, ("|cffffb833[%s v%s]|r"):format(L["Update Available"], remoteVer))
            end
            clanPanel.heroSummaryLbl:SetText(table.concat(sumParts, "  ·  "))
            if clanPanel.heroRankLbl then
                local selfRank = ns.Clan and ns.Clan.GetSelfGuildRank and ns.Clan:GetSelfGuildRank()
                if selfRank and selfRank.rankName and selfRank.rankName ~= "" then
                    local rCol = selfRank.isGuildLeader and "|cffffd200" or (selfRank.isOfficer and "|cff6ec1e4" or "|cff9da7b5")
                    clanPanel.heroRankLbl:SetText(rCol .. selfRank.rankName .. "|r")
                else
                    clanPanel.heroRankLbl:SetText("")
                end
            end

            local clsParts = {}
            for cf, cnt in pairs(classCounts) do
                local locClass = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cf]) or cf
                local cHex = Compat.ClassHex(cf)
                table.insert(clsParts, {
                    n = cnt,
                    fullTxt = ("%s%s (%d)|r"):format(cHex, locClass, cnt),
                    shortTxt = ("%s%s (%d)|r"):format(cHex, ShortClassLabel(locClass), cnt),
                })
            end
            table.sort(clsParts, function(a, b) return a.n > b.n end)
            clanPanel._onlineClassSummary = clsParts

            local cInfo = ns.Clan and ns.Clan.GetClanInfo and ns.Clan:GetClanInfo() or {}
            local detailParts = {}
            if cInfo.summary and cInfo.summary ~= "" then
                table.insert(detailParts, "|cffffd200" .. L["Focus"] .. ":|r " .. cInfo.summary)
            end
            if cInfo.schedule and cInfo.schedule ~= "" then
                table.insert(detailParts, cInfo.schedule)
            end
            if #detailParts == 0 then
                local fullCls, shortCls = {}, {}
                for i = 1, #clsParts do
                    fullCls[#fullCls + 1] = clsParts[i].fullTxt
                    shortCls[#shortCls + 1] = clsParts[i].shortTxt
                end
                if #fullCls > 0 then
                    clanPanel.heroDetailLbl:SetText(table.concat(fullCls, " · "))
                    local heroBar = clanPanel.heroDetailLbl:GetParent()
                    local availW = (heroBar and heroBar:GetWidth() or 0) - 18
                    if availW > 80 and (clanPanel.heroDetailLbl:GetStringWidth() or 0) > availW then
                        clanPanel.heroDetailLbl:SetText(table.concat(shortCls, " · "))
                    end
                else
                    clanPanel.heroDetailLbl:SetText("|cff8b949e" .. L["Click 'Guild Info' to configure shared guild focus and schedule."] .. "|r")
                end
            else
                clanPanel.heroDetailLbl:SetText(table.concat(detailParts, "  ·  "))
            end
        else
            clanPanel._onlineClassSummary = nil
            clanPanel.heroSummaryLbl:SetText("|cff8b949e" .. L["No guild"] .. "|r")
            clanPanel.heroDetailLbl:SetText("|cff8b949e" .. L["You are not in a guild. Guild features are disabled until you join a guild."] .. "|r")
        end
    end

    local locked = ns.Clan and ns.Clan:IsMessagingLocked()
    local modeTag = syncEnabled and (locked and L["Locked"] or "SCentral1") or L["Local only"]
    clanPanel.syncStatus:SetText(string.format("[%s · %d]", modeTag, totalPeersCount))
    clanPanel.syncStatus:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])

    if ReflowClanPanel then
        ReflowClanPanel()
    end

    local isEvents = inGuild and (clanRightView == "events")
    clanPanel.eventsScroll.container:SetShown(isEvents)
    clanPanel.peersScroll.container:SetShown(not isEvents)

    if not inGuild and clanRightView ~= "prof" and clanRightView ~= "locks" then
        clanPanel.peersScroll:SetData({}, L["You are not in a guild. Guild features are disabled until you join a guild."], false)
        return
    end

    if isEvents then
        if clanEventFilter == "calendar" then
            local calRows = {}
            if ns.Clan then
                ns.Clan:RefreshGameCalendar(false)
                calRows = ns.Clan:GetCombinedEventsList("calendar") or {}
            end
            clanPanel.eventsScroll:SetData(calRows, L["No upcoming guild calendar events found in the next 14 days."], false)
        else
            local events = ns.Clan and (ns.Clan.GetCombinedEventsList and ns.Clan:GetCombinedEventsList(clanEventFilter) or ns.Clan:GetEventsList(clanEventFilter)) or {}
            clanPanel.eventsScroll:SetData(events, L["No Clan event calls yet. Click '+ Event Call' to create one!"], false)
        end
    elseif clanRightView == "lfg" then
        local lfgList = (ns.Clan and ns.Clan:GetClanLFGList(clanLfgQuery, clanLfgDungeonsOnly, clanLfgSourceFilter)) or {}
        clanPanel.peersScroll:SetData(lfgList, L["No active Clan LFG posts yet. Click '+ Clan LFG' or 'Share Queue/Key' to post!"], false)
    elseif clanRightView == "prof" then
        local profList = {}
        if ns.Clan and ns.Clan.GetProfessionsList then
            local rawList, counts = ns.Clan:GetProfessionsList(clanProfQuery, clanProfFilter, clanProfSourceFilter)
            clanProfCounts = counts or {}
            profList = rawList or {}
        end
        clanPanel.peersScroll:SetData(profList, L["No matching crafters found. Adjust filters or click '+ Prof' to set your own!"], false)
    elseif clanRightView == "locks" then
        local lockRows = {}
        local qLock = (type(clanProfQuery) == "string" and clanProfQuery ~= "") and clanProfQuery:lower() or nil
        local function LockMatchesQuery(...)
            if not qLock then return true end
            for i = 1, select("#", ...) do
                local v = select(i, ...)
                if type(v) == "string" and v:lower():find(qLock, 1, true) then
                    return true
                end
            end
            return false
        end
        if ns.Clan then
            if ns.Clan.RequestLockoutsRefresh then
                ns.Clan:RequestLockoutsRefresh(false)
            end
            local instStat = (ns.Group and ns.Group.GetHourlyInstanceStatus) and ns.Group:GetHourlyInstanceStatus() or nil
            if instStat then
                local usedH = instStat.used or 0
                local maxH = instStat.max or 5
                local title = "|cffffd200[" .. L["Instance Limit (1h): %d/%d"]:format(usedH, maxH) .. "]|r"
                local detail
                if usedH >= maxH and (instStat.nextSlotSecs or 0) > 0 and ns.Clan.FormatResetDuration then
                    detail = L["Next slot frees in %s"]:format(ns.Clan:FormatResetDuration(instStat.nextSlotSecs))
                else
                    detail = L["Available now (max 5 dungeons per hour)"]
                end
                if instStat.lastRun and instStat.lastRun.name and instStat.lastRun.name ~= "" then
                    detail = detail .. "  ·  " .. instStat.lastRun.name
                end
                if LockMatchesQuery(title, detail) then
                    table.insert(lockRows, {
                        _clanView = "locks",
                        _isInstanceCapRow = true,
                        statusColor = (usedH >= maxH) and "offline" or ((usedH >= maxH - 1) and "nearby" or "online"),
                        title = title,
                        detail = detail,
                    })
                end
            end
            if gameSum.premadeTitle and gameSum.premadeTitle ~= "" then
                local title = "|cff58a6ff[" .. L["Premade Group"] .. "]|r " .. gameSum.premadeTitle
                local detail = string.format(L["Applicants: %d"], gameSum.premadeApplicants or 0)
                if LockMatchesQuery(gameSum.premadeTitle, detail) then
                    table.insert(lockRows, {
                        _clanView = "locks",
                        statusColor = "online",
                        title = title,
                        detail = detail,
                    })
                end
            elseif gameSum.lfgQueued then
                local title = "|cff3fb950[" .. L["Dungeon Finder Queue"] .. "]|r " .. (gameSum.role or "DPS")
                local detail = L["Currently queued in official Group Finder"]
                if LockMatchesQuery(title, detail) then
                    table.insert(lockRows, {
                        _clanView = "locks",
                        statusColor = "online",
                        title = title,
                        detail = detail,
                    })
                end
            end
            local allLocks = (ns.Clan.GetAllLockouts and ns.Clan:GetAllLockouts()) or ns.Clan:GetSavedLockouts()
            for _, lk in ipairs(allLocks) do
                local resetTxt = (ns.Clan.FormatResetDuration and ns.Clan:FormatResetDuration(lk.reset or 0))
                    or (math.max(1, math.floor((lk.reset or 0) / 3600)) .. "h")
                local statusStr = lk.locked and L["Locked"] or L["Unlocked"]
                if lk.extended then statusStr = statusStr .. " (" .. L["Extended"] .. ")" end
                local cHex = Compat.ClassHex(lk.classFile)
                local whoBadge = lk.isAlt
                    and ("|cffffd24d[" .. L["Alt"] .. ":|r " .. cHex .. (lk.charName or "?") .. "|r|cffffd24d]|r ")
                    or (cHex .. (lk.charName or "") .. "|r  ")
                local typeBadge = lk.isRaid and ("|cffff8040[" .. L["Raid"] .. "]|r ") or ""
                local diffStr = (lk.difficultyName and lk.difficultyName ~= "") and (" |cff9da7b5[" .. lk.difficultyName .. "]|r") or ""
                local bossPart = ((lk.numEncounters or 0) > 0) and string.format("  ·  %d/%d %s", lk.encounterProgress or 0, lk.numEncounters or 0, L["Bosses"]) or ""
                local title = whoBadge .. typeBadge .. (lk.name or "?") .. diffStr
                local detail = string.format("%s%s  ·  %s %s", statusStr, bossPart, L["Resets in"], resetTxt)
                if LockMatchesQuery(lk.name, lk.charName, lk.difficultyName, statusStr) then
                    table.insert(lockRows, {
                        _clanView = "locks",
                        statusColor = lk.isAlt and "nearby" or (lk.locked and "offline" or "online"),
                        instanceName = lk.name,
                        charName = lk.charName,
                        title = title,
                        detail = detail,
                    })
                end
            end
        end
        clanPanel.peersScroll:SetData(lockRows, L["No active dungeon/raid lockouts or queues found."], false)
    elseif clanRightView == "diplomacy" then
        local dipRows = (ns.Clan and ns.Clan:GetDiplomacyList(clanRightViewFilterDip)) or {}
        clanPanel.peersScroll:SetData(dipRows, L["No guild diplomacy entries yet. Click '+ Add Guild' to tag Allies or Enemies cleanly."], false)
    elseif clanRightView == "hierarchy" then
        local rankRows = {}
        local rawRanks = (ns.Clan and ns.Clan.GetGuildRanks and ns.Clan:GetGuildRanks()) or {}
        local pol = (ns.Clan and ns.Clan.GetGuildHierarchyPolicy and ns.Clan:GetGuildHierarchyPolicy()) or {}
        local selfRank = (ns.Clan and ns.Clan.GetSelfGuildRank and ns.Clan:GetSelfGuildRank()) or {}
        local allyCfg = (ns.Clan and ns.Clan.GetAllianceConfig and ns.Clan:GetAllianceConfig()) or {}

        local function RankMatchesRule(rIdx, rName, mode, maxR)
            if rIdx == 0 then return true end
            if mode == "ALL" then return true end
            if mode == "RANK" then return rIdx <= (tonumber(maxR) or 0) end
            if mode == "OFFICERS" then
                if selfRank.rankIndex == rIdx then
                    return selfRank.isOfficer == true
                end
                local ln = type(rName) == "string" and rName:lower() or ""
                if ln:find("officer", 1, true) or ln:find("oficial", 1, true) or ln:find("leader", 1, true) or ln:find("lider", 1, true) then
                    return true
                end
                return rIdx <= 1
            end
            return false
        end

        for _, rk in ipairs(rawRanks) do
            local rIdx = rk.rankIndex or 0
            local hasDip = RankMatchesRule(rIdx, rk.name, pol.diplomacyMode, pol.diplomacyMaxRank)
            local hasInfo = RankMatchesRule(rIdx, rk.name, pol.infoMode, pol.infoMaxRank)
            local hasEvt = RankMatchesRule(rIdx, rk.name, pol.eventModMode, pol.eventModMaxRank)
            local hasAlly = (allyCfg.accessMode == "ALL") or (pol.allianceMinRank and pol.allianceMinRank >= 0 and rIdx <= pol.allianceMinRank) or (rIdx == 0)

            local badges = {}
            if rIdx == 0 then badges[#badges + 1] = "|cffffd200[" .. L["LEADER"] .. "]|r" end
            if hasDip then badges[#badges + 1] = "|cfff54747[" .. L["Diplomacy"] .. "]|r" end
            if hasInfo then badges[#badges + 1] = "|cff58a6ff[" .. L["Info"] .. "]|r" end
            if hasEvt then badges[#badges + 1] = "|cff40d973[" .. L["Events"] .. "]|r" end
            if hasAlly then badges[#badges + 1] = "|cff6ec1e4[" .. L["Alliance"] .. "]|r" end

            local isMeRank = (selfRank.rankIndex ~= nil and selfRank.rankIndex == rIdx)
            local nativeList = {}
            if isMeRank then
                if selfRank.canEditMOTD then nativeList[#nativeList + 1] = L["Edit MOTD"] end
                if selfRank.canEditGuildInfo then nativeList[#nativeList + 1] = L["Can Edit Guild Info"] end
                if selfRank.canEditOfficerNote then nativeList[#nativeList + 1] = L["Officer Notes"] end
                if selfRank.canInvite then nativeList[#nativeList + 1] = L["Can Invite"] end
                if selfRank.canPromote then nativeList[#nativeList + 1] = L["Can Promote"] end
                if selfRank.canDemote then nativeList[#nativeList + 1] = L["Can Demote"] end
                if selfRank.canEditCalendar then nativeList[#nativeList + 1] = L["Calendar Events"] end
            end

            local permSummary = (#badges > 0) and table.concat(badges, " ") or ""
            local nativeSummary = (#nativeList > 0) and table.concat(nativeList, " · ") or ""
            local subSummary = (nativeSummary ~= "") and (L["Native Rank"] .. ": " .. nativeSummary)
                or ((rIdx == 0) and L["Guild Leader"] or ((hasDip or hasInfo or hasEvt) and L["Leader & Game Officers"] or L["No permissions listed (Member rank)"]))

            table.insert(rankRows, {
                _clanView = "hierarchy",
                rankIndex = rIdx,
                rankOrder = rk.rankOrder,
                name = rk.name,
                totalMembers = rk.totalMembers or 0,
                onlineMembers = rk.onlineMembers or 0,
                isMyRank = isMeRank,
                hasAddonAuthority = (rIdx == 0) or hasDip or hasInfo or hasEvt,
                badgeText = (permSummary ~= "") and ("  " .. permSummary) or "",
                permSummary = permSummary,
                nativeSummary = nativeSummary,
                subSummary = subSummary,
            })
        end
        clanPanel.peersScroll:SetData(rankRows, L["Guild roster not loaded yet."], false)
    else
        clanPanel.peersScroll:SetData(peers, L["No online Guild members seen yet. Open Guild Roster or enable Clan Sync."], false)
    end
    end
end

local function SyncSubtreeChildren(visitFn, baseLvl, depth, ...)
    local n = select("#", ...)
    for i = 1, n do
        local child = select(i, ...)
        if child
            and not (child.IsForbidden and child:IsForbidden())
            and not child._scSkipLayerSync
            and not child._scIsInternalBtnLayer
            and not child._scIsInputBackdrop
        then
            if child.SetFrameLevel then
                local desired = math.min(9980, baseLvl + (child._scLevelOffset or 1))
                if (child:GetFrameLevel() or 0) ~= desired then
                    child:SetFrameLevel(desired)
                end
            end
            visitFn(child, depth)
        end
    end
end

local function SyncSubtreeButtonLayers(root, depth)
    depth = depth or 12
    if not root or depth <= 0
        or (root.IsForbidden and root:IsForbidden())
        or root._scSkipLayerSync
        or root._scIsInternalBtnLayer
        or root._scIsInputBackdrop
    then
        return
    end
    local baseLvl = math.max(1, math.min(9980, (root.GetFrameLevel and root:GetFrameLevel()) or 1))
    if (root._textLayer or root._blizzTabFrame) and Theme and Theme.SyncButtonLayers then
        Theme:SyncButtonLayers(root)
    end
    if root.clearBtn and root.clearBtn.SetFrameLevel then
        root.clearBtn._scLevelOffset = 4
        root.clearBtn:SetFrameLevel(math.min(9985, baseLvl + 4))
    end
    if root._scClearBtn and root._scClearBtn.SetFrameLevel then
        root._scClearBtn._scLevelOffset = 4
        root._scClearBtn:SetFrameLevel(math.min(9985, baseLvl + 4))
    end
    if root._scBg and root._scBg.SetFrameLevel then
        root._scBg:SetFrameLevel(math.max(0, baseLvl - 1))
    end
    if depth > 1 and root.GetChildren then
        SyncSubtreeChildren(SyncSubtreeButtonLayers, baseLvl, depth - 1, root:GetChildren())
    end
end

function UI:SyncFrameSectionLayers(targetContainer)
    if targetContainer then
        if targetContainer.header then
            SyncSubtreeButtonLayers(targetContainer.header, 12)
        end
        if targetContainer.content then
            SyncSubtreeButtonLayers(targetContainer.content, 12)
        end
        if not targetContainer.header and not targetContainer.content then
            SyncSubtreeButtonLayers(targetContainer, 12)
        end
        return
    end
    if not frame then
        return
    end
    local sections = { frame.header, frame.tabBar, frame.filterBar, frame.socialChipsBar, frame.watchBar, frame.content }
    for i = 1, #sections do
        local sec = sections[i]
        if sec and (not sec.IsShown or sec:IsShown()) then
            SyncSubtreeButtonLayers(sec, 12)
        end
    end
end

local function SyncClanCtxToolbarLayout(mainCard, guildHeroBar, ctxBar, activeBar)
    if not (mainCard and guildHeroBar and ctxBar) then
        return
    end
    local cardLvl = (mainCard.GetFrameLevel and mainCard:GetFrameLevel()) or 2
    ctxBar._scLevelOffset = 4
    if ctxBar._scAnchorHero ~= guildHeroBar then
        ctxBar._scAnchorHero = guildHeroBar
        ctxBar:ClearAllPoints()
        ctxBar:SetPoint("TOPLEFT", guildHeroBar, "BOTTOMLEFT", 2, -6)
        ctxBar:SetPoint("TOPRIGHT", guildHeroBar, "BOTTOMRIGHT", -2, -6)
    end
    if not ctxBar:IsShown() then
        ctxBar:Show()
    end
    if (ctxBar:GetFrameLevel() or 0) ~= (cardLvl + 4) then
        ctxBar:SetFrameLevel(cardLvl + 4)
    end
    if activeBar then
        activeBar._scLevelOffset = 2
        if activeBar._scAttachedCtx ~= ctxBar then
            activeBar._scAttachedCtx = ctxBar
            activeBar:ClearAllPoints()
            activeBar:SetAllPoints(ctxBar)
        end
        if (activeBar:GetFrameLevel() or 0) ~= (cardLvl + 6) then
            activeBar:SetFrameLevel(cardLvl + 6)
        end
        if not activeBar:IsShown() then
            activeBar:Show()
        end
        SyncSubtreeButtonLayers(activeBar, 6)
    end
end

local function CreateClanPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    -- 1. Top Native Stone Header Strip (aligns inside CommunitiesFrame _embeddedHeaderStone)
    local topHeader = CreateFrame("Frame", nil, panel)
    topHeader:SetHeight(26)

    local statusBtn = Theme:CreateButton(topHeader, 152, 22, L["My Status"] .. "  v", "default")
    Theme:AutoFitButton(statusBtn, 124, 16, 220)
    statusBtn:SetPoint("LEFT", 0, 0)
    themeTargets[#themeTargets + 1] = { btn = statusBtn, variant = "default" }
    statusBtn:SetScript("OnClick", function(self)
        if not ns.Clan then return end
        local bucket = ns.Store and ns.Store:GetClanScopeData() or { myTag = "NONE", myNote = "" }
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                local addChoice = root.CreateRadio or root.CreateCheckbox
                root:CreateTitle(L["Select Status Tag"])
                for _, item in ipairs(ns.Clan.STATUS_TAGS) do
                    local tagId = item.id
                    addChoice(root, TAG_LABELS[tagId] or tagId, function()
                        return bucket.myTag == tagId
                    end, function()
                        ns.Clan:SetMyStatus(tagId, bucket.myNote or "")
                    end)
                end
                root:CreateDivider()
                root:CreateButton(L["Clear Note / Custom Note"], function()
                    OpenClanNoteModal(bucket.myTag ~= "NONE" and bucket.myTag or "LFG", bucket.myNote or "")
                end)
                root:CreateButton(L["Guild Absence / Vacation..."], function()
                    UI:OpenClanAbsenceModal()
                end)
                root:CreateDivider()
                root:CreateCheckbox(L["Clan Sync"], function()
                    return ns.db and ns.db.settings and ns.db.settings.clanSync == true
                end, function()
                    if ns.db and ns.db.settings then
                        ns.db.settings.clanSync = not ns.db.settings.clanSync
                        UpdateClanPanel()
                    end
                end)
                root:CreateButton(L["Sync"], function()
                    if ns.Clan then
                        ns.Clan:RequestClanSync()
                        if ns.Clan.RequestAlliedEventsSync then
                            ns.Clan:RequestAlliedEventsSync()
                        end
                        if ns.Clan.RequestIntelSync and C_Timer and C_Timer.After then
                            C_Timer.After(5.2, function()
                                if ns.Clan and ns.db and ns.db.settings and ns.db.settings.clanSync
                                    and (not ns.Clan.isStoppedThisSession)
                                    and not (ns.Clan.IsMessagingLocked and ns.Clan:IsMessagingLocked())
                                then
                                    ns.Clan:RequestIntelSync()
                                end
                            end)
                        end
                        ns.Clan:RefreshGameCalendar(true)
                    end
                end)
                if ns.Clan and ns.Clan.CanManageAlliance and ns.Clan:CanManageAlliance() then
                    root:CreateButton(L["Alliance"], OpenAllianceManagementModal)
                end
            end)
        else
            OpenClanNoteModal(bucket.myTag, bucket.myNote)
        end
    end)

    local statusHelp = AddHelp(
        topHeader,
        statusBtn,
        L["Help: Clan Status Tag"],
        L["Broadcasts your current activity tag (LFG, M+, Raid, PvP, etc.), optional short note, and Clan Sync toggle safely to guildmates using SocialCentral."],
        L["Click 'My Status', pick an activity tag, toggle Clan Sync (SCentral1), or trigger a manual Sync."]
    )

    local guildCounts = topHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    guildCounts:SetJustifyH("RIGHT")
    guildCounts:SetWordWrap(false)
    guildCounts:SetPoint("RIGHT", -2, 0)
    guildCounts:SetPoint("LEFT", statusHelp, "RIGHT", 8, 0)

    -- 2. Bottom Native Utility Bar (MOTD left, 2 compact action buttons right)
    local bottomBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    bottomBar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 2, 2)
    bottomBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)
    bottomBar:SetHeight(28)

    local radarBtn = Theme:CreateButton(bottomBar, 110, 20, L["Target Radar"], "default")
    Theme:AutoFitButton(radarBtn, 96, 20, 165)
    radarBtn:SetScript("OnClick", function()
        if ns.SpotterHUD and ns.SpotterHUD.Toggle then
            ns.SpotterHUD:Toggle()
        end
    end)
    radarBtn:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["Target Radar"], 1, 1, 1)
            local eCount, aCount, sCount, totalCount = 0, 0, 0, 0
            if ns.Spotter and ns.Spotter.GetCounts then
                eCount, aCount, sCount, totalCount = ns.Spotter:GetCounts()
            end
            if totalCount > 0 then
                GameTooltip:AddLine(string.format("|cfff54747%s: %d|r  |cff40d973%s: %d|r  |cfffacc3d%s: %d|r",
                    L["ENEMY"], eCount, L["ALLY"], aCount, L["Clan"], sCount), 1, 1, 1)
            else
                GameTooltip:AddLine(L["No targets currently detected."], 0.7, 0.7, 0.7)
            end
            GameTooltip:AddLine(L["Click this button or type '/sc radar' to show or hide the floating radar."], 0.6, 0.8, 1.0, true)
            GameTooltip:Show()
        end
    end)
    radarBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    themeTargets[#themeTargets + 1] = { btn = radarBtn, variant = "default" }

    local radarHelp = AddHelp(
        bottomBar,
        radarBtn,
        L["Help: Screen Spotter & Target Radar"],
        L["Detects Enemy, Ally, and Same-Clan players appearing on your screen and opens a floating clickable Target Selection HUD."],
        L["Tag Ally/Enemy guilds in the Diplomacy view, then click players on the Target Radar to target them (Blizzard-legal secure click)."]
    )

    local clanInfoBtn = Theme:CreateButton(bottomBar, 102, 20, L["Clan Info"], "default")
    Theme:AutoFitButton(clanInfoBtn, 90, 20, 168)
    clanInfoBtn:SetScript("OnClick", function()
        OpenClanInfoModal()
    end)
    themeTargets[#themeTargets + 1] = { btn = clanInfoBtn, variant = "default" }
    local clanInfoHelp = AddHelp(
        bottomBar,
        clanInfoBtn,
        L["Help: Clan Management Info"],
        L["Shared guild focus, schedule, rules, and recruitment contacts synced securely ONLY inside your active guild."],
        L["Click 'Clan Info' to view or edit your guild's shared management card and configure whether Officers or All Members can edit it."]
    )

    local syncStatus = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    syncStatus:SetPoint("LEFT", bottomBar, "LEFT", 8, 0)
    syncStatus:SetJustifyH("LEFT")
    syncStatus:SetWordWrap(false)

    local guildMotd = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    guildMotd:SetPoint("LEFT", syncStatus, "RIGHT", 8, 0)
    guildMotd:SetJustifyH("LEFT")
    guildMotd:SetWordWrap(false)

    local motdHover = CreateFrame("Frame", nil, bottomBar)
    motdHover:SetPoint("TOPLEFT", guildMotd, "TOPLEFT", 0, 2)
    motdHover:SetPoint("BOTTOMRIGHT", guildMotd, "BOTTOMRIGHT", 0, -2)
    motdHover:EnableMouse(true)
    motdHover:SetScript("OnEnter", function(selfFrm)
        local txt = guildMotd:GetText()
        if GameTooltip and txt and txt ~= "" then
            GameTooltip:SetOwner(selfFrm, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(txt, 1, 0.92, 0.65, true)
            GameTooltip:Show()
        end
    end)
    motdHover:SetScript("OnLeave", function(selfFrm)
        if GameTooltip and GameTooltip:IsOwned(selfFrm) then GameTooltip:Hide() end
    end)

    -- 3. Left Native Communities Sidebar
    local sidebar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -32)
    sidebar:SetPoint("BOTTOMLEFT", bottomBar, "TOPLEFT", 0, 4)
    sidebar:SetWidth(174)

    local guildHead = CreateFrame("Frame", nil, sidebar)
    guildHead:SetPoint("TOPLEFT", 8, -8)
    guildHead:SetPoint("TOPRIGHT", -8, -8)
    guildHead:SetHeight(24)

    local guildName = guildHead:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guildName:SetPoint("LEFT", 2, 0)
    guildName:SetPoint("RIGHT", guildHead, "RIGHT", -2, 0)
    guildName:SetJustifyH("LEFT")
    guildName:SetWordWrap(false)

    local motdEditBtn = Theme:CreateButton(guildHead, 22, 18, "", "default")
    Theme:ConfigureIconButton(motdEditBtn, 22, 18, "Interface\\Icons\\INV_Misc_Note_01", {
        size = 13,
        color = { 1.0, 0.85, 0.35 },
        title = L["Edit MOTD"],
    })
    motdEditBtn:SetPoint("RIGHT", 0, 0)
    motdEditBtn:SetScript("OnClick", OpenMotdModal)
    themeTargets[#themeTargets + 1] = { btn = motdEditBtn, variant = "default" }
    motdEditBtn:Hide()

    local sidebarDiv = sidebar:CreateTexture(nil, "ARTWORK")
    sidebarDiv:SetHeight(1)
    sidebarDiv:SetPoint("TOPLEFT", guildHead, "BOTTOMLEFT", 0, -4)
    sidebarDiv:SetPoint("TOPRIGHT", guildHead, "BOTTOMRIGHT", 0, -4)
    sidebarDiv:SetTexture("Interface\\Buttons\\WHITE8X8")
    sidebarDiv:SetVertexColor(0.35, 0.30, 0.22, 0.65)

    local navDefs = {
        { id = "peers", label = L["Roster"], icon = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon" },
        { id = "events", label = L["Events & Calendar"], icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
        { id = "diplomacy", label = L["Diplomacy"], icon = "Interface\\Icons\\Ability_DualWield" },
        { id = "prof", label = L["Professions & Locks"], icon = "Interface\\Icons\\Trade_BlackSmithing" },
        { id = "hierarchy", label = L["Hierarchy"], icon = "Interface\\Icons\\INV_Crown_01" },
    }
    local prevNav = sidebarDiv
    for _, nd in ipairs(navDefs) do
        local nb = Theme:CreateButton(sidebar, 158, 28, nd.label, "nav")
        if nd.icon and (nb._textLayer or nb).CreateTexture then
            local navIco = (nb._textLayer or nb):CreateTexture(nil, "OVERLAY", nil, 2)
            navIco:SetSize(14, 14)
            navIco:SetPoint("LEFT", nb, "LEFT", 9, 0)
            navIco:SetTexture(nd.icon)
            if not nd.icon:find("UI-Toast", 1, true) then
                navIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            nb._scNavIcon = navIco
            Theme:StyleButton(nb, "nav")
        end
        nb:SetPoint("TOPLEFT", prevNav, "BOTTOMLEFT", 0, (prevNav == sidebarDiv) and -8 or -4)
        nb:SetPoint("TOPRIGHT", prevNav, "BOTTOMRIGHT", 0, (prevNav == sidebarDiv) and -8 or -4)
        nb:SetScript("OnClick", function()
            clanRightView = nd.id
            UpdateClanPanel()
        end)
        clanRightViewButtons[nd.id] = nb
        themeTargets[#themeTargets + 1] = { btn = nb, variant = "nav" }
        prevNav = nb
    end

    local openLfgFinderBtn = Theme:CreateButton(sidebar, 158, 28, "+ " .. L["Clans & Allies LFG"], "primary")
    openLfgFinderBtn:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 8, 8)
    openLfgFinderBtn:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -8, 8)
    openLfgFinderBtn:SetScript("OnClick", function()
        if ns.LFGFrameTab then
            ns.LFGFrameTab.viewMode = "browse"
            ns.LFGFrameTab.sourceFilter = "TRUSTED"
            ns.LFGFrameTab._hasSearchedThisSession = true
            if ns.LFGFrameTab.SaveBrowseFilters then
                ns.LFGFrameTab:SaveBrowseFilters()
            end
        end
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if not inCombat and ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
            ns.LFGFrameTab:OpenOfficialModule("lfg")
        else
            UI:OpenGroupBrowseView()
        end
    end)
    openLfgFinderBtn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Clans & Allies LFG"], 1, 0.9, 0.55, true)
        GameTooltip:AddLine(L["Opens the Group Finder filtered to guildmates and allied guilds."], 0.85, 0.88, 0.94, true)
        GameTooltip:Show()
    end)
    openLfgFinderBtn:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)
    themeTargets[#themeTargets + 1] = { btn = openLfgFinderBtn, variant = "primary" }

    -- 4. Right Main Content Area
    local mainCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    mainCard:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 6, 0)
    mainCard:SetPoint("BOTTOMRIGHT", bottomBar, "TOPRIGHT", 0, 4)

    -- 4.0) Epic Guild Overview Hero Card (live members, [SC], Events, Allies/Enemies, Focus & Online Class Breakdown)
    local guildHeroBar = CreateFrame("Frame", nil, mainCard, "BackdropTemplate")
    guildHeroBar:SetPoint("TOPLEFT", 6, -6)
    guildHeroBar:SetPoint("TOPRIGHT", -6, -6)
    guildHeroBar:SetHeight(42)
    Theme:ApplyBackdrop(guildHeroBar, "header")

    local heroRankLbl = guildHeroBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    heroRankLbl:SetPoint("TOPRIGHT", -8, -5)
    heroRankLbl:SetJustifyH("RIGHT")
    heroRankLbl:SetWordWrap(false)

    local heroSummaryLbl = guildHeroBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    heroSummaryLbl:SetPoint("TOPLEFT", 8, -5)
    heroSummaryLbl:SetPoint("RIGHT", heroRankLbl, "LEFT", -8, 0)
    heroSummaryLbl:SetJustifyH("LEFT")
    heroSummaryLbl:SetWordWrap(false)

    local heroMidSep = guildHeroBar:CreateTexture(nil, "ARTWORK", nil, 1)
    heroMidSep:SetHeight(1)
    heroMidSep:SetPoint("TOPLEFT", guildHeroBar, "TOPLEFT", 8, -21)
    heroMidSep:SetPoint("TOPRIGHT", guildHeroBar, "TOPRIGHT", -8, -21)
    heroMidSep:SetColorTexture(0.76, 0.60, 0.24, 0.26)

    local heroDetailLbl = guildHeroBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    heroDetailLbl:SetPoint("BOTTOMLEFT", 8, 5)
    heroDetailLbl:SetPoint("BOTTOMRIGHT", -8, 5)
    heroDetailLbl:SetJustifyH("LEFT")
    heroDetailLbl:SetWordWrap(false)

    guildHeroBar:EnableMouse(true)
    guildHeroBar:SetScript("OnEnter", function(selfHero)
        local gInfo = ns.Store and ns.Store.guildInfo or {}
        if not (gInfo.inGuild and GameTooltip) then return end
        local cInfo = ns.Clan and ns.Clan.GetClanInfo and ns.Clan:GetClanInfo() or {}
        GameTooltip:SetOwner(selfHero, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("<" .. (gInfo.name or L["Guild"]) .. ">", 1.0, 0.82, 0.0)
        if gInfo.motd and gInfo.motd ~= "" then
            GameTooltip:AddLine(L["MOTD"] .. ": " .. gInfo.motd, 0.90, 0.92, 0.95, true)
        end
        if cInfo.summary and cInfo.summary ~= "" then
            GameTooltip:AddDoubleLine(L["Focus"], cInfo.summary, 0.72, 0.78, 0.86, 1, 1, 1)
        end
        if cInfo.schedule and cInfo.schedule ~= "" then
            GameTooltip:AddDoubleLine(L["Schedule"], cInfo.schedule, 0.72, 0.78, 0.86, 0.65, 0.90, 1.0)
        end
        if cInfo.contacts and cInfo.contacts ~= "" then
            GameTooltip:AddDoubleLine(L["Contacts"], cInfo.contacts, 0.72, 0.78, 0.86, 0.45, 0.90, 0.55)
        end
        if cInfo.rules and cInfo.rules ~= "" then
            GameTooltip:AddLine(cInfo.rules, 0.80, 0.84, 0.90, true)
        end
        if clanPanel and clanPanel._onlineClassSummary and #clanPanel._onlineClassSummary > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Classes Online"], 1.0, 0.82, 0.0)
            local clsLine = {}
            for _, entry in ipairs(clanPanel._onlineClassSummary) do
                clsLine[#clsLine + 1] = entry.fullTxt
            end
            GameTooltip:AddLine(table.concat(clsLine, " · "), 0.90, 0.92, 0.95, true)
        end
        GameTooltip:Show()
    end)
    guildHeroBar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local ctxBar = CreateFrame("Frame", nil, mainCard)
    ctxBar:SetPoint("TOPLEFT", guildHeroBar, "BOTTOMLEFT", 2, -6)
    ctxBar:SetPoint("TOPRIGHT", guildHeroBar, "BOTTOMRIGHT", -2, -6)
    ctxBar:SetHeight(24)

    -- 4a) Roster contextual toolbar (Search + Guild Invite + Sync)
    local peersToolBar = CreateFrame("Frame", nil, ctxBar)
    peersToolBar:SetAllPoints()

    local peerSearch = Theme:CreateEditBox(peersToolBar, {
        width = 136,
        height = 22,
        placeholder = L["Search guild members..."],
        clearButton = true,
    })
    peerSearch:SetPoint("LEFT", 0, 0)
    peerSearch:HookScript("OnTextChanged", function(selfBox)
        local q = selfBox:GetText() or ""
        if q == clanPeerQuery then return end
        clanPeerQuery = q
        if C_Timer and C_Timer.After then
            local seq = (selfBox._scSearchSeq or 0) + 1
            selfBox._scSearchSeq = seq
            C_Timer.After(0.10, function()
                if selfBox._scSearchSeq == seq then
                    UpdateClanPanel()
                end
            end)
        else
            UpdateClanPanel()
        end
    end)

    local peersHelp = AddHelp(
        peersToolBar,
        peerSearch,
        L["Help: Clan Game Info"],
        L["Centralizes Online Guild Roster (Rank/Zone/Note), Events, Diplomacy stances, Guild Crafters, and Saved Dungeon/Raid Lockouts."],
        L["Type a member name, class, rank, or zone to filter the roster, or switch views in the sidebar."],
        nil,
        nil,
        nil,
        nil,
        {
            target = peersToolBar,
            steps = {
                {
                    title = L["Guild Hub Navigation"],
                    tag = "1/3 · " .. L["Guild"],
                    text = L["Use the left sidebar to switch between Roster, Guild & Allied Events, Diplomacy, Hierarchy/Polls, Crafters, and Raid Lockouts."],
                    target = sidebar,
                },
                {
                    title = L["Help: Clan Game Info"],
                    tag = "2/3 · " .. L["Roster & Status"],
                    text = L["Filter guildmates by name, class, rank, or zone right here, set your Guild Status tag, or invite targets safely."],
                    target = peersToolBar,
                },
                {
                    title = L["Spotter Radar & Guild Info"],
                    tag = "3/3 · " .. L["Radar & Info"],
                    text = L["Toggle the Target Radar, read or edit your shared Clan Info card, and see live Guild Sync status along this bottom bar."],
                    target = bottomBar,
                },
            },
        }
    )
    if frame then
        frame._scTabHelpBtns = frame._scTabHelpBtns or {}
        frame._scTabHelpBtns.clan = peersHelp
    end

    local guildInviteBtn = Theme:CreateButton(peersToolBar, 26, 22, "", "primary")
    Theme:ConfigureIconButton(guildInviteBtn, 26, 22, "Interface\\PaperDollInfoFrame\\Character-Plus", {
        size = 14,
        color = { 0.45, 0.95, 0.55 },
    })
    guildInviteBtn:SetPoint("RIGHT", peersToolBar, "RIGHT", 0, 0)
    if guildInviteBtn.SetMotionScriptsWhileDisabled then
        guildInviteBtn:SetMotionScriptsWhileDisabled(true)
    end
    guildInviteBtn:SetScript("OnClick", function()
        OpenGuildInviteModal()
    end)
    guildInviteBtn:HookScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Guild Invite"], 1, 0.85, 0.25)
        if not selfBtn._scInGuild then
            GameTooltip:AddLine(L["You must be in a guild to invite members."], 0.9, 0.45, 0.45, true)
        elseif selfBtn._scCanInvite then
            GameTooltip:AddLine(L["Generates a safe /ginvite command to copy into chat (Blizzard restricts addons from sending guild invites directly)."], 0.9, 0.92, 0.95, true)
        else
            GameTooltip:AddLine(L["No permission to invite (%s). Only authorized guild ranks can invite new members."]:format(selfBtn._scRankLabel or L["Member"]), 0.95, 0.45, 0.45, true)
        end
        GameTooltip:Show()
    end)
    guildInviteBtn:HookScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then
            GameTooltip:Hide()
        end
    end)
    themeTargets[#themeTargets + 1] = { btn = guildInviteBtn, variant = "primary" }

    local historyBtn = Theme:CreateButton(peersToolBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(historyBtn, 24, 22, "Interface\\Icons\\INV_Misc_PocketWatch_01", {
        size = 14,
        title = L["Guild Roster History"],
        desc = L["Shows recent guild joins, leaves, and rank changes observed on your character."],
    })
    historyBtn:SetScript("OnClick", function()
        if UI.OpenGuildRosterHistoryModal then
            UI:OpenGuildRosterHistoryModal()
        end
    end)
    themeTargets[#themeTargets + 1] = { btn = historyBtn, variant = "default" }
    local historyHelp = AddHelp(
        peersToolBar,
        historyBtn,
        L["Help: Guild Roster History"],
        L["Tracks recent guild member joins, departures, and rank promotions/demotions across sessions."],
        L["Click 'History' to view and optionally copy the recent Guild Roster changelog."]
    )
    historyHelp:ClearAllPoints()
    historyHelp:SetPoint("RIGHT", guildInviteBtn, "LEFT", -6, 0)
    historyBtn:ClearAllPoints()
    historyBtn:SetPoint("RIGHT", historyHelp, "LEFT", -4, 0)

    local clanFilterBtn = Theme:CreateButton(peersToolBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(clanFilterBtn, 24, 22, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", {
        size = 14,
        toggle = true,
        active = false,
        activeColor = { 0.96, 0.76, 0.22 },
        tooltipFn = function(selfBtn)
            local n = selfBtn and selfBtn._scActiveFilterCount or 0
            local ttl = L["Filters"] .. (n > 0 and (" (" .. tostring(n) .. ")") or "")
            return ttl, L["Presence / Status"] .. " · " .. L["Rank"] .. " · " .. L["Class"]
        end,
    })
    clanFilterBtn:SetPoint("RIGHT", historyBtn, "LEFT", -6, 0)
    clanFilterBtn:SetScript("OnClick", function(selfBtn)
        if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Clan) then return end
        local ranks = ns.Clan.GetGuildRanks and ns.Clan:GetGuildRanks() or {}
        local classes = ns.Clan.GetGuildPresentClasses and ns.Clan:GetGuildPresentClasses() or {}
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            root:CreateTitle(L["Presence / Status"])
            for _, opt in ipairs({
                { id = "all", label = L["All"] },
                { id = "online", label = L["Online Only"] },
                { id = "offline", label = L["Offline Only"] },
                { id = "inactive30", label = L["Inactive > 30d"] },
                { id = "inactive60", label = L["Inactive > 60d"] },
                { id = "inactive90", label = L["Inactive > 90d"] },
                { id = "sc", label = L["Has Addon [SC]"] },
                { id = "lfg", label = L["Active Status (LFG)"] },
            }) do
                local sid = opt.id
                root:CreateRadio(opt.label, function()
                    return clanPeerStatusFilter == sid
                end, function()
                    clanPeerStatusFilter = sid
                    UpdateClanPanel()
                end)
            end

            root:CreateDivider()
            local rankSub = root:CreateButton(L["Rank"])
            if rankSub and rankSub.CreateRadio then
                rankSub:CreateRadio(L["All Ranks"], function()
                    return clanPeerRankFilter == nil
                end, function()
                    clanPeerRankFilter = nil
                    UpdateClanPanel()
                end)
                for _, rk in ipairs(ranks) do
                    local rIdx = rk.rankIndex
                    local rLabel = string.format("#%d %s (%d)", rIdx, rk.name, rk.totalMembers or 0)
                    rankSub:CreateRadio(rLabel, function()
                        return clanPeerRankFilter == rIdx
                    end, function()
                        clanPeerRankFilter = rIdx
                        UpdateClanPanel()
                    end)
                end
            end

            if #classes > 0 then
                local clsSub = root:CreateButton(L["Class"])
                if clsSub and clsSub.CreateRadio then
                    clsSub:CreateRadio(L["All Classes"], function()
                        return clanPeerClassFilter == nil
                    end, function()
                        clanPeerClassFilter = nil
                        UpdateClanPanel()
                    end)
                    for _, cl in ipairs(classes) do
                        local cid = cl.id
                        clsSub:CreateRadio(Compat.ClassHex(cid) .. cl.label .. "|r", function()
                            return clanPeerClassFilter == cid
                        end, function()
                            clanPeerClassFilter = cid
                            UpdateClanPanel()
                        end)
                    end
                end
            end

            local sortSub = root:CreateButton(L["Sort Order"])
            if sortSub and sortSub.CreateRadio then
                for _, sopt in ipairs({
                    { id = "level_desc", label = L["Sort: Level (High-Low)"] },
                    { id = "rank", label = L["Sort: Rank"] },
                    { id = "name", label = L["Sort: Name"] },
                    { id = "zone", label = L["Sort: Zone"] },
                }) do
                    local sId = sopt.id
                    sortSub:CreateRadio(sopt.label, function()
                        return clanPeerSortBy == sId
                    end, function()
                        clanPeerSortBy = sId
                        UpdateClanPanel()
                    end)
                end
            end

            if clanPeerStatusFilter ~= "all" or clanPeerRankFilter ~= nil or clanPeerClassFilter ~= nil or clanPeerSortBy ~= "level_desc" or clanPeerQuery ~= "" then
                root:CreateDivider()
                root:CreateButton(L["Clear Filters"], function()
                    clanPeerStatusFilter = "all"
                    clanPeerRankFilter = nil
                    clanPeerClassFilter = nil
                    clanPeerSortBy = "level_desc"
                    clanPeerQuery = ""
                    if clanPanel and clanPanel.peerSearch and clanPanel.peerSearch.SetText then
                        clanPanel.peerSearch:SetText("")
                    end
                    UpdateClanPanel()
                end)
            end
            root:CreateDivider()
            root:CreateButton(L["Export Roster (CSV)..."], function()
                if UI.OpenGuildRosterCsvExport then
                    UI:OpenGuildRosterCsvExport()
                end
            end)
        end)
    end)
    themeTargets[#themeTargets + 1] = { btn = clanFilterBtn, variant = "default" }

    -- 4b) Events contextual toolbar (1 filter dropdown + 1 primary button)
    local eventsToolBar = CreateFrame("Frame", nil, ctxBar)
    eventsToolBar:SetAllPoints()
    eventsToolBar:Hide()

    local evtFilterBtn = Theme:CreateButton(eventsToolBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(evtFilterBtn, 24, 22, "Interface\\Icons\\INV_Misc_PocketWatch_01", {
        size = 14,
        toggle = true,
        active = (clanEventFilter ~= "all"),
        activeColor = { 0.96, 0.76, 0.22 },
        tooltipFn = function()
            local evtLabels = {
                all = L["All"],
                guild = L["My Guild Only"],
                allied = L["Allied Guilds Only"],
                open = L["Open Only"],
                need_tank = L["Need T"],
                need_heal = L["Need H"],
                calendar = L["Calendar"],
            }
            return L["Filters"] .. ": " .. (evtLabels[clanEventFilter] or L["All"])
        end,
    })
    evtFilterBtn:SetScript("OnClick", function(self)
        local evtFilters = {
            { id = "all", label = L["All"] },
            { id = "guild", label = L["My Guild Only"] },
            { id = "allied", label = L["Allied Guilds Only"] },
            { id = "open", label = L["Open Only"] },
            { id = "need_tank", label = L["Need T"] },
            { id = "need_heal", label = L["Need H"] },
            { id = "calendar", label = L["Calendar"] },
        }
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                for _, ef in ipairs(evtFilters) do
                    root:CreateRadio(ef.label, function()
                        return clanEventFilter == ef.id
                    end, function()
                        clanEventFilter = ef.id
                        UpdateClanPanel()
                    end)
                end
                root:CreateDivider()
                root:CreateButton(L["WoW Calendar"], function()
                    OpenCopyModal(
                        "/calendar",
                        L["Copy /calendar Command (Ctrl+C)"],
                        L["Blizzard protects direct opening of the Calendar panel from addons. Copy '/calendar' below or click the Calendar icon on your Minimap."]
                    )
                end)
            end)
        else
            local nextIdx = 1
            for i, ef in ipairs(evtFilters) do
                if ef.id == clanEventFilter then nextIdx = (i % #evtFilters) + 1; break end
            end
            clanEventFilter = evtFilters[nextIdx].id
            UpdateClanPanel()
        end
    end)
    themeTargets[#themeTargets + 1] = { btn = evtFilterBtn, variant = "default" }

    local evtAllyBtn = Theme:CreateButton(eventsToolBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(evtAllyBtn, 24, 22, "Interface\\GossipFrame\\TabardGossipIcon", {
        size = 15,
        toggle = true,
        active = false,
        activeColor = { 0.28, 0.88, 0.45 },
        tooltipFn = function()
            local allAllies = (ns.Clan and ns.Clan.GetDiplomacyList and ns.Clan:GetDiplomacyList("ALLY")) or {}
            local mutAllies = (ns.Clan and ns.Clan.GetMutuallyAuthorizedAlliedGuilds and ns.Clan:GetMutuallyAuthorizedAlliedGuilds()) or {}
            return L["Allies (%d/%d)"]:format(#mutAllies, #allAllies), L["Allied Guild Shared Events"]
        end,
    })
    evtAllyBtn:SetScript("OnClick", function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Clan) then
            clanRightView = "diplomacy"
            UpdateClanPanel()
            return
        end
        local allies = (ns.Clan.GetDiplomacyList and ns.Clan:GetDiplomacyList("ALLY")) or {}
        local canShare, authSum = false, L["Guild Leader Only"]
        if ns.Clan.CanManageAlliedEventSharing then
            canShare, authSum = ns.Clan:CanManageAlliedEventSharing()
        end
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle(L["Allied Guild Shared Events"])
            root:CreateTitle("|cff9da7b5" .. L["Requires approval in BOTH guilds (%s)"]:format(authSum) .. "|r")
            root:CreateDivider()
            if #allies == 0 then
                root:CreateTitle("|cff8b949e" .. L["No Allied Guilds registered yet."] .. "|r")
            else
                for _, ally in ipairs(allies) do
                    local aName = ally.name or ally.key or "?"
                    local st = ns.Clan:GetAlliedEventShareState(aName)
                    local statusTag = st.mutual and ("|cff40d973[" .. L["Mutual"] .. "]|r")
                        or (st.myApproved and ("|cffffd24d[" .. L["Awaiting Ally"] .. "]|r")
                        or (st.peerApproved and ("|cff58a6ff[" .. L["Ally Requested"] .. "]|r")
                        or ("|cff8b949e[" .. L["Off"] .. "]|r")))
                    local rowLabel = "<" .. aName .. ">  " .. statusTag
                    if canShare then
                        root:CreateCheckbox(rowLabel, function()
                            return ns.Clan:GetAlliedEventShareState(aName).myApproved == true
                        end, function()
                            local cur = ns.Clan:GetAlliedEventShareState(aName).myApproved == true
                            ns.Clan:SetAlliedEventSharing(aName, not cur)
                        end)
                    else
                        root:CreateTitle(rowLabel)
                    end
                end
            end
            root:CreateDivider()
            root:CreateButton(L["Sync Allied Events Now"], function()
                if ns.Clan and ns.Clan.RequestAlliedEventsSync then
                    ns.Clan:RequestAlliedEventsSync()
                end
                UpdateClanPanel()
            end)
            root:CreateButton(L["Open Guild Diplomacy"], function()
                clanRightView = "diplomacy"
                UpdateClanPanel()
            end)
            root:CreateButton(L["Hierarchy & Ranks"], function()
                clanRightView = "hierarchy"
                UpdateClanPanel()
            end)
        end)
    end)
    themeTargets[#themeTargets + 1] = { btn = evtAllyBtn, variant = "default" }

    local newEventBtn = Theme:CreateButton(eventsToolBar, 26, 22, "", "primary")
    Theme:ConfigureIconButton(newEventBtn, 26, 22, "Interface\\PaperDollInfoFrame\\Character-Plus", {
        size = 14,
        color = { 0.45, 0.95, 0.55 },
        title = L["+ Event Call"],
        desc = L["Creates guild-wide group calls for Dungeons, M+, Raids, World Bosses, or PvP where guildmates sign up as Tank, Healer, DPS, or Maybe."],
    })
    newEventBtn:SetScript("OnClick", function() OpenEventModal() end)
    themeTargets[#themeTargets + 1] = { btn = newEventBtn, variant = "primary" }
    newEventBtn._pairedHelp = AddHelp(
        eventsToolBar,
        newEventBtn,
        L["Help: Clan Event Calls"],
        L["Creates guild-wide group calls for Dungeons, M+, Raids, World Bosses, or PvP where guildmates sign up as Tank, Healer, DPS, or Maybe."],
        L["Click '+ Event Call' to post an event, or use the filter dropdown to inspect 'Calendar' and open the native WoW Calendar."]
    )

    local pollsBtn = Theme:CreateButton(eventsToolBar, 26, 22, "", "default")
    Theme:ConfigureIconButton(pollsBtn, 26, 22, "Interface\\Icons\\INV_Misc_Note_06", {
        size = 14,
        title = L["Guild Polls & Voting"],
        desc = L["Vote on active Guild Polls or create a new poll for your guildmates."],
    })
    pollsBtn:SetScript("OnClick", function() UI:OpenGuildPollsModal() end)
    themeTargets[#themeTargets + 1] = { btn = pollsBtn, variant = "default" }
    pollsBtn._pairedHelp = AddHelp(
        eventsToolBar,
        pollsBtn,
        L["Help: Guild Polls & Voting"],
        L["Lets officers create quick guild polls (2 to 5 choices) and guildmates vote live in real time."],
        L["Click to view active polls, vote in 1 click, or create a new guild poll."]
    )

    -- 4c) Diplomacy contextual toolbar (1 filter/sync dropdown + 1 primary button)
    local dipToolBar = CreateFrame("Frame", nil, ctxBar)
    dipToolBar:SetAllPoints()
    dipToolBar:Hide()

    local dipFilterBtn = Theme:CreateButton(dipToolBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(dipFilterBtn, 24, 22, "Interface\\Icons\\Ability_DualWield", {
        size = 14,
        toggle = true,
        active = (clanRightViewFilterDip ~= "all"),
        activeColor = { 0.28, 0.88, 0.45 },
        tooltipFn = function()
            local fltLbl = clanRightViewFilterDip == "ENEMY" and L["Filter: Enemy"]
                or (clanRightViewFilterDip == "ALLY" and L["Filter: Ally"] or L["Filter: All"])
            return fltLbl
        end,
    })
    dipFilterBtn:SetScript("OnClick", function(self)
        local opts = {
            { id = "all", label = L["Filter: All"] },
            { id = "ENEMY", label = L["Filter: Enemy"] },
            { id = "ALLY", label = L["Filter: Ally"] },
        }
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                for _, o in ipairs(opts) do
                    root:CreateRadio(o.label, function()
                        return clanRightViewFilterDip == o.id
                    end, function()
                        clanRightViewFilterDip = o.id
                        UpdateClanPanel()
                    end)
                end
                if ns.Clan and ns.Clan.CanManageAlliance and ns.Clan:CanManageAlliance() then
                    root:CreateDivider()
                    root:CreateButton(L["Alliance"], OpenAllianceManagementModal)
                end
            end)
        else
            if clanRightViewFilterDip == "all" then
                clanRightViewFilterDip = "ENEMY"
            elseif clanRightViewFilterDip == "ENEMY" then
                clanRightViewFilterDip = "ALLY"
            else
                clanRightViewFilterDip = "all"
            end
            UpdateClanPanel()
        end
    end)
    themeTargets[#themeTargets + 1] = { btn = dipFilterBtn, variant = "default" }

    local dipAddBtn = Theme:CreateButton(dipToolBar, 26, 22, "", "primary")
    Theme:ConfigureIconButton(dipAddBtn, 26, 22, "Interface\\PaperDollInfoFrame\\Character-Plus", {
        size = 14,
        color = { 0.45, 0.95, 0.55 },
    })
    dipAddBtn:SetScript("OnClick", function()
        OpenDiplomacyModal()
    end)
    dipAddBtn:SetScript("OnEnter", function(selfBtn)
        if GameTooltip then
            local canDip, authSummary = false, L["Guild Leader Only"]
            if ns.Clan and ns.Clan.CanManageDiplomacy then
                canDip, authSummary = ns.Clan:CanManageDiplomacy()
            end
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["Guild Diplomacy Registry"], 1.0, 0.85, 0.25)
            if canDip then
                GameTooltip:AddLine(L["Diplomacy Authority: %s"]:format(authSummary), 0.35, 0.88, 0.50, true)
            else
                GameTooltip:AddLine(L["Only guild leaders (%s) can define Allied or Enemy guilds."]:format(authSummary), 1.0, 0.42, 0.42, true)
            end
            GameTooltip:Show()
        end
    end)
    dipAddBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    themeTargets[#themeTargets + 1] = { btn = dipAddBtn, variant = "primary" }

    local dipAuthBtn = Theme:CreateButton(dipToolBar, 148, 22, L["Guild Leader Only"], "default")
    Theme:AutoFitButton(dipAuthBtn, 120, 14, 235)
    dipAuthBtn:SetScript("OnClick", function()
        clanRightView = "hierarchy"
        UpdateClanPanel()
    end)
    dipAuthBtn:SetScript("OnEnter", function(selfBtn)
        if GameTooltip then
            local _, authSummary = false, L["Guild Leader Only"]
            if ns.Clan and ns.Clan.CanManageDiplomacy then
                _, authSummary = ns.Clan:CanManageDiplomacy()
            end
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["Diplomacy Authority: %s"]:format(authSummary), 1.0, 0.85, 0.25, true)
            GameTooltip:AddLine(L["Click to open Guild Hierarchy & Permissions."], 0.65, 0.82, 1.0, true)
            GameTooltip:Show()
        end
    end)
    dipAuthBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    themeTargets[#themeTargets + 1] = { btn = dipAuthBtn, variant = "default" }
    dipAuthBtn._pairedHelp = AddHelp(
        dipToolBar,
        dipAuthBtn,
        L["Help: Guild Hierarchy & Permissions"],
        L["Uses your guild's real WoW rank ladder to show permissions per rank and let the Guild Leader delegate who can define Allied/Enemy guilds, edit Guild Info, moderate Events, and access Alliance Chat."],
        L["Click 'Diplomacy' to choose which ranks can tag Allied/Enemy guilds, 'Hierarchy Rules' for Info/Events/Alliance rank access, or click any rank row below."]
    )

    -- 4c-2) Hierarchy & Ranks contextual toolbar
    local hierToolBar = CreateFrame("Frame", nil, ctxBar)
    hierToolBar:SetAllPoints()
    hierToolBar:Hide()

    local function BuildRuleSubmenu(parentMenu, titleText, currentMode, currentMaxRank, onSelectMode, onSelectRank, includeAllOption)
        local ranks = (ns.Clan and ns.Clan.GetGuildRanks and ns.Clan:GetGuildRanks()) or {}
        local sub = parentMenu:CreateButton(titleText)
        if not (sub and sub.CreateRadio) then return end
        sub:CreateRadio(L["Guild Leader Only"], function()
            return currentMode == "LEADER"
        end, function()
            onSelectMode("LEADER", 0)
        end)
        sub:CreateRadio(L["Leader & Game Officers"], function()
            return currentMode == "OFFICERS"
        end, function()
            onSelectMode("OFFICERS", 1)
        end)
        if includeAllOption then
            sub:CreateRadio(L["All Guild Members"], function()
                return currentMode == "ALL"
            end, function()
                onSelectMode("ALL", 9)
            end)
        end
        if #ranks > 1 then
            sub:CreateDivider()
            sub:CreateTitle(L["Or allow up to Game Rank:"])
            for _, rk in ipairs(ranks) do
                if rk.rankIndex >= 1 then
                    local rIdx = rk.rankIndex
                    sub:CreateRadio(string.format("#%d %s", rIdx, rk.name), function()
                        return currentMode == "RANK" and currentMaxRank == rIdx
                    end, function()
                        onSelectRank(rIdx)
                    end)
                end
            end
        end
    end

    local hierDipBtn = Theme:CreateButton(hierToolBar, 152, 22, L["Guild Leader Only"] .. "  v", "default")
    Theme:AutoFitButton(hierDipBtn, 130, 14, 240)
    hierDipBtn:SetScript("OnClick", function(selfBtn)
        if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Clan) then return end
        local isGM = ns.Clan.IsGuildLeader and ns.Clan:IsGuildLeader()
        local pol = ns.Clan:GetGuildHierarchyPolicy()
        local ranks = ns.Clan.GetGuildRanks and ns.Clan:GetGuildRanks() or {}
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            root:CreateTitle(L["Who can define Allied / Enemy guilds (Diplomacy):"])
            if not isGM then
                root:CreateTitle("|cffff6666" .. L["Only the Guild Leader can configure Guild Hierarchy & Rank Permissions."] .. "|r")
                return
            end
            root:CreateRadio(L["Guild Leader Only"], function()
                return pol.diplomacyMode == "LEADER"
            end, function()
                ns.Clan:SaveGuildHierarchyPolicy({ diplomacyMode = "LEADER", diplomacyMaxRank = 0 })
            end)
            root:CreateRadio(L["Leader & Game Officers"], function()
                return pol.diplomacyMode == "OFFICERS"
            end, function()
                ns.Clan:SaveGuildHierarchyPolicy({ diplomacyMode = "OFFICERS", diplomacyMaxRank = 1 })
            end)
            if #ranks > 1 then
                root:CreateDivider()
                root:CreateTitle(L["Or allow up to Game Rank:"])
                for _, rk in ipairs(ranks) do
                    if rk.rankIndex >= 1 then
                        local rIdx = rk.rankIndex
                        root:CreateRadio(string.format("#%d %s", rIdx, rk.name), function()
                            return pol.diplomacyMode == "RANK" and pol.diplomacyMaxRank == rIdx
                        end, function()
                            ns.Clan:SaveGuildHierarchyPolicy({ diplomacyMode = "RANK", diplomacyMaxRank = rIdx })
                        end)
                    end
                end
            end
        end)
    end)
    themeTargets[#themeTargets + 1] = { btn = hierDipBtn, variant = "default" }
    hierDipBtn._pairedHelp = AddHelp(
        hierToolBar,
        hierDipBtn,
        L["Help: Guild Hierarchy & Permissions"],
        L["Uses your guild's real WoW rank ladder to show permissions per rank and let the Guild Leader delegate who can define Allied/Enemy guilds, edit Guild Info, moderate Events, and access Alliance Chat."],
        L["Click 'Diplomacy' to choose which ranks can tag Allied/Enemy guilds, 'Hierarchy Rules' for Info/Events/Alliance rank access, or click any rank row below."]
    )

    local hierRulesBtn = Theme:CreateButton(hierToolBar, 132, 22, L["Hierarchy Rules"] .. "  v", "primary")
    Theme:AutoFitButton(hierRulesBtn, 110, 14, 190)
    hierRulesBtn:SetScript("OnClick", function(selfBtn)
        if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Clan) then return end
        local isGM = ns.Clan.IsGuildLeader and ns.Clan:IsGuildLeader()
        local pol = ns.Clan:GetGuildHierarchyPolicy()
        local ranks = ns.Clan.GetGuildRanks and ns.Clan:GetGuildRanks() or {}
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            root:CreateTitle(L["Hierarchy Rules"])
            if not isGM then
                root:CreateTitle("|cffff6666" .. L["Only the Guild Leader can configure Guild Hierarchy & Rank Permissions."] .. "|r")
            else
                BuildRuleSubmenu(root, L["Who can edit Guild Info & Schedule:"], pol.infoMode, pol.infoMaxRank, function(mode, maxR)
                    ns.Clan:SaveGuildHierarchyPolicy({ infoMode = mode, infoMaxRank = maxR })
                end, function(rIdx)
                    ns.Clan:SaveGuildHierarchyPolicy({ infoMode = "RANK", infoMaxRank = rIdx })
                end, true)

                BuildRuleSubmenu(root, L["Who can moderate / close any Event Call:"], pol.eventModMode, pol.eventModMaxRank, function(mode, maxR)
                    ns.Clan:SaveGuildHierarchyPolicy({ eventModMode = mode, eventModMaxRank = maxR })
                end, function(rIdx)
                    ns.Clan:SaveGuildHierarchyPolicy({ eventModMode = "RANK", eventModMaxRank = rIdx })
                end, false)

                local allySub = root:CreateButton(L["Auto-allow Alliance Chat up to Rank:"])
                if allySub and allySub.CreateRadio then
                    allySub:CreateRadio(L["Manual Whitelist / Mode Only"], function()
                        return (pol.allianceMinRank or -1) < 0
                    end, function()
                        ns.Clan:SaveGuildHierarchyPolicy({ allianceMinRank = -1 })
                    end)
                    for _, rk in ipairs(ranks) do
                        local rIdx = rk.rankIndex
                        allySub:CreateRadio(string.format("#%d %s", rIdx, rk.name), function()
                            return pol.allianceMinRank == rIdx
                        end, function()
                            ns.Clan:SaveGuildHierarchyPolicy({ allianceMinRank = rIdx })
                        end)
                    end
                end
            end
        end)
    end)
    themeTargets[#themeTargets + 1] = { btn = hierRulesBtn, variant = "primary" }

    local hierAllyBtn = Theme:CreateButton(hierToolBar, 88, 22, L["Alliance"], "default")
    Theme:AutoFitButton(hierAllyBtn, 72, 12, 130)
    hierAllyBtn:SetScript("OnClick", OpenAllianceManagementModal)
    themeTargets[#themeTargets + 1] = { btn = hierAllyBtn, variant = "default" }

    -- 4d) Professions & Lockouts contextual toolbar (View + Profession Filter + Source Filter + My Profs + Refresh + Search)
    local profToolBar = CreateFrame("Frame", nil, ctxBar)
    profToolBar:SetAllPoints()
    profToolBar:Hide()

    local profViewBtn = Theme:CreateButton(profToolBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(profViewBtn, 24, 22, "Interface\\Icons\\Trade_BlackSmithing", {
        size = 14,
        toggle = true,
        active = false,
        activeColor = { 0.96, 0.76, 0.22 },
        tooltipFn = function()
            return (clanRightView == "locks" and L["Locks"] or L["Professions"]), L["Switch between 'Locks' and 'Professions' in the selector or click 'Refresh' to request updated raid lockout timers from the server."]
        end,
    })
    profViewBtn:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateRadio(L["Professions"], function()
                    return clanRightView == "prof"
                end, function()
                    clanRightView = "prof"
                    UpdateClanPanel()
                end)
                root:CreateRadio(L["Locks"], function()
                    return clanRightView == "locks"
                end, function()
                    clanRightView = "locks"
                    if ns.Clan and ns.Clan.RequestLockoutsRefresh then
                        ns.Clan:RequestLockoutsRefresh(false)
                    end
                    UpdateClanPanel()
                end)
            end)
        else
            clanRightView = (clanRightView == "locks") and "prof" or "locks"
            if clanRightView == "locks" and ns.Clan and ns.Clan.RequestLockoutsRefresh then
                ns.Clan:RequestLockoutsRefresh(false)
            end
            UpdateClanPanel()
        end
    end)
    themeTargets[#themeTargets + 1] = { btn = profViewBtn, variant = "default" }

    local profFilterBtn = Theme:CreateButton(profToolBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(profFilterBtn, 24, 22, "Interface\\Icons\\Trade_BlackSmithing", {
        size = 14,
        toggle = true,
        active = (clanProfFilter ~= "ALL"),
        activeColor = { 0.96, 0.76, 0.22 },
        tooltipFn = function()
            local pMap = (ns.SocialPanels and ns.SocialPanels.PROF_LABELS) or {}
            local pfLbl = (clanProfFilter ~= "ALL") and (pMap[clanProfFilter] or clanProfFilter) or L["All Professions"]
            return L["Filter by Profession"] .. ": " .. pfLbl
        end,
    })
    profFilterBtn:SetScript("OnClick", function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then
            clanProfFilter = "ALL"
            UpdateClanPanel()
            return
        end
        local pMap = (ns.SocialPanels and ns.SocialPanels.PROF_LABELS) or {}
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle(L["Filter by Profession"])
            root:CreateRadio(L["All Professions"], function()
                return clanProfFilter == "ALL"
            end, function()
                clanProfFilter = "ALL"
                UpdateClanPanel()
            end)
            local activeProfs, otherProfs = {}, {}
            for _, item in ipairs((ns.Clan and ns.Clan.PROFESSIONS) or {}) do
                if item.id ~= "NONE" then
                    local cnt = clanProfCounts[item.id] or 0
                    if cnt > 0 then
                        activeProfs[#activeProfs + 1] = { id = item.id, count = cnt, label = pMap[item.id] or L[item.labelKey or item.id] }
                    else
                        otherProfs[#otherProfs + 1] = { id = item.id, label = pMap[item.id] or L[item.labelKey or item.id] }
                    end
                end
            end
            if #activeProfs > 0 then
                table.sort(activeProfs, function(a, b) return (a.label or "") < (b.label or "") end)
                root:CreateDivider()
                for _, entry in ipairs(activeProfs) do
                    local pid = entry.id
                    root:CreateRadio(("%s (%d)"):format(entry.label or pid, entry.count), function()
                        return clanProfFilter == pid
                    end, function()
                        clanProfFilter = pid
                        UpdateClanPanel()
                    end)
                end
            end
            if #otherProfs > 0 then
                table.sort(otherProfs, function(a, b) return (a.label or "") < (b.label or "") end)
                root:CreateDivider()
                for _, entry in ipairs(otherProfs) do
                    local pid = entry.id
                    root:CreateRadio(entry.label or pid, function()
                        return clanProfFilter == pid
                    end, function()
                        clanProfFilter = pid
                        UpdateClanPanel()
                    end)
                end
            end
        end)
    end)
    themeTargets[#themeTargets + 1] = { btn = profFilterBtn, variant = "default" }

    local profSourceBtn = Theme:CreateButton(profToolBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(profSourceBtn, 24, 22, "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", {
        size = 15,
        toggle = true,
        active = (clanProfSourceFilter ~= "ALL"),
        activeColor = { 0.35, 0.78, 1.0 },
        tooltipFn = function()
            local srcLabels = {
                ALL = L["All"],
                ONLINE = L["Online Only"],
                GUILD = L["Guild"],
                ALTS = L["My Alts"],
                SYNC = L["SC Sync Only"],
            }
            return L["Source Filter"] .. ": " .. (srcLabels[clanProfSourceFilter] or L["All"])
        end,
    })
    profSourceBtn:SetScript("OnClick", function(self)
        local sourceOpts = {
            { id = "ALL", label = L["All"] },
            { id = "ONLINE", label = L["Online Only"] },
            { id = "GUILD", label = L["Guild"] },
            { id = "ALTS", label = L["My Alts"] },
            { id = "SYNC", label = L["SC Sync Only"] },
        }
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(L["Source Filter"])
                for _, opt in ipairs(sourceOpts) do
                    local sid = opt.id
                    root:CreateRadio(opt.label, function()
                        return clanProfSourceFilter == sid
                    end, function()
                        clanProfSourceFilter = sid
                        UpdateClanPanel()
                    end)
                end
            end)
        else
            local nextMap = { ALL = "ONLINE", ONLINE = "GUILD", GUILD = "ALTS", ALTS = "SYNC", SYNC = "ALL" }
            clanProfSourceFilter = nextMap[clanProfSourceFilter] or "ALL"
            UpdateClanPanel()
        end
    end)
    themeTargets[#themeTargets + 1] = { btn = profSourceBtn, variant = "default" }

    local profBtn = Theme:CreateButton(profToolBar, 26, 22, "", "primary")
    Theme:ConfigureIconButton(profBtn, 26, 22, "Interface\\PaperDollInfoFrame\\Character-Plus", {
        size = 14,
        color = { 0.45, 0.95, 0.55 },
        title = "+ " .. L["Prof"],
        desc = L["Lists your auto-detected professions & skill ranks, your Alts, guildmates using SocialCentral, and guildmates whose Guild Public Note or guild chat lists crafts."],
    })
    profBtn:SetScript("OnClick", function()
        if ns.SocialPanels and ns.SocialPanels.OpenProfessionModal then
            ns.SocialPanels:OpenProfessionModal()
        end
    end)
    themeTargets[#themeTargets + 1] = { btn = profBtn, variant = "primary" }
    profBtn._pairedHelp = AddHelp(
        profToolBar,
        profBtn,
        L["Help: Clan Professions"],
        L["Lists your auto-detected professions & skill ranks, your Alts, guildmates using SocialCentral, and guildmates whose Guild Public Note or guild chat lists crafts."],
        L["Filter by profession or source (Online, Guild, Alts), click any crafter row to whisper or invite, or click '+ Prof' to set a craft note or publish your Guild Public Note."]
    )

    local profSearch
    local profAskBtn = Theme:CreateButton(profToolBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(profAskBtn, 24, 22, "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", {
        size = 14,
    })
    profAskBtn:SetScript("OnClick", function()
        if clanProfQuery == "" then
            ns:Print("%s", L["Type an item or recipe name in the search box first, then click 'Ask Guild'."])
            if profSearch and profSearch.SetFocus then pcall(profSearch.SetFocus, profSearch) end
            return
        end
        if ns.Clan and ns.Clan.RequestGuildRecipeSearch then
            local okSent = ns.Clan:RequestGuildRecipeSearch(clanProfQuery)
            if okSent then
                ns:Print(L["Asking online guildmates who can craft '%s'..."], clanProfQuery)
            end
        end
    end)
    profAskBtn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Ask Guild"], 1.0, 0.82, 0.0)
        GameTooltip:AddLine(L["Sends a lightweight recipe lookup to online guildmates using SocialCentral so crafters who know your typed item appear here and in tooltips."], 0.85, 0.88, 0.92, true)
        GameTooltip:Show()
    end)
    profAskBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    themeTargets[#themeTargets + 1] = { btn = profAskBtn, variant = "default" }
    profAskBtn._pairedHelp = AddHelp(
        profToolBar,
        profAskBtn,
        L["Help: Ask Guild Recipe Search"],
        L["Queries online SocialCentral guildmates cleanly (8s cooldown, opt-in Guild Sync) to find who knows the exact item or recipe you typed."],
        L["Type e.g. 'Crusader' or 'Flask', click 'Ask Guild' (or press Enter), then click any matching crafter to send a pre-filled Craft Request whisper."]
    )

    local locksRefreshBtn = Theme:CreateButton(profToolBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(locksRefreshBtn, 24, 22, "Interface\\Buttons\\UI-RefreshButton", {
        size = 14,
    })
    locksRefreshBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    locksRefreshBtn:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then
            UI:ConfirmResetInstances()
            return
        end
        if ns.Clan and ns.Clan.RequestLockoutsRefresh then
            ns.Clan:RequestLockoutsRefresh(true)
        end
        UpdateClanPanel()
    end)
    locksRefreshBtn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Locks"], 1.0, 0.82, 0.0)
        GameTooltip:AddLine(L["Left-click: Refresh raid lockouts from server"], 0.85, 0.88, 0.92, true)
        GameTooltip:AddLine(L["Right-click: Reset Dungeon Instances"], 0.40, 0.92, 0.55, true)
        GameTooltip:Show()
    end)
    locksRefreshBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    themeTargets[#themeTargets + 1] = { btn = locksRefreshBtn, variant = "default" }
    locksRefreshBtn:Hide()
    locksRefreshBtn._pairedHelp = AddHelp(
        profToolBar,
        locksRefreshBtn,
        L["Help: Saved Lockouts"],
        L["Displays active dungeon and raid lockouts, boss progress, reset countdowns, and your active Group Finder status across this character and your Alts."],
        L["Switch between 'Locks' and 'Professions' in the selector or click 'Refresh' to request updated raid lockout timers from the server."]
    )
    if locksRefreshBtn._pairedHelp then
        locksRefreshBtn._pairedHelp:Hide()
    end

    profSearch = Theme:CreateEditBox(profToolBar, {
        width = 148,
        height = 22,
        placeholder = L["Search recipes or professions..."],
        clearButton = true,
    })
    profSearch:HookScript("OnTextChanged", function(selfBox)
        local q = selfBox:GetText() or ""
        if q == clanProfQuery then return end
        clanProfQuery = q
        if C_Timer and C_Timer.After then
            local seq = (selfBox._scSearchSeq or 0) + 1
            selfBox._scSearchSeq = seq
            C_Timer.After(0.10, function()
                if selfBox._scSearchSeq == seq then
                    UpdateClanPanel()
                end
            end)
        else
            UpdateClanPanel()
        end
    end)
    profSearch:SetScript("OnEnterPressed", function(selfBox)
        selfBox:ClearFocus()
        if clanRightView == "prof" and clanProfQuery ~= "" and ns.Clan and ns.Clan.RequestGuildRecipeSearch and ns.db and ns.db.settings and ns.db.settings.clanSync then
            local okSent = ns.Clan:RequestGuildRecipeSearch(clanProfQuery)
            if okSent then
                ns:Print(L["Asking online guildmates who can craft '%s'..."], clanProfQuery)
            end
        end
    end)

    -- Shared full-size right scroll lists
    local listHolder = CreateFrame("Frame", nil, mainCard)
    listHolder:SetPoint("TOPLEFT", ctxBar, "BOTTOMLEFT", -2, -6)
    listHolder:SetPoint("BOTTOMRIGHT", mainCard, "BOTTOMRIGHT", -6, 6)

    local peersScroll = Theme:CreateScrollList(listHolder, 42, CreatePeerRow, UpdatePeerRow)
    peersScroll.container:SetAllPoints()

    local eventsScroll = Theme:CreateScrollList(listHolder, 54, CreateEventRow, UpdateEventRow)
    eventsScroll.container:SetAllPoints()
    eventsScroll.container:Hide()

    local evtItems = { evtFilterBtn, evtAllyBtn, newEventBtn, pollsBtn }
    local profItems = { profViewBtn, profFilterBtn, profSourceBtn, profBtn, profAskBtn, locksRefreshBtn, profSearch }
    local dipItems = { dipFilterBtn, dipAddBtn, dipAuthBtn }
    local hierItems = { hierDipBtn, hierRulesBtn, hierAllyBtn }

    ReflowClanPanel = function()
        if not panel or not topHeader then return end
        local clanContainer = embedContainers.clan
        local isGuildEmbedded = IsSingleEmbedActive("clan") and clanContainer ~= nil and panel:GetParent() == clanContainer.content
        local isEmbedded = isGuildEmbedded or (embeddedState.active == true)
        local pw = math.floor((panel:GetWidth() or 700) + 0.5)
        if pw <= 40 then pw = 700 end
        local leftPad = isEmbedded and 58 or 2
        local activeContainer = isGuildEmbedded and clanContainer or frame
        local isCompactHdr = pw < 540
        local hdrGap = isCompactHdr and 4 or 6
        local rClear = 6
        if activeContainer then
            local sBtn = (activeContainer.settingsCompactBtn and activeContainer.settingsCompactBtn:IsShown() and activeContainer.settingsCompactBtn)
                or (not isCompactHdr and activeContainer.settingsBtn)
                or activeContainer.settingsCompactBtn
            local sW = (sBtn and sBtn.GetWidth and sBtn:GetWidth()) or (isCompactHdr and 22 or 100)
            rClear = rClear + math.floor(sW + 0.5) + hdrGap
            if activeContainer.updateBtn and activeContainer.updateBtn:IsShown() then
                local uW = activeContainer.updateBtn:GetWidth() or (isCompactHdr and 22 or 90)
                rClear = rClear + math.floor(uW + 0.5) + hdrGap
            end
            if activeContainer.quickBtn and activeContainer.quickBtn:IsShown() then
                local qW = activeContainer.quickBtn:GetWidth() or 18
                rClear = rClear + math.floor(qW + 0.5) + hdrGap
            end
            if (not isGuildEmbedded) and activeContainer.headerHelp and activeContainer.headerHelp:IsShown() then
                local hW = activeContainer.headerHelp:GetWidth() or 18
                rClear = rClear + math.floor(hW + 0.5) + hdrGap
            end
        else
            rClear = isCompactHdr and 56 or 146
        end
        local rightPad = isEmbedded and (-math.ceil(rClear)) or -2

        local activeToolBar = peersToolBar
        if clanRightView == "events" then
            activeToolBar = eventsToolBar
        elseif clanRightView == "prof" or clanRightView == "locks" then
            activeToolBar = profToolBar
        elseif clanRightView == "diplomacy" then
            activeToolBar = dipToolBar
        elseif clanRightView == "hierarchy" then
            activeToolBar = hierToolBar
        end
        SyncClanCtxToolbarLayout(mainCard, guildHeroBar, ctxBar, activeToolBar)

        local radarVis = (radarBtn and radarBtn:IsShown()) and 1 or 0
        local infoVis = (clanInfoBtn and clanInfoBtn:IsShown()) and 1 or 0
        local radarW = radarBtn and math.floor((radarBtn._scAutoFitW or radarBtn:GetWidth() or 0) + 0.5) or 0
        local fltW = clanFilterBtn and math.floor((clanFilterBtn._scAutoFitW or clanFilterBtn:GetWidth() or 84) + 0.5) or 84
        local clanSig = pw .. ":" .. (isEmbedded and 1 or 0) .. ":" .. leftPad .. ":" .. rightPad
            .. ":" .. tostring(clanRightView) .. ":" .. radarVis .. ":" .. infoVis .. ":" .. radarW .. ":" .. fltW
        if panel._scClanReflowSig == clanSig then
            return
        end
        panel._scClanReflowSig = clanSig

        topHeader:ClearAllPoints()
        topHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", leftPad, -2)
        topHeader:SetPoint("TOPRIGHT", panel, "TOPRIGHT", rightPad, -2)

        local sbTargetW = (pw > 0 and pw < 560) and 118 or 174
        if math.abs((sidebar:GetWidth() or 0) - sbTargetW) >= 1 then
            sidebar:SetWidth(sbTargetW)
        end

        -- Layout bottom bar right-to-left (skip hidden buttons cleanly)
        local cursor = bottomBar
        local function ChainLeft(btn, hBtn)
            if not (btn and btn:IsShown()) then
                return
            end
            if hBtn and hBtn:IsShown() then
                hBtn:ClearAllPoints()
                hBtn:SetPoint("RIGHT", cursor, (cursor == bottomBar) and "RIGHT" or "LEFT", -6, 0)
                btn:ClearAllPoints()
                btn:SetPoint("RIGHT", hBtn, "LEFT", -3, 0)
            else
                btn:ClearAllPoints()
                btn:SetPoint("RIGHT", cursor, (cursor == bottomBar) and "RIGHT" or "LEFT", -6, 0)
            end
            cursor = btn
        end
        ChainLeft(radarBtn, radarHelp)
        ChainLeft(clanInfoBtn, clanInfoHelp)
        guildMotd:SetPoint("RIGHT", cursor, "LEFT", -8, 0)

        -- Reflow active contextual toolbar
        local ctxW = math.floor((ctxBar:GetWidth() or 0) + 0.5)
        if ctxW <= 20 then
            ctxW = math.max(380, pw - sbTargetW - 28)
        end
        if guildInviteBtn then
            Theme:ConfigureIconButton(guildInviteBtn, 26, 22, "Interface\\PaperDollInfoFrame\\Character-Plus", {
                size = 14,
                color = { 0.45, 0.95, 0.55 },
            })
        end
        local rightReserved = math.floor((guildInviteBtn._scAutoFitW or guildInviteBtn:GetWidth() or 26) + 0.5)
            + math.floor((historyBtn._scAutoFitW or historyBtn:GetWidth() or 24) + 0.5)
            + math.floor((historyHelp:GetWidth() or 16) + 0.5)
            + fltW
            + math.floor((peersHelp:GetWidth() or 16) + 0.5)
            + 38
        if peerSearch and peerSearch.SetWidth then
            local psw = math.floor(math.max(76, math.min(180, ctxW - rightReserved)) + 0.5)
            if math.abs((peerSearch:GetWidth() or 0) - psw) >= 1 then
                peerSearch:SetWidth(psw)
            end
        end
        if not peersToolBar._legendBtn then
            peersToolBar._legendBtn = Theme:CreateLegendTag(peersToolBar, function()
                return {
                    { tex = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", title = L["Filters"], desc = L["Presence / Status"] .. " · " .. L["Rank"] .. " · " .. L["Class"] },
                    { tex = "Interface\\Icons\\INV_Misc_PocketWatch_01", title = L["Guild Roster History"] },
                    { tex = "Interface\\PaperDollInfoFrame\\Character-Plus", title = L["Guild Invite"] },
                    { tex = (FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online"), title = L["Online"] .. " / " .. L["Offline"], desc = L["Live Guild member online status"] },
                    { title = "|cffffd24d*|r · |cff3fb950[SC]|r · [AFK] · [DND]", desc = L["Favorite · SocialCentral · Away · Busy"] },
                }
            end)
        end
        if peersToolBar._legendBtn then
            local legW = math.floor((peersToolBar._legendBtn:GetWidth() or 68) + 0.5)
            local searchRight = math.floor((peerSearch and peerSearch:GetWidth() or 120) + 0.5) + 28
            if (ctxW - rightReserved - searchRight) >= (legW + 10) then
                peersToolBar._legendBtn:ClearAllPoints()
                peersToolBar._legendBtn:SetPoint("RIGHT", clanFilterBtn, "LEFT", -6, 0)
                peersToolBar._legendBtn:Show()
            else
                peersToolBar._legendBtn:Hide()
            end
        end
        local ctxH = 24
        if clanRightView == "events" then
            ctxH = FlowButtonGroup(eventsToolBar, evtItems, 3, 3, 0)
        elseif clanRightView == "prof" or clanRightView == "locks" then
            if profSearch and profSearch.SetWidth then
                local prw = math.max(96, math.min(170, math.floor(ctxW * 0.28)))
                if math.abs((profSearch:GetWidth() or 0) - prw) >= 1 then
                    profSearch:SetWidth(prw)
                end
            end
            ctxH = FlowButtonGroup(profToolBar, profItems, 3, 3, 0)
        elseif clanRightView == "diplomacy" then
            ctxH = FlowButtonGroup(dipToolBar, dipItems, 3, 3, 0)
        elseif clanRightView == "hierarchy" then
            ctxH = FlowButtonGroup(hierToolBar, hierItems, 3, 3, 0)
        end
        local targetCtxH = math.max(24, ctxH)
        if math.abs((ctxBar:GetHeight() or 0) - targetCtxH) >= 1 then
            ctxBar:SetHeight(targetCtxH)
        end
        if listHolder._scAnchorCtx ~= ctxBar then
            listHolder._scAnchorCtx = ctxBar
            listHolder:ClearAllPoints()
            listHolder:SetPoint("TOPLEFT", ctxBar, "BOTTOMLEFT", -2, -6)
            listHolder:SetPoint("BOTTOMRIGHT", mainCard, "BOTTOMRIGHT", -6, 6)
        end
    end
    panel:SetScript("OnSizeChanged", function()
        if ReflowClanPanel then ReflowClanPanel() end
    end)

    panel.sidebar = sidebar
    panel.mainCard = mainCard
    panel.guildHeroBar = guildHeroBar
    panel.heroSummaryLbl = heroSummaryLbl
    panel.heroRankLbl = heroRankLbl
    panel.heroDetailLbl = heroDetailLbl
    panel.bottomBar = bottomBar
    panel.guildHead = guildHead
    panel.guildName = guildName
    panel.guildCounts = guildCounts
    panel.guildMotd = guildMotd
    panel.motdEditBtn = motdEditBtn
    panel.statusBtn = statusBtn
    panel.clanInfoBtn = clanInfoBtn
    panel.radarBtn = radarBtn
    panel.radarHelp = radarHelp
    panel.syncStatus = syncStatus
    panel.eventsScroll = eventsScroll
    panel.peerSearch = peerSearch
    panel.clanFilterBtn = clanFilterBtn
    panel.guildInviteBtn = guildInviteBtn
    panel.newEventBtn = newEventBtn
    panel.dipFilterBtn = dipFilterBtn
    panel.dipAddBtn = dipAddBtn
    panel.dipAuthBtn = dipAuthBtn
    panel.hierToolBar = hierToolBar
    panel.hierDipBtn = hierDipBtn
    panel.hierRulesBtn = hierRulesBtn
    panel.hierAllyBtn = hierAllyBtn
    panel.profBtn = profBtn
    panel.profAskGuildBtn = profAskBtn
    panel.profFilterBtn = profFilterBtn
    panel.profSourceBtn = profSourceBtn
    panel.locksRefreshBtn = locksRefreshBtn
    panel.profSearch = profSearch
    if clanProfQuery ~= "" and profSearch and profSearch.SetText then
        profSearch:SetText(clanProfQuery)
    end
    panel.openLfgFinderBtn = openLfgFinderBtn
    panel.peersScroll = peersScroll
    panel.peersToolBar = peersToolBar
    panel.eventsToolBar = eventsToolBar
    panel.evtFilterBtn = evtFilterBtn
    panel.evtAllyBtn = evtAllyBtn
    panel.profToolBar = profToolBar
    panel.profViewBtn = profViewBtn
    panel.dipToolBar = dipToolBar
    panel:HookScript("OnShow", function(self)
        if self._dirty then
            UpdateClanPanel()
        end
    end)
    panel:Hide()
    return panel
end

local SORT_MODES = {
    { id = "status", label = L["Sort: Status"] },
    { id = "name", label = L["Sort: Name"] },
    { id = "recent", label = L["Sort: Recent"] },
}

local function GetSortLabel(mode)
    for _, entry in ipairs(SORT_MODES) do
        if entry.id == mode then
            return entry.label
        end
    end
    return L["Sort: Status"]
end

local THEME_ORDER = { "blizzard", "dark", "native" }
local THEME_LABELS = {
    blizzard = L["Blizzard Official"],
    dark = L["Modern Theme"],
    native = L["Classic Gold"],
}

local function ReflowTabStrip()
    if not frame or not frame.tabBar or #tabOrder == 0 then
        return
    end
    local isBlizz = Theme:IsBlizzard()
    local measuredAvail = math.floor((frame.tabBar:GetWidth() or 0) + 0.5)
    local targetAvail = embeddedState.active and frame.tabBar._scTargetAvailW or nil
    local avail
    if targetAvail and targetAvail > 0 then
        avail = (measuredAvail > 0) and math.min(measuredAvail, targetAvail) or targetAvail
    else
        avail = measuredAvail
    end
    if avail <= 0 then
        avail = math.floor(((frame:GetWidth() or 790) - (isBlizz and 78 or 24)) + 0.5)
    end
    local visibleTabs = {}
    local sigParts = { tostring(avail), isBlizz and "B" or "M", Theme:GetThemeName() }
    for _, info in ipairs(tabOrder) do
        local allowed = IsTabAllowed(info.id)
        if info.btn:IsShown() ~= allowed then
            info.btn:SetShown(allowed)
        end
        if allowed then
            visibleTabs[#visibleTabs + 1] = info
            sigParts[#sigParts + 1] = info.id .. "=" .. tostring(info.btn._scFullText or info.baseLabel or "")
        end
    end
    if #visibleTabs == 0 then
        return
    end
    local stripSig = table.concat(sigParts, "|")
    if frame.tabBar._scLastStripSig ~= stripSig then
        frame.tabBar._scLastStripSig = stripSig
        local pad = isBlizz and 18 or 16
        local gap = 4
        local minW = (avail < 260) and 38 or 46
        local widths = {}
        local function MeasureAll(p)
            local sum = 0
            for i, info in ipairs(visibleTabs) do
                local w = math.floor((Theme:AutoFitButton(info.btn, minW, p, 220) or minW) + 0.5)
                widths[i] = w
                sum = sum + w
            end
            return sum + gap * math.max(0, #visibleTabs - 1)
        end
        local total = MeasureAll(pad)
        if total > avail and avail > 80 then
            pad = 10
            gap = 2
            total = MeasureAll(pad)
        end
        if total > avail and avail > 80 then
            local excess = total - avail
            local trimmable = 0
            for i = 1, #widths do
                trimmable = trimmable + math.max(0, widths[i] - minW)
            end
            if trimmable > 0 then
                local ratio = math.min(1, excess / trimmable)
                for i, info in ipairs(visibleTabs) do
                    local cut = math.ceil(math.max(0, widths[i] - minW) * ratio)
                    local nw = math.max(minW, widths[i] - cut)
                    info.btn._scAutoFitW = nw
                    if math.abs((info.btn:GetWidth() or 0) - nw) >= 1 then
                        info.btn:SetWidth(nw)
                    end
                    info.btn._scTruncated = nw < widths[i]
                end
            end
        else
            for _, info in ipairs(visibleTabs) do
                info.btn._scTruncated = false
            end
        end
        local prev
        for _, info in ipairs(visibleTabs) do
            info.btn:ClearAllPoints()
            if not prev then
                info.btn:SetPoint("LEFT", frame.tabBar, "LEFT", 0, 0)
            else
                info.btn:SetPoint("LEFT", prev, "RIGHT", gap, 0)
            end
            if info.btn.SetClipsChildren and not info.btn._scClipsInit then
                info.btn._scClipsInit = true
                info.btn:SetClipsChildren(true)
            end
            prev = info.btn
        end
    end
    for _, info in ipairs(visibleTabs) do
        if info.btn._scThemeKey ~= Theme:GetThemeName() then
            Theme:StyleButton(info.btn, "tab")
        end
        if info.id then
            Theme:SetButtonActive(info.btn, info.id == activeTab, "tab")
        end
    end
end

local function DisableChromeMouseRecursive(root, skipObj, depth)
    if not root or (depth or 0) <= 0 or root == skipObj or (frame and (root == frame.closeBtn or root == frame.blizzCloseBtn)) then
        return
    end
    if root.IsForbidden then
        local okF, forb = pcall(root.IsForbidden, root)
        if not okF or forb then return end
    end
    if root.EnableMouse then
        pcall(root.EnableMouse, root, false)
    end
    if root.SetMouseClickEnabled then
        pcall(root.SetMouseClickEnabled, root, false)
    end
    if root.SetMouseMotionEnabled then
        pcall(root.SetMouseMotionEnabled, root, false)
    end
    if frame and frame._scBeginDrag and Theme and Theme.AttachDragHandle then
        pcall(Theme.AttachDragHandle, Theme, root, frame)
    end
    if root.GetChildren then
        local children = { root:GetChildren() }
        for i = 1, #children do
            DisableChromeMouseRecursive(children[i], skipObj, (depth or 1) - 1)
        end
    end
end

local function MaxHierarchyFrameLevel(root, depth, skipA, skipB)
    local maxLevel = 0
    if not root or (depth or 0) <= 0 or root == skipA or root == skipB then
        return maxLevel
    end
    if root.GetFrameLevel then
        local lvl = root:GetFrameLevel() or 0
        if lvl > maxLevel then
            maxLevel = lvl
        end
    end
    if root.GetChildren then
        local children = { root:GetChildren() }
        for i = 1, #children do
            local childMax = MaxHierarchyFrameLevel(children[i], (depth or 1) - 1, skipA, skipB)
            if childMax > maxLevel then
                maxLevel = childMax
            end
        end
    end
    return maxLevel
end

local function RaiseWindowCloseButton(btn)
    if not btn or not frame then
        return
    end
    local strata = frame:GetFrameStrata() or "MEDIUM"
    if btn.GetFrameStrata and btn:GetFrameStrata() ~= strata then
        btn:SetFrameStrata(strata)
    end
    -- ButtonFrameTemplate.NineSlice renders at hardcoded XML frameLevel 500+,
    -- so elevate the active close button strictly above every chrome descendant
    -- WITHOUT feeding the close button's own level back into MaxHierarchyFrameLevel.
    local baseLvl = math.max(1, math.min(4500, frame:GetFrameLevel() or 1))
    local blizzCloseRef = frame.blizzChrome and frame.blizzChrome.CloseButton or nil
    local chromeMax = frame.blizzChrome and MaxHierarchyFrameLevel(frame.blizzChrome, 3, btn, blizzCloseRef) or baseLvl
    chromeMax = math.min(baseLvl + 40, chromeMax)
    local topLevel = math.max(
        baseLvl + 60,
        frame.header and ((frame.header:GetFrameLevel() or 0) + 12) or 0,
        frame.blizzTitleDrag and ((frame.blizzTitleDrag:GetFrameLevel() or 0) + 4) or 0,
        frame.grip and ((frame.grip:GetFrameLevel() or 0) + 10) or 0,
        chromeMax + 40
    )
    btn:SetFrameLevel(math.min(9600, topLevel))
end

local function SetupFallbackCloseButton(btn)
    if not btn then return end
    btn:SetSize(22, 22)
    btn:SetHitRectInsets(-5, -5, -5, -5)
    if not btn._fallbackBuilt then
        btn._fallbackBuilt = true
        btn._bg = btn:CreateTexture(nil, "BACKGROUND")
        btn._bg:SetAllPoints()
        btn._bg:SetColorTexture(0.55, 0.10, 0.10, 1.0)
        btn._fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        btn._fs:SetPoint("CENTER", 0, 0)
        btn._fs:SetText("X")
        btn._fs:SetTextColor(1.0, 0.86, 0.30, 1.0)
    end
end

local function ConfigureBlizzCloseButton(btn)
    if not btn or not frame then
        return
    end
    btn:SetScript("OnClick", function() frame:Hide() end)
    btn:SetHitRectInsets(-5, -5, -5, -5)
    RaiseWindowCloseButton(btn)
    btn:Show()
end

local EMBED_HOST_SPECS = {
    clan = {
        frameName = "SocialCentralGuildEmbeddedFrame",
        pad = { 4, 4, 21, 4 },
        contentTop = -6,
        minEmbedLevel = 520,
        hideHookKey = "_scGuildEmbedHideHooked",
        getPanel = function()
            if not clanPanel and frame and frame.content then
                clanPanel = CreateClanPanel(frame.content)
            end
            return clanPanel
        end,
        updatePanel = function() UpdateClanPanel() end,
        reflowPanel = function() if ReflowClanPanel then ReflowClanPanel() end end,
        onHideModals = function(standaloneActive)
            if not standaloneActive then
                if eventModalFrame then eventModalFrame:Hide() end
                if clanInfoModalFrame then clanInfoModalFrame:Hide() end
                if diplomacyModalFrame then diplomacyModalFrame:Hide() end
                if allianceModalFrame then allianceModalFrame:Hide() end
            end
        end,
    },
    alts = {
        frameName = "SocialCentralAltsEmbeddedFrame",
        pad = { 4, 4, 21, 4 },
        contentTop = -6,
        minEmbedLevel = 520,
        hideHookKey = "_scAltsEmbedHideHooked",
        getPanel = function()
            if not altsPanel and ns.SocialPanels and ns.SocialPanels.CreateAltsPanel and frame and frame.content then
                altsPanel = ns.SocialPanels:CreateAltsPanel(frame.content)
                if altsPanel then altsPanel:Hide() end
            end
            if altsPanel and pendingAltsNav and altsPanel.ApplyNavigation then
                altsPanel:ApplyNavigation(pendingAltsNav)
                pendingAltsNav = nil
            end
            return altsPanel
        end,
        updatePanel = function()
            if altsPanel and altsPanel.Refresh then altsPanel:Refresh(false) end
        end,
        reflowPanel = function()
            if altsPanel and altsPanel.Relayout then
                altsPanel:Relayout()
            elseif altsPanel and altsPanel.Refresh then
                altsPanel:Refresh(false)
            end
        end,
    },
    group = {
        frameName = "SocialCentralGroupEmbeddedFrame",
        pad = { 6, 6, 56, 6 },
        contentTop = -32,
        minEmbedLevel = 520,
        hideHookKey = "_scGroupEmbedHideHooked",
        getPanel = function()
            if not groupPanel and ns.SocialPanels and ns.SocialPanels.CreateGroupPanel and frame and frame.content then
                groupPanel = ns.SocialPanels:CreateGroupPanel(frame.content)
                if groupPanel then groupPanel:Hide() end
            end
            return groupPanel
        end,
        updatePanel = function()
            if groupPanel and groupPanel.Refresh then groupPanel:Refresh(false) end
        end,
    },
}

function UI:OpenGuildRosterHistoryModal()
    local m = UI._rosterHistoryModal
    if not m then
        m = CreateFrame("Frame", "SocialCentralRosterHistoryModal", UIParent, "BackdropTemplate")
        m:Hide()
        m:SetSize(540, 420)
        m:SetPoint("CENTER")
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(840)
        m:SetToplevel(true)
        m:EnableMouse(true)
        if Theme and Theme.MakeMovable then
            Theme:MakeMovable(m, {
                skipAutoRestore = true,
                onStop = function(selfModal)
                    if Theme and Theme.SaveFramePosition then
                        Theme:SaveFramePosition(selfModal, "rosterHistoryModal")
                    end
                end,
            })
        else
            m:SetMovable(true)
            m:SetClampedToScreen(true)
            m:RegisterForDrag("LeftButton")
        end
        if UISpecialFrames then
            local exists = false
            for _, fn in ipairs(UISpecialFrames) do
                if fn == "SocialCentralRosterHistoryModal" then exists = true; break end
            end
            if not exists then table.insert(UISpecialFrames, "SocialCentralRosterHistoryModal") end
        end
        Theme:ApplyBackdrop(m, "frame")
        if Theme and Theme.RestoreFramePosition then
            Theme:RestoreFramePosition(m, "rosterHistoryModal")
        end

        m._filter = "ALL"
        m._query = ""

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetText(L["Guild Roster History"])
        m.title = title

        local closeBtn = Theme:CreateButton(m, 24, 22, "X", "default")
        closeBtn:SetPoint("TOPRIGHT", -10, -10)
        closeBtn:SetScript("OnClick", function() m:Hide() end)
        m.closeBtn = closeBtn

        m.helpBtn = AddHelp(
            m,
            closeBtn,
            L["Help: Guild Roster History"],
            L["Tracks guild members who joined, left, or changed ranks with timestamps and levels so officers can review recent roster activity."],
            L["Filter by Joins, Leaves, or Ranks, search by player name, adjust history retention (Keep:), or copy the filtered log."],
            "RIGHT",
            "LEFT",
            -4,
            0,
            { target = m }
        )
        title:SetPoint("TOPRIGHT", m.helpBtn or closeBtn, "LEFT", -8, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)

        local summary = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        summary:SetPoint("RIGHT", m.helpBtn or closeBtn, "LEFT", -8, 0)
        summary:SetJustifyH("LEFT")
        summary:SetWordWrap(false)
        m.summary = summary

        local bar = CreateFrame("Frame", nil, m)
        bar:SetPoint("TOPLEFT", 12, -52)
        bar:SetPoint("TOPRIGHT", -12, -52)
        bar:SetHeight(24)

        local clearBtn = Theme:CreateButton(bar, 24, 22, "", "danger")
        Theme:ConfigureIconButton(clearBtn, 24, 22, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", {
            size = 13,
            color = { 1.0, 0.45, 0.45 },
            title = L["Clear History"],
            desc = L["Shows recent guild joins, leaves, and rank changes observed on your character."],
        })
        clearBtn:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
        clearBtn:SetScript("OnClick", function()
            local list = ns.Clan and ns.Clan.GetRosterHistory and ns.Clan:GetRosterHistory() or {}
            if #list == 0 then return end
            UI:OpenConfirmModal({
                title = L["Clear History"],
                message = L["Are you sure you want to clear all %d saved guild roster history entries?"]:format(#list),
                confirmText = L["Clear"],
                confirmVariant = "danger",
                onConfirm = function()
                    if ns.Clan and ns.Clan.ClearRosterHistory then
                        ns.Clan:ClearRosterHistory()
                    end
                    if m.Refresh then m:Refresh(true) end
                end,
            })
        end)
        m.clearBtn = clearBtn

        local copyBtn = Theme:CreateButton(bar, 24, 22, "", "default")
        Theme:ConfigureIconButton(copyBtn, 24, 22, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", {
            size = 14,
            title = L["Copy History"],
            desc = L["Click 'History' to view and optionally copy the recent Guild Roster changelog."],
        })
        copyBtn:SetPoint("RIGHT", clearBtn, "LEFT", -4, 0)
        copyBtn:SetScript("OnClick", function()
            local rows = m._filteredRows or {}
            if #rows == 0 then return end
            local kindMap = {
                JOINED = L["Joined Guild"],
                LEFT = L["Left Guild"],
                PROMOTED = L["Promoted"],
                DEMOTED = L["Demoted"],
                RANK = L["Rank Changed"],
            }
            local lines = {}
            for _, h in ipairs(rows) do
                local stamp = h.ts and date("%Y-%m-%d %H:%M", h.ts) or ""
                local kLbl = kindMap[h.kind] or h.kind or "?"
                local lvlTxt = (h.level and h.level > 0) and (" Lv" .. tostring(h.level)) or ""
                local det = (h.detail and h.detail ~= "") and (" (" .. h.detail .. ")") or ""
                local zTxt = (h.zone and h.zone ~= "") and (" · " .. h.zone) or ""
                lines[#lines + 1] = string.format("[%s] %s: %s%s%s%s", stamp, kLbl, h.name or "?", lvlTxt, det, zTxt)
            end
            UI:OpenCopyModal(table.concat(lines, "\n"), L["Guild Roster History"], L["Shows recent guild joins, leaves, and rank changes observed on your character."])
        end)
        m.copyBtn = copyBtn

        local limitHelp = AddHelp(
            bar,
            bar,
            L["Help: Guild Roster History Limit"],
            L["Controls how many recent guild joins, departures, and rank changes are stored locally (up to 500 lightweight entries, ~60 days retention)."],
            L["Pick a limit from the menu without impacting game performance; older entries are trimmed automatically."],
            "RIGHT",
            "RIGHT",
            -56,
            0
        )
        limitHelp:ClearAllPoints()
        limitHelp:SetPoint("RIGHT", copyBtn, "LEFT", -4, 0)

        local limitBtn = Theme:CreateButton(bar, 86, 22, L["Keep: %d"]:format(50) .. " v", "default")
        Theme:AutoFitButton(limitBtn, 72, 12, 118)
        limitBtn:SetPoint("RIGHT", limitHelp, "LEFT", -3, 0)
        limitBtn:SetScript("OnClick", function(selfBtn)
            local choices = { 25, 50, 100, 200, 500 }
            local curLim = ns.Clan and ns.Clan.GetRosterHistoryLimit and ns.Clan:GetRosterHistoryLimit() or 50
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                    root:CreateTitle(L["History Limit"])
                    for _, n in ipairs(choices) do
                        local val = n
                        root:CreateRadio(L["%d entries"]:format(val), function()
                            return curLim == val
                        end, function()
                            if ns.Clan and ns.Clan.SetRosterHistoryLimit then
                                ns.Clan:SetRosterHistoryLimit(val)
                            end
                            if m.Refresh then m:Refresh(false) end
                        end)
                    end
                end)
            else
                local nextVal = choices[1]
                for idx, n in ipairs(choices) do
                    if n == curLim then nextVal = choices[(idx % #choices) + 1]; break end
                end
                if ns.Clan and ns.Clan.SetRosterHistoryLimit then
                    ns.Clan:SetRosterHistoryLimit(nextVal)
                end
                if m.Refresh then m:Refresh(false) end
            end
        end)
        m.limitBtn = limitBtn

        local filterDefs = {
            { id = "ALL", title = L["All"], tex = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", sz = 15, col = { 0.96, 0.76, 0.22 } },
            { id = "JOINED", title = L["Joined Guild"], tex = "Interface\\PaperDollInfoFrame\\Character-Plus", sz = 14, col = { 0.28, 0.88, 0.45 }, icoCol = { 0.45, 0.95, 0.55 } },
            { id = "LEFT", title = L["Left Guild"], tex = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", sz = 13, col = { 0.96, 0.35, 0.35 }, icoCol = { 1.0, 0.45, 0.45 } },
            { id = "RANK", title = L["Rank Changed"], tex = "Interface\\GroupFrame\\UI-Group-LeaderIcon", sz = 15, col = { 0.40, 0.78, 1.0 } },
        }
        m.filterBtns = {}
        local anchorRight = limitBtn
        for idx = #filterDefs, 1, -1 do
            local def = filterDefs[idx]
            local fBtn = Theme:CreateButton(bar, 24, 22, "", "default")
            fBtn._fId = def.id
            Theme:ConfigureIconButton(fBtn, 24, 22, def.tex, {
                size = def.sz,
                color = def.icoCol,
                toggle = true,
                active = (def.id == "ALL"),
                activeColor = def.col,
                title = def.title,
            })
            fBtn:SetPoint("RIGHT", anchorRight, "LEFT", -3, 0)
            fBtn:SetScript("OnClick", function()
                m._filter = def.id
                if m.Refresh then m:Refresh(true) end
            end)
            m.filterBtns[#m.filterBtns + 1] = fBtn
            anchorRight = fBtn
        end

        local searchBox = Theme:CreateEditBox(bar, {
            height = 22,
            placeholder = L["Search..."],
            clearButton = true,
        })
        searchBox:SetPoint("LEFT", bar, "LEFT", 0, 0)
        searchBox:SetPoint("RIGHT", anchorRight, "LEFT", -6, 0)
        searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        searchBox:HookScript("OnTextChanged", function(self)
            m._query = Compat.Trim(self:GetText() or ""):lower()
            if m.Refresh then m:Refresh(true) end
        end)
        m.searchBox = searchBox

        local listHolder = CreateFrame("Frame", nil, m, "BackdropTemplate")
        listHolder:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8)
        listHolder:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -12, 12)
        Theme:ApplyBackdrop(listHolder, "inset")
        m.listHolder = listHolder

        local scroll = Theme:CreateScrollList(listHolder, 44, function(rowParent, _, rowHeight)
            local row = CreateFrame("Frame", nil, rowParent, "BackdropTemplate")
            row:SetHeight(rowHeight)

            row.stripe = row:CreateTexture(nil, "ARTWORK", nil, 2)
            row.stripe:SetWidth(3)
            row.stripe:SetPoint("TOPLEFT", 2, -4)
            row.stripe:SetPoint("BOTTOMLEFT", 2, 4)

            row.classIco = row:CreateTexture(nil, "ARTWORK", nil, 2)
            row.classIco:SetSize(22, 22)
            row.classIco:SetPoint("LEFT", 10, 0)
            row.classIco:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")

            row.timeTop = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.timeTop:SetPoint("TOPRIGHT", -8, -6)
            row.timeTop:SetJustifyH("RIGHT")

            row.timeBot = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.timeBot:SetPoint("BOTTOMRIGHT", -8, 6)
            row.timeBot:SetJustifyH("RIGHT")

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.nameText:SetPoint("TOPLEFT", row.classIco, "TOPRIGHT", 8, 5)
            row.nameText:SetPoint("RIGHT", row.timeTop, "LEFT", -8, 0)
            row.nameText:SetJustifyH("LEFT")
            row.nameText:SetWordWrap(false)

            row.subText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.subText:SetPoint("BOTTOMLEFT", row.classIco, "BOTTOMRIGHT", 8, -4)
            row.subText:SetPoint("RIGHT", row.timeBot, "LEFT", -8, 0)
            row.subText:SetJustifyH("LEFT")
            row.subText:SetWordWrap(false)
            return row
        end, function(row, item, idx, pal)
            if idx % 2 == 0 then
                Theme:ApplyBackdrop(row, "rowAlt", pal)
            else
                Theme:ApplyBackdrop(row, "row", pal)
            end
            local kind = item.kind or "RANK"
            local sr, sg, sb, badgeHex, badgeLbl = 0.40, 0.78, 1.0, "|cff58a6ff", L["Rank Changed"]
            if kind == "JOINED" then
                sr, sg, sb, badgeHex, badgeLbl = 0.25, 0.85, 0.42, "|cff3fb950", L["Joined Guild"]
            elseif kind == "LEFT" then
                sr, sg, sb, badgeHex, badgeLbl = 0.92, 0.32, 0.32, "|cfff54747", L["Left Guild"]
            elseif kind == "PROMOTED" then
                sr, sg, sb, badgeHex, badgeLbl = 0.30, 0.82, 1.0, "|cff58c4ff", L["Promoted"]
            elseif kind == "DEMOTED" then
                sr, sg, sb, badgeHex, badgeLbl = 0.98, 0.62, 0.22, "|cffff9b3d", L["Demoted"]
            end
            row.stripe:SetColorTexture(sr, sg, sb, 0.95)

            local coords = item.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[item.classFile]
            if coords then
                row.classIco:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                row.classIco:SetTexCoord(coords[1] + 0.02, coords[2] - 0.02, coords[3] + 0.02, coords[4] - 0.02)
                row.classIco:SetAlpha(1.0)
                row.classIco:Show()
            else
                row.classIco:SetTexture("Interface\\GossipFrame\\TabardGossipIcon")
                row.classIco:SetTexCoord(0, 1, 0, 1)
                row.classIco:SetAlpha(0.75)
                row.classIco:Show()
            end

            local nameHex = item.classFile and Compat.ClassHex(item.classFile) or "|cffffffff"
            local lvlPart = (item.level and item.level > 0) and (" |cff9da7b5" .. L["Lv %d"]:format(item.level) .. "|r") or ""
            row.nameText:SetText(nameHex .. tostring(item.name or "?") .. "|r" .. lvlPart)

            local subParts = { badgeHex .. badgeLbl .. "|r" }
            if item.detail and item.detail ~= "" then
                subParts[#subParts + 1] = "|cffe6edf3" .. tostring(item.detail) .. "|r"
            end
            if item.zone and item.zone ~= "" then
                subParts[#subParts + 1] = "|cff9da7b5" .. tostring(item.zone) .. "|r"
            end
            row.subText:SetText(table.concat(subParts, " · "))

            row.timeTop:SetText(item.ts and date("%d/%m %H:%M", item.ts) or "")
            row.timeTop:SetTextColor(0.84, 0.88, 0.94)
            row.timeBot:SetText(item.ts and Compat.FormatRelativeTime(item.ts, L) or "")
        end)
        scroll.container:ClearAllPoints()
        scroll.container:SetPoint("TOPLEFT", listHolder, "TOPLEFT", 4, -4)
        scroll.container:SetPoint("BOTTOMRIGHT", listHolder, "BOTTOMRIGHT", -4, 4)
        m.scroll = scroll

        function m:Refresh(resetScroll)
            local p = Theme:GetPalette()
            Theme:ApplyBackdrop(self, "frame", p)
            Theme:ApplyBackdrop(self.listHolder, "inset", p)
            local tc = p.textGold or p.accent or { 1.0, 0.85, 0.25 }
            self.title:SetTextColor(tc[1], tc[2], tc[3])

            local lim = ns.Clan and ns.Clan.GetRosterHistoryLimit and ns.Clan:GetRosterHistoryLimit() or 50
            Theme:SetButtonText(self.limitBtn, L["Keep: %d"]:format(lim) .. " v")
            Theme:AutoFitButton(self.limitBtn, 72, 12, 118)

            for _, fBtn in ipairs(self.filterBtns) do
                Theme:SetIconToggle(fBtn, self._filter == fBtn._fId)
            end

            local all = (ns.Clan and ns.Clan.GetRosterHistory and ns.Clan:GetRosterHistory()) or {}
            local cJoin, cLeft, cRank = 0, 0, 0
            local filtered = {}
            local q = self._query or ""
            for _, h in ipairs(all) do
                local k = h.kind or "RANK"
                if k == "JOINED" then cJoin = cJoin + 1
                elseif k == "LEFT" then cLeft = cLeft + 1
                else cRank = cRank + 1 end

                local matchKind = (self._filter == "ALL")
                    or (self._filter == "JOINED" and k == "JOINED")
                    or (self._filter == "LEFT" and k == "LEFT")
                    or (self._filter == "RANK" and (k == "RANK" or k == "PROMOTED" or k == "DEMOTED"))
                if matchKind then
                    local matchQ = (q == "")
                        or tostring(h.name or ""):lower():find(q, 1, true)
                        or tostring(h.detail or ""):lower():find(q, 1, true)
                        or tostring(h.zone or ""):lower():find(q, 1, true)
                    if matchQ then
                        filtered[#filtered + 1] = h
                    end
                end
            end
            self._filteredRows = filtered
            self.summary:SetText(string.format("%s  |cff8b949e(%d / %d)|r",
                L["%d joined · %d left · %d rank"]:format(cJoin, cLeft, cRank),
                #all,
                lim
            ))
            self.copyBtn:SetEnabled(#filtered > 0)
            self.clearBtn:SetEnabled(#all > 0)
            self.scroll:SetData(filtered, L["No guild roster changes recorded yet this session."], resetScroll)
        end

        ns:On("CLAN_UPDATED", function()
            if m and m:IsShown() then
                m:Refresh(false)
            end
        end)
        UI._rosterHistoryModal = m
    end

    m:SetParent(UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(840)
    m:SetToplevel(true)
    m:Show()
    m:Raise()
    m:Refresh(true)
end

function UI:OpenGuildRosterCsvExport()
    if not (ns.Clan and ns.Clan.GetMergedGuildMembers) then
        return
    end
    local list = ns.Clan:GetMergedGuildMembers(clanPeerQuery or "", {
        statusFilter = clanPeerStatusFilter or "all",
        rankFilter = clanPeerRankFilter,
        classFilter = clanPeerClassFilter,
        sortBy = clanPeerSortBy or "level_desc",
    }) or {}
    local function csvEsc(v)
        local s = tostring(v or ""):gsub('"', '""'):gsub("[\r\n]+", " ")
        return '"' .. s .. '"'
    end
    local lines = { "Name,Level,Class,Rank,Status,Zone,PublicNote,MainCharacter" }
    for _, m in ipairs(list) do
        local pMeta = (m.lookupKey and ns.Store)
            and ((ns.Store.GetResolvedSocialMeta and ns.Store:GetResolvedSocialMeta(m.lookupKey)) or (ns.Store.GetSocialMeta and ns.Store:GetSocialMeta(m.lookupKey)))
            or nil
        local pMain = (pMeta and pMeta.mainName and pMeta.mainName ~= "") and pMeta.mainName
            or (Compat.ExtractMainFromGuildNote and Compat.ExtractMainFromGuildNote(m.note))
            or ""
        local stStr = m.online and "Online" or (m.offlineDays and m.offlineDays > 0 and ("Offline (" .. tostring(math.floor(m.offlineDays)) .. "d)") or "Offline")
        lines[#lines + 1] = table.concat({
            csvEsc(m.displayName or ""),
            tostring(tonumber(m.level) or 0),
            csvEsc(m.classFile or ""),
            csvEsc(m.rankName or ""),
            csvEsc(stStr),
            csvEsc(m.area or ""),
            csvEsc(m.note or ""),
            csvEsc(pMain),
        }, ",")
    end
    self:OpenCopyModal(table.concat(lines, "\n"), L["Export Guild Roster (CSV)"], L["Press Ctrl+C to copy the CSV roster table (filtered to current view)."])
end

local function BuildEmbeddedHostQuickButton(parent, winKey)
    if not (Theme and Theme.CreateOfficialQuickButton and parent) then
        return nil
    end
    local titles = {
        O = L["Social & Friends (O)"],
        J = L["Guild & Communities (J)"],
        C = L["Character & My Alts (C)"],
        I = L["Group Finder (I)"],
        M = L["World Buffs (M)"],
    }
    local embedKeys = {
        O = "embedSocialWindow",
        J = "embedGuildWindow",
        C = "embedCharacterWindow",
        I = "embedLfgWindow",
        M = "embedWorldMap",
    }
    return Theme:CreateOfficialQuickButton(parent, {
        name = "SocialCentralHostQuickBtn_" .. tostring(winKey),
        size = 18,
        title = titles[winKey] or L["Official Window"],
        tooltipAnchor = "ANCHOR_BOTTOMLEFT",
        getStatusState = function()
            local s = ns.db and ns.db.settings
            local ek = embedKeys[winKey]
            if s and ek and s[ek] == false then return "off" end
            return "active"
        end,
        getTooltipLines = function()
            if winKey == "J" then
                local gwOn = not ns.db or not ns.db.settings or ns.db.settings.clanOfficialGreenWall ~= false
                return {
                    { left = L["GreenWall Official Chat Mirror (/ali)"], right = gwOn and ("|cff3fb950" .. L["On"] .. "|r") or ("|cff8b949e" .. L["Off"] .. "|r") },
                    L["Configure Guild features, export CSV roster, or disable this embedded tab."],
                }
            elseif winKey == "C" then
                local tipOn = not ns.db or not ns.db.settings or ns.db.settings.tooltipItemAlts ~= false
                return {
                    { left = L["Alt & Recipe Item Tooltips"], right = tipOn and ("|cff3fb950" .. L["On"] .. "|r") or ("|cff8b949e" .. L["Off"] .. "|r") },
                    L["Configure Alts & Tooltip integration or disable this embedded tab."],
                }
            elseif winKey == "I" then
                local mirrorOn = not ns.db or not ns.db.settings or ns.db.settings.embedLfgMirrorBar ~= false
                local hideFullOn = not ns.db or not ns.db.settings or ns.db.settings.lfgHideFullGroups ~= false
                return {
                    { left = L["Show Official Tab 1 Mirror Bar"], right = mirrorOn and ("|cff3fb950" .. L["On"] .. "|r") or ("|cff8b949e" .. L["Off"] .. "|r") },
                    { left = L["Hide Full Groups"], right = hideFullOn and ("|cff3fb950" .. L["On"] .. "|r") or ("|cff8b949e" .. L["Off"] .. "|r") },
                    L["Right-click or click to configure SocialCentral LFG features or disable Group Finder (I) integration."],
                }
            end
            local grpOn = not ns.db or not ns.db.settings or ns.db.settings.socialGroupByFolder ~= false
            local popOn = not ns.db or not ns.db.settings or ns.db.settings.socialOfficialPopupAlerts ~= false
            return {
                { left = L["Group by Folders (Collapsible)"], right = grpOn and ("|cff3fb950" .. L["On"] .. "|r") or ("|cff8b949e" .. L["Off"] .. "|r") },
                { left = L["Preventive Popup Alerts"], right = popOn and ("|cff3fb950" .. L["On"] .. "|r") or ("|cff8b949e" .. L["Off"] .. "|r") },
                L["Configure Social directory features, backup notes/ignores, or disable this embedded tab."],
            }
        end,
        buildMenu = function(root)
            root:CreateTitle("SocialCentral — " .. (titles[winKey] or winKey))
            if winKey == "O" then
                if root.CreateCheckbox then
                    root:CreateCheckbox(L["Group by Folders (Collapsible)"], function()
                        return not ns.db or not ns.db.settings or ns.db.settings.socialGroupByFolder ~= false
                    end, function()
                        if ns.db and ns.db.settings then
                            ns.db.settings.socialGroupByFolder = not (ns.db.settings.socialGroupByFolder ~= false)
                        end
                        UI:Refresh(true)
                        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                    end)
                    root:CreateCheckbox(L["Warn on official Invite, Trade & Duel popups"], function()
                        return not ns.db or not ns.db.settings or ns.db.settings.socialOfficialPopupAlerts ~= false
                    end, function()
                        if ns.db and ns.db.settings then
                            ns.db.settings.socialOfficialPopupAlerts = not (ns.db.settings.socialOfficialPopupAlerts ~= false)
                        end
                        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                    end)
                end
                root:CreateButton(L["Export / Import Social Data"] .. "...", function()
                    if ns.SocialPanels and ns.SocialPanels.OpenSocialExportImportModal then
                        ns.SocialPanels:OpenSocialExportImportModal(false)
                    end
                end)
            elseif winKey == "J" then
                if root.CreateCheckbox then
                    root:CreateCheckbox(L["Mirror Alliance Chat in Official Chat (/ali)"], function()
                        return not ns.db or not ns.db.settings or ns.db.settings.clanOfficialGreenWall ~= false
                    end, function()
                        if ns.db and ns.db.settings then
                            ns.db.settings.clanOfficialGreenWall = not (ns.db.settings.clanOfficialGreenWall ~= false)
                        end
                        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                    end)
                end
                root:CreateButton(L["Export Roster (CSV)..."], function()
                    UI:OpenGuildRosterCsvExport()
                end)
            elseif winKey == "C" then
                if root.CreateCheckbox then
                    root:CreateCheckbox(L["Show Alt item counts in item tooltips"], function()
                        return not ns.db or not ns.db.settings or ns.db.settings.tooltipItemAlts ~= false
                    end, function()
                        if ns.db and ns.db.settings then
                            ns.db.settings.tooltipItemAlts = not (ns.db.settings.tooltipItemAlts ~= false)
                        end
                        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                    end)
                    root:CreateCheckbox(L["Show 'Craftable by Alt / Guild' and Recipe hints in tooltips"], function()
                        return not ns.db or not ns.db.settings or ns.db.settings.tooltipRecipeAlts ~= false
                    end, function()
                        if ns.db and ns.db.settings then
                            ns.db.settings.tooltipRecipeAlts = not (ns.db.settings.tooltipRecipeAlts ~= false)
                        end
                        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                    end)
                end
            elseif winKey == "I" then
                if root.CreateCheckbox then
                    root:CreateCheckbox(L["Show Official Tab 1 Mirror Bar"], function()
                        return not ns.db or not ns.db.settings or ns.db.settings.embedLfgMirrorBar ~= false
                    end, function()
                        if ns.db and ns.db.settings then
                            ns.db.settings.embedLfgMirrorBar = not (ns.db.settings.embedLfgMirrorBar ~= false)
                        end
                        if ns.LFGFrameTab and ns.LFGFrameTab.UpdateNativeBridgeBar then
                            ns.LFGFrameTab:UpdateNativeBridgeBar()
                        end
                        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                    end)
                    root:CreateCheckbox(L["Hide Full Groups"], function()
                        return not ns.db or not ns.db.settings or ns.db.settings.lfgHideFullGroups ~= false
                    end, function()
                        if ns.db and ns.db.settings then
                            ns.db.settings.lfgHideFullGroups = not (ns.db.settings.lfgHideFullGroups ~= false)
                        end
                        if ns.LFGFrameTab and ns.LFGFrameTab.RefreshData then
                            ns.LFGFrameTab:RefreshData()
                        end
                        ns:Emit("LFG_BROWSE_STATE_CHANGED")
                        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                    end)
                    root:CreateCheckbox(L["Hide Saved Lockouts"], function()
                        return ns.db and ns.db.settings and ns.db.settings.lfgHideSavedLockouts == true
                    end, function()
                        if ns.db and ns.db.settings then
                            ns.db.settings.lfgHideSavedLockouts = not (ns.db.settings.lfgHideSavedLockouts == true)
                        end
                        if ns.LFGFrameTab and ns.LFGFrameTab.RefreshData then
                            ns.LFGFrameTab:RefreshData()
                        end
                        ns:Emit("LFG_BROWSE_STATE_CHANGED")
                        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                    end)
                end
            end
            if root.CreateDivider then root:CreateDivider() end
            local ek = embedKeys[winKey]
            if ek then
                root:CreateButton(L["Disable in this window"], function()
                    if ns.db and ns.db.settings then
                        ns.db.settings[ek] = false
                    end
                    if winKey == "I" and _G.LFGParentFrame then
                        UI:CloseEmbeddedIfHost(_G.LFGParentFrame)
                    elseif winKey == "J" and (_G.CommunitiesFrame or _G.GuildFrame) then
                        UI:CloseEmbeddedIfHost(_G.CommunitiesFrame or _G.GuildFrame)
                    elseif winKey == "C" and _G.CharacterFrame then
                        UI:CloseEmbeddedIfHost(_G.CharacterFrame)
                    elseif winKey == "O" and (_G.SocialUIFrame or _G.FriendsFrame) then
                        UI:CloseEmbeddedIfHost(_G.SocialUIFrame or _G.FriendsFrame)
                    end
                    ns:Emit("SETTINGS_UPDATED")
                    ns:Emit("SOCIAL_UPDATED")
                    ns:Emit("CLAN_UPDATED")
                    if ns.LFGFrameTab and ns.LFGFrameTab.SyncAllEmbeddedTabStates then
                        ns.LFGFrameTab:SyncAllEmbeddedTabStates()
                    end
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                    ns:Print("%s", L["Disabled in this window. Re-enable anytime in Settings (/sc)."])
                end)
            end
            root:CreateButton(L["Settings"], function()
                if ns.Settings and ns.Settings.Open then ns.Settings:Open("general") end
            end)
        end,
    })
end

local function ApplySingleEmbedTheme(tabKey)
    local f = tabKey and embedContainers[tabKey]
    if not f then
        return
    end
    local p = Theme:GetPalette()
    local isBlizz = Theme:IsBlizzard(p)
    local baseLevel = f:GetFrameLevel()
    local fw = f:GetWidth() or 760
    local isCompact = fw < 540

    if f._solidOpaqueBg then
        local wBg = p.windowBg or { 0.075, 0.07, 0.065, 1.0 }
        f._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
        f._solidOpaqueBg:Show()
    end
    if f._embeddedArtBg then
        f._embeddedArtBg:SetShown(isBlizz)
    end
    if f._embeddedInsideFrame then
        f._embeddedInsideFrame:SetShown(isBlizz)
    end

    Theme:ApplyBackdrop(f, isBlizz and "none" or "surface", p)
    if f._solidOpaqueBg then
        f._solidOpaqueBg:Show()
    end
    Theme:ApplyBackdrop(f.header, "none", p)
    f.header:SetFrameLevel(baseLevel + 10)
    f.content:SetFrameLevel(baseLevel + 8)

    if f.settingsBtn and f.settingsCompactBtn then
        f.settingsBtn:SetShown(not isCompact)
        f.settingsCompactBtn:SetShown(isCompact)
        Theme:StyleButton(f.settingsBtn, "default")
    end

    local settingsAnchor = (f.settingsBtn and f.settingsBtn:IsShown() and f.settingsBtn) or f.settingsCompactBtn
    if f.updateBtn then
        Theme:StyleButton(f.updateBtn, "default")
        local remoteVer = ns.Clan and ns.Clan.latestRemoteVersion
        local hasUpdate = remoteVer and Compat.CompareSemVer(remoteVer, ns.version or "0.0.0") > 0
        if hasUpdate and settingsAnchor then
            if isCompact and fw < 420 then
                Theme:SetButtonText(f.updateBtn, "!")
                f.updateBtn:SetSize(22, 22)
            elseif isCompact then
                Theme:SetButtonText(f.updateBtn, "v" .. remoteVer)
                Theme:AutoFitButton(f.updateBtn, 52, 10, 86)
                f.updateBtn:SetHeight(24)
            else
                Theme:SetButtonText(f.updateBtn, L["Update %s"]:format("v" .. remoteVer))
                Theme:AutoFitButton(f.updateBtn, 76, 16, 155)
                f.updateBtn:SetHeight(24)
            end
            Theme:SetButtonActive(f.updateBtn, true, "primary")
            f.updateBtn:ClearAllPoints()
            f.updateBtn:SetPoint("RIGHT", settingsAnchor, "LEFT", isCompact and -4 or -6, 0)
            f.updateBtn:Show()
        else
            f.updateBtn:Hide()
        end
    end

    if f.quickBtn and settingsAnchor then
        local leftRef = (f.updateBtn and f.updateBtn:IsShown()) and f.updateBtn or settingsAnchor
        f.quickBtn:ClearAllPoints()
        f.quickBtn:SetPoint("RIGHT", leftRef, "LEFT", isCompact and -4 or -6, 0)
        if f.quickBtn.RefreshTheme then f.quickBtn:RefreshTheme() end
        f.quickBtn:Show()
    end

    if tabKey == "clan" and clanPanel then
        if clanPanel.eventsScroll then clanPanel.eventsScroll:RefreshTheme() end
        if clanPanel.peersScroll then clanPanel.peersScroll:RefreshTheme() end
    else
        local spec = EMBED_HOST_SPECS[tabKey]
        local panel = spec and spec.getPanel and spec.getPanel()
        if panel and panel.RefreshTheme then
            panel:RefreshTheme()
        end
    end
    UI:SyncFrameSectionLayers(f)
end

local function BuildSingleEmbedContainer(tabKey)
    if embedContainers[tabKey] then
        return embedContainers[tabKey]
    end
    local spec = EMBED_HOST_SPECS[tabKey]
    if not spec then
        return nil
    end

    local f = CreateFrame("Frame", spec.frameName, UIParent, "BackdropTemplate")
    f._tabKey = tabKey
    f._active = false
    f._host = nil
    f:EnableMouse(true)
    if f.EnableMouseWheel then
        f:EnableMouseWheel(true)
        f:SetScript("OnMouseWheel", function() end)
    end
    f:Hide()

    local solidBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetAllPoints(f)
    solidBg:SetTexture(WHITE8X8)
    solidBg:SetVertexColor(0.08, 0.075, 0.07, 1.0)
    solidBg:Show()
    f._solidOpaqueBg = solidBg

    local embeddedArtBg = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    embeddedArtBg:SetAllPoints(f)
    if Theme:HasAtlas("groupfinder-background") then
        embeddedArtBg:SetAtlas("groupfinder-background", false)
    else
        embeddedArtBg:SetTexture(WHITE8X8)
        embeddedArtBg:SetVertexColor(0.07, 0.065, 0.06, 1.0)
    end
    embeddedArtBg:Hide()
    f._embeddedArtBg = embeddedArtBg

    local embeddedInsideFrame = f:CreateTexture(nil, "ARTWORK", nil, 1)
    embeddedInsideFrame:SetAllPoints(f)
    if Theme:HasAtlas("common-insideframe") then
        embeddedInsideFrame:SetAtlas("common-insideframe", false)
    else
        embeddedInsideFrame:Hide()
    end
    embeddedInsideFrame:Hide()
    f._embeddedInsideFrame = embeddedInsideFrame

    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -4)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -4)
    header:SetHeight(26)
    f.header = header

    local settingsBtn = Theme:CreateButton(header, 90, 24, L["Settings"], "default")
    Theme:AutoFitButton(settingsBtn, 82, 18, 132)
    settingsBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    settingsBtn:SetScript("OnClick", function()
        if ns.Settings then ns.Settings:Open() end
    end)
    f.settingsBtn = settingsBtn

    local settingsCompactBtn = CreateFrame("Button", nil, header)
    settingsCompactBtn:SetSize(22, 22)
    settingsCompactBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    local scIcon = settingsCompactBtn:CreateTexture(nil, "ARTWORK")
    scIcon:SetAllPoints()
    scIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    local scHl = settingsCompactBtn:CreateTexture(nil, "HIGHLIGHT")
    scHl:SetAllPoints()
    scHl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    scHl:SetBlendMode("ADD")
    settingsCompactBtn:SetScript("OnClick", function()
        if ns.Settings then ns.Settings:Open() end
    end)
    settingsCompactBtn:SetScript("OnEnter", function(selfBtn)
        if GameTooltip then
            GameTooltip:SetOwner(selfBtn, "ANCHOR_BOTTOM")
            GameTooltip:SetText(L["Settings"], 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    settingsCompactBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    settingsCompactBtn:Hide()
    f.settingsCompactBtn = settingsCompactBtn

    local updateBtn = Theme:CreateButton(header, 82, 24, L["Update"], "default")
    Theme:AutoFitButton(updateBtn, 76, 16, 145)
    updateBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
    updateBtn:SetScript("OnClick", function()
        UI:OpenUpdateModal()
    end)
    AttachUpdateButtonTooltip(updateBtn)
    updateBtn:Hide()
    f.updateBtn = updateBtn

    local hostWinKey = (tabKey == "clan" and "J")
        or (tabKey == "alts" and "C")
        or (tabKey == "group" and "I")
        or "O"
    local quickBtn = BuildEmbeddedHostQuickButton(header, hostWinKey)
    if quickBtn then
        quickBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
        f.quickBtn = quickBtn
    end

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 6, spec.contentTop or -6)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    f.content = content

    f:HookScript("OnShow", function(selfFrm)
        if not selfFrm._active or not selfFrm._host then
            selfFrm:Hide()
        end
    end)

    f:HookScript("OnSizeChanged", function()
        if spec.reflowPanel then
            spec.reflowPanel()
        end
    end)

    f:HookScript("OnHide", function()
        local standaloneActive = frame and frame:IsShown() and activeTab == tabKey
        if spec.onHideModals then
            spec.onHideModals(standaloneActive)
        end
        f._embedSeq = (f._embedSeq or 0) + 1
        local seq = f._embedSeq
        local wasEmbedded = f._active
        local prevHost = f._host
        f._active = false
        f._host = nil
        if f:IsShown() then
            f:Hide()
        end
        local panel = spec.getPanel and spec.getPanel()
        if panel and frame and frame.content then
            panel:SetParent(frame.content)
            panel:ClearAllPoints()
            panel:SetAllPoints(frame.content)
            panel:SetShown(standaloneActive and true or false)
            if standaloneActive then
                SyncSubtreeButtonLayers(panel, 12)
            end
        end
        if wasEmbedded then
            if prevHost and UI.RestoreEmbeddedHostUI then
                UI:RestoreEmbeddedHostUI(prevHost)
            end
            local inCombatNow = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
            if not inCombatNow and f:GetParent() ~= UIParent then
                f:SetParent(UIParent)
            elseif prevHost and prevHost ~= UIParent and C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if f._embedSeq ~= seq then return end
                    local inCombatTimer = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
                    if f and not f._active and not inCombatTimer and f:GetParent() == prevHost then
                        if f:IsShown() then
                            f:Hide()
                        end
                        f:SetParent(UIParent)
                    end
                end)
            end
        end
        if ns.LFGFrameTab and ns.LFGFrameTab.SyncAllEmbeddedTabStates then
            ns.LFGFrameTab:SyncAllEmbeddedTabStates()
        end
    end)

    embedContainers[tabKey] = f
    return f
end

--- Position the tab strip inside embedded official frames without overlapping header controls.
local function AnchorEmbeddedTabBar(isCompact)
    if not (embeddedState.active and frame and frame.tabBar) then
        return
    end
    local gap = isCompact and 4 or 6
    local rightReserve = 12 -- frame-to-header margin (6) + right inner padding (2) + tabBar clearance (4)
    local function addRightControl(btn, fallbackW, extraGap)
        if btn and btn:IsShown() then
            local bw = math.floor((btn:GetWidth() or fallbackW or 20) + 0.5)
            if bw < 16 then bw = fallbackW or 20 end
            rightReserve = rightReserve + bw + (extraGap or gap)
        end
    end
    local settingsAnchor = (frame.settingsCompactBtn and frame.settingsCompactBtn:IsShown() and frame.settingsCompactBtn)
        or (frame.settingsBtn and frame.settingsBtn:IsShown() and frame.settingsBtn)
        or (isCompact and frame.settingsCompactBtn or frame.settingsBtn)
    addRightControl(settingsAnchor, isCompact and 22 or 96, gap)
    addRightControl(frame.updateBtn, isCompact and 24 or 110, gap)
    addRightControl(frame.quickBtn, 18, gap)
    addRightControl(frame.headerHelp, 18, gap)

    local fw = math.floor((frame:GetWidth() or (isCompact and 326 or 640)) + 0.5)
    frame.tabBar._scTargetAvailW = math.max(80, fw - 8 - rightReserve)
    frame.tabBar:ClearAllPoints()
    frame.tabBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -5)
    frame.tabBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -rightReserve, -5)
    frame.tabBar:SetHeight(26)
end

function UI:EnsureMainFrameDraggable()
    if not frame then
        return
    end
    if not embeddedState.active then
        frame._scLocked = false
        if UIParent and frame.GetParent and frame:GetParent() ~= UIParent then
            local inCombatNow = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
            if not inCombatNow then
                pcall(frame.SetParent, frame, UIParent)
            end
        end
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
    end

    if Theme and Theme.AttachDragHandle then
        local function AttachIf(h)
            if h then
                Theme:AttachDragHandle(h, frame)
            end
        end
        AttachIf(frame.header)
        AttachIf(frame.blizzTitleDrag)
        AttachIf(frame.blizzPortraitDrag)
        AttachIf(frame.tabBar)
        AttachIf(frame.filterBar)
        AttachIf(frame.socialBar)
        AttachIf(frame.watchFilterBar)
        AttachIf(frame.nearbyBar)
        AttachIf(frame.altsBar)
        AttachIf(frame.socialChipsBar)
        AttachIf(frame.watchBar)
        AttachIf(frame.content)
        AttachIf(scrollList and scrollList.container)
        AttachIf(scrollList and scrollList.viewport)
        AttachIf(frame.blizzChrome)
        if frame.blizzChrome then
            AttachIf(frame.blizzChrome.TitleContainer)
            AttachIf(frame.blizzChrome.PortraitContainer)
            AttachIf(frame.blizzChrome.PortraitOverlay)
            AttachIf(frame.blizzChrome.NineSlice)
            AttachIf(frame.blizzChrome.Inset)
        end
        if clanPanel then
            AttachIf(clanPanel)
            AttachIf(clanPanel.guildHeroBar)
            AttachIf(clanPanel.ctxBar)
            AttachIf(clanPanel.leftCard)
            AttachIf(clanPanel.rightCard)
        end
        if groupPanel then
            AttachIf(groupPanel)
            AttachIf(groupPanel.topCard)
            AttachIf(groupPanel.compCard)
            AttachIf(groupPanel.listCard)
        end
        if chatPanel then
            AttachIf(chatPanel)
            AttachIf(chatPanel.topBar)
            AttachIf(chatPanel.leftCard)
            AttachIf(chatPanel.rightCard)
        end
        if altsPanel then
            AttachIf(altsPanel)
            AttachIf(altsPanel.rosterPane)
            AttachIf(altsPanel.rightPane)
        end
    end

    if not embeddedState.active then
        if frame.header then
            frame.header:EnableMouse(true)
            frame.header:RegisterForDrag("LeftButton")
        end
        local showBlizzChrome = (Theme and Theme.IsBlizzard and Theme:IsBlizzard() and frame.blizzChrome ~= nil) and true or false
        local headerLvl = (frame.header and frame.header.GetFrameLevel and frame.header:GetFrameLevel()) or ((frame:GetFrameLevel() or 600) + 10)
        if frame.blizzTitleDrag then
            frame.blizzTitleDrag._scSkipLayerSync = true
            frame.blizzTitleDrag:SetShown(showBlizzChrome)
            frame.blizzTitleDrag:EnableMouse(showBlizzChrome)
            if showBlizzChrome then
                frame.blizzTitleDrag:RegisterForDrag("LeftButton")
                if (frame.blizzTitleDrag:GetFrameLevel() or 0) < (headerLvl + 14) then
                    frame.blizzTitleDrag:SetFrameLevel(headerLvl + 14)
                end
            end
        end
        if frame.blizzPortraitDrag then
            frame.blizzPortraitDrag._scSkipLayerSync = true
            frame.blizzPortraitDrag:SetShown(showBlizzChrome)
            frame.blizzPortraitDrag:EnableMouse(showBlizzChrome)
            if showBlizzChrome then
                frame.blizzPortraitDrag:RegisterForDrag("LeftButton")
                if (frame.blizzPortraitDrag:GetFrameLevel() or 0) < (headerLvl + 14) then
                    frame.blizzPortraitDrag:SetFrameLevel(headerLvl + 14)
                end
            end
        end
        local activeClose = (showBlizzChrome and frame.blizzChrome and frame.blizzChrome.CloseButton) or frame.closeBtn
        if activeClose then
            RaiseWindowCloseButton(activeClose)
        end
    end
end

local function ApplyTheme()
    if not frame then
        return
    end
    local isEmbedded = embeddedState.active == true
    local p = Theme:GetPalette()
    local isBlizz = Theme:IsBlizzard(p)
    local baseLevel = math.max(1, math.min(4500, frame:GetFrameLevel() or 1))
    local fw = frame:GetWidth() or 760
    local isCompact = isEmbedded and fw < 540

    local showBlizzChrome = isBlizz and not isEmbedded and frame.blizzChrome ~= nil
    if frame._solidOpaqueBg then
        local wBg = p.windowBg or { 0.075, 0.07, 0.065, 1.0 }
        frame._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
        frame._solidOpaqueBg:ClearAllPoints()
        if showBlizzChrome then
            -- Keep opaque interior backing strictly inside ButtonFrameTemplate chrome so Portrait, TitleBar, and top NineSlice border are never covered.
            frame._solidOpaqueBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -24)
            frame._solidOpaqueBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
        else
            frame._solidOpaqueBg:SetAllPoints(frame)
        end
        frame._solidOpaqueBg:Show()
    end

    if frame.blizzChrome then
        frame.blizzChrome:SetFrameLevel(baseLevel + 1)
        frame.blizzChrome:SetShown(showBlizzChrome)
        if showBlizzChrome then
            DisableChromeMouseRecursive(frame.blizzChrome, frame.blizzChrome.CloseButton, 6)
            if frame.blizzChrome.Inset then
                frame.blizzChrome.Inset:SetFrameLevel(baseLevel + 2)
                frame.blizzChrome.Inset:ClearAllPoints()
                frame.blizzChrome.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -85)
                frame.blizzChrome.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 12)
            end
            if frame.blizzChrome.NineSlice and frame.blizzChrome.NineSlice.SetFrameLevel then
                frame.blizzChrome.NineSlice:SetFrameLevel(baseLevel + 5)
            end
            if frame.blizzChrome.TitleContainer then
                if frame.blizzChrome.TitleContainer.SetFrameLevel then
                    frame.blizzChrome.TitleContainer:SetFrameLevel(baseLevel + 10)
                end
                frame.blizzChrome.TitleContainer:Show()
            end
            if frame.blizzChrome.PortraitContainer then
                if frame.blizzChrome.PortraitContainer.SetFrameLevel then
                    frame.blizzChrome.PortraitContainer:SetFrameLevel(baseLevel + 12)
                end
                frame.blizzChrome.PortraitContainer:Show()
            end
            if frame.blizzChrome.PortraitOverlay and frame.blizzChrome.PortraitOverlay.SetFrameLevel then
                frame.blizzChrome.PortraitOverlay:SetFrameLevel(baseLevel + 13)
            end
        end
    end

    local blizzCloseRef = frame.blizzChrome and frame.blizzChrome.CloseButton or nil
    local chromeTop = showBlizzChrome and math.min(baseLevel + 40, MaxHierarchyFrameLevel(frame.blizzChrome, 3, blizzCloseRef, frame.closeBtn)) or baseLevel
    local interactiveBase = (not isEmbedded) and math.max(baseLevel, chromeTop) or baseLevel

    local singleEmbedded = IsSingleTabEmbedded()
    local showEmbeddedArt = isEmbedded and isBlizz
    local showEmbeddedHeaderBand = showEmbeddedArt and (not singleEmbedded)
    if frame._embeddedArtBg then
        frame._embeddedArtBg:ClearAllPoints()
        frame._embeddedArtBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, showEmbeddedHeaderBand and -34 or 0)
        frame._embeddedArtBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame._embeddedArtBg:SetShown(showEmbeddedArt)
    end
    if frame._embeddedHeaderStone then frame._embeddedHeaderStone:SetShown(showEmbeddedHeaderBand) end
    if frame._embeddedHeaderSep then frame._embeddedHeaderSep:SetShown(showEmbeddedHeaderBand) end
    if frame._embeddedInsideFrame then
        frame._embeddedInsideFrame:ClearAllPoints()
        frame._embeddedInsideFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, showEmbeddedHeaderBand and -34 or 0)
        frame._embeddedInsideFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame._embeddedInsideFrame:SetShown(showEmbeddedArt)
    end
    if frame._blizzHeaderShelf then
        frame._blizzHeaderShelf:SetShown((not isEmbedded) and isBlizz and frame.blizzChrome ~= nil)
    end
    if frame._tabStripRule then
        frame._tabStripRule:SetShown((not isEmbedded) and not singleEmbedded)
        if isBlizz then
            frame._tabStripRule:SetColorTexture(0.76, 0.60, 0.24, 0.42)
        else
            local ac = p.accentBorder or { 0.30, 0.72, 1.0 }
            frame._tabStripRule:SetColorTexture(ac[1], ac[2], ac[3], 0.35)
        end
    end

    local showBlizzDrag = (not isEmbedded) and isBlizz and frame.blizzChrome and true or false
    local frameStrata = frame:GetFrameStrata()
    if frame.blizzTitleDrag then
        frame.blizzTitleDrag:SetFrameStrata(frameStrata)
        frame.blizzTitleDrag:SetFrameLevel(interactiveBase + 24)
        frame.blizzTitleDrag:EnableMouse(showBlizzDrag)
        frame.blizzTitleDrag:SetShown(showBlizzDrag)
    end
    if frame.blizzPortraitDrag then
        frame.blizzPortraitDrag:SetFrameStrata(frameStrata)
        frame.blizzPortraitDrag:SetFrameLevel(interactiveBase + 24)
        frame.blizzPortraitDrag:EnableMouse(showBlizzDrag)
        frame.blizzPortraitDrag:SetShown(showBlizzDrag)
    end

    if isEmbedded then
        frame._scLocked = true
        if frame.blizzChrome and frame.blizzChrome.CloseButton then
            frame.blizzChrome.CloseButton:Hide()
        end
        if frame.closeBtn then
            frame.closeBtn:Hide()
        end
        if frame.grip then
            frame.grip:Hide()
        end
        if frame._resizeEdges then
            for _, edge in ipairs(frame._resizeEdges) do
                edge:Hide()
            end
        end
    else
        frame._scLocked = false
        frame:SetMovable(true)
        if frame.grip then
            frame.grip:Show()
        end
        if frame._resizeEdges then
            for _, edge in ipairs(frame._resizeEdges) do
                edge:Show()
            end
        end
        local blizzClose = (isBlizz and frame.blizzChrome and frame.blizzChrome.CloseButton) or nil
        if blizzClose then
            ConfigureBlizzCloseButton(blizzClose)
            if frame.closeBtn then
                frame.closeBtn:Hide()
            end
        elseif frame.closeBtn then
            frame.closeBtn:SetParent(frame)
            frame.closeBtn:ClearAllPoints()
            if isBlizz and frame.blizzChrome then
                frame.closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 0)
            else
                frame.closeBtn:SetPoint("RIGHT", frame.header, "RIGHT", -6, 0)
            end
            frame.closeBtn:SetHitRectInsets(-5, -5, -5, -5)
            RaiseWindowCloseButton(frame.closeBtn)
            frame.closeBtn:Show()
        end

        local activeClose = blizzClose or frame.closeBtn
        if activeClose and C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if frame and frame:IsShown() and not embeddedState.active then
                    local currentP = Theme:GetPalette()
                    local currentBlizz = Theme:IsBlizzard(currentP)
                    local targetBtn = (currentBlizz and frame.blizzChrome and frame.blizzChrome.CloseButton) or frame.closeBtn
                    if targetBtn then
                        RaiseWindowCloseButton(targetBtn)
                    end
                end
            end)
        end
    end

    if isEmbedded then
        Theme:ApplyBackdrop(frame, isBlizz and "none" or "surface", p)
        if frame._solidOpaqueBg then
            frame._solidOpaqueBg:Show()
        end
        Theme:ApplyBackdrop(frame.header, "none", p)
    elseif isBlizz and frame.blizzChrome then
        Theme:ApplyBackdrop(frame, "none", p)
        if frame._solidOpaqueBg then
            frame._solidOpaqueBg:Show()
        end
        Theme:ApplyBackdrop(frame.header, "none", p)
    else
        Theme:ApplyBackdrop(frame, "window", p)
        Theme:ApplyBackdrop(frame.header, "header", p)
    end

    if frame.header then
        frame.header:SetFrameLevel(interactiveBase + 10)
        frame.header:EnableMouse(not isEmbedded)
        frame.header:ClearAllPoints()
        if isEmbedded then
            frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -4)
            frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -4)
            frame.header:SetHeight(26)
        elseif isBlizz and frame.blizzChrome then
            frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 66, -24)
            frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -24)
            frame.header:SetHeight(30)
        else
            frame.header:SetPoint("TOPLEFT", 1, -1)
            frame.header:SetPoint("TOPRIGHT", -1, -1)
            frame.header:SetHeight(42)
        end
    end

    if modalFrame and modalFrame.topCloseBtn then
        Theme:StyleButton(modalFrame.topCloseBtn, "default")
    end

    local showHeaderTitle = (not isEmbedded) and not (isBlizz and frame.blizzChrome)
    if frame.headerIcon then frame.headerIcon:SetShown(showHeaderTitle) end
    if frame.titleText then frame.titleText:SetShown(showHeaderTitle) end
    if frame.verText then frame.verText:SetShown(showHeaderTitle) end
    if frame.summaryText then frame.summaryText:SetShown(not isEmbedded) end

    if frame.settingsBtn and frame.settingsCompactBtn then
        frame.settingsBtn:SetShown(not isCompact)
        frame.settingsCompactBtn:SetShown(isCompact)
        frame.settingsBtn:ClearAllPoints()
        frame.settingsCompactBtn:ClearAllPoints()
        if isCompact then
            frame.settingsCompactBtn:SetPoint("RIGHT", frame.header, "RIGHT", -2, 0)
        elseif isEmbedded or (isBlizz and frame.blizzChrome) then
            frame.settingsBtn:SetPoint("RIGHT", frame.header, "RIGHT", -2, 0)
        elseif frame.closeBtn then
            frame.settingsBtn:SetPoint("RIGHT", frame.closeBtn, "LEFT", -6, 0)
        end
    end

    if frame.summaryText and frame.headerHelp then
        frame.summaryText:ClearAllPoints()
        if isBlizz and frame.blizzChrome then
            frame.summaryText:SetPoint("LEFT", frame.header, "LEFT", 4, 0)
        elseif frame.verText then
            frame.summaryText:SetPoint("LEFT", frame.verText, "RIGHT", 16, 0)
        end
        frame.summaryText:SetPoint("RIGHT", frame.headerHelp, "LEFT", -8, 0)
    end

    if frame.quickBtn then
        frame.quickBtn:SetShown(isEmbedded)
    end
    if frame.headerHelp then
        frame.headerHelp:SetShown(not IsSingleTabEmbedded())
    end

    if frame.tabBar then
        local singleEmbedded = IsSingleTabEmbedded()
        frame.tabBar:SetShown(not singleEmbedded)
        frame.tabBar:SetFrameLevel(interactiveBase + 11)
        if isEmbedded then
            AnchorEmbeddedTabBar(isCompact)
        else
            frame.tabBar._scTargetAvailW = nil
            frame.tabBar:ClearAllPoints()
            if isBlizz and frame.blizzChrome then
                frame.tabBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 66, -59)
                frame.tabBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -59)
                frame.tabBar:SetHeight(26)
            else
                frame.tabBar:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 12, -8)
                frame.tabBar:SetPoint("TOPRIGHT", frame.header, "BOTTOMRIGHT", -12, -8)
                frame.tabBar:SetHeight(26)
            end
        end
    end

    if frame.filterBar then
        frame.filterBar:SetFrameLevel(interactiveBase + 8)
        frame.filterBar:ClearAllPoints()
        if isEmbedded then
            if IsSingleTabEmbedded() then
                frame.filterBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
                frame.filterBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
            else
                frame.filterBar:SetPoint("TOPLEFT", frame.tabBar, "BOTTOMLEFT", 0, -8)
                frame.filterBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -39)
            end
        elseif isBlizz and frame.blizzChrome then
            frame.filterBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -93)
            frame.filterBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -93)
        else
            frame.filterBar:SetPoint("TOPLEFT", frame.tabBar, "BOTTOMLEFT", 0, -8)
            frame.filterBar:SetPoint("TOPRIGHT", frame.tabBar, "BOTTOMRIGHT", 0, -8)
        end
    end
    if frame.socialChipsBar then
        frame.socialChipsBar:SetFrameLevel(interactiveBase + 8)
        Theme:ApplyBackdrop(frame.socialChipsBar, "surface", p)
        if frame.socialChipsBar.chips then
            for _, cb in ipairs(frame.socialChipsBar.chips) do
                local isAct = (socialFolderFilter == "all" and socialFilter == cb._chipId)
                Theme:StyleButton(cb, isAct and "primary" or "default")
                Theme:SetButtonActive(cb, isAct, isAct and "primary" or "default")
            end
        end
        if UI._ReflowSocialChipsBar then UI._ReflowSocialChipsBar() end
    end
    if frame.watchBar then frame.watchBar:SetFrameLevel(interactiveBase + 8) end
    if frame.content then frame.content:SetFrameLevel(interactiveBase + 8) end
    if frame.grip then frame.grip:SetFrameLevel(interactiveBase + 35) end
    if frame._resizeEdges then
        for _, edge in ipairs(frame._resizeEdges) do
            edge:SetFrameLevel(interactiveBase + 34)
        end
    end

    for _, item in ipairs(themeTargets) do
        Theme:StyleButton(item.btn, item.variant)
    end
    if frame.themeBtn then
        Theme:SetButtonText(frame.themeBtn, THEME_LABELS[p.key] or L["Blizzard Official"])
    end
    ReflowTabStrip()
    if frame.summaryText then
        local c = (isBlizz and p.textGold) or p.textMuted
        frame.summaryText:SetTextColor(c[1], c[2], c[3])
    end
    if frame.altsGoldText then
        frame.altsGoldText:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
    end
    if frame.socialInviteBanner then
        Theme:ApplyBackdrop(frame.socialInviteBanner, "surface", p)
        if frame.socialInviteBanner.text then
            frame.socialInviteBanner.text:SetTextColor(p.text[1], p.text[2], p.text[3])
        end
    end
    if modalFrame and modalFrame:IsShown() then
        Theme:ApplyBackdrop(modalFrame, "window", p)
        if modalFrame.btnSave then Theme:StyleButton(modalFrame.btnSave, "primary") end
        if modalFrame.btnCancel then Theme:StyleButton(modalFrame.btnCancel, "default") end
    end
    if eventModalFrame and eventModalFrame:IsShown() then
        Theme:ApplyBackdrop(eventModalFrame, "window", p)
        if eventModalFrame.btnSave then Theme:StyleButton(eventModalFrame.btnSave, "primary") end
        if eventModalFrame.btnCancel then Theme:StyleButton(eventModalFrame.btnCancel, "default") end
        for _, item in ipairs(eventModalFrame._catBtns or {}) do
            Theme:StyleButton(item.btn, "default")
            Theme:SetButtonActive(item.btn, eventModalFrame._cat == item.id, "default")
        end
        for _, item in ipairs(eventModalFrame._roleBtns or {}) do
            Theme:StyleButton(item.btn, "default")
            Theme:SetButtonActive(item.btn, eventModalFrame._myRole == item.id, "default")
        end
        for _, tb in ipairs(eventModalFrame._timeBtns or {}) do
            Theme:StyleButton(tb, "default")
        end
        for _, pb in ipairs(eventModalFrame._presetBtns or {}) do
            Theme:StyleButton(pb, "default")
        end
    end
    if clanInfoModalFrame and clanInfoModalFrame:IsShown() then
        Theme:ApplyBackdrop(clanInfoModalFrame, "window", p)
        if clanInfoModalFrame.btnSave then Theme:StyleButton(clanInfoModalFrame.btnSave, "primary") end
        if clanInfoModalFrame.btnSync then Theme:StyleButton(clanInfoModalFrame.btnSync, "default") end
        if clanInfoModalFrame.btnCancel then Theme:StyleButton(clanInfoModalFrame.btnCancel, "default") end
    end
    if diplomacyModalFrame and diplomacyModalFrame:IsShown() then
        Theme:ApplyBackdrop(diplomacyModalFrame, "window", p)
        if diplomacyModalFrame.btnSave then Theme:StyleButton(diplomacyModalFrame.btnSave, "primary") end
        if diplomacyModalFrame.btnCancel then Theme:StyleButton(diplomacyModalFrame.btnCancel, "default") end
        if diplomacyModalFrame.tgtGuildBtn then Theme:StyleButton(diplomacyModalFrame.tgtGuildBtn, "default") end
    end
    if scrollList then
        scrollList:RefreshTheme()
    end
    if clanPanel then
        if clanPanel.eventsScroll then clanPanel.eventsScroll:RefreshTheme() end
        if clanPanel.peersScroll then clanPanel.peersScroll:RefreshTheme() end
    end
    if groupPanel and groupPanel.RefreshTheme then
        groupPanel:RefreshTheme()
    end
    if chatPanel and chatPanel.RefreshTheme then
        chatPanel:RefreshTheme()
    end
    for tabKey, container in pairs(embedContainers) do
        if container:IsShown() then
            ApplySingleEmbedTheme(tabKey)
        end
    end
    UI:SyncFrameSectionLayers()
    UI:Refresh()
    for _, shownModal in pairs({ modalFrame, eventModalFrame, clanInfoModalFrame, diplomacyModalFrame, allianceModalFrame, hierarchyModalFrame }) do
        if shownModal and shownModal:IsShown() then
            if shownModal.topCloseBtn then shownModal.topCloseBtn._scLevelOffset = 12 end
            if shownModal.topClose then shownModal.topClose._scLevelOffset = 12 end
            SyncSubtreeButtonLayers(shownModal, 8)
        end
    end
    UI:SyncFrameSectionLayers()
    UI:EnsureMainFrameDraggable()
end

local function SetupMainFrameResizeHandles(targetFrame)
    if not targetFrame then return end

    local function StopActiveResize(saveResult)
        if targetFrame._scSizeWatch then
            targetFrame._scSizeWatch:SetScript("OnUpdate", nil)
            targetFrame._scSizeWatch:Hide()
        end
        if not targetFrame._scSizing then
            return
        end
        targetFrame._scSizing = false
        pcall(targetFrame.StopMovingOrSizing, targetFrame)
        local minW, minH, maxW, maxH = ApplyStandaloneResizeBounds(targetFrame)
        local curW = math.floor((targetFrame:GetWidth() or 790) + 0.5)
        local curH = math.floor((targetFrame:GetHeight() or 520) + 0.5)
        local clampedW = math.max(minW, math.min(maxW, curW))
        local clampedH = math.max(minH, math.min(maxH, curH))
        if clampedW ~= curW or clampedH ~= curH then
            targetFrame:SetSize(clampedW, clampedH)
        end
        if saveResult then
            if targetFrame._scSavePosition then
                targetFrame._scSavePosition()
            end
            if Theme and Theme.RestoreWindowPosition then
                Theme:RestoreWindowPosition(targetFrame, "main", false)
            end
            SaveGeometry()
        end
        ReflowTabStrip()
        if targetFrame._scReflowResize then
            targetFrame._scReflowResize()
        end
        UI:SyncFrameSectionLayers()
    end

    local function BeginResize(point)
        if embeddedState.active or targetFrame._scLocked or targetFrame._scDragging then
            return
        end
        if UIParent and targetFrame:GetParent() ~= UIParent then
            return
        end
        if targetFrame._scSizing then
            StopActiveResize(false)
        end
        targetFrame:SetResizable(true)
        ApplyStandaloneResizeBounds(targetFrame)
        -- Anchor opposite corner before StartSizing so CENTER anchoring never causes 2x symmetric expansion or edge drift.
        if point == "BOTTOMLEFT" then
            local right, top = targetFrame:GetRight(), targetFrame:GetTop()
            if right and top then
                targetFrame:ClearAllPoints()
                targetFrame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
            end
        else
            local left, top = targetFrame:GetLeft(), targetFrame:GetTop()
            if left and top then
                targetFrame:ClearAllPoints()
                targetFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
        end
        if targetFrame.Raise then
            pcall(targetFrame.Raise, targetFrame)
        end
        targetFrame._scSizing = true
        local ok = pcall(targetFrame.StartSizing, targetFrame, point)
        if not ok then
            targetFrame._scSizing = false
            return
        end
        if not targetFrame._scSizeWatch then
            local sw = CreateFrame("Frame", nil, targetFrame)
            sw:Hide()
            targetFrame._scSizeWatch = sw
        end
        targetFrame._scSizeWatch:Show()
        targetFrame._scSizeWatch:SetScript("OnUpdate", function()
            if not targetFrame._scSizing then
                targetFrame._scSizeWatch:SetScript("OnUpdate", nil)
                targetFrame._scSizeWatch:Hide()
                return
            end
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                StopActiveResize(true)
            end
        end)
    end

    local grip = CreateFrame("Button", nil, targetFrame)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetHitRectInsets(-6, -4, -6, -4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then
            BeginResize("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function(_, btn)
        if btn == "LeftButton" then
            StopActiveResize(true)
        elseif btn == "RightButton" and not embeddedState.active and not targetFrame._scLocked then
            ApplyStandaloneResizeBounds(targetFrame)
            local defW, defH = GetResponsiveDefaultMainSize()
            targetFrame:SetSize(defW, defH)
            if targetFrame._scSavePosition then
                targetFrame._scSavePosition()
            end
            if Theme and Theme.RestoreWindowPosition then
                Theme:RestoreWindowPosition(targetFrame, "main", false)
            end
            SaveGeometry()
            ReflowTabStrip()
            if targetFrame._scReflowResize then
                targetFrame._scReflowResize()
            end
            ns:Print("%s", L["Window size reset to default."])
        end
    end)
    grip:SetScript("OnHide", function()
        StopActiveResize(false)
    end)
    grip:SetScript("OnEnter", function(selfBtn)
        if GameTooltip then
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOPLEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["Resize Window"], 1, 0.85, 0.25)
            GameTooltip:AddLine(L["Drag corner or border to resize.\nRight-click corner to reset size."], 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end
    end)
    grip:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    targetFrame.grip = grip

    local edges = {}
    local function MakeEdgeHandle(resizePoint, setupFn)
        local edge = CreateFrame("Button", nil, targetFrame)
        edge:EnableMouse(true)
        setupFn(edge)
        local hl = edge:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.95, 0.78, 0.28, 0.32)
        edge:SetScript("OnMouseDown", function(_, btn)
            if btn == "LeftButton" then
                BeginResize(resizePoint)
            end
        end)
        edge:SetScript("OnMouseUp", function(_, btn)
            if btn == "LeftButton" then
                StopActiveResize(true)
            end
        end)
        edge:SetScript("OnHide", function()
            StopActiveResize(false)
        end)
        edges[#edges + 1] = edge
    end

    MakeEdgeHandle("RIGHT", function(e)
        e:SetWidth(7)
        e:SetPoint("TOPRIGHT", targetFrame, "TOPRIGHT", 0, -56)
        e:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", 0, 22)
    end)
    MakeEdgeHandle("BOTTOM", function(e)
        e:SetHeight(7)
        e:SetPoint("BOTTOMLEFT", targetFrame, "BOTTOMLEFT", 20, 0)
        e:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", -22, 0)
    end)
    MakeEdgeHandle("BOTTOMLEFT", function(e)
        e:SetSize(16, 16)
        e:SetPoint("BOTTOMLEFT", targetFrame, "BOTTOMLEFT", 2, 2)
        e:SetHitRectInsets(-4, -6, -6, -4)
    end)

    targetFrame._resizeEdges = edges
    targetFrame._scStopResize = StopActiveResize
end

local function RestoreStandalonePlacement()
    if not frame then return end
    frame._scLocked = false
    frame._scSizing = false
    frame._scDragging = false
    if frame._scDragWatch then
        frame._scDragWatch:SetScript("OnUpdate", nil)
        frame._scDragWatch:Hide()
    end
    if frame._scSizeWatch then
        frame._scSizeWatch:SetScript("OnUpdate", nil)
        frame._scSizeWatch:Hide()
    end
    if frame:GetParent() ~= UIParent then
        local inCombatNow = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if not inCombatNow then
            frame:SetParent(UIParent)
        end
    end
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    local minW, minH, maxW, maxH = ApplyStandaloneResizeBounds(frame)
    local defW, defH = GetResponsiveDefaultMainSize()
    local savedW, savedH = Theme and Theme.GetSavedWindowSize and Theme:GetSavedWindowSize("main")
    local hasResPos = Theme and Theme.HasSavedWindowPosition and Theme:HasSavedWindowPosition("main")
    local targetW = math.max(minW, math.min(maxW, savedW or defW))
    local targetH = math.max(minH, math.min(maxH, savedH or defH))
    frame:SetSize(targetW, targetH)
    local restored = Theme and Theme.RestoreWindowPosition and Theme:RestoreWindowPosition(frame, "main", false)
    if not restored then
        frame:ClearAllPoints()
        local w = ns.db and ns.db.window
        if (not hasResPos) and (not (Theme and Theme.EnsureResolutionPositionsMigrated)) and w and w.point and w.x and w.y then
            frame:SetPoint(w.point, UIParent, w.relativePoint or w.point, w.x, w.y)
            if frame._scSavePosition then
                frame._scSavePosition()
            end
            if Theme and Theme.RestoreWindowPosition then
                Theme:RestoreWindowPosition(frame, "main", false)
            end
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(600)
    UI:EnsureMainFrameDraggable()
end

function UI._CreateSocialChipsBar(parentFrame, filterBar, themeTargets)
    local bar = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -4)
    bar:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", 0, -4)
    bar:SetHeight(28)
    Theme:ApplyBackdrop(bar, "surface")
    bar:Hide()
    parentFrame.socialChipsBar = bar

    local chipDefs = {
        {
            id = "all",
            title = L["All"],
            tex = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon",
            sz = 15,
            activeColor = { 0.96, 0.76, 0.22 },
            countKey = "dirTotal",
        },
        {
            id = "online",
            title = L["Online Only"],
            tex = FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online",
            sz = 14,
            activeColor = { 0.25, 0.86, 0.44 },
            countKey = "onlineTotal",
            keepColor = true,
        },
        {
            id = "fav",
            title = L["Favorites"],
            tex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
            sz = 14,
            activeColor = { 0.98, 0.80, 0.20 },
            isFav = true,
        },
        {
            id = "bnet",
            title = L["Battle.net"],
            tex = "Interface\\ChatFrame\\UI-ChatIcon-BattleNet",
            sz = 15,
            activeColor = { 0.30, 0.78, 1.0 },
        },
        {
            id = "sc",
            title = "[SC]",
            tex = "Interface\\AddOns\\SocialCentral\\Media\\icon",
            sz = 14,
            activeColor = { 0.35, 0.80, 1.0 },
        },
        {
            id = "guild",
            title = L["Guild"],
            tex = "Interface\\GossipFrame\\TabardGossipIcon",
            sz = 15,
            activeColor = { 0.28, 0.88, 0.45 },
            guildOnly = true,
        },
        {
            id = "good",
            title = L["Good Partner (+)"],
            tex = "Interface\\RAIDFRAME\\ReadyCheck-Ready",
            sz = 14,
            activeColor = { 0.35, 0.92, 0.50 },
        },
        {
            id = "recent",
            title = L["Recent Companions"],
            tex = "Interface\\Icons\\INV_Misc_PocketWatch_01",
            sz = 14,
            activeColor = { 0.45, 0.80, 1.0 },
        },
        {
            id = "blocked",
            title = L["Account Ignores"],
            tex = "Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull",
            sz = 14,
            activeColor = { 0.96, 0.35, 0.35 },
            isBlocked = true,
        },
    }
    local chips = {}
    for _, def in ipairs(chipDefs) do
        local btn = Theme:CreateButton(bar, 24, 22, "", "default")
        btn._chipId = def.id
        btn._chipDef = def
        btn._guildOnly = def.guildOnly == true
        Theme:ConfigureIconButton(btn, 24, 22, def.tex, {
            size = def.sz or 14,
            toggle = true,
            active = (socialFilter == def.id),
            activeColor = def.activeColor,
            keepColorWhenInactive = def.keepColor == true,
            tooltipFn = function()
                local t = def.title
                local d = nil
                if def.countKey then
                    local n = (bar._stats and bar._stats[def.countKey]) or 0
                    if n > 0 then
                        t = t .. " (" .. tostring(n) .. ")"
                    end
                elseif def.isFav then
                    local favCnt = (ns.Social and ns.Social.GetFavoriteCount) and ns.Social:GetFavoriteCount() or 0
                    d = L["Saved favorites: %d"]:format(favCnt)
                elseif def.isBlocked and ns.Store and ns.Store.GetAccountIgnoresCount then
                    local bCnt = ns.Store:GetAccountIgnoresCount()
                    if bCnt > 0 then
                        t = t .. " (" .. tostring(bCnt) .. ")"
                    end
                end
                return t, d
            end,
        })
        themeTargets[#themeTargets + 1] = { btn = btn, variant = "default" }
        btn:SetScript("OnClick", function()
            socialFilter = def.id
            socialFolderFilter = "all"
            UI:Refresh(true)
        end)
        chips[#chips + 1] = btn
    end
    bar.chips = chips

    local offlineBtn = Theme:CreateButton(bar, 24, 22, "", "default")
    Theme:ApplyOnlineOfflineOrb(offlineBtn, true, 24, 22)
    themeTargets[#themeTargets + 1] = { btn = offlineBtn, variant = "default" }
    offlineBtn:SetScript("OnClick", function()
        if ns.db and ns.db.settings then
            ns.db.settings.socialShowOffline = (ns.db.settings.socialShowOffline == false)
        end
        UI:Refresh(true)
    end)
    parentFrame.socialOfflineBtn = offlineBtn

    local legendBtn = Theme:CreateLegendTag(bar, function()
        local items = {}
        local showGuild = (not Compat or not Compat.ShouldShowGuildFeatures) or Compat.ShouldShowGuildFeatures()
        for _, def in ipairs(chipDefs) do
            if not def.guildOnly or showGuild then
                items[#items + 1] = { tex = def.tex, title = def.title }
            end
        end
        items[#items + 1] = { tex = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", title = L["Social Folders"], desc = L["Filters"] }
        items[#items + 1] = { tex = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", title = L["Sort Order"] }
        items[#items + 1] = { tex = "Interface\\PaperDollInfoFrame\\Character-Plus", title = "+ " .. L["Friend"] }
        items[#items + 1] = {
            tex = (offlineBtn._scShowOffline and (FRIENDS_TEXTURE_DND or "Interface\\FriendsFrame\\StatusIcon-DnD") or (FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online")),
            title = L["Show Offline"],
            desc = L["Green = Online Only · Red = Showing Offline"],
        }
        items[#items + 1] = { tex = "Interface\\AddOns\\SocialCentral\\Media\\bell-on", title = L["Login Alerts"], desc = L["Bell ON = Notify when online"] }
        items[#items + 1] = { title = "|cffffd24d*|r · |cff3fb950[SC]|r · |TInterface\\ChatFrame\\UI-ChatIcon-BattleNet:12:12:0:0|t", desc = L["Favorite · SocialCentral · Battle.net"] }
        items[#items + 1] = { title = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:12:12:0:0|t · |TInterface\\RAIDFRAME\\ReadyCheck-NotReady:12:12:0:0|t", desc = L["Good Partner (+)"] .. " · " .. L["Flag: Avoid"] }
        return items
    end)
    bar.legendBtn = legendBtn

    UI._ReflowSocialChipsBar = function()
        if not bar then return end
        local avail = math.floor((bar:GetWidth() or 0) + 0.5)
        if avail <= 0 then
            avail = math.floor(((parentFrame:GetWidth() or 790) - 34) + 0.5)
        end
        offlineBtn:ClearAllPoints()
        offlineBtn:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
        local offW = math.floor((offlineBtn:GetWidth() or 24) + 0.5)
        local maxLeft = math.max(60, avail - offW - 8)
        local showGuild = (not Compat or not Compat.ShouldShowGuildFeatures) or Compat.ShouldShowGuildFeatures()
        local cursorX = 3
        for _, btn in ipairs(chips) do
            if btn._guildOnly and not showGuild then
                btn:Hide()
            else
                local w = math.floor((btn:GetWidth() or 24) + 0.5)
                if (cursorX + w) <= maxLeft then
                    btn:ClearAllPoints()
                    btn:SetPoint("LEFT", bar, "LEFT", cursorX, 0)
                    btn:Show()
                    cursorX = cursorX + w + 3
                else
                    btn:Hide()
                end
            end
        end
        if legendBtn then
            local legW = math.floor((legendBtn:GetWidth() or 68) + 0.5)
            if (maxLeft - cursorX) >= (legW + 10) then
                legendBtn:ClearAllPoints()
                legendBtn:SetPoint("RIGHT", offlineBtn, "LEFT", -6, 0)
                legendBtn:Show()
            else
                legendBtn:Hide()
            end
        end
    end
    bar:SetScript("OnSizeChanged", function()
        if UI._ReflowSocialChipsBar then UI._ReflowSocialChipsBar() end
    end)
    return bar
end

local function BuildMainFrame()
    frame = CreateFrame("Frame", "SocialCentralFrame", UIParent, "BackdropTemplate")
    local minW, minH, maxW, maxH = ApplyStandaloneResizeBounds(frame)
    local w = ns.db and ns.db.window or { width = 790, height = 520 }
    local initW = math.max(minW, math.min(maxW, w.width or 790))
    local initH = math.max(minH, math.min(maxH, w.height or 520))
    frame:SetSize(initW, initH)
    frame:SetPoint("CENTER")

    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    if frame.EnableMouseWheel then
        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", function() end)
    end
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(600)
    frame:Hide()
    table.insert(UISpecialFrames, "SocialCentralFrame")

    -- Mandatory 100% opaque solid background backing on main window
    if not frame._solidOpaqueBg then
        frame._solidOpaqueBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame._solidOpaqueBg:SetAllPoints(frame)
    end
    frame._solidOpaqueBg:SetTexture(WHITE8X8)
    frame._solidOpaqueBg:SetVertexColor(0.08, 0.075, 0.07, 1.0)
    frame._solidOpaqueBg:Show()

    -- WoW Forever native interior textures when embedded inside official windows
    local embeddedArtBg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    embeddedArtBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -34)
    embeddedArtBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    if Theme:HasAtlas("groupfinder-background") then
        embeddedArtBg:SetAtlas("groupfinder-background", false)
    else
        embeddedArtBg:SetTexture(WHITE8X8)
        embeddedArtBg:SetVertexColor(0.07, 0.065, 0.06, 1.0)
    end
    embeddedArtBg:Hide()
    frame._embeddedArtBg = embeddedArtBg

    local embeddedHeaderStone = frame:CreateTexture(nil, "BACKGROUND", nil, -4)
    embeddedHeaderStone:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    embeddedHeaderStone:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    embeddedHeaderStone:SetHeight(36)
    if Theme:HasAtlas("groupfinder-Stat-StoneBG") then
        embeddedHeaderStone:SetAtlas("groupfinder-Stat-StoneBG", false)
    else
        embeddedHeaderStone:SetTexture(WHITE8X8)
        embeddedHeaderStone:SetVertexColor(0.11, 0.10, 0.09, 1.0)
    end
    embeddedHeaderStone:Hide()
    frame._embeddedHeaderStone = embeddedHeaderStone

    local embeddedHeaderSep = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    embeddedHeaderSep:SetHeight(1)
    embeddedHeaderSep:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -34)
    embeddedHeaderSep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -34)
    embeddedHeaderSep:SetTexture(WHITE8X8)
    embeddedHeaderSep:SetVertexColor(0.68, 0.54, 0.24, 0.72)
    embeddedHeaderSep:Hide()
    frame._embeddedHeaderSep = embeddedHeaderSep

    local embeddedInsideFrame = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    embeddedInsideFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -34)
    embeddedInsideFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    if Theme:HasAtlas("common-insideframe") then
        embeddedInsideFrame:SetAtlas("common-insideframe", false)
    else
        embeddedInsideFrame:Hide()
    end
    embeddedInsideFrame:Hide()
    frame._embeddedInsideFrame = embeddedInsideFrame

    local blizzOk, blizzChrome = pcall(CreateFrame, "Frame", "SocialCentralBlizzChrome", frame, "ButtonFrameTemplate")
    if blizzOk and blizzChrome then
        blizzChrome._scSkipLayerSync = true
        blizzChrome:SetAllPoints(frame)
        blizzChrome:SetFrameLevel(math.max(1, (frame:GetFrameLevel() or 600) + 1))
        DisableChromeMouseRecursive(blizzChrome, blizzChrome.CloseButton, 4)
        local pTex = (blizzChrome.PortraitContainer and blizzChrome.PortraitContainer.portrait) or blizzChrome.portrait
        if pTex and SetPortraitToTexture then
            pcall(SetPortraitToTexture, pTex, "Interface\\AddOns\\SocialCentral\\Media\\icon")
        elseif blizzChrome.SetPortraitToAsset then
            pcall(blizzChrome.SetPortraitToAsset, blizzChrome, "Interface\\AddOns\\SocialCentral\\Media\\icon")
        end
        if blizzChrome.Bg and blizzChrome.Bg.SetVertexColor then
            pcall(blizzChrome.Bg.SetVertexColor, blizzChrome.Bg, 0.14, 0.13, 0.12, 1.0)
        end
        if blizzChrome.Inset then
            local marbleBg = blizzChrome.Inset:CreateTexture(nil, "BACKGROUND")
            marbleBg:SetAllPoints()
            if Theme:HasAtlas("groupfinder-background") then
                marbleBg:SetAtlas("groupfinder-background", false)
            else
                marbleBg:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble")
                marbleBg:SetVertexColor(0.20, 0.19, 0.18, 1.0)
            end
            blizzChrome.marbleBg = marbleBg
        end
        local titleStr = "SocialCentral v" .. (ns.version or "0.0.0")
        local titleWidget = (blizzChrome.TitleContainer and blizzChrome.TitleContainer.TitleText) or blizzChrome.TitleText
        if blizzChrome.SetTitle then
            pcall(blizzChrome.SetTitle, blizzChrome, titleStr)
        elseif titleWidget then
            titleWidget:SetText(titleStr)
        end
        if titleWidget and titleWidget.SetTextColor then
            pcall(titleWidget.SetTextColor, titleWidget, 1.0, 0.82, 0.0)
        end
        if blizzChrome.CloseButton then
            ConfigureBlizzCloseButton(blizzChrome.CloseButton)
        end
        blizzChrome:HookScript("OnShow", function(self)
            if self.CloseButton then
                ConfigureBlizzCloseButton(self.CloseButton)
            elseif frame and frame.closeBtn then
                RaiseWindowCloseButton(frame.closeBtn)
            end
        end)
        blizzChrome:Hide()
        frame.blizzChrome = blizzChrome
    end

    -- Header Bar
    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(42)
    header:EnableMouse(true)
    frame.header = header

    local blizzHeaderShelf = frame:CreateTexture(nil, "BACKGROUND", nil, -3)
    blizzHeaderShelf:SetPoint("TOPLEFT", header, "TOPLEFT", -4, 1)
    blizzHeaderShelf:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 4, -1)
    if Theme:HasAtlas("groupfinder-Stat-StoneBG") then
        blizzHeaderShelf:SetAtlas("groupfinder-Stat-StoneBG", false)
        blizzHeaderShelf:SetAlpha(0.55)
    else
        blizzHeaderShelf:SetColorTexture(0.11, 0.10, 0.08, 0.65)
    end
    blizzHeaderShelf:Hide()
    frame._blizzHeaderShelf = blizzHeaderShelf

    local blizzTitleDrag = CreateFrame("Frame", nil, frame)
    blizzTitleDrag._scSkipLayerSync = true
    blizzTitleDrag:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 2)
    blizzTitleDrag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, 2)
    blizzTitleDrag:SetHeight(28)
    blizzTitleDrag:EnableMouse(true)
    blizzTitleDrag:Hide()
    frame.blizzTitleDrag = blizzTitleDrag

    local blizzPortraitDrag = CreateFrame("Frame", nil, frame)
    blizzPortraitDrag._scSkipLayerSync = true
    blizzPortraitDrag:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 4)
    blizzPortraitDrag:SetSize(68, 60)
    blizzPortraitDrag:EnableMouse(true)
    blizzPortraitDrag:Hide()
    frame.blizzPortraitDrag = blizzPortraitDrag

    local dragHandles = { header, blizzTitleDrag, blizzPortraitDrag }
    Theme:MakeMovable(frame, {
        key = "main",
        skipAutoRestore = true,
        handles = dragHandles,
        onStop = SaveGeometry,
        onReset = function(win)
            if embeddedState.active or not win then return end
            ApplyStandaloneResizeBounds(win)
            local defW, defH = GetResponsiveDefaultMainSize()
            win:SetSize(defW, defH)
            win:ClearAllPoints()
            win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            if win._scReflowResize then
                win._scReflowResize()
            end
            UI:SyncFrameSectionLayers()
        end,
    })

    local headerIcon = header:CreateTexture(nil, "ARTWORK")
    headerIcon:SetSize(22, 22)
    headerIcon:SetPoint("LEFT", 12, 0)
    headerIcon:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\icon")
    frame.headerIcon = headerIcon

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", headerIcon, "RIGHT", 7, 0)
    title:SetText("SocialCentral")
    frame.titleText = title

    local verText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verText:SetPoint("LEFT", title, "RIGHT", 8, -1)
    verText:SetText("v" .. (ns.version or "dev"))
    frame.verText = verText

    local summaryText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summaryText:SetPoint("LEFT", verText, "RIGHT", 16, 0)
    frame.summaryText = summaryText

    local okClose, closeBtn = pcall(CreateFrame, "Button", "SocialCentralCloseButton", frame, "UIPanelCloseButton")
    if not okClose or not closeBtn then
        closeBtn = CreateFrame("Button", "SocialCentralCloseButton", frame)
        SetupFallbackCloseButton(closeBtn)
    end
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    closeBtn:SetHitRectInsets(-5, -5, -5, -5)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    closeBtn:HookScript("OnShow", function(self)
        RaiseWindowCloseButton(self)
    end)
    RaiseWindowCloseButton(closeBtn)
    frame.closeBtn = closeBtn
    frame.blizzCloseBtn = closeBtn

    local settingsBtn = Theme:CreateButton(header, 90, 24, L["Settings"], "default")
    Theme:AutoFitButton(settingsBtn, 82, 18, 132)
    settingsBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    settingsBtn:SetScript("OnClick", function()
        if ns.Settings then ns.Settings:Open() end
    end)
    frame.settingsBtn = settingsBtn
    themeTargets[#themeTargets + 1] = { btn = settingsBtn, variant = "default" }

    -- Compact Settings gear icon shown on narrow embedded official windows (< 540px)
    local settingsCompactBtn = CreateFrame("Button", "SocialCentralCompactSettingsButton", header)
    settingsCompactBtn:SetSize(22, 22)
    settingsCompactBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    local scIcon = settingsCompactBtn:CreateTexture(nil, "ARTWORK")
    scIcon:SetAllPoints()
    scIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    local scHl = settingsCompactBtn:CreateTexture(nil, "HIGHLIGHT")
    scHl:SetAllPoints()
    scHl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    scHl:SetBlendMode("ADD")
    settingsCompactBtn:SetScript("OnClick", function()
        if ns.Settings then ns.Settings:Open() end
    end)
    settingsCompactBtn:SetScript("OnEnter", function(selfBtn)
        if GameTooltip then
            GameTooltip:SetOwner(selfBtn, "ANCHOR_BOTTOMLEFT")
            GameTooltip:SetText(L["Settings"], 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    settingsCompactBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    settingsCompactBtn:Hide()
    frame.settingsCompactBtn = settingsCompactBtn

    local themeBtn = Theme:CreateButton(header, 116, 24, L["Blizzard Official"], "default")
    Theme:AutoFitButton(themeBtn, 104, 18, 152)
    themeBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
    themeBtn:SetScript("OnClick", function()
        if ns.db and ns.db.settings then
            local cur = ns.db.settings.theme or "blizzard"
            local nextTheme = THEME_ORDER[1]
            for idx, key in ipairs(THEME_ORDER) do
                if key == cur then
                    nextTheme = THEME_ORDER[(idx % #THEME_ORDER) + 1]
                    break
                end
            end
            ns.db.settings.theme = nextTheme
            ns.db.settings.themeChosen = true
            Theme:NotifyChanged()
        end
    end)
    themeBtn:Hide()
    frame.themeBtn = themeBtn
    themeTargets[#themeTargets + 1] = { btn = themeBtn, variant = "default" }

    local updateBtn = Theme:CreateButton(header, 82, 24, L["Update"], "default")
    Theme:AutoFitButton(updateBtn, 76, 16, 145)
    updateBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
    updateBtn:SetScript("OnClick", function()
        UI:OpenUpdateModal()
    end)
    AttachUpdateButtonTooltip(updateBtn)
    updateBtn:Hide()
    frame.updateBtn = updateBtn
    themeTargets[#themeTargets + 1] = { btn = updateBtn, variant = "default" }

    local quickBtn = BuildEmbeddedHostQuickButton(header, "O")
    if quickBtn then
        quickBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
        frame.quickBtn = quickBtn
    end

    local headerHelp = AddHelp(
        header,
        quickBtn or settingsBtn,
        L["Help: SocialCentral Overview"],
        L["Blizzard-safe social center integrating Friends, Guild, Battle.net, Friendly Nearby, Alts Gold, Watchlist (/who), and Clan Hub."],
        L["Use '/sc', '/sc check Name', or '/sc config', or click the Minimap button. Hover or click '?' beside any option for detailed guidance."],
        "RIGHT",
        "LEFT",
        -6,
        0,
        {
            target = header,
            steps = {
                {
                    title = L["Help: SocialCentral Overview"],
                    tag = "1/4 · " .. L["Tabs"],
                    text = L["Switch between Watchlist, Social, Conversations, Guild, Group, Nearby, and Alts right from this top strip."],
                    target = function() return frame and frame.tabBar end,
                },
                {
                    title = L["Live Search & Filters"],
                    tag = "2/4 · " .. L["Search & Filters"],
                    text = L["Every tab includes live search and quick filter icons below the tab strip so you can find friends, guildmates, or alts in one click."],
                    target = function() return frame and frame.filterBar end,
                },
                {
                    title = L["Themes & Embedded Windows"],
                    tag = "3/4 · " .. L["Appearance"],
                    text = L["Switch visual styles right here in the header, use the [SC] side tab inside Friends, Group Finder, Guild, or Character windows, or click the Minimap button for Quick Reply."],
                    target = function() return frame and (frame.themeBtn or frame.quickBtn or frame.tabBar) end,
                },
                {
                    title = L["Settings & Customization"],
                    tag = "4/4 · " .. L["Settings"],
                    text = L["Open Settings from the gear button here to customize alerts, Chromie guides, themes, Radar, and which modules run."],
                    target = function() return frame and frame.settingsBtn end,
                },
            },
        }
    )
    frame.headerHelp = headerHelp

    summaryText:SetPoint("RIGHT", headerHelp, "LEFT", -10, 0)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetWordWrap(false)

    -- Tab Strip
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -8)
    tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -12, -8)
    tabBar:SetHeight(26)
    if tabBar.SetClipsChildren then
        tabBar:SetClipsChildren(true)
    end
    tabBar:SetScript("OnSizeChanged", function()
        ReflowTabStrip()
    end)
    frame.tabBar = tabBar

    local tabStripRule = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    tabStripRule:SetHeight(1)
    tabStripRule:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", -2, -2)
    tabStripRule:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 2, -2)
    tabStripRule:SetColorTexture(0.76, 0.60, 0.24, 0.42)
    frame._tabStripRule = tabStripRule

    local tabDefs = {
        { id = "watchlist", label = L["Watchlist"], width = 108 },
        { id = "social", label = L["Social"], width = 94 },
        { id = "chat", label = L["Chat"], width = 88 },
        { id = "clan", label = L["Clan"], width = 80 },
        { id = "group", label = L["Group"], width = 90 },
        { id = "nearby", label = L["Nearby"], width = 98 },
        { id = "alts", label = L["Alts"], width = 84 },
    }
    wipe(tabOrder)
    local prevTab
    for _, def in ipairs(tabDefs) do
        local btn = Theme:CreateButton(tabBar, def.width, 26, def.label, "tab")
        if btn.SetClipsChildren then
            btn:SetClipsChildren(true)
        end
        Theme:AutoFitButton(btn, 48, 16, 190)
        if not prevTab then
            btn:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", prevTab, "RIGHT", 4, 0)
        end
        btn:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            if def.id == "chat" and ns.Chat and ns.Chat.GetUnreadSummary then
                local summary = ns.Chat:GetUnreadSummary()
                if summary and (summary.totalDirect or 0) > 0 then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:ClearLines()
                    GameTooltip:AddDoubleLine(L["Unread Messages (Direct)"], tostring(summary.totalDirect), 1.0, 0.42, 0.42, 1.0, 0.85, 0.35)
                    if summary.senders then
                        local shown = 0
                        for _, item in ipairs(summary.senders) do
                            if shown >= 5 then break end
                            GameTooltip:AddDoubleLine("  " .. tostring(item.title or "?"), tostring(item.unread or 0), 0.90, 0.94, 0.98, 1.0, 0.42, 0.42)
                            shown = shown + 1
                        end
                    end
                    if (summary.invites or 0) > 0 then
                        GameTooltip:AddDoubleLine("  " .. L["Room Invite"], tostring(summary.invites), 0.58, 0.88, 0.98, 1.0, 0.85, 0.35)
                    end
                    GameTooltip:Show()
                    return
                end
            end
            if self._scTruncated then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self._scFullText or self:GetText() or "")
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        btn:SetScript("OnClick", function()
            if Theme:IsBlizzard() and PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
                pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_TAB)
            end
            if activeTab ~= def.id then
                ClearSearchFilter()
            end
            activeTab = def.id
            local activeContainer = embedContainers[def.id]
            if activeContainer and activeContainer._active and activeContainer._host then
                UI:CloseEmbeddedIfHost(activeContainer._host)
            end
            if def.id == "social" and ns.Social then
                ns.Social:RequestRosters(false)
            elseif def.id == "clan" and ns.Clan then
                ns.Clan:RefreshGameCalendar(false)
                if ns.Clan.ClearNotificationCount then
                    ns.Clan:ClearNotificationCount()
                end
            elseif def.id == "group" and ns.Group then
                ns.Group:Scan()
            end
            UI:Refresh(true)
            if UI._maybePromptTabTutorial then
                UI._maybePromptTabTutorial(def.id)
            end
        end)
        local entry = { id = def.id, btn = btn, baseLabel = def.label }
        tabButtons[def.id] = entry
        tabOrder[#tabOrder + 1] = entry
        themeTargets[#themeTargets + 1] = { btn = btn, variant = "tab" }
        prevTab = btn
    end
    ReflowTabStrip()

    -- Filter / Search Bar
    local filterBar = CreateFrame("Frame", nil, frame)
    filterBar:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -8)
    filterBar:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, -8)
    filterBar:SetHeight(26)
    frame.filterBar = filterBar

    searchBox = CreateFrame("EditBox", "SocialCentralSearchBox", filterBar, "SearchBoxTemplate")
    searchBox:SetSize(210, 24)
    searchBox:SetPoint("LEFT", 4, 0)
    searchBox:SetAutoFocus(false)
    if searchBox.Instructions then
        searchBox.Instructions:SetText(L["Search name, zone, guild or note..."])
    end
    Theme:StyleSearchBox(searchBox)
    searchBox:HookScript("OnTextChanged", function(self)
        local q = Compat.CleanInput(self:GetText() or "") or ""
        if q == searchQuery then return end
        searchQuery = q
        if C_Timer and C_Timer.After then
            local seq = (self._scSearchSeq or 0) + 1
            self._scSearchSeq = seq
            C_Timer.After(0.10, function()
                if self._scSearchSeq == seq then
                    UI:Refresh(true)
                end
            end)
        else
            UI:Refresh(true)
        end
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    local socialBar = CreateFrame("Frame", nil, filterBar)
    socialBar:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    socialBar:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
    socialBar:SetHeight(26)
    frame.socialBar = socialBar

    local socialHelp = AddHelp(
        socialBar,
        socialBar,
        L["Help: Social Filters"],
        L["Unifies Character Friends (online & offline), Battle.net friends (WoW, Launcher/Games, & offline), and online Guildmates without spending /who cooldown."],
        L["Filter by source, Favorites (*), [SC] addon users, Good Partners, Recent Companions, or Social Folders; change Sort order or click '+ Friend' to add a WoW friend safely."],
        "RIGHT",
        "RIGHT",
        -2,
        0,
        {
            target = socialBar,
            steps = {
                {
                    title = L["Instant Contact Search"],
                    tag = "1/3 · " .. L["Search"],
                    text = L["Type any character name, Battle.net name, guild, zone, or personal alias to filter all your friends and guildmates instantly."],
                    target = searchBox,
                },
                {
                    title = L["Help: Social Filters"],
                    tag = "2/3 · " .. L["Social Filters"],
                    text = L["Toggle Favorites, Addon Users, Good Partners, Folders, Sort order, or click '+ Friend' on this bar without spending any /who cooldown."],
                    target = socialBar,
                },
                {
                    title = L["Contact Cards & Actions"],
                    tag = "3/3 · " .. L["Social"],
                    text = L["Left-click any player card to start a chat or quick whisper, or right-click to add Notes, Tags, Watchlist tracking, or Group invites."],
                    target = function() return frame and frame.scrollContainer end,
                },
            },
        }
    )
    frame._scTabHelpBtns = frame._scTabHelpBtns or {}
    frame._scTabHelpBtns.social = socialHelp

    local watchFilterBar = CreateFrame("Frame", nil, filterBar)
    watchFilterBar:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    watchFilterBar:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
    watchFilterBar:SetHeight(26)
    frame.watchFilterBar = watchFilterBar

    local groupFilterBtn = Theme:CreateButton(watchFilterBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(groupFilterBtn, 24, 22, "Interface\\GossipFrame\\TabardGossipIcon", {
        size = 15,
        toggle = true,
        active = false,
        activeColor = { 0.96, 0.76, 0.22 },
        tooltipFn = function()
            local lbl = L["All Groups"]
            if watchlistGroupFilter == "__fav" then
                lbl = L["Favorites"]
            elseif watchlistGroupFilter ~= "all" then
                lbl = watchlistGroupFilter
            end
            return L["Groups"] .. ": " .. lbl, L["Filters your Watchlist by text, Favorites (*), or custom Group tags, and sorts by Online status, Name, or Recent."]
        end,
    })
    groupFilterBtn:SetPoint("LEFT", 0, 0)
    table.insert(themeTargets, { btn = groupFilterBtn, variant = "default" })
    frame.groupFilterBtn = groupFilterBtn

    groupFilterBtn:SetScript("OnClick", function(self)
        local groups = ns.Watchlist and ns.Watchlist:GetGroups() or {}
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                local addRadio = root.CreateRadio or root.CreateCheckbox
                root:CreateTitle(L["Groups"])
                addRadio(root, L["All Groups"], function()
                    return watchlistGroupFilter == "all"
                end, function()
                    watchlistGroupFilter = "all"
                    UI:Refresh(true)
                end)
                addRadio(root, L["Favorites"], function()
                    return watchlistGroupFilter == "__fav"
                end, function()
                    watchlistGroupFilter = "__fav"
                    UI:Refresh(true)
                end)
                if #groups > 0 then
                    root:CreateDivider()
                    for _, grp in ipairs(groups) do
                        local grpName = grp
                        addRadio(root, grpName, function()
                            return watchlistGroupFilter == grpName
                        end, function()
                            watchlistGroupFilter = grpName
                            UI:Refresh(true)
                        end)
                    end
                end
            end)
        else
            local options = { "all", "__fav" }
            for _, grp in ipairs(groups) do
                table.insert(options, grp)
            end
            local nextIdx = 1
            for idx, opt in ipairs(options) do
                if opt == watchlistGroupFilter then
                    nextIdx = (idx % #options) + 1
                    break
                end
            end
            watchlistGroupFilter = options[nextIdx]
            UI:Refresh(true)
        end
    end)

    local sortBtn = Theme:CreateButton(watchFilterBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(sortBtn, 24, 22, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", {
        size = 15,
        toggle = true,
        active = false,
        activeColor = { 0.35, 0.78, 1.0 },
        tooltipFn = function()
            local m = (ns.db and ns.db.settings and ns.db.settings.sortBy) or "status"
            return GetSortLabel(m)
        end,
    })
    sortBtn:SetPoint("LEFT", groupFilterBtn, "RIGHT", 4, 0)
    table.insert(themeTargets, { btn = sortBtn, variant = "default" })
    frame.sortBtn = sortBtn

    sortBtn:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                local addRadio = root.CreateRadio or root.CreateCheckbox
                root:CreateTitle(L["Sort Order"])
                for _, entry in ipairs(SORT_MODES) do
                    local modeId = entry.id
                    addRadio(root, entry.label, function()
                        return ((ns.db and ns.db.settings and ns.db.settings.sortBy) or "status") == modeId
                    end, function()
                        if ns.db and ns.db.settings then
                            ns.db.settings.sortBy = modeId
                        end
                        UI:Refresh(true)
                    end)
                end
            end)
        else
            local current = (ns.db and ns.db.settings and ns.db.settings.sortBy) or "status"
            local nextMode = SORT_MODES[1].id
            for idx, entry in ipairs(SORT_MODES) do
                if entry.id == current then
                    nextMode = SORT_MODES[(idx % #SORT_MODES) + 1].id
                    break
                end
            end
            if ns.db and ns.db.settings then
                ns.db.settings.sortBy = nextMode
            end
            UI:Refresh(true)
        end
    end)

    frame.watchOfflineBtn = Theme:CreateButton(watchFilterBar, 24, 22, "", "default")
    Theme:ApplyOnlineOfflineOrb(frame.watchOfflineBtn, true, 24, 22)
    frame.watchOfflineBtn:SetPoint("LEFT", sortBtn, "RIGHT", 4, 0)
    table.insert(themeTargets, { btn = frame.watchOfflineBtn, variant = "default" })
    frame.watchOfflineBtn:SetScript("OnClick", function()
        if ns.db and ns.db.settings then
            ns.db.settings.watchlistShowOffline = (ns.db.settings.watchlistShowOffline == false)
        end
        UI:Refresh(true)
    end)
    frame.watchLegendBtn = Theme:CreateLegendTag(watchFilterBar, function()
        return {
            { tex = "Interface\\GossipFrame\\TabardGossipIcon", title = L["Groups"], desc = L["All Groups"] .. " / " .. L["Favorites"] },
            { tex = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", title = L["Sort Order"] },
            {
                tex = (frame.watchOfflineBtn._scShowOffline and (FRIENDS_TEXTURE_DND or "Interface\\FriendsFrame\\StatusIcon-DnD") or (FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online")),
                title = L["Show Offline"],
                desc = L["Green = Online Only · Red = Showing Offline"],
            },
            { tex = "Interface\\PaperDollInfoFrame\\Character-Plus", title = L["Add to Watchlist"] },
            { tex = "Interface\\ChatFrame\\UI-ChatIcon-BattleNet", title = L["Add Battle.net Account to Watchlist"], desc = "|cff70b5f9[" .. L["All Alts"] .. "]|r" },
            { tex = "Interface\\Buttons\\UI-RefreshButton", title = L["Verify next Watchlist player"] },
            { tex = (FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online"), title = L["Online"] .. " / " .. L["Offline"] .. " / " .. L["Unchecked"], desc = L["Green = Online · Grey = Offline · Amber = /who pending"] },
            { title = "|cffffd24d*|r · |cff3fb950[SC]|r · |TInterface\\AddOns\\SocialCentral\\Media\\bell-on:12:12:0:0|t", desc = L["Favorite · SocialCentral · Login Alerts"] },
        }
    end)
    frame.watchLegendBtn:Hide()

    local watchFilterHelp = AddHelp(
        watchFilterBar,
        watchFilterBar,
        L["Help: Search, Groups & Sort"],
        L["Filters your Watchlist by text, Favorites (*), or custom Group tags, and sorts by Online status, Name, or Recent."],
        L["Right-click any character on the Watchlist to mark Favorite or assign a Group tag, then filter or cycle sorting here."],
        "RIGHT",
        "RIGHT",
        -2,
        0
    )

    local altsBar = CreateFrame("Frame", nil, filterBar)
    altsBar:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    altsBar:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
    altsBar:SetHeight(26)
    frame.altsBar = altsBar

    local altsHelp = AddHelp(
        altsBar,
        altsBar,
        L["Help: Account Alts & Gold"],
        L["Lists your active WoW Forever character ([Current Character]) alongside other characters (Alts) you have logged in on this account, including full FirstName Surname, rested XP, guild, zone, and combined gold."],
        L["Character names are captured automatically on login. Right-click any alt to inspect it, copy its Web Armory URL, or remove offline snapshots."],
        "RIGHT",
        "RIGHT",
        -2,
        0
    )

    local altsGoldText = altsBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    altsGoldText:SetPoint("LEFT", altsBar, "LEFT", 0, 0)
    altsGoldText:SetPoint("RIGHT", altsHelp, "LEFT", -8, 0)
    altsGoldText:SetJustifyH("RIGHT")
    altsGoldText:SetWordWrap(false)
    frame.altsGoldText = altsGoldText

    local nearbyBar = CreateFrame("Frame", nil, filterBar)
    nearbyBar:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    nearbyBar:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
    nearbyBar:SetHeight(26)
    frame.nearbyBar = nearbyBar

    local clearNearbyBtn = Theme:CreateButton(nearbyBar, 24, 22, "", "danger")
    Theme:ConfigureIconButton(clearNearbyBtn, 24, 22, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", {
        size = 13,
        color = { 1.0, 0.45, 0.45 },
    })
    clearNearbyBtn:SetPoint("RIGHT", nearbyBar, "RIGHT", -26, 0)
    clearNearbyBtn:SetScript("OnClick", function()
        UI:OpenConfirmModal({
            title = L["Clear"],
            message = L["Are you sure you want to clear all passive nearby player sightings?"],
            confirmText = L["Clear"],
            onConfirm = function()
                if ns.Nearby and ns.Nearby.Clear then
                    ns.Nearby:Clear()
                end
            end,
        })
    end)
    clearNearbyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Clear"], 1, 1, 1)
        GameTooltip:AddLine(L["Clears all passive nearby sightings."], 0.8, 0.85, 0.95, true)
        GameTooltip:Show()
    end)
    clearNearbyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.clearNearbyBtn = clearNearbyBtn
    themeTargets[#themeTargets + 1] = { btn = clearNearbyBtn, variant = "danger" }

    local nearbyHelp = AddHelp(
        nearbyBar,
        nearbyBar,
        L["Help: Nearby Players"],
        L["Passively records friendly nearby players seen via nameplates, target, mouseover, group, or chat (never hostile PvP tracking)."],
        L["Shows recently seen friendly players in your area. Click '+ Watchlist' or right-click to follow someone permanently."],
        "RIGHT",
        "RIGHT",
        -2,
        0,
        {
            target = nearbyBar,
            steps = {
                {
                    title = L["Help: Nearby Players"],
                    tag = "1/2 · " .. L["Nearby"],
                    text = L["Passively collects friendly nearby players spotted on nameplates, target, mouseover, party, or chat (hostile PvP units are ignored)."],
                    target = nearbyBar,
                },
                {
                    title = L["Follow & Clear Sightings"],
                    tag = "2/2 · " .. L["Actions"],
                    text = L["Right-click any sighted player below to whisper, invite, or promote them to your Watchlist, or use Clear to empty recent sightings."],
                    target = function() return frame and frame.scrollContainer end,
                },
            },
        }
    )
    frame._scTabHelpBtns = frame._scTabHelpBtns or {}
    frame._scTabHelpBtns.nearby = nearbyHelp

    local socialFilterBtn = Theme:CreateButton(socialBar, 24, 22, "", "default")
    socialFilterBtn:SetPoint("LEFT", socialBar, "LEFT", 0, 0)
    Theme:ConfigureIconButton(socialFilterBtn, 24, 22, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", {
        size = 14,
        toggle = true,
        active = false,
        activeColor = { 0.96, 0.76, 0.22 },
        tooltipFn = function()
            local folderText = (socialFolderFilter == "__none" and L["No Folder"]) or (socialFolderFilter ~= "all" and socialFolderFilter or L["All Folders"])
            return L["Filters"] .. " · " .. L["Social Folders"], folderText
        end,
    })
    themeTargets[#themeTargets + 1] = { btn = socialFilterBtn, variant = "default" }
    frame.socialFilterBtn = socialFilterBtn

    local filterDefs = {
        { id = "all", label = L["All"] },
        { id = "online", label = L["Online Only"] },
        { id = "friend", label = L["Friends"] },
        { id = "bnet", label = L["Battle.net"] },
        { id = "guild", label = L["Guild"] },
        { id = "fav", label = L["Favorites"] },
        { id = "sc", label = "[SC]" },
        { id = "good", label = L["Good Partner (+)"] },
        { id = "recent", label = L["Recent Companions"] },
        { id = "blocked", label = L["Account Ignores"] },
        { id = "offline", label = L["Offline Only"] },
    }
    socialFilterBtn:SetScript("OnClick", function(self)
        local folders = ns.Store and ns.Store:GetSocialFolders() or {}
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                local addRadio = root.CreateRadio or root.CreateCheckbox
                local addCheck = root.CreateCheckbox or addRadio
                root:CreateTitle(L["Filters"])
                local showGuildFilt = (not Compat or not Compat.ShouldShowGuildFeatures) or Compat.ShouldShowGuildFeatures()
                for _, def in ipairs(filterDefs) do
                    local id = def.id
                    if id ~= "guild" or showGuildFilt then
                        addRadio(root, def.label, function()
                            return socialFilter == id
                        end, function()
                            socialFilter = id
                            UI:Refresh(true)
                        end)
                    end
                end
                root:CreateDivider()
                addCheck(root, L["Group by Folders (Collapsible)"], function()
                    return not (ns.db and ns.db.settings and ns.db.settings.socialGroupByFolder == false)
                end, function()
                    if ns.db and ns.db.settings then
                        ns.db.settings.socialGroupByFolder = (ns.db.settings.socialGroupByFolder == false)
                    end
                    UI:Refresh(true)
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                end)
                addCheck(root, L["Show Offline Friends"], function()
                    return not (ns.db and ns.db.settings and ns.db.settings.socialShowOffline == false)
                end, function()
                    if ns.db and ns.db.settings then
                        ns.db.settings.socialShowOffline = (ns.db.settings.socialShowOffline == false)
                    end
                    UI:Refresh(true)
                end)
                addCheck(root, L["Compact"] .. " (1L)", function()
                    return ns.db and ns.db.settings and ns.db.settings.compactListRows == true
                end, function()
                    if ns.db and ns.db.settings then
                        ns.db.settings.compactListRows = not (ns.db.settings.compactListRows == true)
                    end
                    UI:Refresh(true)
                    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
                end)
                root:CreateDivider()
                root:CreateTitle(L["Social Folders"])
                addRadio(root, L["All Folders"], function()
                    return socialFolderFilter == "all"
                end, function()
                    socialFolderFilter = "all"
                    UI:Refresh(true)
                end)
                addRadio(root, L["Unassigned (No Folder)"], function()
                    return socialFolderFilter == "__none"
                end, function()
                    socialFolderFilter = "__none"
                    UI:Refresh(true)
                end)
                for _, fName in ipairs(folders) do
                    local fn = fName
                    addRadio(root, fn, function()
                        return socialFolderFilter == fn
                    end, function()
                        socialFolderFilter = fn
                        UI:Refresh(true)
                    end)
                end
            end)
        else
            local nextIdx = 1
            for idx, def in ipairs(filterDefs) do
                if def.id == socialFilter then nextIdx = (idx % #filterDefs) + 1; break end
            end
            socialFilter = filterDefs[nextIdx].id
            UI:Refresh(true)
        end
    end)

    local socialSortDefs = {
        { id = "smart", label = L["Sort: Smart"] },
        { id = "name", label = L["Sort: Name"] },
        { id = "level", label = L["Sort: Level"] },
        { id = "lastSeen", label = L["Sort: Last Seen"] },
    }
    local socialSortBtn = Theme:CreateButton(socialBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(socialSortBtn, 24, 22, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", {
        size = 15,
        toggle = true,
        active = false,
        activeColor = { 0.35, 0.78, 1.0 },
        tooltipFn = function()
            local curMode = (ns.db and ns.db.settings and ns.db.settings.socialSortBy) or "smart"
            for _, def in ipairs(socialSortDefs) do
                if def.id == curMode then
                    return def.label
                end
            end
            return L["Sort: Smart"]
        end,
    })
    themeTargets[#themeTargets + 1] = { btn = socialSortBtn, variant = "default" }
    frame.socialSortBtn = socialSortBtn
    socialSortBtn:SetScript("OnClick", function(self)
        local curMode = (ns.db and ns.db.settings and ns.db.settings.socialSortBy) or "smart"
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                local addRadio = root.CreateRadio or root.CreateCheckbox
                root:CreateTitle(L["Sort Order"])
                for _, def in ipairs(socialSortDefs) do
                    local modeId = def.id
                    addRadio(root, def.label, function()
                        return ((ns.db and ns.db.settings and ns.db.settings.socialSortBy) or "smart") == modeId
                    end, function()
                        if ns.db and ns.db.settings then
                            ns.db.settings.socialSortBy = modeId
                        end
                        UI:Refresh(true)
                    end)
                end
            end)
        else
            local nextMode = socialSortDefs[1].id
            for idx, def in ipairs(socialSortDefs) do
                if def.id == curMode then
                    nextMode = socialSortDefs[(idx % #socialSortDefs) + 1].id
                    break
                end
            end
            if ns.db and ns.db.settings then
                ns.db.settings.socialSortBy = nextMode
            end
            UI:Refresh(true)
        end
    end)

    UI._CreateSocialChipsBar(frame, filterBar, themeTargets)

    local socialProfileBtn = Theme:CreateButton(socialBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(socialProfileBtn, 24, 22, "Interface\\Icons\\INV_Misc_Note_01", {
        size = 14,
        title = L["My Social Profile"],
        desc = L["Configure your optional Role, Play Hours, Languages & Bio shown in tooltips."],
    })
    themeTargets[#themeTargets + 1] = { btn = socialProfileBtn, variant = "default" }
    frame.socialProfileBtn = socialProfileBtn
    socialProfileBtn:SetScript("OnClick", function()
        UI:OpenMySocialProfileModal()
    end)

    local socialAddBtn = Theme:CreateButton(socialBar, 26, 22, "", "primary")
    Theme:ConfigureIconButton(socialAddBtn, 26, 22, "Interface\\PaperDollInfoFrame\\Character-Plus", {
        size = 14,
        color = { 0.45, 0.95, 0.55 },
        tooltipFn = function()
            return socialFilter == "blocked" and ("+ " .. L["Block"]) or ("+ " .. L["Friend"])
        end,
    })
    themeTargets[#themeTargets + 1] = { btn = socialAddBtn, variant = "primary" }
    frame.socialAddBtn = socialAddBtn
    socialAddBtn:SetScript("OnClick", function()
        if socialFilter == "blocked" and ns.SocialPanels and ns.SocialPanels.OpenAccountIgnoreModal then
            ns.SocialPanels:OpenAccountIgnoreModal()
        else
            OpenAddFriendModal()
        end
    end)

    if socialHelp then
        socialHelp:Raise()
    end

    ReflowFilterBar = function()
        if not filterBar or not searchBox then
            return
        end
        local avail = math.floor((filterBar:GetWidth() or 0) + 0.5)
        if avail <= 0 then
            avail = math.floor(((frame:GetWidth() or 790) - 34) + 0.5)
        end
        local compact = filterBar._scCompact and (avail < 548) or (avail < 532)
        if filterBar._scCompact == nil then
            compact = (avail < 540)
        end
        filterBar._scCompact = compact

        if activeTab == "social" then
            local isBlockedView = (socialFilter == "blocked")
            Theme:ConfigureIconButton(
                socialAddBtn,
                26,
                22,
                isBlockedView and "Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull" or "Interface\\PaperDollInfoFrame\\Character-Plus",
                {
                    size = 14,
                    color = isBlockedView and { 1.0, 0.45, 0.45 } or { 0.45, 0.95, 0.55 },
                    tooltipFn = function()
                        return (socialFilter == "blocked") and ("+ " .. L["Block"]) or ("+ " .. L["Friend"])
                    end,
                }
            )
            socialFilterBtn:SetSize(24, 22)
            socialFilterBtn._scAutoFitW = 24
            socialSortBtn:SetSize(24, 22)
            socialSortBtn._scAutoFitW = 24
        elseif activeTab == "watchlist" then
            groupFilterBtn:SetSize(24, 22)
            groupFilterBtn._scAutoFitW = 24
            sortBtn:SetSize(24, 22)
            sortBtn._scAutoFitW = 24
            if frame.watchOfflineBtn then
                frame.watchOfflineBtn:SetSize(24, 22)
                frame.watchOfflineBtn._scAutoFitW = 24
            end
        end

        local sig = avail .. ":" .. tostring(activeTab) .. ":" .. (compact and 1 or 0)
            .. ":" .. math.floor((socialFilterBtn._scAutoFitW or 0) + 0.5)
            .. ":" .. math.floor((socialSortBtn._scAutoFitW or 0) + 0.5)
            .. ":" .. math.floor((socialAddBtn._scAutoFitW or 0) + 0.5)
            .. ":" .. math.floor((groupFilterBtn._scAutoFitW or 0) + 0.5)
            .. ":" .. math.floor((sortBtn._scAutoFitW or 0) + 0.5)
            .. ":" .. math.floor(((frame.watchOfflineBtn and frame.watchOfflineBtn._scAutoFitW) or 0) + 0.5)
            .. ":" .. math.floor((clearNearbyBtn._scAutoFitW or 0) + 0.5)
        if filterBar._scFilterSig == sig then
            if activeTab == "social" and UI._ReflowSocialChipsBar then
                UI._ReflowSocialChipsBar()
            end
            return
        end
        filterBar._scFilterSig = sig

        local subBars = { socialBar, watchFilterBar, altsBar, nearbyBar }

        searchBox:ClearAllPoints()
        if activeTab == "social" then
            if math.abs((searchBox:GetHeight() or 0) - 22) >= 1 then
                searchBox:SetHeight(22)
            end
            local fltW = math.floor((socialFilterBtn._scAutoFitW or socialFilterBtn:GetWidth() or 86) + 0.5)
            local srtW = math.floor((socialSortBtn._scAutoFitW or socialSortBtn:GetWidth() or 76) + 0.5)
            local profW = socialProfileBtn and 24 or 0
            local addW = math.floor((socialAddBtn._scAutoFitW or socialAddBtn:GetWidth() or 26) + 0.5)
            local helpW = socialHelp and 24 or 0
            local rightNeed = fltW + srtW + profW + addW + helpW + 24
            local searchW = math.max(96, avail - rightNeed - 10)
            if math.abs((searchBox:GetWidth() or 0) - searchW) >= 1 then
                searchBox:SetWidth(searchW)
            end
            searchBox:SetPoint("LEFT", filterBar, "LEFT", 2, 0)
            socialBar:ClearAllPoints()
            socialBar:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
            socialBar:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
            if math.abs((socialBar:GetHeight() or 0) - 26) >= 1 then
                socialBar:SetHeight(26)
            end

            local rightAnchor = socialBar
            local rightRel = "RIGHT"
            if socialHelp then
                socialHelp:ClearAllPoints()
                socialHelp:SetPoint("RIGHT", socialBar, "RIGHT", -2, 0)
                rightAnchor = socialHelp
                rightRel = "LEFT"
            end
            socialAddBtn:ClearAllPoints()
            socialAddBtn:SetPoint("RIGHT", rightAnchor, rightRel, -4, 0)
            socialProfileBtn:ClearAllPoints()
            socialProfileBtn:SetPoint("RIGHT", socialAddBtn, "LEFT", -4, 0)
            socialSortBtn:ClearAllPoints()
            socialSortBtn:SetPoint("RIGHT", socialProfileBtn, "LEFT", -4, 0)
            socialFilterBtn:ClearAllPoints()
            socialFilterBtn:SetPoint("RIGHT", socialSortBtn, "LEFT", -4, 0)

            if math.abs((filterBar:GetHeight() or 0) - 26) >= 1 then
                filterBar:SetHeight(26)
            end
            if UI._ReflowSocialChipsBar then
                UI._ReflowSocialChipsBar()
            end
            return
        elseif activeTab == "watchlist" then
            if math.abs((searchBox:GetHeight() or 0) - 22) >= 1 then
                searchBox:SetHeight(22)
            end
            local grpW = math.floor((groupFilterBtn._scAutoFitW or groupFilterBtn:GetWidth() or 86) + 0.5)
            local srtW = math.floor((sortBtn._scAutoFitW or sortBtn:GetWidth() or 80) + 0.5)
            local offW = frame.watchOfflineBtn and math.floor((frame.watchOfflineBtn._scAutoFitW or frame.watchOfflineBtn:GetWidth() or 70) + 0.5) or 0
            local helpW = watchFilterHelp and 24 or 0
            local rightNeed = grpW + srtW + offW + helpW + 20
            local searchW = compact and math.max(76, avail - rightNeed - 10) or math.max(130, math.min(240, avail - rightNeed - 12))
            if math.abs((searchBox:GetWidth() or 0) - searchW) >= 1 then
                searchBox:SetWidth(searchW)
            end
            searchBox:SetPoint("LEFT", filterBar, "LEFT", 2, 0)
            watchFilterBar:ClearAllPoints()
            watchFilterBar:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
            watchFilterBar:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
            if math.abs((watchFilterBar:GetHeight() or 0) - 26) >= 1 then
                watchFilterBar:SetHeight(26)
            end

            local rightAnchor = watchFilterBar
            local rightRel = "RIGHT"
            if watchFilterHelp then
                watchFilterHelp:ClearAllPoints()
                watchFilterHelp:SetPoint("RIGHT", watchFilterBar, "RIGHT", -2, 0)
                rightAnchor = watchFilterHelp
                rightRel = "LEFT"
            end
            if frame.watchOfflineBtn then
                frame.watchOfflineBtn:ClearAllPoints()
                frame.watchOfflineBtn:SetPoint("RIGHT", rightAnchor, rightRel, -4, 0)
                rightAnchor = frame.watchOfflineBtn
                rightRel = "LEFT"
            end
            sortBtn:ClearAllPoints()
            sortBtn:SetPoint("RIGHT", rightAnchor, rightRel, -4, 0)
            groupFilterBtn:ClearAllPoints()
            groupFilterBtn:SetPoint("RIGHT", sortBtn, "LEFT", -4, 0)
            if frame.watchLegendBtn then
                local legW = math.floor((frame.watchLegendBtn:GetWidth() or 68) + 0.5)
                if avail >= 470 and (avail - searchW - rightNeed) >= (legW + 12) then
                    frame.watchLegendBtn:ClearAllPoints()
                    frame.watchLegendBtn:SetPoint("RIGHT", groupFilterBtn, "LEFT", -6, 0)
                    frame.watchLegendBtn:Show()
                else
                    frame.watchLegendBtn:Hide()
                end
            end

            if math.abs((filterBar:GetHeight() or 0) - 26) >= 1 then
                filterBar:SetHeight(26)
            end
            return
        elseif activeTab == "nearby" then
            if math.abs((searchBox:GetHeight() or 0) - 22) >= 1 then
                searchBox:SetHeight(22)
            end
            local clrW = math.floor((clearNearbyBtn._scAutoFitW or clearNearbyBtn:GetWidth() or 64) + 0.5)
            local helpW = nearbyHelp and 24 or 0
            local searchW = math.max(110, avail - clrW - helpW - 22)
            if not compact then
                searchW = math.min(340, searchW)
            end
            if math.abs((searchBox:GetWidth() or 0) - searchW) >= 1 then
                searchBox:SetWidth(searchW)
            end
            searchBox:SetPoint("LEFT", filterBar, "LEFT", 2, 0)
            nearbyBar:ClearAllPoints()
            nearbyBar:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
            nearbyBar:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
            if math.abs((nearbyBar:GetHeight() or 0) - 26) >= 1 then
                nearbyBar:SetHeight(26)
            end
            if nearbyHelp then
                nearbyHelp:ClearAllPoints()
                nearbyHelp:SetPoint("RIGHT", nearbyBar, "RIGHT", -2, 0)
            end
            if clearNearbyBtn then
                clearNearbyBtn:ClearAllPoints()
                clearNearbyBtn:SetPoint("RIGHT", nearbyHelp or nearbyBar, nearbyHelp and "LEFT" or "RIGHT", -4, 0)
            end
            if math.abs((filterBar:GetHeight() or 0) - 26) >= 1 then
                filterBar:SetHeight(26)
            end
            return
        end

        if compact then
            searchBox:SetPoint("TOPLEFT", filterBar, "TOPLEFT", 2, -2)
            searchBox:SetPoint("TOPRIGHT", filterBar, "TOPRIGHT", -2, -2)
            if math.abs((searchBox:GetHeight() or 0) - 22) >= 1 then
                searchBox:SetHeight(22)
            end

            local rowH = 24
            for _, sb in ipairs(subBars) do
                sb:ClearAllPoints()
                sb:SetPoint("TOPLEFT", filterBar, "TOPLEFT", 2, -28)
                sb:SetPoint("TOPRIGHT", filterBar, "TOPRIGHT", -2, -28)
            end

            if activeTab == "watchlist" then
                local wBtns = { groupFilterBtn, sortBtn }
                if frame.watchOfflineBtn then wBtns[#wBtns + 1] = frame.watchOfflineBtn end
                if watchFilterHelp then table.insert(wBtns, watchFilterHelp) end
                local flowH = FlowButtonGroup(watchFilterBar, wBtns, 6, 4, 0)
                if math.abs((watchFilterBar:GetHeight() or 0) - flowH) >= 1 then
                    watchFilterBar:SetHeight(flowH)
                end
                rowH = flowH
            elseif activeTab == "alts" then
                if math.abs((altsBar:GetHeight() or 0) - 24) >= 1 then
                    altsBar:SetHeight(24)
                end
                if altsHelp then
                    altsHelp:ClearAllPoints()
                    altsHelp:SetPoint("RIGHT", altsBar, "RIGHT", -2, 0)
                end
                if altsGoldText then
                    altsGoldText:ClearAllPoints()
                    altsGoldText:SetPoint("LEFT", altsBar, "LEFT", 2, 0)
                    altsGoldText:SetPoint("RIGHT", altsHelp or altsBar, altsHelp and "LEFT" or "RIGHT", -6, 0)
                    altsGoldText:SetJustifyH("LEFT")
                end
            elseif activeTab == "nearby" then
                if math.abs((nearbyBar:GetHeight() or 0) - 24) >= 1 then
                    nearbyBar:SetHeight(24)
                end
                if nearbyHelp then
                    nearbyHelp:ClearAllPoints()
                    nearbyHelp:SetPoint("RIGHT", nearbyBar, "RIGHT", -2, 0)
                end
                if clearNearbyBtn then
                    clearNearbyBtn:ClearAllPoints()
                    clearNearbyBtn:SetPoint("LEFT", nearbyBar, "LEFT", 0, 0)
                end
            end
            local wantH = 28 + math.max(24, rowH)
            if math.abs((filterBar:GetHeight() or 0) - wantH) >= 1 then
                filterBar:SetHeight(wantH)
            end
        else
            if math.abs((searchBox:GetHeight() or 0) - 24) >= 1 then
                searchBox:SetHeight(24)
            end
            local desiredSearch = math.max(150, math.min(250, math.floor(avail * 0.28)))
            if math.abs((searchBox:GetWidth() or 0) - desiredSearch) >= 1 then
                searchBox:SetWidth(desiredSearch)
            end
            searchBox:SetPoint("LEFT", filterBar, "LEFT", 4, 0)
            for _, sb in ipairs(subBars) do
                sb:ClearAllPoints()
                sb:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
                sb:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
                if math.abs((sb:GetHeight() or 0) - 26) >= 1 then
                    sb:SetHeight(26)
                end
            end

            groupFilterBtn:ClearAllPoints()
            groupFilterBtn:SetPoint("LEFT", watchFilterBar, "LEFT", 0, 0)
            sortBtn:ClearAllPoints()
            sortBtn:SetPoint("LEFT", groupFilterBtn, "RIGHT", 6, 0)
            if frame.watchOfflineBtn then
                frame.watchOfflineBtn:ClearAllPoints()
                frame.watchOfflineBtn:SetPoint("LEFT", sortBtn, "RIGHT", 6, 0)
            end
            if watchFilterHelp then
                watchFilterHelp:ClearAllPoints()
                watchFilterHelp:SetPoint("RIGHT", watchFilterBar, "RIGHT", -2, 0)
            end

            if altsHelp then
                altsHelp:ClearAllPoints()
                altsHelp:SetPoint("RIGHT", altsBar, "RIGHT", -2, 0)
            end
            if altsGoldText then
                altsGoldText:ClearAllPoints()
                altsGoldText:SetPoint("LEFT", altsBar, "LEFT", 0, 0)
                altsGoldText:SetPoint("RIGHT", altsHelp or altsBar, altsHelp and "LEFT" or "RIGHT", -8, 0)
                altsGoldText:SetJustifyH("RIGHT")
            end

            if nearbyHelp then
                nearbyHelp:ClearAllPoints()
                nearbyHelp:SetPoint("RIGHT", nearbyBar, "RIGHT", -2, 0)
            end
            if clearNearbyBtn then
                clearNearbyBtn:ClearAllPoints()
                clearNearbyBtn:SetPoint("RIGHT", nearbyBar, "RIGHT", -26, 0)
            end

            if math.abs((filterBar:GetHeight() or 0) - 26) >= 1 then
                filterBar:SetHeight(26)
            end
        end
    end
    filterBar:SetScript("OnSizeChanged", function()
        ReflowFilterBar()
    end)
    ReflowFilterBar()

    -- Watchlist Input Bar
    local watchBar = CreateFrame("Frame", nil, frame)
    watchBar:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -6)
    watchBar:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", 0, -6)
    watchBar:SetHeight(28)
    frame.watchBar = watchBar

    addBox = Theme:CreateEditBox(watchBar, {
        name = "SocialCentralAddInput",
        width = 210,
        height = 24,
        maxLetters = 64,
        placeholder = L["Character name (Name or Name-Surname)"],
    })
    addBox:SetPoint("LEFT", 4, 0)

    local function HideWatchSuggestions()
        if watchSuggestFrame then
            watchSuggestFrame:Hide()
        end
    end

    local function UpdateWatchSuggestions()
        if not (addBox and addBox:HasFocus() and ns.Watchlist and ns.Watchlist.GetNameSuggestions) then
            HideWatchSuggestions()
            return
        end
        local items = ns.Watchlist:GetNameSuggestions(addBox:GetText() or "", 6)
        if not items or #items == 0 then
            HideWatchSuggestions()
            return
        end
        if not watchSuggestFrame then
            local sf = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            sf:SetFrameStrata("DIALOG")
            sf:SetFrameLevel((frame:GetFrameLevel() or 20) + 65)
            sf:SetClampedToScreen(true)
            sf:EnableMouse(true)
            sf:Hide()
            sf.rows = {}
            for i = 1, 6 do
                local rb = CreateFrame("Button", nil, sf)
                rb:SetHeight(22)
                rb:SetPoint("TOPLEFT", sf, "TOPLEFT", 6, -6 - (i - 1) * 23)
                rb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -6, -6 - (i - 1) * 23)
                local hl = rb:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 0.85, 0.35, 0.14)
                local lTxt = rb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                lTxt:SetPoint("LEFT", 6, 0)
                lTxt:SetJustifyH("LEFT")
                lTxt:SetWordWrap(false)
                local rTxt = rb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                rTxt:SetPoint("RIGHT", -6, 0)
                rTxt:SetJustifyH("RIGHT")
                rTxt:SetWordWrap(false)
                lTxt:SetPoint("RIGHT", rTxt, "LEFT", -8, 0)
                rb.leftText = lTxt
                rb.rightText = rTxt
                rb:SetScript("OnClick", function(selfBtn)
                    local picked = selfBtn._cand
                    if not picked or not ns.Watchlist then return end
                    HideWatchSuggestions()
                    local addedOk
                    if picked._isBNetAccountCandidate and ns.Watchlist.AddBNetAccount then
                        addedOk = ns.Watchlist:AddBNetAccount(picked)
                    else
                        addedOk = ns.Watchlist:Add(picked.displayName)
                    end
                    addBox:SetText("")
                    addBox:ClearFocus()
                    if addedOk and (not picked._isBNetAccountCandidate) and not picked.online and ns.Watchlist.AutoCheckNextFromHardwareClick then
                        ns.Watchlist:AutoCheckNextFromHardwareClick(picked.lookupKey)
                    end
                end)
                rb:Hide()
                sf.rows[i] = rb
            end
            watchSuggestFrame = sf
        end

        Theme:ApplyBackdrop(watchSuggestFrame, "window")
        local w = math.max(250, addBox:GetWidth() or 260)
        watchSuggestFrame:SetWidth(w)
        watchSuggestFrame:ClearAllPoints()
        watchSuggestFrame:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", 0, -2)
        local shown = math.min(#items, 6)
        for i = 1, 6 do
            local rb = watchSuggestFrame.rows[i]
            if i <= shown then
                local c = items[i]
                rb._cand = c
                local hex = Compat.ClassHex(c.classFile)
                local lv = (c.level and c.level > 0) and (" |cff9da7b5" .. L["Lv %d"]:format(c.level) .. "|r") or ""
                rb.leftText:SetText(hex .. (c.displayName or "") .. "|r" .. lv)
                local rParts = {}
                if c.guild and c.guild ~= "" then rParts[#rParts + 1] = "<" .. c.guild .. ">" end
                if c.sourceLabel and c.sourceLabel ~= "" then rParts[#rParts + 1] = c.sourceLabel end
                rb.rightText:SetText("|cff8ab4f8" .. table.concat(rParts, " · ") .. "|r")
                rb:Show()
            else
                rb._cand = nil
                rb:Hide()
            end
        end
        watchSuggestFrame:SetHeight(12 + shown * 23)
        watchSuggestFrame:Show()
    end

    local function SubmitAdd()
        if not ns.Watchlist then return end
        HideWatchSuggestions()
        local raw = addBox:GetText() or ""
        local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(raw)
        local ok, reasonOrEntry = ns.Watchlist:Add(raw)
        if ok then
            addBox:SetText("")
            addBox:ClearFocus()
            if ns.Watchlist.AutoCheckNextFromHardwareClick then
                ns.Watchlist:AutoCheckNextFromHardwareClick(parsed and parsed.lookupKey or nil)
            end
        elseif reasonOrEntry == "invalid" then
            ns:Print(L["Type a valid character name (at least 2 letters)."])
        elseif reasonOrEntry == "duplicate" and parsed and ns.Watchlist.AutoCheckNextFromHardwareClick then
            ns.Watchlist:AutoCheckNextFromHardwareClick(parsed.lookupKey)
        end
    end

    addBox:SetScript("OnEnterPressed", SubmitAdd)
    addBox:SetScript("OnEscapePressed", function(self)
        HideWatchSuggestions()
        self:ClearFocus()
    end)
    addBox:HookScript("OnTextChanged", function()
        UpdateWatchSuggestions()
    end)
    addBox:HookScript("OnEditFocusLost", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.18, function()
                if addBox and not addBox:HasFocus() and not (watchSuggestFrame and watchSuggestFrame:IsMouseOver()) then
                    HideWatchSuggestions()
                end
            end)
        end
    end)
    watchBar:HookScript("OnHide", HideWatchSuggestions)

    local addBtn = Theme:CreateButton(watchBar, 92, 24, "+ " .. L["Add"], "primary")
    Theme:AutoFitButton(addBtn, 86, 20, 140)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 6, 0)
    addBtn:SetScript("OnClick", function()
        if not ns.Watchlist then return end
        local raw = Compat.Trim(addBox:GetText() or "")
        if raw ~= "" then
            SubmitAdd()
        elseif UnitExists and UnitExists("target") then
            ns.Watchlist:AddTarget()
        else
            SubmitAdd()
        end
    end)
    themeTargets[#themeTargets + 1] = { btn = addBtn, variant = "primary" }
    watchBar:HookScript("OnSizeChanged", function()
        if ReflowWatchBar then ReflowWatchBar() end
    end)

    frame.bnetAddBtn = Theme:CreateButton(watchBar, 24, 24, "", "default")
    Theme:ConfigureIconButton(frame.bnetAddBtn, 24, 24, "Interface\\ChatFrame\\UI-ChatIcon-BattleNet", {
        size = 15,
        title = L["Add Battle.net Account to Watchlist"],
        desc = L["Select any Battle.net friend to follow all of their characters and alts under a single Watchlist entry."],
    })
    frame.bnetAddBtn:SetScript("OnClick", function(selfBtn)
        if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Social and ns.Social.GetBNetFriendsList and ns.Watchlist) then
            return
        end
        local bList = ns.Social:GetBNetFriendsList()
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            root:CreateTitle(L["Add Battle.net Account to Watchlist"])
            if not bList or #bList == 0 then
                root:CreateTitle("|cff9da7b5" .. L["No Battle.net friends found."] .. "|r")
                return
            end
            for _, bf in ipairs(bList) do
                local isWatched = ns.Watchlist.IsBNetAccountWatched and ns.Watchlist:IsBNetAccountWatched(bf.bnetAccountID)
                local prefix = isWatched and "|cff3fb950[x]|r " or ""
                local stTxt
                if bf.bnetState == "wow_forever" and bf.activeDisplayName then
                    stTxt = " · |cff3fb950" .. bf.activeDisplayName .. "|r"
                elseif bf.online then
                    stTxt = " · |cff70b5f9Battle.net|r"
                else
                    stTxt = " · |cff9da7b5" .. L["Offline"] .. "|r"
                end
                local label = prefix .. tostring(bf.bnetName or bf.displayName or "Battle.net") .. stTxt
                root:CreateButton(label, function()
                    ns.Watchlist:AddBNetAccount(bf)
                end)
            end
        end)
    end)
    themeTargets[#themeTargets + 1] = { btn = frame.bnetAddBtn, variant = "default" }

    frame.verifyBtn = Theme:CreateButton(watchBar, 24, 24, "", "default")
    frame.verifyBtn.ico = (frame.verifyBtn._textLayer or frame.verifyBtn):CreateTexture(nil, "OVERLAY", nil, 2)
    frame.verifyBtn.ico:SetSize(14, 14)
    frame.verifyBtn.ico:SetPoint("CENTER", 0, 0)
    frame.verifyBtn.ico:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    frame.verifyBtn:SetScript("OnClick", function()
        if ns.Watchlist and ns.Watchlist.CheckNext then
            ns.Watchlist:CheckNext()
        end
    end)
    frame.verifyBtn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:SetText(L["Verify next Watchlist player"], 1, 1, 1)
        GameTooltip:AddLine(L["Runs one safe /who check on the oldest or unverified Watchlist player (outside combat, >= 5s cooldown)."], 0.85, 0.88, 0.92, true)
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        local cd = ns.Watchlist and ns.Watchlist.GetCooldownRemaining and ns.Watchlist:GetCooldownRemaining() or 0
        if inCombat then
            GameTooltip:AddLine(L["In Combat"], 1, 0.35, 0.35)
        elseif cd > 0 then
            GameTooltip:AddLine(L["Wait %ds"]:format(cd), 1, 0.78, 0.25)
        end
        GameTooltip:Show()
    end)
    frame.verifyBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    themeTargets[#themeTargets + 1] = { btn = frame.verifyBtn, variant = "default" }

    local watchHelp = AddHelp(
        watchBar,
        watchBar,
        L["Help: Manual Watchlist & /who"],
        L["Lets you add any character manually (or your current target), pick a Battle.net friend account across all alts, and run an official single /who query outside combat with cooldown >= 5s."],
        L["Type Name or Name-Surname and click '+ Add', click the Battle.net globe icon to track a Battle.net friend's entire account, or leave empty while targeting a player."],
        "RIGHT",
        "RIGHT",
        -2,
        0,
        {
            target = watchBar,
            steps = {
                {
                    title = L["Add Characters or BNet Accounts"],
                    tag = "1/3 · " .. L["Watchlist"],
                    text = L["Type any character name (or leave blank with a target selected) and click '+ Add', or use the Battle.net icon to follow all of a friend's characters."],
                    target = watchBar,
                },
                {
                    title = L["Safe Manual /who Verification"],
                    tag = "2/3 · /who",
                    text = L["Click the spyglass Check button whenever you want outside combat to verify the next Watchlist player with Blizzard's safe >= 5s /who cooldown."],
                    target = function() return frame and frame.verifyBtn end,
                },
                {
                    title = L["Tags, Groups & Alert Bells"],
                    tag = "3/3 · " .. L["Filters"],
                    text = L["Filter tracked players by custom Group tag and click any player's bell icon to mute or enable online login alerts."],
                    target = function() return frame and frame.watchFilterBar end,
                },
            },
        }
    )
    frame._scTabHelpBtns = frame._scTabHelpBtns or {}
    frame._scTabHelpBtns.watchlist = watchHelp

    ReflowWatchBar = function()
        if not watchBar or not addBox then
            return
        end
        local avail = math.floor((watchBar:GetWidth() or 0) + 0.5)
        if avail <= 0 then
            avail = math.floor(((frame:GetWidth() or 790) - 34) + 0.5)
        end
        local compact = watchBar._scCompact and (avail < 428) or (avail < 412)
        if watchBar._scCompact == nil then
            compact = (avail < 420)
        end
        watchBar._scCompact = compact
        Theme:ConfigureIconButton(addBtn, 26, compact and 22 or 24, "Interface\\PaperDollInfoFrame\\Character-Plus", {
            size = 14,
            color = { 0.45, 0.95, 0.55 },
            title = L["Add to Watchlist"],
            desc = L["Type Name or Name-Surname and click '+ Add' (or leave empty while targeting a player)."],
        })
        local addW = math.floor((addBtn._scAutoFitW or addBtn:GetWidth() or 26) + 0.5)
        local sig = avail .. ":" .. (compact and 1 or 0) .. ":" .. addW
        if watchBar._scWatchSig == sig then
            return
        end
        watchBar._scWatchSig = sig

        if watchHelp then
            watchHelp:ClearAllPoints()
            watchHelp:SetPoint("RIGHT", watchBar, "RIGHT", -2, 0)
        end
        local rightAnchor = watchHelp or watchBar
        local rightRel = watchHelp and "LEFT" or "RIGHT"
        if frame.verifyBtn then
            local vSz = compact and 22 or 24
            if math.abs((frame.verifyBtn:GetWidth() or 0) - vSz) >= 1 then
                frame.verifyBtn:SetSize(vSz, vSz)
            end
            frame.verifyBtn:ClearAllPoints()
            frame.verifyBtn:SetPoint("RIGHT", rightAnchor, rightRel, -4, 0)
            rightAnchor = frame.verifyBtn
            rightRel = "LEFT"
        end
        if frame.bnetAddBtn then
            local bSz = compact and 22 or 24
            if math.abs((frame.bnetAddBtn:GetWidth() or 0) - bSz) >= 1 then
                frame.bnetAddBtn:SetSize(bSz, bSz)
            end
            frame.bnetAddBtn:ClearAllPoints()
            frame.bnetAddBtn:SetPoint("RIGHT", rightAnchor, rightRel, -4, 0)
            rightAnchor = frame.bnetAddBtn
            rightRel = "LEFT"
        end
        addBtn:ClearAllPoints()
        addBtn:SetPoint("RIGHT", rightAnchor, rightRel, -4, 0)

        addBox:ClearAllPoints()
        addBox:SetPoint("LEFT", watchBar, "LEFT", 4, 0)
        addBox:SetPoint("RIGHT", addBtn, "LEFT", -6, 0)
        local abH = compact and 22 or 24
        if math.abs((addBox:GetHeight() or 0) - abH) >= 1 then
            addBox:SetHeight(abH)
        end
        if math.abs((watchBar:GetHeight() or 0) - 28) >= 1 then
            watchBar:SetHeight(28)
        end
    end
    watchBar:SetScript("OnSizeChanged", function()
        ReflowWatchBar()
    end)
    ReflowWatchBar()

    -- Content Area
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", watchBar, "BOTTOMLEFT", 0, -8)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 16)
    frame.content = content

    local socialInviteBanner = CreateFrame("Frame", nil, content, "BackdropTemplate")
    socialInviteBanner:SetHeight(28)
    socialInviteBanner:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    socialInviteBanner:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    Theme:ApplyBackdrop(socialInviteBanner, "surface")
    socialInviteBanner:Hide()

    local invDecline = Theme:CreateButton(socialInviteBanner, 24, 20, "", "danger")
    Theme:ConfigureIconButton(invDecline, 24, 20, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", {
        size = 13,
        color = { 1.0, 0.45, 0.45 },
        title = L["Decline"],
    })
    invDecline:SetPoint("RIGHT", socialInviteBanner, "RIGHT", -6, 0)
    themeTargets[#themeTargets + 1] = { btn = invDecline, variant = "danger" }
    socialInviteBanner.btnDecline = invDecline

    local invAccept = Theme:CreateButton(socialInviteBanner, 24, 20, "", "primary")
    Theme:ConfigureIconButton(invAccept, 24, 20, "Interface\\RAIDFRAME\\ReadyCheck-Ready", {
        size = 14,
        title = L["Accept"],
    })
    invAccept:SetPoint("RIGHT", invDecline, "LEFT", -6, 0)
    themeTargets[#themeTargets + 1] = { btn = invAccept, variant = "primary" }
    socialInviteBanner.btnAccept = invAccept

    local invText = socialInviteBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    invText:SetPoint("LEFT", socialInviteBanner, "LEFT", 8, 0)
    invText:SetPoint("RIGHT", invAccept, "LEFT", -8, 0)
    invText:SetJustifyH("LEFT")
    invText:SetWordWrap(false)
    socialInviteBanner.text = invText

    invAccept:SetScript("OnClick", function()
        if socialInviteBanner._inviteID and Compat.RespondBNetInvite then
            if not Compat.RespondBNetInvite(socialInviteBanner._inviteID, true) then
                ns:Print("%s", L["Cannot modify friends while in combat."])
            elseif ns.Social and ns.Social.QueueScan then
                ns.Social:QueueScan(0.5)
            end
        end
    end)
    invDecline:SetScript("OnClick", function()
        if socialInviteBanner._inviteID and Compat.RespondBNetInvite then
            if not Compat.RespondBNetInvite(socialInviteBanner._inviteID, false) then
                ns:Print("%s", L["Cannot modify friends while in combat."])
            elseif ns.Social and ns.Social.QueueScan then
                ns.Social:QueueScan(0.5)
            end
        end
    end)
    frame.socialInviteBanner = socialInviteBanner

    scrollList = Theme:CreateScrollList(content, 40, CreateListRow, UpdateListRow)
    scrollList.container:SetAllPoints()

    -- Resize Handles (corner grip + outer edges)
    frame._scReflowResize = function()
        if ReflowFilterBar then ReflowFilterBar() end
        if UI._ReflowSocialChipsBar then UI._ReflowSocialChipsBar() end
        if ReflowWatchBar then ReflowWatchBar() end
        if ReflowClanPanel then ReflowClanPanel() end
    end
    SetupMainFrameResizeHandles(frame)

    -- Use HookScript so Theme:MakeMovable OnShow/OnHide drag & position hooks stay intact.
    frame:HookScript("OnShow", function()
        if not embeddedState.active and UIParent and frame:GetParent() ~= UIParent then
            RestoreStandalonePlacement()
        end
        ApplyTheme()
        if ns.Social then ns.Social:RequestRosters(false) end
        if ticker then ticker:Cancel() end
        local tickCount = 0
        local lastWhoState = nil
        ticker = C_Timer.NewTicker(1, function()
            if frame and frame:IsShown() then
                if activeTab ~= "watchlist" and activeTab ~= "nearby" then
                    lastWhoState = nil
                    return
                end
                tickCount = tickCount + 1
                if activeTab == "watchlist" then
                    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
                    local cd = ns.Watchlist and ns.Watchlist:GetCooldownRemaining() or 0
                    local busy = ns.Watchlist and ns.Watchlist:IsBusy()
                    local whoState = inCombat and "C" or ((busy or cd > 0) and ("W:" .. tostring(math.max(1, math.ceil(cd)))) or "R")
                    if whoState ~= lastWhoState then
                        lastWhoState = whoState
                        UpdateWhoButtons()
                    end
                else
                    lastWhoState = nil
                end
                if (tickCount % 5 == 0) and scrollList then
                    if activeTab == "watchlist" and ns.Watchlist and ns.Watchlist.ExpireStaleOnlineEntries and ns.Watchlist:ExpireStaleOnlineEntries(true) then
                        UI:Refresh(false)
                    else
                        scrollList:Render()
                    end
                end
            end
        end)
        UI:Refresh(true)
    end)

    frame:HookScript("OnSizeChanged", function()
        if embeddedState.active and frame.tabBar and frame.tabBar:IsShown() then
            AnchorEmbeddedTabBar((frame:GetWidth() or 760) < 540)
        end
        ReflowTabStrip()
        if ReflowFilterBar then ReflowFilterBar() end
        if ReflowWatchBar then ReflowWatchBar() end
        if ReflowClanPanel then ReflowClanPanel() end
    end)

    frame:HookScript("OnHide", function()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        if modalFrame then
            modalFrame:Hide()
        end
        if not IsSingleEmbedActive("clan") then
            if eventModalFrame then
                eventModalFrame:Hide()
            end
            if clanInfoModalFrame then
                clanInfoModalFrame:Hide()
            end
            if diplomacyModalFrame then
                diplomacyModalFrame:Hide()
            end
            if allianceModalFrame then
                allianceModalFrame:Hide()
            end
        end
        if frame._scStopResize then
            frame._scStopResize(true)
        end
        SaveGeometry()
        ClearSearchFilter()
        if ns.RequestIdleGcStep then
            ns:RequestIdleGcStep(250, 0.8)
        end
        local wasEmbedded = embeddedState.active
        local prevHost = embeddedState.host
        embeddedState._seq = (embeddedState._seq or 0) + 1
        local seq = embeddedState._seq
        embeddedState.active = false
        embeddedState.host = nil
        embeddedState.allowedSet = nil
        frame._scLocked = false
        if wasEmbedded then
            if frame:IsShown() then
                frame:Hide()
            end
            if prevHost and UI.RestoreEmbeddedHostUI then
                UI:RestoreEmbeddedHostUI(prevHost)
            end
            if prevHost and prevHost ~= UIParent then
                C_Timer.After(0, function()
                    if embeddedState._seq ~= seq then return end
                    local inCombatNow = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
                    if frame and not embeddedState.active and not frame:IsShown() and not inCombatNow and frame:GetParent() == prevHost then
                        frame:SetParent(UIParent)
                        RestoreStandalonePlacement()
                    end
                end)
            end
        end
        if ns.LFGFrameTab and ns.LFGFrameTab.SyncAllEmbeddedTabStates then
            ns.LFGFrameTab:SyncAllEmbeddedTabStates()
        end
    end)

    Theme:RegisterListener(ApplyTheme)
    ApplyTheme()
end

--- Queue a coalesced refresh on the next short tick for burst background events.
function UI:QueueRefresh(resetScroll)
    local anyVisible = (frame and frame:IsShown()) and true or false
    if not anyVisible then
        for _, container in pairs(embedContainers) do
            if container:IsShown() then
                anyVisible = true
                break
            end
        end
    end
    if not anyVisible then
        return
    end
    if resetScroll then
        self._pendingResetScroll = true
    end
    if self._refreshQueued then
        return
    end
    self._refreshQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.10, function()
            self._refreshQueued = false
            local doReset = self._pendingResetScroll
            self._pendingResetScroll = false
            self:Refresh(doReset)
        end)
    else
        self._refreshQueued = false
        local doReset = self._pendingResetScroll
        self._pendingResetScroll = false
        self:Refresh(doReset)
    end
end

local function IsSocialHostFrame(hostFrame)
    return hostFrame ~= nil and (hostFrame == _G.SocialUIFrame or hostFrame == _G.FriendsFrame)
end

local function TriggerTabRefresh(tabId)
    if tabId == "social" and ns.Social then
        if ns.Social.EnsureFullGuildScan then ns.Social:EnsureFullGuildScan() end
        ns.Social:RequestRosters(false)
    elseif tabId == "watchlist" then
        if ns.Social and ns.Social.RequestRosters then
            ns.Social:RequestRosters(false)
        end
    elseif tabId == "clan" then
        if ns.Social and ns.Social.EnsureFullGuildScan then ns.Social:EnsureFullGuildScan() end
        if ns.Social and ns.Social.RequestRosters then ns.Social:RequestRosters(false) end
        if ns.Clan then
            ns.Clan:RefreshGameCalendar(false)
            if ns.Clan.ClearNotificationCount then
                ns.Clan:ClearNotificationCount()
            end
        end
    elseif tabId == "nearby" then
        if ns.Social and ns.Social.RequestRosters then
            ns.Social:RequestRosters(false)
        end
    elseif tabId == "group" and ns.Group then
        ns.Group:Scan()
    elseif tabId == "alts" and ns.Alts then
        ns.Alts:Snapshot(false)
    end
end

--- Refresh active tab state, badges, and visible list items.
function UI:Refresh(resetScroll)
    for tabKey, container in pairs(embedContainers) do
        if container:IsShown() and container._active then
            ApplySingleEmbedTheme(tabKey)
            local spec = EMBED_HOST_SPECS[tabKey]
            local panel = spec and spec.getPanel and spec.getPanel()
            if panel then
                if tabKey == "clan" then
                    panel._dirty = nil
                end
                panel:Show()
                if spec.updatePanel then
                    spec.updatePanel()
                end
                if spec.reflowPanel then
                    spec.reflowPanel()
                end
            end
        end
    end
    if not frame or not frame:IsShown() then
        return
    end
    if not IsTabAllowed(activeTab) then
        activeTab = PickFirstAllowedTab() or "social"
        if TriggerTabRefresh then
            TriggerTabRefresh(activeTab)
        end
    end

    local on, off, unk = 0, 0, 0
    if ns.Watchlist and ns.Watchlist.GetStats then
        on, off, unk = ns.Watchlist:GetStats()
    end
    local watchCount = on + off + unk
    local socialCount = ns.Social and (ns.Social.GetCount and ns.Social:GetCount("all") or #ns.Social:GetList("all")) or 0
    local nearbyCount = ns.Nearby and (ns.Nearby.GetCount and ns.Nearby:GetCount() or #ns.Nearby:GetList()) or 0
    local altsCount = ns.Store and (ns.Store.GetAltsCount and ns.Store:GetAltsCount() or #ns.Store:GetAltsList()) or 0
    local groupCount = ns.Group and ((ns.Group.members and #ns.Group.members) or #ns.Group:GetMembers()) or 0
    local chatUnread = ns.Chat and (ns.Chat.GetUnreadDirectCount and ns.Chat:GetUnreadDirectCount() or ns.Chat:GetTotalUnread()) or 0
    local clanEvents = ns.Clan and (ns.Clan.GetOpenEventsCount and ns.Clan:GetOpenEventsCount() or #ns.Clan:GetEventsList("open")) or 0
    local clanLfg = ns.Clan and (ns.Clan.GetClanBadgeLFGCount and ns.Clan:GetClanBadgeLFGCount() or #ns.Clan:GetClanLFGList()) or 0
    local clanTotal = (clanEvents + clanLfg) > 0 and (clanEvents + clanLfg) or nil

    local counts = {
        watchlist = watchCount,
        social = socialCount,
        clan = clanTotal,
        nearby = nearbyCount,
        alts = altsCount,
        group = groupCount > 0 and groupCount or nil,
        chat = chatUnread > 0 and chatUnread or nil,
    }

    for id, info in pairs(tabButtons) do
        local label
        if counts[id] then
            if id == "chat" then
                label = string.format("%s |cffff5555(%d)|r", info.baseLabel, counts[id])
            else
                label = string.format("%s (%d)", info.baseLabel, counts[id])
            end
        else
            label = info.baseLabel
        end
        info.btn._scFullText = label
        Theme:SetButtonText(info.btn, label)
        Theme:SetButtonActive(info.btn, activeTab == id, "tab")
    end
    ReflowTabStrip()

    if activeTab == "social" and ns.Social and ns.Social.GetDirectoryStats then
        local st = ns.Social:GetDirectoryStats()
        frame.summaryText:SetText(string.format(
            "%s: %d  |  %s: %d/%d  |  BNet: %d/%d",
            L["Online"], st.onlineTotal or 0,
            L["Friends"], st.friendOnline or 0, st.friendTotal or 0,
            (st.bnetOnlineWoW or 0) + (st.bnetOnlineApp or 0), st.bnetTotal or 0
        ))
    elseif activeTab == "nearby" and ns.Nearby then
        frame.summaryText:SetText(string.format("%s: %d", L["Nearby"], nearbyCount))
    elseif activeTab == "alts" and ns.Store then
        frame.summaryText:SetText(L["Total Gold"] .. ": " .. Compat.FormatMoney(ns.Store:GetTotalAltsGold(true)))
    elseif ns.Watchlist then
        frame.summaryText:SetText(string.format("%s: %d  |  %s: %d  |  %s: %d", L["Online"], on, L["Offline"], off, L["Unchecked"], unk))
    end

    local settingsAnchor = (frame.settingsBtn and frame.settingsBtn:IsShown() and frame.settingsBtn) or frame.settingsCompactBtn
    local fw = frame:GetWidth() or 760
    local isCompactHdr = embeddedState.active and fw < 540
    if frame.updateBtn then
        local remoteVer = ns.Clan and ns.Clan.latestRemoteVersion
        local hasUpdate = remoteVer and Compat.CompareSemVer(remoteVer, ns.version or "0.0.0") > 0
        if hasUpdate and settingsAnchor then
            if isCompactHdr and fw < 420 then
                Theme:SetButtonText(frame.updateBtn, "!")
                frame.updateBtn:SetSize(22, 22)
            elseif isCompactHdr then
                Theme:SetButtonText(frame.updateBtn, "v" .. remoteVer)
                Theme:AutoFitButton(frame.updateBtn, 52, 10, 86)
                frame.updateBtn:SetHeight(24)
            else
                Theme:SetButtonText(frame.updateBtn, L["Update %s"]:format("v" .. remoteVer))
                Theme:AutoFitButton(frame.updateBtn, 76, 16, 155)
                frame.updateBtn:SetHeight(24)
            end
            Theme:SetButtonActive(frame.updateBtn, true, "primary")
            frame.updateBtn:ClearAllPoints()
            frame.updateBtn:SetPoint("RIGHT", settingsAnchor, "LEFT", isCompactHdr and -4 or -6, 0)
            frame.updateBtn:Show()
            local leftRef = frame.updateBtn
            if frame.quickBtn then
                if embeddedState.active then
                    frame.quickBtn:ClearAllPoints()
                    frame.quickBtn:SetPoint("RIGHT", leftRef, "LEFT", isCompactHdr and -4 or -6, 0)
                    if frame.quickBtn.RefreshTheme then frame.quickBtn:RefreshTheme() end
                    frame.quickBtn:Show()
                    leftRef = frame.quickBtn
                else
                    frame.quickBtn:Hide()
                end
            end
            if frame.headerHelp then
                frame.headerHelp:ClearAllPoints()
                frame.headerHelp:SetPoint("RIGHT", leftRef, "LEFT", isCompactHdr and -4 or -6, 0)
            end
        else
            frame.updateBtn:Hide()
            local leftRef = settingsAnchor
            if frame.quickBtn and settingsAnchor then
                if embeddedState.active then
                    frame.quickBtn:ClearAllPoints()
                    frame.quickBtn:SetPoint("RIGHT", settingsAnchor, "LEFT", isCompactHdr and -4 or -6, 0)
                    if frame.quickBtn.RefreshTheme then frame.quickBtn:RefreshTheme() end
                    frame.quickBtn:Show()
                    leftRef = frame.quickBtn
                else
                    frame.quickBtn:Hide()
                end
            end
            if frame.headerHelp and leftRef then
                frame.headerHelp:ClearAllPoints()
                frame.headerHelp:SetPoint("RIGHT", leftRef, "LEFT", isCompactHdr and -4 or -6, 0)
            end
        end
    end
    if embeddedState.active and frame.tabBar and frame.tabBar:IsShown() then
        AnchorEmbeddedTabBar(isCompactHdr)
        ReflowTabStrip()
    end

    if ns.Watchlist and watchlistGroupFilter ~= "all" and watchlistGroupFilter ~= "__fav" then
        local validGroup = false
        for _, grp in ipairs(ns.Watchlist:GetGroups()) do
            if grp == watchlistGroupFilter then
                validGroup = true
                break
            end
        end
        if not validGroup then
            watchlistGroupFilter = "all"
        end
    end

    if ns.Store and socialFolderFilter ~= "all" and socialFolderFilter ~= "__none" then
        local validFolder = false
        for _, fn in ipairs(ns.Store:GetSocialFolders()) do
            if fn == socialFolderFilter then
                validFolder = true
                break
            end
        end
        if not validFolder then
            socialFolderFilter = "all"
        end
    end

    if frame.headerHelp then
        frame.headerHelp:SetShown(not IsSingleTabEmbedded())
    end
    local isFullPanel = (activeTab == "clan" or activeTab == "group" or activeTab == "chat" or activeTab == "alts")
    frame.filterBar:SetShown(not isFullPanel)
    frame.socialBar:SetShown(activeTab == "social")
    if frame.socialChipsBar then
        frame.socialChipsBar:SetShown(activeTab == "social")
        if activeTab == "social" and frame.socialChipsBar.chips then
            frame.socialChipsBar._stats = (ns.Social and ns.Social.GetDirectoryStats) and ns.Social:GetDirectoryStats() or nil
            for _, chipBtn in ipairs(frame.socialChipsBar.chips) do
                local isAct = (socialFolderFilter == "all" and socialFilter == chipBtn._chipId)
                Theme:SetIconToggle(chipBtn, isAct)
            end
            if UI._ReflowSocialChipsBar then
                UI._ReflowSocialChipsBar()
            end
        end
    end
    frame.watchFilterBar:SetShown(activeTab == "watchlist")
    frame.altsBar:SetShown(false)
    frame.nearbyBar:SetShown(activeTab == "nearby")
    frame.watchBar:SetShown(activeTab == "watchlist")

    if frame.groupFilterBtn then
        local gTex = (watchlistGroupFilter == "__fav")
            and "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
            or "Interface\\GossipFrame\\TabardGossipIcon"
        Theme:ConfigureIconButton(frame.groupFilterBtn, 24, 22, gTex, {
            size = (watchlistGroupFilter == "__fav") and 14 or 15,
            toggle = true,
            active = (watchlistGroupFilter ~= "all"),
            activeColor = { 0.96, 0.76, 0.22 },
            tooltipFn = function()
                local lbl = L["All Groups"]
                if watchlistGroupFilter == "__fav" then
                    lbl = L["Favorites"]
                elseif watchlistGroupFilter ~= "all" then
                    lbl = watchlistGroupFilter
                end
                return L["Groups"] .. ": " .. lbl, L["Filters your Watchlist by text, Favorites (*), or custom Group tags, and sorts by Online status, Name, or Recent."]
            end,
        })
    end
    if frame.socialFilterBtn then
        local isAdvFilter = (socialFolderFilter ~= "all" or socialFilter == "friend" or socialFilter == "offline")
        Theme:SetIconToggle(frame.socialFilterBtn, isAdvFilter, { 0.96, 0.76, 0.22 })
        if frame.socialAddBtn then
            local isBlockedView = (socialFilter == "blocked")
            Theme:ConfigureIconButton(
                frame.socialAddBtn,
                26,
                22,
                isBlockedView and "Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull" or "Interface\\PaperDollInfoFrame\\Character-Plus",
                {
                    size = 14,
                    color = isBlockedView and { 1.0, 0.45, 0.45 } or { 0.45, 0.95, 0.55 },
                    tooltipFn = function()
                        return isBlockedView and ("+ " .. L["Block"]) or ("+ " .. L["Friend"])
                    end,
                }
            )
        end
    end
    if frame.socialSortBtn then
        local curSMode = (ns.db and ns.db.settings and ns.db.settings.socialSortBy) or "smart"
        Theme:SetIconToggle(frame.socialSortBtn, curSMode ~= "smart", { 0.35, 0.78, 1.0 })
    end
    if frame.socialOfflineBtn then
        local showSocOff = not (ns.db and ns.db.settings and ns.db.settings.socialShowOffline == false)
        Theme:ApplyOnlineOfflineOrb(frame.socialOfflineBtn, showSocOff, 24, 22)
        if activeTab == "social" and UI._ReflowSocialChipsBar then
            UI._ReflowSocialChipsBar()
        end
    end
    local isCompactNow = (ns.db and ns.db.settings and ns.db.settings.compactListRows == true)
    if frame.sortBtn then
        local mode = (ns.db and ns.db.settings and ns.db.settings.sortBy) or "status"
        Theme:SetIconToggle(frame.sortBtn, mode ~= "status", { 0.35, 0.78, 1.0 })
    end
    if frame.watchOfflineBtn then
        local showWOff = not (ns.db and ns.db.settings and ns.db.settings.watchlistShowOffline == false)
        Theme:ApplyOnlineOfflineOrb(frame.watchOfflineBtn, showWOff, 24, 22)
    end
    if scrollList and scrollList.SetRowHeight then
        scrollList:SetRowHeight(isCompactNow and 26 or (activeTab == "social" and 44 or 40))
    end
    if frame.altsGoldText and ns.Store then
        frame.altsGoldText:SetText(L["Total Gold"] .. ": " .. Compat.FormatMoney(ns.Store:GetTotalAltsGold(true)))
    end

    if ReflowFilterBar then
        ReflowFilterBar()
    end
    if ReflowWatchBar then
        ReflowWatchBar()
    end

    local isEmbedded = embeddedState.active == true
    local singleEmbedded = IsSingleTabEmbedded()
    local isBlizz = (not isEmbedded) and Theme:IsBlizzard() and frame.blizzChrome ~= nil
    if frame.tabBar and frame.tabBar:IsShown() ~= (not singleEmbedded) then
        frame.tabBar:SetShown(not singleEmbedded)
    end
    local contentAnchorSig = (activeTab == "watchlist" and "W:" or (activeTab == "social" and "S2:" or (isFullPanel and "F:" or "L:")))
        .. (isEmbedded and "E:" or "S:") .. (singleEmbedded and "1:" or "0:") .. (isBlizz and "B" or "N")
    if frame._scContentAnchorSig ~= contentAnchorSig then
        frame._scContentAnchorSig = contentAnchorSig
        frame.content:ClearAllPoints()
        if activeTab == "watchlist" then
            frame.content:SetPoint("TOPLEFT", frame.watchBar, "BOTTOMLEFT", 0, -6)
        elseif activeTab == "social" and frame.socialChipsBar then
            frame.content:SetPoint("TOPLEFT", frame.socialChipsBar, "BOTTOMLEFT", 0, -5)
        elseif isFullPanel then
            if isEmbedded then
                if singleEmbedded then
                    frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
                else
                    frame.content:SetPoint("TOPLEFT", frame.tabBar, "BOTTOMLEFT", 0, -8)
                end
            elseif isBlizz then
                frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -93)
            else
                frame.content:SetPoint("TOPLEFT", frame.tabBar, "BOTTOMLEFT", 0, -10)
            end
        else
            frame.content:SetPoint("TOPLEFT", frame.filterBar, "BOTTOMLEFT", 0, -6)
        end
        local rightInset = isEmbedded and (singleEmbedded and -6 or -8) or (isBlizz and -14 or -12)
        local bottomInset = isEmbedded and (singleEmbedded and 6 or 8) or (isBlizz and 18 or 16)
        frame.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", rightInset, bottomInset)
    end

    if activeTab == "clan" and not clanPanel then
        clanPanel = CreateClanPanel(frame.content)
    elseif activeTab == "group" and not groupPanel and ns.SocialPanels and ns.SocialPanels.CreateGroupPanel then
        groupPanel = ns.SocialPanels:CreateGroupPanel(frame.content)
        if groupPanel then groupPanel:Hide() end
    elseif activeTab == "chat" and not chatPanel and ns.SocialPanels and ns.SocialPanels.CreateChatPanel then
        chatPanel = ns.SocialPanels:CreateChatPanel(frame.content)
        if chatPanel then chatPanel:Hide() end
    elseif activeTab == "alts" and not altsPanel and ns.SocialPanels and ns.SocialPanels.CreateAltsPanel then
        altsPanel = ns.SocialPanels:CreateAltsPanel(frame.content)
        if altsPanel then altsPanel:Hide() end
    end
    if activeTab == "alts" and altsPanel and pendingAltsNav and altsPanel.ApplyNavigation then
        altsPanel:ApplyNavigation(pendingAltsNav)
        pendingAltsNav = nil
    end

    local function SyncFramePanelAttachment(panel, tabKey)
        if not panel or IsSingleEmbedActive(tabKey) then
            return false
        end
        if panel:GetParent() ~= frame.content then
            panel:SetParent(frame.content)
            panel:ClearAllPoints()
            panel:SetAllPoints(frame.content)
            SyncSubtreeButtonLayers(panel, 12)
        end
        if tabKey == "clan" and activeTab == "clan" then
            panel._dirty = nil
        end
        panel:SetShown(activeTab == tabKey)
        return activeTab == tabKey
    end

    local showClan = SyncFramePanelAttachment(clanPanel, "clan")
    local showGroup = SyncFramePanelAttachment(groupPanel, "group")
    local showChat = SyncFramePanelAttachment(chatPanel, "chat")
    local showAlts = SyncFramePanelAttachment(altsPanel, "alts")

    local showPendingInvite = false
    if activeTab == "social" and frame.socialInviteBanner and ns.Social and ns.Social.GetPendingBNetInvites then
        local invList = ns.Social:GetPendingBNetInvites()
        if type(invList) == "table" and #invList > 0 then
            local firstInv = invList[1]
            showPendingInvite = true
            frame.socialInviteBanner._inviteID = firstInv.inviteID
            local extraTxt = #invList > 1 and (" (+" .. tostring(#invList - 1) .. ")") or ""
            frame.socialInviteBanner.text:SetText("|cff70b5f9" .. L["Pending Battle.net Friend Invite"] .. ":|r " .. tostring(firstInv.accountName or "Battle.net") .. extraTxt)
        end
    end
    if frame.socialInviteBanner then
        frame.socialInviteBanner:SetShown(showPendingInvite)
    end
    local scrollBannerSig = (showPendingInvite and frame.socialInviteBanner) and "banner" or "full"
    if scrollList._scBannerAnchorSig ~= scrollBannerSig then
        scrollList._scBannerAnchorSig = scrollBannerSig
        scrollList.container:ClearAllPoints()
        if scrollBannerSig == "banner" then
            scrollList.container:SetPoint("TOPLEFT", frame.socialInviteBanner, "BOTTOMLEFT", 0, -6)
            scrollList.container:SetPoint("BOTTOMRIGHT", frame.content, "BOTTOMRIGHT", 0, 0)
        else
            scrollList.container:SetAllPoints(frame.content)
        end
    end
    scrollList.container:SetShown(not isFullPanel)

    if activeTab == "clan" then
        if showClan then
            UpdateClanPanel()
        end
    elseif activeTab == "group" and groupPanel then
        if showGroup then
            groupPanel:Refresh(resetScroll)
        end
    elseif activeTab == "chat" and chatPanel then
        if showChat then
            chatPanel:Refresh(resetScroll)
        end
    elseif activeTab == "alts" and altsPanel then
        if showAlts then
            altsPanel:Refresh(resetScroll)
        end
    else
        local emptyText = activeTab == "watchlist" and L["Watchlist is empty."] or L["No entries match your filter."]
        scrollList:SetData(BuildFilteredRows(), emptyText, resetScroll)
    end

    UpdateWhoButtons()
    if frame and frame:IsShown() then
        if embeddedState.active
            and not embeddedState._suppressingHost
            and embeddedState.host
            and IsSocialHostFrame(embeddedState.host)
            and (type(embeddedState.alphaHiddenSocialFrames) ~= "table" or next(embeddedState.alphaHiddenSocialFrames) == nil)
            and self.HideEmbeddedHostSubframes
        then
            self:HideEmbeddedHostSubframes(embeddedState.host)
        end
        UI:SyncFrameSectionLayers()
    end
    UI:EnsureMainFrameDraggable()
end

local function MaybePromptThemePicker()
    if ns.db and ns.db.settings and not ns.db.settings.themeChosen then
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if not inCombat and Theme and Theme.ShowThemeWelcomePicker then
            Theme:ShowThemeWelcomePicker()
        end
    end
end

local function MaybePromptTabTutorial(tabId)
    if not (tabId and Theme and Theme.PromptWindowTutorial) then
        return
    end
    if ns.db and ns.db.settings and not ns.db.settings.themeChosen then
        return
    end
    if _G.SocialCentralThemeWelcomePicker and _G.SocialCentralThemeWelcomePicker:IsShown() then
        return
    end
    local hBtn = frame and frame._scTabHelpBtns and frame._scTabHelpBtns[tabId]
    if not hBtn then
        if tabId == "group" and groupPanel then hBtn = groupPanel._scHelpBtn
        elseif tabId == "chat" and chatPanel then hBtn = chatPanel._scHelpBtn
        elseif tabId == "alts" and altsPanel then hBtn = altsPanel._scHelpBtn
        end
    end
    local hOpts = hBtn and hBtn._scHelpOpts
    if not (hOpts and type(hOpts.steps) == "table" and #hOpts.steps > 0) then
        return
    end
    local tabLabel = (tabButtons[tabId] and tabButtons[tabId].baseLabel) or (hBtn and hBtn._scHelpTitle) or tabId
    local function IsTabStillVisible()
        if activeTab ~= tabId then return false end
        if frame and frame:IsVisible() then return true end
        local cont = embedContainers and embedContainers[tabId]
        return cont and cont._active and cont:IsVisible() == true or false
    end
    Theme:PromptWindowTutorial({
        tutorialKey = "tabPrompt_" .. tostring(tabId),
        title = tabLabel,
        guideSpec = {
            key = "tab_" .. tostring(tabId),
            title = tabLabel,
            defaultTarget = hOpts.target,
            isAnchorVisible = IsTabStillVisible,
            steps = hOpts.steps,
        },
        isWindowVisible = IsTabStillVisible,
    })
end
UI._maybePromptTabTutorial = MaybePromptTabTutorial

local function IsSafeHostObj(obj, allowProtected)
    if not obj then return false end
    if obj.IsForbidden then
        local okF, forb = pcall(obj.IsForbidden, obj)
        if not okF or forb then return false end
    end
    if not allowProtected and obj.IsProtected then
        local okP, prot = pcall(obj.IsProtected, obj)
        if not okP or prot then return false end
    end
    return true
end

local elevatedHostChrome = setmetatable({}, { __mode = "k" })

local function SetMinFrameLevel(obj, minLevel)
    if obj and IsSafeHostObj(obj) and obj.GetFrameLevel and obj.SetFrameLevel then
        local target = math.min(9600, minLevel or 1)
        elevatedHostChrome[obj] = true
        local cur = obj:GetFrameLevel() or 0
        if cur < target then
            pcall(obj.SetFrameLevel, obj, target)
        end
    end
end

local function ScanEmbeddedHostContentMax(hostFrame)
    local contentMax = (hostFrame.GetFrameLevel and hostFrame:GetFrameLevel()) or 1
    local hostName = hostFrame.GetName and hostFrame:GetName() or nil
    local skip = {
        [hostFrame.NineSlice or false] = true,
        [hostFrame.BorderFrame or false] = true,
        [hostFrame.PortraitContainer or false] = true,
        [hostFrame.PortraitOverlay or false] = true,
        [hostFrame.TitleContainer or false] = true,
        [hostFrame.CloseButton or false] = true,
        [hostFrame.MaximizeMinimizeFrame or false] = true,
        [hostFrame.ModeTabs or false] = true,
        [(hostName and _G[hostName .. "CloseButton"]) or false] = true,
        [(hostName and _G[hostName .. "PortraitFrame"]) or false] = true,
        [frame or false] = true,
        [_G.SocialCentralLFGSubPanel or false] = true,
        [_G.SocialCentralWorldMapBuffsPill or false] = true,
        [_G.SocialCentralLFGNativeBridgeBar or false] = true,
    }
    if ns.LFGFrameTab then
        for _, scTab in pairs({ ns.LFGFrameTab.sideTab, ns.LFGFrameTab.socialTab, ns.LFGFrameTab.guildTab, ns.LFGFrameTab.charTab, ns.LFGFrameTab.mapSideTab }) do
            if scTab then
                skip[scTab] = true
            end
        end
    end
    local hRight = hostFrame.GetRight and hostFrame:GetRight() or nil
    local hLeft = hostFrame.GetLeft and hostFrame:GetLeft() or nil
    local hTop = hostFrame.GetTop and hostFrame:GetTop() or nil
    local visited = {}
    local Scan
    local function ScanVararg(depth, ...)
        local n = select("#", ...)
        for i = 1, n do
            local child = select(i, ...)
            if child and not visited[child] then
                Scan(child, depth)
            end
        end
    end
    Scan = function(node, depth)
        if not node or depth <= 0 or visited[node] then
            return
        end
        visited[node] = true
        if node ~= hostFrame then
            if not IsSafeHostObj(node)
                or skip[node]
                or elevatedHostChrome[node]
                or IsAnyEmbedContainer(node)
                or (node.IsShown and not node:IsShown())
            then
                return
            end
            local cLeft = node.GetLeft and node:GetLeft()
            local cTop = node.GetTop and node:GetTop()
            local cW = (node.GetWidth and node:GetWidth()) or 0
            local cH = (node.GetHeight and node:GetHeight()) or 0
            local isSideTab = hRight and cLeft and cLeft >= (hRight - 38) and cW >= 20 and cW <= 84 and (cH == 0 or (cH >= 24 and cH <= 96))
            local isPortraitCorner = hLeft and hTop and cLeft and cTop and cLeft <= (hLeft + 34) and cTop >= (hTop - 34) and cW <= 115 and cH <= 115
            if isSideTab or isPortraitCorner then
                return
            end
            local lvl = (node.GetFrameLevel and node:GetFrameLevel()) or 0
            if lvl > contentMax then
                contentMax = lvl
            end
        end
        if depth > 1 and node.GetChildren then
            ScanVararg(depth - 1, node:GetChildren())
        end
    end
    Scan(hostFrame, (hostFrame == _G.WorldMapFrame) and 6 or 5)
    return contentMax
end

local function ElevateEmbeddedHostChrome(hostFrame, minControlLevel)
    if not hostFrame then return end
    local hostName = hostFrame.GetName and hostFrame:GetName() or nil
    SetMinFrameLevel(hostFrame.CloseButton or (hostName and _G[hostName .. "CloseButton"]), minControlLevel + 12)
    SetMinFrameLevel(hostFrame.MaximizeMinimizeFrame, minControlLevel + 10)
    SetMinFrameLevel(hostFrame.PortraitContainer, minControlLevel + 8)
    SetMinFrameLevel(hostFrame.PortraitOverlay, minControlLevel + 9)
    SetMinFrameLevel(hostName and _G[hostName .. "PortraitFrame"], minControlLevel + 8)
    SetMinFrameLevel(hostFrame.TitleContainer, minControlLevel + 5)
    SetMinFrameLevel(hostFrame.NineSlice, minControlLevel + 5)
    if hostFrame.BorderFrame then
        SetMinFrameLevel(hostFrame.BorderFrame, minControlLevel + 5)
        SetMinFrameLevel(hostFrame.BorderFrame.NineSlice, minControlLevel + 5)
        SetMinFrameLevel(hostFrame.BorderFrame.PortraitContainer, minControlLevel + 8)
        SetMinFrameLevel(hostFrame.BorderFrame.TitleContainer, minControlLevel + 6)
        SetMinFrameLevel(hostFrame.BorderFrame.CloseButton, minControlLevel + 14)
        SetMinFrameLevel(hostFrame.BorderFrame.MaximizeMinimizeFrame, minControlLevel + 12)
    end

    local scSideTabs = {}
    if ns.LFGFrameTab then
        for _, scTab in pairs({ ns.LFGFrameTab.sideTab, ns.LFGFrameTab.socialTab, ns.LFGFrameTab.guildTab, ns.LFGFrameTab.charTab, ns.LFGFrameTab.mapSideTab }) do
            if scTab then
                scSideTabs[scTab] = true
            end
        end
    end

    local hRight = hostFrame.GetRight and hostFrame:GetRight() or nil
    local hLeft = hostFrame.GetLeft and hostFrame:GetLeft() or nil
    local hTop = hostFrame.GetTop and hostFrame:GetTop() or nil
    if hostFrame.GetChildren then
        for _, child in ipairs({ hostFrame:GetChildren() }) do
            if child ~= frame and not IsAnyEmbedContainer(child) and child ~= _G.SocialCentralLFGSubPanel and not scSideTabs[child] then
                local cLeft = child.GetLeft and child:GetLeft()
                local cTop = child.GetTop and child:GetTop()
                local cW = (child.GetWidth and child:GetWidth()) or 0
                local cH = (child.GetHeight and child:GetHeight()) or 0
                local cName = child.GetName and child:GetName() or ""
                if hRight and cLeft and cLeft >= (hRight - 38) and cW >= 20 and cW <= 84 then
                    SetMinFrameLevel(child, minControlLevel + 8)
                    if child.GetChildren then
                        for _, subTab in ipairs({ child:GetChildren() }) do
                            if not scSideTabs[subTab] then
                                SetMinFrameLevel(subTab, minControlLevel + 9)
                            end
                        end
                    end
                elseif cName:find("Portrait") or (hLeft and hTop and cLeft and cTop and cLeft <= (hLeft + 34) and cTop >= (hTop - 34) and cW > 0 and cW <= 115 and cH > 0 and cH <= 115) then
                    SetMinFrameLevel(child, minControlLevel + 8)
                end
            end
        end
    end
    if hostFrame.socialTabPool and hostFrame.socialTabPool.EnumerateActive then
        for tab in hostFrame.socialTabPool:EnumerateActive() do
            SetMinFrameLevel(tab, minControlLevel + 8)
        end
    end
    if hostFrame.ModeTabs and hostFrame.ModeTabs.Tabs then
        for _, tab in ipairs(hostFrame.ModeTabs.Tabs) do
            SetMinFrameLevel(tab, minControlLevel + 8)
        end
    end
    if ns.LFGFrameTab then
        for _, scTab in pairs({ ns.LFGFrameTab.sideTab, ns.LFGFrameTab.socialTab, ns.LFGFrameTab.guildTab, ns.LFGFrameTab.charTab, ns.LFGFrameTab.mapSideTab }) do
            if scTab and scTab.GetParent and scTab:GetParent() == hostFrame then
                SetMinFrameLevel(scTab, minControlLevel + 35)
                if scTab.SetHitRectInsets then
                    scTab:SetHitRectInsets(0, 0, 0, 0)
                end
                if scTab.scUnreadBadge then
                    if scTab.scUnreadBadge.EnableMouse then
                        scTab.scUnreadBadge:EnableMouse(false)
                    end
                    if scTab.scUnreadBadge.SetFrameLevel then
                        scTab.scUnreadBadge:SetFrameLevel(math.min(9600, (scTab:GetFrameLevel() or (minControlLevel + 35)) + 6))
                    end
                end
            end
        end
    end
end

function UI:IsEmbeddedFor(hostFrame, tabId)
    if hostFrame then
        local tabKey = ResolveSinglePanelEmbedKey(hostFrame)
        if tabKey then
            local c = embedContainers[tabKey]
            if not (c and c:IsShown() and c._active and c._host == hostFrame) then
                return false
            end
            if tabId and tabId ~= tabKey then
                return false
            end
            return true
        end
    end
    if not hostFrame and tabId and IsSingleEmbedActive(tabId) then
        return true
    end
    if not (frame and frame:IsShown() and embeddedState.active) then
        return false
    end
    if hostFrame and embeddedState.host ~= hostFrame then
        return false
    end
    if tabId and activeTab ~= tabId then
        return false
    end
    return true
end

function UI:IsAltsVisible()
    local c = embedContainers and embedContainers.alts
    if c and c:IsShown() and c._active then
        return true
    end
    return frame ~= nil and frame:IsShown() and activeTab == "alts"
end

local hiddenCharSubframes = {}
local hiddenCharChildren = {}
local hiddenCommunitiesChildren = {}
local hiddenWorldMapSubframes = {}

local function IsHostChromeOrTabChild(hostFrame, child)
    if not child then return true end
    local hostName = hostFrame.GetName and hostFrame:GetName() or nil
    if child == frame
        or IsAnyEmbedContainer(child)
        or child == _G.SocialCentralLFGSubPanel
        or child == hostFrame.NineSlice
        or child == hostFrame.BorderFrame
        or child == hostFrame.PortraitContainer
        or child == hostFrame.PortraitOverlay
        or child == hostFrame.TitleContainer
        or child == hostFrame.TitleDragArea
        or child == hostFrame.TitleBg
        or child == hostFrame.TopTileStreaks
        or child == hostFrame.Bg
        or child == hostFrame.CloseButton
        or (hostName and child == _G[hostName .. "CloseButton"])
        or (hostName and child == _G[hostName .. "PortraitFrame"])
        or child == hostFrame.MaximizeMinimizeFrame
        or child == hostFrame.ChatTab
        or child == hostFrame.RosterTab
        or child == hostFrame.GuildBenefitsTab
        or child == hostFrame.GuildInfoTab
        or child == hostFrame.GuildPreferredPlaySettingsTab
        or child == hostFrame.PerkRewardsTab
        or child == hostFrame.ListingTab
        or child == hostFrame.BrowsingTab
        or child == hostFrame.WhoListingTab
    then
        return true
    end
    local cName = child.GetName and child:GetName() or ""
    if cName:find("Portrait")
        or cName:find("SocialCentral")
        or cName:find("SideTab")
        or cName:find("^CharacterFrameTab%d+$")
        or cName:find("Tab%d+$")
        or cName:find("CloseButton$")
        or cName:find("Close$")
        or cName:find("TitleBg$")
        or cName:find("TopTileStreaks$")
        or cName:find("Title")
        or cName:find("Drag")
        or cName:find("Header")
        or cName:find("Mover")
    then
        return true
    end
    local hTop = hostFrame.GetTop and hostFrame:GetTop() or nil
    local cTop = child.GetTop and child:GetTop()
    local cH = (child.GetHeight and child:GetHeight()) or 0
    if hTop and cTop and cTop >= (hTop - 26) and cH > 0 and cH <= 32 then
        return true
    end
    local hRight = hostFrame.GetRight and hostFrame:GetRight() or nil
    local cLeft = child.GetLeft and child:GetLeft()
    local cW = (child.GetWidth and child:GetWidth()) or 0
    if hRight and cLeft and cLeft >= (hRight - 38) and cW >= 20 and cW <= 84 and (cH == 0 or (cH >= 24 and cH <= 96)) then
        return true
    end
    return false
end

local function AppendUniqueItem(list, item)
    if not item then
        return
    end
    for i = 1, #list do
        if list[i] == item then
            return
        end
    end
    list[#list + 1] = item
end

local function SuppressedFrameIsMouseOver()
    return false
end

local function IsPaneSkipForMouseSuppress(root, topPane, hostFrame)
    if not root or root == topPane then
        return false
    end
    if hostFrame and IsHostChromeOrTabChild(hostFrame, root) then
        return true
    end
    if root == frame or IsAnyEmbedContainer(root) or root == _G.SocialCentralLFGSubPanel or root == _G.SocialCentralLFGNativeBridgeBar then
        return true
    end
    local rName = (root.GetName and root:GetName()) or ""
    if rName ~= "" and (rName:find("SocialCentral", 1, true) or rName:find("SideTab", 1, true) or rName:find("Close", 1, true)) then
        return true
    end
    if ns.LFGFrameTab then
        for _, scTab in pairs({ ns.LFGFrameTab.sideTab, ns.LFGFrameTab.socialTab, ns.LFGFrameTab.guildTab, ns.LFGFrameTab.charTab, ns.LFGFrameTab.mapSideTab }) do
            if root == scTab then
                return true
            end
        end
    end
    local parent = root.GetParent and root:GetParent()
    if hostFrame and (not parent or parent == hostFrame) then
        local hRight = hostFrame.GetRight and hostFrame:GetRight() or nil
        local cLeft = root.GetLeft and root:GetLeft()
        local cW = (root.GetWidth and root:GetWidth()) or 0
        local cH = (root.GetHeight and root:GetHeight()) or 0
        if hRight and cLeft and cLeft >= (hRight - 22) and cW >= 20 and cW <= 84 and (cH == 0 or (cH >= 24 and cH <= 96)) then
            return true
        end
    end
    return false
end

local function IsHostCurrentlyEmbedded(hostFrame)
    if not hostFrame then
        return false
    end
    if embeddedState.active and embeddedState.host == hostFrame and frame and frame.IsShown and frame:IsShown() then
        return true
    end
    if IsSocialHostFrame(hostFrame) and embeddedState.active and IsSocialHostFrame(embeddedState.host) and frame and frame.IsShown and frame:IsShown() then
        return true
    end
    for _, c in pairs(embedContainers) do
        if c and c._active and c._host == hostFrame and c.IsShown and c:IsShown() then
            return true
        end
    end
    if hostFrame == _G.LFGParentFrame and ns.LFGFrameTab and ns.LFGFrameTab.active and ns.LFGFrameTab.subPanel and ns.LFGFrameTab.subPanel.IsShown and ns.LFGFrameTab.subPanel:IsShown() then
        return true
    end
    return false
end

local function IsSuppressedHostFrameOrDescendant(owner)
    if not owner or owner == _G.UIParent or owner == _G.WorldFrame then
        return false, nil, nil
    end
    local savedCtrls = embeddedState.mouseDisabledHostCtrls
    local alphaSoc = embeddedState.alphaHiddenSocialFrames
    local alphaChar = embeddedState.alphaHiddenCharFrames

    local cur = owner
    local prev = owner
    for _ = 1, 20 do
        if not cur or cur == _G.UIParent or cur == _G.WorldFrame then
            break
        end
        if cur == frame
            or IsAnyEmbedContainer(cur)
            or cur == _G.SocialCentralLFGSubPanel
            or cur == _G.SocialCentralLFGNativeBridgeBar
            or cur == _G.SocialCentralWorldMapBuffsPill
            or cur == _G.SocialCentralWorldMapQuickBtn
        then
            return false, nil, nil
        end
        local curName = (cur.GetName and cur:GetName()) or ""
        if curName ~= "" and curName:find("SocialCentral", 1, true) then
            return false, nil, nil
        end
        if ns.LFGFrameTab then
            if cur == ns.LFGFrameTab.sideTab
                or cur == ns.LFGFrameTab.socialTab
                or cur == ns.LFGFrameTab.guildTab
                or cur == ns.LFGFrameTab.charTab
                or cur == ns.LFGFrameTab.mapSideTab
            then
                return false, nil, nil
            end
        end
        local ctrlMeta = savedCtrls and savedCtrls[cur]
        if type(ctrlMeta) == "table" then
            local recHost = ctrlMeta.host
            if not recHost or IsHostCurrentlyEmbedded(recHost) then
                return true, cur, recHost
            end
        end
        if alphaSoc and alphaSoc[cur] ~= nil then
            local socHost = (IsHostCurrentlyEmbedded(_G.SocialUIFrame) and _G.SocialUIFrame)
                or (IsHostCurrentlyEmbedded(_G.FriendsFrame) and _G.FriendsFrame)
                or nil
            if socHost then
                return true, cur, socHost
            end
        end
        if alphaChar and alphaChar[cur] ~= nil then
            local charHost = _G.CharacterFrame
            if IsHostCurrentlyEmbedded(charHost) then
                return true, cur, charHost
            end
        end
        if IsHostCurrentlyEmbedded(cur) then
            if prev == cur then
                return false, nil, nil
            end
            local isPreservedChrome = IsHostChromeOrTabChild(cur, prev)
            if not isPreservedChrome and IsSocialHostFrame(cur) and prev ~= cur then
                local hTop = cur.GetTop and cur:GetTop() or nil
                local pBottom = prev.GetBottom and prev:GetBottom() or nil
                if hTop and pBottom and pBottom >= (hTop - 64) then
                    isPreservedChrome = true
                end
            end
            if not isPreservedChrome then
                return true, (prev ~= cur and prev) or owner, cur
            end
            return false, nil, nil
        end
        prev = cur
        cur = cur.GetParent and cur:GetParent() or nil
    end
    return false, nil, nil
end

local function HideNativeHostTooltips()
    if _G.FriendsTooltip and _G.FriendsTooltip.IsShown and _G.FriendsTooltip:IsShown() and _G.FriendsTooltip.Hide then
        pcall(_G.FriendsTooltip.Hide, _G.FriendsTooltip)
    end
    if _G.GameTooltip and _G.GameTooltip.IsShown and _G.GameTooltip:IsShown() then
        local owner = _G.GameTooltip.GetOwner and _G.GameTooltip:GetOwner() or nil
        if owner and IsSuppressedHostFrameOrDescendant(owner) then
            pcall(_G.GameTooltip.Hide, _G.GameTooltip)
        end
    end
end

local function SuppressSubtreeChildrenVararg(visitFn, hostFrame, nextDepth, topPane, visited, ...)
    local n = select("#", ...)
    for i = 1, n do
        local child = select(i, ...)
        if child and not visited[child] then
            visitFn(child, hostFrame, nextDepth, topPane, visited)
        end
    end
end

local function SuppressHostSubtreeMouse(root, hostFrame, depth, topPane, visited)
    topPane = topPane or root
    visited = visited or {}
    if not root or (depth or 0) <= 0 or visited[root] or not IsSafeHostObj(root, true) then
        return
    end
    visited[root] = true
    if root ~= hostFrame and IsPaneSkipForMouseSuppress(root, topPane, hostFrame) then
        return
    end
    embeddedState.mouseDisabledHostCtrls = embeddedState.mouseDisabledHostCtrls or {}
    local saved = embeddedState.mouseDisabledHostCtrls
    local canMutateProtectedState = IsSafeHostObj(root) and not ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")))
    if root ~= hostFrame then
        if saved[root] == nil then
            local mOn = (root.IsMouseEnabled and root:IsMouseEnabled()) == true
            local wOn = (root.IsMouseWheelEnabled and root:IsMouseWheelEnabled()) == true
            local rawMo = (type(root) == "table") and rawget(root, "IsMouseOver") or nil
            saved[root] = { m = mOn, w = wOn, mo = rawMo or false, host = hostFrame }
        elseif type(saved[root]) == "table" and not saved[root].host and hostFrame then
            saved[root].host = hostFrame
        end
        if canMutateProtectedState then
            if root.IsMouseEnabled and root:IsMouseEnabled() and root.EnableMouse then
                pcall(root.EnableMouse, root, false)
            end
            if root.IsMouseWheelEnabled and root:IsMouseWheelEnabled() and root.EnableMouseWheel then
                pcall(root.EnableMouseWheel, root, false)
            end
            if type(root.UnlockHighlight) == "function" then
                pcall(root.UnlockHighlight, root)
            end
        end
        if type(root) == "table" and rawget(root, "IsMouseOver") ~= SuppressedFrameIsMouseOver then
            pcall(rawset, root, "IsMouseOver", SuppressedFrameIsMouseOver)
        end
        if _G.GameTooltip and _G.GameTooltip.IsShown and _G.GameTooltip:IsShown() and _G.GameTooltip.IsOwned and _G.GameTooltip:IsOwned(root) then
            pcall(_G.GameTooltip.Hide, _G.GameTooltip)
        end
    end
    if (depth or 0) > 1 then
        local nextDepth = (depth or 1) - 1
        if root.GetChildren then
            SuppressSubtreeChildrenVararg(SuppressHostSubtreeMouse, hostFrame, nextDepth, topPane, visited, root:GetChildren())
        end
        if type(root) == "table" then
            local st = root.ScrollTarget
            if st and st ~= root and not visited[st] then
                SuppressHostSubtreeMouse(st, hostFrame, nextDepth, topPane, visited)
            end
            local sb = root.ScrollBox
            if sb and sb ~= root and not visited[sb] then
                SuppressHostSubtreeMouse(sb, hostFrame, nextDepth, topPane, visited)
            end
        end
    end
end

local function InstallEmbeddedTooltipGuard()
    local function SuppressOwnerAncestryAndSubtree(owner, rootPane, recHost)
        local targetHost = recHost or embeddedState.host
        local visited = {}
        local node = owner
        for _ = 1, 12 do
            if not node or node == _G.UIParent or node == _G.WorldFrame or node == targetHost then
                break
            end
            SuppressHostSubtreeMouse(node, targetHost, 3, rootPane or node, visited)
            if node == rootPane then
                break
            end
            node = node.GetParent and node:GetParent() or nil
        end
        if rootPane and rootPane ~= owner and not visited[rootPane] then
            SuppressHostSubtreeMouse(rootPane, targetHost, 6, rootPane, visited)
        end
    end

    local function HandleSuppressedTooltip(tip, owner, allowRecentBlocked)
        if not tip then return end
        local blocked, rootPane, recHost = IsSuppressedHostFrameOrDescendant(owner)
        if not blocked and allowRecentBlocked and (not owner) and tip._scBlockedOwner ~= nil then
            local nowT = (GetTime and GetTime()) or 0
            if (nowT - (tip._scBlockedOwnerAt or 0)) <= 0.15 then
                blocked, rootPane, recHost = IsSuppressedHostFrameOrDescendant(tip._scBlockedOwner)
                if blocked then
                    owner = tip._scBlockedOwner
                end
            else
                tip._scBlockedOwner = nil
                tip._scBlockedOwnerAt = nil
            end
        end
        if blocked then
            tip._scBlockedOwner = owner or rootPane or recHost
            tip._scBlockedOwnerAt = (GetTime and GetTime()) or 0
            if owner then
                SuppressOwnerAncestryAndSubtree(owner, rootPane, recHost)
            elseif rootPane then
                SuppressHostSubtreeMouse(rootPane, recHost or embeddedState.host, 10, rootPane)
            end
            if tip.ClearLines then
                pcall(tip.ClearLines, tip)
            end
            if tip.Hide then
                pcall(tip.Hide, tip)
            end
            return true
        end
        return false
    end

    if not embeddedState._tooltipGuardHooked and hooksecurefunc and _G.GameTooltip then
        embeddedState._tooltipGuardHooked = true
        if type(_G.GameTooltip.SetOwner) == "function" then
            hooksecurefunc(_G.GameTooltip, "SetOwner", function(tip, owner)
                if not tip then return end
                if not HandleSuppressedTooltip(tip, owner, false) then
                    tip._scBlockedOwner = nil
                    tip._scBlockedOwnerAt = nil
                end
            end)
        end
        if type(_G.GameTooltip.Show) == "function" then
            hooksecurefunc(_G.GameTooltip, "Show", function(tip)
                local owner = tip and tip.GetOwner and tip:GetOwner() or nil
                HandleSuppressedTooltip(tip, owner, true)
            end)
        end
        if _G.GameTooltip.HookScript then
            _G.GameTooltip:HookScript("OnShow", function(tip)
                local owner = tip and tip.GetOwner and tip:GetOwner() or nil
                HandleSuppressedTooltip(tip, owner, true)
            end)
        end
    end
    if _G.FriendsTooltip and _G.FriendsTooltip.HookScript and not _G.FriendsTooltip._scGuardHooked then
        _G.FriendsTooltip._scGuardHooked = true
        _G.FriendsTooltip:HookScript("OnShow", function(selfTip)
            if embeddedState.active and IsSocialHostFrame(embeddedState.host) then
                pcall(selfTip.Hide, selfTip)
            end
        end)
    end
end

local function RestoreSuppressedHostMouse(hostFrame)
    if type(embeddedState.mouseDisabledHostCtrls) ~= "table" then
        return
    end
    local inCombatNow = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    for ctrl, prev in pairs(embeddedState.mouseDisabledHostCtrls) do
        local matchesHost = (not hostFrame) or (not prev.host) or (prev.host == hostFrame) or (IsSocialHostFrame(hostFrame) and IsSocialHostFrame(prev.host))
        if type(prev) == "table" and matchesHost then
            if ctrl and IsSafeHostObj(ctrl, true) then
                if type(ctrl) == "table" and rawget(ctrl, "IsMouseOver") == SuppressedFrameIsMouseOver then
                    pcall(rawset, ctrl, "IsMouseOver", (prev.mo and prev.mo ~= SuppressedFrameIsMouseOver) and prev.mo or nil)
                end
                if not inCombatNow and IsSafeHostObj(ctrl) then
                    if prev.m and ctrl.EnableMouse then
                        pcall(ctrl.EnableMouse, ctrl, true)
                    end
                    if prev.w and ctrl.EnableMouseWheel then
                        pcall(ctrl.EnableMouseWheel, ctrl, true)
                    end
                end
            end
            embeddedState.mouseDisabledHostCtrls[ctrl] = nil
        end
    end
end

local function SuppressSocialHostPanes(hostFrame)
    if not IsSocialHostFrame(hostFrame) then
        return false
    end
    -- Keep Forever SocialUIFrame / FriendsFrame panes shown at alpha 0 (Rule #17: preserves 2nd-press 'O' toggle) while disabling mouse & IsMouseOver so native rows and third-party overlays (e.g. OldFriendsList) never bleed through.
    embeddedState.alphaHiddenSocialFrames = embeddedState.alphaHiddenSocialFrames or {}
    local alphaSoc = embeddedState.alphaHiddenSocialFrames
    local socialPaneCandidates = {}
    local function AddSocialCandidate(cand)
        if cand and IsSafeHostObj(cand, true) then
            AppendUniqueItem(socialPaneCandidates, cand)
        end
    end
    AddSocialCandidate(_G.FriendsListFrame)
    AddSocialCandidate(_G.IgnoreListFrame)
    AddSocialCandidate(_G.WhoFrame)
    AddSocialCandidate(_G.QuickJoinFrame)
    AddSocialCandidate(_G.RaidFrame)
    AddSocialCandidate(_G.RecruitAFriendFrame)
    AddSocialCandidate(_G.FriendsTabHeader)
    AddSocialCandidate(_G.FriendsFrameInset)
    for _, socRoot in pairs({ hostFrame, _G.SocialUIFrame, _G.FriendsFrame }) do
        if socRoot and IsSafeHostObj(socRoot, true) then
            AddSocialCandidate(socRoot.FriendsListFrame)
            AddSocialCandidate(socRoot.FriendsList)
            AddSocialCandidate(socRoot.IgnoreListFrame)
            AddSocialCandidate(socRoot.IgnoreList)
            AddSocialCandidate(socRoot.WhoFrame)
            AddSocialCandidate(socRoot.WhoList)
            AddSocialCandidate(socRoot.GuildList)
            AddSocialCandidate(socRoot.QuickJoinFrame)
            AddSocialCandidate(socRoot.QuickJoin)
            AddSocialCandidate(socRoot.RaidFrame)
            AddSocialCandidate(socRoot.RaidList)
            AddSocialCandidate(socRoot.RecruitAFriend)
            AddSocialCandidate(socRoot.FriendsTabHeader)
            AddSocialCandidate(socRoot.Inset)
            if socRoot.GetChildren then
                local hTop = socRoot.GetTop and socRoot:GetTop() or nil
                for _, ch in ipairs({ socRoot:GetChildren() }) do
                    if IsSafeHostObj(ch, true) and not IsHostChromeOrTabChild(socRoot, ch) then
                        local cBottom = ch.GetBottom and ch:GetBottom() or nil
                        if not (hTop and cBottom and cBottom >= (hTop - 64)) then
                            AddSocialCandidate(ch)
                        end
                    end
                end
            end
        end
    end
    AddSocialCandidate(hostFrame.FriendsList)
    local visited = {}
    for i = 1, #socialPaneCandidates do
        local sub = socialPaneCandidates[i]
        if sub and not visited[sub] and IsSafeHostObj(sub, true) and not IsHostChromeOrTabChild(hostFrame, sub) then
            if alphaSoc[sub] == nil then
                alphaSoc[sub] = (sub.GetAlpha and sub:GetAlpha()) or 1
            end
            if sub.SetAlpha and (sub:GetAlpha() or 1) > 0 then
                pcall(sub.SetAlpha, sub, 0)
            end
            SuppressHostSubtreeMouse(sub, hostFrame, 8, sub, visited)
        end
    end
    return true
end

local function HideCharacterHostSubframes(hostFrame, _)
    if not hostFrame then return end
    HideNativeHostTooltips()
    InstallEmbeddedTooltipGuard()
    if SuppressSocialHostPanes(hostFrame) then
        return
    end
    local visited = {}
    if hostFrame == _G.CharacterFrame then
        embeddedState.alphaHiddenCharFrames = embeddedState.alphaHiddenCharFrames or {}
        embeddedState.hiddenCharModels = embeddedState.hiddenCharModels or {}
        local alphaHidden = embeddedState.alphaHiddenCharFrames
        local hiddenModels = embeddedState.hiddenCharModels
        local function HideModelIfShown(modelObj)
            if modelObj and IsSafeHostObj(modelObj) and modelObj.IsShown and modelObj:IsShown() and modelObj.Hide then
                AppendUniqueItem(hiddenModels, modelObj)
                pcall(modelObj.Hide, modelObj)
            end
        end
        local exclusiveCharMap = {
            PaperDollFrame = true,
            ReputationFrame = true,
            TokenFrame = true,
            PetPaperDollFrame = true,
            SkillFrame = true,
            PVPFrame = true,
            HonorFrame = true,
            StatisticsFrame = true,
            CharacterStatisticsFrame = true,
        }
        -- Keep CharacterFrame subframes shown at alpha 0 so ToggleCharacter("PaperDollFrame") closes on 2nd press of 'C'.
        for name in pairs(exclusiveCharMap) do
            local sub = _G[name]
            if sub and IsSafeHostObj(sub) and sub.IsShown and sub:IsShown() then
                if alphaHidden[sub] == nil then
                    alphaHidden[sub] = (sub.GetAlpha and sub:GetAlpha()) or 1
                end
                if sub.SetAlpha then
                    pcall(sub.SetAlpha, sub, 0)
                end
                SuppressHostSubtreeMouse(sub, hostFrame, 8, sub, visited)
                if name == "PaperDollFrame" then
                    HideModelIfShown(_G.CharacterModelFrame)
                    HideModelIfShown(_G.CharacterModelScene)
                end
                HideModelIfShown(sub.ModelScene)
                HideModelIfShown(sub.CharacterModelFrame)
                if sub.GetChildren then
                    for _, ch in ipairs({ sub:GetChildren() }) do
                        if ch and IsSafeHostObj(ch) and ch.GetObjectType then
                            local ot = ch:GetObjectType()
                            if ot == "PlayerModel" or ot == "DressUpModel" or ot == "Model" or ot == "ModelScene" or ot == "CinematicModel" then
                                HideModelIfShown(ch)
                            end
                        end
                    end
                end
            end
        end
        for _, name in ipairs({
            "PaperDollSidebarTabs",
            "CharacterFrameInset",
            "CharacterFrameInsetRight",
        }) do
            local sub = _G[name]
            if sub and IsSafeHostObj(sub) then
                SuppressHostSubtreeMouse(sub, hostFrame, 6, sub, visited)
                if sub.IsShown and sub:IsShown() and sub.Hide then
                    hiddenCharSubframes[name] = true
                    pcall(sub.Hide, sub)
                end
            end
        end
        if hostFrame.GetChildren then
            for _, child in ipairs({ hostFrame:GetChildren() }) do
                local cName = child.GetName and child:GetName() or ""
                if IsSafeHostObj(child)
                    and not IsHostChromeOrTabChild(hostFrame, child)
                    and alphaHidden[child] == nil
                    and not exclusiveCharMap[cName]
                then
                    SuppressHostSubtreeMouse(child, hostFrame, 8, child, visited)
                    if child.IsShown and child:IsShown() and child.Hide then
                        AppendUniqueItem(hiddenCharChildren, child)
                        pcall(child.Hide, child)
                    end
                end
            end
        end
    elseif hostFrame == (_G.CommunitiesFrame or _G.GuildFrame) then
        if hostFrame.GetChildren then
            for _, child in ipairs({ hostFrame:GetChildren() }) do
                if IsSafeHostObj(child) and not IsHostChromeOrTabChild(hostFrame, child) then
                    SuppressHostSubtreeMouse(child, hostFrame, 8, child, visited)
                    if child.IsShown and child:IsShown() and child.Hide then
                        AppendUniqueItem(hiddenCommunitiesChildren, child)
                        pcall(child.Hide, child)
                    end
                end
            end
        end
    elseif hostFrame == _G.WorldMapFrame then
        for _, sub in pairs({ hostFrame.ScrollContainer, hostFrame.NavBar, _G.QuestMapFrame }) do
            if IsSafeHostObj(sub) then
                SuppressHostSubtreeMouse(sub, hostFrame, 8, sub, visited)
                if sub.IsShown and sub:IsShown() and sub.Hide then
                    AppendUniqueItem(hiddenWorldMapSubframes, sub)
                    pcall(sub.Hide, sub)
                end
            end
        end
    elseif hostFrame == _G.LFGParentFrame then
        for _, sub in pairs({ _G.LFGListingFrame, _G.LFGBrowseFrame, _G.LFGWhoListFrame }) do
            if sub and IsSafeHostObj(sub) then
                SuppressHostSubtreeMouse(sub, hostFrame, 8, sub, visited)
                if sub.IsShown and sub:IsShown() and sub.Hide then
                    pcall(sub.Hide, sub)
                end
            end
        end
    end
end

function UI:HideEmbeddedHostSubframes(hostFrame)
    HideCharacterHostSubframes(hostFrame, true)
end

function UI:ReleaseAlphaHiddenCharacterSubframesForTabClick()
    if type(embeddedState.alphaHiddenCharFrames) == "table" then
        for sub, origAlpha in pairs(embeddedState.alphaHiddenCharFrames) do
            if sub and IsSafeHostObj(sub, true) and sub.SetAlpha then
                pcall(sub.SetAlpha, sub, origAlpha or 1)
            end
        end
        wipe(embeddedState.alphaHiddenCharFrames)
    end
    RestoreSuppressedHostMouse(_G.CharacterFrame)
    if type(embeddedState.hiddenCharModels) == "table" then
        for i = #embeddedState.hiddenCharModels, 1, -1 do
            local m = embeddedState.hiddenCharModels[i]
            if m and IsSafeHostObj(m) and m.Show then
                pcall(m.Show, m)
            end
            embeddedState.hiddenCharModels[i] = nil
        end
    end
end

function UI:RestoreEmbeddedHostUI(hostFrame)
    if not hostFrame then return end
    HideNativeHostTooltips()
    RestoreSuppressedHostMouse(hostFrame)
    if IsSocialHostFrame(hostFrame) then
        if type(embeddedState.alphaHiddenSocialFrames) == "table" then
            for sub, origAlpha in pairs(embeddedState.alphaHiddenSocialFrames) do
                if sub and IsSafeHostObj(sub, true) and sub.SetAlpha then
                    pcall(sub.SetAlpha, sub, origAlpha or 1)
                end
            end
            wipe(embeddedState.alphaHiddenSocialFrames)
        end
    elseif hostFrame == _G.CharacterFrame then
        local wasAlphaHidden = {}
        if type(embeddedState.alphaHiddenCharFrames) == "table" then
            for sub, origAlpha in pairs(embeddedState.alphaHiddenCharFrames) do
                wasAlphaHidden[sub] = true
                if sub and IsSafeHostObj(sub) and sub.SetAlpha then
                    pcall(sub.SetAlpha, sub, origAlpha or 1)
                end
            end
            wipe(embeddedState.alphaHiddenCharFrames)
        end
        if type(embeddedState.hiddenCharModels) == "table" then
            for i = #embeddedState.hiddenCharModels, 1, -1 do
                local m = embeddedState.hiddenCharModels[i]
                if m and IsSafeHostObj(m) and m.Show then
                    pcall(m.Show, m)
                end
                embeddedState.hiddenCharModels[i] = nil
            end
        end
        local exclusiveCharNames = {
            PaperDollFrame = true,
            ReputationFrame = true,
            TokenFrame = true,
            PetPaperDollFrame = true,
            SkillFrame = true,
            PVPFrame = true,
            HonorFrame = true,
            StatisticsFrame = true,
            CharacterStatisticsFrame = true,
        }
        local hiddenChildSet = {}
        for _, ch in ipairs(hiddenCharChildren) do
            hiddenChildSet[ch] = true
        end
        local otherNativeOpen = false
        for _, checkName in ipairs({ "ReputationFrame", "TokenFrame", "PetPaperDollFrame", "SkillFrame", "PVPFrame", "HonorFrame", "StatisticsFrame", "CharacterStatisticsFrame" }) do
            local f = _G[checkName]
            if f and f.IsShown and f:IsShown() and not hiddenCharSubframes[checkName] then
                otherNativeOpen = true
                break
            end
        end
        if not otherNativeOpen then
            -- Ensure PaperDollFrame and its inset panes always restore cleanly after closing via [X].
            for _, coreName in ipairs({ "PaperDollFrame", "CharacterFrameInset", "CharacterFrameInsetRight", "PaperDollSidebarTabs" }) do
                local sub = _G[coreName]
                if sub and IsSafeHostObj(sub) and sub.Show and (hiddenCharSubframes[coreName] or (coreName ~= "PaperDollSidebarTabs" and sub.IsShown and not sub:IsShown())) then
                    pcall(sub.Show, sub)
                end
            end
        end
        for name in pairs(hiddenCharSubframes) do
            if (not otherNativeOpen) or (not exclusiveCharNames[name]) then
                local sub = _G[name]
                if sub and IsSafeHostObj(sub) and sub.Show then
                    pcall(sub.Show, sub)
                end
            end
        end
        for _, child in ipairs(hiddenCharChildren) do
            if child and IsSafeHostObj(child) and child.Show then
                local cName = child.GetName and child:GetName() or ""
                if (not otherNativeOpen) or (not exclusiveCharNames[cName]) then
                    pcall(child.Show, child)
                end
            end
        end
        for k in pairs(hiddenCharSubframes) do
            hiddenCharSubframes[k] = nil
        end
        for i = #hiddenCharChildren, 1, -1 do
            hiddenCharChildren[i] = nil
        end
    elseif hostFrame == (_G.CommunitiesFrame or _G.GuildFrame) then
        local exclusivePanes = {
            hostFrame.Chat,
            hostFrame.MemberList,
            hostFrame.GuildBenefitsFrame,
            hostFrame.GuildDetailsFrame,
            hostFrame.GuildInfoFrame,
            hostFrame.GuildPreferredPlaySettings,
            hostFrame.PreferredPlaySettings,
            hostFrame.PreferredPlaySettingsFrame,
            hostFrame.ClubFinderGuildAndCommunityFrame,
        }
        local exclusiveSet = {}
        local anyNativeShown = false
        for _, sub in pairs(exclusivePanes) do
            if sub then
                exclusiveSet[sub] = true
                if sub.IsShown and sub:IsShown() then
                    anyNativeShown = true
                end
            end
        end
        if anyNativeShown then
            if hostFrame.CommunitiesList and IsSafeHostObj(hostFrame.CommunitiesList) and hostFrame.CommunitiesList.Show then
                pcall(hostFrame.CommunitiesList.Show, hostFrame.CommunitiesList)
            end
            for _, sub in ipairs(hiddenCommunitiesChildren) do
                if sub and not exclusiveSet[sub] and IsSafeHostObj(sub) and sub.Show then
                    pcall(sub.Show, sub)
                end
            end
        else
            for _, sub in ipairs(hiddenCommunitiesChildren) do
                if sub and IsSafeHostObj(sub) and sub.Show then
                    pcall(sub.Show, sub)
                end
            end
        end
        for i = #hiddenCommunitiesChildren, 1, -1 do
            hiddenCommunitiesChildren[i] = nil
        end
        local restoredAnyExclusive = false
        for _, sub in pairs(exclusivePanes) do
            if sub and sub.IsShown and sub:IsShown() then
                restoredAnyExclusive = true
                break
            end
        end
        if not restoredAnyExclusive then
            if hostFrame.CommunitiesList and IsSafeHostObj(hostFrame.CommunitiesList) and hostFrame.CommunitiesList.Show then
                pcall(hostFrame.CommunitiesList.Show, hostFrame.CommunitiesList)
            end
            for _, fallbackSub in pairs({ hostFrame.Chat, hostFrame.MemberList }) do
                if fallbackSub and IsSafeHostObj(fallbackSub) and fallbackSub.Show then
                    pcall(fallbackSub.Show, fallbackSub)
                end
            end
        end
    elseif hostFrame == _G.WorldMapFrame then
        for _, sub in ipairs(hiddenWorldMapSubframes) do
            if sub and IsSafeHostObj(sub) and sub.Show then
                pcall(sub.Show, sub)
            end
        end
        for i = #hiddenWorldMapSubframes, 1, -1 do
            hiddenWorldMapSubframes[i] = nil
        end
        for _, sub in pairs({ hostFrame.ScrollContainer, hostFrame.NavBar }) do
            if sub and IsSafeHostObj(sub) and sub.Show and sub.IsShown and not sub:IsShown() then
                pcall(sub.Show, sub)
            end
        end
    elseif hostFrame == _G.LFGParentFrame then
        if not (ns.LFGFrameTab and ns.LFGFrameTab.active) then
            local selectedTab = hostFrame.selectedTab or 1
            local subs = { _G.LFGListingFrame, _G.LFGBrowseFrame, _G.LFGWhoListFrame }
            local shownOne = false
            for i = 1, 3 do
                local sub = subs[i]
                if sub and IsSafeHostObj(sub) and sub.SetShown then
                    local shouldShow = (i == selectedTab)
                    pcall(sub.SetShown, sub, shouldShow)
                    if shouldShow then
                        shownOne = true
                    end
                end
            end
            if not shownOne and _G.LFGListingFrame and IsSafeHostObj(_G.LFGListingFrame) and _G.LFGListingFrame.Show then
                pcall(_G.LFGListingFrame.Show, _G.LFGListingFrame)
            end
            if hostFrame.UpdateTabs then
                pcall(hostFrame.UpdateTabs, hostFrame)
            end
        end
    end
end

local function CloseSingleContainer(container, hostFrame)
    if not container then return end
    local tabKey = container._tabKey
    local spec = tabKey and EMBED_HOST_SPECS[tabKey]
    local matches = (not hostFrame) or (container._host == hostFrame) or (container:GetParent() == hostFrame)
    if container._active and matches then
        local activeHost = container._host
        container._embedSeq = (container._embedSeq or 0) + 1
        container._active = false
        container._host = nil
        if container:IsShown() then
            container:Hide()
        end
        local panel = spec and spec.getPanel and spec.getPanel()
        if panel and frame and frame.content then
            panel:SetParent(frame.content)
            panel:ClearAllPoints()
            panel:SetAllPoints(frame.content)
            panel:SetShown(frame:IsShown() and activeTab == tabKey)
            if frame:IsShown() and activeTab == tabKey then
                SyncSubtreeButtonLayers(panel, 12)
            end
        end
        UI:RestoreEmbeddedHostUI(activeHost or hostFrame)
        local inCombatNow = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if not inCombatNow and container:GetParent() ~= UIParent then
            container:SetParent(UIParent)
        end
        if ns.LFGFrameTab and ns.LFGFrameTab.SyncAllEmbeddedTabStates then
            ns.LFGFrameTab:SyncAllEmbeddedTabStates()
        end
    elseif matches and (container:IsShown() or (hostFrame and hostFrame ~= UIParent and container:GetParent() == hostFrame)) then
        container._embedSeq = (container._embedSeq or 0) + 1
        container._active = false
        container._host = nil
        if container:IsShown() then
            container:Hide()
        end
        local panel = spec and spec.getPanel and spec.getPanel()
        if panel and frame and frame.content then
            panel:SetParent(frame.content)
            panel:ClearAllPoints()
            panel:SetAllPoints(frame.content)
            panel:SetShown(frame:IsShown() and activeTab == tabKey)
            if frame:IsShown() and activeTab == tabKey then
                SyncSubtreeButtonLayers(panel, 12)
            end
        end
        if hostFrame then
            UI:RestoreEmbeddedHostUI(hostFrame)
        end
        local inCombatNow = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if not inCombatNow and container:GetParent() ~= UIParent then
            container:SetParent(UIParent)
        end
        if ns.LFGFrameTab and ns.LFGFrameTab.SyncAllEmbeddedTabStates then
            ns.LFGFrameTab:SyncAllEmbeddedTabStates()
        end
        if ns.RequestIdleGcStep then
            ns:RequestIdleGcStep(250, 0.8)
        end
    end
end

function UI:CloseEmbeddedIfHost(hostFrame)
    local singleKey = hostFrame and ResolveSinglePanelEmbedKey(hostFrame)
    if singleKey then
        if embedContainers[singleKey] then
            CloseSingleContainer(embedContainers[singleKey], hostFrame)
        end
        return
    end
    if not hostFrame then
        for _, container in pairs(embedContainers) do
            CloseSingleContainer(container, nil)
        end
    end
    if not frame then return end
    local matchesHost = (not hostFrame) or (embeddedState.host == hostFrame) or (frame:GetParent() == hostFrame)
    if embeddedState.active and matchesHost then
        local activeHost = embeddedState.host
        embeddedState._seq = (embeddedState._seq or 0) + 1
        embeddedState.active = false
        embeddedState.host = nil
        embeddedState.allowedSet = nil
        frame._scLocked = false
        if frame:IsShown() then
            frame:Hide()
        end
        self:RestoreEmbeddedHostUI(activeHost or hostFrame)
        local inCombatNow = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if not inCombatNow and frame:GetParent() ~= UIParent then
            frame:SetParent(UIParent)
        end
        RestoreStandalonePlacement()
        if ns.LFGFrameTab and ns.LFGFrameTab.SyncAllEmbeddedTabStates then
            ns.LFGFrameTab:SyncAllEmbeddedTabStates()
        end
    elseif matchesHost and hostFrame and hostFrame ~= UIParent and frame:GetParent() == hostFrame then
        if frame:IsShown() then
            frame:Hide()
        end
        self:RestoreEmbeddedHostUI(hostFrame)
        local inCombatNow = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if not inCombatNow then
            frame:SetParent(UIParent)
        end
        RestoreStandalonePlacement()
        if ns.LFGFrameTab and ns.LFGFrameTab.SyncAllEmbeddedTabStates then
            ns.LFGFrameTab:SyncAllEmbeddedTabStates()
        end
        if ns.RequestIdleGcStep then
            ns:RequestIdleGcStep(250, 0.8)
        end
    end
end

function UI:OpenEmbedded(hostFrame, allowedTabs, defaultTab, forceKeepOpen)
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat then
        return self:ShowHub(defaultTab or "watchlist")
    end
    if not frame then
        BuildMainFrame()
    end

    local singleKey = ResolveSinglePanelEmbedKey(hostFrame)
    if singleKey then
        local spec = EMBED_HOST_SPECS[singleKey]
        local container = BuildSingleEmbedContainer(singleKey)
        if not forceKeepOpen and container:IsShown() and container._active and container._host == hostFrame then
            container:Hide()
            return false
        end
        container._embedSeq = (container._embedSeq or 0) + 1
        local seq = container._embedSeq
        container._active = true
        container._host = hostFrame

        local hostMax = ScanEmbeddedHostContentMax(hostFrame)
        if container:GetParent() ~= hostFrame then
            container:SetParent(hostFrame)
        end
        local hStrata = hostFrame.GetFrameStrata and hostFrame:GetFrameStrata() or "MEDIUM"
        container:SetFrameStrata(hStrata)

        local baseHostLvl = (hostFrame.GetFrameLevel and hostFrame:GetFrameLevel()) or 1
        local lvlOff = (singleKey == "buffs") and 60 or 30
        local maxOff = (singleKey == "buffs") and 25 or 12
        local maxCap = (singleKey == "buffs") and 4500 or 2500
        local embedLvl = math.min(maxCap, math.max(spec.minEmbedLevel or 520, baseHostLvl + lvlOff, hostMax + maxOff))
        container:SetFrameLevel(embedLvl)
        ElevateEmbeddedHostChrome(hostFrame, embedLvl + 45)

        if not hostFrame[spec.hideHookKey] and hostFrame.HookScript then
            hostFrame[spec.hideHookKey] = true
            hostFrame:HookScript("OnHide", function()
                UI:CloseEmbeddedIfHost(hostFrame)
            end)
        end

        HideCharacterHostSubframes(hostFrame, false)
        local leftPad, rightPad, topPad, bottomPad = spec.pad[1], spec.pad[2], spec.pad[3], spec.pad[4]
        container:ClearAllPoints()
        local hw = (hostFrame.GetWidth and hostFrame:GetWidth()) or 780
        local hh = (hostFrame.GetHeight and hostFrame:GetHeight()) or 520
        container:SetSize(math.max(260, hw - leftPad - rightPad), math.max(240, hh - topPad - bottomPad))
        container:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", leftPad, -topPad)
        container:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", -rightPad, bottomPad)

        if singleKey == "clan" and ns.Social and ns.Social.EnsureFullGuildScan then
            ns.Social:EnsureFullGuildScan()
        end
        ApplySingleEmbedTheme(singleKey)
        local panel = spec.getPanel and spec.getPanel()
        if panel then
            panel:SetParent(container.content)
            panel:ClearAllPoints()
            panel:SetAllPoints(container.content)
            if singleKey == "clan" then
                panel._dirty = nil
            end
            panel:Show()
            UI:SyncFrameSectionLayers(container)
        end

        TriggerTabRefresh(singleKey)
        ApplySingleEmbedTheme(singleKey)
        container:Show()
        UI:SyncFrameSectionLayers(container)
        if spec.updatePanel then
            spec.updatePanel()
        end
        if spec.reflowPanel then
            spec.reflowPanel()
        end
        ElevateEmbeddedHostChrome(hostFrame, embedLvl + 45)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if container and container._embedSeq == seq and container:IsShown() and container._active and container._host == hostFrame then
                    HideCharacterHostSubframes(hostFrame, true)
                    ApplySingleEmbedTheme(singleKey)
                    ElevateEmbeddedHostChrome(hostFrame, embedLvl + 45)
                    UI:SyncFrameSectionLayers(container)
                    if spec.updatePanel then
                        spec.updatePanel()
                    end
                    if spec.reflowPanel then
                        spec.reflowPanel()
                    end
                end
            end)
            C_Timer.After(0.16, function()
                if container and container._embedSeq == seq and container:IsShown() and container._active and container._host == hostFrame then
                    HideCharacterHostSubframes(hostFrame, true)
                    ElevateEmbeddedHostChrome(hostFrame, embedLvl + 45)
                end
            end)
        end
        if ns.LFGFrameTab and ns.LFGFrameTab.SyncAllEmbeddedTabStates then
            ns.LFGFrameTab:SyncAllEmbeddedTabStates()
        end
        return true
    end

    local targetTab = defaultTab or (allowedTabs and allowedTabs[1]) or "watchlist"
    if not forceKeepOpen and frame:IsShown() and embeddedState.active and embeddedState.host == hostFrame and activeTab == targetTab then
        frame:Hide()
        return false
    end

    if embeddedState.active and embeddedState.host and embeddedState.host ~= hostFrame then
        self:CloseEmbeddedIfHost(embeddedState.host)
    end

    local allowedSet = {}
    if type(allowedTabs) == "table" then
        for _, id in ipairs(allowedTabs) do
            allowedSet[id] = true
        end
    end

    embeddedState._seq = (embeddedState._seq or 0) + 1
    local multiSeq = embeddedState._seq
    embeddedState.active = true
    embeddedState.host = hostFrame
    embeddedState.allowedSet = next(allowedSet) and allowedSet or nil
    frame._scLocked = true

    if targetTab and tabButtons[targetTab] then
        activeTab = targetTab
    elseif allowedTabs and allowedTabs[1] and tabButtons[allowedTabs[1]] then
        activeTab = allowedTabs[1]
    end

    if frame.SetResizeBounds then
        frame:SetResizeBounds(260, 240, 1400, 1000)
    elseif frame.SetMinResize then
        frame:SetMinResize(260, 240)
        frame:SetMaxResize(1400, 1000)
    end
    frame:ClearAllPoints()

    local embedLvl = nil
    if hostFrame then
        local hostMax = ScanEmbeddedHostContentMax(hostFrame)
        if frame:GetParent() ~= hostFrame then
            frame:SetParent(hostFrame)
        end
        local hStrata = hostFrame.GetFrameStrata and hostFrame:GetFrameStrata() or "MEDIUM"
        frame:SetFrameStrata(hStrata)

        local baseHostLvl = (hostFrame.GetFrameLevel and hostFrame:GetFrameLevel()) or 1
        if hostFrame == _G.WorldMapFrame then
            embedLvl = math.min(4500, math.max(2600, baseHostLvl + 60, hostMax + 25))
        else
            embedLvl = math.min(2500, math.max(520, baseHostLvl + 30, hostMax + 12))
        end
        frame:SetFrameLevel(embedLvl)
        ElevateEmbeddedHostChrome(hostFrame, embedLvl + 45)

        if not hostFrame._scEmbedHideHooked and hostFrame.HookScript then
            hostFrame._scEmbedHideHooked = true
            hostFrame:HookScript("OnHide", function()
                UI:CloseEmbeddedIfHost(hostFrame)
            end)
        end

        local leftPad, rightPad, topPad, bottomPad = 6, 6, 56, 6
        if hostFrame == _G.WorldMapFrame then
            leftPad, rightPad, topPad, bottomPad = 6, 6, 26, 6
        elseif IsSocialHostFrame(hostFrame) then
            leftPad, rightPad, topPad, bottomPad = 6, 6, 58, 6
        elseif hostFrame == _G.CommunitiesFrame or hostFrame == _G.GuildFrame then
            leftPad, rightPad, topPad, bottomPad = 4, 4, 21, 4
        elseif hostFrame == _G.CharacterFrame then
            leftPad, rightPad, topPad, bottomPad = 4, 4, 21, 4
        end
        HideCharacterHostSubframes(hostFrame, false)
        local hw = (hostFrame.GetWidth and hostFrame:GetWidth()) or 410
        local hh = (hostFrame.GetHeight and hostFrame:GetHeight()) or 675
        frame:SetSize(math.max(260, hw - leftPad - rightPad), math.max(240, hh - topPad - bottomPad))
        frame:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", leftPad, -topPad)
        frame:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", -rightPad, bottomPad)
    else
        RestoreStandalonePlacement()
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("HIGH")
    end

    local wasShown = frame:IsShown()
    if (activeTab == "social" or activeTab == "clan") and ns.Social and ns.Social.EnsureFullGuildScan then
        ns.Social:EnsureFullGuildScan()
    end
    embeddedState._suppressingHost = true
    TriggerTabRefresh(activeTab)
    frame:Show()
    UI:SyncFrameSectionLayers()
    if wasShown then
        ApplyTheme()
        UI:Refresh(true)
    end
    embeddedState._suppressingHost = nil
    if activeTab == "chat" and chatPanel then
        if UI._pendingChatNav and chatPanel.ApplyNavigation then
            chatPanel:ApplyNavigation(UI._pendingChatNav)
            UI._pendingChatNav = nil
        else
            chatPanel._filter = "all"
            if chatPanel.Refresh then
                chatPanel:Refresh(true)
            end
        end
        UI:SyncFrameSectionLayers()
    end
    MaybePromptThemePicker()
    MaybePromptTabTutorial(activeTab)
    if hostFrame and embedLvl then
        ElevateEmbeddedHostChrome(hostFrame, embedLvl + 45)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if frame and embeddedState._seq == multiSeq and frame:IsShown() and embeddedState.active and embeddedState.host == hostFrame then
                    ApplyTheme()
                    ElevateEmbeddedHostChrome(hostFrame, embedLvl + 45)
                    UI:SyncFrameSectionLayers()
                    ReflowTabStrip()
                    if ReflowFilterBar then ReflowFilterBar() end
                    if ReflowWatchBar then ReflowWatchBar() end
                    if ReflowClanPanel then ReflowClanPanel() end
                    if altsPanel and altsPanel:IsShown() and altsPanel.Refresh then
                        altsPanel:Refresh(false)
                    end
                end
            end)
            C_Timer.After(0.16, function()
                if frame and embeddedState._seq == multiSeq and frame:IsShown() and embeddedState.active and embeddedState.host == hostFrame then
                    HideCharacterHostSubframes(hostFrame, true)
                    ElevateEmbeddedHostChrome(hostFrame, embedLvl + 45)
                end
            end)
        end
    end
    if ns.LFGFrameTab and ns.LFGFrameTab.SyncAllEmbeddedTabStates then
        ns.LFGFrameTab:SyncAllEmbeddedTabStates()
    end
    return true
end

function UI:ShowHub(defaultTab)
    if not frame then
        BuildMainFrame()
    end
    local inCombatNow = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombatNow and ((embeddedState.active and embeddedState.host) or (UIParent and frame:GetParent() ~= UIParent)) then
        ns:Print("%s", L["Unavailable during combat."])
        return false
    end
    local wasEmbedded = embeddedState.active == true
    if not inCombatNow then
        if embeddedState.active and embeddedState.host then
            self:CloseEmbeddedIfHost(embeddedState.host)
        end
        if defaultTab and embedContainers[defaultTab] and embedContainers[defaultTab]._active then
            self:CloseEmbeddedIfHost(embedContainers[defaultTab]._host)
        end
    end
    embeddedState._seq = (embeddedState._seq or 0) + 1
    embeddedState.active = false
    embeddedState.host = nil
    embeddedState.allowedSet = nil
    if wasEmbedded or not frame:IsShown() or frame:GetParent() ~= UIParent or frame._scLocked then
        RestoreStandalonePlacement()
    else
        frame:SetFrameStrata("HIGH")
        if (frame:GetFrameLevel() or 0) < 600 then
            frame:SetFrameLevel(600)
        end
    end
    if defaultTab and tabButtons[defaultTab] and IsTabAllowed(defaultTab) then
        activeTab = defaultTab
    elseif not IsTabAllowed(activeTab) then
        activeTab = PickFirstAllowedTab() or activeTab
    end
    local wasShown = frame:IsShown()
    if (activeTab == "social" or activeTab == "clan") and ns.Social and ns.Social.EnsureFullGuildScan then
        ns.Social:EnsureFullGuildScan()
    end
    TriggerTabRefresh(activeTab)
    frame:Show()
    if frame.Raise then
        frame:Raise()
    end
    if wasShown then
        ApplyTheme()
        UI:Refresh(true)
    else
        UI:SyncFrameSectionLayers()
    end
    if defaultTab == "chat" and activeTab == "chat" and chatPanel then
        if UI._pendingChatNav and chatPanel.ApplyNavigation then
            chatPanel:ApplyNavigation(UI._pendingChatNav)
            UI._pendingChatNav = nil
        elseif chatPanel._filter ~= "all" then
            chatPanel._filter = "all"
            if chatPanel.Refresh then
                chatPanel:Refresh(true)
            end
        end
        UI:SyncFrameSectionLayers()
    end
    UI:EnsureMainFrameDraggable()
    MaybePromptThemePicker()
    MaybePromptTabTutorial(activeTab)
    if ns.LFGFrameTab and ns.LFGFrameTab.SyncAllEmbeddedTabStates then
        ns.LFGFrameTab:SyncAllEmbeddedTabStates()
    end
end

function UI:OpenGroupBrowseView()
    if Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("group") then
        ns:Print("%s", L["This module is disabled in Settings."])
        return
    end
    self:ShowHub("group")
    if groupPanel then
        groupPanel._view = "browse"
        if groupPanel.Refresh then
            groupPanel:Refresh(true)
        end
        UI:SyncFrameSectionLayers()
    end
end

function UI:OpenGroupRunsView()
    if Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("group") then
        ns:Print("%s", L["This module is disabled in Settings."])
        return
    end
    self:ShowHub("group")
    if groupPanel then
        groupPanel._view = "runs"
        if groupPanel.Refresh then
            groupPanel:Refresh(true)
        end
        UI:SyncFrameSectionLayers()
    end
end

function UI:OpenGroupRecentView()
    if Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("group") then
        ns:Print("%s", L["This module is disabled in Settings."])
        return
    end
    self:ShowHub("group")
    if groupPanel then
        groupPanel._view = "recent"
        if groupPanel.Refresh then
            groupPanel:Refresh(true)
        end
        UI:SyncFrameSectionLayers()
    end
end

function UI:Show()
    self:ShowHub()
end

function UI:Hide()
    if frame then
        frame:Hide()
    end
end

function UI:OpenTab(tabId)
    if tabId and Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled(tabId) then
        ns:Print("%s", L["This module is disabled in Settings."])
        return
    end
    if not frame then
        BuildMainFrame()
    end
    local singleSpec = tabId and EMBED_HOST_SPECS[tabId]
    if singleSpec then
        if IsSingleEmbedActive(tabId) then
            if singleSpec.updatePanel then
                singleSpec.updatePanel()
            end
            return
        end
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if not inCombat and ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
            ns.LFGFrameTab:OpenOfficialModule(tabId, true)
            return
        end
    elseif tabId == "chat" or tabId == "watchlist" or tabId == "social" or tabId == "nearby" then
        local inEmbeddedHost = embeddedState.active and IsTabAllowed(tabId) and embeddedState.host and embeddedState.host.IsShown and embeddedState.host:IsShown()
        if not inEmbeddedHost and ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
            local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
            if not inCombat then
                ns.LFGFrameTab:OpenOfficialModule(tabId, true)
                return
            end
        end
    end
    if embeddedState.active and tabId and not IsTabAllowed(tabId) then
        if (tabId == "chat" or tabId == "watchlist" or tabId == "social" or tabId == "nearby") and ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
            local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
            if not inCombat then
                ns.LFGFrameTab:OpenOfficialModule(tabId, true)
                return
            end
        end
        local host = embeddedState.host
        self:CloseEmbeddedIfHost(host)
        RestoreStandalonePlacement()
        frame:SetFrameStrata("HIGH")
        frame:SetFrameLevel(600)
        if frame.Raise then
            frame:Raise()
        end
    elseif not embeddedState.active then
        if not frame:IsShown() or frame:GetParent() ~= UIParent or frame._scLocked then
            RestoreStandalonePlacement()
        else
            frame:SetFrameStrata("HIGH")
            if (frame:GetFrameLevel() or 0) < 600 then
                frame:SetFrameLevel(600)
            end
            if frame.Raise then
                frame:Raise()
            end
        end
    end
    if tabId and tabButtons[tabId] then
        activeTab = tabId
    end
    local wasShown = frame:IsShown()
    if (activeTab == "social" or activeTab == "clan") and ns.Social and ns.Social.EnsureFullGuildScan then
        ns.Social:EnsureFullGuildScan()
    end
    TriggerTabRefresh(activeTab)
    frame:Show()
    if wasShown then
        ApplyTheme()
        UI:Refresh(true)
    else
        UI:SyncFrameSectionLayers()
    end
    if activeTab == "chat" and chatPanel then
        if UI._pendingChatNav and chatPanel.ApplyNavigation then
            chatPanel:ApplyNavigation(UI._pendingChatNav)
            UI._pendingChatNav = nil
        else
            chatPanel._filter = "all"
            if chatPanel.Refresh then
                chatPanel:Refresh(true)
            end
        end
        UI:SyncFrameSectionLayers()
    end
    UI:EnsureMainFrameDraggable()
    MaybePromptThemePicker()
    MaybePromptTabTutorial(activeTab)
    if ns.LFGFrameTab and ns.LFGFrameTab.SyncAllEmbeddedTabStates then
        ns.LFGFrameTab:SyncAllEmbeddedTabStates()
    end
end

function UI:Toggle()
    if not frame then
        self:ShowHub()
        return
    end
    if frame:IsShown() then
        frame:Hide()
    else
        self:ShowHub()
    end
end

for _, ev in ipairs({ "WATCHLIST_UPDATED", "SOCIAL_UPDATED", "NEARBY_UPDATED", "ALTS_UPDATED", "CLAN_UPDATED", "CLAN_DIPLOMACY_UPDATED", "CLAN_HIERARCHY_UPDATED", "CLAN_LFG_ALERT", "SPOTTER_UPDATED", "GROUP_UPDATED", "CHAT_UPDATED", "VERSION_UPDATE_FOUND", "SETTINGS_UPDATED" }) do
    ns:On(ev, function()
        UI:QueueRefresh(false)
    end)
end

ns:On("WATCHLIST_DISAMBIGUATE", function(entryId)
    if entryId and UI:IsMainVisible() then
        UI:OpenWatchlistDisambiguation(entryId)
    end
end)

ns.RegisterEvent(UI, "PLAYER_REGEN_DISABLED", UpdateWhoButtons)
ns.RegisterEvent(UI, "PLAYER_REGEN_ENABLED", function()
    UpdateWhoButtons()
    if frame and not embeddedState.active and UIParent and frame.GetParent and frame:GetParent() ~= UIParent then
        RestoreStandalonePlacement()
        UI:EnsureMainFrameDraggable()
    end
end)
ns.RegisterEvent(UI, "PLAYER_GUILD_UPDATE", function(_, _, unit)
    if not unit or unit == "player" then
        UI:QueueRefresh(false)
    end
end)

local function OnViewportGeometryChanged()
    if not frame or embeddedState.active or frame._scLocked then
        return
    end
    if UIParent and frame:GetParent() ~= UIParent then
        return
    end
    RestoreStandalonePlacement()
    if frame._scReflowResize then
        frame._scReflowResize()
    end
    UI:SyncFrameSectionLayers()
end

if Theme and Theme.RegisterViewportListener then
    Theme:RegisterViewportListener("main", OnViewportGeometryChanged)
end
