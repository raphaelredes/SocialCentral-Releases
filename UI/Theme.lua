local _, ns = ...

local L = ns.L
local Theme = {}
ns.Theme = Theme

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local listeners = {}

Theme.PALETTES = {
    dark = {
        key = "dark",
        windowBg = { 0.06, 0.07, 0.09, 0.96 },
        windowBorder = { 0.20, 0.24, 0.30, 0.95 },
        headerBg = { 0.09, 0.11, 0.14, 1.0 },
        surfaceBg = { 0.09, 0.11, 0.15, 0.95 },
        surfaceBorder = { 0.18, 0.22, 0.28, 0.90 },
        insetBg = { 0.05, 0.06, 0.08, 0.92 },
        rowBg = { 0.10, 0.12, 0.16, 0.65 },
        rowAltBg = { 0.08, 0.09, 0.12, 0.65 },
        rowHoverBg = { 0.16, 0.21, 0.28, 0.90 },
        rowSelectedBg = { 0.14, 0.27, 0.42, 0.90 },
        accent = { 0.22, 0.65, 0.95, 1.0 },
        accentDim = { 0.13, 0.36, 0.56, 0.90 },
        accentBorder = { 0.30, 0.72, 1.0, 0.95 },
        btnBg = { 0.14, 0.17, 0.22, 0.95 },
        btnHoverBg = { 0.20, 0.25, 0.33, 1.0 },
        btnBorder = { 0.28, 0.33, 0.41, 0.95 },
        dangerBg = { 0.42, 0.14, 0.14, 0.90 },
        dangerHoverBg = { 0.58, 0.18, 0.18, 1.0 },
        dangerBorder = { 0.75, 0.25, 0.25, 0.95 },
        text = { 0.93, 0.95, 0.98 },
        textMuted = { 0.62, 0.68, 0.76 },
        textDim = { 0.44, 0.49, 0.57 },
        online = { 0.24, 0.85, 0.45 },
        offline = { 0.52, 0.55, 0.60 },
        unknown = { 0.95, 0.74, 0.22 },
        nearby = { 0.30, 0.78, 0.98 },
        scrollTrack = { 0.07, 0.08, 0.10, 0.75 },
        scrollThumb = { 0.30, 0.37, 0.48, 0.90 },
        scrollThumbHover = { 0.42, 0.52, 0.66, 1.0 },
    },
    native = {
        key = "native",
        windowBg = { 0.11, 0.10, 0.09, 0.96 },
        windowBorder = { 0.56, 0.48, 0.31, 1.0 },
        headerBg = { 0.16, 0.14, 0.11, 1.0 },
        surfaceBg = { 0.14, 0.13, 0.11, 0.95 },
        surfaceBorder = { 0.45, 0.39, 0.26, 0.95 },
        insetBg = { 0.08, 0.07, 0.06, 0.95 },
        rowBg = { 0.15, 0.14, 0.11, 0.68 },
        rowAltBg = { 0.12, 0.11, 0.09, 0.68 },
        rowHoverBg = { 0.25, 0.22, 0.16, 0.92 },
        rowSelectedBg = { 0.33, 0.26, 0.13, 0.92 },
        accent = { 0.86, 0.68, 0.22, 1.0 },
        accentDim = { 0.44, 0.33, 0.11, 0.95 },
        accentBorder = { 0.92, 0.76, 0.31, 1.0 },
        btnBg = { 0.22, 0.18, 0.13, 0.95 },
        btnHoverBg = { 0.32, 0.26, 0.18, 1.0 },
        btnBorder = { 0.58, 0.49, 0.31, 1.0 },
        dangerBg = { 0.44, 0.15, 0.13, 0.92 },
        dangerHoverBg = { 0.60, 0.20, 0.17, 1.0 },
        dangerBorder = { 0.78, 0.30, 0.26, 0.95 },
        text = { 0.98, 0.94, 0.84 },
        textMuted = { 0.76, 0.70, 0.58 },
        textDim = { 0.54, 0.49, 0.41 },
        online = { 0.25, 0.88, 0.42 },
        offline = { 0.56, 0.54, 0.49 },
        unknown = { 0.98, 0.78, 0.24 },
        nearby = { 0.35, 0.80, 1.0 },
        scrollTrack = { 0.09, 0.08, 0.06, 0.80 },
        scrollThumb = { 0.52, 0.44, 0.28, 0.92 },
        scrollThumbHover = { 0.74, 0.62, 0.38, 1.0 },
    },
}

