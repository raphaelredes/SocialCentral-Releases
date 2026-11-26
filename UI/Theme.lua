local _, ns = ...

local L = ns.L
local Theme = {}
ns.Theme = Theme

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local listeners = {}
local decoratedHeaders = setmetatable({}, { __mode = "k" })

function Theme:HasAtlas(atlasName)
    return C_Texture and C_Texture.GetAtlasInfo and atlasName and C_Texture.GetAtlasInfo(atlasName) ~= nil
end

local function HasAtlas(atlasName)
    return Theme:HasAtlas(atlasName)
end

Theme.PALETTES = {
    dark = {
        key = "dark",
        windowBg = { 0.06, 0.07, 0.09, 1.0 },
        windowBorder = { 0.20, 0.24, 0.30, 1.0 },
        headerBg = { 0.09, 0.11, 0.14, 1.0 },
        surfaceBg = { 0.09, 0.11, 0.15, 1.0 },
        surfaceBorder = { 0.18, 0.22, 0.28, 1.0 },
        insetBg = { 0.05, 0.06, 0.08, 1.0 },
        rowBg = { 0.10, 0.12, 0.16, 0.65 },
        rowAltBg = { 0.08, 0.09, 0.12, 0.65 },
        rowHoverBg = { 0.16, 0.21, 0.28, 0.90 },
        rowSelectedBg = { 0.14, 0.27, 0.42, 0.90 },
        accent = { 0.22, 0.65, 0.95, 1.0 },
        accentDim = { 0.13, 0.36, 0.56, 1.0 },
        accentBorder = { 0.30, 0.72, 1.0, 1.0 },
        btnBg = { 0.14, 0.17, 0.22, 1.0 },
        btnHoverBg = { 0.20, 0.25, 0.33, 1.0 },
        btnBorder = { 0.28, 0.33, 0.41, 1.0 },
        dangerBg = { 0.42, 0.14, 0.14, 1.0 },
        dangerHoverBg = { 0.58, 0.18, 0.18, 1.0 },
        dangerBorder = { 0.75, 0.25, 0.25, 1.0 },
        text = { 0.93, 0.95, 0.98 },
        textGold = { 0.96, 0.80, 0.34 },
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
        windowBg = { 0.11, 0.10, 0.09, 1.0 },
        windowBorder = { 0.56, 0.48, 0.31, 1.0 },
        headerBg = { 0.16, 0.14, 0.11, 1.0 },
        surfaceBg = { 0.14, 0.13, 0.11, 1.0 },
        surfaceBorder = { 0.45, 0.39, 0.26, 1.0 },
        insetBg = { 0.08, 0.07, 0.06, 1.0 },
        rowBg = { 0.15, 0.14, 0.11, 0.68 },
        rowAltBg = { 0.12, 0.11, 0.09, 0.68 },
        rowHoverBg = { 0.25, 0.22, 0.16, 0.92 },
        rowSelectedBg = { 0.33, 0.26, 0.13, 0.92 },
        accent = { 0.86, 0.68, 0.22, 1.0 },
        accentDim = { 0.44, 0.33, 0.11, 1.0 },
        accentBorder = { 0.92, 0.76, 0.31, 1.0 },
        btnBg = { 0.22, 0.18, 0.13, 1.0 },
        btnHoverBg = { 0.32, 0.26, 0.18, 1.0 },
        btnBorder = { 0.58, 0.49, 0.31, 1.0 },
        dangerBg = { 0.44, 0.15, 0.13, 1.0 },
        dangerHoverBg = { 0.60, 0.20, 0.17, 1.0 },
        dangerBorder = { 0.78, 0.30, 0.26, 1.0 },
        text = { 0.98, 0.94, 0.84 },
        textGold = { 1.0, 0.84, 0.24 },
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
    blizzard = {
        key = "blizzard",
        windowBg = { 0.09, 0.085, 0.075, 1.0 },
        windowBorder = { 0.56, 0.48, 0.30, 1.0 },
        headerBg = { 0.07, 0.065, 0.055, 1.0 },
        surfaceBg = { 0.07, 0.065, 0.06, 1.0 },
        surfaceBorder = { 0.44, 0.39, 0.30, 1.0 },
        insetBg = { 0.04, 0.038, 0.036, 1.0 },
        rowBg = { 0.09, 0.085, 0.08, 0.16 },
        rowAltBg = { 0.02, 0.02, 0.02, 0.30 },
        rowHoverBg = { 0.30, 0.23, 0.08, 0.40 },
        rowSelectedBg = { 0.38, 0.20, 0.06, 0.55 },
        accent = { 0.72, 0.16, 0.13, 1.0 },
        accentDim = { 0.48, 0.10, 0.08, 1.0 },
        accentBorder = { 0.94, 0.78, 0.24, 1.0 },
        btnBg = { 0.22, 0.22, 0.24, 1.0 },
        btnHoverBg = { 0.32, 0.32, 0.36, 1.0 },
        btnBorder = { 0.55, 0.50, 0.40, 1.0 },
        dangerBg = { 0.46, 0.11, 0.10, 1.0 },
        dangerHoverBg = { 0.64, 0.15, 0.14, 1.0 },
        dangerBorder = { 0.88, 0.34, 0.26, 1.0 },
        text = { 1.0, 0.95, 0.84 },
        textGold = { 1.0, 0.82, 0.0 },
        textMuted = { 0.78, 0.74, 0.66 },
        textDim = { 0.52, 0.49, 0.44 },
        online = { 0.20, 0.88, 0.38 },
        offline = { 0.54, 0.54, 0.58 },
        unknown = { 0.98, 0.78, 0.24 },
        nearby = { 0.35, 0.80, 1.0 },
        scrollTrack = { 0.03, 0.03, 0.03, 0.68 },
        scrollThumb = { 0.56, 0.45, 0.24, 0.88 },
        scrollThumbHover = { 0.90, 0.72, 0.28, 1.0 },
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

local BLIZZ_DIALOG_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileEdge = true,
    tileSize = 32,
    edgeSize = 20,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

local BLIZZ_SURFACE_BACKDROP = {
    bgFile = "Interface\\FrameGeneral\\UI-Background-Marble",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileEdge = true,
    tileSize = 256,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local BLIZZ_INSET_BACKDROP = {
    bgFile = "Interface\\FrameGeneral\\UI-Background-Marble",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileEdge = true,
    tileSize = 256,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

--- Return the active skin identifier ("blizzard" | "dark" | "native").
function Theme:GetThemeName()
    local key = ns.db and ns.db.settings and ns.db.settings.theme or "blizzard"
    if self.PALETTES[key] then
        return key
    end
    return "blizzard"
end

--- Return the currently selected palette table.
function Theme:GetPalette()
    local key = ns.db and ns.db.settings and ns.db.settings.theme or "blizzard"
    return self.PALETTES[key] or self.PALETTES.blizzard
end

--- Return true when the official Blizzard game UI style is active.
function Theme:IsBlizzard(palette)
    local p = palette or self:GetPalette()
    return p and p.key == "blizzard"
end

--- Register a callback invoked when the active skin changes.
function Theme:RegisterListener(fn)
    if type(fn) == "function" then
        listeners[#listeners + 1] = fn
    end
end

--- Notify registered UI views to re-apply the current palette.
function Theme:NotifyChanged()
    local pal = self:GetPalette()
    for sep in pairs(decoratedHeaders) do
        if sep and sep._refreshRuleFn then
            pcall(sep._refreshRuleFn, sep, pal)
        end
    end
    for _, fn in ipairs(listeners) do
        pcall(fn, pal)
    end
end

local function ApplyBackdropSpec(frame, spec, bg, border, forceOpaque)
    if frame._scAppliedBackdrop ~= spec then
        frame:SetBackdrop(spec)
        frame._scAppliedBackdrop = spec
    end
    if bg then
        local a = forceOpaque and 1.0 or (bg[4] or 1.0)
        frame:SetBackdropColor(bg[1], bg[2], bg[3], a)
    end
    if border then
        local ba = forceOpaque and 1.0 or (border[4] or 1.0)
        frame:SetBackdropBorderColor(border[1], border[2], border[3], ba)
    end
end

local gradColorA, gradColorB

local function ApplySafeGradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    if not tex then return end
    if tex.SetGradient and CreateColor then
        if not gradColorA then gradColorA = CreateColor(0, 0, 0, 1) end
        if not gradColorB then gradColorB = CreateColor(0, 0, 0, 1) end
        gradColorA:SetRGBA(r1, g1, b1, a1)
        gradColorB:SetRGBA(r2, g2, b2, a2)
        tex:SetTexture(WHITE8X8)
        tex:SetVertexColor(1, 1, 1, 1)
        pcall(tex.SetGradient, tex, orient, gradColorA, gradColorB)
    else
        tex:SetColorTexture((r1 + r2) * 0.5, (g1 + g2) * 0.5, (b1 + b2) * 0.5, (a1 + a2) * 0.5)
    end
end

local function SyncDepthPolish(frame, kind, p, isBlizz)
    if not frame then return end
    local fw = frame.GetWidth and frame:GetWidth() or 0
    local fh = frame.GetHeight and frame:GetHeight() or 0
    local depthSig = tostring(kind or "") .. ":" .. tostring(p and p.key or "dark") .. ":" .. tostring(math.floor((fw or 0) + 0.5)) .. "x" .. tostring(math.floor((fh or 0) + 0.5)) .. ":" .. (frame._scNoStone and "1" or "0")
    if frame._scDepthSig == depthSig then
        return
    end
    frame._scDepthSig = depthSig

    local isLargeFrame = (not frame._scIsListRow) and (fw == 0 or fw >= 60)
    local isWideFrame = (not frame._scIsListRow) and (fw == 0 or fw >= 100)
    local wantGrad = isLargeFrame and (kind == "header" or kind == "surface" or kind == "inset" or (kind == "window" and not isBlizz))
    local wantSheen = isWideFrame and (kind == "header" or kind == "surface" or kind == "window")
    local wantBevel = isWideFrame and (kind == "header" or kind == "surface")
    local wantBotBevel = isWideFrame and (kind == "header" or kind == "surface")
    local wantInsetStone = (kind == "inset" and isBlizz and not frame._scNoStone and fw >= 120 and fh >= 80 and HasAtlas("groupfinder-background"))

    if wantGrad then
        if not frame._scGradBg then
            local gbg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
            gbg:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
            gbg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
            frame._scGradBg = gbg
        end
        if kind == "header" then
            if isBlizz then
                ApplySafeGradient(frame._scGradBg, "VERTICAL", 0.055, 0.048, 0.040, 0.85, 0.145, 0.120, 0.085, 0.92)
            elseif p.key == "native" then
                ApplySafeGradient(frame._scGradBg, "VERTICAL", 0.10, 0.09, 0.07, 0.92, 0.21, 0.18, 0.13, 0.95)
            else
                ApplySafeGradient(frame._scGradBg, "VERTICAL", 0.07, 0.09, 0.12, 0.92, 0.13, 0.17, 0.23, 0.96)
            end
        elseif kind == "surface" then
            if isBlizz then
                ApplySafeGradient(frame._scGradBg, "VERTICAL", 0.055, 0.050, 0.045, 0.90, 0.098, 0.088, 0.076, 0.94)
            elseif p.key == "native" then
                ApplySafeGradient(frame._scGradBg, "VERTICAL", 0.11, 0.10, 0.08, 0.90, 0.17, 0.15, 0.12, 0.95)
            else
                ApplySafeGradient(frame._scGradBg, "VERTICAL", 0.075, 0.09, 0.125, 0.92, 0.115, 0.14, 0.19, 0.96)
            end
        elseif kind == "inset" then
            if isBlizz then
                ApplySafeGradient(frame._scGradBg, "VERTICAL", 0.048, 0.044, 0.040, 0.65, 0.024, 0.022, 0.020, 0.82)
            elseif p.key == "native" then
                ApplySafeGradient(frame._scGradBg, "VERTICAL", 0.085, 0.075, 0.062, 0.86, 0.050, 0.044, 0.036, 0.92)
            else
                ApplySafeGradient(frame._scGradBg, "VERTICAL", 0.058, 0.070, 0.092, 0.88, 0.034, 0.040, 0.056, 0.94)
            end
        else -- non-blizzard window atmospheric shading
            if p.key == "native" then
                ApplySafeGradient(frame._scGradBg, "VERTICAL", 0.085, 0.078, 0.065, 0.96, 0.145, 0.128, 0.102, 0.96)
            else
                ApplySafeGradient(frame._scGradBg, "VERTICAL", 0.052, 0.062, 0.082, 0.96, 0.088, 0.108, 0.142, 0.96)
            end
        end
        frame._scGradBg:Show()
    elseif frame._scGradBg then
        frame._scGradBg:Hide()
    end

    if wantSheen then
        if not frame._scCardSheen then
            local sheen = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
            sheen:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
            sheen:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
            frame._scCardSheen = sheen
        end
        local acc = p.accent or { 0.3, 0.7, 1.0 }
        if kind == "header" then
            frame._scCardSheen:SetHeight(math.max(20, (frame:GetHeight() or 36) - 4))
            if isBlizz then
                ApplySafeGradient(frame._scCardSheen, "VERTICAL", 0, 0, 0, 0, 0.56, 0.42, 0.16, 0.22)
            else
                ApplySafeGradient(frame._scCardSheen, "VERTICAL", 0, 0, 0, 0, acc[1] * 0.26 + 0.06, acc[2] * 0.26 + 0.06, acc[3] * 0.26 + 0.08, 0.32)
            end
        elseif kind == "surface" then
            frame._scCardSheen:SetHeight(48)
            ApplySafeGradient(frame._scCardSheen, "VERTICAL", 0, 0, 0, 0, 1, 1, 1, isBlizz and 0.04 or 0.055)
        else
            frame._scCardSheen:SetHeight(58)
            ApplySafeGradient(frame._scCardSheen, "VERTICAL", 0, 0, 0, 0, acc[1] * 0.3 + 0.05, acc[2] * 0.3 + 0.05, acc[3] * 0.3 + 0.08, isBlizz and 0.04 or 0.16)
        end
        frame._scCardSheen:Show()
    elseif frame._scCardSheen then
        frame._scCardSheen:Hide()
    end

    if wantBevel then
        if not frame._scTopBevel then
            local bev = frame:CreateTexture(nil, "BORDER", nil, 2)
            bev:SetHeight(1)
            bev:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -1)
            bev:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -1)
            frame._scTopBevel = bev
        end
        if isBlizz or p.key == "native" then
            frame._scTopBevel:SetColorTexture(0.95, 0.80, 0.38, 0.28)
        else
            frame._scTopBevel:SetColorTexture(0.65, 0.85, 1.0, 0.20)
        end
        frame._scTopBevel:Show()
    elseif frame._scTopBevel then
        frame._scTopBevel:Hide()
    end

    if wantBotBevel then
        if not frame._scBotBevel then
            local bBev = frame:CreateTexture(nil, "BORDER", nil, 2)
            bBev:SetHeight(1)
            bBev:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 1)
            bBev:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 1)
            frame._scBotBevel = bBev
        end
        frame._scBotBevel:SetColorTexture(0, 0, 0, isBlizz and 0.48 or 0.38)
        frame._scBotBevel:Show()
    elseif frame._scBotBevel then
        frame._scBotBevel:Hide()
    end

    if wantInsetStone then
        if not frame._scInsetStone then
            local st = frame:CreateTexture(nil, "BACKGROUND", nil, -4)
            st:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
            st:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
            st:SetAtlas("groupfinder-background", false)
            frame._scInsetStone = st
        end
        frame._scInsetStone:SetVertexColor(0.36, 0.34, 0.32, 0.40)
        frame._scInsetStone:Show()
    elseif frame._scInsetStone then
        frame._scInsetStone:Hide()
    end
end

local function ApplyDecoratedHeaderColors(sep, p)
    if not sep then return end
    local pal = p or Theme:GetPalette()
    local isWarm = (pal and (pal.key == "blizzard" or pal.key == "native"))
    local r, g, b = 0.90, 0.74, 0.28
    if not isWarm and pal and pal.accentBorder then
        r, g, b = pal.accentBorder[1], pal.accentBorder[2], pal.accentBorder[3]
    end
    if sep._accentPip then
        sep._accentPip:SetColorTexture(r, g, b, 0.95)
    end
    if sep._leftTex then
        ApplySafeGradient(sep._leftTex, "HORIZONTAL", r, g, b, 0.80, r, g, b, 0.24)
    end
    if sep._rightTex then
        ApplySafeGradient(sep._rightTex, "HORIZONTAL", r, g, b, 0.24, r, g, b, 0.0)
    end
end

--- Add a clean tapered gold/accent horizontal rule directly below a section heading (auto-updates on theme switch).
function Theme:DecorateSectionHeader(parent, labelFs, lineWidth)
    if not (parent and labelFs) then return nil end
    local halfW = math.floor((lineWidth or 280) * 0.5)
    local sep = CreateFrame("Frame", nil, parent)
    sep:SetHeight(3)
    sep:SetPoint("TOPLEFT", labelFs, "BOTTOMLEFT", 0, -4)
    sep:SetWidth(halfW * 2)

    local pip = sep:CreateTexture(nil, "ARTWORK", nil, 1)
    pip:SetSize(14, 2)
    pip:SetPoint("LEFT", sep, "LEFT", 0, 0)
    sep._accentPip = pip

    local leftTex = sep:CreateTexture(nil, "ARTWORK")
    leftTex:SetPoint("LEFT", pip, "RIGHT", 2, 0)
    leftTex:SetSize(math.max(12, halfW - 16), 1)
    sep._leftTex = leftTex

    local rightTex = sep:CreateTexture(nil, "ARTWORK")
    rightTex:SetPoint("LEFT", leftTex, "RIGHT", 0, 0)
    rightTex:SetSize(halfW, 1)
    sep._rightTex = rightTex

    sep._refreshRuleFn = ApplyDecoratedHeaderColors
    decoratedHeaders[sep] = true
    ApplyDecoratedHeaderColors(sep, self:GetPalette())

    return sep
end

--- Apply a flat, bordered, or Blizzard-official backdrop to a frame created with BackdropTemplate.
function Theme:ApplyBackdrop(frame, kind, palette)
    if not frame or not frame.SetBackdrop then
        return
    end
    local p = palette or self:GetPalette()
    local resolvedKind = kind or "surface"
    local sig = resolvedKind .. ":" .. tostring(p and p.key or "dark")
    if frame._scBackdropSig == sig then
        return
    end
    frame._scBackdropSig = sig
    if resolvedKind == "none" then
        if frame._scAppliedBackdrop ~= nil then
            frame:SetBackdrop(nil)
            frame._scAppliedBackdrop = nil
        end
        if frame._solidOpaqueBg then
            frame._solidOpaqueBg:Hide()
        end
        if frame._foreverRowBg then
            frame._foreverRowBg:Hide()
        end
        if frame._foreverSurfaceStone then
            frame._foreverSurfaceStone:Hide()
        end
        SyncDepthPolish(frame, "none", p, false)
        return
    end

    -- Mandatory 100% Opacity enforcement for any window, modal, or popup dialog:
    -- Ensure an explicit solid opaque quad is present on the frame's BACKGROUND layer (-8)
    -- with alpha 1.0 so background elements (text, buttons, 3D world) NEVER bleed through.
    if resolvedKind == "window" then
        if not frame._solidOpaqueBg then
            frame._solidOpaqueBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
            frame._solidOpaqueBg:SetAllPoints(frame)
        end
        frame._solidOpaqueBg:SetTexture(WHITE8X8)
        local wBg = p.windowBg or { 0.08, 0.08, 0.08, 1.0 }
        frame._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
        frame._solidOpaqueBg:Show()
    end

    if self:IsBlizzard(p) then
        local hasStoneAtlas = HasAtlas("groupfinder-Stat-StoneBG")

        if resolvedKind == "row" or resolvedKind == "rowAlt" then
            if frame._foreverSurfaceStone then
                frame._foreverSurfaceStone:Hide()
            end
            if frame._foreverRowBg then
                frame._foreverRowBg:Hide()
            end
            SyncDepthPolish(frame, "none", p, true)
            local bgRow = (resolvedKind == "row") and { 0.085, 0.078, 0.070 } or { 0.055, 0.050, 0.045 }
            ApplyBackdropSpec(frame, FLAT_BACKDROP_SPEC, bgRow, nil, false)
            frame:SetBackdropColor(bgRow[1], bgRow[2], bgRow[3], (resolvedKind == "row") and 0.42 or 0.25)
            if frame.GetObjectType and frame:GetObjectType() == "Button" and not frame._foreverRowHl then
                local hl = frame:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(frame)
                hl:SetColorTexture(0.95, 0.78, 0.28, 0.10)
                frame._foreverRowHl = hl
            end
            return
        end

        if resolvedKind == "surface" and frame._scIsListRow then
            ApplyBackdropSpec(frame, FLAT_BACKDROP_SPEC, { 0.22, 0.17, 0.08 }, nil, false)
            frame:SetBackdropColor(0.22, 0.17, 0.08, 0.55)
            if frame._foreverRowBg then frame._foreverRowBg:Hide() end
            SyncDepthPolish(frame, "none", p, true)
            return
        end

        if frame._foreverRowBg then
            frame._foreverRowBg:Hide()
        end

        if resolvedKind == "window" then
            if frame._foreverSurfaceStone then
                frame._foreverSurfaceStone:Hide()
            end
            ApplyBackdropSpec(frame, BLIZZ_DIALOG_BACKDROP, { 0.08, 0.075, 0.07 }, { 0.86, 0.80, 0.68 }, true)
            SyncDepthPolish(frame, "none", p, true)
            return
        elseif resolvedKind == "header" then
            ApplyBackdropSpec(frame, hasStoneAtlas and BACKDROP_SPEC or BLIZZ_SURFACE_BACKDROP, { 0.085, 0.08, 0.07 }, { 0.46, 0.38, 0.22 }, true)
            if hasStoneAtlas then
                if not frame._foreverSurfaceStone then
                    frame._foreverSurfaceStone = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
                    frame._foreverSurfaceStone:SetAllPoints(frame)
                    frame._foreverSurfaceStone:SetAtlas("groupfinder-Stat-StoneBG", false)
                end
                frame._foreverSurfaceStone:SetAlpha(0.95)
                frame._foreverSurfaceStone:Show()
            elseif frame._foreverSurfaceStone then
                frame._foreverSurfaceStone:Hide()
            end
            SyncDepthPolish(frame, "header", p, true)
            return
        elseif resolvedKind == "inset" then
            if frame._foreverSurfaceStone then
                frame._foreverSurfaceStone:Hide()
            end
            ApplyBackdropSpec(frame, BACKDROP_SPEC, { 0.048, 0.045, 0.042 }, { 0.36, 0.30, 0.19 }, true)
            SyncDepthPolish(frame, "inset", p, true)
            return
        elseif resolvedKind == "surface" then
            if frame._foreverSurfaceStone then
                frame._foreverSurfaceStone:Hide()
            end
            ApplyBackdropSpec(frame, BACKDROP_SPEC, { 0.075, 0.068, 0.060 }, { 0.44, 0.36, 0.22 }, true)
            SyncDepthPolish(frame, "surface", p, true)
            return
        end
    else
        if frame._foreverRowBg then
            frame._foreverRowBg:Hide()
        end
        if frame._foreverSurfaceStone then
            frame._foreverSurfaceStone:Hide()
        end
    end

    local bg, border

    if resolvedKind == "window" then
        bg, border = p.windowBg, p.windowBorder
    elseif resolvedKind == "header" then
        bg, border = p.headerBg, p.surfaceBorder
    elseif resolvedKind == "surface" then
        bg, border = p.surfaceBg, p.surfaceBorder
    elseif resolvedKind == "inset" then
        bg, border = p.insetBg, p.surfaceBorder
    elseif resolvedKind == "button" then
        bg, border = p.btnBg, p.btnBorder
    elseif resolvedKind == "primary" then
        bg, border = p.accentDim, p.accentBorder
    elseif resolvedKind == "danger" then
        bg, border = p.dangerBg, p.dangerBorder
    elseif resolvedKind == "row" then
        bg, border = p.rowBg, nil
    elseif resolvedKind == "rowAlt" then
        bg, border = p.rowAltBg, nil
    elseif resolvedKind == "activeTab" then
        bg, border = p.accentDim, p.accentBorder
    elseif resolvedKind == "tab" then
        bg, border = p.surfaceBg, p.surfaceBorder
    else
        bg, border = p.surfaceBg, p.surfaceBorder
    end

    ApplyBackdropSpec(frame, border and BACKDROP_SPEC or FLAT_BACKDROP_SPEC, bg, border, true)
    SyncDepthPolish(frame, resolvedKind, p, false)
end

local function SyncBlizzTextOffset(btn, xOff, yOff)
    if not btn or not btn.label then
        return
    end
    local w = btn._scAutoFitW or (btn:GetWidth() or 0)
    local isCenterBtn = (btn._scCenterLabel == true) or (w > 0 and w <= 28)
    if btn.SetClipsChildren and not btn._scClipsInit then
        btn._scClipsInit = true
        btn:SetClipsChildren(not isCenterBtn)
    end
    local variant = btn._scVariant or "default"
    local padX
    if w < 26 then
        padX = 1
    elseif variant == "tab" then
        padX = (w < 60) and 4 or 6
    elseif Theme:IsBlizzard() then
        padX = (w < 54) and 5 or 7
    else
        padX = (w < 50) and 4 or 5
    end
    local parent = btn._textLayer or btn
    if parent.SetClipsChildren and not parent._scClipsInit then
        parent._scClipsInit = true
        parent:SetClipsChildren(not isCenterBtn)
    end
    local sig = (isCenterBtn and "C:" or "L:") .. padX .. ":" .. (xOff or 0) .. ":" .. (yOff or 0)
    if btn._scTextOffsetSig == sig and btn._scTextOffsetParent == parent then
        return
    end
    btn._scTextOffsetSig = sig
    btn._scTextOffsetParent = parent
    btn.label:ClearAllPoints()
    if isCenterBtn then
        btn.label:SetPoint("CENTER", parent, "CENTER", xOff or 0, yOff or 0)
    else
        btn.label:SetPoint("LEFT", parent, "LEFT", padX + (xOff or 0), yOff or 0)
        btn.label:SetPoint("RIGHT", parent, "RIGHT", -padX + (xOff or 0), yOff or 0)
    end
    if not btn._scLabelFmtInit then
        btn._scLabelFmtInit = true
        btn.label:SetJustifyH("CENTER")
        if btn.label.SetJustifyV then
            btn.label:SetJustifyV("MIDDLE")
        end
        btn.label:SetWordWrap(false)
        if btn.label.SetMaxLines then
            btn.label:SetMaxLines(1)
        end
    end
end

local sharedMeasureProbe

local function MeasureLabelWidth(btn)
    if not btn or not btn.label then
        return 0
    end
    local prevText = btn.label:GetText() or ""
    local fontObj = (btn.label.GetFontObject and btn.label:GetFontObject()) or GameFontHighlightSmall
    if btn._scMeasuredText == prevText and btn._scMeasuredFont == fontObj and btn._scMeasuredW then
        return btn._scMeasuredW
    end
    local directW = 0
    if btn.label.GetUnboundedStringWidth then
        directW = math.ceil(btn.label:GetUnboundedStringWidth() or 0)
    end
    if not sharedMeasureProbe and UIParent and UIParent.CreateFontString then
        sharedMeasureProbe = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sharedMeasureProbe:Hide()
    end
    local probeW = 0
    if sharedMeasureProbe then
        sharedMeasureProbe:SetFontObject(fontObj)
        sharedMeasureProbe:SetText(prevText)
        probeW = math.ceil(sharedMeasureProbe:GetStringWidth() or 0)
    end
    local measured = math.max(directW, probeW)
    btn._scMeasuredText = prevText
    btn._scMeasuredFont = fontObj
    btn._scMeasuredW = measured
    return measured
end

function Theme:MeasureTextWidth(btn)
    return MeasureLabelWidth(btn)
end

local function EnsureBlizzButtonVisual(btn, isTab)
    if not isTab then
        if btn._blizzTabFrame then
            btn._blizzTabFrame:Hide()
        end
        return nil, nil
    end

    if not btn._blizzTabFrame then
        local tab = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        tab:SetAllPoints(btn)
        tab:EnableMouse(false)
        if tab.SetClipsChildren then
            tab:SetClipsChildren(true)
        end
        tab._topAccent = tab:CreateTexture(nil, "OVERLAY")
        tab._topAccent:SetPoint("TOPLEFT", tab, "TOPLEFT", 2, -1)
        tab._topAccent:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -2, -1)
        tab._topAccent:SetHeight(2)

        tab._bottomBridge = tab:CreateTexture(nil, "OVERLAY")
        tab._bottomBridge:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 1, 0)
        tab._bottomBridge:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -1, 0)
        tab._bottomBridge:SetHeight(2)

        tab._scIsInternalBtnLayer = true
        btn._blizzTabFrame = tab
    end
    return btn._blizzTabFrame, "tab"
end

--- Keep internal button plate and text layers cleanly ordered above parent card backgrounds.
function Theme:SyncButtonLayers(btn)
    if not btn or not btn.GetFrameLevel then
        return
    end
    local bLvl = math.max(1, math.min(9990, btn:GetFrameLevel() or 1))
    if btn._blizzTabFrame and btn._blizzTabFrame.SetFrameLevel then
        btn._blizzTabFrame:SetFrameLevel(bLvl + 1)
    end
    if btn._textLayer and btn._textLayer.SetFrameLevel then
        btn._textLayer:SetFrameLevel(bLvl + 4)
    end
end

local function SyncThemeSubtreeChildren(visitFn, baseLvl, depth, ...)
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
            visitFn(Theme, child, depth)
        end
    end
end

--- Recursively synchronize frame levels across cards, inputs, scroll lists, and button text layers.
function Theme:SyncSubtreeLayers(root, depth)
    depth = depth or 10
    if not root or depth <= 0
        or (root.IsForbidden and root:IsForbidden())
        or root._scSkipLayerSync
        or root._scIsInternalBtnLayer
        or root._scIsInputBackdrop
    then
        return
    end
    local baseLvl = math.max(1, math.min(9980, (root.GetFrameLevel and root:GetFrameLevel()) or 1))
    if root._textLayer or root._blizzTabFrame then
        self:SyncButtonLayers(root)
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
        SyncThemeSubtreeChildren(self.SyncSubtreeLayers, baseLvl, depth - 1, root:GetChildren())
    end
end

local function EnsureToggleSquareRing(btn)
    if btn._scToggleRing then
        return btn._scToggleRing
    end
    local layer = btn._textLayer or btn
    local ring = {
        top = layer:CreateTexture(nil, "OVERLAY", nil, 5),
        bottom = layer:CreateTexture(nil, "OVERLAY", nil, 5),
        left = layer:CreateTexture(nil, "OVERLAY", nil, 5),
        right = layer:CreateTexture(nil, "OVERLAY", nil, 5),
    }
    ring.top:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    ring.top:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    ring.top:SetHeight(2)
    ring.bottom:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    ring.bottom:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    ring.bottom:SetHeight(2)
    ring.left:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -2)
    ring.left:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 2)
    ring.left:SetWidth(2)
    ring.right:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, -2)
    ring.right:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 2)
    ring.right:SetWidth(2)
    btn._scToggleRing = ring
    return ring
end

local function SetToggleSquareRingColor(ring, r, g, b, a)
    if not ring then return end
    for _, edge in pairs(ring) do
        edge:SetColorTexture(r, g, b, a or 1)
        edge:Show()
    end
end

local function ApplyButtonSurfaceGradient(frame, r, g, b, a, hovered, active, isWarm, isTab)
    if not frame then return end
    if not frame._scGradBg then
        local gbg = frame:CreateTexture(nil, "ARTWORK", nil, -2)
        gbg:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        gbg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        frame._scGradBg = gbg
    end
    local topBoost = active and 0.08 or (hovered and 0.07 or 0.045)
    if isTab then
        topBoost = active and 0.09 or (hovered and 0.06 or 0.03)
    end
    local botShade = active and 0.025 or 0.04
    local rTop = math.min(1, r + (isWarm and topBoost * 1.1 or topBoost))
    local gTop = math.min(1, g + topBoost)
    local bTop = math.min(1, b + (isWarm and topBoost * 0.7 or topBoost * 1.15))
    local rBot = math.max(0, r - botShade)
    local gBot = math.max(0, g - botShade)
    local bBot = math.max(0, b - botShade)
    ApplySafeGradient(frame._scGradBg, "VERTICAL", rBot, gBot, bBot, (a or 1) * 0.92, rTop, gTop, bTop, (a or 1) * 0.96)
    frame._scGradBg:Show()

    if not frame._scBtnShadow then
        local sh = frame:CreateTexture(nil, "ARTWORK", nil, 0)
        sh:SetHeight(1)
        sh:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 1)
        sh:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 1)
        frame._scBtnShadow = sh
    end
    frame._scBtnShadow:SetColorTexture(0, 0, 0, active and 0.48 or 0.36)
    frame._scBtnShadow:Show()
end

