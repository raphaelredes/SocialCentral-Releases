local _, ns = ...

local L = ns.L
local Compat = ns.Compat
local Theme = ns.Theme

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"

local function HasAtlas(atlasName)
    return C_Texture and C_Texture.GetAtlasInfo and atlasName and C_Texture.GetAtlasInfo(atlasName) ~= nil
end

local UI = {}
ns.UI = UI

local frame
local searchBox
local addBox
local checkNextBtn
local scrollList
local clanPanel
local groupPanel
local chatPanel
local buffsPanel
local altsPanel
local modalFrame
local eventModalFrame
local clanLfgModalFrame
local clanAlertModalFrame
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
}
local socialFilter = "all"
local socialFolderFilter = "all"
local watchlistGroupFilter = "all"
local clanEventFilter = "all"
local clanRightView = "peers"
local clanLfgDungeonsOnly = false
local clanLfgSourceFilter = "ALL" -- "ALL" | "CLAN" | "ALLY" | "FRIENDS"
local clanLfgQuery = ""
local clanPeerQuery = ""
local clanProfQuery = ""
local searchQuery = ""

local tabButtons = {}
local tabOrder = {}
local clanRightViewButtons = {}
local themeTargets = {}

function UI:GetFrame()
    return frame
end

function UI:IsMainVisible()
    return (frame and frame:IsShown()) and true or false
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
    if not (embeddedState.active and embeddedState.allowedSet) then
        return true
    end
    return embeddedState.allowedSet[tabId] == true
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

local function SaveGeometry()
    if embeddedState.active then
        return
    end
    if not frame or not (ns.db and ns.db.window) then
        return
    end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then
        ns.db.window.point = point
        ns.db.window.relativePoint = relPoint
        ns.db.window.x = math.floor((x or 0) + 0.5)
        ns.db.window.y = math.floor((y or 0) + 0.5)
    end
    ns.db.window.width = math.floor((frame:GetWidth() or 760) + 0.5)
    ns.db.window.height = math.floor((frame:GetHeight() or 500) + 0.5)
end

local function AddHelp(parent, anchorTo, title, whatText, howText, point, relPoint, xOff, yOff)
    if not (Theme and Theme.CreateHelpButton) then
        return nil
    end
    local btn = Theme:CreateHelpButton(parent, title, whatText, howText, 18)
    btn:SetPoint(point or "LEFT", anchorTo, relPoint or "RIGHT", xOff or 6, yOff or 0)
    return btn
end

local function UpdateWhoButtons()
    if not frame or not frame:IsShown() then
        return
    end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    local cd = ns.Watchlist and ns.Watchlist:GetCooldownRemaining() or 0
    local busy = ns.Watchlist and ns.Watchlist:IsBusy()

    if checkNextBtn then
        if inCombat then
            Theme:SetButtonText(checkNextBtn, L["In Combat"])
            checkNextBtn:SetEnabled(false)
        elseif busy or cd > 0 then
            local secs = math.max(1, math.ceil(cd))
            Theme:SetButtonText(checkNextBtn, L["Wait %ds"]:format(secs))
            checkNextBtn:SetEnabled(false)
        else
            Theme:SetButtonText(checkNextBtn, L["Check Next"])
            checkNextBtn:SetEnabled(true)
        end
    end
    if ReflowWatchBar then
        ReflowWatchBar()
    end
end

local function EnsureModal()
    if modalFrame then
        modalFrame:SetHeight(162)
        if modalFrame.input then
            modalFrame.input:ClearAllPoints()
            modalFrame.input:SetPoint("TOPLEFT", modalFrame, "TOPLEFT", 16, -56)
            modalFrame.input:SetPoint("TOPRIGHT", modalFrame, "TOPRIGHT", -16, -56)
        end
        Theme:ApplyBackdrop(modalFrame, "window")
        Theme:StyleButton(modalFrame.topCloseBtn, "default")
        Theme:StyleButton(modalFrame.btnSave, "primary")
        Theme:StyleButton(modalFrame.btnCancel, "default")
        return modalFrame
    end

    local m = CreateFrame("Frame", "SocialCentralModal", frame, "BackdropTemplate")
    m:SetSize(418, 162)
    m:SetPoint("CENTER")
    m:SetFrameStrata("DIALOG")
    m:SetFrameLevel(110)
    if m.SetClipsChildren then m:SetClipsChildren(false) end
    m:EnableMouse(true)
    Theme:MakeMovable(m, { key = "modal_generic" })
    m:Hide()

    m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    m.title:SetPoint("TOPLEFT", 16, -14)
    m.title:SetPoint("TOPRIGHT", -42, -14)
    m.title:SetJustifyH("LEFT")
    m.title:SetWordWrap(true)

    local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
    topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
    topCloseBtn:SetScript("OnClick", function()
        m.input:ClearFocus()
        m:Hide()
    end)
    m.topCloseBtn = topCloseBtn

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
    m.input:SetText(name or "")
    m.btnSave:Hide()
    m.input:SetScript("OnEnterPressed", function()
        m.input:ClearFocus()
        m:Hide()
    end)
    m:Show()
    m.input:SetFocus()
    m.input:HighlightText()
end

function UI:OpenCopyModal(text, customTitle, noteText)
    OpenCopyModal(text, customTitle, noteText)
end


local TAG_LABELS = {
    NONE = L["No Status"],
    LFG = L["LFG (Looking for Group)"],
    MPLUS = L["Mythic+ / Dungeons"],
    RAID = L["Raid Ready"],
    PVP = L["PvP / Arena"],
    LEVELING = L["Leveling / Questing"],
    CRAFTING = L["Crafting / Professions"],
    BUSY = L["Busy"],
}

