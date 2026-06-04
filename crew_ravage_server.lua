-- =========================================================
--  crew_ravage_server.lua  —  Récap des stocks de la base du crew
-- ---------------------------------------------------------
--  INSTALLATION :
--   1) Place ce fichier dans le dossier de hrs_base_building.
--   2) Dans hrs_base_building/fxmanifest.lua, ajoute-le en server_scripts,
--      APRÈS main.lua (ou le fichier serveur crew) :
--          server_scripts {
--              '@oxmysql/lib/MySQL.lua',   -- (déjà présent normalement)
--              'server/main.lua',
--              'crew_ravage_server.lua',   -- <= ici
--          }
--
-- =========================================================

local STOCK_PERMISSION = "canInteract"

local ACL_PERMISSION = "canManageMembers"

local DEBUG_CHEST = true


local USE_CITIZENID = true

if USE_CITIZENID and Config and Config.Framework == "QB" then
    function GetIdentifier(xPlayer)
        if type(xPlayer) == 'number' then xPlayer = GetPlayerFromId(xPlayer) end
        if xPlayer and xPlayer.PlayerData and xPlayer.PlayerData.citizenid then
            return xPlayer.PlayerData.citizenid
        end
        if xPlayer and xPlayer.PlayerData then
            return QBCore.Functions.GetIdentifier(xPlayer.PlayerData.source, 'license')
        end
        return nil
    end

    function getName(xPlayer)
        if type(xPlayer) == 'number' then xPlayer = GetPlayerFromId(xPlayer) end
        if xPlayer and xPlayer.PlayerData and xPlayer.PlayerData.charinfo then
            local ci = xPlayer.PlayerData.charinfo
            local full = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub("^%s+", ""):gsub("%s+$", "")
            if full ~= '' then return full end
        end
        if xPlayer and xPlayer.PlayerData then
            return GetPlayerName(xPlayer.PlayerData.source)
        end
        return "Inconnu"
    end


elseif USE_CITIZENID and Config and Config.Framework == "ESX" then
    function getName(xPlayer)
        if type(xPlayer) == 'number' then xPlayer = GetPlayerFromId(xPlayer) end
        if xPlayer then
            if xPlayer.getName then
                local n = xPlayer.getName()
                if n and n ~= '' then return n end
            end
            if xPlayer.get then
                local fn = xPlayer.get('firstName') or xPlayer.get('firstname')
                local ln = xPlayer.get('lastName') or xPlayer.get('lastname')
                if fn then return ((fn .. ' ' .. (ln or '')):gsub("%s+$", "")) end
            end
        end
        return "Inconnu"
    end
end

-- ox_inventory : nom de la table de stockage (par défaut "ox_inventory")
local OX_TABLE = "ox_inventory"

-- Trouve le centre + rayon de la zone de claim (totem du chef en priorité)
local function getCrewClaim(crewId)
    local anyCoords, anyRadius
    for k, v in pairs(props) do
        if v.coords then
            local cfg = Config.Models[v.hash]
            if cfg then
                local isClaim = cfg.type == "buildFlag" or cfg.isBuildFLag
                    or cfg.buildRadius or cfg.claimRadius
                    or (Config.claimPropType and Config.claimPropType[cfg.type])
                if isClaim then
                    local inCrew = (v.identifier == crewId)
                        or (crews[crewId] and crews[crewId].data and crews[crewId].data[v.identifier] ~= nil)
                    if inCrew then
                        local radius = cfg.buildRadius or cfg.claimRadius
                            or (Config.claimPropType and Config.claimPropType[cfg.type] and Config.claimPropType[cfg.type].radius)
                            or 25.0
                        if v.identifier == crewId then
                            return v.coords, radius           -- totem du chef -> priorité
                        elseif not anyCoords then
                            anyCoords, anyRadius = v.coords, radius
                        end
                    end
                end
            end
        end
    end
    return anyCoords, anyRadius
end

-- Résout l'ID de prop sur la VRAIE clé utilisée par la table props
-- (les clés peuvent être des nombres OU des chaînes selon le build/DB).
local function resolvePropId(rawId)
    if rawId == nil then return nil end
    if props[rawId] ~= nil then return rawId end
    local n = tonumber(rawId)
    if n ~= nil and props[n] ~= nil then return n end
    local s = tostring(rawId)
    if props[s] ~= nil then return s end
    return nil
end

-- Reconstruit l'ID de stash ox_inventory comme le fait hrs_base_building
local function getStashId(k, v)
    local text = 'HRS' .. v.hash .. "" .. k .. "" .. v.date
    text = string.gsub(text, "-", "n")
    text = string.gsub(text, ":", "")
    text = string.gsub(text, "_", "")
    text = string.gsub(text, "/", "")
    if Config.usingOldInventoryMethod then
        text = tostring('HRS_' .. v.hash .. "_" .. k .. "_" .. v.date)
    end
    return text
