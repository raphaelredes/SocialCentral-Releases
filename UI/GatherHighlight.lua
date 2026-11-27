local _, ns = ...

local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })
local Safe = ns.Safe
local Theme = ns.Theme

local GatherUI = {
    initialized = false,
    plateGlows = setmetatable({}, { __mode = "k" }),
    activePlate = nil,
    beaconFrame = nil,
    beaconPreviewMode = false,
    promptFrame = nil,
    toggleBtnFrame = nil,
}
ns.GatherHighlightUI = GatherUI
table.insert(ns.modules, GatherUI)

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local ICON_TEX = "Interface\\AddOns\\SocialCentral\\Media\\icon.tga"
local ICON_HERB_BTN = "Interface\\Icons\\INV_Misc_Flower_02"
local GLOW_TEX = "Interface\\AddOns\\SocialCentral\\Media\\toast-glow"
local DOT_TEX = "Interface\\AddOns\\SocialCentral\\Media\\dot"
local ARROW_TEX = "Interface\\AddOns\\SocialCentral\\Media\\arrow"

local CATEGORY_COLORS = {
    HERB = {
        r = 0.24, g = 0.98, b = 0.48,
        coreR = 1.00, coreG = 0.96, coreB = 0.42,
    },
    ORE = {
        r = 1.00, g = 0.72, b = 0.16,
        coreR = 1.00, coreG = 0.94, coreB = 0.60,
    },
    FISH = {
        r = 0.24, g = 0.88, b = 1.00,
        coreR = 0.86, coreG = 1.00, coreB = 1.00,
    },
    TREASURE = {
        r = 1.00, g = 0.84, b = 0.24,
        coreR = 1.00, coreG = 0.98, coreB = 0.76,
    },
    OBJECT = {
        r = 0.88, g = 0.92, b = 1.00,
        coreR = 1.00, coreG = 1.00, coreB = 0.85,
    },
}

local function IsPlateAnchorSafe(plate)
    if not plate or type(plate) ~= "table" then
        return false
    end
    if plate.IsForbidden then
        local okF, forb = pcall(plate.IsForbidden, plate)
        if not okF or forb then
            return false
        end
    end
    if plate.IsAnchoringRestricted then
        local okR, rest = pcall(plate.IsAnchoringRestricted, plate)
        if not okR or rest then
            return false
        end
    end
    return true
end

function GatherUI:HasActivePlateGlow(plate)
    if not plate then
        return false
    end
    local g = self.plateGlows[plate]
    return self.activePlate == plate and g ~= nil and g:IsShown() == true
end

local function HidePlateGlow(plate)
    if plate and GatherUI.plateGlows[plate] then
        GatherUI.plateGlows[plate]:Hide()
    end
    if GatherUI.activePlate and GatherUI.activePlate ~= plate and GatherUI.plateGlows[GatherUI.activePlate] then
        GatherUI.plateGlows[GatherUI.activePlate]:Hide()
    end
    if GatherUI.activePlate == plate then
        GatherUI.activePlate = nil
    end
end

