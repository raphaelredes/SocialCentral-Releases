local ADDON_NAME, ns = ...
local L = ns.L
local Safe = ns.Safe
local Compat = ns.Compat

local LootRollUI = {
    selectedRollID = nil,
    tabPageOffset = 0,
    votesCollapsed = false,
    epicWinQueue = {},
    epicWinElapsed = 0,
    epicWinDur = 3.85,
    resultsSubTab = "drops",
    resultsScope = "latest_run",
    resultsFilter = "ALL",
    resultsQualityMin = 0,
    resultsSortBy = "newest",
    resultsSearch = "",
    selectedResultId = nil,
    selectedChatRollId = nil,
    chatRollSearch = "",
}
ns.LootRollUI = LootRollUI
table.insert(ns.modules, LootRollUI)

-- Weak-key registries so we NEVER mutate Blizzard's official GroupLootFrame1..8 or GroupLootContainer tables (Rule #3).
local hookedOfficialFrames = setmetatable({}, { __mode = "k" })
local suppressedOfficialFrames = setmetatable({}, { __mode = "k" })

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local ICON_TEX = "Interface\\AddOns\\SocialCentral\\Media\\icon.tga"
local ICON_DICE = "Interface\\Buttons\\UI-GroupLoot-Dice-Up"
local ICON_TROPHY = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local ICON_COPY = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up"
local ICON_GLOW = "Interface\\AddOns\\SocialCentral\\Media\\toast-glow"
local ICON_DOT = "Interface\\AddOns\\SocialCentral\\Media\\dot"
local ICON_LOCK_CLOSED = "Interface\\AddOns\\SocialCentral\\Media\\lock-closed"
local ICON_LOCK_OPEN = "Interface\\AddOns\\SocialCentral\\Media\\lock-open"
local ICON_PASS = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local ICON_ARROW_UP = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up"
local ICON_ARROW_DOWN = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"
local ICON_LEAD_STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local LEAD_STAR_TAG = "|T" .. ICON_LEAD_STAR .. ":12:12:0:0|t"

local CHOICE_ICONS = {
    NEED = ICON_DICE,
    GREED = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    DE = "Interface\\Buttons\\UI-GroupLoot-DE-Up",
    PASS = ICON_PASS,
    WON = ICON_TROPHY,
    MASTER = ICON_TROPHY,
}

local ROLL_SEMANTIC_ACCENTS = {
    NEED = { 0.22, 0.86, 0.44 },
    GREED = { 0.96, 0.78, 0.24 },
    DE = { 0.72, 0.46, 1.00 },
    PASS = { 0.76, 0.34, 0.36 },
}

local CARD_WIDTH = 380
local CARD_INNER_W = 360
local MAX_DRAWER_ROWS = 8
local MAX_TAB_SLOTS = 5
local MAX_STACKED_CARDS = 4

local function GetChoiceIconTexture(choiceKey)
    return CHOICE_ICONS[choiceKey]
end

local function FormatChoiceIconTag(choiceKey, size)
    local tex = CHOICE_ICONS[choiceKey]
    if not tex then return "" end
    local sz = size or 14
    return "|T" .. tex .. ":" .. tostring(sz) .. ":" .. tostring(sz) .. ":0:0|t"
end

local function QualityHex(quality)
    if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex then
        return ITEM_QUALITY_COLORS[quality].hex
    end
    return "|cffffffff"
end

local function QualityRGB(quality)
    if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local q = ITEM_QUALITY_COLORS[quality]
        return q.r or 1, q.g or 1, q.b or 1
    end
    return 1, 1, 1
end

local function ApplySolidOpaqueBg(frame, palette)
    if not (frame and frame._solidOpaqueBg) then return end
    local p = palette or (ns.Theme and ns.Theme.GetPalette and ns.Theme:GetPalette())
    local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
    frame._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
end

local function ShowItemHoverTooltip(owner, itemLink, allowCompare)
    if not (owner and GameTooltip and itemLink and itemLink ~= "") then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, itemLink)
    if ok then
        local autoCmp = (not ns.db or not ns.db.settings or ns.db.settings.lootRollShowTooltipsCompare ~= false)
        local modCmp = (IsShiftKeyDown and IsShiftKeyDown()) or (IsModifiedClick and IsModifiedClick("COMPAREITEMS"))
        if (allowCompare ~= false) and (autoCmp or modCmp) and _G.GameTooltip_ShowCompareItem then
            pcall(_G.GameTooltip_ShowCompareItem, GameTooltip)
        end
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end

local function HideItemHoverTooltip()
    if GameTooltip then GameTooltip:Hide() end
    if _G.ShoppingTooltip1 and _G.ShoppingTooltip1.Hide then _G.ShoppingTooltip1:Hide() end
    if _G.ShoppingTooltip2 and _G.ShoppingTooltip2.Hide then _G.ShoppingTooltip2:Hide() end
end

--- Anchors roll card tooltips outside the active window bounds so hovered choice tooltips
--- never cover the item details, stat comparison, or party votes inside the card.
local function SetLootRollButtonTooltipOwner(btn, cardFrame, preferBottom)
    if not GameTooltip then return end
    local anchor = cardFrame or btn
    if not (anchor and anchor.GetTop and UIParent and UIParent.GetTop) then
        GameTooltip:SetOwner(anchor or btn, preferBottom and "ANCHOR_BOTTOM" or "ANCHOR_TOP")
        return
    end
    local uTop = UIParent:GetTop() or 900
    local uBot = UIParent:GetBottom() or 0
    local uWidth = UIParent:GetWidth() or 1280
    local cTop = anchor:GetTop() or 0
    local cBot = anchor:GetBottom() or 0
    local cCx = anchor:GetCenter() or (uWidth * 0.5)
    if preferBottom then
        if (cBot - uBot) >= 85 then
            GameTooltip:SetOwner(anchor, "ANCHOR_BOTTOM", 0, -4)
        elseif cCx > (uWidth * 0.5) then
            GameTooltip:SetOwner(anchor, "ANCHOR_LEFT", -4, 0)
        else
            GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT", 4, 0)
        end
    else
        if (uTop - cTop) >= 92 then
            GameTooltip:SetOwner(anchor, "ANCHOR_TOP", 0, 4)
        elseif cCx > (uWidth * 0.5) then
            GameTooltip:SetOwner(anchor, "ANCHOR_LEFT", -4, 0)
        else
            GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT", 4, 0)
        end
    end
end

local function HandleItemIconClick(owner, itemLink, button)
    if not (itemLink and itemLink ~= "") then return false end
    local linkTxt = itemLink
    if not linkTxt:find("|H", 1, true) and linkTxt:find("^item:%d+") then
        local iName = owner and owner._itemName or ""
        linkTxt = "|H" .. linkTxt .. "|h[" .. iName .. "]|h"
    end
    if ns.Theme and ns.Theme.HandleGameHyperlinkClick then
        local cleanLink = linkTxt:match("|H([^|]+)|h") or itemLink
        return ns.Theme:HandleGameHyperlinkClick(cleanLink, linkTxt, button or "LeftButton", owner, nil)
    end
    if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
        pcall(ChatEdit_InsertLink, linkTxt)
        return true
    end
    return false
end

local function InsertSummaryIntoChat(summaryText)
    if type(summaryText) ~= "string" or summaryText == "" then return false end
    local activeEb = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
        or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
        or nil
    if activeEb and activeEb.IsVisible and activeEb:IsVisible() and activeEb.Insert then
        pcall(activeEb.Insert, activeEb, summaryText)
        return true
    end
    if ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown() and ns.QuickReply.frame.inputBox then
        local qBox = ns.QuickReply.frame.inputBox
        if qBox.IsVisible and qBox:IsVisible() and qBox.Insert then
            qBox:Insert(summaryText)
            if ns.QuickReply.FocusInputBox then
                ns.QuickReply:FocusInputBox()
            end
            return true
        end
    end
    if _G.ChatFrameUtil and _G.ChatFrameUtil.OpenChat then
        pcall(_G.ChatFrameUtil.OpenChat, summaryText)
        return true
    elseif _G.ChatEdit_OpenChat then
        pcall(_G.ChatEdit_OpenChat, summaryText)
        return true
    elseif _G.ChatFrame1EditBox and _G.ChatEdit_ActivateChat then
        pcall(_G.ChatEdit_ActivateChat, _G.ChatFrame1EditBox)
        if _G.ChatFrame1EditBox.Insert then
            pcall(_G.ChatFrame1EditBox.Insert, _G.ChatFrame1EditBox, summaryText)
        end
        return true
    end
    if ns.UI and ns.UI.OpenCopyModal then
        ns.UI:OpenCopyModal(summaryText, L["Loot Roll Summary"], L["Press Ctrl+C to copy this summary to your clipboard."])
        return true
    end
    return false
end

local function OpenPlayerQuickRollMenu(anchor, playerName, itemLink, isMe)
    if not (anchor and playerName and playerName ~= "" and MenuUtil and MenuUtil.CreateContextMenu) then
        return
    end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle(playerName)
        if not isMe then
            root:CreateButton(L["Whisper"], function()
                if ns.Chat and ns.Chat.OpenPreferredConversation then
                    ns.Chat:OpenPreferredConversation({ targetName = playerName })
                elseif Compat and Compat.Whisper then
                    Compat.Whisper(playerName)
                end
            end)
            if itemLink and itemLink ~= "" then
                root:CreateButton(L["Ask about item (/w)"], function()
                    local draft = string.format(L["Hey %s, do you need %s?"], playerName, itemLink)
                    if ns.Chat and ns.Chat.OpenPreferredConversation then
                        ns.Chat:OpenPreferredConversation({ targetName = playerName, draftText = draft })
                    elseif Compat and Compat.Whisper then
                        Compat.Whisper(playerName, draft)
                    end
                end)
            end
        end
        root:CreateButton(L["Copy Name"], function()
            if ns.UI and ns.UI.OpenCopyModal then
                ns.UI:OpenCopyModal(playerName, L["Copy Name"])
            end
        end)
    end)
end

local function ApplyIconOnlyLootButton(btn, texPath, iconSize, labelText, semanticKey)
    if not btn then return end
    local sz = iconSize or 17
    local layer = btn._textLayer or btn
    local accent = semanticKey and ROLL_SEMANTIC_ACCENTS[semanticKey] or nil
    btn._semanticAccent = accent

    if accent then
        local wash = btn:CreateTexture(nil, "ARTWORK", nil, -1)
        wash:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        wash:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        wash:SetTexture(WHITE8X8)
        wash:SetVertexColor(accent[1], accent[2], accent[3], 0.10)
        btn._tintWash = wash

        local bar = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        bar:SetHeight(2)
        bar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
        bar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        bar:SetTexture(WHITE8X8)
        bar:SetVertexColor(accent[1], accent[2], accent[3], 0.90)
        btn._accentBar = bar

        btn:HookScript("OnEnter", function(selfBtn)
            if selfBtn:IsEnabled() and selfBtn._tintWash and selfBtn._semanticAccent then
                local a = selfBtn._semanticAccent
                selfBtn._tintWash:SetVertexColor(a[1], a[2], a[3], 0.22)
            end
        end)
        btn:HookScript("OnLeave", function(selfBtn)
            if selfBtn._tintWash and selfBtn._semanticAccent then
                local a = selfBtn._semanticAccent
                selfBtn._tintWash:SetVertexColor(a[1], a[2], a[3], selfBtn:IsEnabled() and 0.10 or 0.0)
            end
        end)
    end

    local ico = layer:CreateTexture(nil, "OVERLAY", nil, 2)
    ico:SetSize(sz, sz)
    if labelText and labelText ~= "" then
        btn._scLeftPad = sz + 7
        ico:SetPoint("LEFT", layer, "LEFT", 7, 1)
    else
        btn._scLeftPad = nil
        ico:SetPoint("CENTER", layer, "CENTER", 0, 1)
    end
    ico:SetTexture(texPath)
    btn._lootIco = ico
    if ns.Theme and ns.Theme.SetButtonText then
        ns.Theme:SetButtonText(btn, labelText or "")
    end
end

local function AttachLeadingButtonIcon(btn, texPath, iconSize)
    if not (btn and texPath) then return end
    local sz = iconSize or 15
    local layer = btn._textLayer or btn
    btn._scLeftPad = sz + 9
    if not btn._leadIco then
        local ico = layer:CreateTexture(nil, "OVERLAY", nil, 2)
        ico:SetSize(sz, sz)
        ico:SetPoint("LEFT", layer, "LEFT", 6, 0)
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn._leadIco = ico
    end
    btn._leadIco:SetTexture(texPath)
    btn._leadIco:Show()
end

local function AttachGeometricLayoutIcon(btn)
    if not btn then return end
    local layer = btn._textLayer or btn
    local bars = {}
    for i = 1, 3 do
        local bar = layer:CreateTexture(nil, "OVERLAY", nil, 2)
        bar:SetSize(11, 2)
        bar:SetPoint("CENTER", layer, "CENTER", 0, (2 - i) * 4)
        bar:SetTexture(WHITE8X8)
        bar:SetVertexColor(0.84, 0.86, 0.90, 0.95)
        bars[i] = bar
    end
    btn._layoutBars = bars
end

local function SyncLayoutIconVisual(btn, isStacked)
    if not (btn and btn._layoutBars) then return end
    local r, g, b = isStacked and 1.0 or 0.84, isStacked and 0.82 or 0.86, isStacked and 0.28 or 0.90
    for i = 1, 3 do
        local bar = btn._layoutBars[i]
        if bar then
            bar:SetVertexColor(r, g, b, 0.96)
            if isStacked then
                bar:SetSize(11, 2)
            else
                bar:SetSize(i == 1 and 11 or 8, 2)
            end
        end
    end
end

local function SyncIconButtonState(btn, enabled)
    if not btn then return end
    local isOn = (enabled == true)
    btn:SetEnabled(isOn)
    if btn._lootIco then
        btn._lootIco:SetAlpha(isOn and 1.0 or 0.32)
        if btn._lootIco.SetDesaturated then
            btn._lootIco:SetDesaturated(not isOn)
        end
    end
    if btn._accentBar and btn._semanticAccent then
        local a = btn._semanticAccent
        btn._accentBar:SetVertexColor(a[1], a[2], a[3], isOn and 0.90 or 0.18)
    end
    if btn._tintWash and btn._semanticAccent then
        local a = btn._semanticAccent
        btn._tintWash:SetVertexColor(a[1], a[2], a[3], isOn and 0.10 or 0.0)
    end
end

