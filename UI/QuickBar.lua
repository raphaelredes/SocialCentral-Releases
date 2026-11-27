local _, ns = ...

local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })
local Safe = ns.Safe
local Compat = ns.Compat

local QuickBar = {
    initialized = false,
    frame = nil,
    buttons = {},
    customModal = nil,
}
ns.QuickBar = QuickBar
table.insert(ns.modules, QuickBar)

local MIN_BUTTONS = 5
local MAX_BUTTONS = 10
local BTN_SIZE = 30
local BTN_GAP = 4
local PAD = 5
local GRIP_THICK = 18

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local ICON_TEX = "Interface\\AddOns\\SocialCentral\\Media\\icon.tga"
local GLOW_TEX = "Interface\\AddOns\\SocialCentral\\Media\\toast-glow"
local DOT_TEX = "Interface\\AddOns\\SocialCentral\\Media\\dot"

local COL_QUICK_REPLY = { 0.32, 0.72, 1.0 }
local COL_GATHER = { 0.28, 0.94, 0.48 }
local COL_RADAR = { 1.0, 0.78, 0.24 }
local COL_LOOT = { 0.32, 0.90, 0.50 }
local COL_DND = { 1.0, 0.56, 0.20 }
local COL_WHO = { 0.45, 0.78, 1.0 }
local COL_CONV = { 0.96, 0.76, 0.24 }
local COL_PRIVACY = { 0.74, 0.50, 1.0 }
local COL_BORDER_FALLBACK = { 0.28, 0.30, 0.35, 1.0 }
local COL_SHEEN_BLIZZ = { 0.96, 0.78, 0.32, 0.65 }
local COL_SHEEN_DARK = { 0.35, 0.76, 1.0, 0.55 }
local COL_SHEEN_NATIVE = { 0.92, 0.68, 0.26, 0.55 }

local DEFAULT_BUTTON_ORDER = {
    "hub",
    "quick_reply",
    "gather_sparkles",
    "radar",
    "loot_rolls",
    "dnd",
    "settings",
}

local QUICK_PRESETS = {
    {
        id = "raiding",
        labelKey = "Preset: Dungeon & Raid",
        buttons = { "hub", "quick_reply", "loot_rolls", "dnd", "audit_buffs", "reset_instances", "dungeon_runs" },
    },
    {
        id = "gathering",
        labelKey = "Preset: Gather & World",
        buttons = { "gather_sparkles", "radar", "quick_reply", "check_watchlist", "dnd", "settings" },
    },
    {
        id = "social",
        labelKey = "Preset: Social & Guild",
        buttons = { "hub", "conversations", "quick_reply", "copy_chat", "check_watchlist", "streamer_mode", "settings" },
    },
}

local function IsInCombatNow()
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        return true
    end
    return false
end

local function OpenSettingsSafe(tabId, sectionKey)
    if ns.Settings and ns.Settings.Open then
        ns.Settings:Open(tabId, sectionKey)
    elseif ns.Settings and ns.Settings.Toggle then
        ns.Settings:Toggle()
    end
end

local ACTION_CATALOG = {
    {
        id = "hub",
        nameKey = "Main Window",
        descKey = "Opens or hides the main SocialCentral window.",
        icon = ICON_TEX,
        onClick = function()
            if ns.Minimap and ns.Minimap.ClearPreviewCounts then
                ns.Minimap:ClearPreviewCounts()
            end
            if ns.UI and ns.UI.Toggle then
                ns.UI:Toggle()
            elseif ns.UI and ns.UI.ShowHub then
                ns.UI:ShowHub()
            end
        end,
    },
    {
        id = "quick_reply",
        nameKey = "Quick Reply",
        descKey = "Opens the floating Quick Reply chat box.",
        icon = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up",
        onClick = function()
            if ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown() then
                ns.QuickReply.frame:Hide()
            elseif ns.QuickReply and ns.QuickReply.OpenPreviewOrLatest then
                ns.QuickReply:OpenPreviewOrLatest()
            elseif ns.UI and ns.UI.ShowHub then
                ns.UI:ShowHub("chat")
            end
        end,
        getState = function()
            local open = ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown() == true
            local unread = (ns.Chat and ns.Chat.GetTotalUnread) and (ns.Chat:GetTotalUnread(true) or 0) or 0
            return open, unread, COL_QUICK_REPLY
        end,
    },
    {
        id = "gather_sparkles",
        isToggle = true,
        nameKey = "Collectible Sparkles",
        descKey = "1-click ON/OFF highlight on nearby herbs, ore & chests (halo + game icon).",
        icon = "Interface\\Icons\\INV_Misc_Flower_02",
        onClick = function()
            local s = ns.db and ns.db.settings
            if not s then return end
            local currentlyActive = (s.gatherHighlightEnabled == true) and (s.gatherHighlightEnhanceRange ~= false)
            local nextOn = not currentlyActive
            if nextOn then
                s.gatherHighlightPromptAnswered = true
                s.gatherHighlightEnhanceRange = true
                s.gatherHighlightOutline = true
            end
            if ns.GatherHighlight and ns.GatherHighlight.SetEnabled then
                ns.GatherHighlight:SetEnabled(nextOn, true)
            else
                s.gatherHighlightEnabled = nextOn
                ns:Emit("SETTINGS_UPDATED")
            end
        end,
        getState = function()
            local s = ns.db and ns.db.settings
            local active = (s ~= nil) and (s.gatherHighlightEnabled == true) and (s.gatherHighlightEnhanceRange ~= false)
            return active, 0, COL_GATHER
        end,
    },
    {
        id = "radar",
        isToggle = true,
        nameKey = "Target Radar",
        descKey = "Shows or hides the nearby players Target Radar.",
        icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
        onClick = function()
            if ns.SpotterHUD and ns.SpotterHUD.Toggle then
                ns.SpotterHUD:Toggle()
            end
        end,
        getState = function()
            local shown = _G.SocialCentralSpotterFrame and _G.SocialCentralSpotterFrame:IsShown() == true
            local cnt = 0
            if ns.Spotter and ns.Spotter.GetCounts then
                local _, _, _, tot = ns.Spotter:GetCounts()
                cnt = tot or 0
            end
            return shown, cnt, COL_RADAR
        end,
    },
    {
        id = "loot_rolls",
        nameKey = "Loot Roll Results",
        descKey = "Opens saved Group Drops & /roll results anytime.",
        icon = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
        onClick = function()
            if IsShiftKeyDown and IsShiftKeyDown() and ns.LootRoll and ns.LootRoll.GetActiveCount and (ns.LootRoll:GetActiveCount() or 0) > 0 then
                if ns.LootRollUI and ns.LootRollUI.ShowActiveRollCard then
                    ns.LootRollUI:ShowActiveRollCard()
                    return
                end
            end
            if ns.LootRollUI and ns.LootRollUI.ToggleResultsWindow then
                ns.LootRollUI:ToggleResultsWindow()
            end
        end,
        getState = function()
            local active = (ns.LootRoll and ns.LootRoll.GetActiveCount) and (ns.LootRoll:GetActiveCount() or 0) or 0
            local unread = (ns.LootRoll and ns.LootRoll.GetUnreadCount) and (ns.LootRoll:GetUnreadCount() or 0) or 0
            local shown = ns.LootRollUI and ns.LootRollUI.resultsWindow and ns.LootRollUI.resultsWindow:IsShown() == true
            local badge = (active > 0) and active or unread
            return shown or (active > 0) or (unread > 0), badge, COL_LOOT
        end,
    },
    {
        id = "dnd",
        isToggle = true,
        nameKey = "Do Not Disturb",
        descKey = "Silence or resume popups & notification sounds in 1 click.",
        icon = "Interface\\AddOns\\SocialCentral\\Media\\bell-off",
        onClick = function()
            local cur = ns.db and ns.db.settings and ns.db.settings.doNotDisturb == true
            local nextVal = not cur
            if Compat and Compat.SetDoNotDisturb then
                Compat.SetDoNotDisturb(nextVal)
            elseif ns.db and ns.db.settings then
                ns.db.settings.doNotDisturb = nextVal
                ns:Emit("SETTINGS_UPDATED")
            end
        end,
        getState = function()
            local s = ns.db and ns.db.settings
            local active = (s ~= nil) and (s.doNotDisturb == true)
            local badge = 0
            if active then
                if type(s.dndUntil) == "number" and s.dndUntil > time() then
                    badge = tostring(math.max(1, math.ceil((s.dndUntil - time()) / 60))) .. "m"
                elseif s.dndUntilLeaveInstance == true then
                    badge = L["Dg"]
                elseif s.dndUntilLeaveGroup == true then
                    badge = L["Grp"]
                end
            end
            return active, badge, COL_DND
        end,
    },
    {
        id = "check_watchlist",
        nameKey = "Check Watchlist (/who)",
        descKey = "Verifies the next player on your Watchlist safely out of combat.",
        icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
        onClick = function()
            if IsInCombatNow() then
                ns:Print("%s", L["In Combat"])
                return
            end
            if ns.Watchlist and ns.Watchlist.CheckNext then
                ns.Watchlist:CheckNext()
            end
        end,
        getState = function()
            local cd = (ns.Watchlist and ns.Watchlist.GetCooldownRemaining) and (ns.Watchlist:GetCooldownRemaining() or 0) or 0
            return false, (cd > 0 and math.ceil(cd) or 0), COL_WHO
        end,
    },
    {
        id = "reset_instances",
        nameKey = "Reset Dungeon Instances",
        descKey = "Asks to reset all your dungeon instances right away.",
        icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
        onClick = function()
            if ns.UI and ns.UI.ConfirmResetInstances then
                ns.UI:ConfirmResetInstances()
            elseif ns.Group and ns.Group.ResetDungeonInstances then
                ns.Group:ResetDungeonInstances()
            end
        end,
    },
    {
        id = "audit_buffs",
        nameKey = "Audit Raid Buffs",
        descKey = "Scans your party or raid for missing buffs and prepares a chat draft.",
        icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
        onClick = function()
            if ns.Group and ns.Group.OpenMissingBuffsDraft then
                ns.Group:OpenMissingBuffsDraft()
            end
        end,
    },
    {
        id = "dungeon_runs",
        nameKey = "Dungeon & Raid Log",
        descKey = "Opens your recorded dungeon and raid group history.",
        icon = "Interface\\Icons\\INV_Misc_Note_01",
        onClick = function()
            if ns.UI and ns.UI.OpenGroupRunsView then
                ns.UI:OpenGroupRunsView()
            elseif ns.UI and ns.UI.ShowHub then
                ns.UI:ShowHub("group")
            end
        end,
    },
    {
        id = "conversations",
        nameKey = "Conversations",
        descKey = "Opens SocialCentral Conversations & Private Rooms.",
        icon = "Interface\\AddOns\\SocialCentral\\Media\\toast-mail",
        onClick = function()
            if ns.UI and ns.UI.ShowHub then
                ns.UI:ShowHub("chat")
            elseif ns.UI and ns.UI.OpenTab then
                ns.UI:OpenTab("chat")
            end
        end,
        getState = function()
            local unread = (ns.Chat and ns.Chat.GetTotalUnread) and (ns.Chat:GetTotalUnread(true) or 0) or 0
            return false, unread, COL_CONV
        end,
    },
    {
        id = "copy_chat",
        nameKey = "Copy Official Chat",
        descKey = "Opens recent Official Chat lines ready to copy with Ctrl+C.",
        icon = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
        onClick = function()
            if ns.Chat and ns.Chat.OpenCopyOfficialChat then
                ns.Chat:OpenCopyOfficialChat(60)
            end
        end,
    },
    {
        id = "streamer_mode",
        isToggle = true,
        nameKey = "Streamer / Privacy Mode",
        descKey = "Masks Real IDs and private whisper text in popups in 1 click.",
        icon = "Interface\\AddOns\\SocialCentral\\Media\\lock-closed",
        onClick = function()
            if ns.db and ns.db.settings then
                ns.db.settings.streamerMode = not (ns.db.settings.streamerMode == true)
                ns:Emit("SETTINGS_UPDATED")
                ns:Emit("SOCIAL_UPDATED")
                ns:Emit("CHAT_UPDATED")
            end
        end,
        getState = function()
            local active = ns.db and ns.db.settings and ns.db.settings.streamerMode == true
            return active, 0, COL_PRIVACY
        end,
    },
    {
        id = "settings",
        nameKey = "Settings",
        descKey = "Opens SocialCentral Settings directly.",
        icon = "Interface\\Icons\\Trade_Engineering",
        onClick = function()
            OpenSettingsSafe()
        end,
    },
}

