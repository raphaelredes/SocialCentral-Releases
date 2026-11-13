local _, ns = ...

local Compat = ns.Compat
local Safe = ns.Safe
local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })

local Spotter = {
    name = "Spotter",
    entries = {},        -- [key] = entry
    visibleUnits = {},   -- [unitToken] = key
    alertCooldowns = {}, -- [key] = timestamp
    lastAlert = nil,
    lastScopeToken = nil,
    plateBadges = setmetatable({}, { __mode = "k" }), -- [plateFrame] = badgeFrame
    _pruneElapsed = 0,
}

local MAX_TARGETS = 24
local RETENTION_SECONDS = 12
local PRUNE_INTERVAL = 0.5
local ENEMY_ALERT_COOLDOWN = 60
local FRIENDLY_ALERT_COOLDOWN = 90

local STANCE_PRIORITY = {
    ENEMY = 1,
    ALLY = 2,
    SAME = 3,
}

local STANCE_COLORS = {
    ENEMY = { r = 0.96, g = 0.28, b = 0.28, hex = "|cfff54747" },
    ALLY  = { r = 0.25, g = 0.85, b = 0.45, hex = "|cff40d973" },
    SAME  = { r = 0.98, g = 0.80, b = 0.24, hex = "|cfffacc3d" },
}

local function NormalizeKeyPart(value)
    local s = Safe.String(value)
    if not s or s == "" then return "" end
    s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s:lower()
end

local function SanitizeMacroTargetName(rawName, rawRealm)
    local clean = Safe.String(rawName)
    if not clean or clean == "" then return nil end
    clean = clean:gsub("[%c%|%/%\\%[%]%;]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if clean == "" then return nil end

    local realm = Safe.String(rawRealm)
    if realm and realm ~= "" and not Compat.IsForeverShardLabel(realm) then
        local cleanRealm = realm:gsub("[%c%|%/%\\%[%]%;%s]", "")
        if cleanRealm ~= "" and not clean:find("-", 1, true) then
            local myRealm = Compat.Realm and Compat.Realm() or ""
            if cleanRealm:lower() ~= myRealm:lower() then
                clean = clean .. "-" .. cleanRealm
            end
        end
    end

    if #clean > 48 then
        clean = clean:sub(1, 48)
    end
    return clean
end

local function GetUnitSafeGuild(unit)
    if not GetGuildInfo then return nil, nil, nil end
    local ok, gName, gRank, _, gRealm = pcall(GetGuildInfo, unit)
    if not ok then return nil, nil, nil end
    local cleanGuild = Safe.String(gName)
    if not cleanGuild or cleanGuild == "" then
        return nil, nil, nil
    end
    local cleanRank = Safe.String(gRank)
    local cleanRealm = Safe.String(gRealm)
    if cleanRealm and Compat.IsForeverShardLabel(cleanRealm) then
        cleanRealm = nil
    end
    return cleanGuild, cleanRank, cleanRealm
end

local function GetPlayerNormalizedGuild()
    local gName = GetUnitSafeGuild("player")
    if not gName then return nil, nil end
    return NormalizeKeyPart(gName), gName
end

local function RecomputeOnScreenFlags()
    local counts = {}
    for _, key in pairs(Spotter.visibleUnits) do
        counts[key] = (counts[key] or 0) + 1
    end
    for key, entry in pairs(Spotter.entries) do
        local c = counts[key] or 0
        entry.onScreen = c > 0
        entry.onScreenCount = c
    end
end

local function IsPlateAccessible(plate)
    if not plate then return false end
    if plate.IsForbidden then
        local ok, forbidden = pcall(plate.IsForbidden, plate)
        if not ok or forbidden then
            return false
        end
    end
    return true
end

local function EnsurePlateBadge(plate)
    local badge = Spotter.plateBadges[plate]
    if badge then return badge end

    local f = CreateFrame("Frame", nil, plate)
    f:SetSize(130, 16)
    f:SetPoint("BOTTOM", plate, "TOP", 0, 2)
    f:EnableMouse(false)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.82)
    f.bg = bg

    local bar = f:CreateTexture(nil, "BORDER")
    bar:SetSize(3, 16)
    bar:SetPoint("LEFT")
    f.bar = bar

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("CENTER", 2, 0)
    lbl:SetJustifyH("CENTER")
    f.lbl = lbl

    f:Hide()
    Spotter.plateBadges[plate] = f
    return f
