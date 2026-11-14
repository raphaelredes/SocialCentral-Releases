local _, ns = ...

local L = ns.L
local Theme = ns.Theme
local Compat = ns.Compat
local Store = ns.Store

local SocialPanels = {}
ns.SocialPanels = SocialPanels

local ROLE_BADGES = {
    TANK = "|cff58a6ff[T]|r",
    HEALER = "|cff3fb950[H]|r",
    DAMAGER = "|cffff7b72[D]|r",
    NONE = "",
}

local PROF_LABELS = {
    NONE = L["None"],
    ALCHEMY = L["Alchemy"],
    BLACKSMITHING = L["Blacksmithing"],
    ENCHANTING = L["Enchanting"],
    ENGINEERING = L["Engineering"],
    HERBALISM = L["Herbalism"],
    INSCRIPTION = L["Inscription"],
    JEWELCRAFTING = L["Jewelcrafting"],
    LEATHERWORKING = L["Leatherworking"],
    MINING = L["Mining"],
    SKINNING = L["Skinning"],
    TAILORING = L["Tailoring"],
    FIRST_AID = L["First Aid"],
    COOKING = L["Cooking"],
}
SocialPanels.PROF_LABELS = PROF_LABELS

local function AddHelp(parent, anchorTo, title, whatText, howText, point, relPoint, xOff, yOff)
    if not (Theme and Theme.CreateHelpButton) then return nil end
    local h = Theme:CreateHelpButton(parent, title, whatText, howText, 18)
    h:SetPoint(point or "LEFT", anchorTo, relPoint or "RIGHT", xOff or 6, yOff or 0)
    return h
end

local metaModal, profModal, createRoomModal, roomInviteModal, tempChannelModal

function SocialPanels:OpenSocialMetaModal(displayName, rawKey)
    local key = rawKey or displayName
    if not key or key == "" then return end
    local parentFrame = ns.UI and ns.UI.GetFrame and ns.UI:GetFrame() or UIParent

    if not metaModal then
        local m = CreateFrame("Frame", "SocialCentralMetaModal", parentFrame, "BackdropTemplate")
        m:SetSize(428, 258)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(110)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
        Theme:MakeMovable(m, { key = "modal_social_meta" })
        table.insert(UISpecialFrames, "SocialCentralMetaModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -36, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        m.title = title

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            m.folderIn:ClearFocus()
            m.mainIn:ClearFocus()
            m.noteIn:ClearFocus()
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        local fLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fLbl:SetPoint("TOPLEFT", 16, -44)
        fLbl:SetPoint("TOPRIGHT", -16, -44)
        fLbl:SetJustifyH("LEFT")
        fLbl:SetWordWrap(false)
        fLbl:SetText(L["Social Folder (e.g. M+ Team, Guild Core):"])
        local fIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 24 })
        fIn:SetPoint("TOPLEFT", fLbl, "BOTTOMLEFT", 0, -4)
        fIn:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        m.folderIn = fIn

        local mainLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        mainLbl:SetPoint("TOPLEFT", 16, -94)
        mainLbl:SetPoint("TOPRIGHT", -16, -94)
        mainLbl:SetJustifyH("LEFT")
        mainLbl:SetWordWrap(false)
        mainLbl:SetText(L["Linked Main Character (optional):"])
        local mainIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 32 })
        mainIn:SetPoint("TOPLEFT", mainLbl, "BOTTOMLEFT", 0, -4)
        mainIn:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        m.mainIn = mainIn

        local noteLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        noteLbl:SetPoint("TOPLEFT", 16, -144)
        noteLbl:SetPoint("TOPRIGHT", -16, -144)
        noteLbl:SetJustifyH("LEFT")
        noteLbl:SetWordWrap(false)
        noteLbl:SetText(L["Social Note:"])
        local noteIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 60 })
        noteIn:SetPoint("TOPLEFT", noteLbl, "BOTTOMLEFT", 0, -4)
        noteIn:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        m.noteIn = noteIn

        local btnSave = Theme:CreateButton(m, 92, 24, L["Save"], "primary")
        Theme:AutoFitButton(btnSave, 86, 18, 140)
        btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnSave = btnSave

        local btnCancel = Theme:CreateButton(m, 92, 24, L["Cancel"], "default")
        Theme:AutoFitButton(btnCancel, 86, 18, 140)
        btnCancel:SetPoint("RIGHT", btnSave, "LEFT", -8, 0)
        m.btnCancel = btnCancel

        btnCancel:SetScript("OnClick", function()
            fIn:ClearFocus()
            mainIn:ClearFocus()
            noteIn:ClearFocus()
            m:Hide()
        end)
        for _, box in ipairs({ fIn, mainIn, noteIn }) do
            box:SetScript("OnEscapePressed", function() m:Hide() end)
        end

        metaModal = m
    end

    local meta = Store and Store:GetSocialMeta(key) or {}
    Theme:ApplyBackdrop(metaModal, "window")
    Theme:StyleButton(metaModal.topCloseBtn, "default")
    Theme:StyleButton(metaModal.btnSave, "primary")
    Theme:StyleButton(metaModal.btnCancel, "default")
    metaModal.title:SetText(L["Social Card: %s"]:format(displayName or key))
    metaModal.folderIn:SetText(meta and meta.folder or "")
    metaModal.mainIn:SetText(meta and meta.mainName or "")
    metaModal.noteIn:SetText(meta and meta.note or "")

    local function Commit()
        if Store and Store.SetSocialMeta then
            Store:SetSocialMeta(key, {
                folder = metaModal.folderIn:GetText() or "",
                mainName = metaModal.mainIn:GetText() or "",
                note = metaModal.noteIn:GetText() or "",
            })
        end
        metaModal.folderIn:ClearFocus()
        metaModal.mainIn:ClearFocus()
        metaModal.noteIn:ClearFocus()
        metaModal:Hide()
    end

    metaModal.btnSave:SetScript("OnClick", Commit)
    metaModal.noteIn:SetScript("OnEnterPressed", Commit)
    metaModal:Show()
    metaModal.folderIn:SetFocus()
end

function SocialPanels:OpenProfessionModal()
    local parentFrame = ns.UI and ns.UI.GetFrame and ns.UI:GetFrame() or UIParent
    local profs = ns.Clan and ns.Clan.PROFESSIONS or {}

    if not profModal then
        local m = CreateFrame("Frame", "SocialCentralProfModal", parentFrame, "BackdropTemplate")
        m:SetSize(486, 336)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(110)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
        Theme:MakeMovable(m, { key = "modal_professions" })
        table.insert(UISpecialFrames, "SocialCentralProfModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -36, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["My Clan Professions"])

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            if m.noteIn then m.noteIn:ClearFocus() end
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        local sub = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetPoint("TOPLEFT", 16, -38)
        sub:SetPoint("TOPRIGHT", -16, -38)
        sub:SetJustifyH("LEFT")
        sub:SetText(L["Pick up to 2 primary professions + a short craft/service note:"])

        m._slot = 1
        m._p1 = "NONE"
        m._p2 = "NONE"

        local s1Btn = Theme:CreateButton(m, 220, 24, "", "default")
        s1Btn:SetPoint("TOPLEFT", 16, -64)
        m.s1Btn = s1Btn

        local s2Btn = Theme:CreateButton(m, 220, 24, "", "default")
        s2Btn:SetPoint("LEFT", s1Btn, "RIGHT", 14, 0)
        m.s2Btn = s2Btn

        local function RefreshSlots()
            Theme:SetButtonActive(s1Btn, m._slot == 1, "default")
            Theme:SetButtonActive(s2Btn, m._slot == 2, "default")
            Theme:SetButtonText(s1Btn, L["Prof 1"] .. ": " .. (PROF_LABELS[m._p1 or "NONE"] or L["None"]))
            Theme:SetButtonText(s2Btn, L["Prof 2"] .. ": " .. (PROF_LABELS[m._p2 or "NONE"] or L["None"]))
        end
        m.RefreshSlots = RefreshSlots

        s1Btn:SetScript("OnClick", function() m._slot = 1; RefreshSlots() end)
        s2Btn:SetScript("OnClick", function() m._slot = 2; RefreshSlots() end)

        m._profBtns = {}
        local cols = 3
        for idx, item in ipairs(profs) do
            local pid = type(item) == "table" and item.id or item
            local r = math.floor((idx - 1) / cols)
            local c = (idx - 1) % cols
            local b = Theme:CreateButton(m, 146, 22, PROF_LABELS[pid] or pid, "default")
            b:SetPoint("TOPLEFT", 16 + c * 154, -98 - r * 26)
            b:SetScript("OnClick", function()
                if m._slot == 1 then
                    m._p1 = pid
                else
                    m._p2 = pid
                end
                RefreshSlots()
            end)
            table.insert(m._profBtns, b)
        end

        local noteLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        noteLbl:SetPoint("BOTTOMLEFT", 16, 78)
        noteLbl:SetPoint("BOTTOMRIGHT", -16, 78)
        noteLbl:SetJustifyH("LEFT")
        noteLbl:SetWordWrap(false)
        noteLbl:SetText(L["Craft Note (e.g. Flasks, Gems, Locks):"])

        local noteIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 48 })
        noteIn:SetPoint("BOTTOMLEFT", 16, 48)
        noteIn:SetPoint("BOTTOMRIGHT", -16, 48)
        m.noteIn = noteIn

        local btnSave = Theme:CreateButton(m, 96, 24, L["Save"], "primary")
        Theme:AutoFitButton(btnSave, 88, 18, 145)
        btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnSave = btnSave

        local btnCancel = Theme:CreateButton(m, 96, 24, L["Cancel"], "default")
        Theme:AutoFitButton(btnCancel, 88, 18, 145)
        btnCancel:SetPoint("RIGHT", btnSave, "LEFT", -8, 0)
        m.btnCancel = btnCancel

        btnCancel:SetScript("OnClick", function() noteIn:ClearFocus(); m:Hide() end)
        noteIn:SetScript("OnEscapePressed", function() noteIn:ClearFocus(); m:Hide() end)

        local function SaveProfs()
            if ns.Clan and ns.Clan.SetMyProfessions then
                ns.Clan:SetMyProfessions(m._p1, m._p2, noteIn:GetText() or "")
            end
            noteIn:ClearFocus()
            m:Hide()
        end
        btnSave:SetScript("OnClick", SaveProfs)
        noteIn:SetScript("OnEnterPressed", SaveProfs)

        profModal = m
    end

    local bucket = Store and Store:GetClanScopeData() or {}
    profModal._p1 = bucket.myProf1 or "NONE"
    profModal._p2 = bucket.myProf2 or "NONE"
    profModal._slot = 1
    Theme:ApplyBackdrop(profModal, "window")
    Theme:StyleButton(profModal.topCloseBtn, "default")
    Theme:StyleButton(profModal.btnSave, "primary")
    Theme:StyleButton(profModal.btnCancel, "default")
    Theme:StyleButton(profModal.s1Btn, "default")
    Theme:StyleButton(profModal.s2Btn, "default")
    for _, b in ipairs(profModal._profBtns) do
        Theme:StyleButton(b, "default")
    end
    profModal.RefreshSlots()
    profModal.noteIn:SetText(bucket.myCraftNote or "")
    profModal:Show()