local function ApplyButtonColors(btn, hovered)
    local p = Theme:GetPalette()
    if not btn.SetBackdrop then
        return
    end
    if btn.SetClipsChildren then
        btn:SetClipsChildren(true)
    end
    local variant = btn._scVariant or "default"
    local active = btn._scActive
    local isBlizz = Theme:IsBlizzard(p)
    btn._scThemeKey = p.key

    Theme:SyncButtonLayers(btn)
    SyncBlizzTextOffset(btn, 0, 0)

    local useBlizzPlate = isBlizz and (variant == "tab")
    if useBlizzPlate then
        local vis = EnsureBlizzButtonVisual(btn, true)
        if vis then
            if btn._scNavIndicator then btn._scNavIndicator:Hide() end
            if btn._scGradBg then btn._scGradBg:Hide() end
            if btn._scBtnShadow then btn._scBtnShadow:Hide() end
            if btn._scAppliedBackdrop ~= nil then
                btn:SetBackdrop(nil)
                btn._scAppliedBackdrop = nil
            end
            Theme:SyncButtonLayers(btn)
            vis:ClearAllPoints()
            vis:SetAllPoints(btn)
            if vis._scAppliedBackdrop ~= BACKDROP_SPEC then
                vis:SetBackdrop(BACKDROP_SPEC)
                vis._scAppliedBackdrop = BACKDROP_SPEC
            end
            if active then
                vis:SetBackdropColor(0.15, 0.13, 0.095, 0.98)
                vis:SetBackdropBorderColor(0.86, 0.68, 0.24, 1)
                ApplyButtonSurfaceGradient(vis, 0.16, 0.135, 0.095, 0.98, hovered, true, true, true)
                vis._topAccent:SetColorTexture(0.98, 0.80, 0.28, 0.98)
                vis._topAccent:Show()
                vis._bottomBridge:SetColorTexture(0.10, 0.09, 0.08, 1)
                vis._bottomBridge:Show()
                SyncBlizzTextOffset(btn, 0, 0)
                if btn.label then
                    btn.label:SetTextColor(1.0, 1.0, 1.0)
                end
            elseif hovered then
                vis:SetBackdropColor(0.12, 0.105, 0.09, 0.96)
                vis:SetBackdropBorderColor(0.68, 0.54, 0.23, 1)
                ApplyButtonSurfaceGradient(vis, 0.12, 0.105, 0.088, 0.96, true, false, true, true)
                vis._topAccent:SetColorTexture(0.84, 0.66, 0.24, 0.72)
                vis._topAccent:Show()
                vis._bottomBridge:SetColorTexture(0.36, 0.29, 0.16, 0.9)
                vis._bottomBridge:Show()
                SyncBlizzTextOffset(btn, 0, -1)
                if btn.label then
                    btn.label:SetTextColor(1.0, 0.94, 0.68)
                end
            else
                vis:SetBackdropColor(0.075, 0.07, 0.075, 0.92)
                vis:SetBackdropBorderColor(0.38, 0.31, 0.17, 0.95)
                ApplyButtonSurfaceGradient(vis, 0.08, 0.075, 0.075, 0.92, false, false, true, true)
                vis._topAccent:SetColorTexture(0.55, 0.44, 0.18, 0.34)
                vis._topAccent:Show()
                vis._bottomBridge:SetColorTexture(0.32, 0.25, 0.13, 0.85)
                vis._bottomBridge:Show()
                SyncBlizzTextOffset(btn, 0, -1)
                if btn.label then
                    local g = p.textGold or p.text
                    btn.label:SetTextColor(g[1], g[2], g[3])
                end
            end
            vis:Show()
            if btn._scBtnGloss then btn._scBtnGloss:Hide() end
            return
        end
    end

    if btn._blizzTabFrame then btn._blizzTabFrame:Hide() end
    if variant == "nav" then
        local parent = btn._textLayer or btn
        if btn.label then
            btn.label:ClearAllPoints()
            btn.label:SetPoint("LEFT", parent, "LEFT", btn._scNavIcon and 28 or 12, 0)
            btn.label:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
            btn.label:SetJustifyH("LEFT")
            btn.label:SetWordWrap(false)
        end
        if not btn._scNavIndicator then
            local ind = btn:CreateTexture(nil, "OVERLAY", nil, 2)
            ind:SetWidth(3)
            ind:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -3)
            ind:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 3)
            btn._scNavIndicator = ind
        end
        local bgNav, brNav, txtNav
        if not btn:IsEnabled() then
            bgNav = { 0.06, 0.055, 0.050, 0.55 }
            brNav = { 0.16, 0.15, 0.14, 0.30 }
            txtNav = p.textDim
            btn._scNavIndicator:Hide()
        elseif active then
            bgNav = isBlizz and { 0.24, 0.17, 0.07, 0.95 } or p.accentDim
            brNav = isBlizz and { 0.84, 0.66, 0.24, 0.90 } or p.accentBorder
            txtNav = { 1.0, 0.96, 0.82 }
            local ic = isBlizz and { 0.98, 0.78, 0.20 } or (p.accentBorder or { 0.35, 0.78, 1.0 })
            btn._scNavIndicator:SetColorTexture(ic[1], ic[2], ic[3], 1.0)
            btn._scNavIndicator:Show()
        elseif hovered then
            bgNav = isBlizz and { 0.16, 0.13, 0.09, 0.90 } or p.rowHoverBg
            brNav = isBlizz and { 0.52, 0.42, 0.22, 0.75 } or p.surfaceBorder
            txtNav = { 1.0, 0.92, 0.65 }
            btn._scNavIndicator:SetColorTexture(0.75, 0.60, 0.24, 0.55)
            btn._scNavIndicator:Show()
        else
            bgNav = isBlizz and { 0.085, 0.078, 0.070, 0.78 } or { 0.08, 0.09, 0.12, 0.65 }
            brNav = isBlizz and { 0.26, 0.22, 0.15, 0.55 } or { 0.16, 0.20, 0.26, 0.55 }
            txtNav = isBlizz and { 0.88, 0.82, 0.68 } or p.textMuted
            btn._scNavIndicator:Hide()
        end
        ApplyBackdropSpec(btn, BACKDROP_SPEC, bgNav, brNav, false)
        if btn:IsEnabled() then
            ApplyButtonSurfaceGradient(btn, bgNav[1], bgNav[2], bgNav[3], bgNav[4] or 0.9, hovered, active, isBlizz or p.key == "native", false)
        else
            if btn._scGradBg then btn._scGradBg:Hide() end
            if btn._scBtnShadow then btn._scBtnShadow:Hide() end
        end
        if btn.label then
            btn.label:SetTextColor(txtNav[1], txtNav[2], txtNav[3])
        end
        if btn._scBtnGloss then btn._scBtnGloss:Hide() end
        return
    elseif btn._scNavIndicator then
        btn._scNavIndicator:Hide()
    end

    SyncBlizzTextOffset(btn, 0, 0)

    local bg, border, textColor
    local isIconToggle = (btn._scIconToggle == true)
    if isIconToggle then
        local enabled = btn:IsEnabled()
        local ac = btn._scToggleActiveCol or { 0.96, 0.76, 0.22 }
        local ring = EnsureToggleSquareRing(btn)
        if not enabled then
            bg = { 0.06, 0.065, 0.075, 0.92 }
            border = { 0.26, 0.28, 0.32, 0.75 }
            textColor = p.textDim
            SetToggleSquareRingColor(ring, 0.26, 0.28, 0.32, 0.70)
        elseif active then
            bg = hovered and { ac[1] * 0.34, ac[2] * 0.34, ac[3] * 0.34, 0.98 }
                or { ac[1] * 0.24, ac[2] * 0.24, ac[3] * 0.24, 0.96 }
            border = { ac[1], ac[2], ac[3], 1.0 }
            textColor = { 1.0, 0.96, 0.84 }
            SetToggleSquareRingColor(ring, ac[1], ac[2], ac[3], 1.0)
        else
            bg = hovered and { 0.14, 0.15, 0.17, 0.96 } or { 0.08, 0.085, 0.095, 0.94 }
            border = hovered and { 0.56, 0.60, 0.66, 0.96 } or { 0.36, 0.38, 0.42, 0.90 }
            textColor = p.textMuted
            if hovered then
                SetToggleSquareRingColor(ring, 0.58, 0.62, 0.68, 0.95)
            else
                SetToggleSquareRingColor(ring, 0.38, 0.40, 0.44, 0.85)
            end
        end
        if btn.ico then
            local inactiveDesat = not (btn._scIconOpts and btn._scIconOpts.keepColorWhenInactive == true)
            local desat = (not enabled) or (not active and inactiveDesat)
            if btn.ico.SetDesaturated then
                btn.ico:SetDesaturated(desat)
            end
            local col = btn._scIconOpts and btn._scIconOpts.color
            if not enabled then
                btn.ico:SetVertexColor(0.55, 0.55, 0.58, 0.45)
            elseif active then
                if col then
                    btn.ico:SetVertexColor(col[1], col[2], col[3], col[4] or 1)
                else
                    btn.ico:SetVertexColor(1, 1, 1, 1)
                end
            else
                if col and not inactiveDesat then
                    btn.ico:SetVertexColor(col[1], col[2], col[3], hovered and 0.92 or 0.72)
                elseif desat then
                    btn.ico:SetVertexColor(0.72, 0.74, 0.78, hovered and 0.92 or 0.78)
                else
                    btn.ico:SetVertexColor(0.85, 0.87, 0.90, hovered and 0.92 or 0.78)
                end
            end
        end
    else
        if btn._scToggleRing then
            for _, edge in pairs(btn._scToggleRing) do
                edge:Hide()
            end
        end
        if not btn:IsEnabled() then
            bg = isBlizz and { 0.07, 0.065, 0.06, 0.88 } or p.insetBg
            border = isBlizz and { 0.24, 0.21, 0.16, 0.75 } or p.surfaceBorder
            textColor = p.textDim
        elseif variant == "primary" or (active and not isBlizz) then
            bg = hovered and p.accent or p.accentDim
            border = p.accentBorder
            textColor = (isBlizz and hovered) and { 1.0, 1.0, 1.0 } or p.text
        elseif active and isBlizz then
            bg = hovered and { 0.28, 0.21, 0.09, 0.98 } or { 0.21, 0.16, 0.07, 0.96 }
            border = { 0.90, 0.72, 0.26, 1.0 }
            textColor = { 1.0, 0.95, 0.78 }
        elseif variant == "danger" then
            bg = hovered and p.dangerHoverBg or p.dangerBg
            border = p.dangerBorder
            textColor = isBlizz and (hovered and { 1.0, 1.0, 1.0 } or { 1.0, 0.86, 0.82 }) or p.text
        elseif variant == "tab" then
            bg = hovered and p.rowHoverBg or p.surfaceBg
            border = p.surfaceBorder
            textColor = hovered and p.text or p.textMuted
        elseif variant == "ghost" then
            if btn._scHelpRing then
                bg = { 0, 0, 0, 0 }
                border = { 0, 0, 0, 0 }
                textColor = hovered and { 1.0, 0.95, 0.72 } or { 0.84, 0.72, 0.38 }
            else
                bg = hovered and (isBlizz and { 0.22, 0.17, 0.09, 0.85 } or p.rowHoverBg) or { 0, 0, 0, 0 }
                border = hovered and (isBlizz and { 0.68, 0.54, 0.22, 0.85 } or p.surfaceBorder) or { 0, 0, 0, 0 }
                textColor = hovered and (isBlizz and { 1.0, 0.90, 0.55 } or p.text) or p.textMuted
            end
        elseif isBlizz then
            -- Sleek Modern Blizzard Charcoal-Bronze Matte Button (replaces archaic red boxes on default utility buttons)
            bg = hovered and { 0.20, 0.17, 0.12, 0.98 } or { 0.12, 0.11, 0.095, 0.96 }
            border = hovered and { 0.84, 0.66, 0.24, 1.0 } or { 0.40, 0.34, 0.21, 0.92 }
            textColor = hovered and { 1.0, 0.96, 0.82 } or { 0.94, 0.86, 0.64 }
        else
            bg = hovered and p.btnHoverBg or p.btnBg
            border = hovered and p.accentBorder or p.btnBorder
            textColor = p.text
        end
    end

    ApplyBackdropSpec(btn, BACKDROP_SPEC, bg, border, false)
    local bw = btn:GetWidth() or 0
    local bh = btn:GetHeight() or 0
    if variant ~= "ghost" and btn:IsEnabled() and bg and (bg[4] or 1) > 0.1 then
        ApplyButtonSurfaceGradient(btn, bg[1], bg[2], bg[3], bg[4] or 1, hovered, active, isBlizz or p.key == "native", variant == "tab")
    else
        if btn._scGradBg then btn._scGradBg:Hide() end
        if btn._scBtnShadow then btn._scBtnShadow:Hide() end
    end
    if variant ~= "ghost" and btn:IsEnabled() and bw >= 28 and bh >= 18 then
        if not btn._scBtnGloss then
            local gloss = btn:CreateTexture(nil, "ARTWORK", nil, 1)
            gloss:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -1)
            gloss:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -1)
            btn._scBtnGloss = gloss
        end
        if variant == "tab" and active then
            btn._scBtnGloss:SetHeight(2)
            local ac = p.accentBorder or { 0.35, 0.78, 1.0 }
            btn._scBtnGloss:SetColorTexture(ac[1], ac[2], ac[3], 0.96)
        else
            btn._scBtnGloss:SetHeight(1)
            btn._scBtnGloss:SetColorTexture(1, 0.96, 0.86, (variant == "primary" or hovered) and 0.24 or 0.11)
        end
        btn._scBtnGloss:Show()
    elseif btn._scBtnGloss then
        btn._scBtnGloss:Hide()
    end
    if btn.label then
        btn.label:SetTextColor(textColor[1], textColor[2], textColor[3])
    end
end

--- Resize a button to comfortably fit its localized text label without clipping.
function Theme:AutoFitButton(btn, minWidth, padding, maxWidth)
    if not btn or not btn.label then
        return 0
    end
    btn._scAutoMin = minWidth or btn._scAutoMin or 0
    if padding ~= nil then
        btn._scAutoPadCustom = padding
    end
    if maxWidth ~= nil then
        btn._scAutoMax = maxWidth
    end
    btn._scAutoFit = true
    local pad = btn._scAutoPadCustom or (self:IsBlizzard() and 22 or 16)
    local textW = MeasureLabelWidth(btn)
    local w = math.max(btn._scAutoMin, textW + pad)
    if btn._scAutoMax and w > btn._scAutoMax then
        w = btn._scAutoMax
    end
    w = math.floor(w + 0.5)
    btn._scAutoFitW = w
    if w > 0 and math.abs((btn:GetWidth() or 0) - w) >= 1 then
        btn:SetWidth(w)
    end
    ApplyButtonColors(btn, false)
    return btn._scAutoFitW or btn:GetWidth() or w
end

--- Clear icon-button texture/tooltip state before restoring text mode.
function Theme:ClearButtonIcon(btn)
    if not btn then return end
    btn._scIconOpts = nil
    btn._scIconToggle = nil
    btn._scToggleActiveCol = nil
    if btn._scToggleRing then
        for _, edge in pairs(btn._scToggleRing) do
            edge:Hide()
        end
    end
    if btn.ico then
        btn.ico:Hide()
    end
end

--- Toggle colored-square (active) vs gray-square (inactive) state on an icon filter/toggle button.
function Theme:SetIconToggle(btn, active, activeColor)
    if not btn then return end
    btn._scIconToggle = true
    btn._scActive = (active == true)
    if activeColor ~= nil then
        btn._scToggleActiveCol = activeColor
    end
    local over = MouseIsOver and MouseIsOver(btn) or false
    local enabled = (not btn.IsEnabled) or btn:IsEnabled()
    ApplyButtonColors(btn, over and enabled)
end

--- Configure or update an icon-only button with cropped game textures, disabled dimming, and hover tooltip.
function Theme:ConfigureIconButton(btn, width, height, tex, opts)
    if not btn then return end
    opts = type(opts) == "table" and opts or {}
    self:SyncButtonLayers(btn)
    btn._scAutoFit = false
    if width and height then
        btn:SetSize(width, height)
        btn._scAutoFitW = width
    end
    self:SetButtonText(btn, "")
    local layer = btn._textLayer or btn
    if not btn.ico then
        btn.ico = layer:CreateTexture(nil, "OVERLAY", nil, 2)
    else
        btn.ico:SetParent(layer)
    end
    btn.ico:ClearAllPoints()
    btn.ico:SetPoint("CENTER", layer, "CENTER", opts.offX or 0, opts.offY or 0)
    local minSide = math.min(width or (btn.GetWidth and btn:GetWidth()) or 20, height or (btn.GetHeight and btn:GetHeight()) or 20)
    local sz = opts.size or math.max(15, math.floor(minSide - 3))
    btn.ico:SetSize(sz, sz)
    if opts.atlas and self.HasAtlas and self:HasAtlas(opts.atlas) and btn.ico.SetAtlas then
        btn.ico:SetAtlas(opts.atlas, false)
    else
        btn.ico:SetTexture(tex)
        local tc = opts.texCoord
        if not tc and type(tex) == "string" then
            if tex:find("Interface\\Icons\\", 1, true) then
                tc = { 0.08, 0.92, 0.08, 0.92 }
            elseif tex:find("Character-Plus", 1, true) or tex:find("ReadyCheck-", 1, true) then
                tc = { 0.12, 0.88, 0.12, 0.88 }
            end
        elseif not tc and type(tex) == "number" then
            tc = { 0.08, 0.92, 0.08, 0.92 }
        end
        if tc then
            btn.ico:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        else
            btn.ico:SetTexCoord(0, 1, 0, 1)
        end
    end
    local isDis = (opts.disabled == true) or (btn.IsEnabled and not btn:IsEnabled())
    if btn.ico.SetDesaturated then
        btn.ico:SetDesaturated(isDis)
    end
    local col = opts.color
    if col then
        btn.ico:SetVertexColor(col[1], col[2], col[3], isDis and 0.50 or (col[4] or 1))
    else
        btn.ico:SetVertexColor(1, 1, 1, isDis and 0.50 or 1)
    end
    btn.ico:Show()
    btn._scIconOpts = opts
    if opts.toggle or opts.active ~= nil or btn._scIconToggle then
        self:SetIconToggle(btn, opts.active, opts.activeColor)
    elseif btn._scToggleRing then
        for _, edge in pairs(btn._scToggleRing) do
            edge:Hide()
        end
    end
    if not btn._scIconTipHooked then
        btn._scIconTipHooked = true
        if btn.SetMotionScriptsWhileDisabled then
            btn:SetMotionScriptsWhileDisabled(true)
        end
        btn:HookScript("OnEnter", function(selfBtn)
            local cur = selfBtn._scIconOpts
            if not (cur and GameTooltip) then return end
            local title, desc
            if type(cur.tooltipFn) == "function" then
                title, desc = cur.tooltipFn(selfBtn)
            else
                title, desc = cur.title, cur.desc
            end
            if title and title ~= "" then
                GameTooltip:SetOwner(selfBtn, cur.anchor or "ANCHOR_TOP")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(title, 1.0, 0.88, 0.35, true)
                if desc and desc ~= "" then
                    GameTooltip:AddLine(desc, 0.85, 0.88, 0.94, true)
                end
                GameTooltip:Show()
            end
        end)
        btn:HookScript("OnLeave", function(selfBtn)
            if GameTooltip and GameTooltip:IsOwned(selfBtn) then
                GameTooltip:Hide()
            end
        end)
    end
end

--- Apply green (Online Only) vs red (Showing Offline) orb visual to an online/offline toggle button.
function Theme:ApplyOnlineOfflineOrb(btn, showOffline, width, height)
    if not btn then return end
    local L = ns.L
    local isShowOff = (showOffline == true)
    btn._scShowOffline = isShowOff
    local tex = isShowOff
        and (FRIENDS_TEXTURE_DND or "Interface\\FriendsFrame\\StatusIcon-DnD")
        or (FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online")
    local ringCol = isShowOff and { 0.95, 0.32, 0.32 } or { 0.25, 0.88, 0.45 }
    self:ConfigureIconButton(btn, width or 24, height or 22, tex, {
        size = 15,
        toggle = true,
        active = true,
        activeColor = ringCol,
        tooltipFn = function(selfBtn)
            local offOn = (selfBtn._scShowOffline == true)
            if offOn then
                return "|cfff54747" .. L["Showing Offline"] .. "|r",
                    L["Click to show online players only"] .. "\n" .. L["Green = Online Only · Red = Showing Offline"]
            end
            return "|cff3fb950" .. L["Online Only"] .. "|r",
                L["Click to show offline players"] .. "\n" .. L["Green = Online Only · Red = Showing Offline"]
        end,
    })
end

--- Create a compact hoverable 'Legend' pill that lists all icons and meanings for a toolbar.
function Theme:CreateLegendTag(parent, getItemsFn)
    local L = ns.L
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(74, 20)
    self:ApplyBackdrop(btn, "surface")
    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("CENTER", 0, 0)
    lbl:SetText(L["Legend"])
    lbl:SetTextColor(0.92, 0.82, 0.48)
    btn.label = lbl
    local tw = math.ceil((lbl:GetStringWidth() or 52) + 16)
    btn:SetWidth(math.max(62, tw))
    btn._scAutoFitW = math.max(62, tw)
    btn:SetScript("OnEnter", function(selfBtn)
        local p = Theme:GetPalette()
        if selfBtn.SetBackdropBorderColor then
            local ac = p.accentBorder or { 0.96, 0.76, 0.22 }
            selfBtn:SetBackdropBorderColor(ac[1], ac[2], ac[3], 1.0)
        end
        lbl:SetTextColor(1.0, 0.94, 0.70)
        if not GameTooltip then return end
        local items = type(getItemsFn) == "function" and getItemsFn() or getItemsFn
        if type(items) ~= "table" or #items == 0 then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Icon Legend"], 1.0, 0.85, 0.25)
        for _, it in ipairs(items) do
            if it.tex then
                local ico = "|T" .. tostring(it.tex) .. ":14:14:0:0|t "
                if it.desc and it.desc ~= "" then
                    GameTooltip:AddDoubleLine(ico .. tostring(it.title or ""), tostring(it.desc), 0.96, 0.96, 0.98, 0.76, 0.82, 0.90)
                else
                    GameTooltip:AddLine(ico .. tostring(it.title or ""), 0.94, 0.95, 0.98, true)
                end
            elseif it.title then
                if it.desc and it.desc ~= "" then
                    GameTooltip:AddDoubleLine(tostring(it.title), tostring(it.desc), 0.96, 0.96, 0.98, 0.76, 0.82, 0.90)
                else
                    GameTooltip:AddLine(tostring(it.title), 0.85, 0.88, 0.94, true)
                end
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(selfBtn)
        Theme:ApplyBackdrop(selfBtn, "surface")
        lbl:SetTextColor(0.92, 0.82, 0.48)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then
            GameTooltip:Hide()
        end
    end)
    return btn
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
            self._scPushed = false
            ApplyButtonColors(self, false)
        end)
        btn:HookScript("OnMouseDown", function(self)
            if self:IsEnabled() then
                self._scPushed = true
                ApplyButtonColors(self, true)
            end
        end)
        btn:HookScript("OnMouseUp", function(self)
            self._scPushed = false
            ApplyButtonColors(self, MouseIsOver and MouseIsOver(self) or false)
        end)
        btn:HookScript("OnEnable", function(self)
            ApplyButtonColors(self, false)
        end)
        btn:HookScript("OnDisable", function(self)
            self._scPushed = false
            ApplyButtonColors(self, false)
        end)
        btn:HookScript("OnShow", function(self)
            Theme:SyncButtonLayers(self)
            if self._scThemeKey ~= Theme:GetPalette().key then
                if self._scAutoFit then
                    Theme:AutoFitButton(self)
                else
                    ApplyButtonColors(self, false)
                end
            end
        end)
        btn:HookScript("OnSizeChanged", function(self)
            SyncBlizzTextOffset(self, 0, 0)
        end)
    end
    if btn._scAutoFit then
        local pad = btn._scAutoPadCustom or (self:IsBlizzard() and 22 or 16)
        local textW = MeasureLabelWidth(btn)
        local w = math.max(btn._scAutoMin or 0, textW + pad)
        if btn._scAutoMax and w > btn._scAutoMax then
            w = btn._scAutoMax
        end
        w = math.floor(w + 0.5)
        btn._scAutoFitW = w
        if w > 0 and math.abs((btn:GetWidth() or 0) - w) >= 1 then
            btn:SetWidth(w)
        end
    end
    ApplyButtonColors(btn, false)
end

--- Create a themed button with centered clamped label.
function Theme:CreateButton(parent, width, height, text, variant)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 80, height or 24)
    if btn.SetClipsChildren then btn:SetClipsChildren(true) end
    btn._textLayer = CreateFrame("Frame", nil, btn)
    btn._textLayer:SetAllPoints()
    btn._textLayer._scIsInternalBtnLayer = true
    if btn._textLayer.SetClipsChildren then btn._textLayer:SetClipsChildren(true) end
    btn._textLayer:SetFrameLevel(math.max(1, btn:GetFrameLevel() + 4))
    btn.label = btn._textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.label:SetText(text or "")
    self:StyleButton(btn, variant)
    return btn
end

--- Update button text while preserving padding/variant.
function Theme:SetButtonText(btn, text)
    if btn and btn.label then
        self:SyncButtonLayers(btn)
        local cleanText = text or ""
        if cleanText ~= "" and btn._scIconOpts ~= nil then
            self:ClearButtonIcon(btn)
        end
        local p = self:GetPalette()
        if btn._scLastBtnText == cleanText and btn._scThemeKey == p.key and btn.label:GetText() == cleanText then
            return
        end
        btn._scLastBtnText = cleanText
        btn._scMeasuredText = nil
        btn.label:SetText(cleanText)
        if btn._scAutoFit then
            self:AutoFitButton(btn)
        else
            ApplyButtonColors(btn, false)
        end
    end
end

--- Update active toggle state on a tab or filter button.
function Theme:SetButtonActive(btn, active, variant)
    if not btn then
        return
    end
    self:SyncButtonLayers(btn)
    local nextActive = active and true or false
    local nextVariant = variant or btn._scVariant
    local p = self:GetPalette()
    if btn._scActive == nextActive and btn._scVariant == nextVariant and btn._scThemeKey == p.key then
        return
    end
    btn._scActive = nextActive
    if variant then
        btn._scVariant = variant
    end
    ApplyButtonColors(btn, false)
end

local STATUS_AWAY_RGB = { 0.96, 0.76, 0.22 }
local STATUS_BUSY_RGB = { 0.92, 0.36, 0.36 }
local STATUS_APP_RGB  = { 0.44, 0.70, 0.96 }

--- Update a ColorTexture or circular dot texture for a character state.
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
    elseif status == "away" then
        c = STATUS_AWAY_RGB
    elseif status == "busy" then
        c = STATUS_BUSY_RGB
    elseif status == "app" then
        c = STATUS_APP_RGB
    end
    if tex._scKeepTexture then
        tex:SetVertexColor(c[1], c[2], c[3], 1)
    else
        tex:SetColorTexture(c[1], c[2], c[3], 1)
    end
end

local function ApplyInputBackdrop(target, focused, hovered, textTarget)
    if not target or not target.SetBackdrop then
        return
    end
    local p = Theme:GetPalette()
    local isBlizz = Theme:IsBlizzard(p)
    local bg, border, textColor
    if isBlizz then
        bg = { 0.055, 0.050, 0.045, 1.0 }
        if focused then
            border = { 0.96, 0.78, 0.22, 1.0 }
        elseif hovered then
            border = { 0.70, 0.58, 0.34, 1.0 }
        else
            border = { 0.46, 0.40, 0.28, 1.0 }
        end
        textColor = { 1.0, 0.95, 0.84 }
    else
        bg = p.insetBg
        if focused then
            border = p.accentBorder
        elseif hovered then
            border = p.btnBorder
        else
            border = p.surfaceBorder
        end
        textColor = p.text
    end

    local styleSig = tostring(p and p.key or "dark") .. ":" .. (focused and "F" or "_") .. (hovered and "H" or "_")
    if target._scAppliedBackdrop ~= BACKDROP_SPEC then
        target:SetBackdrop(BACKDROP_SPEC)
        target._scAppliedBackdrop = BACKDROP_SPEC
        target._scInputStyleSig = nil
    end
    if target._scInputStyleSig ~= styleSig then
        target._scInputStyleSig = styleSig
        target:SetBackdropColor(bg[1], bg[2], bg[3], 1.0)
        target:SetBackdropBorderColor(border[1], border[2], border[3], 1.0)
        if not target._scNoInputShade and target.CreateTexture then
            if not target._scInputTopShade then
                local sh = target:CreateTexture(nil, "ARTWORK", nil, -1)
                sh:SetHeight(2)
                sh:SetPoint("TOPLEFT", target, "TOPLEFT", 1, -1)
                sh:SetPoint("TOPRIGHT", target, "TOPRIGHT", -1, -1)
                target._scInputTopShade = sh
            end
            target._scInputTopShade:SetColorTexture(0, 0, 0, focused and 0.25 or 0.42)
            target._scInputTopShade:Show()
        end
        if textTarget and textTarget.SetTextColor then
            textTarget:SetTextColor(textColor[1], textColor[2], textColor[3])
        end
    end
end

function Theme:ApplyInputBackdrop(target, focused, hovered, textTarget)
    return ApplyInputBackdrop(target, focused, hovered, textTarget)
end

--- Apply responsive theme visuals and placeholder updates to a Theme EditBox.
function Theme:StyleEditBox(box)
    if not box then
        return
    end
    if not box._scNoBackdrop then
        ApplyInputBackdrop(box, box._scFocused, box._scHovered, box)
    end
    if box.placeholder then
        local p = self:GetPalette()
        box.placeholder:SetTextColor(p.textDim[1], p.textDim[2], p.textDim[3])
    end
end

