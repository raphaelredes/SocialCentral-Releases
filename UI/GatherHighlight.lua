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
}
ns.GatherHighlightUI = GatherUI
table.insert(ns.modules, GatherUI)

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local ICON_TEX = "Interface\\AddOns\\SocialCentral\\Media\\icon.tga"
local GLOW_TEX = "Interface\\AddOns\\SocialCentral\\Media\\toast-glow"
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
    if plate.IsVisible then
        local okV, vis = pcall(plate.IsVisible, plate)
        if not okV or not vis then
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
    local g = CreateFrame("Frame", nil, plate)
    g:SetSize(130, 62)
    g:SetPoint("BOTTOM", plate, "TOP", 0, -6)
    g:SetFrameLevel(math.max(130, ((plate.GetFrameLevel and plate:GetFrameLevel()) or 1) + 35))
    g:EnableMouse(false)

    -- Additive outer glow + 4-point star glint that cuts cleanly through foliage/ground colors
    local aura = g:CreateTexture(nil, "BACKGROUND", nil, 0)
    aura:SetSize(108, 108)
    aura:SetPoint("CENTER", g, "BOTTOM", 0, 8)
    aura:SetTexture(GLOW_TEX)
    aura:SetBlendMode("ADD")
    g.aura = aura

    local starH = g:CreateTexture(nil, "ARTWORK", nil, 1)
    starH:SetSize(84, 14)
    starH:SetPoint("CENTER", aura, "CENTER", 0, 0)
    starH:SetTexture(GLOW_TEX)
    starH:SetBlendMode("ADD")
    g.starH = starH

    local starV = g:CreateTexture(nil, "ARTWORK", nil, 1)
    starV:SetSize(14, 84)
    starV:SetPoint("CENTER", aura, "CENTER", 0, 0)
    starV:SetTexture(GLOW_TEX)
    starV:SetBlendMode("ADD")
    g.starV = starV

    local starD1 = g:CreateTexture(nil, "ARTWORK", nil, 1)
    starD1:SetSize(74, 10)
    starD1:SetPoint("CENTER", aura, "CENTER", 0, 0)
    starD1:SetTexture(GLOW_TEX)
    starD1:SetBlendMode("ADD")
    starD1:SetRotation(math.rad(45))
    g.starD1 = starD1

    local starD2 = g:CreateTexture(nil, "ARTWORK", nil, 1)
    starD2:SetSize(74, 10)
    starD2:SetPoint("CENTER", aura, "CENTER", 0, 0)
    starD2:SetTexture(GLOW_TEX)
    starD2:SetBlendMode("ADD")
    starD2:SetRotation(math.rad(-45))
    g.starD2 = starD2

    local arrow = g:CreateTexture(nil, "OVERLAY", nil, 2)
    arrow:SetSize(24, 24)
    arrow:SetPoint("BOTTOM", g, "TOP", 0, -6)
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

    g._elapsed = 0
    g._sanityElapsed = 0
    g._animTick = 0
    g._updateFn = function(selfG, elapsed)
        local dt = elapsed or 0
        selfG._elapsed = (selfG._elapsed or 0) + dt
        selfG._sanityElapsed = (selfG._sanityElapsed or 0) + dt
        if selfG._sanityElapsed >= 0.25 then
            selfG._sanityElapsed = 0
            local liveGuid = Safe.String(Safe.Call(UnitGUID, "softinteract")) or (ns.GatherHighlight and ns.GatherHighlight.lastEventGuid)
            if (not liveGuid or liveGuid == "") and ns.GatherHighlight and ns.GatherHighlight.activeNode then
                ns.GatherHighlight:RefreshSoftInteractNode()
                return
            end
        end
        selfG._animTick = (selfG._animTick or 0) + dt
        if selfG._animTick < 0.033 then
            return
        end
        selfG._animTick = 0
        local w1 = 0.5 + 0.5 * math.sin(selfG._elapsed * 5.2)
        local w2 = 0.5 + 0.5 * math.cos(selfG._elapsed * 7.8)
        local w3 = 0.5 + 0.5 * math.sin(selfG._elapsed * 7.8)
        local sz = 92 + w1 * 28
        selfG.aura:SetSize(sz, sz)
        selfG.aura:SetAlpha(0.45 + w1 * 0.45)
        selfG.starH:SetSize(64 + w2 * 36, 10 + w2 * 6)
        selfG.starV:SetSize(10 + w2 * 6, 64 + w2 * 36)
        selfG.starH:SetAlpha(0.55 + w2 * 0.45)
        selfG.starV:SetAlpha(0.55 + w2 * 0.45)
        selfG.starD1:SetSize(56 + w3 * 30, 8 + w3 * 5)
        selfG.starD2:SetSize(56 + w3 * 30, 8 + w3 * 5)
        selfG.starD1:SetAlpha(0.40 + w3 * 0.55)
        selfG.starD2:SetAlpha(0.40 + w3 * 0.55)
        selfG.arrow:ClearAllPoints()
        selfG.arrow:SetPoint("BOTTOM", selfG, "TOP", 0, -6 + math.sin(selfG._elapsed * 6.5) * 4)
    end
    g:SetScript("OnShow", function(selfG)
        selfG._elapsed = 0
        selfG._sanityElapsed = 0
        selfG._animTick = 0.04
        selfG:SetScript("OnUpdate", selfG._updateFn)
    end)
    g:SetScript("OnHide", function(selfG)
        selfG:SetScript("OnUpdate", nil)
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
    if not plate and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, pl = pcall(C_NamePlate.GetNamePlateForUnit, "softinteract")
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
    g.starD1:SetVertexColor(c.r, c.g, c.b, 0.90)
    g.starD2:SetVertexColor(c.r, c.g, c.b, 0.90)
    g.arrow:SetVertexColor(c.coreR, c.coreG, c.coreB, 0.95)

    g.pill.pTop:SetVertexColor(c.r, c.g, c.b, 0.90)
    g.pill.pBot:SetVertexColor(c.r, c.g, c.b, 0.90)
    g.pill.pAcc:SetVertexColor(c.r, c.g, c.b, 1.00)
    g.pill.ico:SetTexture(node.icon or ICON_TEX)
    g.pill.lbl:SetText(node.name or L["Collectible"])
    g.pill.lbl:SetTextColor(c.coreR, c.coreG, c.coreB, 1.0)

    local tw = (g.pill.lbl.GetStringWidth and g.pill.lbl:GetStringWidth()) or 72
    g.pill:SetWidth(math.max(106, math.min(260, math.ceil(tw + 38))))
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
    local animDriver = CreateFrame("Frame", nil, f)
    animDriver._elapsed = 0
    animDriver._sanityElapsed = 0
    animDriver._animTick = 0
    animDriver._fn = function(selfD, elapsed)
        local dt = elapsed or 0
        selfD._elapsed = (selfD._elapsed or 0) + dt
        selfD._sanityElapsed = (selfD._sanityElapsed or 0) + dt
        if not GatherUI.beaconPreviewMode and selfD._sanityElapsed >= 0.25 then
            selfD._sanityElapsed = 0
            local liveGuid = Safe.String(Safe.Call(UnitGUID, "softinteract")) or (ns.GatherHighlight and ns.GatherHighlight.lastEventGuid)
            if (not liveGuid or liveGuid == "") and ns.GatherHighlight and ns.GatherHighlight.activeNode then
                ns.GatherHighlight:RefreshSoftInteractNode()
                return
            end
        end
        selfD._animTick = (selfD._animTick or 0) + dt
        if selfD._animTick < 0.033 then
            return
        end
        selfD._animTick = 0
        local a = 0.20 + (0.5 + 0.5 * math.sin(selfD._elapsed * 4.5)) * 0.35
        f.glow:SetAlpha(a)
    end
    animDriver:SetScript("OnShow", function(selfD)
        selfD._elapsed = 0
        selfD._sanityElapsed = 0
        selfD._animTick = 0.04
        selfD:SetScript("OnUpdate", selfD._fn)
    end)
    animDriver:SetScript("OnHide", function(selfD)
        selfD:SetScript("OnUpdate", nil)
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
    RestoreBeaconPosition(f)
    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(f, "window")
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
    m:SetSize(446, 232)
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
        L["Asks whether you want SocialCentral to enhance nearby herbs, ore veins, fishing pools, and treasures using Blizzard's official soft-target interaction icons, glowing outlines, and high-contrast sparkles. Because this uses WoW's native Soft-Target system, Blizzard may also show a yellow tip about its optional Interact Key — you can close that tip and keep clicking normally with your mouse, or bind a key in Game Options -> Controls."],
        L["Click Enable Highlight to activate (original game settings are saved and automatically restored whenever you turn this off), Not Now to snooze this session, or Don't Ask Again to manage it anytime in Settings."],
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
    descFs:SetText(L["Would you like to activate SocialCentral's Collectibles Highlight so nearby plants, minerals, and pools sparkle clearly against grass and terrain? Your original settings are preserved and restored whenever you disable this. (Note: uses WoW's official Soft-Target highlight, which may show Blizzard's optional 'Interact Key' tip.)"])
    m.descFs = descFs

    local pathHintFs = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pathHintFs:SetPoint("TOPLEFT", descFs, "BOTTOMLEFT", 0, -8)
    pathHintFs:SetPoint("RIGHT", m, "RIGHT", -14, 0)
    pathHintFs:SetJustifyH("LEFT")
    pathHintFs:SetWordWrap(true)
    pathHintFs:SetTextColor(0.95, 0.80, 0.36)
    pathHintFs:SetText(L["Settings Menu: SocialCentral Settings -> Radar & Map"])
    m.pathHintFs = pathHintFs

    local enableBtn = Theme:CreateButton(m, 138, 24, L["Enable Highlight"], "primary")
    local w1 = Theme:AutoFitButton(enableBtn, 112, 18, 190)
    enableBtn:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -14, 12)
    enableBtn:SetScript("OnClick", function()
        m:Hide()
        if ns.GatherHighlight and ns.GatherHighlight.SetEnabled then
            ns.GatherHighlight:SetEnabled(true, true)
        end
    end)
    m.enableBtn = enableBtn

    local laterBtn = Theme:CreateButton(m, 96, 24, L["Not now"], "default")
    local w2 = Theme:AutoFitButton(laterBtn, 84, 16, 150)
    laterBtn:SetPoint("RIGHT", enableBtn, "LEFT", -8, 0)
    laterBtn:SetScript("OnClick", function()
        if ns.GatherHighlight and ns.GatherHighlight.DismissPrompt then
            ns.GatherHighlight:DismissPrompt(false)
        end
        m:Hide()
    end)
    m.laterBtn = laterBtn

    local neverBtn = Theme:CreateButton(m, 132, 24, L["Don't Ask Again"], "default")
    local w3 = Theme:AutoFitButton(neverBtn, 112, 16, 180)
    neverBtn:SetPoint("BOTTOMLEFT", m, "BOTTOMLEFT", 14, 12)
    neverBtn:SetScript("OnClick", function()
        if ns.GatherHighlight and ns.GatherHighlight.DismissPrompt then
            ns.GatherHighlight:DismissPrompt(true)
        end
        m:Hide()
    end)
    m.neverBtn = neverBtn

    m:SetWidth(math.max(430, w1 + w2 + w3 + 52))
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
    Theme:StyleButton(m.closeBtn, "default")
    Theme:StyleButton(m.enableBtn, "primary")
    Theme:StyleButton(m.laterBtn, "default")
    Theme:StyleButton(m.neverBtn, "default")

    m.trackIco:SetTexture((trackInfo and trackInfo.texture) or "Interface\\Icons\\Trade_Herbalism")
    m.trackTitle:SetText(string.format(L["Activated: %s"], (trackInfo and trackInfo.name) or L["Resource Tracking"]))
    Theme:PrepareTopOverlayModal(m, 855)
    if not m:IsShown() then
        m:Show()
        if m.Raise then m:Raise() end
    end
end

local function NormalizeTipLookupText(raw)
    if Safe and Safe.IsSecret and Safe.IsSecret(raw) then
        return ""
    end
    local str = (Safe and Safe.String and Safe.String(raw)) or (type(raw) == "string" and raw or nil)
    if not str or str == "" then
        return ""
    end
    local lower = (ns.Compat and ns.Compat.LowerUtf8 and ns.Compat.LowerUtf8(str)) or str:lower()
    lower = lower:gsub("á", "a"):gsub("à", "a"):gsub("â", "a"):gsub("ã", "a")
        :gsub("é", "e"):gsub("ê", "e"):gsub("í", "i")
        :gsub("ó", "o"):gsub("ô", "o"):gsub("õ", "o")
        :gsub("ú", "u"):gsub("ç", "c")
    return lower
end

local function IsInteractKeyTipText(rawText)
    local norm = NormalizeTipLookupText(rawText)
    if norm == "" then
        return false
    end
    if norm:find("interact key", 1, true)
        or norm:find("tecla de interac", 1, true)
        or norm:find("softtarget", 1, true)
        or norm:find("soft-target", 1, true)
        or norm:find("soft target", 1, true)
    then
        return true
    end
    return false
end

local function IsSafeInteractHelpTipFrame(tipFrame)
    if not tipFrame or type(tipFrame) ~= "table" then
        return false
    end
    if tipFrame.IsForbidden then
        local okF, forb = pcall(tipFrame.IsForbidden, tipFrame)
        if not okF or forb then
            return false
        end
    end
    if tipFrame.IsShown then
        local okS, shown = pcall(tipFrame.IsShown, tipFrame)
        if not okS or not shown then
            return false
        end
    end
    local info = rawget(tipFrame, "info")
    if type(info) == "table" and IsInteractKeyTipText(info.text) then
        return true
    end
    local txtObj = rawget(tipFrame, "Text")
    if txtObj and txtObj.GetText then
        local okT, txt = pcall(txtObj.GetText, txtObj)
        if okT and IsInteractKeyTipText(txt) then
            return true
        end
    end
    local contentObj = rawget(tipFrame, "Content")
    if type(contentObj) == "table" and contentObj.Text and contentObj.Text.GetText then
        local okC, cTxt = pcall(contentObj.Text.GetText, contentObj.Text)
        if okC and IsInteractKeyTipText(cTxt) then
            return true
        end
    end
    return false
end

local function ScanHelpTipChildren(n, ...)
    for i = 1, n do
        local ch = select(i, ...)
        if ch and IsSafeInteractHelpTipFrame(ch) then
            return ch
        end
    end
    return nil
end

local function FindActiveInteractKeyTipFrame()
    local ht = _G.HelpTip
    if ht then
        local pool = rawget(ht, "framePool")
        if pool and type(pool.EnumerateActive) == "function" then
            local okEnum, iter, state, initKey = pcall(pool.EnumerateActive, pool)
            if okEnum and type(iter) == "function" then
                for frame in iter, state, initKey do
                    if IsSafeInteractHelpTipFrame(frame) then
                        return frame
                    end
                end
            end
        end
    end
    if _G.UIParent and _G.UIParent.GetChildren then
        return ScanHelpTipChildren(select("#", _G.UIParent:GetChildren()), _G.UIParent:GetChildren())
    end
    return nil
end

function GatherUI:ShowInteractKeyTipGuide(tipFrame)
    local s = ns.db and ns.db.settings
    if not s or s.gatherHighlightEnabled ~= true then
        return false
    end
    if not Theme or not Theme.ShowNpcGuide then
        return false
    end
    if ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("gatherInteractTipExplained") then
        return false
    end
    if self._interactTipExplainedThisSession then
        return false
    end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat then
        self._pendingInteractTipFrame = tipFrame
        return false
    end
    if Theme.IsNpcGuideShown and Theme:IsNpcGuideShown() then
        return false
    end

    local targetFrame = (tipFrame and IsSafeInteractHelpTipFrame(tipFrame)) and tipFrame or FindActiveInteractKeyTipFrame()
    if not targetFrame then
        return false
    end

    self._interactTipExplainedThisSession = true
    self._pendingInteractTipFrame = nil
    local finished = false
    local function MarkExplained()
        if finished then return end
        finished = true
        if ns.SetAccountTutorialShown then
            ns:SetAccountTutorialShown("gatherInteractTipExplained", true)
            ns:SetAccountTutorialShown("gatherHighlightTutorialShown", true)
        end
    end

    Theme:ShowNpcGuide({
        key = "gather_interact_tip_explain",
        title = L["Chromie — Blizzard 'Interact Key' Tip"],
        nextLabel = L["Next"],
        prevLabel = L["Back"],
        doneLabel = L["Got it!"],
        defaultTarget = function()
            if tipFrame and IsSafeInteractHelpTipFrame(tipFrame) then
                return tipFrame
            end
            return FindActiveInteractKeyTipFrame()
        end,
        steps = {
            {
                title = L["Blizzard's 'Interact Key' Yellow Tip"],
                tag = "|cfff1c40f" .. L["Native Blizzard Tip (Safe to Close!)"] .. "|r",
                text = L["This yellow box belongs to Blizzard (it is not an error!) and appeared because SocialCentral's Collectibles Highlight enables WoW's official nearby-object detection. You do NOT have to bind anything: just click the yellow X to close it and keep right-clicking herbs, ores, and NPCs normally! (If you ever want 1-key gathering/interacting, you can bind a key in Game Options -> Controls.)"],
            },
            {
                title = L["Control or Disable Anytime"],
                tag = "|cff58a6ff" .. L["Settings -> Radar & Map"] .. "|r",
                text = L["If you ever want to disable WoW's Interact Key / Soft-Target boost completely, open SocialCentral Settings -> Radar & Map -> Collectibles & Gathering Highlight and uncheck 'Expand official detection cone, interact icon & object outline' (your original game controls are restored automatically)."],
            },
        },
        onComplete = MarkExplained,
        onClose = MarkExplained,
    })
    return true
end

function GatherUI:ScanAndExplainVisibleInteractTip()
    local s = ns.db and ns.db.settings
    if not s or s.gatherHighlightEnabled ~= true then
        return false
    end
    local tipFrame = FindActiveInteractKeyTipFrame()
    if tipFrame then
        return self:ShowInteractKeyTipGuide(tipFrame)
    end
    return false
end

function GatherUI:InstallHelpTipWatcher()
    if self._helpTipWatcherInstalled then
        return
    end
    self._helpTipWatcherInstalled = true

    if _G.HelpTip and type(_G.HelpTip.Show) == "function" and type(hooksecurefunc) == "function" then
        hooksecurefunc(_G.HelpTip, "Show", function(_, a1, a2, a3)
            local s = ns.db and ns.db.settings
            if not s or s.gatherHighlightEnabled ~= true then
                return
            end
            if ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("gatherInteractTipExplained") then
                return
            end
            local matchedText = false
            for _, arg in ipairs({ a1, a2, a3 }) do
                if type(arg) == "table" and IsInteractKeyTipText(arg.text) then
                    matchedText = true
                    break
                end
            end
            if not matchedText then
                return
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0.15, function()
                    GatherUI:ScanAndExplainVisibleInteractTip()
                end)
            else
                GatherUI:ScanAndExplainVisibleInteractTip()
            end
        end)
    end

    if not self._regenFrame then
        local rf = CreateFrame("Frame")
        rf:RegisterEvent("PLAYER_REGEN_ENABLED")
        rf:SetScript("OnEvent", function()
            if GatherUI._pendingInteractTipFrame then
                local pend = GatherUI._pendingInteractTipFrame
                GatherUI._pendingInteractTipFrame = nil
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.4, function()
                        GatherUI:ShowInteractKeyTipGuide(pend)
                    end)
                else
                    GatherUI:ShowInteractKeyTipGuide(pend)
                end
            end
        end)
        self._regenFrame = rf
    end