local CAT_LABELS = {
    DUNGEON = L["Dungeon / M+"],
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
    local avail = (container:GetWidth() or 0)
    if avail <= 20 then
        avail = 320
    end
    local x, y, rowH = 0, startY or 0, 22
    for _, b in ipairs(btnList) do
        if b and b:IsShown() then
            local bw = b:GetWidth() or 60
            local helpExtra = b._pairedHelp and ((b._pairedHelp:GetWidth() or 18) + 4) or 0
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
    local m = EnsureModal()
    Theme:ApplyBackdrop(m, "window")
    m.title:SetText(L["Invite to Guild (Name or Name-Surname):"])
    m.input:SetText("")
    m.btnSave:Show()
    Theme:SetButtonText(m.btnSave, L["Invite"])

    local function Commit()
        local raw = Compat.CleanInput(m.input:GetText() or "")
        if not raw then return end
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if inCombat then
            ns:Print(L["Unavailable during combat."])
            return
        end
        if C_GuildInfo and C_GuildInfo.Invite then
            pcall(C_GuildInfo.Invite, raw)
        elseif _G.GuildInvite then
            pcall(_G.GuildInvite, raw)
        end
        m.input:ClearFocus()
        m:Hide()
    end

    m.btnSave:SetScript("OnClick", Commit)
    m.input:SetScript("OnEnterPressed", Commit)
    m:Show()
    m.input:SetFocus()
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

local function OpenEventModal()
    if not eventModalFrame then
        local m = CreateFrame("Frame", "SocialCentralEventModal", frame, "BackdropTemplate")
        m:SetSize(520, 414)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(110)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
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
        local cats = { "DUNGEON", "RAID", "BOSS", "PVP", "GUILD" }
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
        titleLbl:SetText(L["Event Title (e.g. Mythic +10, Karazhan):"])

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

        local whenInput = Theme:CreateEditBox(m, { width = 180, height = 24, maxLetters = 24 })
        whenInput:SetPoint("TOPLEFT", whenLbl, "BOTTOMLEFT", 0, -4)
        m.whenInput = whenInput

        m._timeBtns = {}
        local prevTB = whenInput
        for _, tm in ipairs({ { label = L["Now"], val = L["Now"], h = 20 }, { label = "20:00", val = "20:00", h = 20 }, { label = "21:00", val = "21:00", h = 21 }, { label = "22:00", val = "22:00", h = 22 } }) do
            local tb = Theme:CreateButton(m, 54, 22, tm.label, "default")
            Theme:AutoFitButton(tb, 46, 12, 86)
            tb:SetPoint("LEFT", prevTB, "RIGHT", 5, 0)
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
        calCb:SetPoint("TOPLEFT", roleLbl, "BOTTOMLEFT", -2, -10)
        local calLbl = calCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        calLbl:SetPoint("LEFT", calCb, "RIGHT", 4, 0)
        calLbl:SetText(L["Also post to WoW Guild Calendar (Officers)"])
        m.calCheck = calCb
        AddHelp(m, calLbl, L["Help: WoW Guild Calendar"], L["Attempts to register a guild signup event in Blizzard's native in-game Calendar if your guild rank allows it."], L["All SocialCentral Clan events sync safely in the addon even without officer calendar permission."])

        local btnSave = Theme:CreateButton(m, 96, 24, L["Save"], "primary")
        Theme:AutoFitButton(btnSave, 90, 20)
        btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnSave = btnSave

        local btnCancel = Theme:CreateButton(m, 96, 24, L["Cancel"], "default")
        Theme:AutoFitButton(btnCancel, 90, 20)
        btnCancel:SetPoint("RIGHT", btnSave, "LEFT", -8, 0)
        m.btnCancel = btnCancel

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
                local ok = ns.Clan:CreateEventCall(
                    m._cat,
                    titleStr,
                    whenStr,
                    m.tankIn:GetText(),
                    m.healIn:GetText(),
                    m.dpsIn:GetText(),
                    m.lvlIn:GetText(),
                    m._myRole
                )
                if ok then
                    if m.calCheck and m.calCheck:GetChecked() then
                        local calHour = m._calHour or tonumber(whenStr:match("^(%d+)%s*:")) or 20
                        local calOk, calErr = ns.Clan:PublishGameCalendarEvent(m._cat, titleStr, whenStr, 0, calHour, 0)
                        if calOk then
                            ns:Print(L["Posted event to both SocialCentral Clan and WoW Guild Calendar."])
                        elseif calErr then
                            ns:Print(calErr)
                        end
                    end
                    titleInput:ClearFocus()
                    whenInput:ClearFocus()
                    m:Hide()
                end
            end
        end
        btnSave:SetScript("OnClick", SubmitEvent)
        whenInput:SetScript("OnEnterPressed", SubmitEvent)

        eventModalFrame = m
    end

    -- Refresh dynamic Quick Presets from live Game Summary (Owned Keystone / Premade / Dungeons)
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

    Theme:ApplyBackdrop(eventModalFrame, "window")
    Theme:StyleButton(eventModalFrame.topCloseBtn, "default")
    Theme:StyleButton(eventModalFrame.btnSave, "primary")
    Theme:StyleButton(eventModalFrame.btnCancel, "default")
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
    eventModalFrame._calHour = 20
    eventModalFrame.titleInput:SetText("")
    eventModalFrame.whenInput:SetText(L["Now"])
    eventModalFrame.tankIn:SetText("")
    eventModalFrame.healIn:SetText("")
    eventModalFrame.dpsIn:SetText("")
    eventModalFrame.lvlIn:SetText("")
    eventModalFrame:Show()
    ReflowEventModal()
    eventModalFrame.titleInput:SetFocus()
end

local function OpenClanLFGModal()
    if not clanLfgModalFrame then
        local m = CreateFrame("Frame", "SocialCentralClanLFGModal", frame, "BackdropTemplate")
        m:SetSize(496, 368)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(110)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
        Theme:MakeMovable(m, { key = "modal_clan_lfg" })
        table.insert(UISpecialFrames, "SocialCentralClanLFGModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -36, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["Clan Group Finder (LFG / LFM)"])

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            if m.actIn then m.actIn:ClearFocus() end
            if m.noteIn then m.noteIn:ClearFocus() end
            if m.keyIn then m.keyIn:ClearFocus() end
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        local modeLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        modeLbl:SetPoint("TOPLEFT", 16, -42)
        modeLbl:SetText(L["Mode:"])
        m._mode = "LFG"
        m._modeBtns = {}
        local prevM = modeLbl
        for _, entry in ipairs({
            { id = "LFG", label = L["LFG (Need Group)"] },
            { id = "LFM", label = L["LFM (Forming Group)"] },
        }) do
            local b = Theme:CreateButton(m, 140, 22, entry.label, "default")
            Theme:AutoFitButton(b, 110, 16, 195)
            b:SetPoint("LEFT", prevM, "RIGHT", 6, 0)
            b:SetScript("OnClick", function()
                m._mode = entry.id
                for _, it in ipairs(m._modeBtns) do
                    Theme:SetButtonActive(it.btn, m._mode == it.id, "default")
                end
            end)
            table.insert(m._modeBtns, { id = entry.id, btn = b })
            prevM = b
        end

        local roleLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        roleLbl:SetPoint("TOPLEFT", 16, -74)
        roleLbl:SetText(L["Role:"])
        m._role = "ANY"
        m._roleBtns = {}
        local prevR = roleLbl
        for _, rId in ipairs({ "TANK", "HEALER", "DPS", "ANY" }) do
            local rTxt = (rId == "ANY") and L["Any"] or (ROLE_LABELS[rId] or rId)
            local b = Theme:CreateButton(m, 64, 22, rTxt, "default")
            Theme:AutoFitButton(b, 54, 14, 96)
            b:SetPoint("LEFT", prevR, "RIGHT", 6, 0)
            b:SetScript("OnClick", function()
                m._role = rId
                for _, it in ipairs(m._roleBtns) do
                    Theme:SetButtonActive(it.btn, m._role == it.id, "default")
                end
            end)
            table.insert(m._roleBtns, { id = rId, btn = b })
            prevR = b
        end

        local quickLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        quickLbl:SetPoint("TOPLEFT", 16, -106)
        quickLbl:SetText(L["Quick Dungeon / Activity:"])

        local quickHolder = CreateFrame("Frame", nil, m)
        quickHolder:SetPoint("TOPLEFT", quickLbl, "BOTTOMLEFT", 0, -4)
        quickHolder:SetPoint("TOPRIGHT", m, "TOPRIGHT", -16, 0)
        quickHolder:SetHeight(48)
        m._quickHolder = quickHolder
        m._quickBtns = {}

        local actLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        actLbl:SetPoint("TOPLEFT", quickHolder, "BOTTOMLEFT", 0, -8)
        actLbl:SetText(L["Dungeon / Activity Name:"])

        local actIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 40 })
        actIn:SetPoint("TOPLEFT", actLbl, "BOTTOMLEFT", 0, -4)
        actIn:SetPoint("RIGHT", m, "RIGHT", -112, 0)
        m.actIn = actIn

        local keyLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        keyLbl:SetPoint("LEFT", actIn, "RIGHT", 8, 0)
        keyLbl:SetText(L["Key +:"])
        local keyIn = Theme:CreateEditBox(m, { width = 42, height = 24, numeric = true, maxLetters = 2 })
        keyIn:SetJustifyH("CENTER")
        keyIn:SetPoint("LEFT", keyLbl, "RIGHT", 4, 0)
        m.keyIn = keyIn

        local noteLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        noteLbl:SetPoint("TOPLEFT", actIn, "BOTTOMLEFT", 0, -8)
        noteLbl:SetText(L["Optional Note (e.g. +8 timed, chill run):"])

        local noteIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 44 })
        noteIn:SetPoint("TOPLEFT", noteLbl, "BOTTOMLEFT", 0, -4)
        noteIn:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        m.noteIn = noteIn

        local btnPost = Theme:CreateButton(m, 118, 24, L["Post in Clan LFG"], "primary")
        Theme:AutoFitButton(btnPost, 108, 16)
        btnPost:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnPost = btnPost

        local btnShareG = Theme:CreateButton(m, 118, 24, L["Post + /g Draft"], "default")
        Theme:AutoFitButton(btnShareG, 104, 16)
        btnShareG:SetPoint("RIGHT", btnPost, "LEFT", -6, 0)
        m.btnShareG = btnShareG

        local btnClear = Theme:CreateButton(m, 82, 24, L["Leave LFG"], "danger")
        Theme:AutoFitButton(btnClear, 74, 14)
        btnClear:SetPoint("BOTTOMLEFT", 16, 14)
        m.btnClear = btnClear

        local btnCancel = Theme:CreateButton(m, 76, 24, L["Cancel"], "default")
        Theme:AutoFitButton(btnCancel, 68, 14)
        btnCancel:SetPoint("RIGHT", btnShareG, "LEFT", -6, 0)
        m.btnCancel = btnCancel

        btnCancel:SetScript("OnClick", function() m:Hide() end)
        actIn:SetScript("OnEscapePressed", function() m:Hide() end)
        noteIn:SetScript("OnEscapePressed", function() m:Hide() end)

        local function Submit(alsoOpenGuildChat)
            if not ns.Clan then return end
            local act = actIn:GetText() or ""
            local kLvl = keyIn:GetText() or "0"
            local nt = noteIn:GetText() or ""
            ns.Clan:PostLFG(m._mode, m._role, act, kLvl, nt)
            if alsoOpenGuildChat then
                ns.Clan:OpenGuildChatLFG(m._mode, m._role, act, kLvl, nt)
            end
            clanRightView = "lfg"
            m:Hide()
            UI:Refresh(true)
        end

        btnPost:SetScript("OnClick", function() Submit(false) end)
        btnShareG:SetScript("OnClick", function() Submit(true) end)
        noteIn:SetScript("OnEnterPressed", function() Submit(false) end)
        btnClear:SetScript("OnClick", function()
            if ns.Clan then ns.Clan:ClearMyLFG() end
            m:Hide()
        end)

        clanLfgModalFrame = m
    end

    for _, b in ipairs(clanLfgModalFrame._quickBtns) do b:Hide() end
    wipe(clanLfgModalFrame._quickBtns)
    if ns.Clan then
        local presets = ns.Clan:GetDungeonQuickPresets()
        for idx = 1, math.min(6, #presets) do
            local pr = presets[idx]
            local b = Theme:CreateButton(clanLfgModalFrame._quickHolder, 86, 20, pr.label, "default")
            Theme:AutoFitButton(b, 58, 12, 165)
            b:SetScript("OnClick", function()
                clanLfgModalFrame.actIn:SetText(pr.activity or pr.label)
                if (pr.keyLvl or 0) > 0 then
                    clanLfgModalFrame.keyIn:SetText(tostring(pr.keyLvl))
                end
                if pr.mode then
                    clanLfgModalFrame._mode = pr.mode
                    for _, it in ipairs(clanLfgModalFrame._modeBtns) do
                        Theme:SetButtonActive(it.btn, clanLfgModalFrame._mode == it.id, "default")
                    end
                end
            end)
            table.insert(clanLfgModalFrame._quickBtns, b)
        end
    end

    local defaultRole = ns.Clan and ns.Clan:GetMySpecAndRole() or "ANY"
    clanLfgModalFrame._role = defaultRole
    Theme:ApplyBackdrop(clanLfgModalFrame, "window")
    Theme:StyleButton(clanLfgModalFrame.topCloseBtn, "default")
    Theme:StyleButton(clanLfgModalFrame.btnPost, "primary")
    Theme:StyleButton(clanLfgModalFrame.btnShareG, "default")
    Theme:StyleButton(clanLfgModalFrame.btnClear, "danger")
    Theme:StyleButton(clanLfgModalFrame.btnCancel, "default")
    for _, it in ipairs(clanLfgModalFrame._modeBtns) do
        Theme:StyleButton(it.btn, "default")
        Theme:SetButtonActive(it.btn, clanLfgModalFrame._mode == it.id, "default")
    end
    for _, it in ipairs(clanLfgModalFrame._roleBtns) do
        Theme:StyleButton(it.btn, "default")
        Theme:SetButtonActive(it.btn, clanLfgModalFrame._role == it.id, "default")
    end

    local sum = ns.Clan and ns.Clan:GetPlayerGameSummary()
    clanLfgModalFrame.actIn:SetText((sum and (sum.keystoneLevel or 0) > 0 and sum.keystoneName) or "")
    clanLfgModalFrame.keyIn:SetText((sum and (sum.keystoneLevel or 0) > 0) and tostring(sum.keystoneLevel) or "")
    clanLfgModalFrame.noteIn:SetText("")
    clanLfgModalFrame:Show()
    local qh = FlowButtonGroup(clanLfgModalFrame._quickHolder, clanLfgModalFrame._quickBtns, 5, 4, 0)
    clanLfgModalFrame._quickHolder:SetHeight(math.max(22, qh))
    clanLfgModalFrame.actIn:SetFocus()
end

local function OpenClanLfgAlertModal()
    if not clanAlertModalFrame then
        local m = CreateFrame("Frame", "SocialCentralClanAlertModal", frame, "BackdropTemplate")
        m:SetSize(468, 272)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(110)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
        Theme:MakeMovable(m, { key = "modal_clan_alert" })
        table.insert(UISpecialFrames, "SocialCentralClanAlertModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -36, -14)
        title:SetJustifyH("LEFT")
        title:SetText(L["Clan Dungeon LFG Notifications"])

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            if m.filterIn then m.filterIn:ClearFocus() end
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        local function MakeCheck(yOff, labelText)
            local cb = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("TOPLEFT", 14, yOff)
            local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            lbl:SetPoint("RIGHT", m, "RIGHT", -16, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetText(labelText)
            return cb
        end

        m.cbEnable = MakeCheck(-46, L["Notify me when a clan member looks for a group"])
        m.cbDngOnly = MakeCheck(-76, L["Only notify for Dungeon / Mythic+ group searches"])
        m.cbSound = MakeCheck(-106, L["Play alert chime when a clan dungeon LFG is detected"])

        local filterLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        filterLbl:SetPoint("TOPLEFT", 16, -140)
        filterLbl:SetPoint("TOPRIGHT", -16, -140)
        filterLbl:SetJustifyH("LEFT")
        filterLbl:SetText(L["Optional dungeon keywords filter (comma-separated, blank = all):"])

        local filterIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 80 })
        filterIn:SetPoint("TOPLEFT", filterLbl, "BOTTOMLEFT", 0, -6)
        filterIn:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        m.filterIn = filterIn

        local btnSave = Theme:CreateButton(m, 96, 24, L["Save"], "primary")
        Theme:AutoFitButton(btnSave, 90, 20)
        btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnSave = btnSave

        local btnCancel = Theme:CreateButton(m, 96, 24, L["Cancel"], "default")
        Theme:AutoFitButton(btnCancel, 90, 20)
        btnCancel:SetPoint("RIGHT", btnSave, "LEFT", -8, 0)
        m.btnCancel = btnCancel

        btnCancel:SetScript("OnClick", function() m:Hide() end)
        filterIn:SetScript("OnEscapePressed", function() m:Hide() end)

        local function Commit()
            local s = ns.db and ns.db.settings
            if s then
                s.clanLfgAlertEnabled = m.cbEnable:GetChecked() and true or false
                s.clanLfgAlertDungeonsOnly = m.cbDngOnly:GetChecked() and true or false
                s.clanLfgAlertSound = m.cbSound:GetChecked() and true or false
                s.clanLfgAlertFilter = (m.filterIn:GetText() or ""):gsub("^%s*(.-)%s*$", "%1")
            end
            m:Hide()
            ns:Emit("CLAN_UPDATED")
        end

        btnSave:SetScript("OnClick", Commit)
        filterIn:SetScript("OnEnterPressed", Commit)

        clanAlertModalFrame = m
    end

    local s = ns.db and ns.db.settings or {}
    Theme:ApplyBackdrop(clanAlertModalFrame, "window")
    Theme:StyleButton(clanAlertModalFrame.topCloseBtn, "default")
    Theme:StyleButton(clanAlertModalFrame.btnSave, "primary")
    Theme:StyleButton(clanAlertModalFrame.btnCancel, "default")
    clanAlertModalFrame.cbEnable:SetChecked(s.clanLfgAlertEnabled == true)
    clanAlertModalFrame.cbDngOnly:SetChecked(s.clanLfgAlertDungeonsOnly ~= false)
    clanAlertModalFrame.cbSound:SetChecked(s.clanLfgAlertSound ~= false)
    clanAlertModalFrame.filterIn:SetText(s.clanLfgAlertFilter or "")
    clanAlertModalFrame:Show()
end

local function OpenClanInfoModal()
    if not clanInfoModalFrame then
        local m = CreateFrame("Frame", "SocialCentralClanInfoModal", frame, "BackdropTemplate")
        m:SetSize(530, 424)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(110)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
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

        local metaLbl = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        metaLbl:SetPoint("TOPLEFT", 16, -40)
        metaLbl:SetPoint("TOPRIGHT", -16, -40)
        metaLbl:SetJustifyH("LEFT")
        metaLbl:SetWordWrap(false)
        m.metaLbl = metaLbl

        local sumLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sumLbl:SetPoint("TOPLEFT", 16, -64)
        sumLbl:SetText(L["Clan Focus / Summary:"])
        local sumIn = Theme:CreateEditBox(m, { height = 26, maxLetters = 160, placeholder = L["e.g. Progression Guild · Heroics & Mythic+ nightly"] })
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
        local btnOff = Theme:CreateButton(m, 146, 22, L["Officers Only"], "default")
        Theme:AutoFitButton(btnOff, 118, 16, 200)
        btnOff:SetPoint("TOPLEFT", 16, -304)
        btnOff:SetScript("OnClick", function()
            if not m._isOfficer then return end
            m._editMode = "OFFICERS"
            Theme:SetButtonActive(btnOff, true, "default")
            Theme:SetButtonActive(m._btnAll, false, "default")
        end)

        local btnAll = Theme:CreateButton(m, 164, 22, L["All Guild Members"], "default")
        Theme:AutoFitButton(btnAll, 130, 16, 210)
        btnAll:SetPoint("LEFT", btnOff, "RIGHT", 8, 0)
        btnAll:SetScript("OnClick", function()
            if not m._isOfficer then return end
            m._editMode = "ALL"
            Theme:SetButtonActive(btnOff, false, "default")
            Theme:SetButtonActive(btnAll, true, "default")
        end)
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

        clanInfoModalFrame = m
    end

    local info = ns.Clan and ns.Clan:GetClanInfo() or {}
    local canEdit, isOfficer = false, false
    if ns.Clan and ns.Clan.CanEditClanManagement then
        canEdit, isOfficer = ns.Clan:CanEditClanManagement()
    end
    clanInfoModalFrame._isOfficer = isOfficer
    clanInfoModalFrame._editMode = (info.editMode == "ALL") and "ALL" or "OFFICERS"

    Theme:ApplyBackdrop(clanInfoModalFrame, "window")
    Theme:StyleButton(clanInfoModalFrame.topCloseBtn, "default")
    Theme:StyleButton(clanInfoModalFrame.btnCancel, "default")
    Theme:StyleButton(clanInfoModalFrame.btnSync, "default")
    Theme:StyleButton(clanInfoModalFrame.btnSave, "primary")

    local updater = (info.updatedBy and info.updatedBy ~= "") and info.updatedBy or "-"
    local age = (info.updatedAt and info.updatedAt > 0) and Compat.FormatRelativeTime(info.updatedAt, L) or "-"
    clanInfoModalFrame.metaLbl:SetText(string.format("|cff3fb950[%s]|r  ·  %s: %s (%s)", L["Guild-Isolated Scope"], L["Updated by"], updater, age))

    clanInfoModalFrame.sumIn:SetText(info.summary or "")
    clanInfoModalFrame.schIn:SetText(info.schedule or "")
    clanInfoModalFrame.rulIn:SetText(info.rules or "")
    clanInfoModalFrame.conIn:SetText(info.contacts or "")

    for _, box in ipairs({ clanInfoModalFrame.sumIn, clanInfoModalFrame.schIn, clanInfoModalFrame.rulIn, clanInfoModalFrame.conIn }) do
        box:SetEnabled(canEdit)
        box:UpdatePlaceholder()
    end

    Theme:SetButtonActive(clanInfoModalFrame._btnOff, clanInfoModalFrame._editMode == "OFFICERS", "default")
    Theme:SetButtonActive(clanInfoModalFrame._btnAll, clanInfoModalFrame._editMode == "ALL", "default")
    clanInfoModalFrame._btnOff:SetEnabled(isOfficer)
    clanInfoModalFrame._btnAll:SetEnabled(isOfficer)
    clanInfoModalFrame.btnSave:SetEnabled(canEdit)
    clanInfoModalFrame:Show()
end

local function OpenDiplomacyModal(prefillGuild, prefillStance, prefillFaction)
    if not diplomacyModalFrame then
        local m = CreateFrame("Frame", "SocialCentralDiplomacyModal", frame, "BackdropTemplate")
        m:SetSize(486, 296)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(110)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
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

        local tipFs = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tipFs:SetPoint("TOPLEFT", 16, -214)
        tipFs:SetPoint("TOPRIGHT", -16, -214)
        tipFs:SetJustifyH("LEFT")
        tipFs:SetWordWrap(true)
        tipFs:SetText(L["Players from Enemy or Ally clans appearing on your screen will trigger Spotter alerts & Target Radar."])
        m.tipFs = tipFs

        local btnCancel = Theme:CreateButton(m, 88, 26, L["Cancel"], "default")
        btnCancel:SetPoint("BOTTOMRIGHT", -16, 14)
        btnCancel:SetScript("OnClick", function() m:Hide() end)
        m.btnCancel = btnCancel

        local btnSave = Theme:CreateButton(m, 122, 26, L["Save & Broadcast"], "primary")
        Theme:AutoFitButton(btnSave, 108, 16, 175)
        btnSave:SetPoint("RIGHT", btnCancel, "LEFT", -8, 0)
        local function CommitDip()
            if ns.Clan and ns.Clan:SetGuildStance(m.guildIn:GetText(), m._stance, m.reasonIn:GetText(), m._prefillFaction) then
                m:Hide()
            end
        end
        btnSave:SetScript("OnClick", CommitDip)
        reasonIn:SetScript("OnEnterPressed", CommitDip)
        m.btnSave = btnSave

        diplomacyModalFrame = m
    end

    diplomacyModalFrame._prefillFaction = prefillFaction
    diplomacyModalFrame._stance = (prefillStance == "ALLY" or prefillStance == "NEUTRAL") and prefillStance or "ENEMY"
    Theme:ApplyBackdrop(diplomacyModalFrame, "window")
    Theme:StyleButton(diplomacyModalFrame.topCloseBtn, "default")
    Theme:StyleButton(diplomacyModalFrame.btnCancel, "default")
    Theme:StyleButton(diplomacyModalFrame.btnSave, "primary")
    Theme:StyleButton(diplomacyModalFrame.tgtGuildBtn, "default")
    for _, item in ipairs(diplomacyModalFrame._stanceBtns) do
        Theme:SetButtonActive(item.btn, diplomacyModalFrame._stance == item.id, item.id == "ENEMY" and "danger" or "default")
    end
    diplomacyModalFrame.guildIn:SetText(prefillGuild or "")
    local existingReason = ""
    if prefillGuild and ns.Clan and ns.Clan.LookupGuildStance then
        local _, entry = ns.Clan:LookupGuildStance(prefillGuild)
        if entry and entry.reason then existingReason = entry.reason end
    end
    diplomacyModalFrame.reasonIn:SetText(existingReason)
    diplomacyModalFrame:Show()
    if not prefillGuild or prefillGuild == "" then
        diplomacyModalFrame.guildIn:SetFocus()
    else
        diplomacyModalFrame.reasonIn:SetFocus()
    end
end

function UI:OpenClanInfoModal()
    OpenClanInfoModal()
end

function UI:OpenDiplomacyModal(prefillGuild, prefillStance, prefillFaction)
    OpenDiplomacyModal(prefillGuild, prefillStance, prefillFaction)
end

local allianceModalFrame

local function OpenAllianceManagementModal()
    if not allianceModalFrame then
        local m = CreateFrame("Frame", "SocialCentralAllianceModal", frame, "BackdropTemplate")
        m:SetSize(520, 440)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(110)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
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
            row.nameFs:SetJustifyH("LEFT")
            row.nameFs:SetWordWrap(false)

            row.metaFs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.metaFs:SetPoint("LEFT", row.nameFs, "RIGHT", 6, 0)
            row.metaFs:SetJustifyH("LEFT")
            row.metaFs:SetWordWrap(false)

            row.btnToggle = Theme:CreateButton(row, 86, 20, L["Alliance Access"], "default")
            Theme:AutoFitButton(row.btnToggle, 70, 12, 110)
            row.btnToggle:SetPoint("RIGHT", -6, 0)

            row.btnMgr = Theme:CreateButton(row, 76, 20, L["Manager"], "default")
            Theme:AutoFitButton(row.btnMgr, 60, 12, 90)
            row.btnMgr:SetPoint("RIGHT", row.btnToggle, "LEFT", -6, 0)

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
            local lvlTag = item.level and item.level > 0 and ("Lv " .. item.level) or ""
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
            row.btnToggle:SetScript("OnClick", function()
                if ns.Clan then
                    ns.Clan:SetMemberAllianceAccess(item.lookupKey, not item.authorized, item.isManager)
                    m:RefreshMembers()
                end
            end)

            local isGM = ns.Clan and ns.Clan.IsGuildLeader and ns.Clan:IsGuildLeader()
            row.btnMgr:SetShown(isGM == true)
            if item.isManager then
                Theme:SetButtonText(row.btnMgr, "|cff58a6ff" .. L["Manager"] .. "|r")
                Theme:SetButtonActive(row.btnMgr, true, "default")
            else
                Theme:SetButtonText(row.btnMgr, "|cff8b949e" .. L["Manager"] .. "|r")
                Theme:SetButtonActive(row.btnMgr, false, "default")
            end
            row.btnMgr:SetScript("OnClick", function()
                if ns.Clan and isGM then
                    ns.Clan:SetMemberAllianceAccess(item.lookupKey, item.authorized, not item.isManager)
                    m:RefreshMembers()
                end
            end)
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
end

function UI:OpenAllianceManagementModal()
    OpenAllianceManagementModal()
end

local function OpenRowMenu(row, item)
    if not (MenuUtil and MenuUtil.CreateContextMenu and item) then
        return
    end
    local targetName = item.displayName or item.name
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(targetName or "")
        if item._tab == "watchlist" then
            root:CreateButton(L["Check"], function()
                if ns.Watchlist then
                    ns.Watchlist:CheckEntry(item.id)
                end
            end)
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
            root:CreateButton(L["Pin to Character Friends"], function()
                if ns.Watchlist then
                    ns.Watchlist:PinToFriends(item.id)
                end
            end)
        elseif item._tab == "social" or item._tab == "nearby" then
            local isWatched = ns.Watchlist and ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(item.lookupKey or targetName)
            if isWatched then
                root:CreateButton(L["Remove from Watchlist"], function()
                    if ns.Watchlist then
                        ns.Watchlist:Remove(item.lookupKey or targetName)
                    end
                end)
            else
                root:CreateButton(L["Add to Watchlist"], function()
                    if ns.Watchlist then
                        ns.Watchlist:Add(item.lookupKey or targetName)
                    end
                end)
            end
        end

        if targetName and item._tab ~= "alts" then
            root:CreateButton(L["Edit Social Card"], function()
                if ns.SocialPanels and ns.SocialPanels.OpenSocialMetaModal then
                    ns.SocialPanels:OpenSocialMetaModal(targetName, item.lookupKey or targetName)
                end
            end)
            root:CreateDivider()
            root:CreateButton(L["Open in SocialCentral Chat"], function()
                if ns.Chat and ns.Chat.OpenDirectConversation then
                    ns.Chat:OpenDirectConversation({
                        targetName = targetName,
                        bnetAccountID = item.bnetAccountID,
                        bnetName = item.bnetName,
                        classFile = item.classFile,
                        autoProbe = true,
                    })
                    UI:OpenTab("chat")
                end
            end)
            root:CreateButton(L["WoW Whisper (/w)"], function()
                if item._tab == "social" and item.samePool == false and item.bnetName then
                    Compat.BNetWhisper(item.bnetName, targetName)
                else
                    Compat.Whisper(targetName)
                end
            end)
            if item.sameFaction ~= false then
                root:CreateButton(L["Invite"], function()
                    Compat.Invite(targetName)
                end)
            end
        end

        if targetName and (item._tab == "nearby" or item._tab == "social" or item._tab == "clan" or (item._tab == "watchlist" and item.status == "online")) then
            if not (InCombatLockdown and InCombatLockdown()) and TargetByName then
                root:CreateButton(L["Target Player"], function()
                    local candidates = Compat.GetForeverTargetVariants and Compat.GetForeverTargetVariants(targetName) or { targetName }
                    for _, cand in ipairs(candidates) do
                        if cand and cand ~= "" then
                            pcall(TargetByName, cand, true)
                            local cur = Safe.String(Safe.Call(UnitName, "target"))
                            if cur and cur ~= "" then break end
                        end
                    end
                end)
            end
        end

        if targetName and not item.isSelf and ns.Spotter and ns.Spotter.TrackPlayer then
            if item._tab == "watchlist" or item._tab == "social" or item._tab == "nearby" or item._tab == "clan" then
                root:CreateButton(L["Track on Radar"], function()
                    local stanceHint = (item._tab == "watchlist" or item.isWatchlist) and "WATCHLIST"
                        or ((item.sources and (item.sources.friend or item.sources.bnet)) or item.isFriend) and "FRIEND"
                        or (item.isAllied and "ALLY")
                        or (item.isClan and "SAME")
                        or nil
                    ns.Spotter:TrackPlayer(targetName, item.guild, item.classFile, item.level, item.guid, stanceHint)
                end)
            end
        end

        root:CreateButton(L["Copy Name"], function()
            OpenCopyModal(targetName)
        end)

        if item._tab == "watchlist" then
            root:CreateDivider()
            root:CreateButton(L["Remove"], function()
                if ns.Watchlist then
                    ns.Watchlist:Remove(item.id)
                end
            end)
        end
    end)
