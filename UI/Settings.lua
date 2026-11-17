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

local function HelpBtn(parent, anchorTo, title, whatText, howText)
    if not (ns.Theme and ns.Theme.CreateHelpButton) then
        return nil
    end
    local h = ns.Theme:CreateHelpButton(parent, title, whatText, howText, 18)
    h:SetPoint("LEFT", anchorTo, "RIGHT", 8, 0)
    return h
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
    valueText:SetWidth(76)
    valueText:SetJustifyH("CENTER")

    local plus = ns.Theme:CreateButton(row, 28, 24, "+", "default")
    plus:SetPoint("LEFT", valueText, "RIGHT", 10, 0)

    local function RefreshValue()
        valueText:SetText(string.format("%d %s", getter(), unit))
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
    return row
end

local function EnsurePanelFrame()
    if not panel then
        panel = CreateFrame("Frame", "SocialCentralSettingsPanel", UIParent)
        panel.name = "SocialCentral"
    end
    return panel
end

local function BuildPanel()
    if panelBuilt then
        return
    end
    panelBuilt = true
    EnsurePanelFrame()
    wipe(syncFns)

    -- Top Fixed Header & Category Navigation Tabs
    local headerArea = CreateFrame("Frame", nil, panel)
    headerArea:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    headerArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -10)
    headerArea:SetHeight(76)

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
    content:SetSize(610, 900)
    scrollFrame:SetScrollChild(content)

    local pages = {}
    local pageHeights = {
        overview = 680,
        notifications = 1600,
        radar = 740,
        general = 1260,
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

    local function SelectCategoryTab(tabId)
        if not pages[tabId] then tabId = "overview" end
        activeCategoryTab = tabId
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
        ns.Theme:AutoFitButton(btn, 98, 22, 190)
        if not prevTabBtn then
            btn:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 0, 0)
        else
            btn:SetPoint("LEFT", prevTabBtn, "RIGHT", 6, 0)
        end
        btn:SetScript("OnClick", function()
            SelectCategoryTab(spec.id)
        end)
        catButtons[#catButtons + 1] = { id = spec.id, btn = btn }
        prevTabBtn = btn
    end

    local function CloseSettingsBeforeJump()
        if not ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) then
            if HideUIPanel then
                if _G.SettingsPanel and _G.SettingsPanel.IsShown and _G.SettingsPanel:IsShown() then
                    pcall(HideUIPanel, _G.SettingsPanel)
                elseif _G.InterfaceOptionsFrame and _G.InterfaceOptionsFrame.IsShown and _G.InterfaceOptionsFrame:IsShown() then
                    pcall(HideUIPanel, _G.InterfaceOptionsFrame)
                end
            end
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

    -- =========================================================================
    -- TAB 1: SUMMARY & BLIZZARD WINDOWS (O / I / J / C / M + Quick Switches)
    -- =========================================================================
    local ov = pages.overview

    local winToggleHeader = AddSectionHeader(
        ov,
        L["Game Window Integrations (O / I / J / C / M)"],
        nil,
        -6,
        L["Help: Window Integrations"],
        L["Turn SocialCentral completely on or off inside each Blizzard window without affecting standalone '/sc hub' or other windows."],
        L["Uncheck any window below (for example Social (O), Group Finder (I), or Guild (J)) to leave that native Blizzard window untouched immediately."]
    )

    local winGrid = CreateFrame("Frame", nil, ov)
    winGrid:SetPoint("TOPLEFT", winToggleHeader, "BOTTOMLEFT", 0, -4)
    winGrid:SetSize(600, 118)

    local winLeft = CreateFrame("Frame", nil, winGrid)
    winLeft:SetPoint("TOPLEFT", winGrid, "TOPLEFT", 0, 0)
    winLeft:SetSize(294, 116)

    local winRight = CreateFrame("Frame", nil, winGrid)
    winRight:SetPoint("TOPLEFT", winLeft, "TOPRIGHT", 10, 0)
    winRight:SetSize(294, 116)

    local embSocCb = CreateGridCheckbox(
        winLeft,
        nil,
        -2,
        L["Social & Friends (O)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.embedSocialWindow ~= false end,
        function(checked)
            ns.db.settings.embedSocialWindow = checked
            NotifySettingChanged()
        end,
        L["Help: Integrate Social (O)"],
        L["Attaches the SocialCentral Watchlist, Social, Nearby, and Conversations side-tab to Blizzard's Friends/Social (O) window."],
        L["Uncheck to keep Blizzard's Friends (O) window 100% vanilla while still keeping '/sc hub' available."]
    )

    local embLfgCb = CreateGridCheckbox(
        winLeft,
        embSocCb,
        -4,
        L["Group Finder (I)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.embedLfgWindow ~= false end,
        function(checked)
            ns.db.settings.embedLfgWindow = checked
            NotifySettingChanged()
        end,
        L["Help: Integrate Group Finder (I)"],
        L["Attaches the Clans, Allies & Global Chat LFG side-tab inside Blizzard's Group Finder (I) window."],
        L["Uncheck to disable all Group Finder (I) integration cleanly without reload."]
    )

    local embGuildCb = CreateGridCheckbox(
        winLeft,
        embLfgCb,
        -4,
        L["Guild & Diplomacy (J)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.embedGuildWindow ~= false end,
        function(checked)
            ns.db.settings.embedGuildWindow = checked
            NotifySettingChanged("CLAN_UPDATED")
        end,
        L["Help: Integrate Guild (J)"],
        L["Attaches the Guild Hub, Events, Professions, and Diplomacy side-tab inside Blizzard's Guild / Communities (J) window."],
        L["Uncheck to leave Guild (J) completely vanilla. Also hides automatically on characters without a guild when the auto-hide option is enabled."]
    )

    local embCharCb = CreateGridCheckbox(
        winRight,
        nil,
        -2,
        L["Character & Alts (C)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.embedCharacterWindow ~= false end,
        function(checked)
            ns.db.settings.embedCharacterWindow = checked
            NotifySettingChanged()
        end,
        L["Help: Integrate Character (C)"],
        L["Attaches the My Alts side-tab (gold vault, equipped items, bags, and bank search) inside Blizzard's Character (C) window."],
        L["Uncheck to leave the Character (C) window 100% vanilla."]
    )

    local embMapCb = CreateGridCheckbox(
        winRight,
        embCharCb,
        -4,
        L["World Buffs on Map (M)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.embedWorldMap ~= false end,
        function(checked)
            ns.db.settings.embedWorldMap = checked
            NotifySettingChanged("WORLD_BUFFS_UPDATED")
        end,
        L["Help: Integrate World Map (M)"],
        L["Displays the compact World Buffs corner badge and zone pins on the World Map (M)."],
        L["Uncheck to disable all SocialCentral additions on the World Map completely."]
    )

    local autoHideGuildCb = CreateCheckbox(
        ov,
        L["Automatically hide Guild features when this character has no guild"],
        winGrid,
        -4,
        function() return not ns.db or not ns.db.settings or ns.db.settings.hideGuildFeaturesWhenNoGuild ~= false end,
        function(checked)
            ns.db.settings.hideGuildFeaturesWhenNoGuild = checked
            NotifySettingChanged("CLAN_UPDATED")
        end,
        L["Help: Auto-Hide Without Guild"],
        L["Automatically hides Guild (J) integration, Hub Guild tab, Alliance chat mirrors, and Guild shortcuts whenever you play a character with no guild."],
        L["Keep enabled so guildless characters stay clutter-free without manually turning Guild options off and on."]
    )

    local quickNotifHeader = AddSectionHeader(
        ov,
        L["Quick Notification Switches (1-Click Summary)"],
        autoHideGuildCb,
        -14,
        L["Help: Quick Notification Summary"],
        L["Master summary switches to silence or enable SocialCentral popups, sounds, and alerts at a glance without scrolling."],
        L["Each popup notification also has a crossed-bell icon you can click anytime (with a confirmation popup) to silence just that notification."]
    )

    local qGrid = CreateFrame("Frame", nil, ov)
    qGrid:SetPoint("TOPLEFT", quickNotifHeader, "BOTTOMLEFT", 0, -4)
    qGrid:SetSize(600, 180)

    local qLeft = CreateFrame("Frame", nil, qGrid)
    qLeft:SetPoint("TOPLEFT", qGrid, "TOPLEFT", 0, 0)
    qLeft:SetSize(294, 178)

    local qRight = CreateFrame("Frame", nil, qGrid)
    qRight:SetPoint("TOPLEFT", qLeft, "TOPRIGHT", 10, 0)
    qRight:SetSize(294, 178)

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
        qLeft, qAddonCb, -4, L["Chat Sounds (Master)"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.chatSound ~= false end,
        function(checked) ns.db.settings.chatSound = checked; NotifySettingChanged("CHAT_UPDATED") end,
        L["Help: Chat Sound Alert"],
        L["Master switch for incoming conversation sound chimes across SocialCentral."],
        L["Uncheck to mute all SocialCentral conversation chimes without affecting muted individual threads."]
    )

    local qWbCb = CreateGridCheckbox(
        qRight, nil, -2, L["World Buff Alerts"],
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
    local qRadarCb = CreateGridCheckbox(
        qRight, qClanLfgCb, -4, L["Screen Target Radar"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterEnabled ~= false end,
        function(checked) ns.db.settings.spotterEnabled = checked; NotifySettingChanged() end,
        L["Help: Screen Spotter Master"],
        L["Master toggle for detecting Enemy, Ally, and Same-Clan players on your screen."],
        L["Uncheck to pause screen scanning and hide the Target Radar HUD completely."]
    )
    local qAvoidCb = CreateGridCheckbox(
        qRight, qRadarCb, -4, L["Group Avoid Warnings"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.groupAvoidAlert ~= false end,
        function(checked) ns.db.settings.groupAvoidAlert = checked; NotifySettingChanged() end,
        L["Help: Group Avoid Warning"],
        L["Immediately alerts you with a warning toast and chat notice if someone on your Avoid list or linked alts enters your party or raid."],
        L["Allows you to address toxic encounters or leave before dungeons and raids start."]
    )
    local qScoutCb = CreateGridCheckbox(
        qRight, qAvoidCb, -4, L["Guild Scout Alerts"],
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterScoutAlert ~= false end,
        function(checked) ns.db.settings.spotterScoutAlert = checked; NotifySettingChanged() end,
        L["Help: Guild Scout Alerts"],
        L["Shows chat, sound, and popup alerts when a guildmate shares an Enemy Scout sighting."],
        L["Uncheck to mute shared Guild Scout alerts without disabling your own Target Radar."]
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
            s.worldBuffsAlerts = false
            s.worldBuffsExpiryAlert = false
            s.clanLfgAlertEnabled = false
            s.clanEventAlertEnabled = false
            s.clanSignupAlertEnabled = false
            s.clanEventReminders = false
            s.spotterScoutAlert = false
            s.groupAvoidAlert = false
            s.spotterAutoShowHUD = false
            if s.alerts then s.alerts.toast = false end
        end
        if ns.NotificationToast and ns.NotificationToast.DismissAll then
            ns.NotificationToast:DismissAll()
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
            s.worldBuffsAlerts = true
            s.worldBuffsExpiryAlert = true
            s.clanLfgAlertEnabled = true
            s.clanSignupAlertEnabled = true
            s.clanEventReminders = true
            s.spotterScoutAlert = true
            s.groupAvoidAlert = true
            s.spotterAutoShowHUD = true
            if s.alerts then s.alerts.toast = true end
        end
        NotifySettingChanged("CLAN_UPDATED")
        for _, sync in ipairs(syncFns) do sync() end
    end)

    HelpBtn(
        bulkActionRow,
        enablePopupsBtn,
        L["Help: Quick Popup Controls"],
        L["Quickly test notification positioning, silence all floating popups at once, or restore default notification popups in 1 click."],
        L["Click 'Mute All Popups' for quiet raids/focus sessions, then click 'Restore Popups' anytime to turn them back on."]
    )

    local winHeader = AddSectionHeader(
        ov,
        L["Official Game Windows (Native Tabs)"],
        bulkActionRow,
        -12,
        L["Help: Official Game Windows"],
        L["SocialCentral features live directly inside Blizzard's native windows via side-tabs and toolbar buttons. Use this Settings window for configuration and quick shortcuts."],
        L["Click any shortcut below to jump straight to that official game window with the SocialCentral tab active, or configure Clan Diplomacy and Preferences below."]
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
        jumpButtons[#jumpButtons + 1] = { btn = jb, variant = spec.variant, isGuild = spec.isGuild }
    end

    local function ReflowJumpGrid()
        local maxW = math.max(320, (ov:GetWidth() or 590) - 24)
        local x, y, rowH = 0, 0, 24
        local hideGuild = Compat and Compat.ShouldShowGuildFeatures and not Compat.ShouldShowGuildFeatures()
        for _, item in ipairs(jumpButtons) do
            if item.isGuild and hideGuild then
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
    ReflowJumpGrid()

    -- =========================================================================
    -- TAB 2: NOTIFICATIONS (Detailed Friend, Watchlist, Chat, Toasts & Guild)
    -- =========================================================================
    local nf = pages.notifications

    local wlAlertHeader = AddSectionHeader(
        nf,
        L["Online alerts for Watchlist"],
        nil,
        -6,
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
    local addonTabBadgesCb = CreateCheckbox(
        nf, L["Show unread counters on Social (O) & Guild (J) side-tabs"], addonMinimapBadgeCb, -6,
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
    local groupAvoidAlertCb = CreateCheckbox(
        nf, L["Warn in chat and toast if an Avoided player joins your party/raid"], scoutAlertCb, -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.groupAvoidAlert ~= false end,
        function(checked) ns.db.settings.groupAvoidAlert = checked; NotifySettingChanged() end,
        L["Help: Group Avoid Warning"],
        L["Immediately alerts you with a warning toast and chat notice if someone on your Avoid list or linked alts enters your party or raid."],
        L["Allows you to address toxic encounters or leave before dungeons and raids start."]
    )

    -- =========================================================================
    -- TAB 3: RADAR & WORLD MAP
    -- =========================================================================
    local rd = pages.radar

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
    local spotterEnemyCb = CreateCheckbox(
        rd, L["Notify when an Enemy Clan player appears on screen"], spotterBadgesCb, -6,
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

    -- =========================================================================
    -- TAB 4: GENERAL & TOOLS (Language, Theme, Minimap, /who, Guild Sync, Tooltips)
    -- =========================================================================
    local gn = pages.general

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
        if ns.Theme and ns.Theme.ResetAllWindowPositions then ns.Theme:ResetAllWindowPositions() end
    end)
    HelpBtn(gn, resetPosBtn, L["Help: Reset Window Positions"], L["Restores the default screen positions of the Main Window, Target Radar HUD, and all popup dialogs."], L["Use this if any window was moved off-screen or after changing screen resolution."])

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

    syncFns[#syncFns + 1] = function()
        local inGuild = Compat and Compat.IsInGuild and Compat.IsInGuild()
        if inGuild then
            local gName = GetGuildInfo and ns.Safe and ns.Safe.String(ns.Safe.Call(GetGuildInfo, "player"))
            guildBadgeLbl:SetText("|cff3fb950" .. ((gName and gName ~= "") and ("<" .. gName .. ">") or L["Guild"]) .. "|r")
        else
            guildBadgeLbl:SetText("|cff9da7b5" .. L["No guild"] .. "|r")
        end

        for _, item in ipairs(jumpButtons) do
            ns.Theme:StyleButton(item.btn, item.variant)
            ns.Theme:SetButtonActive(item.btn, false, item.variant)
        end
        ReflowJumpGrid()

        for _, item in ipairs(catButtons) do
            ns.Theme:StyleButton(item.btn, "tab")
            ns.Theme:SetButtonActive(item.btn, item.id == activeCategoryTab, "tab")
        end

        for _, b in ipairs({ testOvBtn, muteAllPopupsBtn, resetToastPosBtn, testToastBtn, openBuffsBtn, viewTutorialBtn, viewRadarTutorialBtn, langReloadBtn, themePickerBtn, resetPosBtn, updateLinkBtn }) do
            ns.Theme:StyleButton(b, "default")
            ns.Theme:SetButtonActive(b, false, "default")
        end
        ns.Theme:StyleButton(enablePopupsBtn, "primary")
        ns.Theme:SetButtonActive(enablePopupsBtn, false, "primary")
        ns.Theme:StyleButton(openRadarBtn, "primary")
        ns.Theme:SetButtonActive(openRadarBtn, false, "primary")
    end

    scrollFrame:SetScript("OnSizeChanged", function(self)
        local w = math.max(500, (self:GetWidth() or 600) - 10)
        content:SetWidth(w)
        local colW = math.floor((w - 22) * 0.5)
        winGrid:SetWidth(w - 8)
        winLeft:SetWidth(colW)
        winRight:SetWidth(colW)
        qGrid:SetWidth(w - 8)
        qLeft:SetWidth(colW)
        qRight:SetWidth(colW)
        for _, sync in ipairs(syncFns) do
            sync()
        end
    end)

    SelectCategoryTab(activeCategoryTab)

    if ns.Theme and ns.Theme.RegisterListener then
        ns.Theme:RegisterListener(function()
            if panel and panel:IsShown() then
                for _, sync in ipairs(syncFns) do sync() end
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
function SettingsMod:Open()
    if not panel then
        self:Register()
    end
    BuildPanel()
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
        if HideUIPanel then
            if _G.SettingsPanel and _G.SettingsPanel:IsShown() then
                pcall(HideUIPanel, _G.SettingsPanel)
            elseif _G.InterfaceOptionsFrame and _G.InterfaceOptionsFrame:IsShown() then
                pcall(HideUIPanel, _G.InterfaceOptionsFrame)
            end
        elseif _G.SettingsPanel and _G.SettingsPanel.Close then
            pcall(_G.SettingsPanel.Close, _G.SettingsPanel)
        end
        return
    end
    self:Open()
end
