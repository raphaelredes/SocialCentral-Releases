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
    _kinematicsElapsed = 0,
    _combatKinElapsed = 0,
}

local HUD_WIDTH = 312
local NAV_H = 21
local PILL_H = 44
local ACTION_H = 44
local MAX_NAV_NUMS = 7
local PAGE_SIZE = 5

local STANCE_RGB = {
    ENEMY     = { 0.96, 0.28, 0.28 },
    BLOCKED   = { 0.88, 0.22, 0.56 },
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

local function ResolveSpotterContactState(entry)
    if not entry then
        return false, nil, nil, false, false, nil
    end
    local targetName = (Compat.FormatForeverTarget and Compat.FormatForeverTarget(entry.displayName or entry.targetName))
        or entry.displayName or entry.targetName
    local lookupKey = entry.key or targetName
    local bInfo = (lookupKey and ns.Social and ns.Social.GetBNetLinkInfo) and ns.Social:GetBNetLinkInfo(lookupKey) or nil
    local bnetAccId = bInfo and bInfo.bnetAccountID or nil
    local bnetName = bInfo and bInfo.bnetName or nil
    local isCrossFac = (bInfo and bInfo.sameFaction == false) == true
    if (not isCrossFac) and entry.faction and entry.faction ~= "" then
        local ownFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
        if ownFac and entry.faction ~= ownFac then
            isCrossFac = true
        end
    end

    if (not isCrossFac) and ns.Spotter and ns.Spotter.FindLiveUnitForEntry then
        local liveUnit = ns.Spotter:FindLiveUnitForEntry(entry)
        if liveUnit then
            local myFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
            local uFac = UnitFactionGroup and Safe.String(Safe.Call(UnitFactionGroup, liveUnit)) or nil
            if uFac and myFac and uFac ~= myFac then
                isCrossFac = true
            elseif UnitIsEnemy and Safe.Value(Safe.Call(UnitIsEnemy, "player", liveUnit)) == true then
                isCrossFac = true
            elseif UnitIsFriend and Safe.Value(Safe.Call(UnitIsFriend, "player", liveUnit)) == false then
                isCrossFac = true
            end
        end
    end

    local isMe = Compat.IsMe and targetName and Compat.IsMe(targetName, entry.guid) or false
    local inGroup = Compat.IsInMyGroup and targetName and Compat.IsInMyGroup(targetName, entry.guid) or false
    local canInvite = (targetName ~= nil and targetName ~= "")
        and (entry.stance ~= "ENEMY")
        and (entry.stance ~= "BLOCKED")
        and (not isMe)
        and (not inGroup)
        and (not isCrossFac)
    return canInvite, targetName, bnetAccId, isCrossFac, inGroup, bnetName
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

    local canInvite, targetName, bnetAccId, isCrossFac, _, bnetName = ResolveSpotterContactState(entry)
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle(entry.displayName or "?")

        if entry.stance ~= "ENEMY" and entry.stance ~= "BLOCKED" and targetName then
            local chatModOn = (not Compat or not Compat.IsOfficialChatMode or not Compat.IsOfficialChatMode())
                and (not Compat or not Compat.IsModuleEnabled or Compat.IsModuleEnabled("chat"))
            local scConfirmed = chatModOn and ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(entry.key or targetName, bnetAccId)
            if scConfirmed then
                root:CreateButton(L["Whisper in SocialCentral"], function()
                    if ns.Chat and ns.Chat.OpenPreferredConversation then
                        ns.Chat:OpenPreferredConversation({
                            targetName = targetName,
                            lookupKey = entry.key or targetName,
                            bnetAccountID = bnetAccId,
                            bnetName = bnetName,
                            classFile = entry.classFile,
                            isCrossFaction = isCrossFac,
                            autoProbe = true,
                            scConfirmed = true,
                        })
                    elseif isCrossFac and bnetName and Compat.BNetWhisper then
                        Compat.BNetWhisper(bnetName, targetName)
                    elseif Compat.Whisper then
                        Compat.Whisper(targetName)
                    end
                end)
            end

            root:CreateButton((isCrossFac and bnetName) and L["Battle.net Whisper"] or L["Official Whisper"], function()
                if isCrossFac and bnetName and Compat.BNetWhisper then
                    Compat.BNetWhisper(bnetName, targetName)
                elseif Compat.Whisper then
                    Compat.Whisper(targetName)
                end
            end)

            if canInvite then
                root:CreateButton(L["Invite"], function()
                    if Compat.Invite then
                        Compat.Invite(targetName, bnetAccId)
                    end
                end)
            end
        end

        if ns.SocialPanels and ns.SocialPanels.PopulatePlayerQuickMenu then
            root:CreateDivider()
            ns.SocialPanels:PopulatePlayerQuickMenu(root, {
                displayName = entry.displayName,
                lookupKey = entry.key or entry.displayName,
                guild = entry.guild,
                watchlistNote = entry.guild or "",
                isCrossFaction = (entry.stance == "ENEMY"),
                samePool = (entry.stance ~= "ENEMY"),
                includeFavorite = (entry.stance ~= "ENEMY"),
                includeWatchlist = (entry.stance ~= "ENEMY"),
                includeCard = (entry.stance ~= "ENEMY"),
                includeFlags = true,
                includeIgnore = true,
                includeDiplomacy = false,
                onAfterAction = function()
                    SpotterHUD:Refresh()
                end,
            })
        else
            root:CreateButton(L["Add to Watchlist"], function()
                if ns.Watchlist and ns.Watchlist.Add then
                    ns.Watchlist:Add(entry.displayName, entry.guild or "")
                end
            end)
        end

        root:CreateDivider()
        if entry.guild and entry.guild ~= "" and entry.stance ~= "SAME" and ns.Clan then
            if ns.SocialPanels and ns.SocialPanels.AppendGuildDiplomacyMenu then
                ns.SocialPanels:AppendGuildDiplomacyMenu(root, entry.guild)
            else
                local canDip = ns.Clan.CanManageDiplomacy and ns.Clan:CanManageDiplomacy()
                if canDip then
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
                    root:CreateButton(L["Edit Diplomacy Entry"], function()
                        if ns.UI and ns.UI.OpenDiplomacyModal then
                            ns.UI:OpenDiplomacyModal(entry.guild, entry.stance, nil)
                        end
                    end)
                else
                    local authTxt = (ns.Clan.GetDiplomacyAuthoritySummary and ns.Clan:GetDiplomacyAuthoritySummary()) or L["Guild Leader Only"]
                    root:CreateTitle("|cff8b949e" .. L["Diplomacy"] .. ": " .. authTxt .. "|r")
                end
            end
        end

        root:CreateButton(L["Reset Position"], function()
            if Theme and Theme.ResetWindowPosition then
                Theme:ResetWindowPosition("spotter")
            end
        end)

        root:CreateButton(L["Dismiss Target"], function()
            if ns.Spotter then
                ns.Spotter:DismissTarget(entry.key)
            end
        end)
    end)
end

