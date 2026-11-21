local _, ns = ...

local L = ns.L
local Theme = {}
ns.Theme = Theme

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local listeners = {}

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
    for _, fn in ipairs(listeners) do
        pcall(fn, self:GetPalette())
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
    local isLargeFrame = (not frame._scIsListRow) and (fw == 0 or fw >= 100)
    local wantSheen = isLargeFrame and (kind == "header" or kind == "surface" or kind == "window")
    local wantBevel = isLargeFrame and (kind == "header" or kind == "surface")
    local wantInsetStone = (kind == "inset" and isBlizz and not frame._scNoStone and fw >= 120 and fh >= 80 and HasAtlas("groupfinder-background"))

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
                ApplySafeGradient(frame._scCardSheen, "VERTICAL", 0, 0, 0, 0, 0.52, 0.40, 0.16, 0.18)
            else
                ApplySafeGradient(frame._scCardSheen, "VERTICAL", 0, 0, 0, 0, acc[1] * 0.24 + 0.06, acc[2] * 0.24 + 0.06, acc[3] * 0.24 + 0.08, 0.28)
            end
        elseif kind == "surface" then
            frame._scCardSheen:SetHeight(48)
            ApplySafeGradient(frame._scCardSheen, "VERTICAL", 0, 0, 0, 0, 1, 1, 1, isBlizz and 0.03 or 0.045)
        else
            frame._scCardSheen:SetHeight(56)
            ApplySafeGradient(frame._scCardSheen, "VERTICAL", 0, 0, 0, 0, acc[1] * 0.3 + 0.05, acc[2] * 0.3 + 0.05, acc[3] * 0.3 + 0.08, isBlizz and 0.04 or 0.14)
        end
        frame._scCardSheen:Show()
    elseif frame._scCardSheen then
        frame._scCardSheen:Hide()
    end

    if wantBevel then
        if not frame._scTopBevel then
            local bev = frame:CreateTexture(nil, "BORDER", nil, 2)
            bev:SetHeight(1)
            bev:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -2)
            bev:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -2)
            frame._scTopBevel = bev
        end
        if isBlizz or p.key == "native" then
            frame._scTopBevel:SetColorTexture(0.95, 0.80, 0.38, 0.24)
        else
            frame._scTopBevel:SetColorTexture(0.65, 0.85, 1.0, 0.16)
        end
        frame._scTopBevel:Show()
    elseif frame._scTopBevel then
        frame._scTopBevel:Hide()
    end

    if wantInsetStone then
        if not frame._scInsetStone then
            local st = frame:CreateTexture(nil, "BACKGROUND", nil, -4)
            st:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
            st:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
            st:SetAtlas("groupfinder-background", false)
            frame._scInsetStone = st
        end
        frame._scInsetStone:SetVertexColor(0.36, 0.34, 0.32, 0.42)
        frame._scInsetStone:Show()
    elseif frame._scInsetStone then
        frame._scInsetStone:Hide()
    end
end

--- Add a clean tapered gold/accent horizontal rule directly below a section heading.
function Theme:DecorateSectionHeader(parent, labelFs, lineWidth)
    if not (parent and labelFs) then return nil end
    local p = self:GetPalette()
    local isBlizz = self:IsBlizzard(p) or p.key == "native"
    local r, g, b = 0.88, 0.72, 0.28
    if not isBlizz and p.accentBorder then
        r, g, b = p.accentBorder[1], p.accentBorder[2], p.accentBorder[3]
    end
    local halfW = math.floor((lineWidth or 280) * 0.5)
    local sep = CreateFrame("Frame", nil, parent)
    sep:SetHeight(2)
    sep:SetPoint("TOPLEFT", labelFs, "BOTTOMLEFT", 0, -4)
    sep:SetWidth(halfW * 2)

    local leftTex = sep:CreateTexture(nil, "ARTWORK")
    leftTex:SetPoint("LEFT", sep, "LEFT", 0, 0)
    leftTex:SetSize(halfW, 1)
    ApplySafeGradient(leftTex, "HORIZONTAL", r, g, b, 0.72, r, g, b, 0.22)

    local rightTex = sep:CreateTexture(nil, "ARTWORK")
    rightTex:SetPoint("LEFT", leftTex, "RIGHT", 0, 0)
    rightTex:SetSize(halfW, 1)
    ApplySafeGradient(rightTex, "HORIZONTAL", r, g, b, 0.22, r, g, b, 0.0)

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
    if kind == "window" then
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

        if kind == "row" or kind == "rowAlt" then
            if frame._foreverSurfaceStone then
                frame._foreverSurfaceStone:Hide()
            end
            if frame._foreverRowBg then
                frame._foreverRowBg:Hide()
            end
            SyncDepthPolish(frame, "none", p, true)
            local bgRow = (kind == "row") and { 0.085, 0.078, 0.070 } or { 0.055, 0.050, 0.045 }
            ApplyBackdropSpec(frame, FLAT_BACKDROP_SPEC, bgRow, nil, false)
            frame:SetBackdropColor(bgRow[1], bgRow[2], bgRow[3], (kind == "row") and 0.42 or 0.25)
            if frame.GetObjectType and frame:GetObjectType() == "Button" and not frame._foreverRowHl then
                local hl = frame:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(frame)
                hl:SetColorTexture(0.95, 0.78, 0.28, 0.10)
                frame._foreverRowHl = hl
            end
            return
        end

        if kind == "surface" and frame._scIsListRow then
            ApplyBackdropSpec(frame, FLAT_BACKDROP_SPEC, { 0.22, 0.17, 0.08 }, nil, false)
            frame:SetBackdropColor(0.22, 0.17, 0.08, 0.55)
            if frame._foreverRowBg then frame._foreverRowBg:Hide() end
            SyncDepthPolish(frame, "none", p, true)
            return
        end

        if frame._foreverRowBg then
            frame._foreverRowBg:Hide()
        end

        if kind == "window" then
            if frame._foreverSurfaceStone then
                frame._foreverSurfaceStone:Hide()
            end
            ApplyBackdropSpec(frame, BLIZZ_DIALOG_BACKDROP, { 0.08, 0.075, 0.07 }, { 0.86, 0.80, 0.68 }, true)
            SyncDepthPolish(frame, "none", p, true)
            return
        elseif kind == "header" then
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
        elseif kind == "inset" then
            if frame._foreverSurfaceStone then
                frame._foreverSurfaceStone:Hide()
            end
            ApplyBackdropSpec(frame, BACKDROP_SPEC, { 0.048, 0.045, 0.042 }, { 0.36, 0.30, 0.19 }, true)
            SyncDepthPolish(frame, "inset", p, true)
            return
        elseif kind == "surface" then
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

    ApplyBackdropSpec(frame, border and BACKDROP_SPEC or FLAT_BACKDROP_SPEC, bg, border, true)
    SyncDepthPolish(frame, resolvedKind, p, false)
