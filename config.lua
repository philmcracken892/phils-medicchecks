Config = {}

Config.Debug = false

Config.HospitalLocation = vector4(2731.81, -1231.28, 50.37, 271.88)
Config.DeleteTreatedNPCsAfter = 120

Config.CheckCooldown = 300

Config.PanicChance = 1
Config.CheckDistance = 3.0
Config.PanicDistance = 100.0
Config.PanicSpeed = 2.0
Config.DeleteNPCOnRelease = false

Config.MedicalDocuments = {
    'identification',
    'medical_history',
    'insurance_card',
    'medication_list'
}

-- Medic/Player Animations
Config.MedicAnimations = {
    first_aid = {
        dict = 'mini_games@story@mob4@heal_jules@bandage@arthur',
        anim = 'bandage_fast',
        flag = 1,
        duration = 5000
    },
    examine = {
        dict = 'amb_work@world_human_clipboard@male_a@idle_a',
        anim = 'idle_a',
        flag = 49,
        duration = 3000
    }
}

-- Patient Animations
Config.PatientAnimations = {
    injured_arm = {
        label = 'Injured Arm',
        dict = 'mech_loco_m@generic@injured@unarmed@right_arm@idle',
        anim = 'idle',
        flag = 31
    },
    injured_shoulder = {
        label = 'Injured Shoulder',
        dict = 'mech_loco_m@character@arthur@injured@left_shoulder@unarmed@idle',
        anim = 'idle',
        flag = 31
    },
    injured_hip = {
        label = 'Injured Hip',
        dict = 'mech_loco_m@generic@injured@unarmed@left_leg@idle',
        anim = 'idle',
        flag = 31
    },
    injured_chest = {
        label = 'Injured Chest',
        dict = 'mech_loco_m@generic@injured@unarmed@chest@idle',
        anim = 'idle',
        flag = 31
    },
    injured_head = {
        label = 'Injured Head',
        dict = 'mech_loco_m@generic@injured@unarmed@head@idle',
        anim = 'idle',
        flag = 31
    },
    injured_neck = {
        label = 'Injured Neck',
        dict = 'mech_loco_m@generic@injured@unarmed@critical_neck_right@idle',
        anim = 'idle',
        flag = 31
    },
    injured_back = {
        label = 'Injured Back',
        dict = 'mech_loco_m@generic@injured@unarmed@critical_back@idle',
        anim = 'idle',
        flag = 31
    },
    sick = {
        label = 'Sick',
        dict = 'amb_wander@upperbody_idles@sick@both_arms@male_a@idle_a',
        anim = 'idle_c',
        flag = 31
    },
    sleeping = {
        label = 'Unconscious',
        dict = 'amb_rest@world_human_sleep_ground@arm@male_b@idle_b',
        anim = 'idle_f',
        flag = 1
    },
    vomiting = {
        label = 'Vomiting',
        dict = 'amb_misc@world_human_vomit@male_a@idle_b',
        anim = 'idle_f',
        flag = 31
    },
    standing_dazed = {
        label = 'Standing Dazed',
        dict = 'amb_misc@world_human_drunk_dancing@male@male_a@idle_b',
        anim = 'idle_e',
        flag = 31
    }
}

-- Possible injuries/conditions to diagnose with associated animations
Config.InjuryTypes = {
    { name = 'Severe Bleeding', chance = 15, animation = 'injured_arm' },
    { name = 'Broken Arm', chance = 12, animation = 'injured_arm' },
    { name = 'Broken Leg', chance = 10, animation = 'injured_hip' },
    { name = 'Gunshot Wound', chance = 20, animation = 'injured_chest' },
    { name = 'Head Trauma', chance = 25, animation = 'injured_head' },
    { name = 'Alcohol Poisoning', chance = 30, animation = 'vomiting' },
    { name = 'Burns', chance = 20, animation = 'injured_chest' },
    { name = 'Hypothermia', chance = 25, animation = 'sick' },
    { name = 'Infection', chance = 15, animation = 'sick' },
    { name = 'Snake Bite', chance = 12, animation = 'injured_arm' },
    { name = 'Dehydration', chance = 18, animation = 'sick' },
    { name = 'Fractured Ribs', chance = 14, animation = 'injured_chest' },
    { name = 'Concussion', chance = 22, animation = 'injured_head' },
    { name = 'Shoulder Injury', chance = 16, animation = 'injured_shoulder' },
    { name = 'Back Injury', chance = 14, animation = 'injured_back' },
    { name = 'Neck Injury', chance = 10, animation = 'injured_neck' },
    { name = 'Food Poisoning', chance = 20, animation = 'vomiting' },
    { name = 'Unconscious', chance = 8, animation = 'sleeping' },
    { name = 'Fever', chance = 22, animation = 'sick' },
    { name = 'Hip Fracture', chance = 12, animation = 'injured_hip' }
}

Config.HasDocumentsChance = 70
Config.ValidDocumentChance = 80
Config.HasInjuryChance = 70
Config.MaxInjuries = 3

Config.TreatmentReward = 10
Config.ExaminationReward = 10

Config.FirstNames = {
    'Patient',
}

Config.LastNames = {
    'Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Miller', 'Davis', 'Garcia', 'Rodriguez', 'Wilson',
    'Martinez', 'Anderson', 'Taylor', 'Thomas', 'Hernandez', 'Moore', 'Martin', 'Jackson', 'Thompson', 'White',
    'Harris', 'Clark', 'Lewis', 'Robinson', 'Walker', 'Perez', 'Hall', 'Young', 'Allen', 'Sanchez'
}