local function BuildTargetMacroText(entry, liveUnit)
    if not entry then return "" end

    -- 1. Fixed group / focus tokens never recycle; target directly when active.
    if type(liveUnit) == "string" and liveUnit ~= "" and liveUnit ~= "target" and liveUnit ~= "mouseover"
        and not liveUnit:find("[%c%|%/%\\%[%]%;%s]") then
        if liveUnit:match("^party%d+$") or liveUnit:match("^raid%d+$") or liveUnit == "focus" then
            return "/target [@" .. liveUnit .. ",exists]"
        end
    end

    local lines = {}
    local seen = {}
    local function addLine(cmd)
        if cmd and cmd ~= "" and not seen[cmd] then
            seen[cmd] = true
            table.insert(lines, cmd)
        end
    end

    -- Emit least specific targeting first so the last exact match always wins in WoW macros.
    local cleanDisplay = entry.displayName and entry.displayName:gsub("[%c%|%/%\\%[%]%;\r\n]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local firstName = entry.firstName or (cleanDisplay and cleanDisplay:match("^([^%s%-]+)"))
    local cleanFirst = firstName and firstName:gsub("[%c%|%/%\\%[%]%;\r\n]", ""):gsub("%s+", "")
    if cleanFirst and cleanFirst ~= "" then
        addLine("/target " .. cleanFirst)
        addLine("/targetexact " .. cleanFirst)
    end

    if type(liveUnit) == "string" and liveUnit ~= "" and liveUnit ~= "target" and liveUnit ~= "mouseover"
        and not liveUnit:find("[%c%|%/%\\%[%]%;%s]") then
        addLine("/target [@" .. liveUnit .. ",exists]")
    end

    local cleanRaw = (entry.unitName and type(entry.unitName) == "string")
        and entry.unitName:gsub("[%c%|%/%\\%[%]%;\r\n]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        or nil
    local candidates = Compat.GetForeverTargetVariants and Compat.GetForeverTargetVariants(cleanDisplay or entry.firstName) or {}
    for _, cand in ipairs(candidates) do
        local c = cand:gsub("[%c%|%/%\\%[%]%;\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if c ~= "" and c ~= cleanRaw then
            addLine("/targetexact " .. c)
        end
    end

    if cleanRaw and cleanRaw ~= "" then
        addLine("/targetexact " .. cleanRaw)
    end

    return table.concat(lines, "\n")
end

local function ApplySecureMacroAttributes(btn, entry, liveUnit)
    if not btn then return end
    if InCombatLockdown and InCombatLockdown() then
        SpotterHUD.pendingRefresh = true
        return
    end
    if not entry then
        if btn._lastMacroCleared then
            return
        end
        btn:SetAttribute("useOnKeyDown", false)
        btn:SetAttribute("type2", nil)
        btn:SetAttribute("*type2", nil)
        btn:SetAttribute("macrotext2", nil)
        btn:SetAttribute("*macrotext2", nil)
        btn:SetAttribute("type", nil)
        btn:SetAttribute("type1", nil)
        btn:SetAttribute("*type1", nil)
        btn:SetAttribute("unit", nil)
        btn:SetAttribute("macrotext", nil)
        btn:SetAttribute("macrotext1", nil)
        btn:SetAttribute("*macrotext1", nil)
        btn._lastMacroText = nil
        btn._lastMacroSig = nil
        btn._lastMacroCleared = true
        return
    end

    local entryTable = (type(entry) == "table") and entry or nil
    local mText = entryTable and BuildTargetMacroText(entryTable, liveUnit) or tostring(entry)
    if btn._lastMacroCleared == false and btn._lastMacroText == mText then
        return
    end
    btn:SetAttribute("useOnKeyDown", false)
    btn:SetAttribute("type2", nil)
    btn:SetAttribute("*type2", nil)
    btn:SetAttribute("macrotext2", nil)
    btn:SetAttribute("*macrotext2", nil)
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("type1", "macro")
    btn:SetAttribute("*type1", "macro")
    btn:SetAttribute("unit", nil)
    btn:SetAttribute("macrotext", mText)
    btn:SetAttribute("macrotext1", mText)
    btn:SetAttribute("*macrotext1", mText)
    btn._lastMacroText = mText
    btn._lastMacroCleared = false
end

local function IsEntryCurrentlyTargeted(entry, currentTargetGuid, tLookupKey, tFirstName, tSurname)
    if not entry then return false end
    if currentTargetGuid and entry.guid then
        return currentTargetGuid == entry.guid
    end
    if tLookupKey then
        if tLookupKey == entry.key then
            return true
        end
        local entryHasSurname = type(entry.displayName) == "string" and entry.displayName:find("%s") ~= nil
        if (not tSurname or not entryHasSurname)
            and entry.firstName and tFirstName
            and tFirstName:lower() == entry.firstName:lower() then
            return true
        end
    end
    return false
end

local function ReadCurrentTargetIdentity()
    local tGuid = Safe.String(Safe.Call(UnitGUID, "target"))
    local tName = Safe.String(Safe.Call(UnitName, "target"))
    local tLookupKey, tFirstName, _, tSurname
    if tName then
        if Compat.ParseCharacterFields then
            tLookupKey, tFirstName, _, tSurname = Compat.ParseCharacterFields(tName)
        elseif Compat.ParseCharacterName then
            local p = Compat.ParseCharacterName(tName)
            if p then
                tLookupKey, tFirstName, tSurname = p.lookupKey, p.firstName, p.surname
            end
        end
    end
    return tGuid, tLookupKey, tFirstName, tSurname
end

local function HandleTargetClick(entry)
    if not entry then return end
    entry.toastShownAt = time()
    entry.lastSeen = entry.toastShownAt
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

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local PORTRAIT_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local CLASS_SPRITE_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local RADAR_FALLBACK_ICON = "Interface\\AddOns\\SocialCentral\\Media\\icon"

local function ApplyCircleMask(parent, tex, size)
    if not (parent and parent.CreateMaskTexture and tex) then return end
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(size, size)
    mask:SetPoint("CENTER", tex, "CENTER", 0, 0)
    tex:AddMaskTexture(mask)
end

local function CreateTargetCrestBox(parentFrame, leftOffset)
    local badgeBox = CreateFrame("Frame", nil, parentFrame)
    badgeBox:SetSize(26, 26)
    badgeBox:SetPoint("LEFT", leftOffset or 8, 0)
    badgeBox:EnableMouse(false)

    local outerRing = badgeBox:CreateTexture(nil, "ARTWORK", nil, 0)
    outerRing:SetSize(26, 26)
    outerRing:SetPoint("CENTER")
    outerRing:SetTexture(WHITE8X8)
    outerRing:SetVertexColor(0.98, 0.80, 0.24, 0.90)
    ApplyCircleMask(badgeBox, outerRing, 26)
    badgeBox.outerRing = outerRing

    local aura = badgeBox:CreateTexture(nil, "ARTWORK", nil, 1)
    aura:SetSize(24, 24)
    aura:SetPoint("CENTER")
    aura:SetTexture(WHITE8X8)
    aura:SetVertexColor(0.06, 0.08, 0.12, 1.0)
    ApplyCircleMask(badgeBox, aura, 24)
    badgeBox.aura = aura

    local crestTex = badgeBox:CreateTexture(nil, "OVERLAY", nil, 2)
    crestTex:SetSize(22, 22)
    crestTex:SetPoint("CENTER")
    crestTex:SetTexture(RADAR_FALLBACK_ICON)
    crestTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ApplyCircleMask(badgeBox, crestTex, 22)
    badgeBox.crestTex = crestTex

    parentFrame.arrowBox = badgeBox
    parentFrame.crestTex = crestTex
    return badgeBox
end

local function ApplySpotterFocusEntry(entry, idx)
    if not entry then return end
    entry.toastShownAt = time()
    entry.lastSeen = entry.toastShownAt
    SpotterHUD.cycleIndex = idx
    SpotterHUD.focusedKey = entry.key
    if SpotterHUD.interactionOpen then
        SpotterHUD.interactionKey = entry.key
    end
    SpotterHUD:Refresh()
    if ns.Spotter and ns.Spotter.UpdateFocusedPlateMarker then
        ns.Spotter:UpdateFocusedPlateMarker()
    end
end

local function CycleRadarTarget(delta)
    if InCombatLockdown and InCombatLockdown() then return end
    local all = ns.Spotter and ns.Spotter:GetActiveTargets("ALL") or {}
    if #all > 1 then
        local cur = SpotterHUD.cycleIndex or 1
        local nextIdx = ((cur - 1 + (delta or 1)) % #all) + 1
        ApplySpotterFocusEntry(all[nextIdx], nextIdx)
    end
end

local function SelectRadarTargetIndex(targetIdx)
    if InCombatLockdown and InCombatLockdown() then return end
    local all = ns.Spotter and ns.Spotter:GetActiveTargets("ALL") or {}
    local idx = tonumber(targetIdx)
    if not idx or idx < 1 or idx > #all then return end
    ApplySpotterFocusEntry(all[idx], idx)
end

local function CycleRadarPage(pageDelta)
    if InCombatLockdown and InCombatLockdown() then return end
    local all = ns.Spotter and ns.Spotter:GetActiveTargets("ALL") or {}
    local total = #all
    if total <= MAX_NAV_NUMS then
        CycleRadarTarget(pageDelta)
        return
    end
    local totalPages = math.ceil(total / PAGE_SIZE)
    local cur = SpotterHUD.cycleIndex or 1
    local curPage = math.floor((cur - 1) / PAGE_SIZE) + 1
    local nextPage = ((curPage - 1 + (pageDelta or 1)) % totalPages) + 1
    local nextIdx = (nextPage - 1) * PAGE_SIZE + 1
    if nextIdx > total then nextIdx = total end
    ApplySpotterFocusEntry(all[nextIdx], nextIdx)
end

local function ApplySpotterFrameLayout(f, showNav, actionOpen)
    if not f then return end
    local isNav = (showNav == true)
    local isAction = (actionOpen == true)
    local topOffset = isNav and (NAV_H + 1) or 0
    local wantH = topOffset + PILL_H + (isAction and (2 + ACTION_H + 3) or 0)

    local changed = (f._lastLayoutNav ~= isNav)
        or (f._lastActionOpen ~= isAction)
        or (f._lastFrameH ~= wantH)
    if not changed then
        return
    end

    f._lastLayoutNav = isNav
    f._lastActionOpen = isAction
    f._lastFrameH = wantH

    if f.navBar then
        if isNav then
            f.navBar:Show()
        else
            f.navBar:Hide()
        end
    end

    if f.selWash then
        f.selWash:ClearAllPoints()
        f.selWash:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -(3 + topOffset))
        f.selWash:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -(3 + topOffset))
    end

    if f.compassBar then
        f.compassBar:ClearAllPoints()
        f.compassBar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -(3 + topOffset))
        -- Reserve space for [?][X] only when navBar is hidden and compassBar shares the top row.
        f.compassBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", isNav and -6 or -48, -(3 + topOffset))
        if f.compassBar.nameFs and f.compassBar.arrowBox then
            f.compassBar.nameFs:ClearAllPoints()
            f.compassBar.nameFs:SetPoint("TOPLEFT", f.compassBar.arrowBox, "TOPRIGHT", 8, 1)
            f.compassBar.nameFs:SetPoint("TOPRIGHT", f.compassBar, "TOPRIGHT", -4, 1)
        end
    end

    if f.actionPanel then
        f.actionPanel:ClearAllPoints()
        f.actionPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -(topOffset + PILL_H - 1))
        f.actionPanel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -(topOffset + PILL_H - 1))
        if isAction then
            f.actionPanel:Show()
        else
            f.actionPanel:Hide()
        end
    end

    f:SetHeight(wantH)
    if ns.NotificationToast and ns.NotificationToast.LayoutStack then
        ns.NotificationToast:LayoutStack()
    end
end

local function ApplyNavBarTheme(navBar, p)
    if not navBar or not p then return end
    if navBar.bg then
        local bg = p.surfaceBg or p.windowBg or { 0.08, 0.09, 0.12 }
        navBar.bg:SetColorTexture(bg[1], bg[2], bg[3], 0.72)
    end
    if navBar.div then
        local bd = p.surfaceBorder or p.windowBorder or { 0.35, 0.30, 0.22 }
        navBar.div:SetColorTexture(bd[1], bd[2], bd[3], 0.45)
    end
    if navBar.countFs then
        local muted = p.textMuted or { 0.65, 0.70, 0.78 }
        navBar.countFs:SetTextColor(muted[1], muted[2], muted[3])
    end
    if navBar.prevPageBtn then Theme:StyleButton(navBar.prevPageBtn, "default") end
    if navBar.prevBtn then Theme:StyleButton(navBar.prevBtn, "default") end
    if navBar.nextBtn then Theme:StyleButton(navBar.nextBtn, "default") end
    if navBar.nextPageBtn then Theme:StyleButton(navBar.nextPageBtn, "default") end
    if navBar.numBtns then
        for _, btn in ipairs(navBar.numBtns) do
            Theme:StyleButton(btn, btn._isActive and "primary" or "default")
            Theme:SetButtonActive(btn, btn._isActive == true, btn._isActive and "primary" or "default")
        end
    end
    navBar._dirtyTheme = nil
end

