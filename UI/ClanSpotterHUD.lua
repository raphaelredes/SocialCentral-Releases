local _, ns = ...

local Compat = ns.Compat
local Safe = ns.Safe
local Theme = ns.Theme
local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })

local SpotterHUD = {
    frame = nil,
    combatArrowFrame = nil,
    filterMode = "ALL",
    collapsed = false,
    interactionOpen = false,
    interactionKey = nil,
    cycleIndex = 1,
    pendingRefresh = false,
    pendingAction = nil, -- "show" | "hide" | nil
    userClosed = false,
    manualPinnedEmpty = false,
    focusedKey = nil,
    _compassEntry = nil,
    _smoothAngle = 0,
    _hasSmoothAngle = false,
    _kinematicsElapsed = 0,
    _combatKinElapsed = 0,
}

local HUD_WIDTH = 248
local PILL_H = 48
local ACTION_H = 52
local ARROW_TEX = "Interface\\AddOns\\SocialCentral\\Media\\arrow"

local STANCE_RGB = {
    ENEMY     = { 0.96, 0.28, 0.28 },
    WATCHLIST = { 1.00, 0.65, 0.20 },
    FRIEND    = { 0.35, 0.78, 1.00 },
    ALLY      = { 0.25, 0.85, 0.45 },
    SAME      = { 0.98, 0.80, 0.24 },
}

local function GetSpotterTotalCount()
    if ns.Spotter and ns.Spotter.GetCounts then
        local _, _, _, total = ns.Spotter:GetCounts()
        return total or 0
    end
    return 0
end

local function RotateArrowTexture(tex, angleRad)
    if not tex then return end
    local a = angleRad or 0
    if tex.SetRotation then
        tex:SetRotation(a)
        return
    end
    if tex.SetTexCoord then
        local s = math.sqrt(2)
        local cosA = math.cos(a)
        local sinA = math.sin(a)
        local function corner(cx, cy)
            return 0.5 + (cx * cosA - cy * sinA) / s, 0.5 + (cx * sinA + cy * cosA) / s
        end
        local ulx, uly = corner(-0.5, -0.5)
        local llx, lly = corner(-0.5, 0.5)
        local urx, ury = corner(0.5, -0.5)
        local lrx, lry = corner(0.5, 0.5)
        tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
    end
end

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