end

local function OpenCreateRoomModal()
    local parentFrame = ns.UI and ns.UI.GetFrame and ns.UI:GetFrame() or UIParent
    if not createRoomModal then
        local m = CreateFrame("Frame", "SocialCentralCreateRoomModal", parentFrame, "BackdropTemplate")
        m:SetSize(420, 154)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(110)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
        Theme:MakeMovable(m, { key = "modal_create_room" })
        table.insert(UISpecialFrames, "SocialCentralCreateRoomModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -36, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["Create Private Chat Room"])

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            if m.input then m.input:ClearFocus() end
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        local lbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 16, -44)
        lbl:SetPoint("TOPRIGHT", -16, -44)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(L["Room Title (e.g. M+ Push, Officer Desk):"])

        local input = Theme:CreateEditBox(m, { height = 24, maxLetters = 32 })
        input:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -6)
        input:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        m.input = input

        local btnSave = Theme:CreateButton(m, 92, 24, L["Create"], "primary")
        Theme:AutoFitButton(btnSave, 86, 18, 140)
        btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnSave = btnSave

        local btnCancel = Theme:CreateButton(m, 92, 24, L["Cancel"], "default")
        Theme:AutoFitButton(btnCancel, 86, 18, 140)
        btnCancel:SetPoint("RIGHT", btnSave, "LEFT", -8, 0)
        m.btnCancel = btnCancel

        btnCancel:SetScript("OnClick", function() input:ClearFocus(); m:Hide() end)
        input:SetScript("OnEscapePressed", function() input:ClearFocus(); m:Hide() end)

        local function Commit()
            if ns.Chat and ns.Chat.CreateRoom then
                local created = ns.Chat:CreateRoom(input:GetText() or "")
                if created then
                    input:ClearFocus()
                    m:Hide()
                end
            end
        end
        btnSave:SetScript("OnClick", Commit)
        input:SetScript("OnEnterPressed", Commit)

        createRoomModal = m
    end

    Theme:ApplyBackdrop(createRoomModal, "window")
    Theme:StyleButton(createRoomModal.topCloseBtn, "default")
    Theme:StyleButton(createRoomModal.btnSave, "primary")
    Theme:StyleButton(createRoomModal.btnCancel, "default")
    createRoomModal.input:SetText("")
    createRoomModal:Show()
    createRoomModal.input:SetFocus()
end

local function OpenTempChannelModal()
    local parentFrame = ns.UI and ns.UI.GetFrame and ns.UI:GetFrame() or UIParent
    if not tempChannelModal then
        local m = CreateFrame("Frame", "SocialCentralTempChanModal", parentFrame, "BackdropTemplate")
        m:SetSize(442, 162)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(110)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
        Theme:MakeMovable(m, { key = "modal_temp_channel" })
        table.insert(UISpecialFrames, "SocialCentralTempChanModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -36, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["Temporary WoW Chat Channel"])

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            if m.input then m.input:ClearFocus() end
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        local lbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 16, -42)
        lbl:SetPoint("TOPRIGHT", -16, -42)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(L["Channel name (uses JoinTemporaryChannel on click):"])

        local input = Theme:CreateEditBox(m, { height = 24, maxLetters = 24 })
        input:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -6)
        input:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        m.input = input

        local btnJoin = Theme:CreateButton(m, 92, 24, L["Join"], "primary")
        Theme:AutoFitButton(btnJoin, 84, 18, 125)
        btnJoin:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnJoin = btnJoin

        local btnLeave = Theme:CreateButton(m, 92, 24, L["Leave"], "danger")
        Theme:AutoFitButton(btnLeave, 84, 18, 125)
        btnLeave:SetPoint("RIGHT", btnJoin, "LEFT", -8, 0)
        m.btnLeave = btnLeave

        local btnCancel = Theme:CreateButton(m, 92, 24, L["Cancel"], "default")
        Theme:AutoFitButton(btnCancel, 84, 18, 125)
        btnCancel:SetPoint("RIGHT", btnLeave, "LEFT", -8, 0)
        m.btnCancel = btnCancel

        btnCancel:SetScript("OnClick", function() input:ClearFocus(); m:Hide() end)
        input:SetScript("OnEscapePressed", function() input:ClearFocus(); m:Hide() end)

        btnJoin:SetScript("OnClick", function()
            if ns.Chat and ns.Chat:JoinTempWoWChannel(input:GetText() or "") then
                input:ClearFocus()
                m:Hide()
            end
        end)
        btnLeave:SetScript("OnClick", function()
            if ns.Chat then
                ns.Chat:LeaveTempWoWChannel(input:GetText() or "")
                input:ClearFocus()
                m:Hide()
            end
        end)

        tempChannelModal = m
    end

    Theme:ApplyBackdrop(tempChannelModal, "window")
    Theme:StyleButton(tempChannelModal.topCloseBtn, "default")
    Theme:StyleButton(tempChannelModal.btnJoin, "primary")
    Theme:StyleButton(tempChannelModal.btnLeave, "danger")
    Theme:StyleButton(tempChannelModal.btnCancel, "default")
    tempChannelModal.input:SetText((ns.Chat and ns.Chat.activeTempChannel) or "SocialCentral")
    tempChannelModal:Show()
    tempChannelModal.input:SetFocus()
    tempChannelModal.input:HighlightText()
end

local function OpenRoomInviteModal(roomId)
    if not roomId then return end
    local parentFrame = ns.UI and ns.UI.GetFrame and ns.UI:GetFrame() or UIParent
    if not roomInviteModal then
        local m = CreateFrame("Frame", "SocialCentralRoomInvModal", parentFrame, "BackdropTemplate")
        m:SetSize(442, 310)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(110)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
        Theme:MakeMovable(m, { key = "modal_room_invite" })
        table.insert(UISpecialFrames, "SocialCentralRoomInvModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -36, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["Invite to Private Room"])

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            if m.input then m.input:ClearFocus() end
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        local lbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 16, -42)
        lbl:SetPoint("TOPRIGHT", -16, -42)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(L["Character-Realm or click an online friend below:"])

        local btnInvite = Theme:CreateButton(m, 84, 24, L["Invite"], "primary")
        Theme:AutoFitButton(btnInvite, 80, 18, 130)
        btnInvite:SetPoint("TOPRIGHT", -16, -62)
        m.btnInvite = btnInvite

        local input = Theme:CreateEditBox(m, { height = 24, maxLetters = 48 })
        input:SetPoint("TOPLEFT", m, "TOPLEFT", 16, -62)
        input:SetPoint("RIGHT", btnInvite, "LEFT", -8, 0)
        m.input = input

        local listWrap = CreateFrame("Frame", nil, m, "BackdropTemplate")
        listWrap:SetPoint("TOPLEFT", 16, -96)
        listWrap:SetPoint("BOTTOMRIGHT", -16, 46)
        m.listWrap = listWrap

        m.scroll = Theme:CreateScrollList(listWrap, 30, function(parent, _, rowHeight)
            local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
            r:SetHeight(rowHeight)
            r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.name:SetPoint("LEFT", 8, 0)
            r.name:SetJustifyH("LEFT")
            r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.tag:SetPoint("RIGHT", -8, 0)
            r.tag:SetJustifyH("RIGHT")
            r.name:SetPoint("RIGHT", r.tag, "LEFT", -6, 0)
            r:SetScript("OnClick", function()
                if r._item and ns.Chat and m._roomId then
                    local ok = ns.Chat:InviteToRoom(m._roomId, r._item.displayName, r._item.bnetAccountID)
                    if ok then m:Hide() end
                end
            end)
            return r
        end, function(r, item, idx, pal)
            r._item = item
            Theme:ApplyBackdrop(r, (idx % 2 == 1) and "row" or "rowAlt", pal)
            local hex = Compat.ClassHex(item.classFile)
            r.name:SetText(hex .. (item.displayName or "") .. "|r")
            r.tag:SetText(item.guild and ("<" .. item.guild .. ">") or (item.bnetAccountID and "Battle.net" or ""))
            r.tag:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])
        end)
        m.scroll.container:SetAllPoints()

        local btnClose = Theme:CreateButton(m, 92, 24, L["Cancel"], "default")
        Theme:AutoFitButton(btnClose, 84, 18, 135)
        btnClose:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnClose = btnClose

        btnClose:SetScript("OnClick", function() input:ClearFocus(); m:Hide() end)
        input:SetScript("OnEscapePressed", function() input:ClearFocus(); m:Hide() end)

        local function SubmitInput()
            if ns.Chat and m._roomId then
                if ns.Chat:InviteToRoom(m._roomId, input:GetText() or "") then
                    input:ClearFocus()
                    m:Hide()
                end
            end
        end
        btnInvite:SetScript("OnClick", SubmitInput)
        input:SetScript("OnEnterPressed", SubmitInput)

        roomInviteModal = m
    end

    roomInviteModal._roomId = roomId
    Theme:ApplyBackdrop(roomInviteModal, "window")
    Theme:StyleButton(roomInviteModal.topCloseBtn, "default")
    Theme:ApplyBackdrop(roomInviteModal.listWrap, "surface")
    Theme:StyleButton(roomInviteModal.btnInvite, "primary")
    Theme:StyleButton(roomInviteModal.btnClose, "default")
    roomInviteModal.input:SetText("")

    local onlineList = ns.Social and ns.Social:GetList("all") or {}
    roomInviteModal.scroll:SetData(onlineList, L["No online friends found right now."], true)
    roomInviteModal:Show()
end