end

local function HidePlateBadgeForUnit(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not IsPlateAccessible(plate) then return end
    local badge = Spotter.plateBadges[plate]
    if badge then
        badge:Hide()
    end
end

local function UpdatePlateBadge(unit, entry)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not IsPlateAccessible(plate) then return end

    local s = ns.db and ns.db.settings
    local enabled = s and s.spotterEnabled ~= false and s.spotterNameplateBadges ~= false
    if not enabled or not entry then
        local existing = Spotter.plateBadges[plate]
        if existing then existing:Hide() end
        return
    end

    local badge = EnsurePlateBadge(plate)
    local col = STANCE_COLORS[entry.stance] or STANCE_COLORS.ENEMY
    local tagText = entry.stance == "ENEMY" and L["ENEMY CLAN"]
        or (entry.stance == "ALLY" and L["ALLY CLAN"] or L["SAME CLAN"])

    badge.bg:SetColorTexture(0.05, 0.05, 0.07, 0.85)
    badge.bar:SetColorTexture(col.r, col.g, col.b, 0.95)
    badge.lbl:SetText(col.hex .. tagText .. "|r")
    local w = math.max(76, math.min(148, (badge.lbl:GetStringWidth() or 60) + 18))
    badge:SetWidth(w)
    badge:Show()
end

function Spotter:GetStanceLabel(stance)
    if stance == "ENEMY" then return L["Enemy Clan"] end
    if stance == "ALLY" then return L["Ally Clan"] end
    if stance == "SAME" then return L["Same Clan"] end
    return L["Neutral"]
end

function Spotter:GetStanceColor(stance)
    return STANCE_COLORS[stance] or STANCE_COLORS.SAME
end

function Spotter:ClassifyGuild(rawGuildName)
    if not rawGuildName or rawGuildName == "" then
        return nil, nil
    end

    local myNormGuild = GetPlayerNormalizedGuild()
    if myNormGuild and myNormGuild ~= "" and NormalizeKeyPart(rawGuildName) == myNormGuild then
        return "SAME", nil
    end

    if ns.Clan and ns.Clan.LookupGuildStance then
        local stance, dipEntry = ns.Clan:LookupGuildStance(rawGuildName)
        if stance == "ENEMY" or stance == "ALLY" then
            return stance, dipEntry
        end
    end
    return nil, nil
end

local function ShouldNotifyStance(stance)
    local s = ns.db and ns.db.settings
    if not s or s.spotterEnabled == false then return false end
    if stance == "ENEMY" then return s.spotterNotifyEnemy ~= false end
    if stance == "ALLY" then return s.spotterNotifyAlly ~= false end
    if stance == "SAME" then return s.spotterNotifySameClan ~= false end
    return false
end

local function PlaySpotterSound(stance)
    local s = ns.db and ns.db.settings
    if not s or s.spotterSound == false then return end
    if not PlaySound then return end

    if SOUNDKIT then
        local kit
        if stance == "ENEMY" then
            kit = SOUNDKIT.RAID_WARNING or SOUNDKIT.ALARM_CLOCK_WARNING_3 or SOUNDKIT.TELL_MESSAGE
        elseif stance == "ALLY" then
            kit = SOUNDKIT.READY_CHECK or SOUNDKIT.IG_QUEST_LOG_OPEN
        else
            kit = SOUNDKIT.TELL_MESSAGE or SOUNDKIT.IG_QUEST_LOG_OPEN
        end
        if kit then
            pcall(PlaySound, kit, "Master")
            return
        end
    end

    local soundName = (stance == "ENEMY") and "RaidWarning" or ((stance == "ALLY") and "ReadyCheck" or "TellMessage")
    pcall(PlaySound, soundName)
end

function Spotter:MaybeTriggerAlert(entry)
    if not entry or not ShouldNotifyStance(entry.stance) then return end

    local now = time()
    local cooldown = (entry.stance == "ENEMY") and ENEMY_ALERT_COOLDOWN or FRIENDLY_ALERT_COOLDOWN
    local prev = self.alertCooldowns[entry.key] or 0
    if (now - prev) < cooldown then
        return
    end
    self.alertCooldowns[entry.key] = now

    local col = STANCE_COLORS[entry.stance] or STANCE_COLORS.SAME
    local tag = col.hex .. "[" .. self:GetStanceLabel(entry.stance):upper() .. "]|r"
    local classHex = Compat.ClassHex and Compat.ClassHex(entry.classFile) or "|cffffffff"
    local shownName = entry.displayName or "?"
    local playerCol = "|Haddon:SCentral:target:" .. entry.key .. "|h" .. classHex .. shownName .. "|r|h"
    local guildText = entry.guild and (" |cff9ea8b8<" .. entry.guild .. ">|r") or ""
    local reasonText = (entry.reason and entry.reason ~= "") and (" — |cffffd280" .. entry.reason .. "|r") or ""
    local radarLink = "|Haddon:SCentral:spotter|h|cff58a6ff[" .. L["Target Radar"] .. "]|r|h"

    ns:Print("%s %s%s%s %s", tag, playerCol, guildText, reasonText, radarLink)
    PlaySpotterSound(entry.stance)

    local alert = {
        key = entry.key,
        stance = entry.stance,
        displayName = entry.displayName,
        firstName = entry.firstName,
        guid = entry.guid,
        guild = entry.guild,
        classFile = entry.classFile,
        level = entry.level,
        reason = entry.reason,
        targetName = entry.targetName,
        ts = now,
    }
    self.lastAlert = alert
    ns:Emit("SPOTTER_ALERT", alert)
end

function Spotter:FocusTarget(key)
    if not key or key == "" then return false end
    local entry = self.entries[key]
    if not entry then
        -- Fall back to firstName or normalized key match in case the key was upgraded with a surname.
        local altParsed = Compat.ParseCharacterName(key)
        local lk = altParsed and altParsed.lookupKey or key:lower()
        local firstLower = altParsed and altParsed.firstName:lower() or lk
        for _, candidate in pairs(self.entries) do
            if candidate.key == lk or (candidate.firstName and candidate.firstName:lower() == firstLower) then
                entry = candidate
                break
            end
        end
    end
    if not entry then
        ns:Print(L["Player is no longer in Target Radar range."])
        return false
    end

    entry.lastSeen = time()
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
    local alert = {
        key = entry.key,
        stance = entry.stance,
        displayName = entry.displayName,
        firstName = entry.firstName,
        guid = entry.guid,
        guild = entry.guild,
        classFile = entry.classFile,
        level = entry.level,
        reason = entry.reason,
        targetName = entry.targetName,
        ts = time(),
    }
    self.lastAlert = alert
    ns:Emit("SPOTTER_ALERT", alert)
    if ns.SpotterHUD and ns.SpotterHUD.Show then
        ns.SpotterHUD:Show(true)
    end
    return true
end

local function TrimExcessTargets()
    local list = {}
    for _, e in pairs(Spotter.entries) do
        table.insert(list, e)
    end
    if #list <= MAX_TARGETS then return end

    table.sort(list, function(a, b)
        if a.onScreen ~= b.onScreen then return a.onScreen end
        local pa = STANCE_PRIORITY[a.stance] or 9
        local pb = STANCE_PRIORITY[b.stance] or 9
        if pa ~= pb then return pa < pb end
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end)

    for i = MAX_TARGETS + 1, #list do
        Spotter.entries[list[i].key] = nil
    end
end

function Spotter:InspectUnit(unit, isNameplate)
    local s = ns.db and ns.db.settings
    if not s or s.spotterEnabled == false then
        if isNameplate then HidePlateBadgeForUnit(unit) end
        return nil
    end

    if not unit or Safe.IsSecret(unit) then return nil end
    local exists = Safe.Value(Safe.Call(UnitExists, unit))
    if exists ~= true then
        if isNameplate and self.visibleUnits[unit] then
            self.visibleUnits[unit] = nil
            HidePlateBadgeForUnit(unit)
            RecomputeOnScreenFlags()
            ns:Emit("SPOTTER_UPDATED")
        end
        return nil
    end

    local isPlayer = Safe.Value(Safe.Call(UnitIsPlayer, unit))
    if isPlayer ~= true then
        if isNameplate and self.visibleUnits[unit] then
            self.visibleUnits[unit] = nil
            HidePlateBadgeForUnit(unit)
            RecomputeOnScreenFlags()
        end
        return nil
    end

    local guid = Safe.String(Safe.Call(UnitGUID, unit))
    local rawUnitName = Safe.String(Safe.Call(UnitName, unit))
    local existingName = nil
    if guid then
        for _, e in pairs(self.entries) do
            if e.guid == guid and e.displayName and e.displayName:find("%s") then
                existingName = e.displayName
                break
            end
        end
    end
    local resolved, rawRealm = Compat.ResolveUnitFullName(unit, guid, existingName)
    local rawName = resolved and resolved.fullName or rawUnitName
    if not rawName or rawName == "" or Compat.IsMe(rawName, guid) then
        if isNameplate then
            self.visibleUnits[unit] = nil
            HidePlateBadgeForUnit(unit)
        end
        return nil
    end

    local gName, gRank = GetUnitSafeGuild(unit)
    local stance, dipEntry = self:ClassifyGuild(gName)
    if not stance and (resolved or rawUnitName) then
        local checkFirst = resolved and resolved.firstName or rawUnitName
        if Compat.IsGuildMember and Compat.IsGuildMember(checkFirst, guid) then
            local _, myGuildName = GetPlayerNormalizedGuild()
            if myGuildName and myGuildName ~= "" then
                gName = myGuildName
                stance = "SAME"
            end
        end
    end
    if not stance then
        if isNameplate and self.visibleUnits[unit] then
            self.visibleUnits[unit] = nil
            HidePlateBadgeForUnit(unit)
            RecomputeOnScreenFlags()
            ns:Emit("SPOTTER_UPDATED")
        elseif isNameplate then
            HidePlateBadgeForUnit(unit)
        end
        return nil
    end

    local parsed = Compat.ParseCharacterName(rawName)
    local key = (parsed and parsed.lookupKey) or NormalizeKeyPart(rawName)
    if not key or key == "" then return nil end

    -- Upgrade any earlier first-name-only sighting matching the same GUID cleanly.
    local upgradedOld
    if guid then
        for oldKey, oldEntry in pairs(self.entries) do
            if oldKey ~= key and oldEntry.guid == guid then
                upgradedOld = oldEntry
                self.entries[oldKey] = nil
                if self.alertCooldowns[oldKey] then
                    self.alertCooldowns[key] = self.alertCooldowns[oldKey]
                    self.alertCooldowns[oldKey] = nil
                end
                for uTok, mappedKey in pairs(self.visibleUnits) do
                    if mappedKey == oldKey then
                        self.visibleUnits[uTok] = key
                    end
                end
                break
            end
        end
    end

    local displayName = (parsed and parsed.displayName) or rawName
    local firstName = (parsed and parsed.firstName) or rawName
    local targetMacroName = SanitizeMacroTargetName(displayName, rawRealm)
    if not targetMacroName then return nil end

    local _, classFile = Safe.Call(UnitClass, unit)
    classFile = Safe.String(classFile)
    local level = Safe.Number(Safe.Call(UnitLevel, unit))
    local isDead = Safe.Value(Safe.Call(UnitIsDeadOrGhost, unit)) == true
    local now = time()

    local isNewOrChanged = false
    local entry = self.entries[key] or upgradedOld
    if not entry then
        entry = {
            key = key,
            firstSeen = now,
        }
        isNewOrChanged = true
    elseif entry.stance ~= stance then
        isNewOrChanged = true
    end
    entry.key = key
    self.entries[key] = entry

    if not (parsed and parsed.surname) and entry and entry.displayName and entry.displayName:find("%s") then
        displayName = entry.displayName
        firstName = entry.firstName or firstName
    end
    entry.displayName = displayName
    entry.firstName = firstName
    entry.unitName = rawUnitName or entry.unitName
    entry.targetName = targetMacroName
    entry.guild = gName
    entry.guildRank = gRank
    entry.stance = stance
    entry.reason = (dipEntry and dipEntry.reason) or ""
    entry.classFile = classFile or entry.classFile
    entry.level = (level and level > 0) and level or entry.level
    entry.dead = isDead
    entry.guid = guid or entry.guid
    entry.lastSeen = now
    entry.unitHint = unit
    entry.unitToken = isNameplate and unit or (entry.unitToken or unit)

    -- Capture immediate proximity metrics when unit is reachable
    if unit and UnitExists(unit) then
        local d3 = CheckInteractDistance and Safe.Value(Safe.Call(CheckInteractDistance, unit, 3))
        local d2 = CheckInteractDistance and Safe.Value(Safe.Call(CheckInteractDistance, unit, 2))
        local d1 = CheckInteractDistance and Safe.Value(Safe.Call(CheckInteractDistance, unit, 1))
        local in40 = UnitInRange and Safe.Value(Safe.Call(UnitInRange, unit))
        if d3 == true then
            entry.lastDistText = L["< 10m"]
            entry.lastDistYards = 8
        elseif d2 == true then
            entry.lastDistText = L["~11m"]
            entry.lastDistYards = 11
        elseif d1 == true then
            entry.lastDistText = L["12-28m"]
            entry.lastDistYards = 20
        elseif in40 == true then
            entry.lastDistText = L["29-40m"]
            entry.lastDistYards = 35
        end
    end

    -- Capture initial world heading from cursor position when hovered without a nameplate
    if unit == "mouseover" and not isNameplate and GetCursorPosition and UIParent and UIParent.GetCenter then
        local okCur, mx = pcall(GetCursorPosition)
        local okC, cx = pcall(UIParent.GetCenter, UIParent)
        if okCur and okC and mx and cx then
            local uScale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            local screenDx = mx - (cx * uScale)
            local halfW = math.max(1, (UIParent:GetWidth() or 1000) * 0.5 * uScale)
            local screenFrac = math.max(-1, math.min(1, screenDx / halfW))
            local cursorAngle = -screenFrac * (math.pi * 0.45)
            local facing = GetPlayerFacing and Safe.Number(Safe.Call(GetPlayerFacing)) or 0
            entry._lastWorldHeading = NormalizeAngleRad(facing + cursorAngle)
        end
    end

    if isNameplate then
        self.visibleUnits[unit] = key
        UpdatePlateBadge(unit, entry)
    end

    RecomputeOnScreenFlags()
    TrimExcessTargets()

    if isNewOrChanged then
        self:MaybeTriggerAlert(entry)
    end

    ns:Emit("SPOTTER_UPDATED")
    return entry
end

function Spotter:RefreshVisibleNameplates()
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in ipairs(plates) do
                if IsPlateAccessible(plate) then
                    local unit = Safe.String(plate.namePlateUnitToken)
                    if not unit and plate.UnitFrame then
                        unit = Safe.String(plate.UnitFrame.unit)
                    end
                    if unit then
                        self:InspectUnit(unit, true)
                    end
                end
            end
        end
    end

    self:InspectUnit("target", false)
    self:InspectUnit("focus", false)
    self:InspectUnit("mouseover", false)
end

function Spotter:ReclassifyActiveEntries()
    local rekeyed = {}
    for key, entry in pairs(self.entries) do
        local stance, dipEntry = self:ClassifyGuild(entry.guild)
        if not stance then
            self.entries[key] = nil
        else
            entry.stance = stance
            entry.reason = (dipEntry and dipEntry.reason) or ""
            if entry.guid and Compat.LookupForeverFullName then
                local resolved = Compat.LookupForeverFullName(entry.guid, entry.firstName)
                if resolved and resolved.surname then
                    local parsed = Compat.ParseCharacterName(resolved.fullName)
                    if parsed and parsed.lookupKey ~= "" then
                        entry.displayName = parsed.displayName
                        entry.firstName = parsed.firstName
                        entry.targetName = SanitizeMacroTargetName(parsed.displayName, nil) or parsed.displayName
                        if parsed.lookupKey ~= key then
                            entry.key = parsed.lookupKey
                            rekeyed[key] = entry
                        end
                    end
                end
            end
        end
    end
    for oldKey, entry in pairs(rekeyed) do
        self.entries[oldKey] = nil
        self.entries[entry.key] = entry
        for uTok, mapped in pairs(self.visibleUnits) do
            if mapped == oldKey then
                self.visibleUnits[uTok] = entry.key
            end
        end
    end

    for unit, key in pairs(self.visibleUnits) do
        local entry = self.entries[key]
        if entry then
            UpdatePlateBadge(unit, entry)
        else
            self.visibleUnits[unit] = nil
            HidePlateBadgeForUnit(unit)
        end
    end

    RecomputeOnScreenFlags()
    self:RefreshVisibleNameplates()
    ns:Emit("SPOTTER_UPDATED")
end

function Spotter:OnGuildChanged()
    local currentScope = ns.Clan and ns.Clan.GetActiveScopeToken and ns.Clan:GetActiveScopeToken() or ""
    if self.lastScopeToken and self.lastScopeToken ~= currentScope then
        self:Clear(true)
        if Compat.ClearGuildMembers then Compat.ClearGuildMembers() end
        if Compat.SyncRosterForeverNames then Compat.SyncRosterForeverNames() end
    elseif not self.lastScopeToken then
        self:Clear(true)
    end
    self.lastScopeToken = currentScope
    self:RefreshVisibleNameplates()
end

function Spotter:Clear(silent)
    wipe(self.entries)
    wipe(self.visibleUnits)
    wipe(self.alertCooldowns)
    self.lastAlert = nil

    for _, badge in pairs(self.plateBadges) do
        if badge and badge.Hide then
            badge:Hide()
        end
    end

    if not silent then
        ns:Emit("SPOTTER_UPDATED")
    end
end

function Spotter:DismissTarget(key)
    if not key or not self.entries[key] then return false end
    self.entries[key] = nil
    for unit, uKey in pairs(self.visibleUnits) do
        if uKey == key then
            self.visibleUnits[unit] = nil
            HidePlateBadgeForUnit(unit)
        end
    end
    ns:Emit("SPOTTER_UPDATED")
    return true
end

local function UnitMatchesEntry(unit, entry)
    if not unit or not entry then return false end
    local exists = Safe.Value(Safe.Call(UnitExists, unit))
    if exists ~= true then return false end

    local uGuid = Safe.String(Safe.Call(UnitGUID, unit))
    if entry.guid and uGuid and uGuid == entry.guid then
        return true
    end

    local uName = Safe.String(Safe.Call(UnitName, unit))
    if uName and uName ~= "" then
        if entry.unitName and uName:lower() == entry.unitName:lower() then
            return true
        end
        local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(uName)
        if parsed and (parsed.lookupKey == entry.key or (entry.firstName and parsed.firstName:lower() == entry.firstName:lower())) then
            return true
        end
    end
    return false
end

function Spotter:FindLiveUnitForEntry(entry)
    if not entry then return nil, nil end

    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in ipairs(plates) do
                if IsPlateAccessible(plate) then
                    local unit = Safe.String(plate.namePlateUnitToken)
                    if not unit and plate.UnitFrame then
                        unit = Safe.String(plate.UnitFrame.unit)
                    end
                    if unit and UnitMatchesEntry(unit, entry) then
                        return unit, plate
                    end
                end
            end
        end
    end

    for _, token in ipairs({ "target", "focus", "mouseover" }) do
        if UnitMatchesEntry(token, entry) then
            local plate
            if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
                local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, token)
                if ok and IsPlateAccessible(p) then
                    plate = p
                end
            end
            return token, plate
        end
    end

    local inRaid = Compat.IsInRaid()
    local numMembers = Compat.GetNumGroupMembers()
    if numMembers and numMembers > 0 then
        local prefix = inRaid and "raid" or "party"
        local limit = inRaid and math.min(40, numMembers) or math.min(4, numMembers)
        for i = 1, limit do
            local token = prefix .. i
            if UnitMatchesEntry(token, entry) then
                return token, nil
            end
        end
    end

    return nil, nil