end

function GatherUI:ShowGatherTutorial(force)
    if not Theme or not Theme.ShowNpcGuide then
        return
    end
    local guideSpec = {
        key = "gather_highlight_tour",
        title = L["Chromie — Collectibles & Interact Key"],
        nextLabel = L["Next"],
        prevLabel = L["Back"],
        doneLabel = L["Got it!"],
        steps = {
            {
                title = L["1. Collectibles Highlight"],
                tag = "|cff2ecc71" .. L["Herbs, Ore, Fish & Treasures"] .. "|r",
                text = L["When Collectibles Highlight is active, facing a nearby herb, ore vein, fishing pool, or chest makes it stand out with an outline glow, floating icon, sparkle halo, and an optional click-through top banner so nothing blocks your mouse."],
            },
            {
                title = L["2. Blizzard's 'Interact Key' Yellow Tip"],
                tag = "|cfff1c40f" .. L["Native WoW Feature (Optional)"] .. "|r",
                text = L["Because this highlight turns on Blizzard's official Soft-Target detection, WoW itself may display a yellow tip saying 'The Interact Key lets you interact with NPCs and objects by pressing a key'. If you want to gather or loot the highlighted herb/NPC with 1 keypress, bind a key in Game Options -> Controls — otherwise just click X on Blizzard's tip and keep clicking with your mouse as usual!"],
            },
            {
                title = L["3. Customize or Restore Anytime"],
                tag = "|cff58a6ff" .. L["Settings -> Radar & Map"] .. "|r",
                text = L["You can turn Collectibles Highlight or 'Expand official detection cone, interact icon & object outline' on or off anytime in SocialCentral Settings -> Radar & Map. Turning either off immediately restores all of your original WoW controls and stops the Soft-Target Interact Key feature."],
            },
        },
    }
    if force then
        if ns.SetAccountTutorialShown then
            ns:SetAccountTutorialShown("gatherHighlightTutorialShown", true)
        end
        Theme:ShowNpcGuide(guideSpec)
        return
    end
    if Theme.PromptWindowTutorial then
        Theme:PromptWindowTutorial({
            tutorialKey = "gatherHighlightTutorialShown",
            title = L["Collectibles Highlight"],
            askText = L["Collectibles Highlight is active! Would you like Chromie's quick 3-step guide explaining how it highlights nodes and what Blizzard's native 'Interact Key' yellow tip means?"],
            guideSpec = guideSpec,
        })
    end