local function BuildTargetMacroText(entry, liveUnit)
    if not entry then return "" end

    -- 1. When a verified live unit token is active right now (nameplate1..40, party1..4, raid1..40, focus, soft*),
    -- target that exact 3D unit directly so recycled tokens or twin FirstNames never steal focus.
    if type(liveUnit) == "string" and liveUnit ~= "" and liveUnit ~= "target" and liveUnit ~= "mouseover"
        and not liveUnit:find("[%c%|%/%\\%[%]%;%s]") then
        return "/target [@" .. liveUnit .. ",exists]"
    end

    local lines = {}
    local seen = {}
    local function addLine(cmd)
        if cmd and cmd ~= "" and not seen[cmd] then
            seen[cmd] = true
            table.insert(lines, cmd)
        end
    end

    -- 2. Exact raw unitName returned by UnitName(unit) in WoW Forever
    if entry.unitName and type(entry.unitName) == "string" then
        local cleanRaw = entry.unitName:gsub("[%c%|%/%\\%[%]%;\r\n]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        if cleanRaw ~= "" then
            addLine("/targetexact " .. cleanRaw)
        end
    end

    -- 3. All Forever target variants (FirstName Surname, FirstName-Surname, FirstName)
    local cleanDisplay = entry.displayName and entry.displayName:gsub("[%c%|%/%\\%[%]%;\r\n]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local candidates = Compat.GetForeverTargetVariants and Compat.GetForeverTargetVariants(cleanDisplay or entry.firstName) or {}
    for _, cand in ipairs(candidates) do
        local c = cand:gsub("[%c%|%/%\\%[%]%;\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if c ~= "" then
            addLine("/targetexact " .. c)
        end
    end

    -- 4. Prefix fallback (/target FirstName)
    local firstName = entry.firstName or (cleanDisplay and cleanDisplay:match("^([^%s%-]+)"))
    local cleanFirst = firstName and firstName:gsub("[%c%|%/%\\%[%]%;\r\n]", ""):gsub("%s+", "")
    if cleanFirst and cleanFirst ~= "" then
        addLine("/targetexact " .. cleanFirst)
        addLine("/target " .. cleanFirst)
    end

    return table.concat(lines, "\n")
end

local function ApplySecureMacroAttributes(btn, entry, liveUnit)
    if not btn then return end
    if InCombatLockdown and InCombatLockdown() then
        SpotterHUD.pendingRefresh = true
        return
    end
    btn:SetAttribute("useOnKeyDown", false)
    btn:SetAttribute("type2", nil)
    btn:SetAttribute("*type2", nil)
    btn:SetAttribute("macrotext2", nil)
    btn:SetAttribute("*macrotext2", nil)
    if not entry then
        btn:SetAttribute("type", nil)
        btn:SetAttribute("type1", nil)
        btn:SetAttribute("*type1", nil)
        btn:SetAttribute("unit", nil)
        btn:SetAttribute("macrotext", nil)
        btn:SetAttribute("macrotext1", nil)
        btn:SetAttribute("*macrotext1", nil)
        btn._lastMacroText = nil
        return
    end

    local entryTable = (type(entry) == "table") and entry or nil
    local mText = entryTable and BuildTargetMacroText(entryTable, liveUnit) or tostring(entry)
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("type1", "macro")
    btn:SetAttribute("*type1", "macro")
    btn:SetAttribute("unit", nil)
    btn:SetAttribute("macrotext", mText)
    btn:SetAttribute("macrotext1", mText)
    btn:SetAttribute("*macrotext1", mText)
    btn._lastMacroText = mText
end

local function IsEntryCurrentlyTargeted(entry, currentTargetGuid, parsedTarget)
    if not entry then return false end
    if currentTargetGuid and entry.guid then
        return currentTargetGuid == entry.guid
    end
    if parsedTarget then
        if parsedTarget.lookupKey == entry.key then
            return true
        end
        local entryHasSurname = type(entry.displayName) == "string" and entry.displayName:find("%s") ~= nil
        if (not parsedTarget.surname or not entryHasSurname)
            and entry.firstName and parsedTarget.firstName
            and parsedTarget.firstName:lower() == entry.firstName:lower() then
            return true
        end
    end
    return false
end

local function HandleTargetClick(entry)
    if not entry then return end
    SpotterHUD.focusedKey = entry.key
    if SpotterHUD.interactionOpen and SpotterHUD.interactionKey == entry.key then
        -- Keep open or toggle if user clicked again after already opening
        SpotterHUD.interactionOpen = true
    else
        SpotterHUD.interactionOpen = true
        SpotterHUD.interactionKey = entry.key
    end
    if InCombatLockdown and InCombatLockdown() then
        SpotterHUD:UpdateTargetVisuals()
    else
        SpotterHUD:Refresh()
    end
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

function SpotterHUD:BuildFrame()
    if self.frame then return self.frame end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingRefresh = true
        return nil
    end

    local f = CreateFrame("Frame", "SocialCentralSpotterFrame", UIParent, "BackdropTemplate")
    f:SetSize(HUD_WIDTH, PILL_H)
    f:SetPoint("TOP", UIParent, "TOP", 0, -96)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(40)
    if f.SetClipsChildren then
        f:SetClipsChildren(true)
    end
    f:EnableMouse(true)

    local stanceBar = f:CreateTexture(nil, "OVERLAY")
    stanceBar:SetWidth(3)
    stanceBar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    stanceBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 2)
    stanceBar:SetColorTexture(0.98, 0.80, 0.24, 1)
    f.stanceBar = stanceBar

    -- Main clickable Arrow Pill (SecureActionButtonTemplate: selects target on screen & opens Interaction Drawer)
    local compassBar = CreateFrame("Button", "SocialCentralSpotterCompass", f, "SecureActionButtonTemplate,BackdropTemplate")
    compassBar:SetHeight(PILL_H - 6)
    compassBar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -3)
    compassBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    if compassBar.SetClipsChildren then
        compassBar:SetClipsChildren(true)
    end
    compassBar:RegisterForClicks("AnyUp")
    compassBar:RegisterForDrag("LeftButton")
    ApplySecureMacroAttributes(compassBar, nil)

    local compassGlow = compassBar:CreateTexture(nil, "HIGHLIGHT")
    compassGlow:SetAllPoints()
    compassGlow:SetColorTexture(1, 1, 1, 0.08)

    local arrowBox = CreateFrame("Frame", nil, compassBar)
    arrowBox:SetSize(36, 36)
    arrowBox:SetPoint("LEFT", 4, 0)
    arrowBox:EnableMouse(false)
    if arrowBox.SetClipsChildren then
        arrowBox:SetClipsChildren(false)
    end
    local arrowAura = arrowBox:CreateTexture(nil, "ARTWORK")
    arrowAura:SetSize(34, 34)
    arrowAura:SetPoint("CENTER")
    arrowAura:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    arrowAura:SetVertexColor(0.05, 0.25, 0.36, 0.40)
    arrowBox.aura = arrowAura

    local arrowTex = arrowBox:CreateTexture(nil, "OVERLAY")
    arrowTex:SetSize(32, 32)
    arrowTex:SetPoint("CENTER")
    arrowTex:SetTexture(ARROW_TEX)
    arrowBox.arrowTex = arrowTex
    compassBar.arrowBox = arrowBox
    compassBar.arrowTex = arrowTex

    local noSignalDot = arrowBox:CreateTexture(nil, "OVERLAY")
    noSignalDot:SetSize(14, 14)
    noSignalDot:SetPoint("CENTER")
    noSignalDot:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    noSignalDot:SetVertexColor(0.95, 0.78, 0.25, 0.92)
    noSignalDot:Hide()
    arrowBox.noSignalDot = noSignalDot
    compassBar.noSignalDot = noSignalDot

    local compassNameFs = compassBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    compassNameFs:SetPoint("TOPLEFT", arrowBox, "TOPRIGHT", 6, -3)
    compassNameFs:SetPoint("TOPRIGHT", compassBar, "TOPRIGHT", -54, -3)
    compassNameFs:SetJustifyH("LEFT")
    compassNameFs:SetWordWrap(false)
    compassBar.nameFs = compassNameFs

    local compassDistFs = compassBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    compassDistFs:SetPoint("BOTTOMLEFT", arrowBox, "BOTTOMRIGHT", 6, 3)
    compassDistFs:SetPoint("BOTTOMRIGHT", compassBar, "BOTTOMRIGHT", -6, 3)
    compassDistFs:SetJustifyH("LEFT")
    compassDistFs:SetWordWrap(false)
    compassBar.distFs = compassDistFs

    local compassSubFs = compassBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    compassSubFs:Hide()
    compassBar.subFs = compassSubFs

    compassBar:SetScript("PostClick", function(selfBtn, mouseBtn, down)
        if down or f._scDragging then return end
        if selfBtn.entry then
            HandleTargetClick(selfBtn.entry)
            if mouseBtn == "RightButton" then
                OpenTargetContextMenu(selfBtn, selfBtn.entry)
            end
        end
    end)
    compassBar:HookScript("OnDragStart", function()
        if f._scBeginDrag then f._scBeginDrag() end
    end)
    compassBar:HookScript("OnDragStop", function()
        if f._scEndDrag then f._scEndDrag() end
    end)
    compassBar:SetScript("OnEnter", function(selfBtn)
        if selfBtn.entry then
            local e = selfBtn.entry
            local l1 = e.guild and ("<" .. e.guild .. ">") or ""
            local locTxt = e.fullLocationText or e.locationText or ""
            if locTxt ~= "" then
                l1 = (l1 ~= "") and (l1 .. "\n" .. L["Location"] .. ": " .. locTxt) or (L["Location"] .. ": " .. locTxt)
            end
            ShowHUDTooltip(
                selfBtn,
                e.displayName or "?",
                l1,
                L["Left-click: Target player  |  Right-click: Actions"]
            )
        end
    end)
    compassBar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.compassBar = compassBar

    -- Top-right micro buttons (Dismiss [X] and optional [1/2] target cycle when >1 nearby)
    local closeBtn = Theme:CreateButton(f, 16, 16, "X", "danger")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetFrameLevel(compassBar:GetFrameLevel() + 6)
    closeBtn:SetScript("OnClick", function()
        local entry = SpotterHUD._compassEntry
        if SpotterHUD.interactionOpen then
            SpotterHUD.interactionOpen = false
            SpotterHUD.interactionKey = nil
            SpotterHUD:Refresh()
            return
        end
        if entry and ns.Spotter and ns.Spotter.DismissTarget then
            ns.Spotter:DismissTarget(entry.key)
        end
        local remaining = GetSpotterTotalCount()
        if remaining == 0 then
            SpotterHUD.manualPinnedEmpty = false
            SpotterHUD:Hide()
        else
            SpotterHUD:Refresh()
        end
    end)
    f.closeBtn = closeBtn

    local cycleBtn = Theme:CreateButton(f, 32, 16, "1/1", "default")
    cycleBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    cycleBtn:SetFrameLevel(compassBar:GetFrameLevel() + 6)
    cycleBtn:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then return end
        local all = ns.Spotter and ns.Spotter:GetActiveTargets("ALL") or {}
        if #all > 1 then
            SpotterHUD.cycleIndex = ((SpotterHUD.cycleIndex or 1) % #all) + 1
            local nextEntry = all[SpotterHUD.cycleIndex]
            if nextEntry then
                SpotterHUD.focusedKey = nextEntry.key
                if SpotterHUD.interactionOpen then
                    SpotterHUD.interactionKey = nextEntry.key
                end
            end
            SpotterHUD:Refresh()
        end
    end)
    cycleBtn:Hide()
    f.cycleBtn = cycleBtn

    -- Expandable On-Click Interaction Drawer (shown only after clicking the Arrow Pill)
    local actionPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    actionPanel:SetHeight(ACTION_H)
    actionPanel:SetPoint("TOPLEFT", compassBar, "BOTTOMLEFT", 0, -2)
    actionPanel:SetPoint("TOPRIGHT", compassBar, "BOTTOMRIGHT", 0, -2)
    if actionPanel.SetClipsChildren then
        actionPanel:SetClipsChildren(true)
    end
    f.actionPanel = actionPanel

    local promptFs = actionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    promptFs:SetPoint("TOPLEFT", 6, -4)
    promptFs:SetPoint("TOPRIGHT", -6, -4)
    promptFs:SetJustifyH("LEFT")
    promptFs:SetWordWrap(false)
    actionPanel.promptFs = promptFs

    local btnW = 54
    local whisperBtn = Theme:CreateButton(actionPanel, btnW, 20, L["Whisper"], "primary")
    whisperBtn:SetPoint("BOTTOMLEFT", 5, 4)
    whisperBtn:SetScript("OnClick", function()
        local e = SpotterHUD._compassEntry
        if not e then return end
        if ns.Chat and ns.Chat.OpenDirectConversation then
            ns.Chat:OpenDirectConversation({
                targetName = e.targetName or e.displayName,
                classFile = e.classFile,
                autoProbe = true,
                openUI = true,
            })
            if ns.UI and ns.UI.OpenTab then
                ns.UI:OpenTab("chat")
            end
        elseif Compat.Whisper then
            Compat.Whisper(e.targetName or e.displayName)
        end
        SpotterHUD.interactionOpen = false
        SpotterHUD:Refresh()
    end)
    actionPanel.whisperBtn = whisperBtn

    local scoutBtn = Theme:CreateButton(actionPanel, btnW + 10, 20, L["Scout Alert"], "danger")
    scoutBtn:SetPoint("BOTTOMLEFT", 5, 4)
    scoutBtn:SetScript("OnClick", function()
        local e = SpotterHUD._compassEntry
        if not e then return end
        if ns.Clan and ns.Clan.BroadcastScoutAlert then
            ns.Clan:BroadcastScoutAlert(e.displayName, e.guild or "", e.level or 0, e.classFile, e.zone or e.subZone or "", e.coordsText or "")
        end
        SpotterHUD.interactionOpen = false
        SpotterHUD:Refresh()
    end)
    scoutBtn:Hide()
    actionPanel.scoutBtn = scoutBtn

    local tellBtn = Theme:CreateButton(actionPanel, 34, 20, "/w", "default")
    tellBtn:SetPoint("LEFT", whisperBtn, "RIGHT", 3, 0)
    tellBtn:SetScript("OnClick", function()
        local e = SpotterHUD._compassEntry
        if e and Compat.Whisper then
            Compat.Whisper(e.targetName or e.displayName)
        end
        SpotterHUD.interactionOpen = false
        SpotterHUD:Refresh()
    end)
    actionPanel.tellBtn = tellBtn

    local inviteBtn = Theme:CreateButton(actionPanel, btnW, 20, L["Invite"], "default")
    inviteBtn:SetPoint("LEFT", tellBtn, "RIGHT", 3, 0)
    inviteBtn:SetScript("OnClick", function()
        local e = SpotterHUD._compassEntry
        if not e then return end
        if e.stance == "ENEMY" then
            if ns.UI and ns.UI.OpenDiplomacyModal and e.guild and e.guild ~= "" then
                ns.UI:OpenDiplomacyModal(e.guild, e.stance, nil)
            end
        elseif Compat.Invite then
            Compat.Invite(e.targetName or e.displayName)
        end
        SpotterHUD.interactionOpen = false
        SpotterHUD:Refresh()
    end)
    actionPanel.inviteBtn = inviteBtn

    local watchBtn = Theme:CreateButton(actionPanel, btnW + 24, 20, "+ " .. L["Watchlist"], "default")
    watchBtn:SetPoint("LEFT", inviteBtn, "RIGHT", 3, 0)
    watchBtn:SetScript("OnClick", function()
        local e = SpotterHUD._compassEntry
        if e and ns.Watchlist and ns.Watchlist.Add then
            ns.Watchlist:Add(e.displayName, e.guild or "")
        end
        SpotterHUD.interactionOpen = false
        SpotterHUD:Refresh()
    end)
    actionPanel.watchBtn = watchBtn

    actionPanel:Hide()

    Theme:MakeMovable(f, {
        key = "spotter",
        anchor = "TOP",
        combatLock = true,
        handles = { f, actionPanel },
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
    self:BuildCombatArrowFrame()
    self:UpdateAppearance()
    f:Hide()
    return f
end

function SpotterHUD:BuildCombatArrowFrame()
    if self.combatArrowFrame then return self.combatArrowFrame end
    local cf = CreateFrame("Frame", "SocialCentralSpotterCombatArrow", UIParent, "BackdropTemplate")
    cf:SetSize(HUD_WIDTH, PILL_H)
    cf:SetPoint("TOP", UIParent, "TOP", 0, -96)
    cf:SetFrameStrata("MEDIUM")
    cf:SetFrameLevel(45)

    local stanceBar = cf:CreateTexture(nil, "OVERLAY")
    stanceBar:SetWidth(3)
    stanceBar:SetPoint("TOPLEFT", cf, "TOPLEFT", 2, -2)
    stanceBar:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 2, 2)
    stanceBar:SetColorTexture(0.98, 0.80, 0.24, 1)
    cf.stanceBar = stanceBar

    local arrowBox = CreateFrame("Frame", nil, cf)
    arrowBox:SetSize(36, 36)
    arrowBox:SetPoint("LEFT", 8, 0)
    if arrowBox.SetClipsChildren then
        arrowBox:SetClipsChildren(false)
    end
    local arrowAura = arrowBox:CreateTexture(nil, "ARTWORK")
    arrowAura:SetSize(34, 34)
    arrowAura:SetPoint("CENTER")
    arrowAura:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    arrowAura:SetVertexColor(0.05, 0.25, 0.36, 0.40)
    arrowBox.aura = arrowAura

    local arrowTex = arrowBox:CreateTexture(nil, "OVERLAY")
    arrowTex:SetSize(32, 32)
    arrowTex:SetPoint("CENTER")
    arrowTex:SetTexture(ARROW_TEX)
    arrowBox.arrowTex = arrowTex
    cf.arrowBox = arrowBox
    cf.arrowTex = arrowTex

    local noSignalDot = arrowBox:CreateTexture(nil, "OVERLAY")
    noSignalDot:SetSize(14, 14)
    noSignalDot:SetPoint("CENTER")
    noSignalDot:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    noSignalDot:SetVertexColor(0.95, 0.78, 0.25, 0.92)
    noSignalDot:Hide()
    arrowBox.noSignalDot = noSignalDot
    cf.noSignalDot = noSignalDot

    local nameFs = cf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFs:SetPoint("TOPLEFT", arrowBox, "TOPRIGHT", 6, -4)
    nameFs:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -8, -4)
    nameFs:SetJustifyH("LEFT")
    nameFs:SetWordWrap(false)
    cf.nameFs = nameFs

    local distFs = cf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    distFs:SetPoint("BOTTOMLEFT", arrowBox, "BOTTOMRIGHT", 6, 4)
    distFs:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -8, 4)
    distFs:SetJustifyH("LEFT")
    distFs:SetWordWrap(false)
    cf.distFs = distFs

    local subFs = cf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subFs:Hide()
    cf.subFs = subFs

    cf:SetScript("OnUpdate", function(_, elapsed)
        SpotterHUD._combatKinElapsed = (SpotterHUD._combatKinElapsed or 0) + elapsed
        if SpotterHUD._combatKinElapsed >= 0.04 then
            local dt = SpotterHUD._combatKinElapsed
            SpotterHUD._combatKinElapsed = 0
            SpotterHUD:UpdateCompassVisuals(false, dt)
        end
    end)

    cf:Hide()
    Theme:ApplyBackdrop(cf, "window", Theme:GetPalette())
    self.combatArrowFrame = cf
    return cf
