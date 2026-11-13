local _, ns = ...

local Compat = ns.Compat
local Safe = ns.Safe
local Theme = ns.Theme
local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })

local SpotterHUD = {
    frame = nil,
    slots = {},
    filterMode = "ALL",
    collapsed = false,
    pendingRefresh = false,
    pendingAction = nil, -- "show" | "hide" | nil
    userClosed = false,
    manualPinnedEmpty = false,
    focusedKey = nil,
    _compassEntry = nil,
    _smoothAngle = 0,
    _hasSmoothAngle = false,
    _kinematicsElapsed = 0,
    lastBannerAt = 0,
    lastBannerText = nil,
    lastBannerColor = nil,
}

local MAX_SLOTS = 6
local HUD_WIDTH = 368
local HEADER_H = 28
local COMPASS_H = 62
local BANNER_H = 22
local FILTER_H = 24
local SLOT_H = 40
local SLOT_GAP = 3
local PAD = 8
local ARROW_TEX = "Interface\\AddOns\\SocialCentral\\Media\\arrow"

local STANCE_RGB = {
    ENEMY = { 0.96, 0.28, 0.28 },
    ALLY  = { 0.25, 0.85, 0.45 },
    SAME  = { 0.98, 0.80, 0.24 },
}

local function ShowHUDTooltip(owner, titleText, line1, line2)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(titleText or "", 1, 0.85, 0.25)
    if line1 and line1 ~= "" then
        GameTooltip:AddLine(line1, 0.9, 0.92, 0.95, true)
    end
    if line2 and line2 ~= "" then
        GameTooltip:AddLine(line2, 0.65, 0.72, 0.80, true)
    end
    GameTooltip:Show()
end

local function OpenTargetContextMenu(anchor, entry)
    if not entry then return end
    if InCombatLockdown and InCombatLockdown() then
        ns:Print(L["Target menu unavailable during combat."])
        return
    end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        return
    end

    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle(entry.displayName or "?")

        if not (InCombatLockdown and InCombatLockdown()) and TargetByName then
            root:CreateButton(L["Target Player"], function()
                if ns.SpotterHUD and ns.SpotterHUD.HandleTargetClick then
                    ns.SpotterHUD.HandleTargetClick(entry)
                end
            end)
        end

        root:CreateButton(L["Whisper in SocialCentral"], function()
            if ns.Chat and ns.Chat.OpenDirectConversation then
                ns.Chat:OpenDirectConversation({
                    targetName = entry.targetName or entry.displayName,
                    classFile = entry.classFile,
                    autoProbe = true,
                    openUI = true,
                })
                if ns.UI and ns.UI.OpenTab then
                    ns.UI:OpenTab("chat")
                end
            elseif Compat.Whisper then
                Compat.Whisper(entry.targetName or entry.displayName)
            end
        end)

        root:CreateButton(L["Official Whisper"], function()
            if Compat.Whisper then
                Compat.Whisper(entry.targetName or entry.displayName)
            end
        end)

        if entry.stance ~= "ENEMY" then
            root:CreateButton(L["Invite"], function()
                if Compat.Invite then
                    Compat.Invite(entry.targetName or entry.displayName)
                end
            end)
        end

        root:CreateButton(L["Add to Watchlist"], function()
            if ns.Watchlist and ns.Watchlist.Add then
                ns.Watchlist:Add(entry.displayName, entry.guild or "")
            end
        end)

        if entry.guild and entry.guild ~= "" and entry.stance ~= "SAME" and ns.Clan then
            if entry.stance ~= "ENEMY" then
                root:CreateButton(L["Mark Guild as Enemy"], function()
                    ns.Clan:SetGuildStance(entry.guild, "ENEMY", entry.reason or "")
                end)
            end
            if entry.stance ~= "ALLY" then
                root:CreateButton(L["Mark Guild as Ally"], function()
                    ns.Clan:SetGuildStance(entry.guild, "ALLY", entry.reason or "")
                end)
            end
            root:CreateButton(L["Remove Guild Diplomacy"], function()
                if ns.UI and ns.UI.OpenDiplomacyModal then
                    ns.UI:OpenDiplomacyModal(entry.guild, entry.stance, nil)
                elseif ns.Clan then
                    ns.Clan:SetGuildStance(entry.guild, "NEUTRAL", "")
                end
            end)
        end

        root:CreateButton(L["Dismiss Target"], function()
            if ns.Spotter then
                ns.Spotter:DismissTarget(entry.key)
            end
        end)
    end)
end