end

function GatherUI:MaybePromptGatherTutorial()
    local s = ns.db and ns.db.settings
    if not s or s.gatherHighlightEnabled ~= true then
        return
    end
    if self:ScanAndExplainVisibleInteractTip() then
        return
    end
    if ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("gatherHighlightTutorialShown") then
        return
    end
    if C_Timer and C_Timer.After then
        if self._gatherTutQueued then return end
        self._gatherTutQueued = true
        C_Timer.After(0.6, function()
            GatherUI._gatherTutQueued = nil
            local cur = ns.db and ns.db.settings
            if cur and cur.gatherHighlightEnabled == true then
                if not GatherUI:ScanAndExplainVisibleInteractTip() then
                    GatherUI:ShowGatherTutorial(false)
                end
            end
        end)
    else
        self:ShowGatherTutorial(false)
    end
end

function GatherUI:Init()
    if self.initialized then
        return
    end
    self.initialized = true

    self:InstallHelpTipWatcher()

    ns:On("GATHER_NODE_CHANGED", function(node)
        GatherUI:RefreshNodeVisuals(node)
    end)

    ns:On("GATHER_PROMPT_REQUESTED", function(trackInfo)
        GatherUI:ShowTrackingPrompt(trackInfo)
    end)

    ns:On("SETTINGS_UPDATED", function()
        local activeNode = ns.GatherHighlight and ns.GatherHighlight.activeNode
        GatherUI:RefreshNodeVisuals(activeNode)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.35, function()
                GatherUI:MaybePromptGatherTutorial()
            end)
        else
            GatherUI:MaybePromptGatherTutorial()
        end
    end)

    if C_Timer and C_Timer.After then
        C_Timer.After(2.0, function()
            GatherUI:ScanAndExplainVisibleInteractTip()
        end)
        C_Timer.After(3.2, function()
            GatherUI:MaybePromptGatherTutorial()
        end)
    end
end