local BACKDROP_SPEC = {
    bgFile = WHITE8X8,
    edgeFile = WHITE8X8,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local FLAT_BACKDROP_SPEC = {
    bgFile = WHITE8X8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

--- Return the currently selected palette table.
function Theme:GetPalette()
    local key = ns.db and ns.db.settings and ns.db.settings.theme or "dark"
    return self.PALETTES[key] or self.PALETTES.dark
end

--- Register a callback invoked when the active skin changes.
function Theme:RegisterListener(fn)
    if type(fn) == "function" then
        listeners[#listeners + 1] = fn
    end
end

--- Notify registered UI views to re-apply the current palette.
function Theme:NotifyChanged()
    for _, fn in ipairs(listeners) do
        pcall(fn, self:GetPalette())
    end
end

--- Apply a flat or bordered backdrop to a frame created with BackdropTemplate.
function Theme:ApplyBackdrop(frame, kind, palette)
    if not frame or not frame.SetBackdrop then
        return
    end
    local p = palette or self:GetPalette()
    local bg, border

    if kind == "window" then
        bg, border = p.windowBg, p.windowBorder
    elseif kind == "header" then
        bg, border = p.headerBg, p.surfaceBorder
    elseif kind == "surface" then
        bg, border = p.surfaceBg, p.surfaceBorder
    elseif kind == "inset" then
        bg, border = p.insetBg, p.surfaceBorder
    elseif kind == "button" then
        bg, border = p.btnBg, p.btnBorder
    elseif kind == "primary" then
        bg, border = p.accentDim, p.accentBorder
    elseif kind == "danger" then
        bg, border = p.dangerBg, p.dangerBorder
    elseif kind == "row" then
        bg, border = p.rowBg, nil
    elseif kind == "rowAlt" then
        bg, border = p.rowAltBg, nil
    elseif kind == "activeTab" then
        bg, border = p.accentDim, p.accentBorder
    elseif kind == "tab" then
        bg, border = p.surfaceBg, p.surfaceBorder
    else
        bg, border = p.surfaceBg, p.surfaceBorder
    end

    if border then
        frame:SetBackdrop(BACKDROP_SPEC)
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
        frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    else
        frame:SetBackdrop(FLAT_BACKDROP_SPEC)
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    end
end

local function ApplyButtonColors(btn, hovered)
    local p = Theme:GetPalette()
    if not btn.SetBackdrop then
        return
    end
    local variant = btn._scVariant or "default"
    local active = btn._scActive

    local bg, border, textColor
    if not btn:IsEnabled() then
        bg = p.insetBg
        border = p.surfaceBorder
        textColor = p.textDim
    elseif variant == "primary" or active then
        bg = hovered and p.accent or p.accentDim
        border = p.accentBorder
        textColor = active and p.text or p.text
    elseif variant == "danger" then
        bg = hovered and p.dangerHoverBg or p.dangerBg
        border = p.dangerBorder
        textColor = p.text
    elseif variant == "tab" then
        bg = hovered and p.rowHoverBg or p.surfaceBg
        border = p.surfaceBorder
        textColor = hovered and p.text or p.textMuted
    elseif variant == "ghost" then
        bg = hovered and p.rowHoverBg or { 0, 0, 0, 0 }
        border = hovered and p.surfaceBorder or { 0, 0, 0, 0 }
        textColor = hovered and p.text or p.textMuted
    else
        bg = hovered and p.btnHoverBg or p.btnBg
        border = hovered and p.accentBorder or p.btnBorder
        textColor = p.text
    end

    btn:SetBackdrop(BACKDROP_SPEC)
    btn:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    btn:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    if btn.label then
        btn.label:SetTextColor(textColor[1], textColor[2], textColor[3])
    end
end

--- Style an existing BackdropTemplate button with hover/disabled visuals.
function Theme:StyleButton(btn, variant)
    btn._scVariant = variant or "default"
    if not btn._scHooksInstalled then
        btn._scHooksInstalled = true
        btn:HookScript("OnEnter", function(self)
            ApplyButtonColors(self, true)
        end)
        btn:HookScript("OnLeave", function(self)
            ApplyButtonColors(self, false)
        end)
        btn:HookScript("OnEnable", function(self)
            ApplyButtonColors(self, false)
        end)
        btn:HookScript("OnDisable", function(self)
            ApplyButtonColors(self, false)
        end)
    end
    ApplyButtonColors(btn, false)
end

--- Create a themed button with centered label.
function Theme:CreateButton(parent, width, height, text, variant)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 80, height or 24)
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.label:SetPoint("CENTER", 0, 0)
    btn.label:SetText(text or "")
    self:StyleButton(btn, variant)
    return btn
end

--- Update button text while preserving padding/variant.
function Theme:SetButtonText(btn, text)
    if btn and btn.label then
        btn.label:SetText(text or "")
    end
end

--- Update active toggle state on a tab or filter button.
function Theme:SetButtonActive(btn, active, variant)
    if not btn then
        return
    end
    btn._scActive = active and true or false
    if variant then
        btn._scVariant = variant
    end
    ApplyButtonColors(btn, false)
end

--- Update a ColorTexture status indicator for a character state.
function Theme:ApplyStatusColor(tex, status)
    if not tex then
        return
    end
    local p = self:GetPalette()
    local c = p.unknown
    if status == "online" then
        c = p.online
    elseif status == "offline" then
        c = p.offline
    elseif status == "nearby" then
        c = p.nearby
    end
    tex:SetColorTexture(c[1], c[2], c[3], 1)
end

local helpPopup
local updatePopup

--- Display a modal help card explaining what an option does and how to use it.
function Theme:ShowHelpPopup(title, whatText, howText)
    if not helpPopup then
        local m = CreateFrame("Frame", "SocialCentralHelpPopup", UIParent, "BackdropTemplate")
        m:SetSize(430, 230)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(120)
        m:EnableMouse(true)
        m:SetMovable(true)
        m:SetClampedToScreen(true)
        m:RegisterForDrag("LeftButton")
        m:SetScript("OnDragStart", function(f) f:StartMoving() end)
        m:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)
        table.insert(UISpecialFrames, "SocialCentralHelpPopup")

        m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        m.title:SetPoint("TOPLEFT", 16, -14)
        m.title:SetPoint("TOPRIGHT", -16, -14)
        m.title:SetJustifyH("LEFT")

        m.body = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        m.body:SetPoint("TOPLEFT", 16, -44)
        m.body:SetPoint("BOTTOMRIGHT", -16, 48)
        m.body:SetJustifyH("LEFT")
        m.body:SetJustifyV("TOP")
        m.body:SetWordWrap(true)

        m.closeBtn = self:CreateButton(m, 96, 24, L["Close"], "primary")
        m.closeBtn:SetPoint("BOTTOMRIGHT", -16, 14)
        m.closeBtn:SetScript("OnClick", function() m:Hide() end)

        self:RegisterListener(function()
            if m:IsShown() then
                self:ApplyBackdrop(m, "window")
                self:StyleButton(m.closeBtn, "primary")
            end
        end)

        helpPopup = m
    end

    self:ApplyBackdrop(helpPopup, "window")
    self:StyleButton(helpPopup.closeBtn, "primary")
    helpPopup.title:SetText(title or L["Help"])
    helpPopup.body:SetText(
        "|cff58a6ff" .. L["What it does:"] .. "|r\n" .. (whatText or "") ..
        "\n\n|cff4ade80" .. L["How to use:"] .. "|r\n" .. (howText or "")
    )
    helpPopup:Show()
end

--- Create a standardized '?' help micro-button beside an option or feature bar.
function Theme:CreateHelpButton(parent, title, whatText, howText, size)
    local btn = self:CreateButton(parent, size or 18, size or 18, "?", "default")
    btn:HookScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(title or L["Help"], 0.35, 0.72, 1.0, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff58a6ff" .. L["What it does:"] .. "|r " .. (whatText or ""), 0.92, 0.94, 0.98, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff4ade80" .. L["How to use:"] .. "|r " .. (howText or ""), 0.85, 0.92, 0.88, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click ? to keep this help open."], 0.58, 0.65, 0.74, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function()
        GameTooltip:Hide()
        Theme:ShowHelpPopup(title, whatText, howText)
    end)
    self:RegisterListener(function()
        self:StyleButton(btn, "default")
    end)
    return btn
end

--- Display a copyable GitHub Releases URL & Windows updater popup (Blizzard HTTP-sandbox safe).
function Theme:ShowUpdatePopup(localVer, remoteVer, url)
    local releaseUrl = url or ns.RELEASE_URL or "https://github.com/raphaelredes/SocialCentral-Releases/releases/latest"
    local psCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File update-socialcentral.ps1"

    if not updatePopup then
        local m = CreateFrame("Frame", "SocialCentralUpdatePopup", UIParent, "BackdropTemplate")
        m:SetSize(470, 225)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(125)
        m:EnableMouse(true)
        m:SetMovable(true)
        m:SetClampedToScreen(true)
        m:RegisterForDrag("LeftButton")
        m:SetScript("OnDragStart", function(f) f:StartMoving() end)
        m:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)
        table.insert(UISpecialFrames, "SocialCentralUpdatePopup")

        m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        m.title:SetPoint("TOPLEFT", 16, -14)
        m.title:SetPoint("TOPRIGHT", -16, -14)
        m.title:SetJustifyH("LEFT")

        m.desc = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        m.desc:SetPoint("TOPLEFT", 16, -42)
        m.desc:SetPoint("TOPRIGHT", -16, -42)
        m.desc:SetJustifyH("LEFT")
        m.desc:SetWordWrap(true)

        m.input = CreateFrame("EditBox", nil, m, "InputBoxTemplate")
        m.input:SetPoint("TOPLEFT", 20, -112)
        m.input:SetPoint("TOPRIGHT", -20, -112)
        m.input:SetHeight(24)
        m.input:SetAutoFocus(false)
        m.input:SetScript("OnEscapePressed", function() m:Hide() end)

        m.hint = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        m.hint:SetPoint("TOPLEFT", 16, -146)
        m.hint:SetPoint("TOPRIGHT", -16, -146)
        m.hint:SetJustifyH("LEFT")
        m.hint:SetText(L["Press Ctrl+C to copy the link or Windows updater command."])

        m.btnUrl = self:CreateButton(m, 130, 24, L["GitHub Releases"], "default")
        m.btnUrl:SetPoint("BOTTOMLEFT", 16, 14)

        m.btnCmd = self:CreateButton(m, 150, 24, L["Updater Script"], "default")
        m.btnCmd:SetPoint("LEFT", m.btnUrl, "RIGHT", 8, 0)

        m.btnClose = self:CreateButton(m, 90, 24, L["Close"], "primary")
        m.btnClose:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnClose:SetScript("OnClick", function() m:Hide() end)

        self:RegisterListener(function()
            if m:IsShown() then
                self:ApplyBackdrop(m, "window")
                self:StyleButton(m.btnUrl, "default")
                self:StyleButton(m.btnCmd, "default")
                self:StyleButton(m.btnClose, "primary")
            end
        end)

        updatePopup = m
    end

    self:ApplyBackdrop(updatePopup, "window")
    self:StyleButton(updatePopup.btnUrl, "default")
    self:StyleButton(updatePopup.btnCmd, "default")
    self:StyleButton(updatePopup.btnClose, "primary")

    updatePopup.title:SetText(L["SocialCentral Update & GitHub"])
    local hasNewer = remoteVer and ns.Compat and ns.Compat.CompareSemVer(remoteVer, localVer or "0.0.0") > 0
    if hasNewer then
        updatePopup.desc:SetText(
            "|cff4ade80" .. L["Newer version detected in-game:"] .. " v" .. remoteVer .. "|r  (" .. L["Installed:"] .. " v" .. (localVer or ns.version or "0.2.0") .. ")\n\n" ..
            L["WoW addons cannot open websites or download files directly inside the game. Copy the public GitHub Releases URL or run the Windows updater script."]
        )
    else
        updatePopup.desc:SetText(
            L["Installed:"] .. " v" .. (localVer or ns.version or "0.2.0") .. "\n\n" ..
            L["Copy the public GitHub Releases URL below to check for newer releases or download updates with the Windows updater script."]
        )
    end

    local function SelectValue(val)
        updatePopup.input:SetText(val)
        updatePopup.input:SetFocus()
        updatePopup.input:HighlightText()
    end

    updatePopup.btnUrl:SetScript("OnClick", function() SelectValue(releaseUrl) end)
    updatePopup.btnCmd:SetScript("OnClick", function() SelectValue(psCmd) end)
    updatePopup:Show()
    SelectValue(releaseUrl)