--- Create a crisp, theme-aware, responsively padded EditBox (replaces inconsistent InputBoxTemplate 9-slices).
function Theme:InstallEditBoxLinkHook()
    if self._editBoxLinkHooked then return end
    self._editBoxLinkHooked = true
    local function HandleChatEditInsertLink(text)
        if ns.Safe and ns.Safe.IsSecret and ns.Safe.IsSecret(text) then
            return
        end
        if type(text) ~= "string" or text == "" then
            return
        end
        local monoNow = (GetTime and GetTime()) or 0
        if Theme._lastInsertLinkText == text and Theme._lastInsertLinkAt and (monoNow - Theme._lastInsertLinkAt) < 0.03 then
            return
        end
        Theme._lastInsertLinkText = text
        Theme._lastInsertLinkAt = monoNow

        local blizzBox = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
            or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
            or nil
        if blizzBox and blizzBox.IsVisible and blizzBox:IsVisible()
            and ((not blizzBox.HasFocus) or blizzBox:HasFocus())
            and ((not blizzBox.GetEffectiveAlpha) or (blizzBox:GetEffectiveAlpha() or 0) > 0.05)
        then
            if ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown() then
                ns.QuickReply.lastInputAt = monoNow
                ns.QuickReply._lastOpaqueActivityAt = monoNow
                ns.QuickReply.idleCountdown = nil
            end
            if _G.StackSplitFrame and _G.StackSplitFrame.IsShown and _G.StackSplitFrame:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
                pcall(_G.StackSplitFrame.Hide, _G.StackSplitFrame)
            end
            return
        end
        local box = Theme._focusedEditBox
        local useQrOfficial = false
        local focusQrInput = false
        if not (box and box.HasFocus and box:HasFocus() and box:IsVisible() and (not box.IsEnabled or box:IsEnabled())) then
            box = nil
            local qr = ns.QuickReply and ns.QuickReply.frame
            if qr and qr.IsVisible and qr:IsVisible() and (not qr.GetAlpha or qr:GetAlpha() > 0.1) then
                if ns.QuickReply.IsOfficialOnlyThread and ns.QuickReply:IsOfficialOnlyThread() then
                    useQrOfficial = true
                elseif qr.inputBox and qr.inputBox.IsVisible and qr.inputBox:IsVisible()
                    and (not qr.inputBox.IsEnabled or qr.inputBox:IsEnabled())
                then
                    box = qr.inputBox
                    focusQrInput = true
                end
            elseif Theme._activeChatReplyBox and Theme._activeChatReplyBox.IsVisible and Theme._activeChatReplyBox:IsVisible() and (not Theme._activeChatReplyBox.IsEnabled or Theme._activeChatReplyBox:IsEnabled()) then
                box = Theme._activeChatReplyBox
            end
        end
        if useQrOfficial and ns.QuickReply and ns.QuickReply.ActivateDockedOfficialInput then
            ns.QuickReply.interactedOutside = false
            ns.QuickReply.lastInputAt = monoNow
            ns.QuickReply._lastOpaqueActivityAt = monoNow
            ns.QuickReply.idleCountdown = nil
            if ns.QuickReply:ActivateDockedOfficialInput("") then
                local activeEb = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
                    or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
                    or _G.ChatFrame1EditBox
                if activeEb and activeEb.Insert then
                    local ins = text
                    if activeEb.GetText and activeEb.GetCursorPosition then
                        local cur = activeEb:GetText() or ""
                        local pos = activeEb:GetCursorPosition() or #cur
                        if pos > 0 and cur:sub(pos, pos) ~= " " then
                            ins = " " .. ins
                        end
                    end
                    if ins:sub(-1) ~= " " then
                        ins = ins .. " "
                    end
                    pcall(activeEb.Insert, activeEb, ins)
                end
                if _G.StackSplitFrame and _G.StackSplitFrame.IsShown and _G.StackSplitFrame:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
                    pcall(_G.StackSplitFrame.Hide, _G.StackSplitFrame)
                end
            end
            return
        end
        if not box then
            return
        end
        local inserted = text
        if box._scInsertLinkMode ~= "full" then
            inserted = text:gsub("|c%x%x%x%x%x%x%x%x", "")
                :gsub("|r", "")
                :gsub("|H[^|]+|h%[?([^%]]*)%]?|h", "%1")
                :gsub("^%s+", "")
                :gsub("%s+$", "")
        elseif box.GetText and box.GetCursorPosition then
            local cur = box:GetText() or ""
            local pos = box:GetCursorPosition() or #cur
            if pos > 0 and cur:sub(pos, pos) ~= " " then
                inserted = " " .. inserted
            end
            if inserted:sub(-1) ~= " " then
                inserted = inserted .. " "
            end
        end
        if inserted ~= "" and box.Insert then
            box:Insert(inserted)
            if focusQrInput and ns.QuickReply and ns.QuickReply.FocusInputBox then
                ns.QuickReply:FocusInputBox()
                if box.SetCursorPosition then
                    box:SetCursorPosition(#(box:GetText() or ""))
                end
            elseif box.SetFocus and not (box.HasFocus and box:HasFocus()) and not (InCombatLockdown and InCombatLockdown()) then
                pcall(box.SetFocus, box)
            end
            if box._scInsertLinkMode == "full" and _G.StackSplitFrame and _G.StackSplitFrame.IsShown and _G.StackSplitFrame:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
                pcall(_G.StackSplitFrame.Hide, _G.StackSplitFrame)
            end
        end
    end
    if type(_G.ChatEdit_InsertLink) == "function" then
        hooksecurefunc("ChatEdit_InsertLink", HandleChatEditInsertLink)
    end
    if _G.ChatFrameUtil and type(_G.ChatFrameUtil.InsertLink) == "function" then
        hooksecurefunc(_G.ChatFrameUtil, "InsertLink", HandleChatEditInsertLink)
    end
end

function Theme:ShowHyperlinkTooltip(owner, link)
    if not owner or type(link) ~= "string" or link == "" then
        return false
    end
    owner._scHoveredHyperlink = link
    if not GameTooltip then return false end
    if link:find("addon:SCentral:w:", 1, true) then
        local who = link:match("addon:SCentral:w:([^|]+)") or "?"
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(who, 1.0, 0.88, 0.35, true)
        GameTooltip:AddLine(L["Click: Whisper · Alt+Click: Invite · Ctrl+Click: Social Card · Right-click: Options"], 0.82, 0.88, 0.94, true)
        GameTooltip:Show()
        return true
    elseif link:find("addon:SCentral:grp:", 1, true) then
        local idxStr, tKey = link:match("addon:SCentral:grp:(%d+):([^|]+)")
        local snap = (ns.Chat and ns.Chat.GetThreadGroupSnapshot) and ns.Chat:GetThreadGroupSnapshot(tKey, tonumber(idxStr)) or nil
        if snap and snap.roster and type(snap.roster.members) == "table" then
            GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
            GameTooltip:ClearLines()
            local count = snap.roster.size or #snap.roster.members
            local refTs = snap.startedAt or snap.msgTs
            local whenStr = (refTs and ns.Chat and ns.Chat.FormatWhenLabel) and ns.Chat:FormatWhenLabel(refTs, true) or ""
            local hdr = (whenStr ~= "")
                and string.format(L["Group · %s (%d players)"], whenStr, count)
                or string.format(L["Group (%d players)"], count)
            if snap.roster.zone and snap.roster.zone ~= "" then
                hdr = hdr .. " · " .. snap.roster.zone
            end
            GameTooltip:AddLine(hdr, 0.48, 0.72, 1.0, true)
            for _, mem in ipairs(snap.roster.members) do
                local cHex = (mem.c and ns.Compat and ns.Compat.ClassHex and ns.Compat.ClassHex(mem.c)) or "|cffe6edf3"
                local roleLbl = nil
                if mem.r == "TANK" then roleLbl = L["Tank"]
                elseif mem.r == "HEALER" then roleLbl = L["Healer"]
                elseif mem.r == "DAMAGER" then roleLbl = L["DPS"]
                end
                local isSelf = ns.Compat and ns.Compat.IsMe and ns.Compat.IsMe(mem.n)
                local leftTxt = cHex .. tostring(mem.n or "?") .. "|r" .. (isSelf and (" |cff8cc2ff(" .. L["You"] .. ")|r") or "")
                if roleLbl then
                    GameTooltip:AddDoubleLine(leftTxt, roleLbl, 1, 1, 1, 0.72, 0.78, 0.86)
                else
                    GameTooltip:AddLine(leftTxt, 1, 1, 1, true)
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Click to whisper or invite members from this group"], 0.65, 0.78, 0.92, true)
            GameTooltip:Show()
            return true
        end
        return false
    elseif link:find("addon:SCentral:msgact:", 1, true) then
        local idxStr, tKey = link:match("addon:SCentral:msgact:(%d+):?([^|]*)")
        if (not tKey or tKey == "") and ns.Chat then
            tKey = (ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown() and ns.QuickReply.activeKey) or ns.Chat.activeThreadKey
        end
        local thr = tKey and ns.Chat and ns.Chat.threads and ns.Chat.threads[tKey]
        local entry = idxStr and thr and thr.messages and thr.messages[tonumber(idxStr) or -1]
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        if entry and tonumber(entry.ts) and tonumber(entry.ts) > 0 and ns.Chat and ns.Chat.FormatRelativeWhenText then
            GameTooltip:AddLine(ns.Chat:FormatRelativeWhenText(entry.ts), 1.0, 0.88, 0.35, true)
        else
            GameTooltip:AddLine(L["Message Actions"], 1.0, 0.88, 0.35, true)
        end
        if entry and entry.groupRosterId and ns.Chat and ns.Chat.GetThreadGroupSnapshot then
            local gSnap = ns.Chat:GetThreadGroupSnapshot(tKey, tonumber(idxStr))
            if gSnap and gSnap.roster then
                local gCnt = gSnap.roster.size or (gSnap.roster.members and #gSnap.roster.members) or 0
                local gInfoLine = string.format(L["%d players in group"], math.max(1, gCnt))
                if gSnap.roster.zone and gSnap.roster.zone ~= "" then
                    gInfoLine = gSnap.roster.zone .. " · " .. gInfoLine
                end
                GameTooltip:AddLine(gInfoLine, 0.48, 0.76, 1.0, true)
            end
        end
        GameTooltip:AddLine(L["Click to quote, copy, or save to notes."], 0.82, 0.88, 0.94, true)
        GameTooltip:Show()
        return true
    elseif link:find("addon:SCentral:url:", 1, true) then
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Copy Link"], 0.40, 0.74, 1.0, true)
        GameTooltip:AddLine(L["Press Ctrl+C to copy this link to your clipboard."], 0.82, 0.88, 0.94, true)
        GameTooltip:Show()
        return true
    elseif link:find("^addon:") or link:find("^player") or link:find("^BNplayer") or link:find("^channel:") then
        return false
    end

    if GameTooltip.SetHyperlink then
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        if ok and GameTooltip:NumLines() and GameTooltip:NumLines() > 0 then
            if (IsModifiedClick and IsModifiedClick("COMPAREITEMS")) or (IsShiftKeyDown and IsShiftKeyDown()) then
                if _G.GameTooltip_ShowCompareItem then
                    pcall(_G.GameTooltip_ShowCompareItem, GameTooltip)
                end
            else
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Click to view · Shift+Click to link"], 0.62, 0.72, 0.84, true)
                GameTooltip:AddLine(L["Hold Shift to compare"], 0.54, 0.64, 0.74, true)
            end
            GameTooltip:Show()
            return true
        else
            GameTooltip:Hide()
        end
    end
    return false
end

function Theme:HideHyperlinkTooltip(owner)
    if owner then
        owner._scHoveredHyperlink = nil
    end
    if GameTooltip and (not owner or GameTooltip:IsOwned(owner)) then
        GameTooltip:Hide()
    end
    if _G.ShoppingTooltip1 and _G.ShoppingTooltip1.Hide then _G.ShoppingTooltip1:Hide() end
    if _G.ShoppingTooltip2 and _G.ShoppingTooltip2.Hide then _G.ShoppingTooltip2:Hide() end
end

function Theme:OpenGroupSnapshotMenu(owner, threadKey, msgIdx)
    if not (owner and MenuUtil and MenuUtil.CreateContextMenu and ns.Chat and ns.Chat.GetThreadGroupSnapshot) then
        return false
    end
    local snap = ns.Chat:GetThreadGroupSnapshot(threadKey, tonumber(msgIdx))
    if not (snap and snap.roster and type(snap.roster.members) == "table") then
        return false
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        local count = snap.roster.size or #snap.roster.members
        local refTs = snap.startedAt or snap.msgTs
        local whenStr = (refTs and ns.Chat and ns.Chat.FormatWhenLabel) and ns.Chat:FormatWhenLabel(refTs, true) or ""
        local hdr = (whenStr ~= "")
            and string.format(L["Group · %s (%d players)"], whenStr, count)
            or string.format(L["Group (%d players)"], count)
        if snap.roster.zone and snap.roster.zone ~= "" then
            hdr = hdr .. " · " .. snap.roster.zone
        end
        root:CreateTitle(hdr)
        for _, mem in ipairs(snap.roster.members) do
            if mem.n and mem.n ~= "" then
                local isSelf = ns.Compat and ns.Compat.IsMe and ns.Compat.IsMe(mem.n)
                local roleSuffix = ""
                if mem.r == "TANK" then roleSuffix = " (" .. L["Tank"] .. ")"
                elseif mem.r == "HEALER" then roleSuffix = " (" .. L["Healer"] .. ")"
                elseif mem.r == "DAMAGER" then roleSuffix = " (" .. L["DPS"] .. ")"
                end
                if isSelf then
                    root:CreateTitle(mem.n .. " (" .. L["You"] .. ")" .. roleSuffix)
                else
                    local sub = root:CreateButton(mem.n .. roleSuffix)
                    sub:CreateButton(L["Whisper"], function()
                        if ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown() and ns.Chat and ns.Chat.EnsureWhisperThread then
                            local wt = ns.Chat:EnsureWhisperThread(mem.n)
                            if wt and wt.key then
                                ns.QuickReply:SaveCurrentDraft()
                                ns.QuickReply:SelectThread(wt.key, true)
                                return
                            end
                        end
                        if ns.Compat and ns.Compat.Whisper then
                            ns.Compat.Whisper(mem.n)
                        end
                    end)
                    sub:CreateButton(L["Invite to Group"], function()
                        if InCombatLockdown and InCombatLockdown() then
                            ns:Print("%s", L["Unavailable during combat."])
                        elseif ns.Compat and ns.Compat.Invite then
                            ns.Compat.Invite(mem.n)
                        end
                    end)
                end
            end
        end
    end)
    return true
end

function Theme:HandleGameHyperlinkClick(link, text, button, ownerFrame, insertBox)
    if type(link) ~= "string" or link == "" or link:find("^addon:") then
        return false
    end
    local isLinkMod = (IsModifiedClick and IsModifiedClick("CHATLINK")) or (IsShiftKeyDown and IsShiftKeyDown())
    if isLinkMod and type(text) == "string" and text ~= "" then
        local blizzBox = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
            or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
            or nil
        if blizzBox and blizzBox.IsVisible and blizzBox:IsVisible() and ((not blizzBox.HasFocus) or blizzBox:HasFocus()) then
            if _G.ChatFrameUtil and _G.ChatFrameUtil.InsertLink then
                pcall(_G.ChatFrameUtil.InsertLink, text)
                return true
            elseif _G.ChatEdit_InsertLink then
                pcall(_G.ChatEdit_InsertLink, text)
                return true
            end
        end
        if ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown()
            and ns.QuickReply.IsOfficialOnlyThread and ns.QuickReply:IsOfficialOnlyThread()
            and ns.QuickReply.ActivateDockedOfficialInput
        then
            if ns.QuickReply:ActivateDockedOfficialInput("") then
                local activeEb = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
                    or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
                    or _G.ChatFrame1EditBox
                if activeEb and activeEb.Insert then
                    local ins = text
                    if activeEb.GetText and activeEb.GetCursorPosition then
                        local cur = activeEb:GetText() or ""
                        local pos = activeEb:GetCursorPosition() or #cur
                        if pos > 0 and cur:sub(pos, pos) ~= " " then
                            ins = " " .. ins
                        end
                    end
                    if ins:sub(-1) ~= " " then
                        ins = ins .. " "
                    end
                    pcall(activeEb.Insert, activeEb, ins)
                end
                return true
            end
        end
        if insertBox and insertBox.IsVisible and insertBox:IsVisible() and (not insertBox.IsEnabled or insertBox:IsEnabled()) and insertBox.Insert then
            local cur = insertBox.GetText and insertBox:GetText() or ""
            local pos = insertBox.GetCursorPosition and insertBox:GetCursorPosition() or #cur
            local ins = ((pos > 0 and cur:sub(pos, pos) ~= " ") and " " or "") .. text .. " "
            insertBox:Insert(ins)
            if ns.QuickReply and ns.QuickReply.frame and insertBox == ns.QuickReply.frame.inputBox and ns.QuickReply.FocusInputBox then
                ns.QuickReply:FocusInputBox()
                if insertBox.SetCursorPosition then
                    insertBox:SetCursorPosition(#(insertBox:GetText() or ""))
                end
            elseif insertBox.SetFocus and not (InCombatLockdown and InCombatLockdown()) then
                pcall(insertBox.SetFocus, insertBox)
            end
            return true
        end
        if _G.ChatFrameUtil and _G.ChatFrameUtil.InsertLink then
            pcall(_G.ChatFrameUtil.InsertLink, text)
            return true
        elseif _G.ChatEdit_InsertLink then
            pcall(_G.ChatEdit_InsertLink, text)
            return true
        end
    end
    local isDressMod = (IsModifiedClick and IsModifiedClick("DRESSUP"))
        or ((IsControlKeyDown and IsControlKeyDown()) and not (IsShiftKeyDown and IsShiftKeyDown()) and not (IsAltKeyDown and IsAltKeyDown()))
    if isDressMod and (link:find("^item:") or link:find("^transmog")) then
        local fullLink = link
        if type(text) == "string" and text:find("|H", 1, true) then
            fullLink = text
        else
            local nameTxt = (type(text) == "string" and text ~= "") and text or ""
            if not nameTxt:find("^%[") then
                nameTxt = "[" .. nameTxt .. "]"
            end
            fullLink = "|H" .. link .. "|h" .. nameTxt .. "|h"
        end
        local done = false
        if _G.DressUpItemLink then
            local ok, res = pcall(_G.DressUpItemLink, fullLink)
            done = ok and res ~= false
            if not done then
                ok, res = pcall(_G.DressUpItemLink, link)
                done = ok and res ~= false
            end
        end
        if not done and _G.DressUpLink then
            local ok = pcall(_G.DressUpLink, fullLink)
            done = ok
        end
        if not done and _G.HandleModifiedItemClick then
            local ok = pcall(_G.HandleModifiedItemClick, fullLink)
            done = ok
        end
        return true
    end
    if _G.ChatFrame_OnHyperlinkShow then
        pcall(_G.ChatFrame_OnHyperlinkShow, ownerFrame, link, text, button)
        return true
    elseif _G.SetItemRef and not (InCombatLockdown and InCombatLockdown()) then
        pcall(_G.SetItemRef, link, text, button, ownerFrame)
        return true
    end
    return false
end

function Theme:CreateEditBox(parent, opts)
    opts = opts or {}
    self:InstallEditBoxLinkHook()
    local box = CreateFrame("EditBox", opts.name, parent, "BackdropTemplate")
    box._scInsertLinkMode = opts.insertLinkMode or "name"
    box:SetSize(opts.width or 180, opts.height or 24)
    box:SetAutoFocus(opts.autoFocus == true)
    box:SetFontObject(opts.font or GameFontHighlight)
    local rightInset = opts.clearButton and 22 or 9
    box:SetTextInsets(9, rightInset, 2, 2)
    box:SetJustifyH("LEFT")
    if opts.maxLetters then
        box:SetMaxLetters(opts.maxLetters)
    end
    if opts.numeric then
        box:SetNumeric(true)
    end

    local placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", box, "LEFT", 9, 0)
    placeholder:SetPoint("RIGHT", box, "RIGHT", -rightInset, 0)
    placeholder:SetJustifyH("LEFT")
    placeholder:SetWordWrap(false)
    placeholder:SetText(opts.placeholder or "")
    box.placeholder = placeholder

    if opts.clearButton then
        local clearBtn = CreateFrame("Button", nil, box)
        clearBtn:SetSize(16, 16)
        clearBtn:SetPoint("RIGHT", box, "RIGHT", -4, 0)
        clearBtn._scLevelOffset = 4
        clearBtn:SetFrameLevel((box:GetFrameLevel() or 1) + 4)
        local xText = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        xText:SetPoint("CENTER", 0, 0)
        xText:SetText("x")
        clearBtn.label = xText
        clearBtn:SetScript("OnEnter", function()
            xText:SetFontObject(GameFontHighlightSmall)
        end)
        clearBtn:SetScript("OnLeave", function()
            xText:SetFontObject(GameFontDisableSmall)
        end)
        clearBtn:SetScript("OnClick", function()
            box:SetText("")
        end)
        clearBtn:Hide()
        box._scClearBtn = clearBtn
    end

    function box:UpdateClearButton()
        if not self._scClearBtn then
            return
        end
        local txt = self:GetText() or ""
        self._scClearBtn:SetShown(txt ~= "")
    end

    function box:UpdatePlaceholder()
        if not self.placeholder then
            return
        end
        local txt = self:GetText() or ""
        local hint = self.placeholder:GetText() or ""
        self.placeholder:SetShown(hint ~= "" and txt == "" and not self:HasFocus())
    end

    function box:SetPlaceholder(text)
        if self.placeholder then
            self.placeholder:SetText(text or "")
            self:UpdatePlaceholder()
        end
    end

    box:SetScript("OnEditFocusGained", function(self)
        self._scFocused = true
        Theme._focusedEditBox = self
        self:UpdatePlaceholder()
        Theme:StyleEditBox(self)
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self._scFocused = false
        if Theme._focusedEditBox == self then
            Theme._focusedEditBox = nil
        end
        self:UpdatePlaceholder()
        Theme:StyleEditBox(self)
    end)
    box:SetScript("OnTextChanged", function(self)
        self:UpdatePlaceholder()
        self:UpdateClearButton()
    end)
    box:SetScript("OnEnter", function(self)
        self._scHovered = true
        Theme:StyleEditBox(self)
    end)
    box:SetScript("OnLeave", function(self)
        self._scHovered = false
        Theme:StyleEditBox(self)
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    self:RegisterListener(function()
        Theme:StyleEditBox(box)
    end)
    self:StyleEditBox(box)
    box:UpdatePlaceholder()
    return box
end

--- Enhance a Blizzard SearchBoxTemplate input with clean text insets, clipped instructions, and themed borders.
function Theme:StyleSearchBox(searchBox)
    if not searchBox then
        return
    end
    for _, regName in ipairs({ "Left", "Middle", "Right", "Mid" }) do
        local tex = searchBox[regName]
        if tex and tex.Hide then
            tex:Hide()
        end
    end

    searchBox._scLevelOffset = 2
    if not searchBox._scBg then
        local bg = CreateFrame("Frame", nil, searchBox:GetParent(), "BackdropTemplate")
        bg:SetPoint("TOPLEFT", searchBox, "TOPLEFT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", searchBox, "BOTTOMRIGHT", 0, 0)
        bg:SetFrameLevel(math.max(0, (searchBox:GetFrameLevel() or 1) - 1))
        bg:EnableMouse(false)
        bg._scIsInputBackdrop = true
        searchBox._scBg = bg

        searchBox:HookScript("OnEditFocusGained", function(self)
            self._scFocused = true
            ApplyInputBackdrop(self._scBg, true, self._scHovered, self)
        end)
        searchBox:HookScript("OnEditFocusLost", function(self)
            self._scFocused = false
            ApplyInputBackdrop(self._scBg, false, self._scHovered, self)
        end)
        searchBox:HookScript("OnEnter", function(self)
            self._scHovered = true
            ApplyInputBackdrop(self._scBg, self._scFocused, true, self)
        end)
        searchBox:HookScript("OnLeave", function(self)
            self._scHovered = false
            ApplyInputBackdrop(self._scBg, self._scFocused, false, self)
        end)
        self:RegisterListener(function()
            ApplyInputBackdrop(searchBox._scBg, searchBox._scFocused, searchBox._scHovered, searchBox)
        end)
    end

    searchBox:SetTextInsets(22, 22, 2, 2)
    if searchBox.searchIcon then
        searchBox.searchIcon:ClearAllPoints()
        searchBox.searchIcon:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
    end
    if searchBox.Instructions then
        searchBox.Instructions:ClearAllPoints()
        searchBox.Instructions:SetPoint("LEFT", searchBox, "LEFT", 22, 0)
        searchBox.Instructions:SetPoint("RIGHT", searchBox, "RIGHT", -22, 0)
        searchBox.Instructions:SetJustifyH("LEFT")
        searchBox.Instructions:SetWordWrap(false)
    end
    ApplyInputBackdrop(searchBox._scBg, searchBox._scFocused, searchBox._scHovered, searchBox)
end

local helpPopup
local guideSpotlight
local updatePopup
local movableRegistry = {}

local function CanDragWindow(win, opts)
    if not win then return false end
    if win.IsShown and not win:IsShown() then return false end
    if win._scLocked or win._scSizing then return false end
    if UIParent and win.GetParent and win:GetParent() ~= UIParent then
        local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if not inCombat and win.SetParent then
            pcall(win.SetParent, win, UIParent)
        end
        if win:GetParent() ~= UIParent then
            return false
        end
    end
    if opts and type(opts.locked) == "function" and opts.locked() then return false end
    if opts and opts.combatLock and InCombatLockdown and InCombatLockdown() then
        return false
    end
    return true
end

local function GetRelativeScaleToUIParent(win)
    local scale = (win and win.GetScale and win:GetScale()) or 1
    if win and UIParent and win.GetParent and win:GetParent() == UIParent and win.GetEffectiveScale and UIParent.GetEffectiveScale then
        local we = win:GetEffectiveScale()
        local ue = UIParent:GetEffectiveScale()
        if we and ue and ue > 0 then
            scale = we / ue
        end
    end
    if not scale or scale <= 0 then
        scale = 1
    end
    return scale
end

Theme._viewportListeners = Theme._viewportListeners or {}

function Theme:GetScreenDimensions()
    local uw, uh
    if UIParent and UIParent.GetSize then
        uw, uh = UIParent:GetSize()
    end
    uw = tonumber(uw)
    uh = tonumber(uh)
    if not uw or not uh or uw < 300 or uh < 200 then
        if GetPhysicalScreenSize then
            local okP, pw, ph = pcall(GetPhysicalScreenSize)
            if okP and tonumber(pw) and tonumber(ph) and pw >= 300 and ph >= 200 then
                uw, uh = pw, ph
            end
        end
    end
    uw = math.floor((uw or 1280) + 0.5)
    uh = math.floor((uh or 720) + 0.5)
    return uw, uh, tostring(uw) .. "x" .. tostring(uh)
end

function Theme:GetScreenProfileKey()
    local _, _, key = self:GetScreenDimensions()
    return key
end

function Theme:ResolveResolutionBucket(rootTbl, createIfMissing)
    if type(rootTbl) ~= "table" then
        return nil, nil, false
    end
    local uw, uh, curKey = self:GetScreenDimensions()
    if type(rootTbl[curKey]) == "table" then
        return rootTbl[curKey], curKey, false
    end
    if not createIfMissing then
        local bestKey, bestBucket, bestDist = nil, nil, 999999
        for k, v in pairs(rootTbl) do
            if type(k) == "string" and type(v) == "table" then
                local bw, bh = k:match("^(%d+)x(%d+)$")
                bw = tonumber(bw)
                bh = tonumber(bh)
                if bw and bh then
                    local dw = math.abs(bw - uw)
                    local dh = math.abs(bh - uh)
                    if dw <= 24 and dh <= 24 then
                        local dist = dw + dh
                        if dist < bestDist then
                            bestDist = dist
                            bestKey = k
                            bestBucket = v
                        end
                    end
                end
            end
        end
        if bestBucket then
            return bestBucket, bestKey, true
        end
        return nil, curKey, false
    end
    rootTbl[curKey] = {}
    return rootTbl[curKey], curKey, false
end

function Theme:EnsureResolutionPositionsMigrated()
    if not ns.db or ns.db.windowPositionsMigratedToRes == true then
        return
    end
    local uw, uh, curKey = self:GetScreenDimensions()
    if uw < 300 or uh < 200 then
        return
    end
    if type(ns.db.windowPositionsByRes) ~= "table" then
        ns.db.windowPositionsByRes = {}
    end
    local bucket = ns.db.windowPositionsByRes[curKey]
    if type(bucket) ~= "table" then
        bucket = {}
        ns.db.windowPositionsByRes[curKey] = bucket
    end
    if type(ns.db.windowPositions) == "table" then
        for posKey, posData in pairs(ns.db.windowPositions) do
            if type(posKey) == "string" and type(posData) == "table" and bucket[posKey] == nil then
                bucket[posKey] = {
                    anchor = posData.anchor,
                    dx = posData.dx,
                    dy = posData.dy,
                    width = posData.width,
                    height = posData.height,
                }
            end
        end
    end
    if type(ns.db.window) == "table" then
        local winW = tonumber(ns.db.window.width)
        local winH = tonumber(ns.db.window.height)
        if (winW and winW > 0 and winW ~= 790) or (winH and winH > 0 and winH ~= 520) or bucket["main"] ~= nil then
            if type(bucket["main"]) ~= "table" then
                bucket["main"] = {}
            end
            if winW and winW > 0 and bucket["main"].width == nil then
                bucket["main"].width = math.floor(winW + 0.5)
            end
            if winH and winH > 0 and bucket["main"].height == nil then
                bucket["main"].height = math.floor(winH + 0.5)
            end
        end
    end
    ns.db.windowPositionsMigratedToRes = true
end

function Theme:GetSavedWindowPosition(posKey)
    if not (posKey and ns.db) then return nil end
    self:EnsureResolutionPositionsMigrated()
    local byRes = ns.db.windowPositionsByRes
    local bucket = type(byRes) == "table" and self:ResolveResolutionBucket(byRes, false) or nil
    local rec = type(bucket) == "table" and bucket[posKey] or nil
    if type(rec) == "table" and rec.dx ~= nil and rec.dy ~= nil then
        return rec
    end
    return nil
end

function Theme:HasSavedWindowPosition(posKey)
    return self:GetSavedWindowPosition(posKey) ~= nil
end

function Theme:SetSavedWindowPosition(posKey, data)
    if not (posKey and ns.db and type(data) == "table") then return end
    self:EnsureResolutionPositionsMigrated()
    if type(ns.db.windowPositionsByRes) ~= "table" then
        ns.db.windowPositionsByRes = {}
    end
    if type(ns.db.windowPositions) ~= "table" then
        ns.db.windowPositions = {}
    end
    local bucket = self:ResolveResolutionBucket(ns.db.windowPositionsByRes, true)
    local prev = type(bucket[posKey]) == "table" and bucket[posKey] or nil
    local rec = {
        anchor = data.anchor or (prev and prev.anchor) or "CENTER",
        dx = data.dx,
        dy = data.dy,
        width = data.width or (prev and prev.width) or nil,
        height = data.height or (prev and prev.height) or nil,
    }
    bucket[posKey] = rec
    ns.db.windowPositions[posKey] = {
        anchor = rec.anchor,
        dx = rec.dx,
        dy = rec.dy,
    }
end

function Theme:SaveWindowSize(posKey, w, h)
    if not (posKey and ns.db and tonumber(w) and tonumber(h)) then return end
    self:EnsureResolutionPositionsMigrated()
    if type(ns.db.windowPositionsByRes) ~= "table" then
        ns.db.windowPositionsByRes = {}
    end
    local bucket = self:ResolveResolutionBucket(ns.db.windowPositionsByRes, true)
    if type(bucket[posKey]) ~= "table" then
        bucket[posKey] = {}
    end
    bucket[posKey].width = math.floor(tonumber(w) + 0.5)
    bucket[posKey].height = math.floor(tonumber(h) + 0.5)
end

function Theme:GetSavedWindowSize(posKey)
    if not (posKey and ns.db) then return nil, nil end
    self:EnsureResolutionPositionsMigrated()
    local byRes = ns.db.windowPositionsByRes
    local bucket = type(byRes) == "table" and self:ResolveResolutionBucket(byRes, false) or nil
    local rec = type(bucket) == "table" and bucket[posKey] or nil
    if type(rec) == "table" and tonumber(rec.width) and tonumber(rec.height) then
        return tonumber(rec.width), tonumber(rec.height)
    end
    return nil, nil
end

function Theme:ClearSavedWindowPosition(posKey, clearSizeAlso)
    if not (posKey and ns.db) then return end
    self:EnsureResolutionPositionsMigrated()
    local byRes = ns.db.windowPositionsByRes
    if type(byRes) == "table" then
        local bucket, _, _ = self:ResolveResolutionBucket(byRes, false)
        if type(bucket) == "table" and type(bucket[posKey]) == "table" then
            if clearSizeAlso ~= false or (bucket[posKey].width == nil and bucket[posKey].height == nil) then
                bucket[posKey] = nil
            else
                bucket[posKey].dx = nil
                bucket[posKey].dy = nil
                bucket[posKey].anchor = nil
            end
        end
    end
    if type(ns.db.windowPositions) == "table" then
        ns.db.windowPositions[posKey] = nil
    end
end

function Theme:RegisterViewportListener(ownerKey, fn)
    if not ownerKey or type(fn) ~= "function" then return end
    self._viewportListeners = self._viewportListeners or {}
    self._viewportListeners[ownerKey] = fn
end

local function SaveWindowCenterOffset(win, posKey, opts)
    if not (win and posKey and ns.db) then return end
    if UIParent and win.GetParent and win:GetParent() ~= UIParent then return end
    local scale = GetRelativeScaleToUIParent(win)
    local cx, cy = win:GetCenter()
    local ux, uy
    if UIParent then
        ux, uy = UIParent:GetCenter()
    end
    local anchor = opts and opts.anchor or "CENTER"

    if anchor == "TOP" then
        local top = win:GetTop()
        local utop = UIParent and UIParent:GetTop()
        if cx and top and ux and utop and cx == cx and top == top then
            Theme:SetSavedWindowPosition(posKey, {
                anchor = "TOP",
                dx = math.floor((cx * scale - ux) + 0.5),
                dy = math.floor((top * scale - utop) + 0.5),
            })
        end
    else
        if cx and cy and ux and uy and cx == cx and cy == cy then
            Theme:SetSavedWindowPosition(posKey, {
                anchor = "CENTER",
                dx = math.floor((cx * scale - ux) + 0.5),
                dy = math.floor((cy * scale - uy) + 0.5),
            })
        end
    end
end

function Theme:RestoreWindowPosition(win, posKey, combatLock, opts)
    if not win or (win._scLocked and not (opts and opts.allowLockedRestore)) then
        return false
    end
    if UIParent and win.GetParent and win:GetParent() ~= UIParent then
        return false
    end
    if not (posKey and ns.db) then
        return false
    end
    local saved = self:GetSavedWindowPosition(posKey)
    if type(saved) ~= "table" or saved.dx == nil or saved.dy == nil then
        return false
    end
    if combatLock and InCombatLockdown and InCombatLockdown() then
        return false
    end
    local uw, uh
    if UIParent then
        uw, uh = UIParent:GetSize()
    end
    local ww, wh = win:GetSize()
    local scale = GetRelativeScaleToUIParent(win)
    local dx = tonumber(saved.dx)
    local dy = tonumber(saved.dy)
    if not (dx and dy and dx == dx and dy == dy) then
        return false
    end
    local anchor = saved.anchor or (opts and opts.anchor) or "CENTER"

    if anchor == "TOP" then
        if uw and ww and ww > 0 then
            local maxX = math.max(0, (uw - ww * scale) * 0.5)
            dx = math.max(-maxX, math.min(maxX, dx))
        end
        if uh and uh > 0 then
            dy = math.max(-uh + 40, math.min(0, dy))
        end
        win:ClearAllPoints()
        win:SetPoint("TOP", UIParent, "TOP", dx / scale, dy / scale)
        return true
    else
        if uw and uh and ww and wh and ww > 0 and wh > 0 then
            local maxX = math.max(0, (uw - ww * scale) * 0.5)
            local maxY = math.max(0, (uh - wh * scale) * 0.5)
            dx = math.max(-maxX, math.min(maxX, dx))
            dy = math.max(-maxY, math.min(maxY, dy))
        end
        win:ClearAllPoints()
        win:SetPoint("CENTER", UIParent, "CENTER", dx / scale, dy / scale)
        return true
    end
end

local function IsHandleAttachedToWindow(handle, win)
    if not (handle and win) then return false end
    if win.IsVisible and not win:IsVisible() then return false end
    if handle == win or handle._scDragWin == win then return true end
    local parent = handle.GetParent and handle:GetParent() or nil
    if not parent or (UIParent and parent == UIParent) then
        return true
    end
    local cur = parent
    for _ = 1, 10 do
        if cur == win then
            return true
        end
        if not cur or (UIParent and cur == UIParent) or (WorldFrame and cur == WorldFrame) then
            break
        end
        cur = cur.GetParent and cur:GetParent() or nil
    end
    return false
end

local function ShouldStartInstantDragOnMouseDown(obj)
    if not obj then return false end
    if obj._scHoveredHyperlink ~= nil then
        return false
    end
    if obj.GetObjectType and obj:GetObjectType() == "Button" and obj.GetScript and obj.GetScript(obj, "OnClick") then
        return false
    end
    return true
end

function Theme:AttachDragHandle(handle, win)
    if not (handle and handle.EnableMouse and handle.RegisterForDrag and win and win._scBeginDrag and win._scEndDrag) then
        return
    end
    if handle == win and win._scMovableHooked then
        return
    end
    handle._scDragWin = win
    if not win._scLocked then
        handle:EnableMouse(true)
    end
    handle:RegisterForDrag("LeftButton")
    if handle.HookScript and not handle._scHandleHooked then
        handle._scHandleHooked = true
        handle:HookScript("OnMouseDown", function(selfHandle, btn)
            if btn == "LeftButton" and IsHandleAttachedToWindow(selfHandle, win) and ShouldStartInstantDragOnMouseDown(selfHandle) then
                if win._scPrepareDrag then
                    win._scPrepareDrag()
                end
            end
        end)
        handle:HookScript("OnMouseUp", function(_, btn)
            if btn == "LeftButton" then
                if win._scDragging then
                    win._scEndDrag()
                elseif win._scDisarmDragWatch then
                    win._scDisarmDragWatch()
                end
            end
        end)
        handle:HookScript("OnDragStart", function(selfHandle)
            if selfHandle._scHoveredHyperlink == nil and IsHandleAttachedToWindow(selfHandle, win) then
                win._scBeginDrag(true)
            end
        end)
        handle:HookScript("OnDragStop", function() win._scEndDrag() end)
        handle:HookScript("OnHide", function()
            if win._scDragging then
                win._scEndDrag()
            end
        end)
    end
end

--- Make any SocialCentral frame/modal smoothly draggable across the entire screen with LibWindow-style position saving.
function Theme:MakeMovable(win, opts)
    if not win then return win end
    opts = opts or {}

    win:SetMovable(true)
    win:SetClampedToScreen(true)
    if win.SetDontSavePosition then
        pcall(win.SetDontSavePosition, win, true)
    end
    if win.SetUserPlaced then
        pcall(win.SetUserPlaced, win, false)
    end

    local function EndDrag()
        if win._scDragWatch then
            win._scDragWatch:SetScript("OnUpdate", nil)
            win._scDragWatch:Hide()
        end
        win._scDragState = nil
        if not win._scDragging then
            if win._scSizing then
                win._scSizing = false
                pcall(win.StopMovingOrSizing, win)
            end
            return
        end
        win._scDragging = false
        win._scJustDraggedAt = (GetTime and GetTime()) or 0
        if win.StopMovingOrSizing then
            pcall(win.StopMovingOrSizing, win)
        end
        if win.SetUserPlaced then
            pcall(win.SetUserPlaced, win, false)
        end
        SaveWindowCenterOffset(win, opts.key, opts)
        if opts.key and UIParent and win.GetParent and win:GetParent() == UIParent then
            Theme:RestoreWindowPosition(win, opts.key, opts.combatLock, opts)
        end
        if type(opts.onStop) == "function" then
            pcall(opts.onStop, win)
        end
    end

    local function EnsureDragWatch()
        if not win._scDragWatch then
            -- Anchor a 1x1 watchdog directly to UIParent so win:ClearAllPoints() or 0x0 culling never stops OnUpdate in 16001.
            local dw = CreateFrame("Frame", nil, UIParent or win)
            dw:SetSize(1, 1)
            dw:SetPoint("TOPLEFT", UIParent or win, "TOPLEFT", 0, 0)
            if dw.SetFrameStrata then
                dw:SetFrameStrata("LOW")
            end
            dw:Hide()
            win._scDragWatch = dw
        end
        return win._scDragWatch
    end

    local function DisarmDragWatch()
        if not win._scDragging and win._scDragWatch then
            win._scDragWatch:SetScript("OnUpdate", nil)
            win._scDragWatch:Hide()
        end
    end

    local function PrepareDragOnMouseDown()
        if not CanDragWindow(win, opts) then
            return
        end
        win:SetMovable(true)
        win:SetClampedToScreen(true)
    end

    local function BeginDrag(fromDragStart)
        if fromDragStart == nil then
            fromDragStart = true
        end
        if win._scDragging then
            return
        end
        if not CanDragWindow(win, opts) then
            return
        end
        win:SetMovable(true)
        win:SetClampedToScreen(true)
        local nPts = (win.GetNumPoints and win:GetNumPoints()) or 0
        local winScale = (win.GetEffectiveScale and win:GetEffectiveScale()) or 1
        if not (winScale and winScale > 0) then
            winScale = 1
        end
        local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if not (uiScale and uiScale > 0) then
            uiScale = 1
        end
        local relScale = winScale / uiScale
        local anchor = (opts and opts.anchor == "TOP") and "TOP" or "CENTER"
        local cx, cy = win:GetCenter()
        local ux, uy
        if UIParent then
            ux, uy = UIParent:GetCenter()
        end
        local startOffX, startOffY = 0, 0
        if anchor == "TOP" then
            local top = win:GetTop()
            local utop = UIParent and UIParent:GetTop()
            if cx and top and ux and utop and cx == cx and top == top then
                startOffX = cx - (ux / relScale)
                startOffY = top - (utop / relScale)
            end
        else
            if cx and cy and ux and uy and cx == cx and cy == cy then
                startOffX = cx - (ux / relScale)
                startOffY = cy - (uy / relScale)
            end
        end
        -- Only normalize multi-point/unanchored frames; leave single-anchor windows untouched for native StartMoving() (like chatButton).
        if (nPts == 0 or nPts > 1) and UIParent and win.GetParent and win:GetParent() == UIParent then
            win:ClearAllPoints()
            win:SetPoint(anchor, UIParent, anchor, startOffX, startOffY)
        end
        if not (opts.combatLock and InCombatLockdown and InCombatLockdown()) and win.Raise then
            pcall(win.Raise, win)
        end
        if type(opts.onStart) == "function" then
            pcall(opts.onStart, win)
        end
        -- Use WoW's native StartMoving() directly from OnDragStart (identical to SocialCentralChatShortcutButton),
        -- never interrupting it with StopMovingOrSizing() in OnUpdate while dragging.
        local usedNativeMove = false
        if win.StartMoving then
            usedNativeMove = (pcall(win.StartMoving, win) == true)
        end
        local rawX, rawY
        if GetCursorPosition then
            rawX, rawY = GetCursorPosition()
        end
        local uw, uh
        if UIParent then
            uw, uh = UIParent:GetSize()
        end
        local ww, wh = win:GetSize()
        local minOffX, maxOffX, minOffY, maxOffY
        if uw and ww and ww > 0 then
            local limX = math.max(0, (uw - ww * relScale) * 0.5 / relScale)
            minOffX, maxOffX = -limX, limX
        end
        if anchor == "TOP" then
            if uh and uh > 0 then
                minOffY = (-uh + 40) / relScale
                maxOffY = 0
            end
        elseif uh and wh and wh > 0 then
            local limY = math.max(0, (uh - wh * relScale) * 0.5 / relScale)
            minOffY, maxOffY = -limY, limY
        end
        win._scDragState = {
            anchor = anchor,
            startedAt = (GetTime and GetTime()) or 0,
            startRawX = rawX or 0,
            startRawY = rawY or 0,
            lastRawX = rawX or 0,
            lastRawY = rawY or 0,
            startOffX = startOffX,
            startOffY = startOffY,
            winScale = winScale,
            minOffX = minOffX,
            maxOffX = maxOffX,
            minOffY = minOffY,
            maxOffY = maxOffY,
            usedNativeMove = usedNativeMove,
        }
        win._scDragging = true
        local dw = EnsureDragWatch()
        dw:Show()
        dw:SetScript("OnUpdate", function()
            if not win._scDragging or not win:IsVisible() then
                EndDrag()
                return
            end
            local ds = win._scDragState
            if not ds then
                EndDrag()
                return
            end
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") and ((GetTime and GetTime() or 0) - (ds.startedAt or 0)) > 0.08 then
                EndDrag()
                return
            end
            if ds.usedNativeMove then
                return
            end
            local curX, curY
            if GetCursorPosition then
                curX, curY = GetCursorPosition()
            end
            if not (curX and curY and curX == curX and curY == curY) then
                return
            end
            if curX == ds.lastRawX and curY == ds.lastRawY then
                return
            end
            ds.lastRawX = curX
            ds.lastRawY = curY
            local newX = ds.startOffX + ((curX - ds.startRawX) / ds.winScale)
            local newY = ds.startOffY + ((curY - ds.startRawY) / ds.winScale)
            if ds.minOffX and ds.maxOffX then
                newX = math.max(ds.minOffX, math.min(ds.maxOffX, newX))
            end
            if ds.minOffY and ds.maxOffY then
                newY = math.max(ds.minOffY, math.min(ds.maxOffY, newY))
            end
            if UIParent and win.GetParent and win:GetParent() == UIParent then
                win:ClearAllPoints()
                win:SetPoint(ds.anchor, UIParent, ds.anchor, newX, newY)
            end
        end)
    end

    win._scCombatLock = opts.combatLock and true or false
    win._scBeginDrag = BeginDrag
    win._scEndDrag = EndDrag
    win._scPrepareDrag = PrepareDragOnMouseDown
    win._scDisarmDragWatch = DisarmDragWatch
    win._scSavePosition = function()
        SaveWindowCenterOffset(win, opts.key, opts)
    end

    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    if not win._scMovableHooked then
        win._scMovableHooked = true
        win:HookScript("OnMouseDown", function(f, btn)
            if btn ~= "LeftButton" then return end
            if ShouldStartInstantDragOnMouseDown(f) then
                PrepareDragOnMouseDown()
            end
        end)
        win:HookScript("OnMouseUp", function(_, btn)
            if btn == "LeftButton" then
                if win._scDragging then
                    EndDrag()
                else
                    DisarmDragWatch()
                end
            end
        end)
        win:HookScript("OnDragStart", function()
            BeginDrag(true)
        end)
        win:HookScript("OnDragStop", EndDrag)
        win:HookScript("OnHide", EndDrag)
        win:HookScript("OnShow", function(f)
            if opts.key and not opts.skipAutoRestore then
                Theme:RestoreWindowPosition(f, opts.key, opts.combatLock, opts)
            end
        end)
    end

    if type(opts.handles) == "table" then
        for _, h in ipairs(opts.handles) do
            self:AttachDragHandle(h, win)
        end
    end

    if opts.key then
        self:RestoreWindowPosition(win, opts.key, opts.combatLock, opts)
        movableRegistry[opts.key] = {
            win = win,
            combatLock = opts.combatLock,
            onReset = opts.onReset,
            opts = opts,
            skipAutoRestore = opts.skipAutoRestore == true,
        }
    end
    return win
end

function Theme:ResetWindowPosition(key, silent)
    if InCombatLockdown and InCombatLockdown() then
        ns:Print(L["In Combat"])
        return false
    end
    if not key or key == "" then return false end
    if ns.db then
        self:ClearSavedWindowPosition(key, true)
        if key == "main" and type(ns.db.window) == "table" then
            ns.db.window.point = nil
            ns.db.window.relativePoint = nil
            ns.db.window.x = nil
            ns.db.window.y = nil
            ns.db.window.width = nil
            ns.db.window.height = nil
        end
    end
    local entry = movableRegistry[key]
    if entry and entry.win then
        local w = entry.win
        w:ClearAllPoints()
        w:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        if type(entry.onReset) == "function" then
            pcall(entry.onReset, w)
        end
    end
    if not silent then
        ns:Print(L["Position reset to default."])
    end
    return true
end

function Theme:ResetAllWindowPositions()
    if InCombatLockdown and InCombatLockdown() then
        ns:Print(L["In Combat"])
        return false
    end
    if ns.db then
        self:EnsureResolutionPositionsMigrated()
        local curKey = self:GetScreenProfileKey()
        if type(ns.db.windowPositionsByRes) == "table" then
            ns.db.windowPositionsByRes[curKey] = {}
        end
        ns.db.windowPositions = {}
        if type(ns.db.settings) == "table" then
            ns.db.settings.chatButtonCustomPos = nil
            if type(ns.db.settings.chatButtonPositionsByRes) == "table" then
                ns.db.settings.chatButtonPositionsByRes[curKey] = nil
            end
        end
        if type(ns.db.window) == "table" then
            ns.db.window.point = nil
            ns.db.window.relativePoint = nil
            ns.db.window.x = nil
            ns.db.window.y = nil
            ns.db.window.width = nil
            ns.db.window.height = nil
        end
        if ns.db.settings and type(ns.db.settings.minimap) == "table" then
            if type(ns.db.settings.minimap.anglesByRes) == "table" then
                ns.db.settings.minimap.anglesByRes[curKey] = nil
            end
            if type(ns.db.settings.minimap.anglesByRes) ~= "table" or next(ns.db.settings.minimap.anglesByRes) == nil then
                ns.db.settings.minimap.angle = 215
            end
        end
    end
    for key in pairs(movableRegistry) do
        self:ResetWindowPosition(key, true)
    end
    if ns.MinimapPreview and ns.MinimapPreview.ResetPosition then
        pcall(ns.MinimapPreview.ResetPosition, ns.MinimapPreview, true)
    end
    if ns.Minimap and ns.Minimap.Update then
        pcall(ns.Minimap.Update, ns.Minimap)
    end
    ns:Print(L["All window positions reset to center."])
    return true
end

function Theme:HandleViewportChanged()
    local curKey = self:GetScreenProfileKey()
    for key, entry in pairs(movableRegistry) do
        if type(entry) == "table" and entry.win and not entry.skipAutoRestore then
            local win = entry.win
            if not (win.GetParent and UIParent and win:GetParent() ~= UIParent) then
                local ok = self:RestoreWindowPosition(win, key, entry.combatLock, entry.opts)
                if not ok then
                    if not (entry.combatLock and InCombatLockdown and InCombatLockdown()) then
                        if type(entry.onReset) == "function" then
                            pcall(entry.onReset, win)
                        else
                            win:ClearAllPoints()
                            win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                        end
                    end
                end
            end
        end
    end
    if type(self._viewportListeners) == "table" then
        for _, fn in pairs(self._viewportListeners) do
            pcall(fn, curKey)
        end
    end
end

function Theme:QueueViewportChanged()
    if self._viewportTimerPending then return end
    self._viewportTimerPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.08, function()
            Theme._viewportTimerPending = false
            Theme:HandleViewportChanged()
        end)
    else
        self._viewportTimerPending = false
        self:HandleViewportChanged()
    end
end

--- Configure any shared modal/popup to sit above all native & World Map hosts with a 100% opaque backing.
function Theme:PrepareTopOverlayModal(m, minLevel, opts)
    if not m then return end
    if not self._overlayModals then
        self._overlayModals = setmetatable({}, { __mode = "k" })
    end
    self._overlayModals[m] = true
    if m.GetParent and m:GetParent() ~= UIParent then
        m:SetParent(UIParent)
    end
    local mapShown = _G.WorldMapFrame and _G.WorldMapFrame.IsShown and _G.WorldMapFrame:IsShown()
    local targetLevel = mapShown and math.max(minLevel or 850, 2750) or math.max(minLevel or 850, 840)
    local stackAbove = (type(opts) == "table" and opts.aboveShownModals == true) or (helpPopup ~= nil and m == helpPopup)
    if stackAbove then
        local maxOther = 0
        for otherM in pairs(self._overlayModals) do
            if otherM and otherM ~= m and otherM.IsShown and otherM:IsShown()
                and otherM.GetFrameStrata and otherM:GetFrameStrata() == "FULLSCREEN_DIALOG"
                and otherM.GetFrameLevel
            then
                local okLvl, oLvl = pcall(otherM.GetFrameLevel, otherM)
                if okLvl and type(oLvl) == "number" and oLvl > maxOther then
                    maxOther = oLvl
                end
            end
        end
        if maxOther > 0 then
            targetLevel = math.max(targetLevel, maxOther + 35)
        end
        targetLevel = math.min(9350, targetLevel)
    else
        targetLevel = math.min(9200, targetLevel)
    end
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(targetLevel)
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
        local pal = self:GetPalette()
        local wBg = (pal and pal.windowBg) or { 0.08, 0.075, 0.07, 1.0 }
        m._solidOpaqueBg:SetVertexColor(wBg[1], wBg[2], wBg[3], 1.0)
        m._solidOpaqueBg:Show()
    end
    for _, closeKey in ipairs({ "topCloseBtn", "closeBtn", "topClose" }) do
        local cb = m[closeKey]
        if cb and cb.SetFrameLevel then
            cb._scLevelOffset = 12
            cb:SetFrameLevel(targetLevel + 12)
        end
    end
    self:SyncSubtreeLayers(m, 8)
    if m.Raise then m:Raise() end
end

local CHROMIE_NPC_ID = 10667
local CHROMIE_DISPLAY_ID = 10008
local CHROMIE_FALLBACK_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_02"

local function CollectGuideTargetObjs(rawTarget, outList, seen)
    if not rawTarget then return end
    local rType = type(rawTarget)
    if rType == "function" then
        local ok, res = pcall(rawTarget)
        if ok and res then
            CollectGuideTargetObjs(res, outList, seen)
        end
        return
    end
    if rType ~= "table" then return end
    if rawTarget.GetLeft then
        if not seen[rawTarget] then
            seen[rawTarget] = true
            outList[#outList + 1] = rawTarget
        end
        return
    end
    for _, sub in ipairs(rawTarget) do
        CollectGuideTargetObjs(sub, outList, seen)
    end
end

local guideObjsScratch = {}
local guideSeenScratch = {}

local function ComputeGuideTargetsRect(rawTarget)
    wipe(guideObjsScratch)
    wipe(guideSeenScratch)
    CollectGuideTargetObjs(rawTarget, guideObjsScratch, guideSeenScratch)
    if #guideObjsScratch == 0 then return nil end

    local uiScale = (_G.UIParent and _G.UIParent.GetEffectiveScale and _G.UIParent:GetEffectiveScale()) or 1
    if not uiScale or uiScale <= 0 then uiScale = 1 end

    local minL, minB, maxR, maxT = nil, nil, nil, nil
    for i = 1, #guideObjsScratch do
        local obj = guideObjsScratch[i]
        local vis = (not obj.IsVisible) or obj:IsVisible()
        if vis and obj.GetLeft and obj.GetRight and obj.GetBottom and obj.GetTop then
            local l = obj:GetLeft()
            local r = obj:GetRight()
            local b = obj:GetBottom()
            local t = obj:GetTop()
            if l and r and b and t and r > l and t > b then
                local oScale = (obj.GetEffectiveScale and obj:GetEffectiveScale()) or uiScale
                local ratio = oScale / uiScale
                l, r, b, t = l * ratio, r * ratio, b * ratio, t * ratio
                if not minL or l < minL then minL = l end
                if not minB or b < minB then minB = b end
                if not maxR or r > maxR then maxR = r end
                if not maxT or t > maxT then maxT = t end
            end
        end
    end
    if not minL then return nil end
    return minL, minB, maxR, maxT
end

local function EnsureGuideSpotlight()
    if guideSpotlight then
        return guideSpotlight
    end
    local spot = CreateFrame("Frame", "SocialCentralNpcGuideSpotlight", UIParent)
    spot:Hide()
    spot:SetFrameStrata("FULLSCREEN_DIALOG")
    spot:SetFrameLevel(862)
    spot:EnableMouse(false)

    local fill = spot:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetTexture(WHITE8X8)
    fill:SetVertexColor(1.0, 0.82, 0.24, 0.11)
    spot.fill = fill

    local eTop = spot:CreateTexture(nil, "OVERLAY", nil, 6)
    eTop:SetPoint("TOPLEFT", 0, 0)
    eTop:SetPoint("TOPRIGHT", 0, 0)
    eTop:SetHeight(2)
    local eBot = spot:CreateTexture(nil, "OVERLAY", nil, 6)
    eBot:SetPoint("BOTTOMLEFT", 0, 0)
    eBot:SetPoint("BOTTOMRIGHT", 0, 0)
    eBot:SetHeight(2)
    local eLeft = spot:CreateTexture(nil, "OVERLAY", nil, 6)
    eLeft:SetPoint("TOPLEFT", 0, 0)
    eLeft:SetPoint("BOTTOMLEFT", 0, 0)
    eLeft:SetWidth(2)
    local eRight = spot:CreateTexture(nil, "OVERLAY", nil, 6)
    eRight:SetPoint("TOPRIGHT", 0, 0)
    eRight:SetPoint("BOTTOMRIGHT", 0, 0)
    eRight:SetWidth(2)
    spot.edges = { eTop, eBot, eLeft, eRight }

    local arrow = CreateFrame("Frame", nil, spot)
    arrow:SetSize(36, 36)
    arrow:EnableMouse(false)

    local clipBox = CreateFrame("Frame", nil, arrow)
    clipBox:SetSize(34, 18)
    if clipBox.SetClipsChildren then
        clipBox:SetClipsChildren(true)
    end
    clipBox:EnableMouse(false)

    local headBorder = clipBox:CreateTexture(nil, "ARTWORK", nil, 1)
    headBorder:SetSize(22, 22)
    headBorder:SetTexture(WHITE8X8)
    headBorder:SetRotation(math.pi * 0.25)
    headBorder:SetVertexColor(0.14, 0.12, 0.10, 1.0)

    local headShoulder = clipBox:CreateTexture(nil, "ARTWORK", nil, 2)
    headShoulder:SetTexture(WHITE8X8)
    headShoulder:SetVertexColor(0.14, 0.12, 0.10, 1.0)

    local headFill = clipBox:CreateTexture(nil, "ARTWORK", nil, 3)
    headFill:SetSize(18, 18)
    headFill:SetTexture(WHITE8X8)
    headFill:SetRotation(math.pi * 0.25)
    headFill:SetVertexColor(0.995, 0.99, 0.975, 1.0)

    local shaftBorder = arrow:CreateTexture(nil, "ARTWORK", nil, 1)
    shaftBorder:SetTexture(WHITE8X8)
    shaftBorder:SetVertexColor(0.14, 0.12, 0.10, 1.0)

    local shaftFrame = CreateFrame("Frame", nil, arrow)
    shaftFrame:SetAllPoints(arrow)
    shaftFrame:SetFrameLevel((clipBox:GetFrameLevel() or 864) + 1)
    shaftFrame:EnableMouse(false)

    local shaftFill = shaftFrame:CreateTexture(nil, "ARTWORK", nil, 4)
    shaftFill:SetTexture(WHITE8X8)
    shaftFill:SetVertexColor(0.995, 0.99, 0.975, 1.0)

    function arrow:SetDirection(dir)
        if self._dir == dir then return end
        self._dir = dir
        clipBox:ClearAllPoints()
        headBorder:ClearAllPoints()
        headShoulder:ClearAllPoints()
        headFill:ClearAllPoints()
        shaftBorder:ClearAllPoints()
        shaftFill:ClearAllPoints()

        if dir == "DOWN" then
            clipBox:SetSize(34, 18)
            clipBox:SetPoint("BOTTOM", self, "BOTTOM", 0, 1)
            headBorder:SetPoint("CENTER", clipBox, "TOP", 0, 0)
            headShoulder:SetSize(31, 2.5)
            headShoulder:SetPoint("TOP", clipBox, "TOP", 0, 0)
            headFill:SetPoint("CENTER", clipBox, "TOP", 0, 1)
            shaftBorder:SetSize(12, 14)
            shaftBorder:SetPoint("BOTTOM", clipBox, "TOP", 0, -2)
            shaftFill:SetSize(7, 13)
            shaftFill:SetPoint("BOTTOM", clipBox, "TOP", 0, -3.5)
        elseif dir == "UP" then
            clipBox:SetSize(34, 18)
            clipBox:SetPoint("TOP", self, "TOP", 0, -1)
            headBorder:SetPoint("CENTER", clipBox, "BOTTOM", 0, 0)
            headShoulder:SetSize(31, 2.5)
            headShoulder:SetPoint("BOTTOM", clipBox, "BOTTOM", 0, 0)
            headFill:SetPoint("CENTER", clipBox, "BOTTOM", 0, -1)
            shaftBorder:SetSize(12, 14)
            shaftBorder:SetPoint("TOP", clipBox, "BOTTOM", 0, 2)
            shaftFill:SetSize(7, 13)
            shaftFill:SetPoint("TOP", clipBox, "BOTTOM", 0, 3.5)
        elseif dir == "LEFT" then
            clipBox:SetSize(18, 34)
            clipBox:SetPoint("LEFT", self, "LEFT", 1, 0)
            headBorder:SetPoint("CENTER", clipBox, "RIGHT", 0, 0)
            headShoulder:SetSize(2.5, 31)
            headShoulder:SetPoint("RIGHT", clipBox, "RIGHT", 0, 0)
            headFill:SetPoint("CENTER", clipBox, "RIGHT", -1, 0)
            shaftBorder:SetSize(14, 12)
            shaftBorder:SetPoint("LEFT", clipBox, "RIGHT", -2, 0)
            shaftFill:SetSize(13, 7)
            shaftFill:SetPoint("LEFT", clipBox, "RIGHT", -3.5, 0)
        else -- RIGHT
            clipBox:SetSize(18, 34)
            clipBox:SetPoint("RIGHT", self, "RIGHT", -1, 0)
            headBorder:SetPoint("CENTER", clipBox, "LEFT", 0, 0)
            headShoulder:SetSize(2.5, 31)
            headShoulder:SetPoint("LEFT", clipBox, "LEFT", 0, 0)
            headFill:SetPoint("CENTER", clipBox, "LEFT", 1, 0)
            shaftBorder:SetSize(14, 12)
            shaftBorder:SetPoint("RIGHT", clipBox, "LEFT", 2, 0)
            shaftFill:SetSize(13, 7)
            shaftFill:SetPoint("RIGHT", clipBox, "LEFT", 3.5, 0)
        end
    end
    arrow:SetDirection("DOWN")
    spot.arrow = arrow

    guideSpotlight = spot
    return spot
end

local function SyncNpcGuideSpotlightAndDock(m, spec, stepSpec, nowT)
    local spot = EnsureGuideSpotlight()
    if not (m and m:IsShown() and stepSpec) then
        spot:Hide()
        return
    end
    local rawTarget = (stepSpec.target ~= nil) and stepSpec.target or (spec and spec.defaultTarget)
    local tl, tb, tr, tt = ComputeGuideTargetsRect(rawTarget)
    local uiW = (_G.UIParent and _G.UIParent.GetWidth and _G.UIParent:GetWidth()) or 1280
    local uiH = (_G.UIParent and _G.UIParent.GetHeight and _G.UIParent:GetHeight()) or 720
    local mw = m:GetWidth() or 516
    local mh = m:GetHeight() or 190

    if not tl then
        spot:Hide()
        spot._lastRectSig = nil
        if not m._userDragged and m._lastDockSig ~= "center" then
            m._lastDockSig = "center"
            m:ClearAllPoints()
            m:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 60)
        end
        return
    end

    tl = math.max(4, tl)
    tb = math.max(4, tb)
    tr = math.min(uiW - 4, tr)
    tt = math.min(uiH - 4, tt)
    if tr <= tl or tt <= tb then
        spot:Hide()
        spot._lastRectSig = nil
        return
    end

    local spotLvl = math.max(862, (m.GetFrameLevel and m:GetFrameLevel() or 865) - 3)
    local rectSig = string.format("%.1f:%.1f:%.1f:%.1f:%d", tl, tb, tr, tt, spotLvl)
    if spot._lastRectSig ~= rectSig or not spot:IsShown() then
        spot._lastRectSig = rectSig
        spot:ClearAllPoints()
        spot:SetFrameLevel(spotLvl)
        spot:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", tl - 4, tb - 4)
        spot:SetPoint("TOPRIGHT", _G.UIParent, "BOTTOMLEFT", tr + 4, tt + 4)
    end

    local t = nowT or (GetTime and GetTime()) or 0
    local wave = 0.5 + 0.5 * math.sin(t * 5.8)
    local edgeA = 0.72 + 0.28 * wave
    for _, ed in ipairs(spot.edges) do
        ed:SetColorTexture(1.0, 0.84, 0.26, edgeA)
    end
    spot.fill:SetVertexColor(1.0, 0.84, 0.26, 0.07 + 0.09 * wave)
    if not spot:IsShown() then
        spot:Show()
    end

    local canAbove = (tt + 26 + mh) <= (uiH - 12)
    local canBelow = (tb - 26 - mh) >= 12
    local canRight = (tr + 26 + mw) <= (uiW - 12)
    local canLeft = (tl - 26 - mw) >= 12

    local bob = math.sin(t * 6.0) * 4
    local arrow = spot.arrow
    local dx, dy = nil, nil
    local cx = (tl + tr) * 0.5
    local cy = (tb + tt) * 0.5
    local wantDir

    if canAbove then
        wantDir = "DOWN"
        if arrow._lastDir ~= wantDir then
            arrow._lastDir = wantDir
            arrow:SetDirection(wantDir)
        end
        arrow:ClearAllPoints()
        arrow:SetPoint("BOTTOM", spot, "TOP", 0, 2 + bob)
        dx = math.max(12, math.min(uiW - mw - 12, cx - mw * 0.5))
        dy = math.max(12, math.min(uiH - mh - 12, tt + 40))
    elseif canRight then
        wantDir = "LEFT"
        if arrow._lastDir ~= wantDir then
            arrow._lastDir = wantDir
            arrow:SetDirection(wantDir)
        end
        arrow:ClearAllPoints()
        arrow:SetPoint("LEFT", spot, "RIGHT", 2 + bob, 0)
        dx = math.max(12, math.min(uiW - mw - 12, tr + 40))
        dy = math.max(12, math.min(uiH - mh - 12, cy - mh * 0.5))
    elseif canLeft then
        wantDir = "RIGHT"
        if arrow._lastDir ~= wantDir then
            arrow._lastDir = wantDir
            arrow:SetDirection(wantDir)
        end
        arrow:ClearAllPoints()
        arrow:SetPoint("RIGHT", spot, "LEFT", -2 - bob, 0)
        dx = math.max(12, math.min(uiW - mw - 12, tl - mw - 40))
        dy = math.max(12, math.min(uiH - mh - 12, cy - mh * 0.5))
    elseif canBelow then
        wantDir = "UP"
        if arrow._lastDir ~= wantDir then
            arrow._lastDir = wantDir
            arrow:SetDirection(wantDir)
        end
        arrow:ClearAllPoints()
        arrow:SetPoint("TOP", spot, "BOTTOM", 0, -2 - bob)
        dx = math.max(12, math.min(uiW - mw - 12, cx - mw * 0.5))
        dy = math.max(12, math.min(uiH - mh - 12, tb - mh - 40))
    else
        wantDir = "DOWN"
        if arrow._lastDir ~= wantDir then
            arrow._lastDir = wantDir
            arrow:SetDirection(wantDir)
        end
        arrow:ClearAllPoints()
        arrow:SetPoint("BOTTOM", spot, "TOP", 0, 2 + bob)
        dx = math.max(12, math.min(uiW - mw - 12, cx - mw * 0.5))
        dy = math.max(12, math.min(uiH - mh - 12, uiH - mh - 16))
    end
    if not arrow:IsShown() then
        arrow:Show()
    end

    if not m._userDragged and dx and dy then
        local dockSig = string.format("%.1f:%.1f", dx, dy)
        if m._lastDockSig ~= dockSig then
            m._lastDockSig = dockSig
            m:ClearAllPoints()
            m:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", dx, dy)
        end
    end
end

local function TriggerNpcPortraitSpeech(m, animId)
    if not m then return end
    local now = (GetTime and GetTime()) or 0
    m._talkUntil = now + 4.2
    m._lastTalkAnimAt = now
    local mod = m.model
    if mod then
        if not mod._loadedOk and mod.SetDisplayInfo then
            pcall(mod.SetDisplayInfo, mod, CHROMIE_DISPLAY_ID)
        end
        if mod.SetAnimation then
            pcall(mod.SetAnimation, mod, animId or 60)
        end
    end
end

local function ResolveHelpTargetFrame(helpBtn, opts)
    if opts and opts.target ~= nil then
        return opts.target
    end
    if helpBtn then
        if helpBtn._scGuideTarget ~= nil then
            return helpBtn._scGuideTarget
        end
        if helpBtn.GetPoint then
            local _, relTo = helpBtn:GetPoint(1)
            local parent = helpBtn:GetParent()
            if relTo and relTo ~= UIParent and relTo ~= parent then
                if relTo._scGuideGroup then
                    return relTo._scGuideGroup
                end
                return relTo
            end
        end
    end
    return nil
end

local function IsNpcGuideInCombat()
    return (InCombatLockdown and InCombatLockdown() == true)
        or (UnitAffectingCombat and UnitAffectingCombat("player") == true)
        or false
end

local function AdaptBubbleTextForWhiteBg(text)
    if type(text) ~= "string" or text == "" then
        return text
    end
    return (text:gsub("|cff(%x%x%x%x%x%x)", function(hex)
        local r = tonumber(hex:sub(1, 2), 16) or 0
        local g = tonumber(hex:sub(3, 4), 16) or 0
        local b = tonumber(hex:sub(5, 6), 16) or 0
        local lum = (0.299 * r) + (0.587 * g) + (0.114 * b)
        if lum > 125 then
            local factor = 0.42
            return string.format("|cff%02x%02x%02x", math.floor(r * factor), math.floor(g * factor), math.floor(b * factor))
        end
        return "|cff" .. hex
    end))
end

local function ApplyCircleMaskToTexture(parent, tex)
    if not (parent and parent.CreateMaskTexture and tex and tex.AddMaskTexture) then
        return
    end
    local mask = parent:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
end

local function CreateRoundedBubbleLayer(parent, layerName, subLevel, radius, inset, r, g, b, a)
    local effR = math.max(4, radius - inset)
    local diam = effR * 2
    local corners = {
        { "TOPLEFT", "TOPLEFT", inset, -inset },
        { "TOPRIGHT", "TOPRIGHT", -inset, -inset },
        { "BOTTOMLEFT", "BOTTOMLEFT", inset, inset },
        { "BOTTOMRIGHT", "BOTTOMRIGHT", -inset, inset },
    }
    for _, c in ipairs(corners) do
        local tex = parent:CreateTexture(nil, layerName, nil, subLevel)
        tex:SetSize(diam, diam)
        tex:SetPoint(c[1], parent, c[2], c[3], c[4])
        tex:SetTexture(WHITE8X8)
        tex:SetVertexColor(r, g, b, a)
        ApplyCircleMaskToTexture(parent, tex)
    end
    local hBar = parent:CreateTexture(nil, layerName, nil, subLevel)
    hBar:SetPoint("TOPLEFT", parent, "TOPLEFT", inset + effR, -inset)
    hBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(inset + effR), inset)
    hBar:SetTexture(WHITE8X8)
    hBar:SetVertexColor(r, g, b, a)

    local vBar = parent:CreateTexture(nil, layerName, nil, subLevel)
    vBar:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -(inset + effR))
    vBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset + effR)
    vBar:SetTexture(WHITE8X8)
    vBar:SetVertexColor(r, g, b, a)