local function ExtractCleanLinkDisplay(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then return nil end
    local colorHex = itemLink:match("^(|c%x%x%x%x%x%x%x%x)")
    local plainName = itemLink:match("%[(.-)%]")
    if plainName and plainName ~= "" then
        return (colorHex or "|cffe6edf3") .. plainName .. "|r"
    end
    return itemLink
end

local function FormatNonGearComparisonNote(comp)
    if not comp then return "" end
    local bits = {}
    if comp.uniqueOwned then
        bits[#bits + 1] = "|cffffb833" .. L["Unique item already owned"] .. "|r"
    end
    if comp.recipeNeededByMe then
        bits[#bits + 1] = "|cff47ef66" .. L["You can learn this recipe!"] .. "|r"
    elseif comp.recipeKnownByMe then
        bits[#bits + 1] = "|cffff9b3d" .. L["Already known by you"] .. "|r"
    end
    if type(comp.recipeNeededAlts) == "table" and #comp.recipeNeededAlts > 0 then
        bits[#bits + 1] = "|cff58b8ff" .. string.format(L["Needed by alt: %s"], comp.recipeNeededAlts[1]) .. "|r"
    elseif type(comp.recipeKnownAlts) == "table" and #comp.recipeKnownAlts > 0 then
        bits[#bits + 1] = "|cff9da7b5" .. string.format(L["Known by alt: %s"], comp.recipeKnownAlts[1]) .. "|r"
    end
    if comp.smallestBagSlots ~= nil then
        bits[#bits + 1] = "|cff9da7b5" .. string.format(L["Smallest equipped bag: %d slots"], comp.smallestBagSlots) .. "|r"
    end
    if (comp.ownedCount or 0) > 0 then
        bits[#bits + 1] = "|cff58a6ff" .. string.format(L["In bag/bank: x%d"], comp.ownedCount) .. "|r"
    elseif (comp.accountCount or 0) > 0 then
        bits[#bits + 1] = "|cff9da7b5" .. string.format(L["On alts: x%d"], comp.accountCount) .. "|r"
    end
    if #bits > 0 then
        return table.concat(bits, "  ·  ")
    end
    return "|cff8b949e" .. L["Item comparison applies automatically to armor, weapons, rings, and trinkets."] .. "|r"
end

local function ApplyDefaultLootRollPlacement(win)
    if not (win and UIParent) then return end
    win:ClearAllPoints()
    win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -110, 148)
end

local function ApplyDefaultResultsButtonPlacement(win)
    if not (win and UIParent) then return end
    win:ClearAllPoints()
    win:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -206, -138)
end

local function ApplyDefaultResultsWindowPlacement(win)
    if not (win and UIParent) then return end
    win:ClearAllPoints()
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
end

-- ============================================================================
-- 1. First-Roll Activation Prompt Modal
-- ============================================================================
function LootRollUI:EnsurePromptFrame()
    if self.promptFrame then
        return self.promptFrame
    end
    local Theme = ns.Theme
    if not Theme then return nil end

    local pFrame = CreateFrame("Frame", "SocialCentralLootRollPrompt", UIParent, "BackdropTemplate")
    pFrame:Hide()
    pFrame:SetSize(424, 252)
    pFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    pFrame:SetClampedToScreen(true)
    table.insert(UISpecialFrames, "SocialCentralLootRollPrompt")
    Theme:PrepareTopOverlayModal(pFrame, 850)

    local pBg = pFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    pBg:SetAllPoints(pFrame)
    pBg:SetTexture(WHITE8X8)
    pBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    pFrame._solidOpaqueBg = pBg

    local hdr = CreateFrame("Frame", nil, pFrame)
    hdr:SetPoint("TOPLEFT", 10, -8)
    hdr:SetPoint("TOPRIGHT", -10, -8)
    hdr:SetHeight(24)

    local hIco = hdr:CreateTexture(nil, "ARTWORK")
    hIco:SetSize(16, 16)
    hIco:SetPoint("LEFT", hdr, "LEFT", 2, 0)
    hIco:SetTexture(ICON_TEX)

    local closeBtn = Theme:CreateButton(hdr, 20, 18, "X", "default")
    closeBtn:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function()
        if ns.LootRoll and ns.LootRoll.SetEnabledFromPrompt then
            ns.LootRoll:SetEnabledFromPrompt(false, false)
        end
        pFrame:Hide()
    end)

    local helpBtn = Theme:CreateHelpButton(
        hdr,
        L["Help: Group Loot Roll Window"],
        L["Shows a sleek SocialCentral roll card on group drops with Need/Greed/Disenchant/Pass buttons, automatic stat & item level comparison against your equipped gear, live teammate choices, roll numbers, an epic win celebration, and a persistent Roll Results ledger."],
        L["Choose Enable Now to start using it right on this drop (you can also hide WoW's official roll bar so they don't overlap), or Keep Default anytime in Settings -> General & Tools."],
        16,
        { target = pFrame }
    )
    helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)

    local titleFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("LEFT", hIco, "RIGHT", 6, 0)
    titleFs:SetPoint("RIGHT", helpBtn, "LEFT", -6, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetWordWrap(false)
    titleFs:SetText(L["New Feature: Group Loot Roll"])

    Theme:MakeMovable(pFrame, { key = "loot_roll_prompt", skipAutoRestore = true, handles = { hdr, pFrame } })

    local itemIco = pFrame:CreateTexture(nil, "ARTWORK")
    itemIco:SetSize(28, 28)
    itemIco:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 4, -8)
    itemIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pFrame.itemIco = itemIco

    local itemName = pFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemName:SetPoint("TOPLEFT", itemIco, "TOPRIGHT", 8, -1)
    itemName:SetPoint("RIGHT", pFrame, "RIGHT", -14, 0)
    itemName:SetJustifyH("LEFT")
    itemName:SetWordWrap(false)
    pFrame.itemName = itemName

    local itemSub = pFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemSub:SetPoint("BOTTOMLEFT", itemIco, "BOTTOMRIGHT", 8, 1)
    itemSub:SetPoint("RIGHT", pFrame, "RIGHT", -14, 0)
    itemSub:SetJustifyH("LEFT")
    itemSub:SetWordWrap(false)
    itemSub:SetTextColor(0.75, 0.80, 0.88)
    itemSub:SetText(L["Compare item stats, see live rolls & track every winner!"])

    local descFs = pFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    descFs:SetPoint("TOPLEFT", itemIco, "BOTTOMLEFT", 0, -10)
    descFs:SetPoint("RIGHT", pFrame, "RIGHT", -14, 0)
    descFs:SetJustifyH("LEFT")
    descFs:SetWordWrap(true)
    descFs:SetText(L["Would you like to activate SocialCentral's Group Loot Roll system with equipped-gear comparison, live party choices, and a fixed Roll Results button?"])

    local pathHint = pFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pathHint:SetPoint("TOPLEFT", descFs, "BOTTOMLEFT", 0, -6)
    pathHint:SetPoint("RIGHT", pFrame, "RIGHT", -14, 0)
    pathHint:SetJustifyH("LEFT")
    pathHint:SetWordWrap(true)
    pathHint:SetTextColor(0.95, 0.80, 0.36)
    pathHint:SetText(L["Toggle anytime in SocialCentral Settings -> General & Tools"])

    local hideOfficialCb = CreateFrame("CheckButton", nil, pFrame, "UICheckButtonTemplate")
    hideOfficialCb:SetSize(22, 22)
    hideOfficialCb:SetPoint("TOPLEFT", pathHint, "BOTTOMLEFT", -2, -6)
    hideOfficialCb:SetChecked(true)
    local hideOfficialLbl = pFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideOfficialLbl:SetPoint("LEFT", hideOfficialCb, "RIGHT", 5, 0)
    hideOfficialLbl:SetPoint("RIGHT", pFrame, "RIGHT", -14, 0)
    hideOfficialLbl:SetJustifyH("LEFT")
    hideOfficialLbl:SetWordWrap(true)
    hideOfficialLbl:SetText(L["Hide official WoW roll bar while active"])
    pFrame.hideOfficialCb = hideOfficialCb

    local enableBtn = Theme:CreateButton(pFrame, 154, 24, L["Enable Now"], "primary")
    local enW = Theme:AutoFitButton(enableBtn, 120, 18, 220)
    enableBtn:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", -14, 12)
    enableBtn:SetScript("OnClick", function()
        local hideOff = pFrame.hideOfficialCb and pFrame.hideOfficialCb:GetChecked() and true or false
        pFrame:Hide()
        if ns.LootRoll and ns.LootRoll.SetEnabledFromPrompt then
            ns.LootRoll:SetEnabledFromPrompt(true, hideOff)
        end
        LootRollUI:Refresh()
    end)

    local skipBtn = Theme:CreateButton(pFrame, 140, 24, L["Keep Default"], "default")
    local skW = Theme:AutoFitButton(skipBtn, 120, 18, 220)
    skipBtn:SetPoint("BOTTOMLEFT", pFrame, "BOTTOMLEFT", 14, 12)
    pFrame:SetWidth(math.max(412, enW + skW + 48))
    skipBtn:SetScript("OnClick", function()
        if ns.LootRoll and ns.LootRoll.SetEnabledFromPrompt then
            ns.LootRoll:SetEnabledFromPrompt(false, false)
        end
        pFrame:Hide()
    end)

    self.promptFrame = pFrame
    return pFrame
end

function LootRollUI:ShowFirstRollPrompt(rec)
    local pFrame = self:EnsurePromptFrame()
    local Theme = ns.Theme
    if not (pFrame and Theme) then return end
    local p = Theme:GetPalette()
    Theme:ApplyBackdrop(pFrame, "window", p)
    ApplySolidOpaqueBg(pFrame, p)
    if rec then
        pFrame.itemIco:SetTexture(rec.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        pFrame.itemName:SetText(QualityHex(rec.quality) .. tostring(rec.name or "?") .. "|r")
    end
    if pFrame.hideOfficialCb then
        pFrame.hideOfficialCb:SetChecked(true)
    end
    Theme:PrepareTopOverlayModal(pFrame, 850)
    pFrame:Show()
    if pFrame.Raise then pFrame:Raise() end
end

-- ============================================================================
-- 2. Active Group Loot Roll Mini-Window
-- ============================================================================
local function OpenLootRollQuickConfigMenu(anchorBtn)
    if not (MenuUtil and MenuUtil.CreateContextMenu and anchorBtn) then
        if ns.Settings and ns.Settings.Open then
            ns.Settings:Open("general", "lootroll")
        end
        return
    end
    local function SaveRollOpt(k, v)
        if ns.db and ns.db.settings then ns.db.settings[k] = v end
        if SocialCentralDB and SocialCentralDB.settings then SocialCentralDB.settings[k] = v end
        ns:Emit("LOOT_ROLL_UPDATED")
        ns:Emit("SETTINGS_UPDATED")
        LootRollUI:SyncOfficialRollBarVisibility()
        LootRollUI:SyncResultsButton()
    end
    MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        root:CreateTitle(L["Group Loot Roll"])
        root:CreateCheckbox(L["Hide official WoW roll bar while active"], function()
            return not ns.db or not ns.db.settings or ns.db.settings.lootRollHideOfficial ~= false
        end, function()
            local cur = not ns.db or not ns.db.settings or ns.db.settings.lootRollHideOfficial ~= false
            SaveRollOpt("lootRollHideOfficial", not cur)
        end)
        root:CreateCheckbox(L["Play sound alert when a group drop is won"], function()
            return not ns.db or not ns.db.settings or ns.db.settings.lootRollWinnerSound ~= false
        end, function()
            local cur = not ns.db or not ns.db.settings or ns.db.settings.lootRollWinnerSound ~= false
            SaveRollOpt("lootRollWinnerSound", not cur)
        end)
        root:CreateCheckbox(L["Show epic celebration splash when I win a group drop"], function()
            return not ns.db or not ns.db.settings or ns.db.settings.lootRollWinnerToast ~= false
        end, function()
            local cur = not ns.db or not ns.db.settings or ns.db.settings.lootRollWinnerToast ~= false
            SaveRollOpt("lootRollWinnerToast", not cur)
        end)
        root:CreateCheckbox(L["Announce group loot winners locally in chat (with Results link)"], function()
            return not ns.db or not ns.db.settings or ns.db.settings.lootRollWinnerChatAnnounce ~= false
        end, function()
            local cur = not ns.db or not ns.db.settings or ns.db.settings.lootRollWinnerChatAnnounce ~= false
            SaveRollOpt("lootRollWinnerChatAnnounce", not cur)
        end)
        root:CreateCheckbox(L["Track group /roll (1-100) rounds passively from party/raid chat"], function()
            return not ns.db or not ns.db.settings or ns.db.settings.lootRollTrackChatRolls ~= false
        end, function()
            local cur = not ns.db or not ns.db.settings or ns.db.settings.lootRollTrackChatRolls ~= false
            SaveRollOpt("lootRollTrackChatRolls", not cur)
        end)
        root:CreateCheckbox(L["Show equipped gear comparison tooltips on hover"], function()
            return not ns.db or not ns.db.settings or ns.db.settings.lootRollShowTooltipsCompare ~= false
        end, function()
            local cur = not ns.db or not ns.db.settings or ns.db.settings.lootRollShowTooltipsCompare ~= false
            SaveRollOpt("lootRollShowTooltipsCompare", not cur)
        end)
        root:CreateCheckbox(L["Lock active roll card position"], function()
            return ns.db and ns.db.settings and ns.db.settings.lootRollCardLock == true
        end, function()
            local cur = ns.db and ns.db.settings and ns.db.settings.lootRollCardLock == true
            SaveRollOpt("lootRollCardLock", not cur)
            if LootRollUI.frame then
                LootRollUI.frame._scLocked = not cur
                LootRollUI:SyncCardLockVisual()
            end
        end)
        local layoutSub = root:CreateButton(L["Roll Card Layout"])
        if layoutSub and layoutSub.CreateRadio then
            for _, opt in ipairs({
                { id = "tabbed", label = L["Single Tabbed Card (Detailed)"] },
                { id = "stacked", label = L["Stacked Multi-Drop Cards (Compact)"] },
            }) do
                local mId = opt.id
                layoutSub:CreateRadio(opt.label, function()
                    return ((ns.db and ns.db.settings and ns.db.settings.lootRollDisplayMode) or "tabbed") == mId
                end, function()
                    SaveRollOpt("lootRollDisplayMode", mId)
                end)
            end
        end
        local visSub = root:CreateButton(L["Button Visibility"])
        if visSub and visSub.CreateRadio then
            for _, opt in ipairs({
                { id = "when_enabled", label = L["During dungeon/raid (+3 min after)"] },
                { id = "always", label = L["Always visible"] },
                { id = "hidden", label = L["Hide button"] },
            }) do
                local mId = opt.id
                visSub:CreateRadio(opt.label, function()
                    return ((ns.db and ns.db.settings and ns.db.settings.lootRollResultsButtonMode) or "when_enabled") == mId
                end, function()
                    SaveRollOpt("lootRollResultsButtonMode", mId)
                end)
            end
        end
        root:CreateDivider()
        root:CreateButton(L["Reset Roll Card Position"], function()
            if ns.Theme and ns.Theme.ResetWindowPosition then
                ns.Theme:ResetWindowPosition("loot_roll_helper")
            end
        end)
        root:CreateButton(L["All Loot Roll Settings..."], function()
            if ns.Settings and ns.Settings.Open then
                ns.Settings:Open("general", "lootroll")
            end
        end)
    end)
end

function LootRollUI:SyncCardLockVisual()
    local f = self.frame
    if not (f and f.lockBtn and ns.Theme) then return end
    local locked = (ns.db and ns.db.settings and ns.db.settings.lootRollCardLock == true)
    f._scLocked = locked
    ns.Theme:ConfigureIconButton(f.lockBtn, 20, 20, locked and ICON_LOCK_CLOSED or ICON_LOCK_OPEN, {
        size = 14,
        toggle = true,
        active = locked,
        keepColorWhenInactive = true,
        title = locked and L["Unlock roll card position"] or L["Lock active roll card position"],
        desc = L["Prevents accidental dragging of the active Group Loot Roll card during combat."],
    })
end

local function CreateStackedRollRow(parent, idx, cardFrame)
    local Theme = ns.Theme
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(50)
    row:Hide()

    local bg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetTexture(WHITE8X8)
    bg:SetVertexColor(0.05, 0.055, 0.065, (idx % 2 == 0) and 0.45 or 0.15)
    row._rowBg = bg

    local botDiv = row:CreateTexture(nil, "ARTWORK", nil, 0)
    botDiv:SetHeight(1)
    botDiv:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 0)
    botDiv:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 0)
    botDiv:SetTexture(WHITE8X8)
    botDiv:SetVertexColor(0.35, 0.35, 0.40, 0.35)
    row._botDiv = botDiv

    local icoBtn = CreateFrame("Button", nil, row)
    icoBtn:SetSize(34, 34)
    icoBtn:SetPoint("LEFT", row, "LEFT", 8, 2)
    local bdr = icoBtn:CreateTexture(nil, "BACKGROUND")
    bdr:SetAllPoints()
    bdr:SetTexture(WHITE8X8)
    icoBtn._border = bdr
    local tx = icoBtn:CreateTexture(nil, "ARTWORK")
    tx:SetPoint("TOPLEFT", 2, -2)
    tx:SetPoint("BOTTOMRIGHT", -2, 2)
    tx:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icoBtn._tex = tx
    local qtyFs = icoBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyFs:SetPoint("BOTTOMRIGHT", icoBtn, "BOTTOMRIGHT", -2, 1)
    qtyFs:SetJustifyH("RIGHT")
    qtyFs:SetTextColor(1, 1, 1)
    qtyFs:Hide()
    icoBtn._qtyBadge = qtyFs
    icoBtn:SetScript("OnEnter", function(selfBtn)
        ShowItemHoverTooltip(selfBtn, selfBtn._itemLink, true)
    end)
    icoBtn:SetScript("OnLeave", HideItemHoverTooltip)
    icoBtn:SetScript("OnClick", function(selfBtn, btn)
        if not HandleItemIconClick(selfBtn, selfBtn._itemLink, btn) and row._rollId then
            LootRollUI.selectedRollID = row._rollId
            LootRollUI:Refresh()
        end
    end)
    row.icoBtn = icoBtn

    local btnPass = Theme:CreateButton(row, 24, 24, "", "default")
    ApplyIconOnlyLootButton(btnPass, CHOICE_ICONS.PASS, 15, nil, "PASS")
    btnPass:SetPoint("RIGHT", row, "RIGHT", -8, 2)

    local btnDE = Theme:CreateButton(row, 24, 24, "", "default")
    ApplyIconOnlyLootButton(btnDE, CHOICE_ICONS.DE, 15, nil, "DE")
    btnDE:SetPoint("RIGHT", btnPass, "LEFT", -4, 0)

    local btnGreed = Theme:CreateButton(row, 24, 24, "", "default")
    ApplyIconOnlyLootButton(btnGreed, CHOICE_ICONS.GREED, 15, nil, "GREED")
    btnGreed:SetPoint("RIGHT", btnDE, "LEFT", -4, 0)

    local btnNeed = Theme:CreateButton(row, 24, 24, "", "default")
    ApplyIconOnlyLootButton(btnNeed, CHOICE_ICONS.NEED, 15, nil, "NEED")
    btnNeed:SetPoint("RIGHT", btnGreed, "LEFT", -4, 0)

    local bopBtn = Theme:CreateButton(row, 102, 24, L["Confirm BoP"], "default")
    ApplyIconOnlyLootButton(bopBtn, CHOICE_ICONS.NEED, 14, L["Confirm BoP"], "NEED")
    bopBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bopBtn:SetPoint("RIGHT", row, "RIGHT", -8, 2)
    bopBtn:Hide()
    bopBtn:SetScript("OnClick", function(_, mBtn)
        if not (row._rollId and ns.LootRoll) then return end
        if mBtn == "RightButton" then
            ns.LootRoll:CancelPendingRoll(row._rollId)
        else
            ns.LootRoll:ConfirmPendingRoll(row._rollId)
        end
    end)
    bopBtn:HookScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        SetLootRollButtonTooltipOwner(selfBtn, cardFrame, false)
        GameTooltip:SetText(L["Confirm BoP"], 0.35, 0.95, 0.55)
        GameTooltip:AddLine(L["Left-click: Confirm BoP roll\nRight-click: Cancel"], 0.88, 0.92, 0.96, true)
        GameTooltip:Show()
    end)
    bopBtn:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.bopBtn = bopBtn

    local statusFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusFs:SetPoint("RIGHT", row, "RIGHT", -8, 2)
    statusFs:SetJustifyH("RIGHT")
    statusFs:SetWordWrap(false)
    statusFs:Hide()
    row.statusFs = statusFs

    local function BindStackBtn(b, rType, tipLbl)
        b:SetScript("OnClick", function()
            if row._rollId and ns.LootRoll then
                ns.LootRoll:SubmitRoll(row._rollId, rType)
            end
        end)
        b:HookScript("OnEnter", function(selfBtn)
            if not GameTooltip then return end
            SetLootRollButtonTooltipOwner(selfBtn, cardFrame, false)
            GameTooltip:SetText(tipLbl, 1, 0.85, 0.25)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end
    BindStackBtn(btnNeed, 1, L["Need (Roll)"])
    BindStackBtn(btnGreed, 2, L["Greed"])
    BindStackBtn(btnDE, 3, L["Disenchant"])
    BindStackBtn(btnPass, 0, L["Pass"])
    row.btnNeed = btnNeed
    row.btnGreed = btnGreed
    row.btnDE = btnDE
    row.btnPass = btnPass

    local titleFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleFs:SetPoint("TOPLEFT", icoBtn, "TOPRIGHT", 8, -1)
    titleFs:SetPoint("RIGHT", btnNeed, "LEFT", -8, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetWordWrap(false)
    row.titleFs = titleFs

    local subFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subFs:SetPoint("BOTTOMLEFT", icoBtn, "BOTTOMRIGHT", 8, 2)
    subFs:SetPoint("RIGHT", btnNeed, "LEFT", -8, 0)
    subFs:SetJustifyH("LEFT")
    subFs:SetWordWrap(false)
    row.subFs = subFs

    local tBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    tBg:SetHeight(3)
    tBg:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 2)
    tBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 2)
    tBg:SetTexture(WHITE8X8)
    tBg:SetVertexColor(0.10, 0.12, 0.16, 0.90)
    local tFill = row:CreateTexture(nil, "ARTWORK", nil, 2)
    tFill:SetHeight(3)
    tFill:SetPoint("TOPLEFT", tBg, "TOPLEFT", 0, 0)
    tFill:SetWidth(80)
    tFill:SetTexture(WHITE8X8)
    tFill:SetVertexColor(0.88, 0.68, 0.22, 1.0)
    row.timerBg = tBg
    row.timerFill = tFill

    local clickBg = CreateFrame("Button", nil, row)
    clickBg:SetPoint("TOPLEFT", icoBtn, "TOPRIGHT", 2, 0)
    clickBg:SetPoint("BOTTOMRIGHT", btnNeed, "BOTTOMLEFT", -2, 0)
    clickBg:SetScript("OnClick", function(_, btn)
        if not HandleItemIconClick(icoBtn, icoBtn._itemLink, btn) and row._rollId then
            LootRollUI.selectedRollID = row._rollId
            LootRollUI:Refresh()
        end
    end)
    clickBg:SetScript("OnEnter", function()
        ShowItemHoverTooltip(icoBtn, icoBtn._itemLink, true)
    end)
    clickBg:SetScript("OnLeave", HideItemHoverTooltip)
    row.clickBg = clickBg

    return row
end

local function BuildActiveComparisonSection(f, itemCard)
    local Theme = ns.Theme
    local compBox = CreateFrame("Frame", nil, f)
    compBox:SetPoint("TOPLEFT", itemCard, "BOTTOMLEFT", 0, 0)
    compBox:SetPoint("TOPRIGHT", itemCard, "BOTTOMRIGHT", 0, 0)
    compBox:SetHeight(54)
    compBox:EnableMouse(true)
    compBox:SetScript("OnEnter", function(selfBox)
        if selfBox._equippedLink and selfBox._equippedLink ~= "" then
            ShowItemHoverTooltip(selfBox, selfBox._equippedLink, false)
        end
    end)
    compBox:SetScript("OnLeave", HideItemHoverTooltip)
    if Theme.AttachDragHandle then
        Theme:AttachDragHandle(compBox, f)
    end

    local cBg = compBox:CreateTexture(nil, "BACKGROUND", nil, -1)
    cBg:SetAllPoints()
    cBg:SetTexture(WHITE8X8)
    cBg:SetVertexColor(0.035, 0.04, 0.05, 0.72)
    compBox._bg = cBg

    local botDiv = compBox:CreateTexture(nil, "ARTWORK", nil, 1)
    botDiv:SetHeight(1)
    botDiv:SetPoint("BOTTOMLEFT", compBox, "BOTTOMLEFT", 0, 0)
    botDiv:SetPoint("BOTTOMRIGHT", compBox, "BOTTOMRIGHT", 0, 0)
    botDiv:SetTexture(WHITE8X8)
    botDiv:SetVertexColor(0.35, 0.32, 0.24, 0.45)
    compBox._botDiv = botDiv

    local slotSwapBtn = Theme:CreateButton(compBox, 34, 17, "1/2", "default")
    slotSwapBtn:SetPoint("TOPRIGHT", compBox, "TOPRIGHT", -10, -5)
    slotSwapBtn:SetScript("OnClick", function()
        if LootRollUI.selectedRollID and ns.LootRoll and ns.LootRoll.SwapComparisonSlot then
            ns.LootRoll:SwapComparisonSlot(LootRollUI.selectedRollID)
        end
    end)
    slotSwapBtn:HookScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        SetLootRollButtonTooltipOwner(selfBtn, f, false)
        GameTooltip:SetText(L["Swap Comparison Slot"], 1, 0.85, 0.25)
        GameTooltip:AddLine(L["Compare this drop against your other Ring, Trinket, or Off-Hand slot."], 0.88, 0.92, 0.96, true)
        GameTooltip:Show()
    end)
    slotSwapBtn:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    slotSwapBtn:Hide()
    f.slotSwapBtn = slotSwapBtn

    local verdictPill = CreateFrame("Frame", nil, compBox)
    verdictPill:SetSize(64, 17)
    verdictPill:SetPoint("TOPRIGHT", compBox, "TOPRIGHT", -10, -5)
    local vpBg = verdictPill:CreateTexture(nil, "BACKGROUND", nil, 0)
    vpBg:SetAllPoints()
    vpBg:SetTexture(WHITE8X8)
    vpBg:SetVertexColor(0.14, 0.36, 0.20, 0.35)
    verdictPill._bg = vpBg
    local vpBar = verdictPill:CreateTexture(nil, "ARTWORK", nil, 1)
    vpBar:SetWidth(2)
    vpBar:SetPoint("TOPLEFT", verdictPill, "TOPLEFT", 0, 0)
    vpBar:SetPoint("BOTTOMLEFT", verdictPill, "BOTTOMLEFT", 0, 0)
    vpBar:SetTexture(WHITE8X8)
    vpBar:SetVertexColor(0.28, 0.92, 0.46, 0.95)
    verdictPill._bar = vpBar
    local compVerdict = verdictPill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    compVerdict:SetPoint("CENTER", verdictPill, "CENTER", 1, 0)
    compVerdict:SetJustifyH("CENTER")
    compVerdict:SetWordWrap(false)
    verdictPill.text = compVerdict
    f.compVerdictPill = verdictPill
    f.compVerdict = compVerdict

    local compHdr = compBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    compHdr:SetPoint("TOPLEFT", compBox, "TOPLEFT", 10, -7)
    compHdr:SetPoint("RIGHT", verdictPill, "LEFT", -8, 0)
    compHdr:SetJustifyH("LEFT")
    compHdr:SetWordWrap(false)
    f.compHdr = compHdr

    local compNoteFs = compBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    compNoteFs:SetPoint("TOPLEFT", compBox, "TOPLEFT", 10, -25)
    compNoteFs:SetPoint("TOPRIGHT", compBox, "TOPRIGHT", -10, -25)
    compNoteFs:SetJustifyH("LEFT")
    compNoteFs:SetWordWrap(true)
    compNoteFs:SetSpacing(1)
    compNoteFs:Hide()
    f.compNoteFs = compNoteFs

    local statCells = {}
    for i = 1, 6 do
        local col = (i - 1) % 2
        local rowIdx = math.floor((i - 1) / 2)
        local cell = compBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell:SetPoint("TOPLEFT", compBox, "TOPLEFT", 10 + (col * 176), -26 - (rowIdx * 16))
        cell:SetWidth(172)
        cell:SetJustifyH("LEFT")
        cell:SetWordWrap(false)
        cell:Hide()
        statCells[i] = cell
    end
    f.compStatCells = statCells
    f.compBox = compBox
    return compBox
end

local function BuildIntegratedPicksSection(f, compBox)
    local Theme = ns.Theme
    -- Integrated Live Party Votes & Multi-Drop Batch Footer inside the single unified roll card
    local picksDrawer = CreateFrame("Frame", nil, f)
    picksDrawer:SetPoint("TOPLEFT", compBox, "BOTTOMLEFT", 0, 0)
    picksDrawer:SetPoint("TOPRIGHT", compBox, "BOTTOMRIGHT", 0, 0)
    picksDrawer:SetHeight(24)
    picksDrawer:EnableMouse(true)
    picksDrawer:Hide()

    local topDiv = picksDrawer:CreateTexture(nil, "ARTWORK", nil, 1)
    topDiv:SetHeight(1)
    topDiv:SetPoint("TOPLEFT", picksDrawer, "TOPLEFT", 0, 0)
    topDiv:SetPoint("TOPRIGHT", picksDrawer, "TOPRIGHT", 0, 0)
    topDiv:SetTexture(WHITE8X8)
    topDiv:SetVertexColor(0.35, 0.32, 0.24, 0.45)
    picksDrawer.topDiv = topDiv

    local tallyBtn = CreateFrame("Button", nil, picksDrawer)
    tallyBtn:SetHeight(23)
    tallyBtn:SetPoint("TOPLEFT", picksDrawer, "TOPLEFT", 0, -1)
    tallyBtn:SetPoint("TOPRIGHT", picksDrawer, "TOPRIGHT", 0, -1)
    local tBg = tallyBtn:CreateTexture(nil, "BACKGROUND", nil, -1)
    tBg:SetAllPoints()
    tBg:SetTexture(WHITE8X8)
    tBg:SetVertexColor(0.04, 0.045, 0.055, 0.65)
    tallyBtn._bg = tBg
    local tHl = tallyBtn:CreateTexture(nil, "HIGHLIGHT")
    tHl:SetAllPoints()
    tHl:SetColorTexture(1.0, 0.94, 0.78, 0.05)

    local collapseIco = tallyBtn:CreateTexture(nil, "OVERLAY")
    collapseIco:SetSize(11, 11)
    collapseIco:SetPoint("RIGHT", tallyBtn, "RIGHT", -10, 0)
    collapseIco:SetTexture(ICON_ARROW_UP)
    collapseIco:SetTexCoord(0.18, 0.82, 0.18, 0.82)
    collapseIco:SetVertexColor(0.60, 0.66, 0.74, 0.95)
    picksDrawer.collapseIco = collapseIco

    local collapseFs = tallyBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    collapseFs:SetPoint("RIGHT", collapseIco, "LEFT", -3, 0)
    collapseFs:SetJustifyH("RIGHT")
    collapseFs:SetWordWrap(false)
    picksDrawer.collapseFs = collapseFs

    local dSummaryFs = tallyBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dSummaryFs:SetPoint("LEFT", tallyBtn, "LEFT", 10, 0)
    dSummaryFs:SetPoint("RIGHT", collapseFs, "LEFT", -8, 0)
    dSummaryFs:SetJustifyH("LEFT")
    dSummaryFs:SetWordWrap(false)
    picksDrawer.summaryFs = dSummaryFs

    tallyBtn:SetScript("OnClick", function()
        LootRollUI.votesCollapsed = not (LootRollUI.votesCollapsed == true)
        LootRollUI:Refresh()
    end)
    tallyBtn:SetScript("OnEnter", function(selfBtn)
        if not (GameTooltip and picksDrawer._tooltipRows and (#picksDrawer._tooltipRows > 0 or (picksDrawer._pendingVoters and #picksDrawer._pendingVoters > 0))) then
            return
        end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(string.format(L["Live Party Choices (%d):"], #picksDrawer._tooltipRows), 1.0, 0.85, 0.28)
        for i = 1, math.min(20, #picksDrawer._tooltipRows) do
            GameTooltip:AddLine(picksDrawer._tooltipRows[i], 0.92, 0.94, 0.98, true)
        end
        if #picksDrawer._tooltipRows > 20 then
            GameTooltip:AddLine(string.format(L["...and %d more"], #picksDrawer._tooltipRows - 20), 0.70, 0.76, 0.84)
        end
        if type(picksDrawer._pendingVoters) == "table" and #picksDrawer._pendingVoters > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Still waiting:"] .. " " .. table.concat(picksDrawer._pendingVoters, ", "), 0.75, 0.82, 0.90, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click to expand or collapse party votes list"], 0.65, 0.72, 0.82)
        GameTooltip:Show()
    end)
    tallyBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    if Theme.AttachDragHandle then
        Theme:AttachDragHandle(tallyBtn, f)
    end
    picksDrawer.tallyBtn = tallyBtn

    picksDrawer._rows = {}
    for idx = 1, MAX_DRAWER_ROWS do
        local row = CreateFrame("Button", nil, picksDrawer)
        row:SetHeight(18)
        row:RegisterForClicks("RightButtonUp")
        if row.SetClipsChildren then row:SetClipsChildren(true) end
        row:SetPoint("TOPLEFT", picksDrawer, "TOPLEFT", 6, -26 - ((idx - 1) * 18))
        row:SetPoint("TOPRIGHT", picksDrawer, "TOPRIGHT", -6, -26 - ((idx - 1) * 18))
        row:Hide()

        local zebraBg = row:CreateTexture(nil, "BACKGROUND", nil, -2)
        zebraBg:SetAllPoints(row)
        zebraBg:SetTexture(WHITE8X8)
        zebraBg:SetVertexColor(1, 1, 1, (idx % 2 == 0) and 0.035 or 0.0)
        row.zebraBg = zebraBg

        local rHl = row:CreateTexture(nil, "HIGHLIGHT")
        rHl:SetAllPoints(row)
        rHl:SetColorTexture(1.0, 0.94, 0.78, 0.07)

        local voteIco = row:CreateTexture(nil, "ARTWORK")
        voteIco:SetSize(14, 14)
        voteIco:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.voteIco = voteIco

        local winAura = row:CreateTexture(nil, "BACKGROUND", nil, -1)
        winAura:SetAllPoints(row)
        winAura:SetTexture(WHITE8X8)
        winAura:SetVertexColor(1.0, 0.78, 0.16, 0.22)
        winAura:Hide()
        row.winAura = winAura

        local winEdgeTop = row:CreateTexture(nil, "ARTWORK", nil, 0)
        winEdgeTop:SetHeight(1)
        winEdgeTop:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        winEdgeTop:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        winEdgeTop:SetTexture(WHITE8X8)
        winEdgeTop:SetVertexColor(1.0, 0.86, 0.30, 0.75)
        winEdgeTop:Hide()
        row.winEdgeTop = winEdgeTop

        local winEdgeBot = row:CreateTexture(nil, "ARTWORK", nil, 0)
        winEdgeBot:SetHeight(1)
        winEdgeBot:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        winEdgeBot:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        winEdgeBot:SetTexture(WHITE8X8)
        winEdgeBot:SetVertexColor(1.0, 0.86, 0.30, 0.75)
        winEdgeBot:Hide()
        row.winEdgeBot = winEdgeBot

        local winShimmer = row:CreateTexture(nil, "OVERLAY", nil, 4)
        winShimmer:SetTexture(ICON_GLOW)
        winShimmer:SetBlendMode("ADD")
        winShimmer:SetSize(56, 22)
        winShimmer:SetPoint("LEFT", row, "LEFT", 0, 0)
        winShimmer:SetVertexColor(1.0, 0.90, 0.42, 0.55)
        winShimmer:Hide()
        row.winShimmer = winShimmer

        local winIco = row:CreateTexture(nil, "ARTWORK", nil, 2)
        winIco:SetSize(13, 13)
        winIco:SetPoint("LEFT", voteIco, "RIGHT", 3, 0)
        winIco:SetTexture(CHOICE_ICONS.WON)
        winIco:Hide()
        row.winIco = winIco

        local rollFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rollFs:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        rollFs:SetJustifyH("RIGHT")
        rollFs:SetWordWrap(false)
        row.rollFs = rollFs

        local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFs:SetPoint("LEFT", voteIco, "RIGHT", 6, 0)
        nameFs:SetPoint("RIGHT", rollFs, "LEFT", -8, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(false)
        row.nameFs = nameFs

        row:SetScript("OnClick", function(selfRow, mBtn)
            if mBtn == "RightButton" and selfRow._playerName then
                local curRec = LootRollUI.selectedRollID and ns.LootRoll and ns.LootRoll:GetRollByID(LootRollUI.selectedRollID)
                OpenPlayerQuickRollMenu(selfRow, selfRow._playerName, curRec and curRec.link or nil, selfRow._isMe == true)
            end
        end)
        if Theme.AttachDragHandle then
            Theme:AttachDragHandle(row, f)
        end

        picksDrawer._rows[idx] = row
    end

    local batchBar = CreateFrame("Frame", nil, picksDrawer)
    batchBar:SetPoint("BOTTOMLEFT", picksDrawer, "BOTTOMLEFT", 0, 0)
    batchBar:SetPoint("BOTTOMRIGHT", picksDrawer, "BOTTOMRIGHT", 0, 0)
    batchBar:SetHeight(31)
    batchBar:Hide()
    local bDiv = batchBar:CreateTexture(nil, "ARTWORK", nil, 1)
    bDiv:SetHeight(1)
    bDiv:SetPoint("TOPLEFT", batchBar, "TOPLEFT", 0, 0)
    bDiv:SetPoint("TOPRIGHT", batchBar, "TOPRIGHT", 0, 0)
    bDiv:SetTexture(WHITE8X8)
    bDiv:SetVertexColor(0.35, 0.32, 0.24, 0.40)
    batchBar.topDiv = bDiv

    local batchGreedBtn = Theme:CreateButton(batchBar, 174, 22, L["Greed Unusable"], "default")
    AttachLeadingButtonIcon(batchGreedBtn, CHOICE_ICONS.GREED, 14)
    Theme:SetButtonText(batchGreedBtn, L["Greed Unusable"])
    batchGreedBtn:SetPoint("LEFT", batchBar, "LEFT", 10, -1)
    batchGreedBtn:SetScript("OnClick", function()
        if ns.LootRoll and ns.LootRoll.SubmitBatchUnvoted then
            ns.LootRoll:SubmitBatchUnvoted("GREED_UNUSABLE")
        end
    end)
    batchGreedBtn:HookScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        SetLootRollButtonTooltipOwner(selfBtn, f, true)
        GameTooltip:SetText(L["Greed Unusable"], 1.0, 0.84, 0.25)
        GameTooltip:AddLine(L["Rolls Greed on all remaining non-BoP items your character cannot equip, already knows, or that are lower item level."], 0.88, 0.92, 0.96, true)
        GameTooltip:Show()
    end)
    batchGreedBtn:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local batchPassBtn = Theme:CreateButton(batchBar, 174, 22, L["Pass Remaining"], "default")
    AttachLeadingButtonIcon(batchPassBtn, CHOICE_ICONS.PASS, 14)
    Theme:SetButtonText(batchPassBtn, L["Pass Remaining"])
    batchPassBtn:SetPoint("RIGHT", batchBar, "RIGHT", -10, -1)
    batchPassBtn:SetScript("OnClick", function()
        if ns.LootRoll and ns.LootRoll.SubmitBatchUnvoted then
            ns.LootRoll:SubmitBatchUnvoted("PASS_ALL")
        end
    end)
    batchPassBtn:HookScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        SetLootRollButtonTooltipOwner(selfBtn, f, true)
        GameTooltip:SetText(L["Pass Remaining"], 1.0, 0.55, 0.45)
        GameTooltip:AddLine(L["Passes on every active drop you have not rolled on yet."], 0.88, 0.92, 0.96, true)
        GameTooltip:Show()
    end)
    batchPassBtn:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    batchBar.greedBtn = batchGreedBtn
    batchBar.passBtn = batchPassBtn
    picksDrawer.batchBar = batchBar

    local moreBtn = Theme:CreateButton(picksDrawer, 280, 17, "", "ghost")
    moreBtn:SetPoint("BOTTOMLEFT", picksDrawer, "BOTTOMLEFT", 10, 4)
    moreBtn:SetPoint("BOTTOMRIGHT", picksDrawer, "BOTTOMRIGHT", -10, 4)
    moreBtn:SetScript("OnClick", function()
        LootRollUI:OpenResultsWindow(LootRollUI.selectedRollID)
    end)
    moreBtn:Hide()
    picksDrawer.moreBtn = moreBtn

    -- Rule #0 arg order: AttachDragHandle(handle, win)
    if Theme.AttachDragHandle then
        Theme:AttachDragHandle(picksDrawer, f)
    end
    f.picksDrawer = picksDrawer
    return picksDrawer
end

function LootRollUI:EnsureFrame()
    if self.frame then
        return self.frame
    end
    local Theme = ns.Theme
    if not Theme then return nil end

    local f = CreateFrame("Frame", "SocialCentralLootRollFrame", UIParent, "BackdropTemplate")
    f:Hide()
    f:SetSize(CARD_WIDTH, 200)
    ApplyDefaultLootRollPlacement(f)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(540)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)

    local sBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    sBg:SetAllPoints(f)
    sBg:SetTexture(WHITE8X8)
    sBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    f._solidOpaqueBg = sBg

    -- Sleek 2px top rarity glow stripe
    local topAccentBar = f:CreateTexture(nil, "OVERLAY", nil, 4)
    topAccentBar:SetHeight(2)
    topAccentBar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    topAccentBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    topAccentBar:SetTexture(WHITE8X8)
    topAccentBar:SetVertexColor(0.86, 0.68, 0.22, 0.95)
    f.topAccentBar = topAccentBar

    -- Clean borderless tonal header with bottom hairline divider
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -4)
    hdr:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -4)
    hdr:SetHeight(28)
    local hdrBg = hdr:CreateTexture(nil, "BACKGROUND", nil, -1)
    hdrBg:SetAllPoints()
    hdrBg:SetTexture(WHITE8X8)
    hdrBg:SetVertexColor(0.11, 0.10, 0.09, 0.85)
    hdr._bg = hdrBg
    local hdrDiv = hdr:CreateTexture(nil, "ARTWORK", nil, 1)
    hdrDiv:SetHeight(1)
    hdrDiv:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", 0, 0)
    hdrDiv:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", 0, 0)
    hdrDiv:SetTexture(WHITE8X8)
    hdrDiv:SetVertexColor(0.42, 0.36, 0.24, 0.55)
    hdr._div = hdrDiv
    f.header = hdr

    local hIco = hdr:CreateTexture(nil, "ARTWORK")
    hIco:SetSize(15, 15)
    hIco:SetPoint("LEFT", hdr, "LEFT", 8, 0)
    hIco:SetTexture(ICON_TEX)

    local closeBtn = Theme:CreateButton(hdr, 20, 20, "X", "default")
    closeBtn:SetPoint("RIGHT", hdr, "RIGHT", -6, 0)
    closeBtn:SetScript("OnClick", function()
        LootRollUI._userClosedActive = true
        f:Hide()
        if LootRollUI.SyncOfficialRollBarVisibility then
            LootRollUI:SyncOfficialRollBarVisibility()
        end
        LootRollUI:SyncResultsButton()
    end)
    f.closeBtn = closeBtn

    local helpBtn = Theme:CreateHelpButton(
        hdr,
        L["Help: Group Loot Roll Window"],
        L["Shows active group loot drops with Need, Greed, Disenchant, and Pass buttons, real-time teammate choices, roll numbers, BoP safety confirmation, and automatic class usability & gear comparisons."],
        L["Hover anywhere on the item card for comparison tooltips, Shift+Click to link in chat, Ctrl+Click for Dressing Room, use the header icons to open Roll Results, switch Tabbed/Stacked layout, or lock position, or right-click the header for quick options."],
        16,
        {
            target = f,
            steps = {
                {
                    title = L["1. Roll Buttons & BoP Safety"],
                    tag = "1/4 · " .. L["Actions"],
                    text = L["Roll Need, Greed, Disenchant, or Pass from the top action bar. Tooltips appear cleanly above the window so stats stay clear, and BoP items confirm inline."],
                    target = function() return (f.actRow and f.actRow:IsShown() and f.actRow) or f end,
                },
                {
                    title = L["2. Item, Usability & Stat Comparison"],
                    tag = "2/4 · " .. L["Group Loot Roll"],
                    text = L["Hover anywhere on the item card for comparison tooltips, read the 2-column stat diff grid, or click 1/2 to swap Ring/Trinket comparison slots."],
                    target = function() return (f.itemCard and f.itemCard:IsShown() and { f.itemCard, f.compBox }) or f end,
                },
                {
                    title = L["3. Live Party Votes & Batch Actions"],
                    tag = "3/4 · " .. L["Choices:"],
                    text = L["Click the live tally strip to expand or collapse party picks. Right-click any player to whisper, or use Greed Unusable / Pass Remaining on multiple drops."],
                    target = function() return (f.picksDrawer and f.picksDrawer:IsShown() and f.picksDrawer) or f end,
                },
                {
                    title = L["4. Results, Layout, Lock & Quick Menu"],
                    tag = "4/4 · " .. L["Settings"],
                    text = L["Use the header icons to open Roll Results (dice), switch Tabbed vs. Stacked multi-drop cards, lock position with the padlock, or right-click this header."],
                    target = hdr,
                },
            },
        }
    )
    helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
    f.helpBtn = helpBtn

    local lockBtn = Theme:CreateButton(hdr, 20, 20, "", "default")
    lockBtn:SetPoint("RIGHT", helpBtn, "LEFT", -3, 0)
    lockBtn:SetScript("OnClick", function()
        local cur = ns.db and ns.db.settings and ns.db.settings.lootRollCardLock == true
        local nextVal = not cur
        if ns.db and ns.db.settings then ns.db.settings.lootRollCardLock = nextVal end
        if SocialCentralDB and SocialCentralDB.settings then SocialCentralDB.settings.lootRollCardLock = nextVal end
        LootRollUI:SyncCardLockVisual()
        ns:Emit("SETTINGS_UPDATED")
    end)
    f.lockBtn = lockBtn

    local stackModeBtn = Theme:CreateButton(hdr, 20, 20, "", "default")
    AttachGeometricLayoutIcon(stackModeBtn)
    stackModeBtn:SetPoint("RIGHT", lockBtn, "LEFT", -3, 0)
    stackModeBtn:SetScript("OnClick", function()
        local cur = (ns.LootRoll and ns.LootRoll.GetDisplayMode and ns.LootRoll:GetDisplayMode()) or "tabbed"
        local nextMode = (cur == "stacked") and "tabbed" or "stacked"
        if ns.db and ns.db.settings then ns.db.settings.lootRollDisplayMode = nextMode end
        if SocialCentralDB and SocialCentralDB.settings then SocialCentralDB.settings.lootRollDisplayMode = nextMode end
        ns:Emit("SETTINGS_UPDATED")
        LootRollUI:Refresh()
    end)
    stackModeBtn:HookScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        SetLootRollButtonTooltipOwner(selfBtn, f, false)
        GameTooltip:SetText(L["Roll Card Layout"], 1.0, 0.85, 0.25)
        GameTooltip:AddLine(L["Switch between Single Tabbed Card (detailed comparison) and Stacked Multi-Drop Cards (compact simultaneous view)."], 0.90, 0.94, 0.98, true)
        GameTooltip:Show()
    end)
    stackModeBtn:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.stackModeBtn = stackModeBtn

    local resultsBtn = Theme:CreateButton(hdr, 20, 20, "", "default")
    Theme:ConfigureIconButton(resultsBtn, 20, 20, ICON_DICE, {
        size = 15,
        title = L["Loot Roll Results"],
        desc = L["Open Loot Roll Results showing your latest dungeon, raid, or group summary (with an option inside for full history)."],
    })
    resultsBtn:SetPoint("RIGHT", stackModeBtn, "LEFT", -3, 0)
    resultsBtn:SetScript("OnClick", function()
        LootRollUI:OpenResultsWindow(LootRollUI.selectedRollID)
    end)
    f.resultsBtn = resultsBtn

    local titleFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("LEFT", hIco, "RIGHT", 6, 0)
    titleFs:SetPoint("RIGHT", resultsBtn, "LEFT", -6, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetWordWrap(false)
    titleFs:SetText(L["Group Loot Roll"])
    f.titleFs = titleFs

    f._scLocked = (ns.db and ns.db.settings and ns.db.settings.lootRollCardLock == true) and true or false
    Theme:MakeMovable(f, {
        key = "loot_roll_helper",
        handles = { hdr, f },
        onReset = ApplyDefaultLootRollPlacement,
    })
    hdr:HookScript("OnMouseUp", function(selfHdr, btn)
        if btn == "RightButton" then
            OpenLootRollQuickConfigMenu(selfHdr)
        end
    end)

    -- Stacked Multi-Drop Container (shown when displayMode == "stacked" and #active >= 2)
    local stackBox = CreateFrame("Frame", nil, f)
    stackBox:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, 0)
    stackBox:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", 0, 0)
    stackBox:SetHeight(50)
    stackBox:Hide()
    stackBox._rows = {}
    for sIdx = 1, MAX_STACKED_CARDS do
        local sRow = CreateStackedRollRow(stackBox, sIdx, f)
        sRow:SetPoint("TOPLEFT", stackBox, "TOPLEFT", 0, -((sIdx - 1) * 50))
        sRow:SetPoint("TOPRIGHT", stackBox, "TOPRIGHT", 0, -((sIdx - 1) * 50))
        stackBox._rows[sIdx] = sRow
    end
    local stackMoreFs = stackBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stackMoreFs:SetPoint("BOTTOMLEFT", stackBox, "BOTTOMLEFT", 8, 2)
    stackMoreFs:SetPoint("BOTTOMRIGHT", stackBox, "BOTTOMRIGHT", -8, 2)
    stackMoreFs:SetJustifyH("CENTER")
    stackMoreFs:Hide()
    stackBox.moreFs = stackMoreFs
    f.stackBox = stackBox

    -- Multi-item selector strip (sleek borderless dark strip + item chips + pending counter)
    local tabsRow = CreateFrame("Frame", nil, f)
    tabsRow:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, 0)
    tabsRow:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", 0, 0)
    tabsRow:SetHeight(27)
    tabsRow:Hide()
    local tabsBg = tabsRow:CreateTexture(nil, "BACKGROUND", nil, -1)
    tabsBg:SetAllPoints()
    tabsBg:SetTexture(WHITE8X8)
    tabsBg:SetVertexColor(0.04, 0.045, 0.055, 0.80)
    tabsRow._bg = tabsBg
    local tabsDiv = tabsRow:CreateTexture(nil, "ARTWORK", nil, 1)
    tabsDiv:SetHeight(1)
    tabsDiv:SetPoint("BOTTOMLEFT", tabsRow, "BOTTOMLEFT", 0, 0)
    tabsDiv:SetPoint("BOTTOMRIGHT", tabsRow, "BOTTOMRIGHT", 0, 0)
    tabsDiv:SetTexture(WHITE8X8)
    tabsDiv:SetVertexColor(0.35, 0.32, 0.24, 0.45)
    tabsRow._div = tabsDiv
    local tabsCountFs = tabsRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tabsCountFs:SetPoint("RIGHT", tabsRow, "RIGHT", -10, 0)
    tabsCountFs:SetJustifyH("RIGHT")
    tabsCountFs:SetWordWrap(false)
    f.tabsCountFs = tabsCountFs
    f.tabsRow = tabsRow
    f.rollTabBtns = {}

    local tabPrevBtn = Theme:CreateButton(tabsRow, 18, 20, "<", "default")
    tabPrevBtn:SetPoint("LEFT", tabsRow, "LEFT", 8, 0)
    tabPrevBtn:SetScript("OnClick", function()
        LootRollUI.tabPageOffset = math.max(0, (LootRollUI.tabPageOffset or 0) - 1)
        LootRollUI:Refresh()
    end)
    tabPrevBtn:Hide()
    f.tabPrevBtn = tabPrevBtn

    local tabNextBtn = Theme:CreateButton(tabsRow, 18, 20, ">", "default")
    tabNextBtn:SetPoint("RIGHT", tabsCountFs, "LEFT", -6, 0)
    tabNextBtn:SetScript("OnClick", function()
        LootRollUI.tabPageOffset = (LootRollUI.tabPageOffset or 0) + 1
        LootRollUI:Refresh()
    end)
    tabNextBtn:Hide()
    f.tabNextBtn = tabNextBtn

    -- Semantic Action Buttons Bar at top of card body (Need / Greed / Disenchant / Pass + Inline BoP Confirm)
    local actRow = CreateFrame("Frame", nil, f)
    actRow:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, 0)
    actRow:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", 0, 0)
    actRow:SetHeight(44)
    actRow:EnableMouse(true)
    local actBg = actRow:CreateTexture(nil, "BACKGROUND", nil, -1)
    actBg:SetAllPoints()
    actBg:SetTexture(WHITE8X8)
    actBg:SetVertexColor(0.04, 0.045, 0.055, 0.48)
    actRow._bg = actBg
    local actBotDiv = actRow:CreateTexture(nil, "ARTWORK", nil, 1)
    actBotDiv:SetHeight(1)
    actBotDiv:SetPoint("BOTTOMLEFT", actRow, "BOTTOMLEFT", 0, 0)
    actBotDiv:SetPoint("BOTTOMRIGHT", actRow, "BOTTOMRIGHT", 0, 0)
    actBotDiv:SetTexture(WHITE8X8)
    actBotDiv:SetVertexColor(0.35, 0.32, 0.24, 0.45)
    actRow._botDiv = actBotDiv
    if Theme.AttachDragHandle then
        Theme:AttachDragHandle(actRow, f)
    end
    f.actRow = actRow

    local btnNeed = Theme:CreateButton(actRow, 86, 34, "", "default")
    ApplyIconOnlyLootButton(btnNeed, CHOICE_ICONS.NEED, 18, L["RollBtnNeed"], "NEED")
    local btnGreed = Theme:CreateButton(actRow, 86, 34, "", "default")
    ApplyIconOnlyLootButton(btnGreed, CHOICE_ICONS.GREED, 18, L["RollBtnGreed"], "GREED")
    local btnDE = Theme:CreateButton(actRow, 86, 34, "", "default")
    ApplyIconOnlyLootButton(btnDE, CHOICE_ICONS.DE, 18, L["RollBtnDE"], "DE")
    local btnPass = Theme:CreateButton(actRow, 86, 34, "", "default")
    ApplyIconOnlyLootButton(btnPass, CHOICE_ICONS.PASS, 18, L["Pass"], "PASS")

    local bopConfirmRow = CreateFrame("Frame", nil, actRow)
    bopConfirmRow:SetAllPoints(actRow)
    bopConfirmRow:Hide()
    local bopConfirmBtn = Theme:CreateButton(bopConfirmRow, 240, 32, L["Confirm BoP"], "default")
    ApplyIconOnlyLootButton(bopConfirmBtn, CHOICE_ICONS.NEED, 16, L["Confirm BoP"], "NEED")
    bopConfirmBtn:SetPoint("LEFT", bopConfirmRow, "LEFT", 10, 0)
    bopConfirmBtn:SetScript("OnClick", function()
        if LootRollUI.selectedRollID and ns.LootRoll and ns.LootRoll.ConfirmPendingRoll then
            ns.LootRoll:ConfirmPendingRoll(LootRollUI.selectedRollID)
        end
    end)
    local bopCancelBtn = Theme:CreateButton(bopConfirmRow, 102, 32, L["Cancel"], "danger")
    bopCancelBtn:SetPoint("RIGHT", bopConfirmRow, "RIGHT", -10, 0)
    bopCancelBtn:SetScript("OnClick", function()
        if LootRollUI.selectedRollID and ns.LootRoll and ns.LootRoll.CancelPendingRoll then
            ns.LootRoll:CancelPendingRoll(LootRollUI.selectedRollID)
        end
    end)
    bopConfirmBtn:SetPoint("RIGHT", bopCancelBtn, "LEFT", -8, 0)
    f.bopConfirmRow = bopConfirmRow
    f.bopConfirmBtn = bopConfirmBtn
    f.bopCancelBtn = bopCancelBtn

    local statusWrap = CreateFrame("Frame", nil, actRow)
    statusWrap:SetPoint("TOPLEFT", actRow, "TOPLEFT", 10, -5)
    statusWrap:SetPoint("BOTTOMRIGHT", actRow, "BOTTOMRIGHT", -10, 5)
    statusWrap:Hide()
    local stBg = statusWrap:CreateTexture(nil, "BACKGROUND", nil, 0)
    stBg:SetAllPoints()
    stBg:SetTexture(WHITE8X8)
    stBg:SetVertexColor(0.14, 0.24, 0.16, 0.30)
    statusWrap._bg = stBg
    local statusBanner = statusWrap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusBanner:SetPoint("LEFT", statusWrap, "LEFT", 8, 0)
    statusBanner:SetPoint("RIGHT", statusWrap, "RIGHT", -8, 0)
    statusBanner:SetJustifyH("CENTER")
    statusBanner:SetWordWrap(false)
    f.statusWrap = statusWrap
    f.statusBanner = statusBanner

    local function BindRollButton(btn, rollType, reasonKey, helpTitle, helpDesc)
        btn:SetScript("OnClick", function()
            if LootRollUI.selectedRollID and ns.LootRoll then
                local curId = LootRollUI.selectedRollID
                ns.LootRoll:SubmitRoll(curId, rollType)
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.30, function()
                        if LootRollUI.selectedRollID == curId and ns.LootRoll then
                            local curRec = ns.LootRoll:GetRollByID(curId)
                            if curRec and curRec.pendingConfirm then return end
                            for _, r in ipairs(ns.LootRoll:GetActiveList()) do
                                if not r.myChoice and not r.resolved then
                                    LootRollUI.selectedRollID = r.rollID
                                    LootRollUI:Refresh()
                                    break
                                end
                            end
                        end
                    end)
                end
            end
        end)
        btn:HookScript("OnEnter", function(selfBtn)
            local rec = LootRollUI.selectedRollID and ns.LootRoll and ns.LootRoll:GetRollByID(LootRollUI.selectedRollID)
            local reason = reasonKey and rec and rec[reasonKey]
            if not GameTooltip then return end
            SetLootRollButtonTooltipOwner(selfBtn, f, false)
            GameTooltip:ClearLines()
            if not btn:IsEnabled() and reason and reason ~= "" then
                GameTooltip:AddLine(helpTitle .. " — " .. L["Unavailable"], 1.0, 0.45, 0.38)
                GameTooltip:AddLine(reason, 0.90, 0.92, 0.95, true)
                GameTooltip:AddLine(helpDesc, 0.72, 0.78, 0.86, true)
            else
                GameTooltip:AddLine(helpTitle, 1.0, 0.85, 0.25)
                GameTooltip:AddLine(helpDesc, 0.90, 0.94, 0.98, true)
            end
            GameTooltip:Show()
        end)
        btn:HookScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end
    BindRollButton(btnNeed, 1, "reasonNeed", L["Need (Roll)"], L["Roll Need for an upgrade you can use right now."])
    BindRollButton(btnGreed, 2, "reasonGreed", L["Greed"], L["Roll Greed when nobody needs the item (or for gold/vendor)."])
    BindRollButton(btnDE, 3, "reasonDisenchant", L["Disenchant"], L["Roll Disenchant if an Enchanter in the group can break the item into shards."])
    BindRollButton(btnPass, 0, nil, L["Pass"], L["Pass on this item so other party members can roll."])

    f.btnNeed = btnNeed
    f.btnGreed = btnGreed
    f.btnDE = btnDE
    f.btnPass = btnPass

    -- Item Hero Band (borderless with soft quality glow wash + 44x44 icon + edge-to-edge timer bar)
    local itemCard = CreateFrame("Frame", nil, f)
    itemCard:SetPoint("TOPLEFT", actRow, "BOTTOMLEFT", 0, 0)
    itemCard:SetPoint("TOPRIGHT", actRow, "BOTTOMRIGHT", 0, 0)
    itemCard:SetHeight(66)
    if itemCard.SetClipsChildren then itemCard:SetClipsChildren(true) end
    local heroGlow = itemCard:CreateTexture(nil, "BACKGROUND", nil, 0)
    heroGlow:SetSize(210, 110)
    heroGlow:SetPoint("LEFT", itemCard, "LEFT", -36, 4)
    heroGlow:SetTexture(ICON_GLOW)
    heroGlow:SetBlendMode("ADD")
    heroGlow:SetVertexColor(0.64, 0.21, 0.93, 0.14)
    f.heroGlow = heroGlow
    f.itemCard = itemCard

    local iconBtn = CreateFrame("Button", nil, itemCard)
    iconBtn:SetSize(44, 44)
    iconBtn:SetPoint("LEFT", itemCard, "LEFT", 10, 2)
    local iconBorder = iconBtn:CreateTexture(nil, "BACKGROUND")
    iconBorder:SetAllPoints(iconBtn)
    iconBorder:SetTexture(WHITE8X8)
    iconBtn._border = iconBorder
    local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT", 2, -2)
    iconTex:SetPoint("BOTTOMRIGHT", -2, 2)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconBtn._tex = iconTex
    local qtyBadge = iconBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyBadge:SetPoint("BOTTOMRIGHT", iconBtn, "BOTTOMRIGHT", -2, 2)
    qtyBadge:SetJustifyH("RIGHT")
    qtyBadge:SetTextColor(1, 1, 1)
    qtyBadge:Hide()
    iconBtn._qtyBadge = qtyBadge
    iconBtn:SetScript("OnEnter", function(selfBtn)
        ShowItemHoverTooltip(selfBtn, selfBtn._itemLink, true)
    end)
    iconBtn:SetScript("OnLeave", HideItemHoverTooltip)
    iconBtn:SetScript("OnClick", function(selfBtn, btn)
        HandleItemIconClick(selfBtn, selfBtn._itemLink, btn)
    end)
    f.iconBtn = iconBtn

    local itemHoverBtn = CreateFrame("Button", nil, itemCard)
    itemHoverBtn:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 4, 4)
    itemHoverBtn:SetPoint("BOTTOMRIGHT", itemCard, "BOTTOMRIGHT", -4, 6)
    itemHoverBtn:SetScript("OnEnter", function()
        ShowItemHoverTooltip(iconBtn, iconBtn._itemLink, true)
    end)
    itemHoverBtn:SetScript("OnLeave", HideItemHoverTooltip)
    itemHoverBtn:SetScript("OnClick", function(_, btn)
        HandleItemIconClick(iconBtn, iconBtn._itemLink, btn)
    end)
    if Theme.AttachDragHandle then
        Theme:AttachDragHandle(itemHoverBtn, f)
    end
    f.itemHoverBtn = itemHoverBtn

    local timerNumFs = itemCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timerNumFs:SetPoint("TOPRIGHT", itemCard, "TOPRIGHT", -10, -10)
    timerNumFs:SetJustifyH("RIGHT")
    timerNumFs:SetWordWrap(false)
    f.timerNumFs = timerNumFs

    local itemTitle = itemCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemTitle:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 10, -2)
    itemTitle:SetPoint("RIGHT", timerNumFs, "LEFT", -8, 0)
    itemTitle:SetJustifyH("LEFT")
    itemTitle:SetWordWrap(false)
    f.itemTitle = itemTitle

    local itemMeta = itemCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemMeta:SetPoint("BOTTOMLEFT", iconBtn, "BOTTOMRIGHT", 10, 4)
    itemMeta:SetJustifyH("LEFT")
    itemMeta:SetWordWrap(false)
    f.itemMeta = itemMeta

    local bindPill = CreateFrame("Frame", nil, itemCard)
    bindPill:SetSize(36, 15)
    bindPill:SetPoint("LEFT", itemMeta, "RIGHT", 6, 0)
    local bpBg = bindPill:CreateTexture(nil, "BACKGROUND", nil, 0)
    bpBg:SetAllPoints()
    bpBg:SetTexture(WHITE8X8)
    bindPill._bg = bpBg
    local bpFs = bindPill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bpFs:SetPoint("CENTER", bindPill, "CENTER", 0, 0)
    bpFs:SetJustifyH("CENTER")
    bpFs:SetWordWrap(false)
    bindPill.text = bpFs
    f.bindPill = bindPill

    -- Edge-to-edge 4px glowing timer bar along bottom of Hero band
    local timerBg = itemCard:CreateTexture(nil, "BACKGROUND", nil, 1)
    timerBg:SetHeight(4)
    timerBg:SetPoint("BOTTOMLEFT", itemCard, "BOTTOMLEFT", 0, 0)
    timerBg:SetPoint("BOTTOMRIGHT", itemCard, "BOTTOMRIGHT", 0, 0)
    timerBg:SetTexture(WHITE8X8)
    timerBg:SetVertexColor(0.10, 0.12, 0.16, 0.95)
    local timerFill = itemCard:CreateTexture(nil, "ARTWORK", nil, 2)
    timerFill:SetHeight(4)
    timerFill:SetPoint("TOPLEFT", timerBg, "TOPLEFT", 0, 0)
    timerFill:SetWidth(120)
    timerFill:SetTexture(WHITE8X8)
    timerFill:SetVertexColor(0.28, 0.82, 0.56, 1.0)
    local timerSpark = itemCard:CreateTexture(nil, "OVERLAY", nil, 3)
    timerSpark:SetSize(16, 9)
    timerSpark:SetPoint("CENTER", timerFill, "RIGHT", 0, 0)
    timerSpark:SetTexture(ICON_GLOW)
    timerSpark:SetBlendMode("ADD")
    timerSpark:SetVertexColor(1.0, 0.94, 0.60, 0.85)
    f.timerBg = timerBg
    f.timerFill = timerFill
    f.timerSpark = timerSpark

    -- Structured Gear / Recipe Comparison Band (modular helper)
    local compBox = BuildActiveComparisonSection(f, itemCard)

    -- Integrated Live Party Votes & Multi-Drop Batch Footer (modular helper)
    BuildIntegratedPicksSection(f, compBox)

    local function UpdateSingleTimerBar(rec, tBg, tFill, tSpark, tNumFs, cacheObj, nowMono)
        if not (rec and tBg and tFill) then return end
        local fullW = math.max(40, (tBg:GetWidth() or 350))
        if rec.resolved then
            if cacheObj._lastTimerState ~= ("DONE:" .. tostring(rec.rollID) .. ":" .. fullW) then
                cacheObj._lastTimerState = "DONE:" .. tostring(rec.rollID) .. ":" .. fullW
                cacheObj._lastTimerPx = nil
                tFill:SetWidth(fullW)
                tFill:SetVertexColor(1.0, 0.80, 0.22, 0.92)
                if tSpark then tSpark:Hide() end
            end
            if tNumFs then
                local wantTxt = "|cffffd24d" .. L["Done"] .. "|r"
                if cacheObj._lastTimerTxt ~= wantTxt then
                    cacheObj._lastTimerTxt = wantTxt
                    tNumFs:SetText(wantTxt)
                end
            end
            return
        end
        local remMs
        if rec.isSimulated then
            remMs = math.max(0, ((rec.simExpiresAt or 0) - nowMono) * 1000)
        else
            remMs = GetLootRollTimeLeft and Safe.Number(Safe.Call(GetLootRollTimeLeft, rec.rollID)) or 0
        end
        if (not remMs or remMs <= 0) and rec.myChoice and rec.maxWaitAt then
            remMs = math.max(0, ((rec.maxWaitAt - 14.0) - nowMono) * 1000)
        end
        local totalMs = math.max(1000, (tonumber(rec.durationSec) or 60) * 1000)
        local frac = math.max(0.02, math.min(1.0, (remMs or 0) / totalMs))
        local wantPx = math.max(2, math.floor((fullW * frac) + 0.5))
        local isUrgent = (not rec.myChoice) and ((remMs or 0) <= 10500)
        if cacheObj._lastTimerPx ~= wantPx or cacheObj._lastTimerUrgent ~= isUrgent or cacheObj._lastTimerVoted ~= (rec.myChoice ~= nil) then
            cacheObj._lastTimerPx = wantPx
            cacheObj._lastTimerUrgent = isUrgent
            cacheObj._lastTimerVoted = (rec.myChoice ~= nil)
            cacheObj._lastTimerState = nil
            tFill:SetWidth(wantPx)
            if rec.myChoice then
                tFill:SetVertexColor(0.28, 0.82, 0.46, 0.88)
            elseif isUrgent then
                tFill:SetVertexColor(1.0, 0.30, 0.24, 1.0)
            elseif frac <= 0.38 then
                tFill:SetVertexColor(0.96, 0.72, 0.22, 1.0)
            else
                tFill:SetVertexColor(0.28, 0.82, 0.56, 1.0)
            end
        end
        if tSpark then
            if isUrgent then
                local pulse = 0.45 + 0.55 * math.sin(nowMono * 9.0)
                tSpark:SetVertexColor(1.0, 0.40, 0.30, pulse)
                tSpark:Show()
            elseif not rec.myChoice then
                tSpark:SetVertexColor(1.0, 0.94, 0.62, 0.72)
                tSpark:Show()
            else
                tSpark:Hide()
            end
        end
        if tNumFs then
            local remSec = math.max(0, math.ceil((remMs or 0) / 1000))
            if cacheObj._lastTimerSec ~= remSec or cacheObj._lastTimerSecVoted ~= (rec.myChoice ~= nil) or cacheObj._lastTimerSecUrg ~= isUrgent then
                cacheObj._lastTimerSec = remSec
                cacheObj._lastTimerSecVoted = (rec.myChoice ~= nil)
                cacheObj._lastTimerSecUrg = isUrgent
                local secTxt
                if rec.myChoice then
                    secTxt = (remSec > 0) and ("|cff47ef66" .. L["Rolled"] .. "|r |cff9da7b5" .. tostring(remSec) .. "s|r") or ("|cff47ef66" .. L["Rolled"] .. "|r")
                else
                    secTxt = (isUrgent and "|cffff5555" or "|cffcfd8e3") .. tostring(remSec) .. "s|r"
                end
                cacheObj._lastTimerTxt = secTxt
                tNumFs:SetText(secTxt)
            end
        end
    end

    local function OnRollFrameUpdate(selfFrame, elapsed)
        local nowMono = GetTime and GetTime() or 0
        if not selfFrame._nextRollCheckAt or nowMono >= selfFrame._nextRollCheckAt then
            selfFrame._nextRollCheckAt = nowMono + 0.5
            if ns.LootRoll and ns.LootRoll.activeRolls and ns.LootRoll.rollOrder then
                for _, rId in ipairs(ns.LootRoll.rollOrder) do
                    local ar = ns.LootRoll.activeRolls[rId]
                    if ar and ar.hideAfterAt and nowMono >= ar.hideAfterAt then
                        LootRollUI:Refresh()
                        return
                    end
                end
            end
        end
        local d = selfFrame.picksDrawer
        local hasWinnerShimmer = (d and d._hasWinner and d:IsShown() and not LootRollUI.votesCollapsed) == true
        local rec = LootRollUI.selectedRollID and ns.LootRoll and ns.LootRoll:GetRollByID(LootRollUI.selectedRollID)
        local isStacked = (selfFrame.stackBox and selfFrame.stackBox:IsShown()) == true
        local stepMin = (hasWinnerShimmer or isStacked or (rec and not rec.myChoice and not rec.resolved)) and 0.033 or 0.25

        selfFrame._animElapsed = (selfFrame._animElapsed or 0) + (elapsed or 0)
        if selfFrame._animElapsed < stepMin then
            return
        end
        selfFrame._animElapsed = 0

        if hasWinnerShimmer then
            local pulse = 0.5 + 0.5 * math.sin(nowMono * 4.5)
            local sweep = (nowMono * 0.72) % 1.0
            local sweepAlpha = math.sin(sweep * math.pi)
            for idx = 1, MAX_DRAWER_ROWS do
                local rw = d._rows and d._rows[idx]
                if rw and rw._isWinner and rw:IsShown() then
                    if rw.winAura then rw.winAura:SetAlpha(0.16 + 0.16 * pulse) end
                    if rw.winEdgeTop then rw.winEdgeTop:SetAlpha(0.55 + 0.40 * pulse) end
                    if rw.winEdgeBot then rw.winEdgeBot:SetAlpha(0.55 + 0.40 * pulse) end
                    if rw.winShimmer then
                        local rwW = math.max(120, rw:GetWidth() or 300)
                        local sx = math.floor((sweep * (rwW + 30)) - 30)
                        if rw._lastShimmerX ~= sx then
                            rw._lastShimmerX = sx
                            rw.winShimmer:SetPoint("LEFT", rw, "LEFT", sx, 0)
                        end
                        rw.winShimmer:SetAlpha(0.18 + 0.52 * sweepAlpha)
                    end
                end
            end
        end

        if isStacked and selfFrame.stackBox._rows then
            for sIdx = 1, MAX_STACKED_CARDS do
                local sr = selfFrame.stackBox._rows[sIdx]
                if sr and sr:IsShown() and sr._rollId and ns.LootRoll then
                    local sRec = ns.LootRoll:GetRollByID(sr._rollId)
                    if sRec then
                        UpdateSingleTimerBar(sRec, sr.timerBg, sr.timerFill, nil, nil, sr, nowMono)
                    end
                end
            end
        elseif rec then
            UpdateSingleTimerBar(rec, selfFrame.timerBg, selfFrame.timerFill, selfFrame.timerSpark, selfFrame.timerNumFs, selfFrame, nowMono)
        end
    end

    f:HookScript("OnShow", function(selfFrame)
        selfFrame._animElapsed = 0.04
        selfFrame._lastTimerPx = nil
        selfFrame._lastTimerState = nil
        selfFrame._lastTimerSec = nil
        selfFrame._lastTimerTxt = nil
        if Theme and Theme.HasSavedWindowPosition and Theme:HasSavedWindowPosition("loot_roll_helper") then
            Theme:RestoreWindowPosition(selfFrame, "loot_roll_helper", false, { allowLockedRestore = true })
        end
        LootRollUI:SyncCardLockVisual()
        selfFrame:SetScript("OnUpdate", OnRollFrameUpdate)
    end)
    f:HookScript("OnHide", function(selfFrame)
        selfFrame:SetScript("OnUpdate", nil)
    end)

    self.frame = f
    self:SyncCardLockVisual()
    return f
