local _, ns = ...

local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })
local Safe = ns.Safe
local Compat = ns.Compat

-- Official Blizzard-compliant Collectible & Resource Highlight engine.
-- Uses ONLY official client Soft-Target Interact CVars (restored on disable),
-- native MINIMAP_UPDATE_TRACKING events, and PLAYER_SOFT_INTERACT_CHANGED.
-- Zero terrain scanning, zero automation, zero nameplate CVar tampering, zero idle CPU.
local Gather = {
    initialized = false,
    pendingCVarSync = false,
    pendingPrompt = nil,
    activeNode = nil,
    activeProfTracking = {},
    baselineTrackingCaptured = false,
    sessionPromptSnoozed = false,
    lastSoundAt = 0,
    lastAnnouncedGuid = nil,
    lastEventGuid = nil,
}
ns.GatherHighlight = Gather
table.insert(ns.modules, Gather)

local PLAY_SOUND_COOLDOWN = 3.0
local ALERT_SOUND_ID = 3175 -- UI Quest/Map ping sound (soft, unobtrusive)

-- Whitelisted official accessibility/graphics CVars only (NEVER touches nameplate* CVars).
local MANAGED_CVAR_NAMES = {
    "SoftTargetInteract",
    "SoftTargetInteractArc",
    "SoftTargetInteractRange",
    "SoftTargetIconInteract",
    "SoftTargetIconGameObject",
    "SoftTargetIconSize",
    "SoftTargetNameplateInteract",
    "Outline",
    "graphicsOutlineMode",
}

local CLASSIC_TRACKING_TEXTURES = {
    [133939] = { kind = "HERB", icon = "Interface\\Icons\\INV_Misc_Flower_02", labelKey = "Herb" },
    [136244] = { kind = "HERB", icon = "Interface\\Icons\\Trade_Herbalism", labelKey = "Herb" },
    [136025] = { kind = "ORE", icon = "Interface\\Icons\\Spell_Nature_Earthquake", labelKey = "Mineral / Ore" },
    [134708] = { kind = "ORE", icon = "Interface\\Icons\\Trade_Mining", labelKey = "Mineral / Ore" },
    [133883] = { kind = "FISH", icon = "Interface\\Icons\\INV_Misc_Fish_02", labelKey = "Fishing Pool" },
    [136245] = { kind = "FISH", icon = "Interface\\Icons\\Trade_Fishing", labelKey = "Fishing Pool" },
    [135725] = { kind = "TREASURE", icon = "Interface\\Icons\\Racial_Dwarf_FindTreasure", labelKey = "Treasure / Resource" },
}

local TRACKING_SPELL_IDS = {
    [2383]  = { kind = "HERB", icon = "Interface\\Icons\\INV_Misc_Flower_02", labelKey = "Herb" }, -- Find Herbs
    [2580]  = { kind = "ORE", icon = "Interface\\Icons\\Spell_Nature_Earthquake", labelKey = "Mineral / Ore" }, -- Find Minerals
    [43308] = { kind = "FISH", icon = "Interface\\Icons\\INV_Misc_Fish_02", labelKey = "Fishing Pool" }, -- Find Fish
    [2481]  = { kind = "TREASURE", icon = "Interface\\Icons\\Racial_Dwarf_FindTreasure", labelKey = "Treasure / Resource" }, -- Find Treasure
}

local TRACKING_CATEGORIES = {
    {
        kind = "HERB",
        fallbackIcon = "Interface\\Icons\\Trade_Herbalism",
        tokens = {
            "find herbs", "herbalism", "herb",
            "localizar ervas", "encontrar ervas", "herborismo", "ervas",
            "buscar hierbas", "encontrar hierbas", "herboristeria", "hierbas",
        },
    },
    {
        kind = "ORE",
        fallbackIcon = "Interface\\Icons\\Trade_Mining",
        tokens = {
            "find minerals", "mining", "minerals",
            "localizar minerios", "encontrar minerios", "mineracao", "minerios",
            "buscar minerales", "encontrar minerales", "mineria", "minerales",
        },
    },
    {
        kind = "FISH",
        fallbackIcon = "Interface\\Icons\\Trade_Fishing",
        tokens = {
            "find fish", "fishing",
            "localizar peixes", "encontrar peixes", "pescaria", "pesca", "cardume",
            "buscar bancos de peces", "encontrar peces", "peces",
        },
    },
    {
        kind = "TREASURE",
        fallbackIcon = "Interface\\Icons\\INV_Misc_Map_01",
        tokens = {
            "find treasure", "find timber", "treasure", "timber",
            "localizar tesouros", "tesouros", "madeira",
            "buscar tesoros", "tesoros", "madera",
        },
    },
}