end

local function NormalizeAngleRad(a)
    local pi = math.pi
    while a > pi do a = a - 2 * pi end
    while a < -pi do a = a + 2 * pi end
    return a
end

function Spotter:GetTargetKinematics(entry)
    if not entry then return nil end

    local unit = entry.unitToken
    local plate
    if unit and UnitExists(unit) then
        if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
            local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, unit)
            if ok and IsPlateAccessible(p) then plate = p end
        end
    else
        unit, plate = self:FindLiveUnitForEntry(entry)
        entry.unitToken = unit
    end

    local facing = GetPlayerFacing and Safe.Number(Safe.Call(GetPlayerFacing)) or 0
    local angle, distYards, distText

    if unit then
        -- Fast engine-level world position (standard TomTom / DBM / Questie approach)
        -- Note: UnitPosition in WoW C-engine returns: y, x, z, instanceID (y = North, x = West)
        if UnitPosition then
            local py, px, _, pMap = UnitPosition("player")
            local ty, tx, _, tMap = UnitPosition(unit)
            if py and px and ty and tx and pMap == tMap then
                local dy = ty - py
                local dx = tx - px
                distYards = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
                local worldAngle = math.atan2(dx, dy)
                angle = NormalizeAngleRad(worldAngle - facing)
                entry._lastWorldHeading = worldAngle
            end
        end

        if not distYards and UnitDistanceSquared then
            local dSq, checked = Safe.Call(UnitDistanceSquared, unit)
            dSq = Safe.Number(dSq)
            if Safe.Value(checked) == true and dSq and dSq >= 0 then
                distYards = math.floor(math.sqrt(dSq) + 0.5)
            end
        end

        if not angle and plate and plate.IsShown and plate:IsShown() and plate.GetCenter and UIParent and UIParent.GetCenter then
            local okP, px = pcall(plate.GetCenter, plate)
            local okC, cx = pcall(UIParent.GetCenter, UIParent)
            if okP and okC and px and cx then
                local pScale = (plate.GetEffectiveScale and plate:GetEffectiveScale()) or 1
                local uScale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
                local screenDx = (px * pScale) - (cx * uScale)
                local halfW = math.max(1, (UIParent:GetWidth() or 1000) * 0.5 * uScale)
                local screenFrac = math.max(-1, math.min(1, screenDx / halfW))
                angle = -screenFrac * (math.pi * 0.45)
                entry._lastWorldHeading = NormalizeAngleRad(facing + angle)
            end
        end

        if not distYards then
            local d3 = CheckInteractDistance and Safe.Value(Safe.Call(CheckInteractDistance, unit, 3))
            local d2 = CheckInteractDistance and Safe.Value(Safe.Call(CheckInteractDistance, unit, 2))
            local d1 = CheckInteractDistance and Safe.Value(Safe.Call(CheckInteractDistance, unit, 1))
            local in40 = UnitInRange and Safe.Value(Safe.Call(UnitInRange, unit))
            if d3 == true then
                distText = L["< 10m"]
                distYards = 8
            elseif d2 == true then
                distText = L["~11m"]
                distYards = 11
            elseif d1 == true then
                distText = L["12-28m"]
                distYards = 20
            elseif in40 == true then
                distText = L["29-40m"]
                distYards = 35
            else
                distText = entry.lastDistText or L["> 28m"]
                distYards = entry.lastDistYards
            end
            if distText and distText ~= L["> 28m"] then
                entry.lastDistText = distText
                entry.lastDistYards = distYards
            end
        else
            distText = string.format("%dm", distYards)
            entry.lastDistText = distText
            entry.lastDistYards = distYards
        end
    end

    if not angle and entry._lastWorldHeading and facing then
        angle = NormalizeAngleRad(entry._lastWorldHeading - facing)
    end

    return {
        unit = unit,
        hasAngle = (angle ~= nil),
        angle = angle and NormalizeAngleRad(angle) or 0,
        distYards = distYards or entry.lastDistYards,
        distText = distText or entry.lastDistText or L["> 28m"],
        exact = (distYards ~= nil),
    }
