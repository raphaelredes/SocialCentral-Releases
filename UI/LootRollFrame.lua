local ADDON_NAME, ns = ...
local L = ns.L
local Safe = ns.Safe
local Compat = ns.Compat

local LootRollUI = {
    selectedRollID = nil,
}
ns.LootRollUI = LootRollUI
table.insert(ns.modules, LootRollUI)

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local ICON_TEX = "Interface\\AddOns\\SocialCentral\\Media\\icon.tga"
local CHOICE_ICONS = {
    NEED = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    GREED = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    DE = "Interface\\Buttons\\UI-GroupLoot-DE-Up",
    PASS = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
    WON = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
}

local function GetChoiceIconTexture(choiceKey)
    return CHOICE_ICONS[choiceKey]
end

local function ApplyDefaultLootRollPlacement(win)
    if not (win and UIParent) then return end
    win:ClearAllPoints()
    win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -110, 148)
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

local function ApplyIconOnlyLootButton(btn, texPath, iconSize)
    if not btn then return end
    if ns.Theme and ns.Theme.SetButtonText then
        ns.Theme:SetButtonText(btn, "")
    end
    local sz = iconSize or 26
    local ico = (btn._textLayer or btn):CreateTexture(nil, "OVERLAY", nil, 2)
    ico:SetSize(sz, sz)
    ico:SetPoint("CENTER", btn, "CENTER", 0, 0)
    ico:SetTexture(texPath)
    btn._lootIco = ico
end

local function SyncIconButtonState(btn, enabled)
    if not btn then return end
    btn:SetEnabled(enabled == true)
    if btn._lootIco then
        btn._lootIco:SetAlpha((enabled == true) and 1.0 or 0.35)
        if btn._lootIco.SetDesaturated then
            btn._lootIco:SetDesaturated(enabled ~= true)
        end
    end
end

function LootRollUI:EnsurePromptFrame()
    if self.promptFrame then
        return self.promptFrame
    end
    local Theme = ns.Theme
    if not Theme then return nil end

    local pFrame = CreateFrame("Frame", "SocialCentralLootRollPrompt", UIParent, "BackdropTemplate")
    pFrame:Hide()
    pFrame:SetSize(392, 206)
    pFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    pFrame:SetClampedToScreen(true)
    table.insert(UISpecialFrames, "SocialCentralLootRollPrompt")
    if pFrame.hideOfficialCb then
        pFrame.hideOfficialCb:SetChecked(true)
    end
    Theme:PrepareTopOverlayModal(pFrame, 850)

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
        L["Shows a sleek SocialCentral roll card on group drops with Need/Greed/Disenchant/Pass buttons, automatic stat & item level comparison against your equipped gear, live teammate choices, roll numbers, and the final winner."],
        L["Choose Enable Now to start using it right on this drop (you can also hide WoW's official roll bar so they don't overlap), or Keep Default anytime in Settings -> Summary & Windows."],
        16
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
    itemSub:SetTextColor(0.75, 0.80, 0.88)
    itemSub:SetText(L["Compare item stats & see live rolls from your party!"])

    local descFs = pFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    descFs:SetPoint("TOPLEFT", itemIco, "BOTTOMLEFT", 0, -10)
    descFs:SetPoint("TOPRIGHT", pFrame, "TOPRIGHT", -14, -68)
    descFs:SetJustifyH("LEFT")
    descFs:SetWordWrap(true)
    descFs:SetText(L["Would you like to activate SocialCentral's Group Loot Roll mini-window with equipped-gear comparison and live party choices?"])

    local hideOfficialCb = CreateFrame("CheckButton", nil, pFrame, "UICheckButtonTemplate")
    hideOfficialCb:SetSize(22, 22)
    hideOfficialCb:SetPoint("TOPLEFT", descFs, "BOTTOMLEFT", -2, -6)
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
    pFrame:SetWidth(math.max(392, enW + skW + 48))
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
    if pFrame._solidOpaqueBg then
        local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
        pFrame._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
    end
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