local NODE_KEYWORDS = {
    HERB = {
        "herb", "erva", "hierba", "flor", "flower", "bloom", "blossom", "leaf", "folha", "hoja",
        "root", "raiz", "lotus", "loto", "moss", "musgo", "musg", "thistle", "cardo",
        "kelp", "alga", "mushroom", "fung", "cogumel", "hongo", "lily", "lirio",
        "petal", "petala", "petalo", "briar", "steelbloom", "kingsblood", "mageroyal",
        "earthroot", "peacebloom", "silverleaf", "bruiseweed", "fadeleaf", "goldthorn",
        "wintersbite", "sungrass", "blindweed", "ghost mushroom", "gromsblood", "sansam",
        "dreamfoil", "silversage", "plaguebloom", "icecap", "felweed", "dreaming glory",
        "ragveil", "flame cap", "terocone", "lichen", "netherbloom", "nightmare vine",
        "goldclover", "tiger lily", "talandra", "adder", "lichbloom", "icethorn",
        "cinderbloom", "stormvine", "whiptail", "jasmine", "poppy", "saxifrage",
        "hochenblume", "writhebark", "mycobloom", "luredrop", "orboreal", "bush", "arbusto",
    },
    ORE = {
        "vein", "veio", "veta", "deposit", "deposito", "ore", "minerio", "mineral", "seam", "filao", "filon",
        "copper", "cobre", "tin", "estanho", "estano", "silver", "prata", "plata",
        "iron", "ferro", "hierro", "gold", "ouro", "oro", "mithril", "mitril",
        "thorium", "torio", "adamantite", "adamantita", "khorium", "cobalt", "cobalto",
        "saronite", "saronita", "titanium", "titanio", "obsidium", "elementium", "pyrite", "pirita",
        "ghost iron", "trillium", "kyparite", "leystone", "felslate", "monelite", "storm silver",
        "osmenite", "laestrite", "elethium", "solenium", "oxxein", "phaedrum", "sinvyr",
        "serevite", "draconium", "khaz", "bismuth", "aqirite", "ironclaw",
    },
    FISH = {
        "school", "cardume", "banco", "pool", "poca", "bobber", "boia", "flote",
        "wreckage", "destrocos", "restos", "swarm", "enfer", "sagefish", "deviate",
        "firefin", "oily blackmouth", "floating", "fish", "peixe", "pez", "peces",
    },
    TREASURE = {
        "chest", "bau", "cofre", "treasure", "tesouro", "tesoro", "cache", "esconderijo",
        "lockbox", "timber", "madeira", "madera", "lumber", "lenha", "crate", "caixa", "caja",
    },
}

local UTILITY_EXCLUSIONS = {
    "mailbox", "caixa de correio", "correio", "buzon",
    "anvil", "bigorna", "yunque", "forge", "forja", "fragua",
    "campfire", "fogueira", "hoguera", "bonfire",
    "portal", "summoning", "pedra de evocacao", "piedra de invocacion", "meeting stone",
    "chair", "cadeira", "silla", "stool", "banquinho", "bench", "banco",
    "door", "porta", "puerta", "gate", "portao", "verja", "elevator", "elevador",
    "mission table", "mesa de missoes", "command", "bulletin", "mural", "tablon",
    "guild vault", "cofre da guilda", "bank", "flight", "hearth",
}

local function StripLatinAccents(s)
    if type(s) ~= "string" or s == "" then
        return ""
    end
    local lower = (Compat and Compat.LowerUtf8 and Compat.LowerUtf8(s)) or s:lower()
    lower = lower:gsub("á", "a"):gsub("à", "a"):gsub("â", "a"):gsub("ã", "a"):gsub("ä", "a")
    lower = lower:gsub("é", "e"):gsub("ê", "e"):gsub("è", "e"):gsub("ë", "e")
    lower = lower:gsub("í", "i"):gsub("ì", "i"):gsub("î", "i"):gsub("ï", "i")
    lower = lower:gsub("ó", "o"):gsub("ô", "o"):gsub("õ", "o"):gsub("ò", "o"):gsub("ö", "o")
    lower = lower:gsub("ú", "u"):gsub("ù", "u"):gsub("û", "u"):gsub("ü", "u")
    lower = lower:gsub("ç", "c"):gsub("ñ", "n")
    return lower
end

local function ContainsAnyToken(haystackNorm, tokens)
    if not haystackNorm or haystackNorm == "" or not tokens then
        return false
    end
    for i = 1, #tokens do
        if haystackNorm:find(tokens[i], 1, true) then
            return true
        end
    end
    return false
end

local function IsInCombatNow()
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        return true
    end
    return false
end