local function EnsurePlateGlow(plate)
    local existing = GatherUI.plateGlows[plate]
    if existing then
        return existing
    end

    -- Anchored directly to Blizzard's safe plate without touching protected plate.UnitFrame.
    -- Ignore parent alpha/scale so 0-alpha GameObject soft-interact plates still display crisp sparkles & pill.
    local g = CreateFrame("Frame", nil, plate)
    g:SetSize(136, 68)
    g:SetPoint("BOTTOM", plate, "CENTER", 0, 8)
    g:SetFrameStrata("LOW")
    g:SetFrameLevel(math.max(130, ((plate.GetFrameLevel and plate:GetFrameLevel()) or 1) + 35))
    if g.SetIgnoreParentAlpha then pcall(g.SetIgnoreParentAlpha, g, true) end
    if g.SetIgnoreParentScale then pcall(g.SetIgnoreParentScale, g, true) end
    g:SetAlpha(1.0)
    g:EnableMouse(false)

    -- Additive outer glow + 4-point star glint that cuts cleanly through foliage/ground colors
    local aura = g:CreateTexture(nil, "BACKGROUND", nil, 0)
    aura:SetSize(116, 116)
    aura:SetPoint("CENTER", g, "BOTTOM", 0, 0)
    aura:SetTexture(GLOW_TEX)
    aura:SetBlendMode("ADD")
    g.aura = aura

    local starH = g:CreateTexture(nil, "ARTWORK", nil, 1)
    starH:SetSize(92, 16)
    starH:SetPoint("CENTER", aura, "CENTER", 0, 0)
    starH:SetTexture(GLOW_TEX)
    starH:SetBlendMode("ADD")
    g.starH = starH

    local starV = g:CreateTexture(nil, "ARTWORK", nil, 1)
    starV:SetSize(16, 92)
    starV:SetPoint("CENTER", aura, "CENTER", 0, 0)
    starV:SetTexture(GLOW_TEX)
    starV:SetBlendMode("ADD")
    g.starV = starV

    local arrow = g:CreateTexture(nil, "OVERLAY", nil, 2)
    arrow:SetSize(26, 26)
    arrow:SetPoint("BOTTOM", g, "TOP", 0, -4)
    arrow:SetTexture(ARROW_TEX)
    arrow:SetDesaturated(true)
    arrow:SetRotation(math.pi)
    g.arrow = arrow

    local pill = CreateFrame("Frame", nil, g)
    pill:SetSize(156, 22)
    pill:SetPoint("TOP", g, "TOP", 0, -4)
    pill:EnableMouse(false)
    g.pill = pill

    local pBg = pill:CreateTexture(nil, "BACKGROUND")
    pBg:SetAllPoints()
    pBg:SetTexture(WHITE8X8)
    pBg:SetVertexColor(0.04, 0.05, 0.08, 0.92)
    pill.bg = pBg

    local pTop = pill:CreateTexture(nil, "BORDER")
    pTop:SetHeight(1)
    pTop:SetPoint("TOPLEFT", 0, 0)
    pTop:SetPoint("TOPRIGHT", 0, 0)
    pTop:SetTexture(WHITE8X8)
    pill.pTop = pTop

    local pBot = pill:CreateTexture(nil, "BORDER")
    pBot:SetHeight(1)
    pBot:SetPoint("BOTTOMLEFT", 0, 0)
    pBot:SetPoint("BOTTOMRIGHT", 0, 0)
    pBot:SetTexture(WHITE8X8)
    pill.pBot = pBot

    local pAcc = pill:CreateTexture(nil, "BORDER")
    pAcc:SetWidth(3)
    pAcc:SetPoint("TOPLEFT", 0, 0)
    pAcc:SetPoint("BOTTOMLEFT", 0, 0)
    pAcc:SetTexture(WHITE8X8)
    pill.pAcc = pAcc

    local ico = pill:CreateTexture(nil, "ARTWORK")
    ico:SetSize(16, 16)
    ico:SetPoint("LEFT", pill, "LEFT", 6, 0)
    ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pill.ico = ico

    local lbl = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", ico, "RIGHT", 5, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    pcall(lbl.SetFont, lbl, fontPath, 11, "THICKOUTLINE")
    pill.lbl = lbl

    local nativeAnimOk = false
    if aura.CreateAnimationGroup and starH.CreateAnimationGroup and starV.CreateAnimationGroup and arrow.CreateAnimationGroup then
        local function BuildPulseAg(region, fromScale, toScale, fromAlpha, toAlpha, dur)
            local okAg, ag = pcall(region.CreateAnimationGroup, region)
            if not (okAg and ag) then return nil end
            pcall(ag.SetLooping, ag, "BOUNCE")
            local okS, sc = pcall(ag.CreateAnimation, ag, "Scale")
            if okS and sc then
                if sc.SetScaleFrom then
                    pcall(sc.SetScaleFrom, sc, fromScale, fromScale)
                elseif sc.SetFromScale then
                    pcall(sc.SetFromScale, sc, fromScale, fromScale)
                end
                if sc.SetScaleTo then
                    pcall(sc.SetScaleTo, sc, toScale, toScale)
                elseif sc.SetToScale then
                    pcall(sc.SetToScale, sc, toScale, toScale)
                end
                if sc.SetOrigin then pcall(sc.SetOrigin, sc, "CENTER", 0, 0) end
                if sc.SetDuration then sc:SetDuration(dur) end
                if sc.SetSmoothing then sc:SetSmoothing("IN_OUT") end
            end
            local okA, al = pcall(ag.CreateAnimation, ag, "Alpha")
            if okA and al then
                if al.SetFromAlpha then al:SetFromAlpha(fromAlpha) end
                if al.SetToAlpha then al:SetToAlpha(toAlpha) end
                if al.SetDuration then al:SetDuration(dur) end
                if al.SetSmoothing then al:SetSmoothing("IN_OUT") end
            end
            return ag
        end
        local auraAg = BuildPulseAg(aura, 0.90, 1.18, 0.48, 0.92, 0.62)
        local shAg = BuildPulseAg(starH, 0.84, 1.24, 0.56, 1.0, 0.46)
        local svAg = BuildPulseAg(starV, 0.84, 1.24, 0.56, 1.0, 0.46)
        local okTrAg, arAg = pcall(arrow.CreateAnimationGroup, arrow)
        if okTrAg and arAg then
            pcall(arAg.SetLooping, arAg, "BOUNCE")
            local okT, tr = pcall(arAg.CreateAnimation, arAg, "Translation")
            if okT and tr then
                if tr.SetOffset then tr:SetOffset(0, 6) end
                if tr.SetDuration then tr:SetDuration(0.48) end
                if tr.SetSmoothing then tr:SetSmoothing("IN_OUT") end
            else
                arAg = nil
            end
        else
            arAg = nil
        end
        if auraAg and shAg and svAg and arAg then
            g._nativeAnims = { auraAg, shAg, svAg, arAg }
            nativeAnimOk = true
        end
    end

    g._elapsed = 0
    g._sanityElapsed = 0
    g._animTick = 0
    g._nativeAnimOk = nativeAnimOk
    g._updateFn = function(selfG, elapsed)
        local dt = elapsed or 0
        selfG._sanityElapsed = (selfG._sanityElapsed or 0) + dt
        if selfG._sanityElapsed >= 0.35 then
            selfG._sanityElapsed = 0
            local liveGuid = Safe.String(Safe.Call(UnitGUID, "softinteract")) or (ns.GatherHighlight and ns.GatherHighlight.lastEventGuid)
            if (not liveGuid or liveGuid == "") and ns.GatherHighlight and ns.GatherHighlight.activeNode then
                ns.GatherHighlight:RefreshSoftInteractNode()
                return
            end
        end
        if selfG._nativeAnimOk then
            return
        end
        selfG._elapsed = (selfG._elapsed or 0) + dt
        selfG._animTick = (selfG._animTick or 0) + dt
        if selfG._animTick < 0.065 then
            return
        end
        selfG._animTick = 0
        local w1 = 0.5 + 0.5 * math.sin(selfG._elapsed * 5.2)
        local w2 = 0.5 + 0.5 * math.cos(selfG._elapsed * 7.8)
        local sz = 92 + w1 * 28
        selfG.aura:SetSize(sz, sz)
        selfG.aura:SetAlpha(0.45 + w1 * 0.45)
        selfG.starH:SetSize(64 + w2 * 36, 10 + w2 * 6)
        selfG.starV:SetSize(10 + w2 * 6, 64 + w2 * 36)
        selfG.starH:SetAlpha(0.55 + w2 * 0.45)
        selfG.starV:SetAlpha(0.55 + w2 * 0.45)
        local arrowY = math.floor((math.sin(selfG._elapsed * 6.5) * 4) * 4 + 0.5) * 0.25
        if selfG._lastArrowY ~= arrowY then
            selfG._lastArrowY = arrowY
            -- Update existing single BOTTOM->TOP anchor offset without rebuilding anchor state.
            selfG.arrow:SetPoint("BOTTOM", selfG, "TOP", 0, -6 + arrowY)
        end
    end
    g:SetScript("OnShow", function(selfG)
        selfG._elapsed = 0
        selfG._sanityElapsed = 0
        selfG._animTick = 0.05
        selfG._lastArrowY = nil
        if selfG._nativeAnims then
            for _, ag in ipairs(selfG._nativeAnims) do
                if ag.Play then pcall(ag.Play, ag) end
            end
        end
        selfG:SetScript("OnUpdate", selfG._updateFn)
    end)
    g:SetScript("OnHide", function(selfG)
        selfG:SetScript("OnUpdate", nil)
        if selfG._nativeAnims then
            for _, ag in ipairs(selfG._nativeAnims) do
                if ag.Stop then pcall(ag.Stop, ag) end
            end
        end
    end)

    g:Hide()
    GatherUI.plateGlows[plate] = g
    return g
end

local function ApplyPlateGlow(node)
    local s = ns.db and ns.db.settings
    if not node or not s or s.gatherHighlightEnabled ~= true or s.gatherHighlightNameplateGlow == false then
        HidePlateGlow(GatherUI.activePlate)
        return
    end
    local plate = node.plate
    if not plate and ns.GatherHighlight and ns.GatherHighlight.FindSafeSoftInteractPlate then
        plate = ns.GatherHighlight:FindSafeSoftInteractPlate(node.guid, nil)
    elseif not plate and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, pl = pcall(C_NamePlate.GetNamePlateForUnit, "softinteract", false)
        if ok and pl then
            plate = pl
        end
    end
    if not IsPlateAnchorSafe(plate) then
        HidePlateGlow(GatherUI.activePlate)
        return
    end
    if GatherUI.activePlate and GatherUI.activePlate ~= plate then
        HidePlateGlow(GatherUI.activePlate)
    end

    local g = EnsurePlateGlow(plate)
    local c = CATEGORY_COLORS[node.category] or CATEGORY_COLORS.OBJECT

    g.aura:SetVertexColor(c.r, c.g, c.b, 0.85)
    g.starH:SetVertexColor(c.coreR, c.coreG, c.coreB, 0.95)
    g.starV:SetVertexColor(c.coreR, c.coreG, c.coreB, 0.95)
    g.arrow:SetVertexColor(c.coreR, c.coreG, c.coreB, 0.95)

    g.pill.pTop:SetVertexColor(c.r, c.g, c.b, 0.90)
    g.pill.pBot:SetVertexColor(c.r, c.g, c.b, 0.90)
    g.pill.pAcc:SetVertexColor(c.r, c.g, c.b, 1.00)
    g.pill.ico:SetTexture(node.icon or ICON_TEX)
    g.pill.lbl:SetText(node.name or L["Collectible"])
    g.pill.lbl:SetTextColor(c.coreR, c.coreG, c.coreB, 1.0)

    local tw = (g.pill.lbl.GetStringWidth and g.pill.lbl:GetStringWidth()) or 72
    g.pill:SetWidth(math.max(106, math.min(260, math.ceil(tw + 38))))
    if g.SetIgnoreParentAlpha then pcall(g.SetIgnoreParentAlpha, g, true) end
    g:SetAlpha(1.0)
    g:SetFrameStrata("LOW")
    g:SetFrameLevel(math.max(130, ((plate.GetFrameLevel and plate:GetFrameLevel()) or 1) + 35))
    g:Show()
    GatherUI.activePlate = plate
end

local function RestoreBeaconPosition(f)
    if not f then return end
    if Theme and Theme.HasSavedWindowPosition and Theme:HasSavedWindowPosition("gatherBeacon") and Theme.RestoreWindowPosition then
        Theme:RestoreWindowPosition(f, "gatherBeacon", false)
        return
    end
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, -108)
end