local function BuildTargetMacroText(entry)
    if not entry then return "" end
    local cleanDisplay = entry.displayName and entry.displayName:gsub("[%c%|%/%\\%[%]%;\r\n]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local candidates = Compat.GetForeverTargetVariants and Compat.GetForeverTargetVariants(cleanDisplay or entry.firstName) or {}
    local lines = {}
    local seen = {}
    for _, cand in ipairs(candidates) do
        local c = cand:gsub("[%c%|%/%\\%[%]%;\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if c ~= "" and not seen[c] then
            seen[c] = true
            table.insert(lines, "/targetexact " .. c)
        end
    end
    local firstName = entry.firstName or (cleanDisplay and cleanDisplay:match("^([^%s%-]+)"))
    local cleanFirst = firstName and firstName:gsub("[%c%|%/%\\%[%]%;\r\n]", ""):gsub("%s+", "")
    if cleanFirst and cleanFirst ~= "" and not seen[cleanFirst] then
        table.insert(lines, "/targetexact " .. cleanFirst)
    end
    if cleanFirst and cleanFirst ~= "" then
        table.insert(lines, "/target " .. cleanFirst)
    end

    return table.concat(lines, "\n")
end

local function ApplySecureMacroAttributes(btn, entry)
    if not btn then return end
    if InCombatLockdown and InCombatLockdown() then
        SpotterHUD.pendingRefresh = true
        return
    end
    if not entry then
        btn:SetAttribute("type", nil)
        btn:SetAttribute("type1", nil)
        btn:SetAttribute("unit", nil)
        btn:SetAttribute("macrotext", nil)
        btn:SetAttribute("macrotext1", nil)
        return
    end

    local entryTable = (type(entry) == "table") and entry or nil
    btn:SetAttribute("type1", "macro")
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("unit", nil)
    local mText = entryTable and BuildTargetMacroText(entryTable) or tostring(entry)
    btn:SetAttribute("macrotext1", mText)
    btn:SetAttribute("macrotext", mText)
end

local function HandleTargetClick(entry)
    if not entry then return end
    SpotterHUD.focusedKey = entry.key
    if not (InCombatLockdown and InCombatLockdown()) and TargetByName then
        local candidates = Compat.GetForeverTargetVariants and Compat.GetForeverTargetVariants(entry.displayName or entry.firstName)
            or { entry.firstName or entry.displayName }
        for _, cand in ipairs(candidates) do
            if cand and cand ~= "" then
                pcall(TargetByName, cand, true)
                local cur = Safe.String(Safe.Call(UnitName, "target"))
                if cur and cur ~= "" then break end
            end
        end
    end
    SpotterHUD:UpdateCompassVisuals(true)
    SpotterHUD:UpdateTargetVisuals()
end
SpotterHUD.HandleTargetClick = HandleTargetClick

local function FormatBearingText(angleRad)
    if not angleRad then return L["Nearby"] end
    local absA = math.abs(angleRad)
    if absA <= 0.42 then
        return L["Ahead"]
    elseif absA >= 2.35 then
        return L["Behind"]
    elseif angleRad > 0 then
        return L["To your left"]
    end
    return L["To your right"]
end

local function ShortestAngleDelta(fromA, toA)
    local diff = (toA - fromA) % (2 * math.pi)
    if diff > math.pi then
        diff = diff - 2 * math.pi
    end
    return diff
end

local function CreateTargetSlot(parent, index)
    local btn = CreateFrame("Button", "SocialCentralSpotterSlot" .. index, parent, "SecureActionButtonTemplate,BackdropTemplate")
    btn:SetHeight(SLOT_H)
    btn:SetClipsChildren(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ApplySecureMacroAttributes(btn, nil)

    local bar = btn:CreateTexture(nil, "ARTWORK")
    bar:SetSize(4, SLOT_H - 4)
    bar:SetPoint("LEFT", 2, 0)
    btn.bar = bar

    local badge = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge:SetPoint("TOPLEFT", 10, -5)
    badge:SetJustifyH("LEFT")
    btn.badge = badge

    local nameFs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameFs:SetPoint("TOPLEFT", badge, "TOPRIGHT", 6, 0)
    nameFs:SetPoint("RIGHT", btn, "RIGHT", -56, 0)
    nameFs:SetJustifyH("LEFT")
    nameFs:SetWordWrap(false)
    btn.nameFs = nameFs

    local lvlFs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lvlFs:SetPoint("TOPRIGHT", -8, -5)
    lvlFs:SetWidth(46)
    lvlFs:SetJustifyH("RIGHT")
    btn.lvlFs = lvlFs

    local subFs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subFs:SetPoint("BOTTOMLEFT", 10, 5)
    subFs:SetPoint("RIGHT", btn, "RIGHT", -104, 0)
    subFs:SetJustifyH("LEFT")
    subFs:SetWordWrap(false)
    btn.subFs = subFs

    local statusFs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFs:SetPoint("BOTTOMRIGHT", -8, 5)
    statusFs:SetWidth(94)
    statusFs:SetJustifyH("RIGHT")
    btn.statusFs = statusFs

    local targetGlow = btn:CreateTexture(nil, "HIGHLIGHT")
    targetGlow:SetAllPoints()
    targetGlow:SetColorTexture(1, 1, 1, 0.08)
    btn.targetGlow = targetGlow

    btn:SetScript("PostClick", function(selfBtn, mouseBtn, down)
        if mouseBtn == "LeftButton" and selfBtn.entry then
            if not down then
                HandleTargetClick(selfBtn.entry)
            end
        elseif mouseBtn == "RightButton" and not down and selfBtn.entry then
            OpenTargetContextMenu(selfBtn, selfBtn.entry)
        end
    end)

    btn:SetScript("OnEnter", function(selfBtn)
        local e = selfBtn.entry
        if not e then return end
        local stanceLbl = ns.Spotter and ns.Spotter:GetStanceLabel(e.stance) or e.stance
        local title = string.format("%s (%s)", e.displayName or "?", stanceLbl)
        local l1 = e.guild and ("<" .. e.guild .. ">" .. (e.reason and e.reason ~= "" and (" — " .. e.reason) or "")) or ""
        local l2 = L["Left-click: Target player  |  Right-click: Actions"]
        ShowHUDTooltip(selfBtn, title, l1, l2)
    end)

    btn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    btn:Hide()
    return btn
end

function SpotterHUD:BuildFrame()
    if self.frame then return self.frame end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingRefresh = true
        return nil
    end

    local f = CreateFrame("Frame", "SocialCentralSpotterFrame", UIParent, "BackdropTemplate")
    f:SetSize(HUD_WIDTH, 180)
    f:SetPoint("TOP", UIParent, "TOP", 0, -96)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(40)
    f:SetClipsChildren(true)
    f:EnableMouse(true)

    local hdr = CreateFrame("Frame", nil, f, "BackdropTemplate")
    hdr:SetHeight(HEADER_H)
    hdr:SetPoint("TOPLEFT", 4, -4)
    hdr:SetPoint("TOPRIGHT", -4, -4)
    hdr:EnableMouse(true)
    f.hdr = hdr

    local title = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 8, 0)
    title:SetText(L["Target Radar"])
    f.title = title

    local countsFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countsFs:SetPoint("LEFT", title, "RIGHT", 6, 0)
    countsFs:SetPoint("RIGHT", hdr, "RIGHT", -106, 0)
    countsFs:SetJustifyH("LEFT")
    countsFs:SetWordWrap(false)
    f.countsFs = countsFs

    local closeBtn = Theme:CreateButton(hdr, 20, 20, "X", "danger")
    closeBtn:SetPoint("RIGHT", -4, 0)
    closeBtn:SetScript("OnClick", function()
        SpotterHUD.userClosed = true
        SpotterHUD:Hide()
    end)
    f.closeBtn = closeBtn

    local collapseBtn = Theme:CreateButton(hdr, 20, 20, "-", "default")
    collapseBtn:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
    collapseBtn:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then
            ns:Print(L["Cannot resize radar during combat."])
            return
        end
        SpotterHUD.collapsed = not SpotterHUD.collapsed
        SpotterHUD:Refresh()
    end)
    f.collapseBtn = collapseBtn

    local clearBtn = Theme:CreateButton(hdr, 48, 20, L["Clear"], "default")
    clearBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -3, 0)
    Theme:AutoFitButton(clearBtn, 44, 12, 64)
    clearBtn:SetScript("OnClick", function()
        if ns.Spotter then ns.Spotter:Clear() end
        SpotterHUD.lastBannerAt = 0
        SpotterHUD:Refresh()
    end)
    f.clearBtn = clearBtn

    hdr:SetScript("OnEnter", function(selfHdr)
        if GameTooltip then
            GameTooltip:SetOwner(selfHdr, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Target Radar (drag to move)"], 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    hdr:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local banner = CreateFrame("Button", "SocialCentralSpotterBanner", f, "SecureActionButtonTemplate,BackdropTemplate")
    banner:SetHeight(BANNER_H)
    banner:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 2, -4)
    banner:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", -2, -4)
    banner:SetClipsChildren(true)
    banner:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ApplySecureMacroAttributes(banner, nil)
    local bannerGlow = banner:CreateTexture(nil, "HIGHLIGHT")
    bannerGlow:SetAllPoints()
    bannerGlow:SetColorTexture(1, 1, 1, 0.10)
    local bannerFs = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bannerFs:SetPoint("LEFT", 8, 0)
    bannerFs:SetPoint("RIGHT", -8, 0)
    bannerFs:SetJustifyH("LEFT")
    bannerFs:SetWordWrap(false)
    banner.fs = bannerFs
    banner:SetScript("PostClick", function(selfBtn, mouseBtn, down)
        if mouseBtn == "LeftButton" and selfBtn.entry then
            if not down then
                HandleTargetClick(selfBtn.entry)
            end
        elseif mouseBtn == "RightButton" and not down and selfBtn.entry then
            OpenTargetContextMenu(selfBtn, selfBtn.entry)
        end
    end)
    banner:SetScript("OnEnter", function(selfBtn)
        if selfBtn.entry then
            ShowHUDTooltip(
                selfBtn,
                selfBtn.entry.displayName or "?",
                selfBtn.entry.guild and ("<" .. selfBtn.entry.guild .. ">") or "",
                L["Left-click: Target player  |  Right-click: Actions"]
            )
        end
    end)
    banner:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    banner:Hide()
    f.banner = banner

    local compassBar = CreateFrame("Button", "SocialCentralSpotterCompass", f, "SecureActionButtonTemplate,BackdropTemplate")
    compassBar:SetHeight(COMPASS_H)
    compassBar:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 2, -4)
    compassBar:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", -2, -4)
    compassBar:SetClipsChildren(true)
    compassBar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ApplySecureMacroAttributes(compassBar, nil)
    local compassGlow = compassBar:CreateTexture(nil, "HIGHLIGHT")
    compassGlow:SetAllPoints()
    compassGlow:SetColorTexture(1, 1, 1, 0.08)

    local arrowBox = CreateFrame("Frame", nil, compassBar, "BackdropTemplate")
    arrowBox:SetSize(52, 52)
    arrowBox:SetPoint("LEFT", 6, 0)
    arrowBox:SetClipsChildren(false)
    local arrowAura = arrowBox:CreateTexture(nil, "ARTWORK")
    arrowAura:SetSize(44, 44)
    arrowAura:SetPoint("CENTER")
    arrowAura:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    arrowAura:SetVertexColor(0.05, 0.25, 0.36, 0.45)
    arrowBox.aura = arrowAura

    local arrowTex = arrowBox:CreateTexture(nil, "OVERLAY")
    arrowTex:SetSize(48, 48)
    arrowTex:SetPoint("CENTER")
    arrowTex:SetTexture(ARROW_TEX)
    arrowBox.arrowTex = arrowTex
    compassBar.arrowBox = arrowBox
    compassBar.arrowTex = arrowTex

    local compassNameFs = compassBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    compassNameFs:SetPoint("TOPLEFT", arrowBox, "TOPRIGHT", 8, -2)
    compassNameFs:SetPoint("TOPRIGHT", compassBar, "TOPRIGHT", -8, -2)
    compassNameFs:SetJustifyH("LEFT")
    compassNameFs:SetWordWrap(false)
    compassBar.nameFs = compassNameFs

    local compassDistFs = compassBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    compassDistFs:SetPoint("LEFT", arrowBox, "RIGHT", 8, 1)
    compassDistFs:SetPoint("RIGHT", compassBar, "RIGHT", -8, 1)
    compassDistFs:SetJustifyH("LEFT")
    compassDistFs:SetWordWrap(false)
    compassBar.distFs = compassDistFs

    local compassSubFs = compassBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    compassSubFs:SetPoint("BOTTOMLEFT", arrowBox, "BOTTOMRIGHT", 8, 2)
    compassSubFs:SetPoint("BOTTOMRIGHT", compassBar, "BOTTOMRIGHT", -8, 2)
    compassSubFs:SetJustifyH("LEFT")
    compassSubFs:SetWordWrap(false)
    compassBar.subFs = compassSubFs

    compassBar:SetScript("PostClick", function(selfBtn, mouseBtn, down)
        if mouseBtn == "LeftButton" and selfBtn.entry then
            if not down then
                HandleTargetClick(selfBtn.entry)
            end
        elseif mouseBtn == "RightButton" and not down and selfBtn.entry then
            OpenTargetContextMenu(selfBtn, selfBtn.entry)
        end
    end)
    compassBar:SetScript("OnEnter", function(selfBtn)
        if selfBtn.entry then
            ShowHUDTooltip(
                selfBtn,
                selfBtn.entry.displayName or "?",
                selfBtn.entry.guild and ("<" .. selfBtn.entry.guild .. ">") or "",
                L["Left-click: Target player  |  Right-click: Actions"]
            )
        end
    end)
    compassBar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    compassBar:Hide()
    f.compassBar = compassBar

    local filterBar = CreateFrame("Frame", nil, f)
    filterBar:SetHeight(FILTER_H)
    filterBar:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, -4)
    filterBar:SetPoint("TOPRIGHT", banner, "BOTTOMRIGHT", 0, -4)
    f.filterBar = filterBar

    local filterDefs = {
        { id = "ALL",   label = L["All"],   w = 62 },
        { id = "ENEMY", label = L["Enemy"], w = 82 },
        { id = "ALLY",  label = L["Ally"],  w = 76 },
        { id = "SAME",  label = L["Clan"],  w = 74 },
    }
    f.filterBtns = {}
    local prevBtn
    for _, def in ipairs(filterDefs) do
        local fb = Theme:CreateButton(filterBar, def.w, 20, def.label, "default")
        if not prevBtn then
            fb:SetPoint("LEFT", 2, 0)
        else
            fb:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
        end
        fb:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then
                ns:Print(L["Cannot filter target buttons during combat."])
                return
            end
            SpotterHUD.filterMode = def.id
            SpotterHUD:Refresh()
        end)
        f.filterBtns[def.id] = fb
        prevBtn = fb
    end

    local listArea = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listArea:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -4)
    listArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    listArea:SetClipsChildren(true)
    f.listArea = listArea

    local emptyFs = listArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emptyFs:SetPoint("CENTER", 0, 0)
    emptyFs:SetWidth(HUD_WIDTH - 36)
    emptyFs:SetJustifyH("CENTER")
    emptyFs:SetText(L["Scanning players on screen, target & mouseover..."])
    f.emptyFs = emptyFs

    self.slots = {}
    for i = 1, MAX_SLOTS do
        local slot = CreateTargetSlot(listArea, i)
        if i == 1 then
            slot:SetPoint("TOPLEFT", listArea, "TOPLEFT", 4, -4)
            slot:SetPoint("TOPRIGHT", listArea, "TOPRIGHT", -4, -4)
        else
            slot:SetPoint("TOPLEFT", self.slots[i - 1], "BOTTOMLEFT", 0, -SLOT_GAP)
            slot:SetPoint("TOPRIGHT", self.slots[i - 1], "BOTTOMRIGHT", 0, -SLOT_GAP)
        end
        self.slots[i] = slot
    end

    Theme:MakeMovable(f, {
        key = "spotter",
        anchor = "TOP",
        combatLock = true,
        handles = { f, hdr, listArea },
    })

    f:SetScript("OnUpdate", function(_, elapsed)
        SpotterHUD._kinematicsElapsed = (SpotterHUD._kinematicsElapsed or 0) + elapsed
        if SpotterHUD._kinematicsElapsed >= 0.04 then
            local dt = SpotterHUD._kinematicsElapsed
            SpotterHUD._kinematicsElapsed = 0
            SpotterHUD:UpdateCompassVisuals(false, dt)
        end
    end)

    self.frame = f
    self:UpdateAppearance()
    f:Hide()
    return f