local ACTION_BY_ID = {}
for _, act in ipairs(ACTION_CATALOG) do
    ACTION_BY_ID[act.id] = act
end

local function GetSettingsTable()
    return (ns.db and ns.db.settings) or (SocialCentralDB and SocialCentralDB.settings)
end

local function SyncSelectedListToSaved(list)
    QuickBar._cachedIds = nil
    local s = ns.db and ns.db.settings
    if s then s.quickBarButtons = list end
    if SocialCentralDB and SocialCentralDB.settings and SocialCentralDB.settings ~= s then
        SocialCentralDB.settings.quickBarButtons = list
    end
end

function QuickBar:GetCatalog()
    return ACTION_CATALOG
end

function QuickBar:GetActionById(id)
    return ACTION_BY_ID[id]
end

function QuickBar:GetSelectedIds()
    local s = GetSettingsTable()
    local raw = s and s.quickBarButtons
    local out = {}
    local seen = {}
    if type(raw) == "table" then
        for _, id in ipairs(raw) do
            if type(id) == "string" and ACTION_BY_ID[id] and not seen[id] then
                seen[id] = true
                out[#out + 1] = id
                if #out >= MAX_BUTTONS then
                    break
                end
            end
        end
    end
    if #out < MIN_BUTTONS then
        for _, defId in ipairs(DEFAULT_BUTTON_ORDER) do
            if ACTION_BY_ID[defId] and not seen[defId] then
                seen[defId] = true
                out[#out + 1] = defId
                if #out >= MIN_BUTTONS and type(raw) == "table" and #raw > 0 then
                    break
                end
                if #out >= #DEFAULT_BUTTON_ORDER and (type(raw) ~= "table" or #raw == 0) then
                    break
                end
            end
        end
        if #out < MIN_BUTTONS then
            for _, act in ipairs(ACTION_CATALOG) do
                if not seen[act.id] then
                    seen[act.id] = true
                    out[#out + 1] = act.id
                    if #out >= MIN_BUTTONS then break end
                end
            end
        end
    end
    local changed = (type(raw) ~= "table") or (#raw ~= #out)
    if not changed then
        for i = 1, #out do
            if raw[i] ~= out[i] then
                changed = true
                break
            end
        end
    end
    if changed then
        SyncSelectedListToSaved(out)
    end
    return out
end

local function GetSelectedIdsCached()
    if QuickBar._cachedIds then
        return QuickBar._cachedIds
    end
    local ids = QuickBar:GetSelectedIds()
    QuickBar._cachedIds = ids
    return ids
end

function QuickBar:GetOrientation()
    local s = GetSettingsTable()
    if s and s.quickBarOrientation == "vertical" then
        return "vertical"
    end
    return "horizontal"
end

function QuickBar:SetOrientation(mode)
    local norm = (mode == "vertical") and "vertical" or "horizontal"
    local s = ns.db and ns.db.settings
    if s then s.quickBarOrientation = norm end
    if SocialCentralDB and SocialCentralDB.settings then
        SocialCentralDB.settings.quickBarOrientation = norm
    end
    self:Refresh()
    if self.customModal and self.customModal:IsShown() and self.customModal.RefreshRows then
        self.customModal:RefreshRows()
    end
    ns:Emit("SETTINGS_UPDATED")
end

function QuickBar:ToggleOrientation()
    self:SetOrientation(self:GetOrientation() == "vertical" and "horizontal" or "vertical")
end

function QuickBar:SetEnabled(on)
    local enabled = (on == true)
    local s = ns.db and ns.db.settings
    if s then s.quickBarEnabled = enabled end
    if SocialCentralDB and SocialCentralDB.settings then
        SocialCentralDB.settings.quickBarEnabled = enabled
    end
    self:Refresh()
    if self.customModal and self.customModal:IsShown() and self.customModal.RefreshRows then
        self.customModal:RefreshRows()
    end
    ns:Emit("SETTINGS_UPDATED")
end

function QuickBar:ResetPosition()
    local Theme = ns.Theme
    if Theme and Theme.ResetWindowPosition then
        Theme:ResetWindowPosition("quick_bar")
    elseif self.frame then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("TOP", UIParent, "TOP", 0, -48)
    end
end

function QuickBar:RestoreDefaultButtons()
    local copy = {}
    for i, id in ipairs(DEFAULT_BUTTON_ORDER) do
        copy[i] = id
    end
    SyncSelectedListToSaved(copy)
    self:Refresh()
    if self.customModal and self.customModal:IsShown() and self.customModal.RefreshRows then
        self.customModal:RefreshRows()
    end
    ns:Emit("SETTINGS_UPDATED")
end

local function ApplyDefaultBarPlacement(win)
    if not (win and UIParent) then return end
    win:ClearAllPoints()
    win:SetPoint("TOP", UIParent, "TOP", 0, -48)
end

local function ApplySolidOpaqueBg(win, pal)
    if not (win and win._solidOpaqueBg) then return end
    local bg = (pal and pal.windowBg) or { 0.08, 0.08, 0.09, 1.0 }
    win._solidOpaqueBg:SetVertexColor(bg[1], bg[2], bg[3], 1.0)
end

function QuickBar:ApplyPreset(presetId)
    for _, pre in ipairs(QUICK_PRESETS) do
        if pre.id == presetId then
            local copy = {}
            for i, id in ipairs(pre.buttons) do
                copy[i] = id
            end
            SyncSelectedListToSaved(copy)
            self:Refresh()
            if self.customModal and self.customModal:IsShown() and self.customModal.RefreshRows then
                self.customModal:RefreshRows()
            end
            ns:Emit("SETTINGS_UPDATED")
            return true
        end
    end
    return false
end

local function PopulateBarControlsMenu(menuRoot)
    menuRoot:CreateButton(L["Customize Buttons (5-10)..."], function()
        QuickBar:OpenCustomizeModal()
    end)
    local preSub = menuRoot:CreateButton(L["Quick Presets"])
    if preSub and preSub.CreateButton then
        for _, pre in ipairs(QUICK_PRESETS) do
            local pid = pre.id
            preSub:CreateButton(L[pre.labelKey] or pre.labelKey, function()
                QuickBar:ApplyPreset(pid)
            end)
        end
    end
    menuRoot:CreateDivider()
    menuRoot:CreateRadio(L["Horizontal"], function()
        return QuickBar:GetOrientation() == "horizontal"
    end, function()
        QuickBar:SetOrientation("horizontal")
    end)
    menuRoot:CreateRadio(L["Vertical"], function()
        return QuickBar:GetOrientation() == "vertical"
    end, function()
        QuickBar:SetOrientation("vertical")
    end)
    menuRoot:CreateDivider()
    menuRoot:CreateCheckbox(L["Lock bar position"], function()
        local s = GetSettingsTable()
        return s and s.quickBarLocked == true
    end, function()
        local s = GetSettingsTable()
        if s then
            local nxt = not (s.quickBarLocked == true)
            s.quickBarLocked = nxt
            if SocialCentralDB and SocialCentralDB.settings then
                SocialCentralDB.settings.quickBarLocked = nxt
            end
            if QuickBar.frame then
                QuickBar.frame._scLocked = nxt
            end
            ns:Emit("SETTINGS_UPDATED")
        end
    end)
    menuRoot:CreateButton(L["Reset Position"], function()
        QuickBar:ResetPosition()
    end)
    menuRoot:CreateButton(L["Hide Quick Bar"], function()
        QuickBar:SetEnabled(false)
        ns:Print("%s", L["Quick Access Bar hidden. Re-enable anytime in Settings or Minimap menu."])
    end)
    menuRoot:CreateDivider()
    menuRoot:CreateButton(L["Open Settings"], function()
        OpenSettingsSafe("overview", "quickbar")
    end)
end

local function ToggleSimpleSetting(key, defaultTrue, emitName)
    local s = GetSettingsTable()
    if not s then return end
    local cur = defaultTrue and (s[key] ~= false) or (s[key] == true)
    local nxt = not cur
    s[key] = nxt
    if SocialCentralDB and SocialCentralDB.settings then
        SocialCentralDB.settings[key] = nxt
    end
    ns:Emit(emitName or "SETTINGS_UPDATED")
    if emitName and emitName ~= "SETTINGS_UPDATED" then
        ns:Emit("SETTINGS_UPDATED")
    end
    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
end

local function IsSettingOn(key, defaultTrue)
    local s = GetSettingsTable()
    if not s then return defaultTrue == true end
    if defaultTrue then
        return s[key] ~= false
    end
    return s[key] == true
end

local function PopulateActionSpecificMenu(root, act)
    local id = act and act.id
    root:CreateTitle(L[act.nameKey] or act.nameKey)

    if id == "dnd" then
        local function ApplyDnd(state, durSec, untilInst, untilGrp)
            if Compat and Compat.SetDoNotDisturb then
                Compat.SetDoNotDisturb(state, durSec, untilInst, untilGrp)
            elseif ns.db and ns.db.settings then
                ns.db.settings.doNotDisturb = (state == true)
                ns:Emit("SETTINGS_UPDATED")
            end
            QuickBar:Refresh()
        end
        local s = GetSettingsTable()
        local isDnd = s and s.doNotDisturb == true
        if isDnd then
            root:CreateButton(L["Turn Off Do Not Disturb"], function() ApplyDnd(false) end)
        else
            root:CreateButton(L["Turn On Do Not Disturb"], function() ApplyDnd(true, nil, false, false) end)
        end
        root:CreateDivider()
        root:CreateTitle(L["Auto-Resume After:"])
        root:CreateButton(L["For 15 minutes"], function() ApplyDnd(true, 900, false, false) end)
        root:CreateButton(L["For 30 minutes"], function() ApplyDnd(true, 1800, false, false) end)
        root:CreateButton(L["For 1 hour"], function() ApplyDnd(true, 3600, false, false) end)
        root:CreateButton(L["For 2 hours"], function() ApplyDnd(true, 7200, false, false) end)
        root:CreateRadio(L["Until leaving instance"], function()
            return isDnd and s and s.dndUntilLeaveInstance == true
        end, function() ApplyDnd(true, nil, true, false) end)
        root:CreateRadio(L["Until leaving group"], function()
            return isDnd and s and s.dndUntilLeaveGroup == true
        end, function() ApplyDnd(true, nil, false, true) end)
        root:CreateRadio(L["Until I turn it off"], function()
            return isDnd and s and (not s.dndUntil or s.dndUntil <= 0) and s.dndUntilLeaveInstance ~= true and s.dndUntilLeaveGroup ~= true
        end, function() ApplyDnd(true, nil, false, false) end)
        root:CreateDivider()
        root:CreateCheckbox(L["Allow Favorites through Do Not Disturb"], function()
            return IsSettingOn("focusAllowFavorites", true)
        end, function() ToggleSimpleSetting("focusAllowFavorites", true) end)
        root:CreateCheckbox(L["Sync with WoW /dnd status"], function()
            return IsSettingOn("syncGameDnd", true)
        end, function() ToggleSimpleSetting("syncGameDnd", true) end)
        root:CreateCheckbox(L["Auto-silence inside Dungeons & Raids"], function()
            return IsSettingOn("autoSilenceInInstances", false)
        end, function() ToggleSimpleSetting("autoSilenceInInstances", false) end)
        root:CreateButton(L["Configure Notifications..."], function()
            OpenSettingsSafe("notifications")
        end)

    elseif id == "gather_sparkles" then
        root:CreateCheckbox(L["Use official object detection & icon (herbs, ore & chests)"], function()
            return IsSettingOn("gatherHighlightEnabled", false) and IsSettingOn("gatherHighlightEnhanceRange", true)
        end, function()
            if act.onClick then act.onClick() end
            QuickBar:Refresh()
        end)
        root:CreateCheckbox(L["Show compact indicator banner when a collectible is in front"], function()
            return IsSettingOn("gatherHighlightFloatBeacon", true)
        end, function() ToggleSimpleSetting("gatherHighlightFloatBeacon", true) end)
        root:CreateCheckbox(L["Show bright sparkle halo & contrast label on nearby node"], function()
            return IsSettingOn("gatherHighlightNameplateGlow", true)
        end, function() ToggleSimpleSetting("gatherHighlightNameplateGlow", true) end)
        root:CreateCheckbox(L["Play subtle chime when spotting a collectible node"], function()
            return IsSettingOn("gatherHighlightSound", false)
        end, function() ToggleSimpleSetting("gatherHighlightSound", false) end)
        root:CreateButton(L["Position Screen Indicator"], function()
            if ns.GatherHighlightUI and ns.GatherHighlightUI.SetBeaconPreviewMode then
                ns.GatherHighlightUI:SetBeaconPreviewMode(true)
            end
        end)
        root:CreateButton(L["Open Radar Settings"], function()
            OpenSettingsSafe("radar", "gather")
        end)

    elseif id == "quick_reply" then
        root:CreateCheckbox(L["Dock Quick Reply over Official WoW Chat (exact size)"], function()
            return IsSettingOn("quickReplyDockToChat", true)
        end, function()
            ToggleSimpleSetting("quickReplyDockToChat", true, "CHAT_UPDATED")
            if ns.QuickReply then
                if IsSettingOn("quickReplyDockToChat", true) and ns.QuickReply.SnapOverOfficialChat then
                    ns.QuickReply:SnapOverOfficialChat()
                elseif ns.QuickReply.SyncDockGeometry then
                    ns.QuickReply:SyncDockGeometry()
                end
            end
        end)
        root:CreateCheckbox(L["Fade when idle"], function()
            return IsSettingOn("quickReplyIdleFade", true)
        end, function() ToggleSimpleSetting("quickReplyIdleFade", true, "CHAT_UPDATED") end)
        root:CreateCheckbox(L["Open Quick Reply on ENTER when messages are pending"], function()
            return IsSettingOn("quickReplyEnterOpen", true)
        end, function() ToggleSimpleSetting("quickReplyEnterOpen", true, "CHAT_UPDATED") end)
        root:CreateCheckbox(L["Lock Quick Reply window position"], function()
            return IsSettingOn("quickReplyLocked", false)
        end, function()
            ToggleSimpleSetting("quickReplyLocked", false, "CHAT_UPDATED")
            if ns.QuickReply and ns.QuickReply.ApplyLockState then
                ns.QuickReply:ApplyLockState()
            end
        end)
        root:CreateButton(L["Edit Quick Replies & Macros..."], function()
            if ns.QuickReply and ns.QuickReply.OpenConfigModal then
                ns.QuickReply:OpenConfigModal()
            end
        end)
        if ns.Chat and ns.Chat.GetTotalUnread and ns.Chat:GetTotalUnread(true) > 0 then
            root:CreateButton(L["Mark All Conversations Read"], function()
                if ns.Chat and ns.Chat.MarkAllRead then ns.Chat:MarkAllRead() end
                QuickBar:Refresh()
            end)
        end
        root:CreateButton(L["Open Settings"], function()
            OpenSettingsSafe("notifications")
        end)

    elseif id == "radar" then
        root:CreateCheckbox(L["Enemy players"], function()
            return IsSettingOn("spotterNotifyEnemy", true)
        end, function() ToggleSimpleSetting("spotterNotifyEnemy", true, "SPOTTER_UPDATED") end)
        root:CreateCheckbox(L["Watchlist"], function()
            return IsSettingOn("spotterNotifyWatchlist", true)
        end, function() ToggleSimpleSetting("spotterNotifyWatchlist", true, "SPOTTER_UPDATED") end)
        root:CreateCheckbox(L["Friends"], function()
            return IsSettingOn("spotterNotifyFriends", true)
        end, function() ToggleSimpleSetting("spotterNotifyFriends", true, "SPOTTER_UPDATED") end)
        root:CreateCheckbox(L["Allies"], function()
            return IsSettingOn("spotterNotifyAlly", true)
        end, function() ToggleSimpleSetting("spotterNotifyAlly", true, "SPOTTER_UPDATED") end)
        root:CreateCheckbox(L["Ignore party/raid members"], function()
            return IsSettingOn("spotterIgnoreGroup", true)
        end, function() ToggleSimpleSetting("spotterIgnoreGroup", true, "SPOTTER_UPDATED") end)
        root:CreateCheckbox(L["Play alert sound"], function()
            return IsSettingOn("spotterSound", true)
        end, function() ToggleSimpleSetting("spotterSound", true, "SPOTTER_UPDATED") end)
        root:CreateButton(L["Open Settings"], function()
            OpenSettingsSafe("radar")
        end)

    elseif id == "loot_rolls" then
        local activeRolls = (ns.LootRoll and ns.LootRoll.GetActiveCount and ns.LootRoll:GetActiveCount()) or 0
        if activeRolls > 0 then
            root:CreateButton(string.format("%s (%d)", L["Show Active Roll Card"], activeRolls), function()
                if ns.LootRollUI and ns.LootRollUI.ShowActiveRollCard then
                    ns.LootRollUI:ShowActiveRollCard()
                end
            end)
        end
        root:CreateCheckbox(L["Enable SocialCentral Group Loot Roll window"], function()
            return IsSettingOn("lootRollHelperEnabled", false)
        end, function()
            if ns.db and ns.db.settings then ns.db.settings.lootRollPromptAnswered = true end
            if SocialCentralDB and SocialCentralDB.settings then SocialCentralDB.settings.lootRollPromptAnswered = true end
            ToggleSimpleSetting("lootRollHelperEnabled", false, "LOOT_ROLL_UPDATED")
        end)
        root:CreateCheckbox(L["Hide official WoW roll bar while active"], function()
            return IsSettingOn("lootRollHideOfficial", true)
        end, function() ToggleSimpleSetting("lootRollHideOfficial", true, "LOOT_ROLL_UPDATED") end)
        root:CreateCheckbox(L["Play sound alert when a group drop is won"], function()
            return IsSettingOn("lootRollWinnerSound", true)
        end, function() ToggleSimpleSetting("lootRollWinnerSound", true, "LOOT_ROLL_UPDATED") end)
        root:CreateCheckbox(L["Epic Win Celebration"], function()
            return IsSettingOn("lootRollWinnerToast", true)
        end, function() ToggleSimpleSetting("lootRollWinnerToast", true, "LOOT_ROLL_UPDATED") end)
        root:CreateCheckbox(L["Announce Winners in Local Chat"], function()
            return IsSettingOn("lootRollWinnerChatAnnounce", true)
        end, function() ToggleSimpleSetting("lootRollWinnerChatAnnounce", true, "LOOT_ROLL_UPDATED") end)
        root:CreateCheckbox(L["Track group /roll (1-100) rounds passively from party/raid chat"], function()
            return IsSettingOn("lootRollTrackChatRolls", true)
        end, function() ToggleSimpleSetting("lootRollTrackChatRolls", true, "LOOT_ROLL_UPDATED") end)
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
                    if ns.db and ns.db.settings then ns.db.settings.lootRollDisplayMode = mId end
                    if SocialCentralDB and SocialCentralDB.settings then SocialCentralDB.settings.lootRollDisplayMode = mId end
                    ns:Emit("SETTINGS_UPDATED")
                    ns:Emit("LOOT_ROLL_UPDATED")
                    QuickBar:Refresh()
                end)
            end
        end
        root:CreateButton(L["All Loot Roll Settings..."], function()
            OpenSettingsSafe("general", "lootroll")
        end)

    elseif id == "hub" then
        for _, tabSpec in ipairs({
            { tid = "watchlist", label = L["Watchlist"] },
            { tid = "social", label = L["Social"] },
            { tid = "chat", label = L["Conversations"] },
            { tid = "clan", label = L["Guild"] },
            { tid = "group", label = L["Group"] },
            { tid = "nearby", label = L["Nearby"] },
            { tid = "alts", label = L["Alts"] },
        }) do
            local tId = tabSpec.tid
            if not (Compat and Compat.IsModuleEnabled) or Compat.IsModuleEnabled(tId) then
                root:CreateButton(tabSpec.label, function()
                    if ns.UI and ns.UI.ShowHub then
                        ns.UI:ShowHub(tId)
                    end
                end)
            end
        end

    elseif id == "conversations" then
        if ns.Chat and ns.Chat.GetTotalUnread and ns.Chat:GetTotalUnread(true) > 0 then
            root:CreateButton(L["Mark All Conversations Read"], function()
                if ns.Chat and ns.Chat.MarkAllRead then ns.Chat:MarkAllRead() end
                QuickBar:Refresh()
            end)
        end
        root:CreateCheckbox(L["Minimap Message Previews"], function()
            return IsSettingOn("msgPreviewEnabled", true)
        end, function() ToggleSimpleSetting("msgPreviewEnabled", true) end)
        root:CreateButton(L["Mentions & Keywords Radar"], function()
            if ns.SocialPanels and ns.SocialPanels.OpenMentionKeywordsModal then
                ns.SocialPanels:OpenMentionKeywordsModal()
            end
        end)
        root:CreateButton(L["Configure Previews..."], function()
            OpenSettingsSafe("notifications", "msgpreview")
        end)

    elseif id == "check_watchlist" then
        root:CreateRadio(L["Silent UI (no Friends popup outside combat)"], function()
            local s = GetSettingsTable()
            return not s or (s.whoMode or "silent_ui") == "silent_ui"
        end, function()
            local s = GetSettingsTable()
            if s then s.whoMode = "silent_ui" end
            ns:Emit("SETTINGS_UPDATED")
        end)
        root:CreateRadio(L["Chat filter (zero touch on FriendsFrame)"], function()
            local s = GetSettingsTable()
            return s and s.whoMode == "chat_filter"
        end, function()
            local s = GetSettingsTable()
            if s then s.whoMode = "chat_filter" end
            ns:Emit("SETTINGS_UPDATED")
        end)
        root:CreateDivider()
        root:CreateButton(L["Open Watchlist"], function()
            if ns.UI and ns.UI.ShowHub then ns.UI:ShowHub("watchlist") end
        end)

    elseif id == "dungeon_runs" then
        root:CreateCheckbox(L["Record started dungeon & raid groups (teammates & total time)"], function()
            return IsSettingOn("dungeonRunLogEnabled", true)
        end, function() ToggleSimpleSetting("dungeonRunLogEnabled", true, "GROUP_UPDATED") end)
        root:CreateButton(L["Reset Dungeon Instances"], function()
            if ns.UI and ns.UI.ConfirmResetInstances then ns.UI:ConfirmResetInstances() end
        end)
        root:CreateButton(L["Open Group"], function()
            if ns.UI and ns.UI.ShowHub then ns.UI:ShowHub("group") end
        end)

    elseif id == "audit_buffs" then
        root:CreateCheckbox(L["Show missing Raid/Dungeon buff audit alert on Blizzard Ready Check"], function()
            return IsSettingOn("groupReadyCheckAudit", true)
        end, function() ToggleSimpleSetting("groupReadyCheckAudit", true) end)
        root:CreateButton(L["Start Ready Check"], function()
            if ns.Group and ns.Group.StartReadyCheck then
                ns.Group:StartReadyCheck()
            end
        end)

    elseif id == "reset_instances" then
        root:CreateButton(L["Reset Dungeon Instances"], function()
            if ns.UI and ns.UI.ConfirmResetInstances then ns.UI:ConfirmResetInstances() end
        end)
        root:CreateButton(L["Dungeon & Raid Log"], function()
            if ns.UI and ns.UI.OpenGroupRunsView then ns.UI:OpenGroupRunsView() end
        end)

    elseif id == "copy_chat" then
        for _, lineCount in ipairs({ 30, 60, 120 }) do
            local n = lineCount
            root:CreateButton(string.format(L["Copy last %d lines"], n), function()
                if ns.Chat and ns.Chat.OpenCopyOfficialChat then
                    ns.Chat:OpenCopyOfficialChat(n)
                end
            end)
        end
        root:CreateDivider()
        root:CreateCheckbox(L["Shorten public channel names in Official Chat ([LFG], [Trade], [Defense])"], function()
            return IsSettingOn("officialChatShortChannels", true)
        end, function() ToggleSimpleSetting("officialChatShortChannels", true, "CHAT_UPDATED") end)

    elseif id == "streamer_mode" then
        root:CreateCheckbox(L["Streamer / Privacy Mode"], function()
            return IsSettingOn("streamerMode", false)
        end, function()
            if act.onClick then act.onClick() end
            QuickBar:Refresh()
        end)
        root:CreateCheckbox(L["Mute All Chat Sounds"], function()
            return not IsSettingOn("chatSound", true)
        end, function() ToggleSimpleSetting("chatSound", true, "CHAT_UPDATED") end)

    elseif id == "settings" then
        for _, secSpec in ipairs({
            { tid = "overview", label = L["Summary & Windows"] },
            { tid = "notifications", label = L["Notifications"] },
            { tid = "radar", label = L["Radar & Map"] },
            { tid = "general", label = L["General & Tools"] },
        }) do
            local tid = secSpec.tid
            root:CreateButton(secSpec.label, function()
                OpenSettingsSafe(tid)
            end)
        end
    end
end

function QuickBar:OpenContextMenu(anchor, act)
    if not (MenuUtil and MenuUtil.CreateContextMenu and anchor) then
        self:OpenCustomizeModal()
        return
    end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        if act then
            PopulateActionSpecificMenu(root, act)
            root:CreateDivider()
            local barSub = root:CreateButton(L["Quick Access Bar"])
            if barSub and barSub.CreateButton then
                PopulateBarControlsMenu(barSub)
            end
        else
            root:CreateTitle(L["Quick Access Bar"])
            PopulateBarControlsMenu(root)
        end
    end)
end

local function RenderQuickBarButtonTooltip(selfBtn)
    local act = selfBtn and selfBtn._action
    if not (act and GameTooltip) then return end
    local orient = QuickBar:GetOrientation()
    GameTooltip:SetOwner(selfBtn, orient == "vertical" and "ANCHOR_RIGHT" or "ANCHOR_BOTTOM")
    GameTooltip:ClearLines()
    local isActive, badgeVal = false, 0
    if type(act.getState) == "function" then
        local a, c = act.getState()
        isActive = (a == true)
        badgeVal = c
    end
    if isActive then
        if act.id == "dnd" then
            local sCfg = GetSettingsTable()
            local statusStr = L["ON"]
            if sCfg and type(sCfg.dndUntil) == "number" and sCfg.dndUntil > time() then
                statusStr = tostring(math.max(1, math.ceil((sCfg.dndUntil - time()) / 60))) .. "m"
            elseif sCfg and sCfg.dndUntilLeaveInstance == true then
                statusStr = L["Until leaving instance"]
            elseif sCfg and sCfg.dndUntilLeaveGroup == true then
                statusStr = L["Until leaving group"]
            end
            GameTooltip:AddDoubleLine(L[act.nameKey] or act.nameKey, "|cffff9b3d" .. statusStr .. "|r", 1, 0.90, 0.35, 1, 1, 1)
        else
            GameTooltip:AddDoubleLine(L[act.nameKey] or act.nameKey, "|cff2ecc71" .. L["ON"] .. "|r", 1, 0.90, 0.35, 1, 1, 1)
        end
    elseif type(badgeVal) == "string" and badgeVal ~= "" then
        GameTooltip:AddDoubleLine(L[act.nameKey] or act.nameKey, "|cffffd24d" .. badgeVal .. "|r", 1, 0.90, 0.35, 1, 1, 1)
    elseif type(badgeVal) == "number" and badgeVal > 0 then
        GameTooltip:AddDoubleLine(L[act.nameKey] or act.nameKey, "|cffffd24d" .. tostring(badgeVal) .. "|r", 1, 0.90, 0.35, 1, 1, 1)
    else
        GameTooltip:AddLine(L[act.nameKey] or act.nameKey, 1, 0.90, 0.35)
    end
    GameTooltip:AddLine(L[act.descKey] or act.descKey, 0.88, 0.92, 0.96, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Right-click: button options & bar"], 0.62, 0.74, 0.88, true)
    GameTooltip:Show()
end

local function EnsureActionButton(bar, idx)
    local existing = QuickBar.buttons[idx]
    if existing then
        return existing
    end
    local Theme = ns.Theme
    local btn = CreateFrame("Button", nil, bar, "BackdropTemplate")
    btn:SetSize(BTN_SIZE, BTN_SIZE)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local sBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
    sBg:SetAllPoints(btn)
    sBg:SetTexture(WHITE8X8)
    sBg:SetVertexColor(0.11, 0.12, 0.14, 1.0)
    btn._solidBg = sBg

    local activeWash = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    activeWash:SetPoint("TOPLEFT", 1, -1)
    activeWash:SetPoint("BOTTOMRIGHT", -1, 1)
    activeWash:SetTexture(WHITE8X8)
    activeWash:Hide()
    btn.activeWash = activeWash

    local aura = btn:CreateTexture(nil, "OVERLAY", nil, 2)
    aura:SetPoint("TOPLEFT", btn, "TOPLEFT", -4, 4)
    aura:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 4, -4)
    aura:SetTexture(GLOW_TEX)
    aura:SetBlendMode("ADD")
    aura:Hide()
    btn.aura = aura

    if aura.CreateAnimationGroup then
        local okAg, ag = pcall(aura.CreateAnimationGroup, aura)
        if okAg and ag then
            ag:SetLooping("BOUNCE")
            local anim = ag:CreateAnimation("Alpha")
            if anim then
                anim:SetFromAlpha(0.32)
                anim:SetToAlpha(0.88)
                anim:SetDuration(1.05)
                anim:SetSmoothing("IN_OUT")
            end
            btn._auraPulseAg = ag
        end
    end

    local ico = btn:CreateTexture(nil, "ARTWORK", nil, 3)
    ico:SetSize(22, 22)
    ico:SetPoint("CENTER", btn, "CENTER", 0, 0)
    ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.ico = ico

    local offVeil = btn:CreateTexture(nil, "ARTWORK", nil, 5)
    offVeil:SetPoint("TOPLEFT", 1, -1)
    offVeil:SetPoint("BOTTOMRIGHT", -1, 1)
    offVeil:SetColorTexture(0.03, 0.03, 0.04, 0.36)
    offVeil:Hide()
    btn.offVeil = offVeil

    local ringTop = btn:CreateTexture(nil, "OVERLAY", nil, 3)
    ringTop:SetHeight(2)
    ringTop:SetPoint("TOPLEFT", 1, -1)
    ringTop:SetPoint("TOPRIGHT", -1, -1)
    ringTop:SetTexture(WHITE8X8)
    ringTop:Hide()
    local ringBot = btn:CreateTexture(nil, "OVERLAY", nil, 3)
    ringBot:SetHeight(2)
    ringBot:SetPoint("BOTTOMLEFT", 1, 1)
    ringBot:SetPoint("BOTTOMRIGHT", -1, 1)
    ringBot:SetTexture(WHITE8X8)
    ringBot:Hide()
    local ringLeft = btn:CreateTexture(nil, "OVERLAY", nil, 3)
    ringLeft:SetWidth(2)
    ringLeft:SetPoint("TOPLEFT", 1, -1)
    ringLeft:SetPoint("BOTTOMLEFT", 1, 1)
    ringLeft:SetTexture(WHITE8X8)
    ringLeft:Hide()
    local ringRight = btn:CreateTexture(nil, "OVERLAY", nil, 3)
    ringRight:SetWidth(2)
    ringRight:SetPoint("TOPRIGHT", -1, -1)
    ringRight:SetPoint("BOTTOMRIGHT", -1, 1)
    ringRight:SetTexture(WHITE8X8)
    ringRight:Hide()
    btn._activeRings = { ringTop, ringBot, ringLeft, ringRight }

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn)
    hl:SetColorTexture(1.0, 0.90, 0.45, 0.16)

    local countFs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countFs:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    countFs:SetJustifyH("RIGHT")
    if countFs.SetFont then
        local fontPath = select(1, countFs:GetFont())
        if fontPath then
            pcall(countFs.SetFont, countFs, fontPath, 11, "OUTLINE")
        end
    end
    countFs:Hide()
    btn.countFs = countFs

    local activeDot = btn:CreateTexture(nil, "OVERLAY", nil, 5)
    activeDot:SetSize(9, 9)
    activeDot:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
    activeDot:SetTexture(DOT_TEX)
    activeDot:Hide()
    btn.activeDot = activeDot

    if Theme and Theme.AttachDragHandle then
        Theme:AttachDragHandle(btn, bar)
    end

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
        if bar._scJustDraggedAt and GetTime and (GetTime() - bar._scJustDraggedAt) < 0.25 then
            return
        end
        if mouseBtn == "RightButton" then
            QuickBar:OpenContextMenu(selfBtn, selfBtn._action)
            return
        end
        local act = selfBtn._action
        if act and type(act.onClick) == "function" then
            act.onClick()
            local function RefreshBarAndTip()
                QuickBar:Refresh()
                if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(selfBtn) then
                    RenderQuickBarButtonTooltip(selfBtn)
                end
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0.05, RefreshBarAndTip)
            else
                RefreshBarAndTip()
            end
        end
    end)

    btn:SetScript("OnEnter", function(selfBtn)
        if selfBtn.SetBackdropBorderColor then
            local ac = selfBtn._scHoverCol or COL_CONV
            selfBtn:SetBackdropBorderColor(ac[1], ac[2], ac[3], 1.0)
        end
        RenderQuickBarButtonTooltip(selfBtn)
    end)
    btn:SetScript("OnLeave", function(selfBtn)
        if selfBtn and selfBtn.ico then
            selfBtn.ico:SetPoint("CENTER", selfBtn, "CENTER", 0, 0)
        end
        if selfBtn and selfBtn.SetBackdropBorderColor and selfBtn._scRestBorder then
            local bc = selfBtn._scRestBorder
            selfBtn:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1.0)
        end
        if GameTooltip then GameTooltip:Hide() end
    end)

    QuickBar.buttons[idx] = btn
    return btn
