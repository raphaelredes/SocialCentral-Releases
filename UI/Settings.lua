local _, ns = ...

local L = ns.L

local SettingsMod = {}
ns.Settings = SettingsMod

local panel
local panelBuilt = false
local category
local syncFns = {}

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
    fs:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOffset or -14)
    fs:SetText(text)
    if helpTitle then
        HelpBtn(parent, fs, helpTitle, helpWhat, helpHow)
    end
    return fs
end

local function CreateCheckbox(parent, labelText, anchorTo, yOffset, getter, setter, helpTitle, helpWhat, helpHow)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOffset or -8)

    local label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    label:SetText(labelText)
    local function FitCheckboxLabel()
        local avail = math.max(320, (parent:GetWidth() or 590) - 86)
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
    end)

    syncFns[#syncFns + 1] = function()
        FitCheckboxLabel()
        cb:SetChecked(getter() and true or false)
    end
    return cb
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
        local x = 0
        local y = 0
        local rowH = 24
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

    local scrollFrame = CreateFrame("ScrollFrame", "SocialCentralSettingsScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(590, 3330)
    scrollFrame:SetScrollChild(content)
    scrollFrame:SetScript("OnSizeChanged", function(self)
        local w = math.max(460, (self:GetWidth() or 590) - 10)
        content:SetWidth(w)
        for _, sync in ipairs(syncFns) do
            sync()
        end
    end)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetText("SocialCentral  v" .. (ns.version or "0.0.0"))

    local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText(L["Unified social hub for WoW: Forever."])

    local winHeader = AddSectionHeader(
        content,
        L["Official Game Windows (Native Tabs)"],
        subtitle,
        -12,
        L["Help: Official Game Windows"],
        L["SocialCentral features live directly inside Blizzard's native windows via side-tabs and toolbar buttons. Use this Settings window for configuration and quick shortcuts."],
        L["Click any shortcut below to jump straight to that official game window with the SocialCentral tab active, or configure Clan Diplomacy and Preferences below."]
    )

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

    local jumpGrid = CreateFrame("Frame", nil, content)
    jumpGrid:SetPoint("TOPLEFT", winHeader, "BOTTOMLEFT", 0, -6)
    jumpGrid:SetSize(560, 62)

    local jumpSpecs = {
        { mod = "lfg", label = L["Looking for Group (I)"], variant = "primary" },
        { mod = "watchlist", label = L["Social & Watchlist (O)"], variant = "default" },
        { mod = "clan", label = L["Clan Hub & Diplomacy (J)"], variant = "default" },
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
        jumpButtons[#jumpButtons + 1] = { btn = jb, variant = spec.variant }
    end

    local function ReflowJumpGrid()
        local maxW = math.max(320, (content:GetWidth() or 590) - 34)
        local x, y, rowH = 0, 0, 24
        for _, item in ipairs(jumpButtons) do
            local bw = math.min(maxW, math.max(96, item.btn:GetWidth() or 140))
            if x > 0 and (x + bw) > maxW then
                x = 0
                y = y - (rowH + 6)
            end
            item.btn:ClearAllPoints()
            item.btn:SetPoint("TOPLEFT", jumpGrid, "TOPLEFT", x, y)
            x = x + bw + 8
        end
        jumpGrid:SetSize(maxW, math.abs(y) + rowH + 2)
    end
    ReflowJumpGrid()
    syncFns[#syncFns + 1] = function()
        for _, item in ipairs(jumpButtons) do
            ns.Theme:StyleButton(item.btn, item.variant)
            ns.Theme:SetButtonActive(item.btn, false, item.variant)
        end
        ReflowJumpGrid()
    end

    local langHeader = AddSectionHeader(
        content,
        L["Language"],
        jumpGrid,
        -12,
        L["Help: Language"],
        L["Choose Auto (WoW) to follow your game client language automatically, or override SocialCentral to English, Português (BR), or Español independently."],
        L["Click a language button below and confirm Reload UI (outside combat) so all menus, tooltips, and labels re-render cleanly in your chosen language."]
    )
    local langValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    langValue:SetPoint("TOPLEFT", langHeader, "BOTTOMLEFT", 0, -4)
    local langModeNote = ns.langOverridden and L["Manual Override"] or L["Auto (WoW)"]
    langValue:SetText(L["Active Language: %s (%s)"]:format(ns.activeLangLabel or "English", ns.activeLocale or "enUS") .. "  [" .. langModeNote .. "]")

    local langChoices = {
        { value = "auto", label = L["Auto (WoW)"], width = 116 },
        { value = "enUS", label = "English", width = 94 },
        { value = "ptBR", label = "Português (BR)", width = 140 },
        { value = "esES", label = "Español", width = 100 },
    }
    local langLabelByVal = {
        auto = L["Auto (WoW)"],
        enUS = "English",
        ptBR = "Português (BR)",
        esES = "Español",
    }
    local langRow = CreateChoiceRow(content, langValue, -6, langChoices, function()
        return (ns.db and ns.db.settings and ns.db.settings.language) or "auto"
    end, function(val)
        local prev = (ns.db and ns.db.settings and ns.db.settings.language) or "auto"
        ns.db.settings.language = val
        if val ~= prev and ns.Theme and ns.Theme.ShowReloadPrompt then
            ns.Theme:ShowReloadPrompt(langLabelByVal[val] or val)
        end
    end)

    local langReloadBtn = ns.Theme:CreateButton(content, 168, 22, L["Reload UI to Apply Language"], "default")
    ns.Theme:AutoFitButton(langReloadBtn, 160, 22)
    langReloadBtn:SetPoint("TOPLEFT", langRow, "BOTTOMLEFT", 0, -6)
    langReloadBtn:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then
            ns:Print(L["In Combat"])
            return
        end
        if ReloadUI then
            ReloadUI()
        elseif C_UI and C_UI.Reload then
            C_UI.Reload()
        end
    end)
    syncFns[#syncFns + 1] = function()
        ns.Theme:StyleButton(langReloadBtn, "default")
        ns.Theme:SetButtonActive(langReloadBtn, false, "default")
    end

    local themeHeader = AddSectionHeader(
        content,
        L["Theme"],
        langReloadBtn,
        -12,
        L["Help: Theme"],
        L["Choose between Blizzard Official (default in-game portrait window, dark marble inset, and classic red/pewter buttons), Modern Theme (optional dark minimalist UI), or Classic Gold."],
        L["Click your preferred design button (or open the visual Preview Picker below); changes apply immediately across all SocialCentral windows without /reload."]
    )
    local themeRow = CreateChoiceRow(content, themeHeader, -6, {
        { value = "blizzard", label = L["Blizzard Official"], width = 176 },
        { value = "dark", label = L["Modern Theme"], width = 166 },
        { value = "native", label = L["Classic Gold"], width = 152 },
    }, function()
        return ns.db and ns.db.settings.theme or "blizzard"
    end, function(val)
        ns.db.settings.theme = val
        ns.db.settings.themeChosen = true
        if ns.Theme then
            ns.Theme:NotifyChanged()
        end
    end)

    local themePickerBtn = ns.Theme:CreateButton(content, 200, 22, L["Open Theme Preview Picker"], "default")
    ns.Theme:AutoFitButton(themePickerBtn, 190, 22)
    themePickerBtn:SetPoint("TOPLEFT", themeRow, "BOTTOMLEFT", 0, -6)
    themePickerBtn:SetScript("OnClick", function()
        if ns.Theme and ns.Theme.ShowThemeWelcomePicker then
            ns.Theme:ShowThemeWelcomePicker()
        end
    end)
    syncFns[#syncFns + 1] = function()
        ns.Theme:StyleButton(themePickerBtn, "default")
        ns.Theme:SetButtonActive(themePickerBtn, false, "default")
    end

    local whoHeader = AddSectionHeader(
        content,
        L["/who mode"],
        themePickerBtn,
        -12,
        L["Help: /who Mode"],
        L["Controls how manual /who responses are captured silently without interrupting your gameplay."],
        L["Choose 'Silent UI' (hides Blizzard Friends popup outside combat) or 'Chat Filter' (parses chat lines cleanly without touching FriendsFrame)."]
    )
    local whoRow = CreateChoiceRow(content, whoHeader, -6, {
        { value = "silent_ui", label = L["Silent UI (no Friends popup outside combat)"], width = 272 },
        { value = "chat_filter", label = L["Chat filter (zero touch on FriendsFrame)"], width = 272 },
    }, function()
        return ns.db and ns.db.settings.whoMode or "silent_ui"
    end, function(val)
        ns.db.settings.whoMode = val
    end)

    local cdHeader = AddSectionHeader(
        content,
        L["/who cooldown (seconds)"],
        whoRow,
        -12,
        L["Help: /who Cooldown"],
        L["Enforces a minimum waiting interval (5 to 30 seconds) between manual /who clicks so servers never throttle or flag requests."],
        L["Use '-' and '+' to adjust. Blizzard servers lock /who if queried too rapidly; 6s or higher is safest."]
    )
    local cdRow = CreateStepperRow(content, cdHeader, -6, 5, 30, "s", function()
        return ns.db and ns.db.settings.whoCooldown or 6
    end, function(val)
        ns.db.settings.whoCooldown = val
    end)

    local nearbyHeader = AddSectionHeader(
        content,
        L["Nearby retention (minutes)"],
        cdRow,
        -12,
        L["Help: Nearby Retention"],
        L["Defines how many minutes passive friendly Nearby sightings remain listed before expiring automatically."],
        L["Adjust from 5 to 60 minutes with '-' and '+'. Older sightings are pruned cleanly to save memory."]
    )
    local nearbyRow = CreateStepperRow(content, nearbyHeader, -6, 5, 60, "min", function()
        return ns.db and ns.db.settings.nearbyRetentionMin or 15
    end, function(val)
        ns.db.settings.nearbyRetentionMin = val
        ns:Emit("NEARBY_UPDATED")
    end)

    local mmCb = CreateCheckbox(
        content,
        L["Show minimap button"],
        nearbyRow,
        -12,
        function() return not (ns.db and ns.db.settings.minimap.hide) end,
        function(checked)
            ns.db.settings.minimap.hide = not checked
            if ns.Minimap then ns.Minimap:Update() end
        end,
        L["Help: Show Minimap Button"],
        L["Displays or hides the circular/square SocialCentral button attached around your Minimap."],
        L["Check to show the button. Left-click opens the window, Shift+Click runs next /who, Right-click opens quick actions, Drag moves it."]
    )

    local lockCb = CreateCheckbox(
        content,
        L["Lock minimap button"],
        mmCb,
        -6,
        function() return ns.db and ns.db.settings.minimap.lock end,
        function(checked) ns.db.settings.minimap.lock = checked end,
        L["Help: Lock Minimap Button"],
        L["Prevents accidental dragging of the Minimap button while clicking or moving your camera."],
        L["Enable after positioning your Minimap button where you want it."]
    )

    local alertCb = CreateCheckbox(
        content,
        L["Online alerts for Watchlist"],
        lockCb,
        -6,
        function() return ns.db and ns.db.settings.alerts and ns.db.settings.alerts.chat end,
        function(checked)
            if ns.db and ns.db.settings.alerts then
                ns.db.settings.alerts.chat = checked
            end
            if ns.UI and ns.UI.QueueRefresh then
                ns.UI:QueueRefresh(false)
            end
        end,
        L["Help: Watchlist Online Alerts"],
        L["Prints a local chat notification whenever a Watchlist character transitions from offline to online."],
        L["Triggered safely when /who, Friends, Guild, Battle.net, or Nearby spots a watched friend online (120s anti-spam debounce)."]
    )

    local watchToastCb = CreateCheckbox(
        content,
        L["Show floating Toast when Watchlist player comes online"],
        alertCb,
        -6,
        function() return not ns.db or not ns.db.settings.alerts or ns.db.settings.alerts.toast ~= false end,
        function(checked)
            if ns.db and ns.db.settings.alerts then
                ns.db.settings.alerts.toast = checked
            end
            if ns.UI and ns.UI.QueueRefresh then
                ns.UI:QueueRefresh(false)
            end
        end,
        L["Help: Watchlist Toast Alert"],
        L["Displays a compact floating Notification Toast at the top of the screen when a watched player transitions online (outside muted rows)."],
        L["Uncheck to stop floating Watchlist toasts globally, or click the bell icon beside any name in the Social/Watchlist window (O) to mute per player."]
    )

    local soundCb = CreateCheckbox(
        content,
        L["Play sound on Watchlist online alert"],
        watchToastCb,
        -6,
        function() return ns.db and ns.db.settings.alerts and ns.db.settings.alerts.sound end,
        function(checked)
            if ns.db and ns.db.settings.alerts then
                ns.db.settings.alerts.sound = checked
            end
        end,
        L["Help: Alert Sound"],
        L["Plays a subtle Blizzard UI chime alongside the local chat online alert."],
        L["Check to hear an audio chime when a watched friend comes online."]
    )

    local friendAlertHeader = AddSectionHeader(
        content,
        L["Friend Online Alerts"],
        soundCb,
        -12,
        L["Help: Friend Online Alerts"],
        L["Notifies you cleanly when Character Friends or Battle.net friends enter World of Warcraft: Forever, after an 8-second post-login grace window and 120-second anti-spam cooldown."],
        L["Enabled for All Friends by default; mute specific players via the bell icon in the Social (O) list, or switch to Favorites Only or Off below."]
    )

    local friendAlertModeRow = CreateChoiceRow(content, friendAlertHeader, -6, {
        { value = "all", label = L["All Friends"], width = 152 },
        { value = "favorites", label = L["Favorites Only"], width = 166 },
        { value = "off", label = L["Off"], width = 112 },
    }, function()
        return ns.db and ns.db.settings.friendOnlineAlertMode or "all"
    end, function(val)
        ns.db.settings.friendOnlineAlertMode = val
        if ns.UI and ns.UI.QueueRefresh then
            ns.UI:QueueRefresh(false)
        end
    end)

    local friendToastCb = CreateCheckbox(
        content,
        L["Show floating Toast when Friends come online"],
        friendAlertModeRow,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.friendOnlineAlertToast ~= false end,
        function(checked)
            ns.db.settings.friendOnlineAlertToast = checked
            if ns.UI and ns.UI.QueueRefresh then
                ns.UI:QueueRefresh(false)
            end
        end,
        L["Help: Friend Online Toast"],
        L["Displays a compact floating Notification Toast when a tracked Favorite or Friend logs into WoW: Forever."],
        L["Left-click the toast to jump straight to that friend in the Social tab."]
    )

    local friendChatCb = CreateCheckbox(
        content,
        L["Print clickable [Social] summary line on Friend login"],
        friendToastCb,
        -6,
        function() return ns.db and ns.db.settings.friendOnlineAlertChat == true end,
        function(checked)
            ns.db.settings.friendOnlineAlertChat = checked
            if ns.UI and ns.UI.QueueRefresh then
                ns.UI:QueueRefresh(false)
            end
        end,
        L["Help: Friend Online Chat"],
        L["Prints an extra local SocialCentral chat line with a clickable [Social] link whenever a friend alert fires."],
        L["Disabled by default to avoid duplicating Blizzard's standard friend-online chat line."]
    )

    local friendSoundCb = CreateCheckbox(
        content,
        L["Play audio chime when Friends come online"],
        friendChatCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.friendOnlineAlertSound ~= false end,
        function(checked)
            ns.db.settings.friendOnlineAlertSound = checked
        end,
        L["Help: Friend Online Sound"],
        L["Plays a subtle Battle.net UI chime when a Friend Online alert triggers."],
        L["Uncheck for silent visual friend login alerts only."]
    )

    local verCb = CreateCheckbox(
        content,
        L["Check for addon updates (DBM-style peer alerts)"],
        friendSoundCb,
        -6,
        function() return ns.db and ns.db.settings.versionCheck ~= false end,
        function(checked)
            if ns.db and ns.db.settings then
                ns.db.settings.versionCheck = checked
            end
        end,
        L["Help: Update Check & GitHub"],
        L["Silently compares versions with other SocialCentral users in your guild or group (just like DBM) and warns you if a newer version is out."],
        L["Keep enabled for in-game update chat links. Click 'GitHub Releases / Updater' to copy the public GitHub download link or Windows updater command."]
    )

    local updateLinkBtn = ns.Theme:CreateButton(content, 210, 24, L["GitHub Releases / Updater"], "default")
    ns.Theme:AutoFitButton(updateLinkBtn, 210, 22, 490)
    updateLinkBtn:SetPoint("TOPLEFT", verCb, "BOTTOMLEFT", 4, -6)
    updateLinkBtn:SetScript("OnClick", function()
        if ns.Theme and ns.Theme.ShowUpdatePopup then
            ns.Theme:ShowUpdatePopup(ns.version, ns.Clan and ns.Clan.latestRemoteVersion, ns.RELEASE_URL)
        end
    end)
    HelpBtn(
        content,
        updateLinkBtn,
        L["Help: Update Check & GitHub"],
        L["Silently compares versions with other SocialCentral users in your guild or group (just like DBM) and warns you if a newer version is out."],
        L["Keep enabled for in-game update chat links. Click 'GitHub Releases / Updater' to copy the public GitHub download link or Windows updater command."]
    )

    local clanSyncCb = CreateCheckbox(
        content,
        L["Enable Clan guild sync (opt-in)"],
        updateLinkBtn,
        -10,
        function() return ns.db and ns.db.settings.clanSync end,
        function(checked)
            ns.db.settings.clanSync = checked
            ns:Emit("CLAN_UPDATED")
        end,
        L["Help: Clan Guild Sync"],
        L["Enables encrypted-free opt-in guild addon messages (SCentral1) to share Status Tags, Event Calls, and Dungeon/Raid Signups with guildmates."],
        L["Leave unchecked for 100% local Clan tracking, or enable to sync tags and event calls safely with guildmates who also use SocialCentral."]
    )

    local guildFinderCb = CreateCheckbox(
        content,
        L["Detect LFM calls in Guild chat (opt-in, read-only)"],
        clanSyncCb,
        -6,
        function() return ns.db and ns.db.settings.guildChatFinder end,
        function(checked)
            ns.db.settings.guildChatFinder = checked
            ns:Emit("CLAN_UPDATED")
        end,
        L["Help: Guild LFM Detector"],
        L["Passively reads Guild chat lines looking for LFG/LFM keywords so guild calls show inside the Clan tab without running any scan or sending messages."],
        L["Enable to capture guild group requests automatically; click a sighting in the Clan tab to whisper or request invite."]
    )

    local globalChatLfgCb = CreateCheckbox(
        content,
        L["Scan public chat channels for LFG Bulletin"],
        guildFinderCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.globalChatLfgScan ~= false end,
        function(checked)
            ns.db.settings.globalChatLfgScan = checked
            ns:Emit("CLAN_UPDATED")
        end,
        L["Help: Global Chat LFG"],
        L["Passively captures LFG/LFM dungeon and raid messages from public chat channels into the 'Global Chat LFG' filter inside Group Finder (I)."],
        L["Select 'Global Chat LFG' in Group Finder to browse clean server chat requests separated from your Guild and Allies."]
    )

    local autoStatusCb = CreateCheckbox(
        content,
        L["Auto-tag Busy inside dungeons/raids (opt-in)"],
        globalChatLfgCb,
        -6,
        function() return ns.db and ns.db.settings.autoStatusInstance end,
        function(checked)
            ns.db.settings.autoStatusInstance = checked
            if ns.Clan and ns.Clan.ApplyAutoInstanceStatus then
                ns.Clan:ApplyAutoInstanceStatus()
            end
        end,
        L["Help: Auto Instance Status"],
        L["Automatically sets your Clan Status Tag to 'Busy' while inside a Dungeon or Raid instance and restores 'None' outside."],
        L["Respects combat lockdown and only broadcasts when Clan Guild Sync is also enabled."]
    )

    local clanLfgAlertCb = CreateCheckbox(
        content,
        L["Notify in chat when guildmates look for Dungeon / LFG"],
        autoStatusCb,
        -6,
        function() return ns.db and ns.db.settings.clanLfgAlertEnabled == true end,
        function(checked)
            ns.db.settings.clanLfgAlertEnabled = checked
            ns:Emit("CLAN_UPDATED")
        end,
        L["Help: Clan Dungeon Alerts"],
        L["Notifies you in chat (with optional sound and clickable Whisper/Clan links) whenever a guildmate looks for a Dungeon/M+ group."],
        L["Click 'LFG Alerts' to enable/disable alerts, restrict to Dungeons only, or filter specific dungeon keywords."]
    )

    local clanLfgDngOnlyCb = CreateCheckbox(
        content,
        L["Alert only for Dungeons & M+ calls (exclude raids/PvP)"],
        clanLfgAlertCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.clanLfgAlertDungeonsOnly ~= false end,
        function(checked)
            ns.db.settings.clanLfgAlertDungeonsOnly = checked
            ns:Emit("CLAN_UPDATED")
        end,
        L["Help: Clan Dungeon Filter"],
        L["Filters Clan LFG alerts to Dungeon and Mythic+ calls, ignoring Raids and PvP announcements."],
        L["Uncheck if you want to be notified for all Clan LFG activity types (Dungeons, Raids, World Bosses, PvP)."]
    )

    local clanLfgAlertSoundCb = CreateCheckbox(
        content,
        L["Play chime sound on Clan Dungeon LFG alert"],
        clanLfgDngOnlyCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.clanLfgAlertSound ~= false end,
        function(checked)
            ns.db.settings.clanLfgAlertSound = checked
        end,
        L["Help: Clan Alert Sound"],
        L["Plays a subtle Blizzard UI chime alongside your chat alert when a matching Clan Dungeon LFG call arrives."],
        L["Requires 'Notify in chat when guildmates look for Dungeon / LFG' to be enabled."]
    )

    local clanFilterRow = CreateFrame("Frame", nil, content)
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
        if ns.db and ns.db.settings then
            ns.db.settings.clanLfgAlertFilter = ns.Compat.CleanInput(self:GetText() or "") or ""
        end
        self:ClearFocus()
    end)
    clanFilterInput:SetScript("OnEditFocusLost", function(self)
        if ns.db and ns.db.settings then
            ns.db.settings.clanLfgAlertFilter = ns.Compat.CleanInput(self:GetText() or "") or ""
        end
    end)
    HelpBtn(
        clanFilterRow,
        clanFilterInput,
        L["Help: Clan Alert Keywords"],
        L["Comma-separated dungeon or level keywords (e.g. 'BRH, +10, tank') so Clan Dungeon Alerts only fire on matching requests."],
        L["Leave blank to receive alerts for all Dungeon LFG calls inside your guild."]
    )
    syncFns[#syncFns + 1] = function()
        if not clanFilterInput:HasFocus() then
            clanFilterInput:SetText((ns.db and ns.db.settings and ns.db.settings.clanLfgAlertFilter) or "")
        end
    end

    local clanEventAlertCb = CreateCheckbox(
        content,
        L["Notify when guildmates post a new Guild Event"],
        clanFilterRow,
        -6,
        function() return ns.db and ns.db.settings.clanEventAlertEnabled == true end,
        function(checked)
            ns.db.settings.clanEventAlertEnabled = checked
            ns:Emit("CLAN_UPDATED")
        end,
        L["Help: Guild Event Alerts"],
        L["Alerts you with a clickable notification and toast whenever a guildmate schedules a new Raid, Quest, PvP, or Custom Guild Event."],
        L["Enable to never miss scheduled guild activities even when outside Dungeon LFG."]
    )

    local clanSignupAlertCb = CreateCheckbox(
        content,
        L["Notify me when guildmates sign up to my Events"],
        clanEventAlertCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.clanSignupAlertEnabled ~= false end,
        function(checked)
            ns.db.settings.clanSignupAlertEnabled = checked
            ns:Emit("CLAN_UPDATED")
        end,
        L["Help: Guild Signup Alerts"],
        L["Notifies you as the event organizer whenever a guildmate signs up (or declines) on one of your active Guild Events."],
        L["Triggers only on events you created so your chat stays clutter-free."]
    )

    local chatSettingsHeader = AddSectionHeader(
        content,
        L["Conversations & Sound Alerts"],
        clanSignupAlertCb,
        -14,
        L["Help: Conversations & Sounds"],
        L["Separately control sound chimes by channel type and decide whether WoW native Guild/Group channels are mirrored inside Conversations."],
        L["By default, SocialCentral focuses on Direct Whispers and Addon Private Rooms while keeping Guild and Party chat silent."]
    )

    local chatSoundCb = CreateCheckbox(
        content,
        L["Master: Enable Chat Sound Alerts"],
        chatSettingsHeader,
        -6,
        function() return ns.db and ns.db.settings.chatSound ~= false end,
        function(checked)
            ns.db.settings.chatSound = checked
            ns:Emit("CHAT_UPDATED")
        end,
        L["Help: Chat Sound Alert"],
        L["Master switch for incoming conversation sound chimes across SocialCentral."],
        L["Uncheck to mute all SocialCentral conversation chimes without affecting muted individual threads."]
    )

    local chatSoundWhispersCb = CreateCheckbox(
        content,
        L["Play chime on Whispers & Battle.net"],
        chatSoundCb,
        -6,
        function() return ns.db and ns.db.settings.chatSoundWhispers ~= false end,
        function(checked)
            ns.db.settings.chatSoundWhispers = checked
        end,
        L["Help: Whisper Sounds"],
        L["Plays a subtle audio chime when an incoming character Whisper or Battle.net whisper arrives while unfocused."],
        L["Requires Master Chat Sound Alerts to be enabled; individual senders can still be muted from the Conversations panel."]
    )

    local chatSoundRoomsCb = CreateCheckbox(
        content,
        L["Play chime on SocialCentral Private Rooms"],
        chatSoundWhispersCb,
        -6,
        function() return ns.db and ns.db.settings.chatSoundRooms ~= false end,
        function(checked)
            ns.db.settings.chatSoundRooms = checked
        end,
        L["Help: Private Room Sounds"],
        L["Plays a chime when a peer sends a message or invite inside an addon Private Room (SCentral1)."],
        L["Turn off if your Private Room is noisy while still keeping Whisper alerts enabled."]
    )

    local chatSoundAllianceCb = CreateCheckbox(
        content,
        L["Play chime on Alliance Chat messages"],
        chatSoundRoomsCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.chatSoundAlliance ~= false end,
        function(checked)
            ns.db.settings.chatSoundAlliance = checked
        end,
        L["Help: Alliance Chat Sound"],
        L["Plays a distinct audio chime when an authorized Alliance member posts in cross-guild Alliance Chat."],
        L["Requires Master Chat Sound Alerts to be enabled."]
    )

    local chatSoundGuildCb = CreateCheckbox(
        content,
        L["Play chime on Guild & Officer chat (off by default)"],
        chatSoundAllianceCb,
        -6,
        function() return ns.db and ns.db.settings.chatSoundGuild == true end,
        function(checked)
            ns.db.settings.chatSoundGuild = checked
        end,
        L["Help: Guild Chat Sound"],
        L["Controls whether mirrored Guild and Officer chat lines trigger a sound chime (disabled by default)."],
        L["Leave unchecked so WoW Guild chat never beeps inside SocialCentral."]
    )

    local chatSoundGroupCb = CreateCheckbox(
        content,
        L["Play chime on Party / Raid / Instance chat (off by default)"],
        chatSoundGuildCb,
        -6,
        function() return ns.db and ns.db.settings.chatSoundGroup == true end,
        function(checked)
            ns.db.settings.chatSoundGroup = checked
        end,
        L["Help: Group Chat Sound"],
        L["Controls whether mirrored Party, Raid, or Instance chat lines trigger a sound chime (disabled by default)."],
        L["Leave unchecked so dungeon and raid chat remains silent in SocialCentral."]
    )

    local chatMirrorCb = CreateCheckbox(
        content,
        L["Mirror WoW Guild / Party / Raid channels inside Conversations (opt-in)"],
        chatSoundGroupCb,
        -6,
        function() return ns.db and ns.db.settings.chatMirrorChannels == true end,
        function(checked)
            ns.db.settings.chatMirrorChannels = checked
            ns:Emit("CHAT_UPDATED")
        end,
        L["Help: Mirror WoW Channels"],
        L["When unchecked (default), SocialCentral Conversations stay separate from native WoW Guild/Party/Raid chat frames."],
        L["Check only if you also want copies of WoW Guild/Group messages logged inside Conversations."]
    )

    local chatChannelUnreadCb = CreateCheckbox(
        content,
        L["Count mirrored Guild/Group lines as unread on Minimap"],
        chatMirrorCb,
        -6,
        function() return ns.db and ns.db.settings.chatChannelUnread == true end,
        function(checked)
            ns.db.settings.chatChannelUnread = checked
            ns:Emit("CHAT_UPDATED")
        end,
        L["Help: Guild Unread Badge"],
        L["By default, only Direct Whispers, BNet whispers, and SocialCentral Private Rooms count toward the Minimap unread badge and tooltip."],
        L["Leave unchecked so noisy Guild channels never trigger unread alerts on your Minimap icon."]
    )

    local addonDirectCb = CreateCheckbox(
        content,
        L["Enable Verified In-Addon 1-on-1 Direct Chat"],
        chatChannelUnreadCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.addonDirectChat ~= false end,
        function(checked)
            ns.db.settings.addonDirectChat = checked
            ns:Emit("CHAT_UPDATED")
        end,
        L["Help: Addon Direct Chat"],
        L["Enables full 1-on-1 chat inside SocialCentral (with delivery confirmation and location share) ONLY when both players have the addon active."],
        L["When unchecked or when the other player lacks SocialCentral, Conversations show a single button to open the pre-addressed official WoW chat instead."]
    )

    local addonNotifyHeader = AddSectionHeader(
        content,
        L["Addon Message Notifications"],
        addonDirectCb,
        -14,
        L["Help: Addon Message Notifications"],
        L["Customize how SocialCentral alerts you when incoming addon-only messages (Direct Messages, Private Rooms, Invites, Alliance Chat, and Guild Alerts) arrive."],
        L["Combine the floating Toast pill, clickable [SC] chat lines, Minimap & Side-Tab unread badges, and taskbar flashing to suit your screen."]
    )

    local addonToastCb = CreateCheckbox(
        content,
        L["Show floating popup Toast for incoming addon messages"],
        addonNotifyHeader,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.addonMsgToast ~= false end,
        function(checked)
            ns.db.settings.addonMsgToast = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Floating Notification Toast"],
        L["Displays a compact, draggable 100%-opaque pill near the top of your screen when a peer messages you via the addon or sends a room invite."],
        L["Left-click the pill to jump directly to the conversation (deferred automatically after combat), hover to pause, or right-click to dismiss."]
    )

    local addonEchoCb = CreateCheckbox(
        content,
        L["Print clickable [SC] summary in Chat window for addon messages"],
        addonToastCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.addonMsgChatEcho ~= false end,
        function(checked)
            ns.db.settings.addonMsgChatEcho = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Addon Chat Echo"],
        L["Blizzard hides raw addon packets from standard chat frames. Enabling this echoes a clean one-line summary with a clickable [Open] link in your chat."],
        L["Skipped automatically while you are actively viewing that exact thread inside SocialCentral."]
    )

    local addonFlashCb = CreateCheckbox(
        content,
        L["Pulse taskbar icon when high-priority addon messages arrive"],
        addonEchoCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.addonMsgTaskbarFlash ~= false end,
        function(checked)
            ns.db.settings.addonMsgTaskbarFlash = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Taskbar Flash"],
        L["Calls Blizzard's FlashClientIcon() so the WoW window highlights on your Windows taskbar if you are alt-tabbed when a DM or invite arrives."],
        L["Only flashes for priority incoming notifications and does nothing while you are already viewing the open thread."]
    )

    local addonMinimapBadgeCb = CreateCheckbox(
        content,
        L["Show numeric unread counter on Minimap icon"],
        addonFlashCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.addonMsgMinimapBadge ~= false end,
        function(checked)
            ns.db.settings.addonMsgMinimapBadge = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Minimap Unread Counter"],
        L["Displays a compact red unread counter badge directly on the corner of the SocialCentral Minimap button alongside the golden ring tint."],
        L["Clears automatically as soon as you open and view the unread threads or invitations."]
    )

    local addonTabBadgesCb = CreateCheckbox(
        content,
        L["Show unread counters on Social (O) & Guild (J) side-tabs"],
        addonMinimapBadgeCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.addonMsgTabBadges ~= false end,
        function(checked)
            ns.db.settings.addonMsgTabBadges = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Side-Tab Unread Counters"],
        L["Displays unread Direct/Room message counts on the Social (O) side-tab and new Guild Event/LFG alert counts on the Guild (J) side-tab."],
        L["Uncheck if you prefer completely plain bookmark tabs without counter pills."]
    )

    local testToastBtn = ns.Theme:CreateButton(content, 190, 22, L["Test Notification Toast"], "default")
    ns.Theme:AutoFitButton(testToastBtn, 160, 18, 260)
    testToastBtn:SetPoint("TOPLEFT", addonTabBadgesCb, "BOTTOMLEFT", 0, -8)
    testToastBtn:SetScript("OnClick", function()
        if ns.NotificationToast and ns.NotificationToast.ShowTestNotification then
            ns.NotificationToast:ShowTestNotification()
        end
    end)
    HelpBtn(
        content,
        testToastBtn,
        L["Help: Test Notification Toast"],
        L["Spawns a sample floating Notification Toast pill with sound so you can preview its look and drag it to your preferred screen position."],
        L["Click to show the pill, drag it anywhere on screen, or reset positions anytime with '/sc resetpos'."]
    )
    syncFns[#syncFns + 1] = function()
        ns.Theme:StyleButton(testToastBtn, "default")
    end

    local histHeader = AddSectionHeader(
        content,
        L["Character Whisper history per thread (0 = off)"],
        testToastBtn,
        -12,
        L["Help: Whisper History Limit"],
        L["Saves the last N lines per Character Whisper locally (0 to 60 lines). Battle.net Real IDs and BattleTags are never persisted to disk."],
        L["Use '-' and '+' in steps of 10. Set to 0 if you want session-only whispers without SavedVariables history."]
    )
    local histRow = CreateStepperRow(content, histHeader, -6, 0, 60, L["lines"], function()
        return ns.db and ns.db.settings.chatHistoryLimit or 30
    end, function(val)
        ns.db.settings.chatHistoryLimit = val
        ns:Emit("CHAT_UPDATED")
    end, 10)

    local tooltipsHeader = AddSectionHeader(
        content,
        L["Tooltips & Item Inventory Counts"],
        histRow,
        -14,
        L["Help: Tooltips Integration"],
        L["Enhances official item and player tooltips with account-wide alt item counts and saved Social Card notes, Red Flags, and recent companions."],
        L["Toggle either tooltip helper below at any time without affecting Blizzard performance or combat safety."]
    )

    local tooltipItemAltsCb = CreateCheckbox(
        content,
        L["Show Alt Item Counts in item tooltips"],
        tooltipsHeader,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.tooltipItemAlts ~= false end,
        function(checked)
            ns.db.settings.tooltipItemAlts = checked
        end,
        L["Help: Alt Item Tooltips"],
        L["Displays which characters on this realm pool own the hovered item across Equipped, Bags, and Bank, plus the account total."],
        L["Hover any item in bags, chat, bank, or auction house to see alt inventory counts instantly."]
    )

    local tooltipPlayerNotesCb = CreateCheckbox(
        content,
        L["Show Social Notes, Red Flags & Companion history in tooltips"],
        tooltipItemAltsCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.tooltipPlayerNotes ~= false end,
        function(checked)
            ns.db.settings.tooltipPlayerNotes = checked
        end,
        L["Help: Player Tooltip Notes"],
        L["Displays saved Social Card notes, 'Avoid' Red Flags, Watchlist notes, and recent dungeon companions when hovering over a player."],
        L["Right-click any player frame or chat name to quickly set Social Notes, 'Good Partner (+)', or 'Flag: Avoid'."]
    )

    local spotterHeader = AddSectionHeader(
        content,
        L["Screen Clan Radar & Target Selection"],
        tooltipPlayerNotesCb,
        -14,
        L["Help: Screen Clan Radar"],
        L["Detects Enemy, Ally, and Same-Clan players appearing on your screen via nameplates, target, focus, or mouseover using guild-isolated Diplomacy lists."],
        L["Click a row on the floating Target Radar HUD to select that player via Blizzard-legal secure macro click (/targetexact)."]
    )

    local spotterEnabledCb = CreateCheckbox(
        content,
        L["Enable On-Screen Clan Spotter (Enemy / Ally / Same Clan)"],
        spotterHeader,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterEnabled ~= false end,
        function(checked)
            ns.db.settings.spotterEnabled = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Screen Spotter Master"],
        L["Master toggle for detecting Enemy, Ally, and Same-Clan players on your screen."],
        L["Uncheck to pause screen scanning and hide the Target Radar HUD completely."]
    )

    local spotterAutoHudCb = CreateCheckbox(
        content,
        L["Auto-open Target Selection Radar HUD on sighting (out of combat)"],
        spotterEnabledCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterAutoShowHUD ~= false end,
        function(checked)
            ns.db.settings.spotterAutoShowHUD = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Spotter Auto HUD"],
        L["Automatically opens the floating Target Radar HUD when a flagged player appears while you are out of combat."],
        L["Close the HUD manually at any time or use '/sc radar' to toggle it."]
    )

    local spotterBadgesCb = CreateCheckbox(
        content,
        L["Show Enemy/Ally/Clan badge tags above visible nameplates"],
        spotterAutoHudCb,
        -6,
        function() return ns.db and ns.db.settings and ns.db.settings.spotterNameplateBadges == true end,
        function(checked)
            ns.db.settings.spotterNameplateBadges = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Nameplate Stance Badges"],
        L["Adds a lightweight non-forbidden [ENEMY]/[ALLY]/[CLAN] indicator tag above player nameplates when readable."],
        L["Disable if you already use heavy custom nameplate addons and prefer HUD-only alerts."]
    )

    local spotterEnemyCb = CreateCheckbox(
        content,
        L["Notify when an Enemy Clan player appears on screen"],
        spotterBadgesCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterNotifyEnemy ~= false end,
        function(checked)
            ns.db.settings.spotterNotifyEnemy = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Spotter Enemy Alerts"],
        L["Triggers chat, banner, and sound alerts when someone from a guild marked Enemy appears on your screen."],
        L["Per-player cooldown prevents repeated spam if the same player stays nearby."]
    )

    local spotterAllyCb = CreateCheckbox(
        content,
        L["Notify when an Ally Clan player appears on screen"],
        spotterEnemyCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterNotifyAlly ~= false end,
        function(checked)
            ns.db.settings.spotterNotifyAlly = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Spotter Ally Alerts"],
        L["Triggers chat, banner, and sound alerts when someone from an Ally guild appears on your screen."],
        L["Keep enabled to spot friendly coalition members quickly in the world."]
    )

    local spotterWatchlistCb = CreateCheckbox(
        content,
        L["Show direction and distance for Watchlist players on Target Radar"],
        spotterAllyCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterNotifyWatchlist ~= false end,
        function(checked)
            ns.db.settings.spotterNotifyWatchlist = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Spotter Watchlist Radar"],
        L["Automatically displays the directional arrow and distance on Target Radar whenever a player on your Watchlist appears nearby."],
        L["Keep checked to track Watchlist targets automatically on screen without waiting for chat links."]
    )

    local spotterFriendsCb = CreateCheckbox(
        content,
        L["Show direction and distance for Friends on Target Radar"],
        spotterWatchlistCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterNotifyFriends ~= false end,
        function(checked)
            ns.db.settings.spotterNotifyFriends = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Spotter Friends Radar"],
        L["Displays the directional arrow and yard distance on Target Radar when a WoW Friend or Battle.net Friend is spotted nearby."],
        L["Combine with 'Ignore Party/Raid members' below to hide friends once you already invited them into your group."]
    )

    local spotterBlockedCb = CreateCheckbox(
        content,
        L["Notify when a Blocked or Avoided player appears nearby"],
        spotterFriendsCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterNotifyBlocked ~= false end,
        function(checked)
            ns.db.settings.spotterNotifyBlocked = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Spotter Blocked Alerts"],
        L["Alerts and displays on Target Radar whenever someone on your WoW Ignore list or SocialCentral 'Avoid' red flag appears nearby."],
        L["Strangers outside Friends, Watchlist, Guild/Diplomacy, and Blocked lists are never scanned repeatedly."]
    )

    local spotterSameCb = CreateCheckbox(
        content,
        L["Notify when a Same Clan guildmate appears on screen"],
        spotterBlockedCb,
        -6,
        function() return ns.db and ns.db.settings and ns.db.settings.spotterNotifySameClan == true end,
        function(checked)
            ns.db.settings.spotterNotifySameClan = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Spotter Same Clan Alerts"],
        L["Highlights and notifies when one of your own guildmates appears on screen."],
        L["Uncheck if you only want notifications for Ally or Enemy guilds."]
    )

    local spotterIgnoreGroupCb = CreateCheckbox(
        content,
        L["Ignore current Party/Raid members on automatic Target Radar"],
        spotterSameCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterIgnoreGroup ~= false end,
        function(checked)
            ns.db.settings.spotterIgnoreGroup = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Spotter Ignore Group"],
        L["Hides automatic Target Radar popups for players who are already in your current Party or Raid group."],
        L["Recommended to keep checked to avoid screen clutter during dungeons and raids."]
    )

    local spotterSoundCb = CreateCheckbox(
        content,
        L["Play alert chime on Enemy / Ally Clan sighting"],
        spotterIgnoreGroupCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.spotterSound ~= false end,
        function(checked)
            ns.db.settings.spotterSound = checked
            ns:Emit("SETTINGS_UPDATED")
        end,
        L["Help: Spotter Sound"],
        L["Plays a distinct alert chime when an Enemy, Ally, or Same-Clan player triggers a Spotter notification."],
        L["Uncheck for silent visual alerts only."]
    )

    local buffsHeader = AddSectionHeader(
        content,
        L["World Buffs (Classic & Forever)"],
        spotterSoundCb,
        -14,
        L["Help: World Buffs"],
        L["Tracks active Classic World Buffs, detects city drop announcements in real time, and lets you report your current buffs to party, raid, or guild."],
        L["Click 'Post in Chat' to pre-fill your buffs into chat, or browse the list to check sources, drop timers, and WoW Forever raid-suppression rules."]
    )

    local buffAlertCb = CreateCheckbox(
        content,
        L["World Buff Drop Alerts"],
        buffsHeader,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.worldBuffsAlerts ~= false end,
        function(checked)
            if ns.db and ns.db.settings then
                ns.db.settings.worldBuffsAlerts = checked
            end
        end,
        L["Help: World Buff Drop Alerts"],
        L["Prints a local chat notification whenever an NPC announces the turn-in of Onyxia, Nefarian, Rend Blackhand, or Hakkar heads in town."],
        L["Alerts you ~6 to 15 seconds before the buff lands so you have time to log in or reposition."]
    )

    local buffSoundCb = CreateCheckbox(
        content,
        L["Play chime on World Buff drop alert"],
        buffAlertCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.worldBuffsSound ~= false end,
        function(checked)
            if ns.db and ns.db.settings then
                ns.db.settings.worldBuffsSound = checked
            end
        end,
        L["Help: World Buff Sound Chime"],
        L["Plays an audio chime when an NPC announces an incoming world buff drop."],
        L["Uncheck if you prefer silent chat notifications only."]
    )

    local buffMapPinsCb = CreateCheckbox(
        content,
        L["Show World Buff pins on World Map (M)"],
        buffSoundCb,
        -6,
        function() return not ns.db or not ns.db.settings or ns.db.settings.worldBuffsMapPins ~= false end,
        function(checked)
            if ns.db and ns.db.settings then
                ns.db.settings.worldBuffsMapPins = checked
            end
            if ns.LFGFrameTab and ns.LFGFrameTab.RefreshWorldMapBuffs then
                ns.LFGFrameTab:RefreshWorldMapBuffs()
            end
        end,
        L["Help: World Buffs Map Integration"],
        L["Shows interactive World Buff pins at Classic/Forever drop zones and open-world sources directly on the World Map (M)."],
        L["Leave checked to see buff spots directly on the map with hover tooltips, or uncheck to keep only the compact corner summary badge."]
    )

    local openBuffsBtn = ns.Theme:CreateButton(content, 210, 24, L["Open World Buffs Tracker"], "default")
    ns.Theme:AutoFitButton(openBuffsBtn, 180, 18, 300)
    openBuffsBtn:SetPoint("TOPLEFT", buffMapPinsCb, "BOTTOMLEFT", 4, -8)
    openBuffsBtn:SetScript("OnClick", function()
        CloseSettingsBeforeJump()
        if ns.UI and ns.UI.ShowHub then
            ns.UI:ShowHub("buffs")
        elseif ns.UI and ns.UI.OpenTab then
            ns.UI:OpenTab("buffs")
        elseif ns.LFGFrameTab and ns.LFGFrameTab.OpenOfficialModule then
            ns.LFGFrameTab:OpenOfficialModule("buffs")
        end
    end)
    HelpBtn(
        content,
        openBuffsBtn,
        L["Help: Open World Buffs Tracker"],
        L["Opens the World Buffs tab in SocialCentral to view active buffs, drop timers, and classic buff sources."],
        L["Click to review all classic world buffs and their status in WoW Forever."]
    )

    local openRadarBtn = ns.Theme:CreateButton(content, 178, 24, L["Open Target Radar"], "primary")
    ns.Theme:AutoFitButton(openRadarBtn, 150, 18, 240)
    openRadarBtn:SetPoint("TOPLEFT", openBuffsBtn, "BOTTOMLEFT", 0, -12)
    openRadarBtn:SetScript("OnClick", function()
        if ns.SpotterHUD and ns.SpotterHUD.Toggle then
            ns.SpotterHUD:Toggle()
        end
    end)
    HelpBtn(
        content,
        openRadarBtn,
        L["Help: Open Target Radar"],
        L["Manually opens the Target Radar HUD to test target tracking, distance, and directional compass."],
        L["Click this button or type '/sc radar' to show or hide the floating radar."]
    )

    local resetPosBtn = ns.Theme:CreateButton(content, 200, 24, L["Reset All Window Positions"], "default")
    ns.Theme:AutoFitButton(resetPosBtn, 170, 18, 270)
    resetPosBtn:SetPoint("LEFT", openRadarBtn, "RIGHT", 32, 0)
    resetPosBtn:SetScript("OnClick", function()
        if ns.Theme and ns.Theme.ResetAllWindowPositions then
            ns.Theme:ResetAllWindowPositions()
        end
    end)
    HelpBtn(
        content,
        resetPosBtn,
        L["Help: Reset Window Positions"],
        L["Restores the default screen positions of the Main Window, Target Radar HUD, and all popup dialogs."],
        L["Use this if any window was moved off-screen or after changing screen resolution."]
    )

    local resetPromptBtn = ns.Theme:CreateButton(content, 210, 24, L["Reset Radar Prompt"], "default")
    ns.Theme:AutoFitButton(resetPromptBtn, 180, 20, 290)
    resetPromptBtn:SetPoint("TOPLEFT", openRadarBtn, "BOTTOMLEFT", 0, -8)
    resetPromptBtn:SetScript("OnClick", function()
        if ns.db and ns.db.settings then
            ns.db.settings.spotterPromptAnswered = false
        end
        if ns.SpotterHUD and ns.SpotterHUD.ShowFirstTimePrompt then
            ns.SpotterHUD:ShowFirstTimePrompt()
        end
    end)
    HelpBtn(
        content,
        resetPromptBtn,
        L["Help: Reset Radar Prompt"],
        L["Resets the first-time Target Radar confirmation so the prompt dialog appears again."],
        L["Use if you previously dismissed the radar prompt and wish to review the setup options."]
    )

    syncFns[#syncFns + 1] = function()
        ns.Theme:StyleButton(updateLinkBtn, "default")
        ns.Theme:SetButtonActive(updateLinkBtn, false, "default")
        ns.Theme:StyleButton(openBuffsBtn, "default")
        ns.Theme:StyleButton(openRadarBtn, "primary")
        ns.Theme:StyleButton(resetPosBtn, "default")
        ns.Theme:StyleButton(resetPromptBtn, "default")
    end

    if ns.Theme and ns.Theme.RegisterListener then
        ns.Theme:RegisterListener(function()
            if panel and panel:IsShown() then
                for _, sync in ipairs(syncFns) do
                    sync()
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