local function SafeGetCVar(name)
    if not name then return nil end
    if C_CVar and C_CVar.GetCVarInfo then
        local ok, val, _, _, _, isLocked, _, isReadOnly = pcall(C_CVar.GetCVarInfo, name)
        if ok and val ~= nil then
            if isLocked == true or isReadOnly == true then
                return nil
            end
            return tostring(val)
        end
    end
    if C_CVar and C_CVar.GetCVar then
        local ok, val = pcall(C_CVar.GetCVar, name)
        if ok and val ~= nil then
            return tostring(val)
        end
    end
    if GetCVar then
        local ok, val = pcall(GetCVar, name)
        if ok and val ~= nil then
            return tostring(val)
        end
    end
    return nil
end

local function SafeSetCVar(name, value)
    if type(name) ~= "string" or name == "" then
        return false
    end
    -- Hard compliance guard: never touch nameplate* CVars.
    if name:lower():find("^nameplate") then
        return false
    end
    if IsInCombatNow() then
        Gather.pendingCVarSync = true
        return false
    end
    local strVal = tostring(value)
    if C_CVar and C_CVar.SetCVar then
        local ok = pcall(C_CVar.SetCVar, name, strVal)
        return ok == true
    elseif SetCVar then
        local ok = pcall(SetCVar, name, strVal)
        return ok == true
    end
    return false
end

local function SnapshotAndApplySingleCVar(savedMap, name, targetVal)
    local cur = SafeGetCVar(name)
    if cur == nil then
        return
    end
    if savedMap[name] == nil then
        savedMap[name] = cur
    end
    if cur ~= tostring(targetVal) then
        SafeSetCVar(name, targetVal)
    end
end

local function RestoreSavedCVars(s)
    if not (s and type(s.gatherHighlightSavedCVars) == "table") then
        return
    end
    if IsInCombatNow() then
        Gather.pendingCVarSync = true
        return
    end
    for i = 1, #MANAGED_CVAR_NAMES do
        local name = MANAGED_CVAR_NAMES[i]
        local prev = s.gatherHighlightSavedCVars[name]
        if prev ~= nil then
            local cur = SafeGetCVar(name)
            if cur ~= nil and cur ~= tostring(prev) then
                SafeSetCVar(name, prev)
            end
        end
    end
    s.gatherHighlightSavedCVars = nil
end

function Gather:SyncOfficialCVars()
    local s = ns.db and ns.db.settings
    if not s then
        return
    end
    if IsInCombatNow() then
        self.pendingCVarSync = true
        return
    end
    self.pendingCVarSync = false

    local masterOn = (s.gatherHighlightEnabled == true)
    local enhanceOn = masterOn and (s.gatherHighlightEnhanceRange ~= false)
    if not enhanceOn then
        RestoreSavedCVars(s)
        return
    end

    if type(s.gatherHighlightSavedCVars) ~= "table" then
        s.gatherHighlightSavedCVars = {}
    end
    local saved = s.gatherHighlightSavedCVars

    -- Official WoW Soft-Target Interact CVars (gamepad/accessibility world interact icons, nameplate & cone)
    SnapshotAndApplySingleCVar(saved, "SoftTargetInteract", "3")
    SnapshotAndApplySingleCVar(saved, "SoftTargetInteractArc", "2")
    SnapshotAndApplySingleCVar(saved, "SoftTargetInteractRange", "30")
    SnapshotAndApplySingleCVar(saved, "SoftTargetIconInteract", "1")
    SnapshotAndApplySingleCVar(saved, "SoftTargetIconGameObject", "1")
    SnapshotAndApplySingleCVar(saved, "SoftTargetNameplateInteract", "1")

    local curIconSz = SafeGetCVar("SoftTargetIconSize")
    if curIconSz ~= nil then
        if saved["SoftTargetIconSize"] == nil then
            saved["SoftTargetIconSize"] = curIconSz
        end
        if (tonumber(curIconSz) or 0) < 28 then
            SafeSetCVar("SoftTargetIconSize", "28")
        end
    end

    if s.gatherHighlightOutline ~= false then
        local curOutline = SafeGetCVar("Outline")
        if curOutline ~= nil then
            if saved["Outline"] == nil then
                saved["Outline"] = curOutline
            end
            local numOut = tonumber(curOutline) or 0
            if numOut < 2 then
                SafeSetCVar("Outline", "3")
            end
        end
        local curGfxOut = SafeGetCVar("graphicsOutlineMode")
        if curGfxOut ~= nil then
            if saved["graphicsOutlineMode"] == nil then
                saved["graphicsOutlineMode"] = curGfxOut
            end
            if (tonumber(curGfxOut) or 0) <= 0 then
                SafeSetCVar("graphicsOutlineMode", "2")
            end
        end
    else
        -- Restore outline CVars cleanly if only Outline sub-toggle was turned off.
        if saved["Outline"] ~= nil then
            SafeSetCVar("Outline", saved["Outline"])
            saved["Outline"] = nil
        end
        if saved["graphicsOutlineMode"] ~= nil then
            SafeSetCVar("graphicsOutlineMode", saved["graphicsOutlineMode"])
            saved["graphicsOutlineMode"] = nil
        end
    end