end

local function EnsureNpcGuidePopup()
    if helpPopup then
        return helpPopup
    end

    local m = CreateFrame("Frame", "SocialCentralHelpPopup", UIParent)
    m:Hide()
    m:SetSize(520, 174)
    m:SetPoint("CENTER")
    Theme:PrepareTopOverlayModal(m, 865)
    m:EnableMouse(false)
    if m._solidOpaqueBg then m._solidOpaqueBg:Hide() end
    table.insert(UISpecialFrames, "SocialCentralHelpPopup")

    -- Floating circular medallion portrait for Chromie (no outer dark backdrop box)
    local portBox = CreateFrame("Button", nil, m)
    portBox:SetSize(96, 96)
    portBox:SetPoint("TOPLEFT", m, "TOPLEFT", 4, -8)
    portBox:EnableMouse(true)
    portBox:RegisterForClicks("LeftButtonUp")
    m.portBox = portBox

    local portGoldRing = portBox:CreateTexture(nil, "BACKGROUND", nil, 1)
    portGoldRing:SetSize(94, 94)
    portGoldRing:SetPoint("CENTER", portBox, "CENTER", 0, 0)
    portGoldRing:SetTexture(WHITE8X8)
    portGoldRing:SetVertexColor(0.88, 0.70, 0.24, 1.0)
    ApplyCircleMaskToTexture(portBox, portGoldRing)

    local portDarkRing = portBox:CreateTexture(nil, "BACKGROUND", nil, 2)
    portDarkRing:SetSize(88, 88)
    portDarkRing:SetPoint("CENTER", portBox, "CENTER", 0, 0)
    portDarkRing:SetTexture(WHITE8X8)
    portDarkRing:SetVertexColor(0.15, 0.13, 0.11, 1.0)
    ApplyCircleMaskToTexture(portBox, portDarkRing)

    local portInnerBg = portBox:CreateTexture(nil, "ARTWORK", nil, 1)
    portInnerBg:SetSize(84, 84)
    portInnerBg:SetPoint("CENTER", portBox, "CENTER", 0, 0)
    portInnerBg:SetTexture(WHITE8X8)
    portInnerBg:SetVertexColor(0.11, 0.10, 0.09, 1.0)
    ApplyCircleMaskToTexture(portBox, portInnerBg)

    local portRing = portBox:CreateTexture(nil, "OVERLAY", nil, 6)
    portRing:SetPoint("CENTER", portBox, "CENTER", 0, 0)
    if Theme:HasAtlas("Artifacts-PerkRing-Final") then
        portRing:SetSize(108, 108)
        portRing:SetAtlas("Artifacts-PerkRing-Final", false)
        portRing:SetVertexColor(0.95, 0.84, 0.52, 0.95)
    elseif Theme:HasAtlas("common-ring-gold") then
        portRing:SetSize(102, 102)
        portRing:SetAtlas("common-ring-gold", false)
        portRing:SetVertexColor(0.98, 0.88, 0.56, 0.95)
    else
        portRing:SetAlpha(0)
    end
    m.portRing = portRing

    local fallbackIco = portBox:CreateTexture(nil, "ARTWORK", nil, 2)
    fallbackIco:SetSize(74, 74)
    fallbackIco:SetPoint("CENTER", portBox, "CENTER", 0, 0)
    fallbackIco:SetTexture(CHROMIE_FALLBACK_ICON)
    fallbackIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ApplyCircleMaskToTexture(portBox, fallbackIco)
    m.fallbackIco = fallbackIco

    local model = CreateFrame("PlayerModel", nil, portBox)
    model:SetSize(82, 82)
    model:SetPoint("CENTER", portBox, "CENTER", 0, 0)
    model._scSkipLayerSync = true
    model._loadedOk = false
    if model.EnableMouse then model:EnableMouse(false) end
    local function ApplyChromieCamera(selfMod)
        if selfMod.SetPortraitZoom then pcall(selfMod.SetPortraitZoom, selfMod, 0.66) end
        if selfMod.SetCamDistanceScale then pcall(selfMod.SetCamDistanceScale, selfMod, 1.06) end
        if selfMod.SetPosition then pcall(selfMod.SetPosition, selfMod, 0, 0, -0.04) end
        if selfMod.SetFacing then pcall(selfMod.SetFacing, selfMod, 0.28) end
        if selfMod.RefreshCamera then pcall(selfMod.RefreshCamera, selfMod) end
    end
    model:SetScript("OnModelLoaded", function(selfMod)
        selfMod._loadedOk = true
        fallbackIco:Hide()
        ApplyChromieCamera(selfMod)
        if selfMod.SetAnimation then pcall(selfMod.SetAnimation, selfMod, 60) end
    end)
    m.model = model

    portBox:SetScript("OnClick", function()
        TriggerNpcPortraitSpeech(m, 67)
    end)
    portBox:SetScript("OnEnter", function(selfPort)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfPort, "ANCHOR_TOP")
        GameTooltip:SetText(L["Chromie"], 1.0, 0.85, 0.28)
        GameTooltip:AddLine(L["SocialCentral Interactive Guide"], 0.85, 0.90, 0.96, true)
        GameTooltip:AddLine(L["Click portrait to replay greeting."], 0.58, 0.72, 0.88, true)
        GameTooltip:Show()
    end)
    portBox:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local npcName = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    npcName:SetText("|cffffd24d" .. L["Chromie"] .. "|r")
    npcName:Hide()
    m.npcName = npcName

    local npcRole = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    npcRole:SetText(L["WoW Guide"])
    npcRole:Hide()
    m.npcRole = npcRole

    -- Super-rounded warm aged-parchment Speech Bubble with seamless parchment grain & sepia tail toward Chromie
    local bubble = CreateFrame("Frame", nil, m)
    bubble:SetPoint("TOPLEFT", portBox, "TOPRIGHT", 22, 4)
    bubble:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -4, 4)
    bubble:EnableMouse(true)
    CreateRoundedBubbleLayer(bubble, "BACKGROUND", 0, 20, 0, 0.25, 0.17, 0.08, 1.0)
    CreateRoundedBubbleLayer(bubble, "BACKGROUND", 2, 20, 2.5, 0.905, 0.835, 0.690, 1.0)
    local paperGrain = bubble:CreateTexture(nil, "BACKGROUND", nil, 3)
    paperGrain:SetPoint("TOPLEFT", bubble, "TOPLEFT", 14, -12)
    paperGrain:SetPoint("BOTTOMRIGHT", bubble, "BOTTOMRIGHT", -14, 12)
    paperGrain:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\parchment.tga")
    paperGrain:SetVertexColor(0.96, 0.91, 0.82, 0.72)
    CreateRoundedBubbleLayer(bubble, "BACKGROUND", 4, 17, 5.5, 0.930, 0.865, 0.730, 0.28)
    for lineIdx = 1, 7 do
        local ruled = bubble:CreateTexture(nil, "BACKGROUND", nil, 5)
        ruled:SetHeight(1)
        ruled:SetPoint("TOPLEFT", bubble, "TOPLEFT", 20, -(26 + lineIdx * 24))
        ruled:SetPoint("TOPRIGHT", bubble, "TOPRIGHT", -20, -(26 + lineIdx * 24))
        ruled:SetTexture(WHITE8X8)
        ruled:SetVertexColor(0.68, 0.57, 0.40, 0.14)
    end
    m.bubble = bubble

    local tailBorder = bubble:CreateTexture(nil, "ARTWORK", nil, 1)
    tailBorder:SetSize(20, 20)
    tailBorder:SetPoint("CENTER", bubble, "TOPLEFT", 0, -52)
    tailBorder:SetTexture(WHITE8X8)
    tailBorder:SetRotation(math.pi * 0.25)
    m.tailBorder = tailBorder

    local tailFill = bubble:CreateTexture(nil, "ARTWORK", nil, 2)
    tailFill:SetSize(16, 16)
    tailFill:SetPoint("CENTER", bubble, "TOPLEFT", 2, -52)
    tailFill:SetTexture(WHITE8X8)
    tailFill:SetRotation(math.pi * 0.25)
    m.tailFill = tailFill

    local tailPatch = bubble:CreateTexture(nil, "ARTWORK", nil, 3)
    tailPatch:SetSize(14, 24)
    tailPatch:SetPoint("LEFT", bubble, "TOPLEFT", 2.5, -52)
    tailPatch:SetTexture(WHITE8X8)
    m.tailPatch = tailPatch

    local topCloseBtn = Theme:CreateButton(bubble, 20, 18, "X", "default")
    topCloseBtn:SetPoint("TOPRIGHT", -12, -10)
    topCloseBtn:SetScript("OnClick", function() m:Hide() end)
    m.topCloseBtn = topCloseBtn

    local stepPill = bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stepPill:SetPoint("RIGHT", topCloseBtn, "LEFT", -8, 0)
    stepPill:SetJustifyH("RIGHT")
    stepPill:SetShadowColor(0, 0, 0, 0)
    stepPill:SetTextColor(0.36, 0.42, 0.50)
    m.stepPill = stepPill

    m.title = bubble:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    m.title:SetPoint("TOPLEFT", 18, -12)
    m.title:SetPoint("RIGHT", stepPill, "LEFT", -6, 0)
    m.title:SetJustifyH("LEFT")
    m.title:SetWordWrap(false)
    m.title:SetShadowColor(0, 0, 0, 0)

    local tagFs = bubble:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tagFs:SetPoint("TOPLEFT", 18, -32)
    tagFs:SetPoint("TOPRIGHT", -18, -32)
    tagFs:SetJustifyH("LEFT")
    tagFs:SetWordWrap(false)
    tagFs:SetShadowColor(0, 0, 0, 0)
    m.tagFs = tagFs

    m.body = bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    m.body:SetPoint("TOPLEFT", tagFs, "BOTTOMLEFT", 0, -5)
    m.body:SetPoint("RIGHT", bubble, "RIGHT", -18, 0)
    m.body:SetWidth(356)
    m.body:SetJustifyH("LEFT")
    m.body:SetJustifyV("TOP")
    m.body:SetWordWrap(true)
    m.body:SetSpacing(3)
    m.body:SetShadowColor(0, 0, 0, 0)

    local bubbleDivider = bubble:CreateTexture(nil, "ARTWORK", nil, 1)
    bubbleDivider:SetHeight(1)
    bubbleDivider:SetPoint("BOTTOMLEFT", 16, 40)
    bubbleDivider:SetPoint("BOTTOMRIGHT", -16, 40)
    bubbleDivider:SetTexture(WHITE8X8)
    bubbleDivider:SetVertexColor(0.86, 0.85, 0.81, 1.0)
    m.bubbleDivider = bubbleDivider

    m.skipBtn = Theme:CreateButton(bubble, 74, 22, L["Close"], "default")
    m.skipBtn:SetPoint("BOTTOMLEFT", 16, 12)
    m.skipBtn:SetScript("OnClick", function()
        local spec = m._guideSpec
        if spec and type(spec.onSkip) == "function" then
            pcall(spec.onSkip)
        end
        m:Hide()
    end)

    m.skipAllBtn = Theme:CreateButton(bubble, 152, 22, L["Not now (all areas)"], "default")
    m.skipAllBtn:SetPoint("LEFT", m.skipBtn, "RIGHT", 6, 0)
    m.skipAllBtn:Hide()
    m.skipAllBtn:SetScript("OnClick", function()
        local spec = m._guideSpec
        if spec and type(spec.onSkipAll) == "function" then
            pcall(spec.onSkipAll)
        end
        m:Hide()
    end)

    m.nextBtn = Theme:CreateButton(bubble, 114, 22, L["Next"], "primary")
    m.nextBtn:SetPoint("BOTTOMRIGHT", -16, 12)

    m.backBtn = Theme:CreateButton(bubble, 78, 22, L["Back"], "default")
    m.backBtn:SetPoint("RIGHT", m.nextBtn, "LEFT", -6, 0)
    m.closeBtn = m.nextBtn

    Theme:MakeMovable(m, {
        key = "helpPopup",
        skipAutoRestore = true,
        handles = { portBox, bubble },
        onStop = function() m._userDragged = true end,
    })

    local function RenderCurrentStep()
        local spec = m._guideSpec
        local steps = spec and spec.steps
        if not (steps and #steps > 0) then return end
        local total = #steps
        local idx = math.max(1, math.min(total, tonumber(m._guideStep) or 1))
        m._guideStep = idx
        local st = steps[idx]

        m.title:SetText(st.title or spec.title or L["Help"])
        m.title:ClearAllPoints()
        m.title:SetPoint("TOPLEFT", 18, -12)
        if total > 1 then
            m.stepPill:SetText(L["Step %d/%d"]:format(idx, total))
            m.stepPill:Show()
            m.title:SetPoint("RIGHT", m.stepPill, "LEFT", -6, 0)
        else
            m.stepPill:SetText("")
            m.stepPill:Hide()
            m.title:SetPoint("RIGHT", m.topCloseBtn, "LEFT", -6, 0)
        end

        if st.tag and st.tag ~= "" then
            m.tagFs:SetText(AdaptBubbleTextForWhiteBg(st.tag))
            m.tagFs:Show()
            m.body:ClearAllPoints()
            m.body:SetPoint("TOPLEFT", m.tagFs, "BOTTOMLEFT", 0, -5)
            m.body:SetPoint("RIGHT", m.bubble, "RIGHT", -18, 0)
        else
            m.tagFs:SetText("")
            m.tagFs:Hide()
            m.body:ClearAllPoints()
            m.body:SetPoint("TOPLEFT", m.bubble, "TOPLEFT", 18, -34)
            m.body:SetPoint("RIGHT", m.bubble, "RIGHT", -18, 0)
        end
        local hasSkip = (idx < total) or (spec.showSkipOnLast == true) or (type(st.skipLabel or spec.skipLabel) == "string")
        local hasSkipAll = (type(spec.skipAllLabel) == "string" and spec.skipAllLabel ~= "")
        m.backBtn:SetShown(idx > 1)
        m.skipBtn:SetShown(hasSkip)
        m.skipAllBtn:SetShown(hasSkipAll and hasSkip)
        Theme:SetButtonText(m.skipBtn, st.skipLabel or spec.skipLabel or L["Close"])
        if hasSkipAll then
            Theme:SetButtonText(m.skipAllBtn, spec.skipAllLabel)
            Theme:AutoFitButton(m.skipAllBtn, 110, 16, 260)
        end
        if idx >= total then
            Theme:SetButtonText(m.nextBtn, spec.doneLabel or L["Got it!"])
        else
            Theme:SetButtonText(m.nextBtn, st.nextLabel or L["Next"])
        end
        local skipW = hasSkip and Theme:AutoFitButton(m.skipBtn, 64, 14, 150) or 0
        local skipAllW = (hasSkip and hasSkipAll) and (m.skipAllBtn:GetWidth() or 160) or 0
        local backW = (idx > 1) and Theme:AutoFitButton(m.backBtn, 64, 14, 130) or 0
        local nextW = Theme:AutoFitButton(m.nextBtn, 86, 16, 220)
        local leftGroupW = skipW + ((skipW > 0 and skipAllW > 0) and (6 + skipAllW) or 0)
        local rightGroupW = nextW + ((backW > 0) and (6 + backW) or 0)
        local neededBubbleW = math.max(396, leftGroupW + rightGroupW + 50)
        local popupW = math.max(520, math.min(720, neededBubbleW + 122))
        m:SetWidth(popupW)
        local bodyW = popupW - 164
        m.body:SetWidth(bodyW)

        local bodyStr = AdaptBubbleTextForWhiteBg(st.text or "")
        if type(m._combatResumeQuip) == "string" and m._combatResumeQuip ~= "" then
            bodyStr = "|cff7c2d12" .. m._combatResumeQuip .. "|r\n\n" .. bodyStr
        end
        m.body:SetText(bodyStr)
        local bodyH = math.ceil((m.body.GetStringHeight and m.body:GetStringHeight()) or 60)
        local extraTop = (st.tag and st.tag ~= "") and 52 or 38
        local bubbleNeedH = math.max(146, math.min(360, extraTop + bodyH + 50))
        local totalH = math.max(154, bubbleNeedH + 8)
        m:SetHeight(totalH)

        TriggerNpcPortraitSpeech(m, (idx == 1 and 67) or 60)
        SyncNpcGuideSpotlightAndDock(m, spec, st, (GetTime and GetTime()) or 0)
    end
    m.RenderCurrentStep = RenderCurrentStep

    m.backBtn:SetScript("OnClick", function()
        m._combatResumeQuip = nil
        m._guideStep = math.max(1, (m._guideStep or 1) - 1)
        RenderCurrentStep()
    end)
    m.nextBtn:SetScript("OnClick", function()
        m._combatResumeQuip = nil
        local spec = m._guideSpec
        local total = (spec and spec.steps and #spec.steps) or 1
        local cur = m._guideStep or 1
        if cur >= total then
            if spec and type(spec.onComplete) == "function" then
                pcall(spec.onComplete)
            end
            m:Hide()
        else
            m._guideStep = cur + 1
            RenderCurrentStep()
        end
    end)

    local function NpcGuideOnUpdate(selfFrame, _)
        local spec = selfFrame._guideSpec
        local st = spec and spec.steps and spec.steps[selfFrame._guideStep or 1]
        local nowT = (GetTime and GetTime()) or 0
        SyncNpcGuideSpotlightAndDock(selfFrame, spec, st, nowT)
        if selfFrame._talkUntil and nowT < selfFrame._talkUntil then
            if (nowT - (selfFrame._lastTalkAnimAt or 0)) >= 1.65 then
                selfFrame._lastTalkAnimAt = nowT
                if selfFrame.model and selfFrame.model.SetAnimation then
                    pcall(selfFrame.model.SetAnimation, selfFrame.model, 60)
                end
            end
        elseif selfFrame._talkUntil then
            selfFrame._talkUntil = nil
            if selfFrame.model and selfFrame.model.SetAnimation then
                pcall(selfFrame.model.SetAnimation, selfFrame.model, 0)
            end
        end
    end

    local function ApplyNpcGuideTheme()
        local bubbleBorder = { 0.25, 0.17, 0.08, 1.0 }
        local bubbleParchment = { 0.905, 0.835, 0.690, 1.0 }
        if m.SetBackdrop then m:SetBackdrop(nil) end
        if m._solidOpaqueBg then m._solidOpaqueBg:Hide() end
        m:EnableMouse(false)
        if m.model and m.portBox then
            m.model:SetFrameLevel((m.portBox:GetFrameLevel() or 866) + 2)
        end
        if m.title then
            m.title:SetTextColor(0.28, 0.14, 0.03)
            if m.title.SetShadowColor then m.title:SetShadowColor(0, 0, 0, 0) end
        end
        if m.tagFs then
            m.tagFs:SetTextColor(0.45, 0.23, 0.04)
            if m.tagFs.SetShadowColor then m.tagFs:SetShadowColor(0, 0, 0, 0) end
        end
        if m.body then
            m.body:SetTextColor(0.16, 0.11, 0.06)
            if m.body.SetShadowColor then m.body:SetShadowColor(0, 0, 0, 0) end
        end
        if m.stepPill then
            m.stepPill:SetTextColor(0.44, 0.34, 0.22)
            if m.stepPill.SetShadowColor then m.stepPill:SetShadowColor(0, 0, 0, 0) end
        end
        m.tailBorder:SetVertexColor(bubbleBorder[1], bubbleBorder[2], bubbleBorder[3], 1.0)
        m.tailFill:SetVertexColor(bubbleParchment[1], bubbleParchment[2], bubbleParchment[3], 1.0)
        if m.tailPatch then
            m.tailPatch:SetVertexColor(bubbleParchment[1], bubbleParchment[2], bubbleParchment[3], 1.0)
        end
        if m.bubbleDivider then
            m.bubbleDivider:SetVertexColor(0.70, 0.59, 0.42, 1.0)
        end
        Theme:StyleButton(m.topCloseBtn, "default")
        Theme:StyleButton(m.skipBtn, "default")
        if m.skipAllBtn then Theme:StyleButton(m.skipAllBtn, "default") end
        Theme:StyleButton(m.backBtn, "default")
        Theme:StyleButton(m.nextBtn, "primary")
    end
    m.ApplyNpcGuideTheme = ApplyNpcGuideTheme

    m:HookScript("OnShow", function(selfFrame)
        selfFrame:SetScript("OnUpdate", NpcGuideOnUpdate)
    end)
    m:HookScript("OnHide", function(selfFrame)
        selfFrame:SetScript("OnUpdate", nil)
        if guideSpotlight then guideSpotlight:Hide() end
        if selfFrame._hidingForCombat then
            return
        end
        selfFrame._combatSuspended = false
        selfFrame._suspendedSpec = nil
        selfFrame._combatResumeToken = (selfFrame._combatResumeToken or 0) + 1
        local spec = selfFrame._guideSpec
        if spec and type(spec.onClose) == "function" then
            pcall(spec.onClose)
        end
    end)

    m:RegisterEvent("PLAYER_REGEN_DISABLED")
    m:RegisterEvent("PLAYER_REGEN_ENABLED")
    m:HookScript("OnEvent", function(selfFrame, eventName)
        if eventName == "PLAYER_REGEN_DISABLED" then
            selfFrame._combatResumeToken = (selfFrame._combatResumeToken or 0) + 1
            if selfFrame:IsShown() and selfFrame._guideSpec then
                selfFrame._combatSuspended = true
                selfFrame._suspendedSpec = selfFrame._guideSpec
                selfFrame._suspendedStep = selfFrame._guideStep or 1
                selfFrame._suspendedDragged = selfFrame._userDragged == true
                selfFrame._hidingForCombat = true
                selfFrame:Hide()
                selfFrame._hidingForCombat = false
            end
        elseif eventName == "PLAYER_REGEN_ENABLED" then
            if selfFrame._combatSuspended and selfFrame._suspendedSpec then
                selfFrame._combatResumeToken = (selfFrame._combatResumeToken or 0) + 1
                local tok = selfFrame._combatResumeToken
                local function TryResumeAfterCombat()
                    if selfFrame._combatResumeToken ~= tok then return end
                    if not (selfFrame._combatSuspended and selfFrame._suspendedSpec) then return end
                    if IsNpcGuideInCombat() then return end
                    local spec = selfFrame._suspendedSpec
                    if type(spec.isAnchorVisible) == "function" then
                        local okVis, vis = pcall(spec.isAnchorVisible)
                        if okVis and vis == false then
                            return
                        end
                    end
                    local resumeStep = selfFrame._suspendedStep or 1
                    local keepDragged = selfFrame._suspendedDragged == true
                    selfFrame._combatSuspended = false
                    selfFrame._suspendedSpec = nil
                    Theme:ShowNpcGuide(spec, {
                        resumeStep = resumeStep,
                        keepDragged = keepDragged,
                        fromCombatResume = true,
                    })
                end
                if C_Timer and C_Timer.After then
                    C_Timer.After(2.5, TryResumeAfterCombat)
                else
                    TryResumeAfterCombat()
                end
            elseif Theme._pendingTutorialPrompts and next(Theme._pendingTutorialPrompts) ~= nil then
                selfFrame._combatPromptToken = (selfFrame._combatPromptToken or 0) + 1
                local pTok = selfFrame._combatPromptToken
                local function FlushPendingPrompts()
                    if selfFrame._combatPromptToken ~= pTok or IsNpcGuideInCombat() then return end
                    if Theme:IsNpcGuideShown() then return end
                    local pending = Theme._pendingTutorialPrompts
                    if type(pending) ~= "table" then return end
                    for k, pSpec in pairs(pending) do
                        pending[k] = nil
                        if pSpec and not (ns.IsAccountTutorialShown and ns:IsAccountTutorialShown(pSpec.tutorialKey)) then
                            local visOk = true
                            if type(pSpec.isWindowVisible) == "function" then
                                local okV, v = pcall(pSpec.isWindowVisible)
                                visOk = (okV and v == true)
                            end
                            if visOk then
                                Theme:PromptWindowTutorial(pSpec)
                                break
                            end
                        end
                    end
                end
                if C_Timer and C_Timer.After then
                    C_Timer.After(2.2, FlushPendingPrompts)
                else
                    FlushPendingPrompts()
                end
            end
        end
    end)

    Theme:RegisterListener(function()
        if m:IsShown() then
            ApplyNpcGuideTheme()
        end
    end)

    ApplyNpcGuideTheme()
    helpPopup = m
    return m
end

function Theme:IsNpcGuideShown(key)
    if not (helpPopup and helpPopup:IsShown()) then return false end
    if key == nil then return true end
    return helpPopup._guideSpec and helpPopup._guideSpec.key == key
end

function Theme:GetActiveNpcGuideStep()
    if not (helpPopup and helpPopup:IsShown() and helpPopup._guideSpec) then
        return nil, nil
    end
    return helpPopup._guideSpec.key, helpPopup._guideStep
end

function Theme:HideNpcGuide(key)
    if not helpPopup then return end
    if helpPopup._combatSuspended and helpPopup._suspendedSpec and (key == nil or helpPopup._suspendedSpec.key == key) then
        helpPopup._combatSuspended = false
        helpPopup._suspendedSpec = nil
        helpPopup._combatResumeToken = (helpPopup._combatResumeToken or 0) + 1
    end
    if not helpPopup:IsShown() then return end
    if key == nil or (helpPopup._guideSpec and helpPopup._guideSpec.key == key) then
        helpPopup:Hide()
    end
end

--- Display Chromie NPC speech-bubble guide with smart multi-target spotlight pointing (never during combat).
function Theme:ShowNpcGuide(spec, opts)
    if IsNpcGuideInCombat() then
        return nil
    end
    if type(spec) ~= "table" or type(spec.steps) ~= "table" or #spec.steps == 0 then
        return nil
    end
    local m = EnsureNpcGuidePopup()
    if not (opts and opts.fromCombatResume) then
        m._combatSuspended = false
        m._suspendedSpec = nil
        m._combatResumeToken = (m._combatResumeToken or 0) + 1
        m._combatResumeQuip = nil
    else
        local quips = {
            L["ChromieResume1"],
            L["ChromieResume2"],
            L["ChromieResume3"],
            L["ChromieResume4"],
        }
        local pickIdx = math.random(1, #quips)
        if m._lastQuipIdx and #quips > 1 and pickIdx == m._lastQuipIdx then
            pickIdx = (pickIdx % #quips) + 1
        end
        m._lastQuipIdx = pickIdx
        m._combatResumeQuip = quips[pickIdx]
    end
    m._guideSpec = spec
    m._guideStep = (opts and opts.resumeStep) and tonumber(opts.resumeStep) or 1
    m._userDragged = (opts and opts.keepDragged == true) and true or false
    self:PrepareTopOverlayModal(m, 865)
    m:EnableMouse(false)
    if m.SetBackdrop then m:SetBackdrop(nil) end
    if m._solidOpaqueBg then m._solidOpaqueBg:Hide() end
    m.ApplyNpcGuideTheme()

    if m.model then
        m.model._loadedOk = false
        m.fallbackIco:Show()
        if m.model.ClearModel then pcall(m.model.ClearModel, m.model) end
        if m.model.SetDisplayInfo then pcall(m.model.SetDisplayInfo, m.model, CHROMIE_DISPLAY_ID) end
        if C_Timer and C_Timer.After then
            local modRef = m.model
            C_Timer.After(0.08, function()
                if not m:IsShown() or modRef._loadedOk then return end
                local fid = modRef.GetModelFileID and tonumber(modRef:GetModelFileID()) or 0
                if fid <= 0 and modRef.SetCreature then
                    pcall(modRef.SetCreature, modRef, CHROMIE_NPC_ID, CHROMIE_DISPLAY_ID)
                end
            end)
        end
    end

    m:Show()
    m.RenderCurrentStep()
    if m.Raise then m:Raise() end
    return m
end

function Theme:PromptWindowTutorial(spec)
    if type(spec) ~= "table" or not spec.tutorialKey or not spec.guideSpec then
        return nil
    end
    if (ns.db and ns.db.settings and ns.db.settings.tutorialDismissAll == true)
        or (SocialCentralDB and SocialCentralDB.settings and SocialCentralDB.settings.tutorialDismissAll == true)
    then
        return nil
    end
    if ns.IsAccountTutorialShown and ns:IsAccountTutorialShown(spec.tutorialKey) then
        return nil
    end
    if IsNpcGuideInCombat() then
        self._pendingTutorialPrompts = self._pendingTutorialPrompts or {}
        self._pendingTutorialPrompts[spec.tutorialKey] = spec
        EnsureNpcGuidePopup()
        return nil
    end
    if self:IsNpcGuideShown() then
        return nil
    end
    if type(spec.isWindowVisible) == "function" then
        local okV, vis = pcall(spec.isWindowVisible)
        if okV and vis == false then
            return nil
        end
    end
    local accepted = false
    local winTitle = spec.title or (spec.guideSpec and spec.guideSpec.title) or "SocialCentral"
    local askBody = spec.askText or string.format(L["First time opening %s! Would you like Chromie's quick tutorial to understand how everything works here?"], winTitle)
    return self:ShowNpcGuide({
        key = "prompt_" .. tostring(spec.tutorialKey),
        title = string.format(L["Chromie — %s"], winTitle),
        skipLabel = L["Not now"],
        skipAllLabel = L["Not now (all areas)"],
        doneLabel = L["Yes, show tutorial"],
        showSkipOnLast = true,
        defaultTarget = spec.guideSpec.defaultTarget,
        isAnchorVisible = spec.isWindowVisible,
        steps = {
            {
                title = string.format(L["Chromie — %s"], winTitle),
                tag = "|cff6b3b09" .. L["First time in this window?"] .. "|r",
                text = askBody .. "\n\n|cff5c4a35" .. L["Tip: Click any [?] button on any window or option for Chromie's help anytime, or toggle auto-guides in Settings > General."] .. "|r",
            },
        },
        onSkip = function()
            if ns.SetAccountTutorialShown then
                ns:SetAccountTutorialShown(spec.tutorialKey, true)
            end
            if type(spec.onSkip) == "function" then
                pcall(spec.onSkip)
            end
        end,
        onSkipAll = function()
            if ns.SetAccountTutorialShown then
                ns:SetAccountTutorialShown(spec.tutorialKey, true)
            end
            if ns.db and ns.db.settings then
                ns.db.settings.tutorialDismissAll = true
            end
            if SocialCentralDB and SocialCentralDB.settings then
                SocialCentralDB.settings.tutorialDismissAll = true
            end
            if SocialCentralCharDB and SocialCentralCharDB.settings then
                SocialCentralCharDB.settings.tutorialDismissAll = true
            end
            self._pendingTutorialPrompts = nil
            ns:Print(L["Chromie auto-tutorials disabled for all areas. Click any [?] button or re-enable auto-tutorials in Settings > General anytime."])
            if type(spec.onSkip) == "function" then
                pcall(spec.onSkip)
            end
        end,
        onClose = function()
            if not accepted then
                if ns.SetAccountTutorialShown then
                    ns:SetAccountTutorialShown(spec.tutorialKey, true)
                end
                if type(spec.onSkip) == "function" then
                    pcall(spec.onSkip)
                end
            end
        end,
        onComplete = function()
            accepted = true
            if ns.SetAccountTutorialShown then
                ns:SetAccountTutorialShown(spec.tutorialKey, true)
            end
            if type(spec.onAccept) == "function" then
                pcall(spec.onAccept)
            end
            local launch = function()
                if not IsNpcGuideInCombat() then
                    Theme:ShowNpcGuide(spec.guideSpec)
                end
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0.05, launch)
            else
                launch()
            end
        end,
    })
end

--- Display interactive Chromie speech-bubble help card with smart spotlight pointing.
function Theme:ShowHelpPopup(title, whatText, howText, opts)
    local guideSteps = opts and opts.steps
    if type(guideSteps) ~= "table" or #guideSteps == 0 then
        guideSteps = {}
        local wTxt = tostring(whatText or "")
        local hTxt = tostring(howText or "")
        local tTarget = opts and opts.target or nil
        if wTxt ~= "" then
            guideSteps[#guideSteps + 1] = {
                title = title or L["Help"],
                tag = "|cff1d4ed8" .. L["What it does:"] .. "|r",
                text = wTxt,
                nextLabel = (hTxt ~= "" and L["How to use >"] or nil),
                target = tTarget,
            }
        end
        if hTxt ~= "" then
            guideSteps[#guideSteps + 1] = {
                title = title or L["Help"],
                tag = "|cff15803d" .. L["How to use:"] .. "|r",
                text = hTxt,
                target = tTarget,
            }
        end
        if #guideSteps == 0 then
            guideSteps[1] = {
                title = title or L["Help"],
                text = title or L["Help"],
                target = tTarget,
            }
        end
    end
    return self:ShowNpcGuide({
        key = (opts and opts.key) or "help_popup",
        title = title or L["Help"],
        defaultTarget = opts and opts.target or nil,
        steps = guideSteps,
    })
end

local visibleHelpButtons = setmetatable({}, { __mode = "k" })
local helpPulseDriver = nil
local helpPulseAccum = 0
local helpPulseAttached = false

local function HelpPulseOnUpdate(_, elapsed)
    helpPulseAccum = helpPulseAccum + (elapsed or 0)
    if helpPulseAccum < 0.10 then
        return
    end
    helpPulseAccum = 0
    if next(visibleHelpButtons) == nil then
        if helpPulseDriver and helpPulseAttached then
            helpPulseAttached = false
            helpPulseDriver:SetScript("OnUpdate", nil)
        end
        return
    end
    local nowT = (GetTime and GetTime()) or 0
    local inCombat = IsNpcGuideInCombat()
    for btn in pairs(visibleHelpButtons) do
        if btn and btn.IsVisible and btn:IsVisible() then
            if not btn._scHelpHovered then
                local w = inCombat and 0.15 or (0.5 + 0.5 * math.sin(nowT * 1.65 + (btn._scHelpPhase or 0)))
                if btn._scHelpAura then
                    btn._scHelpAura:SetVertexColor(0.96, 0.78, 0.28, 0.02 + 0.12 * w)
                end
                if btn.ico then
                    btn.ico:SetVertexColor(0.88 + 0.12 * w, 0.86 + 0.12 * w, 0.78 + 0.18 * w, 1)
                end
            end
        else
            visibleHelpButtons[btn] = nil
        end
    end
end

local function SyncHelpButtonPulseDriver(btn, shown)
    if not btn then return end
    if shown then
        visibleHelpButtons[btn] = true
        if not helpPulseDriver then
            helpPulseDriver = CreateFrame("Frame", nil, UIParent)
        end
        if not helpPulseAttached then
            helpPulseAttached = true
            helpPulseAccum = 0.06
            helpPulseDriver:SetScript("OnUpdate", HelpPulseOnUpdate)
        end
    else
        visibleHelpButtons[btn] = nil
        if next(visibleHelpButtons) == nil and helpPulseDriver and helpPulseAttached then
            helpPulseAttached = false
            helpPulseDriver:SetScript("OnUpdate", nil)
        end
    end
end

--- Create a standardized native-icon '?' help button beside an option or feature bar.
function Theme:CreateHelpButton(parent, title, whatText, howText, size, opts)
    local sz = size or 16
    local btn = self:CreateButton(parent, sz, sz, "", "default")
    btn:SetHitRectInsets(-2, -2, -2, -2)

    local aura = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    aura:SetSize(sz + 6, sz + 6)
    aura:SetPoint("CENTER", btn, "CENTER", 0, 0)
    aura:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\toast-glow")
    aura:SetVertexColor(0.96, 0.78, 0.28, 0.06)
    btn._scHelpAura = aura
    btn._scHelpPhase = ((sz * 0.37) + (#tostring(title or "") * 0.53)) % (math.pi * 2)

    self:ConfigureIconButton(btn, sz, sz, "Interface\\Icons\\INV_Misc_QuestionMark", {
        size = math.max(12, sz - 3),
        color = { 0.94, 0.90, 0.80 },
    })
    btn._scHelpTitle = title
    btn._scHelpWhat = whatText
    btn._scHelpHow = howText
    btn._scHelpOpts = opts
    if opts and opts.target ~= nil then
        btn._scGuideTarget = opts.target
    end

    btn:HookScript("OnShow", function(selfBtn)
        SyncHelpButtonPulseDriver(selfBtn, true)
    end)
    btn:HookScript("OnHide", function(selfBtn)
        selfBtn._scHelpHovered = false
        SyncHelpButtonPulseDriver(selfBtn, false)
    end)
    if btn:IsVisible() then
        SyncHelpButtonPulseDriver(btn, true)
    end

    btn:HookScript("OnEnter", function(selfBtn)
        selfBtn._scHelpHovered = true
        aura:SetVertexColor(0.98, 0.80, 0.28, 0.28)
        if selfBtn.ico then
            selfBtn.ico:SetVertexColor(1.0, 1.0, 1.0, 1)
        end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(selfBtn._scHelpTitle or L["Help"], 0.35, 0.72, 1.0, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff58a6ff" .. L["What it does:"] .. "|r " .. (selfBtn._scHelpWhat or ""), 0.92, 0.94, 0.98, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff4ade80" .. L["How to use:"] .. "|r " .. (selfBtn._scHelpHow or ""), 0.85, 0.92, 0.88, true)
        GameTooltip:AddLine(" ")
        if IsNpcGuideInCombat() then
            GameTooltip:AddLine("|cffff7b72" .. L["In Combat"] .. ":|r " .. L["Chromie's interactive guide pauses during combat."], 1.0, 0.72, 0.68, true)
        else
            GameTooltip:AddLine(L["Click ? to ask Chromie and highlight this control."], 0.58, 0.65, 0.74, true)
        end
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function(selfBtn)
        selfBtn._scHelpHovered = false
        aura:SetVertexColor(0.96, 0.78, 0.28, 0.06)
        if selfBtn.ico then
            selfBtn.ico:SetVertexColor(0.94, 0.90, 0.80, 1)
        end
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(selfBtn)
        if IsNpcGuideInCombat() then
            return
        end
        GameTooltip:Hide()
        local curOpts = selfBtn._scHelpOpts
        local targetRef = ResolveHelpTargetFrame(selfBtn, curOpts)
        Theme:ShowHelpPopup(selfBtn._scHelpTitle, selfBtn._scHelpWhat, selfBtn._scHelpHow, {
            target = targetRef,
            steps = curOpts and curOpts.steps or nil,
        })
    end)
    self:RegisterListener(function()
        if btn:IsVisible() then
            self:StyleButton(btn, "default")
        else
            btn._scThemeKey = nil
        end
    end)
    return btn
end

function Theme:SetHelpButtonInfo(btn, title, whatText, howText, opts)
    if not btn then return end
    btn._scHelpTitle = title
    btn._scHelpWhat = whatText
    btn._scHelpHow = howText
    btn._scHelpOpts = opts
    if opts and opts.target ~= nil then
        btn._scGuideTarget = opts.target
    end
end

--- Display a copyable GitHub Releases URL & Windows updater popup (Blizzard HTTP-sandbox safe).
function Theme:ShowUpdatePopup(localVer, remoteVer, url)
    local releaseUrl = url or ns.RELEASE_URL or "https://github.com/raphaelredes/SocialCentral-Releases/releases/latest"
    local psCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File update-socialcentral.ps1"

    if not updatePopup then
        local m = CreateFrame("Frame", "SocialCentralUpdatePopup", UIParent, "BackdropTemplate")
        m:SetSize(470, 225)
        m:SetPoint("CENTER")
        self:PrepareTopOverlayModal(m, 865)
        self:MakeMovable(m, { key = "updatePopup" })
        table.insert(UISpecialFrames, "SocialCentralUpdatePopup")

        m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        m.title:SetPoint("TOPLEFT", 16, -14)
        m.title:SetPoint("TOPRIGHT", -36, -14)
        m.title:SetJustifyH("LEFT")

        local topCloseBtn = self:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function()
            if m.input then m.input:ClearFocus() end
            m:Hide()
        end)
        m.topCloseBtn = topCloseBtn

        m.desc = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        m.desc:SetPoint("TOPLEFT", 16, -42)
        m.desc:SetPoint("TOPRIGHT", -16, -42)
        m.desc:SetJustifyH("LEFT")
        m.desc:SetWordWrap(true)

        m.input = self:CreateEditBox(m, { height = 24 })
        m.input:SetPoint("TOPLEFT", 16, -112)
        m.input:SetPoint("TOPRIGHT", -16, -112)
        m.input:SetScript("OnEscapePressed", function() m:Hide() end)

        m.hint = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        m.hint:SetPoint("TOPLEFT", 16, -146)
        m.hint:SetPoint("TOPRIGHT", -16, -146)
        m.hint:SetJustifyH("LEFT")
        m.hint:SetText(L["Press Ctrl+C to copy the link or Windows updater command."])

        m.btnUrl = self:CreateButton(m, 130, 24, L["GitHub Releases"], "default")
        self:AutoFitButton(m.btnUrl, 124, 20)
        m.btnUrl:SetPoint("BOTTOMLEFT", 16, 14)

        m.btnCmd = self:CreateButton(m, 165, 24, L["Updater Script"], "default")
        self:AutoFitButton(m.btnCmd, 150, 20)
        m.btnCmd:SetPoint("LEFT", m.btnUrl, "RIGHT", 8, 0)

        m.btnClose = self:CreateButton(m, 92, 24, L["Close"], "primary")
        self:AutoFitButton(m.btnClose, 88, 20)
        m.btnClose:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnClose:SetScript("OnClick", function() m:Hide() end)

        self:RegisterListener(function()
            if m:IsShown() then
                self:ApplyBackdrop(m, "window")
                self:StyleButton(m.topCloseBtn, "default")
                self:StyleButton(m.btnUrl, "default")
                self:StyleButton(m.btnCmd, "default")
                self:StyleButton(m.btnClose, "primary")
            end
        end)

        updatePopup = m
    end

    self:PrepareTopOverlayModal(updatePopup, 865)
    self:ApplyBackdrop(updatePopup, "window")
    self:StyleButton(updatePopup.topCloseBtn, "default")
    self:StyleButton(updatePopup.btnUrl, "default")
    self:StyleButton(updatePopup.btnCmd, "default")
    self:StyleButton(updatePopup.btnClose, "primary")

    updatePopup.title:SetText(L["SocialCentral Update & GitHub"])
    local hasNewer = remoteVer and ns.Compat and ns.Compat.CompareSemVer(remoteVer, localVer or "0.0.0") > 0
    if hasNewer then
        updatePopup.desc:SetText(
            "|cff4ade80" .. L["Newer version detected in-game:"] .. " v" .. remoteVer .. "|r  (" .. L["Installed:"] .. " v" .. (localVer or ns.version or "0.0.0") .. ")\n\n" ..
            L["WoW addons cannot open websites or download files directly inside the game. Copy the public GitHub Releases URL or run the Windows updater script."]
        )
    else
        updatePopup.desc:SetText(
            L["Installed:"] .. " v" .. (localVer or ns.version or "0.0.0") .. "\n\n" ..
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
    if updatePopup.Raise then updatePopup:Raise() end
    SelectValue(releaseUrl)
end

local reloadPopup

--- Prompt the user with a safe, hardware-click Reload UI confirmation after changing language.
function Theme:ShowReloadPrompt(langLabel)
    if not reloadPopup then
        local m = CreateFrame("Frame", "SocialCentralReloadPopup", UIParent, "BackdropTemplate")
        m:SetSize(410, 160)
        m:SetPoint("CENTER")
        self:PrepareTopOverlayModal(m, 870)
        self:MakeMovable(m, { key = "reloadPopup" })
        table.insert(UISpecialFrames, "SocialCentralReloadPopup")

        m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        m.title:SetPoint("TOPLEFT", 16, -14)
        m.title:SetPoint("TOPRIGHT", -36, -14)
        m.title:SetJustifyH("LEFT")

        local topCloseBtn = self:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function() m:Hide() end)
        m.topCloseBtn = topCloseBtn

        m.desc = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        m.desc:SetPoint("TOPLEFT", 16, -42)
        m.desc:SetPoint("BOTTOMRIGHT", -16, 48)
        m.desc:SetJustifyH("LEFT")
        m.desc:SetJustifyV("TOP")
        m.desc:SetWordWrap(true)

        m.btnLater = self:CreateButton(m, 98, 24, L["Later"], "default")
        self:AutoFitButton(m.btnLater, 88, 20)
        m.btnLater:SetPoint("BOTTOMRIGHT", -16, 14)
        m.btnLater:SetScript("OnClick", function() m:Hide() end)

        m.btnReload = self:CreateButton(m, 130, 24, L["Reload UI"], "primary")
        self:AutoFitButton(m.btnReload, 118, 20)
        m.btnReload:SetPoint("RIGHT", m.btnLater, "LEFT", -8, 0)
        m.btnReload:SetScript("OnClick", function()
            if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
                ns:Print(L["In Combat"])
                return
            end
            if ReloadUI then
                ReloadUI()
            elseif C_UI and C_UI.Reload then
                C_UI.Reload()
            end
        end)

        self:RegisterListener(function()
            if m:IsShown() then
                self:ApplyBackdrop(m, "window")
                self:StyleButton(m.topCloseBtn, "default")
                self:StyleButton(m.btnLater, "default")
                self:StyleButton(m.btnReload, "primary")
            end
        end)

        reloadPopup = m
    end

    self:PrepareTopOverlayModal(reloadPopup, 870)
    self:ApplyBackdrop(reloadPopup, "window")
    self:StyleButton(reloadPopup.topCloseBtn, "default")
    self:StyleButton(reloadPopup.btnLater, "default")
    self:StyleButton(reloadPopup.btnReload, "primary")
    reloadPopup.title:SetText(L["Language Changed"])
    reloadPopup.desc:SetText(L["Language saved as %s. Reload UI now to apply the new language across all SocialCentral panels?"]:format(langLabel or "Auto"))
    reloadPopup:Show()
    if reloadPopup.Raise then reloadPopup:Raise() end
end

local themeWelcomePopup

--- First-run & settings visual theme chooser showing live miniature previews for all 3 SocialCentral styles.
function Theme:ShowThemeWelcomePicker()
    if not themeWelcomePopup then
        local m = CreateFrame("Frame", "SocialCentralThemePicker", UIParent, "BackdropTemplate")
        m:SetSize(928, 480)
        m:SetPoint("CENTER")
        self:PrepareTopOverlayModal(m, 880)
        self:MakeMovable(m, { key = "themePicker" })
        table.insert(UISpecialFrames, "SocialCentralThemePicker")

        local closeBtn = self:CreateButton(m, 24, 22, "X", "default")
        closeBtn:SetPoint("TOPRIGHT", -14, -14)
        m.closeBtn = closeBtn

        m.helpBtn = self:CreateHelpButton(
            m,
            L["Help: Choose Visual Style"],
            L["Lets you pick between Blizzard Official (dark charcoal & bronze-gold), Classic Gold (warm obsidian-gold frames), and Modern Theme (high-contrast dark slate) for every SocialCentral window."],
            L["Click any of the three preview cards to apply that visual style right away, or switch themes anytime later in Settings."],
            20,
            { target = m }
        )
        m.helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)

        local function FinishChoice(chosenKey)
            if ns.db and ns.db.settings then
                if chosenKey then
                    ns.db.settings.theme = chosenKey
                elseif not ns.db.settings.theme then
                    ns.db.settings.theme = "blizzard"
                end
                ns.db.settings.themeChosen = true
            end
            Theme:NotifyChanged()
            m:Hide()
            if ns.UI and ns.UI.Show then
                ns.UI:Show()
            end
        end

        closeBtn:SetScript("OnClick", function()
            FinishChoice(nil)
        end)

        m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        m.title:SetPoint("TOPLEFT", 20, -16)
        m.title:SetPoint("TOPRIGHT", m.helpBtn, "LEFT", -8, 0)
        m.title:SetJustifyH("LEFT")
        m.title:SetWordWrap(false)
        m.title:SetText(L["Choose Your SocialCentral Design"])

        m.sub = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        m.sub:SetPoint("TOPLEFT", 20, -40)
        m.sub:SetPoint("TOPRIGHT", -20, -40)
        m.sub:SetJustifyH("LEFT")
        m.sub:SetWordWrap(true)
        m.sub:SetText(L["Select any of the three themes below as your visual style. You can switch anytime in Settings -> General & Tools."])

        local function BuildSampleCard(kind, xOffset)
            local isBlizzSample = (kind == "blizzard")
            local isNativeSample = (kind == "native")
            local card = CreateFrame("Frame", nil, m, "BackdropTemplate")
            card:SetSize(284, 366)
            card:SetPoint("TOPLEFT", m, "TOPLEFT", xOffset, -78)
            card:EnableMouse(true)
            card._themeKind = kind

            local cardBg = isBlizzSample and { 0.10, 0.09, 0.075, 1.0 }
                or (isNativeSample and { 0.12, 0.105, 0.085, 1.0 } or { 0.07, 0.08, 0.11, 1.0 })
            local baseBorder = isBlizzSample and { 0.62, 0.52, 0.28, 1.0 }
                or (isNativeSample and { 0.58, 0.48, 0.28, 1.0 } or { 0.24, 0.34, 0.46, 0.95 })
            local hoverBorder = isBlizzSample and { 1.0, 0.82, 0.22, 1.0 }
                or (isNativeSample and { 0.96, 0.78, 0.28, 1.0 } or { 0.35, 0.78, 1.0, 1.0 })
            card._baseBorder = baseBorder
            card._hoverBorder = hoverBorder
            card:SetBackdrop(BACKDROP_SPEC)
            card:SetBackdropColor(cardBg[1], cardBg[2], cardBg[3], cardBg[4])
            card:SetBackdropBorderColor(baseBorder[1], baseBorder[2], baseBorder[3], baseBorder[4])

            local sheen = card:CreateTexture(nil, "BACKGROUND", nil, -4)
            sheen:SetPoint("TOPLEFT", 1, -1)
            sheen:SetPoint("TOPRIGHT", -1, -1)
            sheen:SetHeight(62)
            ApplySafeGradient(sheen, "VERTICAL", 0, 0, 0, 0,
                hoverBorder[1] * 0.25 + 0.05, hoverBorder[2] * 0.25 + 0.05, hoverBorder[3] * 0.25 + 0.05, 0.22)

            local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            title:SetPoint("TOPLEFT", 14, -12)
            title:SetJustifyH("LEFT")
            title:SetWordWrap(false)
            if isBlizzSample then
                title:SetText(L["Blizzard Official"])
                title:SetTextColor(1.0, 0.82, 0.0)
            elseif isNativeSample then
                title:SetText(L["Classic Gold"])
                title:SetTextColor(0.96, 0.78, 0.28)
            else
                title:SetText(L["Modern Theme"])
                title:SetTextColor(0.38, 0.80, 1.0)
            end

            local badge = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            badge:SetPoint("TOPRIGHT", -14, -15)
            badge:SetJustifyH("RIGHT")
            card.badge = badge
            title:SetPoint("RIGHT", badge, "LEFT", -6, 0)

            local sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            sub:SetPoint("TOPLEFT", 14, -34)
            sub:SetPoint("TOPRIGHT", -14, -34)
            sub:SetJustifyH("LEFT")
            sub:SetWordWrap(false)
            sub:SetText(isBlizzSample and L["Default - Blizzard Portrait & Stone"]
                or (isNativeSample and L["Optional - Warm Obsidian & Gold"] or L["Optional - Sleek Dark Minimalist UI"]))
            sub:SetTextColor(0.84, 0.86, 0.90)

            -- Visual miniature preview
            local preview = CreateFrame("Frame", nil, card, "BackdropTemplate")
            preview:SetPoint("TOPLEFT", 12, -56)
            preview:SetPoint("TOPRIGHT", -12, -56)
            preview:SetHeight(196)

            if isBlizzSample then
                preview:SetBackdrop(BACKDROP_SPEC)
                preview:SetBackdropColor(0.085, 0.08, 0.072, 1.0)
                preview:SetBackdropBorderColor(0.56, 0.48, 0.30, 1.0)

                local pHdr = preview:CreateTexture(nil, "ARTWORK")
                pHdr:SetPoint("TOPLEFT", 2, -2)
                pHdr:SetPoint("TOPRIGHT", -2, -2)
                pHdr:SetHeight(24)
                pHdr:SetColorTexture(0.07, 0.065, 0.055, 1.0)

                local port = preview:CreateTexture(nil, "OVERLAY")
                port:SetSize(26, 26)
                port:SetPoint("TOPLEFT", 4, -2)
                if SetPortraitToTexture then
                    pcall(SetPortraitToTexture, port, "Interface\\AddOns\\SocialCentral\\Media\\icon")
                else
                    port:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\icon")
                end

                local pTitle = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                pTitle:SetPoint("LEFT", port, "RIGHT", 6, 0)
                pTitle:SetText("SocialCentral")
                pTitle:SetTextColor(1.0, 0.82, 0.0)

                local pClose = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pClose:SetSize(14, 14)
                pClose:SetPoint("TOPRIGHT", -6, -6)
                pClose:SetBackdrop(BACKDROP_SPEC)
                pClose:SetBackdropColor(0.22, 0.19, 0.14, 1.0)
                pClose:SetBackdropBorderColor(0.84, 0.66, 0.24, 1.0)
                local pCloseTxt = pClose:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                pCloseTxt:SetPoint("CENTER", 0, 1)
                pCloseTxt:SetText("x")

                local pTab1 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pTab1:SetSize(58, 16)
                pTab1:SetPoint("TOPLEFT", 8, -30)
                pTab1:SetBackdrop(BACKDROP_SPEC)
                pTab1:SetBackdropColor(0.15, 0.13, 0.095, 1.0)
                pTab1:SetBackdropBorderColor(0.86, 0.68, 0.24, 1.0)
                local pTab1Acc = pTab1:CreateTexture(nil, "OVERLAY")
                pTab1Acc:SetHeight(2)
                pTab1Acc:SetPoint("TOPLEFT", 1, -1)
                pTab1Acc:SetPoint("TOPRIGHT", -1, -1)
                pTab1Acc:SetColorTexture(0.98, 0.80, 0.28, 1.0)
                local pTab1Txt = pTab1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                pTab1Txt:SetPoint("CENTER")
                pTab1Txt:SetText(L["Social"])

                local pTab2 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pTab2:SetSize(56, 16)
                pTab2:SetPoint("LEFT", pTab1, "RIGHT", 4, 0)
                pTab2:SetBackdrop(BACKDROP_SPEC)
                pTab2:SetBackdropColor(0.075, 0.07, 0.075, 1.0)
                pTab2:SetBackdropBorderColor(0.38, 0.31, 0.17, 1.0)
                local pTab2Txt = pTab2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                pTab2Txt:SetPoint("CENTER")
                pTab2Txt:SetText(L["Chat"])
                pTab2Txt:SetTextColor(1.0, 0.82, 0.0)

                local pWell = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pWell:SetPoint("TOPLEFT", 8, -48)
                pWell:SetPoint("BOTTOMRIGHT", -8, 32)
                pWell:SetBackdrop(BACKDROP_SPEC)
                pWell:SetBackdropColor(0.048, 0.045, 0.042, 1.0)
                pWell:SetBackdropBorderColor(0.36, 0.30, 0.19, 1.0)

                local r1 = CreateFrame("Frame", nil, pWell, "BackdropTemplate")
                r1:SetPoint("TOPLEFT", 5, -5)
                r1:SetPoint("TOPRIGHT", -14, -5)
                r1:SetHeight(32)
                r1:SetBackdrop(FLAT_BACKDROP_SPEC)
                r1:SetBackdropColor(0.30, 0.23, 0.08, 0.45)
                local d1 = r1:CreateTexture(nil, "OVERLAY")
                d1:SetSize(6, 6)
                d1:SetPoint("LEFT", 6, 4)
                d1:SetColorTexture(0.20, 0.90, 0.42, 1)
                local n1 = r1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                n1:SetPoint("TOPLEFT", 16, -4)
                n1:SetText("Valkur Maul")
                n1:SetTextColor(1.0, 0.82, 0.0)
                local s1 = r1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                s1:SetPoint("BOTTOMLEFT", 16, 4)
                s1:SetText(L["Online"] .. " - Stormwind")
                s1:SetTextColor(0.84, 0.80, 0.72)

                local r2 = CreateFrame("Frame", nil, pWell, "BackdropTemplate")
                r2:SetPoint("TOPLEFT", r1, "BOTTOMLEFT", 0, -2)
                r2:SetPoint("TOPRIGHT", r1, "BOTTOMRIGHT", 0, -2)
                r2:SetHeight(32)
                r2:SetBackdrop(FLAT_BACKDROP_SPEC)
                r2:SetBackdropColor(0.02, 0.02, 0.02, 0.45)
                local d2 = r2:CreateTexture(nil, "OVERLAY")
                d2:SetSize(6, 6)
                d2:SetPoint("LEFT", 6, 4)
                d2:SetColorTexture(0.20, 0.90, 0.42, 1)
                local n2 = r2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                n2:SetPoint("TOPLEFT", 16, -4)
                n2:SetText("Elune")
                n2:SetTextColor(1.0, 0.82, 0.0)
                local s2 = r2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                s2:SetPoint("BOTTOMLEFT", 16, 4)
                s2:SetText(L["Online"] .. " - Dalaran")
                s2:SetTextColor(0.78, 0.74, 0.66)

                local pScroll = pWell:CreateTexture(nil, "ARTWORK")
                pScroll:SetWidth(5)
                pScroll:SetPoint("TOPRIGHT", -5, -6)
                pScroll:SetPoint("BOTTOMRIGHT", -5, 6)
                pScroll:SetColorTexture(0.56, 0.45, 0.24, 0.88)

                local bPri = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                bPri:SetSize(66, 20)
                bPri:SetPoint("BOTTOMLEFT", 8, 7)
                bPri:SetBackdrop(BACKDROP_SPEC)
                bPri:SetBackdropColor(0.48, 0.10, 0.08, 1.0)
                bPri:SetBackdropBorderColor(0.94, 0.78, 0.24, 1.0)
                local bPriTxt = bPri:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                bPriTxt:SetPoint("CENTER")
                bPriTxt:SetText(L["Add"])
                bPriTxt:SetTextColor(1.0, 0.92, 0.70)

                local bChar1 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                bChar1:SetSize(76, 20)
                bChar1:SetPoint("LEFT", bPri, "RIGHT", 5, 0)
                bChar1:SetBackdrop(BACKDROP_SPEC)
                bChar1:SetBackdropColor(0.12, 0.11, 0.095, 1.0)
                bChar1:SetBackdropBorderColor(0.40, 0.34, 0.21, 1.0)
                local bChar1Txt = bChar1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                bChar1Txt:SetPoint("CENTER")
                bChar1Txt:SetText(L["Whisper"])
                bChar1Txt:SetTextColor(0.94, 0.86, 0.64)

                local bChar2 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                bChar2:SetSize(68, 20)
                bChar2:SetPoint("LEFT", bChar1, "RIGHT", 5, 0)
                bChar2:SetBackdrop(BACKDROP_SPEC)
                bChar2:SetBackdropColor(0.12, 0.11, 0.095, 1.0)
                bChar2:SetBackdropBorderColor(0.40, 0.34, 0.21, 1.0)
                local bChar2Txt = bChar2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                bChar2Txt:SetPoint("CENTER")
                bChar2Txt:SetText(L["Invite"])
                bChar2Txt:SetTextColor(0.94, 0.86, 0.64)
            else
                local winC = isNativeSample and { 0.11, 0.10, 0.09, 1.0 } or { 0.06, 0.07, 0.09, 1.0 }
                local winBr = isNativeSample and { 0.56, 0.48, 0.31, 1.0 } or { 0.20, 0.24, 0.30, 1.0 }
                local hdrC = isNativeSample and { 0.16, 0.14, 0.11, 1.0 } or { 0.09, 0.11, 0.14, 1.0 }
                local tabActBg = isNativeSample and { 0.44, 0.33, 0.11, 0.96 } or { 0.13, 0.36, 0.56, 0.95 }
                local tabActBr = isNativeSample and { 0.92, 0.76, 0.31, 1.0 } or { 0.30, 0.72, 1.0, 1.0 }
                local surfBg = isNativeSample and { 0.14, 0.13, 0.11, 1.0 } or { 0.09, 0.11, 0.15, 1.0 }
                local surfBr = isNativeSample and { 0.45, 0.39, 0.26, 1.0 } or { 0.18, 0.22, 0.28, 1.0 }
                local wellBg = isNativeSample and { 0.08, 0.07, 0.06, 0.96 } or { 0.05, 0.06, 0.08, 0.96 }
                local row1Bg = isNativeSample and { 0.33, 0.26, 0.13, 0.90 } or { 0.14, 0.27, 0.42, 0.90 }
                local row2Bg = isNativeSample and { 0.12, 0.11, 0.09, 0.75 } or { 0.10, 0.12, 0.16, 0.75 }
                local txtMain = isNativeSample and { 0.98, 0.94, 0.84 } or { 0.93, 0.95, 0.98 }
                local txtMuted = isNativeSample and { 0.76, 0.70, 0.58 } or { 0.62, 0.68, 0.76 }
                local btnBg = isNativeSample and { 0.22, 0.18, 0.13, 0.96 } or { 0.14, 0.17, 0.22, 0.95 }
                local btnBr = isNativeSample and { 0.58, 0.49, 0.31, 0.95 } or { 0.28, 0.33, 0.41, 0.95 }
                local thumbC = isNativeSample and { 0.52, 0.44, 0.28, 0.92 } or { 0.30, 0.37, 0.48, 0.90 }

                preview:SetBackdrop(BACKDROP_SPEC)
                preview:SetBackdropColor(winC[1], winC[2], winC[3], 1.0)
                preview:SetBackdropBorderColor(winBr[1], winBr[2], winBr[3], 1.0)

                local pHdr = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pHdr:SetPoint("TOPLEFT", 1, -1)
                pHdr:SetPoint("TOPRIGHT", -1, -1)
                pHdr:SetHeight(24)
                pHdr:SetBackdrop(FLAT_BACKDROP_SPEC)
                pHdr:SetBackdropColor(hdrC[1], hdrC[2], hdrC[3], 1.0)

                local pIcon = pHdr:CreateTexture(nil, "ARTWORK")
                pIcon:SetSize(15, 15)
                pIcon:SetPoint("LEFT", 8, 0)
                pIcon:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\icon")

                local pTitle = pHdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                pTitle:SetPoint("LEFT", pIcon, "RIGHT", 6, 0)
                pTitle:SetText("SocialCentral")
                pTitle:SetTextColor(txtMain[1], txtMain[2], txtMain[3])

                local pTab1 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pTab1:SetSize(58, 17)
                pTab1:SetPoint("TOPLEFT", 8, -29)
                pTab1:SetBackdrop(BACKDROP_SPEC)
                pTab1:SetBackdropColor(tabActBg[1], tabActBg[2], tabActBg[3], 0.95)
                pTab1:SetBackdropBorderColor(tabActBr[1], tabActBr[2], tabActBr[3], 1.0)
                local pTab1Txt = pTab1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                pTab1Txt:SetPoint("CENTER")
                pTab1Txt:SetText(L["Social"])

                local pTab2 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pTab2:SetSize(54, 17)
                pTab2:SetPoint("LEFT", pTab1, "RIGHT", 4, 0)
                pTab2:SetBackdrop(BACKDROP_SPEC)
                pTab2:SetBackdropColor(surfBg[1], surfBg[2], surfBg[3], 1.0)
                pTab2:SetBackdropBorderColor(surfBr[1], surfBr[2], surfBr[3], 1.0)
                local pTab2Txt = pTab2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                pTab2Txt:SetPoint("CENTER")
                pTab2Txt:SetText(L["Chat"])
                pTab2Txt:SetTextColor(txtMuted[1], txtMuted[2], txtMuted[3])

                local pTab3 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pTab3:SetSize(54, 17)
                pTab3:SetPoint("LEFT", pTab2, "RIGHT", 4, 0)
                pTab3:SetBackdrop(BACKDROP_SPEC)
                pTab3:SetBackdropColor(surfBg[1], surfBg[2], surfBg[3], 1.0)
                pTab3:SetBackdropBorderColor(surfBr[1], surfBr[2], surfBr[3], 1.0)
                local pTab3Txt = pTab3:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                pTab3Txt:SetPoint("CENTER")
                pTab3Txt:SetText(L["Clan"])
                pTab3Txt:SetTextColor(txtMuted[1], txtMuted[2], txtMuted[3])

                local pWell = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pWell:SetPoint("TOPLEFT", 8, -50)
                pWell:SetPoint("BOTTOMRIGHT", -8, 32)
                pWell:SetBackdrop(BACKDROP_SPEC)
                pWell:SetBackdropColor(wellBg[1], wellBg[2], wellBg[3], 0.96)
                pWell:SetBackdropBorderColor(surfBr[1], surfBr[2], surfBr[3], 0.90)

                local r1 = CreateFrame("Frame", nil, pWell, "BackdropTemplate")
                r1:SetPoint("TOPLEFT", 4, -4)
                r1:SetPoint("TOPRIGHT", -14, -4)
                r1:SetHeight(32)
                r1:SetBackdrop(FLAT_BACKDROP_SPEC)
                r1:SetBackdropColor(row1Bg[1], row1Bg[2], row1Bg[3], 0.90)
                local d1 = r1:CreateTexture(nil, "OVERLAY")
                d1:SetSize(6, 6)
                d1:SetPoint("LEFT", 6, 4)
                d1:SetColorTexture(0.24, 0.85, 0.45, 1)
                local n1 = r1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                n1:SetPoint("TOPLEFT", 16, -4)
                n1:SetText("Valkur Maul")
                n1:SetTextColor(txtMain[1], txtMain[2], txtMain[3])
                local s1 = r1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                s1:SetPoint("BOTTOMLEFT", 16, 4)
                s1:SetText(L["Online"] .. " - Stormwind")
                s1:SetTextColor(tabActBr[1], tabActBr[2], tabActBr[3])

                local r2 = CreateFrame("Frame", nil, pWell, "BackdropTemplate")
                r2:SetPoint("TOPLEFT", r1, "BOTTOMLEFT", 0, -2)
                r2:SetPoint("TOPRIGHT", r1, "BOTTOMRIGHT", 0, -2)
                r2:SetHeight(32)
                r2:SetBackdrop(FLAT_BACKDROP_SPEC)
                r2:SetBackdropColor(row2Bg[1], row2Bg[2], row2Bg[3], 0.75)
                local d2 = r2:CreateTexture(nil, "OVERLAY")
                d2:SetSize(6, 6)
                d2:SetPoint("LEFT", 6, 4)
                d2:SetColorTexture(0.24, 0.85, 0.45, 1)
                local n2 = r2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                n2:SetPoint("TOPLEFT", 16, -4)
                n2:SetText("Elune")
                n2:SetTextColor(txtMain[1], txtMain[2], txtMain[3])
                local s2 = r2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                s2:SetPoint("BOTTOMLEFT", 16, 4)
                s2:SetText(L["Online"] .. " - Dalaran")
                s2:SetTextColor(txtMuted[1], txtMuted[2], txtMuted[3])

                local pScroll = pWell:CreateTexture(nil, "ARTWORK")
                pScroll:SetWidth(5)
                pScroll:SetPoint("TOPRIGHT", -4, -6)
                pScroll:SetPoint("BOTTOMRIGHT", -4, 6)
                pScroll:SetColorTexture(thumbC[1], thumbC[2], thumbC[3], thumbC[4])

                local bPri = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                bPri:SetSize(66, 20)
                bPri:SetPoint("BOTTOMLEFT", 8, 7)
                bPri:SetBackdrop(BACKDROP_SPEC)
                bPri:SetBackdropColor(tabActBg[1], tabActBg[2], tabActBg[3], 0.95)
                bPri:SetBackdropBorderColor(tabActBr[1], tabActBr[2], tabActBr[3], 0.95)
                local bPriTxt = bPri:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                bPriTxt:SetPoint("CENTER")
                bPriTxt:SetText(L["Add"])
                bPriTxt:SetTextColor(txtMain[1], txtMain[2], txtMain[3])

                local bSec1 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                bSec1:SetSize(76, 20)
                bSec1:SetPoint("LEFT", bPri, "RIGHT", 5, 0)
                bSec1:SetBackdrop(BACKDROP_SPEC)
                bSec1:SetBackdropColor(btnBg[1], btnBg[2], btnBg[3], 0.95)
                bSec1:SetBackdropBorderColor(btnBr[1], btnBr[2], btnBr[3], 0.95)
                local bSec1Txt = bSec1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                bSec1Txt:SetPoint("CENTER")
                bSec1Txt:SetText(L["Whisper"])
                bSec1Txt:SetTextColor(txtMain[1], txtMain[2], txtMain[3])

                local bSec2 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                bSec2:SetSize(68, 20)
                bSec2:SetPoint("LEFT", bSec1, "RIGHT", 5, 0)
                bSec2:SetBackdrop(BACKDROP_SPEC)
                bSec2:SetBackdropColor(btnBg[1], btnBg[2], btnBg[3], 0.95)
                bSec2:SetBackdropBorderColor(btnBr[1], btnBr[2], btnBr[3], 0.95)
                local bSec2Txt = bSec2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                bSec2Txt:SetPoint("CENTER")
                bSec2Txt:SetText(L["Invite"])
                bSec2Txt:SetTextColor(txtMain[1], txtMain[2], txtMain[3])
            end

            local cap = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cap:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 2, -10)
            cap:SetPoint("TOPRIGHT", preview, "BOTTOMRIGHT", -2, -10)
            cap:SetJustifyH("LEFT")
            cap:SetWordWrap(true)
            cap:SetText(isBlizzSample
                and L["Portrait, dark inset well & matte charcoal-bronze buttons"]
                or (isNativeSample
                    and L["Warm obsidian-bronze surface, gold accents & amber glow"]
                    or L["Dark slate surface, sky-blue accents & flat buttons"]))
            cap:SetTextColor(0.76, 0.80, 0.86)

            local cta = CreateFrame("Button", nil, card, "BackdropTemplate")
            cta:SetHeight(28)
            cta:SetPoint("BOTTOMLEFT", 14, 12)
            cta:SetPoint("BOTTOMRIGHT", -14, 12)
            cta:SetBackdrop(BACKDROP_SPEC)
            if isBlizzSample then
                cta:SetBackdropColor(0.48, 0.10, 0.08, 1.0)
                cta:SetBackdropBorderColor(0.94, 0.78, 0.24, 1.0)
            elseif isNativeSample then
                cta:SetBackdropColor(0.44, 0.33, 0.11, 1.0)
                cta:SetBackdropBorderColor(0.92, 0.76, 0.31, 1.0)
            else
                cta:SetBackdropColor(0.14, 0.38, 0.60, 1.0)
                cta:SetBackdropBorderColor(0.32, 0.74, 1.0, 1.0)
            end
            cta.lbl = cta:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cta.lbl:SetPoint("LEFT", 8, 0)
            cta.lbl:SetPoint("RIGHT", -8, 0)
            cta.lbl:SetJustifyH("CENTER")
            cta.lbl:SetWordWrap(false)
            cta.lbl:SetText(isBlizzSample
                and L["Use Blizzard Official (Default)"]
                or (isNativeSample and L["Use Classic Gold"] or L["Use Modern Theme"]))
            cta.lbl:SetTextColor(
                (isBlizzSample or isNativeSample) and 1.0 or 0.96,
                isBlizzSample and 0.92 or (isNativeSample and 0.94 or 0.98),
                isBlizzSample and 0.56 or (isNativeSample and 0.66 or 1.0)
            )

            card:SetScript("OnEnter", function(selfCard)
                selfCard:SetBackdropBorderColor(hoverBorder[1], hoverBorder[2], hoverBorder[3], 1.0)
            end)
            card:SetScript("OnLeave", function(selfCard)
                local curTheme = Theme:GetThemeName()
                local br = (curTheme == kind) and hoverBorder or baseBorder
                selfCard:SetBackdropBorderColor(br[1], br[2], br[3], br[4] or 1.0)
            end)
            card:SetScript("OnMouseUp", function()
                FinishChoice(kind)
            end)
            cta:SetScript("OnEnter", function()
                card:SetBackdropBorderColor(hoverBorder[1], hoverBorder[2], hoverBorder[3], 1.0)
            end)
            cta:SetScript("OnLeave", function()
                local curTheme = Theme:GetThemeName()
                local br = (curTheme == kind) and hoverBorder or baseBorder
                card:SetBackdropBorderColor(br[1], br[2], br[3], br[4] or 1.0)
            end)
            cta:SetScript("OnClick", function()
                FinishChoice(kind)
            end)
            return card
        end

        m.cardBlizz = BuildSampleCard("blizzard", 20)
        m.cardNative = BuildSampleCard("native", 322)
        m.cardModern = BuildSampleCard("dark", 624)

        local function SyncPickerState()
            local curTheme = Theme:GetThemeName()
            local cards = { m.cardBlizz, m.cardNative, m.cardModern }
            for _, c in ipairs(cards) do
                if c then
                    local active = (c._themeKind == curTheme)
                    local br = active and c._hoverBorder or c._baseBorder
                    c:SetBackdropBorderColor(br[1], br[2], br[3], br[4] or 1.0)
                    if c.badge then
                        if active then
                            c.badge:SetText("[" .. L["In Use"] .. "]")
                            c.badge:SetTextColor(0.30, 0.92, 0.45)
                        elseif c._themeKind == "blizzard" then
                            c.badge:SetText("[" .. L["Default"] .. "]")
                            c.badge:SetTextColor(0.96, 0.80, 0.28)
                        else
                            c.badge:SetText("[" .. L["Optional"] .. "]")
                            c.badge:SetTextColor(0.62, 0.72, 0.86)
                        end
                    end
                end
            end
        end
        m.SyncPickerState = SyncPickerState
        SyncPickerState()

        self:RegisterListener(function()
            if m:IsShown() then
                self:ApplyBackdrop(m, "window")
                self:StyleButton(m.closeBtn, "default")
                if m.SyncPickerState then m.SyncPickerState() end
            end
        end)

        themeWelcomePopup = m
    end

    if themeWelcomePopup.SyncPickerState then
        themeWelcomePopup.SyncPickerState()
    end
    self:PrepareTopOverlayModal(themeWelcomePopup, 880)
    self:ApplyBackdrop(themeWelcomePopup, "window")
    self:StyleButton(themeWelcomePopup.closeBtn, "default")
    themeWelcomePopup:Show()
    if themeWelcomePopup.Raise then themeWelcomePopup:Raise() end
end

--- Create a reusable clipped virtual scroll list with mouse wheel and slim thumb.
function Theme:CreateScrollList(parent, rowHeight, createRowFn, updateRowFn)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    self:ApplyBackdrop(container, "inset")

    local viewport = CreateFrame("Frame", nil, container)
    viewport:SetPoint("TOPLEFT", 2, -2)
    viewport:SetPoint("BOTTOMRIGHT", -14, 2)
    viewport:SetClipsChildren(true)
    viewport:EnableMouse(true)
    viewport:EnableMouseWheel(true)
    viewport._scLevelOffset = 1

    local track = CreateFrame("Frame", nil, container, "BackdropTemplate")
    track:SetWidth(10)
    track:SetPoint("TOPRIGHT", -3, -4)
    track:SetPoint("BOTTOMRIGHT", -3, 4)
    track:EnableMouse(true)
    track._scLevelOffset = 2

    local upOk, scrollUpBtn = pcall(CreateFrame, "Button", nil, container, "UIPanelScrollUpButtonTemplate")
    if upOk and scrollUpBtn then
        scrollUpBtn:SetSize(14, 14)
        scrollUpBtn:SetPoint("TOPRIGHT", -3, -4)
        scrollUpBtn:Hide()
    else
        scrollUpBtn = nil
    end

    local dnOk, scrollDownBtn = pcall(CreateFrame, "Button", nil, container, "UIPanelScrollDownButtonTemplate")
    if dnOk and scrollDownBtn then
        scrollDownBtn:SetSize(14, 14)
        scrollDownBtn:SetPoint("BOTTOMRIGHT", -3, 4)
        scrollDownBtn:Hide()
    else
        scrollDownBtn = nil
    end

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(6)
    thumb:SetHeight(32)
    thumb:SetPoint("TOP", 0, 0)
    thumb._scLevelOffset = 1
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

    local emptyRule = viewport:CreateTexture(nil, "ARTWORK")
    emptyRule:SetSize(84, 1)
    emptyRule:SetPoint("CENTER", viewport, "CENTER", 0, 22)
    emptyRule:Hide()
    list.emptyRule = emptyRule

    local emptyLabel = viewport:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyLabel:SetPoint("LEFT", viewport, "LEFT", 16, 4)
    emptyLabel:SetPoint("RIGHT", viewport, "RIGHT", -16, 4)
    emptyLabel:SetJustifyH("CENTER")
    emptyLabel:SetWordWrap(true)
    emptyLabel:Hide()
    list.emptyLabel = emptyLabel

    local function UpdateTrackColors(hovered)
        local p = Theme:GetPalette()
        local isBlizz = Theme:IsBlizzard(p)
        local sbSig = tostring(p and p.key or "dark") .. (hovered and ":1" or ":0")
        if list._scTrackThemeSig ~= sbSig then
            list._scTrackThemeSig = sbSig
            viewport:ClearAllPoints()
            track:ClearAllPoints()
            if scrollUpBtn then scrollUpBtn:Hide() end
            if scrollDownBtn then scrollDownBtn:Hide() end
            if isBlizz then
                viewport:SetPoint("TOPLEFT", 3, -3)
                viewport:SetPoint("BOTTOMRIGHT", -13, 3)
                track:SetWidth(6)
                track:SetPoint("TOPRIGHT", -4, -4)
                track:SetPoint("BOTTOMRIGHT", -4, 4)
            else
                viewport:SetPoint("TOPLEFT", 2, -2)
                viewport:SetPoint("BOTTOMRIGHT", -12, 2)
                track:SetWidth(6)
                track:SetPoint("TOPRIGHT", -3, -4)
                track:SetPoint("BOTTOMRIGHT", -3, 4)
            end
            if track.SetBackdrop then
                track:SetBackdrop(BACKDROP_SPEC)
                track:SetBackdropColor(p.scrollTrack[1], p.scrollTrack[2], p.scrollTrack[3], p.scrollTrack[4])
                local br = p.surfaceBorder or { 0.25, 0.25, 0.25, 0.4 }
                track:SetBackdropBorderColor(br[1], br[2], br[3], 0.42)
            end
            local c = hovered and p.scrollThumbHover or p.scrollThumb
            local cTopR, cTopG, cTopB = math.min(1, c[1] + 0.14), math.min(1, c[2] + 0.14), math.min(1, c[3] + 0.14)
            ApplySafeGradient(thumb.tex, "VERTICAL", c[1], c[2], c[3], c[4] or 0.92, cTopR, cTopG, cTopB, c[4] or 0.96)
            if not thumb._topGloss then
                local tg = thumb:CreateTexture(nil, "OVERLAY", nil, 1)
                tg:SetHeight(1)
                tg:SetPoint("TOPLEFT", 0, 0)
                tg:SetPoint("TOPRIGHT", 0, 0)
                thumb._topGloss = tg
            end
            thumb._topGloss:SetColorTexture(1, 0.96, 0.88, hovered and 0.45 or 0.24)
            emptyLabel:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
            local ac = (isBlizz or p.key == "native") and { 0.88, 0.72, 0.28 } or (p.accentBorder or { 0.35, 0.78, 1.0 })
            emptyRule:SetColorTexture(ac[1], ac[2], ac[3], 0.35)
        end
        local sepR, sepG, sepB, sepA = 0.55, 0.78, 1.0, 0.06
        if isBlizz or p.key == "native" then
            sepR, sepG, sepB, sepA = 0.78, 0.64, 0.28, 0.085
        end
        for _, r in ipairs(list.rows) do
            if r._scRowSep then
                r._scRowSep:SetColorTexture(sepR, sepG, sepB, sepA)
            end
        end
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
        local vpH = viewport:GetHeight() or 0
        if vpH <= 0 then
            vpH = 280
        end
        local needed = math.max(1, math.ceil(vpH / list.rowHeight) + 1)
        if #list.rows >= needed then
            return
        end
        local p = Theme:GetPalette()
        local isWarm = (p and (p.key == "blizzard" or p.key == "native"))
        local sepR, sepG, sepB, sepA = 0.55, 0.78, 1.0, 0.06
        if isWarm then
            sepR, sepG, sepB, sepA = 0.78, 0.64, 0.28, 0.085
        end
        while #list.rows < needed do
            local idx = #list.rows + 1
            local row = createRowFn(viewport, idx, list.rowHeight)
            row:SetHeight(list.rowHeight)
            row._scIndex = idx
            row._scIsListRow = true
            if row.CreateTexture and not row._scRowSep then
                local rSep = row:CreateTexture(nil, "ARTWORK", nil, 0)
                rSep:SetHeight(1)
                rSep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 0)
                rSep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 0)
                rSep:SetColorTexture(sepR, sepG, sepB, sepA)
                row._scRowSep = rSep
            end
            list.rows[idx] = row
        end
    end

    local function SyncScrollListLayers()
        local cLvl = math.max(1, math.min(9960, (container.GetFrameLevel and container:GetFrameLevel()) or 1))
        if list._scLastContainerLvl == cLvl then
            return cLvl
        end
        list._scLastContainerLvl = cLvl
        if viewport.SetFrameLevel and (viewport:GetFrameLevel() or 0) ~= (cLvl + 1) then
            viewport:SetFrameLevel(cLvl + 1)
        end
        if track.SetFrameLevel and (track:GetFrameLevel() or 0) ~= (cLvl + 2) then
            track:SetFrameLevel(cLvl + 2)
        end
        if thumb.SetFrameLevel and (thumb:GetFrameLevel() or 0) ~= (cLvl + 3) then
            thumb:SetFrameLevel(cLvl + 3)
        end
        return cLvl
    end

    function list:RefreshTheme()
        list._scTrackThemeSig = nil
        list._scLastContainerLvl = nil
        Theme:ApplyBackdrop(container, "inset")
        SyncScrollListLayers()
        UpdateTrackColors(false)
        for _, row in ipairs(self.rows) do
            if row.RefreshTheme then
                row:RefreshTheme()
            end
        end
    end

    --- Dynamically update scroll row height and re-pool rows to support compact/standard density modes.
    function list:SetRowHeight(newHeight)
        local h = math.max(16, tonumber(newHeight) or 30)
        if not h or h < 16 or self.rowHeight == h then
            return
        end
        self.rowHeight = h
        for _, row in ipairs(self.rows) do
            if row.SetHeight then
                row:SetHeight(h)
            end
            row._scRenderedY = nil
        end
        local maxOffset = GetMaxOffset()
        if (self.offset or 0) > maxOffset then
            self.offset = maxOffset
        end
        self:Render()
    end

    function list:Render()
        local cLvl = SyncScrollListLayers()
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
            local hasEmpty = (self.emptyText ~= nil and self.emptyText ~= "")
            emptyLabel:SetText(self.emptyText or "")
            emptyLabel:SetShown(hasEmpty)
            emptyRule:SetShown(hasEmpty)
        else
            emptyLabel:Hide()
            emptyRule:Hide()
        end

        local firstIndex = math.floor(self.offset / self.rowHeight) + 1
        local subOffset = self.offset % self.rowHeight

        for poolIdx, row in ipairs(self.rows) do
            local dataIdx = firstIndex + poolIdx - 1
            local item = self.items[dataIdx]
            if item then
                local rowTargetLvl = math.min(9970, cLvl + 2)
                if row.SetFrameLevel and (row:GetFrameLevel() or 0) ~= rowTargetLvl then
                    row:SetFrameLevel(rowTargetLvl)
                    Theme:SyncSubtreeLayers(row, 4)
                elseif not row._scRowLayerInit then
                    row._scRowLayerInit = true
                    Theme:SyncSubtreeLayers(row, 4)
                end
                local y = -((poolIdx - 1) * self.rowHeight) + subOffset
                if row._scRenderedY ~= y then
                    row._scRenderedY = y
                    row:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, y)
                    row:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, y)
                end
                Theme:ApplyBackdrop(row, (dataIdx % 2 == 1) and "row" or "rowAlt", p)
                updateRowFn(row, item, dataIdx, p)
                if not row:IsShown() then
                    row:Show()
                end
            else
                if row:IsShown() then
                    row:Hide()
                end
            end
        end

        local trackH = track:GetHeight() or 0
        if maxOffset <= 0 or trackH <= 0 or total == 0 then
            if thumb:IsShown() then
                thumb:Hide()
            end
            list._scThumbH = nil
            list._scThumbPos = nil
        else
            if not thumb:IsShown() then
                thumb:Show()
            end
            local totalH = total * self.rowHeight
            local ratio = math.min(1, vpH / totalH)
            local thumbH = math.min(trackH, math.max(24, math.floor(trackH * ratio)))
            if list._scThumbH ~= thumbH then
                list._scThumbH = thumbH
                thumb:SetHeight(thumbH)
            end
            local travel = math.max(1, trackH - thumbH)
            local pos = math.floor(((self.offset / maxOffset) * travel) + 0.5)
            if list._scThumbPos ~= pos then
                list._scThumbPos = pos
                thumb:ClearAllPoints()
                thumb:SetPoint("TOP", track, "TOP", 0, -pos)
            end
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

    if scrollUpBtn then
        scrollUpBtn:SetScript("OnClick", function()
            list.offset = math.max(0, list.offset - list.rowHeight)
            list:Render()
        end)
    end
    if scrollDownBtn then
        scrollDownBtn:SetScript("OnClick", function()
            list.offset = math.min(GetMaxOffset(), list.offset + list.rowHeight)
            list:Render()
        end)
    end

    viewport:SetScript("OnMouseWheel", function(_, delta)
        local step = list.rowHeight * 2
        list.offset = math.max(0, math.min(GetMaxOffset(), list.offset - delta * step))
        list:Render()
    end)

    viewport:SetScript("OnSizeChanged", function(selfVp, w, h)
        if not (container:IsVisible() and selfVp:IsVisible()) then
            return
        end
        local nw = math.floor((w or selfVp:GetWidth() or 0) + 0.5)
        local nh = math.floor((h or selfVp:GetHeight() or 0) + 0.5)
        if list._lastVpW == nw and list._lastVpH == nh then
            return
        end
        list._lastVpW = nw
        list._lastVpH = nh
        list:Render()
    end)

    local dragging = false
    local dragStartY = 0
    local dragStartOffset = 0
    local function OnThumbUpdate()
        if not dragging or not IsMouseButtonDown("LeftButton") then
            dragging = false
            thumb:SetScript("OnUpdate", nil)
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
    end
    local function StopThumbDrag()
        dragging = false
        thumb:SetScript("OnUpdate", nil)
    end
    thumb:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        dragging = true
        local _, cursorY = GetCursorPosition()
        local scale = thumb:GetEffectiveScale() or 1
        dragStartY = cursorY / scale
        dragStartOffset = list.offset
        thumb:SetScript("OnUpdate", OnThumbUpdate)
    end)
    thumb:SetScript("OnMouseUp", StopThumbDrag)
    thumb:SetScript("OnHide", StopThumbDrag)

    UpdateTrackColors(false)
    return list