end

function Spotter:CleanupAbsentTargets(silent)
    local now = time()
    local changed = false

    for uTok, _ in pairs(self.visibleUnits) do
        local exists = Safe.Value(Safe.Call(UnitExists, uTok))
        if exists ~= true then
            self.visibleUnits[uTok] = nil
            HidePlateBadgeForUnit(uTok)
            changed = true
        end
    end
    RecomputeOnScreenFlags()

    for key, entry in pairs(self.entries) do
        local maxRetention = entry.dead and 3 or RETENTION_SECONDS
        local isRecent = (now - (entry.lastSeen or now)) <= maxRetention
        local keep = entry.onScreen
            or UnitMatchesEntry("target", entry)
            or UnitMatchesEntry("focus", entry)
            or UnitMatchesEntry("mouseover", entry)
            or isRecent
        if not keep then
            self.entries[key] = nil
            if self.lastAlert and self.lastAlert.key == key then
                self.lastAlert = nil
            end
            changed = true
        end
    end

    if changed and not silent then
        ns:Emit("SPOTTER_UPDATED")
    end
    return changed
end

function Spotter:Prune(silent)
    self:CleanupAbsentTargets(silent)
end

function Spotter:GetCounts()
    local enemy, ally, same, onScreen = 0, 0, 0, 0
    for _, entry in pairs(self.entries) do
        if entry.stance == "ENEMY" then
            enemy = enemy + 1
        elseif entry.stance == "ALLY" then
            ally = ally + 1
        elseif entry.stance == "SAME" then
            same = same + 1
        end
        if entry.onScreen then
            onScreen = onScreen + 1
        end
    end
    return enemy, ally, same, (enemy + ally + same), onScreen