end

local function CreateListRow(parent, _, rowHeight)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(rowHeight)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(8, 8)
    row.dot:SetPoint("LEFT", 10, 6)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.nameText:SetPoint("TOPLEFT", 26, -5)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.subText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.subText:SetPoint("BOTTOMLEFT", 26, 5)
    row.subText:SetJustifyH("LEFT")
    row.subText:SetWordWrap(false)

    row.btnRemove = Theme:CreateButton(row, 24, 22, "X", "danger")
    row.btnRemove:SetPoint("RIGHT", -8, 0)

    row.btnInvite = Theme:CreateButton(row, 78, 22, L["Invite"], "default")
    Theme:AutoFitButton(row.btnInvite, 66, 18)
    row.btnWhisper = Theme:CreateButton(row, 84, 22, L["Whisper"], "default")
    Theme:AutoFitButton(row.btnWhisper, 72, 18)
    row.btnAction = Theme:CreateButton(row, 86, 22, L["Check"], "primary")
    Theme:AutoFitButton(row.btnAction, 70, 18)

    row.btnRemove:SetScript("OnClick", function()
        if not row._item then return end
        if row._item._tab ~= "alts" and ns.Watchlist then
            ns.Watchlist:Remove(row._item.id)
        end
    end)

    row.btnWhisper:SetScript("OnClick", function()
        local item = row._item
        if not item then return end
        if ns.Chat and ns.Chat.OpenDirectConversation then
            ns.Chat:OpenDirectConversation({
                targetName = item.displayName,
                bnetAccountID = item.bnetAccountID,
                bnetName = item.bnetName,
                classFile = item.classFile,
                autoProbe = true,
            })
            UI:OpenTab("chat")
        elseif item._tab == "social" and item.samePool == false and item.bnetName then
            Compat.BNetWhisper(item.bnetName, item.displayName)
        else
            Compat.Whisper(item.displayName)
        end
    end)

    row.btnInvite:SetScript("OnClick", function()
        local item = row._item
        if item and item.displayName then
            Compat.Invite(item.displayName)
        end
    end)

    row.btnAction:SetScript("OnClick", function()
        local item = row._item
        if not item then return end
        if item._tab == "watchlist" and ns.Watchlist then
            ns.Watchlist:CheckEntry(item.id)
        elseif (item._tab == "social" or item._tab == "nearby") and ns.Watchlist then
            ns.Watchlist:Add(item.lookupKey or item.displayName)
        end
    end)

    row:SetScript("OnClick", function(self, mouseButton)
        if not self._item then return end
        if self._item._tab == "watchlist" and mouseButton == "LeftButton" and ns.Watchlist and ns.Watchlist.AutoCheckNextFromHardwareClick then
            ns.Watchlist:AutoCheckNextFromHardwareClick(self._item.id)
        end
        if mouseButton == "RightButton" or mouseButton == "LeftButton" then
            OpenRowMenu(self, self._item)
        end
    end)

    row:SetScript("OnEnter", function(self)
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(self, "surface", p)
        if self._item then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            local item = self._item
            GameTooltip:AddLine(item.displayName or item.name or "", 1, 1, 1)
            if item.area and item.area ~= "" then
                GameTooltip:AddLine(item.area, 0.78, 0.84, 0.92)
            end
            if item.guild and item.guild ~= "" then
                GameTooltip:AddLine("<" .. item.guild .. ">", 0.35, 0.88, 0.50)
            end
            if item.note and item.note ~= "" then
                GameTooltip:AddLine(item.note, 0.95, 0.85, 0.45, true)
            end
            if item._tab == "alts" then
                if item.key == Compat.CharacterKey() then
                    GameTooltip:AddLine(L["Current Character"] .. " — " .. L["Active on this WoW Forever account."], 0.39, 0.89, 0.60, true)
                else
                    GameTooltip:AddLine(L["Alt"] .. " — " .. L["Saved character on this WoW Forever account."], 0.62, 0.66, 0.71, true)
                end
            end
            if item.truncatedWarning then
                GameTooltip:AddLine(L["50+ matches found for '%s'; add surname for accuracy."]:format(item.displayName or item.firstName or ""), 1, 0.45, 0.25, true)
            end
            GameTooltip:Show()
        end
    end)

    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(self, (self._dataIdx and self._dataIdx % 2 == 1) and "row" or "rowAlt", p)
    end)

    function row:RefreshTheme()
        Theme:StyleButton(self.btnRemove, "danger")
        Theme:StyleButton(self.btnInvite, "default")
        Theme:StyleButton(self.btnWhisper, "default")
        Theme:StyleButton(self.btnAction, self._actionVariant or "primary")
    end

    return row
end

local function FormatWatchlistSubline(item)
    local parts = {}
    if item.status == "online" then
        table.insert(parts, L["Online"])
    elseif item.status == "offline" then
        table.insert(parts, L["Offline"])
    else
        table.insert(parts, L["Unchecked"])
    end

    if item.area and item.area ~= "" then
        table.insert(parts, item.area)
    end
    if item.guild and item.guild ~= "" then
        table.insert(parts, "<" .. item.guild .. ">")
    end
    if item.note and item.note ~= "" then
        table.insert(parts, item.note)
    end
    local stamp = item.lastSeen or item.lastChecked
    if stamp then
        table.insert(parts, Compat.FormatRelativeTime(stamp, L))
    end
    return table.concat(parts, "  ·  ")
end

local function FormatSocialSubline(item)
    local parts = {}
    local tags = {}
    if item.sources then
        if item.sources.guild then table.insert(tags, L["Guild"]) end
        if item.sources.friend then table.insert(tags, L["Friends"]) end
        if item.sources.bnet then table.insert(tags, L["Battle.net"]) end
    end
    if #tags > 0 then
        table.insert(parts, "[" .. table.concat(tags, "/") .. "]")
    end
    local meta = ns.Store and ns.Store:GetSocialMeta(item.lookupKey or item.displayName)
    if meta and meta.folder and meta.folder ~= "" then
        table.insert(parts, "[" .. meta.folder .. "]")
    end
    if meta and meta.mainName and meta.mainName ~= "" then
        table.insert(parts, L["Main"] .. ": " .. meta.mainName)
    end
    if item.bnetName then
        table.insert(parts, item.bnetName)
    end
    if item.area and item.area ~= "" then
        table.insert(parts, item.area)
    end
    if item.guild and item.guild ~= "" then
        table.insert(parts, "<" .. item.guild .. ">")
    end
    local noteText = (meta and meta.note and meta.note ~= "") and meta.note or item.note
    if noteText and noteText ~= "" then
        table.insert(parts, noteText)
    end
    return table.concat(parts, "  ·  ")
end

local function UpdateListRow(row, item, idx, palette)
    row._item = item
    row._dataIdx = idx
    row.subText:SetTextColor(palette.textMuted[1], palette.textMuted[2], palette.textMuted[3])

    local tab = item._tab
    local hex = item.classFile and Compat.ClassHex(item.classFile) or ((palette.key == "blizzard" and item.status ~= "offline") and "|cffffd100" or Compat.ClassHex(nil))
    local levelStr = item.level and item.level > 0 and (" |cff9da7b5[" .. L["Level %d"]:format(item.level) .. "]|r") or ""

    row.btnRemove:Hide()
    row.btnInvite:Hide()
    row.btnWhisper:Hide()
    row.btnAction:Hide()

    if row.SetClipsChildren then
        row:SetClipsChildren(true)
    end
    local rowW = row:GetWidth() or (frame and frame:GetWidth()) or 760
    local compactRow = rowW > 0 and rowW < 520
    local btnPad = compactRow and 10 or 18
    local btnGap = compactRow and -3 or -6
    local minInvW = compactRow and 50 or 66
    local minWhispW = compactRow and 54 or 72
    local minActW = compactRow and 50 or 68
    local minWatchAddW = compactRow and 68 or 86
    local maxRowBtnW = compactRow and 84 or 150

    local leftMostAnchor
    local scBadge = (item.lookupKey and ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(item.lookupKey)) and " |cff3fb950[SC]|r" or ""
    if tab == "watchlist" then
        Theme:ApplyStatusColor(row.dot, item.status or "unknown")
        local star = item.favorite and "|cffffd24d* |r" or ""
        local grp = (type(item.group) == "string" and item.group ~= "") and (" |cff8ab4f8[" .. item.group .. "]|r") or ""
        local warn = item.truncatedWarning and " |cffff9b3d[!50+]|r" or ""
        row.nameText:SetText(star .. hex .. (item.displayName or "") .. "|r" .. levelStr .. grp .. scBadge .. warn)
        row.subText:SetText(FormatWatchlistSubline(item))

        row.btnRemove:Hide()
        row.btnAction:Hide()
        if item.status == "online" then
            Theme:AutoFitButton(row.btnInvite, minInvW, btnPad, maxRowBtnW)
            Theme:AutoFitButton(row.btnWhisper, minWhispW, btnPad, maxRowBtnW)
            row.btnInvite:Show()
            row.btnInvite:ClearAllPoints()
            row.btnInvite:SetPoint("RIGHT", compactRow and -5 or -8, 0)
            row.btnWhisper:Show()
            row.btnWhisper:ClearAllPoints()
            row.btnWhisper:SetPoint("RIGHT", row.btnInvite, "LEFT", btnGap, 0)
            leftMostAnchor = row.btnWhisper
        else
            row.btnInvite:Hide()
            row.btnWhisper:Hide()
            leftMostAnchor = nil
        end

    elseif tab == "social" then
        Theme:ApplyStatusColor(row.dot, "online")
        local flags = ""
        if item.afk then flags = flags .. " |cffffd24d[AFK]|r" end
        if item.dnd then flags = flags .. " |cffff6b6b[DND]|r" end
        row.nameText:SetText(hex .. (item.displayName or "") .. "|r" .. levelStr .. flags .. scBadge)
        row.subText:SetText(FormatSocialSubline(item))

        Theme:AutoFitButton(row.btnWhisper, minWhispW, btnPad, maxRowBtnW)
        row.btnWhisper:Show()
        row.btnWhisper:ClearAllPoints()
        row.btnWhisper:SetPoint("RIGHT", compactRow and -5 or -8, 0)
        row.btnAction:Hide()
        leftMostAnchor = row.btnWhisper

    elseif tab == "nearby" then
        Theme:ApplyStatusColor(row.dot, "nearby")
        local srcTag = item.source and (" |cff6ec1e4[" .. item.source .. "]|r") or ""
        row.nameText:SetText(hex .. (item.displayName or "") .. "|r" .. levelStr .. srcTag .. scBadge)

        local subParts = {}
        if item.guild and item.guild ~= "" then table.insert(subParts, "<" .. item.guild .. ">") end
        if item.area and item.area ~= "" then table.insert(subParts, item.area) end
        table.insert(subParts, L["Recent"] .. ": " .. Compat.FormatRelativeTime(item.lastSeen, L))
        row.subText:SetText(table.concat(subParts, "  ·  "))

        local isWatched = ns.Watchlist and ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(item.lookupKey or item.displayName)
        row.btnAction:Show()
        row.btnAction:ClearAllPoints()
        row.btnAction:SetPoint("RIGHT", compactRow and -5 or -8, 0)
        row._actionVariant = "default"
        Theme:StyleButton(row.btnAction, "default")
        if isWatched then
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
        leftMostAnchor = row.btnAction

    elseif tab == "alts" then
        local isCurrent = (item.key == Compat.CharacterKey())
        Theme:ApplyStatusColor(row.dot, isCurrent and "online" or "offline")
        local shownName = item.fullName or item.name or ""
        local roleBadge = isCurrent and (" |cff63e29a[" .. L["Current Character"] .. "]|r") or (" |cff9da7b5[" .. L["Alt"] .. "]|r")
        local factionTag = item.faction and (" |cff9da7b5[" .. item.faction .. "]|r") or ""
        row.nameText:SetText(hex .. shownName .. "|r" .. levelStr .. roleBadge .. factionTag)

        local parts = {}
        if item.zone and item.zone ~= "" then table.insert(parts, item.zone) end
        if item.guild and item.guild ~= "" then table.insert(parts, "<" .. item.guild .. ">") end
        table.insert(parts, Compat.FormatMoney(item.money))
        if item.itemLevel and item.itemLevel > 0 then
            table.insert(parts, "iLvl " .. item.itemLevel)
        end
        if item.rested and item.rested > 0 then
            table.insert(parts, L["Rested"] .. ": " .. tostring(math.floor(item.rested)) .. " XP")
        end
        table.insert(parts, Compat.FormatRelativeTime(item.lastActive, L))
        row.subText:SetText(table.concat(parts, "  ·  "))

        row.btnAction:Hide()
        row.btnRemove:Hide()
        leftMostAnchor = nil
    end

    row.nameText:ClearAllPoints()
    row.nameText:SetPoint("TOPLEFT", 26, -5)
    row.subText:ClearAllPoints()
    row.subText:SetPoint("BOTTOMLEFT", 26, 5)
    if leftMostAnchor then
        row.nameText:SetPoint("RIGHT", leftMostAnchor, "LEFT", -8, 0)
        row.subText:SetPoint("RIGHT", leftMostAnchor, "LEFT", -8, 0)
    else
        row.nameText:SetPoint("RIGHT", row, "RIGHT", -12, 0)
        row.subText:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    end
end

local function BuildFilteredRows()
    local out = {}
    if activeTab == "watchlist" and ns.Watchlist then
        local sortBy = ns.db and ns.db.settings and ns.db.settings.sortBy or "status"
        for _, entry in ipairs(ns.Watchlist:GetEntries(watchlistGroupFilter, sortBy)) do
            if SafeTextMatches(searchQuery, entry.displayName, entry.area, entry.guild, entry.note, entry.group) then
                local copy = {}
                for k, v in pairs(entry) do copy[k] = v end
                copy._tab = "watchlist"
                table.insert(out, copy)
            end
        end
    elseif activeTab == "social" and ns.Social then
        for _, item in ipairs(ns.Social:GetList(socialFilter)) do
            local meta = ns.Store and ns.Store:GetSocialMeta(item.lookupKey or item.displayName)
            local folderMatch = (socialFolderFilter == "all") or (meta and meta.folder == socialFolderFilter)
            if folderMatch and SafeTextMatches(
                searchQuery,
                item.displayName,
                item.area,
                item.guild,
                item.note,
                item.bnetName,
                meta and meta.folder,
                meta and meta.mainName,
                meta and meta.note
            ) then
                local copy = {}
                for k, v in pairs(item) do copy[k] = v end
                copy._tab = "social"
                table.insert(out, copy)
            end
        end
    elseif activeTab == "nearby" and ns.Nearby then
        for _, item in ipairs(ns.Nearby:GetList()) do
            if SafeTextMatches(searchQuery, item.displayName, item.guild, item.area, item.source) then
                local copy = {}
                for k, v in pairs(item) do copy[k] = v end
                copy._tab = "nearby"
                table.insert(out, copy)
            end
        end
    elseif activeTab == "alts" and ns.Store then
        for _, alt in ipairs(ns.Store:GetAltsList()) do
            if SafeTextMatches(searchQuery, alt.fullName, alt.surname, alt.name, alt.zone, alt.guild, alt.faction) then
                local copy = {}
                for k, v in pairs(alt) do copy[k] = v end
                copy._tab = "alts"
                copy.displayName = alt.fullName or alt.name
                table.insert(out, copy)
            end
        end
    end
    return out
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
            local hasOther = false
            for _, s in ipairs(sum.signups) do
                if s.name and not Compat.IsMe(s.name) then
                    hasOther = true
                    break
                end
            end
            if hasOther then
                root:CreateDivider()
                root:CreateTitle(L["Invite Applicant"])
                for _, s in ipairs(sum.signups) do
                    if s.name and not Compat.IsMe(s.name) then
                        local target = s.name
                        root:CreateButton(L["Invite %s (%s)"]:format(target, ROLE_LABELS[s.role] or s.role), function()
                            Compat.Invite(target)
                        end)
                        root:CreateButton(L["Whisper %s"]:format(target), function()
                            Compat.Whisper(target)
                        end)
                    end
                end
            end
        end
        root:CreateDivider()
        root:CreateButton(evt.isOpen == false and L["Reopen Event"] or L["Close Event"], function()
            ns.Clan:ToggleEventOpen(evt.id)
        end)
        root:CreateButton(L["Reannounce Event"], function()
            ns.Clan:ReannounceEvent(evt.id)
        end)
        root:CreateButton(L["Copy Name"], function()
            OpenCopyModal(evt.title or "")
        end)
        root:CreateButton(L["Cancel / Remove Event"], function()
            ns.Clan:RemoveEvent(evt.id)
        end)
    end)
end

local function CreateEventRow(parent, _, rowHeight)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(rowHeight)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.titleText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.titleText:SetPoint("TOPLEFT", 8, -7)
    row.titleText:SetJustifyH("LEFT")
    row.titleText:SetWordWrap(false)

    row.subText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.subText:SetPoint("BOTTOMLEFT", 8, 7)
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
        if row._evt and ns.Clan then ns.Clan:RemoveEvent(row._evt.id) end
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
        if mouseButton == "RightButton" and self._evt then
            OpenEventMenu(self, self._evt)
        end
    end)

    row:SetScript("OnEnter", function(self)
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(self, "surface", p)
        if self._evt and self._evt._isCalendarEvent then
            local ev = self._evt
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(ev.title or "", 1.0, 0.85, 0.25, true)
            GameTooltip:AddLine(string.format("%02d  ·  %02d:%02d", ev.monthDay or 0, ev.hour or 0, ev.minute or 0), 0.78, 0.86, 0.96)
            if ev.invitedBy and ev.invitedBy ~= "" then
                GameTooltip:AddLine(L["Host"] .. ": " .. ev.invitedBy, 0.85, 0.88, 0.94)
            end
            GameTooltip:AddLine(L["Click to open Blizzard Game Calendar"], 0.45, 0.85, 0.55)
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
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Signed Up (%d)"]:format(#sum.signups), 1, 1, 1)
            for _, s in ipairs(sum.signups) do
                local r, g, b = Compat.ClassColor(s.classFile)
                GameTooltip:AddDoubleLine(s.name or "", ROLE_LABELS[s.role] or s.role, r, g, b, 0.78, 0.84, 0.92)
            end
            GameTooltip:Show()
        end
    end)

    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
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