end

function SpotterHUD:ShowCombatArrowFallback()
    local cf = self.combatArrowFrame or self:BuildCombatArrowFrame()
    if not cf then return end
    local total = GetSpotterTotalCount()
    if total == 0 or self.userClosed then
        cf:Hide()
        return
    end
    local allTargets = ns.Spotter and ns.Spotter:GetActiveTargets("ALL") or {}
    local entry
    if self.focusedKey then
        for _, cand in ipairs(allTargets) do
            if cand.key == self.focusedKey then
                entry = cand
                break
            end
        end
    end
    if not entry then
        local currentTargetGuid = Safe.String(Safe.Call(UnitGUID, "target"))
        local currentTargetName = Safe.String(Safe.Call(UnitName, "target"))
        local parsedTarget = currentTargetName and Compat.ParseCharacterName(currentTargetName)
        for _, cand in ipairs(allTargets) do
            if IsEntryCurrentlyTargeted(cand, currentTargetGuid, parsedTarget) then
                entry = cand
                break
            end
        end
    end
    entry = entry or allTargets[1]
    if not entry then
        cf:Hide()
        return
    end
    self._compassEntry = entry
    local rgb = STANCE_RGB[entry.stance] or STANCE_RGB.SAME
    if cf.stanceBar then
        cf.stanceBar:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    end
    local stanceTag = entry.stance == "ENEMY" and L["ENEMY"]
        or (entry.stance == "WATCHLIST" and L["WATCHLIST"])
        or (entry.stance == "FRIEND" and L["FRIEND"])
        or (entry.stance == "ALLY" and L["ALLY"] or L["CLAN"])
    local colHex = ns.Spotter:GetStanceColor(entry.stance).hex
    local classHex = Compat.ClassHex and Compat.ClassHex(entry.classFile) or "|cffffffff"
    cf.nameFs:SetText(string.format("%s[%s]|r %s%s|r", colHex, stanceTag, classHex, entry.displayName or "?"))
    cf.subFs:SetText(entry.locationText or (entry.guild and ("<" .. entry.guild .. ">") or ""))
    cf:Show()
    self:UpdateCompassVisuals(true, 0.04)
