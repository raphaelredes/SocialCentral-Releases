local _, ns = ...

local L = ns.L
local Compat = ns.Compat
local Store = ns.Store
local Safe = ns.Safe

-- Fully isolated in-memory screenshot / showcase data generator (/sc demo | /sc demo clear).
-- Temporarily swaps live/saved tables with pure showcase tables so real guild names,
-- friends, alts, or chats never leak into CurseForge screenshots, then restores
-- original references cleanly on /sc demo clear or PLAYER_LOGOUT.
local DemoShowcase = {
    _active = false,
    _backup = {},
}

ns.DemoShowcase = DemoShowcase
table.insert(ns.modules, DemoShowcase)

local function GetCurrentScopeKeys()
    local myName = "Player Demo"
    local myClass = "WARRIOR"
    local resolvedSelf = Compat and Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    if resolvedSelf and resolvedSelf.fullName and resolvedSelf.fullName ~= "" then
        myName = resolvedSelf.fullName
    else
        local rawMe = Safe and Safe.String(Safe.Call(UnitName, "player"))
        if rawMe and rawMe ~= "" then
            myName = rawMe
        end
    end
    local _, cls
    if Safe and Safe.Call and UnitClass then
        _, cls = Safe.Call(UnitClass, "player")
        cls = Safe.String(cls)
    elseif UnitClass then
        _, cls = UnitClass("player")
    end
    if type(cls) == "string" and cls ~= "" then
        myClass = cls
    end
    local myParsed = Compat and Compat.ParseCharacterName and Compat.ParseCharacterName(myName)
    local myLookup = (myParsed and myParsed.lookupKey) or myName:lower()
    local myFaction = (Compat and Compat.PlayerFaction and Compat.PlayerFaction()) or "Alliance"
    local myRealm = (Compat and Compat.Realm and Compat.Realm()) or "Forever"
    local myWorldType, myPool
    if Compat and Compat.GetAltWorldInfo then
        myWorldType, myPool = Compat.GetAltWorldInfo(nil)
    end
    myPool = myPool or (Compat and Compat.RealmPool and Compat.RealmPool(myRealm)) or "pvp"
    myWorldType = myWorldType or ((myPool == "pve") and "PvE" or "PvP")
    local myAltKey = (Store and Store.GetCurrentAltKey and Store:GetCurrentAltKey())
        or (Compat and Compat.CharacterKey and Compat.CharacterKey())
        or ("demo:" .. myLookup)
    return myName, myLookup, myClass, myFaction, myRealm, myPool, myWorldType, myAltKey
end

local function BuildDemoRosterSeed()
    return {
        { first = "Kaelen", surname = "Martelo", class = "WARRIOR", level = 60, role = "TANK", tag = "LFM", zone = "Montanha Rocha Negra", guild = "Guarda Eterna", rankIdx = 1, rankName = "Oficial", online = true, bnet = "Kaelen#1402", note = "Tank MT · Core BWL/MC", sc = true, flag = "GOOD", folder = "Raide Core", fav = true, prof1 = "BLACKSMITHING", prof2 = "MINING", prof1Rank = "300/300", prof2Rank = "300/300", craftNote = "Lionheart Helm / Armeiro" },
        { first = "Lyra", surname = "Ventoleste", class = "PRIEST", level = 60, role = "HEALER", tag = "LFG", zone = "Vento Bravo", guild = "Guarda Eterna", rankIdx = 2, rankName = "Veterano", online = true, bnet = "Lyra#2891", note = "Holy · Core BWL/MC", sc = true, flag = "GOOD", folder = "Raide Core", fav = true, prof1 = "ENCHANTING", prof2 = "TAILORING", prof1Rank = "300/300", prof2Rank = "300/300", craftNote = "Crusader / +4 Stats Peito" },
        { first = "Thorn", surname = "Corvo", class = "HUNTER", level = 60, role = "DAMAGER", tag = "PVP", zone = "Vale Alterac", guild = "Vanguarda do Alba", rankIdx = 3, rankName = "Raider", online = true, bnet = "Thorn#7740", note = "Marksman · Kiter BWL", sc = true, flag = "GOOD", folder = "Masmorras", fav = false },
        { first = "Valen", surname = "Escudoluz", class = "PALADIN", level = 60, role = "HEALER", tag = "NONE", zone = "Terras Pestilentas", guild = "Guarda Eterna", rankIdx = 2, rankName = "Veterano", online = true, bnet = nil, note = "Buffs de Bênção e Proteção", sc = true, flag = "GOOD", folder = "Raide Core", fav = false, prof1 = "ALCHEMY", prof2 = "HERBALISM", prof1Rank = "300/300", prof2Rank = "300/300", craftNote = "Frascos Titã & Poder Supremo" },
        { first = "Mira", surname = "Sombraviva", class = "MAGE", level = 58, role = "DAMAGER", tag = "LFG", zone = "Stratholme", guild = "Ordem Arcana", rankIdx = 3, rankName = "Membro", online = true, bnet = "Mira#5108", note = "Água / Portal · Frost AoE", sc = true, folder = "Masmorras", fav = true },
        { first = "Orin", surname = "Forjapedra", class = "ROGUE", level = 60, role = "DAMAGER", tag = "NONE", zone = "Montanha Rocha Negra", guild = "Lâmina Carmesim", rankIdx = 4, rankName = "Iniciado", online = true, bnet = nil, note = "Stealth Run BRD", sc = false, flag = "AVOID", folder = nil, fav = false },
        { first = "Seraphina", surname = "Sol", class = "WARLOCK", level = 54, role = "DAMAGER", tag = "NONE", zone = "Cratera Un'Goro", guild = "Guarda Eterna", rankIdx = 3, rankName = "Raider", online = false, bnet = "Seraphina#3301", note = "Pedra de Invocação", sc = true, folder = "Raide Core", fav = false, prof1 = "TAILORING", prof2 = "ENCHANTING", prof1Rank = "285/300", prof2Rank = "275/300", craftNote = "Tecido Lunar & Bolsa 16 Slots" },
        { first = "Darius", surname = "Lâmina", class = "DRUID", level = 60, role = "TANK", tag = "LFG", zone = "Gládio Cruel", guild = "Guarda Eterna", rankIdx = 3, rankName = "Raider", online = false, bnet = nil, note = "Urso Off-Tank + MotW", sc = false, folder = "Masmorras", fav = false, prof1 = "LEATHERWORKING", prof2 = "SKINNING", prof1Rank = "300/300", prof2Rank = "300/300", craftNote = "Devilsaur Set & Reforços" },
        { first = "Helena", surname = "Bravofio", class = "SHAMAN", level = 60, role = "HEALER", tag = "RAID", zone = "Rocha Negra", guild = "Guarda Eterna", rankIdx = 2, rankName = "Veterano", online = true, bnet = nil, note = "Totens Windfury & Resto", sc = true, flag = "GOOD", folder = "Raide Core", fav = false, prof1 = "ENGINEERING", prof2 = "MINING", prof1Rank = "300/300", prof2Rank = "300/300", craftNote = "Sapper Charge / Reparador" },
        { first = "Gideon", surname = "Alvor", class = "MAGE", level = 60, role = "DAMAGER", tag = "NONE", zone = "Dire Maul", guild = "Guarda Eterna", rankIdx = 3, rankName = "Raider", online = true, bnet = nil, note = "Portal + Comida", sc = false, folder = "Masmorras", fav = false },
    }
end