end

function QuickBar:EnsureBarFrame()
    if self.frame then
        return self.frame
    end
    local Theme = ns.Theme
    if not Theme then return nil end

    local win = CreateFrame("Frame", "SocialCentralQuickBarFrame", UIParent, "BackdropTemplate")
    win:Hide()
    win:SetSize(260, 40)
    ApplyDefaultBarPlacement(win)
    win:SetFrameStrata("MEDIUM")
    win:SetFrameLevel(48)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)

    local sBg = win:CreateTexture(nil, "BACKGROUND", nil, -8)
    sBg:SetAllPoints(win)
    sBg:SetTexture(WHITE8X8)
    sBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    win._solidOpaqueBg = sBg

    local topSheen = win:CreateTexture(nil, "BORDER", nil, 1)
    topSheen:SetHeight(1)
    topSheen:SetPoint("TOPLEFT", win, "TOPLEFT", 2, -1)
    topSheen:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -1)
    topSheen:SetTexture(WHITE8X8)
    topSheen:SetVertexColor(COL_SHEEN_BLIZZ[1], COL_SHEEN_BLIZZ[2], COL_SHEEN_BLIZZ[3], COL_SHEEN_BLIZZ[4])
    win._topSheen = topSheen

    local gripBtn = CreateFrame("Button", nil, win)
    gripBtn:SetSize(GRIP_THICK, BTN_SIZE)
    gripBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local dots = {}
    for i = 1, 6 do
        local d = gripBtn:CreateTexture(nil, "ARTWORK")
        d:SetSize(3, 3)
        d:SetTexture(WHITE8X8)
        d:SetVertexColor(0.62, 0.68, 0.76, 0.85)
        dots[i] = d
    end
    gripBtn._dots = dots

    gripBtn:SetScript("OnClick", function(selfBtn, mouseBtn)
        if win._scJustDraggedAt and GetTime and (GetTime() - win._scJustDraggedAt) < 0.25 then
            return
        end
        if mouseBtn == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then
            QuickBar:ToggleOrientation()
            return
        end
        QuickBar:OpenContextMenu(selfBtn)
    end)
    gripBtn:SetScript("OnEnter", function(selfBtn)
        for _, d in ipairs(selfBtn._dots or {}) do
            d:SetVertexColor(1.0, 0.85, 0.38, 1.0)
        end
        if not GameTooltip then return end
        local orient = QuickBar:GetOrientation()
        GameTooltip:SetOwner(selfBtn, orient == "vertical" and "ANCHOR_RIGHT" or "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cffffd24dSocialCentral|r — " .. L["Quick Access Bar"], 1, 1, 1)
        GameTooltip:AddLine(L["Drag: move anywhere\nClick: customize buttons / rotate Horizontal <-> Vertical\nShift+Click: rotate immediately"], 0.85, 0.90, 0.96, true)
        GameTooltip:Show()
    end)
    gripBtn:SetScript("OnLeave", function(selfBtn)
        for _, d in ipairs(selfBtn._dots or {}) do
            d:SetVertexColor(0.62, 0.68, 0.76, 0.85)
        end
        if GameTooltip then GameTooltip:Hide() end
    end)
    win.gripBtn = gripBtn

    local s = GetSettingsTable()
    win._scLocked = (s and s.quickBarLocked == true) and true or false
    Theme:MakeMovable(win, {
        key = "quick_bar",
        handles = { win, gripBtn },
        combatLock = false,
        onReset = ApplyDefaultBarPlacement,
    })

    self.frame = win
    return win