--------------------------------------------------------------------------------
-- Group & Recent Companions Tab Panel
--------------------------------------------------------------------------------
function SocialPanels:CreateGroupPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel._view = "current"

    local topCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    topCard:SetPoint("TOPLEFT", 0, 0)
    topCard:SetPoint("TOPRIGHT", 0, 0)
    topCard:SetHeight(60)
    panel.topCard = topCard

    local titleLbl = topCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleLbl:SetPoint("TOPLEFT", 10, -8)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetWordWrap(false)
    panel.titleLbl = titleLbl

    local countLbl = topCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countLbl:SetPoint("BOTTOMLEFT", 10, 8)
    countLbl:SetJustifyH("LEFT")
    countLbl:SetWordWrap(false)
    panel.countLbl = countLbl

    local helpTop = AddHelp(
        topCard,
        topCard,
        L["Help: Group & Recent Companions"],
        L["Shows live Party, Raid, and Instance members with roles, Leader badge, Ready Check state, plus Recent Companions met in the last 7 days."],
        L["Use 'Current Group' for active instance members, 'Recent' to re-whisper/invite past dungeon teammates, or Ready Check / Post in Chat when leading."],
        "TOPRIGHT",
        "TOPRIGHT",
        -8,
        -6
    )

    local btnAnnounce = Theme:CreateButton(topCard, 108, 22, L["Post in Chat"], "default")
    Theme:AutoFitButton(btnAnnounce, 96, 16, 165)
    btnAnnounce:SetPoint("RIGHT", helpTop, "LEFT", -6, 0)
    btnAnnounce:SetScript("OnClick", function()
        if ns.Group then ns.Group:OpenGroupChatAnnouncement() end
    end)

    local btnReady = Theme:CreateButton(topCard, 106, 22, L["Ready Check"], "default")
    Theme:AutoFitButton(btnReady, 92, 16, 165)
    btnReady:SetPoint("RIGHT", btnAnnounce, "LEFT", -6, 0)
    btnReady:SetScript("OnClick", function()
        if ns.Group then ns.Group:StartReadyCheck() end
    end)

    titleLbl:SetPoint("RIGHT", btnReady, "LEFT", -10, 0)

    local btnRecent = Theme:CreateButton(topCard, 128, 22, L["Recent Companions"], "default")
    Theme:AutoFitButton(btnRecent, 118, 16, 185)
    btnRecent:SetPoint("BOTTOMRIGHT", -8, 6)
    btnRecent:SetScript("OnClick", function()
        panel._view = "recent"
        panel:Refresh(true)
    end)

    local btnCurrent = Theme:CreateButton(topCard, 118, 22, L["Current Group"], "default")
    Theme:AutoFitButton(btnCurrent, 102, 16, 170)
    btnCurrent:SetPoint("RIGHT", btnRecent, "LEFT", -6, 0)
    btnCurrent:SetScript("OnClick", function()
        panel._view = "current"
        panel:Refresh(true)
    end)

    countLbl:SetPoint("RIGHT", btnCurrent, "LEFT", -10, 0)

    local listCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    listCard:SetPoint("TOPLEFT", topCard, "BOTTOMLEFT", 0, -8)
    listCard:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.listCard = listCard

    local scroll = Theme:CreateScrollList(listCard, 40, function(rowParent, _, rowHeight)
        local row = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
        row:SetHeight(rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetSize(7, 7)
        row.dot:SetPoint("LEFT", 10, 6)

        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.nameText:SetPoint("TOPLEFT", 24, -5)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)

        row.subText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.subText:SetPoint("BOTTOMLEFT", 24, 5)
        row.subText:SetJustifyH("LEFT")
        row.subText:SetWordWrap(false)

        row.btnWatch = Theme:CreateButton(row, 84, 22, "+ " .. L["Watchlist"], "default")
        Theme:AutoFitButton(row.btnWatch, 84, 16, 150)
        row.btnWatch:SetPoint("RIGHT", -8, 0)

        row.btnWhisper = Theme:CreateButton(row, 68, 22, L["Whisper"], "default")
        Theme:AutoFitButton(row.btnWhisper, 68, 16, 118)
        row.btnWhisper:SetPoint("RIGHT", row.btnWatch, "LEFT", -6, 0)

        row.btnExtra = Theme:CreateButton(row, 74, 22, L["Invite"], "default")
        Theme:AutoFitButton(row.btnExtra, 74, 16, 124)
        row.btnExtra:SetPoint("RIGHT", row.btnWhisper, "LEFT", -6, 0)

        row.nameText:SetPoint("RIGHT", row.btnExtra, "LEFT", -8, 0)
        row.subText:SetPoint("RIGHT", row.btnExtra, "LEFT", -8, 0)

        row.btnWatch:SetScript("OnClick", function()
            if row._item and ns.Watchlist then
                ns.Watchlist:Add(row._item.lookupKey or row._item.displayName)
            end
        end)
        row.btnWhisper:SetScript("OnClick", function()
            if row._item and row._item.displayName then
                if ns.Chat and ns.Chat.OpenDirectConversation then
                    ns.Chat:OpenDirectConversation({
                        targetName = row._item.lookupKey or row._item.displayName,
                        classFile = row._item.classFile,
                        autoProbe = true,
                    })
                    if ns.UI and ns.UI.OpenTab then
                        ns.UI:OpenTab("chat")
                    end
                else
                    Compat.Whisper(row._item.displayName)
                end
            end
        end)
        row.btnExtra:SetScript("OnClick", function()
            if not row._item then return end
            if row._mode == "current" then
                if row._item.isMe then
                    if ns.Group and ns.Group.LeaveGroup then ns.Group:LeaveGroup() end
                elseif row._item.unit then
                    if ns.Group then ns.Group:PromoteMember(row._item.unit) end
                end
            elseif row._item.displayName then
                Compat.Invite(row._item.displayName)
            end
        end)

        row:SetScript("OnClick", function(self, btn)
            if btn == "RightButton" and self._item and MenuUtil and MenuUtil.CreateContextMenu then
                local item = self._item
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(item.displayName or "")
                    if not (InCombatLockdown and InCombatLockdown()) and TargetByName and item.displayName then
                        root:CreateButton(L["Target Player"], function()
                            local candidates = Compat.GetForeverTargetVariants and Compat.GetForeverTargetVariants(item.displayName) or { item.displayName }
                            for _, cand in ipairs(candidates) do
                                if cand and cand ~= "" then
                                    pcall(TargetByName, cand, true)
                                    local cur = Safe.String(Safe.Call(UnitName, "target"))
                                    if cur and cur ~= "" then break end
                                end
                            end
                        end)
                    end
                    root:CreateButton(L["Whisper"], function()
                        if ns.Chat and ns.Chat.OpenDirectConversation then
                            ns.Chat:OpenDirectConversation({
                                targetName = item.lookupKey or item.displayName,
                                classFile = item.classFile,
                                autoProbe = true,
                            })
                            if ns.UI and ns.UI.OpenTab then
                                ns.UI:OpenTab("chat")
                            end
                        else
                            Compat.Whisper(item.displayName)
                        end
                    end)
                    root:CreateButton(L["WoW Whisper (/w)"], function()
                        Compat.Whisper(item.displayName)
                    end)
                    if item.isMe then
                        root:CreateButton(L["Leave Group"], function()
                            if ns.Group and ns.Group.LeaveGroup then
                                ns.Group:LeaveGroup()
                            end
                        end)
                    else
                        if panel._view == "current" then
                            local iAmLeader = UnitIsGroupLeader and ns.Safe.Value(UnitIsGroupLeader("player")) == true
                            if iAmLeader and not item.isLeader and item.unit then
                                root:CreateButton(L["Promote"], function()
                                    if ns.Group then ns.Group:PromoteMember(item.unit) end
                                end)
                            end
                        end
                        root:CreateButton(L["Invite"], function()
                            Compat.Invite(item.displayName)
                        end)
                        root:CreateButton(L["Add to Watchlist"], function()
                            if ns.Watchlist then ns.Watchlist:Add(item.lookupKey or item.displayName) end
                        end)
                        root:CreateButton(L["Edit Social Card"], function()
                            SocialPanels:OpenSocialMetaModal(item.displayName, item.lookupKey or item.displayName)
                        end)
                    end
                end)
            end
        end)

        function row:RefreshTheme()
            Theme:StyleButton(self.btnWatch, "default")
            Theme:StyleButton(self.btnWhisper, "default")
            Theme:StyleButton(self.btnExtra, "default")
        end

        return row
    end, function(row, item, idx, pal)
        row._item = item
        row._mode = panel._view
        Theme:ApplyBackdrop(row, (idx % 2 == 1) and "row" or "rowAlt", pal)
        row.subText:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])

        local hex = Compat.ClassHex(item.classFile)
        local lvl = (item.level and item.level > 0) and (" |cff9da7b5Lv." .. item.level .. "|r") or ""
        local roleTag = ROLE_BADGES[item.role or "NONE"] or ""
        local leadTag = item.isLeader and " |cffffd24d[Leader]|r" or ""
        local readyTag = ""
        if item.ready == true then
            readyTag = " |cff3fb950[OK]|r"
        elseif item.ready == false then
            readyTag = " |cffff6b6b[NO]|r"
        elseif item.inCurrentGroup then
            readyTag = " |cff3fb950[" .. L["Group"] .. "]|r"
        end
        local scTag = (not item.isMe and ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(item.lookupKey or item.displayName))
            and " |cff3fb950[SC]|r" or ""
        local meta = Store and Store:GetSocialMeta(item.lookupKey or item.displayName)
        local mainTag = (meta and meta.mainName) and (" |cff6ec1e4[" .. meta.mainName .. "]|r") or ""

        row.nameText:SetText(hex .. (item.displayName or "") .. "|r" .. lvl .. " " .. roleTag .. leadTag .. readyTag .. scTag .. mainTag)

        local subParts = {}
        if item.zone and item.zone ~= "" then table.insert(subParts, item.zone) end
        if meta and meta.folder then table.insert(subParts, "[" .. meta.folder .. "]") end
        if meta and meta.note then table.insert(subParts, meta.note) end
        if item.lastSeen then
            table.insert(subParts, Compat.FormatRelativeTime(item.lastSeen, L))
        end
        row.subText:SetText(table.concat(subParts, "  ·  "))

        if row._scTheme ~= pal.key then
            row._scTheme = pal.key
            Theme:StyleButton(row.btnWatch, "default")
            Theme:StyleButton(row.btnWhisper, "default")
            Theme:StyleButton(row.btnExtra, "default")
        end
        if panel._view == "current" then
            Theme:ApplyStatusColor(row.dot, item.online ~= false and "online" or "offline")
            local iAmLeader = UnitIsGroupLeader and ns.Safe.Value(UnitIsGroupLeader("player")) == true
            if iAmLeader and not item.isMe and not item.isLeader then
                row.btnExtra:Show()
                Theme:StyleButton(row.btnExtra, "default")
                Theme:SetButtonText(row.btnExtra, L["Promote"])
            elseif item.isMe then
                row.btnExtra:Show()
                Theme:StyleButton(row.btnExtra, "danger")
                Theme:SetButtonText(row.btnExtra, L["Leave"])
            else
                row.btnExtra:Hide()
            end
        else
            Theme:ApplyStatusColor(row.dot, item.inCurrentGroup and "online" or "nearby")
            row.btnExtra:Show()
            Theme:StyleButton(row.btnExtra, "default")
            Theme:SetButtonText(row.btnExtra, L["Invite"])
        end

        row.btnWhisper:SetShown(not item.isMe)
        row.btnWatch:SetShown(not item.isMe)

        local leftMost = (row.btnExtra:IsShown() and row.btnExtra)
            or (row.btnWhisper:IsShown() and row.btnWhisper)
            or (row.btnWatch:IsShown() and row.btnWatch)
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("TOPLEFT", 24, -5)
        row.subText:ClearAllPoints()
        row.subText:SetPoint("BOTTOMLEFT", 24, 5)
        if leftMost then
            row.nameText:SetPoint("RIGHT", leftMost, "LEFT", -8, 0)
            row.subText:SetPoint("RIGHT", leftMost, "LEFT", -8, 0)
        else
            row.nameText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            row.subText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        end
    end)
    scroll.container:SetPoint("TOPLEFT", 6, -6)
    scroll.container:SetPoint("BOTTOMRIGHT", -6, 6)

    function panel:RefreshTheme()
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(topCard, "surface", p)
        Theme:ApplyBackdrop(listCard, "surface", p)
        Theme:StyleButton(btnCurrent, "default")
        Theme:StyleButton(btnRecent, "default")
        Theme:StyleButton(btnReady, "default")
        Theme:StyleButton(btnAnnounce, "default")
        if helpTop and helpTop.RefreshTheme then helpTop:RefreshTheme() end
        if scroll then
            scroll:RefreshTheme()
            scroll:Render()
        end
    end

    function panel:Refresh(resetScroll)
        local p = Theme:GetPalette()
        self:RefreshTheme()
        Theme:SetButtonActive(btnCurrent, self._view == "current", "default")
        Theme:SetButtonActive(btnRecent, self._view == "recent", "default")

        local ch = ns.Group and ns.Group:GetChannelName()
        local counts = ns.Group and ns.Group:GetSummaryCounts() or { total = 0, TANK = 0, HEALER = 0, DAMAGER = 0 }
        if self._view == "recent" then
            local rCount = #(ns.Group and ns.Group:GetRecentCompanions() or {})
            titleLbl:SetText(L["Recent Companions"])
            countLbl:SetText(string.format("%s: %d", L["Recent Companions"], rCount))
        elseif ch then
            titleLbl:SetText(L["Active Group"] .. "  |cff3fb950[" .. ch .. "]|r")
            countLbl:SetText(string.format("%s: %d  (T:%d  H:%d  D:%d)", L["Members"], counts.total, counts.TANK, counts.HEALER, counts.DAMAGER))
        else
            titleLbl:SetText(L["Not currently in a Party/Raid/Instance group"])
            countLbl:SetText(L["Switch to 'Recent Companions' to re-contact past instance teammates."])
        end
        countLbl:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])

        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        local canLead = ch and ((UnitIsGroupLeader and ns.Safe.Value(UnitIsGroupLeader("player"))) or (UnitIsGroupAssistant and ns.Safe.Value(UnitIsGroupAssistant("player"))))
        btnReady:SetEnabled((not inCombat) and canLead == true)
        btnAnnounce:SetEnabled(ch ~= nil)

        local rows, emptyText
        if self._view == "current" then
            rows = ns.Group and ns.Group:GetMembers() or {}
            emptyText = L["Join a Party, Raid, or Instance group to track live members and roles."]
        else
            rows = ns.Group and ns.Group:GetRecentCompanions() or {}
            emptyText = L["No recent companions recorded yet."]
        end
        scroll:SetData(rows, emptyText, resetScroll)
    end

    panel:RefreshTheme()
    return panel