end

function Spotter:GetActiveTargets(filterStance)
    local out = {}
    local f = filterStance and filterStance:upper() or "ALL"
    for _, entry in pairs(self.entries) do
        if f == "ALL" or entry.stance == f then
            table.insert(out, entry)
        end
    end
    table.sort(out, function(a, b)
        if a.onScreen ~= b.onScreen then return a.onScreen end
        local pa = STANCE_PRIORITY[a.stance] or 9
        local pb = STANCE_PRIORITY[b.stance] or 9
        if pa ~= pb then return pa < pb end
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end)
    return out
end

function Spotter:Init()
    self.lastScopeToken = ns.Clan and ns.Clan.GetActiveScopeToken and ns.Clan:GetActiveScopeToken() or ""

    local function ScanActiveNameplates()
        if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if not (ok and type(plates) == "table") then return end
        for _, plate in ipairs(plates) do
            if IsPlateAccessible(plate) then
                local unit = Safe.String(plate.namePlateUnitToken)
                if not unit and plate.UnitFrame then
                    unit = Safe.String(plate.UnitFrame.unit)
                end
                if unit and UnitExists(unit) then
                    Spotter:InspectUnit(unit, true)
                end
            end
        end
    end
    self.ScanActiveNameplates = ScanActiveNameplates

    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        self:OnGuildChanged()
        ScanActiveNameplates()
    end)

    ns.RegisterEvent(self, "PLAYER_GUILD_UPDATE", function(_, unit)
        if not unit or unit == "player" then
            self:OnGuildChanged()
        end
    end)

    ns.RegisterEvent(self, "GUILD_ROSTER_UPDATE", function()
        if Compat.SyncRosterForeverNames then
            Compat.SyncRosterForeverNames()
        end
        self:ReclassifyActiveEntries()
        ScanActiveNameplates()
    end)

    ns.RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", function(_, unit)
        self:InspectUnit(unit, true)
    end)

    ns.RegisterEvent(self, "NAME_PLATE_UNIT_REMOVED", function(_, unit)
        if unit and self.visibleUnits[unit] then
            self.visibleUnits[unit] = nil
            HidePlateBadgeForUnit(unit)
            RecomputeOnScreenFlags()
            if not self:CleanupAbsentTargets(false) then
                ns:Emit("SPOTTER_UPDATED")
            end
        else
            HidePlateBadgeForUnit(unit)
        end
    end)

    ns.RegisterEvent(self, "UNIT_NAME_UPDATE", function(_, unit)
        if unit and unit:match("^nameplate") then
            self:InspectUnit(unit, true)
        elseif unit == "target" or unit == "focus" or unit == "mouseover" then
            self:InspectUnit(unit, false)
        end
    end)

    ns.RegisterEvent(self, "UPDATE_MOUSEOVER_UNIT", function()
        self:InspectUnit("mouseover", false)
    end)

    ns.RegisterEvent(self, "PLAYER_TARGET_CHANGED", function()
        self:InspectUnit("target", false)
        self:CleanupAbsentTargets(false)
    end)

    ns.RegisterEvent(self, "PLAYER_FOCUS_CHANGED", function()
        self:InspectUnit("focus", false)
        self:CleanupAbsentTargets(false)
    end)

    ns:On("CLAN_DIPLOMACY_UPDATED", function()
        self:ReclassifyActiveEntries()
    end)

    ns:On("CLAN_UPDATED", function()
        self:OnGuildChanged()
    end)

    ns:On("SETTINGS_UPDATED", function()
        self:ReclassifyActiveEntries()
    end)

    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, elapsed)
        self._pruneElapsed = (self._pruneElapsed or 0) + elapsed
        self._platePollElapsed = (self._platePollElapsed or 0) + elapsed
        if self._platePollElapsed >= 0.6 then
            self._platePollElapsed = 0
            ScanActiveNameplates()
        end
        if self._pruneElapsed >= PRUNE_INTERVAL then
            self._pruneElapsed = 0
            self:Prune(false)
        end
    end)
    self._ticker = ticker
end

ns.Spotter = Spotter
table.insert(ns.modules, Spotter)
