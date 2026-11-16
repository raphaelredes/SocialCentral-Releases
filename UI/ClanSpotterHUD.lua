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
    minimapPins = {},
    worldMapPins = {},
}

local HUD_WIDTH = 248
local PILL_H = 48
local ACTION_H = 52
local ARROW_TEX = "Interface\\AddOns\\SocialCentral\\Media\\arrow"

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

local function RotateArrowTexture(tex, angleRad)
    -- Compass arrow removed in favor of Minimap/WorldMap pins and pure distance calculator
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

        if entry.stance ~= "ENEMY" and entry.stance ~= "BLOCKED" then
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
                root:CreateButton(L["Remove Guild Diplomacy"], function()
                    if ns.UI and ns.UI.OpenDiplomacyModal then
                        ns.UI:OpenDiplomacyModal(entry.guild, entry.stance, nil)
                    elseif ns.Clan then
                        ns.Clan:SetGuildStance(entry.guild, "NEUTRAL", "")
                    end
                end)
            else
                local authTxt = (ns.Clan.GetDiplomacyAuthoritySummary and ns.Clan:GetDiplomacyAuthoritySummary()) or L["Guild Leader Only"]
                root:CreateTitle("|cff8b949e" .. L["Diplomacy"] .. ": " .. authTxt .. "|r")
            end
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
    return L["Nearby"]
end

local function ShortestAngleDelta(fromA, toA)
    local diff = (toA - fromA) % (2 * math.pi)
    if diff > math.pi then
        diff = diff - 2 * math.pi
    end
    return diff
end

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

local function ShowHUDPinTooltip(owner, entry)
    if not (GameTooltip and entry) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    local classHex = Compat.ClassHex and Compat.ClassHex(entry.classFile) or "|cffffffff"
    local stanceVal = entry.stance or "SAME"
    local colHex = ns.Spotter and ns.Spotter:GetStanceColor(stanceVal).hex or "|cffffff00"
    local stanceTag = stanceVal == "ENEMY" and L["ENEMY"]
        or (stanceVal == "BLOCKED" and L["BLOCKED"])
        or (stanceVal == "WATCHLIST" and L["WATCHLIST"])
        or (stanceVal == "FRIEND" and L["FRIEND"])
        or (stanceVal == "ALLY" and L["ALLY"] or L["CLAN"])

    local lvlPart = (entry.level and entry.level > 0) and (" (" .. entry.level .. ")") or ""
    local title = string.format("%s[%s]|r %s%s|r%s", colHex, stanceTag, classHex, entry.displayName or "?", lvlPart)
    GameTooltip:AddLine(title, 1, 1, 1)

    if entry.guild and entry.guild ~= "" then
        GameTooltip:AddLine("<" .. entry.guild .. ">", 0.9, 0.82, 0.5)
    end

    local loc = entry.fullLocationText or entry.locationText or entry.zone or ""
    if loc ~= "" then
        GameTooltip:AddLine(L["Location"] .. ": " .. loc, 0.75, 0.85, 0.95)
    end

    if entry.lastDistText and entry.lastDistText ~= "" then
        GameTooltip:AddDoubleLine(L["Distance"], entry.lastDistText, 0.65, 0.72, 0.80, 0.35, 0.85, 0.45)
    end

    if entry.coordsText and entry.coordsText ~= "" then
        GameTooltip:AddDoubleLine(L["Coordinates"], entry.coordsText, 0.65, 0.72, 0.80, 0.95, 0.85, 0.35)
    end

    GameTooltip:AddLine(L["Left-click: Target player"], 0.45, 0.85, 1.0)
    GameTooltip:Show()
end

local reusableSrcVec2D = CreateVector2D and CreateVector2D(0, 0) or nil
local reusableTargetVec2D = CreateVector2D and CreateVector2D(0, 0) or nil
local reusablePinTargets = {}
local reusablePinSeen = {}
local reusablePeerPool = {}
local reusableMinimapCtx = {}
local OUTDOOR_ZOOM_RADII = { [0] = 233, [1] = 200, [2] = 166, [3] = 133, [4] = 100, [5] = 66 }
local DOT_CIRCLE_TEX = "Interface\\AddOns\\SocialCentral\\Media\\dot"

local function ProjectCoordsToMap(srcMapID, srcX, srcY, destMapID)
    if not (srcMapID and srcX and srcY and destMapID) then return nil, nil end
    if srcMapID == destMapID then
        return srcX, srcY
    end
    if C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        local vec = reusableSrcVec2D
        if vec and vec.SetXY then
            vec:SetXY(srcX, srcY)
        else
            vec = CreateVector2D(srcX, srcY)
        end
        local ok1, inst, worldPos = pcall(C_Map.GetWorldPosFromMapPos, srcMapID, vec)
        if ok1 and inst and worldPos then
            local ok2, outMapID, outPos = pcall(C_Map.GetMapPosFromWorldPos, inst, worldPos, destMapID)
            if ok2 and outMapID == destMapID and outPos then
                local px = outPos.GetXY and select(1, outPos:GetXY()) or outPos.x
                local py = outPos.GetXY and select(2, outPos:GetXY()) or outPos.y
                if px and py and px >= 0.005 and px <= 0.995 and py >= 0.005 and py <= 0.995 then
                    return px, py
                end
            end
        end
    end
    return nil, nil
end