end

local function SyncBlizzTextOffset(btn, xOff, yOff)
    if not btn or not btn.label then
        return
    end
    if btn.SetClipsChildren and not btn._scClipsInit then
        btn._scClipsInit = true
        btn:SetClipsChildren(true)
    end
    local w = btn._scAutoFitW or (btn:GetWidth() or 0)
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
        parent:SetClipsChildren(true)
    end
    local sig = padX .. ":" .. (xOff or 0) .. ":" .. (yOff or 0)
    if btn._scTextOffsetSig == sig and btn._scTextOffsetParent == parent then
        return
    end
    btn._scTextOffsetSig = sig
    btn._scTextOffsetParent = parent
    btn.label:ClearAllPoints()
    btn.label:SetPoint("LEFT", parent, "LEFT", padX + xOff, yOff)
    btn.label:SetPoint("RIGHT", parent, "RIGHT", -padX + xOff, yOff)
    if not btn._scLabelFmtInit then
        btn._scLabelFmtInit = true
        btn.label:SetJustifyH("CENTER")
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
    if isTab then
        if btn._blizzBtn then
            btn._blizzBtn:Hide()
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

    if btn._blizzTabFrame then
        btn._blizzTabFrame:Hide()
    end
    if not btn._blizzBtn and not btn._blizzBtnFailed then
        local ok, vis = pcall(CreateFrame, "Button", nil, btn, "UIPanelButtonTemplate")
        if ok and vis then
            vis:EnableMouse(false)
            vis:SetText("")
            if vis.Text then vis.Text:SetText("") end
            vis._scIsInternalBtnLayer = true
            btn._blizzBtn = vis
        else
            btn._blizzBtnFailed = true
        end
    end
    return btn._blizzBtn, "button"
end

local function TintBlizzButtonTextures(vis, desat, r, g, b)
    local regions = { vis.Left, vis.Middle, vis.Right }
    for i = 1, 3 do
        local tex = regions[i]
        if tex and tex.SetDesaturated then
            pcall(tex.SetDesaturated, tex, desat)
            pcall(tex.SetVertexColor, tex, r, g, b)
        end
    end
    local norm = vis.GetNormalTexture and vis:GetNormalTexture()
    if norm and norm.SetDesaturated then
        pcall(norm.SetDesaturated, norm, desat)
        pcall(norm.SetVertexColor, norm, r, g, b)
    end
    local push = vis.GetPushedTexture and vis:GetPushedTexture()
    if push and push.SetDesaturated then
        pcall(push.SetDesaturated, push, desat)
        pcall(push.SetVertexColor, push, r, g, b)
    end
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
    if btn._blizzBtn and btn._blizzBtn.SetFrameLevel then
        btn._blizzBtn:SetFrameLevel(bLvl + 1)
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
    if root._textLayer or root._blizzTabFrame or root._blizzBtn then
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
    local w = btn:GetWidth() or 0
    btn._scThemeKey = p.key

    Theme:SyncButtonLayers(btn)
    SyncBlizzTextOffset(btn, 0, 0)

    local useBlizzPlate = isBlizz and (variant == "tab" or ((variant == "primary" or variant == "danger") and w >= 26))
    if useBlizzPlate then
        local vis, kind = EnsureBlizzButtonVisual(btn, variant == "tab")
        if vis then
            if btn._scNavIndicator then btn._scNavIndicator:Hide() end
            if btn._scAppliedBackdrop ~= nil then
                btn:SetBackdrop(nil)
                btn._scAppliedBackdrop = nil
            end
            Theme:SyncButtonLayers(btn)
            vis:ClearAllPoints()
            if kind == "tab" then
                vis:SetAllPoints(btn)
                if vis._scAppliedBackdrop ~= BACKDROP_SPEC then
                    vis:SetBackdrop(BACKDROP_SPEC)
                    vis._scAppliedBackdrop = BACKDROP_SPEC
                end
                if active then
                    vis:SetBackdropColor(0.14, 0.12, 0.09, 0.98)
                    vis:SetBackdropBorderColor(0.84, 0.66, 0.24, 1)
                    vis._topAccent:SetColorTexture(0.98, 0.80, 0.28, 0.95)
                    vis._topAccent:Show()
                    vis._bottomBridge:SetColorTexture(0.10, 0.09, 0.08, 1)
                    vis._bottomBridge:Show()
                    SyncBlizzTextOffset(btn, 0, 0)
                    if btn.label then
                        btn.label:SetTextColor(1.0, 1.0, 1.0)
                    end
                elseif hovered then
                    vis:SetBackdropColor(0.11, 0.10, 0.09, 0.95)
                    vis:SetBackdropBorderColor(0.66, 0.52, 0.22, 1)
                    vis._topAccent:SetColorTexture(0.82, 0.64, 0.24, 0.65)
                    vis._topAccent:Show()
                    vis._bottomBridge:SetColorTexture(0.36, 0.29, 0.16, 0.9)
                    vis._bottomBridge:Show()
                    SyncBlizzTextOffset(btn, 0, -1)
                    if btn.label then
                        btn.label:SetTextColor(1.0, 0.93, 0.65)
                    end
                else
                    vis:SetBackdropColor(0.07, 0.07, 0.08, 0.90)
                    vis:SetBackdropBorderColor(0.38, 0.30, 0.16, 0.95)
                    vis._topAccent:SetColorTexture(0.55, 0.44, 0.18, 0.28)
                    vis._topAccent:Show()
                    vis._bottomBridge:SetColorTexture(0.32, 0.25, 0.13, 0.85)
                    vis._bottomBridge:Show()
                    SyncBlizzTextOffset(btn, 0, -1)
                    if btn.label then
                        local g = p.textGold or p.text
                        btn.label:SetTextColor(g[1], g[2], g[3])
                    end
                end
            else
                vis:SetAllPoints(btn)
                if not btn:IsEnabled() then
                    vis:Disable()
                    vis:UnlockHighlight()
                    vis:SetAlpha(0.60)
                    TintBlizzButtonTextures(vis, true, 0.38, 0.38, 0.40)
                else
                    vis:Enable()
                    vis:SetAlpha(1.0)
                    if btn._scPushed then
                        vis:SetButtonState("PUSHED")
                    else
                        vis:SetButtonState("NORMAL")
                    end
                    if hovered then
                        vis:LockHighlight()
                    else
                        vis:UnlockHighlight()
                    end
                    if variant == "danger" then
                        TintBlizzButtonTextures(vis, false, hovered and 0.96 or 0.84, 0.38, 0.36)
                    else
                        TintBlizzButtonTextures(vis, false, hovered and 1.12 or 1.02, hovered and 1.06 or 1.0, hovered and 1.02 or 0.96)
                    end
                end
                if btn._scPushed and btn:IsEnabled() then
                    SyncBlizzTextOffset(btn, 1, -1)
                else
                    SyncBlizzTextOffset(btn, 0, 0)
                end
                if btn.label then
                    if not btn:IsEnabled() then
                        btn.label:SetTextColor(p.textDim[1], p.textDim[2], p.textDim[3])
                    elseif active or hovered then
                        btn.label:SetTextColor(1, 1, 1)
                    elseif variant == "danger" then
                        btn.label:SetTextColor(1.0, 0.82, 0.78)
                    else
                        btn.label:SetTextColor(1.0, 0.92, 0.68)
                    end
                end
            end
            vis:Show()
            if btn._scBtnGloss then btn._scBtnGloss:Hide() end
            return
        end
    end

    if btn._blizzBtn then btn._blizzBtn:Hide() end
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
    if not btn:IsEnabled() then
        bg = isBlizz and { 0.07, 0.065, 0.06, 0.88 } or p.insetBg
        border = isBlizz and { 0.24, 0.21, 0.16, 0.75 } or p.surfaceBorder
        textColor = p.textDim
    elseif variant == "primary" or (active and not isBlizz) then
        bg = hovered and p.accent or p.accentDim
        border = p.accentBorder
        textColor = p.text
    elseif active and isBlizz then
        bg = hovered and { 0.28, 0.21, 0.09, 0.98 } or { 0.21, 0.16, 0.07, 0.96 }
        border = { 0.90, 0.72, 0.26, 1.0 }
        textColor = { 1.0, 0.95, 0.78 }
    elseif variant == "danger" then
        bg = hovered and p.dangerHoverBg or p.dangerBg
        border = p.dangerBorder
        textColor = p.text
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

    ApplyBackdropSpec(btn, BACKDROP_SPEC, bg, border, false)
    local bw = btn:GetWidth() or 0
    local bh = btn:GetHeight() or 0
    if variant ~= "ghost" and btn:IsEnabled() and bw >= 32 and bh >= 18 then
        if not btn._scBtnGloss then
            local gloss = btn:CreateTexture(nil, "ARTWORK", nil, 1)
            gloss:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -1)
            gloss:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -1)
            btn._scBtnGloss = gloss
        end
        if variant == "tab" and active then
            btn._scBtnGloss:SetHeight(2)
            local ac = p.accentBorder or { 0.35, 0.78, 1.0 }
            btn._scBtnGloss:SetColorTexture(ac[1], ac[2], ac[3], 0.95)
        else
            btn._scBtnGloss:SetHeight(1)
            btn._scBtnGloss:SetColorTexture(1, 0.95, 0.82, (variant == "primary" or hovered) and 0.20 or 0.09)
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
        if textTarget and textTarget.SetTextColor then
            textTarget:SetTextColor(textColor[1], textColor[2], textColor[3])
        end
    end