local function BackupAndSwapLiveTables(now, myFaction, myPool)
    local b = DemoShowcase._backup
    local scope = (Compat and Compat.ScopeKey and Compat.ScopeKey()) or "default"

    b.scope = scope
    b.prevSocial = Store.social
    b.prevSocialByGuid = Store.socialByGuid
    b.prevSocialByLookup = Store.socialByLookup
    b.prevSocialDir = Store.socialDirectory
    b.prevSocialDirByKey = Store.socialDirectoryByKey
    b.prevSocialDirByLookup = Store.socialDirectoryByLookup
    b.prevSocialDirByBNet = Store.socialDirectoryByBNet
    b.prevGuildInfo = Store.guildInfo
    b.prevGuildRanks = Store.guildRosterRanks
    b.prevNearby = Store.nearby

    Store.social = {}
    Store.socialByGuid = {}
    Store.socialByLookup = {}
    Store.socialDirectory = {}
    Store.socialDirectoryByKey = {}
    Store.socialDirectoryByLookup = {}
    Store.socialDirectoryByBNet = {}
    Store.guildRosterRanks = {}
    Store.nearby = {}
    Store._socialFoldersCache = nil

    if ns.db then
        b.prevHasWatchlistTbl = (type(ns.db.watchlist) == "table")
        if b.prevHasWatchlistTbl then
            b.prevWatchlist = ns.db.watchlist[scope]
            b.swappedWatchlist = true
            ns.db.watchlist[scope] = {}
        end

        b.prevHasSocialMetaTbl = (type(ns.db.socialMeta) == "table")
        if b.prevHasSocialMetaTbl then
            b.prevSocialMeta = ns.db.socialMeta[scope]
            b.swappedSocialMeta = true
            ns.db.socialMeta[scope] = {}
        end

        b.prevHasChatHistTbl = (type(ns.db.chatHistory) == "table")
        if b.prevHasChatHistTbl then
            b.prevChatHistory = ns.db.chatHistory[scope]
            b.swappedChatHistory = true
            ns.db.chatHistory[scope] = {}
        end

        b.prevHasChatRoomsTbl = (type(ns.db.chatRooms) == "table")
        if not b.prevHasChatRoomsTbl then
            ns.db.chatRooms = {}
        end
        b.prevChatRooms = ns.db.chatRooms[scope]
        b.swappedChatRooms = true
        ns.db.chatRooms[scope] = {}

        b.prevIgnores = ns.db.accountIgnores
        b.swappedIgnores = true
        ns.db.accountIgnores = {}

        b.prevAlts = ns.db.alts
        b.swappedAlts = true
        ns.db.alts = {}

        b.prevInstanceRuns = ns.db.instanceRuns
        b.swappedInstanceRuns = true
        ns.db.instanceRuns = {}

        b.prevDungeonHistory = ns.db.dungeonHistory
        b.swappedDungeonHistory = true
        ns.db.dungeonHistory = {}

        b.prevWbDrops = ns.db.worldBuffsDrops
        b.swappedWbDrops = true
        ns.db.worldBuffsDrops = { [myPool] = { DRAG = now - 1800, ZAND = now - 900, WARCHIEF = now - 2400 } }

        b.prevItemCatalog = ns.db.itemCatalog
        b.swappedItemCatalog = true
        ns.db.itemCatalog = {}

        b.prevRecipeCatalog = ns.db.recipeCatalog
        b.swappedRecipeCatalog = true
        ns.db.recipeCatalog = {}
    end

    if Store.InvalidateScopeCaches then
        Store:InvalidateScopeCaches()
    end

    if ns.Spotter then
        b.prevSpotterEntries = ns.Spotter.entries
        b.prevSpotterByGuid = ns.Spotter.entryByGuid
        ns.Spotter.entries = {}
        ns.Spotter.entryByGuid = {}
    end

    if ns.Clan then
        b.prevExternalLFG = ns.Clan.externalLFG
        b.prevGlobalLFG = ns.Clan.globalChatLFG
        b.prevOfficialLFG = ns.Clan.officialLfgCache
        ns.Clan.externalLFG = {}
        ns.Clan.globalChatLFG = {}
        ns.Clan.officialLfgCache = {}
    end

    if ns.Chat then
        b.prevChatThreads = ns.Chat.threads
        b.prevActiveThreadKey = ns.Chat.activeThreadKey
        b.prevVerifiedPeers = ns.Chat.sessionVerifiedPeers
        b.prevBNetPeers = ns.Chat.sessionBNetPeers
        b.prevQuickReplyDrafts = ns.Chat.quickReplyDrafts
        b.prevSavedTextBytes = ns.Chat._savedTextBytes
        b.swappedQuickReplyDrafts = true
        ns.Chat.threads = {}
        ns.Chat.sessionVerifiedPeers = {}
        ns.Chat.sessionBNetPeers = {}
        ns.Chat.quickReplyDrafts = {}
        ns.Chat._savedTextBytes = 0
    end

    if ns.Social then
        b.prevSocialCounts = ns.Social._counts
        b.prevSocialDirStats = ns.Social._dirStats
    end

    if ns.Alts then
        ns.Alts._itemIndexBuilt = false
        ns.Alts.itemIndex = nil
        ns.Alts._altBuckets = nil
        ns.Alts._recipeIndexCache = nil
        ns.Alts._recipeSeq = (ns.Alts._recipeSeq or 0) + 1
    end
end

