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

local DEFAULT_FOLDER_PRESETS = { "M+", "Raid", "PvP", "Craft" }

function SocialPanels:OpenSocialMetaModal(displayName, rawKey, contextItem)
    local dirEntry = contextItem
        or (ns.Social and ns.Social.GetDirectoryEntry and ns.Social:GetDirectoryEntry(rawKey or displayName))
        or nil

    local charKey = nil
    if dirEntry then
        if dirEntry.lookupKey and dirEntry.lookupKey ~= "" then
            charKey = dirEntry.lookupKey
        end
    else
        charKey = rawKey or displayName
        if charKey == "" then charKey = nil end
    end

    local bnetAccountID = dirEntry and dirEntry.bnetAccountID or nil
    local isCharFriend = dirEntry and dirEntry.sources and dirEntry.sources.friend == true
    local isBNetFriend = dirEntry and dirEntry.sources and dirEntry.sources.bnet == true and bnetAccountID ~= nil
    local allowSocialCard = charKey ~= nil
    if not allowSocialCard and not isBNetFriend then
        return
    end

    if not metaModal then
        local m = CreateFrame("Frame", "SocialCentralMetaModal", UIParent, "BackdropTemplate")
        m:SetSize(454, 412)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(110)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
        Theme:MakeMovable(m, { key = "modal_social_meta" })
        table.insert(UISpecialFrames, "SocialCentralMetaModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -64, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        m.title = title
        if Theme.DecorateSectionHeader then
            Theme:DecorateSectionHeader(m, title, 360)
        end

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            m.folderIn:ClearFocus()
            m.mainIn:ClearFocus()
            m.noteIn:ClearFocus()
            m.nativeNoteIn:ClearFocus()
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        m.helpBtn = AddHelp(
            m,
            topCloseBtn,
            L["Help: Social Card & Friend Notes"],
            L["Organizes players with Favorite, Social Folders, Good/Avoid relationship tags, linked Main/Alts, personal Social Card notes, and native WoW/Battle.net Friend Notes."],
            L["Social Card fields are stored safely by character name (never saving Real ID or BattleTag), while Blizzard Friend Note updates your official Friend/Battle.net note outside combat."],
            "RIGHT",
            "LEFT",
            -6,
            0
        )

        local fLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fLbl:SetJustifyH("LEFT")
        fLbl:SetWordWrap(false)
        fLbl:SetText(L["Social Folder (e.g. M+ Team, Guild Core):"])
        m.fLbl = fLbl

        local fIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 24 })
        m.folderIn = fIn

        local chipBtns = {}
        for i = 1, 5 do
            local cb = Theme:CreateButton(m, 64, 18, "", "default")
            cb:SetScript("OnClick", function(self)
                if self._folderVal then
                    fIn:SetText(self._folderVal)
                end
            end)
            chipBtns[i] = cb
        end
        m.chipBtns = chipBtns

        local mainLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        mainLbl:SetJustifyH("LEFT")
        mainLbl:SetWordWrap(false)
        mainLbl:SetText(L["Linked Main Character (optional):"])
        m.mainLbl = mainLbl

        local mainIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 32 })
        m.mainIn = mainIn

        local altsLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        altsLbl:SetJustifyH("LEFT")
        altsLbl:SetWordWrap(true)
        altsLbl:SetTextColor(0.66, 0.74, 0.84)
        m.altsLbl = altsLbl

        local noteLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        noteLbl:SetJustifyH("LEFT")
        noteLbl:SetWordWrap(false)
        noteLbl:SetText(L["Social Note:"])
        m.noteLbl = noteLbl

        local noteIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 60, insertLinkMode = "full" })
        m.noteIn = noteIn

        local nativeNoteLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nativeNoteLbl:SetJustifyH("LEFT")
        nativeNoteLbl:SetWordWrap(false)
        m.nativeNoteLbl = nativeNoteLbl

        local nativeNoteIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 48 })
        m.nativeNoteIn = nativeNoteIn

        local btnFav = Theme:CreateButton(m, 110, 22, "* " .. L["Favorite"], "default")
        Theme:AutoFitButton(btnFav, 94, 14, 140)
        m.btnFav = btnFav

        local btnFlagGood = Theme:CreateButton(m, 144, 22, L["Good Partner (+)"], "default")
        Theme:AutoFitButton(btnFlagGood, 120, 14, 175)
        m.btnFlagGood = btnFlagGood

        local btnFlagAvoid = Theme:CreateButton(m, 130, 22, L["Flag: Avoid"], "default")
        Theme:AutoFitButton(btnFlagAvoid, 110, 14, 165)
        m.btnFlagAvoid = btnFlagAvoid

        local function SyncActionButtons()
            Theme:SetButtonActive(btnFav, m._pendingFav == true, "primary")
            Theme:SetButtonActive(btnFlagGood, m._pendingFlag == "GOOD", "default")
            Theme:SetButtonActive(btnFlagAvoid, m._pendingFlag == "AVOID", "danger")
        end
        m.SyncFlagButtons = SyncActionButtons

        btnFav:SetScript("OnClick", function()
            m._pendingFav = not (m._pendingFav == true)
            SyncActionButtons()
        end)
        btnFlagGood:SetScript("OnClick", function()
            m._pendingFlag = (m._pendingFlag == "GOOD") and "" or "GOOD"
            SyncActionButtons()
        end)
        btnFlagAvoid:SetScript("OnClick", function()
            m._pendingFlag = (m._pendingFlag == "AVOID") and "" or "AVOID"
            SyncActionButtons()
        end)

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
            nativeNoteIn:ClearFocus()
            m:Hide()
        end)
        for _, box in ipairs({ fIn, mainIn, noteIn, nativeNoteIn }) do
            box:SetScript("OnEscapePressed", function() m:Hide() end)
        end

        metaModal = m
    end

    local meta = (allowSocialCard and Store and Store:GetSocialMeta(charKey)) or {}
    local curFav = false
    if allowSocialCard and Store and Store.IsSocialFavorite then
        curFav = Store:IsSocialFavorite(charKey)
    end
    if not curFav and dirEntry and dirEntry.bnetFavorite == true then
        curFav = true
    end

    Theme:ApplyBackdrop(metaModal, "window")
    Theme:StyleButton(metaModal.topCloseBtn, "default")
    Theme:StyleButton(metaModal.btnSave, "primary")
    Theme:StyleButton(metaModal.btnCancel, "default")
    Theme:StyleButton(metaModal.btnFav, "default")
    Theme:StyleButton(metaModal.btnFlagGood, "default")
    Theme:StyleButton(metaModal.btnFlagAvoid, "danger")
    if metaModal.helpBtn and metaModal.helpBtn.RefreshTheme then
        metaModal.helpBtn:RefreshTheme()
    end

    metaModal.title:SetText(L["Social Card: %s"]:format(displayName or charKey or ""))

    -- Dynamically stack visible sections cleanly with zero overlap.
    local y = -44
    if allowSocialCard then
        metaModal.fLbl:Show()
        metaModal.fLbl:ClearAllPoints()
        metaModal.fLbl:SetPoint("TOPLEFT", 16, y)
        metaModal.fLbl:SetPoint("TOPRIGHT", -16, y)
        y = y - 16

        metaModal.folderIn:Show()
        metaModal.folderIn:ClearAllPoints()
        metaModal.folderIn:SetPoint("TOPLEFT", 16, y)
        metaModal.folderIn:SetPoint("RIGHT", metaModal, "RIGHT", -16, 0)
        metaModal.folderIn:SetText(meta and meta.folder or "")
        y = y - 28

        -- Populate folder chips: existing user folders first, then curated defaults.
        local chipList, seenChip = {}, {}
        if Store and Store.GetSocialFolders then
            for _, fn in ipairs(Store:GetSocialFolders()) do
                if #chipList < 5 and not seenChip[fn] then
                    seenChip[fn] = true
                    chipList[#chipList + 1] = fn
                end
            end
        end
        for _, def in ipairs(DEFAULT_FOLDER_PRESETS) do
            if #chipList < 5 and not seenChip[def] then
                seenChip[def] = true
                chipList[#chipList + 1] = def
            end
        end
        local cx = 16
        for i, cb in ipairs(metaModal.chipBtns) do
            local fn = chipList[i]
            if fn then
                cb._folderVal = fn
                Theme:StyleButton(cb, "default")
                Theme:SetButtonText(cb, fn)
                Theme:AutoFitButton(cb, 42, 12, 108)
                local cw = cb:GetWidth() or 60
                if (cx + cw) <= 438 then
                    cb:ClearAllPoints()
                    cb:SetPoint("TOPLEFT", metaModal, "TOPLEFT", cx, y)
                    cb:Show()
                    cx = cx + cw + 6
                else
                    cb:Hide()
                end
            else
                cb:Hide()
            end
        end
        y = y - 26

        metaModal.mainLbl:Show()
        metaModal.mainLbl:ClearAllPoints()
        metaModal.mainLbl:SetPoint("TOPLEFT", 16, y)
        metaModal.mainLbl:SetPoint("TOPRIGHT", -16, y)
        y = y - 16

        metaModal.mainIn:Show()
        metaModal.mainIn:ClearAllPoints()
        metaModal.mainIn:SetPoint("TOPLEFT", 16, y)
        metaModal.mainIn:SetPoint("RIGHT", metaModal, "RIGHT", -16, 0)
        metaModal.mainIn:SetText(meta and meta.mainName or "")
        y = y - 28

        local linkedAlts = Store and Store.GetLinkedAltsForCharacter and Store:GetLinkedAltsForCharacter(charKey)
        if linkedAlts and #linkedAlts > 0 then
            metaModal.altsLbl:ClearAllPoints()
            metaModal.altsLbl:SetPoint("TOPLEFT", 16, y)
            metaModal.altsLbl:SetPoint("TOPRIGHT", -16, y)
            metaModal.altsLbl:SetText(L["Linked Alts"] .. ": " .. table.concat(linkedAlts, ", "))
            metaModal.altsLbl:Show()
            y = y - 18
        else
            metaModal.altsLbl:Hide()
        end

        metaModal.noteLbl:Show()
        metaModal.noteLbl:ClearAllPoints()
        metaModal.noteLbl:SetPoint("TOPLEFT", 16, y)
        metaModal.noteLbl:SetPoint("TOPRIGHT", -16, y)
        y = y - 16

        metaModal.noteIn:Show()
        metaModal.noteIn:ClearAllPoints()
        metaModal.noteIn:SetPoint("TOPLEFT", 16, y)
        metaModal.noteIn:SetPoint("RIGHT", metaModal, "RIGHT", -16, 0)
        metaModal.noteIn:SetText(meta and meta.note or "")
        y = y - 30
    else
        metaModal.fLbl:Hide()
        metaModal.folderIn:Hide()
        for _, cb in ipairs(metaModal.chipBtns) do cb:Hide() end
        metaModal.mainLbl:Hide()
        metaModal.mainIn:Hide()
        metaModal.altsLbl:Hide()
        metaModal.noteLbl:Hide()
        metaModal.noteIn:Hide()
    end

    local showNativeNote = isCharFriend or isBNetFriend
    local initialNativeNote = ""
    if showNativeNote then
        if isCharFriend then
            metaModal.nativeNoteLbl:SetText(L["Blizzard Friend Note (synced with WoW Friends):"])
            initialNativeNote = (dirEntry and dirEntry.friendNote) or ""
            metaModal.nativeNoteIn:SetMaxLetters(48)
        else
            metaModal.nativeNoteLbl:SetText(L["Battle.net Friend Note:"])
            initialNativeNote = (dirEntry and dirEntry.bnetNote) or ""
            metaModal.nativeNoteIn:SetMaxLetters(120)
        end
        metaModal.nativeNoteLbl:ClearAllPoints()
        metaModal.nativeNoteLbl:SetPoint("TOPLEFT", 16, y)
        metaModal.nativeNoteLbl:SetPoint("TOPRIGHT", -16, y)
        metaModal.nativeNoteLbl:Show()
        y = y - 16

        metaModal.nativeNoteIn:ClearAllPoints()
        metaModal.nativeNoteIn:SetPoint("TOPLEFT", 16, y)
        metaModal.nativeNoteIn:SetPoint("RIGHT", metaModal, "RIGHT", -16, 0)
        metaModal.nativeNoteIn:SetText(initialNativeNote)
        metaModal.nativeNoteIn:Show()
        y = y - 32
    else
        metaModal.nativeNoteLbl:Hide()
        metaModal.nativeNoteIn:Hide()
    end

    metaModal.btnFav:ClearAllPoints()
    metaModal.btnFav:SetPoint("TOPLEFT", 16, y)
    if allowSocialCard then
        metaModal.btnFlagGood:Show()
        metaModal.btnFlagGood:ClearAllPoints()
        metaModal.btnFlagGood:SetPoint("LEFT", metaModal.btnFav, "RIGHT", 6, 0)
        metaModal.btnFlagAvoid:Show()
        metaModal.btnFlagAvoid:ClearAllPoints()
        metaModal.btnFlagAvoid:SetPoint("LEFT", metaModal.btnFlagGood, "RIGHT", 6, 0)
    else
        metaModal.btnFlagGood:Hide()
        metaModal.btnFlagAvoid:Hide()
    end

    metaModal:SetHeight(math.max(190, math.abs(y) + 74))

    metaModal._pendingFav = curFav
    metaModal._pendingFlag = (allowSocialCard and meta and meta.flag) or ""
    metaModal.SyncFlagButtons()

    local function Commit()
        if allowSocialCard and Store and Store.SetSocialMeta then
            Store:SetSocialMeta(charKey, {
                folder = metaModal.folderIn:GetText() or "",
                mainName = metaModal.mainIn:GetText() or "",
                note = metaModal.noteIn:GetText() or "",
                flag = metaModal._pendingFlag or "",
                favorite = metaModal._pendingFav == true,
            })
            if Store.TouchFriendPresence then
                Store:TouchFriendPresence(charKey, { favorite = metaModal._pendingFav == true })
            end
        end

        if isBNetFriend and Compat and Compat.SetBNetFriendFavorite and (dirEntry.bnetFavorite == true) ~= (metaModal._pendingFav == true) then
            Compat.SetBNetFriendFavorite(bnetAccountID, metaModal._pendingFav == true)
        end

        if showNativeNote and Compat then
            local nextNative = metaModal.nativeNoteIn:GetText() or ""
            if nextNative ~= initialNativeNote then
                local savedOk = false
                if isCharFriend and Compat.SetCharacterFriendNote then
                    savedOk = Compat.SetCharacterFriendNote(displayName or charKey, nextNative)
                elseif isBNetFriend and Compat.SetBNetFriendNote then
                    savedOk = Compat.SetBNetFriendNote(bnetAccountID, nextNative)
                end
                if not savedOk and InCombatLockdown and InCombatLockdown() then
                    ns:Print("%s", L["Cannot update Blizzard friend note while in combat."])
                end
            end
        end

        metaModal.folderIn:ClearFocus()
        metaModal.mainIn:ClearFocus()
        metaModal.noteIn:ClearFocus()
        metaModal.nativeNoteIn:ClearFocus()
        metaModal:Hide()
    end

    metaModal.btnSave:SetScript("OnClick", Commit)
    metaModal.noteIn:SetScript("OnEnterPressed", Commit)
    metaModal.nativeNoteIn:SetScript("OnEnterPressed", Commit)
    metaModal:Show()
    if allowSocialCard then
        metaModal.folderIn:SetFocus()
    else
        metaModal.nativeNoteIn:SetFocus()
    end
end

function SocialPanels:OpenProfessionModal()
    local parentFrame = ns.UI and ns.UI.GetFrame and ns.UI:GetFrame() or UIParent
    local profs = ns.Clan and ns.Clan.PROFESSIONS or {}

    if not profModal then
        local m = CreateFrame("Frame", "SocialCentralProfModal", parentFrame, "BackdropTemplate")
        m:SetSize(504, 372)
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
        m._r1 = ""
        m._r2 = ""

        local s1Btn = Theme:CreateButton(m, 228, 24, "", "default")
        s1Btn:SetPoint("TOPLEFT", 16, -64)
        m.s1Btn = s1Btn

        local s2Btn = Theme:CreateButton(m, 228, 24, "", "default")
        s2Btn:SetPoint("LEFT", s1Btn, "RIGHT", 14, 0)
        m.s2Btn = s2Btn

        local function RefreshSlots()
            Theme:SetButtonActive(s1Btn, m._slot == 1, "default")
            Theme:SetButtonActive(s2Btn, m._slot == 2, "default")
            local r1Txt = (m._r1 and m._r1 ~= "" and m._p1 ~= "NONE") and (" (" .. m._r1 .. ")") or ""
            local r2Txt = (m._r2 and m._r2 ~= "" and m._p2 ~= "NONE") and (" (" .. m._r2 .. ")") or ""
            Theme:SetButtonText(s1Btn, L["Prof 1"] .. ": " .. (PROF_LABELS[m._p1 or "NONE"] or L["None"]) .. r1Txt)
            Theme:SetButtonText(s2Btn, L["Prof 2"] .. ": " .. (PROF_LABELS[m._p2 or "NONE"] or L["None"]) .. r2Txt)
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
            local b = Theme:CreateButton(m, 152, 22, PROF_LABELS[pid] or pid, "default")
            b:SetPoint("TOPLEFT", 16 + c * 158, -98 - r * 26)
            b:SetScript("OnClick", function()
                local det = ns.Clan and ns.Clan._myDetectedRanks and ns.Clan._myDetectedRanks[pid]
                local detRank = det and det.rank or ""
                if m._slot == 1 then
                    m._p1 = pid
                    m._r1 = (pid ~= "NONE") and detRank or ""
                else
                    m._p2 = pid
                    m._r2 = (pid ~= "NONE") and detRank or ""
                end
                RefreshSlots()
            end)
            table.insert(m._profBtns, b)
        end

        local noteLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        noteLbl:SetPoint("BOTTOMLEFT", 16, 86)
        noteLbl:SetPoint("BOTTOMRIGHT", -16, 86)
        noteLbl:SetJustifyH("LEFT")
        noteLbl:SetWordWrap(false)
        noteLbl:SetText(L["Craft Note (e.g. Flasks, Gems, Locks):"])

        local noteIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 48 })
        noteIn:SetPoint("BOTTOMLEFT", 16, 56)
        noteIn:SetPoint("BOTTOMRIGHT", -16, 56)
        m.noteIn = noteIn

        local btnAuto = Theme:CreateButton(m, 112, 24, L["Auto-Detect"], "default")
        Theme:AutoFitButton(btnAuto, 98, 16, 138)
        btnAuto:SetPoint("BOTTOMLEFT", 16, 14)
        m.btnAuto = btnAuto

        local btnPubNote = Theme:CreateButton(m, 116, 24, L["Publish Note"], "default")
        Theme:AutoFitButton(btnPubNote, 102, 16, 146)
        btnPubNote:SetPoint("LEFT", btnAuto, "RIGHT", 6, 0)
        m.btnPubNote = btnPubNote

        m.profModalHelp = AddHelp(
            m,
            btnPubNote,
            L["Help: Profession Auto-Detect & Guild Note"],
            L["Detects your character's current professions and skill ranks automatically, and lets you publish a compact tag to your Guild Public Note."],
            L["Click 'Auto-Detect' to pull your live professions, or click 'Publish Note' so all guildmates see your crafts even without SocialCentral."]
        )

        local btnSave = Theme:CreateButton(m, 88, 24, L["Save"], "primary")
        Theme:AutoFitButton(btnSave, 78, 16, 116)
        btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnSave = btnSave

        local btnCancel = Theme:CreateButton(m, 88, 24, L["Cancel"], "default")
        Theme:AutoFitButton(btnCancel, 78, 16, 116)
        btnCancel:SetPoint("RIGHT", btnSave, "LEFT", -6, 0)
        m.btnCancel = btnCancel

        btnCancel:SetScript("OnClick", function() noteIn:ClearFocus(); m:Hide() end)
        noteIn:SetScript("OnEscapePressed", function() noteIn:ClearFocus(); m:Hide() end)

        local function SaveProfs()
            if ns.Clan and ns.Clan.SetMyProfessions then
                ns.Clan:SetMyProfessions(m._p1, m._p2, noteIn:GetText() or "", m._r1, m._r2)
            end
            noteIn:ClearFocus()
            m:Hide()
        end
        btnSave:SetScript("OnClick", SaveProfs)
        noteIn:SetScript("OnEnterPressed", SaveProfs)

        btnAuto:SetScript("OnClick", function()
            if ns.Clan and ns.Clan.AutoDetectMyProfessions then
                local found, p1, p2, r1, r2 = ns.Clan:AutoDetectMyProfessions(true)
                if found then
                    m._p1 = p1 or "NONE"
                    m._p2 = p2 or "NONE"
                    m._r1 = r1 or ""
                    m._r2 = r2 or ""
                    RefreshSlots()
                else
                    ns:Print("%s", L["No primary professions detected yet on this character."])
                end
            end
        end)

        btnPubNote:SetScript("OnClick", function()
            if ns.Clan and ns.Clan.SetMyProfessions then
                ns.Clan:SetMyProfessions(m._p1, m._p2, noteIn:GetText() or "", m._r1, m._r2)
            end
            if ns.Clan and ns.Clan.PublishProfessionsToGuildNote then
                local ok, msgOrErr = ns.Clan:PublishProfessionsToGuildNote(noteIn:GetText() or "")
                if ok then
                    ns:Print("%s", L["Guild Public Note updated: %s"]:format(msgOrErr))
                else
                    ns:Print("%s", msgOrErr or L["Unable to update Guild Public Note right now."])
                end
            end
        end)

        profModal = m
    end

    if ns.Clan and ns.Clan.AutoDetectMyProfessions then
        ns.Clan:AutoDetectMyProfessions(false)
    end
    local bucket = Store and Store:GetClanScopeData() or {}
    local p1 = (type(bucket.myProf1) == "string" and bucket.myProf1 ~= "") and bucket.myProf1 or "NONE"
    local p2 = (type(bucket.myProf2) == "string" and bucket.myProf2 ~= "") and bucket.myProf2 or "NONE"
    local r1 = bucket.myProf1Rank or ""
    local r2 = bucket.myProf2Rank or ""
    if p1 == "NONE" and p2 == "NONE" and ns.db and ns.db.alts then
        local myAlt = ns.db.alts[Compat.CharacterKey()]
        if myAlt and type(myAlt.professions) == "table" then
            local matched, ranks = {}, {}
            for _, ap in ipairs(myAlt.professions) do
                if ap and ap.isPrimary and ap.name and ap.name ~= "" then
                    local pid = (ns.Clan and ns.Clan.MatchProfessionId) and ns.Clan:MatchProfessionId(ap.name) or "NONE"
                    if pid ~= "NONE" then
                        matched[#matched + 1] = pid
                        ranks[#matched] = ((ap.maxRank or 0) > 0) and string.format("%d/%d", ap.rank or 0, ap.maxRank or 0) or ""
                    else
                        local low = ap.name:lower()
                        for lpid, lbl in pairs(PROF_LABELS) do
                            if lpid ~= "NONE" and lbl and lbl:lower() == low then
                                matched[#matched + 1] = lpid
                                ranks[#matched] = ""
                                break
                            end
                        end
                    end
                end
            end
            if matched[1] then p1, r1 = matched[1], ranks[1] or "" end
            if matched[2] then p2, r2 = matched[2], ranks[2] or "" end
        end
    end
    profModal._p1 = p1
    profModal._p2 = p2
    profModal._r1 = r1
    profModal._r2 = r2
    profModal._slot = 1
    local canPub = (ns.Clan and ns.Clan.CanEditMyGuildNote and ns.Clan:CanEditMyGuildNote()) == true
    if profModal.btnPubNote then
        profModal.btnPubNote:SetEnabled(canPub)
    end
    Theme:ApplyBackdrop(profModal, "window")
    Theme:StyleButton(profModal.topCloseBtn, "default")
    Theme:StyleButton(profModal.btnAuto, "default")
    Theme:StyleButton(profModal.btnPubNote, "default")
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

        local input = Theme:CreateEditBox(m, { height = 24, maxLetters = 48, clearButton = true })
        input:SetPoint("TOPLEFT", m, "TOPLEFT", 16, -62)
        input:SetPoint("RIGHT", btnInvite, "LEFT", -8, 0)
        m.input = input

        m._applyFilter = function()
            local all = m._allOnline or {}
            local raw = input:GetText() or ""
            local q = (Compat.Trim and Compat.Trim(raw) or raw):lower()
            if q == "" then
                m.scroll:SetData(all, L["No online friends found right now."], true)
                return
            end
            local filtered = {}
            for _, row in ipairs(all) do
                local dn = (row.displayName or ""):lower()
                local g = (row.guild or ""):lower()
                if dn:find(q, 1, true) or (g ~= "" and g:find(q, 1, true)) then
                    filtered[#filtered + 1] = row
                end
            end
            m.scroll:SetData(filtered, L["No online friends found right now."], true)
        end
        input:HookScript("OnTextChanged", function()
            if not m._applyFilter then return end
            m._filterToken = (m._filterToken or 0) + 1
            local token = m._filterToken
            if C_Timer and C_Timer.After then
                C_Timer.After(0.10, function()
                    if m:IsShown() and m._filterToken == token and m._applyFilter then
                        m._applyFilter()
                    end
                end)
            else
                m._applyFilter()
            end
        end)

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
    local onlineList = ns.Social and ns.Social:GetList("all") or {}
    roomInviteModal._allOnline = onlineList
    roomInviteModal.input:SetText("")
    if roomInviteModal._applyFilter then
        roomInviteModal._applyFilter()
    else
        roomInviteModal.scroll:SetData(onlineList, L["No online friends found right now."], true)
    end
    roomInviteModal:Show()
end

--------------------------------------------------------------------------------
-- Shared Responsive Flow Helper
--------------------------------------------------------------------------------
local function LayoutButtonFlow(container, buttons, startX, startY, maxRowW, rowStep, gap)
    local x = 0
    local rows = 1
    local gapPx = gap or 4
    local stepY = rowStep or 24
    local limitW = math.max(120, maxRowW or 360)
    for _, btn in ipairs(buttons) do
        if btn and btn:IsShown() then
            local bw = math.ceil(btn:GetWidth() or 60)
            if x > 0 and (x + bw) > limitW then
                x = 0
                rows = rows + 1
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", container, "TOPLEFT", startX + x, startY - (rows - 1) * stepY)
            x = x + bw + gapPx
        end
    end
    return rows
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

    local btnView = Theme:CreateButton(topCard, 150, 22, L["Current Group"] .. "  v", "default")
    Theme:AutoFitButton(btnView, 128, 16, 210)
    btnView:SetPoint("BOTTOMRIGHT", -8, 6)
    btnView:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateRadio(L["Current Group"], function()
                    return panel._view == "current"
                end, function()
                    panel._view = "current"
                    panel:Refresh(true)
                end)
                root:CreateRadio(L["Recent Companions"], function()
                    return panel._view == "recent"
                end, function()
                    panel._view = "recent"
                    panel:Refresh(true)
                end)
            end)
        else
            panel._view = (panel._view == "current") and "recent" or "current"
            panel:Refresh(true)
        end
    end)

    countLbl:SetPoint("RIGHT", btnView, "LEFT", -10, 0)

    local function LayoutGroupTopBar()
        local w = topCard:GetWidth() or panel:GetWidth() or 0
        if w <= 0 then w = 730 end
        local compact = w < 540
        local showReady = btnReady:IsShown()
        titleLbl:ClearAllPoints()
        countLbl:ClearAllPoints()
        if compact then
            Theme:AutoFitButton(btnReady, 72, 10, 128)
            Theme:AutoFitButton(btnAnnounce, 76, 10, 134)
            Theme:AutoFitButton(btnView, 110, 10, 175)

            titleLbl:SetPoint("TOPLEFT", topCard, "TOPLEFT", 10, -7)
            titleLbl:SetPoint("RIGHT", helpTop, "LEFT", -6, 0)
            countLbl:SetPoint("TOPLEFT", topCard, "TOPLEFT", 10, -27)
            countLbl:SetPoint("TOPRIGHT", topCard, "TOPRIGHT", -10, -27)

            local flowBtns = { btnView }
            if showReady then table.insert(flowBtns, btnReady) end
            table.insert(flowBtns, btnAnnounce)
            local rows = LayoutButtonFlow(topCard, flowBtns, 8, -46, w - 16, 24, 4)
            topCard:SetHeight(rows == 1 and 78 or (46 + rows * 24 + 6))
        else
            topCard:SetHeight(60)
            Theme:AutoFitButton(btnAnnounce, 96, 16, 165)
            Theme:AutoFitButton(btnReady, 92, 16, 165)
            Theme:AutoFitButton(btnView, 128, 16, 210)

            btnAnnounce:ClearAllPoints()
            btnAnnounce:SetPoint("RIGHT", helpTop, "LEFT", -6, 0)
            btnReady:ClearAllPoints()
            btnReady:SetPoint("RIGHT", btnAnnounce, "LEFT", -6, 0)
            btnView:ClearAllPoints()
            btnView:SetPoint("BOTTOMRIGHT", -8, 6)

            titleLbl:SetPoint("TOPLEFT", 10, -8)
            titleLbl:SetPoint("RIGHT", showReady and btnReady or btnAnnounce, "LEFT", -10, 0)
            countLbl:SetPoint("BOTTOMLEFT", 10, 8)
            countLbl:SetPoint("RIGHT", btnView, "LEFT", -10, 0)
        end
    end
    topCard:SetScript("OnSizeChanged", LayoutGroupTopBar)
    LayoutGroupTopBar()

    local listCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    listCard:SetPoint("TOPLEFT", topCard, "BOTTOMLEFT", 0, -8)
    listCard:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.listCard = listCard

    local recentSearch = Theme:CreateEditBox(listCard, {
        height = 22,
        clearButton = true,
        placeholder = L["Search companions by name or zone..."],
    })
    recentSearch:SetPoint("TOPLEFT", 8, -6)
    recentSearch:SetPoint("TOPRIGHT", -8, -6)
    recentSearch:Hide()
    recentSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    recentSearch:HookScript("OnTextChanged", function()
        if panel._view ~= "recent" then return end
        panel._recentSearchToken = (panel._recentSearchToken or 0) + 1
        local tok = panel._recentSearchToken
        if C_Timer and C_Timer.After then
            C_Timer.After(0.12, function()
                if panel:IsShown() and panel._view == "recent" and panel._recentSearchToken == tok then
                    panel:Refresh(true)
                end
            end)
        else
            panel:Refresh(true)
        end
    end)

    local scroll = Theme:CreateScrollList(listCard, 40, function(rowParent, _, rowHeight)
        local row = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
        row:SetHeight(rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.statusBar = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.statusBar:SetWidth(3)
        row.statusBar:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -4)
        row.statusBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 4)
        row.statusBar:SetColorTexture(0.35, 0.78, 1.0, 0.85)

        row.dot = row:CreateTexture(nil, "ARTWORK", nil, 2)
        row.dot:SetSize(9, 9)
        row.dot:SetPoint("LEFT", 10, 6)
        row.dot:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\dot")
        row.dot._scKeepTexture = true

        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.nameText:SetPoint("TOPLEFT", 24, -5)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)

        row.subText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.subText:SetPoint("BOTTOMLEFT", 24, 5)
        row.subText:SetJustifyH("LEFT")
        row.subText:SetWordWrap(false)

        row.btnPrimary = Theme:CreateButton(row, 80, 22, L["Whisper"], "default")
        Theme:AutoFitButton(row.btnPrimary, 72, 16, 124)
        row.btnPrimary:SetPoint("RIGHT", -8, 0)

        row.nameText:SetPoint("RIGHT", row.btnPrimary, "LEFT", -8, 0)
        row.subText:SetPoint("RIGHT", row.btnPrimary, "LEFT", -8, 0)

        row.btnPrimary:SetScript("OnClick", function()
            if not row._item then return end
            if row._mode == "current" and row._item.isMe then
                if ns.Group and ns.Group.LeaveGroup then ns.Group:LeaveGroup() end
                return
            end
            if row._item.displayName then
                local scConfirmed = ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(row._item.lookupKey or row._item.displayName, row._item.bnetAccountID)
                if scConfirmed and ns.Chat and ns.Chat.OpenDirectConversation then
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

        row:SetScript("OnClick", function(self, btn)
            if (btn == "RightButton" or btn == "LeftButton") and self._item and MenuUtil and MenuUtil.CreateContextMenu then
                local item = self._item
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(item.displayName or "")
                    if not item.isMe and item.displayName and ns.Spotter and ns.Spotter.TrackPlayer then
                        root:CreateButton(L["Track on Radar"], function()
                            ns.Spotter:TrackPlayer(item.displayName, item.guild, item.classFile, item.level, item.guid, nil)
                        end)
                    end
                    local scConfirmed = (not item.isMe) and ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(item.lookupKey or item.displayName, item.bnetAccountID)
                    if scConfirmed then
                        root:CreateButton(L["Whisper in SocialCentral"], function()
                            if ns.Chat and ns.Chat.OpenDirectConversation then
                                ns.Chat:OpenDirectConversation({
                                    targetName = item.lookupKey or item.displayName,
                                    classFile = item.classFile,
                                    autoProbe = true,
                                })
                                if ns.UI and ns.UI.OpenTab then
                                    ns.UI:OpenTab("chat")
                                end
                            elseif Compat.Whisper then
                                Compat.Whisper(item.displayName)
                            end
                        end)
                    end
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
                                if Compat.IsInRaid and Compat.IsInRaid() and ns.Group and ns.Group.ToggleAssistant then
                                    root:CreateButton(item.isAssistant and L["Demote Assistant"] or L["Promote to Assistant"], function()
                                        ns.Group:ToggleAssistant(item.unit)
                                    end)
                                end
                            end
                        end
                        root:CreateButton(L["Invite"], function()
                            Compat.Invite(item.displayName, item.bnetAccountID)
                        end)
                        root:CreateButton(L["Add to Watchlist"], function()
                            if ns.Watchlist then ns.Watchlist:Add(item.lookupKey or item.displayName) end
                        end)
                        root:CreateButton(L["Edit Social Card"], function()
                            SocialPanels:OpenSocialMetaModal(item.displayName, item.lookupKey or item.displayName)
                        end)
                        if Store and Store.SetSocialFlag then
                            local curMeta = Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(item.lookupKey or item.displayName)
                            local goodLbl = (curMeta and curMeta.flag == "GOOD") and ("|cff3fb950[x]|r " .. L["Good Partner (+)"]) or L["Good Partner (+)"]
                            local avoidLbl = (curMeta and curMeta.flag == "AVOID") and ("|cffff4d4d[x]|r " .. L["Flag: Avoid"]) or L["Flag: Avoid"]
                            root:CreateButton(goodLbl, function()
                                Store:SetSocialFlag(item.lookupKey or item.displayName, "GOOD")
                            end)
                            root:CreateButton(avoidLbl, function()
                                Store:SetSocialFlag(item.lookupKey or item.displayName, "AVOID")
                            end)
                        end
                    end
                end)
            end
        end)

        function row:RefreshTheme()
            Theme:StyleButton(self.btnPrimary, "default")
        end

        return row
    end, function(row, item, idx, pal)
        row._item = item
        row._mode = panel._view
        row.subText:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])

        local hex = Compat.ClassHex(item.classFile)
        local lvl = (item.level and item.level > 0) and (" |cff9da7b5Lv." .. item.level .. "|r") or ""
        local roleTag = ROLE_BADGES[item.role or "NONE"] or ""
        local leadTag = item.isLeader and (" |cffffd24d[" .. L["Leader"] .. "]|r") or (item.isAssistant and (" |cff58a6ff[" .. L["Assistant"] .. "]|r") or "")
        local readyTag = ""
        if item.ready == true then
            readyTag = " |cff3fb950[OK]|r"
        elseif item.ready == false then
            readyTag = " |cffff6b6b[NO]|r"
        elseif item.inCurrentGroup then
            readyTag = " |cff3fb950[" .. L["Group"] .. "]|r"
        elseif panel._view == "recent" and ns.Store and ns.Store.socialByLookup and item.lookupKey and ns.Store.socialByLookup[item.lookupKey] then
            readyTag = " |cff3fb950[" .. L["Online"] .. "]|r"
        end
        local scTag = (not item.isMe and ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(item.lookupKey or item.displayName))
            and " |cff3fb950[SC]|r" or ""
        local meta = Store and (Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(item.lookupKey or item.displayName) or Store:GetSocialMeta(item.lookupKey or item.displayName))
        local flagTag = ""
        if meta and meta.flag == "AVOID" then
            flagTag = "|cffff4d4d[" .. L["AVOID"] .. "]|r "
        elseif meta and meta.flag == "GOOD" then
            flagTag = "|cff3fb950[+]|r "
        end
        local mainTag = (meta and meta.mainName) and (" |cff6ec1e4[" .. meta.mainName .. "]|r") or ""

        row.nameText:SetText(flagTag .. hex .. (item.displayName or "") .. "|r" .. lvl .. " " .. roleTag .. leadTag .. readyTag .. scTag .. mainTag)

        local subParts = {}
        if item.zone and item.zone ~= "" then table.insert(subParts, item.zone) end
        if panel._view == "recent" and (item.runs or 0) > 1 then
            table.insert(subParts, L["%d runs"]:format(item.runs))
        end
        if meta and meta.folder then table.insert(subParts, "[" .. meta.folder .. "]") end
        if meta and meta.note then table.insert(subParts, meta.note) end
        if item.lastSeen then
            table.insert(subParts, Compat.FormatRelativeTime(item.lastSeen, L))
        end
        row.subText:SetText(table.concat(subParts, "  ·  "))

        if panel._view == "current" then
            local st = item.online ~= false and "online" or "offline"
            Theme:ApplyStatusColor(row.dot, st)
            if row.statusBar then
                Theme:ApplyStatusColor(row.statusBar, st)
                row.statusBar:SetAlpha(item.online ~= false and 0.90 or 0.25)
            end
        else
            local st = item.inCurrentGroup and "online" or "nearby"
            Theme:ApplyStatusColor(row.dot, st)
            if row.statusBar then
                Theme:ApplyStatusColor(row.statusBar, st)
                row.statusBar:SetAlpha(0.85)
            end
        end

        if panel._view == "current" and item.isMe then
            row.btnPrimary:Show()
            Theme:StyleButton(row.btnPrimary, "danger")
            Theme:SetButtonText(row.btnPrimary, L["Leave"])
        elseif not item.isMe then
            row.btnPrimary:Show()
            Theme:StyleButton(row.btnPrimary, "default")
            Theme:SetButtonText(row.btnPrimary, L["Whisper"])
        else
            row.btnPrimary:Hide()
        end

        local compactRow = (row:GetWidth() or 700) < 520
        if compactRow then
            Theme:AutoFitButton(row.btnPrimary, 56, 10, 98)
        else
            Theme:AutoFitButton(row.btnPrimary, 72, 16, 124)
        end
        row.btnPrimary:ClearAllPoints()
        row.btnPrimary:SetPoint("RIGHT", -8, 0)

        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("TOPLEFT", 24, -5)
        row.subText:ClearAllPoints()
        row.subText:SetPoint("BOTTOMLEFT", 24, 5)
        if row.btnPrimary:IsShown() then
            row.nameText:SetPoint("RIGHT", row.btnPrimary, "LEFT", -8, 0)
            row.subText:SetPoint("RIGHT", row.btnPrimary, "LEFT", -8, 0)
        else
            row.nameText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            row.subText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        end
    end)
    scroll.container:SetPoint("TOPLEFT", 6, -6)
    scroll.container:SetPoint("BOTTOMRIGHT", -6, 6)

    function panel:RefreshTheme(skipRender)
        local p = Theme:GetPalette()
        if not self:IsShown() then
            self._lastThemeKey = nil
            return
        end
        if self._lastThemeKey == p.key then
            if not skipRender and scroll then
                scroll:Render()
            end
            return
        end
        self._lastThemeKey = p.key
        Theme:ApplyBackdrop(topCard, "surface", p)
        Theme:ApplyBackdrop(listCard, "surface", p)
        Theme:StyleButton(btnView, "default")
        Theme:StyleButton(btnReady, "default")
        Theme:StyleButton(btnAnnounce, "default")
        if helpTop and helpTop.RefreshTheme then helpTop:RefreshTheme() end
        if scroll then
            scroll:RefreshTheme()
            if not skipRender then
                scroll:Render()
            end
        end
    end

    panel:HookScript("OnShow", function()
        if panel._dirty or panel._lastThemeKey ~= Theme:GetPalette().key then
            panel:Refresh(false)
        end
    end)

    function panel:Refresh(resetScroll)
        if not self:IsShown() then
            self._dirty = true
            return
        end
        self._dirty = false
        local p = Theme:GetPalette()
        self:RefreshTheme(true)
        local ch = ns.Group and ns.Group:GetChannelName()
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        local canLead = ch and ((UnitIsGroupLeader and ns.Safe.Value(UnitIsGroupLeader("player"))) or (UnitIsGroupAssistant and ns.Safe.Value(UnitIsGroupAssistant("player"))))
        btnReady:SetShown(ch ~= nil and self._view == "current")
        btnReady:SetEnabled((not inCombat) and canLead == true)
        btnAnnounce:SetEnabled(ch ~= nil)
        Theme:SetButtonText(btnView, ((self._view == "recent") and L["Recent Companions"] or L["Current Group"]) .. "  v")
        LayoutGroupTopBar()

        local showRecentSearch = (self._view == "recent")
        recentSearch:SetShown(showRecentSearch)
        scroll.container:ClearAllPoints()
        scroll.container:SetPoint("TOPLEFT", 6, showRecentSearch and -32 or -6)
        scroll.container:SetPoint("BOTTOMRIGHT", -6, 6)

        local counts = ns.Group and ns.Group:GetSummaryCounts() or { total = 0, TANK = 0, HEALER = 0, DAMAGER = 0 }
        local rQuery = showRecentSearch and (recentSearch:GetText() or "") or nil
        if self._view == "recent" then
            local allRecent = ns.Group and ns.Group:GetRecentCompanions(rQuery) or {}
            local onlineRecent = 0
            for _, rec in ipairs(allRecent) do
                if rec.inCurrentGroup or (ns.Store and ns.Store.socialByLookup and rec.lookupKey and ns.Store.socialByLookup[rec.lookupKey]) then
                    onlineRecent = onlineRecent + 1
                end
            end
            titleLbl:SetText(L["Recent Companions"])
            countLbl:SetText(string.format("%s: %d  |cff3fb950(%d %s)|r", L["Recent Companions"], #allRecent, onlineRecent, L["Online"]))
            rows = allRecent
            emptyText = (rQuery and rQuery ~= "") and L["No matching players found."] or L["No recent companions recorded yet."]
        elseif ch then
            local rcTag = ""
            if ns.Group and ns.Group.readyCheckActive and ns.Group.GetReadyCheckProgress then
                local rOk, _, _, rTot = ns.Group:GetReadyCheckProgress()
                rcTag = "  |cffffd24d[" .. string.format(L["Ready Check: %d/%d"], rOk, rTot) .. "]|r"
            end
            titleLbl:SetText(L["Active Group"] .. "  |cff3fb950[" .. ch .. "]|r" .. rcTag)
            countLbl:SetText(string.format("%s: %d  (T:%d  H:%d  D:%d)", L["Members"], counts.total, counts.TANK, counts.HEALER, counts.DAMAGER))
            rows = ns.Group and ns.Group:GetMembers() or {}
            emptyText = L["Join a Party, Raid, or Instance group to track live members and roles."]
        else
            titleLbl:SetText(L["Not currently in a Party/Raid/Instance group"])
            countLbl:SetText(L["Switch to 'Recent Companions' to re-contact past instance teammates."])
            rows = ns.Group and ns.Group:GetMembers() or {}
            emptyText = L["Join a Party, Raid, or Instance group to track live members and roles."]
        end
        countLbl:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
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
                    local rawName, rawRealm
                    if UnitFullName then
                        local okF, n, r = pcall(UnitFullName, "target")
                        if okF then
                            rawName, rawRealm = ns.Safe.String(n), ns.Safe.String(r)
                        end
                    elseif UnitName then
                        rawName, rawRealm = ns.Safe.Call(UnitName, "target")
                        rawName = ns.Safe.String(rawName)
                        rawRealm = ns.Safe.String(rawRealm)
                    end
                    if rawName and rawName ~= "" then
                        if rawRealm and rawRealm ~= "" and not rawName:find("-", 1, true) then
                            rawName = rawName .. "-" .. rawRealm
                        end
                        targetName = rawName
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
                    if item and item.online and not item.isMe then
                        local scConfirmed = ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(item.lookupKey or item.displayName, item.bnetAccountID)
                        local sc = scConfirmed and " [SC]" or ""
                        local lblItem = (item.displayName or "?") .. sc
                        root:CreateButton(lblItem, function()
                            if ns.Chat and ns.Chat.OpenDirectConversation then
                                ns.Chat:OpenDirectConversation({
                                    targetName = (item.hasCharacterName ~= false) and (item.displayName or item.lookupKey) or nil,
                                    bnetAccountID = item.bnetAccountID,
                                    bnetName = (item.sources and item.sources.bnet) and (item.bnetName or item.displayName) or nil,
                                    classFile = item.classFile,
                                    autoProbe = true,
                                })
                            end
                            input:ClearFocus()
                            m:Hide()
                        end)
                        added = added + 1
                    end
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
        { id = "all", label = L["All"] },
        { id = "unread", label = L["Unread"] },
        { id = "whispers", label = L["Whispers"] },
        { id = "guild", label = L["Guild"] },
        { id = "group", label = L["Group"] },
        { id = "alliance", label = L["Alliance"] },
        { id = "rooms", label = L["Rooms"] },
        { id = "channels", label = L["Channels"] },
    }
    local function GetFilterLabel(id)
        for _, def in ipairs(filterDefs) do
            if def.id == id then return def.label end
        end
        return L["All"]
    end

    local btnFilterMenu = Theme:CreateButton(topBar, 140, 22, L["All"] .. "  v", "default")
    btnFilterMenu:SetPoint("LEFT", topBar, "LEFT", 8, 0)
    btnFilterMenu:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(L["Filters"])
                for _, def in ipairs(filterDefs) do
                    root:CreateRadio(def.label, function()
                        return panel._filter == def.id
                    end, function()
                        panel._filter = def.id
                        panel:Refresh(true)
                    end)
                end
            end)
        else
            local idx = 1
            for i, def in ipairs(filterDefs) do
                if def.id == panel._filter then
                    idx = (i % #filterDefs) + 1
                    break
                end
            end
            panel._filter = filterDefs[idx].id
            panel:Refresh(true)
        end
    end)

    local btnUnreadQuick = Theme:CreateButton(topBar, 108, 22, L["Unread"], "danger")
    btnUnreadQuick:SetPoint("LEFT", btnFilterMenu, "RIGHT", 6, 0)
    btnUnreadQuick:SetScript("OnClick", function()
        panel._filter = (panel._filter == "unread") and "all" or "unread"
        panel:Refresh(true)
    end)
    btnUnreadQuick:SetScript("OnEnter", function(selfBtn)
        if GameTooltip then
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:SetText(panel._filter == "unread" and L["Show all conversations"] or L["Show only conversations with unread messages"], 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btnUnreadQuick:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    btnUnreadQuick:Hide()

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

    local btnNewMenu = Theme:CreateButton(topBar, 118, 22, "+ " .. L["New"] .. "  v", "primary")
    Theme:AutoFitButton(btnNewMenu, 88, 16, 155)
    btnNewMenu:SetPoint("RIGHT", helpTop, "LEFT", -6, 0)
    btnNewMenu:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateButton("+ " .. L["New 1-on-1 Chat"], OpenNewDirectChatModal)
                root:CreateButton("+ " .. L["Create Private Room"], OpenCreateRoomModal)
                root:CreateButton(L["Temp Channel"], OpenTempChannelModal)
                root:CreateDivider()
                root:CreateButton(L["Mark Read"], function()
                    if ns.Chat then ns.Chat:MarkAllRead() end
                end)
                root:CreateButton(L["Clear"], function()
                    if ns.Chat then ns.Chat:ClearHistory(ns.Chat.activeThreadKey) end
                end)
            end)
        else
            OpenNewDirectChatModal()
        end
    end)

    local function ReflowChatTopBar()
        topBar:SetHeight(34)
        local compactTop = (topBar:GetWidth() or panel:GetWidth() or 500) < 420
        local fLabel = GetFilterLabel(panel._filter)
        Theme:SetButtonText(btnFilterMenu, (compactTop and fLabel or string.format(L["Filter: %s"], fLabel)) .. "  v")
        Theme:AutoFitButton(btnFilterMenu, compactTop and 78 or 110, compactTop and 12 or 16, compactTop and 136 or 210)
        Theme:AutoFitButton(btnNewMenu, compactTop and 72 or 88, compactTop and 12 or 16, compactTop and 115 or 155)
        if btnUnreadQuick:IsShown() then
            Theme:AutoFitButton(btnUnreadQuick, compactTop and 74 or 92, compactTop and 12 or 14, compactTop and 132 or 165)
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

    local threadSearch = Theme:CreateEditBox(leftCard, {
        height = 22,
        clearButton = true,
        placeholder = L["Search conversations..."],
    })
    threadSearch:SetPoint("TOPLEFT", 6, -6)
    threadSearch:SetPoint("TOPRIGHT", -6, -6)
    threadSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    threadSearch:HookScript("OnTextChanged", function()
        panel._chatSearchToken = (panel._chatSearchToken or 0) + 1
        local tok = panel._chatSearchToken
        if C_Timer and C_Timer.After then
            C_Timer.After(0.10, function()
                if panel:IsShown() and panel._chatSearchToken == tok then
                    panel:Refresh(true)
                end
            end)
        else
            panel:Refresh(true)
        end
    end)

    local threadsScroll = Theme:CreateScrollList(leftCard, 38, function(rowParent, _, rowHeight)
        local r = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
        r:SetHeight(rowHeight)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        r.selBar = r:CreateTexture(nil, "ARTWORK", nil, 1)
        r.selBar:SetWidth(3)
        r.selBar:SetPoint("TOPLEFT", r, "TOPLEFT", 2, -4)
        r.selBar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 2, 4)
        r.selBar:Hide()

        r.unreadDot = r:CreateTexture(nil, "ARTWORK", nil, 2)
        r.unreadDot:SetSize(7, 7)
        r.unreadDot:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -8)
        r.unreadDot:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\dot")
        r.unreadDot:SetVertexColor(1.0, 0.30, 0.32, 1.0)
        r.unreadDot:Hide()

        r.unreadBadge = CreateFrame("Frame", nil, r, "BackdropTemplate")
        r.unreadBadge:SetSize(20, 15)
        r.unreadBadge:SetPoint("TOPRIGHT", r, "TOPRIGHT", -6, -4)
        r.unreadBadge:EnableMouse(false)
        if r.unreadBadge.SetBackdrop then
            r.unreadBadge:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            r.unreadBadge:SetBackdropColor(0.86, 0.16, 0.22, 1.0)
            r.unreadBadge:SetBackdropBorderColor(0.08, 0.10, 0.14, 1.0)
        end
        r.unreadBadge.text = r.unreadBadge:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        r.unreadBadge.text:SetPoint("CENTER", 0, 0)
        r.unreadBadge.text:SetTextColor(1, 1, 1)
        r.unreadBadge:Hide()

        r.title = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.title:SetPoint("TOPLEFT", 10, -5)
        r.title:SetPoint("RIGHT", -8, 0)
        r.title:SetJustifyH("LEFT")
        r.title:SetWordWrap(false)

        r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.sub:SetPoint("BOTTOMLEFT", 10, 4)
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
        r:SetScript("OnEnter", function(selfBtn)
            local it = selfBtn._item
            if not (it and GameTooltip) then return end
            GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
            GameTooltip:SetText(it.title or it.key or "?", 1, 1, 1)
            local st, stMsg = ns.Chat and ns.Chat.GetThreadAvailabilityStatus and ns.Chat:GetThreadAvailabilityStatus(it.key)
            if st then
                local stTag = (st == "DND") and L["DND"] or L["AFK"]
                local stFull = (stMsg and stMsg ~= "") and (stTag .. ": " .. stMsg) or stTag
                GameTooltip:AddLine(stFull, 1.0, 0.65, 0.25, true)
            end
            if it.preview and it.preview ~= "" then
                GameTooltip:AddLine(it.preview, 0.80, 0.85, 0.92, true)
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        return r
    end, function(r, item, idx, pal)
        r._item = item
        local isSel = ns.Chat and ns.Chat.activeThreadKey == item.key
        local hasUnread = (not item.muted and item.unread and item.unread > 0)
        Theme:ApplyBackdrop(r, (isSel or hasUnread) and "surface" or ((idx % 2 == 1) and "row" or "rowAlt"), pal)
        if hasUnread and r.SetBackdropBorderColor then
            r:SetBackdropBorderColor(0.86, 0.24, 0.28, 0.90)
        end
        if r.selBar then
            if hasUnread then
                r.selBar:SetColorTexture(0.95, 0.24, 0.28, 1.0)
                r.selBar:Show()
            elseif isSel then
                local ac = pal.accentBorder or { 0.88, 0.70, 0.25 }
                r.selBar:SetColorTexture(ac[1], ac[2], ac[3], 1.0)
                r.selBar:Show()
            else
                r.selBar:Hide()
            end
        end
        if r.unreadDot then
            r.unreadDot:SetShown(hasUnread)
        end
        if r.unreadBadge then
            if hasUnread then
                local uCount = item.unread or 0
                r.unreadBadge.text:SetText(uCount > 99 and "99+" or tostring(uCount))
                r.unreadBadge:SetWidth((uCount > 99 and 28) or (uCount > 9 and 24) or 19)
                r.unreadBadge:Show()
            else
                r.unreadBadge:Hide()
            end
        end

        r.title:ClearAllPoints()
        r.title:SetPoint("TOPLEFT", hasUnread and 18 or 10, -5)
        if hasUnread and r.unreadBadge then
            r.title:SetPoint("RIGHT", r.unreadBadge, "LEFT", -6, 0)
        else
            r.title:SetPoint("RIGHT", r, "RIGHT", -8, 0)
        end

        local tagMap = {
            WHISPER = "|cffd2a8ff[W]|r ",
            BN_WHISPER = "|cff58a6ff[BN]|r ",
            ROOM = "|cff3fb950[R]|r ",
        }
        local prefix = tagMap[item.kind] or "|cff9da7b5[C]|r "
        local st = (ns.Chat and ns.Chat.GetPeerAddonState) and ns.Chat:GetPeerAddonState(item.key) or nil
        local scTag = ""
        if item.kind ~= "ROOM" and st then
            if st.state == "verified" then
                scTag = "|cff3fb950[SC]|r "
            elseif st.state == "registered" then
                scTag = "|cff58a6ff[SC]|r "
            elseif st.knownAddon then
                scTag = "|cff8ab4f8[SC*]|r "
            end
        end
        local mutedTag = item.muted and (" |cffff9b3d[" .. L["Muted"] .. "]|r") or ""
        local availTag = ""
        if item.statusTag == "DND" then
            availTag = " |cfff54747[" .. L["DND"] .. "]|r"
        elseif item.statusTag == "AFK" then
            availTag = " |cffff9b3d[" .. L["AFK"] .. "]|r"
        end
        local hex = item.classFile and Compat.ClassHex(item.classFile) or "|cffffffff"
        r.title:SetText(prefix .. scTag .. hex .. (item.title or "") .. "|r" .. availTag .. mutedTag)

        r.sub:SetText((item.preview ~= "" and item.preview) or (Compat.FormatRelativeTime(item.lastAt, L)))
        if hasUnread then
            local tc = pal.text or { 0.95, 0.96, 0.98 }
            r.sub:SetTextColor(tc[1], tc[2], tc[3])
        else
            r.sub:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])
        end
    end)
    threadsScroll.container:SetPoint("TOPLEFT", 6, -32)
    threadsScroll.container:SetPoint("BOTTOMRIGHT", -6, 6)

    -- Right: Active conversation & composer
    local rightCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 8, 0)
    rightCard:SetPoint("BOTTOMRIGHT", 0, 0)

    local rightHdr = CreateFrame("Frame", nil, rightCard)
    rightHdr:SetPoint("TOPLEFT", 8, -6)
    rightHdr:SetPoint("TOPRIGHT", -8, -6)
    rightHdr:SetHeight(24)

    local rightHdrSep = rightCard:CreateTexture(nil, "ARTWORK", nil, 1)
    rightHdrSep:SetHeight(1)
    rightHdrSep:SetPoint("TOPLEFT", rightHdr, "BOTTOMLEFT", 0, -2)
    rightHdrSep:SetPoint("TOPRIGHT", rightHdr, "BOTTOMRIGHT", 0, -2)
    rightHdrSep:SetColorTexture(0.68, 0.54, 0.24, 0.35)

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

    local btnCopyThread = Theme:CreateButton(rightHdr, 62, 20, L["Copy"], "default")
    Theme:AutoFitButton(btnCopyThread, 56, 14, 100)
    btnCopyThread:SetPoint("RIGHT", 0, 0)
    btnCopyThread:Hide()

    local btnMarkRead = Theme:CreateButton(rightHdr, 78, 20, L["Mark Read"], "primary")
    Theme:AutoFitButton(btnMarkRead, 64, 12, 118)
    btnMarkRead:SetPoint("RIGHT", 0, 0)
    btnMarkRead:SetScript("OnClick", function()
        local k = ns.Chat and ns.Chat.activeThreadKey
        if k and ns.Chat and ns.Chat.MarkThreadRead then
            ns.Chat:MarkThreadRead(k)
        end
    end)
    btnMarkRead:Hide()

    hdrTitle:SetPoint("RIGHT", btnMuteThread, "LEFT", -8, 0)

    btnCopyThread:SetScript("OnClick", function()
        local k = ns.Chat and ns.Chat.activeThreadKey
        local act = k and ns.Chat and ns.Chat.threads and ns.Chat.threads[k]
        if not act or not (act.messages and #act.messages > 0) then return end
        local buf = {}
        for _, entry in ipairs(act.messages) do
            local ts = entry.ts and entry.ts > 0 and date("[%H:%M] ", entry.ts) or ""
            local rawTxt = tostring(entry.text or "")
            rawTxt = rawTxt:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
            table.insert(buf, ts .. (entry.sender or "") .. ": " .. rawTxt)
        end
        if ns.UI and ns.UI.OpenCopyModal then
            ns.UI:OpenCopyModal(table.concat(buf, "\n"), L["Copy Chat: %s"]:format(act.title or ""), L["Press Ctrl+C to copy the conversation log to clipboard."])
        end
    end)

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
        insertLinkMode = "full",
        placeholder = L["Select a conversation to reply..."],
    })
    replyInput:SetPoint("LEFT", 0, 0)
    replyInput:SetPoint("RIGHT", btnSend, "LEFT", -8, 0)

    local function SubmitReply()
        if not (ns.Chat and ns.Chat.activeThreadKey) then return end
        local txt = replyInput:GetText() or ""
        if ns.Chat:SendOrOpenReply(ns.Chat.activeThreadKey, txt, true) then
            replyInput:SetText("")
        end
    end
    btnSend:SetScript("OnClick", SubmitReply)
    replyInput:SetScript("OnEnterPressed", SubmitReply)
    replyInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    replyInput:HookScript("OnEditFocusGained", function()
        if ns.Chat and ns.Chat.activeThreadKey and ns.Chat.MarkThreadRead then
            ns.Chat:MarkThreadRead(ns.Chat.activeThreadKey)
        end
    end)

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
    btnOfficialDest:SetScript("OnEnter", function(selfBtn)
        local tipText = selfBtn._scFullTooltip
        if not tipText or tipText == "" then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(tipText, 1, 0.9, 0.55, 1, true)
        GameTooltip:Show()
    end)
    btnOfficialDest:SetScript("OnLeave", function()
        if GameTooltip:IsOwned(btnOfficialDest) then GameTooltip:Hide() end
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
        Theme:StyleButton(btnFilterMenu, "default")
        Theme:StyleButton(btnUnreadQuick, "danger")
        Theme:StyleButton(btnNewMenu, "primary")
        Theme:StyleButton(invAccept, "primary")
        Theme:StyleButton(invDecline, "danger")
        Theme:StyleButton(btnRoomInvite, "default")
        Theme:StyleButton(btnLeaveRoom, "danger")
        Theme:StyleButton(btnTargetCard, "default")
        Theme:StyleButton(btnPinLoc, "default")
        Theme:StyleButton(btnCopyThread, "default")
        Theme:StyleButton(btnMarkRead, "primary")
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
        panel._lastThemeKey = p.key
    end

    local function LayoutChatPanels()
        ReflowChatTopBar()
        local pw = panel:GetWidth() or 0
        if pw <= 0 then pw = 730 end

        local pending = ns.Chat and ns.Chat:GetPendingRoomInvites() or {}
        local topAnchor = (#pending > 0 and inviteBar:IsShown()) and inviteBar or topBar
        local topGap = (#pending > 0 and inviteBar:IsShown()) and -6 or -8

        leftCard:ClearAllPoints()
        rightCard:ClearAllPoints()
        if pw < 540 then
            local h = panel:GetHeight() or 0
            local topH = topBar:GetHeight() or 60
            local avail = math.max(200, h - topH - 16)
            local leftH = math.max(122, math.min(168, math.floor(avail * 0.40)))
            leftCard:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, topGap)
            leftCard:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", 0, topGap)
            leftCard:SetHeight(leftH)

            rightCard:SetPoint("TOPLEFT", leftCard, "BOTTOMLEFT", 0, -6)
            rightCard:SetPoint("BOTTOMRIGHT", 0, 0)
        else
            local leftW = math.max(205, math.min(288, math.floor(pw * 0.31)))
            leftCard:SetWidth(leftW)
            leftCard:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, topGap)
            leftCard:SetPoint("BOTTOMLEFT", 0, 0)

            rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 8, 0)
            rightCard:SetPoint("BOTTOMRIGHT", 0, 0)
        end
    end
    panel:SetScript("OnSizeChanged", LayoutChatPanels)

    function panel:Refresh(resetScroll)
        local p = Theme:GetPalette()
        local themeChanged = (panel._lastThemeKey ~= p.key)
        if themeChanged then
            self:RefreshTheme()
        end

        local unreadDirect = ns.Chat and ((ns.Chat.GetUnreadDirectCount and ns.Chat:GetUnreadDirectCount()) or (ns.Chat.GetTotalUnread and ns.Chat:GetTotalUnread(false))) or 0
        local showQuickUnread = (unreadDirect > 0) or (self._filter == "unread")
        btnUnreadQuick:SetShown(showQuickUnread)
        if showQuickUnread then
            local uLabel = unreadDirect > 0 and string.format("%s (%d)", L["Unread"], unreadDirect) or L["Unread"]
            Theme:SetButtonText(btnUnreadQuick, uLabel)
            Theme:SetButtonActive(btnUnreadQuick, self._filter == "unread", "danger")
        end
        ReflowChatTopBar()

        local pending = ns.Chat and ns.Chat:GetPendingRoomInvites() or {}
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
        else
            inviteBar:Hide()
        end
        LayoutChatPanels()

        local threads = ns.Chat and ns.Chat:GetThreadsList(self._filter) or {}
        local tQuery = threadSearch and threadSearch:GetText() or ""
        if tQuery ~= "" then
            local qLow = tQuery:lower()
            local filtered = {}
            for _, th in ipairs(threads) do
                local hay = ((th.title or "") .. " " .. (th.preview or "")):lower()
                if hay:find(qLow, 1, true) then
                    filtered[#filtered + 1] = th
                end
            end
            threads = filtered
        end
        if ns.Chat and (not ns.Chat.activeThreadKey or not ns.Chat.threads[ns.Chat.activeThreadKey]) and #threads > 0 then
            ns.Chat:SetActiveThread(threads[1].key, (threads[1].unread or 0) > 0)
        end
        local emptyMsg = (tQuery ~= "" and L["No matching conversations found."])
            or (self._filter == "unread" and L["No unread conversations right now."])
            or L["No conversations yet. Whispers, group chats, and Private Rooms appear here."]
        threadsScroll:SetData(threads, emptyMsg, resetScroll)

        local activeKey = ns.Chat and ns.Chat.activeThreadKey
        local active = activeKey and ns.Chat.threads[activeKey]
        local lines = active and active.messages or nil
        local lineCount = lines and #lines or 0
        local delivSig = ""
        if active and lines and lineCount > 0 then
            local startScan = math.max(1, lineCount - 7)
            for i = startScan, lineCount do
                local ent = lines[i]
                if ent and not ent.incoming and ent.viaAddon then
                    delivSig = delivSig .. i .. ":" .. tostring(ent.deliveryState or "") .. ";"
                end
            end
        end
        local needMsgRebuild = themeChanged or resetScroll
            or panel._renderedMsgActiveKey ~= activeKey
            or panel._renderedMsgNil ~= (active == nil)
            or panel._renderedMsgCount ~= lineCount
            or (lines and (panel._renderedMsgFirst ~= lines[1] or panel._renderedMsgLast ~= lines[lineCount]))
            or panel._renderedMsgDelivSig ~= delivSig
        if needMsgRebuild then
            panel._renderedMsgActiveKey = activeKey
            panel._renderedMsgNil = (active == nil)
            panel._renderedMsgCount = lineCount
            panel._renderedMsgFirst = lines and lines[1] or nil
            panel._renderedMsgLast = (lines and lineCount > 0) and lines[lineCount] or nil
            panel._renderedMsgDelivSig = delivSig
            msgFrame:Clear()
        end

        if active then
            local isRoom = active.kind == "ROOM"
            local isDirect = (active.kind == "WHISPER" or active.kind == "BN_WHISPER")
            local pState = (ns.Chat and ns.Chat.GetPeerAddonState) and ns.Chat:GetPeerAddonState(activeKey) or { state = "none", verified = isRoom }
            local isMuted = ns.Chat and ns.Chat:IsThreadMuted(activeKey)
            local activeUnread = (not isMuted and active.unread) or 0
            local room = isRoom and ns.Chat:GetRoom(active.roomId)
            local memberCount = 0
            if room and room.members then
                for _ in pairs(room.members) do memberCount = memberCount + 1 end
            end
            local unreadHdrTag = (activeUnread > 0) and ("  |cffff5555[" .. string.format(L["%d unread"], activeUnread) .. "]|r") or ""
            local availState = ns.Chat and ns.Chat.GetThreadAvailabilityStatus and ns.Chat:GetThreadAvailabilityStatus(activeKey)
            local availHdrTag = (availState == "DND" and ("  |cfff54747[" .. L["DND"] .. "]|r"))
                or (availState == "AFK" and ("  |cffff9b3d[" .. L["AFK"] .. "]|r"))
                or ""
            hdrTitle:SetText((active.title or "") .. (isRoom and ("  |cff3fb950[" .. memberCount .. "]|r") or "") .. availHdrTag .. unreadHdrTag)

            btnRoomInvite:SetShown(isRoom)
            btnLeaveRoom:SetShown(isRoom)
            btnTargetCard:SetShown(active.kind == "WHISPER" and active.targetName ~= nil)
            btnPinLoc:SetShown(not isRoom and isDirect and pState.verified == true)
            btnMarkRead:SetShown(activeUnread > 0)
            btnMuteThread:Show()
            btnCopyThread:SetShown(type(active.messages) == "table" and #active.messages > 0)
            Theme:SetButtonText(btnMuteThread, isMuted and L["Muted"] or L["Mute"])
            Theme:SetButtonActive(btnMuteThread, isMuted, "default")

            local compactRight = (rightCard:GetWidth() or panel:GetWidth() or 500) < 430
            if compactRight then
                Theme:AutoFitButton(btnLeaveRoom, 46, 10, 92)
                Theme:AutoFitButton(btnRoomInvite, 46, 10, 96)
                Theme:AutoFitButton(btnTargetCard, 46, 10, 90)
                Theme:AutoFitButton(btnPinLoc, 46, 10, 98)
                Theme:AutoFitButton(btnMarkRead, 56, 10, 108)
                Theme:AutoFitButton(btnMuteThread, 46, 12, 108)
                Theme:AutoFitButton(btnCopyThread, 44, 10, 84)
            else
                Theme:AutoFitButton(btnLeaveRoom, 60, 16, 110)
                Theme:AutoFitButton(btnRoomInvite, 72, 16, 120)
                Theme:AutoFitButton(btnTargetCard, 66, 16, 115)
                Theme:AutoFitButton(btnPinLoc, 72, 14, 124)
                Theme:AutoFitButton(btnMarkRead, 68, 14, 124)
                Theme:AutoFitButton(btnMuteThread, 64, 16, 120)
                Theme:AutoFitButton(btnCopyThread, 56, 14, 100)
            end

            local orderedRight = {}
            if btnLeaveRoom:IsShown() then table.insert(orderedRight, btnLeaveRoom) end
            if btnRoomInvite:IsShown() then table.insert(orderedRight, btnRoomInvite) end
            if btnMarkRead:IsShown() then table.insert(orderedRight, btnMarkRead) end
            if btnTargetCard:IsShown() then table.insert(orderedRight, btnTargetCard) end
            if btnPinLoc:IsShown() then table.insert(orderedRight, btnPinLoc) end
            if btnCopyThread:IsShown() then table.insert(orderedRight, btnCopyThread) end
            if btnMuteThread:IsShown() then table.insert(orderedRight, btnMuteThread) end
            local rightGap = compactRight and -4 or -6
            local prevR
            for _, rb in ipairs(orderedRight) do
                rb:ClearAllPoints()
                if not prevR then
                    rb:SetPoint("RIGHT", rightHdr, "RIGHT", 0, 0)
                else
                    rb:SetPoint("RIGHT", prevR, "LEFT", rightGap, 0)
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
            elseif pState.state == "registered" then
                local verTag = pState.version and ("v" .. pState.version) or "OK"
                peerStatusText:SetText("|cff58a6ff[SocialCentral " .. verTag .. " · " .. L["Registered"] .. "]|r  " .. L["In-addon direct chat ready"])
            elseif pState.verified then
                local verTag = pState.version and ("v" .. pState.version) or "OK"
                peerStatusText:SetText("|cff3fb950[SocialCentral " .. verTag .. "]|r  " .. L["Both players verified — in-addon direct chat active"])
            elseif pState.state == "checking" then
                peerStatusText:SetText("|cffffd24d[" .. L["Checking SocialCentral..."] .. "]|r")
            elseif pState.state == "disabled" then
                peerStatusText:SetText("|cffff9b3d[" .. L["In-addon direct chat disabled in Settings"] .. "]|r")
            elseif pState.state == "offline" then
                if pState.knownAddon then
                    local verStr = pState.version and ("v" .. pState.version .. " · ") or ""
                    peerStatusText:SetText("|cff8ab4f8[SocialCentral " .. verStr .. L["Offline"] .. "]|r  " .. L["Registered user — in-addon chat resumes automatically when online"])
                else
                    peerStatusText:SetText("|cff9da7b5[" .. L["Offline or out of addon range"] .. "]|r")
                end
            elseif pState.state == "channel" then
                peerStatusText:SetText("|cff58a6ff[" .. L["Official WoW Channel"] .. "]|r  " .. (pState.slash or ""))
            else
                peerStatusText:SetText("|cff9da7b5[" .. L["WoW Whisper (/w)"] .. "]|r  " .. L["SocialCentral not detected on peer"])
            end

            -- Unified composer bar (direct in-addon packets when verified, instant WoW /w or channel reply otherwise)
            local isAlliance = (activeKey == "ch:alliance")
            officialBar:Hide()
            composer:Show()
            if isRoom or pState.verified or isAlliance then
                if ns.Chat and ns.Chat.focusInputPending then
                    ns.Chat.focusInputPending = nil
                    if replyInput and replyInput.SetFocus then
                        replyInput:SetFocus()
                    end
                end
                Theme:SetButtonText(btnSend, L["Send"])
                Theme:AutoFitButton(btnSend, 74, 18, 125)
                btnSend:SetEnabled(true)
                if replyInput.SetPlaceholder then
                    replyInput:SetPlaceholder(isAlliance
                        and L["Type in-addon alliance message and press Enter..."]
                        or (isRoom and L["Type message to Private Room and press Enter..."]
                        or L["Type in-addon direct message and press Enter..."]))
                end
            else
                local destInfo = (ns.Chat and ns.Chat.GetOfficialDestinationInfo) and ns.Chat:GetOfficialDestinationInfo(activeKey)
                local btnLabel = (destInfo and destInfo.compactButtonText) or L["WoW Whisper (/w)"]
                Theme:SetButtonText(btnSend, btnLabel)
                Theme:AutoFitButton(btnSend, 84, 14, 196)
                btnSend:SetEnabled(destInfo ~= nil)
                if replyInput.SetPlaceholder then
                    replyInput:SetPlaceholder((destInfo and destInfo.buttonText) or L["Select a conversation to reply..."])
                end
            end
            replyInput:ClearAllPoints()
            replyInput:SetPoint("LEFT", 0, 0)
            replyInput:SetPoint("RIGHT", btnSend, "LEFT", -8, 0)
            if ns.Chat and ns.Chat.pendingDraftText then
                local draft = ns.Chat.pendingDraftText
                ns.Chat.pendingDraftText = nil
                replyInput:SetText(draft)
                if replyInput.SetCursorPosition then
                    replyInput:SetCursorPosition(#draft)
                end
                if replyInput.SetFocus then
                    replyInput:SetFocus()
                end
            end

            if needMsgRebuild then
                if #lines == 0 then
                    msgFrame:AddMessage(L["No messages yet."], p.textMuted[1], p.textMuted[2], p.textMuted[3])
                else
                    for _, entry in ipairs(lines) do
                        local ts = entry.ts and entry.ts > 0 and date("|cff9da7b5[%H:%M]|r ", entry.ts) or ""
                        if entry.isStatusNotice then
                            local sCol = (entry.statusKind == "DND") and "|cfff54747" or "|cffff9b3d"
                            msgFrame:AddMessage(ts .. sCol .. "[" .. (entry.sender or L["Status"]) .. "]|r |cffb8c2d0" .. (entry.text or "") .. "|r")
                        else
                            local addonTag = (entry.viaAddon and not isRoom) and "|cff3fb950[SC]|r " or ""
                            local tick = ""
                            if not entry.incoming and entry.viaAddon and not isRoom then
                                if entry.deliveryState == "delivered" then
                                    tick = " |cff3fb950[" .. L["ok"] .. "]|r"
                                elseif entry.deliveryState == "off" or entry.deliveryState == "declined" then
                                    tick = " |cfff54747[" .. L["off"] .. "]|r"
                                else
                                    tick = " |cff9da7b5[" .. L["sent"] .. "]|r"
                                end
                            end
                            local hex = entry.classFile and Compat.ClassHex(entry.classFile) or (entry.incoming and "|cffd2a8ff" or "|cff58a6ff")
                            msgFrame:AddMessage(ts .. addonTag .. hex .. (entry.sender or "") .. "|r: " .. (entry.text or "") .. tick)
                        end
                    end
                end
                if msgFrame.ScrollToBottom then
                    msgFrame:ScrollToBottom()
                end
            end
        else
            hdrTitle:SetText(L["Select a conversation or create a Private Room"])
            peerStatusText:SetText("")
            btnVerify:Hide()
            btnRoomInvite:Hide()
            btnLeaveRoom:Hide()
            btnTargetCard:Hide()
            btnPinLoc:Hide()
            btnCopyThread:Hide()
            btnMarkRead:Hide()
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
            if needMsgRebuild then
                msgFrame:AddMessage(L["Use '+ Chat' for 1-on-1 verified addon chat or '+ Room' for group rooms."], p.textMuted[1], p.textMuted[2], p.textMuted[3])
            end
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

    local buffViews = {
        { id = "all", label = L["All Buffs"] },
        { id = "active", label = L["My Buffs"] },
        { id = "history", label = L["Drop History"] },
    }
    local function GetBuffViewLabel(id)
        for _, v in ipairs(buffViews) do
            if v.id == id then return v.label end
        end
        return L["All Buffs"]
    end

    local btnViewMode = Theme:CreateButton(topCard, 136, 22, L["All Buffs"] .. "  v", "default")
    Theme:AutoFitButton(btnViewMode, 116, 16, 195)
    btnViewMode:SetPoint("BOTTOMRIGHT", -8, 6)
    btnViewMode:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                for _, v in ipairs(buffViews) do
                    root:CreateRadio(v.label, function()
                        return panel._view == v.id
                    end, function()
                        panel._view = v.id
                        panel:Refresh(true)
                    end)
                end
            end)
        else
            local idx = 1
            for i, v in ipairs(buffViews) do
                if v.id == panel._view then
                    idx = (i % #buffViews) + 1
                    break
                end
            end
            panel._view = buffViews[idx].id
            panel:Refresh(true)
        end
    end)
    panel.btnViewMode = btnViewMode

    titleLbl:SetPoint("RIGHT", btnAnnounce, "LEFT", -10, 0)
    countLbl:SetPoint("RIGHT", btnViewMode, "LEFT", -10, 0)

    local function LayoutBuffsTopBar()
        local w = topCard:GetWidth() or panel:GetWidth() or 0
        if w <= 0 then w = 730 end
        local compact = w < 540
        Theme:SetButtonText(btnViewMode, GetBuffViewLabel(panel._view) .. "  v")
        titleLbl:ClearAllPoints()
        countLbl:ClearAllPoints()
        if compact then
            Theme:AutoFitButton(btnViewMode, 96, 10, 175)
            Theme:AutoFitButton(btnAnnounce, 76, 10, 140)

            titleLbl:SetPoint("TOPLEFT", topCard, "TOPLEFT", 10, -7)
            titleLbl:SetPoint("RIGHT", helpTop, "LEFT", -6, 0)
            countLbl:SetPoint("TOPLEFT", topCard, "TOPLEFT", 10, -27)
            countLbl:SetPoint("TOPRIGHT", topCard, "TOPRIGHT", -10, -27)

            local rows = LayoutButtonFlow(topCard, { btnViewMode, btnAnnounce }, 8, -46, w - 16, 24, 4)
            topCard:SetHeight(rows == 1 and 78 or (46 + rows * 24 + 6))
        else
            topCard:SetHeight(64)
            Theme:AutoFitButton(btnAnnounce, 102, 16, 160)
            Theme:AutoFitButton(btnViewMode, 116, 16, 195)

            btnAnnounce:ClearAllPoints()
            btnAnnounce:SetPoint("RIGHT", helpTop, "LEFT", -6, 0)
            btnViewMode:ClearAllPoints()
            btnViewMode:SetPoint("BOTTOMRIGHT", -8, 6)

            titleLbl:SetPoint("TOPLEFT", 10, -8)
            titleLbl:SetPoint("RIGHT", btnAnnounce, "LEFT", -10, 0)
            countLbl:SetPoint("BOTTOMLEFT", 10, 8)
            countLbl:SetPoint("RIGHT", btnViewMode, "LEFT", -10, 0)
        end
    end
    topCard:SetScript("OnSizeChanged", LayoutBuffsTopBar)
    LayoutBuffsTopBar()

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

        row.activeBar = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.activeBar:SetWidth(3)
        row.activeBar:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -4)
        row.activeBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 4)

        row.iconFrame = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.iconFrame:SetSize(38, 38)
        row.iconFrame:SetPoint("LEFT", 9, 0)
        row.iconFrame:SetColorTexture(0.45, 0.36, 0.18, 0.95)

        row.icon = row:CreateTexture(nil, "ARTWORK", nil, 2)
        row.icon:SetSize(34, 34)
        row.icon:SetPoint("CENTER", row.iconFrame, "CENTER", 0, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

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

        local texture = item.icon or (item.def and item.def.icon) or 132333
        row.icon:SetTexture(texture)

        local isActive = item.isActive
        local remStr = item.remaining and ns.WorldBuffs and ns.WorldBuffs:FormatDuration(item.remaining) or ""

        if isActive then
            local activeBadge = " |cff3fb950[" .. L["Active"] .. (remStr ~= "" and (" - " .. remStr) or "") .. "]|r"
            row.title:SetText("|cffffd200" .. item.name .. "|r" .. activeBadge)
            row.btnReport:Show()
            Theme:SetButtonText(row.btnReport, L["Report"])
            if row.activeBar then row.activeBar:SetColorTexture(0.24, 0.88, 0.46, 0.95) end
            if row.iconFrame then row.iconFrame:SetColorTexture(0.24, 0.88, 0.46, 1.0) end
        else
            local inactiveBadge = " |cff8b949e[" .. L["Inactive"] .. "]|r"
            row.title:SetText("|cffffffff" .. item.name .. "|r" .. inactiveBadge)
            row.btnReport:Hide()
            if row.activeBar then row.activeBar:SetColorTexture(0.50, 0.42, 0.24, 0.25) end
            if row.iconFrame then row.iconFrame:SetColorTexture(0.42, 0.34, 0.20, 0.70) end
        end
        if row._lastActiveAnchor ~= isActive then
            row._lastActiveAnchor = isActive
            row.title:ClearAllPoints()
            row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
            row.effect:ClearAllPoints()
            row.effect:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
            row.source:ClearAllPoints()
            row.source:SetPoint("TOPLEFT", row.effect, "BOTTOMLEFT", 0, -2)
            if isActive then
                row.title:SetPoint("RIGHT", row.btnReport, "LEFT", -8, 0)
                row.effect:SetPoint("RIGHT", row.btnReport, "LEFT", -8, 0)
                row.source:SetPoint("RIGHT", row.btnReport, "LEFT", -8, 0)
            else
                row.title:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                row.effect:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                row.source:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            end
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
            elseif cdStatus.status == "NO_COOLDOWN" then
                dropNote = "|cff58a6ff[" .. cdStatus.text .. "]|r"
            elseif cdStatus.status == "SCHEDULED" or cdStatus.status == "OPEN_WORLD" then
                dropNote = "|cff8cb8e8[" .. cdStatus.text .. "]|r"
            elseif lastDrop and lastDrop > 0 then
                dropNote = L["Last drop detected: %s"]:format(Compat.FormatRelativeTime(lastDrop, L))
            end
            if cdStatus.peakText and cdStatus.peakText ~= "" then
                dropNote = (dropNote ~= "" and (dropNote .. "  ·  ") or "") .. "|cff56d364" .. cdStatus.peakText .. "|r"
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
    scroll.container:SetFrameLevel((listCard:GetFrameLevel() or 1) + 2)
    scroll.container:ClearAllPoints()
    scroll.container:SetPoint("TOPLEFT", listCard, "TOPLEFT", 6, -6)
    scroll.container:SetPoint("BOTTOMRIGHT", listCard, "BOTTOMRIGHT", -6, 6)
    panel.scroll = scroll

    function panel:RefreshTheme()
        local pal = Theme:GetPalette()
        Theme:ApplyBackdrop(topCard, "header", pal)
        Theme:ApplyBackdrop(listCard, "inset", pal)
        Theme:ApplyBackdrop(dropBanner, "surface", pal)
        Theme:StyleButton(btnAnnounce, "default")
        Theme:StyleButton(btnViewMode, "default")
        if scroll.RefreshTheme then scroll:RefreshTheme() end
        scroll:Render()
        panel._lastThemeKey = pal.key
    end

    function panel:Refresh(resetScroll)
        LayoutBuffsTopBar()
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

        local readyCount = 0
        if ns.WorldBuffs and ns.WorldBuffs.GetDropCooldownStatus then
            for _, def in ipairs(allDefs) do
                if def.yellDelay and def.yellDelay > 0 then
                    local st = ns.WorldBuffs:GetDropCooldownStatus(def)
                    if st and st.status == "READY" then
                        readyCount = readyCount + 1
                    end
                end
            end
        end
        countLbl:SetText(L["%d / %d Active · %d Capital Drops Ready · Open World & Dungeons"]:format(#activeList, #allDefs, readyCount))

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
        if panel._lastThemeKey ~= Theme:GetPalette().key then
            self:RefreshTheme()
        end
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

----------------------------------------------------------------------
-- Character Equipment, Bags, Bank & Account Alts Panel (2D Items Only)
----------------------------------------------------------------------

local SLOT_INFO_NAMES = {
    [1] = "HeadSlot",
    [2] = "NeckSlot",
    [3] = "ShoulderSlot",
    [4] = "ShirtSlot",
    [5] = "ChestSlot",
    [6] = "WaistSlot",
    [7] = "LegsSlot",
    [8] = "FeetSlot",
    [9] = "WristSlot",
    [10] = "HandsSlot",
    [11] = "Finger0Slot",
    [12] = "Finger1Slot",
    [13] = "Trinket0Slot",
    [14] = "Trinket1Slot",
    [15] = "BackSlot",
    [16] = "MainHandSlot",
    [17] = "SecondaryHandSlot",
    [18] = "RangedSlot",
    [19] = "TabardSlot",
}

local QUALITY_FALLBACK = {
    [0] = { 0.62, 0.62, 0.62 },
    [1] = { 0.85, 0.85, 0.85 },
    [2] = { 0.12, 1.00, 0.00 },
    [3] = { 0.00, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 },
    [5] = { 1.00, 0.50, 0.00 },
    [6] = { 0.90, 0.80, 0.50 },
}

local function GetQualityRGB(quality)
    local q = tonumber(quality) or 1
    local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if qc and qc.r and qc.g and qc.b then
        return qc.r, qc.g, qc.b
    end
    local fb = QUALITY_FALLBACK[q] or QUALITY_FALLBACK[1]
    return fb[1], fb[2], fb[3]
end

local function ExtractLinkName(link)
    if type(link) ~= "string" then return "" end
    return link:match("%[(.-)%]") or ""
end

local function ShowItemTooltip(anchor, itemData, slotId)
    if not GameTooltip then return end
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    if itemData and itemData.link then
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, itemData.link)
        if ok then
            GameTooltip:Show()
            return
        end
    elseif itemData and itemData.itemID then
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. tostring(itemData.itemID))
        if ok then
            GameTooltip:Show()
            return
        end
    end
    if slotId and SLOT_INFO_NAMES[slotId] then
        GameTooltip:SetText(SLOT_INFO_NAMES[slotId]:gsub("Slot$", ""), 1, 0.82, 0)
    else
        GameTooltip:SetText(L["Empty Slot"], 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

function SocialPanels:CreateAltsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel:Hide()
    panel._bagSource = "all" -- "all" | "equip" | "bags" | "bank"
    panel._selectedKey = Compat.CharacterKey()
    panel._userPickedAlt = false

    local function GetSelectedAlt()
        local myKey = Compat.CharacterKey()
        local list = Store and Store:GetAltsList() or {}
        local preferred, fallback
        for _, rec in ipairs(list) do
            if rec.key == panel._selectedKey then
                return rec, list
            end
            if rec.key == myKey then
                preferred = rec
            elseif not fallback then
                fallback = rec
            end
        end
        local chosen = preferred or fallback
        if chosen then
            panel._selectedKey = chosen.key
        end
        return chosen, list
    end

    -- Row 1: Character Selector + Help (cleanly clearing portrait and top-right settings icon)
    local topBar = CreateFrame("Frame", nil, panel)
    topBar:SetHeight(26)
    panel.topBar = topBar

    local charBtn = Theme:CreateButton(topBar, 168, 22, "...", "default")
    charBtn:SetPoint("LEFT", 0, 0)

    local charHelpBtn = AddHelp(
        topBar,
        charBtn,
        L["Help: Select Character & Armory"],
        L["Switches between your recorded characters on this WoW Forever realm pool to inspect equipped gear, bags, bank, professions, and gold."],
        L["Click to pick any saved character on this server or copy their Web Armory profile URL."],
        "LEFT",
        "RIGHT",
        4,
        0
    )

    -- Row 2: Search + Equipment/Bag Filter + Help + Count (cleanly below the 32px stone header strip)
    local searchBar = CreateFrame("Frame", nil, panel)
    searchBar:SetHeight(24)
    searchBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -36)
    searchBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -36)

    local bagSearch = Theme:CreateEditBox(searchBar, {
        width = 156,
        height = 22,
        placeholder = L["Search items..."],
        clearButton = true,
    })
    bagSearch:SetPoint("LEFT", 0, 0)

    local filterBtn = Theme:CreateButton(searchBar, 96, 22, L["All"] .. "  v", "default")
    filterBtn:SetPoint("LEFT", bagSearch, "RIGHT", 6, 0)

    local helpBtn = AddHelp(
        searchBar,
        filterBtn,
        L["Help: Equipped Gear, Bags & Alts"],
        L["Displays equipped items, bags, bank snapshots, gold, and account alts in a lightweight 2D item grid."],
        L["Select any character on this server or use the filter dropdown ('All', 'Equipped', 'Bags', 'Bank'), search by item name, or copy Web Armory link inside the character menu."],
        "LEFT",
        "RIGHT",
        4,
        0
    )

    local infoLbl = searchBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoLbl:SetPoint("LEFT", helpBtn or filterBtn, "RIGHT", 8, 0)
    infoLbl:SetPoint("RIGHT", searchBar, "RIGHT", -2, 0)
    infoLbl:SetJustifyH("RIGHT")
    infoLbl:SetWordWrap(false)

    -- Right Column: Character Dossier Card (full professions, stats, zone, hearthstone, inventory & gold)
    local dossierCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    dossierCard:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -64)
    dossierCard:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)
    dossierCard:SetWidth(238)
    Theme:ApplyBackdrop(dossierCard, "inset")
    panel._dossierCard = dossierCard

    -- Header strip inside Dossier Card
    local dossierHeader = CreateFrame("Frame", nil, dossierCard)
    dossierHeader:SetPoint("TOPLEFT", dossierCard, "TOPLEFT", 2, -2)
    dossierHeader:SetPoint("TOPRIGHT", dossierCard, "TOPRIGHT", -2, -2)
    dossierHeader:SetHeight(26)

    local dossierHdrBg = dossierHeader:CreateTexture(nil, "BACKGROUND", nil, -6)
    dossierHdrBg:SetAllPoints()
    dossierHdrBg:SetTexture(WHITE8X8)
    dossierHdrBg:SetVertexColor(0.14, 0.11, 0.08, 1.0)
    dossierHeader._bg = dossierHdrBg

    local dossierHdrLine = dossierHeader:CreateTexture(nil, "ARTWORK", nil, 1)
    dossierHdrLine:SetHeight(1)
    dossierHdrLine:SetPoint("BOTTOMLEFT", dossierHeader, "BOTTOMLEFT", 0, 0)
    dossierHdrLine:SetPoint("BOTTOMRIGHT", dossierHeader, "BOTTOMRIGHT", 0, 0)
    dossierHdrLine:SetTexture(WHITE8X8)
    dossierHdrLine:SetVertexColor(0.65, 0.50, 0.22, 0.85)

    local dossierHelpBtn = AddHelp(
        dossierHeader,
        dossierHeader,
        L["Help: Character Dossier & Gold Summary"],
        L["Summarizes the selected character's Level, Race, Class, Professions, Zone, Hearthstone Bind, XP/Rested status, Equipped Gear, Character Gold, and Total Server Gold."],
        L["Switch characters at the top dropdown to compare Alts, Professions, Inventory, and Server Gold totals across your entire realm pool."],
        "RIGHT",
        "RIGHT",
        -4,
        0
    )

    local dossierTitleLbl = dossierHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dossierTitleLbl:SetPoint("LEFT", dossierHeader, "LEFT", 8, 0)
    dossierTitleLbl:SetPoint("RIGHT", dossierHelpBtn, "LEFT", -6, 0)
    dossierTitleLbl:SetJustifyH("LEFT")
    dossierTitleLbl:SetWordWrap(false)

    -- Gold Vault Footer strip at bottom of Dossier Card (2 crisp rows: Character Gold + Total Server Gold)
    local goldBar = CreateFrame("Frame", nil, dossierCard)
    goldBar:SetPoint("BOTTOMLEFT", dossierCard, "BOTTOMLEFT", 2, 2)
    goldBar:SetPoint("BOTTOMRIGHT", dossierCard, "BOTTOMRIGHT", -2, 2)
    goldBar:SetHeight(40)

    local goldBarBg = goldBar:CreateTexture(nil, "BACKGROUND", nil, -6)
    goldBarBg:SetAllPoints()
    goldBarBg:SetTexture(WHITE8X8)
    goldBarBg:SetVertexColor(0.15, 0.12, 0.06, 1.0)
    goldBar._bg = goldBarBg

    local goldBarLine = goldBar:CreateTexture(nil, "ARTWORK", nil, 1)
    goldBarLine:SetHeight(1)
    goldBarLine:SetPoint("TOPLEFT", goldBar, "TOPLEFT", 0, 0)
    goldBarLine:SetPoint("TOPRIGHT", goldBar, "TOPRIGHT", 0, 0)
    goldBarLine:SetTexture(WHITE8X8)
    goldBarLine:SetVertexColor(0.75, 0.58, 0.22, 0.90)

    local dossierCharGoldLbl = goldBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dossierCharGoldLbl:SetPoint("TOPLEFT", goldBar, "TOPLEFT", 8, -5)
    dossierCharGoldLbl:SetJustifyH("LEFT")
    dossierCharGoldLbl:SetWordWrap(false)

    local dossierCharGoldVal = goldBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dossierCharGoldVal:SetPoint("TOPRIGHT", goldBar, "TOPRIGHT", -8, -5)
    dossierCharGoldVal:SetJustifyH("RIGHT")
    dossierCharGoldVal:SetWordWrap(false)
    dossierCharGoldLbl:SetPoint("RIGHT", dossierCharGoldVal, "LEFT", -6, 0)

    local dossierTotalGoldLbl = goldBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dossierTotalGoldLbl:SetPoint("TOPLEFT", goldBar, "TOPLEFT", 8, -21)
    dossierTotalGoldLbl:SetJustifyH("LEFT")
    dossierTotalGoldLbl:SetWordWrap(false)

    local dossierTotalGoldVal = goldBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dossierTotalGoldVal:SetPoint("TOPRIGHT", goldBar, "TOPRIGHT", -8, -21)
    dossierTotalGoldVal:SetJustifyH("RIGHT")
    dossierTotalGoldVal:SetWordWrap(false)
    dossierTotalGoldLbl:SetPoint("RIGHT", dossierTotalGoldVal, "LEFT", -6, 0)

    -- Scrollable Middle Dossier Body (renders ALL professions + character info cleanly without overflow)
    local dossierScroll = CreateFrame("ScrollFrame", nil, dossierCard)
    dossierScroll:SetPoint("TOPLEFT", dossierHeader, "BOTTOMLEFT", 6, -4)
    dossierScroll:SetPoint("BOTTOMRIGHT", goldBar, "TOPRIGHT", -6, 4)
    dossierScroll:SetClipsChildren(true)
    dossierScroll:EnableMouseWheel(true)

    local dossierContent = CreateFrame("Frame", nil, dossierScroll)
    dossierContent:SetPoint("TOPLEFT", 0, 0)
    dossierContent:SetSize(220, 200)
    dossierScroll:SetScrollChild(dossierContent)

    local dossierRows = {}
    local dossierSeps = {}
    local dossierMaxScroll = 0

    local function UpdateDossierScrollBounds()
        local vpH = dossierScroll:GetHeight() or 0
        local contentH = dossierContent:GetHeight() or 0
        dossierMaxScroll = math.max(0, contentH - vpH)
        local cur = dossierScroll:GetVerticalScroll() or 0
        if cur > dossierMaxScroll then
            dossierScroll:SetVerticalScroll(dossierMaxScroll)
        end
        local vpW = dossierScroll:GetWidth() or 220
        if vpW > 40 then
            dossierContent:SetWidth(vpW)
        end
    end

    dossierScroll:SetScript("OnMouseWheel", function(selfScroll, delta)
        if dossierMaxScroll <= 0 then return end
        local cur = selfScroll:GetVerticalScroll() or 0
        local nxt = math.max(0, math.min(dossierMaxScroll, cur - delta * 20))
        selfScroll:SetVerticalScroll(nxt)
    end)
    dossierScroll:SetScript("OnSizeChanged", UpdateDossierScrollBounds)

    local function AcquireDossierRow(idx)
        if not dossierRows[idx] then
            local row = CreateFrame("Frame", nil, dossierContent)
            row:SetHeight(16)
            local lLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lLbl:SetPoint("TOPLEFT", row, "TOPLEFT", 2, 0)
            lLbl:SetJustifyH("LEFT")
            lLbl:SetWordWrap(false)
            local rLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, 0)
            rLbl:SetJustifyH("RIGHT")
            rLbl:SetWordWrap(false)
            lLbl:SetPoint("RIGHT", rLbl, "LEFT", -6, 0)
            row.left = lLbl
            row.right = rLbl
            dossierRows[idx] = row
        end
        return dossierRows[idx]
    end

    local function AcquireDossierSep(idx)
        if not dossierSeps[idx] then
            local sep = dossierContent:CreateTexture(nil, "ARTWORK", nil, 1)
            sep:SetHeight(1)
            sep:SetTexture(WHITE8X8)
            sep:SetVertexColor(0.55, 0.44, 0.20, 0.45)
            dossierSeps[idx] = sep
        end
        return dossierSeps[idx]
    end

    -- Left Column: Unified 2D Item Grid (Equipped, Bags & Bank)
    local mainCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    mainCard:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -64)
    mainCard:SetPoint("BOTTOMRIGHT", dossierCard, "BOTTOMLEFT", -6, 0)
    Theme:ApplyBackdrop(mainCard, "inset")
    panel._mainCard = mainCard

    local bagGridScroll = Theme:CreateScrollList(mainCard, 40, function(rowParent, _, rowHeight)
        local row = CreateFrame("Frame", nil, rowParent)
        row:SetHeight(rowHeight)

        local headerTitle = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        headerTitle:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 8)
        headerTitle:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 8)
        headerTitle:SetJustifyH("LEFT")
        headerTitle:SetWordWrap(false)
        headerTitle:Hide()
        row._headerTitle = headerTitle

        local headerLine = row:CreateTexture(nil, "ARTWORK")
        headerLine:SetHeight(1)
        headerLine:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 4)
        headerLine:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 4)
        headerLine:SetTexture(WHITE8X8)
        headerLine:SetVertexColor(0.55, 0.44, 0.20, 0.75)
        headerLine:Hide()
        row._headerLine = headerLine

        row._cells = {}
        for c = 1, 18 do
            local cell = CreateFrame("Button", nil, row, "BackdropTemplate")
            cell:SetSize(34, 34)
            cell._scNoStone = true
            Theme:ApplyBackdrop(cell, "inset")

            local tex = cell:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", 2, -2)
            tex:SetPoint("BOTTOMRIGHT", -2, 2)
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            cell.icon = tex

            local hl = cell:CreateTexture(nil, "HIGHLIGHT")
            hl:SetPoint("TOPLEFT", 2, -2)
            hl:SetPoint("BOTTOMRIGHT", -2, 2)
            hl:SetColorTexture(1, 0.92, 0.65, 0.16)
            hl:SetBlendMode("ADD")

            local eqLbl = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            eqLbl:SetPoint("TOPLEFT", 3, -2)
            eqLbl:SetText("|cffffd200E|r")
            eqLbl:Hide()
            cell.eqLbl = eqLbl

            local countLbl = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            countLbl:SetPoint("BOTTOMRIGHT", -2, 2)
            countLbl:SetJustifyH("RIGHT")
            cell.countLbl = countLbl

            cell:SetScript("OnEnter", function(self)
                if self._item then
                    ShowItemTooltip(self, self._item, self._item._slotId)
                end
            end)
            cell:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
            cell:SetScript("OnClick", function(self)
                if self._item and self._item.link and IsModifiedClick and IsModifiedClick("CHATLINK") then
                    if ChatEdit_InsertLink then
                        ChatEdit_InsertLink(self._item.link)
                    end
                end
            end)
            cell:Hide()
            row._cells[c] = cell
        end
        return row
    end, function(row, rowData)
        if rowData.isHeader then
            row._headerTitle:SetText(rowData.title or "")
            row._headerTitle:Show()
            row._headerLine:Show()
            for c = 1, 18 do
                local cell = row._cells[c]
                cell._item = nil
                cell:Hide()
            end
            return
        end

        row._headerTitle:Hide()
        row._headerLine:Hide()

        local cols = rowData.cols or 7
        for c = 1, 18 do
            local cell = row._cells[c]
            local item = rowData.items and rowData.items[c]
            if c <= cols and item then
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", row, "LEFT", 4 + (c - 1) * 38, 0)
                cell.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local r, g, b = GetQualityRGB(item.quality)
                cell:SetBackdropBorderColor(r, g, b, 1.0)
                if item._isEquip then
                    cell.eqLbl:Show()
                else
                    cell.eqLbl:Hide()
                end
                cell.countLbl:SetText((item.count and item.count > 1) and tostring(item.count) or "")
                cell._item = item
                cell:Show()
            else
                cell._item = nil
                cell:Hide()
            end
        end
    end)
    bagGridScroll.container:SetFrameLevel((mainCard:GetFrameLevel() or 1) + 2)
    bagGridScroll.container:ClearAllPoints()
    bagGridScroll.container:SetPoint("TOPLEFT", mainCard, "TOPLEFT", 4, -4)
    bagGridScroll.container:SetPoint("BOTTOMRIGHT", mainCard, "BOTTOMRIGHT", -4, 4)

    local function GetFilterButtonLabel(altData)
        if panel._bagSource == "all_alts" then
            return L["All Characters"] .. "  v"
        elseif panel._bagSource == "equip" then
            return L["Equipped"] .. "  v"
        elseif panel._bagSource == "bags" then
            local used = altData and math.max(0, (altData.bagTotal or 0) - (altData.bagFree or 0)) or 0
            local total = altData and (altData.bagTotal or 0) or 0
            return (L["Bags"] .. " (%d/%d)  v"):format(used, total)
        elseif panel._bagSource == "bank" then
            local used = altData and math.max(0, (altData.bankTotal or 0) - (altData.bankFree or 0)) or 0
            local total = altData and (altData.bankTotal or 0) or 0
            return (L["Bank"] .. " (%d/%d)  v"):format(used, total)
        end
        return L["All"] .. "  v"
    end

    local function AppendGlobalSearchSections(sections, queryText, excludeAltKey, headingPrefix)
        if not (ns.Alts and ns.Alts.SearchAllItems) then return end
        local groups = ns.Alts:SearchAllItems(queryText, excludeAltKey)
        for _, g in ipairs(groups) do
            local hex = Compat.ClassHex(g.classFile)
            local lbl = headingPrefix
                and ("|cff8ab4f8" .. headingPrefix .. "|r " .. hex .. (g.displayName or "?") .. "|r |cffc6ceda(" .. #g.items .. ")|r")
                or (hex .. (g.displayName or "?") .. "|r |cffc6ceda(" .. #g.items .. ")|r")
            sections[#sections + 1] = {
                title = lbl,
                items = g.items,
            }
        end
    end

    local function CollectFilteredItems(altData)
        if not altData then return {}, "" end
        local src = panel._bagSource or "all"
        local query = Compat.Trim(bagSearch:GetText() or ""):lower()

        if src == "all_alts" then
            local sections = {}
            AppendGlobalSearchSections(sections, query, nil, nil)
            if #sections == 0 then
                return {}, (query ~= "" and L["No matching items found across any character."] or L["No items recorded yet."])
            end
            return sections, ""
        end

        local function MatchesQuery(item)
            if query == "" then return true end
            local iName = ExtractLinkName(item.link):lower()
            local slotLabel = (item._slotId and SLOT_INFO_NAMES[item._slotId] or ""):lower()
            return iName:find(query, 1, true) ~= nil or (slotLabel ~= "" and slotLabel:find(query, 1, true) ~= nil)
        end

        local sections = {}

        if (src == "all" or src == "equip") and type(altData.equipment) == "table" then
            panel._equipItemWrappers = panel._equipItemWrappers or {}
            local equipItems = {}
            for slotId = 1, 19 do
                local entry = altData.equipment[slotId]
                if entry and (entry.icon or entry.itemID or entry.link) then
                    local obj = panel._equipItemWrappers[slotId]
                    if not obj then
                        obj = { count = 1, _isEquip = true, _slotId = slotId }
                        panel._equipItemWrappers[slotId] = obj
                    end
                    obj.icon = entry.icon
                    obj.link = entry.link
                    obj.itemID = entry.itemID
                    obj.quality = entry.quality
                    if MatchesQuery(obj) then
                        equipItems[#equipItems + 1] = obj
                    end
                end
            end
            if #equipItems > 0 then
                sections[#sections + 1] = {
                    title = ("|cffffd200%s|r |cffc6ceda(%d)|r"):format(L["Equipped"], #equipItems),
                    items = equipItems,
                }
            end
        end

        if (src == "all" or src == "bags") and type(altData.bags) == "table" then
            local bagItems = {}
            for _, item in ipairs(altData.bags) do
                if MatchesQuery(item) then
                    bagItems[#bagItems + 1] = item
                end
            end
            if #bagItems > 0 then
                local bagUsed = math.max(0, (altData.bagTotal or 0) - (altData.bagFree or 0))
                local bagCap = (altData.bagTotal or 0) > 0 and altData.bagTotal or #bagItems
                sections[#sections + 1] = {
                    title = ("|cffffd200%s|r |cffc6ceda(%d/%d)|r"):format(L["Bags"], bagUsed, bagCap),
                    items = bagItems,
                }
            end
        end

        if (src == "all" or src == "bank") and type(altData.bank) == "table" then
            local bankItems = {}
            for _, item in ipairs(altData.bank) do
                if MatchesQuery(item) then
                    bankItems[#bankItems + 1] = item
                end
            end
            if #bankItems > 0 then
                sections[#sections + 1] = {
                    title = ("|cffffd200%s|r |cffc6ceda(%d)|r"):format(L["Bank"], #bankItems),
                    items = bankItems,
                }
            end
        end

        if #sections == 0 then
            if query ~= "" then
                AppendGlobalSearchSections(sections, query, altData.key, L["Other Alt:"])
                if #sections > 0 then
                    return sections, ""
                end
                return {}, L["No matching items found."]
            elseif src == "bank" and type(altData.bank) ~= "table" then
                return {}, L["Visit a Bank NPC to snapshot bank items."]
            end
            return {}, L["No bag snapshot recorded yet."]
        end

        return sections, ""
    end

    local function CountEquippedSlots(equipment)
        if type(equipment) ~= "table" then return 0 end
        local n = 0
        for slotId = 1, 19 do
            local entry = equipment[slotId]
            if entry and (entry.icon or entry.itemID or entry.link) then
                n = n + 1
            end
        end
        return n
    end

    local function UpdateDossierCard(altData, resetDossierScroll)
        dossierCard._altData = altData
        for i = 1, #dossierRows do dossierRows[i]:Hide() end
        for i = 1, #dossierSeps do dossierSeps[i]:Hide() end

        if not altData then
            dossierTitleLbl:SetText(L["No characters recorded yet."])
            dossierCharGoldLbl:SetText("")
            dossierCharGoldVal:SetText("")
            dossierTotalGoldLbl:SetText("")
            dossierTotalGoldVal:SetText("")
            dossierContent:SetHeight(20)
            UpdateDossierScrollBounds()
            return
        end

        local hex = Compat.ClassHex(altData.classFile)
        local displayName = altData.fullName or altData.name or altData.key or "?"
        dossierTitleLbl:SetText(("%s%s|r"):format(hex, displayName))

        local rowIdx = 0
        local sepIdx = 0
        local yOff = 0

        local function AddDossierLine(leftTxt, rightTxt, lr, lg, lb, rr, rg, rb, stepH)
            rowIdx = rowIdx + 1
            local row = AcquireDossierRow(rowIdx)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", dossierContent, "TOPLEFT", 0, -yOff)
            row:SetPoint("TOPRIGHT", dossierContent, "TOPRIGHT", 0, -yOff)
            row.left:SetText(leftTxt or "")
            row.left:SetTextColor(lr or 0.78, lg or 0.80, lb or 0.86)
            row.right:SetText(rightTxt or "")
            row.right:SetTextColor(rr or 1.0, rg or 1.0, rb or 1.0)
            row:Show()
            yOff = yOff + (stepH or 16)
        end

        local function AddDossierSep()
            sepIdx = sepIdx + 1
            local sep = AcquireDossierSep(sepIdx)
            sep:ClearAllPoints()
            sep:SetPoint("TOPLEFT", dossierContent, "TOPLEFT", 2, -(yOff + 3))
            sep:SetPoint("TOPRIGHT", dossierContent, "TOPRIGHT", -2, -(yOff + 3))
            sep:Show()
            yOff = yOff + 8
        end

        local lvl = tonumber(altData.level) or 0
        local classLoc = altData.className
            or (altData.classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[altData.classFile])
            or altData.classFile
            or ""
        local raceLoc = altData.raceName or ""
        local raceClass = (raceLoc ~= "" and classLoc ~= "") and (raceLoc .. " " .. classLoc) or (classLoc ~= "" and classLoc or raceLoc)
        local facLbl = altData.faction == "Alliance" and L["Alliance"] or (altData.faction == "Horde" and L["Horde"] or "")
        local fr, fg, fb = 0.72, 0.82, 0.96
        if altData.faction == "Alliance" then
            fr, fg, fb = 0.45, 0.72, 1.00
        elseif altData.faction == "Horde" then
            fr, fg, fb = 0.78, 0.85, 0.96
        end
        AddDossierLine(("%s %d · %s"):format(L["Level"], lvl, raceClass), facLbl, 1.0, 0.85, 0.30, fr, fg, fb, 17)

        if altData.guild and altData.guild ~= "" then
            AddDossierLine(L["Guild"], "<" .. altData.guild .. ">", 0.75, 0.78, 0.85, 0.35, 0.92, 0.55, 16)
        end

        if altData.itemLevel and altData.itemLevel > 0 then
            AddDossierLine("Item Level", tostring(math.floor(altData.itemLevel)), 0.75, 0.78, 0.85, 0.35, 0.92, 0.55, 16)
        end

        if lvl >= 60 then
            AddDossierLine(L["Experience"], L["Max Level"], 0.75, 0.78, 0.85, 0.35, 0.92, 0.55, 16)
        else
            local xpVal = tonumber(altData.xp) or 0
            local xpMaxVal = math.max(1, tonumber(altData.xpMax) or 1)
            local xpPct = math.min(100, math.floor((xpVal / xpMaxVal) * 100 + 0.5))
            local restedVal = tonumber(altData.rested) or 0
            local restedMaxCap = (restedVal > 0 and xpMaxVal > 1 and (restedVal / xpMaxVal) >= 1.48)
            local restedBadge = restedMaxCap and (" |cff58a6ff[" .. L["150% MAX"] .. "]|r") or ""
            local xpTxt = restedVal > 0 and ("%d%% (+%s)%s"):format(xpPct, L["Rested"], restedBadge) or ("%d%%"):format(xpPct)
            local xr, xg, xb = restedVal > 0 and 0.45 or 0.90, restedVal > 0 and 0.76 or 0.92, restedVal > 0 and 1.0 or 0.95
            AddDossierLine(L["Experience"], xpTxt, 0.75, 0.78, 0.85, xr, xg, xb, 16)
        end

        AddDossierSep()
        AddDossierLine(L["Professions"], "", 1.0, 0.82, 0.0, 1.0, 0.82, 0.0, 17)

        local profs = altData.professions
        if type(profs) == "table" and #profs > 0 then
            local primaryList, secondaryList = {}, {}
            for _, pr in ipairs(profs) do
                if pr and pr.name and pr.name ~= "" then
                    if pr.isPrimary then
                        primaryList[#primaryList + 1] = pr
                    else
                        secondaryList[#secondaryList + 1] = pr
                    end
                end
            end
            for _, pr in ipairs(primaryList) do
                local rankStr = (pr.maxRank and pr.maxRank > 0) and ("%d / %d"):format(pr.rank or 0, pr.maxRank) or tostring(pr.rank or 0)
                AddDossierLine("  " .. pr.name, rankStr, 0.90, 0.92, 0.96, 0.35, 0.92, 0.55, 16)
            end
            for _, pr in ipairs(secondaryList) do
                local rankStr = (pr.maxRank and pr.maxRank > 0) and ("%d / %d"):format(pr.rank or 0, pr.maxRank) or tostring(pr.rank or 0)
                AddDossierLine("  " .. pr.name, rankStr, 0.86, 0.88, 0.92, 0.35, 0.92, 0.55, 16)
            end
        else
            AddDossierLine("  " .. L["No professions learned"], "", 0.62, 0.65, 0.70, 0.62, 0.65, 0.70, 16)
        end

        AddDossierSep()

        local zoneTxt = (altData.zone and altData.zone ~= "") and altData.zone or "-"
        AddDossierLine(L["Zone"], zoneTxt, 0.75, 0.78, 0.85, 1.0, 1.0, 1.0, 16)

        local bindTxt = (altData.bindLocation and altData.bindLocation ~= "") and altData.bindLocation or "-"
        if ns.Alts and ns.Alts.GetHearthstoneStatus and altData.bindLocation and altData.bindLocation ~= "" then
            local hsReadyAt, hsRem = ns.Alts:GetHearthstoneStatus(altData)
            if hsReadyAt ~= nil then
                if hsRem and hsRem > 1 then
                    local hsCdTxt = hsRem >= 60 and ("%dm"):format(math.ceil(hsRem / 60)) or ("%ds"):format(hsRem)
                    bindTxt = bindTxt .. " |cffff9b3d[" .. hsCdTxt .. "]|r"
                else
                    bindTxt = bindTxt .. " |cff3fb950[" .. L["Ready"] .. "]|r"
                end
            end
        end
        AddDossierLine(L["Hearthstone"], bindTxt, 0.75, 0.78, 0.85, 0.65, 0.88, 1.0, 16)

        local eqCount = CountEquippedSlots(altData.equipment)
        local bagFreeVal = tonumber(altData.bagFree) or 0
        local bagCap = altData.bagTotal or 0
        local bagUsed = math.max(0, bagCap - bagFreeVal)
        local bagText = ("%d / %d"):format(bagUsed, bagCap)
        local bagR, bagG, bagB = 0.92, 0.94, 0.96
        if bagCap > 0 and bagFreeVal <= 2 then
            local bagTagCol = (bagFreeVal <= 1) and "|cfff54747" or "|cffff9b3d"
            bagText = bagText .. " " .. bagTagCol .. "(" .. L["%d free"]:format(bagFreeVal) .. ")|r"
            if bagFreeVal <= 1 then bagR, bagG, bagB = 0.96, 0.30, 0.30 else bagR, bagG, bagB = 1.0, 0.65, 0.24 end
        end

        local bankTxt = "-"
        if type(altData.bank) == "table" then
            bankTxt = ("%d %s"):format(#altData.bank, L["items"])
            if altData.bankUpdatedAt and altData.bankUpdatedAt > 0 then
                bankTxt = bankTxt .. " · " .. Compat.FormatRelativeTime(altData.bankUpdatedAt, L)
            end
        end

        AddDossierLine(L["Equipped"], tostring(eqCount), 0.75, 0.78, 0.85, 0.92, 0.94, 0.96, 16)
        AddDossierLine(L["Bags"], bagText, 0.75, 0.78, 0.85, bagR, bagG, bagB, 16)
        AddDossierLine(L["Bank"], bankTxt, 0.75, 0.78, 0.85, type(altData.bank) == "table" and 0.92 or 0.58, type(altData.bank) == "table" and 0.94 or 0.62, type(altData.bank) == "table" and 0.96 or 0.68, 16)

        if altData.hasMail then
            local mailStr = "|cffffd24d[" .. L["Pending Mail"] .. "]|r"
            if type(altData.mailSenders) == "table" and #altData.mailSenders > 0 then
                mailStr = mailStr .. " " .. table.concat(altData.mailSenders, ", ")
            end
            AddDossierLine(L["Mailbox"], mailStr, 0.75, 0.78, 0.85, 1.0, 0.82, 0.30, 16)
        end

        if altData.key ~= Compat.CharacterKey() and altData.lastActive then
            AddDossierLine(L["Last Seen"], Compat.FormatRelativeTime(altData.lastActive, L), 0.58, 0.62, 0.68, 0.58, 0.62, 0.68, 16)
        end

        dossierContent:SetHeight(math.max(20, yOff + 2))
        if resetDossierScroll then
            dossierScroll:SetVerticalScroll(0)
        end
        UpdateDossierScrollBounds()

        local shortChar = altData.firstName or altData.name or displayName
        local charGold = Compat.FormatMoney(altData.money or 0)
        local totGold = Compat.FormatMoney((Store and Store.GetTotalAltsGold and Store:GetTotalAltsGold(true)) or (altData.money or 0))
        dossierCharGoldLbl:SetText(("|cffffd200%s|r"):format(L["Gold (%s)"]:format(shortChar)))
        dossierCharGoldVal:SetText(charGold)
        dossierTotalGoldLbl:SetText(("|cffffd200%s|r"):format(L["Total Server Gold"]))
        dossierTotalGoldVal:SetText(totGold)
    end

    local function RenderItems(altData, resetScroll)
        UpdateDossierCard(altData, resetScroll)
        if not altData then
            infoLbl:SetText("")
            bagGridScroll:SetData({}, L["No characters recorded yet."], true)
            return
        end

        Theme:SetButtonText(filterBtn, GetFilterButtonLabel(altData))
        Theme:AutoFitButton(filterBtn, 78, 18, 148)

        local sections, emptyMsg = CollectFilteredItems(altData)
        local shownCount = 0
        for _, sec in ipairs(sections) do
            shownCount = shownCount + #sec.items
        end
        if shownCount > 0 then
            infoLbl:SetText(L["%d items"]:format(shownCount))
        else
            infoLbl:SetText("")
        end

        local vpW = (bagGridScroll.viewport and bagGridScroll.viewport.GetWidth and bagGridScroll.viewport:GetWidth()) or 0
        if vpW < 100 then
            local pw = panel:GetWidth() or 580
            local dw = (panel._dossierCard and panel._dossierCard.GetWidth and panel._dossierCard:GetWidth()) or 238
            vpW = math.max(160, pw - dw - 44)
        end
        local cols = math.max(4, math.min(18, math.floor((vpW - 8) / 38)))
        local rows = {}
        for _, sec in ipairs(sections) do
            table.insert(rows, { isHeader = true, title = sec.title })
            for i = 1, #sec.items, cols do
                local chunk = {}
                for j = 0, cols - 1 do
                    if sec.items[i + j] then
                        chunk[j + 1] = sec.items[i + j]
                    end
                end
                table.insert(rows, { cols = cols, items = chunk })
            end
        end
        bagGridScroll:SetData(rows, emptyMsg, resetScroll)
        panel._lastRenderedW = math.floor(panel:GetWidth() or 0)
        panel._lastRenderedCols = cols
    end

    bagSearch:HookScript("OnTextChanged", function()
        panel._searchToken = (panel._searchToken or 0) + 1
        local token = panel._searchToken
        if C_Timer and C_Timer.After then
            C_Timer.After(0.10, function()
                if panel:IsShown() and panel._searchToken == token then
                    local altData = GetSelectedAlt()
                    RenderItems(altData, true)
                end
            end)
        else
            local altData = GetSelectedAlt()
            RenderItems(altData, true)
        end
    end)

    filterBtn:SetScript("OnClick", function(self)
        local opts = {
            { id = "all", label = L["All"] },
            { id = "all_alts", label = L["All Characters"] },
            { id = "equip", label = L["Equipped"] },
            { id = "bags", label = L["Bags"] },
            { id = "bank", label = L["Bank"] },
        }
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                for _, o in ipairs(opts) do
                    root:CreateRadio(o.label, function()
                        return panel._bagSource == o.id
                    end, function()
                        panel._bagSource = o.id
                        local altData = GetSelectedAlt()
                        RenderItems(altData, true)
                    end)
                end
            end)
        else
            local idx = 1
            for i, o in ipairs(opts) do
                if o.id == panel._bagSource then
                    idx = (i % #opts) + 1
                    break
                end
            end
            panel._bagSource = opts[idx].id
            local altData = GetSelectedAlt()
            RenderItems(altData, true)
        end
    end)

    charBtn:SetScript("OnClick", function(self)
        local selectedAlt, list = GetSelectedAlt()
        if #list == 0 then return end
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(L["Select Character"])
                for _, rec in ipairs(list) do
                    local hex = Compat.ClassHex(rec.classFile)
                    local lbl = ("%s%s|r"):format(hex, rec.fullName or rec.name or rec.key)
                    root:CreateRadio(lbl, function()
                        return panel._selectedKey == rec.key
                    end, function()
                        panel._userPickedAlt = true
                        panel._selectedKey = rec.key
                        panel:Refresh(true)
                    end)
                end
                if selectedAlt then
                    root:CreateDivider()
                    root:CreateButton(L["Web Armory Link"], function()
                        local url = ns.Alts and ns.Alts:GetArmoryURL(selectedAlt)
                        if url and ns.UI and ns.UI.OpenCopyModal then
                            ns.UI:OpenCopyModal(url, L["Web Armory Link"], L["Blizzard's addon sandbox prohibits external internet requests. Copy this link to open your Web Armory in a browser:"])
                        end
                    end)
                end
            end)
        else
            local idx = 1
            for i, rec in ipairs(list) do
                if rec.key == panel._selectedKey then
                    idx = (i % #list) + 1
                    break
                end
            end
            panel._userPickedAlt = true
            panel._selectedKey = list[idx].key
            panel:Refresh(true)
        end
    end)

    function panel:RefreshTheme(skipRender)
        Theme:StyleButton(charBtn, "default")
        Theme:StyleButton(filterBtn, "default")
        Theme:AutoFitButton(filterBtn, 78, 18, 148)
        if charHelpBtn and charHelpBtn.RefreshTheme then charHelpBtn:RefreshTheme() end
        if helpBtn and helpBtn.RefreshTheme then helpBtn:RefreshTheme() end
        if dossierHelpBtn and dossierHelpBtn.RefreshTheme then dossierHelpBtn:RefreshTheme() end
        if panel._dossierCard then
            Theme:ApplyBackdrop(panel._dossierCard, "inset")
        end
        if bagGridScroll and bagGridScroll.RefreshTheme then
            bagGridScroll:RefreshTheme()
            if not skipRender then
                bagGridScroll:Render()
            end
        end
    end

    local function RelayoutAltsPanel()
        local isEmbeddedChar = (CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown())
            and ((not ns.UI or not ns.UI.IsEmbeddedFor) or ns.UI:IsEmbeddedFor(CharacterFrame))
        local w = math.floor((panel:GetWidth() or 560) + 0.5)
        local p = Theme:GetPalette()
        local layoutSig = (isEmbeddedChar and "E:" or "M:") .. w .. ":" .. tostring(p and p.key or "dark")
        if panel._lastLayoutSig == layoutSig then
            return
        end
        panel._lastLayoutSig = layoutSig

        local portraitPad = (isEmbeddedChar or w < 520) and 54 or 4
        local rightPad = isEmbeddedChar and ((w < 540) and -34 or -114) or -4
        local topY = isEmbeddedChar and -3 or 0
        topBar:ClearAllPoints()
        topBar:SetPoint("TOPLEFT", panel, "TOPLEFT", portraitPad, topY)
        topBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", rightPad, topY)

        searchBar:ClearAllPoints()
        searchBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -36)
        searchBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -36)

        local topAvail = math.max(140, w - portraitPad + rightPad)
        local charW = math.max(110, math.min(240, topAvail - 28))
        charBtn:SetWidth(charW)

        local searchW = (w >= 540) and 164 or math.max(110, math.floor(w * 0.28))
        bagSearch:SetWidth(searchW)
        Theme:AutoFitButton(filterBtn, 78, 18, 148)

        if panel._mainCard then
            Theme:ApplyBackdrop(panel._mainCard, "inset")
        end
        if panel._dossierCard then
            local dossierW = math.max(216, math.min(282, math.floor(w * 0.40)))
            panel._dossierCard:SetWidth(dossierW)
            dossierContent:SetWidth(math.max(180, dossierW - 16))
            Theme:ApplyBackdrop(panel._dossierCard, "inset", p)
            if p and p.key == "blizzard" then
                dossierHdrBg:SetVertexColor(0.18, 0.14, 0.09, 1.0)
                goldBarBg:SetVertexColor(0.20, 0.15, 0.07, 1.0)
            elseif p and p.key == "native" then
                dossierHdrBg:SetVertexColor(0.13, 0.11, 0.09, 1.0)
                goldBarBg:SetVertexColor(0.15, 0.12, 0.06, 1.0)
            else
                dossierHdrBg:SetVertexColor(0.12, 0.13, 0.16, 1.0)
                goldBarBg:SetVertexColor(0.14, 0.12, 0.07, 1.0)
            end
            UpdateDossierScrollBounds()
        end
    end

    local isRefreshing = false

    function panel:Refresh(resetScroll)
        if isRefreshing then return end
        if not self:IsShown() then
            self._dirty = true
            return
        end
        self._dirty = false
        isRefreshing = true
        RelayoutAltsPanel()

        local myKey = Compat.CharacterKey()
        if not panel._userPickedAlt then
            panel._selectedKey = myKey
        end

        if panel._selectedKey == myKey and ns.Alts and ns.Alts.Snapshot then
            pcall(ns.Alts.Snapshot, ns.Alts, false)
        end

        local altData = GetSelectedAlt()
        if altData then
            local charLabel = (altData.fullName or altData.name or altData.key) .. "  v"
            Theme:SetButtonText(charBtn, charLabel)
        else
            Theme:SetButtonText(charBtn, L["Select Character"])
        end

        RenderItems(altData, resetScroll)
        self:RefreshTheme(true)
        isRefreshing = false
    end

    panel:SetScript("OnShow", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if panel:IsShown() then
                    if panel._dirty then
                        panel:Refresh(false)
                    else
                        RelayoutAltsPanel()
                        local curW = math.floor((panel:GetWidth() or 0) + 0.5)
                        if not panel._lastRenderedW or math.abs(curW - panel._lastRenderedW) >= 2 then
                            local altData = GetSelectedAlt()
                            RenderItems(altData, false)
                        end
                    end
                end
            end)
        end
    end)

    panel:SetScript("OnHide", function()
        panel._userPickedAlt = false
    end)

    panel:SetScript("OnSizeChanged", function()
        if not panel:IsShown() then return end
        panel._resizeToken = (panel._resizeToken or 0) + 1
        local token = panel._resizeToken
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function()
                if panel:IsShown() and panel._resizeToken == token then
                    RelayoutAltsPanel()
                    local curW = math.floor((panel:GetWidth() or 0) + 0.5)
                    if not panel._lastRenderedW or math.abs(curW - panel._lastRenderedW) >= 2 then
                        local altData = GetSelectedAlt()
                        RenderItems(altData, false)
                    end
                end
            end)
        else
            RelayoutAltsPanel()
            local altData = GetSelectedAlt()
            RenderItems(altData, false)
        end
    end)

    if ns.On then
        ns:On("ALTS_UPDATED", function()
            if panel:IsShown() and not isRefreshing then
                panel:Refresh(false)
            end
        end)
    end

    panel:RefreshTheme()
    return panel
end
