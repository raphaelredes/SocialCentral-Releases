local _, ns = ...

-- Secret-value and WoW: Forever (16001 / Project Camelot) compatibility layer.
-- Protects unit/chat/who reads against 12.x secret values and normalizes
-- Forever's backend shard labels (CAMWOWUS1Realm2PvP -> camwowus1realmpvp)
-- plus Name / Name-Surname identities.

local Safe = {}
local Compat = {}
ns.Safe = Safe
ns.Compat = Compat

function Safe.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end

function Safe.CanAccess(value)
    if value == nil then return false end
    if Safe.IsSecret(value) then return false end
    if canaccessvalue ~= nil then
        local ok, accessible = pcall(canaccessvalue, value)
        return ok and accessible == true
    end
    return true
end

function Safe.Value(value)
    if not Safe.CanAccess(value) then return nil end
    return value
end

function Safe.String(value)
    value = Safe.Value(value)
    if type(value) ~= "string" or value == "" then return nil end
    return value
end

function Safe.Number(value)
    value = Safe.Value(value)
    if type(value) ~= "number" then return nil end
    return value
end

function Safe.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    return Safe.Value(a), Safe.Value(b), Safe.Value(c)
end

local cachedRealm

local function Plain(text)
    return (text:gsub("[%s%-']", "")):lower()
end

function Compat.Plain(text)
    if type(text) ~= "string" then return "" end
    return Plain(text)
end

function Compat.Realm()
    if cachedRealm and cachedRealm ~= "" then return cachedRealm end
    local norm = Safe.String(Safe.Call(GetNormalizedRealmName))
    if norm then
        cachedRealm = norm
        return cachedRealm
    end
    local _, unitRealm = Safe.Call(UnitFullName, "player")
    unitRealm = Safe.String(unitRealm)
    if unitRealm then
        cachedRealm = unitRealm
        return cachedRealm
    end
    local raw = Safe.String(Safe.Call(GetRealmName))
    if raw then
        cachedRealm = raw:gsub("[%s%-]", "")
        return cachedRealm
    end
    return ""
end

-- Collapse numbered Forever shard realms into a single ruleset pool key:
-- "CAMWOWUS1Realm2PvP" and "CAMWOWUS1Realm9PvP" -> "camwowus1realmpvp".
function Compat.RealmPool(realmName)
    if type(realmName) ~= "string" or realmName == "" then
        realmName = Compat.Realm()
    end
    if realmName == "" then return "default" end
    local key = Plain(realmName)
    key = key:gsub("realm%d+", "realm")
    return key
end

function Compat.IsForeverShardLabel(label)
    if type(label) ~= "string" or label == "" then return false end
    local p = Plain(label)
    if p:match("^camwow%a+%d+realm%d+%a+$") then return true end
    local own = Compat.Realm()
    return own ~= "" and Compat.RealmPool(p) == Compat.RealmPool(own)
end

function Compat.PlayerFaction()
    if UnitFactionGroup then
        local ok, eng, loc = pcall(UnitFactionGroup, "player")
        if ok then
            eng = Safe.String(eng)
            loc = Safe.String(loc)
            if eng == "Horde" or eng == "Alliance" then
                return eng, loc
            end
        end
    end
    return "Alliance", nil
end

function Compat.ScopeKey()
    return Compat.RealmPool(Compat.Realm()) .. ":" .. Compat.PlayerFaction()
end

function Compat.CharacterKey()
    local name = Safe.String(Safe.Call(UnitName, "player")) or "Unknown"
    return name .. "@" .. Compat.RealmPool(Compat.Realm())
end

-- Sanitize user-entered text: strip UI escape sequences, newlines, trim whitespace.
function Compat.CleanInput(text)
    if type(text) ~= "string" then return nil end
    local cleaned = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    cleaned = cleaned:gsub("[%c|]", " "):gsub("^%s*(.-)%s*$", "%1"):gsub("%s+", " ")
    if cleaned == "" then return nil end
    return cleaned
end

-- Sanitize a single-line addon payload field, removing delimiters (~ |) and capping length.
function Compat.CleanPayloadField(text, maxLen)
    local cleaned = Compat.CleanInput(text)
    if not cleaned then return "" end
    cleaned = cleaned:gsub("[~^]", " "):gsub("^%s*(.-)%s*$", "%1"):gsub("%s+", " ")
    if maxLen and #cleaned > maxLen then
        cleaned = cleaned:sub(1, maxLen)
    end
    return cleaned
end

-- Compare strict MAJOR.MINOR.PATCH SemVer strings. Returns 1 (a>b), -1 (a<b), or 0.
function Compat.CompareSemVer(verA, verB)
    if type(verA) ~= "string" or type(verB) ~= "string" then return 0 end
    local a1, a2, a3 = verA:match("^(%d+)%.(%d+)%.(%d+)$")
    local b1, b2, b3 = verB:match("^(%d+)%.(%d+)%.(%d+)$")
    if not a1 or not b1 then return 0 end
    local va = { tonumber(a1), tonumber(a2), tonumber(a3) }
    local vb = { tonumber(b1), tonumber(b2), tonumber(b3) }
    for i = 1, 3 do
        if va[i] > vb[i] then return 1 end
        if va[i] < vb[i] then return -1 end
    end
    return 0
end