local function BuildSpotterNavBar(f)
    local navBar = CreateFrame("Frame", nil, f)
    navBar:SetHeight(NAV_H)
    navBar:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -3)
    navBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -46, -3)
    navBar:SetFrameLevel(math.max((f:GetFrameLevel() or 40) + 10, 50))
    if navBar.SetClipsChildren then
        navBar:SetClipsChildren(true)
    end

    local bg = navBar:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAllPoints()
    navBar.bg = bg

    local div = navBar:CreateTexture(nil, "BORDER", nil, 1)
    div:SetHeight(1)
    div:SetPoint("BOTTOMLEFT", navBar, "BOTTOMLEFT", 0, 0)
    div:SetPoint("BOTTOMRIGHT", navBar, "BOTTOMRIGHT", 0, 0)
    navBar.div = div

    navBar:EnableMouse(true)
    navBar:EnableMouseWheel(true)
    navBar:SetScript("OnMouseWheel", function(_, delta)
        CycleRadarTarget(delta > 0 and -1 or 1)
    end)
    navBar:SetScript("OnEnter", function(selfBar)
        if selfBar._totalCount and selfBar._totalCount > 1 then
            ShowHUDTooltip(
                selfBar,
                string.format(L["Target %d of %d"], selfBar._activeIdx or 1, selfBar._totalCount),
                nil,
                L["Left-click: Target player  |  Right-click: Actions  |  Wheel: Cycle"]
            )
        end
    end)
    navBar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local function makeNavArrowBtn(w, text, tipText, onClickFn)
        local b = Theme:CreateButton(navBar, w, 17, text, "default")
        b:RegisterForClicks("AnyUp")
        b:SetScript("OnClick", onClickFn)
        b:SetScript("OnEnter", function(selfBtn)
            ShowHUDTooltip(selfBtn, tipText)
        end)
        b:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        return b
    end

    navBar.prevPageBtn = makeNavArrowBtn(22, "<<", L["Previous targets page"], function()
        CycleRadarPage(-1)
    end)
    navBar.prevBtn = makeNavArrowBtn(20, "<", L["Previous target"], function()
        CycleRadarTarget(-1)
    end)

    local numBtns = {}
    for i = 1, MAX_NAV_NUMS do
        local b = Theme:CreateButton(navBar, 23, 17, tostring(i), "default")
        b:RegisterForClicks("AnyUp")
        local pip = b:CreateTexture(nil, "OVERLAY", nil, 4)
        pip:SetHeight(2)
        pip:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 1)
        pip:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 1)
        pip:SetColorTexture(0.98, 0.80, 0.24, 0.95)
        b._stancePip = pip
        b:SetScript("OnClick", function(selfBtn)
            if selfBtn._targetIdx then
                SelectRadarTargetIndex(selfBtn._targetIdx)
            end
        end)
        b:SetScript("OnEnter", function(selfBtn)
            local idx = selfBtn._targetIdx
            if not idx then return end
            local disp = selfBtn._entryName or "?"
            local title = string.format("#%d · %s", idx, disp)
            if selfBtn._entryLevel and selfBtn._entryLevel > 0 then
                title = title .. string.format(" (%d)", selfBtn._entryLevel)
            end
            local l1 = (selfBtn._entryGuild and selfBtn._entryGuild ~= "") and ("<" .. selfBtn._entryGuild .. ">") or ""
            if selfBtn._entryLoc and selfBtn._entryLoc ~= "" then
                l1 = (l1 ~= "") and (l1 .. " · " .. selfBtn._entryLoc) or selfBtn._entryLoc
            end
            ShowHUDTooltip(selfBtn, title, l1, string.format(L["Click to focus target #%d"], idx))
        end)
        b:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        b:Hide()
        numBtns[i] = b
    end
    navBar.numBtns = numBtns

    navBar.nextBtn = makeNavArrowBtn(20, ">", L["Next target"], function()
        CycleRadarTarget(1)
    end)
    navBar.nextPageBtn = makeNavArrowBtn(22, ">>", L["Next targets page"], function()
        CycleRadarPage(1)
    end)

    local countFs = navBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countFs:SetPoint("RIGHT", navBar, "RIGHT", -4, 0)
    countFs:SetJustifyH("RIGHT")
    navBar.countFs = countFs

    navBar:Hide()
    return navBar
end

local function UpdateSpotterNavBar(f, allTargets, activeIdx, totalCount, p)
    local navBar = f and f.navBar
    if not navBar or not totalCount or totalCount <= 1 then
        if navBar then
            navBar._activeIdx = nil
            navBar._totalCount = nil
        end
        return false
    end

    local idx = math.max(1, math.min(activeIdx or 1, totalCount))
    navBar._activeIdx = idx
    navBar._totalCount = totalCount

    if navBar._lastCountActive ~= idx or navBar._lastCountTotal ~= totalCount then
        navBar._lastCountActive = idx
        navBar._lastCountTotal = totalCount
        navBar.countFs:SetText(string.format("%d/%d", idx, totalCount))
    end

    local paged = (totalCount > MAX_NAV_NUMS)
    local curPage = paged and (math.floor((idx - 1) / PAGE_SIZE) + 1) or 1
    local startIdx = paged and ((curPage - 1) * PAGE_SIZE + 1) or 1
    local maxSlots = paged and PAGE_SIZE or MAX_NAV_NUMS
    local visibleCount = math.min(maxSlots, totalCount - startIdx + 1)
    if visibleCount < 1 then visibleCount = 1 end

    local prevAnchor
    local layoutDirty = (navBar._lastPaged ~= paged) or (navBar._lastVisCount ~= visibleCount)
    if layoutDirty then
        navBar._lastPaged = paged
        navBar._lastVisCount = visibleCount

        navBar.prevPageBtn:ClearAllPoints()
        if paged then
            navBar.prevPageBtn:SetPoint("LEFT", navBar, "LEFT", 3, 1)
            navBar.prevPageBtn:Show()
            prevAnchor = navBar.prevPageBtn
        else
            navBar.prevPageBtn:Hide()
        end

        navBar.prevBtn:ClearAllPoints()
        if prevAnchor then
            navBar.prevBtn:SetPoint("LEFT", prevAnchor, "RIGHT", 2, 0)
        else
            navBar.prevBtn:SetPoint("LEFT", navBar, "LEFT", 3, 1)
        end
        prevAnchor = navBar.prevBtn
    else
        prevAnchor = navBar.prevBtn
    end

    for i = 1, MAX_NAV_NUMS do
        local btn = navBar.numBtns[i]
        if i <= visibleCount then
            local tIdx = startIdx + i - 1
            local cand = allTargets and allTargets[tIdx] or nil
            local wantW = (tIdx >= 100) and 25 or 23
            local isActive = (tIdx == idx)
            local stance = (cand and cand.stance) or "SAME"

            if layoutDirty or btn._lastLeftAnchor ~= prevAnchor then
                btn._lastLeftAnchor = prevAnchor
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", prevAnchor, "RIGHT", 2, 0)
            end
            if btn._lastWidth ~= wantW then
                btn._lastWidth = wantW
                btn:SetWidth(wantW)
            end
            if btn._targetIdx ~= tIdx then
                btn._targetIdx = tIdx
                Theme:SetButtonText(btn, tostring(tIdx))
            end
            if btn._isActive ~= isActive or btn._activePalKey ~= (p and p.key or "dark") then
                btn._isActive = isActive
                btn._activePalKey = p and p.key or "dark"
                Theme:StyleButton(btn, isActive and "primary" or "default")
                Theme:SetButtonActive(btn, isActive, isActive and "primary" or "default")
            end
            if btn._stance ~= stance or btn._pipActive ~= isActive then
                btn._stance = stance
                btn._pipActive = isActive
                local sRgb = STANCE_RGB[stance] or STANCE_RGB.SAME
                btn._stancePip:SetColorTexture(sRgb[1], sRgb[2], sRgb[3], isActive and 1.0 or 0.72)
            end
            btn._entryName = cand and cand.displayName or "?"
            btn._entryLevel = cand and cand.level or 0
            btn._entryGuild = cand and cand.guild or nil
            btn._entryLoc = cand and (cand.fullLocationText or cand.locationText) or nil
            if not btn:IsShown() then
                btn:Show()
            end
            prevAnchor = btn
        else
            btn._targetIdx = nil
            btn._entryName = nil
            btn._entryLevel = nil
            btn._entryGuild = nil
            btn._entryLoc = nil
            if btn:IsShown() then
                btn:Hide()
            end
        end
    end

    if layoutDirty or navBar._lastNextAnchor ~= prevAnchor then
        navBar._lastNextAnchor = prevAnchor
        navBar.nextBtn:ClearAllPoints()
        navBar.nextBtn:SetPoint("LEFT", prevAnchor, "RIGHT", 2, 0)

        navBar.nextPageBtn:ClearAllPoints()
        if paged then
            navBar.nextPageBtn:SetPoint("LEFT", navBar.nextBtn, "RIGHT", 2, 0)
            navBar.nextPageBtn:Show()
        else
            navBar.nextPageBtn:Hide()
        end
    end

    return true
end