end

function LootRollUI:ApplyTheme()
    local f = self.frame
    local Theme = ns.Theme
    if not (f and Theme) then return end
    local p = Theme:GetPalette()
    ApplySolidOpaqueBg(f, p)
    Theme:ApplyBackdrop(f, "window", p)
    local hBg = (p and p.headerBg) or { 0.11, 0.10, 0.09, 1.0 }
    local iBg = (p and p.insetBg) or { 0.04, 0.045, 0.055, 1.0 }
    local divC = (p and (p.surfaceBorder or p.windowBorder)) or { 0.35, 0.32, 0.24, 1.0 }
    if f.header and f.header._bg then
        f.header._bg:SetVertexColor(hBg[1], hBg[2], hBg[3], 0.92)
    end
    if f.header and f.header._div then
        f.header._div:SetVertexColor(divC[1], divC[2], divC[3], 0.55)
    end
    if f.tabsRow and f.tabsRow._bg then
        f.tabsRow._bg:SetVertexColor(iBg[1], iBg[2], iBg[3], 0.85)
    end
    if f.tabsRow and f.tabsRow._div then
        f.tabsRow._div:SetVertexColor(divC[1], divC[2], divC[3], 0.45)
    end
    if f.actRow and f.actRow._bg then
        f.actRow._bg:SetVertexColor(iBg[1], iBg[2], iBg[3], 0.48)
    end
    if f.actRow and f.actRow._botDiv then
        f.actRow._botDiv:SetVertexColor(divC[1], divC[2], divC[3], 0.55)
    end
    if f.compBox and f.compBox._bg then
        f.compBox._bg:SetVertexColor(iBg[1], iBg[2], iBg[3], 0.72)
    end
    if f.compBox and f.compBox._botDiv then
        f.compBox._botDiv:SetVertexColor(divC[1], divC[2], divC[3], 0.45)
    end
    if f.titleFs and p and p.textGold then
        f.titleFs:SetTextColor(p.textGold[1], p.textGold[2], p.textGold[3])
    end
    if f.resultsBtn then Theme:StyleButton(f.resultsBtn, "default") end
    if f.closeBtn then Theme:StyleButton(f.closeBtn, "default") end
    if f.lockBtn then Theme:StyleButton(f.lockBtn, "default") end
    if f.stackModeBtn then Theme:StyleButton(f.stackModeBtn, "default") end
    if f.slotSwapBtn then Theme:StyleButton(f.slotSwapBtn, "default") end
    if f.tabPrevBtn then Theme:StyleButton(f.tabPrevBtn, "default") end
    if f.tabNextBtn then Theme:StyleButton(f.tabNextBtn, "default") end
    if f.btnNeed then Theme:StyleButton(f.btnNeed, "default") end
    if f.btnGreed then Theme:StyleButton(f.btnGreed, "default") end
    if f.btnDE then Theme:StyleButton(f.btnDE, "default") end
    if f.btnPass then Theme:StyleButton(f.btnPass, "default") end
    if f.bopConfirmBtn then Theme:StyleButton(f.bopConfirmBtn, "default") end
    if f.bopCancelBtn then Theme:StyleButton(f.bopCancelBtn, "danger") end
    if f.stackBox and f.stackBox._rows then
        for idx, sr in ipairs(f.stackBox._rows) do
            if sr._rowBg then
                sr._rowBg:SetVertexColor(iBg[1], iBg[2], iBg[3], (idx % 2 == 0) and 0.60 or 0.20)
            end
            if sr._botDiv then
                sr._botDiv:SetVertexColor(divC[1], divC[2], divC[3], 0.35)
            end
            Theme:StyleButton(sr.btnNeed, "default")
            Theme:StyleButton(sr.btnGreed, "default")
            Theme:StyleButton(sr.btnDE, "default")
            Theme:StyleButton(sr.btnPass, "default")
            Theme:StyleButton(sr.bopBtn, "default")
        end
    end
    if f.picksDrawer then
        if f.picksDrawer.topDiv then
            f.picksDrawer.topDiv:SetVertexColor(divC[1], divC[2], divC[3], 0.45)
        end
        if f.picksDrawer.tallyBtn and f.picksDrawer.tallyBtn._bg then
            f.picksDrawer.tallyBtn._bg:SetVertexColor(iBg[1], iBg[2], iBg[3], 0.72)
        end
        if f.picksDrawer.moreBtn then Theme:StyleButton(f.picksDrawer.moreBtn, "ghost") end
        if f.picksDrawer.batchBar then
            if f.picksDrawer.batchBar.topDiv then
                f.picksDrawer.batchBar.topDiv:SetVertexColor(divC[1], divC[2], divC[3], 0.40)
            end
            Theme:StyleButton(f.picksDrawer.batchBar.greedBtn, "default")
            Theme:StyleButton(f.picksDrawer.batchBar.passBtn, "default")
        end
    end
end

-- ============================================================================
-- 3. Blizzard Official Roll Bar Suppression (Zero Taint, Weak-Key, Fail-Open)
-- ============================================================================
local function SafeIsFrameForbidden(obj)
    if not obj then return true end
    if not obj.IsForbidden then return false end
    local ok, forb = pcall(obj.IsForbidden, obj)
    return (not ok) or (forb == true)
end

local function SafeIsFrameProtected(obj)
    if not obj or not obj.IsProtected then return false end
    local ok, prot = pcall(obj.IsProtected, obj)
    return ok and (prot == true)
end

function LootRollUI:ShouldSuppressOfficialRollBar(targetFrame)
    if not (ns.LootRoll and ns.LootRoll.IsEnabled and ns.LootRoll:IsEnabled()) then
        return false
    end
    if not (ns.LootRoll.IsHideOfficialEnabled and ns.LootRoll:IsHideOfficialEnabled()) then
        return false
    end
    if self._userClosedActive then
        return false
    end
    -- Fail-open safety: never hide an official GroupLootFrame whose active rollID is untracked by SocialCentral!
    if targetFrame and targetFrame ~= _G.GroupLootContainer then
        local rId = Safe.Number(targetFrame.rollID)
        if rId and rId > 0 then
            local remMs = GetLootRollTimeLeft and Safe.Number(Safe.Call(GetLootRollTimeLeft, rId)) or 0
            if remMs and remMs > 0 then
                if not (ns.LootRoll.activeRolls and ns.LootRoll.activeRolls[rId]) then
                    if ns.LootRoll.RecoverActiveRolls then
                        ns.LootRoll:RecoverActiveRolls()
                    end
                    if not (ns.LootRoll.activeRolls and ns.LootRoll.activeRolls[rId]) then
                        return false
                    end
                end
            end
        end
    end
    return true
end

local OFFICIAL_CHILD_BTN_KEYS = { "NeedButton", "GreedButton", "PassButton", "DisenchantButton", "IconFrame" }

local function SetOfficialRollMouseState(frame, allowMouse)
    if frame.EnableMouse then
        pcall(frame.EnableMouse, frame, allowMouse)
    end
    for _, k in ipairs(OFFICIAL_CHILD_BTN_KEYS) do
        local child = frame[k]
        if child and not SafeIsFrameForbidden(child) and child.EnableMouse then
            pcall(child.EnableMouse, child, allowMouse)
        end
    end
end

function LootRollUI:SyncSingleOfficialLootFrame(frame, shouldHide, isContainer)
    if not frame or SafeIsFrameForbidden(frame) then return end

    if not hookedOfficialFrames[frame] and frame.HookScript then
        hookedOfficialFrames[frame] = true
        frame:HookScript("OnShow", function(selfFrame)
            if LootRollUI and LootRollUI.ShouldSuppressOfficialRollBar and LootRollUI:ShouldSuppressOfficialRollBar(selfFrame) then
                LootRollUI:SyncSingleOfficialLootFrame(selfFrame, true, selfFrame == _G.GroupLootContainer)
            end
        end)
    end

    local isProtected = SafeIsFrameProtected(frame)
    local inCombat = (InCombatLockdown and InCombatLockdown()) == true
    if shouldHide then
        local okShown, isSh = pcall(frame.IsShown, frame)
        if okShown and isSh then
            suppressedOfficialFrames[frame] = true
        end
        pcall(frame.SetAlpha, frame, 0)
        if inCombat and isProtected then
            self._pendingOfficialLootSync = true
            return
        end
        SetOfficialRollMouseState(frame, false)
        if not isProtected and not isContainer then
            pcall(frame.SetScale, frame, 0.001)
        end
    else
        pcall(frame.SetAlpha, frame, 1)
        if inCombat and isProtected then
            self._pendingOfficialLootSync = true
            return
        end
        if not isProtected and not isContainer then
            pcall(frame.SetScale, frame, 1)
        end
        SetOfficialRollMouseState(frame, true)
        if suppressedOfficialFrames[frame] then
            suppressedOfficialFrames[frame] = nil
            local shouldShow = false
            if isContainer then
                local maxFrames = math.max(8, Safe.Number(_G.NUM_GROUP_LOOT_FRAMES) or 8)
                for i = 1, maxFrames do
                    local child = _G["GroupLootFrame" .. i]
                    if child and not SafeIsFrameForbidden(child) then
                        local rId = child.rollID and Safe.Number(child.rollID)
                        local rem = rId and GetLootRollTimeLeft and Safe.Number(Safe.Call(GetLootRollTimeLeft, rId))
                        if rem and rem > 0 then
                            shouldShow = true
                            break
                        end
                    end
                end
            else
                local rId = frame.rollID and Safe.Number(frame.rollID)
                local rem = rId and GetLootRollTimeLeft and Safe.Number(Safe.Call(GetLootRollTimeLeft, rId))
                if rem and rem > 0 then
                    shouldShow = true
                end
            end
            if shouldShow and not isProtected then
                pcall(frame.Show, frame)
            end
        end
    end
end

function LootRollUI:SyncOfficialRollBarVisibility()
    local maxFrames = math.max(8, Safe.Number(_G.NUM_GROUP_LOOT_FRAMES) or 8)
    local anyUntrackedVisible = false
    for i = 1, maxFrames do
        local f = _G["GroupLootFrame" .. i]
        if f and not SafeIsFrameForbidden(f) then
            local hideThis = self:ShouldSuppressOfficialRollBar(f)
            if not hideThis then
                local rId = Safe.Number(f.rollID)
                local rem = rId and GetLootRollTimeLeft and Safe.Number(Safe.Call(GetLootRollTimeLeft, rId))
                if rem and rem > 0 then
                    anyUntrackedVisible = true
                end
            end
            self:SyncSingleOfficialLootFrame(f, hideThis, false)
        end
    end
    local container = _G.GroupLootContainer
    if container and not SafeIsFrameForbidden(container) then
        if type(container.rollFrames) == "table" then
            for _, rf in ipairs(container.rollFrames) do
                if rf and not SafeIsFrameForbidden(rf) then
                    local hideRf = self:ShouldSuppressOfficialRollBar(rf)
                    if not hideRf then anyUntrackedVisible = true end
                    self:SyncSingleOfficialLootFrame(rf, hideRf, false)
                end
            end
        end
        local hideContainer = self:ShouldSuppressOfficialRollBar(container) and (not anyUntrackedVisible)
        self:SyncSingleOfficialLootFrame(container, hideContainer, true)
    end
end

function LootRollUI:InstallOfficialLootHooks()
    if self._officialLootHooksInstalled then return end
    self._officialLootHooksInstalled = true
    if hooksecurefunc then
        if type(_G.GroupLootFrame_OpenNewFrame) == "function" then
            hooksecurefunc("GroupLootFrame_OpenNewFrame", function()
                LootRollUI:SyncOfficialRollBarVisibility()
            end)
        end
        if type(_G.GroupLootContainer_AddFrame) == "function" then
            hooksecurefunc("GroupLootContainer_AddFrame", function()
                LootRollUI:SyncOfficialRollBarVisibility()
            end)
        end
        if type(_G.GroupLootContainer_Update) == "function" then
            hooksecurefunc("GroupLootContainer_Update", function()
                LootRollUI:SyncOfficialRollBarVisibility()
            end)
        end
        if type(_G.GroupLootFrame_OnShow) == "function" then
            hooksecurefunc("GroupLootFrame_OnShow", function()
                LootRollUI:SyncOfficialRollBarVisibility()
            end)
        end
    end
    self:SyncOfficialRollBarVisibility()
end

-- ============================================================================
-- 4B. Epic Self-Win Celebration Splash (0ms idle CPU, 100% click-through)
-- ============================================================================
local function EaseOutCubic(t)
    local u = 1 - math.max(0, math.min(1, t))
    return 1 - (u * u * u)
end

local function EaseOutBack(t)
    local x = math.max(0, math.min(1, t)) - 1
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (x * x * x) + c1 * (x * x)
end

local function ApplyCircleMaskLoot(parent, tex)
    if not (parent and parent.CreateMaskTexture and tex and tex.AddMaskTexture) then
        return
    end
    local mask = parent:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
end