end

function SpotterHUD:UpdateAppearance()
    local f = self.frame
    if not f then return end
    local p = Theme:GetPalette()

    Theme:ApplyBackdrop(f, "window", p)
    Theme:ApplyBackdrop(f.hdr, "header", p)
    Theme:ApplyBackdrop(f.listArea, "inset", p)
    Theme:ApplyBackdrop(f.banner, "surface", p)
    if self.promptDialog then
        Theme:ApplyBackdrop(self.promptDialog, "window", p)
        self.promptDialog.titleFs:SetTextColor(p.accent[1], p.accent[2], p.accent[3])
        self.promptDialog.bodyFs:SetTextColor(p.text[1], p.text[2], p.text[3])
        self.promptDialog.tipFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
        Theme:StyleButton(self.promptDialog.closeBtn, "default")
        Theme:StyleButton(self.promptDialog.keepBtn, "primary")
        Theme:StyleButton(self.promptDialog.disableBtn, "danger")
    end
    if f.compassBar then
        Theme:ApplyBackdrop(f.compassBar, "surface", p)
        Theme:ApplyBackdrop(f.compassBar.arrowBox, "inset", p)
        f.compassBar.subFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
    end

    f.title:SetTextColor(p.accent[1], p.accent[2], p.accent[3])
    f.countsFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
    f.emptyFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])

    Theme:StyleButton(f.closeBtn, "danger")
    Theme:StyleButton(f.collapseBtn, "default")
    Theme:StyleButton(f.clearBtn, "default")

    for _, slot in ipairs(self.slots) do
        Theme:ApplyBackdrop(slot, "surface", p)
    end
    self:Refresh()
