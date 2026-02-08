local RSGCore = exports['rsg-core']:GetCoreObject()

local playerCooldowns = {}

local function IsPlayerMedic(source)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not Player.PlayerData.job then return false end
    
    return Player.PlayerData.job.name == 'medic'
end

local function GetPlayerCooldownRemaining(source)
    local lastCheck = playerCooldowns[source]
    if not lastCheck then return 0 end
    
    local currentTime = os.time()
    local elapsed = currentTime - lastCheck
    local remaining = Config.CheckCooldown - elapsed
    
    return remaining > 0 and remaining or 0
end

local function SetPlayerCooldown(source)
    playerCooldowns[source] = os.time()
end

RSGCore.Functions.CreateCallback('medic:checkCooldown', function(source, cb)
    local remaining = GetPlayerCooldownRemaining(source)
    cb(remaining)
end)

RegisterNetEvent('medic:setCooldown', function()
    local src = source
    if not IsPlayerMedic(src) then return end
    SetPlayerCooldown(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    playerCooldowns[src] = nil
end)

local function LogMedicActivity(source, action, details)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return end
    
    print(('[MEDIC LOG] %s (%s) - %s: %s'):format(
        Player.PlayerData.name or 'Unknown',
        Player.PlayerData.job.name or 'Unknown',
        action,
        details
    ))
end

RegisterNetEvent('medic:treatPatient', function(patientName, injuries)
    local src = source
    if not IsPlayerMedic(src) then return end
    
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if not injuries or type(injuries) ~= 'table' then
        injuries = {}
    end
    
    local reward = Config.TreatmentReward or 50
    if #injuries > 1 then
        reward = reward + (#injuries - 1) * 10
    end
    
    Player.Functions.AddMoney('cash', reward, 'medic-treatment')
    
    local injuriesList = #injuries > 0 and table.concat(injuries, ', ') or 'General checkup'
    LogMedicActivity(src, 'TREATMENT', ('Treated %s for: %s'):format(patientName, injuriesList))
    
    TriggerClientEvent('medic:treatmentSuccess', src, patientName, reward)
end)

RegisterNetEvent('medic:patientDischarged', function(patientName)
    local src = source
    if not IsPlayerMedic(src) then return end
    
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local reward = Config.ExaminationReward or 10
    Player.Functions.AddMoney('cash', reward, 'medic-examination')
    
    LogMedicActivity(src, 'DISCHARGE', ('Discharged patient: %s after examination'):format(patientName))
    
    TriggerClientEvent('medic:examinationReward', src, reward)
end)

RegisterNetEvent('medic:patientPanicked', function()
    local src = source
    if not IsPlayerMedic(src) then return end
    
    LogMedicActivity(src, 'PANIC', 'Patient panicked during examination')
end)