local function PrepareMinimapContext()
    local ctx = reusableMinimapCtx
    ctx.valid = false
    if not (Minimap and Minimap:IsShown()) then
        return ctx
    end

    local mapRadius = 100
    if C_Minimap and C_Minimap.GetViewRadius then
        local okR, vr = pcall(C_Minimap.GetViewRadius)
        if okR and vr and vr > 10 then
            mapRadius = vr
        end
    else
        local zoom = Minimap:GetZoom() or 0
        mapRadius = OUTDOOR_ZOOM_RADII[zoom] or 100
    end
    ctx.mapRadius = mapRadius
    ctx.miniW = (Minimap:GetWidth() or 140) / 2
    ctx.miniH = (Minimap:GetHeight() or 140) / 2

    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and CreateVector2D and C_Map.GetWorldPosFromMapPos) then
        return ctx
    end

    local playerMapID = Safe.Number(Safe.Call(C_Map.GetBestMapForUnit, "player"))
    if not playerMapID then return ctx end
    local pPos = Safe.Call(C_Map.GetPlayerMapPosition, playerMapID, "player")
    if not pPos then return ctx end
    local px = pPos.GetXY and select(1, pPos:GetXY()) or pPos.x
    local py = pPos.GetXY and select(2, pPos:GetXY()) or pPos.y
    if not (px and py) then return ctx end

    local pVec = reusableSrcVec2D
    if pVec and pVec.SetXY then
        pVec:SetXY(px, py)
    else
        pVec = CreateVector2D(px, py)
    end
    local ok1, pInst, pWorld = pcall(C_Map.GetWorldPosFromMapPos, playerMapID, pVec)
    if not (ok1 and pInst and pWorld) then
        return ctx
    end

    ctx.pInst = pInst
    ctx.pWorldX = pWorld.x
    ctx.pWorldY = pWorld.y
    ctx.rotate = GetCVar and GetCVar("rotateMinimap") == "1"
    if ctx.rotate and GetPlayerFacing then
        local facing = GetPlayerFacing() or 0
        ctx.sinF = math.sin(facing)
        ctx.cosF = math.cos(facing)
    end
    ctx.valid = true
    return ctx
end

local function ProjectCoordsToMinimapWithContext(ctx, srcMapID, srcX, srcY)
    if not (ctx and ctx.valid and srcMapID and srcX and srcY) then
        return nil, nil, false
    end

    local tVec = reusableTargetVec2D
    if tVec and tVec.SetXY then
        tVec:SetXY(srcX, srcY)
    else
        tVec = CreateVector2D(srcX, srcY)
    end
    local ok2, tInst, tWorld = pcall(C_Map.GetWorldPosFromMapPos, srcMapID, tVec)
    if not (ok2 and tInst and tInst == ctx.pInst and tWorld) then
        return nil, nil, false
    end

    local dNorth = tWorld.x - ctx.pWorldX
    local dWest = tWorld.y - ctx.pWorldY
    local xDist = -dWest  -- yards East (+right)
    local yDist = dNorth  -- yards North (+up)

    if ctx.rotate and ctx.sinF and ctx.cosF then
        local rx = xDist * ctx.cosF - yDist * ctx.sinF
        local ry = xDist * ctx.sinF + yDist * ctx.cosF
        xDist, yDist = rx, ry
    end

    local normX = xDist / ctx.mapRadius
    local normY = yDist / ctx.mapRadius
    local normDistSq = normX * normX + normY * normY
    local maxRatio = 0.88
    local onEdge = false

    if normDistSq > (maxRatio * maxRatio) then
        local normDist = math.sqrt(normDistSq)
        if normDist > 0 then
            normX = (normX / normDist) * maxRatio
            normY = (normY / normDist) * maxRatio
        end
        onEdge = true
    end

    return normX * ctx.miniW, normY * ctx.miniH, onEdge
end