end

--- Apply responsive theme visuals and placeholder updates to a Theme EditBox.
function Theme:StyleEditBox(box)
    if not box then
        return
    end
    ApplyInputBackdrop(box, box._scFocused, box._scHovered, box)
    if box.placeholder then
        local p = self:GetPalette()
        box.placeholder:SetTextColor(p.textDim[1], p.textDim[2], p.textDim[3])
    end
end

--- Create a crisp, theme-aware, responsively padded EditBox (replaces inconsistent InputBoxTemplate 9-slices).
function Theme:InstallEditBoxLinkHook()
    if self._editBoxLinkHooked then return end
    self._editBoxLinkHooked = true
    if type(_G.ChatEdit_InsertLink) == "function" then
        hooksecurefunc("ChatEdit_InsertLink", function(text)
            local box = Theme._focusedEditBox
            if not (box and box.HasFocus and box:HasFocus() and box:IsVisible()) then
                return
            end
            if ns.Safe and ns.Safe.IsSecret and ns.Safe.IsSecret(text) then
                return
            end
            if type(text) ~= "string" or text == "" then
                return
            end
            local inserted = text
            if box._scInsertLinkMode ~= "full" then
                inserted = text:gsub("|c%x%x%x%x%x%x%x%x", "")
                    :gsub("|r", "")
                    :gsub("|H[^|]+|h%[?([^%]]*)%]?|h", "%1")
                    :gsub("^%s+", "")
                    :gsub("%s+$", "")
            end
            if inserted ~= "" and box.Insert then
                box:Insert(inserted)
            end
        end)
    end
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
local updatePopup
local movableRegistry = {}

local function CanDragWindow(win, opts)
    if not win then return false end
    if win._scLocked or win._scSizing then return false end
    if UIParent and win.GetParent and win:GetParent() ~= UIParent then return false end
    if opts and type(opts.locked) == "function" and opts.locked() then return false end
    if opts and opts.combatLock and InCombatLockdown and InCombatLockdown() then
        return false
    end
    return true
end

local function SaveWindowCenterOffset(win, posKey, opts)
    if not (win and posKey and ns.db) then return end
    if UIParent and win.GetParent and win:GetParent() ~= UIParent then return end
    if type(ns.db.windowPositions) ~= "table" then
        ns.db.windowPositions = {}
    end
    local scale = win:GetScale() or 1
    if scale <= 0 then scale = 1 end
    local cx, cy = win:GetCenter()
    local ux, uy = UIParent and UIParent:GetCenter()
    local anchor = opts and opts.anchor or "CENTER"

    if anchor == "TOP" then
        local top = win:GetTop()
        local utop = UIParent and UIParent:GetTop()
        if cx and top and ux and utop and cx == cx and top == top then
            ns.db.windowPositions[posKey] = {
                anchor = "TOP",
                dx = math.floor((cx * scale - ux) + 0.5),
                dy = math.floor((top * scale - utop) + 0.5),
            }
        end
    else
        if cx and cy and ux and uy and cx == cx and cy == cy then
            ns.db.windowPositions[posKey] = {
                anchor = "CENTER",
                dx = math.floor((cx * scale - ux) + 0.5),
                dy = math.floor((cy * scale - uy) + 0.5),
            }
        end
    end
