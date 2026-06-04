-- =========================================================
--  crew_ravage.lua  —  Pont RAVAGE pour le crew de hrs_base_building
-- ---------------------------------------------------------
--  INSTALLATION :
--   1) Place ce fichier dans le dossier de hrs_base_building.
--   2) Dans hrs_base_building/fxmanifest.lua, ajoute-le APRÈS client.lua :
--          client_scripts {
--              'client.lua',
--              'crew_ravage.lua',   -- <= ici, en dernier
--          }
--   3) Démarre 'ravage-crews' AVANT 'hrs_base_building' dans server.cfg.
--
-- =========================================================

local STOCK_PERMISSION = "canInteract"
local ACL_PERMISSION = "canManageMembers"

local CREW_EVENTS = {
    invite       = 'hrs_base_building:addToCrew',
    removeMember = 'hrs_base_building:removeFromCrew',
    giveOwner    = 'hrs_base_building:updateCrewOwner',
    savePerms    = 'hrs_base_building:updateCrewPerms',
    rename       = 'hrs_base_building:updateCrewName',
    delete       = 'hrs_base_building:deleteCrew',
    leave        = 'hrs_base_building:leaveCrew',
    create       = 'hrs_base_building:createCrew',
    acceptInvite = 'hrs_base_building:acceptCrew',
}

local function canPerm(permType)
    return hasCrewPermission(identifier, nil, permType) and true or false
end

local function buildCrewPayload()
    local p = { events = CREW_EVENTS, identifier = identifier, hasCrew = (myCrew ~= nil) }

    if myCrew then
        p.isOwner     = (myCrew.owner == identifier)
        p.maxMembers  = Config.maxCrewMembers or nil
        p.canInvite   = canPerm("canInviteMembers")
        p.canManage   = canPerm("canManageMembers")
        p.canRemove   = canPerm("canRemoveMembers")
        p.canStocks   = canPerm(STOCK_PERMISSION)
        p.canChestAcl = canPerm(ACL_PERMISSION)

        local defs = {}
        for i, perm in ipairs(Config.crewPermissions or {}) do
            defs[#defs + 1] = { index = i, label = perm.label_fr or perm.label or ("Permission " .. i) }
        end
        p.permissionDefs = defs

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

function OpenCrewMenu()
    exports['ravage-crews']:openCrewPage(buildCrewPayload())
    TriggerServerEvent('hrs_base_building:getCrewS')
end

RegisterCommand("crew", function()
    OpenCrewMenu()
end, false)

local function refreshIfOpen()
    SetTimeout(60, function()
        if exports['ravage-crews']:isCrewPageOpen() then
            exports['ravage-crews']:updateCrewPage(buildCrewPayload())
        end
    end)
end

RegisterNetEvent('hrs_base_building:setCrewC', function() refreshIfOpen() end)
RegisterNetEvent('hrs_base_building:setInvitesC', function() refreshIfOpen() end)

AddEventHandler('ravage-crews:action', function(event, args)
    if type(event) ~= 'string' or event == '' then return end
    args = args or {}
    TriggerServerEvent(event, table.unpack(args))
end)

AddEventHandler('ravage-crews:requestStocks', function()
    TriggerServerEvent('ravage-crews:requestStocks')
end)

RegisterNetEvent('ravage-crews:stocksResult', function(data, err)
    if exports['ravage-crews']:isCrewPageOpen() then
        exports['ravage-crews']:setStocks(data, err)
    end
end)

AddEventHandler('ravage-crews:requestChests', function()
    TriggerServerEvent('ravage-crews:requestChests')
end)

RegisterNetEvent('ravage-crews:chestsResult', function(data, err)
    if exports['ravage-crews']:isCrewPageOpen() then
        exports['ravage-crews']:setChests(data, err)
    end
end)

AddEventHandler('ravage-crews:ping', function(x, y, z)
    if not (x and y) then return end
    x = x + 0.0; y = y + 0.0

    exports['ravage-crews']:closeCrewPage()
    SetNewWaypoint(x, y)
    if ShowNotification then ShowNotification("Coffre désigné (flèche pendant 5 s).") end

    CreateThread(function()
        local baseZ = z and (z + 0.0) or nil
        if not baseZ then
            local found, gz = GetGroundZFor_3dCoord(x, y, 1000.0, false)
            baseZ = (found and gz) or 0.0
        end
        local endTime = GetGameTimer() + 5000
        while GetGameTimer() < endTime do
            DrawMarker(
                2,
                x, y, baseZ + 1.4,
                0.0, 0.0, 0.0,
                180.0, 0.0, 0.0,
                0.55, 0.55, 0.55,
                200, 180, 140, 200,
                true,
                false,
                2, false, nil, nil, false
            )
            Wait(0)
        end
    end)
end)

AddEventHandler('ravage-crews:waypoint', function()
    exports['ravage-crews']:closeCrewPage()

    if not myCrew then
        if ShowNotification then ShowNotification("Vous n'êtes dans aucun crew.") end
        return
    end

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

-- ===========================================================================
--  Nom flottant au-dessus des coffres nommés
-- ===========================================================================
local chestNames = {}

local function Draw3DTextChest(x, y, z, text)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    local cam = GetGameplayCamCoords()
    local dist = #(cam - vector3(x, y, z))
    local fov = (1.0 / GetGameplayCamFov()) * 100.0
    local scale = (1.0 / dist) * 2.0 * fov * 0.30

    SetTextScale(0.0, scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(200, 180, 140, 220)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 180)
    SetTextDropShadow()
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry("STRING")
    AddTextComponentString("[ " .. text .. " ]")
    DrawText(sx, sy)
end

RegisterNetEvent('ravage-crews:chestNameSync', function(propId, name, x, y, z, owner)
    propId = tonumber(propId)
    if not propId then return end
    if name and name ~= false and name ~= "" then
        chestNames[propId] = { coords = vector3(x + 0.0, y + 0.0, z + 0.0), name = name, identifier = owner }
    else
        chestNames[propId] = nil
    end
end)

RegisterNetEvent('ravage-crews:allChestNames', function(list)
    chestNames = {}
    if type(list) == 'table' then
        for _, c in ipairs(list) do
            chestNames[c.id] = { coords = vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0), name = c.name, identifier = c.identifier }
        end
    end
end)

CreateThread(function()
    Wait(4000)
    TriggerServerEvent('ravage-crews:requestAllChestNames')
end)

RegisterNetEvent('hrs_base_building:juststarted', function()
    SetTimeout(3000, function() TriggerServerEvent('ravage-crews:requestAllChestNames') end)
end)

CreateThread(function()
    while true do
        local wait = 700
        if next(chestNames) and identifier then
            local pc = GetEntityCoords(PlayerPedId())
            local drew = false
            for propId, c in pairs(chestNames) do
                if #(pc - c.coords) < 9.0 and hasPermissionVeh(identifier, c.identifier) then
                    Draw3DTextChest(c.coords.x, c.coords.y, c.coords.z + 0.85, c.name)
                    drew = true
                end
            end
            if drew then wait = 0 end
        end
        Wait(wait)
    end
end)