end

--------------------------------------------------------------------------------
-- Conversations & Private Rooms Tab Panel
--------------------------------------------------------------------------------
local newChatModal

local function OpenNewDirectChatModal()
    local parentFrame = ns.UI and ns.UI.GetFrame and ns.UI:GetFrame() or UIParent
    if not newChatModal then
        local m = CreateFrame("Frame", "SocialCentralNewChatModal", parentFrame, "BackdropTemplate")
        m:SetSize(440, 178)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(110)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
        Theme:MakeMovable(m, { key = "modal_new_chat" })
        table.insert(UISpecialFrames, "SocialCentralNewChatModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -36, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["New 1-on-1 Chat"])

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            if m.input then m.input:ClearFocus() end
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        local lbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 16, -42)
        lbl:SetPoint("TOPRIGHT", -16, -42)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(L["Character name (Name or Name-Realm):"])

        local input = Theme:CreateEditBox(m, { height = 24, maxLetters = 64 })
        input:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -6)
        input:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        m.input = input

        local targetBtn = Theme:CreateButton(m, 92, 22, L["+ Target"], "default")
        Theme:AutoFitButton(targetBtn, 76, 14, 130)
        targetBtn:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -8)
        m.targetBtn = targetBtn

        targetBtn:SetScript("OnClick", function()
            if UnitExists and UnitIsPlayer and UnitIsPlayer("target") then
                local guid = UnitGUID and UnitGUID("target")
                local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName("target", guid)
                local targetName = resolved and resolved.fullName
                if not targetName or targetName == "" then
                    local name, realm = UnitFullName and UnitFullName("target") or UnitName("target")
                    if name and not ns.Safe.IsSecret(name) then
                        if realm and realm ~= "" and not name:find("-", 1, true) then
                            name = name .. "-" .. realm
                        end
                        targetName = name
                    end
                end
                if targetName and not ns.Safe.IsSecret(targetName) then
                    input:SetText(targetName)
                end
            end
        end)

        local pickBtn = Theme:CreateButton(m, 148, 22, L["Pick Online Friend"], "default")
        Theme:AutoFitButton(pickBtn, 120, 16, 210)
        pickBtn:SetPoint("LEFT", targetBtn, "RIGHT", 6, 0)
        m.pickBtn = pickBtn

        pickBtn:SetScript("OnClick", function(selfBtn)
            if not (ns.Social and MenuUtil and MenuUtil.CreateContextMenu) then
                return
            end
            local entries = ns.Social:GetList("all") or {}
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                root:CreateTitle(L["Online Friends & Guild"])
                local added = 0
                for _, item in ipairs(entries) do
                    if added >= 18 then break end
                    local sc = (ns.Chat and ns.Chat:IsLookupKeyVerified(item.lookupKey or item.displayName)) and " [SC]" or ""
                    local lblItem = (item.displayName or "?") .. sc
                    root:CreateButton(lblItem, function()
                        if ns.Chat and ns.Chat.OpenDirectConversation then
                            ns.Chat:OpenDirectConversation({
                                targetName = item.charName or item.lookupKey or item.displayName,
                                bnetAccountID = item.bnetAccountID,
                                bnetName = item.source == "BNET" and item.displayName or nil,
                                classFile = item.classFile,
                                autoProbe = true,
                            })
                        end
                        input:ClearFocus()
                        m:Hide()
                    end)
                    added = added + 1
                end
                if added == 0 then
                    root:CreateTitle(L["No entries match your filter."])
                end
            end)
        end)

        local btnStart = Theme:CreateButton(m, 134, 24, L["Start & Verify"], "primary")
        Theme:AutoFitButton(btnStart, 110, 18, 180)
        btnStart:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnStart = btnStart

        local btnCancel = Theme:CreateButton(m, 86, 24, L["Cancel"], "default")
        Theme:AutoFitButton(btnCancel, 74, 16, 120)
        btnCancel:SetPoint("RIGHT", btnStart, "LEFT", -8, 0)
        m.btnCancel = btnCancel

        local function SubmitStart()
            local txt = Compat.CleanInput(input:GetText() or "")
            if txt and txt ~= "" and ns.Chat and ns.Chat.OpenDirectConversation then
                ns.Chat:OpenDirectConversation({
                    targetName = txt,
                    autoProbe = true,
                })
                input:ClearFocus()
                m:Hide()
            end
        end

        btnStart:SetScript("OnClick", SubmitStart)
        input:SetScript("OnEnterPressed", SubmitStart)
        btnCancel:SetScript("OnClick", function() input:ClearFocus(); m:Hide() end)
        input:SetScript("OnEscapePressed", function() input:ClearFocus(); m:Hide() end)

        newChatModal = m
    end

    Theme:ApplyBackdrop(newChatModal, "window")
    Theme:StyleButton(newChatModal.topCloseBtn, "default")
    Theme:StyleButton(newChatModal.targetBtn, "default")
    Theme:StyleButton(newChatModal.pickBtn, "default")
    Theme:StyleButton(newChatModal.btnStart, "primary")
    Theme:StyleButton(newChatModal.btnCancel, "default")
    newChatModal.input:SetText("")
    newChatModal:Show()
    newChatModal.input:SetFocus()
end