local function EnsureBeaconFrame()
    if GatherUI.beaconFrame then
        return GatherUI.beaconFrame
    end
    if not Theme then
        return nil
    end

    local f = CreateFrame("Frame", "SocialCentralGatherBeaconFrame", UIParent, "BackdropTemplate")
    f:Hide()
    f:SetSize(256, 40)
    RestoreBeaconPosition(f)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(520)
    f:SetClampedToScreen(true)
    -- Pass mouse clicks straight through to the 3D world while gathering so herbs are never blocked.
    f:EnableMouse(false)

    local solid = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    solid:SetAllPoints(f)
    solid:SetTexture(WHITE8X8)
    solid:SetVertexColor(0.05, 0.07, 0.10, 0.94)
    f._solidOpaqueBg = solid

    local accent = f:CreateTexture(nil, "BORDER")
    accent:SetWidth(4)
    accent:SetPoint("TOPLEFT", 1, -1)
    accent:SetPoint("BOTTOMLEFT", 1, 1)
    accent:SetTexture(WHITE8X8)
    accent:SetVertexColor(0.24, 0.98, 0.48, 1.0)
    f.accent = accent

    local glow = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    glow:SetPoint("TOPLEFT", f, "TOPLEFT", -12, 8)
    glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 12, -8)
    glow:SetTexture(GLOW_TEX)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.24, 0.98, 0.48, 0.35)
    f.glow = glow

    local ico = f:CreateTexture(nil, "ARTWORK")
    ico:SetSize(24, 24)
    ico:SetPoint("LEFT", f, "LEFT", 10, 0)
    ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ico:SetTexture("Interface\\Icons\\Trade_Herbalism")
    f.ico = ico

    local closeBtn = Theme:CreateButton(f, 18, 18, "X", "default")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function()
        GatherUI:SetBeaconPreviewMode(false)
    end)
    closeBtn:Hide()
    f.closeBtn = closeBtn

    local titleFs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("TOPLEFT", ico, "TOPRIGHT", 8, -1)
    titleFs:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetWordWrap(false)
    f.titleFs = titleFs

    local subFs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subFs:SetPoint("BOTTOMLEFT", ico, "BOTTOMRIGHT", 8, 0)
    subFs:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    subFs:SetJustifyH("LEFT")
    subFs:SetWordWrap(false)
    f.subFs = subFs

    -- Child animation driver so the movable frame itself keeps zero forbidden SetScript hooks.
    local beaconGlowAg = nil
    if f.glow and f.glow.CreateAnimationGroup then
        local okBgAg, ag = pcall(f.glow.CreateAnimationGroup, f.glow)
        if okBgAg and ag then
            pcall(ag.SetLooping, ag, "BOUNCE")
            local okAl, al = pcall(ag.CreateAnimation, ag, "Alpha")
            if okAl and al then
                if al.SetFromAlpha then al:SetFromAlpha(0.22) end
                if al.SetToAlpha then al:SetToAlpha(0.58) end
                if al.SetDuration then al:SetDuration(0.72) end
                if al.SetSmoothing then al:SetSmoothing("IN_OUT") end
                beaconGlowAg = ag
            end
        end
    end

    local animDriver = CreateFrame("Frame", nil, f)
    animDriver._elapsed = 0
    animDriver._sanityElapsed = 0
    animDriver._animTick = 0
    animDriver._glowAg = beaconGlowAg
    animDriver._fn = function(selfD, elapsed)
        local dt = elapsed or 0
        selfD._sanityElapsed = (selfD._sanityElapsed or 0) + dt
        if not GatherUI.beaconPreviewMode and selfD._sanityElapsed >= 0.35 then
            selfD._sanityElapsed = 0
            local liveGuid = Safe.String(Safe.Call(UnitGUID, "softinteract")) or (ns.GatherHighlight and ns.GatherHighlight.lastEventGuid)
            if (not liveGuid or liveGuid == "") and ns.GatherHighlight and ns.GatherHighlight.activeNode then
                ns.GatherHighlight:RefreshSoftInteractNode()
                return
            end
            local activeNode = ns.GatherHighlight and ns.GatherHighlight.activeNode
            local sCfg = ns.db and ns.db.settings
            if activeNode and (not GatherUI.activePlate) and sCfg and sCfg.gatherHighlightEnabled == true and sCfg.gatherHighlightNameplateGlow ~= false then
                local latePlate = ns.GatherHighlight.FindSafeSoftInteractPlate and ns.GatherHighlight:FindSafeSoftInteractPlate(activeNode.guid, nil) or nil
                if latePlate then
                    activeNode.plate = latePlate
                    ApplyPlateGlow(activeNode)
                end
            end
        end
        if selfD._glowAg then
            return
        end
        selfD._elapsed = (selfD._elapsed or 0) + dt
        selfD._animTick = (selfD._animTick or 0) + dt
        if selfD._animTick < 0.055 then
            return
        end
        selfD._animTick = 0
        local a = 0.20 + (0.5 + 0.5 * math.sin(selfD._elapsed * 4.5)) * 0.35
        f.glow:SetAlpha(a)
    end
    animDriver:SetScript("OnShow", function(selfD)
        selfD._elapsed = 0
        selfD._sanityElapsed = 0
        selfD._animTick = 0.055
        if selfD._glowAg and selfD._glowAg.Play then
            pcall(selfD._glowAg.Play, selfD._glowAg)
        end
        if not (selfD._glowAg and GatherUI.beaconPreviewMode) then
            selfD:SetScript("OnUpdate", selfD._fn)
        end
    end)
    animDriver:SetScript("OnHide", function(selfD)
        selfD:SetScript("OnUpdate", nil)
        if selfD._glowAg and selfD._glowAg.Stop then
            pcall(selfD._glowAg.Stop, selfD._glowAg)
        end
    end)
    f.animDriver = animDriver

    f._scLocked = true
    Theme:MakeMovable(f, {
        key = "gatherBeacon",
        skipAutoRestore = true,
        onReset = function(win)
            win:ClearAllPoints()
            win:SetPoint("TOP", UIParent, "TOP", 0, -108)
        end,
        handles = { f },
    })

    GatherUI.beaconFrame = f
    return f
end

function GatherUI:SetBeaconPreviewMode(active)
    local f = EnsureBeaconFrame()
    if not f then
        return
    end
    self.beaconPreviewMode = (active == true)
    if self.beaconPreviewMode then
        RestoreBeaconPosition(f)
        if Theme and Theme.ApplyBackdrop then
            Theme:ApplyBackdrop(f, "window")
        end
        f._scLocked = false
        f:EnableMouse(true)
        f.closeBtn:Show()
        f.ico:SetTexture("Interface\\Icons\\Trade_Herbalism")
        f.titleFs:SetText(L["Collectible Spotter Preview"])
        f.titleFs:SetTextColor(0.24, 0.98, 0.48, 1.0)
        f.subFs:SetText(L["Drag to position this indicator, then click X."])
        f.subFs:SetTextColor(0.86, 0.90, 0.96, 1.0)
        f.accent:SetVertexColor(0.24, 0.98, 0.48, 1.0)
        f.glow:SetVertexColor(0.24, 0.98, 0.48, 0.42)
        f:Show()
        if f.Raise then f:Raise() end
    else
        f._scLocked = true
        f:EnableMouse(false)
        f.closeBtn:Hide()
        local activeNode = ns.GatherHighlight and ns.GatherHighlight.activeNode
        if activeNode then
            self:RefreshNodeVisuals(activeNode)
        else
            f:Hide()
        end
    end
end

function GatherUI:ResetBeaconPosition()
    if Theme and Theme.ClearSavedWindowPosition then
        Theme:ClearSavedWindowPosition("gatherBeacon")
    end
    if self.beaconFrame then
        RestoreBeaconPosition(self.beaconFrame)
    end
end