end

function SpotterHUD:UpdateCompassVisuals(snap, dt)
    local f = self.frame
    if not (f and f:IsShown() and not self.collapsed and f.compassBar) then return end
    local entry = self._compassEntry
    if not (entry and ns.Spotter and ns.Spotter.GetTargetKinematics) then return end

    local kin = ns.Spotter:GetTargetKinematics(entry)
    if not kin then return end

    local targetAngle = kin.hasAngle and kin.angle or 0
    if snap or not self._hasSmoothAngle then
        self._smoothAngle = targetAngle
        self._hasSmoothAngle = true
    else
        local step = math.min(1, (dt or 0.04) * 14)
        self._smoothAngle = self._smoothAngle + ShortestAngleDelta(self._smoothAngle, targetAngle) * step
    end

    if f.compassBar.arrowTex and f.compassBar.arrowTex.SetRotation then
        f.compassBar.arrowTex:SetRotation(self._smoothAngle)
    end

    local rgb = STANCE_RGB[entry.stance] or STANCE_RGB.SAME
    if entry.dead then
        if f.compassBar.arrowBox and f.compassBar.arrowBox.aura then
            f.compassBar.arrowBox.aura:SetVertexColor(0.4, 0.4, 0.4, 0.20)
        end
        if f.compassBar.arrowTex and f.compassBar.arrowTex.SetVertexColor then
            f.compassBar.arrowTex:SetVertexColor(0.55, 0.55, 0.55, 0.65)
        end
        local bearing = kin.hasAngle and FormatBearingText(kin.angle) or L["Nearby"]
        f.compassBar.distFs:SetText(string.format("|cff888888%s|r  |cff8b949e· %s|r", L["Dead"], bearing))
    else
        if f.compassBar.arrowBox and f.compassBar.arrowBox.aura then
            f.compassBar.arrowBox.aura:SetVertexColor(rgb[1], rgb[2], rgb[3], kin.hasAngle and 0.38 or 0.18)
        end
        if f.compassBar.arrowTex and f.compassBar.arrowTex.SetVertexColor then
            f.compassBar.arrowTex:SetVertexColor(1, 1, 1, 1)
        end
        local bearing = kin.hasAngle and FormatBearingText(kin.angle) or L["Nearby"]
        f.compassBar.distFs:SetText(string.format("|cff58d8ff%s: %s|r  |cffffd100· %s|r", L["Distance"], kin.distText or L["> 28m"], bearing))
    end

    -- Refresh compact live distance badges on visible target slots cleanly (throttled to 4 FPS)
    self._slotDistElapsed = (self._slotDistElapsed or 0) + (dt or 0.04)
    if snap or self._slotDistElapsed >= 0.25 then
        self._slotDistElapsed = 0
        local now = time()
        for _, slot in ipairs(self.slots) do
            local se = slot.entry
            if se and slot:IsShown() then
                local sk = (se.key == entry.key) and kin or ns.Spotter:GetTargetKinematics(se)
                local dTxt = sk and sk.distText or ""
                if se.dead then
                    slot.statusFs:SetText("|cff888888" .. L["Dead"] .. "|r")
                elseif se.onScreen then
                    slot.statusFs:SetText("|cff58d8ff" .. dTxt .. "|r |cff3fb950· " .. L["On Screen"] .. "|r")
                else
                    local age = math.max(0, now - (se.lastSeen or now))
                    slot.statusFs:SetText(string.format("|cff58d8ff%s|r |cff8b949e· %ds|r", dTxt, age))
                end
            end
        end
    end
