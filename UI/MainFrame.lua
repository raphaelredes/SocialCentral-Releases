local _, ns = ...

local L = ns.L
local Compat = ns.Compat
local Theme = ns.Theme

local UI = {}
ns.UI = UI

local frame
local searchBox
local addBox
local checkAddBtn
local checkNextBtn
local scrollList
local clanPanel
local groupPanel
local chatPanel
local modalFrame
local eventModalFrame
local ticker

local activeTab = "watchlist"
local socialFilter = "all"
local socialFolderFilter = "all"
local watchlistGroupFilter = "all"
local clanEventFilter = "all"
local clanRightView = "peers"
local searchQuery = ""

local tabButtons = {}
local socialFilterButtons = {}
local clanEventFilterButtons = {}
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

local function SaveGeometry()
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

    if checkAddBtn then
        if inCombat then
            Theme:SetButtonText(checkAddBtn, L["In Combat"])
            checkAddBtn:SetEnabled(false)
        elseif busy or cd > 0 then
            local secs = math.max(1, math.ceil(cd))
            Theme:SetButtonText(checkAddBtn, L["Wait %ds"]:format(secs))
            checkAddBtn:SetEnabled(false)
        else
            Theme:SetButtonText(checkAddBtn, L["+ /who"])
            checkAddBtn:SetEnabled(true)
        end
    end
end

local function EnsureModal()
    if modalFrame then
        return modalFrame
    end

    local m = CreateFrame("Frame", "SocialCentralModal", frame, "BackdropTemplate")
    m:SetSize(340, 140)
    m:SetPoint("CENTER")
    m:SetFrameStrata("DIALOG")
    m:EnableMouse(true)
    m:Hide()

    m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    m.title:SetPoint("TOPLEFT", 16, -14)
    m.title:SetPoint("TOPRIGHT", -16, -14)
    m.title:SetJustifyH("LEFT")

    local input = CreateFrame("EditBox", nil, m, "InputBoxTemplate")
    input:SetSize(304, 24)
    input:SetPoint("TOPLEFT", 18, -46)
    input:SetAutoFocus(false)
    input:SetMaxLetters(120)
    m.input = input

    local btnSave = Theme:CreateButton(m, 90, 24, L["Save"], "primary")
    btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
    m.btnSave = btnSave

    local btnCancel = Theme:CreateButton(m, 90, 24, L["Cancel"], "default")
    btnCancel:SetPoint("RIGHT", btnSave, "LEFT", -8, 0)
    btnCancel:SetScript("OnClick", function()
        input:ClearFocus()
        m:Hide()
    end)

    input:SetScript("OnEscapePressed", function()
        input:ClearFocus()
        m:Hide()
    end)

    modalFrame = m
    return m
end

local function OpenNoteModal(entry)
    local m = EnsureModal()
    Theme:ApplyBackdrop(m, "window")
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
    Theme:ApplyBackdrop(m, "window")
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

local function OpenCopyModal(name)
    local m = EnsureModal()
    Theme:ApplyBackdrop(m, "window")
    m.title:SetText(L["Copy Name"] .. " (Ctrl+C)")
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

