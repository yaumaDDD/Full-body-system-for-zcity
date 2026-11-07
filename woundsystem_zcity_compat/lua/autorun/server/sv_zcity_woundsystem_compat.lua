-- ZCity <-> Casualties: Unknown compatibility layer (server part)
--
-- The supplied C:U build does not export the API that ZCity's
-- lua/homigrad/woundbridge expects.  This addon adds those exports at runtime,
-- guards C:U's native EntityTakeDamage hook against double processing, maps
-- ZCity bone/hitgroup hits to C:U limbs, routes ZCity medicine through C:U item
-- definitions, and keeps C:U from spawning a second unconscious ragdoll.
--
-- The original ZIP addons are never edited.  Initialization is deferred until
-- both C:U and the ZCity bridge are present.

WSZC = WSZC or {}

if SERVER then
    SetGlobalBool("WSZC_Ready", false)
end

if WSZC._ServerLoaded then return end
WSZC._ServerLoaded = true

AddCSLuaFile("autorun/sh_zcity_woundsystem_compat.lua")
AddCSLuaFile("autorun/client/cl_zcity_woundsystem_compat_minigames.lua")
AddCSLuaFile("autorun/client/cl_zcity_woundsystem_compat_inspect.lua")
AddCSLuaFile("autorun/client/wszc_cl_bandage.lua")
AddCSLuaFile("autorun/client/wszc_cl_syringe.lua")
if not WSZC.PatchIsEnabled then
    include("autorun/sh_zcity_woundsystem_compat.lua")
end