end

local function ReadTrackingInfoSafe(idx)
    if C_Minimap and C_Minimap.GetTrackingInfo then
        local ok, r1, r2, r3, r4 = pcall(C_Minimap.GetTrackingInfo, idx)
        if not ok then
            return nil
        end
        if type(r1) == "table" then
            return {
                name = Safe.String(r1.name),
                texture = Safe.Value(r1.texture),
                active = r1.active == true,
                category = Safe.Value(r1.category),
            }
        elseif type(r1) == "string" then
            return {
                name = Safe.String(r1),
                texture = Safe.Value(r2),
                active = r3 == true,
                category = Safe.Value(r4),
            }
        end
    elseif GetTrackingInfo then
        local ok, name, tex, active, cat = pcall(GetTrackingInfo, idx)
        if ok and type(name) == "string" then
            return {
                name = Safe.String(name),
                texture = Safe.Value(tex),
                active = active == true,
                category = Safe.Value(cat),
            }
        end
    end
    return nil
end

local function GetTrackingCountSafe()
    if C_Minimap and C_Minimap.GetNumTrackingTypes then
        local ok, count = pcall(C_Minimap.GetNumTrackingTypes)
        if ok and type(count) == "number" then
            return count
        end
    elseif GetNumTrackingTypes then
        local ok, count = pcall(GetNumTrackingTypes)
        if ok and type(count) == "number" then
            return count
        end
    end
    return 0
end

local function ClassifyTrackingName(name)
    local norm = StripLatinAccents(name)
    if norm == "" then
        return nil
    end
    for i = 1, #TRACKING_CATEGORIES do
        local cat = TRACKING_CATEGORIES[i]
        if ContainsAnyToken(norm, cat.tokens) then
            return cat.kind, cat.fallbackIcon
        end
    end
    return nil
end

local function ClassifyTrackingTexture(tex)
    if tex == nil then
        return nil
    end
    local numTex = tonumber(tex)
    if numTex and CLASSIC_TRACKING_TEXTURES[numTex] then
        local c = CLASSIC_TRACKING_TEXTURES[numTex]
        return c.kind, c.icon, L[c.labelKey]
    end
    if type(tex) == "string" and tex ~= "" then
        local norm = StripLatinAccents(tex)
        if norm:find("flower", 1, true) or norm:find("herb", 1, true) then
            return "HERB", tex, L["Herb"]
        elseif norm:find("earthquake", 1, true) or norm:find("mining", 1, true) or norm:find("mineral", 1, true) then
            return "ORE", tex, L["Mineral / Ore"]
        elseif norm:find("fish", 1, true) then
            return "FISH", tex, L["Fishing Pool"]
        elseif norm:find("treasure", 1, true) then
            return "TREASURE", tex, L["Treasure / Resource"]
        end
    end
    return nil
end

function Gather:HasAnyActiveProfTracking()
    for _, entry in pairs(self.activeProfTracking) do
        if entry and entry.active then
            return true
        end
    end
    return false
end

function Gather:GetSingleActiveTrackingKind()
    local foundKind = nil
    for _, entry in pairs(self.activeProfTracking) do
        if entry and entry.active and entry.kind then
            if foundKind and foundKind ~= entry.kind then
                return nil
            end
            foundKind = entry.kind
        end
    end
    return foundKind
end

