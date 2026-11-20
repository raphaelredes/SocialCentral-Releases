local _, ns = ...

local L = ns.L
local Compat = ns.Compat

local SettingsMod = {}
ns.Settings = SettingsMod

local panel
local panelBuilt = false
local category
local syncFns = {}
local activeCategoryTab = "overview"
local selectCategoryTabFn

-- ============================================================================
-- Professional Settings Search Engine (Multi-Tab, Accent-Insensitive, Live Edit)
-- ============================================================================
local Search = {
    entries = {},
    tabFilter = "all", -- "all" | "overview" | "notifications" | "radar" | "general"
    query = "",
    lastMatches = {},
    cardPool = {},
    filterBtns = {},
    emptyChips = {},
    buildTabId = "overview",
    buildTabLabel = "",
    buildTabOrder = 1,
    buildSectionTitle = "",
    buildSectionHelp = nil,
    pendingMeta = nil,
    searchPage = nil,
    searchBox = nil,
    countLbl = nil,
    beaconFrame = nil,
    scrollFrame = nil,
    pages = nil,
    content = nil,
    pageHeights = nil,
    catButtons = nil,
    tabOrderMap = { overview = 1, notifications = 2, radar = 3, general = 4 },
    tabColors = {
        overview      = { 0.35, 0.72, 1.00 },
        notifications = { 0.96, 0.76, 0.24 },
        radar         = { 0.96, 0.42, 0.32 },
        general       = { 0.30, 0.84, 0.62 },
    },
    maxRender = 42,
}

Search.ACCENT_MAP = {
    ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a",
    ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Ä"] = "a",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
    ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i",
    ["Í"] = "i", ["Ì"] = "i", ["Î"] = "i", ["Ï"] = "i",
    ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o",
    ["Ó"] = "o", ["Ò"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ö"] = "o",
    ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
    ["Ú"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
    ["ç"] = "c", ["Ç"] = "c", ["ñ"] = "n", ["Ñ"] = "n",
}

Search.SYNONYM_GROUPS = {
    { "whisper", "whispers", "sussurro", "sussurros", "susurro", "susurros", "pm", "dm", "tell", "direct", "direto", "directo" },
    { "bnet", "battlenet", "battle", "realid", "blizzard" },
    { "sound", "sounds", "som", "sons", "sonido", "sonidos", "audio", "chime", "campainha", "beep", "timbre" },
    { "mute", "muted", "mudo", "silenciar", "silencio", "silenced", "silenciado", "calado", "quiet", "pausar", "pause" },
    { "dungeon", "dungeons", "masmorra", "masmorras", "mazmorra", "mazmorras", "dg", "dng", "instancia", "instancias", "instance", "instances", "estancia" },
    { "raid", "raids", "raide", "raides", "banda", "bandas", "boss", "chefe" },
    { "pvp", "bg", "bgs", "arena", "arenas", "battleground", "battlegrounds", "batalha", "batalla", "jcj" },
    { "combat", "combate", "luta", "fight", "pelea" },
    { "minimap", "minimapa", "mini", "botao", "button", "boton", "icone", "icon", "icono" },
    { "preview", "previews", "previa", "previas", "vista", "capsula", "capsule", "fila", "queue", "cola" },
    { "toast", "toasts", "popup", "popups", "alerta", "alertas", "alert", "alerts", "aviso", "avisos", "notificacao", "notificacoes", "notification", "notifications", "notificacion" },
    { "guild", "guilda", "guildas", "hermandad", "cla", "clan", "oficial", "oficiais", "officer", "alianca", "alianza", "alliance", "diplomacia", "diplomacy", "evento", "event" },
    { "group", "grupo", "party", "lfg", "lfm", "localizador", "buscador", "finder", "companheiro", "companion", "companero" },
    { "radar", "spotter", "alvo", "alvos", "target", "targets", "objetivo", "seta", "arrow", "flecha", "plaqueta", "plaquetas", "nameplate", "nameplates", "placa", "inimigo", "enemy", "enemigo", "aliado", "ally" },
    { "buff", "buffs", "worldbuff", "world", "mundo", "mapa", "map", "pino", "pinos", "pin", "pins", "onyxia", "nefarian", "rend", "hakkar", "cronobencao" },
    { "theme", "tema", "skin", "visual", "aparencia", "apariencia", "cor", "cores", "color", "escuro", "dark", "moderno", "modern", "dourado", "gold", "oro" },
    { "language", "idioma", "lingua", "lengua", "portugues", "ptbr", "ingles", "english", "espanhol", "espanol", "traducao", "reload", "recarregar" },
    { "shortcut", "shortcuts", "atalho", "atalhos", "atajo", "atajos", "tecla", "janela", "janelas", "window", "windows", "ventana", "aba", "abas", "tab", "tabs", "pestana", "embutir", "embed", "integracao" },
    { "profile", "perfil", "conta", "account", "cuenta", "personagem", "character", "personaje", "preset", "predefinicao", "padrao", "default", "reset", "redefinir", "restaurar" },
    { "dnd", "perturbe", "disturb", "molestar", "foco", "focus" },
    { "alt", "alts", "ouro", "gold", "oro", "mochila", "bag", "bags", "banco", "bank", "item", "itens", "items", "inventario", "tooltip", "tooltips", "dica", "dicas", "nota", "notas", "note", "notes" },
    { "watchlist", "who", "cooldown", "recarga", "nearby", "perto", "cerca", "evitar", "avoid", "bloqueado", "blocked", "ignore", "ignorar", "amigo", "amigos", "friend", "friends", "favorito", "favorites" },
    { "chat", "conversa", "conversas", "conversations", "conversacion", "sala", "salas", "room", "rooms", "mensagem", "mensagens", "message", "messages", "mensaje", "historico", "history", "espelhar", "mirror", "eco", "echo", "spam", "boost", "wts", "update", "atualizacao", "versao", "version", "github" },
}

Search.synonymLookup = {}
for _, grp in ipairs(Search.SYNONYM_GROUPS) do
    for _, word in ipairs(grp) do
        local list = Search.synonymLookup[word]
        if not list then
            list = {}
            Search.synonymLookup[word] = list
        end
        for _, sibling in ipairs(grp) do
            if sibling ~= word then
                list[#list + 1] = sibling
            end
        end
    end
end

function Search.Fold(text)
    if type(text) ~= "string" or text == "" then
        return ""
    end
    local s = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("[%z\1-\127\194-\244][\128-\191]*", function(ch)
        return Search.ACCENT_MAP[ch] or ch
    end)
    s = s:lower()
    local spaced = s:gsub("[^%w]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    return spaced
end

function Search.ExpandSynonyms(tok)
    local out = {}
    local seen = { [tok] = true }
    local direct = Search.synonymLookup[tok]
    if direct then
        for _, sib in ipairs(direct) do
            if not seen[sib] then
                seen[sib] = true
                out[#out + 1] = sib
            end
        end
    end
    if #tok >= 3 then
        for key, sibs in pairs(Search.synonymLookup) do
            if key:sub(1, #tok) == tok and key ~= tok then
                if not seen[key] then
                    seen[key] = true
                    out[#out + 1] = key
                end
                for _, sib in ipairs(sibs) do
                    if not seen[sib] then
                        seen[sib] = true
                        out[#out + 1] = sib
                    end
                end
            end
        end
    end
    return out
end

function Search.SetBuildContext(tabId, tabLabel, tabOrder)
    Search.buildTabId = tabId
    Search.buildTabLabel = tabLabel or tabId
    Search.buildTabOrder = tabOrder or 1
    Search.buildSectionTitle = tabLabel or ""
    Search.buildSectionHelp = nil
    Search.pendingMeta = nil
end

function Search.SetPendingMeta(title, helpTitle, helpWhat, helpHow)
    Search.pendingMeta = {
        title = title,
        helpTitle = helpTitle,
        description = helpWhat,
        howText = helpHow,
    }
end

function Search.Register(spec)
    if type(spec) ~= "table" or not spec.title or spec.title == "" then
        return
    end
    local entry = {
        id = #Search.entries + 1,
        tabId = spec.tabId or Search.buildTabId,
        tabLabel = spec.tabLabel or Search.buildTabLabel,
        tabOrder = spec.tabOrder or Search.buildTabOrder,
        sectionTitle = spec.sectionTitle or Search.buildSectionTitle or "",
        kind = spec.kind or "checkbox",
        title = spec.title,
        description = spec.description or "",
        howText = spec.howText or "",
        helpTitle = spec.helpTitle or spec.title,
        widget = spec.widget,
        getter = spec.getter,
        setter = spec.setter,
        options = spec.options,
        minVal = spec.minVal,
        maxVal = spec.maxVal,
        unit = spec.unit,
        step = spec.step,
        actionLabel = spec.actionLabel,
        onTrigger = spec.onTrigger,
        extraKeywords = spec.extraKeywords or "",
    }
    local optLabels = {}
    if type(entry.options) == "table" then
        for _, opt in ipairs(entry.options) do
            if opt and opt.label then
                optLabels[#optLabels + 1] = tostring(opt.label)
            end
        end
    end
    local optStr = table.concat(optLabels, " ")
    entry.foldTitle = " " .. Search.Fold(entry.title) .. " "
    entry.foldSection = " " .. Search.Fold(entry.sectionTitle .. " " .. entry.tabLabel) .. " "
    entry.foldOptions = " " .. Search.Fold(optStr) .. " "
    entry.foldDesc = " " .. Search.Fold(entry.description .. " " .. entry.extraKeywords) .. " "
    entry.foldHow = " " .. Search.Fold(entry.howText) .. " "
    entry.compactAll = (entry.foldTitle .. entry.foldSection .. entry.foldOptions .. entry.foldDesc):gsub("%s+", "")
    Search.entries[#Search.entries + 1] = entry
    return entry
end

function Search.IsEntryModuleEnabled(entry)
    local modKey = entry and entry.widget and entry.widget._scDepMod
    if not modKey then return true end
    local s = ns.db and ns.db.settings
    if not s then return true end
    if modKey == "wb" then return s.embedWorldMap ~= false
    elseif modKey == "radar" then return s.spotterEnabled ~= false
    elseif modKey == "guild" then return (not Compat or not Compat.IsWindowIntegrationEnabled) or Compat.IsWindowIntegrationEnabled("J")
    elseif modKey == "lfg" then return s.embedLfgWindow ~= false
    elseif modKey == "social" then return s.embedSocialWindow ~= false
    elseif modKey == "alts" then return s.embedCharacterWindow ~= false
    elseif modKey == "watch" then return s.moduleWatchlistEnabled ~= false
    elseif modKey == "nearby" then return s.moduleNearbyEnabled ~= false
    elseif modKey == "chat" then return s.moduleChatEnabled ~= false
    end
    return true
end

function Search.ScoreEntry(entry, tokens, synTable)
    local total = 0
    for i = 1, #tokens do
        local tok = tokens[i]
        local tokScore = 0
        if entry.foldTitle:find(" " .. tok, 1, true) then
            tokScore = (entry.foldTitle:sub(2, 1 + #tok) == tok) and 120 or 85
        elseif entry.foldTitle:find(tok, 1, true) then
            tokScore = 58
        elseif entry.foldOptions:find(tok, 1, true) then
            tokScore = 44
        elseif entry.foldSection:find(tok, 1, true) then
            tokScore = 36
        elseif entry.foldDesc:find(tok, 1, true) then
            tokScore = 26
        elseif entry.foldHow:find(tok, 1, true) then
            tokScore = 16
        elseif #tok >= 4 and entry.compactAll:find(tok, 1, true) then
            tokScore = 32
        else
            local sibs = synTable[i]
            if sibs then
                for _, sib in ipairs(sibs) do
                    if entry.foldTitle:find(" " .. sib, 1, true) then
                        tokScore = math.max(tokScore, 30)
                        break
                    elseif entry.foldSection:find(" " .. sib, 1, true) or entry.foldOptions:find(" " .. sib, 1, true) then
                        tokScore = math.max(tokScore, 20)
                    elseif entry.foldDesc:find(" " .. sib, 1, true) then
                        tokScore = math.max(tokScore, 12)
                    end
                end
            end
        end
        if tokScore == 0 then
            return 0
        end
        total = total + tokScore
    end
    if entry.kind == "checkbox" or entry.kind == "choice" or entry.kind == "stepper" then
        total = total + 10
    end
    return total
end

function Search.HighlightTitle(rawText, tokens)
    if type(rawText) ~= "string" or rawText == "" or not tokens or #tokens == 0 then
        return rawText or ""
    end
    local clean = rawText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    -- Build accent-folded ASCII mirror with exact UTF-8 byte bounds so "previa" highlights "Prévia" cleanly
    local foldedChars = {}
    local origStarts = {}
    local origEnds = {}
    local pos = 1
    local len = #clean
    while pos <= len do
        local b = clean:byte(pos)
        local charLen = 1
        if b >= 240 then charLen = 4
        elseif b >= 224 then charLen = 3
        elseif b >= 192 then charLen = 2
        end
        local ch = clean:sub(pos, pos + charLen - 1)
        local mapped = Search.ACCENT_MAP[ch] or ch:lower()
        local idx = #foldedChars + 1
        foldedChars[idx] = mapped:sub(1, 1)
        origStarts[idx] = pos
        origEnds[idx] = pos + charLen - 1
        pos = pos + charLen
    end
    local foldedStr = table.concat(foldedChars)
    local bestStart, bestEnd
    for _, tok in ipairs(tokens) do
        if #tok >= 2 then
            local s, e = foldedStr:find(tok, 1, true)
            if s and (not bestStart or s < bestStart) then
                bestStart, bestEnd = s, e
            end
        end
    end
    if not bestStart or not origStarts[bestStart] or not origEnds[bestEnd] then
        return clean
    end
    local bStart = origStarts[bestStart]
    local bEnd = origEnds[bestEnd]
    return clean:sub(1, bStart - 1) .. "|cffffd24d" .. clean:sub(bStart, bEnd) .. "|r" .. clean:sub(bEnd + 1)
end

function Search.StopBeacon()
    if Search.beaconFrame then
        Search.beaconFrame:SetScript("OnUpdate", nil)
        Search.beaconFrame:Hide()
    end
end

function Search.LocateEntry(entry)
    if not entry then return end
    if Search.searchBox then
        Search.searchBox:SetText("")
        Search.searchBox:ClearFocus()
    end
    Search.query = ""
    Search.tabFilter = "all"
    if selectCategoryTabFn then
        selectCategoryTabFn(entry.tabId)
    end
    local targetWidget = entry.widget
    local targetPage = Search.pages and Search.pages[entry.tabId]
    local sf = Search.scrollFrame
    if not (targetWidget and targetPage and sf) then
        return
    end
    local function ScrollAndPulse()
        if not (targetPage:IsShown() and targetWidget.GetTop and targetPage.GetTop) then
            return
        end
        local pTop = targetPage:GetTop()
        local wTop = targetWidget:GetTop()
        if pTop and wTop then
            local relY = pTop - wTop
            local maxRange = (sf.GetVerticalScrollRange and sf:GetVerticalScrollRange()) or 0
            local destScroll = math.max(0, math.min(maxRange, relY - 68))
            if sf.SetVerticalScroll then
                sf:SetVerticalScroll(destScroll)
            end
        end
        if targetWidget.GetObjectType and targetWidget:GetObjectType() == "EditBox" and targetWidget.SetFocus then
            pcall(targetWidget.SetFocus, targetWidget)
        end
        local b = Search.beaconFrame
        if not b then
            b = CreateFrame("Frame", nil, targetPage, "BackdropTemplate")
            b:EnableMouse(false)
            if b.SetBackdrop then
                b:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = 2,
                })
            end
            Search.beaconFrame = b
        end
        b:SetParent(targetPage)
        b:SetFrameLevel(math.max((targetWidget.GetFrameLevel and targetWidget:GetFrameLevel() or 5) + 12, 24))
        b:ClearAllPoints()
        local rightTarget = (targetWidget._scLabel and targetWidget._scLabel.GetRight and targetWidget._scLabel) or targetWidget
        b:SetPoint("TOPLEFT", targetWidget, "TOPLEFT", -6, 5)
        b:SetPoint("BOTTOMRIGHT", rightTarget, "BOTTOMRIGHT", 12, -5)
        if b.SetBackdropColor then
            b:SetBackdropColor(1.0, 0.82, 0.22, 0.16)
            b:SetBackdropBorderColor(1.0, 0.84, 0.24, 0.96)
        end
        b:SetAlpha(1)
        b:Show()
        local elapsed = 0
        local dur = 2.4
        b:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + (dt or 0)
            if elapsed >= dur or not targetPage:IsShown() then
                Search.StopBeacon()
                return
            end
            local wave = 0.55 + 0.45 * math.sin(elapsed * 9.0)
            local fade = (elapsed > 1.7) and (1 - ((elapsed - 1.7) / 0.7)) or 1.0
            self:SetAlpha(math.max(0, math.min(1, wave * fade)))
        end)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, ScrollAndPulse)
    else
        ScrollAndPulse()
    end
end

function Search.EnsureCard(index)
    if Search.cardPool[index] then
        return Search.cardPool[index]
    end
    local parent = Search.searchPage
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(580, 74)
    card:EnableMouse(false)
    card:Hide()

    local accentBar = card:CreateTexture(nil, "OVERLAY", nil, 2)
    accentBar:SetWidth(3)
    accentBar:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
    accentBar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 2, 2)
    card.accentBar = accentBar

    local locateBtn = ns.Theme:CreateButton(card, 74, 20, L["Go to"], "default")
    ns.Theme:AutoFitButton(locateBtn, 58, 14, 110)
    locateBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -7)
    locateBtn:SetScript("OnClick", function()
        if card._entry then
            Search.LocateEntry(card._entry)
        end
    end)
    card.locateBtn = locateBtn

    local helpBtn = ns.Theme:CreateHelpButton(card, "", "", "", 18)
    helpBtn:SetPoint("RIGHT", locateBtn, "LEFT", -6, 0)
    helpBtn:SetScript("OnClick", function()
        local e = card._entry
        if e and ns.Theme and ns.Theme.ShowHelpPopup then
            ns.Theme:ShowHelpPopup(e.helpTitle or e.title, e.description ~= "" and e.description or e.title, e.howText or "")
        end
    end)
    helpBtn:SetScript("OnEnter", function(self)
        local e = card._entry
        if e and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(e.helpTitle or e.title, 0.35, 0.78, 1.0)
            if e.description and e.description ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["What it does:"], 1.0, 0.82, 0.25)
                GameTooltip:AddLine(e.description, 0.90, 0.93, 0.98, true)
            end
            if e.howText and e.howText ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["How to use it:"], 0.35, 0.92, 0.55)
                GameTooltip:AddLine(e.howText, 0.85, 0.90, 0.95, true)
            end
            GameTooltip:Show()
        end
    end)
    helpBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    card.helpBtn = helpBtn

    local breadLbl = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    breadLbl:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -8)
    breadLbl:SetPoint("TOPRIGHT", helpBtn, "TOPLEFT", -6, -8)
    breadLbl:SetJustifyH("LEFT")
    breadLbl:SetWordWrap(false)
    card.breadLbl = breadLbl

    -- Control row: live checkbox OR title + choice/stepper/action
    local cb = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -25)
    cb:SetScript("OnClick", function(self)
        local e = card._entry
        if e and e.setter then
            e.setter(self:GetChecked() and true or false)
            for _, sync in ipairs(syncFns) do sync() end
            Search.RefreshCardStates()
        end
    end)
    cb:Hide()
    card.cb = cb

    local titleLbl = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleLbl:SetPoint("TOPLEFT", card, "TOPLEFT", 36, -29)
    titleLbl:SetPoint("TOPRIGHT", helpBtn, "TOPLEFT", -6, -29)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetWordWrap(false)
    card.titleLbl = titleLbl

    local choiceHolder = CreateFrame("Frame", nil, card)
    choiceHolder:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -48)
    choiceHolder:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -48)
    choiceHolder:SetHeight(22)
    choiceHolder:Hide()
    card.choiceHolder = choiceHolder
    card.choiceBtns = {}
    for ci = 1, 4 do
        local cbtn = ns.Theme:CreateButton(choiceHolder, 108, 20, "", "default")
        cbtn:SetScript("OnClick", function()
            local e = card._entry
            if e and e.setter and cbtn._optValue ~= nil then
                e.setter(cbtn._optValue)
                for _, sync in ipairs(syncFns) do sync() end
                Search.RefreshCardStates()
            end
        end)
        cbtn:Hide()
        card.choiceBtns[ci] = cbtn
    end

    local stepperHolder = CreateFrame("Frame", nil, card)
    stepperHolder:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -48)
    stepperHolder:SetSize(200, 22)
    stepperHolder:Hide()
    local sMinus = ns.Theme:CreateButton(stepperHolder, 24, 20, "-", "default")
    sMinus:SetPoint("LEFT", stepperHolder, "LEFT", 0, 0)
    local sVal = stepperHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sVal:SetPoint("LEFT", sMinus, "RIGHT", 6, 0)
    sVal:SetWidth(68)
    sVal:SetJustifyH("CENTER")
    local sPlus = ns.Theme:CreateButton(stepperHolder, 24, 20, "+", "default")
    sPlus:SetPoint("LEFT", sVal, "RIGHT", 6, 0)
    sMinus:SetScript("OnClick", function()
        local e = card._entry
        if e and e.getter and e.setter then
            local v = math.max(e.minVal or 0, (e.getter() or 0) - (e.step or 1))
            e.setter(v)
            for _, sync in ipairs(syncFns) do sync() end
            Search.RefreshCardStates()
        end
    end)
    sPlus:SetScript("OnClick", function()
        local e = card._entry
        if e and e.getter and e.setter then
            local v = math.min(e.maxVal or 100, (e.getter() or 0) + (e.step or 1))
            e.setter(v)
            for _, sync in ipairs(syncFns) do sync() end
            Search.RefreshCardStates()
        end
    end)
    card.stepperHolder = stepperHolder
    card.sMinus, card.sPlus, card.sVal = sMinus, sPlus, sVal

    local actionBtn = ns.Theme:CreateButton(card, 140, 20, "", "primary")
    actionBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -48)
    actionBtn:SetScript("OnClick", function()
        local e = card._entry
        if e and e.onTrigger then
            e.onTrigger()
            for _, sync in ipairs(syncFns) do sync() end
            Search.RefreshCardStates()
        end
    end)
    actionBtn:Hide()
    card.actionBtn = actionBtn

    local descLbl = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    descLbl:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 8)
    descLbl:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 8)
    descLbl:SetJustifyH("LEFT")
    descLbl:SetWordWrap(false)
    card.descLbl = descLbl

    Search.cardPool[index] = card
    return card
end

function Search.RefreshCardStates()
    local p = ns.Theme and ns.Theme.GetPalette and ns.Theme:GetPalette()
    for _, card in ipairs(Search.cardPool) do
        if card:IsShown() and card._entry then
            local e = card._entry
            local modOn = Search.IsEntryModuleEnabled(e)
            ns.Theme:ApplyBackdrop(card, "surface", p)
            local rgb = Search.tabColors[e.tabId] or { 0.45, 0.72, 1.0 }
            card.accentBar:SetColorTexture(rgb[1], rgb[2], rgb[3], modOn and 1.0 or 0.45)

            local tabHex = string.format("|cff%02x%02x%02x", math.floor(rgb[1] * 255), math.floor(rgb[2] * 255), math.floor(rgb[3] * 255))
            local secPart = (e.sectionTitle ~= "" and e.sectionTitle ~= e.tabLabel) and ("  ›  " .. e.sectionTitle) or ""
            local modTag = (not modOn) and ("  |cffff9b3d[" .. L["Module Disabled"] .. "]|r") or ""
            card.breadLbl:SetText(tabHex .. (e.tabLabel or "") .. "|r|cff9da7b5" .. secPart .. "|r" .. modTag)

            ns.Theme:StyleButton(card.locateBtn, "default")
            if ns.Theme.SyncButtonLayers then ns.Theme:SyncButtonLayers(card.locateBtn) end
            if card.helpBtn and ns.Theme.SyncButtonLayers then ns.Theme:SyncButtonLayers(card.helpBtn) end

            if e.kind == "checkbox" and e.getter then
                card.cb:SetChecked(e.getter() and true or false)
                card.cb:SetEnabled(modOn)
                card.cb:SetAlpha(modOn and 1.0 or 0.45)
            elseif e.kind == "choice" and e.getter and type(e.options) == "table" then
                local curVal = e.getter()
                for ci, cbtn in ipairs(card.choiceBtns) do
                    local opt = e.options[ci]
                    if opt then
                        local isAct = (curVal == opt.value)
                        ns.Theme:StyleButton(cbtn, isAct and "primary" or "default")
                        ns.Theme:SetButtonActive(cbtn, isAct, isAct and "primary" or "default")
                        cbtn:SetEnabled(modOn)
                        cbtn:SetAlpha(modOn and 1.0 or 0.45)
                    end
                end
            elseif e.kind == "stepper" and e.getter then
                local u = (e.unit and e.unit ~= "") and (" " .. e.unit) or ""
                card.sVal:SetText(tostring(e.getter()) .. u)
                ns.Theme:StyleButton(card.sMinus, "default")
                ns.Theme:StyleButton(card.sPlus, "default")
                card.sMinus:SetEnabled(modOn)
                card.sPlus:SetEnabled(modOn)
                card.sMinus:SetAlpha(modOn and 1.0 or 0.45)
                card.sPlus:SetAlpha(modOn and 1.0 or 0.45)
            elseif e.kind == "action" then
                ns.Theme:StyleButton(card.actionBtn, "primary")
                card.actionBtn:SetEnabled(modOn)
                card.actionBtn:SetAlpha(modOn and 1.0 or 0.45)
            end
            card.titleLbl:SetAlpha(modOn and 1.0 or 0.55)
        end
    end
