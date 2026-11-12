local _, ns = ...

local Safe = ns.Safe
local Compat = ns.Compat

-- Records snapshots of the player's own characters across logins.
local Alts = {}
ns.Alts = Alts
table.insert(ns.modules, Alts)

function Alts:Snapshot()
    if not (ns.db and ns.db.alts) then return end
    local name = Safe.String(Safe.Call(UnitName, "player"))
    if not name then return end

    local key = Compat.CharacterKey()
    local _, classFile = Safe.Call(UnitClass, "player")
    local level = Safe.Number(Safe.Call(UnitLevel, "player")) or 1
    local xp = Safe.Number(Safe.Call(UnitXP, "player")) or 0
    local xpMax = Safe.Number(Safe.Call(UnitXPMax, "player")) or 1
    local rested = Safe.Number(Safe.Call(GetXPExhaustion)) or 0
    local money = Safe.Number(Safe.Call(GetMoney)) or 0
    local guild = Safe.String(Safe.Call(GetGuildInfo, "player")) or ""
    local faction = Compat.PlayerFaction()

    ns.db.alts[key] = {
        name = name,
        realmPool = Compat.RealmPool(Compat.Realm()),
        faction = faction,
        classFile = Safe.String(classFile),
        level = level,
        xp = xp,
        xpMax = xpMax,
        rested = rested,
        money = money,
        zone = Compat.CurrentZoneName(),
        guild = guild,
        lastActive = time(),
    }

    ns:Emit("ALTS_UPDATED")
end

function Alts:Init()
    for _, eventName in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_XP_UPDATE",
        "PLAYER_LEVEL_UP",
        "UPDATE_EXHAUSTION",
        "PLAYER_MONEY",
        "ZONE_CHANGED_NEW_AREA",
        "PLAYER_GUILD_UPDATE",
        "PLAYER_LOGOUT",
    }) do
        ns.RegisterEvent(self, eventName, function()
            self:Snapshot()
        end)
    end
end