local function SeedSocialWatchlistNearbySpotter(now, myFaction, myPool)
    local b = DemoShowcase._backup
    local metaBucket = Store.GetSocialMetaTable and Store:GetSocialMetaTable()
    local ignBucket = Store.GetAccountIgnoresTable and Store:GetAccountIgnoresTable()
    local wlBucket = Store.GetWatchlistTable and Store:GetWatchlistTable()

    local seed = BuildDemoRosterSeed()
    local onlineAll, onlineGuild, onlineFriend, onlineBnet = 0, 0, 0, 0
    local friendOn, friendTot, bnetWow, bnetApp, bnetTot, dirTot, offlineTot = 0, 0, 0, 0, 0, 0, 0
    for i, entry in ipairs(seed) do
        local fullName = entry.first .. " " .. entry.surname
        local parsed = Compat and Compat.ParseCharacterName and Compat.ParseCharacterName(fullName)
        local lk = (parsed and parsed.lookupKey) or (entry.first .. " " .. entry.surname):lower()
        local rowKey = "demo:" .. lk
        local fakeGuid = string.format("Player-0000-%08X", 0xD000 + i)

        local isFriend = (i <= 5)
        local isGuild = (entry.guild == "Guarda Eterna")
        local isBnet = (entry.bnet ~= nil)
        local bnetId = isBnet and (99000 + i) or nil
        dirTot = dirTot + 1
        if entry.online then
            onlineAll = onlineAll + 1
            if isGuild then onlineGuild = onlineGuild + 1 end
            if isFriend then
                onlineFriend = onlineFriend + 1
                friendOn = friendOn + 1
            end
            if isBnet then
                onlineBnet = onlineBnet + 1
                bnetWow = bnetWow + 1
            end
        else
            offlineTot = offlineTot + 1
            if isBnet then bnetApp = bnetApp + 1 end
        end
        if isFriend then friendTot = friendTot + 1 end
        if isBnet then bnetTot = bnetTot + 1 end

        local row = {
            key = rowKey,
            guid = fakeGuid,
            lookupKey = lk,
            firstName = entry.first,
            surname = entry.surname,
            displayName = fullName,
            classFile = entry.class,
            level = entry.level,
            area = entry.zone,
            guild = entry.guild,
            rankName = entry.rankName,
            rankIndex = entry.rankIdx,
            online = entry.online,
            friendOnline = isFriend and entry.online or false,
            guildOnline = isGuild and entry.online or false,
            bnetOnline = isBnet and entry.online or false,
            bnetState = isBnet and (entry.online and "wow_forever" or "bnet_app") or nil,
            bnetName = entry.bnet,
            bnetAccountID = bnetId,
            sameFaction = true,
            samePool = true,
            realmPool = myPool,
            faction = myFaction,
            hasCharacterName = true,
            lastSeen = entry.online and now or (now - (i * 1800)),
            note = entry.note,
            friendNote = entry.note,
            sources = {
                friend = isFriend,
                bnet = isBnet,
                guild = isGuild,
            },
            _isDemo = true,
        }

        if entry.online then
            Store.social[rowKey] = row
            Store.socialByLookup[lk] = row
            Store.socialByGuid[fakeGuid] = row
        end
        Store.socialDirectory[rowKey] = row
        Store.socialDirectoryByKey[rowKey] = row
        Store.socialDirectoryByLookup[lk] = row
        if bnetId then
            Store.socialDirectoryByBNet[bnetId] = row
        end

        if entry.sc and ns.Chat and ns.Chat.sessionVerifiedPeers then
            ns.Chat.sessionVerifiedPeers[lk] = {
                verifiedAt = now,
                version = ns.version or "0.0.0",
                displayName = fullName,
                _isDemo = true,
            }
        end

        if metaBucket and (entry.flag or entry.folder or entry.note or entry.fav) then
            metaBucket[lk] = {
                flag = entry.flag,
                folder = entry.folder,
                note = entry.note,
                favorite = entry.fav == true,
                updatedAt = now,
                _isDemo = true,
            }
        end

        if wlBucket and i <= 5 then
            wlBucket[lk] = {
                id = lk,
                firstName = entry.first,
                surname = entry.surname,
                displayName = fullName,
                status = (i <= 4) and "online" or "offline",
                level = entry.level,
                classFile = entry.class,
                area = entry.zone,
                guild = entry.guild,
                group = (i <= 2) and "Raide Core" or nil,
                favorite = entry.fav == true,
                watchAllAlts = isBnet,
                lastSeen = (i <= 4) and now or (now - 3600),
                lastChecked = now,
                note = entry.note,
                _isDemo = true,
            }
        end

        if i <= 5 and entry.online then
            Store.nearby[lk] = {
                key = lk,
                lookupKey = lk,
                displayName = fullName,
                classFile = entry.class,
                level = entry.level,
                area = entry.zone,
                guild = entry.guild,
                source = "nameplate",
                lastSeen = now + 1800,
                _isDemo = true,
            }
        end
    end

    Store._socialFoldersCache = nil
    if ns.Social then
        ns.Social._counts = { all = onlineAll, guild = onlineGuild, friend = onlineFriend, bnet = onlineBnet }
        ns.Social._dirStats = {
            onlineTotal = onlineAll,
            onlineGuild = onlineGuild,
            onlineFriend = onlineFriend,
            onlineBnet = onlineBnet,
            friendOnline = friendOn,
            friendTotal = friendTot,
            bnetOnlineWoW = bnetWow,
            bnetOnlineApp = bnetApp,
            bnetTotal = bnetTot,
            dirTotal = dirTot,
            offlineTotal = offlineTot,
            pendingBNetInvites = 0,
        }
        ns.Social._dirRevision = (ns.Social._dirRevision or 0) + 1
    end

    if ignBucket then
        ignBucket["malakor sombrio"] = {
            name = "Malakor Sombrio",
            lookupKey = "malakor sombrio",
            reason = "TOXIC",
            note = "Quitou após o 1º wipe",
            addedAt = now - 86400,
            hideChat = true,
            _isDemo = true,
        }
    end

    if ns.Spotter and ns.Spotter.entries then
        local stances = {
            { key = "demo_kaelen", name = "Kaelen Martelo", guild = "Guarda Eterna", class = "WARRIOR", lvl = 60, stance = "SAME", reason = L["Same Clan"], dist = 14 },
            { key = "demo_thorn", name = "Thorn Corvo", guild = "Vanguarda do Alba", class = "HUNTER", lvl = 60, stance = "ALLY", reason = L["Allied Guild"], dist = 28 },
            { key = "demo_orin", name = "Orin Forjapedra", guild = "Lâmina Carmesim", class = "ROGUE", lvl = 60, stance = "ENEMY", reason = L["Enemy Guild"], dist = 42 },
            { key = "demo_lyra", name = "Lyra Ventoleste", guild = "Guarda Eterna", class = "PRIEST", lvl = 60, stance = "WATCHLIST", reason = L["Watchlist"], dist = 65 },
        }
        for _, sp in ipairs(stances) do
            ns.Spotter.entries[sp.key] = {
                key = sp.key,
                lookupKey = sp.key,
                displayName = sp.name,
                firstName = sp.name:match("^(%S+)"),
                targetName = sp.name,
                guild = sp.guild,
                stance = sp.stance,
                reason = sp.reason,
                classFile = sp.class,
                level = sp.lvl,
                lastSeen = now + 1800,
                lastDistYards = sp.dist,
                lastDistText = tostring(sp.dist) .. " yd",
                onScreen = true,
                _manualTracked = true,
                _isDemo = true,
            }
        end
        if ns.Spotter.MarkDemoDirty then
            ns.Spotter:MarkDemoDirty()
        end
        if ns.SpotterHUD then
            b.spotterWasShown = (ns.SpotterHUD.frame and ns.SpotterHUD.frame:IsShown()) == true
            ns.SpotterHUD.focusedKey = "demo_kaelen"
            if ns.SpotterHUD.Show then
                ns.SpotterHUD:Show(true)
            end
        end
    end
end