local TAG = "[ZCity/CU compat] "
-- Shared with sv_zcity_woundsystem_compat_organism.lua.  Weak keys because
-- CTakeDamageInfo objects are transient and must not be retained.
WSZC.RawDamage = WSZC.RawDamage or setmetatable({}, { __mode = "k" })
local cvDebug = CreateConVar("zc_woundsystem_compat_debug", "0", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Print diagnostics for the ZCity <-> WoundSystem compatibility addon")

function WSZC.Debug(fmt, ...)
    if not (cvDebug and cvDebug:GetBool()) then return end
    local ok, msg = pcall(string.format, fmt, ...)
    print(TAG .. (ok and msg or tostring(fmt)))
end

function WSZC.Log(msg)
    print(TAG .. tostring(msg))
end

function WSZC.Warn(msg)
    ErrorNoHalt(TAG .. tostring(msg) .. "\n")
end

local function BridgeEnabled()
    local WB = hg and hg.WoundBridge
    if not (WB and WB.IsEnabled) then return false end
    local ok, enabled = pcall(WB.IsEnabled)
    return ok and enabled == true
end

local function Bridged(ply)
    local WB = hg and hg.WoundBridge
    if not (WB and WB.IsBridged) then return false end
    local ok, bridged = pcall(WB.IsBridged, ply)
    return ok and bridged == true
end

WSZC.BridgeEnabled = BridgeEnabled
WSZC.Bridged = Bridged

---------------------------------------------------------------------------
-- Locating C:U locals through debug upvalues (read-only introspection)
---------------------------------------------------------------------------

local function CollectFunctions(root, out, seen, depth)
    if type(root) == "function" then
        out[#out + 1] = root
        return
    end
    if type(root) ~= "table" or seen[root] or depth > 4 then return end
    seen[root] = true
    for _, value in pairs(root) do
        CollectFunctions(value, out, seen, depth + 1)
    end
end

local function RootFunctions()
    local out, seen = {}, {}
    local roots = {
        hook.GetTable(),
        WoundSystem,
        WoundSystem and WoundSystem.Health,
        net and net.Receivers,
    }
    for _, root in ipairs(roots) do
        CollectFunctions(root, out, seen, 0)
    end
    return out
end

local function Upvalue(fn, wanted)
    if type(fn) ~= "function" or not debug then return nil end
    local i = 1
    while true do
        local ok, name, value = pcall(debug.getupvalue, fn, i)
        if not ok or not name then break end
        if name == wanted then return value end
        i = i + 1
    end
    return nil
end

local function FindUpvalue(wanted)
    for _, fn in ipairs(RootFunctions()) do
        local value = Upvalue(fn, wanted)
        if value ~= nil then return value, fn end
    end
    return nil, nil
end

local function ReplaceUpvalue(fn, wanted, newValue)
    if type(fn) ~= "function" or not debug then return false end
    local i = 1
    while true do
        local ok, name = pcall(debug.getupvalue, fn, i)
        if not ok or not name then break end
        if name == wanted then
            local replaced = pcall(debug.setupvalue, fn, i, newValue)
            return replaced
        end
        i = i + 1
    end
    return false
end

---------------------------------------------------------------------------
-- Fallback tables / helpers (used only when an upvalue cannot be found)
---------------------------------------------------------------------------

local FALLBACK_HITGROUP = {
    [HITGROUP_HEAD] = "head",
    [HITGROUP_CHEST] = "thorax",
    [HITGROUP_STOMACH] = "abdomen",
    [HITGROUP_LEFTARM] = "forearm_L",
    [HITGROUP_RIGHTARM] = "forearm_R",
    [HITGROUP_LEFTLEG] = "crus_L",
    [HITGROUP_RIGHTLEG] = "crus_R",
    [HITGROUP_GEAR] = "pelvis",
    [HITGROUP_GENERIC] = "thorax",
}

local FALLBACK_PARENT_LIMB = {
    hand_R = "forearm_R", forearm_R = "arm_R", arm_R = "thorax",
    hand_L = "forearm_L", forearm_L = "arm_L", arm_L = "thorax",
    foot_R = "crus_R", crus_R = "thigh_R", thigh_R = "pelvis",
    foot_L = "crus_L", crus_L = "thigh_L", thigh_L = "pelvis",
    neck = "head", head = "thorax", abdomen = "thorax", pelvis = "abdomen",
}

local FALLBACK_RAGDOLL_BONES = {
    { limb = "neck", patterns = { "neck" } },
    { limb = "head", patterns = { "head", "jaw", "face" } },
    { limb = "hand_L", patterns = { "l_hand", "l hand", "left hand", "bip01_l_finger", "leftfinger" } },
    { limb = "hand_R", patterns = { "r_hand", "r hand", "right hand", "bip01_r_finger", "rightfinger" } },
    { limb = "forearm_L", patterns = { "l_forearm", "l forearm", "left forearm", "l_lowerarm", "left lowerarm" } },
    { limb = "forearm_R", patterns = { "r_forearm", "r forearm", "right forearm", "r_lowerarm", "right lowerarm" } },
    { limb = "arm_L", patterns = { "l_upperarm", "l upperarm", "left upperarm", "l_clavicle", "left clavicle" } },
    { limb = "arm_R", patterns = { "r_upperarm", "r upperarm", "right upperarm", "r_clavicle", "right clavicle" } },
    { limb = "foot_L", patterns = { "l_foot", "l foot", "left foot", "l_toe", "left toe" } },
    { limb = "foot_R", patterns = { "r_foot", "r foot", "right foot", "r_toe", "right toe" } },
    { limb = "crus_L", patterns = { "l_calf", "l calf", "l_shin", "l shin", "left shin", "left calf", "l_lowerleg", "left lowerleg" } },
    { limb = "crus_R", patterns = { "r_calf", "r calf", "r_shin", "r shin", "right shin", "right calf", "r_lowerleg", "right lowerleg" } },
    { limb = "thigh_L", patterns = { "l_thigh", "l thigh", "left thigh", "l_upperleg", "left upperleg" } },
    { limb = "thigh_R", patterns = { "r_thigh", "r thigh", "right thigh", "r_upperleg", "right upperleg" } },
    { limb = "thorax", patterns = { "spine2", "spine3", "spine4", "chest", "rib", "sternum" } },
    { limb = "abdomen", patterns = { "spine1", "stomach", "abdomen" } },
    { limb = "pelvis", patterns = { "pelvis", "spine", "hips", "hip" } },
}

local FALLBACK_LIMB_CLAMPS = {
    skin = { 0, 100 }, muscle = { 0, 100 }, pain = { 0, 100 }, bleed = { 0, 100 },
    infection = { 0, 100 }, infectionAmount = { 0, 100 }, infectionSpeed = { 0, 100 },
    disinfectTime = { 0, 999999 }, bandageSlowAmount = { 0, 100 },
    skinHealAmount = { 0, 100 }, muscleStrength = { 0, 1 },
    boneHealTimer = { 0, 100 }, dislocationTimer = { 0, 100 },
    furBloodAmount = { 0, 100 },
}

local FALLBACK_BODY_CLAMPS = {
    bloodVolume = { -100, 200 }, internalBleeding = { 0, 100 }, hemothorax = { 0, 100 },
    bloodOxygen = { 0, 100 }, bloodPressure = { 0, 250 }, heartRate = { 0, 320 },
    shock = { 0, 100 }, cardioShock = { 0, 100 }, adrenaline = { 0, 100 },
    stamina = { 0, 100 }, brainHealth = { 0, 100 }, consciousness = { 0, 100 },
    temperature = { 0, 100 }, bloodViscosity = { -100, 150 },
    sicknessAmount = { 0, 100 }, septicShock = { 0, 100 },
    opiateAmount = { 0, 1000 }, antagonistAmount = { 0, 1000 },
    opiateTolerance = { 0, 1000 }, strokeAmount = { 0, 100 },
    antibioticImmunityTime = { 0, 999999 },
}

local FALLBACK_DRUG_ALIASES = {
    opiate = "opiateAmount", opiateDose = "opiateAmount", opiateAmount = "opiateAmount",
    opioid = "opiateAmount", opioidDose = "opiateAmount",
    antagonist = "antagonistAmount", antagonistDose = "antagonistAmount", antagonistAmount = "antagonistAmount",
    antidepressant = "antidepressantHappiness", antidepressantMood = "antidepressantHappiness",
    antidepressantHappiness = "antidepressantHappiness", opiateMood = "opiateHappiness",
    opiateHappiness = "opiateHappiness", tolerance = "opiateTolerance",
    opiateTolerance = "opiateTolerance", overdose = "overdoseIndex",
    overdoseRisk = "overdoseIndex", overdoseIndex = "overdoseIndex",
}

local function NormalizeItemId(itemId)
    if WoundSystem and WoundSystem.NormalizeItemId then
        return WoundSystem.NormalizeItemId(itemId)
    end
    return string.upper(tostring(itemId or ""))
end

local function FallbackRagdollBoneNameToLimb(boneName)
    boneName = string.lower(tostring(boneName or ""))
    if boneName == "" then return nil end
    if string.find(boneName, "neck", 1, true) then return "neck" end
    local const = WSZC.Const or {}
    local patterns = const.RagdollDamageBones or FALLBACK_RAGDOLL_BONES
    for _, candidate in ipairs(patterns) do
        for _, pattern in ipairs(candidate.patterns or {}) do
            if string.find(boneName, pattern, 1, true) then
                return candidate.limb
            end
        end
    end
    return nil
end

local function FallbackClearLimbBandage(state)
    if type(state) ~= "table" then return end
    state.isBandaged = false
    state.blockedBleeding = false
    state.bandageSlowAmount = 0
end

local function FallbackResolveLivingLimb(ply, limbId)
    local H = WoundSystem and WoundSystem.Health
    local limbs = H and H.GetLimbs and H.GetLimbs(ply)
    if type(limbs) ~= "table" then return limbId end
    local const = WSZC.Const or {}
    local parents = const.ParentLimb or FALLBACK_PARENT_LIMB
    local current, visited = limbId, {}
    while current and limbs[current] and limbs[current].dismembered do
        if visited[current] then break end
        visited[current] = true
        current = parents[current]
    end
    if current and limbs[current] and not limbs[current].dismembered then return current end
    return "thorax"
end

local function FallbackSendCardioUpdate(ply, force)
    if not IsValid(ply) then return end
    local H = WoundSystem and WoundSystem.Health
    local body = H and H.GetBody and H.GetBody(ply)
    if type(body) ~= "table" then return end
    if ply.SetNWFloat then
        ply:SetNWFloat("BloodAmount", body.bloodVolume or 100)
        ply:SetNWFloat("BrainHealth", body.brainHealth or 100)
        ply:SetNWFloat("Consciousness", body.consciousness or 100)
    end
    if ply.SetNWBool then
        ply:SetNWBool("WoundSystemUnconscious", body.unconscious == true)
    end
end

local function FallbackSendLimbUpdate(ply, limbId, force)
    -- C:U exports this function; the fallback is intentionally a no-op.
end

local function FallbackProcessImpactDamage(ply, limbId, force)
    local H = WoundSystem and WoundSystem.Health
    if not H then return end
    local body = H.GetBody and H.GetBody(ply)
    local limbs = H.GetLimbs and H.GetLimbs(ply)
    local state = type(limbs) == "table" and limbs[limbId]
    if type(body) ~= "table" or type(state) ~= "table" or body.isGodMode then return end
    force = tonumber(force) or 0
    local jump = body.jumpSpeed or 6.5
    if force <= jump then return end

    state.muscle = math.Clamp((state.muscle or 100) - force * 0.33, 0, 100)
    state.pain = math.Clamp((state.pain or 0) + force * 0.4, 0, 100)
    body.adrenaline = math.Clamp((body.adrenaline or 0) + force * 0.075, 0, 100)
    body.shock = math.Clamp((body.shock or 0) + force * 0.05, 0, 100)
    body.cardioShock = math.max(body.cardioShock or 0, body.shock or 0)

    if force > jump * 2.6 then
        state.bleed = math.max(state.bleed or 0, math.Rand(state.bleed or 0, (100 - (state.skin or 100)) * 0.4))
        FallbackClearLimbBandage(state)
    end

    if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end
    if H.SendCardioUpdate then H.SendCardioUpdate(ply, true) end
    hook.Run("WoundSystem_OnImpact", ply, limbId, force)
end

local function FallbackResetPlayer(ply)
    local H = WoundSystem and WoundSystem.Health
    if not (IsValid(ply) and ply:IsPlayer() and H) then return false end

    if type(WoundSystemCloseAllMedicalSessions) == "function" then
        pcall(WoundSystemCloseAllMedicalSessions, ply, "zcity_compat_reset")
    end

    if H.InitPlayer then pcall(H.InitPlayer, ply) end

    local body = H.GetBody and H.GetBody(ply)
    if type(body) == "table" then
        body.unconscious = false
        body.wasUnconscious = false
        body.brainDead = false
        body.fallingRagdoll = nil
        body.fallingRagdollWakeTime = nil
        body.fallingRagdollReason = nil
        body.unconsciousRagdoll = nil
        body.deathRagdollOverride = nil
        body.ragdollModeFailed = false
        body.ragdollWakePos = nil
        body.ragdollWakeAng = nil
    end

    if ply.SetNWEntity then ply:SetNWEntity("WoundSystemUnconsciousRagdoll", NULL) end
    if H.SendCardioUpdate then H.SendCardioUpdate(ply, true) end
    local limbs = H.GetLimbs and H.GetLimbs(ply)
    if type(limbs) == "table" and H.SendLimbUpdate then
        for limbId in pairs(limbs) do H.SendLimbUpdate(ply, limbId, true) end
    end
    return true
end

local function BuildContextFallback(ply, item, itemId, slotIdx, slot, limbId)
    local H = WoundSystem and WoundSystem.Health or {}
    local limb = H.GetLimbState and H.GetLimbState(ply, limbId)
    if not limb and H.GetLimbs then
        local limbs = H.GetLimbs(ply)
        limb = type(limbs) == "table" and limbs[limbId] or nil
    end
    local body = H.GetBody and H.GetBody(ply)
    local limbs = H.GetLimbs and H.GetLimbs(ply)
    local ctx = {
        ply = ply,
        item = item,
        itemId = itemId,
        slotIdx = slotIdx,
        slot = slot,
        limbId = limbId,
        limb = limb,
        body = body,
        limbs = limbs,
        inventory = H.GetInventory and H.GetInventory(ply) or nil,
    }
    ctx.syncLimb = function(force)
        if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, force ~= false) end
    end
    ctx.syncInventory = function()
        if H.SyncInventoryToClient then H.SyncInventoryToClient(ply) end
    end
    ctx.setStatus = function(statusId, value)
        if not (WoundSystem and WoundSystem.Statuses) then return false end
        return WoundSystem.Statuses.Set(limb, statusId, value)
    end
    ctx.clearStatus = function(statusId)
        if not (WoundSystem and WoundSystem.Statuses) then return false end
        return WoundSystem.Statuses.Clear(limb, statusId)
    end
    ctx.hasStatus = function(statusId)
        return WoundSystem and WoundSystem.Statuses and WoundSystem.Statuses.Has(limb, statusId) or false
    end
    return ctx
end

local function ApplyNumericFallback(target, effects, fraction, clamps)
    if type(target) ~= "table" or type(effects) ~= "table" then return end
    fraction = tonumber(fraction) or 1
    clamps = clamps or {}
    for key, amount in pairs(effects) do
        if type(amount) == "number" then
            local nextValue = (tonumber(target[key]) or 0) + amount * fraction
            local clamp = clamps[key]
            if clamp then nextValue = math.Clamp(nextValue, clamp[1], clamp[2]) end
            target[key] = nextValue
        elseif type(amount) == "boolean" then
            target[key] = amount
        end
    end
end

local function ApplyDrugFallback(body, effects, fraction)
    if type(body) ~= "table" or type(effects) ~= "table" then return end
    local const = WSZC.Const or {}
    local aliases = const.DrugEffectAliases or FALLBACK_DRUG_ALIASES
    local clamps = const.BodyEffectClamps or FALLBACK_BODY_CLAMPS
    for key, amount in pairs(effects) do
        local targetKey = aliases[key] or key
        if type(amount) == "number" then
            local nextValue = (tonumber(body[targetKey]) or 0) + amount * (tonumber(fraction) or 1)
            local clamp = clamps[targetKey]
            if clamp then nextValue = math.Clamp(nextValue, clamp[1], clamp[2]) end
            body[targetKey] = nextValue
        elseif type(amount) == "boolean" then
            body[targetKey] = amount
        end
    end
end

local function BandageProfile(itemId, item)
    local Fn = WSZC.Fn
    if Fn and type(Fn.GetBandageProfile) == "function" then
        local ok, profile = pcall(Fn.GetBandageProfile, itemId)
        if ok and type(profile) == "table" then return profile end
    end

    local use = item and item.use or {}
    local bandage = type(use.bandage) == "table" and use.bandage or {}
    local constants = WoundSystem and WoundSystem.Health and WoundSystem.Health.Constants or {}
    local defaultPerWrap = constants.BandageDurabilityPerWrap or (100 / 12)
    local durabilityPerWrap = tonumber(bandage.durabilityPerWrap or use.durabilityPerWrap) or defaultPerWrap
    local effectDivisor = tonumber(bandage.effectDivisor or use.effectDivisor) or 12
    return {
        mode = bandage.mode or use.bandageMode or "gauze",
        durabilityPerWrap = durabilityPerWrap,
        effectDivisor = math.max(effectDivisor, 1),
        requireBleed = false,
        effects = bandage.effects or use.bandageEffects or {},
        bodyEffects = bandage.bodyEffects or use.bandageBodyEffects or {},
        setStatuses = bandage.setStatuses or use.bandageSetStatuses,
        clearStatuses = bandage.clearStatuses or use.bandageClearStatuses,
        bandagedAtBleed = bandage.bandagedAtBleed or use.bandagedAtBleed,
        bandagedAtSlow = bandage.bandagedAtSlow or use.bandagedAtSlow,
        applyWrap = bandage.applyWrap or use.applyWrap,
    }
end

local function SyringeProfile(itemId, item)
    if WSZC.GetSyringeProfile then
        local ok, profile = pcall(WSZC.GetSyringeProfile, itemId)
        if ok and type(profile) == "table" then return profile end
    end

    local use = item and item.use or {}
    local syringe = type(use.syringe) == "table" and use.syringe or {}
    return {
        color = syringe.color or use.syringeColor,
        durabilityPerSecond = tonumber(syringe.durabilityPerSecond or use.syringeDurabilityPerSecond) or 18,
        effects = syringe.effects or use.syringeEffects or {},
        bodyEffects = syringe.bodyEffects or use.syringeBodyEffects or {},
        drugEffects = syringe.drugEffects or use.syringeDrugEffects or {},
        woundStatus = syringe.woundStatus or use.syringeWoundStatus or "SYRINGE_WOUND",
        applyUse = syringe.applyUse or use.applyUse,
    }
end

local function ApplyBandageProfile(ctx, profile, effectFraction)
    local const = WSZC.Const or {}
    local limbClamps = const.LimbEffectClamps or FALLBACK_LIMB_CLAMPS
    local bodyClamps = const.BodyEffectClamps or FALLBACK_BODY_CLAMPS
    local Fn = WSZC.Fn

    if Fn and type(Fn.ApplyNumericEffects) == "function" then
        pcall(Fn.ApplyNumericEffects, ctx.limb, profile.effects, effectFraction, limbClamps)
        pcall(Fn.ApplyNumericEffects, ctx.body, profile.bodyEffects, effectFraction, bodyClamps)
    else
        ApplyNumericFallback(ctx.limb, profile.effects, effectFraction, limbClamps)
        ApplyNumericFallback(ctx.body, profile.bodyEffects, effectFraction, bodyClamps)
    end

    if ctx.limb then
        if ctx.limb.broken and profile.effects and profile.effects.boneHealTimer and (ctx.limb.boneHealTimer or 0) <= 0 then
            ctx.limb.broken = false
            ctx.limb.boneHealTimer = 0
        end
        if ctx.limb.dislocated and profile.effects and profile.effects.dislocationTimer and (ctx.limb.dislocationTimer or 0) <= 0 then
            ctx.limb.dislocated = false
            ctx.limb.dislocationTimer = 0
        end
    end

    if profile.setStatuses and ctx.setStatus then
        for statusId, value in pairs(profile.setStatuses) do ctx.setStatus(statusId, value) end
    end
    if profile.clearStatuses and ctx.clearStatus then
        for statusId in pairs(profile.clearStatuses) do ctx.clearStatus(statusId) end
    end

    if ctx.limb and (profile.bandagedAtSlow or profile.bandagedAtBleed) then
        local slowOk = profile.bandagedAtSlow and (ctx.limb.bandageSlowAmount or 0) >= profile.bandagedAtSlow
        local bleedOk = profile.bandagedAtBleed and (ctx.limb.bleed or 0) <= profile.bandagedAtBleed
        if slowOk or bleedOk then ctx.limb.isBandaged = true end
    end

    if type(profile.applyWrap) == "function" then pcall(profile.applyWrap, ctx) end
    return true
end

local function ApplySyringeProfile(ctx, profile, fraction)
    local const = WSZC.Const or {}
    local limbClamps = const.LimbEffectClamps or FALLBACK_LIMB_CLAMPS
    local bodyClamps = const.BodyEffectClamps or FALLBACK_BODY_CLAMPS
    local Fn = WSZC.Fn

    if Fn and type(Fn.ApplyNumericEffects) == "function" then
        pcall(Fn.ApplyNumericEffects, ctx.limb, profile.effects, fraction, limbClamps)
        pcall(Fn.ApplyNumericEffects, ctx.body, profile.bodyEffects, fraction, bodyClamps)
    else
        ApplyNumericFallback(ctx.limb, profile.effects, fraction, limbClamps)
        ApplyNumericFallback(ctx.body, profile.bodyEffects, fraction, bodyClamps)
    end

    if Fn and type(Fn.ApplyDrugEffects) == "function" then
        pcall(Fn.ApplyDrugEffects, ctx.body, profile.drugEffects, fraction)
    else
        ApplyDrugFallback(ctx.body, profile.drugEffects, fraction)
    end

    if type(profile.applyUse) == "function" then
        local callOk, result = pcall(profile.applyUse, ctx)
        if not callOk or result == false then return false end
    end
    return true
end

local function NormalizeAmount(amount, maxDurability)
    local value = tonumber(amount) or 0
    maxDurability = math.max(tonumber(maxDurability) or 100, 0.0001)
    -- Bridge "apply" items pass 100 for a full ZCity item even when the C:U
    -- item has a different max (e.g. INJECTION = 10).  Smaller values are
    -- already C:U durability units.
    if value > maxDurability + 0.001 then
        value = value / 100 * maxDurability
    end
    return math.Clamp(value, 0, maxDurability)
end

local function ApplyItemToBodyImpl(ply, itemId, limbId, amount, opts)
    local H = WoundSystem and WoundSystem.Health
    local Items = WoundSystem and WoundSystem.Items
    if not (IsValid(ply) and ply:IsPlayer() and ply:Alive() and H and Items) then return false, 0 end

    itemId = NormalizeItemId(itemId)
    -- InstallMedicalBridge resolves the PhysicsBone under the owner's crosshair
    -- before native WB.SwepHeal/BestLimb runs.  Native self-use suppresses its
    -- own AimedLimb, so it may pass the worst-bleeding ARM here instead.  This
    -- scoped override changes only a tourniquet call for the same patient; the
    -- corrected limbId then drives BuildMedicalItemContext, authoritative
    -- artery treatment, C:U status and the native visual marker together.
    local tourniquetRoute = WSZC.TourniquetLimbOverride
    if itemId == "TOURNIQUET" and type(tourniquetRoute) == "table"
        and tourniquetRoute.ply == ply and type(tourniquetRoute.limbId) == "string" then
        limbId = tourniquetRoute.limbId
    end
    local item = Items.Get and Items.Get(itemId)
    if not item then return false, 0 end
    local maxDurability = (Items.GetMax and Items.GetMax(itemId)) or item.max or 100
    local used = NormalizeAmount(amount, maxDurability)
    if used <= 0 then return false, 0 end

    if H.InitPlayer and H.GetLimbs and not H.GetLimbs(ply) then pcall(H.InitPlayer, ply) end
    local slot = Items.CreateSlot and Items.CreateSlot(itemId, used) or {
        type = "tool", toolName = itemId, durability = used,
    }

    local buildCtx = WSZC.BuildMedicalItemContext
    local ctx
    if buildCtx then
        local ok, result = pcall(buildCtx, ply, item, nil, slot, limbId)
        if ok and type(result) == "table" then ctx = result end
    end
    if not ctx then ctx = BuildContextFallback(ply, item, itemId, nil, slot, limbId) end
    if type(ctx.limb) ~= "table" and limbId ~= "body" then return false, 0 end

    local use = item.use or {}
    local minigame = use.minigame
    -- In organism-authority mode C:U's state is only a shadow of ply.organism.
    -- Capture it before the medicine acts, then mirror the produced delta back
    -- into the real ZCity organism (WSZC.ApplyMedicalDelta is a no-op in bridge
    -- mode, where C:U owns health).
    local medicalBefore
    if WSZC.SnapshotMedical then
        local snapOk, snap = pcall(WSZC.SnapshotMedical, ply, limbId)
        if snapOk then medicalBefore = snap end
    end
    local ok = false
    local bandageEffectFraction = 0
    local directTourniquetTreated, directTourniquetAfter = 0, nil

    if minigame == "bandage" then
        local profile = BandageProfile(itemId, item)
        local perWrap = math.max(tonumber(profile.durabilityPerWrap) or (maxDurability / 12), 0.0001)
        local wrapFraction = used / perWrap
        local effectFraction = wrapFraction / math.max(tonumber(profile.effectDivisor) or 1, 1)
        bandageEffectFraction = effectFraction
        ctx.wrapFraction = wrapFraction
        ctx.degreesMoved = wrapFraction * 360
        ctx.profile = profile
        if WSZC.ApplyBandageProfile then
            local callOk, result = pcall(WSZC.ApplyBandageProfile, ctx, profile)
            ok = callOk and result ~= false
        else
            ok = ApplyBandageProfile(ctx, profile, effectFraction)
        end
    elseif minigame == "syringe" then
        local profile = SyringeProfile(itemId, item)
        ctx.syringeFraction = used / math.max(maxDurability, 0.0001)
        ctx.injectDepth = 1
        ctx.durabilityCost = used
        ctx.profile = profile
        if WSZC.ApplySyringeProfile then
            local callOk, result = pcall(WSZC.ApplySyringeProfile, ctx, profile)
            ok = callOk and result ~= false
        else
            ok = ApplySyringeProfile(ctx, profile, ctx.syringeFraction)
        end
    else
        -- Ordinary item: reuse C:U's own use.apply/canUse/validLimbs logic
        -- with a virtual inventory slot.
        if Items.LimbAllowed and not Items.LimbAllowed(use, limbId) then return false, 0 end
        local useItem = WoundSystem.UseMedicalItem

        -- A PHYSICAL ZCity tourniquet must not become a no-op merely because
        -- C:U rejects its shadow state, a status helper is missing, or its
        -- virtual inventory apply errors.  Close the authoritative artery
        -- first; C:U presentation is then best-effort and cannot veto it.
        local authoritativeTourniquet = itemId == "TOURNIQUET"
            and WSZC.ApplyTourniquetToOrganism
            and WSZC.OrganismAuthority and WSZC.OrganismAuthority()
        if authoritativeTourniquet then
            local treatOk, treated, _, afterBleed = pcall(WSZC.ApplyTourniquetToOrganism, ctx)
            if not treatOk then
                if WSZC.Warn then WSZC.Warn("tourniquet organism treatment failed: " .. tostring(treated)) end
            elseif (tonumber(treated) or 0) > 0 then
                directTourniquetTreated = tonumber(treated) or 0
                directTourniquetAfter = afterBleed
                ok = true
                if useItem then pcall(useItem, ply, itemId, limbId, nil, slot)
                elseif type(use.apply) == "function" then pcall(use.apply, ctx) end
                if type(ctx.limb) == "table" then
                    ctx.limb.tourniqueted, ctx.limb.blockedBleeding = true, true
                    if ctx.setStatus then pcall(ctx.setStatus, "TOURNIQUET", 0.01) end
                end
            end
            -- Native success on a shadow limb is not a reason to consume the
            -- physical SWEP item when no real ZCity wound was treated.
            if not ok then return false, 0 end
        end

        if not ok then
            if useItem then
                local callOk, result = pcall(useItem, ply, itemId, limbId, nil, slot)
                ok = callOk and result ~= false
            elseif type(use.apply) == "function" then
                local callOk, result = pcall(use.apply, ctx)
                ok = callOk and result ~= false
            end
        end
    end

    if not ok then return false, 0 end

    if minigame == "bandage" and WSZC.ApplyBandageToOrganism then
        local treatOk, treated, _, afterBleed = pcall(
            WSZC.ApplyBandageToOrganism, ctx, ctx.profile, bandageEffectFraction)
        if not treatOk then
            if WSZC.Warn then WSZC.Warn("bandage organism treatment failed: " .. tostring(treated)) end
        elseif (tonumber(treated) or 0) > 0 and medicalBefore then
            -- ApplyBandageToOrganism already changed the real wounds and the
            -- immediate org.bleed value, and wrote the resulting value into
            -- ctx.limb.bleed.  Zero this ONE snapshot delta so the generic
            -- C:U -> organism mirror cannot subtract the same treatment twice.
            medicalBefore.limbBleed = tonumber(afterBleed) or medicalBefore.limbBleed
        end
    elseif itemId == "TOURNIQUET" and WSZC.ApplyTourniquetToOrganism then
        if directTourniquetTreated > 0 then
            if medicalBefore then
                medicalBefore.limbBleed = tonumber(directTourniquetAfter) or medicalBefore.limbBleed
            end
        else
            local treatOk, treated, _, afterBleed = pcall(WSZC.ApplyTourniquetToOrganism, ctx)
            if not treatOk then
                if WSZC.Warn then WSZC.Warn("tourniquet organism treatment failed: " .. tostring(treated)) end
            elseif (tonumber(treated) or 0) > 0 and medicalBefore then
                -- The real arterial/ordinary wounds and org.bleed were updated by
                -- the tourniquet itself; do not mirror the same bleed delta twice.
                medicalBefore.limbBleed = tonumber(afterBleed) or medicalBefore.limbBleed
            end
        end
    end

    -- When called from inside WB.SwepHeal() the outer wrapper already measured
    -- the whole body delta; applying ours too would double the medicine.
    if medicalBefore and WSZC.ApplyMedicalDelta and (WSZC.SwepHealDepth or 0) == 0 then
        pcall(WSZC.ApplyMedicalDelta, ply, limbId, medicalBefore)
    end
    if H.SendLimbUpdate and limbId ~= "body" then H.SendLimbUpdate(ply, limbId, true) end
    if H.SendCardioUpdate then H.SendCardioUpdate(ply) end
    return true, used
end

---------------------------------------------------------------------------
-- Helpers shared with the external-minigame module
---------------------------------------------------------------------------

WSZC.Upvalue = Upvalue
WSZC.FindUpvalue = FindUpvalue
WSZC.NormalizeItemId = NormalizeItemId
WSZC.BandageProfile = BandageProfile
WSZC.SyringeProfile = SyringeProfile
WSZC.ApplyItemToBodyImpl = ApplyItemToBodyImpl

-- Registers WSZC.InstallMinigameAPI() and the namespaced net protocol.
include("autorun/server/sv_zcity_woundsystem_compat_minigames.lua")
include("autorun/server/sv_zcity_woundsystem_compat_organism.lua")

---------------------------------------------------------------------------
-- One-time setup
---------------------------------------------------------------------------

function WSZC.Setup()
    if WSZC.SetupDone then return true end

    local H = WoundSystem and WoundSystem.Health
    local WB = hg and hg.WoundBridge
    if not (H and WB and WB.IsEnabled and WB.ApplyDamage and WoundSystem.Items) then
        return false
    end

    WSZC.H = H
    if WSZC.InstallNeckState then WSZC.InstallNeckState(H) end

    -- A future C:U build may already provide the full bridge API.  Even then,
    -- install our external-minigame implementation: the supplied C:U build has
    -- none, and the ZCity bridge needs it for non-instant medical items.
    if type(H.HandleDamage) == "function" and type(H.ApplyItemToBody) == "function" then
        if WSZC.InstallMinigameAPI then WSZC.InstallMinigameAPI(H) end
        WSZC.SetupDone = true
        return true
    end

    local hooks = hook.GetTable().EntityTakeDamage or {}
    local CUDamage = hooks.WoundSystem_Damage
    if WSZC.CUDamageHandler and CUDamage == WSZC.DamageWrapper then
        CUDamage = WSZC.CUDamageHandler
    end
    if type(CUDamage) ~= "function" and type(H.HandleDamage) ~= "function" then
        return false
    end

    local refs = {}
    refs.Fn = CUDamage and Upvalue(CUDamage, "Fn") or FindUpvalue("Fn")
    refs.Const = CUDamage and Upvalue(CUDamage, "Const") or FindUpvalue("Const")
    refs.SendCardioUpdate = CUDamage and Upvalue(CUDamage, "SendCardioUpdate") or FindUpvalue("SendCardioUpdate")
    refs.ProcessImpactDamage = CUDamage and Upvalue(CUDamage, "ProcessImpactDamage") or FindUpvalue("ProcessImpactDamage")
    refs.SendLimbUpdate = CUDamage and Upvalue(CUDamage, "SendLimbUpdate") or FindUpvalue("SendLimbUpdate")
    refs.BodyState = CUDamage and Upvalue(CUDamage, "BodyState") or FindUpvalue("BodyState")
    refs.PlayerLimbs = CUDamage and Upvalue(CUDamage, "PlayerLimbs") or FindUpvalue("PlayerLimbs")
    refs.GetBody = CUDamage and Upvalue(CUDamage, "GetBody") or FindUpvalue("GetBody")
    refs.TryCreateUnconsciousRagdoll = (CUDamage and Upvalue(CUDamage, "TryCreateUnconsciousRagdoll"))
        or FindUpvalue("TryCreateUnconsciousRagdoll") or H.TryCreateUnconsciousRagdoll

    local guess = CUDamage and Upvalue(CUDamage, "GuessRagdollDamageLimb") or FindUpvalue("GuessRagdollDamageLimb")
    refs.RagdollBoneNameToLimb = (guess and Upvalue(guess, "RagdollBoneNameToLimb"))
        or FindUpvalue("RagdollBoneNameToLimb")

    refs.BuildMedicalItemContext = Upvalue(WoundSystem.UseMedicalItem, "BuildMedicalItemContext")
        or FindUpvalue("BuildMedicalItemContext")
    refs.ApplyBandageProfile = FindUpvalue("ApplyBandageProfile")
    refs.GetSyringeProfile = FindUpvalue("GetSyringeProfile")
    refs.ApplySyringeProfile = FindUpvalue("ApplySyringeProfile")
    refs.CUSessions = FindUpvalue("Sessions")
    refs.CUCloseBandageSession = FindUpvalue("CloseBandageSession")
    refs.CUCloseSyringeSession = FindUpvalue("CloseSyringeSession")
    refs.CUCloseShrapnelSession = FindUpvalue("CloseShrapnelSession")
    refs.CUCloseDislocationSession = FindUpvalue("CloseDislocationSession")
    refs.CUCloseAedSession = FindUpvalue("CloseAedSession")

    WSZC.H = H
    WSZC.OriginalFn = WSZC.OriginalFn or refs.Fn
    WSZC.OriginalConst = WSZC.OriginalConst or refs.Const
    WSZC.Fn = WSZC.OriginalFn
    WSZC.Const = WSZC.OriginalConst
    WSZC.BuildMedicalItemContext = refs.BuildMedicalItemContext
    WSZC.ApplyBandageProfile = refs.ApplyBandageProfile
    WSZC.GetSyringeProfile = refs.GetSyringeProfile
    WSZC.ApplySyringeProfile = refs.ApplySyringeProfile
    WSZC.CUTryRagdoll = refs.TryCreateUnconsciousRagdoll
    WSZC.CUSessions = refs.CUSessions
    WSZC.CUCloseBandageSession = refs.CUCloseBandageSession
    WSZC.CUCloseSyringeSession = refs.CUCloseSyringeSession
    WSZC.CUCloseShrapnelSession = refs.CUCloseShrapnelSession
    WSZC.CUCloseDislocationSession = refs.CUCloseDislocationSession
    WSZC.CUCloseAedSession = refs.CUCloseAedSession

    WSZC.Debug("refs: Fn=%s Const=%s Bandage=%s Syringe=%s Ctx=%s TryRagdoll=%s Sessions=%s",
        tostring(refs.Fn ~= nil), tostring(refs.Const ~= nil),
        tostring(refs.ApplyBandageProfile ~= nil), tostring(refs.GetSyringeProfile ~= nil),
        tostring(refs.BuildMedicalItemContext ~= nil), tostring(refs.TryCreateUnconsciousRagdoll ~= nil),
        tostring(refs.CUSessions ~= nil))

    -- Expose the state tables the ZCity bridge reads directly.
    H.BodyState = H.BodyState or refs.BodyState or {}
    H.PlayerLimbs = H.PlayerLimbs or refs.PlayerLimbs or {}
    H.GetBody = H.GetBody or refs.GetBody or function(ply) return H.BodyState[ply] end
    H.GetLimbs = H.GetLimbs or function(ply) return H.PlayerLimbs[ply] end
    H.GetLimbState = H.GetLimbState or function(ply, limbId)
        local limbs = H.GetLimbs(ply)
        return type(limbs) == "table" and limbs[limbId] or nil
    end
    H.SendLimbUpdate = H.SendLimbUpdate or refs.SendLimbUpdate or FallbackSendLimbUpdate
    H.SendCardioUpdate = H.SendCardioUpdate or refs.SendCardioUpdate or FallbackSendCardioUpdate
    H.ProcessImpactDamage = H.ProcessImpactDamage or refs.ProcessImpactDamage or FallbackProcessImpactDamage
    H.RagdollBoneNameToLimb = H.RagdollBoneNameToLimb or refs.RagdollBoneNameToLimb or FallbackRagdollBoneNameToLimb
    H.ResetPlayer = H.ResetPlayer or FallbackResetPlayer
    H.ApplyItemToBody = H.ApplyItemToBody or ApplyItemToBodyImpl
    H.LimbForce = H.LimbForce or {}
    H.CAS3BodyFeel = H.CAS3BodyFeel or {}
    H.SetLimbDislocated = H.SetLimbDislocated or function(ply, limbId, dislocated, timerValue, forceSync)
        local state = H.GetLimbState(ply, limbId)
        if type(state) ~= "table" then return false end
        state.dislocated = dislocated == true
        state.dislocationTimer = math.Clamp(tonumber(timerValue) or 100, 0, 100)
        if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end
        return true
    end

    local fnTable = WSZC.Fn or {}
    H.Fn = fnTable
    H.Fn.ClearLimbBandage = H.Fn.ClearLimbBandage or FallbackClearLimbBandage
    H.Fn.ResolveLivingLimb = H.Fn.ResolveLivingLimb or FallbackResolveLivingLimb

    local constTable = WSZC.Const or {}
    H.Const = constTable
    H.Const.HitgroupToLimb = H.Const.HitgroupToLimb or FALLBACK_HITGROUP
    H.Const.ParentLimb = H.Const.ParentLimb or FALLBACK_PARENT_LIMB
    H.Const.RagdollDamageBones = H.Const.RagdollDamageBones or FALLBACK_RAGDOLL_BONES
    H.Const.LimbEffectClamps = H.Const.LimbEffectClamps or FALLBACK_LIMB_CLAMPS
    H.Const.BodyEffectClamps = H.Const.BodyEffectClamps or FALLBACK_BODY_CLAMPS
    H.Const.DrugEffectAliases = H.Const.DrugEffectAliases or FALLBACK_DRUG_ALIASES
    if WSZC.InstallNeckState then WSZC.InstallNeckState(H) end

    -- External-minigame API for ZCity's non-instant medical SWEPs.  The
    -- implementation lives in sv_zcity_woundsystem_compat_minigames.lua and
    -- uses namespaced copies of C:U's bandage/syringe client minigames.
    if WSZC.InstallMinigameAPI then WSZC.InstallMinigameAPI(H) end

    -- Export HandleDamage and wrap the native C:U damage hook.
    if CUDamage then
        WSZC.CUDamageHandler = CUDamage

        -- Force the hook to use the limb ZCity already resolved from the bone /
        -- hitgroup instead of ply:LastHitGroup().
        if not WSZC.DamageProxiesApplied or WSZC.ProxiedCUDamage ~= CUDamage then
            local limbProxy = setmetatable({}, {
                __index = function(_, hitgroup)
                    local victim = WSZC.CurrentVictim
                    if IsValid(victim) and victim._WoundBridgeLimb then
                        return victim._WoundBridgeLimb
                    end
                    return (WSZC.OriginalConst and WSZC.OriginalConst.HitgroupToLimb or FALLBACK_HITGROUP)[hitgroup]
                end,
            })
            local constProxy = setmetatable({}, {
                __index = function(_, key)
                    if key == "HitgroupToLimb" then return limbProxy end
                    return WSZC.OriginalConst and WSZC.OriginalConst[key]
                end,
            })
            local fnProxy = setmetatable({}, {
                __index = function(_, key)
                    if key == "PickRandomDamageLimb" then
                        return function(ply)
                            if IsValid(ply) and ply._WoundBridgeLimb then return ply._WoundBridgeLimb end
                            if WSZC.OriginalFn and WSZC.OriginalFn.PickRandomDamageLimb then
                                return WSZC.OriginalFn.PickRandomDamageLimb(ply)
                            end
                            return "thorax"
                        end
                    end
                    return WSZC.OriginalFn and WSZC.OriginalFn[key]
                end,
            })
            ReplaceUpvalue(CUDamage, "Const", constProxy)
            ReplaceUpvalue(CUDamage, "Fn", fnProxy)
            WSZC.ProxiedCUDamage = CUDamage
            WSZC.DamageProxiesApplied = true
        end

        local function DefaultHandleDamage(target, dmginfo)
            return CUDamage(target, dmginfo)
        end

        if not WSZC.HandleDamageWrapped or WSZC.WrappedCUDamage ~= CUDamage
            or H.HandleDamage ~= WSZC.HandleDamageWrapper then
            local base = H.HandleDamage
            if WSZC.OriginalHandleDamage and base == WSZC.HandleDamageWrapper then
                base = WSZC.OriginalHandleDamage
            end
            WSZC.OriginalHandleDamage = base or DefaultHandleDamage
            H.HandleDamage = function(target, dmginfo)
                if IsValid(target) and H.InitPlayer and H.GetLimbs and not H.GetLimbs(target) then
                    pcall(H.InitPlayer, target)
                end
                local previous = WSZC.CurrentVictim
                WSZC.CurrentVictim = target
                local ok, a, b, c = pcall(WSZC.OriginalHandleDamage, target, dmginfo)
                WSZC.CurrentVictim = previous
                if not ok then
                    WSZC.Warn("WoundSystem.Health.HandleDamage failed: " .. tostring(a))
                    return false
                end
                return a, b, c
            end
            WSZC.HandleDamageWrapper = H.HandleDamage
            WSZC.WrappedCUDamage = CUDamage
            WSZC.HandleDamageWrapped = true
        end

        local function DamageWrapper(ent, dmginfo)
            -- In organism-authority mode C:U must NOT simulate this hit at all:
            -- its handler ends with dmginfo:SetDamage(0), which would erase the
            -- ZCity hit.  WSZC_AuthorityDamagePost (PostEntityTakeDamage) records
            -- the shrapnel instead, using the unscaled damage saved below.
            if WSZC.OrganismAuthority() then
                -- Only fill the raw-damage cache if our homigrad-damage wrapper
                -- has not done it yet (hook order is not guaranteed, and that
                -- wrapper sees the value before ZCity's ScaleDamage(0.15)).
                if WSZC.RawDamage[dmginfo] == nil and IsValid(ent) and ent:IsPlayer()
                    and dmginfo and dmginfo.GetDamage then
                    local okRaw, raw = pcall(dmginfo.GetDamage, dmginfo)
                    if okRaw then WSZC.RawDamage[dmginfo] = raw end
                end
                return
            end
            if WSZC.Ready and BridgeEnabled() and IsValid(ent) and ent:IsPlayer() and Bridged(ent) then
                return -- ZCity already forwarded this hit through WB.ApplyDamage
            end
            return CUDamage(ent, dmginfo)
        end
        WSZC.DamageWrapper = DamageWrapper
        hook.Add("EntityTakeDamage", "WoundSystem_Damage", DamageWrapper)

        timer.Create("WSZC_ReapplyDamageHook", 5, 0, function()
            local current = (hook.GetTable().EntityTakeDamage or {}).WoundSystem_Damage
            if current ~= WSZC.DamageWrapper then
                hook.Add("EntityTakeDamage", "WoundSystem_Damage", WSZC.DamageWrapper)
            end
        end)
    elseif not H.HandleDamage then
        return false
    end

    -- Prevent C:U from deleting the ZCity fake ragdoll during wake/restore.
    if H.BridgeRagdollForPlayerRestore and (not WSZC.BridgeRagdollWrapped
        or H.BridgeRagdollForPlayerRestore ~= WSZC.BridgeRagdollWrapper) then
        local base = H.BridgeRagdollForPlayerRestore
        if WSZC.OriginalBridgeRagdoll and base == WSZC.BridgeRagdollWrapper then
            base = WSZC.OriginalBridgeRagdoll
        end
        WSZC.OriginalBridgeRagdoll = base
        H.BridgeRagdollForPlayerRestore = function(ply, ragdoll)
            if WSZC.Ready and BridgeEnabled() and IsValid(ply) and IsValid(ragdoll) and ragdoll == ply.FakeRagdoll then
                return
            end
            return WSZC.OriginalBridgeRagdoll(ply, ragdoll)
        end
        WSZC.BridgeRagdollWrapper = H.BridgeRagdollForPlayerRestore
        WSZC.BridgeRagdollWrapped = true
    end

    -- External callers of the exported ragdoll creator should use ZCity's fake.
    if H.TryCreateUnconsciousRagdoll and (not WSZC.TryRagdollWrapped
        or H.TryCreateUnconsciousRagdoll ~= WSZC.TryRagdollWrapper) then
        local base = H.TryCreateUnconsciousRagdoll
        if WSZC.OriginalTryRagdoll and base == WSZC.TryRagdollWrapper then
            base = WSZC.OriginalTryRagdoll
        end
        WSZC.OriginalTryRagdoll = base
        H.TryCreateUnconsciousRagdoll = function(ply, body)
            if WSZC.Ready and BridgeEnabled() and Bridged(ply) then
                body = type(body) == "table" and body or (H.GetBody and H.GetBody(ply))
                if type(body) ~= "table" then return false end
                if IsValid(body.unconsciousRagdoll) then return true end
                if WB.CreateRagdoll and WB.CreateRagdoll(ply, body) and IsValid(ply.FakeRagdoll) then
                    body.unconsciousRagdoll = ply.FakeRagdoll
                    body.ragdollModeFailed = false
                    return true
                end
                return false
            end
            return WSZC.OriginalTryRagdoll(ply, body)
        end
        WSZC.TryRagdollWrapper = H.TryCreateUnconsciousRagdoll
        WSZC.TryRagdollWrapped = true
    end

    -- Internal C:U calls use the local function, not the exported one.  Catch
    -- its ents.Create("prop_ragdoll") and create the ZCity fake instead.
    if debug and ents and ents.Create and type(WSZC.CUTryRagdoll) == "function" then
        if not WSZC.OriginalEntsCreate then WSZC.OriginalEntsCreate = ents.Create end
        local baseCreate = WSZC.OriginalEntsCreate

        local function RagdollCallInfo()
            local info = debug.getinfo(3, "f")
            local name, ply = debug.getlocal(3, 1)
            local bodyName, body = debug.getlocal(3, 2)
            return info, name, ply, bodyName, body
        end

        local function EntsCreateWrapper(class, ...)
            if WSZC.Ready and BridgeEnabled() and class == "prop_ragdoll" then
                local info, name, ply, bodyName, body = RagdollCallInfo()
                if info and info.func == WSZC.CUTryRagdoll and name == "ply" and IsValid(ply) and ply:IsPlayer() and Bridged(ply) then
                    if bodyName ~= "body" or type(body) ~= "table" then
                        body = H.GetBody and H.GetBody(ply)
                    end
                    if type(body) == "table" and WB.CreateRagdoll then
                        pcall(WB.CreateRagdoll, ply, body)
                        if IsValid(ply.FakeRagdoll) then
                            body.unconsciousRagdoll = ply.FakeRagdoll
                            body.ragdollModeFailed = false
                            timer.Simple(0, function()
                                if not IsValid(ply) or type(body) ~= "table" then return end
                                if IsValid(ply.FakeRagdoll) then
                                    body.unconsciousRagdoll = ply.FakeRagdoll
                                    body.ragdollModeFailed = false
                                end
                                ply:SetNWEntity("WoundSystemUnconsciousRagdoll", NULL)
                            end)
                        end
                    end
                    return NULL
                end
            end
            return baseCreate(class, ...)
        end

        if ents.Create ~= WSZC.EntsCreateWrapper then
            ents.Create = EntsCreateWrapper
            WSZC.EntsCreateWrapper = EntsCreateWrapper
        end
    else
        WSZC.Warn("Could not intercept C:U unconscious ragdoll creation; duplicate ragdolls may appear")
    end

    -- Keep C:U's body.unconsciousRagdoll pointing at the ZCity fake, but do NOT
    -- set the NW entity: that keeps C:U's ragdoll damage proxy disabled.
    hook.Add("Fake", "WSZC_RagdollMirror", function(ply, ragdoll)
        if not (WSZC.Ready and BridgeEnabled() and IsValid(ply) and ply:IsPlayer() and IsValid(ragdoll)) then return end
        local body = H.GetBody and H.GetBody(ply)
        if type(body) ~= "table" then return end
        if body.unconscious or body.fallingRagdoll then
            body.unconsciousRagdoll = ragdoll
            body.ragdollModeFailed = false
        end
    end)

    hook.Add("HG_OnWakeOtrub", "WSZC_Wake", function(ply)
        if not (WSZC.Ready and BridgeEnabled() and IsValid(ply) and ply:IsPlayer()) then return end
        local body = H.GetBody and H.GetBody(ply)
        if type(body) == "table" then
            if H.RestorePlayerFromUnconsciousRagdoll then
                pcall(H.RestorePlayerFromUnconsciousRagdoll, ply, body, true, true)
            end
            body.unconscious = false
            body.fallingRagdoll = nil
            body.fallingRagdollWakeTime = nil
            body.fallingRagdollReason = nil
            body.unconsciousRagdoll = nil
            body.ragdollModeFailed = false
        end
        if ply.SetNWEntity then ply:SetNWEntity("WoundSystemUnconsciousRagdoll", NULL) end
        local org = ply.organism
        if type(org) == "table" then
            org.fake = false
            org.needfake = false
        end
        if WB.RestoreRagdoll then pcall(WB.RestoreRagdoll, ply, body, false) end
    end)

    local function ClearRagdollState(ply)
        if not IsValid(ply) then return end
        local body = H.GetBody and H.GetBody(ply)
        if type(body) == "table" then
            body.unconsciousRagdoll = nil
            body.ragdollModeFailed = false
            body.fallingRagdoll = nil
        end
        if ply.SetNWEntity then ply:SetNWEntity("WoundSystemUnconsciousRagdoll", NULL) end
    end
    hook.Add("PlayerSpawn", "WSZC_SpawnClear", ClearRagdollState)
    hook.Add("PlayerDeath", "WSZC_DeathClear", ClearRagdollState)

    WSZC.SetupDone = true
    return true
end

---------------------------------------------------------------------------
-- Deferred initialization
---------------------------------------------------------------------------

local attempts = 0
local function Attempt()
    if WSZC.Ready then return true end
    local ok, ready = pcall(WSZC.Setup)
    if not ok then
        WSZC.Warn("setup error: " .. tostring(ready))
        SetGlobalBool("WSZC_Ready", false)
        return false
    end
    if not ready then return false end

    WSZC.Ready = true
    SetGlobalBool("WSZC_Ready", true)
    SetGlobalBool("WSZC_OrganismAuthority", WSZC.OrganismAuthority())
    if WSZC.PatchIsEnabled then WSZC.PatchIsEnabled() end
    if WSZC.PatchIsBridged then WSZC.PatchIsBridged() end
    if WSZC.InstallOrganismMode then WSZC.InstallOrganismMode() end

    if WSZC.OrganismAuthority() then
        WSZC.Log("compatibility layer active (ply.organism owns health; C:U = HUD, minigames, shrapnel)")
    else
        WSZC.Log("compatibility layer active (C:U owns wounds, ZCity owns hits)")
    end
    return true
end

WSZC.Attempt = Attempt

local function Chain()
    if WSZC.Ready then return end
    if Attempt() then return end
    attempts = attempts + 1
    if attempts < 60 then timer.Simple(0.5, Chain) end
end

if not WSZC._ChainStarted then
    WSZC._ChainStarted = true
    timer.Simple(0, Chain)
end

hook.Add("InitPostEntity", "WSZC_ServerInit", Attempt)
hook.Add("HomigradRun", "WSZC_ServerInit", Attempt)