end

--- Sleek theme-aware reskin for native UIPanelScrollFrameTemplate scrollbars across Settings and modals.
function Theme:StyleScrollFrame(sf)
    if not sf then return end
    local p = self:GetPalette()
    local isBlizz = self:IsBlizzard(p)
    local sbName = sf.GetName and sf:GetName() or nil
    local sb = sf.ScrollBar or (sbName and _G[sbName .. "ScrollBar"]) or nil
    if not sb then return end
    local sig = tostring(p and p.key or "dark")
    if sb._scStyledSig == sig then
        return
    end
    sb._scStyledSig = sig

    if not sb._scBgStrip then
        local bg = sb:CreateTexture(nil, "BACKGROUND", nil, -6)
        bg:SetWidth(8)
        bg:SetPoint("TOP", sb, "TOP", 0, -16)
        bg:SetPoint("BOTTOM", sb, "BOTTOM", 0, 16)
        sb._scBgStrip = bg
    end
    local tr = p.scrollTrack or { 0.06, 0.07, 0.09, 0.78 }
    sb._scBgStrip:SetColorTexture(tr[1], tr[2], tr[3], tr[4] or 0.80)

    local thumb = (sb.GetThumbTexture and sb:GetThumbTexture())
        or sb.ThumbTexture
        or (sbName and _G[sbName .. "ScrollBarThumbTexture"])
        or nil
    if thumb and thumb.SetTexture then
        local tc = p.scrollThumb or { 0.35, 0.42, 0.55, 0.90 }
        thumb:SetTexture(WHITE8X8)
        thumb:SetVertexColor(tc[1], tc[2], tc[3], tc[4] or 0.92)
        thumb:SetWidth(8)
    end

    local upBtn = sb.ScrollUpButton or (sbName and _G[sbName .. "ScrollBarScrollUpButton"])
    local dnBtn = sb.ScrollDownButton or (sbName and _G[sbName .. "ScrollBarScrollDownButton"])
    local tintA = isBlizz and 0.92 or 0.72
    if upBtn and upBtn.SetAlpha then upBtn:SetAlpha(tintA) end
    if dnBtn and dnBtn.SetAlpha then dnBtn:SetAlpha(tintA) end

    local nReg = sb.GetNumRegions and sb:GetNumRegions() or 0
    for i = 1, nReg do
        local reg = select(i, sb:GetRegions())
        if reg and reg ~= sb._scBgStrip and reg ~= thumb and reg.GetObjectType and reg:GetObjectType() == "Texture" then
            if isBlizz then
                reg:SetAlpha(0.75)
            else
                reg:SetAlpha(0.18)
            end
        end
    end