function Gather:ScanProfessionTracking(promptMode)
    -- promptMode: "new_only" | "any_active" | "baseline"
    local count = GetTrackingCountSafe()
    local nextActive = {}
    local newlyActivated = nil
    local firstActive = nil

    for i = 1, count do
        local info = ReadTrackingInfoSafe(i)
        if info and info.name and info.name ~= "" then
            local kind, fallbackIcon = ClassifyTrackingName(info.name)
            if not kind and info.texture then
                kind, fallbackIcon = ClassifyTrackingTexture(info.texture)
            end
            if kind then
                local key = StripLatinAccents(info.name)
                if info.active then
                    local rec = {
                        kind = kind,
                        name = info.name,
                        texture = info.texture or fallbackIcon,
                        active = true,
                    }
                    nextActive[key] = rec
                    if not firstActive then
                        firstActive = rec
                    end
                    if promptMode == "new_only" and self.baselineTrackingCaptured and not self.activeProfTracking[key] and not newlyActivated then
                        newlyActivated = rec
                    end
                end
            end
        end
    end

    -- Forever / Classic fallback: single active spell-based tracking texture (e.g. Find Herbs / Find Minerals)
    if GetTrackingTexture then
        local okTex, rawTex = pcall(GetTrackingTexture)
        if okTex and rawTex ~= nil then
            local texVal = Safe.Value(rawTex)
            local cKind, cIcon, cLabel = ClassifyTrackingTexture(texVal)
            if cKind then
                local tKey = "classic:" .. cKind
                local rec = {
                    kind = cKind,
                    name = cLabel or L["Resource Tracking"],
                    texture = cIcon,
                    active = true,
                }
                nextActive[tKey] = rec
                if not firstActive then
                    firstActive = rec
                end
                if promptMode == "new_only" and self.baselineTrackingCaptured and not self.activeProfTracking[tKey] and not newlyActivated then
                    newlyActivated = rec
                end
            end
        end
    end

    -- Fallback 2: MiniMapTrackingIcon texture (for Forever UI variants showing classic tracking icon directly)
    local mmTrackIco = _G.MiniMapTrackingIcon
    if mmTrackIco and mmTrackIco.IsShown and mmTrackIco.GetTexture then
        local okVis, vis = pcall(mmTrackIco.IsShown, mmTrackIco)
        if okVis and vis then
            local okT, rawT = pcall(mmTrackIco.GetTexture, mmTrackIco)
            if okT and rawT ~= nil then
                local cKind, cIcon, cLabel = ClassifyTrackingTexture(Safe.Value(rawT))
                if cKind then
                    local tKey = "classic:" .. cKind
                    if not nextActive[tKey] then
                        local rec = {
                            kind = cKind,
                            name = cLabel or L["Resource Tracking"],
                            texture = cIcon,
                            active = true,
                        }
                        nextActive[tKey] = rec
                        if not firstActive then
                            firstActive = rec
                        end
                        if promptMode == "new_only" and self.baselineTrackingCaptured and not self.activeProfTracking[tKey] and not newlyActivated then
                            newlyActivated = rec
                        end
                    end
                end
            end
        end
    end

    -- Fallback 3: Player aura scan for tracking spells (2383 Herbs, 2580 Minerals, 43308 Fish, 2481 Treasure)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for spId, spMeta in pairs(TRACKING_SPELL_IDS) do
            local okA, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spId)
            if okA and type(auraData) == "table" then
                local tKey = "classic:" .. spMeta.kind
                if not nextActive[tKey] then
                    local spName = Safe.String(auraData.name)
                    if (not spName or spName == "") and C_Spell and C_Spell.GetSpellName then
                        local okN, sn = pcall(C_Spell.GetSpellName, spId)
                        if okN then spName = Safe.String(sn) end
                    end
                    local rec = {
                        kind = spMeta.kind,
                        name = (spName and spName ~= "") and spName or L[spMeta.labelKey],
                        texture = Safe.Value(auraData.icon) or spMeta.icon,
                        active = true,
                    }
                    nextActive[tKey] = rec
                    if not firstActive then
                        firstActive = rec
                    end
                    if promptMode == "new_only" and self.baselineTrackingCaptured and not self.activeProfTracking[tKey] and not newlyActivated then
                        newlyActivated = rec
                    end
                end
            end
        end
    end

    self.activeProfTracking = nextActive
    self.baselineTrackingCaptured = true

    if promptMode == "new_only" and newlyActivated then
        self:MaybePromptFromTracking(newlyActivated)
    elseif promptMode == "any_active" and firstActive then
        self:MaybePromptFromTracking(firstActive)
    end
end

function Gather:HandleTrackingSpellCast(spellID)
    if type(spellID) ~= "number" then
        return
    end
    local info = TRACKING_SPELL_IDS[spellID]
    local spellName = nil
    if C_Spell and C_Spell.GetSpellName then
        local okN, sn = pcall(C_Spell.GetSpellName, spellID)
        if okN then
            spellName = Safe.String(sn)
        end
    end
    local kind = info and info.kind
    local fallbackIcon = info and info.icon
    if not kind and spellName then
        kind, fallbackIcon = ClassifyTrackingName(spellName)
    end
    if not kind then
        return
    end
    local rec = {
        kind = kind,
        name = spellName or (info and L[info.labelKey]) or L["Resource Tracking"],
        texture = fallbackIcon or "Interface\\Icons\\Trade_Herbalism",
        active = true,
    }
    self.activeProfTracking["classic:" .. kind] = rec
    self:MaybePromptFromTracking(rec)
end