local function AcquireMinimapPin(idx)
    SpotterHUD.minimapPins = SpotterHUD.minimapPins or {}
    local pin = SpotterHUD.minimapPins[idx]
    if pin then return pin end

    pin = CreateFrame("Button", "SocialCentralSpotterMiniPin" .. idx, Minimap, "SecureActionButtonTemplate")
    pin:SetSize(14, 14)
    pin:RegisterForClicks("AnyUp")
    pin:SetAttribute("useOnKeyDown", false)
    pin:SetFrameStrata("MEDIUM")
    pin:SetFrameLevel((Minimap:GetFrameLevel() or 10) + 15)

    local solidBg = pin:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetSize(14, 14)
    solidBg:SetPoint("CENTER")
    solidBg:SetTexture(DOT_CIRCLE_TEX)
    solidBg:SetVertexColor(0.06, 0.08, 0.12, 1.0)
    pin._solidOpaqueBg = solidBg

    local outerRing = pin:CreateTexture(nil, "ARTWORK", nil, 0)
    outerRing:SetSize(14, 14)
    outerRing:SetPoint("CENTER")
    outerRing:SetTexture(DOT_CIRCLE_TEX)
    outerRing:SetVertexColor(0.98, 0.80, 0.24, 1.0)
    pin.outerRing = outerRing

    local icon = pin:CreateTexture(nil, "OVERLAY", nil, 1)
    icon:SetSize(10, 10)
    icon:SetPoint("CENTER")
    icon:SetTexture(RADAR_FALLBACK_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ApplyCircleMask(pin, icon, 10)
    pin.icon = icon

    pin:SetScript("OnEnter", function(selfPin)
        if selfPin.entry then
            ShowHUDPinTooltip(selfPin, selfPin.entry)
        end
    end)
    pin:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    pin:SetScript("PostClick", function(selfPin)
        if selfPin.entry then
            SpotterHUD.focusedKey = selfPin.entry.key
            SpotterHUD:Refresh()
        end
    end)

    SpotterHUD.minimapPins[idx] = pin
    return pin
end

local function AcquireWorldMapPin(canvas, idx)
    SpotterHUD.worldMapPins = SpotterHUD.worldMapPins or {}
    local pin = SpotterHUD.worldMapPins[idx]
    if pin then return pin end

    pin = CreateFrame("Button", "SocialCentralSpotterWorldPin" .. idx, canvas, "SecureActionButtonTemplate")
    pin:SetSize(18, 18)
    pin:RegisterForClicks("AnyUp")
    pin:SetAttribute("useOnKeyDown", false)
    pin:SetFrameLevel(math.max(2050, (canvas:GetFrameLevel() or 2000) + 40))

    local solidBg = pin:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetSize(18, 18)
    solidBg:SetPoint("CENTER")
    solidBg:SetTexture(DOT_CIRCLE_TEX)
    solidBg:SetVertexColor(0.06, 0.08, 0.12, 1.0)
    pin._solidOpaqueBg = solidBg

    local outerRing = pin:CreateTexture(nil, "ARTWORK", nil, 0)
    outerRing:SetSize(18, 18)
    outerRing:SetPoint("CENTER")
    outerRing:SetTexture(DOT_CIRCLE_TEX)
    outerRing:SetVertexColor(0.98, 0.80, 0.24, 1.0)
    pin.outerRing = outerRing

    local icon = pin:CreateTexture(nil, "OVERLAY", nil, 1)
    icon:SetSize(14, 14)
    icon:SetPoint("CENTER")
    icon:SetTexture(RADAR_FALLBACK_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ApplyCircleMask(pin, icon, 14)
    pin.icon = icon

    pin:SetScript("OnEnter", function(selfPin)
        if selfPin.entry then
            ShowHUDPinTooltip(selfPin, selfPin.entry)
        end
    end)
    pin:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    pin:SetScript("PostClick", function(selfPin)
        if selfPin.entry then
            SpotterHUD.focusedKey = selfPin.entry.key
            SpotterHUD:Refresh()
        end
    end)

    SpotterHUD.worldMapPins[idx] = pin
    return pin
end

local function GetPlottableTargets()
    wipe(reusablePinTargets)
    wipe(reusablePinSeen)

    if ns.Spotter and ns.Spotter.GetActiveTargets then
        local spotterTargets = ns.Spotter:GetActiveTargets("ALL")
        if spotterTargets then
            for i = 1, #spotterTargets do
                local entry = spotterTargets[i]
                if entry and entry.key and not reusablePinSeen[entry.key] then
                    reusablePinSeen[entry.key] = true
                    reusablePinTargets[#reusablePinTargets + 1] = entry
                end
            end
        end
    end

    if ns.Spotter and ns.Spotter.peerPositions then
        local now = GetTime()
        for senderName, p in pairs(ns.Spotter.peerPositions) do
            if p and p.mapID and p.x and p.y and (now - (p.at or 0)) < 150 then
                if not reusablePinSeen[senderName] then
                    reusablePinSeen[senderName] = true
                    local stance = "SAME"
                    if ns.Watchlist and ns.Watchlist.IsOnWatchlist and ns.Watchlist:IsOnWatchlist(senderName) then
                        stance = "WATCHLIST"
                    elseif ns.Compat and ns.Compat.IsFriend and ns.Compat.IsFriend(senderName) then
                        stance = "FRIEND"
                    end
                    local entry = reusablePeerPool[senderName]
                    if not entry then
                        entry = {
                            key = senderName,
                            displayName = senderName,
                            unitName = senderName,
                            isPeer = true,
                        }
                        reusablePeerPool[senderName] = entry
                    end
                    entry.stance = stance
                    entry.classFile = p.classFile
                    entry.level = p.level
                    if entry._anchorMapX ~= p.x or entry._anchorMapY ~= p.y then
                        entry._anchorMapX = p.x
                        entry._anchorMapY = p.y
                        entry.coordsText = string.format("%.1f, %.1f", p.x * 100, p.y * 100)
                    end
                    entry._anchorMapID = p.mapID
                    reusablePinTargets[#reusablePinTargets + 1] = entry
                end
            end
        end
    end

    return reusablePinTargets
end

local function CreateRadarBadgeBox(parentFrame, leftOffset)
    local badgeBox = CreateFrame("Frame", nil, parentFrame)
    badgeBox:SetSize(36, 36)
    badgeBox:SetPoint("LEFT", leftOffset or 4, 0)
    badgeBox:EnableMouse(false)
    if badgeBox.SetClipsChildren then
        badgeBox:SetClipsChildren(false)
    end

    -- Soft radial bloom aura behind stance ring
    local badgeGlow = badgeBox:CreateTexture(nil, "BACKGROUND", nil, 1)
    badgeGlow:SetSize(48, 48)
    badgeGlow:SetPoint("CENTER")
    badgeGlow:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\toast-glow")
    badgeGlow:SetVertexColor(0.98, 0.80, 0.24, 0.38)
    badgeBox.badgeGlow = badgeGlow

    -- Thin stance-colored outer circular border
    local outerRing = badgeBox:CreateTexture(nil, "ARTWORK", nil, 0)
    outerRing:SetSize(34, 34)
    outerRing:SetPoint("CENTER")
    outerRing:SetTexture(WHITE8X8)
    outerRing:SetVertexColor(0.98, 0.80, 0.24, 0.90)
    ApplyCircleMask(badgeBox, outerRing, 34)
    badgeBox.outerRing = outerRing

    local aura = badgeBox:CreateTexture(nil, "ARTWORK", nil, 1)
    aura:SetSize(30, 30)
    aura:SetPoint("CENTER")
    aura:SetTexture(WHITE8X8)
    aura:SetVertexColor(0.08, 0.11, 0.16, 0.96)
    ApplyCircleMask(badgeBox, aura, 30)
    badgeBox.aura = aura

    local arrowTex = badgeBox:CreateTexture(nil, "OVERLAY", nil, 2)
    arrowTex:SetSize(28, 28)
    arrowTex:SetPoint("CENTER")
    arrowTex:Hide()
    badgeBox.arrowTex = arrowTex

    local noSignalDot = badgeBox:CreateTexture(nil, "OVERLAY", nil, 1)
    noSignalDot:SetSize(26, 26)
    noSignalDot:SetPoint("CENTER")
    noSignalDot:SetTexture(RADAR_FALLBACK_ICON)
    noSignalDot:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ApplyCircleMask(badgeBox, noSignalDot, 26)
    noSignalDot:Show()
    badgeBox.noSignalDot = noSignalDot

    local noSignalBlip = badgeBox:CreateTexture(nil, "OVERLAY", nil, 3)
    noSignalBlip:SetSize(10, 10)
    noSignalBlip:SetPoint("BOTTOMRIGHT", badgeBox, "BOTTOMRIGHT", -1, 1)
    noSignalBlip:SetTexture(WHITE8X8)
    noSignalBlip:SetVertexColor(0.98, 0.80, 0.24, 1.0)
    ApplyCircleMask(badgeBox, noSignalBlip, 10)
    noSignalBlip:Show()
    badgeBox.noSignalBlip = noSignalBlip

    parentFrame.arrowBox = badgeBox
    parentFrame.arrowTex = arrowTex
    parentFrame.noSignalDot = noSignalDot
    parentFrame.noSignalBlip = noSignalBlip
    return badgeBox
end
local CreateRadarArrowBox = CreateRadarBadgeBox

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

    local topBevel = f:CreateTexture(nil, "BORDER", nil, 1)
    topBevel:SetHeight(1)
    topBevel:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -3)
    topBevel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -3)
    topBevel:SetColorTexture(1, 0.90, 0.65, 0.16)
    f._topBevel = topBevel

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

    local arrowBox = CreateRadarArrowBox(compassBar, 4)

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
            local tipFooter = L["Left-click: Target player  |  Right-click: Actions"]
            ShowHUDTooltip(
                selfBtn,
                e.displayName or "?",
                l1,
                tipFooter
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
    local drawerSep = actionPanel:CreateTexture(nil, "ARTWORK", nil, 1)
    drawerSep:SetHeight(1)
    drawerSep:SetPoint("TOPLEFT", actionPanel, "TOPLEFT", 6, 0)
    drawerSep:SetPoint("TOPRIGHT", actionPanel, "TOPRIGHT", -6, 0)
    drawerSep:SetColorTexture(0.68, 0.56, 0.28, 0.35)
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
            if ns.Clan and ns.Clan.CanManageDiplomacy and not ns.Clan:CanManageDiplomacy() then
                local authTxt = (ns.Clan.GetDiplomacyAuthoritySummary and ns.Clan:GetDiplomacyAuthoritySummary()) or L["Guild Leader Only"]
                ns:Print(L["Only guild leaders (%s) can define Allied or Enemy guilds."]:format(authTxt))
            elseif ns.UI and ns.UI.OpenDiplomacyModal and e.guild and e.guild ~= "" then
                ns.UI:OpenDiplomacyModal(e.guild, e.stance, nil)
            end
        elseif e.stance == "BLOCKED" then
            if ns.Spotter and ns.Spotter.DismissTarget then
                ns.Spotter:DismissTarget(e.key)
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

    f:HookScript("OnHide", function()
        SpotterHUD:SyncTickerState(nil)
    end)

    self.frame = f
    self:BuildCombatArrowFrame()
    self:UpdateAppearance()
    f:Hide()
    return f
end

function SpotterHUD:SyncTickerState(kin)
    local interval = 0.5
    self._tickerInterval = interval

    if not self._mainOnUpdateFn then
        self._mainOnUpdateFn = function(_, elapsed)
            local stepInterval = SpotterHUD._tickerInterval or 0.5
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
            local stepInterval = SpotterHUD._tickerInterval or 0.5
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
        local mainActive = f:IsShown() and self._compassEntry ~= nil
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
        local combatActive = cf:IsShown() and self._compassEntry ~= nil
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
    cf:SetPoint("TOP", UIParent, "TOP", 0, -96)
    cf:SetFrameStrata("MEDIUM")
    cf:SetFrameLevel(45)

    local stanceBar = cf:CreateTexture(nil, "OVERLAY")
    stanceBar:SetWidth(3)
    stanceBar:SetPoint("TOPLEFT", cf, "TOPLEFT", 2, -2)
    stanceBar:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 2, 2)
    stanceBar:SetColorTexture(0.98, 0.80, 0.24, 1)
    cf.stanceBar = stanceBar

    local arrowBox = CreateRadarArrowBox(cf, 8)

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

    cf:HookScript("OnHide", function()
        SpotterHUD:SyncTickerState(nil)
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
    cf.nameFs:SetText(string.format("%s[%s]|r %s%s|r", colHex, stanceTag, classHex, entry.displayName or "?"))
    cf.subFs:SetText(entry.locationText or (entry.guild and ("<" .. entry.guild .. ">") or ""))
    cf:Show()
    self:UpdateCompassVisuals(true, 0.04)
end

local function ApplyPromptDialogTheme(dlg, p)
    if not dlg then return end
    Theme:ApplyBackdrop(dlg, "window", p)
    dlg.titleFs:SetTextColor(p.accent[1], p.accent[2], p.accent[3])
    dlg.bodyFs:SetTextColor(p.text[1], p.text[2], p.text[3])
    dlg.tipFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
    Theme:StyleButton(dlg.closeBtn, "default")
    Theme:StyleButton(dlg.keepBtn, "primary")
    Theme:StyleButton(dlg.disableBtn, "danger")
    dlg._dirtyTheme = nil
end

local function ApplyActionPanelTheme(actionPanel, p)
    if not actionPanel then return end
    Theme:ApplyBackdrop(actionPanel, "inset", p)
    actionPanel.promptFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3])
    Theme:StyleButton(actionPanel.whisperBtn, "primary")
    Theme:StyleButton(actionPanel.tellBtn, "default")
    Theme:StyleButton(actionPanel.inviteBtn, "default")
    Theme:StyleButton(actionPanel.watchBtn, "default")
    actionPanel._dirtyTheme = nil
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

    if self.promptDialog then
        if self.promptDialog:IsShown() then
            ApplyPromptDialogTheme(self.promptDialog, p)
        else
            self.promptDialog._dirtyTheme = true
        end
    end

    local f = self.frame
    if not f then return end

    if f._dirtyTheme then
        f._dirtyTheme = nil
    end
    Theme:ApplyBackdrop(f, "window", p)
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

    Theme:StyleButton(f.closeBtn, "danger")
    Theme:StyleButton(f.cycleBtn, "default")
    self:Refresh()
end

local function ResetCompassBarDirtyState(bar)
    if not bar then return end
    bar._visHasAngle = nil
    bar._visAngle = nil
    bar._visDead = nil
    bar._visClassFile = nil
    bar._visBlipDead = nil
    bar._visBlipStance = nil
    bar._visTintDead = nil
    bar._visTintHasAngle = nil
    bar._visTintAhead = nil
    bar._visTintStance = nil
    bar._visDistText = nil
    bar._visBearing = nil
    bar._visSubZone = nil
    bar._visDistDead = nil
end

local function ApplyCompassBarVisuals(bar, entry, kin)
    if not bar then return end

    local stanceVal = entry.stance or "SAME"
    local isDead = entry.dead == true
    local rgb = STANCE_RGB[stanceVal] or STANCE_RGB.SAME

    if bar.arrowTex then
        bar.arrowTex:Hide()
    end
    if bar.noSignalDot then
        bar.noSignalDot:Show()
    end
    if bar.noSignalBlip then
        bar.noSignalBlip:Show()
    end

    local classFileVal = entry.classFile or false
    if (bar._visDead ~= isDead or bar._visClassFile ~= classFileVal) and bar.noSignalDot then
        bar._visDead = isDead
        bar._visClassFile = classFileVal
        local coords = classFileVal and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFileVal]
        if coords then
            bar.noSignalDot:SetTexture(CLASS_SPRITE_TEX)
            bar.noSignalDot:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
            if isDead then
                bar.noSignalDot:SetVertexColor(0.55, 0.55, 0.55, 0.70)
            else
                bar.noSignalDot:SetVertexColor(1, 1, 1, 1)
            end
        else
            bar.noSignalDot:SetTexture(RADAR_FALLBACK_ICON)
            bar.noSignalDot:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if isDead then
                bar.noSignalDot:SetVertexColor(0.55, 0.55, 0.55, 0.70)
            else
                bar.noSignalDot:SetVertexColor(1, 1, 1, 0.95)
            end
        end
    end

    if bar.noSignalBlip and (bar._visBlipDead ~= isDead or bar._visBlipStance ~= stanceVal) then
        bar._visBlipDead = isDead
        bar._visBlipStance = stanceVal
        if isDead then
            bar.noSignalBlip:SetVertexColor(0.50, 0.50, 0.50, 0.70)
        else
            bar.noSignalBlip:SetVertexColor(rgb[1], rgb[2], rgb[3], 1.0)
        end
    end

    if bar._visTintDead ~= isDead or bar._visTintStance ~= stanceVal then
        bar._visTintDead = isDead
        bar._visTintStance = stanceVal
        if isDead then
            if bar.arrowBox and bar.arrowBox.outerRing then
                bar.arrowBox.outerRing:SetVertexColor(0.45, 0.45, 0.45, 0.75)
            end
            if bar.arrowBox and bar.arrowBox.badgeGlow then
                bar.arrowBox.badgeGlow:SetVertexColor(0.45, 0.45, 0.45, 0.16)
            end
            if bar.arrowBox and bar.arrowBox.aura then
                bar.arrowBox.aura:SetVertexColor(0.08, 0.09, 0.12, 0.95)
            end
        else
            if bar.arrowBox and bar.arrowBox.outerRing then
                bar.arrowBox.outerRing:SetVertexColor(rgb[1], rgb[2], rgb[3], 0.95)
            end
            if bar.arrowBox and bar.arrowBox.badgeGlow then
                bar.arrowBox.badgeGlow:SetVertexColor(rgb[1], rgb[2], rgb[3], 0.42)
            end
            if bar.arrowBox and bar.arrowBox.aura then
                bar.arrowBox.aura:SetVertexColor(0.07, 0.09, 0.14, 0.96)
            end
        end
    end

    -- Pure Distance Calculator (Color coded by proximity)
    local distNum = (kin and kin.distYards) or entry.lastDistYards
    local distStr
    if isDead then
        distStr = "|cff888888" .. L["Dead"] .. "|r"
    elseif distNum and type(distNum) == "number" and distNum > 0 then
        if distNum <= 10 then
            distStr = string.format("|cff4ade80~%dm|r", distNum)
        elseif distNum <= 25 then
            distStr = string.format("|cff86efac%dm|r", distNum)
        elseif distNum <= 40 then
            distStr = string.format("|cfffde047%dm|r", distNum)
        elseif distNum <= 60 then
            distStr = string.format("|cfffb923c%dm|r", distNum)
        else
            distStr = string.format("|cff94a3b8>%dm|r", distNum)
        end
    else
        local rawText = (kin and kin.distText) or entry.lastDistText or L["Nearby"]
        distStr = "|cff58d8ff" .. rawText .. "|r"
    end

    local zoneShort = (entry.subZone and entry.subZone ~= "") and entry.subZone or ""
    local locPart = (zoneShort ~= "") and (" |cff8b949e· " .. zoneShort .. "|r") or ""
    local coordsPart = entry.coordsText and (" |cff64748b(" .. entry.coordsText .. ")|r") or ""
    local distOut = distStr .. locPart .. coordsPart

    if bar._visDistOut ~= distOut then
        bar._visDistOut = distOut
        bar.distFs:SetText(distOut)
    end