end

function SpotterHUD:UpdateAppearance()
    local p = Theme:GetPalette()
    if self.combatArrowFrame then
        Theme:ApplyBackdrop(self.combatArrowFrame, "window", p)
        self.combatArrowFrame.subFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
    end

    local f = self.frame
    if not f then return end

    Theme:ApplyBackdrop(f, "window", p)
    if f.compassBar then
        f.compassBar.subFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
    end
    if f.actionPanel then
        Theme:ApplyBackdrop(f.actionPanel, "inset", p)
        f.actionPanel.promptFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
        Theme:StyleButton(f.actionPanel.whisperBtn, "primary")
        Theme:StyleButton(f.actionPanel.tellBtn, "default")
        Theme:StyleButton(f.actionPanel.inviteBtn, "default")
        Theme:StyleButton(f.actionPanel.watchBtn, "default")
    end

    if self.promptDialog then
        Theme:ApplyBackdrop(self.promptDialog, "window", p)
        self.promptDialog.titleFs:SetTextColor(p.accent[1], p.accent[2], p.accent[3])
        self.promptDialog.bodyFs:SetTextColor(p.text[1], p.text[2], p.text[3])
        self.promptDialog.tipFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
        Theme:StyleButton(self.promptDialog.closeBtn, "default")
        Theme:StyleButton(self.promptDialog.keepBtn, "primary")
        Theme:StyleButton(self.promptDialog.disableBtn, "danger")
    end

    Theme:StyleButton(f.closeBtn, "danger")
    Theme:StyleButton(f.cycleBtn, "default")
    self:Refresh()