local function UpdateEventRow(row, evt, idx, palette)
    row._evt = evt
    row._dataIdx = idx
    row.subText:SetTextColor(palette.textMuted[1], palette.textMuted[2], palette.textMuted[3])

    if evt._isCalendarEvent then
        row.btnTank:Hide()
        row.btnHeal:Hide()
        row.btnDps:Hide()
        row.btnDel:Hide()
        row.titleText:ClearAllPoints()
        row.titleText:SetPoint("TOPLEFT", 8, -7)
        row.titleText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.subText:ClearAllPoints()
        row.subText:SetPoint("BOTTOMLEFT", 8, 7)
        row.subText:SetPoint("RIGHT", row, "RIGHT", -8, 0)

        local tag = evt.isGuild and ("|cfff2c94c[" .. L["Calendar"] .. "]|r ") or "|cff9da7b5[Event]|r "
        row.titleText:SetText(tag .. (evt.title or ""))
        local dayLabel = (evt.dayDelta == 0) and L["Today"] or ((evt.dayDelta == 1) and L["Tomorrow"] or string.format(L["Day %d"], evt.monthDay or 0))
        local parts = { string.format("%s %02d:%02d", dayLabel, evt.hour or 0, evt.minute or 0) }
        if evt.invitedBy and evt.invitedBy ~= "" then
            table.insert(parts, evt.invitedBy)
        end
        row.subText:SetText(table.concat(parts, "  ·  "))
        row:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "LeftButton" and ToggleCalendar then
                if not ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) then
                    pcall(ToggleCalendar)
                end
            end
        end)
        return
    end

    row.btnTank:Show()
    row.btnHeal:Show()
    row.btnDps:Show()
    row.titleText:ClearAllPoints()
    row.titleText:SetPoint("TOPLEFT", 8, -7)
    row.titleText:SetPoint("RIGHT", row.btnTank, "LEFT", -6, 0)
    row.subText:ClearAllPoints()
    row.subText:SetPoint("BOTTOMLEFT", 8, 7)
    row.subText:SetPoint("RIGHT", row.btnTank, "LEFT", -6, 0)
    row:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" and self._evt then
            OpenEventMenu(self, self._evt)
        end
    end)

    local catLabel = CAT_LABELS[evt.category] or evt.category or ""
    local closedTag = (evt.isOpen == false) and ("|cffff6b6b[" .. L["Closed"] .. "]|r ") or ""
    row.titleText:SetText(closedTag .. "|cff58a6ff[" .. catLabel .. "]|r " .. (evt.title or ""))

    local sum = ns.Clan and ns.Clan:GetSignupSummary(evt) or { TANK = 0, HEALER = 0, DPS = 0 }
    local function SlotStr(prefix, cur, need)
        if need and need > 0 then
            return string.format("%s:%d/%d", prefix, cur or 0, need)
        end
        return string.format("%s:%d", prefix, cur or 0)
    end
    local slots = string.format(
        "%s %s %s",
        SlotStr("T", sum.TANK, evt.needT),
        SlotStr("H", sum.HEALER, evt.needH),
        SlotStr("D", sum.DPS, evt.needD)
    )
    local lvlPart = (evt.minLvl and evt.minLvl > 0) and ("  ·  Lv" .. evt.minLvl .. "+") or ""
    row.subText:SetText(string.format("%s  ·  %s  ·  %s%s", evt.whenText or L["Now"], evt.creator or "", slots, lvlPart))

    local myName = ns.Safe and ns.Safe.String(ns.Safe.Call(UnitName, "player"))
    local myParsed = myName and Compat.ParseCharacterName(myName)
    local mySignup = myParsed and evt.signups and evt.signups[myParsed.lookupKey]
    local myRole = mySignup and mySignup.role or nil
    row._myRole = myRole

    local isCreator = (myParsed and evt.creatorKey and myParsed.lookupKey == evt.creatorKey)
        or (myParsed and evt.creator and (myParsed.displayName == evt.creator or myParsed.firstName:lower() == evt.creator:lower()))
    local canManage = isCreator or (ns.Clan and ns.Clan:CanEditClanManagement())

    if canManage then
        row.btnDel:Show()
        row.btnDps:ClearAllPoints()
        row.btnDps:SetPoint("RIGHT", row.btnDel, "LEFT", -4, 0)
    else
        row.btnDel:Hide()
        row.btnDps:ClearAllPoints()
        row.btnDps:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    end

    Theme:SetButtonActive(row.btnTank, myRole == "TANK", myRole == "TANK" and "primary" or "default")
    Theme:SetButtonActive(row.btnHeal, myRole == "HEALER", myRole == "HEALER" and "primary" or "default")
    Theme:SetButtonActive(row.btnDps, myRole == "DPS", myRole == "DPS" and "primary" or "default")
end

local function CreatePeerRow(parent, _, rowHeight)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(rowHeight)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(7, 7)
    row.dot:SetPoint("LEFT", 8, 6)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.nameText:SetPoint("TOPLEFT", 20, -5)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.subText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.subText:SetPoint("BOTTOMLEFT", 20, 5)
    row.subText:SetJustifyH("LEFT")
    row.subText:SetWordWrap(false)

    row.nameText:SetPoint("RIGHT", -10, 0)
    row.subText:SetPoint("RIGHT", -10, 0)

    row:SetScript("OnClick", function(self, mouseButton)
        if (mouseButton == "RightButton" or mouseButton == "LeftButton") and self._item then
            if self._item._clanView == "diplomacy" then
                if MenuUtil and MenuUtil.CreateContextMenu then
                    local entry = self._item
                    MenuUtil.CreateContextMenu(self, function(_, root)
                        root:CreateTitle(entry.name or "?")
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
                            if ns.Clan then ns.Clan:RemoveGuildDiplomacy(entry.key) end
                        end)
                        root:CreateDivider()
                        root:CreateButton(L["Sync Intel"], function()
                            if ns.Clan then ns.Clan:BroadcastFullIntel() end
                        end)
                    end)
                end
                return
            elseif self._item._clanView ~= "locks" and self._item.displayName then
                local menuItem = {}
                for k, v in pairs(self._item) do menuItem[k] = v end
                menuItem._tab = "social"
                OpenRowMenu(self, menuItem)
            end
        end
    end)

    row:SetScript("OnEnter", function(self)
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(self, "surface", p)
        if self._item then
            local item = self._item
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if item._clanView == "locks" then
                GameTooltip:AddLine(item.title or "", 1.0, 0.85, 0.25, true)
                GameTooltip:AddLine(item.detail or "", 0.80, 0.86, 0.94, true)
                GameTooltip:Show()
                return
            elseif item._clanView == "diplomacy" then
                local stLbl = item.stance == "ENEMY" and L["Enemy Clan"] or (item.stance == "ALLY" and L["Ally Clan"] or L["Neutral"])
                GameTooltip:AddLine("<" .. (item.name or "?") .. ">  [" .. stLbl .. "]", 1.0, 0.85, 0.25, true)
                if item.reason and item.reason ~= "" then
                    GameTooltip:AddLine(item.reason, 0.92, 0.94, 0.96, true)
                end
                GameTooltip:AddLine(string.format("%s: %s (%s)", L["Updated by"], item.addedBy or "?", Compat.FormatRelativeTime(item.updatedAt, L)), 0.65, 0.72, 0.82, true)
                GameTooltip:AddLine(L["Right-click to edit stance or remove."], 0.55, 0.82, 0.62, true)
                GameTooltip:Show()
                return
            end
            GameTooltip:AddLine((item.displayName or "") .. (item.version and ("  (v" .. item.version .. ")") or ""), 1, 1, 1)
            if item._clanView == "lfg" then
                local modeStr = (item.mode or "LFG") .. ((item.role and item.role ~= "ANY") and (" · " .. (ROLE_LABELS[item.role] or item.role)) or "")
                GameTooltip:AddLine(modeStr .. " — " .. (item.activity or ""), 0.35, 0.88, 0.55, true)
                if item.note and item.note ~= "" then
                    GameTooltip:AddLine(item.note, 0.90, 0.92, 0.96, true)
                end
            elseif item._clanView == "prof" then
                local pMap = (ns.SocialPanels and ns.SocialPanels.PROF_LABELS) or {}
                local pNames = {}
                if item.prof1 and item.prof1 ~= "NONE" then table.insert(pNames, pMap[item.prof1] or item.prof1) end
                if item.prof2 and item.prof2 ~= "NONE" then table.insert(pNames, pMap[item.prof2] or item.prof2) end
                GameTooltip:AddLine(table.concat(pNames, " / "), 0.35, 0.88, 0.50)
                if item.craftNote and item.craftNote ~= "" then
                    GameTooltip:AddLine(item.craftNote, 0.95, 0.85, 0.45, true)
                end
            elseif item._clanView == "gchat" then
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
            end
            GameTooltip:Show()
        end
    end)

    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(self, (self._dataIdx and self._dataIdx % 2 == 1) and "row" or "rowAlt", p)
    end)

    function row:RefreshTheme()
    end

    return row
end

local function UpdatePeerRow(row, item, idx, palette)
    row._item = item
    row._dataIdx = idx
    row.subText:SetTextColor(palette.textMuted[1], palette.textMuted[2], palette.textMuted[3])
    row.nameText:ClearAllPoints()
    row.nameText:SetPoint("TOPLEFT", 20, -5)
    row.nameText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.subText:ClearAllPoints()
    row.subText:SetPoint("BOTTOMLEFT", 20, 5)
    row.subText:SetPoint("RIGHT", row, "RIGHT", -10, 0)

    if item._clanView == "locks" then
        Theme:ApplyStatusColor(row.dot, item.statusColor or "unknown")
        row.nameText:SetText(item.title or "")
        row.subText:SetText(item.detail or "")
        return
    elseif item._clanView == "diplomacy" then
        local tagHex, stanceLbl
        if item.stance == "ENEMY" then
            row.dot:SetColorTexture(0.96, 0.28, 0.28, 1)
            tagHex = "|cfff54747"
            stanceLbl = L["ENEMY"]
        elseif item.stance == "ALLY" then
            row.dot:SetColorTexture(0.25, 0.85, 0.45, 1)
            tagHex = "|cff40d973"
            stanceLbl = L["ALLY"]
        else
            row.dot:SetColorTexture(0.66, 0.70, 0.78, 1)
            tagHex = "|cffb0b8c4"
            stanceLbl = L["NEUTRAL"]
        end
        local facStr = (item.faction and item.faction ~= "") and ("  |cff8b949e(" .. item.faction .. ")|r") or ""
        row.nameText:SetText(string.format("%s[%s]|r  |cffffffff<%s>|r%s", tagHex, stanceLbl, item.name or "?", facStr))
        local reasonText = (item.reason and item.reason ~= "") and item.reason or L["No note"]
        row.subText:SetText(string.format("%s  ·  %s: %s · %s", reasonText, L["Updated by"], item.addedBy or "?", Compat.FormatRelativeTime(item.updatedAt, L)))
        return
    end

    local isOnline = (item._clanView == "gchat") or (item.online == true)
    Theme:ApplyStatusColor(row.dot, item._clanView == "gchat" and "nearby" or (isOnline and "online" or "offline"))

    local hex = item.classFile and Compat.ClassHex(item.classFile) or ((palette.key == "blizzard" and isOnline) and "|cffffd100" or Compat.ClassHex(nil))
    local scTag = (item.hasAddon or (item.lookupKey and ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(item.lookupKey))) and " |cff3fb950[SC]|r" or ""

    if item._clanView == "lfg" then
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
            srcBadge = srcBadge .. " |cffffa633[" .. L["WATCHLIST"] .. "]|r"
        elseif item.isFriend then
            srcBadge = srcBadge .. " |cff59c7ff[" .. L["FRIEND"] .. "]|r"
        end
        row.nameText:SetText(modeCol .. " " .. hex .. (item.displayName or "") .. "|r" .. scTag .. roleTag .. keyTag .. dngBadge .. srcBadge)

        local subParts = {}
        if item.activity and item.activity ~= "" then table.insert(subParts, item.activity) end
        if item.ilvl and item.ilvl > 0 then table.insert(subParts, "iLvl " .. item.ilvl) end
        if item.note and item.note ~= "" then table.insert(subParts, item.note) end
        if item.hasFriendOrWatchlistSignup and item.friendOrWatchlistNames and item.friendOrWatchlistNames ~= "" then
            table.insert(subParts, L["In group"] .. ": " .. item.friendOrWatchlistNames)
        end
        table.insert(subParts, Compat.FormatRelativeTime(item.updatedAt, L))
        row.subText:SetText(table.concat(subParts, "  ·  "))
        return
    elseif item._clanView == "prof" then
        local pMap = (ns.SocialPanels and ns.SocialPanels.PROF_LABELS) or {}
        local pList = {}
        if item.prof1 and item.prof1 ~= "NONE" then table.insert(pList, pMap[item.prof1] or item.prof1) end
        if item.prof2 and item.prof2 ~= "NONE" then table.insert(pList, pMap[item.prof2] or item.prof2) end
        row.nameText:SetText(hex .. (item.displayName or "") .. "|r" .. scTag .. "  |cff3fb950[" .. table.concat(pList, " / ") .. "]|r")
        local subParts = {}
        if item.craftNote and item.craftNote ~= "" then table.insert(subParts, item.craftNote) end
        table.insert(subParts, Compat.FormatRelativeTime(item.updatedAt, L))
        row.subText:SetText(table.concat(subParts, "  ·  "))
        return
    elseif item._clanView == "gchat" then
        row.nameText:SetText(hex .. (item.displayName or "") .. "|r  |cff58a6ff[/g LFM]|r")
        row.subText:SetText((item.text or "") .. "  ·  " .. Compat.FormatRelativeTime(item.ts, L))
        return
    end

    local lvlStr = (item.level and item.level > 0) and (" [" .. item.level .. "]") or ""
    local ver = item.version and (" |cff3fb950[SC v" .. item.version .. "]|r") or (item.hasAddon and " |cff3fb950[SC]|r" or "")
    local rankStr = (item.rankName and item.rankName ~= "") and (" |cff9da7b5<" .. item.rankName .. ">|r") or ""
    row.nameText:SetText(hex .. (item.displayName or "") .. "|r" .. lvlStr .. rankStr .. ver)

    local sub = {}
    if item.tag and item.tag ~= "NONE" then
        table.insert(sub, "[" .. (TAG_LABELS[item.tag] or item.tag) .. "]")
    end
    if item.note and item.note ~= "" then
        table.insert(sub, item.note)
    end
    if item.area and item.area ~= "" then
        table.insert(sub, item.area)
    end
    if #sub == 0 then
        table.insert(sub, isOnline and L["Online"] or Compat.FormatRelativeTime(item.updatedAt, L))
    end
    row.subText:SetText(table.concat(sub, "  ·  "))
end