function SocialPanels:CreateChatPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel._filter = "all"

    local topBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    topBar:SetPoint("TOPLEFT", 0, 0)
    topBar:SetPoint("TOPRIGHT", 0, 0)
    topBar:SetHeight(34)
    panel.topBar = topBar

    local filterDefs = {
        { id = "all", label = L["All"], w = 48 },
        { id = "whispers", label = L["Whispers"], w = 72 },
        { id = "guild", label = L["Guild"], w = 62 },
        { id = "group", label = L["Group"], w = 62 },
        { id = "alliance", label = L["Alliance"], w = 68 },
        { id = "rooms", label = L["Rooms"], w = 62 },
        { id = "channels", label = L["Channels"], w = 72 },
    }
    local fBtns = {}
    local prevF
    local leftTotalW = 8
    for _, def in ipairs(filterDefs) do
        local b = Theme:CreateButton(topBar, def.w, 22, def.label, "default")
        Theme:AutoFitButton(b, math.min(48, def.w), 16, 110)
        if not prevF then
            b:SetPoint("TOPLEFT", topBar, "TOPLEFT", 8, -6)
        else
            b:SetPoint("LEFT", prevF, "RIGHT", 4, 0)
        end
        b:SetScript("OnClick", function()
            panel._filter = def.id
            panel:Refresh(true)
        end)
        fBtns[def.id] = b
        leftTotalW = leftTotalW + (b:GetWidth() or def.w) + 4
        prevF = b
    end

    local helpTop = AddHelp(
        topBar,
        topBar,
        L["Help: Conversations & Private Rooms"],
        L["Collects whispers, Battle.net chats, group/guild tabs, and Addon Private Chat Rooms (SCentral1) in one view without storing BattleTags or Real IDs."],
        L["Private Rooms send directly to invited friends via addon packets. Native WoW whispers/channels pre-fill Blizzard chat safely on Send/Enter."],
        "TOPRIGHT",
        "TOPRIGHT",
        -8,
        -8
    )

    local btnClear = Theme:CreateButton(topBar, 72, 22, L["Clear"], "default")
    Theme:AutoFitButton(btnClear, 60, 16, 105)
    btnClear:SetScript("OnClick", function()
        if ns.Chat then
            ns.Chat:ClearHistory(ns.Chat.activeThreadKey)
        end
    end)
    btnClear:Hide()

    local btnMarkRead = Theme:CreateButton(topBar, 82, 22, L["Mark Read"], "default")
    Theme:AutoFitButton(btnMarkRead, 72, 16, 120)
    btnMarkRead:SetScript("OnClick", function()
        if ns.Chat then
            ns.Chat:MarkAllRead()
        end
    end)
    btnMarkRead:Hide()

    local btnTemp = Theme:CreateButton(topBar, 96, 22, L["Temp Channel"], "default")
    Theme:AutoFitButton(btnTemp, 88, 16, 145)
    btnTemp:SetPoint("RIGHT", helpTop, "LEFT", -6, 0)
    btnTemp:SetScript("OnClick", OpenTempChannelModal)

    local btnNewRoom = Theme:CreateButton(topBar, 88, 22, "+ " .. L["Room"], "primary")
    Theme:AutoFitButton(btnNewRoom, 72, 16, 120)
    btnNewRoom:SetPoint("RIGHT", btnTemp, "LEFT", -4, 0)
    btnNewRoom:SetScript("OnClick", OpenCreateRoomModal)

    local btnNewChat = Theme:CreateButton(topBar, 76, 22, "+ " .. L["Chat"], "default")
    Theme:AutoFitButton(btnNewChat, 66, 16, 112)
    btnNewChat:SetPoint("RIGHT", btnNewRoom, "LEFT", -4, 0)
    btnNewChat:SetScript("OnClick", OpenNewDirectChatModal)

    local function ReflowChatTopBar()
        local w = topBar:GetWidth() or 0
        if w <= 0 then
            w = 730
        end
        local rightW = (helpTop and (helpTop:GetWidth() or 18) or 18)
            + (btnTemp:GetWidth() or 96)
            + (btnNewRoom:GetWidth() or 88)
            + (btnNewChat:GetWidth() or 76)
            + 24
        local wrap = (leftTotalW + rightW + 12) > w
        topBar:SetHeight(wrap and 60 or 34)
        if helpTop then
            helpTop:ClearAllPoints()
            helpTop:SetPoint("TOPRIGHT", topBar, "TOPRIGHT", -8, wrap and -36 or -8)
        end
    end
    topBar:SetScript("OnSizeChanged", ReflowChatTopBar)
    ReflowChatTopBar()

    -- Pending room invite banner (auto-hidden when empty)
    local inviteBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    inviteBar:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -6)
    inviteBar:SetPoint("TOPRIGHT", topBar, "BOTTOMRIGHT", 0, -6)
    inviteBar:SetHeight(30)
    inviteBar:Hide()

    local invText = inviteBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    invText:SetPoint("LEFT", 10, 0)
    invText:SetJustifyH("LEFT")
    invText:SetWordWrap(false)

    local invDecline = Theme:CreateButton(inviteBar, 74, 20, L["Decline"], "danger")
    Theme:AutoFitButton(invDecline, 66, 16, 115)
    invDecline:SetPoint("RIGHT", -8, 0)
    local invAccept = Theme:CreateButton(inviteBar, 74, 20, L["Accept"], "primary")
    Theme:AutoFitButton(invAccept, 66, 16, 115)
    invAccept:SetPoint("RIGHT", invDecline, "LEFT", -6, 0)
    invText:SetPoint("RIGHT", invAccept, "LEFT", -8, 0)

    -- Left: Threads list
    local leftCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    leftCard:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -8)
    leftCard:SetPoint("BOTTOMLEFT", 0, 0)
    leftCard:SetWidth(238)

    local threadsScroll = Theme:CreateScrollList(leftCard, 40, function(rowParent, _, rowHeight)
        local r = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
        r:SetHeight(rowHeight)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        r.title = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.title:SetPoint("TOPLEFT", 8, -5)
        r.title:SetPoint("RIGHT", -8, 0)
        r.title:SetJustifyH("LEFT")
        r.title:SetWordWrap(false)

        r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.sub:SetPoint("BOTTOMLEFT", 8, 5)
        r.sub:SetPoint("RIGHT", -8, 0)
        r.sub:SetJustifyH("LEFT")
        r.sub:SetWordWrap(false)

        r:SetScript("OnClick", function(selfBtn, mouseBtn)
            if not (r._item and ns.Chat) then return end
            if mouseBtn == "RightButton" then
                if MenuUtil and MenuUtil.CreateContextMenu then
                    local key = r._item.key
                    MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                        root:CreateTitle(r._item.title or key)
                        local isMuted = ns.Chat:IsThreadMuted(key)
                        root:CreateButton(isMuted and L["Unmute Conversation"] or L["Mute Conversation"], function()
                            ns.Chat:ToggleThreadMuted(key)
                        end)
                        root:CreateButton(L["Mark Read"], function()
                            ns.Chat:MarkThreadRead(key)
                        end)
                        root:CreateButton(L["Clear"], function()
                            ns.Chat:ClearHistory(key)
                        end)
                    end)
                else
                    ns.Chat:ToggleThreadMuted(r._item.key)
                end
                return
            end
            ns.Chat:SetActiveThread(r._item.key)
            if ns.Chat.ShouldAutoProbe and ns.Chat.ProbePeerAddon then
                if ns.Chat:ShouldAutoProbe(r._item.key) then
                    ns.Chat:ProbePeerAddon(r._item.key, false)
                end
            elseif ns.Chat.GetPeerAddonState and ns.Chat.ProbePeerAddon then
                local st = ns.Chat:GetPeerAddonState(r._item.key)
                if st and st.state == "unprobed" then
                    ns.Chat:ProbePeerAddon(r._item.key, false)
                end
            end
            panel:Refresh(false)
        end)
        return r
    end, function(r, item, idx, pal)
        r._item = item
        local isSel = ns.Chat and ns.Chat.activeThreadKey == item.key
        Theme:ApplyBackdrop(r, isSel and "surface" or ((idx % 2 == 1) and "row" or "rowAlt"), pal)

        local tagMap = {
            WHISPER = "|cffd2a8ff[W]|r ",
            BN_WHISPER = "|cff58a6ff[BN]|r ",
            ROOM = "|cff3fb950[R]|r ",
        }
        local prefix = tagMap[item.kind] or "|cff9da7b5[C]|r "
        local st = (ns.Chat and ns.Chat.GetPeerAddonState) and ns.Chat:GetPeerAddonState(item.key) or nil
        local scTag = (st and st.verified and item.kind ~= "ROOM") and "|cff3fb950[SC]|r " or ""
        local mutedTag = item.muted and (" |cffff9b3d[" .. L["Muted"] .. "]|r") or ""
        local badge = (not item.muted and item.unread and item.unread > 0) and (" |cff3fb950(" .. item.unread .. ")|r") or ""
        local hex = item.classFile and Compat.ClassHex(item.classFile) or "|cffffffff"
        r.title:SetText(prefix .. scTag .. hex .. (item.title or "") .. "|r" .. badge .. mutedTag)
        r.sub:SetText((item.preview ~= "" and item.preview) or (Compat.FormatRelativeTime(item.lastAt, L)))
        r.sub:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])
    end)
    threadsScroll.container:SetPoint("TOPLEFT", 6, -6)
    threadsScroll.container:SetPoint("BOTTOMRIGHT", -6, 6)

    -- Right: Active conversation & composer
    local rightCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 8, 0)
    rightCard:SetPoint("BOTTOMRIGHT", 0, 0)

    local rightHdr = CreateFrame("Frame", nil, rightCard)
    rightHdr:SetPoint("TOPLEFT", 8, -6)
    rightHdr:SetPoint("TOPRIGHT", -8, -6)
    rightHdr:SetHeight(24)

    local hdrTitle = rightHdr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hdrTitle:SetPoint("LEFT", 2, 0)
    hdrTitle:SetJustifyH("LEFT")
    hdrTitle:SetWordWrap(false)

    local btnLeaveRoom = Theme:CreateButton(rightHdr, 64, 20, L["Leave"], "danger")
    Theme:AutoFitButton(btnLeaveRoom, 60, 16, 110)
    btnLeaveRoom:SetPoint("RIGHT", 0, 0)
    btnLeaveRoom:Hide()

    local btnRoomInvite = Theme:CreateButton(rightHdr, 76, 20, "+ " .. L["Invite"], "default")
    Theme:AutoFitButton(btnRoomInvite, 72, 16, 120)
    btnRoomInvite:SetPoint("RIGHT", btnLeaveRoom, "LEFT", -6, 0)
    btnRoomInvite:Hide()

    local btnTargetCard = Theme:CreateButton(rightHdr, 78, 20, L["Note"], "default")
    Theme:AutoFitButton(btnTargetCard, 66, 16, 115)
    btnTargetCard:SetPoint("RIGHT", 0, 0)
    btnTargetCard:Hide()

    local btnPinLoc = Theme:CreateButton(rightHdr, 84, 20, "+ " .. L["Location"], "default")
    Theme:AutoFitButton(btnPinLoc, 72, 14, 124)
    btnPinLoc:SetPoint("RIGHT", 0, 0)
    btnPinLoc:Hide()

    local btnMuteThread = Theme:CreateButton(rightHdr, 74, 20, L["Mute"], "default")
    Theme:AutoFitButton(btnMuteThread, 64, 16, 120)
    btnMuteThread:SetPoint("RIGHT", 0, 0)
    btnMuteThread:Hide()

    hdrTitle:SetPoint("RIGHT", btnMuteThread, "LEFT", -8, 0)

    btnMuteThread:SetScript("OnClick", function()
        local k = ns.Chat and ns.Chat.activeThreadKey
        if k and ns.Chat then
            ns.Chat:ToggleThreadMuted(k)
        end
    end)

    btnPinLoc:SetScript("OnClick", function()
        local k = ns.Chat and ns.Chat.activeThreadKey
        if k and ns.Chat and ns.Chat.SendLocationPing then
            ns.Chat:SendLocationPing(k)
        end
    end)

    btnRoomInvite:SetScript("OnClick", function()
        local k = ns.Chat and ns.Chat.activeThreadKey
        if k and k:sub(1, 5) == "room:" then
            OpenRoomInviteModal(k:sub(6))
        end
    end)
    btnLeaveRoom:SetScript("OnClick", function()
        local k = ns.Chat and ns.Chat.activeThreadKey
        if k and k:sub(1, 5) == "room:" and ns.Chat then
            ns.Chat:LeaveRoom(k:sub(6))
        end
    end)
    btnTargetCard:SetScript("OnClick", function()
        local k = ns.Chat and ns.Chat.activeThreadKey
        local t = k and ns.Chat and ns.Chat.threads[k]
        if t and t.targetName then
            SocialPanels:OpenSocialMetaModal(t.targetName, t.targetName)
        end
    end)

    local peerBar = CreateFrame("Frame", nil, rightCard)
    peerBar:SetPoint("TOPLEFT", rightHdr, "BOTTOMLEFT", 0, -4)
    peerBar:SetPoint("TOPRIGHT", rightHdr, "BOTTOMRIGHT", 0, -4)
    peerBar:SetHeight(20)

    local btnVerify = Theme:CreateButton(peerBar, 106, 18, L["Verify Addon"], "default")
    Theme:AutoFitButton(btnVerify, 88, 14, 150)
    btnVerify:SetPoint("RIGHT", 0, 0)
    btnVerify:SetScript("OnClick", function()
        local k = ns.Chat and ns.Chat.activeThreadKey
        if k and ns.Chat and ns.Chat.ProbePeerAddon then
            ns.Chat:ProbePeerAddon(k, true)
        end
    end)
    btnVerify:Hide()

    local peerStatusText = peerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    peerStatusText:SetPoint("LEFT", 2, 0)
    peerStatusText:SetPoint("RIGHT", btnVerify, "LEFT", -6, 0)
    peerStatusText:SetJustifyH("LEFT")
    peerStatusText:SetWordWrap(false)

    local msgFrame = CreateFrame("ScrollingMessageFrame", nil, rightCard)
    msgFrame:SetPoint("TOPLEFT", 10, -56)
    msgFrame:SetPoint("BOTTOMRIGHT", -10, 40)
    msgFrame:SetFontObject(ChatFontNormal)
    msgFrame:SetJustifyH("LEFT")
    msgFrame:SetFading(false)
    msgFrame:SetMaxLines(120)
    if msgFrame.SetIndentedWordWrap then
        msgFrame:SetIndentedWordWrap(true)
    end
    if msgFrame.SetInsertMode then
        msgFrame:SetInsertMode("BOTTOM")
    end
    msgFrame:EnableMouseWheel(true)
    msgFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 and self.ScrollUp then
            self:ScrollUp()
        elseif delta < 0 and self.ScrollDown then
            self:ScrollDown()
        end
    end)

    local composer = CreateFrame("Frame", nil, rightCard)
    composer:SetPoint("BOTTOMLEFT", 8, 6)
    composer:SetPoint("BOTTOMRIGHT", -8, 6)
    composer:SetHeight(26)

    local helpComposer = AddHelp(
        composer,
        composer,
        L["Help: Safe Chat Composer"],
        L["In Addon Private Rooms and verified 1-on-1 SocialCentral chats, messages send directly inside the addon via SCentral1 packets."],
        L["Type your message and press Enter. Location share & delivery status work whenever both players run SocialCentral."],
        "RIGHT",
        "RIGHT",
        0,
        0
    )

    local btnSend = Theme:CreateButton(composer, 92, 24, L["Send"], "primary")
    Theme:AutoFitButton(btnSend, 74, 18, 125)
    btnSend:SetPoint("RIGHT", helpComposer, "LEFT", -6, 0)

    local replyInput = Theme:CreateEditBox(composer, {
        height = 24,
        maxLetters = 200,
        placeholder = L["Select a conversation to reply..."],
    })
    replyInput:SetPoint("LEFT", 0, 0)
    replyInput:SetPoint("RIGHT", btnSend, "LEFT", -8, 0)

    local function SubmitReply()
        if not (ns.Chat and ns.Chat.activeThreadKey) then return end
        local txt = replyInput:GetText() or ""
        if ns.Chat:SendOrOpenReply(ns.Chat.activeThreadKey, txt) then
            replyInput:SetText("")
        end
    end
    btnSend:SetScript("OnClick", SubmitReply)
    replyInput:SetScript("OnEnterPressed", SubmitReply)
    replyInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local officialBar = CreateFrame("Frame", nil, rightCard)
    officialBar:SetPoint("BOTTOMLEFT", 8, 6)
    officialBar:SetPoint("BOTTOMRIGHT", -8, 6)
    officialBar:SetHeight(26)
    officialBar:Hide()

    local helpOfficial = AddHelp(
        officialBar,
        officialBar,
        L["Help: Official Chat Destination"],
        L["Per Blizzard addon rules, WoW channels and players without SocialCentral cannot receive addon-only chat packets."],
        L["Click the pre-configured destination button to open WoW's official chat targeting that exact destination, or click 'Verify Addon' once your peer installs SocialCentral."],
        "RIGHT",
        "RIGHT",
        0,
        0
    )

    local btnOfficialDest = Theme:CreateButton(officialBar, 150, 24, L["Open Chat"], "primary")
    Theme:AutoFitButton(btnOfficialDest, 110, 18, 250)
    btnOfficialDest:SetPoint("RIGHT", helpOfficial, "LEFT", -6, 0)
    btnOfficialDest:SetScript("OnClick", function()
        local k = ns.Chat and ns.Chat.activeThreadKey
        if not (k and ns.Chat) then return end
        if ns.Chat.VerifyBeforeOfficialSend then
            ns.Chat:VerifyBeforeOfficialSend(k)
        elseif ns.Chat.OpenOfficialChatForThread then
            ns.Chat:OpenOfficialChatForThread(k)
        end
    end)

    local officialHint = officialBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    officialHint:SetPoint("LEFT", 2, 0)
    officialHint:SetPoint("RIGHT", btnOfficialDest, "LEFT", -8, 0)
    officialHint:SetJustifyH("LEFT")
    officialHint:SetWordWrap(false)

    function panel:RefreshTheme()
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(topBar, "surface", p)
        Theme:ApplyBackdrop(inviteBar, "surface", p)
        Theme:ApplyBackdrop(leftCard, "surface", p)
        Theme:ApplyBackdrop(rightCard, "surface", p)
        for _, b in pairs(fBtns) do Theme:StyleButton(b, "default") end
        Theme:StyleButton(btnNewChat, "default")
        Theme:StyleButton(btnNewRoom, "primary")
        Theme:StyleButton(btnTemp, "default")
        Theme:StyleButton(btnMarkRead, "default")
        Theme:StyleButton(btnClear, "default")
        Theme:StyleButton(invAccept, "primary")
        Theme:StyleButton(invDecline, "danger")
        Theme:StyleButton(btnRoomInvite, "default")
        Theme:StyleButton(btnLeaveRoom, "danger")
        Theme:StyleButton(btnTargetCard, "default")
        Theme:StyleButton(btnPinLoc, "default")
        Theme:StyleButton(btnMuteThread, "default")
        Theme:StyleButton(btnVerify, "default")
        Theme:StyleButton(btnSend, "primary")
        Theme:StyleButton(btnOfficialDest, "primary")
        if helpTop and helpTop.RefreshTheme then helpTop:RefreshTheme() end
        if helpComposer and helpComposer.RefreshTheme then helpComposer:RefreshTheme() end
        if helpOfficial and helpOfficial.RefreshTheme then helpOfficial:RefreshTheme() end
        if threadsScroll then
            threadsScroll:RefreshTheme()
            threadsScroll:Render()
        end
    end

    local function UpdateSplitWidths()
        ReflowChatTopBar()
        local pw = panel:GetWidth() or 730
        if pw <= 0 then pw = 730 end
        local leftW = math.max(205, math.min(288, math.floor(pw * 0.31)))
        leftCard:SetWidth(leftW)
    end
    panel:SetScript("OnSizeChanged", UpdateSplitWidths)

    function panel:Refresh(resetScroll)
        local p = Theme:GetPalette()
        self:RefreshTheme()
        UpdateSplitWidths()
        for id, b in pairs(fBtns) do
            Theme:SetButtonActive(b, self._filter == id, "default")
        end

        local pending = ns.Chat and ns.Chat:GetPendingRoomInvites() or {}
        leftCard:ClearAllPoints()
        if #pending > 0 then
            local inv = pending[1]
            invText:SetText(string.format(L["Invite to room '%s' from %s"], inv.title or inv.id, inv.host or "?"))
            invAccept:SetScript("OnClick", function()
                if ns.Chat then ns.Chat:AcceptRoomInvite(inv.id) end
            end)
            invDecline:SetScript("OnClick", function()
                if ns.Chat then ns.Chat:DeclineRoomInvite(inv.id) end
            end)
            inviteBar:Show()
            leftCard:SetPoint("TOPLEFT", inviteBar, "BOTTOMLEFT", 0, -6)
        else
            inviteBar:Hide()
            leftCard:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -8)
        end
        leftCard:SetPoint("BOTTOMLEFT", 0, 0)

        rightCard:ClearAllPoints()
        rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 8, 0)
        rightCard:SetPoint("BOTTOMRIGHT", 0, 0)

        local threads = ns.Chat and ns.Chat:GetThreadsList(self._filter) or {}
        if ns.Chat and (not ns.Chat.activeThreadKey or not ns.Chat.threads[ns.Chat.activeThreadKey]) and #threads > 0 then
            ns.Chat:SetActiveThread(threads[1].key)
        end
        threadsScroll:SetData(threads, L["No conversations yet. Whispers, group chats, and Private Rooms appear here."], resetScroll)

        local activeKey = ns.Chat and ns.Chat.activeThreadKey
        local active = activeKey and ns.Chat.threads[activeKey]
        msgFrame:Clear()

        if active then
            local isRoom = active.kind == "ROOM"
            local isDirect = (active.kind == "WHISPER" or active.kind == "BN_WHISPER")
            local pState = (ns.Chat and ns.Chat.GetPeerAddonState) and ns.Chat:GetPeerAddonState(activeKey) or { state = "none", verified = isRoom }
            local isMuted = ns.Chat and ns.Chat:IsThreadMuted(activeKey)
            local room = isRoom and ns.Chat:GetRoom(active.roomId)
            local memberCount = 0
            if room and room.members then
                for _ in pairs(room.members) do memberCount = memberCount + 1 end
            end
            hdrTitle:SetText((active.title or "") .. (isRoom and ("  |cff3fb950[" .. memberCount .. "]|r") or ""))

            btnRoomInvite:SetShown(isRoom)
            btnLeaveRoom:SetShown(isRoom)
            btnTargetCard:SetShown(active.kind == "WHISPER" and active.targetName ~= nil)
            btnPinLoc:SetShown(not isRoom and isDirect and pState.verified == true)
            btnMuteThread:Show()
            Theme:SetButtonText(btnMuteThread, isMuted and L["Muted"] or L["Mute"])
            Theme:SetButtonActive(btnMuteThread, isMuted, "default")

            local orderedRight = {}
            if btnLeaveRoom:IsShown() then table.insert(orderedRight, btnLeaveRoom) end
            if btnRoomInvite:IsShown() then table.insert(orderedRight, btnRoomInvite) end
            if btnTargetCard:IsShown() then table.insert(orderedRight, btnTargetCard) end
            if btnPinLoc:IsShown() then table.insert(orderedRight, btnPinLoc) end
            if btnMuteThread:IsShown() then table.insert(orderedRight, btnMuteThread) end
            local prevR
            for _, rb in ipairs(orderedRight) do
                rb:ClearAllPoints()
                if not prevR then
                    rb:SetPoint("RIGHT", rightHdr, "RIGHT", 0, 0)
                else
                    rb:SetPoint("RIGHT", prevR, "LEFT", -6, 0)
                end
                prevR = rb
            end
            hdrTitle:ClearAllPoints()
            hdrTitle:SetPoint("LEFT", 2, 0)
            if prevR then
                hdrTitle:SetPoint("RIGHT", prevR, "LEFT", -8, 0)
            else
                hdrTitle:SetPoint("RIGHT", rightHdr, "RIGHT", -4, 0)
            end

            -- Peer verification bar
            local showVerifyBtn = isDirect and (pState.state == "unprobed" or pState.state == "unverified" or pState.state == "checking")
            btnVerify:SetShown(showVerifyBtn)
            if showVerifyBtn then
                if pState.state == "checking" then
                    Theme:SetButtonText(btnVerify, L["Checking..."])
                    btnVerify:SetEnabled(false)
                else
                    Theme:SetButtonText(btnVerify, L["Verify Addon"])
                    btnVerify:SetEnabled(true)
                end
            end
            peerStatusText:ClearAllPoints()
            peerStatusText:SetPoint("LEFT", 2, 0)
            peerStatusText:SetPoint("RIGHT", showVerifyBtn and btnVerify or peerBar, showVerifyBtn and "LEFT" or "RIGHT", showVerifyBtn and -6 or -2, 0)
            peerStatusText:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])

            if isRoom then
                peerStatusText:SetText("|cff3fb950[" .. L["Addon Private Room"] .. "]|r  " .. string.format(L["%d members"], memberCount))
            elseif activeKey == "ch:alliance" or pState.state == "alliance" then
                local allCfg = ns.Clan and ns.Clan.GetAllianceConfig and ns.Clan:GetAllianceConfig() or {}
                local allName = (allCfg.name and allCfg.name ~= "") and allCfg.name or L["Cross-Guild Alliance"]
                peerStatusText:SetText("|cff3fb950[" .. L["Alliance Chat"] .. "]|r  " .. allName)
            elseif pState.verified then
                local verTag = pState.version and ("v" .. pState.version) or "OK"
                peerStatusText:SetText("|cff3fb950[SocialCentral " .. verTag .. "]|r  " .. L["Both players verified — in-addon direct chat active"])
            elseif pState.state == "checking" then
                peerStatusText:SetText("|cffffd24d[" .. L["Checking SocialCentral..."] .. "]|r")
            elseif pState.state == "disabled" then
                peerStatusText:SetText("|cffff9b3d[" .. L["In-addon direct chat disabled in Settings"] .. "]|r")
            elseif pState.state == "offline" then
                local hint = pState.knownAddon and L["Offline (used SocialCentral before)"] or L["Offline or out of addon range"]
                peerStatusText:SetText("|cff9da7b5[" .. hint .. "]|r")
            elseif pState.state == "channel" then
                peerStatusText:SetText("|cff58a6ff[" .. L["Official WoW Channel"] .. "]|r  " .. (pState.slash or ""))
            elseif pState.state == "unverified" then
                peerStatusText:SetText("|cff9da7b5[" .. L["SocialCentral not detected on peer"] .. "]|r")
            else
                peerStatusText:SetText("|cff9da7b5[" .. L["Addon status not checked yet"] .. "]|r")
            end

            -- Dual composer vs official-destination bar
            local isAlliance = (activeKey == "ch:alliance")
            if isRoom or pState.verified or isAlliance then
                officialBar:Hide()
                composer:Show()
                if ns.Chat and ns.Chat.focusInputPending then
                    ns.Chat.focusInputPending = nil
                    if replyInput and replyInput.SetFocus then
                        replyInput:SetFocus()
                    end
                end
                Theme:SetButtonText(btnSend, L["Send"])
                btnSend:SetEnabled(true)
                if replyInput.SetPlaceholder then
                    replyInput:SetPlaceholder(isAlliance
                        and L["Type in-addon alliance message and press Enter..."]
                        or (isRoom and L["Type message to Private Room and press Enter..."]
                        or L["Type in-addon direct message and press Enter..."]))
                end
            else
                replyInput:ClearFocus()
                composer:Hide()
                officialBar:Show()
                local destInfo = (ns.Chat and ns.Chat.GetOfficialDestinationInfo) and ns.Chat:GetOfficialDestinationInfo(activeKey)
                local barW = officialBar:GetWidth() or 0
                if barW <= 200 then barW = 470 end
                local maxBtnW = math.max(120, math.min(270, math.floor(barW * 0.56)))
                local pendingOpen = ns.Chat and ns.Chat.pendingOfficialOpen and ns.Chat.pendingOfficialOpen[activeKey]
                local btnLabel = (destInfo and destInfo.buttonText) or L["Open Chat"]
                if pState.state == "checking" and pendingOpen then
                    btnLabel = L["Verifying addon... (click for /w)"]
                end
                Theme:SetButtonText(btnOfficialDest, btnLabel)
                Theme:AutoFitButton(btnOfficialDest, 110, 18, maxBtnW)
                btnOfficialDest:SetEnabled(destInfo ~= nil)
                officialHint:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
                if pState.state == "channel" then
                    officialHint:SetText(L["Protected WoW channel — click button to write in chat:"])
                elseif pState.state == "disabled" then
                    officialHint:SetText(L["Enable 'Addon Direct Chat' in Settings or send via WoW:"])
                elseif pState.state == "checking" then
                    officialHint:SetText(L["Verifying addon... or send right away via WoW:"])
                elseif pState.state == "offline" then
                    officialHint:SetText(L["Player offline/unavailable for addon chat:"])
                elseif pState.state == "unverified" then
                    officialHint:SetText(L["Requires SocialCentral on both sides. Send via WoW:"])
                else
                    officialHint:SetText(L["Click 'Verify Addon' for in-addon chat, or send via WoW:"])
                end
            end

            local lines = active.messages or {}
            if #lines == 0 then
                msgFrame:AddMessage(L["No messages yet."], p.textMuted[1], p.textMuted[2], p.textMuted[3])
            else
                for _, entry in ipairs(lines) do
                    local ts = entry.ts and entry.ts > 0 and date("|cff9da7b5[%H:%M]|r ", entry.ts) or ""
                    local addonTag = (entry.viaAddon and not isRoom) and "|cff3fb950[SC]|r " or ""
                    local tick = ""
                    if not entry.incoming and entry.viaAddon and not isRoom then
                        if entry.deliveryState == "delivered" then
                            tick = " |cff3fb950[" .. L["ok"] .. "]|r"
                        else
                            tick = " |cff9da7b5[" .. L["sent"] .. "]|r"
                        end
                    end
                    local hex = entry.classFile and Compat.ClassHex(entry.classFile) or (entry.incoming and "|cffd2a8ff" or "|cff58a6ff")
                    msgFrame:AddMessage(ts .. addonTag .. hex .. (entry.sender or "") .. "|r: " .. (entry.text or "") .. tick)
                end
            end
            if msgFrame.ScrollToBottom then
                msgFrame:ScrollToBottom()
            end
        else
            hdrTitle:SetText(L["Select a conversation or create a Private Room"])
            peerStatusText:SetText("")
            btnVerify:Hide()
            btnRoomInvite:Hide()
            btnLeaveRoom:Hide()
            btnTargetCard:Hide()
            btnPinLoc:Hide()
            btnMuteThread:Hide()
            hdrTitle:ClearAllPoints()
            hdrTitle:SetPoint("LEFT", 2, 0)
            hdrTitle:SetPoint("RIGHT", rightHdr, "RIGHT", -4, 0)
            officialBar:Hide()
            composer:Show()
            btnSend:SetEnabled(false)
            if replyInput.SetPlaceholder then
                replyInput:SetPlaceholder(L["Select a conversation to reply..."])
            end
            msgFrame:AddMessage(L["Use '+ Chat' for 1-on-1 verified addon chat or '+ Room' for group rooms."], p.textMuted[1], p.textMuted[2], p.textMuted[3])
        end
    end

    panel:RefreshTheme()
    return panel