end

local function ApplyCompassBarVisuals(bar, entry, kin, smoothAngle)
    if not bar then return end

    local rgb = STANCE_RGB[entry.stance] or STANCE_RGB.SAME
    local hasAngle = kin and kin.hasAngle == true
    local zoneShort = (entry.subZone and entry.subZone ~= "") and entry.subZone or ""
    local locPart = (zoneShort ~= "") and (" |cff8b949e· " .. zoneShort .. "|r") or ""

    if hasAngle then
        if bar.noSignalDot then bar.noSignalDot:Hide() end
        if bar.arrowTex then bar.arrowTex:Show() end
        RotateArrowTexture(bar.arrowTex, smoothAngle)
    else
        if bar.arrowTex then bar.arrowTex:Hide() end
        if bar.noSignalDot then
            if entry.dead then
                bar.noSignalDot:SetVertexColor(0.55, 0.55, 0.55, 0.65)
            else
                bar.noSignalDot:SetVertexColor(rgb[1], rgb[2], rgb[3], 0.95)
            end
            bar.noSignalDot:Show()
        end
    end

    if entry.dead then
        if bar.arrowBox and bar.arrowBox.aura then
            bar.arrowBox.aura:SetVertexColor(0.4, 0.4, 0.4, 0.20)
        end
        if bar.arrowTex and bar.arrowTex.SetVertexColor then
            bar.arrowTex:SetVertexColor(0.55, 0.55, 0.55, 0.65)
        end
        local bearing = hasAngle and FormatBearingText(kin.angle) or L["Nearby"]
        bar.distFs:SetText(string.format("|cff888888%s|r |cff8b949e· %s|r%s", L["Dead"], bearing, locPart))
    else
        local isAhead = hasAngle and math.abs(kin.angle or 0) <= 0.42
        if bar.arrowBox and bar.arrowBox.aura then
            bar.arrowBox.aura:SetVertexColor(rgb[1], rgb[2], rgb[3], hasAngle and 0.42 or 0.24)
        end
        if bar.arrowTex and bar.arrowTex.SetVertexColor then
            if isAhead then
                bar.arrowTex:SetVertexColor(0.35, 1.0, 0.58, 1)
            else
                bar.arrowTex:SetVertexColor(1, 1, 1, 1)
            end
        end
        local bearing = hasAngle and FormatBearingText(kin.angle) or L["Nearby"]
        bar.distFs:SetText(string.format("|cff58d8ff%s|r |cffffd100· %s|r%s", kin.distText or L["Nearby"], bearing, locPart))
    end
end