function GatherUI:HidePlateIfBound(plate)
    if plate and self.plateGlows[plate] then
        self.plateGlows[plate]:Hide()
        if self.activePlate == plate then
            self.activePlate = nil
        end
    end
end

local function ApplyDefaultToggleBtnPlacement(btn)
    if not (btn and UIParent) then return end
    btn:ClearAllPoints()
    btn:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -206, -178)
end

local function OpenToggleBtnContextMenu(anchorBtn)
    if not (MenuUtil and MenuUtil.CreateContextMenu and anchorBtn) then
        if ns.Settings and ns.Settings.Open then
            ns.Settings:Open("radar", "gather")
        end
        return
    end
    MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        root:CreateTitle(L["Collectible Sparkles"])
        root:CreateCheckbox(L["Collectible Sparkles"], function()
            return not ns.db or not ns.db.settings or ns.db.settings.gatherHighlightEnhanceRange ~= false
        end, function()
            GatherUI:ToggleClassicSparklesFromButton()
        end)
        root:CreateButton(L["Disable Highlight & Hide Button (1-Click)"], function()
            if ns.GatherHighlight and ns.GatherHighlight.SetEnabled then
                ns.GatherHighlight:SetEnabled(false, true)
            elseif ns.db and ns.db.settings then
                ns.db.settings.gatherHighlightEnabled = false
                ns.db.settings.gatherHighlightPromptAnswered = true
                ns:Emit("SETTINGS_UPDATED")
            end
            ns:Print("%s", L["Collectibles Highlight disabled."])
        end)
        root:CreateDivider()
        root:CreateCheckbox(L["Lock button position"], function()
            return ns.db and ns.db.settings and ns.db.settings.gatherHighlightQuickButtonLock == true
        end, function()
            if ns.db and ns.db.settings then
                ns.db.settings.gatherHighlightQuickButtonLock = not (ns.db.settings.gatherHighlightQuickButtonLock == true)
                anchorBtn._scLocked = (ns.db.settings.gatherHighlightQuickButtonLock == true)
                ns:Emit("SETTINGS_UPDATED")
            end
        end)
        root:CreateButton(L["Reset Position"], function()
            if Theme and Theme.ResetWindowPosition then
                Theme:ResetWindowPosition("gather_sparkle_btn")
            end
        end)
        root:CreateButton(L["Hide button"], function()
            if ns.db and ns.db.settings then
                ns.db.settings.gatherHighlightQuickButton = false
            end
            GatherUI:SyncToggleButton()
            ns:Emit("SETTINGS_UPDATED")
        end)
        root:CreateButton(L["Open Settings"], function()
            if ns.Settings and ns.Settings.Open then
                ns.Settings:Open("radar", "gather")
            end
        end)
    end)
end

local function RenderToggleButtonTooltip(btn)
    if not (GameTooltip and btn) then
        return
    end
    local s = ns.db and ns.db.settings
    local sparklesOn = (not s) or (s.gatherHighlightEnhanceRange ~= false)
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    if sparklesOn then
        GameTooltip:AddLine(L["Collectible Sparkles"] .. ": |cff2ecc71" .. L["ON"] .. "|r", 1, 1, 1)
    else
        GameTooltip:AddLine(L["Collectible Sparkles"] .. ": |cff9da7b5" .. L["OFF"] .. "|r", 1, 1, 1)
    end
    GameTooltip:AddLine(L["Click: light up nearby herbs, ore & chests (halo + icon + banner).\nRight-click: lock button, toggle halo/chime, or settings."], 0.85, 0.90, 0.96, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Drag: move  ·  Right-click: lock / options"], 0.65, 0.76, 0.88, true)
    GameTooltip:Show()
end

local function UpdateToggleButtonTooltip(btn)
    if not (GameTooltip and btn and GameTooltip.IsOwned and GameTooltip:IsOwned(btn)) then
        return
    end
    RenderToggleButtonTooltip(btn)
end

function GatherUI:EnsureToggleButton()
    if self.toggleBtnFrame then
        return self.toggleBtnFrame
    end
    local T = Theme or ns.Theme
    if not T then return nil end

    local btn = CreateFrame("Button", "SocialCentralGatherToggleButton", UIParent, "BackdropTemplate")
    btn:Hide()
    btn:SetSize(34, 34)
    ApplyDefaultToggleBtnPlacement(btn)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(48)
    btn:SetClampedToScreen(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local sBg = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    sBg:SetAllPoints(btn)
    sBg:SetTexture(WHITE8X8)
    sBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    btn._solidOpaqueBg = sBg

    local activeWash = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    activeWash:SetPoint("TOPLEFT", 1, -1)
    activeWash:SetPoint("BOTTOMRIGHT", -1, 1)
    activeWash:SetTexture(WHITE8X8)
    activeWash:SetVertexColor(0.24, 0.94, 0.46, 0.24)
    activeWash:Hide()
    btn.activeWash = activeWash

    local aura = btn:CreateTexture(nil, "OVERLAY", nil, 2)
    aura:SetPoint("TOPLEFT", btn, "TOPLEFT", -5, 5)
    aura:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 5, -5)
    aura:SetTexture(GLOW_TEX)
    aura:SetBlendMode("ADD")
    aura:SetVertexColor(0.28, 0.95, 0.48, 0.72)
    btn.aura = aura

    if aura.CreateAnimationGroup then
        local okAg, ag = pcall(aura.CreateAnimationGroup, aura)
        if okAg and ag then
            ag:SetLooping("BOUNCE")
            local anim = ag:CreateAnimation("Alpha")
            if anim then
                anim:SetFromAlpha(0.32)
                anim:SetToAlpha(0.88)
                anim:SetDuration(1.05)
                anim:SetSmoothing("IN_OUT")
            end
            btn._auraPulseAg = ag
        end
    end

    local ico = btn:CreateTexture(nil, "ARTWORK", nil, 3)
    ico:SetSize(24, 24)
    ico:SetPoint("CENTER", btn, "CENTER", 0, 0)
    ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ico:SetTexture(ICON_HERB_BTN)
    btn.ico = ico

    local offVeil = btn:CreateTexture(nil, "ARTWORK", nil, 5)
    offVeil:SetPoint("TOPLEFT", 1, -1)
    offVeil:SetPoint("BOTTOMRIGHT", -1, 1)
    offVeil:SetColorTexture(0.03, 0.03, 0.04, 0.36)
    offVeil:Hide()
    btn.offVeil = offVeil

    local ringTop = btn:CreateTexture(nil, "OVERLAY", nil, 3)
    ringTop:SetHeight(2)
    ringTop:SetPoint("TOPLEFT", 1, -1)
    ringTop:SetPoint("TOPRIGHT", -1, -1)
    ringTop:SetTexture(WHITE8X8)
    local ringBot = btn:CreateTexture(nil, "OVERLAY", nil, 3)
    ringBot:SetHeight(2)
    ringBot:SetPoint("BOTTOMLEFT", 1, 1)
    ringBot:SetPoint("BOTTOMRIGHT", -1, 1)
    ringBot:SetTexture(WHITE8X8)
    local ringLeft = btn:CreateTexture(nil, "OVERLAY", nil, 3)
    ringLeft:SetWidth(2)
    ringLeft:SetPoint("TOPLEFT", 1, -1)
    ringLeft:SetPoint("BOTTOMLEFT", 1, 1)
    ringLeft:SetTexture(WHITE8X8)
    local ringRight = btn:CreateTexture(nil, "OVERLAY", nil, 3)
    ringRight:SetWidth(2)
    ringRight:SetPoint("TOPRIGHT", -1, -1)
    ringRight:SetPoint("BOTTOMRIGHT", -1, 1)
    ringRight:SetTexture(WHITE8X8)
    btn._activeRings = { ringTop, ringBot, ringLeft, ringRight }

    local statusDot = btn:CreateTexture(nil, "OVERLAY", nil, 5)
    statusDot:SetSize(10, 10)
    statusDot:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
    statusDot:SetTexture(DOT_TEX)
    btn.statusDot = statusDot

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn)
    hl:SetColorTexture(1.0, 0.88, 0.36, 0.16)

    btn._scLocked = (ns.db and ns.db.settings and ns.db.settings.gatherHighlightQuickButtonLock == true) and true or false
    T:MakeMovable(btn, {
        key = "gather_sparkle_btn",
        handles = { btn },
        combatLock = false,
        onReset = ApplyDefaultToggleBtnPlacement,
    })

    btn:HookScript("OnMouseDown", function(selfBtn)
        if selfBtn.ico then
            selfBtn.ico:SetPoint("CENTER", selfBtn, "CENTER", 1, -1)
        end
    end)
    btn:HookScript("OnMouseUp", function(selfBtn)
        if selfBtn.ico then
            selfBtn.ico:SetPoint("CENTER", selfBtn, "CENTER", 0, 0)
        end
    end)

    btn:SetScript("OnClick", function(selfBtn, mouseBtn)
        if selfBtn._scJustDraggedAt and GetTime and (GetTime() - selfBtn._scJustDraggedAt) < 0.25 then
            return
        end
        if mouseBtn == "RightButton" then
            OpenToggleBtnContextMenu(selfBtn)
            return
        end
        GatherUI:ToggleClassicSparklesFromButton()
        UpdateToggleButtonTooltip(selfBtn)
    end)

    btn:SetScript("OnEnter", function(selfBtn)
        RenderToggleButtonTooltip(selfBtn)
    end)
    btn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    self.toggleBtnFrame = btn
    return btn