end

function SocialPanels:CreateBuffsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel._view = "all"

    local topCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    topCard:SetPoint("TOPLEFT", 0, 0)
    topCard:SetPoint("TOPRIGHT", 0, 0)
    topCard:SetHeight(64)
    panel.topCard = topCard

    local titleLbl = topCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleLbl:SetPoint("TOPLEFT", 10, -8)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetWordWrap(false)
    titleLbl:SetText(L["World Buffs (Classic & Forever)"])
    panel.titleLbl = titleLbl

    local countLbl = topCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countLbl:SetPoint("BOTTOMLEFT", 10, 8)
    countLbl:SetJustifyH("LEFT")
    countLbl:SetWordWrap(false)
    panel.countLbl = countLbl

    local helpTop = AddHelp(
        topCard,
        topCard,
        L["Help: World Buffs"],
        L["Tracks active Classic World Buffs, detects city drop announcements in real time, and lets you report your current buffs to party, raid, or guild."],
        L["Click 'Post in Chat' to pre-fill your buffs into chat, or browse the list to check sources, drop timers, and WoW Forever raid-suppression rules."],
        "TOPRIGHT",
        "TOPRIGHT",
        -8,
        -6
    )

    local btnAnnounce = Theme:CreateButton(topCard, 114, 22, L["Post in Chat"], "default")
    Theme:AutoFitButton(btnAnnounce, 102, 16, 160)
    btnAnnounce:SetPoint("RIGHT", helpTop, "LEFT", -6, 0)
    btnAnnounce:SetScript("OnClick", function()
        if ns.WorldBuffs then
            ns.WorldBuffs:OpenChatAnnouncement()
        end
    end)
    panel.btnAnnounce = btnAnnounce

    local btnHistory = Theme:CreateButton(topCard, 104, 22, L["Drop History"], "default")
    Theme:AutoFitButton(btnHistory, 94, 14, 150)
    btnHistory:SetPoint("BOTTOMRIGHT", -8, 6)
    btnHistory:SetScript("OnClick", function()
        panel._view = "history"
        panel:Refresh(true)
    end)
    panel.btnHistory = btnHistory

    local btnActive = Theme:CreateButton(topCard, 90, 22, L["My Buffs"], "default")
    Theme:AutoFitButton(btnActive, 80, 14, 130)
    btnActive:SetPoint("RIGHT", btnHistory, "LEFT", -6, 0)
    btnActive:SetScript("OnClick", function()
        panel._view = "active"
        panel:Refresh(true)
    end)
    panel.btnActive = btnActive

    local btnAll = Theme:CreateButton(topCard, 84, 22, L["All Buffs"], "default")
    Theme:AutoFitButton(btnAll, 74, 14, 120)
    btnAll:SetPoint("RIGHT", btnActive, "LEFT", -6, 0)
    btnAll:SetScript("OnClick", function()
        panel._view = "all"
        panel:Refresh(true)
    end)
    panel.btnAll = btnAll

    titleLbl:SetPoint("RIGHT", btnAnnounce, "LEFT", -10, 0)
    countLbl:SetPoint("RIGHT", btnAll, "LEFT", -10, 0)

    local dropBanner = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    dropBanner:SetPoint("TOPLEFT", topCard, "BOTTOMLEFT", 0, -4)
    dropBanner:SetPoint("TOPRIGHT", topCard, "BOTTOMRIGHT", 0, -4)
    dropBanner:SetHeight(24)
    dropBanner:Hide()
    panel.dropBanner = dropBanner

    local bannerText = dropBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bannerText:SetAllPoints()
    bannerText:SetJustifyH("CENTER")
    dropBanner.text = bannerText

    local listCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    listCard:SetPoint("TOPLEFT", topCard, "BOTTOMLEFT", 0, -8)
    listCard:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.listCard = listCard

    local scroll = Theme:CreateScrollList(listCard, 52, function(rowParent, _, rowHeight)
        local row = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
        row:SetHeight(rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(36, 36)
        row.icon:SetPoint("LEFT", 8, 0)

        row.btnReport = Theme:CreateButton(row, 84, 22, L["Report"], "default")
        Theme:AutoFitButton(row.btnReport, 74, 14, 120)
        row.btnReport:SetPoint("RIGHT", -8, 0)

        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
        row.title:SetPoint("RIGHT", row.btnReport, "LEFT", -8, 0)
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)

        row.effect = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.effect:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
        row.effect:SetPoint("RIGHT", row.btnReport, "LEFT", -8, 0)
        row.effect:SetJustifyH("LEFT")
        row.effect:SetWordWrap(false)

        row.source = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.source:SetPoint("TOPLEFT", row.effect, "BOTTOMLEFT", 0, -2)
        row.source:SetPoint("RIGHT", row.btnReport, "LEFT", -8, 0)
        row.source:SetJustifyH("LEFT")
        row.source:SetWordWrap(false)

        row.btnReport:SetScript("OnClick", function()
            if row._item and row._item.def and ns.WorldBuffs then
                ns.WorldBuffs:OpenIndividualBuffAnnouncement(row._item.def)
            end
        end)

        row:SetScript("OnClick", function(self, btn)
            if btn == "RightButton" and self._item and self._item.def and MenuUtil and MenuUtil.CreateContextMenu then
                local item = self._item
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(item.name or item.def.name)
                    root:CreateButton(L["Report"], function()
                        if ns.WorldBuffs then
                            ns.WorldBuffs:OpenIndividualBuffAnnouncement(item.def)
                        end
                    end)
                end)
            end
        end)

        function row:RefreshTheme()
            Theme:StyleButton(self.btnReport, "default")
        end

        return row
    end, function(row, item, idx, pal)
        row._item = item
        Theme:ApplyBackdrop(row, (idx % 2 == 1) and "row" or "rowAlt", pal)

        local texture = item.icon or (item.def and item.def.icon) or 132333
        row.icon:SetTexture(texture)

        local isActive = item.isActive
        local remStr = item.remaining and ns.WorldBuffs and ns.WorldBuffs:FormatDuration(item.remaining) or ""

        if isActive then
            local activeBadge = " |cff3fb950[" .. L["Active"] .. (remStr ~= "" and (" - " .. remStr) or "") .. "]|r"
            row.title:SetText("|cffffd200" .. item.name .. "|r" .. activeBadge)
            row.btnReport:Show()
            Theme:SetButtonText(row.btnReport, L["Report"])
        else
            local inactiveBadge = " |cff8b949e[" .. L["Inactive"] .. "]|r"
            row.title:SetText("|cffffffff" .. item.name .. "|r" .. inactiveBadge)
            row.btnReport:Hide()
        end

        row.effect:SetText(item.effect or (item.def and item.def.effect) or "")
        row.effect:SetTextColor(pal.text[1], pal.text[2], pal.text[3])

        local lastDrop = ns.WorldBuffs and ns.WorldBuffs:GetLastDropTime(item.id)
        local cdStatus = ns.WorldBuffs and ns.WorldBuffs:GetDropCooldownStatus(item.def or item)
        local dropNote = ""
        if cdStatus then
            if cdStatus.status == "COOLDOWN" then
                dropNote = "|cffff9b3d[" .. cdStatus.text .. "]|r"
                if lastDrop and lastDrop > 0 then
                    dropNote = dropNote .. "  ·  |cff8b949e" .. L["Last drop detected: %s"]:format(Compat.FormatRelativeTime(lastDrop, L)) .. "|r"
                end
            elseif cdStatus.status == "READY" then
                dropNote = "|cff3fb950[" .. cdStatus.text .. "]|r"
                if lastDrop and lastDrop > 0 then
                    dropNote = dropNote .. "  ·  |cff8b949e" .. L["Last drop detected: %s"]:format(Compat.FormatRelativeTime(lastDrop, L)) .. "|r"
                end
            elseif lastDrop and lastDrop > 0 then
                dropNote = L["Last drop detected: %s"]:format(Compat.FormatRelativeTime(lastDrop, L))
            end
        elseif lastDrop and lastDrop > 0 then
            dropNote = L["Last drop detected: %s"]:format(Compat.FormatRelativeTime(lastDrop, L))
        end

        local sourceInfo = (item.foreverStatus or (item.def and item.def.foreverStatus) or "")
        local locInfo = (item.source or (item.def and item.def.source) or "")
        local fullSource = sourceInfo
        if locInfo ~= "" then
            fullSource = fullSource .. "  ·  " .. locInfo
        end
        if dropNote ~= "" then
            fullSource = fullSource .. "  ·  " .. dropNote
        end

        row.source:SetText(fullSource)
        row.source:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])

        if row._scTheme ~= pal.key then
            row._scTheme = pal.key
            Theme:StyleButton(row.btnReport, "default")
        end
    end)
    panel.scroll = scroll

    function panel:RefreshTheme()
        local pal = Theme:GetPalette()
        Theme:ApplyBackdrop(topCard, "header", pal)
        Theme:ApplyBackdrop(listCard, "inset", pal)
        Theme:ApplyBackdrop(dropBanner, "surface", pal)
        Theme:StyleButton(btnAnnounce, "default")
        Theme:StyleButton(btnAll, panel._view == "all" and "active" or "default")
        Theme:StyleButton(btnActive, panel._view == "active" and "active" or "default")
        Theme:StyleButton(btnHistory, panel._view == "history" and "active" or "default")
        scroll:Render()
    end

    function panel:Refresh(resetScroll)
        local now = GetTime and GetTime() or 0
        local inc = ns.WorldBuffs and ns.WorldBuffs.incomingDrop
        if inc and inc.dropAt and inc.dropAt > now then
            local left = math.max(1, math.ceil(inc.dropAt - now))
            bannerText:SetText(L["[World Buff Alert] %s will drop in ~%ds!"]:format(inc.def.name, left))
            dropBanner:Show()
            listCard:ClearAllPoints()
            listCard:SetPoint("TOPLEFT", dropBanner, "BOTTOMLEFT", 0, -4)
            listCard:SetPoint("BOTTOMRIGHT", 0, 0)
        else
            dropBanner:Hide()
            listCard:ClearAllPoints()
            listCard:SetPoint("TOPLEFT", topCard, "BOTTOMLEFT", 0, -8)
            listCard:SetPoint("BOTTOMRIGHT", 0, 0)
        end

        local allDefs = ns.WorldBuffs and ns.WorldBuffs:GetDefinitions() or {}
        local activeList = ns.WorldBuffs and ns.WorldBuffs:GetActiveBuffs() or {}
        local activeMap = {}
        for _, act in ipairs(activeList) do
            if act.def and act.def.id then
                activeMap[act.def.id] = act
            end
        end

        countLbl:SetText(L["%d / %d Active World Buffs · WoW Forever: Open World & Dungeons only"]:format(#activeList, #allDefs))

        local displayItems = {}
        if panel._view == "active" then
            for _, act in ipairs(activeList) do
                table.insert(displayItems, {
                    id = act.def.id,
                    name = act.name,
                    icon = act.icon,
                    effect = act.def.effect,
                    source = act.def.source,
                    foreverStatus = act.def.foreverStatus,
                    isActive = true,
                    remaining = act.remaining,
                    def = act.def,
                })
            end
        elseif panel._view == "history" then
            for _, def in ipairs(allDefs) do
                local act = activeMap[def.id]
                local lastDrop = ns.WorldBuffs and ns.WorldBuffs:GetLastDropTime(def.id) or 0
                table.insert(displayItems, {
                    id = def.id,
                    name = def.name,
                    icon = def.icon,
                    effect = def.effect,
                    source = def.source,
                    foreverStatus = def.foreverStatus,
                    isActive = act ~= nil,
                    remaining = act and act.remaining or nil,
                    lastDrop = lastDrop,
                    def = def,
                })
            end
            table.sort(displayItems, function(a, b)
                return (a.lastDrop or 0) > (b.lastDrop or 0)
            end)
        else
            for _, def in ipairs(allDefs) do
                local act = activeMap[def.id]
                table.insert(displayItems, {
                    id = def.id,
                    name = def.name,
                    icon = def.icon,
                    effect = def.effect,
                    source = def.source,
                    foreverStatus = def.foreverStatus,
                    isActive = act ~= nil,
                    remaining = act and act.remaining or nil,
                    def = def,
                })
            end
        end

        local emptyText = (panel._view == "active") and L["No active world buffs."] or L["No drop detected yet this session"]
        scroll:SetData(displayItems, emptyText, resetScroll)
        self:RefreshTheme()
    end

    if ns.On then
        ns:On("WORLD_BUFFS_UPDATED", function()
            if panel:IsShown() then
                panel:Refresh(false)
            end
        end)
    end

    panel:RefreshTheme()
    return panel
end