function SpotterHUD:UpdateCompassVisuals(snap, dt)
    local f = self.frame
    local cf = self.combatArrowFrame
    local mainCompassActive = f and f:IsShown() and f.compassBar and f.compassBar:IsShown()
    local combatCompassActive = cf and cf:IsShown()
    if not (mainCompassActive or combatCompassActive) then return end

    local entry = self._compassEntry
    if not (entry and ns.Spotter and ns.Spotter.GetTargetKinematics) then return end

    local kin = ns.Spotter:GetTargetKinematics(entry)
    if not kin then return end

    -- Keep the secure target macro synced with any newly resolved live unitToken (e.g. nameplate1) outside combat
    if mainCompassActive and not (InCombatLockdown and InCombatLockdown()) then
        local expectedMacro = BuildTargetMacroText(entry, kin.unit)
        if expectedMacro ~= f.compassBar._lastMacroText then
            ApplySecureMacroAttributes(f.compassBar, entry, kin.unit)
        end
    end

    if kin.hasAngle and kin.angle then
        local targetAngle = kin.angle
        if snap or not self._hasSmoothAngle then
            self._smoothAngle = targetAngle
            self._hasSmoothAngle = true
        else
            local step = math.min(1, (dt or 0.04) * 14)
            self._smoothAngle = self._smoothAngle + ShortestAngleDelta(self._smoothAngle, targetAngle) * step
        end
    else
        self._hasSmoothAngle = false
        self._smoothAngle = 0
    end

    if mainCompassActive then
        ApplyCompassBarVisuals(f.compassBar, entry, kin, self._smoothAngle)
        if f.actionPanel and f.actionPanel:IsShown() and f.actionPanel.promptFs then
            local guildAndLoc = entry.guild and ("<" .. entry.guild .. ">") or ""
            if entry.locationText and entry.locationText ~= "" then
                guildAndLoc = (guildAndLoc ~= "") and (guildAndLoc .. " · " .. entry.locationText) or entry.locationText
            end
            local desiredPrompt = guildAndLoc ~= "" and guildAndLoc or (entry.displayName or "?")
            if f.actionPanel._lastPromptText ~= desiredPrompt then
                f.actionPanel._lastPromptText = desiredPrompt
                f.actionPanel.promptFs:SetText(desiredPrompt)
            end
        end
    end
    if combatCompassActive then
        ApplyCompassBarVisuals(cf, entry, kin, self._smoothAngle)
        if cf.subFs then
            local guildAndLoc = entry.guild and ("<" .. entry.guild .. ">") or L["Target Radar"]
            if entry.locationText and entry.locationText ~= "" then
                guildAndLoc = guildAndLoc .. " · " .. entry.locationText
            end
            if cf._lastSubText ~= guildAndLoc then
                cf._lastSubText = guildAndLoc
                cf.subFs:SetText(guildAndLoc)
            end
        end
    end
end

function SpotterHUD:UpdateTargetVisuals()
    local f = self.frame
    if not (f and f:IsShown() and f.compassBar) then return end

    local allTargets = ns.Spotter and ns.Spotter:GetActiveTargets("ALL") or {}
    local entry = self._compassEntry
    if entry then
        local stillActive = false
        for _, cand in ipairs(allTargets) do
            if cand.key == entry.key then
                entry = cand
                stillActive = true
                break
            end
        end
        if not stillActive then
            entry = allTargets[1]
            self._compassEntry = entry
        end
    else
        entry = allTargets[1]
        self._compassEntry = entry
    end
    if not entry then return end

    local currentTargetGuid = Safe.String(Safe.Call(UnitGUID, "target"))
    local currentTargetName = Safe.String(Safe.Call(UnitName, "target"))
    local parsedTarget = currentTargetName and Compat.ParseCharacterName(currentTargetName)
    local isTargeted = IsEntryCurrentlyTargeted(entry, currentTargetGuid, parsedTarget)

    local p = Theme:GetPalette()
    if isTargeted then
        Theme:ApplyBackdrop(f.compassBar, "primary", p)
    elseif f.compassBar.SetBackdrop then
        f.compassBar:SetBackdrop(nil)
    end
    self:UpdateCompassVisuals(true, 0.04)
end