end

function GatherUI:ToggleClassicSparklesFromButton()
    local s = ns.db and ns.db.settings
    if not s then return end
    local curOn = (s.gatherHighlightEnhanceRange ~= false)
    local nextOn = not curOn
    s.gatherHighlightEnhanceRange = nextOn
    s.gatherHighlightOutline = nextOn
    if ns.GatherHighlight and ns.GatherHighlight.SyncOfficialCVars then
        ns.GatherHighlight:SyncOfficialCVars()
    end
    self:SyncToggleButton()
    ns:Emit("SETTINGS_UPDATED")
end

function GatherUI:SyncToggleButton()
    local s = ns.db and ns.db.settings
    local shouldShow = (s ~= nil) and (s.gatherHighlightEnabled == true) and (s.gatherHighlightQuickButton ~= false)
    if not shouldShow then
        if self.toggleBtnFrame and self.toggleBtnFrame:IsShown() then
            self.toggleBtnFrame:Hide()
        end
        return
    end
    local btn = self:EnsureToggleButton()
    if not btn then return end
    local T = Theme or ns.Theme
    local p = T and T.GetPalette and T:GetPalette()
    local palKey = (p and p.key) or "default"
    if btn._lastPalKey ~= palKey then
        btn._lastPalKey = palKey
        if T and T.ApplyBackdrop then
            T:ApplyBackdrop(btn, "window", p)
        end
        if btn._solidOpaqueBg then
            local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
            btn._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
        end
    end
    btn._scLocked = (s.gatherHighlightQuickButtonLock == true) and true or false
    local hasSavedPos = T and T.HasSavedWindowPosition and T:HasSavedWindowPosition("gather_sparkle_btn")
    local posMode = hasSavedPos and "saved" or "default"
    if btn._lastPlacedMode ~= posMode then
        btn._lastPlacedMode = posMode
        if hasSavedPos then
            T:RestoreWindowPosition(btn, "gather_sparkle_btn", false, { allowLockedRestore = true })
        else
            ApplyDefaultToggleBtnPlacement(btn)
        end
    end

    local sparklesOn = (s.gatherHighlightEnhanceRange ~= false)
    if btn.ico then
        if btn.ico.SetDesaturated then
            btn.ico:SetDesaturated(not sparklesOn)
        end
        btn.ico:SetAlpha(sparklesOn and 1.0 or 0.42)
    end
    if btn.offVeil then
        btn.offVeil:SetShown(not sparklesOn)
    end
    if btn.activeWash then
        btn.activeWash:SetShown(sparklesOn)
    end
    for _, edge in ipairs(btn._activeRings or {}) do
        edge:SetVertexColor(0.28, 0.96, 0.48, 0.98)
        edge:SetShown(sparklesOn)
    end
    if btn.aura then
        btn.aura:SetShown(sparklesOn)
    end
    if btn._auraPulseAg then
        if sparklesOn and not btn._auraPulseAg:IsPlaying() then
            btn._auraPulseAg:Play()
        elseif (not sparklesOn) and btn._auraPulseAg:IsPlaying() then
            btn._auraPulseAg:Stop()
        end
    end
    if btn.statusDot then
        if sparklesOn then
            btn.statusDot:SetVertexColor(0.28, 0.96, 0.48, 1.0)
        else
            btn.statusDot:SetVertexColor(0.42, 0.45, 0.50, 0.80)
        end
    end
    if btn.SetBackdropBorderColor and sparklesOn then
        btn:SetBackdropBorderColor(0.30, 0.92, 0.48, 1.0)
    end
    if not btn:IsShown() then
        btn:Show()
    end
    UpdateToggleButtonTooltip(btn)
end

function GatherUI:RefreshNodeVisuals(node)
    ApplyPlateGlow(node)

    local s = ns.db and ns.db.settings
    if self.beaconPreviewMode then
        return
    end
    if not node or not s or s.gatherHighlightEnabled ~= true or s.gatherHighlightFloatBeacon == false then
        if self.beaconFrame then
            self.beaconFrame:Hide()
        end
        return
    end

    local f = EnsureBeaconFrame()
    if not f then
        return
    end
    local p = Theme and Theme.GetPalette and Theme:GetPalette()
    local palKey = (p and p.key) or "default"
    if not f:IsShown() then
        RestoreBeaconPosition(f)
    end
    if f._lastPalKey ~= palKey then
        f._lastPalKey = palKey
        if Theme and Theme.ApplyBackdrop then
            Theme:ApplyBackdrop(f, "window")
        end
    end
    f:EnableMouse(false)
    f.closeBtn:Hide()

    local c = CATEGORY_COLORS[node.category] or CATEGORY_COLORS.OBJECT
    f.accent:SetVertexColor(c.r, c.g, c.b, 1.0)
    f.glow:SetVertexColor(c.r, c.g, c.b, 0.40)
    f.ico:SetTexture(node.icon or ICON_TEX)
    f.titleFs:SetText(node.name or L["Collectible"])
    f.titleFs:SetTextColor(c.coreR, c.coreG, c.coreB, 1.0)
    f.subFs:SetText((node.categoryLabel or L["Collectible"]) .. "  ·  " .. L["Nearby in front"])
    f.subFs:SetTextColor(0.82, 0.88, 0.94, 0.95)
    f:Show()
end