local function SeedClanAndLfg(now, myName, myLookup, myClass)
    local b = DemoShowcase._backup

    -- Always replace Store.guildInfo with a pure showcase guild while /sc demo is active
    Store.guildInfo = {
        inGuild = true,
        name = "Guarda Eterna",
        motd = "Raide Core BWL/MC Quinta 20:00 · Use /sc para eventos, grupos e saques!",
        onlineCount = 5,
        totalCount = 7,
        myRankIndex = 0,
        myRankName = "Líder da Guilda",
        isGuildLeader = true,
        _isDemo = true,
    }
    if Store.InvalidateScopeCaches then
        Store:InvalidateScopeCaches()
    end

    local cleanGuild = (Compat and Compat.Plain and Compat.Plain("Guarda Eterna")) or "Guarda Eterna"
    local clanScopeKey = ((Compat and Compat.ScopeKey and Compat.ScopeKey()) or "default") .. "::" .. cleanGuild
    b.demoClanScopeKey = clanScopeKey
    b.prevHasClanTbl = (ns.db and type(ns.db.clan) == "table") == true
    if ns.db then
        if not b.prevHasClanTbl then
            ns.db.clan = {}
        end
        b.prevDemoClanBucket = ns.db.clan[clanScopeKey]
        b.swappedDemoClanBucket = true
        ns.db.clan[clanScopeKey] = {
            myTag = "LFM",
            myNote = "BWL/MC Quinta 20:00",
            peers = {},
            events = {},
            lfg = {},
            myProf1 = "ALCHEMY",
            myProf2 = "HERBALISM",
            myProf1Rank = "300/300",
            myProf2Rank = "300/300",
            myCraftNote = "Frascos Titã & Poder Supremo",
            diplomacy = { rev = 1, updatedAt = now, updatedBy = myName, guilds = {} },
            alliance = {
                enabled = true,
                name = "Aliança Alba Eterna",
                token = "DEMO-ALLY",
                accessMode = "ALL",
                whitelist = {},
                managers = {},
                alliedGuilds = {
                    ["vanguarda do alba"] = { name = "Vanguarda do Alba", token = "DEMO", leader = "Thorn Corvo" },
                    ["ordem arcana"] = { name = "Ordem Arcana", token = "DEMO", leader = "Mira Sombraviva" },
                },
            },
            rosterHistory = {
                { kind = "PROMOTED", name = "Kaelen Martelo", detail = "Veterano -> Oficial", ts = now - 3600, classFile = "WARRIOR", level = 60, zone = "Montanha Rocha Negra" },
                { kind = "JOINED", name = "Gideon Alvor", detail = "Raider", ts = now - 10800, classFile = "MAGE", level = 60, zone = "Dire Maul" },
                { kind = "JOINED", name = "Helena Bravofio", detail = "Veterano", ts = now - 28800, classFile = "SHAMAN", level = 60, zone = "Rocha Negra" },
            },
        }
    end

    local bucket = Store.GetClanScopeData and Store:GetClanScopeData()
    local seed = BuildDemoRosterSeed()
    for idx, entry in ipairs(seed) do
        if entry.guild == "Guarda Eterna" then
            local fullName = entry.first .. " " .. entry.surname
            local parsed = Compat and Compat.ParseCharacterName and Compat.ParseCharacterName(fullName)
            local lk = (parsed and parsed.lookupKey) or fullName:lower()
            Store.guildRosterRanks[lk] = {
                rankIndex = entry.rankIdx,
                rankName = entry.rankName,
                displayName = fullName,
                online = entry.online,
                level = entry.level,
                classFile = entry.class,
                area = entry.zone,
                note = entry.note,
                offlineDays = entry.online and 0 or idx,
                _isDemo = true,
            }
            if bucket and bucket.peers then
                bucket.peers[lk] = {
                    displayName = fullName,
                    version = ns.version or "0.0.0",
                    tag = entry.tag,
                    note = entry.note,
                    prof1 = entry.prof1,
                    prof2 = entry.prof2,
                    prof1Rank = entry.prof1Rank,
                    prof2Rank = entry.prof2Rank,
                    craftNote = entry.craftNote,
                    classFile = entry.class,
                    updatedAt = now,
                    _isDemo = true,
                }
            end
        end
    end

    Store.guildRosterRanks[myLookup] = {
        rankIndex = 0,
        rankName = "Líder da Guilda",
        displayName = myName,
        online = true,
        level = 60,
        classFile = myClass,
        area = "Vento Bravo",
        note = "Líder · Core PvE",
        isSelf = true,
        _isDemo = true,
    }

    if bucket then
        bucket.diplomacy.guilds = {
            ["vanguarda do alba"] = { name = "Vanguarda do Alba", stance = "ALLY", note = "Parceria BWL / Onyxia", updatedBy = myName, updatedAt = now },
            ["ordem arcana"] = { name = "Ordem Arcana", stance = "ALLY", note = "Masmorras e Portais", updatedBy = myName, updatedAt = now },
            ["lamina carmesim"] = { name = "Lâmina Carmesim", stance = "ENEMY", note = "Guilda rival em Rocha Negra", updatedBy = myName, updatedAt = now },
        }

        bucket.events = {
            ["demo_evt_1"] = {
                id = "demo_evt_1", category = "RAID", title = "Covil Asa Negra (BWL) Core", whenText = "Hoje 20:00",
                needT = 2, needH = 5, needD = 15, minLvl = 60, isOpen = true, originGuild = "Guarda Eterna", shareAllies = true,
                creator = "Kaelen Martelo", creatorKey = "kaelen martelo", createdAt = now, updatedAt = now,
                signups = {
                    ["kaelen martelo"] = { name = "Kaelen Martelo", classFile = "WARRIOR", guild = "Guarda Eterna", role = "TANK", updatedAt = now },
                    ["lyra ventoleste"] = { name = "Lyra Ventoleste", classFile = "PRIEST", guild = "Guarda Eterna", role = "HEALER", updatedAt = now },
                    ["valen escudoluz"] = { name = "Valen Escudoluz", classFile = "PALADIN", guild = "Guarda Eterna", role = "HEALER", updatedAt = now },
                    ["thorn corvo"] = { name = "Thorn Corvo", classFile = "HUNTER", guild = "Vanguarda do Alba", role = "DPS", updatedAt = now },
                    [myLookup] = { name = myName, classFile = myClass, guild = "Guarda Eterna", role = "DPS", updatedAt = now },
                },
            },
            ["demo_evt_2"] = {
                id = "demo_evt_2", category = "DUNGEON", title = "Stratholme Live — Orbes", whenText = "Em 30 min",
                needT = 1, needH = 1, needD = 3, minLvl = 58, isOpen = true, originGuild = "Guarda Eterna", shareAllies = false,
                creator = "Lyra Ventoleste", creatorKey = "lyra ventoleste", createdAt = now - 300, updatedAt = now,
                signups = {
                    ["lyra ventoleste"] = { name = "Lyra Ventoleste", classFile = "PRIEST", guild = "Guarda Eterna", role = "HEALER", updatedAt = now },
                    ["mira sombraviva"] = { name = "Mira Sombraviva", classFile = "MAGE", guild = "Ordem Arcana", role = "DPS", updatedAt = now },
                },
            },
            ["demo_evt_3"] = {
                id = "demo_evt_3", category = "QUEST", title = "Attunement Onyxia + BRD", whenText = "Amanhã 19:30",
                needT = 1, needH = 1, needD = 3, minLvl = 55, isOpen = true, originGuild = "Vanguarda do Alba", shareAllies = true, isAlliedEvent = true,
                creator = "Thorn Corvo", creatorKey = "thorn corvo", createdAt = now - 600, updatedAt = now,
                signups = {
                    ["thorn corvo"] = { name = "Thorn Corvo", classFile = "HUNTER", guild = "Vanguarda do Alba", role = "DPS", updatedAt = now },
                },
            },
        }
    end

    if ns.Clan then
        local demoLfg = {
            { key = "demo_lfg_1", sourceType = "ALLY_LFG", name = "Kaelen Martelo", class = "WARRIOR", lvl = 60, guild = "Guarda Eterna", mode = "LFM", role = "HEALER", act = "Blackrock Depths", ilvl = 72, note = "LFM 1 Healer 1 DPS BRD Arena/Imperador — Full run!" },
            { key = "demo_lfg_2", sourceType = "ALLY_LFG", name = "Lyra Ventoleste", class = "PRIEST", lvl = 60, guild = "Guarda Eterna", mode = "LFG", role = "HEALER", act = "Stratholme", ilvl = 74, note = "Healer 60 pronta para Stratholme Viva ou Morta" },
            { key = "demo_lfg_3", sourceType = "ALLY_LFG", name = "Thorn Corvo", class = "HUNTER", lvl = 60, guild = "Vanguarda do Alba", mode = "LFM", role = "TANK", act = "Onyxia's Lair", ilvl = 70, note = "LFM Tank + Healers Onyxia 20man — Saque MS>OS" },
            { key = "demo_lfg_4", sourceType = "GCHAT", name = "Mira Sombraviva", class = "MAGE", lvl = 58, guild = "Ordem Arcana", mode = "LFM", role = "ANY", act = "Scholomance", ilvl = 64, note = "LFM Scholomance missão Kirtonos 3/5 (T+2D)" },
        }
        for _, lr in ipairs(demoLfg) do
            ns.Clan.externalLFG[lr.key] = {
                sourceType = lr.sourceType, lookupKey = lr.key, displayName = lr.name, classFile = lr.class,
                level = lr.lvl, guild = lr.guild, mode = lr.mode, role = lr.role, activity = lr.act,
                ilvl = lr.ilvl, note = lr.note, isDungeon = true, updatedAt = now + 1800, _isDemo = true,
            }
        end
    end
end

