local RSGCore = exports['rsg-core']:GetCoreObject()

local isExaminingNPC = false
local currentTarget = nil
local examinedNPCs = {}
local assistedNPC = nil
local isPlayingAnimation = false

local assistPromptGroup = GetRandomIntInRange(0, 0xffffff)
local stopAssistPrompt = nil
local patientMenuPrompt = nil
local promptsCreated = false

local HOSPITAL_LOCATION = Config.HospitalLocation

-- Debug function
local function DebugPrint(msg)
    if Config.Debug then
        print('[MEDIC DEBUG] ' .. msg)
    end
end

-- Animation Functions
local function LoadAnimDict(dict)
    if not DoesAnimDictExist(dict) then
        DebugPrint('Animation dict does not exist: ' .. dict)
        return false
    end
    
    if HasAnimDictLoaded(dict) then
        return true
    end
    
    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    
    if HasAnimDictLoaded(dict) then
        DebugPrint('Loaded animation dict: ' .. dict)
        return true
    else
        DebugPrint('Failed to load animation dict: ' .. dict)
        return false
    end
end

-- Complete NPC reset function
local function ResetNPCState(npc)
    if not DoesEntityExist(npc) then return end
    
    DebugPrint('Resetting NPC state completely...')
    
    -- Stop all tasks immediately
    ClearPedTasks(npc)
    ClearPedTasksImmediately(npc)
    ClearPedSecondaryTask(npc)
    
    -- Unfreeze first
    FreezeEntityPosition(npc, false)
    
    -- Reset all movement and AI flags
    SetPedFleeAttributes(npc, 0, false)
    SetPedCombatAttributes(npc, 17, true)
    SetPedDesiredMoveBlendRatio(npc, 0.0)
    SetPedMoveRateOverride(npc, 1.0)
    
    -- Block events so NPC doesn't react to world
    SetBlockingOfNonTemporaryEvents(npc, true)
    
    -- Make invincible
    SetEntityInvincible(npc, true)
    
    -- Disable ragdoll
    SetPedCanRagdoll(npc, false)
    
    -- Allow gesture anims
    SetPedCanPlayGestureAnims(npc, true)
    
    -- Reset config flags
    SetPedConfigFlag(npc, 118, true)
    SetPedConfigFlag(npc, 208, true)
    SetPedConfigFlag(npc, 225, true)
    SetPedConfigFlag(npc, 421, true)
    
    -- Clear all decorators
    DecorSetBool(npc, "IsFollowing", false)
    DecorSetBool(npc, "IsPanicking", false)
    
    -- Small wait to ensure everything is cleared
    Wait(100)
    
    DebugPrint('NPC state reset complete')
end

local function ClearNPCAnimations(npc)
    if not DoesEntityExist(npc) then return end
    
    ClearPedTasks(npc)
    ClearPedTasksImmediately(npc)
    ClearPedSecondaryTask(npc)
    
    -- Also block events
    SetBlockingOfNonTemporaryEvents(npc, true)
    
    Wait(100)
    DebugPrint('Cleared all animations on NPC')
end

local function PlayPatientAnimation(npc, animKey)
    if not DoesEntityExist(npc) then return false end
    
    local animData = Config.PatientAnimations[animKey]
    if not animData then
        DebugPrint('Animation not found: ' .. tostring(animKey))
        return false
    end
    
    if not LoadAnimDict(animData.dict) then
        return false
    end
    
    local flag = animData.flag or 31
    
    -- Clear existing animations first
    ClearPedTasks(npc)
    ClearPedTasksImmediately(npc)
    Wait(100)
    
    TaskPlayAnim(npc, animData.dict, animData.anim, 8.0, -8.0, -1, flag, 0, false, false, false)
    
    DebugPrint('Playing animation: ' .. animData.label .. ' on NPC')
    return true
end

local function StopPatientAnimation(npc)
    if not DoesEntityExist(npc) then return end
    ClearNPCAnimations(npc)
end

local function PlayMedicAnimation(animKey, callback)
    local playerPed = PlayerPedId()
    local animData = Config.MedicAnimations[animKey]
    
    if not animData then
        DebugPrint('Medic animation not found: ' .. tostring(animKey))
        if callback then callback() end
        return false
    end
    
    if not LoadAnimDict(animData.dict) then
        if callback then callback() end
        return false
    end
    
    isPlayingAnimation = true
    
    local flag = animData.flag or 1
    local duration = animData.duration or 3000
    
    TaskPlayAnim(playerPed, animData.dict, animData.anim, 8.0, -8.0, -1, flag, 0, false, false, false)
    
    DebugPrint('Playing medic animation: ' .. animKey)
    
    -- Wait for animation duration then clear
    CreateThread(function()
        Wait(duration)
        ClearPedTasks(playerPed)
        isPlayingAnimation = false
        if callback then callback() end
    end)
    
    return true
end

local function StopMedicAnimation()
    local playerPed = PlayerPedId()
    ClearPedTasks(playerPed)
    isPlayingAnimation = false
end

local function GetAnimationForInjury(injuryName)
    for _, injury in ipairs(Config.InjuryTypes) do
        if injury.name == injuryName then
            return injury.animation
        end
    end
    return 'sick'
end

