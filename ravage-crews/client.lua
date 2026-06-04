-- =========================================================
--  ravage-crews (client)
--  Page de gestion du crew RAVAGE (NUI plein écran).
--  Pilotée par hrs_base_building via les exports :
--    exports['ravage-crews']:openCrewPage(payload)
--    exports['ravage-crews']:updateCrewPage(payload)  -- maj live si page ouverte
--    exports['ravage-crews']:closeCrewPage()
--    exports['ravage-crews']:isCrewPageOpen()
--  Les actions de la page déclenchent directement les events serveur
--  fournis dans payload.events (addToCrew, removeFromCrew, etc.).
-- =========================================================

local pageOpen = false

function OpenCrewPage(payload)
    if type(payload) ~= "table" then return end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "openCrew", data = payload })
    pageOpen = true
end

function UpdateCrewPage(payload)
    if not pageOpen then return end
    if type(payload) ~= "table" then return end
    SendNUIMessage({ action = "updateCrew", data = payload })
end

function CloseCrewPage()
    if pageOpen then
        SetNuiFocus(false, false)
        pageOpen = false
    end
    SendNUIMessage({ action = "closeCrew" })
end

function IsCrewPageOpen()
    return pageOpen
end

exports('openCrewPage',   OpenCrewPage)
exports('updateCrewPage', UpdateCrewPage)
exports('closeCrewPage',  CloseCrewPage)
exports('isCrewPageOpen', IsCrewPageOpen)

-- Pousse le récap des stocks vers la page
exports('setStocks', function(data, err)
    if not pageOpen then return end
    SendNUIMessage({ action = "stocks", data = data, err = err })
end)

-- Pousse la liste des coffres (accès) vers la page
exports('setChests', function(data, err)
    if not pageOpen then return end
    SendNUIMessage({ action = "chests", data = data, err = err })
end)

-- ---------------- NUI callbacks ----------------

-- Action de la page -> relayée à hrs_base_building (qui déclenche l'event
-- serveur PUIS force un rechargement de l'état du crew). La page reste ouverte.
RegisterNUICallback('crewAction', function(data, cb)
    cb('ok')
    if not data or type(data.event) ~= 'string' or data.event == '' then return end
    TriggerEvent('ravage-crews:action', data.event, data.args or {})
end)

RegisterNUICallback('closeCrew', function(_, cb)
    SetNuiFocus(false, false)
    pageOpen = false
    cb('ok')
end)

-- Demande de récap des stocks -> traité par hrs_base_building
RegisterNUICallback('crewStocks', function(_, cb)
    cb('ok')
    TriggerEvent('ravage-crews:requestStocks')
end)

-- Accès coffres
RegisterNUICallback('crewChests', function(_, cb)
    cb('ok')
    TriggerEvent('ravage-crews:requestChests')
end)

RegisterNUICallback('crewSetAcl', function(data, cb)
    cb('ok')
    if data and data.propId then
        local payload = json.encode({ propId = data.propId, denied = data.denied or {} })
        print('[ravage-crews] NUI crewSetAcl -> ' .. payload)
        TriggerServerEvent('ravage-crews:setChestAcl', payload)
    end
end)

RegisterNUICallback('crewSetChestName', function(data, cb)
    cb('ok')
    if data and data.propId ~= nil then
        TriggerServerEvent('ravage-crews:setChestName', json.encode({ propId = data.propId, name = data.name or "" }))
    end
end)

RegisterNUICallback('crewPing', function(data, cb)
    cb('ok')
    if data and data.x and data.y then
        TriggerEvent('ravage-crews:ping', data.x, data.y, data.z)
    end
end)

-- Demande de waypoint vers la base -> traité par hrs_base_building (accès aux props)
RegisterNUICallback('crewWaypoint', function(_, cb)
    cb('ok')
    TriggerEvent('ravage-crews:waypoint')
end)

-- Sécurité : fermer la page si le joueur meurt avec la page ouverte
CreateThread(function()
    while true do
        Wait(500)
        if pageOpen and IsEntityDead(PlayerPedId()) then
            CloseCrewPage()
        end
    end
end)