local function SeedGroupAndDungeonRuns(now, myName, myLookup, myClass, myPool)
    local b = DemoShowcase._backup
    if ns.Group then
        b.prevGroupMembers = ns.Group.members
        ns.Group.members = {
            { unit = "player", name = myName, displayName = myName, lookupKey = myLookup, classFile = myClass, level = 60, role = "DAMAGER", subgroup = 1, online = true, isLeader = true, isMe = true, ready = "ready", zone = "Montanha Rocha Negra", instanceUsed = 2, instanceMax = 5, _isDemo = true },
            { unit = "party1", name = "Kaelen Martelo", displayName = "Kaelen Martelo", lookupKey = "kaelen martelo", classFile = "WARRIOR", level = 60, role = "TANK", subgroup = 1, online = true, ready = "ready", zone = "Montanha Rocha Negra", instanceUsed = 2, instanceMax = 5, _isDemo = true },
            { unit = "party2", name = "Lyra Ventoleste", displayName = "Lyra Ventoleste", lookupKey = "lyra ventoleste", classFile = "PRIEST", level = 60, role = "HEALER", subgroup = 1, online = true, ready = "ready", zone = "Montanha Rocha Negra", instanceUsed = 1, instanceMax = 5, _isDemo = true },
            { unit = "party3", name = "Mira Sombraviva", displayName = "Mira Sombraviva", lookupKey = "mira sombraviva", classFile = "MAGE", level = 58, role = "DAMAGER", subgroup = 1, online = true, ready = "waiting", zone = "Vento Bravo", instanceUsed = 3, instanceMax = 5, _isDemo = true },
            { unit = "party4", name = "Valen Escudoluz", displayName = "Valen Escudoluz", lookupKey = "valen escudoluz", classFile = "PALADIN", level = 60, role = "HEALER", subgroup = 1, online = true, ready = "ready", zone = "Montanha Rocha Negra", instanceUsed = 2, instanceMax = 5, _isDemo = true },
        }
        ns.Group._compCache = nil

        if ns.Group.GetDungeonHistoryTable then
            local hist = ns.Group:GetDungeonHistoryTable()
            hist[1] = {
                id = "demo_run_1", z = "Stratholme", t = "party", st = now - 5400, en = now - 3100, dur = 2300, cdur = 1480,
                pulls = 42, bk = 6, bn = "Baron Rivendare", dth = 1, gold = 84500, xp = 0,
                ch = myName, ck = myLookup, cl = myClass, clv = 60, rl = myPool, sz = 5, er = "completed",
                dm = { myDmg = 684200, myDps = 462, myHeal = 18500, myHps = 12, myTkn = 124000, myIntr = 14, myDisp = 3, myD = 0, myRole = "DAMAGER" },
                m = {
                    { n = "Kaelen Martelo", c = "WARRIOR", l = 60, r = "TANK", dmg = 412000, dps = 278, heal = 0, hps = 0 },
                    { n = "Lyra Ventoleste", c = "PRIEST", l = 60, r = "HEALER", dmg = 48000, dps = 32, heal = 590000, hps = 398 },
                    { n = "Mira Sombraviva", c = "MAGE", l = 58, r = "DAMAGER", dmg = 710500, dps = 480, heal = 0, hps = 0 },
                },
                _isDemo = true,
            }
            hist[2] = {
                id = "demo_run_2", z = "Blackrock Depths", t = "party", st = now - 14400, en = now - 11200, dur = 3200, cdur = 2100,
                pulls = 58, bk = 8, bn = "Emperor Dagran Thaurissan", dth = 0, gold = 112000, xp = 28500,
                ch = myName, ck = myLookup, cl = myClass, clv = 60, rl = myPool, sz = 5, er = "completed",
                dm = { myDmg = 892000, myDps = 425, myHeal = 24000, myHps = 11, myTkn = 190000, myIntr = 19, myDisp = 2, myD = 0, myRole = "DAMAGER" },
                m = {
                    { n = "Kaelen Martelo", c = "WARRIOR", l = 60, r = "TANK", dmg = 560000, dps = 266, heal = 0, hps = 0 },
                    { n = "Valen Escudoluz", c = "PALADIN", l = 60, r = "HEALER", dmg = 85000, dps = 40, heal = 740000, hps = 352 },
                },
                _isDemo = true,
            }
        end
    end

    if ns.db and type(ns.db.instanceRuns) == "table" then
        ns.db.instanceRuns[1] = { sig = "party:329", name = "Stratholme", instType = "party", enteredAt = now - 1200, charName = myName, classFile = myClass, _isDemo = true }
        ns.db.instanceRuns[2] = { sig = "party:289", name = "Scholomance", instType = "party", enteredAt = now - 2800, charName = myName, classFile = myClass, _isDemo = true }
    end
end