end

function SpotterHUD:UpdateTargetVisuals()
    local f = self.frame
    if not (f and f:IsShown() and not self.collapsed) then return end

    local currentTargetGuid = Safe.String(Safe.Call(UnitGUID, "target"))
    local currentTargetName = Safe.String(Safe.Call(UnitName, "target"))
    local parsedTarget = currentTargetName and Compat.ParseCharacterName(currentTargetName)
    local p = Theme:GetPalette()

    local activeEntry = nil
    for _, slot in ipairs(self.slots) do
        local entry = slot.entry
        if entry and slot:IsShown() then
            local isCurrent = (currentTargetGuid and entry.guid and currentTargetGuid == entry.guid)
                or (parsedTarget and (parsedTarget.lookupKey == entry.key or (entry.firstName and parsedTarget.firstName:lower() == entry.firstName:lower())))
            if not isCurrent and not currentTargetGuid and not parsedTarget and self.focusedKey and entry.key == self.focusedKey then
                isCurrent = true
            end
            if isCurrent then
                Theme:ApplyBackdrop(slot, "primary", p)
                if not activeEntry then
                    activeEntry = entry
                end
            else
                Theme:ApplyBackdrop(slot, "surface", p)
            end
        end
    end

    if not activeEntry and (currentTargetGuid or parsedTarget) and ns.Spotter and ns.Spotter.entries then
        for _, entry in pairs(ns.Spotter.entries) do
            local isCurrent = (currentTargetGuid and entry.guid and currentTargetGuid == entry.guid)
                or (parsedTarget and (parsedTarget.lookupKey == entry.key or (entry.firstName and parsedTarget.firstName:lower() == entry.firstName:lower())))
            if isCurrent then
                activeEntry = entry
                break
            end
        end
    end

    if not activeEntry and f.compassBar and f.compassBar:IsShown() and ns.Spotter then
        local all = ns.Spotter:GetActiveTargets("ALL")
        if all and all[1] then
            activeEntry = all[1]
        end
    end

    if activeEntry and f.compassBar and f.compassBar:IsShown() then
        self._compassEntry = activeEntry
        local colHex = ns.Spotter:GetStanceColor(activeEntry.stance).hex
        local stanceLbl = ns.Spotter:GetStanceLabel(activeEntry.stance)
        local classHex = Compat.ClassHex and Compat.ClassHex(activeEntry.classFile) or "|cffffffff"
        f.compassBar.nameFs:SetText(string.format("%s[%s]|r %s%s|r", colHex, stanceLbl, classHex, activeEntry.displayName or "?"))
        local guildSub = activeEntry.guild and ("<" .. activeEntry.guild .. ">") or ""
        if activeEntry.reason and activeEntry.reason ~= "" then
            guildSub = guildSub .. " · " .. activeEntry.reason
        end
        local isActuallyTargeted = (currentTargetGuid and activeEntry.guid and currentTargetGuid == activeEntry.guid)
            or (parsedTarget and (parsedTarget.lookupKey == activeEntry.key or (activeEntry.firstName and parsedTarget.firstName:lower() == activeEntry.firstName:lower())))
        local targetHint = isActuallyTargeted and ("|cff3fb950[" .. L["Current Target"] .. "]|r") or L["Click to Target"]
        f.compassBar.subFs:SetText(guildSub ~= "" and (guildSub .. " · " .. targetHint) or targetHint)
        self:UpdateCompassVisuals(true)
    end
