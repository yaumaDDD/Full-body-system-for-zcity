-- ZCity <-> Casualties: Unknown: `ply.organism`-authoritative mode (server part)
--
-- Goal (owner's choice): the standard ZCity health simulation owns the body.
-- WoundSystem (C:U) stays loaded, but only as
--   * the injury HUD / inspection panel (WoundSystem.OpenHealthHUD),
--   * the treatment minigames (bandage / syringe) and their protocol,
--   * a *shadow* view of ZCity injuries (BodyState / PlayerLimbs),
--   * the single, source-agnostic shrapnel protocol (state.shrapnel).
--
-- `zc_woundsystem_compat_authority 1` (default) = this mode.
-- `zc_woundsystem_compat_authority 0`           = the original bridge, where
--                                                C:U owns wounds entirely.
--
-- No file inside the original ZIP addons is modified.  Everything here is a
-- runtime wrapper installed after both addons have loaded.
--
-- IMPORTANT CONSEQUENCE OF THE CHOSEN BASE
-- ---------------------------------------
-- When C:U stops owning wounds, its own shrapnel producers stop firing too:
-- Fn.AddGunshotShrapnel() and the DMG_BLAST branch live *inside* C:U's
-- EntityTakeDamage handler, which this mode no longer calls.  To keep shotgun
-- and explosive shrapnel (an explicit requirement) those two rules are MOVED
-- into WSZC.AddShrapnel() below.  They are not duplicated: C:U's handler is
-- suppressed in this mode, and in bridge mode (authority 0) this injector is
-- disabled so C:U's own producers stay authoritative.
--
-- All three producers (gunshot, blast, glass) write the SAME integer field
-- `state.shrapnel`.  There is no `source` field and no source-dependent branch:
-- the native C:U "Remove shrapnel" button always opens the very same
-- BuildShrapnelSession() minigame, opened from our "Проверить травмы" button.

if not SERVER then return end

WSZC = WSZC or {}

if WSZC._OrganismLoaded then return end
WSZC._OrganismLoaded = true

-- The shared module normally loads from lua/autorun/ before server files, but
-- do not depend on loader ordering: WrapHook() needs WithVanillaContext().
if not WSZC.WithVanillaContext then
    include("autorun/sh_zcity_woundsystem_compat.lua")
end

local cvShrapnel = CreateConVar("zc_woundsystem_compat_shrapnel", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Enable the unified ZCity shrapnel state (gunshot, blast and glass)", 0, 1)
local cvGlass = CreateConVar("zc_woundsystem_compat_glass_shrapnel", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Inject shrapnel from hands/feet hitting glass, including ragdoll collisions", 0, 1)
local cvRegen = CreateConVar("zc_woundsystem_compat_shrapnel_regen_block", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Lodged shrapnel blocks ZCity limb regeneration until extracted", 0, 1)
local cvLodgedEffects = CreateConVar("zc_woundsystem_compat_shrapnel_lodged_effects", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Any lodged shrapnel/glass causes growing real wounds and pain until extracted", 0, 1)
local cvBandageStrength = CreateConVar("zc_woundsystem_compat_bandage_strength", "3",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Multiplier for real ZCity wound severity treated by one bandage roll", 0.25, 5)
local cvBleedingMul = CreateConVar("zc_woundsystem_compat_bleeding_multiplier", "0.55",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Upper cap for ZCity ordinary-wound bleedingmul; arteries remain a tourniquet emergency", 0.1, 2)
local cvBandagedInfection = CreateConVar("zc_woundsystem_compat_bandaged_shrapnel_infection", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Bandaging over lodged shrapnel causes slowly spreading internal infection", 0, 1)
local cvInfectionDeathDelay = CreateConVar("zc_woundsystem_compat_shrapnel_infection_death_delay", "600",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Seconds from bandaging an extremity over shrapnel to fatal brain infection without full aftercare", 60, 3600)
local cvShadow = CreateConVar("zc_woundsystem_compat_shadow", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Mirror ZCity injuries into the C:U injury HUD (BodyState / PlayerLimbs)", 0, 1)
local cvLimbBleed = CreateConVar("zc_woundsystem_compat_limb_bleed", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Use ZCity's per-bone wounds for limb bleeding instead of painting all 16 C:U limbs", 0, 1)
local cvOnBlocked = CreateConVar("zc_woundsystem_compat_shrapnel_on_blocked", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Count a hit whose EntityTakeDamage hook returned true (ZCity redirects it to the fake ragdoll)", 0, 1)
local cvCUBlood = CreateConVar("zc_woundsystem_compat_disable_cu_blood", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Stop C:U from hiding vanilla/ZCity blood (woundsys_replace_vanilla_blood)", 0, 1)
local cvShotgunOnly = CreateConVar("zc_woundsystem_compat_shrapnel_only_shotgun_blast", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Lodge fragments ONLY from shotguns and explosions (0 = also every DMG_BULLET pistol hit)", 0, 1)
local cvPreserveReset = CreateConVar("zc_woundsystem_compat_preserve_reset_structure", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "On 'reset organism' keep ZCity unconscious/ragdoll structure instead of standing the player up", 0, 1)
local cvDislocationStart = CreateConVar("zc_woundsystem_compat_dislocation_start", "35",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Starting bone displacement (0..100) for the C:U manual reduction minigame; lower = fewer hits and a bone that stays on screen", 10, 100)
local cvDebug = CreateConVar("zc_woundsystem_compat_organism_debug", "0",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Print organism-authority diagnostics", 0, 1)

local TAG = "[ZCity/CU compat] "
local Unpack = table.unpack or unpack -- GMod Lua 5.1 / newer regression runtimes

local function Debug(fmt, ...)
    if not (cvDebug and cvDebug:GetBool()) then return end
    local ok, msg = pcall(string.format, fmt, ...)
    print(TAG .. (ok and msg or tostring(fmt)))
end

local function Warn(msg)
    if WSZC.Warn then WSZC.Warn(msg) else ErrorNoHalt(TAG .. tostring(msg) .. "\n") end
end

local function ConVarFloat(cv, fallback)
    if cv and cv.GetFloat then
        local ok, value = pcall(cv.GetFloat, cv)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return fallback
end

local function Authority()
    if WSZC.OrganismAuthority then return WSZC.OrganismAuthority() end
    local cv = GetConVar and GetConVar("zc_woundsystem_compat_authority")
    return not cv or cv:GetBool() ~= false
end

-- Autorun hooks are registered before deferred Setup finishes.  In adaptive
-- mode they must be inert until both readiness and the optional organism
-- contract are proven; otherwise installing the connector on an unknown
-- gamemode could still inject shrapnel or rewrite ragdoll state.
local function OrganismHooksActive()
    if WSZC.AdaptiveCompatibility and WSZC.AdaptiveCompatibility() then
        if WSZC.Ready ~= true then return false end
        if WSZC.Supports and not WSZC.Supports("organism_extensions") then return false end
    end
    return Authority()
end

local function H()
    return WoundSystem and WoundSystem.Health
end

local function WB()
    return hg and hg.WoundBridge
end

-- C:U exposes two different tables: WoundSystem.Health.Constants (the real
-- config, with ShrapnelPieceCount and the timer names) and WoundSystem.Health.Const
-- (an internal limb map populated by the compat layer).  Never mix them up.
local function Constants()
    local h = H()
    if not h then return nil end
    return h.Constants or WSZC.Const or h.Const
end

---------------------------------------------------------------------------
-- Limb mapping
---------------------------------------------------------------------------

-- C:U limb id -> ZCity organism damage / amputation flags.
-- `org.larm` etc. are damage fractions (0 = healthy, 1 = destroyed), which is
-- exactly the inverse of the strength value WB.Sync() used to write.
local LIMB_ORG = {
    -- C:U calls head.broken "Broken neck".  Give that fracture its own limb;
    -- head keeps head-bone wounds/eyes, while neck owns org.skull treatment,
    -- muscle shadow and boneHealTimer.  The two are not aliases.
    head      = { dmg = nil,      amp = "headamputated", dis = nil },
    neck      = { dmg = "skull",  amp = "headamputated", dis = nil },
    thorax    = { dmg = "chest",  amp = nil,              dis = nil },
    -- ZCity has ONE lower-torso scalar (org.pelvis).  Abdomen and pelvis have
    -- independent C:U states/actions, while real wounds are routed by bone.
    -- A single treatment is applied once; the scalar is never added twice.
    abdomen   = { dmg = "pelvis", amp = nil,              dis = nil },
    pelvis    = { dmg = "pelvis", amp = nil,              dis = nil },
    -- Native AmputateLimb() starts at the FOREARM / CALF, exactly like
    -- WB.ZLimbToWS (larm -> forearm_L, lleg -> crus_L).  The upper arm/thigh
    -- is the remaining stump and must NOT be marked dismembered.  The previous
    -- whole-group mapping deleted that stump from both the 3D visual and UI.
    arm_L     = { dmg = "larm", amp = nil, dis = "larmdislocation" },
    forearm_L = { dmg = "larm", amp = "larmamputated", dis = "larmdislocation" },
    hand_L    = { dmg = "larm", amp = "larmamputated", dis = "larmdislocation" },
    arm_R     = { dmg = "rarm", amp = nil, dis = "rarmdislocation" },
    forearm_R = { dmg = "rarm", amp = "rarmamputated", dis = "rarmdislocation" },
    hand_R    = { dmg = "rarm", amp = "rarmamputated", dis = "rarmdislocation" },
    thigh_L   = { dmg = "lleg", amp = nil, dis = "llegdislocation" },
    crus_L    = { dmg = "lleg", amp = "llegamputated", dis = "llegdislocation" },
    foot_L    = { dmg = "lleg", amp = "llegamputated", dis = "llegdislocation" },
    thigh_R   = { dmg = "rleg", amp = nil, dis = "rlegdislocation" },
    crus_R    = { dmg = "rleg", amp = "rlegamputated", dis = "rlegdislocation" },
    foot_R    = { dmg = "rleg", amp = "rlegamputated", dis = "rlegdislocation" },
}

local NECK_DEFAULT_STATE = {
    skin = 100, muscle = 100, muscleStrength = 1,
    pain = 0, bleed = 0, infection = 0, infectionSpeed = 0,
    shrapnel = 0, disinfectTime = 0,
    broken = false, dislocated = false, dislocationTimer = 0, boneHealTimer = 0,
    isBandaged = false, blockedBleeding = false,
    bandageSlowAmount = 0, skinHealAmount = 0, furBloodAmount = 0,
    eyes = 2, dismembered = false, bandageMinigameSpeedMult = 1,
    customStatuses = {},
}

--- Add a REAL sixteenth entry to C:U's server PlayerLimbs table.  SendLimbUpdate
--- already accepts any key present here, so skin/muscle/broken and every native
--- status use the stock net protocol without a parallel client-only shadow.
function WSZC.EnsureNeckState(ply)
    if not IsValid(ply) then return false end
    local h = H()
    local limbs = h and h.GetLimbs and h.GetLimbs(ply) or nil
    if type(limbs) ~= "table" then return false end
    if type(limbs.neck) == "table" then return false end

    local state = table.Copy(WSZC.NeckDefaultState or NECK_DEFAULT_STATE)
    state.customStatuses = {}
    if WoundSystem and WoundSystem.Statuses
        and type(WoundSystem.Statuses.ApplyDefaultState) == "function" then
        pcall(WoundSystem.Statuses.ApplyDefaultState, state)
    end
    limbs.neck = state
    if h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, "neck", true) end
    return true
end

--- Seventeenth native entry: pelvis has its own hover/action/net state.  It is
--- a fresh state, not table.Copy(current abdomen damage); ZCity remains the
--- authority and PushShadow routes each actual wound to exactly one of them.
function WSZC.EnsurePelvisState(ply)
    if not IsValid(ply) then return false end
    local h = H()
    local limbs = h and h.GetLimbs and h.GetLimbs(ply) or nil
    if type(limbs) ~= "table" then return false end
    if type(limbs.pelvis) == "table" then return false end

    local state = table.Copy(WSZC.NeckDefaultState or NECK_DEFAULT_STATE)
    state.customStatuses = {}
    if WoundSystem and WoundSystem.Statuses
        and type(WoundSystem.Statuses.ApplyDefaultState) == "function" then
        pcall(WoundSystem.Statuses.ApplyDefaultState, state)
    end
    limbs.pelvis = state
    if h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, "pelvis", true) end
    return true
end

function WSZC.InstallNeckState(h)
    h = h or H()
    if type(h) ~= "table" then return false end

    if not WSZC.NeckDefaultState and type(h.InitPlayer) == "function"
        and type(WSZC.Upvalue) == "function" then
        local template = WSZC.Upvalue(h.InitPlayer, "defaultLimbState")
        if type(template) == "table" then WSZC.NeckDefaultState = table.Copy(template) end
    end

    -- Exported InitPlayer is used by the bridge and by several C:U systems.
    -- Its PlayerSpawn hook calls the LOCAL original directly, hence the spawn
    -- hook below is deliberately a second, authoritative first-life path.
    if type(h.InitPlayer) == "function" and h.InitPlayer ~= WSZC._NeckInitWrapper then
        local original = h.InitPlayer
        WSZC._NeckOriginalInitPlayer = original
        WSZC._NeckInitWrapper = function(ply)
            local a, b, c = original(ply)
            WSZC.EnsureNeckState(ply)
            WSZC.EnsurePelvisState(ply)
            return a, b, c
        end
        h.InitPlayer = WSZC._NeckInitWrapper
    end

    local const = h.Const
    if type(const) == "table" then
        const.ParentLimb = const.ParentLimb or {}
        const.ParentLimb.neck = "head"
        const.ParentLimb.pelvis = "abdomen"
        const.ParentLimb.thigh_R = "pelvis"
        const.ParentLimb.thigh_L = "pelvis"
        const.LimbToBones = const.LimbToBones or {}
        const.LimbToBones.neck = { "ValveBiped.Bip01_Neck1", "Bip01 Neck" }
        const.LimbToBones.abdomen = { "ValveBiped.Bip01_Spine1", "Bip01 Spine1" }
        const.LimbToBones.pelvis = { "ValveBiped.Bip01_Pelvis", "Bip01 Pelvis" }
        const.NonDismemberableCoreLimbs = const.NonDismemberableCoreLimbs or {}
        const.NonDismemberableCoreLimbs.pelvis = true
        if type(const.ConnectedLimbs) == "table" then
            const.ConnectedLimbs.abdomen = { "thorax", "pelvis" }
            const.ConnectedLimbs.pelvis = { "abdomen", "thigh_R", "thigh_L" }
            const.ConnectedLimbs.thigh_R = { "pelvis", "crus_R" }
            const.ConnectedLimbs.thigh_L = { "pelvis", "crus_L" }
        end
        if type(const.LimbToBones.head) == "table"
            and WSZC._NeckLimbBonesTable ~= const.LimbToBones then
            local headBones = const.LimbToBones.head
            for i = #headBones, 1, -1 do
                if string.find(string.lower(tostring(headBones[i])), "neck", 1, true) then
                    table.remove(headBones, i)
                end
            end
            WSZC._NeckLimbBonesTable = const.LimbToBones
        end

        local ragdollBones = const.RagdollDamageBones
        if type(ragdollBones) == "table" and WSZC._NeckRagdollBonesTable ~= ragdollBones then
            for _, candidate in ipairs(ragdollBones) do
                if candidate.limb == "head" and type(candidate.patterns) == "table" then
                    for i = #candidate.patterns, 1, -1 do
                        if string.find(string.lower(tostring(candidate.patterns[i])), "neck", 1, true) then
                            table.remove(candidate.patterns, i)
                        end
                    end
                end
            end
            table.insert(ragdollBones, 1, { limb = "neck", patterns = { "neck" } })

            local abdomenIndex, hasPelvis
            for i, candidate in ipairs(ragdollBones) do
                if candidate.limb == "abdomen" then
                    abdomenIndex = i
                    candidate.patterns = { "spine1", "stomach", "abdomen" }
                elseif candidate.limb == "pelvis" then
                    hasPelvis = true
                    candidate.patterns = { "pelvis", "spine", "hips", "hip" }
                end
            end
            if not hasPelvis then
                table.insert(ragdollBones, (abdomenIndex or #ragdollBones) + 1, {
                    limb = "pelvis", patterns = { "pelvis", "spine", "hips", "hip" },
                })
            end
            WSZC._NeckRagdollBonesTable = ragdollBones
        end
    end

    if not WSZC._NeckSpawnHook then
        WSZC._NeckSpawnHook = true
        hook.Add("PlayerSpawn", "WSZC_NeckFirstLifeSync", function(ply)
            timer.Simple(0, function()
                if not IsValid(ply) then return end
                WSZC.EnsureNeckState(ply)
                WSZC.EnsurePelvisState(ply)
                local restored = false
                if WSZC.RestoreBones then
                    local ok, result = pcall(WSZC.RestoreBones, ply)
                    restored = ok and result == true
                end
                if not restored then
                    local health = H()
                    local limbs = health and health.GetLimbs and health.GetLimbs(ply) or nil
                    if type(limbs) == "table" and health.SendLimbUpdate then
                        for limbId in pairs(limbs) do
                            pcall(health.SendLimbUpdate, ply, limbId, true)
                        end
                    end
                end
            end)
            -- A first-life client can finish its own entity initialization
            -- after the spawn packet.  Re-send both added states once it is up.
            timer.Simple(1, function()
                if not IsValid(ply) then return end
                WSZC.EnsureNeckState(ply)
                WSZC.EnsurePelvisState(ply)
                local health = H()
                if health and health.SendLimbUpdate then
                    pcall(health.SendLimbUpdate, ply, "neck", true)
                    pcall(health.SendLimbUpdate, ply, "pelvis", true)
                end
            end)
        end)
    end

    if player and player.GetAll then
        WSZC._NeckInitialNetSent = WSZC._NeckInitialNetSent or {}
        for _, ply in ipairs(player.GetAll()) do
            local created = WSZC.EnsureNeckState(ply)
            local createdPelvis = WSZC.EnsurePelvisState(ply)
            if h.SendLimbUpdate and not WSZC._NeckInitialNetSent[ply] then
                -- Existing players do not necessarily respawn after addon setup.
                -- Ensure* sends newly-created states itself; these cover states
                -- created during an earlier pre-export install pass.
                if not created then pcall(h.SendLimbUpdate, ply, "neck", true) end
                if not createdPelvis then pcall(h.SendLimbUpdate, ply, "pelvis", true) end
            end
            if h.SendLimbUpdate then WSZC._NeckInitialNetSent[ply] = true end
        end
    end
    return true
end

-- The only treatment site for a ZCity amputation is the remaining proximal
-- stump.  Distal trace hits can still arrive from an old ragdoll for one tick;
-- route those to the same stump without changing ordinary aimed-limb routing.
local AMPUTATION_APPLICATION_SITE = {
    arm_L = "arm_L", forearm_L = "arm_L", hand_L = "arm_L",
    arm_R = "arm_R", forearm_R = "arm_R", hand_R = "arm_R",
    thigh_L = "thigh_L", crus_L = "thigh_L", foot_L = "thigh_L",
    thigh_R = "thigh_R", crus_R = "thigh_R", foot_R = "thigh_R",
}
local AMPUTATION_STUMP_FLAG = {
    arm_L = "larmamputated", arm_R = "rarmamputated",
    thigh_L = "llegamputated", thigh_R = "rlegamputated",
}

--- Project native ZCity amputation flags into C:U presentation only.  The
--- organism tables/flags themselves are never rewritten.  A separate status
--- is placed on the visible stump; the absent distal sprites stay hidden by
--- the stock WoundView, while its real arterial wound remains independent.
local function SyncAmputationShadow(org, limbs)
    local dirty = {}
    if type(org) ~= "table" or type(limbs) ~= "table" then return dirty end
    if WSZC.InstallAmputationStatus then WSZC.InstallAmputationStatus() end
    local statusId = WSZC.AMPUTATION_STATUS_ID or "WSZC_AMPUTATION"

    for limbId, map in pairs(LIMB_ORG) do
        local state = limbs[limbId]
        if type(state) == "table" then
            local dismembered = map.amp ~= nil and org[map.amp] == true or false
            if state.dismembered ~= dismembered then
                state.dismembered = dismembered
                dirty[limbId] = true
            end

            local stumpFlag = AMPUTATION_STUMP_FLAG[limbId]
            local showStatus = stumpFlag ~= nil and org[stumpFlag] == true
            local statuses = state.customStatuses
            if showStatus then
                if type(statuses) ~= "table" then
                    statuses = {}
                    state.customStatuses = statuses
                end
                if statuses[statusId] ~= true then
                    statuses[statusId] = true
                    dirty[limbId] = true
                end
            elseif type(statuses) == "table" and statuses[statusId] ~= nil then
                statuses[statusId] = nil
                dirty[limbId] = true
            end
        end
    end
    return dirty
end
WSZC.SyncAmputationShadow = SyncAmputationShadow

-- Cardio/internal bleeding is an organism-wide value in ZCity.  Keep it in
-- that model and expose a single native C:U status on abdomen; do NOT turn it
-- into state.bleed (which would create a fake external haemorrhage) and do not
-- duplicate the marker on pelvis.
function WSZC.SyncInternalBleedingShadow(org, limbs)
    if type(org) ~= "table" or type(limbs) ~= "table" then return false end
    if not (WSZC.InstallInternalBleedingStatus and WSZC.InstallInternalBleedingStatus()) then
        return false
    end

    local state = limbs.abdomen
    if type(state) ~= "table" then return false end
    local id = WSZC.INTERNAL_BLEEDING_STATUS_ID
    local amount = math.max(0, tonumber(org.internalBleed) or 0)
    local current = state.customStatuses and state.customStatuses[id] or nil

    if amount <= 0 then
        if current == nil then return false end
        state.customStatuses[id] = nil
        return true
    end

    state.customStatuses = state.customStatuses or {}
    if type(current) == "number" and math.abs(current - amount) <= 0.01 then
        return false
    end
    state.customStatuses[id] = amount
    return true
end

-- Owner (2026-11-05): "переломы должны создавать только в одной точке тоесть
-- по середине ноги или руки там же три лимба а вывих на один лимб выше".
-- ZCity keeps ONE flag for a whole arm/leg (org.larm / org.rarm / org.lleg /
-- org.rleg and the matching *dislocation), while C:U has THREE limbs there:
--   arm/forearm/hand  and  thigh/crus/foot.
-- Before this anchor, the single flag painted `broken` AND `dislocated` onto
-- all three limbs at once, so the WoundView showed a column of fracture /
-- dislocation icons down the whole leg (Screenshot_7.png).  Now:
--   fracture    -> ONLY the MIDDLE limb:  forearm_L/R, crus_L/R
--   dislocation -> ONLY ONE limb ABOVE:   arm_L/R, thigh_L/R
-- neck (C:U's head/skull fracture) and thorax (brokenribs) are single points.
local BONE_ANCHOR = {
    fracture    = { forearm_L = true, forearm_R = true,
                    crus_L = true,    crus_R = true },
    dislocation = { arm_L = true, arm_R = true,
                    thigh_L = true, thigh_R = true },
}

--- True when this C:U limb is the ONE point that owns a bone state.
--- Neck/thorax are their own single points (skull fracture, ribs); every other
--- limb must be in the anchor set or it is deliberately left healthy-looking.
local function BoneAnchor(limbId, kind)
    if limbId == "neck" or limbId == "thorax" then return true end
    local set = BONE_ANCHOR[kind]
    return set ~= nil and set[limbId] == true
end
WSZC.BoneAnchor = BoneAnchor

-- Built defensively: GMod defines these, but a headless test runtime may not.
local HITGROUP_LIMB = {}
local function AddHitgroup(id, limbId)
    if id ~= nil then HITGROUP_LIMB[id] = limbId end
end
AddHitgroup(HITGROUP_HEAD, "head")
AddHitgroup(HITGROUP_CHEST, "thorax")
AddHitgroup(HITGROUP_STOMACH, "abdomen")
AddHitgroup(HITGROUP_GEAR, "pelvis")
AddHitgroup(HITGROUP_LEFTARM, "forearm_L")
AddHitgroup(HITGROUP_RIGHTARM, "forearm_R")
AddHitgroup(HITGROUP_LEFTLEG, "crus_L")
AddHitgroup(HITGROUP_RIGHTLEG, "crus_R")

local GLASS_SURFACES = {
    glass = true, glassbottle = true, glassfloor = true,
    brokenglass = true, glass_breakable = true,
}

local function BoneLimb(bonename)
    if type(bonename) ~= "string" then return nil end
    local lower = string.lower(bonename)
    local side = (string.find(lower, "_l_") or string.find(lower, "_l.")) and "_L" or
                 (string.find(lower, "_r_") or string.find(lower, "_r.")) and "_R" or nil
    local L = string.find(lower, "left") ~= nil
    local R = string.find(lower, "right") ~= nil
    if L then side = "_L" elseif R then side = "_R" end
    if not side then return nil end

    if string.find(lower, "hand") then return "hand" .. side end
    if string.find(lower, "foot") then return "foot" .. side end
    if string.find(lower, "forearm") then return "forearm" .. side end
    if string.find(lower, "upperarm") then return "arm" .. side end
    if string.find(lower, "calf") then return "crus" .. side end
    if string.find(lower, "thigh") then return "thigh" .. side end
    return nil
end

local function HitgroupLimb(hitgroup)
    return HITGROUP_LIMB[hitgroup]
end

---------------------------------------------------------------------------
-- Per-bone wound -> C:U limb id
---------------------------------------------------------------------------
-- ZCity stores `org.wounds[n] = {severity, localPos, localAng, boneName, time}`
-- and `org.arterialwounds[n][7] = "<limb>artery"`.  The old shadow copied the
-- single global `org.bleed` into EVERY C:U limb, which is why one shotgun hit
-- in the leg made the whole body drip blood in the C:U HUD.

local LIMB_ALIAS = {
    head = "head", skull = "head", neck = "neck",
    chest = "thorax", thorax = "thorax", spine2 = "thorax", spine3 = "thorax",
    spine4 = "thorax", rib = "thorax", sternum = "thorax",
    stomach = "abdomen", abdomen = "abdomen", spine1 = "abdomen",
    pelvis = "pelvis", spine = "pelvis", hips = "pelvis", hip = "pelvis",
    larm = "forearm_L", rarm = "forearm_R",
    lleg = "thigh_L", rleg = "thigh_R",
}

local ARTERY_LIMB = {
    larmartery = "forearm_L", rarmartery = "forearm_R",
    llegartery = "thigh_L", rlegartery = "thigh_R",
    spineartery = "abdomen", neckartery = "neck", headartery = "head",
}

local function NormalizeLimb(limbId)
    if type(limbId) ~= "string" then return nil end
    if LIMB_ORG[limbId] then return limbId end
    return LIMB_ALIAS[string.lower(limbId)]
end

local function BoneNameOf(ply, bone)
    if type(bone) == "string" then return bone end
    if isnumber and isnumber(bone) and IsValid(ply) and ply.GetBoneName then
        local ok, name = pcall(ply.GetBoneName, ply, bone)
        if ok and type(name) == "string" then return name end
    end
    if isnumber and isnumber(bone) and IsValid(ply) and IsValid(ply.FakeRagdoll)
        and ply.FakeRagdoll.GetBoneName then
        local ok, name = pcall(ply.FakeRagdoll.GetBoneName, ply.FakeRagdoll, bone)
        if ok and type(name) == "string" then return name end
    end
    return nil
end

local function LimbFromBoneName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local lower = string.lower(name)

    -- C:U's legacy head patterns also contain "neck".  Resolve the anatomical
    -- bone FIRST so Bip01_Neck1 can never be folded back into head by that table.
    if string.find(lower, "neck", 1, true) then return "neck" end

    -- 1) C:U's own ragdoll table, when that build exports it.
    local c = Constants()
    if c and type(c.RagdollDamageBones) == "table" then
        for _, candidate in ipairs(c.RagdollDamageBones) do
            if LIMB_ORG[candidate.limb] then
                for _, pattern in ipairs(candidate.patterns or {}) do
                    if string.find(lower, string.lower(pattern), 1, true) then
                        return candidate.limb
                    end
                end
            end
        end
    end

    -- 2) ZCity / ValveBiped bone names ("ValveBiped.Bip01_L_Calf", ...).
    local limb = BoneLimb(name)
    if limb then return limb end

    -- 3) Body-level names without a side.
    if string.find(lower, "head") or string.find(lower, "skull") then return "head" end
    if string.find(lower, "spine2") or string.find(lower, "spine3")
        or string.find(lower, "chest") or string.find(lower, "rib") then return "thorax" end
    if string.find(lower, "spine1") or string.find(lower, "stomach")
        or string.find(lower, "abdomen") then return "abdomen" end
    if string.find(lower, "pelvis") or string.find(lower, "spine")
        or string.find(lower, "hip") then return "pelvis" end
    return NormalizeLimb(lower)
end

--- Build { limbId = bleeding 0..100 } from the actual ZCity wound tables.
-- These weights are shared by the shadow HUD, the bandage progress meter and
-- the actual treatment below.  Keeping one scale prevents a situation where
-- the UI says "100%" while a wound still has severity left in ply.organism.
local NORMAL_WOUND_BLEED = 2.0
local ARTERIAL_WOUND_BLEED = 3.0

local function ArterialWoundLimb(ply, wound)
    if type(wound) ~= "table" then return nil end
    local artery = type(wound[7]) == "string" and string.lower(wound[7]) or nil
    return (artery and (ARTERY_LIMB[artery] or NormalizeLimb((string.gsub(artery, "artery", "")))))
        or LimbFromBoneName(BoneNameOf(ply, wound[4]))
end

-- One anatomical routing rule for BOTH presentation and treatment.  A wound
-- on a missing forearm/calf still bleeds from the remaining upper arm/thigh;
-- bandage queries must therefore see exactly the same stump as LimbBleedMap.
-- The original wound bone/artery fields remain untouched.
local function AuthoritativeWoundLimb(org, limbId, limbs)
    limbId = NormalizeLimb(limbId) or limbId
    local stump = AMPUTATION_APPLICATION_SITE[limbId]
    local flag = stump and AMPUTATION_STUMP_FLAG[stump] or nil
    if not (type(org) == "table" and flag and org[flag] == true) then return limbId end

    -- During a ragdoll/net transition the organism flag may arrive before the
    -- native limb table.  If a distal state is explicitly still alive, keep
    -- its wound on that visible limb; once it is confirmed dismembered, route
    -- treatment to the stump.  With no limb table the organism is the fallback.
    local state = type(limbs) == "table" and limbs[limbId] or nil
    if type(state) == "table" and state.dismembered ~= true then return limbId end
    return stump
end

local function LimbBleedMap(ply, org)
    local map = {}
    local function add(limbId, amount)
        limbId = AuthoritativeWoundLimb(org, limbId)
        if not limbId or amount <= 0 then return end
        map[limbId] = (map[limbId] or 0) + amount
    end

    for _, w in pairs(org.wounds or {}) do
        if type(w) == "table" then
            local severity = math.max(tonumber(w[1]) or 0, 0)
            add(LimbFromBoneName(BoneNameOf(ply, w[4])), severity * NORMAL_WOUND_BLEED)
        end
    end
    for _, w in pairs(org.arterialwounds or {}) do
        if type(w) == "table" then
            local severity = math.max(tonumber(w[1]) or 0, 0)
            add(ArterialWoundLimb(ply, w), severity * ARTERIAL_WOUND_BLEED)
        end
    end
    return map
end
WSZC.LimbBleedMap = LimbBleedMap -- exported for diagnostics / headless tests

local function NormalBleedingOnLimb(ply, org, limbId)
    local h = H()
    local limbs = h and h.GetLimbs and h.GetLimbs(ply) or nil
    limbId = AuthoritativeWoundLimb(org, limbId, limbs)
    local total = 0
    for _, wound in pairs(org.wounds or {}) do
        if type(wound) == "table" and AuthoritativeWoundLimb(org,
            LimbFromBoneName(BoneNameOf(ply, wound[4])), limbs) == limbId then
            total = total + math.max(tonumber(wound[1]) or 0, 0) * NORMAL_WOUND_BLEED
        end
    end
    return total
end

local function ArterialBleedingOnLimb(ply, org, limbId)
    local h = H()
    local limbs = h and h.GetLimbs and h.GetLimbs(ply) or nil
    limbId = AuthoritativeWoundLimb(org, limbId, limbs)
    local total = 0
    for _, wound in pairs(org.arterialwounds or {}) do
        if type(wound) == "table" and AuthoritativeWoundLimb(org,
            ArterialWoundLimb(ply, wound), limbs) == limbId then
            total = total + math.max(tonumber(wound[1]) or 0, 0) * ARTERIAL_WOUND_BLEED
        end
    end
    return total
end

--- Actual NORMAL bleeding that a bandage may treat.  Arterial bleeding is a
--- separate rule: only a tourniquet can close it.  In authority mode never use
--- the 4 Hz C:U shadow for this value; progress must describe real wounds.
function WSZC.GetBandageBleeding(ply, limbId)
    local org = IsValid(ply) and ply.organism or nil
    if Authority() and type(org) == "table" then
        return NormalBleedingOnLimb(ply, org, limbId)
    end

    local h = H()
    local state = h and h.GetLimbState and h.GetLimbState(ply, limbId)
    return type(state) == "table" and math.max(tonumber(state.bleed) or 0, 0) or 0
end

function WSZC.GetArterialBleeding(ply, limbId)
    local org = IsValid(ply) and ply.organism or nil
    if not (Authority() and type(org) == "table") then return 0 end
    return ArterialBleedingOnLimb(ply, org, limbId)
end

local function CompactWoundTable(wounds)
    if type(wounds) ~= "table" then return end
    local entries = {}
    for key, wound in pairs(wounds) do
        if type(key) == "number" and type(wound) == "table" then
            local severity = tonumber(wound[1]) or 0
            -- A zero-severity managed wound is a closed treatment record, not
            -- garbage to recreate on the next tick.  Keep it until extraction
            -- or reset explicitly removes it; ordinary native zero wounds are
            -- still compacted exactly as before.
            local managedZero = severity <= 0
                and (wound.wszcShrapnel ~= nil or wound.wszcShrapnelExtraction ~= nil)
            if severity > 0 or managedZero then
                entries[#entries + 1] = { key = key, wound = wound }
            end
        end
    end
    table.sort(entries, function(a, b) return a.key < b.key end)
    for key in pairs(wounds) do wounds[key] = nil end
    for i, entry in ipairs(entries) do wounds[i] = entry.wound end
end

-- Negative C:U limb-bleed deltas are real treatment, not merely a different
-- HUD number.  Apply the same proportional reduction to the authoritative
-- ordinary and arterial wounds on that limb.  Bandages/tourniquets zero their
-- snapshot delta after their specialised treatment, so they never enter here.
local function ReduceLimbWoundBleeding(ply, org, limbId, amount)
    limbId = NormalizeLimb(limbId) or limbId
    amount = math.max(tonumber(amount) or 0, 0)
    if not limbId or amount <= 0.000001 or type(org) ~= "table" then return 0 end
    local normalBefore = NormalBleedingOnLimb(ply, org, limbId)
    local arterialBefore = ArterialBleedingOnLimb(ply, org, limbId)
    local total = normalBefore + arterialBefore
    if total <= 0.000001 then return 0 end

    local h = H()
    local limbs = h and h.GetLimbs and h.GetLimbs(ply) or nil
    local target = AuthoritativeWoundLimb(org, limbId, limbs)
    local scale = math.Clamp((total - amount) / total, 0, 1)
    for _, wound in pairs(org.wounds or {}) do
        if type(wound) == "table" and AuthoritativeWoundLimb(org,
            LimbFromBoneName(BoneNameOf(ply, wound[4])), limbs) == target then
            wound[1] = math.max((tonumber(wound[1]) or 0) * scale, 0)
            if wound[1] <= 0.000001 then wound[1] = 0 end
        end
    end
    for _, wound in pairs(org.arterialwounds or {}) do
        if type(wound) == "table" and AuthoritativeWoundLimb(org,
            ArterialWoundLimb(ply, wound), limbs) == target then
            wound[1] = math.max((tonumber(wound[1]) or 0) * scale, 0)
            if wound[1] <= 0.000001 then
                wound[1] = 0
                if type(wound[7]) == "string" then org[wound[7]] = 0 end
                if wound[7] == "arteria" and type(org.o2) == "table" then org.o2.regen = 0 end
            end
        end
    end
    CompactWoundTable(org.wounds)
    CompactWoundTable(org.arterialwounds)
    if ply.SetNetVar then
        pcall(ply.SetNetVar, ply, "wounds", org.wounds)
        pcall(ply.SetNetVar, ply, "arterialwounds", org.arterialwounds)
    end
    ply.fullsend = true
    return math.max(total - NormalBleedingOnLimb(ply, org, limbId)
        - ArterialBleedingOnLimb(ply, org, limbId), 0)
end
WSZC.ReduceLimbWoundBleeding = ReduceLimbWoundBleeding

-- ZCity wound schema is {severity, localPos:Vector, localAng:Angle, bone, time}.
-- Synthetic shrapnel wounds used to put nil in slots 2/3.  That is not a
-- harmless omission: native hg.RenderTourniquets() dereferences the saved
-- position with wound[1]:GetNegated() while drawing the character.  Always
-- create the real value types, and repair old in-memory/saved wounds on use.
local function NativeWoundPosition(value)
    if (isvector and isvector(value))
        or (type(value) == "table" and type(value.GetNegated) == "function") then
        return value
    end
    if Vector then return Vector(0, 0, 0) end
    return vector_origin
end

local function NativeWoundAngle(value)
    if isangle then
        if isangle(value) then return value end
    elseif value ~= nil and value ~= false then
        return value
    end
    if Angle then return Angle(0, 0, 0) end
    return angle_zero
end

local function NormalizeNativeWound(wound)
    if type(wound) ~= "table" then return nil end
    wound[2] = NativeWoundPosition(wound[2])
    wound[3] = NativeWoundAngle(wound[3])
    return wound
end

local function SyncBandagedWounds(ply, org, bandagedBones)
    local owner = IsValid(org.owner) and org.owner or ply
    local entities = { ply, owner, ply.FakeRagdoll }
    if hg and hg.GetCurrentCharacter then
        local ok, current = pcall(hg.GetCurrentCharacter, ply)
        if ok then entities[#entities + 1] = current end
    end

    local seen = {}
    for _, ent in ipairs(entities) do
        if IsValid(ent) and not seen[ent] then
            seen[ent] = true
            ent.bandaged_limbs = ent.bandaged_limbs or {}
            for bone in pairs(bandagedBones) do ent.bandaged_limbs[bone] = true end
            if ent.SetNetVar then
                pcall(ent.SetNetVar, ent, "wounds", org.wounds)
                pcall(ent.SetNetVar, ent, "arterialwounds", org.arterialwounds)
                pcall(ent.SetNetVar, ent, "bandaged_limbs", ent.bandaged_limbs)
            end
        end
    end
    ply.fullsend = true
end

--- A bandage may cover a fragment, but then the fragment is inaccessible until
--- that dressing is removed.  The map is authoritative and survives ragdoll;
--- C:U's isBandaged flag alone is insufficient because partial WSZC wraps do
--- not set it and native shrapnel extraction clears it on a failed grasp.
local COMPLICATION_BONES = {
    head = "ValveBiped.Bip01_Head1", neck = "ValveBiped.Bip01_Neck1",
    thorax = "ValveBiped.Bip01_Spine2",
    abdomen = "ValveBiped.Bip01_Spine1", pelvis = "ValveBiped.Bip01_Pelvis",
    arm_L = "ValveBiped.Bip01_L_UpperArm", forearm_L = "ValveBiped.Bip01_L_Forearm",
    hand_L = "ValveBiped.Bip01_L_Hand",
    arm_R = "ValveBiped.Bip01_R_UpperArm", forearm_R = "ValveBiped.Bip01_R_Forearm",
    hand_R = "ValveBiped.Bip01_R_Hand",
    thigh_L = "ValveBiped.Bip01_L_Thigh", crus_L = "ValveBiped.Bip01_L_Calf",
    foot_L = "ValveBiped.Bip01_L_Foot",
    thigh_R = "ValveBiped.Bip01_R_Thigh", crus_R = "ValveBiped.Bip01_R_Calf",
    foot_R = "ValveBiped.Bip01_R_Foot",
}

local SHRAPNEL_WOUND_TAG = "WSZC_LODGED_SHRAPNEL"

local function AuthoritativeShrapnelCount(ply, org, limbId)
    local n = org and org.wszc_shrapnel and tonumber(org.wszc_shrapnel[limbId]) or nil
    if n then return math.max(n, 0) end
    local h = H()
    local state = h and h.GetLimbState and h.GetLimbState(ply, limbId)
    return type(state) == "table" and math.max(tonumber(state.shrapnel) or 0, 0) or 0
end

function WSZC.IsShrapnelBandaged(ply, limbId)
    local org = IsValid(ply) and ply.organism or nil
    if type(org) ~= "table" or type(org.wszc_bandaged_shrapnel) ~= "table" then return false end
    local entry = org.wszc_bandaged_shrapnel[limbId]
    return type(entry) == "table" and entry.covered == true
        and AuthoritativeShrapnelCount(ply, org, limbId) > 0, entry
end

local INFECTION_EXTREMITY = {
    arm_L = true, forearm_L = true, hand_L = true,
    arm_R = true, forearm_R = true, hand_R = true,
    thigh_L = true, crus_L = true, foot_L = true,
    thigh_R = true, crus_R = true, foot_R = true,
}

function WSZC.MarkBandagedShrapnel(ply, limbId, bones)
    local org = IsValid(ply) and ply.organism or nil
    if type(org) ~= "table" or AuthoritativeShrapnelCount(ply, org, limbId) <= 0 then return false end
    org.wszc_bandaged_shrapnel = org.wszc_bandaged_shrapnel or {}
    local entry = org.wszc_bandaged_shrapnel[limbId] or { infection = 0, bones = {} }
    entry.covered = true
    entry.bones = entry.bones or {}
    for bone in pairs(bones or {}) do entry.bones[bone] = true end
    entry.infection = math.Clamp(tonumber(entry.infection) or 0, 0, 100)
    if INFECTION_EXTREMITY[limbId] and entry.infectionAge == nil then
        entry.infectionAge = 0
    end
    org.wszc_bandaged_shrapnel[limbId] = entry

    -- The external wound is really closed, not merely hidden in C:U.  A zero
    -- severity entry may subsequently be compacted away by NATIVE sv_blood;
    -- the independent organism marker survives that table.remove as well.
    org.wszc_shrapnel_closed = org.wszc_shrapnel_closed or {}
    org.wszc_shrapnel_closed[limbId] = true
    for _, wound in pairs(org.wounds or {}) do
        if type(wound) == "table" and wound.wszcShrapnel == SHRAPNEL_WOUND_TAG
            and wound.wszcLimb == limbId then wound[1] = 0 end
    end

    local h = H()
    local state = h and h.GetLimbState and h.GetLimbState(ply, limbId)
    if type(state) == "table" then
        state.wszcBandagedShrapnel = true
        -- Alginate/disinfectant normally leaves a "processing" icon.  A dirty
        -- fragment under a dressing is NOT disinfected: show only infection.
        state.disinfectTime = 0
    end
    if entry.infectionAge ~= nil and WSZC.TickBandagedShrapnel then
        WSZC.TickBandagedShrapnel(ply, org, 0)
    end
    if ply.SetNetVar then pcall(ply.SetNetVar, ply, "wounds", org.wounds) end
    ply.fullsend = true
    return true
end

---------------------------------------------------------------------------
-- Extraction aftercare: a separate, small wound that must be dressed again
---------------------------------------------------------------------------
local SHRAPNEL_EXTRACTION_TAG = "WSZC_SHRAPNEL_EXTRACTION"

local function RemoveExtractionWounds(org, limbId)
    if type(org) ~= "table" or type(org.wounds) ~= "table" then return false end
    local removed = false
    for key, wound in pairs(org.wounds) do
        if type(wound) == "table" and wound.wszcShrapnelExtraction == SHRAPNEL_EXTRACTION_TAG
            and (not limbId or wound.wszcLimb == limbId) then
            org.wounds[key] = nil
            removed = true
        end
    end
    if removed then CompactWoundTable(org.wounds) end
    return removed
end
WSZC.RemoveExtractionWounds = RemoveExtractionWounds

local function EnsureExtractionWound(ply, org, limbId)
    if type(org) ~= "table" then return nil end
    org.wounds = org.wounds or {}
    local closed = org.wszc_shrapnel_aftercare_closed
        and org.wszc_shrapnel_aftercare_closed[limbId] == true
    for _, wound in pairs(org.wounds) do
        if type(wound) == "table" and wound.wszcShrapnelExtraction == SHRAPNEL_EXTRACTION_TAG
            and wound.wszcLimb == limbId then
            if closed then wound[1] = 0 end
            return NormalizeNativeWound(wound)
        end
    end
    -- Native sv_blood removes zero wounds outright.  The organism-level marker
    -- keeps a partial dressing closed until the required FINAL dressing.
    if closed then return nil end
    local last = 0
    for key in pairs(org.wounds) do
        if type(key) == "number" and key > last then last = key end
    end
    local wound = NormalizeNativeWound({
        0.3, nil, nil, COMPLICATION_BONES[limbId] or COMPLICATION_BONES.hand_R,
        CurTime and CurTime() or 0,
    })
    wound.wszcShrapnelExtraction = SHRAPNEL_EXTRACTION_TAG
    wound.wszcLimb = limbId
    org.wounds[last + 1] = wound
    return wound
end

--- Called by SyncShrapnel for EVERY observed decrease, including extraction of
--- only one of several pieces.  The lodged source and this aftercare wound are
--- deliberately different tags, so removing a fragment cannot delete the new
--- bleeding on the same synchronisation pass.
function WSZC.StartShrapnelAftercare(ply, org, limbId, removed)
    if not (IsValid(ply) and type(org) == "table") then return false end
    removed = math.max(math.floor(tonumber(removed) or 1), 1)
    org.wszc_shrapnel_aftercare = org.wszc_shrapnel_aftercare or {}
    local entry = org.wszc_shrapnel_aftercare[limbId]
    if type(entry) ~= "table" then
        entry = { age = 0, extracted = 0, baseSeverity = 0.3 }
        org.wszc_shrapnel_aftercare[limbId] = entry
    end
    entry.extracted = (tonumber(entry.extracted) or 0) + removed
    entry.baseSeverity = math.min(1, (tonumber(entry.baseSeverity) or 0.3) + (removed - 1) * 0.1)
    entry.awaitingBandage = true
    -- This is a NEW extraction, not the next tick of an already clotted one.
    org.wszc_shrapnel_aftercare_closed = org.wszc_shrapnel_aftercare_closed or {}
    org.wszc_shrapnel_aftercare_closed[limbId] = nil
    local wound = EnsureExtractionWound(ply, org, limbId)
    wound[1] = math.max(tonumber(wound[1]) or 0, entry.baseSeverity)
    if ply.SetNetVar then pcall(ply.SetNetVar, ply, "wounds", org.wounds) end
    ply.fullsend = true
    return true
end

function WSZC.ShrapnelAftercarePending(ply, limbId)
    local org = IsValid(ply) and ply.organism or nil
    local entry = type(org) == "table" and org.wszc_shrapnel_aftercare
        and org.wszc_shrapnel_aftercare[NormalizeLimb(limbId) or limbId] or nil
    return type(entry) == "table" and entry.awaitingBandage == true
end

function WSZC.TickShrapnelAftercare(ply, org, dt)
    if not (IsValid(ply) and type(org) == "table")
        or type(org.wszc_shrapnel_aftercare) ~= "table" then return false end
    dt = math.Clamp(tonumber(dt) or 0.1, 0, 0.5)
    local changed = false
    local h = H()
    for limbId, entry in pairs(org.wszc_shrapnel_aftercare) do
        if type(entry) == "table" and entry.awaitingBandage then
            entry.age = math.max(tonumber(entry.age) or 0, 0) + dt
            local wound = EnsureExtractionWound(ply, org, limbId)
            -- Base severity 0.3, +0.015/s up to 6: noticeable but
            -- small compared with an untreated lodged fragment or an artery.
            -- Once a partial dressing has closed the external extraction
            -- wound, later ticks must not resurrect it just because another
            -- ordinary wound still needs bandaging.  Pain/age and the required
            -- FINAL dressing continue until FinishShrapnelAftercare().
            if wound and (tonumber(wound[1]) or 0) > 0 then
                wound[1] = math.min(6, math.max(tonumber(wound[1]) or 0,
                    (tonumber(entry.baseSeverity) or 0.3) + entry.age * 0.015))
            end
            if wound then wound[5] = CurTime and CurTime() or wound[5] end

            local painRate = 0.06
            org.painadd = math.Clamp((tonumber(org.painadd) or 0) + painRate * dt, 0, 150)
            org.avgpain = math.Clamp((tonumber(org.avgpain) or tonumber(org.pain) or 0)
                + painRate * 0.5 * dt, 0, 150)
            org.pain = math.Clamp((tonumber(org.pain) or 0) + painRate * 0.25 * dt, 0, 150)
            local state = h and h.GetLimbState and h.GetLimbState(ply, limbId)
            if type(state) == "table" then
                state.pain = math.Clamp((tonumber(state.pain) or 0) + 0.03 * dt, 0, 100)
            end
            changed = true
        else
            org.wszc_shrapnel_aftercare[limbId] = nil
        end
    end
    if changed then ply.fullsend = true end
    return changed
end

function WSZC.CompleteShrapnelAftercare(ply, org, limbId)
    if not (IsValid(ply) and type(org) == "table") then return false end
    local all = org.wszc_shrapnel_aftercare
    if type(all) ~= "table" or type(all[limbId]) ~= "table" then return false end
    all[limbId] = nil
    if type(org.wszc_shrapnel_aftercare_closed) == "table" then
        org.wszc_shrapnel_aftercare_closed[limbId] = nil
    end
    RemoveExtractionWounds(org, limbId)
    -- A dressing after PARTIAL extraction closes that extraction wound too,
    -- but the remaining covered fragments keep their infection timer.  Only
    -- dressing after the LAST fragment is a complete cure.
    if AuthoritativeShrapnelCount(ply, org, limbId) <= 0 and WSZC.ClearShrapnelInfection then
        WSZC.ClearShrapnelInfection(ply, org, limbId)
    end
    local h = H()
    local state = h and h.GetLimbState and h.GetLimbState(ply, limbId)
    if type(state) == "table" then
        state.wszcBandagedShrapnel = WSZC.IsShrapnelBandaged(ply, limbId)
        state.disinfectTime = 0
        if h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, limbId, true) end
    end
    if ply.SetNetVar then pcall(ply.SetNetVar, ply, "wounds", org.wounds) end
    ply.fullsend = true
    return true
end

--- Apply a C:U bandage dose to ordinary authoritative ZCity wounds.
---
--- C:U normally spends bandageSlowAmount in WoundSystem_LimbTick, reducing
--- limb.bleed by 1.25/s.  That timer is deliberately disabled in authority
--- mode, so merely mirroring the numeric C:U delta consumed the bandage but
--- never treated org.wounds.  Convert the SAME total clotting budget into an
--- immediate severity reduction on the selected limb instead.  Arterial
--- wounds are deliberately EXCLUDED: only ApplyTourniquetToOrganism may close
--- them.  The returned before/after values still include an untouched artery,
--- so the C:U shadow and the generic medical delta cannot hide or duplicate it.
---
--- Severity treated by effectFraction = 1 for this bandage profile.  The
--- external-minigame cost bridge uses the same function in reverse, so its
--- physical ZCity consumption can never drift from the real treatment math.
function WSZC.BandageSeverityPerFullEffect(profile)
    local effects = type(profile) == "table" and type(profile.effects) == "table"
        and profile.effects or {}
    local fullBudget = math.max(tonumber(effects.bandageSlowAmount) or 0, 0)
        + math.max(-(tonumber(effects.bleed) or 0), 0)
    return fullBudget * math.max(ConVarFloat(cvBandageStrength, 3), 0.01)
        / NORMAL_WOUND_BLEED
end

function WSZC.BandageSeverityOnLimb(ply, limbId)
    return math.max(tonumber(WSZC.GetBandageBleeding(ply, limbId)) or 0, 0)
        / NORMAL_WOUND_BLEED
end

--- Returns treatedAmount, beforeBleed, afterBleed in LimbBleedMap units.
function WSZC.ApplyBandageToOrganism(ctx, profile, effectFraction)
    local ply = ctx and ctx.ply
    local org = IsValid(ply) and ply.organism or nil
    if not (Authority() and type(org) == "table" and type(profile) == "table") then
        return 0, nil, nil
    end

    local limbId = NormalizeLimb(ctx.limbId) or ctx.limbId
    local normalBefore = WSZC.GetBandageBleeding(ply, limbId)
    local arterial = WSZC.GetArterialBleeding(ply, limbId)
    local before = normalBefore + arterial
    local h = H()
    local limbs = h and h.GetLimbs and h.GetLimbs(ply) or nil
    local budget = WSZC.BandageSeverityPerFullEffect(profile)
        * math.max(tonumber(effectFraction) or 0, 0) * NORMAL_WOUND_BLEED
    if budget <= 0 then return 0, before, before end

    local candidates = {}
    for _, wound in pairs(org.wounds or {}) do
        if type(wound) == "table" and (tonumber(wound[1]) or 0) > 0
            and AuthoritativeWoundLimb(org, LimbFromBoneName(BoneNameOf(ply, wound[4])), limbs) == limbId then
            candidates[#candidates + 1] = {
                wound = wound,
                weight = NORMAL_WOUND_BLEED,
                -- Treat the complication wound before unrelated native damage.
                -- Otherwise a large wound can consume every partial wrap while
                -- the lodged fragment keeps growing underneath it.
                priority = (wound.wszcShrapnel ~= nil or wound.wszcShrapnelExtraction ~= nil)
                    and 0 or 1,
            }
        end
    end
    table.sort(candidates, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return (tonumber(a.wound[1]) or 0) > (tonumber(b.wound[1]) or 0)
    end)

    local bandagedBones = {}
    for _, candidate in ipairs(candidates) do
        if budget <= 0.000001 then break end
        local wound, weight = candidate.wound, candidate.weight
        local severity = math.max(tonumber(wound[1]) or 0, 0)
        local reduction = math.min(severity, budget / weight)
        if reduction > 0 then
            wound[1] = math.max(severity - reduction, 0)
            budget = math.max(budget - reduction * weight, 0)
            if wound[1] <= 0 and wound.wszcShrapnel == SHRAPNEL_WOUND_TAG then
                org.wszc_shrapnel_closed = org.wszc_shrapnel_closed or {}
                org.wszc_shrapnel_closed[limbId] = true
            elseif wound[1] <= 0 and wound.wszcShrapnelExtraction == SHRAPNEL_EXTRACTION_TAG then
                org.wszc_shrapnel_aftercare_closed = org.wszc_shrapnel_aftercare_closed or {}
                org.wszc_shrapnel_aftercare_closed[limbId] = true
            end
            local bone = BoneNameOf(ply, wound[4])
            if type(bone) == "string" and bone ~= "" then bandagedBones[bone] = true end
        end
    end

    local normalAfter = WSZC.GetBandageBleeding(ply, limbId)
    local after = normalAfter + arterial
    local treated = math.max(normalBefore - normalAfter, 0)
    if treated <= 0.000001 then
        -- A clotted extraction wound still needs the FINAL dressing to finish
        -- the required unwrap -> extract -> re-bandage cycle.  Zero remaining
        -- severity must not make that last step a no-op with a fatal timer.
        local aftercarePending = org.wszc_shrapnel_aftercare
            and org.wszc_shrapnel_aftercare[limbId]
        if normalAfter <= 0.0001 and (AuthoritativeShrapnelCount(ply, org, limbId) > 0
            or aftercarePending) then
            local bone = COMPLICATION_BONES[limbId]
            if bone then bandagedBones[bone] = true end
            SyncBandagedWounds(ply, org, bandagedBones)
            WSZC.MarkBandagedShrapnel(ply, limbId, bandagedBones)
            WSZC.CompleteShrapnelAftercare(ply, org, limbId)
            if type(ctx.limb) == "table" then ctx.limb.isBandaged = after <= 0.0001 end
        end
        return 0, before, after
    end

    CompactWoundTable(org.wounds)
    normalAfter = WSZC.GetBandageBleeding(ply, limbId)
    after = normalAfter + arterial
    treated = math.max(normalBefore - normalAfter, 0)

    -- Update both authorities immediately.  ZCity's blood module will derive
    -- the exact rate from the reduced severity on its next tick; this small
    -- immediate adjustment simply avoids a one-tick delay in the HUD.
    org.bleed = math.max((tonumber(org.bleed) or 0) - treated * 0.2, 0)
    if type(ctx.limb) == "table" then
        ctx.limb.bleed = after
        -- WB.BestLimb skips isBandaged limbs.  C:U sets that flag merely
        -- after enough bandageSlowAmount, which would make a partially
        -- treated ZCity wound impossible to finish with a second roll.
        -- Keep it eligible until the REAL bleeding is completely closed.
        ctx.limb.isBandaged = after <= 0.0001
    end
    ply._WSZCExpectedBleed = ply._WSZCExpectedBleed or {}
    ply._WSZCExpectedBleed[limbId] = after
    SyncBandagedWounds(ply, org, bandagedBones)
    if normalAfter <= 0.0001 then
        WSZC.MarkBandagedShrapnel(ply, limbId, bandagedBones)
        WSZC.CompleteShrapnelAftercare(ply, org, limbId)
    end

    Debug("bandage treated %s/%s: %.3f -> %.3f (-%.3f)",
        tostring(ply), tostring(limbId), before, after, treated)
    return treated, before, after
end

---------------------------------------------------------------------------
-- Tourniquet: the ONLY treatment for arterial wounds
---------------------------------------------------------------------------

local TOURNIQUET_CLOT_TIME = 180 -- seconds before removal leaves the wound closed
local TOURNIQUET_DOWNSTREAM = {
    arm_R = { "arm_R", "forearm_R", "hand_R" },
    forearm_R = { "forearm_R", "hand_R" }, hand_R = { "hand_R" },
    arm_L = { "arm_L", "forearm_L", "hand_L" },
    forearm_L = { "forearm_L", "hand_L" }, hand_L = { "hand_L" },
    thigh_R = { "thigh_R", "crus_R", "foot_R" },
    crus_R = { "crus_R", "foot_R" }, foot_R = { "foot_R" },
    thigh_L = { "thigh_L", "crus_L", "foot_L" },
    crus_L = { "crus_L", "foot_L" }, foot_L = { "foot_L" },
}

-- Native ZCity has tourniquet offsets only for upper arm/forearm/thigh/calf.
-- Anchor the visual to the SELECTED application site, not to an arbitrary
-- downstream wound.  Hands/feet use their nearest supported proximal bone.
--- Redirect only a genuinely amputated group to its remaining stump.  On a
--- healthy limb the exact aimed forearm/hand/crus/foot remains unchanged.
function WSZC.TourniquetApplicationSite(ply, limbId)
    limbId = NormalizeLimb(limbId)
    if not limbId or not TOURNIQUET_DOWNSTREAM[limbId] then return nil end
    local org = IsValid(ply) and ply.organism or nil
    local stump = AMPUTATION_APPLICATION_SITE[limbId]
    local flag = stump and AMPUTATION_STUMP_FLAG[stump] or nil
    if type(org) == "table" and flag and org[flag] == true then return stump end
    return limbId
end

--- Native WB.BestLimb() skips EVERY dismembered limb and otherwise picks only
--- the largest bleed number.  In authority mode select from the real ZCity
--- wound map instead: a bleeding amputation stump is tier 1, every other
--- extremity is tier 0.  No synthetic bleed bonus is written to C:U state.
function WSZC.BestTourniquetLimb(ply, spec, preferred)
    local h = H()
    local limbs = h and h.GetLimbs and h.GetLimbs(ply) or nil
    local org = IsValid(ply) and ply.organism or nil
    if type(limbs) ~= "table" then return nil end
    local bleedMap = type(org) == "table" and LimbBleedMap(ply, org) or {}

    local function candidate(limbId, allowMissing)
        limbId = WSZC.TourniquetApplicationSite(ply, limbId)
        if not limbId then return nil end
        local state = limbs[limbId]
        if type(state) ~= "table" or state.tourniqueted then return nil end
        local flag = AMPUTATION_STUMP_FLAG[limbId]
        local amputated = flag ~= nil and type(org) == "table" and org[flag] == true
        if state.dismembered and not (amputated and allowMissing ~= false) then return nil end
        local bleed = math.max(tonumber(bleedMap[limbId]) or 0, 0)
        if type(org) ~= "table" then bleed = math.max(tonumber(state.bleed) or 0, 0) end
        if bleed <= 0.1 then return nil end
        return { id = limbId, tier = amputated and 1 or 0, bleed = bleed }
    end

    -- InstallMedicalBridge resolves self-use and ragdoll PhysicsBones before
    -- this function.  That exact site wins; only its amputated group is
    -- redirected to the anatomically remaining stump.
    local route = WSZC.TourniquetLimbOverride
    if type(route) == "table" and route.ply == ply then
        local selected = candidate(route.limbId)
        if selected then return selected.id end
    end
    if preferred then
        local selected = candidate(preferred)
        if selected then return selected.id end
    end

    local best
    for limbId, state in pairs(limbs) do
        if type(state) == "table" and TOURNIQUET_DOWNSTREAM[limbId] then
            local current = candidate(limbId)
            if current and (not best or current.tier > best.tier
                or (current.tier == best.tier and (current.bleed > best.bleed
                or (current.bleed == best.bleed and current.id < best.id)))) then
                best = current
            end
        end
    end
    return best and best.id or nil
end

--- Select a bandage target from the authoritative wounds, not C:U's 4 Hz
--- presentation shadow.  Native BestLimb skips every `isBandaged` limb and can
--- also select a damage-only shadow bleed for which org.wounds has no entry.
--- Both cases produce a session/progress UI with no treatable target.  A real
--- partially dressed wound must remain eligible until it is actually closed.
function WSZC.BestBandageLimb(ply, spec, preferred)
    local h = H()
    local limbs = h and h.GetLimbs and h.GetLimbs(ply) or nil
    local org = IsValid(ply) and ply.organism or nil
    if type(limbs) ~= "table" or type(org) ~= "table" then return nil end

    local bestId, bestScore
    local preferredSite = preferred and AuthoritativeWoundLimb(org, preferred, limbs) or nil
    for limbId, state in pairs(limbs) do
        if type(state) == "table" and not state.dismembered then
            local bleed = math.max(tonumber(NormalBleedingOnLimb(ply, org, limbId)) or 0, 0)
            local aftercare = org.wszc_shrapnel_aftercare
                and org.wszc_shrapnel_aftercare[limbId] ~= nil or false
            -- A zero-severity extraction wound still needs its FINAL dressing.
            -- Artery-only and damage-only shadow entries deliberately do not
            -- qualify: the former needs a tourniquet, the latter has no real
            -- bandage wound and used to make every input a no-op.
            if bleed > 0.1 or aftercare then
                local score = bleed + (aftercare and 0.2 or 0)
                    + (limbId == preferredSite and 1000 or 0)
                if not bestScore or score > bestScore
                    or (score == bestScore and limbId < bestId) then
                    bestId, bestScore = limbId, score
                end
            end
        end
    end
    return bestId
end

--- Replace only WB.SwepHeal's private BestLimb upvalue.  Syringes and
--- non-authority mode keep the stock function byte-for-byte.  Tourniquets use
--- the two-tier selector above; bandages use real normal-wound severity and
--- cannot be vetoed by a stale C:U isBandaged flag or phantom shadow bleed.
local patchedTourniquetSelectors = setmetatable({}, { __mode = "k" })
local function PatchTourniquetBestLimb(swepHeal)
    if type(swepHeal) ~= "function" then return false end

    local function Install(bestLimb, replace)
        if type(bestLimb) ~= "function" then return false end
        if patchedTourniquetSelectors[bestLimb] then return true end
        local wrapped = function(ply, spec, preferred)
            local isTourniquet = type(spec) == "table" and spec.kind == "apply"
                and string.upper(tostring(spec.item or "")) == "TOURNIQUET"
            local isBandage = type(spec) == "table" and spec.kind == "bandage"
            if Authority() and isTourniquet then
                return WSZC.BestTourniquetLimb(ply, spec, preferred)
            end
            if Authority() and isBandage then
                return WSZC.BestBandageLimb(ply, spec, preferred)
            end
            return bestLimb(ply, spec, preferred)
        end
        patchedTourniquetSelectors[wrapped] = true
        return replace(wrapped) == true
    end

    local wb = WB()
    if type(wb) == "table" and wb._WSZCEmbedded == true
        and type(wb._WSZCBridgeRefs) == "table"
        and type(wb._WSZCReplaceBestLimb) == "function" then
        return Install(wb._WSZCBridgeRefs.BestLimb, function(wrapped)
            return wb._WSZCReplaceBestLimb(swepHeal, wrapped)
        end)
    end

    if not (debug and debug.getupvalue and debug.setupvalue) then return false end
    for i = 1, 64 do
        local name, bestLimb = debug.getupvalue(swepHeal, i)
        if not name then break end
        if name == "BestLimb" and type(bestLimb) == "function" then
            return Install(bestLimb, function(wrapped)
                debug.setupvalue(swepHeal, i, wrapped)
                return true
            end)
        end
    end
    return false
end
WSZC.PatchTourniquetBestLimb = PatchTourniquetBestLimb

local TOURNIQUET_VISUAL_BONES = {
    arm_R = "ValveBiped.Bip01_R_UpperArm", forearm_R = "ValveBiped.Bip01_R_Forearm",
    hand_R = "ValveBiped.Bip01_R_Forearm",
    arm_L = "ValveBiped.Bip01_L_UpperArm", forearm_L = "ValveBiped.Bip01_L_Forearm",
    hand_L = "ValveBiped.Bip01_L_Forearm",
    thigh_R = "ValveBiped.Bip01_R_Thigh", crus_R = "ValveBiped.Bip01_R_Calf",
    foot_R = "ValveBiped.Bip01_R_Calf",
    thigh_L = "ValveBiped.Bip01_L_Thigh", crus_L = "ValveBiped.Bip01_L_Calf",
    foot_L = "ValveBiped.Bip01_L_Calf",
}

local function TotalMappedBleeding(map)
    local total = 0
    for _, value in pairs(map) do total = total + math.max(tonumber(value) or 0, 0) end
    return total
end

local function SyncTourniquetWounds(ply, org, visualWound, limbId)
    NormalizeNativeWound(visualWound)
    local visualBone = TOURNIQUET_VISUAL_BONES[limbId]
        or BoneNameOf(ply, visualWound[4])
    local owner = IsValid(org.owner) and org.owner or ply
    local entities = { ply, owner, ply.FakeRagdoll }
    if hg and hg.GetCurrentCharacter then
        local ok, current = pcall(hg.GetCurrentCharacter, ply)
        if ok then entities[#entities + 1] = current end
    end

    local seen = {}
    for _, ent in ipairs(entities) do
        if IsValid(ent) and not seen[ent] then
            seen[ent] = true
            ent.tourniquets = ent.tourniquets or {}
            ent.tourniquets[#ent.tourniquets + 1] = {
                visualWound[2], visualWound[3], visualBone,
            }
            if ent.SetNetVar then
                pcall(ent.SetNetVar, ent, "wounds", org.wounds)
                pcall(ent.SetNetVar, ent, "arterialwounds", org.arterialwounds)
                pcall(ent.SetNetVar, ent, "Tourniquets", ent.tourniquets)
            end
        end
    end

    -- Keep ZCity's own visual/user list in sync as well.  No second damage or
    -- healing system is introduced: this is the native tourniquet marker.
    if hg then
        hg.TourniquetGuys = hg.TourniquetGuys or {}
        local found = false
        for _, ent in ipairs(hg.TourniquetGuys) do
            if ent == owner then found = true break end
        end
        if not found then hg.TourniquetGuys[#hg.TourniquetGuys + 1] = owner end
        if SetNetVar then pcall(SetNetVar, "TourniquetGuys", hg.TourniquetGuys) end
    end
    ply.fullsend = true
end

--- Apply the native ZCity tourniquet rule to the affected limb and everything
--- below it.  One arterial wound is closed per tourniquet, matching ZCity;
--- ordinary wounds in the same downstream region are closed too.  Bandages
--- never call this function and can never clear org.<limb>artery.
function WSZC.ApplyTourniquetToOrganism(ctx)
    local ply = ctx and ctx.ply
    local org = IsValid(ply) and ply.organism or nil
    if not (Authority() and type(org) == "table") then return 0, nil, nil end

    local limbId = NormalizeLimb(ctx.limbId) or ctx.limbId
    -- One physical strap per application site.  Rejecting a second application
    -- before any mutation prevents both item loss and overwriting the first
    -- cycle's restorable wound references.  Remove, then reuse the returned
    -- SWEP if a new wound needs treatment under an existing strap.
    if ply._WSZCTourniquetCycles and ply._WSZCTourniquetCycles[limbId] then
        local value = LimbBleedMap(ply, org)[limbId] or 0
        return 0, value, value
    end
    local affected = {}
    for _, id in ipairs(TOURNIQUET_DOWNSTREAM[limbId] or { limbId }) do affected[id] = true end

    local beforeMap = LimbBleedMap(ply, org)
    local beforeTotal = TotalMappedBleeding(beforeMap)
    local cycle = {
        appliedAt = CurTime and CurTime() or 0,
        duration = TOURNIQUET_CLOT_TIME,
        affected = affected,
        arterial = {},
        ordinary = {},
        flags = {},
    }
    local arteries, ordinary = {}, {}
    for _, wound in pairs(org.arterialwounds or {}) do
        if type(wound) == "table" and (tonumber(wound[1]) or 0) > 0
            and affected[ArterialWoundLimb(ply, wound)] then
            arteries[#arteries + 1] = wound
        end
    end
    for _, wound in pairs(org.wounds or {}) do
        if type(wound) == "table" and (tonumber(wound[1]) or 0) > 0
            and affected[LimbFromBoneName(BoneNameOf(ply, wound[4]))] then
            ordinary[#ordinary + 1] = wound
        end
    end
    table.sort(arteries, function(a, b) return (a[1] or 0) > (b[1] or 0) end)

    local visualWound = arteries[1] or ordinary[1]
    if not visualWound then
        local value = beforeMap[limbId] or 0
        return 0, value, value
    end

    if arteries[1] then
        local wound = arteries[1]
        cycle.arterial[1] = { wound = wound, severity = tonumber(wound[1]) or 0 }
        if type(wound[7]) == "string" then
            cycle.flags[wound[7]] = org[wound[7]]
        end
        if wound[7] == "arteria" and type(org.o2) == "table" then
            cycle.o2regen = org.o2.regen
        end
        wound[1] = 0
        if type(wound[7]) == "string" then org[wound[7]] = 0 end
        if wound[7] == "arteria" and type(org.o2) == "table" then org.o2.regen = 0 end
    end
    for _, wound in ipairs(ordinary) do
        cycle.ordinary[#cycle.ordinary + 1] = { wound = wound, severity = tonumber(wound[1]) or 0 }
        wound[1] = 0
    end

    CompactWoundTable(org.wounds)
    CompactWoundTable(org.arterialwounds)
    local afterMap = LimbBleedMap(ply, org)
    local treated = math.max(beforeTotal - TotalMappedBleeding(afterMap), 0)
    if treated <= 0.000001 then
        local value = afterMap[limbId] or 0
        return 0, value, value
    end

    cycle.treated = treated
    ply._WSZCTourniquetCycles = ply._WSZCTourniquetCycles or {}
    ply._WSZCTourniquetCycles[limbId] = cycle

    org.bleed = math.max((tonumber(org.bleed) or 0) - treated * 0.2, 0)
    local h = H()
    ply._WSZCExpectedBleed = ply._WSZCExpectedBleed or {}
    for id in pairs(affected) do
        local state = h and h.GetLimbState and h.GetLimbState(ply, id)
        if type(state) == "table" then state.bleed = afterMap[id] or 0 end
        ply._WSZCExpectedBleed[id] = afterMap[id] or 0
    end
    SyncTourniquetWounds(ply, org, visualWound, limbId)

    Debug("tourniquet treated %s/%s: -%.3f bleeding", tostring(ply), tostring(limbId), treated)
    return treated, beforeMap[limbId] or 0, afterMap[limbId] or 0
end

local function RestoreTourniquetWoundList(wounds, backups)
    if type(wounds) ~= "table" or type(backups) ~= "table" then return end
    for _, entry in ipairs(backups) do
        local wound = entry.wound
        if type(wound) == "table" then
            -- Do not erase additional damage that arrived while the strap was
            -- on.  Restore at least the severity that was merely compressed.
            wound[1] = math.max(tonumber(wound[1]) or 0, tonumber(entry.severity) or 0)
            local present = false
            for _, current in pairs(wounds) do
                if current == wound then present = true break end
            end
            if not present then
                local last = 0
                for key in pairs(wounds) do
                    if type(key) == "number" and key > last then last = key end
                end
                wounds[last + 1] = wound
            end
        end
    end
end

local function RemoveTourniquetVisual(ply, org, limbId)
    local visualBone = TOURNIQUET_VISUAL_BONES[limbId]
    local entities = { ply, IsValid(org.owner) and org.owner or nil, ply.FakeRagdoll }
    if hg and hg.GetCurrentCharacter then
        local ok, current = pcall(hg.GetCurrentCharacter, ply)
        if ok then entities[#entities + 1] = current end
    end
    local seen = {}
    for _, ent in ipairs(entities) do
        if IsValid(ent) and not seen[ent] then
            seen[ent] = true
            if type(ent.tourniquets) == "table" then
                local kept = {}
                for _, marker in ipairs(ent.tourniquets) do
                    if type(marker) ~= "table" or marker[3] ~= visualBone then
                        kept[#kept + 1] = marker
                    end
                end
                ent.tourniquets = kept
                if ent.SetNetVar then pcall(ent.SetNetVar, ent, "Tourniquets", kept) end
            end
        end
    end
    if hg and type(hg.TourniquetGuys) == "table" then
        for i = #hg.TourniquetGuys, 1, -1 do
            local ent = hg.TourniquetGuys[i]
            if not IsValid(ent) or type(ent.tourniquets) ~= "table" or #ent.tourniquets == 0 then
                table.remove(hg.TourniquetGuys, i)
            end
        end
        if SetNetVar then pcall(SetNetVar, "TourniquetGuys", hg.TourniquetGuys) end
    end
end

local function MatureTourniquetCycle(cycle, now)
    if type(cycle) ~= "table" or cycle.mature then return false end
    now = tonumber(now) or (CurTime and CurTime() or 0)
    local elapsed = math.max(now - (tonumber(cycle.appliedAt) or now), 0)
    if elapsed < (tonumber(cycle.duration) or TOURNIQUET_CLOT_TIME) then return false end
    cycle.mature = true
    cycle.arterial, cycle.ordinary, cycle.flags = nil, nil, nil
    cycle.o2regen = nil
    return true
end

function WSZC.TickTourniquets(ply, org, dt)
    if not (Authority() and IsValid(ply) and type(org) == "table") then return false end
    local cycles = ply._WSZCTourniquetCycles
    if type(cycles) ~= "table" then return false end
    local now = CurTime and CurTime() or 0
    local h = H()
    local sync = now >= (ply._WSZCNextTourniquetSync or 0)
    if sync then ply._WSZCNextTourniquetSync = now + 1 end
    local changed = false

    for limbId, cycle in pairs(cycles) do
        local elapsed = math.max(now - (tonumber(cycle.appliedAt) or now), 0)
        local state = h and h.GetLimbState and h.GetLimbState(ply, limbId) or nil
        if type(state) == "table" then
            state.customStatuses = state.customStatuses or {}
            state.customStatuses.TOURNIQUET = math.max(elapsed, 0.01)
            if sync and h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, limbId, false) end
        end
        if MatureTourniquetCycle(cycle, now) then
            changed = true
            if not cycle.notified and ply.PrintMessage then
                cycle.notified = true
                pcall(ply.PrintMessage, ply, HUD_PRINTCENTER or 2,
                    "Tourniquet: 3 minutes passed - remove and reuse it")
            end
        end
    end
    return changed
end

--- Remove the strap and return ONE reusable ZCity SWEP.  Before 180 seconds
--- this also restores the compressed wounds; after clot time they stay closed.
function WSZC.RemoveTourniquet(ply, limbId)
    if not (Authority() and IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return false end
    local org = ply.organism
    if type(org) ~= "table" then return false end
    limbId = NormalizeLimb(limbId) or limbId
    local cycles = ply._WSZCTourniquetCycles
    local cycle = cycles and cycles[limbId] or nil
    if not cycle then
        local routed = WSZC.TourniquetApplicationSite(ply, limbId)
        if routed and cycles and cycles[routed] then limbId, cycle = routed, cycles[routed] end
    end
    if not limbId then return false end

    local h = H()
    local state = h and h.GetLimbState and h.GetLimbState(ply, limbId) or nil
    local active = cycle ~= nil or (type(state) == "table"
        and (state.tourniqueted == true or (type(state.customStatuses) == "table"
        and state.customStatuses.TOURNIQUET ~= nil)))
    if not active then return false end

    -- The click may arrive after 180 s but before the next Org Think.  Decide
    -- maturity from the authoritative timestamp here as well, never from only
    -- the last periodic tick.
    MatureTourniquetCycle(cycle)
    if cycle and not cycle.mature then
        RestoreTourniquetWoundList(org.arterialwounds, cycle.arterial)
        RestoreTourniquetWoundList(org.wounds, cycle.ordinary)
        for flag, value in pairs(cycle.flags or {}) do org[flag] = value == nil and 1 or value end
        if cycle.o2regen ~= nil and type(org.o2) == "table" then org.o2.regen = cycle.o2regen end
        org.bleed = math.Clamp((tonumber(org.bleed) or 0) + (tonumber(cycle.treated) or 0) * 0.2, 0, 200)
    end
    if cycles then cycles[limbId] = nil end

    if type(state) == "table" and WoundSystem and WoundSystem.Statuses
        and type(WoundSystem.Statuses.Clear) == "function" then
        pcall(WoundSystem.Statuses.Clear, state, "TOURNIQUET")
    end
    local affected = cycle and cycle.affected or nil
    if not affected then
        affected = {}
        for _, id in ipairs(TOURNIQUET_DOWNSTREAM[limbId] or { limbId }) do affected[id] = true end
    end
    local bleedMap = LimbBleedMap(ply, org)
    for id in pairs(affected) do
        local affectedState = h and h.GetLimbState and h.GetLimbState(ply, id) or nil
        if type(affectedState) == "table" then
            affectedState.tourniqueted = false
            affectedState.tourniquetPain = 0
            affectedState.tourniquetDurability = nil
            affectedState.tourniquetSourceSlot = nil
            if not affectedState.isBandaged then affectedState.blockedBleeding = false end
            affectedState.bleed = bleedMap[id] or 0
            if type(affectedState.customStatuses) == "table" then
                affectedState.customStatuses.TOURNIQUET = nil
            end
            ply._WSZCExpectedBleed = ply._WSZCExpectedBleed or {}
            ply._WSZCExpectedBleed[id] = affectedState.bleed
            if h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, id, true) end
        end
    end
    RemoveTourniquetVisual(ply, org, limbId)
    if ply.SetNetVar then
        pcall(ply.SetNetVar, ply, "wounds", org.wounds)
        pcall(ply.SetNetVar, ply, "arterialwounds", org.arterialwounds)
    end
    ply.fullsend = true

    -- The native receiver returns into C:U's hidden inventory. Authority mode
    -- uses real ZCity SWEPs, so return exactly one weapon_tourniquet instead.
    -- Self-removal returns it to the patient; remote removal temporarily sets
    -- the validated medic as recipient. Wound state always belongs to `ply`.
    local recipient = WSZC.RemoteMedicalReturnRecipient
    if not IsValid(recipient) then recipient = ply end
    if recipient.Give then
        local ok, swep = pcall(recipient.Give, recipient, "weapon_tourniquet")
        if not ok then
            Warn("could not return weapon_tourniquet: " .. tostring(swep))
        elseif IsValid(swep) and type(swep.modeValues) == "table" then
            swep.modeValues[1] = 1
            if swep.SetNetVar then pcall(swep.SetNetVar, swep, "modeValues", swep.modeValues) end
        end
    elseif h and type(h.ReturnAttachedMedicalItem) == "function" then
        pcall(h.ReturnAttachedMedicalItem, recipient, "TOURNIQUET", 100, nil)
    end
    return true
end

-- Preserve the original receiver for SPLINTED and for bridge mode.  Net reads
-- cannot be "unread", so replay the two already captured strings only for the
-- duration of that synchronous native call.
local function ReplayRemoveStatus(original, len, ply, limbId, rawStatus)
    if type(original) ~= "function" then return false end
    local readString = net.ReadString
    local values, index = { limbId, rawStatus }, 0
    net.ReadString = function()
        index = index + 1
        return values[index]
    end
    local ok, a, b, c = pcall(original, len, ply)
    net.ReadString = readString
    if not ok then
        Warn("native limb-status removal failed: " .. tostring(a))
        return nil
    end
    return a, b, c
end

function WSZC.InstallTourniquetRemovalBridge()
    if type(net) ~= "table" or type(net.Receivers) ~= "table" then return false end
    local name = "WoundSystem_RemoveLimbStatus"
    local current = net.Receivers[name]
    if current == WSZC._TourniquetRemovalWrapper then return current ~= nil end
    local original = current
    local function wrapped(len, ply)
        local limbId = net.ReadString()
        local rawStatus = net.ReadString()
        local statusId = string.upper(tostring(rawStatus or ""))
        if WoundSystem and type(WoundSystem.NormalizeItemId) == "function" then
            local ok, normalized = pcall(WoundSystem.NormalizeItemId, rawStatus)
            if ok and normalized then statusId = string.upper(tostring(normalized)) end
        elseif WSZC.NormalizeItemId then
            local ok, normalized = pcall(WSZC.NormalizeItemId, rawStatus)
            if ok and normalized then statusId = string.upper(tostring(normalized)) end
        end
        if Authority() and statusId == "TOURNIQUET" then
            return WSZC.RemoveTourniquet(ply, limbId)
        end
        return ReplayRemoveStatus(original, len, ply, limbId, rawStatus)
    end
    WSZC._OriginalRemoveLimbStatus = original
    WSZC._TourniquetRemovalWrapper = wrapped
    net.Receivers[name] = wrapped
    return true
end

---------------------------------------------------------------------------
-- Shrapnel minigame complications (pain + growing bleeding)
---------------------------------------------------------------------------
-- C:U's BreakShrapnelGrasp() adds state.bleed (+0.4..1.0) and state.pain
-- (+9..16) when the player yanks / re-impales a fragment.  Our PushShadow
-- used to overwrite those values from ply.organism every 250 ms, so nothing
-- ever bled.  Detect the unexpected jump and mirror it into the ZCity
-- organism: a real wound on that limb plus a rising irritation counter.

function WSZC.ApplyShrapnelComplication(ply, org, limbId, bleedDelta, painDelta)
    if not (IsValid(ply) and type(org) == "table") then return false end
    local h = H()
    local state = h and h.GetLimbState and h.GetLimbState(ply, limbId)
    if type(state) ~= "table" or (tonumber(state.shrapnel) or 0) <= 0 then return false end

    local now = CurTime and CurTime() or 0
    -- One mistake can be observed by several shadow ticks; collapse them.
    if (ply._WSZCLastComplication or 0) > (now - 0.4)
        and ply._WSZCLastComplicationLimb == limbId then return false end
    ply._WSZCLastComplication, ply._WSZCLastComplicationLimb = now, limbId

    bleedDelta = math.max(tonumber(bleedDelta) or 0, 0.4)
    painDelta = math.max(tonumber(painDelta) or 0, 8)

    org.wszc_shrapnel_irritation = org.wszc_shrapnel_irritation or {}
    local irritation = math.Clamp((tonumber(org.wszc_shrapnel_irritation[limbId]) or 0)
        + bleedDelta, 0, 20)
    org.wszc_shrapnel_irritation[limbId] = irritation

    org.pain = math.Clamp((tonumber(org.pain) or 0) + painDelta * 0.8, 0, 1000)
    org.bleed = math.Clamp((tonumber(org.bleed) or 0) + bleedDelta * 0.5, 0, 200)

    -- A real ZCity wound entry on the injured limb: LimbBleedMap() then shows
    -- the bleeding exactly there instead of on a random limb.
    org.wounds = org.wounds or {}
    -- ZCity clears wounds with `org.wounds[n] = nil`, so #org.wounds can point
    -- into a hole.  Append after the highest numeric index instead.
    local last = 0
    for key in pairs(org.wounds) do
        if type(key) == "number" and key > last then last = key end
    end
    local bone = COMPLICATION_BONES[limbId] or COMPLICATION_BONES[NormalizeLimb(limbId) or ""]
        or "ValveBiped.Bip01_R_Hand"
    org.wounds[last + 1] = NormalizeNativeWound({
        math.Clamp(irritation * 1.2, 4, 24), nil, nil, bone, now,
    })
    Debug("shrapnel complication on %s: bleed +%.2f pain +%.1f", tostring(limbId), bleedDelta, painDelta)
    return true
end

-- Resolve the player who owns a damaged player or fake ragdoll.  Damage never
-- accepts a dead owner; an explicit admin reset may also target a death ragdoll.
local function OwnerOf(ent, allowDead, skipNativeResolver)
    if not IsValid(ent) then return nil end
    if ent:IsPlayer() then return (allowDead or ent:Alive()) and ent or nil end
    local ragdollOwner = not skipNativeResolver and hg and hg.RagdollOwner or nil
    if ragdollOwner then
        local ok, ply = pcall(ragdollOwner, ent)
        if ok and IsValid(ply) and ply:IsPlayer() and (allowDead or ply:Alive()) then return ply end
    end

    -- hg.RagdollOwner() rejects a dead player.  The ragdoll's organism still
    -- points at that player, which is exactly what death-ragdoll reset needs.
    local entOrg = ent.organism
    local orgOwner = type(entOrg) == "table" and entOrg.owner or nil
    if IsValid(orgOwner) and orgOwner:IsPlayer() and (allowDead or orgOwner:Alive()) then
        return orgOwner
    end

    -- FakeRagdoll also stores the owner as an NW entity; some ZCity ragdolls
    -- (collision proxies, death ragdolls) have no `ragdoll.ply` Lua field.
    if ent.GetNWEntity then
        for _, key in ipairs({ "ply", "Owner", "RagdollOwner" }) do
            local ok, ply = pcall(ent.GetNWEntity, ent, key)
            if ok and IsValid(ply) and ply:IsPlayer() and (allowDead or ply:Alive()) then return ply end
        end
    end
    -- Do not scan every player's network vars for arbitrary map entities on
    -- damage paths. Reverse lookup is needed only for unresolved ragdolls;
    -- direct owner/organism/native links above remain the common fast paths.
    local reverseBodyLookup = allowDead
    if not reverseBodyLookup and ent.IsRagdoll then
        local ok, isRagdoll = pcall(ent.IsRagdoll, ent)
        reverseBodyLookup = ok and isRagdoll or false
    end
    if reverseBodyLookup then
        for _, ply in ipairs(player.GetAll()) do
            if allowDead or ply:Alive() then
                if ply.FakeRagdoll == ent or ply.DeathRagdoll == ent or ply.Ragdoll == ent then return ply end
                if ply.GetNWEntity then
                    for _, key in ipairs({ "FakeRagdoll", "WoundSystemUnconsciousRagdoll" }) do
                        local ok, ragdoll = pcall(ply.GetNWEntity, ply, key, NULL)
                        if ok and ragdoll == ent then return ply end
                    end
                end
            end
        end
    end
    return nil
end

-- Canonical WB.GetPlayer accepts only the exact current ZCity FakeRagdoll.
-- The connector also supports shared-organism/C:U proxies and network-only
-- fake links, so medicine must resolve those same living patients instead of
-- silently falling through to legacy SWEP code. Keep the native fast path and
-- add only verified owner/current-body/shared-organism links; dead players and
-- unrelated ragdolls remain rejected.
local function PatchBridgePlayerResolver(wb)
    if type(wb) ~= "table" or type(wb.GetPlayer) ~= "function" then return false end
    if wb._WSZCGetPlayerPatched then return true end
    local original = wb.GetPlayer
    wb._WSZCOriginalGetPlayer = original
    wb.GetPlayer = function(ent)
        if IsValid(ent) then
            local ok, ply = pcall(original, ent)
            if ok and IsValid(ply) and ply:IsPlayer() and ply:Alive() then return ply end
        end

        local ply = OwnerOf(ent)
        if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return nil end
        if ent == ply then return ply end

        local entOrg = ent.organism
        if type(entOrg) == "table" and entOrg == ply.organism and entOrg.owner == ply then
            return ply
        end
        if ply.FakeRagdoll == ent or ply.DeathRagdoll == ent or ply.Ragdoll == ent then return ply end
        if ply.GetNWEntity then
            for _, key in ipairs({ "FakeRagdoll", "WoundSystemUnconsciousRagdoll" }) do
                local ok, ragdoll = pcall(ply.GetNWEntity, ply, key, NULL)
                if ok and ragdoll == ent then return ply end
            end
        end
        if ent.GetNWEntity then
            for _, key in ipairs({ "ply", "WoundSystemOwner", "Owner", "RagdollOwner" }) do
                local ok, owner = pcall(ent.GetNWEntity, ent, key, NULL)
                if ok and owner == ply then return ply end
            end
        end
        return nil
    end
    wb._WSZCGetPlayerPatched = true
    return true
end
WSZC.PatchBridgePlayerResolver = PatchBridgePlayerResolver

---------------------------------------------------------------------------
-- The ONE shrapnel state
---------------------------------------------------------------------------

-- `state.shrapnel` is the single source of truth for the C:U panel and the
-- C:U shrapnel minigame.  `org.wszc_shrapnel` is a shadow copy so ZCity code
-- and the regeneration blocker can read it.  Neither table has a `source`.
local DEFAULT_MAX_PIECES = 5

-- GLASS keeps the owner's original four-point rule: both hands and both feet.
-- It is deliberately source-specific.  Shotgun pellets and blast fragments
-- remain on the actual resolved damage limb (including head/torso/limbs).
local GLASS_SHRAPNEL_LIMBS = {
    hand_R = true, hand_L = true,
    foot_R = true, foot_L = true,
}
local SHRAPNEL_MIN_PIECES = 3
local SHRAPNEL_MAX_PIECES = 5

-- Glass-only fallback onto the nearest circled limb of the same side.
-- Kept exported for compatibility with existing glass callers; AddShrapnel
-- must never apply this remap to shotgun or blast damage.
function WSZC.ShrapnelSpawnLimb(limbId)
    if type(limbId) ~= "string" then return "hand_R" end
    if GLASS_SHRAPNEL_LIMBS[limbId] then return limbId end
    local side = (string.sub(limbId, -2) == "_L") and "_L" or "_R"
    local lower = string.lower(limbId)
    if string.find(lower, "foot", 1, true) or string.find(lower, "crus", 1, true)
       or string.find(lower, "thigh", 1, true) or string.find(lower, "leg", 1, true) then
        return "foot" .. side
    end
    return "hand" .. side
end
local ShrapnelSpawnLimb = WSZC.ShrapnelSpawnLimb

-- The C:U protocol intentionally keeps ONE integer `state.shrapnel`, but the
-- authoritative organism records WHERE each fragment came from.  In
-- particular, shotgun fragments are a separate class: they can be created
-- only by InjectDamageShrapnel after a positive shotgun identification.
local SHRAPNEL_SOURCES = { "glass", "blast", "shotgun", "legacy" }

local function RecordShrapnelSource(org, limbId, source, amount)
    if amount <= 0 then return end
    if source ~= "shotgun" and source ~= "blast" and source ~= "glass" then source = "legacy" end
    org.wszc_shrapnel_sources = org.wszc_shrapnel_sources or {}
    local sources = org.wszc_shrapnel_sources[limbId] or {}
    sources[source] = math.max((tonumber(sources[source]) or 0) + amount, 0)
    org.wszc_shrapnel_sources[limbId] = sources
end

local function ConsumeShrapnelSource(org, limbId, amount)
    local byLimb = org.wszc_shrapnel_sources
    local sources = type(byLimb) == "table" and byLimb[limbId] or nil
    if type(sources) ~= "table" then return end
    for _, source in ipairs(SHRAPNEL_SOURCES) do
        if amount <= 0 then break end
        local n = math.min(tonumber(sources[source]) or 0, amount)
        sources[source] = math.max((tonumber(sources[source]) or 0) - n, 0)
        amount = amount - n
    end
    local left = false
    for _, n in pairs(sources) do if (tonumber(n) or 0) > 0 then left = true break end end
    if not left then byLimb[limbId] = nil end
end

local function RemoveLodgedWounds(org, limbId)
    if type(org) ~= "table" or type(org.wounds) ~= "table" then return false end
    local removed = false
    for key, wound in pairs(org.wounds) do
        if type(wound) == "table" and wound.wszcShrapnel == SHRAPNEL_WOUND_TAG
            and (not limbId or wound.wszcLimb == limbId) then
            org.wounds[key] = nil
            removed = true
        end
    end
    if removed then CompactWoundTable(org.wounds) end
    return removed
end
WSZC.RemoveLodgedWounds = RemoveLodgedWounds

local function EnsureLodgedWound(ply, org, limbId, count)
    if type(org) ~= "table" or (tonumber(count) or 0) <= 0 then return nil end
    org.wounds = org.wounds or {}
    local covered = WSZC.IsShrapnelBandaged and WSZC.IsShrapnelBandaged(ply, limbId) or false
    local closed = org.wszc_shrapnel_closed and org.wszc_shrapnel_closed[limbId] == true
    for _, wound in pairs(org.wounds) do
        if type(wound) == "table" and wound.wszcShrapnel == SHRAPNEL_WOUND_TAG
            and wound.wszcLimb == limbId then
            -- A dressing closes the EXTERNAL wound even though the fragment
            -- remains inside.  Infection is tracked separately; never let the
            -- lodged-wound synchroniser recreate bleeding under the bandage.
            if covered or closed then wound[1] = 0 end
            return NormalizeNativeWound(wound)
        end
    end
    if covered or closed then return nil end
    local last = 0
    for key in pairs(org.wounds) do
        if type(key) == "number" and key > last then last = key end
    end
    local wound = NormalizeNativeWound({
        math.Clamp(1.5 + count * 0.5, 2, 6), nil, nil,
        COMPLICATION_BONES[limbId] or COMPLICATION_BONES.hand_R,
        CurTime and CurTime() or 0,
    })
    wound.wszcShrapnel = SHRAPNEL_WOUND_TAG
    wound.wszcLimb = limbId
    org.wounds[last + 1] = wound
    if IsValid(ply) and ply.SetNetVar then pcall(ply.SetNetVar, ply, "wounds", org.wounds) end
    return wound
end

--- Active gauze work must be a winnable race, including when another player
--- bandages the patient.  This freezes only NEW shrapnel severity/pain growth:
--- existing blood loss, covered-shrapnel infection, unwrap and aftercare remain.
function WSZC.ShrapnelBandageInProgress(ply, limbId)
    if not IsValid(ply) then return false end
    for _, session in pairs(WSZC.MinigameSessions or {}) do
        if type(session) == "table" and session.kind == "bandage"
            and session.mode ~= "unwrap" and session.closed ~= true
            and session.target == ply
            and NormalizeLimb(session.limbId) == NormalizeLimb(limbId) then
            return true
        end
    end
    return false
end

--- Every lodged fragment hurts and opens a REAL ZCity wound.  Severity and
--- irritation grow with time and piece count; blood loss itself is then done
--- by ZCity's native sv_blood module, so the effect cannot be overwritten by
--- its next org.bleed recalculation.  Extraction removes this tagged wound.
function WSZC.TickLodgedShrapnel(ply, org, dt)
    if not (cvLodgedEffects and cvLodgedEffects:GetBool()) then return false end
    if not (IsValid(ply) and type(org) == "table") then return false end
    dt = math.Clamp(tonumber(dt) or 0.1, 0, 0.5)
    org.wszc_shrapnel_irritation = org.wszc_shrapnel_irritation or {}
    local changed = false
    for limbId, value in pairs(org.wszc_shrapnel or {}) do
        local count = math.max(tonumber(value) or 0, 0)
        if count > 0 then
            local covered = WSZC.IsShrapnelBandaged(ply, limbId)
            if covered then
                -- Keep the source closed, including after CompactWoundTable()
                -- removed its zero-severity entry.  Only the separate
                -- infection timer may progress while the fragment is covered.
                for _, wound in pairs(org.wounds or {}) do
                    if type(wound) == "table" and wound.wszcShrapnel == SHRAPNEL_WOUND_TAG
                        and wound.wszcLimb == limbId then wound[1] = 0 end
                end
            else
                local wound = EnsureLodgedWound(ply, org, limbId, count)
                if not WSZC.ShrapnelBandageInProgress(ply, limbId) then
                    local growth = 0.4
                    local irritation = math.Clamp(
                        (tonumber(org.wszc_shrapnel_irritation[limbId]) or 1) + count * dt * 0.012 * growth,
                        1, 20)
                    org.wszc_shrapnel_irritation[limbId] = irritation
                    if wound then
                        -- Zero is a deliberately clotted external wound.  Never
                        -- clamp it back to 0.5 or recreate it between partial
                        -- wraps; extraction alone removes the managed record.
                        local severity = math.max(tonumber(wound[1]) or 0, 0)
                        if severity > 0 then
                            wound[1] = math.Clamp(severity
                                + count * (0.018 + irritation * 0.002) * dt * growth, 0, 8)
                        end
                        wound[5] = CurTime and CurTime() or wound[5]
                    end
                    local painRate = count * (0.35 + irritation * 0.02)
                    org.avgpain = math.Clamp((tonumber(org.avgpain) or tonumber(org.pain) or 0)
                        + painRate * dt, 0, 150)
                    org.painadd = math.Clamp((tonumber(org.painadd) or 0)
                        + count * 0.08 * dt, 0, 150)
                    -- Immediate feedback too; avgpain/painadd above survive the
                    -- native pain module's next recomputation.
                    org.pain = math.Clamp((tonumber(org.pain) or 0) + painRate * 0.5 * dt, 0, 150)
                    changed = true
                end
            end
        end
    end
    if changed then ply.fullsend = true end
    return changed
end

WSZC.EnsureLodgedWound = EnsureLodgedWound

local function NotifyMedical(ply, text)
    if not IsValid(ply) then return end
    if ply.Notify then
        pcall(ply.Notify, ply, text, 45, "bandage", 0)
    elseif ply.PrintMessage then
        pcall(ply.PrintMessage, ply, HUD_PRINTCENTER or 4, text)
    end
end

--- Called ONLY after the reverse-bandage minigame completes.  Infection is
--- deliberately retained: unwrap alone is not a cure, and its timer keeps
--- running until extraction is followed by a complete re-bandage.
function WSZC.RemoveBandageForShrapnel(ply, limbId)
    local org = IsValid(ply) and ply.organism or nil
    if type(org) ~= "table" then return false end
    local covered, entry = WSZC.IsShrapnelBandaged(ply, limbId)
    if not covered then return false end
    entry.covered = false
    entry.reopenedAt = CurTime and CurTime() or 0
    -- Unwrapping intentionally reopens the managed external wounds.  New
    -- extraction/aftercare ticks may now recreate what native blood removed.
    if type(org.wszc_shrapnel_closed) == "table" then
        org.wszc_shrapnel_closed[limbId] = nil
    end
    if type(org.wszc_shrapnel_aftercare_closed) == "table" then
        org.wszc_shrapnel_aftercare_closed[limbId] = nil
    end

    local h = H()
    local state = h and h.GetLimbState and h.GetLimbState(ply, limbId)
    if type(state) == "table" then
        if h.Fn and h.Fn.ClearLimbBandage then pcall(h.Fn.ClearLimbBandage, state) end
        state.isBandaged, state.blockedBleeding = false, false
        state.bandageSlowAmount = 0
        state.wszcBandagedShrapnel = false
        state.infectionSpeed = 0
        if h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, limbId, true) end
    end

    local entities = { ply, org.owner, ply.FakeRagdoll }
    if hg and hg.GetCurrentCharacter then
        local ok, current = pcall(hg.GetCurrentCharacter, ply)
        if ok then entities[#entities + 1] = current end
    end
    local seen = {}
    for _, ent in ipairs(entities) do
        if IsValid(ent) and not seen[ent] then
            seen[ent] = true
            if type(ent.bandaged_limbs) == "table" then
                for bone in pairs(entry.bones or {}) do ent.bandaged_limbs[bone] = nil end
                if ent.SetNetVar then pcall(ent.SetNetVar, ent, "bandaged_limbs", ent.bandaged_limbs) end
            end
        end
    end

    local count = AuthoritativeShrapnelCount(ply, org, limbId)
    local wound = EnsureLodgedWound(ply, org, limbId, count)
    if wound then wound[1] = math.max(tonumber(wound[1]) or 0, 2.5) end
    org.bleed = math.max(tonumber(org.bleed) or 0, 0.5)
    ply.fullsend = true
    NotifyMedical(ply, "Bandage removed. Click REMOVE SHRAPNEL again.")
    return true
end

--- Infection is a server timer INDEPENDENT of the external wound.  Unwrapping
--- does not pause it and extraction alone does not cure it.  Only
--- CompleteShrapnelAftercare (extract -> fully re-bandage) removes the source.
local function SetShrapnelInfectionVisual(ply, h, entry, sourceLimb, limbId, amount)
    if not (h and h.GetLimbState) then return false end
    local state = h.GetLimbState(ply, limbId)
    if type(state) ~= "table" then return false end
    entry.infectedLimbs = entry.infectedLimbs or {}

    if amount == nil then
        if state._wszcShrapnelInfectionOwner ~= entry then return false end
        state.infection, state.infectionSpeed = 0, 0
        state._wszcShrapnelInfectionOwner = nil
        entry.infectedLimbs[limbId] = nil
        if h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, limbId, true) end
        return true
    end

    -- With several covered fragments the oldest infection owns a shared
    -- torso/head icon.  A younger source takes over on the next tick after the
    -- older one has completed aftercare.
    local owner = state._wszcShrapnelInfectionOwner
    if owner and owner ~= entry
        and (tonumber(owner.infectionAge) or 0) > (tonumber(entry.infectionAge) or 0) then
        return false
    end
    local changed = owner ~= entry
        or math.floor(tonumber(state.infection) or 0) ~= math.floor(amount)
    state.infection = math.Clamp(amount, 0, 100)
    -- Zero keeps C:U's own infection simulation from adding a second clock or
    -- spreading before our anatomical thresholds.  The stock neutral
    -- infection icon is latched at 25, so it is visible immediately.
    state.infectionSpeed = 0
    state.disinfectTime = 0
    state._wszcShrapnelInfectionOwner = entry
    entry.infectedLimbs[limbId] = true
    if limbId == sourceLimb then
        state.wszcBandagedShrapnel = entry.covered == true
            and AuthoritativeShrapnelCount(ply, ply.organism, sourceLimb) > 0
    end
    if changed and h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, limbId, false) end
    return changed
end

function WSZC.ClearShrapnelInfection(ply, org, limbId)
    local all = type(org) == "table" and org.wszc_bandaged_shrapnel or nil
    local entry = type(all) == "table" and all[limbId] or nil
    if type(entry) ~= "table" then return false end
    local h = H()
    for infectedLimb in pairs(entry.infectedLimbs or {}) do
        SetShrapnelInfectionVisual(ply, h, entry, limbId, infectedLimb, nil)
    end
    all[limbId] = nil
    local maxInfection = 0
    for _, other in pairs(all) do
        if type(other) == "table" then
            maxInfection = math.max(maxInfection, tonumber(other.infection) or 0)
        end
    end
    org.wszc_infection = maxInfection > 0 and maxInfection or nil
    return true
end

--- Default timeline (ConVar scales the whole sequence):
---   0..240 s  infected arm/leg, external bleeding remains bandaged off;
---   240 s     infection reaches the thorax;
---   420 s     infection reaches the brain;
---   600 s     fatal brain infection unless the complete aftercare cycle ended.
function WSZC.TickBandagedShrapnel(ply, org, dt)
    if not (IsValid(ply) and type(org) == "table") then return false end
    if type(org.wszc_bandaged_shrapnel) ~= "table" then return false end
    dt = math.Clamp(tonumber(dt) or 0.1, 0, 0.5)
    local enabled = not cvBandagedInfection or cvBandagedInfection:GetBool()
    local deathDelay = math.max(ConVarFloat(cvInfectionDeathDelay, 600), 1)
    local torsoAt, brainAt = deathDelay * 0.4, deathDelay * 0.7
    local maxInfection, changed = 0, false
    local h = H()

    for limbId, entry in pairs(org.wszc_bandaged_shrapnel) do
        if type(entry) ~= "table" then
            org.wszc_bandaged_shrapnel[limbId] = nil
        else
            local count = AuthoritativeShrapnelCount(ply, org, limbId)
            if entry.infectionAge == nil and entry.covered and count > 0
                and INFECTION_EXTREMITY[limbId] then entry.infectionAge = 0 end

            if entry.infectionAge ~= nil and INFECTION_EXTREMITY[limbId] then
                if enabled and not entry.terminal then
                    entry.infectionAge = math.max(tonumber(entry.infectionAge) or 0, 0) + dt
                end
                local age = math.max(tonumber(entry.infectionAge) or 0, 0)
                entry.infection = 25 + 74 * math.Clamp(age / deathDelay, 0, 1)
                maxInfection = math.max(maxInfection, entry.infection)

                local sourceAmount = age < torsoAt
                    and (25 + 64 * math.Clamp(age / math.max(torsoAt, 0.001), 0, 1)) or 89
                changed = SetShrapnelInfectionVisual(ply, h, entry, limbId, limbId, sourceAmount)
                    or changed

                if age >= torsoAt then
                    local torsoProgress = math.Clamp((age - torsoAt)
                        / math.max(brainAt - torsoAt, 0.001), 0, 1)
                    changed = SetShrapnelInfectionVisual(ply, h, entry, limbId,
                        "thorax", 25 + 64 * torsoProgress) or changed
                    if entry.stage ~= "torso" and entry.stage ~= "brain" and entry.stage ~= "terminal" then
                        entry.stage = "torso"
                        NotifyMedical(ply, "Infection has spread from the limb to the torso. Extract the fragment and re-bandage.")
                    end
                else
                    changed = SetShrapnelInfectionVisual(ply, h, entry, limbId, "thorax", nil)
                        or changed
                    entry.stage = "limb"
                end

                if age >= brainAt then
                    local brainProgress = math.Clamp((age - brainAt)
                        / math.max(deathDelay - brainAt, 0.001), 0, 1)
                    changed = SetShrapnelInfectionVisual(ply, h, entry, limbId,
                        "head", 25 + 74 * brainProgress) or changed
                    if entry.stage ~= "brain" and entry.stage ~= "terminal" then
                        entry.stage = "brain"
                        NotifyMedical(ply, "Infection has reached the brain. Complete extraction and re-bandaging immediately.")
                    end
                else
                    changed = SetShrapnelInfectionVisual(ply, h, entry, limbId, "head", nil)
                        or changed
                end

                if age >= deathDelay and enabled then
                    entry.terminal = true
                    entry.stage = "terminal"
                    org.brain = math.max(tonumber(org.brain) or 0, 1)
                    org.needfake = true
                    -- ZCity resets org.alive from owner:Alive() near the start
                    -- of every native Org Think, so a flag alone would be
                    -- overwritten before its death check.  Use the SAME
                    -- owner:Kill() call as that native check; all ordinary
                    -- death and ragdoll hooks therefore remain authoritative.
                    org.alive = false
                    if ply.Alive and ply:Alive() and ply.Kill then pcall(ply.Kill, ply) end
                    if not entry.terminalNotified then
                        entry.terminalNotified = true
                        NotifyMedical(ply, "The covered shrapnel infection has become fatal.")
                    end
                    changed = true
                end
            else
                entry.infection = math.Clamp(tonumber(entry.infection) or 0, 0, 100)
                maxInfection = math.max(maxInfection, entry.infection)
                local state = h and h.GetLimbState and h.GetLimbState(ply, limbId)
                if type(state) == "table" then
                    state.wszcBandagedShrapnel = entry.covered == true and count > 0
                end
            end
        end
    end

    org.wszc_infection = maxInfection > 0 and maxInfection or nil
    if changed then ply.fullsend = true end
    return changed
end

--- Native C:U owns this net message.  Reuse its own captured helpers, adding
--- only the covered-fragment gate BEFORE BuildShrapnelSession / tool cost.
--- A covered click starts the reverse-bandage minigame; it never unwraps or
--- removes a fragment by itself.  The next click follows native extraction.
function WSZC.InstallShrapnelBandageGuard()
    if not (net and net.Receive and WSZC.FindUpvalue) then return false end
    local receivers = net.Receivers or {}
    local original = receivers["WoundSystem_ShrapnelStart"]
        or receivers["woundsystem_shrapnelstart"]
    if type(original) ~= "function" then return false end
    if WSZC._ShrapnelBandageGuardOriginal == original then return true end

    local sessions = WSZC.CUSessions or WSZC.FindUpvalue("Sessions")
    local sendOpen = WSZC.FindUpvalue("SendShrapnelOpen")
    local closeSession = WSZC.CUCloseShrapnelSession or WSZC.FindUpvalue("CloseShrapnelSession")
    local buildSession = WSZC.FindUpvalue("BuildShrapnelSession")
    local hasTweezers = WSZC.FindUpvalue("ShrapnelItemHasTweezers")
    local consumeTool = WSZC.FindUpvalue("ConsumeToolDurability")
    local broadcast = WSZC.FindUpvalue("BroadcastMinigameOneShot")
    if not (type(sessions) == "table" and type(sessions.Shrapnel) == "table"
        and type(sendOpen) == "function" and type(closeSession) == "function"
        and type(buildSession) == "function" and type(hasTweezers) == "function"
        and type(consumeTool) == "function") then return false end

    local function GuardedShrapnelStart(_, ply)
        if type(WoundSystemHealthEnabled) == "function" and not WoundSystemHealthEnabled() then return end
        if not IsValid(ply) or not ply:Alive() then return end
        local limbId = net.ReadString()
        local slotIdx = 0
        if net.BytesLeft then
            local bytesLeft, bitsLeft = net.BytesLeft()
            if (bitsLeft or 0) >= 3 or (bytesLeft or 0) >= 1 then slotIdx = net.ReadUInt(3) end
        end

        if WSZC.IsShrapnelBandaged(ply, limbId) then
            -- Close a stale native overlay without BreakShrapnelGrasp, then
            -- open OUR reverse-bandage session.  No state changes happen here:
            -- only 360 accepted reverse degrees may call RemoveBandage...().
            if sessions.Shrapnel[ply] then closeSession(ply, "unwrap_started") end
            local started = WSZC.StartShrapnelUnwrap
                and WSZC.StartShrapnelUnwrap(ply, limbId)
            if not started then
                NotifyMedical(ply, "The reverse-bandage minigame is required before extraction.")
            end
            return -- no click unwrap, extraction session or tweezers cost
        end

        local existing = sessions.Shrapnel[ply]
        if existing then
            if existing.limbId == limbId then
                sendOpen(ply, existing)
                return
            end
            closeSession(ply, "replaced")
        end

        local h = H()
        local state = h and h.GetLimbState and h.GetLimbState(ply, limbId)
        if not state or (tonumber(state.shrapnel) or 0) <= 0 then return end
        local tweezers = hasTweezers(ply, slotIdx)
        if tweezers and not consumeTool(ply, slotIdx, 1) then return end
        local session = buildSession(limbId, state.shrapnel, tweezers)
        sessions.Shrapnel[ply] = session
        sendOpen(ply, session)
        if tweezers and type(broadcast) == "function" then
            broadcast(ply, "tweezeruse.ogg", 0.5)
        end
    end

    WSZC._OriginalShrapnelStart = original
    WSZC._ShrapnelBandageGuardOriginal = original
    net.Receive("WoundSystem_ShrapnelStart", GuardedShrapnelStart)
    return true
end

local function MaxShrapnel()
    local c = Constants()
    local n = tonumber(c and c.ShrapnelPieceCount) or 0
    return n > 0 and math.floor(n) or DEFAULT_MAX_PIECES
end

local function ShrapnelState(ply, limbId)
    local h = H()
    if not (h and h.GetLimbState) then return nil end
    local ok, state = pcall(h.GetLimbState, ply, limbId)
    if ok and type(state) == "table" then return state end
    return nil
end

--- Add lodged fragments.  The aggregate state is shared by the native
--- minigame; per-limb sources remain separate for reset/debug accounting.
--- Only glass uses ShrapnelSpawnLimb's four-point remap.  Shotgun and blast
--- damage keep the exact normalized limb resolved from hitgroup/HitBones.
function WSZC.AddShrapnel(ply, limbId, count, reason)
    if not Authority() then return false end
    if not (cvShrapnel and cvShrapnel:GetBool()) then return false end
    if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return false end
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return false end

    if reason == "glass" then
        limbId = ShrapnelSpawnLimb(limbId)
    else
        limbId = NormalizeLimb(limbId)
    end
    -- A real damage source with no resolved limb is skipped, never redirected
    -- to a hand/foot.  Glass alone retains its explicit fallback rule.
    if not limbId then return false end
    -- One hit leaves 3, 4 or 5 fragments (glass / shotgun = 3; a blast adds
    -- one per extra pellet = 4 or 5).  Deterministic, keeps the damage scaling,
    -- and never exceeds the C:U piece cap.
    local cap = math.min(SHRAPNEL_MAX_PIECES, MaxShrapnel())
    count = math.Clamp(count + 2, math.min(SHRAPNEL_MIN_PIECES, cap), cap)

    local h = H()
    if h and h.InitPlayer and h.GetLimbs and not h.GetLimbs(ply) then pcall(h.InitPlayer, ply) end

    local state = ShrapnelState(ply, limbId)
    if not state then
        if reason ~= "glass" then return false end
        -- Only glass may fall back to a circled limb while C:U initializes.
        state = ShrapnelState(ply, "hand_R")
        if not state then return false end
        limbId = "hand_R"
    end

    local before = math.floor(tonumber(state.shrapnel) or 0)
    local after = math.Clamp(before + count, 0, MaxShrapnel())
    if after == before then return false end

    state.shrapnel = after

    local org = ply.organism
    if type(org) == "table" then
        org.wszc_shrapnel = org.wszc_shrapnel or {}
        org.wszc_shrapnel[limbId] = after
        RecordShrapnelSource(org, limbId, reason, after - before)
        org.wszc_shrapnel_irritation = org.wszc_shrapnel_irritation or {}
        org.wszc_shrapnel_irritation[limbId] = math.max(
            tonumber(org.wszc_shrapnel_irritation[limbId]) or 0, 1)
        -- A NEW fragment is a new external injury unless the limb is already
        -- covered below.  Do not let the previous clot marker suppress it.
        org.wszc_shrapnel_closed = org.wszc_shrapnel_closed or {}
        org.wszc_shrapnel_closed[limbId] = nil
        local lodgedWound = EnsureLodgedWound(ply, org, limbId, after)
        if lodgedWound and not WSZC.IsShrapnelBandaged(ply, limbId)
            and (tonumber(lodgedWound[1]) or 0) <= 0 then
            lodgedWound[1] = math.Clamp(1.5 + after * 0.5, 2, 6)
        end
        -- A pellet can hit a limb that was dressed BEFORE the shot.  Such a
        -- fragment is covered too; otherwise pre-bandaging would bypass the
        -- unwrap -> extract cycle and the internal-infection consequence.
        local bone = COMPLICATION_BONES[limbId] or COMPLICATION_BONES.hand_R
        local dressed = state.isBandaged == true
            or (type(ply.bandaged_limbs) == "table" and ply.bandaged_limbs[bone] == true)
        if dressed then WSZC.MarkBandagedShrapnel(ply, limbId, { [bone] = true }) end
        -- Freeze ZCity limb regeneration at the state it had when the fragment
        -- lodged; extraction releases the floor again.
        if cvRegen and cvRegen:GetBool() then
            org.wszc_shrapnel_floor = org.wszc_shrapnel_floor or {}
            local map = LIMB_ORG[limbId]
            if map and map.dmg then
                org.wszc_shrapnel_floor[limbId] = tonumber(org[map.dmg]) or 0
            end
        end
    end

    if h and h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, limbId, true) end
    Debug("shrapnel +%d on %s (%s): %d -> %d", count, tostring(limbId), tostring(reason or "?"), before, after)
    return true
end

--- Put the fragments back into C:U from the ZCity organism.
--- C:U's InitPlayer() wipes PlayerLimbs[ply] on PlayerSpawn / ragdoll
--- transitions.  Since `ply.organism` is authoritative, the fragments must
--- survive that: "fell into a ragdoll and the shrapnel disappeared".
function WSZC.RestoreShrapnel(ply)
    if not (Authority() and IsValid(ply)) then return 0 end
    local org = ply.organism
    if type(org) ~= "table" or type(org.wszc_shrapnel) ~= "table" then return 0 end
    local h = H()
    local limbs = h and h.GetLimbs and h.GetLimbs(ply)
    if type(limbs) ~= "table" then return 0 end

    local restored = 0
    for limbId, value in pairs(org.wszc_shrapnel) do
        local n = math.floor(tonumber(value) or 0)
        if n > 0 then
            local state = limbs[limbId]
            if type(state) ~= "table" and h.GetLimbState then
                -- InitPlayer() may have left an empty table for a frame.
                local ok, created = pcall(h.GetLimbState, ply, limbId)
                if ok then state = created end
            end
            if type(state) == "table" and math.floor(tonumber(state.shrapnel) or 0) ~= n then
                state.shrapnel = math.Clamp(n, 0, MaxShrapnel())
                if h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, limbId, true) end
                restored = restored + 1
            end
            if type(state) == "table" then
                org.wszc_shrapnel_irritation = org.wszc_shrapnel_irritation or {}
                org.wszc_shrapnel_irritation[limbId] = math.max(
                    tonumber(org.wszc_shrapnel_irritation[limbId]) or 0, 1)
                EnsureLodgedWound(ply, org, limbId, n)
                if not (org.wszc_shrapnel_sources and org.wszc_shrapnel_sources[limbId]) then
                    RecordShrapnelSource(org, limbId, "legacy", n)
                end
            end
        end
    end
    ply._WSZCLimbsRef = limbs
    return restored
end

--- Bidirectional sync.  A NEW PlayerLimbs table means C:U reset its limb
--- state (ragdoll / spawn transition) and we must RESTORE from the organism,
--- not pull the empty table back into it.  On the SAME table a lower value is
--- a real extraction from the shrapnel minigame, so the organism follows C:U.
local function SyncShrapnel(ply, org)
    local h = H()
    if not (h and h.GetLimbs) then return end
    local limbs = h.GetLimbs(ply)
    if type(limbs) ~= "table" then return end
    org.wszc_shrapnel = org.wszc_shrapnel or {}
    org.wszc_shrapnel_floor = org.wszc_shrapnel_floor or {}

    if ply._WSZCLimbsRef ~= limbs then
        -- A NEW PlayerLimbs table means C:U rebuilt its limb state (spawn /
        -- ragdoll transition).  Re-assert the organism shadow FIRST.  Do NOT
        -- copy the fresh (possibly empty) table back into the organism on this
        -- same tick: that is exactly what erased the fragments when the player
        -- stood up from the ragdoll.  The next tick sees a known table and
        -- resumes normal bidirectional sync.
        WSZC.RestoreShrapnel(ply)
        WSZC.RestoreBones(ply)
        ply._WSZCLimbsRef = limbs
        return
    end

    for limbId, state in pairs(limbs) do
        if type(state) == "table" then
            local n = math.floor(tonumber(state.shrapnel) or 0)
            local previous = tonumber(org.wszc_shrapnel[limbId]) or 0
            if previous ~= n then
                org.wszc_shrapnel[limbId] = n
                if n < previous then
                    ConsumeShrapnelSource(org, limbId, previous - n)
                    -- Native C:U has already decremented state.shrapnel.  Keep
                    -- a NEW extraction wound even when the last lodged wound
                    -- is removed below; infection also remains until dress-up.
                    WSZC.StartShrapnelAftercare(ply, org, limbId, previous - n)
                end
                if n <= 0 then
                    org.wszc_shrapnel_floor[limbId] = nil
                    if org.wszc_shrapnel_sources then org.wszc_shrapnel_sources[limbId] = nil end
                    if org.wszc_shrapnel_irritation then org.wszc_shrapnel_irritation[limbId] = nil end
                    if org.wszc_shrapnel_closed then org.wszc_shrapnel_closed[limbId] = nil end
                    local bandaged = org.wszc_bandaged_shrapnel and org.wszc_bandaged_shrapnel[limbId]
                    if type(bandaged) == "table" then bandaged.covered = false end
                    if RemoveLodgedWounds(org, limbId) and ply.SetNetVar then
                        pcall(ply.SetNetVar, ply, "wounds", org.wounds)
                    end
                else
                    EnsureLodgedWound(ply, org, limbId, n)
                end
            end
        end
    end
end
WSZC.SyncShrapnel = SyncShrapnel
local PullShrapnel = SyncShrapnel -- keep the old internal name working

---------------------------------------------------------------------------
-- Bones: dislocations / fractures stay in the ZCity organism
---------------------------------------------------------------------------
-- ZCity's vanilla sv_bone.lua is the ONLY source of truth for bones:
--   org.larmdislocation / org.rarmdislocation / org.llegdislocation /
--   org.rlegdislocation = true  -> joint out of the socket
--   org.larm / org.rarm / org.lleg / org.rleg >= 1 -> the bone is broken
--   org.brokenribs > 0 -> fractured ribs (thorax)
-- C:U only draws the WoundView icons and runs the manual reduction minigame.
-- The three C:U limbs of one arm/leg share ONE ZCity flag, exactly like
-- WB.Sync()'s AnyDislocated() did.  But only the anchor limb (one above the
-- fracture's middle limb) is MARKED, so a successful reduction on THAT limb
-- clears the whole ZCity group.  Listing all three here would let a stale
-- false on a non-anchor limb be mistaken for a manual reduction.
local DISLOC_FLAGS = {
    larmdislocation = { "arm_L" },
    rarmdislocation = { "arm_R" },
    llegdislocation = { "thigh_L" },
    rlegdislocation = { "thigh_R" },
}

--- C:U multiplies this by DislocationStartSpread = 5 to place the bone away
--- from the socket.  At 100 the bone lands up to ~660 sim units above the
--- finish point and is literally off the top of the screen ("why are they so
--- high, I can't click the bone"), and the reduction needs a huge number of
--- hits.  35 keeps one short, reachable drag.
local function DislocationStartTimer()
    local v = cvDislocationStart and cvDislocationStart:GetFloat() or 35
    return math.Clamp(v, 10, 100)
end
WSZC.DislocationStartTimer = DislocationStartTimer

-- ZCity writes a full break as org[key] = 1.  Regeneration (sv_pain.lua) and
-- ZCity medical SWEPs then bring it back down; 0.85 keeps the fracture icon
-- visible while the bone is still essentially broken.
local FRACTURE_DAMAGE = 0.85

local function Fractured(org, limbId, map)
    -- Only the middle limb of an arm/leg owns the fracture icon.  Otherwise
    -- one org.larm >= 0.85 would mark arm, forearm AND hand at once.
    if not BoneAnchor(limbId, "fracture") then return false end
    if limbId == "thorax" and (tonumber(org.brokenribs) or 0) > 0 then return true end
    return (tonumber(org[map and map.dmg]) or 0) >= FRACTURE_DAMAGE
end
WSZC.Fractured = Fractured -- exported for headless tests

--- True when the organism has at least one joint out of its socket.
function WSZC.AnyDislocation(org)
    if type(org) ~= "table" then return false end
    for flag in pairs(DISLOC_FLAGS) do
        if org[flag] == true then return true end
    end
    return false
end

--- True while C:U's native manual-reduction minigame session is open.
function WSZC.DislocationActive(ply)
    local sessions = WSZC.CUSessions
    return type(sessions) == "table" and type(sessions.Dislocation) == "table"
        and sessions.Dislocation[ply] ~= nil
end

--- Restore bone state from ply.organism after C:U InitPlayer() replaced the
--- PlayerLimbs table (ragdoll / spawn).  Called from RestoreShrapnelSoon().
function WSZC.RestoreBones(ply)
    if not (Authority() and IsValid(ply)) then return false end
    local org = ply.organism
    if type(org) ~= "table" then return false end
    local h = H()
    if WSZC.EnsureNeckState then pcall(WSZC.EnsureNeckState, ply) end
    if WSZC.EnsurePelvisState then pcall(WSZC.EnsurePelvisState, ply) end
    local limbs = h and h.GetLimbs and h.GetLimbs(ply)
    if type(limbs) ~= "table" then return false end

    -- C:U InitPlayer() also resets dismembered/customStatuses.  Re-assert the
    -- native amputation anatomy together with fractures/dislocations on every
    -- ragdoll transition instead of waiting for the next 4 Hz shadow pass.
    SyncAmputationShadow(org, limbs)
    if WSZC.SyncInternalBleedingShadow then WSZC.SyncInternalBleedingShadow(org, limbs) end
    ply._WSZCExpectedDislocation = ply._WSZCExpectedDislocation or {}
    for limbId, map in pairs(LIMB_ORG) do
        local state = limbs[limbId]
        if type(state) ~= "table" and h.GetLimbState then
            local ok, created = pcall(h.GetLimbState, ply, limbId)
            if ok then state = created end
        end
        if type(state) == "table" then
            -- Dislocation lives on the limb ABOVE the fracture's middle
            -- limb, and nowhere else.  A non-anchor limb is always healthy.
            local out = map.dis and BoneAnchor(limbId, "dislocation")
                and org[map.dis] == true or false
            state.dislocated = out
            state.dislocationTimer = out and DislocationStartTimer() or 0
            local fractured = map.dmg ~= nil and Fractured(org, limbId, map) or false
            state.broken = fractured
            -- C:U stores REMAINING fracture time: ApplyFracture starts at 100
            -- and healing decreases it to zero.  ZCity damage has the same
            -- direction (healthy 0 -> fully broken 1), so do not invert it.
            state.boneHealTimer = fractured and math.Clamp(
                (tonumber(org[map.dmg]) or 0) * 100, 0, 100) or 0
            ply._WSZCExpectedDislocation[limbId] = out
            if h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, limbId, true) end
        end
    end
    return true
end

--- Bidirectional sync.  On a NEW PlayerLimbs table we restore from the
--- organism.  On the SAME table, a `dislocated -> false` change that we did
--- not write came from C:U (the manual reduction minigame, or its heal timer)
--- and must clear the ZCity flag.  Without this the 4 Hz shadow would put the
--- joint straight back into its socket and the minigame could never succeed.
function WSZC.SyncDislocation(ply, org, limbs, newLimbTable)
    if type(limbs) ~= "table" then return false end
    ply._WSZCExpectedDislocation = ply._WSZCExpectedDislocation or {}

    if newLimbTable then
        return WSZC.RestoreBones(ply)
    end

    local changed = false
    for flag, names in pairs(DISLOC_FLAGS) do
        if org[flag] == true then
            local reduced = false
            for _, id in ipairs(names) do
                local state = limbs[id]
                if type(state) == "table"
                    and ply._WSZCExpectedDislocation[id] == true
                    and state.dislocated ~= true then
                    reduced = true
                    break
                end
            end
            if reduced then
                org[flag] = false
                -- ZCity's own fixlimb()/FixDislocatedGroup() charge pain for a
                -- reduction; keep that structure instead of C:U happiness.
                org.painadd = (tonumber(org.painadd) or 0) + 10
                ply.fullsend = true
                changed = true
            end
        end
    end
    return changed
end

-- DisableCUPhysiology removes WoundSystem_LimbTick, which is also where the
-- native SPLINTED status expires and multiplies bone/joint recovery.  Preserve
-- JUST that item contract here; do not restart C:U's general health tick.
-- Fracture acceleration is an addition to ZCity's own sv_pain regeneration:
-- baseline + 1.5 * baseline = the native splint multiplier 2.5.  At damage 1
-- vanilla regeneration is gated off, and the splint supplies the 2.5 rate that
-- starts recovery.  Joint recovery uses C:U's 0.07 * 2 timer rate and then the
-- ordinary SyncDislocation path clears the authoritative ZCity flag.
function WSZC.TickSplints(ply, org, dt)
    if not (Authority() and IsValid(ply) and type(org) == "table") then return false end
    local h = H()
    local limbs = h and h.GetLimbs and h.GetLimbs(ply) or nil
    if type(limbs) ~= "table" then return false end
    dt = math.max(tonumber(dt) or 0, 0)
    if dt <= 0 then return false end
    local changed, active = false, {}
    local now = CurTime and CurTime() or 0

    for limbId, map in pairs(LIMB_ORG) do
        local state = limbs[limbId]
        if type(state) == "table" then
            local statuses = state.customStatuses
            local durability = type(statuses) == "table" and tonumber(statuses.SPLINTED) or nil
            local expired = false
            if durability ~= nil then
                durability = math.max(durability - dt * 0.025, 0)
                if durability <= 0 then
                    statuses.SPLINTED = nil
                    state.splinted = false
                    expired = true
                    changed = true
                else
                    statuses.SPLINTED = durability
                end
            end

            if state.splinted == true and not state.dismembered then
                active[#active + 1] = limbId
                if map.dmg and BoneAnchor(limbId, "fracture") and state.broken == true then
                    local damage = math.Clamp(tonumber(org[map.dmg]) or 0, 0, 1)
                    local amputated = map.amp and org[map.amp] == true or false
                    if damage > 0 and not amputated then
                        local nativeStep = damage < 1 and dt / 240 or 0
                        local extra = nativeStep > 0 and nativeStep * 1.5 or dt / 240 * 2.5
                        org[map.dmg] = math.max(damage - extra, 0)
                        ply.fullsend = true
                        changed = true
                    end
                end
                if BoneAnchor(limbId, "dislocation") and state.dislocated == true then
                    local timerValue = math.max((tonumber(state.dislocationTimer) or 0)
                        - dt * 0.07 * 2, 0)
                    state.dislocationTimer = timerValue
                    if timerValue <= 0 then state.dislocated = false end
                    changed = true
                end
            end

            if expired and h.SendLimbUpdate then
                pcall(h.SendLimbUpdate, ply, limbId, true)
            end
        end
    end

    -- Durability is a native net status.  A 1 Hz refresh is enough for its
    -- very slow 0.025/s wear and avoids sending every 10 Hz organism tick.
    if #active > 0 and h.SendLimbUpdate and now >= (ply._WSZCNextSplintSync or 0) then
        ply._WSZCNextSplintSync = now + 1
        for _, limbId in ipairs(active) do pcall(h.SendLimbUpdate, ply, limbId, false) end
    end
    return changed
end

-- ZCity's `hg.Fake` / `hg.FakeUp` fire when the character drops into / gets
-- up from the unconscious ragdoll.  Re-assert the fragments immediately and
-- once more after every ragdoll hook has run (C:U may reset limbs there).
local function RestoreShrapnelSoon(ply)
    if not (OrganismHooksActive() and IsValid(ply) and ply.IsPlayer and ply:IsPlayer()) then return end
    -- Tell WSZC_OrganismSpawn that this PlayerSpawn is a ragdoll -> standing
    -- transition, NOT a respawn.  Without the marker GMod's undefined hook
    -- order could clear the organism shadow before we re-attach it.
    ply._WSZCRagdollTransitionUntil = (CurTime and CurTime() or 0) + 5
    ply._WSZCSpawnKind = "ragdoll"
    timer.Simple(0, function()
        WSZC.RestoreShrapnel(ply)
        WSZC.RestoreBones(ply)
    end)
    timer.Simple(0.3, function()
        WSZC.RestoreShrapnel(ply)
        WSZC.RestoreBones(ply)
    end)
end
WSZC.RestoreShrapnelSoon = RestoreShrapnelSoon
hook.Add("Fake", "WSZC_ShrapnelRagdollKeep", function(ply) RestoreShrapnelSoon(ply) end)
-- Server ZCity emits "Fake Up" immediately BEFORE its internal ply:Spawn();
-- client ZCity uses "FakeUp".  Listen to both names, never just the client one.
hook.Add("Fake Up", "WSZC_ShrapnelRagdollKeep", function(ply) RestoreShrapnelSoon(ply) end)
hook.Add("FakeUp", "WSZC_ShrapnelRagdollKeep", function(ply) RestoreShrapnelSoon(ply) end)
hook.Add("HG_OnWakeOtrub", "WSZC_ShrapnelRagdollKeep", function(ply) RestoreShrapnelSoon(ply) end)

-- PlayerDeath always precedes ZCity's PostPlayerDeath organism copy/Clear.
-- Do not erase the injuries here (the corpse still needs them); only retire
-- transition markers so a fast respawn cannot inherit a five-second FakeUp
-- preservation window from the previous life.
hook.Add("PlayerDeath", "WSZC_RagdollTransitionDeath", function(ply)
    if not IsValid(ply) then return end
    ply._WSZCRagdollTransitionUntil = nil
    ply._WSZCShrapnelCarry = nil
    ply._WSZCSpawnKind = "genuine"
end)

---------------------------------------------------------------------------
-- Damage-derived shrapnel (gunshot / blast), moved out of C:U
---------------------------------------------------------------------------

-- `EntityTakeDamage` hooks run in an undefined order and ZCity scales the
-- damage by 0.15 inside takeRagdollDamage().  The homigrad-damage wrapper
-- records the unscaled value so the blast thresholds stay faithful to C:U.
WSZC.RawDamage = WSZC.RawDamage or setmetatable({}, { __mode = "k" })

local function HevBlocks(ply)
    local chance = WoundSystem and WoundSystem.HEVGetShrapnelBlockChance
    if type(chance) ~= "function" then return false end
    local ok, value = pcall(chance, ply)
    if not ok then return false end
    value = tonumber(value) or 0
    return value > 0 and math.random() < value
end

local BONE_HITGROUPS = {
    ["ValveBiped.Bip01_Head1"] = HITGROUP_HEAD,
    ["ValveBiped.Bip01_Spine2"] = HITGROUP_CHEST,
    ["ValveBiped.Bip01_Spine1"] = HITGROUP_STOMACH,
    ["ValveBiped.Bip01_Pelvis"] = HITGROUP_GEAR,
    ["ValveBiped.Bip01_L_Hand"] = HITGROUP_LEFTARM,
    ["ValveBiped.Bip01_R_Hand"] = HITGROUP_RIGHTARM,
    ["ValveBiped.Bip01_L_Foot"] = HITGROUP_LEFTLEG,
    ["ValveBiped.Bip01_R_Foot"] = HITGROUP_RIGHTLEG,
    -- The original table only had hands/feet for limbs, so a thigh or calf hit
    -- resolved to whichever foot bone happened to be nearest.
    ["ValveBiped.Bip01_L_Thigh"] = HITGROUP_LEFTLEG,
    ["ValveBiped.Bip01_R_Thigh"] = HITGROUP_RIGHTLEG,
    ["ValveBiped.Bip01_L_Calf"] = HITGROUP_LEFTLEG,
    ["ValveBiped.Bip01_R_Calf"] = HITGROUP_RIGHTLEG,
    ["ValveBiped.Bip01_L_UpperArm"] = HITGROUP_LEFTARM,
    ["ValveBiped.Bip01_R_UpperArm"] = HITGROUP_RIGHTARM,
    ["ValveBiped.Bip01_L_Forearm"] = HITGROUP_LEFTARM,
    ["ValveBiped.Bip01_R_Forearm"] = HITGROUP_RIGHTARM,
}

-- ZCity traces the ragdoll for a bone, but the C:U hook only sees a damage
-- position.  Pick the closest limb bone so shrapnel lands on a plausible limb.
local function GuessHitgroup(ent, dmginfo)
    if IsValid(ent) and ent.LastHitGroup then
        local ok, hg = pcall(ent.LastHitGroup, ent)
        if ok and hg and HITGROUP_LIMB[hg] then return hg end
    end
    local pos = dmginfo and dmginfo.GetDamagePosition and dmginfo:GetDamagePosition()
    if not (pos and isvector(pos) and IsValid(ent) and ent.LookupBone and ent.GetBonePosition) then return nil end
    local best, bestDist
    for name, hitgroup in pairs(BONE_HITGROUPS) do
        local ok, b = pcall(ent.LookupBone, ent, name)
        if ok and b then
            local ok2, bp = pcall(ent.GetBonePosition, ent, b)
            if ok2 and bp and isvector(bp) then
                local d = (bp - pos):LengthSqr()
                if not bestDist or d < bestDist then bestDist, best = d, hitgroup end
            end
        end
    end
    -- Never guess "somewhere" from a far-away damage position: a far hit used
    -- to pick an arbitrary nearest bone (a leg hit could lodge in a hand).
    if best and bestDist and bestDist <= (55 * 55) then return best end
    return nil
end

local function LimbFromHitgroup(hitgroup)
    if not hitgroup then return nil end
    local wb = WB()
    local limb = wb and wb.HitgroupToWS and wb.HitgroupToWS[hitgroup]
    limb = NormalizeLimb(limb) or NormalizeLimb(HitgroupLimb(hitgroup))
    -- HITGROUP_GENERIC / HITGROUP_GEAR must NOT turn into an arbitrary thorax.
    return limb
end

-- ZCity records every hit in org.dmgstack[hitgroup] = { amount, CurTime(), ... }
-- inside its own damage hook.  This is the authoritative limb for the hit,
-- unlike dmginfo:GetDamagePosition() (bullet entry point, often on a different
-- ragdoll bone).  Read the freshest entry only, so old wounds do not win.
local function FreshHitgroup(org)
    if type(org) ~= "table" or type(org.dmgstack) ~= "table" then return nil end
    local now = CurTime and CurTime() or 0
    local best, bestTime
    for hitgroup, stack in pairs(org.dmgstack) do
        if type(stack) == "table" and (tonumber(stack[1]) or 0) > 0 then
            local t = tonumber(stack[2]) or 0
            if (now - t) < 1.0 and (not bestTime or t > bestTime) then
                bestTime, best = t, hitgroup
            end
        end
    end
    return best
end

-- ply.HitBones[bonename] = CurTime() + damage is filled by ZCity for the
-- hitgroup's bones.  Secondary source, still exact for the injured limb.
local function LimbFromHitBones(ply)
    if not (IsValid(ply) and type(ply.HitBones) == "table") then return nil end
    local now = CurTime and CurTime() or 0
    local best, bestExpiry
    for bonename, expiry in pairs(ply.HitBones) do
        local n = tonumber(expiry) or 0
        if type(bonename) == "string" and n > now then
            local limb = NormalizeLimb(BoneLimb(bonename))
            if limb and (not bestExpiry or n > bestExpiry) then
                bestExpiry, best = n, limb
            end
        end
    end
    return best
end

--- Resolve the EXACT limb that was hit.  Returning nil means "unknown" and the
--- caller SKIPS the fragment -- shrapnel must never appear "somewhere random".
local function DamageLimb(ply, ent, dmginfo, hitgroup)
    local limb = LimbFromHitgroup(hitgroup)
    if limb then return limb end

    if IsValid(ply) and ply.LastHitGroup then
        local ok, hg = pcall(ply.LastHitGroup, ply)
        if ok then limb = LimbFromHitgroup(hg) end
        if limb then return limb end
    end

    local org = IsValid(ply) and ply.organism or nil
    limb = LimbFromHitgroup(FreshHitgroup(org))
    if limb then return limb end

    limb = LimbFromHitBones(ply)
    if limb then return limb end

    -- Last resort: the damage position must really be on the bone.
    return LimbFromHitgroup(GuessHitgroup(ent, dmginfo))
end

--- Shrapnel may come from SHOTGUNS or EXPLOSIONS only -- never from a pistol.
---
--- ZCity's custom bullet engine (sh_luabullets.lua) calls
--- `info:SetDamageType(tAmmoData.dmgtype)`, but the 12/70 gauge / slug ammo
--- definitions in sh_ammostuff.lua have `dmgtype` COMMENTED OUT.  Shotgun
--- pellets therefore arrive as DMG_GENERIC (0).  `info:SetAmmoType()` IS
--- always set, so the ammo name is the reliable identifier.  The old check
--- also accepted plain DMG_BULLET and any "NxM mm" rifle/pistol calibre,
--- which is exactly why pistols produced fragments.
local SHOTGUN_AMMO = {
    ["12/70gauge"] = true, ["12/70slug"] = true, ["12/70rip"] = true,
    ["12/70beanbag"] = true, ["12/70blank"] = true,
    ["20/70gauge"] = true, ["20/70slug"] = true,
}

-- Calibre families used by ZCity's shotgun SWEPs (xm1014, spas12, saiga12,
-- remington870, roullet, doublebarrel_short and the KS-23 style 23x75).
local function IsShotgunAmmoName(name)
    if type(name) ~= "string" then return false end
    local lower = string.lower(name)
    local compact = string.gsub(lower, "%s+", "")
    if SHOTGUN_AMMO[compact] then return true end
    return string.find(compact, "12/70", 1, true) == 1
        or string.find(compact, "20/70", 1, true) == 1
        or string.find(compact, "23x75", 1, true) == 1
        or string.find(lower, "buckshot", 1, true) ~= nil
        or string.find(lower, "shotgun", 1, true) ~= nil
end

local SHOTGUN_WEAPONS = {
    weapon_xm1014 = true, weapon_spas12 = true, weapon_saiga12 = true,
    weapon_remington870 = true, weapon_remington870_roullet = true,
    weapon_doublebarrel = true, weapon_doublebarrel_short = true,
    weapon_ks23 = true, weapon_m590a1 = true, weapon_toz106 = true,
}

local function IsShotgunEntity(ent)
    if not IsValid(ent) then return false end
    local ok, class = pcall(ent.GetClass, ent)
    class = ok and string.lower(tostring(class or "")) or ""
    if SHOTGUN_WEAPONS[class] then return true end
    -- Physical ZCity bullets do not retain their weapon as inflictor.  Keep
    -- family fallbacks for derived SWEP class names used by server packs.
    if string.find(class, "shotgun", 1, true)
        or string.find(class, "spas12", 1, true)
        or string.find(class, "xm1014", 1, true)
        or string.find(class, "saiga12", 1, true)
        or string.find(class, "remington870", 1, true)
        or string.find(class, "doublebarrel", 1, true)
        or string.find(class, "ks23", 1, true)
        or string.find(class, "m590", 1, true) then return true end

    local primary = type(ent.Primary) == "table" and ent.Primary or nil
    if primary and IsShotgunAmmoName(primary.Ammo) then return true end
    if ent.GetPrimaryAmmoType and game and game.GetAmmoName then
        local okAmmo, ammoId = pcall(ent.GetPrimaryAmmoType, ent)
        if okAmmo and type(ammoId) == "number" and ammoId >= 0 then
            local okName, name = pcall(game.GetAmmoName, ammoId)
            if okName and IsShotgunAmmoName(name) then return true end
        end
    end

    -- Different ZCity generations store pellet count in these fields.  A
    -- multi-pellet weapon is positive evidence even when ammo is already -1.
    return (tonumber(ent.NumBullet) or 0) > 1
        or (primary and (tonumber(primary.NumBullets or primary.NumBullet) or 0) > 1)
        or false
end

local function IsShotgunHit(dmginfo, dmgtype)
    -- zc_woundsystem_compat_shrapnel_only_shotgun_blast 0 restores the old
    -- "any bullet" behaviour for servers that want it back.
    if cvShotgunOnly and not cvShotgunOnly:GetBool() then
        local bullet = DMG_BULLET or 0
        local buckshot = DMG_BUCKSHOT or 0
        return (bullet ~= 0 and bit.band(dmgtype, bullet) ~= 0)
            or (buckshot ~= 0 and bit.band(dmgtype, buckshot) ~= 0)
    end

    -- DMG_BUCKSHOT alone is NOT enough: a custom pistol/SWEP can set that bit.
    -- Require the shotgun ammo name or a real multi-pellet/known shotgun
    -- weapon below, otherwise no fragment is created.
    if dmginfo.GetAmmoType and game and game.GetAmmoName then
        local ok, ammoId = pcall(dmginfo.GetAmmoType, dmginfo)
        if ok and type(ammoId) == "string" and IsShotgunAmmoName(ammoId) then return true end
        if ok and type(ammoId) == "number" and ammoId >= 0 then
            local ok2, name = pcall(game.GetAmmoName, ammoId)
            if ok2 and IsShotgunAmmoName(name) then return true end
        end
    end

    local inf = dmginfo.GetInflictor and dmginfo:GetInflictor()
    if IsShotgunEntity(inf) then return true end
    local att = dmginfo.GetAttacker and dmginfo:GetAttacker()
    if IsShotgunEntity(att) then return true end
    if IsValid(att) and att.GetActiveWeapon then
        local ok, wep = pcall(att.GetActiveWeapon, att)
        if ok and IsShotgunEntity(wep) then return true end
    end
    return false
end

-- A single CTakeDamageInfo may reach PostEntityTakeDamage twice: once for the
-- player (ZCity returns true and redirects to the fake ragdoll) and once for
-- that ragdoll.  Weak keys avoid leaking and avoid a second fragment.
WSZC.ShrapnelHandled = WSZC.ShrapnelHandled or setmetatable({}, { __mode = "k" })

--- Unified damage injector.  No `source` field, no per-source session.
function WSZC.InjectDamageShrapnel(ent, dmginfo, hitgroup, rawOverride)
    if not Authority() then return end
    if not (cvShrapnel and cvShrapnel:GetBool()) then return end
    if not (IsValid(ent) and dmginfo) then return end
    if WSZC.ShrapnelHandled[dmginfo] then return end

    -- Do NOT mark an unresolved proxy hit as handled.  ZCity can deliver the
    -- same CTakeDamageInfo to npc_bullseye first and to the real player/ragdoll
    -- immediately afterwards; marking here used to suppress the real wound.
    local ply = OwnerOf(ent)
    if not ply then return end

    local dmgtype = dmginfo.GetDamageType and dmginfo:GetDamageType() or 0
    -- Dissolve / godmode hits are not wounds.
    if (DMG_DISSOLVE or 0) ~= 0 and bit.band(dmgtype, DMG_DISSOLVE) ~= 0 then return end
    local org = ply.organism
    if type(org) == "table" and org.godmode then return end

    local raw = rawOverride
    if raw == nil then raw = WSZC.RawDamage[dmginfo] end
    if raw == nil then raw = dmginfo.GetDamage and dmginfo:GetDamage() or 0 end
    raw = tonumber(raw) or 0

    local limbId = DamageLimb(ply, ent, dmginfo, hitgroup)
    if not limbId then
        Debug("shrapnel skipped: no reliable injured limb for %s", tostring(ent))
        return
    end

    -- Only a resolved player + limb consumes this DamageInfo.  From here on a
    -- duplicate player/ragdoll callback must not roll the HEV chance twice.
    WSZC.ShrapnelHandled[dmginfo] = true
    local shotgunAdded, blastAdded = 0, 0

    -- One separate shotgun fragment group per confirmed SHOTGUN hit only
    -- (HEV can block it).  Pistols / rifles / SMGs deliberately produce none.
    local blast = DMG_BLAST or 0
    if IsShotgunHit(dmginfo, dmgtype) and not HevBlocks(ply) then
        shotgunAdded = 1
    end

    -- C:U's DMG_BLAST branch: fragment shower scaled by raw damage on
    -- non-critical limbs only.
    if blast ~= 0 and bit.band(dmgtype, blast) ~= 0 then
        local h = H()
        local critical = (limbId == "head" or limbId == "thorax" or limbId == "abdomen")
        if not critical and h and h.Fn and h.Fn.IsCriticalLimb then
            local ok, v = pcall(h.Fn.IsCriticalLimb, limbId)
            if ok then critical = v == true end
        end
        if not critical then
            local frags = 0
            if raw >= 20 and math.random() < 0.6 then frags = frags + 1 end
            if raw >= 40 and math.random() < 0.5 then frags = frags + 1 end
            if raw >= 70 and math.random() < 0.4 then frags = frags + 1 end
            blastAdded = frags
        end
    end

    if shotgunAdded > 0 then WSZC.AddShrapnel(ply, limbId, shotgunAdded, "shotgun") end
    if blastAdded > 0 then WSZC.AddShrapnel(ply, limbId, blastAdded, "blast") end
end

---------------------------------------------------------------------------
-- Glass shrapnel: hands / feet on glass, standing and in the fake ragdoll
---------------------------------------------------------------------------

local glassCooldown = {}

local function GlassLimbFromBone(ent, bone)
    if not (IsValid(ent) and ent.GetBoneName) then return nil end
    local bonename
    if isnumber(bone) and ent.TranslatePhysBoneToBone then
        local ok, name = pcall(ent.GetBoneName, ent, ent:TranslatePhysBoneToBone(bone))
        if ok then bonename = name end
    else
        bonename = bone
    end
    return BoneLimb(bonename)
end

local function InjectGlass(ply, limbId, bone)
    if not (cvGlass and cvGlass:GetBool()) then return end
    limbId = limbId or GlassLimbFromBone(ply.FakeRagdoll, bone) or "hand_R"

    local now = CurTime and CurTime() or 0
    local key = tostring(ply) .. "/" .. tostring(limbId)
    if (glassCooldown[key] or 0) > now then return end
    glassCooldown[key] = now + 0.5 -- matches ZCity's lasttouched throttle
    WSZC.AddShrapnel(ply, limbId, 1, "glass")
end

-- A collision counts as glass EITHER by surfaceprop OR by the brush entity
-- itself.  In a fake ragdoll the hand/foot phys object often reports the
-- default surfaceprop from the world side, so relying on TheirSurfaceProps
-- alone made ragdoll glass hits register never.
local function IsGlassCollision(data)
    if util and util.GetSurfacePropName and data["TheirSurfaceProps"] ~= nil then
        local ok, name = pcall(util.GetSurfacePropName, data["TheirSurfaceProps"])
        if ok and GLASS_SURFACES[name] then return true end
    end
    local hit = data.HitEntity
    if not IsValid(hit) then return false end
    local ok, class = pcall(hit.GetClass, hit)
    if not ok or type(class) ~= "string" then return false end
    local lower = string.lower(class)
    if lower == "func_breakable_surf" then return true end
    if not string.find(lower, "break", 1, true) then return false end
    if hit.GetMaterialType and hit:GetMaterialType() == (MAT_GLASS or 0) then return true end
    if hit.GetBrushSurfaces then
        local ok2, surfaces = pcall(hit.GetBrushSurfaces, hit)
        if ok2 and type(surfaces) == "table" and surfaces[1] then
            local ok3, mat = pcall(function()
                return surfaces[1]:GetMaterial():GetName()
            end)
            if ok3 and type(mat) == "string" and string.find(string.lower(mat), "glass", 1, true) then
                return true
            end
        end
    end
    return false
end

-- Ragdoll Collide: a hand/foot phys object striking glass while the player is
-- in the fake ragdoll.  Registered as its own hook (not as a WrapHook `pre`)
-- so it also fires when ZCity's "organism" hook is missing or re-registered.
local function RagdollGlassShrapnel(ragdoll, data)
    if not (OrganismHooksActive() and cvGlass and cvGlass:GetBool()) then return end
    if not (IsValid(ragdoll) and type(data) == "table") then return end
    if ragdoll == data.HitEntity then return end
    -- ZCity's own velocityDamage() uses DeltaTime >= 0.25 and speed >= 350,
    -- but those are DAMAGE thresholds: a hand brushing glass must still lodge
    -- a fragment.  Only require a real, non-trivial impact.
    local speed = (data.OurOldVelocity and data.TheirOldVelocity)
        and (data.OurOldVelocity - data.TheirOldVelocity):Length() or 0
    if speed < 120 then return end
    if not IsGlassCollision(data) then return end

    local ply = OwnerOf(ragdoll)
    if not ply then return end

    -- Resolve the colliding physics object to a bone, exactly like ZCity does.
    local bone
    local phys = data.PhysObject
    if phys and ragdoll.GetPhysicsObjectCount and ragdoll.GetPhysicsObjectNum then
        for i = 0, ragdoll:GetPhysicsObjectCount() do
            if ragdoll:GetPhysicsObjectNum(i) == phys then bone = i break end
        end
    end
    local limbId = GlassLimbFromBone(ragdoll, bone)
    if not limbId and data.HitObject and data.HitObject.GetEntity then
        local ok, hitEnt = pcall(data.HitObject.GetEntity, data.HitObject)
        if ok and IsValid(hitEnt) and hitEnt ~= ragdoll then
            limbId = GlassLimbFromBone(hitEnt, nil)
        end
    end
    if not limbId and ragdoll.GetBoneName then
        limbId = BoneLimb(ragdoll:GetBoneName(0))
    end
    InjectGlass(ply, limbId, bone)
end

-- Own hook name: GMod's hook table is iterated with pairs(), so a separate
-- hook cannot be accidentally replaced by a third party re-registering
-- "Ragdoll Collide"/"organism".  Re-assert on every InstallVanillaHooks().
hook.Add("Ragdoll Collide", "WSZC_GlassRagdoll", RagdollGlassShrapnel)

-- Standing player / ragdoll punching a breakable glass brush.  ZCity's own
-- hook for this is commented out (sv_input.lua:441-446) and GlassShards
-- (sv_util.lua:1354) only spawns a world item, so this is the missing piece.
-- The ONLY shrapnel injection point.  It runs after ZCity's damage hook has
-- filled org.dmgstack / ply.HitBones, so the fragment lands on the limb that
-- was actually hit (a leg stays a leg).  `took == false` is NORMAL in ZCity:
-- homigrad-damage returns true for a player hit and forwards it to
-- ply.FakeRagdoll, so GMod reports the damage as blocked even though the wound
-- was applied.  ShrapnelHandled de-duplicates repeated post hooks.
hook.Add("PostEntityTakeDamage", "WSZC_AuthorityDamagePost", function(ent, dmginfo, took)
    if not (OrganismHooksActive() and IsValid(ent) and dmginfo) then return end
    local raw = WSZC.RawDamage[dmginfo]
    if took == false and not (cvOnBlocked and cvOnBlocked:GetBool()) then return end
    WSZC.InjectDamageShrapnel(ent, dmginfo, nil, raw)
    -- Do not clear RawDamage here: a nested ragdoll Post can run BEFORE the
    -- outer player hook returns.  Weak keys already prevent leaks, and the
    -- outer unresolved hit may still need the original unscaled damage.
end)

--- Shared by BOTH damage hooks.  ZCity's fists (weapon_hands_sh.lua:1653)
--- call Ent:TakeDamageInfo() on the glass brush; on some builds only
--- EntityTakeDamage fires for a brush entity and PostEntityTakeDamage does
--- not, which is why "punch glass -> no fragments" kept coming back.
--- glassCooldown in InjectGlass de-duplicates the two paths.
local function TryGlassStrike(ent, dmginfo)
    if not (OrganismHooksActive() and cvGlass and cvGlass:GetBool()) then return false end
    if not (IsValid(ent) and dmginfo) then return false end
    -- A player hit (already handled above) is never a glass brush entity.
    if ent.organism then return false end

    local class = ent.GetClass and ent:GetClass() or ""
    local isGlass = false

    if class == "func_breakable_surf" then
        isGlass = true
    elseif class == "func_breakable" and ent.GetMaterialType then
        isGlass = ent:GetMaterialType() == (MAT_GLASS or 0)
    elseif string.find(class, "break") and ent.GetBrushSurfaces then
        local ok, surfaces = pcall(ent.GetBrushSurfaces, ent)
        if ok and type(surfaces) == "table" and surfaces[1] then
            local ok2, mat = pcall(function()
                return surfaces[1]:GetMaterial():GetName()
            end)
            if ok2 and type(mat) == "string" and string.find(string.lower(mat), "glass") then
                isGlass = true
            end
        end
    end
    if not isGlass then return false end

    -- With fists the inflictor is the SWEP (no .organism) and the attacker is
    -- the player.  With a fake ragdoll it can be the other way round.  Try
    -- every candidate through OwnerOf instead of requiring .organism twice.
    local inflictor = dmginfo.GetInflictor and dmginfo:GetInflictor() or nil
    local attacker = dmginfo.GetAttacker and dmginfo:GetAttacker() or nil
    local striker = (IsValid(inflictor) and inflictor.organism and inflictor) or attacker
    local ply = OwnerOf(striker) or OwnerOf(attacker) or OwnerOf(inflictor)
    if not ply then return false end
    if not IsValid(striker) then striker = ply end

    local limbId
    local pos = dmginfo.GetDamagePosition and dmginfo:GetDamagePosition() or nil
    if pos and isvector(pos) and striker.LookupBone and striker.GetBonePosition then
        -- Nearest hand/foot bone to the impact point: this is what makes
        -- "hit glass with hands or feet" land on the right limb.
        local best, bestDist
        for _, name in ipairs({
            "ValveBiped.Bip01_L_Hand", "ValveBiped.Bip01_R_Hand",
            "ValveBiped.Bip01_L_Foot", "ValveBiped.Bip01_R_Foot",
        }) do
            local ok, b = pcall(striker.LookupBone, striker, name)
            if ok and b then
                local ok2, bp = pcall(striker.GetBonePosition, striker, b)
                if ok2 and bp then
                    local d = (bp - pos):LengthSqr()
                    if not bestDist or d < bestDist then
                        bestDist, best = d, BoneLimb(name)
                    end
                end
            end
        end
        limbId = best
    end
    if not limbId and striker.GetBoneName then
        limbId = GlassLimbFromBone(striker, 0)
    end

    Debug("glass strike: ent=%s ply=%s limb=%s", tostring(ent), tostring(ply), tostring(limbId))
    InjectGlass(ply, limbId, 0)
    return true
end
WSZC.TryGlassStrike = TryGlassStrike

-- Post hook: canonical path, sees the damage after ZCity's own hooks.
hook.Add("PostEntityTakeDamage", "WSZC_GlassStrike", function(ent, dmginfo)
    TryGlassStrike(ent, dmginfo)
end)

-- Pre hook: brush entities (func_breakable_surf) do not always deliver
-- PostEntityTakeDamage when ZCity's fists call TakeDamageInfo.  Returning nil
-- never blocks vanilla damage; InjectGlass's 0.5 s cooldown de-duplicates.
hook.Add("EntityTakeDamage", "WSZC_GlassStrikePre", function(ent, dmginfo)
    TryGlassStrike(ent, dmginfo)
    return nil
end)

---------------------------------------------------------------------------
-- Shadow view: ZCity organism -> C:U injury HUD
---------------------------------------------------------------------------

local function SetIfChanged(tbl, key, value)
    if tbl[key] == value then return false end
    tbl[key] = value
    return true
end

local function PushShadow(ply, org)
    local h = H()
    if not (h and h.GetBody and h.GetLimbs) then return end
    if h.InitPlayer and not h.GetLimbs(ply) then pcall(h.InitPlayer, ply) end

    local body, limbs = h.GetBody(ply), h.GetLimbs(ply)
    if type(body) ~= "table" or type(limbs) ~= "table" then return end

    -- Capture this BEFORE PullShrapnel() refreshes ply._WSZCLimbsRef: a new
    -- C:U PlayerLimbs table means ragdoll/spawn, not a real reduction.
    local newLimbTable = (ply._WSZCLimbsRef ~= limbs)

    -- sh_inertia.lua gives a non-nil wsmovemult priority over ALL vanilla
    -- immobilization/leg/pain/shock multipliers.  WB.Sync used to write that
    -- C:U value, but organism-authoritative PushShadow deliberately replaces
    -- WB.Sync.  A stale value therefore disables exactly the vanilla slowdown
    -- this mode relies on.  Remove it and force one full organism update.
    if org.wsmovemult ~= nil then
        org.wsmovemult = nil
        org._wbSentMove, org._wbNextMoveSend = nil, nil
        ply.fullsend = true
    end

    local now = CurTime and CurTime() or 0
    if (ply._WSZCShadowNext or 0) > now then return end
    ply._WSZCShadowNext = now + 0.25 -- 4 Hz is plenty for a HUD
    local amputationDirty = SyncAmputationShadow(org, limbs)
    local internalBleedingDirty = WSZC.SyncInternalBleedingShadow(org, limbs)

    local bodyChanged = false
    local dirtyLimbs = {}
    local function bodySet(key, value)
        bodyChanged = SetIfChanged(body, key, value) or bodyChanged
    end

    bodySet("bloodVolume", math.Clamp((tonumber(org.blood) or 5000) / 5000 * 100, 0, 200))
    -- C:U blocks every bone hit while avgPain > DislocationPainBlock (75).
    -- A fresh ZCity dislocation already adds +35 painadd, so without this cap
    -- the manual reduction minigame would be unwinnable.  It is a temporary
    -- analgesia for the session only; the organism keeps its real pain.
    -- The block is evaluated at session START too, not only while it runs, so
    -- cap the shadow pain for the whole time a joint is dislocated.
    local avgPain = math.max(tonumber(org.pain) or 0, 0)
    if WSZC.DislocationActive(ply) or WSZC.AnyDislocation(org) then
        avgPain = math.min(avgPain, 60)
    end
    bodySet("avgPain", avgPain)
    bodySet("heartRate", tonumber(org.pulse) or 70)
    bodySet("shock", math.Clamp((tonumber(org.shock) or 0) / 0.7, 0, 100))
    bodySet("consciousness", math.Clamp((tonumber(org.consciousness) or 1) * 100, 0, 100))
    bodySet("brainHealth", math.Clamp((1 - (tonumber(org.brain) or 0)) * 100, 0, 100))
    bodySet("totalBleedSpeed", math.max(tonumber(org.bleed) or 0, 0))
    bodySet("internalBleeding", math.max(tonumber(org.internalBleed) or 0, 0))
    bodySet("unconscious", org.otrub == true)
    -- WoundSystem.OpenHealthHUD() refuses to open while CardioState.unconscious
    -- OR ply:GetNWBool("WoundSystemUnconscious") is set.  C:U's own physiology
    -- is disabled in this mode, so it can leave that NW bool stuck at true and
    -- permanently lock the panel.  Mirror ZCity's otrub flag explicitly.
    if ply.SetNWBool and ply.GetNWBool then
        local unconscious = org.otrub == true
        if ply:GetNWBool("WoundSystemUnconscious", false) ~= unconscious then
            ply:SetNWBool("WoundSystemUnconscious", unconscious)
        end
    end
    if type(org.stamina) == "table" then
        bodySet("stamina", math.Clamp((tonumber(org.stamina[1]) or 0) /
            math.max(tonumber(org.stamina.max) or 180, 1) * 100, 0, 100))
    end

    -- C:U body.adrenaline / painkiller are 0..100; ZCity organism uses 0..2
    -- and 0..1.  Keeping them in sync stops ApplyMedicalDelta() from applying
    -- a bogus delta, and keeps the C:U status HUD truthful.
    bodySet("adrenaline", math.Clamp((tonumber(org.adrenaline) or 0) * 20, 0, 100))
    bodySet("painkiller", math.Clamp((tonumber(org.painkiller) or 0) * 100, 0, 100))

    -- Values WE last wrote into C:U.  Anything above them was added by a C:U
    -- minigame (BreakShrapnelGrasp) and must be mirrored into the organism.
    ply._WSZCExpectedBleed = ply._WSZCExpectedBleed or {}
    ply._WSZCExpectedPain = ply._WSZCExpectedPain or {}

    local pain, bleed = math.max(tonumber(org.pain) or 0, 0), math.max(tonumber(org.bleed) or 0, 0)
    local woundMap = (cvLimbBleed and cvLimbBleed:GetBool()) and LimbBleedMap(ply, org) or nil
    WSZC.SyncDislocation(ply, org, limbs, newLimbTable)
    for limbId, state in pairs(limbs) do
        if type(state) == "table" then
            local cuBleed = math.max(tonumber(state.bleed) or 0, 0)
            local cuPain = math.max(tonumber(state.pain) or 0, 0)
            local expectedBleed = tonumber(ply._WSZCExpectedBleed[limbId]) or 0
            local expectedPain = tonumber(ply._WSZCExpectedPain[limbId]) or 0
            if (tonumber(state.shrapnel) or 0) > 0
                and (cuBleed > expectedBleed + 0.05 or cuPain > expectedPain + 0.5) then
                if WSZC.ApplyShrapnelComplication(ply, org, limbId,
                        cuBleed - expectedBleed, cuPain - expectedPain) then
                    -- organism changed: recompute the values for this limb
                    pain = math.max(tonumber(org.pain) or 0, 0)
                    bleed = math.max(tonumber(org.bleed) or 0, 0)
                    if cvLimbBleed and cvLimbBleed:GetBool() then
                        woundMap = LimbBleedMap(ply, org)
                    end
                end
            end

            local map = LIMB_ORG[limbId]
            local limbChanged = false
            local function limbSet(key, value)
                limbChanged = SetIfChanged(state, key, value) or limbChanged
            end
            -- `shrapnel`, `isBandaged`, `hasInjection` and the minigames'
            -- custom statuses stay C:U-owned.  The shadow helpers touch only
            -- WSZC_AMPUTATION / WSZC_INTERNAL_BLEEDING and preserve the rest.
            local limbBleed
            if woundMap then
                local fromWounds = woundMap[limbId] or 0
                local dmg = math.Clamp(tonumber(map and org[map.dmg]) or 0, 0, 1)
                if fromWounds > 0 then
                    limbBleed = math.Clamp(fromWounds, 0, 100)
                elseif dmg > 0.001 then
                    -- Only limbs the organism actually damaged bleed.  Internal
                    -- bleeding stays in body.internalBleeding and never paints
                    -- all 17 limbs red.
                    limbBleed = math.Clamp(math.min(bleed * 0.2, dmg * 20), 0, 100)
                else
                    limbBleed = 0
                end
            else
                limbBleed = math.Clamp(bleed * 0.2, 0, 100)
            end
            local limbPain = math.Clamp(pain * 0.12 + limbBleed * 0.35, 0, 100)
            limbSet("bleed", limbBleed)
            limbSet("pain", limbPain)
            ply._WSZCExpectedBleed[limbId] = limbBleed
            ply._WSZCExpectedPain[limbId] = limbPain
            if map and map.dmg then
                local dmg = math.Clamp(tonumber(org[map.dmg]) or 0, 0, 1)
                limbSet("muscle", math.Clamp((1 - dmg) * 100, 0, 100))
                if map.amp then limbSet("dismembered", org[map.amp] == true) end
                -- Fractures are pure ZCity state (org.<limb>, brokenribs).
                -- C:U's timer is REMAINING healing time (100 at a fresh break),
                -- hence damage * 100 and zero as soon as Fractured is false.
                local fractured = Fractured(org, limbId, map)
                limbSet("broken", fractured)
                limbSet("boneHealTimer", fractured and math.Clamp(dmg * 100, 0, 100) or 0)
                if map.dis then
                    -- One point per dislocation: the limb above the fracture.
                    -- All other limbs of this arm/leg get `false`, so the
                    -- WoundView can no longer show three joints at once.
                    local out = BoneAnchor(limbId, "dislocation")
                        and org[map.dis] == true or false
                    limbSet("dislocated", out)
                    -- C:U's WoundSystem_DislocationStart() uses this as the
                    -- bone's starting distance.  A fresh ZCity dislocation
                    -- would otherwise arrive with timer = 0 (already reduced)
                    -- and complete on the first input packet without ever
                    -- letting the player move the bone by hand.
                    if out then
                        if (tonumber(state.dislocationTimer) or 0) <= 0 then
                            limbSet("dislocationTimer", DislocationStartTimer())
                        end
                    else
                        limbSet("dislocationTimer", 0)
                    end
                    ply._WSZCExpectedDislocation[limbId] = out
                end
            elseif map then
                -- Head is now wound/eye presentation only.  In particular a
                -- legacy head.broken must not duplicate the neck fracture.
                limbSet("broken", false)
                limbSet("boneHealTimer", 0)
                limbSet("dislocated", false)
                limbSet("dislocationTimer", 0)
            end
            if limbChanged then dirtyLimbs[limbId] = true end
        end
    end

    PullShrapnel(ply, org)

    if bodyChanged and h.SendCardioUpdate then pcall(h.SendCardioUpdate, ply, true) end
    if h.SendLimbUpdate then
        for limbId in pairs(amputationDirty) do dirtyLimbs[limbId] = true end
        if internalBleedingDirty then dirtyLimbs.abdomen = true end
        for limbId in pairs(dirtyLimbs) do pcall(h.SendLimbUpdate, ply, limbId, false) end
    end
end
WSZC.SyncOrganismShadow = PushShadow -- diagnostics / source-faithful regressions

---------------------------------------------------------------------------
-- Medical effects: mirror C:U treatment deltas back into ply.organism
---------------------------------------------------------------------------

local function Snapshot(ply, limbId)
    local h = H()
    if not (h and h.GetBody and h.GetLimbState) then return nil end
    local body = h.GetBody(ply)
    local state = h.GetLimbState(ply, limbId)
    if type(body) ~= "table" then return nil end
    return {
        bloodVolume = tonumber(body.bloodVolume) or 100,
        avgPain = tonumber(body.avgPain) or 0,
        heartRate = tonumber(body.heartRate) or 70,
        shock = tonumber(body.shock) or 0,
        consciousness = tonumber(body.consciousness) or 100,
        brainHealth = tonumber(body.brainHealth) or 100,
        totalBleedSpeed = tonumber(body.totalBleedSpeed) or 0,
        internalBleeding = tonumber(body.internalBleeding) or 0,
        stamina = tonumber(body.stamina) or 100,
        painkiller = tonumber(body.painkiller) or 0,
        adrenaline = tonumber(body.adrenaline) or 0,
        -- C:U stores the opioid dose here (FENTANYL adds 420, MORPHINE similar).
        -- ZCity's organism reads org.analgesiaAdd instead, so without this
        -- field the drug delta was invisible to the authoritative organism.
        opiateAmount = tonumber(body.opiateAmount) or 0,
        antagonistAmount = tonumber(body.antagonistAmount) or 0,
        limbBleed = type(state) == "table" and (tonumber(state.bleed) or 0) or 0,
        limbPain = type(state) == "table" and (tonumber(state.pain) or 0) or 0,
        limbMuscle = type(state) == "table" and (tonumber(state.muscle) or 100) or 100,
        limbBroken = type(state) == "table" and state.broken == true or false,
        limbBoneHealTimer = type(state) == "table" and (tonumber(state.boneHealTimer) or 0) or 0,
    }
end

-- The C:U item definitions already know how each medicine changes the body.
-- Instead of re-implementing every ZCity drug, take the *delta* C:U produced
-- and apply the inverse of WB.Sync() to the authoritative organism.
function WSZC.ApplyMedicalDelta(ply, limbId, before)
    if not (Authority() and before) then return end
    local after = Snapshot(ply, limbId)
    if not after then return end
    local org = ply.organism
    if type(org) ~= "table" then return end

    local function add(key, delta, low, high)
        if delta == 0 then return end
        local cur = tonumber(org[key])
        if cur == nil then return end
        org[key] = math.Clamp(cur + delta, low or -1e9, high or 1e9)
    end

    add("blood", (after.bloodVolume - before.bloodVolume) / 100 * 5000, 0, 6000)
    add("pain", (after.avgPain - before.avgPain) * 0.5, 0)
    add("pulse", after.heartRate - before.heartRate, 0, 260)
    add("shock", (after.shock - before.shock) * 0.7, 0, 70)
    add("consciousness", (after.consciousness - before.consciousness) / 100, 0, 1)
    add("brain", -(after.brainHealth - before.brainHealth) / 100, 0, 1)
    add("bleed", (after.totalBleedSpeed - before.totalBleedSpeed), 0)
    local bleedTreatment = before.limbBleed - after.limbBleed
    if bleedTreatment > 0.000001 and LIMB_ORG[limbId] then
        ReduceLimbWoundBleeding(ply, org, limbId, bleedTreatment)
    end
    add("bleed", (after.limbBleed - before.limbBleed) * 0.2, 0)
    add("pain", (after.limbPain - before.limbPain) * 0.25, 0)
    add("internalBleed", after.internalBleeding - before.internalBleeding, 0)
    -- C:U uses 0..100 for both of these.  ZCity's organism expects 0..1 for
    -- painkiller and 0..2 for adrenaline; pushing +100 straight through made
    -- cl_camera.lua compute a -500 FOV offset (the "adrenaline" screen warp).
    add("painkiller", (after.painkiller - before.painkiller) * 0.01, 0, 1)
    add("adrenaline", (after.adrenaline - before.adrenaline) * 0.02, 0, 2)
    -- Morphine / fentanyl / painkillers: ZCity's SWEP:Heal short-circuits on
    -- `WB.SwepHeal(...) ~= nil` and therefore never runs its own
    -- `org.analgesiaAdd = min(org.analgesiaAdd + injected, 4)`.  C:U applies
    -- the dose to body.opiateAmount when the syringe minigame finishes.  Mirror
    -- the delta into the authoritative organism so the analgesic actually
    -- works (pain relief, sedation, breathing).  0.006 maps a full 420-unit
    -- fentanyl syringe to ~2.5 analgesia, inside ZCity's 0..4 range.
    add("analgesiaAdd", (after.opiateAmount - before.opiateAmount) * 0.006, 0, 4)
    -- Naloxone does not subtract opiateAmount directly.  C:U records the
    -- antagonist separately (a full native syringe adds 50), so mirror that
    -- delta into ZCity's own naloxoneadd timer (full dose = 1).  The native
    -- sv_pain module then accelerates analgesia decay exactly as it should.
    add("naloxoneadd", (after.antagonistAmount - before.antagonistAmount) * 0.02, 0, 1)
    if type(org.stamina) == "table" then
        local max = math.max(tonumber(org.stamina.max) or 180, 1)
        org.stamina[1] = math.Clamp((tonumber(org.stamina[1]) or 0) +
            (after.stamina - before.stamina) / 100 * max, 0, max)
    end

    local map = LIMB_ORG[limbId]
    if map and map.dmg then
        add(map.dmg, -(after.limbMuscle - before.limbMuscle) / 100, 0, 1)
        if BoneAnchor(limbId, "fracture") and before.limbBroken then
            local boneDelta = (after.limbBoneHealTimer - before.limbBoneHealTimer) / 100
            if boneDelta < 0 then
                add(map.dmg, boneDelta, 0, 1)
                if limbId == "thorax" then
                    -- Native sv_bone derives this display/count field from the
                    -- same chest scalar; keep the two authoritative values in
                    -- lockstep instead of clearing only the C:U icon.
                    org.brokenribs = math.floor(math.Clamp((tonumber(org.chest) or 0) * 3, 0, 3) + 0.5)
                end
                ply.fullsend = true
            end
        end
        -- A limb that healed past its shrapnel floor releases the block.
        if org.wszc_shrapnel_floor and org.wszc_shrapnel_floor[limbId] then
            org.wszc_shrapnel_floor[limbId] = math.min(
                org.wszc_shrapnel_floor[limbId], tonumber(org[map.dmg]) or 0)
        end
    end
    Debug("medical delta applied to %s/%s", tostring(ply), tostring(limbId))
end

function WSZC.SnapshotMedical(ply, limbId)
    if not Authority() then return nil end
    return Snapshot(ply, limbId)
end

---------------------------------------------------------------------------
-- Native timed medicine (procoagulant / relief cream)
---------------------------------------------------------------------------

-- C:U applies these effects once immediately and then once per second.  Its
-- later ticks are outside SwepHeal/ApplyItemToBody, so an ordinary delta
-- wrapper cannot see them before PushShadow restores the old C:U values.
-- Execute the exact native numeric step on a TEMPORARY shadow, mirror every
-- affected body/limb delta, then restore that shadow.  The caller's own outer
-- snapshot consequently sees no duplicate immediate dose.
local function MirrorTimedBodyEffectStep(ply, effect)
    if not (Authority() and IsValid(ply) and type(effect) == "table") then return end
    local h = H()
    local body = h and h.GetBody and h.GetBody(ply) or nil
    local limbs = h and h.GetLimbs and h.GetLimbs(ply) or nil
    if type(body) ~= "table" then return end
    local kind = effect.kind or effect.id

    if kind == "procoagulant" then
        local bodyShadow = effect._WSZCBodyShadow or {}
        local limbShadow = effect._WSZCLimbShadow or {}
        local externalBody = effect._WSZCExternalBodyShadow or {}
        local externalLimbs = effect._WSZCExternalLimbShadow or {}
        effect._WSZCBodyShadow, effect._WSZCLimbShadow = bodyShadow, limbShadow
        effect._WSZCExternalBodyShadow, effect._WSZCExternalLimbShadow = externalBody, externalLimbs
        local bodyKeys = { "internalBleeding", "bloodViscosity", "strokeAmount" }
        local savedBody = {}
        for _, key in ipairs(bodyKeys) do
            savedBody[key] = body[key]
            local externalValue = savedBody[key] == nil and false or savedBody[key]
            -- If PushShadow/new damage changed the external value, it is the
            -- current native baseline.  Otherwise continue our simulated
            -- cumulative value (needed when shadow sync is disabled).
            if bodyShadow[key] ~= nil and externalBody[key] ~= nil
                and externalBody[key] == externalValue then
                body[key] = bodyShadow[key]
            end
        end

        local beforeLimbs, savedBleed = {}, {}
        for limbId, state in pairs(type(limbs) == "table" and limbs or {}) do
            if type(state) == "table" then
                savedBleed[limbId] = state.bleed
                local cached = limbShadow[limbId]
                local external = externalLimbs[limbId]
                local externalValue = savedBleed[limbId] == nil and false or savedBleed[limbId]
                if cached and cached.bleed ~= nil and external
                    and external.bleed ~= nil and external.bleed == externalValue then
                    state.bleed = cached.bleed
                end
                beforeLimbs[limbId] = Snapshot(ply, limbId)
            end
        end
        local bodyBefore = Snapshot(ply, "body")
        if not bodyBefore then
            for key, value in pairs(savedBody) do body[key] = value end
            for limbId, value in pairs(savedBleed) do limbs[limbId].bleed = value end
            return
        end
        local simulatedBeforeBody = {}
        for _, key in ipairs(bodyKeys) do simulatedBeforeBody[key] = body[key] end

        body.internalBleeding = math.Clamp((body.internalBleeding or 0) * 0.95, 0, 100)
        body.bloodViscosity = math.Clamp((body.bloodViscosity or 0) + 1.75, -100, 150)
        body.strokeAmount = math.Clamp((body.strokeAmount or 0) - 10, 0, 100)
        for limbId in pairs(beforeLimbs) do
            local state = limbs[limbId]
            state.bleed = math.Clamp((state.bleed or 0) * 0.96, 0, 100)
        end

        local ok, err = pcall(WSZC.ApplyMedicalDelta, ply, "body", bodyBefore)
        for _, key in ipairs(bodyKeys) do
            bodyShadow[key] = body[key]
            -- Limb snapshots were taken against the simulated BEFORE body.
            -- Keep that baseline until every limb delta is done; restoring the
            -- external shadow here would add a phantom body dose per limb.
            body[key] = simulatedBeforeBody[key]
        end
        if not ok then Warn("procoagulant body mirror failed: " .. tostring(err)) end

        for limbId, before in pairs(beforeLimbs) do
            local state = limbs[limbId]
            ok, err = pcall(WSZC.ApplyMedicalDelta, ply, limbId, before)
            local cached = limbShadow[limbId] or {}
            cached.bleed = state.bleed
            limbShadow[limbId] = cached
            state.bleed = savedBleed[limbId]
            if not ok then Warn("procoagulant limb mirror failed: " .. tostring(err)) end
        end
        for key, value in pairs(savedBody) do
            body[key] = value
            externalBody[key] = value == nil and false or value
        end
        for limbId, value in pairs(savedBleed) do
            local external = externalLimbs[limbId] or {}
            external.bleed = value == nil and false or value
            externalLimbs[limbId] = external
        end
    elseif kind == "reliefcream" and type(limbs) == "table" then
        local limbId = effect.limbId
        local state = limbId and limbs[limbId] or nil
        if type(state) ~= "table" then return end
        local limbShadow = effect._WSZCLimbShadow or {}
        local externalLimbs = effect._WSZCExternalLimbShadow or {}
        effect._WSZCLimbShadow, effect._WSZCExternalLimbShadow = limbShadow, externalLimbs
        local cached = limbShadow[limbId]
        local external = externalLimbs[limbId]
        local savedPain = state.pain
        local externalValue = savedPain == nil and false or savedPain
        if cached and cached.pain ~= nil and external
            and external.pain ~= nil and external.pain == externalValue then
            state.pain = cached.pain
        end
        local before = Snapshot(ply, limbId)
        if not before then state.pain = savedPain return end
        -- Native: Lerp(0.15, pain, pain * 0.1) == pain * 0.865.
        state.pain = math.Clamp((state.pain or 0) * 0.865, 0, 100)
        local ok, err = pcall(WSZC.ApplyMedicalDelta, ply, limbId, before)
        cached = cached or {}
        cached.pain = state.pain
        limbShadow[limbId] = cached
        external = external or {}
        external.pain = savedPain == nil and false or savedPain
        externalLimbs[limbId] = external
        state.pain = savedPain
        if not ok then Warn("relief-cream mirror failed: " .. tostring(err)) end
    end
end
WSZC.MirrorTimedBodyEffectStep = MirrorTimedBodyEffectStep

function WSZC.TickTimedBodyEffects(ply, dt)
    if not Authority() then return end
    local effects = IsValid(ply) and ply._WSZCTimedBodyEffects or nil
    if type(effects) ~= "table" then return end
    if ply.Alive and not ply:Alive() then ply._WSZCTimedBodyEffects = nil return end
    dt = math.max(tonumber(dt) or 0, 0)
    for id, effect in pairs(effects) do
        effect.remaining = (tonumber(effect.remaining) or 0) - dt
        effect.accumulator = (tonumber(effect.accumulator) or 0) + dt
        while effect.remaining > 0 and effect.accumulator >= 1 do
            MirrorTimedBodyEffectStep(ply, effect)
            effect.accumulator = effect.accumulator - 1
        end
        if effect.remaining <= 0 then effects[id] = nil end
    end
end

local function InstallTimedEffectBridge()
    local h = H()
    if type(h) ~= "table" or type(h.QueueTimedBodyEffect) ~= "function" then return false end
    if h.QueueTimedBodyEffect == h._WSZCQueueTimedBodyEffectWrapper then return true end
    local base = h.QueueTimedBodyEffect
    local function wrapped(ply, body, id, duration, data)
        local kind = data and data.kind or id
        if not Authority() or (kind ~= "procoagulant" and kind ~= "reliefcream") then
            return base(ply, body, id, duration, data)
        end
        if not IsValid(ply) or type(body) ~= "table" then return false end
        id = tostring(id or "")
        duration = math.max(tonumber(duration) or 0, 0)
        if id == "" or duration <= 0 then return false end

        local effects = ply._WSZCTimedBodyEffects
        if type(effects) ~= "table" then
            effects = {}
            ply._WSZCTimedBodyEffects = effects
        end
        local effect = effects[id]
        if effect then
            effect.remaining = (effect.remaining or 0) + duration
            effect.maxHad = math.max(effect.maxHad or 0, effect.remaining or 0)
            effect.kind = data and data.kind or effect.kind
            effect.limbId = data and data.limbId or effect.limbId
        else
            effect = {
                id = id, kind = kind, limbId = data and data.limbId or nil,
                remaining = duration, maxHad = duration, accumulator = 0,
            }
            effects[id] = effect
            if not data or data.immediate ~= false then
                MirrorTimedBodyEffectStep(ply, effect)
            end
        end
        return true
    end
    h._WSZCOriginalQueueTimedBodyEffect = base
    h._WSZCQueueTimedBodyEffectWrapper = wrapped
    h.QueueTimedBodyEffect = wrapped
    return true
end
WSZC.InstallTimedEffectBridge = InstallTimedEffectBridge

---------------------------------------------------------------------------
-- Wrapper installation
---------------------------------------------------------------------------

local installed = false
local wrappedByKey = {}
-- Lua functions cannot carry fields (fn._flag = true raises "attempt to index
-- a function value"), so identity markers live in a weak-keyed table instead.
local wrappedFns = setmetatable({}, { __mode = "k" })

--- Wrap an existing ZCity hook so it runs with WB.IsBridged() == false.
--- `pre` / `post` (optional) run before / after the original, still inside the
--- vanilla context.  GMod iterates hook tables with pairs(), so registration
--- order cannot guarantee this position around ZCity's own damage code.
local function WrapHook(event, name, pre, post)
    local key = event .. "/" .. name
    local hooks = hook.GetTable()[event]
    local current = hooks and hooks[name]
    if type(current) ~= "function" then return false end

    -- Already ours?  Keep the wrapper.  If a third party re-registered the
    -- hook, wrap the NEW function instead (defensive re-apply every 5 s).
    if wrappedByKey[key] == current and wrappedFns[current] then return false end
    if wrappedFns[current] then return false end -- never wrap a wrapper
    local original = current

    local inner
    if pre or post then
        inner = function(...)
            if pre then
                local ok, err = pcall(pre, ...)
                if not ok then Warn(event .. "/" .. name .. " pre: " .. tostring(err)) end
            end
            -- EntityTakeDamage (the only post-wrapped hook) has one meaningful
            -- return value; preserve several anyway for third-party variants.
            local a, b, c, d = original(...)
            if post then
                local ok, err = pcall(post, ...)
                if not ok then Warn(event .. "/" .. name .. " post: " .. tostring(err)) end
            end
            return a, b, c, d
        end
    else
        inner = original
    end
    local function wrapped(...)
        if not Authority() then return original(...) end
        return WSZC.WithVanillaContext(inner, ...)
    end
    wrappedFns[wrapped] = true
    hook.Add(event, name, wrapped)
    wrappedByKey[key] = wrapped
    Debug("wrapped %s/%s for vanilla organism context", event, name)
    return true
end

local function CaptureRawDamage(ent, dmginfo)
    if not (IsValid(ent) and dmginfo and dmginfo.GetDamage) then return end
    -- Save the UNSCALED damage.  ZCity calls dmginfo:ScaleDamage(0.15) and may
    -- rewrite the damage type later in this very hook, so PostEntityTakeDamage
    -- would otherwise see only 15% of the real blast damage.
    local ok, raw = pcall(dmginfo.GetDamage, dmginfo)
    if ok then WSZC.RawDamage[dmginfo] = raw end
    -- Deliberately NO injection here: ZCity writes org.dmgstack[hitgroup] and
    -- ply.HitBones INSIDE this hook, and the shrapnel must land on that exact
    -- limb.  InjectAfterZCityDamage runs immediately after those writes.
end

--- Vanilla ZCity explicitly zeroes dmgHurt/instaPain/immobilization for
--- DMG_CRUSH + DMG_FALL.  In organism-authoritative mode WB.ApplyFall is a
--- deliberate no-op, so without this mirror a survivable standing landing can
--- produce neither muscle damage nor the expected temporary slowdown.
---
--- Use C:U's own fall-speed/impact-force contract, but write ONLY the aggregate
--- muscle/pain/shock delta into the authoritative ZCity organism.  Do not run
--- C:U HandleDamage here: that would create a second health simulation and can
--- duplicate fractures/bleeding already produced by ZCity.  Ragdoll landings
--- stay on the existing velocityDamage/collision path.
WSZC.FallHandled = WSZC.FallHandled or setmetatable({}, { __mode = "k" })
function WSZC.ApplyStandingFall(ply, dmginfo, rawDamage)
    if not (Authority() and IsValid(ply) and ply:IsPlayer() and dmginfo) then return false end
    if type(dmginfo.IsFallDamage) ~= "function" or not dmginfo:IsFallDamage() then return false end
    if WSZC.FallHandled[dmginfo] then return false end
    if not ply:Alive() or IsValid(ply.FakeRagdoll) then return false end
    local org = ply.organism
    if type(org) ~= "table" or org.alive == false or org.godmode then return false end
    if ply.Health and ply:Health() <= 0 then return false end

    WSZC.FallHandled[dmginfo] = true
    local h = H()
    local damage = tonumber(rawDamage)
    if damage == nil and dmginfo.GetDamage then
        local ok, value = pcall(dmginfo.GetDamage, dmginfo)
        if ok then damage = tonumber(value) end
    end
    damage = damage or 0

    local speed
    if h and type(h.GetRecentFallSpeed) == "function" then
        local ok, value = pcall(h.GetRecentFallSpeed, ply, damage)
        if ok then speed = tonumber(value) end
    end
    speed = speed or (damage > 0 and (damage * 3.96 + 526.5) or 0)

    local body = h and h.GetBody and h.GetBody(ply) or nil
    local jump = type(body) == "table" and (tonumber(body.jumpSpeed) or 6.5) or 6.5
    local force
    if h and type(h.FallSpeedToImpactForce) == "function" then
        local ok, value = pcall(h.FallSpeedToImpactForce, speed)
        if ok then force = tonumber(value) end
    end
    force = force or math.max((speed - 420) / 60, 0)
    if ply._woundSystemLastFallOnFloater then force = force * 0.5 end
    if force <= jump then return false end

    -- Native C:U hits both feet and adds both shins above jumpSpeed * 1.8.
    -- Three C:U limb segments share one ZCity leg scalar.  Aggregate first so
    -- the same scalar is never accidentally applied once per PushShadow limb.
    local segmentsPerLeg = force > jump * 1.8 and 2 or 1
    local affectedSides = 0
    for _, side in ipairs({
        { damage = "lleg", amputated = "llegamputated" },
        { damage = "rleg", amputated = "rlegamputated" },
    }) do
        if org[side.amputated] ~= true then
            local delta = force * 0.33 * segmentsPerLeg / 100
            org[side.damage] = math.Clamp((tonumber(org[side.damage]) or 0) + delta, 0, 1)
            affectedSides = affectedSides + 1
        end
    end
    if affectedSides == 0 then return false end

    local segments = segmentsPerLeg * affectedSides
    local muscleDamage = force * 0.33 * segments
    org.painadd = math.max((tonumber(org.painadd) or 0) + force * 0.4 * segments * 0.25, 0)
    org.shock = math.Clamp((tonumber(org.shock) or 0) + force * 0.05 * segments * 0.7, 0, 70)
    if type(org.adrenaline) == "number" then
        org.adrenaline = math.Clamp(org.adrenaline + force * 0.075 * segments * 0.02, 0, 2)
    end
    -- This is the temporary component.  ZCity's sv_pain/organism thinkers
    -- decay immobilization naturally; persistent slowdown comes from the leg
    -- muscle damage above.  Cap at the same native damage-hook maximum (30).
    org.immobilization = math.min((tonumber(org.immobilization) or 0)
        + math.min(muscleDamage * 1.5, 30), 30)
    org.lasthit = CurTime and CurTime() or 0
    -- Even with the HUD shadow disabled, never let the old C:U movement
    -- override bypass the freshly applied vanilla immobilization/leg damage.
    org.wsmovemult, org._wbSentMove, org._wbNextMoveSend = nil, nil, nil
    ply.fullsend = true

    if hg.send_organism then pcall(hg.send_organism, org, ply) end
    if hg.send_bareinfo then pcall(hg.send_bareinfo, org) end
    if cvShadow and cvShadow:GetBool() then
        ply._WSZCShadowNext = 0
        local ok, err = pcall(PushShadow, ply, org)
        if not ok then Warn("standing fall shadow failed: " .. tostring(err)) end
    end
    Debug("standing fall: speed=%.2f force=%.2f segments=%d immobilization=%.2f",
        speed, force, segments, tonumber(org.immobilization) or 0)
    return true
end

local function InjectAfterZCityDamage(ent, dmginfo)
    if not (Authority() and IsValid(ent) and dmginfo) then return end
    -- PostEntityTakeDamage is not guaranteed when homigrad-damage returns true
    -- (its normal player/ragdoll path).  Inject here as well; ShrapnelHandled
    -- de-duplicates the public post hook and nested player -> ragdoll damage.
    WSZC.InjectDamageShrapnel(ent, dmginfo, nil)
    WSZC.ApplyStandingFall(ent, dmginfo, WSZC.RawDamage[dmginfo])
end

-- Plain no-op replacements for the ZCity bridge entry points.  With these in
-- place the vanilla ZCity damage / collision / amputation code runs even if a
-- hook we did not wrap calls the bridge directly.
local bridgeStubs = {}

local function Stub(name, ret)
    local wb = WB()
    if not wb or bridgeStubs[name] then return end
    if type(wb[name]) ~= "function" then return end
    bridgeStubs[name] = wb[name]
    wb[name] = function(...)
        if not Authority() then return bridgeStubs[name](...) end
        return ret
    end
end

-- ZCity medicine goes through WB.SwepHeal(): instant items use spec.fn()
-- directly on the C:U body, continuous items use H.ApplyItemToBody() later from
-- the minigame's onProgress.  Wrap the synchronous path here and let
-- ApplyItemToBodyImpl handle the asynchronous one (WSZC.SwepHealDepth > 0
-- tells it the outer wrapper already computed the full body delta).
WSZC.SwepHealDepth = 0

local function TourniquetExtremity(limbId)
    limbId = NormalizeLimb(limbId)
    return limbId and TOURNIQUET_DOWNSTREAM[limbId] and limbId or nil
end

local function IsTourniquetHeal(swep, mode)
    if not IsValid(swep) or not swep.GetClass then return false end
    local ok, class = pcall(swep.GetClass, swep)
    class = ok and string.lower(tostring(class or "")) or ""
    if class == "weapon_tourniquet" then return true end
    if class ~= "weapon_medkit_sh" then return false end
    return tonumber(swep.mode or mode or 1) == 4
end

--- Resolve the application site BEFORE native WB.SwepHeal/BestLimb.  Native
--- AimedLimb deliberately returns nil for self-use, which is especially wrong
--- while the owner's current character is a ragdoll: its traced PhysicsBone
--- still identifies the exact leg the player selected.
function WSZC.ResolveTourniquetLimb(swep, ent, mode, bone)
    if not IsTourniquetHeal(swep, mode) then return nil end
    local target = OwnerOf(ent)
    if not target then return nil end

    local direct = TourniquetExtremity(LimbFromBoneName(BoneNameOf(ent, bone)))
    if direct then return direct end
    if not IsValid(swep) or not swep.GetOwner or not (hg and hg.eyeTrace) then return nil end
    local owner = swep:GetOwner()
    if not IsValid(owner) then return nil end
    local traceOk, tr = pcall(hg.eyeTrace, owner)
    if not traceOk or type(tr) ~= "table" or not IsValid(tr.Entity) then return nil end
    local hit = tr.Entity
    if OwnerOf(hit) ~= target then return nil end

    local boneName
    if hit.IsRagdoll and hit:IsRagdoll() and tr.PhysicsBone
        and hit.TranslatePhysBoneToBone and hit.GetBoneName then
        local boneOk, boneId = pcall(hit.TranslatePhysBoneToBone, hit, tr.PhysicsBone)
        boneId = tonumber(boneId)
        if boneOk and boneId and boneId >= 0 then
            local nameOk, name = pcall(hit.GetBoneName, hit, boneId)
            if nameOk then boneName = name end
        end
    end

    local limb = TourniquetExtremity(LimbFromBoneName(boneName))
    if not limb and boneName then
        local h = H()
        local mapper = h and h.RagdollBoneNameToLimb
        if type(mapper) == "function" then
            local mapOk, mapped = pcall(mapper, boneName)
            if mapOk then limb = TourniquetExtremity(mapped) end
        end
    end
    -- Player hit traces do not have a PhysicsBone; retain their real hitgroup
    -- instead of falling back to the worst-bleeding limb.
    return limb or TourniquetExtremity(LimbFromHitgroup(tr.HitGroup))
end

-- Body drugs administered through a minigame call spec.fn LATER from
-- StartMinigame.onProgress, after WB.SwepHeal (and its outer snapshot) has
-- already returned.  Wrap the exposed spec functions so that asynchronous
-- call gets its own delta.  During instant use SwepHealDepth > 0 and the outer
-- wrapper remains solely responsible, preventing a double dose.
local patchedBodyDrugFns = setmetatable({}, { __mode = "k" })
local function PatchBodyDrugSpecs(wb)
    if type(wb) ~= "table" then return false end
    local changed = false
    local function patch(specs)
        for _, spec in pairs(type(specs) == "table" and specs or {}) do
            if type(spec) == "table" and spec.kind == "body"
                and type(spec.fn) == "function" and not patchedBodyDrugFns[spec.fn] then
                local base = spec.fn
                local wrapped = function(ply, body, ...)
                    local mirror = Authority() and (WSZC.SwepHealDepth or 0) <= 0
                    local before = mirror and WSZC.SnapshotMedical(ply, "body") or nil
                    local a, b, c = base(ply, body, ...)
                    if before then WSZC.ApplyMedicalDelta(ply, "body", before) end
                    return a, b, c
                end
                patchedBodyDrugFns[wrapped] = true
                spec.fn = wrapped
                changed = true
            end
        end
    end
    patch(wb.SwepSpecs)
    patch(wb.MedkitModes)
    return changed
end
WSZC.PatchBodyDrugSpecs = PatchBodyDrugSpecs

-- BloodBagGive already goes through H.ApplyItemToBody.  BloodBagTake is the
-- opposite native path and writes body.bloodVolume directly, so without this
-- wrapper the next organism shadow simply restored the supposedly drawn blood.
local function PatchBloodBagTake(wb)
    if type(wb) ~= "table" or type(wb.BloodBagTake) ~= "function" then return false end
    if wb.BloodBagTake == wb._WSZCBloodBagTakeWrapper then return true end
    local base = wb.BloodBagTake
    local wrapped = function(swep, ent)
        if not Authority() then return base(swep, ent) end
        local ply = OwnerOf(ent)
        local before = ply and WSZC.SnapshotMedical(ply, "body") or nil
        local ok, a, b, c = pcall(base, swep, ent)
        if not ok then
            Warn("WB.BloodBagTake failed: " .. tostring(a))
            return nil
        end
        if before then WSZC.ApplyMedicalDelta(ply, "body", before) end
        return a, b, c
    end
    wb._WSZCOriginalBloodBagTake = base
    wb._WSZCBloodBagTakeWrapper = wrapped
    wb.BloodBagTake = wrapped
    return true
end

-- Some Workshop/GitHub ZCity builds ship the medical SWEPs without the
-- supplied WoundBridge call at the top of SWEP:Heal.  The connector's embedded
-- bridge can then be fully ready while a bandage never reaches it.  Adapt the
-- registered medical SWEP tables directly instead of depending on that one
-- source-line.  A non-nil bridge result (including false for an opened game or
-- a rejected treatment) is authoritative; nil preserves the original legacy
-- Heal for NPCs/unknown modes.  Supplied SWEPs with their own bridge call are
-- safe too: a handled bridge call returns before their original Heal runs.
local directHealAdapters = setmetatable({}, { __mode = "k" })

function WSZC.InstallDirectSwepHealAdapters()
    local wb = WB()
    if not (wb and type(wb.SwepHeal) == "function")
        or type(weapons) ~= "table" or type(weapons.GetStored) ~= "function" then return 0 end

    local classes = { weapon_medkit_sh = true }
    for class in pairs(type(wb.SwepSpecs) == "table" and wb.SwepSpecs or {}) do
        classes[class] = true
    end

    local installedCount = 0
    for class in pairs(classes) do
        local stored = weapons.GetStored(class)
        if type(stored) == "table" and type(stored.Heal) == "function"
            and not directHealAdapters[stored] then
            local weaponClass = class
            local original = stored.Heal
            directHealAdapters[stored] = true
            stored._WSZCDirectHealOriginal = original
            stored.Heal = function(self, ent, mode, bone)
                local bridge = WB()
                local supported = type(WSZC.Supports) ~= "function" or WSZC.Supports("medicine")
                if WSZC.Ready and Authority() and supported
                    and bridge and type(bridge.SwepHeal) == "function" then
                    local a, b, c = bridge.SwepHeal(self, ent, mode, bone)
                    WSZC.LastMedicalHealRoute = weaponClass .. " -> bridge (" .. tostring(a) .. ")"
                    if a ~= nil then return a, b, c end
                end
                WSZC.LastMedicalHealRoute = weaponClass .. " -> legacy"
                return original(self, ent, mode, bone)
            end
            installedCount = installedCount + 1
        end
    end

    if installedCount > 0 then
        WSZC.DirectMedicalAdapterCount = (WSZC.DirectMedicalAdapterCount or 0) + installedCount
        Debug("direct Workshop medical SWEP adapters installed: %d", installedCount)
    end
    return installedCount
end

-- The radial DislocatedJoint options call hg_fixdislocation, whose old
-- WoundBridge branch performs a chance-based instant reduction.  That is a
-- second medical path around the real C:U minigame.  Block BOTH the public
-- bridge function and the console command while WSZC is ready.  Returning
-- true from WB.FixDislocation is intentional: stock sv_organism.lua treats it
-- as "handled" and returns before its legacy implementation.
local legacyFixDislocationWrapper
function WSZC.InstallLegacyRadialMedicineBlock()
    local blocked = WSZC.LegacyRadialMedicineBlocked
        and WSZC.LegacyRadialMedicineBlocked() or false
    local wb = WB()
    if wb and type(wb.FixDislocation) == "function"
        and wb.FixDislocation ~= legacyFixDislocationWrapper then
        local original = wb.FixDislocation
        legacyFixDislocationWrapper = function(fixer, args)
            if WSZC.LegacyRadialMedicineBlocked
                and WSZC.LegacyRadialMedicineBlocked() then return true end
            return original(fixer, args)
        end
        wb.FixDislocation = legacyFixDislocationWrapper
    end

    if concommand and concommand.GetTable and concommand.Add then
        local commands = concommand.GetTable()
        local entry = commands and commands.hg_fixdislocation
        local callback = type(entry) == "table" and (entry[1] or entry.callback) or entry
        if type(callback) == "function" and callback ~= WSZC._LegacyFixDislocationCommandWrapper then
            local original = callback
            WSZC._LegacyFixDislocationCommandWrapper = function(ply, ...)
                if WSZC.LegacyRadialMedicineBlocked
                    and WSZC.LegacyRadialMedicineBlocked() then return true end
                return original(ply, ...)
            end
            concommand.Add("hg_fixdislocation", WSZC._LegacyFixDislocationCommandWrapper)
        end
    end
    if timer and timer.Create then
        local timerName = "WSZC_LegacyRadialMedicineBlock"
        local exists = timer.Exists and timer.Exists(timerName)
        if not exists then
            timer.Create(timerName, 5, 0, function()
                if WSZC.InstallLegacyRadialMedicineBlock then WSZC.InstallLegacyRadialMedicineBlock() end
            end)
        end
    end
    return blocked, wb ~= nil
end

local function InstallMedicalBridge()
    WSZC.InstallTourniquetRemovalBridge()
    WSZC.InstallLegacyRadialMedicineBlock()
    local wb = WB()
    if not (wb and wb.SwepHeal) then return false end
    PatchBridgePlayerResolver(wb)
    PatchBodyDrugSpecs(wb)
    PatchBloodBagTake(wb)
    InstallTimedEffectBridge()
    WSZC.InstallDirectSwepHealAdapters()
    if wb._WSZCSwepHealPatched then return true end
    wb._WSZCSwepHealPatched = true
    local original = wb.SwepHeal
    PatchTourniquetBestLimb(original)
    wb.SwepHeal = function(swep, ent, mode, bone)
        if not Authority() then return original(swep, ent, mode, bone) end
        local ply = OwnerOf(ent) or (IsValid(ent) and ent:IsPlayer() and ent)
        local before = ply and WSZC.SnapshotMedical(ply, "body") or nil
        local previousRoute = WSZC.TourniquetLimbOverride
        local routedLimb
        if ply then
            local routeOk, resolved = pcall(WSZC.ResolveTourniquetLimb, swep, ent, mode, bone)
            if routeOk then routedLimb = resolved
            else Warn("tourniquet aim resolve failed: " .. tostring(resolved)) end
        end
        if routedLimb then
            routedLimb = WSZC.TourniquetApplicationSite(ply, routedLimb) or routedLimb
        end
        if routedLimb then
            WSZC.TourniquetLimbOverride = { ply = ply, limbId = routedLimb }
            Debug("tourniquet route %s/%s", tostring(ply), tostring(routedLimb))
        end
        WSZC.SwepHealDepth = WSZC.SwepHealDepth + 1
        local ok, a, b, c = pcall(original, swep, ent, mode, bone)
        WSZC.SwepHealDepth = WSZC.SwepHealDepth - 1
        if WSZC.SwepHealDepth < 0 then WSZC.SwepHealDepth = 0 end
        WSZC.TourniquetLimbOverride = previousRoute
        if not ok then
            Warn("WB.SwepHeal failed: " .. tostring(a))
            return nil
        end
        if ply and before then
            WSZC.ApplyMedicalDelta(ply, "body", before)
        end
        return a, b, c
    end
    return true
end
WSZC.InstallMedicalBridge = InstallMedicalBridge

local function DisableCUPhysiology()
    if not Authority() then return end
    local c = Constants() or {}
    for _, name in ipairs({
        c.LimbTimerName or "WoundSystem_LimbTick",
        c.CardioTimerName or "WoundSystem_CardioTick",
        (c.CardioTimerName or "WoundSystem_CardioTick") .. "_Start",
        "WoundSystem_UnconsciousTimescaleCheck",
        "WoundSystem_LimbLossDropWeapon",
        "WoundSystem_MissingHandWeaponDrop",
    }) do
        if timer.Exists(name) then timer.Remove(name) end
    end
    -- C:U must not run a second health simulation, but its shrapnel session
    -- safety tick (WoundSystem_ShrapnelTick) MUST stay alive for the minigame.
    hook.Remove("Think", "WoundSystem_HEV_AutoMedic")
    hook.Remove("Think", "WoundSystem_SelfHarmServerThink")
    hook.Remove("EntityTakeDamage", "WoundSystem_HappinessDamageMemory")
    hook.Remove("PostEntityTakeDamage", "WoundSystem_LobotomyTriggerTakeDamage")
    hook.Remove("EntityTakeDamage", "WoundSystem_TalkerHitByCreature")
end

--- C:U's server config sets DONT_BLEED on every player while
--- `woundsys_replace_vanilla_blood 1` (its default), which SILENCES ZCity's /
--- Hemogen's own blood.  The owner wants only ZCity effects, so restore the
--- vanilla blood colour and keep C:U's blood purely as data (no decals).
--- Patching the function (instead of just setting the convar) also covers
--- C:U re-applying it on spawn / convar change.
function WSZC.DisableCUBloodReplacement()
    local cfg = WoundSystem and WoundSystem.Health and WoundSystem.Health.Config
    if not (cvCUBlood and cvCUBlood:GetBool()) then
        if WSZC._CUBloodOriginal and cfg then
            cfg.ApplyVanillaBloodMode = WSZC._CUBloodOriginal
        end
        WSZC._CUBloodOriginal = nil
        return false
    end
    if not (cfg and type(cfg.ApplyVanillaBloodMode) == "function") then return false end
    if not WSZC._CUBloodOriginal then
        WSZC._CUBloodOriginal = cfg.ApplyVanillaBloodMode
        cfg.ApplyVanillaBloodMode = function(ent)
            if not (IsValid(ent) and ent.SetBloodColor) then return end
            if ent:IsPlayer() then ent:SetBloodColor(BLOOD_COLOR_RED or 0) end
        end
    end
    if player and player.GetAll then
        for _, ply in ipairs(player.GetAll()) do pcall(cfg.ApplyVanillaBloodMode, ply) end
    end
    return true
end

---------------------------------------------------------------------------
-- "Reset organism" must NOT stand the character up
---------------------------------------------------------------------------
-- ZCity's `hg_organism_clear` / the admin "Reset organism" property clear the
-- whole organism table.  WB.ResetOrganism() additionally calls
-- WB.RestoreRagdoll(..., false), which runs hg.FakeUp(ply, true) and resets
-- org.fake / org.needfake.  That is the "character gets up by himself".
-- The owner wants the reset to clean the wounds but KEEP the ZCity organism
-- structure (unconscious / fake-ragdoll state), i.e. never auto-stand.
-- Only the "down / unconscious" structure is preserved.  Wounds, blood,
-- organs, health etc. are still cleared -- that is what "reset" is for.
-- ONLY the "still down" structure is preserved.  The previous list also
-- carried canmove / stun / consciousness / brain over from the injured state;
-- after a reset those stayed at their wounded values, so ZCity (and the
-- HG_MovementCalc_2 hooks) kept the player at walking speed forever.  A reset
-- must clear wounds AND lift movement penalties while still not standing the
-- character up by itself.
local RESET_KEEP = {
    "otrub", "needotrub", "fake", "needfake",
    "alive", "otrub_start", "unconscious",
}

-- An EXPLICIT admin reset is different from a FakeUp spawn.  Preserve the
-- physical ragdoll, but never restore brain-death/unconscious flags after the
-- native clear: doing so re-applies the blackout and blocks OpenHealthHUD().
local RESET_EXPLICIT_KEEP = { "fake", "needfake" }

local SHRAPNEL_SHADOW_KEYS = {
    "wszc_shrapnel", "wszc_shrapnel_floor", "wszc_shrapnel_irritation",
    "wszc_shrapnel_sources", "wszc_bandaged_shrapnel", "wszc_infection",
    "wszc_shrapnel_aftercare", "wszc_shrapnel_closed", "wszc_shrapnel_aftercare_closed",
}

local function SnapshotZCityStructure(org, preserveShrapnel, explicitReset)
    local snap = {}
    local keys = explicitReset and RESET_EXPLICIT_KEEP or RESET_KEEP
    for _, key in ipairs(keys) do snap[key] = org[key] end
    if explicitReset then
        local owner = org.owner
        local down = org.otrub == true or org.needotrub == true
            or org.fake == true or org.needfake == true
            or (IsValid(owner) and IsValid(owner.FakeRagdoll))
        -- Conscious does NOT mean standing: retain just the ragdoll request.
        snap.fake, snap.needfake = down == true, down == true
    end
    -- Only a ragdoll transition keeps fragments.  An EXPLICIT admin reset
    -- passes false and therefore cannot resurrect them after Clear().
    if preserveShrapnel ~= false then
        for _, key in ipairs(SHRAPNEL_SHADOW_KEYS) do snap[key] = org[key] end
    end
    return snap
end

--- hg.FakeUp() calls ply:Spawn() internally with OverrideSpawn=true.  ZCity's
--- Player Spawn hook consequently runs Org Clear on a character who is merely
--- standing up, not respawning.  A selective shrapnel/down snapshot is not
--- enough here: it loses native wounds, arterialwounds, amputations, organs and
--- third-party organism fields.  Snapshot the COMPLETE organism (except its
--- entity owner), with cycle-safe table copies, and restore it after all native
--- Org Clear hooks have run.  Explicit admin reset and genuine respawn never
--- enter this path and still clear injuries normally.
local function CopyRagdollValue(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, nested in pairs(value) do
        copy[key] = CopyRagdollValue(nested, seen)
    end
    if setmetatable and getmetatable then setmetatable(copy, getmetatable(value)) end
    return copy
end

local function SnapshotRagdollOrganism(org)
    if type(org) ~= "table" then return nil end
    local snap = {}
    for key, value in pairs(org) do
        if key ~= "owner" then snap[key] = CopyRagdollValue(value) end
    end
    return snap
end

local function RestoreRagdollOrganism(org, snap)
    if type(org) ~= "table" or type(snap) ~= "table" then return end
    for key, value in pairs(snap) do
        if key ~= "owner" then org[key] = value end
    end
end

local function IsExplicitReset(ply)
    return (WSZC._ExplicitResetDepth or 0) > 0
        or (IsValid(ply) and ply._WSZCExplicitReset == true)
end

function WSZC.ClearAllShrapnel(ply, org)
    if type(org) == "table" then
        RemoveLodgedWounds(org)
        for _, key in ipairs(SHRAPNEL_SHADOW_KEYS) do org[key] = nil end
        org.wounds = {}
        org.arterialwounds = {}
        org.bleed, org.internalBleed, org.bleedStart = 0, 0, 0
        -- Native Org Clear "Main" resets org.chest but forgets brokenribs.
        -- Fractured() reads that derived field, so leaving it behind brings
        -- the red thorax fracture icon straight back on the next shadow pass.
        org.brokenribs = 0
        org.pain, org.avgpain, org.painadd = 0, 0, 0
        org.shock, org.hurt, org.hurtadd = 0, 0, 0
        org.immobilization, org.disorientation = 0, 0
        org.wsmovemult, org._wbSentMove, org._wbNextMoveSend = nil, nil, nil
        org.dmgstack, org.LodgedEntities = {}, nil
        for _, flag in ipairs({ "arteria", "rarmartery", "larmartery",
            "rlegartery", "llegartery", "spineartery", "neckartery" }) do
            org[flag] = 0
        end
    end

    if IsValid(ply) then
        ply._WSZCTimedBodyEffects = nil
        ply._WSZCTourniquetCycles = nil
        ply._WSZCNextTourniquetSync = nil
        ply._WSZCNextSplintSync = nil
        if WSZC.StopAllMinigames then WSZC.StopAllMinigames(ply, "zcity_compat_reset", true) end
        local h = H()
        if h and h.ResetPlayer then pcall(h.ResetPlayer, ply)
        elseif h and h.InitPlayer then pcall(h.InitPlayer, ply) end
        local limbs = h and h.GetLimbs and h.GetLimbs(ply)
        if type(limbs) == "table" then
            for limbId, state in pairs(limbs) do
                if type(state) == "table" then
                    state.shrapnel, state.bleed, state.pain = 0, 0, 0
                    state.broken, state.dislocated = false, false
                    state.isBandaged, state.wszcBandagedShrapnel = false, false
                    state.tourniqueted, state.blockedBleeding = false, false
                    state.tourniquetPain, state.tourniquetDurability = 0, nil
                    state.tourniquetSourceSlot = nil
                    state.splinted, state.splintItemId, state.splintSourceSlot = false, nil, nil
                    if type(state.customStatuses) == "table" then
                        state.customStatuses.SPLINTED = nil
                        state.customStatuses.TOURNIQUET = nil
                    end
                    state.bandageSlowAmount = 0
                    state.infection, state.infectionSpeed = 0, 0
                    state.dislocationTimer = 0
                    if h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, limbId, true) end
                end
            end
            ply._WSZCLimbsRef = limbs
        end

        -- Explicit reset also removes ZCity's own medical presentation.  A
        -- stale bandaged_limbs entry would otherwise keep rendering a dressing
        -- after every real wound and infection has already been cleared.
        local owner = type(org) == "table" and org.owner or nil
        local entities = { ply, owner, ply.FakeRagdoll }
        local seen = {}
        for _, ent in ipairs(entities) do
            if IsValid(ent) and not seen[ent] then
                seen[ent] = true
                ent.bandaged_limbs, ent.tourniquets = {}, {}
                if ent.SetNetVar then
                    pcall(ent.SetNetVar, ent, "bandaged_limbs", ent.bandaged_limbs)
                    pcall(ent.SetNetVar, ent, "Tourniquets", ent.tourniquets)
                end
            end
        end
        if hg and type(hg.TourniquetGuys) == "table" then
            for i = #hg.TourniquetGuys, 1, -1 do
                if seen[hg.TourniquetGuys[i]] then table.remove(hg.TourniquetGuys, i) end
            end
            if SetNetVar then pcall(SetNetVar, "TourniquetGuys", hg.TourniquetGuys) end
        end
        ply._WSZCExpectedBleed, ply._WSZCExpectedPain = {}, {}
        ply._WSZCExpectedDislocation = {}
        ply._WSZCShrapnelCarry = nil
        ply._WSZCRagdollTransitionUntil = nil
        ply.HitBones = {}
        ply._WSZCLastComplication, ply._WSZCLastComplicationLimb = nil, nil
        ply.fullsend = true
        if ply.SetNetVar and type(org) == "table" then
            pcall(ply.SetNetVar, ply, "wounds", org.wounds)
            pcall(ply.SetNetVar, ply, "arterialwounds", org.arterialwounds)
        end
    end
    return true
end

--- `down` is already false by the time some ZCity builds call Clear() on
--- wake-up (the FakeRagdoll entity was removed first), so the structure
--- snapshot above is skipped entirely.  Re-attach just the shrapnel shadow
--- whenever a Fake / FakeUp / HG_OnWakeOtrub transition is in progress.
local function RestoreShrapnelShadow(org)
    if type(org) ~= "table" then return end
    local owner = org.owner
    if IsExplicitReset(owner) then return end
    local ply = IsValid(owner) and owner or nil
    if not ply then return end
    local now = CurTime and CurTime() or 0
    if (ply._WSZCRagdollTransitionUntil or 0) <= now then return end
    local carry = ply._WSZCShrapnelCarry
    if type(carry) ~= "table" then return end
    for _, key in ipairs(SHRAPNEL_SHADOW_KEYS) do
        if type(carry[key]) == "table" then org[key] = carry[key] end
    end
end

--- Called right before any hg.organism.Clear()/wb.ResetOrganism() while a
--- ragdoll transition is active, so the shadow survives even if the stock
--- Clear() wipes every field.
local function CarryShrapnelShadow(ply, org)
    if not (IsValid(ply) and type(org) == "table") then return end
    if IsExplicitReset(ply) then return end
    local now = CurTime and CurTime() or 0
    if (ply._WSZCRagdollTransitionUntil or 0) <= now then return end
    local carry = {}
    for _, key in ipairs(SHRAPNEL_SHADOW_KEYS) do
        if type(org[key]) == "table" then carry[key] = org[key] end
    end
    ply._WSZCShrapnelCarry = carry
end
WSZC.CarryShrapnelShadow = CarryShrapnelShadow
WSZC.RestoreShrapnelShadow = RestoreShrapnelShadow

--- Explicitly lift the speed / sprint penalties: some ZCity builds do not
--- reinitialise these fields in hg.organism.Clear(), they just leave them as
--- they were.  Without this a healed character still cannot sprint.
local function ClearMovementPenalties(org)
    if type(org) ~= "table" then return end
    if org.canmove == false then org.canmove = true end
    if type(org.stun) == "number" and org.stun > 0 then org.stun = 0 end
    if type(org.pain) == "number" and org.pain > 0 then org.pain = 0 end
    if type(org.legs) == "table" then
        -- ZCity / Organs+ keep per-leg damage here; a reset wipes wounds, so
        -- the movement limiter must not keep the old broken-leg value.
        for _, key in ipairs({ "l", "r", "left", "right", "L", "R" }) do
            if type(org.legs[key]) == "number" and org.legs[key] > 0 then org.legs[key] = 0 end
        end
    end
end
WSZC.ClearMovementPenalties = ClearMovementPenalties

local function RestoreZCityStructure(org, snap, preserveMovement, explicitReset)
    if type(org) ~= "table" or type(snap) ~= "table" then return end
    for key, value in pairs(snap) do org[key] = value end
    local owner = org.owner
    if explicitReset then
        -- These are injuries/lifecycle state, not the physical ragdoll.  In
        -- particular brain >= 0.7 can set alive=false and brain trauma leaves
        -- otrub/unconscious set; neither may survive an explicit full reset.
        if IsValid(owner) and owner.Alive then org.alive = owner:Alive() == true end
        org.otrub, org.needotrub, org.unconscious = false, false, false
        org.otrub_start, org.uncon_timer = nil, 0
        if IsValid(owner) then owner._WSZCShadowNext = 0 end
    end
    if not preserveMovement then ClearMovementPenalties(org) end
    if IsValid(owner) then owner.fullsend = true end
    if hg then
        if hg.send_organism then pcall(hg.send_organism, org) end
        if hg.send_bareinfo then pcall(hg.send_bareinfo, org) end
    end
    -- Keep the C:U shadow (HUD / NWBool) in sync with the ZCity structure.
    -- Explicit reset bypasses the 4 Hz throttle so inspection is unblocked NOW.
    if cvShadow and cvShadow:GetBool() and IsValid(owner) then
        pcall(PushShadow, owner, org)
    end
end

function WSZC.InstallResetStructureGuard()
    local wb = WB()
    local clear = hg and hg.organism and hg.organism.Clear
    if not (wb and type(clear) == "function") then return false end
    -- Re-check late properties/commands as well as replaced ZCity functions.
    -- Saved native originals below make this idempotent (no wrapper nesting).
    WSZC._ResetGuardPatched = true

    -- A later addon may replace either function.  Re-wrap that new function on
    -- the 5-second authority pass, but never wrap our own wrapper recursively.
    local originalClear = (clear == WSZC._ResetClearWrapper and WSZC._ResetClearOriginal) or clear
    hg.organism.Clear = function(org, ...)
        if not (cvPreserveReset and cvPreserveReset:GetBool() and Authority()) then
            return originalClear(org, ...)
        end
        if type(org) ~= "table" then return originalClear(org, ...) end
        local owner = org.owner
        local explicit = IsExplicitReset(owner)
        local fakeUpSpawn = not explicit and OverrideSpawn == true
        local genuineSpawn = IsValid(owner) and (owner._WSZCGenuineSpawnDepth or 0) > 0
        local deadOwner = IsValid(owner) and owner.IsPlayer and owner:IsPlayer() and not owner:Alive()
        -- otrub/fake are INJURY flags, not proof of FakeUp: they routinely
        -- survive until PostPlayerDeath/PlayerSpawn.  Only a genuine spawn
        -- context or a dead player may force the full new-life clear.  A direct
        -- Clear on a living ragdoll outside Player Spawn keeps its old down
        -- structure, preserving the existing admin/third-party behaviour.
        local down = not genuineSpawn and not deadOwner and (fakeUpSpawn
            or (IsValid(owner) and IsValid(owner.FakeRagdoll))
            or org.otrub == true or org.fake == true)
        local preserveTransition = not explicit and not genuineSpawn and not deadOwner
        local snap = SnapshotZCityStructure(org, preserveTransition, explicit)
        local ragdollSnap = fakeUpSpawn and SnapshotRagdollOrganism(org) or nil
        CarryShrapnelShadow(owner, org)
        local a, b, c = originalClear(org, ...)
        if ragdollSnap then RestoreRagdollOrganism(org, ragdollSnap) end

        if explicit then
            -- This branch is ONLY hg_organism_clear / WB.ResetOrganism, never
            -- an ordinary Fake/FakeUp transition.  No carry table, no shrapnel
            -- snapshot and no tagged wound is allowed to survive it.
            WSZC.ClearAllShrapnel(owner, org)
            RestoreZCityStructure(org, snap, false, true)
            return a, b, c
        end

        if not down then
            if IsValid(owner) then
                owner._WSZCTourniquetCycles = nil
                owner._WSZCNextTourniquetSync = nil
                if genuineSpawn or deadOwner then
                    owner._WSZCRagdollTransitionUntil = nil
                    owner._WSZCShrapnelCarry = nil
                end
            end
            if genuineSpawn and owner._WSZCSpawnCleanupAt ~= (CurTime and CurTime() or 0) then
                -- Native Org Clear does not know connector-owned shrapnel,
                -- tourniquet/minigame or timed-effect fields.  Clear those too,
                -- otherwise the next NEW PlayerLimbs table can restore the old
                -- life even after every native limb scalar was reset.
                --
                -- Do this on RESPAWN, not PostPlayerDeath: ZCity shallow-copies
                -- organism tables into its death ragdoll before calling Clear,
                -- so removing wound rows at death could also edit the corpse.
                owner._WSZCSpawnCleanupAt = CurTime and CurTime() or 0
                WSZC.ClearAllShrapnel(owner, org)
            end
            RestoreShrapnelShadow(org)
            -- A genuine standing spawn is a real clear, not a ragdoll
            -- transition.  Cover the same native brokenribs omission here;
            -- FakeUp/down transitions deliberately keep the injury instead.
            org.brokenribs = 0
            ClearMovementPenalties(org)
            return a, b, c
        end
        RestoreZCityStructure(org, snap, fakeUpSpawn)
        return a, b, c
    end
    WSZC._ResetClearOriginal = originalClear
    WSZC._ResetClearWrapper = hg.organism.Clear

    if type(wb.ResetOrganism) == "function" then
        local originalReset = (wb.ResetOrganism == WSZC._ResetWBWrapper and WSZC._ResetWBOriginal)
            or wb.ResetOrganism
        local originalRestore = wb.RestoreRagdoll
        wb.ResetOrganism = function(ent, ...)
            if not (cvPreserveReset and cvPreserveReset:GetBool() and Authority()) then
                return originalReset(ent, ...)
            end

            local ply
            if wb.GetPlayer then
                local ok, resolved = pcall(wb.GetPlayer, ent)
                if ok then ply = resolved end
            end
            ply = ply or OwnerOf(ent, true)
            local org = IsValid(ply) and ply.organism or nil
            if IsValid(ply) then ply._WSZCExplicitReset = true end
            WSZC._ExplicitResetDepth = (WSZC._ExplicitResetDepth or 0) + 1
            CarryShrapnelShadow(ply, org)
            local snap = type(org) == "table" and SnapshotZCityStructure(org, false, true) or nil

            -- Suppress only WB's explicit stand-up call, and ALWAYS restore the
            -- function, including a native error.  Keep a real traceback in the
            -- server console so an incompatible ZCity build is diagnosable.
            wb.RestoreRagdoll = function() return true end
            local argv = { n = select("#", ...), ... }
            local function traceback(err)
                return debug and debug.traceback and debug.traceback(tostring(err), 2) or tostring(err)
            end
            local ok, res = xpcall(function()
                return originalReset(ent, Unpack(argv, 1, argv.n))
            end, traceback)
            wb.RestoreRagdoll = originalRestore

            local cleanupOK, cleanupErr = xpcall(function()
                -- H.ResetPlayer / third-party hooks may replace the organism
                -- or C:U limb tables.  Never clean a stale pre-reset table.
                local currentOrg = IsValid(ply) and ply.organism or org
                if (not ok or res == false) and type(currentOrg) == "table" then
                    -- WB.GetPlayer rejects dead players and WB.IsEnabled() can
                    -- be false on mixed builds.  Use the stock native fallback.
                    local clearOK, clearErr = xpcall(function()
                        originalClear(currentOrg)
                        return true
                    end, traceback)
                    if not clearOK then Warn("hg.organism.Clear reset fallback failed: " .. tostring(clearErr)) end
                end
                WSZC.ClearAllShrapnel(ply, currentOrg)
                if snap and type(currentOrg) == "table" then RestoreZCityStructure(currentOrg, snap) end
                ClearMovementPenalties(currentOrg)
                if IsValid(ply) and type(currentOrg) == "table" then
                    ply.fullsend = true
                    if hg.send_organism then pcall(hg.send_organism, currentOrg, ply) end
                    if hg.send_bareinfo then pcall(hg.send_bareinfo, currentOrg) end
                end
                return true
            end, traceback)

            -- Finally, on BOTH native and cleanup failures: later ragdoll Clear
            -- calls must never inherit a stale explicit-reset marker.
            WSZC._ExplicitResetDepth = math.max((WSZC._ExplicitResetDepth or 1) - 1, 0)
            if IsValid(ply) then ply._WSZCExplicitReset = nil end
            if not ok then
                Warn("WB.ResetOrganism failed; native Clear fallback was attempted:\n" .. tostring(res))
            end
            if not cleanupOK then
                Warn("WB.ResetOrganism cleanup failed:\n" .. tostring(cleanupErr))
            end
            return (ok and cleanupOK) and res or false
        end
        WSZC._ResetWBOriginal = originalReset
        WSZC._ResetWBWrapper = wb.ResetOrganism
    end

    -- Stock reset_org maps a ragdoll through hg.RagdollOwner(), then prints
    -- ent:Nick().  For a DEATH ragdoll the native resolver returns nil, so the
    -- old callback both failed to identify the player and called Player:Nick
    -- on a ragdoll.  Supply the dead owner ONLY during this admin callback;
    -- normal damage/ragdoll ownership semantics remain unchanged.
    if properties and properties.GetTable then
        local ok, list = pcall(properties.GetTable)
        local entry = ok and type(list) == "table" and list.reset_org or nil
        if type(entry) == "table" and type(entry.Receive) == "function"
            and not entry._WSZCResetReceivePatched then
            local originalReceive = entry.Receive
            entry._WSZCResetReceivePatched = true
            entry._WSZCOriginalReceive = originalReceive
            entry.Receive = function(self, ...)
                local originalResolver = hg.RagdollOwner
                hg.RagdollOwner = function(ent, ...)
                    if originalResolver then
                        local ok, owner = pcall(originalResolver, ent, ...)
                        if ok and IsValid(owner) then return owner end
                    end
                    return OwnerOf(ent, true, true)
                end
                WSZC._ExplicitResetDepth = (WSZC._ExplicitResetDepth or 0) + 1
                local argv = { n = select("#", ...), ... }
                local ok, res = xpcall(function()
                    return originalReceive(self, Unpack(argv, 1, argv.n))
                end, function(err)
                    return debug and debug.traceback and debug.traceback(tostring(err), 2) or tostring(err)
                end)
                WSZC._ExplicitResetDepth = math.max((WSZC._ExplicitResetDepth or 1) - 1, 0)
                hg.RagdollOwner = originalResolver
                if not ok then
                    Warn("reset_org Receive failed:\n" .. tostring(res))
                    return false
                end
                return res
            end
        end
    end

    -- WB.ResetOrganism normally covers the command, but the stock command has
    -- a direct hg.organism.Clear fallback (and can reset a list of players).
    -- Mark that whole callback as explicit so NONE of those paths preserves
    -- shrapnel as though it were a ragdoll transition.
    if concommand and concommand.GetTable and concommand.Add
        and not WSZC._ResetCommandPatched then
        local commands = concommand.GetTable()
        local entry = commands and commands.hg_organism_clear
        local callback = type(entry) == "table" and (entry[1] or entry.callback) or entry
        if type(callback) == "function" then
            WSZC._ResetCommandPatched = true
            concommand.Add("hg_organism_clear", function(...)
                WSZC._ExplicitResetDepth = (WSZC._ExplicitResetDepth or 0) + 1
                local ok, a, b, c = pcall(callback, ...)
                WSZC._ExplicitResetDepth = math.max((WSZC._ExplicitResetDepth or 1) - 1, 0)
                if not ok then error(a, 0) end
                return a, b, c
            end)
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Spawn context and accepted native dislocation completion
---------------------------------------------------------------------------

local spawnContextByKey, spawnContextFns = {}, setmetatable({}, { __mode = "k" })

--- Wrap the actual ZCity clear hook, not PlayerSpawn's undefined registration
--- order.  A living unconscious player and a genuine respawn can have exactly
--- the same otrub/fake flags; only this call context distinguishes them.
function WSZC.InstallSpawnContextGuard()
    if type(hook) ~= "table" or type(hook.GetTable) ~= "function" then return false end
    local installedAny = false
    for _, event in ipairs({ "Player Spawn", "PlayerSpawn" }) do
        local hooks = hook.GetTable()[event]
        local current = hooks and hooks["homigrad-organism"]
        if type(current) == "function" and spawnContextByKey[event] ~= current
            and not spawnContextFns[current] then
            local original = current
            local function wrapped(ply, ...)
                -- FakeUp's internal ply:Spawn() is protected by ZCity's own
                -- OverrideSpawn.  It must never be labelled a new life.
                if not Authority() or OverrideSpawn == true or not IsValid(ply) then
                    if IsValid(ply) and OverrideSpawn == true then
                        ply._WSZCSpawnKind = "ragdoll"
                    end
                    return original(ply, ...)
                end
                ply._WSZCSpawnKind = "genuine"
                ply._WSZCRagdollTransitionUntil = nil
                ply._WSZCShrapnelCarry = nil
                ply._WSZCGenuineSpawnDepth = (ply._WSZCGenuineSpawnDepth or 0) + 1
                local a, b, c, d = pcall(original, ply, ...)
                ply._WSZCGenuineSpawnDepth = math.max((ply._WSZCGenuineSpawnDepth or 1) - 1, 0)
                if not a then error(b, 0) end
                return b, c, d
            end
            spawnContextFns[wrapped] = true
            spawnContextByKey[event] = wrapped
            hook.Add(event, "homigrad-organism", wrapped)
            installedAny = true
        elseif type(current) == "function" then
            installedAny = true
        end
    end
    return installedAny
end

-- Shared by the ordinary native receiver wrapper and the rendered-position
-- completion packet below.  Only a real C:U true -> false transition may clear
-- the authoritative ZCity group; a client prediction alone never calls this.
function WSZC.CommitNativeDislocationReduction(ply, limbId)
    if not (Authority() and IsValid(ply) and type(ply.organism) == "table") then return false end
    local map = LIMB_ORG[limbId]
    local h = H()
    local limbs = h and h.GetLimbs and h.GetLimbs(ply) or nil
    local state = type(limbs) == "table" and limbs[limbId] or nil
    if not (map and map.dis and type(state) == "table") then return false end
    if state.dislocated == true or ply.organism[map.dis] ~= true then return false end

    ply._WSZCExpectedDislocation = ply._WSZCExpectedDislocation or {}
    ply._WSZCExpectedDislocation[limbId] = true
    if not WSZC.SyncDislocation(ply, ply.organism, limbs, false) then return false end

    -- Close the race with RestoreBones()/spawn timers and make the completed
    -- reduction visible immediately instead of waiting for the 4 Hz shadow.
    ply.fullsend = true
    ply._WSZCShadowNext = 0
    if hg.send_organism then pcall(hg.send_organism, ply.organism, ply) end
    if hg.send_bareinfo then pcall(hg.send_bareinfo, ply.organism) end
    if cvShadow and cvShadow:GetBool() then pcall(PushShadow, ply, ply.organism) end
    return true
end

-- Native C:U uses client-predicted rendering but a second server-side physics
-- copy.  Accept the position the player actually sees only inside a live native
-- session and only when it satisfies the same socket tolerance.  The server
-- still owns the limb transition, happiness, update and session close.  Remote
-- treatment resolves the patient through RemoteNativeSessions and revalidates
-- the operator pair; no limb id or patient entity is trusted from the packet.
function WSZC.HandleDislocationVisualComplete(operator, sessionId, x, y)
    if not (WSZC.Ready and Authority() and IsValid(operator) and operator:Alive()) then return false end
    if not WSZC.DislocationVisualAligned or not WSZC.DislocationVisualAligned(x, y) then return false end
    x, y = tonumber(x), tonumber(y)
    if not x or not y or x < -500 or x > 900 or y < -500 or y > 500 then return false end
    sessionId = math.floor(tonumber(sessionId) or 0)
    if sessionId <= 0 then return false end

    if (type(WSZC.CUSessions) ~= "table"
        or type(WSZC.CUCloseDislocationSession) ~= "function")
        and WSZC.RefreshNativeSessionRefs then
        -- Modern native-api Setup used to skip these refs entirely.  Lazy
        -- discovery also covers a hot reload immediately before this packet.
        WSZC.RefreshNativeSessionRefs(true)
    end
    local sessions = WSZC.CUSessions
    local byPatient = type(sessions) == "table" and sessions.Dislocation or nil
    if type(byPatient) ~= "table" or type(WSZC.CUCloseDislocationSession) ~= "function" then return false end
    local target, session = operator, byPatient[operator]
    if not session or session.id ~= sessionId then
        target, session = nil, nil
        for patient, byKind in pairs(WSZC.RemoteNativeSessions or {}) do
            local meta = type(byKind) == "table" and byKind.Dislocation or nil
            local candidate = byPatient[patient]
            if meta and meta.operator == operator and candidate and candidate.id == sessionId then
                target, session = patient, candidate
                break
            end
        end
    end
    if not (target and session and IsValid(target) and target:Alive()) then return false end
    if target ~= operator and not (WSZC.RemoteMedicalValidPair
        and WSZC.RemoteMedicalValidPair(operator, target)) then return false end

    local h = H()
    local state = h and h.GetLimbState and h.GetLimbState(target, session.limbId) or nil
    local map = LIMB_ORG[session.limbId]
    if type(state) ~= "table" or state.dislocated ~= true then return false end
    if not (map and map.dis and BoneAnchor(session.limbId, "dislocation")) then return false end
    if type(target.organism) ~= "table" or target.organism[map.dis] ~= true then return false end

    local previousTimer = state.dislocationTimer
    session.boneX, session.boneY = x, y
    session.boneVelX, session.boneVelY = 0, 0
    session.dislocationTimer = 0
    state.dislocated = false
    state.dislocationTimer = 0
    if not WSZC.CommitNativeDislocationReduction(target, session.limbId) then
        -- Never report/close a visual success if the authoritative ZCity
        -- transition failed.  Restore native prediction and the update marker.
        state.dislocated = true
        state.dislocationTimer = previousTimer
        if target._WSZCExpectedDislocation then
            target._WSZCExpectedDislocation[session.limbId] = nil
        end
        if h.SendLimbUpdate then pcall(h.SendLimbUpdate, target, session.limbId, true) end
        return false
    end
    if h.SendLimbUpdate then pcall(h.SendLimbUpdate, target, session.limbId, true) end
    if WoundSystemHappiness and WoundSystemHappiness.Add then
        pcall(WoundSystemHappiness.Add, target, 3)
    end
    pcall(WSZC.CUCloseDislocationSession, target, "complete")

    -- Do not leave the remote operator marked busy until the next watchdog.
    if byPatient[target] == nil and type(WSZC.RemoteNativeSessions) == "table" then
        local byKind = WSZC.RemoteNativeSessions[target]
        if type(byKind) == "table" then
            byKind.Dislocation = nil
            if next(byKind) == nil then WSZC.RemoteNativeSessions[target] = nil end
        end
    end
    return true
end

local nativeDislocationWrapper
function WSZC.InstallNativeDislocationBridge()
    if type(net) ~= "table" or type(net.Receivers) ~= "table" then return false end
    local current = net.Receivers.WoundSystem_DislocationInput
    if type(current) ~= "function" then return false end
    if current == nativeDislocationWrapper then return true end

    local original = current
    nativeDislocationWrapper = function(len, ply, ...)
        if not (Authority() and IsValid(ply)) then return original(len, ply, ...) end
        local h = H()
        local limbs = h and h.GetLimbs and h.GetLimbs(ply) or nil
        local wasDislocated = {}
        if type(limbs) == "table" then
            for limbId, map in pairs(LIMB_ORG) do
                local state = limbs[limbId]
                if map.dis and type(state) == "table" and state.dislocated == true then
                    wasDislocated[limbId] = true
                end
            end
        end

        local a, b, c, d = original(len, ply, ...)
        if type(limbs) ~= "table" or type(ply.organism) ~= "table" then return a, b, c, d end

        for limbId in pairs(wasDislocated) do
            -- The native receiver has already changed the actual server limb.
            -- Commit only that true -> false transition, never boneDrawX/Y.
            WSZC.CommitNativeDislocationReduction(ply, limbId)
        end
        return a, b, c, d
    end
    net.Receivers.WoundSystem_DislocationInput = nativeDislocationWrapper
    return true
end

local function InstallVanillaHooks()
    WSZC.InstallSpawnContextGuard()
    -- Org Think "Main": without this wrapper the hook returns early through
    -- WB.Think() and every vanilla ZCity organ module (and Organs+) is skipped.
    WrapHook("Org Think", "Main")
    -- ZCity hit handling: prevents forwarding to WB.ApplyDamage and lets the
    -- vanilla organ/hitbox/bleed code run.
    -- `pre` captures the unscaled damage: takeRagdollDamage() calls
    -- dmginfo:ScaleDamage(0.15), so PostEntityTakeDamage would otherwise see
    -- only 15% of the real blast damage and C:U's thresholds would never fire.
    WrapHook("EntityTakeDamage", "homigrad-damage", CaptureRawDamage, InjectAfterZCityDamage)
    -- Ragdoll collisions: lets the vanilla glass -> AddWoundManual path run.
    -- Glass shrapnel is a separate hook below so it always fires, even if the
    -- ZCity hook was re-registered after us.
    WrapHook("Ragdoll Collide", "organism")
    -- Standing-player PhysicsCollide callback calls hg.velocityDamage.
    local vd = hg and hg.velocityDamage
    if type(vd) == "function" and not wrappedFns[vd] then
        local function wrapped(...)
            if not Authority() then return vd(...) end
            return WSZC.WithVanillaContext(vd, ...)
        end
        wrappedFns[wrapped] = true
        hg.velocityDamage = wrapped
    end
end

-- Replace WB.Sync / WB.Think so the shadow never overwrites ply.organism.
local function InstallShadowBridge()
    local wb = WB()
    if not wb then return end
    if not wb._WSZCSyncPatched then
        wb._WSZCSyncPatched = true
        wb._WSZCOriginalSync = wb.Sync
        wb.Sync = function(ply, org)
            if not Authority() then
                return wb._WSZCOriginalSync and wb._WSZCOriginalSync(ply, org) or nil
            end
            if cvShadow and cvShadow:GetBool() then
                local ok, err = pcall(PushShadow, ply, org)
                if not ok then Warn("shadow sync failed: " .. tostring(err)) end
            end
            return H() and H().GetBody and H().GetBody(ply) or nil
        end
    end
    if not wb._WSZCThinkPatched then
        wb._WSZCThinkPatched = true
        wb._WSZCOriginalThink = wb.Think
        wb.Think = function(owner, org, dt)
            if not Authority() then
                return wb._WSZCOriginalThink and wb._WSZCOriginalThink(owner, org, dt) or nil
            end
            if cvShadow and cvShadow:GetBool() then
                pcall(PushShadow, owner, org)
            end
            -- ZCity's Org Think "Main" already sends organism/bareinfo in
            -- vanilla mode, so nothing else is needed here.
        end
    end
end

function WSZC.InstallOrganismMode()
    if installed then return true end
    if not (WSZC.Ready and WSZC.H and WB()) then return false end
    if WSZC.Supports and not WSZC.Supports("organism_extensions") then return false end
    installed = true

    -- Stubs make ZCity's vanilla paths authoritative even outside the wrapped
    -- hooks.  WB.Sync/Think are handled separately by InstallShadowBridge.
    Stub("ApplyDamage", false)
    Stub("ApplyCollision", false)
    Stub("ApplyFall", false)
    Stub("AddWoundManual", false)
    Stub("Amputate", false)

    InstallVanillaHooks()
    -- One receiver wrapper per native/autorefresh generation.  The ordinary
    -- 4 Hz SyncDislocation remains a fallback if a third party replaces it;
    -- do not stack a new receiver around remote guards every reapply pass.
    WSZC.InstallNativeDislocationBridge()
    InstallShadowBridge()
    InstallMedicalBridge()
    DisableCUPhysiology()
    WSZC.DisableCUBloodReplacement()
    WSZC.InstallResetStructureGuard()
    WSZC.InstallShrapnelBandageGuard()

    -- Org Think runs at 10 Hz in ZCity.  Our own hook keeps the C:U HUD and the
    -- shrapnel shadow in sync, and holds the regeneration block.
    hook.Add("Org Think", "WSZC_OrganismShadow", function(owner, org, dt)
        if not Authority() then return end
        if not (IsValid(owner) and owner:IsPlayer() and owner:Alive()) then return end
        if type(org) ~= "table" then return end

        WSZC.TickTourniquets(owner, org, dt)
        WSZC.TickSplints(owner, org, dt)
        WSZC.TickTimedBodyEffects(owner, dt)
        if cvShadow and cvShadow:GetBool() then
            local ok, err = pcall(PushShadow, owner, org)
            if not ok then Warn("shadow sync failed: " .. tostring(err)) end
        else
            PullShrapnel(owner, org)
        end

        if cvRegen and cvRegen:GetBool() and org.wszc_shrapnel_floor then
            for limbId, floor in pairs(org.wszc_shrapnel_floor) do
                local map = LIMB_ORG[limbId]
                local n = org.wszc_shrapnel and org.wszc_shrapnel[limbId] or 0
                if map and map.dmg and n > 0 and (tonumber(org[map.dmg]) or 0) < floor then
                    org[map.dmg] = floor
                elseif n <= 0 then
                    org.wszc_shrapnel_floor[limbId] = nil
                end
            end
        end

        -- Keep ordinary ZCity bleeding survivable enough for a physical roll
        -- of bandage.  Arterial wounds do not use bleedingmul and still need a
        -- tourniquet immediately.  Never raise a server's custom lower value.
        local bleedCap = math.max(ConVarFloat(cvBleedingMul, 0.55), 0.01)
        org.bleedingmul = math.min(tonumber(org.bleedingmul) or 1, bleedCap)

        -- Every UNCOVERED lodged fragment grows a tagged real wound and pain.
        -- Extraction removes that lodged source but starts a separate growing
        -- aftercare wound; only a final bandage completes the full cure.
        WSZC.TickLodgedShrapnel(owner, org, dt)
        WSZC.TickShrapnelAftercare(owner, org, dt)
        WSZC.TickBandagedShrapnel(owner, org, dt)
    end)

    -- The organism is authoritative (`organism_authoritative`).  The old
    -- ClearSpawnShrapnel() unconditionally nil'ed org.wszc_shrapnel* on EVERY
    -- PlayerSpawn and repeated it on the next frame, which also fired when
    -- ZCity stood a player up from the unconscious ragdoll: "why does
    -- shrapnel disappear when I get up?".  C:U's WoundSystem_SpawnSync can
    -- restore a persisted limb table on a map change without InitPlayer(),
    -- so a plain respawn must still clear C:U's limbs - but a ragdoll
    -- transition must instead PUSH the surviving organism shadow back in.
    local function ReconcileSpawnShrapnel(ply, delayed)
        if not (Authority() and IsValid(ply)) then return end
        local org = ply.organism
        local h = H()
        local limbs = h and h.GetLimbs and h.GetLimbs(ply)

        local preserved = false
        if type(org) == "table" and type(org.wszc_shrapnel) == "table" then
            for _, value in pairs(org.wszc_shrapnel) do
                if (tonumber(value) or 0) > 0 then preserved = true break end
            end
        end
        -- Fake / FakeUp / HG_OnWakeOtrub set this marker.  GMod does not
        -- guarantee hook order, so it also covers a PlayerSpawn that arrives
        -- before the organism shadow was re-attached.
        local now = CurTime and CurTime() or 0
        local genuine = ply._WSZCSpawnKind == "genuine"
        local transitioning = not genuine and (ply._WSZCRagdollTransitionUntil or 0) > now

        -- A positive shrapnel count alone is NOT a ragdoll-transition proof:
        -- native Org Clear knows nothing about these custom fields, so they can
        -- still be present when a previous life reaches PlayerSpawn.  Once the
        -- death/spawn context says genuine, never restore that old life.
        if not genuine and (preserved or transitioning) then
            WSZC.RestoreShrapnel(ply)
            WSZC.RestoreBones(ply)
            if type(limbs) == "table" then ply._WSZCLimbsRef = limbs end
            return
        end

        -- Genuine respawn / map change.  Normally the wrapped native Clear has
        -- already reset the connector.  Repeat that cleanup as a compatibility
        -- fallback when it has not run yet.  The DELAYED call must always do
        -- one final reset: C:U LoadPlayerPersistData mutates the SAME limb
        -- table from another PlayerSpawn hook, so table identity/CurTime cannot
        -- prove that a late restore did not reintroduce the previous life.
        if genuine and (delayed == true or ply._WSZCSpawnCleanupAt ~= now) then
            ply._WSZCSpawnCleanupAt = now
            WSZC.ClearAllShrapnel(ply, org)
            limbs = h and h.GetLimbs and h.GetLimbs(ply) or limbs
        end
        if type(limbs) ~= "table" then return end
        for limbId, state in pairs(limbs) do
            if type(state) == "table" and (tonumber(state.shrapnel) or 0) > 0 then
                state.shrapnel = 0
                if h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, limbId, true) end
            end
        end
        -- The table is now known and clean.  Without this, SyncShrapnel would
        -- interpret its first sight as a ragdoll reset and restore from org.
        ply._WSZCLimbsRef = limbs
    end
    WSZC.ReconcileSpawnShrapnel = ReconcileSpawnShrapnel

    hook.Add("PlayerSpawn", "WSZC_OrganismSpawn", function(ply)
        if not Authority() then return end
        ReconcileSpawnShrapnel(ply, false)
        timer.Simple(0, function()
            if IsValid(ply) then ReconcileSpawnShrapnel(ply, true) end
        end)
    end)

    -- Re-apply: other addons (or a woundsys_enabled toggle) may re-register
    -- these hooks/timers later.  Same defensive pattern as the damage wrapper.
    timer.Create("WSZC_AuthorityReapply", 5, 0, function()
        SetGlobalBool("WSZC_OrganismAuthority", Authority())
        if not Authority() then return end
        InstallVanillaHooks()
        DisableCUPhysiology()
        InstallMedicalBridge()
        WSZC.InstallResetStructureGuard()
    end)

    -- Wrappers are installed unconditionally but every one of them checks
    -- Authority() at call time, so flipping the replicated convar at runtime
    -- switches modes without a map restart.  Do not claim the mode is active
    -- when it is currently off.
    if Authority() then
        local msg = "organism-authoritative mode active (ply.organism owns health; C:U = HUD, minigames, shrapnel)"
        if WSZC.Log then WSZC.Log(msg) else print(TAG .. msg) end
    end
    return true
end

-- In case this file is loaded before the main compatibility layer, keep trying
-- until WSZC.Ready is set (the main layer already uses this retry pattern).
local retries = 0
local function TryInstall()
    -- Keep re-asserting vanilla blood even if InstallOrganismMode() already
    -- succeeded: C:U may create its Config table after our first attempt.
    WSZC.DisableCUBloodReplacement()
    local guardReady = WSZC.InstallShrapnelBandageGuard()
    if WSZC.InstallOrganismMode() and guardReady
        and (not cvCUBlood:GetBool() or WSZC._CUBloodOriginal) then return end
    retries = retries + 1
    if retries < 60 then timer.Simple(0.5, TryInstall) end
end
timer.Simple(0, TryInstall)
hook.Add("InitPostEntity", "WSZC_OrganismInit", function()
    WSZC.InstallOrganismMode()
    WSZC.DisableCUBloodReplacement()
end)
hook.Add("HomigradRun", "WSZC_OrganismInit", function()
    WSZC.InstallOrganismMode()
    WSZC.DisableCUBloodReplacement()
end)