local function EnsurePromptFrame()
    if GatherUI.promptFrame then
        return GatherUI.promptFrame
    end
    if not Theme then
        return nil
    end

    local m = CreateFrame("Frame", "SocialCentralGatherPromptModal", UIParent, "BackdropTemplate")
    m:Hide()
    m:SetSize(468, 258)
    m:SetPoint("CENTER", UIParent, "CENTER", 0, 110)
    m:SetClampedToScreen(true)
    table.insert(UISpecialFrames, "SocialCentralGatherPromptModal")
    Theme:PrepareTopOverlayModal(m, 855)

    local hdr = CreateFrame("Frame", nil, m)
    hdr:SetPoint("TOPLEFT", 12, -10)
    hdr:SetPoint("TOPRIGHT", -12, -10)
    hdr:SetHeight(24)

    local hIco = hdr:CreateTexture(nil, "ARTWORK")
    hIco:SetSize(16, 16)
    hIco:SetPoint("LEFT", hdr, "LEFT", 0, 0)
    hIco:SetTexture(ICON_TEX)

    local closeBtn = Theme:CreateButton(hdr, 20, 18, "X", "default")
    closeBtn:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function()
        if ns.GatherHighlight and ns.GatherHighlight.DismissPrompt then
            ns.GatherHighlight:DismissPrompt(false)
        end
        m:Hide()
    end)
    m.closeBtn = closeBtn

    local helpBtn = Theme:CreateHelpButton(
        hdr,
        L["Help: Gatherables Highlight Prompt"],
        L["Turns on WoW's official world-object detection so herbs, ore, and chests light up with a glow halo, game icon, and screen banner."],
        L["Choose Enable Highlight to turn it on (or toggle anytime with 1 click on the floating button)."],
        16,
        { target = m }
    )
    helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    m.helpBtn = helpBtn

    local titleFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("LEFT", hIco, "RIGHT", 6, 0)
    titleFs:SetPoint("RIGHT", helpBtn, "LEFT", -6, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetWordWrap(false)
    titleFs:SetText(L["Tracking Detected: Highlight Collectibles?"])

    Theme:MakeMovable(m, { key = "gather_prompt", skipAutoRestore = true, handles = { hdr, m } })

    local trackIco = m:CreateTexture(nil, "ARTWORK")
    trackIco:SetSize(30, 30)
    trackIco:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 2, -10)
    trackIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    trackIco:SetTexture("Interface\\Icons\\Trade_Herbalism")
    m.trackIco = trackIco

    local trackTitle = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trackTitle:SetPoint("TOPLEFT", trackIco, "TOPRIGHT", 10, 0)
    trackTitle:SetPoint("RIGHT", m, "RIGHT", -14, 0)
    trackTitle:SetJustifyH("LEFT")
    trackTitle:SetWordWrap(false)
    m.trackTitle = trackTitle

    local trackSub = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trackSub:SetPoint("BOTTOMLEFT", trackIco, "BOTTOMRIGHT", 10, 1)
    trackSub:SetPoint("RIGHT", m, "RIGHT", -14, 0)
    trackSub:SetJustifyH("LEFT")
    trackSub:SetTextColor(0.55, 0.88, 0.65)
    trackSub:SetText(L["Official Blizzard-safe highlight for nearby nodes"])

    local descFs = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    descFs:SetPoint("TOPLEFT", trackIco, "BOTTOMLEFT", 0, -10)
    descFs:SetPoint("RIGHT", m, "RIGHT", -14, 0)
    descFs:SetJustifyH("LEFT")
    descFs:SetJustifyV("TOP")
    descFs:SetWordWrap(true)
    descFs:SetText(L["Enable the quick Sparkles toggle button to spot herbs, ore, and chests easily?"])
    m.descFs = descFs

    local sparklesCb = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
    sparklesCb:SetSize(22, 22)
    sparklesCb:SetPoint("TOPLEFT", descFs, "BOTTOMLEFT", -2, -6)
    sparklesCb:SetChecked(not ns.db or not ns.db.settings or ns.db.settings.gatherHighlightEnhanceRange ~= false)
    local sparklesLbl = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sparklesLbl:SetPoint("LEFT", sparklesCb, "RIGHT", 5, 0)
    sparklesLbl:SetPoint("RIGHT", m, "RIGHT", -14, 0)
    sparklesLbl:SetJustifyH("LEFT")
    sparklesLbl:SetWordWrap(true)
    sparklesLbl:SetText(L["Start with Collectibles Highlight active immediately"])
    m.sparklesCb = sparklesCb

    local pathHintFs = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pathHintFs:SetPoint("TOPLEFT", sparklesCb, "BOTTOMLEFT", 2, -4)
    pathHintFs:SetPoint("RIGHT", m, "RIGHT", -14, 0)
    pathHintFs:SetJustifyH("LEFT")
    pathHintFs:SetWordWrap(true)
    pathHintFs:SetTextColor(0.95, 0.80, 0.36)
    pathHintFs:SetText(L["Tip: if Blizzard shows a yellow Interact Key box, bind an interact key and use it twice (or turn off Game Tutorials) to clear it."])
    m.pathHintFs = pathHintFs

    local enableBtn = Theme:CreateButton(m, 138, 24, L["Enable Highlight"], "primary")
    local w1 = Theme:AutoFitButton(enableBtn, 112, 18, 190)
    enableBtn:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -14, 12)
    enableBtn:SetScript("OnClick", function()
        local useSparkles = (not m.sparklesCb) or (m.sparklesCb:GetChecked() == true)
        m:Hide()
        if ns.db and ns.db.settings then
            ns.db.settings.gatherHighlightEnhanceRange = useSparkles
            ns.db.settings.gatherHighlightOutline = useSparkles
        end
        if ns.GatherHighlight and ns.GatherHighlight.SetEnabled then
            ns.GatherHighlight:SetEnabled(true, true)
        end
    end)
    m.enableBtn = enableBtn

    local laterBtn = Theme:CreateButton(m, 92, 24, L["Not now"], "default")
    local w2 = Theme:AutoFitButton(laterBtn, 80, 14, 140)
    laterBtn:SetPoint("RIGHT", enableBtn, "LEFT", -6, 0)
    laterBtn:SetScript("OnClick", function()
        if ns.GatherHighlight and ns.GatherHighlight.DismissPrompt then
            ns.GatherHighlight:DismissPrompt(false)
        end
        m:Hide()
    end)
    m.laterBtn = laterBtn

    local neverBtn = Theme:CreateButton(m, 124, 24, L["Don't Ask Again"], "default")
    local w3 = Theme:AutoFitButton(neverBtn, 108, 14, 175)
    neverBtn:SetPoint("BOTTOMLEFT", m, "BOTTOMLEFT", 14, 12)
    neverBtn:SetScript("OnClick", function()
        if ns.GatherHighlight and ns.GatherHighlight.DismissPrompt then
            ns.GatherHighlight:DismissPrompt(true)
        end
        m:Hide()
    end)
    m.neverBtn = neverBtn

    local configBtn = Theme:CreateButton(m, 92, 24, L["Settings"], "default")
    local w4 = Theme:AutoFitButton(configBtn, 78, 14, 130)
    configBtn:SetPoint("LEFT", neverBtn, "RIGHT", 6, 0)
    configBtn:SetScript("OnClick", function()
        m:Hide()
        if ns.Settings and ns.Settings.Open then
            ns.Settings:Open("radar", "gather")
        end
    end)
    m.configBtn = configBtn

    m:SetWidth(math.max(468, w1 + w2 + w3 + w4 + 68))
    GatherUI.promptFrame = m
    return m
end

function GatherUI:ShowTrackingPrompt(trackInfo)
    local m = EnsurePromptFrame()
    if not m or not Theme then
        return
    end
    local p = Theme:GetPalette()
    Theme:ApplyBackdrop(m, "window", p)
    if m._solidOpaqueBg then
        local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
        m._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
    end
    if m.sparklesCb then
        m.sparklesCb:SetChecked(not ns.db or not ns.db.settings or ns.db.settings.gatherHighlightEnhanceRange ~= false)
    end
    Theme:StyleButton(m.closeBtn, "default")
    Theme:StyleButton(m.enableBtn, "primary")
    Theme:StyleButton(m.laterBtn, "default")
    Theme:StyleButton(m.neverBtn, "default")
    if m.configBtn then Theme:StyleButton(m.configBtn, "default") end

    m.trackIco:SetTexture((trackInfo and trackInfo.texture) or "Interface\\Icons\\Trade_Herbalism")
    m.trackTitle:SetText(string.format(L["Activated: %s"], (trackInfo and trackInfo.name) or L["Resource Tracking"]))
    Theme:PrepareTopOverlayModal(m, 855)
    if not m:IsShown() then
        m:Show()
        if m.Raise then m:Raise() end
    end
end