local function SeedAlts(now, myName, myClass, myFaction, myRealm, myPool, myWorldType, myAltKey)
    if not (ns.db and type(ns.db.alts) == "table") then return end

    ns.db.itemCatalog = ns.db.itemCatalog or {}
    ns.db.itemCatalog[19019] = "Thunderfury, Blessed Blade of the Windseeker\tInterface\\Icons\\INV_Sword_39\t5\t2\t7\tINVTYPE_WEAPONMAINHAND"
    ns.db.itemCatalog[16914] = "Netherwind Crown\tInterface\\Icons\\INV_Helmet_70\t4\t4\t1\tINVTYPE_HEAD"
    ns.db.itemCatalog[16815] = "Robe of Prophecy\tInterface\\Icons\\INV_Chest_Cloth_03\t4\t4\t1\tINVTYPE_ROBE"
    ns.db.itemCatalog[12640] = "Lionheart Helm\tInterface\\Icons\\INV_Helmet_36\t4\t4\t4\tINVTYPE_HEAD"
    ns.db.itemCatalog[13510] = "Flask of the Titans\tInterface\\Icons\\INV_Potion_62\t1\t0\t3\t"
    ns.db.itemCatalog[13444] = "Major Mana Potion\tInterface\\Icons\\INV_Potion_76\t1\t0\t1\t"
    ns.db.itemCatalog[14342] = "Mooncloth\tInterface\\Icons\\INV_Fabric_MoonRag_01\t1\t7\t5\t"
    ns.db.itemCatalog[12360] = "Arcanite Bar\tInterface\\Icons\\INV_Ingot_08\t2\t7\t7\t"

    ns.db.recipeCatalog = ns.db.recipeCatalog or {}
    ns.db.recipeCatalog["s:17632"] = "Flask of the Titans\tALCHEMY\tAlchemy\t13510\t17632\t1\tInterface\\Icons\\INV_Potion_62\t12360:1"
    ns.db.recipeCatalog["s:18560"] = "Mooncloth\tTAILORING\tTailoring\t14342\t18560\t1\tInterface\\Icons\\INV_Fabric_MoonRag_01\t14342:2"
    ns.db.recipeCatalog["s:20034"] = "Enchant Weapon - Crusader\tENCHANTING\tEnchanting\t\t20034\t3\tInterface\\Icons\\Spell_Holy_GreaterHeal\t12360:2"
    ns.db.recipeCatalog["s:23787"] = "Lionheart Helm\tBLACKSMITHING\tBlacksmithing\t12640\t23787\t4\tInterface\\Icons\\INV_Helmet_36\t12360:12"

    local altWorld = (myWorldType == "PvE") and "PvP" or "PvE"
    local altPool = (altWorld == "PvP") and "pvp" or "pve"
    local myParsed = Compat and Compat.ParseCharacterName and Compat.ParseCharacterName(myName)

    ns.db.alts[myAltKey] = {
        key = myAltKey,
        name = (myParsed and myParsed.firstName) or myName,
        firstName = (myParsed and myParsed.firstName) or myName,
        surname = myParsed and myParsed.surname or nil,
        fullName = myName,
        realmName = myRealm, worldType = myWorldType, realmPool = myPool, faction = myFaction,
        className = myClass, classFile = myClass, level = 60, itemLevel = 76, durabilityPct = 96,
        xp = 0, xpMax = 1, rested = 0, wasResting = true, money = 22650000,
        zone = "Vento Bravo", bindLocation = "Vento Bravo", hearthReadyAt = 0, guild = "Guarda Eterna",
        professions = { { name = "Alchemy", rank = 300, maxRank = 300 }, { name = "Herbalism", rank = 300, maxRank = 300 } },
        recipes = { ALCHEMY = { keys = "s:17632", pn = "Alchemy", rank = 300, maxRank = 300 } },
        craftCooldowns = { { name = "Transmutar: Arcanita", readyAt = now - 30 } },
        lockouts = {
            { name = "Blackwing Lair", id = 469, expiresAt = now + 345600, locked = true, extended = false, isRaid = true, difficultyName = "40 Players", numEncounters = 8, encounterProgress = 6 },
            { name = "Zul'Gurub", id = 309, expiresAt = now + 129600, locked = true, extended = false, isRaid = true, difficultyName = "20 Players", numEncounters = 10, encounterProgress = 10 },
        },
        equipment = { [1] = "12640\t1", [16] = "19019\t1" },
        bags = { "13510\t4", "13444\t15", "12360\t3" },
        bank = { "14342\t8", "12360\t5" },
        bagFree = 20, bagTotal = 80, bankFree = 30, bankTotal = 96,
        _itemSeq = 1,
        hasMail = true, mailSince = now - 7200, mailSenders = { "Kaelen Martelo" },
        firstSeen = now - 1200000, lastActive = now, _isDemo = true,
    }

    ns.db.alts["demo_alt_mage"] = {
        key = "demo_alt_mage",
        name = "Kaelen", firstName = "Kaelen", surname = "Arcanista", fullName = "Kaelen Arcanista",
        realmName = myRealm, worldType = myWorldType, realmPool = myPool, faction = myFaction,
        className = "Mage", classFile = "MAGE", level = 60, itemLevel = 74, durabilityPct = 98,
        xp = 0, xpMax = 1, rested = 0, wasResting = true, money = 14854200,
        zone = "Vento Bravo", bindLocation = "Vento Bravo", hearthReadyAt = 0, guild = "Guarda Eterna",
        professions = { { name = "Tailoring", rank = 300, maxRank = 300 }, { name = "Enchanting", rank = 300, maxRank = 300 } },
        recipes = {
            TAILORING = { keys = "s:18560", pn = "Tailoring", rank = 300, maxRank = 300 },
            ENCHANTING = { keys = "s:20034", pn = "Enchanting", rank = 300, maxRank = 300 },
        },
        craftCooldowns = { { name = "Tecido Lunar", readyAt = now - 60 } },
        lockouts = {
            { name = "Molten Core", id = 409, expiresAt = now + 259200, locked = true, extended = false, isRaid = true, difficultyName = "40 Players", numEncounters = 10, encounterProgress = 10 },
            { name = "Onyxia's Lair", id = 249, expiresAt = now + 172800, locked = true, extended = false, isRaid = true, difficultyName = "40 Players", numEncounters = 1, encounterProgress = 1 },
        },
        equipment = { [1] = "16914\t1" },
        bags = { "13444\t20", "14342\t6" },
        bank = { "13510\t2", "14342\t10" },
        bagFree = 18, bagTotal = 80, bankFree = 24, bankTotal = 96,
        _itemSeq = 1,
        hasMail = true, mailSince = now - 172800, mailSenders = { "Leiloeira" },
        firstSeen = now - 864000, lastActive = now - 1200, _isDemo = true,
    }

    ns.db.alts["demo_alt_priest"] = {
        key = "demo_alt_priest",
        name = "Lyra", firstName = "Lyra", surname = "Alvorada", fullName = "Lyra Alvorada",
        realmName = myRealm, worldType = altWorld, realmPool = altPool, faction = myFaction,
        className = "Priest", classFile = "PRIEST", level = 54, itemLevel = 58, durabilityPct = 100,
        xp = 98400, xpMax = 148200, rested = 222300, wasResting = true, money = 4238000,
        zone = "Tanaris", bindLocation = "Geringontzan", hearthReadyAt = 0, guild = "Guarda Eterna",
        professions = { { name = "Alchemy", rank = 290, maxRank = 300 }, { name = "Herbalism", rank = 300, maxRank = 300 } },
        recipes = { ALCHEMY = { keys = "s:17632", pn = "Alchemy", rank = 290, maxRank = 300 } },
        craftCooldowns = { { name = "Transmutar: Arcanita", readyAt = now + 7200 } },
        equipment = { [5] = "16815\t1" },
        bags = { "13444\t12", "13510\t2" },
        bank = { "12360\t4" },
        bagFree = 22, bagTotal = 72, bankFree = 16, bankTotal = 72,
        _itemSeq = 1,
        hasMail = false, firstSeen = now - 604800, lastActive = now - 18000, _isDemo = true,
    }

    ns.db.alts["demo_alt_warrior"] = {
        key = "demo_alt_warrior",
        name = "Thorn", firstName = "Thorn", surname = "Punho", fullName = "Thorn Punho",
        realmName = myRealm, worldType = myWorldType, realmPool = myPool, faction = myFaction,
        className = "Warrior", classFile = "WARRIOR", level = 48, itemLevel = 51, durabilityPct = 92,
        xp = 72000, xpMax = 122500, rested = 160000, wasResting = true, money = 1859000,
        zone = "Feralas", bindLocation = "Vento Bravo", hearthReadyAt = 0, guild = "Guarda Eterna",
        professions = { { name = "Blacksmithing", rank = 265, maxRank = 300 }, { name = "Mining", rank = 275, maxRank = 300 } },
        recipes = { BLACKSMITHING = { keys = "s:23787", pn = "Blacksmithing", rank = 265, maxRank = 300 } },
        equipment = { [1] = "12640\t1", [16] = "19019\t1" },
        bags = { "12360\t6" },
        bank = { "12360\t12" },
        bagFree = 14, bagTotal = 64, bankFree = 20, bankTotal = 64,
        _itemSeq = 1,
        hasMail = false, firstSeen = now - 404800, lastActive = now - 42000, _isDemo = true,
    }

    if ns.Alts then
        ns.Alts._itemIndexBuilt = false
        ns.Alts.itemIndex = nil
        ns.Alts._altBuckets = nil
        ns.Alts._recipeIndexCache = nil
        ns.Alts._recipeSeq = (ns.Alts._recipeSeq or 0) + 1
    end
end

