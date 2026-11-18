local _, ns = ...

local L = ns.L
local Theme = ns.Theme
local Compat = ns.Compat
local Store = ns.Store
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"

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
    LEATHERWORKING = L["Leatherworking"],
    MINING = L["Mining"],
    SKINNING = L["Skinning"],
    TAILORING = L["Tailoring"],
    FISHING = L["Fishing"],
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

local DEFAULT_FOLDER_PRESETS = { "Dungeons", "Raid", "PvP", "Craft" }

function SocialPanels:OpenSocialMetaModal(displayName, rawKey, contextItem)
    local socialEntry = (ns.Social and ns.Social.GetDirectoryEntry and ns.Social:GetDirectoryEntry(rawKey or displayName)) or nil
    local dirEntry = socialEntry or contextItem or nil

    local charKey = nil
    if dirEntry and dirEntry.lookupKey and dirEntry.lookupKey ~= "" then
        charKey = dirEntry.lookupKey
    elseif contextItem and contextItem.lookupKey and contextItem.lookupKey ~= "" then
        charKey = contextItem.lookupKey
    elseif type(rawKey) == "string" and rawKey ~= "" then
        charKey = rawKey
    elseif type(displayName) == "string" and displayName ~= "" then
        charKey = displayName
    end

    local bnetAccountID = (dirEntry and dirEntry.bnetAccountID) or (contextItem and contextItem.bnetAccountID) or nil
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
            Theme:SetButtonActive(btnFlagGood, m._pendingFlag == "GOOD", "primary")
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
        local myAlt = (Store and Store.GetCurrentAltRecord and Store:GetCurrentAltRecord())
            or (Compat.CharacterKey and ns.db.alts[Compat.CharacterKey()])
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
    if not createRoomModal then
        local m = CreateFrame("Frame", "SocialCentralCreateRoomModal", UIParent, "BackdropTemplate")
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
    if not tempChannelModal then
        local m = CreateFrame("Frame", "SocialCentralTempChanModal", UIParent, "BackdropTemplate")
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
    if not roomInviteModal then
        local m = CreateFrame("Frame", "SocialCentralRoomInvModal", UIParent, "BackdropTemplate")
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
                local rKey = row._item.lookupKey or row._item.displayName
                local bInfo = ns.Social and ns.Social.GetBNetLinkInfo and ns.Social:GetBNetLinkInfo(rKey)
                local isCrossFac = (row._item.sameFaction == false) or (bInfo and bInfo.sameFaction == false)
                local bnetName = row._item.bnetName or (bInfo and bInfo.bnetName)
                local chatModOn = (not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("chat")
                local scConfirmed = chatModOn and ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(rKey, row._item.bnetAccountID or (bInfo and bInfo.bnetAccountID))
                if scConfirmed and ns.Chat and ns.Chat.OpenDirectConversation then
                    ns.Chat:OpenDirectConversation({
                        targetName = rKey,
                        classFile = row._item.classFile,
                        autoProbe = true,
                    })
                    if ns.UI and ns.UI.OpenTab then
                        ns.UI:OpenTab("chat")
                    end
                elseif isCrossFac and bnetName and Compat.BNetWhisper then
                    Compat.BNetWhisper(bnetName, row._item.displayName)
                else
                    Compat.Whisper(row._item.displayName)
                end
            end
        end)

        row:SetScript("OnClick", function(self, btn)
            if (btn == "RightButton" or btn == "LeftButton") and self._item and MenuUtil and MenuUtil.CreateContextMenu then
                local item = self._item
                local rKey = item.lookupKey or item.displayName
                local bInfo = (rKey and ns.Social and ns.Social.GetBNetLinkInfo) and ns.Social:GetBNetLinkInfo(rKey) or nil
                local isCrossFac = (item.sameFaction == false) or (bInfo and bInfo.sameFaction == false)
                local bnetName = item.bnetName or (bInfo and bInfo.bnetName)
                local bnetId = item.bnetAccountID or (bInfo and bInfo.bnetAccountID)
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(item.displayName or "")
                    local radarModOn = (not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("radar")
                    local chatModOn = (not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("chat")
                    if radarModOn and not item.isMe and item.displayName and ns.Spotter and ns.Spotter.TrackPlayer then
                        local isTracked = ns.Spotter.IsPlayerTracked and ns.Spotter:IsPlayerTracked(item.displayName, item.guid)
                        if isTracked and ns.Spotter.UntrackPlayer then
                            root:CreateButton(L["Untrack from Radar"], function()
                                ns.Spotter:UntrackPlayer(item.displayName, item.guid)
                            end)
                        else
                            root:CreateButton(L["Track on Radar"], function()
                                ns.Spotter:TrackPlayer(item.displayName, item.guild, item.classFile, item.level, item.guid, nil)
                            end)
                        end
                    end
                    local scConfirmed = chatModOn and (not item.isMe) and ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(rKey, bnetId)
                    if scConfirmed then
                        root:CreateButton(L["Whisper in SocialCentral"], function()
                            if ns.Chat and ns.Chat.OpenDirectConversation then
                                ns.Chat:OpenDirectConversation({
                                    targetName = rKey,
                                    classFile = item.classFile,
                                    autoProbe = true,
                                })
                                if ns.UI and ns.UI.OpenTab then
                                    ns.UI:OpenTab("chat")
                                end
                            elseif isCrossFac and bnetName and Compat.BNetWhisper then
                                Compat.BNetWhisper(bnetName, item.displayName)
                            elseif Compat.Whisper then
                                Compat.Whisper(item.displayName)
                            end
                        end)
                    end
                    if isCrossFac and bnetName and Compat.BNetWhisper then
                        root:CreateButton(L["Battle.net Whisper"], function()
                            Compat.BNetWhisper(bnetName, item.displayName)
                        end)
                    elseif not isCrossFac then
                        root:CreateButton(L["WoW Whisper (/w)"], function()
                            Compat.Whisper(item.displayName)
                        end)
                    end
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
                        local inGroupAlready = (panel._view == "current")
                            or (item.inCurrentGroup == true)
                            or (Compat.IsInMyGroup and Compat.IsInMyGroup(item.displayName, item.guid))
                        if (not isCrossFac) and (not inGroupAlready) then
                            root:CreateButton(L["Invite"], function()
                                Compat.Invite(item.displayName, bnetId)
                            end)
                        end
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
        local rows, emptyText
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
    if not newChatModal then
        local m = CreateFrame("Frame", "SocialCentralNewChatModal", UIParent, "BackdropTemplate")
        m:SetSize(446, 342)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(125)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
        Theme:MakeMovable(m, { key = "modal_new_chat" })
        table.insert(UISpecialFrames, "SocialCentralNewChatModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -64, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["New 1-on-1 Chat"])
        if Theme.DecorateSectionHeader then
            Theme:DecorateSectionHeader(m, title, 360)
        end

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            if m.input then m.input:ClearFocus() end
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        m.helpBtn = AddHelp(
            m,
            topCloseBtn,
            L["Help: New 1-on-1 Chat"],
            L["Starts a 1-on-1 conversation with any Battle.net friend, WoW friend, guildmate, target, or typed character name."],
            L["Click anyone in the online list to open chat immediately, click '+ Target' to fill your current target, or type a name and click 'Start'."],
            "RIGHT",
            "LEFT",
            -6,
            0
        )

        local lbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 16, -42)
        lbl:SetPoint("TOPRIGHT", -16, -42)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(L["Type a name to filter online friends, Battle.net, or guildmates — or click a player below:"])

        local targetBtn = Theme:CreateButton(m, 84, 24, L["+ Target"], "default")
        Theme:AutoFitButton(targetBtn, 72, 12, 118)
        targetBtn:SetPoint("TOPRIGHT", -16, -62)
        m.targetBtn = targetBtn

        local input = Theme:CreateEditBox(m, {
            height = 24,
            maxLetters = 64,
            clearButton = true,
            placeholder = L["Character name (Name or Name-Realm):"],
        })
        input:SetPoint("TOPLEFT", m, "TOPLEFT", 16, -62)
        input:SetPoint("RIGHT", targetBtn, "LEFT", -6, 0)
        m.input = input

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
                        local hasTwoPart = rawName:find("[%s%-]") ~= nil
                        local isShardOrSame = Compat and Compat.IsForeverShardLabel and Compat.IsForeverShardLabel(rawRealm)
                        if (not hasTwoPart) and (not isShardOrSame) and rawRealm and rawRealm ~= "" then
                            local myRealm = Compat and Compat.Realm and Compat.Realm() or ""
                            if myRealm == "" or rawRealm:lower() ~= myRealm:lower() then
                                rawName = rawName .. "-" .. rawRealm
                            end
                        end
                        targetName = (Compat and Compat.FormatForeverTarget and Compat.FormatForeverTarget(rawName)) or rawName
                    end
                end
                if targetName and not ns.Safe.IsSecret(targetName) then
                    input:SetText(targetName)
                end
            end
        end)

        local listWrap = CreateFrame("Frame", nil, m, "BackdropTemplate")
        listWrap:SetPoint("TOPLEFT", 16, -94)
        listWrap:SetPoint("BOTTOMRIGHT", -16, 46)
        m.listWrap = listWrap

        m.scroll = Theme:CreateScrollList(listWrap, 30, function(rowParent, _, rowHeight)
            local r = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
            r:SetHeight(rowHeight)

            r.ico = r:CreateTexture(nil, "ARTWORK")
            r.ico:SetSize(16, 16)
            r.ico:SetPoint("LEFT", 8, 0)

            r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.tag:SetPoint("RIGHT", -8, 0)
            r.tag:SetJustifyH("RIGHT")
            r.tag:SetWordWrap(false)

            r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.name:SetPoint("LEFT", r.ico, "RIGHT", 6, 0)
            r.name:SetPoint("RIGHT", r.tag, "LEFT", -6, 0)
            r.name:SetJustifyH("LEFT")
            r.name:SetWordWrap(false)

            r:SetScript("OnClick", function(selfRow)
                local item = selfRow._item
                if not item then return end
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
            return r
        end, function(r, item, _, pal)
            r._item = item
            local isBNet = item.sources and item.sources.bnet == true
            local classCoords = item.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[item.classFile]
            if classCoords then
                r.ico:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                r.ico:SetTexCoord(classCoords[1] + 0.02, classCoords[2] - 0.02, classCoords[3] + 0.02, classCoords[4] - 0.02)
            elseif isBNet then
                r.ico:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-BattleNet")
                r.ico:SetTexCoord(0, 1, 0, 1)
            else
                r.ico:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
                r.ico:SetTexCoord(0, 1, 0, 1)
            end

            local hex = Compat.ClassHex(item.classFile)
            local disp = item.displayName or item.bnetName or "?"
            if isBNet and item.bnetName and item.bnetName ~= "" and item.bnetName ~= disp and item.hasCharacterName ~= false then
                disp = disp .. " |cff70b5f9(" .. item.bnetName .. ")|r"
            end
            local fac = item.faction
                or (Compat.ResolveCharacterFaction and Compat.ResolveCharacterFaction(item.lookupKey or item.displayName, item.guid, item.bnetAccountID))
                or (ns.Chat and ns.Chat.GetKnownCharacterFaction and ns.Chat:GetKnownCharacterFaction(item.lookupKey or item.displayName, item.guid, item.bnetAccountID))
            local facIco = (Compat.FactionIconMarkup and Compat.FactionIconMarkup(fac, 12)) or ""
            local chatModOn = (not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("chat")
            local scConfirmed = chatModOn and ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(item.lookupKey or item.displayName, item.bnetAccountID)
            local scTag = scConfirmed and " |cff3fb950[SC]|r" or ""
            r.name:SetText(facIco .. hex .. disp .. "|r" .. scTag)

            local rightStr = ""
            if isBNet then
                rightStr = "|cff70b5f9Battle.net|r"
            elseif item.sources and item.sources.friend then
                rightStr = "|cff58a6ff" .. L["Friend"] .. "|r"
            elseif item.guild and item.guild ~= "" then
                rightStr = "<" .. item.guild .. ">"
            end
            r.tag:SetText(rightStr)
            r.tag:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])
        end)
        m.scroll.container:SetAllPoints()

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
                local bn = (row.bnetName or ""):lower()
                local g = (row.guild or ""):lower()
                if dn:find(q, 1, true) or (bn ~= "" and bn:find(q, 1, true)) or (g ~= "" and g:find(q, 1, true)) then
                    filtered[#filtered + 1] = row
                end
            end
            m.scroll:SetData(filtered, L["No online friends found right now."], true)
        end

        input:HookScript("OnTextChanged", function()
            if not m._applyFilter then return end
            m._filterToken = (m._filterToken or 0) + 1
            local tok = m._filterToken
            if C_Timer and C_Timer.After then
                C_Timer.After(0.10, function()
                    if m:IsShown() and m._filterToken == tok and m._applyFilter then
                        m._applyFilter()
                    end
                end)
            else
                m._applyFilter()
            end
        end)

        local btnStart = Theme:CreateButton(m, 110, 24, L["Start"], "primary")
        Theme:AutoFitButton(btnStart, 92, 18, 150)
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

    local onlineList = {}
    local affByItem = {}
    local rawEntries = ns.Social and ns.Social:GetList("all") or {}
    for _, item in ipairs(rawEntries) do
        if item and item.online and not item.isMe then
            onlineList[#onlineList + 1] = item
            affByItem[item] = (Store and Store.GetPlayerAffinityScore and Store:GetPlayerAffinityScore(item.lookupKey or item.displayName)) or 0
        end
    end
    table.sort(onlineList, function(a, b)
        local aa, ab = affByItem[a] or 0, affByItem[b] or 0
        if aa ~= ab then return aa > ab end
        local aB = (a.sources and a.sources.bnet) and 1 or 0
        local bB = (b.sources and b.sources.bnet) and 1 or 0
        if aB ~= bB then return aB > bB end
        local aF = (a.sources and a.sources.friend) and 1 or 0
        local bF = (b.sources and b.sources.friend) and 1 or 0
        if aF ~= bF then return aF > bF end
        return (a.displayName or "") < (b.displayName or "")
    end)

    Theme:ApplyBackdrop(newChatModal, "window")
    Theme:ApplyBackdrop(newChatModal.listWrap, "surface")
    Theme:StyleButton(newChatModal.topCloseBtn, "default")
    Theme:StyleButton(newChatModal.targetBtn, "default")
    Theme:StyleButton(newChatModal.btnStart, "primary")
    Theme:StyleButton(newChatModal.btnCancel, "default")
    if newChatModal.helpBtn and newChatModal.helpBtn.RefreshTheme then
        newChatModal.helpBtn:RefreshTheme()
    end
    if newChatModal.scroll and newChatModal.scroll.RefreshTheme then
        newChatModal.scroll:RefreshTheme()
    end
    newChatModal._allOnline = onlineList
    newChatModal.input:SetText("")
    newChatModal._applyFilter()
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
    btnFilterMenu:SetPoint("TOPLEFT", topBar, "TOPLEFT", 8, -6)
    btnFilterMenu:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(L["Filters"])
                local showGuildChatFilt = (not Compat or not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("clan")
                for _, def in ipairs(filterDefs) do
                    if (def.id ~= "guild" and def.id ~= "alliance") or showGuildChatFilt then
                        root:CreateRadio(def.label, function()
                            return panel._filter == def.id
                        end, function()
                            panel._filter = def.id
                            panel:Refresh(true)
                        end)
                    end
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
    btnFilterMenu:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Filters"], 1, 0.9, 0.55, true)
        GameTooltip:AddLine(L["Filter conversations by unread, whispers, guild, group, or rooms."], 0.85, 0.88, 0.94, true)
        GameTooltip:Show()
    end)
    btnFilterMenu:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)

    local btnUnreadQuick = Theme:CreateButton(topBar, 88, 22, L["Unread"], "default")
    btnUnreadQuick:SetPoint("LEFT", btnFilterMenu, "RIGHT", 4, 0)
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
        "TOPRIGHT",
        "TOPRIGHT",
        -8,
        -8
    )

    local OpenDeleteThreadModal

    local btnManageMenu = Theme:CreateButton(topBar, 24, 22, "", "default")
    do
        local layer = btnManageMenu._textLayer or btnManageMenu
        local ico = layer:CreateTexture(nil, "OVERLAY", nil, 2)
        ico:SetSize(15, 15)
        ico:SetPoint("CENTER")
        ico:SetTexture("Interface\\Buttons\\UI-OptionsButton")
        btnManageMenu.ico = ico
    end
    btnManageMenu:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Manage Conversations"], 1, 0.9, 0.55, true)
        GameTooltip:AddLine(L["Mark all conversations read, open Personal Notes, or clear/delete the active conversation."], 0.85, 0.88, 0.94, true)
        GameTooltip:Show()
    end)
    btnManageMenu:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)
    btnManageMenu:SetScript("OnClick", function(selfBtn)
        if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Chat) then
            if ns.Chat then ns.Chat:MarkAllRead() end
            return
        end
        local activeKey = ns.Chat.activeThreadKey
        local activeThread = activeKey and ns.Chat.threads and ns.Chat.threads[activeKey]
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            root:CreateTitle(L["Manage Conversations"])
            root:CreateButton(L["Mark All Read"], function()
                ns.Chat:MarkAllRead()
            end)
            root:CreateButton(L["Personal Notes (You)"], function()
                if ns.Chat.EnsurePersonalNotesThread then
                    local nt = ns.Chat:EnsurePersonalNotesThread()
                    if nt then
                        ns.Chat:SetActiveThread(nt.key, false)
                        ns:Emit("CHAT_UPDATED")
                    end
                end
            end)
            if activeKey and activeThread then
                root:CreateDivider()
                local clearSub = root:CreateButton(L["Clear Active Chat"])
                clearSub:CreateButton(L["Confirm Clear?"], function()
                    ns.Chat:ClearHistory(activeKey)
                end)
                if ns.Chat.CanDeleteThread and ns.Chat:CanDeleteThread(activeKey) and OpenDeleteThreadModal then
                    root:CreateButton("|cfff54747" .. L["Delete Conversation"] .. "|r", function()
                        OpenDeleteThreadModal(activeKey, activeThread.title or activeKey)
                    end)
                end
            end
        end)
    end)

    local btnRoomMenu = Theme:CreateButton(topBar, 74, 22, L["+ Room"] .. "  v", "default")
    btnRoomMenu:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["+ Room"], 1, 0.9, 0.55, true)
        GameTooltip:AddLine(L["Create a Private Addon Room or join a temporary WoW channel."], 0.85, 0.88, 0.94, true)
        GameTooltip:Show()
    end)
    btnRoomMenu:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)
    btnRoomMenu:SetScript("OnClick", function(selfBtn)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                root:CreateTitle(L["Rooms"])
                root:CreateButton("+ " .. L["Create Private Room"], OpenCreateRoomModal)
                root:CreateButton(L["Temp Channel"], OpenTempChannelModal)
            end)
        else
            OpenCreateRoomModal()
        end
    end)

    local btnNewChat = Theme:CreateButton(topBar, 72, 22, L["+ Chat"], "primary")
    btnNewChat:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["New 1-on-1 Chat"], 1, 0.9, 0.55, true)
        GameTooltip:AddLine(L["Open a 1-on-1 conversation with a friend, guildmate, target, or character name."], 0.85, 0.88, 0.94, true)
        GameTooltip:Show()
    end)
    btnNewChat:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)
    btnNewChat:SetScript("OnClick", OpenNewDirectChatModal)

    local function ReflowChatTopBar()
        local topW = math.floor((topBar:GetWidth() or panel:GetWidth() or 500) + 0.5)
        local compactTop = topW < 450
        local fLabel = GetFilterLabel(panel._filter)
        Theme:SetButtonText(btnFilterMenu, (compactTop and fLabel or string.format(L["Filter: %s"], fLabel)) .. "  v")
        Theme:AutoFitButton(btnFilterMenu, compactTop and 72 or 106, compactTop and 10 or 16, compactTop and 112 or 190)
        Theme:AutoFitButton(btnNewChat, compactTop and 62 or 76, compactTop and 12 or 16, compactTop and 88 or 116)
        Theme:AutoFitButton(btnRoomMenu, compactTop and 66 or 80, compactTop and 12 or 16, compactTop and 94 or 124)
        if btnUnreadQuick:IsShown() then
            Theme:AutoFitButton(btnUnreadQuick, compactTop and 54 or 86, compactTop and 10 or 14, compactTop and 88 or 150)
        end

        local leftW = 8 + (btnFilterMenu:GetWidth() or 78) + (btnUnreadQuick:IsShown() and (4 + (btnUnreadQuick:GetWidth() or 60)) or 0)
        local rightW = 8 + 18 + 4 + 24 + 4 + (btnRoomMenu:GetWidth() or 70) + 4 + (btnNewChat:GetWidth() or 66)
        local twoRows = (topW > 120) and ((leftW + rightW + 8) > topW)

        btnFilterMenu:ClearAllPoints()
        btnFilterMenu:SetPoint("TOPLEFT", topBar, "TOPLEFT", 8, -6)
        btnUnreadQuick:ClearAllPoints()
        btnUnreadQuick:SetPoint("LEFT", btnFilterMenu, "RIGHT", 4, 0)

        helpTop:ClearAllPoints()
        helpTop:SetPoint("TOPRIGHT", topBar, "TOPRIGHT", -8, twoRows and -8 or -8)

        btnManageMenu:ClearAllPoints()
        btnRoomMenu:ClearAllPoints()
        btnNewChat:ClearAllPoints()

        if twoRows then
            topBar:SetHeight(60)
            btnManageMenu:SetPoint("TOPRIGHT", topBar, "TOPRIGHT", -8, -32)
            btnRoomMenu:SetPoint("RIGHT", btnManageMenu, "LEFT", -4, 0)
            btnNewChat:SetPoint("RIGHT", btnRoomMenu, "LEFT", -4, 0)
        else
            topBar:SetHeight(34)
            btnManageMenu:SetPoint("RIGHT", helpTop, "LEFT", -4, 0)
            btnRoomMenu:SetPoint("RIGHT", btnManageMenu, "LEFT", -4, 0)
            btnNewChat:SetPoint("RIGHT", btnRoomMenu, "LEFT", -4, 0)
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

    local deleteThreadModal
    OpenDeleteThreadModal = function(threadKey, threadTitle)
        if not threadKey then return end
        local confirmWord = L["DELETE"]
        if not deleteThreadModal then
            local m = CreateFrame("Frame", "SocialCentralDeleteThreadModal", UIParent, "BackdropTemplate")
            m:SetSize(380, 176)
            m:SetPoint("CENTER")
            m:SetFrameStrata("DIALOG")
            m:SetFrameLevel(120)
            m:EnableMouse(true)
            Theme:MakeMovable(m, { key = "modal_delete_thread" })
            table.insert(UISpecialFrames, "SocialCentralDeleteThreadModal")

            local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            title:SetPoint("TOPLEFT", 16, -14)
            title:SetPoint("TOPRIGHT", -36, -14)
            title:SetJustifyH("LEFT")
            title:SetWordWrap(false)
            title:SetText("|cfff54747" .. L["Delete Conversation"] .. "|r")

            local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
            topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
            topCloseBtn:SetScript("OnClick", function()
                if m.input then m.input:ClearFocus() end
                m:Hide()
            end)

            local desc = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            desc:SetPoint("TOPLEFT", 16, -42)
            desc:SetPoint("TOPRIGHT", -16, -42)
            desc:SetJustifyH("LEFT")
            desc:SetWordWrap(true)
            m.desc = desc

            local input = Theme:CreateEditBox(m, { height = 24, maxLetters = 24 })
            input:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)
            input:SetPoint("RIGHT", m, "RIGHT", -16, 0)
            m.input = input

            local btnConfirm = Theme:CreateButton(m, 110, 24, L["Delete"], "danger")
            btnConfirm:SetPoint("BOTTOMRIGHT", -16, 14)
            btnConfirm:SetEnabled(false)
            m.btnConfirm = btnConfirm

            local btnCancel = Theme:CreateButton(m, 90, 24, L["Cancel"], "default")
            btnCancel:SetPoint("RIGHT", btnConfirm, "LEFT", -8, 0)
            btnCancel:SetScript("OnClick", function()
                input:ClearFocus()
                m:Hide()
            end)

            local function IsWordMatched()
                local raw = (input:GetText() or ""):gsub("^%s*(.-)%s*$", "%1"):upper()
                local targetWord = (L["DELETE"] or "DELETE"):upper()
                return raw == targetWord
            end

            input:SetScript("OnTextChanged", function()
                btnConfirm:SetEnabled(IsWordMatched())
            end)
            input:SetScript("OnEscapePressed", function()
                input:ClearFocus()
                m:Hide()
            end)

            local function ConfirmDelete()
                if not IsWordMatched() then return end
                local targetKey = m._threadKey
                input:ClearFocus()
                m:Hide()
                if targetKey and ns.Chat and ns.Chat.DeleteThread then
                    ns.Chat:DeleteThread(targetKey)
                end
            end

            input:SetScript("OnEnterPressed", ConfirmDelete)
            btnConfirm:SetScript("OnClick", ConfirmDelete)
            deleteThreadModal = m
        end

        deleteThreadModal._threadKey = threadKey
        Theme:ApplyBackdrop(deleteThreadModal, "window")
        deleteThreadModal.desc:SetText(string.format(
            L["Are you sure you want to permanently delete the conversation with \"%s\"?\n\nType %s to confirm:"],
            threadTitle or threadKey,
            "|cffffd24d" .. confirmWord .. "|r"
        ))
        deleteThreadModal.input:SetText("")
        deleteThreadModal.btnConfirm:SetEnabled(false)
        deleteThreadModal:Show()
        deleteThreadModal.input:SetFocus()
    end

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

        r.kindIcon = r:CreateTexture(nil, "ARTWORK", nil, 2)
        r.kindIcon:SetSize(12, 12)
        r.kindIcon:SetPoint("TOPLEFT", r, "TOPLEFT", 9, -5)

        r.scDot = r:CreateTexture(nil, "ARTWORK", nil, 3)
        r.scDot:SetSize(6, 6)
        r.scDot:SetPoint("BOTTOMRIGHT", r.kindIcon, "BOTTOMRIGHT", 2, -1)
        r.scDot:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\dot")
        r.scDot:Hide()

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
                        if key ~= "notes:self" and ns.Chat.ToggleThreadPinned then
                            local isPinned = ns.Chat:IsThreadPinned(key)
                            root:CreateButton(isPinned and L["Unpin Conversation"] or L["Pin Conversation"], function()
                                ns.Chat:ToggleThreadPinned(key)
                            end)
                        end
                        local isMuted = ns.Chat:IsThreadMuted(key)
                        root:CreateButton(isMuted and L["Unmute Conversation"] or L["Mute Conversation"], function()
                            ns.Chat:ToggleThreadMuted(key)
                        end)
                        if (r._item.unread or 0) > 0 then
                            root:CreateButton(L["Mark Read"], function()
                                ns.Chat:MarkThreadRead(key)
                            end)
                        elseif key ~= "notes:self" and ns.Chat.MarkThreadUnread then
                            root:CreateButton(L["Mark Unread"], function()
                                ns.Chat:MarkThreadUnread(key)
                            end)
                        end
                        local clearSub = root:CreateButton(L["Clear"])
                        clearSub:CreateButton(L["Confirm Clear?"], function()
                            ns.Chat:ClearHistory(key)
                        end)
                        if ns.Chat.CanDeleteThread and ns.Chat:CanDeleteThread(key) then
                            root:CreateDivider()
                            root:CreateButton("|cfff54747" .. L["Delete Conversation"] .. "|r", function()
                                OpenDeleteThreadModal(key, r._item.title or key)
                            end)
                        end
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
            local kindNames = {
                WHISPER = L["WoW Whisper (/w)"],
                BN_WHISPER = "Battle.net",
                ROOM = L["Addon Private Room"],
                NOTES = L["Personal Notes"],
            }
            local kindLbl = kindNames[it.kind] or L["Official WoW Channel"]
            local stPeer = (ns.Chat and ns.Chat.GetPeerAddonState) and ns.Chat:GetPeerAddonState(it.key) or nil
            if it.kind ~= "ROOM" and it.kind ~= "NOTES" and stPeer then
                if stPeer.state == "verified" then
                    kindLbl = kindLbl .. " · |cff3fb950SocialCentral|r"
                elseif stPeer.state == "registered" or stPeer.knownAddon then
                    kindLbl = kindLbl .. " · |cff58a6ffSocialCentral|r"
                end
            end
            GameTooltip:AddLine(kindLbl, 0.72, 0.80, 0.90, true)
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
        if r._hadUnreadBorder and not hasUnread then
            r._scBackdropSig = nil
        end
        Theme:ApplyBackdrop(r, (isSel or hasUnread) and "surface" or ((idx % 2 == 1) and "row" or "rowAlt"), pal)
        if hasUnread and r.SetBackdropBorderColor then
            r:SetBackdropBorderColor(0.86, 0.24, 0.28, 0.90)
            r._hadUnreadBorder = true
        else
            r._hadUnreadBorder = false
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

        if r.kindIcon then
            r.kindIcon:ClearAllPoints()
            r.kindIcon:SetPoint("TOPLEFT", r, "TOPLEFT", hasUnread and 18 or 9, -5)
            r.kindIcon:SetTexCoord(0, 1, 0, 1)
            r.kindIcon:SetVertexColor(1, 1, 1)
            if item.kind == "BN_WHISPER" then
                r.kindIcon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-BattleNet")
            elseif item.kind == "ROOM" then
                r.kindIcon:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\icon")
            elseif item.kind == "NOTES" then
                r.kindIcon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
                r.kindIcon:SetVertexColor(1.0, 0.85, 0.35)
            elseif item.kind == "WHISPER" then
                r.kindIcon:SetTexture("Interface\\Icons\\INV_Letter_15")
                r.kindIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else
                r.kindIcon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
                r.kindIcon:SetVertexColor(0.65, 0.78, 0.96)
            end
        end

        r.title:ClearAllPoints()
        r.title:SetPoint("TOPLEFT", r.kindIcon or r, r.kindIcon and "TOPRIGHT" or "TOPLEFT", r.kindIcon and 6 or (hasUnread and 18 or 10), r.kindIcon and 0 or -5)
        if hasUnread and r.unreadBadge then
            r.title:SetPoint("RIGHT", r.unreadBadge, "LEFT", -6, 0)
        else
            r.title:SetPoint("RIGHT", r, "RIGHT", -8, 0)
        end

        local st = (ns.Chat and ns.Chat.GetPeerAddonState) and ns.Chat:GetPeerAddonState(item.key) or nil
        if r.scDot then
            if item.kind ~= "ROOM" and item.kind ~= "NOTES" and st then
                if st.state == "verified" then
                    r.scDot:SetVertexColor(0.25, 0.73, 0.31, 1.0)
                    r.scDot:Show()
                elseif st.state == "registered" or st.knownAddon then
                    r.scDot:SetVertexColor(0.35, 0.65, 1.0, 1.0)
                    r.scDot:Show()
                else
                    r.scDot:Hide()
                end
            else
                r.scDot:Hide()
            end
        end
        local pinTag = item.pinned and "|cffffd24d*|r " or ""
        local mentionTag = item.hasMention and "|cffffd24d[@]|r " or ""
        local mutedTag = item.muted and (" |cffff9b3d[" .. L["Muted"] .. "]|r") or ""
        local availTag = ""
        if item.statusTag == "DND" then
            availTag = " |cfff54747[" .. L["DND"] .. "]|r"
        elseif item.statusTag == "AFK" then
            availTag = " |cffff9b3d[" .. L["AFK"] .. "]|r"
        end
        local isDirectRow = (item.kind == "WHISPER" or item.kind == "BN_WHISPER")
        local rowFac = isDirectRow and (item.faction
            or (Compat.ResolveCharacterFaction and Compat.ResolveCharacterFaction(item.targetName, nil, item.bnetAccountID))
            or (ns.Chat and ns.Chat.GetKnownCharacterFaction and ns.Chat:GetKnownCharacterFaction(item.targetName, nil, item.bnetAccountID))) or nil
        local facIco = (rowFac and Compat.FactionIconMarkup and Compat.FactionIconMarkup(rowFac, 12)) or ""
        local hex = item.classFile and Compat.ClassHex(item.classFile) or "|cffffffff"
        r.title:SetText(pinTag .. mentionTag .. facIco .. hex .. (item.title or "") .. "|r" .. availTag .. mutedTag)

        local draftTxt = panel._drafts and panel._drafts[item.key]
        local subStr
        if item._searchPreview and item._searchPreview ~= "" then
            subStr = "|cff8ab4f8" .. L["Match:"] .. "|r " .. item._searchPreview
        elseif draftTxt and draftTxt ~= "" and not isSel then
            subStr = "|cffff9b3d[" .. L["Draft"] .. "]|r " .. draftTxt
        else
            subStr = (item.preview ~= "" and item.preview) or (Compat.FormatRelativeTime(item.lastAt, L))
        end
        r.sub:SetText(subStr)
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

    local function SetupIconBtn(btn, w, h, tex, opts)
        opts = opts or {}
        Theme:SetButtonText(btn, "")
        btn:SetSize(w, h)
        local layer = btn._textLayer or btn
        local ico = layer:CreateTexture(nil, "OVERLAY", nil, 2)
        ico:SetSize(opts.size or 14, opts.size or 14)
        ico:SetPoint("CENTER")
        if opts.atlas and Theme.HasAtlas and Theme:HasAtlas(opts.atlas) and ico.SetAtlas then
            ico:SetAtlas(opts.atlas, false)
        else
            ico:SetTexture(tex)
            if opts.texCoord then
                ico:SetTexCoord(opts.texCoord[1], opts.texCoord[2], opts.texCoord[3], opts.texCoord[4])
            end
        end
        if opts.color then
            ico:SetVertexColor(opts.color[1], opts.color[2], opts.color[3], opts.color[4] or 1)
        end
        btn.ico = ico
        btn:HookScript("OnEnter", function(selfBtn)
            if not GameTooltip then return end
            local title, desc
            if type(opts.tooltipFn) == "function" then
                title, desc = opts.tooltipFn(selfBtn)
            else
                title, desc = opts.title, opts.desc
            end
            if title and title ~= "" then
                GameTooltip:SetOwner(selfBtn, opts.anchor or "ANCHOR_TOP")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(title, 1, 0.9, 0.55, true)
                if desc and desc ~= "" then
                    GameTooltip:AddLine(desc, 0.85, 0.88, 0.94, true)
                end
                GameTooltip:Show()
            end
        end)
        btn:HookScript("OnLeave", function(selfBtn)
            if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
        end)
    end

    local btnLeaveRoom = Theme:CreateButton(rightHdr, 24, 20, "", "danger")
    SetupIconBtn(btnLeaveRoom, 24, 20, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", {
        size = 13,
        color = { 1.0, 0.45, 0.45 },
        title = L["Leave"],
        desc = L["Leave this Private Addon Room."],
    })
    btnLeaveRoom:SetPoint("RIGHT", 0, 0)
    btnLeaveRoom:Hide()

    local btnRoomInvite = Theme:CreateButton(rightHdr, 24, 20, "", "default")
    SetupIconBtn(btnRoomInvite, 24, 20, "Interface\\PaperDollInfoFrame\\Character-Plus", {
        size = 13,
        color = { 0.45, 0.95, 0.55 },
        title = L["Invite"],
        desc = L["Invite another player to this Private Addon Room."],
    })
    btnRoomInvite:SetPoint("RIGHT", btnLeaveRoom, "LEFT", -4, 0)
    btnRoomInvite:Hide()

    local btnTargetCard = Theme:CreateButton(rightHdr, 24, 20, "", "default")
    SetupIconBtn(btnTargetCard, 24, 20, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", {
        size = 14,
        color = { 1.0, 0.85, 0.35 },
        title = L["Social Card & Notes"],
        desc = L["Open Social Card, folders, alts, and friend notes."],
    })
    btnTargetCard:SetPoint("RIGHT", 0, 0)
    btnTargetCard:Hide()

    local btnPinLoc = Theme:CreateButton(rightHdr, 24, 20, "", "default")
    SetupIconBtn(btnPinLoc, 24, 20, "Interface\\Icons\\INV_Misc_Map_01", {
        size = 14,
        texCoord = { 0.08, 0.92, 0.08, 0.92 },
        title = L["Location"],
        desc = L["Send your current zone and coordinates to this player."],
    })
    btnPinLoc:SetPoint("RIGHT", 0, 0)
    btnPinLoc:Hide()

    local btnMuteThread = Theme:CreateButton(rightHdr, 24, 20, "", "default")
    SetupIconBtn(btnMuteThread, 24, 20, "Interface\\AddOns\\SocialCentral\\Media\\bell-on", {
        size = 14,
        tooltipFn = function(selfBtn)
            if selfBtn._scMuted then
                return L["Unmute Conversation"], L["Sound alerts are muted for this conversation. Click to re-enable."]
            end
            return L["Mute Conversation"], L["Mute sound and unread badges for this conversation."]
        end,
    })
    btnMuteThread:SetPoint("RIGHT", 0, 0)
    btnMuteThread:Hide()

    local btnThreadActions = Theme:CreateButton(rightHdr, 24, 20, "", "default")
    SetupIconBtn(btnThreadActions, 24, 20, "Interface\\Buttons\\UI-OptionsButton", {
        size = 14,
        color = { 0.92, 0.85, 0.72 },
        title = L["Conversation Actions"],
        desc = L["Pin, mark unread, copy, clear history, or delete this conversation."],
    })
    btnThreadActions:SetPoint("RIGHT", 0, 0)
    btnThreadActions:Hide()

    local btnMarkRead = Theme:CreateButton(rightHdr, 24, 20, "", "primary")
    SetupIconBtn(btnMarkRead, 24, 20, "Interface\\Buttons\\UI-CheckBox-Check", {
        size = 15,
        color = { 0.45, 0.95, 0.55 },
        title = L["Mark Read"],
        desc = L["Clear unread message counter for this conversation."],
    })
    btnMarkRead:SetPoint("RIGHT", 0, 0)
    btnMarkRead:SetScript("OnClick", function()
        local k = ns.Chat and ns.Chat.activeThreadKey
        if k and ns.Chat and ns.Chat.MarkThreadRead then
            ns.Chat:MarkThreadRead(k)
        end
    end)
    btnMarkRead:Hide()

    local btnClearNotes = Theme:CreateButton(rightHdr, 24, 20, "", "danger")
    SetupIconBtn(btnClearNotes, 24, 20, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", {
        size = 13,
        color = { 1.0, 0.45, 0.45 },
        tooltipFn = function(selfBtn)
            if selfBtn._confirmUntil and (GetTime and GetTime() or time()) <= selfBtn._confirmUntil then
                return L["Confirm Clear?"], L["Click again to permanently delete all personal notes."]
            end
            return L["Clear Notes"], L["Delete all saved personal notes."]
        end,
    })
    btnClearNotes:SetPoint("RIGHT", 0, 0)
    btnClearNotes:SetScript("OnClick", function(selfBtn)
        local nowMono = GetTime and GetTime() or time()
        if not selfBtn._confirmUntil or nowMono > selfBtn._confirmUntil then
            selfBtn._confirmUntil = nowMono + 4.0
            Theme:SetButtonActive(selfBtn, true, "danger")
            if GameTooltip and GameTooltip:IsOwned(selfBtn) then
                GameTooltip:ClearLines()
                GameTooltip:AddLine(L["Confirm Clear?"], 1, 0.45, 0.45, true)
                GameTooltip:AddLine(L["Click again to permanently delete all personal notes."], 0.85, 0.88, 0.94, true)
                GameTooltip:Show()
            end
            if C_Timer and C_Timer.After then
                local tok = selfBtn._confirmUntil
                C_Timer.After(4.1, function()
                    if selfBtn._confirmUntil == tok then
                        selfBtn._confirmUntil = nil
                        Theme:SetButtonActive(selfBtn, false, "danger")
                    end
                end)
            end
            return
        end
        selfBtn._confirmUntil = nil
        Theme:SetButtonActive(selfBtn, false, "danger")
        if ns.Chat and ns.Chat.ClearHistory then
            ns.Chat:ClearHistory("notes:self")
        end
    end)
    btnClearNotes:Hide()

    hdrTitle:SetPoint("RIGHT", btnThreadActions, "LEFT", -8, 0)

    local function CopyActiveThreadLog()
        local k = ns.Chat and ns.Chat.activeThreadKey
        local act = k and ns.Chat and ns.Chat.threads and ns.Chat.threads[k]
        if not act or not (act.messages and #act.messages > 0) then return end
        local buf = {}
        local lastPairKey = nil
        for _, entry in ipairs(act.messages) do
            local ts = entry.ts and entry.ts > 0 and date("[%H:%M] ", entry.ts) or ""
            local rawTxt = tostring(entry.text or "")
            rawTxt = rawTxt:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
            local shortSender = entry.sender or ""
            if (act.kind == "WHISPER" or act.kind == "BN_WHISPER") and not entry.isStatusNotice and not entry.isSystem then
                if entry.targetChar and entry.targetChar ~= "" then
                    local sLk, sFirst = Compat.ParseCharacterFields and Compat.ParseCharacterFields(entry.sender)
                    sLk = sLk or tostring(entry.sender):lower()
                    local tLk = Compat.ParseCharacterFields and Compat.ParseCharacterFields(entry.targetChar) or tostring(entry.targetChar):lower()
                    local pKey = (sLk < tLk) and (sLk .. "|" .. tLk) or (tLk .. "|" .. sLk)
                    if pKey ~= lastPairKey then
                        lastPairKey = pKey
                        local myC = entry.incoming and entry.targetChar or entry.sender
                        local peerC = entry.incoming and entry.sender or entry.targetChar
                        table.insert(buf, ("—— %s & %s ——"):format(myC or "?", peerC or "?"))
                    end
                    if sFirst and sFirst ~= "" then
                        shortSender = sFirst
                    end
                elseif Compat.ParseCharacterFields then
                    local _, sFirst = Compat.ParseCharacterFields(shortSender)
                    if sFirst and sFirst ~= "" then
                        shortSender = sFirst
                    end
                end
            end
            table.insert(buf, ts .. shortSender .. ": " .. rawTxt)
        end
        if ns.UI and ns.UI.OpenCopyModal then
            ns.UI:OpenCopyModal(table.concat(buf, "\n"), L["Copy Chat: %s"]:format(act.title or ""), L["Press Ctrl+C to copy the conversation log to clipboard."])
        end
    end

    btnThreadActions:SetScript("OnClick", function(selfBtn)
        local k = ns.Chat and ns.Chat.activeThreadKey
        local act = k and ns.Chat and ns.Chat.threads and ns.Chat.threads[k]
        if not k or not act or act.kind == "notes" then return end
        if not MenuUtil or not MenuUtil.CreateContextMenu then
            CopyActiveThreadLog()
            return
        end
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            local isPinned = ns.Chat and ns.Chat.IsThreadPinned and ns.Chat:IsThreadPinned(k)
            root:CreateButton(isPinned and L["Unpin Conversation"] or L["Pin Conversation"], function()
                if ns.Chat and ns.Chat.ToggleThreadPinned then
                    ns.Chat:ToggleThreadPinned(k)
                    panel:Refresh()
                end
            end)
            if (act.unread or 0) > 0 then
                root:CreateButton(L["Mark Read"], function()
                    if ns.Chat and ns.Chat.MarkThreadRead then
                        ns.Chat:MarkThreadRead(k)
                        panel:Refresh()
                    end
                end)
            else
                root:CreateButton(L["Mark Unread"], function()
                    if ns.Chat and ns.Chat.MarkThreadUnread then
                        ns.Chat:MarkThreadUnread(k)
                        panel:Refresh()
                    end
                end)
            end
            if type(act.messages) == "table" and #act.messages > 0 then
                root:CreateButton(L["Copy"], CopyActiveThreadLog)
                root:CreateDivider()
                local clrSub = root:CreateButton(L["Clear Active Chat"])
                clrSub:CreateButton("|cffff5555" .. L["Confirm Clear?"] .. "|r", function()
                    if ns.Chat and ns.Chat.ClearHistory then
                        ns.Chat:ClearHistory(k)
                        panel:Refresh()
                    end
                end)
            end
            if ns.Chat and ns.Chat.CanDeleteThread and ns.Chat:CanDeleteThread(k) and OpenDeleteThreadModal then
                root:CreateDivider()
                root:CreateButton("|cffff5555" .. L["Delete Conversation"] .. "|r", function()
                    OpenDeleteThreadModal(k, act.title)
                end)
            end
        end)
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
        if not t then return end
        local rawTarget = t.targetName or t.bnetName or t.title
        local parsed = rawTarget and Compat.ParseCharacterName and Compat.ParseCharacterName(rawTarget)
        local lk = parsed and parsed.lookupKey or rawTarget
        local disp = (parsed and parsed.displayName) or rawTarget
        local ctx = (t.bnetAccountID and {
            lookupKey = parsed and parsed.lookupKey or nil,
            bnetAccountID = t.bnetAccountID,
            bnetName = t.bnetName,
            sources = { bnet = true },
        }) or nil
        if disp or ctx then
            SocialPanels:OpenSocialMetaModal(disp, lk, ctx)
        end
    end)

    local peerBar = CreateFrame("Frame", nil, rightCard)
    peerBar:SetPoint("TOPLEFT", rightHdr, "BOTTOMLEFT", 0, -4)
    peerBar:SetPoint("TOPRIGHT", rightHdr, "BOTTOMRIGHT", 0, -4)
    peerBar:SetHeight(20)

    local btnVerify = Theme:CreateButton(peerBar, 22, 18, "", "default")
    SetupIconBtn(btnVerify, 22, 18, "Interface\\Buttons\\UI-RefreshButton", {
        size = 13,
        tooltipFn = function()
            return L["Verify Addon"], L["Ping this player to check if SocialCentral direct chat is active."]
        end,
    })
    btnVerify:SetPoint("RIGHT", 0, 0)
    btnVerify:SetScript("OnClick", function()
        local k = ns.Chat and ns.Chat.activeThreadKey
        if k and ns.Chat and ns.Chat.ProbePeerAddon then
            ns.Chat:ProbePeerAddon(k, true)
        end
    end)
    btnVerify:Hide()

    local peerStatusIcon = peerBar:CreateTexture(nil, "OVERLAY")
    peerStatusIcon:SetSize(13, 13)
    peerStatusIcon:SetPoint("LEFT", 2, 0)
    peerStatusIcon:Hide()

    local peerStatusText = peerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    peerStatusText:SetPoint("LEFT", peerStatusIcon, "RIGHT", 5, 0)
    peerStatusText:SetPoint("RIGHT", btnVerify, "LEFT", -6, 0)
    peerStatusText:SetJustifyH("LEFT")
    peerStatusText:SetWordWrap(false)

    local peerStatusHover = CreateFrame("Frame", nil, peerBar)
    peerStatusHover:SetPoint("TOPLEFT", peerBar, "TOPLEFT", 0, 0)
    peerStatusHover:SetPoint("BOTTOMRIGHT", btnVerify, "BOTTOMLEFT", -4, 0)
    peerStatusHover:EnableMouse(true)
    peerStatusHover:SetScript("OnEnter", function(selfFrm)
        if not GameTooltip or not selfFrm._tipTitle then return end
        GameTooltip:SetOwner(selfFrm, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(selfFrm._tipTitle, 1, 0.9, 0.55, true)
        if selfFrm._tipDesc and selfFrm._tipDesc ~= "" then
            GameTooltip:AddLine(selfFrm._tipDesc, 0.85, 0.88, 0.94, true)
        end
        GameTooltip:Show()
    end)
    peerStatusHover:SetScript("OnLeave", function(selfFrm)
        if GameTooltip and GameTooltip:IsOwned(selfFrm) then GameTooltip:Hide() end
    end)

    local pinnedBanner = CreateFrame("Frame", nil, rightCard, "BackdropTemplate")
    pinnedBanner:SetPoint("TOPLEFT", peerBar, "BOTTOMLEFT", 0, -2)
    pinnedBanner:SetPoint("TOPRIGHT", peerBar, "BOTTOMRIGHT", 0, -2)
    pinnedBanner:SetHeight(20)
    Theme:ApplyBackdrop(pinnedBanner, "inset")
    pinnedBanner:Hide()

    local btnUnpinBanner = Theme:CreateButton(pinnedBanner, 20, 18, "x", "default")
    btnUnpinBanner:SetPoint("RIGHT", -2, 0)
    btnUnpinBanner:SetScript("OnClick", function()
        local k = ns.Chat and ns.Chat.activeThreadKey
        if k and panel._pinnedMsgs then
            panel._pinnedMsgs[k] = nil
            panel:Refresh(false)
        end
    end)

    local pinnedBannerText = pinnedBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pinnedBannerText:SetPoint("LEFT", 6, 0)
    pinnedBannerText:SetPoint("RIGHT", btnUnpinBanner, "LEFT", -4, 0)
    pinnedBannerText:SetJustifyH("LEFT")
    pinnedBannerText:SetWordWrap(false)

    local replyInput
    local msgFrame = CreateFrame("ScrollingMessageFrame", nil, rightCard)
    msgFrame:SetClipsChildren(true)
    msgFrame:SetPoint("TOPLEFT", 10, -60)
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
    msgFrame:EnableMouse(true)
    msgFrame:EnableMouseWheel(true)
    if msgFrame.SetHyperlinksEnabled then
        msgFrame:SetHyperlinksEnabled(true)
    end
    msgFrame:SetScript("OnHyperlinkClick", function(selfFrame, link, text, button)
        if type(link) ~= "string" then return end
        if link:find("addon:SCentral:delnote:", 1, true) then
            local noteId = link:match("addon:SCentral:delnote:([^|]+)")
            if noteId and noteId ~= "" and ns.Chat and ns.Chat.DeletePersonalNote then
                ns.Chat:DeletePersonalNote(noteId)
            end
        elseif link:find("addon:SCentral:msgact:", 1, true) then
            local idx = tonumber(link:match("addon:SCentral:msgact:(%d+)"))
            local k = ns.Chat and ns.Chat.activeThreadKey
            local t = k and ns.Chat and ns.Chat.threads and ns.Chat.threads[k]
            local entry = idx and t and t.messages and t.messages[idx]
            if entry and MenuUtil and MenuUtil.CreateContextMenu then
                local rawPlain = tostring(entry.text or ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
                local senderLbl = entry.sender or t.title or "?"
                MenuUtil.CreateContextMenu(msgFrame, function(_, root)
                    root:CreateTitle(senderLbl)
                    root:CreateButton(L["Quote Reply"], function()
                        local snippet = (#rawPlain > 45) and (rawPlain:sub(1, 42) .. "...") or rawPlain
                        local quote = string.format("> %s: \"%s\" ", senderLbl, snippet)
                        replyInput:SetText(quote)
                        if replyInput.SetCursorPosition then replyInput:SetCursorPosition(#quote) end
                        if replyInput.SetFocus then replyInput:SetFocus() end
                    end)
                    root:CreateButton(L["Pin Message"], function()
                        panel._pinnedMsgs = panel._pinnedMsgs or {}
                        panel._pinnedMsgs[k] = senderLbl .. ": " .. rawPlain
                        panel:Refresh(false)
                    end)
                    if k ~= "notes:self" and ns.Chat and ns.Chat.SavePersonalNote then
                        root:CreateButton(L["Save to Personal Notes"], function()
                            ns.Chat:SavePersonalNote("[" .. senderLbl .. "] " .. rawPlain)
                            ns:Print("%s", L["Saved to Personal Notes."])
                        end)
                    end
                    root:CreateButton(L["Copy Message"], function()
                        if ns.UI and ns.UI.OpenCopyModal then
                            ns.UI:OpenCopyModal(senderLbl .. ": " .. rawPlain, L["Copy Message"], L["Press Ctrl+C to copy this message."])
                        end
                    end)
                end)
            end
        elseif not link:find("^addon:") then
            if _G.ChatFrame_OnHyperlinkShow then
                pcall(_G.ChatFrame_OnHyperlinkShow, selfFrame, link, text, button)
            elseif _G.SetItemRef and not (InCombatLockdown and InCombatLockdown()) then
                pcall(_G.SetItemRef, link, text, button, selfFrame)
            end
        end
    end)
    local btnScrollBottom = Theme:CreateButton(rightCard, 24, 22, "", "default")
    SetupIconBtn(btnScrollBottom, 24, 22, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", {
        size = 15,
        color = { 0.95, 0.88, 0.72 },
        title = L["Jump to latest messages"],
    })
    btnScrollBottom:SetPoint("BOTTOMRIGHT", msgFrame, "BOTTOMRIGHT", -4, 4)
    btnScrollBottom:SetFrameLevel((msgFrame:GetFrameLevel() or 2) + 4)
    btnScrollBottom:Hide()
    btnScrollBottom:SetScript("OnClick", function()
        if msgFrame.ScrollToBottom then
            msgFrame:ScrollToBottom()
        end
        btnScrollBottom:Hide()
    end)
    btnScrollBottom:SetScript("OnLeave", function()
        if GameTooltip and GameTooltip:IsOwned(btnScrollBottom) then GameTooltip:Hide() end
    end)

    msgFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 and self.ScrollUp then
            self:ScrollUp()
        elseif delta < 0 and self.ScrollDown then
            self:ScrollDown()
        end
        local atBot = self.AtBottom and self:AtBottom()
        btnScrollBottom:SetShown(atBot == false)
    end)

    local dragScrollActive = false
    local dragLastY = 0
    local DRAG_STEP_PX = 14
    local function StopMsgDrag()
        dragScrollActive = false
        msgFrame:SetScript("OnUpdate", nil)
    end
    local function OnMsgDragUpdate()
        if not dragScrollActive or not IsMouseButtonDown("LeftButton") then
            StopMsgDrag()
            return
        end
        local _, cursorY = GetCursorPosition()
        local scale = msgFrame:GetEffectiveScale() or 1
        local curY = cursorY / scale
        local dy = curY - dragLastY
        local moved = false
        while dy >= DRAG_STEP_PX do
            if msgFrame.ScrollDown then msgFrame:ScrollDown() end
            dragLastY = dragLastY + DRAG_STEP_PX
            dy = curY - dragLastY
            moved = true
        end
        while dy <= -DRAG_STEP_PX do
            if msgFrame.ScrollUp then msgFrame:ScrollUp() end
            dragLastY = dragLastY - DRAG_STEP_PX
            dy = curY - dragLastY
            moved = true
        end
        if moved then
            local atBot = msgFrame.AtBottom and msgFrame:AtBottom()
            btnScrollBottom:SetShown(atBot == false)
        end
    end
    msgFrame:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local _, cursorY = GetCursorPosition()
        local scale = msgFrame:GetEffectiveScale() or 1
        dragLastY = cursorY / scale
        dragScrollActive = true
        msgFrame:SetScript("OnUpdate", OnMsgDragUpdate)
    end)
    msgFrame:SetScript("OnMouseUp", StopMsgDrag)
    msgFrame:SetScript("OnHide", StopMsgDrag)

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

    local btnSend = Theme:CreateButton(composer, 56, 24, L["Send"], "primary")
    SetupIconBtn(btnSend, 56, 24, "Interface\\AddOns\\SocialCentral\\Media\\arrow", {
        size = 15,
        color = { 1.0, 0.92, 0.65 },
        tooltipFn = function(selfBtn)
            return selfBtn._tipTitle or L["Send"], selfBtn._tipDesc or L["Send your message."]
        end,
    })
    if btnSend.ico then
        if btnSend.ico.SetRotation then
            btnSend.ico:SetRotation(-math.pi / 2)
        end
        btnSend.ico:Hide()
    end
    btnSend:SetPoint("RIGHT", helpComposer, "LEFT", -6, 0)

    local function SyncSendButtonVisual()
        local cw = composer.GetWidth and composer:GetWidth() or 0
        if cw <= 0 then
            cw = (panel.GetWidth and panel:GetWidth() or 0) - 20
        end
        local useText = (cw <= 0) or (cw >= 260)
        if useText then
            if btnSend.ico then btnSend.ico:Hide() end
            Theme:SetButtonText(btnSend, L["Send"])
            Theme:AutoFitButton(btnSend, 52, 14, 78)
        else
            Theme:SetButtonText(btnSend, "")
            btnSend:SetSize(28, 24)
            if btnSend.ico then
                if btnSend._isBNetSend then
                    btnSend.ico:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-BattleNet")
                    btnSend.ico:SetSize(15, 15)
                    btnSend.ico:SetVertexColor(1, 1, 1)
                    if btnSend.ico.SetRotation then btnSend.ico:SetRotation(0) end
                else
                    btnSend.ico:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\arrow")
                    btnSend.ico:SetSize(15, 15)
                    btnSend.ico:SetVertexColor(1.0, 0.92, 0.65)
                    if btnSend.ico.SetRotation then btnSend.ico:SetRotation(-math.pi / 2) end
                end
                btnSend.ico:Show()
            end
        end
    end

    local btnQuickReply = Theme:CreateButton(composer, 26, 24, "", "default")
    SetupIconBtn(btnQuickReply, 26, 24, "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", {
        size = 15,
        title = L["Quick Replies"],
        desc = L["Send a saved message in 1 click or save the current text as a new template."],
    })
    btnQuickReply:SetPoint("RIGHT", btnSend, "LEFT", -4, 0)

    replyInput = Theme:CreateEditBox(composer, {
        height = 24,
        maxLetters = 200,
        insertLinkMode = "full",
        placeholder = L["Select a conversation to reply..."],
    })
    replyInput:SetPoint("LEFT", 0, 0)
    replyInput:SetPoint("RIGHT", btnQuickReply, "LEFT", -6, 0)

    local charCounter = composer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charCounter:SetPoint("RIGHT", replyInput, "RIGHT", -6, 0)
    charCounter:SetJustifyH("RIGHT")
    charCounter:Hide()
    replyInput:HookScript("OnTextChanged", function(selfBox)
        local len = #(selfBox:GetText() or "")
        if len >= 100 then
            charCounter:SetText(string.format("%d/180", len))
            if len > 180 then
                charCounter:SetTextColor(1.0, 0.35, 0.35)
            elseif len >= 160 then
                charCounter:SetTextColor(1.0, 0.72, 0.25)
            else
                charCounter:SetTextColor(0.65, 0.72, 0.80)
            end
            charCounter:Show()
        else
            charCounter:Hide()
        end
    end)

    local function SubmitReply()
        if not (ns.Chat and ns.Chat.activeThreadKey) then return end
        local key = ns.Chat.activeThreadKey
        local txt = replyInput:GetText() or ""
        if ns.Chat:SendOrOpenReply(key, txt, true) then
            replyInput:SetText("")
            if panel._drafts then
                panel._drafts[key] = nil
            end
        end
    end
    btnSend:SetScript("OnClick", SubmitReply)
    btnQuickReply:SetScript("OnClick", function(selfBtn)
        if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Chat) then return end
        local key = ns.Chat.activeThreadKey
        local list = ns.Chat.GetQuickReplies and ns.Chat:GetQuickReplies() or {}
        local curTxt = Compat.CleanInput(replyInput:GetText() or "")
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            root:CreateTitle(L["Quick Replies"])
            for idx, tpl in ipairs(list) do
                root:CreateButton(tpl, function()
                    if key and ns.Chat:SendOrOpenReply(key, tpl, true) then
                        replyInput:SetText("")
                        if panel._drafts then
                            panel._drafts[key] = nil
                        end
                    end
                end)
            end
            root:CreateDivider()
            if curTxt and curTxt ~= "" then
                root:CreateButton("+ " .. L["Save current text as Quick Reply"], function()
                    ns.Chat:AddQuickReply(curTxt)
                end)
            end
            local sub = root:CreateButton(L["Remove Quick Reply"])
            for idx, tpl in ipairs(list) do
                sub:CreateButton(tpl, function()
                    ns.Chat:RemoveQuickReply(idx)
                end)
            end
            root:CreateButton(L["Reset Defaults"], function()
                ns.Chat:ResetQuickReplies()
            end)
        end)
    end)
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
        Theme:StyleButton(btnUnreadQuick, "default")
        Theme:StyleButton(btnNewChat, "primary")
        Theme:StyleButton(btnRoomMenu, "default")
        Theme:StyleButton(btnManageMenu, "default")
        Theme:StyleButton(invAccept, "primary")
        Theme:StyleButton(invDecline, "danger")
        Theme:StyleButton(btnRoomInvite, "default")
        Theme:StyleButton(btnLeaveRoom, "danger")
        Theme:StyleButton(btnTargetCard, "default")
        Theme:StyleButton(btnPinLoc, "default")
        Theme:StyleButton(btnThreadActions, "default")
        Theme:StyleButton(btnMarkRead, "primary")
        Theme:StyleButton(btnClearNotes, "danger")
        Theme:StyleButton(btnMuteThread, "default")
        Theme:StyleButton(btnVerify, "default")
        Theme:StyleButton(btnSend, "primary")
        Theme:StyleButton(btnQuickReply, "default")
        Theme:StyleButton(btnScrollBottom, "default")
        Theme:StyleButton(btnUnpinBanner, "default")
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
        if ReflowChatTopBar then
            ReflowChatTopBar(pw)
        end
        SyncSendButtonVisual()
        if pw < 540 then
            local h = panel:GetHeight() or 0
            local topH = topBar:GetHeight() or 60
            local avail = math.max(200, h - topH - 16)
            local rows = math.max(2, math.min(4, math.floor((math.floor(avail * 0.42) - 38) / 38)))
            local leftH = 38 + rows * 38
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
            local pw = panel.GetWidth and panel:GetWidth() or 0
            local compactBar = pw > 0 and pw < 430
            local uLabel
            if unreadDirect > 0 then
                uLabel = compactBar and ("! |cffff5555(" .. unreadDirect .. ")|r") or (L["Unread"] .. " |cffff5555(" .. unreadDirect .. ")|r")
            else
                uLabel = L["Unread"]
            end
            Theme:SetButtonText(btnUnreadQuick, uLabel)
            if Theme.AutoFitButton then
                Theme:AutoFitButton(btnUnreadQuick, compactBar and 44 or 64, 14, 120)
            end
            Theme:SetButtonActive(btnUnreadQuick, self._filter == "unread", "default")
        end
        if ReflowChatTopBar then
            ReflowChatTopBar(panel.GetWidth and panel:GetWidth() or 0)
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
                th._searchPreview = nil
                local hay = ((th.title or "") .. " " .. (th.preview or "")):lower()
                if hay:find(qLow, 1, true) then
                    filtered[#filtered + 1] = th
                else
                    local rawThread = ns.Chat and ns.Chat.threads and ns.Chat.threads[th.key]
                    local msgs = rawThread and rawThread.messages
                    if type(msgs) == "table" then
                        for i = #msgs, 1, -1 do
                            local m = msgs[i]
                            local mText = m and m.text or ""
                            local mSender = m and m.sender or ""
                            if mText:lower():find(qLow, 1, true) or mSender:lower():find(qLow, 1, true) then
                                th._searchPreview = mText
                                filtered[#filtered + 1] = th
                                break
                            end
                        end
                    end
                end
            end
            threads = filtered
        end
        if ns.Chat and (not ns.Chat.activeThreadKey or not ns.Chat.threads[ns.Chat.activeThreadKey]) and #threads > 0 then
            ns.Chat:SetActiveThread(threads[1].key, (threads[1].unread or 0) > 0)
        end
        local activeKeyNow = ns.Chat and ns.Chat.activeThreadKey
        if activeKeyNow and panel:IsShown() and ns.Chat and ns.Chat.GetPeerAddonState and ns.Chat.ShouldAutoProbe and ns.Chat.ProbePeerAddon then
            local stProbe = ns.Chat:GetPeerAddonState(activeKeyNow)
            if stProbe and (stProbe.state == "registered" or stProbe.bnetGameAccId ~= nil) and ns.Chat:ShouldAutoProbe(activeKeyNow) then
                ns.Chat:ProbePeerAddon(activeKeyNow, false)
            end
        end
        panel._drafts = panel._drafts or {}
        if panel._lastDraftThreadKey ~= activeKeyNow then
            if panel._lastDraftThreadKey then
                local prevText = replyInput:GetText() or ""
                panel._drafts[panel._lastDraftThreadKey] = (prevText ~= "") and prevText or nil
            end
            panel._lastDraftThreadKey = activeKeyNow
            local hasMatchingPending = ns.Chat and ns.Chat.pendingDraftText and ((not ns.Chat.pendingDraftThreadKey) or ns.Chat.pendingDraftThreadKey == activeKeyNow)
            if not hasMatchingPending then
                replyInput:SetText((activeKeyNow and panel._drafts[activeKeyNow]) or "")
            end
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
            local isNotes = active.kind == "NOTES"
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
            local hdrFac = ((not isNotes) and (not isRoom) and isDirect) and (pState.faction
                or (Compat.ResolveCharacterFaction and Compat.ResolveCharacterFaction(pState.activeChar or active.targetName, nil, active.bnetAccountID))
                or (ns.Chat and ns.Chat.GetKnownCharacterFaction and ns.Chat:GetKnownCharacterFaction(pState.activeChar or active.targetName, nil, active.bnetAccountID))) or nil
            local hdrFacIco = (hdrFac and Compat.FactionIconMarkup and Compat.FactionIconMarkup(hdrFac, 14)) or ""
            local shownHdrTitle = (isDirect and (not isNotes) and pState.activeChar and pState.activeChar ~= "" and not tostring(pState.activeChar):find("#", 1, true))
                and pState.activeChar
                or (active.title or "")
            hdrTitle:SetText(hdrFacIco .. shownHdrTitle .. (isRoom and ("  |cff3fb950[" .. memberCount .. "]|r") or "") .. availHdrTag .. unreadHdrTag)

            btnRoomInvite:SetShown(isRoom)
            btnLeaveRoom:SetShown(isRoom)
            btnTargetCard:SetShown((not isNotes) and isDirect and (active.targetName ~= nil or active.bnetAccountID ~= nil))
            btnPinLoc:SetShown((not isNotes) and (not isRoom) and isDirect and pState.verified == true)
            btnMarkRead:SetShown((not isNotes) and activeUnread > 0)
            btnClearNotes:SetShown(isNotes and type(active.messages) == "table" and #active.messages > 0)
            btnMuteThread:SetShown(not isNotes)
            btnThreadActions:SetShown(not isNotes)
            btnMuteThread._scMuted = isMuted
            if btnMuteThread.ico then
                btnMuteThread.ico:SetTexture(isMuted
                    and "Interface\\AddOns\\SocialCentral\\Media\\bell-off"
                    or "Interface\\AddOns\\SocialCentral\\Media\\bell-on")
            end
            Theme:SetButtonActive(btnMuteThread, isMuted, "default")

            local orderedRight = {}
            if btnLeaveRoom:IsShown() then table.insert(orderedRight, btnLeaveRoom) end
            if btnRoomInvite:IsShown() then table.insert(orderedRight, btnRoomInvite) end
            if btnClearNotes:IsShown() then table.insert(orderedRight, btnClearNotes) end
            if btnThreadActions:IsShown() then table.insert(orderedRight, btnThreadActions) end
            if btnMuteThread:IsShown() then table.insert(orderedRight, btnMuteThread) end
            if btnTargetCard:IsShown() then table.insert(orderedRight, btnTargetCard) end
            if btnPinLoc:IsShown() then table.insert(orderedRight, btnPinLoc) end
            if btnMarkRead:IsShown() then table.insert(orderedRight, btnMarkRead) end
            local rightGap = -4
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

            -- Peer verification bar (compact icon + short tag; full explanation on hover)
            local showVerifyBtn = (not isNotes) and isDirect and (pState.state == "unprobed" or pState.state == "unverified" or pState.state == "checking" or pState.state == "registered")
            btnVerify:SetShown(showVerifyBtn)
            if showVerifyBtn then
                btnVerify:SetEnabled(pState.state ~= "checking")
                if btnVerify.ico then
                    btnVerify.ico:SetVertexColor(pState.state == "checking" and 0.6 or 1, pState.state == "checking" and 0.6 or 1, pState.state == "checking" and 0.6 or 1)
                end
            end
            peerStatusIcon:Show()
            peerStatusIcon:SetTexCoord(0, 1, 0, 1)
            peerStatusIcon:SetVertexColor(1, 1, 1)
            peerStatusText:ClearAllPoints()
            peerStatusText:SetPoint("LEFT", peerStatusIcon, "RIGHT", 5, 0)
            peerStatusText:SetPoint("RIGHT", showVerifyBtn and btnVerify or peerBar, showVerifyBtn and "LEFT" or "RIGHT", showVerifyBtn and -6 or -2, 0)
            peerStatusText:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])

            local function SetPeerStatus(iconTex, r, g, b, shortTxt, tipTitle, tipDesc, texCoord)
                peerStatusIcon:SetTexture(iconTex)
                if texCoord then
                    peerStatusIcon:SetTexCoord(texCoord[1], texCoord[2], texCoord[3], texCoord[4])
                end
                peerStatusIcon:SetVertexColor(r, g, b)
                peerStatusText:SetText(shortTxt)
                peerStatusHover._tipTitle = tipTitle
                peerStatusHover._tipDesc = tipDesc
            end

            local parsedAct = active.targetName and Compat.ParseCharacterName and Compat.ParseCharacterName(active.targetName) or nil
            local bInfo = parsedAct and parsedAct.lookupKey and ns.Social and ns.Social.GetBNetLinkInfo
                and ns.Social:GetBNetLinkInfo(parsedAct.lookupKey) or nil
            local isBNetRedirectActive = (not isNotes) and (not isRoom) and active.kind == "WHISPER"
                and bInfo and bInfo.online == true
                and ((bInfo.sameFaction == false) or (pState.state == "offline") or (bInfo.activeLookupKey ~= (parsedAct and parsedAct.lookupKey)))

            local destInfo = (not isNotes and not isRoom and ns.Chat and ns.Chat.GetOfficialDestinationInfo)
                and ns.Chat:GetOfficialDestinationInfo(activeKey) or nil
            local isAltRedirectActive = (destInfo and destInfo.isAltRedirect == true) or false

            if isNotes then
                SetPeerStatus(
                    "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", 1.0, 0.85, 0.35,
                    "|cffffd24d" .. L["Personal Notes"] .. "|r",
                    L["Personal Notes"],
                    L["Saved permanently until you delete them."]
                )
            elseif isRoom then
                SetPeerStatus(
                    "Interface\\AddOns\\SocialCentral\\Media\\icon", 1, 1, 1,
                    "|cff3fb950" .. string.format(L["%d members"], memberCount) .. "|r",
                    L["Addon Private Room"],
                    string.format(L["%d members"], memberCount)
                )
            elseif activeKey == "ch:alliance" or pState.state == "alliance" then
                local allCfg = ns.Clan and ns.Clan.GetAllianceConfig and ns.Clan:GetAllianceConfig() or {}
                local allName = (allCfg.name and allCfg.name ~= "") and allCfg.name or L["Cross-Guild Alliance"]
                SetPeerStatus(
                    "Interface\\AddOns\\SocialCentral\\Media\\icon", 1, 1, 1,
                    "|cff3fb950" .. allName .. "|r",
                    L["Alliance Chat"],
                    allName
                )
            elseif isBNetRedirectActive then
                local activeLbl = bInfo.activeDisplayName or bInfo.bnetName or "Battle.net"
                local facLbl = bInfo.faction and ((bInfo.faction == "Alliance") and L["Alliance"] or L["Horde"]) or nil
                local shortLbl = (bInfo.sameFaction == false and facLbl)
                    and ("|cff58a6ffB.net · " .. facLbl .. "|r")
                    or ("|cff58a6ffB.net -> " .. activeLbl .. "|r")
                local desc = string.format(
                    L["Character offline or opposite faction. Messages sent here are automatically redirected to Battle.net (%s) tagged [To %s]."],
                    activeLbl,
                    (parsedAct and parsedAct.displayName) or active.title or "?"
                )
                SetPeerStatus("Interface\\ChatFrame\\UI-ChatIcon-BattleNet", 1, 1, 1, shortLbl, L["Battle.net Redirect"], desc)
            elseif isAltRedirectActive then
                local altLbl = destInfo.activeChar or destInfo.label or "?"
                local desc = string.format(
                    L["Character offline. Messages sent here are automatically redirected to %s tagged [To %s]."],
                    altLbl,
                    destInfo.targetDisplay or active.title or "?"
                )
                SetPeerStatus("Interface\\Icons\\INV_Letter_15", 0.55, 0.82, 1.0, "|cff58a6ff-> " .. altLbl .. "|r", L["Alt Redirect"], desc, { 0.08, 0.92, 0.08, 0.92 })
            elseif pState.state == "registered" then
                local verTag = pState.version and ("v" .. pState.version) or "OK"
                SetPeerStatus(
                    "Interface\\AddOns\\SocialCentral\\Media\\icon", 1, 1, 1,
                    "|cff58a6ffSC " .. verTag .. "|r",
                    "SocialCentral " .. verTag .. " · " .. L["Registered"],
                    L["In-addon direct chat ready"]
                )
            elseif pState.verified then
                local verTag = pState.version and ("v" .. pState.version) or "OK"
                SetPeerStatus(
                    "Interface\\AddOns\\SocialCentral\\Media\\icon", 1, 1, 1,
                    "|cff3fb950SC " .. verTag .. "|r",
                    "SocialCentral " .. verTag,
                    L["Both players verified — in-addon direct chat active"]
                )
            elseif pState.state == "checking" then
                SetPeerStatus(
                    "Interface\\AddOns\\SocialCentral\\Media\\dot", 1.0, 0.82, 0.30,
                    "|cffffd24d...|r",
                    L["Checking SocialCentral..."],
                    L["Waiting for addon handshake response."]
                )
            elseif pState.state == "disabled" then
                SetPeerStatus(
                    "Interface\\AddOns\\SocialCentral\\Media\\dot", 1.0, 0.60, 0.24,
                    "|cffff9b3d/w|r",
                    L["In-addon direct chat disabled in Settings"],
                    L["Messages will be sent via standard WoW whisper."]
                )
            elseif pState.state == "offline" then
                if pState.knownAddon then
                    local verStr = pState.version and ("v" .. pState.version .. " · ") or ""
                    SetPeerStatus(
                        "Interface\\AddOns\\SocialCentral\\Media\\dot", 0.54, 0.71, 0.97,
                        "|cff8ab4f8" .. L["Offline"] .. "|r",
                        "SocialCentral " .. verStr .. L["Offline"],
                        L["Registered user — in-addon chat resumes automatically when online"]
                    )
                else
                    SetPeerStatus(
                        "Interface\\AddOns\\SocialCentral\\Media\\dot", 0.62, 0.65, 0.71,
                        "|cff9da7b5" .. L["Offline"] .. "|r",
                        L["Offline or out of addon range"],
                        L["Player is currently offline or unreachable."]
                    )
                end
            elseif pState.state == "channel" then
                SetPeerStatus(
                    "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", 0.35, 0.65, 1.0,
                    "|cff58a6ff" .. (pState.slash or "") .. "|r",
                    L["Official WoW Channel"],
                    (pState.slash or "")
                )
            else
                if active.kind == "BN_WHISPER" then
                    SetPeerStatus(
                        "Interface\\ChatFrame\\UI-ChatIcon-BattleNet", 1, 1, 1,
                        "|cff58a6ffB.net|r",
                        "Battle.net",
                        L["SocialCentral not detected on peer"]
                    )
                else
                    SetPeerStatus(
                        "Interface\\Icons\\INV_Letter_15", 0.85, 0.85, 0.85,
                        "|cff9da7b5/w|r",
                        L["WoW Whisper (/w)"],
                        L["SocialCentral not detected on peer"],
                        { 0.08, 0.92, 0.08, 0.92 }
                    )
                end
            end

            if lineCount == 0 and panel._pinnedMsgs and panel._pinnedMsgs[activeKey] then
                panel._pinnedMsgs[activeKey] = nil
            end
            local pinnedMsg = panel._pinnedMsgs and panel._pinnedMsgs[activeKey]
            if pinnedMsg and pinnedMsg ~= "" then
                pinnedBannerText:SetText("|cffffd24d[" .. L["Pinned"] .. "]|r " .. pinnedMsg)
                Theme:ApplyBackdrop(pinnedBanner, "inset", p)
                pinnedBanner:Show()
                msgFrame:ClearAllPoints()
                msgFrame:SetPoint("TOPLEFT", 10, -82)
                msgFrame:SetPoint("BOTTOMRIGHT", -10, 40)
            else
                pinnedBanner:Hide()
                msgFrame:ClearAllPoints()
                msgFrame:SetPoint("TOPLEFT", 10, -60)
                msgFrame:SetPoint("BOTTOMRIGHT", -10, 40)
            end

            -- Unified composer bar (direct in-addon packets when verified, instant WoW /w or channel reply otherwise)
            local isAlliance = (activeKey == "ch:alliance")
            officialBar:Hide()
            composer:Show()
            btnQuickReply:SetEnabled(true)
            if ns.Chat and ns.Chat.focusInputPending then
                ns.Chat.focusInputPending = nil
                if replyInput and replyInput.SetFocus then
                    replyInput:SetFocus()
                end
            end
            if (isNotes or isRoom or pState.verified or isAlliance) and not isBNetRedirectActive and not isAltRedirectActive then
                btnSend:SetEnabled(true)
                btnSend._isBNetSend = false
                SyncSendButtonVisual()
                btnSend._tipTitle = L["Send"]
                btnSend._tipDesc = isNotes and L["Save personal note."]
                    or (isAlliance and L["Send to Alliance chat inside SocialCentral."]
                    or (isRoom and L["Send to Private Addon Room."]
                    or L["Send direct in-addon message."]))
                if replyInput.SetPlaceholder then
                    replyInput:SetPlaceholder(isNotes
                        and L["Type a personal note to save permanently..."]
                        or (isAlliance and L["Type in-addon alliance message and press Enter..."]
                        or (isRoom and L["Type message to Private Room and press Enter..."]
                        or L["Type in-addon direct message and press Enter..."])))
                end
            else
                btnSend:SetEnabled(destInfo ~= nil)
                btnSend._isBNetSend = (destInfo and destInfo.kind == "BN_WHISPER") or false
                SyncSendButtonVisual()
                btnSend._tipTitle = (destInfo and destInfo.buttonText) or L["Send"]
                if destInfo and destInfo.isBNetRedirect then
                    btnSend._tipDesc = string.format(L["Redirects to Battle.net tagged [To %s]."], destInfo.targetDisplay or active.title or "?")
                elseif destInfo and destInfo.isAltRedirect then
                    btnSend._tipDesc = string.format(L["Redirects to %s tagged [To %s]."], destInfo.activeChar or "?", destInfo.targetDisplay or active.title or "?")
                else
                    btnSend._tipDesc = L["Press Enter or click to send."]
                end
                if replyInput.SetPlaceholder then
                    replyInput:SetPlaceholder((destInfo and destInfo.buttonText) or L["Select a conversation to reply..."])
                end
            end
            replyInput:ClearAllPoints()
            replyInput:SetPoint("LEFT", 0, 0)
            replyInput:SetPoint("RIGHT", btnQuickReply, "LEFT", -6, 0)
            if ns.Chat and ns.Chat.pendingDraftText and ((not ns.Chat.pendingDraftThreadKey) or ns.Chat.pendingDraftThreadKey == activeKey) then
                local draft = ns.Chat.pendingDraftText
                ns.Chat.pendingDraftText = nil
                ns.Chat.pendingDraftThreadKey = nil
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
                    local todayKey = date("%Y-%m-%d")
                    local yesterdayKey = date("%Y-%m-%d", time() - 86400)
                    local lastDayKey = nil
                    local lastPairKey = nil
                    for msgIdx, entry in ipairs(lines) do
                        if entry.ts and entry.ts > 0 then
                            local dKey = date("%Y-%m-%d", entry.ts)
                            if dKey ~= lastDayKey then
                                lastDayKey = dKey
                                lastPairKey = nil
                                local dLabel = (dKey == todayKey and L["Today"])
                                    or (dKey == yesterdayKey and L["Yesterday"])
                                    or date("%d/%m/%Y", entry.ts)
                                msgFrame:AddMessage("|cff7f8a9c—— " .. dLabel .. " ——|r")
                            end
                        end
                        local tsRaw = entry.ts and entry.ts > 0 and date("[%H:%M]", entry.ts) or nil
                        local ts = tsRaw and (entry.isStatusNotice and ("|cff9da7b5" .. tsRaw .. "|r ") or ("|Haddon:SCentral:msgact:" .. tostring(msgIdx) .. "|h|cff9da7b5" .. tsRaw .. "|r|h ")) or ""
                        if entry.isStatusNotice then
                            local sCol = (entry.statusKind == "DND") and "|cfff54747" or "|cffff9b3d"
                            msgFrame:AddMessage(ts .. sCol .. "[" .. (entry.sender or L["Status"]) .. "]|r |cffb8c2d0" .. (entry.text or "") .. "|r")
                        elseif isNotes then
                            local delLink = entry.noteId and ("|Haddon:SCentral:delnote:" .. tostring(entry.noteId) .. "|h|cffff6b6b[x]|r|h ") or ""
                            msgFrame:AddMessage(ts .. delLink .. "|cffffd24d" .. (entry.sender or "") .. "|r: " .. (entry.text or ""))
                        else
                            local addonTag = (entry.viaAddon and not isRoom) and "|cff3fb950[SC]|r " or ""
                            local mentionPrefix = entry.isMention and "|cffffd24d[@]|r " or ""
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
                            local isDirectMsg = (not isRoom) and (not isNotes) and (not entry.isSystem)
                                and (active.kind == "WHISPER" or active.kind == "BN_WHISPER")
                                and (entry.sender ~= L["System"])
                            if isDirectMsg and entry.targetChar and entry.targetChar ~= "" then
                                local sLk = Compat.ParseCharacterFields and Compat.ParseCharacterFields(entry.sender) or tostring(entry.sender):lower()
                                local tLk = Compat.ParseCharacterFields and Compat.ParseCharacterFields(entry.targetChar) or tostring(entry.targetChar):lower()
                                local pairKey = (sLk < tLk) and (sLk .. "|" .. tLk) or (tLk .. "|" .. sLk)
                                if pairKey ~= lastPairKey then
                                    lastPairKey = pairKey
                                    local myChar = entry.incoming and entry.targetChar or entry.sender
                                    local myClass = entry.incoming and entry.targetClass or entry.classFile
                                    local myFac = entry.incoming and entry.targetFaction or entry.senderFaction
                                    local peerChar = entry.incoming and entry.sender or entry.targetChar
                                    local peerClass = entry.incoming and entry.classFile or entry.targetClass
                                    local peerFac = entry.incoming and entry.senderFaction or entry.targetFaction
                                    if (not myFac or myFac == "") and myChar then
                                        myFac = (Compat.ResolveCharacterFaction and Compat.ResolveCharacterFaction(myChar))
                                            or (ns.Chat and ns.Chat.GetKnownCharacterFaction and ns.Chat:GetKnownCharacterFaction(myChar))
                                    end
                                    if (not peerFac or peerFac == "") and peerChar then
                                        peerFac = (Compat.ResolveCharacterFaction and Compat.ResolveCharacterFaction(peerChar, nil, active.bnetAccountID))
                                            or (ns.Chat and ns.Chat.GetKnownCharacterFaction and ns.Chat:GetKnownCharacterFaction(peerChar, nil, active.bnetAccountID))
                                    end
                                    local myFacIco = (myFac and Compat.FactionIconMarkup and Compat.FactionIconMarkup(myFac, 11)) or ""
                                    local peerFacIco = (peerFac and Compat.FactionIconMarkup and Compat.FactionIconMarkup(peerFac, 11)) or ""
                                    local myHex = (myClass and Compat.ClassHex(myClass)) or "|cff58a6ff"
                                    local peerHex = (peerClass and Compat.ClassHex(peerClass)) or "|cffd2a8ff"
                                    msgFrame:AddMessage("|cff7f8a9c—— |r" .. myFacIco .. myHex .. myChar .. "|r |cff7f8a9c&|r " .. peerFacIco .. peerHex .. peerChar .. "|r |cff7f8a9c——|r")
                                end
                            end
                            local sFac = entry.senderFaction
                            if isDirectMsg and (not sFac or sFac == "") and entry.sender and entry.sender ~= "" then
                                sFac = (Compat.ResolveCharacterFaction and Compat.ResolveCharacterFaction(entry.sender, nil, entry.incoming and active.bnetAccountID or nil))
                                    or (ns.Chat and ns.Chat.GetKnownCharacterFaction and ns.Chat:GetKnownCharacterFaction(entry.sender, nil, entry.incoming and active.bnetAccountID or nil))
                            end
                            local shortSender = entry.sender or ""
                            if isDirectMsg and shortSender ~= "" and Compat.ParseCharacterFields then
                                local _, sFirst = Compat.ParseCharacterFields(shortSender)
                                if sFirst and sFirst ~= "" then
                                    shortSender = sFirst
                                end
                            end
                            local sFacIco = (isDirectMsg and sFac and Compat.FactionIconMarkup and Compat.FactionIconMarkup(sFac, 12)) or ""
                            local hex = entry.classFile and Compat.ClassHex(entry.classFile) or (entry.incoming and "|cffd2a8ff" or "|cff58a6ff")
                            local senderDisp = sFacIco .. hex .. shortSender .. "|r"
                            msgFrame:AddMessage(ts .. mentionPrefix .. addonTag .. senderDisp .. ": " .. (entry.text or "") .. tick)
                        end
                    end
                end
                if msgFrame.ScrollToBottom then
                    msgFrame:ScrollToBottom()
                end
                btnScrollBottom:Hide()
            end
        else
            hdrTitle:SetText(L["Select a conversation or create a Private Room"])
            peerStatusText:SetText("")
            peerStatusIcon:Hide()
            peerStatusHover._tipTitle = nil
            peerStatusHover._tipDesc = nil
            pinnedBanner:Hide()
            btnVerify:Hide()
            btnRoomInvite:Hide()
            btnLeaveRoom:Hide()
            btnTargetCard:Hide()
            btnPinLoc:Hide()
            btnThreadActions:Hide()
            btnMarkRead:Hide()
            btnClearNotes:Hide()
            btnMuteThread:Hide()
            hdrTitle:ClearAllPoints()
            hdrTitle:SetPoint("LEFT", 2, 0)
            hdrTitle:SetPoint("RIGHT", rightHdr, "RIGHT", -4, 0)
            officialBar:Hide()
            composer:Show()
            btnSend:SetEnabled(false)
            btnQuickReply:SetEnabled(false)
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
            if btn == "RightButton" and self._item and self._item.def and self._item.isActive and MenuUtil and MenuUtil.CreateContextMenu then
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
        local boonTag = (ns.WorldBuffs and ns.WorldBuffs.IsChronoboonSuspended and ns.WorldBuffs:IsChronoboonSuspended())
            and ("  ·  |cff70b5ff[" .. L["Chronoboon Displacer Active"] .. "]|r")
            or ""
        countLbl:SetText(L["%d / %d Active · %d Capital Drops Ready · Open World & Dungeons"]:format(#activeList, #allDefs, readyCount) .. boonTag)

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

local EQUIP_DISPLAY_ORDER = { 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

local EQUIP_SLOT_LABEL_KEYS = {
    [1] = "Head",
    [2] = "Neck",
    [3] = "Shoulders",
    [4] = "Shirt",
    [5] = "Chest",
    [6] = "Waist",
    [7] = "Legs",
    [8] = "Feet",
    [9] = "Wrist",
    [10] = "Hands",
    [11] = "Ring 1",
    [12] = "Ring 2",
    [13] = "Trinket 1",
    [14] = "Trinket 2",
    [15] = "Cloak",
    [16] = "Main Hand",
    [17] = "Off Hand",
    [18] = "Ranged",
    [19] = "Tabard",
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

local function GetSlotLabel(slotId)
    local key = EQUIP_SLOT_LABEL_KEYS[slotId]
    if key and L[key] then
        return L[key]
    end
    local raw = slotId and SLOT_INFO_NAMES[slotId]
    return raw and raw:gsub("Slot$", "") or L["Empty Slot"]
end

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

local function ResolveItemDisplayName(item)
    if ns.Alts and ns.Alts.ResolveItemName then
        local n = ns.Alts:ResolveItemName(item)
        if n and n ~= "" then return n end
    end
    local n = item and ExtractLinkName(item.link) or ""
    if n ~= "" then return n end
    if item and item.itemID then
        return "Item #" .. tostring(item.itemID)
    end
    return ""
end

local function FormatDurationCompact(sec)
    local s = tonumber(sec) or 0
    if ns.Clan and ns.Clan.FormatResetDuration then
        return ns.Clan:FormatResetDuration(s)
    end
    if s <= 0 then return "0m" end
    local days = math.floor(s / 86400)
    local hrs = math.floor((s % 86400) / 3600)
    local mins = math.floor((s % 3600) / 60)
    if days > 0 then return ("%dd %dh"):format(days, hrs) end
    if hrs > 0 then return ("%dh %dm"):format(hrs, mins) end
    return ("%dm"):format(math.max(1, mins))
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
    if slotId then
        GameTooltip:SetText(GetSlotLabel(slotId), 1, 0.82, 0)
    else
        GameTooltip:SetText(L["Empty Slot"], 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local altRemoveModal

local function CurrentAltKey()
    if Store and Store.GetCurrentAltKey then
        return Store:GetCurrentAltKey()
    end
    return Compat.CharacterKey and Compat.CharacterKey() or nil
end
local function EnsureAltRemoveModal()
    if altRemoveModal then
        Theme:ApplyBackdrop(altRemoveModal, "window")
        Theme:StyleButton(altRemoveModal.topCloseBtn, "default")
        Theme:StyleButton(altRemoveModal.btnConfirm, "danger")
        Theme:StyleButton(altRemoveModal.btnCancel, "default")
        return altRemoveModal
    end

    local m = CreateFrame("Frame", "SocialCentralRemoveAltModal", UIParent, "BackdropTemplate")
    m:SetSize(400, 168)
    m:SetPoint("CENTER")
    m:SetFrameStrata("DIALOG")
    m:SetFrameLevel(125)
    m:EnableMouse(true)
    Theme:MakeMovable(m, { key = "modal_alt_remove" })
    table.insert(UISpecialFrames, "SocialCentralRemoveAltModal")
    m:Hide()

    local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetPoint("TOPRIGHT", -42, -14)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText("|cfff54747" .. L["Remove Alt"] .. "|r")
    if Theme.DecorateSectionHeader then
        Theme:DecorateSectionHeader(m, title, 340)
    end

    local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
    topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
    topCloseBtn:SetScript("OnClick", function() m:Hide() end)
    m.topCloseBtn = topCloseBtn

    local desc = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", 16, -44)
    desc:SetPoint("TOPRIGHT", -16, -44)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    m.desc = desc

    local btnConfirm = Theme:CreateButton(m, 118, 24, L["Remove Alt"], "danger")
    Theme:AutoFitButton(btnConfirm, 102, 18)
    btnConfirm:SetPoint("BOTTOMRIGHT", -16, 14)
    m.btnConfirm = btnConfirm

    local btnCancel = Theme:CreateButton(m, 90, 24, L["Cancel"], "default")
    Theme:AutoFitButton(btnCancel, 84, 18)
    btnCancel:SetPoint("RIGHT", btnConfirm, "LEFT", -8, 0)
    m.btnCancel = btnCancel
    btnCancel:SetScript("OnClick", function() m:Hide() end)

    btnConfirm:SetScript("OnClick", function()
        local key = m._altKey
        local onDone = m._onRemoved
        m:Hide()
        if key and ns.Alts and ns.Alts.RemoveAlt then
            if ns.Alts:RemoveAlt(key) and type(onDone) == "function" then
                onDone(key)
            end
        end
    end)

    Theme:ApplyBackdrop(m, "window")
    altRemoveModal = m
    return m
end

local function OpenAltRemoveModal(altData, onRemoved)
    if not altData or not altData.key then return end
    if altData.key == CurrentAltKey() then
        ns:Print(L["Cannot remove the currently logged-in character."])
        return
    end
    local m = EnsureAltRemoveModal()
    m._altKey = altData.key
    m._onRemoved = onRemoved
    local hex = Compat.ClassHex(altData.classFile)
    local disp = hex .. (altData.fullName or altData.name or altData.key) .. "|r"
    m.desc:SetText(L["Remove the saved local snapshot for %s?\n\nThis does not affect your character in-game, and it will be recorded again if you log in with it."]:format(disp))
    m:Show()
end

local function OpenItemContextMenu(anchor, itemData, onSearchAllAlts)
    if not itemData then return end
    local itemName = ResolveItemDisplayName(itemData)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(anchor, function(_, root)
            local r, g, b = GetQualityRGB(itemData.quality)
            local hex = ("|cff%02x%02x%02x"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
            root:CreateTitle(hex .. (itemName ~= "" and itemName or L["Items"]) .. "|r")
            if itemName ~= "" and type(onSearchAllAlts) == "function" then
                root:CreateButton(L["Search this item across all Alts"], function()
                    onSearchAllAlts(itemName)
                end)
            end
            if itemData.link and ChatEdit_InsertLink then
                root:CreateButton(L["Insert link in chat"], function()
                    ChatEdit_InsertLink(itemData.link)
                end)
            end
            if itemName ~= "" and ns.UI and ns.UI.OpenCopyModal then
                root:CreateButton(L["Copy Name"], function()
                    ns.UI:OpenCopyModal(itemName)
                end)
            end
        end)
    elseif itemName ~= "" and type(onSearchAllAlts) == "function" then
        onSearchAllAlts(itemName)
    end
end

local function GetSortedAltsList(sortBy)
    local raw = (Store and Store.GetAltsList and Store:GetAltsList()) or {}
    local out = {}
    for i = 1, #raw do
        out[i] = raw[i]
    end
    local curKey = CurrentAltKey()
    if sortBy == "gold" then
        table.sort(out, function(a, b)
            local am, bm = tonumber(a.money) or 0, tonumber(b.money) or 0
            if am ~= bm then return am > bm end
            return (a.fullName or a.name or "") < (b.fullName or b.name or "")
        end)
    elseif sortBy == "level" then
        table.sort(out, function(a, b)
            local al, bl = tonumber(a.level) or 0, tonumber(b.level) or 0
            if al ~= bl then return al > bl end
            local ax = (tonumber(a.xp) or 0) / math.max(1, tonumber(a.xpMax) or 1)
            local bx = (tonumber(b.xp) or 0) / math.max(1, tonumber(b.xpMax) or 1)
            if ax ~= bx then return ax > bx end
            return (a.lastActive or 0) > (b.lastActive or 0)
        end)
    elseif sortBy == "mail" then
        table.sort(out, function(a, b)
            local am, bm = a.hasMail == true, b.hasMail == true
            if am ~= bm then return am end
            if am and (a.mailSince or 0) ~= (b.mailSince or 0) then
                return (a.mailSince or 0) < (b.mailSince or 0)
            end
            local ac, bc = (a.key == curKey), (b.key == curKey)
            if ac ~= bc then return ac end
            return (a.lastActive or 0) > (b.lastActive or 0)
        end)
    elseif sortBy == "name" then
        table.sort(out, function(a, b)
            return (a.fullName or a.name or ""):lower() < (b.fullName or b.name or ""):lower()
        end)
    end
    return out
end

local function ShowAltTooltip(anchor, altData)
    if not (GameTooltip and altData) then return end
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    local curKey = CurrentAltKey()
    local isCurrent = (altData.key == curKey)
    local hex = Compat.ClassHex(altData.classFile)
    local dispName = altData.fullName or altData.name or altData.key or "?"
    local titleRight = isCurrent and ("|cff3fb950[" .. L["Current"] .. "]|r") or Compat.FormatRelativeTime(altData.lastActive, L)
    GameTooltip:AddDoubleLine(hex .. dispName .. "|r", titleRight)

    local lvl = tonumber(altData.level) or 0
    local classLoc = altData.className or (altData.classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[altData.classFile]) or altData.classFile or ""
    local raceLoc = altData.raceName or ""
    local raceClass = (raceLoc ~= "" and classLoc ~= "") and (raceLoc .. " " .. classLoc) or (classLoc ~= "" and classLoc or raceLoc)
    local facLbl = altData.faction == "Alliance" and L["Alliance"] or (altData.faction == "Horde" and L["Horde"] or "")
    GameTooltip:AddDoubleLine(("%s %d · %s"):format(L["Level"], lvl, raceClass), facLbl, 0.90, 0.92, 0.96, 0.72, 0.84, 1.0)

    if altData.guild and altData.guild ~= "" then
        GameTooltip:AddDoubleLine(L["Guild"], "<" .. altData.guild .. ">", 0.75, 0.78, 0.85, 0.35, 0.92, 0.55)
    end
    if altData.itemLevel and altData.itemLevel > 0 then
        GameTooltip:AddDoubleLine("Item Level", tostring(math.floor(altData.itemLevel)), 0.75, 0.78, 0.85, 1.0, 0.85, 0.35)
    end
    if lvl < 60 then
        local xpVal = tonumber(altData.xp) or 0
        local xpMaxVal = math.max(1, tonumber(altData.xpMax) or 1)
        local xpPct = math.min(100, math.floor((xpVal / xpMaxVal) * 100 + 0.5))
        local restedVal = tonumber(altData.rested) or 0
        local restPct = math.min(150, math.floor((restedVal / xpMaxVal) * 100 + 0.5))
        local xpStr = restPct > 0 and ("%d%% (+%d%% %s)"):format(xpPct, restPct, L["Rested"]) or ("%d%%"):format(xpPct)
        GameTooltip:AddDoubleLine(L["Experience"], xpStr, 0.75, 0.78, 0.85, restPct > 0 and 0.45 or 0.92, restPct > 0 and 0.76 or 0.94, 1.0)
    end

    GameTooltip:AddDoubleLine(L["Zone"], (altData.zone and altData.zone ~= "") and altData.zone or "-", 0.75, 0.78, 0.85, 1, 1, 1)
    if altData.bindLocation and altData.bindLocation ~= "" then
        local bindStr = altData.bindLocation
        if ns.Alts and ns.Alts.GetHearthstoneStatus then
            local hsReadyAt, hsRem = ns.Alts:GetHearthstoneStatus(altData)
            if hsReadyAt ~= nil then
                bindStr = bindStr .. ((hsRem and hsRem > 1) and (" [" .. FormatDurationCompact(hsRem) .. "]") or (" [" .. L["Ready"] .. "]"))
            end
        end
        GameTooltip:AddDoubleLine(L["Hearthstone"], bindStr, 0.75, 0.78, 0.85, 0.65, 0.88, 1.0)
    end

    GameTooltip:AddDoubleLine(L["Gold (%s)"]:format(altData.fullName or altData.name or dispName), Compat.FormatMoney(altData.money or 0), 0.75, 0.78, 0.85, 1, 1, 1)

    local bagCap = altData.bagTotal or 0
    local bagFree = tonumber(altData.bagFree) or 0
    local bagUsed = math.max(0, bagCap - bagFree)
    GameTooltip:AddDoubleLine(L["Bags"], ("%d / %d (%s)"):format(bagUsed, bagCap, L["%d free"]:format(bagFree)), 0.75, 0.78, 0.85, 0.92, 0.94, 0.96)

    if type(altData.bank) == "table" then
        local bStr = ("%d %s"):format(#altData.bank, L["items"])
        if altData.bankUpdatedAt and altData.bankUpdatedAt > 0 then
            bStr = bStr .. " · " .. Compat.FormatRelativeTime(altData.bankUpdatedAt, L)
        end
        GameTooltip:AddDoubleLine(L["Bank"], bStr, 0.75, 0.78, 0.85, 0.92, 0.94, 0.96)
    end

    if ns.Alts and ns.Alts.GetMailStatus then
        local hasMail, ageDays, _, senders = ns.Alts:GetMailStatus(altData)
        if hasMail then
            local mTxt = (ageDays > 0) and L["Detected %dd ago"]:format(ageDays) or L["Pending Mail"]
            if type(senders) == "table" and #senders > 0 then
                mTxt = mTxt .. " (" .. table.concat(senders, ", ") .. ")"
            end
            GameTooltip:AddDoubleLine(L["Mailbox"], mTxt, 0.75, 0.78, 0.85, 1.0, ageDays >= 15 and 0.42 or 0.82, 0.28)
        end
    end

    if type(altData.professions) == "table" and #altData.professions > 0 then
        local pNames = {}
        for _, pr in ipairs(altData.professions) do
            if pr and pr.name and pr.isPrimary then
                pNames[#pNames + 1] = ("%s (%d/%d)"):format(pr.name, pr.rank or 0, pr.maxRank or 0)
            end
        end
        if #pNames > 0 then
            GameTooltip:AddDoubleLine(L["Professions"], table.concat(pNames, ", "), 0.75, 0.78, 0.85, 0.35, 0.92, 0.55)
        end
    end

    if ns.Alts and ns.Alts.GetLockouts then
        local locks = ns.Alts:GetLockouts(altData)
        if #locks > 0 then
            GameTooltip:AddDoubleLine(L["Active Lockouts"], ("%d (%s)"):format(#locks, FormatDurationCompact(locks[1].reset)), 0.75, 0.78, 0.85, 1.0, 0.65, 0.30)
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Right-click to inspect, copy Armory URL, or remove."], 0.58, 0.72, 0.92, true)
    GameTooltip:Show()
end

local function ShowGoldBreakdownTooltip(anchor)
    if not GameTooltip then return end
    local list = GetSortedAltsList("gold")
    local myFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    local byFac = (Store and Store.GetTotalAltsGoldByFaction and Store:GetTotalAltsGoldByFaction(true)) or nil
    local facTot = (byFac and myFac and byFac[myFac]) or (Store and Store.GetTotalAltsGold and Store:GetTotalAltsGold(true, true)) or 0
    local allTot = (byFac and byFac.total) or facTot
    local hasDualFaction = byFac and (byFac.Alliance or 0) > 0 and (byFac.Horde or 0) > 0

    GameTooltip:SetOwner(anchor, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddDoubleLine(L["Gold Breakdown"], Compat.FormatMoney(hasDualFaction and facTot or allTot), 1.0, 0.85, 0.25, 1.0, 1.0, 1.0)
    if hasDualFaction then
        GameTooltip:AddDoubleLine("|cff70b5ff" .. L["Alliance"] .. "|r", Compat.FormatMoney(byFac.Alliance or 0), 0.65, 0.82, 1.0, 1, 1, 1)
        GameTooltip:AddDoubleLine("|cffff7878" .. L["Horde"] .. "|r", Compat.FormatMoney(byFac.Horde or 0), 1.0, 0.65, 0.65, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    local denom = hasDualFaction and nil or allTot
    for _, alt in ipairs(list) do
        local hex = Compat.ClassHex(alt.classFile)
        local disp = alt.fullName or alt.name or alt.key or "?"
        local m = tonumber(alt.money) or 0
        local facDenominator = denom or (alt.faction and byFac and byFac[alt.faction]) or allTot
        local pct = (facDenominator > 0) and math.floor((m / facDenominator) * 100 + 0.5) or 0
        local facTag = hasDualFaction and (alt.faction == "Alliance" and " |cff70b5ff[A]|r" or (alt.faction == "Horde" and " |cffff7878[H]|r" or "")) or ""
        local leftTxt = hex .. disp .. "|r" .. facTag .. ((facDenominator > 0 and #list > 1) and (" |cff9da7b5(" .. pct .. "%)|r") or "")
        GameTooltip:AddDoubleLine(leftTxt, Compat.FormatMoney(m))
    end
    GameTooltip:Show()
end

local function ConsolidateItems(rawList, isEquip)
    if type(rawList) ~= "table" then return {} end
    if isEquip then return rawList end
    local out = {}
    local byKey = {}
    for _, item in ipairs(rawList) do
        if type(item) == "table" and (item.icon or item.itemID or item.link) then
            local k = item.link or (item.itemID and ("id:" .. tostring(item.itemID))) or nil
            local qty = math.max(1, tonumber(item.count) or 1)
            if k and byKey[k] then
                byKey[k].count = byKey[k].count + qty
            else
                local copy = {
                    itemID = item.itemID,
                    link = item.link,
                    name = item.name,
                    icon = item.icon,
                    quality = item.quality,
                    count = qty,
                    _isEquip = item._isEquip,
                    _slotId = item._slotId,
                    _locLabel = item._locLabel,
                }
                if k then byKey[k] = copy end
                out[#out + 1] = copy
            end
        end
    end
    return out
end

function SocialPanels:CreateAltsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel:Hide()
    panel._bagSource = "all" -- "all" | "equip" | "bags" | "bank"
    panel._allAltsScope = false
    panel._viewMode = "grid" -- "grid" | "list"
    panel._sortBy = "recent" -- "recent" | "gold" | "level" | "mail" | "name"
    panel._subTab = "overview" -- "alts" (narrow only) | "overview" | "items" | "gear"
    panel._narrowTabPicked = false
    panel._selectedKey = CurrentAltKey()
    panel._userPickedAlt = false

    local SORT_MODES = {
        { id = "recent", label = L["Sort: Recent"] },
        { id = "gold", label = L["Sort: Gold"] },
        { id = "level", label = L["Sort: Level"] },
        { id = "mail", label = L["Sort: Mail"] },
        { id = "name", label = L["Sort: Name"] },
    }

    local function GetSortLabel(modeId)
        for _, m in ipairs(SORT_MODES) do
            if m.id == modeId then return m.label end
        end
        return L["Sort: Recent"]
    end

    local function GetSelectedAlt()
        local myKey = CurrentAltKey()
        local list = GetSortedAltsList(panel._sortBy)
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

    local function IsNarrowLayout()
        local w = math.floor((panel:GetWidth() or 560) + 0.5)
        return w < 580, w
    end

    local function OpenAltActionMenu(anchor, altData)
        if not altData then return end
        local function CopyArmory()
            local url = ns.Alts and ns.Alts:GetArmoryURL(altData)
            if url and ns.UI and ns.UI.OpenCopyModal then
                ns.UI:OpenCopyModal(url, L["Web Armory Link"], L["Blizzard's addon sandbox prohibits external internet requests. Copy this link to open your Web Armory in a browser:"])
            end
        end
        local function SelectSubTab(subId)
            panel._userPickedAlt = true
            panel._selectedKey = altData.key
            panel._narrowTabPicked = true
            panel._subTab = subId
            panel:Refresh(true)
        end
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(anchor, function(_, root)
                local hex = Compat.ClassHex(altData.classFile)
                root:CreateTitle(hex .. (altData.fullName or altData.name or altData.key) .. "|r")
                root:CreateButton(L["Inspect Character"], function() SelectSubTab("overview") end)
                root:CreateButton(L["Items"], function() SelectSubTab("items") end)
                root:CreateButton(L["Gear"], function() SelectSubTab("gear") end)
                root:CreateDivider()
                root:CreateButton(L["Web Armory Link"], CopyArmory)
                if altData.key ~= CurrentAltKey() then
                    root:CreateButton("|cfff54747" .. L["Remove Alt"] .. "|r", function()
                        OpenAltRemoveModal(altData, function()
                            panel._userPickedAlt = false
                            panel._selectedKey = CurrentAltKey()
                            panel:Refresh(true)
                        end)
                    end)
                end
            end)
        else
            SelectSubTab("overview")
        end
    end

    -- Narrow Top Character Bar (clears CharacterFrame portrait & Settings/Update buttons)
    local topBar = CreateFrame("Frame", nil, panel)
    topBar:SetHeight(24)
    panel.topBar = topBar

    local charBtn = Theme:CreateButton(topBar, 168, 22, "...", "default")
    charBtn:SetPoint("LEFT", 0, 0)
    charBtn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Help: Select Character & Armory"], 1, 0.9, 0.55, true)
        GameTooltip:AddLine(L["Click to pick any saved character on this server or copy their Web Armory profile URL."], 0.85, 0.88, 0.94, true)
        GameTooltip:Show()
    end)
    charBtn:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)

    local charHelpBtn = AddHelp(
        topBar,
        charBtn,
        L["Help: Select Character & Armory"],
        L["Switches between your recorded characters on this WoW Forever realm pool to inspect equipped gear, bags, bank, professions, and gold."],
        L["Select any character or use the filter dropdown ('All', 'Equipped', 'Bags', 'Bank'), search by item name, or access Web Armory / Remove actions inside the character menu."],
        "LEFT",
        "RIGHT",
        4,
        0
    )

    -- Narrow Sub-Tab Strip (Alts | Overview | Items | Gear)
    local narrowTabBar = CreateFrame("Frame", nil, panel)
    narrowTabBar:SetHeight(24)
    narrowTabBar:Hide()

    local btnNarrowAlts = Theme:CreateButton(narrowTabBar, 76, 22, L["Alts"], "tab")
    local btnNarrowOverview = Theme:CreateButton(narrowTabBar, 76, 22, L["Overview"], "tab")
    local btnNarrowItems = Theme:CreateButton(narrowTabBar, 76, 22, L["Items"], "tab")
    local btnNarrowGear = Theme:CreateButton(narrowTabBar, 76, 22, L["Gear"], "tab")

    -- Left Column: All Account Alts Roster + Gold Vault Footer
    local rosterPane = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    Theme:ApplyBackdrop(rosterPane, "inset")
    panel._rosterPane = rosterPane

    local rosterHeader = CreateFrame("Frame", nil, rosterPane)
    rosterHeader:SetPoint("TOPLEFT", rosterPane, "TOPLEFT", 2, -2)
    rosterHeader:SetPoint("TOPRIGHT", rosterPane, "TOPRIGHT", -2, -2)
    rosterHeader:SetHeight(28)

    local rosterHdrBg = rosterHeader:CreateTexture(nil, "BACKGROUND", nil, -6)
    rosterHdrBg:SetAllPoints()
    rosterHdrBg:SetTexture(WHITE8X8)
    rosterHdrBg:SetVertexColor(0.14, 0.11, 0.08, 1.0)

    local rosterHdrLine = rosterHeader:CreateTexture(nil, "ARTWORK", nil, 1)
    rosterHdrLine:SetHeight(1)
    rosterHdrLine:SetPoint("BOTTOMLEFT", rosterHeader, "BOTTOMLEFT", 0, 0)
    rosterHdrLine:SetPoint("BOTTOMRIGHT", rosterHeader, "BOTTOMRIGHT", 0, 0)
    rosterHdrLine:SetTexture(WHITE8X8)
    rosterHdrLine:SetVertexColor(0.65, 0.50, 0.22, 0.85)

    local rosterHelpBtn = AddHelp(
        rosterHeader,
        rosterHeader,
        L["Help: Alts Roster & Gold"],
        L["Shows all recorded characters on this WoW Forever realm pool with class, level, gold, rested XP, bag space, pending mail, professions, and active lockouts."],
        L["Click any character to inspect it, hover the bottom gold bar for a per-alt breakdown, or right-click a row to copy Armory URL or remove old alts."],
        "RIGHT",
        "RIGHT",
        -4,
        0
    )

    local rosterSortBtn = Theme:CreateButton(rosterHeader, 98, 20, L["Sort: Recent"] .. "  v", "default")
    Theme:AutoFitButton(rosterSortBtn, 72, 12, 126)
    rosterSortBtn:SetHeight(20)
    rosterSortBtn:SetPoint("RIGHT", rosterHelpBtn or rosterHeader, rosterHelpBtn and "LEFT" or "RIGHT", -4, 0)

    local rosterTitleLbl = rosterHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rosterTitleLbl:SetPoint("LEFT", rosterHeader, "LEFT", 8, 0)
    rosterTitleLbl:SetPoint("RIGHT", rosterSortBtn, "LEFT", -6, 0)
    rosterTitleLbl:SetJustifyH("LEFT")
    rosterTitleLbl:SetWordWrap(false)

    -- Gold Vault Footer at bottom of Roster Pane
    local goldBar = CreateFrame("Frame", nil, rosterPane)
    goldBar:SetPoint("BOTTOMLEFT", rosterPane, "BOTTOMLEFT", 2, 2)
    goldBar:SetPoint("BOTTOMRIGHT", rosterPane, "BOTTOMRIGHT", -2, 2)
    goldBar:SetHeight(32)
    goldBar:EnableMouse(true)

    local goldBarBg = goldBar:CreateTexture(nil, "BACKGROUND", nil, -6)
    goldBarBg:SetAllPoints()
    goldBarBg:SetTexture(WHITE8X8)
    goldBarBg:SetVertexColor(0.15, 0.12, 0.06, 1.0)

    local goldBarLine = goldBar:CreateTexture(nil, "ARTWORK", nil, 1)
    goldBarLine:SetHeight(1)
    goldBarLine:SetPoint("TOPLEFT", goldBar, "TOPLEFT", 0, 0)
    goldBarLine:SetPoint("TOPRIGHT", goldBar, "TOPRIGHT", 0, 0)
    goldBarLine:SetTexture(WHITE8X8)
    goldBarLine:SetVertexColor(0.75, 0.58, 0.22, 0.90)

    local goldVaultLbl = goldBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    goldVaultLbl:SetPoint("LEFT", goldBar, "LEFT", 8, 0)
    goldVaultLbl:SetJustifyH("LEFT")
    goldVaultLbl:SetWordWrap(false)

    local goldVaultVal = goldBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    goldVaultVal:SetPoint("RIGHT", goldBar, "RIGHT", -8, 0)
    goldVaultVal:SetJustifyH("RIGHT")
    goldVaultVal:SetWordWrap(false)
    goldVaultLbl:SetPoint("RIGHT", goldVaultVal, "LEFT", -6, 0)

    goldBar:SetScript("OnEnter", function(selfBar)
        ShowGoldBreakdownTooltip(selfBar)
    end)
    goldBar:SetScript("OnLeave", function(selfBar)
        if GameTooltip and GameTooltip:IsOwned(selfBar) then GameTooltip:Hide() end
    end)

    local rosterScroll = Theme:CreateScrollList(rosterPane, 58, function(rowParent, _, rowHeight)
        local row = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
        row:SetHeight(rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.statusBar = row:CreateTexture(nil, "ARTWORK", nil, 2)
        row.statusBar:SetWidth(3)
        row.statusBar:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -4)
        row.statusBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 4)

        row.classIcon = row:CreateTexture(nil, "ARTWORK", nil, 2)
        row.classIcon:SetSize(22, 22)
        row.classIcon:SetPoint("TOPLEFT", row, "TOPLEFT", 9, -6)
        row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")

        row.goldText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.goldText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
        row.goldText:SetJustifyH("RIGHT")
        row.goldText:SetWordWrap(false)

        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.nameText:SetPoint("TOPLEFT", row.classIcon, "TOPRIGHT", 7, 1)
        row.nameText:SetPoint("RIGHT", row.goldText, "LEFT", -6, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)

        row.badgesText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.badgesText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -23)
        row.badgesText:SetJustifyH("RIGHT")
        row.badgesText:SetWordWrap(false)

        row.zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.zoneText:SetPoint("TOPLEFT", row.classIcon, "TOPRIGHT", 7, -16)
        row.zoneText:SetPoint("RIGHT", row.badgesText, "LEFT", -6, 0)
        row.zoneText:SetJustifyH("LEFT")
        row.zoneText:SetWordWrap(false)

        row.seenText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.seenText:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 5)
        row.seenText:SetJustifyH("RIGHT")
        row.seenText:SetWordWrap(false)

        row.profText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.profText:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 5)
        row.profText:SetPoint("RIGHT", row.seenText, "LEFT", -6, 0)
        row.profText:SetJustifyH("LEFT")
        row.profText:SetWordWrap(false)

        row:SetScript("OnClick", function(selfRow, button)
            local alt = selfRow._alt
            if not alt then return end
            if button == "RightButton" then
                OpenAltActionMenu(selfRow, alt)
                return
            end
            panel._userPickedAlt = true
            panel._selectedKey = alt.key
            local narrow = IsNarrowLayout()
            if narrow then
                panel._narrowTabPicked = true
                panel._subTab = "overview"
            end
            panel:Refresh(true)
        end)
        row:SetScript("OnEnter", function(selfRow)
            ShowAltTooltip(selfRow, selfRow._alt)
        end)
        row:SetScript("OnLeave", function(selfRow)
            if GameTooltip and GameTooltip:IsOwned(selfRow) then GameTooltip:Hide() end
        end)

        return row
    end, function(row, alt, _, pal)
        row._alt = alt
        local curKey = CurrentAltKey()
        local isCurrent = (alt.key == curKey)
        local isSelected = (alt.key == panel._selectedKey)

        if isSelected then
            Theme:ApplyBackdrop(row, "surface", pal)
            row.statusBar:SetColorTexture(1.0, 0.82, 0.12, 1.0)
        elseif isCurrent then
            row.statusBar:SetColorTexture(0.24, 0.86, 0.46, 0.95)
        else
            row.statusBar:SetColorTexture(0.55, 0.44, 0.22, 0.35)
        end

        local coords = alt.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[alt.classFile]
        if coords then
            row.classIcon:SetTexCoord(coords[1] + 0.02, coords[2] - 0.02, coords[3] + 0.02, coords[4] - 0.02)
            row.classIcon:Show()
        else
            row.classIcon:Hide()
        end

        local fac = alt.faction or (Compat.ResolveCharacterFaction and Compat.ResolveCharacterFaction(alt.fullName or alt.name or alt.key))
        local facIco = (fac and Compat.FactionIconMarkup and Compat.FactionIconMarkup(fac, 12)) or ""
        local hex = Compat.ClassHex(alt.classFile)
        local disp = alt.fullName or alt.name or alt.key or "?"
        local lvl = tonumber(alt.level) or 0
        row.nameText:SetText(("%s%s%s|r |cffc6ceda%s|r"):format(facIco, hex, disp, L["Lv %d"]:format(lvl)))
        row.goldText:SetText(Compat.FormatMoney(alt.money or 0))

        local badgeParts = {}
        if ns.Alts and ns.Alts.GetMailStatus then
            local hasMail, ageDays = ns.Alts:GetMailStatus(alt)
            if hasMail then
                if ageDays >= 15 then
                    badgeParts[#badgeParts + 1] = ("|cfff54747[%s %dd!]|r"):format(L["Mailbox"], ageDays)
                else
                    badgeParts[#badgeParts + 1] = "|cffffd24d[" .. L["Mailbox"] .. "]|r"
                end
            end
        end
        if lvl < 60 then
            local xpMax = math.max(1, tonumber(alt.xpMax) or 1)
            local rested = tonumber(alt.rested) or 0
            if rested > 0 then
                local rPct = math.min(150, math.floor((rested / xpMax) * 100 + 0.5))
                badgeParts[#badgeParts + 1] = (rPct >= 148)
                    and ("|cff58a6ff[" .. L["150% MAX"] .. "]|r")
                    or ("|cff58a6ff[" .. rPct .. "%]|r")
            end
        end
        local bagCap = alt.bagTotal or 0
        local bagFree = tonumber(alt.bagFree) or 0
        if bagCap > 0 and bagFree <= 3 then
            local bCol = (bagFree <= 1) and "|cfff54747" or "|cffff9b3d"
            badgeParts[#badgeParts + 1] = bCol .. "[" .. L["%d free"]:format(bagFree) .. "]|r"
        end
        row.badgesText:SetText(table.concat(badgeParts, " "))

        local zoneStr = (alt.zone and alt.zone ~= "") and alt.zone or ((alt.guild and alt.guild ~= "") and ("<" .. alt.guild .. ">") or "-")
        row.zoneText:SetText(zoneStr)
        row.zoneText:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])

        local profParts = {}
        if type(alt.professions) == "table" then
            for _, pr in ipairs(alt.professions) do
                if pr and pr.name and pr.isPrimary then
                    profParts[#profParts + 1] = ("%s %d"):format(pr.name, pr.rank or 0)
                end
            end
        end
        row.profText:SetText(#profParts > 0 and table.concat(profParts, " · ") or L["No professions learned"])

        local lockCount = (ns.Alts and ns.Alts.GetLockouts) and #ns.Alts:GetLockouts(alt) or 0
        local rightFoot = isCurrent and ("|cff3fb950" .. L["Current"] .. "|r") or Compat.FormatRelativeTime(alt.lastActive, L)
        if lockCount > 0 then
            rightFoot = ("|cffff9b3d%s|r · %s"):format(L["%d lockouts"]:format(lockCount), rightFoot)
        end
        row.seenText:SetText(rightFoot)
    end)
    rosterScroll.container:ClearAllPoints()
    rosterScroll.container:SetPoint("TOPLEFT", rosterHeader, "BOTTOMLEFT", 2, -2)
    rosterScroll.container:SetPoint("BOTTOMRIGHT", goldBar, "TOPRIGHT", -2, 2)

    -- Right Column: Inspector Pane (Header + Sub-Tabs + Overview / Items / Gear)
    local inspectorPane = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    Theme:ApplyBackdrop(inspectorPane, "inset")
    panel._inspectorPane = inspectorPane

    local charHeader = CreateFrame("Frame", nil, inspectorPane)
    charHeader:SetPoint("TOPLEFT", inspectorPane, "TOPLEFT", 2, -2)
    charHeader:SetPoint("TOPRIGHT", inspectorPane, "TOPRIGHT", -2, -2)
    charHeader:SetHeight(44)

    local charHdrBg = charHeader:CreateTexture(nil, "BACKGROUND", nil, -6)
    charHdrBg:SetAllPoints()
    charHdrBg:SetTexture(WHITE8X8)
    charHdrBg:SetVertexColor(0.14, 0.11, 0.08, 1.0)

    local charHdrLine = charHeader:CreateTexture(nil, "ARTWORK", nil, 1)
    charHdrLine:SetHeight(1)
    charHdrLine:SetPoint("BOTTOMLEFT", charHeader, "BOTTOMLEFT", 0, 0)
    charHdrLine:SetPoint("BOTTOMRIGHT", charHeader, "BOTTOMRIGHT", 0, 0)
    charHdrLine:SetTexture(WHITE8X8)
    charHdrLine:SetVertexColor(0.65, 0.50, 0.22, 0.85)

    local charIcon = charHeader:CreateTexture(nil, "ARTWORK", nil, 2)
    charIcon:SetSize(28, 28)
    charIcon:SetPoint("LEFT", charHeader, "LEFT", 8, 0)
    charIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")

    local headerHelpBtn = AddHelp(
        charHeader,
        charHeader,
        L["Help: Character Inspector & Actions"],
        L["Displays the selected character's full profile, quick Web Armory link, and character management actions."],
        L["Click 'Armory' to copy the Web Armory URL, use 'Actions' to inspect or remove an offline alt, and switch between 'Overview', 'Items', and 'Gear' below."],
        "RIGHT",
        "RIGHT",
        -6,
        0
    )

    local btnActions = Theme:CreateButton(charHeader, 76, 22, L["Actions"] .. "  v", "default")
    Theme:AutoFitButton(btnActions, 64, 12, 108)
    btnActions:SetPoint("RIGHT", headerHelpBtn or charHeader, headerHelpBtn and "LEFT" or "RIGHT", -4, 0)

    local btnArmory = Theme:CreateButton(charHeader, 68, 22, L["Armory"], "default")
    Theme:AutoFitButton(btnArmory, 56, 12, 92)
    btnArmory:SetPoint("RIGHT", btnActions, "LEFT", -4, 0)
    btnArmory:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Web Armory Link"], 1, 0.9, 0.55, true)
        GameTooltip:AddLine(L["Click to copy this character's Web Armory profile URL."], 0.85, 0.88, 0.94, true)
        GameTooltip:Show()
    end)
    btnArmory:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)

    local charTitleLbl = charHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    charTitleLbl:SetPoint("TOPLEFT", charIcon, "TOPRIGHT", 8, -1)
    charTitleLbl:SetPoint("RIGHT", btnArmory, "LEFT", -8, 0)
    charTitleLbl:SetJustifyH("LEFT")
    charTitleLbl:SetWordWrap(false)

    local charSubLbl = charHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charSubLbl:SetPoint("BOTTOMLEFT", charIcon, "BOTTOMRIGHT", 8, 1)
    charSubLbl:SetPoint("RIGHT", btnArmory, "LEFT", -8, 0)
    charSubLbl:SetJustifyH("LEFT")
    charSubLbl:SetWordWrap(false)

    -- Wide Sub-Tabs Bar (Overview | Items | Gear)
    local wideTabBar = CreateFrame("Frame", nil, inspectorPane)
    wideTabBar:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 4, -4)
    wideTabBar:SetPoint("TOPRIGHT", charHeader, "BOTTOMRIGHT", -4, -4)
    wideTabBar:SetHeight(26)

    local btnWideOverview = Theme:CreateButton(wideTabBar, 88, 22, L["Overview"], "tab")
    Theme:AutoFitButton(btnWideOverview, 74, 14, 120)
    btnWideOverview:SetPoint("LEFT", wideTabBar, "LEFT", 2, 0)

    local btnWideItems = Theme:CreateButton(wideTabBar, 82, 22, L["Items"], "tab")
    Theme:AutoFitButton(btnWideItems, 68, 14, 110)
    btnWideItems:SetPoint("LEFT", btnWideOverview, "RIGHT", 4, 0)

    local btnWideGear = Theme:CreateButton(wideTabBar, 88, 22, L["Gear"], "tab")
    Theme:AutoFitButton(btnWideGear, 72, 14, 120)
    btnWideGear:SetPoint("LEFT", btnWideItems, "RIGHT", 4, 0)

    local wideSummaryLbl = wideTabBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wideSummaryLbl:SetPoint("LEFT", btnWideGear, "RIGHT", 8, 0)
    wideSummaryLbl:SetPoint("RIGHT", wideTabBar, "RIGHT", -4, 0)
    wideSummaryLbl:SetJustifyH("RIGHT")
    wideSummaryLbl:SetWordWrap(false)

    local subArea = CreateFrame("Frame", nil, inspectorPane)
    subArea:SetPoint("TOPLEFT", wideTabBar, "BOTTOMLEFT", 0, -4)
    subArea:SetPoint("BOTTOMRIGHT", inspectorPane, "BOTTOMRIGHT", -4, 4)

    -- ========================================================================
    -- Sub-View 1: Overview (Rich Character Dossier with Bars, Profs, Lockouts)
    -- ========================================================================
    local overviewFrame = CreateFrame("Frame", nil, subArea)
    overviewFrame:SetAllPoints()

    local overviewScroll = CreateFrame("ScrollFrame", nil, overviewFrame)
    overviewScroll:SetPoint("TOPLEFT", 2, -2)
    overviewScroll:SetPoint("BOTTOMRIGHT", -2, 2)
    overviewScroll:SetClipsChildren(true)
    overviewScroll:EnableMouseWheel(true)

    local overviewContent = CreateFrame("Frame", nil, overviewScroll)
    overviewContent:SetPoint("TOPLEFT", 0, 0)
    overviewContent:SetSize(300, 200)
    overviewScroll:SetScrollChild(overviewContent)

    local overviewRows, overviewBars, overviewIconRows, overviewSeps = {}, {}, {}, {}
    local overviewMaxScroll = 0

    local function UpdateOverviewScrollBounds()
        local vpH = overviewScroll:GetHeight() or 0
        local contentH = overviewContent:GetHeight() or 0
        overviewMaxScroll = math.max(0, contentH - vpH)
        local cur = overviewScroll:GetVerticalScroll() or 0
        if cur > overviewMaxScroll then
            overviewScroll:SetVerticalScroll(overviewMaxScroll)
        end
        local vpW = overviewScroll:GetWidth() or 300
        if vpW > 60 then
            overviewContent:SetWidth(vpW)
        end
    end

    overviewScroll:SetScript("OnMouseWheel", function(selfScroll, delta)
        if overviewMaxScroll <= 0 then return end
        local cur = selfScroll:GetVerticalScroll() or 0
        local nxt = math.max(0, math.min(overviewMaxScroll, cur - delta * 24))
        selfScroll:SetVerticalScroll(nxt)
    end)
    overviewScroll:SetScript("OnSizeChanged", UpdateOverviewScrollBounds)

    local function AcquireOverviewRow(idx)
        if not overviewRows[idx] then
            local row = CreateFrame("Frame", nil, overviewContent)
            row:SetHeight(18)
            row:EnableMouse(true)
            local lLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lLbl:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -1)
            lLbl:SetJustifyH("LEFT")
            lLbl:SetWordWrap(false)
            local rLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -1)
            rLbl:SetJustifyH("RIGHT")
            rLbl:SetWordWrap(false)
            row.left = lLbl
            row.right = rLbl
            row:SetScript("OnEnter", function(selfRow)
                if not GameTooltip then return end
                local lt, rt = selfRow._leftFull or "", selfRow._rightFull or ""
                if lt == "" and rt == "" then return end
                GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                if rt ~= "" then
                    GameTooltip:AddDoubleLine(lt, rt, 0.85, 0.88, 0.94, 1.0, 1.0, 1.0)
                else
                    GameTooltip:AddLine(lt, 1.0, 0.85, 0.25, true)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(selfRow)
                if GameTooltip and GameTooltip:IsOwned(selfRow) then GameTooltip:Hide() end
            end)
            overviewRows[idx] = row
        end
        return overviewRows[idx]
    end

    local function AcquireOverviewIconRow(idx)
        if not overviewIconRows[idx] then
            local row = CreateFrame("Frame", nil, overviewContent)
            row:SetHeight(20)
            row:EnableMouse(true)
            local ico = row:CreateTexture(nil, "ARTWORK")
            ico:SetSize(16, 16)
            ico:SetPoint("LEFT", row, "LEFT", 6, 0)
            ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local rLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rLbl:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            rLbl:SetJustifyH("RIGHT")
            rLbl:SetWordWrap(false)
            local lLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lLbl:SetPoint("LEFT", ico, "RIGHT", 6, 0)
            lLbl:SetPoint("RIGHT", rLbl, "LEFT", -8, 0)
            lLbl:SetJustifyH("LEFT")
            lLbl:SetWordWrap(false)
            row.icon = ico
            row.left = lLbl
            row.right = rLbl
            row:SetScript("OnEnter", function(selfRow)
                if not GameTooltip then return end
                local lt, rt = selfRow._leftFull or "", selfRow._rightFull or ""
                if lt == "" and rt == "" then return end
                GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                GameTooltip:AddDoubleLine(lt, rt, 0.90, 0.92, 0.96, 1.0, 1.0, 1.0)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(selfRow)
                if GameTooltip and GameTooltip:IsOwned(selfRow) then GameTooltip:Hide() end
            end)
            overviewIconRows[idx] = row
        end
        return overviewIconRows[idx]
    end

    local function AcquireOverviewBar(idx)
        if not overviewBars[idx] then
            local bar = CreateFrame("Frame", nil, overviewContent, "BackdropTemplate")
            bar:SetHeight(18)
            Theme:ApplyBackdrop(bar, "inset")
            local fill = bar:CreateTexture(nil, "ARTWORK", nil, 1)
            fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 2, -2)
            fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 2, 2)
            fill:SetTexture(WHITE8X8)
            local subFill = bar:CreateTexture(nil, "ARTWORK", nil, 0)
            subFill:SetPoint("TOPLEFT", bar, "TOPLEFT", 2, -2)
            subFill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 2, 2)
            subFill:SetTexture(WHITE8X8)
            subFill:Hide()
            local lbl = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lbl:SetPoint("LEFT", bar, "LEFT", 6, 0)
            lbl:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
            lbl:SetJustifyH("CENTER")
            lbl:SetWordWrap(false)
            bar.fill = fill
            bar.subFill = subFill
            bar.label = lbl
            overviewBars[idx] = bar
        end
        return overviewBars[idx]
    end

    local function AcquireOverviewSep(idx)
        if not overviewSeps[idx] then
            local sep = overviewContent:CreateTexture(nil, "ARTWORK", nil, 1)
            sep:SetHeight(1)
            sep:SetTexture(WHITE8X8)
            sep:SetVertexColor(0.55, 0.44, 0.20, 0.45)
            overviewSeps[idx] = sep
        end
        return overviewSeps[idx]
    end

    local function RenderOverview(altData, resetScroll)
        for i = 1, #overviewRows do overviewRows[i]:Hide() end
        for i = 1, #overviewBars do overviewBars[i]:Hide() end
        for i = 1, #overviewIconRows do overviewIconRows[i]:Hide() end
        for i = 1, #overviewSeps do overviewSeps[i]:Hide() end

        if not altData then
            overviewContent:SetHeight(24)
            UpdateOverviewScrollBounds()
            return
        end

        local cw = math.max(220, (overviewScroll:GetWidth() or 320) - 4)
        overviewContent:SetWidth(cw)
        local rIdx, bIdx, iIdx, sIdx, yOff = 0, 0, 0, 0, 2

        local function AddLine(leftTxt, rightTxt, lr, lg, lb, rr, rg, rb, stepH)
            rIdx = rIdx + 1
            local row = AcquireOverviewRow(rIdx)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", overviewContent, "TOPLEFT", 0, -yOff)
            row:SetPoint("TOPRIGHT", overviewContent, "TOPRIGHT", 0, -yOff)
            row._leftFull = leftTxt or ""
            row._rightFull = rightTxt or ""
            row.left:SetText(leftTxt or "")
            row.left:SetTextColor(lr or 0.78, lg or 0.80, lb or 0.86)
            row.right:SetText(rightTxt or "")
            row.right:SetTextColor(rr or 1.0, rg or 1.0, rb or 1.0)
            row.left:ClearAllPoints()
            row.left:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -1)
            if rightTxt and rightTxt ~= "" then
                local rightMax = math.floor(cw * 0.62)
                row.right:SetWidth(0)
                local rw = math.min(rightMax, math.ceil(row.right:GetStringWidth() or 60) + 4)
                row.right:SetWidth(math.max(24, rw))
                row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
            else
                row.right:SetWidth(0)
                row.left:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            end
            row:Show()
            yOff = yOff + (stepH or 18)
        end

        local function AddBar(pct, r, g, b, text, subPct, sr, sg, sb)
            bIdx = bIdx + 1
            local bar = AcquireOverviewBar(bIdx)
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", overviewContent, "TOPLEFT", 4, -yOff)
            bar:SetPoint("TOPRIGHT", overviewContent, "TOPRIGHT", -4, -yOff)
            local innerW = math.max(40, cw - 12)
            local clamped = math.max(0, math.min(1, pct or 0))
            if clamped > 0.01 then
                bar.fill:SetWidth(math.max(3, math.floor(innerW * clamped)))
                bar.fill:SetVertexColor(r, g, b, 0.82)
                bar.fill:Show()
            else
                bar.fill:Hide()
            end
            if subPct and subPct > clamped then
                local sClamped = math.max(0, math.min(1, subPct))
                bar.subFill:SetWidth(math.max(3, math.floor(innerW * sClamped)))
                bar.subFill:SetVertexColor(sr or 0.25, sg or 0.55, sb or 0.95, 0.55)
                bar.subFill:Show()
            else
                bar.subFill:Hide()
            end
            bar.label:SetText(text or "")
            bar:Show()
            yOff = yOff + 22
        end

        local function AddIconLine(tex, leftTxt, rightTxt, lr, lg, lb, rr, rg, rb)
            iIdx = iIdx + 1
            local row = AcquireOverviewIconRow(iIdx)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", overviewContent, "TOPLEFT", 0, -yOff)
            row:SetPoint("TOPRIGHT", overviewContent, "TOPRIGHT", 0, -yOff)
            row.icon:SetTexture(tex or 136243)
            row._leftFull = leftTxt or ""
            row._rightFull = rightTxt or ""
            row.left:SetText(leftTxt or "")
            row.left:SetTextColor(lr or 0.90, lg or 0.92, lb or 0.96)
            row.right:SetText(rightTxt or "")
            row.right:SetTextColor(rr or 0.35, rg or 0.92, rb or 0.55)
            row:Show()
            yOff = yOff + 20
        end

        local function AddSep()
            sIdx = sIdx + 1
            local sep = AcquireOverviewSep(sIdx)
            sep:ClearAllPoints()
            sep:SetPoint("TOPLEFT", overviewContent, "TOPLEFT", 4, -(yOff + 3))
            sep:SetPoint("TOPRIGHT", overviewContent, "TOPRIGHT", -4, -(yOff + 3))
            sep:Show()
            yOff = yOff + 8
        end

        -- 1. Experience / Rested Progress + Item Level
        local lvl = tonumber(altData.level) or 0
        if lvl >= 60 then
            local rightLvl = (altData.itemLevel and altData.itemLevel > 0) and ("Item Level " .. math.floor(altData.itemLevel)) or ""
            AddLine(L["Experience"] .. ": |cff3fb950" .. L["Max Level"] .. "|r", rightLvl, 0.85, 0.88, 0.94, 1.0, 0.85, 0.35, 19)
        else
            local xpVal = tonumber(altData.xp) or 0
            local xpMaxVal = math.max(1, tonumber(altData.xpMax) or 1)
            local xpFrac = math.max(0, math.min(1, xpVal / xpMaxVal))
            local xpPct = math.floor(xpFrac * 100 + 0.5)
            local restedVal = tonumber(altData.rested) or 0
            local restPct = math.min(150, math.floor((restedVal / xpMaxVal) * 100 + 0.5))
            local restTag = ""
            if restPct > 0 then
                restTag = (restPct >= 148)
                    and (" · |cff58a6ff" .. L["150% MAX"] .. "|r")
                    or (" · |cff58a6ff+" .. L["Rested: %d%%"]:format(restPct) .. "|r")
            end
            local barText = ("%s %d · %d%%%s"):format(L["Level"], lvl, xpPct, restTag)
            local subFrac = (restedVal > 0) and math.min(1, xpFrac + (restedVal / xpMaxVal)) or nil
            AddBar(xpFrac, 0.58, 0.34, 0.88, barText, subFrac, 0.25, 0.56, 0.96)
            if altData.itemLevel and altData.itemLevel > 0 then
                AddLine("Item Level", tostring(math.floor(altData.itemLevel)), 0.75, 0.78, 0.85, 1.0, 0.85, 0.35, 18)
            end
        end

        -- 2. Bags Capacity Bar & Bank Snapshot
        local bagFreeVal = tonumber(altData.bagFree) or 0
        local bagCap = altData.bagTotal or 0
        local bagUsed = math.max(0, bagCap - bagFreeVal)
        local bagFrac = (bagCap > 0) and (bagUsed / bagCap) or 0
        local br, bg, bb = 0.24, 0.72, 0.42
        if bagCap > 0 and bagFreeVal <= 1 then
            br, bg, bb = 0.88, 0.26, 0.26
        elseif bagCap > 0 and bagFreeVal <= 4 then
            br, bg, bb = 0.92, 0.56, 0.20
        end
        AddBar(bagFrac, br, bg, bb, ("%s: %d / %d (%s)"):format(L["Bags"], bagUsed, bagCap, L["%d free"]:format(bagFreeVal)))

        if type(altData.bank) == "table" then
            local bankUsed = math.max(0, (altData.bankTotal or 0) - (altData.bankFree or 0))
            local bankStr = (altData.bankTotal and altData.bankTotal > 0)
                and (L["%d / %d slots"]:format(bankUsed, altData.bankTotal) .. " (" .. #altData.bank .. " " .. L["items"] .. ")")
                or ("%d %s"):format(#altData.bank, L["items"])
            if altData.bankUpdatedAt and altData.bankUpdatedAt > 0 then
                bankStr = bankStr .. " · " .. Compat.FormatRelativeTime(altData.bankUpdatedAt, L)
            end
            AddLine(L["Bank"], bankStr, 0.75, 0.78, 0.85, 0.92, 0.94, 0.96, 18)
        else
            AddLine(L["Bank"], L["Visit a Bank NPC to snapshot bank items."], 0.75, 0.78, 0.85, 0.58, 0.62, 0.68, 18)
        end

        AddSep()

        -- 3. Location, Hearthstone, Mail & Gold
        local zoneTxt = (altData.zone and altData.zone ~= "") and altData.zone or "-"
        AddLine(L["Zone"], zoneTxt, 0.75, 0.78, 0.85, 1.0, 1.0, 1.0, 18)

        local bindTxt = (altData.bindLocation and altData.bindLocation ~= "") and altData.bindLocation or "-"
        if ns.Alts and ns.Alts.GetHearthstoneStatus and altData.bindLocation and altData.bindLocation ~= "" then
            local hsReadyAt, hsRem = ns.Alts:GetHearthstoneStatus(altData)
            if hsReadyAt ~= nil then
                if hsRem and hsRem > 1 then
                    bindTxt = bindTxt .. " |cffff9b3d[" .. FormatDurationCompact(hsRem) .. "]|r"
                else
                    bindTxt = bindTxt .. " |cff3fb950[" .. L["Ready"] .. "]|r"
                end
            end
        end
        AddLine(L["Hearthstone"], bindTxt, 0.75, 0.78, 0.85, 0.65, 0.88, 1.0, 18)

        if ns.Alts and ns.Alts.GetMailStatus then
            local hasMail, ageDays, _, senders = ns.Alts:GetMailStatus(altData)
            if hasMail then
                local tagCol = ageDays >= 15 and "|cfff54747" or "|cffffd24d"
                local mStr = tagCol .. "[" .. L["Pending Mail"] .. "]|r"
                if ageDays > 0 then
                    mStr = mStr .. " " .. L["Detected %dd ago"]:format(ageDays)
                end
                if type(senders) == "table" and #senders > 0 then
                    mStr = mStr .. " · " .. table.concat(senders, ", ")
                end
                AddLine(L["Mailbox"], mStr, 0.75, 0.78, 0.85, 1.0, ageDays >= 15 and 0.45 or 0.82, 0.30, 18)
            end
        end

        local charGoldLabel = altData.fullName or altData.name or "?"
        local myMoney = tonumber(altData.money) or 0
        local charGold = Compat.FormatMoney(myMoney)
        AddLine(L["Gold (%s)"]:format(charGoldLabel), charGold, 1.0, 0.84, 0.25, 1.0, 1.0, 1.0, 18)
        local altFac = altData.faction or true
        local facGoldNum = (Store and Store.GetTotalAltsGold and Store:GetTotalAltsGold(true, altFac)) or myMoney
        local sameFacCount = 0
        for _, rec in ipairs((Store and Store.GetAltsList and Store:GetAltsList()) or {}) do
            if type(rec) == "table" and (altData.faction == nil or rec.faction == altData.faction) then
                sameFacCount = sameFacCount + 1
            end
        end
        if sameFacCount > 1 or facGoldNum > myMoney then
            local facSuffix = (altData.faction == "Alliance" and (" (" .. L["Alliance"] .. ")"))
                or (altData.faction == "Horde" and (" (" .. L["Horde"] .. ")"))
                or ""
            AddLine(L["Total Server Gold"] .. facSuffix, Compat.FormatMoney(facGoldNum), 1.0, 0.84, 0.25, 1.0, 1.0, 1.0, 18)
        end

        AddSep()

        -- 4. Professions with icons & zero truncation
        AddLine(L["Professions"], "", 1.0, 0.82, 0.0, 1.0, 0.82, 0.0, 18)
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
            local function RenderProfList(plist, isPrim)
                for _, pr in ipairs(plist) do
                    local rank = pr.rank or 0
                    local maxR = pr.maxRank or 0
                    local rankStr = (maxR > 0) and ("%d / %d"):format(rank, maxR) or tostring(rank)
                    local isCap = (maxR > 0 and rank >= maxR)
                    AddIconLine(
                        pr.icon or 136243,
                        pr.name,
                        rankStr,
                        isPrim and 0.94 or 0.80,
                        isPrim and 0.96 or 0.84,
                        isPrim and 1.0 or 0.90,
                        isCap and 0.35 or 1.0,
                        isCap and 0.92 or 0.82,
                        isCap and 0.55 or 0.35
                    )
                end
            end
            RenderProfList(primaryList, true)
            RenderProfList(secondaryList, false)
        else
            AddLine("  " .. L["No professions learned"], "", 0.62, 0.65, 0.70, 0.62, 0.65, 0.70, 18)
        end

        AddSep()

        -- 5. Active Dungeon / Raid Lockouts
        AddLine(L["Active Lockouts"], "", 1.0, 0.82, 0.0, 1.0, 0.82, 0.0, 18)
        local locks = (ns.Alts and ns.Alts.GetLockouts) and ns.Alts:GetLockouts(altData) or {}
        if #locks > 0 then
            for _, lk in ipairs(locks) do
                local tag = lk.isRaid and ("|cffff8040[" .. L["Raid"] .. "]|r ") or ""
                local diff = (lk.difficultyName and lk.difficultyName ~= "") and (" |cff9da7b5[" .. lk.difficultyName .. "]|r") or ""
                local boss = ((lk.numEncounters or 0) > 0) and (" · " .. lk.encounterProgress .. "/" .. lk.numEncounters .. " " .. L["Bosses"]) or ""
                local leftTxt = tag .. (lk.name or "?") .. diff .. boss
                local rightTxt = L["Resets in"] .. " " .. FormatDurationCompact(lk.reset or 0)
                AddLine("  " .. leftTxt, rightTxt, 0.92, 0.94, 0.98, 1.0, 0.74, 0.36, 18)
            end
        else
            AddLine("  " .. L["No active dungeon or raid lockouts."], "", 0.62, 0.65, 0.70, 0.62, 0.65, 0.70, 18)
        end

        overviewContent:SetHeight(math.max(24, yOff + 6))
        if resetScroll then
            overviewScroll:SetVerticalScroll(0)
        end
        UpdateOverviewScrollBounds()
    end

    -- ========================================================================
    -- Sub-View 2: Items (Search + Scope + Filter + Grid/List Toggle)
    -- ========================================================================
    local itemsFrame = CreateFrame("Frame", nil, subArea)
    itemsFrame:SetAllPoints()
    itemsFrame:Hide()

    local itemsToolbar = CreateFrame("Frame", nil, itemsFrame)
    itemsToolbar:SetPoint("TOPLEFT", itemsFrame, "TOPLEFT", 2, -2)
    itemsToolbar:SetPoint("TOPRIGHT", itemsFrame, "TOPRIGHT", -2, -2)
    itemsToolbar:SetHeight(26)

    local bagSearch = Theme:CreateEditBox(itemsToolbar, {
        width = 148,
        height = 22,
        placeholder = L["Search items..."],
        clearButton = true,
    })

    local filterBtn = Theme:CreateButton(itemsToolbar, 88, 22, L["All"] .. "  v", "default")
    filterBtn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Filter Items"], 1, 0.9, 0.55, true)
        GameTooltip:AddLine(L["Filter by source: All, Equipped, Bags, or Bank."], 0.85, 0.88, 0.94, true)
        GameTooltip:Show()
    end)
    filterBtn:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)

    local scopeBtn = Theme:CreateButton(itemsToolbar, 92, 22, L["This Alt"], "default")
    scopeBtn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["All Alts"], 1, 0.9, 0.55, true)
        GameTooltip:AddLine(L["Toggle between searching only the selected alt or all saved alts."], 0.85, 0.88, 0.94, true)
        GameTooltip:Show()
    end)
    scopeBtn:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)

    local viewModeBtn = Theme:CreateButton(itemsToolbar, 64, 22, L["Grid"], "default")
    viewModeBtn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Grid"] .. " / " .. L["List"], 1, 0.9, 0.55, true)
        GameTooltip:AddLine(L["Click 'Grid' or 'List' to switch item view mode."], 0.85, 0.88, 0.94, true)
        GameTooltip:Show()
    end)
    viewModeBtn:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)

    local itemsHelpBtn = AddHelp(
        itemsToolbar,
        viewModeBtn,
        L["Help: Alt Items & Account Search"],
        L["Browse equipped items, bags, and bank snapshots in a compact 2D icon grid or readable name list, across either one character or your entire account."],
        L["Type to search by item name, toggle 'All Alts' to search across every character, switch between 'Grid' and 'List', Shift+Click to link in chat, or Right-Click any item to find it across all alts."],
        "LEFT",
        "RIGHT",
        4,
        0
    )

    local infoLbl = itemsToolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoLbl:SetJustifyH("RIGHT")
    infoLbl:SetWordWrap(false)

    local itemsCard = CreateFrame("Frame", nil, itemsFrame, "BackdropTemplate")
    itemsCard:SetPoint("TOPLEFT", itemsToolbar, "BOTTOMLEFT", 0, -4)
    itemsCard:SetPoint("BOTTOMRIGHT", itemsFrame, "BOTTOMRIGHT", -2, 2)
    Theme:ApplyBackdrop(itemsCard, "inset")

    local function TriggerSearchAllAlts(itemName)
        if not itemName or itemName == "" then return end
        panel._allAltsScope = true
        panel._bagSource = "all"
        panel._subTab = "items"
        panel._narrowTabPicked = true
        bagSearch:SetText(itemName)
        panel:Refresh(true)
    end

    local bagGridScroll = Theme:CreateScrollList(itemsCard, 40, function(rowParent, _, rowHeight)
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
            cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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

            cell:SetScript("OnEnter", function(selfCell)
                if selfCell._item then
                    ShowItemTooltip(selfCell, selfCell._item, selfCell._item._slotId)
                end
            end)
            cell:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
            cell:SetScript("OnClick", function(selfCell, button)
                if not selfCell._item then return end
                if button == "RightButton" then
                    OpenItemContextMenu(selfCell, selfCell._item, TriggerSearchAllAlts)
                    return
                end
                if selfCell._item.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
                    ChatEdit_InsertLink(selfCell._item.link)
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
    bagGridScroll.container:ClearAllPoints()
    bagGridScroll.container:SetAllPoints(itemsCard)

    local bagListScroll = Theme:CreateScrollList(itemsCard, 32, function(rowParent, _, rowHeight)
        local row = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
        row:SetHeight(rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local headerTitle = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        headerTitle:SetPoint("LEFT", row, "LEFT", 8, 0)
        headerTitle:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        headerTitle:SetJustifyH("LEFT")
        headerTitle:SetWordWrap(false)
        headerTitle:Hide()
        row._headerTitle = headerTitle

        local headerLine = row:CreateTexture(nil, "ARTWORK")
        headerLine:SetHeight(1)
        headerLine:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 2)
        headerLine:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 2)
        headerLine:SetTexture(WHITE8X8)
        headerLine:SetVertexColor(0.55, 0.44, 0.20, 0.75)
        headerLine:Hide()
        row._headerLine = headerLine

        local iconBox = CreateFrame("Frame", nil, row, "BackdropTemplate")
        iconBox:SetSize(24, 24)
        iconBox:SetPoint("LEFT", row, "LEFT", 8, 0)
        iconBox._scNoStone = true
        Theme:ApplyBackdrop(iconBox, "inset")
        row.iconBox = iconBox

        local icon = iconBox:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", -2, 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = icon

        local rightLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rightLbl:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        rightLbl:SetJustifyH("RIGHT")
        rightLbl:SetWordWrap(false)
        row.rightLbl = rightLbl

        local nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameLbl:SetPoint("LEFT", iconBox, "RIGHT", 8, 0)
        nameLbl:SetPoint("RIGHT", rightLbl, "LEFT", -8, 0)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetWordWrap(false)
        row.nameLbl = nameLbl

        row:SetScript("OnEnter", function(selfRow)
            if selfRow._item then
                ShowItemTooltip(selfRow, selfRow._item, selfRow._item._slotId)
            end
        end)
        row:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        row:SetScript("OnClick", function(selfRow, button)
            if not selfRow._item then return end
            if button == "RightButton" then
                OpenItemContextMenu(selfRow, selfRow._item, TriggerSearchAllAlts)
                return
            end
            if selfRow._item.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
                ChatEdit_InsertLink(selfRow._item.link)
            end
        end)
        return row
    end, function(row, rowData)
        if rowData.isHeader then
            row._item = nil
            row.iconBox:Hide()
            row.nameLbl:Hide()
            row.rightLbl:Hide()
            row._headerTitle:SetText(rowData.title or "")
            row._headerTitle:Show()
            row._headerLine:Show()
            return
        end

        row._headerTitle:Hide()
        row._headerLine:Hide()
        local item = rowData.item
        row._item = item
        if not item then
            row.iconBox:Hide()
            row.nameLbl:Hide()
            row.rightLbl:Hide()
            return
        end

        row.iconBox:Show()
        row.nameLbl:Show()
        row.rightLbl:Show()
        row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local r, g, b = GetQualityRGB(item.quality)
        row.iconBox:SetBackdropBorderColor(r, g, b, 1.0)
        local qtyStr = (item.count and item.count > 1) and (" |cffffffffx" .. item.count .. "|r") or ""
        local iName = ResolveItemDisplayName(item)
        row.nameLbl:SetText(iName .. qtyStr)
        row.nameLbl:SetTextColor(r, g, b)

        local locParts = {}
        if item._locLabel and item._locLabel ~= "" then
            locParts[#locParts + 1] = item._locLabel
        end
        if item.itemID and ns.Alts and ns.Alts.GetAccountItemTotal then
            local acctTot = ns.Alts:GetAccountItemTotal(item.itemID, panel._inspectedFaction)
            if acctTot > (item.count or 1) then
                locParts[#locParts + 1] = "|cffffd24d" .. L["Account: %d"]:format(acctTot) .. "|r"
            end
        end
        row.rightLbl:SetText(table.concat(locParts, " · "))
    end)
    bagListScroll.container:ClearAllPoints()
    bagListScroll.container:SetAllPoints(itemsCard)
    bagListScroll.container:Hide()

    -- ========================================================================
    -- Sub-View 3: Equipped Gear (2D Slot Sheet with All 19 Slots)
    -- ========================================================================
    local gearFrame = CreateFrame("Frame", nil, subArea)
    gearFrame:SetAllPoints()
    gearFrame:Hide()

    local gearTopBar = CreateFrame("Frame", nil, gearFrame)
    gearTopBar:SetPoint("TOPLEFT", gearFrame, "TOPLEFT", 4, -2)
    gearTopBar:SetPoint("TOPRIGHT", gearFrame, "TOPRIGHT", -4, -2)
    gearTopBar:SetHeight(24)

    local gearHelpBtn = AddHelp(
        gearTopBar,
        gearTopBar,
        L["Help: Equipped Gear (2D)"],
        L["Shows all 19 equipment slots in a lightweight 2D overview, including empty slots."],
        L["Hover any slot for the full tooltip, Shift+Click to insert the item link in chat, or Right-Click to search for that item across all your alts."],
        "RIGHT",
        "RIGHT",
        -2,
        0
    )

    local gearSummaryLbl = gearTopBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gearSummaryLbl:SetPoint("LEFT", gearTopBar, "LEFT", 4, 0)
    gearSummaryLbl:SetPoint("RIGHT", gearHelpBtn or gearTopBar, gearHelpBtn and "LEFT" or "RIGHT", -8, 0)
    gearSummaryLbl:SetJustifyH("LEFT")
    gearSummaryLbl:SetWordWrap(false)

    local gearScroll = Theme:CreateScrollList(gearFrame, 40, function(rowParent, _, rowHeight)
        local row = CreateFrame("Frame", nil, rowParent)
        row:SetHeight(rowHeight)
        row._cells = {}
        for c = 1, 2 do
            local cell = CreateFrame("Button", nil, row, "BackdropTemplate")
            cell:SetHeight(36)
            cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            Theme:ApplyBackdrop(cell, "inset")

            local iconBox = CreateFrame("Frame", nil, cell, "BackdropTemplate")
            iconBox:SetSize(28, 28)
            iconBox:SetPoint("LEFT", cell, "LEFT", 5, 0)
            iconBox._scNoStone = true
            Theme:ApplyBackdrop(iconBox, "inset")
            cell.iconBox = iconBox

            local tex = iconBox:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", 2, -2)
            tex:SetPoint("BOTTOMRIGHT", -2, 2)
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            cell.icon = tex

            local hl = cell:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.92, 0.65, 0.08)

            local slotLbl = cell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            slotLbl:SetPoint("TOPLEFT", iconBox, "TOPRIGHT", 7, -1)
            slotLbl:SetPoint("RIGHT", cell, "RIGHT", -6, 0)
            slotLbl:SetJustifyH("LEFT")
            slotLbl:SetWordWrap(false)
            cell.slotLbl = slotLbl

            local itemLbl = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            itemLbl:SetPoint("BOTTOMLEFT", iconBox, "BOTTOMRIGHT", 7, 1)
            itemLbl:SetPoint("RIGHT", cell, "RIGHT", -6, 0)
            itemLbl:SetJustifyH("LEFT")
            itemLbl:SetWordWrap(false)
            cell.itemLbl = itemLbl

            cell:SetScript("OnEnter", function(selfCell)
                ShowItemTooltip(selfCell, selfCell._item, selfCell._slotId)
            end)
            cell:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
            cell:SetScript("OnClick", function(selfCell, button)
                if not selfCell._item then return end
                if button == "RightButton" then
                    OpenItemContextMenu(selfCell, selfCell._item, TriggerSearchAllAlts)
                    return
                end
                if selfCell._item.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
                    ChatEdit_InsertLink(selfCell._item.link)
                end
            end)
            row._cells[c] = cell
        end
        return row
    end, function(row, rowData, _, pal)
        local cols = rowData.cols or 1
        local rowW = (row:GetWidth() and row:GetWidth() > 40) and row:GetWidth() or 300
        local gap = 6
        local cellW = (cols == 2) and math.floor((rowW - 10 - gap) / 2) or (rowW - 8)
        for c = 1, 2 do
            local cell = row._cells[c]
            local slotData = rowData.slots and rowData.slots[c]
            if c <= cols and slotData then
                cell:ClearAllPoints()
                cell:SetWidth(math.max(120, cellW))
                if c == 1 then
                    cell:SetPoint("LEFT", row, "LEFT", 4, 0)
                else
                    cell:SetPoint("LEFT", row._cells[1], "RIGHT", gap, 0)
                end
                cell._slotId = slotData.slotId
                cell._item = slotData.item
                cell.slotLbl:SetText(GetSlotLabel(slotData.slotId))
                if slotData.item then
                    cell.icon:SetTexture(slotData.item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    cell.icon:SetAlpha(1.0)
                    local r, g, b = GetQualityRGB(slotData.item.quality)
                    cell.iconBox:SetBackdropBorderColor(r, g, b, 1.0)
                    cell.itemLbl:SetText(ResolveItemDisplayName(slotData.item))
                    cell.itemLbl:SetTextColor(r, g, b)
                    Theme:ApplyBackdrop(cell, "surface", pal)
                else
                    cell.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
                    cell.icon:SetAlpha(0.35)
                    cell.iconBox:SetBackdropBorderColor(0.35, 0.32, 0.28, 0.7)
                    cell.itemLbl:SetText(L["Empty Slot"])
                    cell.itemLbl:SetTextColor(0.50, 0.52, 0.56)
                    Theme:ApplyBackdrop(cell, "inset", pal)
                end
                cell:Show()
            else
                cell._slotId = nil
                cell._item = nil
                cell:Hide()
            end
        end
    end)
    gearScroll.container:ClearAllPoints()
    gearScroll.container:SetPoint("TOPLEFT", gearTopBar, "BOTTOMLEFT", -2, -4)
    gearScroll.container:SetPoint("BOTTOMRIGHT", gearFrame, "BOTTOMRIGHT", -2, 2)

    -- ========================================================================
    -- Data Collection & Rendering
    -- ========================================================================
    local function GetFilterButtonLabel(altData)
        if panel._bagSource == "equip" then
            return L["Equipped"] .. "  v"
        elseif panel._bagSource == "bags" then
            if not panel._allAltsScope and altData then
                local used = math.max(0, (altData.bagTotal or 0) - (altData.bagFree or 0))
                return (L["Bags"] .. " (%d/%d)  v"):format(used, altData.bagTotal or 0)
            end
            return L["Bags"] .. "  v"
        elseif panel._bagSource == "bank" then
            if not panel._allAltsScope and altData then
                local used = math.max(0, (altData.bankTotal or 0) - (altData.bankFree or 0))
                return (L["Bank"] .. " (%d/%d)  v"):format(used, altData.bankTotal or 0)
            end
            return L["Bank"] .. "  v"
        end
        return L["All"] .. "  v"
    end

    local function AppendGlobalSearchSections(sections, queryText, excludeAltKey, headingPrefix, srcFilter, factionFilter)
        if not (ns.Alts and ns.Alts.SearchAllItems) then return end
        local groups = ns.Alts:SearchAllItems(queryText, excludeAltKey, srcFilter, factionFilter)
        for _, g in ipairs(groups) do
            local consolidated = ConsolidateItems(g.items, false)
            local hex = Compat.ClassHex(g.classFile)
            local lbl = headingPrefix
                and ("|cff8ab4f8" .. headingPrefix .. "|r " .. hex .. (g.displayName or "?") .. "|r |cffc6ceda(" .. #consolidated .. ")|r")
                or (hex .. (g.displayName or "?") .. "|r |cffc6ceda(" .. #consolidated .. ")|r")
            sections[#sections + 1] = {
                title = lbl,
                items = consolidated,
            }
        end
    end

    local function CollectFilteredItems(altData)
        local src = panel._bagSource or "all"
        local query = Compat.Trim(bagSearch:GetText() or ""):lower()

        if panel._allAltsScope then
            local sections = {}
            local facFilter = (altData and altData.faction) or (Compat.PlayerFaction and Compat.PlayerFaction())
            AppendGlobalSearchSections(sections, query, nil, nil, src, facFilter)
            if #sections == 0 then
                return {}, (query ~= "" and L["No matching items found across any character."] or L["No items recorded yet."])
            end
            return sections, ""
        end

        if not altData then return {}, "" end

        local function MatchesQuery(item)
            if query == "" then return true end
            local iName = ResolveItemDisplayName(item):lower()
            local slotLabel = (item._slotId and GetSlotLabel(item._slotId) or ""):lower()
            return iName:find(query, 1, true) ~= nil or (slotLabel ~= "" and slotLabel:find(query, 1, true) ~= nil)
        end

        local sections = {}

        if (src == "all" or src == "equip") and type(altData.equipment) == "table" then
            panel._equipItemWrappers = panel._equipItemWrappers or {}
            local equipItems = {}
            for _, slotId in ipairs(EQUIP_DISPLAY_ORDER) do
                local entry = altData.equipment[slotId]
                if entry and (entry.icon or entry.itemID or entry.link) then
                    local obj = panel._equipItemWrappers[slotId]
                    if not obj then
                        obj = { count = 1, _isEquip = true, _slotId = slotId, _locLabel = L["Equipped"] }
                        panel._equipItemWrappers[slotId] = obj
                    end
                    obj.icon = entry.icon
                    obj.link = entry.link
                    obj.name = entry.name
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
                    bagItems[#bagItems + 1] = {
                        itemID = item.itemID,
                        link = item.link,
                        name = item.name,
                        icon = item.icon,
                        quality = item.quality,
                        count = item.count or 1,
                        _locLabel = L["Bags"],
                    }
                end
            end
            bagItems = ConsolidateItems(bagItems, false)
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
                    bankItems[#bankItems + 1] = {
                        itemID = item.itemID,
                        link = item.link,
                        name = item.name,
                        icon = item.icon,
                        quality = item.quality,
                        count = item.count or 1,
                        _locLabel = L["Bank"],
                    }
                end
            end
            bankItems = ConsolidateItems(bankItems, false)
            if #bankItems > 0 then
                sections[#sections + 1] = {
                    title = ("|cffffd200%s|r |cffc6ceda(%d)|r"):format(L["Bank"], #bankItems),
                    items = bankItems,
                }
            end
        end

        if #sections == 0 then
            if query ~= "" then
                AppendGlobalSearchSections(sections, query, altData.key, L["Other Alt:"], src, altData.faction or (Compat.PlayerFaction and Compat.PlayerFaction()))
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

    local function RenderItems(altData, resetScroll)
        panel._inspectedFaction = (altData and altData.faction) or (Compat.PlayerFaction and Compat.PlayerFaction())
        Theme:SetButtonText(filterBtn, GetFilterButtonLabel(altData))
        Theme:AutoFitButton(filterBtn, 72, 14, 138)

        Theme:SetButtonText(scopeBtn, panel._allAltsScope and L["All Alts"] or L["This Alt"])
        Theme:AutoFitButton(scopeBtn, 76, 14, 128)
        Theme:SetButtonActive(scopeBtn, panel._allAltsScope == true, "default")

        Theme:SetButtonText(viewModeBtn, (panel._viewMode == "list") and L["List"] or L["Grid"])
        Theme:AutoFitButton(viewModeBtn, 56, 14, 88)
        RelayoutItemsToolbar()

        local sections, emptyMsg = CollectFilteredItems(altData)
        local shownCount = 0
        for _, sec in ipairs(sections) do
            shownCount = shownCount + #sec.items
        end
        infoLbl:SetText(shownCount > 0 and L["%d items"]:format(shownCount) or "")

        local isList = (panel._viewMode == "list")
        bagGridScroll.container:SetShown(not isList)
        bagListScroll.container:SetShown(isList)

        if isList then
            local rows = {}
            for _, sec in ipairs(sections) do
                rows[#rows + 1] = { isHeader = true, title = sec.title }
                for _, it in ipairs(sec.items) do
                    rows[#rows + 1] = { item = it }
                end
            end
            bagListScroll:SetData(rows, emptyMsg, resetScroll)
        else
            local vpW = (bagGridScroll.viewport and bagGridScroll.viewport.GetWidth and bagGridScroll.viewport:GetWidth()) or 0
            if vpW < 80 then
                local isNarrow, pw = IsNarrowLayout()
                local rosterW = isNarrow and 0 or math.max(236, math.min(278, math.floor(pw * 0.34)))
                vpW = math.max(120, pw - rosterW - 36)
            end
            local cols = math.max(1, math.min(18, math.floor((vpW - 8) / 38)))
            local rows = {}
            for _, sec in ipairs(sections) do
                rows[#rows + 1] = { isHeader = true, title = sec.title }
                for i = 1, #sec.items, cols do
                    local chunk = {}
                    for j = 0, cols - 1 do
                        if sec.items[i + j] then
                            chunk[j + 1] = sec.items[i + j]
                        end
                    end
                    rows[#rows + 1] = { cols = cols, items = chunk }
                end
            end
            bagGridScroll:SetData(rows, emptyMsg, resetScroll)
        end
        panel._lastRenderedW = math.floor((panel:GetWidth() or 0) + 0.5)
    end

    local function RenderGear(altData, resetScroll)
        if not altData then
            gearSummaryLbl:SetText("")
            gearScroll:SetData({}, L["No characters recorded yet."], true)
            return
        end
        local eq = type(altData.equipment) == "table" and altData.equipment or {}
        local equippedCount = 0
        for _, slotId in ipairs(EQUIP_DISPLAY_ORDER) do
            local e = eq[slotId]
            if e and (e.icon or e.itemID or e.link) then
                equippedCount = equippedCount + 1
            end
        end
        local sumStr = L["Equipped (%d/%d)"]:format(equippedCount, #EQUIP_DISPLAY_ORDER)
        if altData.itemLevel and altData.itemLevel > 0 then
            sumStr = sumStr .. " · Item Level " .. math.floor(altData.itemLevel)
        end
        gearSummaryLbl:SetText(sumStr)

        local vpW = (gearScroll.viewport and gearScroll.viewport.GetWidth and gearScroll.viewport:GetWidth()) or 0
        if vpW < 80 then
            local isNarrow, pw = IsNarrowLayout()
            local rosterW = isNarrow and 0 or math.max(236, math.min(278, math.floor(pw * 0.34)))
            vpW = math.max(180, pw - rosterW - 36)
        end
        local cols = (vpW >= 400) and 2 or 1
        local rows = {}
        for i = 1, #EQUIP_DISPLAY_ORDER, cols do
            local slots = {}
            for j = 0, cols - 1 do
                local sid = EQUIP_DISPLAY_ORDER[i + j]
                if sid then
                    local raw = eq[sid]
                    local itemObj = nil
                    if raw and (raw.icon or raw.itemID or raw.link) then
                        itemObj = {
                            itemID = raw.itemID,
                            link = raw.link,
                            name = raw.name,
                            icon = raw.icon,
                            quality = raw.quality,
                            count = 1,
                            _isEquip = true,
                            _slotId = sid,
                            _locLabel = L["Equipped"],
                        }
                    end
                    slots[j + 1] = { slotId = sid, item = itemObj }
                end
            end
            rows[#rows + 1] = { cols = cols, slots = slots }
        end
        gearScroll:SetData(rows, L["No characters recorded yet."], resetScroll)
    end

    local function RenderCharHeader(altData)
        if not altData then
            charIcon:Hide()
            charTitleLbl:SetText(L["No characters recorded yet."])
            charSubLbl:SetText("")
            wideSummaryLbl:SetText("")
            btnArmory:SetEnabled(false)
            btnActions:SetEnabled(false)
            return
        end
        btnArmory:SetEnabled(true)
        btnActions:SetEnabled(true)

        local coords = altData.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[altData.classFile]
        if coords then
            charIcon:SetTexCoord(coords[1] + 0.02, coords[2] - 0.02, coords[3] + 0.02, coords[4] - 0.02)
            charIcon:Show()
        else
            charIcon:Hide()
        end

        local fac = altData.faction or (Compat.ResolveCharacterFaction and Compat.ResolveCharacterFaction(altData.fullName or altData.name or altData.key))
        local facIco = (fac and Compat.FactionIconMarkup and Compat.FactionIconMarkup(fac, 14)) or ""
        local hex = Compat.ClassHex(altData.classFile)
        local disp = altData.fullName or altData.name or altData.key or "?"
        local lvl = tonumber(altData.level) or 0
        local classLoc = altData.className or (altData.classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[altData.classFile]) or altData.classFile or ""
        local raceLoc = altData.raceName or ""
        local rc = (raceLoc ~= "" and classLoc ~= "") and (raceLoc .. " " .. classLoc) or (classLoc ~= "" and classLoc or raceLoc)
        charTitleLbl:SetText(("%s%s%s|r |cffc6ceda· %s %d · %s|r"):format(facIco, hex, disp, L["Level"], lvl, rc))

        local subParts = {}
        if altData.guild and altData.guild ~= "" then
            subParts[#subParts + 1] = "<" .. altData.guild .. ">"
        else
            subParts[#subParts + 1] = L["No guild"]
        end
        if altData.faction == "Alliance" then
            subParts[#subParts + 1] = "|cff70b5ff" .. L["Alliance"] .. "|r"
        elseif altData.faction == "Horde" then
            subParts[#subParts + 1] = "|cffff7878" .. L["Horde"] .. "|r"
        end
        if altData.zone and altData.zone ~= "" then
            subParts[#subParts + 1] = altData.zone
        end
        if altData.key == CurrentAltKey() then
            subParts[#subParts + 1] = "|cff3fb950" .. L["Current"] .. "|r"
        elseif altData.lastActive then
            subParts[#subParts + 1] = Compat.FormatRelativeTime(altData.lastActive, L)
        end
        charSubLbl:SetText(table.concat(subParts, " · "))

        local eqCount = 0
        if type(altData.equipment) == "table" then
            for _, sid in ipairs(EQUIP_DISPLAY_ORDER) do
                local e = altData.equipment[sid]
                if e and (e.icon or e.itemID or e.link) then eqCount = eqCount + 1 end
            end
        end
        local bagCap = altData.bagTotal or 0
        local bagUsed = math.max(0, bagCap - (tonumber(altData.bagFree) or 0))
        wideSummaryLbl:SetText(("%d/19 %s · %d/%d %s"):format(eqCount, L["Equipped"], bagUsed, bagCap, L["Bags"]))
    end

    local function SyncSubTabs(altCount)
        local isNarrow = IsNarrowLayout()
        local activeSub = panel._subTab or "overview"
        if not isNarrow and activeSub == "alts" then
            activeSub = "overview"
            panel._subTab = "overview"
        end

        Theme:SetButtonText(btnNarrowAlts, ("%s (%d)"):format(L["Alts"], altCount or 0))
        Theme:SetButtonActive(btnNarrowAlts, activeSub == "alts", "tab")
        Theme:SetButtonActive(btnNarrowOverview, activeSub == "overview", "tab")
        Theme:SetButtonActive(btnNarrowItems, activeSub == "items", "tab")
        Theme:SetButtonActive(btnNarrowGear, activeSub == "gear", "tab")

        Theme:SetButtonActive(btnWideOverview, activeSub == "overview", "tab")
        Theme:SetButtonActive(btnWideItems, activeSub == "items", "tab")
        Theme:SetButtonActive(btnWideGear, activeSub == "gear", "tab")

        rosterPane:SetShown((not isNarrow) or (activeSub == "alts"))
        inspectorPane:SetShown((not isNarrow) or (activeSub ~= "alts"))
        overviewFrame:SetShown(activeSub == "overview")
        itemsFrame:SetShown(activeSub == "items")
        gearFrame:SetShown(activeSub == "gear")
    end

    local function RelayoutItemsToolbar()
        local tw = math.floor((itemsToolbar:GetWidth() or 320) + 0.5)
        if tw < 120 then return end
        local btnsNeed = math.ceil(filterBtn:GetWidth() or 88) + 4 + math.ceil(scopeBtn:GetWidth() or 92) + 4 + math.ceil(viewModeBtn:GetWidth() or 64)
        local singleRow = tw >= (144 + btnsNeed + 92)

        bagSearch:ClearAllPoints()
        bagSearch:SetPoint("TOPLEFT", itemsToolbar, "TOPLEFT", 0, 0)
        local buttons = { filterBtn, scopeBtn, viewModeBtn }
        if singleRow then
            local searchW = math.max(136, math.min(180, tw - btnsNeed - 98))
            bagSearch:SetWidth(searchW)
            itemsToolbar:SetHeight(26)
            LayoutButtonFlow(itemsToolbar, buttons, searchW + 6, -1, btnsNeed + 16, 24, 4)
            if itemsHelpBtn then
                itemsHelpBtn:ClearAllPoints()
                itemsHelpBtn:SetPoint("RIGHT", itemsToolbar, "RIGHT", -2, 0)
            end
            infoLbl:ClearAllPoints()
            infoLbl:SetPoint("LEFT", viewModeBtn, "RIGHT", 6, 0)
            infoLbl:SetPoint("RIGHT", itemsHelpBtn or itemsToolbar, itemsHelpBtn and "LEFT" or "RIGHT", -6, 0)
        else
            local searchW = math.max(108, math.min(240, math.floor(tw * 0.54)))
            bagSearch:SetWidth(searchW)
            local rows = LayoutButtonFlow(itemsToolbar, buttons, 0, -26, tw - 4, 24, 4)
            itemsToolbar:SetHeight(26 + rows * 24 + 2)
            if itemsHelpBtn then
                itemsHelpBtn:ClearAllPoints()
                itemsHelpBtn:SetPoint("TOPRIGHT", itemsToolbar, "TOPRIGHT", -2, -2)
            end
            infoLbl:ClearAllPoints()
            infoLbl:SetPoint("LEFT", bagSearch, "RIGHT", 6, 0)
            infoLbl:SetPoint("RIGHT", itemsHelpBtn or itemsToolbar, itemsHelpBtn and "LEFT" or "RIGHT", -6, 0)
        end
    end

    local function RelayoutAltsPanel()
        local isEmbeddedChar = (CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown())
            and ((not ns.UI or not ns.UI.IsEmbeddedFor) or ns.UI:IsEmbeddedFor(CharacterFrame))
        local isNarrow, w = IsNarrowLayout()
        local p = Theme:GetPalette()

        local embRightClear = 34
        if isEmbeddedChar then
            local emb = _G.SocialCentralAltsEmbeddedFrame
            if emb then
                local rClear = 8
                if emb.settingsBtn and emb.settingsBtn:IsShown() then
                    rClear = rClear + (emb.settingsBtn:GetWidth() or 90) + 6
                elseif emb.settingsCompactBtn and emb.settingsCompactBtn:IsShown() then
                    rClear = rClear + (emb.settingsCompactBtn:GetWidth() or 22) + 6
                end
                if emb.updateBtn and emb.updateBtn:IsShown() then
                    rClear = rClear + (emb.updateBtn:GetWidth() or 24) + 6
                end
                embRightClear = math.max(34, math.ceil(rClear))
            elseif w >= 540 then
                embRightClear = 114
            end
        end

        local layoutSig = (isEmbeddedChar and "E:" or "M:") .. (isNarrow and "N:" or "W:") .. w .. ":" .. embRightClear .. ":" .. tostring(panel._subTab) .. ":" .. tostring(p and p.key or "dark")
        if panel._lastLayoutSig == layoutSig then
            return
        end
        panel._lastLayoutSig = layoutSig

        topBar:SetShown(isNarrow or isEmbeddedChar)
        narrowTabBar:SetShown(isNarrow)
        wideTabBar:SetShown(not isNarrow)

        if isNarrow or isEmbeddedChar then
            local portraitPad = (isEmbeddedChar or w < 520) and 54 or 4
            local rightPad = isEmbeddedChar and -embRightClear or -4
            local topY = isEmbeddedChar and -3 or 0
            topBar:ClearAllPoints()
            topBar:SetPoint("TOPLEFT", panel, "TOPLEFT", portraitPad, topY)
            topBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", rightPad, topY)
            local topAvail = math.max(120, w - portraitPad + rightPad)
            local charW = math.max(104, math.min(240, topAvail - 28))
            charBtn:SetWidth(charW)
        end

        if isNarrow then
            narrowTabBar:ClearAllPoints()
            narrowTabBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -31)
            narrowTabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -31)
            local narrowBtns = { btnNarrowAlts, btnNarrowOverview, btnNarrowItems, btnNarrowGear }
            local availW = math.max(240, w - 4 - 12)
            local widths = {}
            local totalNeed = 0
            for idx, b in ipairs(narrowBtns) do
                Theme:AutoFitButton(b, 50, 12, math.floor(availW * 0.42))
                local bw = math.ceil(b:GetWidth() or 58)
                widths[idx] = bw
                totalNeed = totalNeed + bw
            end
            local delta = availW - totalNeed
            if delta >= 0 then
                local extraEach = math.floor(delta / #narrowBtns)
                for idx = 1, #narrowBtns do
                    widths[idx] = widths[idx] + extraEach
                end
            elseif totalNeed > 0 then
                local scale = availW / totalNeed
                for idx = 1, #narrowBtns do
                    widths[idx] = math.max(44, math.floor(widths[idx] * scale))
                end
            end
            for idx, b in ipairs(narrowBtns) do
                b:SetWidth(widths[idx])
                b:ClearAllPoints()
                if idx == 1 then
                    b:SetPoint("LEFT", narrowTabBar, "LEFT", 0, 0)
                else
                    b:SetPoint("LEFT", narrowBtns[idx - 1], "RIGHT", 4, 0)
                end
            end

            rosterPane:ClearAllPoints()
            rosterPane:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -59)
            rosterPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)

            inspectorPane:ClearAllPoints()
            inspectorPane:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -59)
            inspectorPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)

            subArea:ClearAllPoints()
            subArea:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 2, -4)
            subArea:SetPoint("BOTTOMRIGHT", inspectorPane, "BOTTOMRIGHT", -4, 4)
        else
            local topPad = isEmbeddedChar and -32 or -2
            local rosterW = math.max(240, math.min(278, math.floor(w * 0.34)))
            rosterPane:ClearAllPoints()
            rosterPane:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, topPad)
            rosterPane:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 2, 2)
            rosterPane:SetWidth(rosterW)

            inspectorPane:ClearAllPoints()
            inspectorPane:SetPoint("TOPLEFT", rosterPane, "TOPRIGHT", 6, 0)
            inspectorPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)

            subArea:ClearAllPoints()
            subArea:SetPoint("TOPLEFT", wideTabBar, "BOTTOMLEFT", 0, -4)
            subArea:SetPoint("BOTTOMRIGHT", inspectorPane, "BOTTOMRIGHT", -4, 4)
        end

        if p and p.key == "blizzard" then
            rosterHdrBg:SetVertexColor(0.18, 0.14, 0.09, 1.0)
            charHdrBg:SetVertexColor(0.18, 0.14, 0.09, 1.0)
            goldBarBg:SetVertexColor(0.20, 0.15, 0.07, 1.0)
        elseif p and p.key == "native" then
            rosterHdrBg:SetVertexColor(0.13, 0.11, 0.09, 1.0)
            charHdrBg:SetVertexColor(0.13, 0.11, 0.09, 1.0)
            goldBarBg:SetVertexColor(0.15, 0.12, 0.06, 1.0)
        else
            rosterHdrBg:SetVertexColor(0.12, 0.13, 0.16, 1.0)
            charHdrBg:SetVertexColor(0.12, 0.13, 0.16, 1.0)
            goldBarBg:SetVertexColor(0.14, 0.12, 0.07, 1.0)
        end

        Theme:ApplyBackdrop(rosterPane, "inset", p)
        Theme:ApplyBackdrop(inspectorPane, "inset", p)
        Theme:ApplyBackdrop(itemsCard, "inset", p)

        local showArmoryBtn = w >= 410
        btnArmory:SetShown(showArmoryBtn)
        local titleRightAnchor = showArmoryBtn and btnArmory or btnActions
        charTitleLbl:ClearAllPoints()
        charTitleLbl:SetPoint("TOPLEFT", charIcon, "TOPRIGHT", 8, -1)
        charTitleLbl:SetPoint("RIGHT", titleRightAnchor, "LEFT", -8, 0)
        charSubLbl:ClearAllPoints()
        charSubLbl:SetPoint("BOTTOMLEFT", charIcon, "BOTTOMRIGHT", 8, 1)
        charSubLbl:SetPoint("RIGHT", titleRightAnchor, "LEFT", -8, 0)

        RelayoutItemsToolbar()
        UpdateOverviewScrollBounds()
    end

    -- Button Scripts
    local function SwitchSubTab(tabId)
        panel._narrowTabPicked = true
        panel._subTab = tabId
        panel:Refresh(true)
    end
    btnNarrowAlts:SetScript("OnClick", function() SwitchSubTab("alts") end)
    btnNarrowOverview:SetScript("OnClick", function() SwitchSubTab("overview") end)
    btnNarrowItems:SetScript("OnClick", function() SwitchSubTab("items") end)
    btnNarrowGear:SetScript("OnClick", function() SwitchSubTab("gear") end)
    btnWideOverview:SetScript("OnClick", function() SwitchSubTab("overview") end)
    btnWideItems:SetScript("OnClick", function() SwitchSubTab("items") end)
    btnWideGear:SetScript("OnClick", function() SwitchSubTab("gear") end)

    rosterSortBtn:SetScript("OnClick", function(selfBtn)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                root:CreateTitle(L["Sort Alts"])
                for _, m in ipairs(SORT_MODES) do
                    local id = m.id
                    root:CreateRadio(m.label, function()
                        return panel._sortBy == id
                    end, function()
                        panel._sortBy = id
                        panel:Refresh(true)
                    end)
                end
            end)
        else
            local idx = 1
            for i, m in ipairs(SORT_MODES) do
                if m.id == panel._sortBy then idx = (i % #SORT_MODES) + 1; break end
            end
            panel._sortBy = SORT_MODES[idx].id
            panel:Refresh(true)
        end
    end)

    btnArmory:SetScript("OnClick", function()
        local selectedAlt = GetSelectedAlt()
        local url = selectedAlt and ns.Alts and ns.Alts:GetArmoryURL(selectedAlt)
        if url and ns.UI and ns.UI.OpenCopyModal then
            ns.UI:OpenCopyModal(url, L["Web Armory Link"], L["Blizzard's addon sandbox prohibits external internet requests. Copy this link to open your Web Armory in a browser:"])
        end
    end)

    btnActions:SetScript("OnClick", function(selfBtn)
        local selectedAlt = GetSelectedAlt()
        if selectedAlt then
            OpenAltActionMenu(selfBtn, selectedAlt)
        end
    end)

    charBtn:SetScript("OnClick", function(selfBtn)
        local selectedAlt, list = GetSelectedAlt()
        if #list == 0 then return end
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                root:CreateTitle(L["Select Character"])
                for _, rec in ipairs(list) do
                    local hex = Compat.ClassHex(rec.classFile)
                    local mailTag = rec.hasMail and (" |cffffd24d[" .. L["Mailbox"] .. "]|r") or ""
                    local lbl = ("%s%s|r |cffc6ceda(%s)|r · %s%s"):format(
                        hex,
                        rec.fullName or rec.name or rec.key,
                        L["Lv %d"]:format(tonumber(rec.level) or 0),
                        Compat.FormatMoney(rec.money or 0),
                        mailTag
                    )
                    root:CreateRadio(lbl, function()
                        return panel._selectedKey == rec.key
                    end, function()
                        panel._userPickedAlt = true
                        panel._selectedKey = rec.key
                        if panel._subTab == "alts" then
                            panel._narrowTabPicked = true
                            panel._subTab = "overview"
                        end
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
                    if selectedAlt.key ~= CurrentAltKey() then
                        root:CreateButton("|cfff54747" .. L["Remove Alt"] .. "|r", function()
                            OpenAltRemoveModal(selectedAlt, function()
                                panel._userPickedAlt = false
                                panel._selectedKey = CurrentAltKey()
                                panel:Refresh(true)
                            end)
                        end)
                    end
                end
            end)
        else
            local idx = 1
            for i, rec in ipairs(list) do
                if rec.key == panel._selectedKey then idx = (i % #list) + 1; break end
            end
            panel._userPickedAlt = true
            panel._selectedKey = list[idx].key
            panel:Refresh(true)
        end
    end)

    bagSearch:HookScript("OnTextChanged", function()
        panel._searchToken = (panel._searchToken or 0) + 1
        local token = panel._searchToken
        if C_Timer and C_Timer.After then
            C_Timer.After(0.10, function()
                if panel:IsShown() and panel._searchToken == token and panel._subTab == "items" then
                    local altData = GetSelectedAlt()
                    RenderItems(altData, true)
                end
            end)
        elseif panel._subTab == "items" then
            local altData = GetSelectedAlt()
            RenderItems(altData, true)
        end
    end)

    filterBtn:SetScript("OnClick", function(selfBtn)
        local opts = {
            { id = "all", label = L["All"] },
            { id = "equip", label = L["Equipped"] },
            { id = "bags", label = L["Bags"] },
            { id = "bank", label = L["Bank"] },
        }
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
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
                if o.id == panel._bagSource then idx = (i % #opts) + 1; break end
            end
            panel._bagSource = opts[idx].id
            local altData = GetSelectedAlt()
            RenderItems(altData, true)
        end
    end)

    scopeBtn:SetScript("OnClick", function()
        panel._allAltsScope = not panel._allAltsScope
        local altData = GetSelectedAlt()
        RenderItems(altData, true)
    end)

    viewModeBtn:SetScript("OnClick", function()
        panel._viewMode = (panel._viewMode == "list") and "grid" or "list"
        local altData = GetSelectedAlt()
        RenderItems(altData, true)
    end)

    function panel:RefreshTheme(skipRender)
        local buttonsToStyle = {
            { charBtn, "default" },
            { rosterSortBtn, "default" },
            { btnArmory, "default" },
            { btnActions, "default" },
            { filterBtn, "default" },
            { scopeBtn, "default" },
            { viewModeBtn, "default" },
            { btnNarrowAlts, "tab" },
            { btnNarrowOverview, "tab" },
            { btnNarrowItems, "tab" },
            { btnNarrowGear, "tab" },
            { btnWideOverview, "tab" },
            { btnWideItems, "tab" },
            { btnWideGear, "tab" },
        }
        for _, pair in ipairs(buttonsToStyle) do
            Theme:StyleButton(pair[1], pair[2])
        end
        Theme:AutoFitButton(filterBtn, 72, 14, 138)
        Theme:AutoFitButton(scopeBtn, 76, 14, 128)
        Theme:AutoFitButton(viewModeBtn, 56, 14, 88)
        Theme:AutoFitButton(rosterSortBtn, 72, 12, 126)
        rosterSortBtn:SetHeight(20)
        Theme:AutoFitButton(btnArmory, 56, 12, 92)
        Theme:AutoFitButton(btnActions, 64, 12, 108)

        for _, hb in ipairs({ charHelpBtn, rosterHelpBtn, headerHelpBtn, itemsHelpBtn, gearHelpBtn }) do
            if hb and hb.RefreshTheme then hb:RefreshTheme() end
        end
        Theme:ApplyBackdrop(rosterPane, "inset")
        Theme:ApplyBackdrop(inspectorPane, "inset")
        Theme:ApplyBackdrop(itemsCard, "inset")
        for _, sc in ipairs({ rosterScroll, bagGridScroll, bagListScroll, gearScroll }) do
            if sc and sc.RefreshTheme then
                sc:RefreshTheme()
                if not skipRender then sc:Render() end
            end
        end
    end

    local isRefreshing = false

    local function RenderActiveSubView(altData, list, resetScroll)
        local isNarrow = IsNarrowLayout()
        local activeSub = panel._subTab or "overview"
        if not isNarrow and activeSub == "alts" then
            activeSub = "overview"
        end
        if (not isNarrow) or activeSub == "alts" then
            rosterTitleLbl:SetText(("%s (%d)"):format(L["My Alts"], #list))
            Theme:SetButtonText(rosterSortBtn, GetSortLabel(panel._sortBy) .. "  v")
            Theme:AutoFitButton(rosterSortBtn, 72, 12, 126)
            rosterSortBtn:SetHeight(20)
            local totGold = (Store and Store.GetTotalAltsGold and Store:GetTotalAltsGold(true, true)) or 0
            local curFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
            local byFac = (Store and Store.GetTotalAltsGoldByFaction and Store:GetTotalAltsGoldByFaction(true)) or nil
            local dualFac = byFac and (byFac.Alliance or 0) > 0 and (byFac.Horde or 0) > 0
            local facSuffix = (dualFac and curFac == "Alliance" and (" (" .. L["Alliance"] .. ")"))
                or (dualFac and curFac == "Horde" and (" (" .. L["Horde"] .. ")"))
                or ""
            goldVaultLbl:SetText("|cffffd200" .. L["Total Server Gold"] .. facSuffix .. "|r")
            goldVaultVal:SetText(Compat.FormatMoney(totGold))
            rosterScroll:SetData(list, L["No characters recorded yet."], resetScroll)
        end
        if (not isNarrow) or activeSub ~= "alts" then
            RenderCharHeader(altData)
            if activeSub == "overview" then
                RenderOverview(altData, resetScroll)
            elseif activeSub == "items" then
                RenderItems(altData, resetScroll)
            elseif activeSub == "gear" then
                RenderGear(altData, resetScroll)
            end
        end
    end

    function panel:Relayout()
        if not self:IsShown() then return end
        RelayoutAltsPanel()
        local curW = math.floor((self:GetWidth() or 0) + 0.5)
        if not self._lastRenderedW or math.abs(curW - self._lastRenderedW) >= 2 then
            self._lastRenderedW = curW
            local altData, list = GetSelectedAlt()
            SyncSubTabs(#list)
            RenderActiveSubView(altData, list, false)
        end
    end

    function panel:Refresh(resetScroll)
        if isRefreshing then return end
        if not self:IsShown() then
            self._dirty = true
            return
        end
        self._dirty = false
        isRefreshing = true

        local myKey = CurrentAltKey()
        if not panel._userPickedAlt then
            panel._selectedKey = myKey
        end

        local altData, list = GetSelectedAlt()
        local isNarrow = IsNarrowLayout()
        if isNarrow and not panel._narrowTabPicked then
            panel._subTab = (#list >= 2) and "alts" or "overview"
        elseif (not isNarrow) and panel._subTab == "alts" then
            panel._subTab = "overview"
        end

        RelayoutAltsPanel()
        SyncSubTabs(#list)

        if altData then
            Theme:SetButtonText(charBtn, (altData.fullName or altData.name or altData.key) .. "  v")
        else
            Theme:SetButtonText(charBtn, L["Select Character"])
        end

        RenderActiveSubView(altData, list, resetScroll)
        self:RefreshTheme(true)
        SyncSubTabs(#list)
        isRefreshing = false
    end

    panel:SetScript("OnShow", function()
        if ns.Alts and ns.Alts.Snapshot and panel._selectedKey == CurrentAltKey() then
            pcall(ns.Alts.Snapshot, ns.Alts, false)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if panel:IsShown() then
                    if panel._dirty then
                        panel:Refresh(false)
                    else
                        panel:Relayout()
                    end
                end
            end)
        else
            panel:Refresh(false)
        end
    end)

    panel:SetScript("OnHide", function()
        panel._userPickedAlt = false
        panel._narrowTabPicked = false
    end)

    panel:SetScript("OnSizeChanged", function()
        if not panel:IsShown() then return end
        panel._resizeToken = (panel._resizeToken or 0) + 1
        local token = panel._resizeToken
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function()
                if panel:IsShown() and panel._resizeToken == token then
                    panel:Relayout()
                end
            end)
        else
            panel:Relayout()
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