function SpotterHUD:BuildFrame()
    if self.frame then return self.frame end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingRefresh = true
        return nil
    end

    local f = CreateFrame("Frame", "SocialCentralSpotterFrame", UIParent, "BackdropTemplate")
    f:SetSize(HUD_WIDTH, PILL_H)
    f:SetPoint("TOP", UIParent, "TOP", 0, -64)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(40)
    if f.SetClipsChildren then
        f:SetClipsChildren(true)
    end
    f:EnableMouse(true)

    local stanceBar = f:CreateTexture(nil, "OVERLAY", nil, 3)
    stanceBar:SetWidth(3)
    stanceBar:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
    stanceBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 3, 3)
    stanceBar:SetColorTexture(0.98, 0.80, 0.24, 1)
    f.stanceBar = stanceBar

    -- Full-width subtle top-row selection wash (replaces half-width crimson box)
    local selWash = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    selWash:SetHeight(PILL_H - 6)
    selWash:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -3)
    selWash:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    selWash:SetColorTexture(0.98, 0.80, 0.24, 0.14)
    selWash:Hide()
    f.selWash = selWash

    local topBevel = f:CreateTexture(nil, "BORDER", nil, 1)
    topBevel:SetHeight(1)
    topBevel:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -3)
    topBevel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -3)
    topBevel:SetColorTexture(1, 0.90, 0.65, 0.16)
    f._topBevel = topBevel

    local navBar = BuildSpotterNavBar(f)
    f.navBar = navBar

    -- Main clickable Pill (SecureActionButtonTemplate: selects target on screen & opens Interaction Drawer)
    local compassBar = CreateFrame("Button", "SocialCentralSpotterCompass", f, "SecureActionButtonTemplate,BackdropTemplate")
    compassBar:SetHeight(PILL_H - 6)
    compassBar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -3)
    compassBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -48, -3)
    if compassBar.SetClipsChildren then
        compassBar:SetClipsChildren(true)
    end
    compassBar:RegisterForClicks("AnyUp")
    compassBar:RegisterForDrag("LeftButton")
    ApplySecureMacroAttributes(compassBar, nil)

    local compassGlow = compassBar:CreateTexture(nil, "HIGHLIGHT")
    compassGlow:SetAllPoints()
    compassGlow:SetColorTexture(1, 1, 1, 0.06)

    local arrowBox = CreateTargetCrestBox(compassBar, 6)

    local compassNameFs = compassBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    compassNameFs:SetPoint("TOPLEFT", arrowBox, "TOPRIGHT", 8, 1)
    compassNameFs:SetPoint("TOPRIGHT", compassBar, "TOPRIGHT", -4, 1)
    compassNameFs:SetJustifyH("LEFT")
    compassNameFs:SetWordWrap(false)
    compassBar.nameFs = compassNameFs

    local compassDistFs = compassBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    compassDistFs:SetPoint("BOTTOMLEFT", arrowBox, "BOTTOMRIGHT", 8, -1)
    compassDistFs:SetPoint("BOTTOMRIGHT", compassBar, "BOTTOMRIGHT", -6, -1)
    compassDistFs:SetJustifyH("LEFT")
    compassDistFs:SetWordWrap(false)
    compassBar.distFs = compassDistFs

    local compassSubFs = compassBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    compassSubFs:Hide()
    compassBar.subFs = compassSubFs

    compassBar:EnableMouseWheel(true)
    compassBar:SetScript("OnMouseWheel", function(_, delta)
        CycleRadarTarget(delta > 0 and -1 or 1)
    end)

    compassBar:SetScript("PostClick", function(selfBtn, mouseBtn, down)
        if down or f._scDragging then return end
        if f._scJustDraggedAt and GetTime and (GetTime() - f._scJustDraggedAt) < 0.25 then return end
        if selfBtn.entry then
            HandleTargetClick(selfBtn.entry)
            if mouseBtn == "RightButton" then
                OpenTargetContextMenu(selfBtn, selfBtn.entry)
            end
        end
    end)
    compassBar:HookScript("OnMouseDown", function(_, mouseBtn)
        if mouseBtn == "LeftButton" and f._scPrepareDrag then
            f._scPrepareDrag()
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
                l1 = (l1 ~= "") and (l1 .. " · " .. locTxt) or locTxt
            end
            ShowHUDTooltip(
                selfBtn,
                e.displayName or "?",
                l1,
                L["Left-click: Target player  |  Right-click: Actions  |  Wheel: Cycle"]
            )
        end
    end)
    compassBar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.compassBar = compassBar

    -- Top-right [X] button kept strictly above compassBar and navBar
    local closeBtn = Theme:CreateButton(f, 20, 20, "X", "danger")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetFrameLevel(math.max((f:GetFrameLevel() or 40) + 50, compassBar:GetFrameLevel() + 50, navBar:GetFrameLevel() + 50))
    closeBtn:SetHitRectInsets(-4, -4, -4, -4)
    closeBtn:RegisterForClicks("AnyUp")
    closeBtn:SetScript("OnClick", function()
        SpotterHUD.userClosed = true
        SpotterHUD.manualPinnedEmpty = false
        SpotterHUD.interactionOpen = false
        SpotterHUD.interactionKey = nil
        SpotterHUD:Hide()
    end)
    f.closeBtn = closeBtn

    if Theme and Theme.CreateHelpButton then
        local helpBtn = Theme:CreateHelpButton(
            f,
            L["Target Radar & Proximity Tracking"],
            L["The Target Radar tracks nearby Watchlist, Friend, Ally, Same-Clan, and Enemy players via sightlines and nameplates, and lets you quickly flag Avoid, Account Ignore, Watchlist, Favorites, or Guild Diplomacy."],
            L["Left-click the Radar HUD outside combat to target/open quick actions (+ Avoid, Manage Block, Watchlist, Diplomacy), or right-click any spotted target for full Social & Diplomacy options."],
            19,
            { target = f }
        )
        helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
        helpBtn:SetFrameLevel(closeBtn:GetFrameLevel())
        helpBtn:SetScript("OnClick", function()
            if GameTooltip then GameTooltip:Hide() end
            SpotterHUD:ShowRadarTutorial(true)
        end)
        f.helpBtn = helpBtn
    end

    -- Expandable On-Click Interaction Drawer anchored cleanly across FULL frame width (zero right seam/clipping!)
    local actionPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    actionPanel:SetHeight(ACTION_H)
    actionPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -(PILL_H - 1))
    actionPanel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -(PILL_H - 1))
    if actionPanel.SetClipsChildren then
        actionPanel:SetClipsChildren(true)
    end
    local drawerSep = actionPanel:CreateTexture(nil, "ARTWORK", nil, 1)
    drawerSep:SetHeight(1)
    drawerSep:SetPoint("TOPLEFT", actionPanel, "TOPLEFT", 6, 0)
    drawerSep:SetPoint("TOPRIGHT", actionPanel, "TOPRIGHT", -6, 0)
    drawerSep:SetColorTexture(0.68, 0.56, 0.28, 0.35)
    f.drawerSep = drawerSep

    local promptFs = actionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    promptFs:SetPoint("TOPLEFT", 8, -4)
    promptFs:SetPoint("TOPRIGHT", -8, -4)
    promptFs:SetJustifyH("LEFT")
    promptFs:SetWordWrap(false)
    actionPanel.promptFs = promptFs

    local btnW = 92
    local whisperBtn = Theme:CreateButton(actionPanel, btnW, 20, L["Whisper"], "primary")
    whisperBtn:SetPoint("BOTTOMLEFT", 6, 4)
    whisperBtn:SetScript("OnClick", function()
        local e = SpotterHUD._compassEntry
        if not e then return end
        local _, targetName, bnetAccId, isCrossFac, _, bnetName = ResolveSpotterContactState(e)
        local dest = targetName or e.displayName or e.targetName
        local addonAllowed = (not Compat or not Compat.IsOfficialChatMode or not Compat.IsOfficialChatMode())
            and (not Compat or not Compat.IsModuleEnabled or Compat.IsModuleEnabled("chat"))
        local hasAddon = addonAllowed and ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(e.key or dest, bnetAccId)
        if hasAddon and ns.Chat and ns.Chat.OpenPreferredConversation then
            ns.Chat:OpenPreferredConversation({
                targetName = dest,
                lookupKey = e.key or dest,
                bnetAccountID = bnetAccId,
                bnetName = bnetName,
                classFile = e.classFile,
                isCrossFaction = isCrossFac,
                autoProbe = true,
                scConfirmed = true,
            })
        elseif isCrossFac and bnetName and Compat.BNetWhisper then
            Compat.BNetWhisper(bnetName, dest)
        elseif Compat.Whisper then
            Compat.Whisper(dest)
        end
        SpotterHUD.interactionOpen = false
        SpotterHUD:Refresh()
    end)
    actionPanel.whisperBtn = whisperBtn

    local scoutBtn = Theme:CreateButton(actionPanel, btnW, 20, L["Scout Alert"], "danger")
    scoutBtn:SetPoint("BOTTOMLEFT", 6, 4)
    scoutBtn:SetScript("OnClick", function()
        local e = SpotterHUD._compassEntry
        if not e then return end
        local coordsStr = ""
        if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
            local mapId = Safe and Safe.Number(Safe.Call(C_Map.GetBestMapForUnit, "player")) or C_Map.GetBestMapForUnit("player")
            if mapId then
                local pos = C_Map.GetPlayerMapPosition(mapId, "player")
                if pos and pos.GetXY then
                    local px, py = pos:GetXY()
                    if px and py and (px > 0 or py > 0) then
                        coordsStr = string.format("%d, %d", math.floor(px * 100 + 0.5), math.floor(py * 100 + 0.5))
                    end
                end
            end
        end
        if ns.Clan and ns.Clan.BroadcastScoutAlert then
            ns.Clan:BroadcastScoutAlert(e.displayName, e.guild or "", e.level or 0, e.classFile, e.zone or e.subZone or "", coordsStr)
        end
        SpotterHUD.interactionOpen = false
        SpotterHUD:Refresh()
    end)
    scoutBtn:Hide()
    actionPanel.scoutBtn = scoutBtn

    local inviteBtn = Theme:CreateButton(actionPanel, btnW, 20, L["Invite"], "default")
    inviteBtn:SetPoint("LEFT", whisperBtn, "RIGHT", 6, 0)
    inviteBtn:SetScript("OnClick", function()
        local e = SpotterHUD._compassEntry
        if not e then return end
        if e.stance == "ENEMY" then
            if ns.Clan and ns.Clan.CanManageDiplomacy and not ns.Clan:CanManageDiplomacy() then
                local authTxt = (ns.Clan.GetDiplomacyAuthoritySummary and ns.Clan:GetDiplomacyAuthoritySummary()) or L["Guild Leader Only"]
                ns:Print(L["Only guild leaders (%s) can define Allied or Enemy guilds."]:format(authTxt))
            elseif ns.UI and ns.UI.OpenDiplomacyModal then
                ns.UI:OpenDiplomacyModal(e.guild, e.stance, nil)
            end
        elseif e.stance == "BLOCKED" then
            if ns.Spotter and ns.Spotter.DismissTarget then
                ns.Spotter:DismissTarget(e.key)
            end
        else
            local canInvite, targetName, bnetAccId = ResolveSpotterContactState(e)
            if canInvite and Compat.Invite then
                Compat.Invite(targetName or e.displayName or e.targetName, bnetAccId)
            end
        end
        SpotterHUD.interactionOpen = false
        SpotterHUD:Refresh()
    end)
    actionPanel.inviteBtn = inviteBtn

    local watchBtn = Theme:CreateButton(actionPanel, btnW + 2, 20, "+ " .. L["Watchlist"], "default")
    watchBtn:SetPoint("LEFT", inviteBtn, "RIGHT", 6, 0)
    watchBtn:SetScript("OnClick", function()
        local e = SpotterHUD._compassEntry
        if not e then return end
        local key = e.key or e.displayName
        if e.stance == "BLOCKED" then
            if Store and Store.IsAccountIgnored and Store:IsAccountIgnored(key) and ns.SocialPanels and ns.SocialPanels.OpenAccountIgnoreModal then
                ns.SocialPanels:OpenAccountIgnoreModal(e.displayName, key)
            elseif ns.SocialPanels and ns.SocialPanels.ConfirmToggleOrRemoveAvoid then
                ns.SocialPanels:ConfirmToggleOrRemoveAvoid(key, e.displayName)
            elseif Store and Store.SetSocialFlag then
                Store:SetSocialFlag(key, "AVOID")
            end
        elseif e.stance == "ENEMY" then
            if ns.SocialPanels and ns.SocialPanels.ConfirmToggleOrRemoveAvoid then
                ns.SocialPanels:ConfirmToggleOrRemoveAvoid(key, e.displayName)
            elseif Store and Store.SetSocialFlag then
                Store:SetSocialFlag(key, "AVOID")
            end
        elseif ns.Watchlist then
            if key and ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(key) then
                if ns.UI and ns.UI.OpenConfirmModal then
                    ns.UI:OpenConfirmModal({
                        title = L["Remove from Watchlist"],
                        message = L["Are you sure you want to remove %s from your Watchlist?"]:format(e.displayName or key or "?"),
                        confirmText = L["Remove"],
                        onConfirm = function()
                            if ns.Watchlist then ns.Watchlist:Remove(key) end
                            SpotterHUD:Refresh()
                        end,
                    })
                else
                    ns.Watchlist:Remove(key)
                end
            elseif ns.Watchlist.Add then
                ns.Watchlist:Add(e.displayName, e.guild or "")
            end
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
        locked = function()
            return ns.db and ns.db.settings and ns.db.settings.spotterLockHUD == true
        end,
        handles = { f, navBar, actionPanel },
        onStop = function()
            if ns.NotificationToast and ns.NotificationToast.LayoutStack then
                ns.NotificationToast:LayoutStack()
            end
        end,
        onReset = function(win)
            win:ClearAllPoints()
            win:SetPoint("TOP", UIParent, "TOP", 0, -64)
            if ns.NotificationToast and ns.NotificationToast.LayoutStack then
                ns.NotificationToast:LayoutStack()
            end
        end,
    })

    f:HookScript("OnHide", function()
        SpotterHUD:SyncTickerState(nil)
        if ns.NotificationToast and ns.NotificationToast.LayoutStack then
            ns.NotificationToast:LayoutStack()
        end
    end)

    self.frame = f
    self:BuildCombatArrowFrame()
    self:UpdateAppearance()
    f:Hide()
    return f
end