end

function SpotterHUD:UpdateMapPins()
    local s = ns.db and ns.db.settings
    local enabled = not s or s.spotterMapPins ~= false
    if not enabled then
        if self.minimapPins then
            for i = 1, #self.minimapPins do self.minimapPins[i]:Hide() end
        end
        if self.worldMapPins then
            for i = 1, #self.worldMapPins do self.worldMapPins[i]:Hide() end
        end
        return
    end

    local miniShown = Minimap and Minimap:IsShown()
    local worldShown = _G.WorldMapFrame and _G.WorldMapFrame.IsShown and _G.WorldMapFrame:IsShown()
    if not (miniShown or worldShown) then
        if self.minimapPins then
            for i = 1, #self.minimapPins do self.minimapPins[i]:Hide() end
        end
        if self.worldMapPins then
            for i = 1, #self.worldMapPins do self.worldMapPins[i]:Hide() end
        end
        return
    end

    local targets = GetPlottableTargets()
    if miniShown then
        self:UpdateMinimapPinsInternal(targets)
    elseif self.minimapPins then
        for i = 1, #self.minimapPins do self.minimapPins[i]:Hide() end
    end
    if worldShown then
        self:UpdateWorldMapPinsInternal(targets)
    elseif self.worldMapPins then
        for i = 1, #self.worldMapPins do self.worldMapPins[i]:Hide() end
    end