end

function Theme:RestoreWindowPosition(win, posKey, combatLock, opts)
    if not win or win._scLocked then
        return false
    end
    if UIParent and win.GetParent and win:GetParent() ~= UIParent then
        return false
    end
    if not (posKey and ns.db and type(ns.db.windowPositions) == "table") then
        return false
    end
    local saved = ns.db.windowPositions[posKey]
    if type(saved) ~= "table" or saved.dx == nil or saved.dy == nil then
        return false
    end
    if combatLock and InCombatLockdown and InCombatLockdown() then
        return false
    end
    local uw, uh = UIParent and UIParent:GetSize()
    local ww, wh = win:GetSize()
    local scale = win:GetScale() or 1
    if scale <= 0 then scale = 1 end
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

function Theme:AttachDragHandle(handle, win)
    if not (handle and win and win._scBeginDrag and win._scEndDrag) then
        return
    end
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    if handle.HookScript and not handle._scHandleHooked then
        handle._scHandleHooked = true
        handle:HookScript("OnMouseDown", function(_, btn)
            if btn == "LeftButton" and not (win._scCombatLock and InCombatLockdown and InCombatLockdown()) and win.Raise then
                pcall(win.Raise, win)
            end
        end)
        handle:HookScript("OnMouseUp", function(_, btn)
            if btn == "LeftButton" and win._scDragging then
                win._scEndDrag()
            end
        end)
        handle:HookScript("OnDragStart", function() win._scBeginDrag() end)
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

    local function BeginDrag()
        if not CanDragWindow(win, opts) then
            return
        end
        if win._scDragging then
            pcall(win.StopMovingOrSizing, win)
            win._scDragging = false
        end
        win:SetMovable(true)
        win:SetClampedToScreen(true)
        if win:GetParent() == UIParent and win.GetNumPoints and win:GetNumPoints() > 1 then
            local cx, cy = win:GetCenter()
            local ux, uy = UIParent and UIParent:GetCenter()
            if cx and cy and ux and uy then
                local scale = win:GetScale() or 1
                if scale <= 0 then scale = 1 end
                win:ClearAllPoints()
                win:SetPoint("CENTER", UIParent, "CENTER", (cx * scale - ux) / scale, (cy * scale - uy) / scale)
            end
        end
        win._scDragging = true
        if not (opts.combatLock and InCombatLockdown and InCombatLockdown()) and win.Raise then
            pcall(win.Raise, win)
        end
        local ok = pcall(win.StartMoving, win)
        if not ok then
            win._scDragging = false
        end
    end

    local function EndDrag()
        if not win._scDragging then
            if win._scSizing then
                win._scSizing = false
                pcall(win.StopMovingOrSizing, win)
            end
            return
        end
        win._scDragging = false
        pcall(win.StopMovingOrSizing, win)
        SaveWindowCenterOffset(win, opts.key, opts)
        if type(opts.onStop) == "function" then
            pcall(opts.onStop, win)
        end
    end

    win._scCombatLock = opts.combatLock and true or false
    win._scBeginDrag = BeginDrag
    win._scEndDrag = EndDrag
    win._scSavePosition = function()
        SaveWindowCenterOffset(win, opts.key, opts)
    end

    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    if not win._scMovableHooked then
        win._scMovableHooked = true
        win:HookScript("OnMouseDown", function(f, btn)
            if btn == "LeftButton" and not (opts.combatLock and InCombatLockdown and InCombatLockdown()) and f.Raise then
                pcall(f.Raise, f)
            end
        end)
        win:HookScript("OnMouseUp", function(_, btn)
            if btn == "LeftButton" and win._scDragging then
                EndDrag()
            end
        end)
        win:HookScript("OnDragStart", BeginDrag)
        win:HookScript("OnDragStop", EndDrag)
        win:HookScript("OnHide", EndDrag)
        win:HookScript("OnShow", function(f)
            if opts.key then
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
        if type(ns.db.windowPositions) == "table" then
            ns.db.windowPositions[key] = nil
        end
        if key == "main" and type(ns.db.window) == "table" then
            ns.db.window.point = nil
            ns.db.window.relativePoint = nil
            ns.db.window.x = nil
            ns.db.window.y = nil
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
        ns.db.windowPositions = {}
        if type(ns.db.window) == "table" then
            ns.db.window.point = nil
            ns.db.window.relativePoint = nil
            ns.db.window.x = nil
            ns.db.window.y = nil
        end
    end
    for key in pairs(movableRegistry) do
        self:ResetWindowPosition(key, true)
    end
    ns:Print(L["All window positions reset to center."])
    return true
end

--- Configure any shared modal/popup to sit above all native & World Map hosts with a 100% opaque backing.
function Theme:PrepareTopOverlayModal(m, minLevel)
    if not m then return end
    if m.GetParent and m:GetParent() ~= UIParent then
        m:SetParent(UIParent)
    end
    local mapShown = _G.WorldMapFrame and _G.WorldMapFrame.IsShown and _G.WorldMapFrame:IsShown()
    local targetLevel = mapShown and math.max(minLevel or 850, 2750) or math.max(minLevel or 850, 840)
    targetLevel = math.min(9200, targetLevel)
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

--- Display a modal help card explaining what an option does and how to use it.
function Theme:ShowHelpPopup(title, whatText, howText)
    if not helpPopup then
        local m = CreateFrame("Frame", "SocialCentralHelpPopup", UIParent, "BackdropTemplate")
        m:SetSize(430, 230)
        m:SetPoint("CENTER")
        self:PrepareTopOverlayModal(m, 860)
        self:MakeMovable(m, { key = "helpPopup" })
        table.insert(UISpecialFrames, "SocialCentralHelpPopup")

        m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        m.title:SetPoint("TOPLEFT", 16, -14)
        m.title:SetPoint("TOPRIGHT", -36, -14)
        m.title:SetJustifyH("LEFT")

        local topCloseBtn = self:CreateButton(m, 22, 20, "X", "default")
        topCloseBtn:SetPoint("TOPRIGHT", -10, -10)
        topCloseBtn:SetScript("OnClick", function() m:Hide() end)
        m.topCloseBtn = topCloseBtn

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
                self:StyleButton(m.topCloseBtn, "default")
                self:StyleButton(m.closeBtn, "primary")
            end
        end)

        helpPopup = m
    end

    self:PrepareTopOverlayModal(helpPopup, 860)
    self:ApplyBackdrop(helpPopup, "window")
    self:StyleButton(helpPopup.topCloseBtn, "default")
    self:StyleButton(helpPopup.closeBtn, "primary")
    helpPopup.title:SetText(title or L["Help"])
    helpPopup.body:SetText(
        "|cff58a6ff" .. L["What it does:"] .. "|r\n" .. (whatText or "") ..
        "\n\n|cff4ade80" .. L["How to use:"] .. "|r\n" .. (howText or "")
    )
    helpPopup:Show()
    if helpPopup.Raise then helpPopup:Raise() end