end

local BADGE_CIRCLE_TEX = "Interface\\AddOns\\SocialCentral\\Media\\dot"
local BADGE_GLOW_TEX = "Interface\\AddOns\\SocialCentral\\Media\\toast-glow"
local BADGE_MASK_TEX = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local activeCounterBadges = setmetatable({}, { __mode = "k" })
local counterFontHooksInstalled = false
local counterFontEventFrame

local function RefreshAllCounterBadges()
    for badge in pairs(activeCounterBadges) do
        if badge and badge.IsShown and badge:IsShown() and (badge._count or 0) > 0 then
            if badge._isMulti and badge.SetCountMulti and badge._multiTones then
                badge:SetCountMulti(badge._count, badge._multiTones, false)
            elseif badge.SetCount then
                badge:SetCount(badge._count, badge._tone)
            end
        end
    end
end

local function EnsureCounterBadgeFontSync()
    if counterFontHooksInstalled then
        return
    end
    counterFontHooksInstalled = true
    if not counterFontEventFrame and CreateFrame then
        counterFontEventFrame = CreateFrame("Frame")
        if ns and ns.RegisterEvent then
            ns.RegisterEvent(counterFontEventFrame, "PLAYER_ENTERING_WORLD", RefreshAllCounterBadges)
            ns.RegisterEvent(counterFontEventFrame, "UPDATE_CHAT_WINDOWS", RefreshAllCounterBadges)
            ns.RegisterEvent(counterFontEventFrame, "UI_SCALE_CHANGED", RefreshAllCounterBadges)
        end
    end
    if type(_G.FCF_SetChatWindowFontSize) == "function" and type(hooksecurefunc) == "function" then
        hooksecurefunc("FCF_SetChatWindowFontSize", RefreshAllCounterBadges)
    end