local function EnsureEpicWinFrame()
    if LootRollUI.epicWinFrame then
        return LootRollUI.epicWinFrame
    end
    local Theme = ns.Theme

    local f = CreateFrame("Frame", "SocialCentralLootEpicWinFrame", UIParent)
    f:Hide()
    f:SetSize(460, 146)
    f:SetPoint("TOP", UIParent, "TOP", 0, -138)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(572)
    f:EnableMouse(false)

    -- Behind-medallion starburst god-rays & shockwaves
    local sunburst = CreateFrame("Frame", nil, f)
    sunburst:SetSize(250, 250)
    sunburst:SetPoint("CENTER", f, "TOP", 0, -45)
    sunburst:SetFrameLevel(571)
    sunburst:EnableMouse(false)
    f.sunburst = sunburst

    local auraCore = sunburst:CreateTexture(nil, "BACKGROUND", nil, 0)
    auraCore:SetSize(166, 166)
    auraCore:SetPoint("CENTER", sunburst, "CENTER", 0, 0)
    auraCore:SetTexture(ICON_GLOW)
    auraCore:SetBlendMode("ADD")
    f.auraCore = auraCore

    local flashOrb = sunburst:CreateTexture(nil, "OVERLAY", nil, 6)
    flashOrb:SetSize(140, 140)
    flashOrb:SetPoint("CENTER", sunburst, "CENTER", 0, 0)
    flashOrb:SetTexture(ICON_GLOW)
    flashOrb:SetBlendMode("ADD")
    flashOrb:SetVertexColor(1.0, 0.96, 0.78, 0)
    f.flashOrb = flashOrb

    local shock1 = sunburst:CreateTexture(nil, "ARTWORK", nil, 2)
    shock1:SetSize(64, 64)
    shock1:SetPoint("CENTER", sunburst, "CENTER", 0, 0)
    shock1:SetTexture(ICON_GLOW)
    shock1:SetBlendMode("ADD")
    f.shock1 = shock1

    local shock2 = sunburst:CreateTexture(nil, "ARTWORK", nil, 3)
    shock2:SetSize(54, 54)
    shock2:SetPoint("CENTER", sunburst, "CENTER", 0, 0)
    shock2:SetTexture(ICON_GLOW)
    shock2:SetBlendMode("ADD")
    f.shock2 = shock2

    local rays = {}
    local rayConfigs = {
        { w = 236, h = 44, base = 0.0,           speed = 0.42,  gold = true },
        { w = 236, h = 44, base = math.pi * 0.5, speed = 0.42,  gold = true },
        { w = 198, h = 30, base = math.pi * 0.25, speed = -0.64, gold = false },
        { w = 198, h = 30, base = math.pi * 0.75, speed = -0.64, gold = false },
    }
    for i, rc in ipairs(rayConfigs) do
        local ray = sunburst:CreateTexture(nil, "ARTWORK", nil, 1)
        ray:SetSize(rc.w, rc.h)
        ray:SetPoint("CENTER", sunburst, "CENTER", 0, 0)
        ray:SetTexture(ICON_GLOW)
        ray:SetBlendMode("ADD")
        ray._baseAngle = rc.base
        ray._spinSpeed = rc.speed
        ray._isGold = rc.gold
        rays[i] = ray
    end
    f.rays = rays

    -- Clipped winged ribbon plate expanding symmetrically from center
    local ribbonClip = CreateFrame("Frame", nil, f)
    ribbonClip:SetSize(438, 72)
    ribbonClip:SetPoint("TOP", f, "TOP", 0, -64)
    ribbonClip:SetFrameLevel(575)
    ribbonClip:EnableMouse(false)
    if ribbonClip.SetClipsChildren then
        ribbonClip:SetClipsChildren(true)
    end
    f.ribbonClip = ribbonClip

    local solidBg = ribbonClip:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetAllPoints(ribbonClip)
    solidBg:SetTexture(WHITE8X8)
    solidBg:SetVertexColor(0.055, 0.050, 0.068, 1.0)
    ribbonClip._solidOpaqueBg = solidBg
    f._solidOpaqueBg = solidBg

    local bgTint = ribbonClip:CreateTexture(nil, "BACKGROUND", nil, -4)
    bgTint:SetPoint("TOPLEFT", ribbonClip, "TOPLEFT", -24, 16)
    bgTint:SetPoint("BOTTOMRIGHT", ribbonClip, "BOTTOMRIGHT", 24, -16)
    bgTint:SetTexture(ICON_GLOW)
    bgTint:SetBlendMode("ADD")
    f.bgTint = bgTint

    local topRimOuter = ribbonClip:CreateTexture(nil, "BORDER", nil, 2)
    topRimOuter:SetHeight(2)
    topRimOuter:SetPoint("TOPLEFT", ribbonClip, "TOPLEFT", 0, 0)
    topRimOuter:SetPoint("TOPRIGHT", ribbonClip, "TOPRIGHT", 0, 0)
    topRimOuter:SetTexture(WHITE8X8)
    f.topRimOuter = topRimOuter

    local topRimInner = ribbonClip:CreateTexture(nil, "BORDER", nil, 3)
    topRimInner:SetHeight(1)
    topRimInner:SetPoint("TOPLEFT", ribbonClip, "TOPLEFT", 4, -2)
    topRimInner:SetPoint("TOPRIGHT", ribbonClip, "TOPRIGHT", -4, -2)
    topRimInner:SetTexture(WHITE8X8)
    topRimInner:SetVertexColor(1.0, 0.96, 0.72, 0.72)

    local botRimOuter = ribbonClip:CreateTexture(nil, "BORDER", nil, 2)
    botRimOuter:SetHeight(2)
    botRimOuter:SetPoint("BOTTOMLEFT", ribbonClip, "BOTTOMLEFT", 0, 0)
    botRimOuter:SetPoint("BOTTOMRIGHT", ribbonClip, "BOTTOMRIGHT", 0, 0)
    botRimOuter:SetTexture(WHITE8X8)
    f.botRimOuter = botRimOuter

    local botRimInner = ribbonClip:CreateTexture(nil, "BORDER", nil, 3)
    botRimInner:SetHeight(1)
    botRimInner:SetPoint("BOTTOMLEFT", ribbonClip, "BOTTOMLEFT", 4, 2)
    botRimInner:SetPoint("BOTTOMRIGHT", ribbonClip, "BOTTOMRIGHT", -4, 2)
    botRimInner:SetTexture(WHITE8X8)
    botRimInner:SetVertexColor(1.0, 0.92, 0.56, 0.55)

    local capL = ribbonClip:CreateTexture(nil, "BORDER", nil, 4)
    capL:SetWidth(4)
    capL:SetPoint("TOPLEFT", ribbonClip, "TOPLEFT", 0, 0)
    capL:SetPoint("BOTTOMLEFT", ribbonClip, "BOTTOMLEFT", 0, 0)
    capL:SetTexture(WHITE8X8)
    f.capL = capL

    local capR = ribbonClip:CreateTexture(nil, "BORDER", nil, 4)
    capR:SetWidth(4)
    capR:SetPoint("TOPRIGHT", ribbonClip, "TOPRIGHT", 0, 0)
    capR:SetPoint("BOTTOMRIGHT", ribbonClip, "BOTTOMRIGHT", 0, 0)
    capR:SetTexture(WHITE8X8)
    f.capR = capR

    local wingGlowL = f:CreateTexture(nil, "ARTWORK", nil, 3)
    wingGlowL:SetSize(44, 92)
    wingGlowL:SetPoint("CENTER", ribbonClip, "LEFT", 0, 0)
    wingGlowL:SetTexture(ICON_GLOW)
    wingGlowL:SetBlendMode("ADD")
    f.wingGlowL = wingGlowL

    local wingGlowR = f:CreateTexture(nil, "ARTWORK", nil, 3)
    wingGlowR:SetSize(44, 92)
    wingGlowR:SetPoint("CENTER", ribbonClip, "RIGHT", 0, 0)
    wingGlowR:SetTexture(ICON_GLOW)
    wingGlowR:SetBlendMode("ADD")
    f.wingGlowR = wingGlowR

    local shimmerL = ribbonClip:CreateTexture(nil, "ARTWORK", nil, 5)
    shimmerL:SetSize(96, 86)
    shimmerL:SetTexture(ICON_GLOW)
    shimmerL:SetBlendMode("ADD")
    shimmerL:SetVertexColor(1.0, 0.92, 0.45, 0.65)
    shimmerL:Hide()
    f.shimmerL = shimmerL

    local shimmerR = ribbonClip:CreateTexture(nil, "ARTWORK", nil, 5)
    shimmerR:SetSize(96, 86)
    shimmerR:SetTexture(ICON_GLOW)
    shimmerR:SetBlendMode("ADD")
    shimmerR:SetVertexColor(1.0, 0.92, 0.45, 0.65)
    shimmerR:Hide()
    f.shimmerR = shimmerR

    -- Fixed-width text container inside ribbonClip so text never re-wraps while unfurling
    local textAnchor = CreateFrame("Frame", nil, ribbonClip)
    textAnchor:SetSize(416, 56)
    textAnchor:SetPoint("TOP", f, "TOP", 0, -76)
    textAnchor:EnableMouse(false)

    local kickerFs = textAnchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    kickerFs:SetPoint("TOP", textAnchor, "TOP", 0, 0)
    kickerFs:SetWidth(410)
    kickerFs:SetJustifyH("CENTER")
    kickerFs:SetWordWrap(false)
    f.kickerFs = kickerFs

    local itemFs = textAnchor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    itemFs:SetPoint("TOP", kickerFs, "BOTTOM", 0, -3)
    itemFs:SetWidth(410)
    itemFs:SetJustifyH("CENTER")
    itemFs:SetWordWrap(false)
    f.itemFs = itemFs

    local subFs = textAnchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subFs:SetPoint("TOP", itemFs, "BOTTOM", 0, -3)
    subFs:SetWidth(410)
    subFs:SetJustifyH("CENTER")
    subFs:SetWordWrap(false)
    f.subFs = subFs

    -- Heroic Item Medallion & Bouncing Royal Crown
    local medFrame = CreateFrame("Frame", nil, f)
    medFrame:SetSize(58, 58)
    medFrame:SetPoint("TOP", f, "TOP", 0, -16)
    medFrame:SetFrameLevel(578)
    medFrame:EnableMouse(false)
    f.medFrame = medFrame

    local medRingBg = medFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    medRingBg:SetSize(56, 56)
    medRingBg:SetPoint("CENTER", medFrame, "CENTER", 0, 0)
    medRingBg:SetTexture(WHITE8X8)
    ApplyCircleMaskLoot(medFrame, medRingBg)
    f.medRingBg = medRingBg

    local medDarkBg = medFrame:CreateTexture(nil, "ARTWORK", nil, 0)
    medDarkBg:SetSize(50, 50)
    medDarkBg:SetPoint("CENTER", medFrame, "CENTER", 0, 0)
    medDarkBg:SetTexture(WHITE8X8)
    medDarkBg:SetVertexColor(0.06, 0.05, 0.08, 1.0)
    ApplyCircleMaskLoot(medFrame, medDarkBg)

    local medIcon = medFrame:CreateTexture(nil, "ARTWORK", nil, 2)
    medIcon:SetSize(46, 46)
    medIcon:SetPoint("CENTER", medFrame, "CENTER", 0, 0)
    medIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ApplyCircleMaskLoot(medFrame, medIcon)
    f.medIcon = medIcon

    local medOrnate = medFrame:CreateTexture(nil, "OVERLAY", nil, 4)
    medOrnate:SetPoint("CENTER", medFrame, "CENTER", 0, 0)
    if Theme and Theme.HasAtlas and Theme:HasAtlas("Artifacts-PerkRing-Final") then
        medOrnate:SetSize(78, 78)
        medOrnate:SetAtlas("Artifacts-PerkRing-Final", false)
        medOrnate:SetVertexColor(1.0, 0.88, 0.42, 0.96)
    elseif Theme and Theme.HasAtlas and Theme:HasAtlas("common-ring-gold") then
        medOrnate:SetSize(72, 72)
        medOrnate:SetAtlas("common-ring-gold", false)
        medOrnate:SetVertexColor(1.0, 0.90, 0.46, 0.96)
    else
        medOrnate:SetSize(58, 58)
        medOrnate:SetTexture(ICON_GLOW)
        medOrnate:SetBlendMode("ADD")
        medOrnate:SetVertexColor(1.0, 0.85, 0.30, 0.45)
    end
    f.medOrnate = medOrnate

    local medFlash = medFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    medFlash:SetSize(56, 56)
    medFlash:SetPoint("CENTER", medFrame, "CENTER", 0, 0)
    medFlash:SetTexture(ICON_GLOW)
    medFlash:SetBlendMode("ADD")
    ApplyCircleMaskLoot(medFrame, medFlash)
    medFlash:SetVertexColor(1.0, 0.98, 0.82, 0)
    f.medFlash = medFlash

    local crownTex = f:CreateTexture(nil, "OVERLAY", nil, 7)
    crownTex:SetSize(30, 30)
    crownTex:SetPoint("BOTTOM", medFrame, "TOP", 0, -6)
    crownTex:SetTexture(CHOICE_ICONS.WON)
    f.crownTex = crownTex

    -- 14 Pre-allocated Celebration Spark Motes (0 allocations per tick)
    local sparkLayer = CreateFrame("Frame", nil, f)
    sparkLayer:SetAllPoints(f)
    sparkLayer:SetFrameLevel(580)
    sparkLayer:EnableMouse(false)

    local sparks = {}
    for i = 1, 14 do
        local isDiamond = (i % 2 == 0)
        local sp = sparkLayer:CreateTexture(nil, "OVERLAY", nil, 5)
        if isDiamond then
            sp:SetTexture(WHITE8X8)
            sp:SetRotation(math.pi * 0.25)
        else
            sp:SetTexture(ICON_GLOW)
        end
        sp:SetBlendMode("ADD")
        sp._isDiamond = isDiamond
        sp._ang = ((i - 1) / 14) * (math.pi * 2) + ((i % 3) * 0.14)
        sp._speed = 74 + ((i * 23) % 86)
        sp._baseSz = isDiamond and (5 + (i % 4)) or (10 + (i % 6))
        sp._freq = 9 + ((i * 3) % 7)
        sp._phase = i * 0.85
        sp._delay = (i % 4) * 0.035
        sp._life = 1.45 + ((i % 5) * 0.18)
        sp._ox = math.cos(sp._ang) * 14
        sp._oy = math.sin(sp._ang) * 10
        sp:Hide()
        sparks[i] = sp
    end
    f.sparks = sparks

    local function FinishCurrentEpicWin()
        f:SetScript("OnUpdate", nil)
        f:Hide()
        if #LootRollUI.epicWinQueue > 0 then
            local nextRec = table.remove(LootRollUI.epicWinQueue, 1)
            LootRollUI:ShowEpicWinRec(nextRec)
        end
    end

    f:SetScript("OnHide", function(selfF)
        selfF:SetScript("OnUpdate", nil)
    end)

    local function OnEpicWinUpdate(selfF, elapsed)
        local dt = elapsed or 0
        selfF._tickAccum = (selfF._tickAccum or 0) + dt
        if selfF._tickAccum < 0.033 then
            return
        end
        local step = math.min(0.06, selfF._tickAccum)
        selfF._tickAccum = 0

        LootRollUI.epicWinElapsed = (LootRollUI.epicWinElapsed or 0) + step
        local t = LootRollUI.epicWinElapsed
        local totalDur = LootRollUI.epicWinDur or 3.85
        if t >= totalDur then
            FinishCurrentEpicWin()
            return
        end

        local qr = selfF._qr or 1.0
        local qg = selfF._qg or 0.84
        local qb = selfF._qb or 0.22

        -- Whole celebration fade-in / drift fade-out at end
        local fadeOutStart = totalDur - 0.55
        local masterAlpha = 1.0
        local driftY = 0
        if t < 0.08 then
            masterAlpha = t / 0.08
        elseif t > fadeOutStart then
            local fProg = (t - fadeOutStart) / 0.55
            masterAlpha = math.max(0, 1 - fProg)
            driftY = math.floor((EaseOutCubic(fProg) * 10) + 0.5)
        end
        selfF:SetAlpha(masterAlpha)
        if selfF._lastDriftY ~= driftY then
            selfF._lastDriftY = driftY
            selfF:ClearAllPoints()
            selfF:SetPoint("TOP", UIParent, "TOP", 0, -138 + driftY)
        end

        -- 1. Medallion spring-overshoot pop (0.00 -> 0.34s)
        local medScale = 1.0
        if t < 0.34 then
            local p = t / 0.34
            medScale = 0.24 + 0.76 * EaseOutBack(p)
        end
        medFrame:SetScale(math.max(0.20, math.min(1.35, medScale)))

        -- 2. Crown triumphant drop & bounce (0.12 -> 0.44s)
        local crownY = -6
        local crownA = 1.0
        if t < 0.12 then
            crownA = 0
            crownY = 24
        elseif t < 0.44 then
            local cp = (t - 0.12) / 0.32
            crownA = math.min(1, cp * 2.5)
            crownY = -6 + (1 - EaseOutBack(cp)) * 28
        else
            crownY = -6 + math.sin((t - 0.44) * 3.8) * 1.5
        end
        local qCrownY = math.floor(crownY * 4 + 0.5) * 0.25
        if selfF._lastCrownY ~= qCrownY then
            selfF._lastCrownY = qCrownY
            crownTex:ClearAllPoints()
            crownTex:SetPoint("BOTTOM", medFrame, "TOP", 0, qCrownY)
        end
        crownTex:SetAlpha(crownA)

        -- 3. Center-out ribbon unfurl (0.06 -> 0.38s)
        local ribW = 438
        if t < 0.06 then
            ribW = 68
        elseif t < 0.38 then
            local rp = (t - 0.06) / 0.32
            ribW = math.floor(68 + 370 * EaseOutCubic(rp) + 0.5)
        end
        if selfF._lastRibW ~= ribW then
            selfF._lastRibW = ribW
            ribbonClip:SetWidth(ribW)
        end

        -- 4. Flash orb & twin expanding shockwaves
        if t < 0.22 then
            local fp = t / 0.22
            local fSz = math.floor(36 + 116 * EaseOutCubic(fp) + 0.5)
            flashOrb:SetSize(fSz, fSz)
            flashOrb:SetVertexColor(1.0, 0.96, 0.80, math.max(0, (1 - fp) * 0.92))
            if not selfF._flashVis then
                selfF._flashVis = true
                flashOrb:Show()
            end
            medFlash:SetAlpha(math.max(0, (1 - fp) * 0.85))
        elseif selfF._flashVis ~= false then
            selfF._flashVis = false
            flashOrb:Hide()
            medFlash:SetAlpha(0)
        end

        if t < 0.72 then
            local sp1 = t / 0.72
            local s1 = math.floor(48 + 204 * EaseOutCubic(sp1) + 0.5)
            local a1 = math.max(0, (1 - sp1) * (1 - sp1) * 0.88)
            shock1:SetSize(s1, s1)
            shock1:SetVertexColor(1.0, 0.86, 0.32, a1)
            if not selfF._shock1Vis then
                selfF._shock1Vis = true
                shock1:Show()
            end
        elseif selfF._shock1Vis ~= false then
            selfF._shock1Vis = false
            shock1:Hide()
        end

        if t >= 0.08 and t < 0.84 then
            local sp2 = (t - 0.08) / 0.76
            local s2 = math.floor(42 + 188 * EaseOutCubic(sp2) + 0.5)
            local a2 = math.max(0, (1 - sp2) * (1 - sp2) * 0.80)
            shock2:SetSize(s2, s2)
            shock2:SetVertexColor(qr, qg, qb, a2)
            if not selfF._shock2Vis then
                selfF._shock2Vis = true
                shock2:Show()
            end
        elseif selfF._shock2Vis ~= false then
            selfF._shock2Vis = false
            shock2:Hide()
        end

        -- 5. Counter-rotating god rays & breathing aura
        local auraPulse = 0.5 + 0.5 * math.sin(t * 5.2)
        auraCore:SetVertexColor(1.0 * 0.45 + qr * 0.55, 0.84 * 0.45 + qg * 0.55, 0.22 * 0.45 + qb * 0.55, 0.34 + 0.24 * auraPulse)
        for i = 1, #rays do
            local rTex = rays[i]
            rTex:SetRotation((rTex._baseAngle or 0) + t * (rTex._spinSpeed or 0.4))
            local rayFadeIn = math.min(1, t / 0.22)
            if rTex._isGold then
                rTex:SetVertexColor(1.0, 0.86, 0.36, (0.32 + 0.16 * auraPulse) * rayFadeIn)
            else
                rTex:SetVertexColor(qr, qg, qb, (0.28 + 0.14 * auraPulse) * rayFadeIn)
            end
        end

        -- Wing glow pulse
        local wingAlpha = (0.36 + 0.24 * auraPulse) * math.min(1, math.max(0, (t - 0.14) / 0.24))
        wingGlowL:SetVertexColor(1.0 * 0.5 + qr * 0.5, 0.84 * 0.5 + qg * 0.5, 0.24 * 0.5 + qb * 0.5, wingAlpha)
        wingGlowR:SetVertexColor(1.0 * 0.5 + qr * 0.5, 0.84 * 0.5 + qg * 0.5, 0.24 * 0.5 + qb * 0.5, wingAlpha)

        -- 6. Dual outward shimmer sweeps across ribbon (wave 1 at 0.28..1.05, wave 2 at 1.55..2.32)
        local waveP = nil
        if t >= 0.28 and t <= 1.05 then
            waveP = (t - 0.28) / 0.77
        elseif t >= 1.55 and t <= 2.32 then
            waveP = (t - 1.55) / 0.77
        end
        if waveP then
            local off = math.floor((waveP * 240) + 0.5)
            local sAlpha = math.sin(waveP * math.pi) * 0.72
            shimmerL:ClearAllPoints()
            shimmerL:SetPoint("CENTER", ribbonClip, "CENTER", -off, 0)
            shimmerL:SetAlpha(sAlpha)
            shimmerR:ClearAllPoints()
            shimmerR:SetPoint("CENTER", ribbonClip, "CENTER", off, 0)
            shimmerR:SetAlpha(sAlpha)
            if not selfF._shimmerVis then
                selfF._shimmerVis = true
                shimmerL:Show()
                shimmerR:Show()
            end
        elseif selfF._shimmerVis ~= false then
            selfF._shimmerVis = false
            shimmerL:Hide()
            shimmerR:Hide()
        end

        -- 7. Radial celebration sparks burst & twinkle
        for i = 1, #sparks do
            local sp = sparks[i]
            local st = t - (sp._delay or 0)
            if st >= 0 and st < (sp._life or 1.6) then
                local lp = st / (sp._life or 1.6)
                local inv = 1 - math.min(1, lp * 1.15)
                local dist = (sp._speed or 90) * (1 - (inv * inv)) * 1.25
                local px = math.floor(((sp._ox or 0) + math.cos(sp._ang) * dist) + 0.5)
                local py = math.floor((-45 + (sp._oy or 0) + math.sin(sp._ang) * dist + (18 * st) - (48 * st * st)) + 0.5)
                local tw = 0.55 + 0.45 * math.sin(st * (sp._freq or 10) + (sp._phase or 0))
                local sAlpha = math.min(1, st / 0.08) * math.max(0, 1 - (lp * lp)) * tw
                local curSz = math.max(3, math.floor(((sp._baseSz or 8) * (0.7 + 0.4 * tw) * (1 - 0.25 * lp)) + 0.5))
                if sp._lastSz ~= curSz then
                    sp._lastSz = curSz
                    sp:SetSize(curSz, curSz)
                end
                if sp._lastPx ~= px or sp._lastPy ~= py then
                    sp._lastPx = px
                    sp._lastPy = py
                    sp:ClearAllPoints()
                    sp:SetPoint("CENTER", sparkLayer, "TOP", px, py)
                end
                if sp._isDiamond then
                    sp:SetVertexColor(math.min(1, qr + 0.3), math.min(1, qg + 0.3), math.min(1, qb + 0.3), sAlpha)
                else
                    sp:SetVertexColor(1.0, 0.86, 0.34, sAlpha)
                end
                if not sp._vis then
                    sp._vis = true
                    sp:Show()
                end
            elseif sp._vis ~= false then
                sp._vis = false
                sp:Hide()
            end
        end
    end

    f.OnEpicWinUpdate = OnEpicWinUpdate
    LootRollUI.epicWinFrame = f
    return f
end