end

function SpotterHUD:UpdateMinimapPinsInternal(targets)
    local miniIdx = 0
    local inCombat = InCombatLockdown and InCombatLockdown()
    local ctx = PrepareMinimapContext()

    if ctx.valid then
        for i = 1, #targets do
            local entry = targets[i]
            local mapID = entry._anchorMapID
            local mx = entry._anchorMapX
            local my = entry._anchorMapY

            local offX, offY, onEdge
            if mapID and mx and my then
                offX, offY, onEdge = ProjectCoordsToMinimapWithContext(ctx, mapID, mx, my)
            elseif entry._kinematics and entry._kinematics.distYards and entry._kinematics.angle then
                local distY = entry._kinematics.distYards
                local a = entry._kinematics.angle
                local xYards = -math.sin(a) * distY
                local yYards = math.cos(a) * distY
                local nX = xYards / ctx.mapRadius
                local nY = yYards / ctx.mapRadius
                local dSq = nX * nX + nY * nY
                local maxR = 0.88
                if dSq > (maxR * maxR) then
                    local d = math.sqrt(dSq)
                    if d > 0 then nX = (nX / d) * maxR; nY = (nY / d) * maxR end
                    onEdge = true
                end
                offX, offY = nX * ctx.miniW, nY * ctx.miniH
            end

            if offX and offY then
                miniIdx = miniIdx + 1
                local pin = AcquireMinimapPin(miniIdx)
                local roundedX = math.floor(offX * 2 + 0.5) * 0.5
                local roundedY = math.floor(offY * 2 + 0.5) * 0.5
                if pin._lastOffX ~= roundedX or pin._lastOffY ~= roundedY then
                    pin._lastOffX = roundedX
                    pin._lastOffY = roundedY
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", Minimap, "CENTER", roundedX, roundedY)
                end
                pin.entry = entry

                local stanceVal = entry.stance or "SAME"
                if pin._lastStance ~= stanceVal or pin._lastOnEdge ~= onEdge then
                    pin._lastStance = stanceVal
                    pin._lastOnEdge = onEdge
                    local rgb = STANCE_RGB[stanceVal] or STANCE_RGB.SAME
                    if pin.outerRing then
                        pin.outerRing:SetVertexColor(rgb[1], rgb[2], rgb[3], onEdge and 0.75 or 1.0)
                    end
                end

                local classFileVal = entry.classFile or "NONE"
                if pin._lastClassFile ~= classFileVal then
                    pin._lastClassFile = classFileVal
                    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFileVal]
                    if coords then
                        pin.icon:SetTexture(CLASS_SPRITE_TEX)
                        pin.icon:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
                    else
                        pin.icon:SetTexture(RADAR_FALLBACK_ICON)
                        pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    end
                end

                if not inCombat then
                    local curUnit = entry.unit or ""
                    local curDisp = entry.displayName or ""
                    if pin._lastMacroKey ~= entry.key or pin._lastMacroUnit ~= curUnit or pin._lastMacroDisp ~= curDisp then
                        pin._lastMacroKey = entry.key
                        pin._lastMacroUnit = curUnit
                        pin._lastMacroDisp = curDisp
                        ApplySecureMacroAttributes(pin, entry, entry.unit)
                    end
                end
                pin:Show()
            end
        end
    end

    if self.minimapPins then
        for i = miniIdx + 1, #self.minimapPins do
            self.minimapPins[i]:Hide()
        end
    end