end

function SpotterHUD:Refresh()
    if InCombatLockdown and InCombatLockdown() then
        self.pendingRefresh = true
        return
    end
    local f = self.frame
    if not f then return end

    local p = Theme:GetPalette()
    local now = time()
    local spotter = ns.Spotter
    local eCount, aCount, sCount, totalCount = 0, 0, 0, 0
    local targets = {}
    if spotter then
        eCount, aCount, sCount, totalCount = spotter:GetCounts()
        targets = spotter:GetActiveTargets(self.filterMode)
    end

    if totalCount == 0 then
        self.lastBannerText = nil
        self.lastBannerEntry = nil
        self.lastBannerAt = 0
        self.focusedKey = nil
        self._compassEntry = nil
        self._hasSmoothAngle = false
        self.manualPinnedEmpty = false
        self.userClosed = false
        if f:IsShown() then
            self:Hide()
        end
        return
    end

    f.countsFs:SetText(string.format("|cfff54747E:%d|r |cff40d973A:%d|r |cfffacc3dC:%d|r", eCount, aCount, sCount))
    Theme:SetButtonText(f.collapseBtn, self.collapsed and "+" or "-")

    local topAnchor = f.hdr
    local usedH = 4 + HEADER_H

    local currentTargetGuid = Safe.String(Safe.Call(UnitGUID, "target"))
    local currentTargetName = Safe.String(Safe.Call(UnitName, "target"))
    local parsedTarget = currentTargetName and Compat.ParseCharacterName(currentTargetName)

    -- Pick hero target for Compass Arrow: active targeted enemy/ally/clan -> manual slot focus -> top priority target
    local compassEntry
    if totalCount > 0 then
        local allTargets = spotter and spotter:GetActiveTargets("ALL") or targets
        for _, cand in ipairs(allTargets) do
            local isCur = (currentTargetGuid and cand.guid and currentTargetGuid == cand.guid)
                or (parsedTarget and (parsedTarget.lookupKey == cand.key or (cand.firstName and parsedTarget.firstName:lower() == cand.firstName:lower())))
            if isCur then
                compassEntry = cand
                break
            end
        end
        if not compassEntry and self.focusedKey then
            for _, cand in ipairs(allTargets) do
                if cand.key == self.focusedKey then
                    compassEntry = cand
                    break
                end
            end
        end
        if not compassEntry then
            compassEntry = targets[1] or allTargets[1]
        end
    end
    self._compassEntry = compassEntry

    local showCompass = (compassEntry ~= nil) and not self.collapsed
    if f.compassBar then
        f.compassBar:ClearAllPoints()
        if showCompass then
            f.compassBar:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", (topAnchor == f.hdr) and 2 or 0, -4)
            f.compassBar:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", (topAnchor == f.hdr) and -2 or 0, -4)
            f.compassBar.entry = compassEntry
            ApplySecureMacroAttributes(f.compassBar, compassEntry)
            local colHex = ns.Spotter:GetStanceColor(compassEntry.stance).hex
            local stanceLbl = ns.Spotter:GetStanceLabel(compassEntry.stance)
            local classHex = Compat.ClassHex and Compat.ClassHex(compassEntry.classFile) or "|cffffffff"
            f.compassBar.nameFs:SetText(string.format("%s[%s]|r %s%s|r", colHex, stanceLbl, classHex, compassEntry.displayName or "?"))
            local guildSub = compassEntry.guild and ("<" .. compassEntry.guild .. ">") or ""
            if compassEntry.reason and compassEntry.reason ~= "" then
                guildSub = guildSub .. " · " .. compassEntry.reason
            end
            local isActuallyTargeted = (currentTargetGuid and compassEntry.guid and currentTargetGuid == compassEntry.guid)
                or (parsedTarget and (parsedTarget.lookupKey == compassEntry.key or (compassEntry.firstName and parsedTarget.firstName:lower() == compassEntry.firstName:lower())))
            local targetHint = isActuallyTargeted and ("|cff3fb950[" .. L["Current Target"] .. "]|r") or L["Click to Target"]
            f.compassBar.subFs:SetText(guildSub ~= "" and (guildSub .. " · " .. targetHint) or targetHint)
            f.compassBar:Show()
            topAnchor = f.compassBar
            usedH = usedH + 4 + COMPASS_H
            self:UpdateCompassVisuals(false, 0.04)
        else
            f.compassBar.entry = nil
            ApplySecureMacroAttributes(f.compassBar, nil)
            f.compassBar:Hide()
        end
    end

    local showBanner = not showCompass and self.lastBannerText and (now - (self.lastBannerAt or 0) <= 8)
    f.banner:ClearAllPoints()
    if showBanner then
        f.banner:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", (topAnchor == f.hdr) and 2 or 0, -4)
        f.banner:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", (topAnchor == f.hdr) and -2 or 0, -4)
        f.banner.fs:SetText(self.lastBannerText)
        f.banner.entry = self.lastBannerEntry
        ApplySecureMacroAttributes(f.banner, self.lastBannerEntry)
        f.banner:Show()
        topAnchor = f.banner
        usedH = usedH + 4 + BANNER_H
    else
        f.banner.entry = nil
        ApplySecureMacroAttributes(f.banner, nil)
        f.banner:Hide()
    end

    if self.collapsed then
        f.filterBar:Hide()
        f.listArea:Hide()
        f:SetHeight(usedH + 6)
        return
    end

    f.filterBar:Show()
    f.listArea:Show()
    f.filterBar:ClearAllPoints()
    f.filterBar:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", (topAnchor == f.hdr) and 2 or 0, -4)
    f.filterBar:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", (topAnchor == f.hdr) and -2 or 0, -4)
    usedH = usedH + 4 + FILTER_H

    if f.filterBtns then
        Theme:SetButtonText(f.filterBtns.ALL, string.format("%s (%d)", L["All"], totalCount))
        Theme:SetButtonText(f.filterBtns.ENEMY, string.format("%s (%d)", L["Enemy"], eCount))
        Theme:SetButtonText(f.filterBtns.ALLY, string.format("%s (%d)", L["Ally"], aCount))
        Theme:SetButtonText(f.filterBtns.SAME, string.format("%s (%d)", L["Clan"], sCount))
        for id, fb in pairs(f.filterBtns) do
            Theme:SetButtonActive(fb, self.filterMode == id, id == "ENEMY" and "danger" or "default")
        end
    end

    local shownCount = math.min(#targets, MAX_SLOTS)

    for i = 1, MAX_SLOTS do
        local slot = self.slots[i]
        local entry = targets[i]
        if entry and i <= shownCount then
            slot.entry = entry
            ApplySecureMacroAttributes(slot, entry)

            local rgb = STANCE_RGB[entry.stance] or STANCE_RGB.SAME
            slot.bar:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)

            local isCurrentTarget = (currentTargetGuid and entry.guid and currentTargetGuid == entry.guid)
                or (parsedTarget and (parsedTarget.lookupKey == entry.key or (entry.firstName and parsedTarget.firstName:lower() == entry.firstName:lower())))
            if isCurrentTarget then
                Theme:ApplyBackdrop(slot, "primary", p)
            else
                Theme:ApplyBackdrop(slot, "surface", p)
            end

            local stanceTag = entry.stance == "ENEMY" and L["ENEMY"]
                or (entry.stance == "ALLY" and L["ALLY"] or L["CLAN"])
            local colHex = ns.Spotter:GetStanceColor(entry.stance).hex
            slot.badge:SetText(colHex .. "[" .. stanceTag .. "]|r")

            local classHex = Compat.ClassHex and Compat.ClassHex(entry.classFile) or "|cffffffff"
            slot.nameFs:SetText(classHex .. (entry.displayName or "?") .. "|r")
            slot.lvlFs:SetText(entry.level and ("Lv." .. entry.level) or "")
            slot.lvlFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])

            local guildStr = entry.guild and ("<" .. entry.guild .. ">") or ""
            if entry.reason and entry.reason ~= "" then
                guildStr = guildStr .. " · " .. entry.reason
            end
            slot.subFs:SetText(guildStr)
            slot.subFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])

            local sk = ns.Spotter and ns.Spotter.GetTargetKinematics and ns.Spotter:GetTargetKinematics(entry)
            local distStr = (sk and sk.distText) or ""
            if entry.dead then
                slot.statusFs:SetText("|cff888888" .. L["Dead"] .. "|r")
            elseif entry.onScreen then
                slot.statusFs:SetText("|cff58d8ff" .. distStr .. "|r |cff3fb950· " .. L["On Screen"] .. "|r")
            else
                local age = math.max(0, now - (entry.lastSeen or now))
                slot.statusFs:SetText(string.format("|cff58d8ff%s|r |cff8b949e· %ds|r", distStr, age))
            end

            slot:Show()
        else
            slot.entry = nil
            ApplySecureMacroAttributes(slot, nil)
            slot:Hide()
        end
    end

    if shownCount == 0 then
        f.emptyFs:Show()
    else
        f.emptyFs:Hide()
    end

    local bodyRows = math.max(1, shownCount)
    local listH = PAD + bodyRows * SLOT_H + math.max(0, bodyRows - 1) * SLOT_GAP + 4
    f:SetHeight(usedH + 4 + listH + 8)