function LootRollUI:ShowEpicWinRec(rec)
    if not rec then return end
    local f = EnsureEpicWinFrame()
    if not f then return end

    local q = tonumber(rec.quality) or 1
    local qr, qg, qb = QualityRGB(q)
    if q <= 1 then
        qr, qg, qb = 1.0, 0.84, 0.22
    end
    f._qr, f._qg, f._qb = qr, qg, qb

    -- Harmonize border & rarity aura while maintaining 100% opaque interior backing
    f.bgTint:SetVertexColor(qr, qg, qb, 0.22)
    f.topRimOuter:SetVertexColor(1.0 * 0.4 + qr * 0.6, 0.84 * 0.4 + qg * 0.6, 0.22 * 0.4 + qb * 0.6, 1.0)
    f.botRimOuter:SetVertexColor(1.0 * 0.4 + qr * 0.6, 0.84 * 0.4 + qg * 0.6, 0.22 * 0.4 + qb * 0.6, 1.0)
    f.capL:SetVertexColor(1.0, 0.86, 0.30, 1.0)
    f.capR:SetVertexColor(1.0, 0.86, 0.30, 1.0)
    f.medRingBg:SetVertexColor(qr, qg, qb, 1.0)
    f.medIcon:SetTexture(rec.texture or ICON_DICE)

    local cKey = rec.winnerChoice or rec.myChoice or "WON"
    local cLbl = (ns.LootRoll and ns.LootRoll.GetRollChoiceLabel) and ns.LootRoll:GetRollChoiceLabel(cKey) or L["Won"]
    local rollVal = rec.winnerRoll or rec.myRoll
    local rollTag = rollVal and (" [" .. tostring(rollVal) .. "]") or ""
    f.kickerFs:SetText(FormatChoiceIconTag("WON", 13) .. "  |cffffea70" .. L["YOU WON!"] .. "|r  ·  " .. FormatChoiceIconTag(cKey, 12) .. " |cffd6e2f0" .. cLbl .. rollTag .. "|r")

    local qtyTxt = (rec.count and rec.count > 1) and (" |cffffffffx" .. tostring(rec.count) .. "|r") or ""
    f.itemFs:SetText(QualityHex(q) .. tostring(rec.name or "?") .. "|r" .. qtyTxt)

    local subParts = {}
    if rec.zone and rec.zone ~= "" then
        subParts[#subParts + 1] = rec.zone
    end
    local totalRolls = 0
    for _ in pairs(rec.choices or {}) do
        totalRolls = totalRolls + 1
    end
    if totalRolls > 1 then
        subParts[#subParts + 1] = string.format(L["Won against %d players"], totalRolls - 1)
    elseif rec.bindOnPickUp then
        subParts[#subParts + 1] = L["BoP"]
    end
    f.subFs:SetText("|cffb6c4d6" .. table.concat(subParts, "  ·  ") .. "|r")

    self.epicWinElapsed = 0
    self.epicWinDur = (#self.epicWinQueue > 0) and 2.95 or 3.85
    f._tickAccum = 0.04
    f._lastDriftY = nil
    f._lastCrownY = nil
    f._lastRibW = nil
    f._flashVis = nil
    f._shock1Vis = nil
    f._shock2Vis = nil
    f._shimmerVis = nil
    for i = 1, #f.sparks do
        local sp = f.sparks[i]
        sp._vis = nil
        sp._lastSz = nil
        sp._lastPx = nil
        sp._lastPy = nil
    end
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, -138)
    f.OnEpicWinUpdate(f, 0)
    f:SetScript("OnUpdate", f.OnEpicWinUpdate)
    f:Show()
    if f.Raise then f:Raise() end
end

function LootRollUI:QueueEpicWinAnimation(rec)
    if not rec then return end
    local hid = rec.historyId or rec.id or rec.rollID
    if self.epicWinFrame and self.epicWinFrame:IsShown() then
        for _, queued in ipairs(self.epicWinQueue) do
            local qid = queued.historyId or queued.id or queued.rollID
            if hid and qid == hid then
                return
            end
        end
        table.insert(self.epicWinQueue, rec)
        -- Shorten active timer smoothly when another win awaits in queue
        self.epicWinDur = math.min(self.epicWinDur or 3.85, math.max(2.6, (self.epicWinElapsed or 0) + 0.9))
        return
    end
    self:ShowEpicWinRec(rec)
end

-- ============================================================================
-- 5. Fixed Floating Roll Results Shortcut Button
-- ============================================================================
function LootRollUI:ShouldShowResultsButton()
    local s = ns.db and ns.db.settings
    local mode = (s and s.lootRollResultsButtonMode) or "when_enabled"
    if mode == "hidden" then
        return false
    end
    if mode == "always" then
        return true
    end
    if s and s.lootRollAutoHideWithQuickBar == true and s.quickBarEnabled ~= false then
        local qbIds = (ns.QuickBar and ns.QuickBar.GetSelectedIdsCached and ns.QuickBar:GetSelectedIdsCached()) or nil
        if type(qbIds) == "table" then
            for _, qid in ipairs(qbIds) do
                if qid == "loot_rolls" then
                    return false
                end
            end
        end
    end
    if Compat and Compat.IsModuleEnabled and Compat.IsModuleEnabled("group") == false then
        return false
    end
    if ns.LootRoll and ns.LootRoll.GetActiveCount and ns.LootRoll:GetActiveCount() > 0 then
        return true
    end
    if ns.LootRoll and ns.LootRoll.IsInsideDungeonOrRaid and ns.LootRoll:IsInsideDungeonOrRaid() then
        return true
    end
    if ns.LootRoll and ns.LootRoll.GetPostRunRemainingSec and ns.LootRoll:GetPostRunRemainingSec() > 0 then
        return true
    end
    return false
end

function LootRollUI:ToggleResultsButtonVisibility()
    if not (ns.db and ns.db.settings) then return end
    local cur = ns.db.settings.lootRollResultsButtonMode or "when_enabled"
    if cur == "hidden" then
        ns.db.settings.lootRollResultsButtonMode = "always"
        ns:Print("%s", L["Fixed Roll Results button enabled."])
    else
        ns.db.settings.lootRollResultsButtonMode = "hidden"
        ns:Print("%s", L["Fixed Roll Results button hidden (use /sc rolls or Minimap menu anytime)."])
    end
    ns:Emit("SETTINGS_UPDATED")
    self:SyncResultsButton()
end

function LootRollUI:EnsureResultsButton()
    if self.resultsBtnFrame then
        return self.resultsBtnFrame
    end
    local Theme = ns.Theme
    if not Theme then return nil end

    local btn = CreateFrame("Button", "SocialCentralLootRollResultsButton", UIParent, "BackdropTemplate")
    btn:Hide()
    btn:SetSize(34, 34)
    ApplyDefaultResultsButtonPlacement(btn)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(48)
    btn:SetClampedToScreen(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local sBg = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    sBg:SetAllPoints(btn)
    sBg:SetTexture(WHITE8X8)
    sBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    btn._solidOpaqueBg = sBg

    local ico = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    ico:SetSize(26, 26)
    ico:SetPoint("CENTER", btn, "CENTER", 0, 0)
    ico:SetTexture(ICON_DICE)
    btn.ico = ico

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn)
    hl:SetColorTexture(1.0, 0.88, 0.36, 0.16)

    if Theme.CreateCounterBadge then
        local badge = Theme:CreateCounterBadge(btn, {
            height = 20,
            maxNum = 99,
            haloAlpha = 0.45,
            minFontSize = 14,
            maxFontSize = 16,
            fontScaleOffset = -1,
        })
        badge:SetPoint("CENTER", btn, "TOPRIGHT", -2, -2)
        badge:SetFrameLevel((btn:GetFrameLevel() or 48) + 8)
        btn.badge = badge
    end

    btn._scLocked = (ns.db and ns.db.settings and ns.db.settings.lootRollResultsButtonLock == true) and true or false
    Theme:MakeMovable(btn, {
        key = "loot_roll_results_btn",
        handles = { btn },
        combatLock = false,
        onReset = ApplyDefaultResultsButtonPlacement,
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
    btn:HookScript("OnDragStart", function(selfBtn)
        if selfBtn.ico then
            selfBtn.ico:SetPoint("CENTER", selfBtn, "CENTER", 0, 0)
        end
    end)
    btn:HookScript("OnHide", function(selfBtn)
        if selfBtn.ico then
            selfBtn.ico:SetPoint("CENTER", selfBtn, "CENTER", 0, 0)
        end
    end)

    btn:SetScript("OnClick", function(selfBtn, mouseBtn)
        if selfBtn._scJustDraggedAt and GetTime and (GetTime() - selfBtn._scJustDraggedAt) < 0.25 then
            return
        end
        if mouseBtn == "RightButton" then
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                    root:CreateTitle(L["Group Loot Roll"])
                    root:CreateButton(L["Open Roll Results"], function()
                        LootRollUI:OpenResultsWindow()
                    end)
                    local active = ns.LootRoll and ns.LootRoll.GetActiveList and ns.LootRoll:GetActiveList() or {}
                    if #active > 0 then
                        root:CreateButton(L["Show Active Roll Card"], function()
                            LootRollUI:ShowActiveRollCard()
                        end)
                    end
                    root:CreateDivider()
                    root:CreateCheckbox(L["Lock button position"], function()
                        return ns.db and ns.db.settings and ns.db.settings.lootRollResultsButtonLock == true
                    end, function()
                        local nextVal = not (ns.db and ns.db.settings and ns.db.settings.lootRollResultsButtonLock == true)
                        if ns.db and ns.db.settings then ns.db.settings.lootRollResultsButtonLock = nextVal end
                        if SocialCentralDB and SocialCentralDB.settings then SocialCentralDB.settings.lootRollResultsButtonLock = nextVal end
                        btn._scLocked = nextVal
                        ns:Emit("SETTINGS_UPDATED")
                    end)
                    local visSub = root:CreateButton(L["Button Visibility"])
                    if visSub and visSub.CreateRadio then
                        for _, opt in ipairs({
                            { id = "when_enabled", label = L["During dungeon/raid (+3 min after)"] },
                            { id = "always", label = L["Always visible"] },
                            { id = "hidden", label = L["Hide button"] },
                        }) do
                            local modeId = opt.id
                            visSub:CreateRadio(opt.label, function()
                                return ((ns.db and ns.db.settings and ns.db.settings.lootRollResultsButtonMode) or "when_enabled") == modeId
                            end, function()
                                if ns.db and ns.db.settings then ns.db.settings.lootRollResultsButtonMode = modeId end
                                if SocialCentralDB and SocialCentralDB.settings then SocialCentralDB.settings.lootRollResultsButtonMode = modeId end
                                ns:Emit("SETTINGS_UPDATED")
                                LootRollUI:SyncResultsButton()
                            end)
                        end
                    end
                    root:CreateButton(L["Reset Position"], function()
                        if Theme and Theme.ResetWindowPosition then
                            Theme:ResetWindowPosition("loot_roll_results_btn")
                        end
                    end)
                    root:CreateButton(L["Open Settings"], function()
                        if ns.Settings and ns.Settings.Open then
                            ns.Settings:Open("general", "lootroll")
                        end
                    end)
                    root:CreateDivider()
                    root:CreateButton(L["Clear Roll History"], function()
                        LootRollUI:ConfirmClearHistory()
                    end)
                end)
            else
                LootRollUI:OpenResultsWindow()
            end
            return
        end
        if IsShiftKeyDown and IsShiftKeyDown() then
            local active = ns.LootRoll and ns.LootRoll.GetActiveList and ns.LootRoll:GetActiveList() or {}
            if #active > 0 then
                LootRollUI:ShowActiveRollCard()
                return
            end
        end
        LootRollUI:ToggleResultsWindow()
    end)

    btn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cffffd24dSocialCentral|r — " .. L["Loot Roll Results"], 1, 1, 1)
        local runSum = (ns.LootRoll and ns.LootRoll.GetLatestRunSummary) and ns.LootRoll:GetLatestRunSummary() or nil
        if runSum and (runSum.total or 0) > 0 then
            GameTooltip:AddLine(
                string.format(L["Last Group: %s (%d drops · %d won)"], tostring(runSum.zone or L["Group"]), runSum.total or 0, runSum.won or 0),
                0.85, 0.90, 0.96
            )
        else
            GameTooltip:AddLine(L["Shows your latest dungeon, raid, or group loot summary."], 0.85, 0.90, 0.96, true)
        end
        if ns.LootRoll and ns.LootRoll.GetPostRunRemainingSec then
            local remSec = ns.LootRoll:GetPostRunRemainingSec()
            if remSec > 0 then
                local mins = math.floor(remSec / 60)
                local secs = remSec % 60
                GameTooltip:AddLine(string.format(L["Auto-hides in %dm %02ds after run end"], mins, secs), 0.65, 0.78, 0.92)
            end
        end
        if ns.LootRoll and ns.LootRoll.GetResultsList then
            local recent = ns.LootRoll:GetResultsList({ scope = "latest_run" })
            if #recent > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Latest Results:"], 1.0, 0.85, 0.28)
                for i = 1, math.min(3, #recent) do
                    local r = recent[i]
                    local iName = QualityHex(r.quality or 1) .. tostring(r.name or "?") .. "|r"
                    local wStr
                    if r.allPassed then
                        wStr = "|cff8b949e" .. L["All passed"] .. "|r"
                    elseif r.winnerName then
                        local wHex = (r.winnerClass and Compat and Compat.ClassHex and Compat.ClassHex(r.winnerClass)) or "|cffe6edf3"
                        local rVal = r.winnerRoll and (" [" .. tostring(r.winnerRoll) .. "]") or ""
                        wStr = wHex .. tostring(r.winnerName) .. "|r" .. rVal
                    else
                        wStr = "|cffffd24d" .. L["Rolling..."] .. "|r"
                    end
                    GameTooltip:AddDoubleLine(iName, wStr, 1, 1, 1, 1, 1, 1)
                end
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Left-click: Open Last Group Summary\nShift+Click: Show Active Roll Card\nRight-click: Options & Visibility\nDrag: Move button"], 0.65, 0.76, 0.88, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(selfBtn)
        if selfBtn and selfBtn.ico then
            selfBtn.ico:SetPoint("CENTER", selfBtn, "CENTER", 0, 0)
        end
        if GameTooltip then GameTooltip:Hide() end
    end)

    self.resultsBtnFrame = btn
    return btn
end

function LootRollUI:SyncResultsButton()
    local shouldShow = self:ShouldShowResultsButton()
    if not shouldShow then
        if self.resultsBtnFrame and self.resultsBtnFrame:IsShown() then
            self.resultsBtnFrame:Hide()
        end
        return
    end
    local btn = self:EnsureResultsButton()
    if not btn then return end
    local Theme = ns.Theme
    local p = Theme and Theme.GetPalette and Theme:GetPalette()
    local palKey = (p and p.key) or "default"
    if btn._lastResultsPalKey ~= palKey then
        btn._lastResultsPalKey = palKey
        if Theme and Theme.ApplyBackdrop then
            Theme:ApplyBackdrop(btn, "surface", p)
        end
        ApplySolidOpaqueBg(btn, p)
    end
    btn._scLocked = (ns.db and ns.db.settings and ns.db.settings.lootRollResultsButtonLock == true) and true or false

    if btn._lastRestoredPos ~= true then
        btn._lastRestoredPos = true
        if Theme and Theme.HasSavedWindowPosition and Theme:HasSavedWindowPosition("loot_roll_results_btn") then
            Theme:RestoreWindowPosition(btn, "loot_roll_results_btn", false, { allowLockedRestore = true })
        else
            ApplyDefaultResultsButtonPlacement(btn)
        end
    end

    local active = 0
    if ns.LootRoll and ns.LootRoll.GetActiveCount then
        active = ns.LootRoll:GetActiveCount() or 0
    end
    local hasUnvoted = (active > 0 and ns.LootRoll and ns.LootRoll.HasUnvotedActiveRoll and ns.LootRoll:HasUnvotedActiveRoll()) == true
    local unread = (ns.LootRoll and ns.LootRoll.GetUnreadCount and ns.LootRoll:GetUnreadCount()) or 0

    local badgeSig = tostring(active) .. ":" .. (hasUnvoted and "1" or "0") .. ":" .. tostring(unread)
    if btn.badge and btn.badge.SetCount and btn._lastBadgeSig ~= badgeSig then
        btn._lastBadgeSig = badgeSig
        if active > 0 then
            btn.badge:SetCount(active, hasUnvoted and "whisper" or "guild")
        elseif unread > 0 then
            btn.badge:SetCount(unread, "bnet")
        else
            btn.badge:SetCount(0)
        end
    end
    if btn.SetBackdropBorderColor then
        local borderState = palKey .. ":" .. (hasUnvoted and "U" or (active > 0 and "A" or (unread > 0 and "R" or "I")))
        if btn._lastBorderState ~= borderState then
            btn._lastBorderState = borderState
            if hasUnvoted then
                btn:SetBackdropBorderColor(1.0, 0.82, 0.25, 1.0)
            elseif active > 0 then
                btn:SetBackdropBorderColor(0.32, 0.92, 0.48, 1.0)
            elseif unread > 0 then
                btn:SetBackdropBorderColor(0.36, 0.72, 1.0, 1.0)
            else
                local bc = (p and (p.windowBorder or p.surfaceBorder or p.btnBorder)) or { 0.30, 0.32, 0.38, 1.0 }
                btn:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1.0)
            end
        end
    end
    if not btn:IsShown() then
        btn:Show()
    end
end

-- ============================================================================
-- 6. Epic Loot Roll Results & History Window
-- ============================================================================
function LootRollUI:ConfirmClearHistory()
    local isChatRollTab = (self.resultsSubTab == "chatroll")
    local count = 0
    if isChatRollTab then
        count = ns.LootRoll and ns.LootRoll.chatRollSessions and #ns.LootRoll.chatRollSessions or 0
    else
        count = ns.LootRoll and select(1, ns.LootRoll:GetResultsStats()) or 0
    end
    if count <= 0 then return end
    local function DoClear()
        if isChatRollTab then
            if ns.LootRoll and ns.LootRoll.ClearChatRollSessions then
                ns.LootRoll:ClearChatRollSessions()
            end
        else
            if ns.LootRoll and ns.LootRoll.ClearHistory then
                ns.LootRoll:ClearHistory()
            end
        end
        LootRollUI:RefreshResultsWindow()
        LootRollUI:SyncResultsButton()
    end
    if ns.UI and ns.UI.OpenConfirmModal then
        ns.UI:OpenConfirmModal({
            title = L["Clear Roll History"],
            message = isChatRollTab
                and string.format(L["Are you sure you want to clear all %d recorded Group /roll rounds?"], count)
                or string.format(L["Are you sure you want to clear all %d recorded Loot Roll results?"], count),
            confirmText = L["Clear"],
            confirmVariant = "danger",
            onConfirm = DoClear,
        })
    else
        DoClear()
    end
end

local function OpenDropRowContextMenu(anchor, rec)
    if not (anchor and rec and MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle(tostring(rec.name or L["Group Loot Roll"]))
        if ns.LootRoll and ns.LootRoll.FormatWinnerAnnouncementText then
            root:CreateButton(L["Announce Winner"], function()
                InsertSummaryIntoChat(ns.LootRoll:FormatWinnerAnnouncementText(rec))
            end)
        end
        if ns.LootRoll and ns.LootRoll.FormatRollSummaryText then
            root:CreateButton(L["Link in Chat"], function()
                InsertSummaryIntoChat(ns.LootRoll:FormatRollSummaryText(rec))
            end)
            root:CreateButton(L["Copy Results"], function()
                if ns.UI and ns.UI.OpenCopyModal then
                    ns.UI:OpenCopyModal(ns.LootRoll:FormatRollSummaryText(rec), L["Loot Roll Summary"], L["Press Ctrl+C to copy this loot roll breakdown."])
                end
            end)
        end
        if rec.winnerName and rec.winnerName ~= "" and not rec.wonByMe then
            root:CreateDivider()
            root:CreateButton(L["Whisper Winner"], function()
                if ns.Chat and ns.Chat.OpenPreferredConversation then
                    ns.Chat:OpenPreferredConversation({ targetName = rec.winnerName })
                elseif Compat and Compat.Whisper then
                    Compat.Whisper(rec.winnerName)
                end
            end)
            if rec.itemLink or rec.link then
                root:CreateButton(L["Ask about item (/w)"], function()
                    local draft = string.format(L["Hey %s, do you need %s?"], rec.winnerName, rec.itemLink or rec.link)
                    if ns.Chat and ns.Chat.OpenPreferredConversation then
                        ns.Chat:OpenPreferredConversation({ targetName = rec.winnerName, draftText = draft })
                    elseif Compat and Compat.Whisper then
                        Compat.Whisper(rec.winnerName, draft)
                    end
                end)
            end
        end
        root:CreateDivider()
        root:CreateButton(L["Delete Entry"], function()
            local function DoDel()
                if ns.LootRoll and ns.LootRoll.DeleteResult then
                    ns.LootRoll:DeleteResult(rec.id)
                end
                LootRollUI:RefreshResultsWindow()
                LootRollUI:SyncResultsButton()
            end
            if ns.UI and ns.UI.OpenConfirmModal then
                ns.UI:OpenConfirmModal({
                    title = L["Delete Entry"],
                    message = string.format(L["Delete saved roll result for %s?"], tostring(rec.name or "?")),
                    confirmText = L["Remove"],
                    confirmVariant = "danger",
                    onConfirm = DoDel,
                })
            else
                DoDel()
            end
        end)
    end)
end

local function CreateDropItemRow(rowParent, _, rowHeight)
    local row = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
    row:SetHeight(rowHeight)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.94, 0.78, 0.07)

    local selBg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    selBg:SetAllPoints()
    selBg:SetTexture(WHITE8X8)
    selBg:SetVertexColor(0.24, 0.42, 0.68, 0.25)
    selBg:Hide()
    row.selBg = selBg

    local stripe = row:CreateTexture(nil, "ARTWORK", nil, 1)
    stripe:SetWidth(3)
    stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -4)
    stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 4)
    stripe:SetTexture(WHITE8X8)
    row.stripe = stripe

    local icoFrame = CreateFrame("Frame", nil, row)
    icoFrame:SetSize(30, 30)
    icoFrame:SetPoint("LEFT", row, "LEFT", 9, 0)
    local icoBorder = icoFrame:CreateTexture(nil, "BACKGROUND")
    icoBorder:SetAllPoints()
    icoBorder:SetTexture(WHITE8X8)
    icoFrame.border = icoBorder
    local icoTex = icoFrame:CreateTexture(nil, "ARTWORK")
    icoTex:SetPoint("TOPLEFT", 2, -2)
    icoTex:SetPoint("BOTTOMRIGHT", -2, 2)
    icoTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icoFrame.tex = icoTex
    row.icoFrame = icoFrame

    local timeFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeFs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -7)
    timeFs:SetJustifyH("RIGHT")
    timeFs:SetWordWrap(false)
    row.timeFs = timeFs

    local titleFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleFs:SetPoint("TOPLEFT", icoFrame, "TOPRIGHT", 7, -1)
    titleFs:SetPoint("RIGHT", timeFs, "LEFT", -6, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetWordWrap(false)
    row.titleFs = titleFs

    local subFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subFs:SetPoint("BOTTOMLEFT", icoFrame, "BOTTOMRIGHT", 7, 1)
    subFs:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    subFs:SetJustifyH("LEFT")
    subFs:SetWordWrap(false)
    row.subFs = subFs

    row:SetScript("OnClick", function(selfRow, btn)
        local rec = selfRow._rec
        if not rec then return end
        if btn == "RightButton" then
            LootRollUI:SelectResultRow(rec)
            OpenDropRowContextMenu(selfRow, rec)
            return
        end
        if (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) then
            HandleItemIconClick(selfRow, rec.itemLink or rec.link, btn)
            return
        end
        LootRollUI:SelectResultRow(rec)
    end)
    row:SetScript("OnEnter", function(selfRow)
        local rec = selfRow._rec
        if rec then
            ShowItemHoverTooltip(selfRow, rec.itemLink or rec.link, true)
        end
    end)
    row:SetScript("OnLeave", HideItemHoverTooltip)
    return row
end

local function UpdateDropItemRow(row, rec, _, pal)
    row._rec = rec
    row._itemName = rec.name
    local isSel = (LootRollUI.selectedResultId == rec.id)
    if pal and pal.rowSelectedBg then
        row.selBg:SetVertexColor(pal.rowSelectedBg[1], pal.rowSelectedBg[2], pal.rowSelectedBg[3], pal.rowSelectedBg[4] or 0.30)
    end
    row.selBg:SetShown(isSel)

    local qr, qg, qb = QualityRGB(rec.quality or 1)
    row.icoFrame.border:SetVertexColor(qr, qg, qb, 0.95)
    row.icoFrame.tex:SetTexture(rec.texture or "Interface\\Icons\\INV_Misc_QuestionMark")

    if rec.wonByMe then
        row.stripe:SetVertexColor(1.0, 0.84, 0.22, 1.0)
    elseif rec._isActive and not rec.resolved then
        row.stripe:SetVertexColor(0.28, 0.90, 0.48, 1.0)
    else
        row.stripe:SetVertexColor(qr, qg, qb, 0.85)
    end

    local qty = (rec.count and rec.count > 1) and (" x" .. tostring(rec.count)) or ""
    local mlTag = rec.isMasterLoot and (" |cffff9b3d[" .. L["ML"] .. "]|r") or ""
    local simTag = rec.isSimulated and (" |cff9da7b5[" .. L["Test"] .. "]|r") or ""
    row.titleFs:SetText(QualityHex(rec.quality or 1) .. tostring(rec.name or "?") .. "|r" .. qty .. mlTag .. simTag)

    local whenStr = rec.ts and Compat and Compat.FormatRelativeTime and Compat.FormatRelativeTime(rec.ts, L) or ""
    row.timeFs:SetText(whenStr)
    if pal and pal.textMuted then
        row.timeFs:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])
    end

    local subTxt
    if rec._isActive and not rec.resolved then
        subTxt = "|cff47ef66" .. L["Rolling now..."] .. "|r"
    elseif rec.allPassed then
        subTxt = FormatChoiceIconTag("PASS", 12) .. " |cff8b949e" .. L["All passed"] .. "|r"
    elseif rec.winnerName then
        local wHex = (rec.winnerClass and Compat and Compat.ClassHex and Compat.ClassHex(rec.winnerClass)) or "|cffe6edf3"
        local cIco = FormatChoiceIconTag(rec.winnerChoice or "WON", 12)
        local rPart = rec.winnerRoll and (" [" .. tostring(rec.winnerRoll) .. "]") or ""
        local youBadge = rec.wonByMe and (" |cffffea70(" .. L["You"] .. ")|r") or ""
        local bossSuffix = (rec.bossName and rec.bossName ~= "") and (" · |cff8b949e" .. rec.bossName .. "|r") or ""
        subTxt = FormatChoiceIconTag("WON", 12) .. " " .. wHex .. tostring(rec.winnerName) .. "|r" .. youBadge .. " · " .. cIco .. rPart .. bossSuffix
    else
        subTxt = "|cff9da7b5" .. L["No winner recorded"] .. "|r"
    end
    row.subFs:SetText(subTxt)
end

local function CreateRollerBreakdownRow(rowParent, _, rowHeight)
    local row = CreateFrame("Button", nil, rowParent)
    row:SetHeight(rowHeight)
    row:RegisterForClicks("RightButtonUp")

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.94, 0.78, 0.06)

    local winBg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    winBg:SetAllPoints()
    winBg:SetTexture(WHITE8X8)
    winBg:SetVertexColor(1.0, 0.80, 0.20, 0.16)
    winBg:Hide()
    row.winBg = winBg

    local rankFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rankFs:SetPoint("LEFT", row, "LEFT", 6, 0)
    rankFs:SetWidth(22)
    rankFs:SetJustifyH("LEFT")
    row.rankFs = rankFs

    local voteIco = row:CreateTexture(nil, "ARTWORK")
    voteIco:SetSize(14, 14)
    voteIco:SetPoint("LEFT", rankFs, "RIGHT", 2, 0)
    row.voteIco = voteIco

    local winIco = row:CreateTexture(nil, "ARTWORK", nil, 2)
    winIco:SetSize(13, 13)
    winIco:SetPoint("LEFT", voteIco, "RIGHT", 3, 0)
    winIco:SetTexture(ICON_TROPHY)
    winIco:Hide()
    row.winIco = winIco

    local rollFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rollFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    rollFs:SetJustifyH("RIGHT")
    rollFs:SetWordWrap(false)
    row.rollFs = rollFs

    local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFs:SetPoint("LEFT", voteIco, "RIGHT", 6, 0)
    nameFs:SetPoint("RIGHT", rollFs, "LEFT", -8, 0)
    nameFs:SetJustifyH("LEFT")
    nameFs:SetWordWrap(false)
    row.nameFs = nameFs

    row:SetScript("OnClick", function(selfRow, mBtn)
        if mBtn == "RightButton" and selfRow._playerName then
            OpenPlayerQuickRollMenu(selfRow, selfRow._playerName, LootRollUI._activeDetailLink, selfRow._isMe == true)
        end
    end)

    return row
end

local function UpdateRollerBreakdownRow(row, item, idx)
    local isWon = (item.w == true or item.won == true)
    row.winBg:SetShown(isWon)
    row.rankFs:SetText("|cff8b949e#" .. tostring(idx) .. "|r")

    local chKey = item.ch or item.choice or "PASS"
    row.voteIco:SetTexture(GetChoiceIconTexture(chKey) or ICON_PASS)
    row.voteIco:SetAlpha((chKey == "PASS") and 0.70 or 1.0)

    row.nameFs:ClearAllPoints()
    if isWon then
        row.winIco:Show()
        row.nameFs:SetPoint("LEFT", row.winIco, "RIGHT", 4, 0)
    else
        row.winIco:Hide()
        row.nameFs:SetPoint("LEFT", row.voteIco, "RIGHT", 6, 0)
    end
    row.nameFs:SetPoint("RIGHT", row.rollFs, "LEFT", -8, 0)

    local pName = tostring(item.n or item.name or "?")
    local cls = item.c or item.classFile
    local isMe = (item.me == true or item.isMe == true)
    row._playerName = pName
    row._isMe = isMe
    local cHex = isWon and "|cffffea70"
        or ((chKey == "PASS") and "|cff8b949e" or ((cls and Compat and Compat.ClassHex and Compat.ClassHex(cls)) or "|cffe6edf3"))
    local meSuffix = isMe and (" |cff8cc2ff(" .. L["You"] .. ")|r") or ""
    row.nameFs:SetText(cHex .. pName .. "|r" .. meSuffix)

    local cLbl = (ns.LootRoll and ns.LootRoll.GetRollChoiceLabel) and ns.LootRoll:GetRollChoiceLabel(chKey) or chKey
    local cCol = (ns.LootRoll and ns.LootRoll.GetChoiceColor) and ns.LootRoll:GetChoiceColor(chKey) or "|cffd0d7de"
    local rNum = item.r or item.roll
    if isWon and rNum then
        row.rollFs:SetText("|cffffea70" .. cLbl .. " · " .. tostring(rNum) .. "|r")
    elseif isWon then
        row.rollFs:SetText("|cffffea70" .. L["Won"] .. "|r")
    elseif rNum then
        row.rollFs:SetText(cCol .. cLbl .. " · " .. tostring(rNum) .. "|r")
    else
        row.rollFs:SetText(cCol .. cLbl .. "|r")
    end
end

local function OpenChatRollSessionMenu(anchor, sess)
    if not (anchor and sess and MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle(tostring(sess.itemName or L["Group /roll Round"]))
        if ns.LootRoll and ns.LootRoll.FormatChatRollOpenDraft then
            root:CreateButton(L["Open Roll"], function()
                InsertSummaryIntoChat(ns.LootRoll:FormatChatRollOpenDraft(sess))
            end)
        end
        if sess.isTied and ns.LootRoll and ns.LootRoll.StartTieBreakerRound then
            root:CreateButton(L["Start Tie-Breaker"], function()
                local tb = ns.LootRoll:StartTieBreakerRound(sess.id)
                if tb then
                    LootRollUI.selectedChatRollId = tb.id
                    LootRollUI:RefreshResultsWindow()
                end
                if ns.LootRoll.FormatChatRollTieBreakerDraft then
                    InsertSummaryIntoChat(ns.LootRoll:FormatChatRollTieBreakerDraft(sess))
                end
            end)
        end
        if ns.LootRoll and ns.LootRoll.FormatChatRollWinnerDraft then
            root:CreateButton(L["Announce Winner"], function()
                InsertSummaryIntoChat(ns.LootRoll:FormatChatRollWinnerDraft(sess))
            end)
        end
        if ns.LootRoll and ns.LootRoll.FormatChatRollSummaryText then
            root:CreateButton(L["Copy Results"], function()
                if ns.UI and ns.UI.OpenCopyModal then
                    ns.UI:OpenCopyModal(ns.LootRoll:FormatChatRollSummaryText(sess), L["Group /roll Summary"], L["Press Ctrl+C to copy this /roll summary."])
                end
            end)
        end
        root:CreateDivider()
        root:CreateButton(L["Delete Round"], function()
            local function DoDel()
                if ns.LootRoll and ns.LootRoll.DeleteChatRollSession then
                    ns.LootRoll:DeleteChatRollSession(sess.id)
                end
                LootRollUI:RefreshResultsWindow()
            end
            if ns.UI and ns.UI.OpenConfirmModal then
                ns.UI:OpenConfirmModal({
                    title = L["Delete Round"],
                    message = string.format(L["Delete /roll round for %s?"], tostring(sess.itemName or L["Group /roll Round"])),
                    confirmText = L["Remove"],
                    confirmVariant = "danger",
                    onConfirm = DoDel,
                })
            else
                DoDel()
            end
        end)
    end)
end

local function CreateChatRollSessionRow(rowParent, _, rowHeight)
    local row = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
    row:SetHeight(rowHeight)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.94, 0.78, 0.07)

    local selBg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    selBg:SetAllPoints()
    selBg:SetTexture(WHITE8X8)
    selBg:SetVertexColor(0.24, 0.42, 0.68, 0.25)
    selBg:Hide()
    row.selBg = selBg

    local stripe = row:CreateTexture(nil, "ARTWORK", nil, 1)
    stripe:SetWidth(3)
    stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -4)
    stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 4)
    stripe:SetTexture(WHITE8X8)
    row.stripe = stripe

    local ico = row:CreateTexture(nil, "ARTWORK")
    ico:SetSize(26, 26)
    ico:SetPoint("LEFT", row, "LEFT", 9, 0)
    ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.ico = ico

    local timeFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeFs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -7)
    timeFs:SetJustifyH("RIGHT")
    row.timeFs = timeFs

    local titleFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleFs:SetPoint("TOPLEFT", ico, "TOPRIGHT", 7, 0)
    titleFs:SetPoint("RIGHT", timeFs, "LEFT", -6, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetWordWrap(false)
    row.titleFs = titleFs

    local subFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subFs:SetPoint("BOTTOMLEFT", ico, "BOTTOMRIGHT", 7, 1)
    subFs:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    subFs:SetJustifyH("LEFT")
    subFs:SetWordWrap(false)
    row.subFs = subFs

    row:SetScript("OnClick", function(selfRow, btn)
        if not selfRow._sess then return end
        if btn == "RightButton" then
            LootRollUI:SelectChatRollRow(selfRow._sess)
            OpenChatRollSessionMenu(selfRow, selfRow._sess)
            return
        end
        if (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) then
            if selfRow._sess.itemLink then
                HandleItemIconClick(selfRow, selfRow._sess.itemLink, btn)
                return
            end
        end
        LootRollUI:SelectChatRollRow(selfRow._sess)
    end)
    row:SetScript("OnEnter", function(selfRow)
        if selfRow._sess and selfRow._sess.itemLink then
            ShowItemHoverTooltip(selfRow, selfRow._sess.itemLink, true)
        end
    end)
    row:SetScript("OnLeave", HideItemHoverTooltip)
    return row
end

local function UpdateChatRollSessionRow(row, sess, _, pal)
    row._sess = sess
    row._itemName = sess.itemName
    if pal and pal.rowSelectedBg then
        row.selBg:SetVertexColor(pal.rowSelectedBg[1], pal.rowSelectedBg[2], pal.rowSelectedBg[3], pal.rowSelectedBg[4] or 0.30)
    end
    row.selBg:SetShown(LootRollUI.selectedChatRollId == sess.id)
    local isLive = (not sess.closed) and ((time() - (sess.lastRollAt or sess.ts or 0)) <= 45)
    local qr, qg, qb = QualityRGB(sess.itemQuality or 1)
    if sess.isTied then
        row.stripe:SetVertexColor(1.0, 0.62, 0.22, 1.0)
    elseif isLive then
        row.stripe:SetVertexColor(0.28, 0.90, 0.48, 1.0)
    else
        row.stripe:SetVertexColor(qr, qg, qb, 0.90)
    end
    row.ico:SetTexture(sess.itemTexture or ICON_DICE)

    local liveDot = isLive and "|cff47ef66• |r" or ""
    local titleTxt = liveDot .. (sess.itemName
        and (QualityHex(sess.itemQuality or 1) .. sess.itemName .. "|r")
        or ("|cffffd24d" .. L["Group /roll Round"] .. "|r"))
    if sess.isTieBreaker then
        titleTxt = titleTxt .. " |cff58b8ff[" .. L["Tie-Breaker"] .. "]|r"
    end
    if sess.isTied then
        titleTxt = titleTxt .. " |cffff9b3d[" .. L["TIE"] .. "]|r"
    end
    if (sess.anomalyCount or 0) > 0 or (sess.dupCount or 0) > 0 then
        titleTxt = titleTxt .. " |cffff5555[!]|r"
    end
    if sess.isSimulated then
        titleTxt = titleTxt .. " |cff9da7b5[" .. L["Test"] .. "]|r"
    end
    row.titleFs:SetText(titleTxt)

    local whenStr = sess.ts and Compat and Compat.FormatRelativeTime and Compat.FormatRelativeTime(sess.ts, L) or ""
    row.timeFs:SetText(whenStr)
    if pal and pal.textMuted then
        row.timeFs:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3])
    end

    local nRolls = #(sess.rolls or {})
    if sess.leaderName and sess.leaderRoll then
        local wHex = (sess.leaderClass and Compat and Compat.ClassHex and Compat.ClassHex(sess.leaderClass)) or "|cffe6edf3"
        row.subFs:SetText(string.format("%s %s (%d) · %d %s", FormatChoiceIconTag("WON", 12), wHex .. sess.leaderName .. "|r", sess.leaderRoll, nRolls, L["rolls"]))
    elseif sess.osLeaderName and sess.osLeaderRoll then
        local wHex = (sess.osLeaderClass and Compat and Compat.ClassHex and Compat.ClassHex(sess.osLeaderClass)) or "|cffe6edf3"
        row.subFs:SetText(string.format("|cff58b8ffOS|r %s (%d) · %d %s", wHex .. sess.osLeaderName .. "|r", sess.osLeaderRoll, nRolls, L["rolls"]))
    elseif isLive and nRolls == 0 then
        row.subFs:SetText("|cff47ef66" .. L["Waiting for /roll..."] .. "|r")
    else
        row.subFs:SetText(string.format("%d %s", nRolls, L["rolls"]))
    end
end

local function CreateChatRollEntryRow(rowParent, _, rowHeight)
    local row = CreateFrame("Button", nil, rowParent)
    row:SetHeight(rowHeight)
    row:RegisterForClicks("RightButtonUp")

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.94, 0.78, 0.06)

    local winBg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    winBg:SetAllPoints()
    winBg:SetTexture(WHITE8X8)
    winBg:SetVertexColor(1.0, 0.80, 0.20, 0.14)
    winBg:Hide()
    row.winBg = winBg

    local rankFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rankFs:SetPoint("LEFT", row, "LEFT", 6, 0)
    rankFs:SetWidth(24)
    row.rankFs = rankFs

    local rollFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rollFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    rollFs:SetJustifyH("RIGHT")
    row.rollFs = rollFs

    local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFs:SetPoint("LEFT", rankFs, "RIGHT", 4, 0)
    nameFs:SetPoint("RIGHT", rollFs, "LEFT", -8, 0)
    nameFs:SetJustifyH("LEFT")
    nameFs:SetWordWrap(false)
    row.nameFs = nameFs

    row:SetScript("OnClick", function(selfRow, mBtn)
        if mBtn == "RightButton" and selfRow._playerName then
            OpenPlayerQuickRollMenu(selfRow, selfRow._playerName, LootRollUI._activeChatRollLink, selfRow._isMe == true)
        end
    end)

    return row
end

local function UpdateChatRollEntryRow(row, item, idx)
    local selSess = LootRollUI._activeChatRollSess
    local isValidMS = (item.bracket == "MS" or (item.bracket == nil and item.isStandard100)) and not item.isDuplicate and not item.isNotInvitedTie
    local isTop = isValidMS and selSess and selSess.leaderRoll and (item.roll == selSess.leaderRoll)
    local isOsTop = (not isTop) and (item.bracket == "OS") and not item.isDuplicate and not item.isNotInvitedTie and selSess and (not selSess.leaderRoll) and selSess.osLeaderRoll and (item.roll == selSess.osLeaderRoll)
    row.winBg:SetShown((isTop or isOsTop) == true)
    if isTop and selSess and selSess.isTied then
        row.winBg:SetVertexColor(1.0, 0.62, 0.20, 0.18)
    elseif isOsTop then
        row.winBg:SetVertexColor(0.32, 0.70, 1.0, 0.15)
    else
        row.winBg:SetVertexColor(1.0, 0.80, 0.20, 0.15)
    end
    row.rankFs:SetText("|cff8b949e#" .. tostring(idx) .. "|r")

    row._playerName = tostring(item.name or "?")
    row._isMe = (item.isMe == true)

    local cHex = (item.classFile and Compat and Compat.ClassHex and Compat.ClassHex(item.classFile)) or "|cffe6edf3"
    local warn = ""
    if item.isNotInvitedTie then
        warn = " |cffff5555[" .. L["Not in tie-breaker"] .. "]|r"
    elseif item.bracket == "OS" then
        warn = string.format(" |cff58b8ff[OS 1-%d]|r", item.maxVal or 50)
    elseif not item.isStandard100 then
        warn = string.format(" |cffff6b6b(%d-%d!)|r", item.minVal or 1, item.maxVal or 100)
    end
    if item.isDuplicate then
        warn = warn .. " |cffff9b3d[" .. L["Duplicate roll"] .. "]|r"
    elseif isTop and selSess and selSess.isTied then
        warn = warn .. " |cffff9b3d[" .. L["TIE"] .. "]|r"
    end
    local meTag = item.isMe and (" |cff8cc2ff(" .. L["You"] .. ")|r") or ""
    row.nameFs:SetText(cHex .. tostring(item.name or "?") .. "|r" .. meTag .. warn)

    if isTop then
        row.rollFs:SetText("|cffffea70" .. tostring(item.roll or 0) .. "|r")
    elseif isOsTop then
        row.rollFs:SetText("|cff58b8ff" .. tostring(item.roll or 0) .. "|r")
    elseif item.isDuplicate or item.isNotInvitedTie or (not item.isStandard100 and item.bracket ~= "OS") then
        row.rollFs:SetText("|cff8b949e" .. tostring(item.roll or 0) .. "|r")
    else
        row.rollFs:SetText("|cffe6edf3" .. tostring(item.roll or 0) .. "|r")
    end
end