function Gather:MaybePromptFromTracking(trackInfo)
    local s = ns.db and ns.db.settings
    if not s or not trackInfo then
        return
    end
    if s.gatherHighlightEnabled == true or s.gatherHighlightPromptAnswered == true then
        return
    end
    if self.sessionPromptSnoozed then
        return
    end
    local now = (GetTime and GetTime()) or 0
    if self._lastPromptEmitAt and (now - self._lastPromptEmitAt) < 0.5 then
        return
    end
    if IsInCombatNow() then
        self.pendingPrompt = trackInfo
        return
    end
    self._lastPromptEmitAt = now
    self.pendingPrompt = nil
    ns:Emit("GATHER_PROMPT_REQUESTED", trackInfo)
end

function Gather:SetEnabled(enabled, markAnswered)
    local s = ns.db and ns.db.settings
    if not s then
        return
    end
    local on = (enabled == true)
    s.gatherHighlightEnabled = on
    if markAnswered == true then
        s.gatherHighlightPromptAnswered = true
    end
    self:SyncOfficialCVars()
    self:RefreshSoftInteractNode()
    ns:Emit("SETTINGS_UPDATED")
end

function Gather:DismissPrompt(permanent)
    if permanent then
        if ns.db and ns.db.settings then
            ns.db.settings.gatherHighlightPromptAnswered = true
        end
        if SocialCentralDB and type(SocialCentralDB.settings) == "table" then
            SocialCentralDB.settings.gatherHighlightPromptAnswered = true
        end
    else
        self.sessionPromptSnoozed = true
    end
end

local function ClassifyNodeObject(name)
    local norm = StripLatinAccents(name)
    if norm == "" then
        return nil
    end
    if ContainsAnyToken(norm, UTILITY_EXCLUSIONS) then
        return nil
    end
    if ContainsAnyToken(norm, NODE_KEYWORDS.HERB) then
        return "HERB", "Interface\\Icons\\Trade_Herbalism", L["Herb"]
    end
    if ContainsAnyToken(norm, NODE_KEYWORDS.ORE) then
        return "ORE", "Interface\\Icons\\Trade_Mining", L["Mineral / Ore"]
    end
    if ContainsAnyToken(norm, NODE_KEYWORDS.FISH) then
        return "FISH", "Interface\\Icons\\Trade_Fishing", L["Fishing Pool"]
    end
    if ContainsAnyToken(norm, NODE_KEYWORDS.TREASURE) then
        return "TREASURE", "Interface\\Icons\\INV_Misc_Map_01", L["Treasure / Resource"]
    end

    -- Fallback: when the player has one specific profession tracker on, highlight generic interactable objects
    local inferredKind = Gather:GetSingleActiveTrackingKind()
    if inferredKind == "HERB" then
        return "HERB", "Interface\\Icons\\Trade_Herbalism", L["Herb"]
    elseif inferredKind == "ORE" then
        return "ORE", "Interface\\Icons\\Trade_Mining", L["Mineral / Ore"]
    elseif inferredKind == "FISH" then
        return "FISH", "Interface\\Icons\\Trade_Fishing", L["Fishing Pool"]
    elseif inferredKind == "TREASURE" or Gather:HasAnyActiveProfTracking() then
        return "OBJECT", "Interface\\Icons\\INV_Misc_Spyglass_03", L["Collectible"]
    end
    return nil
end

local function MaybePlaySpotSound(category)
    local s = ns.db and ns.db.settings
    if not s or s.gatherHighlightSound ~= true then
        return
    end
    if category == "OBJECT" then
        return
    end
    if Compat and Compat.IsFocusSilenced and Compat.IsFocusSilenced() then
        return
    end
    local now = (GetTime and GetTime()) or 0
    if (now - (Gather.lastSoundAt or 0)) < PLAY_SOUND_COOLDOWN then
        return
    end
    Gather.lastSoundAt = now
    if PlaySound then
        pcall(PlaySound, ALERT_SOUND_ID, "SFX")
    end
end

