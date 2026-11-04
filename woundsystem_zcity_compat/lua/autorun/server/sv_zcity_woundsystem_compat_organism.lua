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
local cvShadow = CreateConVar("zc_woundsystem_compat_shadow", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Mirror ZCity injuries into the C:U injury HUD (BodyState / PlayerLimbs)", 0, 1)
local cvLimbBleed = CreateConVar("zc_woundsystem_compat_limb_bleed", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Use ZCity's per-bone wounds for limb bleeding instead of painting all 15 C:U limbs", 0, 1)
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
local cvDebug = CreateConVar("zc_woundsystem_compat_organism_debug", "0",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Print organism-authority diagnostics", 0, 1)

local TAG = "[ZCity/CU compat] "

local function Debug(fmt, ...)
    if not (cvDebug and cvDebug:GetBool()) then return end
    local ok, msg = pcall(string.format, fmt, ...)
    print(TAG .. (ok and msg or tostring(fmt)))
end

local function Warn(msg)
    if WSZC.Warn then WSZC.Warn(msg) else ErrorNoHalt(TAG .. tostring(msg) .. "\n") end
end

local function Authority()
    if WSZC.OrganismAuthority then return WSZC.OrganismAuthority() end
    local cv = GetConVar and GetConVar("zc_woundsystem_compat_authority")
    return not cv or cv:GetBool() ~= false
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
    head      = { dmg = "skull",  amp = "headamputated", dis = nil },
    thorax    = { dmg = "chest",  amp = nil,              dis = nil },
    abdomen   = { dmg = "pelvis", amp = nil,              dis = nil },
    arm_L     = { dmg = "larm", amp = "larmamputated", dis = "larmdislocation" },
    forearm_L = { dmg = "larm", amp = "larmamputated", dis = "larmdislocation" },
    hand_L    = { dmg = "larm", amp = "larmamputated", dis = "larmdislocation" },
    arm_R     = { dmg = "rarm", amp = "rarmamputated", dis = "rarmdislocation" },
    forearm_R = { dmg = "rarm", amp = "rarmamputated", dis = "rarmdislocation" },
    hand_R    = { dmg = "rarm", amp = "rarmamputated", dis = "rarmdislocation" },
    thigh_L   = { dmg = "lleg", amp = "llegamputated", dis = "llegdislocation" },
    crus_L    = { dmg = "lleg", amp = "llegamputated", dis = "llegdislocation" },
    foot_L    = { dmg = "lleg", amp = "llegamputated", dis = "llegdislocation" },
    thigh_R   = { dmg = "rleg", amp = "rlegamputated", dis = "rlegdislocation" },
    crus_R    = { dmg = "rleg", amp = "rlegamputated", dis = "rlegdislocation" },
    foot_R    = { dmg = "rleg", amp = "rlegamputated", dis = "rlegdislocation" },
}

-- Built defensively: GMod defines these, but a headless test runtime may not.
local HITGROUP_LIMB = {}
local function AddHitgroup(id, limbId)
    if id ~= nil then HITGROUP_LIMB[id] = limbId end
end
AddHitgroup(HITGROUP_HEAD, "head")
AddHitgroup(HITGROUP_CHEST, "thorax")
AddHitgroup(HITGROUP_STOMACH, "abdomen")
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
    if string.find(lower, "forearm") or string.find(lower, "upperarm") then return "forearm" .. side end
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
    head = "head", skull = "head", neck = "head",
    chest = "thorax", thorax = "thorax", spine2 = "thorax", spine3 = "thorax",
    spine4 = "thorax", rib = "thorax", sternum = "thorax",
    stomach = "abdomen", abdomen = "abdomen", pelvis = "abdomen",
    spine = "abdomen", spine1 = "abdomen", hips = "abdomen", hip = "abdomen",
    larm = "forearm_L", rarm = "forearm_R",
    lleg = "thigh_L", rleg = "thigh_R",
}

local ARTERY_LIMB = {
    larmartery = "forearm_L", rarmartery = "forearm_R",
    llegartery = "thigh_L", rlegartery = "thigh_R",
    spineartery = "abdomen", neckartery = "head", headartery = "head",
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
    if string.find(lower, "pelvis") or string.find(lower, "spine")
        or string.find(lower, "hip") then return "abdomen" end
    return NormalizeLimb(lower)
end

--- Build { limbId = bleeding 0..100 } from the actual ZCity wound tables.
local function LimbBleedMap(ply, org)
    local map = {}
    local function add(limbId, amount)
        limbId = NormalizeLimb(limbId)
        if not limbId or amount <= 0 then return end
        map[limbId] = (map[limbId] or 0) + amount
    end

    for _, w in ipairs(org.wounds or {}) do
        if type(w) == "table" then
            local severity = math.max(tonumber(w[1]) or 0, 0)
            add(LimbFromBoneName(BoneNameOf(ply, w[4])), severity * 2.0)
        end
    end
    for _, w in ipairs(org.arterialwounds or {}) do
        if type(w) == "table" then
            local severity = math.max(tonumber(w[1]) or 0, 0)
            local artery = type(w[7]) == "string" and string.lower(w[7]) or nil
            local limb = (artery and (ARTERY_LIMB[artery] or NormalizeLimb((string.gsub(artery, "artery", "")))))
                or LimbFromBoneName(BoneNameOf(ply, w[4]))
            add(limb, severity * 3.0)
        end
    end
    return map
end
WSZC.LimbBleedMap = LimbBleedMap -- exported for diagnostics / headless tests

---------------------------------------------------------------------------
-- Shrapnel minigame complications (pain + growing bleeding)
---------------------------------------------------------------------------
-- C:U's BreakShrapnelGrasp() adds state.bleed (+0.4..1.0) and state.pain
-- (+9..16) when the player yanks / re-impales a fragment.  Our PushShadow
-- used to overwrite those values from ply.organism every 250 ms, so nothing
-- ever bled.  Detect the unexpected jump and mirror it into the ZCity
-- organism: a real wound on that limb plus a rising irritation counter.
local COMPLICATION_BONES = {
    head = "ValveBiped.Bip01_Head1", thorax = "ValveBiped.Bip01_Spine2",
    abdomen = "ValveBiped.Bip01_Spine1",
    arm_L = "ValveBiped.Bip01_L_UpperArm", forearm_L = "ValveBiped.Bip01_L_Forearm",
    hand_L = "ValveBiped.Bip01_L_Hand",
    arm_R = "ValveBiped.Bip01_R_UpperArm", forearm_R = "ValveBiped.Bip01_R_Forearm",
    hand_R = "ValveBiped.Bip01_R_Hand",
    thigh_L = "ValveBiped.Bip01_L_Thigh", crus_L = "ValveBiped.Bip01_L_Calf",
    foot_L = "ValveBiped.Bip01_L_Foot",
    thigh_R = "ValveBiped.Bip01_R_Thigh", crus_R = "ValveBiped.Bip01_R_Calf",
    foot_R = "ValveBiped.Bip01_R_Foot",
}

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
    org.wounds[last + 1] = {
        math.Clamp(irritation * 1.2, 4, 24), nil, nil, bone, now,
    }
    Debug("shrapnel complication on %s: bleed +%.2f pain +%.1f", tostring(limbId), bleedDelta, painDelta)
    return true
end

-- Resolve the player who owns a damaged player or fake ragdoll.
local function OwnerOf(ent)
    if not IsValid(ent) then return nil end
    if ent:IsPlayer() then return ent end
    local ragdollOwner = hg and hg.RagdollOwner
    if ragdollOwner then
        local ok, ply = pcall(ragdollOwner, ent)
        if ok and IsValid(ply) and ply:IsPlayer() and ply:Alive() then return ply end
    end
    -- FakeRagdoll also stores the owner as an NW entity; some ZCity ragdolls
    -- (collision proxies, death ragdolls) have no `ragdoll.ply` Lua field.
    if ent.GetNWEntity then
        local ok, ply = pcall(ent.GetNWEntity, ent, "ply")
        if ok and IsValid(ply) and ply:IsPlayer() and ply:Alive() then return ply end
    end
    return nil
end

---------------------------------------------------------------------------
-- The ONE shrapnel state
---------------------------------------------------------------------------

-- `state.shrapnel` is the single source of truth for the C:U panel and the
-- C:U shrapnel minigame.  `org.wszc_shrapnel` is a shadow copy so ZCity code
-- and the regeneration blocker can read it.  Neither table has a `source`.
local DEFAULT_MAX_PIECES = 5

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

--- Add lodged fragments.  `reason` is used for the debug log ONLY and is never
--- stored: glass, gunshot and blast shrapnel are indistinguishable afterwards.
function WSZC.AddShrapnel(ply, limbId, count, reason)
    if not Authority() then return false end
    if not (cvShrapnel and cvShrapnel:GetBool()) then return false end
    if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return false end
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return false end

    local h = H()
    if h and h.InitPlayer and h.GetLimbs and not h.GetLimbs(ply) then pcall(h.InitPlayer, ply) end

    limbId = limbId or "thorax"
    local state = ShrapnelState(ply, limbId)
    if not state then
        -- Unknown limb id: fall back to something the C:U panel can draw.
        state = ShrapnelState(ply, "thorax")
        if not state then return false end
        limbId = "thorax"
    end

    local before = math.floor(tonumber(state.shrapnel) or 0)
    local after = math.Clamp(before + count, 0, MaxShrapnel())
    if after == before then return false end

    state.shrapnel = after

    local org = ply.organism
    if type(org) == "table" then
        org.wszc_shrapnel = org.wszc_shrapnel or {}
        org.wszc_shrapnel[limbId] = after
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
        WSZC.RestoreShrapnel(ply)
        -- RestoreShrapnel() returns early when there are no fragments, so it
        -- cannot be the only place that records the table identity.  Without
        -- this, a player with a dislocation but no shrapnel would look like a
        -- "fresh ragdoll" on EVERY tick and the reduction would be undone.
        ply._WSZCLimbsRef = limbs
    end

    for limbId, state in pairs(limbs) do
        if type(state) == "table" then
            local n = math.floor(tonumber(state.shrapnel) or 0)
            if (tonumber(org.wszc_shrapnel[limbId]) or 0) ~= n then
                org.wszc_shrapnel[limbId] = n
                if n <= 0 then org.wszc_shrapnel_floor[limbId] = nil end
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
-- WB.Sync()'s AnyDislocated() did.  A successful reduction on any of them
-- clears the whole ZCity group.

local DISLOC_FLAGS = {
    larmdislocation = { "arm_L", "forearm_L", "hand_L" },
    rarmdislocation = { "arm_R", "forearm_R", "hand_R" },
    llegdislocation = { "thigh_L", "crus_L", "foot_L" },
    rlegdislocation = { "thigh_R", "crus_R", "foot_R" },
}

-- ZCity writes a full break as org[key] = 1.  Regeneration (sv_pain.lua) and
-- ZCity medical SWEPs then bring it back down; 0.85 keeps the fracture icon
-- visible while the bone is still essentially broken.
local FRACTURE_DAMAGE = 0.85

local function Fractured(org, limbId, map)
    if limbId == "thorax" and (tonumber(org.brokenribs) or 0) > 0 then return true end
    return (tonumber(org[map and map.dmg]) or 0) >= FRACTURE_DAMAGE
end
WSZC.Fractured = Fractured -- exported for headless tests

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
    local limbs = h and h.GetLimbs and h.GetLimbs(ply)
    if type(limbs) ~= "table" then return false end

    ply._WSZCExpectedDislocation = ply._WSZCExpectedDislocation or {}
    for limbId, map in pairs(LIMB_ORG) do
        if map.dmg then
            local state = limbs[limbId]
            if type(state) ~= "table" and h.GetLimbState then
                local ok, created = pcall(h.GetLimbState, ply, limbId)
                if ok then state = created end
            end
            if type(state) == "table" then
                local out = map.dis and org[map.dis] == true or false
                state.dislocated = out
                state.dislocationTimer = out and 100 or 0
                state.broken = Fractured(org, limbId, map)
                state.boneHealTimer = math.Clamp((1 -
                    (tonumber(org[map.dmg]) or 0)) * 100, 0, 100)
                ply._WSZCExpectedDislocation[limbId] = out
                if h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, limbId, true) end
            end
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

-- ZCity's `hg.Fake` / `hg.FakeUp` fire when the character drops into / gets
-- up from the unconscious ragdoll.  Re-assert the fragments immediately and
-- once more after every ragdoll hook has run (C:U may reset limbs there).
local function RestoreShrapnelSoon(ply)
    if not (Authority() and IsValid(ply) and ply.IsPlayer and ply:IsPlayer()) then return end
    timer.Simple(0, function()
        WSZC.RestoreShrapnel(ply)
        WSZC.RestoreBones(ply)
    end)
    timer.Simple(0.3, function()
        WSZC.RestoreShrapnel(ply)
        WSZC.RestoreBones(ply)
    end)
end
hook.Add("Fake", "WSZC_ShrapnelRagdollKeep", function(ply) RestoreShrapnelSoon(ply) end)
hook.Add("FakeUp", "WSZC_ShrapnelRagdollKeep", function(ply) RestoreShrapnelSoon(ply) end)
hook.Add("HG_OnWakeOtrub", "WSZC_ShrapnelRagdollKeep", function(ply) RestoreShrapnelSoon(ply) end)

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
    weapon_doublebarrel_short = true,
}