function SpotterHUD:SyncTickerState(kin)
    local isSelected = (kin ~= nil and kin.isSelected == true)
    self._tickerInterval = (kin and kin.stationary) and 0.75 or 0.25

    if not self._mainOnUpdateFn then
        self._mainOnUpdateFn = function(_, elapsed)
            local stepInterval = SpotterHUD._tickerInterval or 0.25
            SpotterHUD._kinematicsElapsed = (SpotterHUD._kinematicsElapsed or 0) + elapsed
            if SpotterHUD._kinematicsElapsed >= stepInterval then
                local dt = SpotterHUD._kinematicsElapsed
                SpotterHUD._kinematicsElapsed = 0
                SpotterHUD:UpdateCompassVisuals(false, dt)
            end
        end
    end
    if not self._combatOnUpdateFn then
        self._combatOnUpdateFn = function(_, elapsed)
            local stepInterval = SpotterHUD._tickerInterval or 0.25
            SpotterHUD._combatKinElapsed = (SpotterHUD._combatKinElapsed or 0) + elapsed
            if SpotterHUD._combatKinElapsed >= stepInterval then
                local dt = SpotterHUD._combatKinElapsed
                SpotterHUD._combatKinElapsed = 0
                SpotterHUD:UpdateCompassVisuals(false, dt)
            end
        end
    end

    local f = self.frame
    if f then
        local mainActive = f:IsShown() and self._compassEntry ~= nil and isSelected
        if mainActive then
            if not f._scOnUpdateAttached then
                f._scOnUpdateAttached = true
                f:SetScript("OnUpdate", self._mainOnUpdateFn)
            end
        elseif f._scOnUpdateAttached then
            f._scOnUpdateAttached = false
            f:SetScript("OnUpdate", nil)
        end
    end

    local cf = self.combatArrowFrame
    if cf then
        local combatActive = cf:IsShown() and self._compassEntry ~= nil and isSelected
        if combatActive then
            if not cf._scOnUpdateAttached then
                cf._scOnUpdateAttached = true
                cf:SetScript("OnUpdate", self._combatOnUpdateFn)
            end
        elseif cf._scOnUpdateAttached then
            cf._scOnUpdateAttached = false
            cf:SetScript("OnUpdate", nil)
        end
    end
end

function SpotterHUD:BuildCombatArrowFrame()
    if self.combatArrowFrame then return self.combatArrowFrame end
    local cf = CreateFrame("Frame", "SocialCentralSpotterCombatArrow", UIParent, "BackdropTemplate")
    cf:SetSize(HUD_WIDTH, PILL_H)
    if self.frame then
        cf:SetPoint("TOP", self.frame, "TOP", 0, 0)
    else
        cf:SetPoint("TOP", UIParent, "TOP", 0, -64)
    end
    cf:SetFrameStrata("MEDIUM")
    cf:SetFrameLevel(45)

    local selWash = cf:CreateTexture(nil, "BACKGROUND", nil, 1)
    selWash:SetPoint("TOPLEFT", cf, "TOPLEFT", 5, -3)
    selWash:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -5, 3)
    selWash:SetBlendMode("ADD")
    selWash:Hide()
    cf.selWash = selWash

    local topBevel = cf:CreateTexture(nil, "BORDER", nil, 1)
    topBevel:SetHeight(1)
    topBevel:SetPoint("TOPLEFT", cf, "TOPLEFT", 8, -3)
    topBevel:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -8, -3)
    topBevel:SetColorTexture(1, 0.90, 0.65, 0.16)
    cf._topBevel = topBevel

    local stanceBar = cf:CreateTexture(nil, "OVERLAY")
    stanceBar:SetWidth(3)
    stanceBar:SetPoint("TOPLEFT", cf, "TOPLEFT", 3, -3)
    stanceBar:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 3, 3)
    stanceBar:SetColorTexture(0.98, 0.80, 0.24, 1)
    cf.stanceBar = stanceBar

    local arrowBox = CreateTargetCrestBox(cf, 6)

    local nameFs = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameFs:SetPoint("TOPLEFT", arrowBox, "TOPRIGHT", 8, 1)
    nameFs:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -8, 1)
    nameFs:SetJustifyH("LEFT")
    nameFs:SetWordWrap(false)
    cf.nameFs = nameFs

    local distFs = cf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    distFs:SetPoint("BOTTOMLEFT", arrowBox, "BOTTOMRIGHT", 8, -1)
    distFs:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -8, -1)
    distFs:SetJustifyH("LEFT")
    distFs:SetWordWrap(false)
    cf.distFs = distFs

    local subFs = cf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subFs:Hide()
    cf.subFs = subFs

    cf:HookScript("OnShow", function()
        if ns.NotificationToast and ns.NotificationToast.LayoutStack then
            ns.NotificationToast:LayoutStack()
        end
    end)
    cf:HookScript("OnHide", function()
        SpotterHUD:SyncTickerState(nil)
        if ns.NotificationToast and ns.NotificationToast.LayoutStack then
            ns.NotificationToast:LayoutStack()
        end
    end)

    cf:Hide()
    Theme:ApplyBackdrop(cf, "window", Theme:GetPalette())
    self.combatArrowFrame = cf
    return cf
end

function SpotterHUD:ShowCombatArrowFallback()
    if not (ns.Spotter and ns.Spotter.IsEnabled and ns.Spotter:IsEnabled()) then
        if self.combatArrowFrame then self.combatArrowFrame:Hide() end
        return
    end
    local cf = self.combatArrowFrame or self:BuildCombatArrowFrame()
    if not cf then return end
    if cf._dirtyTheme then
        cf._dirtyTheme = nil
        local p = Theme:GetPalette()
        Theme:ApplyBackdrop(cf, "window", p)
        if cf.subFs then
            cf.subFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
        end
    end
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
        local currentTargetGuid, tLookupKey, tFirstName, tSurname = ReadCurrentTargetIdentity()
        for _, cand in ipairs(allTargets) do
            if IsEntryCurrentlyTargeted(cand, currentTargetGuid, tLookupKey, tFirstName, tSurname) then
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
        or (entry.stance == "BLOCKED" and L["BLOCKED"])
        or (entry.stance == "WATCHLIST" and L["WATCHLIST"])
        or (entry.stance == "FRIEND" and L["FRIEND"])
        or (entry.stance == "ALLY" and L["ALLY"] or L["CLAN"])
    local colHex = ns.Spotter:GetStanceColor(entry.stance).hex
    local classHex = Compat.ClassHex and Compat.ClassHex(entry.classFile) or "|cffffffff"
    if self.frame then
        cf:ClearAllPoints()
        cf:SetPoint("TOP", self.frame, "TOP", 0, 0)
    end
    local lvlPart = (entry.level and tonumber(entry.level) and tonumber(entry.level) > 0) and (" |cff8b949e" .. tostring(entry.level) .. "|r") or ""
    cf.nameFs:SetText(string.format("%s[%s]|r %s%s|r%s", colHex, stanceTag, classHex, entry.displayName or "?", lvlPart))
    cf.distFs:SetText(entry.locationText and entry.locationText ~= "" and ("|cff8b949e" .. entry.locationText .. "|r") or ("|cff8b949e" .. L["In Combat"] .. "|r"))
    cf.subFs:SetText(entry.locationText or (entry.guild and ("<" .. entry.guild .. ">") or ""))
    cf:Show()
    self:UpdateCompassVisuals(true, 0.04)
end

local function ApplyActionPanelTheme(actionPanel, p)
    if not actionPanel then return end
    Theme:ApplyBackdrop(actionPanel, "inset", p)
    actionPanel.promptFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
    if actionPanel.whisperBtn then Theme:StyleButton(actionPanel.whisperBtn, "primary") end
    if actionPanel.scoutBtn then Theme:StyleButton(actionPanel.scoutBtn, "danger") end
    if actionPanel.inviteBtn then Theme:StyleButton(actionPanel.inviteBtn, "default") end
    if actionPanel.watchBtn then Theme:StyleButton(actionPanel.watchBtn, "default") end
    actionPanel._lastLayoutStance = nil
    actionPanel._dirtyTheme = nil
end

local function ApplyHUDSelectionHighlight(f, isTargeted, stanceRgb, p)
    if not f then return end
    local pal = p or Theme:GetPalette()
    local rgb = stanceRgb or STANCE_RGB.SAME
    local sr, sg, sb = rgb[1], rgb[2], rgb[3]
    if f._scHLActive == isTargeted and (not isTargeted or (f._scHLR == sr and f._scHLG == sg and f._scHLB == sb)) and not f._scHLForce then
        return
    end
    f._scHLForce = nil
    f._scHLActive = isTargeted
    f._scHLR = sr
    f._scHLG = sg
    f._scHLB = sb
    if isTargeted then
        if f.selWash then
            f.selWash:SetColorTexture(sr, sg, sb, 0.14)
            f.selWash:Show()
        end
        if f.SetBackdropBorderColor then
            f:SetBackdropBorderColor(
                math.min(1, sr * 0.85 + 0.12),
                math.min(1, sg * 0.85 + 0.12),
                math.min(1, sb * 0.85 + 0.12),
                1.0
            )
        end
    else
        if f.selWash then
            f.selWash:Hide()
        end
        local br = pal and (pal.windowBorder or pal.surfaceBorder)
        if f.SetBackdropBorderColor and br then
            f:SetBackdropBorderColor(br[1], br[2], br[3], 1.0)
        end
    end
end

function SpotterHUD:UpdateAppearance()
    local p = Theme:GetPalette()
    if self.combatArrowFrame then
        if self.combatArrowFrame:IsShown() then
            self.combatArrowFrame._dirtyTheme = nil
            Theme:ApplyBackdrop(self.combatArrowFrame, "window", p)
            self.combatArrowFrame.subFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
        else
            self.combatArrowFrame._dirtyTheme = true
        end
    end

    local f = self.frame
    if not f then return end

    if f._dirtyTheme then
        f._dirtyTheme = nil
    end
    Theme:ApplyBackdrop(f, "window", p)
    local isWarm = (p and (p.key == "blizzard" or p.key == "native"))
    if f._topBevel then
        f._topBevel:SetColorTexture(isWarm and 1 or 0.65, isWarm and 0.90 or 0.85, isWarm and 0.65 or 1.0, isWarm and 0.16 or 0.14)
    end
    if f.drawerSep then
        if isWarm then
            f.drawerSep:SetColorTexture(0.68, 0.56, 0.28, 0.35)
        else
            f.drawerSep:SetColorTexture(0.30, 0.72, 1.0, 0.25)
        end
    end
    if self.combatArrowFrame and self.combatArrowFrame._topBevel then
        self.combatArrowFrame._topBevel:SetColorTexture(isWarm and 1 or 0.65, isWarm and 0.90 or 0.85, isWarm and 0.65 or 1.0, isWarm and 0.16 or 0.14)
    end
    f._scHLForce = true
    if f.compassBar then
        f.compassBar.subFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
    end
    if f.actionPanel then
        if not f.actionPanel._scOnShowHooked then
            f.actionPanel._scOnShowHooked = true
            f.actionPanel:HookScript("OnShow", function(selfPanel)
                if selfPanel._dirtyTheme then
                    ApplyActionPanelTheme(selfPanel, Theme:GetPalette())
                end
            end)
        end
        if f.actionPanel:IsShown() then
            ApplyActionPanelTheme(f.actionPanel, p)
        else
            f.actionPanel._dirtyTheme = true
        end
    end

    if f.navBar then
        if not f.navBar._scOnShowHooked then
            f.navBar._scOnShowHooked = true
            f.navBar:HookScript("OnShow", function(selfBar)
                if selfBar._dirtyTheme then
                    ApplyNavBarTheme(selfBar, Theme:GetPalette())
                end
            end)
        end
        if f.navBar:IsShown() then
            ApplyNavBarTheme(f.navBar, p)
        else
            f.navBar._dirtyTheme = true
        end
    end

    Theme:StyleButton(f.closeBtn, "danger")
    self:Refresh()