function Gather:RefreshSoftInteractNode(eventNewGuid)
    local s = ns.db and ns.db.settings
    if not s or s.gatherHighlightEnabled ~= true then
        if self.activeNode ~= nil then
            self.activeNode = nil
            ns:Emit("GATHER_NODE_CHANGED", nil)
        end
        return
    end

    local guid = Safe.String(Safe.Call(UnitGUID, "softinteract"))
    if (not guid or guid == "") and type(eventNewGuid) == "string" and eventNewGuid ~= "" then
        guid = Safe.String(eventNewGuid)
    elseif (not guid or guid == "") and type(self.lastEventGuid) == "string" and self.lastEventGuid ~= "" then
        guid = self.lastEventGuid
    end
    local name = Safe.String(Safe.Call(UnitName, "softinteract"))
    if name == UNKNOWNOBJECT or name == "" then
        name = nil
    end
    local exists = Safe.Value(Safe.Call(UnitExists, "softinteract")) == true
    local isWorldObject = (guid ~= nil and (guid:find("^GameObject%-") ~= nil or guid:find("^Object%-") ~= nil))

    if not exists and not isWorldObject and not guid then
        if self.activeNode ~= nil then
            self.activeNode = nil
            ns:Emit("GATHER_NODE_CHANGED", nil)
        end
        return
    end

    -- Never treat players, hostile enemies, friendly players/NPCs, or Creatures as collectible nodes.
    if Safe.Value(Safe.Call(UnitIsPlayer, "softinteract")) == true then
        if self.activeNode ~= nil then
            self.activeNode = nil
            ns:Emit("GATHER_NODE_CHANGED", nil)
        end
        return
    end
    if guid then
        if guid:find("^Player%-") or guid:find("^Creature%-") or guid:find("^Pet%-") or guid:find("^Vehicle%-") then
            if self.activeNode ~= nil then
                self.activeNode = nil
                ns:Emit("GATHER_NODE_CHANGED", nil)
            end
            return
        end
    end
    if Safe.Value(Safe.Call(UnitCanAttack, "player", "softinteract")) == true or Safe.Value(Safe.Call(UnitIsFriend, "player", "softinteract")) == true then
        if self.activeNode ~= nil then
            self.activeNode = nil
            ns:Emit("GATHER_NODE_CHANGED", nil)
        end
        return
    end

    local category, icon, catLabel = nil, nil, nil
    if name then
        category, icon, catLabel = ClassifyNodeObject(name)
    elseif isWorldObject then
        local inferredKind = Gather:GetSingleActiveTrackingKind()
        if inferredKind == "HERB" then
            category, icon, catLabel = "HERB", "Interface\\Icons\\Trade_Herbalism", L["Herb"]
        elseif inferredKind == "ORE" then
            category, icon, catLabel = "ORE", "Interface\\Icons\\Trade_Mining", L["Mineral / Ore"]
        elseif inferredKind == "FISH" then
            category, icon, catLabel = "FISH", "Interface\\Icons\\Trade_Fishing", L["Fishing Pool"]
        else
            category, icon, catLabel = "OBJECT", "Interface\\Icons\\INV_Misc_Spyglass_03", L["Collectible"]
        end
    end

    if not category then
        if self.activeNode ~= nil then
            self.activeNode = nil
            ns:Emit("GATHER_NODE_CHANGED", nil)
        end
        return
    end

    local plate = nil
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local okPl, pl = pcall(C_NamePlate.GetNamePlateForUnit, "softinteract")
        if okPl and pl then
            plate = pl
        end
    end

    local displayName = name or catLabel or L["Collectible"]
    local node = {
        guid = guid or ("name:" .. displayName),
        name = displayName,
        category = category,
        icon = icon,
        categoryLabel = catLabel,
        plate = plate,
    }

    local isNewNode = (self.lastAnnouncedGuid ~= node.guid)
    if isNewNode then
        self.lastAnnouncedGuid = node.guid
        MaybePlaySpotSound(category)
    end

    self.activeNode = node
    ns:Emit("GATHER_NODE_CHANGED", node)

    -- GameObject names sometimes populate one frame after PLAYER_SOFT_INTERACT_CHANGED fires.
    if not name and C_Timer and C_Timer.After then
        local retryGuid = node.guid
        C_Timer.After(0.08, function()
            if Gather.activeNode and Gather.activeNode.guid == retryGuid then
                local lateName = Safe.String(Safe.Call(UnitName, "softinteract"))
                if lateName and lateName ~= "" and lateName ~= UNKNOWNOBJECT then
                    Gather:RefreshSoftInteractNode(retryGuid)
                end
            end
        end)
    end
end