local function IsShotgunEntity(ent)
    if not IsValid(ent) then return false end
    local ok, class = pcall(ent.GetClass, ent)
    if ok and SHOTGUN_WEAPONS[class] then return true end
    -- NumBullet > 1 is the pellet count on every ZCity shotgun SWEP; pistols
    -- and rifles always have 1.
    return (tonumber(ent.NumBullet) or 0) > 1
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

    local buckshot = DMG_BUCKSHOT or 0
    if buckshot ~= 0 and bit.band(dmgtype, buckshot) ~= 0 then return true end

    if dmginfo.GetAmmoType and game and game.GetAmmoName then
        local ok, ammoId = pcall(dmginfo.GetAmmoType, dmginfo)
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
    WSZC.ShrapnelHandled[dmginfo] = true

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
    local added = 0

    -- One fragment per SHOTGUN hit only (HEV blocks it), capped at
    -- ShrapnelPieceCount.  Pistols / rifles / SMGs deliberately produce none.
    local blast = DMG_BLAST or 0
    if IsShotgunHit(dmginfo, dmgtype) and not HevBlocks(ply) then
        added = added + 1
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
            added = added + frags
        end
    end

    if added > 0 then WSZC.AddShrapnel(ply, limbId, added, "damage") end
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
    if not (Authority() and cvGlass and cvGlass:GetBool()) then return end
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
    if not (Authority() and IsValid(ent) and dmginfo) then return end
    local raw = WSZC.RawDamage[dmginfo]
    if took == false and not (cvOnBlocked and cvOnBlocked:GetBool()) then
        WSZC.RawDamage[dmginfo] = nil
        return
    end
    WSZC.InjectDamageShrapnel(ent, dmginfo, nil, raw)
    WSZC.RawDamage[dmginfo] = nil