function SpotterHUD:Refresh()
    if InCombatLockdown and InCombatLockdown() then
        self.pendingRefresh = true
        if not (self.frame and self.frame:IsShown()) then
            local s = ns.db and ns.db.settings
            if not s or (s.spotterEnabled ~= false and s.spotterAutoShowHUD ~= false) then
                self.pendingAction = "show"
                self:ShowCombatArrowFallback()
            end
        else
            self:UpdateTargetVisuals()
        end
        return
    end
    local f = self.frame
    if not f then return end

    local p = Theme:GetPalette()
    local spotter = ns.Spotter
    local _, _, _, totalCount = 0, 0, 0, 0
    local allTargets = {}
    if spotter then
        _, _, _, totalCount = spotter:GetCounts()
        allTargets = spotter:GetActiveTargets("ALL")
    end

    if totalCount == 0 and not self.manualPinnedEmpty then
        self.focusedKey = nil
        self.interactionOpen = false
        self.interactionKey = nil
        self._compassEntry = nil
        self._hasSmoothAngle = false
        self.userClosed = false
        if self.combatArrowFrame then
            self.combatArrowFrame:Hide()
        end
        if f:IsShown() then
            self:Hide()
        end
        return
    elseif totalCount > 0 then
        self.manualPinnedEmpty = false
        local s = ns.db and ns.db.settings
        if not f:IsShown() and not self.userClosed and (not s or (s.spotterEnabled ~= false and s.spotterAutoShowHUD ~= false)) then
            f:Show()
        end
    end

    if self.combatArrowFrame and f:IsShown() then
        self.combatArrowFrame:Hide()
    end

    local currentTargetGuid = Safe.String(Safe.Call(UnitGUID, "target"))
    local currentTargetName = Safe.String(Safe.Call(UnitName, "target"))
    local parsedTarget = currentTargetName and Compat.ParseCharacterName(currentTargetName)

    -- Pick active target for the Minimalist Arrow Pill:
    -- 1. Manually focused target -> 2. Currently targeted player -> 3. Top priority target
    local compassEntry
    local activeIdx = 1
    if totalCount > 0 then
        if self.focusedKey then
            for idx, cand in ipairs(allTargets) do
                if cand.key == self.focusedKey then
                    compassEntry = cand
                    activeIdx = idx
                    break
                end
            end
        end
        if not compassEntry then
            for idx, cand in ipairs(allTargets) do
                if IsEntryCurrentlyTargeted(cand, currentTargetGuid, parsedTarget) then
                    compassEntry = cand
                    activeIdx = idx
                    break
                end
            end
        end
        if not compassEntry then
            compassEntry = allTargets[1]
            activeIdx = 1
        end
    end
    self.cycleIndex = activeIdx
    self._compassEntry = compassEntry

    if totalCount > 1 and f.cycleBtn then
        Theme:SetButtonText(f.cycleBtn, string.format("%d/%d", activeIdx, totalCount))
        f.cycleBtn:Show()
        f.compassBar.nameFs:SetPoint("TOPRIGHT", f.compassBar, "TOPRIGHT", -54, -3)
    else
        if f.cycleBtn then f.cycleBtn:Hide() end
        f.compassBar.nameFs:SetPoint("TOPRIGHT", f.compassBar, "TOPRIGHT", -22, -3)
    end

    if not compassEntry then
        -- Empty state when opened manually via /sc radar
        if f.stanceBar then
            f.stanceBar:SetColorTexture(p.accent[1], p.accent[2], p.accent[3], 1)
        end
        ApplySecureMacroAttributes(f.compassBar, nil)
        if f.compassBar.SetBackdrop then
            f.compassBar:SetBackdrop(nil)
        end
        f.compassBar.entry = nil
        if f.compassBar.arrowTex then
            f.compassBar.arrowTex:Hide()
        end
        if f.compassBar.noSignalDot then
            f.compassBar.noSignalDot:SetVertexColor(0.55, 0.55, 0.55, 0.65)
            f.compassBar.noSignalDot:Show()
        end
        f.compassBar.nameFs:SetText(L["Target Radar"])
        f.compassBar.distFs:SetText("|cff8b949e" .. L["No targets currently detected."] .. "|r")
        f.actionPanel:Hide()
        f:SetHeight(PILL_H)
        return
    end

    local rgb = STANCE_RGB[compassEntry.stance] or STANCE_RGB.SAME
    if f.stanceBar then
        f.stanceBar:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    end

    local kin = spotter and spotter.GetTargetKinematics and spotter:GetTargetKinematics(compassEntry)
    f.compassBar.entry = compassEntry
    ApplySecureMacroAttributes(f.compassBar, compassEntry, kin and kin.unit)

    local stanceTag = compassEntry.stance == "ENEMY" and L["ENEMY"]
        or (compassEntry.stance == "WATCHLIST" and L["WATCHLIST"])
        or (compassEntry.stance == "FRIEND" and L["FRIEND"])
        or (compassEntry.stance == "ALLY" and L["ALLY"] or L["CLAN"])
    local colHex = ns.Spotter:GetStanceColor(compassEntry.stance).hex
    local classHex = Compat.ClassHex and Compat.ClassHex(compassEntry.classFile) or "|cffffffff"
    local lvlPart = (compassEntry.level and compassEntry.level > 0) and (" |cff8b949e" .. compassEntry.level .. "|r") or ""
    f.compassBar.nameFs:SetText(string.format("%s[%s]|r %s%s|r%s", colHex, stanceTag, classHex, compassEntry.displayName or "?", lvlPart))

    local isActuallyTargeted = IsEntryCurrentlyTargeted(compassEntry, currentTargetGuid, parsedTarget)
    if isActuallyTargeted then
        Theme:ApplyBackdrop(f.compassBar, "primary", p)
    elseif f.compassBar.SetBackdrop then
        f.compassBar:SetBackdrop(nil)
    end

    self:UpdateCompassVisuals(true, 0.04)

    -- Show or hide the On-Click Interaction Drawer below the Arrow Pill
    if self.interactionOpen and (not self.interactionKey or self.interactionKey == compassEntry.key) then
        local guildAndLoc = compassEntry.guild and ("<" .. compassEntry.guild .. ">") or ""
        if compassEntry.locationText and compassEntry.locationText ~= "" then
            guildAndLoc = (guildAndLoc ~= "") and (guildAndLoc .. " · " .. compassEntry.locationText) or compassEntry.locationText
        end
        f.actionPanel.promptFs:SetText(guildAndLoc ~= "" and guildAndLoc or (compassEntry.displayName or "?"))
        if compassEntry.stance == "ENEMY" then
            if f.actionPanel.whisperBtn then f.actionPanel.whisperBtn:Hide() end
            if f.actionPanel.tellBtn then f.actionPanel.tellBtn:Hide() end
            if f.actionPanel.scoutBtn then
                f.actionPanel.scoutBtn:SetWidth(76)
                f.actionPanel.scoutBtn:ClearAllPoints()
                f.actionPanel.scoutBtn:SetPoint("BOTTOMLEFT", 5, 4)
                f.actionPanel.scoutBtn:Show()
                Theme:SetButtonText(f.actionPanel.scoutBtn, L["Scout Alert"])
            end
            Theme:SetButtonText(f.actionPanel.inviteBtn, L["Diplomacy"])
            f.actionPanel.inviteBtn:SetWidth(72)
            f.actionPanel.inviteBtn:ClearAllPoints()
            f.actionPanel.inviteBtn:SetPoint("LEFT", f.actionPanel.scoutBtn, "RIGHT", 3, 0)
            if f.actionPanel.watchBtn then
                f.actionPanel.watchBtn:SetWidth(72)
                f.actionPanel.watchBtn:ClearAllPoints()
                f.actionPanel.watchBtn:SetPoint("LEFT", f.actionPanel.inviteBtn, "RIGHT", 3, 0)
            end
        else
            if f.actionPanel.scoutBtn then f.actionPanel.scoutBtn:Hide() end
            if f.actionPanel.whisperBtn then
                f.actionPanel.whisperBtn:SetWidth(60)
                f.actionPanel.whisperBtn:Show()
                f.actionPanel.whisperBtn:ClearAllPoints()
                f.actionPanel.whisperBtn:SetPoint("BOTTOMLEFT", 5, 4)
            end
            if f.actionPanel.tellBtn then
                f.actionPanel.tellBtn:SetWidth(28)
                f.actionPanel.tellBtn:Show()
                f.actionPanel.tellBtn:ClearAllPoints()
                f.actionPanel.tellBtn:SetPoint("LEFT", f.actionPanel.whisperBtn, "RIGHT", 3, 0)
            end
            Theme:SetButtonText(f.actionPanel.inviteBtn, L["Invite"])
            f.actionPanel.inviteBtn:SetWidth(54)
            f.actionPanel.inviteBtn:ClearAllPoints()
            f.actionPanel.inviteBtn:SetPoint("LEFT", f.actionPanel.tellBtn, "RIGHT", 3, 0)
            if f.actionPanel.watchBtn then
                f.actionPanel.watchBtn:SetWidth(75)
                f.actionPanel.watchBtn:ClearAllPoints()
                f.actionPanel.watchBtn:SetPoint("LEFT", f.actionPanel.inviteBtn, "RIGHT", 3, 0)
            end
        end
        f.actionPanel:Show()
        f:SetHeight(PILL_H + 2 + ACTION_H + 3)
    else
        f.actionPanel:Hide()
        f:SetHeight(PILL_H)
    end