end

function QuickBar:Refresh()
    local s = GetSettingsTable()
    local enabled = (not s) or (s.quickBarEnabled ~= false)
    if not enabled then
        if self.frame and self.frame:IsShown() then
            self.frame:Hide()
        end
        return
    end

    local win = self:EnsureBarFrame()
    local Theme = ns.Theme
    if not (win and Theme) then return end

    local p = Theme.GetPalette and Theme:GetPalette()
    local palKey = (p and p.key) or "default"
    if win._lastPalKey ~= palKey then
        Theme:ApplyBackdrop(win, "window", p)
        ApplySolidOpaqueBg(win, p)
        if win._topSheen then
            local sh = (palKey == "dark" and COL_SHEEN_DARK)
                or (palKey == "native" and COL_SHEEN_NATIVE)
                or COL_SHEEN_BLIZZ
            win._topSheen:SetVertexColor(sh[1], sh[2], sh[3], sh[4])
        end
        win._lastPalKey = palKey
    end

    win._scLocked = (s and s.quickBarLocked == true) and true or false
    local ids = GetSelectedIdsCached()
    local count = #ids
    local isVert = (self:GetOrientation() == "vertical")
    local hasSavedPos = Theme.HasSavedWindowPosition and Theme:HasSavedWindowPosition("quick_bar")
    local posSig = (hasSavedPos and "saved" or "default") .. ":" .. (isVert and "V" or "H")
    if win._lastRestoredPosSig ~= posSig then
        win._lastRestoredPosSig = posSig
        if hasSavedPos then
            Theme:RestoreWindowPosition(win, "quick_bar", false, { allowLockedRestore = true })
        else
            ApplyDefaultBarPlacement(win)
        end
    end

    local spanButtons = (count * BTN_SIZE) + (math.max(0, count - 1) * BTN_GAP)
    local layoutSig = (isVert and "V:" or "H:") .. table.concat(ids, ",")
    local layoutChanged = (win._lastLayoutSig ~= layoutSig)
    if layoutChanged then
        win._lastLayoutSig = layoutSig
        if isVert then
            local totalW = PAD + BTN_SIZE + PAD
            local totalH = PAD + GRIP_THICK + 4 + spanButtons + PAD
            win:SetSize(totalW, totalH)
            win.gripBtn:ClearAllPoints()
            win.gripBtn:SetSize(BTN_SIZE, GRIP_THICK)
            win.gripBtn:SetPoint("TOP", win, "TOP", 0, -PAD)
            for i, d in ipairs(win.gripBtn._dots) do
                local col = (i - 1) % 3
                local row = math.floor((i - 1) / 3)
                d:ClearAllPoints()
                d:SetPoint("CENTER", win.gripBtn, "CENTER", (col - 1) * 5, (row == 0) and 3 or -3)
            end
        else
            local totalW = PAD + GRIP_THICK + 4 + spanButtons + PAD
            local totalH = PAD + BTN_SIZE + PAD
            win:SetSize(totalW, totalH)
            win.gripBtn:ClearAllPoints()
            win.gripBtn:SetSize(GRIP_THICK, BTN_SIZE)
            win.gripBtn:SetPoint("LEFT", win, "LEFT", PAD, 0)
            for i, d in ipairs(win.gripBtn._dots) do
                local col = math.floor((i - 1) / 3)
                local row = (i - 1) % 3
                d:ClearAllPoints()
                d:SetPoint("CENTER", win.gripBtn, "CENTER", (col == 0) and -3 or 3, (1 - row) * 5)
            end
        end
    end

    for idx, actId in ipairs(ids) do
        local act = ACTION_BY_ID[actId]
        local btn = EnsureActionButton(win, idx)
        local actionChanged = (btn._action ~= act)
        btn._action = act
        if btn._lastPalKey ~= palKey then
            Theme:ApplyBackdrop(btn, "surface", p)
            if btn._solidBg then
                local sBgCol = (p and p.surfaceBg) or { 0.12, 0.13, 0.16, 1.0 }
                btn._solidBg:SetVertexColor(sBgCol[1], sBgCol[2], sBgCol[3], 1.0)
            end
            btn._lastPalKey = palKey
        end
        if actionChanged then
            btn.ico:SetTexture(act.icon)
            local tc = Theme and Theme.ResolveIconTexCoord and Theme:ResolveIconTexCoord(act.icon)
            if tc then
                btn.ico:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            else
                btn.ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        end

        if layoutChanged or actionChanged then
            btn:ClearAllPoints()
            local offset = PAD + GRIP_THICK + 4 + ((idx - 1) * (BTN_SIZE + BTN_GAP))
            if isVert then
                btn:SetPoint("TOP", win, "TOP", 0, -offset)
            else
                btn:SetPoint("LEFT", win, "LEFT", offset, 0)
            end
        end

        local isActive, badgeCnt, col = false, 0, nil
        if type(act.getState) == "function" then
            local a, c, clr = act.getState()
            isActive = (a == true)
            badgeCnt = c
            col = clr
        end
        local isToggleBtn = (act.isToggle == true)
        local r, g, b = (col and col[1]) or 0.35, (col and col[2]) or 0.85, (col and col[3]) or 0.55
        btn._scHoverCol = col or COL_CONV
        local visSig = palKey .. ":" .. actId .. ":" .. (isActive and "1" or "0") .. ":" .. (isToggleBtn and "T" or "A") .. ":" .. tostring(badgeCnt or 0)
        if btn._scVisSig ~= visSig then
            btn._scVisSig = visSig
            if isActive then
                if btn.ico.SetDesaturated then btn.ico:SetDesaturated(false) end
                btn.ico:SetAlpha(1.0)
                if btn.offVeil then btn.offVeil:Hide() end
                if btn.activeWash then
                    btn.activeWash:SetVertexColor(r, g, b, 0.24)
                    btn.activeWash:Show()
                end
                for _, edge in ipairs(btn._activeRings or {}) do
                    edge:SetVertexColor(r, g, b, 0.98)
                    edge:Show()
                end
                btn.aura:SetVertexColor(r, g, b, 0.68)
                btn.aura:Show()
                if btn._auraPulseAg and not btn._auraPulseAg:IsPlaying() then
                    btn._auraPulseAg:Play()
                end
                btn.activeDot:SetVertexColor(r, g, b, 1.0)
                btn.activeDot:Show()
                btn._scRestBorder = col or COL_CONV
                if btn.SetBackdropBorderColor then
                    btn:SetBackdropBorderColor(r, g, b, 1.0)
                end
            else
                if btn._auraPulseAg and btn._auraPulseAg:IsPlaying() then
                    btn._auraPulseAg:Stop()
                end
                btn.aura:Hide()
                if btn.activeWash then btn.activeWash:Hide() end
                for _, edge in ipairs(btn._activeRings or {}) do
                    edge:Hide()
                end
                if isToggleBtn then
                    if btn.ico.SetDesaturated then btn.ico:SetDesaturated(true) end
                    btn.ico:SetAlpha(0.42)
                    if btn.offVeil then btn.offVeil:Show() end
                    btn.activeDot:SetVertexColor(0.40, 0.43, 0.48, 0.78)
                    btn.activeDot:Show()
                else
                    if btn.ico.SetDesaturated then btn.ico:SetDesaturated(false) end
                    btn.ico:SetAlpha(1.0)
                    if btn.offVeil then btn.offVeil:Hide() end
                    btn.activeDot:Hide()
                end
                local bc = (p and p.border) or COL_BORDER_FALLBACK
                btn._scRestBorder = bc
                if btn.SetBackdropBorderColor then
                    btn:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1.0)
                end
            end
            if type(badgeCnt) == "string" and badgeCnt ~= "" then
                btn.countFs:SetText(badgeCnt)
                btn.countFs:SetTextColor(1.0, 0.78, 0.30)
                btn.countFs:Show()
            elseif type(badgeCnt) == "number" and badgeCnt > 0 then
                btn.countFs:SetText(badgeCnt > 99 and "99+" or tostring(badgeCnt))
                btn.countFs:SetTextColor(1.0, 0.90, 0.32)
                btn.countFs:Show()
            else
                btn.countFs:Hide()
            end
        end
        if not btn:IsShown() then
            btn:Show()
        end
    end

    for idx = count + 1, #self.buttons do
        if self.buttons[idx] then
            self.buttons[idx]:Hide()
        end
    end

    local hasTimedDnd = (s and s.doNotDisturb == true and type(s.dndUntil) == "number" and s.dndUntil > time())
    if hasTimedDnd then
        if not self._dndBadgeTicker and C_Timer and C_Timer.NewTicker then
            self._dndBadgeTicker = C_Timer.NewTicker(15.0, function()
                local curS = GetSettingsTable()
                if curS and curS.doNotDisturb == true and type(curS.dndUntil) == "number" and curS.dndUntil > time() then
                    QuickBar:Refresh()
                elseif QuickBar._dndBadgeTicker then
                    QuickBar._dndBadgeTicker:Cancel()
                    QuickBar._dndBadgeTicker = nil
                end
            end)
        end
    elseif self._dndBadgeTicker then
        self._dndBadgeTicker:Cancel()
        self._dndBadgeTicker = nil
    end

    if not win:IsShown() then
        win:Show()
    end