local function UpdateClanPanel()
    if not clanPanel then
        return
    end
    local prefView = ns.Clan and ns.Clan.ConsumePreferredRightView and ns.Clan:ConsumePreferredRightView()
    if prefView and (prefView == "peers" or prefView == "events" or prefView == "diplomacy" or prefView == "prof" or prefView == "locks" or prefView == "lfg") then
        clanRightView = prefView
    end

    local p = Theme:GetPalette()
    Theme:ApplyBackdrop(clanPanel.sidebar, "inset", p)
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

    if clanPanel.motdEditBtn then
        clanPanel.motdEditBtn:SetShown(inGuild and gameSum.canEditMOTD == true)
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
        Theme:SetButtonActive(b, inGuild and (activeNav == id), "default")
        if b.SetEnabled then
            b:SetEnabled(inGuild)
        end
        Theme:StyleButton(b, "default")
    end
    for _, gBtn in ipairs({
        clanPanel.statusBtn,
        clanPanel.clanInfoBtn,
        clanPanel.syncBtn,
        clanPanel.guildInviteBtn,
        clanPanel.evtFilterBtn,
        clanPanel.newEventBtn,
        clanPanel.dipFilterBtn,
        clanPanel.dipAddBtn,
        clanPanel.profViewBtn,
        clanPanel.profBtn,
        clanPanel.openLfgFinderBtn,
    }) do
        if gBtn and gBtn.SetEnabled then
            local canUse = inGuild
            if gBtn == clanPanel.guildInviteBtn then
                canUse = inGuild and (gameSum.canInviteGuild == true)
            end
            gBtn:SetEnabled(canUse)
            Theme:StyleButton(gBtn, gBtn._scVariant or "default")
        end
    end
    for _, gBox in ipairs({ clanPanel.peerSearch, clanPanel.profSearch }) do
        if gBox and gBox.SetEnabled then
            gBox:SetEnabled(inGuild)
            if not inGuild and gBox.ClearFocus then
                gBox:ClearFocus()
            end
            if gBox.SetAlpha then
                gBox:SetAlpha(inGuild and 1.0 or 0.55)
            end
        end
    end

    if clanPanel.peersToolBar then
        clanPanel.peersToolBar:SetShown(clanRightView == "peers" or clanRightView == "lfg")
    end
    if clanPanel.eventsToolBar then
        clanPanel.eventsToolBar:SetShown(clanRightView == "events")
        if clanPanel.evtFilterBtn then
            local evtLabels = {
                all = L["All"],
                open = L["Open Only"],
                need_tank = L["Need T"],
                need_heal = L["Need H"],
                calendar = L["Calendar"],
            }
            Theme:SetButtonText(clanPanel.evtFilterBtn, (evtLabels[clanEventFilter] or L["All"]) .. "  v")
            Theme:SetButtonActive(clanPanel.evtFilterBtn, clanEventFilter ~= "all", "default")
            Theme:AutoFitButton(clanPanel.evtFilterBtn, 86, 14, 150)
        end
    end
    if clanPanel.profToolBar then
        clanPanel.profToolBar:SetShown(clanRightView == "prof" or clanRightView == "locks")
        if clanPanel.profViewBtn then
            local pvLbl = (clanRightView == "locks") and L["Locks"] or L["Professions"]
            Theme:SetButtonText(clanPanel.profViewBtn, pvLbl .. "  v")
            Theme:AutoFitButton(clanPanel.profViewBtn, 96, 14, 155)
        end
    end
    if clanPanel.dipToolBar then
        clanPanel.dipToolBar:SetShown(clanRightView == "diplomacy")
        if clanPanel.dipFilterBtn then
            local fltLbl = clanRightViewFilterDip == "ENEMY" and L["Filter: Enemy"]
                or (clanRightViewFilterDip == "ALLY" and L["Filter: Ally"] or L["Filter: All"])
            Theme:SetButtonText(clanPanel.dipFilterBtn, fltLbl .. "  v")
            Theme:SetButtonActive(clanPanel.dipFilterBtn, clanRightViewFilterDip ~= "all", clanRightViewFilterDip == "ENEMY" and "danger" or "default")
            Theme:AutoFitButton(clanPanel.dipFilterBtn, 90, 14, 145)
        end
    end

    if clanPanel.radarBtn then
        local eCount, aCount, sCount, totalCount = 0, 0, 0, 0
        if ns.Spotter and ns.Spotter.GetCounts then
            eCount, aCount, sCount, totalCount = ns.Spotter:GetCounts()
        end
        if totalCount > 0 then
            Theme:SetButtonText(clanPanel.radarBtn, string.format("%s (%d)", L["Target Radar"], totalCount))
            Theme:SetButtonActive(clanPanel.radarBtn, true, eCount > 0 and "danger" or "primary")
        else
            Theme:SetButtonText(clanPanel.radarBtn, L["Target Radar"])
            Theme:SetButtonActive(clanPanel.radarBtn, false, "default")
        end
        Theme:AutoFitButton(clanPanel.radarBtn, 84, 14, 144)
    end

    local allPeers = ns.Clan and ns.Clan:GetMergedGuildMembers("") or {}
    local peers = (clanPeerQuery ~= "" and ns.Clan) and ns.Clan:GetMergedGuildMembers(clanPeerQuery) or allPeers

    if clanPanel.heroSummaryLbl and clanPanel.heroDetailLbl then
        if inGuild then
            local scUsers, onlineTotal, classCounts = 0, 0, {}
            for _, mbr in ipairs(allPeers) do
                if mbr.hasAddon then scUsers = scUsers + 1 end
                if mbr.online then
                    onlineTotal = onlineTotal + 1
                    if mbr.classFile and mbr.classFile ~= "" then
                        classCounts[mbr.classFile] = (classCounts[mbr.classFile] or 0) + 1
                    end
                end
            end
            local openEvents = ns.Clan and ns.Clan.GetEventsList and #(ns.Clan:GetEventsList("open")) or 0
            local allies = ns.Clan and ns.Clan.GetDiplomacyList and #(ns.Clan:GetDiplomacyList("ALLY")) or 0
            local enemies = ns.Clan and ns.Clan.GetDiplomacyList and #(ns.Clan:GetDiplomacyList("ENEMY")) or 0
            local allyCfg = ns.Clan and ns.Clan.GetAllianceConfig and ns.Clan:GetAllianceConfig() or nil

            local sumParts = {
                ("|cff3fb950%s: %d/%d|r"):format(L["Online"], info.onlineCount or onlineTotal, info.totalCount or #allPeers),
                ("|cff58a6ffSC: %d|r"):format(scUsers),
                ("|cffffd200%s: %d|r"):format(L["Events"], openEvents),
                ("|cff40d973%d %s|r / |cfff54747%d %s|r"):format(allies, L["ALLY"]:lower(), enemies, L["ENEMY"]:lower()),
            }
            if allyCfg and allyCfg.enabled and allyCfg.name and allyCfg.name ~= "" then
                table.insert(sumParts, ("|cff6ec1e4[%s: %s]|r"):format(L["Alliance"], allyCfg.name))
            end
            clanPanel.heroSummaryLbl:SetText(table.concat(sumParts, "  ·  "))

            local cInfo = ns.Clan and ns.Clan.GetClanInfo and ns.Clan:GetClanInfo() or {}
            local detailParts = {}
            if cInfo.summary and cInfo.summary ~= "" then
                table.insert(detailParts, "|cffffd200" .. L["Focus"] .. ":|r " .. cInfo.summary)
            end
            if cInfo.schedule and cInfo.schedule ~= "" then
                table.insert(detailParts, cInfo.schedule)
            end
            if #detailParts == 0 then
                local clsParts = {}
                for cf, cnt in pairs(classCounts) do
                    local locClass = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cf]) or cf
                    table.insert(clsParts, { n = cnt, txt = ("%s%s (%d)|r"):format(Compat.ClassHex(cf), locClass, cnt) })
                end
                table.sort(clsParts, function(a, b) return a.n > b.n end)
                local topCls = {}
                for i = 1, math.min(4, #clsParts) do topCls[#topCls + 1] = clsParts[i].txt end
                if #topCls > 0 then
                    clanPanel.heroDetailLbl:SetText(table.concat(topCls, "  ·  "))
                else
                    clanPanel.heroDetailLbl:SetText("|cff8b949e" .. L["Click 'Guild Info' to configure shared guild focus and schedule."] .. "|r")
                end
            else
                clanPanel.heroDetailLbl:SetText(table.concat(detailParts, "  ·  "))
            end
        else
            clanPanel.heroSummaryLbl:SetText("|cff8b949e" .. L["No guild"] .. "|r")
            clanPanel.heroDetailLbl:SetText("|cff8b949e" .. L["You are not in a guild. Guild features are disabled until you join a guild."] .. "|r")
        end
    end

    local locked = ns.Clan and ns.Clan:IsMessagingLocked()
    local modeTag = syncEnabled and (locked and L["Locked"] or "SCentral1") or L["Local only"]
    clanPanel.syncStatus:SetText(string.format("[%s · %d]", modeTag, #allPeers))
    clanPanel.syncStatus:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])

    if ReflowClanPanel then
        ReflowClanPanel()
    end

    local isEvents = inGuild and (clanRightView == "events")
    clanPanel.eventsScroll.container:SetShown(isEvents)
    clanPanel.peersScroll.container:SetShown(not isEvents)

    if not inGuild then
        clanPanel.peersScroll:SetData({}, L["You are not in a guild. Guild features are disabled until you join a guild."], false)
        return
    end

    if isEvents then
        if clanEventFilter == "calendar" then
            local calRows = {}
            if ns.Clan then
                ns.Clan:RefreshGameCalendar(false)
                for _, ce in ipairs(ns.Clan:GetUpcomingCalendarEvents()) do
                    local copy = {}
                    for k, v in pairs(ce) do copy[k] = v end
                    copy._isCalendarEvent = true
                    table.insert(calRows, copy)
                end
            end
            clanPanel.eventsScroll:SetData(calRows, L["No upcoming guild calendar events found in the next 14 days."], false)
        else
            local events = ns.Clan and ns.Clan:GetEventsList(clanEventFilter) or {}
            clanPanel.eventsScroll:SetData(events, L["No Clan event calls yet. Click '+ Event Call' to create one!"], false)
        end
    elseif clanRightView == "lfg" then
        local lfgList = {}
        for _, item in ipairs(ns.Clan and ns.Clan:GetClanLFGList(clanLfgQuery, clanLfgDungeonsOnly, clanLfgSourceFilter) or {}) do
            local copy = {}
            for k, v in pairs(item) do copy[k] = v end
            copy._clanView = "lfg"
            table.insert(lfgList, copy)
        end
        clanPanel.peersScroll:SetData(lfgList, L["No active Clan LFG posts yet. Click '+ Clan LFG' or 'Share Queue/Key' to post!"], false)
    elseif clanRightView == "prof" then
        local profList = {}
        for _, item in ipairs(ns.Clan and ns.Clan:GetProfessionsList(clanProfQuery) or {}) do
            local copy = {}
            for k, v in pairs(item) do copy[k] = v end
            copy._clanView = "prof"
            table.insert(profList, copy)
        end
        clanPanel.peersScroll:SetData(profList, L["No Clan professions set yet. Click '+ Prof' above to add yours!"], false)
    elseif clanRightView == "locks" then
        local lockRows = {}
        if ns.Clan then
            if gameSum.premadeTitle and gameSum.premadeTitle ~= "" then
                table.insert(lockRows, {
                    _clanView = "locks",
                    statusColor = "online",
                    title = "|cff58a6ff[" .. L["Premade Group"] .. "]|r " .. gameSum.premadeTitle,
                    detail = string.format(L["Applicants: %d"], gameSum.premadeApplicants or 0),
                })
            elseif gameSum.lfgQueued then
                table.insert(lockRows, {
                    _clanView = "locks",
                    statusColor = "online",
                    title = "|cff3fb950[" .. L["Dungeon Finder Queue"] .. "]|r " .. (gameSum.role or "DPS"),
                    detail = L["Currently queued in official Group Finder"],
                })
            end
            if (gameSum.keystoneLevel or 0) > 0 then
                table.insert(lockRows, {
                    _clanView = "locks",
                    statusColor = "nearby",
                    title = string.format("|cfff2c94c[%s]|r +%d %s", L["My Keystone"], gameSum.keystoneLevel, gameSum.keystoneName or ""),
                    detail = (gameSum.mplusScore and gameSum.mplusScore > 0) and (L["Rating"] .. ": " .. gameSum.mplusScore) or "",
                })
            end
            for _, lk in ipairs(ns.Clan:GetSavedLockouts()) do
                local resetHours = math.max(1, math.floor((lk.reset or 0) / 3600))
                local statusStr = lk.locked and L["Locked"] or L["Unlocked"]
                if lk.extended then statusStr = statusStr .. " (" .. L["Extended"] .. ")" end
                table.insert(lockRows, {
                    _clanView = "locks",
                    statusColor = lk.locked and "offline" or "online",
                    title = string.format("%s  |cff9da7b5[%s]|r", lk.name, lk.difficultyName),
                    detail = string.format("%s  ·  %d/%d %s  ·  %s %dh", statusStr, lk.encounterProgress or 0, lk.numEncounters or 0, L["Bosses"], L["Resets in"], resetHours),
                })
            end
        end
        clanPanel.peersScroll:SetData(lockRows, L["No active dungeon/raid lockouts or queues found."], false)
    elseif clanRightView == "diplomacy" then
        local dipRows = {}
        for _, d in ipairs(ns.Clan and ns.Clan:GetDiplomacyList(clanRightViewFilterDip) or {}) do
            local copy = {}
            for k, v in pairs(d) do copy[k] = v end
            copy._clanView = "diplomacy"
            table.insert(dipRows, copy)
        end
        clanPanel.peersScroll:SetData(dipRows, L["No guild diplomacy entries yet. Click '+ Add Guild' to tag Allies or Enemies cleanly."], false)
    else
        clanPanel.peersScroll:SetData(peers, L["No online Guild members seen yet. Open Guild Roster or enable Clan Sync."], false)
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

    local radarBtn = Theme:CreateButton(bottomBar, 96, 20, L["Target Radar"], "default")
    Theme:AutoFitButton(radarBtn, 84, 14, 144)
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

    local clanInfoBtn = Theme:CreateButton(bottomBar, 82, 20, L["Clan Info"], "default")
    Theme:AutoFitButton(clanInfoBtn, 72, 12, 118)
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
    guildName:SetJustifyH("LEFT")
    guildName:SetWordWrap(false)

    local motdEditBtn = Theme:CreateButton(guildHead, 56, 18, L["Edit MOTD"], "default")
    Theme:AutoFitButton(motdEditBtn, 48, 10, 82)
    motdEditBtn:SetPoint("RIGHT", 0, 0)
    motdEditBtn:SetScript("OnClick", OpenMotdModal)
    themeTargets[#themeTargets + 1] = { btn = motdEditBtn, variant = "default" }
    motdEditBtn:Hide()
    guildName:SetPoint("RIGHT", motdEditBtn, "LEFT", -4, 0)

    local sidebarDiv = sidebar:CreateTexture(nil, "ARTWORK")
    sidebarDiv:SetHeight(1)
    sidebarDiv:SetPoint("TOPLEFT", guildHead, "BOTTOMLEFT", 0, -4)
    sidebarDiv:SetPoint("TOPRIGHT", guildHead, "BOTTOMRIGHT", 0, -4)
    sidebarDiv:SetTexture("Interface\\Buttons\\WHITE8X8")
    sidebarDiv:SetVertexColor(0.35, 0.30, 0.22, 0.65)

    local navDefs = {
        { id = "peers", label = L["Roster"] },
        { id = "events", label = L["Events & Calendar"] },
        { id = "diplomacy", label = L["Diplomacy"] },
        { id = "prof", label = L["Professions & Locks"] },
    }
    local prevNav = sidebarDiv
    for _, nd in ipairs(navDefs) do
        local nb = Theme:CreateButton(sidebar, 158, 28, nd.label, "default")
        nb:SetPoint("TOPLEFT", prevNav, "BOTTOMLEFT", 0, (prevNav == sidebarDiv) and -8 or -4)
        nb:SetPoint("TOPRIGHT", prevNav, "BOTTOMRIGHT", 0, (prevNav == sidebarDiv) and -8 or -4)
        nb:SetScript("OnClick", function()
            clanRightView = nd.id
            UpdateClanPanel()
        end)
        clanRightViewButtons[nd.id] = nb
        themeTargets[#themeTargets + 1] = { btn = nb, variant = "default" }
        prevNav = nb
    end

    local openLfgFinderBtn = Theme:CreateButton(sidebar, 158, 28, "+ " .. L["Clans & Allies LFG"], "primary")
    openLfgFinderBtn:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 8, 8)
    openLfgFinderBtn:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -8, 8)
    openLfgFinderBtn:SetScript("OnClick", function()
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if not inCombat and ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
            ns.LFGFrameTab:OpenOfficialModule("lfg")
        else
            ns:Print(L["In Combat"])
        end
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

    local heroSummaryLbl = guildHeroBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    heroSummaryLbl:SetPoint("TOPLEFT", 8, -5)
    heroSummaryLbl:SetPoint("TOPRIGHT", -8, -5)
    heroSummaryLbl:SetJustifyH("LEFT")
    heroSummaryLbl:SetWordWrap(false)

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
    })
    peerSearch:SetPoint("LEFT", 0, 0)
    peerSearch:HookScript("OnTextChanged", function(selfBox)
        clanPeerQuery = selfBox:GetText() or ""
        UpdateClanPanel()
    end)

    local peersHelp = AddHelp(
        peersToolBar,
        peerSearch,
        L["Help: Clan Game Info"],
        L["Centralizes Online Guild Roster (Rank/Zone/Note), Events, Diplomacy stances, Guild Crafters, and Saved Dungeon/Raid Lockouts."],
        L["Type a member name, class, rank, or zone to filter the roster, or switch views in the sidebar."]
    )

    local syncBtn = Theme:CreateButton(peersToolBar, 76, 22, L["Sync"], "default")
    Theme:AutoFitButton(syncBtn, 62, 12, 108)
    syncBtn:SetScript("OnClick", function()
        if ns.Clan then
            ns.Clan:RequestClanSync()
            ns.Clan:RefreshGameCalendar(true)
        end
    end)
    themeTargets[#themeTargets + 1] = { btn = syncBtn, variant = "default" }
    local syncBtnHelp = AddHelp(
        peersToolBar,
        syncBtn,
        L["Help: Clan Sync & Roster"],
        L["Manually requests fresh status tags from online guildmates without background spam loops (max once every 5s, disabled in combat)."],
        L["Enable 'Clan Sync' inside 'My Status', then click 'Sync' whenever you log in or want refreshed guildmate tags."]
    )
    syncBtnHelp:ClearAllPoints()
    syncBtnHelp:SetPoint("RIGHT", peersToolBar, "RIGHT", 0, 0)
    syncBtn:ClearAllPoints()
    syncBtn:SetPoint("RIGHT", syncBtnHelp, "LEFT", -4, 0)

    local guildInviteBtn = Theme:CreateButton(peersToolBar, 84, 22, "+ " .. L["Invite"], "primary")
    Theme:AutoFitButton(guildInviteBtn, 70, 12, 118)
    guildInviteBtn:SetPoint("RIGHT", syncBtn, "LEFT", -6, 0)
    guildInviteBtn:SetScript("OnClick", function()
        OpenGuildInviteModal()
    end)
    themeTargets[#themeTargets + 1] = { btn = guildInviteBtn, variant = "primary" }

    local historyBtn = Theme:CreateButton(peersToolBar, 72, 22, L["History"], "default")
    Theme:AutoFitButton(historyBtn, 60, 12, 108)
    historyBtn:SetPoint("RIGHT", guildInviteBtn, "LEFT", -6, 0)
    historyBtn:SetScript("OnClick", function()
        local list = ns.Clan and ns.Clan.GetRosterHistory and ns.Clan:GetRosterHistory() or {}
        if #list == 0 then
            ns:Print(L["No guild roster changes recorded yet this session."])
            return
        end
        local lines = {}
        local kindLabels = {
            JOINED = L["Joined Guild"],
            LEFT = L["Left Guild"],
            RANK = L["Rank Changed"],
        }
        for _, h in ipairs(list) do
            local stamp = h.ts and date("%Y-%m-%d %H:%M", h.ts) or ""
            local kLabel = kindLabels[h.kind] or h.kind or "?"
            local det = (h.detail and h.detail ~= "") and (" (" .. h.detail .. ")") or ""
            table.insert(lines, string.format("[%s] %s: %s%s", stamp, kLabel, h.name or "?", det))
        end
        if ns.UI and ns.UI.OpenCopyModal then
            ns.UI:OpenCopyModal(table.concat(lines, "\n"), L["Guild Roster History"], L["Shows recent guild joins, leaves, and rank changes observed on your character."])
        end
    end)
    themeTargets[#themeTargets + 1] = { btn = historyBtn, variant = "default" }
    AddHelp(
        peersToolBar,
        historyBtn,
        L["Help: Guild Roster History"],
        L["Tracks recent guild member joins, departures, and rank promotions/demotions across sessions."],
        L["Click 'History' to view and optionally copy the recent Guild Roster changelog."],
        "RIGHT",
        historyBtn,
        "LEFT",
        -4,
        0
    )

    -- 4b) Events contextual toolbar (1 filter dropdown + 1 primary button)
    local eventsToolBar = CreateFrame("Frame", nil, ctxBar)
    eventsToolBar:SetAllPoints()
    eventsToolBar:Hide()

    local evtFilterBtn = Theme:CreateButton(eventsToolBar, 118, 22, L["All"] .. "  v", "default")
    Theme:AutoFitButton(evtFilterBtn, 86, 14, 150)
    evtFilterBtn:SetScript("OnClick", function(self)
        local evtFilters = {
            { id = "all", label = L["All"] },
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
                    if not ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) then
                        if ToggleCalendar then pcall(ToggleCalendar) end
                    end
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

    local newEventBtn = Theme:CreateButton(eventsToolBar, 102, 22, L["+ Event Call"], "primary")
    Theme:AutoFitButton(newEventBtn, 86, 14, 142)
    newEventBtn:SetScript("OnClick", OpenEventModal)
    themeTargets[#themeTargets + 1] = { btn = newEventBtn, variant = "primary" }
    newEventBtn._pairedHelp = AddHelp(
        eventsToolBar,
        newEventBtn,
        L["Help: Clan Event Calls"],
        L["Creates guild-wide group calls for Dungeons, M+, Raids, World Bosses, or PvP where guildmates sign up as Tank, Healer, DPS, or Maybe."],
        L["Click '+ Event Call' to post an event, or use the filter dropdown to inspect 'Calendar' and open the native WoW Calendar."]
    )

    -- 4c) Diplomacy contextual toolbar (1 filter/sync dropdown + 1 primary button)
    local dipToolBar = CreateFrame("Frame", nil, ctxBar)
    dipToolBar:SetAllPoints()
    dipToolBar:Hide()

    local dipFilterBtn = Theme:CreateButton(dipToolBar, 110, 22, L["Filter: All"] .. "  v", "default")
    Theme:AutoFitButton(dipFilterBtn, 90, 14, 145)
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
                root:CreateDivider()
                root:CreateButton(L["Sync Intel"], function()
                    if ns.Clan then
                        ns.Clan:RequestIntelSync()
                        ns.Clan:BroadcastFullIntel()
                    end
                end)
                if ns.Clan and ns.Clan.CanManageAlliance and ns.Clan:CanManageAlliance() then
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

    local dipAddBtn = Theme:CreateButton(dipToolBar, 96, 22, L["+ Add Guild"], "primary")
    Theme:AutoFitButton(dipAddBtn, 84, 12, 142)
    dipAddBtn:SetScript("OnClick", function()
        OpenDiplomacyModal()
    end)
    themeTargets[#themeTargets + 1] = { btn = dipAddBtn, variant = "primary" }

    -- 4d) Professions & Lockouts contextual toolbar (1 view menu/toggle + 1 primary button)
    local profToolBar = CreateFrame("Frame", nil, ctxBar)
    profToolBar:SetAllPoints()
    profToolBar:Hide()

    local profViewBtn = Theme:CreateButton(profToolBar, 118, 22, L["Professions"] .. "  v", "default")
    Theme:AutoFitButton(profViewBtn, 96, 14, 155)
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
                    UpdateClanPanel()
                end)
            end)
        else
            clanRightView = (clanRightView == "locks") and "prof" or "locks"
            UpdateClanPanel()
        end
    end)
    themeTargets[#themeTargets + 1] = { btn = profViewBtn, variant = "default" }

    local profBtn = Theme:CreateButton(profToolBar, 82, 22, "+ " .. L["Prof"], "primary")
    Theme:AutoFitButton(profBtn, 68, 12, 112)
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
        L["Share up to 2 crafting professions and a short service note (e.g. Flasks, Lariat, Enchanting) with guildmates using SocialCentral."],
        L["Click '+ Prof' to set your professions, or switch between 'Professions' and 'Locks' using the selector."]
    )

    local profSearch = Theme:CreateEditBox(profToolBar, {
        width = 140,
        height = 22,
        placeholder = L["Search professions..."],
    })
    profSearch:HookScript("OnTextChanged", function(selfBox)
        clanProfQuery = selfBox:GetText() or ""
        UpdateClanPanel()
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

    local evtItems = { evtFilterBtn, newEventBtn }
    local profItems = { profViewBtn, profBtn, profSearch }
    local dipItems = { dipFilterBtn, dipAddBtn }

    ReflowClanPanel = function()
        if not panel or not topHeader then return end
        local isEmbedded = embeddedState.active == true
        local pw = panel:GetWidth() or 700
        local leftPad = isEmbedded and 58 or 2
        local rightPad = isEmbedded and ((pw < 540) and -34 or -114) or -2
        topHeader:ClearAllPoints()
        topHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", leftPad, -2)
        topHeader:SetPoint("TOPRIGHT", panel, "TOPRIGHT", rightPad, -2)

        sidebar:SetWidth((pw > 0 and pw < 560) and 136 or 174)

        -- Layout bottom bar right-to-left (only Target Radar + Clan Info)
        local cursor = bottomBar
        local function ChainLeft(btn, hBtn)
            if hBtn then
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
        local ctxW = ctxBar:GetWidth() or 420
        local rightReserved = (syncBtn:GetWidth() or 76) + (guildInviteBtn:GetWidth() or 92) + 46
        if peerSearch and peerSearch.SetWidth then
            peerSearch:SetWidth(math.max(96, math.min(184, ctxW - rightReserved)))
        end
        local ctxH = 24
        if clanRightView == "events" then
            ctxH = FlowButtonGroup(eventsToolBar, evtItems, 4, 4, 0)
        elseif clanRightView == "prof" or clanRightView == "locks" then
            ctxH = FlowButtonGroup(profToolBar, profItems, 4, 4, 0)
        elseif clanRightView == "diplomacy" then
            ctxH = FlowButtonGroup(dipToolBar, dipItems, 4, 4, 0)
        end
        ctxBar:SetHeight(math.max(24, ctxH))
        listHolder:ClearAllPoints()
        listHolder:SetPoint("TOPLEFT", ctxBar, "BOTTOMLEFT", -2, -6)
        listHolder:SetPoint("BOTTOMRIGHT", mainCard, "BOTTOMRIGHT", -6, 6)
    end
    panel:SetScript("OnSizeChanged", function()
        if ReflowClanPanel then ReflowClanPanel() end
    end)

    panel.sidebar = sidebar
    panel.mainCard = mainCard
    panel.guildHeroBar = guildHeroBar
    panel.heroSummaryLbl = heroSummaryLbl
    panel.heroDetailLbl = heroDetailLbl
    panel.bottomBar = bottomBar
    panel.guildName = guildName
    panel.guildCounts = guildCounts
    panel.guildMotd = guildMotd
    panel.motdEditBtn = motdEditBtn
    panel.statusBtn = statusBtn
    panel.clanInfoBtn = clanInfoBtn
    panel.radarBtn = radarBtn
    panel.syncStatus = syncStatus
    panel.eventsScroll = eventsScroll
    panel.peerSearch = peerSearch
    panel.guildInviteBtn = guildInviteBtn
    panel.syncBtn = syncBtn
    panel.newEventBtn = newEventBtn
    panel.dipFilterBtn = dipFilterBtn
    panel.dipAddBtn = dipAddBtn
    panel.profBtn = profBtn
    panel.profSearch = profSearch
    panel.openLfgFinderBtn = openLfgFinderBtn
    panel.peersScroll = peersScroll
    panel.peersToolBar = peersToolBar
    panel.eventsToolBar = eventsToolBar
    panel.evtFilterBtn = evtFilterBtn
    panel.profToolBar = profToolBar
    panel.profViewBtn = profViewBtn
    panel.dipToolBar = dipToolBar
    panel.dipFilterBtn = dipFilterBtn
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
    local avail = frame.tabBar:GetWidth() or 0
    if avail <= 0 then
        avail = (frame:GetWidth() or 790) - (isBlizz and 78 or 24)
    end
    local visibleTabs = {}
    for _, info in ipairs(tabOrder) do
        local allowed = IsTabAllowed(info.id)
        info.btn:SetShown(allowed)
        if allowed then
            visibleTabs[#visibleTabs + 1] = info
        end
    end
    if #visibleTabs == 0 then
        return
    end
    local pad = isBlizz and 18 or 16
    local gap = 4
    local minW = 46
    local widths = {}
    local function MeasureAll(p)
        local sum = 0
        for i, info in ipairs(visibleTabs) do
            local w = Theme:AutoFitButton(info.btn, minW, p, 220)
            widths[i] = w
            sum = sum + w
        end
        return sum + gap * math.max(0, #visibleTabs - 1)
    end
    local total = MeasureAll(pad)
    if total > avail and avail > 200 then
        pad = 12
        gap = 2
        total = MeasureAll(pad)
    end
    if total > avail and avail > 200 then
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
                info.btn:SetWidth(nw)
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
        if info.btn.SetClipsChildren then
            info.btn:SetClipsChildren(true)
        end
        Theme:StyleButton(info.btn, "tab")
        if info.id then
            Theme:SetButtonActive(info.btn, info.id == activeTab, "tab")
        end
        prev = info.btn
    end
end

local function MaxHierarchyFrameLevel(root, depth)
    local maxLevel = 0
    if not root or (depth or 0) <= 0 then
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
            local childMax = MaxHierarchyFrameLevel(children[i], (depth or 1) - 1)
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
    -- so elevate the active close button strictly above every chrome descendant.
    local topLevel = math.max(
        (frame:GetFrameLevel() or 1) + 60,
        frame.header and (frame.header:GetFrameLevel() or 0) or 0,
        frame.blizzTitleDrag and (frame.blizzTitleDrag:GetFrameLevel() or 0) or 0,
        MaxHierarchyFrameLevel(frame.blizzChrome, 3) + 50
    )
    btn:SetFrameLevel(topLevel)
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

local function ApplyTheme()
    if not frame then
        return
    end
    local isEmbedded = embeddedState.active == true
    local p = Theme:GetPalette()
    local isBlizz = Theme:IsBlizzard(p)
    local baseLevel = frame:GetFrameLevel()
    local fw = frame:GetWidth() or 760
    local isCompact = isEmbedded and fw < 540

    if frame._solidOpaqueBg then
        local wBg = p.windowBg or { 0.075, 0.07, 0.065, 1.0 }
        frame._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
        frame._solidOpaqueBg:Show()
    end

    if frame.blizzChrome then
        frame.blizzChrome:SetFrameLevel(baseLevel)
        frame.blizzChrome:SetShown(isBlizz and not isEmbedded)
        if isBlizz and not isEmbedded and frame.blizzChrome.Inset then
            frame.blizzChrome.Inset:ClearAllPoints()
            frame.blizzChrome.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -85)
            frame.blizzChrome.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 12)
        end
    end

    local showEmbeddedArt = isEmbedded and isBlizz
    if frame._embeddedArtBg then frame._embeddedArtBg:SetShown(showEmbeddedArt) end
    if frame._embeddedHeaderStone then frame._embeddedHeaderStone:SetShown(showEmbeddedArt) end
    if frame._embeddedInsideFrame then frame._embeddedInsideFrame:SetShown(showEmbeddedArt) end

    if frame.blizzTitleDrag then
        frame.blizzTitleDrag:SetFrameStrata(frame:GetFrameStrata())
        frame.blizzTitleDrag:SetFrameLevel(baseLevel + 24)
        frame.blizzTitleDrag:SetShown((not isEmbedded) and isBlizz and frame.blizzChrome and true or false)
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
    else
        frame._scLocked = false
        if frame.grip then
            frame.grip:Show()
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
        frame.header:SetFrameLevel(baseLevel + 10)
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

    if frame.tabBar then
        local singleEmbedded = IsSingleTabEmbedded()
        frame.tabBar:SetShown(not singleEmbedded)
        frame.tabBar:SetFrameLevel(baseLevel + 11)
        frame.tabBar:ClearAllPoints()
        if isEmbedded then
            local rightReserve = isCompact and 54 or 160
            frame.tabBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -5)
            frame.tabBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -rightReserve, -5)
            frame.tabBar:SetHeight(26)
        elseif isBlizz and frame.blizzChrome then
            frame.tabBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 66, -59)
            frame.tabBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -59)
            frame.tabBar:SetHeight(26)
        else
            frame.tabBar:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 12, -8)
            frame.tabBar:SetPoint("TOPRIGHT", frame.header, "BOTTOMRIGHT", -12, -8)
            frame.tabBar:SetHeight(26)
        end
    end
    if frame.headerHelp then
        frame.headerHelp:SetShown(not IsSingleTabEmbedded())
    end

    if frame.filterBar then
        frame.filterBar:SetFrameLevel(baseLevel + 8)
        frame.filterBar:ClearAllPoints()
        if isEmbedded then
            frame.filterBar:SetPoint("TOPLEFT", frame.tabBar, "BOTTOMLEFT", 0, -8)
            frame.filterBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -39)
        elseif isBlizz and frame.blizzChrome then
            frame.filterBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -93)
            frame.filterBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -93)
        else
            frame.filterBar:SetPoint("TOPLEFT", frame.tabBar, "BOTTOMLEFT", 0, -8)
            frame.filterBar:SetPoint("TOPRIGHT", frame.tabBar, "BOTTOMRIGHT", 0, -8)
        end
    end
    if frame.watchBar then frame.watchBar:SetFrameLevel(baseLevel + 8) end
    if frame.content then frame.content:SetFrameLevel(baseLevel + 8) end
    if frame.grip then frame.grip:SetFrameLevel(baseLevel + 14) end

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
    if clanLfgModalFrame and clanLfgModalFrame:IsShown() then
        Theme:ApplyBackdrop(clanLfgModalFrame, "window", p)
        if clanLfgModalFrame.btnPost then Theme:StyleButton(clanLfgModalFrame.btnPost, "primary") end
        if clanLfgModalFrame.btnShareG then Theme:StyleButton(clanLfgModalFrame.btnShareG, "default") end
        if clanLfgModalFrame.btnClear then Theme:StyleButton(clanLfgModalFrame.btnClear, "danger") end
        if clanLfgModalFrame.btnCancel then Theme:StyleButton(clanLfgModalFrame.btnCancel, "default") end
        for _, it in ipairs(clanLfgModalFrame._modeBtns or {}) do
            Theme:StyleButton(it.btn, "default")
            Theme:SetButtonActive(it.btn, clanLfgModalFrame._mode == it.id, "default")
        end
        for _, it in ipairs(clanLfgModalFrame._roleBtns or {}) do
            Theme:StyleButton(it.btn, "default")
            Theme:SetButtonActive(it.btn, clanLfgModalFrame._role == it.id, "default")
        end
    end
    if clanAlertModalFrame and clanAlertModalFrame:IsShown() then
        Theme:ApplyBackdrop(clanAlertModalFrame, "window", p)
        if clanAlertModalFrame.btnSave then Theme:StyleButton(clanAlertModalFrame.btnSave, "primary") end
        if clanAlertModalFrame.btnCancel then Theme:StyleButton(clanAlertModalFrame.btnCancel, "default") end
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
    if buffsPanel and buffsPanel.RefreshTheme then
        buffsPanel:RefreshTheme()
    end
    UI:Refresh()