local function GetRandomPatientAnimation()
    local animKeys = {}
    for key, _ in pairs(Config.PatientAnimations) do
        if not string.find(key, 'sitting') and key ~= 'standing_dazed' then
            table.insert(animKeys, key)
        end
    end
    return animKeys[math.random(#animKeys)]
end

local function GetPriorityAnimation(injuries)
    local priorityOrder = {
        'sleeping',
        'injured_neck',
        'injured_back',
        'injured_head',
        'injured_chest',
        'vomiting',
        'injured_shoulder',
        'injured_arm',
        'injured_hip',
        'sick'
    }
    
    if not injuries or #injuries == 0 then
        return GetRandomPatientAnimation()
    end
    
    local injuryAnims = {}
    for _, injuryName in ipairs(injuries) do
        local anim = GetAnimationForInjury(injuryName)
        if anim then
            injuryAnims[anim] = true
        end
    end
    
    for _, animKey in ipairs(priorityOrder) do
        if injuryAnims[animKey] then
            return animKey
        end
    end
    
    return 'sick'
end

-- Sitting Scenarios for RedM
local SittingScenarios = {
    'WORLD_HUMAN_SIT_GROUND',
    'WORLD_HUMAN_SIT_GROUND_TIRED',
    'WORLD_HUMAN_SIT_GROUND_STARE',
}

local SittingScenariosDrunk = {
    'WORLD_HUMAN_SIT_GROUND_DRUNK',
    'WORLD_HUMAN_SIT_GROUND_TIRED',
}

local function GetSittingScenario(injuries)
    if injuries and #injuries > 0 then
        for _, injuryName in ipairs(injuries) do
            if injuryName == 'Alcohol Poisoning' or 
               injuryName == 'Food Poisoning' or 
               injuryName == 'Concussion' or 
               injuryName == 'Head Trauma' or
               injuryName == 'Dehydration' then
                return SittingScenariosDrunk[math.random(#SittingScenariosDrunk)]
            end
        end
    end
    
    return SittingScenarios[math.random(#SittingScenarios)]
end

local function MakePatientSitWithScenario(npc, injuries)
    if not DoesEntityExist(npc) then return false end
    
    DebugPrint('Making patient sit with scenario...')
    
    -- Complete reset of NPC state
    ResetNPCState(npc)
    
    -- Additional wait to ensure clean state
    Wait(200)
    
    -- Place on ground properly
    PlaceEntityOnGroundProperly(npc)
    Wait(100)
    
    -- Get appropriate sitting scenario
    local scenario = GetSittingScenario(injuries)
    DebugPrint('Using scenario: ' .. scenario)
    
    -- Start the sitting scenario
    TaskStartScenarioInPlace(npc, GetHashKey(scenario), -1, true, false, false, false)
    
    -- Wait for scenario to begin
    Wait(500)
    
    DecorSetBool(npc, "IsStabilized", true)
    DecorSetBool(npc, "IsSitting", true)
    
    DebugPrint('Patient should now be sitting with scenario')
    return true
end

local function MakePatientSitDirect(npc, injuries)
    if not DoesEntityExist(npc) then return false end
    
    DebugPrint('Making patient sit with direct animation...')
    
    -- Complete reset of NPC state
    ResetNPCState(npc)
    
    -- Additional wait
    Wait(200)
    
    -- Place on ground properly
    PlaceEntityOnGroundProperly(npc)
    Wait(200)
    
    -- Sitting animation dictionaries that work in RedM
    local sitAnims = {
        {dict = 'amb_rest@world_human_sit_ground@base@male_a@base', anim = 'base', flag = 1},
        {dict = 'amb_rest@world_human_sit_ground@generic@male_a@base', anim = 'base', flag = 1},
        {dict = 'amb_rest_drunk@base_sitting_ground@wasted@male_a@idle_a', anim = 'idle_a', flag = 1},
    }
    
    -- Choose animation based on injury
    local animIndex = 1
    if injuries and #injuries > 0 then
        for _, injuryName in ipairs(injuries) do
            if injuryName == 'Alcohol Poisoning' or injuryName == 'Concussion' then
                animIndex = 3
                break
            end
        end
    end
    
    local sitData = sitAnims[animIndex]
    
    if LoadAnimDict(sitData.dict) then
        TaskPlayAnim(npc, sitData.dict, sitData.anim, 8.0, -8.0, -1, sitData.flag, 0, false, false, false)
        DebugPrint('Playing sitting animation: ' .. sitData.dict)
        
        -- Wait for animation to settle
        Wait(500)
        
        DecorSetBool(npc, "IsStabilized", true)
        DecorSetBool(npc, "IsSitting", true)
        
        return true
    else
        DebugPrint('Failed to load sitting animation dict')
        return false
    end
end

local function CreateAssistPrompts()
    if promptsCreated then return end
    
    CreateThread(function()
        local str = "Stop Assisting"
        stopAssistPrompt = PromptRegisterBegin()
        PromptSetControlAction(stopAssistPrompt, 0x760A9C6F)
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(stopAssistPrompt, str)
        PromptSetEnabled(stopAssistPrompt, true)
        PromptSetVisible(stopAssistPrompt, true)
        PromptSetHoldMode(stopAssistPrompt, true)
        PromptSetGroup(stopAssistPrompt, assistPromptGroup)
        PromptRegisterEnd(stopAssistPrompt)
        DebugPrint('Stop Assist prompt created')
    end)
    
    CreateThread(function()
        local str = "Patient Options"
        patientMenuPrompt = PromptRegisterBegin()
        PromptSetControlAction(patientMenuPrompt, 0xCEFD9220)
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(patientMenuPrompt, str)
        PromptSetEnabled(patientMenuPrompt, true)
        PromptSetVisible(patientMenuPrompt, true)
        PromptSetHoldMode(patientMenuPrompt, true)
        PromptSetGroup(patientMenuPrompt, assistPromptGroup)
        PromptRegisterEnd(patientMenuPrompt)
        DebugPrint('Patient Menu prompt created')
    end)
    
    promptsCreated = true
    DebugPrint('Assist prompts created')
end

local function IsMedic()
    local PlayerData = RSGCore.Functions.GetPlayerData()
    if not PlayerData or not PlayerData.job then
        DebugPrint('IsMedic: No PlayerData or job')
        return false
    end
    
    local jobName = PlayerData.job.name
    DebugPrint('IsMedic check - Job: ' .. tostring(jobName))
    
    return jobName == 'medic'
end

local function Notify(title, message, type)
    local icon = 'warning'
    if type == 'success' then
        icon = 'awards_set_a_009'
    elseif type == 'error' then
        icon = 'warning'
    elseif type == 'info' then
        icon = 'awards_set_c_001'
    end
    
    TriggerEvent('bln_notify:send', {
        title = title,
        description = message,
        icon = icon,
        duration = 5000,
        placement = 'top-right'
    })
end

local function FormatTime(seconds)
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60
    if minutes > 0 then
        return string.format('%d min %d sec', minutes, secs)
    else
        return string.format('%d sec', secs)
    end
end

local function GetRandomPatientName()
    return Config.FirstNames[math.random(#Config.FirstNames)] .. ' ' .. Config.LastNames[math.random(#Config.LastNames)]
end

local function GenerateDocumentsStatus()
    local hasDocuments = math.random(1, 100) <= Config.HasDocumentsChance
    local documents = {}
    if hasDocuments then
        for _, docType in pairs(Config.MedicalDocuments) do
            documents[docType] = math.random(1, 100) <= Config.ValidDocumentChance
        end
    end
    return documents, hasDocuments
end

local function GenerateInjuryStatus()
    local hasInjury = math.random(1, 100) <= Config.HasInjuryChance
    local injuries = {}
    local injuryData = {}
    if hasInjury then
        local injuryCount = math.random(1, Config.MaxInjuries)
        local usedInjuries = {}
        for i = 1, injuryCount do
            local attempts = 0
            local injury
            repeat
                injury = Config.InjuryTypes[math.random(#Config.InjuryTypes)]
                attempts = attempts + 1
            until not usedInjuries[injury.name] or attempts > 10
            
            if not usedInjuries[injury.name] then
                usedInjuries[injury.name] = true
                table.insert(injuries, injury.name)
                table.insert(injuryData, {
                    name = injury.name,
                    animation = injury.animation
                })
            end
        end
    end
    return injuries, hasInjury, injuryData
end

local function GetStoredNPCData(npc)
    for _, npcData in pairs(examinedNPCs) do
        if npcData.entity == npc then
            return npcData
        end
    end
    return nil
end

local function IsPatientNPC(entity)
    return GetStoredNPCData(entity) ~= nil
end

local function IsNPCAssisted(npc)
    return assistedNPC == npc and DoesEntityExist(npc)
end

local function IsCurrentlyAssisting()
    return assistedNPC ~= nil and DoesEntityExist(assistedNPC)
end

local function StabilizePatient(npc, injuries)
    if not DoesEntityExist(npc) then return end
    
    -- Complete reset first
    ResetNPCState(npc)
    
    -- Get appropriate animation based on injuries
    local animKey = GetPriorityAnimation(injuries)
    
    -- If sleeping/unconscious animation, we need special handling
    if animKey == 'sleeping' then
        local coords = GetEntityCoords(npc)
        SetEntityCoords(npc, coords.x, coords.y, coords.z - 0.5, false, false, false, false)
    end
    
    FreezeEntityPosition(npc, true)
    
    -- Play the injury animation
    Wait(200)
    PlayPatientAnimation(npc, animKey)
    
    DecorSetBool(npc, "IsStabilized", true)
    DecorSetBool(npc, "IsSitting", false)
    DecorSetInt(npc, "CurrentAnimation", GetHashKey(animKey))
    
    DebugPrint('Patient stabilized with animation: ' .. animKey)
end

-- New function for standing with dazed animation (no injury animation)
local function MakePatientStandDazed(npc)
    if not DoesEntityExist(npc) then return end
    
    DebugPrint('Making patient stand with dazed animation...')
    
    -- Complete reset first
    ResetNPCState(npc)
    
    -- Keep frozen during setup
    FreezeEntityPosition(npc, true)
    Wait(200)
    
    -- Place on ground properly
    PlaceEntityOnGroundProperly(npc)
    Wait(100)
    
    -- Unfreeze for animation
    FreezeEntityPosition(npc, false)
    
    -- Play the dazed/drunk standing animation
    Wait(100)
    PlayPatientAnimation(npc, 'standing_dazed')
    
    Wait(300)
    FreezeEntityPosition(npc, true)
    
    DecorSetBool(npc, "IsStabilized", true)
    DecorSetBool(npc, "IsSitting", false)
    DecorSetBool(npc, "IsStanding", true)
    
    DebugPrint('Patient now standing with dazed animation')
end

local function StabilizePatientStanding(npc, injuries)
    if not DoesEntityExist(npc) then return end
    
    -- Complete reset first
    ResetNPCState(npc)
    
    FreezeEntityPosition(npc, false)
    TaskStandStill(npc, -1)
    Wait(300)
    FreezeEntityPosition(npc, true)
    
    -- Get appropriate animation based on injuries (excluding sleeping for standing)
    local animKey = GetPriorityAnimation(injuries)
    if animKey == 'sleeping' then
        animKey = 'sick'
    end
    
    Wait(200)
    PlayPatientAnimation(npc, animKey)
    
    DecorSetBool(npc, "IsStabilized", true)
    DecorSetBool(npc, "IsSitting", false)
end

local function SoftStabilizePatient(npc)
    if not DoesEntityExist(npc) then return end
    
    StopPatientAnimation(npc)
    
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetEntityInvincible(npc, true)
    SetPedCanRagdoll(npc, false)
    SetPedCanPlayGestureAnims(npc, false)
    FreezeEntityPosition(npc, false)
    
    DecorSetBool(npc, "IsStabilized", true)
    DecorSetBool(npc, "IsSitting", false)
end

local function ReleasePatient(npc)
    if not DoesEntityExist(npc) then return end
    
    StopPatientAnimation(npc)
    ClearNPCAnimations(npc)
    FreezeEntityPosition(npc, false)
    
    -- Re-enable normal behavior for release
    SetBlockingOfNonTemporaryEvents(npc, false)
    SetEntityInvincible(npc, false)
    SetPedCanRagdoll(npc, true)
    SetPedCanPlayGestureAnims(npc, true)
    
    -- Reset config flags for release
    SetPedConfigFlag(npc, 118, false)
    SetPedConfigFlag(npc, 225, false)
    
    DecorSetBool(npc, "IsStabilized", false)
    DecorSetBool(npc, "IsSitting", false)
    DecorSetBool(npc, "IsStanding", false)
end

local ShowMedicMenu
local ShowAssistMenu

local function StopAssistingPatient()
    if not assistedNPC or not DoesEntityExist(assistedNPC) then 
        assistedNPC = nil
        return 
    end
    
    local npc = assistedNPC
    local npcData = GetStoredNPCData(npc)
    
    DetachEntity(npc, true, false)
    PlaceEntityOnGroundProperly(npc)
    
    Wait(100)
    
    -- Make patient stand with dazed animation when stopped assisting
    MakePatientStandDazed(npc)
    
    DecorSetBool(npc, "IsAssisted", false)
    assistedNPC = nil
    
    Notify('Medic', 'Patient is no longer being assisted.', 'info')
end

local function StartAssistingPatient(npc)
    if not DoesEntityExist(npc) then return end
    
    if assistedNPC and DoesEntityExist(assistedNPC) then
        StopAssistingPatient()
    end
    
    local playerPed = PlayerPedId()
    
    -- Complete reset
    ResetNPCState(npc)
    
    FreezeEntityPosition(npc, false)
    
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetEntityInvincible(npc, true)
    SetPedCanRagdoll(npc, false)
    
    SetEntityCoords(npc, GetOffsetFromEntityInWorldCoords(playerPed, 0.5, 0.3, 0.0))
    
    AttachEntityToEntity(npc, playerPed, 11816, 0.5, 0.3, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    
    assistedNPC = npc
    DecorSetBool(npc, "IsAssisted", true)
    DecorSetBool(npc, "IsFollowing", false)
    DecorSetBool(npc, "IsSitting", false)
    DecorSetBool(npc, "IsStanding", false)
    
    Notify('Medic', 'You are now assisting the patient.', 'success')
end

local function ToggleAssistPatient(npc)
    if not DoesEntityExist(npc) then return end
    
    local isAssisted = IsNPCAssisted(npc)
    
    if isAssisted then
        StopAssistingPatient()
    else
        StartAssistingPatient(npc)
    end
end

local function TransportToHospital(npc, npcData)
    if not DoesEntityExist(npc) then return end
    
    if IsNPCAssisted(npc) then
        DetachEntity(npc, true, false)
        assistedNPC = nil
    end
    
    -- Complete reset
    ResetNPCState(npc)
    
    DoScreenFadeOut(500)
    Wait(500)
    
    FreezeEntityPosition(npc, false)
    SetEntityCollision(npc, true, true)
    SetEntityAsMissionEntity(npc, true, true)
    
    SetEntityCoordsNoOffset(npc, HOSPITAL_LOCATION.x, HOSPITAL_LOCATION.y, HOSPITAL_LOCATION.z, false, false, false)
    Wait(100)
    SetEntityHeading(npc, HOSPITAL_LOCATION.w)
    Wait(100)
    PlaceEntityOnGroundProperly(npc)
    Wait(200)
    
    -- Play sleeping/resting animation at hospital
    PlayPatientAnimation(npc, 'sleeping')
    FreezeEntityPosition(npc, true)
    
    DoScreenFadeIn(500)
    
    if Config.DeleteTreatedNPCsAfter then
        SetTimeout(Config.DeleteTreatedNPCsAfter * 1000, function()
            if DoesEntityExist(npc) then
                SetEntityAsMissionEntity(npc, true, true)
                DeletePed(npc)
            end
        end)
    end
    
    DebugPrint('Transported ' .. npcData.name .. ' to hospital at ' .. tostring(HOSPITAL_LOCATION))
end

local function MakePatientPanic(npc)
    if not DoesEntityExist(npc) then return end
    
    ReleasePatient(npc)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    DecorSetBool(npc, "IsPanicking", true)
    ClearPedTasks(npc)
    SetPedFleeAttributes(npc, 2, true)
    SetPedDesiredMoveBlendRatio(npc, 3.0)
    SetPedMoveRateOverride(npc, 3.0)
    TaskFleeCoord(npc, playerCoords.x, playerCoords.y, playerCoords.z, 3, -1)
    
    Notify('Medic', 'The patient is panicking and running away!', 'error')
end

local function MakePatientFollow(npc)
    if not DoesEntityExist(npc) then return end
    
    -- Reset but allow movement
    ClearPedTasks(npc)
    ClearPedTasksImmediately(npc)
    ClearPedSecondaryTask(npc)
    
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetEntityInvincible(npc, true)
    SetPedCanRagdoll(npc, false)
    SetPedCanPlayGestureAnims(npc, false)
    FreezeEntityPosition(npc, false)
    
    Wait(100)
    
    local playerPed = PlayerPedId()
    TaskFollowToOffsetOfEntity(npc, playerPed, -1.0, -1.0, 0.0, 1.0, -1, 1.5, true)
    
    DecorSetBool(npc, "IsFollowing", true)
    DecorSetBool(npc, "IsSitting", false)
    DecorSetBool(npc, "IsStanding", false)
    Notify('Medic', 'The patient is following you.', 'success')
end

local function MakePatientRest(npc)
    if not DoesEntityExist(npc) then return end
    
    DebugPrint('MakePatientRest called')
    
    -- Stop assisting if currently assisted
    if IsNPCAssisted(npc) then
        StopAssistingPatient()
        Wait(300)
    end
    
    local npcData = GetStoredNPCData(npc)
    local injuries = npcData and npcData.injuries or nil
    
    -- First, freeze the NPC in place immediately to prevent wandering
    FreezeEntityPosition(npc, true)
    
    -- Complete reset
    ResetNPCState(npc)
    
    -- Keep frozen during setup
    FreezeEntityPosition(npc, true)
    Wait(300)
    
    -- Now unfreeze and try scenario
    FreezeEntityPosition(npc, false)
    
    -- Try scenario method
    local success = MakePatientSitWithScenario(npc, injuries)
    
    -- Wait a moment to see if scenario works
    Wait(1500)
    
    -- Check if ped is doing something
    if IsPedStill(npc) and not success then
        DebugPrint('Scenario may have failed, trying direct animation')
        -- Try direct animation method as fallback
        MakePatientSitDirect(npc, injuries)
    else
        DebugPrint('Scenario appears to be working')
    end
    
    DecorSetBool(npc, "IsFollowing", false)
    DecorSetBool(npc, "IsStanding", false)
    Notify('Medic', 'The patient is resting.', 'success')
end

local function MakePatientLayDown(npc)
    if not DoesEntityExist(npc) then return end
    
    if IsNPCAssisted(npc) then
        StopAssistingPatient()
        Wait(200)
    end
    
    -- Complete reset first
    ResetNPCState(npc)
    
    -- Keep frozen during setup
    FreezeEntityPosition(npc, true)
    Wait(200)
    
    -- Unfreeze for animation
    FreezeEntityPosition(npc, false)
    
    Wait(100)
    PlayPatientAnimation(npc, 'sleeping')
    
    Wait(500)
    FreezeEntityPosition(npc, true)
    
    DecorSetBool(npc, "IsFollowing", false)
    DecorSetBool(npc, "IsSitting", false)
    DecorSetBool(npc, "IsStanding", false)
    Notify('Medic', 'The patient is laying down.', 'success')
end

local function AdministerFirstAid(npc, npcData, callback)
    if not DoesEntityExist(npc) then 
        if callback then callback() end
        return 
    end
    
    if isPlayingAnimation then
        Notify('Medic', 'Already performing an action...', 'error')
        if callback then callback() end
        return
    end
    
    local playerPed = PlayerPedId()
    
    -- Face the patient
    local npcCoords = GetEntityCoords(npc)
    local playerCoords = GetEntityCoords(playerPed)
    local heading = GetHeadingFromVector_2d(npcCoords.x - playerCoords.x, npcCoords.y - playerCoords.y)
    SetEntityHeading(playerPed, heading)
    
    Wait(200)
    
    Notify('Medic', 'Administering first aid to ' .. npcData.name .. '...', 'info')
    
    -- Play the bandaging animation on the medic
    PlayMedicAnimation('first_aid', function()
        Notify('Medic', 'First aid administered successfully.', 'success')
        
        -- Mark patient as treated
        if npcData then
            npcData.treatedWithFirstAid = true
        end
        
        if callback then callback() end
    end)
end

local function IsValidHumanNPC(entity)
    if not DoesEntityExist(entity) then return false end
    if IsPedAPlayer(entity) then return false end
    if IsEntityDead(entity) then return false end
    if not IsPedHuman(entity) then return false end
    if IsPedInAnyVehicle(entity, false) then return false end
    return true
end

local function ExaminePatient(npc)
    if not DoesEntityExist(npc) or not IsValidHumanNPC(npc) then
        Notify('Medic', 'Invalid target!', 'error')
        return
    end
    
    if not IsMedic() then
        Notify('Medic', 'Only medics can perform examinations', 'error')
        return
    end
    
    local existingData = GetStoredNPCData(npc)
    if existingData then
        ShowMedicMenu(npc)
        return
    end
    
    RSGCore.Functions.TriggerCallback('medic:checkCooldown', function(remaining)
        if remaining > 0 then
            Notify('Medic', 'You must wait ' .. FormatTime(remaining) .. ' before examining another patient.', 'error')
            return
        end
        
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        
        Notify('Medic', 'Approaching patient...', 'info')
        
        ClearPedTasksImmediately(npc)
        TaskGoToEntity(npc, playerPed, -1, 1.5, 1.0, 0, 0)
        
        CreateThread(function()
            local attempts = 0
            while DoesEntityExist(npc) and attempts < 50 do
                Wait(200)
                local dist = #(GetEntityCoords(npc) - playerCoords)
                if dist <= 2.5 then break end
                attempts = attempts + 1
            end
            
            TriggerServerEvent('medic:setCooldown')
            
            if math.random(1, 100) <= Config.PanicChance then
                local npcData = {
                    entity = npc,
                    name = GetRandomPatientName(),
                    isPanicking = true
                }
                table.insert(examinedNPCs, npcData)
                MakePatientPanic(npc)
                TriggerServerEvent('medic:patientPanicked')
                return
            end
            
            local patientName = GetRandomPatientName()
            local documents, hasDocuments = GenerateDocumentsStatus()
            local injuries, hasInjuries, injuryData = GenerateInjuryStatus()
            
            local npcData = {
                entity = npc,
                name = patientName,
                documents = documents,
                hasDocuments = hasDocuments,
                injuries = injuries,
                hasInjuries = hasInjuries,
                injuryData = injuryData,
                treatedWithFirstAid = false
            }
            
            table.insert(examinedNPCs, npcData)
            
            -- Stabilize with appropriate injury animation
            StabilizePatient(npc, injuries)
            
            Notify('Medic', 'Patient stabilized. Beginning examination...', 'info')
            Wait(1500)
            
            ShowMedicMenu(npc)
        end)
    end)
end

ShowMedicMenu = function(npc)
    if not DoesEntityExist(npc) then return end
    
    local npcData = GetStoredNPCData(npc)
    if not npcData then return end
    
    currentTarget = npc
    
    local isAssisted = IsNPCAssisted(npc)
    
    local assistText = isAssisted and 'Stop Assisting' or 'Assist Patient'
    local assistIcon = isAssisted and 'fas fa-user-minus' or 'fas fa-hands-helping'
    
    local firstAidDesc = 'Provide basic medical treatment'
    if npcData.treatedWithFirstAid then
        firstAidDesc = 'Patient already received first aid'
    end
    
    lib.registerContext({
        id = 'medic_menu',
        title = npcData.name,
        icon = 'fas fa-user-injured',
        options = {
            {
                title = 'Patient Information',
                icon = 'fas fa-id-card',
                description = 'Name: ' .. npcData.name,
                onSelect = function()
                    Notify('Patient Info', 'Patient: ' .. npcData.name, 'info')
                    ShowMedicMenu(npc)
                end
            },
            {
                title = 'Check Medical Records',
                icon = 'fas fa-notes-medical',
                description = 'Review medical documentation',
                onSelect = function()
                    local message = ""
                    if not npcData.hasDocuments then
                        message = "No medical records found on patient"
                    else
                        for docType, isValid in pairs(npcData.documents) do
                            local status = isValid and 'Present' or 'Missing'
                            message = message .. docType .. ": " .. status .. "\n"
                        end
                    end
                    Notify('Medical Records', message, 'info')
                    ShowMedicMenu(npc)
                end
            },
            {
                title = 'Diagnose Injuries',
                icon = 'fas fa-stethoscope',
                description = 'Examine patient for injuries',
                onSelect = function()
                    if not npcData.hasInjuries or #npcData.injuries == 0 then
                        Notify('Diagnosis', 'No significant injuries detected', 'success')
                    else
                        local injuriesList = table.concat(npcData.injuries, ', ')
                        Notify('Diagnosis', 'Injuries found: ' .. injuriesList, 'error')
                    end
                    ShowMedicMenu(npc)
                end
            },
            {
                title = 'Administer First Aid',
                icon = 'fas fa-first-aid',
                description = firstAidDesc,
                onSelect = function()
                    if npcData.treatedWithFirstAid then
                        Notify('Medic', 'Patient has already received first aid.', 'info')
                        ShowMedicMenu(npc)
                        return
                    end
                    
                    AdministerFirstAid(npc, npcData, function()
                        ShowMedicMenu(npc)
                    end)
                end
            },
            {
                title = assistText,
                icon = assistIcon,
                description = isAssisted and 'Release patient from assistance' or 'Help patient walk',
                onSelect = function()
                    ToggleAssistPatient(npc)
                    Wait(300)
                    if not IsCurrentlyAssisting() then
                        ShowMedicMenu(npc)
                    end
                end
            },
            {
                title = 'Have Patient Lay Down',
                icon = 'fas fa-procedures',
                description = 'Instruct patient to lay down',
                onSelect = function()
					FreezeEntityPosition(npc, true)
                    MakePatientLayDown(npc)
                    Wait(500)
                    ShowMedicMenu(npc)
                end
            },
            {
                title = 'Make patient get up and leave',
                icon = 'fas fa-male',
                description = 'Make patient get up and leave',
                onSelect = function()
                    if IsNPCAssisted(npc) then
                        StopAssistingPatient()
                        Wait(200)
                    end
                    
                    -- Use the new dazed standing animation (not injury animation)
                    FreezeEntityPosition(npc, true)
					Wait(500)
					FreezeEntityPosition(npc, false)
					TaskWanderStandard(npc, 10.0, 10)
                    
                    Notify('Medic', 'The patient is Happy.', 'success')
                    Wait(500)
                    ShowMedicMenu(npc)
                end
            },
            {
                title = 'Transport to Hospital',
                icon = 'fas fa-hospital',
                description = 'Take patient for further treatment',
                onSelect = function()
                    Notify('Medic', 'Transporting ' .. npcData.name .. ' to hospital...', 'info')
                    
                    TransportToHospital(npc, npcData)
                    
                    for i, data in ipairs(examinedNPCs) do
                        if data.entity == npc then
                            table.remove(examinedNPCs, i)
                            break
                        end
                    end
                    
                    Notify('Medic', npcData.name .. ' has been admitted to the hospital!', 'success')
                    TriggerServerEvent('medic:treatPatient', npcData.name, npcData.injuries or {})
                end
            },
            {
                title = 'recieve payment',
                icon = 'fas fa-door-open',
                description = 'Release patient after treatment for cash',
                onSelect = function()
                    if IsNPCAssisted(npc) then
                        StopAssistingPatient()
                    end
                    
                    ReleasePatient(npc)
                    if Config.DeleteNPCOnRelease then
                        DeletePed(npc)
                    else
                        TaskWanderStandard(npc, 10.0, 10)
                    end
                    for i, data in ipairs(examinedNPCs) do
                        if data.entity == npc then
                            table.remove(examinedNPCs, i)
                            break
                        end
                    end
                    Notify('Medic', npcData.name .. ' has been discharged.', 'success')
                    TriggerServerEvent('medic:patientDischarged', npcData.name)
                end
            }
        }
    })
    
    lib.showContext('medic_menu')
end

ShowAssistMenu = function()
    if not assistedNPC or not DoesEntityExist(assistedNPC) then
        Notify('Medic', 'No patient currently being assisted.', 'error')
        return
    end
    
    local npc = assistedNPC
    local npcData = GetStoredNPCData(npc)
    
    if not npcData then return end
    
    local firstAidDesc = 'Provide basic treatment'
    if npcData.treatedWithFirstAid then
        firstAidDesc = 'Patient already received first aid'
    end
    
    lib.registerContext({
        id = 'assist_menu',
        title = 'Assisting: ' .. npcData.name,
        icon = 'fas fa-hand-holding-medical',
        options = {
            {
                title = 'Stop Assisting',
                icon = 'fas fa-user-minus',
                description = 'Release patient from assistance',
                onSelect = function()
                    StopAssistingPatient()
                end
            },
            {
                title = 'Transport to Hospital',
                icon = 'fas fa-hospital',
                description = 'Take patient for treatment',
                onSelect = function()
                    Notify('Medic', 'Transporting ' .. npcData.name .. ' to hospital...', 'info')
                    
                    TransportToHospital(npc, npcData)
                    
                    for i, data in ipairs(examinedNPCs) do
                        if data.entity == npc then
                            table.remove(examinedNPCs, i)
                            break
                        end
                    end
                    
                    Notify('Medic', npcData.name .. ' has been admitted to the hospital!', 'success')
                    TriggerServerEvent('medic:treatPatient', npcData.name, npcData.injuries or {})
                end
            },
            {
                title = 'Discharge Patient',
                icon = 'fas fa-door-open',
                description = 'Release after treatment',
                onSelect = function()
                    StopAssistingPatient()
                    
                    ReleasePatient(npc)
                    if Config.DeleteNPCOnRelease then
                        DeletePed(npc)
                    else
                        TaskWanderStandard(npc, 10.0, 10)
                    end
                    
                    for i, data in ipairs(examinedNPCs) do
                        if data.entity == npc then
                            table.remove(examinedNPCs, i)
                            break
                        end
                    end
                    
                    Notify('Medic', npcData.name .. ' has been discharged.', 'success')
                    TriggerServerEvent('medic:patientDischarged', npcData.name)
                end
            },
            {
                title = 'Check Medical Records',
                icon = 'fas fa-notes-medical',
                description = 'Review documentation',
                onSelect = function()
                    local message = ""
                    if not npcData.hasDocuments then
                        message = "No medical records found on patient"
                    else
                        for docType, isValid in pairs(npcData.documents) do
                            local status = isValid and 'Present' or 'Missing'
                            message = message .. docType .. ": " .. status .. "\n"
                        end
                    end
                    Notify('Medical Records', message, 'info')
                end
            },
            {
                title = 'Diagnose Injuries',
                icon = 'fas fa-stethoscope',
                description = 'Check for injuries',
                onSelect = function()
                    if not npcData.hasInjuries or #npcData.injuries == 0 then
                        Notify('Diagnosis', 'No significant injuries detected', 'success')
                    else
                        local injuriesList = table.concat(npcData.injuries, ', ')
                        Notify('Diagnosis', 'Injuries found: ' .. injuriesList, 'error')
                    end
                end
            },
            {
                title = 'Administer First Aid',
                icon = 'fas fa-first-aid',
                description = firstAidDesc,
                onSelect = function()
                    if npcData.treatedWithFirstAid then
                        Notify('Medic', 'Patient has already received first aid.', 'info')
                        return
                    end
                    
                    StopAssistingPatient()
                    Wait(300)
                    
                    AdministerFirstAid(npc, npcData, function()
                        -- Done
                    end)
                end
            }
        }
    })
    
    lib.showContext('assist_menu')
end

local function RegisterNPCTargeting()
    exports['ox_target']:addGlobalPed({
        {
            name = 'medic_examine',
            icon = 'fas fa-stethoscope',
            label = 'Examine Person',
            distance = 3.0,
            canInteract = function(entity)
                return IsMedic() and IsValidHumanNPC(entity) and not IsPatientNPC(entity) and not isPlayingAnimation
            end,
            onSelect = function(data)
                if data.entity then
                    ExaminePatient(data.entity)
                end
            end
        },
        {
            name = 'medic_patient_menu',
            icon = 'fas fa-user-injured',
            label = 'Patient Options',
            distance = 3.0,
            canInteract = function(entity)
                return IsMedic() and IsValidHumanNPC(entity) and IsPatientNPC(entity) and not IsNPCAssisted(entity) and not isPlayingAnimation
            end,
            onSelect = function(data)
                if data.entity then
                    ShowMedicMenu(data.entity)
                end
            end
        }
    })
end

CreateThread(function()
    Wait(2000)
    CreateAssistPrompts()
    Wait(500)
    RegisterNPCTargeting()
    DebugPrint('Medic NPC system initialized')
end)

CreateThread(function()
    while true do
        Wait(0)

        if IsCurrentlyAssisting() and IsMedic() and stopAssistPrompt and patientMenuPrompt and not isPlayingAnimation then
            local npcData = GetStoredNPCData(assistedNPC)
            local promptTitle = npcData and ('Assisting: ' .. npcData.name) or 'Assisting Patient'
            local str = CreateVarString(10, 'LITERAL_STRING', promptTitle)

            PromptSetActiveGroupThisFrame(assistPromptGroup, str)

            if PromptHasHoldModeCompleted(stopAssistPrompt) then
                DebugPrint('[Prompt] G held - stopping assistance')
                StopAssistingPatient()
            end

            if PromptHasHoldModeCompleted(patientMenuPrompt) then
                DebugPrint('[Prompt] E held - opening patient menu')
                ShowAssistMenu()
            end

        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(30000)
        
        for i = #examinedNPCs, 1, -1 do
            if not DoesEntityExist(examinedNPCs[i].entity) then
                table.remove(examinedNPCs, i)
            end
        end
        
        if assistedNPC and not DoesEntityExist(assistedNPC) then
            assistedNPC = nil
        end
    end
end)

CreateThread(function()
    while true do
        Wait(2000)
        local playerPed = PlayerPedId()
        for _, npcData in pairs(examinedNPCs) do
            if DoesEntityExist(npcData.entity) then
                local isFollowing = DecorGetBool(npcData.entity, "IsFollowing") or false
                local isAssisted = DecorGetBool(npcData.entity, "IsAssisted") or false
                
                if isFollowing and not isAssisted then
                    local dist = #(GetEntityCoords(npcData.entity) - GetEntityCoords(playerPed))
                    if dist > 10.0 then
                        TaskFollowToOffsetOfEntity(npcData.entity, playerPed, -1.0, -1.0, 0.0, 1.0, -1, 1.5, true)
                    end
                end
            end
        end
    end
end)

RegisterNetEvent('medic:treatmentSuccess', function(patientName, reward)
    Notify('Medic', 'Treated ' .. patientName .. '. Received $' .. reward, 'success')
end)

RegisterNetEvent('medic:examinationReward', function(reward)
    Notify('Medic', 'Received $' .. reward .. ' for medical examination', 'success')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- Stop medic animation if playing
        if isPlayingAnimation then
            StopMedicAnimation()
        end
        
        if assistedNPC and DoesEntityExist(assistedNPC) then
            DetachEntity(assistedNPC, true, false)
        end
        
        -- Clean up animations on all examined NPCs
        for _, npcData in pairs(examinedNPCs) do
            if DoesEntityExist(npcData.entity) then
                StopPatientAnimation(npcData.entity)
                ReleasePatient(npcData.entity)
            end
        end
        
        if stopAssistPrompt then
            PromptDelete(stopAssistPrompt)
        end
        if patientMenuPrompt then
            PromptDelete(patientMenuPrompt)
        end
    end
end)