function LootRollUI:EnsureFrame()
    if self.frame then
        return self.frame
    end
    local Theme = ns.Theme
    if not Theme then return nil end

    local f = CreateFrame("Frame", "SocialCentralLootRollFrame", UIParent, "BackdropTemplate")
    f:Hide()
    f:SetSize(276, 166)
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

    local hdr = CreateFrame("Frame", nil, f, "BackdropTemplate")
    hdr:SetPoint("TOPLEFT", 5, -5)
    hdr:SetPoint("TOPRIGHT", -5, -5)
    hdr:SetHeight(20)
    f.header = hdr

    local hIco = hdr:CreateTexture(nil, "ARTWORK")
    hIco:SetSize(14, 14)
    hIco:SetPoint("LEFT", hdr, "LEFT", 5, 0)
    hIco:SetTexture(ICON_TEX)

    local closeBtn = Theme:CreateButton(hdr, 18, 16, "X", "default")
    closeBtn:SetPoint("RIGHT", hdr, "RIGHT", -3, 0)
    closeBtn:SetScript("OnClick", function()
        LootRollUI._userClosedActive = true
        f:Hide()
        if LootRollUI.SyncOfficialRollBarVisibility then
            LootRollUI:SyncOfficialRollBarVisibility()
        end
    end)
    f.closeBtn = closeBtn

    local helpBtn = Theme:CreateHelpButton(
        hdr,
        L["Help: Group Loot Roll Window"],
        L["Shows active group loot drops with Need, Greed, Disenchant, and Pass buttons, real-time teammate choices, roll numbers, and winners alongside automatic item level & stat deltas against your equipped slot."],
        L["Hover the item icon to inspect the full tooltip, Shift+Click it to link in chat, or switch tabs at the top when multiple items drop at once."],
        14
    )
    helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
    f.helpBtn = helpBtn

    local titleFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleFs:SetPoint("LEFT", hIco, "RIGHT", 5, 0)
    titleFs:SetPoint("RIGHT", helpBtn, "LEFT", -5, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetWordWrap(false)
    titleFs:SetText(L["Group Loot Roll"])
    f.titleFs = titleFs

    Theme:MakeMovable(f, {
        key = "loot_roll_helper",
        handles = { hdr, f },
        onReset = ApplyDefaultLootRollPlacement,
    })

    -- Multi-item selector tabs row (visible when 2+ rolls are active)
    local tabsRow = CreateFrame("Frame", nil, f)
    tabsRow:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -3)
    tabsRow:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", 0, -3)
    tabsRow:SetHeight(18)
    tabsRow:Hide()
    f.tabsRow = tabsRow
    f.rollTabBtns = {}

    -- Item Hero Box
    local itemCard = CreateFrame("Frame", nil, f, "BackdropTemplate")
    itemCard:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -4)
    itemCard:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", 0, -4)
    itemCard:SetHeight(42)
    f.itemCard = itemCard

    local iconBtn = CreateFrame("Button", nil, itemCard)
    iconBtn:SetSize(30, 30)
    iconBtn:SetPoint("LEFT", itemCard, "LEFT", 6, 2)
    local iconBorder = iconBtn:CreateTexture(nil, "BACKGROUND")
    iconBorder:SetAllPoints(iconBtn)
    iconBorder:SetTexture(WHITE8X8)
    iconBtn._border = iconBorder
    local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT", 2, -2)
    iconTex:SetPoint("BOTTOMRIGHT", -2, 2)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconBtn._tex = iconTex
    iconBtn:SetScript("OnEnter", function(selfBtn)
        if not (GameTooltip and selfBtn._itemLink) then return end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, selfBtn._itemLink)
        GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    iconBtn:SetScript("OnClick", function(selfBtn)
        if IsShiftKeyDown and IsShiftKeyDown() and selfBtn._itemLink and ChatEdit_InsertLink then
            pcall(ChatEdit_InsertLink, selfBtn._itemLink)
        end
    end)
    f.iconBtn = iconBtn

    local itemTitle = itemCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemTitle:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 7, -1)
    itemTitle:SetPoint("RIGHT", itemCard, "RIGHT", -6, 0)
    itemTitle:SetJustifyH("LEFT")
    itemTitle:SetWordWrap(false)
    f.itemTitle = itemTitle

    local itemMeta = itemCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemMeta:SetPoint("BOTTOMLEFT", iconBtn, "BOTTOMRIGHT", 7, 1)
    itemMeta:SetPoint("RIGHT", itemCard, "RIGHT", -6, 0)
    itemMeta:SetJustifyH("LEFT")
    itemMeta:SetWordWrap(false)
    f.itemMeta = itemMeta

    local timerBg = itemCard:CreateTexture(nil, "BACKGROUND", nil, 1)
    timerBg:SetHeight(3)
    timerBg:SetPoint("BOTTOMLEFT", itemCard, "BOTTOMLEFT", 5, 2)
    timerBg:SetPoint("BOTTOMRIGHT", itemCard, "BOTTOMRIGHT", -5, 2)
    timerBg:SetTexture(WHITE8X8)
    timerBg:SetVertexColor(0.14, 0.16, 0.20, 1.0)
    local timerFill = itemCard:CreateTexture(nil, "ARTWORK", nil, 2)
    timerFill:SetHeight(3)
    timerFill:SetPoint("TOPLEFT", timerBg, "TOPLEFT", 0, 0)
    timerFill:SetWidth(100)
    timerFill:SetTexture(WHITE8X8)
    timerFill:SetVertexColor(0.88, 0.68, 0.22, 1.0)
    f.timerBg = timerBg
    f.timerFill = timerFill

    -- Gear Comparison Panel (fixed height so main roll buttons never jump vertically)
    local compBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
    compBox:SetPoint("TOPLEFT", itemCard, "BOTTOMLEFT", 0, -4)
    compBox:SetPoint("TOPRIGHT", itemCard, "BOTTOMRIGHT", 0, -4)
    compBox:SetHeight(52)
    f.compBox = compBox

    local compHdr = compBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    compHdr:SetPoint("TOPLEFT", compBox, "TOPLEFT", 6, -4)
    compHdr:SetPoint("TOPRIGHT", compBox, "TOPRIGHT", -6, -4)
    compHdr:SetJustifyH("LEFT")
    compHdr:SetWordWrap(false)
    f.compHdr = compHdr

    local compLines = compBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    compLines:SetPoint("TOPLEFT", compHdr, "BOTTOMLEFT", 0, -2)
    compLines:SetPoint("BOTTOMRIGHT", compBox, "BOTTOMRIGHT", -6, 4)
    compLines:SetJustifyH("LEFT")
    compLines:SetJustifyV("TOP")
    compLines:SetWordWrap(true)
    compLines:SetSpacing(1)
    f.compLines = compLines

    -- Action Buttons Row (Icon-Only Need / Greed / Disenchant / Pass)
    local actRow = CreateFrame("Frame", nil, f)
    actRow:SetPoint("TOPLEFT", compBox, "BOTTOMLEFT", 0, -4)
    actRow:SetPoint("TOPRIGHT", compBox, "BOTTOMRIGHT", 0, -4)
    actRow:SetHeight(34)
    f.actRow = actRow

    local btnNeed = Theme:CreateButton(actRow, 48, 32, "", "primary")
    ApplyIconOnlyLootButton(btnNeed, "Interface\\Buttons\\UI-GroupLoot-Dice-Up", 26)

    local btnGreed = Theme:CreateButton(actRow, 48, 32, "", "default")
    ApplyIconOnlyLootButton(btnGreed, "Interface\\Buttons\\UI-GroupLoot-Coin-Up", 26)

    local btnDE = Theme:CreateButton(actRow, 48, 32, "", "default")
    ApplyIconOnlyLootButton(btnDE, "Interface\\Buttons\\UI-GroupLoot-DE-Up", 26)

    local btnPass = Theme:CreateButton(actRow, 48, 32, "", "default")
    ApplyIconOnlyLootButton(btnPass, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", 24)

    local statusBanner = actRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusBanner:SetAllPoints(actRow)
    statusBanner:SetJustifyH("CENTER")
    statusBanner:Hide()
    f.statusBanner = statusBanner

    local function BindRollButton(btn, rollType, reasonKey, helpTitle, helpDesc)
        btn:SetScript("OnClick", function()
            if LootRollUI.selectedRollID and ns.LootRoll then
                local curId = LootRollUI.selectedRollID
                ns.LootRoll:SubmitRoll(curId, rollType)
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.9, function()
                        if LootRollUI.selectedRollID == curId and ns.LootRoll then
                            for _, r in ipairs(ns.LootRoll:GetActiveList()) do
                                if not r.myChoice then
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
        btn:SetScript("OnEnter", function(selfBtn)
            local rec = LootRollUI.selectedRollID and ns.LootRoll and ns.LootRoll:GetRollByID(LootRollUI.selectedRollID)
            local reason = reasonKey and rec and rec[reasonKey]
            if not GameTooltip then return end
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
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
        btn:SetScript("OnLeave", function()
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

    -- Docked Expandable Votes Drawer below the main roll card (grows downward without moving or resizing main card)
    local picksDrawer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    picksDrawer:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -3)
    picksDrawer:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -3)
    picksDrawer:SetHeight(24)
    picksDrawer:SetFrameStrata("DIALOG")
    picksDrawer:SetFrameLevel(535)
    picksDrawer:EnableMouse(true)
    picksDrawer:Hide()

    local dBg = picksDrawer:CreateTexture(nil, "BACKGROUND", nil, -8)
    dBg:SetAllPoints(picksDrawer)
    dBg:SetTexture(WHITE8X8)
    dBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    picksDrawer._solidOpaqueBg = dBg

    picksDrawer:SetScript("OnEnter", function(selfBox)
        if not (GameTooltip and selfBox._tooltipRows and #selfBox._tooltipRows > 0) then return end
        GameTooltip:SetOwner(selfBox, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(string.format(L["Live Party Choices (%d):"], #selfBox._tooltipRows), 1.0, 0.85, 0.28)
        for _, line in ipairs(selfBox._tooltipRows) do
            GameTooltip:AddLine(line, 0.92, 0.94, 0.98, true)
        end
        GameTooltip:Show()
    end)
    picksDrawer:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    picksDrawer._rows = {}
    for idx = 1, 8 do
        local row = CreateFrame("Frame", nil, picksDrawer)
        row:SetHeight(16)
        if row.SetClipsChildren then row:SetClipsChildren(true) end
        row:SetPoint("TOPLEFT", picksDrawer, "TOPLEFT", 7, -5 - ((idx - 1) * 16))
        row:SetPoint("TOPRIGHT", picksDrawer, "TOPRIGHT", -7, -5 - ((idx - 1) * 16))
        row:Hide()

        local voteIco = row:CreateTexture(nil, "ARTWORK")
        voteIco:SetSize(14, 14)
        voteIco:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.voteIco = voteIco

        local winAura = row:CreateTexture(nil, "BACKGROUND", nil, -1)
        winAura:SetAllPoints(row)
        winAura:SetTexture(WHITE8X8)
        winAura:SetVertexColor(1.0, 0.78, 0.16, 0.24)
        winAura:Hide()
        row.winAura = winAura

        local winEdgeTop = row:CreateTexture(nil, "ARTWORK", nil, 0)
        winEdgeTop:SetHeight(1)
        winEdgeTop:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        winEdgeTop:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        winEdgeTop:SetTexture(WHITE8X8)
        winEdgeTop:SetVertexColor(1.0, 0.86, 0.30, 0.78)
        winEdgeTop:Hide()
        row.winEdgeTop = winEdgeTop

        local winEdgeBot = row:CreateTexture(nil, "ARTWORK", nil, 0)
        winEdgeBot:SetHeight(1)
        winEdgeBot:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        winEdgeBot:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        winEdgeBot:SetTexture(WHITE8X8)
        winEdgeBot:SetVertexColor(1.0, 0.86, 0.30, 0.78)
        winEdgeBot:Hide()
        row.winEdgeBot = winEdgeBot

        local winShimmer = row:CreateTexture(nil, "OVERLAY", nil, 4)
        winShimmer:SetTexture("Interface\\AddOns\\SocialCentral\\Media\\toast-glow.tga")
        winShimmer:SetBlendMode("ADD")
        winShimmer:SetSize(56, 22)
        winShimmer:SetPoint("LEFT", row, "LEFT", 0, 0)
        winShimmer:SetVertexColor(1.0, 0.90, 0.42, 0.55)
        winShimmer:Hide()
        row.winShimmer = winShimmer

        local winIco = row:CreateTexture(nil, "ARTWORK", nil, 2)
        winIco:SetSize(13, 13)
        winIco:SetPoint("LEFT", voteIco, "RIGHT", 2, 0)
        winIco:SetTexture(CHOICE_ICONS.WON)
        winIco:Hide()
        row.winIco = winIco

        local rollFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rollFs:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        rollFs:SetJustifyH("RIGHT")
        rollFs:SetWordWrap(false)
        row.rollFs = rollFs

        local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFs:SetPoint("LEFT", voteIco, "RIGHT", 5, 0)
        nameFs:SetPoint("RIGHT", rollFs, "LEFT", -6, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(false)
        row.nameFs = nameFs

        picksDrawer._rows[idx] = row
    end
    if Theme.AttachDragHandle then
        Theme:AttachDragHandle(f, picksDrawer)
    end
    f.picksDrawer = picksDrawer

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
        selfFrame._animElapsed = (selfFrame._animElapsed or 0) + (elapsed or 0)
        if selfFrame._animElapsed < 0.033 then
            return
        end
        selfFrame._animElapsed = 0

        local d = selfFrame.picksDrawer
        if d and d._hasWinner and d:IsShown() then
            local pulse = 0.5 + 0.5 * math.sin(nowMono * 4.5)
            local sweep = (nowMono * 0.72) % 1.0
            local sweepAlpha = math.sin(sweep * math.pi)
            for idx = 1, 6 do
                local rw = d._rows and d._rows[idx]
                if rw and rw._isWinner and rw:IsShown() then
                    if rw.winAura then
                        rw.winAura:SetAlpha(0.16 + 0.16 * pulse)
                    end
                    if rw.winEdgeTop then
                        rw.winEdgeTop:SetAlpha(0.55 + 0.40 * pulse)
                    end
                    if rw.winEdgeBot then
                        rw.winEdgeBot:SetAlpha(0.55 + 0.40 * pulse)
                    end
                    if rw.winShimmer then
                        local rwW = math.max(120, rw:GetWidth() or 230)
                        local sx = math.floor((sweep * (rwW + 30)) - 30)
                        if rw._lastShimmerX ~= sx then
                            rw._lastShimmerX = sx
                            rw.winShimmer:ClearAllPoints()
                            rw.winShimmer:SetPoint("LEFT", rw, "LEFT", sx, 0)
                        end
                        rw.winShimmer:SetAlpha(0.18 + 0.52 * sweepAlpha)
                    end
                end
            end
        end
        local rec = LootRollUI.selectedRollID and ns.LootRoll and ns.LootRoll:GetRollByID(LootRollUI.selectedRollID)
        if not rec or not selfFrame.timerBg or not selfFrame.timerFill then return end
        local fullW = math.max(40, (selfFrame.timerBg:GetWidth() or 350))
        if rec.myChoice then
            if selfFrame._lastTimerChoiceDone ~= rec.rollID or selfFrame._lastTimerFullW ~= fullW then
                selfFrame._lastTimerChoiceDone = rec.rollID
                selfFrame._lastTimerFullW = fullW
                selfFrame._lastTimerPx = nil
                selfFrame.timerFill:SetWidth(fullW)
                selfFrame.timerFill:SetVertexColor(0.32, 0.78, 0.45, 0.85)
            end
            return
        end
        if selfFrame._lastTimerChoiceDone ~= nil then
            selfFrame._lastTimerChoiceDone = nil
            selfFrame.timerFill:SetVertexColor(0.88, 0.68, 0.22, 1.0)
        end
        local remMs
        if rec.isSimulated then
            remMs = math.max(0, ((rec.simExpiresAt or 0) - nowMono) * 1000)
        else
            remMs = GetLootRollTimeLeft and Safe.Number(Safe.Call(GetLootRollTimeLeft, rec.rollID)) or 0
        end
        local totalMs = math.max(1000, (tonumber(rec.durationSec) or 60) * 1000)
        local frac = math.max(0.02, math.min(1.0, remMs / totalMs))
        local wantPx = math.max(2, math.floor((fullW * frac) + 0.5))
        if selfFrame._lastTimerPx ~= wantPx then
            selfFrame._lastTimerPx = wantPx
            selfFrame.timerFill:SetWidth(wantPx)
        end
    end

    f:HookScript("OnShow", function(selfFrame)
        selfFrame._animElapsed = 0.04
        selfFrame._lastTimerPx = nil
        selfFrame._lastTimerChoiceDone = nil
        selfFrame:SetScript("OnUpdate", OnRollFrameUpdate)
    end)
    f:HookScript("OnHide", function(selfFrame)
        selfFrame:SetScript("OnUpdate", nil)
    end)

    self.frame = f
    return f
end

function LootRollUI:ApplyTheme()
    local f = self.frame
    local Theme = ns.Theme
    if not (f and Theme) then return end
    local p = Theme:GetPalette()
    if f._solidOpaqueBg then
        local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
        f._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
    end
    Theme:ApplyBackdrop(f, "window", p)
    Theme:ApplyBackdrop(f.header, "header", p)
    Theme:ApplyBackdrop(f.itemCard, "inset", p)
    Theme:ApplyBackdrop(f.compBox, "inset", p)
    if f.picksDrawer then
        if f.picksDrawer._solidOpaqueBg then
            local bg = (p and p.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
            f.picksDrawer._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
        end
        Theme:ApplyBackdrop(f.picksDrawer, "window", p)
    end
end

function LootRollUI:ShouldSuppressOfficialRollBar()
    if not (ns.LootRoll and ns.LootRoll.IsEnabled and ns.LootRoll:IsEnabled()) then
        return false
    end
    if not (ns.LootRoll.IsHideOfficialEnabled and ns.LootRoll:IsHideOfficialEnabled()) then
        return false
    end
    if self._userClosedActive then
        return false
    end
    local active = ns.LootRoll:GetActiveList()
    return (#active > 0) and true or false
end

function LootRollUI:SyncSingleOfficialLootFrame(frame, shouldHide, isContainer)
    if not frame then return end
    if frame.IsForbidden and frame:IsForbidden() then return end

    if not frame._scLootHideHooked and frame.HookScript then
        frame._scLootHideHooked = true
        frame:HookScript("OnShow", function(selfFrame)
            if LootRollUI and LootRollUI.ShouldSuppressOfficialRollBar and LootRollUI:ShouldSuppressOfficialRollBar() then
                LootRollUI:SyncSingleOfficialLootFrame(selfFrame, true, selfFrame == _G.GroupLootContainer)
            end
        end)
    end

    local isProtected = frame.IsProtected and frame:IsProtected()
    local inCombat = InCombatLockdown and InCombatLockdown()
    if shouldHide then
        if inCombat and isProtected then
            self._pendingOfficialLootSync = true
            return
        end
        if frame.IsShown and frame:IsShown() then
            frame._scWasSuppressed = true
        end
        pcall(frame.SetAlpha, frame, 0)
        if not isProtected then
            pcall(frame.Hide, frame)
        end
    else
        if inCombat and isProtected then
            self._pendingOfficialLootSync = true
            return
        end
        pcall(frame.SetAlpha, frame, 1)
        if frame._scWasSuppressed then
            frame._scWasSuppressed = nil
            local shouldShow = false
            if isContainer then
                local maxFrames = Safe.Number(_G.NUM_GROUP_LOOT_FRAMES) or 8
                for i = 1, maxFrames do
                    local child = _G["GroupLootFrame" .. i]
                    local rId = child and child.rollID and Safe.Number(child.rollID)
                    local rem = rId and GetLootRollTimeLeft and Safe.Number(Safe.Call(GetLootRollTimeLeft, rId))
                    if rem and rem > 0 then
                        shouldShow = true
                        break
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
    local shouldHide = self:ShouldSuppressOfficialRollBar()
    local maxFrames = math.max(8, Safe.Number(_G.NUM_GROUP_LOOT_FRAMES) or 8)
    for i = 1, maxFrames do
        local f = _G["GroupLootFrame" .. i]
        if f then
            self:SyncSingleOfficialLootFrame(f, shouldHide, false)
        end
    end
    local container = _G.GroupLootContainer
    if container then
        if type(container.rollFrames) == "table" then
            for _, rf in ipairs(container.rollFrames) do
                self:SyncSingleOfficialLootFrame(rf, shouldHide, false)
            end
        end
        self:SyncSingleOfficialLootFrame(container, shouldHide, true)
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
    end
end

function LootRollUI:Refresh()
    if not (ns.LootRoll and ns.LootRoll.IsEnabled and ns.LootRoll:IsEnabled()) then
        if self.frame and self.frame:IsShown() then
            self.frame:Hide()
        end
        self:SyncOfficialRollBarVisibility()
        return
    end
    local active = ns.LootRoll:GetActiveList()
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
    if self.selectedRollID then
        for _, r in ipairs(active) do
            if r.rollID == self.selectedRollID then
                selectedRec = r
                break
            end
        end
    end
    if not selectedRec then
        selectedRec = active[1]
        self.selectedRollID = selectedRec.rollID
    end

    -- Multi-roll selector tabs when 2+ items drop simultaneously
    local showTabs = (#active >= 2)
    f.tabsRow:SetShown(showTabs)
    f.itemCard:ClearAllPoints()
    if showTabs then
        f.itemCard:SetPoint("TOPLEFT", f.tabsRow, "BOTTOMLEFT", 0, -3)
        f.itemCard:SetPoint("TOPRIGHT", f.tabsRow, "BOTTOMRIGHT", 0, -3)
        local prevTab = nil
        for idx, r in ipairs(active) do
            local tBtn = f.rollTabBtns[idx]
            if not tBtn then
                tBtn = ns.Theme:CreateButton(f.tabsRow, 46, 18, "", "default")
                tBtn:SetScript("OnClick", function(selfBtn)
                    if selfBtn._rollId then
                        LootRollUI.selectedRollID = selfBtn._rollId
                        LootRollUI:Refresh()
                    end
                end)
                f.rollTabBtns[idx] = tBtn
            end
            tBtn._rollId = r.rollID
            local isSel = (r.rollID == self.selectedRollID)
            ns.Theme:StyleButton(tBtn, isSel and "primary" or "default")
            tBtn:ClearAllPoints()
            if prevTab then
                tBtn:SetPoint("LEFT", prevTab, "RIGHT", 4, 0)
            else
                tBtn:SetPoint("LEFT", f.tabsRow, "LEFT", 0, 0)
            end
            ns.Theme:SetButtonText(tBtn, string.format("#%d%s", idx, (r.myChoice and " |cff47ef66*|r" or "")))
            ns.Theme:AutoFitButton(tBtn, 36, 10, 72)
            tBtn:Show()
            prevTab = tBtn
        end
        for idx = #active + 1, #f.rollTabBtns do
            f.rollTabBtns[idx]:Hide()
        end
    else
        f.itemCard:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -4)
        f.itemCard:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT", 0, -4)
    end

    -- Hero Item Row
    f.iconBtn._itemLink = selectedRec.link
    f.iconBtn._tex:SetTexture(selectedRec.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    local qr, qg, qb = QualityRGB(selectedRec.quality)
    f.iconBtn._border:SetVertexColor(qr, qg, qb, 0.9)
    local qtyTxt = (selectedRec.count and selectedRec.count > 1) and (" x" .. tostring(selectedRec.count)) or ""
    f.itemTitle:SetText(QualityHex(selectedRec.quality) .. tostring(selectedRec.name or "?") .. "|r" .. qtyTxt)

    local comp = selectedRec.comparison or {}
    local slotTxt = (comp.equipLoc and _G[comp.equipLoc]) or ""
    local ilvlTxt = (comp.candidateILvl and comp.candidateILvl > 0) and (L["iLvl %d"]:format(comp.candidateILvl)) or ""
    local bopTxt = selectedRec.bindOnPickUp and L["BoP"] or L["BoE / Trade"]
    local metaParts = {}
    if ilvlTxt ~= "" then metaParts[#metaParts + 1] = ilvlTxt end
    if slotTxt ~= "" then metaParts[#metaParts + 1] = slotTxt else metaParts[#metaParts + 1] = bopTxt end
    f.itemMeta:SetText("|cff9da7b5" .. table.concat(metaParts, " · ") .. "|r")

    -- Gear Comparison Box
    if not comp.isEquippable then
        f.compHdr:SetText("|cff9da7b5" .. L["Not equippable / Non-gear drop"] .. "|r")
        f.compLines:SetText("")
    else
        local slotLabel = (comp.equipLoc and _G[comp.equipLoc]) or L["Equipped"]
        if comp.isEmptySlot then
            f.compHdr:SetText("|cff47ef66" .. string.format(L["Slot Comparison (%s): Empty slot!"], slotLabel) .. "|r")
        else
            local eqIlvlStr = (comp.equippedILvl and comp.equippedILvl > 0) and (" (" .. tostring(comp.equippedILvl) .. ")") or ""
            f.compHdr:SetText("|cff9da7b5" .. tostring(comp.equippedLink or L["None"]) .. eqIlvlStr .. "|r")
        end

        local statStrs = {}
        if comp.ilvlDiff and comp.ilvlDiff ~= 0 then
            if comp.ilvlDiff > 0 then
                statStrs[#statStrs + 1] = string.format("|cff47ef66+%d iLvl|r", comp.ilvlDiff)
            else
                statStrs[#statStrs + 1] = string.format("|cffff7b72%d iLvl|r", comp.ilvlDiff)
            end
        elseif comp.candidateILvl and comp.candidateILvl > 0 and comp.equippedILvl == comp.candidateILvl then
            statStrs[#statStrs + 1] = "|cff9da7b5=iLvl|r"
        end
        for i = 1, math.min(4, #(comp.diffs or {})) do
            local d = comp.diffs[i]
            if d.delta > 0 then
                statStrs[#statStrs + 1] = string.format("|cff47ef66+%d %s|r", d.delta, tostring(d.label))
            else
                statStrs[#statStrs + 1] = string.format("|cffff7b72%d %s|r", d.delta, tostring(d.label))
            end
        end
        if #statStrs == 0 then
            f.compLines:SetText("|cff9da7b5" .. L["Identical stats to your currently equipped item."] .. "|r")
        else
            f.compLines:SetText(table.concat(statStrs, "  "))
        end
    end

    -- Roll Action Buttons (Centered Icon-Only Row)
    f:SetWidth(276)
    local picksList = {}
    local winnerChoiceRec = nil
    for _, cRec in pairs(selectedRec.choices or {}) do
        picksList[#picksList + 1] = cRec
        if cRec.won == true then
            winnerChoiceRec = cRec
        end
    end
    table.sort(picksList, function(a, b)
        if (a.won == true) ~= (b.won == true) then return a.won == true end
        local ra, rb = tonumber(a.roll) or -1, tonumber(b.roll) or -1
        if ra ~= rb then return ra > rb end
        return tostring(a.name or "") < tostring(b.name or "")
    end)

    if selectedRec.myChoice or winnerChoiceRec or selectedRec.allPassed then
        f.btnNeed:Hide()
        f.btnGreed:Hide()
        f.btnDE:Hide()
        f.btnPass:Hide()
        if winnerChoiceRec then
            local wName = tostring(winnerChoiceRec.name or selectedRec.winnerName or "?")
            local wRoll = winnerChoiceRec.roll or selectedRec.winnerRoll
            local winIco = FormatChoiceIconTag("WON", 15)
            local winRollStr = wRoll and ("  [" .. tostring(wRoll) .. "]") or ""
            f.statusBanner:SetText(winIco .. "  |cffffea70" .. string.format(L["Winner: %s"], wName) .. winRollStr .. "|r")
        elseif selectedRec.allPassed then
            local passIco = FormatChoiceIconTag("PASS", 15)
            f.statusBanner:SetText(passIco .. "  |cff9da7b5" .. L["All passed"] .. "|r")
        else
            local choiceLbl = ns.LootRoll:GetRollChoiceLabel(selectedRec.myChoice)
            local choiceHex = ns.LootRoll:GetChoiceColor(selectedRec.myChoice)
            local choiceIco = FormatChoiceIconTag(selectedRec.myChoice, 16)
            f.statusBanner:SetText(choiceIco .. "  " .. L["Your choice"] .. ": " .. choiceHex .. choiceLbl .. "|r")
        end
        f.statusBanner:Show()
    else
        f.statusBanner:Hide()
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
        local bW, bH, bGap = 46, 32, 8
        local totalW = (#rowBtns * bW) + ((#rowBtns - 1) * bGap)
        local startX = math.floor((266 - totalW) * 0.5)
        for i, b in ipairs(rowBtns) do
            b:SetSize(bW, bH)
            b:ClearAllPoints()
            b:SetPoint("LEFT", f.actRow, "LEFT", startX + ((i - 1) * (bW + bGap)), 0)
        end
    end

    f.compBox:SetHeight(52)
    f:SetHeight(showTabs and 187 or 166)

    -- Live Player Choices in separate bottom drawer (grows downward independently; zero shifting of main roll card)
    local drawer = f.picksDrawer
    local tipRows = {}
    local shownRows = math.min(8, #picksList)
    if drawer then
        drawer._hasWinner = false
        if shownRows == 0 then
            for idx = 1, 8 do
                local r = drawer._rows[idx]
                if r then
                    r._isWinner = false
                    if r.winAura then r.winAura:Hide() end
                    if r.winEdgeTop then r.winEdgeTop:Hide() end
                    if r.winEdgeBot then r.winEdgeBot:Hide() end
                    if r.winShimmer then r.winShimmer:Hide() end
                    r:Hide()
                end
            end
            drawer:Hide()
        else
            for idx = 1, 8 do
                local row = drawer._rows[idx]
                local pr = (idx <= shownRows) and picksList[idx] or nil
                if row and pr then
                    local isWon = (pr.won == true)
                    row._isWinner = isWon
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
                        row.nameFs:SetPoint("LEFT", row.voteIco, "RIGHT", 5, 0)
                    end
                    row.nameFs:SetPoint("RIGHT", row.rollFs, "LEFT", -6, 0)

                    local cHex = isWon and "|cffffea70"
                        or ((pr.choice == "PASS") and "|cff8b949e" or ((pr.classFile and Compat and Compat.ClassHex and Compat.ClassHex(pr.classFile)) or "|cffe6edf3"))
                    row.nameFs:SetText(cHex .. tostring(pr.name) .. "|r")

                    local pickHex = isWon and "|cffffea70" or ns.LootRoll:GetChoiceColor(pr.choice)
                    local pickLbl = ns.LootRoll:GetRollChoiceLabel(isWon and "WON" or pr.choice)
                    local rightStr
                    if pr.roll then
                        if isWon then
                            rightStr = pickHex .. L["Won"] .. " " .. tostring(pr.roll) .. "|r"
                        else
                            rightStr = ns.LootRoll:GetChoiceColor(pr.choice) .. ns.LootRoll:GetRollChoiceLabel(pr.choice) .. " · " .. tostring(pr.roll) .. "|r"
                        end
                    else
                        rightStr = pickHex .. pickLbl .. "|r"
                    end
                    row.rollFs:SetText(rightStr)

                    local winPrefix = isWon and (FormatChoiceIconTag("WON", 13) .. " ") or ""
                    local voteTag = FormatChoiceIconTag(voteKey, 14)
                    local tipRoll = pr.roll and (" [" .. tostring(pr.roll) .. "]") or ""
                    tipRows[#tipRows + 1] = winPrefix .. voteTag .. " " .. cHex .. tostring(pr.name) .. "|r — " .. pickHex .. pickLbl .. tipRoll .. "|r"
                    row:Show()
                elseif row then
                    row._isWinner = false
                    if row.winAura then row.winAura:Hide() end
                    if row.winEdgeTop then row.winEdgeTop:Hide() end
                    if row.winEdgeBot then row.winEdgeBot:Hide() end
                    if row.winShimmer then row.winShimmer:Hide() end
                    row:Hide()
                end
            end
            drawer:SetHeight(10 + (shownRows * 16))
            drawer:Show()
        end
        drawer._tooltipRows = tipRows
    end

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
    ns.On("LOOT_ROLL_FIRST_PROMPT", function(rec)
        self:ShowFirstRollPrompt(rec)
    end)
    ns:On("LOOT_ROLL_UPDATED", function()
        self:Refresh()
    end)
end