end

local function ResetCompassBarDirtyState(bar)
    if not bar then return end
    bar._visDead = nil
    bar._visClassFile = nil
    bar._visRingDead = nil
    bar._visRingStance = nil
    bar._visRingSelected = nil
    bar._visDistOut = nil
end

local function ApplyCompassBarVisuals(bar, entry, kin)
    if not bar then return end

    local stanceVal = entry.stance or "SAME"
    local isDead = entry.dead == true
    local isSelected = (kin ~= nil and kin.isSelected == true)
    local rgb = STANCE_RGB[stanceVal] or STANCE_RGB.SAME

    local classFileVal = entry.classFile or false
    local crest = bar.crestTex
    if crest and (bar._visDead ~= isDead or bar._visClassFile ~= classFileVal) then
        bar._visDead = isDead
        bar._visClassFile = classFileVal
        local coords = classFileVal and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFileVal]
        if coords then
            crest:SetTexture(CLASS_SPRITE_TEX)
            crest:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
            if isDead then
                crest:SetVertexColor(0.55, 0.55, 0.55, 0.70)
            else
                crest:SetVertexColor(1, 1, 1, 1)
            end
        else
            crest:SetTexture(RADAR_FALLBACK_ICON)
            crest:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if isDead then
                crest:SetVertexColor(0.55, 0.55, 0.55, 0.70)
            else
                crest:SetVertexColor(1, 1, 1, 0.95)
            end
        end
    end

    if bar.arrowBox and bar.arrowBox.outerRing and (bar._visRingDead ~= isDead or bar._visRingStance ~= stanceVal or bar._visRingSelected ~= isSelected) then
        bar._visRingDead = isDead
        bar._visRingStance = stanceVal
        bar._visRingSelected = isSelected
        if isDead then
            bar.arrowBox.outerRing:SetVertexColor(0.45, 0.45, 0.45, 0.75)
        elseif isSelected then
            bar.arrowBox.outerRing:SetVertexColor(0.28, 0.78, 1.0, 1.0)
        else
            bar.arrowBox.outerRing:SetVertexColor(rgb[1], rgb[2], rgb[3], 0.95)
        end
    end

    -- Pure Distance Calculator (strictly calculated only while actively targeted)
    local distStr
    if not isSelected then
        distStr = "|cff8b949e" .. L["Select target to measure distance"] .. "|r"
    elseif isDead then
        distStr = "|cff888888" .. L["Dead"] .. "|r"
    else
        local distNum = kin.distYards
        if distNum and type(distNum) == "number" and distNum >= 0 then
            if distNum <= 10 then
                distStr = string.format("|cff4ade80~%dm|r", distNum)
            elseif distNum <= 25 then
                distStr = string.format("|cff86efac%dm|r", distNum)
            elseif distNum <= 40 then
                distStr = string.format("|cfffde047%dm|r", distNum)
            elseif distNum <= 60 then
                distStr = string.format("|cfffb923c%dm|r", distNum)
            else
                local prefix = (not kin.exact) and ">" or ""
                distStr = string.format("|cff94a3b8%s%dm|r", prefix, distNum)
            end
        else
            local rawText = kin.distText or L["Nearby"]
            distStr = "|cff58d8ff" .. rawText .. "|r"
        end
    end

    local zoneShort = isSelected and (entry.subZone and entry.subZone ~= "") and entry.subZone or ""
    local locPart = (zoneShort ~= "") and (" |cff8b949e· " .. zoneShort .. "|r") or ""
    local distOut = distStr .. locPart

    if bar._visDistOut ~= distOut then
        bar._visDistOut = distOut
        bar.distFs:SetText(distOut)
    end
end

function SpotterHUD:UpdateCompassVisuals(snap, dt)
    local f = self.frame
    local cf = self.combatArrowFrame
    local mainCompassActive = f and f:IsShown() and f.compassBar and f.compassBar:IsShown()
    local combatCompassActive = cf and cf:IsShown()

    local entry = self._compassEntry
    local kin = (entry and ns.Spotter and ns.Spotter.GetTargetKinematics) and ns.Spotter:GetTargetKinematics(entry) or nil

    if not (mainCompassActive or combatCompassActive) then
        self:SyncTickerState(nil)
        return
    end

    if not kin then
        self:SyncTickerState(nil)
        return
    end

    -- Keep the secure target macro synced only when target identity or resolved unit token changes
    if mainCompassActive and not (InCombatLockdown and InCombatLockdown()) then
        local curUnit = kin.unit or ""
        local curDisp = entry.displayName or ""
        local curUName = entry.unitName or ""
        if snap
            or f.compassBar._sigKey ~= entry.key
            or f.compassBar._sigUnit ~= curUnit
            or f.compassBar._sigDisp ~= curDisp
            or f.compassBar._sigUName ~= curUName
        then
            f.compassBar._sigKey = entry.key
            f.compassBar._sigUnit = curUnit
            f.compassBar._sigDisp = curDisp
            f.compassBar._sigUName = curUName
            local expectedMacro = BuildTargetMacroText(entry, kin.unit)
            if expectedMacro ~= f.compassBar._lastMacroText then
                ApplySecureMacroAttributes(f.compassBar, entry, kin.unit)
            end
        end
    elseif mainCompassActive and InCombatLockdown and InCombatLockdown() then
        self.pendingRefresh = true
    end

    if entry and entry.key ~= self._lastCompassEntryKey then
        self._lastCompassEntryKey = entry.key
        ResetCompassBarDirtyState(f and f.compassBar)
        ResetCompassBarDirtyState(cf)
    end

    if mainCompassActive then
        ApplyCompassBarVisuals(f.compassBar, entry, kin)
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
        ApplyCompassBarVisuals(cf, entry, kin)
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

    self:SyncTickerState(kin)
end

local function ApplyHUDEntryIdentity(f, entry)
    if not (f and f.compassBar and entry) then return end
    local stanceVal = entry.stance or "SAME"
    local rgb = STANCE_RGB[stanceVal] or STANCE_RGB.SAME
    if f.stanceBar and f._lastStanceBar ~= stanceVal then
        f._lastStanceBar = stanceVal
        f.stanceBar:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    end

    f.compassBar.entry = entry

    local dispName = entry.displayName or "?"
    local classVal = entry.classFile or false
    local lvlVal = (entry.level and entry.level > 0) and entry.level or 0
    if f._lastNameStance ~= stanceVal or f._lastNameText ~= dispName or f._lastNameClass ~= classVal or f._lastNameLvl ~= lvlVal then
        f._lastNameStance = stanceVal
        f._lastNameText = dispName
        f._lastNameClass = classVal
        f._lastNameLvl = lvlVal
        local stanceTag = stanceVal == "ENEMY" and L["ENEMY"]
            or (stanceVal == "BLOCKED" and L["BLOCKED"])
            or (stanceVal == "WATCHLIST" and L["WATCHLIST"])
            or (stanceVal == "FRIEND" and L["FRIEND"])
            or (stanceVal == "ALLY" and L["ALLY"] or L["CLAN"])
        local colHex = (ns.Spotter and ns.Spotter.GetStanceColor and ns.Spotter:GetStanceColor(stanceVal).hex) or "|cffffffff"
        local classHex = Compat.ClassHex and Compat.ClassHex(entry.classFile) or "|cffffffff"
        local lvlPart = (lvlVal > 0) and (" |cff8b949e" .. lvlVal .. "|r") or ""
        f.compassBar.nameFs:SetText(string.format("%s[%s]|r %s%s|r%s", colHex, stanceTag, classHex, dispName, lvlPart))
    end

    if f.compassBar.subFs then
        local guildAndLoc = entry.guild and ("<" .. entry.guild .. ">") or ""
        if entry.locationText and entry.locationText ~= "" then
            guildAndLoc = (guildAndLoc ~= "") and (guildAndLoc .. " · " .. entry.locationText) or entry.locationText
        end
        if f.compassBar._lastSubText ~= guildAndLoc then
            f.compassBar._lastSubText = guildAndLoc
            f.compassBar.subFs:SetText(guildAndLoc)
        end
    end
end

function SpotterHUD:UpdateTargetVisuals()
    local f = self.frame
    local cf = self.combatArrowFrame
    local mainShown = (f and f:IsShown() and f.compassBar) == true
    local combatShown = (cf and cf:IsShown()) == true
    if not mainShown and not combatShown then return end

    local spotter = ns.Spotter
    local entriesMap = spotter and spotter.entries
    local prevKey = self._compassEntry and self._compassEntry.key
    local currentTargetGuid, tLookupKey, tFirstName, tSurname = ReadCurrentTargetIdentity()
    local entry = self._compassEntry
    local targetedMatch
    if (currentTargetGuid or tLookupKey) and entriesMap then
        for _, cand in pairs(entriesMap) do
            if IsEntryCurrentlyTargeted(cand, currentTargetGuid, tLookupKey, tFirstName, tSurname) then
                targetedMatch = cand
                break
            end
        end
    end
    if targetedMatch then
        entry = targetedMatch
        self._compassEntry = targetedMatch
        self.focusedKey = targetedMatch.key
    elseif entry and entriesMap and entriesMap[entry.key] then
        entry = entriesMap[entry.key]
    else
        local allTargets = spotter and spotter:GetActiveTargets("ALL") or {}
        entry = allTargets[1]
        self._compassEntry = entry
    end
    if not entry then return end

    local isTargeted = IsEntryCurrentlyTargeted(entry, currentTargetGuid, tLookupKey, tFirstName, tSurname)
    local stanceVal = entry.stance or "SAME"
    local stanceRgb = STANCE_RGB[stanceVal] or STANCE_RGB.SAME
    local entryChanged = (prevKey ~= entry.key)
    local inCombat = (InCombatLockdown and InCombatLockdown()) == true

    if mainShown then
        ApplyHUDSelectionHighlight(f, isTargeted, stanceRgb)
        ApplyHUDEntryIdentity(f, entry)
        if entryChanged then
            if not inCombat then
                self:Refresh()
                return
            end
            self.pendingRefresh = true
        end
    end

    if combatShown then
        if cf._lastStanceVal ~= stanceVal then
            cf._lastStanceVal = stanceVal
            if cf.stanceBar then
                cf.stanceBar:SetColorTexture(stanceRgb[1], stanceRgb[2], stanceRgb[3], 1)
            end
        end
        local stanceTag = stanceVal == "ENEMY" and L["ENEMY"]
            or (stanceVal == "BLOCKED" and L["BLOCKED"])
            or (stanceVal == "WATCHLIST" and L["WATCHLIST"])
            or (stanceVal == "FRIEND" and L["FRIEND"])
            or (stanceVal == "ALLY" and L["ALLY"] or L["CLAN"])
        local colHex = (ns.Spotter and ns.Spotter.GetStanceColor and ns.Spotter:GetStanceColor(stanceVal).hex) or "|cffffffff"
        local classHex = Compat.ClassHex and Compat.ClassHex(entry.classFile) or "|cffffffff"
        local lvlPart = (entry.level and tonumber(entry.level) and tonumber(entry.level) > 0) and (" |cff8b949e" .. tostring(entry.level) .. "|r") or ""
        local nameOut = string.format("%s[%s]|r %s%s|r%s", colHex, stanceTag, classHex, entry.displayName or "?", lvlPart)
        if cf.nameFs and cf._lastNameOut ~= nameOut then
            cf._lastNameOut = nameOut
            cf.nameFs:SetText(nameOut)
        end
        ApplyHUDSelectionHighlight(cf, isTargeted, stanceRgb)
    end

    self:UpdateCompassVisuals(entryChanged, 0.04)
    if ns.Spotter and ns.Spotter.UpdateFocusedPlateMarker then
        ns.Spotter:UpdateFocusedPlateMarker()
    end