end

function SpotterHUD:CreatePromptDialog()
    if self.promptDialog then return self.promptDialog end

    local p = Theme:GetPalette()
    local dlg = CreateFrame("Frame", "SocialCentralSpotterPromptDialog", UIParent, "BackdropTemplate")
    dlg:SetSize(370, 154)
    dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    dlg:SetFrameStrata("DIALOG")
    dlg:SetFrameLevel(110)
    dlg:SetClipsChildren(false)
    Theme:ApplyBackdrop(dlg, "window", p)
    Theme:MakeMovable(dlg, { key = "spotterPrompt" })
    table.insert(UISpecialFrames, "SocialCentralSpotterPromptDialog")

    local titleFs = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleFs:SetPoint("TOPLEFT", 14, -12)
    titleFs:SetPoint("TOPRIGHT", -36, -12)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetTextColor(p.accent[1], p.accent[2], p.accent[3])
    titleFs:SetText(L["SocialCentral — Clan Radar"])
    dlg.titleFs = titleFs

    local closeBtn = Theme:CreateButton(dlg, 20, 20, "X", "default")
    closeBtn:SetPoint("TOPRIGHT", -10, -10)
    closeBtn:SetScript("OnClick", function()
        if ns.db and ns.db.settings then
            ns.db.settings.spotterPromptAnswered = true
        end
        dlg:Hide()
    end)
    dlg.closeBtn = closeBtn

    local bodyFs = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bodyFs:SetPoint("TOPLEFT", 14, -36)
    bodyFs:SetPoint("TOPRIGHT", -14, -36)
    bodyFs:SetJustifyH("LEFT")
    bodyFs:SetWordWrap(true)
    bodyFs:SetTextColor(p.text[1], p.text[2], p.text[3])
    bodyFs:SetText(L["A clan member, ally, or enemy was spotted nearby! Do you want to keep Target Radar and screen notifications enabled?"])
    dlg.bodyFs = bodyFs

    local tipFs = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tipFs:SetPoint("TOPLEFT", bodyFs, "BOTTOMLEFT", 0, -6)
    tipFs:SetPoint("TOPRIGHT", bodyFs, "BOTTOMRIGHT", 0, -6)
    tipFs:SetJustifyH("LEFT")
    tipFs:SetWordWrap(true)
    tipFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
    tipFs:SetText(L["You can change this anytime in SocialCentral > Settings."])
    dlg.tipFs = tipFs

    local keepBtn = Theme:CreateButton(dlg, 140, 24, L["Keep Active"], "primary")
    keepBtn:SetPoint("BOTTOMLEFT", 14, 14)
    Theme:AutoFitButton(keepBtn, 120, 14, 160)
    keepBtn:SetScript("OnClick", function()
        if ns.db and ns.db.settings then
            ns.db.settings.spotterPromptAnswered = true
            ns.db.settings.spotterEnabled = true
        end
        ns:Print(L["Clan Radar notifications enabled. You can adjust them anytime in Settings."])
        dlg:Hide()
        SpotterHUD:Refresh()
    end)
    dlg.keepBtn = keepBtn

    local disableBtn = Theme:CreateButton(dlg, 140, 24, L["Turn Off"], "danger")
    disableBtn:SetPoint("BOTTOMRIGHT", -14, 14)
    Theme:AutoFitButton(disableBtn, 120, 14, 160)
    disableBtn:SetScript("OnClick", function()
        if ns.db and ns.db.settings then
            ns.db.settings.spotterPromptAnswered = true
            ns.db.settings.spotterEnabled = false
        end
        ns:Print(L["Clan Radar notifications disabled. Re-enable anytime in Settings."])
        dlg:Hide()
        SpotterHUD:Hide()
        ns:Emit("SETTINGS_UPDATED")
    end)
    dlg.disableBtn = disableBtn

    dlg:SetScript("OnHide", function()
        if ns.db and ns.db.settings then
            ns.db.settings.spotterPromptAnswered = true
        end
    end)

    self.promptDialog = dlg
    dlg:Hide()
    return dlg