end

function SpotterHUD:CreatePromptDialog()
    if self.promptDialog then return self.promptDialog end

    local p = Theme:GetPalette()
    local dlg = CreateFrame("Frame", "SocialCentralSpotterPromptDialog", UIParent, "BackdropTemplate")
    dlg:SetSize(370, 154)
    dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    dlg:SetFrameStrata("DIALOG")
    dlg:SetFrameLevel(110)
    if dlg.SetClipsChildren then
        dlg:SetClipsChildren(false)
    end
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
    local tCount = GetSpotterTotalCount()
    if forceUser then
        self.userClosed = false
        if tCount == 0 then
            self.manualPinnedEmpty = true
        end
    end
    if not self.frame then
        self:BuildFrame()
    end
    if not self.frame then
        self.pendingAction = "show"
        self:ShowCombatArrowFallback()
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingAction = "show"
        self.pendingRefresh = true
        if not self.frame:IsShown() then
            self:ShowCombatArrowFallback()
        else
            self:UpdateTargetVisuals()
        end
        return
    end
    local s = ns.db and ns.db.settings
    if s and not s.spotterPromptAnswered then
        self:ShowFirstTimePrompt()
    end
    if tCount > 0 or self.manualPinnedEmpty then
        if self.combatArrowFrame then
            self.combatArrowFrame:Hide()
        end
        self.frame:Show()
    end
    self:Refresh()
    local totalAfter = GetSpotterTotalCount()
    if totalAfter > 0 or self.manualPinnedEmpty then
        self.frame:Show()
        self:UpdateCompassVisuals(true, 0.04)
    end
end

function SpotterHUD:Hide()
    if self.combatArrowFrame then
        self.combatArrowFrame:Hide()
    end
    if not self.frame then return end
    self.manualPinnedEmpty = false
    self.interactionOpen = false
    self.interactionKey = nil
    if InCombatLockdown and InCombatLockdown() then
        self.pendingAction = "hide"
        return
    end
    self.frame:Hide()
end

function SpotterHUD:Toggle()
    if (self.frame and self.frame:IsShown()) or (self.combatArrowFrame and self.combatArrowFrame:IsShown()) then
        local totalNow = GetSpotterTotalCount()
        if totalNow > 0 then
            self.userClosed = true
        end
        self.manualPinnedEmpty = false
        self:Hide()
    else
        self:Show(true)
    end
end

function SpotterHUD:OnAlert(alert)
    if not alert then return end
    self.focusedKey = alert.key

    local s = ns.db and ns.db.settings
    if s and not s.spotterPromptAnswered then
        self:ShowFirstTimePrompt()
    end

    if not s or s.spotterAutoShowHUD ~= false then
        self.userClosed = false
        if not self.frame or not self.frame:IsShown() then
            self:Show(false)
            return
        end
    end
    self:Refresh()
end

function SpotterHUD:TrackEntry(info, forcedStance)
    if not (ns.Spotter and ns.Spotter.TrackPlayer) then return nil end
    local name = (type(info) == "table" and (info.displayName or info.targetName or info.firstName)) or (type(info) == "string" and info)
    if not name or name == "" then return nil end
    local guild = type(info) == "table" and info.guild or nil
    local classFile = type(info) == "table" and info.classFile or nil
    local level = type(info) == "table" and info.level or nil
    local guid = type(info) == "table" and info.guid or nil
    local stanceArg = forcedStance
    if stanceArg ~= "ENEMY" and stanceArg ~= "ALLY" and stanceArg ~= "SAME" and stanceArg ~= "WATCHLIST" and stanceArg ~= "FRIEND" then
        stanceArg = nil
    end
    return ns.Spotter:TrackPlayer(name, guild, classFile, level, guid, stanceArg)
end

function SpotterHUD:Init()
    self:BuildFrame()
    self:BuildCombatArrowFrame()
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
        if SpotterHUD.combatArrowFrame then
            SpotterHUD.combatArrowFrame:Hide()
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