local function IsTutorialsDismissedAll()
    return (ns.db and ns.db.settings and ns.db.settings.tutorialDismissAll == true)
        or (SocialCentralDB and SocialCentralDB.settings and SocialCentralDB.settings.tutorialDismissAll == true)
end

function GatherUI:ShowGatherTutorial(force)
    if not Theme or not Theme.ShowNpcGuide then
        return false
    end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat then
        self._pendingTradeoffTutorial = true
        return false
    end
    if (not force) and Theme.IsNpcGuideShown and Theme:IsNpcGuideShown() then
        self._pendingTradeoffTutorial = true
        return false
    end
    local acked = false
    local function MarkAcked()
        if acked then return end
        acked = true
        if ns.SetAccountTutorialShown then
            ns:SetAccountTutorialShown("gatherHighlightTutorialShown", true)
            ns:SetAccountTutorialShown("gatherSparkleTradeoffShown", true)
            ns:SetAccountTutorialShown("gatherClassicSparkleNoticeAck", true)
            ns:SetAccountTutorialShown("gatherSparkleBtnIntroAck", true)
            ns:SetAccountTutorialShown("gatherSoftDetectIntroAck", true)
        end
    end
    local guideSpec = {
        key = "gather_highlight_tour",
        title = L["Quick Sparkles Button"],
        nextLabel = L["Next"],
        prevLabel = L["Back"],
        doneLabel = L["Got it!"],
        defaultTarget = function()
            return (GatherUI.toggleBtnFrame and GatherUI.toggleBtnFrame:IsShown()) and GatherUI.toggleBtnFrame or nil
        end,
        onComplete = MarkAcked,
        onClose = MarkAcked,
        steps = {
            {
                title = L["Quick Sparkles Button"],
                tag = "|cff2ecc71" .. L["1-Click Gather Toggle"] .. "|r",
                text = L["Herbs, ore & chests now light up when you face them!\nLeft-click toggles ON/OFF · Right-click opens options.\nTip: if a yellow Interact Key box appears, bind an Interact Key and use it twice (or uncheck Game Tutorials) to clear it."],
                actionLabel = L["Open Settings"],
                onAction = function()
                    MarkAcked()
                    if Theme.HideNpcGuide then Theme:HideNpcGuide("gather_highlight_tour") end
                    if ns.Settings and ns.Settings.Open then
                        ns.Settings:Open("radar", "gather")
                    end
                end,
                target = function()
                    return (GatherUI.toggleBtnFrame and GatherUI.toggleBtnFrame:IsShown()) and GatherUI.toggleBtnFrame or nil
                end,
            },
        },
    }
    self._pendingTradeoffTutorial = nil
    if force then
        local shown = Theme:ShowNpcGuide(guideSpec)
        if not shown then
            self._pendingTradeoffTutorial = true
            return false
        end
        return true
    end
    if not IsTutorialsDismissedAll() and Theme.ShowNpcGuide then
        local shown = Theme:ShowNpcGuide(guideSpec)
        return shown ~= nil
    end
    return false
end

function GatherUI:MaybePromptGatherTutorial()
    local s = ns.db and ns.db.settings
    if not s or s.gatherHighlightEnabled ~= true then
        return
    end
    self:SyncToggleButton()
    if s.gatherHighlightQuickButton == false then
        return
    end
    if ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("gatherSoftDetectIntroAck") then
        return
    end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat then
        self._pendingTradeoffTutorial = true
        return
    end
    if C_Timer and C_Timer.After then
        if self._gatherTutQueued then return end
        self._gatherTutQueued = true
        C_Timer.After(0.6, function()
            GatherUI._gatherTutQueued = nil
            local cur = ns.db and ns.db.settings
            if cur and cur.gatherHighlightEnabled == true and cur.gatherHighlightQuickButton ~= false then
                if not (ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("gatherSoftDetectIntroAck")) then
                    GatherUI:SyncToggleButton()
                    GatherUI:ShowGatherTutorial(true)
                end
            end
        end)
    else
        self:ShowGatherTutorial(true)
    end
end

local function IsSafeBlizzSettingsFrameShown(frame)
    if not frame or not frame.IsForbidden then
        return false
    end
    local okF, forb = pcall(frame.IsForbidden, frame)
    if not okF or forb then
        return false
    end
    return (frame.IsShown and frame:IsShown()) == true
end

function GatherUI:ShowInteractKeySearchGuide()
    if not (Theme and Theme.ShowNpcGuide) then
        return false
    end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat then
        return false
    end
    local function TargetSettingsSearchBox()
        local sp = _G.SettingsPanel
        if not IsSafeBlizzSettingsFrameShown(sp) then
            return nil
        end
        local sb = sp.SearchBox
        if IsSafeBlizzSettingsFrameShown(sb) then
            return sb
        end
        return sp
    end
    local spRef = _G.SettingsPanel
    if spRef and not self._settingsPanelHideHooked and spRef.HookScript and spRef.IsForbidden then
        local okF, forb = pcall(spRef.IsForbidden, spRef)
        if okF and not forb then
            self._settingsPanelHideHooked = true
            pcall(spRef.HookScript, spRef, "OnHide", function()
                if Theme and Theme.HideNpcGuide then
                    Theme:HideNpcGuide("gather_interact_search_guide")
                end
            end)
        end
    end
    return Theme:ShowNpcGuide({
        key = "gather_interact_search_guide",
        title = L["Find the Interact Key"],
        doneLabel = L["Got it!"],
        defaultTarget = TargetSettingsSearchBox,
        isAnchorVisible = function()
            return IsSafeBlizzSettingsFrameShown(_G.SettingsPanel)
        end,
        steps = {
            {
                title = L["Find the Interact Key"],
                tag = "|cff1d4ed8" .. L["Settings Search"] .. "|r",
                text = L["Type |cff1d4ed8interact|r in the top search bar and look for |cff15803dInteract With Target|r.\nThen use it 2x so the warning never appears again!"],
                target = TargetSettingsSearchBox,
            },
        },
    }) ~= nil
end

function GatherUI:OpenInteractKeyOptions()
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print("%s", L["In Combat"])
        return
    end
    if Theme and Theme.HideNpcGuide then
        Theme:HideNpcGuide("gather_interact_helptip")
    end
    local opened = false
    local blizzSettings = _G.Settings
    if blizzSettings and blizzSettings.OpenToCategory then
        local targetId = nil
        if blizzSettings.GetCategory then
            local candidates = {
                _G.CONTROLS_LABEL,
                "Controls",
                "Controles",
                blizzSettings.CONTROLS_CATEGORY_ID,
                blizzSettings.KEYBINDINGS_CATEGORY_ID,
            }
            for i = 1, #candidates do
                local cand = candidates[i]
                if cand ~= nil and cand ~= "" then
                    local okCat, cat = pcall(blizzSettings.GetCategory, cand)
                    if okCat and cat and cat.GetID then
                        local okId, cid = pcall(cat.GetID, cat)
                        if okId and cid then
                            targetId = cid
                            break
                        end
                    end
                end
            end
        end
        if not targetId and blizzSettings.GetAllCategories then
            local okAll, cats = pcall(blizzSettings.GetAllCategories)
            if okAll and type(cats) == "table" then
                local want = type(_G.CONTROLS_LABEL) == "string" and _G.CONTROLS_LABEL:lower() or "controls"
                for _, cat in ipairs(cats) do
                    if cat and cat.GetName and cat.GetID then
                        local okN, cname = pcall(cat.GetName, cat)
                        if okN and type(cname) == "string" then
                            local clow = cname:lower()
                            if clow == want or clow == "controls" or clow == "controles" then
                                local okId, cid = pcall(cat.GetID, cat)
                                if okId and cid then
                                    targetId = cid
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        if not targetId then
            targetId = blizzSettings.CONTROLS_CATEGORY_ID or blizzSettings.KEYBINDINGS_CATEGORY_ID
        end
        if targetId and pcall(blizzSettings.OpenToCategory, targetId) then
            opened = true
        end
    end
    if not opened then
        local sp = _G.SettingsPanel
        if sp and sp.Open and sp.IsForbidden then
            local okF, forb = pcall(sp.IsForbidden, sp)
            if okF and not forb then
                opened = pcall(sp.Open, sp)
            end
        end
    end
    if opened then
        if C_Timer and C_Timer.After then
            C_Timer.After(0.15, function()
                GatherUI:ShowInteractKeySearchGuide()
            end)
        else
            GatherUI:ShowInteractKeySearchGuide()
        end
    end