end

-- Lecture EN MÉMOIRE des items d'un stash ox (essaie plusieurs exports).
-- Renvoie une table d'items, ou nil si non chargé / indisponible.
local function readStashItems(stashId)
    local ok, res = pcall(function() return exports.ox_inventory:GetInventoryItems(stashId) end)
    if ok and type(res) == 'table' then return res end
    local ok2, inv = pcall(function() return exports.ox_inventory:GetInventory(stashId) end)
    if ok2 and type(inv) == 'table' and type(inv.items) == 'table' then return inv.items end
    return nil
end

local function sendStocks(src, crewId, center, radius)
    local agg = {}        -- name -> count
    local stashIds = {}

    for k, v in pairs(props) do
        if v.coords and GetDistanceXY(v.coords, center) <= radius then
            local inCrew = (v.identifier == crewId)
                or (crews[crewId] and crews[crewId].data and crews[crewId].data[v.identifier] ~= nil)
            if inCrew then
                local cfg = Config.Models[v.hash]
                if cfg then
                    -- Stockpiles (itemStock) -> items dans la metadata
                    if cfg.itemStock then
                        local md = getMetadata(k)
                        if md and md.items then
                            for itemName, cnt in pairs(md.items) do
                                if type(cnt) == 'number' and cnt > 0 then
                                    agg[itemName] = (agg[itemName] or 0) + cnt
                                end
                            end
                        end
                    end
                    -- Coffres ox_inventory : lecture EN MÉMOIRE (live) via l'export.
                    -- Repli SQL uniquement si le coffre n'est pas chargé (jamais ouvert).
                    if cfg.type == "storages" and not v.dead then
                        local stashId = getStashId(k, v)
                        local items = readStashItems(stashId)

                        if items ~= nil then
                            for _, it in pairs(items) do
                                if type(it) == 'table' and it.name then
                                    local c = it.count or it.amount or 0
                                    if type(c) == 'number' and c > 0 then
                                        agg[it.name] = (agg[it.name] or 0) + c
                                    end
                                end
                            end
                        else
                            stashIds[#stashIds + 1] = stashId  -- repli SQL
                        end
                    end
                end
            end
        end
    end

    local function finish()
        local list = {}
        local total = 0
        for name, count in pairs(agg) do
            if count > 0 then
                list[#list + 1] = { name = name, label = (itemLabels[name] or name), count = count }
                total = total + count
            end
        end
        table.sort(list, function(a, b) return a.count > b.count end)
        TriggerClientEvent('ravage-crews:stocksResult', src, { items = list, total = total }, nil)
    end

    if #stashIds == 0 then
        finish()
        return
    end

    -- Lecture directe de la table ox_inventory (robuste : pas de souci de
    -- coffre non chargé en mémoire). Les ID sont alphanumériques (sanitisés).
    local placeholders = {}
    for i = 1, #stashIds do placeholders[i] = '?' end
    local query = "SELECT name, data FROM " .. OX_TABLE .. " WHERE name IN (" .. table.concat(placeholders, ",") .. ")"

    MySQL.Async.fetchAll(query, stashIds, function(rows)
        if rows then
            for _, row in ipairs(rows) do
                if row.data then
                    local ok, items = pcall(json.decode, row.data)
                    if ok and type(items) == 'table' then
                        for _, it in pairs(items) do
                            if type(it) == 'table' and it.name then
                                local c = it.count or it.amount or 0
                                if type(c) == 'number' and c > 0 then
                                    agg[it.name] = (agg[it.name] or 0) + c
                                end
                            end
                        end
                    end
                end
            end
        end
        finish()
    end)
end

RegisterNetEvent('ravage-crews:requestStocks')
AddEventHandler('ravage-crews:requestStocks', function()
    local src = source
    local xPlayer = GetPlayerFromId(src)
    if not xPlayer then return end

    local identifier = GetIdentifier(xPlayer)
    local crewBool, crewId = isPartOfCrew(identifier)

    if not crewBool then
        TriggerClientEvent('ravage-crews:stocksResult', src, nil, "no_crew")
        return
    end

    if not hasCrewPermission(identifier, nil, STOCK_PERMISSION) then
        TriggerClientEvent('ravage-crews:stocksResult', src, nil, "no_perm")
        return
    end

    local center, radius = getCrewClaim(crewId)
    if not center then
        TriggerClientEvent('ravage-crews:stocksResult', src, nil, "no_base")
        return
    end

    sendStocks(src, crewId, center, radius)
end)

-- =========================================================
--  ACCÈS PAR COFFRE (ACL par membre)
--  Modèle : coffre SANS réglage = ouvert à tout le crew.
--  L'ACL stocke les membres BLOQUÉS (metadata.acl[identifier] = true).
--  Le chef et le propriétaire du coffre gardent toujours l'accès.
-- =========================================================

-- ---- Lister les coffres de la zone (pour l'écran de gestion d'accès) ----
RegisterNetEvent('ravage-crews:requestChests')
AddEventHandler('ravage-crews:requestChests', function()
    local src = source
    local xPlayer = GetPlayerFromId(src)
    if not xPlayer then return end

    local identifier = GetIdentifier(xPlayer)
    local crewBool, crewId = isPartOfCrew(identifier)

    if not crewBool then
        TriggerClientEvent('ravage-crews:chestsResult', src, nil, "no_crew")
        return
    end
    if not hasCrewPermission(identifier, nil, ACL_PERMISSION) then
        TriggerClientEvent('ravage-crews:chestsResult', src, nil, "no_perm")
        return
    end

    local center, radius = getCrewClaim(crewId)
    if not center then
        TriggerClientEvent('ravage-crews:chestsResult', src, nil, "no_base")
        return
    end

    local chests = {}
    for k, v in pairs(props) do
        if v.coords and GetDistanceXY(v.coords, center) <= radius then
            local inCrew = (v.identifier == crewId)
                or (crews[crewId] and crews[crewId].data and crews[crewId].data[v.identifier] ~= nil)
            if inCrew then
                local cfg = Config.Models[v.hash]
                if cfg and cfg.type == "storages" and not v.dead then
                    local denied = {}
                    local md = getMetadata(k)
                    if md and md.acl then
                        for id, blocked in pairs(md.acl) do
                            if blocked then denied[#denied + 1] = id end
                        end
                    end
                    if DEBUG_CHEST then
                    end
                    local md2 = getMetadata(k)
                    chests[#chests + 1] = {
                        id     = k,
                        label  = (itemLabels[cfg.item] or cfg.item or ("Coffre #" .. k)),
                        name   = (type(md2) == 'table' and md2.crewName) or nil,
                        x      = v.coords.x,
                        y      = v.coords.y,
                        z      = v.coords.z,
                        denied = denied
                    }
                end
            end
        end
    end

    table.sort(chests, function(a, b) return a.id < b.id end)
    TriggerClientEvent('ravage-crews:chestsResult', src, { chests = chests }, nil)
end)

-- ---- Définir l'ACL d'un coffre (liste des membres bloqués) ----
RegisterNetEvent('ravage-crews:setChestAcl')
AddEventHandler('ravage-crews:setChestAcl', function(payloadStr)
    local src = source
    if DEBUG_CHEST then
    end

    local payload = (type(payloadStr) == 'string') and json.decode(payloadStr) or payloadStr
    if type(payload) ~= 'table' then return end
    local propId = resolvePropId(payload.propId)
    local deniedList = payload.denied or {}

    local xPlayer = GetPlayerFromId(src)
    if not xPlayer then return end

    if not propId or not props[propId] then return end

    local identifier = GetIdentifier(xPlayer)
    local crewBool, crewId = isPartOfCrew(identifier)
    if not crewBool then return end
    if not hasCrewPermission(identifier, nil, ACL_PERMISSION) then
        ShowNotification(src, "Accès refusé.")
        return
    end

    -- le coffre doit appartenir au crew
    local v = props[propId]
    local inCrew = (v.identifier == crewId)
        or (crews[crewId] and crews[crewId].data and crews[crewId].data[v.identifier] ~= nil)
    if not inCrew then return end

    local cfg = Config.Models[v.hash]
    if not cfg or cfg.type ~= "storages" then return end

    -- merge dans la metadata existante
    local md = getMetadata(propId) or {}
    local acl = {}
    local n = 0
    if type(deniedList) == 'table' then
        for _, id in pairs(deniedList) do
            if type(id) == 'string' and id ~= crewId then -- on ne bloque jamais le chef
                acl[id] = true
                n = n + 1
            end
        end
    end
    md.acl = (n > 0) and acl or nil   -- aucun bloqué -> on retire le réglage (open à tous)
    setMetadata(propId, md, true)

    if DEBUG_CHEST then
        local recv = {}
        if type(deniedList) == 'table' then
            for _, id in pairs(deniedList) do recv[#recv + 1] = tostring(id) end
        end
    end

    ShowNotification(src, "Accès du coffre mis à jour.")
end)

-- ---- GATE RÉEL : hook ox_inventory pour bloquer l'ouverture d'un coffre ----
-- Indépendant du handler d'ouverture de hrs : on intercepte au niveau d'ox.
local stashToProp = {}   -- [stashId] = propId  (cache)

local function rebuildStashMap()
    stashToProp = {}
    for k, v in pairs(props) do
        local cfg = Config.Models[v.hash]
        if cfg and cfg.type == "storages" then
            stashToProp[getStashId(k, v)] = k
        end
    end
end

CreateThread(function()
    Wait(2000)
    local okReg = pcall(function()
        exports.ox_inventory:registerHook('openInventory', function(payload)
            local invId = payload and payload.inventoryId
            if not invId then return true end

            local propId = stashToProp[invId]
            if not propId then
                -- ne reconstruit le cache que pour un stash base-building (préfixe HRS)
                if type(invId) == 'string' and invId:sub(1, 3) == 'HRS' then
                    rebuildStashMap()
                    propId = stashToProp[invId]
                end
            end
            if not propId or not props[propId] then return true end  -- pas un coffre base-building connu

            local md = getMetadata(propId)
            if not md or not md.acl then return true end             -- aucun réglage -> open à tous

            local src = payload.source
            local xPlayer = GetPlayerFromId(src)
            if not xPlayer then return true end
            local identifier = GetIdentifier(xPlayer)

            if identifier == props[propId].identifier then return true end   -- propriétaire du coffre
            if crewByIdentifier[identifier] == identifier then return true end -- chef du crew

            if md.acl[identifier] then
                ShowNotification(src, "Accès à ce coffre refusé.")
                return false   -- BLOQUE l'ouverture
            end

            return true
        end, {})
    end)

    if okReg then
    else
    end
end)

-- ---- Renommer un coffre (nom custom affiché en jeu + dans le panel) ----
RegisterNetEvent('ravage-crews:setChestName')
AddEventHandler('ravage-crews:setChestName', function(payloadStr)
    local src = source
    if DEBUG_CHEST then
    end

    local payload = (type(payloadStr) == 'string') and json.decode(payloadStr) or payloadStr
    if type(payload) ~= 'table' then return end
    local propId = resolvePropId(payload.propId)
    local name = payload.name

    local xPlayer = GetPlayerFromId(src)
    if not xPlayer then return end

    if not propId or not props[propId] then return end

    local identifier = GetIdentifier(xPlayer)
    local crewBool, crewId = isPartOfCrew(identifier)
    if not crewBool then return end
    if not hasCrewPermission(identifier, nil, ACL_PERMISSION) then
        ShowNotification(src, "Accès refusé.")
        return
    end

    local v = props[propId]
    local inCrew = (v.identifier == crewId)
        or (crews[crewId] and crews[crewId].data and crews[crewId].data[v.identifier] ~= nil)
    if not inCrew then return end

    local cfg = Config.Models[v.hash]
    if not cfg or cfg.type ~= "storages" then return end

    if type(name) == 'string' then
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if #name > 32 then name = name:sub(1, 32) end
    else
        name = ""
    end

    -- Stockage via metadata (même voie fiable que l'ACL, indépendant de la
    -- colonne clientmetadata qui peut ne pas exister).
    local md = getMetadata(propId) or {}
    md.crewName = (name ~= "") and name or nil
    setMetadata(propId, md, true)

    if DEBUG_CHEST then
    end

    -- Diffusion dédiée (fiable) pour le nom flottant en jeu
    if v.coords then
        TriggerClientEvent('ravage-crews:chestNameSync', -1, propId, md.crewName or false,
            v.coords.x, v.coords.y, v.coords.z, v.identifier)
    end

    ShowNotification(src, (name ~= "") and "Coffre renommé." or "Nom du coffre retiré.")
end)

-- ---- Sync complète des noms de coffres (au démarrage / relog du client) ----
RegisterNetEvent('ravage-crews:requestAllChestNames')
AddEventHandler('ravage-crews:requestAllChestNames', function()
    local src = source
    local list = {}
    for k, v in pairs(props) do
        if v.coords then
            local cfg = Config.Models[v.hash]
            if cfg and cfg.type == "storages" then
                local md = getMetadata(k)
                if type(md) == 'table' and md.crewName and md.crewName ~= "" then
                    list[#list + 1] = { id = k, name = md.crewName, x = v.coords.x, y = v.coords.y, z = v.coords.z, identifier = v.identifier }
                end
            end
        end
    end
    if DEBUG_CHEST then
    end
    TriggerClientEvent('ravage-crews:allChestNames', src, list)
end)