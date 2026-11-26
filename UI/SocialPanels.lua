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

local function AddHelp(parent, anchorTo, title, whatText, howText, point, relPoint, xOff, yOff, opts)
    if not (Theme and Theme.CreateHelpButton) then return nil end
    local h = Theme:CreateHelpButton(parent, title, whatText, howText, 18, opts)
    h:SetPoint(point or "LEFT", anchorTo, relPoint or "RIGHT", xOff or 6, yOff or 0)
    return h
end

local metaModal, profModal, createRoomModal, roomInviteModal

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
        m:Hide()
        m:SetSize(454, 456)
        m:SetPoint("CENTER")
        Theme:PrepareTopOverlayModal(m, 850)
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
            m.nickIn:ClearFocus()
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

        local nickLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nickLbl:SetJustifyH("LEFT")
        nickLbl:SetWordWrap(false)
        nickLbl:SetText(L["Personal Nickname (shown in lists, Tooltips & Official Chat):"])
        m.nickLbl = nickLbl

        local nickIn = Theme:CreateEditBox(m, { height = 24, maxLetters = 28 })
        m.nickIn = nickIn

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

        local btnAcctIgnore = Theme:CreateButton(m, 124, 24, L["Account Ignore..."], "danger")
        Theme:AutoFitButton(btnAcctIgnore, 112, 16, 172)
        btnAcctIgnore:SetPoint("BOTTOMLEFT", 16, 14)
        m.btnAcctIgnore = btnAcctIgnore

        btnCancel:SetScript("OnClick", function()
            fIn:ClearFocus()
            nickIn:ClearFocus()
            mainIn:ClearFocus()
            noteIn:ClearFocus()
            nativeNoteIn:ClearFocus()
            m:Hide()
        end)
        for _, box in ipairs({ fIn, nickIn, mainIn, noteIn, nativeNoteIn }) do
            box:SetScript("OnEscapePressed", function() m:Hide() end)
        end

        metaModal = m
    end

    local meta = (allowSocialCard and Store and Store:GetSocialMeta(charKey)) or {}
    local curFav = false
    if allowSocialCard and Store and Store.IsSocialFavorite then
        curFav = Store:IsSocialFavorite(charKey)
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
                local chipLabel = (fn == "Dungeons" or fn == "Raid" or fn == "PvP" or fn == "Craft") and (L[fn] or fn) or fn
                cb._folderVal = chipLabel
                Theme:StyleButton(cb, "default")
                Theme:SetButtonText(cb, chipLabel)
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

        metaModal.nickLbl:Show()
        metaModal.nickLbl:ClearAllPoints()
        metaModal.nickLbl:SetPoint("TOPLEFT", 16, y)
        metaModal.nickLbl:SetPoint("TOPRIGHT", -16, y)
        y = y - 16

        metaModal.nickIn:Show()
        metaModal.nickIn:ClearAllPoints()
        metaModal.nickIn:SetPoint("TOPLEFT", 16, y)
        metaModal.nickIn:SetPoint("RIGHT", metaModal, "RIGHT", -16, 0)
        metaModal.nickIn:SetText(meta and meta.nickname or "")
        y = y - 28

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
        metaModal.nickLbl:Hide()
        metaModal.nickIn:Hide()
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
        if metaModal.btnAcctIgnore then
            local isIgn = Store and Store.IsAccountIgnored and Store:IsAccountIgnored(charKey)
            Theme:SetButtonText(metaModal.btnAcctIgnore, isIgn and L["Edit Account Ignore..."] or L["Account Ignore..."])
            Theme:AutoFitButton(metaModal.btnAcctIgnore, 112, 16, 180)
            Theme:StyleButton(metaModal.btnAcctIgnore, "danger")
            metaModal.btnAcctIgnore:Show()
            metaModal.btnAcctIgnore:SetScript("OnClick", function()
                metaModal:Hide()
                SocialPanels:OpenAccountIgnoreModal(displayName or charKey, charKey)
            end)
        end
    else
        metaModal.btnFlagGood:Hide()
        metaModal.btnFlagAvoid:Hide()
        if metaModal.btnAcctIgnore then metaModal.btnAcctIgnore:Hide() end
    end

    metaModal:SetHeight(math.max(190, math.abs(y) + 74))

    metaModal._pendingFav = curFav
    metaModal._pendingFlag = (allowSocialCard and meta and meta.flag) or ""
    metaModal.SyncFlagButtons()

    local function Commit()
        if allowSocialCard and Store and Store.SetSocialMeta then
            Store:SetSocialMeta(charKey, {
                folder = metaModal.folderIn:GetText() or "",
                nickname = metaModal.nickIn:GetText() or "",
                mainName = metaModal.mainIn:GetText() or "",
                note = metaModal.noteIn:GetText() or "",
                flag = metaModal._pendingFlag or "",
                favorite = metaModal._pendingFav == true,
            })
            if Store.TouchFriendPresence then
                Store:TouchFriendPresence(charKey, { favorite = metaModal._pendingFav == true })
            end
            if ns.Chat and ns.Chat.InvalidateOfficialChatCache then
                ns.Chat:InvalidateOfficialChatCache()
            end
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
        metaModal.nickIn:ClearFocus()
        metaModal.mainIn:ClearFocus()
        metaModal.noteIn:ClearFocus()
        metaModal.nativeNoteIn:ClearFocus()
        metaModal:Hide()
    end

    Theme:PrepareTopOverlayModal(metaModal, 850)
    metaModal.btnSave:SetScript("OnClick", Commit)
    metaModal.noteIn:SetScript("OnEnterPressed", Commit)
    metaModal.nativeNoteIn:SetScript("OnEnterPressed", Commit)
    metaModal:Show()
    if metaModal.Raise then metaModal:Raise() end
    if allowSocialCard then
        metaModal.folderIn:SetFocus()
    else
        metaModal.nativeNoteIn:SetFocus()
    end
end

local exportImportModal = nil

function SocialPanels:OpenSocialExportImportModal(focusImport)
    if not exportImportModal then
        local m = CreateFrame("Frame", "SocialCentralExportImportModal", UIParent, "BackdropTemplate")
        m:Hide()
        m:SetSize(486, 366)
        m:SetPoint("CENTER")
        Theme:PrepareTopOverlayModal(m, 860)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        m:EnableMouse(true)
        Theme:MakeMovable(m, { key = "modal_social_export" })
        table.insert(UISpecialFrames, "SocialCentralExportImportModal")

        local solidBg = m:CreateTexture(nil, "BACKGROUND", nil, -8)
        solidBg:SetAllPoints()
        solidBg:SetTexture("Interface\\Buttons\\WHITE8X8")
        solidBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
        m._solidOpaqueBg = solidBg

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -64, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["Export / Import Social Data"])
        m.title = title
        if Theme.DecorateSectionHeader then
            Theme:DecorateSectionHeader(m, title, 390)
        end

        local topCloseBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            if m.editBox then m.editBox:ClearFocus() end
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        m.helpBtn = AddHelp(
            m, topCloseBtn,
            L["Help: Export / Import Social Data"],
            L["Generates a compact backup string containing your Account Ignores, Social Cards (nicknames, folders, notes, Good/Avoid flags), and Watchlist entries (no BattleTags saved)."],
            L["Press Ctrl+C to copy your backup string, or paste a received string and click 'Import & Merge' to merge entries safely without overwriting active timers."],
            "RIGHT", "LEFT", -6, 0
        )

        local desc = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", 16, -42)
        desc:SetPoint("TOPRIGHT", -16, -42)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetText(L["Press Ctrl+C to copy your SocialCentral backup, or paste a string below and click Import & Merge."])
        m.desc = desc

        local boxWrap = CreateFrame("Frame", nil, m, "BackdropTemplate")
        boxWrap:SetPoint("TOPLEFT", 16, -74)
        boxWrap:SetPoint("BOTTOMRIGHT", -16, 70)
        Theme:ApplyBackdrop(boxWrap, "inset")
        m.boxWrap = boxWrap

        local sf = CreateFrame("ScrollFrame", "SocialCentralExportImportScroll", boxWrap, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 6, -6)
        sf:SetPoint("BOTTOMRIGHT", -26, 6)
        if Theme.StyleScrollFrame then Theme:StyleScrollFrame(sf) end
        m.scrollFrame = sf

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
        eb:SetWidth(420)
        eb:SetScript("OnEscapePressed", function()
            eb:ClearFocus()
            m:Hide()
        end)
        sf:SetScrollChild(eb)
        m.editBox = eb

        local statusLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        statusLbl:SetPoint("TOPLEFT", boxWrap, "BOTTOMLEFT", 2, -6)
        statusLbl:SetPoint("TOPRIGHT", boxWrap, "BOTTOMRIGHT", -2, -6)
        statusLbl:SetJustifyH("LEFT")
        statusLbl:SetWordWrap(false)
        m.statusLbl = statusLbl

        local btnClose = Theme:CreateButton(m, 88, 24, L["Close"], "default")
        Theme:AutoFitButton(btnClose, 78, 14, 130)
        btnClose:SetPoint("BOTTOMRIGHT", -16, 12)
        btnClose:SetScript("OnClick", function()
            eb:ClearFocus()
            m:Hide()
        end)
        m.btnClose = btnClose

        local btnImport = Theme:CreateButton(m, 134, 24, L["Import & Merge"], "primary")
        Theme:AutoFitButton(btnImport, 118, 18, 180)
        btnImport:SetPoint("RIGHT", btnClose, "LEFT", -8, 0)
        btnImport:SetScript("OnClick", function()
            if not (Store and Store.ImportSocialDataString) then return end
            local ok, igC, mC, wC = Store:ImportSocialDataString(eb:GetText() or "")
            if ok then
                statusLbl:SetTextColor(0.28, 0.92, 0.50)
                statusLbl:SetText(L["Imported %d ignores, %d notes & %d watchlist entries."]:format(igC, mC, wC))
                if ns.UI and ns.UI.Refresh then ns.UI:Refresh(true) end
            else
                statusLbl:SetTextColor(1.0, 0.35, 0.35)
                statusLbl:SetText(L["Invalid backup string. Ensure it begins with 'SC1'."])
            end
        end)
        m.btnImport = btnImport

        local btnRefreshExp = Theme:CreateButton(m, 130, 24, L["Generate Export"], "default")
        Theme:AutoFitButton(btnRefreshExp, 114, 18, 180)
        btnRefreshExp:SetPoint("BOTTOMLEFT", 16, 12)
        btnRefreshExp:SetScript("OnClick", function()
            if not (Store and Store.ExportSocialDataString) then return end
            local str, igC, mC, wC = Store:ExportSocialDataString()
            eb:SetText(str or "")
            eb:SetFocus()
            eb:HighlightText()
            statusLbl:SetTextColor(0.55, 0.85, 1.0)
            statusLbl:SetText(L["Ready to copy: %d ignores, %d notes, %d watchlist."]:format(igC, mC, wC))
        end)
        m.btnRefreshExp = btnRefreshExp

        exportImportModal = m
    end

    local m = exportImportModal
    Theme:ApplyBackdrop(m, "window")
    Theme:ApplyBackdrop(m.boxWrap, "inset")
    if m.scrollFrame and Theme.StyleScrollFrame then Theme:StyleScrollFrame(m.scrollFrame) end
    Theme:StyleButton(m.topCloseBtn, "default")
    Theme:StyleButton(m.btnClose, "default")
    Theme:StyleButton(m.btnImport, "primary")
    Theme:StyleButton(m.btnRefreshExp, "default")
    if m.helpBtn and m.helpBtn.RefreshTheme then m.helpBtn:RefreshTheme() end
    Theme:PrepareTopOverlayModal(m, 860)

    if focusImport then
        m.editBox:SetText("")
        m.statusLbl:SetTextColor(0.75, 0.82, 0.90)
        m.statusLbl:SetText(L["Paste your SC1 backup text above and click Import & Merge."])
    elseif Store and Store.ExportSocialDataString then
        local str, igC, mC, wC = Store:ExportSocialDataString()
        m.editBox:SetText(str or "")
        m.statusLbl:SetTextColor(0.55, 0.85, 1.0)
        m.statusLbl:SetText(L["Ready to copy: %d ignores, %d notes, %d watchlist."]:format(igC, mC, wC))
    end
    m:Show()
    if m.Raise then m:Raise() end
    m.editBox:SetFocus()
    if not focusImport then
        m.editBox:HighlightText()
    end
end

function SocialPanels:OpenProfessionModal()
    local profs = ns.Clan and ns.Clan.PROFESSIONS or {}

    if not profModal then
        local m = CreateFrame("Frame", "SocialCentralProfModal", UIParent, "BackdropTemplate")
        m:SetSize(504, 372)
        m:SetPoint("CENTER")
        Theme:PrepareTopOverlayModal(m, 850)
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

        m.profModalHelp = AddHelp(
            m,
            topCloseBtn,
            L["Help: Profession Auto-Detect & Guild Note"],
            L["Detects your character's current professions and skill ranks automatically, and lets you publish a compact tag to your Guild Public Note."],
            L["Click 'Auto-Detect' to pull your live professions, or click 'Publish Note' so all guildmates see your crafts even without SocialCentral."],
            "RIGHT",
            "LEFT",
            -6,
            0,
            { target = m }
        )
        if m.profModalHelp then
            title:ClearAllPoints()
            title:SetPoint("TOPLEFT", 16, -14)
            title:SetPoint("TOPRIGHT", m.profModalHelp, "TOPLEFT", -6, -4)
        end

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

        local profIcons = {
            ALCHEMY = "Interface\\Icons\\Trade_Alchemy",
            BLACKSMITHING = "Interface\\Icons\\Trade_BlackSmithing",
            ENCHANTING = "Interface\\Icons\\Trade_Engraving",
            ENGINEERING = "Interface\\Icons\\Trade_Engineering",
            HERBALISM = "Interface\\Icons\\Trade_Herbalism",
            INSCRIPTION = "Interface\\Icons\\INV_Inscription_Tradeskill01",
            JEWELCRAFTING = "Interface\\Icons\\INV_Misc_Gem_01",
            LEATHERWORKING = "Interface\\Icons\\Trade_LeatherWorking",
            MINING = "Interface\\Icons\\Trade_Mining",
            SKINNING = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
            TAILORING = "Interface\\Icons\\Trade_Tailoring",
        }
        m._profBtns = {}
        local cols = 3
        for idx, item in ipairs(profs) do
            local pid = type(item) == "table" and item.id or item
            local r = math.floor((idx - 1) / cols)
            local c = (idx - 1) % cols
            local b = Theme:CreateButton(m, 152, 22, PROF_LABELS[pid] or pid, "default")
            local pTex = profIcons[pid]
            if pTex and b.label then
                local pIco = (b._textLayer or b):CreateTexture(nil, "OVERLAY", nil, 2)
                pIco:SetSize(15, 15)
                pIco:SetPoint("LEFT", b, "LEFT", 6, 0)
                pIco:SetTexture(pTex)
                pIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.label:ClearAllPoints()
                b.label:SetPoint("LEFT", pIco, "RIGHT", 5, 0)
                b.label:SetPoint("RIGHT", b, "RIGHT", -5, 0)
                b.label:SetJustifyH("LEFT")
                b.label:SetWordWrap(false)
            end
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
    Theme:PrepareTopOverlayModal(profModal, 850)
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
    if profModal.Raise then profModal:Raise() end
end

local function OpenCreateRoomModal()
    if not createRoomModal then
        local m = CreateFrame("Frame", "SocialCentralCreateRoomModal", UIParent, "BackdropTemplate")
        m:SetSize(420, 154)
        m:SetPoint("CENTER")
        Theme:PrepareTopOverlayModal(m, 850)
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

        m.helpBtn = AddHelp(
            m,
            topCloseBtn,
            L["Help: Create Private Chat Room"],
            L["Creates an addon-synced private multi-person room in Conversations so you can chat with specific dungeon partners or friends."],
            L["Type a room title (e.g. Raid Officers or Dungeon Crew) and click Create, then invite friends inside the thread."],
            "RIGHT",
            "LEFT",
            -4,
            0,
            { target = m }
        )
        title:SetPoint("TOPRIGHT", m.helpBtn or topCloseBtn, "LEFT", -6, 0)

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

    Theme:PrepareTopOverlayModal(createRoomModal, 850)
    Theme:ApplyBackdrop(createRoomModal, "window")
    Theme:StyleButton(createRoomModal.topCloseBtn, "default")
    if createRoomModal.helpBtn then Theme:StyleButton(createRoomModal.helpBtn, "ghost") end
    Theme:StyleButton(createRoomModal.btnSave, "primary")
    Theme:StyleButton(createRoomModal.btnCancel, "default")
    createRoomModal.input:SetText("")
    createRoomModal:Show()
    if createRoomModal.Raise then createRoomModal:Raise() end
    createRoomModal.input:SetFocus()
end

local function OpenRoomInviteModal(roomId)
    if not roomId then return end
    if not roomInviteModal then
        local m = CreateFrame("Frame", "SocialCentralRoomInvModal", UIParent, "BackdropTemplate")
        m:SetSize(442, 310)
        m:SetPoint("CENTER")
        Theme:PrepareTopOverlayModal(m, 850)
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

        m.helpBtn = AddHelp(
            m,
            topCloseBtn,
            L["Help: Invite to Private Room"],
            L["Invites online SocialCentral friends into this private room so everyone receives messages in one shared thread."],
            L["Click any online friend from the list below or type a Character-Realm name and click Invite."],
            "RIGHT",
            "LEFT",
            -4,
            0,
            { target = m }
        )
        title:SetPoint("TOPRIGHT", m.helpBtn or topCloseBtn, "LEFT", -6, 0)

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
            local hl = r:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.94, 0.78, 0.06)
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
    Theme:PrepareTopOverlayModal(roomInviteModal, 850)
    Theme:ApplyBackdrop(roomInviteModal, "window")
    Theme:StyleButton(roomInviteModal.topCloseBtn, "default")
    if roomInviteModal.helpBtn then Theme:StyleButton(roomInviteModal.helpBtn, "ghost") end
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
    if roomInviteModal.Raise then roomInviteModal:Raise() end
end

--------------------------------------------------------------------------------
-- Shared Responsive Flow Helper
--------------------------------------------------------------------------------
local function LayoutButtonFlow(container, buttons, startX, startY, maxRowW, rowStep, gap)
    local x = 0
    local rows = 1
    local gapPx = gap or 4
    local stepY = rowStep or 24
    local limitW = math.floor(math.max(120, maxRowW or 360) + 0.5)
    local baseX = math.floor((startX or 0) + 0.5)
    local baseY = math.floor((startY or 0) + 0.5)
    for _, btn in ipairs(buttons) do
        if btn and btn:IsShown() then
            local bw = math.floor((btn._scAutoFitW or btn:GetWidth() or 60) + 0.5)
            if x > 0 and (x + bw) > limitW then
                x = 0
                rows = rows + 1
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", container, "TOPLEFT", baseX + x, baseY - (rows - 1) * stepY)
            x = x + bw + gapPx
        end
    end
    return rows
end

--------------------------------------------------------------------------------
-- Group & Recent Companions Tab Panel
--------------------------------------------------------------------------------
local GROUP_CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local function GetLocalizedClassShort(cf)
    local loc = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cf]) or cf or "?"
    return loc
end

local function ResolveRecentCompanionPresence(item)
    if type(item) ~= "table" then
        return false, false, "unknown"
    end
    if item.inCurrentGroup == true then
        return true, false, "online"
    end
    local lk = item.lookupKey or (item.displayName and Compat.ParseCharacterFields and Compat.ParseCharacterFields(item.displayName))
    if lk and ns.Store and ns.Store.socialByLookup and ns.Store.socialByLookup[lk] then
        return true, false, "online"
    end
    local wlEntry = lk and ns.Watchlist and ns.Watchlist.GetEntry and ns.Watchlist:GetEntry(lk) or nil
    if wlEntry then
        if wlEntry.status == "online" then
            return true, false, "online"
        elseif wlEntry.status == "offline" then
            return false, true, "offline"
        end
    end
    local dirRow = lk and ns.Store and ns.Store.socialDirectoryByLookup and ns.Store.socialDirectoryByLookup[lk] or nil
    if dirRow then
        if dirRow.online == true then
            return true, false, "online"
        end
        return false, true, "offline"
    end
    return false, false, "unknown"
end

local function OpenGroupMemberMenu(anchor, panel, item)
    if not (anchor and item and MenuUtil and MenuUtil.CreateContextMenu) then return end
    local rKey = item.lookupKey or item.displayName
    local bInfo = (rKey and ns.Social and ns.Social.GetBNetLinkInfo) and ns.Social:GetBNetLinkInfo(rKey) or nil
    local isCrossFac = (item.sameFaction == false) or (bInfo and bInfo.sameFaction == false)
    local bnetName = item.bnetName or (bInfo and bInfo.bnetName)
    local bnetId = item.bnetAccountID or (bInfo and bInfo.bnetAccountID)
    MenuUtil.CreateContextMenu(anchor, function(_, root)
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
        local chatModOn = (not Compat.IsOfficialChatMode or not Compat.IsOfficialChatMode())
            and ((not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("chat"))
        local scConfirmed = chatModOn and (not item.isMe) and ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(rKey, bnetId)
        if scConfirmed then
            root:CreateButton(L["Whisper in SocialCentral"], function()
                if ns.Chat and ns.Chat.OpenPreferredConversation then
                    ns.Chat:OpenPreferredConversation({
                        targetName = rKey,
                        lookupKey = rKey,
                        bnetAccountID = bnetId,
                        bnetName = bnetName,
                        classFile = item.classFile,
                        isCrossFaction = isCrossFac,
                        online = item.online,
                        autoProbe = true,
                        scConfirmed = true,
                    })
                elseif ns.Chat and ns.Chat.OpenDirectConversation then
                    ns.Chat:OpenDirectConversation({
                        targetName = rKey,
                        classFile = item.classFile,
                        autoProbe = true,
                    })
                    if ns.UI and ns.UI.ShowHub then
                        ns.UI:ShowHub("chat")
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
        elseif not isCrossFac and not item.isMe then
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
            local isWatched = rKey and ns.Watchlist and ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(rKey)
            if isWatched then
                root:CreateButton(L["Check"], function()
                    if ns.Watchlist and ns.Watchlist.CheckEntry then
                        ns.Watchlist:CheckEntry(rKey)
                    end
                end)
                root:CreateButton(L["Remove from Watchlist"], function()
                    if ns.UI and ns.UI.OpenConfirmModal then
                        ns.UI:OpenConfirmModal({
                            title = L["Remove from Watchlist"],
                            message = L["Are you sure you want to remove %s from your Watchlist?"]:format(item.displayName or rKey or "?"),
                            confirmText = L["Remove"],
                            onConfirm = function()
                                if ns.Watchlist then ns.Watchlist:Remove(rKey) end
                            end,
                        })
                    elseif ns.Watchlist then
                        ns.Watchlist:Remove(rKey)
                    end
                end)
            else
                root:CreateButton(L["Add to Watchlist"], function()
                    if ns.Watchlist then ns.Watchlist:Add(item.displayName or item.lookupKey) end
                end)
            end
            root:CreateButton(L["Edit Social Card"], function()
                SocialPanels:OpenSocialMetaModal(item.displayName, item.lookupKey or item.displayName)
            end)
            if Store and Store.IsSocialFavorite and Store.ToggleSocialFavorite and (item.lookupKey or item.displayName) then
                local favKey = item.lookupKey or item.displayName
                local isFav = Store:IsSocialFavorite(favKey)
                local starMark = Compat.FavoriteStarMarkup and Compat.FavoriteStarMarkup(12) or ""
                root:CreateButton(isFav and (starMark .. L["Unfavorite"]) or L["Favorite"], function()
                    Store:ToggleSocialFavorite(favKey)
                    panel:Refresh(false)
                end)
            end
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

local function AppendGroupSynergyTooltip(tt, comp, instStat)
    if not tt then return end
    tt:AddLine(L["Class & Buff Synergy"], 1.0, 0.82, 0.0)
    if not comp or not comp.counts or (comp.counts.total or 0) == 0 then
        local rec = (ns.Clan and ns.Clan.GetRecommendedRolesForCharacter) and ns.Clan:GetRecommendedRolesForCharacter() or nil
        if rec then
            tt:AddDoubleLine(rec.whoDesc or L["Player"], rec.rolesLabel or L["DPS"], 0.78, 0.84, 0.92, 0.35, 0.92, 0.55)
        end
        if ns.Group and ns.Group.AppendInstanceHistoryTooltip then
            ns.Group:AppendInstanceHistoryTooltip(tt)
        end
        return
    end
    local c = comp.counts
    tt:AddDoubleLine(L["Members"], string.format("%d  (%d %s · T:%d H:%d D:%d)", c.total, c.online or 0, L["Online"], c.TANK or 0, c.HEALER or 0, c.DAMAGER or 0), 0.78, 0.84, 0.92, 0.92, 0.96, 1.0)
    if (c.dead or 0) > 0 then
        tt:AddDoubleLine(L["Dead"], tostring(c.dead), 0.78, 0.84, 0.92, 1.0, 0.35, 0.35)
    end
    local u = comp.utilities or {}
    tt:AddLine(" ")
    tt:AddLine(L["Utility"], 0.35, 0.78, 1.0)
    local resVal = (u.resurrection or 0) > 0 and ("|cff3fb950" .. tostring(u.resurrection) .. "|r") or ("|cffff55550|r")
    tt:AddDoubleLine(L["Resurrection"], resVal, 0.82, 0.86, 0.92, 1, 1, 1)
    local dispParts = {
        L["Magic"] .. ": " .. ((u.dispelMagic or 0) > 0 and "|cff3fb950OK|r" or "|cff8b949e-|r"),
        L["Curse"] .. ": " .. ((u.dispelCurse or 0) > 0 and "|cff3fb950OK|r" or "|cff8b949e-|r"),
        L["Poison"] .. ": " .. ((u.dispelPoison or 0) > 0 and "|cff3fb950OK|r" or "|cff8b949e-|r"),
        L["Disease"] .. ": " .. ((u.dispelDisease or 0) > 0 and "|cff3fb950OK|r" or "|cff8b949e-|r"),
    }
    tt:AddLine(L["Dispels"] .. ": " .. table.concat(dispParts, "  ·  "), 0.88, 0.92, 0.96, true)

    local myFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    local buffList = {
        { label = L["Fortitude"], ok = (u.fortitude or 0) > 0 },
        { label = L["Intellect"], ok = (u.intellect or 0) > 0 },
        { label = L["MotW"], ok = (u.mark or 0) > 0 },
        { label = L["Battle Shout"], ok = (u.shout or 0) > 0 },
        { label = L["HS / Summon"], ok = (u.warlock or 0) > 0 },
    }
    if myFac ~= "Horde" then
        buffList[#buffList + 1] = { label = L["Blessings"], ok = (u.blessings or 0) > 0 }
    end
    if myFac ~= "Alliance" then
        buffList[#buffList + 1] = { label = L["Totems"], ok = (u.totems or 0) > 0 }
    end
    local bParts = {}
    for _, bf in ipairs(buffList) do
        bParts[#bParts + 1] = (bf.ok and "|cff3fb950" or "|cff6e7681") .. bf.label .. "|r"
    end
    tt:AddLine(table.concat(bParts, "  ·  "), 0.9, 0.9, 0.9, true)

    if comp.missingClasses and #comp.missingClasses > 0 then
        local mNames = {}
        for _, cf in ipairs(comp.missingClasses) do
            mNames[#mNames + 1] = GetLocalizedClassShort(cf)
        end
        tt:AddLine(L["Missing"] .. ": " .. table.concat(mNames, ", "), 0.72, 0.76, 0.82, true)
    else
        tt:AddLine(L["All classes covered"], 0.35, 0.92, 0.55)
    end
    if ns.Group and ns.Group.AppendInstanceHistoryTooltip then
        ns.Group:AppendInstanceHistoryTooltip(tt)
    end
end

local function CreateGroupCompCard(panel, topCard)
    local card = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    card:SetPoint("TOPLEFT", topCard, "BOTTOMLEFT", 0, -6)
    card:SetPoint("TOPRIGHT", topCard, "BOTTOMRIGHT", 0, -6)
    card:SetHeight(48)
    card:EnableMouse(true)

    local line1 = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line1:SetPoint("TOPLEFT", 10, -7)
    line1:SetPoint("TOPRIGHT", -10, -7)
    line1:SetJustifyH("LEFT")
    line1:SetWordWrap(false)
    card.line1 = line1

    local line2 = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line2:SetPoint("BOTTOMLEFT", 10, 7)
    line2:SetPoint("BOTTOMRIGHT", -10, 7)
    line2:SetJustifyH("LEFT")
    line2:SetWordWrap(false)
    card.line2 = line2

    card:SetScript("OnEnter", function(selfCard)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfCard, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        local comp = ns.Group and ns.Group.GetCompositionAnalysis and ns.Group:GetCompositionAnalysis() or nil
        local instStat = ns.Group and ns.Group.GetHourlyInstanceStatus and ns.Group:GetHourlyInstanceStatus() or nil
        AppendGroupSynergyTooltip(GameTooltip, comp, instStat)
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    panel.compCard = card
    return card
end

local function UpdateGroupCompCard(panel, comp, instStat)
    local card = panel.compCard
    if not card then return end
    local showComp = (panel._view == "current")
    card:SetShown(showComp)
    if not showComp then return end

    local pal = Theme:GetPalette()
    Theme:ApplyBackdrop(card, "surface", pal)

    if comp and comp.counts and (comp.counts.total or 0) > 0 then
        local c = comp.counts
        local tIco = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:13:13:0:0:64:64:0:19:22:41|t "
        local hIco = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:13:13:0:0:64:64:20:39:1:20|t "
        local dIco = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:13:13:0:0:64:64:20:39:22:41|t "
        local p1 = {
            tIco .. "|cff58a6ff" .. tostring(c.TANK or 0) .. "|r",
            hIco .. "|cff3fb950" .. tostring(c.HEALER or 0) .. "|r",
            dIco .. "|cffff6b6b" .. tostring(c.DAMAGER or 0) .. "|r",
        }
        if (c.NONE or 0) > 0 then
            p1[#p1 + 1] = "|cff9da7b5?:" .. tostring(c.NONE) .. "|r"
        end
        p1[#p1 + 1] = "|cff3fb950" .. tostring(c.online or 0) .. "/" .. tostring(c.total or 0) .. " " .. L["Online"] .. "|r"
        if (c.dead or 0) > 0 then
            p1[#p1 + 1] = "|cffff4d4d" .. L["Dead"] .. ": " .. tostring(c.dead) .. "|r"
        end
        if (comp.scUsers or 0) > 0 then
            p1[#p1 + 1] = "|cff3fb950[SC:" .. tostring(comp.scUsers) .. "]|r"
        end
        if (comp.avoidCount or 0) > 0 then
            p1[#p1 + 1] = "|cffff4d4d[!] " .. L["Alert: %d Avoid-flagged player(s) in group!"]:format(comp.avoidCount) .. "|r"
        elseif comp.missingRolesText and comp.missingRolesText ~= "" then
            p1[#p1 + 1] = "|cffffd24d" .. L["Need"] .. ": " .. comp.missingRolesText .. "|r"
        elseif (not comp.inRaid) and comp.utilities and (comp.utilities.resurrection or 0) == 0 then
            p1[#p1 + 1] = "|cffff9b3d" .. L["No resurrection class in group"] .. "|r"
        end
        card.line1:SetText(table.concat(p1, "  ·  "))

        local clsParts = {}
        for _, cf in ipairs(GROUP_CLASS_ORDER) do
            local n = comp.classCounts and comp.classCounts[cf] or 0
            if n > 0 then
                local hex = Compat.ClassHex and Compat.ClassHex(cf) or "|cffffffff"
                clsParts[#clsParts + 1] = hex .. GetLocalizedClassShort(cf) .. ":" .. tostring(n) .. "|r"
            end
        end
        local u = comp.utilities or {}
        local dispCount = ((u.dispelMagic or 0) > 0 and 1 or 0) + ((u.dispelCurse or 0) > 0 and 1 or 0) + ((u.dispelPoison or 0) > 0 and 1 or 0) + ((u.dispelDisease or 0) > 0 and 1 or 0)
        local synSuffix = "  |  |cff8ab4f8" .. L["Dispels"] .. " " .. tostring(dispCount) .. "/4|r"
        if comp.utilities and (comp.utilities.resurrection or 0) > 0 then
            synSuffix = synSuffix .. "  ·  |cff3fb950" .. L["Resurrection"] .. ":" .. tostring(comp.utilities.resurrection) .. "|r"
        end
        card.line2:SetText((#clsParts > 0 and table.concat(clsParts, " ") or L["Class & Buff Synergy"]) .. synSuffix)
    else
        local rec = (ns.Clan and ns.Clan.GetRecommendedRolesForCharacter) and ns.Clan:GetRecommendedRolesForCharacter() or nil
        local usedH = instStat and instStat.used or 0
        local maxH = instStat and instStat.max or 5
        local instCol = (usedH >= maxH) and "|cffff5555" or ((usedH == maxH - 1) and "|cffffb833" or "|cff3fb950")
        if rec then
            card.line1:SetText("|cffffd24d" .. L["Character Readiness & Suggested Roles"] .. ":|r " .. (rec.whoDesc or "") .. " · |cff3fb950" .. (rec.rolesLabel or L["DPS"]) .. "|r")
        else
            card.line1:SetText("|cffffd24d" .. L["Character Readiness & Suggested Roles"] .. "|r")
        end
        local capLine = instCol .. L["Instances (1h): %d/%d"]:format(usedH, maxH) .. "|r"
        if usedH > 0 and instStat and (instStat.nextSlotSecs or 0) > 0 and ns.Clan and ns.Clan.FormatResetDuration then
            capLine = capLine .. "  ·  |cffffb833" .. L["Next slot frees in %s"]:format(ns.Clan:FormatResetDuration(instStat.nextSlotSecs)) .. "|r"
        else
            capLine = capLine .. "  ·  |cff8b949e" .. L["Available now (max 5 dungeons per hour)"] .. "|r"
        end
        card.line2:SetText(capLine)
    end
end

local function CreateRaidGridFrame(listCard, panel)
    local sf = CreateFrame("ScrollFrame", "SocialCentralRaidGridScroll", listCard, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -24, 6)
    sf:Hide()
    if Theme and Theme.StyleScrollFrame then
        Theme:StyleScrollFrame(sf)
    end

    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(620, 460)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(selfSf, delta)
        local cur = selfSf:GetVerticalScroll() or 0
        local maxS = math.max(0, (child:GetHeight() or 0) - (selfSf:GetHeight() or 0))
        local nextS = math.max(0, math.min(maxS, cur - delta * 28))
        selfSf:SetVerticalScroll(nextS)
    end)

    local boxes = {}
    for g = 1, 8 do
        local box = CreateFrame("Frame", nil, child, "BackdropTemplate")
        box:SetHeight(124)
        local hdr = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hdr:SetPoint("TOPLEFT", 8, -6)
        hdr:SetPoint("TOPRIGHT", -8, -6)
        hdr:SetJustifyH("LEFT")
        hdr:SetWordWrap(false)
        box.hdr = hdr

        local slots = {}
        for s = 1, 5 do
            local btn = CreateFrame("Button", nil, box)
            btn:SetHeight(19)
            btn:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -24 - (s - 1) * 19)
            btn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -6, -24 - (s - 1) * 19)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0.25, 0.14)
            local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lbl:SetPoint("LEFT", 4, 0)
            lbl:SetPoint("RIGHT", -4, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false)
            btn.lbl = lbl
            btn:SetScript("OnClick", function(selfBtn)
                if selfBtn._member then
                    OpenGroupMemberMenu(selfBtn, panel, selfBtn._member)
                end
            end)
            btn:SetScript("OnEnter", function(selfBtn)
                if not (selfBtn._member and GameTooltip) then return end
                local m = selfBtn._member
                GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                local hex = Compat.ClassHex and Compat.ClassHex(m.classFile) or "|cffffffff"
                GameTooltip:AddLine(hex .. (m.displayName or "?") .. "|r" .. (m.level and (" " .. L["Lv %d"]:format(m.level)) or ""))
                if m.zone and m.zone ~= "" then
                    GameTooltip:AddLine(m.zone, 0.78, 0.84, 0.92)
                end
                if m.instanceUsed ~= nil then
                    GameTooltip:AddLine(L["Instances (1h): %d/%d"]:format(m.instanceUsed, m.instanceMax or 5), 0.88, 0.82, 0.48)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
            btn:Hide()
            slots[s] = btn
        end
        box.slots = slots
        boxes[g] = box
    end

    sf.content = child
    sf.boxes = boxes

    local function LayoutGrid()
        local w = math.floor((sf:GetWidth() or listCard:GetWidth() or 640) + 0.5)
        if w <= 40 then w = 640 end
        local activeCount = sf._visibleBoxes or 8
        local sig = w .. ":" .. activeCount
        if sf._scGridSig == sig then
            return
        end
        sf._scGridSig = sig
        if math.abs((child:GetWidth() or 0) - w) >= 1 then
            child:SetWidth(w)
        end
        local cols = (w >= 430) and 2 or 1
        local gap = 6
        local boxW = math.floor((w - (cols - 1) * gap) / cols)
        local rowsNeeded = math.max(1, math.ceil(activeCount / cols))
        for g = 1, 8 do
            local box = boxes[g]
            if g <= activeCount then
                local idx0 = g - 1
                local col = idx0 % cols
                local row = math.floor(idx0 / cols)
                box:ClearAllPoints()
                box:SetPoint("TOPLEFT", child, "TOPLEFT", col * (boxW + gap), -row * (124 + gap))
                if math.abs((box:GetWidth() or 0) - boxW) >= 1 then
                    box:SetWidth(boxW)
                end
            end
        end
        local targetH = rowsNeeded * (124 + gap)
        if math.abs((child:GetHeight() or 0) - targetH) >= 1 then
            child:SetHeight(targetH)
        end
    end
    sf:SetScript("OnSizeChanged", LayoutGrid)
    sf.LayoutGrid = LayoutGrid

    panel.raidGrid = sf
    return sf
end

local function UpdateRaidGridFrame(panel, comp)
    local sf = panel.raidGrid
    if not sf then return end
    local pal = Theme:GetPalette()
    if Theme and Theme.StyleScrollFrame then
        Theme:StyleScrollFrame(sf)
    end
    local visibleBoxes = math.max(2, comp and comp.maxSubgroup or 2)
    sf._visibleBoxes = visibleBoxes
    for g = 1, 8 do
        local box = sf.boxes[g]
        local sg = comp and comp.subgroups and comp.subgroups[g]
        if g <= visibleBoxes and sg then
            box:Show()
            Theme:ApplyBackdrop(box, "surface", pal)
            local sup = sg.hasShaman and " |cff0070de[Sha]|r" or (sg.hasPaladin and " |cfff58cba[Pal]|r" or "")
            local rt = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:12:12:0:0:64:64:0:19:22:41|t" .. tostring(sg.TANK or 0)
            local rh = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:12:12:0:0:64:64:20:39:1:20|t" .. tostring(sg.HEALER or 0)
            local rd = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:12:12:0:0:64:64:20:39:22:41|t" .. tostring(sg.DAMAGER or 0)
            box.hdr:SetText(string.format("|cffffd24d%s|r  |cff9da7b5%s %s %s|r%s", L["Subgroup %d"]:format(g), rt, rh, rd, sup))
            for s = 1, 5 do
                local btn = box.slots[s]
                local m = sg.members and sg.members[s]
                if m then
                    btn._member = m
                    local hex = (m.online ~= false and not m.isDead) and Compat.ClassHex(m.classFile) or "|cff8b949e"
                    local rShort = (m.role == "TANK" and "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:12:12:0:0:64:64:0:19:22:41|t ")
                        or (m.role == "HEALER" and "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:12:12:0:0:64:64:20:39:1:20|t ")
                        or (m.role == "DAMAGER" and "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:12:12:0:0:64:64:20:39:22:41|t " or "|cff8b949e·|r ")
                    local tags = ""
                    if m.isLeader then tags = tags .. " |cffffd24d[L]|r"
                    elseif m.isAssistant then tags = tags .. " |cff58a6ff[A]|r" end
                    if m.raidRole == "MAINTANK" then tags = tags .. " |cff58a6ff[MT]|r"
                    elseif m.raidRole == "MAINASSIST" then tags = tags .. " |cffffb833[MA]|r" end
                    if m.isDead then tags = tags .. " |cffff4d4d[" .. L["Dead"] .. "]|r"
                    elseif m.online == false then tags = tags .. " |cff8b949e[Off]|r" end
                    if m.ready == true then tags = tags .. " |cff3fb950[OK]|r"
                    elseif m.ready == false then tags = tags .. " |cffff4d4d[NO]|r" end
                    btn.lbl:SetText(rShort .. hex .. (m.displayName or "?") .. "|r" .. tags)
                    btn:Show()
                else
                    btn._member = nil
                    btn:Hide()
                end
            end
        else
            box:Hide()
        end
    end
    sf.LayoutGrid()
end

local dungeonLogPromptModal = nil

function SocialPanels:ShowDungeonLogFirstRunPrompt(runRec)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        self._pendingDungeonLogPromptRec = runRec or true
        if not self._dungeonLogCombatFrame then
            local cf = CreateFrame("Frame")
            cf:RegisterEvent("PLAYER_REGEN_ENABLED")
            cf:SetScript("OnEvent", function()
                if not ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) then
                    if SocialPanels._pendingDungeonLogPromptRec then
                        local rec = SocialPanels._pendingDungeonLogPromptRec
                        SocialPanels._pendingDungeonLogPromptRec = nil
                        if C_Timer and C_Timer.After then
                            C_Timer.After(1.8, function()
                                if not ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) then
                                    SocialPanels:ShowDungeonLogFirstRunPrompt(type(rec) == "table" and rec or nil)
                                end
                            end)
                        end
                    end
                end
            end)
            self._dungeonLogCombatFrame = cf
        end
        return
    end
    local p = Theme:GetPalette()
    if not dungeonLogPromptModal then
        local m = CreateFrame("Frame", "SocialCentralDungeonLogPromptModal", UIParent, "BackdropTemplate")
        m:Hide()
        m:SetSize(468, 294)
        m:SetPoint("CENTER")
        m:EnableMouse(true)
        if m.SetClipsChildren then m:SetClipsChildren(false) end
        Theme:MakeMovable(m, { key = "modal_dungeon_log_prompt" })
        if type(UISpecialFrames) == "table" then
            table.insert(UISpecialFrames, "SocialCentralDungeonLogPromptModal")
        end

        local solidBg = m:CreateTexture(nil, "BACKGROUND", nil, -8)
        solidBg:SetAllPoints(m)
        solidBg:SetTexture(WHITE8X8)
        solidBg:SetVertexColor(0.08, 0.075, 0.07, 1.0)
        m._solidOpaqueBg = solidBg

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -64, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["Dungeon & Raid Group Log"])
        m.title = title
        if Theme.DecorateSectionHeader then
            Theme:DecorateSectionHeader(m, title, 390)
        end

        local closeBtn = Theme:CreateButton(m, 22, 20, "X", "default")
        closeBtn:SetPoint("TOPRIGHT", -10, -10)
        closeBtn:SetScript("OnClick", function()
            if ns.SetAccountTutorialShown then
                ns:SetAccountTutorialShown("dungeonLogPromptShown", true)
            end
            m:Hide()
        end)
        m.closeBtn = closeBtn

        m.helpBtn = AddHelp(
            m,
            closeBtn,
            L["Help: Dungeon & Raid Log"],
            L["Passively records started dungeon and raid groups, teammate names, roles, bosses defeated, and total run time from the first enemy pulled until the run ends."],
            L["View anytime in /sc -> Dungeon & Raid Log (or /sc runs). Uses zero combat-log scanning and keeps up to 120 compact runs so PC impact stays negligible."],
            "RIGHT",
            "LEFT",
            -6,
            0
        )

        local summaryCard = CreateFrame("Frame", nil, m, "BackdropTemplate")
        summaryCard:SetPoint("TOPLEFT", 16, -44)
        summaryCard:SetPoint("TOPRIGHT", -16, -44)
        summaryCard:SetHeight(64)
        m.summaryCard = summaryCard

        local runTitle = summaryCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        runTitle:SetPoint("TOPLEFT", 10, -10)
        runTitle:SetPoint("TOPRIGHT", -10, -10)
        runTitle:SetJustifyH("LEFT")
        runTitle:SetWordWrap(false)
        m.runTitle = runTitle

        local runSub = summaryCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        runSub:SetPoint("TOPLEFT", runTitle, "BOTTOMLEFT", 0, -6)
        runSub:SetPoint("TOPRIGHT", -10, -32)
        runSub:SetJustifyH("LEFT")
        runSub:SetWordWrap(true)
        m.runSub = runSub

        local body = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", summaryCard, "BOTTOMLEFT", 0, -12)
        body:SetPoint("TOPRIGHT", summaryCard, "BOTTOMRIGHT", 0, -12)
        body:SetJustifyH("LEFT")
        body:SetWordWrap(true)
        body:SetText(L["Your first dungeon/raid group has been recorded! You can check who you ran with and how long each run took anytime via /sc (Dungeon & Raid Log). Would you like to keep recording future runs?"])
        m.body = body

        local perfNote = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        perfNote:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -10)
        perfNote:SetPoint("TOPRIGHT", body, "BOTTOMRIGHT", 0, -10)
        perfNote:SetJustifyH("LEFT")
        perfNote:SetWordWrap(true)
        perfNote:SetText(L["Ultra-lightweight: only runs when a dungeon/raid actually starts combat, with zero background polling. You can change this anytime in /sc."])
        m.perfNote = perfNote

        local btnKeep = Theme:CreateButton(m, 140, 26, L["Keep Recording"], "primary")
        Theme:AutoFitButton(btnKeep, 124, 18, 176)
        btnKeep:SetPoint("BOTTOMLEFT", 16, 14)
        btnKeep:SetScript("OnClick", function()
            if ns.db and ns.db.settings then
                ns.db.settings.dungeonRunLogEnabled = true
            end
            if ns.SetAccountTutorialShown then
                ns:SetAccountTutorialShown("dungeonLogPromptShown", true)
            end
            m:Hide()
            if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
        end)
        m.btnKeep = btnKeep

        local btnOpen = Theme:CreateButton(m, 130, 26, L["Open Log"], "default")
        Theme:AutoFitButton(btnOpen, 108, 16, 162)
        btnOpen:SetPoint("LEFT", btnKeep, "RIGHT", 8, 0)
        btnOpen:SetScript("OnClick", function()
            if ns.db and ns.db.settings then
                ns.db.settings.dungeonRunLogEnabled = true
            end
            if ns.SetAccountTutorialShown then
                ns:SetAccountTutorialShown("dungeonLogPromptShown", true)
            end
            m:Hide()
            if ns.UI and ns.UI.OpenGroupRunsView then
                ns.UI:OpenGroupRunsView()
            end
        end)
        m.btnOpen = btnOpen

        local btnDisable = Theme:CreateButton(m, 124, 26, L["Disable Recording"], "danger")
        Theme:AutoFitButton(btnDisable, 110, 16, 168)
        btnDisable:SetPoint("BOTTOMRIGHT", -16, 14)
        btnDisable:SetScript("OnClick", function()
            if ns.db and ns.db.settings then
                ns.db.settings.dungeonRunLogEnabled = false
            end
            if ns.SetAccountTutorialShown then
                ns:SetAccountTutorialShown("dungeonLogPromptShown", true)
            end
            m:Hide()
            ns:Print("%s", L["Dungeon & Raid recording disabled. Re-enable anytime in /sc."])
            ns:Emit("GROUP_UPDATED")
            if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
        end)
        m.btnDisable = btnDisable

        m:HookScript("OnHide", function()
            if not m._hidingForCombat and ns.SetAccountTutorialShown then
                ns:SetAccountTutorialShown("dungeonLogPromptShown", true)
            end
        end)
        m:RegisterEvent("PLAYER_REGEN_DISABLED")
        m:RegisterEvent("PLAYER_REGEN_ENABLED")
        m:SetScript("OnEvent", function(selfM, ev)
            if ev == "PLAYER_REGEN_DISABLED" and selfM:IsShown() then
                selfM._suspendedRunRec = selfM._activeRunRec or true
                selfM._hidingForCombat = true
                selfM:Hide()
                selfM._hidingForCombat = false
            elseif ev == "PLAYER_REGEN_ENABLED" and selfM._suspendedRunRec then
                local rec = selfM._suspendedRunRec
                selfM._suspendedRunRec = nil
                if C_Timer and C_Timer.After then
                    C_Timer.After(1.8, function()
                        if not ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) then
                            SocialPanels:ShowDungeonLogFirstRunPrompt(type(rec) == "table" and rec or nil)
                        end
                    end)
                end
            end
        end)

        dungeonLogPromptModal = m
    end

    local m = dungeonLogPromptModal
    m._activeRunRec = runRec
    local wBg = p.windowBg or { 0.08, 0.075, 0.07, 1.0 }
    if m._solidOpaqueBg then
        m._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
    end
    Theme:ApplyBackdrop(m, "window", p)
    Theme:ApplyBackdrop(m.summaryCard, "surface", p)
    local gold = p.textGold or p.accent or { 1.0, 0.82, 0.25 }
    m.title:SetTextColor(gold[1], gold[2], gold[3])
    m.body:SetTextColor(p.text[1], p.text[2], p.text[3])
    m.perfNote:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
    Theme:StyleButton(m.closeBtn, "default")
    Theme:StyleButton(m.btnKeep, "primary")
    Theme:StyleButton(m.btnOpen, "default")
    Theme:StyleButton(m.btnDisable, "danger")
    if m.helpBtn and m.helpBtn.RefreshTheme then m.helpBtn:RefreshTheme() end

    local kindLbl = (runRec and runRec.t == "raid") and L["Raid"] or L["Dungeon"]
    local durTxt = (ns.Group and ns.Group.FormatRunDuration and runRec) and ns.Group:FormatRunDuration(runRec.dur or 0) or "0s"
    local instName = (runRec and runRec.z) or L["Instance"]
    local sz = (runRec and runRec.sz) or 1
    local bk = (runRec and runRec.bk) or 0
    m.runTitle:SetText(string.format("|cff58a6ff[%s]|r  %s  ·  |cffffd24d%s|r", kindLbl, instName, durTxt))
    local endLbl = (ns.Group and ns.Group.GetRunEndReasonLabel and runRec) and ns.Group:GetRunEndReasonLabel(runRec.er) or L["Completed"]
    local bossPart = bk > 0 and ("  ·  " .. L["%d boss(es)"]:format(bk)) or ""
    local dmgPart = ""
    if runRec and runRec.dm and (runRec.dm.dmg or 0) > 0 and ns.Group and ns.Group.FormatCompactNumber then
        dmgPart = string.format("  ·  %s: %s (%s/s)", L["Dmg"], ns.Group:FormatCompactNumber(runRec.dm.dmg), ns.Group:FormatCompactNumber(runRec.dm.dps or 0))
    end
    m.runSub:SetText(string.format("%s: %d%s%s  ·  %s", L["Members"], sz, bossPart, dmgPart, endLbl))
    m.runSub:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])

    Theme:PrepareTopOverlayModal(m, 860)
    m:Show()
    if Theme.SyncSubtreeLayers then
        Theme:SyncSubtreeLayers(m, 8)
    end
end

local function FormatStatCompact(n)
    if ns.Group and ns.Group.FormatCompactNumber then
        return ns.Group:FormatCompactNumber(n)
    end
    return tostring(math.floor(tonumber(n) or 0))
end

local function FormatGoldCompact(copper)
    if ns.Group and ns.Group.FormatCopperCompact then
        return ns.Group:FormatCopperCompact(copper)
    end
    return tostring(math.floor(tonumber(copper) or 0)) .. "c"
end

local function BuildDungeonRunMeterRows(rec)
    if type(rec) ~= "table" or not rec.dm then return {} end
    local rows = {}
    local dm = rec.dm
    if (dm.myDmg or 0) > 0 or (dm.myHeal or 0) > 0 or (dm.myTkn or 0) > 0 or (dm.myIntr or 0) > 0 or (dm.myDisp or 0) > 0 or (dm.myD or 0) > 0 then
        rows[#rows + 1] = {
            name = rec.ch or L["Player"],
            classFile = rec.cl,
            role = dm.myRole or "NONE",
            dmg = dm.myDmg or 0,
            dps = dm.myDps or 0,
            heal = dm.myHeal or 0,
            hps = dm.myHps or 0,
            tkn = dm.myTkn or 0,
            intr = dm.myIntr or 0,
            disp = dm.myDisp or 0,
            d = dm.myD or 0,
            isSelf = true,
        }
    end
    for _, mm in ipairs(rec.m or {}) do
        if mm and mm.n and ((mm.dmg or 0) > 0 or (mm.heal or 0) > 0 or (mm.tkn or 0) > 0 or (mm.intr or 0) > 0 or (mm.disp or 0) > 0 or (mm.d or 0) > 0) then
            rows[#rows + 1] = {
                name = mm.n,
                classFile = mm.c,
                role = mm.r or "NONE",
                dmg = mm.dmg or 0,
                dps = mm.dps or 0,
                heal = mm.heal or 0,
                hps = mm.hps or 0,
                tkn = mm.tkn or 0,
                intr = mm.intr or 0,
                disp = mm.disp or 0,
                d = mm.d or 0,
                isSelf = false,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.dmg ~= b.dmg then return a.dmg > b.dmg end
        if a.heal ~= b.heal then return a.heal > b.heal end
        if a.tkn ~= b.tkn then return a.tkn > b.tkn end
        return (a.name or "") < (b.name or "")
    end)
    return rows
end

local function AppendDungeonRunTooltipMetrics(rec)
    if not (rec and GameTooltip) then return end
    if rec.diff and rec.diff ~= "" then
        GameTooltip:AddDoubleLine(L["Difficulty"], rec.diff, 0.78, 0.84, 0.92, 0.92, 0.94, 0.96)
    end
    if (rec.cdur or 0) > 0 or (rec.pulls or 0) > 0 then
        local cDurTxt = (ns.Group and ns.Group.FormatRunDuration) and ns.Group:FormatRunDuration(rec.cdur or 0) or "0s"
        local valTxt = ((rec.pulls or 0) > 0) and L["%s (%d pulls)"]:format(cDurTxt, rec.pulls) or cDurTxt
        GameTooltip:AddDoubleLine(L["Active Combat"], valTxt, 0.78, 0.84, 0.92, 1.0, 0.82, 0.35)
    end
    if (rec.dth or 0) > 0 or (rec.wipes or 0) > 0 then
        GameTooltip:AddDoubleLine(
            L["Deaths / Wipes"],
            L["%d deaths  ·  %d wipes"]:format(rec.dth or 0, rec.wipes or 0),
            0.78, 0.84, 0.92,
            1.0, 0.45, 0.45
        )
    end

    local dm = rec.dm
    if dm and ((dm.dmg or 0) > 0 or (dm.heal or 0) > 0 or (dm.tkn or 0) > 0) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Damage Meter (Blizzard)"], 1.0, 0.78, 0.25)
        if (dm.dmg or 0) > 0 then
            GameTooltip:AddDoubleLine(
                L["Group Damage"],
                string.format("%s (%s DPS)", FormatStatCompact(dm.dmg), FormatStatCompact(dm.dps or 0)),
                0.80, 0.86, 0.94,
                1.0, 0.74, 0.32
            )
        end
        if (dm.heal or 0) > 0 then
            GameTooltip:AddDoubleLine(
                L["Group Healing"],
                string.format("%s (%s HPS)", FormatStatCompact(dm.heal), FormatStatCompact(dm.hps or 0)),
                0.80, 0.86, 0.94,
                0.35, 0.90, 0.55
            )
        end
        if (dm.tkn or 0) > 0 then
            GameTooltip:AddDoubleLine(L["Damage Taken"], FormatStatCompact(dm.tkn), 0.80, 0.86, 0.94, 0.92, 0.62, 0.62)
        end
        if (dm.intr or 0) > 0 or (dm.disp or 0) > 0 then
            GameTooltip:AddDoubleLine(
                L["Interrupts / Dispels"],
                L["%d interrupts  ·  %d dispels"]:format(dm.intr or 0, dm.disp or 0),
                0.80, 0.86, 0.94,
                0.55, 0.85, 1.0
            )
        end

        local mRows = BuildDungeonRunMeterRows(rec)
        local groupDmg = math.max(1, dm.dmg or 1)
        local capRows = math.min(#mRows, 10)
        for idx = 1, capRows do
            local r = mRows[idx]
            local hex = Compat.ClassHex(r.classFile)
            local rTag = ROLE_BADGES[r.role or "NONE"] or ""
            local selfStar = r.isSelf and "|cffffd24d*|r " or ""
            local left = string.format("%d. %s%s %s%s|r", idx, selfStar, rTag, hex, r.name or "?")
            local parts = {}
            if r.dmg > 0 then
                local pct = math.floor(((r.dmg / groupDmg) * 100) + 0.5)
                parts[#parts + 1] = string.format("|cffffb84d%s (%d%%, %s/s)|r", FormatStatCompact(r.dmg), pct, FormatStatCompact(r.dps))
            end
            if r.heal > 0 then
                parts[#parts + 1] = string.format("|cff57d98c+%s (%s/s)|r", FormatStatCompact(r.heal), FormatStatCompact(r.hps))
            end
            if r.intr > 0 then
                parts[#parts + 1] = string.format("|cff58a6ff%di|r", r.intr)
            end
            if r.disp > 0 then
                parts[#parts + 1] = string.format("|cffb392f0%ddp|r", r.disp)
            end
            if r.d > 0 then
                parts[#parts + 1] = string.format("|cffff5555%dd|r", r.d)
            end
            GameTooltip:AddDoubleLine(left, table.concat(parts, " · "), 1, 1, 1, 0.92, 0.94, 0.96)
        end
    end

    local hasRewards = (rec.xp or 0) > 0 or (rec.lvup or 0) > 0 or (rec.gold or 0) > 0
    local hasLoot = type(rec.loot) == "table" and #rec.loot > 0
    if hasRewards or hasLoot then
        GameTooltip:AddLine(" ")
        if hasRewards then
            local rw = {}
            if (rec.xp or 0) > 0 then rw[#rw + 1] = "|cffc084fc" .. L["+%s XP"]:format(FormatStatCompact(rec.xp)) .. "|r" end
            if (rec.lvup or 0) > 0 then rw[#rw + 1] = "|cffffd24d" .. L["+%d Lv"]:format(rec.lvup) .. "|r" end
            if (rec.gold or 0) > 0 then rw[#rw + 1] = "|cffffd24d+" .. FormatGoldCompact(rec.gold) .. "|r" end
            GameTooltip:AddDoubleLine(L["Rewards & Progress"], table.concat(rw, "  ·  "), 0.78, 0.84, 0.92, 1, 1, 1)
        end
        if hasLoot then
            GameTooltip:AddLine(L["Notable Loot (%d)"]:format(#rec.loot), 0.45, 0.82, 1.0)
            for idx = 1, #rec.loot do
                local it = rec.loot[idx]
                if it and it.n then
                    local qc = (ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.q or 1]) or nil
                    local qHex = (qc and qc.hex) or "|cff1eff00"
                    local whoTxt = (it.w and it.w ~= "") and ("  ->  " .. it.w) or ""
                    GameTooltip:AddLine("  " .. qHex .. "[" .. it.n .. "]|r" .. whoTxt, 0.85, 0.88, 0.92)
                end
            end
        end
    end
end

local function FormatDungeonRunCopyText(rec, meterOnly)
    if type(rec) ~= "table" then return "" end
    local kindLbl = (rec.t == "raid") and L["Raid"] or L["Dungeon"]
    local durTxt = (ns.Group and ns.Group.FormatRunDuration) and ns.Group:FormatRunDuration(rec.dur or 0) or tostring(rec.dur or 0)
    local whenTxt = rec.st and date("%Y-%m-%d %H:%M", rec.st) or ""
    local lines = {}

    if meterOnly then
        local cPart = (rec.cdur and rec.cdur > 0 and ns.Group and ns.Group.FormatRunDuration)
            and ns.Group:FormatRunDuration(rec.cdur)
            or durTxt
        local pullPart = ((rec.pulls or 0) > 0) and (", " .. L["%d pulls"]:format(rec.pulls)) or ""
        lines[#lines + 1] = string.format("[%s] %s (%s%s)", L["Damage Meter (Blizzard)"], rec.z or "?", cPart, pullPart)
        if rec.dm then
            if (rec.dm.dmg or 0) > 0 then
                lines[#lines + 1] = string.format("%s: %s (%s DPS) | %s: %s (%s HPS)",
                    L["Group Damage"], FormatStatCompact(rec.dm.dmg), FormatStatCompact(rec.dm.dps or 0),
                    L["Group Healing"], FormatStatCompact(rec.dm.heal or 0), FormatStatCompact(rec.dm.hps or 0))
            end
            if (rec.dm.intr or 0) > 0 or (rec.dm.disp or 0) > 0 then
                lines[#lines + 1] = L["%d interrupts  ·  %d dispels"]:format(rec.dm.intr or 0, rec.dm.disp or 0)
            end
            local mRows = BuildDungeonRunMeterRows(rec)
            local groupDmg = math.max(1, rec.dm.dmg or 1)
            for idx, r in ipairs(mRows) do
                local roleTxt = (r.role and r.role ~= "NONE") and (" [" .. r.role .. "]") or ""
                local dmgPct = (r.dmg > 0) and string.format("%s (%d%%, %s DPS)", FormatStatCompact(r.dmg), math.floor(((r.dmg / groupDmg) * 100) + 0.5), FormatStatCompact(r.dps)) or "0"
                local extras = {}
                if r.heal > 0 then extras[#extras + 1] = string.format("%s HPS (%s)", FormatStatCompact(r.hps), FormatStatCompact(r.heal)) end
                if r.intr > 0 then extras[#extras + 1] = tostring(r.intr) .. " intr" end
                if r.disp > 0 then extras[#extras + 1] = tostring(r.disp) .. " disp" end
                if r.d > 0 then extras[#extras + 1] = tostring(r.d) .. " d" end
                local tail = (#extras > 0) and (" | " .. table.concat(extras, ", ")) or ""
                lines[#lines + 1] = string.format("%d. %s%s: %s%s", idx, r.name or "?", roleTxt, dmgPct, tail)
            end
        end
        return table.concat(lines, "\n")
    end

    lines = {
        string.format("[%s] %s — %s (%s)", kindLbl, rec.z or "?", durTxt, whenTxt),
        string.format("%s: %s", L["Character"], rec.ch or "?"),
    }
    if rec.diff and rec.diff ~= "" then
        lines[#lines + 1] = string.format("%s: %s", L["Difficulty"], rec.diff)
    end
    if (rec.cdur or 0) > 0 or (rec.pulls or 0) > 0 then
        local cTxt = (ns.Group and ns.Group.FormatRunDuration) and ns.Group:FormatRunDuration(rec.cdur or 0) or "0s"
        lines[#lines + 1] = string.format("%s: %s (%s)", L["Active Combat"], cTxt, L["%d pulls"]:format(rec.pulls or 0))
    end
    if (rec.dth or 0) > 0 or (rec.wipes or 0) > 0 then
        lines[#lines + 1] = string.format("%s: %s", L["Deaths / Wipes"], L["%d deaths  ·  %d wipes"]:format(rec.dth or 0, rec.wipes or 0))
    end
    if (rec.bk or 0) > 0 then
        local bossNames = (type(rec.bs) == "table" and #rec.bs > 0) and (" (" .. table.concat(rec.bs, ", ") .. ")") or ""
        lines[#lines + 1] = string.format("%s: %d%s", L["Bosses Defeated"], rec.bk, bossNames)
    end
    if rec.dm and ((rec.dm.dmg or 0) > 0 or (rec.dm.heal or 0) > 0) then
        lines[#lines + 1] = string.format("%s: %s (%s DPS) | %s: %s (%s HPS)",
            L["Group Damage"], FormatStatCompact(rec.dm.dmg or 0), FormatStatCompact(rec.dm.dps or 0),
            L["Group Healing"], FormatStatCompact(rec.dm.heal or 0), FormatStatCompact(rec.dm.hps or 0))
        local mRows = BuildDungeonRunMeterRows(rec)
        local groupDmg = math.max(1, rec.dm.dmg or 1)
        for idx, r in ipairs(mRows) do
            if idx <= 15 then
                local roleTxt = (r.role and r.role ~= "NONE") and (" [" .. r.role .. "]") or ""
                lines[#lines + 1] = string.format("  %d. %s%s: %s dmg (%d%%, %s DPS) | %s heal",
                    idx, r.name or "?", roleTxt, FormatStatCompact(r.dmg), math.floor(((r.dmg / groupDmg) * 100) + 0.5), FormatStatCompact(r.dps), FormatStatCompact(r.heal))
            end
        end
    end
    if (rec.xp or 0) > 0 or (rec.lvup or 0) > 0 or (rec.gold or 0) > 0 then
        local rw = {}
        if (rec.xp or 0) > 0 then rw[#rw + 1] = L["+%s XP"]:format(FormatStatCompact(rec.xp)) end
        if (rec.lvup or 0) > 0 then rw[#rw + 1] = L["+%d Lv"]:format(rec.lvup) end
        if (rec.gold or 0) > 0 then rw[#rw + 1] = "+" .. FormatGoldCompact(rec.gold) end
        lines[#lines + 1] = string.format("%s: %s", L["Rewards & Progress"], table.concat(rw, ", "))
    end
    if type(rec.loot) == "table" and #rec.loot > 0 then
        local lParts = {}
        for _, it in ipairs(rec.loot) do
            if it and it.n then
                lParts[#lParts + 1] = "[" .. it.n .. "]" .. ((it.w and it.w ~= "") and (" (" .. it.w .. ")") or "")
            end
        end
        lines[#lines + 1] = string.format("%s: %s", L["Notable Loot (%d)"]:format(#rec.loot), table.concat(lParts, ", "))
    end
    local names = {}
    for _, mm in ipairs(rec.m or {}) do
        if mm and mm.n then
            local roleTxt = (mm.r and mm.r ~= "NONE") and (" [" .. mm.r .. "]") or ""
            local gTxt = (mm.g and mm.g ~= "") and (" <" .. mm.g .. ">") or ""
            names[#names + 1] = mm.n .. roleTxt .. gTxt
        end
    end
    lines[#lines + 1] = string.format("%s (%d): %s", L["Teammates"], #names, (#names > 0) and table.concat(names, ", ") or "-")
    return table.concat(lines, "\n")
end

local function OpenDungeonRunContextMenu(anchor, panel, rec)
    if not (anchor and rec and MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        local durTxt = (ns.Group and ns.Group.FormatRunDuration) and ns.Group:FormatRunDuration(rec.dur or 0) or ""
        root:CreateTitle((rec.z or L["Instance"]) .. (durTxt ~= "" and ("  (" .. durTxt .. ")") or ""))

        local members = rec.m or {}
        if #members > 0 then
            local sub = root:CreateButton(L["Teammates"] .. " (" .. tostring(#members) .. ")")
            local shownMax = math.min(#members, 25)
            for i = 1, shownMax do
                local mm = members[i]
                if mm and mm.n then
                    local hex = Compat.ClassHex(mm.c)
                    local roleTag = ROLE_BADGES[mm.r or "NONE"] or ""
                    local mSub = sub:CreateButton(hex .. mm.n .. "|r " .. roleTag)
                    mSub:CreateButton(L["Whisper"], function()
                        if ns.Chat and ns.Chat.OpenPreferredConversation then
                            ns.Chat:OpenPreferredConversation({
                                targetName = mm.n,
                                lookupKey = mm.k,
                            })
                        else
                            Compat.Whisper(mm.n)
                        end
                    end)
                    mSub:CreateButton(L["Invite to Group"], function()
                        Compat.Invite(mm.n)
                    end)
                    if ns.Watchlist and ns.Watchlist.Add then
                        mSub:CreateButton(L["Add to Watchlist"], function()
                            ns.Watchlist:Add(mm.n)
                        end)
                    end
                    if Store and Store.SetSocialFlag then
                        mSub:CreateButton(L["Good Partner (+)"], function()
                            Store:SetSocialFlag(mm.k or mm.n, "GOOD")
                            ns:Emit("SOCIAL_UPDATED")
                        end)
                        mSub:CreateButton(L["Avoid / Red Flag"], function()
                            Store:SetSocialFlag(mm.k or mm.n, "AVOID")
                            ns:Emit("SOCIAL_UPDATED")
                        end)
                    end
                    mSub:CreateButton(L["Copy Name"], function()
                        if ns.UI and ns.UI.OpenCopyModal then
                            ns.UI:OpenCopyModal(mm.n, L["Copy Name"])
                        end
                    end)
                end
            end
        end

        root:CreateButton(L["Copy Run Summary"], function()
            if ns.UI and ns.UI.OpenCopyModal then
                ns.UI:OpenCopyModal(FormatDungeonRunCopyText(rec, false), L["Dungeon & Raid Log"])
            end
        end)

        if rec.dm and ((rec.dm.dmg or 0) > 0 or (rec.dm.heal or 0) > 0) then
            root:CreateButton(L["Copy Damage Meter Breakdown"], function()
                if ns.UI and ns.UI.OpenCopyModal then
                    ns.UI:OpenCopyModal(FormatDungeonRunCopyText(rec, true), L["Damage Meter (Blizzard)"])
                end
            end)
        end

        root:CreateDivider()
        root:CreateButton("|cffff5555" .. L["Delete This Run"] .. "|r", function()
            local function DoDelete()
                if ns.Group and ns.Group.DeleteDungeonRun then
                    ns.Group:DeleteDungeonRun(rec.id)
                end
                if panel and panel.Refresh then
                    panel:Refresh(false)
                end
            end
            if ns.UI and ns.UI.OpenConfirmModal then
                ns.UI:OpenConfirmModal({
                    title = L["Delete This Run"],
                    message = L["Remove %s from your Dungeon & Raid Log?"]:format(rec.z or L["Instance"]),
                    confirmText = L["Delete"],
                    confirmVariant = "danger",
                    onConfirm = DoDelete,
                })
            else
                DoDelete()
            end
        end)
    end)
end

local function CreateDungeonRunsSubView(panel, listCard)
    local rv = CreateFrame("Frame", nil, listCard)
    rv:SetAllPoints(listCard)
    rv:Hide()
    rv._filter = "ALL"

    local topStrip = CreateFrame("Frame", nil, rv)
    topStrip:SetPoint("TOPLEFT", 8, -6)
    topStrip:SetPoint("TOPRIGHT", -8, -6)
    topStrip:SetHeight(24)

    local helpBtn = AddHelp(
        topStrip,
        topStrip,
        L["Help: Dungeon & Raid Log"],
        L["Passively records started dungeon and raid groups, teammate names, roles, bosses defeated, and total run time from the first enemy pulled until the run ends."],
        L["Hover any run for the full teammate roster and boss details, or click a run to whisper/invite past teammates, copy the summary, or delete entries."],
        "RIGHT",
        "RIGHT",
        0,
        0
    )

    local clearBtn = Theme:CreateButton(topStrip, 24, 22, "", "default")
    Theme:ConfigureIconButton(clearBtn, 24, 22, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", {
        size = 13,
        color = { 1.0, 0.45, 0.45 },
        title = L["Clear Dungeon Log"],
        desc = L["Clear"],
    })
    clearBtn:SetPoint("RIGHT", helpBtn, "LEFT", -6, 0)
    clearBtn:SetScript("OnClick", function()
        local cnt = ns.Group and ns.Group.GetDungeonHistoryCount and ns.Group:GetDungeonHistoryCount() or 0
        if cnt <= 0 then return end
        local function DoClear()
            if ns.Group and ns.Group.ClearDungeonHistory then
                ns.Group:ClearDungeonHistory()
            end
            if panel and panel.Refresh then panel:Refresh(true) end
        end
        if ns.UI and ns.UI.OpenConfirmModal then
            ns.UI:OpenConfirmModal({
                title = L["Clear Dungeon Log"],
                message = L["Are you sure you want to delete all %d recorded dungeon and raid runs?"]:format(cnt),
                confirmText = L["Clear"],
                confirmVariant = "danger",
                onConfirm = DoClear,
            })
        else
            DoClear()
        end
    end)

    local filterBtn = Theme:CreateButton(topStrip, 24, 22, "", "default")
    Theme:ConfigureIconButton(filterBtn, 24, 22, "Interface\\Icons\\INV_Misc_Map_01", {
        size = 14,
        toggle = true,
        active = (rv._filter ~= "ALL"),
        activeColor = { 0.96, 0.76, 0.22 },
        tooltipFn = function()
            local fLabels = {
                ALL = L["All"],
                DUNGEON = L["Dungeons"],
                RAID = L["Raids"],
                CHAR = L["This Character"],
            }
            return L["Filters"] .. ": " .. (fLabels[rv._filter] or L["All"])
        end,
    })
    filterBtn:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)
    filterBtn:SetScript("OnClick", function(selfBtn)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        local opts = {
            { id = "ALL", label = L["All"] },
            { id = "DUNGEON", label = L["Dungeons"] },
            { id = "RAID", label = L["Raids"] },
            { id = "CHAR", label = L["This Character"] },
        }
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            for _, opt in ipairs(opts) do
                local fid = opt.id
                root:CreateRadio(opt.label, function()
                    return rv._filter == fid
                end, function()
                    rv._filter = fid
                    rv:Refresh(true)
                end)
            end
        end)
    end)

    local searchBox = Theme:CreateEditBox(topStrip, {
        height = 22,
        clearButton = true,
        placeholder = L["Search by dungeon, player or boss..."],
    })
    searchBox:SetPoint("LEFT", topStrip, "LEFT", 0, 0)
    searchBox:SetPoint("RIGHT", filterBtn, "LEFT", -6, 0)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:HookScript("OnTextChanged", function()
        if panel._view ~= "runs" then return end
        rv._searchTok = (rv._searchTok or 0) + 1
        local tok = rv._searchTok
        if C_Timer and C_Timer.After then
            C_Timer.After(0.12, function()
                if panel:IsShown() and panel._view == "runs" and rv._searchTok == tok then
                    rv:Refresh(true)
                end
            end)
        else
            rv:Refresh(true)
        end
    end)

    local statusBar = CreateFrame("Frame", nil, rv, "BackdropTemplate")
    statusBar:SetPoint("TOPLEFT", topStrip, "BOTTOMLEFT", 0, -4)
    statusBar:SetPoint("TOPRIGHT", topStrip, "BOTTOMRIGHT", 0, -4)
    statusBar:SetHeight(24)

    local statusLbl = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusLbl:SetPoint("LEFT", 8, 0)
    statusLbl:SetJustifyH("LEFT")
    statusLbl:SetWordWrap(false)

    local toggleRecBtn = Theme:CreateButton(statusBar, 22, 18, "", "default")
    Theme:ConfigureIconButton(toggleRecBtn, 22, 18, FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online", {
        size = 13,
        toggle = true,
        active = true,
        activeColor = { 0.25, 0.88, 0.45 },
        tooltipFn = function()
            local recOn = ns.Group and ns.Group.IsDungeonRunLogEnabled and ns.Group:IsDungeonRunLogEnabled()
            return recOn and L["Recording: ON"] or L["Recording: OFF"]
        end,
    })
    toggleRecBtn:SetPoint("RIGHT", -6, 0)
    toggleRecBtn:SetScript("OnClick", function()
        if ns.db and ns.db.settings then
            local cur = ns.db.settings.dungeonRunLogEnabled ~= false
            ns.db.settings.dungeonRunLogEnabled = not cur
            if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
            rv:Refresh(false)
        end
    end)
    statusLbl:SetPoint("RIGHT", toggleRecBtn, "LEFT", -8, 0)

    local runsScroll = Theme:CreateScrollList(rv, 54, function(rowParent, _, rowHeight)
        local row = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
        row:SetHeight(rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.94, 0.78, 0.06)

        row.statusBar = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.statusBar:SetWidth(3)
        row.statusBar:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -4)
        row.statusBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 4)
        row.statusBar:SetColorTexture(0.35, 0.72, 1.0, 0.90)

        row.durText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.durText:SetPoint("TOPRIGHT", -10, -7)
        row.durText:SetJustifyH("RIGHT")
        row.durText:SetWordWrap(false)

        row.whenText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.whenText:SetPoint("BOTTOMRIGHT", -10, 7)
        row.whenText:SetJustifyH("RIGHT")
        row.whenText:SetWordWrap(false)

        row.titleText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.titleText:SetPoint("TOPLEFT", 12, -7)
        row.titleText:SetPoint("RIGHT", row.durText, "LEFT", -8, 0)
        row.titleText:SetJustifyH("LEFT")
        row.titleText:SetWordWrap(false)

        row.membersText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.membersText:SetPoint("BOTTOMLEFT", 12, 7)
        row.membersText:SetPoint("RIGHT", row.whenText, "LEFT", -8, 0)
        row.membersText:SetJustifyH("LEFT")
        row.membersText:SetWordWrap(false)

        row:SetScript("OnClick", function(selfRow)
            if selfRow._rec then
                OpenDungeonRunContextMenu(selfRow, panel, selfRow._rec)
            end
        end)

        row:SetScript("OnEnter", function(selfRow)
            local rec = selfRow._rec
            if not (rec and GameTooltip) then return end
            GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
            local kindLbl = (rec.t == "raid") and L["Raid"] or L["Dungeon"]
            local durTxt = (ns.Group and ns.Group.FormatRunDuration) and ns.Group:FormatRunDuration(rec.dur or 0) or ""
            GameTooltip:AddLine(string.format("[%s] %s", kindLbl, rec.z or L["Instance"]), 1.0, 0.85, 0.30)
            GameTooltip:AddDoubleLine(L["Duration (1st pull to end)"], durTxt, 0.78, 0.84, 0.92, 0.40, 0.95, 0.55)
            if rec.st then
                local startStr = date("%d/%m %H:%M", rec.st)
                local endStr = rec.en and date("%H:%M", rec.en) or ""
                GameTooltip:AddDoubleLine(L["Started / Ended"], startStr .. (endStr ~= "" and (" - " .. endStr) or ""), 0.78, 0.84, 0.92, 0.92, 0.94, 0.96)
            end
            if ns.Group and ns.Group.GetRunEndReasonLabel then
                GameTooltip:AddDoubleLine(L["Ended By"], ns.Group:GetRunEndReasonLabel(rec.er), 0.78, 0.84, 0.92, 0.85, 0.88, 0.94)
            end
            local myHex = Compat.ClassHex(rec.cl)
            local myLv = (rec.clv and rec.clv > 0) and (" Lv." .. tostring(rec.clv)) or ""
            GameTooltip:AddDoubleLine(L["Character"], myHex .. (rec.ch or "?") .. "|r" .. myLv, 0.78, 0.84, 0.92, 1, 1, 1)
            if (rec.bk or 0) > 0 then
                GameTooltip:AddDoubleLine(L["Bosses Defeated"], tostring(rec.bk), 0.78, 0.84, 0.92, 1.0, 0.82, 0.25)
                if type(rec.bs) == "table" and #rec.bs > 0 then
                    GameTooltip:AddLine("  " .. table.concat(rec.bs, ", "), 0.86, 0.88, 0.92, true)
                end
            end
            AppendDungeonRunTooltipMetrics(rec)
            local members = rec.m or {}
            if #members > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(string.format("%s (%d):", L["Teammates"], #members), 0.45, 0.82, 1.0)
                local limit = math.min(#members, 20)
                for i = 1, limit do
                    local mm = members[i]
                    if mm and mm.n then
                        local hex = Compat.ClassHex(mm.c)
                        local rBadge = ROLE_BADGES[mm.r or "NONE"] or ""
                        local lvTxt = (mm.l and mm.l > 0) and (" Lv." .. tostring(mm.l)) or ""
                        local extra = ""
                        if mm.j then extra = extra .. " |cff58a6ff[" .. L["Joined mid-run"] .. "]|r" end
                        if mm.lv then extra = extra .. " |cffff9b42[" .. L["Left early"] .. "]|r" end
                        local rightTxt = (mm.g and mm.g ~= "") and ("<" .. mm.g .. ">") or ""
                        GameTooltip:AddDoubleLine(rBadge .. " " .. hex .. mm.n .. "|r" .. lvTxt .. extra, rightTxt, 1, 1, 1, 0.68, 0.76, 0.86)
                    end
                end
                if #members > limit then
                    GameTooltip:AddLine(L["...and %d more"]:format(#members - limit), 0.65, 0.72, 0.80)
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Click for teammate actions, copy summary, or delete"], 0.60, 0.70, 0.82, true)
            GameTooltip:Show()
        end)

        row:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        return row
    end, function(row, rec, _, pal)
        row._rec = rec
        local isRaid = (rec.t == "raid")
        if row.statusBar then
            if isRaid then
                row.statusBar:SetColorTexture(1.0, 0.56, 0.16, 0.92)
            else
                row.statusBar:SetColorTexture(0.32, 0.72, 1.0, 0.92)
            end
        end
        local typeBadge = isRaid and ("|cffff9433[" .. L["Raid"] .. "]|r ") or ("|cff58a6ff[" .. L["Dungeon"] .. "]|r ")
        local bossTag = ((rec.bk or 0) > 0) and ("  |cffffd24d(" .. L["%d boss(es)"]:format(rec.bk) .. ")|r") or ""
        local dmBadge = ""
        if rec.dm and (rec.dm.dmg or 0) > 0 then
            dmBadge = string.format("  |cffffb84d[%s · %s/s]|r", FormatStatCompact(rec.dm.dmg), FormatStatCompact(rec.dm.dps or 0))
        elseif rec.dm and (rec.dm.heal or 0) > 0 then
            dmBadge = string.format("  |cff57d98c[+%s]|r", FormatStatCompact(rec.dm.heal))
        end
        local charHex = Compat.ClassHex(rec.cl)
        local charTag = (rec.ch and rec.ch ~= "") and ("  |cff8b949e·|r " .. charHex .. rec.ch .. "|r") or ""
        row.titleText:SetText(typeBadge .. (rec.z or L["Instance"]) .. bossTag .. dmBadge .. charTag)

        local durTxt = (ns.Group and ns.Group.FormatRunDuration) and ns.Group:FormatRunDuration(rec.dur or 0) or ""
        row.durText:SetText("|cffffd24d" .. durTxt .. "|r")

        local whenStr = rec.st and ((Compat.FormatRelativeTime and Compat.FormatRelativeTime(rec.st, L)) or date("%d/%m %H:%M", rec.st)) or ""
        row.whenText:SetText(whenStr)
        row.whenText:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])

        local rwTail = ""
        if (rec.xp or 0) > 0 then
            rwTail = rwTail .. "  |cffc084fc" .. L["+%s XP"]:format(FormatStatCompact(rec.xp)) .. "|r"
        end
        if (rec.gold or 0) > 0 then
            rwTail = rwTail .. "  |cffffd24d+" .. FormatGoldCompact(rec.gold) .. "|r"
        end

        local members = rec.m or {}
        if #members > 0 then
            local parts = {}
            local capShow = isRaid and 5 or 7
            local lim = math.min(#members, capShow)
            for i = 1, lim do
                local mm = members[i]
                if mm and mm.n then
                    local hex = Compat.ClassHex(mm.c)
                    local rShort = (mm.r == "TANK" and "|cff58a6ffT|r ")
                        or (mm.r == "HEALER" and "|cff3fb950H|r ")
                        or (mm.r == "DAMAGER" and "|cffff6b6bD|r ")
                        or ""
                    local mStat = ""
                    if (mm.dmg or 0) > 0 then
                        mStat = " |cff9da7b5(" .. FormatStatCompact(mm.dmg) .. ")|r"
                    elseif (mm.heal or 0) > 0 then
                        mStat = " |cff57d98c(+" .. FormatStatCompact(mm.heal) .. ")|r"
                    end
                    parts[#parts + 1] = rShort .. hex .. mm.n .. "|r" .. mStat
                end
            end
            local tail = (#members > lim) and ("  |cff9da7b5+" .. tostring(#members - lim) .. "|r") or ""
            row.membersText:SetText(table.concat(parts, " · ") .. tail .. rwTail)
        else
            row.membersText:SetText(L["Solo / no teammates recorded"] .. rwTail)
            row.membersText:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])
        end
    end)

    runsScroll.container:SetPoint("TOPLEFT", 6, -62)
    runsScroll.container:SetPoint("BOTTOMRIGHT", -6, 6)

    function rv:RefreshTheme(skipRender)
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(statusBar, "surface", p)
        Theme:StyleButton(filterBtn, "default")
        Theme:StyleButton(clearBtn, "default")
        local recOn = ns.Group and ns.Group.IsDungeonRunLogEnabled and ns.Group:IsDungeonRunLogEnabled()
        Theme:StyleButton(toggleRecBtn, recOn and "primary" or "default")
        if helpBtn and helpBtn.RefreshTheme then helpBtn:RefreshTheme() end
        if runsScroll then
            runsScroll:RefreshTheme()
            if not skipRender then runsScroll:Render() end
        end
    end

    function rv:Refresh(resetScroll)
        local p = Theme:GetPalette()
        local recOn = ns.Group and ns.Group.IsDungeonRunLogEnabled and ns.Group:IsDungeonRunLogEnabled()
        Theme:SetIconToggle(toggleRecBtn, recOn == true, { 0.25, 0.88, 0.45 })
        Theme:SetIconToggle(filterBtn, rv._filter ~= "ALL", { 0.96, 0.76, 0.22 })

        local active = ns.Group and ns.Group.GetActiveDungeonRunSummary and ns.Group:GetActiveDungeonRunSummary()
        if active and active.started then
            local elTxt = (ns.Group and ns.Group.FormatRunDuration) and ns.Group:FormatRunDuration(active.elapsed or 0) or ""
            local liveExtra = ""
            if (active.pulls or 0) > 0 then
                liveExtra = liveExtra .. " · " .. L["%d pulls"]:format(active.pulls)
            end
            if (active.dmg or 0) > 0 then
                liveExtra = liveExtra .. " · " .. FormatStatCompact(active.dmg) .. " " .. L["Dmg"]
            end
            statusLbl:SetText(string.format("|cff3fb950●|r %s: %s · %s (%d)%s", L["In Progress"], active.zone or "?", elTxt, active.memberCount or 1, liveExtra))
        elseif active then
            statusLbl:SetText(string.format("|cffffd24d●|r %s: %s (%s)", L["Armed"], active.zone or "?", L["waiting for 1st pull"]))
        elseif not recOn then
            statusLbl:SetText("|cffff6b6b" .. L["Recording is paused. Click 'Recording: OFF' to re-enable."] .. "|r")
        else
            local totalCount = ns.Group and ns.Group.GetDungeonHistoryCount and ns.Group:GetDungeonHistoryCount() or 0
            statusLbl:SetText(L["Recorded runs: %d / 120 (event-driven, zero lag)"]:format(totalCount))
        end
        statusLbl:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])

        local q = searchBox:GetText() or ""
        local rows = (ns.Group and ns.Group.GetDungeonHistory) and ns.Group:GetDungeonHistory(q, rv._filter) or {}
        clearBtn:SetEnabled((ns.Group and ns.Group.GetDungeonHistoryCount and ns.Group:GetDungeonHistoryCount() or 0) > 0)
        local emptyText = (q ~= "" or rv._filter ~= "ALL")
            and L["No matching dungeon or raid runs found."]
            or L["No started dungeons or raids recorded yet. Runs are logged automatically from the 1st enemy pulled."]
        runsScroll:SetData(rows, emptyText, resetScroll)
    end

    rv.runsScroll = runsScroll
    return rv
end

local function CreateGroupLfgSubView(panel, listCard)
    local bv = CreateFrame("Frame", nil, listCard)
    bv:SetAllPoints(listCard)
    bv:Hide()
    panel.browseView = bv

    local ROW_H = 76
    local lfgTab = ns.LFGFrameTab

    local function TriggerBrowseChange(triggerOfficial, resetScroll)
        if not ns.LFGFrameTab then return end
        local tab = ns.LFGFrameTab
        tab._hasSearchedThisSession = true
        if tab.SaveBrowseFilters then tab:SaveBrowseFilters() end
        if triggerOfficial and tab.TriggerOfficialBrowseSearch then
            tab:TriggerOfficialBrowseSearch(true)
        end
        if tab.RefreshData then tab:RefreshData() end
        bv:Refresh(resetScroll == true)
        ns:Emit("LFG_BROWSE_STATE_CHANGED")
    end

    -- Row 1: Category, Activities ★, Search, Filters, Refresh, [?]
    local catBtn = Theme:CreateButton(bv, 92, 22, L["All Categories"], "default")
    catBtn:SetPoint("TOPLEFT", bv, "TOPLEFT", 8, -6)
    catBtn:SetScript("OnClick", function(selfBtn)
        if MenuUtil and MenuUtil.CreateContextMenu and ns.LFGFrameTab and ns.LFGFrameTab.PopulateCategoryMenu then
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                ns.LFGFrameTab:PopulateCategoryMenu(root, function()
                    bv:Refresh(true)
                end)
            end)
        end
    end)

    local actBtn = Theme:CreateButton(bv, 126, 22, L["All"], "default")
    actBtn:SetPoint("LEFT", catBtn, "RIGHT", 4, 0)
    actBtn:SetScript("OnClick", function(selfBtn)
        if MenuUtil and MenuUtil.CreateContextMenu and ns.LFGFrameTab and ns.LFGFrameTab.PopulateActivityMenu then
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                ns.LFGFrameTab:PopulateActivityMenu(root, function()
                    bv:Refresh(true)
                end)
            end)
        end
    end)

    local helpLfgBtn = AddHelp(
        bv,
        bv,
        L["Help: Find Groups (LFG)"],
        L["Browse groups ([LFM]) and individual players looking for a group ([Looking]) in separate collapsible sections, clearly badging Official Blizzard listings separately from [Guild], [Ally], and [Addon] listings."],
        L["Pick Category & Activities (starred favorites stay pinned above level filters), cycle Tri-State Roles (Any / + Needs / = Has), open Filters for Official Blizzard vs Guild/Addon controls and Favorites, toggle Bulletin Dungeon view, or click any row's right button to Ask to Join or Invite."],
        "TOPRIGHT",
        "TOPRIGHT",
        -8,
        -7,
        {
            target = bv,
            steps = {
                {
                    title = L["Category, Favorites & Search"],
                    tag = "1/3 · " .. L["Search"],
                    text = L["Select Category and Activities to filter specific dungeons/raids. Starred favorites remain visible above level limits."],
                    target = actBtn,
                },
                {
                    title = L["Tri-State Roles & Presets"],
                    tag = "2/3 · " .. L["Filters"],
                    text = L["Click Tank/Heal/DPS buttons to cycle Any -> + Needs -> = Has, toggle All/Groups/Looking, or open Filters for Exclude Classes, Languages, Playstyle, Players Looking (Roles/Class/Level/Sort), and saved Presets."],
                    target = function() return bv.roleRow or bv end,
                },
                {
                    title = L["1-Click Ask to Join & Whisper Templates"],
                    tag = "3/3 · " .. L["Actions"],
                    text = L["Click the right button on any group to Ask to Join using your {spec}/{activity_en} template (green check tracks contacted groups), or invite [Looking] players directly."],
                    target = function() return bv.lfgScroll and bv.lfgScroll.container or bv end,
                },
            },
        }
    )

    local refreshBtn = Theme:CreateButton(bv, 24, 22, "", "default")
    Theme:ConfigureIconButton(refreshBtn, 24, 22, "Interface\\Buttons\\UI-RefreshButton", {
        size = 14,
        title = L["Refresh"],
        desc = L["Search Blizzard Official LFG, Guild, Allies, and Global Chat for active listings."],
    })
    refreshBtn:SetPoint("RIGHT", helpLfgBtn, "LEFT", -4, 0)
    refreshBtn:SetScript("OnClick", function()
        if ns.Social and ns.Social.RequestRosters then
            ns.Social:RequestRosters(false)
        end
        if ns.Clan and ns.Clan.RequestExternalLFGCatchup then
            ns.Clan:RequestExternalLFGCatchup()
        end
        TriggerBrowseChange(true, false)
    end)

    local drawerBtn = Theme:CreateButton(bv, 96, 22, L["More Filters »"], "default")
    drawerBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -4, 0)
    Theme:AutoFitButton(drawerBtn, 84, 12, 126)
    drawerBtn:SetScript("OnClick", function()
        if ns.LFG and ns.LFG.ToggleSideDrawer then
            ns.LFG:ToggleSideDrawer(ns.LFGFrameTab)
            bv:Refresh(false)
        end
    end)

    local filterBtn = Theme:CreateButton(bv, 84, 22, L["Filters"], "default")
    filterBtn:SetPoint("RIGHT", drawerBtn, "LEFT", -4, 0)
    filterBtn:SetScript("OnClick", function(selfBtn)
        if MenuUtil and MenuUtil.CreateContextMenu and ns.LFGFrameTab and ns.LFGFrameTab.PopulateBrowseFilterMenu then
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                ns.LFGFrameTab:PopulateBrowseFilterMenu(root, function()
                    bv:Refresh(true)
                end)
            end)
        end
    end)

    local searchBox = Theme:CreateEditBox(bv, {
        height = 21,
        clearButton = true,
        placeholder = L["Search dungeon, raid, or player..."],
    })
    searchBox:SetPoint("LEFT", actBtn, "RIGHT", 4, 0)
    searchBox:SetPoint("RIGHT", filterBtn, "LEFT", -4, 0)
    searchBox:SetScript("OnEscapePressed", function(selfBox) selfBox:ClearFocus() end)
    searchBox:HookScript("OnTextChanged", function(selfBox)
        if panel._view ~= "browse" or not ns.LFGFrameTab then return end
        local txt = selfBox:GetText() or ""
        if (ns.LFGFrameTab.query or "") == txt then return end
        ns.LFGFrameTab.query = txt
        if txt ~= "" then
            ns.LFGFrameTab._hasSearchedThisSession = true
        end
        bv._searchToken = (bv._searchToken or 0) + 1
        local tok = bv._searchToken
        if C_Timer and C_Timer.After then
            C_Timer.After(0.12, function()
                if bv._searchToken == tok and panel._view == "browse" and panel:IsShown() then
                    if ns.LFGFrameTab.RefreshData then ns.LFGFrameTab:RefreshData() end
                    bv:Refresh(true)
                    ns:Emit("LFG_BROWSE_STATE_CHANGED")
                end
            end)
        else
            if ns.LFGFrameTab.RefreshData then ns.LFGFrameTab:RefreshData() end
            bv:Refresh(true)
            ns:Emit("LFG_BROWSE_STATE_CHANGED")
        end
    end)

    -- Row 2: All/Groups/Looking cycle, 3 Tri-State Role Buttons, Bulletin toggle, Role Check, List Group
    local roleRow = CreateFrame("Frame", nil, bv)
    roleRow:SetPoint("TOPLEFT", bv, "TOPLEFT", 8, -32)
    roleRow:SetPoint("TOPRIGHT", bv, "TOPRIGHT", -8, -32)
    roleRow:SetHeight(24)
    bv.roleRow = roleRow

    local typeBtn = Theme:CreateButton(roleRow, 74, 22, L["All"], "default")
    typeBtn:SetPoint("LEFT", roleRow, "LEFT", 0, 0)
    typeBtn:SetScript("OnClick", function()
        if not (ns.LFG and ns.LFG.GetListingType and ns.LFG.SetListingType) then return end
        local cur = ns.LFG:GetListingType()
        local nxt = (cur == "ALL" and "GROUPS") or (cur == "GROUPS" and "SOLO") or "ALL"
        ns.LFG:SetListingType(nxt)
    end)
    typeBtn:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Listing Type Filter"], 1.0, 0.82, 0.0)
        GameTooltip:AddLine(L["Click to cycle between All listings, Groups (LFM), and Players Looking (LFG)."], 0.88, 0.90, 0.94, true)
        GameTooltip:Show()
    end)
    typeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local roleBtns = {}
    local roleDefs = {
        { id = "TANK",   label = L["Tank"], ico = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:2:17:24:39|t " },
        { id = "HEALER", label = L["Heal"], ico = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:22:37:3:18|t " },
        { id = "DPS",    label = L["DPS"],  ico = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:22:37:24:39|t " },
    }
    local prevRoleBtn = typeBtn
    for _, rDef in ipairs(roleDefs) do
        local rb = Theme:CreateButton(roleRow, 86, 22, rDef.ico .. rDef.label, "default")
        rb._roleId = rDef.id
        rb._baseLabel = rDef.label
        rb._roleIco = rDef.ico
        rb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        rb:SetPoint("LEFT", prevRoleBtn, "RIGHT", 4, 0)
        rb:SetScript("OnClick", function(_, mouseBtn)
            if not ns.LFG then return end
            if mouseBtn == "RightButton" then
                ns.LFG:SetRoleState(rDef.id, 0)
            else
                ns.LFG:CycleRoleState(rDef.id)
            end
        end)
        rb:SetScript("OnEnter", function(selfBtn)
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Tri-State Role Filter"] .. ": " .. rDef.label, 1.0, 0.82, 0.0)
            GameTooltip:AddLine(L["Left-click cycles: Any -> + Needs (looking for this role) -> = Has (role already filled). Right-click resets to Any."], 0.88, 0.90, 0.94, true)
            GameTooltip:Show()
        end)
        rb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        roleBtns[#roleBtns + 1] = rb
        prevRoleBtn = rb
    end

    local listGroupBtn = Theme:CreateButton(roleRow, 84, 22, L["List Group"], "primary")
    Theme:AutoFitButton(listGroupBtn, 74, 12, 118)
    listGroupBtn:SetPoint("RIGHT", roleRow, "RIGHT", 0, 0)
    listGroupBtn:SetScript("OnClick", function()
        if ns.LFGFrameTab then
            if ns.LFGFrameTab.HasSelfActiveListing and not ns.LFGFrameTab:HasSelfActiveListing() then
                ns.LFGFrameTab.viewMode = "categories"
            end
            if ns.Compat and ns.Compat.IsWindowIntegrationEnabled and not ns.Compat.IsWindowIntegrationEnabled("I") then
                local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
                if inCombat then
                    ns:Print("%s", L["Unavailable during combat."])
                elseif ns.LFGFrameTab.ShowSubPanel and ns.LFGFrameTab.EnsureStandaloneLfgHost then
                    local host = ns.LFGFrameTab:EnsureStandaloneLfgHost()
                    ns.LFGFrameTab:ShowSubPanel(host)
                end
                return
            end
            if ns.LFGFrameTab.OpenOfficialModule then
                ns.LFGFrameTab:OpenOfficialModule("lfg")
            end
        end
    end)

    local bulletinBtn = Theme:CreateButton(roleRow, 24, 22, "", "default")
    Theme:ConfigureIconButton(bulletinBtn, 24, 22, "Interface\\Icons\\INV_Misc_Note_01", {
        size = 13,
        toggle = true,
        active = true,
        activeColor = { 0.35, 0.90, 0.55 },
        title = L["Group by Dungeon (Bulletin Board)"],
        desc = L["Groups listings into collapsible dungeon headers or shows a flat sorted list."],
    })
    bulletinBtn:SetPoint("RIGHT", listGroupBtn, "LEFT", -4, 0)
    bulletinBtn:SetScript("OnClick", function()
        if ns.db and ns.db.settings then
            local curBull = (ns.db.settings.lfgSplitGroupsAndPlayers == false) and (ns.db.settings.lfgBulletinMode ~= false)
            local targetBull = not curBull
            ns.db.settings.lfgBulletinMode = targetBull
            ns.db.settings.lfgSplitGroupsAndPlayers = not targetBull
            if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
            TriggerBrowseChange(false, false)
        end
    end)

    local roleCheckBtn = Theme:CreateButton(roleRow, 82, 22, L["Role Check"], "default")
    Theme:AutoFitButton(roleCheckBtn, 72, 12, 116)
    roleCheckBtn:SetPoint("RIGHT", bulletinBtn, "LEFT", -4, 0)
    roleCheckBtn:SetScript("OnClick", function()
        if ns.LFG and ns.LFG.TriggerRoleCheck then
            ns.LFG:TriggerRoleCheck()
        end
    end)
    roleCheckBtn:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Initiate Role Check"], 1.0, 0.82, 0.0)
        GameTooltip:AddLine(L["Triggers Blizzard's native group role poll for all party or raid members."], 0.88, 0.90, 0.94, true)
        GameTooltip:Show()
    end)
    roleCheckBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Row 3: Dynamic Active Filter Chips Bar (collapsed when 0 advanced filters active)
    local chipBar = CreateFrame("Frame", nil, bv)
    chipBar:SetPoint("TOPLEFT", bv, "TOPLEFT", 8, -58)
    chipBar:SetPoint("TOPRIGHT", bv, "TOPRIGHT", -8, -58)
    chipBar:SetHeight(20)
    chipBar:Hide()

    local chipPool = {}
    for ci = 1, 10 do
        local ch = Theme:CreateButton(chipBar, 72, 18, "", "default")
        ch:SetScript("OnClick", function(selfBtn)
            if selfBtn._onClear then selfBtn._onClear() end
        end)
        ch:Hide()
        chipPool[ci] = ch
    end
    local clearChipsBtn = Theme:CreateButton(chipBar, 54, 18, L["Clear"], "danger")
    Theme:AutoFitButton(clearChipsBtn, 54, 12, 92)
    clearChipsBtn:Hide()
    clearChipsBtn:SetScript("OnClick", function()
        if ns.LFG and ns.LFG.ResetAdvancedFilters then
            ns.LFG:ResetAdvancedFilters()
        end
    end)

    local lfgScroll = Theme:CreateScrollList(bv, ROW_H, function(rowParent)
        if ns.LFGFrameTab and ns.LFGFrameTab.CreateSharedLfgRow then
            return ns.LFGFrameTab.CreateSharedLfgRow(rowParent)
        end
        return CreateFrame("Button", nil, rowParent, "BackdropTemplate")
    end, function(row, item, idx, pal)
        if ns.LFGFrameTab and ns.LFGFrameTab.UpdateSharedLfgRow then
            ns.LFGFrameTab.UpdateSharedLfgRow(row, item, idx, pal)
        end
    end)
    lfgScroll.container:SetPoint("TOPLEFT", 6, -60)
    lfgScroll.container:SetPoint("BOTTOMRIGHT", -6, 6)
    bv.lfgScroll = lfgScroll

    bv:HookScript("OnHide", function()
        if ns.LFG and ns.LFG.IsSideDrawerShown and ns.LFG:IsSideDrawerShown() then
            local subShown = ns.LFGFrameTab and ns.LFGFrameTab.subPanel and ns.LFGFrameTab.subPanel:IsShown()
            if not subShown and ns.LFG.HideSideDrawer then
                ns.LFG:HideSideDrawer()
            end
        end
    end)

    function bv:RefreshTheme(skipRender)
        local p = Theme:GetPalette()
        Theme:StyleButton(catBtn, "default")
        Theme:StyleButton(actBtn, "default")
        Theme:StyleButton(drawerBtn, (ns.LFG and ns.LFG.IsSideDrawerShown and ns.LFG:IsSideDrawerShown()) and "primary" or "default")
        Theme:StyleButton(filterBtn, "default")
        Theme:StyleButton(refreshBtn, "default")
        Theme:StyleButton(typeBtn, "default")
        Theme:StyleButton(listGroupBtn, "primary")
        Theme:StyleButton(bulletinBtn, "default")
        Theme:StyleButton(roleCheckBtn, "default")
        Theme:StyleButton(clearChipsBtn, "danger")
        for _, rb in ipairs(roleBtns) do
            Theme:StyleButton(rb, "default")
        end
        for _, ch in ipairs(chipPool) do
            Theme:StyleButton(ch, "default")
        end
        if Theme.StyleEditBox then Theme:StyleEditBox(searchBox) end
        if helpLfgBtn and helpLfgBtn.RefreshTheme then helpLfgBtn:RefreshTheme() end
        if lfgScroll then
            lfgScroll:RefreshTheme()
            if not skipRender then lfgScroll:Render() end
        end
    end

    function bv:Refresh(resetScroll)
        local tab = ns.LFGFrameTab
        if not tab then return end
        if tab.LoadSavedBrowseFilters and not tab._filtersLoadedFromDb then
            tab:LoadSavedBrowseFilters(false)
        end
        if tab.GetCategoryLabel then
            Theme:SetButtonText(catBtn, tab:GetCategoryLabel(tab.categoryFilter, true))
            Theme:AutoFitButton(catBtn, 72, 14, 146)
        end
        if tab.GetBrowseActivityDropdownLabel then
            Theme:SetButtonText(actBtn, tab:GetBrowseActivityDropdownLabel())
            Theme:AutoFitButton(actBtn, 84, 14, 162)
        end
        local advCount = (ns.LFG and ns.LFG.CountActiveAdvancedFilters) and ns.LFG:CountActiveAdvancedFilters() or 0
        local fLabel = (advCount > 0) and (L["Filters"] .. " (" .. tostring(advCount) .. ")") or L["Filters"]
        Theme:SetButtonText(filterBtn, fLabel)
        Theme:AutoFitButton(filterBtn, 62, 14, 122)
        Theme:StyleButton(filterBtn, (advCount > 0 or (tab.sourceFilter or "ALL") ~= "ALL") and "primary" or "default")
        Theme:StyleButton(drawerBtn, (ns.LFG and ns.LFG.IsSideDrawerShown and ns.LFG:IsSideDrawerShown()) and "primary" or "default")

        if searchBox and searchBox.HasFocus and not searchBox:HasFocus() then
            local curQ = tab.query or ""
            if (searchBox:GetText() or "") ~= curQ then
                searchBox:SetText(curQ)
            end
        end

        local listType = (ns.LFG and ns.LFG.GetListingType) and ns.LFG:GetListingType() or "ALL"
        local typeTxt = (listType == "GROUPS" and L["Groups"]) or (listType == "SOLO" and L["Looking"]) or L["All"]
        Theme:SetButtonText(typeBtn, typeTxt)
        Theme:AutoFitButton(typeBtn, 58, 12, 110)
        Theme:StyleButton(typeBtn, (listType ~= "ALL") and "primary" or "default")

        for _, rb in ipairs(roleBtns) do
            local st = (ns.LFG and ns.LFG.GetRoleState) and ns.LFG:GetRoleState(rb._roleId) or 0
            local txt = (rb._roleIco or "") .. rb._baseLabel
            if st == 1 then
                txt = (rb._roleIco or "") .. "|cff3fb950+|r " .. rb._baseLabel
            elseif st == 2 then
                txt = (rb._roleIco or "") .. "|cffffd24d=|r " .. rb._baseLabel
            end
            Theme:SetButtonText(rb, txt)
            Theme:AutoFitButton(rb, 74, 12, 104)
            Theme:StyleButton(rb, (st > 0) and "primary" or "default")
        end

        local sCfg = ns.db and ns.db.settings
        local bulOn = (sCfg ~= nil) and (sCfg.lfgSplitGroupsAndPlayers == false) and (sCfg.lfgBulletinMode ~= false)
        Theme:SetIconToggle(bulletinBtn, bulOn, { 0.35, 0.90, 0.55 })

        local ch = ns.Group and ns.Group:GetChannelName()
        local canLead = ch and ((UnitIsGroupLeader and ns.Safe.Value(UnitIsGroupLeader("player"))) or (UnitIsGroupAssistant and ns.Safe.Value(UnitIsGroupAssistant("player"))))
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        roleCheckBtn:SetShown(canLead == true)
        roleCheckBtn:SetEnabled(not inCombat)

        local chips = (ns.LFG and ns.LFG.GetActiveFilterChips) and ns.LFG:GetActiveFilterChips() or {}
        local hasChips = (#chips > 0)
        chipBar:SetShown(hasChips)
        local prevChip = nil
        local maxBarW = math.max(240, (chipBar:GetWidth() or 460) - 58)
        local usedW = 0
        for ci = 1, #chipPool do
            local chBtn = chipPool[ci]
            local def = chips[ci]
            if def and (usedW + 64) <= maxBarW then
                Theme:SetButtonText(chBtn, (def.label or "?") .. " |cffff7b72x|r")
                Theme:AutoFitButton(chBtn, 46, 10, 128)
                chBtn:ClearAllPoints()
                if not prevChip then
                    chBtn:SetPoint("LEFT", chipBar, "LEFT", 0, 0)
                else
                    chBtn:SetPoint("LEFT", prevChip, "RIGHT", 4, 0)
                end
                chBtn._onClear = def.onClear
                chBtn:Show()
                prevChip = chBtn
                usedW = usedW + (chBtn:GetWidth() or 60) + 4
            else
                chBtn._onClear = nil
                chBtn:Hide()
            end
        end
        if hasChips and prevChip then
            Theme:AutoFitButton(clearChipsBtn, 44, 8, 72)
            clearChipsBtn:ClearAllPoints()
            clearChipsBtn:SetPoint("LEFT", prevChip, "RIGHT", 6, 0)
            clearChipsBtn:Show()
        else
            clearChipsBtn:Hide()
        end

        lfgScroll.container:ClearAllPoints()
        lfgScroll.container:SetPoint("TOPLEFT", 6, hasChips and -81 or -60)
        lfgScroll.container:SetPoint("BOTTOMRIGHT", -6, 6)

        local rows, emptyMsg = {}, L["Loading..."]
        if tab.GetSharedBrowseData then
            rows, emptyMsg = tab:GetSharedBrowseData()
        end
        lfgScroll:SetData(rows, emptyMsg, resetScroll)
    end

    return bv
end

function SocialPanels:CreateGroupPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel._view = "current"
    panel._raidLayout = "grid"
    panel._recentFilter = "ALL"

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

    local btnBroadcast = nil
    local helpTop = AddHelp(
        topCard,
        topCard,
        L["Help: Group, Find Groups & Companions"],
        L["Shows live Party/Raid members, integrated Find Groups (LFG) search, Recent Companions met in the last 365 days, and automatic Dungeon/Raid Run History."],
        L["Use 'Current Group' for active members, 'Find Groups (LFG)' to browse groups & players looking with Tri-State Role filters and Favorites, 'Recent' for past teammates & quick Good/Avoid ratings, or 'Dungeon Log' for recorded runs."],
        "TOPRIGHT",
        "TOPRIGHT",
        -8,
        -6,
        {
            target = topCard,
            steps = {
                {
                    title = L["Help: Group, Find Groups & Companions"],
                    tag = "1/4 · " .. L["Group"],
                    text = L["Switch here between Current Group, Find Groups (LFG), Recent Companions (last 365 days), and Dungeon/Raid Run History."],
                    target = topCard,
                },
                {
                    title = L["Find Groups (LFG)"],
                    tag = "2/4 · " .. L["LFG"],
                    text = L["Browse Official LFG, Global Chat, Guild, Allies, Friends & Watchlist with Tri-State Role filters, Exclude Classes, Languages, Favorite pinning, Presets, and 1-click Ask to Join / Invite."],
                    target = function()
                        return (panel._groupViewChips and panel._groupViewChips[2]) or topCard
                    end,
                },
                {
                    title = L["Buffs, Ready Check & Group Call"],
                    tag = "3/4 · " .. L["Actions"],
                    text = L["When in a party or raid, use these top-right action buttons to broadcast an LFG role call, trigger Ready Check, or audit missing Raid & World Buffs."],
                    target = function() return (btnBroadcast and btnBroadcast:IsVisible()) and btnBroadcast or topCard end,
                },
                {
                    title = L["Roster, Comp & Raid Grid"],
                    tag = "4/4 · " .. L["Members"],
                    text = L["Inspect live party or raid members, rate recent companions with quick Good/Avoid buttons, or switch to Grid layout for 10/25/40-player raids."],
                    target = function() return panel.listCard or panel end,
                },
            },
        }
    )
    panel._scHelpBtn = helpTop

    btnBroadcast = Theme:CreateButton(topCard, 26, 22, "", "primary")
    Theme:ConfigureIconButton(btnBroadcast, 26, 22, 132333, {
        size = 15,
    })
    btnBroadcast:SetPoint("RIGHT", helpTop, "LEFT", -6, 0)
    btnBroadcast:SetScript("OnClick", function()
        if ns.Clan and ns.Clan.PostSmartGroupFormation then
            local okPost, reason = ns.Clan:PostSmartGroupFormation()
            if not okPost and reason == "needs_activity" then
                if ns.LFGFrameTab then
                    ns.LFGFrameTab.viewMode = "categories"
                    if ns.LFGFrameTab.OpenOfficialModule then
                        ns.LFGFrameTab:OpenOfficialModule("lfg")
                    end
                end
                ns:Print("%s", L["Select the dungeon or activity you want to broadcast to Guild & Allies."])
            end
        end
    end)
    btnBroadcast:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Broadcast Group"], 1.0, 0.82, 0.0)
        GameTooltip:AddLine(L["Publishes your current party composition or role attempt to Guildmates, Allied Guilds, Friends, and SocialCentral [SC] users."], 0.88, 0.90, 0.94, true)
        GameTooltip:Show()
    end)
    btnBroadcast:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local btnReady = Theme:CreateButton(topCard, 26, 22, "", "default")
    Theme:ConfigureIconButton(btnReady, 26, 22, "Interface\\RAIDFRAME\\ReadyCheck-Ready", {
        size = 15,
        title = L["Ready Check"],
        desc = L["Starts a Ready Check for your party or raid."],
    })
    btnReady:SetPoint("RIGHT", btnBroadcast, "LEFT", -6, 0)
    btnReady:SetScript("OnClick", function()
        if ns.Group then ns.Group:StartReadyCheck() end
    end)

    local buffAuditModal
    local function OpenGroupBuffAuditModal()
        if not buffAuditModal then
            local m = CreateFrame("Frame", "SocialCentralGroupBuffAuditModal", UIParent, "BackdropTemplate")
            m:Hide()
            m:SetSize(440, 360)
            m:SetPoint("CENTER")
            if Theme.PrepareTopOverlayModal then
                Theme:PrepareTopOverlayModal(m, 835)
            else
                m:SetFrameStrata("FULLSCREEN_DIALOG")
                m:SetFrameLevel(835)
                m:SetToplevel(true)
            end
            m:EnableMouse(true)
            Theme:MakeMovable(m, { key = "modal_group_buff_audit" })
            table.insert(UISpecialFrames, "SocialCentralGroupBuffAuditModal")

            local bg = m:CreateTexture(nil, "BACKGROUND", nil, -8)
            bg:SetAllPoints()
            bg:SetTexture(WHITE8X8)
            m._solidOpaqueBg = bg

            local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            title:SetPoint("TOPLEFT", 14, -12)
            title:SetText(L["Raid Buffs & World Buffs Auditor"])
            m.title = title

            local closeX = Theme:CreateButton(m, 22, 20, "X", "default")
            closeX:SetPoint("TOPRIGHT", -10, -10)
            closeX:SetScript("OnClick", function() m:Hide() end)
            m.closeX = closeX

            m.helpBtn = AddHelp(
                m,
                closeX,
                L["Help: Raid Buffs & World Buffs Auditor"],
                L["Scans your party or raid for missing core class buffs and displays each player's active World Buffs and Chronoboon status."],
                L["Use this pre-pull checklist before bosses, or click Announce Missing Buffs to prefill a polite group reminder in chat."],
                "RIGHT",
                "LEFT",
                -4,
                0,
                { target = m }
            )
            title:SetPoint("TOPRIGHT", m.helpBtn or closeX, "LEFT", -6, 0)
            title:SetJustifyH("LEFT")
            title:SetWordWrap(false)

            local raidBox = CreateFrame("Frame", nil, m, "BackdropTemplate")
            raidBox:SetPoint("TOPLEFT", 12, -38)
            raidBox:SetPoint("TOPRIGHT", -12, -38)
            raidBox:SetHeight(74)
            m.raidBox = raidBox

            local raidLbl = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            raidLbl:SetPoint("TOPLEFT", 10, -8)
            raidLbl:SetPoint("BOTTOMRIGHT", -10, 8)
            raidLbl:SetJustifyH("LEFT")
            raidLbl:SetJustifyV("TOP")
            raidLbl:SetWordWrap(true)
            m.raidLbl = raidLbl

            local wbSummary = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            wbSummary:SetPoint("TOPLEFT", raidBox, "BOTTOMLEFT", 2, -10)
            wbSummary:SetPoint("TOPRIGHT", raidBox, "BOTTOMRIGHT", -2, -10)
            wbSummary:SetJustifyH("LEFT")
            m.wbSummary = wbSummary

            local scroll = Theme:CreateScrollList(m, 22, function(rowParent, _, rowHeight)
                local row = CreateFrame("Frame", nil, rowParent)
                row:SetHeight(rowHeight)
                row.nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.nameLbl:SetPoint("LEFT", 6, 0)
                row.nameLbl:SetWidth(148)
                row.nameLbl:SetJustifyH("LEFT")
                row.nameLbl:SetWordWrap(false)

                row.boonLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.boonLbl:SetPoint("RIGHT", -6, 0)
                row.boonLbl:SetWidth(86)
                row.boonLbl:SetJustifyH("RIGHT")
                row.boonLbl:SetWordWrap(false)

                row.buffsLbl = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.buffsLbl:SetPoint("LEFT", row.nameLbl, "RIGHT", 6, 0)
                row.buffsLbl:SetPoint("RIGHT", row.boonLbl, "LEFT", -6, 0)
                row.buffsLbl:SetJustifyH("LEFT")
                row.buffsLbl:SetWordWrap(false)
                return row
            end, function(row, item)
                local hex = Compat.ClassHex(item.classFile)
                row.nameLbl:SetText(hex .. (item.name or "?") .. "|r")
                if item.hasBoon then
                    row.boonLbl:SetText("|cff3fb950[" .. L["Chronoboon"] .. "]|r")
                else
                    row.boonLbl:SetText("|cff6e7681-|r")
                end
                if (item.activeCount or 0) > 0 then
                    row.buffsLbl:SetText("|cffffd24d" .. tostring(item.activeCount) .. ":|r |cffc8d1de" .. (item.buffsText or "") .. "|r")
                else
                    row.buffsLbl:SetText("|cff6e7681" .. L["No active World Buffs"] .. "|r")
                end
            end)
            scroll.container:SetPoint("TOPLEFT", wbSummary, "BOTTOMLEFT", -2, -6)
            scroll.container:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -12, 42)
            m.scroll = scroll

            local btnAnnounce = Theme:CreateButton(m, 190, 24, L["Announce Missing Buffs"], "primary")
            Theme:AutoFitButton(btnAnnounce, 150, 16, 240)
            btnAnnounce:SetPoint("BOTTOMLEFT", 12, 10)
            btnAnnounce:SetScript("OnClick", function()
                if ns.Group and ns.Group.OpenMissingBuffsDraft then
                    ns.Group:OpenMissingBuffsDraft()
                end
            end)
            m.btnAnnounce = btnAnnounce

            local btnClose = Theme:CreateButton(m, 88, 24, L["Close"], "default")
            Theme:AutoFitButton(btnClose, 78, 14, 130)
            btnClose:SetPoint("BOTTOMRIGHT", -12, 10)
            btnClose:SetScript("OnClick", function() m:Hide() end)
            m.btnClose = btnClose

            buffAuditModal = m
        end

        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(buffAuditModal, "window", p)
        Theme:ApplyBackdrop(buffAuditModal.raidBox, "inset", p)
        if buffAuditModal._solidOpaqueBg and p and p.windowBg then
            buffAuditModal._solidOpaqueBg:SetVertexColor(p.windowBg[1], p.windowBg[2], p.windowBg[3], 1.0)
        end
        Theme:StyleButton(buffAuditModal.closeX, "default")
        if buffAuditModal.helpBtn then Theme:StyleButton(buffAuditModal.helpBtn, "ghost") end
        Theme:StyleButton(buffAuditModal.btnAnnounce, "primary")
        Theme:StyleButton(buffAuditModal.btnClose, "default")
        buffAuditModal.scroll:RefreshTheme()

        local rAudit = ns.Group and ns.Group.GetMissingRaidBuffsAudit and ns.Group:GetMissingRaidBuffsAudit() or { missingCount = 0, detailLines = {} }
        if (rAudit.missingCount or 0) > 0 and #(rAudit.detailLines or {}) > 0 then
            local parts = {}
            for _, dl in ipairs(rAudit.detailLines) do
                parts[#parts + 1] = ("|cffffd24d%s (%d):|r %s"):format(dl.buff, dl.count, dl.players)
            end
            buffAuditModal.raidLbl:SetText(table.concat(parts, "\n"))
            buffAuditModal.btnAnnounce:SetEnabled(true)
        else
            buffAuditModal.raidLbl:SetText("|cff3fb950" .. L["All covered raid buffs are already active on everyone!"] .. "|r")
            buffAuditModal.btnAnnounce:SetEnabled(false)
        end
        local raidTxtH = (buffAuditModal.raidLbl.GetStringHeight and buffAuditModal.raidLbl:GetStringHeight()) or 48
        local wantBoxH = math.max(58, math.min(138, math.ceil(raidTxtH + 18)))
        if buffAuditModal.raidBox and math.abs((buffAuditModal.raidBox:GetHeight() or 74) - wantBoxH) >= 2 then
            buffAuditModal.raidBox:SetHeight(wantBoxH)
            buffAuditModal:SetHeight(360 + (wantBoxH - 74))
        end

        local wAudit = ns.Group and ns.Group.GetWorldBuffsAudit and ns.Group:GetWorldBuffsAudit() or { totalMembers = 0, withActiveCount = 0, withBoonCount = 0, rows = {} }
        buffAuditModal.wbSummary:SetText(("|cff58a6ff%s:|r %d/%d %s · %d %s"):format(
            L["World Buffs & Chronoboon"],
            wAudit.withActiveCount or 0,
            wAudit.totalMembers or 0,
            L["Active"],
            wAudit.withBoonCount or 0,
            L["Chronoboon"]
        ))
        buffAuditModal.scroll:SetData(wAudit.rows or {}, L["You are not in a group."], true)

        if Theme.PrepareTopOverlayModal then
            Theme:PrepareTopOverlayModal(buffAuditModal, 835)
        end
        buffAuditModal:Show()
        buffAuditModal:Raise()
    end

    local btnAuditBuffs = Theme:CreateButton(topCard, 26, 22, "", "default")
    Theme:ConfigureIconButton(btnAuditBuffs, 26, 22, 135964, {
        size = 15,
    })
    btnAuditBuffs:SetPoint("RIGHT", btnReady, "LEFT", -6, 0)
    btnAuditBuffs:SetScript("OnClick", function()
        if IsShiftKeyDown and IsShiftKeyDown() then
            if ns.Group and ns.Group.OpenMissingBuffsDraft then
                ns.Group:OpenMissingBuffsDraft()
            end
            return
        end
        OpenGroupBuffAuditModal()
    end)
    btnAuditBuffs:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Raid Buffs & World Buffs Auditor"], 1.0, 0.82, 0.0)
        GameTooltip:AddLine(L["Checks online group members for missing Fortitude, Arcane Intellect, Mark of the Wild, active World Buffs, and Chronoboon Displacer."], 0.88, 0.90, 0.94, true)
        GameTooltip:AddLine(L["Click: Open Auditor · Shift+Click: Draft Missing Buffs in chat"], 0.45, 0.85, 1.0, true)
        GameTooltip:Show()
    end)
    btnAuditBuffs:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    titleLbl:SetPoint("RIGHT", btnAuditBuffs, "LEFT", -10, 0)

    local viewChipDefs = {
        {
            id = "current",
            label = L["Group"],
            tex = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
            sz = 15,
            activeColor = { 0.35, 0.78, 1.0 },
        },
        {
            id = "browse",
            label = L["Find Groups (LFG)"],
            tex = "Interface\\GossipFrame\\BattleMasterGossipIcon",
            sz = 14,
            activeColor = { 0.35, 0.90, 0.55 },
            isBrowse = true,
        },
        {
            id = "recent",
            label = L["Recent Companions"],
            tex = "Interface\\Icons\\INV_Misc_PocketWatch_01",
            sz = 14,
            activeColor = { 0.45, 0.80, 1.0 },
        },
        {
            id = "runs",
            label = L["Dungeon Log"],
            tex = "Interface\\Icons\\INV_Misc_Map_01",
            sz = 14,
            activeColor = { 0.96, 0.76, 0.22 },
            isRuns = true,
        },
    }
    panel._groupViewChips = {}
    for _, def in ipairs(viewChipDefs) do
        local cBtn = Theme:CreateButton(topCard, 26, 22, "", "default")
        cBtn._viewId = def.id
        Theme:ConfigureIconButton(cBtn, 26, 22, def.tex, {
            size = def.sz or 14,
            toggle = true,
            active = (panel._view == def.id),
            activeColor = def.activeColor,
            tooltipFn = function()
                if def.isRuns then
                    local rc = (ns.Group and ns.Group.GetDungeonHistoryCount and ns.Group:GetDungeonHistoryCount()) or 0
                    local ttl = L["Dungeon & Raid Log"] .. (rc > 0 and (" (" .. tostring(rc) .. ")") or "")
                    return ttl, L["Shows started dungeons and raids with all teammate names, roles, bosses defeated, and total run time from the 1st enemy pulled."]
                end
                return def.label
            end,
        })
        cBtn:SetScript("OnClick", function()
            panel._view = def.id
            panel:Refresh(true)
        end)
        panel._groupViewChips[#panel._groupViewChips + 1] = cBtn
    end

    local btnView = Theme:CreateButton(topCard, 24, 22, "", "default")
    Theme:ConfigureIconButton(btnView, 24, 22, "Interface\\Buttons\\UI-OptionsButton", {
        size = 14,
        title = L["More"],
        desc = L["Current Group"] .. " · " .. L["Find Groups (LFG)"] .. " · " .. L["Recent Companions"] .. " · " .. L["Dungeon & Raid Log"],
    })
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
                root:CreateRadio(L["Find Groups (LFG)"], function()
                    return panel._view == "browse"
                end, function()
                    panel._view = "browse"
                    panel:Refresh(true)
                end)
                root:CreateRadio(L["Recent Companions"], function()
                    return panel._view == "recent"
                end, function()
                    panel._view = "recent"
                    panel:Refresh(true)
                end)
                root:CreateRadio(L["Dungeon & Raid Log"], function()
                    return panel._view == "runs"
                end, function()
                    panel._view = "runs"
                    panel:Refresh(true)
                end)
                if Compat.IsInRaid and Compat.IsInRaid() then
                    root:CreateDivider()
                    root:CreateRadio(L["Raid Grid (G1-G8)"], function()
                        return panel._view == "current" and panel._raidLayout ~= "list"
                    end, function()
                        panel._view = "current"
                        panel._raidLayout = "grid"
                        panel:Refresh(true)
                    end)
                    root:CreateRadio(L["Group List"], function()
                        return panel._view == "current" and panel._raidLayout == "list"
                    end, function()
                        panel._view = "current"
                        panel._raidLayout = "list"
                        panel:Refresh(true)
                    end)
                end
                root:CreateDivider()
                root:CreateButton(L["Broadcast Group to Clan & Friends"], function()
                    if ns.Clan and ns.Clan.PostSmartGroupFormation then
                        local okPost, reason = ns.Clan:PostSmartGroupFormation()
                        if not okPost and reason == "needs_activity" then
                            if ns.LFGFrameTab then
                                ns.LFGFrameTab.viewMode = "categories"
                                if ns.LFGFrameTab.OpenOfficialModule then
                                    ns.LFGFrameTab:OpenOfficialModule("lfg")
                                end
                            end
                            ns:Print("%s", L["Select the dungeon or activity you want to broadcast to Guild & Allies."])
                        end
                    end
                end)
                root:CreateButton(L["Open Group Finder (I)"], function()
                    if ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
                        ns.LFGFrameTab:OpenOfficialModule("lfg")
                    end
                end)
                root:CreateButton(L["Reset Dungeon Instances"], function()
                    if ns.UI and ns.UI.ConfirmResetInstances then
                        ns.UI:ConfirmResetInstances()
                    elseif ns.Group and ns.Group.ResetDungeonInstances then
                        ns.Group:ResetDungeonInstances()
                    end
                end)
            end)
        else
            panel._view = (panel._view == "current") and "recent" or ((panel._view == "recent") and "runs" or "current")
            panel:Refresh(true)
        end
    end)

    countLbl:SetPoint("RIGHT", btnView, "LEFT", -10, 0)

    local function LayoutGroupTopBar()
        local w = math.floor((topCard:GetWidth() or panel:GetWidth() or 730) + 0.5)
        if w <= 40 then w = 730 end
        local compact = topCard._scCompact and (w < 548) or (w < 532)
        if topCard._scCompact == nil then
            compact = (w < 540)
        end
        topCard._scCompact = compact
        local showReady = btnReady:IsShown()
        local showAuditBuffs = btnAuditBuffs:IsShown()
        local showBroadcast = btnBroadcast:IsShown()
        local sig = w .. ":" .. (compact and 1 or 0) .. ":" .. (showReady and 1 or 0) .. ":" .. (showAuditBuffs and 1 or 0) .. ":" .. (showBroadcast and 1 or 0)
            .. ":" .. math.floor(btnView._scAutoFitW or 0) .. ":" .. math.floor(panel._groupViewChips[3]._scAutoFitW or 0)
        if topCard._scTopBarSig == sig then
            return
        end
        topCard._scTopBarSig = sig

        titleLbl:ClearAllPoints()
        countLbl:ClearAllPoints()
        btnBroadcast:ClearAllPoints()
        btnBroadcast:SetPoint("RIGHT", helpTop, "LEFT", -6, 0)
        btnReady:ClearAllPoints()
        btnReady:SetPoint("RIGHT", showBroadcast and btnBroadcast or helpTop, "LEFT", -6, 0)
        btnAuditBuffs:ClearAllPoints()
        btnAuditBuffs:SetPoint("RIGHT", (showReady and btnReady) or (showBroadcast and btnBroadcast) or helpTop, "LEFT", -6, 0)
        local leftMostTopBtn = (showAuditBuffs and btnAuditBuffs) or (showReady and btnReady) or (showBroadcast and btnBroadcast) or helpTop

        if compact then
            titleLbl:SetPoint("TOPLEFT", topCard, "TOPLEFT", 10, -7)
            titleLbl:SetPoint("RIGHT", leftMostTopBtn, "LEFT", -8, 0)
            countLbl:SetPoint("TOPLEFT", topCard, "TOPLEFT", 10, -25)
            countLbl:SetPoint("TOPRIGHT", topCard, "TOPRIGHT", -10, -25)

            local flowBtns = {}
            for _, cb in ipairs(panel._groupViewChips) do
                flowBtns[#flowBtns + 1] = cb
            end
            flowBtns[#flowBtns + 1] = btnView
            local rows = LayoutButtonFlow(topCard, flowBtns, 8, -44, w - 16, 24, 4)
            local targetH = 44 + rows * 24 + 6
            if math.abs((topCard:GetHeight() or 0) - targetH) >= 1 then
                topCard:SetHeight(targetH)
            end
        else
            if math.abs((topCard:GetHeight() or 0) - 62) >= 1 then
                topCard:SetHeight(62)
            end

            local prevChip
            for _, cb in ipairs(panel._groupViewChips) do
                cb:ClearAllPoints()
                if not prevChip then
                    cb:SetPoint("BOTTOMLEFT", topCard, "BOTTOMLEFT", 8, 6)
                else
                    cb:SetPoint("LEFT", prevChip, "RIGHT", 4, 0)
                end
                prevChip = cb
            end

            btnView:ClearAllPoints()
            btnView:SetPoint("BOTTOMRIGHT", topCard, "BOTTOMRIGHT", -8, 6)

            if not topCard._legendBtn then
                topCard._legendBtn = Theme:CreateLegendTag(topCard, function()
                    return {
                        { tex = "Interface\\GroupFrame\\UI-Group-LeaderIcon", title = L["Current Group"] },
                        { tex = "Interface\\GossipFrame\\BattleMasterGossipIcon", title = L["Find Groups (LFG)"] },
                        { tex = "Interface\\Icons\\INV_Misc_PocketWatch_01", title = L["Recent Companions"] },
                        { tex = "Interface\\Icons\\INV_Misc_Map_01", title = L["Dungeon & Raid Log"] },
                        { tex = "Interface\\Buttons\\UI-OptionsButton", title = L["More"] },
                        { tex = 135964, title = L["Raid & Party Buff Auditor"] },
                        { tex = "Interface\\RAIDFRAME\\ReadyCheck-Ready", title = L["Ready Check"] },
                        { tex = "Interface\\Buttons\\UI-GuildButton-MOTD-Up", title = L["Broadcast Group to Clan & Friends"] },
                        { title = "|cff58a6ff[T]|r · |cff3fb950[H]|r · |cffff7b72[D]|r", desc = L["Tank · Healer · DPS Role"] },
                        { title = "|cff58a6ff[MT]|r · |cffffb833[MA]|r · |cfff2c94c[ML]|r", desc = L["Main Tank · Main Assist · Master Looter"] },
                        { tex = (FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online"), title = L["Online"] .. " / " .. L["Group"], desc = L["Confirmed online (Group, Friends, Guild, BNet, Watchlist)"] },
                        { tex = (FRIENDS_TEXTURE_OFFLINE or "Interface\\FriendsFrame\\StatusIcon-Offline"), title = L["Offline"], desc = L["Confirmed offline in Friends, Guild, or Watchlist"] },
                        { tex = (FRIENDS_TEXTURE_AFK or "Interface\\FriendsFrame\\StatusIcon-Away"), title = L["Unverified History"], desc = L["Outside Friends/Guild — right-click to add to Watchlist (/who)"] },
                        { title = "|cffffd24d*|r · |cff3fb950[SC]|r · |TInterface\\RAIDFRAME\\ReadyCheck-Ready:12:12:0:0|t · |TInterface\\RAIDFRAME\\ReadyCheck-NotReady:12:12:0:0|t", desc = L["Favorite · SocialCentral · Good Partner · Avoid"] },
                    }
                end)
            end
            local showGrpLeg = (w >= 540)
            topCard._legendBtn:SetShown(showGrpLeg)
            if showGrpLeg then
                topCard._legendBtn:ClearAllPoints()
                topCard._legendBtn:SetPoint("LEFT", prevChip or topCard, prevChip and "RIGHT" or "LEFT", 8, 0)
            end

            titleLbl:SetPoint("TOPLEFT", 10, -8)
            titleLbl:SetPoint("RIGHT", leftMostTopBtn, "LEFT", -10, 0)
            countLbl:SetPoint("LEFT", showGrpLeg and topCard._legendBtn or (prevChip or topCard), (showGrpLeg or prevChip) and "RIGHT" or "LEFT", 10, 0)
            countLbl:SetPoint("RIGHT", btnView, "LEFT", -8, 0)
        end
        if compact and topCard._legendBtn then
            topCard._legendBtn:Hide()
        end
    end
    topCard:SetScript("OnSizeChanged", LayoutGroupTopBar)
    LayoutGroupTopBar()

    local compCard = CreateGroupCompCard(panel, topCard)

    local listCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    listCard:SetPoint("TOPLEFT", compCard, "BOTTOMLEFT", 0, -6)
    listCard:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.listCard = listCard
    CreateRaidGridFrame(listCard, panel)
    panel.runsView = CreateDungeonRunsSubView(panel, listCard)
    panel.browseView = CreateGroupLfgSubView(panel, listCard)

    local recentFilterBtn = Theme:CreateButton(listCard, 24, 22, "", "default")
    Theme:ConfigureIconButton(recentFilterBtn, 24, 22, "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", {
        size = 15,
        toggle = true,
        active = (panel._recentFilter ~= "ALL"),
        activeColor = { 0.96, 0.76, 0.22 },
        tooltipFn = function()
            local fLabels = {
                ALL = L["All"],
                ONLINE = L["Online Only"],
                GOOD = L["Good Partner (+)"],
                TANK = L["Tank"],
                HEALER = L["Healer"],
                DAMAGER = L["DPS"],
            }
            return L["Filters"] .. ": " .. (fLabels[panel._recentFilter] or L["All"])
        end,
    })
    recentFilterBtn:SetPoint("TOPRIGHT", -8, -6)
    recentFilterBtn:Hide()
    recentFilterBtn:SetScript("OnClick", function(selfBtn)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        local opts = {
            { id = "ALL", label = L["All"] },
            { id = "ONLINE", label = L["Online Only"] },
            { id = "GOOD", label = L["Good Partner (+)"] },
            { id = "TANK", label = L["Tank"] },
            { id = "HEALER", label = L["Healer"] },
            { id = "DAMAGER", label = L["DPS"] },
        }
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            for _, opt in ipairs(opts) do
                local fid = opt.id
                root:CreateRadio(opt.label, function()
                    return panel._recentFilter == fid
                end, function()
                    panel._recentFilter = fid
                    panel:Refresh(true)
                end)
            end
        end)
    end)

    local recentSearch = Theme:CreateEditBox(listCard, {
        height = 22,
        clearButton = true,
        placeholder = L["Search companions by name or zone..."],
    })
    recentSearch:SetPoint("TOPLEFT", 8, -6)
    recentSearch:SetPoint("RIGHT", recentFilterBtn, "LEFT", -6, 0)
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

        row.btnQuickAvoid = Theme:CreateButton(row, 22, 22, "", "default")
        Theme:ConfigureIconButton(row.btnQuickAvoid, 22, 22, "Interface\\RAIDFRAME\\ReadyCheck-NotReady", {
            size = 13,
            toggle = true,
            active = false,
            activeColor = { 0.98, 0.28, 0.28 },
            title = L["Mark Avoid"],
            desc = L["Flags this player as Avoid so warnings and red highlights appear across Group Finder, Chat, and Recent Companions."],
        })
        row.btnQuickAvoid:SetPoint("RIGHT", row.btnPrimary, "LEFT", -4, 0)
        row.btnQuickAvoid:SetScript("OnClick", function()
            local it = row._item
            if not (it and Store and Store.SetSocialFlag) then return end
            local rKey = it.lookupKey or it.displayName
            if not rKey or rKey == "" then return end
            Store:SetSocialFlag(rKey, "AVOID")
            ns:Emit("SOCIAL_UPDATED")
            ns:Emit("LFG_BROWSE_STATE_CHANGED")
            panel:Refresh(false)
        end)
        row.btnQuickAvoid:Hide()

        row.btnQuickGood = Theme:CreateButton(row, 22, 22, "", "default")
        Theme:ConfigureIconButton(row.btnQuickGood, 22, 22, "Interface\\RAIDFRAME\\ReadyCheck-Ready", {
            size = 13,
            toggle = true,
            active = false,
            activeColor = { 0.25, 0.92, 0.45 },
            title = L["Mark Good Partner (+)"],
            desc = L["Flags this player as a Good Partner so green highlights and priority sorting appear across Group Finder and Recent Companions."],
        })
        row.btnQuickGood:SetPoint("RIGHT", row.btnQuickAvoid, "LEFT", -3, 0)
        row.btnQuickGood:SetScript("OnClick", function()
            local it = row._item
            if not (it and Store and Store.SetSocialFlag) then return end
            local rKey = it.lookupKey or it.displayName
            if not rKey or rKey == "" then return end
            Store:SetSocialFlag(rKey, "GOOD")
            ns:Emit("SOCIAL_UPDATED")
            ns:Emit("LFG_BROWSE_STATE_CHANGED")
            panel:Refresh(false)
        end)
        row.btnQuickGood:Hide()

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
                local bnetAccId = row._item.bnetAccountID or (bInfo and bInfo.bnetAccountID)
                local chatModOn = (not Compat.IsOfficialChatMode or not Compat.IsOfficialChatMode())
                    and ((not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("chat"))
                local scConfirmed = chatModOn and ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(rKey, bnetAccId)
                if scConfirmed and ns.Chat and ns.Chat.OpenPreferredConversation then
                    ns.Chat:OpenPreferredConversation({
                        targetName = rKey,
                        lookupKey = rKey,
                        bnetAccountID = bnetAccId,
                        bnetName = bnetName,
                        classFile = row._item.classFile,
                        isCrossFaction = isCrossFac,
                        online = row._item.online,
                        autoProbe = true,
                        scConfirmed = true,
                    })
                elseif isCrossFac and bnetName and Compat.BNetWhisper then
                    Compat.BNetWhisper(bnetName, row._item.displayName)
                else
                    Compat.Whisper(row._item.displayName)
                end
            end
        end)

        row:SetScript("OnClick", function(self, btn)
            if (btn == "RightButton" or btn == "LeftButton") and self._item then
                OpenGroupMemberMenu(self, panel, self._item)
            end
        end)

        function row:RefreshTheme()
            Theme:StyleButton(self.btnPrimary, "default")
            if self.btnQuickGood then Theme:StyleButton(self.btnQuickGood, "default") end
            if self.btnQuickAvoid then Theme:StyleButton(self.btnQuickAvoid, "default") end
        end

        return row
    end, function(row, item, idx, pal)
        row._item = item
        row._mode = panel._view
        row.subText:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])

        local hex = Compat.ClassHex(item.classFile)
        local lvl = (item.level and item.level > 0) and (" |cff9da7b5Lv." .. item.level .. "|r") or ""
        local roleTag = ROLE_BADGES[item.role or "NONE"] or ""
        local subTag = (panel._view == "current" and Compat.IsInRaid and Compat.IsInRaid() and item.subgroup)
            and (" |cff9da7b5[G" .. tostring(item.subgroup) .. "]|r") or ""
        local raidRoleTag = ""
        if panel._view == "current" then
            if item.raidRole == "MAINTANK" then raidRoleTag = " |cff58a6ff[MT]|r"
            elseif item.raidRole == "MAINASSIST" then raidRoleTag = " |cffffb833[MA]|r" end
            if item.isML then raidRoleTag = raidRoleTag .. " |cfff2c94c[ML]|r" end
            if item.isDead then raidRoleTag = raidRoleTag .. " " .. (Compat.StatusIconMarkup and Compat.StatusIconMarkup("DEAD", 13) or ("|cffff4d4d[" .. L["Dead"] .. "]|r")) end
        end
        local leadTag = item.isLeader and (" " .. (Compat.StatusIconMarkup and Compat.StatusIconMarkup("LEADER", 13) or ("|cffffd24d[" .. L["Leader"] .. "]|r"))) or (item.isAssistant and (" |cff58a6ff[" .. L["Assistant"] .. "]|r") or "")
        local recentOn, recentOff, recentStatusKey = ResolveRecentCompanionPresence(item)
        local readyTag = ""
        if item.ready == true then
            readyTag = " " .. (Compat.StatusIconMarkup and Compat.StatusIconMarkup("READY", 13) or "|cff3fb950[OK]|r")
        elseif item.ready == false then
            readyTag = " " .. (Compat.StatusIconMarkup and Compat.StatusIconMarkup("NOTREADY", 13) or "|cffff6b6b[NO]|r")
        elseif item.inCurrentGroup then
            readyTag = " |cff3fb950[" .. L["Group"] .. "]|r"
        elseif panel._view == "recent" and recentOn then
            readyTag = " |cff3fb950[" .. L["Online"] .. "]|r"
        end
        local scTag = (not item.isMe and ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(item.lookupKey or item.displayName))
            and (" " .. (Compat.AddonIconMarkup and Compat.AddonIconMarkup(true, 13) or "|cff3fb950[SC]|r")) or ""
        local meta = Store and (Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(item.lookupKey or item.displayName) or Store:GetSocialMeta(item.lookupKey or item.displayName))
        local flagTag = ""
        if meta and meta.flag == "AVOID" then
            flagTag = (Compat.StatusIconMarkup and Compat.StatusIconMarkup("AVOID", 13) or ("|cffff4d4d[" .. L["AVOID"] .. "]|r")) .. " "
        elseif meta and meta.flag == "GOOD" then
            flagTag = (Compat.StatusIconMarkup and Compat.StatusIconMarkup("GOOD", 13) or "|cff3fb950[+]|r") .. " "
        end
        local mainTag = (meta and meta.mainName) and (" |cff6ec1e4[" .. meta.mainName .. "]|r") or ""
        local isFavGrp = (not item.isMe) and Store and Store.IsSocialFavorite and (item.lookupKey or item.displayName) and Store:IsSocialFavorite(item.lookupKey or item.displayName)
        local starGrp = isFavGrp and (Compat.FavoriteStarMarkup and Compat.FavoriteStarMarkup(13) or "") or ""

        row.nameText:SetText(starGrp .. flagTag .. hex .. (item.displayName or "") .. "|r" .. lvl .. " " .. roleTag .. subTag .. leadTag .. raidRoleTag .. readyTag .. scTag .. mainTag)

        local subParts = {}
        if item.zone and item.zone ~= "" then table.insert(subParts, item.zone) end
        if panel._view == "current" and item.instanceUsed ~= nil then
            local iMax = item.instanceMax or 5
            local iCol = (item.instanceUsed >= iMax) and "|cffff5555" or ((item.instanceUsed >= iMax - 1) and "|cffffb833" or "|cff3fb950")
            table.insert(subParts, iCol .. L["Instances (1h): %d/%d"]:format(item.instanceUsed, iMax) .. "|r")
        end
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
            row.nameText:SetAlpha(item.online ~= false and 1.0 or 0.65)
            row.subText:SetAlpha(item.online ~= false and 0.94 or 0.58)
        else
            Theme:ApplyStatusColor(row.dot, recentStatusKey)
            if row.statusBar then
                Theme:ApplyStatusColor(row.statusBar, recentStatusKey)
                row.statusBar:SetAlpha(recentOn and 0.90 or (recentOff and 0.24 or 0.36))
            end
            row.nameText:SetAlpha(recentOn and 1.0 or (recentOff and 0.62 or 0.78))
            row.subText:SetAlpha(recentOn and 0.94 or (recentOff and 0.56 or 0.68))
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

        local showQuickFlags = (panel._view == "recent" and not item.isMe)
        if row.btnQuickGood and row.btnQuickAvoid then
            row.btnQuickGood:SetShown(showQuickFlags)
            row.btnQuickAvoid:SetShown(showQuickFlags)
            if showQuickFlags then
                local isG = (meta and meta.flag == "GOOD") == true
                local isA = (meta and meta.flag == "AVOID") == true
                Theme:SetIconToggle(row.btnQuickGood, isG, { 0.25, 0.92, 0.45 })
                Theme:SetIconToggle(row.btnQuickAvoid, isA, { 0.98, 0.28, 0.28 })
            end
        end

        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("TOPLEFT", 24, -5)
        row.subText:ClearAllPoints()
        row.subText:SetPoint("BOTTOMLEFT", 24, 5)
        if showQuickFlags and row.btnQuickGood then
            row.nameText:SetPoint("RIGHT", row.btnQuickGood, "LEFT", -8, 0)
            row.subText:SetPoint("RIGHT", row.btnQuickGood, "LEFT", -8, 0)
        elseif row.btnPrimary:IsShown() then
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
        if compCard then Theme:ApplyBackdrop(compCard, "surface", p) end
        Theme:ApplyBackdrop(listCard, "surface", p)
        Theme:StyleButton(btnView, "default")
        if self._groupViewChips then
            for _, cb in ipairs(self._groupViewChips) do
                local isAct = (self._view == cb._viewId)
                Theme:StyleButton(cb, isAct and "primary" or "default")
                Theme:SetButtonActive(cb, isAct, isAct and "primary" or "default")
            end
        end
        Theme:StyleButton(btnReady, "default")
        Theme:StyleButton(btnAuditBuffs, "default")
        Theme:StyleButton(btnBroadcast, "primary")
        Theme:StyleButton(recentFilterBtn, "default")
        if helpTop and helpTop.RefreshTheme then helpTop:RefreshTheme() end
        if self.runsView and self.runsView.RefreshTheme then
            self.runsView:RefreshTheme(skipRender)
        end
        if self.browseView and self.browseView.RefreshTheme then
            self.browseView:RefreshTheme(skipRender)
        end
        if self.raidGrid and self.raidGrid:IsShown() and ns.Group and ns.Group.GetCompositionAnalysis then
            UpdateRaidGridFrame(self, ns.Group:GetCompositionAnalysis())
        end
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
        local counts = ns.Group and ns.Group:GetSummaryCounts() or { total = 0, TANK = 0, HEALER = 0, DAMAGER = 0 }
        local inRaidNow = Compat.IsInRaid and Compat.IsInRaid()
        local isRunsView = (self._view == "runs")
        local isBrowseView = (self._view == "browse")
        local runCount = (ns.Group and ns.Group.GetDungeonHistoryCount and ns.Group:GetDungeonHistoryCount()) or 0
        btnReady:SetShown(ch ~= nil and self._view == "current")
        btnReady:SetEnabled((not inCombat) and canLead == true)
        btnAuditBuffs:SetShown(ch ~= nil and self._view == "current")
        btnBroadcast:SetShown(self._view == "current" and (not inRaidNow) and (counts.total or 0) < 5)
        btnBroadcast:SetEnabled(not inCombat)
        if self._groupViewChips then
            for _, cb in ipairs(self._groupViewChips) do
                Theme:SetIconToggle(cb, self._view == cb._viewId)
            end
        end
        LayoutGroupTopBar()

        local showRecentSearch = (self._view == "recent")
        recentSearch:SetShown(showRecentSearch)
        recentFilterBtn:SetShown(showRecentSearch)
        if showRecentSearch then
            Theme:SetIconToggle(recentFilterBtn, panel._recentFilter ~= "ALL", { 0.96, 0.76, 0.22 })
        end
        scroll.container:ClearAllPoints()
        scroll.container:SetPoint("TOPLEFT", 6, showRecentSearch and -32 or -6)
        scroll.container:SetPoint("BOTTOMRIGHT", -6, 6)

        local instStat = (ns.Group and ns.Group.GetHourlyInstanceStatus and ns.Group:GetHourlyInstanceStatus()) or { used = 0, max = 5 }
        local comp = (ns.Group and ns.Group.GetCompositionAnalysis) and ns.Group:GetCompositionAnalysis() or nil
        if isRunsView or isBrowseView then
            if panel.compCard then panel.compCard:Hide() end
        else
            UpdateGroupCompCard(panel, comp, instStat)
        end
        listCard:ClearAllPoints()
        if panel.compCard and panel.compCard:IsShown() then
            listCard:SetPoint("TOPLEFT", panel.compCard, "BOTTOMLEFT", 0, -6)
        else
            listCard:SetPoint("TOPLEFT", topCard, "BOTTOMLEFT", 0, -8)
        end
        listCard:SetPoint("BOTTOMRIGHT", 0, 0)

        local useRaidGrid = (self._view == "current") and (comp and comp.inRaid) and (self._raidLayout ~= "list")
        if panel.raidGrid then
            panel.raidGrid:SetShown((not isRunsView) and (not isBrowseView) and useRaidGrid)
        end
        if panel.runsView then
            panel.runsView:SetShown(isRunsView)
        end
        if panel.browseView then
            panel.browseView:SetShown(isBrowseView)
        end
        scroll.container:SetShown((not isRunsView) and (not isBrowseView) and (not useRaidGrid))

        local instTag = "  ·  " .. L["Instances (1h): %d/%d"]:format(instStat.used or 0, instStat.max or 5)
        if isBrowseView then
            if ns.LFGFrameTab and not ns.LFGFrameTab._hasSearchedThisSession then
                ns.LFGFrameTab._hasSearchedThisSession = true
                if ns.LFGFrameTab.TriggerOfficialBrowseSearch then
                    ns.LFGFrameTab:TriggerOfficialBrowseSearch(false)
                end
            end
            titleLbl:SetText(L["Find Groups (LFG)"])
            local advCnt = (ns.LFG and ns.LFG.CountActiveAdvancedFilters) and ns.LFG:CountActiveAdvancedFilters() or 0
            local advStr = (advCnt > 0) and (" · " .. L["%d filters"]:format(advCnt)) or ""
            countLbl:SetText(L["Official LFG, Global Chat, Guild, Allies & Watchlist"] .. advStr .. instTag)
            countLbl:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
            if panel.browseView and panel.browseView.Refresh then
                panel.browseView:Refresh(resetScroll)
            end
            return
        elseif isRunsView then
            titleLbl:SetText(L["Dungeon & Raid Log"])
            countLbl:SetText(string.format("%s: %d%s", L["Recorded Runs"], runCount, instTag))
            countLbl:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
            if panel.runsView and panel.runsView.Refresh then
                panel.runsView:Refresh(resetScroll)
            end
            return
        end
        local rQuery = showRecentSearch and (recentSearch:GetText() or "") or nil
        local rows, emptyText
        if self._view == "recent" then
            local allRecent = ns.Group and ns.Group:GetRecentCompanions(rQuery) or {}
            local onlineRecent = 0
            local filteredRecent = {}
            local rf = panel._recentFilter or "ALL"
            for _, rec in ipairs(allRecent) do
                local isOn = ResolveRecentCompanionPresence(rec)
                local passFilter = true
                if rf == "ONLINE" then
                    passFilter = isOn == true
                elseif rf == "GOOD" then
                    local recMeta = Store and (Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(rec.lookupKey or rec.displayName) or Store:GetSocialMeta(rec.lookupKey or rec.displayName))
                    passFilter = (recMeta and recMeta.flag == "GOOD") == true
                elseif rf == "TANK" or rf == "HEALER" or rf == "DAMAGER" then
                    passFilter = (rec.role == rf)
                end
                if passFilter then
                    if isOn then
                        onlineRecent = onlineRecent + 1
                    end
                    rec._isOnlineRecent = isOn
                    filteredRecent[#filteredRecent + 1] = rec
                end
            end
            table.sort(filteredRecent, function(a, b)
                local aOn = a._isOnlineRecent == true
                local bOn = b._isOnlineRecent == true
                if aOn ~= bOn then return aOn end
                local aSeen = tonumber(a.lastSeen) or 0
                local bSeen = tonumber(b.lastSeen) or 0
                if aSeen ~= bSeen then return aSeen > bSeen end
                return tostring(a.displayName or "") < tostring(b.displayName or "")
            end)
            titleLbl:SetText(L["Recent Companions"])
            countLbl:SetText(string.format("%s: %d  |cff3fb950(%d %s)|r%s", L["Recent Companions"], #filteredRecent, onlineRecent, L["Online"], instTag))
            rows = filteredRecent
            emptyText = (rQuery and rQuery ~= "" or rf ~= "ALL") and L["No matching players found."] or L["No recent companions recorded yet."]
        elseif ch then
            local rcTag = ""
            if ns.Group and ns.Group.readyCheckActive and ns.Group.GetReadyCheckProgress then
                local rOk, _, _, rTot = ns.Group:GetReadyCheckProgress()
                rcTag = "  |cffffd24d[" .. string.format(L["Ready Check: %d/%d"], rOk, rTot) .. "]|r"
            end
            titleLbl:SetText(L["Active Group"] .. "  |cff3fb950[" .. ch .. "]|r" .. rcTag)
            countLbl:SetText(string.format("%s: %d  (T:%d  H:%d  D:%d)%s", L["Members"], counts.total, counts.TANK, counts.HEALER, counts.DAMAGER, instTag))
            rows = ns.Group and ns.Group:GetMembers() or {}
            emptyText = L["Join a Party, Raid, or Instance group to track live members and roles."]
        else
            titleLbl:SetText(L["Not currently in a Party/Raid/Instance group"])
            countLbl:SetText(L["Switch to 'Recent Companions' to re-contact past instance teammates."] .. instTag)
            rows = ns.Group and ns.Group:GetMembers() or {}
            emptyText = L["Join a Party, Raid, or Instance group to track live members and roles."]
        end
        countLbl:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
        if useRaidGrid then
            UpdateRaidGridFrame(panel, comp)
        else
            scroll:SetData(rows, emptyText, resetScroll)
        end
    end

    local browseSyncQueued = false
    local function QueueBrowseViewSync()
        if not (panel:IsShown() and panel._view == "browse" and panel.browseView and panel.browseView.Refresh) then
            return
        end
        if C_Timer and C_Timer.After then
            if browseSyncQueued then return end
            browseSyncQueued = true
            C_Timer.After(0.06, function()
                browseSyncQueued = false
                if panel:IsShown() and panel._view == "browse" and panel.browseView and panel.browseView.Refresh then
                    panel.browseView:Refresh(false)
                end
            end)
        else
            panel.browseView:Refresh(false)
        end
    end
    ns:On("LFG_BROWSE_STATE_CHANGED", QueueBrowseViewSync)
    ns:On("CLAN_UPDATED", QueueBrowseViewSync)
    ns:On("SOCIAL_UPDATED", QueueBrowseViewSync)
    ns:On("GROUP_UPDATED", QueueBrowseViewSync)

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
        Theme:PrepareTopOverlayModal(m, 855)
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
            local hl = r:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.94, 0.78, 0.06)

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
            local scTag = scConfirmed and (" " .. (Compat.AddonIconMarkup and Compat.AddonIconMarkup(true, 13) or "|cff3fb950[SC]|r")) or ""
            local isFavModal = Store and Store.IsSocialFavorite and (item.lookupKey or item.displayName) and Store:IsSocialFavorite(item.lookupKey or item.displayName)
            local starModal = isFavModal and (Compat.FavoriteStarMarkup and Compat.FavoriteStarMarkup(12) or "") or ""
            r.name:SetText(starModal .. facIco .. hex .. disp .. "|r" .. scTag)

            local rightStr = ""
            if isBNet then
                rightStr = (Compat.BNetIconMarkup and Compat.BNetIconMarkup(14)) or "|cff70b5f9Battle.net|r"
            elseif item.sources and item.sources.friend then
                rightStr = (Compat.StatusIconMarkup and Compat.StatusIconMarkup("FRIEND", 14)) or ("|cff58a6ff" .. L["Friend"] .. "|r")
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

    Theme:PrepareTopOverlayModal(newChatModal, 855)
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
    if newChatModal.Raise then newChatModal:Raise() end
    newChatModal.input:SetFocus()
end

-- =====================================================================
-- Phase 1 Modals: Account Ignore, Mentions/Keywords & Filtered Chat Log
-- =====================================================================

local accountIgnoreModal
function SocialPanels:OpenAccountIgnoreModal(displayName, rawKey)
    if not accountIgnoreModal then
        local m = CreateFrame("Frame", "SocialCentralAccountIgnoreModal", UIParent, "BackdropTemplate")
        m:Hide()
        m:SetSize(430, 326)
        m:SetPoint("CENTER")
        Theme:PrepareTopOverlayModal(m, 855)
        Theme:MakeMovable(m, { key = "modal_account_ignore" })
        table.insert(UISpecialFrames, "SocialCentralAccountIgnoreModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -64, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["Account Ignore (Unlimited)"])
        m.title = title

        local topClose = Theme:CreateButton(m, 22, 20, "X", "default")
        topClose:SetPoint("TOPRIGHT", -10, -10)
        topClose:SetScript("OnClick", function()
            if m.nameIn then m.nameIn:ClearFocus() end
            if m.noteIn then m.noteIn:ClearFocus() end
            m:Hide()
        end)
        m.topClose = topClose

        m.helpBtn = AddHelp(
            m, topClose,
            L["Help: Account Ignore"],
            L["Blocks a player across all characters on your account with a reason, optional expiration, and automatic official chat hiding without using WoW's 50-slot character ignore limit."],
            L["Account-Ignored players also trigger Group Avoid warnings, LFG warnings, and Target Radar alerts. Never stores BattleTags or Real IDs."],
            "RIGHT", "LEFT", -6, 0
        )

        local nameLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameLbl:SetPoint("TOPLEFT", 16, -44)
        nameLbl:SetText(L["Character Name:"])
        m.nameLbl = nameLbl

        local btnTarget = Theme:CreateButton(m, 64, 22, L["Target"], "default")
        Theme:AutoFitButton(btnTarget, 64, 14, 110)
        btnTarget:SetPoint("TOPRIGHT", -16, -60)
        btnTarget:SetScript("OnClick", function()
            if UnitExists and UnitIsPlayer and UnitExists("target") and UnitIsPlayer("target") then
                local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName("target", nil, nil, true)
                local tName = (resolved and resolved.fullName) or (UnitName and ns.Safe.String(ns.Safe.Call(UnitName, "target")))
                if tName and tName ~= "" then
                    m.nameIn:SetText(tName)
                end
            else
                ns:Print("%s", L["Target a player first."])
            end
        end)
        m.btnTarget = btnTarget

        local nameIn = Theme:CreateEditBox(m, { height = 22, maxLetters = 48, clearButton = true, placeholder = L["FirstName Surname"] })
        nameIn:SetPoint("TOPLEFT", 16, -60)
        nameIn:SetPoint("RIGHT", btnTarget, "LEFT", -6, 0)
        nameIn:SetScript("OnEscapePressed", function(selfBox) selfBox:ClearFocus() end)
        m.nameIn = nameIn

        local reasonLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        reasonLbl:SetPoint("TOPLEFT", 16, -92)
        reasonLbl:SetText(L["Reason:"])

        local reasonDefs = {
            { id = "SPAM", label = L["Spammer"], w = 74 },
            { id = "SCAM", label = L["Scammer"], w = 74 },
            { id = "NINJA", label = L["Ninja Loot"], w = 82 },
            { id = "TOXIC", label = L["Toxic"], w = 68 },
            { id = "OTHER", label = L["Other"], w = 68 },
        }
        m.reasonBtns = {}
        for _, def in ipairs(reasonDefs) do
            local rb = Theme:CreateButton(m, def.w, 22, def.label, "default")
            Theme:AutoFitButton(rb, 56, 12, 112)
            rb._reasonId = def.id
            rb:SetScript("OnClick", function()
                m._selectedReason = def.id
                m.SyncChoiceVisuals()
            end)
            m.reasonBtns[#m.reasonBtns + 1] = rb
        end
        local rRows = LayoutButtonFlow(m, m.reasonBtns, 16, -108, 398, 26, 4)

        local durLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        local durLblY = -108 - (rRows * 26) - 4
        durLbl:SetPoint("TOPLEFT", 16, durLblY)
        durLbl:SetText(L["Duration:"])

        local durDefs = {
            { sec = 86400, label = L["24h"], w = 62 },
            { sec = 604800, label = L["7 days"], w = 74 },
            { sec = 2592000, label = L["30 days"], w = 78 },
            { sec = 0, label = L["Permanent"], w = 98 },
        }
        m.durBtns = {}
        for _, def in ipairs(durDefs) do
            local dbBtn = Theme:CreateButton(m, def.w, 22, def.label, "default")
            Theme:AutoFitButton(dbBtn, 56, 14, 120)
            dbBtn._durSec = def.sec
            dbBtn:SetScript("OnClick", function()
                m._selectedDur = def.sec
                m.SyncChoiceVisuals()
            end)
            m.durBtns[#m.durBtns + 1] = dbBtn
        end
        local dStartY = durLblY - 16
        local dRows = LayoutButtonFlow(m, m.durBtns, 16, dStartY, 398, 26, 6)

        local noteLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        local noteLblY = dStartY - (dRows * 26) - 6
        noteLbl:SetPoint("TOPLEFT", 16, noteLblY)
        noteLbl:SetText(L["Optional Note:"])

        local noteIn = Theme:CreateEditBox(m, { height = 22, maxLetters = 120, clearButton = true, placeholder = L["Add details (optional)..."] })
        noteIn:SetPoint("TOPLEFT", 16, noteLblY - 16)
        noteIn:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        noteIn:SetScript("OnEscapePressed", function(selfBox) selfBox:ClearFocus() end)
        m.noteIn = noteIn

        local hideChatCb = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
        hideChatCb:SetSize(22, 22)
        hideChatCb:SetPoint("TOPLEFT", 14, noteLblY - 48)
        m:SetHeight(math.max(308, math.abs(noteLblY - 48) + 74))
        hideChatCb.text = hideChatCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hideChatCb.text:SetPoint("LEFT", hideChatCb, "RIGHT", 4, 0)
        hideChatCb.text:SetText(L["Hide this player's messages in official WoW chat"])
        m.hideChatCb = hideChatCb

        local btnSave = Theme:CreateButton(m, 118, 24, L["Save Block"], "primary")
        Theme:AutoFitButton(btnSave, 108, 16, 170)
        btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnSave = btnSave

        local btnCancel = Theme:CreateButton(m, 86, 24, L["Cancel"], "default")
        Theme:AutoFitButton(btnCancel, 80, 14, 136)
        btnCancel:SetPoint("RIGHT", btnSave, "LEFT", -8, 0)
        btnCancel:SetScript("OnClick", function()
            nameIn:ClearFocus()
            noteIn:ClearFocus()
            m:Hide()
        end)
        m.btnCancel = btnCancel

        local btnRemove = Theme:CreateButton(m, 112, 24, L["Unblock"], "danger")
        Theme:AutoFitButton(btnRemove, 100, 16, 160)
        btnRemove:SetPoint("BOTTOMLEFT", 16, 14)
        btnRemove:Hide()
        m.btnRemove = btnRemove

        function m.SyncChoiceVisuals()
            for _, rb in ipairs(m.reasonBtns) do
                Theme:SetButtonActive(rb, rb._reasonId == m._selectedReason, "default")
            end
            for _, dbBtn in ipairs(m.durBtns) do
                Theme:SetButtonActive(dbBtn, dbBtn._durSec == m._selectedDur, "default")
            end
        end

        btnSave:SetScript("OnClick", function()
            local raw = Compat.CleanInput and Compat.CleanInput(nameIn:GetText() or "") or (nameIn:GetText() or "")
            if not raw or raw == "" then
                ns:Print("%s", L["Enter a character name to block."])
                return
            end
            if raw:find("#", 1, true) then
                ns:Print("%s", L["Use a character name (BattleTags are never stored)."])
                return
            end
            if Store and Store.SetAccountIgnore then
                local saved = Store:SetAccountIgnore(raw, {
                    name = raw,
                    reason = m._selectedReason or "OTHER",
                    note = noteIn:GetText() or "",
                    durationSec = m._selectedDur or 0,
                    hideChat = hideChatCb:GetChecked() == true,
                })
                if saved then
                    ns:Print("%s: %s", L["Account Ignore saved"], saved.name or raw)
                end
            end
            nameIn:ClearFocus()
            noteIn:ClearFocus()
            m:Hide()
        end)

        btnRemove:SetScript("OnClick", function()
            local keyToRemove = m._editingKey
            local dispToRemove = m._editingDisplay or keyToRemove
            if not keyToRemove then return end
            local function DoRemove()
                if Store and Store.RemoveAccountIgnore then
                    Store:RemoveAccountIgnore(keyToRemove, true)
                    ns:Print("%s: %s", L["Account Ignore removed"], dispToRemove or keyToRemove)
                end
                m:Hide()
            end
            if ns.UI and ns.UI.OpenConfirmModal then
                ns.UI:OpenConfirmModal({
                    title = L["Unblock"],
                    message = L["Are you sure you want to remove '%s' from your Account Ignore list?"]:format(dispToRemove or keyToRemove),
                    confirmText = L["Unblock"],
                    confirmVariant = "danger",
                    onConfirm = DoRemove,
                })
            else
                DoRemove()
            end
        end)

        accountIgnoreModal = m
    end

    local m = accountIgnoreModal
    Theme:PrepareTopOverlayModal(m, 855)
    Theme:ApplyBackdrop(m, "window")
    Theme:StyleButton(m.topClose, "default")
    Theme:StyleButton(m.btnTarget, "default")
    Theme:StyleButton(m.btnSave, "primary")
    Theme:StyleButton(m.btnCancel, "default")
    Theme:StyleButton(m.btnRemove, "danger")
    for _, rb in ipairs(m.reasonBtns) do Theme:StyleButton(rb, "default") end
    for _, dbBtn in ipairs(m.durBtns) do Theme:StyleButton(dbBtn, "default") end
    if m.helpBtn and m.helpBtn.RefreshTheme then m.helpBtn:RefreshTheme() end

    local lookupInput = rawKey or displayName
    local existing, existKey
    if lookupInput and Store and Store.GetAccountIgnore then
        existing, existKey = Store:GetAccountIgnore(lookupInput)
    end
    if existing then
        m._editingKey = existKey or lookupInput
        m._editingDisplay = existing.name or displayName or lookupInput
        m.nameIn:SetText(existing.name or displayName or "")
        m.noteIn:SetText(existing.note or "")
        m._selectedReason = existing.reason or "OTHER"
        if (existing.expiresAt or 0) <= 0 then
            m._selectedDur = 0
        else
            local rem = existing.expiresAt - time()
            if rem <= 100000 then m._selectedDur = 86400
            elseif rem <= 700000 then m._selectedDur = 604800
            else m._selectedDur = 2592000 end
        end
        m.hideChatCb:SetChecked(existing.hideChat ~= false)
        m.btnRemove:Show()
    else
        m._editingKey = nil
        m._editingDisplay = nil
        m.nameIn:SetText(displayName or "")
        m.noteIn:SetText("")
        m._selectedReason = "SPAM"
        m._selectedDur = 0
        m.hideChatCb:SetChecked(true)
        m.btnRemove:Hide()
    end
    m.SyncChoiceVisuals()
    Theme:SyncSubtreeLayers(m, 8)
    m:Show()
    if m.Raise then m:Raise() end
    if (m.nameIn:GetText() or "") == "" then
        m.nameIn:SetFocus()
    else
        m.noteIn:SetFocus()
    end
end

local mentionKeywordsModal
function SocialPanels:OpenMentionKeywordsModal()
    if not mentionKeywordsModal then
        local m = CreateFrame("Frame", "SocialCentralMentionKeywordsModal", UIParent, "BackdropTemplate")
        m:Hide()
        m:SetSize(440, 324)
        m:SetPoint("CENTER")
        Theme:PrepareTopOverlayModal(m, 855)
        Theme:MakeMovable(m, { key = "modal_mention_keywords" })
        table.insert(UISpecialFrames, "SocialCentralMentionKeywordsModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -64, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["Mentions & Keywords Radar"])
        m.title = title

        local topClose = Theme:CreateButton(m, 22, 20, "X", "default")
        topClose:SetPoint("TOPRIGHT", -10, -10)
        topClose:SetScript("OnClick", function()
            if m.nickIn then m.nickIn:ClearFocus() end
            if m.kwIn then m.kwIn:ClearFocus() end
            m:Hide()
        end)
        m.topClose = topClose

        m.helpBtn = AddHelp(
            m, topClose,
            L["Help: Mentions & Keywords Radar"],
            L["Highlights matched words in gold directly inside chat messages, triggers optional alerts, and logs matches in the Mentions Radar whenever your name, nicknames, or keywords appear in selected channels."],
            L["Separate multiple entries with commas (e.g. 'Onyxia, Crusader, Portal, Tank'). Respects Do Not Disturb and Auto-Silence in Instances."],
            "RIGHT", "LEFT", -6, 0
        )

        local function MakeModalCb(xOff, yOff, text)
            local cb = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("TOPLEFT", xOff, yOff)
            cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            cb.text:SetText(text)
            return cb
        end

        m.enableCb = MakeModalCb(14, -42, L["Enable Mentions & Keywords Radar"])
        m.soundCb = MakeModalCb(14, -66, L["Play audio chime on mention or keyword match"])

        local nickLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nickLbl:SetPoint("TOPLEFT", 16, -96)
        nickLbl:SetText(L["Personal nicknames / alt names (comma-separated):"])
        local nickIn = Theme:CreateEditBox(m, { height = 22, maxLetters = 160, clearButton = true, placeholder = L["e.g. Rapha, Tank, MainName"] })
        nickIn:SetPoint("TOPLEFT", 16, -112)
        nickIn:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        nickIn:SetScript("OnEscapePressed", function(selfBox) selfBox:ClearFocus() end)
        m.nickIn = nickIn

        local kwLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        kwLbl:SetPoint("TOPLEFT", 16, -142)
        kwLbl:SetText(L["Custom monitored keywords (comma-separated):"])
        local kwIn = Theme:CreateEditBox(m, { height = 22, maxLetters = 200, clearButton = true, placeholder = L["e.g. Onyxia, Crusader, Portal, BRD"] })
        kwIn:SetPoint("TOPLEFT", 16, -158)
        kwIn:SetPoint("RIGHT", m, "RIGHT", -16, 0)
        kwIn:SetScript("OnEscapePressed", function(selfBox) selfBox:ClearFocus() end)
        m.kwIn = kwIn

        local chLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        chLbl:SetPoint("TOPLEFT", 16, -188)
        chLbl:SetText(L["Monitored chat channels:"])

        m.chGuildCb = MakeModalCb(14, -204, L["Guild / Officer"])
        m.chGroupCb = MakeModalCb(216, -204, L["Party / Raid / Instance"])
        m.chSayCb = MakeModalCb(14, -228, L["Say / Yell"])
        m.chPubCb = MakeModalCb(216, -228, L["Public Channels (Trade/General)"])

        local btnSave = Theme:CreateButton(m, 96, 24, L["Save"], "primary")
        Theme:AutoFitButton(btnSave, 86, 16, 140)
        btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnSave = btnSave

        local btnCancel = Theme:CreateButton(m, 84, 24, L["Close"], "default")
        Theme:AutoFitButton(btnCancel, 78, 14, 130)
        btnCancel:SetPoint("RIGHT", btnSave, "LEFT", -8, 0)
        btnCancel:SetScript("OnClick", function()
            nickIn:ClearFocus()
            kwIn:ClearFocus()
            m:Hide()
        end)
        m.btnCancel = btnCancel

        local btnTest = Theme:CreateButton(m, 128, 24, L["Test Mention Alert"], "default")
        Theme:AutoFitButton(btnTest, 112, 16, 175)
        btnTest:SetPoint("BOTTOMLEFT", 16, 14)
        btnTest:SetScript("OnClick", function()
            if ns.Chat and ns.Chat.TriggerTestMention then
                ns.Chat:TriggerTestMention()
            end
        end)
        m.btnTest = btnTest

        btnSave:SetScript("OnClick", function()
            local s = ns.db and ns.db.settings
            if s then
                s.mentionAlertsEnabled = m.enableCb:GetChecked() == true
                s.mentionSound = m.soundCb:GetChecked() == true
                s.mentionNicknames = (Compat.CleanInput and Compat.CleanInput(nickIn:GetText() or "")) or ""
                s.mentionKeywords = (Compat.CleanInput and Compat.CleanInput(kwIn:GetText() or "")) or ""
                s.mentionWatchGuild = m.chGuildCb:GetChecked() == true
                s.mentionWatchGroup = m.chGroupCb:GetChecked() == true
                s.mentionWatchSayYell = m.chSayCb:GetChecked() == true
                s.mentionWatchPublic = m.chPubCb:GetChecked() == true
            end
            nickIn:ClearFocus()
            kwIn:ClearFocus()
            ns:Emit("SETTINGS_UPDATED")
            ns:Emit("CHAT_UPDATED")
            m:Hide()
        end)

        mentionKeywordsModal = m
    end

    local m = mentionKeywordsModal
    local s = ns.db and ns.db.settings or {}
    Theme:PrepareTopOverlayModal(m, 855)
    Theme:ApplyBackdrop(m, "window")
    Theme:StyleButton(m.topClose, "default")
    Theme:StyleButton(m.btnSave, "primary")
    Theme:StyleButton(m.btnCancel, "default")
    Theme:StyleButton(m.btnTest, "default")
    if m.helpBtn and m.helpBtn.RefreshTheme then m.helpBtn:RefreshTheme() end

    m.enableCb:SetChecked(s.mentionAlertsEnabled ~= false)
    m.soundCb:SetChecked(s.mentionSound ~= false)
    m.nickIn:SetText(s.mentionNicknames or "")
    m.kwIn:SetText(s.mentionKeywords or "")
    m.chGuildCb:SetChecked(s.mentionWatchGuild ~= false)
    m.chGroupCb:SetChecked(s.mentionWatchGroup ~= false)
    m.chSayCb:SetChecked(s.mentionWatchSayYell ~= false)
    m.chPubCb:SetChecked(s.mentionWatchPublic ~= false)

    Theme:SyncSubtreeLayers(m, 8)
    m:Show()
    if m.Raise then m:Raise() end
end

local filteredChatModal
function SocialPanels:OpenFilteredChatModal()
    if not filteredChatModal then
        local m = CreateFrame("Frame", "SocialCentralFilteredChatModal", UIParent, "BackdropTemplate")
        m:Hide()
        m:SetSize(520, 360)
        m:SetPoint("CENTER")
        Theme:PrepareTopOverlayModal(m, 855)
        Theme:MakeMovable(m, { key = "modal_filtered_chat" })
        table.insert(UISpecialFrames, "SocialCentralFilteredChatModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -64, -14)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(L["Filtered Chat Log"])
        m.title = title

        local topClose = Theme:CreateButton(m, 22, 20, "X", "default")
        topClose:SetPoint("TOPRIGHT", -10, -10)
        topClose:SetScript("OnClick", function() m:Hide() end)
        m.topClose = topClose

        m.helpBtn = AddHelp(
            m, topClose,
            L["Help: Filtered Chat Log"],
            L["Shows every message hidden this session by your Account Ignore list or the optional Public Anti-Spam Shield so nothing legitimate is ever lost silently."],
            L["Click any row to copy the message, edit/remove an Account Ignore, or block a spammer permanently."],
            "RIGHT", "LEFT", -6, 0
        )

        local summaryLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        summaryLbl:SetPoint("TOPLEFT", 16, -40)
        summaryLbl:SetPoint("TOPRIGHT", -16, -40)
        summaryLbl:SetJustifyH("LEFT")
        m.summaryLbl = summaryLbl

        local listWrap = CreateFrame("Frame", nil, m, "BackdropTemplate")
        listWrap:SetPoint("TOPLEFT", 14, -60)
        listWrap:SetPoint("BOTTOMRIGHT", -14, 46)
        m.listWrap = listWrap

        local scroll = Theme:CreateScrollList(listWrap, 42, function(rowParent, _, rh)
            local r = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
            r:SetHeight(rh)
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            r.top = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.top:SetPoint("TOPLEFT", 8, -5)
            r.top:SetPoint("TOPRIGHT", -8, -5)
            r.top:SetJustifyH("LEFT")
            r.top:SetWordWrap(false)

            r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.sub:SetPoint("BOTTOMLEFT", 8, 5)
            r.sub:SetPoint("BOTTOMRIGHT", -8, 5)
            r.sub:SetJustifyH("LEFT")
            r.sub:SetWordWrap(false)

            r:SetScript("OnClick", function(selfBtn)
                local it = selfBtn._item
                if not it then return end
                if MenuUtil and MenuUtil.CreateContextMenu then
                    MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                        root:CreateTitle(it.sender or "?")
                        root:CreateButton(L["Copy Message"], function()
                            if ns.UI and ns.UI.OpenCopyModal then
                                ns.UI:OpenCopyModal((it.sender or "?") .. ": " .. (it.text or ""), L["Copy Message"], L["Press Ctrl+C to copy this message."])
                            end
                        end)
                        if it.lookupKey and it.lookupKey ~= "" then
                            local isIgn = Store and Store.IsAccountIgnored and Store:IsAccountIgnored(it.lookupKey)
                            if isIgn then
                                root:CreateButton(L["Edit Account Ignore..."], function()
                                    SocialPanels:OpenAccountIgnoreModal(it.sender, it.lookupKey)
                                end)
                                root:CreateButton("|cff3fb950" .. L["Unblock"] .. "|r", function()
                                    if ns.UI and ns.UI.OpenConfirmModal then
                                        ns.UI:OpenConfirmModal({
                                            title = L["Unblock"],
                                            message = L["Are you sure you want to remove '%s' from your Account Ignore list?"]:format(it.sender or it.lookupKey),
                                            confirmText = L["Unblock"],
                                            confirmVariant = "danger",
                                            onConfirm = function()
                                                if Store and Store.RemoveAccountIgnore then
                                                    Store:RemoveAccountIgnore(it.lookupKey, true)
                                                end
                                            end,
                                        })
                                    end
                                end)
                            else
                                root:CreateButton(L["Account Ignore..."], function()
                                    SocialPanels:OpenAccountIgnoreModal(it.sender, it.lookupKey)
                                end)
                            end
                        end
                    end)
                end
            end)
            r:SetScript("OnEnter", function(selfBtn)
                local it = selfBtn._item
                if not (it and GameTooltip) then return end
                GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
                GameTooltip:SetText((it.sender or "?") .. " · " .. (it.channel or ""), 1, 0.9, 0.55)
                GameTooltip:AddLine(it.reason or "", 1.0, 0.45, 0.45, true)
                GameTooltip:AddLine(it.text or "", 0.9, 0.92, 0.96, true)
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
            return r
        end, function(r, item, idx, pal)
            r._item = item
            Theme:ApplyBackdrop(r, (idx % 2 == 1) and "row" or "rowAlt", pal)
            local tsStr = item.ts and item.ts > 0 and date("[%H:%M]", item.ts) or ""
            local tagCol = (item.filterType == "IGNORE") and "|cffff5555" or "|cffff9b3d"
            r.top:SetText("|cff9da7b5" .. tsStr .. "|r " .. tagCol .. "[" .. (item.reason or "") .. "]|r  |cffffffff" .. (item.sender or "?") .. "|r  |cff8ab4f8(" .. (item.channel or "") .. ")|r")
            r.sub:SetText(item.text or "")
            r.sub:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])
        end)
        scroll.container:SetAllPoints(listWrap)
        m.scroll = scroll

        local btnClose = Theme:CreateButton(m, 84, 24, L["Close"], "default")
        Theme:AutoFitButton(btnClose, 78, 14, 130)
        btnClose:SetPoint("BOTTOMRIGHT", -14, 12)
        btnClose:SetScript("OnClick", function() m:Hide() end)
        m.btnClose = btnClose

        local btnClear = Theme:CreateButton(m, 118, 24, L["Clear Log"], "danger")
        Theme:AutoFitButton(btnClear, 98, 16, 150)
        btnClear:SetPoint("BOTTOMLEFT", 14, 12)
        btnClear:SetScript("OnClick", function()
            if ns.UI and ns.UI.OpenConfirmModal then
                ns.UI:OpenConfirmModal({
                    title = L["Clear Log"],
                    message = L["Are you sure you want to clear the session filtered messages log?"],
                    confirmText = L["Clear"],
                    confirmVariant = "danger",
                    onConfirm = function()
                        if ns.Chat and ns.Chat.ClearFilteredChatLog then
                            ns.Chat:ClearFilteredChatLog()
                        end
                    end,
                })
            elseif ns.Chat and ns.Chat.ClearFilteredChatLog then
                ns.Chat:ClearFilteredChatLog()
            end
        end)
        m.btnClear = btnClear

        local btnManageIgn = Theme:CreateButton(m, 156, 24, L["Manage Account Ignores"], "default")
        Theme:AutoFitButton(btnManageIgn, 136, 16, 210)
        btnManageIgn:SetPoint("LEFT", btnClear, "RIGHT", 8, 0)
        btnManageIgn:SetScript("OnClick", function()
            m:Hide()
            if ns.NavigateToModule then
                ns:NavigateToModule("social", { socialFilter = "blocked" })
            end
        end)
        m.btnManageIgn = btnManageIgn

        function m:Refresh()
            local log = (ns.Chat and ns.Chat.GetFilteredChatLog) and ns.Chat:GetFilteredChatLog() or {}
            local total = (ns.Chat and ns.Chat.GetFilteredChatCount) and ns.Chat:GetFilteredChatCount() or #log
            local ignCnt = (Store and Store.GetAccountIgnoresCount) and Store:GetAccountIgnoresCount() or 0
            m.summaryLbl:SetText(string.format(L["Filtered this session: %d  ·  Account Ignores: %d"], total, ignCnt))
            m.scroll:SetData(log, L["No messages have been filtered this session."], false)
        end

        ns:On("CHAT_FILTERED_UPDATED", function()
            if m:IsShown() then m:Refresh() end
        end)
        ns:On("ACCOUNT_IGNORES_UPDATED", function()
            if m:IsShown() then m:Refresh() end
        end)

        filteredChatModal = m
    end

    local m = filteredChatModal
    Theme:PrepareTopOverlayModal(m, 855)
    Theme:ApplyBackdrop(m, "window")
    Theme:ApplyBackdrop(m.listWrap, "surface")
    Theme:StyleButton(m.topClose, "default")
    Theme:StyleButton(m.btnClose, "default")
    Theme:StyleButton(m.btnClear, "danger")
    Theme:StyleButton(m.btnManageIgn, "default")
    if m.helpBtn and m.helpBtn.RefreshTheme then m.helpBtn:RefreshTheme() end
    if m.scroll and m.scroll.RefreshTheme then m.scroll:RefreshTheme() end
    m:Refresh()
    Theme:SyncSubtreeLayers(m, 8)
    m:Show()
    if m.Raise then m:Raise() end
end

local function ResolveChatFavKey(item)
    if not item or (item.kind ~= "WHISPER" and item.kind ~= "BN_WHISPER") then
        return nil
    end
    local raw = nil
    if type(item.activeChar) == "string" and item.activeChar ~= "" and not item.activeChar:find("#", 1, true) then
        raw = item.activeChar
    elseif type(item.targetName) == "string" and item.targetName ~= "" and not item.targetName:find("#", 1, true) then
        raw = item.targetName
    elseif type(item.key) == "string" and item.key:sub(1, 2) == "w:" then
        raw = item.key:sub(3)
    end
    if not raw or raw == "" then
        return nil
    end
    local lk = Compat.ParseCharacterFields and Compat.ParseCharacterFields(raw)
    return lk or raw:lower()
end

local function IsChatThreadOnline(item)
    if not item then return false end
    local k = item.kind
    if k == "NOTES" or k == "MENTIONS" or k == "ROOM" or k == "GUILD" or k == "OFFICER" or k == "ALLIANCE" or k == "PARTY" or k == "RAID" or k == "INSTANCE_CHAT" or k == "LOCAL_SAY" or k == "LOCAL_YELL" then
        return true
    end
    local lk = ResolveChatFavKey(item)
    if lk and Store and Store.socialByLookup then
        local sRow = Store.socialByLookup[lk]
        if sRow and sRow.online == true then
            local bnetOnly = sRow.sources and sRow.sources.bnet == true and not sRow.sources.friend and not sRow.sources.guild
            if not bnetOnly or sRow.bnetState == "wow_forever" or sRow.bnetState == "wow_other" then
                return true
            end
        end
    end
    if item.bnetAccountID and Store and Store.socialDirectoryByKey then
        local bRow = Store.socialDirectoryByKey["bnet:" .. tostring(item.bnetAccountID)]
        if bRow and bRow.online == true and (bRow.bnetState == "wow_forever" or bRow.bnetState == "wow_other") then
            return true
        end
    end
    local grpTarget = item.activeChar or item.targetName or lk
    if grpTarget and Compat.IsInMyGroup and Compat.IsInMyGroup(grpTarget) then
        return true
    end
    if lk and ns.Watchlist and ns.Watchlist.GetEntry then
        local wl = ns.Watchlist:GetEntry(lk)
        if wl and wl.status == "online" then
            return true
        end
    end
    return false
end

local function MatchesChatTypeFilter(item, filterId)
    if not item then return false end
    if filterId == "pinned" then
        return item.pinned == true
    elseif filterId == "favorites" then
        local fk = ResolveChatFavKey(item)
        return (fk and Store and Store.IsSocialFavorite and Store:IsSocialFavorite(fk) == true) or false
    elseif filterId == "online" then
        return IsChatThreadOnline(item)
    elseif filterId == "offline" then
        return (item.kind == "WHISPER" or item.kind == "BN_WHISPER") and (not IsChatThreadOnline(item))
    end
    return true
end

local function FilterChatThreadsByType(filterId, forceIncludeOffline)
    local fId = filterId or "all"
    local baseFilter = (fId == "pinned" or fId == "favorites" or fId == "online" or fId == "offline") and "all" or fId
    local raw = (ns.Chat and ns.Chat.GetThreadsList) and ns.Chat:GetThreadsList(baseFilter) or {}
    local hideOff = (fId ~= "offline") and (not forceIncludeOffline)
        and (ns.db and ns.db.settings and ns.db.settings.chatShowOffline == false)
    local out = {}
    for i = 1, #raw do
        local th = raw[i]
        if MatchesChatTypeFilter(th, fId) then
            local isDirectTh = (th.kind == "WHISPER" or th.kind == "BN_WHISPER")
            if (not hideOff) or (not isDirectTh) or IsChatThreadOnline(th) or ((th.unread or 0) > 0) then
                out[#out + 1] = th
            end
        end
    end
    return out
end

local function FindNewestUnreadThread(threads)
    local best = nil
    local bestAt = -1
    if type(threads) ~= "table" then return nil end
    for i = 1, #threads do
        local th = threads[i]
        if th and (not th.muted) and ((th.unread or 0) > 0) then
            local at = tonumber(th.lastAt) or 0
            if (not best) or at > bestAt then
                best = th
                bestAt = at
            end
        end
    end
    return best
end

local function MapChatKindToBadgeTone(kind)
    if kind == "PARTY" or kind == "RAID" or kind == "INSTANCE_CHAT" then
        return "party"
    elseif kind == "GUILD" or kind == "OFFICER" or kind == "ALLIANCE" then
        return "guild"
    elseif kind == "ROOM" or kind == "PUB_CHANNEL" or kind == "GENERAL" then
        return "room"
    end
    return "whisper"
end

local function ThreadMatchesFilterIdForUnread(th, fid)
    if fid == "all" or fid == "unread" then
        return true
    elseif fid == "pinned" then
        return th.pinned == true
    elseif fid == "favorites" then
        local fk = ResolveChatFavKey(th)
        return (fk and Store and Store.IsSocialFavorite and Store:IsSocialFavorite(fk) == true) or false
    elseif fid == "online" then
        return IsChatThreadOnline(th)
    elseif fid == "offline" then
        return (th.kind == "WHISPER" or th.kind == "BN_WHISPER") and (not IsChatThreadOnline(th))
    elseif fid == "whispers" then
        return th.kind == "WHISPER" or th.kind == "BN_WHISPER" or th.kind == "NOTES"
    elseif fid == "guild" then
        return th.kind == "GUILD" or th.kind == "OFFICER"
    elseif fid == "group" then
        return th.kind == "PARTY" or th.kind == "RAID" or th.kind == "INSTANCE_CHAT"
    elseif fid == "alliance" then
        return th.kind == "ALLIANCE"
    elseif fid == "rooms" then
        return th.kind == "ROOM"
    elseif fid == "channels" then
        return th.kind == "ALLIANCE" or th.kind == "GENERAL" or th.kind == "PUB_CHANNEL" or th.kind == "LOCAL_SAY" or th.kind == "LOCAL_YELL"
    elseif fid == "mentions" then
        return th.kind == "MENTIONS" or th.hasMention == true
    end
    return false
end

local function CollectUnreadBadgeSummary(filterDefs)
    local allThreads = FilterChatThreadsByType("all", true)
    local totalUnread = 0
    local tones = {}
    local seenTones = {}
    local byFilter = {}
    if type(filterDefs) == "table" then
        for i = 1, #filterDefs do
            byFilter[filterDefs[i].id] = 0
        end
    end
    for i = 1, #allThreads do
        local th = allThreads[i]
        local u = (th and not th.muted) and (tonumber(th.unread) or 0) or 0
        if u > 0 then
            totalUnread = totalUnread + u
            local tone = MapChatKindToBadgeTone(th.kind)
            if not seenTones[tone] then
                seenTones[tone] = true
                tones[#tones + 1] = tone
            end
            if type(filterDefs) == "table" then
                for j = 1, #filterDefs do
                    local fid = filterDefs[j].id
                    if ThreadMatchesFilterIdForUnread(th, fid) then
                        byFilter[fid] = (byFilter[fid] or 0) + u
                    end
                end
            end
        end
    end
    return totalUnread, tones, byFilter
end

local function SetupChatThreadDragReorder(threadsScroll, panel)
    local vp = threadsScroll and threadsScroll.viewport
    if not vp then return end

    local dropLine = CreateFrame("Frame", nil, vp)
    dropLine:SetHeight(2)
    dropLine:SetFrameLevel((vp:GetFrameLevel() or 1) + 25)
    dropLine:Hide()
    local lineTex = dropLine:CreateTexture(nil, "OVERLAY", nil, 7)
    lineTex:SetAllPoints()
    lineTex:SetColorTexture(1.0, 0.84, 0.24, 1.0)
    local leftDot = dropLine:CreateTexture(nil, "OVERLAY", nil, 7)
    leftDot:SetSize(6, 6)
    leftDot:SetPoint("LEFT", dropLine, "LEFT", -2, 0)
    leftDot:SetColorTexture(1.0, 0.84, 0.24, 1.0)

    local dragWatch = CreateFrame("Frame", nil, vp)
    dragWatch:Hide()

    local function UpdateDropTarget()
        if not panel._dragThreadKey then return end
        local _, curY = GetCursorPosition()
        local scale = (vp.GetEffectiveScale and vp:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        local cy = curY / scale

        local bestRow, bestDist, bestAfter = nil, nil, false
        for _, row in ipairs(threadsScroll.rows or {}) do
            local it = row._item
            if row:IsShown() and it and not it._isChatSectionHeader and it.pinned == true then
                local top = row:GetTop()
                local bot = row:GetBottom()
                if top and bot then
                    local mid = (top + bot) * 0.5
                    local dist = math.abs(cy - mid)
                    if not bestDist or dist < bestDist then
                        bestDist = dist
                        bestRow = row
                        bestAfter = (cy < mid)
                    end
                end
            end
        end

        if bestRow and bestRow._item then
            panel._dragDropTargetKey = bestRow._item.key
            panel._dragDropAfter = bestAfter
            dropLine:ClearAllPoints()
            if bestAfter then
                dropLine:SetPoint("LEFT", bestRow, "BOTTOMLEFT", 6, 0)
                dropLine:SetPoint("RIGHT", bestRow, "BOTTOMRIGHT", -6, 0)
            else
                dropLine:SetPoint("LEFT", bestRow, "TOPLEFT", 6, 0)
                dropLine:SetPoint("RIGHT", bestRow, "TOPRIGHT", -6, 0)
            end
            dropLine:SetFrameLevel((bestRow:GetFrameLevel() or 2) + 8)
            dropLine:Show()
        else
            panel._dragDropTargetKey = nil
            dropLine:Hide()
        end
    end

    function panel._EndPinnedDrag()
        dragWatch:SetScript("OnUpdate", nil)
        dragWatch:Hide()
        dropLine:Hide()
        local srcKey = panel._dragThreadKey
        local tgtKey = panel._dragDropTargetKey
        local insAfter = panel._dragDropAfter == true
        panel._dragThreadKey = nil
        panel._dragDropTargetKey = nil
        panel._dragDropAfter = false
        panel._justDraggedAt = (GetTime and GetTime()) or 0
        if srcKey and tgtKey and srcKey ~= tgtKey and ns.Chat and ns.Chat.MovePinnedThread then
            ns.Chat:MovePinnedThread(srcKey, tgtKey, insAfter)
        elseif panel.Refresh then
            panel:Refresh(false)
        end
    end

    function panel._BeginPinnedDrag(row)
        if not (row and row._item and row._item.pinned == true and not row._item._isChatSectionHeader) then
            return
        end
        panel._dragThreadKey = row._item.key
        panel._dragDropTargetKey = nil
        panel._dragDropAfter = false
        UpdateDropTarget()
        dragWatch:Show()
        dragWatch:SetScript("OnUpdate", function()
            if not panel._dragThreadKey then
                dragWatch:SetScript("OnUpdate", nil)
                dragWatch:Hide()
                dropLine:Hide()
                return
            end
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                panel._EndPinnedDrag()
                return
            end
            UpdateDropTarget()
        end)
    end
end

function SocialPanels:CreateChatPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel._filter = "all"
    panel._compactHideThreads = false

    local topBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    topBar:SetPoint("TOPLEFT", 0, 0)
    topBar:SetPoint("TOPRIGHT", 0, 0)
    topBar:SetHeight(34)
    panel.topBar = topBar

    local filterDefs = {
        { id = "all", label = L["All"] },
        { id = "unread", label = L["Unread"] },
        { id = "pinned", label = L["Pinned"] },
        { id = "favorites", label = L["Favorites"] },
        { id = "online", label = L["Online"] },
        { id = "offline", label = L["Offline"] },
        { id = "whispers", label = L["Whispers"] },
        { id = "guild", label = L["Guild"] },
        { id = "group", label = L["Group"] },
        { id = "alliance", label = L["Alliance"] },
        { id = "rooms", label = L["Rooms"] },
        { id = "channels", label = L["Channels"] },
        { id = "mentions", label = L["Mentions"] },
    }
    local function GetFilterLabel(id)
        for _, def in ipairs(filterDefs) do
            if def.id == id then return def.label end
        end
        return L["All"]
    end

    local btnFilterMenu = Theme:CreateButton(topBar, 114, 22, L["All"], "default")
    local dropArrow = btnFilterMenu:CreateTexture(nil, "OVERLAY")
    dropArrow:SetSize(13, 13)
    dropArrow:SetPoint("RIGHT", btnFilterMenu, "RIGHT", -5, 0)
    dropArrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    dropArrow:SetVertexColor(0.96, 0.80, 0.34, 1)
    btnFilterMenu._dropArrow = dropArrow
    if btnFilterMenu.label then
        btnFilterMenu.label:ClearAllPoints()
        btnFilterMenu.label:SetPoint("LEFT", btnFilterMenu, "LEFT", 8, 0)
        btnFilterMenu.label:SetPoint("RIGHT", dropArrow, "LEFT", -4, 0)
        btnFilterMenu.label:SetJustifyH("LEFT")
        btnFilterMenu.label:SetWordWrap(false)
    end

    local filterUnreadBadge = Theme:CreateCounterBadge(topBar, {
        height = 19,
        maxNum = 99,
        haloAlpha = 0.50,
        minFontSize = 13,
        maxFontSize = 16,
    })
    filterUnreadBadge:SetPoint("CENTER", btnFilterMenu, "TOPRIGHT", -2, -1)
    filterUnreadBadge:SetFrameLevel((btnFilterMenu:GetFrameLevel() or 8) + 12)
    filterUnreadBadge:Hide()
    panel._filterUnreadBadge = filterUnreadBadge

    local btnFilterUnreadHit = CreateFrame("Button", nil, topBar)
    btnFilterUnreadHit:SetPoint("CENTER", filterUnreadBadge, "CENTER", 0, 0)
    btnFilterUnreadHit:SetSize(22, 22)
    btnFilterUnreadHit:SetFrameLevel((filterUnreadBadge:GetFrameLevel() or 20) + 4)
    btnFilterUnreadHit:Hide()

    local function OpenNewestUnreadForFilter(targetFilter)
        local fId = targetFilter or panel._filter or "all"
        local list = FilterChatThreadsByType(fId, true)
        local best = FindNewestUnreadThread(list)
        local chosenFilter = fId
        if not best and fId ~= "all" and targetFilter == nil then
            list = FilterChatThreadsByType("all", true)
            best = FindNewestUnreadThread(list)
            if best then
                chosenFilter = "all"
            end
        end
        panel._filter = chosenFilter
        if best and ns.Chat and ns.Chat.SetActiveThread then
            ns.Chat:SetActiveThread(best.key, false)
        elseif list[1] and ns.Chat and ns.Chat.SetActiveThread then
            local activeKey = ns.Chat.activeThreadKey
            local foundActive = false
            for i = 1, #list do
                if list[i].key == activeKey then
                    foundActive = true
                    break
                end
            end
            if not foundActive then
                ns.Chat:SetActiveThread(list[1].key, false)
            end
        end
        panel:Refresh(true)
    end

    local function SyncFilterDropdownVisual()
        local lbl = GetFilterLabel(panel._filter)
        Theme:SetButtonText(btnFilterMenu, lbl)
        local tw = 44
        if btnFilterMenu.label then
            tw = (btnFilterMenu.label.GetUnboundedStringWidth and btnFilterMenu.label:GetUnboundedStringWidth())
                or (btnFilterMenu.label.GetStringWidth and btnFilterMenu.label:GetStringWidth()) or 44
        end
        local wantW = math.max(92, math.min(168, math.ceil(tw + 30)))
        if math.abs((btnFilterMenu:GetWidth() or 0) - wantW) >= 1 then
            btnFilterMenu:SetWidth(wantW)
        end
        btnFilterMenu._scAutoFitW = wantW
        if btnFilterMenu._dropArrow then
            if panel._filter ~= "all" then
                btnFilterMenu._dropArrow:SetVertexColor(0.98, 0.80, 0.24, 1)
            else
                btnFilterMenu._dropArrow:SetVertexColor(0.84, 0.88, 0.94, 0.95)
            end
        end
        Theme:SetButtonActive(btnFilterMenu, panel._filter ~= "all", "default")
    end

    btnFilterMenu:SetPoint("TOPLEFT", topBar, "TOPLEFT", 8, -6)
    btnFilterMenu:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btnFilterMenu:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        local totalUnread = panel._lastTotalUnread or 0
        GameTooltip:SetOwner(selfBtn, "ANCHOR_BOTTOMLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(string.format(L["Filter: %s"], GetFilterLabel(panel._filter)), 1, 0.85, 0.28)
        GameTooltip:AddLine(L["Conversation Type"], 0.82, 0.88, 0.96, true)
        if totalUnread > 0 then
            GameTooltip:AddLine(string.format(L["Click badge: open next unread conversation (%d remaining)"], totalUnread), 0.35, 0.95, 0.55, true)
        end
        GameTooltip:Show()
    end)
    btnFilterMenu:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    btnFilterMenu:SetScript("OnClick", function(self, mouseBtn)
        if mouseBtn == "RightButton" and (panel._lastTotalUnread or 0) > 0 then
            OpenNewestUnreadForFilter(nil)
            return
        end
        if MenuUtil and MenuUtil.CreateContextMenu then
            local totalU, _, byFilter = CollectUnreadBadgeSummary(filterDefs)
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(L["Conversation Type"])
                if totalU > 0 then
                    root:CreateButton("|cff47ef66" .. string.format(L["Open latest unread (%d)"], totalU) .. "|r", function()
                        OpenNewestUnreadForFilter(nil)
                    end)
                    root:CreateDivider()
                end
                local showGuildChatFilt = (not Compat or not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("clan")
                for _, def in ipairs(filterDefs) do
                    if (def.id ~= "guild" and def.id ~= "alliance") or showGuildChatFilt then
                        local uCnt = byFilter[def.id] or 0
                        local optText = (uCnt > 0 and def.id ~= "unread")
                            and (def.label .. " |cff47ef66(" .. tostring(uCnt) .. ")|r")
                            or def.label
                        root:CreateRadio(optText, function()
                            return panel._filter == def.id
                        end, function()
                            OpenNewestUnreadForFilter(def.id)
                        end)
                    end
                end
                root:CreateDivider()
                root:CreateCheckbox(L["Show Offline"], function()
                    return not (ns.db and ns.db.settings and ns.db.settings.chatShowOffline == false)
                end, function()
                    if ns.db and ns.db.settings then
                        ns.db.settings.chatShowOffline = (ns.db.settings.chatShowOffline == false)
                    end
                    panel:Refresh(true)
                end)
            end)
        else
            local idx = 1
            for i, def in ipairs(filterDefs) do
                if def.id == panel._filter then
                    idx = (i % #filterDefs) + 1
                    break
                end
            end
            OpenNewestUnreadForFilter(filterDefs[idx].id)
        end
    end)

    btnFilterUnreadHit:SetScript("OnClick", function()
        OpenNewestUnreadForFilter(nil)
    end)
    btnFilterUnreadHit:SetScript("OnEnter", function(selfHit)
        if not GameTooltip then return end
        local n = panel._lastTotalUnread or 0
        if n <= 0 then return end
        GameTooltip:SetOwner(selfHit, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Unread"] .. " (" .. tostring(n) .. ")", 0.35, 0.95, 0.55)
        GameTooltip:AddLine(string.format(L["Click badge: open next unread conversation (%d remaining)"], n), 0.92, 0.94, 0.98, true)
        GameTooltip:Show()
    end)
    btnFilterUnreadHit:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local btnChatOffline = Theme:CreateButton(topBar, 24, 22, "", "default")
    Theme:ApplyOnlineOfflineOrb(btnChatOffline, not (ns.db and ns.db.settings and ns.db.settings.chatShowOffline == false), 24, 22)
    btnChatOffline:SetPoint("LEFT", btnFilterMenu, "RIGHT", 10, 0)
    btnChatOffline:SetScript("OnClick", function()
        if ns.db and ns.db.settings then
            ns.db.settings.chatShowOffline = (ns.db.settings.chatShowOffline == false)
        end
        panel:Refresh(true)
    end)
    panel.btnChatOffline = btnChatOffline

    local btnUnreadQuick = Theme:CreateButton(topBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(btnUnreadQuick, 24, 22, "Interface\\AddOns\\SocialCentral\\Media\\bell-on", {
        size = 14,
        toggle = true,
        active = false,
        activeColor = { 1.0, 0.40, 0.35 },
        tooltipFn = function(selfBtn)
            local n = selfBtn._unreadCount or 0
            local t = L["Unread"] .. (n > 0 and (" (" .. tostring(n) .. ")") or "")
            local d = (n > 0) and string.format(L["Click badge: open next unread conversation (%d remaining)"], n)
                or L["Show all conversations"]
            return t, d
        end,
    })
    btnUnreadQuick:SetPoint("LEFT", btnChatOffline, "RIGHT", 4, 0)
    btnUnreadQuick:SetScript("OnClick", function()
        if (panel._lastTotalUnread or 0) > 0 then
            OpenNewestUnreadForFilter(nil)
        else
            panel._filter = (panel._filter == "unread") and "all" or "unread"
            panel:Refresh(true)
        end
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
        -8,
        {
            target = topBar,
            steps = {
                {
                    title = L["Conversation Type"],
                    tag = "1/4 · " .. L["Filters"],
                    text = L["Choose a conversation type (All, Unread, Pinned, Favorites, Online, Offline, Whispers, Guild, Group, or Rooms), or click the counter badge to open each newest unread chat."],
                    target = btnFilterMenu,
                },
                {
                    title = L["Conversation List"],
                    tag = "2/4 · " .. L["Threads"],
                    text = L["Select any conversation on the left, drag threads to reorder, or right-click to Pin, Mute alerts, Archive, or open Player Actions."],
                    target = function() return panel._leftCard or panel end,
                },
                {
                    title = L["Help: Conversations & Private Rooms"],
                    tag = "3/4 · " .. L["Messages"],
                    text = L["Read full history with timestamps, level tags, item links, and interactive copy/reply actions without leaving SocialCentral."],
                    target = function() return panel._rightCard or panel end,
                },
                {
                    title = L["Safe Chat Composer"],
                    tag = "4/4 · " .. L["Send"],
                    text = L["Send direct messages inside Private Rooms & addon peers, or use Quick Official Send / prefilled WoW chat bar safely on whispers and channels."],
                    target = function() return panel._composer or panel end,
                },
            },
        }
    )
    panel._scHelpBtn = helpTop

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
            root:CreateButton(L["Mentions & Keywords Radar..."], function()
                SocialPanels:OpenMentionKeywordsModal()
            end)
            local filtCnt = (ns.Chat.GetFilteredChatCount and ns.Chat:GetFilteredChatCount()) or 0
            local filtLbl = (filtCnt > 0) and (L["Filtered Chat Log"] .. " (" .. filtCnt .. ")") or L["Filtered Chat Log"]
            root:CreateButton(filtLbl, function()
                SocialPanels:OpenFilteredChatModal()
            end)
            root:CreateButton(L["Account Ignore..."], function()
                SocialPanels:OpenAccountIgnoreModal()
            end)
            if activeKey and activeThread then
                root:CreateDivider()
                root:CreateButton(L["Clear Active Chat"], function()
                    local targetKey = activeKey
                    local title = activeThread.title or activeKey
                    local msg = L["Are you sure you want to clear all messages in '%s'?"]:format(title)
                    if ns.UI and ns.UI.OpenConfirmModal then
                        ns.UI:OpenConfirmModal({
                            title = L["Clear Active Chat"],
                            message = msg,
                            confirmText = L["Clear"],
                            onConfirm = function()
                                if ns.Chat and ns.Chat.ClearHistory then
                                    ns.Chat:ClearHistory(targetKey)
                                end
                            end,
                        })
                    elseif ns.Chat and ns.Chat.ClearHistory then
                        ns.Chat:ClearHistory(targetKey)
                    end
                end)
                if ns.Chat.CanDeleteThread and ns.Chat:CanDeleteThread(activeKey) and OpenDeleteThreadModal then
                    root:CreateButton("|cfff54747" .. L["Delete Conversation"] .. "|r", function()
                        OpenDeleteThreadModal(activeKey, activeThread.title or activeKey)
                    end)
                end
            end
        end)
    end)

    local btnRoomMenu = Theme:CreateButton(topBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(btnRoomMenu, 24, 22, "Interface\\GroupFrame\\UI-Group-LeaderIcon", {
        size = 15,
        title = L["+ Room"],
        desc = L["Create a Private Addon Room for synced group or friend chats."],
    })
    btnRoomMenu:SetScript("OnClick", OpenCreateRoomModal)

    local btnNewChat = Theme:CreateButton(topBar, 24, 22, "", "primary")
    Theme:ConfigureIconButton(btnNewChat, 24, 22, "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", {
        size = 14,
        color = { 0.45, 0.95, 0.55 },
        title = L["New 1-on-1 Chat"],
        desc = L["Open a 1-on-1 conversation with a friend, guildmate, target, or character name."],
    })
    btnNewChat:SetScript("OnClick", OpenNewDirectChatModal)

    local function ReflowChatTopBar(widthHint)
        local topW = math.floor(((widthHint and widthHint > 40 and widthHint) or topBar:GetWidth() or panel:GetWidth() or 500) + 0.5)
        local compactTop = topBar._scCompactTop and (topW < 458) or (topW < 442)
        if topBar._scCompactTop == nil then
            compactTop = (topW < 450)
        end
        topBar._scCompactTop = compactTop
        local showUnread = btnUnreadQuick:IsShown()

        local bwFilt = math.floor((btnFilterMenu._scAutoFitW or btnFilterMenu:GetWidth() or 104) + 0.5)
        local bwOff = math.floor((btnChatOffline:GetWidth() or 24) + 0.5)
        local bwUnread = showUnread and math.floor((btnUnreadQuick:GetWidth() or 24) + 0.5) or 0
        local bwRoom = math.floor((btnRoomMenu:GetWidth() or 24) + 0.5)
        local bwNew = math.floor((btnNewChat:GetWidth() or 24) + 0.5)
        local leftW = 8 + bwFilt + 10 + bwOff + (showUnread and (4 + bwUnread) or 0)
        local rightW = 8 + 18 + 4 + 24 + 4 + bwRoom + 4 + bwNew
        local twoRows = (topW > 120) and ((leftW + rightW + 8) > topW)
        topBar._scTwoRows = twoRows

        local sig = topW .. ":" .. (compactTop and 1 or 0) .. ":" .. (twoRows and 1 or 0)
            .. ":" .. bwFilt .. ":" .. bwOff .. ":" .. bwUnread .. ":" .. bwRoom .. ":" .. bwNew .. ":" .. (showUnread and 1 or 0)
        if topBar._scChatTopSig == sig then
            return
        end
        topBar._scChatTopSig = sig

        btnFilterMenu:ClearAllPoints()
        btnFilterMenu:SetPoint("TOPLEFT", topBar, "TOPLEFT", 8, -6)
        btnChatOffline:ClearAllPoints()
        btnChatOffline:SetPoint("LEFT", btnFilterMenu, "RIGHT", 10, 0)
        btnUnreadQuick:ClearAllPoints()
        btnUnreadQuick:SetPoint("LEFT", btnChatOffline, "RIGHT", 4, 0)

        helpTop:ClearAllPoints()
        helpTop:SetPoint("TOPRIGHT", topBar, "TOPRIGHT", -8, -8)

        btnManageMenu:ClearAllPoints()
        btnRoomMenu:ClearAllPoints()
        btnNewChat:ClearAllPoints()

        if twoRows then
            if math.abs((topBar:GetHeight() or 0) - 60) >= 1 then
                topBar:SetHeight(60)
            end
            btnManageMenu:SetPoint("TOPRIGHT", topBar, "TOPRIGHT", -8, -32)
            btnRoomMenu:SetPoint("RIGHT", btnManageMenu, "LEFT", -4, 0)
            btnNewChat:SetPoint("RIGHT", btnRoomMenu, "LEFT", -4, 0)
        else
            if math.abs((topBar:GetHeight() or 0) - 34) >= 1 then
                topBar:SetHeight(34)
            end
            btnManageMenu:SetPoint("RIGHT", helpTop, "LEFT", -4, 0)
            btnRoomMenu:SetPoint("RIGHT", btnManageMenu, "LEFT", -4, 0)
            btnNewChat:SetPoint("RIGHT", btnRoomMenu, "LEFT", -4, 0)
        end
        if not topBar._legendBtn then
            topBar._legendBtn = Theme:CreateLegendTag(topBar, function()
                return {
                    { tex = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", title = L["Conversation Type"] },
                    {
                        tex = (btnChatOffline._scShowOffline and (FRIENDS_TEXTURE_DND or "Interface\\FriendsFrame\\StatusIcon-DnD") or (FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online")),
                        title = L["Show Offline"],
                        desc = L["Green = Online Only · Red = Showing Offline"],
                    },
                    { tex = "Interface\\AddOns\\SocialCentral\\Media\\bell-on", title = L["Unread"] },
                    { tex = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", title = L["New 1-on-1 Chat"] },
                    { tex = "Interface\\GroupFrame\\UI-Group-LeaderIcon", title = L["+ Room"] },
                    { tex = "Interface\\Buttons\\UI-OptionsButton", title = L["More"] },
                    { title = "|cffff7fff" .. L["Whisper"] .. "|r · |cff7aaeff" .. L["Group"] .. "|r · |cffff8a2e" .. L["Raid"] .. "|r · |cff47ef66" .. L["Guild"] .. "|r · |cff1ad1ffBNet|r · |cffbd80ff" .. L["Private Rooms"] .. "|r", desc = L["Chat Colors"] },
                    { title = "|cffffd24d*|r · |cff3fb950[SC]|r · |TInterface\\ChatFrame\\UI-ChatIcon-BattleNet:12:12:0:0|t", desc = L["Favorite · SocialCentral · Battle.net"] },
                }
            end)
        end
        if topBar._legendBtn then
            local legW = math.floor((topBar._legendBtn:GetWidth() or 68) + 0.5)
            if (not twoRows) and (topW - leftW - rightW) >= (legW + 16) then
                topBar._legendBtn:ClearAllPoints()
                topBar._legendBtn:SetPoint("RIGHT", btnNewChat, "LEFT", -8, 0)
                topBar._legendBtn:Show()
            else
                topBar._legendBtn:Hide()
            end
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

    local invDecline = Theme:CreateButton(inviteBar, 24, 20, "", "danger")
    Theme:ConfigureIconButton(invDecline, 24, 20, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", {
        size = 13,
        color = { 1.0, 0.45, 0.45 },
        title = L["Decline"],
    })
    invDecline:SetPoint("RIGHT", -8, 0)
    invDecline:SetScript("OnClick", function(selfBtn)
        if selfBtn._invId and ns.Chat then ns.Chat:DeclineRoomInvite(selfBtn._invId) end
    end)
    local invAccept = Theme:CreateButton(inviteBar, 24, 20, "", "primary")
    Theme:ConfigureIconButton(invAccept, 24, 20, "Interface\\RAIDFRAME\\ReadyCheck-Ready", {
        size = 14,
        title = L["Accept"],
    })
    invAccept:SetPoint("RIGHT", invDecline, "LEFT", -6, 0)
    invAccept:SetScript("OnClick", function(selfBtn)
        if selfBtn._invId and ns.Chat then ns.Chat:AcceptRoomInvite(selfBtn._invId) end
    end)
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
            Theme:PrepareTopOverlayModal(m, 850)
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
            m.topCloseBtn = topCloseBtn

            m.helpBtn = AddHelp(
                m,
                topCloseBtn,
                L["Help: Delete Conversation"],
                L["Permanently deletes this conversation's local message history stored on your account."],
                L["Type DELETE in the confirmation box and click Delete to remove this thread, or Cancel to keep it."],
                "RIGHT",
                "LEFT",
                -6,
                0,
                { target = m }
            )
            if m.helpBtn then
                title:ClearAllPoints()
                title:SetPoint("TOPLEFT", 16, -14)
                title:SetPoint("TOPRIGHT", m.helpBtn, "TOPLEFT", -6, -4)
            end

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
            Theme:AutoFitButton(btnConfirm, 96, 16, 150)
            btnConfirm:SetPoint("BOTTOMRIGHT", -16, 14)
            btnConfirm:SetEnabled(false)
            m.btnConfirm = btnConfirm

            local btnCancel = Theme:CreateButton(m, 90, 24, L["Cancel"], "default")
            Theme:AutoFitButton(btnCancel, 80, 14, 130)
            btnCancel:SetPoint("RIGHT", btnConfirm, "LEFT", -8, 0)
            btnCancel:SetScript("OnClick", function()
                input:ClearFocus()
                m:Hide()
            end)
            m.btnCancel = btnCancel

            local function IsWordMatched()
                local raw = (input:GetText() or ""):gsub("^%s*(.-)%s*$", "%1"):upper()
                local targetWord = (L["DELETE"] or "DELETE"):upper()
                return raw == targetWord
            end

            input:HookScript("OnTextChanged", function()
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
        Theme:PrepareTopOverlayModal(deleteThreadModal, 850)
        Theme:ApplyBackdrop(deleteThreadModal, "window")
        if deleteThreadModal.topCloseBtn then Theme:StyleButton(deleteThreadModal.topCloseBtn, "default") end
        if deleteThreadModal.btnConfirm then Theme:StyleButton(deleteThreadModal.btnConfirm, "danger") end
        if deleteThreadModal.btnCancel then Theme:StyleButton(deleteThreadModal.btnCancel, "default") end
        deleteThreadModal.desc:SetText(string.format(
            L["Are you sure you want to permanently delete the conversation with \"%s\"?\n\nType %s to confirm:"],
            threadTitle or threadKey,
            "|cffffd24d" .. confirmWord .. "|r"
        ))
        deleteThreadModal.input:SetText("")
        deleteThreadModal.btnConfirm:SetEnabled(false)
        Theme:SyncSubtreeLayers(deleteThreadModal, 8)
        deleteThreadModal:Show()
        if deleteThreadModal.Raise then deleteThreadModal:Raise() end
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

        if Theme and Theme.CreateCounterBadge then
            r.unreadBadge = Theme:CreateCounterBadge(r, {
                height = 22,
                maxNum = 99,
                haloAlpha = 0.25,
                noPulse = true,
                minFontSize = 14,
                maxFontSize = 16,
                fontScaleOffset = 0,
            })
            r.unreadBadge:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        else
            r.unreadBadge = CreateFrame("Frame", nil, r, "BackdropTemplate")
            r.unreadBadge:SetSize(22, 22)
            r.unreadBadge:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.unreadBadge:EnableMouse(false)
            if r.unreadBadge.SetBackdrop then
                r.unreadBadge:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = 1,
                })
                r.unreadBadge:SetBackdropColor(0.84, 0.14, 0.18, 1.0)
                r.unreadBadge:SetBackdropBorderColor(0.08, 0.08, 0.10, 1.0)
            end
            r.unreadBadge.text = r.unreadBadge:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            if Theme and Theme.ApplyReadableCounterFont then
                Theme:ApplyReadableCounterFont(r.unreadBadge.text, 14, 16, 0, true)
            end
            r.unreadBadge.text:SetPoint("CENTER", 0, 0)
            r.unreadBadge.text:SetTextColor(1, 1, 1)
            r.unreadBadge:Hide()
        end

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

        r:RegisterForDrag("LeftButton")
        r:SetScript("OnDragStart", function(selfBtn)
            if selfBtn._item and selfBtn._item.pinned == true and not selfBtn._item._isChatSectionHeader and panel._BeginPinnedDrag then
                panel._BeginPinnedDrag(selfBtn)
            end
        end)
        r:SetScript("OnDragStop", function()
            if panel._EndPinnedDrag then
                panel._EndPinnedDrag()
            end
        end)
        r:HookScript("OnHide", function()
            if panel._dragThreadKey and panel._EndPinnedDrag then
                panel._EndPinnedDrag()
            end
        end)

        r:SetScript("OnClick", function(selfBtn, mouseBtn)
            if panel._dragThreadKey or (panel._justDraggedAt and GetTime and (GetTime() - panel._justDraggedAt) < 0.08) then
                return
            end
            if not (r._item and ns.Chat) then return end
            if r._item._isChatSectionHeader then
                local sk = r._item.sectionKey
                if sk and panel._collapsedSections then
                    panel._collapsedSections[sk] = not (panel._collapsedSections[sk] == true)
                end
                panel:Refresh(false)
                return
            end
            if mouseBtn == "RightButton" then
                if MenuUtil and MenuUtil.CreateContextMenu then
                    local key = r._item.key
                    local favKey = ResolveChatFavKey(r._item)
                    MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                        root:CreateTitle(r._item.title or key)
                        if key ~= "notes:self" and ns.Chat.ToggleThreadPinned then
                            local isPinned = ns.Chat:IsThreadPinned(key)
                            root:CreateButton(isPinned and L["Unpin Conversation"] or L["Pin Conversation"], function()
                                ns.Chat:ToggleThreadPinned(key)
                            end)
                        end
                        if key ~= "notes:self" and key ~= "mentions:radar" and ns.Chat.ToggleQuickReplyPinned then
                            local qrPinned = ns.Chat.IsQuickReplyPinned and ns.Chat:IsQuickReplyPinned(key) == true
                            root:CreateButton(qrPinned and L["Unpin from Quick Reply"] or L["Pin in Quick Reply"], function()
                                ns.Chat:ToggleQuickReplyPinned(key)
                            end)
                        end
                        if favKey and Store and Store.IsSocialFavorite and Store.ToggleSocialFavorite then
                            local isFav = Store:IsSocialFavorite(favKey)
                            local starMark = Compat.FavoriteStarMarkup and Compat.FavoriteStarMarkup(12) or ""
                            root:CreateButton(isFav and (starMark .. L["Unfavorite"]) or L["Favorite"], function()
                                Store:ToggleSocialFavorite(favKey)
                                panel:Refresh(false)
                            end)
                        end
                        if ns.Chat.PopulateThreadMuteMenu then
                            local muteSub = root:CreateButton(L["Silence Notifications"])
                            ns.Chat:PopulateThreadMuteMenu(muteSub, key, r._item.title or key)
                        else
                            local isMuted = ns.Chat:IsThreadMuted(key)
                            root:CreateButton(isMuted and L["Unmute Conversation"] or L["Mute Conversation"], function()
                                ns.Chat:ToggleThreadMuted(key)
                            end)
                        end
                        if (r._item.unread or 0) > 0 then
                            root:CreateButton(L["Mark Read"], function()
                                ns.Chat:MarkThreadRead(key)
                            end)
                        elseif key ~= "notes:self" and ns.Chat.MarkThreadUnread then
                            root:CreateButton(L["Mark Unread"], function()
                                ns.Chat:MarkThreadUnread(key)
                            end)
                        end
                        root:CreateButton(L["Clear"], function()
                            local threadTitle = r._item and r._item.title or key
                            if ns.UI and ns.UI.OpenConfirmModal then
                                ns.UI:OpenConfirmModal({
                                    title = L["Clear"],
                                    message = L["Are you sure you want to clear all messages in '%s'?"]:format(threadTitle),
                                    confirmText = L["Clear"],
                                    onConfirm = function()
                                        if ns.Chat and ns.Chat.ClearHistory then
                                            ns.Chat:ClearHistory(key)
                                        end
                                    end,
                                })
                            elseif ns.Chat and ns.Chat.ClearHistory then
                                ns.Chat:ClearHistory(key)
                            end
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
            if it._isChatSectionHeader then
                GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(it.sectionLabel or "", 1.0, 0.84, 0.28)
                if it.isPinnedGroup then
                    GameTooltip:AddLine(string.format("%d", it.totalCount or 0), 0.72, 0.88, 1.0)
                else
                    GameTooltip:AddLine(string.format(L["%d online / %d total"], it.onlineCount or 0, it.totalCount or 0), 0.72, 0.88, 1.0)
                end
                GameTooltip:AddLine(L["Click: Expand / Collapse"], 0.45, 0.85, 1.0)
                GameTooltip:Show()
                return
            end
            GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
            GameTooltip:SetText(it.title or it.key or "?", 1, 1, 1)
            local kindNames = {
                WHISPER = L["WoW Whisper (/w)"],
                BN_WHISPER = "Battle.net",
                ROOM = L["Addon Private Room"],
                NOTES = L["Personal Notes"],
                MENTIONS = L["Mentions & Keywords Radar"],
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
            local st, stMsg
            if ns.Chat and ns.Chat.GetThreadAvailabilityStatus then
                st, stMsg = ns.Chat:GetThreadAvailabilityStatus(it.key)
            end
            if st then
                local stTag = (st == "DND") and L["DND"] or L["AFK"]
                local stFull = (stMsg and stMsg ~= "") and (stTag .. ": " .. stMsg) or stTag
                GameTooltip:AddLine(stFull, 1.0, 0.65, 0.25, true)
            end
            if it.pinned == true then
                GameTooltip:AddLine(L["Drag up or down to reorder pinned conversations."], 0.55, 0.85, 1.0, true)
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
        if item._isChatSectionHeader then
            if r._hadUnreadBorder then
                r._scBackdropSig = nil
                r._hadUnreadBorder = false
            end
            Theme:ApplyBackdrop(r, "surface", pal)
            if r.selBar then
                if item.sectionKey == "__pinned" or item.sectionKey == "__fav" then
                    r.selBar:SetColorTexture(1.0, 0.78, 0.24, 0.95)
                elseif item.sectionKey == "__guild" then
                    r.selBar:SetColorTexture(0.25, 0.82, 0.45, 0.92)
                elseif item.sectionKey == "__offline" then
                    r.selBar:SetColorTexture(0.45, 0.50, 0.58, 0.70)
                else
                    r.selBar:SetColorTexture(0.32, 0.74, 0.98, 0.92)
                end
                r.selBar:Show()
            end
            if r.unreadDot then r.unreadDot:Hide() end
            if r.kindIcon then r.kindIcon:Hide() end
            if r.scDot then r.scDot:Hide() end
            if r.unreadBadge then
                if r.unreadBadge.SetCount then r.unreadBadge:SetCount(0) else r.unreadBadge:Hide() end
            end
            r.title:ClearAllPoints()
            r.title:SetPoint("LEFT", r, "LEFT", 12, 0)
            r.title:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.sub:ClearAllPoints()
            r.sub:SetPoint("BOTTOMLEFT", 12, 4)
            r.sub:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            local arrow = item.isCollapsed and "|cffffd24d[+]|r " or "|cffffd24d[-]|r "
            local cntStr = (item.isPinnedGroup or item.sectionKey == "__online" or item.sectionKey == "__offline")
                and string.format(" |cff9da7b5(%d)|r", item.totalCount or 0)
                or string.format(" |cff9da7b5(%d/%d)|r", item.onlineCount or 0, item.totalCount or 0)
            r.title:SetAlpha(1.0)
            r.title:SetText(arrow .. (item.sectionLabel or "") .. cntStr)
            r.sub:SetAlpha(1.0)
            r.sub:SetText("")
            r.sub:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])
            return
        end
        if r.kindIcon then r.kindIcon:Show() end
        local isSel = ns.Chat and ns.Chat.activeThreadKey == item.key
        local hasUnread = (not item.muted and item.unread and item.unread > 0)
        if r._hadUnreadBorder and not hasUnread then
            r._scBackdropSig = nil
        end
        Theme:ApplyBackdrop(r, (isSel or hasUnread) and "surface" or ((idx % 2 == 1) and "row" or "rowAlt"), pal)
        if not r._scRowHoverTex then
            local rh = r:CreateTexture(nil, "HIGHLIGHT")
            rh:SetAllPoints()
            rh:SetColorTexture(1, 0.94, 0.78, 0.06)
            r._scRowHoverTex = rh
        end
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
            local rowTone = (Theme and Theme.GetChatToneForKind) and Theme:GetChatToneForKind(item.kind) or "whisper"
            if r.unreadBadge.SetCount then
                r.unreadBadge:SetCount(hasUnread and (item.unread or 0) or 0, rowTone)
            elseif hasUnread then
                local uCount = item.unread or 0
                if Theme and Theme.ApplyReadableCounterFont then
                    Theme:ApplyReadableCounterFont(r.unreadBadge.text, 14, 16, 0, true)
                end
                r.unreadBadge.text:SetText(uCount > 99 and "99+" or tostring(uCount))
                r.unreadBadge:SetSize((uCount > 99 and 36) or (uCount > 9 and 30) or 22, 22)
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
            elseif item.kind == "MENTIONS" then
                r.kindIcon:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\bell-on")
                r.kindIcon:SetVertexColor(1.0, 0.82, 0.24)
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
        r.sub:ClearAllPoints()
        r.sub:SetPoint("BOTTOMLEFT", 10, 4)
        if hasUnread and r.unreadBadge then
            r.title:SetPoint("RIGHT", r.unreadBadge, "LEFT", -6, 0)
            r.sub:SetPoint("RIGHT", r.unreadBadge, "LEFT", -6, 0)
        else
            r.title:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.sub:SetPoint("RIGHT", r, "RIGHT", -8, 0)
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
        local favKey = ResolveChatFavKey(item)
        local isFav = favKey and Store and Store.IsSocialFavorite and Store:IsSocialFavorite(favKey) == true
        local favStar = isFav and (Compat.FavoriteStarMarkup and Compat.FavoriteStarMarkup(12) or "") or ""
        local pinTag = item.pinned and ("|cffffd24d[" .. L["Pinned"] .. "]|r ") or ""
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
        local isOfflineDirect = isDirectRow and (not IsChatThreadOnline(item)) and not hasUnread
        r.title:SetAlpha(isOfflineDirect and 0.66 or 1.0)
        r.sub:SetAlpha(isOfflineDirect and 0.60 or 0.94)
        r.title:SetText(favStar .. pinTag .. mentionTag .. facIco .. hex .. (item.title or "") .. "|r" .. availTag .. mutedTag)

        local draftTxt = panel._drafts and panel._drafts[item.key]
        local subStr
        if item._searchPreview and item._searchPreview ~= "" then
            local mTag = (item._searchMatchCount and item._searchMatchCount > 1)
                and (L["Match"] .. " (" .. item._searchMatchCount .. "):")
                or L["Match:"]
            subStr = "|cff8ab4f8" .. mTag .. "|r " .. item._searchPreview
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
    SetupChatThreadDragReorder(threadsScroll, panel)

    -- Right: Active conversation & composer
    local rightCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 8, 0)
    rightCard:SetPoint("BOTTOMRIGHT", 0, 0)
    panel._leftCard = leftCard
    panel._rightCard = rightCard

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

    panel.btnToggleThreads = Theme:CreateButton(rightHdr, 24, 20, "", "default")
    Theme:ConfigureIconButton(panel.btnToggleThreads, 24, 20, "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", {
        size = 15,
        tooltipFn = function()
            return (panel._compactHideThreads == true) and L["Show Threads"] or L["Focus Chat"]
        end,
    })
    panel.btnToggleThreads:SetPoint("LEFT", rightHdr, "LEFT", 0, 0)
    panel.btnToggleThreads:Hide()

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
            local k = ns.Chat and ns.Chat.activeThreadKey
            local statusTxt = (k and ns.Chat and ns.Chat.FormatThreadMuteStatus) and ns.Chat:FormatThreadMuteStatus(k) or nil
            if statusTxt then
                return L["Notifications Muted"], statusTxt .. "\n" .. L["Click to unmute or change duration."]
            elseif selfBtn._scMuted then
                return L["Unmute Conversation"], L["Sound alerts are muted for this conversation. Click to re-enable."]
            end
            return L["Silence Notifications"], L["Silence this tab for 5, 10, 30 minutes, until leaving a dungeon/raid, or permanently."]
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
    btnClearNotes:SetScript("OnClick", function()
        if ns.UI and ns.UI.OpenConfirmModal then
            ns.UI:OpenConfirmModal({
                title = L["Clear Notes"],
                message = L["Are you sure you want to clear all saved personal notes?"],
                confirmText = L["Clear"],
                onConfirm = function()
                    if ns.Chat and ns.Chat.ClearHistory then
                        ns.Chat:ClearHistory("notes:self")
                    end
                end,
            })
        elseif ns.Chat and ns.Chat.ClearHistory then
            ns.Chat:ClearHistory("notes:self")
        end
    end)
    btnClearNotes:Hide()

    panel.btnMentionCfg = Theme:CreateButton(rightHdr, 24, 20, "", "primary")
    Theme:ConfigureIconButton(panel.btnMentionCfg, 24, 20, "Interface\\Icons\\INV_Letter_15", {
        size = 13,
        title = L["Keywords"],
    })
    panel.btnMentionCfg:SetPoint("RIGHT", 0, 0)
    panel.btnMentionCfg:SetScript("OnClick", function()
        SocialPanels:OpenMentionKeywordsModal()
    end)
    panel.btnMentionCfg:Hide()

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
                    local sLk, sFirst
                    if Compat.ParseCharacterFields then
                        sLk, sFirst = Compat.ParseCharacterFields(entry.sender)
                    end
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
        if not k or not act or act.kind == "NOTES" then return end
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
            local actFavKey = ResolveChatFavKey(act)
            if actFavKey and Store and Store.IsSocialFavorite and Store.ToggleSocialFavorite then
                local isFav = Store:IsSocialFavorite(actFavKey)
                local starMark = Compat.FavoriteStarMarkup and Compat.FavoriteStarMarkup(12) or ""
                root:CreateButton(isFav and (starMark .. L["Unfavorite"]) or L["Favorite"], function()
                    Store:ToggleSocialFavorite(actFavKey)
                    panel:Refresh()
                end)
            end
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
                root:CreateButton("|cffff5555" .. L["Clear Active Chat"] .. "|r", function()
                    local targetKey = k
                    local title = act.title or k
                    if ns.UI and ns.UI.OpenConfirmModal then
                        ns.UI:OpenConfirmModal({
                            title = L["Clear Active Chat"],
                            message = L["Are you sure you want to clear all messages in '%s'?"]:format(title),
                            confirmText = L["Clear"],
                            onConfirm = function()
                                if ns.Chat and ns.Chat.ClearHistory then
                                    ns.Chat:ClearHistory(targetKey)
                                    panel:Refresh()
                                end
                            end,
                        })
                    elseif ns.Chat and ns.Chat.ClearHistory then
                        ns.Chat:ClearHistory(targetKey)
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

    btnMuteThread:SetScript("OnClick", function(selfBtn)
        local k = ns.Chat and ns.Chat.activeThreadKey
        if not (k and ns.Chat) then return end
        if MenuUtil and MenuUtil.CreateContextMenu and ns.Chat.PopulateThreadMuteMenu then
            local thr = ns.Chat.threads and ns.Chat.threads[k]
            local titleStr = (thr and (thr.title or thr.targetName)) or k
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                root:CreateTitle(L["Silence Notifications"] .. ": " .. titleStr)
                ns.Chat:PopulateThreadMuteMenu(root, k, titleStr)
            end)
        else
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
            local roomId = k:sub(6)
            local thr = ns.Chat.threads and ns.Chat.threads[k]
            local roomTitle = (thr and thr.title) or roomId
            if ns.UI and ns.UI.OpenConfirmModal then
                ns.UI:OpenConfirmModal({
                    title = L["Leave"],
                    message = L["Are you sure you want to leave room '%s'?"]:format(roomTitle),
                    confirmText = L["Leave"],
                    onConfirm = function()
                        if ns.Chat and ns.Chat.LeaveRoom then
                            ns.Chat:LeaveRoom(roomId)
                        end
                    end,
                })
            else
                ns.Chat:LeaveRoom(roomId)
            end
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

    local peerStatusIcon = peerBar:CreateTexture(nil, "OVERLAY")
    peerStatusIcon:SetSize(13, 13)
    peerStatusIcon:SetPoint("LEFT", 2, 0)
    peerStatusIcon:Hide()

    local peerStatusText = peerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    peerStatusText:SetPoint("LEFT", peerStatusIcon, "RIGHT", 5, 0)
    peerStatusText:SetPoint("RIGHT", peerBar, "RIGHT", -4, 0)
    peerStatusText:SetJustifyH("LEFT")
    peerStatusText:SetWordWrap(false)

    local peerStatusHover = CreateFrame("Frame", nil, peerBar)
    peerStatusHover:SetPoint("TOPLEFT", peerBar, "TOPLEFT", 0, 0)
    peerStatusHover:SetPoint("BOTTOMRIGHT", peerBar, "BOTTOMRIGHT", 0, 0)
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
    msgFrame:SetMaxLines(1000)
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
                if ns.UI and ns.UI.OpenConfirmModal then
                    ns.UI:OpenConfirmModal({
                        title = L["Delete"],
                        message = L["Are you sure you want to delete this personal note?"],
                        confirmText = L["Delete"],
                        onConfirm = function()
                            if ns.Chat and ns.Chat.DeletePersonalNote then
                                ns.Chat:DeletePersonalNote(noteId)
                            end
                        end,
                    })
                else
                    ns.Chat:DeletePersonalNote(noteId)
                end
            end
        elseif link:find("addon:SCentral:url:", 1, true) then
            local encoded = link:match("addon:SCentral:url:([^|]+)")
            if encoded and encoded ~= "" and ns.UI and ns.UI.OpenCopyModal then
                local decoded = (ns.Chat and ns.Chat.DecodeUrlLink) and ns.Chat:DecodeUrlLink(encoded) or encoded
                ns.UI:OpenCopyModal(decoded, L["Copy Link"], L["Press Ctrl+C to copy this link to your clipboard."])
            end
        elseif link:find("addon:SCentral:w:", 1, true) then
            local who = link:match("addon:SCentral:w:([^|]+)")
            if who and who ~= "" then
                if button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() and not (IsAltKeyDown and IsAltKeyDown()) and not (IsControlKeyDown and IsControlKeyDown()) then
                    local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(who)
                    local disp = (parsed and parsed.displayName) or who
                    if replyInput and replyInput.HasFocus and replyInput:HasFocus() and replyInput.Insert then
                        local cur = (replyInput.GetText and replyInput:GetText()) or ""
                        local ins = (cur ~= "" and cur:sub(-1) ~= " " and " " or "") .. disp .. " "
                        pcall(replyInput.Insert, replyInput, ins)
                    elseif ns.Chat and ns.Chat.ExecuteSlashCommand then
                        ns.Chat:ExecuteSlashCommand('/who n-"' .. disp .. '"', true)
                    end
                    return
                elseif button == "LeftButton" and IsAltKeyDown and IsAltKeyDown() and not (IsControlKeyDown and IsControlKeyDown()) and not (IsShiftKeyDown and IsShiftKeyDown()) and (not ns.db or not ns.db.settings or ns.db.settings.chatModifierQuickActions ~= false) then
                    if InCombatLockdown and InCombatLockdown() then
                        ns:Print("%s", L["Unavailable during combat."])
                    elseif Compat and Compat.Invite then
                        Compat.Invite(who)
                    end
                    return
                elseif button == "LeftButton" and IsControlKeyDown and IsControlKeyDown() and not (IsAltKeyDown and IsAltKeyDown()) and not (IsShiftKeyDown and IsShiftKeyDown()) and (not ns.db or not ns.db.settings or ns.db.settings.chatModifierQuickActions ~= false) then
                    local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(who)
                    local disp = (parsed and parsed.displayName) or who
                    local lk = (parsed and parsed.lookupKey) or disp:lower()
                    if ns.SocialPanels and ns.SocialPanels.OpenSocialMetaModal then
                        ns.SocialPanels:OpenSocialMetaModal(disp, lk, { displayName = disp, lookupKey = lk })
                    end
                    return
                end
                local lookup = Compat.ParseCharacterFields and Compat.ParseCharacterFields(who) or who:lower()
                local bInfo = ns.Social and ns.Social.GetBNetLinkInfo and lookup and ns.Social:GetBNetLinkInfo(lookup)
                local bnetAccId = bInfo and bInfo.bnetAccountID or nil
                local bnetName = bInfo and bInfo.bnetName or nil
                local chatModOn = (not Compat.IsOfficialChatMode or not Compat.IsOfficialChatMode())
                    and ((not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("chat"))
                local scConfirmed = chatModOn and ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(who, bnetAccId)
                if scConfirmed and ns.Chat and ns.Chat.OpenDirectConversation then
                    ns.Chat:OpenDirectConversation({ targetName = who, bnetAccountID = bnetAccId, bnetName = bnetName, autoProbe = true })
                    panel:Refresh(false)
                elseif Compat.Whisper then
                    Compat.Whisper(who)
                end
            end
        elseif link:find("addon:SCentral:grp:", 1, true) then
            local idxStr, tKey = link:match("addon:SCentral:grp:(%d+):([^|]+)")
            if idxStr and tKey and Theme and Theme.OpenGroupSnapshotMenu then
                Theme:OpenGroupSnapshotMenu(msgFrame, tKey, tonumber(idxStr))
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
            if Theme and Theme.HandleGameHyperlinkClick then
                Theme:HandleGameHyperlinkClick(link, text, button, selfFrame, replyInput)
            elseif _G.ChatFrame_OnHyperlinkShow then
                pcall(_G.ChatFrame_OnHyperlinkShow, selfFrame, link, text, button)
            elseif _G.SetItemRef and not (InCombatLockdown and InCombatLockdown()) then
                pcall(_G.SetItemRef, link, text, button, selfFrame)
            end
        end
    end)
    if Theme and Theme.ShowHyperlinkTooltip then
        msgFrame:SetScript("OnHyperlinkEnter", function(selfFrame, link)
            Theme:ShowHyperlinkTooltip(selfFrame, link)
        end)
        msgFrame:SetScript("OnHyperlinkLeave", function(selfFrame)
            Theme:HideHyperlinkTooltip(selfFrame)
        end)
    end
    local btnScrollBottom = Theme:CreateButton(rightCard, 24, 22, "", "default")
    SetupIconBtn(btnScrollBottom, 24, 22, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", {
        size = 15,
        color = { 0.95, 0.88, 0.72 },
        title = L["Jump to latest messages"],
    })
    btnScrollBottom:SetPoint("BOTTOMRIGHT", msgFrame, "BOTTOMRIGHT", -4, 4)
    btnScrollBottom._scLevelOffset = 5
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
        if IsShiftKeyDown and IsShiftKeyDown() then
            if delta > 0 and self.ScrollToTop then
                self:ScrollToTop()
            elseif delta < 0 and self.ScrollToBottom then
                self:ScrollToBottom()
            end
        elseif IsControlKeyDown and IsControlKeyDown() then
            for _ = 1, 4 do
                if delta > 0 and self.PageUp then
                    self:PageUp()
                elseif delta < 0 and self.PageDown then
                    self:PageDown()
                elseif delta > 0 and self.ScrollUp then
                    self:ScrollUp()
                elseif delta < 0 and self.ScrollDown then
                    self:ScrollDown()
                end
            end
        else
            if delta > 0 and self.ScrollUp then
                self:ScrollUp()
            elseif delta < 0 and self.ScrollDown then
                self:ScrollDown()
            end
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
        if button ~= "LeftButton" or msgFrame._scHoveredHyperlink ~= nil then return end
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
    panel._composer = composer

    local inlineNotice = CreateFrame("Frame", nil, rightCard, "BackdropTemplate")
    inlineNotice:SetHeight(24)
    inlineNotice:SetPoint("BOTTOMLEFT", rightCard, "BOTTOMLEFT", 10, 36)
    inlineNotice:SetPoint("BOTTOMRIGHT", rightCard, "BOTTOMRIGHT", -10, 36)
    inlineNotice:SetFrameLevel((rightCard:GetFrameLevel() or 2) + 10)
    local inSolid = inlineNotice:CreateTexture(nil, "BACKGROUND", nil, -8)
    inSolid:SetAllPoints()
    inSolid:SetTexture(WHITE8X8)
    inSolid:SetVertexColor(0.11, 0.10, 0.10, 1.0)
    inlineNotice._solidBg = inSolid
    local inAccent = inlineNotice:CreateTexture(nil, "OVERLAY", nil, 1)
    inAccent:SetWidth(3)
    inAccent:SetPoint("TOPLEFT", inlineNotice, "TOPLEFT", 1, -2)
    inAccent:SetPoint("BOTTOMLEFT", inlineNotice, "BOTTOMLEFT", 1, 2)
    inAccent:SetTexture(WHITE8X8)
    inAccent:SetVertexColor(0.95, 0.42, 0.30, 1.0)
    local inIco = inlineNotice:CreateTexture(nil, "OVERLAY", nil, 2)
    inIco:SetSize(14, 14)
    inIco:SetPoint("LEFT", inAccent, "RIGHT", 6, 0)
    inIco:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    local inTxt = inlineNotice:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    inTxt:SetPoint("LEFT", inIco, "RIGHT", 6, 0)
    inTxt:SetPoint("RIGHT", inlineNotice, "RIGHT", -8, 0)
    inTxt:SetJustifyH("LEFT")
    inTxt:SetWordWrap(false)
    inTxt:SetTextColor(1.0, 0.88, 0.72)
    inlineNotice._txt = inTxt
    Theme:ApplyBackdrop(inlineNotice, "surface")
    inlineNotice:Hide()
    panel._inlineNotice = inlineNotice
    panel:HookScript("OnHide", function()
        if panel._inlineNotice then panel._inlineNotice:Hide() end
    end)

    local function ShowInlineNotice(msgText)
        local n = panel._inlineNotice
        if not (n and n._txt) then return end
        n._seq = (n._seq or 0) + 1
        local seq = n._seq
        n._txt:SetText(msgText or "")
        local pal = Theme:GetPalette()
        Theme:ApplyBackdrop(n, "surface", pal)
        if n.SetBackdropBorderColor then
            n:SetBackdropBorderColor(0.95, 0.42, 0.30, 0.95)
        end
        if n._solidBg then
            local sBg = (pal and pal.surfaceBg) or { 0.11, 0.10, 0.10, 1.0 }
            n._solidBg:SetVertexColor(sBg[1], sBg[2], sBg[3], 1.0)
        end
        n:SetFrameLevel((rightCard:GetFrameLevel() or 2) + 10)
        n:Show()
        if n.Raise then n:Raise() end
        if C_Timer and C_Timer.After then
            C_Timer.After(3.2, function()
                if panel._inlineNotice and panel._inlineNotice._seq == seq then
                    panel._inlineNotice:Hide()
                end
            end)
        end
    end

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
        maxLetters = 255,
        insertLinkMode = "full",
        placeholder = L["Select a conversation to reply..."],
    })
    Theme._activeChatReplyBox = replyInput
    replyInput:SetPoint("LEFT", 0, 0)
    replyInput:SetPoint("RIGHT", btnQuickReply, "LEFT", -6, 0)

    local charCounter = composer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charCounter:SetPoint("RIGHT", replyInput, "RIGHT", -8, 0)
    charCounter:SetJustifyH("RIGHT")
    charCounter:Hide()
    replyInput:HookScript("OnTextChanged", function(selfBox)
        local len = #(selfBox:GetText() or "")
        if len >= 100 then
            if selfBox.SetTextInsets then
                selfBox:SetTextInsets(9, 54, 2, 2)
            end
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
            if selfBox.SetTextInsets then
                selfBox:SetTextInsets(9, 9, 2, 2)
            end
            charCounter:Hide()
        end
    end)

    local function SubmitReply()
        if not ns.Chat then return end
        local txt = replyInput:GetText() or ""
        local trimmedTxt = Compat.Trim and Compat.Trim(txt) or txt
        if trimmedTxt == "" then
            replyInput:ClearFocus()
            return
        end
        if ns.Chat.IsSlashCommandText and ns.Chat:IsSlashCommandText(txt) then
            local okSlash, slashReason = ns.Chat:ExecuteSlashCommand(txt, true)
            if okSlash then
                replyInput:SetText("")
                replyInput:ClearFocus()
            elseif slashReason == "not_in_group" then
                replyInput:SetText("")
                if panel._drafts and ns.Chat.activeThreadKey then
                    panel._drafts[ns.Chat.activeThreadKey] = nil
                end
                replyInput:ClearFocus()
                ShowInlineNotice(L["There is no active group at the moment."])
            end
            return
        end
        if not ns.Chat.activeThreadKey then return end
        local key = ns.Chat.activeThreadKey
        local okSent, sendMode = ns.Chat:SendOrOpenReply(key, txt, true)
        if okSent ~= false then
            replyInput:SetText("")
            if panel._drafts then
                panel._drafts[key] = nil
            end
            replyInput:ClearFocus()
        elseif sendMode == "not_in_group" then
            replyInput:SetText("")
            if panel._drafts then
                panel._drafts[key] = nil
            end
            replyInput:ClearFocus()
            ShowInlineNotice(L["There is no active group at the moment."])
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
                    if not key then return end
                    local okSent, sendMode = ns.Chat:SendOrOpenReply(key, tpl, true)
                    if okSent ~= false then
                        replyInput:SetText("")
                        if panel._drafts then
                            panel._drafts[key] = nil
                        end
                        replyInput:ClearFocus()
                    elseif sendMode == "not_in_group" then
                        replyInput:SetText("")
                        if panel._drafts then
                            panel._drafts[key] = nil
                        end
                        replyInput:ClearFocus()
                        ShowInlineNotice(L["There is no active group at the moment."])
                    end
                end)
            end
            if ns.Chat.GetCategorizedQuickReplies then
                root:CreateDivider()
                local cats = ns.Chat:GetCategorizedQuickReplies()
                for _, cat in ipairs(cats) do
                    local cSub = root:CreateButton(cat.title)
                    for _, cTpl in ipairs(cat.items) do
                        local preview = (ns.Chat.ExpandQuickReplyText and ns.Chat:ExpandQuickReplyText(cTpl)) or cTpl
                        cSub:CreateButton(preview, function()
                            if not key then return end
                            local okSent, sendMode = ns.Chat:SendOrOpenReply(key, cTpl, true)
                            if okSent ~= false then
                                replyInput:SetText("")
                                if panel._drafts then
                                    panel._drafts[key] = nil
                                end
                                replyInput:ClearFocus()
                            elseif sendMode == "not_in_group" then
                                replyInput:SetText("")
                                if panel._drafts then
                                    panel._drafts[key] = nil
                                end
                                replyInput:ClearFocus()
                                ShowInlineNotice(L["There is no active group at the moment."])
                            end
                        end)
                    end
                end
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
                    if ns.UI and ns.UI.OpenConfirmModal then
                        ns.UI:OpenConfirmModal({
                            title = L["Remove Quick Reply"],
                            message = L["Are you sure you want to remove this quick reply?"],
                            confirmText = L["Remove"],
                            onConfirm = function()
                                if ns.Chat and ns.Chat.RemoveQuickReply then
                                    ns.Chat:RemoveQuickReply(idx)
                                end
                            end,
                        })
                    else
                        ns.Chat:RemoveQuickReply(idx)
                    end
                end)
            end
            root:CreateButton(L["Reset Defaults"], function()
                if ns.UI and ns.UI.OpenConfirmModal then
                    ns.UI:OpenConfirmModal({
                        title = L["Reset Defaults"],
                        message = L["Are you sure you want to reset all quick replies to defaults?"],
                        confirmText = L["Reset"],
                        onConfirm = function()
                            if ns.Chat and ns.Chat.ResetQuickReplies then
                                ns.Chat:ResetQuickReplies()
                            end
                        end,
                    })
                else
                    ns.Chat:ResetQuickReplies()
                end
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
        SyncFilterDropdownVisual()
        Theme:StyleButton(btnChatOffline, "default")
        Theme:ApplyOnlineOfflineOrb(btnChatOffline, not (ns.db and ns.db.settings and ns.db.settings.chatShowOffline == false), 24, 22)
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
        Theme:StyleButton(btnClearNotes, "danger")
        Theme:StyleButton(panel.btnMentionCfg, "primary")
        Theme:StyleButton(btnMuteThread, "default")
        Theme:StyleButton(btnSend, "primary")
        Theme:StyleButton(btnQuickReply, "default")
        Theme:StyleButton(btnScrollBottom, "default")
        Theme:StyleButton(btnUnpinBanner, "default")
        Theme:StyleButton(btnOfficialDest, "primary")
        if panel.btnToggleThreads then Theme:StyleButton(panel.btnToggleThreads, "default") end
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
        local pw = math.floor((panel:GetWidth() or 730) + 0.5)
        if pw <= 40 then pw = 730 end
        local ph = math.floor((panel:GetHeight() or 0) + 0.5)
        ReflowChatTopBar(pw)
        SyncSendButtonVisual()

        local isNarrow = pw < 540
        local hideThreads = isNarrow and (panel._compactHideThreads == true)
        if panel.btnToggleThreads then
            panel.btnToggleThreads:SetShown(isNarrow)
            if isNarrow then
                Theme:SetButtonActive(panel.btnToggleThreads, hideThreads, "default")
            end
        end

        local pending = ns.Chat and ns.Chat:GetPendingRoomInvites() or {}
        local showInvite = (#pending > 0 and inviteBar:IsShown()) and true or false
        local topH = math.floor((topBar:GetHeight() or 60) + 0.5)
        local sig = pw .. ":" .. ph .. ":" .. topH .. ":" .. (showInvite and 1 or 0) .. ":" .. (hideThreads and 1 or 0)
        if panel._scChatSplitSig == sig then
            return
        end
        panel._scChatSplitSig = sig

        local topAnchor = showInvite and inviteBar or topBar
        local topGap = showInvite and -6 or -8

        leftCard:ClearAllPoints()
        rightCard:ClearAllPoints()
        if isNarrow then
            if hideThreads then
                leftCard:Hide()
                rightCard:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, topGap)
                rightCard:SetPoint("BOTTOMRIGHT", 0, 0)
            else
                leftCard:Show()
                local avail = math.max(200, ph - topH - 16)
                local rows = math.max(2, math.min(4, math.floor((math.floor(avail * 0.42) - 38) / 38)))
                local leftH = 38 + rows * 38
                leftCard:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, topGap)
                leftCard:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", 0, topGap)
                if math.abs((leftCard:GetHeight() or 0) - leftH) >= 1 then
                    leftCard:SetHeight(leftH)
                end

                rightCard:SetPoint("TOPLEFT", leftCard, "BOTTOMLEFT", 0, -6)
                rightCard:SetPoint("BOTTOMRIGHT", 0, 0)
            end
        else
            leftCard:Show()
            local leftW = math.max(205, math.min(288, math.floor(pw * 0.31)))
            if math.abs((leftCard:GetWidth() or 0) - leftW) >= 1 then
                leftCard:SetWidth(leftW)
            end
            leftCard:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, topGap)
            leftCard:SetPoint("BOTTOMLEFT", 0, 0)

            rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 8, 0)
            rightCard:SetPoint("BOTTOMRIGHT", 0, 0)
        end
    end
    if panel.btnToggleThreads then
        panel.btnToggleThreads:SetScript("OnClick", function()
            panel._compactHideThreads = not (panel._compactHideThreads == true)
            LayoutChatPanels()
            if panel.Refresh then
                panel:Refresh(false)
            end
        end)
    end
    panel:SetScript("OnSizeChanged", LayoutChatPanels)

    function panel:ApplyNavigation(opts)
        if type(opts) ~= "table" then return end
        if opts.chatFilter and opts.chatFilter ~= "" then
            self._filter = opts.chatFilter
        end
        if opts.chatThreadKey and ns.Chat and ns.Chat.SetActiveThread then
            ns.Chat:SetActiveThread(opts.chatThreadKey, false)
        else
            local navList = FilterChatThreadsByType(self._filter, true)
            local bestUnread = FindNewestUnreadThread(navList)
            if bestUnread and ns.Chat and ns.Chat.SetActiveThread then
                ns.Chat:SetActiveThread(bestUnread.key, false)
            elseif navList[1] and ns.Chat and ns.Chat.SetActiveThread then
                ns.Chat:SetActiveThread(navList[1].key, false)
            end
        end
        if self.Refresh then
            self:Refresh(true)
        end
    end

    function panel:Refresh(resetScroll)
        local p = Theme:GetPalette()
        local themeChanged = (panel._lastThemeKey ~= p.key)
        if themeChanged then
            self:RefreshTheme()
        end

        SyncFilterDropdownVisual()
        local totalUnread, badgeTones = CollectUnreadBadgeSummary(filterDefs)
        self._lastTotalUnread = totalUnread
        if totalUnread > 0 then
            filterUnreadBadge:SetAlpha(1)
            if filterUnreadBadge.SetCountMulti and #badgeTones >= 2 then
                filterUnreadBadge:SetCountMulti(totalUnread, badgeTones, false)
            elseif filterUnreadBadge.SetCount then
                filterUnreadBadge:SetCount(totalUnread, badgeTones[1] or "whisper")
            end
            filterUnreadBadge:SetFrameLevel((btnFilterMenu:GetFrameLevel() or 8) + 12)
            btnFilterUnreadHit:SetSize(math.max(20, filterUnreadBadge:GetWidth() or 20), math.max(20, filterUnreadBadge:GetHeight() or 20))
            btnFilterUnreadHit:SetFrameLevel((filterUnreadBadge:GetFrameLevel() or 20) + 4)
            btnFilterUnreadHit:Show()
        else
            if filterUnreadBadge.SetCount then
                filterUnreadBadge:SetCount(0)
            else
                filterUnreadBadge:Hide()
            end
            btnFilterUnreadHit:Hide()
        end

        local showChatOff = not (ns.db and ns.db.settings and ns.db.settings.chatShowOffline == false)
        Theme:ApplyOnlineOfflineOrb(btnChatOffline, showChatOff, 24, 22)
        local showQuickUnread = (totalUnread > 0) or (self._filter == "unread")
        btnUnreadQuick:SetShown(showQuickUnread)
        if showQuickUnread then
            btnUnreadQuick._unreadCount = totalUnread
            Theme:SetIconToggle(btnUnreadQuick, self._filter == "unread" or totalUnread > 0, { 1.0, 0.40, 0.35 })
        end

        local pending = ns.Chat and ns.Chat:GetPendingRoomInvites() or {}
        if #pending > 0 then
            local inv = pending[1]
            invText:SetText(string.format(L["Invite to room '%s' from %s"], inv.title or inv.id, inv.host or "?"))
            invAccept._invId = inv.id
            invDecline._invId = inv.id
            inviteBar:Show()
        else
            invAccept._invId = nil
            invDecline._invId = nil
            inviteBar:Hide()
        end
        LayoutChatPanels()

        local threads = FilterChatThreadsByType(self._filter, false)
        local tQuery = threadSearch and threadSearch:GetText() or ""
        local qFold = (tQuery ~= "") and ((ns.Chat and ns.Chat.FoldSearchText) and ns.Chat:FoldSearchText(tQuery) or tQuery:lower()) or ""
        if qFold ~= "" then
            local filtered = {}
            for _, th in ipairs(threads) do
                th._searchPreview = nil
                th._searchMatchCount = nil
                local hay = (ns.Chat and ns.Chat.FoldSearchText)
                    and ns.Chat:FoldSearchText((th.title or "") .. " " .. (th.preview or ""))
                    or ((th.title or "") .. " " .. (th.preview or "")):lower()
                local rawThread = ns.Chat and ns.Chat.threads and ns.Chat.threads[th.key]
                local msgs = rawThread and rawThread.messages
                local matchCount = 0
                local latestMatchText = nil
                if type(msgs) == "table" then
                    for i = #msgs, 1, -1 do
                        local m = msgs[i]
                        local mText = m and (m.rawText or m.text) or ""
                        local mSender = m and m.sender or ""
                        local mFold = (ns.Chat and ns.Chat.FoldSearchText) and ns.Chat:FoldSearchText(mSender .. " " .. mText) or (mSender .. " " .. mText):lower()
                        if mFold:find(qFold, 1, true) then
                            matchCount = matchCount + 1
                            if not latestMatchText then
                                latestMatchText = mText
                            end
                        end
                    end
                end
                if matchCount > 0 then
                    th._searchPreview = latestMatchText
                    th._searchMatchCount = matchCount
                    filtered[#filtered + 1] = th
                elseif hay:find(qFold, 1, true) then
                    filtered[#filtered + 1] = th
                end
            end
            threads = filtered
        else
            for _, th in ipairs(threads) do
                th._searchPreview = nil
                th._searchMatchCount = nil
            end
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
        local displayThreads = threads
        threadsScroll:SetData(displayThreads, emptyMsg, resetScroll)

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
        local prevSameThread = (panel._renderedMsgActiveKey == activeKey) and (not resetScroll)
        local prevMsgCount = panel._renderedMsgCount or 0
        local canIncrementalAppend = (not themeChanged)
            and (not resetScroll)
            and active ~= nil
            and prevSameThread
            and (panel._renderedMsgNil == false)
            and (panel._renderedSearchFold == "")
            and (qFold == "")
            and (panel._renderedMsgDelivSig == delivSig)
            and (prevMsgCount > 0)
            and (lineCount > prevMsgCount)
            and (lines ~= nil and panel._renderedMsgFirst == lines[1])
        local needMsgRebuild = canIncrementalAppend
            or themeChanged or resetScroll
            or panel._renderedMsgActiveKey ~= activeKey
            or panel._renderedMsgNil ~= (active == nil)
            or panel._renderedMsgCount ~= lineCount
            or (lines and (panel._renderedMsgFirst ~= lines[1] or panel._renderedMsgLast ~= lines[lineCount]))
            or panel._renderedMsgDelivSig ~= delivSig
            or panel._renderedSearchFold ~= qFold
        local wasAtBottom = (not msgFrame.AtBottom) or (msgFrame:AtBottom() ~= false)
        local savedScrollOff = (prevSameThread and (not wasAtBottom) and msgFrame.GetScrollOffset) and (msgFrame:GetScrollOffset() or 0) or 0
        if prevSameThread and (not wasAtBottom) and lineCount > prevMsgCount and savedScrollOff > 0 then
            savedScrollOff = savedScrollOff + (lineCount - prevMsgCount)
        end
        panel._pendingRestoreScrollOffset = (prevSameThread and (not wasAtBottom) and savedScrollOff > 0) and savedScrollOff or nil
        if needMsgRebuild then
            panel._renderedMsgActiveKey = activeKey
            panel._renderedMsgNil = (active == nil)
            panel._renderedMsgCount = lineCount
            panel._renderedMsgFirst = lines and lines[1] or nil
            panel._renderedMsgLast = (lines and lineCount > 0) and lines[lineCount] or nil
            panel._renderedMsgDelivSig = delivSig
            panel._renderedSearchFold = qFold
            if not canIncrementalAppend then
                panel._renderedLastDayKey = nil
                panel._renderedLastPairKey = nil
                panel._renderedLastGroupKey = nil
                panel._renderedLastMsgTs = nil
                panel._renderedUnreadBannerShown = nil
                msgFrame:Clear()
            end
        end

        if active then
            local isRoom = active.kind == "ROOM"
            local isNotes = active.kind == "NOTES"
            local isMentions = active.kind == "MENTIONS"
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
            local hdrFavKey = isDirect and ResolveChatFavKey(active) or nil
            local hdrStar = (hdrFavKey and Store and Store.IsSocialFavorite and Store:IsSocialFavorite(hdrFavKey) == true)
                and (Compat.FavoriteStarMarkup and Compat.FavoriteStarMarkup(14) or "") or ""
            local hdrLvl = isDirect and (not isNotes) and ((active.level and active.level > 0 and active.level)
                or (ns.Chat and ns.Chat.ResolvePlayerLevel and ns.Chat:ResolvePlayerLevel(active.lookupKey, shownHdrTitle, active.guid, active.bnetAccountID))) or nil
            local hdrLvlTag = (hdrLvl and hdrLvl > 0) and (" |cff9da7b5[" .. L["Lv."] .. tostring(math.floor(hdrLvl)) .. "]|r") or ""
            hdrTitle:SetText(hdrStar .. hdrFacIco .. shownHdrTitle .. hdrLvlTag .. (isRoom and ("  |cff3fb950[" .. memberCount .. "]|r") or "") .. availHdrTag .. unreadHdrTag)

            btnRoomInvite:SetShown(isRoom)
            btnLeaveRoom:SetShown(isRoom)
            btnTargetCard:SetShown((not isNotes) and (not isMentions) and isDirect and (active.targetName ~= nil or active.bnetAccountID ~= nil))
            btnPinLoc:SetShown((not isNotes) and (not isMentions) and (not isRoom) and isDirect and pState.verified == true)
            btnClearNotes:SetShown(isNotes and type(active.messages) == "table" and #active.messages > 0)
            btnMuteThread:SetShown(not isNotes)
            btnThreadActions:SetShown(not isNotes)
            if panel.btnMentionCfg then
                panel.btnMentionCfg:SetShown(isMentions)
            end
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
            if panel.btnMentionCfg and panel.btnMentionCfg:IsShown() then table.insert(orderedRight, panel.btnMentionCfg) end
            if btnMuteThread:IsShown() then table.insert(orderedRight, btnMuteThread) end
            if btnTargetCard:IsShown() then table.insert(orderedRight, btnTargetCard) end
            if btnPinLoc:IsShown() then table.insert(orderedRight, btnPinLoc) end
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
            if panel.btnToggleThreads and panel.btnToggleThreads:IsShown() then
                hdrTitle:SetPoint("LEFT", panel.btnToggleThreads, "RIGHT", 6, 0)
            else
                hdrTitle:SetPoint("LEFT", 2, 0)
            end
            if prevR then
                hdrTitle:SetPoint("RIGHT", prevR, "LEFT", -8, 0)
            else
                hdrTitle:SetPoint("RIGHT", rightHdr, "RIGHT", -4, 0)
            end

            -- Peer verification bar (compact icon + short tag; full explanation on hover)
            peerStatusIcon:Show()
            peerStatusIcon:SetTexCoord(0, 1, 0, 1)
            peerStatusIcon:SetVertexColor(1, 1, 1)
            peerStatusText:ClearAllPoints()
            peerStatusText:SetPoint("LEFT", peerStatusIcon, "RIGHT", 5, 0)
            peerStatusText:SetPoint("RIGHT", peerBar, "RIGHT", -4, 0)
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
            elseif isMentions then
                SetPeerStatus(
                    "Interface\\AddOns\\SocialCentral\\Media\\bell-on", 1.0, 0.82, 0.24,
                    "|cffffd24d" .. L["Mentions & Keywords Radar"] .. "|r",
                    L["Mentions & Keywords Radar"],
                    L["Click any sender name to whisper or open chat, or click Keywords to edit monitored words."]
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
            if isMentions then
                btnSend:SetEnabled(false)
                btnQuickReply:SetEnabled(false)
                if replyInput.SetPlaceholder then
                    replyInput:SetPlaceholder(L["Click a sender name above to reply, or click 'Keywords' to configure."])
                end
            elseif (isNotes or isRoom or pState.verified or isAlliance) and not isBNetRedirectActive and not isAltRedirectActive then
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
                    local lastDayKey = canIncrementalAppend and panel._renderedLastDayKey or nil
                    local lastPairKey = canIncrementalAppend and panel._renderedLastPairKey or nil
                    local lastGroupKey = canIncrementalAppend and panel._renderedLastGroupKey or nil
                    local lastMsgTs = canIncrementalAppend and panel._renderedLastMsgTs or nil
                    local grpRenderMap = ((active.kind == "PARTY" or active.kind == "RAID" or active.kind == "INSTANCE_CHAT") and ns.Chat and ns.Chat.GetThreadGroupRenderMap)
                        and ns.Chat:GetThreadGroupRenderMap(active)
                        or nil
                    local unreadTargetEntry = active.lastReadBannerEntry or active.firstUnreadEntry
                    local unreadTargetTs = active.lastReadBannerTs or active.firstUnreadTs
                    local unreadBannerShown = canIncrementalAppend and (panel._renderedUnreadBannerShown == true) or false
                    local startMsgIdx = canIncrementalAppend and (prevMsgCount + 1) or ((qFold ~= "") and 1 or math.max(1, #lines - 599))
                    for msgIdx = startMsgIdx, #lines do
                        local entry = lines[msgIdx]
                        local eTs = tonumber(entry.ts) or 0
                        local showedBreakLine = false
                        if eTs > 0 then
                            local dKey = date("%Y-%m-%d", eTs)
                            if dKey ~= lastDayKey then
                                lastDayKey = dKey
                                lastPairKey = nil
                                local dLabel = (dKey == todayKey and L["Today"])
                                    or (dKey == yesterdayKey and L["Yesterday"])
                                    or date("%d/%m/%Y", eTs)
                                msgFrame:AddMessage("|cff7f8a9c—— " .. dLabel .. " ——|r")
                                showedBreakLine = true
                            end
                        end
                        local gInfo = (not entry.isStatusNotice and grpRenderMap and entry.groupRosterId and grpRenderMap[entry.groupRosterId]) or nil
                        local mGrpSess = gInfo and gInfo.sessKey or nil
                        if mGrpSess and mGrpSess ~= lastGroupKey then
                            lastGroupKey = mGrpSess
                            local grpBanner = ns.Chat and ns.Chat.FormatGroupSessionBanner and ns.Chat:FormatGroupSessionBanner(active.key, msgIdx, gInfo, eTs)
                            if grpBanner then
                                msgFrame:AddMessage(grpBanner)
                                showedBreakLine = true
                            end
                        elseif (not mGrpSess) and lastGroupKey ~= nil and not entry.isStatusNotice then
                            lastGroupKey = nil
                        end
                        if (not showedBreakLine) and lastMsgTs and eTs > 0 and (eTs - lastMsgTs) >= 7200 and not entry.isStatusNotice then
                            msgFrame:AddMessage("|cff6e7681· · · " .. date("%H:%M", eTs) .. " · · ·|r")
                        end
                        if eTs > 0 then
                            lastMsgTs = eTs
                        end
                        if not unreadBannerShown and entry.incoming and ((unreadTargetEntry and entry == unreadTargetEntry) or (not unreadTargetEntry and unreadTargetTs and entry.ts and entry.ts >= unreadTargetTs)) then
                            unreadBannerShown = true
                            msgFrame:AddMessage("|cffffd24d—— " .. L["New Messages"] .. " ——|r")
                        end
                        local tsRaw = entry.ts and entry.ts > 0 and date("[%H:%M]", entry.ts) or nil
                        local ts = tsRaw and (entry.isStatusNotice and ("|cff9da7b5" .. tsRaw .. "|r ") or ("|Haddon:SCentral:msgact:" .. tostring(msgIdx) .. ":" .. tostring(active.key) .. "|h|cff9da7b5" .. tsRaw .. "|r|h ")) or ""
                        local bodyTxt = entry.rawText or entry.text or ""
                        if (not ns.db or not ns.db.settings or ns.db.settings.chatClickableUrls ~= false) and ns.Chat and ns.Chat.LinkifyUrls then
                            bodyTxt = ns.Chat:LinkifyUrls(bodyTxt)
                        end
                        if ns.Chat and ns.Chat.FormatRaidTargetTokens then
                            bodyTxt = ns.Chat:FormatRaidTargetTokens(bodyTxt)
                        end
                        if entry.incoming and not entry.isStatusNotice and not isNotes and ns.Chat and ns.Chat.HighlightMentionsInline then
                            local mKind
                            if isMentions then
                                mKind = nil
                            else
                                mKind = active.kind
                            end
                            bodyTxt = ns.Chat:HighlightMentionsInline(bodyTxt, mKind, entry.mentionTerm)
                        end
                        local searchHitTag = ""
                        if qFold ~= "" and ns.Chat and ns.Chat.FoldSearchText then
                            if ns.Chat:FoldSearchText((entry.sender or "") .. " " .. (entry.rawText or entry.text or "")):find(qFold, 1, true) then
                                searchHitTag = "|cffffd24d[»]|r "
                            end
                        end
                        if entry.isStatusNotice then
                            local sCol = (entry.statusKind == "DND") and "|cfff54747" or "|cffff9b3d"
                            msgFrame:AddMessage(ts .. searchHitTag .. sCol .. "[" .. (entry.sender or L["Status"]) .. "]|r |cffb8c2d0" .. bodyTxt .. "|r")
                        elseif isNotes then
                            local delLink = entry.noteId and ("|Haddon:SCentral:delnote:" .. tostring(entry.noteId) .. "|h|cffff6b6b[x]|r|h ") or ""
                            msgFrame:AddMessage(ts .. searchHitTag .. delLink .. "|cffffd24d" .. (entry.sender or "") .. "|r: " .. bodyTxt)
                        elseif isMentions then
                            local hex = entry.classFile and Compat.ClassHex(entry.classFile) or "|cff58a6ff"
                            local chTag = entry.mentionChannel and ("|cff8ab4f8[" .. entry.mentionChannel .. "]|r ") or ""
                            local kwTag = entry.mentionTerm and ("|cffffd24d[" .. entry.mentionTerm .. "]|r ") or ""
                            local sName = entry.sender or "?"
                            local senderLink = "|Haddon:SCentral:w:" .. sName .. "|h" .. hex .. "[" .. sName .. "]|r|h"
                            msgFrame:AddMessage(ts .. searchHitTag .. chTag .. kwTag .. senderLink .. ": " .. bodyTxt)
                        else
                            local addonTag = (entry.viaAddon and not isRoom) and ((Compat.AddonIconMarkup and (Compat.AddonIconMarkup(true, 12) .. " ")) or "|cff3fb950[SC]|r ") or ""
                            local mentionPrefix = ""
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
                            local msgLvlTag = ""
                            if entry.incoming and not entry.isStatusNotice then
                                local mLvl = (tonumber(entry.senderLevel) and tonumber(entry.senderLevel) > 0 and math.floor(tonumber(entry.senderLevel)))
                                    or (ns.Chat and ns.Chat.ResolvePlayerLevel and ns.Chat:ResolvePlayerLevel(nil, entry.senderCharName or entry.sender, entry.senderGuid, isDirectMsg and active.bnetAccountID or nil, true))
                                    or nil
                                if mLvl and mLvl > 0 then
                                    entry.senderLevel = mLvl
                                    msgLvlTag = " |cff9da7b5[" .. L["Lv."] .. tostring(mLvl) .. "]|r"
                                end
                            end
                            local senderDisp = sFacIco .. hex .. shortSender .. "|r" .. msgLvlTag
                            msgFrame:AddMessage(ts .. searchHitTag .. mentionPrefix .. addonTag .. senderDisp .. ": " .. bodyTxt .. tick)
                        end
                    end
                    panel._renderedLastDayKey = lastDayKey
                    panel._renderedLastPairKey = lastPairKey
                    panel._renderedLastGroupKey = lastGroupKey
                    panel._renderedLastMsgTs = lastMsgTs
                    panel._renderedUnreadBannerShown = unreadBannerShown
                end
                if panel._pendingRestoreScrollOffset and panel._pendingRestoreScrollOffset > 0 and msgFrame.SetScrollOffset then
                    msgFrame:SetScrollOffset(panel._pendingRestoreScrollOffset)
                elseif msgFrame.ScrollToBottom then
                    msgFrame:ScrollToBottom()
                end
                panel._pendingRestoreScrollOffset = nil
                local atBotNow = (not msgFrame.AtBottom) or (msgFrame:AtBottom() ~= false)
                btnScrollBottom:SetShown(not atBotNow)
            end
        else
            hdrTitle:SetText(L["Select a conversation or create a Private Room"])
            peerStatusText:SetText("")
            peerStatusIcon:Hide()
            peerStatusHover._tipTitle = nil
            peerStatusHover._tipDesc = nil
            pinnedBanner:Hide()
            btnRoomInvite:Hide()
            btnLeaveRoom:Hide()
            btnTargetCard:Hide()
            btnPinLoc:Hide()
            btnThreadActions:Hide()
            btnClearNotes:Hide()
            if panel.btnMentionCfg then panel.btnMentionCfg:Hide() end
            btnMuteThread:Hide()
            hdrTitle:ClearAllPoints()
            if panel.btnToggleThreads and panel.btnToggleThreads:IsShown() then
                hdrTitle:SetPoint("LEFT", panel.btnToggleThreads, "RIGHT", 6, 0)
            else
                hdrTitle:SetPoint("LEFT", 2, 0)
            end
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

    panel:HookScript("OnHide", function()
        local k = ns.Chat and ns.Chat.activeThreadKey
        local act = k and ns.Chat.threads and ns.Chat.threads[k]
        if act then
            act.lastReadBannerTs = nil
            act.lastReadBannerEntry = nil
        end
        panel._renderedMsgActiveKey = nil
        panel._renderedLastDayKey = nil
        panel._renderedLastPairKey = nil
        panel._renderedLastGroupKey = nil
        panel._renderedLastMsgTs = nil
        panel._renderedUnreadBannerShown = nil
    end)

    panel:RefreshTheme()
    return panel
end

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
    if itemData and itemData._isRecipe then
        local shown = false
        if itemData.link then
            shown = pcall(GameTooltip.SetHyperlink, GameTooltip, itemData.link)
        elseif itemData.itemID then
            shown = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. tostring(itemData.itemID))
        elseif itemData.spellID and GameTooltip.SetSpellByID then
            shown = pcall(GameTooltip.SetSpellByID, GameTooltip, itemData.spellID)
        end
        if not shown then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(itemData.name or "?", 1, 0.85, 0.25, true)
        end
        if itemData._profName and itemData._profName ~= "" then
            GameTooltip:AddLine("|cff58a6ff" .. L["Profession"] .. ":|r " .. itemData._profName, 0.88, 0.94, 1.0, true)
        end
        if itemData._reagentsSummary and itemData._reagentsSummary ~= "" then
            GameTooltip:AddLine("|cffffd24d" .. L["Materials"] .. ":|r " .. itemData._reagentsSummary, 0.92, 0.92, 0.94, true)
        end
        GameTooltip:Show()
        return
    end
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
        Theme:PrepareTopOverlayModal(altRemoveModal, 850)
        Theme:ApplyBackdrop(altRemoveModal, "window")
        Theme:StyleButton(altRemoveModal.topCloseBtn, "default")
        Theme:StyleButton(altRemoveModal.btnConfirm, "danger")
        Theme:StyleButton(altRemoveModal.btnCancel, "default")
        Theme:SyncSubtreeLayers(altRemoveModal, 8)
        return altRemoveModal
    end

    local m = CreateFrame("Frame", "SocialCentralRemoveAltModal", UIParent, "BackdropTemplate")
    m:SetSize(400, 168)
    m:SetPoint("CENTER")
    Theme:PrepareTopOverlayModal(m, 850)
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

    m.helpBtn = AddHelp(
        m,
        topCloseBtn,
        L["Help: Remove Saved Alt"],
        L["Removes an offline character snapshot (gold, items, professions, and lockouts) from your SocialCentral account roster."],
        L["Click Remove Alt to erase the saved snapshot, or Cancel to keep it. Logging back in on that character records it again."],
        "RIGHT",
        "LEFT",
        -6,
        0,
        { target = m }
    )
    if m.helpBtn then
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", m.helpBtn, "TOPLEFT", -6, -4)
    end

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
    Theme:SyncSubtreeLayers(m, 8)
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
    if m.Raise then m:Raise() end
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
                    onSearchAllAlts(itemName, itemData._isRecipe == true)
                end)
            end
            if itemName ~= "" and (not Compat.ShouldShowGuildFeatures or Compat.ShouldShowGuildFeatures()) and ns.NavigateToModule then
                root:CreateButton(L["Find crafters in Guild (J)"], function()
                    ns:NavigateToModule("clan", { clanRightView = "prof", clanProfQuery = itemName })
                end)
            end
            if itemData.link and ChatEdit_InsertLink then
                root:CreateButton(L["Insert link in chat"], function()
                    ChatEdit_InsertLink(itemData.link)
                end)
            elseif itemData.spellID and C_Spell and C_Spell.GetSpellLink and ChatEdit_InsertLink then
                local spLink = C_Spell.GetSpellLink(itemData.spellID)
                if spLink then
                    root:CreateButton(L["Insert link in chat"], function()
                        ChatEdit_InsertLink(spLink)
                    end)
                end
            end
            if itemName ~= "" and ns.UI and ns.UI.OpenCopyModal then
                local copyText = (itemData._reagentsSummary and itemData._reagentsSummary ~= "")
                    and (itemName .. " — " .. itemData._reagentsSummary)
                    or itemName
                root:CreateButton(L["Copy Name"], function()
                    ns.UI:OpenCopyModal(copyText)
                end)
            end
        end)
    elseif itemName ~= "" and type(onSearchAllAlts) == "function" then
        onSearchAllAlts(itemName, itemData._isRecipe == true)
    end
end

local function FormatAltWorldBadge(alt, showAlways)
    if type(alt) ~= "table" then return "" end
    local wt, altPool, wtLabel
    if Compat.GetAltWorldInfo then
        wt, altPool, wtLabel = Compat.GetAltWorldInfo(alt)
    else
        wt = alt.worldType or (Compat.DetectWorldType and Compat.DetectWorldType(alt.realmName or alt.realmPool, alt.realmRaw))
        altPool = (alt.realmName and Compat.RealmPool and Compat.RealmPool(alt.realmName))
            or (alt.realmPool and Compat.RealmPool and Compat.RealmPool(alt.realmPool))
            or alt.realmPool
        wtLabel = (Compat.FormatWorldTypeLabel and Compat.FormatWorldTypeLabel(wt)) or wt or alt.realmName
    end
    local curWorld, myPool
    if Compat.GetAltWorldInfo then
        curWorld, myPool = Compat.GetAltWorldInfo(nil)
    else
        myPool = Compat.RealmPool and Compat.RealmPool() or nil
        curWorld = Compat.DetectWorldType and Compat.DetectWorldType(Compat.Realm()) or nil
    end
    local sameWorld = (altPool and myPool and altPool == myPool) and (not curWorld or not wt or wt == curWorld)
    if (not wtLabel or wtLabel == "") and not sameWorld and alt.realmName and alt.realmName ~= "" then
        wtLabel = alt.realmName
    end
    if not wtLabel or wtLabel == "" then return "" end
    if not showAlways and sameWorld then
        return ""
    end
    local col = (wt == "PvP" or wt == "RP-PvP") and "|cffd29922" or "|cff58a6ff"
    return " " .. col .. "[" .. wtLabel .. "]|r"
end

local function ResolveAltRestedInfo(alt)
    if ns.Alts and ns.Alts.GetEstimatedRested then
        return ns.Alts:GetEstimatedRested(alt)
    end
    local lvl = tonumber(alt and alt.level) or 0
    if lvl >= 60 then return 0, false, 0, false, 0 end
    local xpMax = math.max(1, tonumber(alt and alt.xpMax) or 1)
    local r = tonumber(alt and alt.rested) or 0
    local pct = math.min(150, math.floor((r / xpMax) * 100 + 0.5))
    return pct, false, 0, false, pct
end

local function UnpackAltItem(raw, locLabel, slotId)
    if ns.Alts and ns.Alts.UnpackItem then
        return ns.Alts:UnpackItem(raw, locLabel, slotId)
    end
    if type(raw) ~= "table" then return nil end
    return {
        itemID = raw.itemID,
        link = raw.link,
        name = raw.name,
        icon = raw.icon,
        quality = raw.quality or 1,
        count = raw.count or 1,
        _isEquip = slotId ~= nil or nil,
        _slotId = slotId,
        _locLabel = locLabel,
    }
end

local function CountTableEntries(tbl)
    if type(tbl) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

local function GetSortedAltsList(sortBy, worldScope)
    local raw = (Store and Store.GetAltsList and Store:GetAltsList(worldScope)) or {}
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
    elseif sortBy == "rested" then
        table.sort(out, function(a, b)
            local al, bl = tonumber(a.level) or 0, tonumber(b.level) or 0
            local aMax, bMax = (al >= 60), (bl >= 60)
            if aMax ~= bMax then return not aMax end
            local ar = ResolveAltRestedInfo(a)
            local br = ResolveAltRestedInfo(b)
            if ar ~= br then return ar > br end
            if al ~= bl then return al > bl end
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
        GameTooltip:AddDoubleLine(L["Item Level"], tostring(math.floor(altData.itemLevel)), 0.75, 0.78, 0.85, 1.0, 0.85, 0.35)
    end
    if lvl < 60 then
        local xpVal = tonumber(altData.xp) or 0
        local xpMaxVal = math.max(1, tonumber(altData.xpMax) or 1)
        local xpPct = math.min(100, math.floor((xpVal / xpMaxVal) * 100 + 0.5))
        local restPct, isEst, etaSec = ResolveAltRestedInfo(altData)
        local xpStr
        if restPct > 0 then
            local estPref = isEst and "~" or ""
            local estTag = isEst and (" " .. L["Rested (est.)"]) or (" " .. L["Rested"])
            xpStr = ("%d%% (+%s%d%%%s)"):format(xpPct, estPref, restPct, estTag)
            if etaSec and etaSec > 60 and restPct < 150 then
                xpStr = xpStr .. " · " .. L["MAX in %s"]:format(FormatDurationCompact(etaSec))
            end
        else
            xpStr = ("%d%%"):format(xpPct)
        end
        GameTooltip:AddDoubleLine(L["Experience"], xpStr, 0.75, 0.78, 0.85, restPct >= 148 and 0.35 or (restPct > 0 and 0.45 or 0.92), restPct >= 148 and 0.92 or (restPct > 0 and 0.76 or 0.94), restPct >= 148 and 0.55 or 1.0)
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
        local bUsed = math.max(0, (altData.bankTotal or 0) - (altData.bankFree or 0))
        local bStr = (altData.bankTotal and altData.bankTotal > 0)
            and L["%d / %d slots"]:format(bUsed, altData.bankTotal)
            or ("%d %s"):format(#altData.bank, L["items"])
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

    if ns.Alts and ns.Alts.GetCraftCooldowns then
        local cds = ns.Alts:GetCraftCooldowns(altData)
        if #cds > 0 then
            local cdParts = {}
            for i = 1, math.min(#cds, 3) do
                local c = cds[i]
                cdParts[#cdParts + 1] = c.isReady
                    and (c.name .. " [" .. L["Ready"] .. "]")
                    or (c.name .. " [" .. FormatDurationCompact(c.remaining) .. "]")
            end
            local anyReady = cds[1].isReady == true
            GameTooltip:AddDoubleLine(L["Craft Cooldowns"], table.concat(cdParts, ", "), 0.75, 0.78, 0.85, anyReady and 0.35 or 1.0, anyReady and 0.92 or 0.74, anyReady and 0.55 or 0.30)
        end
    end

    if ns.Alts and ns.Alts.GetLockouts then
        local locks = ns.Alts:GetLockouts(altData)
        if #locks > 0 then
            GameTooltip:AddDoubleLine(L["Active Lockouts"], ("%d (%s)"):format(#locks, FormatDurationCompact(locks[1].reset)), 0.75, 0.78, 0.85, 1.0, 0.65, 0.30)
        end
    end
    if ns.Group and ns.Group.GetHourlyInstanceStatus then
        local st = ns.Group:GetHourlyInstanceStatus()
        local usedH, maxH = st and st.used or 0, st and st.max or 5
        GameTooltip:AddDoubleLine(L["Instance Limit (1h)"], string.format("%d/%d", usedH, maxH), 0.75, 0.78, 0.85, usedH >= maxH and 1.0 or 0.35, usedH >= maxH and 0.35 or 0.92, usedH >= maxH and 0.35 or 0.55)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Right-click to inspect, copy Armory URL, or remove."], 0.58, 0.72, 0.92, true)
    GameTooltip:Show()
end

local function ShowGoldBreakdownTooltip(anchor, worldScope, curWorldType)
    if not GameTooltip then return end
    local scopeArg = (Compat.NormalizeWorldScope and Compat.NormalizeWorldScope(worldScope)) or ((worldScope == "all") and "all" or "pool")
    local list = GetSortedAltsList("gold", scopeArg)
    local myFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    local byFac = (Store and Store.GetTotalAltsGoldByFaction and Store:GetTotalAltsGoldByFaction(scopeArg)) or nil
    local facTot = (byFac and myFac and byFac[myFac]) or (Store and Store.GetTotalAltsGold and Store:GetTotalAltsGold(scopeArg, true)) or 0
    local allTot = (byFac and byFac.total) or facTot
    local hasDualFaction = byFac and (byFac.Alliance or 0) > 0 and (byFac.Horde or 0) > 0

    GameTooltip:SetOwner(anchor, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddDoubleLine(L["Gold Breakdown"], Compat.FormatMoney(hasDualFaction and facTot or allTot), 1.0, 0.85, 0.25, 1.0, 1.0, 1.0)
    if hasDualFaction then
        GameTooltip:AddDoubleLine("|cff70b5ff" .. L["Alliance"] .. "|r", Compat.FormatMoney(byFac.Alliance or 0), 0.65, 0.82, 1.0, 1, 1, 1)
        GameTooltip:AddDoubleLine("|cffff7878" .. L["Horde"] .. "|r", Compat.FormatMoney(byFac.Horde or 0), 1.0, 0.65, 0.65, 1, 1, 1)
        GameTooltip:AddDoubleLine("|cffffd24d" .. L["Total (Account)"] .. "|r", Compat.FormatMoney(allTot), 1.0, 0.85, 0.25, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    local denom = (not hasDualFaction) and allTot or nil
    local showAllBadges = (scopeArg ~= "pool")
    for _, alt in ipairs(list) do
        local hex = Compat.ClassHex(alt.classFile)
        local disp = alt.fullName or alt.name or alt.key or "?"
        local m = tonumber(alt.money) or 0
        local facDenominator = denom or (alt.faction and byFac and byFac[alt.faction]) or allTot
        local pct = (facDenominator > 0) and math.floor((m / facDenominator) * 100 + 0.5) or 0
        local facTag = hasDualFaction and (alt.faction == "Alliance" and " |cff70b5ff[A]|r" or (alt.faction == "Horde" and " |cffff7878[H]|r" or "")) or ""
        local wTag = FormatAltWorldBadge(alt, showAllBadges)
        local leftTxt = hex .. disp .. "|r" .. facTag .. wTag .. ((facDenominator > 0 and #list > 1) and (" |cff9da7b5(" .. pct .. "%)|r") or "")
        GameTooltip:AddDoubleLine(leftTxt, Compat.FormatMoney(m))
    end
    local recordedWorlds = (Store and Store.GetRecordedAltWorlds and Store:GetRecordedAltWorlds()) or {}
    if scopeArg == "all" and #recordedWorlds <= 1 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Log in once on a character in PvE, RP PvE, or RP PvP to unlock its world filter here."], 0.70, 0.82, 0.96, true)
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
                    classID = item.classID,
                    subClassID = item.subClassID,
                    equipLoc = item.equipLoc,
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

local function CreateRosterWorldHintBar(panel, rosterPane, goldBar)
    local bar = CreateFrame("Frame", nil, rosterPane)
    bar:SetPoint("BOTTOMLEFT", goldBar, "TOPLEFT", 0, 2)
    bar:SetPoint("BOTTOMRIGHT", goldBar, "TOPRIGHT", 0, 2)
    bar:SetHeight(34)
    bar:Hide()

    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetAllPoints()
    bg:SetTexture(WHITE8X8)
    bg:SetVertexColor(0.08, 0.12, 0.18, 0.96)

    local line = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    line:SetTexture(WHITE8X8)
    line:SetVertexColor(0.35, 0.62, 0.92, 0.70)

    local lbl = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", bar, "TOPLEFT", 8, -4)
    lbl:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -8, 4)
    lbl:SetJustifyH("LEFT")
    lbl:SetJustifyV("MIDDLE")
    lbl:SetWordWrap(true)
    lbl:SetTextColor(0.68, 0.84, 0.98)
    lbl:SetText(L["No other world alts saved yet — log in once on each PvE / PvP character to sync them."])
    panel._worldHintBar = bar
    panel._goldBar = goldBar
end

-- Modular Alt UI helpers extracted outside CreateAltsPanel to stay well below Lua 5.1 local/upvalue compiler caps.
local AltUI = {}

function AltUI.CreateOverviewScrollbar(overviewFrame, overviewScroll)
    local track = CreateFrame("Frame", nil, overviewFrame)
    track:SetWidth(6)
    track:SetPoint("TOPRIGHT", overviewFrame, "TOPRIGHT", -2, -4)
    track:SetPoint("BOTTOMRIGHT", overviewFrame, "BOTTOMRIGHT", -2, 4)
    track:Hide()

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(0, 0, 0, 0.28)

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(6)
    thumb:SetHeight(32)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
    thumb.tex:SetAllPoints()

    local hovered = false
    local function RefreshThumbColor()
        local p = Theme:GetPalette()
        local c = hovered and (p.scrollThumbHover or { 0.85, 0.70, 0.30, 1.0 }) or (p.scrollThumb or { 0.56, 0.45, 0.24, 0.88 })
        thumb.tex:SetColorTexture(c[1], c[2], c[3], c[4])
    end

    local function SyncThumb(maxScroll)
        local maxS = math.max(0, tonumber(maxScroll) or 0)
        overviewScroll._scMaxScroll = maxS
        if maxS <= 1 then
            track:Hide()
            overviewScroll:ClearAllPoints()
            overviewScroll:SetPoint("TOPLEFT", overviewFrame, "TOPLEFT", 2, -2)
            overviewScroll:SetPoint("BOTTOMRIGHT", overviewFrame, "BOTTOMRIGHT", -2, 2)
            return
        end
        track:Show()
        overviewScroll:ClearAllPoints()
        overviewScroll:SetPoint("TOPLEFT", overviewFrame, "TOPLEFT", 2, -2)
        overviewScroll:SetPoint("BOTTOMRIGHT", overviewFrame, "BOTTOMRIGHT", -10, 2)
        local trackH = math.max(40, track:GetHeight() or 120)
        local vpH = overviewScroll:GetHeight() or 120
        local ratio = math.max(0.14, math.min(0.90, vpH / math.max(1, vpH + maxS)))
        local thumbH = math.max(22, math.floor(trackH * ratio))
        thumb:SetHeight(thumbH)
        local cur = overviewScroll:GetVerticalScroll() or 0
        local travel = math.max(1, trackH - thumbH)
        local pos = math.floor((math.min(maxS, math.max(0, cur)) / maxS) * travel)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -pos)
        RefreshThumbColor()
    end

    thumb:SetScript("OnEnter", function() hovered = true; RefreshThumbColor() end)
    thumb:SetScript("OnLeave", function() hovered = false; RefreshThumbColor() end)

    local dragStartY, dragStartVal
    thumb:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or (overviewScroll._scMaxScroll or 0) <= 0 then return end
        local _, cy = GetCursorPosition()
        local scale = thumb:GetEffectiveScale() or 1
        dragStartY = cy / scale
        dragStartVal = overviewScroll:GetVerticalScroll() or 0
        thumb:SetScript("OnUpdate", function()
            if not IsMouseButtonDown("LeftButton") or (overviewScroll._scMaxScroll or 0) <= 0 then
                thumb:SetScript("OnUpdate", nil)
                return
            end
            local _, curY = GetCursorPosition()
            local sc = thumb:GetEffectiveScale() or 1
            local dy = dragStartY - (curY / sc)
            local trackH = math.max(40, track:GetHeight() or 120)
            local travel = math.max(1, trackH - (thumb:GetHeight() or 22))
            local maxS = overviewScroll._scMaxScroll or 0
            local nxt = math.max(0, math.min(maxS, dragStartVal + (dy / travel) * maxS))
            overviewScroll:SetVerticalScroll(nxt)
            SyncThumb(maxS)
        end)
    end)
    local function StopDrag() thumb:SetScript("OnUpdate", nil) end
    thumb:SetScript("OnMouseUp", StopDrag)
    thumb:SetScript("OnHide", StopDrag)
    RefreshThumbColor()
    return SyncThumb, RefreshThumbColor
end

function AltUI.AttachHeaderTooltip(charHeader, panel)
    charHeader:EnableMouse(true)
    charHeader:SetScript("OnEnter", function(selfHdr)
        if panel._headerAltData then
            ShowAltTooltip(selfHdr, panel._headerAltData)
        end
    end)
    charHeader:SetScript("OnLeave", function(selfHdr)
        if GameTooltip and GameTooltip:IsOwned(selfHdr) then GameTooltip:Hide() end
    end)
end

function AltUI.ConfigureHeaderRow(row, rowData, panel, openAltActionMenuFn)
    if not row._headerHit then
        local hit = CreateFrame("Button", nil, row)
        hit:SetAllPoints()
        hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = hit:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1.0, 0.85, 0.35, 0.08)
        hit:SetScript("OnEnter", function(selfBtn)
            if not (GameTooltip and selfBtn._altKey) then return end
            GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(selfBtn._altName or "Alt", 1.0, 0.85, 0.30)
            GameTooltip:AddLine(L["Click to inspect this character's overview, or right-click for actions."], 0.82, 0.86, 0.94, true)
            GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function(selfBtn)
            if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
        end)
        hit:SetScript("OnClick", function(selfBtn, button)
            local altKey = selfBtn._altKey
            if not altKey then return end
            local altRec = ns.db and ns.db.alts and ns.db.alts[altKey]
            if button == "RightButton" and altRec and openAltActionMenuFn then
                altRec.key = altKey
                openAltActionMenuFn(selfBtn, altRec)
                return
            end
            if panel._worldScope ~= "all" and type(altRec) == "table" then
                local matchesCurrentScope = Store and Store.AltMatchesWorldScope and Store:AltMatchesWorldScope(altRec, panel._worldScope)
                if not matchesCurrentScope then
                    panel._worldScope = "all"
                    if ns.db and ns.db.settings then
                        ns.db.settings.altsWorldScope = "all"
                    end
                end
            end
            panel._userPickedAlt = true
            panel._selectedKey = altKey
            panel._narrowTabPicked = true
            panel._subTab = "overview"
            panel:Refresh(true)
        end)
        row._headerHit = hit
    end
    row._headerHit._altKey = rowData.altKey
    row._headerHit._altName = rowData.altName
    row._headerHit:SetShown(rowData.altKey ~= nil and rowData.altKey ~= "")
end

function AltUI.MatchesItemFilter(panel, item)
    if type(item) ~= "table" then return false end
    local minQ = panel._minQuality or 0
    if minQ > 0 and (tonumber(item.quality) or 1) < minQ then
        return false
    end
    local cat = panel._itemCategory or "all"
    if cat ~= "all" then
        local c = tonumber(item.classID)
        local eq = (type(item.equipLoc) == "string" and item.equipLoc ~= "") or item._isEquip == true
        if cat == "equip" and not (eq or c == 2 or c == 4) then
            return false
        elseif cat == "consumable" and c ~= 0 then
            return false
        elseif cat == "trade" and c ~= 7 and c ~= 9 then
            return false
        elseif cat == "other" and (eq or c == 2 or c == 4 or c == 0 or c == 7 or c == 9) then
            return false
        end
    end
    return true
end

function AltUI.OpenItemFilterMenu(panel, selfBtn, getSelectedAltFn, renderItemsFn)
    local locOpts = {
        { id = "all", label = L["All"] },
        { id = "equip", label = L["Equipped"] },
        { id = "bags", label = L["Bags"] },
        { id = "bank", label = L["Bank"] },
        { id = "recipes", label = L["Recipes"] },
    }
    local catOpts = {
        { id = "all", label = L["All Types"] },
        { id = "equip", label = L["Gear / Equipment"] },
        { id = "consumable", label = L["Consumables"] },
        { id = "trade", label = L["Materials & Recipes"] },
        { id = "other", label = L["Quest / Misc"] },
    }
    local qualOpts = {
        { id = 0, label = L["Any Rarity"] },
        { id = 2, label = "|cff1eff00" .. L["Uncommon+"] .. "|r" },
        { id = 3, label = "|cff0070dd" .. L["Rare+"] .. "|r" },
        { id = 4, label = "|cffa335ee" .. L["Epic+"] .. "|r" },
    }
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            root:CreateTitle(L["Location"])
            for _, o in ipairs(locOpts) do
                root:CreateRadio(o.label, function() return panel._bagSource == o.id end, function()
                    panel._bagSource = o.id
                    if o.id == "recipes" then
                        panel._viewMode = "list"
                    end
                    renderItemsFn(getSelectedAltFn(), true)
                end)
            end
            root:CreateDivider()
            root:CreateTitle(L["Item Category"])
            for _, o in ipairs(catOpts) do
                root:CreateRadio(o.label, function() return (panel._itemCategory or "all") == o.id end, function()
                    panel._itemCategory = o.id
                    renderItemsFn(getSelectedAltFn(), true)
                end)
            end
            root:CreateDivider()
            root:CreateTitle(L["Minimum Rarity"])
            for _, o in ipairs(qualOpts) do
                root:CreateRadio(o.label, function() return (panel._minQuality or 0) == o.id end, function()
                    panel._minQuality = o.id
                    renderItemsFn(getSelectedAltFn(), true)
                end)
            end
            if panel._bagSource ~= "all" or (panel._itemCategory and panel._itemCategory ~= "all") or (panel._minQuality or 0) > 0 then
                root:CreateDivider()
                root:CreateButton(L["Reset Filters"], function()
                    panel._bagSource = "all"
                    panel._itemCategory = "all"
                    panel._minQuality = 0
                    renderItemsFn(getSelectedAltFn(), true)
                end)
            end
        end)
    else
        local idx = 1
        for i, o in ipairs(locOpts) do
            if o.id == panel._bagSource then idx = (i % #locOpts) + 1; break end
        end
        panel._bagSource = locOpts[idx].id
        renderItemsFn(getSelectedAltFn(), true)
    end
end

function AltUI.BuildRecipeSections(panel, altData, query)
    if not (ns.Alts and ns.Alts.SearchAllRecipes) then
        return {}, L["No learned recipes recorded yet."]
    end
    local onlyAltKey = (panel._allAltsScope ~= true and altData) and altData.key or nil
    local facFilter = panel._allAltsScope
        and (panel._includeOppositeFaction and "ALL" or ((altData and altData.faction) or (Compat.PlayerFaction and Compat.PlayerFaction())))
        or nil
    local wScope = panel._allAltsScope and AltUI.NormalizeWorldScope(panel._itemsWorldScope) or AltUI.NormalizeWorldScope(panel._worldScope)
    local groups = ns.Alts:SearchAllRecipes(query or "", onlyAltKey, facFilter, wScope)
    local sections = {}
    local dualFac = (facFilter == "ALL")
    local showWorldBadge = AltUI.NormalizeWorldScope(wScope) ~= "pool"

    if panel._allAltsScope then
        for _, g in ipairs(groups) do
            local hex = Compat.ClassHex(g.classFile)
            local facTag = ""
            if dualFac then
                facTag = (g.faction == "Alliance" and " |cff70b5ff[A]|r") or (g.faction == "Horde" and " |cffff7878[H]|r") or ""
            end
            local wBadge = FormatAltWorldBadge(g, showWorldBadge)
            sections[#sections + 1] = {
                title = hex .. (g.displayName or "?") .. "|r" .. facTag .. wBadge .. " |cffc6ceda(" .. #g.items .. ")|r",
                altKey = g.altKey,
                altName = g.displayName,
                items = g.items,
            }
        end
    elseif groups[1] and type(groups[1].items) == "table" then
        local byProf, profOrder = {}, {}
        for _, item in ipairs(groups[1].items) do
            local pn = (item._profName and item._profName ~= "") and item._profName or (item._profCode or L["Profession"])
            if not byProf[pn] then
                byProf[pn] = {}
                profOrder[#profOrder + 1] = pn
            end
            byProf[pn][#byProf[pn] + 1] = item
        end
        table.sort(profOrder)
        for _, pn in ipairs(profOrder) do
            local pItems = byProf[pn]
            sections[#sections + 1] = {
                title = ("|cffffd200%s|r |cffc6ceda(%d)|r"):format(pn, #pItems),
                items = pItems,
            }
        end
    end

    if #sections == 0 then
        local emptyMsg = (query and query ~= "")
            and L["No matching recipes found."]
            or L["No learned recipes recorded yet. Open a Profession window once to catalog recipes automatically."]
        return {}, emptyMsg
    end
    return sections, ""
end

AltUI.MAX_GRID_COLS = 14

function AltUI.NormalizeWorldScope(scopeMode)
    if Compat.NormalizeWorldScope then
        return Compat.NormalizeWorldScope(scopeMode)
    end
    return (scopeMode == "all") and "all" or "pool"
end

function AltUI.GetWorldScopeLabel(scopeMode)
    local norm = AltUI.NormalizeWorldScope(scopeMode)
    if norm == "all" then
        return L["All Worlds"]
    elseif norm:sub(1, 6) == "world:" then
        local rawWt = norm:sub(7)
        return (Compat.FormatWorldTypeLabel and Compat.FormatWorldTypeLabel(rawWt)) or rawWt
    elseif norm:sub(1, 5) == "pool:" then
        local wantPool = norm:sub(6)
        local recorded = (Store and Store.GetRecordedAltWorlds and Store:GetRecordedAltWorlds()) or {}
        for _, w in ipairs(recorded) do
            if w.scopeKey == norm or w.realmPool == wantPool then
                return w.displayLabel
            end
        end
        return wantPool
    end
    local _, _, curLabel = Compat.GetAltWorldInfo(nil)
    return curLabel or L["This World Only"]
end

function AltUI.PopulateWorldScopeMenu(root, panel)
    local _, _, curLabel = Compat.GetAltWorldInfo(nil)
    local recordedWorlds = (Store and Store.GetRecordedAltWorlds and Store:GetRecordedAltWorlds()) or {}
    local curScope = AltUI.NormalizeWorldScope(panel._worldScope)

    local function SetScope(nextScope)
        panel._worldScope = nextScope
        if ns.db and ns.db.settings then
            ns.db.settings.altsWorldScope = nextScope
        end
        panel:Refresh(true)
    end

    local thisWorldLbl = (curLabel and curLabel ~= "")
        and L["This World (%s)"]:format(curLabel)
        or L["This World Only"]
    root:CreateRadio(thisWorldLbl, function()
        return curScope == "pool"
    end, function()
        SetScope("pool")
    end)

    -- Add each distinct world/ruleset dynamically ONLY when at least 1 character record exists for it.
    if #recordedWorlds > 1 then
        for _, w in ipairs(recordedWorlds) do
            if (w.count or 0) > 0 then
                local wKey = w.scopeKey
                local wLbl = string.format("%s (%d)", w.displayLabel, w.count)
                root:CreateRadio(wLbl, function()
                    return curScope == wKey
                end, function()
                    SetScope(wKey)
                end)
            end
        end
    end

    local worldNames = {}
    for _, w in ipairs(recordedWorlds) do
        worldNames[#worldNames + 1] = w.displayLabel
    end
    local allWorldsLbl = (#worldNames > 1)
        and L["All Recorded Worlds (%s)"]:format(table.concat(worldNames, " + "))
        or L["All Worlds"]
    root:CreateRadio(allWorldsLbl, function()
        return curScope == "all"
    end, function()
        SetScope("all")
    end)

    if #recordedWorlds <= 1 then
        root:CreateTitle("|cff8b949e" .. L["Log in once on a character in PvE, RP PvE, or RP PvP to unlock its world filter here."] .. "|r")
    end
end

function AltUI.CycleWorldScope(panel)
    local order = { "pool" }
    local recordedWorlds = (Store and Store.GetRecordedAltWorlds and Store:GetRecordedAltWorlds()) or {}
    if #recordedWorlds > 1 then
        for _, w in ipairs(recordedWorlds) do
            if (w.count or 0) > 0 then
                order[#order + 1] = w.scopeKey
            end
        end
    end
    order[#order + 1] = "all"
    local cur = AltUI.NormalizeWorldScope(panel._worldScope)
    local nextIdx = 1
    for i, s in ipairs(order) do
        if s == cur then
            nextIdx = (i % #order) + 1
            break
        end
    end
    panel._worldScope = order[nextIdx]
    if ns.db and ns.db.settings then
        ns.db.settings.altsWorldScope = panel._worldScope
    end
    panel:Refresh(true)
end

function AltUI.AcquireGridCell(row, colIdx, onEnterFn, onLeaveFn, onClickFn)
    row._cells = row._cells or {}
    local cell = row._cells[colIdx]
    if cell then
        return cell
    end
    cell = CreateFrame("Button", nil, row, "BackdropTemplate")
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

    cell:SetScript("OnEnter", onEnterFn)
    cell:SetScript("OnLeave", onLeaveFn)
    cell:SetScript("OnClick", onClickFn)
    cell:Hide()
    row._cells[colIdx] = cell
    return cell
end

function AltUI.OpenScopeMenu(panel, selfBtn, getSelectedAltFn, renderItemsFn)
    local recordedWorlds = (Store and Store.GetRecordedAltWorlds and Store:GetRecordedAltWorlds()) or {}
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            root:CreateTitle(L["All Alts"])
            root:CreateRadio(L["This Alt"], function()
                return not panel._allAltsScope
            end, function()
                panel._allAltsScope = false
                renderItemsFn(getSelectedAltFn(), true)
            end)
            root:CreateRadio(L["All Alts (This World)"], function()
                return panel._allAltsScope == true and AltUI.NormalizeWorldScope(panel._itemsWorldScope) == "pool"
            end, function()
                panel._allAltsScope = true
                panel._itemsWorldScope = "pool"
                renderItemsFn(getSelectedAltFn(), true)
            end)
            if #recordedWorlds > 1 then
                for _, w in ipairs(recordedWorlds) do
                    if (w.count or 0) > 0 then
                        local wKey = w.scopeKey
                        local wLbl = L["All Alts (%s)"]:format(w.displayLabel)
                        root:CreateRadio(wLbl, function()
                            return panel._allAltsScope == true and AltUI.NormalizeWorldScope(panel._itemsWorldScope) == wKey
                        end, function()
                            panel._allAltsScope = true
                            panel._itemsWorldScope = wKey
                            renderItemsFn(getSelectedAltFn(), true)
                        end)
                    end
                end
            end
            root:CreateRadio(L["All Alts (All Worlds)"], function()
                return panel._allAltsScope == true and panel._itemsWorldScope == "all"
            end, function()
                panel._allAltsScope = true
                panel._itemsWorldScope = "all"
                renderItemsFn(getSelectedAltFn(), true)
            end)
            root:CreateDivider()
            root:CreateCheckbox(L["Include Opposite Faction"], function()
                return panel._includeOppositeFaction == true
            end, function()
                panel._includeOppositeFaction = not panel._includeOppositeFaction
                panel._allAltsScope = true
                renderItemsFn(getSelectedAltFn(), true)
            end)
        end)
    else
        if not panel._allAltsScope then
            panel._allAltsScope = true
            panel._itemsWorldScope = "pool"
        elseif panel._itemsWorldScope ~= "all" then
            panel._itemsWorldScope = "all"
        else
            panel._allAltsScope = false
            panel._itemsWorldScope = "pool"
        end
        renderItemsFn(getSelectedAltFn(), true)
    end
end

function AltUI.OpenWorldSortMenu(panel, selfBtn, sortModes, fallbackStep)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(selfBtn, function(_, root)
            root:CreateTitle(L["World / Ruleset"])
            AltUI.PopulateWorldScopeMenu(root, panel)
            root:CreateDivider()
            root:CreateTitle(L["Sort Alts"])
            for _, m in ipairs(sortModes) do
                local id = m.id
                root:CreateRadio(m.label, function()
                    return panel._sortBy == id
                end, function()
                    panel._sortBy = id
                    panel:Refresh(true)
                end)
            end
        end)
    elseif type(fallbackStep) == "function" then
        fallbackStep()
    end
end

local function FormatShortProfList(alt, compactMode)
    if type(alt and alt.professions) ~= "table" then return "-" end
    local parts = {}
    for _, pr in ipairs(alt.professions) do
        if pr and pr.name and pr.isPrimary then
            local pName = tostring(pr.name)
            if compactMode and #pName > 5 then
                pName = pName:sub(1, 4) .. "."
            end
            parts[#parts + 1] = ("%s %d"):format(pName, tonumber(pr.rank) or 0)
        end
    end
    return #parts > 0 and table.concat(parts, compactMode and "/" or " · ") or "-"
end

local function ComputeMatrixColBounds(rw, compact)
    local p1 = compact and 0.34 or 0.33
    local p2 = compact and 0.22 or 0.24
    local p3 = compact and 0.22 or 0.26
    local w1 = math.floor(rw * p1 + 0.5)
    local w2 = math.floor(rw * p2 + 0.5)
    local w3 = math.floor(rw * p3 + 0.5)
    local w4 = math.max(54, rw - w1 - w2 - w3)
    return { 0, w1, w1 + w2, w1 + w2 + w3, rw }, { w1, w2, w3, w4 }
end

function AltUI.CreateAccountMatrixPane(panel, subArea, AddHelpFn, openAltActionMenuFn, sortModes)
    local frame = CreateFrame("Frame", nil, subArea)
    frame:SetAllPoints()
    frame:Hide()

    local topBar = CreateFrame("Frame", nil, frame)
    topBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    topBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    topBar:SetHeight(26)

    local backBtn = Theme:CreateButton(topBar, 66, 22, "< " .. L["Alts"], "default")
    Theme:AutoFitButton(backBtn, 56, 10, 96)
    backBtn:SetPoint("LEFT", topBar, "LEFT", 0, 0)
    backBtn:SetScript("OnClick", function()
        panel._narrowTabPicked = true
        panel._subTab = "alts"
        panel:Refresh(true)
    end)
    backBtn:Hide()

    local helpBtn = AddHelpFn(
        topBar, topBar,
        L["Help: Account Summary Matrix"],
        L["Compares every character across level, live estimated rested XP, professions, ready craft cooldowns, free bag slots, pending mail, and gold at a glance."],
        L["Click any character row to jump straight to their profile, or right-click to copy Armory / remove old entries."],
        "RIGHT", "RIGHT", -2, 0
    )

    local matrixMode = "overview" -- "overview" | "resets"

    local modeBtn = Theme:CreateButton(topBar, 24, 20, "", "default")
    Theme:ConfigureIconButton(modeBtn, 24, 20, "Interface\\Icons\\INV_Misc_PocketWatch_01", {
        size = 14,
        toggle = true,
        active = false,
        activeColor = { 1.0, 0.82, 0.12 },
        tooltipFn = function()
            return (matrixMode == "resets") and L["View: Resets, Reputations & Marks"] or L["View: Level, Professions & Gold"],
                L["Click to toggle between Overview (XP/Profs/Gold) and Account Resets & Reputations Checklist."]
        end,
    })
    modeBtn:SetPoint("RIGHT", helpBtn or topBar, helpBtn and "LEFT" or "RIGHT", -4, 0)

    local sortBtn = Theme:CreateButton(topBar, 24, 20, "", "default")
    Theme:ConfigureIconButton(sortBtn, 24, 20, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", {
        size = 14,
        toggle = true,
        active = (panel._sortBy ~= "recent"),
        activeColor = { 0.35, 0.78, 1.0 },
        tooltipFn = function()
            local sortLbl = L["Sort: Recent"]
            for _, sm in ipairs(sortModes or {}) do
                if sm.id == panel._sortBy then
                    sortLbl = sm.label
                    break
                end
            end
            return sortLbl
        end,
    })
    sortBtn:SetPoint("RIGHT", modeBtn, "LEFT", -4, 0)
    sortBtn:SetScript("OnClick", function(selfBtn)
        AltUI.OpenWorldSortMenu(panel, selfBtn, sortModes or {})
    end)

    local titleLbl = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("LEFT", topBar, "LEFT", 4, 0)
    titleLbl:SetPoint("RIGHT", sortBtn, "LEFT", -6, 0)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetWordWrap(false)
    titleLbl:SetTextColor(1.0, 0.82, 0.0)

    local kpiBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    kpiBar:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -2)
    kpiBar:SetPoint("TOPRIGHT", topBar, "BOTTOMRIGHT", 0, -2)
    kpiBar:SetHeight(24)
    kpiBar._scNoStone = true
    Theme:ApplyBackdrop(kpiBar, "surface")
    kpiBar:EnableMouse(true)
    kpiBar:SetScript("OnEnter", function(selfBar)
        ShowGoldBreakdownTooltip(selfBar, panel._worldScope)
    end)
    kpiBar:SetScript("OnLeave", function(selfBar)
        if GameTooltip and GameTooltip:IsOwned(selfBar) then GameTooltip:Hide() end
    end)

    local kpiLeft = kpiBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    kpiLeft:SetPoint("LEFT", kpiBar, "LEFT", 8, 0)
    kpiLeft:SetJustifyH("LEFT")
    kpiLeft:SetWordWrap(false)

    local kpiRight = kpiBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    kpiRight:SetPoint("RIGHT", kpiBar, "RIGHT", -8, 0)
    kpiRight:SetPoint("LEFT", kpiLeft, "RIGHT", 6, 0)
    kpiRight:SetJustifyH("RIGHT")
    kpiRight:SetWordWrap(false)

    local colHeader = CreateFrame("Frame", nil, frame)
    colHeader:SetHeight(20)
    local colHdrBg = colHeader:CreateTexture(nil, "BACKGROUND", nil, -4)
    colHdrBg:SetAllPoints()
    colHdrBg:SetTexture(WHITE8X8)
    colHdrBg:SetVertexColor(0.14, 0.11, 0.08, 1.0)
    local colHdrLine = colHeader:CreateTexture(nil, "ARTWORK", nil, 1)
    colHdrLine:SetHeight(1)
    colHdrLine:SetPoint("BOTTOMLEFT", colHeader, "BOTTOMLEFT", 0, 0)
    colHdrLine:SetPoint("BOTTOMRIGHT", colHeader, "BOTTOMRIGHT", 0, 0)
    colHdrLine:SetTexture(WHITE8X8)
    colHdrLine:SetVertexColor(0.68, 0.54, 0.24, 0.85)

    local colSpecs = {
        { id = "char", title = L["Character"],   align = "LEFT",  sortId = "level", altSortId = "name" },
        { id = "xp",   title = L["Experience"],  align = "LEFT",  sortId = "rested" },
        { id = "prof", title = L["Professions"], align = "LEFT",  sortId = "mail",  altSortId = "recent" },
        { id = "gold", title = L["Gold"],        align = "RIGHT", sortId = "gold" },
    }
    local colBtns, colHdrDivs = {}, {}
    for ci, sp in ipairs(colSpecs) do
        local cb = CreateFrame("Button", nil, colHeader)
        cb:SetHeight(20)
        local hl = cb:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1.0, 0.82, 0.25, 0.12)
        cb.lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cb.lbl:SetPoint("LEFT", cb, "LEFT", 5, 0)
        cb.lbl:SetPoint("RIGHT", cb, "RIGHT", -5, 0)
        cb.lbl:SetJustifyH(sp.align)
        cb.lbl:SetWordWrap(false)
        cb._spec = sp
        cb:SetScript("OnClick", function()
            if sp.altSortId and panel._sortBy == sp.sortId then
                panel._sortBy = sp.altSortId
            else
                panel._sortBy = sp.sortId
            end
            panel:Refresh(true)
        end)
        colBtns[ci] = cb
        if ci > 1 then
            local dv = colHeader:CreateTexture(nil, "ARTWORK", nil, 2)
            dv:SetSize(1, 14)
            colHdrDivs[ci - 1] = dv
        end
    end

    local matrixState = { totalMoney = 0, compact = false, listW = 308 }

    local function LayoutRowCols(row, rw)
        local compact = (rw < 450)
        if row._lastColW == rw and row._lastColCompact == compact then
            return
        end
        row._lastColW = rw
        row._lastColCompact = compact
        local bounds = ComputeMatrixColBounds(rw, compact)
        for di = 1, 3 do
            local dv = row.colDivs[di]
            if dv then
                dv:ClearAllPoints()
                dv:SetPoint("TOPLEFT", row, "TOPLEFT", bounds[di + 1], -5)
                dv:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", bounds[di + 1], 5)
            end
        end
        row.classIcon:ClearAllPoints()
        row.classIcon:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.col1Top:ClearAllPoints()
        row.col1Top:SetPoint("TOPLEFT", row.classIcon, "TOPRIGHT", 5, 2)
        row.col1Top:SetPoint("RIGHT", row, "LEFT", bounds[2] - 4, 0)
        row.col1Bot:ClearAllPoints()
        row.col1Bot:SetPoint("BOTTOMLEFT", row.classIcon, "BOTTOMRIGHT", 5, -2)
        row.col1Bot:SetPoint("RIGHT", row, "LEFT", bounds[2] - 4, 0)

        row.xpBarBg:ClearAllPoints()
        row.xpBarBg:SetPoint("TOPLEFT", row, "TOPLEFT", bounds[2] + 5, -8)
        row.xpBarBg:SetPoint("RIGHT", row, "LEFT", bounds[3] - 5, 0)
        row.xpBarBg:SetHeight(12)
        row._c2x = bounds[2] + 5
        row._c2w = math.max(40, bounds[3] - bounds[2] - 9)
        row.col2Bot:ClearAllPoints()
        row.col2Bot:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", bounds[2] + 5, 6)
        row.col2Bot:SetPoint("RIGHT", row, "LEFT", bounds[3] - 4, 0)

        row.col3Top:ClearAllPoints()
        row.col3Top:SetPoint("TOPLEFT", row, "TOPLEFT", bounds[3] + 5, -7)
        row.col3Top:SetPoint("RIGHT", row, "LEFT", bounds[4] - 4, 0)
        row.col3Bot:ClearAllPoints()
        row.col3Bot:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", bounds[3] + 5, 6)
        row.col3Bot:SetPoint("RIGHT", row, "LEFT", bounds[4] - 4, 0)

        row.col4Top:ClearAllPoints()
        row.col4Top:SetPoint("TOPLEFT", row, "TOPLEFT", bounds[4] + 3, -7)
        row.col4Top:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.col4Bot:ClearAllPoints()
        row.col4Bot:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", bounds[4] + 3, 6)
        row.col4Bot:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    end

    local scroll = Theme:CreateScrollList(frame, 48, function(rowParent, _, rowHeight)
        local row = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
        row:SetHeight(rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1.0, 0.82, 0.25, 0.12)

        row.statusBar = row:CreateTexture(nil, "ARTWORK", nil, 2)
        row.statusBar:SetWidth(3)
        row.statusBar:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -4)
        row.statusBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 4)

        row.colDivs = {}
        for di = 1, 3 do
            local dv = row:CreateTexture(nil, "ARTWORK", nil, 1)
            dv:SetWidth(1)
            dv:SetColorTexture(0.65, 0.54, 0.30, 0.16)
            row.colDivs[di] = dv
        end

        row.classIcon = row:CreateTexture(nil, "ARTWORK", nil, 2)
        row.classIcon:SetSize(18, 18)
        row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")

        row.col1Top = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.col1Top:SetJustifyH("LEFT")
        row.col1Top:SetWordWrap(false)

        row.col1Bot = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.col1Bot:SetJustifyH("LEFT")
        row.col1Bot:SetWordWrap(false)

        row.xpBarBg = CreateFrame("Frame", nil, row)
        row.xpBarBg.tex = row.xpBarBg:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.xpBarBg.tex:SetAllPoints()
        row.xpBarBg.tex:SetColorTexture(0.04, 0.04, 0.05, 0.90)
        row.xpBarRest = row.xpBarBg:CreateTexture(nil, "BORDER", nil, 1)
        row.xpBarRest:SetPoint("TOPLEFT", 0, 0)
        row.xpBarRest:SetPoint("BOTTOMLEFT", 0, 0)
        row.xpBarRest:SetColorTexture(0.24, 0.56, 0.96, 0.52)
        row.xpBarFill = row.xpBarBg:CreateTexture(nil, "ARTWORK", nil, 1)
        row.xpBarFill:SetPoint("TOPLEFT", 0, 0)
        row.xpBarFill:SetPoint("BOTTOMLEFT", 0, 0)
        row.col2Top = row.xpBarBg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.col2Top:SetAllPoints()
        row.col2Top:SetJustifyH("CENTER")
        row.col2Top:SetJustifyV("MIDDLE")
        row.col2Top:SetWordWrap(false)

        row.col2Bot = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.col2Bot:SetJustifyH("LEFT")
        row.col2Bot:SetWordWrap(false)

        row.col3Top = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.col3Top:SetJustifyH("LEFT")
        row.col3Top:SetWordWrap(false)

        row.col3Bot = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.col3Bot:SetJustifyH("LEFT")
        row.col3Bot:SetWordWrap(false)

        row.col4Top = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.col4Top:SetJustifyH("RIGHT")
        row.col4Top:SetWordWrap(false)

        row.col4Bot = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.col4Bot:SetJustifyH("RIGHT")
        row.col4Bot:SetWordWrap(false)

        row:SetScript("OnEnter", function(selfRow) ShowAltTooltip(selfRow, selfRow._alt) end)
        row:SetScript("OnLeave", function(selfRow)
            if GameTooltip and GameTooltip:IsOwned(selfRow) then GameTooltip:Hide() end
        end)
        row:SetScript("OnClick", function(selfRow, button)
            local alt = selfRow._alt
            if not alt then return end
            if button == "RightButton" then
                openAltActionMenuFn(selfRow, alt)
                return
            end
            panel._userPickedAlt = true
            panel._selectedKey = alt.key
            panel._narrowTabPicked = true
            panel._subTab = "overview"
            panel:Refresh(true)
        end)
        return row
    end, function(row, alt, _, pal)
        row._alt = alt
        local rw = math.floor((row.GetWidth and row:GetWidth()) or 0)
        if rw < 180 then rw = matrixState.listW or 308 end
        LayoutRowCols(row, rw)
        local compact = (rw < 450)
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
        local facIco = (fac and Compat.FactionIconMarkup and Compat.FactionIconMarkup(fac, 11)) or ""
        local hex = Compat.ClassHex(alt.classFile)
        local disp = alt.fullName or alt.name or alt.key or "?"
        local lvl = tonumber(alt.level) or 0
        local wBadge = FormatAltWorldBadge(alt, panel._worldScope == "all")
        row.col1Top:SetText(("%s%s%s|r"):format(facIco, hex, disp))

        local lvlCol = (lvl >= 60) and "|cff3fb950" or "|cffd8dde6"
        local ilvlTag = (not compact and alt.itemLevel and alt.itemLevel > 0) and (" · iLvl " .. math.floor(alt.itemLevel)) or ""
        local curTag = isCurrent and (" |cff3fb950[" .. L["Current"] .. "]|r") or wBadge
        row.col1Bot:SetText(lvlCol .. L["Lv %d"]:format(lvl) .. "|r" .. ilvlTag .. curTag)

        -- Col 2..4: Overview vs Resets & Reputations checklist
        local lockCount = (ns.Alts and ns.Alts.GetLockouts) and #ns.Alts:GetLockouts(alt) or 0
        local hasReadyCraft = (ns.Alts and ns.Alts.HasReadyCraftCooldown and ns.Alts:HasReadyCraftCooldown(alt)) == true
        local hasMail, ageDays = false, 0
        if ns.Alts and ns.Alts.GetMailStatus then
            hasMail, ageDays = ns.Alts:GetMailStatus(alt)
        end
        if matrixMode == "resets" then
            row.xpBarBg:Hide()
            row.col2Top:SetParent(row)
            row.col2Top:ClearAllPoints()
            row.col2Top:SetPoint("TOPLEFT", row, "TOPLEFT", row._c2x or 100, -4)
            row.col2Top:SetWidth(row._c2w or 70)
            row.col2Top:SetJustifyH("LEFT")
            row.col2Top:SetText((lockCount > 0) and ("|cffff9b3d" .. L["%d lockouts"]:format(lockCount) .. "|r") or ("|cff3fb950" .. L["No lockouts"] .. "|r"))
            row.col2Bot:SetText(hasReadyCraft and ("|cff3fb950" .. L["Craft Ready"] .. "|r") or ("|cff8d98a6" .. L["No ready CD"] .. "|r"))

            local reps = (ns.Alts and ns.Alts.GetReputations) and ns.Alts:GetReputations(alt) or {}
            local topRep = reps[1]
            if topRep then
                local stLbl = (ns.Alts and ns.Alts.GetStandingLabel) and ns.Alts:GetStandingLabel(topRep.standing) or ""
                row.col3Top:SetText("|cff7ee787" .. tostring(topRep.name) .. "|r")
                row.col3Bot:SetText("|cff9da7b5" .. stLbl .. " (" .. tostring(#reps) .. ")|r")
            else
                row.col3Top:SetText("|cff8d98a6-|r")
                row.col3Bot:SetText("|cff8d98a6" .. L["No rep cached"] .. "|r")
            end

            local marks = (ns.Alts and ns.Alts.GetMarks) and ns.Alts:GetMarks(alt) or {}
            local totMarks = 0
            for _, mk in ipairs(marks) do
                totMarks = totMarks + (tonumber(mk.count) or 0)
            end
            row.col4Top:SetText((totMarks > 0) and ("|cffffd24d" .. L["%d marks"]:format(totMarks) .. "|r") or "|cff8d98a60|r")
            if hasMail then
                row.col4Bot:SetText("|cffffb833" .. L["Mailbox"] .. (ageDays >= 15 and (" " .. ageDays .. "d") or "") .. "|r")
            else
                local dPct = tonumber(alt.durabilityPct)
                row.col4Bot:SetText(dPct and ("|cff9da7b5" .. math.floor(dPct + 0.5) .. "% dur|r") or "|cff6e7681-|r")
            end
            return
        end

        row.xpBarBg:Show()
        row.col2Top:SetParent(row.xpBarBg)
        row.col2Top:ClearAllPoints()
        row.col2Top:SetAllPoints()
        row.col2Top:SetJustifyH("CENTER")

        -- Col 2: Visual Mini XP/Rested Progress Bar + Lockouts or Activity
        local barW = math.max(36, math.floor((row._c2w or row.xpBarBg:GetWidth() or 60) + 0.5))
        if lvl >= 60 then
            row.xpBarFill:SetColorTexture(0.22, 0.72, 0.38, 0.85)
            row.xpBarFill:SetWidth(barW)
            row.xpBarRest:Hide()
            row.col2Top:SetText(compact and L["Lv %d"]:format(60) or L["Max Level"])
        else
            local xpVal = tonumber(alt.xp) or 0
            local xpMax = math.max(1, tonumber(alt.xpMax) or 1)
            local rawXpFrac = math.max(0, math.min(1, xpVal / xpMax))
            local xpPct = math.floor(rawXpFrac * 100 + 0.5)
            local xpFrac = math.max(0.02, rawXpFrac)
            local restPct = ResolveAltRestedInfo(alt)
            row.xpBarFill:SetColorTexture(0.56, 0.32, 0.86, 0.90)
            row.xpBarFill:SetWidth(math.max(2, math.floor(barW * xpFrac)))
            if restPct > 0 then
                local combFrac = math.min(1, rawXpFrac + (restPct / 100))
                row.xpBarRest:SetWidth(math.max(2, math.floor(barW * combFrac)))
                row.xpBarRest:Show()
                row.col2Top:SetText(("%d%% +%d%%"):format(xpPct, restPct))
            else
                row.xpBarRest:Hide()
                row.col2Top:SetText(("%d%%"):format(xpPct))
            end
        end
        if lockCount > 0 then
            row.col2Bot:SetText("|cffff9b3d" .. L["%d lockouts"]:format(lockCount) .. "|r")
        else
            local seenStr = isCurrent and ("|cff3fb950" .. L["Current"] .. "|r") or Compat.FormatRelativeTime(alt.lastActive, L)
            local locOrTime = (not compact and alt.zone and alt.zone ~= "") and alt.zone or seenStr
            row.col2Bot:SetText("|cff8d98a6" .. locOrTime .. "|r")
        end

        -- Col 3: Professions + Craft Cooldown + Free Bags + Mail
        local profStr = FormatShortProfList(alt, compact)
        if hasReadyCraft then
            profStr = (profStr ~= "-" and (profStr .. " ") or "") .. "|cff3fb950[" .. L["Ready"] .. "]|r"
        end
        row.col3Top:SetText(profStr)

        local bagFree = tonumber(alt.bagFree) or 0
        local bagCol = (bagFree <= 1 and (alt.bagTotal or 0) > 0) and "|cfff54747" or ((bagFree <= 5 and (alt.bagTotal or 0) > 0) and "|cffffb833" or "|cff9da7b5")
        local bagPart = bagCol .. L["%d free"]:format(bagFree) .. "|r"
        if hasMail then
            local mCol = (ageDays >= 15) and "|cfff54747" or "|cffffd24d"
            bagPart = bagPart .. " " .. mCol .. "[" .. L["Mailbox"] .. (ageDays >= 15 and (" " .. ageDays .. "d") or "") .. "]|r"
        end
        row.col3Bot:SetText(bagPart)

        -- Col 4: Gold + % share
        row.col4Top:SetText(Compat.FormatMoney(alt.money or 0))
        local pct = (matrixState.totalMoney > 0) and math.floor(((tonumber(alt.money) or 0) / matrixState.totalMoney) * 100 + 0.5) or 0
        row.col4Bot:SetText((matrixState.totalMoney > 0) and ("|cffffd24d" .. pct .. "%|r") or "")
    end)

    colHeader:SetPoint("TOPLEFT", kpiBar, "BOTTOMLEFT", 3, -3)
    colHeader:SetPoint("TOPRIGHT", kpiBar, "BOTTOMRIGHT", -13, -3)
    scroll.container:ClearAllPoints()
    scroll.container:SetPoint("TOPLEFT", kpiBar, "BOTTOMLEFT", 0, -24)
    scroll.container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

    local function UpdateColHeadersAndTheme()
        local p = Theme:GetPalette()
        local isBlizz = Theme:IsBlizzard(p) or (p and p.key == "native")
        if isBlizz then
            colHdrBg:SetVertexColor(0.16, 0.12, 0.08, 1.0)
            colHdrLine:SetVertexColor(0.74, 0.58, 0.24, 0.90)
        else
            colHdrBg:SetVertexColor(0.11, 0.13, 0.17, 1.0)
            colHdrLine:SetVertexColor(0.30, 0.62, 0.95, 0.65)
        end
        local hdrW = math.max(260, math.floor((colHeader:GetWidth() or (frame:GetWidth() or 320) - 16) + 0.5))
        local hdrChanged = (matrixState.lastHdrW == nil) or (math.abs(matrixState.lastHdrW - hdrW) >= 2)
        matrixState.lastHdrW = hdrW
        local compact = (hdrW < 450)
        matrixState.listW = hdrW
        matrixState.compact = compact
        local bounds, widths = ComputeMatrixColBounds(hdrW, compact)
        for ci, cb in ipairs(colBtns) do
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", colHeader, "TOPLEFT", bounds[ci], 0)
            cb:SetWidth(widths[ci])
            local sp = cb._spec
            local hdrTitle = sp.title
            if matrixMode == "resets" then
                if sp.id == "xp" then hdrTitle = L["Resets"]
                elseif sp.id == "prof" then hdrTitle = L["Reputations"]
                elseif sp.id == "gold" then hdrTitle = L["Marks"]
                end
            end
            local isActive = (panel._sortBy == sp.sortId) or (sp.altSortId and panel._sortBy == sp.altSortId)
            local arrow = isActive and " v" or ""
            cb.lbl:SetText(hdrTitle .. arrow)
            if isActive then
                if isBlizz then
                    cb.lbl:SetTextColor(1.0, 0.85, 0.22)
                else
                    local ac = (p and p.accentBorder) or { 0.35, 0.78, 1.0 }
                    cb.lbl:SetTextColor(ac[1], ac[2], ac[3])
                end
            else
                local tc = (p and p.textMuted) or { 0.78, 0.80, 0.84 }
                cb.lbl:SetTextColor(tc[1], tc[2], tc[3])
            end
            if ci > 1 and colHdrDivs[ci - 1] then
                colHdrDivs[ci - 1]:ClearAllPoints()
                colHdrDivs[ci - 1]:SetPoint("LEFT", colHeader, "LEFT", bounds[ci], 0)
                if isBlizz then
                    colHdrDivs[ci - 1]:SetColorTexture(0.70, 0.56, 0.28, 0.35)
                else
                    colHdrDivs[ci - 1]:SetColorTexture(0.30, 0.62, 0.95, 0.32)
                end
            end
        end
        return hdrChanged
    end

    colHeader:HookScript("OnSizeChanged", function()
        local w = math.floor((colHeader:GetWidth() or 0) + 0.5)
        if w >= 260 and ((matrixState.lastHdrW == nil) or (math.abs(matrixState.lastHdrW - w) >= 2)) then
            if UpdateColHeadersAndTheme() and panel.Refresh then
                panel:Refresh(false)
            end
        end
    end)

    return {
        frame = frame,
        scroll = scroll,
        summaryLbl = titleLbl,
        backBtn = backBtn,
        helpBtn = helpBtn,
        RefreshTheme = function()
            Theme:StyleButton(backBtn, "default")
            Theme:StyleButton(modeBtn, "default")
            Theme:StyleButton(sortBtn, "default")
            Theme:ApplyBackdrop(kpiBar, "surface")
            if helpBtn and helpBtn.RefreshTheme then helpBtn:RefreshTheme() end
            UpdateColHeadersAndTheme()
            scroll:RefreshTheme()
        end,
        Render = function(list, isNarrow, resetScroll)
            if not modeBtn._scClickWired then
                modeBtn._scClickWired = true
                modeBtn:SetScript("OnClick", function()
                    matrixMode = (matrixMode == "resets") and "overview" or "resets"
                    Theme:SetIconToggle(modeBtn, matrixMode == "resets", { 1.0, 0.82, 0.12 })
                    panel:Refresh(false)
                end)
            end
            Theme:SetIconToggle(modeBtn, matrixMode == "resets", { 1.0, 0.82, 0.12 })
            backBtn:SetShown(isNarrow)
            titleLbl:ClearAllPoints()
            if isNarrow then
                titleLbl:SetPoint("LEFT", backBtn, "RIGHT", 6, 0)
            else
                titleLbl:SetPoint("LEFT", topBar, "LEFT", 4, 0)
            end
            titleLbl:SetPoint("RIGHT", sortBtn, "LEFT", -6, 0)
            titleLbl:SetText(("%s (%d)"):format(matrixMode == "resets" and L["Resets & Reputations"] or L["Account Matrix"], #list))

            Theme:SetIconToggle(sortBtn, panel._sortBy ~= "recent", { 0.35, 0.78, 1.0 })

            local totMoney, totFree, maxRestedCnt, readyCraftCnt = 0, 0, 0, 0
            for _, alt in ipairs(list) do
                totMoney = totMoney + (tonumber(alt.money) or 0)
                totFree = totFree + (tonumber(alt.bagFree) or 0)
                if (tonumber(alt.level) or 0) < 60 and ResolveAltRestedInfo(alt) >= 100 then
                    maxRestedCnt = maxRestedCnt + 1
                end
                if ns.Alts and ns.Alts.HasReadyCraftCooldown and ns.Alts:HasReadyCraftCooldown(alt) then
                    readyCraftCnt = readyCraftCnt + 1
                end
            end
            matrixState.totalMoney = totMoney
            kpiLeft:SetText("|cffffd200" .. Compat.FormatMoney(totMoney) .. "|r")

            local rParts = { L["Bags Free: %d"]:format(totFree) }
            if maxRestedCnt > 0 then
                rParts[#rParts + 1] = "|cff58a6ff" .. L["Rested 100%%+: %d"]:format(maxRestedCnt) .. "|r"
            end
            if readyCraftCnt > 0 then
                rParts[#rParts + 1] = "|cff3fb950" .. L["Crafts Ready: %d"]:format(readyCraftCnt) .. "|r"
            end
            kpiRight:SetText(table.concat(rParts, " · "))

            UpdateColHeadersAndTheme()
            scroll:SetData(list, L["No characters recorded yet."], resetScroll)
        end,
    }
end

function SocialPanels:CreateAltsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel:Hide()
    panel._bagSource = "all" -- "all" | "equip" | "bags" | "bank"
    panel._itemCategory = "all" -- "all" | "equip" | "consumable" | "trade" | "other"
    panel._minQuality = 0
    panel._allAltsScope = false
    panel._includeOppositeFaction = false
    panel._itemsWorldScope = AltUI.NormalizeWorldScope(ns.db and ns.db.settings and ns.db.settings.altsWorldScope)
    panel._worldScope = AltUI.NormalizeWorldScope(ns.db and ns.db.settings and ns.db.settings.altsWorldScope)
    panel._viewMode = "grid" -- "grid" | "list"
    panel._sortBy = "recent" -- "recent" | "gold" | "level" | "rested" | "mail" | "name"
    panel._subTab = "overview" -- "alts" (narrow only) | "overview" | "items" | "gear" | "account"
    panel._narrowTabPicked = false
    panel._selectedKey = CurrentAltKey()
    panel._userPickedAlt = false

    local SORT_MODES = {
        { id = "recent", label = L["Sort: Recent"] },
        { id = "gold", label = L["Sort: Gold"] },
        { id = "level", label = L["Sort: Level"] },
        { id = "rested", label = L["Sort: Rested"] },
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
        local list = GetSortedAltsList(panel._sortBy, panel._worldScope)
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
                root:CreateButton(L["Account Matrix"], function()
                    panel._narrowTabPicked = true
                    panel._subTab = "account"
                    panel:Refresh(true)
                end)
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

    panel._worldBtn = Theme:CreateButton(topBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(panel._worldBtn, 24, 22, "Interface\\Icons\\INV_Misc_Map_01", {
        size = 14,
        toggle = true,
        active = (AltUI.NormalizeWorldScope(panel._worldScope) ~= "pool"),
        activeColor = { 0.35, 0.78, 1.0 },
    })
    panel._worldBtn:SetPoint("LEFT", charHelpBtn or charBtn, "RIGHT", 6, 0)
    panel._worldBtn:SetScript("OnClick", function(selfBtn)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                root:CreateTitle(L["World / Ruleset"])
                AltUI.PopulateWorldScopeMenu(root, panel)
            end)
        else
            AltUI.CycleWorldScope(panel)
        end
    end)
    panel._worldBtn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        local curW = AltUI.GetWorldScopeLabel(panel._worldScope)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["World / Ruleset"], 1, 0.9, 0.55, true)
        GameTooltip:AddLine(L["Show characters from this realm ruleset only or include other WoW Forever worlds (PvP / PvE)."] .. " (" .. tostring(curW) .. ")", 0.85, 0.88, 0.94, true)
        GameTooltip:AddLine(L["Log in once on a character in PvE, RP PvE, or RP PvP to unlock its world filter here."], 0.68, 0.82, 0.96, true)
        GameTooltip:Show()
    end)
    panel._worldBtn:SetScript("OnLeave", function(selfBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then GameTooltip:Hide() end
    end)

    -- Narrow Sub-Tab Strip (Alts | Overview | Items | Gear | Account)
    local narrowTabBar = CreateFrame("Frame", nil, panel)
    narrowTabBar:SetHeight(24)
    narrowTabBar:Hide()

    local btnNarrowAlts = Theme:CreateButton(narrowTabBar, 70, 22, L["Alts"], "tab")
    local btnNarrowOverview = Theme:CreateButton(narrowTabBar, 68, 22, L["Overview"], "tab")
    local btnNarrowItems = Theme:CreateButton(narrowTabBar, 58, 22, L["Items"], "tab")
    local btnNarrowGear = Theme:CreateButton(narrowTabBar, 68, 22, L["Gear"], "tab")
    local btnNarrowAccount = Theme:CreateButton(narrowTabBar, 58, 22, L["Account"], "tab")

    -- Left Column: All Account Alts Roster + Gold Vault Footer
    local rosterPane = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    Theme:ApplyBackdrop(rosterPane, "surface")
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

    local rosterSortBtn = Theme:CreateButton(rosterHeader, 24, 20, "", "default")
    Theme:ConfigureIconButton(rosterSortBtn, 24, 20, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", {
        size = 17,
        toggle = true,
        active = (panel._sortBy ~= "recent"),
        activeColor = { 0.35, 0.78, 1.0 },
        tooltipFn = function()
            return GetSortLabel(panel._sortBy)
        end,
    })
    rosterSortBtn:SetPoint("RIGHT", rosterHelpBtn or rosterHeader, rosterHelpBtn and "LEFT" or "RIGHT", -4, 0)

    local rosterAccountBtn = Theme:CreateButton(rosterHeader, 62, 20, L["Account"], "default")
    Theme:AutoFitButton(rosterAccountBtn, 52, 10, 82)
    rosterAccountBtn:SetHeight(20)
    rosterAccountBtn:SetPoint("RIGHT", rosterSortBtn, "LEFT", -4, 0)
    rosterAccountBtn:Hide()

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

    CreateRosterWorldHintBar(panel, rosterPane, goldBar)

    goldBar:SetScript("OnEnter", function(selfBar)
        ShowGoldBreakdownTooltip(selfBar, panel._worldScope)
    end)
    goldBar:SetScript("OnLeave", function(selfBar)
        if GameTooltip and GameTooltip:IsOwned(selfBar) then GameTooltip:Hide() end
    end)

    local rosterScroll = Theme:CreateScrollList(rosterPane, 58, function(rowParent, _, rowHeight)
        local row = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
        row:SetHeight(rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.94, 0.78, 0.06)

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
        if ns.Alts and ns.Alts.HasReadyCraftCooldown and ns.Alts:HasReadyCraftCooldown(alt) then
            badgeParts[#badgeParts + 1] = "|cff3fb950[" .. L["Craft Ready"] .. "]|r"
        end
        if lvl < 60 then
            local rPct, isEst = ResolveAltRestedInfo(alt)
            if rPct > 0 then
                local pref = isEst and "~" or ""
                badgeParts[#badgeParts + 1] = (rPct >= 148)
                    and ("|cff58a6ff[" .. L["150% MAX"] .. "]|r")
                    or ("|cff58a6ff[" .. pref .. rPct .. "%]|r")
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
        local wBadge = FormatAltWorldBadge(alt, AltUI.NormalizeWorldScope(panel._worldScope) ~= "pool")
        if wBadge ~= "" then
            zoneStr = wBadge:gsub("^%s+", "") .. " " .. zoneStr
        end
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
    Theme:ApplyBackdrop(inspectorPane, "surface")
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
        L["Displays the selected character's full profile and character management actions."],
        L["Click 'Actions' to view the Web Armory link or remove an offline alt, and switch between 'Overview', 'Items', 'Gear', and 'Account' below."],
        "RIGHT",
        "RIGHT",
        -6,
        0,
        {
            target = charHeader,
            steps = {
                {
                    title = L["Alts Roster & Gold Vault"],
                    tag = "1/3 · " .. L["Alts"],
                    text = L["Select any character in your roster on the left to inspect them, or hover the bottom Gold Vault bar to see total realm gold across all alts."],
                    target = function()
                        if rosterPane and rosterPane:IsShown() then
                            return rosterPane
                        end
                        return narrowTabBar:IsShown() and narrowTabBar or charHeader
                    end,
                },
                {
                    title = L["Help: Character Inspector & Actions"],
                    tag = "2/3 · " .. L["Character"],
                    text = L["This header displays the active character's level, class, zone, and Armory/management menu via Actions."],
                    target = charHeader,
                },
                {
                    title = L["Overview, Items, Gear & Account Matrix"],
                    tag = "3/3 · " .. L["Account"],
                    text = L["Switch between Overview (XP, currencies, reps), Items (bags & bank across alts), Equipped Gear, and the Account Matrix of reputations, marks & raid lockouts."],
                    target = inspectorPane,
                },
            },
        }
    )
    panel._scHelpBtn = headerHelpBtn

    local btnActions = Theme:CreateButton(charHeader, 76, 22, L["Actions"] .. "  v", "default")
    Theme:AutoFitButton(btnActions, 64, 12, 108)
    btnActions:SetPoint("RIGHT", headerHelpBtn or charHeader, headerHelpBtn and "LEFT" or "RIGHT", -4, 0)

    local charTitleLbl = charHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    charTitleLbl:SetPoint("TOPLEFT", charIcon, "TOPRIGHT", 8, -1)
    charTitleLbl:SetPoint("RIGHT", btnActions, "LEFT", -8, 0)
    charTitleLbl:SetJustifyH("LEFT")
    charTitleLbl:SetWordWrap(false)

    local charSubLbl = charHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charSubLbl:SetPoint("BOTTOMLEFT", charIcon, "BOTTOMRIGHT", 8, 1)
    charSubLbl:SetPoint("RIGHT", btnActions, "LEFT", -8, 0)
    charSubLbl:SetJustifyH("LEFT")
    charSubLbl:SetWordWrap(false)
    AltUI.AttachHeaderTooltip(charHeader, panel)

    -- Wide Sub-Tabs Bar (Overview | Items | Gear | Account)
    local wideTabBar = CreateFrame("Frame", nil, inspectorPane)
    wideTabBar:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 4, -4)
    wideTabBar:SetPoint("TOPRIGHT", charHeader, "BOTTOMRIGHT", -4, -4)
    wideTabBar:SetHeight(26)

    local btnWideOverview = Theme:CreateButton(wideTabBar, 82, 22, L["Overview"], "tab")
    Theme:AutoFitButton(btnWideOverview, 68, 12, 108)
    btnWideOverview:SetPoint("LEFT", wideTabBar, "LEFT", 2, 0)

    local btnWideItems = Theme:CreateButton(wideTabBar, 74, 22, L["Items"], "tab")
    Theme:AutoFitButton(btnWideItems, 60, 12, 98)
    btnWideItems:SetPoint("LEFT", btnWideOverview, "RIGHT", 4, 0)

    local btnWideGear = Theme:CreateButton(wideTabBar, 80, 22, L["Gear"], "tab")
    Theme:AutoFitButton(btnWideGear, 64, 12, 108)
    btnWideGear:SetPoint("LEFT", btnWideItems, "RIGHT", 4, 0)

    local btnWideAccount = Theme:CreateButton(wideTabBar, 74, 22, L["Account"], "tab")
    Theme:AutoFitButton(btnWideAccount, 60, 12, 98)
    btnWideAccount:SetPoint("LEFT", btnWideGear, "RIGHT", 4, 0)

    local wideSummaryLbl = wideTabBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wideSummaryLbl:SetPoint("LEFT", btnWideAccount, "RIGHT", 8, 0)
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
    local syncOverviewScrollUI, refreshOverviewThumb = AltUI.CreateOverviewScrollbar(overviewFrame, overviewScroll)
    local accountMatrix = AltUI.CreateAccountMatrixPane(panel, subArea, AddHelp, OpenAltActionMenu, SORT_MODES)

    local function UpdateOverviewScrollBounds()
        local vpH = math.floor((overviewScroll:GetHeight() or 0) + 0.5)
        local contentH = math.floor((overviewContent:GetHeight() or 0) + 0.5)
        overviewMaxScroll = math.max(0, contentH - vpH)
        local cur = overviewScroll:GetVerticalScroll() or 0
        if cur > overviewMaxScroll then
            overviewScroll:SetVerticalScroll(overviewMaxScroll)
        end
        syncOverviewScrollUI(overviewMaxScroll)
        local vpW = math.floor((overviewScroll:GetWidth() or 300) + 0.5)
        if vpW > 60 and math.abs((overviewContent:GetWidth() or 0) - vpW) >= 1 then
            overviewContent:SetWidth(vpW)
        end
    end

    overviewScroll:SetScript("OnMouseWheel", function(selfScroll, delta)
        if overviewMaxScroll <= 0 then return end
        local cur = selfScroll:GetVerticalScroll() or 0
        local nxt = math.max(0, math.min(overviewMaxScroll, cur - delta * 24))
        selfScroll:SetVerticalScroll(nxt)
        syncOverviewScrollUI(overviewMaxScroll)
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

        -- 1. Experience / Live Estimated Rested Progress + Item Level
        local lvl = tonumber(altData.level) or 0
        if lvl >= 60 then
            local rightLvl = (altData.itemLevel and altData.itemLevel > 0) and L["Item Level: %d"]:format(math.floor(altData.itemLevel)) or ""
            AddLine(L["Experience"] .. ": |cff3fb950" .. L["Max Level"] .. "|r", rightLvl, 0.85, 0.88, 0.94, 1.0, 0.85, 0.35, 19)
        else
            local xpVal = tonumber(altData.xp) or 0
            local xpMaxVal = math.max(1, tonumber(altData.xpMax) or 1)
            local xpFrac = math.max(0, math.min(1, xpVal / xpMaxVal))
            local xpPct = math.floor(xpFrac * 100 + 0.5)
            local restPct, isEst, etaSec, wasResting = ResolveAltRestedInfo(altData)
            local restTag = ""
            if restPct > 0 then
                if restPct >= 148 then
                    restTag = " · |cff58a6ff" .. L["150% MAX"] .. "|r"
                elseif isEst then
                    restTag = " · |cff58a6ff+~" .. L["Rested: %d%%"]:format(restPct) .. "|r"
                else
                    restTag = " · |cff58a6ff+" .. L["Rested: %d%%"]:format(restPct) .. "|r"
                end
            end
            local barText = ("%s %d · %d%%%s"):format(L["Level"], lvl, xpPct, restTag)
            local subFrac = (restPct > 0) and math.min(1, xpFrac + (restPct / 100)) or nil
            AddBar(xpFrac, 0.58, 0.34, 0.88, barText, subFrac, 0.25, 0.56, 0.96)
            if isEst or (etaSec and etaSec > 60 and restPct < 150) then
                local restDesc = wasResting and L["Inn/City Rest Estimate"] or L["Outdoors Rest Estimate"]
                local restRight = (etaSec and etaSec > 60 and restPct < 150)
                    and L["MAX in %s"]:format(FormatDurationCompact(etaSec))
                    or ("|cff3fb950" .. L["150% MAX"] .. "|r")
                AddLine(restDesc, restRight, 0.65, 0.72, 0.84, 0.58, 0.82, 1.0, 18)
            end
            if altData.itemLevel and altData.itemLevel > 0 then
                AddLine(L["Item Level"], tostring(math.floor(altData.itemLevel)), 0.75, 0.78, 0.85, 1.0, 0.85, 0.35, 18)
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
                and L["%d / %d slots"]:format(bankUsed, altData.bankTotal)
                or ("%d %s"):format(#altData.bank, L["items"])
            if altData.bankUpdatedAt and altData.bankUpdatedAt > 0 then
                bankStr = bankStr .. " · " .. Compat.FormatRelativeTime(altData.bankUpdatedAt, L)
            end
            AddLine(L["Bank"], bankStr, 0.75, 0.78, 0.85, 0.92, 0.94, 0.96, 18)
        else
            AddLine(L["Bank"], L["Visit a Bank NPC to snapshot bank items."], 0.75, 0.78, 0.85, 0.58, 0.62, 0.68, 18)
        end

        AddSep()

        -- 3. Location, Hearthstone, Supplies, Mail & Gold
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

        if ns.Alts and ns.Alts.GetClassSuppliesSummary then
            local supStr = ns.Alts:GetClassSuppliesSummary(altData)
            if supStr and supStr ~= "" then
                AddLine(L["Class Supplies"], supStr, 0.75, 0.78, 0.85, 0.78, 0.86, 0.98, 18)
            end
        end

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
        local scopeArg = AltUI.NormalizeWorldScope(panel._worldScope)
        local facGoldNum = (Store and Store.GetTotalAltsGold and Store:GetTotalAltsGold(scopeArg, altFac)) or myMoney
        local sameFacCount = 0
        for _, rec in ipairs((Store and Store.GetAltsList and Store:GetAltsList(scopeArg)) or {}) do
            if type(rec) == "table" and (altData.faction == nil or rec.faction == altData.faction) then
                sameFacCount = sameFacCount + 1
            end
        end
        if sameFacCount > 1 or facGoldNum > myMoney then
            local facSuffix = (altData.faction == "Alliance" and (" (" .. L["Alliance"] .. ")"))
                or (altData.faction == "Horde" and (" (" .. L["Horde"] .. ")"))
                or ""
            local totHeading
            if scopeArg == "all" then
                totHeading = L["Total Gold (All Worlds)"]
            elseif scopeArg == "pool" then
                totHeading = L["Total Server Gold"]
            else
                totHeading = L["Total Gold (%s)"]:format(AltUI.GetWorldScopeLabel(scopeArg))
            end
            AddLine(totHeading .. facSuffix, Compat.FormatMoney(facGoldNum), 1.0, 0.84, 0.25, 1.0, 1.0, 1.0, 18)
        end

        AddSep()

        -- 4. Professions & Tracked Craft Cooldowns
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

        if ns.Alts and ns.Alts.GetCraftCooldowns then
            local cds = ns.Alts:GetCraftCooldowns(altData)
            if #cds > 0 then
                AddLine(L["Craft Cooldowns"], "", 1.0, 0.82, 0.0, 1.0, 0.82, 0.0, 18)
                for _, cd in ipairs(cds) do
                    local lbl = (cd.prof and cd.prof ~= "") and (cd.prof .. ": " .. cd.name) or cd.name
                    if cd.isReady then
                        AddLine("  " .. lbl, "[" .. L["Ready"] .. "]", 0.92, 0.96, 1.0, 0.35, 0.92, 0.55, 18)
                    else
                        AddLine("  " .. lbl, L["Ready in %s"]:format(FormatDurationCompact(cd.remaining)), 0.88, 0.90, 0.95, 1.0, 0.74, 0.36, 18)
                    end
                end
            end
        end

        AddSep()

        -- 5. Account Hourly Instance Cap + Active Dungeon / Raid Lockouts
        if ns.Group and ns.Group.GetHourlyInstanceStatus then
            local st = ns.Group:GetHourlyInstanceStatus()
            local usedH, maxH = st and st.used or 0, st and st.max or 5
            local valTxt = string.format("%d/%d", usedH, maxH)
            if usedH > 0 and (st.nextSlotSecs or 0) > 0 and ns.Clan and ns.Clan.FormatResetDuration then
                valTxt = valTxt .. " · " .. ns.Clan:FormatResetDuration(st.nextSlotSecs)
            end
            local ir = (usedH >= maxH) and 1.0 or ((usedH >= maxH - 1) and 1.0 or 0.35)
            local ig = (usedH >= maxH) and 0.35 or ((usedH >= maxH - 1) and 0.72 or 0.92)
            local ib = (usedH >= maxH) and 0.35 or ((usedH >= maxH - 1) and 0.25 or 0.55)
            AddLine(L["Instance Limit (1h)"], valTxt, 0.75, 0.78, 0.85, ir, ig, ib, 18)
        end
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

        local reps = (ns.Alts and ns.Alts.GetReputations) and ns.Alts:GetReputations(altData) or {}
        if #reps > 0 then
            AddLine(L["Reputations"], "", 1.0, 0.82, 0.0, 1.0, 0.82, 0.0, 18)
            for ri = 1, math.min(#reps, 6) do
                local rep = reps[ri]
                local stLbl = (ns.Alts and ns.Alts.GetStandingLabel) and ns.Alts:GetStandingLabel(rep.standing) or ""
                local prog = (rep.standing == 8) and stLbl or ("%s (%d/%d)"):format(stLbl, rep.cur or 0, rep.max or 1)
                local rr, rg, rb = (rep.standing == 8) and 0.25 or 0.45, (rep.standing == 8) and 0.90 or 0.82, (rep.standing == 8) and 0.45 or 0.98
                AddLine("  " .. (rep.name or "?"), prog, 0.92, 0.94, 0.98, rr, rg, rb, 18)
            end
        end

        local marks = (ns.Alts and ns.Alts.GetMarks) and ns.Alts:GetMarks(altData) or {}
        if #marks > 0 then
            AddLine(L["Marks & Tokens"], "", 1.0, 0.82, 0.0, 1.0, 0.82, 0.0, 18)
            for mi = 1, math.min(#marks, 6) do
                local mk = marks[mi]
                AddLine("  " .. (mk.name or "?"), "x" .. tostring(mk.count or 0), 0.92, 0.94, 0.98, 1.0, 0.84, 0.30, 18)
            end
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

    local filterBtn = Theme:CreateButton(itemsToolbar, 24, 22, "", "default")
    Theme:ConfigureIconButton(filterBtn, 24, 22, "Interface\\Icons\\INV_Misc_Bag_08", {
        size = 14,
        toggle = true,
        active = false,
        activeColor = { 0.96, 0.76, 0.22 },
        tooltipFn = function()
            return L["Filter Items"] .. ": " .. (filterBtn._scLastLabel or L["All"]), L["Filter by source: All, Equipped, Bags, Bank, or Recipes."]
        end,
    })

    local scopeBtn = Theme:CreateButton(itemsToolbar, 24, 22, "", "default")
    Theme:ConfigureIconButton(scopeBtn, 24, 22, "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", {
        size = 15,
        toggle = true,
        active = (panel._allAltsScope == true),
        activeColor = { 0.35, 0.78, 1.0 },
        tooltipFn = function()
            return scopeBtn._scLastLabel or L["This Alt"], L["Toggle between searching only the selected alt or all saved alts."]
        end,
    })

    local viewModeBtn = Theme:CreateButton(itemsToolbar, 24, 22, "", "default")
    Theme:ConfigureIconButton(viewModeBtn, 24, 22, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", {
        size = 14,
        toggle = true,
        active = (panel._viewMode == "list"),
        activeColor = { 0.96, 0.76, 0.22 },
        tooltipFn = function()
            local curMode = (panel._viewMode == "list") and L["List"] or L["Grid"]
            return (L["Grid"] .. " / " .. L["List"]) .. ": " .. curMode, L["Click 'Grid' or 'List' to switch item view mode."]
        end,
    })

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
    infoLbl:SetHeight(16)
    infoLbl:SetJustifyH("RIGHT")
    infoLbl:SetJustifyV("MIDDLE")
    infoLbl:SetWordWrap(false)

    -- Forward-declared so RenderItems resolves it lexically instead of global nil.
    local RelayoutItemsToolbar

    local itemsCard = CreateFrame("Frame", nil, itemsFrame, "BackdropTemplate")
    itemsCard:SetPoint("TOPLEFT", itemsToolbar, "BOTTOMLEFT", 0, -4)
    itemsCard:SetPoint("BOTTOMRIGHT", itemsFrame, "BOTTOMRIGHT", -2, 2)
    Theme:ApplyBackdrop(itemsCard, "surface")

    local function TriggerSearchAllAlts(itemName, keepRecipesMode)
        if not itemName or itemName == "" then return end
        panel._allAltsScope = true
        panel._bagSource = keepRecipesMode and "recipes" or "all"
        panel._subTab = "items"
        panel._narrowTabPicked = true
        bagSearch:SetText(itemName)
        panel:Refresh(true)
    end

    local function OnGridCellEnter(selfCell)
        if selfCell._item then
            ShowItemTooltip(selfCell, selfCell._item, selfCell._item._slotId)
        end
    end
    local function OnGridCellLeave()
        if GameTooltip then GameTooltip:Hide() end
    end
    local function OnGridCellClick(selfCell, button)
        if not selfCell._item then return end
        if button == "RightButton" then
            OpenItemContextMenu(selfCell, selfCell._item, TriggerSearchAllAlts)
            return
        end
        if selfCell._item.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
            ChatEdit_InsertLink(selfCell._item.link)
        end
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
        return row
    end, function(row, rowData)
        row._cells = row._cells or {}
        if rowData.isHeader then
            row._headerTitle:SetText(rowData.title or "")
            row._headerTitle:Show()
            row._headerLine:Show()
            AltUI.ConfigureHeaderRow(row, rowData, panel, OpenAltActionMenu)
            for c = 1, #row._cells do
                local cell = row._cells[c]
                if cell then
                    cell._item = nil
                    cell:Hide()
                end
            end
            return
        end

        if row._headerHit then row._headerHit:Hide() end
        row._headerTitle:Hide()
        row._headerLine:Hide()

        local cols = math.max(1, math.min(AltUI.MAX_GRID_COLS or 14, rowData.cols or 7))
        for c = 1, cols do
            local item = rowData.items and rowData.items[c]
            if item then
                local cell = AltUI.AcquireGridCell(row, c, OnGridCellEnter, OnGridCellLeave, OnGridCellClick)
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", row, "LEFT", 4 + (c - 1) * 38, 0)
                cell.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local r, g, b = GetQualityRGB(item.quality)
                if cell.SetBackdropBorderColor then
                    pcall(cell.SetBackdropBorderColor, cell, r, g, b, 1.0)
                end
                if item._isEquip then
                    cell.eqLbl:Show()
                else
                    cell.eqLbl:Hide()
                end
                cell.countLbl:SetText((item.count and item.count > 1) and tostring(item.count) or "")
                cell._item = item
                cell:Show()
            elseif row._cells[c] then
                row._cells[c]._item = nil
                row._cells[c]:Hide()
            end
        end
        for c = cols + 1, #row._cells do
            local extra = row._cells[c]
            if extra then
                extra._item = nil
                extra:Hide()
            end
        end
    end)
    bagGridScroll.container:ClearAllPoints()
    bagGridScroll.container:SetAllPoints(itemsCard)

    local bagListScroll = Theme:CreateScrollList(itemsCard, 32, function(rowParent, _, rowHeight)
        local row = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
        row:SetHeight(rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.94, 0.78, 0.06)

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
            AltUI.ConfigureHeaderRow(row, rowData, panel, OpenAltActionMenu)
            return
        end

        if row._headerHit then row._headerHit:Hide() end
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
            local facArg = panel._includeOppositeFaction and "ALL" or panel._inspectedFaction
            local wScope = panel._allAltsScope and AltUI.NormalizeWorldScope(panel._itemsWorldScope) or AltUI.NormalizeWorldScope(panel._worldScope)
            local acctTot = ns.Alts:GetAccountItemTotal(item.itemID, facArg, wScope)
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
                local enchantTag = ""
                if slotData.item and slotData.enchantable then
                    enchantTag = slotData.enchanted
                        and (" |cff3fb950[" .. L["Ench"] .. "]|r")
                        or (slotData.warnNoEnchant and (" |cffff9b3d[" .. L["No Ench"] .. "]|r") or "")
                elseif slotData.item and slotData.enchanted then
                    enchantTag = " |cff3fb950[" .. L["Ench"] .. "]|r"
                end
                cell.slotLbl:SetText(GetSlotLabel(slotData.slotId) .. enchantTag)
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
        local extra = ((panel._itemCategory and panel._itemCategory ~= "all") or (panel._minQuality or 0) > 0) and " *" or ""
        if panel._bagSource == "equip" then
            return L["Equipped"] .. extra .. "  v"
        elseif panel._bagSource == "bags" then
            if not panel._allAltsScope and altData then
                local used = math.max(0, (altData.bagTotal or 0) - (altData.bagFree or 0))
                return (L["Bags"] .. " (%d/%d)" .. extra .. "  v"):format(used, altData.bagTotal or 0)
            end
            return L["Bags"] .. extra .. "  v"
        elseif panel._bagSource == "bank" then
            if not panel._allAltsScope and altData then
                local used = math.max(0, (altData.bankTotal or 0) - (altData.bankFree or 0))
                return (L["Bank"] .. " (%d/%d)" .. extra .. "  v"):format(used, altData.bankTotal or 0)
            end
            return L["Bank"] .. extra .. "  v"
        elseif panel._bagSource == "recipes" then
            return L["Recipes"] .. extra .. "  v"
        end
        return L["All"] .. extra .. "  v"
    end

    local function AppendGlobalSearchSections(sections, queryText, excludeAltKey, headingPrefix, srcFilter, factionFilter, worldScope)
        if not (ns.Alts and ns.Alts.SearchAllItems) then return end
        local opts = {
            itemCat = panel._itemCategory or "all",
            minQuality = panel._minQuality or 0,
        }
        local groups = ns.Alts:SearchAllItems(queryText, excludeAltKey, srcFilter, factionFilter, worldScope, opts)
        local dualFac = (factionFilter == "ALL")
        local showWorldBadge = AltUI.NormalizeWorldScope(worldScope) ~= "pool"
        for _, g in ipairs(groups) do
            local consolidated = ConsolidateItems(g.items, false)
            local hex = Compat.ClassHex(g.classFile)
            local facTag = ""
            if dualFac then
                facTag = (g.faction == "Alliance" and " |cff70b5ff[A]|r") or (g.faction == "Horde" and " |cffff7878[H]|r") or ""
            end
            local wBadge = FormatAltWorldBadge(g, showWorldBadge)
            local lbl = headingPrefix
                and ("|cff8ab4f8" .. headingPrefix .. "|r " .. hex .. (g.displayName or "?") .. "|r" .. facTag .. wBadge .. " |cffc6ceda(" .. #consolidated .. ")|r")
                or (hex .. (g.displayName or "?") .. "|r" .. facTag .. wBadge .. " |cffc6ceda(" .. #consolidated .. ")|r")
            sections[#sections + 1] = {
                title = lbl,
                altKey = g.altKey,
                altName = g.displayName,
                items = consolidated,
            }
        end
    end

    local function CollectFilteredItems(altData)
        local src = panel._bagSource or "all"
        local query = Compat.Trim(bagSearch:GetText() or ""):lower()
        if src == "recipes" and AltUI.BuildRecipeSections then
            return AltUI.BuildRecipeSections(panel, altData, query)
        end
        local hasExtraFilters = (panel._itemCategory and panel._itemCategory ~= "all") or (panel._minQuality or 0) > 0

        if panel._allAltsScope then
            local sections = {}
            local facFilter = panel._includeOppositeFaction and "ALL" or ((altData and altData.faction) or (Compat.PlayerFaction and Compat.PlayerFaction()))
            local wScope = AltUI.NormalizeWorldScope(panel._itemsWorldScope)
            AppendGlobalSearchSections(sections, query, nil, nil, src, facFilter, wScope)
            if #sections == 0 then
                return {}, ((query ~= "" or hasExtraFilters) and L["No matching items found across any character."] or L["No items recorded yet."])
            end
            return sections, ""
        end

        if not altData then return {}, "" end

        local function MatchesQuery(item)
            if not AltUI.MatchesItemFilter(panel, item) then return false end
            if query == "" then return true end
            local iName = ResolveItemDisplayName(item):lower()
            local slotLabel = (item._slotId and GetSlotLabel(item._slotId) or ""):lower()
            return iName:find(query, 1, true) ~= nil or (slotLabel ~= "" and slotLabel:find(query, 1, true) ~= nil)
        end

        local sections = {}

        if (src == "all" or src == "equip") and type(altData.equipment) == "table" then
            local equipItems = {}
            for _, slotId in ipairs(EQUIP_DISPLAY_ORDER) do
                local obj = UnpackAltItem(altData.equipment[slotId], L["Equipped"], slotId)
                if obj and MatchesQuery(obj) then
                    equipItems[#equipItems + 1] = obj
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
            for _, rawItem in ipairs(altData.bags) do
                local obj = UnpackAltItem(rawItem, L["Bags"])
                if obj and MatchesQuery(obj) then
                    bagItems[#bagItems + 1] = obj
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
            for _, rawItem in ipairs(altData.bank) do
                local obj = UnpackAltItem(rawItem, L["Bank"])
                if obj and MatchesQuery(obj) then
                    bankItems[#bankItems + 1] = obj
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
            if query ~= "" or hasExtraFilters then
                local fallbackFac = panel._includeOppositeFaction and "ALL" or (altData.faction or (Compat.PlayerFaction and Compat.PlayerFaction()))
                local iScope = AltUI.NormalizeWorldScope(panel._itemsWorldScope)
                local wScope = (iScope ~= "pool") and iScope or AltUI.NormalizeWorldScope(panel._worldScope)
                AppendGlobalSearchSections(sections, query, altData.key, L["Other Alt:"], src, fallbackFac, wScope)
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
        filterBtn._scLastLabel = GetFilterButtonLabel(altData)
        local hasItemFilter = (panel._bagSource and panel._bagSource ~= "all")
            or (panel._itemCategory and panel._itemCategory ~= "all")
            or ((panel._minQuality or 0) > 0)
        Theme:SetIconToggle(filterBtn, hasItemFilter == true, { 0.96, 0.76, 0.22 })

        local scopeText = L["This Alt"]
        if panel._allAltsScope then
            local iScope = AltUI.NormalizeWorldScope(panel._itemsWorldScope)
            if iScope == "all" then
                scopeText = L["All Alts (All Worlds)"]
            elseif iScope == "pool" then
                scopeText = L["All Alts (This World)"]
            else
                scopeText = L["All Alts (%s)"]:format(AltUI.GetWorldScopeLabel(iScope))
            end
            if panel._includeOppositeFaction then
                scopeText = scopeText .. " +"
            end
        end
        scopeBtn._scLastLabel = scopeText
        Theme:SetIconToggle(scopeBtn, panel._allAltsScope == true, { 0.35, 0.78, 1.0 })

        Theme:SetIconToggle(viewModeBtn, panel._viewMode == "list", { 0.96, 0.76, 0.22 })
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
            panel._lastGridCols = nil
            local rows = {}
            for _, sec in ipairs(sections) do
                rows[#rows + 1] = { isHeader = true, title = sec.title, altKey = sec.altKey, altName = sec.altName }
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
                vpW = math.max(180, pw - rosterW - 36)
            end
            local maxGridCols = AltUI.MAX_GRID_COLS or 14
            local cols = math.max(1, math.min(maxGridCols, math.floor((vpW - 8) / 38)))
            panel._lastGridCols = cols
            local rows = {}
            for _, sec in ipairs(sections) do
                rows[#rows + 1] = { isHeader = true, title = sec.title, altKey = sec.altKey, altName = sec.altName }
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

    local ENCHANTABLE_GEAR_SLOTS = {
        [5] = true, [7] = true, [8] = true, [9] = true, [10] = true,
        [15] = true, [16] = true, [17] = true,
    }

    local function HasPermanentEnchant(itemObj)
        local lnk = itemObj and itemObj.link
        if type(lnk) ~= "string" or lnk == "" then return false end
        local enchId = tonumber(lnk:match("item:%d+:(%d+)")) or 0
        return enchId > 0
    end

    local function RenderGear(altData, resetScroll)
        if not altData then
            gearSummaryLbl:SetText("")
            gearScroll:SetData({}, L["No characters recorded yet."], true)
            return
        end
        local eq = type(altData.equipment) == "table" and altData.equipment or {}
        local equippedCount = 0
        local missingEnchCount = 0
        local charLvl = tonumber(altData.level) or 0
        local checkMissingEnch = (charLvl >= 45)
        for _, slotId in ipairs(EQUIP_DISPLAY_ORDER) do
            if eq[slotId] then
                local parsedId = (type(eq[slotId]) == "string") or (type(eq[slotId]) == "table" and (eq[slotId].icon or eq[slotId].itemID or eq[slotId].link))
                if parsedId then
                    equippedCount = equippedCount + 1
                end
            end
        end

        local vpW = (gearScroll.viewport and gearScroll.viewport.GetWidth and gearScroll.viewport:GetWidth()) or 0
        if vpW < 80 then
            local isNarrow, pw = IsNarrowLayout()
            local rosterW = isNarrow and 0 or math.max(236, math.min(278, math.floor(pw * 0.34)))
            vpW = math.max(180, pw - rosterW - 36)
        end
        local cols = (vpW >= 400) and 2 or 1
        local rows = {}
        local slotEntryMap = {}
        for _, sid in ipairs(EQUIP_DISPLAY_ORDER) do
            local raw = eq[sid]
            local itemObj = raw and UnpackAltItem(raw, L["Equipped"], sid) or nil
            local isEnchSlot = ENCHANTABLE_GEAR_SLOTS[sid] == true
            if isEnchSlot and sid == 17 and itemObj then
                local eqLoc = itemObj.equipLoc
                if (not eqLoc or eqLoc == "") and itemObj.itemID and C_Item and C_Item.GetItemInfoInstant then
                    local _, _, _, invType = C_Item.GetItemInfoInstant(itemObj.itemID)
                    if type(invType) == "string" and invType ~= "" then
                        eqLoc = invType
                    end
                end
                if eqLoc == "INVTYPE_HOLDABLE" then
                    isEnchSlot = false
                end
            end
            local isEnchanted = itemObj and HasPermanentEnchant(itemObj) or false
            if itemObj and isEnchSlot and checkMissingEnch and not isEnchanted then
                missingEnchCount = missingEnchCount + 1
            end
            slotEntryMap[sid] = {
                slotId = sid,
                item = itemObj,
                enchantable = isEnchSlot,
                enchanted = isEnchanted,
                warnNoEnchant = (isEnchSlot and checkMissingEnch and not isEnchanted) == true,
            }
        end
        local sumStr = L["Equipped (%d/%d)"]:format(equippedCount, #EQUIP_DISPLAY_ORDER)
        if altData.itemLevel and altData.itemLevel > 0 then
            sumStr = sumStr .. " · iLvl " .. math.floor(altData.itemLevel)
        end
        if altData.durabilityPct ~= nil then
            local dCol = (altData.durabilityPct >= 80) and "|cff3fb950" or ((altData.durabilityPct >= 45) and "|cffffd24d" or "|cffff4d4d")
            sumStr = sumStr .. " · " .. L["Durability"] .. ": " .. dCol .. tostring(altData.durabilityPct) .. "%|r"
        end
        if checkMissingEnch then
            if missingEnchCount > 0 then
                sumStr = sumStr .. " · |cffff9b3d" .. L["Missing Enchants: %d"]:format(missingEnchCount) .. "|r"
            elseif equippedCount >= 8 then
                sumStr = sumStr .. " · |cff3fb950" .. L["All Enchanted"] .. "|r"
            end
        end
        gearSummaryLbl:SetText(sumStr)

        for i = 1, #EQUIP_DISPLAY_ORDER, cols do
            local slots = {}
            for j = 0, cols - 1 do
                local sid = EQUIP_DISPLAY_ORDER[i + j]
                if sid then
                    slots[j + 1] = slotEntryMap[sid]
                end
            end
            rows[#rows + 1] = { cols = cols, slots = slots }
        end
        gearScroll:SetData(rows, L["No characters recorded yet."], resetScroll)
    end

    local function RenderCharHeader(altData)
        panel._headerAltData = altData
        if not altData then
            charIcon:Hide()
            charTitleLbl:SetText(L["No characters recorded yet."])
            charSubLbl:SetText("")
            wideSummaryLbl:SetText("")
            btnActions:SetEnabled(false)
            return
        end
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
        local wBadge = FormatAltWorldBadge(altData, AltUI.NormalizeWorldScope(panel._worldScope) ~= "pool")
        charTitleLbl:SetText(("%s%s%s|r |cffc6ceda· %s|r"):format(facIco, hex, disp, L["Lv %d"]:format(lvl)))

        local subParts = {}
        if wBadge ~= "" then
            subParts[#subParts + 1] = wBadge:gsub("^%s+", "")
        end
        if rc ~= "" then
            subParts[#subParts + 1] = rc
        end
        if altData.guild and altData.guild ~= "" then
            subParts[#subParts + 1] = "<" .. altData.guild .. ">"
        else
            subParts[#subParts + 1] = L["No guild"]
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

        local _, panelW = IsNarrowLayout()
        if panelW >= 690 then
            local eqCount = 0
            if type(altData.equipment) == "table" then
                for _, sid in ipairs(EQUIP_DISPLAY_ORDER) do
                    if altData.equipment[sid] then eqCount = eqCount + 1 end
                end
            end
            local bagCap = altData.bagTotal or 0
            local bagUsed = math.max(0, bagCap - (tonumber(altData.bagFree) or 0))
            wideSummaryLbl:SetText(("%d/19 · %d/%d"):format(eqCount, bagUsed, bagCap))
        else
            wideSummaryLbl:SetText("")
        end
    end

    local function SyncSubTabs(altCount)
        local isNarrow = IsNarrowLayout()
        local activeSub = panel._subTab or "overview"
        if not isNarrow and activeSub == "alts" then
            activeSub = "overview"
            panel._subTab = "overview"
        end

        rosterAccountBtn:SetShown(false)
        rosterTitleLbl:ClearAllPoints()
        rosterTitleLbl:SetPoint("LEFT", rosterHeader, "LEFT", 8, 0)
        rosterTitleLbl:SetPoint("RIGHT", rosterSortBtn, "LEFT", -6, 0)

        Theme:SetButtonText(btnNarrowAlts, ("%s (%d)"):format(L["Alts"], altCount or 0))
        Theme:SetButtonActive(btnNarrowAlts, activeSub == "alts", "tab")
        Theme:SetButtonActive(btnNarrowOverview, activeSub == "overview", "tab")
        Theme:SetButtonActive(btnNarrowItems, activeSub == "items", "tab")
        Theme:SetButtonActive(btnNarrowGear, activeSub == "gear", "tab")
        Theme:SetButtonActive(btnNarrowAccount, activeSub == "account", "tab")

        Theme:SetButtonActive(btnWideOverview, activeSub == "overview", "tab")
        Theme:SetButtonActive(btnWideItems, activeSub == "items", "tab")
        Theme:SetButtonActive(btnWideGear, activeSub == "gear", "tab")
        Theme:SetButtonActive(btnWideAccount, activeSub == "account", "tab")

        local isAcct = (activeSub == "account")
        rosterPane:SetShown((not isNarrow and not isAcct) or (isNarrow and activeSub == "alts"))
        inspectorPane:SetShown((not isNarrow) or (activeSub ~= "alts"))
        charHeader:SetShown(not isAcct)
        local anchorSig = (isNarrow and "N:" or "W:") .. (isAcct and "A" or "C")
        if panel._scSubTabAnchorSig ~= anchorSig then
            panel._scSubTabAnchorSig = anchorSig
            if isNarrow then
                subArea:ClearAllPoints()
                if isAcct then
                    subArea:SetPoint("TOPLEFT", inspectorPane, "TOPLEFT", 2, -2)
                else
                    subArea:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 2, -4)
                end
                subArea:SetPoint("BOTTOMRIGHT", inspectorPane, "BOTTOMRIGHT", -4, 4)
            else
                wideTabBar:ClearAllPoints()
                if isAcct then
                    wideTabBar:SetPoint("TOPLEFT", inspectorPane, "TOPLEFT", 4, -6)
                    wideTabBar:SetPoint("TOPRIGHT", inspectorPane, "TOPRIGHT", -4, -6)
                else
                    wideTabBar:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 4, -4)
                    wideTabBar:SetPoint("TOPRIGHT", charHeader, "BOTTOMRIGHT", -4, -4)
                end
            end
        end
        overviewFrame:SetShown(activeSub == "overview")
        itemsFrame:SetShown(activeSub == "items")
        gearFrame:SetShown(activeSub == "gear")
        accountMatrix.frame:SetShown(isAcct)
    end

    RelayoutItemsToolbar = function(twOverride)
        local rawTw = tonumber(twOverride) or (itemsToolbar:GetWidth() or 0)
        local tw = math.floor(rawTw + 0.5)
        if tw < 120 then
            local isNarrow, pw = IsNarrowLayout()
            local rosterW = isNarrow and 0 or math.max(240, math.min(278, math.floor(pw * 0.34)))
            tw = math.max(220, isNarrow and (pw - 16) or (pw - rosterW - 24))
        end
        local bwFilter = math.floor((filterBtn._scAutoFitW or filterBtn:GetWidth() or 88) + 0.5)
        local bwScope = math.floor((scopeBtn._scAutoFitW or scopeBtn:GetWidth() or 92) + 0.5)
        local bwView = math.floor((viewModeBtn._scAutoFitW or viewModeBtn:GetWidth() or 64) + 0.5)
        local btnsNeed = bwFilter + 4 + bwScope + 4 + bwView
        local enterSingleW = 140 + btnsNeed + 92
        local exitSingleW = 140 + btnsNeed + 74
        local singleRow = itemsToolbar._scSingleRow and (tw >= exitSingleW) or (tw >= enterSingleW)
        if itemsToolbar._scSingleRow == nil then
            singleRow = (tw >= enterSingleW)
        end
        itemsToolbar._scSingleRow = singleRow

        local sig = tw .. ":" .. bwFilter .. ":" .. bwScope .. ":" .. bwView .. ":" .. (singleRow and "1" or "0") .. ":" .. (itemsHelpBtn and "1" or "0")
        if itemsToolbar._scToolbarSig == sig then
            return
        end
        itemsToolbar._scToolbarSig = sig

        bagSearch:ClearAllPoints()
        bagSearch:SetPoint("TOPLEFT", itemsToolbar, "TOPLEFT", 0, 0)
        local buttons = { filterBtn, scopeBtn, viewModeBtn }
        if singleRow then
            local searchW = math.floor(math.max(136, math.min(180, tw - btnsNeed - 98)) + 0.5)
            if math.abs((bagSearch:GetWidth() or 0) - searchW) >= 1 then
                bagSearch:SetWidth(searchW)
            end
            if math.abs((itemsToolbar:GetHeight() or 0) - 26) >= 1 then
                itemsToolbar:SetHeight(26)
            end
            LayoutButtonFlow(itemsToolbar, buttons, searchW + 6, -1, btnsNeed + 16, 24, 4)
            if itemsHelpBtn then
                itemsHelpBtn:ClearAllPoints()
                itemsHelpBtn:SetPoint("RIGHT", itemsToolbar, "RIGHT", -2, 0)
            end
            if not itemsToolbar._legendBtn then
                itemsToolbar._legendBtn = Theme:CreateLegendTag(itemsToolbar, function()
                    return {
                        { tex = "Interface\\Icons\\INV_Misc_Bag_08", title = L["Filter Items"], desc = L["All"] .. " / " .. L["Equipped"] .. " / " .. L["Bags"] .. " / " .. L["Bank"] },
                        { tex = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", title = L["This Alt"] .. " / " .. L["All Alts"] },
                        { tex = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", title = L["Grid"] .. " / " .. L["List"] },
                        { title = "|cff70b5ff[A]|r · |cffff7878[H]|r", desc = L["Alliance / Horde Faction Tag"] },
                    }
                end)
            end
            local showItLeg = (tw >= 460)
            itemsToolbar._legendBtn:SetShown(showItLeg)
            if showItLeg then
                itemsToolbar._legendBtn:ClearAllPoints()
                itemsToolbar._legendBtn:SetPoint("LEFT", viewModeBtn, "RIGHT", 6, 0)
            end
            infoLbl:ClearAllPoints()
            infoLbl:SetPoint("LEFT", showItLeg and itemsToolbar._legendBtn or viewModeBtn, "RIGHT", 6, 0)
            infoLbl:SetPoint("RIGHT", itemsHelpBtn or itemsToolbar, itemsHelpBtn and "LEFT" or "RIGHT", -6, 0)
        else
            if itemsToolbar._legendBtn then
                itemsToolbar._legendBtn:Hide()
            end
            local searchW = math.max(108, math.min(240, math.floor(tw * 0.54)))
            if math.abs((bagSearch:GetWidth() or 0) - searchW) >= 1 then
                bagSearch:SetWidth(searchW)
            end
            local rows = LayoutButtonFlow(itemsToolbar, buttons, 0, -26, tw - 4, 24, 4)
            local targetH = 26 + rows * 24 + 2
            if math.abs((itemsToolbar:GetHeight() or 0) - targetH) >= 1 then
                itemsToolbar:SetHeight(targetH)
            end
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
                if emb.quickBtn and emb.quickBtn:IsShown() then
                    rClear = rClear + (emb.quickBtn:GetWidth() or 18) + 4
                end
                embRightClear = math.max(34, math.ceil(rClear))
            elseif w >= 540 then
                embRightClear = 136
            else
                embRightClear = 56
            end
        end

        local layoutSig = (isEmbeddedChar and "E:" or "M:") .. (isNarrow and "N:" or "W:") .. w .. ":" .. embRightClear .. ":" .. tostring(panel._subTab) .. ":" .. tostring(p and p.key or "dark")
        if panel._lastLayoutSig == layoutSig then
            return
        end
        panel._lastLayoutSig = layoutSig
        panel._scSubTabAnchorSig = nil

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
            local showTopWorld = topAvail >= 300 and panel._worldBtn ~= nil
            local worldReserve = showTopWorld and (math.ceil(panel._worldBtn:GetWidth() or 116) + 8) or 0
            local charW = math.max(104, math.min(220, topAvail - 28 - worldReserve))
            charBtn:SetWidth(charW)
            if panel._worldBtn then
                panel._worldBtn:SetShown(showTopWorld)
            end
        end

        if isNarrow then
            narrowTabBar:ClearAllPoints()
            narrowTabBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -31)
            narrowTabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -31)
            local narrowBtns = { btnNarrowAlts, btnNarrowOverview, btnNarrowItems, btnNarrowGear, btnNarrowAccount }
            local gapPx = 3
            local availW = math.max(240, w - 4 - ((#narrowBtns - 1) * gapPx))
            local widths = {}
            local totalNeed = 0
            for idx, b in ipairs(narrowBtns) do
                Theme:AutoFitButton(b, 44, 10, math.floor(availW * 0.42))
                local bw = math.ceil(b:GetWidth() or 52)
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
                    widths[idx] = math.max(38, math.floor(widths[idx] * scale))
                end
            end
            for idx, b in ipairs(narrowBtns) do
                b:SetWidth(widths[idx])
                b:ClearAllPoints()
                if idx == 1 then
                    b:SetPoint("LEFT", narrowTabBar, "LEFT", 0, 0)
                else
                    b:SetPoint("LEFT", narrowBtns[idx - 1], "RIGHT", gapPx, 0)
                end
            end

            rosterPane:ClearAllPoints()
            rosterPane:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -59)
            rosterPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)

            inspectorPane:ClearAllPoints()
            inspectorPane:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -59)
            inspectorPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)

            subArea:ClearAllPoints()
            if panel._subTab == "account" then
                subArea:SetPoint("TOPLEFT", inspectorPane, "TOPLEFT", 2, -2)
            else
                subArea:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 2, -4)
            end
            subArea:SetPoint("BOTTOMRIGHT", inspectorPane, "BOTTOMRIGHT", -4, 4)
        else
            local topPad = isEmbeddedChar and -32 or -2
            local rosterW = math.max(240, math.min(278, math.floor(w * 0.34)))
            rosterPane:ClearAllPoints()
            rosterPane:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, topPad)
            rosterPane:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 2, 2)
            rosterPane:SetWidth(rosterW)

            inspectorPane:ClearAllPoints()
            if panel._subTab == "account" then
                inspectorPane:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, topPad)
            else
                inspectorPane:SetPoint("TOPLEFT", rosterPane, "TOPRIGHT", 6, 0)
            end
            inspectorPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)

            subArea:ClearAllPoints()
            subArea:SetPoint("TOPLEFT", wideTabBar, "BOTTOMLEFT", 0, -4)
            subArea:SetPoint("BOTTOMRIGHT", inspectorPane, "BOTTOMRIGHT", -4, 4)
        end

        if p and p.key == "blizzard" then
            rosterHdrBg:SetVertexColor(0.18, 0.14, 0.09, 1.0)
            charHdrBg:SetVertexColor(0.18, 0.14, 0.09, 1.0)
            goldBarBg:SetVertexColor(0.20, 0.15, 0.07, 1.0)
            rosterHdrLine:SetVertexColor(0.65, 0.50, 0.22, 0.85)
            charHdrLine:SetVertexColor(0.65, 0.50, 0.22, 0.85)
            goldBarLine:SetVertexColor(0.75, 0.58, 0.22, 0.90)
        elseif p and p.key == "native" then
            rosterHdrBg:SetVertexColor(0.13, 0.11, 0.09, 1.0)
            charHdrBg:SetVertexColor(0.13, 0.11, 0.09, 1.0)
            goldBarBg:SetVertexColor(0.15, 0.12, 0.06, 1.0)
            rosterHdrLine:SetVertexColor(0.58, 0.48, 0.28, 0.85)
            charHdrLine:SetVertexColor(0.58, 0.48, 0.28, 0.85)
            goldBarLine:SetVertexColor(0.70, 0.56, 0.24, 0.90)
        else
            rosterHdrBg:SetVertexColor(0.10, 0.12, 0.16, 1.0)
            charHdrBg:SetVertexColor(0.10, 0.12, 0.16, 1.0)
            goldBarBg:SetVertexColor(0.08, 0.10, 0.14, 1.0)
            rosterHdrLine:SetVertexColor(0.24, 0.56, 0.86, 0.65)
            charHdrLine:SetVertexColor(0.24, 0.56, 0.86, 0.65)
            goldBarLine:SetVertexColor(0.32, 0.66, 0.96, 0.65)
        end

        Theme:ApplyBackdrop(rosterPane, "surface", p)
        Theme:ApplyBackdrop(inspectorPane, "surface", p)
        Theme:ApplyBackdrop(itemsCard, "surface", p)

        charTitleLbl:ClearAllPoints()
        charTitleLbl:SetPoint("TOPLEFT", charIcon, "TOPRIGHT", 8, -1)
        charTitleLbl:SetPoint("RIGHT", btnActions, "LEFT", -8, 0)
        charSubLbl:ClearAllPoints()
        charSubLbl:SetPoint("BOTTOMLEFT", charIcon, "BOTTOMRIGHT", 8, 1)
        charSubLbl:SetPoint("RIGHT", btnActions, "LEFT", -8, 0)

        local estTw = isNarrow and math.max(220, w - 16) or math.max(220, w - math.max(240, math.min(278, math.floor(w * 0.34))) - 24)
        RelayoutItemsToolbar(estTw)
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
    btnNarrowAccount:SetScript("OnClick", function() SwitchSubTab("account") end)
    btnWideOverview:SetScript("OnClick", function() SwitchSubTab("overview") end)
    btnWideItems:SetScript("OnClick", function() SwitchSubTab("items") end)
    btnWideGear:SetScript("OnClick", function() SwitchSubTab("gear") end)
    btnWideAccount:SetScript("OnClick", function() SwitchSubTab("account") end)
    rosterAccountBtn:SetScript("OnClick", function() SwitchSubTab("account") end)

    rosterSortBtn:SetScript("OnClick", function(selfBtn)
        AltUI.OpenWorldSortMenu(panel, selfBtn, SORT_MODES, function()
            local idx = 1
            for i, m in ipairs(SORT_MODES) do
                if m.id == panel._sortBy then idx = (i % #SORT_MODES) + 1; break end
            end
            panel._sortBy = SORT_MODES[idx].id
            panel:Refresh(true)
        end)
    end)

    btnActions:SetScript("OnClick", function(selfBtn)
        local selectedAlt = GetSelectedAlt()
        if selectedAlt then
            OpenAltActionMenu(selfBtn, selectedAlt)
        end
    end)

    charBtn:SetScript("OnClick", function(selfBtn)
        local selectedAlt, list = GetSelectedAlt()
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                root:CreateTitle(L["World / Ruleset"])
                AltUI.PopulateWorldScopeMenu(root, panel)
                if #list > 0 then
                    root:CreateDivider()
                    root:CreateTitle(L["Select Character"])
                    for _, rec in ipairs(list) do
                        local hex = Compat.ClassHex(rec.classFile)
                        local mailTag = rec.hasMail and (" |cffffd24d[" .. L["Mailbox"] .. "]|r") or ""
                        local wBadge = FormatAltWorldBadge(rec, AltUI.NormalizeWorldScope(panel._worldScope) ~= "pool")
                        local lbl = ("%s%s|r%s |cffc6ceda(%s)|r · %s%s"):format(
                            hex,
                            rec.fullName or rec.name or rec.key,
                            wBadge,
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
            if list and #list > 0 then
                local idx = 1
                for i, rec in ipairs(list) do
                    if rec.key == panel._selectedKey then idx = (i % #list) + 1; break end
                end
                panel._userPickedAlt = true
                panel._selectedKey = list[idx].key
                panel:Refresh(true)
            end
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
        AltUI.OpenItemFilterMenu(panel, selfBtn, GetSelectedAlt, RenderItems)
    end)

    scopeBtn:SetScript("OnClick", function(selfBtn)
        AltUI.OpenScopeMenu(panel, selfBtn, GetSelectedAlt, RenderItems)
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
            { rosterAccountBtn, "default" },
            { btnActions, "default" },
            { filterBtn, "default" },
            { scopeBtn, "default" },
            { viewModeBtn, "default" },
            { btnNarrowAlts, "tab" },
            { btnNarrowOverview, "tab" },
            { btnNarrowItems, "tab" },
            { btnNarrowGear, "tab" },
            { btnNarrowAccount, "tab" },
            { btnWideOverview, "tab" },
            { btnWideItems, "tab" },
            { btnWideGear, "tab" },
            { btnWideAccount, "tab" },
        }
        for _, pair in ipairs(buttonsToStyle) do
            Theme:StyleButton(pair[1], pair[2])
        end
        if panel._worldBtn then
            Theme:StyleButton(panel._worldBtn, "default")
            local wScope = AltUI.NormalizeWorldScope(panel._worldScope)
            Theme:SetIconToggle(panel._worldBtn, wScope ~= "pool", { 0.35, 0.78, 1.0 })
        end
        Theme:AutoFitButton(rosterAccountBtn, 52, 10, 82)
        rosterAccountBtn:SetHeight(20)
        Theme:SetIconToggle(rosterSortBtn, panel._sortBy ~= "recent", { 0.35, 0.78, 1.0 })
        Theme:AutoFitButton(btnActions, 64, 12, 108)

        for _, hb in ipairs({ charHelpBtn, rosterHelpBtn, headerHelpBtn, itemsHelpBtn, gearHelpBtn }) do
            if hb and hb.RefreshTheme then hb:RefreshTheme() end
        end
        accountMatrix.RefreshTheme()
        refreshOverviewThumb()
        Theme:ApplyBackdrop(rosterPane, "surface")
        Theme:ApplyBackdrop(inspectorPane, "surface")
        Theme:ApplyBackdrop(itemsCard, "surface")
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
        local isAcct = (activeSub == "account")
        if not isNarrow and activeSub == "alts" then
            activeSub = "overview"
        end
        local scopeArg = AltUI.NormalizeWorldScope(panel._worldScope)
        if panel._worldBtn then
            Theme:SetIconToggle(panel._worldBtn, scopeArg ~= "pool", { 0.35, 0.78, 1.0 })
        end
        if (not isNarrow and not isAcct) or activeSub == "alts" then
            rosterTitleLbl:SetText(("%s (%d)"):format(L["My Alts"], #list))
            Theme:SetIconToggle(rosterSortBtn, panel._sortBy ~= "recent", { 0.35, 0.78, 1.0 })
            local totGold = (Store and Store.GetTotalAltsGold and Store:GetTotalAltsGold(scopeArg, true)) or 0
            local curFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
            local byFac = (Store and Store.GetTotalAltsGoldByFaction and Store:GetTotalAltsGoldByFaction(scopeArg)) or nil
            local dualFac = byFac and (byFac.Alliance or 0) > 0 and (byFac.Horde or 0) > 0
            local facSuffix = (dualFac and curFac == "Alliance" and (" (" .. L["Alliance"] .. ")"))
                or (dualFac and curFac == "Horde" and (" (" .. L["Horde"] .. ")"))
                or ""
            local goldHeading
            if scopeArg == "all" then
                goldHeading = L["Total Gold (All Worlds)"]
            elseif scopeArg == "pool" then
                goldHeading = L["Total Server Gold"]
            else
                goldHeading = L["Total Gold (%s)"]:format(AltUI.GetWorldScopeLabel(scopeArg))
            end
            goldVaultLbl:SetText("|cffffd200" .. goldHeading .. facSuffix .. "|r")
            goldVaultVal:SetText(Compat.FormatMoney(totGold))
            if panel._worldHintBar and panel._goldBar then
                local showOtherHint = false
                if scopeArg == "all" then
                    local recordedWorlds = (Store and Store.GetRecordedAltWorlds and Store:GetRecordedAltWorlds()) or {}
                    showOtherHint = (#recordedWorlds <= 1)
                end
                panel._worldHintBar:SetShown(showOtherHint)
                rosterScroll.container:ClearAllPoints()
                rosterScroll.container:SetPoint("TOPLEFT", rosterHeader, "BOTTOMLEFT", 2, -2)
                rosterScroll.container:SetPoint("BOTTOMRIGHT", showOtherHint and panel._worldHintBar or panel._goldBar, "TOPRIGHT", -2, 2)
            end
            local rosterEmpty = (scopeArg == "pool" or scopeArg == "all") and L["No characters recorded yet."] or L["No alts recorded in this world yet."]
            rosterScroll:SetData(list, rosterEmpty, resetScroll)
        end
        if (not isNarrow) or activeSub ~= "alts" then
            if activeSub ~= "account" then
                RenderCharHeader(altData)
            end
            if activeSub == "overview" then
                RenderOverview(altData, resetScroll)
            elseif activeSub == "items" then
                RenderItems(altData, resetScroll)
            elseif activeSub == "gear" then
                RenderGear(altData, resetScroll)
            elseif activeSub == "account" then
                accountMatrix.Render(list, isNarrow, resetScroll)
            end
        end
    end

    function panel:Relayout()
        if not self:IsShown() then return end
        RelayoutAltsPanel()
        local curW = math.floor((self:GetWidth() or 0) + 0.5)
        local needColsSync = false
        if panel._subTab == "items" and itemsFrame:IsShown() and panel._viewMode ~= "list" then
            local liveVpW = (bagGridScroll.viewport and bagGridScroll.viewport.GetWidth and bagGridScroll.viewport:GetWidth()) or 0
            if liveVpW >= 80 then
                local liveCols = math.max(1, math.min(AltUI.MAX_GRID_COLS or 14, math.floor((liveVpW - 8) / 38)))
                if panel._lastGridCols ~= liveCols then
                    needColsSync = true
                end
            end
        end
        if needColsSync or not self._lastRenderedW or math.abs(curW - self._lastRenderedW) >= 2 then
            self._lastRenderedW = curW
            local altData, list = GetSelectedAlt()
            SyncSubTabs(#list)
            RenderActiveSubView(altData, list, false)
        end
    end

    local function ExecutePanelRefreshBody()
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

        RenderActiveSubView(altData, list, panel._pendingResetScroll)
        local curThemeKey = Theme.GetThemeName and Theme:GetThemeName() or "blizzard"
        if panel._scLastThemeKey ~= curThemeKey then
            panel._scLastThemeKey = curThemeKey
            panel:RefreshTheme(true)
        end
        SyncSubTabs(#list)
    end

    function panel:Refresh(resetScroll)
        if isRefreshing then return end
        if not self:IsShown() then
            self._dirty = true
            return
        end
        self._dirty = false
        self._pendingResetScroll = resetScroll
        isRefreshing = true
        local errFn = (type(geterrorhandler) == "function" and geterrorhandler()) or tostring
        xpcall(ExecutePanelRefreshBody, errFn)
        -- Always release lock so no subview error can permanently freeze character inspection.
        isRefreshing = false
        self._pendingResetScroll = nil
    end

    function panel:ApplyNavigation(opts)
        if type(opts) ~= "table" then return end
        if not self:IsShown() then
            self._pendingNav = opts
        end
        if opts.altSubTab and opts.altSubTab ~= "" then
            self._subTab = opts.altSubTab
            self._narrowTabPicked = true
        end
        if opts.altBagSource and opts.altBagSource ~= "" then
            self._bagSource = opts.altBagSource
        end
        if opts.altViewMode and (opts.altViewMode == "list" or opts.altViewMode == "grid") then
            self._viewMode = opts.altViewMode
        elseif opts.altBagSource == "recipes" then
            self._viewMode = "list"
        end
        if opts.altAllAlts ~= nil then
            self._allAltsScope = opts.altAllAlts == true
        end
        if opts.altSearch ~= nil and bagSearch and bagSearch.SetText then
            bagSearch:SetText(Compat.CleanInput(opts.altSearch) or "")
        end
        self._dirty = true
        if self:IsShown() then
            self:Refresh(true)
        end
    end

    panel:SetScript("OnShow", function()
        isRefreshing = false
        if panel._pendingNav then
            local pNav = panel._pendingNav
            panel._pendingNav = nil
            panel:ApplyNavigation(pNav)
        end
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
        isRefreshing = false
        panel._lastLayoutSig = nil
        panel._scSubTabAnchorSig = nil
        panel._lastRenderedW = nil
        panel._lastGridCols = nil
        itemsToolbar._scToolbarSig = nil
        itemsToolbar._scSingleRow = nil
        panel._userPickedAlt = false
        panel._narrowTabPicked = false
        panel._subTab = "overview"
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