end

--- Create a standardized '?' help micro-button beside an option or feature bar.
function Theme:CreateHelpButton(parent, title, whatText, howText, size)
    local sz = size or 16
    local btn = self:CreateButton(parent, sz, sz, "?", "ghost")
    btn:SetHitRectInsets(-3, -3, -3, -3)

    local ring = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    ring:SetAllPoints()
    ring:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\dot")
    ring:SetVertexColor(0.28, 0.24, 0.17, 0.65)
    btn._scHelpRing = ring

    local inner = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\dot")
    inner:SetVertexColor(0.09, 0.085, 0.075, 0.95)
    btn._scHelpInner = inner

    if btn.label then
        btn.label:SetTextColor(0.84, 0.72, 0.38)
    end

    btn:HookScript("OnEnter", function(selfBtn)
        ring:SetVertexColor(0.95, 0.76, 0.26, 0.95)
        inner:SetVertexColor(0.18, 0.14, 0.08, 0.98)
        if selfBtn.label then
            selfBtn.label:SetTextColor(1.0, 0.95, 0.72)
        end
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
    btn:HookScript("OnLeave", function(selfBtn)
        ring:SetVertexColor(0.28, 0.24, 0.17, 0.65)
        inner:SetVertexColor(0.09, 0.085, 0.075, 0.95)
        if selfBtn.label then
            selfBtn.label:SetTextColor(0.84, 0.72, 0.38)
        end
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function()
        GameTooltip:Hide()
        Theme:ShowHelpPopup(title, whatText, howText)
    end)
    self:RegisterListener(function()
        if btn:IsVisible() then
            self:StyleButton(btn, "ghost")
        else
            btn._scThemeKey = nil
        end
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

--- First-run visual theme chooser showing side-by-side live miniature examples of Blizzard Official vs Modern Theme.
function Theme:ShowThemeWelcomePicker()
    if not themeWelcomePopup then
        local m = CreateFrame("Frame", "SocialCentralThemePicker", UIParent, "BackdropTemplate")
        m:SetSize(664, 464)
        m:SetPoint("CENTER")
        self:PrepareTopOverlayModal(m, 880)
        self:MakeMovable(m, { key = "themePicker" })
        table.insert(UISpecialFrames, "SocialCentralThemePicker")

        local closeBtn = self:CreateButton(m, 24, 22, "X", "default")
        closeBtn:SetPoint("TOPRIGHT", -14, -14)
        m.closeBtn = closeBtn

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
        m.title:SetPoint("TOPRIGHT", closeBtn, "LEFT", -10, 0)
        m.title:SetJustifyH("LEFT")
        m.title:SetWordWrap(false)
        m.title:SetText(L["Choose Your SocialCentral Design"])

        m.sub = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        m.sub:SetPoint("TOPLEFT", 20, -40)
        m.sub:SetPoint("TOPRIGHT", -20, -40)
        m.sub:SetJustifyH("LEFT")
        m.sub:SetWordWrap(true)
        m.sub:SetText(L["Select which theme to use as your default visual style. You can switch anytime from the header or Settings."])

        local function BuildSampleCard(isBlizzSample, xAnchorPoint, xOffset)
            local card = CreateFrame("Frame", nil, m, "BackdropTemplate")
            card:SetSize(302, 356)
            card:SetPoint(xAnchorPoint, m, xAnchorPoint, xOffset, -76)
            card:EnableMouse(true)

            local bgSpec = BACKDROP_SPEC
            local cardBg = isBlizzSample and { 0.11, 0.095, 0.075, 1.0 } or { 0.07, 0.08, 0.11, 1.0 }
            local baseBorder = isBlizzSample and { 0.68, 0.56, 0.30, 1.0 } or { 0.24, 0.34, 0.46, 0.95 }
            local hoverBorder = isBlizzSample and { 1.0, 0.82, 0.22, 1.0 } or { 0.35, 0.78, 1.0, 1.0 }
            card:SetBackdrop(bgSpec)
            card:SetBackdropColor(cardBg[1], cardBg[2], cardBg[3], cardBg[4])
            card:SetBackdropBorderColor(baseBorder[1], baseBorder[2], baseBorder[3], baseBorder[4])

            local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            title:SetPoint("TOPLEFT", 14, -12)
            title:SetJustifyH("LEFT")
            title:SetWordWrap(false)
            if isBlizzSample then
                title:SetText(L["Blizzard Official"])
                title:SetTextColor(1.0, 0.82, 0.0)
            else
                title:SetText(L["Modern Theme"])
                title:SetTextColor(0.38, 0.80, 1.0)
            end

            local badge = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            badge:SetPoint("TOPRIGHT", -14, -15)
            badge:SetJustifyH("RIGHT")
            badge:SetText(isBlizzSample and ("[" .. L["Default"] .. "]") or ("[" .. L["Optional"] .. "]"))
            if isBlizzSample then
                badge:SetTextColor(0.30, 0.92, 0.45)
            else
                badge:SetTextColor(0.62, 0.72, 0.86)
            end
            title:SetPoint("RIGHT", badge, "LEFT", -8, 0)

            local sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            sub:SetPoint("TOPLEFT", 14, -34)
            sub:SetPoint("TOPRIGHT", -14, -34)
            sub:SetJustifyH("LEFT")
            sub:SetWordWrap(false)
            sub:SetText(isBlizzSample and L["Default - Classic WoW Window"] or L["Optional - Sleek Dark Minimalist UI"])
            sub:SetTextColor(0.84, 0.86, 0.90)

            -- Visual miniature example directly underneath the title
            local preview = CreateFrame("Frame", nil, card, "BackdropTemplate")
            preview:SetPoint("TOPLEFT", 14, -56)
            preview:SetPoint("TOPRIGHT", -14, -56)
            preview:SetHeight(194)

            if isBlizzSample then
                preview:SetBackdrop(BLIZZ_SURFACE_BACKDROP)
                preview:SetBackdropColor(0.18, 0.165, 0.145, 0.98)
                preview:SetBackdropBorderColor(0.64, 0.55, 0.36, 1.0)

                local pHdr = preview:CreateTexture(nil, "ARTWORK")
                pHdr:SetPoint("TOPLEFT", 4, -4)
                pHdr:SetPoint("TOPRIGHT", -4, -4)
                pHdr:SetHeight(24)
                pHdr:SetColorTexture(0.14, 0.11, 0.08, 0.95)

                local port = preview:CreateTexture(nil, "OVERLAY")
                port:SetSize(28, 28)
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
                pClose:SetPoint("TOPRIGHT", -8, -8)
                pClose:SetBackdrop(BACKDROP_SPEC)
                pClose:SetBackdropColor(0.66, 0.12, 0.10, 1.0)
                pClose:SetBackdropBorderColor(0.90, 0.74, 0.28, 1.0)
                local pCloseTxt = pClose:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                pCloseTxt:SetPoint("CENTER", 0, 1)
                pCloseTxt:SetText("x")

                local pSum = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                pSum:SetPoint("TOPLEFT", 10, -34)
                pSum:SetText(L["Online"] .. ": 3 / 5")
                pSum:SetTextColor(1.0, 0.82, 0.0)

                local pWell = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pWell:SetPoint("TOPLEFT", 8, -50)
                pWell:SetPoint("BOTTOMRIGHT", -8, 32)
                pWell:SetBackdrop(BLIZZ_INSET_BACKDROP)
                pWell:SetBackdropColor(0.20, 0.19, 0.18, 0.98)
                pWell:SetBackdropBorderColor(0.54, 0.47, 0.34, 1.0)

                local r1 = CreateFrame("Frame", nil, pWell, "BackdropTemplate")
                r1:SetPoint("TOPLEFT", 6, -6)
                r1:SetPoint("TOPRIGHT", -16, -6)
                r1:SetHeight(32)
                r1:SetBackdrop(FLAT_BACKDROP_SPEC)
                r1:SetBackdropColor(0.08, 0.075, 0.07, 0.36)
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
                r2:SetBackdropColor(0.03, 0.03, 0.03, 0.46)
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
                s2:SetTextColor(0.84, 0.80, 0.72)

                local pScroll = pWell:CreateTexture(nil, "ARTWORK")
                pScroll:SetWidth(6)
                pScroll:SetPoint("TOPRIGHT", -6, -8)
                pScroll:SetPoint("BOTTOMRIGHT", -6, 8)
                pScroll:SetColorTexture(0.38, 0.34, 0.28, 0.78)

                local bRed = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                bRed:SetSize(74, 20)
                bRed:SetPoint("BOTTOMLEFT", 8, 8)
                bRed:SetBackdrop(BACKDROP_SPEC)
                bRed:SetBackdropColor(0.62, 0.12, 0.10, 1.0)
                bRed:SetBackdropBorderColor(0.84, 0.66, 0.24, 1.0)
                local bRedTxt = bRed:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                bRedTxt:SetPoint("CENTER")
                bRedTxt:SetText(L["Add"])
                bRedTxt:SetTextColor(1.0, 0.88, 0.35)

                local bGrey1 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                bGrey1:SetSize(82, 20)
                bGrey1:SetPoint("LEFT", bRed, "RIGHT", 6, 0)
                bGrey1:SetBackdrop(BACKDROP_SPEC)
                bGrey1:SetBackdropColor(0.24, 0.24, 0.26, 1.0)
                bGrey1:SetBackdropBorderColor(0.55, 0.50, 0.40, 1.0)
                local bGrey1Txt = bGrey1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                bGrey1Txt:SetPoint("CENTER")
                bGrey1Txt:SetText(L["Whisper"])
                bGrey1Txt:SetTextColor(0.88, 0.88, 0.90)

                local bGrey2 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                bGrey2:SetSize(74, 20)
                bGrey2:SetPoint("LEFT", bGrey1, "RIGHT", 6, 0)
                bGrey2:SetBackdrop(BACKDROP_SPEC)
                bGrey2:SetBackdropColor(0.24, 0.24, 0.26, 1.0)
                bGrey2:SetBackdropBorderColor(0.55, 0.50, 0.40, 1.0)
                local bGrey2Txt = bGrey2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                bGrey2Txt:SetPoint("CENTER")
                bGrey2Txt:SetText(L["Invite"])
                bGrey2Txt:SetTextColor(0.88, 0.88, 0.90)
            else
                preview:SetBackdrop(BACKDROP_SPEC)
                preview:SetBackdropColor(0.06, 0.07, 0.09, 1.0)
                preview:SetBackdropBorderColor(0.20, 0.24, 0.30, 1.0)

                local pHdr = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pHdr:SetPoint("TOPLEFT", 1, -1)
                pHdr:SetPoint("TOPRIGHT", -1, -1)
                pHdr:SetHeight(24)
                pHdr:SetBackdrop(FLAT_BACKDROP_SPEC)
                pHdr:SetBackdropColor(0.09, 0.11, 0.14, 1.0)

                local pIcon = pHdr:CreateTexture(nil, "ARTWORK")
                pIcon:SetSize(15, 15)
                pIcon:SetPoint("LEFT", 8, 0)
                pIcon:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\icon")

                local pTitle = pHdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                pTitle:SetPoint("LEFT", pIcon, "RIGHT", 6, 0)
                pTitle:SetText("SocialCentral")
                pTitle:SetTextColor(0.93, 0.95, 0.98)

                local pTab1 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pTab1:SetSize(64, 18)
                pTab1:SetPoint("TOPLEFT", 8, -30)
                pTab1:SetBackdrop(BACKDROP_SPEC)
                pTab1:SetBackdropColor(0.13, 0.36, 0.56, 0.95)
                pTab1:SetBackdropBorderColor(0.30, 0.72, 1.0, 1.0)
                local pTab1Txt = pTab1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                pTab1Txt:SetPoint("CENTER")
                pTab1Txt:SetText(L["Social"])

                local pTab2 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pTab2:SetSize(62, 18)
                pTab2:SetPoint("LEFT", pTab1, "RIGHT", 4, 0)
                pTab2:SetBackdrop(BACKDROP_SPEC)
                pTab2:SetBackdropColor(0.09, 0.11, 0.15, 1.0)
                pTab2:SetBackdropBorderColor(0.18, 0.22, 0.28, 1.0)
                local pTab2Txt = pTab2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                pTab2Txt:SetPoint("CENTER")
                pTab2Txt:SetText(L["Chat"])
                pTab2Txt:SetTextColor(0.62, 0.68, 0.76)

                local pTab3 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pTab3:SetSize(62, 18)
                pTab3:SetPoint("LEFT", pTab2, "RIGHT", 4, 0)
                pTab3:SetBackdrop(BACKDROP_SPEC)
                pTab3:SetBackdropColor(0.09, 0.11, 0.15, 1.0)
                pTab3:SetBackdropBorderColor(0.18, 0.22, 0.28, 1.0)
                local pTab3Txt = pTab3:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                pTab3Txt:SetPoint("CENTER")
                pTab3Txt:SetText(L["Clan"])
                pTab3Txt:SetTextColor(0.62, 0.68, 0.76)

                local pWell = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                pWell:SetPoint("TOPLEFT", 8, -52)
                pWell:SetPoint("BOTTOMRIGHT", -8, 32)
                pWell:SetBackdrop(BACKDROP_SPEC)
                pWell:SetBackdropColor(0.05, 0.06, 0.08, 0.96)
                pWell:SetBackdropBorderColor(0.18, 0.22, 0.28, 0.90)

                local r1 = CreateFrame("Frame", nil, pWell, "BackdropTemplate")
                r1:SetPoint("TOPLEFT", 4, -4)
                r1:SetPoint("TOPRIGHT", -14, -4)
                r1:SetHeight(32)
                r1:SetBackdrop(FLAT_BACKDROP_SPEC)
                r1:SetBackdropColor(0.14, 0.27, 0.42, 0.90)
                local d1 = r1:CreateTexture(nil, "OVERLAY")
                d1:SetSize(6, 6)
                d1:SetPoint("LEFT", 6, 4)
                d1:SetColorTexture(0.24, 0.85, 0.45, 1)
                local n1 = r1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                n1:SetPoint("TOPLEFT", 16, -4)
                n1:SetText("Valkur Maul")
                n1:SetTextColor(0.93, 0.95, 0.98)
                local s1 = r1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                s1:SetPoint("BOTTOMLEFT", 16, 4)
                s1:SetText(L["Online"] .. " - Stormwind")
                s1:SetTextColor(0.62, 0.76, 0.92)

                local r2 = CreateFrame("Frame", nil, pWell, "BackdropTemplate")
                r2:SetPoint("TOPLEFT", r1, "BOTTOMLEFT", 0, -2)
                r2:SetPoint("TOPRIGHT", r1, "BOTTOMRIGHT", 0, -2)
                r2:SetHeight(32)
                r2:SetBackdrop(FLAT_BACKDROP_SPEC)
                r2:SetBackdropColor(0.10, 0.12, 0.16, 0.75)
                local d2 = r2:CreateTexture(nil, "OVERLAY")
                d2:SetSize(6, 6)
                d2:SetPoint("LEFT", 6, 4)
                d2:SetColorTexture(0.24, 0.85, 0.45, 1)
                local n2 = r2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                n2:SetPoint("TOPLEFT", 16, -4)
                n2:SetText("Elune")
                n2:SetTextColor(0.93, 0.95, 0.98)
                local s2 = r2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                s2:SetPoint("BOTTOMLEFT", 16, 4)
                s2:SetText(L["Online"] .. " - Dalaran")
                s2:SetTextColor(0.62, 0.68, 0.76)

                local pScroll = pWell:CreateTexture(nil, "ARTWORK")
                pScroll:SetWidth(5)
                pScroll:SetPoint("TOPRIGHT", -4, -6)
                pScroll:SetPoint("BOTTOMRIGHT", -4, 6)
                pScroll:SetColorTexture(0.30, 0.37, 0.48, 0.90)

                local bBlue = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                bBlue:SetSize(74, 20)
                bBlue:SetPoint("BOTTOMLEFT", 8, 8)
                bBlue:SetBackdrop(BACKDROP_SPEC)
                bBlue:SetBackdropColor(0.13, 0.36, 0.56, 0.95)
                bBlue:SetBackdropBorderColor(0.30, 0.72, 1.0, 0.95)
                local bBlueTxt = bBlue:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                bBlueTxt:SetPoint("CENTER")
                bBlueTxt:SetText(L["Add"])
                bBlueTxt:SetTextColor(0.95, 0.98, 1.0)

                local bSlate1 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                bSlate1:SetSize(82, 20)
                bSlate1:SetPoint("LEFT", bBlue, "RIGHT", 6, 0)
                bSlate1:SetBackdrop(BACKDROP_SPEC)
                bSlate1:SetBackdropColor(0.14, 0.17, 0.22, 0.95)
                bSlate1:SetBackdropBorderColor(0.28, 0.33, 0.41, 0.95)
                local bSlate1Txt = bSlate1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                bSlate1Txt:SetPoint("CENTER")
                bSlate1Txt:SetText(L["Whisper"])
                bSlate1Txt:SetTextColor(0.90, 0.94, 0.98)

                local bSlate2 = CreateFrame("Frame", nil, preview, "BackdropTemplate")
                bSlate2:SetSize(74, 20)
                bSlate2:SetPoint("LEFT", bSlate1, "RIGHT", 6, 0)
                bSlate2:SetBackdrop(BACKDROP_SPEC)
                bSlate2:SetBackdropColor(0.14, 0.17, 0.22, 0.95)
                bSlate2:SetBackdropBorderColor(0.28, 0.33, 0.41, 0.95)
                local bSlate2Txt = bSlate2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                bSlate2Txt:SetPoint("CENTER")
                bSlate2Txt:SetText(L["Invite"])
                bSlate2Txt:SetTextColor(0.90, 0.94, 0.98)
            end

            local cap = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cap:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 2, -10)
            cap:SetPoint("TOPRIGHT", preview, "BOTTOMRIGHT", -2, -10)
            cap:SetJustifyH("LEFT")
            cap:SetWordWrap(true)
            cap:SetText(isBlizzSample
                and L["Portrait, marble inset & classic two-tone buttons"]
                or L["Dark slate surface, sky-blue accents & flat buttons"])
            cap:SetTextColor(0.76, 0.80, 0.86)

            local cta = CreateFrame("Button", nil, card, "BackdropTemplate")
            cta:SetHeight(28)
            cta:SetPoint("BOTTOMLEFT", 14, 12)
            cta:SetPoint("BOTTOMRIGHT", -14, 12)
            cta:SetBackdrop(BACKDROP_SPEC)
            if isBlizzSample then
                cta:SetBackdropColor(0.58, 0.12, 0.10, 1.0)
                cta:SetBackdropBorderColor(0.92, 0.76, 0.26, 1.0)
            else
                cta:SetBackdropColor(0.14, 0.38, 0.60, 1.0)
                cta:SetBackdropBorderColor(0.32, 0.74, 1.0, 1.0)
            end
            cta.lbl = cta:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cta.lbl:SetPoint("LEFT", 8, 0)
            cta.lbl:SetPoint("RIGHT", -8, 0)
            cta.lbl:SetJustifyH("CENTER")
            cta.lbl:SetWordWrap(false)
            cta.lbl:SetText(isBlizzSample and L["Use Blizzard Official (Default)"] or L["Use Modern Theme"])
            cta.lbl:SetTextColor(isBlizzSample and 1.0 or 0.96, isBlizzSample and 0.90 or 0.98, isBlizzSample and 0.42 or 1.0)

            local targetTheme = isBlizzSample and "blizzard" or "dark"
            card:SetScript("OnEnter", function(selfCard)
                selfCard:SetBackdropBorderColor(hoverBorder[1], hoverBorder[2], hoverBorder[3], 1.0)
            end)
            card:SetScript("OnLeave", function(selfCard)
                selfCard:SetBackdropBorderColor(baseBorder[1], baseBorder[2], baseBorder[3], baseBorder[4])
            end)
            card:SetScript("OnMouseUp", function()
                FinishChoice(targetTheme)
            end)
            cta:SetScript("OnEnter", function()
                card:SetBackdropBorderColor(hoverBorder[1], hoverBorder[2], hoverBorder[3], 1.0)
            end)
            cta:SetScript("OnLeave", function()
                card:SetBackdropBorderColor(baseBorder[1], baseBorder[2], baseBorder[3], baseBorder[4])
            end)
            cta:SetScript("OnClick", function()
                FinishChoice(targetTheme)
            end)
            return card
        end

        m.cardBlizz = BuildSampleCard(true, "TOPLEFT", 20)
        m.cardModern = BuildSampleCard(false, "TOPRIGHT", -20)

        self:RegisterListener(function()
            if m:IsShown() then
                self:ApplyBackdrop(m, "window")
                self:StyleButton(m.closeBtn, "default")
            end
        end)

        themeWelcomePopup = m
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

    local emptyLabel = viewport:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyLabel:SetPoint("LEFT", viewport, "LEFT", 16, 6)
    emptyLabel:SetPoint("RIGHT", viewport, "RIGHT", -16, 6)
    emptyLabel:SetJustifyH("CENTER")
    emptyLabel:SetWordWrap(true)
    emptyLabel:Hide()
    list.emptyLabel = emptyLabel

    local function UpdateTrackColors(hovered)
        local p = Theme:GetPalette()
        local isBlizz = Theme:IsBlizzard(p)
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
        local vpH = viewport:GetHeight() or 0
        if vpH <= 0 then
            vpH = 280
        end
        local needed = math.max(1, math.ceil(vpH / list.rowHeight) + 1)
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
                rSep:SetColorTexture(1, 1, 1, 0.05)
                row._scRowSep = rSep
            end
            list.rows[idx] = row
        end
    end

    local function SyncScrollListLayers()
        local cLvl = math.max(1, math.min(9960, (container.GetFrameLevel and container:GetFrameLevel()) or 1))
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
        Theme:ApplyBackdrop(container, "inset")
        SyncScrollListLayers()
        UpdateTrackColors(false)
        for _, row in ipairs(self.rows) do
            if row.RefreshTheme then
                row:RefreshTheme()
            end
        end
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
                    row:ClearAllPoints()
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
            local thumbH = math.max(24, math.floor(trackH * ratio))
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
}

