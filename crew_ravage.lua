-- =========================================================
--  INSTALLATION :
--   1) Place ce fichier dans le dossier de hrs_base_building.
--   2) Dans hrs_base_building/fxmanifest.lua, ajoute-le APRÈS client.lua :
--          client_scripts {
--              'client.lua',
--              'crew_ravage.lua',   -- <= ici, en dernier
--          }
--   3) Démarre 'ravage-crews' AVANT 'hrs_base_building' dans server.cfg.
--
--  Ce fichier remplace tout l'ancien flux de menu crew (qb-menu / qb-input /
--  ox_lib). Tu n'as plus besoin des remplacements exports['qb-menu']/qb-input.
--  Les anciens events 'hrs_base_building:crew:*' deviennent inutiles (inoffensifs).
--  La commande /crew ouvre désormais la page RAVAGE (override de OpenCrewMenu).
-- =========================================================

-- Events serveur réels du base building (ne pas modifier sauf si renommés)
local CREW_EVENTS = {
    invite       = 'hrs_base_building:addToCrew',       -- arg: serverId
    removeMember = 'hrs_base_building:removeFromCrew',  -- arg: identifier
    giveOwner    = 'hrs_base_building:updateCrewOwner', -- arg: identifier
    savePerms    = 'hrs_base_building:updateCrewPerms', -- args: identifier, permsArray
    rename       = 'hrs_base_building:updateCrewName',  -- arg: nouveau nom
    delete       = 'hrs_base_building:deleteCrew',
    leave        = 'hrs_base_building:leaveCrew',
    create       = 'hrs_base_building:createCrew',
    acceptInvite = 'hrs_base_building:acceptCrew',      -- arg: crewId
}

local function canPerm(permType)
    -- hasCrewPermission(myIdentifier, otherIdentifier(nil), permissionType)
    return hasCrewPermission(identifier, nil, permType) and true or false
end