end

function QuickBar:EnsureCustomizeModal()
    if self.customModal then
        return self.customModal
    end
    local Theme = ns.Theme
    if not Theme then return nil end

    local m = CreateFrame("Frame", "SocialCentralQuickBarCustomizeModal", UIParent, "BackdropTemplate")
    m:Hide()
    m:SetSize(532, 594)
    m:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
    m:SetClampedToScreen(true)
    table.insert(UISpecialFrames, "SocialCentralQuickBarCustomizeModal")
    Theme:PrepareTopOverlayModal(m, 855)

    local sBg = m:CreateTexture(nil, "BACKGROUND", nil, -8)
    sBg:SetAllPoints(m)
    sBg:SetTexture(WHITE8X8)
    sBg:SetVertexColor(0.08, 0.08, 0.09, 1.0)
    m._solidOpaqueBg = sBg

    local hdr = CreateFrame("Frame", nil, m, "BackdropTemplate")
    hdr:SetPoint("TOPLEFT", 8, -8)
    hdr:SetPoint("TOPRIGHT", -8, -8)
    hdr:SetHeight(28)
    m.hdr = hdr

    local hIco = hdr:CreateTexture(nil, "ARTWORK")
    hIco:SetSize(16, 16)
    hIco:SetPoint("LEFT", hdr, "LEFT", 8, 0)
    hIco:SetTexture(ICON_TEX)

    local closeBtn = Theme:CreateButton(hdr, 22, 20, "X", "default")
    closeBtn:SetPoint("RIGHT", hdr, "RIGHT", -5, 0)
    closeBtn:SetScript("OnClick", function() m:Hide() end)
    m.closeBtn = closeBtn

    local helpBtn = Theme:CreateHelpButton(
        hdr,
        L["Help: Quick Access Bar"],
        L["Lets you pick 5 to 10 1-click buttons and arrange the Quick Access Bar horizontally or vertically anywhere on screen."],
        L["Check or uncheck buttons below (5 minimum, 10 maximum), use the Up/Down arrows to reorder, and switch Horizontal/Vertical anytime."],
        16,
        { target = m }
    )
    helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    m.helpBtn = helpBtn

    local titleFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("LEFT", hIco, "RIGHT", 6, 0)
    titleFs:SetPoint("RIGHT", helpBtn, "LEFT", -6, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetWordWrap(false)
    titleFs:SetText(L["Customize Quick Access Bar (5-10 Buttons)"])
    m.titleFs = titleFs

    Theme:MakeMovable(m, { key = "quick_bar_customizer", skipAutoRestore = true, handles = { hdr, m } })

    local ctrlBar = CreateFrame("Frame", nil, m, "BackdropTemplate")
    ctrlBar:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -6)
    ctrlBar:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", 0, -6)
    ctrlBar:SetHeight(34)
    m.ctrlBar = ctrlBar

    local horizBtn = Theme:CreateButton(ctrlBar, 102, 22, L["Horizontal"], "default")
    Theme:AutoFitButton(horizBtn, 86, 14, 130)
    horizBtn:SetPoint("LEFT", ctrlBar, "LEFT", 8, 0)
    horizBtn:SetScript("OnClick", function() QuickBar:SetOrientation("horizontal") end)
    m.horizBtn = horizBtn

    local vertBtn = Theme:CreateButton(ctrlBar, 94, 22, L["Vertical"], "default")
    Theme:AutoFitButton(vertBtn, 78, 14, 120)
    vertBtn:SetPoint("LEFT", horizBtn, "RIGHT", 6, 0)
    vertBtn:SetScript("OnClick", function() QuickBar:SetOrientation("vertical") end)
    m.vertBtn = vertBtn

    local lockCb = CreateFrame("CheckButton", nil, ctrlBar, "UICheckButtonTemplate")
    lockCb:SetSize(22, 22)
    lockCb:SetPoint("LEFT", vertBtn, "RIGHT", 12, 0)
    local lockLbl = ctrlBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lockLbl:SetPoint("LEFT", lockCb, "RIGHT", 3, 0)
    lockLbl:SetText(L["Lock bar position"])
    lockCb:SetScript("OnClick", function(selfCb)
        local nxt = selfCb:GetChecked() == true
        local s = ns.db and ns.db.settings
        if s then s.quickBarLocked = nxt end
        if SocialCentralDB and SocialCentralDB.settings then
            SocialCentralDB.settings.quickBarLocked = nxt
        end
        QuickBar:Refresh()
        ns:Emit("SETTINGS_UPDATED")
    end)
    m.lockCb = lockCb

    local presetRow = CreateFrame("Frame", nil, m)
    presetRow:SetPoint("TOPLEFT", ctrlBar, "BOTTOMLEFT", 0, -6)
    presetRow:SetPoint("TOPRIGHT", ctrlBar, "BOTTOMRIGHT", 0, -6)
    presetRow:SetHeight(24)
    m.presetBtns = {}
    local prevPreBtn = nil
    for _, pre in ipairs(QUICK_PRESETS) do
        local pid = pre.id
        local pBtn = Theme:CreateButton(presetRow, 140, 22, L[pre.labelKey] or pre.labelKey, "default")
        Theme:AutoFitButton(pBtn, 118, 12, 166)
        if not prevPreBtn then
            pBtn:SetPoint("LEFT", presetRow, "LEFT", 0, 0)
        else
            pBtn:SetPoint("LEFT", prevPreBtn, "RIGHT", 6, 0)
        end
        pBtn:SetScript("OnClick", function()
            m._limitHint = nil
            QuickBar:ApplyPreset(pid)
        end)
        prevPreBtn = pBtn
        m.presetBtns[#m.presetBtns + 1] = pBtn
    end

    local countFs = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countFs:SetPoint("TOPLEFT", presetRow, "BOTTOMLEFT", 4, -8)
    countFs:SetJustifyH("LEFT")
    m.countFs = countFs

    local limitMsgFs = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    limitMsgFs:SetPoint("LEFT", countFs, "RIGHT", 10, 0)
    limitMsgFs:SetPoint("RIGHT", m, "RIGHT", -12, 0)
    limitMsgFs:SetJustifyH("RIGHT")
    limitMsgFs:SetTextColor(1.0, 0.72, 0.30)
    m.limitMsgFs = limitMsgFs

    local listBox = CreateFrame("Frame", nil, m, "BackdropTemplate")
    listBox:SetPoint("TOPLEFT", countFs, "BOTTOMLEFT", -4, -6)
    listBox:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -8, 42)
    m.listBox = listBox

    local resetBtn = Theme:CreateButton(m, 134, 24, L["Restore Defaults"], "default")
    Theme:AutoFitButton(resetBtn, 112, 16, 175)
    resetBtn:SetPoint("BOTTOMLEFT", m, "BOTTOMLEFT", 10, 10)
    resetBtn:SetScript("OnClick", function()
        m._limitHint = nil
        QuickBar:RestoreDefaultButtons()
        QuickBar:ResetPosition()
    end)
    m.resetBtn = resetBtn

    local doneBtn = Theme:CreateButton(m, 96, 24, L["Close"], "primary")
    Theme:AutoFitButton(doneBtn, 82, 16, 140)
    doneBtn:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -10, 10)
    doneBtn:SetScript("OnClick", function() m:Hide() end)
    m.doneBtn = doneBtn

    m.rows = {}
    local rowH = 26
    for i = 1, #ACTION_CATALOG do
        local r = CreateFrame("Frame", nil, listBox)
        r:SetPoint("TOPLEFT", listBox, "TOPLEFT", 6, -6 - ((i - 1) * (rowH + 1)))
        r:SetPoint("TOPRIGHT", listBox, "TOPRIGHT", -6, -6 - ((i - 1) * (rowH + 1)))
        r:SetHeight(rowH)

        local rBg = r:CreateTexture(nil, "BACKGROUND")
        rBg:SetAllPoints()
        rBg:SetTexture(WHITE8X8)
        rBg:SetVertexColor(1, 1, 1, (i % 2 == 0) and 0.035 or 0.015)

        local cb = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("LEFT", r, "LEFT", 2, 0)
        r.cb = cb

        local ordFs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ordFs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        ordFs:SetWidth(24)
        ordFs:SetJustifyH("CENTER")
        r.ordFs = ordFs

        local ico = r:CreateTexture(nil, "ARTWORK")
        ico:SetSize(18, 18)
        ico:SetPoint("LEFT", ordFs, "RIGHT", 2, 0)
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.ico = ico

        local dnBtn = Theme:CreateButton(r, 22, 20, "v", "default")
        dnBtn:SetPoint("RIGHT", r, "RIGHT", -2, 0)
        r.dnBtn = dnBtn

        local upBtn = Theme:CreateButton(r, 22, 20, "^", "default")
        upBtn:SetPoint("RIGHT", dnBtn, "LEFT", -3, 0)
        r.upBtn = upBtn

        local titleTxt = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        titleTxt:SetPoint("TOPLEFT", ico, "TOPRIGHT", 8, 1)
        titleTxt:SetPoint("RIGHT", upBtn, "LEFT", -8, 0)
        titleTxt:SetJustifyH("LEFT")
        titleTxt:SetWordWrap(false)
        r.titleTxt = titleTxt

        local descTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        descTxt:SetPoint("BOTTOMLEFT", ico, "BOTTOMRIGHT", 8, -1)
        descTxt:SetPoint("RIGHT", upBtn, "LEFT", -8, 0)
        descTxt:SetJustifyH("LEFT")
        descTxt:SetWordWrap(false)
        descTxt:SetTextColor(0.68, 0.74, 0.82)
        r.descTxt = descTxt

        cb:SetScript("OnClick", function()
            local actId = r._actId
            if not actId then return end
            local cur = QuickBar:GetSelectedIds()
            local foundIdx = nil
            for k, v in ipairs(cur) do
                if v == actId then
                    foundIdx = k
                    break
                end
            end
            if foundIdx then
                if #cur <= MIN_BUTTONS then
                    m._limitHint = string.format(L["Minimum %d buttons required."], MIN_BUTTONS)
                    if m.RefreshRows then m.RefreshRows() end
                    return
                end
                table.remove(cur, foundIdx)
            else
                if #cur >= MAX_BUTTONS then
                    m._limitHint = string.format(L["Maximum %d buttons allowed."], MAX_BUTTONS)
                    if m.RefreshRows then m.RefreshRows() end
                    return
                end
                cur[#cur + 1] = actId
            end
            m._limitHint = nil
            SyncSelectedListToSaved(cur)
            QuickBar:Refresh()
            if m.RefreshRows then m.RefreshRows() end
        end)

        upBtn:SetScript("OnClick", function()
            local sIdx = r._selIdx
            if not (sIdx and sIdx > 1) then return end
            local cur = QuickBar:GetSelectedIds()
            cur[sIdx], cur[sIdx - 1] = cur[sIdx - 1], cur[sIdx]
            m._limitHint = nil
            SyncSelectedListToSaved(cur)
            QuickBar:Refresh()
            if m.RefreshRows then m.RefreshRows() end
        end)

        dnBtn:SetScript("OnClick", function()
            local sIdx = r._selIdx
            local cur = QuickBar:GetSelectedIds()
            if not (sIdx and sIdx < #cur) then return end
            cur[sIdx], cur[sIdx + 1] = cur[sIdx + 1], cur[sIdx]
            m._limitHint = nil
            SyncSelectedListToSaved(cur)
            QuickBar:Refresh()
            if m.RefreshRows then m.RefreshRows() end
        end)

        m.rows[i] = r
    end

    local function RebuildModalLayoutAndState()
        local selIds = QuickBar:GetSelectedIds()
        local posMap = {}
        for idx, id in ipairs(selIds) do
            posMap[id] = idx
        end

        local ordered = {}
        for _, id in ipairs(selIds) do
            if ACTION_BY_ID[id] then
                ordered[#ordered + 1] = ACTION_BY_ID[id]
            end
        end
        for _, act in ipairs(ACTION_CATALOG) do
            if not posMap[act.id] then
                ordered[#ordered + 1] = act
            end
        end

        local isVert = (QuickBar:GetOrientation() == "vertical")
        Theme:StyleButton(m.horizBtn, isVert and "default" or "primary")
        Theme:SetButtonActive(m.horizBtn, not isVert, isVert and "default" or "primary")
        Theme:StyleButton(m.vertBtn, isVert and "primary" or "default")
        Theme:SetButtonActive(m.vertBtn, isVert, isVert and "primary" or "default")

        local s = GetSettingsTable()
        m.lockCb:SetChecked(s and s.quickBarLocked == true)
        m.countFs:SetText(string.format(L["Selected: %d / %d (minimum %d)"], #selIds, MAX_BUTTONS, MIN_BUTTONS))
        m.limitMsgFs:SetText(m._limitHint or "")

        for i, act in ipairs(ordered) do
            local r = m.rows[i]
            local selIdx = posMap[act.id]
            local isSel = (selIdx ~= nil)
            r._actId = act.id
            r._selIdx = selIdx
            r.cb:SetChecked(isSel)
            r.ordFs:SetText(isSel and ("|cff2ecc71#" .. tostring(selIdx) .. "|r") or "|cff666d78--|r")
            r.ico:SetTexture(act.icon)
            local tc = Theme and Theme.ResolveIconTexCoord and Theme:ResolveIconTexCoord(act.icon)
            if tc then
                r.ico:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            else
                r.ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            r.titleTxt:SetText(L[act.nameKey] or act.nameKey)
            r.descTxt:SetText(L[act.descKey] or act.descKey)

            r.upBtn:SetShown(isSel)
            r.dnBtn:SetShown(isSel)
            r.upBtn:SetEnabled(isSel and selIdx > 1)
            r.dnBtn:SetEnabled(isSel and selIdx < #selIds)
            Theme:StyleButton(r.upBtn, "default")
            Theme:StyleButton(r.dnBtn, "default")
        end
    end

    m.RefreshRows = RebuildModalLayoutAndState
    self.customModal = m
    return m
end

function QuickBar:OpenCustomizeModal()
    local m = self:EnsureCustomizeModal()
    local Theme = ns.Theme
    if not (m and Theme) then return end
    local p = Theme:GetPalette()
    Theme:PrepareTopOverlayModal(m, 855)
    Theme:ApplyBackdrop(m, "window", p)
    ApplySolidOpaqueBg(m, p)
    Theme:ApplyBackdrop(m.hdr, "header", p)
    Theme:ApplyBackdrop(m.ctrlBar, "surface", p)
    Theme:ApplyBackdrop(m.listBox, "inset", p)
    Theme:StyleButton(m.closeBtn, "default")
    Theme:StyleButton(m.resetBtn, "default")
    Theme:StyleButton(m.doneBtn, "primary")
    for _, pBtn in ipairs(m.presetBtns or {}) do
        Theme:StyleButton(pBtn, "default")
    end
    m._limitHint = nil
    m:RefreshRows()
    m:Show()
    if m.Raise then m:Raise() end
end

function QuickBar:ShowIntroTutorial(force)
    local Theme = ns.Theme
    if not (Theme and Theme.ShowNpcGuide) then
        return false
    end
    if IsInCombatNow() then
        self._pendingIntroTutorial = true
        return false
    end
    if (not force) and Theme.IsNpcGuideShown and Theme:IsNpcGuideShown() then
        self._pendingIntroTutorial = true
        return false
    end
    local acked = false
    local function MarkAcked()
        if acked then return end
        acked = true
        if ns.SetAccountTutorialShown then
            ns:SetAccountTutorialShown("quickBarIntroAck", true)
        end
    end
    local guideSpec = {
        key = "quick_bar_intro",
        title = L["Quick Access Bar"],
        doneLabel = L["Got it!"],
        defaultTarget = function()
            return (QuickBar.frame and QuickBar.frame:IsShown()) and QuickBar.frame or nil
        end,
        onComplete = MarkAcked,
        onClose = MarkAcked,
        steps = {
            {
                title = L["Quick Access Bar"],
                tag = "|cff58a6ff" .. L["5-10 Custom Shortcuts"] .. "|r",
                text = L["1-click shortcuts. Drag to move · Right-click ANY icon for its own options (like DND timer), or rotate & pick 5-10 buttons."],
                actionLabel = L["Customize Buttons (5-10)..."],
                onAction = function()
                    MarkAcked()
                    if Theme.HideNpcGuide then Theme:HideNpcGuide("quick_bar_intro") end
                    QuickBar:OpenCustomizeModal()
                end,
                target = function()
                    return (QuickBar.frame and QuickBar.frame:IsShown()) and QuickBar.frame or nil
                end,
            },
        },
    }
    self._pendingIntroTutorial = nil
    local shown = Theme:ShowNpcGuide(guideSpec)
    if not shown then
        self._pendingIntroTutorial = true
        return false
    end
    return true
end

function QuickBar:MaybeShowIntroTutorial()
    local s = GetSettingsTable()
    if s and s.quickBarEnabled == false then
        return
    end
    if ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("quickBarIntroAck") then
        return
    end
    if not (self.frame and self.frame:IsShown()) then
        self:Refresh()
    end
    if not (self.frame and self.frame:IsShown()) then
        return
    end
    if IsInCombatNow() then
        self._pendingIntroTutorial = true
        return
    end
    local Theme = ns.Theme
    if Theme and Theme.IsNpcGuideShown and Theme:IsNpcGuideShown() then
        self._pendingIntroTutorial = true
        if C_Timer and C_Timer.After and not self._introRetryQueued then
            self._introRetryQueued = true
            C_Timer.After(4.0, function()
                QuickBar._introRetryQueued = nil
                QuickBar:MaybeShowIntroTutorial()
            end)
        end
        return
    end
    self:ShowIntroTutorial(false)
end

function QuickBar:Init()
    if self.initialized then
        return
    end
    self.initialized = true

    if not self._regenFrame then
        local rf = CreateFrame("Frame")
        rf:RegisterEvent("PLAYER_REGEN_ENABLED")
        rf:SetScript("OnEvent", function()
            if QuickBar._pendingIntroTutorial then
                QuickBar._pendingIntroTutorial = nil
                if C_Timer and C_Timer.After then
                    C_Timer.After(1.0, function()
                        QuickBar:MaybeShowIntroTutorial()
                    end)
                else
                    QuickBar:MaybeShowIntroTutorial()
                end
            end
        end)
        self._regenFrame = rf
    end

    local function RunCoalescedRefresh()
        QuickBar._refreshQueued = false
        QuickBar:Refresh()
        if QuickBar.customModal and QuickBar.customModal:IsShown() and QuickBar.customModal.RefreshRows then
            QuickBar.customModal:RefreshRows()
        end
        if QuickBar._pendingIntroTutorial then
            QuickBar:MaybeShowIntroTutorial()
        end
    end

    local function QueueRefresh()
        if C_Timer and C_Timer.After then
            if QuickBar._refreshQueued then
                return
            end
            QuickBar._refreshQueued = true
            C_Timer.After(0, RunCoalescedRefresh)
        else
            RunCoalescedRefresh()
        end
    end

    ns:On("SETTINGS_UPDATED", function()
        QuickBar._cachedIds = nil
        QueueRefresh()
    end)
    ns:On("CHAT_UPDATED", QueueRefresh)
    ns:On("LOOT_ROLL_UPDATED", QueueRefresh)
    ns:On("LOOT_ROLL_WINNER", QueueRefresh)
    ns:On("LOOT_ROLL_RESULTS_READ", QueueRefresh)
    ns:On("SPOTTER_UPDATED", QueueRefresh)
    ns:On("WATCHLIST_UPDATED", QueueRefresh)
    if ns.Theme and ns.Theme.RegisterListener then
        ns.Theme:RegisterListener(QueueRefresh)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.6, QueueRefresh)
        C_Timer.After(3.2, function()
            QuickBar:MaybeShowIntroTutorial()
        end)
    else
        QueueRefresh()
    end
end