function Gather:SyncUnitAndNodeEvents()
    local s = ns.db and ns.db.settings
    local enabled = (s ~= nil and s.gatherHighlightEnabled == true)
    local needPromptEvents = (not enabled) and (not (s and s.gatherHighlightPromptAnswered == true))

    if self._evtFrame then
        if enabled then
            if not self._nodeEventsActive then
                self._nodeEventsActive = true
                pcall(self._evtFrame.RegisterEvent, self._evtFrame, "PLAYER_SOFT_INTERACT_CHANGED")
                pcall(self._evtFrame.RegisterEvent, self._evtFrame, "NAME_PLATE_UNIT_ADDED")
                pcall(self._evtFrame.RegisterEvent, self._evtFrame, "NAME_PLATE_UNIT_REMOVED")
            end
        elseif self._nodeEventsActive then
            self._nodeEventsActive = false
            pcall(self._evtFrame.UnregisterEvent, self._evtFrame, "PLAYER_SOFT_INTERACT_CHANGED")
            pcall(self._evtFrame.UnregisterEvent, self._evtFrame, "NAME_PLATE_UNIT_ADDED")
            pcall(self._evtFrame.UnregisterEvent, self._evtFrame, "NAME_PLATE_UNIT_REMOVED")
        end
    end

    if self._unitEvtFrame then
        if needPromptEvents then
            if not self._promptUnitEventsActive then
                self._promptUnitEventsActive = true
                if self._unitEvtFrame.RegisterUnitEvent then
                    pcall(self._unitEvtFrame.RegisterUnitEvent, self._unitEvtFrame, "UNIT_AURA", "player")
                    pcall(self._unitEvtFrame.RegisterUnitEvent, self._unitEvtFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
                else
                    pcall(self._unitEvtFrame.RegisterEvent, self._unitEvtFrame, "UNIT_AURA")
                    pcall(self._unitEvtFrame.RegisterEvent, self._unitEvtFrame, "UNIT_SPELLCAST_SUCCEEDED")
                end
            end
        elseif self._promptUnitEventsActive then
            self._promptUnitEventsActive = false
            pcall(self._unitEvtFrame.UnregisterAllEvents, self._unitEvtFrame)
        end
    end
end

function Gather:Init()
    if self.initialized then
        return
    end
    self.initialized = true

    local evtFrame = CreateFrame("Frame")
    evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    evtFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    evtFrame:RegisterEvent("MINIMAP_UPDATE_TRACKING")
    evtFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self._evtFrame = evtFrame

    local unitEvtFrame = CreateFrame("Frame")
    self._unitEvtFrame = unitEvtFrame
    unitEvtFrame:SetScript("OnEvent", function(_, event, arg1, _, arg3)
        if arg1 ~= "player" then
            return
        end
        if event == "UNIT_AURA" then
            local sCfg = ns.db and ns.db.settings
            if sCfg and sCfg.gatherHighlightEnabled ~= true and sCfg.gatherHighlightPromptAnswered ~= true and not Gather.sessionPromptSnoozed then
                Gather:ScanProfessionTracking("new_only")
            end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            Gather:HandleTrackingSpellCast(arg3)
        end
    end)

    evtFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "PLAYER_ENTERING_WORLD" then
            Gather:SyncUnitAndNodeEvents()
            Gather:SyncOfficialCVars()
            Gather.lastAnnouncedGuid = nil
            Gather.lastEventGuid = nil
            Gather:RefreshSoftInteractNode()
            if C_Timer and C_Timer.After then
                C_Timer.After(1.2, function()
                    Gather:ScanProfessionTracking("any_active")
                    Gather:RefreshSoftInteractNode()
                end)
            else
                Gather:ScanProfessionTracking("any_active")
                Gather:RefreshSoftInteractNode()
            end
        elseif event == "ZONE_CHANGED_NEW_AREA" then
            Gather.lastAnnouncedGuid = nil
            Gather.lastEventGuid = nil
            Gather:RefreshSoftInteractNode()
        elseif event == "MINIMAP_UPDATE_TRACKING" then
            Gather:ScanProfessionTracking("new_only")
        elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
            Gather.lastEventGuid = (type(arg2) == "string" and arg2 ~= "") and Safe.String(arg2) or nil
            Gather:RefreshSoftInteractNode(Gather.lastEventGuid)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            if C_NamePlate and C_NamePlate.GetNamePlateForUnit and ns.GatherHighlightUI and ns.GatherHighlightUI.HidePlateIfBound then
                local okPl, pl = pcall(C_NamePlate.GetNamePlateForUnit, arg1)
                if okPl and pl then
                    ns.GatherHighlightUI:HidePlateIfBound(pl)
                end
            end
            if ns.db and ns.db.settings and ns.db.settings.gatherHighlightEnabled == true and arg1 == "softinteract" then
                Gather:RefreshSoftInteractNode()
            end
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            if ns.db and ns.db.settings and ns.db.settings.gatherHighlightEnabled == true then
                if arg1 == "softinteract" or (Gather.activeNode and Gather.activeNode.guid and Safe.String(Safe.Call(UnitGUID, arg1)) == Gather.activeNode.guid) then
                    Gather:RefreshSoftInteractNode()
                end
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if Gather.pendingCVarSync then
                Gather:SyncOfficialCVars()
            end
            if Gather.pendingPrompt then
                local pend = Gather.pendingPrompt
                Gather.pendingPrompt = nil
                Gather:MaybePromptFromTracking(pend)
            end
        end
    end)

    self:SyncUnitAndNodeEvents()

    ns:On("SETTINGS_UPDATED", function()
        Gather:SyncUnitAndNodeEvents()
        Gather:SyncOfficialCVars()
        Gather:RefreshSoftInteractNode()
    end)
end
