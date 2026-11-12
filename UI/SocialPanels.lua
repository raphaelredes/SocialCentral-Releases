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
        m:SetSize(370, 248)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:EnableMouse(true)
        table.insert(UISpecialFrames, "SocialCentralMetaModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        m.title = title

        local fLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fLbl:SetPoint("TOPLEFT", 16, -44)
        fLbl:SetText(L["Social Folder (e.g. M+ Team, Guild Core):"])
        local fIn = CreateFrame("EditBox", nil, m, "InputBoxTemplate")
        fIn:SetSize(330, 22)
        fIn:SetPoint("TOPLEFT", fLbl, "BOTTOMLEFT", 4, -4)
        fIn:SetAutoFocus(false)
        fIn:SetMaxLetters(24)
        m.folderIn = fIn

        local mainLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        mainLbl:SetPoint("TOPLEFT", 16, -94)
        mainLbl:SetText(L["Linked Main Character (optional):"])
        local mainIn = CreateFrame("EditBox", nil, m, "InputBoxTemplate")
        mainIn:SetSize(330, 22)
        mainIn:SetPoint("TOPLEFT", mainLbl, "BOTTOMLEFT", 4, -4)
        mainIn:SetAutoFocus(false)
        mainIn:SetMaxLetters(32)
        m.mainIn = mainIn

        local noteLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        noteLbl:SetPoint("TOPLEFT", 16, -144)
        noteLbl:SetText(L["Social Note:"])
        local noteIn = CreateFrame("EditBox", nil, m, "InputBoxTemplate")
        noteIn:SetSize(330, 22)
        noteIn:SetPoint("TOPLEFT", noteLbl, "BOTTOMLEFT", 4, -4)
        noteIn:SetAutoFocus(false)
        noteIn:SetMaxLetters(60)
        m.noteIn = noteIn

        local btnSave = Theme:CreateButton(m, 92, 24, L["Save"], "primary")
        btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnSave = btnSave

        local btnCancel = Theme:CreateButton(m, 92, 24, L["Cancel"], "default")
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
        m:SetSize(440, 330)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:EnableMouse(true)
        table.insert(UISpecialFrames, "SocialCentralProfModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetText(L["My Clan Professions"])

        local sub = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetPoint("TOPLEFT", 16, -38)
        sub:SetText(L["Pick up to 2 primary professions + a short craft/service note:"])

        m._slot = 1
        m._p1 = "NONE"
        m._p2 = "NONE"

        local s1Btn = Theme:CreateButton(m, 195, 24, "", "default")
        s1Btn:SetPoint("TOPLEFT", 16, -60)
        m.s1Btn = s1Btn

        local s2Btn = Theme:CreateButton(m, 195, 24, "", "default")
        s2Btn:SetPoint("LEFT", s1Btn, "RIGHT", 10, 0)
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
            local b = Theme:CreateButton(m, 130, 22, PROF_LABELS[pid] or pid, "default")
            if b.label then
                b.label:ClearAllPoints()
                b.label:SetPoint("LEFT", 4, 0)
                b.label:SetPoint("RIGHT", -4, 0)
                b.label:SetWordWrap(false)
            end
            b:SetPoint("TOPLEFT", 16 + c * 136, -96 - r * 26)
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
        noteLbl:SetText(L["Craft Note (e.g. Flasks, Gems, Locks):"])

        local noteIn = CreateFrame("EditBox", nil, m, "InputBoxTemplate")
        noteIn:SetSize(400, 22)
        noteIn:SetPoint("BOTTOMLEFT", 20, 50)
        noteIn:SetAutoFocus(false)
        noteIn:SetMaxLetters(48)
        m.noteIn = noteIn

        local btnSave = Theme:CreateButton(m, 96, 24, L["Save"], "primary")
        btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnSave = btnSave

        local btnCancel = Theme:CreateButton(m, 96, 24, L["Cancel"], "default")
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
        m:SetSize(340, 140)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:EnableMouse(true)
        table.insert(UISpecialFrames, "SocialCentralCreateRoomModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetText(L["Create Private Chat Room"])

        local lbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 16, -44)
        lbl:SetText(L["Room Title (e.g. M+ Push, Officer Desk):"])

        local input = CreateFrame("EditBox", nil, m, "InputBoxTemplate")
        input:SetSize(300, 22)
        input:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 4, -6)
        input:SetAutoFocus(false)
        input:SetMaxLetters(32)
        m.input = input

        local btnSave = Theme:CreateButton(m, 92, 24, L["Create"], "primary")
        btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnSave = btnSave

        local btnCancel = Theme:CreateButton(m, 92, 24, L["Cancel"], "default")
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
        m:SetSize(360, 152)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:EnableMouse(true)
        table.insert(UISpecialFrames, "SocialCentralTempChanModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetText(L["Temporary WoW Chat Channel"])

        local lbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 16, -42)
        lbl:SetText(L["Channel name (uses JoinTemporaryChannel on click):"])

        local input = CreateFrame("EditBox", nil, m, "InputBoxTemplate")
        input:SetSize(320, 22)
        input:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 4, -6)
        input:SetAutoFocus(false)
        input:SetMaxLetters(24)
        m.input = input

        local btnJoin = Theme:CreateButton(m, 92, 24, L["Join"], "primary")
        btnJoin:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnJoin = btnJoin

        local btnLeave = Theme:CreateButton(m, 92, 24, L["Leave"], "danger")
        btnLeave:SetPoint("RIGHT", btnJoin, "LEFT", -8, 0)
        m.btnLeave = btnLeave

        local btnCancel = Theme:CreateButton(m, 92, 24, L["Cancel"], "default")
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
        m:SetSize(380, 300)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:EnableMouse(true)
        table.insert(UISpecialFrames, "SocialCentralRoomInvModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetText(L["Invite to Private Room"])

        local lbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 16, -42)
        lbl:SetText(L["Character-Realm or click an online friend below:"])

        local input = CreateFrame("EditBox", nil, m, "InputBoxTemplate")
        input:SetSize(250, 22)
        input:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 4, -6)
        input:SetAutoFocus(false)
        input:SetMaxLetters(48)
        m.input = input

        local btnInvite = Theme:CreateButton(m, 84, 22, L["Invite"], "primary")
        btnInvite:SetPoint("LEFT", input, "RIGHT", 8, 0)
        m.btnInvite = btnInvite

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
    topCard:SetHeight(56)
    panel.topCard = topCard

    local titleLbl = topCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleLbl:SetPoint("TOPLEFT", 10, -8)
    panel.titleLbl = titleLbl

    local countLbl = topCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countLbl:SetPoint("BOTTOMLEFT", 10, 8)
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
    btnAnnounce:SetPoint("RIGHT", helpTop, "LEFT", -6, 0)
    btnAnnounce:SetScript("OnClick", function()
        if ns.Group then ns.Group:OpenGroupChatAnnouncement() end
    end)

    local btnReady = Theme:CreateButton(topCard, 106, 22, L["Ready Check"], "default")
    btnReady:SetPoint("RIGHT", btnAnnounce, "LEFT", -6, 0)
    btnReady:SetScript("OnClick", function()
        if ns.Group then ns.Group:StartReadyCheck() end
    end)

    local btnRecent = Theme:CreateButton(topCard, 128, 22, L["Recent Companions"], "default")
    btnRecent:SetPoint("BOTTOMRIGHT", -8, 6)
    btnRecent:SetScript("OnClick", function()
        panel._view = "recent"
        panel:Refresh(true)
    end)

    local btnCurrent = Theme:CreateButton(topCard, 118, 22, L["Current Group"], "default")
    btnCurrent:SetPoint("RIGHT", btnRecent, "LEFT", -6, 0)
    btnCurrent:SetScript("OnClick", function()
        panel._view = "current"
        panel:Refresh(true)
    end)

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
        row.btnWatch:SetPoint("RIGHT", -8, 0)

        row.btnWhisper = Theme:CreateButton(row, 68, 22, L["Whisper"], "default")
        row.btnWhisper:SetPoint("RIGHT", row.btnWatch, "LEFT", -6, 0)

        row.btnExtra = Theme:CreateButton(row, 74, 22, L["Invite"], "default")
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
                Compat.Whisper(row._item.displayName)
            end
        end)
        row.btnExtra:SetScript("OnClick", function()
            if not row._item then return end
            if row._mode == "current" and row._item.unit then
                if ns.Group then ns.Group:PromoteMember(row._item.unit) end
            elseif row._item.displayName then
                Compat.Invite(row._item.displayName)
            end
        end)

        row:SetScript("OnClick", function(self, btn)
            if btn == "RightButton" and self._item and MenuUtil and MenuUtil.CreateContextMenu then
                local item = self._item
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(item.displayName or "")
                    root:CreateButton(L["Whisper"], function()
                        Compat.Whisper(item.displayName)
                    end)
                    if not item.isMe then
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
        local meta = Store and Store:GetSocialMeta(item.lookupKey or item.displayName)
        local mainTag = (meta and meta.mainName) and (" |cff6ec1e4[" .. meta.mainName .. "]|r") or ""

        row.nameText:SetText(hex .. (item.displayName or "") .. "|r" .. lvl .. " " .. roleTag .. leadTag .. readyTag .. mainTag)

        local subParts = {}
        if item.zone and item.zone ~= "" then table.insert(subParts, item.zone) end
        if meta and meta.folder then table.insert(subParts, "[" .. meta.folder .. "]") end
        if meta and meta.note then table.insert(subParts, meta.note) end
        if item.lastSeen then
            table.insert(subParts, Compat.FormatRelativeTime(item.lastSeen, L))
        end
        row.subText:SetText(table.concat(subParts, "  ·  "))

        if panel._view == "current" then
            Theme:ApplyStatusColor(row.dot, item.online ~= false and "online" or "offline")
            local iAmLeader = UnitIsGroupLeader and ns.Safe.Value(UnitIsGroupLeader("player")) == true
            if iAmLeader and not item.isMe and not item.isLeader then
                row.btnExtra:Show()
                Theme:SetButtonText(row.btnExtra, L["Promote"])
            else
                row.btnExtra:Hide()
            end
        else
            Theme:ApplyStatusColor(row.dot, item.inCurrentGroup and "online" or "nearby")
            row.btnExtra:Show()
            Theme:SetButtonText(row.btnExtra, L["Invite"])
        end

        row.btnWhisper:SetShown(not item.isMe)
        row.btnWatch:SetShown(not item.isMe)
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
    end

    function panel:Refresh(resetScroll)
        local p = Theme:GetPalette()
        self:RefreshTheme()
        Theme:SetButtonActive(btnCurrent, self._view == "current", "default")
        Theme:SetButtonActive(btnRecent, self._view == "recent", "default")

        local ch = ns.Group and ns.Group:GetChannelName()
        local counts = ns.Group and ns.Group:GetSummaryCounts() or { total = 0, TANK = 0, HEALER = 0, DAMAGER = 0 }
        if ch then
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
        { id = "all", label = L["All"], w = 54 },
        { id = "whispers", label = L["Whispers"], w = 78 },
        { id = "rooms", label = L["Rooms"], w = 68 },
        { id = "channels", label = L["Channels"], w = 76 },
    }
    local fBtns = {}
    local prevF
    for _, def in ipairs(filterDefs) do
        local b = Theme:CreateButton(topBar, def.w, 22, def.label, "default")
        if not prevF then
            b:SetPoint("LEFT", topBar, "LEFT", 8, 0)
        else
            b:SetPoint("LEFT", prevF, "RIGHT", 6, 0)
        end
        b:SetScript("OnClick", function()
            panel._filter = def.id
            panel:Refresh(true)
        end)
        fBtns[def.id] = b
        prevF = b
    end

    local helpTop = AddHelp(
        topBar,
        topBar,
        L["Help: Conversations & Private Rooms"],
        L["Collects whispers, Battle.net chats, group/guild tabs, and Addon Private Chat Rooms (SCentral1) in one view without storing BattleTags or Real IDs."],
        L["Private Rooms send directly to invited friends via addon packets. Native WoW whispers/channels pre-fill Blizzard chat safely on Send/Enter."],
        "RIGHT",
        "RIGHT",
        -8,
        0
    )

    local btnClear = Theme:CreateButton(topBar, 72, 22, L["Clear"], "default")
    btnClear:SetPoint("RIGHT", helpTop, "LEFT", -6, 0)
    btnClear:SetScript("OnClick", function()
        if ns.Chat then
            ns.Chat:ClearHistory(ns.Chat.activeThreadKey)
        end
    end)

    local btnTemp = Theme:CreateButton(topBar, 96, 22, L["Temp Channel"], "default")
    btnTemp:SetPoint("RIGHT", btnClear, "LEFT", -6, 0)
    btnTemp:SetScript("OnClick", OpenTempChannelModal)

    local btnNewRoom = Theme:CreateButton(topBar, 88, 22, "+ " .. L["Room"], "primary")
    btnNewRoom:SetPoint("RIGHT", btnTemp, "LEFT", -6, 0)
    btnNewRoom:SetScript("OnClick", OpenCreateRoomModal)

    -- Pending room invite banner (auto-hidden when empty)
    local inviteBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    inviteBar:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -6)
    inviteBar:SetPoint("TOPRIGHT", topBar, "BOTTOMRIGHT", 0, -6)
    inviteBar:SetHeight(30)
    inviteBar:Hide()

    local invText = inviteBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    invText:SetPoint("LEFT", 10, 0)
    invText:SetJustifyH("LEFT")

    local invDecline = Theme:CreateButton(inviteBar, 74, 20, L["Decline"], "danger")
    invDecline:SetPoint("RIGHT", -8, 0)
    local invAccept = Theme:CreateButton(inviteBar, 74, 20, L["Accept"], "primary")
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

        r:SetScript("OnClick", function()
            if r._item and ns.Chat then
                ns.Chat:SetActiveThread(r._item.key)
                panel:Refresh(false)
            end
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
        local badge = (item.unread and item.unread > 0) and (" |cff3fb950(" .. item.unread .. ")|r") or ""
        local hex = item.classFile and Compat.ClassHex(item.classFile) or "|cffffffff"
        r.title:SetText(prefix .. hex .. (item.title or "") .. "|r" .. badge)
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

    local btnLeaveRoom = Theme:CreateButton(rightHdr, 64, 20, L["Leave"], "danger")
    btnLeaveRoom:SetPoint("RIGHT", 0, 0)
    btnLeaveRoom:Hide()

    local btnRoomInvite = Theme:CreateButton(rightHdr, 76, 20, "+ " .. L["Invite"], "default")
    btnRoomInvite:SetPoint("RIGHT", btnLeaveRoom, "LEFT", -6, 0)
    btnRoomInvite:Hide()

    local btnTargetCard = Theme:CreateButton(rightHdr, 78, 20, L["Note"], "default")
    btnTargetCard:SetPoint("RIGHT", 0, 0)
    btnTargetCard:Hide()

    hdrTitle:SetPoint("RIGHT", btnRoomInvite, "LEFT", -8, 0)

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

    local msgFrame = CreateFrame("ScrollingMessageFrame", nil, rightCard)
    msgFrame:SetPoint("TOPLEFT", 10, -34)
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
        L["In Addon Private Rooms, pressing Enter or Send dispatches addon messages directly. On Whispers and WoW channels, it safely pre-fills Blizzard's protected chat box."],
        L["Type your message and press Enter. SocialCentral never calls restricted chat-automation APIs."],
        "RIGHT",
        "RIGHT",
        0,
        0
    )

    local btnSend = Theme:CreateButton(composer, 92, 22, L["Open Chat"], "primary")
    btnSend:SetPoint("RIGHT", helpComposer, "LEFT", -6, 0)

    local replyInput = CreateFrame("EditBox", nil, composer, "InputBoxTemplate")
    replyInput:SetPoint("LEFT", 6, 0)
    replyInput:SetPoint("RIGHT", btnSend, "LEFT", -8, 0)
    replyInput:SetHeight(22)
    replyInput:SetAutoFocus(false)
    replyInput:SetMaxLetters(160)

    local function SubmitReply()
        if not (ns.Chat and ns.Chat.activeThreadKey) then return end
        local txt = replyInput:GetText() or ""
        if ns.Chat:SendOrOpenReply(ns.Chat.activeThreadKey, txt) then
            if ns.Chat.activeThreadKey:sub(1, 5) == "room:" then
                replyInput:SetText("")
            end
        end
    end
    btnSend:SetScript("OnClick", SubmitReply)
    replyInput:SetScript("OnEnterPressed", SubmitReply)
    replyInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    function panel:RefreshTheme()
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(topBar, "surface", p)
        Theme:ApplyBackdrop(inviteBar, "surface", p)
        Theme:ApplyBackdrop(leftCard, "surface", p)
        Theme:ApplyBackdrop(rightCard, "surface", p)
        for _, b in pairs(fBtns) do Theme:StyleButton(b, "default") end
        Theme:StyleButton(btnNewRoom, "primary")
        Theme:StyleButton(btnTemp, "default")
        Theme:StyleButton(btnClear, "default")
        Theme:StyleButton(invAccept, "primary")
        Theme:StyleButton(invDecline, "danger")
        Theme:StyleButton(btnRoomInvite, "default")
        Theme:StyleButton(btnLeaveRoom, "danger")
        Theme:StyleButton(btnTargetCard, "default")
        Theme:StyleButton(btnSend, "primary")
        if helpTop and helpTop.RefreshTheme then helpTop:RefreshTheme() end
        if helpComposer and helpComposer.RefreshTheme then helpComposer:RefreshTheme() end
    end

    function panel:Refresh(resetScroll)
        local p = Theme:GetPalette()
        self:RefreshTheme()
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
        leftCard:SetWidth(238)

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
            local room = isRoom and ns.Chat:GetRoom(active.roomId)
            local memberCount = 0
            if room and room.members then
                for _ in pairs(room.members) do memberCount = memberCount + 1 end
            end
            hdrTitle:SetText((active.title or "") .. (isRoom and ("  |cff3fb950[" .. memberCount .. "]|r") or ""))
            btnRoomInvite:SetShown(isRoom)
            btnLeaveRoom:SetShown(isRoom)
            btnTargetCard:SetShown(active.kind == "WHISPER" and active.targetName ~= nil)
            Theme:SetButtonText(btnSend, isRoom and L["Send"] or L["Open Chat"])
            btnSend:SetEnabled(true)

            local lines = active.messages or {}
            if #lines == 0 then
                msgFrame:AddMessage(L["No messages yet."], p.textMuted[1], p.textMuted[2], p.textMuted[3])
            else
                for _, entry in ipairs(lines) do
                    local ts = entry.ts and entry.ts > 0 and date("|cff9da7b5[%H:%M]|r ", entry.ts) or ""
                    local hex = entry.classFile and Compat.ClassHex(entry.classFile) or (entry.incoming and "|cffd2a8ff" or "|cff58a6ff")
                    msgFrame:AddMessage(ts .. hex .. (entry.sender or "") .. "|r: " .. (entry.text or ""))
                end
            end
            if msgFrame.ScrollToBottom then
                msgFrame:ScrollToBottom()
            end
        else
            hdrTitle:SetText(L["Select a conversation or create a Private Room"])
            btnRoomInvite:Hide()
            btnLeaveRoom:Hide()
            btnTargetCard:Hide()
            btnSend:SetEnabled(false)
            msgFrame:AddMessage(L["Use '+ Room' above to start an addon-only Private Chat Room with friends or guildmates."], p.textMuted[1], p.textMuted[2], p.textMuted[3])
        end
    end

    panel:RefreshTheme()
    return panel
end