end

function SpotterHUD:ShowFirstTimePrompt()
    local dlg = self.promptDialog or self:CreatePromptDialog()
    if dlg then
        dlg:Show()
    end
end

function SpotterHUD:Show(forceUser)
    if forceUser then
        self.userClosed = false
        local _, _, _, tCount = (ns.Spotter and ns.Spotter.GetCounts) and ns.Spotter:GetCounts() or 0, 0, 0, 0
        if (tCount or 0) == 0 then
            self.manualPinnedEmpty = true
        end
    end
    if not self.frame then
        self:BuildFrame()
    end
    if not self.frame then
        self.pendingAction = "show"
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingAction = "show"
        self.pendingRefresh = true
        return
    end
    local s = ns.db and ns.db.settings
    if s and not s.spotterPromptAnswered then
        self:ShowFirstTimePrompt()
    end
    self:Refresh()
    local _, _, _, totalAfter = (ns.Spotter and ns.Spotter.GetCounts) and ns.Spotter:GetCounts() or 0, 0, 0, 0
    if (totalAfter or 0) > 0 or self.manualPinnedEmpty then
        self.frame:Show()
    end
end

function SpotterHUD:Hide()
    if not self.frame then return end
    self.manualPinnedEmpty = false
    if InCombatLockdown and InCombatLockdown() then
        self.pendingAction = "hide"
        return
    end
    self.frame:Hide()
end

function SpotterHUD:Toggle()
    if self.frame and self.frame:IsShown() then
        self.userClosed = true
        self.manualPinnedEmpty = false
        self:Hide()
    else
        self:Show(true)
    end
end

function SpotterHUD:OnAlert(alert)
    if not alert then return end
    local colHex = ns.Spotter and ns.Spotter:GetStanceColor(alert.stance).hex or "|cfff54747"
    local lbl = ns.Spotter and ns.Spotter:GetStanceLabel(alert.stance) or alert.stance
    local classHex = Compat.ClassHex and Compat.ClassHex(alert.classFile) or "|cffffffff"
    local guildPart = alert.guild and (" <" .. alert.guild .. ">") or ""
    self.lastBannerText = string.format("%s[%s]|r %s%s|r%s  |cff8fb8ff[%s]|r", colHex, lbl, classHex, alert.displayName or "?", guildPart, L["Target"])
    self.lastBannerEntry = alert
    self.lastBannerAt = time()

    local s = ns.db and ns.db.settings
    if s and not s.spotterPromptAnswered then
        self:ShowFirstTimePrompt()
    end

    if s and s.spotterAutoShowHUD ~= false and not self.userClosed then
        if not self.frame or not self.frame:IsShown() then
            self:Show(false)
            return
        end
    end
    self:Refresh()
end

function SpotterHUD:Init()
    self:BuildFrame()
    self:CreatePromptDialog()

    Theme:RegisterListener(function()
        SpotterHUD:UpdateAppearance()
    end)

    ns:On("SPOTTER_UPDATED", function()
        SpotterHUD:Refresh()
    end)

    ns:On("SPOTTER_ALERT", function(alert)
        SpotterHUD:OnAlert(alert)
    end)

    ns:On("SETTINGS_UPDATED", function()
        local s = ns.db and ns.db.settings
        if s and s.spotterEnabled == false then
            SpotterHUD:Hide()
        else
            SpotterHUD:Refresh()
        end
    end)

    ns.RegisterEvent(self, "PLAYER_TARGET_CHANGED", function()
        if SpotterHUD.frame and SpotterHUD.frame:IsShown() then
            if InCombatLockdown and InCombatLockdown() then
                SpotterHUD:UpdateTargetVisuals()
            else
                SpotterHUD:Refresh()
            end
        end
    end)

    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if not SpotterHUD.frame then
            SpotterHUD:BuildFrame()
        end
        if SpotterHUD.pendingAction == "show" then
            SpotterHUD.pendingAction = nil
            SpotterHUD.pendingRefresh = false
            SpotterHUD:Show(false)
        elseif SpotterHUD.pendingAction == "hide" then
            SpotterHUD.pendingAction = nil
            SpotterHUD.pendingRefresh = false
            SpotterHUD:Hide()
        elseif SpotterHUD.pendingRefresh then
            SpotterHUD.pendingRefresh = false
            SpotterHUD:Refresh()
        end
    end)
end

ns.SpotterHUD = SpotterHUD
table.insert(ns.modules, SpotterHUD)
