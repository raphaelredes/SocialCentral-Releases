local _, ns = ...

local L = ns.L

local SettingsMod = {}
ns.Settings = SettingsMod

local panel
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
    label:SetText(labelText)
    cb._scLabel = label

    if helpTitle then
        HelpBtn(parent, label, helpTitle, helpWhat, helpHow)
    end

    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
    end)

    syncFns[#syncFns + 1] = function()
        cb:SetChecked(getter() and true or false)
    end
    return cb
end

local function CreateChoiceRow(parent, anchorTo, yOffset, options, getter, setter)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOffset or -6)
    row:SetSize(560, 26)

    local buttons = {}
    local prev
    for _, opt in ipairs(options) do
        local btn = ns.Theme:CreateButton(row, opt.width or 170, 24, opt.label, "default")
        if not prev then
            btn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        else
            btn:SetPoint("LEFT", prev, "RIGHT", 8, 0)
        end
        btn:SetScript("OnClick", function()
            setter(opt.value)
            for _, sync in ipairs(syncFns) do
                sync()
            end
        end)
        buttons[#buttons + 1] = { btn = btn, value = opt.value }
        prev = btn
    end

    syncFns[#syncFns + 1] = function()
        local current = getter()
        for _, item in ipairs(buttons) do
            ns.Theme:SetButtonActive(item.btn, current == item.value, "default")
        end
    end
    return row
end

local function CreateStepperRow(parent, anchorTo, yOffset, minVal, maxVal, unit, getter, setter)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOffset or -6)
    row:SetSize(320, 26)

    local minus = ns.Theme:CreateButton(row, 28, 24, "-", "default")
    minus:SetPoint("LEFT", row, "LEFT", 0, 0)

    local valueText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valueText:SetPoint("LEFT", minus, "RIGHT", 10, 0)
    valueText:SetWidth(60)
    valueText:SetJustifyH("CENTER")

    local plus = ns.Theme:CreateButton(row, 28, 24, "+", "default")
    plus:SetPoint("LEFT", valueText, "RIGHT", 10, 0)

    local function RefreshValue()
        valueText:SetText(string.format("%d %s", getter(), unit))
        ns.Theme:SetButtonActive(minus, false, "default")
        ns.Theme:SetButtonActive(plus, false, "default")
    end

    minus:SetScript("OnClick", function()
        local v = math.max(minVal, getter() - 1)
        setter(v)
        RefreshValue()
    end)

    plus:SetScript("OnClick", function()
        local v = math.min(maxVal, getter() + 1)
        setter(v)
        RefreshValue()
    end)

    syncFns[#syncFns + 1] = RefreshValue
    return row
end

local function BuildPanel()
    panel = CreateFrame("Frame", "SocialCentralSettingsPanel", UIParent)
    panel.name = "SocialCentral"

    local scrollFrame = CreateFrame("ScrollFrame", "SocialCentralSettingsScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(590, 650)
    scrollFrame:SetScrollChild(content)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetText("SocialCentral  v" .. (ns.version or "0.2.0"))

    local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText(L["Unified social hub for WoW: Forever."])

    local langHeader = AddSectionHeader(
        content,
        L["Language (Game Options)"],
        subtitle,
        -12,
        L["Help: Game Language"],
        L["Automatically matches the text language chosen in your WoW Game Options (English, Portuguese ptBR/ptPT, Spanish esES/esMX)."],
        L["Change Text Language in Blizzard System Settings if needed; SocialCentral switches all texts automatically without violating addon rules."]
    )
    local langValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    langValue:SetPoint("TOPLEFT", langHeader, "BOTTOMLEFT", 0, -4)
    langValue:SetText(L["Active Language: %s (%s)"]:format(ns.activeLangLabel or "English", ns.activeLocale or "enUS"))

    local themeHeader = AddSectionHeader(
        content,
        L["Theme"],
        langValue,
        -12,
        L["Help: Theme"],
        L["Switches between Modern Dark (sleek panel) and Native Warcraft (classic gold & stone borders)."],
        L["Click your preferred theme button; the change applies immediately across all SocialCentral windows."]
    )
    local themeRow = CreateChoiceRow(content, themeHeader, -6, {
        { value = "dark", label = L["Modern Dark"], width = 160 },
        { value = "native", label = L["Native Warcraft"], width = 160 },
    }, function()
        return ns.db and ns.db.settings.theme or "dark"
    end, function(val)
        ns.db.settings.theme = val
        if ns.Theme then
            ns.Theme:NotifyChanged()
        end
    end)

    local whoHeader = AddSectionHeader(
        content,
        L["/who mode"],
        themeRow,
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
        end,
        L["Help: Watchlist Online Alerts"],
        L["Prints a local chat notification whenever a Watchlist character transitions from offline to online."],
        L["Triggered safely when /who, Friends, Guild, Battle.net, or Nearby spots a watched friend online (120s anti-spam debounce)."]
    )

    local soundCb = CreateCheckbox(
        content,
        L["Play sound on Watchlist online alert"],
        alertCb,
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

    local verCb = CreateCheckbox(
        content,
        L["Check for addon updates (DBM-style peer alerts)"],
        soundCb,
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

    CreateCheckbox(
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

    syncFns[#syncFns + 1] = function()
        ns.Theme:SetButtonActive(updateLinkBtn, false, "default")
    end

    if ns.Theme and ns.Theme.RegisterListener then
        ns.Theme:RegisterListener(function()
            for _, sync in ipairs(syncFns) do
                sync()
            end
        end)
    end

    panel:SetScript("OnShow", function()
        for _, sync in ipairs(syncFns) do
            sync()
        end
    end)
end

--- Register SocialCentral inside Blizzard Settings.
function SettingsMod:Register()
    if panel then
        return
    end
    BuildPanel()

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