end

--- Create a reusable clipped virtual scroll list with mouse wheel and slim thumb.
function Theme:CreateScrollList(parent, rowHeight, createRowFn, updateRowFn)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    self:ApplyBackdrop(container, "inset")

    local viewport = CreateFrame("Frame", nil, container)
    viewport:SetPoint("TOPLEFT", 2, -2)
    viewport:SetPoint("BOTTOMRIGHT", -14, 2)
    viewport:SetClipsChildren(true)
    viewport:EnableMouseWheel(true)

    local track = CreateFrame("Frame", nil, container, "BackdropTemplate")
    track:SetWidth(8)
    track:SetPoint("TOPRIGHT", -3, -4)
    track:SetPoint("BOTTOMRIGHT", -3, 4)

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(8)
    thumb:SetHeight(32)
    thumb:SetPoint("TOP", 0, 0)
    thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
    thumb.tex:SetAllPoints()

    local list = {
        container = container,
        viewport = viewport,
        track = track,
        thumb = thumb,
        rowHeight = rowHeight or 30,
        rows = {},
        items = {},
        offset = 0,
        emptyText = nil,
    }

    local emptyLabel = viewport:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyLabel:SetPoint("CENTER", 0, 10)
    emptyLabel:SetWidth(360)
    emptyLabel:SetJustifyH("CENTER")
    emptyLabel:Hide()
    list.emptyLabel = emptyLabel

    local function UpdateTrackColors(hovered)
        local p = Theme:GetPalette()
        if track.SetBackdrop then
            track:SetBackdrop(FLAT_BACKDROP_SPEC)
            track:SetBackdropColor(p.scrollTrack[1], p.scrollTrack[2], p.scrollTrack[3], p.scrollTrack[4])
        end
        local c = hovered and p.scrollThumbHover or p.scrollThumb
        thumb.tex:SetColorTexture(c[1], c[2], c[3], c[4])
        emptyLabel:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
    end

    thumb:SetScript("OnEnter", function() UpdateTrackColors(true) end)
    thumb:SetScript("OnLeave", function() UpdateTrackColors(false) end)

    local function GetMaxOffset()
        local vpH = viewport:GetHeight() or 0
        if vpH <= 0 then
            return 0
        end
        local totalH = #list.items * list.rowHeight
        return math.max(0, totalH - vpH)
    end

    local function EnsureRowPool()
        local vpH = viewport:GetHeight() or 280
        local needed = math.max(1, math.ceil(vpH / list.rowHeight) + 1)
        while #list.rows < needed do
            local idx = #list.rows + 1
            local row = createRowFn(viewport, idx, list.rowHeight)
            row:SetHeight(list.rowHeight)
            row._scIndex = idx
            list.rows[idx] = row
        end
    end

    function list:RefreshTheme()
        Theme:ApplyBackdrop(container, "inset")
        UpdateTrackColors(false)
        for _, row in ipairs(self.rows) do
            if row.RefreshTheme then
                row:RefreshTheme()
            end
        end
    end

    function list:Render()
        EnsureRowPool()
        local p = Theme:GetPalette()
        local vpH = viewport:GetHeight() or 0
        local maxOffset = GetMaxOffset()
        if self.offset > maxOffset then
            self.offset = maxOffset
        end
        if self.offset < 0 then
            self.offset = 0
        end

        local total = #self.items
        if total == 0 then
            emptyLabel:SetText(self.emptyText or "")
            emptyLabel:SetShown(self.emptyText ~= nil and self.emptyText ~= "")
        else
            emptyLabel:Hide()
        end

        local firstIndex = math.floor(self.offset / self.rowHeight) + 1
        local subOffset = self.offset % self.rowHeight

        for poolIdx, row in ipairs(self.rows) do
            local dataIdx = firstIndex + poolIdx - 1
            local item = self.items[dataIdx]
            if item then
                local y = -((poolIdx - 1) * self.rowHeight) + subOffset
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, y)
                row:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, y)
                Theme:ApplyBackdrop(row, (dataIdx % 2 == 1) and "row" or "rowAlt", p)
                updateRowFn(row, item, dataIdx, p)
                row:Show()
            else
                row:Hide()
            end
        end

        local trackH = track:GetHeight() or 0
        if maxOffset <= 0 or trackH <= 0 or total == 0 then
            thumb:Hide()
        else
            thumb:Show()
            local totalH = total * self.rowHeight
            local ratio = math.min(1, vpH / totalH)
            local thumbH = math.max(24, math.floor(trackH * ratio))
            thumb:SetHeight(thumbH)
            local travel = math.max(1, trackH - thumbH)
            local pos = (self.offset / maxOffset) * travel
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -pos)
        end
    end

    function list:SetData(items, emptyText, resetScroll)
        self.items = items or {}
        self.emptyText = emptyText
        if resetScroll then
            self.offset = 0
        end
        self:Render()
    end

    viewport:SetScript("OnMouseWheel", function(_, delta)
        local step = list.rowHeight * 2
        list.offset = math.max(0, math.min(GetMaxOffset(), list.offset - delta * step))
        list:Render()
    end)

    viewport:SetScript("OnSizeChanged", function()
        list:Render()
    end)

    local dragging = false
    local dragStartY = 0
    local dragStartOffset = 0
    thumb:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        dragging = true
        local _, cursorY = GetCursorPosition()
        local scale = thumb:GetEffectiveScale() or 1
        dragStartY = cursorY / scale
        dragStartOffset = list.offset
    end)
    thumb:SetScript("OnMouseUp", function()
        dragging = false
    end)
    thumb:SetScript("OnUpdate", function()
        if not dragging then
            return
        end
        if not IsMouseButtonDown("LeftButton") then
            dragging = false
            return
        end
        local maxOffset = GetMaxOffset()
        local trackH = track:GetHeight() or 0
        local thumbH = thumb:GetHeight() or 24
        local travel = math.max(1, trackH - thumbH)
        local _, cursorY = GetCursorPosition()
        local scale = thumb:GetEffectiveScale() or 1
        local dy = dragStartY - (cursorY / scale)
        list.offset = math.max(0, math.min(maxOffset, dragStartOffset + (dy / travel) * maxOffset))
        list:Render()
    end)

    UpdateTrackColors(false)
    return list
end