end

function Search.RenderResults()
    local sp = Search.searchPage
    if not sp then return end
    local qRaw = Search.query or ""
    local qFold = Search.Fold(qRaw)
    if qFold == "" then
        sp:Hide()
        if Search.countLbl then Search.countLbl:SetText("") end
        if Search.pages then
            for id, pFrame in pairs(Search.pages) do
                pFrame:SetShown(id == activeCategoryTab)
            end
        end
        if Search.content and Search.pageHeights then
            Search.content:SetHeight(Search.pageHeights[activeCategoryTab] or 900)
        end
        return
    end

    local tokens = {}
    local synTable = {}
    for tok in qFold:gmatch("%S+") do
        tokens[#tokens + 1] = tok
        synTable[#tokens] = Search.ExpandSynonyms(tok)
    end

    local allMatches = {}
    local countsByTab = { overview = 0, notifications = 0, radar = 0, general = 0 }
    for _, entry in ipairs(Search.entries) do
        local sc = Search.ScoreEntry(entry, tokens, synTable)
        if sc > 0 then
            allMatches[#allMatches + 1] = { entry = entry, score = sc }
            countsByTab[entry.tabId] = (countsByTab[entry.tabId] or 0) + 1
        end
    end
    table.sort(allMatches, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.entry.tabOrder ~= b.entry.tabOrder then return a.entry.tabOrder < b.entry.tabOrder end
        return a.entry.id < b.entry.id
    end)
    Search.lastMatches = allMatches

    if Search.tabFilter ~= "all" and (countsByTab[Search.tabFilter] or 0) == 0 then
        Search.tabFilter = "all"
    end

    local filtered = {}
    for _, m in ipairs(allMatches) do
        if Search.tabFilter == "all" or m.entry.tabId == Search.tabFilter then
            filtered[#filtered + 1] = m.entry
        end
    end

    if Search.pages then
        for _, pFrame in pairs(Search.pages) do
            pFrame:Hide()
        end
    end
    sp:Show()

    local totalCount = #allMatches
    if Search.countLbl then
        if totalCount == 0 then
            Search.countLbl:SetText("|cffff9b3d" .. L["0 results"] .. "|r")
        elseif totalCount == 1 then
            Search.countLbl:SetText("|cff3fb950" .. L["1 result"] .. "|r")
        else
            Search.countLbl:SetText("|cff3fb950" .. string.format(L["%d results"], totalCount) .. "|r")
        end
    end

    local maxW = math.max(460, ((Search.content and Search.content:GetWidth()) or 590) - 16)
    -- Update filter chips row
    local fx = 8
    local fy = -6
    for _, fItem in ipairs(Search.filterBtns) do
        local cnt = (fItem.id == "all") and totalCount or (countsByTab[fItem.id] or 0)
        if (fItem.id == "all" and totalCount > 0) or cnt > 0 then
            local lbl = string.format("%s (%d)", fItem.label, cnt)
            ns.Theme:SetButtonText(fItem.btn, lbl)
            ns.Theme:AutoFitButton(fItem.btn, 72, 14, 190)
            local bw = fItem.btn:GetWidth() or 90
            if fx > 8 and (fx + bw) > maxW then
                fx = 8
                fy = fy - 26
            end
            fItem.btn:ClearAllPoints()
            fItem.btn:SetPoint("TOPLEFT", sp, "TOPLEFT", fx, fy)
            local isAct = (Search.tabFilter == fItem.id)
            ns.Theme:StyleButton(fItem.btn, isAct and "primary" or "default")
            ns.Theme:SetButtonActive(fItem.btn, isAct, isAct and "primary" or "default")
            fItem.btn:Show()
            fx = fx + bw + 6
        else
            fItem.btn:Hide()
        end
    end

    local yCursor = (totalCount > 0) and (fy - 30) or -12
    local shownCards = 0
    if #filtered == 0 then
        for _, c in ipairs(Search.cardPool) do c:Hide() end
        if sp.emptyBox then
            sp.emptyBox:ClearAllPoints()
            sp.emptyBox:SetPoint("TOPLEFT", sp, "TOPLEFT", 8, yCursor)
            sp.emptyBox:SetWidth(maxW - 8)
            sp.emptyTitle:SetText(string.format(L["No settings found for \"%s\"."], qRaw))
            ns.Theme:ApplyBackdrop(sp.emptyBox, "surface")
            local cx, cy = 12, -56
            for _, chip in ipairs(Search.emptyChips) do
                ns.Theme:StyleButton(chip.btn, "default")
                ns.Theme:AutoFitButton(chip.btn, 64, 14, 140)
                local cw = chip.btn:GetWidth() or 80
                if cx > 12 and (cx + cw) > (maxW - 24) then
                    cx = 12
                    cy = cy - 26
                end
                chip.btn:ClearAllPoints()
                chip.btn:SetPoint("TOPLEFT", sp.emptyBox, "TOPLEFT", cx, cy)
                chip.btn:Show()
                cx = cx + cw + 6
            end
            sp.emptyBox:SetHeight(math.abs(cy) + 36)
            sp.emptyBox:Show()
            yCursor = yCursor - (sp.emptyBox:GetHeight() + 16)
        end
    else
        if sp.emptyBox then sp.emptyBox:Hide() end
        local limit = math.min(#filtered, Search.maxRender)
        for i = 1, limit do
            local entry = filtered[i]
            local card = Search.EnsureCard(i)
            card._entry = entry
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", sp, "TOPLEFT", 8, yCursor)
            card:SetWidth(maxW - 8)

            local hiTitle = Search.HighlightTitle(entry.title, tokens)
            card.titleLbl:SetText(hiTitle)

            card.cb:Hide()
            card.choiceHolder:Hide()
            card.stepperHolder:Hide()
            card.actionBtn:Hide()

            local hasSubCtrl = false
            if entry.kind == "checkbox" then
                card.cb:Show()
                card.titleLbl:ClearAllPoints()
                card.titleLbl:SetPoint("LEFT", card.cb, "RIGHT", 6, 0)
                card.titleLbl:SetPoint("RIGHT", card.helpBtn, "LEFT", -8, 0)
            else
                card.titleLbl:ClearAllPoints()
                card.titleLbl:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -26)
                card.titleLbl:SetPoint("TOPRIGHT", card.helpBtn, "TOPLEFT", -8, -26)
                if entry.kind == "choice" and type(entry.options) == "table" then
                    hasSubCtrl = true
                    card.choiceHolder:Show()
                    local bx = 0
                    for ci, cbtn in ipairs(card.choiceBtns) do
                        local opt = entry.options[ci]
                        if opt then
                            cbtn._optValue = opt.value
                            ns.Theme:SetButtonText(cbtn, opt.label)
                            ns.Theme:AutoFitButton(cbtn, 64, 12, math.floor((maxW - 36) * 0.45))
                            cbtn:ClearAllPoints()
                            cbtn:SetPoint("LEFT", card.choiceHolder, "LEFT", bx, 0)
                            cbtn:Show()
                            bx = bx + (cbtn:GetWidth() or 80) + 6
                        else
                            cbtn:Hide()
                        end
                    end
                elseif entry.kind == "stepper" then
                    hasSubCtrl = true
                    card.stepperHolder:Show()
                elseif entry.kind == "action" and entry.onTrigger then
                    hasSubCtrl = true
                    ns.Theme:SetButtonText(card.actionBtn, entry.actionLabel or entry.title)
                    ns.Theme:AutoFitButton(card.actionBtn, 96, 16, 260)
                    card.actionBtn:Show()
                end
            end

            local hasDesc = (entry.description and entry.description ~= "")
            if hasDesc then
                card.descLbl:SetText(entry.description)
                card.descLbl:Show()
            else
                card.descLbl:SetText("")
                card.descLbl:Hide()
            end

            local cardH = hasSubCtrl and (hasDesc and 92 or 76) or (hasDesc and 68 or 52)
            card:SetHeight(cardH)
            card:Show()
            shownCards = i
            yCursor = yCursor - (cardH + 6)
        end
        for i = shownCards + 1, #Search.cardPool do
            Search.cardPool[i]:Hide()
        end
    end

    local totalH = math.max(360, math.abs(yCursor) + 24)
    sp:SetHeight(totalH)
    if Search.content then
        Search.content:SetHeight(totalH)
    end
    Search.RefreshCardStates()
end

local function HelpBtn(parent, anchorTo, title, whatText, howText)
    if not (ns.Theme and ns.Theme.CreateHelpButton) then
        return nil
    end
    local h = ns.Theme:CreateHelpButton(parent, title, whatText, howText, 18)
    h:SetPoint("LEFT", anchorTo, "RIGHT", 8, 0)
    return h
end

local function AddDeps(list, ...)
    local modKey = list and list._scModKey
    for i = 1, select("#", ...) do
        local w = select(i, ...)
        if w then
            if modKey and type(w) == "table" then
                w._scDepMod = modKey
            end
            list[#list + 1] = w
        end
    end
end

local function SetWidgetEnabled(w, enabled)
    if not w then return end
    local on = enabled and true or false
    if w.SetEnabled then
        w:SetEnabled(on)
    end
    if w.EnableMouse and (w.GetObjectType and w:GetObjectType() == "EditBox") then
        w:EnableMouse(on)
        if w.EnableKeyboard then w:EnableKeyboard(on) end
        if not on and w.HasFocus and w:HasFocus() and w.ClearFocus then
            w:ClearFocus()
        end
        if w._clearBtn and w._clearBtn.SetEnabled then
            w._clearBtn:SetEnabled(on)
        end
    end
    if w._scMinus and w._scMinus.SetEnabled then
        w._scMinus:SetEnabled(on)
        w._scMinus:SetAlpha(on and 1.0 or 0.42)
    end
    if w._scPlus and w._scPlus.SetEnabled then
        w._scPlus:SetEnabled(on)
        w._scPlus:SetAlpha(on and 1.0 or 0.42)
    end
    if w.SetAlpha then
        w:SetAlpha(on and 1.0 or 0.42)
    end
    if w._scLabel and w._scLabel.SetAlpha then
        w._scLabel:SetAlpha(on and 1.0 or 0.42)
    end
    if w.text and w.text.SetAlpha then
        w.text:SetAlpha(on and 1.0 or 0.42)
    end
end

local function AddSectionHeader(parent, text, anchorTo, yOffset, helpTitle, helpWhat, helpHow)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    if anchorTo then
        fs:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOffset or -16)
    else
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset or -8)
    end
    fs:SetText(text)
    if ns.Theme and ns.Theme.DecorateSectionHeader then
        ns.Theme:DecorateSectionHeader(parent, fs, math.min(540, math.max(320, (parent:GetWidth() or 590) - 24)))
    end
    if helpTitle then
        HelpBtn(parent, fs, helpTitle, helpWhat, helpHow)
    end
    Search.buildSectionTitle = text or ""
    Search.buildSectionHelp = {
        helpTitle = helpTitle,
        description = helpWhat,
        howText = helpHow,
    }
    return fs
end

local function CreateCheckbox(parent, labelText, anchorTo, yOffset, getter, setter, helpTitle, helpWhat, helpHow, xOffset)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    if anchorTo then
        cb:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", xOffset or 0, yOffset or -6)
    else
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset or 10, yOffset or -8)
    end

    local label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    label:SetText(labelText)
    local function FitCheckboxLabel()
        local pw = (parent and parent.GetWidth and parent:GetWidth()) or 590
        local avail = (pw < 420) and math.max(150, pw - 58) or math.max(260, pw - 86)
        local rawW = label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth() or 0
        if rawW > avail then
            label:SetWidth(avail)
        else
            label:SetWidth(0)
        end
    end
    FitCheckboxLabel()
    cb._scLabel = label

    if helpTitle then
        HelpBtn(parent, label, helpTitle, helpWhat, helpHow)
    end

    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
        for _, sync in ipairs(syncFns) do
            sync()
        end
    end)

    syncFns[#syncFns + 1] = function()
        FitCheckboxLabel()
        cb:SetChecked(getter() and true or false)
    end

    Search.Register({
        kind = "checkbox",
        title = labelText,
        widget = cb,
        getter = getter,
        setter = setter,
        helpTitle = helpTitle,
        description = helpWhat,
        howText = helpHow,
    })
    return cb
end

local function CreateGridCheckbox(colParent, anchorTo, yOffset, labelText, getter, setter, helpTitle, helpWhat, helpHow)
    return CreateCheckbox(colParent, labelText, anchorTo, yOffset, getter, setter, helpTitle, helpWhat, helpHow, 0)
end

local function CreateChoiceRow(parent, anchorTo, yOffset, options, getter, setter)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOffset or -6)
    row:SetSize(560, 26)

    local buttons = {}
    for _, opt in ipairs(options) do
        local btn = ns.Theme:CreateButton(row, opt.width or 140, 24, opt.label, "default")
        ns.Theme:AutoFitButton(btn, math.min(opt.width or 140, 110), 22, 548)
        btn:SetScript("OnClick", function()
            setter(opt.value)
            for _, sync in ipairs(syncFns) do
                sync()
            end
        end)
        buttons[#buttons + 1] = { btn = btn, value = opt.value }
    end

    local function ReflowChoiceRow()
        local maxW = math.max(320, (parent:GetWidth() or 590) - 34)
        local x, y, rowH = 0, 0, 24
        for _, item in ipairs(buttons) do
            local btn = item.btn
            local bw = math.min(maxW, math.max(80, btn:GetWidth() or 120))
            if x > 0 and (x + bw) > maxW then
                x = 0
                y = y - (rowH + 6)
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", row, "TOPLEFT", x, y)
            x = x + bw + 8
        end
        row:SetSize(maxW, math.abs(y) + rowH + 2)
    end
    ReflowChoiceRow()

    syncFns[#syncFns + 1] = function()
        local current = getter()
        for _, item in ipairs(buttons) do
            ns.Theme:StyleButton(item.btn, "default")
            ns.Theme:SetButtonActive(item.btn, current == item.value, "default")
        end
        ReflowChoiceRow()
    end

    local meta = Search.pendingMeta or Search.buildSectionHelp
    local choiceTitle = (Search.pendingMeta and Search.pendingMeta.title) or Search.buildSectionTitle
    Search.pendingMeta = nil
    Search.Register({
        kind = "choice",
        title = choiceTitle,
        widget = row,
        options = options,
        getter = getter,
        setter = setter,
        helpTitle = meta and meta.helpTitle or choiceTitle,
        description = meta and meta.description or "",
        howText = meta and meta.howText or "",
    })
    return row
end

local function CreateStepperRow(parent, anchorTo, yOffset, minVal, maxVal, unit, getter, setter, stepSize)
    local step = stepSize or 1
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOffset or -6)
    row:SetSize(320, 26)

    local minus = ns.Theme:CreateButton(row, 28, 24, "-", "default")
    minus:SetPoint("LEFT", row, "LEFT", 0, 0)

    local valueText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valueText:SetPoint("LEFT", minus, "RIGHT", 10, 0)
    valueText:SetWidth(84)
    valueText:SetJustifyH("CENTER")

    local plus = ns.Theme:CreateButton(row, 28, 24, "+", "default")
    plus:SetPoint("LEFT", valueText, "RIGHT", 10, 0)

    row._scMinus = minus
    row._scPlus = plus
    row._scValue = valueText

    local function RefreshValue()
        if unit and unit ~= "" then
            valueText:SetText(string.format("%d %s", getter(), unit))
        else
            valueText:SetText(tostring(getter()))
        end
        ns.Theme:StyleButton(minus, "default")
        ns.Theme:StyleButton(plus, "default")
        ns.Theme:SetButtonActive(minus, false, "default")
        ns.Theme:SetButtonActive(plus, false, "default")
    end

    minus:SetScript("OnClick", function()
        local v = math.max(minVal, getter() - step)
        setter(v)
        RefreshValue()
    end)

    plus:SetScript("OnClick", function()
        local v = math.min(maxVal, getter() + step)
        setter(v)
        RefreshValue()
    end)

    syncFns[#syncFns + 1] = RefreshValue

    local meta = Search.pendingMeta or Search.buildSectionHelp
    local stepTitle = (Search.pendingMeta and Search.pendingMeta.title) or Search.buildSectionTitle
    Search.pendingMeta = nil
    Search.Register({
        kind = "stepper",
        title = stepTitle,
        widget = row,
        minVal = minVal,
        maxVal = maxVal,
        unit = unit,
        step = step,
        getter = getter,
        setter = setter,
        helpTitle = meta and meta.helpTitle or stepTitle,
        description = meta and meta.description or "",
        howText = meta and meta.howText or "",
    })
    return row
end

local function CountMutedPlayersAndThreads()
    local playerCount = 0
    if ns.db and ns.db.socialMeta and ns.Compat and ns.Compat.ScopeKey then
        local scope = ns.Compat.ScopeKey()
        local tbl = ns.db.socialMeta[scope]
        if type(tbl) == "table" then
            for _, meta in pairs(tbl) do
                if type(meta) == "table" and meta.notifyMuted == true then
                    playerCount = playerCount + 1
                end
            end
        end
    end
    local threadCount = 0
    local mutedMap = ns.db and ns.db.settings and ns.db.settings.chatMutedThreads
    if type(mutedMap) == "table" then
        for _, v in pairs(mutedMap) do
            if v == true then
                threadCount = threadCount + 1
            end
        end
    end
    return playerCount, threadCount
end

local function CollectDisabledNotificationNames()
    local s = ns.db and ns.db.settings
    if not s then return {} end
    local out = {}
    local focusReason = Compat and Compat.GetFocusSilenceReason and Compat.GetFocusSilenceReason()
    if focusReason == "dnd" then
        out[#out + 1] = L["Do Not Disturb (Active)"]
    elseif focusReason == "instance" then
        out[#out + 1] = L["Silenced in Instance"]
    end
    local wbOn = s.embedWorldMap ~= false
    local guildOn = (not Compat or not Compat.IsWindowIntegrationEnabled) or Compat.IsWindowIntegrationEnabled("J")
    local watchOn = s.moduleWatchlistEnabled ~= false
    local chatOn = s.moduleChatEnabled ~= false

    if s.friendOnlineAlertToast == false then out[#out + 1] = L["Friend Online Alerts"] end
    if s.friendOfflineAlertToast == false then out[#out + 1] = L["Friend Offline Alerts"] end
    if watchOn and s.alerts and s.alerts.toast == false then out[#out + 1] = L["Watchlist Online Alerts"] end
    if chatOn and s.addonMsgToast == false then out[#out + 1] = L["Floating Message Popups"] end
    if chatOn and s.msgPreviewEnabled == false then out[#out + 1] = L["Minimap Message Previews"] end
    if chatOn and s.chatSound == false then out[#out + 1] = L["Chat Sounds (Master)"] end
    if wbOn and s.worldBuffsAlerts == false then out[#out + 1] = L["World Buff Drop Alerts"] end
    if wbOn and s.worldBuffsExpiryAlert == false then out[#out + 1] = L["World Buff Expiry Warning"] end
    if guildOn and s.clanLfgAlertEnabled == false then out[#out + 1] = L["Clan Dungeon Alerts"] end
    if guildOn and s.clanSignupAlertEnabled == false then out[#out + 1] = L["Guild Signup Alerts"] end
    if guildOn and s.clanEventReminders == false then out[#out + 1] = L["Guild Event Reminders"] end
    if guildOn and s.spotterScoutAlert == false then out[#out + 1] = L["Guild Scout Alerts"] end
    if s.groupAvoidAlert == false then out[#out + 1] = L["Group Avoid Warnings"] end
    return out
end

local function GetActivePresetMode()
    local s = ns.db and ns.db.settings
    if not s then return "full" end
    if s.embedSocialWindow ~= false
        and s.embedLfgWindow ~= false
        and s.embedGuildWindow ~= false
        and s.embedCharacterWindow ~= false
        and s.embedWorldMap ~= false
        and s.spotterEnabled ~= false
        and s.moduleWatchlistEnabled ~= false
        and s.moduleNearbyEnabled ~= false
        and s.moduleChatEnabled ~= false
        and s.moduleGroupEnabled ~= false
        and s.doNotDisturb ~= true
    then
        return "full"
    elseif s.embedSocialWindow ~= false
        and s.embedLfgWindow == false
        and s.embedGuildWindow == false
        and s.embedCharacterWindow ~= false
        and s.embedWorldMap == false
        and s.spotterEnabled == false
        and s.moduleWatchlistEnabled ~= false
        and s.moduleNearbyEnabled ~= false
        and s.moduleChatEnabled ~= false
        and s.moduleGroupEnabled == false
        and s.doNotDisturb ~= true
    then
        return "social"
    elseif s.embedSocialWindow == false
        and s.embedLfgWindow == false
        and s.embedGuildWindow == false
        and s.embedCharacterWindow ~= false
        and s.embedWorldMap == false
        and s.spotterEnabled == false
        and s.moduleWatchlistEnabled == false
        and s.moduleNearbyEnabled == false
        and s.moduleChatEnabled ~= false
        and s.moduleGroupEnabled == false
        and s.doNotDisturb == true
    then
        return "ultralight"
    end
    return nil
end

local function EnsurePanelFrame()
    if not panel then
        panel = CreateFrame("Frame", "SocialCentralSettingsPanel", UIParent)
        panel.name = "SocialCentral"
    end
    return panel
end

local function EnsureShortcutTable(s, field)
    if not s then return nil end
    if type(s[field]) ~= "table" then
        s[field] = { O = false, I = false, J = false, C = false }
    end
    return s[field]
end

local function BuildShortcutAutoOpenSection(ov, anchor, deps, refs, NotifySettingChanged)
    local scAutoHeader = AddSectionHeader(
        ov,
        L["Open Shortcut Directly on SocialCentral Tab"],
        anchor,
        -10,
        L["Help: Shortcut Auto-Open"],
        L["Lets you choose whether pressing an official game window shortcut (O, I, J, C) jumps straight to the SocialCentral tab or opens Blizzard's default tab."],
        L["Choose whether to apply this preference to only the current shortcut or to all enabled shortcuts, and change it anytime in Settings."]
    )

    local scAutoGrid = CreateFrame("Frame", nil, ov)
    scAutoGrid:SetPoint("TOPLEFT", scAutoHeader, "BOTTOMLEFT", 0, -4)
    scAutoGrid:SetSize(600, 62)

    local scAutoLeft = CreateFrame("Frame", nil, scAutoGrid)
    scAutoLeft:SetPoint("TOPLEFT", scAutoGrid, "TOPLEFT", 0, 0)
    scAutoLeft:SetSize(294, 60)

    local scAutoRight = CreateFrame("Frame", nil, scAutoGrid)
    scAutoRight:SetPoint("TOPLEFT", scAutoLeft, "TOPRIGHT", 10, 0)
    scAutoRight:SetSize(294, 60)

    refs.scAutoGrid, refs.scAutoLeft, refs.scAutoRight = scAutoGrid, scAutoLeft, scAutoRight

    local function MakeAutoOpenCheckbox(colFrame, rowAnchor, winKey, labelText, helpTitle, helpWhat, helpHow)
        return CreateGridCheckbox(
            colFrame,
            rowAnchor,
            rowAnchor and -4 or -2,
            labelText,
            function()
                local tbl = ns.db and ns.db.settings and ns.db.settings.shortcutAutoOpenAddon
                return type(tbl) == "table" and tbl[winKey] == true
            end,
            function(checked)
                local s = ns.db and ns.db.settings
                if s then
                    local autoTbl = EnsureShortcutTable(s, "shortcutAutoOpenAddon")
                    local ansTbl = EnsureShortcutTable(s, "shortcutPromptAnswered")
                    autoTbl[winKey] = (checked == true)
                    ansTbl[winKey] = true
                    if ns.LFGFrameTab and ns.LFGFrameTab._shortcutPromptDismissed then
                        ns.LFGFrameTab._shortcutPromptDismissed[winKey] = nil
                    end
                end
                NotifySettingChanged()
            end,
            helpTitle,
            helpWhat,
            helpHow
        )
    end

    local autoSocCb = MakeAutoOpenCheckbox(
        scAutoLeft, nil, "O", L["Social & Friends (O)"],
        L["Help: Auto-Open Social (O)"],
        L["Automatically opens the SocialCentral side-tab whenever you open Social / Friends (O)."],
        L["Click any Blizzard tab inside the window anytime to switch back to the native Friends or Who lists."]
    )
    local autoLfgCb = MakeAutoOpenCheckbox(
        scAutoLeft, autoSocCb, "I", L["Group Finder (I)"],
        L["Help: Auto-Open Group Finder (I)"],
        L["Automatically opens the SocialCentral Clans & Allies LFG tab whenever you open Group Finder (I)."],
        L["Click Blizzard's Official Listing or Browse tabs anytime to switch back inside the same window."]
    )
    local autoGuildCb = MakeAutoOpenCheckbox(
        scAutoRight, nil, "J", L["Guild & Diplomacy (J)"],
        L["Help: Auto-Open Guild (J)"],
        L["Automatically opens the SocialCentral Guild Hub tab whenever you open Guild / Communities (J)."],
        L["Click Blizzard's Guild Chat or Roster tabs on the right anytime to return to the native guild view."]
    )
    local autoCharCb = MakeAutoOpenCheckbox(
        scAutoRight, autoGuildCb, "C", L["Character & Alts (C)"],
        L["Help: Auto-Open Character (C)"],
        L["Automatically opens the SocialCentral My Alts inventory & gold vault tab whenever you open Character (C)."],
        L["Click Blizzard's Character or Currency bottom tabs anytime to switch back to equipment view."]
    )

    AddDeps(deps.social, autoSocCb)
    AddDeps(deps.lfg, autoLfgCb)
    AddDeps(deps.guild, autoGuildCb)
    AddDeps(deps.alts, autoCharCb)

    local scResetRow = CreateFrame("Frame", nil, ov)
    scResetRow:SetPoint("TOPLEFT", scAutoGrid, "BOTTOMLEFT", 0, -4)
    scResetRow:SetSize(560, 24)

    local askAgainBtn = ns.Theme:CreateButton(scResetRow, 206, 22, L["Ask Again on Shortcuts"], "default")
    ns.Theme:AutoFitButton(askAgainBtn, 168, 16, 280)
    askAgainBtn:SetPoint("LEFT", scResetRow, "LEFT", 0, 0)
    askAgainBtn:SetScript("OnClick", function()
        local function DoResetPrompts()
            local s = ns.db and ns.db.settings
            if s then
                s.shortcutAutoOpenAddon = { O = false, I = false, J = false, C = false }
                s.shortcutPromptAnswered = { O = false, I = false, J = false, C = false }
            end
            if ns.LFGFrameTab then
                ns.LFGFrameTab._shortcutPromptDismissed = {}
            end
            NotifySettingChanged()
            ns:Print("%s", L["Shortcut prompts reset: SocialCentral will ask again the next time you open each window."])
        end
        if ns.UI and ns.UI.OpenConfirmModal then
            ns.UI:OpenConfirmModal({
                title = L["Ask Again on Shortcuts"],
                message = L["Are you sure you want to reset your shortcut auto-open choices so SocialCentral asks again on O, I, J, and C?"],
                confirmText = L["Reset"],
                confirmVariant = "primary",
                onConfirm = DoResetPrompts,
            })
        else
            DoResetPrompts()
        end
    end)

    HelpBtn(
        scResetRow,
        askAgainBtn,
        L["Help: Ask Again on Shortcuts"],
        L["Clears your saved first-time shortcut choices (O, I, J, C) and resets auto-open back to asking on first open."],
        L["Click to re-enable the confirmation prompt the next time you press an enabled official shortcut key."]
    )
    Search.Register({
        kind = "action",
        title = L["Ask Again on Shortcuts"],
        actionLabel = L["Ask Again on Shortcuts"],
        widget = askAgainBtn,
        helpTitle = L["Help: Ask Again on Shortcuts"],
        description = L["Clears your saved first-time shortcut choices (O, I, J, C) and resets auto-open back to asking on first open."],
        howText = L["Click to re-enable the confirmation prompt the next time you press an enabled official shortcut key."],
        onTrigger = function() askAgainBtn:Click() end,
    })
    AddDeps(deps.defaultBtns, askAgainBtn)

    return scResetRow
end

local function BuildOverviewTab(ov, deps, refs, NotifySettingChanged, CloseSettingsBeforeJump)
    local charProfCb = CreateCheckbox(
        ov,
        L["Use separate settings profile for this character"],
        nil,
        -6,
        function() return ns.IsCharProfileEnabled and ns:IsCharProfileEnabled() end,
        function(checked)
            if ns.SetCharProfileEnabled then
                ns:SetCharProfileEnabled(checked)
            end
        end,
        L["Help: Per-Character Profile"],
        L["When checked, module toggles, notification settings, and window integrations are saved separately just for this character instead of sharing account-wide."],
        L["Ideal for bank alts or leveling characters where you want a lighter setup without changing your main character."]
    )

    local charProfActions = CreateFrame("Frame", nil, ov)
    charProfActions:SetPoint("TOPLEFT", charProfCb, "BOTTOMLEFT", 24, -4)
    charProfActions:SetSize(560, 24)

    local copyAccBtn = ns.Theme:CreateButton(charProfActions, 174, 20, L["Copy from Account Profile"], "default")
    ns.Theme:AutoFitButton(copyAccBtn, 150, 14, 230)
    copyAccBtn:SetPoint("LEFT", charProfActions, "LEFT", 0, 0)
    copyAccBtn:SetScript("OnClick", function()
        local function DoCopy()
            if ns.CopyAccountSettingsToChar and ns:CopyAccountSettingsToChar() then
                for _, sync in ipairs(syncFns) do sync() end
            end
        end
        if ns.UI and ns.UI.OpenConfirmModal then
            ns.UI:OpenConfirmModal({
                title = L["Copy from Account Profile"],
                message = L["Are you sure you want to overwrite this character's settings with the shared Account Profile?"],
                confirmText = L["Confirm"],
                confirmVariant = "primary",
                onConfirm = DoCopy,
            })
        else
            DoCopy()
        end
    end)

    local resetProfBtn = ns.Theme:CreateButton(charProfActions, 168, 20, L["Reset Profile to Defaults"], "default")
    ns.Theme:AutoFitButton(resetProfBtn, 146, 14, 220)
    resetProfBtn:SetPoint("LEFT", copyAccBtn, "RIGHT", 6, 0)
    resetProfBtn:SetScript("OnClick", function()
        local function DoReset()
            if ns.ResetCurrentSettingsToDefaults and ns:ResetCurrentSettingsToDefaults() then
                for _, sync in ipairs(syncFns) do sync() end
            end
        end
        if ns.UI and ns.UI.OpenConfirmModal then
            ns.UI:OpenConfirmModal({
                title = L["Reset Profile to Defaults"],
                message = L["Are you sure you want to reset the active SocialCentral profile back to default settings?"],
                confirmText = L["Reset"],
                confirmVariant = "danger",
                onConfirm = DoReset,
            })
        else
            DoReset()
        end
    end)

    HelpBtn(
        charProfActions,
        resetProfBtn,
        L["Help: Profile Actions"],
        L["Copy your shared Account settings into this character profile or reset the currently active profile back to SocialCentral defaults."],
        L["'Copy from Account Profile' is available whenever per-character profile mode is enabled above."]
    )

    refs.copyAccBtn = copyAccBtn
    AddDeps(deps.defaultBtns, copyAccBtn, resetProfBtn)

    local presetRow = CreateFrame("Frame", nil, ov)
    presetRow:SetPoint("TOPLEFT", charProfActions, "BOTTOMLEFT", -20, -6)
    presetRow:SetSize(600, 28)

    local function ApplyPreset(mode)
        local s = ns.db and ns.db.settings
        if not s then return end
        if mode == "full" then
            s.embedSocialWindow = true
            s.embedLfgWindow = true
            s.embedGuildWindow = true
            s.embedCharacterWindow = true
            s.embedWorldMap = true
            s.spotterEnabled = true
            s.moduleWatchlistEnabled = true
            s.moduleNearbyEnabled = true
            s.moduleChatEnabled = true
            s.moduleGroupEnabled = true
            s.doNotDisturb = false
        elseif mode == "social" then
            s.embedSocialWindow = true
            s.embedLfgWindow = false
            s.embedGuildWindow = false
            s.embedCharacterWindow = true
            s.embedWorldMap = false
            s.spotterEnabled = false
            s.moduleWatchlistEnabled = true
            s.moduleNearbyEnabled = true
            s.moduleChatEnabled = true
            s.moduleGroupEnabled = false
            s.doNotDisturb = false
        elseif mode == "ultralight" then
            s.embedSocialWindow = false
            s.embedLfgWindow = false
            s.embedGuildWindow = false
            s.embedCharacterWindow = true
            s.embedWorldMap = false
            s.spotterEnabled = false
            s.moduleWatchlistEnabled = false
            s.moduleNearbyEnabled = false
            s.moduleChatEnabled = true
            s.moduleGroupEnabled = false
            s.doNotDisturb = true
        end
        NotifySettingChanged("CLAN_UPDATED")
        ns:Emit("WORLD_BUFFS_UPDATED")
        ns:Emit("CHAT_UPDATED")
        for _, sync in ipairs(syncFns) do sync() end
    end

    local presetFullBtn = ns.Theme:CreateButton(presetRow, 138, 22, L["Preset: Full (Default)"], "primary")
    ns.Theme:AutoFitButton(presetFullBtn, 118, 14, 175)
    presetFullBtn:SetPoint("LEFT", presetRow, "LEFT", 0, 0)
    presetFullBtn:SetScript("OnClick", function() ApplyPreset("full") end)

    local presetSocialBtn = ns.Theme:CreateButton(presetRow, 152, 22, L["Preset: Friends & Chat"], "default")
    ns.Theme:AutoFitButton(presetSocialBtn, 132, 14, 195)
    presetSocialBtn:SetPoint("LEFT", presetFullBtn, "RIGHT", 6, 0)
    presetSocialBtn:SetScript("OnClick", function() ApplyPreset("social") end)

    local presetLiteBtn = ns.Theme:CreateButton(presetRow, 154, 22, L["Preset: Ultra-Light (Alts)"], "default")
    ns.Theme:AutoFitButton(presetLiteBtn, 134, 14, 195)
    presetLiteBtn:SetPoint("LEFT", presetSocialBtn, "RIGHT", 6, 0)
    presetLiteBtn:SetScript("OnClick", function() ApplyPreset("ultralight") end)

    HelpBtn(
        presetRow,
        presetLiteBtn,
        L["Help: 1-Click Presets"],
        L["Instantly switch between Full Suite, Friends & Chat Only, or Ultra-Light (Alts & Notes) presets, then fine-tune any checkbox below."],
        L["Use 'Ultra-Light' on bank or crafting alts to pause all background scanners, popups, and extra Blizzard window tabs."]
    )
    Search.Register({
        kind = "choice",
        title = L["Help: 1-Click Presets"],
        widget = presetRow,
        helpTitle = L["Help: 1-Click Presets"],
        description = L["Instantly switch between Full Suite, Friends & Chat Only, or Ultra-Light (Alts & Notes) presets, then fine-tune any checkbox below."],
        howText = L["Use 'Ultra-Light' on bank or crafting alts to pause all background scanners, popups, and extra Blizzard window tabs."],
        options = {
            { value = "full", label = L["Preset: Full (Default)"] },
            { value = "social", label = L["Preset: Friends & Chat"] },
            { value = "ultralight", label = L["Preset: Ultra-Light (Alts)"] },
        },
        getter = GetActivePresetMode,
        setter = ApplyPreset,
    })
    Search.Register({
        kind = "action",
        title = L["Reset Profile to Defaults"],
        actionLabel = L["Reset Profile to Defaults"],
        widget = resetProfBtn,
        helpTitle = L["Help: Profile Actions"],
        description = L["Copy your shared Account settings into this character profile or reset the currently active profile back to SocialCentral defaults."],
        howText = L["'Copy from Account Profile' is available whenever per-character profile mode is enabled above."],
        onTrigger = function() resetProfBtn:Click() end,
    })

    local winToggleHeader = AddSectionHeader(
        ov,
        L["Modules & Blizzard Window Integrations"],
        presetRow,
        -10,
        L["Help: Window Integrations"],
        L["Turn entire SocialCentral modules and Blizzard window integrations (O, I, J, C, M) on or off immediately without reload."],
        L["Unchecking a module disables its tabs, shortcuts, alerts, and background scanners completely."]
    )

    local winGrid = CreateFrame("Frame", nil, ov)
    winGrid:SetPoint("TOPLEFT", winToggleHeader, "BOTTOMLEFT", 0, -4)
    winGrid:SetSize(600, 154)

    local winLeft = CreateFrame("Frame", nil, winGrid)
    winLeft:SetPoint("TOPLEFT", winGrid, "TOPLEFT", 0, 0)
    winLeft:SetSize(294, 152)

    local winRight = CreateFrame("Frame", nil, winGrid)
    winRight:SetPoint("TOPLEFT", winLeft, "TOPRIGHT", 10, 0)
    winRight:SetSize(294, 152)

    refs.winGrid, refs.winLeft, refs.winRight = winGrid, winLeft, winRight

    local embSocCb = CreateGridCheckbox(
        winLeft, nil, -2, L["Social & Friends (O)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.embedSocialWindow ~= false end,
        function(checked) ns.db.settings.embedSocialWindow = checked; NotifySettingChanged() end,
        L["Help: Integrate Social (O)"],
        L["Attaches the SocialCentral Watchlist, Social, Nearby, and Conversations side-tab to Blizzard's Friends/Social (O) window."],
        L["Uncheck to keep Blizzard's Friends (O) window 100% vanilla while still keeping '/sc hub' available."]
    )
    local embLfgCb = CreateGridCheckbox(
        winLeft, embSocCb, -4, L["Group Finder (I)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.embedLfgWindow ~= false end,
        function(checked) ns.db.settings.embedLfgWindow = checked; NotifySettingChanged() end,
        L["Help: Integrate Group Finder (I)"],
        L["Attaches the Clans, Allies & Global Chat LFG side-tab inside Blizzard's Group Finder (I) window and scans public LFG channels."],
        L["Uncheck to disable the entire Group Finder (I) module and stop LFG chat scanning immediately."]
    )
    local embGuildCb = CreateGridCheckbox(
        winLeft, embLfgCb, -4, L["Guild & Diplomacy (J)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.embedGuildWindow ~= false end,
        function(checked) ns.db.settings.embedGuildWindow = checked; NotifySettingChanged("CLAN_UPDATED") end,
        L["Help: Integrate Guild (J)"],
        L["Attaches the Guild Hub, Events, Professions, and Diplomacy side-tab inside Blizzard's Guild / Communities (J) window."],
        L["Uncheck to disable the Guild module completely. Also hides automatically on characters without a guild."]
    )
    local embCharCb = CreateGridCheckbox(
        winLeft, embGuildCb, -4, L["Character & Alts (C)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.embedCharacterWindow ~= false end,
        function(checked) ns.db.settings.embedCharacterWindow = checked; NotifySettingChanged() end,
        L["Help: Integrate Character (C)"],
        L["Attaches the My Alts side-tab (gold vault, equipped items, bags, and bank search) inside Blizzard's Character (C) window."],
        L["Uncheck to disable the My Alts module, bag/bank snapshots, and alt item tooltip counts completely."]
    )
    CreateGridCheckbox(
        winLeft, embCharCb, -4, L["World Buffs on Map (M)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.embedWorldMap ~= false end,
        function(checked) ns.db.settings.embedWorldMap = checked; NotifySettingChanged("WORLD_BUFFS_UPDATED") end,
        L["Help: Integrate World Map (M)"],
        L["Enables the entire World Buffs module: World Map (M) badge & pins, drop alerts, timers, and guild buff sync."],
        L["Uncheck to turn off the entire World Buffs module and disable all World Buff options in Radar & Map."]
    )

    local modRadarCb = CreateGridCheckbox(
        winRight, nil, -2, L["Screen Target Radar"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterEnabled ~= false end,
        function(checked) ns.db.settings.spotterEnabled = checked; NotifySettingChanged() end,
        L["Help: Screen Spotter Master"],
        L["Master toggle for detecting Enemy, Ally, Watchlist, and Friend players on your screen."],
        L["Uncheck to pause screen scanning and disable all Target Radar controls and HUD."]
    )
    local modWatchCb = CreateGridCheckbox(
        winRight, modRadarCb, -4, L["Watchlist (/who)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.moduleWatchlistEnabled ~= false end,
        function(checked) ns.db.settings.moduleWatchlistEnabled = checked; NotifySettingChanged("WATCHLIST_UPDATED") end,
        L["Help: Watchlist Module"],
        L["Master toggle for the Watchlist tab, online alerts, and right-click Watchlist menu actions."],
        L["Uncheck to hide the Watchlist tab and mute Watchlist online tracking completely."]
    )
    local modNearbyCb = CreateGridCheckbox(
        winRight, modWatchCb, -4, L["Nearby Players"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.moduleNearbyEnabled ~= false end,
        function(checked) ns.db.settings.moduleNearbyEnabled = checked; NotifySettingChanged("NEARBY_UPDATED") end,
        L["Help: Nearby Module"],
        L["Master toggle for the passive Friendly Nearby players tab and proximity recording."],
        L["Uncheck to hide the Nearby tab and stop all passive unit/chat proximity recording."]
    )
    local modChatCb = CreateGridCheckbox(
        winRight, modNearbyCb, -4, L["Conversations (Chat)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.moduleChatEnabled ~= false end,
        function(checked) ns.db.settings.moduleChatEnabled = checked; NotifySettingChanged("CHAT_UPDATED") end,
        L["Help: Conversations Module"],
        L["Master toggle for SocialCentral Conversations, Private Rooms, and addon chat popups/sounds."],
        L["Uncheck to hide Conversations and disable all addon chat popups and chimes."]
    )
    CreateGridCheckbox(
        winRight, modChatCb, -4, L["Group & Companions"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.moduleGroupEnabled ~= false end,
        function(checked) ns.db.settings.moduleGroupEnabled = checked; NotifySettingChanged("GROUP_UPDATED") end,
        L["Help: Group Module"],
        L["Master toggle for the Group tab and automatic Recent Companions recording."],
        L["Uncheck to hide the Group tab and stop recording recent party/raid companions."]
    )

    local autoHideGuildCb = CreateCheckbox(
        ov,
        L["Automatically hide Guild features when this character has no guild"],
        winGrid,
        -4,
        function() return not ns.db or not ns.db.settings or ns.db.settings.hideGuildFeaturesWhenNoGuild ~= false end,
        function(checked) ns.db.settings.hideGuildFeaturesWhenNoGuild = checked; NotifySettingChanged("CLAN_UPDATED") end,
        L["Help: Auto-Hide Without Guild"],
        L["Automatically hides Guild (J) integration, Hub Guild tab, Alliance chat mirrors, and Guild shortcuts whenever you play a character with no guild."],
        L["Keep enabled so guildless characters stay clutter-free without manually turning Guild options off and on."]
    )

    local scAutoBottom = BuildShortcutAutoOpenSection(ov, autoHideGuildCb, deps, refs, NotifySettingChanged)

    local dndCb = CreateCheckbox(
        ov,
        L["Do Not Disturb (pause all popups & chimes without changing your checkboxes)"],
        scAutoBottom,
        -4,
        function() return ns.db and ns.db.settings and ns.db.settings.doNotDisturb == true end,
        function(checked) ns.db.settings.doNotDisturb = checked; NotifySettingChanged() end,
        L["Help: Do Not Disturb"],
        L["Temporarily pauses all non-critical floating popups and sound chimes without overwriting any of your saved notification checkboxes."],
        L["Great for raids, arenas, or quiet focus sessions; uncheck to resume your exact saved preferences."]
    )

    local autoInstSilCb = CreateCheckbox(
        ov,
        L["Auto-silence social popups & chimes inside Dungeons, Raids & BGs"],
        dndCb,
        -4,
        function() return ns.db and ns.db.settings and ns.db.settings.autoSilenceInInstances == true end,
        function(checked) ns.db.settings.autoSilenceInInstances = checked; NotifySettingChanged() end,
        L["Help: Auto-Silence in Instances"],
        L["Automatically pauses social popups and chimes whenever you enter a Dungeon, Raid, or Battleground (Group Avoid safety warnings still show)."],
        L["Resumes notifications automatically as soon as you step back into the open world."]
    )

    local quickNotifHeader = AddSectionHeader(
        ov,
        L["Quick Notification Switches (1-Click Summary)"],
        autoInstSilCb,
        -12,
        L["Help: Quick Notification Summary"],
        L["Master summary switches to silence or enable SocialCentral popups, sounds, and alerts at a glance without scrolling."],
        L["Each popup notification also has a crossed-bell icon you can click anytime (with a confirmation popup) to silence just that notification."]
    )

    local qGrid = CreateFrame("Frame", nil, ov)
    qGrid:SetPoint("TOPLEFT", quickNotifHeader, "BOTTOMLEFT", 0, -4)
    qGrid:SetSize(600, 148)

    local qLeft = CreateFrame("Frame", nil, qGrid)
    qLeft:SetPoint("TOPLEFT", qGrid, "TOPLEFT", 0, 0)
    qLeft:SetSize(294, 146)

    local qRight = CreateFrame("Frame", nil, qGrid)
    qRight:SetPoint("TOPLEFT", qLeft, "TOPRIGHT", 10, 0)
    qRight:SetSize(294, 146)

    refs.qGrid, refs.qLeft, refs.qRight = qGrid, qLeft, qRight

    local qFrOnCb = CreateGridCheckbox(
        qLeft, nil, -2, L["Friend Online (Toast)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.friendOnlineAlertToast ~= false end,
        function(checked) ns.db.settings.friendOnlineAlertToast = checked; NotifySettingChanged() end,
        L["Help: Friend Online Toast"],
        L["Displays a compact floating Notification Toast when a tracked Favorite or Friend logs into WoW: Forever."],
        L["Left-click the toast to jump straight to that friend in the Social tab."]
    )
    local qFrOffCb = CreateGridCheckbox(
        qLeft, qFrOnCb, -4, L["Friend Offline (Toast)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.friendOfflineAlertToast ~= false end,
        function(checked) ns.db.settings.friendOfflineAlertToast = checked; NotifySettingChanged() end,
        L["Help: Friend Disconnect Toast"],
        L["Displays a compact floating Notification Toast when a friend or tracked player logs off or disconnects from WoW."],
        L["Left-click the toast to view the player in the Social directory."]
    )
    local qWlCb = CreateGridCheckbox(
        qLeft, qFrOffCb, -4, L["Watchlist Online (Toast)"],
        function() return not ns.db or not ns.db.settings.alerts or ns.db.settings.alerts.toast ~= false end,
        function(checked) if ns.db and ns.db.settings and ns.db.settings.alerts then ns.db.settings.alerts.toast = checked end; NotifySettingChanged() end,
        L["Help: Watchlist Toast Alert"],
        L["Displays a compact floating Notification Toast at the top of the screen when a watched player transitions online (outside muted rows)."],
        L["Uncheck to stop floating Watchlist toasts globally, or click the bell icon beside any name in the Social/Watchlist window (O) to mute per player."]
    )
    local qAddonCb = CreateGridCheckbox(
        qLeft, qWlCb, -4, L["Addon Messages (Toast)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.addonMsgToast ~= false end,
        function(checked) ns.db.settings.addonMsgToast = checked; NotifySettingChanged() end,
        L["Help: Floating Notification Toast"],
        L["Displays a compact, draggable 100%-opaque pill near the top of your screen when a peer messages you via the addon or sends a room invite."],
        L["Left-click the pill to jump directly to the conversation (deferred automatically after combat), hover to pause, or right-click to dismiss."]
    )

    local qChatSndCb = CreateGridCheckbox(
        qRight, nil, -2, L["Chat Sounds (Master)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.chatSound ~= false end,
        function(checked) ns.db.settings.chatSound = checked; NotifySettingChanged("CHAT_UPDATED") end,
        L["Help: Chat Sound Alert"],
        L["Master switch for incoming conversation sound chimes across SocialCentral."],
        L["Uncheck to mute all SocialCentral conversation chimes without affecting muted individual threads."]
    )
    local qWbCb = CreateGridCheckbox(
        qRight, qChatSndCb, -4, L["World Buff Alerts"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.worldBuffsAlerts ~= false end,
        function(checked) ns.db.settings.worldBuffsAlerts = checked; NotifySettingChanged() end,
        L["Help: World Buff Drop Alerts"],
        L["Prints a local chat notification whenever an NPC announces the turn-in of Onyxia, Nefarian, Rend Blackhand, or Hakkar heads in town."],
        L["Alerts you ~6 to 15 seconds before the buff lands so you have time to log in or reposition."]
    )
    local qClanLfgCb = CreateGridCheckbox(
        qRight, qWbCb, -4, L["Clan LFG Alerts"],
        function() return ns.db and ns.db.settings and ns.db.settings.clanLfgAlertEnabled == true end,
        function(checked) ns.db.settings.clanLfgAlertEnabled = checked; NotifySettingChanged("CLAN_UPDATED") end,
        L["Help: Clan Dungeon Alerts"],
        L["Notifies you in chat (with optional sound and clickable Whisper/Clan links) whenever a guildmate looks for a Dungeon group."],
        L["Uncheck to stop Guild LFG notifications while still seeing listings inside Group Finder (I)."]
    )
    CreateGridCheckbox(
        qRight, qClanLfgCb, -4, L["Group Avoid Warnings"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.groupAvoidAlert ~= false end,
        function(checked) ns.db.settings.groupAvoidAlert = checked; NotifySettingChanged() end,
        L["Help: Group Avoid Warning"],
        L["Immediately alerts you with a warning toast and chat notice if someone on your Avoid list or linked alts enters your party or raid."],
        L["Allows you to address toxic encounters or leave before dungeons and raids start."]
    )

    local bulkActionRow = CreateFrame("Frame", nil, ov)
    bulkActionRow:SetPoint("TOPLEFT", qGrid, "BOTTOMLEFT", 0, -6)
    bulkActionRow:SetSize(600, 28)

    local testOvBtn = ns.Theme:CreateButton(bulkActionRow, 150, 24, L["Test Notification Toast"], "default")
    ns.Theme:AutoFitButton(testOvBtn, 128, 16, 200)
    testOvBtn:SetPoint("LEFT", bulkActionRow, "LEFT", 0, 0)
    testOvBtn:SetScript("OnClick", function()
        if ns.NotificationToast and ns.NotificationToast.ShowTestNotification then
            ns.NotificationToast:ShowTestNotification()
        end
    end)

    local muteAllPopupsBtn = ns.Theme:CreateButton(bulkActionRow, 156, 24, L["Mute All Popups"], "default")
    ns.Theme:AutoFitButton(muteAllPopupsBtn, 130, 16, 210)
    muteAllPopupsBtn:SetPoint("LEFT", testOvBtn, "RIGHT", 8, 0)
    muteAllPopupsBtn:SetScript("OnClick", function()
        local s = ns.db and ns.db.settings
        if s then
            s.friendOnlineAlertToast = false
            s.friendOfflineAlertToast = false
            s.addonMsgToast = false
            s.msgPreviewEnabled = false
            s.worldBuffsAlerts = false
            s.worldBuffsExpiryAlert = false
            s.clanLfgAlertEnabled = false
            s.clanEventAlertEnabled = false
            s.clanSignupAlertEnabled = false
            s.clanEventReminders = false
            s.spotterScoutAlert = false
            s.spotterAutoShowHUD = false
            if s.alerts then s.alerts.toast = false end
        end
        if ns.NotificationToast and ns.NotificationToast.DismissAll then
            ns.NotificationToast:DismissAll()
        end
        if ns.MinimapPreview and ns.MinimapPreview.Dismiss then
            ns.MinimapPreview:Dismiss(false)
        end
        NotifySettingChanged("CLAN_UPDATED")
        for _, sync in ipairs(syncFns) do sync() end
    end)

    local enablePopupsBtn = ns.Theme:CreateButton(bulkActionRow, 164, 24, L["Restore Popups"], "primary")
    ns.Theme:AutoFitButton(enablePopupsBtn, 130, 16, 210)
    enablePopupsBtn:SetPoint("LEFT", muteAllPopupsBtn, "RIGHT", 8, 0)
    enablePopupsBtn:SetScript("OnClick", function()
        local s = ns.db and ns.db.settings
        if s then
            s.friendOnlineAlertToast = true
            s.friendOfflineAlertToast = true
            s.addonMsgToast = true
            s.msgPreviewEnabled = true
            s.msgPreviewPromptAnswered = true
            s.worldBuffsAlerts = true
            s.worldBuffsExpiryAlert = true
            s.clanLfgAlertEnabled = true
            s.clanSignupAlertEnabled = true
            s.clanEventReminders = true
            s.spotterScoutAlert = true
            s.groupAvoidAlert = true
            s.spotterAutoShowHUD = true
            s.doNotDisturb = false
            if s.alerts then s.alerts.toast = true end
        end
        NotifySettingChanged("CLAN_UPDATED")
        for _, sync in ipairs(syncFns) do sync() end
    end)

    HelpBtn(
        bulkActionRow,
        enablePopupsBtn,
        L["Help: Quick Popup Controls"],
        L["Quickly test notification positioning, silence social floating popups (while keeping Group Avoid safety warnings), or restore all notification popups in 1 click."],
        L["Click 'Mute All Popups' to uncheck popup alerts, or use 'Do Not Disturb' above to pause without overwriting your checkboxes."]
    )
    Search.Register({
        kind = "action",
        title = L["Mute All Popups"],
        actionLabel = L["Mute All Popups"],
        widget = muteAllPopupsBtn,
        helpTitle = L["Help: Quick Popup Controls"],
        description = L["Quickly test notification positioning, silence social floating popups (while keeping Group Avoid safety warnings), or restore all notification popups in 1 click."],
        howText = L["Click 'Mute All Popups' to uncheck popup alerts, or use 'Do Not Disturb' above to pause without overwriting your checkboxes."],
        onTrigger = function() muteAllPopupsBtn:Click() end,
    })
    Search.Register({
        kind = "action",
        title = L["Restore Popups"],
        actionLabel = L["Restore Popups"],
        widget = enablePopupsBtn,
        helpTitle = L["Help: Quick Popup Controls"],
        description = L["Quickly test notification positioning, silence social floating popups (while keeping Group Avoid safety warnings), or restore all notification popups in 1 click."],
        howText = L["Click 'Mute All Popups' to uncheck popup alerts, or use 'Do Not Disturb' above to pause without overwriting your checkboxes."],
        onTrigger = function() enablePopupsBtn:Click() end,
    })

    local winHeader = AddSectionHeader(
        ov,
        L["Official Game Windows (Native Tabs)"],
        bulkActionRow,
        -12,
        L["Help: Official Game Windows"],
        L["SocialCentral features live directly inside Blizzard's native windows via side-tabs and toolbar buttons. Use this Settings window for configuration and quick shortcuts."],
        L["Click any shortcut below to jump straight to that official game window with the SocialCentral tab active, or configure preferences above."]
    )

    local jumpGrid = CreateFrame("Frame", nil, ov)
    jumpGrid:SetPoint("TOPLEFT", winHeader, "BOTTOMLEFT", 0, -6)
    jumpGrid:SetSize(580, 64)

    local jumpSpecs = {
        { mod = "lfg", label = L["Looking for Group (I)"], variant = "primary" },
        { mod = "watchlist", label = L["Social & Watchlist (O)"], variant = "default" },
        { mod = "clan", label = L["Clan Hub & Diplomacy (J)"], variant = "default", isGuild = true },
        { mod = "alts", label = L["My Alts (C)"], variant = "default" },
        { mod = "chat", label = L["Conversations (Chat)"], variant = "default" },
        { mod = "buffs", label = L["World Buffs (M)"], variant = "default" },
        { mod = "hub", label = L["Unified Hub (/sc hub)"], variant = "default" },
    }
    local jumpButtons = {}
    for _, spec in ipairs(jumpSpecs) do
        local jb = ns.Theme:CreateButton(jumpGrid, 150, 24, spec.label, spec.variant)
        ns.Theme:AutoFitButton(jb, 110, 18, 250)
        jb:SetScript("OnClick", function()
            CloseSettingsBeforeJump()
            if spec.mod == "hub" then
                if ns.UI and ns.UI.ShowHub then
                    ns.UI:ShowHub()
                elseif ns.UI then
                    ns.UI:Toggle()
                end
            elseif ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
                ns.LFGFrameTab:OpenOfficialModule(spec.mod)
            elseif ns.UI and ns.UI.OpenTab then
                ns.UI:OpenTab(spec.mod)
            end
        end)
        jumpButtons[#jumpButtons + 1] = { btn = jb, mod = spec.mod, variant = spec.variant, isGuild = spec.isGuild }
    end

    refs.jumpButtons = jumpButtons
    refs.ReflowJumpGrid = function()
        local maxW = math.max(320, (ov:GetWidth() or 590) - 24)
        local x, y, rowH = 0, 0, 24
        for _, item in ipairs(jumpButtons) do
            local modOk = (item.mod == "hub")
                or (item.mod == "chat" and ((not Compat or not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("chat")))
                or (item.mod ~= "chat" and ((not Compat or not Compat.IsWindowIntegrationEnabled) or Compat.IsWindowIntegrationEnabled(item.mod)))
            if not modOk then
                item.btn:Hide()
            else
                item.btn:Show()
                local bw = math.min(maxW, math.max(96, item.btn:GetWidth() or 140))
                if x > 0 and (x + bw) > maxW then
                    x = 0
                    y = y - (rowH + 6)
                end
                item.btn:ClearAllPoints()
                item.btn:SetPoint("TOPLEFT", jumpGrid, "TOPLEFT", x, y)
                x = x + bw + 8
            end
        end
        jumpGrid:SetSize(maxW, math.abs(y) + rowH + 2)
    end

    AddDeps(deps.defaultBtns, testOvBtn, muteAllPopupsBtn)
    AddDeps(deps.primaryBtns, enablePopupsBtn)
    refs.presetBtns = {
        { mode = "full", btn = presetFullBtn },
        { mode = "social", btn = presetSocialBtn },
        { mode = "ultralight", btn = presetLiteBtn },
    }
    AddDeps(deps.wb, qWbCb)
    AddDeps(deps.guild, qClanLfgCb)
    AddDeps(deps.watch, qWlCb)
    AddDeps(deps.chat, qAddonCb, qChatSndCb)
end

local function BuildMinimapPreviewSettingsSection(nf, anchorTo, deps, NotifySettingChanged)
    local mpHeader = AddSectionHeader(
        nf,
        L["Minimap Message Previews"],
        anchorTo,
        -12,
        L["Help: Minimap Message Previews"],
        L["Temporarily expands a compact animated capsule vertically centered on the left side of your Minimap showing the sender's character icon and opening words, then smoothly closes back into the SC icon."],
        L["Pick which channels trigger previews (Whispers, Battle.net, Group, Guild, Private Rooms) and silence them automatically inside Dungeons, Raids, Battlegrounds, or Combat."]
    )

    local mpMasterCb = CreateCheckbox(
        nf, L["Enable animated message preview capsule beside Minimap"], mpHeader, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.msgPreviewEnabled ~= false end,
        function(checked)
            ns.db.settings.msgPreviewEnabled = checked
            ns.db.settings.msgPreviewPromptAnswered = true
            if not checked and ns.MinimapPreview and ns.MinimapPreview.Dismiss then
                ns.MinimapPreview:Dismiss(false)
            end
            NotifySettingChanged()
        end,
        L["Help: Enable Minimap Message Previews"],
        L["Master switch for the animated message preview capsule beside the Minimap."],
        L["Uncheck to disable minimap message previews completely without affecting your Conversations panel or unread counter badge."]
    )

    local mpWhisperCb = CreateCheckbox(
        nf, L["Show previews for Whispers & SocialCentral Direct Chat"], mpMasterCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.msgPreviewWhispers ~= false end,
        function(checked)
            ns.db.settings.msgPreviewWhispers = checked
            ns.db.settings.msgPreviewPromptAnswered = true
            NotifySettingChanged()
        end,
        L["Help: Preview Whispers"],
        L["Expands the minimap message preview whenever you receive an in-game character Whisper or SocialCentral 1-on-1 Direct Message."],
        L["Hover over the preview to read the full text and pause the timer, or click to jump straight into replying."]
    )

    local mpBNetCb = CreateCheckbox(
        nf, L["Show previews for Battle.net Friends"], mpWhisperCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.msgPreviewBNet ~= false end,
        function(checked)
            ns.db.settings.msgPreviewBNet = checked
            ns.db.settings.msgPreviewPromptAnswered = true
            NotifySettingChanged()
        end,
        L["Help: Preview Battle.net"],
        L["Expands the minimap message preview whenever a Battle.net friend messages you (showing their character icon or the Battle.net emblem)."],
        L["Left-click opens the conversation or Shift+Click opens a quick Battle.net reply."]
    )

    local mpGroupCb = CreateCheckbox(
        nf, L["Show previews for Group Chat (Party / Raid / Instance)"], mpBNetCb, -6,
        function() return ns.db and ns.db.settings and ns.db.settings.msgPreviewGroup == true end,
        function(checked)
            ns.db.settings.msgPreviewGroup = checked
            ns.db.settings.msgPreviewPromptAnswered = true
            NotifySettingChanged()
        end,
        L["Help: Preview Group"],
        L["Expands the minimap message preview for Party, Raid, and Instance chat lines sent by your teammates (showing their live portrait when nearby)."],
        L["Off by default to keep group runs quiet; combine with the Dungeon/Raid silence checkboxes below to show only open-world group chat."]
    )

    local mpGuildCb = CreateCheckbox(
        nf, L["Show previews for Guild & Officer Chat"], mpGroupCb, -6,
        function() return ns.db and ns.db.settings and ns.db.settings.msgPreviewGuild == true end,
        function(checked)
            ns.db.settings.msgPreviewGuild = checked
            ns.db.settings.msgPreviewPromptAnswered = true
            NotifySettingChanged()
        end,
        L["Help: Preview Guild"],
        L["Expands the minimap message preview whenever a guildmate posts in Guild or Officer chat."],
        L["Off by default for busy guilds; enable if you want to catch guild messages right beside your minimap without watching chat."]
    )

    local mpRoomsCb = CreateCheckbox(
        nf, L["Show previews for Private Rooms & Alliance Chat"], mpGuildCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.msgPreviewRooms ~= false end,
        function(checked)
            ns.db.settings.msgPreviewRooms = checked
            ns.db.settings.msgPreviewPromptAnswered = true
            NotifySettingChanged()
        end,
        L["Help: Preview Rooms"],
        L["Expands the minimap message preview for SocialCentral Private Rooms and cross-guild Alliance Chat messages."],
        L["Uncheck if you prefer to receive Private Room & Alliance alerts only in the top Toast stack or Conversations panel."]
    )

    local mpSilDngCb = CreateCheckbox(
        nf, L["Hide message previews inside Dungeons"], mpRoomsCb, -8,
        function() return not ns.db or not ns.db.settings or ns.db.settings.msgPreviewSilenceDungeons ~= false end,
        function(checked)
            ns.db.settings.msgPreviewSilenceDungeons = checked
            ns.db.settings.msgPreviewPromptAnswered = true
            NotifySettingChanged()
        end,
        L["Help: Preview Silence Dungeons"],
        L["Automatically pauses minimap message previews while you are inside 5-player Dungeons or instanced scenarios."],
        L["Keep checked to keep your minimap area completely clear during dungeon pulls; resumes automatically once you exit."]
    )

    local mpSilRaidCb = CreateCheckbox(
        nf, L["Hide message previews inside Raids"], mpSilDngCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.msgPreviewSilenceRaids ~= false end,
        function(checked)
            ns.db.settings.msgPreviewSilenceRaids = checked
            ns.db.settings.msgPreviewPromptAnswered = true
            NotifySettingChanged()
        end,
        L["Help: Preview Silence Raids"],
        L["Automatically pauses minimap message previews while you are inside Raid instances."],
        L["Keep checked during boss nights to avoid distractions beside the minimap."]
    )

    local mpSilPvpCb = CreateCheckbox(
        nf, L["Hide message previews inside Battlegrounds & Arenas"], mpSilRaidCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.msgPreviewSilencePvP ~= false end,
        function(checked)
            ns.db.settings.msgPreviewSilencePvP = checked
            ns.db.settings.msgPreviewPromptAnswered = true
            NotifySettingChanged()
        end,
        L["Help: Preview Silence PvP"],
        L["Automatically pauses minimap message previews while you are inside Battlegrounds or Arenas."],
        L["Uncheck if you still want Whispers or Group previews during PvP matches."]
    )

    local mpSilCombatCb = CreateCheckbox(
        nf, L["Hide message previews while in combat"], mpSilPvpCb, -6,
        function() return ns.db and ns.db.settings and ns.db.settings.msgPreviewSilenceCombat == true end,
        function(checked)
            ns.db.settings.msgPreviewSilenceCombat = checked
            ns.db.settings.msgPreviewPromptAnswered = true
            NotifySettingChanged()
        end,
        L["Help: Preview Silence Combat"],
        L["Pauses minimap message previews whenever your character is actively in combat, even in the open world."],
        L["Enable for completely distraction-free fights anywhere in Azeroth."]
    )

    local durLbl = nf:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    durLbl:SetPoint("TOPLEFT", mpSilCombatCb, "BOTTOMLEFT", 4, -8)
    durLbl:SetText(L["Preview display duration (seconds):"])
    HelpBtn(
        nf, durLbl, L["Help: Preview Duration"],
        L["Controls how many seconds the message preview stays expanded beside the Minimap before closing and gliding back into the SC icon."],
        L["Hovering your mouse over the preview always pauses the countdown automatically so you can finish reading."]
    )

    Search.SetPendingMeta(
        L["Preview display duration (seconds):"],
        L["Help: Preview Duration"],
        L["Controls how many seconds the message preview stays expanded beside the Minimap before closing and gliding back into the SC icon."],
        L["Hovering your mouse over the preview always pauses the countdown automatically so you can finish reading."]
    )
    local durStep = CreateStepperRow(
        nf, durLbl, -4, 3, 12, "s",
        function() return (ns.db and ns.db.settings and ns.db.settings.msgPreviewDuration) or 6 end,
        function(val)
            if ns.db and ns.db.settings then
                ns.db.settings.msgPreviewDuration = val
                ns.db.settings.msgPreviewPromptAnswered = true
            end
        end,
        1
    )

    local maxVisLbl = nf:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    maxVisLbl:SetPoint("TOPLEFT", durStep, "BOTTOMLEFT", 0, -8)
    maxVisLbl:SetText(L["Simultaneous minimap preview rows (1–3):"])
    HelpBtn(
        nf, maxVisLbl, L["Help: Preview Max Visible"],
        L["Sets how many message previews can appear stacked simultaneously beside your Minimap (1 to 3 rows, newest at the bottom)."],
        L["Any additional incoming messages wait cleanly in a queue (+N) and rise smoothly into view as soon as the top preview finishes and returns to the SC icon."]
    )

    Search.SetPendingMeta(
        L["Simultaneous minimap preview rows (1–3):"],
        L["Help: Preview Max Visible"],
        L["Sets how many message previews can appear stacked simultaneously beside your Minimap (1 to 3 rows, newest at the bottom)."],
        L["Any additional incoming messages wait cleanly in a queue (+N) and rise smoothly into view as soon as the top preview finishes and returns to the SC icon."]
    )
    local maxVisStep = CreateStepperRow(
        nf, maxVisLbl, -4, 1, 3, L["lines"],
        function() return (ns.db and ns.db.settings and ns.db.settings.msgPreviewMaxVisible) or 3 end,
        function(val)
            if ns.db and ns.db.settings then
                ns.db.settings.msgPreviewMaxVisible = val
                ns.db.settings.msgPreviewPromptAnswered = true
                NotifySettingChanged()
            end
        end,
        1
    )

    local mpBtnRow = CreateFrame("Frame", nil, nf)
    mpBtnRow:SetPoint("TOPLEFT", maxVisStep, "BOTTOMLEFT", 0, -8)
    mpBtnRow:SetSize(560, 26)

    local testMpBtn = ns.Theme:CreateButton(mpBtnRow, 148, 22, L["Test Minimap Preview"], "default")
    ns.Theme:AutoFitButton(testMpBtn, 126, 14, 210)
    testMpBtn:SetPoint("LEFT", mpBtnRow, "LEFT", 0, 0)
    testMpBtn:SetScript("OnClick", function()
        if ns.MinimapPreview and ns.MinimapPreview.ShowTestPreview then
            ns.MinimapPreview:ShowTestPreview("")
        end
    end)

    local testQueueMpBtn = ns.Theme:CreateButton(mpBtnRow, 134, 22, L["Test Queue (4)"], "default")
    ns.Theme:AutoFitButton(testQueueMpBtn, 108, 14, 180)
    testQueueMpBtn:SetPoint("LEFT", testMpBtn, "RIGHT", 6, 0)
    testQueueMpBtn:SetScript("OnClick", function()
        if ns.MinimapPreview and ns.MinimapPreview.ShowTestPreview then
            ns.MinimapPreview:ShowTestPreview("queue")
        end
    end)

    local setupMpBtn = ns.Theme:CreateButton(mpBtnRow, 146, 22, L["Open Setup Prompt"], "default")
    ns.Theme:AutoFitButton(setupMpBtn, 118, 14, 195)
    setupMpBtn:SetPoint("LEFT", testQueueMpBtn, "RIGHT", 6, 0)
    setupMpBtn:SetScript("OnClick", function()
        if ns.MinimapPreview and ns.MinimapPreview.ShowTestPreview then
            ns.MinimapPreview:ShowTestPreview("setup")
        end
    end)

    HelpBtn(
        mpBtnRow, setupMpBtn, L["Help: Test Minimap Preview"],
        L["Plays a live sample message preview beside your Minimap (with expand and close-to-SC-icon animation) or re-opens the first-time setup assistant."],
        L["You can also test specific channels anytime using '/sc preview whisper', 'bnet', 'group', 'guild', or 'setup'."]
    )

    Search.Register({
        kind = "action",
        title = L["Test Minimap Preview"],
        actionLabel = L["Test Minimap Preview"],
        widget = testMpBtn,
        helpTitle = L["Help: Test Minimap Preview"],
        description = L["Plays a live sample message preview beside your Minimap (with expand and close-to-SC-icon animation) or re-opens the first-time setup assistant."],
        howText = L["You can also test specific channels anytime using '/sc preview whisper', 'bnet', 'group', 'guild', or 'setup'."],
        onTrigger = function()
            if ns.MinimapPreview and ns.MinimapPreview.ShowTestPreview then
                ns.MinimapPreview:ShowTestPreview("")
            end
        end,
    })
    Search.Register({
        kind = "action",
        title = L["Test Queue (4)"],
        actionLabel = L["Test Queue (4)"],
        widget = testQueueMpBtn,
        helpTitle = L["Help: Preview Max Visible"],
        description = L["Sets how many message previews can appear stacked simultaneously beside your Minimap (1 to 3 rows, newest at the bottom)."],
        howText = L["Any additional incoming messages wait cleanly in a queue (+N) and rise smoothly into view as soon as the top preview finishes and returns to the SC icon."],
        onTrigger = function()
            if ns.MinimapPreview and ns.MinimapPreview.ShowTestPreview then
                ns.MinimapPreview:ShowTestPreview("queue")
            end
        end,
    })
    Search.Register({
        kind = "action",
        title = L["Open Setup Prompt"],
        actionLabel = L["Open Setup Prompt"],
        widget = setupMpBtn,
        helpTitle = L["Help: Minimap Message Preview Setup"],
        description = L["Shows a compact animated preview with the sender's icon and opening words on the left side of your Minimap whenever a matching message arrives, then closes back into the SC icon."],
        howText = L["Choose which message types should trigger previews and whether to automatically silence them inside Dungeons, Raids, Battlegrounds, or Combat. You can change this anytime in Settings -> Notifications."],
        onTrigger = function()
            if ns.MinimapPreview and ns.MinimapPreview.ShowTestPreview then
                ns.MinimapPreview:ShowTestPreview("setup")
            end
        end,
    })

    local mpPosRow = CreateFrame("Frame", nil, nf)
    mpPosRow:SetPoint("TOPLEFT", mpBtnRow, "BOTTOMLEFT", 0, -6)
    mpPosRow:SetSize(560, 26)

    local moveMpPosBtn = ns.Theme:CreateButton(mpPosRow, 168, 22, L["Move Preview Position"], "default")
    ns.Theme:AutoFitButton(moveMpPosBtn, 146, 16, 225)
    moveMpPosBtn:SetPoint("LEFT", mpPosRow, "LEFT", 0, 0)
    moveMpPosBtn:SetScript("OnClick", function()
        if ns.MinimapPreview and ns.MinimapPreview.ToggleAnchorMover then
            ns.MinimapPreview:ToggleAnchorMover()
        end
    end)

    local resetMpPosBtn = ns.Theme:CreateButton(mpPosRow, 152, 22, L["Reset Preview Position"], "default")
    ns.Theme:AutoFitButton(resetMpPosBtn, 134, 16, 215)
    resetMpPosBtn:SetPoint("LEFT", moveMpPosBtn, "RIGHT", 6, 0)
    resetMpPosBtn:SetScript("OnClick", function()
        if ns.MinimapPreview and ns.MinimapPreview.ResetPosition then
            ns.MinimapPreview:ResetPosition()
        end
    end)

    HelpBtn(
        mpPosRow, resetMpPosBtn, L["Help: Move Preview Position"],
        L["Lets you move the 3-row message preview stack to any location on your screen (or drag any live preview directly), while keeping the smooth launch and return-to-Minimap fusion animation."],
        L["Click 'Move Preview Position' (or type '/sc preview move') to drag the 3-slot guide anywhere on screen, then click 'Done'. Click 'Reset Preview Position' anytime to dock back beside the Minimap."]
    )

    Search.Register({
        kind = "action",
        title = L["Move Preview Position"],
        actionLabel = L["Move Preview Position"],
        widget = moveMpPosBtn,
        helpTitle = L["Help: Move Preview Position"],
        description = L["Lets you move the 3-row message preview stack to any location on your screen (or drag any live preview directly), while keeping the smooth launch and return-to-Minimap fusion animation."],
        howText = L["Click 'Move Preview Position' (or type '/sc preview move') to drag the 3-slot guide anywhere on screen, then click 'Done'. Click 'Reset Preview Position' anytime to dock back beside the Minimap."],
        onTrigger = function()
            if ns.MinimapPreview and ns.MinimapPreview.ToggleAnchorMover then
                ns.MinimapPreview:ToggleAnchorMover()
            end
        end,
    })
    Search.Register({
        kind = "action",
        title = L["Reset Preview Position"],
        actionLabel = L["Reset Preview Position"],
        widget = resetMpPosBtn,
        helpTitle = L["Help: Move Preview Position"],
        description = L["Lets you move the 3-row message preview stack to any location on your screen (or drag any live preview directly), while keeping the smooth launch and return-to-Minimap fusion animation."],
        howText = L["Click 'Move Preview Position' (or type '/sc preview move') to drag the 3-slot guide anywhere on screen, then click 'Done'. Click 'Reset Preview Position' anytime to dock back beside the Minimap."],
        onTrigger = function()
            if ns.MinimapPreview and ns.MinimapPreview.ResetPosition then
                ns.MinimapPreview:ResetPosition()
            end
        end,
    })

    AddDeps(deps.defaultBtns, testMpBtn, testQueueMpBtn, setupMpBtn, moveMpPosBtn, resetMpPosBtn)
    AddDeps(deps.chat, mpMasterCb, mpWhisperCb, mpBNetCb, mpGroupCb, mpGuildCb, mpRoomsCb, mpSilDngCb, mpSilRaidCb, mpSilPvpCb, mpSilCombatCb, durLbl, durStep, maxVisLbl, maxVisStep, testMpBtn, testQueueMpBtn, setupMpBtn, moveMpPosBtn, resetMpPosBtn)
    return mpPosRow
end

local function BuildMinimapBadgeStyleControls(nf, anchorTo, deps, NotifySettingChanged)
    local styleLbl = nf:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    styleLbl:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -8)
    styleLbl:SetText(L["Minimap counter badge style:"])
    HelpBtn(
        nf, styleLbl, L["Help: Minimap Badge Style"],
        L["Choose how multiple unread message types appear on the Minimap icon: either a single chat-colored Fusion Circle directly under the SC icon (blending Whisper pink, Group blue, Guild green, and Battle.net cyan, splitting cleanly on hover) or separate non-overlapping numbers orbiting around the icon."],
        L["Pick 'Fusion Circle (Under Icon)' for the animated color-merge orb directly beneath the icon, or 'Around Icon (Separate)' to keep each chat type spaced around the icon at all times."]
    )

    Search.SetPendingMeta(
        L["Minimap counter badge style:"],
        L["Help: Minimap Badge Style"],
        L["Choose how multiple unread message types appear on the Minimap icon: either a single chat-colored Fusion Circle directly under the SC icon (blending Whisper pink, Group blue, Guild green, and Battle.net cyan, splitting cleanly on hover) or separate non-overlapping numbers orbiting around the icon."],
        L["Pick 'Fusion Circle (Under Icon)' for the animated color-merge orb directly beneath the icon, or 'Around Icon (Separate)' to keep each chat type spaced around the icon at all times."]
    )
    local styleRow = CreateChoiceRow(nf, styleLbl, -4, {
        { value = "fusion", label = L["Fusion Circle (Under Icon)"], width = 205 },
        { value = "separate", label = L["Around Icon (Separate)"], width = 185 },
    }, function()
        return (ns.db and ns.db.settings and ns.db.settings.minimapBadgeStyle) or "fusion"
    end, function(val)
        if ns.db and ns.db.settings then
            ns.db.settings.minimapBadgeStyle = val
            NotifySettingChanged()
        end
    end)

    local testFusionBtn = ns.Theme:CreateButton(nf, 152, 22, L["Test Fusion Badge"], "default")
    ns.Theme:AutoFitButton(testFusionBtn, 134, 16, 210)
    testFusionBtn:SetPoint("TOPLEFT", styleRow, "BOTTOMLEFT", 0, -6)
    testFusionBtn:SetScript("OnClick", function()
        if ns.MinimapPreview and ns.MinimapPreview.ShowTestPreview then
            ns.MinimapPreview:ShowTestPreview("badge fusion")
        end
    end)
    HelpBtn(
        nf, testFusionBtn, L["Help: Test Fusion Badge"],
        L["Plays the live multi-color fusion animation on your Minimap icon with sample Whisper (pink), Group (blue), and Guild (green) counters."],
        L["Hover over the SC minimap icon after fusion to see the numbers split cleanly around the icon, or type '/sc preview clear' to reset."]
    )
    Search.Register({
        kind = "action",
        title = L["Test Fusion Badge"],
        actionLabel = L["Test Fusion Badge"],
        widget = testFusionBtn,
        helpTitle = L["Help: Test Fusion Badge"],
        description = L["Plays the live multi-color fusion animation on your Minimap icon with sample Whisper (pink), Group (blue), and Guild (green) counters."],
        howText = L["Hover over the SC minimap icon after fusion to see the numbers split cleanly around the icon, or type '/sc preview clear' to reset."],
        onTrigger = function()
            if ns.MinimapPreview and ns.MinimapPreview.ShowTestPreview then
                ns.MinimapPreview:ShowTestPreview("badge fusion")
            end
        end,
    })

    AddDeps(deps.defaultBtns, testFusionBtn)
    AddDeps(deps.chat, styleLbl, styleRow, testFusionBtn)
    return testFusionBtn
end

local function BuildNotificationsTab(nf, deps, refs, NotifySettingChanged)
    local mutedHeader = AddSectionHeader(
        nf,
        L["Muted Items & Players Summary"],
        nil,
        -6,
        L["Help: Muted Items Summary"],
        L["Shows a live summary of notification categories you silenced and how many individual players or conversations are currently muted."],
        L["Click 'Re-enable Alerts' or 'Unmute All Players' anytime if you accidentally silenced something via the toast crossed-bell button."]
    )

    local mutedStatusLbl = nf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    mutedStatusLbl:SetPoint("TOPLEFT", mutedHeader, "BOTTOMLEFT", 4, -6)
    mutedStatusLbl:SetPoint("TOPRIGHT", nf, "TOPRIGHT", -16, -30)
    mutedStatusLbl:SetJustifyH("LEFT")
    mutedStatusLbl:SetWordWrap(true)

    local mutedBtnRow = CreateFrame("Frame", nil, nf)
    mutedBtnRow:SetPoint("TOPLEFT", mutedStatusLbl, "BOTTOMLEFT", 0, -6)
    mutedBtnRow:SetSize(560, 26)

    local unmuteAlertsBtn = ns.Theme:CreateButton(mutedBtnRow, 150, 22, L["Re-enable Alerts"], "default")
    ns.Theme:AutoFitButton(unmuteAlertsBtn, 128, 16, 200)
    unmuteAlertsBtn:SetPoint("LEFT", mutedBtnRow, "LEFT", 0, 0)
    unmuteAlertsBtn:SetScript("OnClick", function()
        local s = ns.db and ns.db.settings
        if s then
            s.doNotDisturb = false
            s.friendOnlineAlertToast = true
            s.friendOfflineAlertToast = true
            s.addonMsgToast = true
            s.msgPreviewEnabled = true
            s.msgPreviewPromptAnswered = true
            s.worldBuffsAlerts = true
            s.worldBuffsExpiryAlert = true
            s.clanLfgAlertEnabled = true
            s.clanSignupAlertEnabled = true
            s.clanEventReminders = true
            s.spotterScoutAlert = true
            s.groupAvoidAlert = true
            s.spotterAutoShowHUD = true
            s.chatSound = true
            if s.alerts then s.alerts.toast = true end
        end
        NotifySettingChanged("CLAN_UPDATED")
        for _, sync in ipairs(syncFns) do sync() end
    end)

    local unmutePlayersBtn = ns.Theme:CreateButton(mutedBtnRow, 174, 22, L["Unmute All Players"], "default")
    ns.Theme:AutoFitButton(unmutePlayersBtn, 144, 16, 220)
    unmutePlayersBtn:SetPoint("LEFT", unmuteAlertsBtn, "RIGHT", 8, 0)
    unmutePlayersBtn:SetScript("OnClick", function()
        if ns.db and ns.db.socialMeta and ns.Compat and ns.Compat.ScopeKey then
            local tbl = ns.db.socialMeta[ns.Compat.ScopeKey()]
            if type(tbl) == "table" then
                for _, meta in pairs(tbl) do
                    if type(meta) == "table" and meta.notifyMuted ~= nil then
                        meta.notifyMuted = nil
                    end
                end
            end
        end
        if ns.db and ns.db.settings and type(ns.db.settings.chatMutedThreads) == "table" then
            wipe(ns.db.settings.chatMutedThreads)
        end
        NotifySettingChanged("SOCIAL_UPDATED")
        ns:Emit("WATCHLIST_UPDATED")
        ns:Emit("CHAT_UPDATED")
        for _, sync in ipairs(syncFns) do sync() end
    end)

    refs.mutedStatusLbl = mutedStatusLbl
    refs.unmuteAlertsBtn = unmuteAlertsBtn
    refs.unmutePlayersBtn = unmutePlayersBtn

    local mpSectionBottom = BuildMinimapPreviewSettingsSection(nf, mutedBtnRow, deps, NotifySettingChanged)

    local wlAlertHeader = AddSectionHeader(
        nf,
        L["Online alerts for Watchlist"],
        mpSectionBottom,
        -12,
        L["Help: Watchlist Online Alerts"],
        L["Prints a local chat notification whenever a Watchlist character transitions from offline to online."],
        L["Triggered safely when /who, Friends, Guild, Battle.net, or Nearby spots a watched friend online (120s anti-spam debounce)."]
    )

    local alertCb = CreateCheckbox(
        nf, L["Online alerts for Watchlist"], wlAlertHeader, -6,
        function() return ns.db and ns.db.settings.alerts and ns.db.settings.alerts.chat end,
        function(checked)
            if ns.db and ns.db.settings.alerts then ns.db.settings.alerts.chat = checked end
            NotifySettingChanged()
        end,
        L["Help: Watchlist Online Alerts"],
        L["Prints a local chat notification whenever a Watchlist character transitions from offline to online."],
        L["Triggered safely when /who, Friends, Guild, Battle.net, or Nearby spots a watched friend online (120s anti-spam debounce)."]
    )
    local watchToastCb = CreateCheckbox(
        nf, L["Show floating Toast when Watchlist player comes online"], alertCb, -6,
        function() return not ns.db or not ns.db.settings.alerts or ns.db.settings.alerts.toast ~= false end,
        function(checked)
            if ns.db and ns.db.settings.alerts then ns.db.settings.alerts.toast = checked end
            NotifySettingChanged()
        end,
        L["Help: Watchlist Toast Alert"],
        L["Displays a compact floating Notification Toast at the top of the screen when a watched player transitions online (outside muted rows)."],
        L["Uncheck to stop floating Watchlist toasts globally, or click the bell icon beside any name in the Social/Watchlist window (O) to mute per player."]
    )
    local soundCb = CreateCheckbox(
        nf, L["Play sound on Watchlist online alert"], watchToastCb, -6,
        function() return ns.db and ns.db.settings.alerts and ns.db.settings.alerts.sound end,
        function(checked)
            if ns.db and ns.db.settings.alerts then ns.db.settings.alerts.sound = checked end
        end,
        L["Help: Alert Sound"],
        L["Plays a subtle Blizzard UI chime alongside the local chat online alert."],
        L["Check to hear an audio chime when a watched friend comes online."]
    )
    AddDeps(deps.watch, alertCb, watchToastCb, soundCb)

    local friendAlertHeader = AddSectionHeader(
        nf, L["Friend Online Alerts"], soundCb, -14,
        L["Help: Friend Online Alerts"],
        L["Notifies you cleanly when Character Friends or Battle.net friends enter World of Warcraft: Forever, after an 8-second post-login grace window and 120-second anti-spam cooldown."],
        L["Enabled for All Friends by default; mute specific players via the bell icon in the Social (O) list, or switch to Favorites Only or Off below."]
    )
    local friendAlertModeRow = CreateChoiceRow(nf, friendAlertHeader, -6, {
        { value = "all", label = L["All Friends"], width = 152 },
        { value = "favorites", label = L["Favorites Only"], width = 166 },
        { value = "off", label = L["Off"], width = 112 },
    }, function()
        return ns.db and ns.db.settings.friendOnlineAlertMode or "all"
    end, function(val)
        ns.db.settings.friendOnlineAlertMode = val
        NotifySettingChanged()
    end)
    local friendToastCb = CreateCheckbox(
        nf, L["Show floating Toast when Friends come online"], friendAlertModeRow, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.friendOnlineAlertToast ~= false end,
        function(checked) ns.db.settings.friendOnlineAlertToast = checked; NotifySettingChanged() end,
        L["Help: Friend Online Toast"],
        L["Displays a compact floating Notification Toast when a tracked Favorite or Friend logs into WoW: Forever."],
        L["Left-click the toast to jump straight to that friend in the Social tab."]
    )
    local friendChatCb = CreateCheckbox(
        nf, L["Print clickable [Social] summary line on Friend login"], friendToastCb, -6,
        function() return ns.db and ns.db.settings.friendOnlineAlertChat == true end,
        function(checked) ns.db.settings.friendOnlineAlertChat = checked; NotifySettingChanged() end,
        L["Help: Friend Online Chat"],
        L["Prints an extra local SocialCentral chat line with a clickable [Social] link whenever a friend alert fires."],
        L["Disabled by default to avoid duplicating Blizzard's standard friend-online chat line."]
    )
    local friendSoundCb = CreateCheckbox(
        nf, L["Play audio chime when Friends come online"], friendChatCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.friendOnlineAlertSound ~= false end,
        function(checked) ns.db.settings.friendOnlineAlertSound = checked end,
        L["Help: Friend Online Sound"],
        L["Plays a subtle Battle.net UI chime when a Friend Online alert triggers."],
        L["Uncheck for silent visual friend login alerts only."]
    )
    local friendOfflineToastCb = CreateCheckbox(
        nf, L["Show floating Toast when Friends disconnect"], friendSoundCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.friendOfflineAlertToast ~= false end,
        function(checked) ns.db.settings.friendOfflineAlertToast = checked; NotifySettingChanged() end,
        L["Help: Friend Disconnect Toast"],
        L["Displays a compact floating Notification Toast when a friend or tracked player logs off or disconnects from WoW."],
        L["Left-click the toast to view the player in the Social directory."]
    )
    local friendOfflineChatCb = CreateCheckbox(
        nf, L["Print clickable [Social] summary line on Friend logoff"], friendOfflineToastCb, -6,
        function() return ns.db and ns.db.settings.friendOfflineAlertChat == true end,
        function(checked) ns.db.settings.friendOfflineAlertChat = checked; NotifySettingChanged() end,
        L["Help: Friend Disconnect Chat"],
        L["Prints a local chat notification with a clickable [Social] shortcut when a friend logs off."],
        L["Disabled by default to prevent chat clutter."]
    )

    local addonNotifyHeader = AddSectionHeader(
        nf, L["Addon Message Notifications"], friendOfflineChatCb, -14,
        L["Help: Addon Message Notifications"],
        L["Customize how SocialCentral alerts you when incoming addon-only messages (Direct Messages, Private Rooms, Invites, Alliance Chat, and Guild Alerts) arrive."],
        L["Combine the floating Toast pill, clickable [SC] chat lines, Minimap & Side-Tab unread badges, and taskbar flashing to suit your screen."]
    )
    local addonToastCb = CreateCheckbox(
        nf, L["Show floating popup Toast for incoming addon messages"], addonNotifyHeader, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.addonMsgToast ~= false end,
        function(checked) ns.db.settings.addonMsgToast = checked; NotifySettingChanged() end,
        L["Help: Floating Notification Toast"],
        L["Displays a compact, draggable 100%-opaque pill near the top of your screen when a peer messages you via the addon or sends a room invite."],
        L["Left-click the pill to jump directly to the conversation (deferred automatically after combat), hover to pause, or right-click to dismiss."]
    )
    local toastResetRow = CreateFrame("Frame", nil, nf)
    toastResetRow:SetSize(460, 26)
    toastResetRow:SetPoint("TOPLEFT", addonToastCb, "BOTTOMLEFT", 0, -4)
    local resetToastPosBtn = ns.Theme:CreateButton(toastResetRow, 190, 22, L["Reset Notification Position"], "default")
    ns.Theme:AutoFitButton(resetToastPosBtn, 160, 18, 280)
    resetToastPosBtn:SetPoint("LEFT", toastResetRow, "LEFT", 24, 0)
    resetToastPosBtn:SetScript("OnClick", function()
        if ns.Theme and ns.Theme.ResetWindowPosition then ns.Theme:ResetWindowPosition("notification_toast") end
    end)
    HelpBtn(toastResetRow, resetToastPosBtn, L["Help: Reset Notification Position"], L["Moves the floating notification popup back to its default top-center screen position."], L["Also available anytime by right-clicking any floating notification."])
    Search.Register({
        kind = "action",
        title = L["Reset Notification Position"],
        actionLabel = L["Reset Notification Position"],
        widget = resetToastPosBtn,
        helpTitle = L["Help: Reset Notification Position"],
        description = L["Moves the floating notification popup back to its default top-center screen position."],
        howText = L["Also available anytime by right-clicking any floating notification."],
        onTrigger = function() resetToastPosBtn:Click() end,
    })

    local addonEchoCb = CreateCheckbox(
        nf, L["Print received [SC] addon messages in Blizzard Chat immediately"], toastResetRow, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.addonMsgChatEcho ~= false end,
        function(checked) ns.db.settings.addonMsgChatEcho = checked; NotifySettingChanged() end,
        L["Help: Addon Chat Echo"],
        L["Blizzard hides raw addon packets from standard chat frames. Enabling this echoes incoming [SC] messages with a clickable sender link immediately into selected Blizzard chat tabs."],
        L["Also works even while SocialCentral's Conversations window is open so you can read messages directly in WoW's native chat box."]
    )
    local addonEchoSentCb = CreateCheckbox(
        nf, L["Also show my sent [SC] addon messages in Blizzard Chat immediately"], addonEchoCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.addonMsgChatEchoSent ~= false end,
        function(checked) ns.db.settings.addonMsgChatEchoSent = checked; NotifySettingChanged() end,
        L["Help: Echo Sent Addon Chat"],
        L["Displays messages you send inside SocialCentral immediately as [SC] whisper lines in your checked Blizzard chat tabs."],
        L["Helps follow the full back-and-forth conversation right inside Blizzard's General or custom chat tabs."]
    )

    local officialChatTabsRow = CreateFrame("Frame", nil, nf)
    officialChatTabsRow:SetSize(540, 48)
    officialChatTabsRow:SetPoint("TOPLEFT", addonEchoSentCb, "BOTTOMLEFT", 4, -6)
    local tabsRowLbl = officialChatTabsRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    tabsRowLbl:SetPoint("TOPLEFT", 0, -2)
    tabsRowLbl:SetText("|cffb8c2d0" .. L["Blizzard chat tabs displaying [SC] addon chat:"] .. "|r")
    HelpBtn(
        officialChatTabsRow, tabsRowLbl, L["Help: Official Chat Tabs for [SC]"],
        L["Choose which Blizzard chat windows (General, custom Whispers tab, etc.) display incoming and sent [SC] addon messages."],
        L["You can also toggle this directly inside Blizzard's right-click Tab Settings window via the '[SC] Addon Chat' checkbox."]
    )
    local tabCheckboxes = {}
    for cid = 1, 10 do
        local tcb = CreateFrame("CheckButton", nil, officialChatTabsRow, "UICheckButtonTemplate")
        tcb:SetSize(22, 22)
        tcb.text = tcb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        tcb.text:SetPoint("LEFT", tcb, "RIGHT", 2, 0)
        tcb:SetScript("OnClick", function(self)
            if ns.db and ns.db.settings then
                if type(ns.db.settings.addonChatFrames) ~= "table" then
                    ns.db.settings.addonChatFrames = { [1] = true }
                end
                ns.db.settings.addonChatFrames[cid] = self:GetChecked() and true or false
                NotifySettingChanged()
            end
        end)
        tabCheckboxes[cid] = tcb
    end
    syncFns[#syncFns + 1] = function()
        local framesCfg = ns.db and ns.db.settings and ns.db.settings.addonChatFrames
        local xOff, yOff = 0, -20
        for cid = 1, 10 do
            local tcb = tabCheckboxes[cid]
            local cf = _G["ChatFrame" .. tostring(cid)]
            local winName, _, _, _, _, _, isShownFlag = nil, nil, nil, nil, nil, nil, false
            if GetChatWindowInfo then winName, _, _, _, _, _, isShownFlag = GetChatWindowInfo(cid) end
            local isActive = (cid == 1) or (cf and (cf.isDocked or cf:IsShown())) or (winName and winName ~= "" and isShownFlag)
            if isActive then
                local label = (winName and winName ~= "" and winName) or (cf and cf.name) or tostring(cid)
                tcb.text:SetText(label)
                local itemW = math.min(130, math.max(58, (tcb.text:GetStringWidth() or 40) + 30))
                if xOff > 0 and (xOff + itemW) > 520 then
                    xOff = 0
                    yOff = -42
                end
                tcb:ClearAllPoints()
                tcb:SetPoint("TOPLEFT", officialChatTabsRow, "TOPLEFT", xOff, yOff)
                local checked = (type(framesCfg) ~= "table" and cid == 1) or (type(framesCfg) == "table" and framesCfg[cid] == true)
                tcb:SetChecked(checked and true or false)
                tcb:Show()
                xOff = xOff + itemW + 6
            else
                tcb:Hide()
            end
        end
        officialChatTabsRow:SetHeight((yOff < -30) and 68 or 48)
    end
    AddDeps(deps.chat, tabsRowLbl)
    for cid = 1, 10 do
        AddDeps(deps.chat, tabCheckboxes[cid])
    end

    local addonFlashCb = CreateCheckbox(
        nf, L["Pulse taskbar icon when high-priority addon messages arrive"], officialChatTabsRow, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.addonMsgTaskbarFlash ~= false end,
        function(checked) ns.db.settings.addonMsgTaskbarFlash = checked; NotifySettingChanged() end,
        L["Help: Taskbar Flash"],
        L["Calls Blizzard's FlashClientIcon() so the WoW window highlights on your Windows taskbar if you are alt-tabbed when a DM or invite arrives."],
        L["Only flashes for priority incoming notifications and does nothing while you are already viewing the open thread."]
    )
    local addonMinimapBadgeCb = CreateCheckbox(
        nf, L["Show numeric unread counter on Minimap icon"], addonFlashCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.addonMsgMinimapBadge ~= false end,
        function(checked) ns.db.settings.addonMsgMinimapBadge = checked; NotifySettingChanged() end,
        L["Help: Minimap Unread Counter"],
        L["Displays a compact red unread counter badge directly on the corner of the SocialCentral Minimap button alongside the golden ring tint."],
        L["Clears automatically as soon as you open and view the unread threads or invitations."]
    )
    local minimapBadgeStyleBottom = BuildMinimapBadgeStyleControls(nf, addonMinimapBadgeCb, deps, NotifySettingChanged)
    local addonTabBadgesCb = CreateCheckbox(
        nf, L["Show unread counters on Social (O) & Guild (J) side-tabs"], minimapBadgeStyleBottom, -8,
        function() return not ns.db or not ns.db.settings or ns.db.settings.addonMsgTabBadges ~= false end,
        function(checked) ns.db.settings.addonMsgTabBadges = checked; NotifySettingChanged() end,
        L["Help: Side-Tab Unread Counters"],
        L["Displays unread Direct/Room message counts on the Social (O) side-tab and new Guild Event/LFG alert counts on the Guild (J) side-tab."],
        L["Uncheck if you prefer completely plain bookmark tabs without counter pills."]
    )
    local testToastBtn = ns.Theme:CreateButton(nf, 190, 22, L["Test Notification Toast"], "default")
    ns.Theme:AutoFitButton(testToastBtn, 160, 18, 260)
    testToastBtn:SetPoint("TOPLEFT", addonTabBadgesCb, "BOTTOMLEFT", 0, -8)
    testToastBtn:SetScript("OnClick", function()
        if ns.NotificationToast and ns.NotificationToast.ShowTestNotification then
            ns.NotificationToast:ShowTestNotification()
        end
    end)
    HelpBtn(nf, testToastBtn, L["Help: Test Notification Toast"], L["Spawns a sample floating Notification Toast pill with sound so you can preview its look and drag it to your preferred screen position."], L["Click to show the pill, drag it anywhere on screen, or reset positions anytime with '/sc resetpos'."])
    Search.Register({
        kind = "action",
        title = L["Test Notification Toast"],
        actionLabel = L["Test Notification Toast"],
        widget = testToastBtn,
        helpTitle = L["Help: Test Notification Toast"],
        description = L["Spawns a sample floating Notification Toast pill with sound so you can preview its look and drag it to your preferred screen position."],
        howText = L["Click to show the pill, drag it anywhere on screen, or reset positions anytime with '/sc resetpos'."],
        onTrigger = function() testToastBtn:Click() end,
    })

    local chatSettingsHeader = AddSectionHeader(
        nf, L["Conversations & Sound Alerts"], testToastBtn, -14,
        L["Help: Conversations & Sounds"],
        L["Separately control sound chimes by channel type and decide whether WoW native Guild/Group channels are mirrored inside Conversations."],
        L["By default, SocialCentral focuses on Direct Whispers and Addon Private Rooms while keeping Guild and Party chat silent."]
    )
    local chatSoundCb = CreateCheckbox(
        nf, L["Master: Enable Chat Sound Alerts"], chatSettingsHeader, -6,
        function() return ns.db and ns.db.settings.chatSound ~= false end,
        function(checked) ns.db.settings.chatSound = checked; NotifySettingChanged("CHAT_UPDATED") end,
        L["Help: Chat Sound Alert"],
        L["Master switch for incoming conversation sound chimes across SocialCentral."],
        L["Uncheck to mute all SocialCentral conversation chimes without affecting muted individual threads."]
    )
    local chatSoundWhispersCb = CreateCheckbox(
        nf, L["Play chime on Whispers & Battle.net"], chatSoundCb, -6,
        function() return ns.db and ns.db.settings.chatSoundWhispers ~= false end,
        function(checked) ns.db.settings.chatSoundWhispers = checked end,
        L["Help: Whisper Sounds"],
        L["Plays a subtle audio chime when an incoming character Whisper or Battle.net whisper arrives while unfocused."],
        L["Requires Master Chat Sound Alerts to be enabled; individual senders can still be muted from the Conversations panel."]
    )
    local chatSoundRoomsCb = CreateCheckbox(
        nf, L["Play chime on SocialCentral Private Rooms"], chatSoundWhispersCb, -6,
        function() return ns.db and ns.db.settings.chatSoundRooms ~= false end,
        function(checked) ns.db.settings.chatSoundRooms = checked end,
        L["Help: Private Room Sounds"],
        L["Plays a chime when a peer sends a message or invite inside an addon Private Room (SCentral1)."],
        L["Turn off if your Private Room is noisy while still keeping Whisper alerts enabled."]
    )
    local chatSoundAllianceCb = CreateCheckbox(
        nf, L["Play chime on Alliance Chat messages"], chatSoundRoomsCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.chatSoundAlliance ~= false end,
        function(checked) ns.db.settings.chatSoundAlliance = checked end,
        L["Help: Alliance Chat Sound"],
        L["Plays a distinct audio chime when an authorized Alliance member posts in cross-guild Alliance Chat."],
        L["Requires Master Chat Sound Alerts to be enabled."]
    )
    local chatSoundGuildCb = CreateCheckbox(
        nf, L["Play chime on Guild & Officer chat (off by default)"], chatSoundAllianceCb, -6,
        function() return ns.db and ns.db.settings.chatSoundGuild == true end,
        function(checked) ns.db.settings.chatSoundGuild = checked end,
        L["Help: Guild Chat Sound"],
        L["Controls whether mirrored Guild and Officer chat lines trigger a sound chime (disabled by default)."],
        L["Leave unchecked so WoW Guild chat never beeps inside SocialCentral."]
    )
    local chatSoundGroupCb = CreateCheckbox(
        nf, L["Play chime on Party / Raid / Instance chat (off by default)"], chatSoundGuildCb, -6,
        function() return ns.db and ns.db.settings.chatSoundGroup == true end,
        function(checked) ns.db.settings.chatSoundGroup = checked end,
        L["Help: Group Chat Sound"],
        L["Controls whether mirrored Party, Raid, or Instance chat lines trigger a sound chime (disabled by default)."],
        L["Leave unchecked so dungeon and raid chat remains silent in SocialCentral."]
    )
    local chatMirrorCb = CreateCheckbox(
        nf, L["Mirror WoW Guild / Party / Raid channels inside Conversations"], chatSoundGroupCb, -6,
        function() return ns.db and ns.db.settings.chatMirrorChannels == true end,
        function(checked) ns.db.settings.chatMirrorChannels = checked; NotifySettingChanged("CHAT_UPDATED") end,
        L["Help: Mirror WoW Channels"],
        L["Enabled by default: mirrors WoW Guild, Officer, Party, Raid, and Instance messages inside Conversations."],
        L["Uncheck if you want Conversations to focus only on Direct Whispers, Battle.net, Alliance Chat, and Private Rooms."]
    )
    local chatChannelUnreadCb = CreateCheckbox(
        nf, L["Count mirrored Guild/Group lines as unread on Minimap"], chatMirrorCb, -6,
        function() return ns.db and ns.db.settings.chatChannelUnread == true end,
        function(checked) ns.db.settings.chatChannelUnread = checked; NotifySettingChanged("CHAT_UPDATED") end,
        L["Help: Guild Unread Badge"],
        L["By default, only Direct Whispers, BNet whispers, and SocialCentral Private Rooms count toward the Minimap unread badge and tooltip."],
        L["Leave unchecked so noisy Guild channels never trigger unread alerts on your Minimap icon."]
    )
    local addonDirectCb = CreateCheckbox(
        nf, L["Enable Verified In-Addon 1-on-1 Direct Chat"], chatChannelUnreadCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.addonDirectChat ~= false end,
        function(checked) ns.db.settings.addonDirectChat = checked; NotifySettingChanged("CHAT_UPDATED") end,
        L["Help: Addon Direct Chat"],
        L["Enables full 1-on-1 chat inside SocialCentral (with delivery confirmation and location share) ONLY when both players have the addon active."],
        L["When unchecked or when the other player lacks SocialCentral, sending falls back cleanly to official WoW Whisper or Battle.net chat."]
    )
    local chatDirectOfficialCb = CreateCheckbox(
        nf, L["Send /w, Battle.net & Guild/Group messages directly in 1 click"], addonDirectCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.chatDirectOfficialSend ~= false end,
        function(checked) ns.db.settings.chatDirectOfficialSend = checked; NotifySettingChanged("CHAT_UPDATED") end,
        L["Help: 1-Click Direct Official Chat"],
        L["When checked, clicking Send or pressing Enter in Conversations sends Whispers, Battle.net, Guild, and Group messages immediately without needing a second Enter."],
        L["Strictly triggered only by your manual Send click/Enter outside combat or boss chat lockdowns; safely falls back to pre-filling the chat bar when restricted."]
    )
    AddDeps(deps.defaultBtns, unmuteAlertsBtn, unmutePlayersBtn, resetToastPosBtn, testToastBtn)
    AddDeps(deps.chat, addonToastCb, resetToastPosBtn, addonEchoCb, addonEchoSentCb, addonFlashCb, chatSoundCb, chatSoundWhispersCb, chatSoundRoomsCb, chatSoundAllianceCb, chatSoundGuildCb, chatSoundGroupCb, chatMirrorCb, chatChannelUnreadCb, addonDirectCb, chatDirectOfficialCb)

    local guildAlertsHeader = AddSectionHeader(
        nf, L["Guild, LFG & World Buff Alerts"], chatDirectOfficialCb, -14,
        L["Help: Guild & World Buff Alerts"],
        L["Configure alerts for Guild LFG calls, scheduled Events, World Buff announcements, Scout shares, and Group Avoid safety warnings."],
        L["Disable any alert type here or click the crossed-bell button directly on any notification popup."]
    )
    local clanLfgAlertCb = CreateCheckbox(
        nf, L["Notify in chat when guildmates look for Dungeon / LFG"], guildAlertsHeader, -6,
        function() return ns.db and ns.db.settings.clanLfgAlertEnabled == true end,
        function(checked) ns.db.settings.clanLfgAlertEnabled = checked; NotifySettingChanged("CLAN_UPDATED") end,
        L["Help: Clan Dungeon Alerts"],
        L["Notifies you in chat (with optional sound and clickable Whisper/Clan links) whenever a guildmate looks for a Dungeon group."],
        L["Configure below to enable/disable alerts, restrict to Dungeons only, or filter specific dungeon keywords."]
    )
    local clanLfgDngOnlyCb = CreateCheckbox(
        nf, L["Alert only for Dungeon calls (exclude raids/PvP)"], clanLfgAlertCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.clanLfgAlertDungeonsOnly ~= false end,
        function(checked) ns.db.settings.clanLfgAlertDungeonsOnly = checked; NotifySettingChanged("CLAN_UPDATED") end,
        L["Help: Clan Dungeon Filter"],
        L["Filters Clan LFG alerts to Dungeon calls, ignoring Raids and PvP announcements."],
        L["Uncheck if you want to be notified for all Clan LFG activity types (Dungeons, Raids, World Bosses, PvP)."]
    )
    local clanLfgNearLevelCb = CreateCheckbox(
        nf, L["Notify only for nearby-level LFG/LFM (±5 levels)"], clanLfgDngOnlyCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.clanLfgAlertNearLevel ~= false end,
        function(checked) ns.db.settings.clanLfgAlertNearLevel = checked; NotifySettingChanged("CLAN_UPDATED") end,
        L["Help: Nearby-Level LFG Alerts"],
        L["Filters group-finder alerts to players within ±5 levels of your character (or max-level peers) so leveling alerts stay relevant."],
        L["Keep checked to avoid alerts for dungeons far above or below your current level."]
    )
    local clanLfgAlertSoundCb = CreateCheckbox(
        nf, L["Play chime sound on Clan Dungeon LFG alert"], clanLfgNearLevelCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.clanLfgAlertSound ~= false end,
        function(checked) ns.db.settings.clanLfgAlertSound = checked end,
        L["Help: Clan Alert Sound"],
        L["Plays a subtle Blizzard UI chime alongside your chat alert when a matching Clan Dungeon LFG call arrives."],
        L["Requires 'Notify in chat when guildmates look for Dungeon / LFG' to be enabled."]
    )

    local clanFilterRow = CreateFrame("Frame", nil, nf)
    clanFilterRow:SetPoint("TOPLEFT", clanLfgAlertSoundCb, "BOTTOMLEFT", 0, -6)
    clanFilterRow:SetSize(540, 46)
    local clanFilterLbl = clanFilterRow:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    clanFilterLbl:SetPoint("TOPLEFT", 2, 0)
    clanFilterLbl:SetPoint("TOPRIGHT", -4, 0)
    clanFilterLbl:SetJustifyH("LEFT")
    clanFilterLbl:SetWordWrap(true)
    clanFilterLbl:SetText(L["Dungeon keywords filter (comma-separated, blank = all):"])
    local clanFilterInput = ns.Theme:CreateEditBox(clanFilterRow, { width = 260, height = 22, maxLetters = 120, clearButton = true })
    clanFilterInput:SetPoint("TOPLEFT", clanFilterLbl, "BOTTOMLEFT", 0, -4)
    clanFilterInput:SetScript("OnEnterPressed", function(self)
        if ns.db and ns.db.settings then ns.db.settings.clanLfgAlertFilter = ns.Compat.CleanInput(self:GetText() or "") or "" end
        self:ClearFocus()
    end)
    clanFilterInput:SetScript("OnEditFocusLost", function(self)
        if ns.db and ns.db.settings then ns.db.settings.clanLfgAlertFilter = ns.Compat.CleanInput(self:GetText() or "") or "" end
    end)
    HelpBtn(clanFilterRow, clanFilterInput, L["Help: Clan Alert Keywords"], L["Comma-separated dungeon or level keywords (e.g. 'BRD, Strat, tank') so Clan Dungeon Alerts only fire on matching requests."], L["Leave blank to receive alerts for all Dungeon LFG calls inside your guild."])
    Search.Register({
        kind = "input",
        title = L["Dungeon keywords filter (comma-separated, blank = all):"],
        widget = clanFilterInput,
        helpTitle = L["Help: Clan Alert Keywords"],
        description = L["Comma-separated dungeon or level keywords (e.g. 'BRD, Strat, tank') so Clan Dungeon Alerts only fire on matching requests."],
        howText = L["Leave blank to receive alerts for all Dungeon LFG calls inside your guild."],
    })
    syncFns[#syncFns + 1] = function()
        if not clanFilterInput:HasFocus() then
            clanFilterInput:SetText((ns.db and ns.db.settings and ns.db.settings.clanLfgAlertFilter) or "")
        end
    end

    local clanEventAlertCb = CreateCheckbox(
        nf, L["Notify when guildmates post a new Guild Event"], clanFilterRow, -6,
        function() return ns.db and ns.db.settings.clanEventAlertEnabled == true end,
        function(checked) ns.db.settings.clanEventAlertEnabled = checked; NotifySettingChanged("CLAN_UPDATED") end,
        L["Help: Guild Event Alerts"],
        L["Alerts you with a clickable notification and toast whenever a guildmate schedules a new Raid, Quest, PvP, or Custom Guild Event."],
        L["Enable to never miss scheduled guild activities even when outside Dungeon LFG."]
    )
    local clanSignupAlertCb = CreateCheckbox(
        nf, L["Notify me when guildmates sign up to my Events"], clanEventAlertCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.clanSignupAlertEnabled ~= false end,
        function(checked) ns.db.settings.clanSignupAlertEnabled = checked; NotifySettingChanged("CLAN_UPDATED") end,
        L["Help: Guild Signup Alerts"],
        L["Notifies you as the event organizer whenever a guildmate signs up (or declines) on one of your active Guild Events."],
        L["Triggers only on events you created so your chat stays clutter-free."]
    )
    local clanEventRemindersCb = CreateCheckbox(
        nf, L["Remind me 15m and 5m before confirmed Guild & Calendar events"], clanSignupAlertCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.clanEventReminders ~= false end,
        function(checked) ns.db.settings.clanEventReminders = checked; NotifySettingChanged() end,
        L["Help: Guild Event Reminders"],
        L["Shows clickable reminders 15 minutes and 5 minutes before scheduled Guild Events or Blizzard Calendar raids you confirmed or organized."],
        L["Click the reminder toast or chat link to jump straight to your Events tab in Guild (J)."]
    )
    local buffAlertCb = CreateCheckbox(
        nf, L["World Buff Drop Alerts"], clanEventRemindersCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.worldBuffsAlerts ~= false end,
        function(checked) if ns.db and ns.db.settings then ns.db.settings.worldBuffsAlerts = checked end; NotifySettingChanged() end,
        L["Help: World Buff Drop Alerts"],
        L["Prints a local chat notification whenever an NPC announces the turn-in of Onyxia, Nefarian, Rend Blackhand, or Hakkar heads in town."],
        L["Alerts you ~6 to 15 seconds before the buff lands so you have time to log in or reposition."]
    )
    local buffSoundCb = CreateCheckbox(
        nf, L["Play chime on World Buff drop alert"], buffAlertCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.worldBuffsSound ~= false end,
        function(checked) if ns.db and ns.db.settings then ns.db.settings.worldBuffsSound = checked end end,
        L["Help: World Buff Sound Chime"],
        L["Plays an audio chime when an NPC announces an incoming world buff drop."],
        L["Uncheck if you prefer silent chat notifications only."]
    )
    local buffExpiryCb = CreateCheckbox(
        nf, L["Warn me out of combat when an active World Buff has under 5m left"], buffSoundCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.worldBuffsExpiryAlert ~= false end,
        function(checked) if ns.db and ns.db.settings then ns.db.settings.worldBuffsExpiryAlert = checked end; NotifySettingChanged() end,
        L["Help: World Buff Expiry Warning"],
        L["Alerts you with a chat line and toast outside combat when one of your active Classic World Buffs drops below 5 minutes remaining."],
        L["Helpful before starting a dungeon run or chronobooning / refreshing your buffs."]
    )
    local scoutAlertCb = CreateCheckbox(
        nf, L["Notify on shared Guild Scout sighting alerts"], buffExpiryCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterScoutAlert ~= false end,
        function(checked) ns.db.settings.spotterScoutAlert = checked; NotifySettingChanged() end,
        L["Help: Guild Scout Alerts"],
        L["Shows chat, sound, and popup alerts when a guildmate shares an Enemy Scout sighting."],
        L["Uncheck to mute shared Guild Scout alerts without disabling your own Target Radar."]
    )
    CreateCheckbox(
        nf, L["Warn in chat and toast if an Avoided player joins your party/raid"], scoutAlertCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.groupAvoidAlert ~= false end,
        function(checked) ns.db.settings.groupAvoidAlert = checked; NotifySettingChanged() end,
        L["Help: Group Avoid Warning"],
        L["Immediately alerts you with a warning toast and chat notice if someone on your Avoid list or linked alts enters your party or raid."],
        L["Allows you to address toxic encounters or leave before dungeons and raids start."]
    )

    AddDeps(deps.wb, buffAlertCb, buffSoundCb, buffExpiryCb)
    AddDeps(deps.guild, clanLfgAlertCb, clanLfgDngOnlyCb, clanLfgNearLevelCb, clanLfgAlertSoundCb, clanFilterLbl, clanFilterInput, clanEventAlertCb, clanSignupAlertCb, clanEventRemindersCb, scoutAlertCb)
end

local function BuildRadarTab(rd, deps, NotifySettingChanged, CloseSettingsBeforeJump)
    local spotterHeader = AddSectionHeader(
        rd, L["Screen Clan Radar & Target Selection"], nil, -6,
        L["Help: Screen Clan Radar"],
        L["Detects Enemy, Ally, and Same-Clan players appearing on your screen via nameplates, target, focus, or mouseover using guild-isolated Diplomacy lists."],
        L["Click a row on the floating Target Radar HUD to select that player via Blizzard-legal secure macro click (/targetexact)."]
    )
    local spotterEnabledCb = CreateCheckbox(
        rd, L["Enable On-Screen Clan Spotter (Enemy / Ally / Same Clan)"], spotterHeader, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterEnabled ~= false end,
        function(checked) ns.db.settings.spotterEnabled = checked; NotifySettingChanged() end,
        L["Help: Screen Spotter Master"],
        L["Master toggle for detecting Enemy, Ally, and Same-Clan players on your screen."],
        L["Uncheck to pause screen scanning and hide the Target Radar HUD completely."]
    )
    local spotterAutoHudCb = CreateCheckbox(
        rd, L["Auto-open Target Selection Radar HUD on sighting (out of combat)"], spotterEnabledCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterAutoShowHUD ~= false end,
        function(checked) ns.db.settings.spotterAutoShowHUD = checked; NotifySettingChanged() end,
        L["Help: Spotter Auto HUD"],
        L["Automatically opens the floating Target Radar HUD when a flagged player appears while you are out of combat."],
        L["Close the HUD manually at any time or use '/sc radar' to toggle it."]
    )
    local spotterPlateArrowCb = CreateCheckbox(
        rd, L["Show animated red arrow above Radar target nameplate (when visible)"], spotterAutoHudCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterNameplateArrow ~= false end,
        function(checked) ns.db.settings.spotterNameplateArrow = checked; NotifySettingChanged() end,
        L["Help: Animated Target Nameplate Arrow"],
        L["Displays a highly visible pulsing red arrow above your focused or selected Radar target whenever WoW renders their nameplate."],
        L["Blizzard controls player nameplates: press Shift+V for allies/friends or V for enemies anytime to show or hide nameplates."]
    )
    local spotterBadgesCb = CreateCheckbox(
        rd, L["Show Enemy/Ally/Clan badge tags above visible nameplates"], spotterPlateArrowCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterNameplateBadges ~= false end,
        function(checked) ns.db.settings.spotterNameplateBadges = checked; NotifySettingChanged() end,
        L["Help: Nameplate Stance Badges"],
        L["Adds a lightweight non-forbidden [ENEMY]/[ALLY]/[CLAN] indicator tag above player nameplates when readable."],
        L["Disable if you already use heavy custom nameplate addons and prefer HUD-only alerts."]
    )
    local spotterTargetHighlightCb = CreateCheckbox(
        rd, L["Highlight selected target name & info above head (eye-catching banner)"], spotterBadgesCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterNameplateTargetHighlight ~= false end,
        function(checked) ns.db.settings.spotterNameplateTargetHighlight = checked; NotifySettingChanged() end,
        L["Help: Target Nameplate Highlight"],
        L["Displays a high-contrast, thick-outlined banner with your selected target's name, level, guild, and stance right above their head whenever their nameplate is shown."],
        L["Keep enabled so clicking any player or target makes their overhead name unmistakable; press Shift+V / V if nameplates are hidden."]
    )
    local spotterEnemyCb = CreateCheckbox(
        rd, L["Notify when an Enemy Clan player appears on screen"], spotterTargetHighlightCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterNotifyEnemy ~= false end,
        function(checked) ns.db.settings.spotterNotifyEnemy = checked; NotifySettingChanged() end,
        L["Help: Spotter Enemy Alerts"],
        L["Triggers chat, banner, and sound alerts when someone from a guild marked Enemy appears on your screen."],
        L["Per-player cooldown prevents repeated spam if the same player stays nearby."]
    )
    local spotterAllyCb = CreateCheckbox(
        rd, L["Notify when an Ally Clan player appears on screen"], spotterEnemyCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterNotifyAlly ~= false end,
        function(checked) ns.db.settings.spotterNotifyAlly = checked; NotifySettingChanged() end,
        L["Help: Spotter Ally Alerts"],
        L["Triggers chat, banner, and sound alerts when someone from an Ally guild appears on your screen."],
        L["Keep enabled to spot friendly coalition members quickly in the world."]
    )
    local spotterWatchlistCb = CreateCheckbox(
        rd, L["Show direction and distance for Watchlist players on Target Radar"], spotterAllyCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterNotifyWatchlist ~= false end,
        function(checked) ns.db.settings.spotterNotifyWatchlist = checked; NotifySettingChanged() end,
        L["Help: Spotter Watchlist Radar"],
        L["Automatically displays tracked Watchlist players on Target Radar and measures distance when selected."],
        L["Keep checked to track Watchlist targets automatically on screen without waiting for chat links."]
    )
    local spotterFriendsCb = CreateCheckbox(
        rd, L["Show direction and distance for Friends on Target Radar"], spotterWatchlistCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterNotifyFriends ~= false end,
        function(checked) ns.db.settings.spotterNotifyFriends = checked; NotifySettingChanged() end,
        L["Help: Spotter Friends Radar"],
        L["Displays WoW Friends and Battle.net Friends on Target Radar and shows range when selected."],
        L["Combine with 'Ignore Party/Raid members' below to hide friends once you already invited them into your group."]
    )
    local spotterBlockedCb = CreateCheckbox(
        rd, L["Notify when a Blocked or Avoided player appears nearby"], spotterFriendsCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterNotifyBlocked ~= false end,
        function(checked) ns.db.settings.spotterNotifyBlocked = checked; NotifySettingChanged() end,
        L["Help: Spotter Blocked Alerts"],
        L["Alerts and displays on Target Radar whenever someone on your WoW Ignore list or SocialCentral 'Avoid' red flag appears nearby."],
        L["Strangers outside Friends, Watchlist, Guild/Diplomacy, and Blocked lists are never scanned repeatedly."]
    )
    local spotterSameCb = CreateCheckbox(
        rd, L["Notify when a Same Clan guildmate appears on screen"], spotterBlockedCb, -6,
        function() return ns.db and ns.db.settings and ns.db.settings.spotterNotifySameClan == true end,
        function(checked) ns.db.settings.spotterNotifySameClan = checked; NotifySettingChanged() end,
        L["Help: Spotter Same Clan Alerts"],
        L["Highlights and notifies when one of your own guildmates appears on screen."],
        L["Uncheck if you only want notifications for Ally or Enemy guilds."]
    )
    local spotterIgnoreGroupCb = CreateCheckbox(
        rd, L["Ignore current Party/Raid members on automatic Target Radar"], spotterSameCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterIgnoreGroup ~= false end,
        function(checked) ns.db.settings.spotterIgnoreGroup = checked; NotifySettingChanged() end,
        L["Help: Spotter Ignore Group"],
        L["Hides automatic Target Radar popups for players who are already in your current Party or Raid group."],
        L["Recommended to keep checked to avoid screen clutter during dungeons and raids."]
    )
    local spotterSoundCb = CreateCheckbox(
        rd, L["Play alert chime on Enemy / Ally Clan sighting"], spotterIgnoreGroupCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterSound ~= false end,
        function(checked) ns.db.settings.spotterSound = checked; NotifySettingChanged() end,
        L["Help: Spotter Sound"],
        L["Plays a distinct alert chime when an Enemy, Ally, or Same-Clan player triggers a Spotter notification."],
        L["Uncheck for silent visual alerts only."]
    )
    local spotterLockCb = CreateCheckbox(
        rd, L["Lock Target Radar HUD position"], spotterSoundCb, -6,
        function() return ns.db and ns.db.settings and ns.db.settings.spotterLockHUD == true end,
        function(checked) ns.db.settings.spotterLockHUD = checked; NotifySettingChanged() end,
        L["Help: Lock Target Radar HUD"],
        L["Prevents accidental dragging of the floating Target Radar pill during gameplay."],
        L["Check after placing Target Radar where you want it on screen."]
    )

    local buffsHeader = AddSectionHeader(
        rd, L["World Buffs (Classic & Forever)"], spotterLockCb, -14,
        L["Help: World Buffs"],
        L["Tracks active Classic World Buffs, detects city drop announcements in real time, and lets you report your current buffs to party, raid, or guild."],
        L["Click 'Post in Chat' to pre-fill your buffs into chat, or browse the list to check sources, drop timers, and WoW Forever raid-suppression rules."]
    )
    local buffMapPinsCb = CreateCheckbox(
        rd, L["Show World Buff pins on World Map (M)"], buffsHeader, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.worldBuffsMapPins ~= false end,
        function(checked)
            if ns.db and ns.db.settings then ns.db.settings.worldBuffsMapPins = checked end
            if ns.LFGFrameTab and ns.LFGFrameTab.RefreshWorldMapBuffs then ns.LFGFrameTab:RefreshWorldMapBuffs() end
        end,
        L["Help: World Buffs Map Integration"],
        L["Shows interactive World Buff pins at Classic/Forever drop zones and open-world sources directly on the World Map (M)."],
        L["Leave checked to see buff spots directly on the map with hover tooltips, or uncheck to keep only the compact corner summary badge."]
    )

    local openRadarBtn = ns.Theme:CreateButton(rd, 178, 24, L["Open Target Radar"], "primary")
    ns.Theme:AutoFitButton(openRadarBtn, 150, 18, 240)
    openRadarBtn:SetPoint("TOPLEFT", buffMapPinsCb, "BOTTOMLEFT", 4, -10)
    openRadarBtn:SetScript("OnClick", function()
        if ns.SpotterHUD and ns.SpotterHUD.Toggle then ns.SpotterHUD:Toggle() end
    end)
    HelpBtn(rd, openRadarBtn, L["Help: Open Target Radar"], L["Manually opens the Target Radar HUD to test target tracking and range display."], L["Click this button or type '/sc radar' to show or hide the floating radar."])

    local openBuffsBtn = ns.Theme:CreateButton(rd, 210, 24, L["Open World Buffs Tracker"], "default")
    ns.Theme:AutoFitButton(openBuffsBtn, 180, 18, 280)
    openBuffsBtn:SetPoint("LEFT", openRadarBtn, "RIGHT", 32, 0)
    openBuffsBtn:SetScript("OnClick", function()
        CloseSettingsBeforeJump()
        if ns.UI and ns.UI.ShowHub then
            ns.UI:ShowHub("buffs")
        elseif ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
            ns.LFGFrameTab:OpenOfficialModule("buffs")
        end
    end)
    HelpBtn(rd, openBuffsBtn, L["Help: Open World Buffs Tracker"], L["Opens the World Buffs tab in SocialCentral to view active buffs, drop timers, and classic buff sources."], L["Click to review all classic world buffs and their status in WoW Forever."])

    local viewTutorialBtn = ns.Theme:CreateButton(rd, 210, 24, L["View Nameplate Tutorial"], "default")
    ns.Theme:AutoFitButton(viewTutorialBtn, 180, 20, 280)
    viewTutorialBtn:SetPoint("TOPLEFT", openRadarBtn, "BOTTOMLEFT", 0, -8)
    viewTutorialBtn:SetScript("OnClick", function()
        if ns.db and ns.db.settings then ns.db.settings.spotterPlateTutorialShown = false end
        if ns.SpotterHUD and ns.SpotterHUD.ShowNameplateTutorial then ns.SpotterHUD:ShowNameplateTutorial(true) end
    end)
    HelpBtn(rd, viewTutorialBtn, L["Help: Nameplate Tutorial"], L["Opens the quick visual guide showing how to toggle friendly (Shift+V) and enemy (V) nameplates so the Radar arrow and badges appear over targets."], L["Click anytime to review how nameplate shortcuts work alongside Target Radar."])

    local viewRadarTutorialBtn = ns.Theme:CreateButton(rd, 210, 24, L["View Radar Tutorial"], "default")
    ns.Theme:AutoFitButton(viewRadarTutorialBtn, 170, 20, 260)
    viewRadarTutorialBtn:SetPoint("LEFT", viewTutorialBtn, "RIGHT", 32, 0)
    viewRadarTutorialBtn:SetScript("OnClick", function()
        if ns.db and ns.db.settings then ns.db.settings.spotterRadarTutorialShown = false end
        if ns.SpotterHUD and ns.SpotterHUD.ShowRadarTutorial then ns.SpotterHUD:ShowRadarTutorial(true) end
    end)
    HelpBtn(rd, viewRadarTutorialBtn, L["Help: Radar Tutorial"], L["Opens the quick visual guide explaining how Target Radar proximity tracking, range display, and click-to-target work."], L["Tip: Watchlist entries are tracked automatically. Right-click any row to toggle Radar tracking on or off."])
    Search.Register({
        kind = "action",
        title = L["Open Target Radar"],
        actionLabel = L["Open Target Radar"],
        widget = openRadarBtn,
        helpTitle = L["Help: Open Target Radar"],
        description = L["Manually opens the Target Radar HUD to test target tracking and range display."],
        howText = L["Click this button or type '/sc radar' to show or hide the floating radar."],
        onTrigger = function() openRadarBtn:Click() end,
    })
    Search.Register({
        kind = "action",
        title = L["Open World Buffs Tracker"],
        actionLabel = L["Open World Buffs Tracker"],
        widget = openBuffsBtn,
        helpTitle = L["Help: Open World Buffs Tracker"],
        description = L["Opens the World Buffs tab in SocialCentral to view active buffs, drop timers, and classic buff sources."],
        howText = L["Click to review all classic world buffs and their status in WoW Forever."],
        onTrigger = function() openBuffsBtn:Click() end,
    })
    Search.Register({
        kind = "action",
        title = L["View Nameplate Tutorial"],
        actionLabel = L["View Nameplate Tutorial"],
        widget = viewTutorialBtn,
        helpTitle = L["Help: Nameplate Tutorial"],
        description = L["Opens the quick visual guide showing how to toggle friendly (Shift+V) and enemy (V) nameplates so the Radar arrow and badges appear over targets."],
        howText = L["Click anytime to review how nameplate shortcuts work alongside Target Radar."],
        onTrigger = function() viewTutorialBtn:Click() end,
    })
    Search.Register({
        kind = "action",
        title = L["View Radar Tutorial"],
        actionLabel = L["View Radar Tutorial"],
        widget = viewRadarTutorialBtn,
        helpTitle = L["Help: Radar Tutorial"],
        description = L["Opens the quick visual guide explaining how Target Radar proximity tracking, range display, and click-to-target work."],
        howText = L["Tip: Watchlist entries are tracked automatically. Right-click any row to toggle Radar tracking on or off."],
        onTrigger = function() viewRadarTutorialBtn:Click() end,
    })

    local resetRadarTabBtn = ns.Theme:CreateButton(rd, 190, 22, L["Restore Defaults (This Tab)"], "default")
    ns.Theme:AutoFitButton(resetRadarTabBtn, 160, 16, 250)
    resetRadarTabBtn:SetPoint("TOPLEFT", viewTutorialBtn, "BOTTOMLEFT", 0, -12)
    resetRadarTabBtn:SetScript("OnClick", function()
        local function DoReset()
            local s = ns.db and ns.db.settings
            if s then
                s.spotterEnabled = true
                s.spotterAutoShowHUD = true
                s.spotterNameplateArrow = true
                s.spotterNameplateBadges = true
                s.spotterNameplateTargetHighlight = true
                s.spotterNotifyEnemy = true
                s.spotterNotifyAlly = true
                s.spotterNotifyWatchlist = true
                s.spotterNotifyFriends = true
                s.spotterNotifyBlocked = true
                s.spotterNotifySameClan = false
                s.spotterIgnoreGroup = true
                s.spotterSound = true
                s.spotterLockHUD = false
                s.embedWorldMap = true
                s.worldBuffsMapPins = true
            end
            NotifySettingChanged("WORLD_BUFFS_UPDATED")
            for _, sync in ipairs(syncFns) do sync() end
        end
        if ns.UI and ns.UI.OpenConfirmModal then
            ns.UI:OpenConfirmModal({
                title = L["Restore Defaults (This Tab)"],
                message = L["Are you sure you want to restore all Target Radar & World Buff settings on this tab to defaults?"],
                confirmText = L["Reset"],
                confirmVariant = "danger",
                onConfirm = DoReset,
            })
        else
            DoReset()
        end
    end)

    AddDeps(deps.defaultBtns, openBuffsBtn, viewTutorialBtn, viewRadarTutorialBtn, resetRadarTabBtn)
    AddDeps(deps.primaryBtns, openRadarBtn)
    AddDeps(deps.wb, buffMapPinsCb, openBuffsBtn)
    AddDeps(deps.radar, spotterAutoHudCb, spotterPlateArrowCb, spotterBadgesCb, spotterTargetHighlightCb, spotterEnemyCb, spotterAllyCb, spotterWatchlistCb, spotterFriendsCb, spotterBlockedCb, spotterSameCb, spotterIgnoreGroupCb, spotterSoundCb, spotterLockCb, openRadarBtn, viewTutorialBtn, viewRadarTutorialBtn)
end

local function BuildGeneralTab(gn, deps)
    local langHeader = AddSectionHeader(
        gn, L["Language"], nil, -6,
        L["Help: Language"],
        L["Choose Auto (WoW) to follow your game client language automatically, or override SocialCentral to English, Português (BR), or Español independently."],
        L["Click a language button below and confirm Reload UI (outside combat) so all menus, tooltips, and labels re-render cleanly in your chosen language."]
    )
    local langValue = gn:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    langValue:SetPoint("TOPLEFT", langHeader, "BOTTOMLEFT", 0, -4)
    local langModeNote = ns.langOverridden and L["Manual Override"] or L["Auto (WoW)"]
    langValue:SetText(L["Active Language: %s (%s)"]:format(ns.activeLangLabel or "English", ns.activeLocale or "enUS") .. "  [" .. langModeNote .. "]")

    local langLabelByVal = { auto = L["Auto (WoW)"], enUS = "English", ptBR = "Português (BR)", esES = "Español" }
    local langRow = CreateChoiceRow(gn, langValue, -6, {
        { value = "auto", label = L["Auto (WoW)"], width = 116 },
        { value = "enUS", label = "English", width = 94 },
        { value = "ptBR", label = "Português (BR)", width = 140 },
        { value = "esES", label = "Español", width = 100 },
    }, function()
        return (ns.db and ns.db.settings and ns.db.settings.language) or "auto"
    end, function(val)
        local prev = (ns.db and ns.db.settings and ns.db.settings.language) or "auto"
        ns.db.settings.language = val
        if val ~= prev and ns.Theme and ns.Theme.ShowReloadPrompt then
            ns.Theme:ShowReloadPrompt(langLabelByVal[val] or val)
        end
    end)

    local langReloadBtn = ns.Theme:CreateButton(gn, 168, 22, L["Reload UI to Apply Language"], "default")
    ns.Theme:AutoFitButton(langReloadBtn, 160, 22)
    langReloadBtn:SetPoint("TOPLEFT", langRow, "BOTTOMLEFT", 0, -6)
    langReloadBtn:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then ns:Print(L["In Combat"]); return end
        if ReloadUI then ReloadUI() elseif C_UI and C_UI.Reload then C_UI.Reload() end
    end)

    local themeHeader = AddSectionHeader(
        gn, L["Theme"], langReloadBtn, -12,
        L["Help: Theme"],
        L["Choose between Blizzard Official (default in-game portrait window, dark marble inset, and classic red/pewter buttons), Modern Theme (optional dark minimalist UI), or Classic Gold."],
        L["Click your preferred design button (or open the visual Preview Picker below); changes apply immediately across all SocialCentral windows without /reload."]
    )
    local themeRow = CreateChoiceRow(gn, themeHeader, -6, {
        { value = "blizzard", label = L["Blizzard Official"], width = 176 },
        { value = "dark", label = L["Modern Theme"], width = 166 },
        { value = "native", label = L["Classic Gold"], width = 152 },
    }, function()
        return ns.db and ns.db.settings.theme or "blizzard"
    end, function(val)
        ns.db.settings.theme = val
        ns.db.settings.themeChosen = true
        if ns.Theme then ns.Theme:NotifyChanged() end
    end)

    local themePickerBtn = ns.Theme:CreateButton(gn, 200, 22, L["Open Theme Preview Picker"], "default")
    ns.Theme:AutoFitButton(themePickerBtn, 190, 22)
    themePickerBtn:SetPoint("TOPLEFT", themeRow, "BOTTOMLEFT", 0, -6)
    themePickerBtn:SetScript("OnClick", function()
        if ns.Theme and ns.Theme.ShowThemeWelcomePicker then ns.Theme:ShowThemeWelcomePicker() end
    end)

    local resetPosBtn = ns.Theme:CreateButton(gn, 200, 22, L["Reset All Window Positions"], "default")
    ns.Theme:AutoFitButton(resetPosBtn, 170, 18, 270)
    resetPosBtn:SetPoint("LEFT", themePickerBtn, "RIGHT", 12, 0)
    resetPosBtn:SetScript("OnClick", function()
        if ns.UI and ns.UI.OpenConfirmModal then
            ns.UI:OpenConfirmModal({
                title = L["Reset All Window Positions"],
                message = L["Are you sure you want to reset all SocialCentral window positions to defaults?"],
                confirmText = L["Reset"],
                confirmVariant = "danger",
                onConfirm = function()
                    if ns.Theme and ns.Theme.ResetAllWindowPositions then ns.Theme:ResetAllWindowPositions() end
                end,
            })
        elseif ns.Theme and ns.Theme.ResetAllWindowPositions then
            ns.Theme:ResetAllWindowPositions()
        end
    end)
    HelpBtn(gn, resetPosBtn, L["Help: Reset Window Positions"], L["Restores the default screen positions of the Main Window, Target Radar HUD, and all popup dialogs."], L["Use this if any window was moved off-screen or after changing screen resolution."])
    Search.Register({
        kind = "action",
        title = L["Open Theme Preview Picker"],
        actionLabel = L["Open Theme Preview Picker"],
        widget = themePickerBtn,
        helpTitle = L["Help: Theme"],
        description = L["Choose between Blizzard Official (default in-game portrait window, dark marble inset, and classic red/pewter buttons), Modern Theme (optional dark minimalist UI), or Classic Gold."],
        howText = L["Click your preferred design button (or open the visual Preview Picker below); changes apply immediately across all SocialCentral windows without /reload."],
        onTrigger = function() themePickerBtn:Click() end,
    })
    Search.Register({
        kind = "action",
        title = L["Reset All Window Positions"],
        actionLabel = L["Reset All Window Positions"],
        widget = resetPosBtn,
        helpTitle = L["Help: Reset Window Positions"],
        description = L["Restores the default screen positions of the Main Window, Target Radar HUD, and all popup dialogs."],
        howText = L["Use this if any window was moved off-screen or after changing screen resolution."],
        onTrigger = function() resetPosBtn:Click() end,
    })

    local mmCb = CreateCheckbox(
        gn, L["Show minimap button"], themePickerBtn, -12,
        function() return not (ns.db and ns.db.settings.minimap.hide) end,
        function(checked)
            ns.db.settings.minimap.hide = not checked
            if ns.Minimap then ns.Minimap:Update() end
        end,
        L["Help: Show Minimap Button"],
        L["Displays or hides the circular/square SocialCentral button attached around your Minimap."],
        L["Check to show the button. Left-click opens SocialCentral, Right-click opens quick actions, Drag moves it."]
    )
    local lockCb = CreateCheckbox(
        gn, L["Lock minimap button"], mmCb, -6,
        function() return ns.db and ns.db.settings.minimap.lock end,
        function(checked) ns.db.settings.minimap.lock = checked end,
        L["Help: Lock Minimap Button"],
        L["Prevents accidental dragging of the Minimap button while clicking or moving your camera."],
        L["Enable after positioning your Minimap button where you want it."]
    )

    local minimapClickHeader = AddSectionHeader(
        gn, L["Minimap Left-Click behavior"], lockCb, -10,
        L["Help: Minimap Left-Click"],
        L["Chooses what happens when you left-click the Minimap button or Addon Compartment icon."],
        L["'Smart' jumps straight to unread Conversations when whispers wait for you, otherwise opening the Main Window."]
    )
    local minimapClickRow = CreateChoiceRow(gn, minimapClickHeader, -6, {
        { value = "smart", label = L["Smart: Unread or Hub"], width = 186 },
        { value = "hub", label = L["Always Main Window"], width = 170 },
        { value = "menu", label = L["Quick Chooser Menu"], width = 170 },
    }, function()
        return ns.db and ns.db.settings.minimapLeftClickAction or "smart"
    end, function(val)
        ns.db.settings.minimapLeftClickAction = val
    end)

    local whoHeader = AddSectionHeader(
        gn, L["/who mode"], minimapClickRow, -12,
        L["Help: /who Mode"],
        L["Controls how manual /who responses are captured silently without interrupting your gameplay."],
        L["Choose 'Silent UI' (hides Blizzard Friends popup outside combat) or 'Chat Filter' (parses chat lines cleanly without touching FriendsFrame)."]
    )
    local whoRow = CreateChoiceRow(gn, whoHeader, -6, {
        { value = "silent_ui", label = L["Silent UI (no Friends popup outside combat)"], width = 272 },
        { value = "chat_filter", label = L["Chat filter (zero touch on FriendsFrame)"], width = 272 },
    }, function()
        return ns.db and ns.db.settings.whoMode or "silent_ui"
    end, function(val)
        ns.db.settings.whoMode = val
    end)

    local cdHeader = AddSectionHeader(
        gn, L["/who cooldown (seconds)"], whoRow, -10,
        L["Help: /who Cooldown"],
        L["Enforces a minimum waiting interval (5 to 30 seconds) between manual /who clicks so servers never throttle or flag requests."],
        L["Use '-' and '+' to adjust. Blizzard servers lock /who if queried too rapidly; 6s or higher is safest."]
    )
    local cdRow = CreateStepperRow(gn, cdHeader, -6, 5, 30, "s", function()
        return ns.db and ns.db.settings.whoCooldown or 6
    end, function(val)
        ns.db.settings.whoCooldown = val
    end)

    local nearbyHeader = AddSectionHeader(
        gn, L["Nearby retention (minutes)"], cdRow, -10,
        L["Help: Nearby Retention"],
        L["Defines how many minutes passive friendly Nearby sightings remain listed before expiring automatically."],
        L["Adjust from 5 to 60 minutes with '-' and '+'. Older sightings are pruned cleanly to save memory."]
    )
    local nearbyRow = CreateStepperRow(gn, nearbyHeader, -6, 5, 60, "min", function()
        return ns.db and ns.db.settings.nearbyRetentionMin or 15
    end, function(val)
        ns.db.settings.nearbyRetentionMin = val
        ns:Emit("NEARBY_UPDATED")
    end)

    local histHeader = AddSectionHeader(
        gn, L["Character Whisper history per thread (0 = off)"], nearbyRow, -10,
        L["Help: Whisper History Limit"],
        L["Saves the last N lines per Character Whisper locally (0 to 60 lines). Battle.net Real IDs and BattleTags are never persisted to disk."],
        L["Use '-' and '+' in steps of 10. Set to 0 if you want session-only whispers without SavedVariables history."]
    )
    local histRow = CreateStepperRow(gn, histHeader, -6, 0, 60, L["lines"], function()
        return ns.db and ns.db.settings.chatHistoryLimit or 30
    end, function(val)
        ns.db.settings.chatHistoryLimit = val
        ns:Emit("CHAT_UPDATED")
    end, 10)

    local tooltipsHeader = AddSectionHeader(
        gn, L["Tooltips & Item Inventory Counts"], histRow, -12,
        L["Help: Tooltips Integration"],
        L["Enhances official item and player tooltips with account-wide alt item counts and saved Social Card notes, Red Flags, and recent companions."],
        L["Toggle either tooltip helper below at any time without affecting Blizzard performance or combat safety."]
    )
    local tooltipItemAltsCb = CreateCheckbox(
        gn, L["Show Alt Item Counts in item tooltips"], tooltipsHeader, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.tooltipItemAlts ~= false end,
        function(checked) ns.db.settings.tooltipItemAlts = checked end,
        L["Help: Alt Item Tooltips"],
        L["Displays which characters on this realm pool own the hovered item across Equipped, Bags, and Bank, plus the account total."],
        L["Hover any item in bags, chat, bank, or auction house to see alt inventory counts instantly."]
    )
    local tooltipPlayerNotesCb = CreateCheckbox(
        gn, L["Show Social Notes, Red Flags & Companion history in tooltips"], tooltipItemAltsCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.tooltipPlayerNotes ~= false end,
        function(checked) ns.db.settings.tooltipPlayerNotes = checked end,
        L["Help: Player Tooltip Notes"],
        L["Displays saved Social Card notes, 'Avoid' Red Flags, Watchlist notes, and recent dungeon companions when hovering over a player."],
        L["Right-click any player frame or chat name to quickly set Social Notes, 'Good Partner (+)', or 'Flag: Avoid'."]
    )

    local guildToolsHeader = AddSectionHeader(
        gn, L["Guild Sync, LFG Tools & Updates"], tooltipPlayerNotesCb, -12,
        L["Help: Guild Sync & LFG Tools"],
        L["Opt-in guild communication, Group Finder automation-free helpers, and peer version checks."],
        L["Keep opt-in sync off for 100% local play, or turn on to share guild status/LFG/events with teammates."]
    )
    local clanSyncCb = CreateCheckbox(
        gn, L["Enable Clan guild sync (opt-in)"], guildToolsHeader, -6,
        function() return ns.db and ns.db.settings.clanSync end,
        function(checked) ns.db.settings.clanSync = checked; ns:Emit("CLAN_UPDATED") end,
        L["Help: Clan Guild Sync"],
        L["Enables encrypted-free opt-in guild addon messages (SCentral1) to share Status Tags, Event Calls, and Dungeon/Raid Signups with guildmates."],
        L["Leave unchecked for 100% local Clan tracking, or enable to sync tags and event calls safely with guildmates who also use SocialCentral."]
    )
    local guildFinderCb = CreateCheckbox(
        gn, L["Detect LFM calls in Guild chat (opt-in, read-only)"], clanSyncCb, -6,
        function() return ns.db and ns.db.settings.guildChatFinder end,
        function(checked) ns.db.settings.guildChatFinder = checked; ns:Emit("CLAN_UPDATED") end,
        L["Help: Guild LFM Detector"],
        L["Passively reads Guild chat lines looking for LFG/LFM keywords so guild calls show inside the Clan tab without running any scan or sending messages."],
        L["Enable to capture guild group requests automatically; click a sighting in the Clan tab to whisper or request invite."]
    )
    local autoStatusCb = CreateCheckbox(
        gn, L["Auto-tag Busy inside dungeons/raids (opt-in)"], guildFinderCb, -6,
        function() return ns.db and ns.db.settings.autoStatusInstance end,
        function(checked)
            ns.db.settings.autoStatusInstance = checked
            if ns.Clan and ns.Clan.ApplyAutoInstanceStatus then ns.Clan:ApplyAutoInstanceStatus() end
        end,
        L["Help: Auto Instance Status"],
        L["Automatically sets your Clan Status Tag to 'Busy' while inside a Dungeon or Raid instance and restores 'None' outside."],
        L["Respects combat lockdown and only broadcasts when Clan Guild Sync is also enabled."]
    )
    local clanAutoCloseLfgCb = CreateCheckbox(
        gn, L["Auto-close my Dungeon LFM listing when party reaches 5 players"], autoStatusCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.clanAutoCloseFullLfg ~= false end,
        function(checked) ns.db.settings.clanAutoCloseFullLfg = checked end,
        L["Help: Auto-Close Full Dungeon LFM"],
        L["Automatically clears your own active Guild/Allied Dungeon LFM post once your party reaches 5 members or enters a 5-player dungeon instance."],
        L["Runs safely out of combat so guildmates stop whispering for already full groups."]
    )
    local globalChatLfgCb = CreateCheckbox(
        gn, L["Scan public chat channels for LFG Bulletin"], clanAutoCloseLfgCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.globalChatLfgScan ~= false end,
        function(checked) ns.db.settings.globalChatLfgScan = checked; ns:Emit("CLAN_UPDATED") end,
        L["Help: Global Chat LFG"],
        L["Passively captures LFG/LFM dungeon and raid messages from public chat channels into the 'Global Chat LFG' filter inside Group Finder (I)."],
        L["Select 'Global Chat LFG' in Group Finder to browse clean server chat requests separated from your Guild and Allies."]
    )
    local lfgDraftCb = CreateCheckbox(
        gn, L["Pre-fill Level, Class & Role when applying in Group Finder (I)"], globalChatLfgCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.lfgAutoApplyDraft ~= false end,
        function(checked) ns.db.settings.lfgAutoApplyDraft = checked end,
        L["Help: LFG Quick Apply Draft"],
        L["Automatically builds a ready-to-send whisper draft containing your Level, Class, and currently selected Group Finder Role when contacting a leader."],
        L["Click Send Message or Quick Apply on any group listing to open your message ready to confirm or send in 1 click."]
    )
    local lfgAntiSpamCb = CreateCheckbox(
        gn, L["Filter WTS and boost spam from public LFG channels"], lfgDraftCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.lfgAntiSpam ~= false end,
        function(checked) ns.db.settings.lfgAntiSpam = checked; ns:Emit("CLAN_UPDATED") end,
        L["Help: LFG Anti-Spam Filter"],
        L["Hides booster advertisements, real-money sales (WTS/GDKP/carry services), and repetitive commercial spam from Group Finder and chat scans."],
        L["Keep checked for a clean, legitimate dungeon and raid group recruitment feed."]
    )
    local verCb = CreateCheckbox(
        gn, L["Check for addon updates (DBM-style peer alerts)"], lfgAntiSpamCb, -6,
        function() return ns.db and ns.db.settings.versionCheck ~= false end,
        function(checked) if ns.db and ns.db.settings then ns.db.settings.versionCheck = checked end end,
        L["Help: Update Check & GitHub"],
        L["Silently compares versions with other SocialCentral users in your guild or group (just like DBM) and warns you if a newer version is out."],
        L["Keep enabled for in-game update chat links. Click 'GitHub Releases / Updater' to copy the public GitHub download link or Windows updater command."]
    )
    local updateLinkBtn = ns.Theme:CreateButton(gn, 210, 24, L["GitHub Releases / Updater"], "default")
    ns.Theme:AutoFitButton(updateLinkBtn, 210, 22, 490)
    updateLinkBtn:SetPoint("TOPLEFT", verCb, "BOTTOMLEFT", 4, -8)
    updateLinkBtn:SetScript("OnClick", function()
        if ns.Theme and ns.Theme.ShowUpdatePopup then
            ns.Theme:ShowUpdatePopup(ns.version, ns.Clan and ns.Clan.latestRemoteVersion, ns.RELEASE_URL)
        end
    end)
    HelpBtn(gn, updateLinkBtn, L["Help: Update Check & GitHub"], L["Silently compares versions with other SocialCentral users in your guild or group (just like DBM) and warns you if a newer version is out."], L["Keep enabled for in-game update chat links. Click 'GitHub Releases / Updater' to copy the public GitHub download link or Windows updater command."])
    Search.Register({
        kind = "action",
        title = L["GitHub Releases / Updater"],
        actionLabel = L["GitHub Releases / Updater"],
        widget = updateLinkBtn,
        helpTitle = L["Help: Update Check & GitHub"],
        description = L["Silently compares versions with other SocialCentral users in your guild or group (just like DBM) and warns you if a newer version is out."],
        howText = L["Keep enabled for in-game update chat links. Click 'GitHub Releases / Updater' to copy the public GitHub download link or Windows updater command."],
        onTrigger = function() updateLinkBtn:Click() end,
    })

    AddDeps(deps.defaultBtns, langReloadBtn, themePickerBtn, resetPosBtn, updateLinkBtn)
    AddDeps(deps.guild, clanSyncCb, guildFinderCb, autoStatusCb, clanAutoCloseLfgCb)
    AddDeps(deps.lfg, globalChatLfgCb, lfgDraftCb, lfgAntiSpamCb)
    AddDeps(deps.alts, tooltipItemAltsCb)
    AddDeps(deps.nearby, nearbyRow)
end

function Search.BuildUI(headerArea, tabBar, content, scrollFrame, pages, pageHeights, catTabs, catButtons)
    Search.scrollFrame = scrollFrame
    Search.pages = pages
    Search.content = content
    Search.pageHeights = pageHeights
    Search.catButtons = catButtons
    wipe(Search.entries)
    wipe(Search.filterBtns)
    wipe(Search.emptyChips)

    local searchRow = CreateFrame("Frame", nil, headerArea)
    searchRow:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -6)
    searchRow:SetPoint("TOPRIGHT", headerArea, "TOPRIGHT", 0, -72)
    searchRow:SetHeight(26)

    local searchBox = CreateFrame("EditBox", "SocialCentralSettingsSearchBox", searchRow, "SearchBoxTemplate")
    searchBox:SetHeight(24)
    searchBox:SetPoint("LEFT", searchRow, "LEFT", 0, 0)
    searchBox:SetPoint("RIGHT", searchRow, "RIGHT", -132, 0)
    searchBox:SetAutoFocus(false)
    if searchBox.Instructions then
        searchBox.Instructions:SetText(L["Search settings (e.g. minimap, sound, raid, radar, theme)..."])
    end
    if ns.Theme and ns.Theme.StyleSearchBox then
        ns.Theme:StyleSearchBox(searchBox)
    end
    Search.searchBox = searchBox

    local countLbl = searchRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    countLbl:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    countLbl:SetWidth(90)
    countLbl:SetJustifyH("LEFT")
    countLbl:SetWordWrap(false)
    Search.countLbl = countLbl

    local searchHelp = HelpBtn(
        searchRow,
        countLbl,
        L["Help: Settings Search"],
        L["Instantly searches every SocialCentral option across all four tabs by title, description, channel, or common keywords in English, Portuguese, and Spanish (no accents required)."],
        L["Toggle checkboxes, adjust counters, switch options, or run actions right inside the search results — or click 'Go to' on any card to jump directly to its tab and highlight it."]
    )
    if searchHelp then
        searchHelp:ClearAllPoints()
        searchHelp:SetPoint("RIGHT", searchRow, "RIGHT", -2, 0)
    end

    local sp = CreateFrame("Frame", nil, content)
    sp:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    sp:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    sp:SetHeight(420)
    sp:Hide()
    Search.searchPage = sp

    local filterSpecs = { { id = "all", label = L["All"] } }
    for _, spec in ipairs(catTabs) do
        filterSpecs[#filterSpecs + 1] = { id = spec.id, label = spec.label }
    end
    for _, fSpec in ipairs(filterSpecs) do
        local fBtn = ns.Theme:CreateButton(sp, 92, 22, fSpec.label, "default")
        fBtn:SetScript("OnClick", function()
            Search.tabFilter = fSpec.id
            if scrollFrame.SetVerticalScroll then scrollFrame:SetVerticalScroll(0) end
            Search.RenderResults()
        end)
        fBtn:Hide()
        Search.filterBtns[#Search.filterBtns + 1] = { id = fSpec.id, label = fSpec.label, btn = fBtn }
    end

    local emptyBox = CreateFrame("Frame", nil, sp, "BackdropTemplate")
    emptyBox:SetSize(560, 118)
    emptyBox:Hide()
    local emptyTitle = emptyBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyTitle:SetPoint("TOPLEFT", 12, -12)
    emptyTitle:SetPoint("TOPRIGHT", -12, -12)
    emptyTitle:SetJustifyH("LEFT")
    emptyTitle:SetWordWrap(false)
    local emptyHint = emptyBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyHint:SetPoint("TOPLEFT", emptyTitle, "BOTTOMLEFT", 0, -6)
    emptyHint:SetPoint("TOPRIGHT", -12, -32)
    emptyHint:SetJustifyH("LEFT")
    emptyHint:SetText(L["Try a quick topic below or search by tab, feature, or shortcut key:"])
    sp.emptyBox = emptyBox
    sp.emptyTitle = emptyTitle

    local quickTopics = {
        L["Minimap"],
        L["Whisper"],
        L["Sound"],
        L["Dungeons"],
        L["Radar"],
        L["Theme"],
        L["Language"],
        L["Shortcuts"],
    }
    for _, topic in ipairs(quickTopics) do
        local qBtn = ns.Theme:CreateButton(emptyBox, 84, 20, topic, "default")
        qBtn:SetScript("OnClick", function()
            searchBox:SetText(topic)
            searchBox:ClearFocus()
        end)
        Search.emptyChips[#Search.emptyChips + 1] = { term = topic, btn = qBtn }
    end

    searchBox:HookScript("OnTextChanged", function(self)
        local raw = self:GetText() or ""
        local trimmed = raw:match("^%s*(.-)%s*$") or ""
        if trimmed ~= Search.query then
            Search.query = trimmed
            Search.tabFilter = "all"
            Search.StopBeacon()
            if scrollFrame.SetVerticalScroll then
                scrollFrame:SetVerticalScroll(0)
            end
            Search.RenderResults()
        end
    end)

    searchBox:SetScript("OnEscapePressed", function(self)
        local txt = self:GetText() or ""
        if txt ~= "" then
            self:SetText("")
        else
            self:ClearFocus()
        end
    end)

    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
end

local function BuildPanel()
    if panelBuilt then
        return
    end
    panelBuilt = true
    EnsurePanelFrame()
    wipe(syncFns)

    -- Top Fixed Header, Category Navigation Tabs & Pinned Search Bar
    local headerArea = CreateFrame("Frame", nil, panel)
    headerArea:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    headerArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -10)
    headerArea:SetHeight(110)

    local title = headerArea:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 2, -2)
    title:SetText("SocialCentral  v" .. (ns.version or "0.0.0"))

    local subtitle = headerArea:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetText(L["Unified social hub for WoW: Forever."])

    local guildBadgeLbl = headerArea:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    guildBadgeLbl:SetPoint("TOPRIGHT", headerArea, "TOPRIGHT", -4, -4)
    guildBadgeLbl:SetJustifyH("RIGHT")

    local tabBar = CreateFrame("Frame", nil, headerArea)
    tabBar:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)
    tabBar:SetPoint("TOPRIGHT", headerArea, "TOPRIGHT", 0, -40)
    tabBar:SetHeight(26)

    local scrollFrame = CreateFrame("ScrollFrame", "SocialCentralSettingsScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", headerArea, "BOTTOMLEFT", -6, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 6)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(610, 1120)
    scrollFrame:SetScrollChild(content)

    local pages = {}
    local pageHeights = {
        overview = 1120,
        notifications = 2360,
        radar = 800,
        general = 1320,
    }
    local catTabs = {
        { id = "overview", label = L["Summary & Windows"] },
        { id = "notifications", label = L["Notifications"] },
        { id = "radar", label = L["Radar & Map"] },
        { id = "general", label = L["General & Tools"] },
    }
    local catButtons = {}

    for _, spec in ipairs(catTabs) do
        local pFrame = CreateFrame("Frame", nil, content)
        pFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        pFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
        pFrame:SetHeight(pageHeights[spec.id] or 900)
        pFrame:Hide()
        pages[spec.id] = pFrame
    end

    Search.BuildUI(headerArea, tabBar, content, scrollFrame, pages, pageHeights, catTabs, catButtons)

    local function SelectCategoryTab(tabId)
        if not pages[tabId] then tabId = "overview" end
        activeCategoryTab = tabId
        Search.StopBeacon()
        if Search.query ~= "" then
            Search.query = ""
            Search.tabFilter = "all"
            if Search.searchBox then
                Search.searchBox:SetText("")
                Search.searchBox:ClearFocus()
            end
            if Search.countLbl then Search.countLbl:SetText("") end
        end
        if Search.searchPage then
            Search.searchPage:Hide()
        end
        for id, pFrame in pairs(pages) do
            pFrame:SetShown(id == tabId)
        end
        content:SetHeight(pageHeights[tabId] or 800)
        if scrollFrame.SetVerticalScroll then
            scrollFrame:SetVerticalScroll(0)
        end
        for _, item in ipairs(catButtons) do
            ns.Theme:StyleButton(item.btn, "tab")
            ns.Theme:SetButtonActive(item.btn, item.id == tabId, "tab")
        end
        for _, sync in ipairs(syncFns) do
            sync()
        end
    end

    local prevTabBtn
    for _, spec in ipairs(catTabs) do
        local btn = ns.Theme:CreateButton(tabBar, 134, 24, spec.label, "tab")
        ns.Theme:AutoFitButton(btn, 98, 22, 210)
        if not prevTabBtn then
            btn:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 0, 0)
        else
            btn:SetPoint("LEFT", prevTabBtn, "RIGHT", 6, 0)
        end
        btn:SetScript("OnClick", function()
            SelectCategoryTab(spec.id)
        end)
        catButtons[#catButtons + 1] = { id = spec.id, baseLabel = spec.label, btn = btn }
        prevTabBtn = btn
    end

    local function SafeHideSettingsFrame(sp)
        if not sp then return end
        if sp.IsForbidden then
            local okF, forb = pcall(sp.IsForbidden, sp)
            if not okF or forb then return end
        end
        if sp.IsProtected then
            local okP, prot = pcall(sp.IsProtected, sp)
            if not okP or prot then return end
        end
        if sp.IsShown and sp:IsShown() and sp.Hide then
            pcall(sp.Hide, sp)
        end
    end

    local function CloseSettingsBeforeJump()
        if not ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) then
            SafeHideSettingsFrame(_G.SettingsPanel)
            SafeHideSettingsFrame(_G.InterfaceOptionsFrame)
        end
    end

    local function NotifySettingChanged(extraEmit)
        ns:Emit("SETTINGS_UPDATED")
        if extraEmit then
            ns:Emit(extraEmit)
        end
        if ns.UI and ns.UI.QueueRefresh then
            ns.UI:QueueRefresh(false)
        end
    end

    local deps = {
        wb = { _scModKey = "wb" },
        radar = { _scModKey = "radar" },
        guild = { _scModKey = "guild" },
        lfg = { _scModKey = "lfg" },
        social = { _scModKey = "social" },
        watch = { _scModKey = "watch" },
        chat = { _scModKey = "chat" },
        alts = { _scModKey = "alts" },
        nearby = { _scModKey = "nearby" },
        defaultBtns = {},
        primaryBtns = {},
    }
    local refs = {}

    Search.SetBuildContext("overview", L["Summary & Windows"], 1)
    BuildOverviewTab(pages.overview, deps, refs, NotifySettingChanged, CloseSettingsBeforeJump)
    Search.SetBuildContext("notifications", L["Notifications"], 2)
    BuildNotificationsTab(pages.notifications, deps, refs, NotifySettingChanged)
    Search.SetBuildContext("radar", L["Radar & Map"], 3)
    BuildRadarTab(pages.radar, deps, NotifySettingChanged, CloseSettingsBeforeJump)
    Search.SetBuildContext("general", L["General & Tools"], 4)
    BuildGeneralTab(pages.general, deps)

    syncFns[#syncFns + 1] = function()
        local badgeParts = {}
        local inGuild = Compat and Compat.IsInGuild and Compat.IsInGuild()
        if inGuild then
            local gName = GetGuildInfo and ns.Safe and ns.Safe.String(ns.Safe.Call(GetGuildInfo, "player"))
            badgeParts[#badgeParts + 1] = "|cff3fb950" .. ((gName and gName ~= "") and ("<" .. gName .. ">") or L["Guild"]) .. "|r"
        else
            badgeParts[#badgeParts + 1] = "|cff9da7b5" .. L["No guild"] .. "|r"
        end
        local isCharProf = ns.IsCharProfileEnabled and ns:IsCharProfileEnabled()
        badgeParts[#badgeParts + 1] = isCharProf and ("|cff58a6ff" .. L["Profile: Character"] .. "|r") or ("|cff9da7b5" .. L["Profile: Account"] .. "|r")
        local focusReason = Compat and Compat.GetFocusSilenceReason and Compat.GetFocusSilenceReason()
        if focusReason == "dnd" then
            badgeParts[#badgeParts + 1] = "|cffff9b3d[" .. L["Do Not Disturb"] .. "]|r"
        elseif focusReason == "instance" then
            badgeParts[#badgeParts + 1] = "|cffffd24d[" .. L["Silenced in Instance"] .. "]|r"
        end
        guildBadgeLbl:SetText(table.concat(badgeParts, "  ·  "))

        for _, item in ipairs(refs.jumpButtons) do
            ns.Theme:StyleButton(item.btn, item.variant)
            ns.Theme:SetButtonActive(item.btn, false, item.variant)
        end
        refs.ReflowJumpGrid()

        local disabledCats = CollectDisabledNotificationNames()
        local mutedPlayers, mutedThreads = CountMutedPlayersAndThreads()
        local offTotal = #disabledCats + (mutedPlayers > 0 and 1 or 0) + (mutedThreads > 0 and 1 or 0)

        if #disabledCats == 0 and mutedPlayers == 0 and mutedThreads == 0 then
            refs.mutedStatusLbl:SetText("|cff3fb950" .. L["All notification categories are active and no individual players are muted."] .. "|r")
        else
            local parts = {}
            if #disabledCats > 0 then
                parts[#parts + 1] = "|cffff9b3d" .. L["Disabled:"] .. "|r " .. table.concat(disabledCats, ", ")
            end
            if mutedPlayers > 0 or mutedThreads > 0 then
                parts[#parts + 1] = "|cff8ab4f8" .. string.format(L["Muted players/chats: %d"], mutedPlayers + mutedThreads) .. "|r"
            end
            refs.mutedStatusLbl:SetText(table.concat(parts, "\n"))
        end
        SetWidgetEnabled(refs.unmuteAlertsBtn, #disabledCats > 0 or (ns.db and ns.db.settings and ns.db.settings.doNotDisturb == true))
        SetWidgetEnabled(refs.unmutePlayersBtn, (mutedPlayers + mutedThreads) > 0)

        for _, item in ipairs(catButtons) do
            local lbl = item.baseLabel
            if item.id == "notifications" and offTotal > 0 then
                lbl = string.format("%s (%d)", item.baseLabel, offTotal)
            end
            ns.Theme:SetButtonText(item.btn, lbl)
            ns.Theme:AutoFitButton(item.btn, 98, 22, 220)
            ns.Theme:StyleButton(item.btn, "tab")
            ns.Theme:SetButtonActive(item.btn, item.id == activeCategoryTab, "tab")
        end

        for _, b in ipairs(deps.defaultBtns) do
            ns.Theme:StyleButton(b, "default")
            ns.Theme:SetButtonActive(b, false, "default")
        end
        for _, pb in ipairs(deps.primaryBtns) do
            ns.Theme:StyleButton(pb, "primary")
            ns.Theme:SetButtonActive(pb, false, "primary")
        end
        local activePreset = GetActivePresetMode()
        if refs.presetBtns then
            for _, pItem in ipairs(refs.presetBtns) do
                local isAct = (activePreset == pItem.mode)
                local var = isAct and "primary" or "default"
                ns.Theme:StyleButton(pItem.btn, var)
                ns.Theme:SetButtonActive(pItem.btn, isAct, var)
            end
        end
        if refs.copyAccBtn then
            SetWidgetEnabled(refs.copyAccBtn, isCharProf == true)
        end

        local s = ns.db and ns.db.settings
        local modStates = {
            wb = not s or s.embedWorldMap ~= false,
            radar = not s or s.spotterEnabled ~= false,
            guild = (not Compat or not Compat.IsWindowIntegrationEnabled) or Compat.IsWindowIntegrationEnabled("J"),
            lfg = not s or s.embedLfgWindow ~= false,
            social = not s or s.embedSocialWindow ~= false,
            alts = not s or s.embedCharacterWindow ~= false,
            watch = not s or s.moduleWatchlistEnabled ~= false,
            nearby = not s or s.moduleNearbyEnabled ~= false,
            chat = not s or s.moduleChatEnabled ~= false,
        }
        for bucket, enabled in pairs(modStates) do
            for _, w in ipairs(deps[bucket]) do
                SetWidgetEnabled(w, enabled)
            end
        end
    end

    scrollFrame:SetScript("OnSizeChanged", function(self)
        local w = math.max(500, (self:GetWidth() or 600) - 10)
        content:SetWidth(w)
        local colW = math.floor((w - 22) * 0.5)
        refs.winGrid:SetWidth(w - 8)
        refs.winLeft:SetWidth(colW)
        refs.winRight:SetWidth(colW)
        if refs.scAutoGrid then
            refs.scAutoGrid:SetWidth(w - 8)
            refs.scAutoLeft:SetWidth(colW)
            refs.scAutoRight:SetWidth(colW)
        end
        refs.qGrid:SetWidth(w - 8)
        refs.qLeft:SetWidth(colW)
        refs.qRight:SetWidth(colW)
        for _, sync in ipairs(syncFns) do
            sync()
        end
        if Search.query ~= "" then
            Search.RenderResults()
        end
    end)

    SelectCategoryTab(activeCategoryTab)
    selectCategoryTabFn = SelectCategoryTab

    if ns.Theme and ns.Theme.RegisterListener then
        ns.Theme:RegisterListener(function()
            if panel and panel:IsShown() then
                for _, sync in ipairs(syncFns) do sync() end
                if Search.query ~= "" then
                    Search.RenderResults()
                end
            end
        end)
    end
end

--- Refresh all Settings panel widgets from saved preferences.
function SettingsMod:Refresh()
    if not (panel and panelBuilt) then
        return
    end
    for _, sync in ipairs(syncFns) do
        sync()
    end
    if Search.query ~= "" then
        Search.RefreshCardStates()
    end
end

--- Register SocialCentral inside Blizzard Settings.
function SettingsMod:Register()
    if panel then
        return
    end
    EnsurePanelFrame()
    panel:HookScript("OnShow", function()
        BuildPanel()
        for _, sync in ipairs(syncFns) do
            sync()
        end
        if Search.query ~= "" then
            Search.RenderResults()
        end
    end)

    ns:On("SETTINGS_UPDATED", function()
        if panel and panel:IsShown() then
            SettingsMod:Refresh()
        end
    end)
    ns.RegisterEvent(panel, "PLAYER_GUILD_UPDATE", function(_, _, unit)
        if (not unit or unit == "player") and panel and panel:IsShown() then
            SettingsMod:Refresh()
        end
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, "SocialCentral")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

--- Open the Blizzard Settings window at the SocialCentral category.
function SettingsMod:Open(tabId)
    if not panel then
        self:Register()
    end
    BuildPanel()
    if tabId and selectCategoryTabFn then
        selectCategoryTabFn(tabId)
    elseif tabId then
        activeCategoryTab = tabId
    end
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print("%s", L["In Combat"])
        return
    end
    if Settings and Settings.OpenToCategory and category then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

--- Toggle Blizzard Settings directly at the SocialCentral category.
function SettingsMod:Toggle()
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print("%s", L["In Combat"])
        return
    end
    local isShown = (_G.SettingsPanel and _G.SettingsPanel.IsShown and _G.SettingsPanel:IsShown())
        or (_G.InterfaceOptionsFrame and _G.InterfaceOptionsFrame.IsShown and _G.InterfaceOptionsFrame:IsShown())
    local panelVisible = panel and panel.IsVisible and panel:IsVisible()
    if isShown and panelVisible then
        for _, sp in ipairs({ _G.SettingsPanel, _G.InterfaceOptionsFrame }) do
            if sp and sp.IsShown and sp:IsShown() then
                local forb = sp.IsForbidden and select(2, pcall(sp.IsForbidden, sp))
                local prot = sp.IsProtected and select(2, pcall(sp.IsProtected, sp))
                if not forb and not prot and sp.Hide then
                    pcall(sp.Hide, sp)
                end
            end
        end
        return
    end
    self:Open()
end