end

function GatherUI:ShowInteractKeyTipGuide(tipFrame)
    if self._interactTipSessionShown or not (Theme and Theme.ShowNpcGuide) then
        return false
    end
    local s = ns.db and ns.db.settings
    if not s or s.gatherHighlightEnabled ~= true or s.gatherHighlightEnhanceRange == false then
        return false
    end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat then
        self._pendingInteractTipGuide = true
        return false
    end
    if Theme.IsNpcGuideShown and Theme:IsNpcGuideShown() then
        self._pendingInteractTipGuide = true
        return false
    end
    self._pendingInteractTipGuide = nil
    self._interactTipSessionShown = true

    local function TargetActiveTip()
        if tipFrame and tipFrame.IsForbidden then
            local okF, forb = pcall(tipFrame.IsForbidden, tipFrame)
            if okF and not forb and tipFrame.IsShown and tipFrame:IsShown() then
                return tipFrame
            end
        end
        return (GatherUI.toggleBtnFrame and GatherUI.toggleBtnFrame:IsShown()) and GatherUI.toggleBtnFrame or nil
    end

    local guideSpec = {
        key = "gather_interact_helptip",
        title = L["Blizzard's Yellow Interact Box"],
        doneLabel = L["Keep Active"],
        defaultTarget = TargetActiveTip,
        steps = {
            {
                title = L["Blizzard's Yellow Interact Box"],
                tag = "|cffffd24d" .. L["Native WoW Tip"] .. "|r",
                text = L["WoW warning from active highlight.\nOptional: bind a key and use it 2x to never show again."],
                actionLabel = L["Disable Highlight (1-Click)"],
                onAction = function()
                    if Theme.HideNpcGuide then
                        Theme:HideNpcGuide("gather_interact_helptip")
                    end
                    if ns.GatherHighlight and ns.GatherHighlight.SetEnabled then
                        ns.GatherHighlight:SetEnabled(false, true)
                    elseif ns.db and ns.db.settings then
                        ns.db.settings.gatherHighlightEnabled = false
                        ns.db.settings.gatherHighlightPromptAnswered = true
                        ns:Emit("SETTINGS_UPDATED")
                    end
                    ns:Print("%s", L["Collectibles Highlight disabled."])
                end,
                midActionLabel = L["Set Keybind"],
                onMidAction = function()
                    GatherUI:OpenInteractKeyOptions()
                end,
                target = TargetActiveTip,
            },
        },
    }
    return Theme:ShowNpcGuide(guideSpec) ~= nil
end

local function IsInteractHelpTipFrame(tipFrame)
    if not tipFrame or type(tipFrame) ~= "table" then return false end
    if tipFrame.IsForbidden then
        local okF, forb = pcall(tipFrame.IsForbidden, tipFrame)
        if not okF or forb then return false end
    end
    if not (tipFrame.IsShown and tipFrame:IsShown()) then
        return false
    end
    local rawTxt = (type(tipFrame.info) == "table" and Safe and Safe.String and Safe.String(tipFrame.info.text))
        or (tipFrame.Text and tipFrame.Text.GetText and Safe and Safe.String and Safe.String(tipFrame.Text:GetText()))
        or nil
    if not rawTxt or rawTxt == "" then
        return false
    end
    local low = rawTxt:lower()
    return low:find("tecla de intera", 1, true) ~= nil
        or low:find("interact key", 1, true) ~= nil
        or low:find("interact with target", 1, true) ~= nil
end

function GatherUI:ScanActiveInteractHelpTip()
    if self._interactTipSessionShown then
        return
    end
    local s = ns.db and ns.db.settings
    if not s or s.gatherHighlightEnabled ~= true or s.gatherHighlightEnhanceRange == false then
        return
    end
    local ht = _G.HelpTip
    if ht and ht.framePool and ht.framePool.EnumerateActive then
        local okIt, iterFn, state, var = pcall(ht.framePool.EnumerateActive, ht.framePool)
        if okIt and type(iterFn) == "function" then
            for tipFrame in iterFn, state, var do
                if IsInteractHelpTipFrame(tipFrame) then
                    self:ShowInteractKeyTipGuide(tipFrame)
                    return
                end
            end
        end
    end
end

function GatherUI:InstallInteractHelpTipWatcher()
    if self._helpTipWatcherInstalled then
        return
    end
    local ht = _G.HelpTip
    if not (ht and type(ht.Show) == "function" and hooksecurefunc) then
        return
    end
    self._helpTipWatcherInstalled = true
    pcall(hooksecurefunc, ht, "Show", function()
        if GatherUI._interactTipSessionShown then
            return
        end
        local s = ns.db and ns.db.settings
        if not s or s.gatherHighlightEnabled ~= true or s.gatherHighlightEnhanceRange == false then
            return
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.15, function()
                GatherUI:ScanActiveInteractHelpTip()
            end)
        else
            GatherUI:ScanActiveInteractHelpTip()
        end
    end)
end

function GatherUI:Init()
    if self.initialized then
        return
    end
    self.initialized = true

    if not self._regenFrame then
        local rf = CreateFrame("Frame")
        rf:RegisterEvent("PLAYER_REGEN_ENABLED")
        rf:SetScript("OnEvent", function()
            if GatherUI._pendingInteractTipGuide then
                GatherUI._pendingInteractTipGuide = nil
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.9, function()
                        GatherUI:ScanActiveInteractHelpTip()
                    end)
                else
                    GatherUI:ScanActiveInteractHelpTip()
                end
            end
            if GatherUI._pendingTradeoffTutorial then
                GatherUI._pendingTradeoffTutorial = nil
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.8, function()
                        GatherUI:MaybePromptGatherTutorial()
                    end)
                else
                    GatherUI:MaybePromptGatherTutorial()
                end
            end
        end)
        self._regenFrame = rf
    end

    ns:On("GATHER_NODE_CHANGED", function(node)
        GatherUI:RefreshNodeVisuals(node)
    end)

    ns:On("GATHER_PROMPT_REQUESTED", function(trackInfo)
        GatherUI:ShowTrackingPrompt(trackInfo)
    end)

    ns:On("SETTINGS_UPDATED", function()
        local sCfg = ns.db and ns.db.settings
        if sCfg and sCfg.gatherHighlightEnabled == true and sCfg.gatherHighlightEnhanceRange ~= false then
            GatherUI._interactTipSessionShown = nil
        end
        local activeNode = ns.GatherHighlight and ns.GatherHighlight.activeNode
        GatherUI:RefreshNodeVisuals(activeNode)
        GatherUI:SyncToggleButton()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.35, function()
                GatherUI:MaybePromptGatherTutorial()
                GatherUI:ScanActiveInteractHelpTip()
            end)
        else
            GatherUI:MaybePromptGatherTutorial()
            GatherUI:ScanActiveInteractHelpTip()
        end
    end)

    if ns.Theme and ns.Theme.RegisterListener then
        ns.Theme:RegisterListener(function()
            GatherUI:SyncToggleButton()
        end)
    end

    self:InstallInteractHelpTipWatcher()
    self:SyncToggleButton()
    if C_Timer and C_Timer.After then
        C_Timer.After(1.6, function()
            GatherUI:InstallInteractHelpTipWatcher()
            GatherUI:SyncToggleButton()
            GatherUI:MaybePromptGatherTutorial()
            GatherUI:ScanActiveInteractHelpTip()
        end)
    end
end