-- Parse a character identifier into firstName, optional surname, displayName, and lookupKey.
-- Handles Forever formats: "Name", "Name-Surname", "Name Surname", or "Name-CAMWOW...".
function Compat.ParseCharacterName(raw)
    local cleaned = Compat.CleanInput(raw)
    if not cleaned then return nil end

    -- Strip trailing Forever shard suffix if present (e.g. "Arthas-CAMWOWUS1Realm2PvP" or "Arthas Menethil-CAMWOW...").
    local head, tail = cleaned:match("^(.-)%-([^%-]+)$")
    if head and tail and Compat.IsForeverShardLabel(tail) then
        cleaned = head
    end

    -- Forever characters can have FirstName + Surname separated by "-" or space.
    local first, second = cleaned:match("^([^%s%-]+)[%s%-]+([^%s%-]+)$")
    if first and second then
        if Compat.IsForeverShardLabel(second) then
            return {
                firstName = first,
                surname = nil,
                displayName = first,
                lookupKey = first:lower(),
            }
        end
        return {
            firstName = first,
            surname = second,
            displayName = first .. "-" .. second,
            lookupKey = (first .. "-" .. second):lower(),
        }
    end

    local single = cleaned:match("^([^%s%-]+)$") or cleaned
    return {
        firstName = single,
        surname = nil,
        displayName = single,
        lookupKey = single:lower(),
    }
end

function Compat.IsMe(rawName, guid)
    local myGuid = Safe.String(Safe.Call(UnitGUID, "player"))
    if myGuid and guid and guid == myGuid then return true end
    local parsed = Compat.ParseCharacterName(rawName)
    local myName = Safe.String(Safe.Call(UnitName, "player"))
    if not parsed or not myName then return false end
    local myParsed = Compat.ParseCharacterName(myName)
    if not myParsed then return false end
    if parsed.lookupKey == myParsed.lookupKey then return true end
    if not parsed.surname and parsed.firstName:lower() == myParsed.firstName:lower() then
        return true
    end
    return false
end

function Compat.ClassColor(classFile)
    if type(classFile) == "string" and classFile ~= "" then
        if C_ClassColor and C_ClassColor.GetClassColor then
            local color = C_ClassColor.GetClassColor(classFile)
            if color then return color.r, color.g, color.b end
        end
        if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
            local c = RAID_CLASS_COLORS[classFile]
            return c.r, c.g, c.b
        end
    end
    return 0.85, 0.88, 0.92
end

function Compat.ClassHex(classFile)
    local r, g, b = Compat.ClassColor(classFile)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local classByLocalized
function Compat.ClassFileFromLocalized(localized)
    if type(localized) ~= "string" or localized == "" then return nil end
    if not classByLocalized then
        classByLocalized = {}
        for file, label in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do classByLocalized[label] = file end
        for file, label in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do classByLocalized[label] = file end
    end
    return classByLocalized[localized]
end

function Compat.CurrentZoneName()
    local mapID = Safe.Number(Safe.Call(C_Map and C_Map.GetBestMapForUnit, "player"))
    if mapID and C_Map and C_Map.GetMapInfo then
        local info = Safe.Call(C_Map.GetMapInfo, mapID)
        if type(info) == "table" and Safe.String(info.name) then
            return info.name
        end
    end
    return Safe.String(Safe.Call(GetRealZoneText)) or Safe.String(Safe.Call(GetZoneText)) or ""
end

function Compat.Whisper(target)
    local clean = Compat.CleanInput(target)
    if not clean then return end
    if ChatFrameUtil and ChatFrameUtil.SendTell then
        local ok = pcall(ChatFrameUtil.SendTell, clean)
        if ok then return end
    end
    if ChatFrame_SendTell then
        local ok = pcall(ChatFrame_SendTell, clean)
        if ok then return end
    end
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        local ok = pcall(ChatFrameUtil.OpenChat, "/w " .. clean .. " ")
        if ok then return end
    end
    if ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, "/w " .. clean .. " ")
    end
end

function Compat.BNetWhisper(bnetName, fallbackTarget)
    local cleanBNet = Compat.CleanInput(bnetName)
    if cleanBNet then
        if ChatFrameUtil and ChatFrameUtil.SendBNetTell then
            local ok = pcall(ChatFrameUtil.SendBNetTell, cleanBNet)
            if ok then return end
        end
        if ChatFrame_SendBNetTell then
            local ok = pcall(ChatFrame_SendBNetTell, cleanBNet)
            if ok then return end
        end
    end
    if fallbackTarget then
        Compat.Whisper(fallbackTarget)
    end
end

function Compat.Invite(target)
    local clean = Compat.CleanInput(target)
    if not clean then return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        local ok = pcall(C_PartyInfo.InviteUnit, clean)
        if ok then return end
    end
    if InviteUnit then
        pcall(InviteUnit, clean)
    end
end

function Compat.FormatMoney(copper)
    copper = tonumber(copper) or 0
    local g = math.floor(copper / 10000)
    local s = math.floor(copper / 100) % 100
    local c = copper % 100
    if g > 0 then
        return ("%dg %ds"):format(g, s)
    elseif s > 0 then
        return ("%ds %dc"):format(s, c)
    end
    return ("%dc"):format(c)
end

function Compat.FormatRelativeTime(timestamp, L)
    if not timestamp or timestamp <= 0 then return "-" end
    local delta = math.max(0, time() - timestamp)
    if delta < 45 then
        return L["just now"]
    elseif delta < 60 then
        return L["%ds ago"]:format(delta)
    elseif delta < 3600 then
        return L["%dm ago"]:format(math.floor(delta / 60))
    elseif delta < 86400 then
        return L["%dh ago"]:format(math.floor(delta / 3600))
    end
    return L["%dd ago"]:format(math.floor(delta / 86400))
end