local function OpenEventModal()
    if not eventModalFrame then
        local m = CreateFrame("Frame", "SocialCentralEventModal", frame, "BackdropTemplate")
        m:SetSize(390, 290)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:EnableMouse(true)
        table.insert(UISpecialFrames, "SocialCentralEventModal")

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetText(L["Create Clan Event Call"])

        local catLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        catLbl:SetPoint("TOPLEFT", 16, -42)
        catLbl:SetText(L["Category:"])

        m._cat = "DUNGEON"
        m._catBtns = {}
        local cats = { "DUNGEON", "RAID", "BOSS", "PVP", "GUILD" }
        local prevCat
        for _, cId in ipairs(cats) do
            local btn = Theme:CreateButton(m, 68, 22, CAT_LABELS[cId] or cId, "default")
            if btn.label then
                btn.label:ClearAllPoints()
                btn.label:SetPoint("LEFT", 4, 0)
                btn.label:SetPoint("RIGHT", -4, 0)
                btn.label:SetWordWrap(false)
            end
            if not prevCat then
                btn:SetPoint("TOPLEFT", catLbl, "BOTTOMLEFT", 0, -6)
            else
                btn:SetPoint("LEFT", prevCat, "RIGHT", 4, 0)
            end
            btn:SetScript("OnClick", function()
                m._cat = cId
                for _, item in ipairs(m._catBtns) do
                    Theme:SetButtonActive(item.btn, m._cat == item.id, "default")
                end
            end)
            table.insert(m._catBtns, { id = cId, btn = btn })
            prevCat = btn
        end

        local titleLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        titleLbl:SetPoint("TOPLEFT", 16, -94)
        titleLbl:SetText(L["Event Title (e.g. Mythic +10, Karazhan):"])

        local titleInput = CreateFrame("EditBox", nil, m, "InputBoxTemplate")
        titleInput:SetSize(350, 22)
        titleInput:SetPoint("TOPLEFT", titleLbl, "BOTTOMLEFT", 4, -4)
        titleInput:SetAutoFocus(false)
        titleInput:SetMaxLetters(40)
        m.titleInput = titleInput

        local whenLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        whenLbl:SetPoint("TOPLEFT", 16, -144)
        whenLbl:SetText(L["When (e.g. Now, Today 21:00):"])

        local whenInput = CreateFrame("EditBox", nil, m, "InputBoxTemplate")
        whenInput:SetSize(350, 22)
        whenInput:SetPoint("TOPLEFT", whenLbl, "BOTTOMLEFT", 4, -4)
        whenInput:SetAutoFocus(false)
        whenInput:SetMaxLetters(24)
        m.whenInput = whenInput

        local slotsLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slotsLbl:SetPoint("TOPLEFT", 16, -196)
        slotsLbl:SetText(L["Role Slots & Min Level (optional):"])

        local function MakeSmallNumInput(xOff, lblText)
            local l = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            l:SetPoint("TOPLEFT", xOff, -216)
            l:SetText(lblText)
            local box = CreateFrame("EditBox", nil, m, "InputBoxTemplate")
            box:SetSize(34, 20)
            box:SetPoint("LEFT", l, "RIGHT", 6, 0)
            box:SetAutoFocus(false)
            box:SetNumeric(true)
            box:SetMaxLetters(2)
            box:SetScript("OnEscapePressed", function() m:Hide() end)
            return box
        end

        m.tankIn = MakeSmallNumInput(16, "T:")
        m.healIn = MakeSmallNumInput(90, "H:")
        m.dpsIn = MakeSmallNumInput(164, "D:")
        m.lvlIn = MakeSmallNumInput(242, L["Min Lv:"])

        local btnSave = Theme:CreateButton(m, 96, 24, L["Save"], "primary")
        btnSave:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnSave = btnSave

        local btnCancel = Theme:CreateButton(m, 96, 24, L["Cancel"], "default")
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
                local ok = ns.Clan:CreateEventCall(
                    m._cat,
                    titleInput:GetText() or "",
                    whenInput:GetText() or "",
                    m.tankIn:GetText(),
                    m.healIn:GetText(),
                    m.dpsIn:GetText(),
                    m.lvlIn:GetText()
                )
                if ok then
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

    Theme:ApplyBackdrop(eventModalFrame, "window")
    Theme:StyleButton(eventModalFrame.btnSave, "primary")
    Theme:StyleButton(eventModalFrame.btnCancel, "default")
    for _, item in ipairs(eventModalFrame._catBtns) do
        Theme:StyleButton(item.btn, "default")
        Theme:SetButtonActive(item.btn, eventModalFrame._cat == item.id, "default")
    end
    eventModalFrame.titleInput:SetText("")
    eventModalFrame.whenInput:SetText(L["Now"])
    eventModalFrame.tankIn:SetText("")
    eventModalFrame.healIn:SetText("")
    eventModalFrame.dpsIn:SetText("")
    eventModalFrame.lvlIn:SetText("")
    eventModalFrame:Show()
    eventModalFrame.titleInput:SetFocus()
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
            root:CreateButton(L["Add to Watchlist"], function()
                if ns.Watchlist then
                    ns.Watchlist:Add(item.lookupKey or targetName)
                end
            end)
        end

        if targetName and item._tab ~= "alts" then
            root:CreateButton(L["Edit Social Card"], function()
                if ns.SocialPanels and ns.SocialPanels.OpenSocialMetaModal then
                    ns.SocialPanels:OpenSocialMetaModal(targetName, item.lookupKey or targetName)
                end
            end)
            root:CreateDivider()
            root:CreateButton(L["Whisper"], function()
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
    row.nameText:SetPoint("RIGHT", row, "RIGHT", -258, 0)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.subText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.subText:SetPoint("BOTTOMLEFT", 26, 5)
    row.subText:SetPoint("RIGHT", row, "RIGHT", -258, 0)
    row.subText:SetJustifyH("LEFT")
    row.subText:SetWordWrap(false)

    row.btnRemove = Theme:CreateButton(row, 24, 22, "×", "danger")
    row.btnRemove:SetPoint("RIGHT", -8, 0)

    row.btnInvite = Theme:CreateButton(row, 64, 22, L["Invite"], "default")
    row.btnWhisper = Theme:CreateButton(row, 68, 22, L["Whisper"], "default")
    row.btnAction = Theme:CreateButton(row, 68, 22, L["Check"], "primary")

    row.btnRemove:SetScript("OnClick", function()
        if row._item and ns.Watchlist then
            ns.Watchlist:Remove(row._item.id)
        end
    end)

    row.btnWhisper:SetScript("OnClick", function()
        local item = row._item
        if not item then return end
        if item._tab == "social" and item.samePool == false and item.bnetName then
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
        if not item or not ns.Watchlist then return end
        if item._tab == "watchlist" then
            ns.Watchlist:CheckEntry(item.id)
        elseif item._tab == "social" or item._tab == "nearby" then
            ns.Watchlist:Add(item.lookupKey or item.displayName)
        end
    end)

    row:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" and self._item then
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
            if item.truncatedWarning then
                GameTooltip:AddLine(L["50+ matches found for '%s'; add surname for accuracy."]:format(item.firstName or item.displayName or ""), 1, 0.45, 0.25, true)
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
    local hex = Compat.ClassHex(item.classFile)
    local levelStr = item.level and item.level > 0 and (" |cff9da7b5[" .. L["Level %d"]:format(item.level) .. "]|r") or ""

    row.btnRemove:Hide()
    row.btnInvite:Hide()
    row.btnWhisper:Hide()
    row.btnAction:Hide()

    if tab == "watchlist" then
        Theme:ApplyStatusColor(row.dot, item.status or "unknown")
        local star = item.favorite and "|cffffd24d* |r" or ""
        local grp = (type(item.group) == "string" and item.group ~= "") and (" |cff8ab4f8[" .. item.group .. "]|r") or ""
        local warn = item.truncatedWarning and " |cffff9b3d[!50+]|r" or ""
        row.nameText:SetText(star .. hex .. (item.displayName or "") .. "|r" .. levelStr .. grp .. warn)
        row.subText:SetText(FormatWatchlistSubline(item))

        row.btnRemove:Show()
        row.btnInvite:Show()
        row.btnInvite:ClearAllPoints()
        row.btnInvite:SetPoint("RIGHT", row.btnRemove, "LEFT", -6, 0)

        row.btnWhisper:Show()
        row.btnWhisper:ClearAllPoints()
        row.btnWhisper:SetPoint("RIGHT", row.btnInvite, "LEFT", -6, 0)

        row.btnAction:Show()
        row.btnAction:ClearAllPoints()
        row.btnAction:SetPoint("RIGHT", row.btnWhisper, "LEFT", -6, 0)
        row.btnAction:SetWidth(68)
        row._actionVariant = "primary"
        Theme:StyleButton(row.btnAction, "primary")
        Theme:SetButtonText(row.btnAction, L["Check"])

        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        local cd = ns.Watchlist and ns.Watchlist:GetCooldownRemaining() or 0
        local busy = ns.Watchlist and ns.Watchlist:IsBusy()
        row.btnAction:SetEnabled((not inCombat) and (not busy) and cd <= 0)

    elseif tab == "social" then
        Theme:ApplyStatusColor(row.dot, "online")
        local flags = ""
        if item.afk then flags = flags .. " |cffffd24d[AFK]|r" end
        if item.dnd then flags = flags .. " |cffff6b6b[DND]|r" end
        row.nameText:SetText(hex .. (item.displayName or "") .. "|r" .. levelStr .. flags)
        row.subText:SetText(FormatSocialSubline(item))

        row.btnWhisper:Show()
        row.btnWhisper:ClearAllPoints()
        row.btnWhisper:SetPoint("RIGHT", -8, 0)

        local anchor = row.btnWhisper
        if item.sameFaction ~= false and item.samePool ~= false then
            row.btnInvite:Show()
            row.btnInvite:ClearAllPoints()
            row.btnInvite:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
            anchor = row.btnInvite
        end

        row.btnAction:Show()
        row.btnAction:ClearAllPoints()
        row.btnAction:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
        row._actionVariant = "default"
        Theme:StyleButton(row.btnAction, "default")
        Theme:SetButtonText(row.btnAction, "+ " .. L["Watchlist"])
        row.btnAction:SetWidth(86)
        row.btnAction:SetEnabled(true)

    elseif tab == "nearby" then
        Theme:ApplyStatusColor(row.dot, "nearby")
        local srcTag = item.source and (" |cff6ec1e4[" .. item.source .. "]|r") or ""
        row.nameText:SetText(hex .. (item.displayName or "") .. "|r" .. levelStr .. srcTag)

        local subParts = {}
        if item.area and item.area ~= "" then table.insert(subParts, item.area) end
        table.insert(subParts, L["Recent"] .. ": " .. Compat.FormatRelativeTime(item.lastSeen, L))
        row.subText:SetText(table.concat(subParts, "  ·  "))

        row.btnWhisper:Show()
        row.btnWhisper:ClearAllPoints()
        row.btnWhisper:SetPoint("RIGHT", -8, 0)

        row.btnInvite:Show()
        row.btnInvite:ClearAllPoints()
        row.btnInvite:SetPoint("RIGHT", row.btnWhisper, "LEFT", -6, 0)

        row.btnAction:Show()
        row.btnAction:ClearAllPoints()
        row.btnAction:SetPoint("RIGHT", row.btnInvite, "LEFT", -6, 0)
        row._actionVariant = "default"
        Theme:StyleButton(row.btnAction, "default")
        Theme:SetButtonText(row.btnAction, "+ " .. L["Watchlist"])
        row.btnAction:SetWidth(86)
        row.btnAction:SetEnabled(true)

    elseif tab == "alts" then
        Theme:ApplyStatusColor(row.dot, item.key == Compat.CharacterKey() and "online" or "offline")
        local factionTag = item.faction and (" |cff9da7b5[" .. item.faction .. "]|r") or ""
        row.nameText:SetText(hex .. (item.name or "") .. "|r" .. levelStr .. factionTag)

        local parts = {}
        if item.zone and item.zone ~= "" then table.insert(parts, item.zone) end
        if item.guild and item.guild ~= "" then table.insert(parts, "<" .. item.guild .. ">") end
        table.insert(parts, Compat.FormatMoney(item.money))
        if item.rested and item.rested > 0 then
            table.insert(parts, L["Rested"] .. ": " .. tostring(math.floor(item.rested)) .. " XP")
        end
        table.insert(parts, Compat.FormatRelativeTime(item.lastActive, L))
        row.subText:SetText(table.concat(parts, "  ·  "))
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
            if SafeTextMatches(searchQuery, item.displayName, item.area, item.source) then
                local copy = {}
                for k, v in pairs(item) do copy[k] = v end
                copy._tab = "nearby"
                table.insert(out, copy)
            end
        end
    elseif activeTab == "alts" and ns.Store then
        for _, alt in ipairs(ns.Store:GetAltsList()) do
            if SafeTextMatches(searchQuery, alt.name, alt.zone, alt.guild, alt.faction) then
                local copy = {}
                for k, v in pairs(alt) do copy[k] = v end
                copy._tab = "alts"
                copy.displayName = alt.name
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

    row.btnDel = Theme:CreateButton(row, 20, 20, "×", "danger")
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
        if row._evt and ns.Clan then ns.Clan:SignupEvent(row._evt.id, "TANK") end
    end)
    row.btnHeal:SetScript("OnClick", function()
        if row._evt and ns.Clan then ns.Clan:SignupEvent(row._evt.id, "HEALER") end
    end)
    row.btnDps:SetScript("OnClick", function()
        if row._evt and ns.Clan then ns.Clan:SignupEvent(row._evt.id, "DPS") end
    end)
    row.btnDel:SetScript("OnClick", function()
        if row._evt and ns.Clan then ns.Clan:RemoveEvent(row._evt.id) end
    end)

    row:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" and self._evt then
            OpenEventMenu(self, self._evt)
        end
    end)

    row:SetScript("OnEnter", function(self)
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(self, "surface", p)
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

    Theme:SetButtonActive(row.btnTank, myRole == "TANK", "default")
    Theme:SetButtonActive(row.btnHeal, myRole == "HEALER", "default")
    Theme:SetButtonActive(row.btnDps, myRole == "DPS", "default")
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

    row.btnInvite = Theme:CreateButton(row, 22, 20, "I", "default")
    row.btnInvite:SetPoint("RIGHT", -6, 0)

    row.btnWhisper = Theme:CreateButton(row, 22, 20, "W", "default")
    row.btnWhisper:SetPoint("RIGHT", row.btnInvite, "LEFT", -4, 0)

    row.nameText:SetPoint("RIGHT", row.btnWhisper, "LEFT", -6, 0)
    row.subText:SetPoint("RIGHT", row.btnWhisper, "LEFT", -6, 0)

    row.btnWhisper:SetScript("OnClick", function()
        if row._item and row._item.displayName then
            Compat.Whisper(row._item.displayName)
        end
    end)
    row.btnInvite:SetScript("OnClick", function()
        if row._item and row._item.displayName then
            Compat.Invite(row._item.displayName)
        end
    end)

    row:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" and self._item then
            local menuItem = {}
            for k, v in pairs(self._item) do menuItem[k] = v end
            menuItem._tab = "social"
            OpenRowMenu(self, menuItem)
        end
    end)

    row:SetScript("OnEnter", function(self)
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(self, "surface", p)
        if self._item then
            local item = self._item
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine((item.displayName or "") .. (item.version and ("  (v" .. item.version .. ")") or ""), 1, 1, 1)
            if item._clanView == "prof" then
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
        Theme:StyleButton(self.btnInvite, "default")
        Theme:StyleButton(self.btnWhisper, "default")
    end

    return row
end

local function UpdatePeerRow(row, item, idx, palette)
    row._item = item
    row._dataIdx = idx
    row.subText:SetTextColor(palette.textMuted[1], palette.textMuted[2], palette.textMuted[3])
    local isOnline = item._clanView == "gchat" and true or (item.online == true)
    Theme:ApplyStatusColor(row.dot, item._clanView == "gchat" and "nearby" or (isOnline and "online" or "offline"))

    local hex = Compat.ClassHex(item.classFile)
    if item._clanView == "prof" then
        local pMap = (ns.SocialPanels and ns.SocialPanels.PROF_LABELS) or {}
        local pList = {}
        if item.prof1 and item.prof1 ~= "NONE" then table.insert(pList, pMap[item.prof1] or item.prof1) end
        if item.prof2 and item.prof2 ~= "NONE" then table.insert(pList, pMap[item.prof2] or item.prof2) end
        row.nameText:SetText(hex .. (item.displayName or "") .. "|r  |cff3fb950[" .. table.concat(pList, " / ") .. "]|r")
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

    local ver = item.version and (" |cff9da7b5[v" .. item.version .. "]|r") or ""
    row.nameText:SetText(hex .. (item.displayName or "") .. "|r" .. ver)

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
        table.insert(sub, Compat.FormatRelativeTime(item.updatedAt, L))
    end
    row.subText:SetText(table.concat(sub, "  ·  "))
end

local function UpdateClanPanel()
    if not clanPanel then
        return
    end
    local p = Theme:GetPalette()
    Theme:ApplyBackdrop(clanPanel.guildCard, "surface", p)
    Theme:ApplyBackdrop(clanPanel.eventsCard, "surface", p)
    Theme:ApplyBackdrop(clanPanel.peersCard, "surface", p)

    local info = ns.Store and ns.Store.guildInfo or {}
    if info.inGuild then
        clanPanel.guildName:SetText(info.name or L["Guild"])
        clanPanel.guildCounts:SetText(string.format("%s: %d / %d", L["Online Members"], info.onlineCount or 0, info.totalCount or 0))
        local motd = (info.motd and info.motd ~= "") and info.motd or "-"
        clanPanel.guildMotd:SetText(L["Message of the Day"] .. ": " .. motd)
    else
        clanPanel.guildName:SetText(L["No guild"])
        clanPanel.guildCounts:SetText("")
        clanPanel.guildMotd:SetText("")
    end

    local syncEnabled = ns.db and ns.db.settings and ns.db.settings.clanSync
    clanPanel.syncCheck:SetChecked(syncEnabled and true or false)

    local bucket = ns.Store and ns.Store:GetClanScopeData() or { myTag = "NONE", myNote = "" }
    local tagName = TAG_LABELS[bucket.myTag or "NONE"] or L["No Status"]
    Theme:SetButtonText(clanPanel.statusBtn, L["My Status: %s"]:format(tagName))

    for id, b in pairs(clanEventFilterButtons) do
        Theme:SetButtonActive(b, clanEventFilter == id, "default")
    end
    for id, b in pairs(clanRightViewButtons) do
        Theme:SetButtonActive(b, clanRightView == id, "default")
    end

    local peers = ns.Clan and ns.Clan:GetPeersList() or {}
    local events = ns.Clan and ns.Clan:GetEventsList(clanEventFilter) or {}
    local locked = ns.Clan and ns.Clan:IsMessagingLocked()
    local modeTag = syncEnabled and (locked and L["Locked"] or "SCentral1") or L["Local only"]
    clanPanel.syncStatus:SetText(string.format("SCentral1  ·  %s: %d  ·  [%s]", L["Peers"], #peers, modeTag))
    clanPanel.syncStatus:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])

    clanPanel.eventsScroll:SetData(events, L["No Clan event calls yet. Click '+ Event Call' to create one!"], false)

    if clanRightView == "prof" then
        local profList = {}
        for _, item in ipairs(ns.Clan and ns.Clan:GetProfessionsList() or {}) do
            local copy = {}
            for k, v in pairs(item) do copy[k] = v end
            copy._clanView = "prof"
            table.insert(profList, copy)
        end
        clanPanel.peersScroll:SetData(profList, L["No Clan professions set yet. Click '+ Prof' above to add yours!"], false)
    elseif clanRightView == "gchat" then
        local gcList = {}
        for _, item in ipairs(ns.Clan and ns.Clan:GetGuildChatLFGList() or {}) do
            local copy = {}
            for k, v in pairs(item) do copy[k] = v end
            copy._clanView = "gchat"
            table.insert(gcList, copy)
        end
        clanPanel.peersScroll:SetData(gcList, L["No /g LFM calls captured yet (enable 'Detect LFM calls in Guild chat' in Settings)."], false)
    else
        clanPanel.peersScroll:SetData(peers, L["No Clan peers seen yet. Enable Clan Sync or click 'Sync'."], false)
    end
end

local function CreateClanPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    local guildCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    guildCard:SetPoint("TOPLEFT", 2, -2)
    guildCard:SetPoint("TOPRIGHT", -2, -2)
    guildCard:SetHeight(54)

    local guildName = guildCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guildName:SetPoint("TOPLEFT", 12, -8)

    local guildCounts = guildCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    guildCounts:SetPoint("TOPRIGHT", -12, -9)

    local guildMotd = guildCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    guildMotd:SetPoint("TOPLEFT", guildName, "BOTTOMLEFT", 0, -6)
    guildMotd:SetPoint("BOTTOMRIGHT", -12, 6)
    guildMotd:SetJustifyH("LEFT")
    guildMotd:SetWordWrap(false)

    local controlsBar = CreateFrame("Frame", nil, panel)
    controlsBar:SetPoint("TOPLEFT", guildCard, "BOTTOMLEFT", 0, -6)
    controlsBar:SetPoint("TOPRIGHT", guildCard, "BOTTOMRIGHT", 0, -6)
    controlsBar:SetHeight(28)

    local cb = CreateFrame("CheckButton", nil, controlsBar, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("LEFT", 0, 0)

    local cbLabel = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbLabel:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cbLabel:SetText(L["Clan Sync"])

    cb:SetScript("OnClick", function(self)
        if ns.db and ns.db.settings then
            ns.db.settings.clanSync = self:GetChecked() and true or false
            UpdateClanPanel()
        end
    end)

    local syncHelp = AddHelp(
        controlsBar,
        cbLabel,
        L["Help: Clan Guild Sync"],
        L["Enables encrypted-free opt-in guild addon messages (SCentral1) to share Status Tags, Event Calls, and Dungeon/Raid Signups with guildmates."],
        L["Leave unchecked for 100% local Clan tracking, or enable to sync tags and event calls safely with guildmates who also use SocialCentral."]
    )

    local statusBtn = Theme:CreateButton(controlsBar, 124, 22, L["My Status"], "default")
    if statusBtn.label then
        statusBtn.label:ClearAllPoints()
        statusBtn.label:SetPoint("LEFT", 6, 0)
        statusBtn.label:SetPoint("RIGHT", -6, 0)
        statusBtn.label:SetWordWrap(false)
    end
    statusBtn:SetPoint("LEFT", syncHelp, "RIGHT", 8, 0)
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
            end)
        else
            OpenClanNoteModal(bucket.myTag, bucket.myNote)
        end
    end)

    local statusHelp = AddHelp(
        controlsBar,
        statusBtn,
        L["Help: Clan Status Tag"],
        L["Broadcasts your current activity tag (LFG, M+, Raid, PvP, etc.) and optional short note to guildmates using SocialCentral."],
        L["Click 'My Status', pick an activity tag, and optionally add a short note like '+10 tank LFG'."]
    )

    local newEventBtn = Theme:CreateButton(controlsBar, 96, 22, L["+ Event Call"], "primary")
    newEventBtn:SetPoint("LEFT", statusHelp, "RIGHT", 8, 0)
    newEventBtn:SetScript("OnClick", OpenEventModal)
    themeTargets[#themeTargets + 1] = { btn = newEventBtn, variant = "primary" }

    local eventHelp = AddHelp(
        controlsBar,
        newEventBtn,
        L["Help: Clan Event Calls"],
        L["Creates guild-wide group calls for Dungeons, M+, Raids, World Bosses, or PvP where guildmates sign up as Tank, Healer, DPS, or Maybe."],
        L["Click '+ Event Call' to post an event, click T / H / D on any row to sign up, hover for the full roster, or right-click to invite applicants or close."]
    )

    local profBtn = Theme:CreateButton(controlsBar, 74, 22, "+ " .. L["Prof"], "default")
    profBtn:SetPoint("LEFT", eventHelp, "RIGHT", 8, 0)
    profBtn:SetScript("OnClick", function()
        if ns.SocialPanels and ns.SocialPanels.OpenProfessionModal then
            ns.SocialPanels:OpenProfessionModal()
        end
    end)
    themeTargets[#themeTargets + 1] = { btn = profBtn, variant = "default" }

    local profHelp = AddHelp(
        controlsBar,
        profBtn,
        L["Help: Clan Professions"],
        L["Share up to 2 crafting professions and a short service note (e.g. Flasks, Lariat, Enchanting) with guildmates using SocialCentral."],
        L["Click '+ Prof' to set your professions, then view the 'Professions' subtab on the right panel to find guild crafters."]
    )

    local syncBtn = Theme:CreateButton(controlsBar, 54, 22, L["Sync"], "default")
    syncBtn:SetPoint("LEFT", profHelp, "RIGHT", 8, 0)
    syncBtn:SetScript("OnClick", function()
        if ns.Clan then ns.Clan:RequestClanSync() end
    end)
    themeTargets[#themeTargets + 1] = { btn = syncBtn, variant = "default" }

    AddHelp(
        controlsBar,
        syncBtn,
        L["Help: Clan Sync & Roster"],
        L["Manually requests fresh status tags from online guildmates without background spam loops (max once every 5s, disabled in combat)."],
        L["Check 'Clan Sync' to enable guild addon comms, then click 'Sync' whenever you log in or want refreshed guildmate tags."]
    )

    local syncStatus = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    syncStatus:SetPoint("TOPLEFT", controlsBar, "BOTTOMLEFT", 2, -2)
    syncStatus:SetPoint("TOPRIGHT", controlsBar, "BOTTOMRIGHT", -2, -2)
    syncStatus:SetJustifyH("LEFT")

    local eventsCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    eventsCard:SetPoint("TOPLEFT", syncStatus, "BOTTOMLEFT", -2, -6)
    eventsCard:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -4, 4)

    local eventsTitle = eventsCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    eventsTitle:SetPoint("TOPLEFT", 10, -8)
    eventsTitle:SetText(L["Event Calls & Signups"])
    AddHelp(
        eventsCard,
        eventsTitle,
        L["Help: Clan Event Calls"],
        L["Creates guild-wide group calls for Dungeons, M+, Raids, World Bosses, or PvP where guildmates sign up as Tank, Healer, DPS, or Maybe."],
        L["Click '+ Event Call' to post an event, click T / H / D on any row to sign up, hover for the full roster, or right-click to invite applicants or close."]
    )

    local evtFilterRow = CreateFrame("Frame", nil, eventsCard)
    evtFilterRow:SetPoint("TOPLEFT", 8, -28)
    evtFilterRow:SetPoint("TOPRIGHT", -8, -28)
    evtFilterRow:SetHeight(22)

    local evtFilters = {
        { id = "all", label = L["All"], w = 52 },
        { id = "open", label = L["Open Only"], w = 78 },
        { id = "need_tank", label = L["Need T"], w = 66 },
        { id = "need_heal", label = L["Need H"], w = 66 },
    }
    local prevEvtF
    for _, ef in ipairs(evtFilters) do
        local b = Theme:CreateButton(evtFilterRow, ef.w, 20, ef.label, "default")
        if not prevEvtF then
            b:SetPoint("LEFT", evtFilterRow, "LEFT", 0, 0)
        else
            b:SetPoint("LEFT", prevEvtF, "RIGHT", 4, 0)
        end
        b:SetScript("OnClick", function()
            clanEventFilter = ef.id
            UpdateClanPanel()
        end)
        clanEventFilterButtons[ef.id] = b
        themeTargets[#themeTargets + 1] = { btn = b, variant = "default" }
        prevEvtF = b
    end

    local eventsHolder = CreateFrame("Frame", nil, eventsCard)
    eventsHolder:SetPoint("TOPLEFT", 6, -54)
    eventsHolder:SetPoint("BOTTOMRIGHT", -6, 6)
    local eventsScroll = Theme:CreateScrollList(eventsHolder, 54, CreateEventRow, UpdateEventRow)
    eventsScroll.container:SetAllPoints()

    local peersCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    peersCard:SetPoint("TOPLEFT", eventsCard, "TOPRIGHT", 8, 0)
    peersCard:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 4)

    local peersTitle = peersCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    peersTitle:SetPoint("TOPLEFT", 10, -8)
    peersTitle:SetText(L["Clan Members & Status"])
    AddHelp(
        peersCard,
        peersTitle,
        L["Help: Clan Sync & Roster"],
        L["Manually requests fresh status tags from online guildmates without background spam loops (max once every 5s, disabled in combat)."],
        L["Switch between 'Peers', 'Professions', and 'Guild Chat' LFM sightings using the filter buttons below."]
    )

    local rightViewRow = CreateFrame("Frame", nil, peersCard)
    rightViewRow:SetPoint("TOPLEFT", 8, -28)
    rightViewRow:SetPoint("TOPRIGHT", -8, -28)
    rightViewRow:SetHeight(22)

    local rightViews = {
        { id = "peers", label = L["Peers"], w = 72 },
        { id = "prof", label = L["Professions"], w = 96 },
        { id = "gchat", label = L["Guild Chat"], w = 92 },
    }
    local prevRV
    for _, rv in ipairs(rightViews) do
        local b = Theme:CreateButton(rightViewRow, rv.w, 20, rv.label, "default")
        if not prevRV then
            b:SetPoint("LEFT", rightViewRow, "LEFT", 0, 0)
        else
            b:SetPoint("LEFT", prevRV, "RIGHT", 4, 0)
        end
        b:SetScript("OnClick", function()
            clanRightView = rv.id
            UpdateClanPanel()
        end)
        clanRightViewButtons[rv.id] = b
        themeTargets[#themeTargets + 1] = { btn = b, variant = "default" }
        prevRV = b
    end

    local peersHolder = CreateFrame("Frame", nil, peersCard)
    peersHolder:SetPoint("TOPLEFT", 6, -54)
    peersHolder:SetPoint("BOTTOMRIGHT", -6, 6)
    local peersScroll = Theme:CreateScrollList(peersHolder, 42, CreatePeerRow, UpdatePeerRow)
    peersScroll.container:SetAllPoints()

    panel.guildCard = guildCard
    panel.guildName = guildName
    panel.guildCounts = guildCounts
    panel.guildMotd = guildMotd
    panel.syncCheck = cb
    panel.statusBtn = statusBtn
    panel.syncStatus = syncStatus
    panel.eventsCard = eventsCard
    panel.eventsScroll = eventsScroll
    panel.peersCard = peersCard
    panel.peersScroll = peersScroll
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

local function ApplyTheme()
    if not frame then
        return
    end
    local p = Theme:GetPalette()
    Theme:ApplyBackdrop(frame, "window", p)
    Theme:ApplyBackdrop(frame.header, "header", p)
    for _, item in ipairs(themeTargets) do
        Theme:StyleButton(item.btn, item.variant)
    end
    if frame.themeBtn then
        Theme:SetButtonText(frame.themeBtn, p.key == "dark" and L["Modern Dark"] or L["Native Warcraft"])
    end
    if frame.summaryText then
        frame.summaryText:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
    end
    if frame.altsGoldText then
        frame.altsGoldText:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
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
    UI:Refresh()
end

local function BuildMainFrame()
    frame = CreateFrame("Frame", "SocialCentralFrame", UIParent, "BackdropTemplate")
    local w = ns.db and ns.db.window or { width = 790, height = 520 }
    frame:SetSize(w.width or 790, w.height or 520)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(680, 440, 1140, 840)
    elseif frame.SetMinResize then
        frame:SetMinResize(680, 440)
        frame:SetMaxResize(1140, 840)
    end

    if w.point and w.x and w.y then
        frame:SetPoint(w.point, UIParent, w.relativePoint or w.point, w.x, w.y)
    else
        frame:SetPoint("CENTER")
    end

    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetFrameStrata("MEDIUM")
    table.insert(UISpecialFrames, "SocialCentralFrame")

    -- Header Bar
    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(42)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SaveGeometry()
    end)
    frame.header = header

    local headerIcon = header:CreateTexture(nil, "ARTWORK")
    headerIcon:SetSize(22, 22)
    headerIcon:SetPoint("LEFT", 12, 0)
    headerIcon:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\icon")

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", headerIcon, "RIGHT", 7, 0)
    title:SetText("SocialCentral")

    local verText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verText:SetPoint("LEFT", title, "RIGHT", 8, -1)
    verText:SetText("v" .. (ns.version or "dev"))

    local summaryText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summaryText:SetPoint("LEFT", verText, "RIGHT", 16, 0)
    frame.summaryText = summaryText

    local closeBtn = Theme:CreateButton(header, 26, 24, "×", "danger")
    closeBtn:SetPoint("RIGHT", -10, 0)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    themeTargets[#themeTargets + 1] = { btn = closeBtn, variant = "danger" }

    local settingsBtn = Theme:CreateButton(header, 90, 24, L["Settings"], "default")
    settingsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    settingsBtn:SetScript("OnClick", function()
        if ns.Settings then ns.Settings:Open() end
    end)
    themeTargets[#themeTargets + 1] = { btn = settingsBtn, variant = "default" }

    local themeBtn = Theme:CreateButton(header, 76, 24, L["Modern Dark"], "default")
    if themeBtn.label then
        themeBtn.label:ClearAllPoints()
        themeBtn.label:SetPoint("LEFT", 4, 0)
        themeBtn.label:SetPoint("RIGHT", -4, 0)
        themeBtn.label:SetWordWrap(false)
    end
    themeBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
    themeBtn:SetScript("OnClick", function()
        if ns.db and ns.db.settings then
            ns.db.settings.theme = ns.db.settings.theme == "dark" and "native" or "dark"
            Theme:NotifyChanged()
        end
    end)
    frame.themeBtn = themeBtn
    themeTargets[#themeTargets + 1] = { btn = themeBtn, variant = "default" }

    local updateBtn = Theme:CreateButton(header, 82, 24, L["Update"], "default")
    if updateBtn.label then
        updateBtn.label:ClearAllPoints()
        updateBtn.label:SetPoint("LEFT", 4, 0)
        updateBtn.label:SetPoint("RIGHT", -4, 0)
        updateBtn.label:SetWordWrap(false)
    end
    updateBtn:SetPoint("RIGHT", themeBtn, "LEFT", -6, 0)
    updateBtn:SetScript("OnClick", function()
        UI:OpenUpdateModal()
    end)
    frame.updateBtn = updateBtn
    themeTargets[#themeTargets + 1] = { btn = updateBtn, variant = "default" }

    local headerHelp = AddHelp(
        header,
        updateBtn,
        L["Help: SocialCentral Overview"],
        L["Blizzard-safe social center integrating Friends, Guild, Battle.net, Friendly Nearby, Alts Gold, Watchlist (/who), and Clan Hub."],
        L["Use '/sc', '/sc check Name', or '/sc config', or click the Minimap button. Hover or click '?' beside any option for detailed guidance."],
        "RIGHT",
        "LEFT",
        -6,
        0
    )

    summaryText:SetPoint("RIGHT", headerHelp, "LEFT", -10, 0)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetWordWrap(false)

    -- Tab Strip
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -8)
    tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -12, -8)
    tabBar:SetHeight(28)

    local tabDefs = {
        { id = "watchlist", label = L["Watchlist"], width = 108 },
        { id = "social", label = L["Social"], width = 94 },
        { id = "clan", label = L["Clan"], width = 80 },
        { id = "group", label = L["Group"], width = 90 },
        { id = "chat", label = L["Chat"], width = 88 },
        { id = "nearby", label = L["Nearby"], width = 98 },
        { id = "alts", label = L["Alts"], width = 84 },
    }
    local prevTab
    for _, def in ipairs(tabDefs) do
        local btn = Theme:CreateButton(tabBar, def.width, 26, def.label, "tab")
        if btn.label then
            btn.label:ClearAllPoints()
            btn.label:SetPoint("LEFT", 4, 0)
            btn.label:SetPoint("RIGHT", -4, 0)
            btn.label:SetJustifyH("CENTER")
            btn.label:SetWordWrap(false)
        end
        if not prevTab then
            btn:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", prevTab, "RIGHT", 6, 0)
        end
        btn:SetScript("OnClick", function()
            activeTab = def.id
            if def.id == "social" and ns.Social then
                ns.Social:RequestRosters(false)
            elseif def.id == "group" and ns.Group then
                ns.Group:Scan()
            end
            UI:Refresh(true)
        end)
        tabButtons[def.id] = { btn = btn, baseLabel = def.label }
        themeTargets[#themeTargets + 1] = { btn = btn, variant = "tab" }
        prevTab = btn
    end

    -- Filter / Search Bar
    local filterBar = CreateFrame("Frame", nil, frame)
    filterBar:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -8)
    filterBar:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, -8)
    filterBar:SetHeight(26)
    frame.filterBar = filterBar

    searchBox = CreateFrame("EditBox", "SocialCentralSearchBox", filterBar, "SearchBoxTemplate")
    searchBox:SetSize(215, 24)
    searchBox:SetPoint("LEFT", 4, 0)
    searchBox:SetAutoFocus(false)
    if searchBox.Instructions then
        searchBox.Instructions:SetText(L["Search name, zone, guild or note..."])
    end
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
    if groupFilterBtn.label then
        groupFilterBtn.label:ClearAllPoints()
        groupFilterBtn.label:SetPoint("LEFT", 6, 0)
        groupFilterBtn.label:SetPoint("RIGHT", -6, 0)
        groupFilterBtn.label:SetJustifyH("CENTER")
        groupFilterBtn.label:SetWordWrap(false)
    end
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

    AddHelp(
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
        L["Tracks level, zone, guild, rested XP, and total gold across all your characters on this account pool."],
        L["Simply log in once on each alt for SocialCentral to save its gold and location automatically."],
        "RIGHT",
        "RIGHT",
        -2,
        0
    )

    local altsGoldText = altsBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    altsGoldText:SetPoint("RIGHT", altsHelp, "LEFT", -8, 0)
    altsGoldText:SetJustifyH("RIGHT")
    frame.altsGoldText = altsGoldText

    local nearbyBar = CreateFrame("Frame", nil, filterBar)
    nearbyBar:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    nearbyBar:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
    nearbyBar:SetHeight(26)
    frame.nearbyBar = nearbyBar

    AddHelp(
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

    local filterDefs = {
        { id = "all", label = L["All"], width = 54 },
        { id = "guild", label = L["Guild"], width = 66 },
        { id = "friend", label = L["Friends"], width = 72 },
        { id = "bnet", label = L["Battle.net"], width = 82 },
    }
    local prevFilter
    for _, def in ipairs(filterDefs) do
        local btn = Theme:CreateButton(socialBar, def.width, 22, def.label, "default")
        if not prevFilter then
            btn:SetPoint("LEFT", socialBar, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", prevFilter, "RIGHT", 5, 0)
        end
        btn:SetScript("OnClick", function()
            socialFilter = def.id
            UI:Refresh(true)
        end)
        socialFilterButtons[def.id] = btn
        themeTargets[#themeTargets + 1] = { btn = btn, variant = "default" }
        prevFilter = btn
    end

    local socialFolderBtn = Theme:CreateButton(socialBar, 108, 22, L["All Folders"], "default")
    if socialFolderBtn.label then
        socialFolderBtn.label:ClearAllPoints()
        socialFolderBtn.label:SetPoint("LEFT", 4, 0)
        socialFolderBtn.label:SetPoint("RIGHT", -4, 0)
        socialFolderBtn.label:SetWordWrap(false)
    end
    socialFolderBtn:SetPoint("LEFT", prevFilter, "RIGHT", 6, 0)
    themeTargets[#themeTargets + 1] = { btn = socialFolderBtn, variant = "default" }
    frame.socialFolderBtn = socialFolderBtn

    socialFolderBtn:SetScript("OnClick", function(self)
        local folders = ns.Store and ns.Store:GetSocialFolders() or {}
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                local addChoice = root.CreateRadio or root.CreateCheckbox
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
            local opts = { "all" }
            for _, fName in ipairs(folders) do table.insert(opts, fName) end
            local nextIdx = 1
            for idx, v in ipairs(opts) do
                if v == socialFolderFilter then nextIdx = (idx % #opts) + 1; break end
            end
            socialFolderFilter = opts[nextIdx]
            UI:Refresh(true)
        end
    end)

    if socialHelp then
        socialHelp:Raise()
    end

    -- Watchlist Input Bar
    local watchBar = CreateFrame("Frame", nil, frame)
    watchBar:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -8)
    watchBar:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", 0, -8)
    watchBar:SetHeight(28)
    frame.watchBar = watchBar

    addBox = CreateFrame("EditBox", "SocialCentralAddInput", watchBar, "InputBoxTemplate")
    addBox:SetSize(205, 24)
    addBox:SetPoint("LEFT", 6, 0)
    addBox:SetAutoFocus(false)
    addBox:SetMaxLetters(64)

    local placeholder = addBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 4, 0)
    placeholder:SetText(L["Character name (Name or Name-Surname)"])

    local function UpdatePlaceholder()
        local hasText = (addBox:GetText() or "") ~= ""
        placeholder:SetShown(not hasText and not addBox:HasFocus())
    end
    addBox:SetScript("OnEditFocusGained", UpdatePlaceholder)
    addBox:SetScript("OnEditFocusLost", UpdatePlaceholder)
    addBox:SetScript("OnTextChanged", UpdatePlaceholder)

    local function SubmitAdd()
        if not ns.Watchlist then return end
        local ok, reason = ns.Watchlist:Add(addBox:GetText() or "")
        if ok then
            addBox:SetText("")
            addBox:ClearFocus()
            UpdatePlaceholder()
        elseif reason == "invalid" then
            ns:Print(L["Type a valid character name (at least 2 letters)."])
        end
    end

    local function SubmitAddAndCheck()
        if not ns.Watchlist then return end
        local raw = addBox:GetText() or ""
        local ok = ns.Watchlist:AddAndCheck(raw)
        if ok then
            addBox:SetText("")
            addBox:ClearFocus()
            UpdatePlaceholder()
        end
    end

    addBox:SetScript("OnEnterPressed", SubmitAdd)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local addBtn = Theme:CreateButton(watchBar, 72, 24, L["Add"], "default")
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 6, 0)
    addBtn:SetScript("OnClick", SubmitAdd)
    themeTargets[#themeTargets + 1] = { btn = addBtn, variant = "default" }

    checkAddBtn = Theme:CreateButton(watchBar, 76, 24, L["+ /who"], "default")
    checkAddBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    checkAddBtn:SetScript("OnClick", SubmitAddAndCheck)
    themeTargets[#themeTargets + 1] = { btn = checkAddBtn, variant = "default" }

    local targetBtn = Theme:CreateButton(watchBar, 80, 24, L["+ Target"], "default")
    targetBtn:SetPoint("LEFT", checkAddBtn, "RIGHT", 6, 0)
    targetBtn:SetScript("OnClick", function()
        if ns.Watchlist then ns.Watchlist:AddTarget() end
    end)
    themeTargets[#themeTargets + 1] = { btn = targetBtn, variant = "default" }

    local watchHelp = AddHelp(
        watchBar,
        watchBar,
        L["Help: Manual Watchlist & /who"],
        L["Lets you add any character manually and run an official single /who query outside combat with cooldown >= 5s."],
        L["Type Name or Name-Surname. Click 'Add' to save, '+ /who' to save & query immediately, '+ Target' for your current target, or 'Check Next' to check the oldest entry."],
        "RIGHT",
        "RIGHT",
        -2,
        0
    )

    checkNextBtn = Theme:CreateButton(watchBar, 116, 24, L["Check Next"], "primary")
    checkNextBtn:SetPoint("RIGHT", watchHelp, "LEFT", -6, 0)
    checkNextBtn:SetScript("OnClick", function()
        if ns.Watchlist then ns.Watchlist:CheckNext() end
    end)
    themeTargets[#themeTargets + 1] = { btn = checkNextBtn, variant = "primary" }

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
        SaveGeometry()
    end)

    frame:SetScript("OnShow", function()
        if ns.Social then ns.Social:RequestRosters(false) end
        if ticker then ticker:Cancel() end
        ticker = C_Timer.NewTicker(1, function()
            if frame and frame:IsShown() then
                UpdateWhoButtons()
                if activeTab ~= "clan" and activeTab ~= "group" and activeTab ~= "chat" and scrollList then
                    scrollList:Render()
                end
            end
        end)
        UI:Refresh(true)
    end)

    frame:SetScript("OnHide", function()
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
        SaveGeometry()
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

    local counts = {
        watchlist = watchCount,
        social = socialCount,
        nearby = nearbyCount,
        alts = altsCount,
        group = groupCount > 0 and groupCount or nil,
        chat = chatUnread > 0 and chatUnread or nil,
    }

    for id, info in pairs(tabButtons) do
        local label = counts[id] and string.format("%s (%d)", info.baseLabel, counts[id]) or info.baseLabel
        Theme:SetButtonText(info.btn, label)
        Theme:SetButtonActive(info.btn, activeTab == id, "tab")
    end

    if ns.Watchlist then
        local on, off, unk = ns.Watchlist:GetStats()
        frame.summaryText:SetText(string.format("%s: %d  |  %s: %d  |  %s: %d", L["Online"], on, L["Offline"], off, L["Unchecked"], unk))
    end

    if frame.updateBtn then
        local remoteVer = ns.Clan and ns.Clan.latestRemoteVersion
        local hasUpdate = remoteVer and Compat.CompareSemVer(remoteVer, ns.version or "0.2.2") > 0
        if hasUpdate then
            Theme:SetButtonText(frame.updateBtn, L["Update %s"]:format("v" .. remoteVer))
            Theme:SetButtonActive(frame.updateBtn, true, "primary")
        else
            Theme:SetButtonText(frame.updateBtn, L["Update"])
            Theme:SetButtonActive(frame.updateBtn, false, "default")
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

    local isFullPanel = (activeTab == "clan" or activeTab == "group" or activeTab == "chat")
    frame.filterBar:SetShown(not isFullPanel)
    frame.socialBar:SetShown(activeTab == "social")
    frame.watchFilterBar:SetShown(activeTab == "watchlist")
    frame.altsBar:SetShown(activeTab == "alts")
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
    if frame.socialFolderBtn then
        local fLbl = socialFolderFilter == "all" and L["All Folders"] or socialFolderFilter
        Theme:SetButtonText(frame.socialFolderBtn, fLbl)
        Theme:SetButtonActive(frame.socialFolderBtn, socialFolderFilter ~= "all")
    end
    if frame.sortBtn then
        local mode = (ns.db and ns.db.settings and ns.db.settings.sortBy) or "status"
        Theme:SetButtonText(frame.sortBtn, GetSortLabel(mode))
    end
    if frame.altsGoldText and ns.Store then
        frame.altsGoldText:SetText(L["Total Gold"] .. ": " .. Compat.FormatMoney(ns.Store:GetTotalAltsGold()))
    end

    for id, btn in pairs(socialFilterButtons) do
        Theme:SetButtonActive(btn, socialFilter == id, "default")
    end

    frame.content:ClearAllPoints()
    if activeTab == "watchlist" then
        frame.content:SetPoint("TOPLEFT", frame.watchBar, "BOTTOMLEFT", 0, -8)
    elseif isFullPanel then
        frame.content:SetPoint("TOPLEFT", tabButtons.watchlist.btn, "BOTTOMLEFT", 0, -10)
    else
        frame.content:SetPoint("TOPLEFT", frame.filterBar, "BOTTOMLEFT", 0, -8)
    end
    frame.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 16)

    clanPanel:SetShown(activeTab == "clan")
    if groupPanel then groupPanel:SetShown(activeTab == "group") end
    if chatPanel then chatPanel:SetShown(activeTab == "chat") end
    scrollList.container:SetShown(not isFullPanel)

    if activeTab == "clan" then
        UpdateClanPanel()
    elseif activeTab == "group" and groupPanel then
        groupPanel:Refresh(resetScroll)
    elseif activeTab == "chat" and chatPanel then
        chatPanel:Refresh(resetScroll)
    else
        local emptyText = activeTab == "watchlist" and L["Watchlist is empty."] or L["No entries match your filter."]
        scrollList:SetData(BuildFilteredRows(), emptyText, resetScroll)
    end

    UpdateWhoButtons()
end

function UI:Show()
    if not frame then
        BuildMainFrame()
    end
    frame:Show()
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
    if tabId and tabButtons[tabId] then
        activeTab = tabId
    end
    frame:Show()
    UI:Refresh(true)
end

function UI:Toggle()
    if not frame then
        BuildMainFrame()
        frame:Show()
        return
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

for _, ev in ipairs({ "WATCHLIST_UPDATED", "SOCIAL_UPDATED", "NEARBY_UPDATED", "ALTS_UPDATED", "CLAN_UPDATED", "GROUP_UPDATED", "CHAT_UPDATED", "VERSION_UPDATE_FOUND" }) do
    ns:On(ev, function()
        UI:Refresh(false)
    end)
end

ns.RegisterEvent(UI, "PLAYER_REGEN_DISABLED", UpdateWhoButtons)
ns.RegisterEvent(UI, "PLAYER_REGEN_ENABLED", UpdateWhoButtons)