end

local BADGE_TONES = {
    whisper = {
        rimTop = { 1.00, 0.88, 0.42, 1.0 },
        rimBot = { 0.80, 0.56, 0.14, 1.0 },
        coreTop = { 0.94, 0.34, 0.90, 1.0 },
        coreBot = { 0.60, 0.12, 0.62, 1.0 },
        lobe = { 1.00, 0.34, 0.92 },
        halo = { 1.00, 0.46, 0.96 },
        accent = { 1.00, 0.50, 1.00 },
        cardBgTop = { 0.30, 0.10, 0.29, 1.0 },
        cardBgBot = { 0.17, 0.04, 0.18, 1.0 },
        cardBorder = { 0.90, 0.40, 0.90, 1.0 },
    },
    bnet = {
        rimTop = { 1.00, 0.88, 0.42, 1.0 },
        rimBot = { 0.78, 0.56, 0.16, 1.0 },
        coreTop = { 0.08, 0.72, 0.96, 1.0 },
        coreBot = { 0.03, 0.40, 0.68, 1.0 },
        lobe = { 0.08, 0.82, 1.00 },
        halo = { 0.14, 0.86, 1.00 },
        accent = { 0.10, 0.82, 1.00 },
        cardBgTop = { 0.06, 0.21, 0.31, 1.0 },
        cardBgBot = { 0.03, 0.11, 0.19, 1.0 },
        cardBorder = { 0.18, 0.76, 0.98, 1.0 },
    },
    group = {
        rimTop = { 1.00, 0.88, 0.42, 1.0 },
        rimBot = { 0.78, 0.56, 0.16, 1.0 },
        coreTop = { 0.32, 0.54, 1.00, 1.0 },
        coreBot = { 0.14, 0.28, 0.72, 1.0 },
        lobe = { 0.30, 0.58, 1.00 },
        halo = { 0.44, 0.68, 1.00 },
        accent = { 0.48, 0.68, 1.00 },
        cardBgTop = { 0.11, 0.17, 0.36, 1.0 },
        cardBgBot = { 0.06, 0.09, 0.22, 1.0 },
        cardBorder = { 0.44, 0.64, 1.00, 1.0 },
    },
    raid = {
        rimTop = { 1.00, 0.88, 0.42, 1.0 },
        rimBot = { 0.80, 0.54, 0.14, 1.0 },
        coreTop = { 0.94, 0.46, 0.08, 1.0 },
        coreBot = { 0.62, 0.24, 0.03, 1.0 },
        lobe = { 1.00, 0.52, 0.14 },
        halo = { 1.00, 0.58, 0.20 },
        accent = { 1.00, 0.54, 0.18 },
        cardBgTop = { 0.32, 0.15, 0.04, 1.0 },
        cardBgBot = { 0.18, 0.07, 0.02, 1.0 },
        cardBorder = { 0.96, 0.52, 0.18, 1.0 },
    },
    guild = {
        rimTop = { 1.00, 0.90, 0.44, 1.0 },
        rimBot = { 0.80, 0.56, 0.14, 1.0 },
        coreTop = { 0.18, 0.78, 0.26, 1.0 },
        coreBot = { 0.08, 0.46, 0.14, 1.0 },
        lobe = { 0.22, 0.94, 0.36 },
        halo = { 0.30, 0.98, 0.42 },
        accent = { 0.28, 0.94, 0.40 },
        cardBgTop = { 0.07, 0.26, 0.10, 1.0 },
        cardBgBot = { 0.03, 0.15, 0.06, 1.0 },
        cardBorder = { 0.30, 0.88, 0.40, 1.0 },
    },
    room = {
        rimTop = { 1.00, 0.88, 0.42, 1.0 },
        rimBot = { 0.78, 0.56, 0.16, 1.0 },
        coreTop = { 0.60, 0.32, 0.96, 1.0 },
        coreBot = { 0.36, 0.14, 0.68, 1.0 },
        lobe = { 0.68, 0.38, 1.00 },
        halo = { 0.74, 0.46, 1.00 },
        accent = { 0.74, 0.50, 1.00 },
        cardBgTop = { 0.19, 0.10, 0.33, 1.0 },
        cardBgBot = { 0.10, 0.05, 0.20, 1.0 },
        cardBorder = { 0.70, 0.46, 0.98, 1.0 },
    },
    alert = {
        rimTop = { 1.00, 0.86, 0.34, 1.0 },
        rimBot = { 0.78, 0.56, 0.14, 1.0 },
        coreTop = { 0.90, 0.14, 0.18, 1.0 },
        coreBot = { 0.62, 0.04, 0.08, 1.0 },
        lobe = { 0.96, 0.20, 0.24 },
        halo = { 1.00, 0.26, 0.24 },
        accent = { 1.00, 0.30, 0.32 },
        cardBgTop = { 0.28, 0.07, 0.09, 1.0 },
        cardBgBot = { 0.15, 0.03, 0.05, 1.0 },
        cardBorder = { 0.92, 0.30, 0.32, 1.0 },
    },
    say = {
        rimTop = { 0.92, 0.90, 0.78, 1.0 },
        rimBot = { 0.68, 0.66, 0.54, 1.0 },
        coreTop = { 0.88, 0.90, 0.94, 1.0 },
        coreBot = { 0.58, 0.62, 0.68, 1.0 },
        lobe = { 0.92, 0.94, 0.98 },
        halo = { 0.96, 0.98, 1.00 },
        accent = { 0.94, 0.96, 0.98 },
        cardBgTop = { 0.20, 0.21, 0.24, 1.0 },
        cardBgBot = { 0.11, 0.12, 0.14, 1.0 },
        cardBorder = { 0.78, 0.82, 0.88, 1.0 },
    },
    general = {
        rimTop = { 0.86, 0.78, 0.54, 1.0 },
        rimBot = { 0.58, 0.52, 0.34, 1.0 },
        coreTop = { 0.62, 0.78, 0.98, 1.0 },
        coreBot = { 0.34, 0.48, 0.70, 1.0 },
        lobe = { 0.74, 0.86, 1.00 },
        halo = { 0.78, 0.88, 1.00 },
        accent = { 0.80, 0.90, 1.00 },
        cardBgTop = { 0.15, 0.20, 0.28, 1.0 },
        cardBgBot = { 0.08, 0.11, 0.17, 1.0 },
        cardBorder = { 0.62, 0.78, 0.98, 1.0 },
    },
    pub = {
        rimTop = { 1.00, 0.82, 0.76, 1.0 },
        rimBot = { 0.78, 0.54, 0.48, 1.0 },
        coreTop = { 1.00, 0.75, 0.75, 1.0 },
        coreBot = { 0.72, 0.44, 0.44, 1.0 },
        lobe = { 1.00, 0.78, 0.78 },
        halo = { 1.00, 0.82, 0.82 },
        accent = { 1.00, 0.76, 0.76 },
        cardBgTop = { 0.24, 0.14, 0.14, 1.0 },
        cardBgBot = { 0.14, 0.08, 0.08, 1.0 },
        cardBorder = { 0.96, 0.68, 0.68, 1.0 },
    },
}

Theme.CHAT_TONES = BADGE_TONES

function Theme:GetChatToneSpec(toneKey)
    local key = type(toneKey) == "string" and toneKey:lower() or "whisper"
    return BADGE_TONES[key] or BADGE_TONES.whisper
end

function Theme:GetChatToneForKind(kind)
    local k = type(kind) == "string" and kind:upper() or ""
    if k == "GENERAL" then
        return "general"
    elseif k == "PUB_CHANNEL" then
        return "pub"
    elseif k == "BN_WHISPER" or k == "BNET" then
        return "bnet"
    elseif k == "GUILD" or k == "OFFICER" then
        return "guild"
    elseif k == "RAID" then
        return "raid"
    elseif k == "PARTY" or k == "GROUP" or k == "INSTANCE_CHAT" or k == "INSTANCE" then
        return "group"
    elseif k == "ROOM" or k == "ALLIANCE" then
        return "room"
    elseif k == "LOCAL_SAY" then
        return "say"
    elseif k == "LOCAL_YELL" then
        return "alert"
    elseif k == "WHISPER" or k == "DIRECT" then
        return "whisper"
    end
    return "whisper"
end

local function ResolveReadableCounterFontSpec(minSize, maxSize, sizeOffset)
    local chatPath, chatSize
    local cf = _G.ChatFrame1
    if cf and cf.GetFont then
        local ok, p, sz = pcall(cf.GetFont, cf)
        if ok and type(p) == "string" and p ~= "" and type(sz) == "number" and sz > 0 then
            chatPath = p
            chatSize = sz
        end
    end
    if not chatSize and _G.ChatFontNormal and _G.ChatFontNormal.GetFont then
        local ok, p, sz = pcall(_G.ChatFontNormal.GetFont, _G.ChatFontNormal)
        if ok then
            if type(p) == "string" and p ~= "" then
                chatPath = chatPath or p
            end
            if type(sz) == "number" and sz > 0 then
                chatSize = sz
            end
        end
    end
    local baseChat = chatSize or 14
    local floorSz = minSize or 14
    local ceilSz = maxSize or 20
    local target = math.floor(baseChat + (sizeOffset or 0) + 0.5)
    if target < floorSz then target = floorSz end
    if target > ceilSz then target = ceilSz end

    -- Prefer Blizzard's wider standard text typeface so thin digits like '1' stay bright white
    -- instead of getting darkened by outline compression on condensed narrow fonts.
    local stdPath = _G.STANDARD_TEXT_FONT
    if (not stdPath or stdPath == "") and _G.GameFontNormal and _G.GameFontNormal.GetFont then
        local ok, p = pcall(_G.GameFontNormal.GetFont, _G.GameFontNormal)
        if ok and type(p) == "string" and p ~= "" then
            stdPath = p
        end
    end
    local fontPath = (type(stdPath) == "string" and stdPath ~= "") and stdPath or chatPath
    if (not fontPath or fontPath == "") and _G.NumberFontNormal and _G.NumberFontNormal.GetFont then
        local ok, p = pcall(_G.NumberFontNormal.GetFont, _G.NumberFontNormal)
        if ok and type(p) == "string" and p ~= "" then
            fontPath = p
        end
    end
    return fontPath, target, baseChat
end

--- Return (fontPath, targetSize, rawChatSize) scaled to be at least WoW chat font size.
function Theme:GetReadableCounterFont(minSize, maxSize, sizeOffset)
    return ResolveReadableCounterFontSpec(minSize, maxSize, sizeOffset)
end

--- Apply crisp, high-contrast chat-scale typography to a notification/queue FontString.
function Theme:ApplyReadableCounterFont(fs, minSize, maxSize, sizeOffset, useOutline)
    if not fs then return end
    local fontPath, targetSz = ResolveReadableCounterFontSpec(minSize, maxSize, sizeOffset)
    local flags = (useOutline ~= false) and "OUTLINE" or ""
    if fontPath and fs.SetFont then
        pcall(fs.SetFont, fs, fontPath, targetSz, flags)
    end
    if fs.SetShadowColor then
        fs:SetShadowColor(0, 0, 0, useOutline == false and 0.85 or 0.45)
        fs:SetShadowOffset(0, -1)
    end
    return targetSz
end