local function SeedChatPreviewsToastsAndRolls(now)
    local b = DemoShowcase._backup
    local scope = b.scope or (Compat and Compat.ScopeKey and Compat.ScopeKey()) or "default"

    if ns.db and type(ns.db.chatRooms) == "table" then
        ns.db.chatRooms[scope] = ns.db.chatRooms[scope] or {}
        ns.db.chatRooms[scope]["demo_core"] = {
            id = "demo_core",
            title = "Core Raide BWL",
            joined = true,
            _isDemo = true,
        }
    end

    if ns.Chat and ns.Chat.threads then
        ns.Chat.threads["ch:general"] = {
            key = "ch:general",
            kind = "GENERAL",
            title = L["General"],
            unread = 0,
            lastAt = now - 15,
            skipPersist = true,
            _isDemo = true,
            messages = {
                { ts = now - 120, sender = "Kaelen Martelo", text = "Alguém para fechar BRD Arena/Imperador?", incoming = true, classFile = "WARRIOR" },
                { ts = now - 15, sender = "Mira Sombraviva", text = "Fazendo portais em Vento Bravo!", incoming = true, classFile = "MAGE" },
            },
        }
        ns.Chat.threads["notes:self"] = {
            key = "notes:self",
            kind = "NOTES",
            title = L["Personal Notes (You)"],
            unread = 0,
            lastAt = now - 300,
            _isDemo = true,
            messages = {
                { ts = now - 3600, sender = "Você", text = "Lembrar de levar 2 Frascos de Titã e 15 Poções de Mana para BWL.", incoming = false },
                { ts = now - 300, sender = "Você", text = "Kaelen Martelo guarda os Cristais Arcanos no banco da guilda.", incoming = false },
            },
        }
        ns.Chat.threads["ch:guild"] = {
            key = "ch:guild",
            kind = "GUILD",
            title = L["Guild"],
            unread = 1,
            lastAt = now - 60,
            _isDemo = true,
            messages = {
                { ts = now - 180, sender = "Kaelen Martelo", text = "Invites do Core BWL abrem às 19:45!", incoming = true, classFile = "WARRIOR", senderLevel = 60, viaAddon = true },
                { ts = now - 60, sender = "Valen Escudoluz", text = "Estou levando consumíveis para os healers.", incoming = true, classFile = "PALADIN", senderLevel = 60, viaAddon = true },
            },
        }
        ns.Chat.threads["ch:alliance"] = {
            key = "ch:alliance",
            kind = "ALLIANCE",
            title = L["Alliance"],
            slash = "/al ",
            unread = 1,
            lastAt = now - 90,
            _isDemo = true,
            messages = {
                { ts = now - 90, sender = "Thorn Corvo", text = "Onyxia 20man às 21:30 — vagas abertas para aliados!", incoming = true, classFile = "HUNTER", senderLevel = 60, viaAddon = true },
            },
        }
        ns.Chat.threads["room:demo_core"] = {
            key = "room:demo_core",
            kind = "ROOM",
            roomId = "demo_core",
            title = "Core Raide BWL",
            unread = 0,
            lastAt = now - 140,
            _isDemo = true,
            messages = {
                { ts = now - 240, sender = "Kaelen Martelo", text = "Definida a rotação de tanques para Razorgore e Vaelastrasz.", incoming = true, classFile = "WARRIOR", viaAddon = true },
                { ts = now - 140, sender = "Lyra Ventoleste", text = "Assignments de cura atualizados.", incoming = true, classFile = "PRIEST", viaAddon = true },
            },
        }
        ns.Chat.threads["demo:w:kaelen"] = {
            key = "demo:w:kaelen",
            kind = "WHISPER",
            title = "Kaelen Martelo",
            targetName = "Kaelen Martelo",
            classFile = "WARRIOR",
            level = 60,
            unread = 1,
            lastAt = now - 45,
            pinned = true,
            _isDemo = true,
            messages = {
                { ts = now - 240, sender = "Kaelen Martelo", text = "Bora fechar BRD Arena/Imperador agora? Só falta healer e 1 dps.", incoming = true, classFile = "WARRIOR", viaAddon = true },
                { ts = now - 160, sender = "Você", text = "Fechou! Estou terminando de reparar em Vento Bravo.", incoming = false, viaAddon = true },
                { ts = now - 45, sender = "Kaelen Martelo", text = "Beleza, Lyra já está indo pra pedra de encontro!", incoming = true, classFile = "WARRIOR", viaAddon = true },
            },
        }
        ns.Chat.threads["bn:demo_lyra"] = {
            key = "bn:demo_lyra",
            kind = "BN_WHISPER",
            title = "Lyra Ventoleste",
            targetName = "Lyra Ventoleste",
            bnetName = "Lyra#2891",
            bnetAccountID = 99002,
            classFile = "PRIEST",
            level = 60,
            unread = 2,
            lastAt = now - 20,
            pinned = false,
            _isDemo = true,
            messages = {
                { ts = now - 90, sender = "Lyra Ventoleste", text = "Guardei 2 poções de mana extras pra nossa run!", incoming = true, classFile = "PRIEST" },
                { ts = now - 20, sender = "Lyra Ventoleste", text = "Me avisa quando entrar na instância.", incoming = true, classFile = "PRIEST" },
            },
        }
        if ns.Chat.TriggerTestMention then
            ns.Chat:TriggerTestMention()
        end
        ns.Chat.activeThreadKey = "demo:w:kaelen"
        if ns.Chat.InvalidateUnreadCache then
            ns.Chat:InvalidateUnreadCache()
        end
    end

    if ns.QuickBar and ns.QuickBar.SetEnabled then
        b.quickBarWasOff = (ns.db and ns.db.settings and ns.db.settings.quickBarEnabled == false)
        if b.quickBarWasOff then
            ns.QuickBar:SetEnabled(true)
        end
    end

    if ns.QuickReply and ns.QuickReply.OpenThread then
        ns.QuickReply:OpenThread("demo:w:kaelen", false)
    end
    if ns.MinimapPreview and ns.MinimapPreview.ShowTestPreview then
        ns.MinimapPreview:ShowTestPreview("badge fusion")
        ns.MinimapPreview:ShowTestPreview("queue")
    end
    if ns.NotificationToast and ns.NotificationToast.ShowTestNotification then
        ns.NotificationToast:ShowTestNotification("queue")
    end
    if ns.LootRoll and ns.LootRoll.RunPreviewSimulation then
        ns.LootRoll:RunPreviewSimulation("")
    end
    if ns.FlightTimes and ns.FlightTimes.SetDemoPreview then
        ns.FlightTimes:SetDemoPreview(true)
    end
end

local function EmitAllRefreshSignals()
    for _, ev in ipairs({
        "SOCIAL_UPDATED",
        "WATCHLIST_UPDATED",
        "NEARBY_UPDATED",
        "SPOTTER_UPDATED",
        "CLAN_UPDATED",
        "GROUP_UPDATED",
        "DUNGEON_HISTORY_UPDATED",
        "ALTS_UPDATED",
        "CHAT_UPDATED",
        "LFG_BROWSE_STATE_CHANGED",
    }) do
        ns:Emit(ev)
    end
    if ns.Minimap and ns.Minimap.Update then
        pcall(ns.Minimap.Update, ns.Minimap)
    end
    if ns.LFGFrameTab and ns.LFGFrameTab.RefreshData then
        pcall(ns.LFGFrameTab.RefreshData, ns.LFGFrameTab)
    end
    if ns.UI and ns.UI.QueueRefresh then
        ns.UI:QueueRefresh(false)
    elseif ns.UI and ns.UI.Refresh then
        pcall(ns.UI.Refresh, ns.UI)
    end
end

function DemoShowcase:IsActive()
    return self._active == true
end

function DemoShowcase:Enable()
    if self._active then
        self:Clear(true)
    end
    self._active = true
    self._backup = {}

    local now = time()
    local myName, myLookup, myClass, myFaction, myRealm, myPool, myWorldType, myAltKey = GetCurrentScopeKeys()

    BackupAndSwapLiveTables(now, myFaction, myPool)
    SeedSocialWatchlistNearbySpotter(now, myFaction, myPool)
    SeedClanAndLfg(now, myName, myLookup, myClass)
    SeedGroupAndDungeonRuns(now, myName, myLookup, myClass, myPool)
    SeedAlts(now, myName, myClass, myFaction, myRealm, myPool, myWorldType, myAltKey)
    SeedChatPreviewsToastsAndRolls(now)

    EmitAllRefreshSignals()
    ns:Print("|cff34d399%s|r", L["Demo mode activated: hypothetical data populated across all windows."])
    return true
end