local function BuildDropsPane(parent)
    local Theme = ns.Theme
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()

    local topBar = CreateFrame("Frame", nil, pane)
    topBar:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    topBar:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 0)
    topBar:SetHeight(52)

    local searchBox = Theme:CreateEditBox(topBar, {
        width = 216,
        height = 22,
        clearButton = true,
        placeholder = L["Search item, boss, player or zone..."],
    })
    searchBox:SetPoint("TOPLEFT", topBar, "TOPLEFT", 2, -2)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:HookScript("OnTextChanged", function(selfBox)
        LootRollUI._resSearchTok = (LootRollUI._resSearchTok or 0) + 1
        local tok = LootRollUI._resSearchTok
        LootRollUI.resultsSearch = selfBox:GetText() or ""
        if C_Timer and C_Timer.After then
            C_Timer.After(0.10, function()
                if LootRollUI._resSearchTok == tok then
                    LootRollUI:RefreshResultsWindow()
                end
            end)
        else
            LootRollUI:RefreshResultsWindow()
        end
    end)
    pane.searchBox = searchBox

    local clearBtn = Theme:CreateButton(topBar, 70, 22, L["Clear"], "default")
    Theme:AutoFitButton(clearBtn, 60, 14, 100)
    clearBtn:SetPoint("TOPRIGHT", topBar, "TOPRIGHT", -2, -2)
    clearBtn:SetScript("OnClick", function()
        LootRollUI:ConfirmClearHistory()
    end)
    pane.clearBtn = clearBtn

    local sortBtn = Theme:CreateButton(topBar, 110, 22, L["Sort: Newest"], "default")
    Theme:AutoFitButton(sortBtn, 96, 14, 152)
    sortBtn:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)
    sortBtn:SetScript("OnClick", function(selfBtn)
        local opts = {
            { id = "newest", label = L["Sort: Newest"] },
            { id = "quality", label = L["Sort: Rarity"] },
            { id = "roll", label = L["Sort: Highest Roll"] },
            { id = "winner", label = L["Sort: Winner"] },
        }
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                root:CreateTitle(L["Sort Drops By"])
                for _, o in ipairs(opts) do
                    local oid = o.id
                    root:CreateRadio(o.label, function()
                        return (LootRollUI.resultsSortBy or "newest") == oid
                    end, function()
                        LootRollUI.resultsSortBy = oid
                        LootRollUI:RefreshResultsWindow()
                    end)
                end
            end)
        else
            local cur = LootRollUI.resultsSortBy or "newest"
            for i, o in ipairs(opts) do
                if o.id == cur then
                    LootRollUI.resultsSortBy = opts[(i % #opts) + 1].id
                    break
                end
            end
            LootRollUI:RefreshResultsWindow()
        end
    end)
    pane.sortBtn = sortBtn

    local qualBtn = Theme:CreateButton(topBar, 92, 22, L["Rarity: All"], "default")
    Theme:AutoFitButton(qualBtn, 82, 14, 134)
    qualBtn:SetPoint("RIGHT", sortBtn, "LEFT", -6, 0)
    qualBtn:SetScript("OnClick", function(selfBtn)
        local opts = {
            { min = 0, label = L["Rarity: All"] },
            { min = 2, label = L["Rarity: Uncommon+"] },
            { min = 3, label = L["Rarity: Rare+"] },
            { min = 4, label = L["Rarity: Epic+"] },
        }
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(selfBtn, function(_, root)
                root:CreateTitle(L["Minimum Item Rarity"])
                for _, o in ipairs(opts) do
                    local mv = o.min
                    root:CreateRadio(o.label, function()
                        return (LootRollUI.resultsQualityMin or 0) == mv
                    end, function()
                        LootRollUI.resultsQualityMin = mv
                        LootRollUI:RefreshResultsWindow()
                    end)
                end
            end)
        else
            local cur = LootRollUI.resultsQualityMin or 0
            for i, o in ipairs(opts) do
                if o.min == cur then
                    LootRollUI.resultsQualityMin = opts[(i % #opts) + 1].min
                    break
                end
            end
            LootRollUI:RefreshResultsWindow()
        end
    end)
    pane.qualBtn = qualBtn

    local filterDefs = {
        { id = "ALL", label = L["All"] },
        { id = "WON_ME", label = L["Won by Me"] },
        { id = "MY_ROLLS", label = L["My Rolls"] },
        { id = "ACTIVE", label = L["Active"] },
        { id = "THIS_CHAR", label = L["This Character"] },
    }
    pane.filterBtns = {}
    local prevF = nil
    for _, fd in ipairs(filterDefs) do
        local fb = Theme:CreateButton(topBar, 64, 20, fd.label, "default")
        fb._filterId = fd.id
        Theme:AutoFitButton(fb, 48, 14, 130)
        if prevF then
            fb:SetPoint("LEFT", prevF, "RIGHT", 4, 0)
        else
            fb:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -6)
        end
        fb:SetScript("OnClick", function()
            LootRollUI.resultsFilter = fd.id
            LootRollUI:RefreshResultsWindow()
        end)
        pane.filterBtns[#pane.filterBtns + 1] = fb
        prevF = fb
    end

    local leftList = Theme:CreateScrollList(pane, 46, CreateDropItemRow, UpdateDropItemRow)
    leftList.container:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -4)
    leftList.container:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 0)
    leftList.container:SetWidth(298)
    pane.leftList = leftList

    local detail = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    detail:SetPoint("TOPLEFT", leftList.container, "TOPRIGHT", 8, 0)
    detail:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
    pane.detail = detail

    local hero = CreateFrame("Frame", nil, detail, "BackdropTemplate")
    hero:SetPoint("TOPLEFT", detail, "TOPLEFT", 8, -8)
    hero:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -8, -8)
    hero:SetHeight(58)
    pane.hero = hero

    local dIco = CreateFrame("Button", nil, hero)
    dIco:SetSize(38, 38)
    dIco:SetPoint("LEFT", hero, "LEFT", 8, 0)
    local dBorder = dIco:CreateTexture(nil, "BACKGROUND")
    dBorder:SetAllPoints()
    dBorder:SetTexture(WHITE8X8)
    dIco._border = dBorder
    local dTex = dIco:CreateTexture(nil, "ARTWORK")
    dTex:SetPoint("TOPLEFT", 2, -2)
    dTex:SetPoint("BOTTOMRIGHT", -2, 2)
    dTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dIco._tex = dTex
    dIco:SetScript("OnEnter", function(selfBtn)
        ShowItemHoverTooltip(selfBtn, selfBtn._itemLink, true)
    end)
    dIco:SetScript("OnLeave", HideItemHoverTooltip)
    dIco:SetScript("OnClick", function(selfBtn, btn)
        HandleItemIconClick(selfBtn, selfBtn._itemLink, btn)
    end)
    pane.dIco = dIco

    local dTitle = hero:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dTitle:SetPoint("TOPLEFT", dIco, "TOPRIGHT", 9, -2)
    dTitle:SetPoint("RIGHT", hero, "RIGHT", -8, 0)
    dTitle:SetJustifyH("LEFT")
    dTitle:SetWordWrap(false)
    pane.dTitle = dTitle

    local dMeta = hero:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dMeta:SetPoint("BOTTOMLEFT", dIco, "BOTTOMRIGHT", 9, 2)
    dMeta:SetPoint("RIGHT", hero, "RIGHT", -8, 0)
    dMeta:SetJustifyH("LEFT")
    dMeta:SetWordWrap(false)
    pane.dMeta = dMeta

    local winBox = CreateFrame("Frame", nil, detail, "BackdropTemplate")
    winBox:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -6)
    winBox:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", 0, -6)
    winBox:SetHeight(42)
    pane.winBox = winBox

    local winMain = winBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    winMain:SetPoint("TOPLEFT", winBox, "TOPLEFT", 8, -6)
    winMain:SetPoint("TOPRIGHT", winBox, "TOPRIGHT", -8, -6)
    winMain:SetJustifyH("LEFT")
    winMain:SetWordWrap(false)
    pane.winMain = winMain

    local winSub = winBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    winSub:SetPoint("BOTTOMLEFT", winBox, "BOTTOMLEFT", 8, 6)
    winSub:SetPoint("BOTTOMRIGHT", winBox, "BOTTOMRIGHT", -8, 6)
    winSub:SetJustifyH("LEFT")
    winSub:SetWordWrap(false)
    pane.winSub = winSub

    local actBar = CreateFrame("Frame", nil, detail)
    actBar:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 8, 8)
    actBar:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -8, 8)
    actBar:SetHeight(24)

    local announceBtn = Theme:CreateButton(actBar, 118, 22, L["Announce Winner"], "primary")
    Theme:AutoFitButton(announceBtn, 102, 16, 154)
    announceBtn:SetPoint("LEFT", actBar, "LEFT", 0, 0)
    announceBtn:SetScript("OnClick", function()
        if pane._selectedRec and ns.LootRoll and ns.LootRoll.FormatWinnerAnnouncementText then
            InsertSummaryIntoChat(ns.LootRoll:FormatWinnerAnnouncementText(pane._selectedRec))
        end
    end)
    pane.announceBtn = announceBtn

    local chatBtn = Theme:CreateButton(actBar, 96, 22, L["Link in Chat"], "default")
    Theme:AutoFitButton(chatBtn, 84, 16, 134)
    chatBtn:SetPoint("LEFT", announceBtn, "RIGHT", 6, 0)
    chatBtn:SetScript("OnClick", function()
        if pane._selectedRec and ns.LootRoll then
            InsertSummaryIntoChat(ns.LootRoll:FormatRollSummaryText(pane._selectedRec))
        end
    end)
    pane.chatBtn = chatBtn

    local copyBtn = Theme:CreateButton(actBar, 96, 22, L["Copy Results"], "default")
    AttachLeadingButtonIcon(copyBtn, ICON_COPY, 15)
    Theme:SetButtonText(copyBtn, L["Copy Results"])
    Theme:AutoFitButton(copyBtn, 86, 30, 140)
    copyBtn:SetPoint("LEFT", chatBtn, "RIGHT", 6, 0)
    copyBtn:HookScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["Copy Results"], 1, 0.85, 0.25)
        GameTooltip:AddLine(L["Open a copyable summary of this loot roll."], 0.88, 0.92, 0.96, true)
        GameTooltip:Show()
    end)
    copyBtn:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    copyBtn:SetScript("OnClick", function()
        if pane._selectedRec and ns.LootRoll and ns.UI and ns.UI.OpenCopyModal then
            local txt = ns.LootRoll:FormatRollSummaryText(pane._selectedRec)
            ns.UI:OpenCopyModal(txt, L["Loot Roll Summary"], L["Press Ctrl+C to copy this loot roll breakdown."])
        end
    end)
    pane.copyBtn = copyBtn

    local delBtn = Theme:CreateButton(actBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(delBtn, 24, 22, ICON_PASS, {
        size = 16,
        color = { 1.0, 0.45, 0.45 },
        title = L["Delete Entry"],
        desc = L["Remove this roll record from saved history."],
    })
    delBtn:SetPoint("RIGHT", actBar, "RIGHT", 0, 0)
    delBtn:SetScript("OnClick", function()
        local rec = pane._selectedRec
        if not rec then return end
        local function DoDel()
            if ns.LootRoll and ns.LootRoll.DeleteResult then
                ns.LootRoll:DeleteResult(rec.id)
            end
            LootRollUI:RefreshResultsWindow()
            LootRollUI:SyncResultsButton()
        end
        if ns.UI and ns.UI.OpenConfirmModal then
            ns.UI:OpenConfirmModal({
                title = L["Delete Entry"],
                message = string.format(L["Delete saved roll result for %s?"], tostring(rec.name or "?")),
                confirmText = L["Remove"],
                confirmVariant = "danger",
                onConfirm = DoDel,
            })
        else
            DoDel()
        end
    end)
    pane.delBtn = delBtn

    local rollsList = Theme:CreateScrollList(detail, 24, CreateRollerBreakdownRow, UpdateRollerBreakdownRow)
    rollsList.container:SetPoint("TOPLEFT", winBox, "BOTTOMLEFT", 0, -6)
    rollsList.container:SetPoint("BOTTOMRIGHT", actBar, "TOPRIGHT", 0, 6)
    pane.rollsList = rollsList

    return pane
end

local function BuildChatRollsPane(parent)
    local Theme = ns.Theme
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()
    pane:Hide()

    local topBar = CreateFrame("Frame", nil, pane)
    topBar:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    topBar:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 0)
    topBar:SetHeight(28)

    local searchBox = Theme:CreateEditBox(topBar, {
        width = 190,
        height = 22,
        clearButton = true,
        placeholder = L["Search item or roller..."],
    })
    searchBox:SetPoint("TOPLEFT", topBar, "TOPLEFT", 2, -2)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:HookScript("OnTextChanged", function(selfBox)
        LootRollUI._crSearchTok = (LootRollUI._crSearchTok or 0) + 1
        local tok = LootRollUI._crSearchTok
        LootRollUI.chatRollSearch = selfBox:GetText() or ""
        if C_Timer and C_Timer.After then
            C_Timer.After(0.10, function()
                if LootRollUI._crSearchTok == tok then
                    LootRollUI:RefreshResultsWindow()
                end
            end)
        else
            LootRollUI:RefreshResultsWindow()
        end
    end)
    pane.searchBox = searchBox

    local clearBtn = Theme:CreateButton(topBar, 68, 22, L["Clear"], "default")
    Theme:AutoFitButton(clearBtn, 58, 14, 96)
    clearBtn:SetPoint("TOPRIGHT", topBar, "TOPRIGHT", -2, -2)
    clearBtn:SetScript("OnClick", function()
        LootRollUI:ConfirmClearHistory()
    end)
    pane.clearBtn = clearBtn

    local newRoundBtn = Theme:CreateButton(topBar, 128, 22, L["New /roll Round"], "primary")
    Theme:AutoFitButton(newRoundBtn, 110, 16, 166)
    newRoundBtn:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)
    newRoundBtn:SetScript("OnClick", function()
        if ns.LootRoll and ns.LootRoll.StartNewChatRollRound then
            local newSess = ns.LootRoll:StartNewChatRollRound()
            if newSess then
                LootRollUI.selectedChatRollId = newSess.id
            end
        end
        LootRollUI:RefreshResultsWindow()
        ns:Print("%s", L["Started a fresh Group /roll tracking round."])
    end)
    pane.newRoundBtn = newRoundBtn

    local roll100Btn = Theme:CreateButton(topBar, 102, 22, L["Roll 1-100"], "default")
    AttachLeadingButtonIcon(roll100Btn, ICON_DICE, 15)
    Theme:SetButtonText(roll100Btn, L["Roll 1-100"])
    Theme:AutoFitButton(roll100Btn, 92, 30, 136)
    roll100Btn:SetPoint("RIGHT", newRoundBtn, "LEFT", -6, 0)
    roll100Btn:SetScript("OnClick", function()
        if _G.RandomRoll then
            pcall(_G.RandomRoll, 1, 100)
        end
    end)
    roll100Btn:HookScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["Roll 1-100"], 1, 0.85, 0.25)
        GameTooltip:AddLine(L["Executes /roll 1-100 immediately so your roll joins the active round."], 0.88, 0.92, 0.96, true)
        GameTooltip:Show()
    end)
    roll100Btn:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    pane.roll100Btn = roll100Btn

    local leftList = Theme:CreateScrollList(pane, 44, CreateChatRollSessionRow, UpdateChatRollSessionRow)
    leftList.container:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -4)
    leftList.container:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 0)
    leftList.container:SetWidth(286)
    pane.leftList = leftList

    local detail = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    detail:SetPoint("TOPLEFT", leftList.container, "TOPRIGHT", 8, 0)
    detail:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
    pane.detail = detail

    local hdrBox = CreateFrame("Frame", nil, detail, "BackdropTemplate")
    hdrBox:SetPoint("TOPLEFT", detail, "TOPLEFT", 8, -8)
    hdrBox:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -8, -8)
    hdrBox:SetHeight(56)
    pane.hdrBox = hdrBox

    local hIco = CreateFrame("Button", nil, hdrBox)
    hIco:SetSize(36, 36)
    hIco:SetPoint("LEFT", hdrBox, "LEFT", 8, 0)
    local hBorder = hIco:CreateTexture(nil, "BACKGROUND")
    hBorder:SetAllPoints()
    hBorder:SetTexture(WHITE8X8)
    hIco._border = hBorder
    local hTex = hIco:CreateTexture(nil, "ARTWORK")
    hTex:SetPoint("TOPLEFT", 2, -2)
    hTex:SetPoint("BOTTOMRIGHT", -2, 2)
    hTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    hIco._tex = hTex
    hIco:SetScript("OnEnter", function(selfBtn)
        if selfBtn._itemLink then
            ShowItemHoverTooltip(selfBtn, selfBtn._itemLink, true)
        end
    end)
    hIco:SetScript("OnLeave", HideItemHoverTooltip)
    hIco:SetScript("OnClick", function(selfBtn, btn)
        HandleItemIconClick(selfBtn, selfBtn._itemLink, btn)
    end)
    pane.hIco = hIco

    local hMain = hdrBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hMain:SetPoint("TOPLEFT", hIco, "TOPRIGHT", 9, -2)
    hMain:SetPoint("RIGHT", hdrBox, "RIGHT", -8, 0)
    hMain:SetJustifyH("LEFT")
    hMain:SetWordWrap(false)
    pane.hMain = hMain

    local hSub = hdrBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hSub:SetPoint("BOTTOMLEFT", hIco, "BOTTOMRIGHT", 9, 2)
    hSub:SetPoint("RIGHT", hdrBox, "RIGHT", -8, 0)
    hSub:SetJustifyH("LEFT")
    hSub:SetWordWrap(false)
    pane.hSub = hSub

    local actBar = CreateFrame("Frame", nil, detail)
    actBar:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 8, 8)
    actBar:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -8, 8)
    actBar:SetHeight(24)

    local openCallBtn = Theme:CreateButton(actBar, 88, 22, L["Open Roll"], "default")
    Theme:AutoFitButton(openCallBtn, 74, 14, 118)
    openCallBtn:SetPoint("LEFT", actBar, "LEFT", 0, 0)
    openCallBtn:SetScript("OnClick", function()
        if pane._selectedSess and ns.LootRoll and ns.LootRoll.FormatChatRollOpenDraft then
            InsertSummaryIntoChat(ns.LootRoll:FormatChatRollOpenDraft(pane._selectedSess))
        end
    end)
    pane.openCallBtn = openCallBtn

    local tieBreakBtn = Theme:CreateButton(actBar, 94, 22, L["Tie-Breaker"], "primary")
    Theme:AutoFitButton(tieBreakBtn, 82, 14, 124)
    tieBreakBtn:SetPoint("LEFT", openCallBtn, "RIGHT", 5, 0)
    tieBreakBtn:SetScript("OnClick", function()
        local sess = pane._selectedSess
        if not (sess and ns.LootRoll and ns.LootRoll.StartTieBreakerRound) then return end
        local tb = ns.LootRoll:StartTieBreakerRound(sess.id)
        if tb then
            LootRollUI.selectedChatRollId = tb.id
            LootRollUI:RefreshResultsWindow()
        end
        if ns.LootRoll.FormatChatRollTieBreakerDraft then
            InsertSummaryIntoChat(ns.LootRoll:FormatChatRollTieBreakerDraft(sess))
        end
    end)
    tieBreakBtn:Hide()
    pane.tieBreakBtn = tieBreakBtn

    local winChatBtn = Theme:CreateButton(actBar, 112, 22, L["Announce Winner"], "primary")
    Theme:AutoFitButton(winChatBtn, 96, 14, 144)
    winChatBtn:SetPoint("LEFT", openCallBtn, "RIGHT", 5, 0)
    winChatBtn:SetScript("OnClick", function()
        if pane._selectedSess and ns.LootRoll and ns.LootRoll.FormatChatRollWinnerDraft then
            InsertSummaryIntoChat(ns.LootRoll:FormatChatRollWinnerDraft(pane._selectedSess))
        end
    end)
    pane.winChatBtn = winChatBtn

    local copyBtn = Theme:CreateButton(actBar, 70, 22, L["Copy"], "default")
    Theme:AutoFitButton(copyBtn, 58, 14, 92)
    copyBtn:SetPoint("LEFT", winChatBtn, "RIGHT", 5, 0)
    copyBtn:SetScript("OnClick", function()
        if pane._selectedSess and ns.LootRoll and ns.UI and ns.UI.OpenCopyModal then
            local txt = ns.LootRoll:FormatChatRollSummaryText(pane._selectedSess)
            ns.UI:OpenCopyModal(txt, L["Group /roll Summary"], L["Press Ctrl+C to copy this /roll summary."])
        end
    end)
    pane.copyBtn = copyBtn

    local delBtn = Theme:CreateButton(actBar, 24, 22, "", "default")
    Theme:ConfigureIconButton(delBtn, 24, 22, ICON_PASS, {
        size = 16,
        color = { 1.0, 0.45, 0.45 },
        title = L["Delete Round"],
        desc = L["Remove this /roll round from saved history."],
    })
    delBtn:SetPoint("RIGHT", actBar, "RIGHT", 0, 0)
    delBtn:SetScript("OnClick", function()
        local sess = pane._selectedSess
        if not sess then return end
        local function DoDel()
            if ns.LootRoll and ns.LootRoll.DeleteChatRollSession then
                ns.LootRoll:DeleteChatRollSession(sess.id)
            end
            LootRollUI:RefreshResultsWindow()
        end
        if ns.UI and ns.UI.OpenConfirmModal then
            ns.UI:OpenConfirmModal({
                title = L["Delete Round"],
                message = string.format(L["Delete /roll round for %s?"], tostring(sess.itemName or L["Group /roll Round"])),
                confirmText = L["Remove"],
                confirmVariant = "danger",
                onConfirm = DoDel,
            })
        else
            DoDel()
        end
    end)
    pane.delBtn = delBtn

    local rollsList = Theme:CreateScrollList(detail, 24, CreateChatRollEntryRow, UpdateChatRollEntryRow)
    rollsList.container:SetPoint("TOPLEFT", hdrBox, "BOTTOMLEFT", 0, -6)
    rollsList.container:SetPoint("BOTTOMRIGHT", actBar, "TOPRIGHT", 0, 6)
    pane.rollsList = rollsList

    return pane
end

function LootRollUI:EnsureResultsWindow()
    if self.resultsWindow then
        return self.resultsWindow
    end
    local Theme = ns.Theme
    if not Theme then return nil end

    local win = CreateFrame("Frame", "SocialCentralLootRollResultsFrame", UIParent, "BackdropTemplate")
    win:Hide()
    win:SetSize(748, 498)
    ApplyDefaultResultsWindowPlacement(win)
    win:SetClampedToScreen(true)
    win:SetResizable(true)
    if win.SetResizeBounds then
        win:SetResizeBounds(660, 430, 980, 740)
    elseif win.SetMinResize and win.SetMaxResize then
        win:SetMinResize(660, 430)
        win:SetMaxResize(980, 740)
    end
    table.insert(UISpecialFrames, "SocialCentralLootRollResultsFrame")
    Theme:PrepareTopOverlayModal(win, 845)

    local sBg = win:CreateTexture(nil, "BACKGROUND", nil, -8)
    sBg:SetAllPoints(win)
    sBg:SetTexture(WHITE8X8)
    sBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    win._solidOpaqueBg = sBg

    local hdr = CreateFrame("Frame", nil, win, "BackdropTemplate")
    hdr:SetPoint("TOPLEFT", 6, -6)
    hdr:SetPoint("TOPRIGHT", -6, -6)
    hdr:SetHeight(28)
    win.header = hdr

    local hIco = hdr:CreateTexture(nil, "ARTWORK")
    hIco:SetSize(16, 16)
    hIco:SetPoint("LEFT", hdr, "LEFT", 8, 0)
    hIco:SetTexture(ICON_DICE)

    local closeBtn = Theme:CreateButton(hdr, 22, 20, "X", "default")
    closeBtn:SetPoint("RIGHT", hdr, "RIGHT", -5, 0)
    closeBtn:SetScript("OnClick", function()
        win:Hide()
    end)
    win.closeBtn = closeBtn

    local dropsPane
    local chatRollsPane
    local tabDropsBtn
    local tabChatRollBtn
    local latestRunBtn
    local fullHistBtn

    local helpBtn = Theme:CreateHelpButton(
        hdr,
        L["Help: Loot Roll Results Window"],
        L["Opens focused on your latest dungeon, raid, or group loot summary with Win Rate & Roll Luck analytics, rarity/sort filters, Master Loot & boss attribution, and a full Raid Leader /roll (1-100) console with MS/OS brackets and automatic Tie-Breakers."],
        L["Filter or sort drops on the left, right-click any drop or player for quick actions, switch to Group /roll (1-100) to run Raid Leader roll calls and tie-breakers, or click Configure for quick Loot Roll options."],
        16,
        {
            target = win,
            steps = {
                {
                    title = L["1. Group Drops & /roll Tabs"],
                    tag = "1/4 · " .. L["Loot Roll Results"],
                    text = L["Switch between Need/Greed Drops (with Rarity & Sort filters) and the Raid Leader Group /roll (1-100) console."],
                    target = function() return tabDropsBtn or hdr end,
                },
                {
                    title = L["2. Last Group, Full History & Luck Analytics"],
                    tag = "2/4 · " .. L["Scope"],
                    text = L["Opens on Last Group with Win Rate, Average Roll, and top winners. Click Full History for older runs."],
                    target = function() return fullHistBtn or latestRunBtn or hdr end,
                },
                {
                    title = L["3. Roll Breakdown, Ties & Player Actions"],
                    tag = "3/4 · " .. L["Details"],
                    text = L["Inspect every roll, MS/OS brackets, and Boss/Master Loot info. Right-click any player to whisper or ask about an item."],
                    target = function()
                        if LootRollUI.resultsSubTab == "chatroll" and chatRollsPane and chatRollsPane.detail then
                            return chatRollsPane.detail
                        end
                        return (dropsPane and dropsPane.detail) or win
                    end,
                },
                {
                    title = L["4. Announce, Tie-Breaker & Quick Settings"],
                    tag = "4/4 · " .. L["Actions"],
                    text = L["Use Announce Winner, Open Roll, Tie-Breaker, Roll 1-100, or Configure to adjust layout, official bar, and notifications."],
                    target = function() return win.configBtn or (dropsPane and dropsPane.announceBtn) or win end,
                },
            },
        }
    )
    helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    win.helpBtn = helpBtn

    local configBtn = Theme:CreateButton(hdr, 84, 20, L["Configure"], "default")
    Theme:AutoFitButton(configBtn, 72, 14, 120)
    configBtn:SetPoint("RIGHT", helpBtn, "LEFT", -4, 0)
    configBtn:SetScript("OnClick", function(selfBtn)
        OpenLootRollQuickConfigMenu(selfBtn)
    end)
    configBtn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Quick Loot Roll Settings"], 1.0, 0.85, 0.25)
        GameTooltip:AddLine(L["Adjust dice button visibility, Tabbed/Stacked layout, hiding Blizzard's default roll bar, winner celebration, or jump straight to full Settings."], 0.90, 0.94, 0.98, true)
        GameTooltip:Show()
    end)
    configBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    win.configBtn = configBtn

    local statsFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statsFs:SetPoint("RIGHT", configBtn, "LEFT", -8, 0)
    statsFs:SetJustifyH("RIGHT")
    statsFs:SetWordWrap(false)
    win.statsFs = statsFs

    local titleFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("LEFT", hIco, "RIGHT", 6, 0)
    titleFs:SetPoint("RIGHT", statsFs, "LEFT", -8, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetWordWrap(false)
    titleFs:SetText(L["Group Loot Roll Results"])
    win.titleFs = titleFs

    Theme:MakeMovable(win, {
        key = "loot_roll_results",
        handles = { hdr, win },
        onReset = ApplyDefaultResultsWindowPlacement,
    })

    local subTabRow = CreateFrame("Frame", nil, win)
    subTabRow:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 2, -6)
    subTabRow:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", -2, -6)
    subTabRow:SetHeight(24)

    tabDropsBtn = Theme:CreateButton(subTabRow, 150, 22, L["Group Drops"], "tab")
    Theme:AutoFitButton(tabDropsBtn, 120, 18, 196)
    tabDropsBtn:SetPoint("LEFT", subTabRow, "LEFT", 0, 0)
    tabDropsBtn:SetScript("OnClick", function()
        LootRollUI.resultsSubTab = "drops"
        LootRollUI:RefreshResultsWindow()
    end)
    win.tabDropsBtn = tabDropsBtn

    tabChatRollBtn = Theme:CreateButton(subTabRow, 150, 22, L["Group /roll (1-100)"], "tab")
    Theme:AutoFitButton(tabChatRollBtn, 128, 18, 200)
    tabChatRollBtn:SetPoint("LEFT", tabDropsBtn, "RIGHT", 6, 0)
    tabChatRollBtn:SetScript("OnClick", function()
        LootRollUI.resultsSubTab = "chatroll"
        LootRollUI:RefreshResultsWindow()
    end)
    win.tabChatRollBtn = tabChatRollBtn

    local scopeHelpBtn = Theme:CreateHelpButton(
        subTabRow,
        L["Help: Roll History Scope"],
        L["By default, opening Roll Results always shows only the summary of your last dungeon, raid, or group session."],
        L["Click 'Full History' whenever you explicitly want to view older drops from previous groups and runs."],
        16,
        { target = subTabRow }
    )
    scopeHelpBtn:SetPoint("RIGHT", subTabRow, "RIGHT", 0, 0)
    win.scopeHelpBtn = scopeHelpBtn

    fullHistBtn = Theme:CreateButton(subTabRow, 114, 22, L["Full History"], "default")
    Theme:AutoFitButton(fullHistBtn, 92, 16, 158)
    fullHistBtn:SetPoint("RIGHT", scopeHelpBtn, "LEFT", -4, 0)
    fullHistBtn:SetScript("OnClick", function()
        LootRollUI.resultsScope = "all"
        LootRollUI:RefreshResultsWindow()
    end)
    win.fullHistBtn = fullHistBtn

    latestRunBtn = Theme:CreateButton(subTabRow, 108, 22, L["Last Group"], "primary")
    Theme:AutoFitButton(latestRunBtn, 86, 16, 140)
    latestRunBtn:SetPoint("RIGHT", fullHistBtn, "LEFT", -4, 0)
    latestRunBtn:SetScript("OnClick", function()
        LootRollUI.resultsScope = "latest_run"
        LootRollUI:RefreshResultsWindow()
    end)
    win.latestRunBtn = latestRunBtn

    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", subTabRow, "BOTTOMLEFT", 0, -6)
    body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -8, 12)
    win.body = body

    local summaryBar = CreateFrame("Frame", nil, body, "BackdropTemplate")
    summaryBar:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    summaryBar:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    summaryBar:SetHeight(26)
    summaryBar:EnableMouse(true)
    if Theme.AttachDragHandle then
        Theme:AttachDragHandle(summaryBar, win)
    end
    win.summaryBar = summaryBar

    local summaryRightFs = summaryBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summaryRightFs:SetPoint("RIGHT", summaryBar, "RIGHT", -10, 0)
    summaryRightFs:SetJustifyH("RIGHT")
    summaryRightFs:SetWordWrap(false)
    win.summaryRightFs = summaryRightFs

    local summaryLeftFs = summaryBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summaryLeftFs:SetPoint("LEFT", summaryBar, "LEFT", 10, 0)
    summaryLeftFs:SetPoint("RIGHT", summaryRightFs, "LEFT", -8, 0)
    summaryLeftFs:SetJustifyH("LEFT")
    summaryLeftFs:SetWordWrap(false)
    win.summaryLeftFs = summaryLeftFs

    summaryBar:SetScript("OnEnter", function(selfBar)
        local rs = selfBar._runSum
        local an = selfBar._analytics
        if not GameTooltip then return end
        if not ((rs and (rs.total or 0) > 0) or (an and (an.total or 0) > 0)) then return end
        GameTooltip:SetOwner(selfBar, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        if rs and (rs.total or 0) > 0 then
            GameTooltip:AddLine("|cffffd24d" .. L["Last Group Summary"] .. "|r — " .. tostring(rs.zone or L["Group"]), 1, 1, 1)
            GameTooltip:AddLine(string.format(L["%d drops · %d won"], rs.total or 0, rs.won or 0), 0.85, 0.90, 0.96)
        else
            GameTooltip:AddLine("|cff58a6ff" .. L["Full History"] .. "|r — " .. L["Loot Analytics"], 1, 1, 1)
        end
        if an and (an.total or 0) > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Your Roll Luck:"], 1.0, 0.85, 0.28)
            GameTooltip:AddLine(string.format(L["Win Rate: %d%% (%d/%d) · Avg Roll: %d · Best: %d"], an.winPct or 0, an.wonByMe or 0, an.myRolls or 0, an.avgRoll or 0, an.bestRoll or 0), 0.90, 0.94, 0.98)
            if type(an.perPlayer) == "table" and #an.perPlayer > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Loot Distribution:"], 0.68, 0.84, 1.0)
                for i = 1, math.min(8, #an.perPlayer) do
                    local pp = an.perPlayer[i]
                    local cHex = (pp.classFile and Compat and Compat.ClassHex and Compat.ClassHex(pp.classFile)) or "|cffe6edf3"
                    local meTag = pp.isMe and (" |cffffea70(" .. L["You"] .. ")|r") or ""
                    GameTooltip:AddDoubleLine(cHex .. tostring(pp.name or "?") .. "|r" .. meTag, string.format(L["%d won"], pp.wins or 0), 1, 1, 1, 1.0, 0.88, 0.35)
                end
            end
        end
        if rs and type(rs.participants) == "table" and #rs.participants > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Group Participants:"], 0.68, 0.84, 1.0)
            GameTooltip:AddLine(table.concat(rs.participants, ", "), 0.90, 0.94, 0.98, true)
        end
        GameTooltip:Show()
    end)
    summaryBar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local contentArea = CreateFrame("Frame", nil, body)
    contentArea:SetPoint("TOPLEFT", summaryBar, "BOTTOMLEFT", 0, -6)
    contentArea:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    win.contentArea = contentArea

    dropsPane = BuildDropsPane(contentArea)
    chatRollsPane = BuildChatRollsPane(contentArea)
    win.dropsPane = dropsPane
    win.chatRollsPane = chatRollsPane

    local resizeGrip = CreateFrame("Button", nil, win)
    resizeGrip:SetSize(14, 14)
    resizeGrip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -2, 2)
    local gripTex = resizeGrip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" and win.StartSizing then
            win:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        if win.StopMovingOrSizing then
            win:StopMovingOrSizing()
        end
    end)
    win.resizeGrip = resizeGrip

    win:HookScript("OnShow", function()
        if ns.LootRoll and ns.LootRoll.MarkResultsRead then
            ns.LootRoll:MarkResultsRead()
        end
        LootRollUI:RefreshResultsWindow()
        LootRollUI:SyncResultsButton()
    end)

    self.resultsWindow = win
    return win
end

function LootRollUI:ApplyResultsWindowTheme()
    local win = self.resultsWindow
    local Theme = ns.Theme
    if not (win and Theme) then return end
    local p = Theme:GetPalette()
    Theme:ApplyBackdrop(win, "window", p)
    ApplySolidOpaqueBg(win, p)
    Theme:ApplyBackdrop(win.header, "header", p)
    Theme:StyleButton(win.closeBtn, "default")
    if win.configBtn then Theme:StyleButton(win.configBtn, "default") end

    local isDrops = (self.resultsSubTab ~= "chatroll")
    Theme:StyleButton(win.tabDropsBtn, "tab")
    Theme:SetButtonActive(win.tabDropsBtn, isDrops, "tab")
    Theme:StyleButton(win.tabChatRollBtn, "tab")
    Theme:SetButtonActive(win.tabChatRollBtn, not isDrops, "tab")

    local isLatestScope = (self.resultsScope ~= "all")
    if win.latestRunBtn then
        Theme:StyleButton(win.latestRunBtn, isLatestScope and "primary" or "default")
        Theme:SetButtonActive(win.latestRunBtn, isLatestScope, isLatestScope and "primary" or "default")
    end
    if win.fullHistBtn then
        Theme:StyleButton(win.fullHistBtn, (not isLatestScope) and "primary" or "default")
        Theme:SetButtonActive(win.fullHistBtn, not isLatestScope, (not isLatestScope) and "primary" or "default")
    end
    if win.summaryBar then
        Theme:ApplyBackdrop(win.summaryBar, "inset", p)
    end

    if win.dropsPane then
        local dp = win.dropsPane
        Theme:ApplyBackdrop(dp.detail, "surface", p)
        Theme:ApplyBackdrop(dp.hero, "inset", p)
        Theme:ApplyBackdrop(dp.winBox, "inset", p)
        Theme:StyleButton(dp.clearBtn, "default")
        if dp.sortBtn then Theme:StyleButton(dp.sortBtn, (self.resultsSortBy and self.resultsSortBy ~= "newest") and "primary" or "default") end
        if dp.qualBtn then Theme:StyleButton(dp.qualBtn, ((self.resultsQualityMin or 0) > 0) and "primary" or "default") end
        if dp.announceBtn then Theme:StyleButton(dp.announceBtn, "primary") end
        Theme:StyleButton(dp.copyBtn, "default")
        Theme:StyleButton(dp.chatBtn, "default")
        Theme:StyleButton(dp.delBtn, "default")
        for _, fb in ipairs(dp.filterBtns or {}) do
            local act = (self.resultsFilter == fb._filterId)
            Theme:StyleButton(fb, act and "primary" or "default")
            Theme:SetButtonActive(fb, act, act and "primary" or "default")
        end
        if dp.leftList then dp.leftList:RefreshTheme() end
        if dp.rollsList then dp.rollsList:RefreshTheme() end
    end
    if win.chatRollsPane then
        local cp = win.chatRollsPane
        Theme:ApplyBackdrop(cp.detail, "surface", p)
        Theme:ApplyBackdrop(cp.hdrBox, "inset", p)
        Theme:StyleButton(cp.clearBtn, "default")
        Theme:StyleButton(cp.newRoundBtn, "primary")
        if cp.roll100Btn then Theme:StyleButton(cp.roll100Btn, "default") end
        if cp.openCallBtn then Theme:StyleButton(cp.openCallBtn, "default") end
        if cp.tieBreakBtn then Theme:StyleButton(cp.tieBreakBtn, "primary") end
        if cp.winChatBtn then Theme:StyleButton(cp.winChatBtn, "primary") end
        Theme:StyleButton(cp.copyBtn, "default")
        if cp.delBtn then Theme:StyleButton(cp.delBtn, "default") end
        if cp.leftList then cp.leftList:RefreshTheme() end
        if cp.rollsList then cp.rollsList:RefreshTheme() end
    end