end

function SpotterHUD:UpdateWorldMapPinsInternal(targets)
    local mapFrame = _G.WorldMapFrame
    if not (mapFrame and mapFrame.IsShown and mapFrame:IsShown()) then
        if self.worldMapPins then
            for i = 1, #self.worldMapPins do self.worldMapPins[i]:Hide() end
        end
        return
    end

    local canvas = mapFrame.GetCanvas and mapFrame:GetCanvas()
    local currentMapID = mapFrame.GetMapID and mapFrame:GetMapID()
    if not (canvas and currentMapID) then return end

    local cw, ch = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    if cw < 40 or ch < 40 then return end

    local inCombat = InCombatLockdown and InCombatLockdown()
    local worldIdx = 0

    for i = 1, #targets do
        local entry = targets[i]
        local mapID = entry._anchorMapID
        local mx = entry._anchorMapX
        local my = entry._anchorMapY
        if mapID and mx and my then
            local px, py = ProjectCoordsToMap(mapID, mx, my, currentMapID)
            if px and py then
                worldIdx = worldIdx + 1
                local pin = AcquireWorldMapPin(canvas, worldIdx)
                if pin:GetParent() ~= canvas then
                    pin:SetParent(canvas)
                    pin._lastOffX = nil
                end
                local offX = math.floor(px * cw * 2 + 0.5) * 0.5
                local offY = math.floor(-py * ch * 2 + 0.5) * 0.5
                if pin._lastOffX ~= offX or pin._lastOffY ~= offY then
                    pin._lastOffX = offX
                    pin._lastOffY = offY
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", canvas, "TOPLEFT", offX, offY)
                end
                pin.entry = entry

                local stanceVal = entry.stance or "SAME"
                if pin._lastStance ~= stanceVal then
                    pin._lastStance = stanceVal
                    local rgb = STANCE_RGB[stanceVal] or STANCE_RGB.SAME
                    if pin.outerRing then
                        pin.outerRing:SetVertexColor(rgb[1], rgb[2], rgb[3], 1.0)
                    end
                end

                local classFileVal = entry.classFile or "NONE"
                if pin._lastClassFile ~= classFileVal then
                    pin._lastClassFile = classFileVal
                    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFileVal]
                    if coords then
                        pin.icon:SetTexture(CLASS_SPRITE_TEX)
                        pin.icon:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
                    else
                        pin.icon:SetTexture(RADAR_FALLBACK_ICON)
                        pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    end
                end

                if not inCombat then
                    local curUnit = entry.unit or ""
                    local curDisp = entry.displayName or ""
                    if pin._lastMacroKey ~= entry.key or pin._lastMacroUnit ~= curUnit or pin._lastMacroDisp ~= curDisp then
                        pin._lastMacroKey = entry.key
                        pin._lastMacroUnit = curUnit
                        pin._lastMacroDisp = curDisp
                        ApplySecureMacroAttributes(pin, entry, entry.unit)
                    end
                end
                pin:Show()
            end
        end
    end

    if self.worldMapPins then
        for i = worldIdx + 1, #self.worldMapPins do
            self.worldMapPins[i]:Hide()
        end
    end