function DemoShowcase:Clear(silent)
    local b = self._backup or {}
    if not self._active and next(b) == nil then
        return false
    end
    self._active = false

    if b.prevSocial then Store.social = b.prevSocial end
    if b.prevSocialByGuid then Store.socialByGuid = b.prevSocialByGuid end
    if b.prevSocialByLookup then Store.socialByLookup = b.prevSocialByLookup end
    if b.prevSocialDir then Store.socialDirectory = b.prevSocialDir end
    if b.prevSocialDirByKey then Store.socialDirectoryByKey = b.prevSocialDirByKey end
    if b.prevSocialDirByLookup then Store.socialDirectoryByLookup = b.prevSocialDirByLookup end
    if b.prevSocialDirByBNet then Store.socialDirectoryByBNet = b.prevSocialDirByBNet end
    if b.prevGuildInfo then Store.guildInfo = b.prevGuildInfo end
    if b.prevGuildRanks then Store.guildRosterRanks = b.prevGuildRanks end
    if b.prevNearby then Store.nearby = b.prevNearby end
    Store._socialFoldersCache = nil

    if ns.db then
        local scope = b.scope or (Compat and Compat.ScopeKey and Compat.ScopeKey()) or "default"
        if b.swappedWatchlist and type(ns.db.watchlist) == "table" then
            ns.db.watchlist[scope] = b.prevWatchlist
        end
        if b.swappedSocialMeta and type(ns.db.socialMeta) == "table" then
            ns.db.socialMeta[scope] = b.prevSocialMeta
        end
        if b.swappedChatHistory and type(ns.db.chatHistory) == "table" then
            ns.db.chatHistory[scope] = b.prevChatHistory
        end
        if b.swappedChatRooms then
            if b.prevHasChatRoomsTbl and type(ns.db.chatRooms) == "table" then
                ns.db.chatRooms[scope] = b.prevChatRooms
            else
                ns.db.chatRooms = nil
            end
        end
        if b.swappedIgnores then ns.db.accountIgnores = b.prevIgnores end
        if b.swappedAlts then ns.db.alts = b.prevAlts end
        if b.swappedInstanceRuns then ns.db.instanceRuns = b.prevInstanceRuns end
        if b.swappedDungeonHistory then ns.db.dungeonHistory = b.prevDungeonHistory end
        if b.swappedWbDrops then ns.db.worldBuffsDrops = b.prevWbDrops end
        if b.swappedItemCatalog then ns.db.itemCatalog = b.prevItemCatalog end
        if b.swappedRecipeCatalog then ns.db.recipeCatalog = b.prevRecipeCatalog end
        if b.swappedDemoClanBucket and b.demoClanScopeKey then
            if b.prevHasClanTbl and type(ns.db.clan) == "table" then
                ns.db.clan[b.demoClanScopeKey] = b.prevDemoClanBucket
            else
                ns.db.clan = nil
            end
        end
    end

    if Store.InvalidateScopeCaches then
        Store:InvalidateScopeCaches()
    end

    if ns.Spotter then
        if b.prevSpotterEntries then ns.Spotter.entries = b.prevSpotterEntries end
        if b.prevSpotterByGuid then ns.Spotter.entryByGuid = b.prevSpotterByGuid end
        if ns.Spotter.MarkDemoDirty then ns.Spotter:MarkDemoDirty() end
        if ns.Spotter.RefreshVisibleNameplates then
            pcall(ns.Spotter.RefreshVisibleNameplates, ns.Spotter, false)
        end
        if ns.SpotterHUD and ns.SpotterHUD.frame and b.spotterWasShown == false then
            ns.SpotterHUD.frame:Hide()
        end
    end

    if ns.Clan then
        if b.prevExternalLFG then ns.Clan.externalLFG = b.prevExternalLFG end
        if b.prevGlobalLFG then ns.Clan.globalChatLFG = b.prevGlobalLFG end
        if b.prevOfficialLFG then ns.Clan.officialLfgCache = b.prevOfficialLFG end
    end

    if ns.Chat then
        if b.prevChatThreads then ns.Chat.threads = b.prevChatThreads end
        ns.Chat.activeThreadKey = b.prevActiveThreadKey
        if b.prevVerifiedPeers then ns.Chat.sessionVerifiedPeers = b.prevVerifiedPeers end
        if b.prevBNetPeers then ns.Chat.sessionBNetPeers = b.prevBNetPeers end
        if b.swappedQuickReplyDrafts then ns.Chat.quickReplyDrafts = b.prevQuickReplyDrafts end
        ns.Chat._savedTextBytes = b.prevSavedTextBytes
        if ns.Chat.InvalidateUnreadCache then ns.Chat:InvalidateUnreadCache() end
    end

    if ns.Social then
        ns.Social._counts = b.prevSocialCounts
        ns.Social._dirStats = b.prevSocialDirStats
        ns.Social._dirRevision = (ns.Social._dirRevision or 0) + 1
    end

    if ns.Group then
        if b.prevGroupMembers ~= nil then
            ns.Group.members = b.prevGroupMembers
        else
            ns.Group.members = {}
        end
        ns.Group._compCache = nil
        if ns.Group.Scan then pcall(ns.Group.Scan, ns.Group) end
    end

    if ns.Nearby and ns.Nearby.GetCount then
        pcall(ns.Nearby.GetCount, ns.Nearby)
    end
    if ns.Alts then
        ns.Alts._itemIndexBuilt = false
        ns.Alts.itemIndex = nil
        ns.Alts._altBuckets = nil
        ns.Alts._recipeIndexCache = nil
        ns.Alts._recipeSeq = (ns.Alts._recipeSeq or 0) + 1
    end

    if ns.QuickReply then
        local lastDst = ns.QuickReply._lastDestinationKey
        if lastDst and (lastDst:sub(1, 5) == "demo:" or lastDst:sub(1, 8) == "bn:demo_" or lastDst == "room:demo_core") then
            ns.QuickReply._lastDestinationKey = nil
        end
        local aKey = ns.QuickReply.activeKey
        if aKey and (aKey:sub(1, 5) == "demo:" or aKey:sub(1, 8) == "bn:demo_" or aKey == "room:demo_core") then
            ns.QuickReply.activeKey = b.prevActiveThreadKey or "ch:general"
            ns.QuickReply._forceMsgRebuild = true
            if ns.QuickReply.frame and ns.QuickReply.frame:IsShown() then
                ns.QuickReply.frame:Hide()
            end
        end
    end
    if b.quickBarWasOff and ns.QuickBar and ns.QuickBar.SetEnabled then
        ns.QuickBar:SetEnabled(false)
    end
    if ns.MinimapPreview and ns.MinimapPreview.ShowTestPreview then
        ns.MinimapPreview:ShowTestPreview("clear")
    end
    if ns.NotificationToast and ns.NotificationToast.ShowTestNotification then
        ns.NotificationToast:ShowTestNotification("clear")
    end
    if ns.LootRoll and ns.LootRoll.ClearSimulatedRolls then
        ns.LootRoll:ClearSimulatedRolls()
    end
    if ns.FlightTimes and ns.FlightTimes.SetDemoPreview then
        ns.FlightTimes:SetDemoPreview(false)
    end

    self._backup = {}
    if ns.Social and ns.Social.Scan then
        pcall(ns.Social.Scan, ns.Social)
    end
    EmitAllRefreshSignals()
    if not silent then
        ns:Print("|cffffd200%s|r", L["Demo mode cleared: all hypothetical data removed."])
    end
    return true
end

function DemoShowcase:Toggle()
    if self._active then
        return self:Clear()
    end
    return self:Enable()
end

function DemoShowcase:Init()
    -- Pure in-memory isolation; zero SavedVariables pollution.
end