local function buildCrewPayload()
    local p = { events = CREW_EVENTS, identifier = identifier, hasCrew = (myCrew ~= nil) }

    if myCrew then
        p.isOwner   = (myCrew.owner == identifier)
        p.maxMembers = Config.maxCrewMembers or nil
        p.canInvite = canPerm("canInviteMembers")
        p.canManage = canPerm("canManageMembers")
        p.canRemove = canPerm("canRemoveMembers")

        -- définitions des permissions (ordre = index utilisé côté serveur)
        local defs = {}
        for i, perm in ipairs(Config.crewPermissions or {}) do
            defs[#defs + 1] = { index = i, label = perm.label_fr or perm.label or ("Permission " .. i) }
        end
        p.permissionDefs = defs

        -- membres
        local members = {}
        for id, m in pairs(myCrew.data or {}) do
            local base  = m.permissions or {}
            local perms = {}
            for i = 1, #(Config.crewPermissions or {}) do
                perms[i] = base[i] and true or false
            end
            members[#members + 1] = {
                id          = id,
                name        = m.name or ("Membre (" .. tostring(id) .. ")"),
                isOwner     = (id == myCrew.owner),
                isMe        = (id == identifier),
                permissions = perms,
            }
        end
        table.sort(members, function(a, b)
            if a.isOwner ~= b.isOwner then return a.isOwner end
            return tostring(a.name):lower() < tostring(b.name):lower()
        end)
        p.crew = { name = myCrew.label or "CREW", ownerId = myCrew.owner, members = members }

        -- joueurs à proximité (pour inviter)
        local nearby = {}
        if p.canInvite then
            local me       = PlayerId()
            local myCoords = GetEntityCoords(PlayerPedId())
            for _, v in ipairs(GetActivePlayers()) do
                if me ~= v then
                    local c = GetEntityCoords(GetPlayerPed(v))
                    if #(myCoords - c) < 3.0 then
                        nearby[#nearby + 1] = { serverId = GetPlayerServerId(v), name = GetPlayerName(v) }
                    end
                end
            end
        end
        p.nearbyPlayers = nearby
    else
        -- pas de crew : liste des invitations
        local invites = {}
        if invitesCrew then
            for id, name in pairs(invitesCrew) do
                invites[#invites + 1] = { id = id, name = tostring(name) }
            end
        end
        table.sort(invites, function(a, b) return a.name:lower() < b.name:lower() end)
        p.invites = invites
    end

    return p
end

-- Override : /crew ouvre la page RAVAGE (la commande existante appelle ce global)
function OpenCrewMenu()
    exports['ravage-crews']:openCrewPage(buildCrewPayload())
    -- Re-synchronise l'état réel depuis le serveur (corrige les désyncs
    -- client/serveur : le serveur renvoie setCrewC -> la page se met à jour).
    TriggerServerEvent('hrs_base_building:getCrewS')
end

-- Sécurité : si la commande n'est pas déjà enregistrée ailleurs
RegisterCommand("crew", function()
    OpenCrewMenu()
end, false)

-- Rafraîchissement live de la page quand l'état du crew change.
-- Le serveur hrs_base_building broadcast 'setCrewC' / 'setInvitesC' sur TOUTES
-- les actions (create / delete / leave / remove / accept / rename / perms / owner),
-- donc on se contente de re-render la page à chaque réception : pas d'optimiste,
-- pas de désync possible.
local function refreshIfOpen()
    SetTimeout(60, function()
        if exports['ravage-crews']:isCrewPageOpen() then
            exports['ravage-crews']:updateCrewPage(buildCrewPayload())
        end
    end)
end

RegisterNetEvent('hrs_base_building:setCrewC', function() refreshIfOpen() end)
RegisterNetEvent('hrs_base_building:setInvitesC', function() refreshIfOpen() end)

-- ---------------------------------------------------------------------------
-- Réception des actions de la page : on déclenche simplement l'event serveur
-- réel. Le serveur renvoie setCrewC -> refreshIfOpen met la page à jour.
-- ---------------------------------------------------------------------------
AddEventHandler('ravage-crews:action', function(event, args)
    if type(event) ~= 'string' or event == '' then return end
    args = args or {}
    TriggerServerEvent(event, table.unpack(args))
end)

-- ---------------------------------------------------------------------------
-- Waypoint vers la base : on vise EN PRIORITÉ le totem de claim du chef
-- (propriétaire du crew), puis tout totem du crew, puis un prop du chef,
-- puis n'importe quel prop du crew. Pose ensuite le GPS dessus.
-- ---------------------------------------------------------------------------
AddEventHandler('ravage-crews:waypoint', function()
    exports['ravage-crews']:closeCrewPage()

    if not myCrew then
        if ShowNotification then ShowNotification("Vous n'êtes dans aucun crew.") end
        return
    end

    -- Récupère les props de façon fiable (export dédié, sinon global)
    local allProps
    local ok, res = pcall(function() return exports['hrs_base_building']:getBaseBuildingProps() end)
    if ok and res then allProps = res else allProps = props end

    if not allProps then
        if ShowNotification then ShowNotification("Impossible de localiser les constructions.") end
        return
    end

    local owner = myCrew.owner

    local function isClaim(hash)
        local cfg = Config.Models and Config.Models[hash]
        if not cfg then return false end
        if cfg.type == "buildFlag" or cfg.isBuildFLag then return true end
        if cfg.buildRadius or cfg.claimRadius then return true end
        if Config.claimPropType and Config.claimPropType[cfg.type] then return true end
        return false
    end

    local ownerClaim, anyClaim, ownerProp, anyCrewProp

    for _, v in pairs(allProps) do
        if v.coords then
            local inCrew = (v.identifier == owner) or (myCrew.data and myCrew.data[v.identifier] ~= nil)
            if inCrew then
                if isClaim(v.hash) then
                    if v.identifier == owner then
                        ownerClaim = v.coords
                        break
                    elseif not anyClaim then
                        anyClaim = v.coords
                    end
                end
                if v.identifier == owner and not ownerProp then ownerProp = v.coords end
                if not anyCrewProp then anyCrewProp = v.coords end
            end
        end
    end

    local coords = ownerClaim or anyClaim or ownerProp or anyCrewProp

    if not coords then
        if ShowNotification then ShowNotification("Aucun totem de claim trouvé pour votre crew.") end
        return
    end

    SetNewWaypoint(coords.x, coords.y)
    if ShowNotification then ShowNotification("Itinéraire défini vers le totem du crew.") end
end)