Theme.CHAT_TONES = BADGE_TONES

function Theme:GetChatToneSpec(toneKey)
    local key = type(toneKey) == "string" and toneKey:lower() or "whisper"
    return BADGE_TONES[key] or BADGE_TONES.whisper
end

function Theme:GetChatToneForKind(kind)
    local k = type(kind) == "string" and kind:upper() or ""
    if k == "BN_WHISPER" or k == "BNET" then
        return "bnet"
    elseif k == "GUILD" or k == "OFFICER" then
        return "guild"
    elseif k == "RAID" or k == "INSTANCE_CHAT" or k == "INSTANCE" then
        return "raid"
    elseif k == "PARTY" or k == "GROUP" then
        return "group"
    elseif k == "ROOM" or k == "ALLIANCE" then
        return "room"
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
        if gradColorA and gradColorB and capL.SetGradient and CreateColor then
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
        for i = 1, 5 do
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
        for i = 1, 5 do
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

        local count = math.min(5, #tones)
        local step = (math.pi * 2) / count
        local rx = coreW * 0.36
        local ry = coreH * 0.36
        local outerW, outerH = coreW * 1.92, coreH * 1.92
        local innerW, innerH = coreW * 1.36, coreH * 1.36
        local auraW, auraH = bw + 12, bh + 12
        local auraAlpha = b._pulseEnabled and (baseHaloAlpha * 0.72) or (baseHaloAlpha * 0.42)

        for i = 1, 5 do
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
        local delta = math.min(dt or 0, 0.05)
        local now = (GetTime and GetTime()) or 0
        local pulsing = b._pulseEnabled == true
        local popping = (b._popUntil or 0) > now
        local bursting = (b._fusionBurstUntil or 0) > now
        local swirling = b._isMulti == true
        if not pulsing and not popping and not bursting and not swirling then
            StopAnimLoop()
            return
        end

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
        local n = math.floor(tonumber(count) or 0)
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
                    if #cleanTones >= 5 then break end
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

        for i = 1, 5 do
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