end

function SpotterHUD:UpdateCompassVisuals(snap, dt)
    local f = self.frame
    local cf = self.combatArrowFrame
    local mainCompassActive = f and f:IsShown() and f.compassBar and f.compassBar:IsShown()
    local combatCompassActive = cf and cf:IsShown()

    local now = GetTime and GetTime() or 0
    if snap or not self._lastMapPinsAt or (now - self._lastMapPinsAt) >= 1.5 then
        self._lastMapPinsAt = now
        self:UpdateMapPins()
    end

    if not (mainCompassActive or combatCompassActive) then
        self:SyncTickerState(nil)
        return
    end

    local entry = self._compassEntry
    if not (entry and ns.Spotter and ns.Spotter.GetTargetKinematics) then
        self:SyncTickerState(nil)
        return
    end

    local kin = ns.Spotter:GetTargetKinematics(entry)
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

function SpotterHUD:UpdateTargetVisuals()
    local f = self.frame
    if not (f and f:IsShown() and f.compassBar) then return end

    local spotter = ns.Spotter
    local entriesMap = spotter and spotter.entries
    local prevKey = self._compassEntry and self._compassEntry.key
    local entry = self._compassEntry
    if entry and entriesMap and entriesMap[entry.key] then
        entry = entriesMap[entry.key]
    else
        local allTargets = spotter and spotter:GetActiveTargets("ALL") or {}
        entry = allTargets[1]
        self._compassEntry = entry
    end
    if not entry then return end

    local currentTargetGuid, tLookupKey, tFirstName, tSurname = ReadCurrentTargetIdentity()
    local isTargeted = IsEntryCurrentlyTargeted(entry, currentTargetGuid, tLookupKey, tFirstName, tSurname)

    if f.compassBar._isTargetedBackdrop ~= isTargeted then
        f.compassBar._isTargetedBackdrop = isTargeted
        local p = Theme:GetPalette()
        if isTargeted then
            Theme:ApplyBackdrop(f.compassBar, "primary", p)
        elseif f.compassBar.SetBackdrop then
            f.compassBar:SetBackdrop(nil)
        end
    end
    local entryChanged = (prevKey ~= entry.key)
    self:UpdateCompassVisuals(entryChanged, 0.04)
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

    local showCycle = (totalCount > 1 and f.cycleBtn ~= nil)
    if showCycle then
        if f._lastCycleIdx ~= activeIdx or f._lastCycleTotal ~= totalCount then
            f._lastCycleIdx = activeIdx
            f._lastCycleTotal = totalCount
            Theme:SetButtonText(f.cycleBtn, string.format("%d/%d", activeIdx, totalCount))
        end
        if f._lastCycleShown ~= true then
            f._lastCycleShown = true
            f.cycleBtn:Show()
            f.compassBar.nameFs:SetPoint("TOPRIGHT", f.compassBar, "TOPRIGHT", -54, -3)
        end
    else
        if f._lastCycleShown ~= false then
            f._lastCycleShown = false
            if f.cycleBtn then f.cycleBtn:Hide() end
            f.compassBar.nameFs:SetPoint("TOPRIGHT", f.compassBar, "TOPRIGHT", -22, -3)
        end
    end

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
        f.compassBar._isTargetedBackdrop = false
        if f.compassBar.SetBackdrop then
            f.compassBar:SetBackdrop(nil)
        end
        self._lastCompassEntryKey = nil
        f.compassBar.entry = nil
        if f.compassBar.arrowTex then
            f.compassBar.arrowTex:Hide()
        end
        if f.compassBar.arrowBox and f.compassBar.arrowBox.outerRing then
            f.compassBar.arrowBox.outerRing:SetVertexColor(p.accent[1], p.accent[2], p.accent[3], 0.70)
        end
        if f.compassBar.noSignalBlip then
            f.compassBar.noSignalBlip:Hide()
        end
        if f.compassBar.noSignalDot then
            f.compassBar.noSignalDot:SetTexture(RADAR_FALLBACK_ICON)
            f.compassBar.noSignalDot:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            f.compassBar.noSignalDot:SetVertexColor(0.85, 0.90, 0.96, 0.85)
            f.compassBar.noSignalDot:Show()
        end
        ResetCompassBarDirtyState(f.compassBar)
        f.compassBar.nameFs:SetText(L["Target Radar"])
        f._lastStanceBar = nil
        f._lastNameStance = nil
        f._lastNameText = nil
        f._lastNameClass = nil
        f._lastNameLvl = nil
        f.compassBar.distFs:SetText("|cff8b949e" .. L["No targets currently detected."] .. "|r")
        f._lastActionOpen = false
        f.actionPanel:Hide()
        f:SetHeight(PILL_H)
        self:SyncTickerState(nil)
        return
    end

    local stanceVal = compassEntry.stance or "SAME"
    local rgb = STANCE_RGB[stanceVal] or STANCE_RGB.SAME
    if f.stanceBar and f._lastStanceBar ~= stanceVal then
        f._lastStanceBar = stanceVal
        f.stanceBar:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    end

    f.compassBar.entry = compassEntry

    local dispName = compassEntry.displayName or "?"
    local classVal = compassEntry.classFile or false
    local lvlVal = (compassEntry.level and compassEntry.level > 0) and compassEntry.level or 0
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
        local colHex = ns.Spotter:GetStanceColor(stanceVal).hex
        local classHex = Compat.ClassHex and Compat.ClassHex(compassEntry.classFile) or "|cffffffff"
        local lvlPart = (lvlVal > 0) and (" |cff8b949e" .. lvlVal .. "|r") or ""
        f.compassBar.nameFs:SetText(string.format("%s[%s]|r %s%s|r%s", colHex, stanceTag, classHex, dispName, lvlPart))
    end

    local isActuallyTargeted = IsEntryCurrentlyTargeted(compassEntry, currentTargetGuid, tLookupKey, tFirstName, tSurname)
    if f.compassBar._isTargetedBackdrop ~= isActuallyTargeted then
        f.compassBar._isTargetedBackdrop = isActuallyTargeted
        if isActuallyTargeted then
            Theme:ApplyBackdrop(f.compassBar, "primary", p)
        elseif f.compassBar.SetBackdrop then
            f.compassBar:SetBackdrop(nil)
        end
    end

    self:UpdateCompassVisuals(true, 0.04)

    -- Show or hide the On-Click Interaction Drawer below the Arrow Pill
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
        local layoutKey = (stanceVal == "ENEMY" and "ENEMY") or (stanceVal == "BLOCKED" and "BLOCKED") or "DEFAULT"
        if f.actionPanel._lastLayoutStance ~= layoutKey then
            f.actionPanel._lastLayoutStance = layoutKey
            if layoutKey == "ENEMY" then
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
            elseif layoutKey == "BLOCKED" then
                if f.actionPanel.whisperBtn then f.actionPanel.whisperBtn:Hide() end
                if f.actionPanel.tellBtn then f.actionPanel.tellBtn:Hide() end
                if f.actionPanel.scoutBtn then f.actionPanel.scoutBtn:Hide() end
                Theme:SetButtonText(f.actionPanel.inviteBtn, L["Dismiss Target"])
                f.actionPanel.inviteBtn:SetWidth(108)
                f.actionPanel.inviteBtn:ClearAllPoints()
                f.actionPanel.inviteBtn:SetPoint("BOTTOMLEFT", 5, 4)
                if f.actionPanel.watchBtn then
                    f.actionPanel.watchBtn:SetWidth(108)
                    f.actionPanel.watchBtn:ClearAllPoints()
                    f.actionPanel.watchBtn:SetPoint("LEFT", f.actionPanel.inviteBtn, "RIGHT", 4, 0)
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
        end
        if f._lastActionOpen ~= true then
            f._lastActionOpen = true
            f.actionPanel:Show()
            f:SetHeight(PILL_H + 2 + ACTION_H + 3)
        end
    else
        if f._lastActionOpen ~= false then
            f._lastActionOpen = false
            f.actionPanel:Hide()
            f:SetHeight(PILL_H)
        end
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
    if not (ns.Spotter and ns.Spotter.IsEnabled and ns.Spotter:IsEnabled()) then
        return
    end
    local dlg = self.promptDialog or self:CreatePromptDialog()
    if dlg then
        if dlg._dirtyTheme then
            ApplyPromptDialogTheme(dlg, Theme:GetPalette())
        end
        dlg:Show()
    end
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
    if not self.frame then
        self:SyncTickerState(nil)
        return
    end
    self.manualPinnedEmpty = false
    self.interactionOpen = false
    self.interactionKey = nil
    self.frame._lastActionOpen = false
    if InCombatLockdown and InCombatLockdown() then
        self.pendingAction = "hide"
        self:SyncTickerState(nil)
        return
    end
    self.frame:Hide()
    self:SyncTickerState(nil)
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
            else
                SpotterHUD:UpdateMapPins()
            end
        end)
        ns:On("SPOTTER_ALERT", function(alert)
            SpotterHUD:OnAlert(alert)
        end)
        ns:On("SPOTTER_PEER_POSITIONS_UPDATED", function()
            SpotterHUD:UpdateMapPins()
        end)
        ns:On("SETTINGS_UPDATED", function()
            if not (ns.Spotter and ns.Spotter.IsEnabled and ns.Spotter:IsEnabled()) then
                SpotterHUD:Hide()
            elseif SpotterHUD.frame then
                SpotterHUD:UpdateAppearance()
            end
            SpotterHUD:UpdateMapPins()
        end)
        if Theme and Theme.RegisterListener then
            Theme:RegisterListener(function()
                if SpotterHUD.frame then
                    SpotterHUD:UpdateAppearance()
                end
            end)
        end

        if _G.WorldMapFrame and _G.WorldMapFrame.HookScript then
            _G.WorldMapFrame:HookScript("OnShow", function()
                SpotterHUD:UpdateMapPins()
            end)
        end

        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(1.5, function()
                local s = ns.db and ns.db.settings
                if s and s.spotterMapPins == false then return end
                if (_G.WorldMapFrame and _G.WorldMapFrame:IsShown()) or (Minimap and Minimap:IsShown()) then
                    SpotterHUD:UpdateMapPins()
                end
            end)
        end
    end
end

ns.SpotterHUD = SpotterHUD
table.insert(ns.modules, SpotterHUD)