end

function SpotterHUD:Refresh()
    if not (ns.Spotter and ns.Spotter.IsEnabled and ns.Spotter:IsEnabled()) then
        return
    end
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
        self._lastCompassEntryKey = nil
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

    local currentTargetGuid, tLookupKey, tFirstName, tSurname = ReadCurrentTargetIdentity()

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
                if IsEntryCurrentlyTargeted(cand, currentTargetGuid, tLookupKey, tFirstName, tSurname) then
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

    local showNav = UpdateSpotterNavBar(f, allTargets, activeIdx, totalCount, p)

    if not compassEntry then
        -- Empty state when opened manually via /sc radar
        if f.stanceBar then
            f.stanceBar:SetColorTexture(p.accent[1], p.accent[2], p.accent[3], 1)
        end
        ApplySecureMacroAttributes(f.compassBar, nil)
        f.compassBar._sigKey = nil
        f.compassBar._sigUnit = nil
        f.compassBar._sigDisp = nil
        f.compassBar._sigUName = nil
        ApplyHUDSelectionHighlight(f, false, nil, p)
        self._lastCompassEntryKey = nil
        f.compassBar.entry = nil
        if f.compassBar.arrowBox and f.compassBar.arrowBox.outerRing then
            f.compassBar.arrowBox.outerRing:SetVertexColor(p.accent[1], p.accent[2], p.accent[3], 0.70)
        end
        if f.compassBar.crestTex then
            f.compassBar.crestTex:SetTexture(RADAR_FALLBACK_ICON)
            f.compassBar.crestTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            f.compassBar.crestTex:SetVertexColor(0.85, 0.90, 0.96, 0.85)
        end
        ResetCompassBarDirtyState(f.compassBar)
        f.compassBar.nameFs:SetText(L["Target Radar"])
        f._lastStanceBar = nil
        f._lastNameStance = nil
        f._lastNameText = nil
        f._lastNameClass = nil
        f._lastNameLvl = nil
        f.compassBar._lastSubText = nil
        f.compassBar.distFs:SetText("|cff8b949e" .. L["No targets currently detected."] .. "|r")
        ApplySpotterFrameLayout(f, false, false)
        self:SyncTickerState(nil)
        if ns.Spotter and ns.Spotter.UpdateFocusedPlateMarker then
            ns.Spotter:UpdateFocusedPlateMarker()
        end
        return
    end

    local stanceVal = compassEntry.stance or "SAME"
    local rgb = STANCE_RGB[stanceVal] or STANCE_RGB.SAME
    local dispName = compassEntry.displayName or "?"
    ApplyHUDEntryIdentity(f, compassEntry)

    local isActuallyTargeted = IsEntryCurrentlyTargeted(compassEntry, currentTargetGuid, tLookupKey, tFirstName, tSurname)
    ApplyHUDSelectionHighlight(f, isActuallyTargeted, rgb, p)

    self:UpdateCompassVisuals(true, 0.04)

    -- Show or hide the On-Click Interaction Drawer below the Target Pill
    if self.interactionOpen and (not self.interactionKey or self.interactionKey == compassEntry.key) then
        local guildAndLoc = compassEntry.guild and ("<" .. compassEntry.guild .. ">") or ""
        if compassEntry.locationText and compassEntry.locationText ~= "" then
            guildAndLoc = (guildAndLoc ~= "") and (guildAndLoc .. " · " .. compassEntry.locationText) or compassEntry.locationText
        end
        local desiredPrompt = guildAndLoc ~= "" and guildAndLoc or dispName
        if f.actionPanel._lastPromptText ~= desiredPrompt then
            f.actionPanel._lastPromptText = desiredPrompt
            f.actionPanel.promptFs:SetText(desiredPrompt)
        end
        local baseKey = (stanceVal == "ENEMY" and "ENEMY") or (stanceVal == "BLOCKED" and "BLOCKED") or "DEFAULT"
        local lookupId = compassEntry.key or compassEntry.displayName
        local isWatchedNow = (baseKey == "DEFAULT" and lookupId and ns.Watchlist and ns.Watchlist.IsWatched and ns.Watchlist:IsWatched(lookupId)) == true
        local curMetaRadar = (baseKey == "ENEMY" and lookupId and Store)
            and ((Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(lookupId)) or (Store.GetSocialMeta and Store:GetSocialMeta(lookupId)))
            or nil
        local isAvoidNow = (curMetaRadar and curMetaRadar.flag == "AVOID") == true
        local layoutKey = baseKey .. ":" .. ((baseKey == "ENEMY") and (isAvoidNow and "A" or "N") or ((baseKey == "DEFAULT") and (isWatchedNow and "W" or "N") or "B"))
        if f.actionPanel._lastLayoutStance ~= layoutKey then
            f.actionPanel._lastLayoutStance = layoutKey
            local rowBtns = {}
            if baseKey == "ENEMY" then
                if f.actionPanel.whisperBtn then f.actionPanel.whisperBtn:Hide() end
                if f.actionPanel.scoutBtn then
                    Theme:SetButtonText(f.actionPanel.scoutBtn, L["Scout Alert"])
                    f.actionPanel.scoutBtn:Show()
                    rowBtns[#rowBtns + 1] = f.actionPanel.scoutBtn
                end
                if f.actionPanel.inviteBtn then
                    Theme:SetButtonText(f.actionPanel.inviteBtn, L["Diplomacy"])
                    rowBtns[#rowBtns + 1] = f.actionPanel.inviteBtn
                end
                if f.actionPanel.watchBtn then
                    Theme:SetButtonText(f.actionPanel.watchBtn, isAvoidNow and ("|cffff4d4d[x]|r " .. L["AVOID"]) or ("+ " .. L["AVOID"]))
                    rowBtns[#rowBtns + 1] = f.actionPanel.watchBtn
                end
            elseif baseKey == "BLOCKED" then
                if f.actionPanel.whisperBtn then f.actionPanel.whisperBtn:Hide() end
                if f.actionPanel.scoutBtn then f.actionPanel.scoutBtn:Hide() end
                if f.actionPanel.inviteBtn then
                    Theme:SetButtonText(f.actionPanel.inviteBtn, L["Dismiss Target"])
                    rowBtns[#rowBtns + 1] = f.actionPanel.inviteBtn
                end
                if f.actionPanel.watchBtn then
                    Theme:SetButtonText(f.actionPanel.watchBtn, L["Manage Block"])
                    rowBtns[#rowBtns + 1] = f.actionPanel.watchBtn
                end
            else
                if f.actionPanel.scoutBtn then f.actionPanel.scoutBtn:Hide() end
                if f.actionPanel.whisperBtn then
                    Theme:SetButtonText(f.actionPanel.whisperBtn, L["Whisper"])
                    f.actionPanel.whisperBtn:Show()
                    rowBtns[#rowBtns + 1] = f.actionPanel.whisperBtn
                end
                if f.actionPanel.inviteBtn then
                    Theme:SetButtonText(f.actionPanel.inviteBtn, L["Invite"])
                    rowBtns[#rowBtns + 1] = f.actionPanel.inviteBtn
                end
                if f.actionPanel.watchBtn then
                    Theme:SetButtonText(f.actionPanel.watchBtn, isWatchedNow and ("- " .. L["Watchlist"]) or ("+ " .. L["Watchlist"]))
                    rowBtns[#rowBtns + 1] = f.actionPanel.watchBtn
                end
            end
            if #rowBtns > 0 then
                local gap = 5
                local panelW = math.max(260, (f.actionPanel:GetWidth() or (f:GetWidth() or 320) - 12))
                local availW = panelW - 12 - ((#rowBtns - 1) * gap)
                local widths = {}
                local sumW = 0
                for idx, rb in ipairs(rowBtns) do
                    local fit = Theme:AutoFitButton(rb, 64, 12, 168)
                    widths[idx] = math.floor((fit or rb:GetWidth() or 80) + 0.5)
                    sumW = sumW + widths[idx]
                end
                local extra = availW - sumW
                if extra >= 0 then
                    local each = math.floor(extra / #rowBtns)
                    for idx = 1, #rowBtns do
                        widths[idx] = widths[idx] + each
                    end
                elseif sumW > 0 then
                    local scale = availW / sumW
                    for idx = 1, #rowBtns do
                        widths[idx] = math.max(58, math.floor(widths[idx] * scale))
                    end
                end
                local sig = tostring(layoutKey) .. ":" .. tostring(#rowBtns) .. ":" .. table.concat(widths, ",")
                if f.actionPanel._scBtnLayoutSig ~= sig then
                    f.actionPanel._scBtnLayoutSig = sig
                    local prevRb = nil
                    for idx, rb in ipairs(rowBtns) do
                        rb:SetWidth(widths[idx])
                        rb:ClearAllPoints()
                        if prevRb then
                            rb:SetPoint("LEFT", prevRb, "RIGHT", gap, 0)
                        else
                            rb:SetPoint("BOTTOMLEFT", 6, 4)
                        end
                        prevRb = rb
                    end
                end
            end
        end
        local wantInviteEnabled = true
        if layoutKey == "DEFAULT" then
            wantInviteEnabled = ResolveSpotterContactState(compassEntry) == true
        end
        if f.actionPanel.inviteBtn and f.actionPanel._lastInviteEnabled ~= wantInviteEnabled then
            f.actionPanel._lastInviteEnabled = wantInviteEnabled
            f.actionPanel.inviteBtn:SetEnabled(wantInviteEnabled)
        end
        ApplySpotterFrameLayout(f, showNav, true)
    else
        ApplySpotterFrameLayout(f, showNav, false)
    end
    if ns.Spotter and ns.Spotter.UpdateFocusedPlateMarker then
        ns.Spotter:UpdateFocusedPlateMarker()
    end
end

function SpotterHUD:ShowNameplateTutorial(forceShow)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        if not forceShow then
            self._pendingPlateTutorial = true
        end
        return
    end
    self._pendingPlateTutorial = false
    local s = ns.db and ns.db.settings
    if not forceShow then
        if not (ns.Spotter and ns.Spotter.IsEnabled and ns.Spotter:IsEnabled()) then
            return
        end
        if (ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("spotterPlateTutorialShown")) or (s and s.spotterPlateTutorialShown == true) then
            return
        end
        if s and s.spotterNameplateArrow == false and s.spotterNameplateBadges == false then
            return
        end
    end
    local function ResolveRadarHudTarget()
        return (_G.SocialCentralSpotterFrame and _G.SocialCentralSpotterFrame:IsShown()) and _G.SocialCentralSpotterFrame or nil
    end
    local plateSpec = {
        key = "spotter_plate",
        doneLabel = L["Got it, don't show again"],
        defaultTarget = ResolveRadarHudTarget,
        isAnchorVisible = function()
            return (_G.SocialCentralSpotterFrame and _G.SocialCentralSpotterFrame:IsShown()) == true
        end,
        steps = {
            {
                title = L["Nameplate Indicators & Target Arrow"],
                text = L["Marks tracked players and points a red arrow on visible nameplates."],
            },
            {
                title = L["Nameplate Shortcuts"],
                text = L["Shift+V toggles friendly plates · V toggles enemy plates."],
            },
        },
    }
    if not forceShow and Theme and Theme.PromptWindowTutorial then
        Theme:PromptWindowTutorial({
            tutorialKey = "spotterPlateTutorialShown",
            title = L["Target Radar Nameplates"],
            guideSpec = plateSpec,
            isWindowVisible = plateSpec.isAnchorVisible,
            onSkip = function()
                if ns.SetAccountTutorialShown then
                    ns:SetAccountTutorialShown("spotterPlateTutorialShown", true)
                elseif ns.db and ns.db.settings then
                    ns.db.settings.spotterPlateTutorialShown = true
                end
            end,
        })
        return
    end
    if ns.SetAccountTutorialShown then
        ns:SetAccountTutorialShown("spotterPlateTutorialShown", true)
    elseif ns.db and ns.db.settings then
        ns.db.settings.spotterPlateTutorialShown = true
    end
    if not (Theme and Theme.ShowNpcGuide) then
        return
    end
    self.tutorialDialog = Theme:ShowNpcGuide(plateSpec)
end

function SpotterHUD:ShowNameplateTutorialIfNeeded()
    self:ShowNameplateTutorial(false)
end

function SpotterHUD:ShowRadarTutorial(forceShow)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        if not forceShow then
            self._pendingRadarTutorial = true
        end
        return
    end
    self._pendingRadarTutorial = false
    local s = ns.db and ns.db.settings
    if not forceShow then
        if not (ns.Spotter and ns.Spotter.IsEnabled and ns.Spotter:IsEnabled()) then
            return
        end
        if (ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("spotterRadarTutorialShown")) or (s and s.spotterRadarTutorialShown == true) then
            return
        end
    end
    local function ResolveRadarHudTarget()
        return (_G.SocialCentralSpotterFrame and _G.SocialCentralSpotterFrame:IsShown()) and _G.SocialCentralSpotterFrame or nil
    end
    local radarSpec = {
        key = "spotter_radar",
        doneLabel = L["Got it, don't show again"],
        defaultTarget = ResolveRadarHudTarget,
        isAnchorVisible = function()
            return (_G.SocialCentralSpotterFrame and _G.SocialCentralSpotterFrame:IsShown()) == true
        end,
        steps = {
            {
                title = L["Target Radar"],
                text = L["Detects nearby Watchlist, Friends, Allies, and Enemies within nameplate range."],
            },
            {
                title = L["Target Radar Controls"],
                text = L["Click the HUD out of combat to target · Right-click entries to toggle tracking."],
            },
        },
    }
    if not forceShow and Theme and Theme.PromptWindowTutorial then
        Theme:PromptWindowTutorial({
            tutorialKey = "spotterRadarTutorialShown",
            title = L["Target Radar"],
            guideSpec = radarSpec,
            isWindowVisible = radarSpec.isAnchorVisible,
            onSkip = function()
                if ns.SetAccountTutorialShown then
                    ns:SetAccountTutorialShown("spotterRadarTutorialShown", true)
                elseif ns.db and ns.db.settings then
                    ns.db.settings.spotterRadarTutorialShown = true
                end
            end,
        })
        return
    end
    if ns.SetAccountTutorialShown then
        ns:SetAccountTutorialShown("spotterRadarTutorialShown", true)
    elseif ns.db and ns.db.settings then
        ns.db.settings.spotterRadarTutorialShown = true
    end
    if not (Theme and Theme.ShowNpcGuide) then
        return
    end
    self.radarTutorialDialog = Theme:ShowNpcGuide(radarSpec)
end

function SpotterHUD:Show(forceUser)
    if not (ns.Spotter and ns.Spotter.IsEnabled and ns.Spotter:IsEnabled()) then
        if forceUser and ns.Print then
            ns:Print(L["Clan Radar notifications disabled. Re-enable anytime in Settings."])
        end
        return
    end
    if forceUser and ns.Spotter.RefreshVisibleNameplates and not (InCombatLockdown and InCombatLockdown()) then
        ns.Spotter:RefreshVisibleNameplates(false)
    end
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
    if tCount > 0 or forceUser then
        self:ShowNameplateTutorialIfNeeded()
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
    if ns.NotificationToast and ns.NotificationToast.LayoutStack then
        ns.NotificationToast:LayoutStack()
    end
    if ns.Spotter and ns.Spotter.UpdateFocusedPlateMarker then
        ns.Spotter:UpdateFocusedPlateMarker()
    end
end

function SpotterHUD:Hide()
    if self.combatArrowFrame then
        self.combatArrowFrame:Hide()
    end
    if not self.frame then
        self:SyncTickerState(nil)
        if ns.Spotter and ns.Spotter.UpdateFocusedPlateMarker then
            ns.Spotter:UpdateFocusedPlateMarker()
        end
        return
    end
    self.manualPinnedEmpty = false
    self.interactionOpen = false
    self.interactionKey = nil
    self.frame._lastActionOpen = false
    self.frame._lastFrameH = nil
    if InCombatLockdown and InCombatLockdown() then
        self.pendingAction = "hide"
        self:SyncTickerState(nil)
        return
    end
    self.frame:Hide()
    self:SyncTickerState(nil)
    if ns.NotificationToast and ns.NotificationToast.LayoutStack then
        ns.NotificationToast:LayoutStack()
    end
    if ns.Spotter and ns.Spotter.UpdateFocusedPlateMarker then
        ns.Spotter:UpdateFocusedPlateMarker()
    end
end

function SpotterHUD:Toggle()
    if not (ns.Spotter and ns.Spotter.IsEnabled and ns.Spotter:IsEnabled()) then
        self:Hide()
        if ns.Print then
            ns:Print(L["Clan Radar notifications disabled. Re-enable anytime in Settings."])
        end
        return
    end
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
    if not (ns.Spotter and ns.Spotter.IsEnabled and ns.Spotter:IsEnabled()) then
        return
    end
    if not alert then return end
    self.focusedKey = alert.key

    self:ShowNameplateTutorialIfNeeded()

    local s = ns.db and ns.db.settings
    if not s or s.spotterAutoShowHUD ~= false then
        if self.userClosed and alert.stance ~= "ENEMY" and alert.stance ~= "BLOCKED" then
            return
        end
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
    if stanceArg ~= "ENEMY" and stanceArg ~= "BLOCKED" and stanceArg ~= "ALLY" and stanceArg ~= "SAME" and stanceArg ~= "WATCHLIST" and stanceArg ~= "FRIEND" then
        stanceArg = nil
    end
    return ns.Spotter:TrackPlayer(name, guild, classFile, level, guid, stanceArg)
end

function SpotterHUD:Init()
    self.pendingRefresh = false
    self.pendingAction = nil

    if not self._eventFrame then
        local ef = CreateFrame("Frame")
        ef:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_TARGET_CHANGED" then
                if (SpotterHUD.frame and SpotterHUD.frame:IsShown()) or (SpotterHUD.combatArrowFrame and SpotterHUD.combatArrowFrame:IsShown()) then
                    SpotterHUD:UpdateTargetVisuals()
                end
            elseif event == "PLAYER_REGEN_ENABLED" then
                local act = SpotterHUD.pendingAction
                local doRefresh = SpotterHUD.pendingRefresh
                SpotterHUD.pendingAction = nil
                SpotterHUD.pendingRefresh = false
                if act == "hide" then
                    SpotterHUD:Hide()
                elseif act == "show" then
                    SpotterHUD:Show(false)
                elseif doRefresh then
                    SpotterHUD:Refresh()
                end
                if SpotterHUD._pendingRadarTutorial and SpotterHUD.frame and SpotterHUD.frame:IsShown() then
                    SpotterHUD:ShowRadarTutorial(false)
                elseif SpotterHUD._pendingPlateTutorial and SpotterHUD.frame and SpotterHUD.frame:IsShown() then
                    SpotterHUD:ShowNameplateTutorial(false)
                end
            end
        end)
        pcall(ef.RegisterEvent, ef, "PLAYER_TARGET_CHANGED")
        pcall(ef.RegisterEvent, ef, "PLAYER_REGEN_ENABLED")
        self._eventFrame = ef
    end

    if not self._hooksInitialized then
        self._hooksInitialized = true
        ns:On("SPOTTER_UPDATED", function()
            if (SpotterHUD.frame and SpotterHUD.frame:IsShown()) or (SpotterHUD.combatArrowFrame and SpotterHUD.combatArrowFrame:IsShown()) or GetSpotterTotalCount() > 0 then
                SpotterHUD:Refresh()
            end
        end)
        ns:On("SPOTTER_ALERT", function(alert)
            SpotterHUD:OnAlert(alert)
        end)
        ns:On("SETTINGS_UPDATED", function()
            if not (ns.Spotter and ns.Spotter.IsEnabled and ns.Spotter:IsEnabled()) then
                SpotterHUD:Hide()
            elseif SpotterHUD.frame then
                SpotterHUD:UpdateAppearance()
            end
        end)
        if Theme and Theme.RegisterListener then
            Theme:RegisterListener(function()
                if SpotterHUD.frame then
                    SpotterHUD:UpdateAppearance()
                end
            end)
        end
    end
end

ns.SpotterHUD = SpotterHUD
table.insert(ns.modules, SpotterHUD)
