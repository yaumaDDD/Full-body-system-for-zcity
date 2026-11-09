if WoundSystem and WoundSystem._WSZCEmbeddedLoaderRan then return end
WoundSystem = WoundSystem or {}
WoundSystem._WSZCEmbeddedLoaderRan = true
WoundSystem._WSZCEmbedded = true

WoundSystem = WoundSystem or {}

local sharedFiles = {
    "wszc_vendor/cu/woundsystem/shared/sh_core.lua",
    "wszc_vendor/cu/woundsystem/shared/sh_limb_statuses.lua",
    "wszc_vendor/cu/woundsystem/shared/sh_medical_items.lua",
    "wszc_vendor/cu/woundsystem/shared/sh_cas3_locale.lua",
    "wszc_vendor/cu/woundsystem/shared/sh_skills.lua",
    "wszc_vendor/cu/woundsystem/shared/sh_limb_muscle.lua",
    "wszc_vendor/cu/woundsystem/shared/sh_ragdoll_visuals.lua"
}

local sharedDirs = {
    "wszc_vendor/cu/woundsystem/medical_tools"
}

local serverFiles = {
    "wszc_vendor/cu/woundsystem/server/sv_resources.lua",
    "wszc_vendor/cu/woundsystem/server/health/sv_config.lua",
    "wszc_vendor/cu/woundsystem/server/health/sv_constants.lua",
    "wszc_vendor/cu/woundsystem/server/health/sv_wake_positions.lua",
    "wszc_vendor/cu/woundsystem/server/health/sv_facial_state.lua",
    "wszc_vendor/cu/woundsystem/server/health/sv_damage_feedback.lua",
    "wszc_vendor/cu/woundsystem/server/health/sv_fall_impact.lua",
    "wszc_vendor/cu/woundsystem/server/health/sv_cas3_bodyfeel.lua",
    "wszc_vendor/cu/woundsystem/server/sv_health.lua",
    "wszc_vendor/cu/woundsystem/server/sv_talker_chat.lua",
    "wszc_vendor/cu/woundsystem/server/sv_blood_effects.lua",
    "wszc_vendor/cu/woundsystem/server/sv_brain_effects.lua",
    "wszc_vendor/cu/woundsystem/server/sv_happiness.lua",
    "wszc_vendor/cu/woundsystem/server/sv_deathscreen.lua",
    "wszc_vendor/cu/woundsystem/server/sv_sounds.lua",
    "wszc_vendor/cu/woundsystem/server/sv_voice_proximity.lua",
    "wszc_vendor/cu/woundsystem/server/sv_hev_automedic.lua",
    "wszc_vendor/cu/woundsystem/server/health/sv_selfharm.lua"
}

local clientFiles = {
    "wszc_vendor/cu/woundsystem/client/cl_ui_registry.lua",
    "wszc_vendor/cu/woundsystem/client/cl_text_corruption.lua",
    "wszc_vendor/cu/woundsystem/client/cl_skills.lua",
    "wszc_vendor/cu/woundsystem/client/minigames/cl_clip.lua",
    "wszc_vendor/cu/woundsystem/client/minigames/sh_handphysics.lua",
    "wszc_vendor/cu/woundsystem/client/minigames/minigame_dev_config.lua",
    "wszc_vendor/cu/woundsystem/client/minigames/cl_shrapnel.lua",
    "wszc_vendor/cu/woundsystem/client/minigames/cl_dislocation.lua",
    "wszc_vendor/cu/woundsystem/client/minigames/cl_bandage.lua",
    "wszc_vendor/cu/woundsystem/client/minigames/cl_syringe.lua",
    "wszc_vendor/cu/woundsystem/client/minigames/cl_aed.lua",
    "wszc_vendor/cu/woundsystem/client/minigames/cl_selfharm.lua",
    "wszc_vendor/cu/woundsystem/client/cl_dismemberment_visuals.lua",
    "wszc_vendor/cu/woundsystem/client/cl_health_gui.lua",
    "wszc_vendor/cu/woundsystem/client/cl_multiplayer_feedback.lua",
    "wszc_vendor/cu/woundsystem/client/cl_facial_expressions.lua",
    "wszc_vendor/cu/woundsystem/client/cl_screen_effect_smoothing.lua",
    "wszc_vendor/cu/woundsystem/client/cl_screen_effect_shaders.lua",
    "wszc_vendor/cu/woundsystem/client/cl_body_item_use.lua",
    "wszc_vendor/cu/woundsystem/client/cl_blood_effects.lua",
    "wszc_vendor/cu/woundsystem/client/cl_brain_effects.lua",
    "wszc_vendor/cu/woundsystem/client/cl_self_talk_hud.lua",
    "wszc_vendor/cu/woundsystem/client/cl_chat_distance.lua",
    "wszc_vendor/cu/woundsystem/client/cl_happiness.lua",
    "wszc_vendor/cu/woundsystem/client/cl_moodles.lua",
    "wszc_vendor/cu/woundsystem/client/cl_options.lua",
    "wszc_vendor/cu/woundsystem/client/cl_sound_manager.lua",
    "wszc_vendor/cu/woundsystem/client/cl_voice_proximity.lua"
}

local function AddClientFile(path)
    if SERVER then
        AddCSLuaFile(path)
    end
end

local function IncludeShared(path)
    AddClientFile(path)
    include(path)
end

local function IncludeRealmFile(path)
    local name = string.GetFileFromFilename and string.GetFileFromFilename(path) or string.match(path, "[^/\\]+$") or path
    local prefix = string.sub(name, 1, 3)

    if prefix == "sv_" then
        if SERVER then include(path) end
        return
    end

    if prefix == "cl_" then
        AddClientFile(path)
        if CLIENT then include(path) end
        return
    end

    IncludeShared(path)
end

local function IncludeDir(dir)
    if not file or not file.Find then return end

    local files = file.Find(dir .. "/*.lua", "LUA") or {}
    table.sort(files)

    for _, name in ipairs(files) do
        IncludeRealmFile(dir .. "/" .. name)
    end
end

for _, path in ipairs(sharedFiles) do
    IncludeShared(path)
end

for _, dir in ipairs(sharedDirs) do
    IncludeDir(dir)
end

if SERVER then
    WoundSystem.PoolNetStrings()

    for _, path in ipairs(clientFiles) do
        AddClientFile(path)
    end

    for _, path in ipairs(serverFiles) do
        include(path)
    end
else
    for _, path in ipairs(clientFiles) do
        include(path)
    end
end