end

local function RenderSelectedDropDetail(dp, sel)
    dp._selectedRec = sel
    LootRollUI._activeDetailLink = sel and (sel.itemLink or sel.link) or nil
    if sel then
        dp.dIco._itemLink = sel.itemLink or sel.link
        dp.dIco._itemName = sel.name
        dp.dIco._tex:SetTexture(sel.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        local qr, qg, qb = QualityRGB(sel.quality or 1)
        dp.dIco._border:SetVertexColor(qr, qg, qb, 0.95)
        local qty = (sel.count and sel.count > 1) and (" x" .. tostring(sel.count)) or ""
        local mlTag = sel.isMasterLoot and (" |cffff9b3d[" .. L["Master Loot"] .. "]|r") or ""
        dp.dTitle:SetText(QualityHex(sel.quality or 1) .. tostring(sel.name or "?") .. "|r" .. qty .. mlTag)

        local metaBits = {}
        if sel.bossName and sel.bossName ~= "" then metaBits[#metaBits + 1] = "|cffffd24d" .. sel.bossName .. "|r" end
        if sel.zone and sel.zone ~= "" then metaBits[#metaBits + 1] = sel.zone end
        if sel.charName and sel.charName ~= "" then metaBits[#metaBits + 1] = sel.charName end
        if sel.ts then metaBits[#metaBits + 1] = date("%d/%m %H:%M", sel.ts) end
        dp.dMeta:SetText("|cff9da7b5" .. table.concat(metaBits, " · ") .. "|r")

        if sel._isActive and not sel.resolved then
            dp.winMain:SetText("|cff47ef66" .. L["Roll in progress — watching live party picks"] .. "|r")
        elseif sel.allPassed then
            dp.winMain:SetText(FormatChoiceIconTag("PASS", 14) .. "  |cff9da7b5" .. L["All passed — nobody claimed this item"] .. "|r")
        elseif sel.winnerName then
            local wHex = (sel.winnerClass and Compat and Compat.ClassHex and Compat.ClassHex(sel.winnerClass)) or "|cffe6edf3"
            local cKey = sel.winnerChoice or "WON"
            local cLbl = (ns.LootRoll and ns.LootRoll.GetRollChoiceLabel) and ns.LootRoll:GetRollChoiceLabel(cKey) or L["Won"]
            local rVal = sel.winnerRoll and (" [" .. tostring(sel.winnerRoll) .. "]") or ""
            local prefix = sel.wonByMe
                and (FormatChoiceIconTag("WON", 14) .. " |cffffea70" .. L["YOU WON!"] .. "|r ")
                or (FormatChoiceIconTag("WON", 14) .. " |cffffd24d" .. L["Winner:"] .. "|r ")
            dp.winMain:SetText(prefix .. wHex .. tostring(sel.winnerName) .. "|r · " .. FormatChoiceIconTag(cKey, 13) .. " " .. cLbl .. rVal)
        else
            dp.winMain:SetText("|cff9da7b5" .. L["Pending / Expired without winner notice"] .. "|r")
        end

        if sel.myChoice then
            local myLbl = (ns.LootRoll and ns.LootRoll.GetRollChoiceLabel) and ns.LootRoll:GetRollChoiceLabel(sel.myChoice) or sel.myChoice
            local myHex = (ns.LootRoll and ns.LootRoll.GetChoiceColor) and ns.LootRoll:GetChoiceColor(sel.myChoice) or "|cffe6edf3"
            local myRollStr = sel.myRoll and (" [" .. tostring(sel.myRoll) .. "]") or ""
            dp.winSub:SetText(L["Your choice"] .. ": " .. myHex .. myLbl .. myRollStr .. "|r")
        else
            dp.winSub:SetText("|cff8b949e" .. L["No roll submitted on this character"] .. "|r")
        end

        dp.rollsList:SetData(sel.choices or {}, L["No individual player rolls recorded for this item."], true)
        if dp.announceBtn then dp.announceBtn:SetEnabled(true) end
        dp.copyBtn:SetEnabled(true)
        dp.chatBtn:SetEnabled(true)
        dp.delBtn:SetEnabled(true)
    else
        dp.dIco._itemLink = nil
        dp.dIco._tex:SetTexture(ICON_DICE)
        dp.dIco._border:SetVertexColor(0.3, 0.3, 0.35, 0.7)
        dp.dTitle:SetText("|cff9da7b5" .. L["Select a loot drop"] .. "|r")
        dp.dMeta:SetText("")
        dp.winMain:SetText("")
        dp.winSub:SetText("")
        dp.rollsList:SetData({}, L["Select a drop on the left to inspect every roll."], true)
        if dp.announceBtn then dp.announceBtn:SetEnabled(false) end
        dp.copyBtn:SetEnabled(false)
        dp.chatBtn:SetEnabled(false)
        dp.delBtn:SetEnabled(false)
    end
end

local function RenderSelectedChatRollDetail(cp, selSess)
    cp._selectedSess = selSess
    LootRollUI._activeChatRollSess = selSess
    LootRollUI._activeChatRollLink = selSess and selSess.itemLink or nil
    if selSess then
        if cp.hIco then
            cp.hIco._itemLink = selSess.itemLink
            cp.hIco._itemName = selSess.itemName
            cp.hIco._tex:SetTexture(selSess.itemTexture or ICON_DICE)
            local qr, qg, qb = QualityRGB(selSess.itemQuality or 1)
            cp.hIco._border:SetVertexColor(qr, qg, qb, selSess.itemLink and 0.95 or 0.55)
        end
        local headName = selSess.itemName
            and (QualityHex(selSess.itemQuality or 1) .. selSess.itemName .. "|r")
            or ("|cffffd24d" .. L["Group /roll Round"] .. "|r")
        if selSess.isTieBreaker then
            headName = headName .. " |cff58b8ff[" .. L["Tie-Breaker"] .. "]|r"
        end
        cp.hMain:SetText(headName)

        local subParts = {}
        if selSess.leaderName and selSess.leaderRoll then
            local wHex = (selSess.leaderClass and Compat and Compat.ClassHex and Compat.ClassHex(selSess.leaderClass)) or "|cffe6edf3"
            if selSess.isTied and type(selSess.tiedNames) == "table" and #selSess.tiedNames > 1 then
                subParts[#subParts + 1] = "|cffff9b3d" .. L["TIE — RE-ROLL!"] .. "|r " .. table.concat(selSess.tiedNames, " & ") .. " [" .. tostring(selSess.leaderRoll) .. "]"
            else
                subParts[#subParts + 1] = FormatChoiceIconTag("WON", 13) .. " MS: " .. wHex .. selSess.leaderName .. "|r [" .. tostring(selSess.leaderRoll) .. "]"
            end
        end
        if selSess.osLeaderName and selSess.osLeaderRoll then
            local osHex = (selSess.osLeaderClass and Compat and Compat.ClassHex and Compat.ClassHex(selSess.osLeaderClass)) or "|cffe6edf3"
            subParts[#subParts + 1] = "|cff58b8ffOS:|r " .. osHex .. selSess.osLeaderName .. "|r [" .. tostring(selSess.osLeaderRoll) .. "]"
        end
        if #subParts > 0 then
            cp.hSub:SetText(table.concat(subParts, "  ·  "))
        else
            cp.hSub:SetText("|cff9da7b5" .. L["No valid 1-100 rolls yet"] .. "|r")
        end
        cp.rollsList:SetData(selSess.rolls or {}, L["No rolls in this round yet. Click 'Open Roll' or type /roll 100 in chat!"], true)
        if cp.openCallBtn then cp.openCallBtn:SetEnabled(true) end
        if cp.tieBreakBtn and cp.winChatBtn then
            local showTie = (selSess.isTied == true)
            cp.tieBreakBtn:SetShown(showTie)
            cp.tieBreakBtn:SetEnabled(showTie)
            cp.winChatBtn:ClearAllPoints()
            if showTie then
                cp.winChatBtn:SetPoint("LEFT", cp.tieBreakBtn, "RIGHT", 5, 0)
            else
                cp.winChatBtn:SetPoint("LEFT", cp.openCallBtn, "RIGHT", 5, 0)
            end
            cp.winChatBtn:SetEnabled(true)
        end
        cp.copyBtn:SetEnabled(true)
        if cp.delBtn then cp.delBtn:SetEnabled(true) end
    else
        if cp.hIco then
            cp.hIco._itemLink = nil
            cp.hIco._tex:SetTexture(ICON_DICE)
            cp.hIco._border:SetVertexColor(0.3, 0.3, 0.35, 0.7)
        end
        cp.hMain:SetText("|cff9da7b5" .. L["Select a /roll round"] .. "|r")
        cp.hSub:SetText("")
        cp.rollsList:SetData({}, L["When your party or raid uses /roll, players will be ranked here automatically (tracking MS 1-100, OS 1-50, duplicates, and tie-breakers)."], true)
        if cp.openCallBtn then cp.openCallBtn:SetEnabled(false) end
        if cp.tieBreakBtn then cp.tieBreakBtn:Hide() end
        if cp.winChatBtn then
            cp.winChatBtn:ClearAllPoints()
            cp.winChatBtn:SetPoint("LEFT", cp.openCallBtn, "RIGHT", 5, 0)
            cp.winChatBtn:SetEnabled(false)
        end
        cp.copyBtn:SetEnabled(false)
        if cp.delBtn then cp.delBtn:SetEnabled(false) end
    end
end

function LootRollUI:SelectResultRow(rec)
    if not rec then return end
    self.selectedResultId = rec.id or rec.historyId
    local win = self.resultsWindow
    local dp = win and win.dropsPane
    if not (win and win:IsShown() and dp) then
        return
    end
    for _, r in ipairs((dp.leftList and dp.leftList.rows) or {}) do
        if r and r.selBg and r._rec then
            r.selBg:SetShown(r._rec.id == self.selectedResultId or (r._rec.historyId and r._rec.historyId == self.selectedResultId))
        end
    end
    RenderSelectedDropDetail(dp, rec)
end

function LootRollUI:SelectChatRollRow(sess)
    if not sess then return end
    self.selectedChatRollId = sess.id
    local win = self.resultsWindow
    local cp = win and win.chatRollsPane
    if not (win and win:IsShown() and cp) then
        return
    end
    for _, r in ipairs((cp.leftList and cp.leftList.rows) or {}) do
        if r and r.selBg and r._sess then
            r.selBg:SetShown(r._sess.id == self.selectedChatRollId)
        end
    end
    RenderSelectedChatRollDetail(cp, sess)
end

function LootRollUI:RefreshResultsWindow()
    local win = self.resultsWindow
    if not (win and win:IsShown()) then return end
    local Theme = ns.Theme
    self:ApplyResultsWindowTheme()

    local curScope = (self.resultsScope == "all") and "all" or "latest_run"
    local isDrops = (self.resultsSubTab ~= "chatroll")
    local tot, won = 0, 0
    if ns.LootRoll and ns.LootRoll.GetResultsStats then
        tot, won = ns.LootRoll:GetResultsStats()
    end
    local totalChatSess = #(ns.LootRoll and ns.LootRoll.chatRollSessions or {})
    local runSum = (ns.LootRoll and ns.LootRoll.GetLatestRunSummary) and ns.LootRoll:GetLatestRunSummary() or nil

    if win.fullHistBtn and Theme then
        local scopeTot = isDrops and tot or totalChatSess
        local fhLabel = (scopeTot > 0) and string.format("%s (%d)", L["Full History"], scopeTot) or L["Full History"]
        Theme:SetButtonText(win.fullHistBtn, fhLabel)
        Theme:AutoFitButton(win.fullHistBtn, 92, 16, 175)
    end

    win.dropsPane:SetShown(isDrops)
    win.chatRollsPane:SetShown(not isDrops)

    if isDrops then
        local dp = win.dropsPane
        if dp.qualBtn and Theme then
            local qMap = { [0] = L["Rarity: All"], [2] = L["Rarity: Uncommon+"], [3] = L["Rarity: Rare+"], [4] = L["Rarity: Epic+"] }
            Theme:SetButtonText(dp.qualBtn, qMap[self.resultsQualityMin or 0] or L["Rarity: All"])
            Theme:AutoFitButton(dp.qualBtn, 82, 14, 142)
        end
        if dp.sortBtn and Theme then
            local sMap = { newest = L["Sort: Newest"], quality = L["Sort: Rarity"], roll = L["Sort: Highest Roll"], winner = L["Sort: Winner"] }
            Theme:SetButtonText(dp.sortBtn, sMap[self.resultsSortBy or "newest"] or L["Sort: Newest"])
            Theme:AutoFitButton(dp.sortBtn, 94, 14, 156)
        end

        local items = (ns.LootRoll and ns.LootRoll.GetResultsList) and ns.LootRoll:GetResultsList({
            filter = self.resultsFilter,
            query = self.resultsSearch,
            scope = curScope,
            qualityMin = self.resultsQualityMin or 0,
            sortBy = self.resultsSortBy or "newest",
        }) or {}
        local scopePool = (ns.LootRoll and ns.LootRoll.GetResultsList) and ns.LootRoll:GetResultsList({
            filter = "ALL",
            query = "",
            scope = curScope,
        }) or items
        local analytics = (ns.LootRoll and ns.LootRoll.GetRunAnalytics) and ns.LootRoll:GetRunAnalytics(scopePool) or nil

        local luckStr = ""
        if analytics and (analytics.myRolls or 0) > 0 then
            luckStr = string.format(L[" · |cff47ef66%d%% win|r · |cff58b8ffavg %d|r"], analytics.winPct or 0, analytics.avgRoll or 0)
        end

        if curScope == "latest_run" then
            local rTot = runSum and runSum.total or 0
            local rWon = runSum and runSum.won or 0
            win.statsFs:SetText(string.format(L["|cff9da7b5%d drops · |cffffea70%d won|r"], rTot, rWon))
            if win.summaryBar then
                win.summaryBar._runSum = runSum
                win.summaryBar._analytics = analytics
                if runSum and (runSum.total or 0) > 0 then
                    local whenStr = runSum.ts and Compat and Compat.FormatRelativeTime and Compat.FormatRelativeTime(runSum.ts, L) or ""
                    local bits = { "|cffffd24d" .. L["Last Group Summary"] .. ":|r " .. tostring(runSum.zone or L["Group"]) }
                    if whenStr ~= "" then
                        bits[#bits + 1] = "|cff9da7b5" .. whenStr .. "|r"
                    end
                    if (runSum.participantCount or 0) > 1 then
                        bits[#bits + 1] = "|cff9da7b5" .. string.format(L["%d players"], runSum.participantCount) .. "|r"
                    end
                    win.summaryLeftFs:SetText(table.concat(bits, " · "))
                    win.summaryRightFs:SetText(string.format(L["|cff9da7b5%d drops · |cffffea70%d won|r"], rTot, rWon) .. luckStr)
                else
                    win.summaryLeftFs:SetText("|cff9da7b5" .. L["Showing only your latest dungeon, raid, or group session."] .. "|r")
                    win.summaryRightFs:SetText("")
                end
            end
        else
            win.statsFs:SetText(string.format(L["|cff9da7b5%d drops · |cffffea70%d won|r"], tot, won))
            if win.summaryBar then
                win.summaryBar._runSum = nil
                win.summaryBar._analytics = analytics
                win.summaryLeftFs:SetText("|cff58a6ff" .. L["Full History"] .. ":|r |cff9da7b5" .. L["Showing all saved drops and previous groups."] .. "|r")
                win.summaryRightFs:SetText(string.format(L["|cff9da7b5%d drops · |cffffea70%d won|r"], tot, won) .. luckStr)
            end
        end

        local sel = nil
        if self.selectedResultId then
            for _, it in ipairs(items) do
                if it.id == self.selectedResultId or tostring(it.rollID) == tostring(self.selectedResultId) then
                    sel = it
                    break
                end
            end
        end
        if not sel then
            sel = items[1]
            self.selectedResultId = sel and sel.id or nil
        end

        local emptyMsg
        if #(self.resultsSearch or "") > 0 or self.resultsFilter ~= "ALL" or (self.resultsQualityMin or 0) > 0 then
            emptyMsg = L["No matching loot roll results found."]
        elseif curScope == "latest_run" and tot > 0 then
            emptyMsg = L["No drops in the latest group session (click Full History above to view older runs)."]
        else
            emptyMsg = L["No group loot rolls recorded yet. Drops from dungeons and raids appear here automatically!"]
        end
        dp.leftList:SetData(items, emptyMsg, false)
        dp.clearBtn:SetEnabled(tot > 0)
        RenderSelectedDropDetail(dp, sel)
    else
        local cp = win.chatRollsPane
        local sessions = (ns.LootRoll and ns.LootRoll.GetChatRollSessions) and ns.LootRoll:GetChatRollSessions(self.chatRollSearch, curScope) or {}
        local tiedCount = 0
        for _, s in ipairs(sessions) do
            if s.isTied then tiedCount = tiedCount + 1 end
        end
        win.statsFs:SetText(string.format(L["|cff9da7b5%d /roll rounds|r"], #sessions))
        if win.summaryBar then
            win.summaryBar._runSum = nil
            win.summaryBar._analytics = nil
            win.summaryLeftFs:SetText("|cffffd24d" .. L["Raid Leader /roll Console:"] .. "|r |cff9da7b5" .. L["MS (1-100) · OS (1-50) · Automatic duplicate & tie detection"] .. "|r")
            if tiedCount > 0 then
                win.summaryRightFs:SetText(string.format("|cffff9b3d%d %s|r", tiedCount, L["tied rounds"]))
            else
                win.summaryRightFs:SetText(string.format("|cff9da7b5%d / %d|r", #sessions, totalChatSess))
            end
        end

        local selSess = nil
        if self.selectedChatRollId then
            for _, s in ipairs(sessions) do
                if s.id == self.selectedChatRollId then
                    selSess = s
                    break
                end
            end
        end
        if not selSess then
            selSess = sessions[1]
            self.selectedChatRollId = selSess and selSess.id or nil
        end
        cp.leftList:SetData(sessions, L["No Group /roll (1-100) rounds captured yet. Click 'New /roll Round' or whenever teammates type /roll in party or raid, results appear here automatically!"], false)
        cp.clearBtn:SetEnabled(totalChatSess > 0)
        RenderSelectedChatRollDetail(cp, selSess)
    end
end

function LootRollUI:OpenResultsWindow(focusIdOrRollId)
    local win = self:EnsureResultsWindow()
    if not win then return end
    self.resultsScope = "latest_run"
    if focusIdOrRollId ~= nil then
        local rec = ns.LootRoll and ns.LootRoll.GetResultById and ns.LootRoll:GetResultById(focusIdOrRollId)
        if rec and rec.id then
            self.selectedResultId = rec.id
            self.resultsSubTab = "drops"
            self.resultsFilter = "ALL"
            local latestItems = ns.LootRoll and ns.LootRoll.GetResultsList and ns.LootRoll:GetResultsList({ scope = "latest_run" }) or {}
            local inLatest = false
            for _, it in ipairs(latestItems) do
                if it.id == rec.id then
                    inLatest = true
                    break
                end
            end
            if not inLatest then
                self.resultsScope = "all"
            end
        end
    end
    if ns.Theme and ns.Theme.PrepareTopOverlayModal then
        ns.Theme:PrepareTopOverlayModal(win, 845)
    end
    if ns.Theme and ns.Theme.HasSavedWindowPosition and ns.Theme:HasSavedWindowPosition("loot_roll_results") then
        ns.Theme:RestoreWindowPosition(win, "loot_roll_results", false)
    end
    if ns.LootRoll and ns.LootRoll.MarkResultsRead then
        ns.LootRoll:MarkResultsRead()
    end
    win:Show()
    if win.Raise then win:Raise() end
    self:RefreshResultsWindow()
    self:SyncResultsButton()
end

function LootRollUI:ToggleResultsWindow()
    if self.resultsWindow and self.resultsWindow:IsShown() then
        self.resultsWindow:Hide()
    else
        self:OpenResultsWindow()
    end
end

-- ============================================================================
-- 7. Active Roll Card Refresh & Lifecycle
-- ============================================================================
function LootRollUI:ShowActiveRollCard()
    self._userClosedActive = nil
    self:Refresh()
    if self.frame and self.frame.Raise then
        self.frame:Raise()
    end
end

local function SetVerdictPillVisual(f, text, bgR, bgG, bgB, barR, barG, barB, txR, txG, txB)
    local pill = f.compVerdictPill
    if not pill then return end
    if not text or text == "" then
        pill:Hide()
        return
    end
    pill.text:SetText(text)
    pill.text:SetTextColor(txR or 1, txG or 1, txB or 1)
    pill._bg:SetVertexColor(bgR or 0.14, bgG or 0.18, bgB or 0.24, 0.36)
    pill._bar:SetVertexColor(barR or 0.65, barG or 0.72, barB or 0.80, 0.95)
    local txtW = math.ceil(pill.text:GetStringWidth() or 38)
    pill:SetWidth(math.max(42, math.min(116, txtW + 14)))
    pill:Show()
end

local function UpdateComparisonSection(f, comp)
    f.compBox._equippedLink = comp.equippedLink
    local hasSwap = (comp.isEquippable == true and comp.altSlotId ~= nil)
    if f.slotSwapBtn then
        f.compVerdictPill:ClearAllPoints()
        if hasSwap then
            local isSlot2 = (comp.slotId == 12 or comp.slotId == 14 or comp.slotId == 17)
            ns.Theme:SetButtonText(f.slotSwapBtn, isSlot2 and "2/2" or "1/2")
            f.slotSwapBtn:Show()
            f.compVerdictPill:SetPoint("RIGHT", f.slotSwapBtn, "LEFT", -5, 0)
        else
            f.slotSwapBtn:Hide()
            f.compVerdictPill:SetPoint("TOPRIGHT", f.compBox, "TOPRIGHT", -10, -5)
        end
    end

    if comp.verdict == "UNIQUE_OWNED" then
        SetVerdictPillVisual(f, L["Unique"], 0.48, 0.32, 0.08, 1.0, 0.72, 0.20, 1.0, 0.82, 0.32)
    elseif comp.verdict == "CANNOT_EQUIP" then
        SetVerdictPillVisual(f, L["Cannot Equip"], 0.52, 0.12, 0.12, 1.0, 0.34, 0.32, 1.0, 0.56, 0.54)
    elseif comp.verdict == "WRONG_ARMOR" then
        SetVerdictPillVisual(f, L["Wrong Armor"], 0.48, 0.32, 0.08, 1.0, 0.72, 0.20, 1.0, 0.82, 0.32)
    elseif comp.verdict == "RECIPE_YOU" then
        SetVerdictPillVisual(f, L["Can Learn"], 0.10, 0.42, 0.20, 0.28, 0.94, 0.42, 0.42, 0.96, 0.54)
    elseif comp.verdict == "RECIPE_KNOWN" then
        SetVerdictPillVisual(f, L["Known"], 0.46, 0.26, 0.08, 1.0, 0.62, 0.24, 1.0, 0.74, 0.38)
    elseif comp.verdict == "RECIPE_ALT" then
        SetVerdictPillVisual(f, L["Alt Needs"], 0.12, 0.30, 0.52, 0.34, 0.72, 1.0, 0.52, 0.82, 1.0)
    elseif comp.verdict == "EMPTY" then
        SetVerdictPillVisual(f, L["EMPTY"], 0.10, 0.42, 0.20, 0.28, 0.94, 0.42, 0.42, 0.96, 0.54)
    elseif comp.ilvlDiff and comp.ilvlDiff > 0 then
        SetVerdictPillVisual(f, string.format("+%d iLvl", comp.ilvlDiff), 0.10, 0.42, 0.20, 0.28, 0.94, 0.42, 0.42, 0.96, 0.54)
    elseif comp.ilvlDiff and comp.ilvlDiff < 0 then
        SetVerdictPillVisual(f, string.format("%d iLvl", comp.ilvlDiff), 0.48, 0.14, 0.14, 1.0, 0.42, 0.38, 1.0, 0.58, 0.54)
    elseif (comp.ownedCount or 0) > 0 then
        SetVerdictPillVisual(f, "x" .. tostring(comp.ownedCount), 0.12, 0.30, 0.52, 0.34, 0.72, 1.0, 0.52, 0.82, 1.0)
    elseif comp.isEquippable then
        SetVerdictPillVisual(f, "= iLvl", 0.16, 0.18, 0.22, 0.58, 0.64, 0.72, 0.78, 0.82, 0.88)
    else
        SetVerdictPillVisual(f, nil)
    end

    f.compHdr:ClearAllPoints()
    f.compHdr:SetPoint("TOPLEFT", f.compBox, "TOPLEFT", 10, -7)
    if f.compVerdictPill:IsShown() then
        f.compHdr:SetPoint("RIGHT", f.compVerdictPill, "LEFT", -8, 0)
    elseif hasSwap then
        f.compHdr:SetPoint("RIGHT", f.slotSwapBtn, "LEFT", -8, 0)
    else
        f.compHdr:SetPoint("RIGHT", f.compBox, "RIGHT", -10, 0)
    end

    if not comp.isEquippable then
        local typeHdr = comp.itemType and (comp.itemSubType and (comp.itemType .. " · " .. comp.itemSubType) or comp.itemType) or L["Not equippable / Non-gear drop"]
        f.compHdr:SetText("|cff9da7b5" .. typeHdr .. "|r")
        for i = 1, 6 do
            if f.compStatCells[i] then f.compStatCells[i]:Hide() end
        end
        local noteTxt = FormatNonGearComparisonNote(comp)
        f.compNoteFs:ClearAllPoints()
        f.compNoteFs:SetPoint("TOPLEFT", f.compBox, "TOPLEFT", 10, -26)
        f.compNoteFs:SetPoint("TOPRIGHT", f.compBox, "TOPRIGHT", -10, -26)
        f.compNoteFs:SetText(noteTxt)
        f.compNoteFs:Show()
        local noteH = math.max(14, math.ceil(f.compNoteFs:GetStringHeight() or 14))
        local compH = 32 + noteH
        f.compBox:SetHeight(compH)
        return compH
    end

    local slotLabel = comp.slotLabel or (comp.equipLoc and _G[comp.equipLoc]) or L["Equipped"]
    if comp.isEmptySlot then
        f.compHdr:SetText("|cff47ef66" .. string.format(L["Slot Comparison (%s): Empty slot!"], slotLabel) .. "|r")
    else
        local eqIlvlStr = (comp.equippedILvl and comp.equippedILvl > 0) and (" |cff8b949e(" .. tostring(comp.equippedILvl) .. ")|r") or ""
        local cleanEq = comp.vsComboLabel or ExtractCleanLinkDisplay(comp.equippedLink) or L["None"]
        f.compHdr:SetText("|cff8b949evs " .. slotLabel .. " · |r" .. cleanEq .. eqIlvlStr)
    end

    local warnTxt = nil
    if comp.uniqueOwned then
        warnTxt = "|cffffb833" .. L["Unique item already owned"] .. "|r"
    elseif comp.canEquip == false and comp.unusableReason then
        warnTxt = "|cffff5555" .. tostring(comp.unusableReason) .. "|r"
    elseif comp.wrongArmor and comp.unusableReason then
        warnTxt = "|cffffb833" .. tostring(comp.unusableReason) .. "|r"
    end

    local gridTopY = -26
    if warnTxt then
        f.compNoteFs:ClearAllPoints()
        f.compNoteFs:SetPoint("TOPLEFT", f.compBox, "TOPLEFT", 10, -25)
        f.compNoteFs:SetPoint("TOPRIGHT", f.compBox, "TOPRIGHT", -10, -25)
        f.compNoteFs:SetText(warnTxt)
        f.compNoteFs:Show()
        gridTopY = -42
    else
        f.compNoteFs:Hide()
    end

    -- Sort positive gains before negative losses for crisp 2-column visual scanning (never duplicating iLvl!)
    local orderedDiffs = {}
    for _, d in ipairs(comp.diffs or {}) do
        if d and d.delta and d.delta > 0 then orderedDiffs[#orderedDiffs + 1] = d end
    end
    for _, d in ipairs(comp.diffs or {}) do
        if d and d.delta and d.delta < 0 then orderedDiffs[#orderedDiffs + 1] = d end
    end

    local shownStats = math.min(6, #orderedDiffs)
    for i = 1, 6 do
        local cell = f.compStatCells[i]
        if cell then
            if i <= shownStats then
                local d = orderedDiffs[i]
                local col = (i - 1) % 2
                local rowIdx = math.floor((i - 1) / 2)
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", f.compBox, "TOPLEFT", 10 + (col * 178), gridTopY - (rowIdx * 16))
                local fmtNum = (d.key == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT") and string.format("%.1f", math.abs(d.delta)) or tostring(math.abs(d.delta))
                if d.delta > 0 then
                    local hex = (comp.canEquip == false) and "|cff9da7b5" or "|cff47ef66"
                    cell:SetText(string.format("%s+%s|r |cffe6edf3%s|r", hex, fmtNum, tostring(d.label)))
                else
                    cell:SetText(string.format("|cffff7b72-%s|r |cff9da7b5%s|r", fmtNum, tostring(d.label)))
                end
                cell:Show()
            else
                cell:Hide()
            end
        end
    end

    local statRows = math.ceil(shownStats / 2)
    if statRows == 0 and not warnTxt then
        f.compNoteFs:ClearAllPoints()
        f.compNoteFs:SetPoint("TOPLEFT", f.compBox, "TOPLEFT", 10, -25)
        f.compNoteFs:SetPoint("TOPRIGHT", f.compBox, "TOPRIGHT", -10, -25)
        f.compNoteFs:SetText("|cff8b949e" .. L["Identical stats to your currently equipped item."] .. "|r")
        f.compNoteFs:Show()
        f.compBox:SetHeight(44)
        return 44
    end

    local compH = math.abs(gridTopY) + (statRows * 16) + 6
    f.compBox:SetHeight(compH)
    return compH
end

local function RefreshStackedMode(f, active, unvotedCount)
    f.tabsRow:Hide()
    f.itemCard:Hide()
    f.compBox:Hide()
    f.actRow:Hide()
    if f.bopConfirmRow then f.bopConfirmRow:Hide() end
    if f.statusWrap then f.statusWrap:Hide() end
    f.stackBox:Show()

    local shownCards = math.min(MAX_STACKED_CARDS, #active)
    local overflowCards = math.max(0, #active - MAX_STACKED_CARDS)
    for sIdx = 1, MAX_STACKED_CARDS do
        local sr = f.stackBox._rows[sIdx]
        local r = (sIdx <= shownCards) and active[sIdx] or nil
        if sr and r then
            sr._rollId = r.rollID
            sr.icoBtn._itemLink = r.link
            sr.icoBtn._itemName = r.name
            sr.icoBtn._tex:SetTexture(r.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            local qr, qg, qb = QualityRGB(r.quality)
            sr.icoBtn._border:SetVertexColor(qr, qg, qb, 0.95)
            if r.count and r.count > 1 then
                sr.icoBtn._qtyBadge:SetText(tostring(r.count))
                sr.icoBtn._qtyBadge:Show()
            else
                sr.icoBtn._qtyBadge:Hide()
            end
            local qtyTxt = (r.count and r.count > 1) and (" x" .. tostring(r.count)) or ""
            sr.titleFs:SetText(QualityHex(r.quality) .. tostring(r.name or "?") .. "|r" .. qtyTxt)

            local rComp = r.comparison or {}
            local subStr
            if r.winnerName then
                subStr = FormatChoiceIconTag("WON", 12) .. " |cffffea70" .. tostring(r.winnerName) .. (r.winnerRoll and (" [" .. tostring(r.winnerRoll) .. "]") or "") .. "|r"
            elseif r.allPassed then
                subStr = "|cff8b949e" .. L["All passed"] .. "|r"
            else
                local vTag = ""
                if rComp.verdict == "UNIQUE_OWNED" then vTag = "|cffffb833" .. L["Unique"] .. "|r · "
                elseif rComp.verdict == "CANNOT_EQUIP" then vTag = "|cffff5555" .. L["Cannot Equip"] .. "|r · "
                elseif rComp.verdict == "WRONG_ARMOR" then vTag = "|cffffb833" .. L["Wrong Armor"] .. "|r · "
                elseif rComp.verdict == "RECIPE_YOU" then vTag = "|cff47ef66" .. L["Can Learn"] .. "|r · "
                elseif rComp.verdict == "RECIPE_KNOWN" then vTag = "|cffff9b3d" .. L["Known"] .. "|r · "
                elseif rComp.verdict == "RECIPE_ALT" then vTag = "|cff58b8ff" .. L["Alt Needs"] .. "|r · "
                elseif rComp.verdict == "EMPTY" then vTag = "|cff47ef66" .. L["EMPTY"] .. "|r · "
                elseif rComp.ilvlDiff and rComp.ilvlDiff > 0 then vTag = string.format("|cff47ef66+%d iLvl|r · ", rComp.ilvlDiff)
                elseif rComp.ilvlDiff and rComp.ilvlDiff < 0 then vTag = string.format("|cffff7b72%d iLvl|r · ", rComp.ilvlDiff)
                end
                local bindTag = r.bindOnPickUp and "|cffffb84dBoP|r" or "|cff79c0ffBoE|r"
                local ilvlTag = (rComp.candidateILvl and rComp.candidateILvl > 0) and ("|cff9da7b5iLvl " .. tostring(rComp.candidateILvl) .. "|r · ") or ""
                subStr = vTag .. ilvlTag .. bindTag
            end
            sr.subFs:SetText(subStr)

            if r.pendingConfirm and not r.resolved then
                sr.btnNeed:Hide()
                sr.btnGreed:Hide()
                sr.btnDE:Hide()
                sr.btnPass:Hide()
                sr.statusFs:Hide()
                ns.Theme:SetButtonText(sr.bopBtn, L["Confirm BoP"])
                sr.bopBtn:Show()
                sr.titleFs:SetPoint("RIGHT", sr.bopBtn, "LEFT", -8, 0)
                sr.subFs:SetPoint("RIGHT", sr.bopBtn, "LEFT", -8, 0)
            elseif r.myChoice or r.resolved or r.allPassed then
                sr.btnNeed:Hide()
                sr.btnGreed:Hide()
                sr.btnDE:Hide()
                sr.btnPass:Hide()
                sr.bopBtn:Hide()
                if r.winnerName then
                    sr.statusFs:SetText("|cffffea70" .. L["Won"] .. "|r")
                elseif r.allPassed then
                    sr.statusFs:SetText("|cff8b949e" .. L["Pass"] .. "|r")
                else
                    local cIco = FormatChoiceIconTag(r.myChoice, 13)
                    local cHex = ns.LootRoll:GetChoiceColor(r.myChoice)
                    sr.statusFs:SetText(cIco .. " " .. cHex .. ns.LootRoll:GetRollChoiceLabel(r.myChoice) .. "|r")
                end
                sr.statusFs:Show()
                sr.titleFs:SetPoint("RIGHT", sr.statusFs, "LEFT", -8, 0)
                sr.subFs:SetPoint("RIGHT", sr.statusFs, "LEFT", -8, 0)
            else
                sr.bopBtn:Hide()
                sr.statusFs:Hide()
                local showDE = (r.canDisenchant == true)
                sr.btnPass:Show()
                sr.btnDE:SetShown(showDE)
                sr.btnGreed:ClearAllPoints()
                if showDE then
                    sr.btnGreed:SetPoint("RIGHT", sr.btnDE, "LEFT", -4, 0)
                else
                    sr.btnGreed:SetPoint("RIGHT", sr.btnPass, "LEFT", -4, 0)
                end
                sr.btnGreed:Show()
                sr.btnNeed:Show()
                SyncIconButtonState(sr.btnNeed, r.canNeed == true)
                SyncIconButtonState(sr.btnGreed, r.canGreed == true)
                SyncIconButtonState(sr.btnDE, showDE)
                SyncIconButtonState(sr.btnPass, true)
                sr.titleFs:SetPoint("RIGHT", sr.btnNeed, "LEFT", -8, 0)
                sr.subFs:SetPoint("RIGHT", sr.btnNeed, "LEFT", -8, 0)
            end
            sr:Show()
        elseif sr then
            sr._rollId = nil
            sr:Hide()
        end
    end

    local stackH = (shownCards * 50)
    if overflowCards > 0 then
        f.stackBox.moreFs:SetText("|cff9da7b5" .. string.format(L["+%d more drops — click layout icon to browse all tabs"], overflowCards) .. "|r")
        f.stackBox.moreFs:Show()
        stackH = stackH + 18
    else
        f.stackBox.moreFs:Hide()
    end
    f.stackBox:SetHeight(stackH)

    local drawer = f.picksDrawer
    local drawerH = 0
    if drawer then
        drawer._hasWinner = false
        for idx = 1, MAX_DRAWER_ROWS do
            local dr = drawer._rows[idx]
            if dr then dr:Hide() end
        end
        if drawer.tallyBtn then drawer.tallyBtn:Hide() end
        if drawer.moreBtn then drawer.moreBtn:Hide() end
        if unvotedCount >= 2 and drawer.batchBar then
            drawer:ClearAllPoints()
            drawer:SetPoint("TOPLEFT", f.stackBox, "BOTTOMLEFT", 0, 0)
            drawer:SetPoint("TOPRIGHT", f.stackBox, "BOTTOMRIGHT", 0, 0)
            drawer.batchBar:Show()
            drawerH = 31
            drawer:SetHeight(drawerH)
            drawer:Show()
        else
            if drawer.batchBar then drawer.batchBar:Hide() end
            drawer:Hide()
        end
    end
    f:SetHeight(36 + stackH + drawerH)
end

function LootRollUI:Refresh()
    self:SyncResultsButton()
    if self.resultsWindow and self.resultsWindow:IsShown() then
        self:RefreshResultsWindow()
    end

    local active = ns.LootRoll:GetActiveList()
    local hasSimActive = false
    for _, r in ipairs(active) do
        if r and r.isSimulated then
            hasSimActive = true
            break
        end
    end
    if not (ns.LootRoll and ns.LootRoll.IsEnabled and ns.LootRoll:IsEnabled()) and not hasSimActive then
        if self.frame and self.frame:IsShown() then
            self.frame:Hide()
        end
        self:SyncOfficialRollBarVisibility()
        return
    end
    if #active == 0 then
        self.selectedRollID = nil
        self._userClosedActive = nil
        if self.frame and self.frame:IsShown() then
            self.frame:Hide()
        end
        self:SyncOfficialRollBarVisibility()
        return
    end
    if self._userClosedActive then
        self:SyncOfficialRollBarVisibility()
        return
    end
    self:SyncOfficialRollBarVisibility()

    local f = self:EnsureFrame()
    if not f then return end
    self:ApplyTheme()

    local selectedRec = nil
    local selectedIdx = 1
    if self.selectedRollID then
        for idx, r in ipairs(active) do
            if r.rollID == self.selectedRollID then
                selectedRec = r
                selectedIdx = idx
                break
            end
        end
    end
    if not selectedRec then
        selectedRec = active[1]
        selectedIdx = 1
        self.selectedRollID = selectedRec.rollID
    end

    local unvotedCount = 0
    for _, r in ipairs(active) do
        if not r.myChoice and not r.resolved then
            unvotedCount = unvotedCount + 1
        end
    end
    if unvotedCount > 0 and #active > 1 then
        f.titleFs:SetText(string.format("%s (%d)", L["Group Loot Roll"], unvotedCount))
    else
        f.titleFs:SetText(L["Group Loot Roll"])
    end

    local hasMulti = (#active >= 2)
    local displayMode = (ns.LootRoll and ns.LootRoll.GetDisplayMode and ns.LootRoll:GetDisplayMode()) or "tabbed"
    local useStacked = (displayMode == "stacked" and hasMulti)
    if f.stackModeBtn then
        f.stackModeBtn:SetShown(hasMulti)
        SyncLayoutIconVisual(f.stackModeBtn, displayMode == "stacked")
        if ns.Theme and ns.Theme.SetButtonActive then
            ns.Theme:SetButtonActive(f.stackModeBtn, displayMode == "stacked", "default")
        end
    end
    if f.resultsBtn then
        f.resultsBtn:ClearAllPoints()
        if hasMulti and f.stackModeBtn then
            f.resultsBtn:SetPoint("RIGHT", f.stackModeBtn, "LEFT", -3, 0)
        else
            f.resultsBtn:SetPoint("RIGHT", f.lockBtn, "LEFT", -3, 0)
        end
    end

    f:SetWidth(CARD_WIDTH)
    local topQr, topQg, topQb = QualityRGB(selectedRec.quality)
    if f.topAccentBar then
        f.topAccentBar:SetVertexColor(topQr, topQg, topQb, 0.95)
    end

    if useStacked and f.stackBox then
        RefreshStackedMode(f, active, unvotedCount)
        if not f:IsShown() then
            f:Show()
            if f.Raise then f:Raise() end
        end
        return
    end

    -- Detailed Single / Tabbed Card Mode
    if f.stackBox then f.stackBox:Hide() end
    f.itemCard:Show()
    f.compBox:Show()
    f.actRow:Show()

    local showTabs = hasMulti
    f.tabsRow:SetShown(showTabs)
    f.actRow:ClearAllPoints()
    if showTabs then
        f.actRow:SetPoint("TOPLEFT", f.tabsRow, "BOTTOMLEFT", 0, 0)
        f.actRow:SetPoint("TOPRIGHT", f.tabsRow, "BOTTOMRIGHT", 0, 0)

        if f.tabsCountFs then
            if unvotedCount > 0 then
                f.tabsCountFs:SetText("|cffffd24d" .. string.format(L["%d pending"], unvotedCount) .. "|r")
            else
                f.tabsCountFs:SetText(string.format("|cff8b949e%d / %d|r", selectedIdx, #active))
            end
        end

        local totalActive = #active
        local paged = (totalActive > MAX_TAB_SLOTS)
        local maxOffset = math.max(0, totalActive - MAX_TAB_SLOTS)
        if not paged then
            self.tabPageOffset = 0
        else
            if selectedIdx <= (self.tabPageOffset or 0) then
                self.tabPageOffset = selectedIdx - 1
            elseif selectedIdx > ((self.tabPageOffset or 0) + MAX_TAB_SLOTS) then
                self.tabPageOffset = selectedIdx - MAX_TAB_SLOTS
            end
            self.tabPageOffset = math.max(0, math.min(maxOffset, self.tabPageOffset or 0))
        end

        f.tabPrevBtn:SetShown(paged)
        f.tabNextBtn:SetShown(paged)
        f.tabPrevBtn:SetEnabled((self.tabPageOffset or 0) > 0)
        f.tabNextBtn:SetEnabled((self.tabPageOffset or 0) < maxOffset)

        local prevTab = paged and f.tabPrevBtn or nil
        local shownTabs = math.min(MAX_TAB_SLOTS, totalActive)
        for slot = 1, MAX_TAB_SLOTS do
            local rIdx = (self.tabPageOffset or 0) + slot
            local r = (slot <= shownTabs) and active[rIdx] or nil
            local tBtn = f.rollTabBtns[slot]
            if r then
                if not tBtn then
                    tBtn = ns.Theme:CreateButton(f.tabsRow, 52, 21, "", "default")
                    local tLayer = tBtn._textLayer or tBtn
                    local tWash = tBtn:CreateTexture(nil, "ARTWORK", nil, -1)
                    tWash:SetPoint("TOPLEFT", tBtn, "TOPLEFT", 1, -1)
                    tWash:SetPoint("BOTTOMRIGHT", tBtn, "BOTTOMRIGHT", -1, 1)
                    tWash:SetTexture(WHITE8X8)
                    tBtn._selWash = tWash
                    local tQual = tLayer:CreateTexture(nil, "OVERLAY", nil, 3)
                    tQual:SetHeight(2)
                    tQual:SetPoint("BOTTOMLEFT", tBtn, "BOTTOMLEFT", 1, 1)
                    tQual:SetPoint("BOTTOMRIGHT", tBtn, "BOTTOMRIGHT", -1, 1)
                    tQual:SetTexture(WHITE8X8)
                    tBtn._qualBar = tQual
                    local tIcoBg = tLayer:CreateTexture(nil, "OVERLAY", nil, 1)
                    tIcoBg:SetSize(16, 16)
                    tIcoBg:SetPoint("LEFT", tBtn, "LEFT", 4, 0)
                    tIcoBg:SetTexture(WHITE8X8)
                    tBtn._tabIcoBg = tIcoBg
                    local tIco = tLayer:CreateTexture(nil, "OVERLAY", nil, 2)
                    tIco:SetSize(14, 14)
                    tIco:SetPoint("CENTER", tIcoBg, "CENTER", 0, 0)
                    tIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    tBtn._tabIco = tIco
                    local tDot = tLayer:CreateTexture(nil, "OVERLAY", nil, 4)
                    tDot:SetSize(6, 6)
                    tDot:SetPoint("TOPRIGHT", tBtn, "TOPRIGHT", -3, -3)
                    tDot:SetTexture(ICON_DOT)
                    tBtn._statusDot = tDot
                    tBtn._scLeftPad = 18
                    tBtn:SetScript("OnClick", function(selfBtn)
                        if selfBtn._rollId then
                            LootRollUI.selectedRollID = selfBtn._rollId
                            LootRollUI:Refresh()
                        end
                    end)
                    tBtn:SetScript("OnEnter", function(selfBtn)
                        local rec = selfBtn._rollId and ns.LootRoll and ns.LootRoll:GetRollByID(selfBtn._rollId)
                        if rec and rec.link and rec.link ~= "" then
                            ShowItemHoverTooltip(selfBtn, rec.link, true)
                        end
                    end)
                    tBtn:SetScript("OnLeave", HideItemHoverTooltip)
                    f.rollTabBtns[slot] = tBtn
                end
                tBtn._rollId = r.rollID
                local isSel = (r.rollID == self.selectedRollID)
                ns.Theme:StyleButton(tBtn, "default")
                local tqr, tqg, tqb = QualityRGB(r.quality)
                if tBtn._selWash then
                    tBtn._selWash:SetVertexColor(tqr, tqg, tqb, isSel and 0.18 or 0.0)
                end
                if tBtn._qualBar then
                    tBtn._qualBar:SetVertexColor(tqr, tqg, tqb, isSel and 1.0 or 0.35)
                end
                if tBtn._tabIcoBg then
                    tBtn._tabIcoBg:SetVertexColor(tqr, tqg, tqb, 0.90)
                end
                if tBtn._statusDot then
                    if r.resolved then
                        tBtn._statusDot:SetVertexColor(1.0, 0.84, 0.24, 1.0)
                    elseif r.pendingConfirm then
                        tBtn._statusDot:SetVertexColor(1.0, 0.56, 0.18, 1.0)
                    elseif r.myChoice then
                        tBtn._statusDot:SetVertexColor(0.28, 0.92, 0.44, 1.0)
                    else
                        tBtn._statusDot:SetVertexColor(1.0, 0.78, 0.26, 0.95)
                    end
                end
                local targetTex = r.texture or ICON_DICE
                if tBtn._tabIco and tBtn._lastTabIcoTex ~= targetTex then
                    tBtn._lastTabIcoTex = targetTex
                    tBtn._tabIco:SetTexture(targetTex)
                end
                local tabPosSig = (paged and "P:" or "S:") .. tostring(prevTab or "ROOT")
                if tBtn._lastTabPosSig ~= tabPosSig then
                    tBtn._lastTabPosSig = tabPosSig
                    tBtn:ClearAllPoints()
                    if prevTab then
                        tBtn:SetPoint("LEFT", prevTab, "RIGHT", 4, 0)
                    else
                        tBtn:SetPoint("LEFT", f.tabsRow, "LEFT", 8, 0)
                    end
                    tBtn:SetSize(paged and 46 or 50, 21)
                end
                ns.Theme:SetButtonText(tBtn, string.format("#%d", rIdx))
                tBtn:Show()
                prevTab = tBtn
            elseif tBtn then
                tBtn._rollId = nil
                tBtn:Hide()
            end
        end
    else
        f.tabPrevBtn:Hide()
        f.tabNextBtn:Hide()
        f.actRow:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, 0)
        f.actRow:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT", 0, 0)
    end
    f.itemCard:ClearAllPoints()
    f.itemCard:SetPoint("TOPLEFT", f.actRow, "BOTTOMLEFT", 0, 0)
    f.itemCard:SetPoint("TOPRIGHT", f.actRow, "BOTTOMRIGHT", 0, 0)

    -- Hero Item Row
    f.iconBtn._itemLink = selectedRec.link
    f.iconBtn._itemName = selectedRec.name
    f.iconBtn._tex:SetTexture(selectedRec.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    f.iconBtn._border:SetVertexColor(topQr, topQg, topQb, 0.96)
    if f.heroGlow then
        f.heroGlow:SetVertexColor(topQr, topQg, topQb, 0.14)
    end
    if selectedRec.count and selectedRec.count > 1 then
        f.iconBtn._qtyBadge:SetText(tostring(selectedRec.count))
        f.iconBtn._qtyBadge:Show()
    else
        f.iconBtn._qtyBadge:Hide()
    end
    local qtyTxt = (selectedRec.count and selectedRec.count > 1) and (" x" .. tostring(selectedRec.count)) or ""
    f.itemTitle:SetText(QualityHex(selectedRec.quality) .. tostring(selectedRec.name or "?") .. "|r" .. qtyTxt)

    local comp = selectedRec.comparison or {}
    local slotTxt = (comp.equipLoc and _G[comp.equipLoc]) or comp.itemSubType or ""
    local ilvlTxt = (comp.candidateILvl and comp.candidateILvl > 0) and (L["iLvl %d"]:format(comp.candidateILvl)) or ""
    local metaParts = {}
    if ilvlTxt ~= "" then metaParts[#metaParts + 1] = "|cffd0d7de" .. ilvlTxt .. "|r" end
    if slotTxt ~= "" then metaParts[#metaParts + 1] = "|cff8b949e" .. slotTxt .. "|r" end
    f.itemMeta:SetText(table.concat(metaParts, "  ·  "))

    if f.bindPill then
        if selectedRec.bindOnPickUp then
            f.bindPill.text:SetText("BoP")
            f.bindPill.text:SetTextColor(1.0, 0.74, 0.30)
            f.bindPill._bg:SetVertexColor(0.55, 0.34, 0.08, 0.42)
        else
            f.bindPill.text:SetText("BoE")
            f.bindPill.text:SetTextColor(0.54, 0.82, 1.0)
            f.bindPill._bg:SetVertexColor(0.12, 0.30, 0.54, 0.42)
        end
        local bpW = math.max(30, math.ceil(f.bindPill.text:GetStringWidth() or 24) + 10)
        f.bindPill:SetWidth(bpW)
        f.bindPill:Show()
    end

    -- Structured 2-Column Comparison Section (dynamic height, zero empty black void!)
    local compH = UpdateComparisonSection(f, comp)

    -- Tally live choices, current leader, ties & waiting teammates
    local picksList = {}
    local winnerChoiceRec = nil
    local countsByChoice = { NEED = 0, GREED = 0, DE = 0, PASS = 0 }
    local votedKeys = {}
    if ns.LootRoll and ns.LootRoll.ComputeCurrentLeader then
        ns.LootRoll:ComputeCurrentLeader(selectedRec)
    end
    local leadCount = 0
    for ck, cRec in pairs(selectedRec.choices or {}) do
        picksList[#picksList + 1] = cRec
        votedKeys[ck] = true
        if cRec.name then
            local pLk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(cRec.name)) or tostring(cRec.name):lower()
            votedKeys[pLk] = true
        end
        if cRec.won == true then
            winnerChoiceRec = cRec
        end
        if cRec.isLeading == true then
            leadCount = leadCount + 1
        end
        if cRec.choice and countsByChoice[cRec.choice] ~= nil then
            countsByChoice[cRec.choice] = countsByChoice[cRec.choice] + 1
        end
    end
    if ns.LootRoll and ns.LootRoll.SortChoicesList then
        ns.LootRoll:SortChoicesList(picksList)
    end
    local leadIsTied = (not winnerChoiceRec and not selectedRec.resolved and leadCount > 1)

    local pendingVoters = {}
    if (not selectedRec.resolved) and (not selectedRec.isSimulated) and ns.Group and type(ns.Group.members) == "table" then
        for _, gm in ipairs(ns.Group.members) do
            if type(gm) == "table" and gm.name and gm.online ~= false then
                local gLk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(gm.name)) or tostring(gm.name):lower()
                if not votedKeys[gLk] then
                    pendingVoters[#pendingVoters + 1] = gm.name
                end
            end
        end
    end

    -- Action Row: Inline BoP Confirm > Status Pill > Semantic Roll Buttons
    if selectedRec.pendingConfirm and not selectedRec.resolved then
        f.btnNeed:Hide()
        f.btnGreed:Hide()
        f.btnDE:Hide()
        f.btnPass:Hide()
        if f.statusWrap then f.statusWrap:Hide() end
        if f.bopConfirmRow then
            local pendChoice = selectedRec.pendingConfirm.choice or "NEED"
            local pendLbl = ns.LootRoll:GetRollChoiceLabel(pendChoice)
            if f.bopConfirmBtn._lootIco then
                f.bopConfirmBtn._lootIco:SetTexture(GetChoiceIconTexture(pendChoice) or CHOICE_ICONS.NEED)
            end
            ns.Theme:SetButtonText(f.bopConfirmBtn, string.format(L["Confirm BoP: %s"], pendLbl))
            f.bopConfirmRow:Show()
        end
    elseif selectedRec.myChoice or winnerChoiceRec or selectedRec.allPassed then
        if f.bopConfirmRow then f.bopConfirmRow:Hide() end
        f.btnNeed:Hide()
        f.btnGreed:Hide()
        f.btnDE:Hide()
        f.btnPass:Hide()
        if winnerChoiceRec then
            local wName = tostring(winnerChoiceRec.name or selectedRec.winnerName or "?")
            local wRoll = winnerChoiceRec.roll or selectedRec.winnerRoll
            local winIco = FormatChoiceIconTag("WON", 15)
            local winRollStr = wRoll and (" [" .. tostring(wRoll) .. "]") or ""
            f.statusBanner:SetText(winIco .. " |cffffea70" .. string.format(L["Winner: %s"], wName) .. winRollStr .. "|r")
            if f.statusWrap and f.statusWrap._bg then f.statusWrap._bg:SetVertexColor(0.55, 0.42, 0.10, 0.30) end
        elseif selectedRec.allPassed then
            local passIco = FormatChoiceIconTag("PASS", 15)
            f.statusBanner:SetText(passIco .. "  |cff9da7b5" .. L["All passed"] .. "|r")
            if f.statusWrap and f.statusWrap._bg then f.statusWrap._bg:SetVertexColor(0.18, 0.20, 0.24, 0.32) end
        else
            local choiceLbl = ns.LootRoll:GetRollChoiceLabel(selectedRec.myChoice)
            local choiceHex = ns.LootRoll:GetChoiceColor(selectedRec.myChoice)
            local choiceIco = FormatChoiceIconTag(selectedRec.myChoice, 15)
            local leadName, leadRoll = ns.LootRoll:ComputeCurrentLeader(selectedRec)
            local tail = ""
            if leadName and leadName ~= "" then
                local lr = leadRoll and (" " .. tostring(leadRoll)) or ""
                local tieSuffix = leadIsTied and (" |cffff9b3d(" .. L["Tied!"] .. ")|r") or ""
                tail = "  |cff9da7b5· " .. L["Leading:"] .. "|r |cffffd24d" .. leadName .. lr .. "|r" .. tieSuffix
            end
            f.statusBanner:SetText(choiceIco .. " " .. choiceHex .. choiceLbl .. "|r" .. tail)
            if f.statusWrap and f.statusWrap._bg then f.statusWrap._bg:SetVertexColor(0.10, 0.32, 0.18, 0.28) end
        end
        if f.statusWrap then f.statusWrap:Show() end
    else
        if f.bopConfirmRow then f.bopConfirmRow:Hide() end
        if f.statusWrap then f.statusWrap:Hide() end
        SyncIconButtonState(f.btnNeed, selectedRec.canNeed == true)
        SyncIconButtonState(f.btnGreed, selectedRec.canGreed == true)
        SyncIconButtonState(f.btnPass, true)
        local showDE = (selectedRec.canDisenchant == true)
        f.btnDE:SetShown(showDE)
        SyncIconButtonState(f.btnDE, showDE)
        f.btnNeed:Show()
        f.btnGreed:Show()
        f.btnPass:Show()

        local rowBtns = showDE and { f.btnNeed, f.btnGreed, f.btnDE, f.btnPass } or { f.btnNeed, f.btnGreed, f.btnPass }
        local bGap = showDE and 5 or 6
        local bW = math.floor((CARD_INNER_W - ((#rowBtns - 1) * bGap)) / #rowBtns)
        local totalW = (#rowBtns * bW) + ((#rowBtns - 1) * bGap)
        local startX = math.floor(((CARD_WIDTH - 4) - totalW) * 0.5)
        for i, b in ipairs(rowBtns) do
            b:SetSize(bW, 34)
            b:ClearAllPoints()
            b:SetPoint("LEFT", f.actRow, "LEFT", startX + ((i - 1) * (bW + bGap)), 0)
        end
    end

    -- Integrated Live Party Votes & Multi-Drop Batch Footer (inside the single unified card!)
    local drawer = f.picksDrawer
    local drawerH = 0
    local tipRows = {}
    local shownRows = math.min(MAX_DRAWER_ROWS, #picksList)
    local overflowCount = math.max(0, #picksList - MAX_DRAWER_ROWS)
    local showBatchBar = (unvotedCount >= 2 and drawer and drawer.batchBar ~= nil)
    local hasTally = (#picksList > 0 or #pendingVoters > 0)

    if drawer then
        drawer._hasWinner = false
        drawer._pendingVoters = pendingVoters
        drawer:ClearAllPoints()
        drawer:SetPoint("TOPLEFT", f.compBox, "BOTTOMLEFT", 0, 0)
        drawer:SetPoint("TOPRIGHT", f.compBox, "BOTTOMRIGHT", 0, 0)

        if not hasTally and not showBatchBar then
            for idx = 1, MAX_DRAWER_ROWS do
                local r = drawer._rows[idx]
                if r then
                    r._isWinner = false
                    r._playerName = nil
                    if r.winAura then r.winAura:Hide() end
                    if r.winEdgeTop then r.winEdgeTop:Hide() end
                    if r.winEdgeBot then r.winEdgeBot:Hide() end
                    if r.winShimmer then r.winShimmer:Hide() end
                    r:Hide()
                end
            end
            if drawer.tallyBtn then drawer.tallyBtn:Hide() end
            if drawer.moreBtn then drawer.moreBtn:Hide() end
            if drawer.batchBar then drawer.batchBar:Hide() end
            drawer:Hide()
        else
            if drawer.tallyBtn then
                drawer.tallyBtn:SetShown(hasTally)
                if hasTally then
                    local sumBits = {}
                    if countsByChoice.NEED > 0 then sumBits[#sumBits + 1] = FormatChoiceIconTag("NEED", 13) .. " |cff47ef66" .. tostring(countsByChoice.NEED) .. "|r" end
                    if countsByChoice.GREED > 0 then sumBits[#sumBits + 1] = FormatChoiceIconTag("GREED", 13) .. " |cffffd24d" .. tostring(countsByChoice.GREED) .. "|r" end
                    if countsByChoice.DE > 0 then sumBits[#sumBits + 1] = FormatChoiceIconTag("DE", 13) .. " |cffb980ff" .. tostring(countsByChoice.DE) .. "|r" end
                    if countsByChoice.PASS > 0 then sumBits[#sumBits + 1] = FormatChoiceIconTag("PASS", 13) .. " |cff8b949e" .. tostring(countsByChoice.PASS) .. "|r" end
                    if #pendingVoters > 0 and not selectedRec.resolved then
                        sumBits[#sumBits + 1] = "|cff58b8ff" .. string.format(L["Waiting: %d"], #pendingVoters) .. "|r"
                    end
                    drawer.summaryFs:SetText(table.concat(sumBits, "   "))
                    drawer.collapseFs:SetText("|cff8b949e" .. (self.votesCollapsed and L["Show"] or L["Hide"]) .. "|r")
                    if drawer.collapseIco then
                        drawer.collapseIco:SetTexture(self.votesCollapsed and ICON_ARROW_DOWN or ICON_ARROW_UP)
                    end
                end
            end

            local showRowsNow = hasTally and (not self.votesCollapsed)
            local visibleRows = showRowsNow and shownRows or 0
            for idx = 1, MAX_DRAWER_ROWS do
                local row = drawer._rows[idx]
                local pr = (idx <= visibleRows) and picksList[idx] or nil
                if row and pr then
                    local isWon = (pr.won == true)
                    local isLead = (not isWon and not selectedRec.resolved and pr.isLeading == true)
                    row._isWinner = isWon
                    row._playerName = tostring(pr.name or "?")
                    row._isMe = (pr.isMe == true)
                    if isWon then
                        drawer._hasWinner = true
                    end
                    local voteKey = pr.choice or (isWon and "WON") or "PASS"
                    local vTex = GetChoiceIconTexture(voteKey) or CHOICE_ICONS.PASS
                    row.voteIco:SetTexture(vTex)
                    row.voteIco:SetAlpha((voteKey == "PASS") and 0.72 or 1.0)

                    if row.winAura then row.winAura:SetShown(isWon) end
                    if row.winEdgeTop then row.winEdgeTop:SetShown(isWon) end
                    if row.winEdgeBot then row.winEdgeBot:SetShown(isWon) end
                    if row.winShimmer then row.winShimmer:SetShown(isWon) end

                    row.nameFs:ClearAllPoints()
                    if isWon then
                        row.winIco:Show()
                        row.nameFs:SetPoint("LEFT", row.winIco, "RIGHT", 4, 0)
                    else
                        row.winIco:Hide()
                        row.nameFs:SetPoint("LEFT", row.voteIco, "RIGHT", 6, 0)
                    end
                    row.nameFs:SetPoint("RIGHT", row.rollFs, "LEFT", -8, 0)

                    local cHex = isWon and "|cffffea70"
                        or ((pr.choice == "PASS") and "|cff8b949e" or ((pr.classFile and Compat and Compat.ClassHex and Compat.ClassHex(pr.classFile)) or "|cffe6edf3"))
                    local youTag = (pr.isMe == true) and (" |cff8cc2ff(" .. L["You"] .. ")|r") or ""
                    local tieTag = (isLead and leadIsTied) and (" |cffff9b3d[" .. L["TIE"] .. "]|r") or ""
                    row.nameFs:SetText(cHex .. tostring(pr.name) .. "|r" .. youTag .. tieTag)

                    local pickHex = isWon and "|cffffea70" or ns.LootRoll:GetChoiceColor(pr.choice)
                    local pickLbl = ns.LootRoll:GetRollChoiceLabel(isWon and "WON" or pr.choice)
                    local rightStr
                    if pr.roll then
                        if isWon then
                            rightStr = pickHex .. L["Won"] .. " " .. tostring(pr.roll) .. "|r"
                        elseif isLead then
                            rightStr = LEAD_STAR_TAG .. " " .. ns.LootRoll:GetChoiceColor(pr.choice) .. ns.LootRoll:GetRollChoiceLabel(pr.choice) .. " · " .. tostring(pr.roll) .. "|r"
                        else
                            rightStr = ns.LootRoll:GetChoiceColor(pr.choice) .. ns.LootRoll:GetRollChoiceLabel(pr.choice) .. " · " .. tostring(pr.roll) .. "|r"
                        end
                    else
                        rightStr = pickHex .. pickLbl .. "|r"
                    end
                    row.rollFs:SetText(rightStr)
                    row:Show()
                elseif row then
                    row._isWinner = false
                    row._playerName = nil
                    if row.winAura then row.winAura:Hide() end
                    if row.winEdgeTop then row.winEdgeTop:Hide() end
                    if row.winEdgeBot then row.winEdgeBot:Hide() end
                    if row.winShimmer then row.winShimmer:Hide() end
                    row:Hide()
                end
            end

            for _, pr in ipairs(picksList) do
                local isWon = (pr.won == true)
                local voteKey = pr.choice or (isWon and "WON") or "PASS"
                local cHex = isWon and "|cffffea70"
                    or ((pr.choice == "PASS") and "|cff8b949e" or ((pr.classFile and Compat and Compat.ClassHex and Compat.ClassHex(pr.classFile)) or "|cffe6edf3"))
                local pickHex = isWon and "|cffffea70" or ns.LootRoll:GetChoiceColor(pr.choice)
                local pickLbl = ns.LootRoll:GetRollChoiceLabel(isWon and "WON" or pr.choice)
                local winPrefix = isWon and (FormatChoiceIconTag("WON", 13) .. " ") or ""
                local voteTag = FormatChoiceIconTag(voteKey, 14)
                local tipRoll = pr.roll and (" [" .. tostring(pr.roll) .. "]") or ""
                tipRows[#tipRows + 1] = winPrefix .. voteTag .. " " .. cHex .. tostring(pr.name) .. "|r — " .. pickHex .. pickLbl .. tipRoll .. "|r"
            end

            local showMore = (showRowsNow and overflowCount > 0)
            if drawer.batchBar then
                drawer.batchBar:SetShown(showBatchBar)
            end
            if drawer.moreBtn then
                if showMore then
                    drawer.moreBtn:ClearAllPoints()
                    drawer.moreBtn:SetPoint("BOTTOMLEFT", drawer, "BOTTOMLEFT", 10, showBatchBar and 33 or 4)
                    drawer.moreBtn:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMRIGHT", -10, showBatchBar and 33 or 4)
                    ns.Theme:SetButtonText(drawer.moreBtn, string.format(L["+%d more — Open Full Results"], overflowCount))
                    drawer.moreBtn:Show()
                else
                    drawer.moreBtn:Hide()
                end
            end

            drawerH = (hasTally and 24 or 0)
                + (visibleRows > 0 and ((visibleRows * 18) + 4) or 0)
                + (showMore and 20 or 0)
                + (showBatchBar and 31 or 0)
            drawer:SetHeight(math.max(1, drawerH))
            drawer:Show()
        end
        drawer._tooltipRows = tipRows
    end

    if f.compBox and f.compBox._botDiv then
        f.compBox._botDiv:SetShown(drawerH > 0)
    end
    local totalH = 34 + (showTabs and 27 or 0) + 44 + 66 + compH + drawerH + 4
    f:SetHeight(totalH)

    if not f:IsShown() then
        f:Show()
        if f.Raise then f:Raise() end
    end
end

function LootRollUI:Init()
    self:InstallOfficialLootHooks()
    ns.RegisterEvent(self, "START_LOOT_ROLL", function()
        self._userClosedActive = false
        self:SyncOfficialRollBarVisibility()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() self:SyncOfficialRollBarVisibility() end)
        end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if self._pendingOfficialLootSync then
            self._pendingOfficialLootSync = nil
            self:SyncOfficialRollBarVisibility()
        end
    end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        self:SyncResultsButton()
    end)
    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", function()
        self:SyncResultsButton()
    end)
    ns:On("LOOT_ROLL_VISIBILITY_CHANGED", function()
        self:SyncResultsButton()
    end)
    ns:On("LOOT_ROLL_FIRST_PROMPT", function(rec)
        self:ShowFirstRollPrompt(rec)
    end)
    ns:On("LOOT_ROLL_UPDATED", function()
        self:Refresh()
    end)
    ns:On("LOOT_ROLL_WINNER", function(rec)
        if rec and rec.winnerIsMe == true and ((not ns.LootRoll) or not ns.LootRoll.IsWinnerToastEnabled or ns.LootRoll:IsWinnerToastEnabled()) then
            self:QueueEpicWinAnimation(rec)
        end
        self:SyncResultsButton()
        if self.resultsWindow and self.resultsWindow:IsShown() then
            self:RefreshResultsWindow()
        end
    end)
    ns:On("LOOT_ROLL_RESULTS_READ", function()
        self:SyncResultsButton()
    end)
    ns:On("LOOT_CHAT_ROLL_UPDATED", function()
        if self.resultsWindow and self.resultsWindow:IsShown() and self.resultsSubTab == "chatroll" then
            self:RefreshResultsWindow()
        end
    end)
    ns:On("SETTINGS_UPDATED", function()
        self:SyncOfficialRollBarVisibility()
        self:Refresh()
    end)
    if ns.Theme and ns.Theme.RegisterListener then
        ns.Theme:RegisterListener(function()
            if self.frame and self.frame:IsShown() then self:ApplyTheme() end
            if self.promptFrame and self.promptFrame:IsShown() then
                local p = ns.Theme:GetPalette()
                ns.Theme:ApplyBackdrop(self.promptFrame, "window", p)
                ApplySolidOpaqueBg(self.promptFrame, p)
            end
            if self.resultsBtnFrame and self.resultsBtnFrame:IsShown() then self:SyncResultsButton() end
            if self.resultsWindow and self.resultsWindow:IsShown() then self:ApplyResultsWindowTheme() end
        end)
    end
    self:SyncOfficialRollBarVisibility()
    self:SyncResultsButton()
end