end

local function BuildMainFrame()
    frame = CreateFrame("Frame", "SocialCentralFrame", UIParent, "BackdropTemplate")
    local w = ns.db and ns.db.window or { width = 820, height = 520 }
    local initW = math.max(760, w.width or 820)
    local initH = math.max(460, w.height or 520)
    frame:SetSize(initW, initH)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(760, 460, 1140, 840)
    elseif frame.SetMinResize then
        frame:SetMinResize(760, 460)
        frame:SetMaxResize(1140, 840)
    end

    if w.point and w.x and w.y then
        frame:SetPoint(w.point, UIParent, w.relativePoint or w.point, w.x, w.y)
    else
        frame:SetPoint("CENTER")
    end

    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetFrameStrata("MEDIUM")
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
    if HasAtlas("groupfinder-background") then
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
    if HasAtlas("groupfinder-Stat-StoneBG") then
        embeddedHeaderStone:SetAtlas("groupfinder-Stat-StoneBG", false)
    else
        embeddedHeaderStone:SetTexture(WHITE8X8)
        embeddedHeaderStone:SetVertexColor(0.11, 0.10, 0.09, 1.0)
    end
    embeddedHeaderStone:Hide()
    frame._embeddedHeaderStone = embeddedHeaderStone

    local embeddedInsideFrame = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    embeddedInsideFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -34)
    embeddedInsideFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    if HasAtlas("common-insideframe") then
        embeddedInsideFrame:SetAtlas("common-insideframe", false)
    else
        embeddedInsideFrame:Hide()
    end
    embeddedInsideFrame:Hide()
    frame._embeddedInsideFrame = embeddedInsideFrame

    local blizzOk, blizzChrome = pcall(CreateFrame, "Frame", "SocialCentralBlizzChrome", frame, "ButtonFrameTemplate")
    if blizzOk and blizzChrome then
        blizzChrome:SetAllPoints(frame)
        blizzChrome:SetFrameLevel(math.max(0, frame:GetFrameLevel()))
        blizzChrome:EnableMouse(false)
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
            if HasAtlas("groupfinder-background") then
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

    local blizzTitleDrag = CreateFrame("Frame", nil, frame)
    blizzTitleDrag:SetPoint("TOPLEFT", frame, "TOPLEFT", 58, -2)
    blizzTitleDrag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -2)
    blizzTitleDrag:SetHeight(22)
    blizzTitleDrag:EnableMouse(true)
    blizzTitleDrag:Hide()
    frame.blizzTitleDrag = blizzTitleDrag

    local dragHandles = { header, blizzTitleDrag }
    Theme:MakeMovable(frame, {
        key = "main",
        handles = dragHandles,
        onStop = SaveGeometry,
        onReset = SaveGeometry,
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
    updateBtn:Hide()
    frame.updateBtn = updateBtn
    themeTargets[#themeTargets + 1] = { btn = updateBtn, variant = "default" }

    local headerHelp = AddHelp(
        header,
        settingsBtn,
        L["Help: SocialCentral Overview"],
        L["Blizzard-safe social center integrating Friends, Guild, Battle.net, Friendly Nearby, Alts Gold, Watchlist (/who), and Clan Hub."],
        L["Use '/sc', '/sc check Name', or '/sc config', or click the Minimap button. Hover or click '?' beside any option for detailed guidance."],
        "RIGHT",
        "LEFT",
        -6,
        0
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

    local tabDefs = {
        { id = "watchlist", label = L["Watchlist"], width = 108 },
        { id = "social", label = L["Social"], width = 94 },
        { id = "chat", label = L["Chat"], width = 88 },
        { id = "clan", label = L["Clan"], width = 80 },
        { id = "group", label = L["Group"], width = 90 },
        { id = "nearby", label = L["Nearby"], width = 98 },
        { id = "buffs", label = L["Buffs"], width = 84 },
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
            if self._scTruncated and GameTooltip then
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
            activeTab = def.id
            if def.id == "watchlist" and ns.Watchlist and ns.Watchlist.AutoCheckNextFromHardwareClick then
                ns.Watchlist:AutoCheckNextFromHardwareClick()
            elseif def.id == "social" and ns.Social then
                ns.Social:RequestRosters(false)
            elseif def.id == "clan" and ns.Clan then
                ns.Clan:RefreshGameCalendar(false)
            elseif def.id == "group" and ns.Group then
                ns.Group:Scan()
            elseif def.id == "buffs" and ns.WorldBuffs then
                ns.WorldBuffs:Scan()
            end
            UI:Refresh(true)
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
        searchQuery = Compat.CleanInput(self:GetText() or "") or ""
        UI:Refresh(true)
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
        L["Combines live online friends from Guild, Character Friends, and Battle.net without spending /who cooldown."],
        L["Click a source button (All, Guild, Friends, Battle.net) or type in search. Right-click a row to Whisper, Invite, or add to Watchlist."],
        "RIGHT",
        "RIGHT",
        -2,
        0
    )

    local watchFilterBar = CreateFrame("Frame", nil, filterBar)
    watchFilterBar:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    watchFilterBar:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
    watchFilterBar:SetHeight(26)
    frame.watchFilterBar = watchFilterBar

    local groupFilterBtn = Theme:CreateButton(watchFilterBar, 128, 22, L["All Groups"], "default")
    Theme:AutoFitButton(groupFilterBtn, 108, 18, 175)
    groupFilterBtn:SetPoint("LEFT", 0, 0)
    table.insert(themeTargets, { btn = groupFilterBtn, variant = "default" })
    frame.groupFilterBtn = groupFilterBtn

    groupFilterBtn:SetScript("OnClick", function(self)
        local groups = ns.Watchlist and ns.Watchlist:GetGroups() or {}
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                local addChoice = root.CreateRadio or root.CreateCheckbox
                root:CreateTitle(L["Set Group Tag"])
                addChoice(root, L["All Groups"], function()
                    return watchlistGroupFilter == "all"
                end, function()
                    watchlistGroupFilter = "all"
                    UI:Refresh(true)
                end)
                addChoice(root, L["Favorites"], function()
                    return watchlistGroupFilter == "__fav"
                end, function()
                    watchlistGroupFilter = "__fav"
                    UI:Refresh(true)
                end)
                if #groups > 0 then
                    root:CreateDivider()
                    for _, grp in ipairs(groups) do
                        local gName = grp
                        addChoice(root, gName, function()
                            return watchlistGroupFilter == gName
                        end, function()
                            watchlistGroupFilter = gName
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

    local sortBtn = Theme:CreateButton(watchFilterBar, 120, 22, GetSortLabel(ns.db and ns.db.settings and ns.db.settings.sortBy or "status"), "default")
    Theme:AutoFitButton(sortBtn, 112, 18, 165)
    sortBtn:SetPoint("LEFT", groupFilterBtn, "RIGHT", 6, 0)
    table.insert(themeTargets, { btn = sortBtn, variant = "default" })
    frame.sortBtn = sortBtn

    sortBtn:SetScript("OnClick", function()
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
    end)

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
        L["Forever surnames auto-fill from Guild Roster, Friends, or chat. Right-click any character row to set or edit its surname manually or remove old alts."],
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

    local clearNearbyBtn = Theme:CreateButton(nearbyBar, 64, 22, L["Clear"], "default")
    Theme:AutoFitButton(clearNearbyBtn, 50, 16, 90)
    clearNearbyBtn:SetPoint("RIGHT", nearbyBar, "RIGHT", -26, 0)
    clearNearbyBtn:SetScript("OnClick", function()
        if ns.Nearby and ns.Nearby.Clear then
            ns.Nearby:Clear()
        end
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
    themeTargets[#themeTargets + 1] = { btn = clearNearbyBtn, variant = "default" }

    local nearbyHelp = AddHelp(
        nearbyBar,
        nearbyBar,
        L["Help: Nearby Players"],
        L["Passively records friendly nearby players seen via nameplates, target, mouseover, group, or chat (never hostile PvP tracking)."],
        L["Shows recently seen friendly players in your area. Click '+ Watchlist' or right-click to follow someone permanently."],
        "RIGHT",
        "RIGHT",
        -2,
        0
    )

    local socialFilterBtn = Theme:CreateButton(socialBar, 146, 22, L["All"] .. "  v", "default")
    socialFilterBtn:SetPoint("LEFT", socialBar, "LEFT", 0, 0)
    themeTargets[#themeTargets + 1] = { btn = socialFilterBtn, variant = "default" }
    frame.socialFilterBtn = socialFilterBtn

    local filterDefs = {
        { id = "all", label = L["All"] },
        { id = "guild", label = L["Guild"] },
        { id = "friend", label = L["Friends"] },
        { id = "bnet", label = L["Battle.net"] },
    }
    socialFilterBtn:SetScript("OnClick", function(self)
        local folders = ns.Store and ns.Store:GetSocialFolders() or {}
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                local addChoice = root.CreateRadio or root.CreateCheckbox
                root:CreateTitle(L["Filters"])
                for _, def in ipairs(filterDefs) do
                    local id = def.id
                    addChoice(root, def.label, function()
                        return socialFilter == id
                    end, function()
                        socialFilter = id
                        UI:Refresh(true)
                    end)
                end
                root:CreateDivider()
                root:CreateTitle(L["Social Folders"])
                addChoice(root, L["All Folders"], function()
                    return socialFolderFilter == "all"
                end, function()
                    socialFolderFilter = "all"
                    UI:Refresh(true)
                end)
                for _, fName in ipairs(folders) do
                    local fn = fName
                    addChoice(root, fn, function()
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

    if socialHelp then
        socialHelp:Raise()
    end

    ReflowFilterBar = function()
        if not filterBar or not searchBox then
            return
        end
        local avail = filterBar:GetWidth() or 0
        if avail <= 0 then
            avail = (frame:GetWidth() or 790) - 34
        end
        local compact = avail < 540
        local subBars = { socialBar, watchFilterBar, altsBar, nearbyBar }

        searchBox:ClearAllPoints()
        if compact then
            searchBox:SetPoint("TOPLEFT", filterBar, "TOPLEFT", 2, -2)
            searchBox:SetPoint("TOPRIGHT", filterBar, "TOPRIGHT", -2, -2)
            searchBox:SetHeight(22)

            local rowH = 24
            for _, sb in ipairs(subBars) do
                sb:ClearAllPoints()
                sb:SetPoint("TOPLEFT", filterBar, "TOPLEFT", 2, -28)
                sb:SetPoint("TOPRIGHT", filterBar, "TOPRIGHT", -2, -28)
            end

            if activeTab == "social" then
                Theme:AutoFitButton(socialFilterBtn, 110, 12, 195)
                local sBtns = { socialFilterBtn }
                if socialHelp then table.insert(sBtns, socialHelp) end
                local flowH = FlowButtonGroup(socialBar, sBtns, 6, 4, 0)
                socialBar:SetHeight(flowH)
                rowH = flowH
            elseif activeTab == "watchlist" then
                Theme:AutoFitButton(groupFilterBtn, 78, 10, 145)
                Theme:AutoFitButton(sortBtn, 82, 10, 145)
                local wBtns = { groupFilterBtn, sortBtn }
                if watchFilterHelp then table.insert(wBtns, watchFilterHelp) end
                local flowH = FlowButtonGroup(watchFilterBar, wBtns, 6, 4, 0)
                watchFilterBar:SetHeight(flowH)
                rowH = flowH
            elseif activeTab == "alts" then
                altsBar:SetHeight(24)
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
                nearbyBar:SetHeight(24)
                if nearbyHelp then
                    nearbyHelp:ClearAllPoints()
                    nearbyHelp:SetPoint("RIGHT", nearbyBar, "RIGHT", -2, 0)
                end
                if clearNearbyBtn then
                    clearNearbyBtn:ClearAllPoints()
                    clearNearbyBtn:SetPoint("LEFT", nearbyBar, "LEFT", 0, 0)
                end
            end
            filterBar:SetHeight(28 + math.max(24, rowH))
        else
            searchBox:SetHeight(24)
            searchBox:SetPoint("LEFT", filterBar, "LEFT", 4, 0)
            for _, sb in ipairs(subBars) do
                sb:ClearAllPoints()
                sb:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
                sb:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
                sb:SetHeight(26)
            end

            Theme:AutoFitButton(socialFilterBtn, 128, 16, 220)
            socialFilterBtn:ClearAllPoints()
            socialFilterBtn:SetPoint("LEFT", socialBar, "LEFT", 0, 0)
            if socialHelp then
                socialHelp:ClearAllPoints()
                socialHelp:SetPoint("RIGHT", socialBar, "RIGHT", -2, 0)
            end

            Theme:AutoFitButton(groupFilterBtn, 108, 18, 175)
            Theme:AutoFitButton(sortBtn, 112, 18, 165)
            groupFilterBtn:ClearAllPoints()
            groupFilterBtn:SetPoint("LEFT", watchFilterBar, "LEFT", 0, 0)
            sortBtn:ClearAllPoints()
            sortBtn:SetPoint("LEFT", groupFilterBtn, "RIGHT", 6, 0)
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

            local desiredSearch = math.max(150, math.min(250, math.floor(avail * 0.28)))
            if activeTab == "social" then
                local fltW = socialFilterBtn:GetWidth() or 140
                local maxSearchForSocial = avail - (fltW + 44)
                desiredSearch = math.max(150, math.min(280, maxSearchForSocial))
            end
            searchBox:SetWidth(desiredSearch)
            filterBar:SetHeight(26)
        end
    end
    filterBar:SetScript("OnSizeChanged", function()
        ReflowFilterBar()
    end)
    ReflowFilterBar()

    -- Watchlist Input Bar
    local watchBar = CreateFrame("Frame", nil, frame)
    watchBar:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -8)
    watchBar:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", 0, -8)
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

    local function SubmitAdd()
        if not ns.Watchlist then return end
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
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local addBtn = Theme:CreateButton(watchBar, 76, 24, "+ " .. L["Add"], "default")
    Theme:AutoFitButton(addBtn, 66, 16, 112)
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
    themeTargets[#themeTargets + 1] = { btn = addBtn, variant = "default" }

    local watchHelp = AddHelp(
        watchBar,
        watchBar,
        L["Help: Manual Watchlist & /who"],
        L["Lets you add any character manually (or your current target) and run an official single /who query outside combat with cooldown >= 5s."],
        L["Type Name or Name-Surname and click '+ Add' (or leave empty while targeting a player), or click 'Check Next' to /who the typed character or oldest entry."],
        "RIGHT",
        "RIGHT",
        -2,
        0
    )

    -- Hidden compatibility button reference (Watchlist status updates automatically without manual check buttons).
    checkNextBtn = Theme:CreateButton(watchBar, 2, 2, "", "primary")
    checkNextBtn:Hide()

    ReflowWatchBar = function()
        if not watchBar or not addBox then
            return
        end
        if checkNextBtn then
            checkNextBtn:Hide()
        end
        local avail = watchBar:GetWidth() or 0
        if avail <= 0 then
            avail = (frame:GetWidth() or 790) - 34
        end
        watchBar:ClearAllPoints()
        watchBar:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -6)
        watchBar:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", 0, -6)

        local compact = avail < 420
        Theme:AutoFitButton(addBtn, compact and 60 or 66, compact and 12 or 16, 128)
        if watchHelp then
            watchHelp:ClearAllPoints()
            watchHelp:SetPoint("RIGHT", watchBar, "RIGHT", -2, 0)
        end
        addBtn:ClearAllPoints()
        addBtn:SetPoint("RIGHT", watchHelp or watchBar, watchHelp and "LEFT" or "RIGHT", -6, 0)

        local buttonsW = (addBtn:GetWidth() or 76) + (watchHelp and (watchHelp:GetWidth() or 18) or 18) + 18
        addBox:ClearAllPoints()
        addBox:SetPoint("LEFT", watchBar, "LEFT", 4, 0)
        addBox:SetPoint("RIGHT", addBtn, "LEFT", -6, 0)
        addBox:SetHeight(compact and 22 or 24)
        addBox:SetWidth(math.max(120, avail - buttonsW))
        watchBar:SetHeight(28)
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

    scrollList = Theme:CreateScrollList(content, 40, CreateListRow, UpdateListRow)
    scrollList.container:SetAllPoints()

    clanPanel = CreateClanPanel(content)
    groupPanel = ns.SocialPanels and ns.SocialPanels:CreateGroupPanel(content)
    if groupPanel then groupPanel:Hide() end
    chatPanel = ns.SocialPanels and ns.SocialPanels:CreateChatPanel(content)
    if chatPanel then chatPanel:Hide() end
    buffsPanel = ns.SocialPanels and ns.SocialPanels:CreateBuffsPanel(content)
    if buffsPanel then buffsPanel:Hide() end
    altsPanel = ns.SocialPanels and ns.SocialPanels:CreateAltsPanel(content)
    if altsPanel then altsPanel:Hide() end

    -- Resize Grip
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        if frame._scSavePosition then
            frame._scSavePosition()
        end
        SaveGeometry()
    end)
    frame.grip = grip

    -- Use HookScript so Theme:MakeMovable OnShow/OnHide drag & position hooks stay intact.
    frame:HookScript("OnShow", function()
        ApplyTheme()
        if ns.Social then ns.Social:RequestRosters(false) end
        if ticker then ticker:Cancel() end
        ticker = C_Timer.NewTicker(1, function()
            if frame and frame:IsShown() then
                UpdateWhoButtons()
                if activeTab ~= "clan" and activeTab ~= "group" and activeTab ~= "chat" and activeTab ~= "buffs" and activeTab ~= "alts" and scrollList then
                    scrollList:Render()
                end
            end
        end)
        UI:Refresh(true)
    end)

    frame:HookScript("OnSizeChanged", function()
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
        if eventModalFrame then
            eventModalFrame:Hide()
        end
        if clanLfgModalFrame then
            clanLfgModalFrame:Hide()
        end
        if clanAlertModalFrame then
            clanAlertModalFrame:Hide()
        end
        if clanInfoModalFrame then
            clanInfoModalFrame:Hide()
        end
        if diplomacyModalFrame then
            diplomacyModalFrame:Hide()
        end
        SaveGeometry()
        local wasEmbedded = embeddedState.active
        local prevHost = embeddedState.host
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
                    local inCombatNow = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
                    if frame and not embeddedState.active and not frame:IsShown() and not inCombatNow and frame:GetParent() == prevHost then
                        frame:SetParent(UIParent)
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

--- Refresh active tab state, badges, and visible list items.
function UI:Refresh(resetScroll)
    if not frame or not frame:IsShown() then
        return
    end

    local watchCount = ns.Watchlist and #ns.Watchlist:GetEntries() or 0
    local socialCount = ns.Social and #ns.Social:GetList("all") or 0
    local nearbyCount = ns.Nearby and #ns.Nearby:GetList() or 0
    local altsCount = ns.Store and #ns.Store:GetAltsList() or 0
    local groupCount = ns.Group and #ns.Group:GetMembers() or 0
    local chatUnread = ns.Chat and ns.Chat:GetTotalUnread() or 0
    local clanEvents = ns.Clan and #ns.Clan:GetEventsList("open") or 0
    local clanLfg = ns.Clan and #ns.Clan:GetClanLFGList() or 0
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
        local label = counts[id] and string.format("%s (%d)", info.baseLabel, counts[id]) or info.baseLabel
        info.btn._scFullText = label
        Theme:SetButtonText(info.btn, label)
        Theme:SetButtonActive(info.btn, activeTab == id, "tab")
    end
    ReflowTabStrip()

    if ns.Watchlist then
        local on, off, unk = ns.Watchlist:GetStats()
        frame.summaryText:SetText(string.format("%s: %d  |  %s: %d  |  %s: %d", L["Online"], on, L["Offline"], off, L["Unchecked"], unk))
    end

    local settingsAnchor = (frame.settingsBtn and frame.settingsBtn:IsShown() and frame.settingsBtn) or frame.settingsCompactBtn
    if frame.updateBtn then
        local remoteVer = ns.Clan and ns.Clan.latestRemoteVersion
        local hasUpdate = remoteVer and Compat.CompareSemVer(remoteVer, ns.version or "0.0.0") > 0
        local allowUpdateBanner = hasUpdate and not (embeddedState.active and (frame:GetWidth() or 0) < 540)
        if allowUpdateBanner and settingsAnchor then
            Theme:SetButtonText(frame.updateBtn, L["Update %s"]:format("v" .. remoteVer))
            Theme:SetButtonActive(frame.updateBtn, true, "primary")
            frame.updateBtn:ClearAllPoints()
            frame.updateBtn:SetPoint("RIGHT", settingsAnchor, "LEFT", -6, 0)
            frame.updateBtn:Show()
            if frame.headerHelp then
                frame.headerHelp:ClearAllPoints()
                frame.headerHelp:SetPoint("RIGHT", frame.updateBtn, "LEFT", -6, 0)
            end
        else
            frame.updateBtn:Hide()
            if frame.headerHelp and settingsAnchor then
                frame.headerHelp:ClearAllPoints()
                frame.headerHelp:SetPoint("RIGHT", settingsAnchor, "LEFT", -4, 0)
            end
        end
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

    if ns.Store and socialFolderFilter ~= "all" then
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
    local isFullPanel = (activeTab == "clan" or activeTab == "group" or activeTab == "chat" or activeTab == "buffs" or activeTab == "alts")
    frame.filterBar:SetShown(not isFullPanel)
    frame.socialBar:SetShown(activeTab == "social")
    frame.watchFilterBar:SetShown(activeTab == "watchlist")
    frame.altsBar:SetShown(false)
    frame.nearbyBar:SetShown(activeTab == "nearby")
    frame.watchBar:SetShown(activeTab == "watchlist")

    if frame.groupFilterBtn then
        local groupLabel = L["All Groups"]
        if watchlistGroupFilter == "__fav" then
            groupLabel = L["Favorites"]
        elseif watchlistGroupFilter ~= "all" then
            groupLabel = watchlistGroupFilter
        end
        Theme:SetButtonText(frame.groupFilterBtn, groupLabel)
        Theme:SetButtonActive(frame.groupFilterBtn, watchlistGroupFilter ~= "all")
    end
    if frame.socialFilterBtn then
        local srcLabels = {
            all = L["All"],
            guild = L["Guild"],
            friend = L["Friends"],
            bnet = L["Battle.net"],
        }
        local sLbl = srcLabels[socialFilter] or L["All"]
        if socialFolderFilter ~= "all" then
            sLbl = sLbl .. " · " .. socialFolderFilter
        end
        Theme:SetButtonText(frame.socialFilterBtn, sLbl .. "  v")
        Theme:SetButtonActive(frame.socialFilterBtn, socialFilter ~= "all" or socialFolderFilter ~= "all", "default")
    end
    if frame.sortBtn then
        local mode = (ns.db and ns.db.settings and ns.db.settings.sortBy) or "status"
        Theme:SetButtonText(frame.sortBtn, GetSortLabel(mode))
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
    if frame.tabBar then
        frame.tabBar:SetShown(not singleEmbedded)
    end
    frame.content:ClearAllPoints()
    if activeTab == "watchlist" then
        frame.content:SetPoint("TOPLEFT", frame.watchBar, "BOTTOMLEFT", 0, -6)
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

    clanPanel:SetShown(activeTab == "clan")
    if groupPanel then groupPanel:SetShown(activeTab == "group") end
    if chatPanel then chatPanel:SetShown(activeTab == "chat") end
    if buffsPanel then buffsPanel:SetShown(activeTab == "buffs") end
    if altsPanel then altsPanel:SetShown(activeTab == "alts") end
    scrollList.container:SetShown(not isFullPanel)

    if activeTab == "clan" then
        UpdateClanPanel()
    elseif activeTab == "group" and groupPanel then
        groupPanel:Refresh(resetScroll)
    elseif activeTab == "chat" and chatPanel then
        chatPanel:Refresh(resetScroll)
    elseif activeTab == "buffs" and buffsPanel then
        buffsPanel:Refresh(resetScroll)
    elseif activeTab == "alts" and altsPanel then
        altsPanel:Refresh(resetScroll)
    else
        local emptyText = activeTab == "watchlist" and L["Watchlist is empty."] or L["No entries match your filter."]
        scrollList:SetData(BuildFilteredRows(), emptyText, resetScroll)
    end

    UpdateWhoButtons()
end

local function MaybePromptThemePicker()
    if ns.db and ns.db.settings and not ns.db.settings.themeChosen then
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if not inCombat and Theme and Theme.ShowThemeWelcomePicker then
            Theme:ShowThemeWelcomePicker()
        end
    end
end

local function TriggerTabRefresh(tabId)
    if tabId == "social" and ns.Social then
        ns.Social:RequestRosters(false)
    elseif tabId == "clan" and ns.Clan then
        ns.Clan:RefreshGameCalendar(false)
    elseif tabId == "group" and ns.Group then
        ns.Group:Scan()
    elseif tabId == "buffs" and ns.WorldBuffs then
        ns.WorldBuffs:Scan()
    elseif tabId == "alts" and ns.Alts then
        ns.Alts:Snapshot(false)
    end
end

local function RestoreStandalonePlacement()
    if not frame then return end
    frame._scLocked = false
    if frame:GetParent() ~= UIParent then
        frame:SetParent(UIParent)
    end
    if frame.SetResizeBounds then
        frame:SetResizeBounds(760, 460, 1140, 840)
    elseif frame.SetMinResize then
        frame:SetMinResize(760, 460)
        frame:SetMaxResize(1140, 840)
    end
    local w = ns.db and ns.db.window or { width = 820, height = 520 }
    frame:SetSize(math.max(760, w.width or 820), math.max(460, w.height or 520))
    frame:ClearAllPoints()
    if w.point and w.x and w.y then
        frame:SetPoint(w.point, UIParent, w.relativePoint or w.point, w.x, w.y)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetFrameStrata("MEDIUM")
end

local function SetMinFrameLevel(obj, minLevel)
    if obj and obj.GetFrameLevel and obj.SetFrameLevel then
        local cur = obj:GetFrameLevel() or 0
        if cur < minLevel then
            pcall(obj.SetFrameLevel, obj, minLevel)
        end
    end
end

local function ScanEmbeddedHostContentMax(hostFrame)
    local contentMax = (hostFrame.GetFrameLevel and hostFrame:GetFrameLevel()) or 1
    local skip = {
        [hostFrame.NineSlice or false] = true,
        [hostFrame.BorderFrame or false] = true,
        [hostFrame.PortraitContainer or false] = true,
        [hostFrame.PortraitOverlay or false] = true,
        [hostFrame.TitleContainer or false] = true,
        [hostFrame.CloseButton or false] = true,
        [hostFrame.MaximizeMinimizeFrame or false] = true,
        [frame or false] = true,
        [_G.SocialCentralLFGSubPanel or false] = true,
    }
    local hRight = hostFrame.GetRight and hostFrame:GetRight() or nil
    local hLeft = hostFrame.GetLeft and hostFrame:GetLeft() or nil
    local hTop = hostFrame.GetTop and hostFrame:GetTop() or nil
    local function Scan(node, depth)
        if not node or depth <= 0 or not node.GetChildren then
            return
        end
        for _, child in ipairs({ node:GetChildren() }) do
            if not skip[child] and (not child.IsShown or child:IsShown()) then
                local cLeft = child.GetLeft and child:GetLeft()
                local cTop = child.GetTop and child:GetTop()
                local cW = (child.GetWidth and child:GetWidth()) or 0
                local cH = (child.GetHeight and child:GetHeight()) or 0
                local isSideTab = hRight and cLeft and cLeft >= (hRight - 14) and cW >= 24 and cW <= 76
                local isPortraitCorner = hLeft and hTop and cLeft and cTop and cLeft <= (hLeft + 34) and cTop >= (hTop - 34) and cW <= 115 and cH <= 115
                if not isSideTab and not isPortraitCorner then
                    local lvl = (child.GetFrameLevel and child:GetFrameLevel()) or 0
                    if lvl > contentMax then
                        contentMax = lvl
                    end
                    Scan(child, depth - 1)
                end
            end
        end
    end
    Scan(hostFrame, (hostFrame == _G.WorldMapFrame) and 5 or 3)
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

    local hRight = hostFrame.GetRight and hostFrame:GetRight() or nil
    local hLeft = hostFrame.GetLeft and hostFrame:GetLeft() or nil
    local hTop = hostFrame.GetTop and hostFrame:GetTop() or nil
    if hostFrame.GetChildren then
        for _, child in ipairs({ hostFrame:GetChildren() }) do
            if child ~= frame and child ~= _G.SocialCentralLFGSubPanel then
                local cLeft = child.GetLeft and child:GetLeft()
                local cTop = child.GetTop and child:GetTop()
                local cW = (child.GetWidth and child:GetWidth()) or 0
                local cH = (child.GetHeight and child:GetHeight()) or 0
                local cName = child.GetName and child:GetName() or ""
                if hRight and cLeft and cLeft >= (hRight - 14) and cW >= 24 and cW <= 76 then
                    SetMinFrameLevel(child, minControlLevel + 8)
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
        for _, scTab in ipairs({ ns.LFGFrameTab.sideTab, ns.LFGFrameTab.socialTab, ns.LFGFrameTab.guildTab, ns.LFGFrameTab.charTab }) do
            if scTab and scTab.GetParent and scTab:GetParent() == hostFrame then
                SetMinFrameLevel(scTab, minControlLevel + 10)
            end
        end
    end
end

function UI:IsEmbeddedFor(hostFrame, tabId)
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
    return frame ~= nil and frame:IsShown() and activeTab == "alts"
end

local hiddenCharSubframes = {}
local hiddenCommunitiesChildren = {}
local hiddenWorldMapSubframes = {}

local function IsHostChromeOrTabChild(hostFrame, child)
    if not child then return true end
    if child == frame
        or child == _G.SocialCentralLFGSubPanel
        or child == hostFrame.NineSlice
        or child == hostFrame.BorderFrame
        or child == hostFrame.PortraitContainer
        or child == hostFrame.PortraitOverlay
        or child == hostFrame.TitleContainer
        or child == hostFrame.CloseButton
        or child == hostFrame.MaximizeMinimizeFrame
    then
        return true
    end
    local cName = child.GetName and child:GetName() or ""
    if cName:find("Portrait") or cName:find("SocialCentral") or cName:find("SideTab") then
        return true
    end
    local hRight = hostFrame.GetRight and hostFrame:GetRight() or nil
    local cLeft = child.GetLeft and child:GetLeft()
    local cW = (child.GetWidth and child:GetWidth()) or 0
    if hRight and cLeft and cLeft >= (hRight - 14) and cW >= 24 and cW <= 76 then
        return true
    end
    return false
end

local function HideCharacterHostSubframes(hostFrame)
    if not hostFrame then return end
    if hostFrame == _G.CharacterFrame then
        for k in pairs(hiddenCharSubframes) do
            hiddenCharSubframes[k] = nil
        end
        for _, name in ipairs({
            "PaperDollFrame",
            "PaperDollSidebarTabs",
            "CharacterFrameInset",
            "CharacterFrameInsetRight",
            "ReputationFrame",
            "TokenFrame",
        }) do
            local sub = _G[name]
            if sub and sub.IsShown and sub:IsShown() and sub.Hide then
                hiddenCharSubframes[name] = true
                pcall(sub.Hide, sub)
            end
        end
    elseif hostFrame == (_G.CommunitiesFrame or _G.GuildFrame) then
        for i = #hiddenCommunitiesChildren, 1, -1 do
            hiddenCommunitiesChildren[i] = nil
        end
        if hostFrame.GetChildren then
            for _, child in ipairs({ hostFrame:GetChildren() }) do
                if not IsHostChromeOrTabChild(hostFrame, child) and child.IsShown and child:IsShown() and child.Hide then
                    hiddenCommunitiesChildren[#hiddenCommunitiesChildren + 1] = child
                    pcall(child.Hide, child)
                end
            end
        end
    elseif hostFrame == _G.WorldMapFrame then
        for i = #hiddenWorldMapSubframes, 1, -1 do
            hiddenWorldMapSubframes[i] = nil
        end
        for _, sub in ipairs({ hostFrame.ScrollContainer, hostFrame.NavBar, _G.QuestMapFrame }) do
            if sub and sub.IsShown and sub:IsShown() and sub.Hide then
                hiddenWorldMapSubframes[#hiddenWorldMapSubframes + 1] = sub
                pcall(sub.Hide, sub)
            end
        end
    end
end

function UI:RestoreEmbeddedHostUI(hostFrame)
    if not hostFrame then return end
    if hostFrame == _G.CharacterFrame then
        local otherNativeOpen = false
        for _, checkName in ipairs({ "ReputationFrame", "TokenFrame", "PetPaperDollFrame", "SkillFrame", "PVPFrame" }) do
            local f = _G[checkName]
            if f and f.IsShown and f:IsShown() and not hiddenCharSubframes[checkName] then
                otherNativeOpen = true
                break
            end
        end
        if not otherNativeOpen then
            for name in pairs(hiddenCharSubframes) do
                local sub = _G[name]
                if sub and sub.Show then
                    pcall(sub.Show, sub)
                end
            end
        end
        for k in pairs(hiddenCharSubframes) do
            hiddenCharSubframes[k] = nil
        end
    elseif hostFrame == (_G.CommunitiesFrame or _G.GuildFrame) then
        local anyNativeShown = false
        for _, sub in ipairs({ hostFrame.Chat, hostFrame.MemberList, hostFrame.GuildBenefitsFrame, hostFrame.GuildDetailsFrame }) do
            if sub and sub.IsShown and sub:IsShown() then
                anyNativeShown = true
                break
            end
        end
        if not anyNativeShown then
            for _, sub in ipairs(hiddenCommunitiesChildren) do
                if sub and sub.Show then
                    pcall(sub.Show, sub)
                end
            end
        end
        for i = #hiddenCommunitiesChildren, 1, -1 do
            hiddenCommunitiesChildren[i] = nil
        end
    elseif hostFrame == _G.WorldMapFrame then
        for _, sub in ipairs(hiddenWorldMapSubframes) do
            if sub and sub.Show then
                pcall(sub.Show, sub)
            end
        end
        for i = #hiddenWorldMapSubframes, 1, -1 do
            hiddenWorldMapSubframes[i] = nil
        end
    end
end

function UI:CloseEmbeddedIfHost(hostFrame)
    if not frame then return end
    local matchesHost = (not hostFrame) or (embeddedState.host == hostFrame)
    if embeddedState.active and matchesHost then
        local activeHost = embeddedState.host
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
    end
end

function UI:OpenEmbedded(hostFrame, allowedTabs, defaultTab)
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat then
        ns:Print("%s", L["Unavailable during combat."])
        return false
    end
    if not frame then
        BuildMainFrame()
    end

    local targetTab = defaultTab or (allowedTabs and allowedTabs[1]) or "watchlist"
    if frame:IsShown() and embeddedState.active and embeddedState.host == hostFrame and activeTab == targetTab then
        frame:Hide()
        return false
    end

    local allowedSet = {}
    if type(allowedTabs) == "table" then
        for _, id in ipairs(allowedTabs) do
            allowedSet[id] = true
        end
    end

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
    if hostFrame and hostFrame ~= _G.ChatFrame1 then
        local hostMax = ScanEmbeddedHostContentMax(hostFrame)
        if frame:GetParent() ~= hostFrame then
            frame:SetParent(hostFrame)
        end
        local hStrata = hostFrame.GetFrameStrata and hostFrame:GetFrameStrata() or "MEDIUM"
        frame:SetFrameStrata(hStrata)

        local baseHostLvl = (hostFrame.GetFrameLevel and hostFrame:GetFrameLevel()) or 1
        if hostFrame == _G.WorldMapFrame then
            embedLvl = math.max(2600, baseHostLvl + 60, hostMax + 25)
        else
            embedLvl = math.max(520, baseHostLvl + 30, hostMax + 12)
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
        elseif hostFrame == (_G.SocialUIFrame or _G.FriendsFrame) then
            leftPad, rightPad, topPad, bottomPad = 6, 6, 58, 6
        elseif hostFrame == _G.CommunitiesFrame or hostFrame == _G.GuildFrame then
            leftPad, rightPad, topPad, bottomPad = 4, 4, 21, 4
        elseif hostFrame == _G.CharacterFrame then
            leftPad, rightPad, topPad, bottomPad = 4, 4, 21, 4
        end
        HideCharacterHostSubframes(hostFrame)
        local hw = (hostFrame.GetWidth and hostFrame:GetWidth()) or 410
        local hh = (hostFrame.GetHeight and hostFrame:GetHeight()) or 675
        frame:SetSize(math.max(260, hw - leftPad - rightPad), math.max(240, hh - topPad - bottomPad))
        frame:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", leftPad, -topPad)
        frame:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", -rightPad, bottomPad)
    elseif hostFrame == _G.ChatFrame1 then
        if frame:GetParent() ~= UIParent then
            frame:SetParent(UIParent)
        end
        local cw = math.max(390, math.min(540, (hostFrame.GetWidth and hostFrame:GetWidth()) or 430))
        local ch = math.max(360, math.min(520, (hostFrame.GetHeight and hostFrame:GetHeight()) or 380))
        frame:SetSize(cw, ch)
        frame:SetPoint("BOTTOMLEFT", hostFrame, "BOTTOMLEFT", 0, 0)
        frame:SetFrameStrata(hostFrame.GetFrameStrata and hostFrame:GetFrameStrata() or "MEDIUM")
        frame:SetFrameLevel(((hostFrame.GetFrameLevel and hostFrame:GetFrameLevel()) or 1) + 25)
    else
        RestoreStandalonePlacement()
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("HIGH")
    end

    TriggerTabRefresh(activeTab)
    ApplyTheme()
    ReflowTabStrip()
    frame:Show()
    ApplyTheme()
    UI:Refresh(true)
    MaybePromptThemePicker()
    if hostFrame and hostFrame ~= _G.ChatFrame1 and embedLvl then
        ElevateEmbeddedHostChrome(hostFrame, embedLvl + 45)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if frame and frame:IsShown() and embeddedState.active and embeddedState.host == hostFrame then
                    ApplyTheme()
                    ElevateEmbeddedHostChrome(hostFrame, embedLvl + 45)
                    ReflowTabStrip()
                    if ReflowFilterBar then ReflowFilterBar() end
                    if ReflowWatchBar then ReflowWatchBar() end
                    if ReflowClanPanel then ReflowClanPanel() end
                    if altsPanel and altsPanel:IsShown() and altsPanel.Refresh then
                        altsPanel:Refresh(false)
                    end
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
    embeddedState.active = false
    embeddedState.host = nil
    embeddedState.allowedSet = nil
    RestoreStandalonePlacement()
    if defaultTab and tabButtons[defaultTab] then
        activeTab = defaultTab
    end
    TriggerTabRefresh(activeTab)
    ReflowTabStrip()
    frame:Show()
    ApplyTheme()
    UI:Refresh(true)
    MaybePromptThemePicker()
    if ns.LFGFrameTab and ns.LFGFrameTab.SyncAllEmbeddedTabStates then
        ns.LFGFrameTab:SyncAllEmbeddedTabStates()
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
    if not frame then
        BuildMainFrame()
    end
    if tabId == "chat" and embeddedState.active and not IsTabAllowed("chat") and ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if not inCombat then
            ns.LFGFrameTab:OpenOfficialModule("chat")
            return
        end
    end
    if embeddedState.active and tabId and not IsTabAllowed(tabId) then
        embeddedState.active = false
        embeddedState.host = nil
        embeddedState.allowedSet = nil
        RestoreStandalonePlacement()
    elseif not embeddedState.active then
        RestoreStandalonePlacement()
    end
    if tabId and tabButtons[tabId] then
        activeTab = tabId
    end
    TriggerTabRefresh(activeTab)
    ReflowTabStrip()
    frame:Show()
    ApplyTheme()
    UI:Refresh(true)
    MaybePromptThemePicker()
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

for _, ev in ipairs({ "WATCHLIST_UPDATED", "SOCIAL_UPDATED", "NEARBY_UPDATED", "ALTS_UPDATED", "CLAN_UPDATED", "CLAN_DIPLOMACY_UPDATED", "CLAN_LFG_ALERT", "SPOTTER_UPDATED", "GROUP_UPDATED", "CHAT_UPDATED", "VERSION_UPDATE_FOUND" }) do
    ns:On(ev, function()
        UI:Refresh(false)
    end)
end

ns.RegisterEvent(UI, "PLAYER_REGEN_DISABLED", UpdateWhoButtons)
ns.RegisterEvent(UI, "PLAYER_REGEN_ENABLED", UpdateWhoButtons)