end)

hook.Add("PostEntityTakeDamage", "WSZC_GlassStrike", function(ent, dmginfo)
    if not (Authority() and cvGlass and cvGlass:GetBool()) then return end
    if not (IsValid(ent) and dmginfo) then return end
    -- A player hit (already handled above) is never a glass brush entity.
    if ent.organism then return end

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
    if not isGlass then return end

    -- The inflictor is the hand/foot entity that hit the brush; ZCity gives it
    -- an organism table.  Fall back to the attacker for weapon-based punches.
    local inflictor = dmginfo.GetInflictor and dmginfo:GetInflictor() or nil
    local attacker = dmginfo.GetAttacker and dmginfo:GetAttacker() or nil
    local striker = (IsValid(inflictor) and inflictor.organism and inflictor)
        or (IsValid(attacker) and attacker.organism and attacker) or nil
    if not striker then return end

    local ply = OwnerOf(striker)
    if not ply then return end

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

    InjectGlass(ply, limbId, 0)
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

    local now = CurTime and CurTime() or 0
    if (ply._WSZCShadowNext or 0) > now then return end
    ply._WSZCShadowNext = now + 0.25 -- 4 Hz is plenty for a HUD

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
    local avgPain = math.max(tonumber(org.pain) or 0, 0)
    if WSZC.DislocationActive(ply) then avgPain = math.min(avgPain, 60) end
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
            -- `shrapnel`, `isBandaged`, `hasInjection` and customStatuses are
            -- owned by the C:U minigames: never overwrite them here.
            local limbBleed
            if woundMap then
                local fromWounds = woundMap[limbId] or 0
                local dmg = math.Clamp(tonumber(map and org[map.dmg]) or 0, 0, 1)
                if fromWounds > 0 then
                    limbBleed = math.Clamp(fromWounds, 0, 100)
                elseif dmg > 0.001 then
                    -- Only limbs the organism actually damaged bleed.  Internal
                    -- bleeding stays in body.internalBleeding and never paints
                    -- all 15 limbs red.
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
                -- Fractures are pure ZCity state (org.<limb> >= 1, brokenribs).
                -- C:U only draws the icon; no C:U fracture simulation runs.
                limbSet("broken", Fractured(org, limbId, map))
                limbSet("boneHealTimer", math.Clamp((1 - dmg) * 100, 0, 100))
                if map.dis then
                    local out = org[map.dis] == true
                    limbSet("dislocated", out)
                    -- C:U's WoundSystem_DislocationStart() uses this as the
                    -- bone's starting distance.  A fresh ZCity dislocation
                    -- would otherwise arrive with timer = 0 (already reduced)
                    -- and complete on the first input packet without ever
                    -- letting the player move the bone by hand.
                    if out then
                        if (tonumber(state.dislocationTimer) or 0) <= 0 then
                            limbSet("dislocationTimer", 100)
                        end
                    else
                        limbSet("dislocationTimer", 0)
                    end
                    ply._WSZCExpectedDislocation[limbId] = out
                end
            end
            if limbChanged then dirtyLimbs[limbId] = true end
        end
    end

    PullShrapnel(ply, org)

    if bodyChanged and h.SendCardioUpdate then pcall(h.SendCardioUpdate, ply, true) end
    if h.SendLimbUpdate then
        for limbId in pairs(dirtyLimbs) do pcall(h.SendLimbUpdate, ply, limbId, false) end
    end
end

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
        limbBleed = type(state) == "table" and (tonumber(state.bleed) or 0) or 0,
        limbPain = type(state) == "table" and (tonumber(state.pain) or 0) or 0,
        limbMuscle = type(state) == "table" and (tonumber(state.muscle) or 100) or 100,
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
    add("bleed", (after.limbBleed - before.limbBleed) * 0.2, 0)
    add("pain", (after.limbPain - before.limbPain) * 0.25, 0)
    add("internalBleed", after.internalBleeding - before.internalBleeding, 0)
    -- C:U uses 0..100 for both of these.  ZCity's organism expects 0..1 for
    -- painkiller and 0..2 for adrenaline; pushing +100 straight through made
    -- cl_camera.lua compute a -500 FOV offset (the "adrenaline" screen warp).
    add("painkiller", (after.painkiller - before.painkiller) * 0.01, 0, 1)
    add("adrenaline", (after.adrenaline - before.adrenaline) * 0.02, 0, 2)
    if type(org.stamina) == "table" then
        local max = math.max(tonumber(org.stamina.max) or 180, 1)
        org.stamina[1] = math.Clamp((tonumber(org.stamina[1]) or 0) +
            (after.stamina - before.stamina) / 100 * max, 0, max)
    end

    local map = LIMB_ORG[limbId]
    if map and map.dmg then
        add(map.dmg, -(after.limbMuscle - before.limbMuscle) / 100, 0, 1)
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
-- Wrapper installation
---------------------------------------------------------------------------

local installed = false
local wrappedByKey = {}
-- Lua functions cannot carry fields (fn._flag = true raises "attempt to index
-- a function value"), so identity markers live in a weak-keyed table instead.
local wrappedFns = setmetatable({}, { __mode = "k" })

--- Wrap an existing ZCity hook so it runs with WB.IsBridged() == false.
--- `pre` (optional) runs before the original, still inside the vanilla context.
--- GMod iterates hook tables with pairs(), so hook registration order is NOT a
--- reliable way to observe damage before ZCity scales it; doing it inside the
--- wrapper is.
local function WrapHook(event, name, pre)
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
    if pre then
        inner = function(...)
            pcall(pre, ...)
            return original(...)
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
    -- limb.  WSZC_AuthorityDamagePost runs afterwards (also for took=false).
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

local function InstallMedicalBridge()
    local wb = WB()
    if not (wb and wb.SwepHeal) or wb._WSZCSwepHealPatched then return end
    wb._WSZCSwepHealPatched = true
    local original = wb.SwepHeal
    wb.SwepHeal = function(swep, ent, mode, bone)
        if not Authority() then return original(swep, ent, mode, bone) end
        local ply = OwnerOf(ent) or (IsValid(ent) and ent:IsPlayer() and ent)
        local before = ply and WSZC.SnapshotMedical(ply, "body") or nil
        WSZC.SwepHealDepth = WSZC.SwepHealDepth + 1
        local ok, a, b, c = pcall(original, swep, ent, mode, bone)
        WSZC.SwepHealDepth = WSZC.SwepHealDepth - 1
        if WSZC.SwepHealDepth < 0 then WSZC.SwepHealDepth = 0 end
        if not ok then
            Warn("WB.SwepHeal failed: " .. tostring(a))
            return nil
        end
        if ply and before then
            WSZC.ApplyMedicalDelta(ply, "body", before)
        end
        return a, b, c
    end
end

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
local RESET_KEEP = {
    "otrub", "needotrub", "fake", "needfake",
    "canmove", "alive", "stun", "consciousness",
    "brain", "otrub_start", "unconscious",
}

local function SnapshotZCityStructure(org)
    local snap = {}
    for _, key in ipairs(RESET_KEEP) do snap[key] = org[key] end
    return snap
end

local function RestoreZCityStructure(org, snap)
    if type(org) ~= "table" or type(snap) ~= "table" then return end
    for key, value in pairs(snap) do org[key] = value end
    local owner = org.owner
    if IsValid(owner) then owner.fullsend = true end
    if hg then
        if hg.send_organism then pcall(hg.send_organism, org) end
        if hg.send_bareinfo then pcall(hg.send_bareinfo, org) end
    end
    -- Keep the C:U shadow (HUD / NWBool) in sync with the ZCity structure.
    if cvShadow and cvShadow:GetBool() and IsValid(owner) then
        pcall(PushShadow, owner, org)
    end
end

function WSZC.InstallResetStructureGuard()
    if WSZC._ResetGuardPatched then return true end
    local wb = WB()
    local clear = hg and hg.organism and hg.organism.Clear
    if not (wb and type(clear) == "function") then return false end
    WSZC._ResetGuardPatched = true

    local originalClear = clear
    hg.organism.Clear = function(org, ...)
        if not (cvPreserveReset and cvPreserveReset:GetBool() and Authority()) then
            return originalClear(org, ...)
        end
        if type(org) ~= "table" then return originalClear(org, ...) end
        local owner = org.owner
        local down = (IsValid(owner) and IsValid(owner.FakeRagdoll))
            or org.otrub == true or org.fake == true
        -- A normal Player Spawn has no ragdoll / unconscious state: let the
        -- stock clear run untouched there.
        if not down then return originalClear(org, ...) end
        local snap = SnapshotZCityStructure(org)
        local a, b, c = originalClear(org, ...)
        RestoreZCityStructure(org, snap)
        return a, b, c
    end

    if type(wb.ResetOrganism) == "function" then
        local originalReset = wb.ResetOrganism
        local originalRestore = wb.RestoreRagdoll
        wb.ResetOrganism = function(ent, ...)
            if not (cvPreserveReset and cvPreserveReset:GetBool() and Authority()) then
                return originalReset(ent, ...)
            end
            local ply = (wb.GetPlayer and wb.GetPlayer(ent))
                or (IsValid(ent) and ent.IsPlayer and ent:IsPlayer() and ent) or nil
            local org = IsValid(ply) and ply.organism or nil
            local snap = type(org) == "table" and SnapshotZCityStructure(org) or nil
            -- Suppress the explicit "stand up if the old state kept him on the
            -- floor" call.  Its timer.Simple(0) would otherwise run AFTER this
            -- wrapper returns and undo everything.
            wb.RestoreRagdoll = function() return true end
            local ok, res = pcall(originalReset, ent, ...)
            wb.RestoreRagdoll = originalRestore
            if snap then RestoreZCityStructure(org, snap) end
            if not ok then
                Warn("WB.ResetOrganism failed: " .. tostring(res))
                return false
            end
            return res
        end
    end
    return true
end

local function InstallVanillaHooks()
    -- Org Think "Main": without this wrapper the hook returns early through
    -- WB.Think() and every vanilla ZCity organ module (and Organs+) is skipped.
    WrapHook("Org Think", "Main")
    -- ZCity hit handling: prevents forwarding to WB.ApplyDamage and lets the
    -- vanilla organ/hitbox/bleed code run.
    -- `pre` captures the unscaled damage: takeRagdollDamage() calls
    -- dmginfo:ScaleDamage(0.15), so PostEntityTakeDamage would otherwise see
    -- only 15% of the real blast damage and C:U's thresholds would never fire.
    WrapHook("EntityTakeDamage", "homigrad-damage", CaptureRawDamage)
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
    installed = true

    -- Stubs make ZCity's vanilla paths authoritative even outside the wrapped
    -- hooks.  WB.Sync/Think are handled separately by InstallShadowBridge.
    Stub("ApplyDamage", false)
    Stub("ApplyCollision", false)
    Stub("ApplyFall", false)
    Stub("AddWoundManual", false)
    Stub("Amputate", false)

    InstallVanillaHooks()
    InstallShadowBridge()
    InstallMedicalBridge()
    DisableCUPhysiology()
    WSZC.DisableCUBloodReplacement()
    WSZC.InstallResetStructureGuard()

    -- Org Think runs at 10 Hz in ZCity.  Our own hook keeps the C:U HUD and the
    -- shrapnel shadow in sync, and holds the regeneration block.
    hook.Add("Org Think", "WSZC_OrganismShadow", function(owner, org, dt)
        if not Authority() then return end
        if not (IsValid(owner) and owner:IsPlayer() and owner:Alive()) then return end
        if type(org) ~= "table" then return end

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

        -- A botched shrapnel extraction keeps hurting and bleeding until the
        -- fragment is removed.  The irritation clears itself when C:U's
        -- extraction minigame empties state.shrapnel for that limb.
        if type(org.wszc_shrapnel_irritation) == "table" then
            local h = H()
            local dt = math.Clamp(tonumber(dt) or 0.1, 0, 0.5)
            for limbId, irritation in pairs(org.wszc_shrapnel_irritation) do
                local state = h and h.GetLimbState and h.GetLimbState(owner, limbId)
                if type(state) ~= "table" or (tonumber(state.shrapnel) or 0) <= 0 then
                    org.wszc_shrapnel_irritation[limbId] = nil
                else
                    local inc = math.Clamp(tonumber(irritation) or 0, 0, 20) * dt * 0.06
                    org.bleed = math.Clamp((tonumber(org.bleed) or 0) + inc, 0, 200)
                    org.pain = math.Clamp((tonumber(org.pain) or 0) + inc * 0.5, 0, 1000)
                end
            end
        end
    end)

    -- C:U's WoundSystem_SpawnSync restores persisted limb state on a map
    -- transition without calling InitPlayer().  GMod does not guarantee hook
    -- order, so clear shrapnel both immediately and on the next frame (after
    -- every PlayerSpawn hook has run).
    local function ClearSpawnShrapnel(ply)
        if not (Authority() and IsValid(ply)) then return end
        local org = ply.organism
        if type(org) == "table" then
            org.wszc_shrapnel = nil
            org.wszc_shrapnel_floor = nil
        end
        local h = H()
        local limbs = h and h.GetLimbs and h.GetLimbs(ply)
        if type(limbs) ~= "table" then return end
        for limbId, state in pairs(limbs) do
            if type(state) == "table" and (tonumber(state.shrapnel) or 0) > 0 then
                state.shrapnel = 0
                if h.SendLimbUpdate then pcall(h.SendLimbUpdate, ply, limbId, true) end
            end
        end
    end

    hook.Add("PlayerSpawn", "WSZC_OrganismSpawn", function(ply)
        if not Authority() then return end
        ClearSpawnShrapnel(ply)
        timer.Simple(0, function() ClearSpawnShrapnel(ply) end)
    end)

    -- Re-apply: other addons (or a woundsys_enabled toggle) may re-register
    -- these hooks/timers later.  Same defensive pattern as the damage wrapper.
    timer.Create("WSZC_AuthorityReapply", 5, 0, function()
        SetGlobalBool("WSZC_OrganismAuthority", Authority())
        if not Authority() then return end
        InstallVanillaHooks()
        DisableCUPhysiology()
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
    if WSZC.InstallOrganismMode() and (not cvCUBlood:GetBool() or WSZC._CUBloodOriginal) then return end
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