local function CreateCounterPillBand(animFrame, layer, subLevel, inset)
    local capL = animFrame:CreateTexture(nil, layer, nil, subLevel)
    capL:SetTexture(BADGE_CIRCLE_TEX)
    capL:SetTexCoord(0, 0.5, 0, 1)

    local capR = animFrame:CreateTexture(nil, layer, nil, subLevel)
    capR:SetTexture(BADGE_CIRCLE_TEX)
    capR:SetTexCoord(0.5, 1, 0, 1)

    local mid = animFrame:CreateTexture(nil, layer, nil, subLevel)
    mid:SetTexture(WHITE8X8)

    local band = {}
    function band:SetSizeForBadge(totalW, totalH)
        local effThick = math.max(8, (totalH or 24) - (inset or 0))
        local bw = math.max(effThick, (totalW or effThick) - (inset or 0))
        local capW = effThick * 0.5
        local midW = bw - effThick
        capL:SetSize(capW, effThick)
        capL:ClearAllPoints()
        capL:SetPoint("LEFT", animFrame, "CENTER", -bw * 0.5, 0)

        capR:SetSize(capW, effThick)
        capR:ClearAllPoints()
        capR:SetPoint("RIGHT", animFrame, "CENTER", bw * 0.5, 0)

        if midW > 0.25 then
            mid:SetSize(midW + 0.8, effThick)
            mid:ClearAllPoints()
            mid:SetPoint("CENTER", animFrame, "CENTER", 0, 0)
            mid:Show()
        else
            mid:Hide()
        end
    end

    function band:SetSolidColor(r, g, b, a)
        capL:SetVertexColor(r, g, b, a or 1)
        capR:SetVertexColor(r, g, b, a or 1)
        mid:SetVertexColor(r, g, b, a or 1)
    end

    function band:SetVerticalGradient(cTop, cBot)
        if capL.SetGradient and CreateColor then
            if not gradColorA then gradColorA = CreateColor(0, 0, 0, 1) end
            if not gradColorB then gradColorB = CreateColor(0, 0, 0, 1) end
            gradColorA:SetRGBA(cBot[1], cBot[2], cBot[3], cBot[4] or 1)
            gradColorB:SetRGBA(cTop[1], cTop[2], cTop[3], cTop[4] or 1)
            capL:SetVertexColor(1, 1, 1, 1)
            capR:SetVertexColor(1, 1, 1, 1)
            mid:SetVertexColor(1, 1, 1, 1)
            pcall(capL.SetGradient, capL, "VERTICAL", gradColorA, gradColorB)
            pcall(capR.SetGradient, capR, "VERTICAL", gradColorA, gradColorB)
            pcall(mid.SetGradient, mid, "VERTICAL", gradColorA, gradColorB)
        else
            local r = (cTop[1] + cBot[1]) * 0.5
            local g = (cTop[2] + cBot[2]) * 0.5
            local b = (cTop[3] + cBot[3]) * 0.5
            local a = ((cTop[4] or 1) + (cBot[4] or 1)) * 0.5
            band:SetSolidColor(r, g, b, a)
        end
    end

    return band
end

--- Create a high-contrast, chat-font-scaled pill/circle notification counter badge.
function Theme:CreateCounterBadge(parent, opts)
    opts = opts or {}
    local minFontSize = opts.minFontSize or 14
    local maxFontSize = opts.maxFontSize or 20
    local fontScaleOffset = opts.fontScaleOffset or 0
    local _, initialFontSz = ResolveReadableCounterFontSpec(minFontSize, maxFontSize, fontScaleOffset)
    local h = math.max(opts.height or 24, initialFontSz + 8)
    local maxNum = opts.maxNum or 99
    local baseHaloAlpha = opts.haloAlpha or 0.48
    local allowPulse = opts.noPulse ~= true

    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(h, h)
    b:EnableMouse(false)
    if b.SetClipsChildren then
        b:SetClipsChildren(false)
    end
    b._baseHeight = h
    b._maxNum = maxNum
    b._minFontSize = minFontSize
    b._maxFontSize = maxFontSize
    b._fontScaleOffset = fontScaleOffset
    b._tone = "whisper"
    b._count = 0
    b._isMulti = false
    b._multiTones = nil
    b._pulseEnabled = allowPulse
    b._popUntil = 0
    b._fusionBurstUntil = 0
    b._pulsePhase = 0
    b._swirlAngle = 0.55
    b._curW = h
    b._curH = h

    local anim = CreateFrame("Frame", nil, b)
    anim:SetSize(h, h)
    anim:SetPoint("CENTER", b, "CENTER", 0, 0)
    anim:EnableMouse(false)
    b.anim = anim

    local halo = anim:CreateTexture(nil, "BACKGROUND", nil, -2)
    halo:SetTexture(BADGE_GLOW_TEX)
    halo:SetBlendMode("ADD")
    halo:SetPoint("CENTER", anim, "CENTER", 0, 0)
    halo:SetSize(h + 12, h + 12)
    halo:SetAlpha(baseHaloAlpha)
    b.halo = halo

    local shadowBand = CreateCounterPillBand(anim, "BACKGROUND", -1, -2)
    shadowBand:SetSolidColor(0.04, 0.03, 0.04, 0.96)
    b.shadowBand = shadowBand

    local rimBand = CreateCounterPillBand(anim, "ARTWORK", 0, 0)
    b.rimBand = rimBand

    local coreBand = CreateCounterPillBand(anim, "ARTWORK", 2, 3)
    b.coreBand = coreBand

    local txt = anim:CreateFontString(nil, "OVERLAY")
    if txt.SetDrawLayer then
        txt:SetDrawLayer("OVERLAY", 7)
    end
    txt:SetPoint("CENTER", anim, "CENTER", 0.5, 0)
    txt:SetJustifyH("CENTER")
    if txt.SetJustifyV then
        txt:SetJustifyV("MIDDLE")
    end
    txt:SetWordWrap(false)
    txt:SetTextColor(1, 1, 1, 1)
    b.text = txt

    local function SyncFont(charLen)
        local drop = (charLen and charLen >= 3) and 1 or 0
        local floorSz = math.max(13, minFontSize - drop)
        local fontPath, targetSz = ResolveReadableCounterFontSpec(floorSz, maxFontSize, fontScaleOffset - drop)
        if b._curFontPath ~= fontPath or b._curFontSize ~= targetSz then
            b._curFontPath = fontPath
            b._curFontSize = targetSz
            if fontPath and txt.SetFont then
                pcall(txt.SetFont, txt, fontPath, targetSz, "OUTLINE")
            end
            if txt.SetShadowColor then
                txt:SetShadowColor(0, 0, 0, 0.45)
                txt:SetShadowOffset(0, -1)
            end
        end
        return targetSz
    end

    local function ApplyToneColors(toneKey)
        local spec = BADGE_TONES[toneKey] or BADGE_TONES.whisper
        rimBand:SetVerticalGradient(spec.rimTop, spec.rimBot)
        coreBand:SetVerticalGradient(spec.coreTop, spec.coreBot)
        halo:SetVertexColor(spec.halo[1], spec.halo[2], spec.halo[3], 1)
    end

    local function EnsureFusionVisuals()
        if b._fusion then
            return b._fusion
        end
        local mask = anim.CreateMaskTexture and anim:CreateMaskTexture() or nil
        if mask then
            mask:SetTexture(BADGE_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetPoint("CENTER", anim, "CENTER", 0, 0)
            mask:SetSize(math.max(12, h - 3), math.max(12, h - 3))
        end
        local lobes = {}
        for i = 1, 6 do
            local outer = anim:CreateTexture(nil, "ARTWORK", nil, 3)
            outer:SetTexture(BADGE_GLOW_TEX)
            outer:SetBlendMode("BLEND")
            if mask then outer:AddMaskTexture(mask) end
            outer:Hide()

            local inner = anim:CreateTexture(nil, "ARTWORK", nil, 4)
            inner:SetTexture(BADGE_GLOW_TEX)
            inner:SetBlendMode("BLEND")
            if mask then inner:AddMaskTexture(mask) end
            inner:Hide()

            local aura = anim:CreateTexture(nil, "BACKGROUND", nil, -2)
            aura:SetTexture(BADGE_GLOW_TEX)
            aura:SetBlendMode("ADD")
            aura:Hide()

            lobes[i] = { outer = outer, inner = inner, aura = aura }
        end

        local vignette = anim:CreateTexture(nil, "ARTWORK", nil, 6)
        vignette:SetTexture(BADGE_GLOW_TEX)
        vignette:SetBlendMode("BLEND")
        vignette:SetVertexColor(0.03, 0.02, 0.05, 0.36)
        vignette:SetPoint("CENTER", anim, "CENTER", 0, 0)
        if mask then vignette:AddMaskTexture(mask) end
        vignette:Hide()

        local flash = anim:CreateTexture(nil, "OVERLAY", nil, 5)
        flash:SetTexture(BADGE_GLOW_TEX)
        flash:SetBlendMode("ADD")
        flash:SetVertexColor(1.0, 0.96, 0.86, 0)
        flash:SetPoint("CENTER", anim, "CENTER", 0, 0)
        flash:Hide()

        b._fusion = {
            mask = mask,
            lobes = lobes,
            vignette = vignette,
            flash = flash,
        }
        return b._fusion
    end

    local function HideFusionVisuals()
        local fz = b._fusion
        if not fz then return end
        for i = 1, 6 do
            local lb = fz.lobes[i]
            lb.outer:Hide()
            lb.inner:Hide()
            lb.aura:Hide()
        end
        fz.vignette:Hide()
        fz.flash:Hide()
    end

    local function PositionFusionLobes(angleOffset)
        local fz = b._fusion
        local tones = b._multiTones
        if not (fz and b._isMulti and tones and #tones >= 2) then
            return
        end
        local bw = b._curW or h
        local bh = b._curH or h
        local coreW = math.max(12, bw - 3)
        local coreH = math.max(12, bh - 3)
        if fz.mask then
            fz.mask:SetSize(coreW, coreH)
        end
        fz.vignette:SetSize(coreW * 0.78, coreH * 0.78)

        local count = math.min(6, #tones)
        local step = (math.pi * 2) / count
        local rx = coreW * 0.36
        local ry = coreH * 0.36
        local outerW, outerH = coreW * 1.92, coreH * 1.92
        local innerW, innerH = coreW * 1.36, coreH * 1.36
        local auraW, auraH = bw + 12, bh + 12
        local auraAlpha = b._pulseEnabled and (baseHaloAlpha * 0.72) or (baseHaloAlpha * 0.42)

        for i = 1, 6 do
            local lb = fz.lobes[i]
            if i <= count then
                local ang = angleOffset + (i - 1) * step
                local cosA = math.cos(ang)
                local sinA = math.sin(ang)
                local ox = cosA * rx
                local oy = sinA * ry
                lb.outer:SetSize(outerW, outerH)
                lb.outer:ClearAllPoints()
                lb.outer:SetPoint("CENTER", anim, "CENTER", ox, oy)
                lb.outer:Show()

                lb.inner:SetSize(innerW, innerH)
                lb.inner:ClearAllPoints()
                lb.inner:SetPoint("CENTER", anim, "CENTER", ox, oy)
                lb.inner:Show()

                if b._pulseEnabled then
                    lb.aura:SetSize(auraW, auraH)
                    lb.aura:ClearAllPoints()
                    lb.aura:SetPoint("CENTER", anim, "CENTER", cosA * 4.5, sinA * 4.5)
                    lb.aura:SetAlpha(auraAlpha)
                    lb.aura:Show()
                else
                    lb.aura:Hide()
                end
            else
                lb.outer:Hide()
                lb.inner:Hide()
                lb.aura:Hide()
            end
        end
        fz.vignette:Show()
    end

    local function StopAnimLoop()
        anim:SetScript("OnUpdate", nil)
        b._animAccum = 0
        anim:SetScale(1)
        if b._fusion and b._fusion.flash then
            b._fusion.flash:Hide()
        end
        if b._isMulti then
            halo:Hide()
            PositionFusionLobes(b._swirlAngle or 0.55)
        else
            halo:SetAlpha(b._pulseEnabled and baseHaloAlpha or (baseHaloAlpha * 0.65))
        end
    end

    local function DriveAnimLoop(_, dt)
        if not (b:IsShown() and b._count > 0) then
            StopAnimLoop()
            return
        end
        local now = (GetTime and GetTime()) or 0
        local pulsing = b._pulseEnabled == true
        local popping = (b._popUntil or 0) > now
        local bursting = (b._fusionBurstUntil or 0) > now
        local swirling = b._isMulti == true
        if not pulsing and not popping and not bursting and not swirling then
            StopAnimLoop()
            return
        end
        local stepDt = dt or 0
        if not popping and not bursting then
            b._animAccum = (b._animAccum or 0) + stepDt
            if b._animAccum < 0.04 then
                return
            end
            stepDt = b._animAccum
            b._animAccum = 0
        else
            b._animAccum = 0
        end
        local delta = math.min(stepDt, 0.08)

        if popping then
            local popDur = bursting and 0.34 or 0.24
            local rem = math.max(0, math.min(1, (b._popUntil - now) / popDur))
            local amp = bursting and 0.24 or 0.14
            anim:SetScale(1 + amp * math.sin(rem * math.pi))
        else
            anim:SetScale(1)
        end

        if swirling then
            local spinSpeed = 0.42
            if bursting then
                local bRem = math.max(0, math.min(1, (b._fusionBurstUntil - now) / 0.56))
                spinSpeed = spinSpeed + 4.8 * (bRem * bRem)
                if b._fusion and b._fusion.flash then
                    local prog = 1 - bRem
                    local fSize = ((b._curW or h) * (0.65 + 1.85 * prog))
                    b._fusion.flash:SetSize(fSize, fSize)
                    b._fusion.flash:SetAlpha(math.max(0, (1 - prog) * 0.92))
                    b._fusion.flash:Show()
                end
            elseif b._fusion and b._fusion.flash then
                b._fusion.flash:Hide()
            end
            b._swirlAngle = ((b._swirlAngle or 0.55) + delta * spinSpeed) % (math.pi * 2)
            PositionFusionLobes(b._swirlAngle)
            halo:Hide()
        else
            if b._fusion and b._fusion.flash then
                b._fusion.flash:Hide()
            end
            if pulsing then
                b._pulsePhase = ((b._pulsePhase or 0) + delta * 3.1) % (math.pi * 2)
                local wave = 0.5 + 0.5 * math.sin(b._pulsePhase)
                halo:SetAlpha(math.max(0.12, math.min(0.92, baseHaloAlpha * (0.68 + 0.55 * wave))))
            else
                halo:SetAlpha(baseHaloAlpha * 0.65)
            end
        end
    end

    local function RefreshAnimLoop()
        local now = (GetTime and GetTime()) or 0
        local needsDrive = b:IsShown() and b._count > 0 and (
            b._pulseEnabled
            or b._isMulti
            or ((b._popUntil or 0) > now)
            or ((b._fusionBurstUntil or 0) > now)
        )
        if needsDrive then
            if not anim:GetScript("OnUpdate") then
                anim:SetScript("OnUpdate", DriveAnimLoop)
            end
        else
            StopAnimLoop()
        end
    end

    local function ApplyMetricLayout(lbl)
        local targetSz = SyncFont(#lbl) or 14
        local effH = math.max(b._baseHeight, targetSz + 9)
        txt:SetText(lbl)

        local strW = 0
        if txt.GetUnboundedStringWidth then
            strW = txt:GetUnboundedStringWidth() or 0
        elseif txt.GetStringWidth then
            strW = txt:GetStringWidth() or 0
        end

        local w
        if #lbl <= 1 then
            w = math.max(effH, math.ceil(strW + 10))
        else
            w = math.max(effH + ((#lbl == 2) and 8 or 14), math.ceil(strW + 13))
        end

        b._curW = w
        b._curH = effH
        b:SetSize(w, effH)
        anim:SetSize(w, effH)
        halo:SetSize(w + 12, effH + 12)
        shadowBand:SetSizeForBadge(w, effH)
        rimBand:SetSizeForBadge(w, effH)
        coreBand:SetSizeForBadge(w, effH)
        return w, effH
    end

    function b:SetTone(toneKey)
        local key = type(toneKey) == "string" and toneKey:lower() or "whisper"
        local clean = BADGE_TONES[key] and key or "whisper"
        self._tone = clean
        if not self._isMulti then
            ApplyToneColors(clean)
        end
    end

    function b:SetPulseEnabled(enabled)
        self._pulseEnabled = allowPulse and (enabled ~= false)
        if not self._pulseEnabled then
            halo:Hide()
        elseif not self._isMulti then
            halo:Show()
        end
        if self._isMulti then
            PositionFusionLobes(self._swirlAngle or 0.55)
        end
        RefreshAnimLoop()
    end

    function b:TriggerFusionBurst()
        if not GetTime then return end
        local now = GetTime()
        self._fusionBurstUntil = now + 0.56
        self._popUntil = now + 0.34
        RefreshAnimLoop()
    end

    function b:SetCount(count, toneKey)
        local n = math.floor(tonumber(count) or 0)
        local resolvedTone = toneKey and (type(toneKey) == "string" and BADGE_TONES[toneKey:lower()] and toneKey:lower() or "whisper") or (self._tone or "whisper")
        if n <= 0 and not self._isMulti and (self._count or 0) == 0 and not self:IsShown() then
            return
        end
        if n > 0 and not self._isMulti and self._count == n and self._tone == resolvedTone and self:IsShown() then
            return
        end
        self._isMulti = false
        self._multiTones = nil
        HideFusionVisuals()
        if self._pulseEnabled then
            halo:Show()
        end
        if toneKey then
            self:SetTone(toneKey)
        else
            ApplyToneColors(self._tone or "whisper")
        end
        if n <= 0 then
            self._count = 0
            self._popUntil = 0
            self._fusionBurstUntil = 0
            txt:SetText("")
            StopAnimLoop()
            self:Hide()
            return
        end

        local prev = self._count or 0
        self._count = n
        local lbl = (n > self._maxNum) and (tostring(self._maxNum) .. "+") or tostring(n)
        ApplyMetricLayout(lbl)

        if n > prev and prev >= 0 and self:IsVisible() and GetTime then
            self._popUntil = GetTime() + 0.24
        end
        self:Show()
        RefreshAnimLoop()
    end

    function b:SetCountMulti(count, tonesList, triggerBurst)
        local cleanTones = {}
        local seen = {}
        if type(tonesList) == "table" then
            for _, rawTone in ipairs(tonesList) do
                local key = type(rawTone) == "string" and rawTone:lower() or nil
                if key and BADGE_TONES[key] and not seen[key] then
                    seen[key] = true
                    cleanTones[#cleanTones + 1] = key
                    if #cleanTones >= 6 then break end
                end
            end
        end

        if #cleanTones <= 1 then
            self:SetCount(count, cleanTones[1] or self._tone or "whisper")
            return
        end

        local n = math.floor(tonumber(count) or 0)
        if n <= 0 then
            self:SetCount(0)
            return
        end

        local prev = self._count or 0
        self._isMulti = true
        self._multiTones = cleanTones
        self._tone = cleanTones[1]
        self._count = n

        local fz = EnsureFusionVisuals()
        rimBand:SetVerticalGradient({ 1.00, 0.90, 0.46, 1.0 }, { 0.80, 0.56, 0.14, 1.0 })
        coreBand:SetSolidColor(0.11, 0.10, 0.15, 1.0)
        halo:Hide()

        for i = 1, 6 do
            local lb = fz.lobes[i]
            local tKey = cleanTones[i]
            if tKey then
                local spec = BADGE_TONES[tKey] or BADGE_TONES.whisper
                local lc = spec.lobe or spec.accent
                local hc = spec.halo or lc
                lb.outer:SetVertexColor(lc[1], lc[2], lc[3], 1.0)
                lb.inner:SetVertexColor(lc[1], lc[2], lc[3], 0.96)
                lb.aura:SetVertexColor(hc[1], hc[2], hc[3], 1.0)
            else
                lb.outer:Hide()
                lb.inner:Hide()
                lb.aura:Hide()
            end
        end

        local lbl = (n > self._maxNum) and (tostring(self._maxNum) .. "+") or tostring(n)
        ApplyMetricLayout(lbl)
        PositionFusionLobes(self._swirlAngle or 0.55)

        if triggerBurst then
            self:TriggerFusionBurst()
        elseif n > prev and prev >= 0 and self:IsVisible() and GetTime then
            self._popUntil = GetTime() + 0.24
        end
        self:Show()
        RefreshAnimLoop()
    end

    b:SetScript("OnShow", RefreshAnimLoop)
    b:SetScript("OnHide", StopAnimLoop)
    ApplyToneColors("whisper")
    if not allowPulse then
        halo:Hide()
        b._pulseEnabled = false
    end
    activeCounterBadges[b] = true
    EnsureCounterBadgeFontSync()
    SyncFont(1)
    b:Hide()
    return b
end

--- Standardized compact [SC] quick-control button anchored beside or inside official Blizzard windows.
function Theme:CreateOfficialQuickButton(parent, opts)
    opts = opts or {}
    local sz = math.max(16, math.min(26, tonumber(opts.size) or 20))
    local btn = CreateFrame("Button", opts.name, parent, "BackdropTemplate")
    btn:SetSize(sz, sz)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if btn.SetClipsChildren then
        btn:SetClipsChildren(false)
    end

    local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetAllPoints()
    bg:SetTexture(WHITE8X8)
    bg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    btn._solidBg = bg

    local icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    icon:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\icon")
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    btn.icon = icon

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.45)
    btn.hl = hl

    local dot = btn:CreateTexture(nil, "OVERLAY", nil, 3)
    dot:SetSize(math.max(6, math.floor(sz * 0.36)), math.max(6, math.floor(sz * 0.36)))
    dot:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    dot:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\dot")
    btn.statusDot = dot

    function btn:SetStatusState(state)
        self._statusState = state or "active"
        if self._statusState == "off" then
            self.statusDot:SetVertexColor(0.55, 0.58, 0.64, 1.0)
            self.icon:SetDesaturated(true)
            self.icon:SetAlpha(0.72)
        elseif self._statusState == "partial" then
            self.statusDot:SetVertexColor(0.98, 0.76, 0.22, 1.0)
            self.icon:SetDesaturated(false)
            self.icon:SetAlpha(0.94)
        else
            self.statusDot:SetVertexColor(0.24, 0.88, 0.46, 1.0)
            self.icon:SetDesaturated(false)
            self.icon:SetAlpha(1.0)
        end
    end

    function btn:RefreshTheme()
        local p = Theme:GetPalette()
        local gold = p.textGold or p.accent or { 0.85, 0.68, 0.28, 1.0 }
        local wbg = p.windowBg or { 0.08, 0.08, 0.09, 1.0 }
        self._solidBg:SetVertexColor(wbg[1], wbg[2], wbg[3], 1.0)
        if self.SetBackdrop then
            self:SetBackdrop({
                bgFile = WHITE8X8,
                edgeFile = WHITE8X8,
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            self:SetBackdropColor(wbg[1], wbg[2], wbg[3], 1.0)
            self:SetBackdropBorderColor(gold[1], gold[2], gold[3], 0.92)
        end
        if type(opts.getStatusState) == "function" then
            self:SetStatusState(opts.getStatusState())
        else
            self:SetStatusState(self._statusState or "active")
        end
    end

    btn:SetScript("OnEnter", function(selfBtn)
        local p = Theme:GetPalette()
        local gold = p.textGold or p.accent or { 0.95, 0.78, 0.35 }
        if selfBtn.SetBackdropBorderColor then
            selfBtn:SetBackdropBorderColor(1.0, 0.88, 0.42, 1.0)
        end
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, opts.tooltipAnchor or "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("SocialCentral — " .. tostring(opts.title or L["Official Window"]), gold[1], gold[2], gold[3])
        if type(opts.getTooltipLines) == "function" then
            local lines = opts.getTooltipLines()
            if type(lines) == "table" then
                for _, ln in ipairs(lines) do
                    if type(ln) == "table" then
                        if ln.right ~= nil then
                            GameTooltip:AddDoubleLine(tostring(ln.left or ""), tostring(ln.right or ""), ln.lr or 0.78, ln.lg or 0.84, ln.lb or 0.92, ln.rr or 0.92, ln.rg or 0.96, ln.rb or 1.0)
                        else
                            GameTooltip:AddLine(tostring(ln.text or ln[1] or ""), ln.r or 0.85, ln.g or 0.88, ln.b or 0.94, true)
                        end
                    elseif type(ln) == "string" and ln ~= "" then
                        GameTooltip:AddLine(ln, 0.85, 0.88, 0.94, true)
                    end
                end
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click: Toggle features or disable here"], 0.48, 0.86, 1.0, true)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function(selfBtn)
        selfBtn:RefreshTheme()
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then
            GameTooltip:Hide()
        end
    end)

    btn:SetScript("OnClick", function(selfBtn, mouseBtn)
        if GameTooltip and GameTooltip:IsOwned(selfBtn) then
            GameTooltip:Hide()
        end
        if MenuUtil and MenuUtil.CreateContextMenu and type(opts.buildMenu) == "function" then
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                opts.buildMenu(root, selfBtn, mouseBtn)
            end)
        elseif type(opts.onFallbackClick) == "function" then
            opts.onFallbackClick(selfBtn, mouseBtn)
        elseif ns.Settings and ns.Settings.Open then
            ns.Settings:Open()
        end
    end)

    btn:RefreshTheme()
    Theme:RegisterListener(function()
        if btn and btn.RefreshTheme then
            btn:RefreshTheme()
        end
    end)
    return btn
end

local hookedBlizzMenuFrames = setmetatable({}, { __mode = "k" })

local function IsSocialCentralMenuOwner(owner)
    local cur = owner
    local depth = 0
    while cur and depth < 16 do
        depth = depth + 1
        if cur.IsForbidden and cur:IsForbidden() then
            return false
        end
        if Theme._overlayModals and Theme._overlayModals[cur] == true then
            return true
        end
        local name = cur.GetName and cur:GetName() or nil
        if type(name) == "string" and name:sub(1, 13) == "SocialCentral" then
            return true
        end
        if cur == _G.SocialCentralFrame
            or cur == _G.SocialCentralQuickReplyFrame
            or cur == _G.SocialCentralLFGStandaloneHost
            or cur == _G.SocialCentralSettingsFrame
        then
            return true
        end
        cur = cur.GetParent and cur:GetParent() or nil
    end
    return false
end

function Theme:GetHighestShownOverlayLevel()
    local best = 0
    if not self._overlayModals then
        return 0
    end
    for m in pairs(self._overlayModals) do
        if m and m.IsShown and m:IsShown()
            and m.GetFrameStrata and m:GetFrameStrata() == "FULLSCREEN_DIALOG"
            and m.GetFrameLevel
        then
            local okLvl, lvl = pcall(m.GetFrameLevel, m)
            if okLvl and type(lvl) == "number" and lvl > best then
                best = lvl
            end
        end
    end
    return best
end

local function ElevateSingleMenuFrame(mf, minLevel)
    if not mf then return false end
    if (mf.IsForbidden and mf:IsForbidden()) or (mf.IsProtected and mf:IsProtected()) then
        return false
    end
    if mf.IsShown and not mf:IsShown() then
        return false
    end
    if mf.GetFrameStrata and mf:GetFrameStrata() ~= "FULLSCREEN_DIALOG" and mf.SetFrameStrata then
        pcall(mf.SetFrameStrata, mf, "FULLSCREEN_DIALOG")
    end
    local okCur, curLvl = pcall(mf.GetFrameLevel, mf)
    curLvl = (okCur and type(curLvl) == "number") and curLvl or 0
    if curLvl < minLevel and mf.SetFrameLevel then
        pcall(mf.SetFrameLevel, mf, minLevel)
    end
    if mf.Raise then
        pcall(mf.Raise, mf)
    end
    if not hookedBlizzMenuFrames[mf] and mf.HookScript then
        hookedBlizzMenuFrames[mf] = true
        mf:HookScript("OnShow", function(selfMf)
            local mgr = _G.Menu and _G.Menu.GetManager and _G.Menu.GetManager() or nil
            local anyOverlay = Theme:GetHighestShownOverlayLevel() > 0
            if Theme._lastMenuWasSocialCentral or anyOverlay or (mgr and mgr.IsAnyMenuOpen and mgr:IsAnyMenuOpen() and (Theme._menuElevationUntil or 0) >= ((_G.GetTime and _G.GetTime()) or 0)) then
                Theme:ElevateOpenBlizzardMenus()
            end
        end)
    end
    return true
end

local function LooksLikeBlizzardMenuContainer(frame, openMenu)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) or (frame.IsProtected and frame:IsProtected()) then
        return false
    end
    if openMenu and frame == openMenu then
        return true
    end
    if type(frame.GetMenuDescription) == "function" or frame.menuDescription ~= nil or type(frame.SetMenuDescription) == "function" then
        return true
    end
    local name = frame.GetName and frame:GetName() or nil
    if type(name) == "string" and name:match("^DropDownList%d+$") then
        return true
    end
    return false
end

local function ElevateMenuSubtree(rootFrame, baseLevel, depth, seen)
    if not rootFrame or seen[rootFrame] or depth > 6 then
        return
    end
    seen[rootFrame] = true
    ElevateSingleMenuFrame(rootFrame, baseLevel + (depth * 20))
    if rootFrame.GetChildren then
        local children = { rootFrame:GetChildren() }
        for _, child in ipairs(children) do
            if child and not seen[child] and child.IsShown and child:IsShown() and LooksLikeBlizzardMenuContainer(child, nil) then
                ElevateMenuSubtree(child, baseLevel, depth + 1, seen)
            end
        end
    end
end

--- Raise open Blizzard Menu / DropDownList popups (and submenus) above all SocialCentral modals.
function Theme:ElevateOpenBlizzardMenus()
    local topOverlay = self:GetHighestShownOverlayLevel()
    local baseLevel = math.min(9700, math.max(9500, topOverlay + 120))
    local seen = {}
    local mgr = _G.Menu and _G.Menu.GetManager and _G.Menu.GetManager() or nil
    local openMenu = (mgr and mgr.GetOpenMenu and mgr:GetOpenMenu()) or nil

    if openMenu and openMenu.IsShown and openMenu:IsShown() then
        ElevateMenuSubtree(openMenu, baseLevel, 0, seen)
    end
    if mgr and type(mgr.openMenus) == "table" then
        for idx, om in ipairs(mgr.openMenus) do
            if om and om.IsShown and om:IsShown() then
                ElevateMenuSubtree(om, baseLevel, math.max(0, idx - 1), seen)
            end
        end
    end
    if _G.UIParent and _G.UIParent.GetChildren then
        local depth = (openMenu and 1) or 0
        local uChildren = { _G.UIParent:GetChildren() }
        for _, child in ipairs(uChildren) do
            if child and not seen[child] and child.IsShown and child:IsShown() and LooksLikeBlizzardMenuContainer(child, openMenu) then
                ElevateMenuSubtree(child, baseLevel, depth, seen)
                depth = depth + 1
            end
        end
    end
    for i = 1, 3 do
        local ddl = _G["DropDownList" .. i]
        if ddl and ddl.IsShown and ddl:IsShown() then
            ElevateSingleMenuFrame(ddl, baseLevel + ((i - 1) * 20))
        end
    end
end

local function OnBlizzardMenuTriggered(owner)
    local isSC = IsSocialCentralMenuOwner(owner) or (Theme:GetHighestShownOverlayLevel() > 0)
    Theme._lastMenuWasSocialCentral = isSC and true or false
    if not isSC then
        return
    end
    Theme._menuElevationUntil = ((_G.GetTime and _G.GetTime()) or 0) + 2.0
    Theme:ElevateOpenBlizzardMenus()
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, function()
            if Theme._lastMenuWasSocialCentral or Theme:GetHighestShownOverlayLevel() > 0 then
                Theme:ElevateOpenBlizzardMenus()
            end
        end)
    end
end

function Theme:InstallGlobalMenuElevationHooks()
    if self._menuHooksInstalled then
        return
    end
    self._menuHooksInstalled = true
    if type(_G.hooksecurefunc) ~= "function" then
        return
    end
    if _G.MenuUtil and type(_G.MenuUtil.CreateContextMenu) == "function" then
        self._hookedCreateContextMenu = true
        _G.hooksecurefunc(_G.MenuUtil, "CreateContextMenu", function(owner)
            OnBlizzardMenuTriggered(owner)
        end)
    end
    local mgr = _G.Menu and _G.Menu.GetManager and _G.Menu.GetManager() or nil
    if mgr then
        if type(mgr.OpenContextMenu) == "function" then
            self._hookedMgrOpenContextMenu = true
            _G.hooksecurefunc(mgr, "OpenContextMenu", function(_, owner)
                OnBlizzardMenuTriggered(owner)
            end)
        end
        if type(mgr.OpenMenu) == "function" then
            self._hookedMgrOpenMenu = true
            _G.hooksecurefunc(mgr, "OpenMenu", function(_, owner)
                OnBlizzardMenuTriggered(owner)
            end)
        end
    end
    if type(_G.ToggleDropDownMenu) == "function" then
        self._hookedToggleDropDownMenu = true
        _G.hooksecurefunc("ToggleDropDownMenu", function(_, _, dropDownFrame)
            OnBlizzardMenuTriggered(dropDownFrame)
        end)
    end
end

Theme:InstallGlobalMenuElevationHooks()

if ns.RegisterEvent then
    ns.RegisterEvent(Theme, "PLAYER_LOGIN", function()
        if not Theme._hookedCreateContextMenu and _G.MenuUtil and type(_G.MenuUtil.CreateContextMenu) == "function" and type(_G.hooksecurefunc) == "function" then
            Theme._hookedCreateContextMenu = true
            _G.hooksecurefunc(_G.MenuUtil, "CreateContextMenu", function(owner)
                OnBlizzardMenuTriggered(owner)
            end)
        end
        local mgr = _G.Menu and _G.Menu.GetManager and _G.Menu.GetManager() or nil
        if mgr and type(_G.hooksecurefunc) == "function" then
            if not Theme._hookedMgrOpenContextMenu and type(mgr.OpenContextMenu) == "function" then
                Theme._hookedMgrOpenContextMenu = true
                _G.hooksecurefunc(mgr, "OpenContextMenu", function(_, owner)
                    OnBlizzardMenuTriggered(owner)
                end)
            end
            if not Theme._hookedMgrOpenMenu and type(mgr.OpenMenu) == "function" then
                Theme._hookedMgrOpenMenu = true
                _G.hooksecurefunc(mgr, "OpenMenu", function(_, owner)
                    OnBlizzardMenuTriggered(owner)
                end)
            end
        end
    end)
    ns.RegisterEvent(Theme, "DISPLAY_SIZE_CHANGED", function()
        Theme:QueueViewportChanged()
    end)
    ns.RegisterEvent(Theme, "UI_SCALE_CHANGED", function()
        Theme:QueueViewportChanged()
    end)
end
