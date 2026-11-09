#!/usr/bin/env python3
"""Focused regressions: unconscious cleanup, shrapnel DOT and explicit reset."""
from pathlib import Path
from zipfile import ZipFile
import sys

ROOT = Path(__file__).resolve().parents[2]
CONN = ROOT / "woundsystem_zcity_compat"
ORGANISM = CONN / "lua/autorun/server/sv_zcity_woundsystem_compat_organism.lua"
SERVER_MAIN = CONN / "lua/autorun/server/sv_zcity_woundsystem_compat.lua"
SERVER_MG = CONN / "lua/autorun/server/sv_zcity_woundsystem_compat_minigames.lua"
CLIENT_MG = CONN / "lua/autorun/client/cl_zcity_woundsystem_compat_minigames.lua"
LAYOUT = CONN / "lua/autorun/client/cl_zcity_woundsystem_compat_layout.lua"

results = []


def check(name, value):
    results.append((name, bool(value)))
    print(("PASS " if value else "FAIL ") + name)


organism_s = ORGANISM.read_text(encoding="utf-8")
shared_s = (CONN / "lua/autorun/sh_zcity_woundsystem_compat.lua").read_text(encoding="utf-8")
server_main_s = SERVER_MAIN.read_text(encoding="utf-8")
server_mg_s = SERVER_MG.read_text(encoding="utf-8")
client_mg_s = CLIENT_MG.read_text(encoding="utf-8")
layout_s = LAYOUT.read_text(encoding="utf-8")
with ZipFile(ROOT / "zcity.zip") as zcity_zip:
    tourniquet_swep_s = zcity_zip.read("z_city/lua/weapons/weapon_tourniquet.lua").decode("utf-8-sig")
    bandage_swep_s = zcity_zip.read("z_city/lua/weapons/weapon_bandage_sh.lua").decode("utf-8-sig")
    woundbridge_s = zcity_zip.read("z_city/lua/homigrad/woundbridge/sv_woundbridge.lua").decode("utf-8-sig")
    native_org_s = zcity_zip.read("z_city/lua/homigrad/organism/tier_1/sv_organism.lua").decode("utf-8-sig")
    native_input_s = zcity_zip.read("z_city/lua/homigrad/organism/tier_1/sv_input.lua").decode("utf-8-sig")
with ZipFile(ROOT / "zcity_full_pack.zip") as full_pack:
    limb_statuses_s = full_pack.read(
        "garrysmod/addons/casualties_unknown_health_system_beta/lua/woundsystem/shared/sh_limb_statuses.lua"
    ).decode("utf-8-sig")

client_context = layout_s.split("function WSZC.MinigameContextOK()", 1)[1].split("function WSZC.MinigameScale", 1)[0]
check("S01 unconscious closes WSZC + native games on both realms",
      '"WSZC_MinigameForceClose"' in server_mg_s
      and 'StopAllMinigames(ply, "unconscious", true)' in server_mg_s
      and "CUCloseShrapnelSession" in server_mg_s
      and "CUCloseDislocationSession" in server_mg_s
      and "CUCloseAedSession" in server_mg_s and '"Aed"' in server_mg_s
      and 'net.Receive("WSZC_MinigameForceClose"' in client_mg_s
      and '"WoundSystemUnconscious"' in layout_s
      and 'type(ply) == "table"' not in client_context)
check("S02 shotgun source is separate and requires positive identification",
      'RecordShrapnelSource(org, limbId, reason' in organism_s
      and '"shotgun"' in organism_s and '"glass"' in organism_s
      and 'AddShrapnel(ply, limbId, shotgunAdded, "shotgun")' in organism_s
      and "DMG_BUCKSHOT alone is NOT enough" in organism_s)
check("S03 every lodged piece grows a real wound; explicit reset clears it",
      "function WSZC.TickLodgedShrapnel" in organism_s
      and "wound.wszcShrapnel = SHRAPNEL_WOUND_TAG" in organism_s
      and "function WSZC.ClearAllShrapnel" in organism_s
      and "SnapshotZCityStructure(org, false, true)" in organism_s
      and "_ExplicitResetDepth" in organism_s)
check("S04 added WoundView cards are rolled back; native geometry remains",
      "zc_woundsystem_compat_woundview_polish" not in layout_s
      and "WSZC_WoundViewPolishBackground" not in layout_s
      and "DrawVitalRow" not in layout_s and "LIMB STATUS" not in layout_s
      and "WSZC_UNITMENU_LIMB_GEOMETRY" in layout_s)
check("S05 bandage budget and ordinary bleed are bounded for a physical roll",
      'zc_woundsystem_compat_bandage_strength", "3"' in organism_s
      and 'zc_woundsystem_compat_bleeding_multiplier", "0.55"' in organism_s
      and "org.bleedingmul = math.min" in organism_s
      and "+ count * (0.018 + irritation * 0.002) * dt * growth, 0, 8)" in organism_s
      and "function WSZC.ShrapnelBandageInProgress" in organism_s
      and "managedZero" in organism_s)
check("S06 physical tourniquet treats before native and requires a real wound",
      "directTourniquetTreated" in server_main_s
      and "if authoritativeTourniquet then" in server_main_s
      and "if not ok then return false, 0 end" in server_main_s
      and "medicalBefore.limbBleed = tonumber(directTourniquetAfter)" in server_main_s)
check("S07 stock physical SWEP really reaches this ApplyItemToBody contract",
      "hg.WoundBridge.SwepHeal(self, ent, mode, bone)" in tourniquet_swep_s
      and 'weapon_tourniquet    = {kind = "apply", item = "TOURNIQUET"' in woundbridge_s
      and "local ok = H.ApplyItemToBody(target, spec.item, limbId, 100)" in woundbridge_s
      and "if ok then\n\t\t\tswep.modeValues[idx] = 0" in woundbridge_s)
inject_pos = organism_s.find("function WSZC.InjectDamageShrapnel")
mark_pos = organism_s.find("WSZC.ShrapnelHandled[dmginfo] = true", inject_pos)
limb_pos = organism_s.find("local limbId = DamageLimb", inject_pos)
check("S08 shotgun injects after native damage and unresolved proxies stay retryable",
      'WrapHook("EntityTakeDamage", "homigrad-damage", CaptureRawDamage, InjectAfterZCityDamage)' in organism_s
      and "WSZC.InjectDamageShrapnel(ent, dmginfo, nil)" in organism_s
      and 0 <= limb_pos < mark_pos
      and "Do NOT mark an unresolved proxy hit as handled" in organism_s)
check("S09 explicit reset covers death ragdolls and the stock admin property",
      "OwnerOf(ent, true)" in organism_s
      and "OwnerOf(ent, true, true)" in organism_s
      and "list.reset_org" in organism_s
      and "originalClear(currentOrg)" in organism_s
      and "local currentOrg = IsValid(ply) and ply.organism or org" in organism_s)
check("S10 tourniquet route precedes treatment and native renderer gets real vectors",
      "pcall(WSZC.ResolveTourniquetLimb, swep, ent, mode, bone)" in organism_s
      and "WSZC.TourniquetLimbOverride = { ply = ply, limbId = routedLimb }" in organism_s
      and "tourniquetRoute.ply == ply" in server_main_s
      and "NormalizeNativeWound(visualWound)" in organism_s
      and "TOURNIQUET_VISUAL_BONES[limbId]" in organism_s
      and "wound[1]:GetNegated()" in bandage_swep_s)
shared_s = (CONN / 'lua/autorun/sh_zcity_woundsystem_compat.lua').read_text(encoding='utf-8')
check("S11 amputation is a distinct native-ZCity shadow and outranks bleed icons",
      'WSZC_AMPUTATION' in shared_s and 'InstallAmputationStatus' in shared_s
      and 'order = -10000' in shared_s
      and 'arm_R     = { dmg = "rarm", amp = nil' in organism_s
      and 'thigh_R   = { dmg = "rleg", amp = nil' in organism_s
      and 'WSZC_AMPUTATION' in organism_s)
check("S12 tourniquet selection has a real-amputation tier, never a fake bleed bonus",
      'function WSZC.BestTourniquetLimb' in organism_s
      and 'function WSZC.TourniquetApplicationSite' in organism_s
      and 'AMPUTATION_APPLICATION_SITE' in organism_s
      and 'BestTourniquetLimb' in organism_s
      and 'bleed = 1000' not in organism_s)
check("S13 FakeUp internal spawn preserves the complete native organism",
      'SnapshotRagdollOrganism' in organism_s
      and 'RestoreRagdollOrganism' in organism_s
      and 'OverrideSpawn == true' in organism_s
      and 'hook.Add("Fake Up", "WSZC_ShrapnelRagdollKeep"' in organism_s)
check("S14 conscious ragdoll is not an incapacitated minigame operator",
      'or org.fake == true or org.needfake == true' not in server_mg_s
      and 'or org.fake == true or org.needfake == true' not in layout_s
      and 'IsValid(ply.FakeRagdoll)' not in server_mg_s.split('local function PlayerIncapacitated', 1)[1].split('local function ValidSession', 1)[0]
      and 'if WSZC.MinigameContextOK() then return end' in client_mg_s)
check("S15 a generic Fake transition closes only a genuinely incapacitated operator",
      'hook.Add("Fake", "WSZC_MinigameUnconscious"' in server_mg_s
      and 'if PlayerIncapacitated(ply) then' in server_mg_s.split('hook.Add("Fake", "WSZC_MinigameUnconscious"', 1)[1])
check("S17 legacy radial reduction is blocked at both bridge and command levels",
      'function WSZC.InstallLegacyRadialMedicineBlock' in organism_s
      and 'wb.FixDislocation = legacyFixDislocationWrapper' in organism_s
      and 'concommand.Add("hg_fixdislocation"' in organism_s
      and 'WSZC.InstallLegacyRadialMedicineBlock()' in organism_s)
check("S18 rendered reduction is server-validated and closes the native session",
      'function WSZC.HandleDislocationVisualComplete' in organism_s
      and 'WSZC.DislocationVisualAligned(x, y)' in organism_s
      and 'session.id ~= sessionId' in organism_s
      and 'WSZC.RemoteMedicalValidPair(operator, target)' in organism_s
      and 'state.dislocated = false' in organism_s
      and 'WSZC.CUCloseDislocationSession, target, "complete"' in organism_s
      and 'WSZC.RefreshNativeSessionRefs(true)' in organism_s
      and 'WSZC.RefreshNativeSessionRefs(true)' in server_main_s
      and server_main_s.index('WSZC.RefreshNativeSessionRefs(true)')
          < server_main_s.index('if (caps and caps.cu_native_api)')
      and 'net.Receive("WSZC_DislocationVisualComplete"' in server_mg_s)

try:
    sys.path.insert(0, "/tmp/lupa_pkg")
    from lupa import LuaRuntime
except ImportError:
    LuaRuntime = None

if LuaRuntime is None:
    print("SKIP runtime checks (lupa unavailable)")
else:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
SERVER = true; CLIENT = false
WSZC = { OrganismAuthority = function() return true end }
WoundSystem = { Health = { Constants = { ShrapnelPieceCount = 5 } } }
hg = {}
math.Clamp = function(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end
table.Copy = function(t)
    local out = {}
    for k, v in pairs(t or {}) do if type(v) == "table" then out[k] = table.Copy(v) else out[k] = v end end
    return out
end
CreateConVar = function(name, def)
    return { GetBool = function() return def ~= "0" end,
             GetFloat = function() return tonumber(def) or 0 end }
end
GetConVar = function() return nil end
hook = { _t = {}, Add = function(e, n, f) hook._t[e] = hook._t[e] or {}; hook._t[e][n] = f end,
         Remove = function() end, GetTable = function() return hook._t end }
timer = { Simple = function() end, Create = function() end, Remove = function() end,
          Exists = function() return false end }
include = function() end
IsValid = function(v) return v ~= nil and v ~= false end
CurTime = function() return 100 end
print = function() end
ErrorNoHalt = function() end
SetGlobalBool = function() end
isnumber = function(v) return type(v) == "number" end
isvector = function(v) return type(v) == "table" and v._isVector == true end
Vector = function(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0, _isVector = true }
    v.GetNegated = function(self) return Vector(-self.x, -self.y, -self.z) end
    return v
end
Angle = function(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
vector_origin = Vector(0, 0, 0)
angle_zero = Angle(0, 0, 0)
bit = { band = function(a, b)
    local result, place = 0, 1
    a, b = math.floor(a or 0), math.floor(b or 0)
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + place end
        a, b = math.floor(a / 2), math.floor(b / 2); place = place * 2
    end
    return result
end }
DMG_BULLET, DMG_BUCKSHOT, DMG_BLAST, DMG_DISSOLVE = 1, 2, 4, 8
HITGROUP_RIGHTARM = 5
player = { GetAll = function() return {} end }
game = { GetAmmoName = function(id) return id == 12 and "12/70gauge" or "9mm" end }
''')
    lua.execute(organism_s)

    lua.execute(r'''
function MakePlayer()
    local ply = { _nw = {}, _limbs = {}, _body = {} }
    ply._limbs.hand_R = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100 }
    ply._limbs.forearm_R = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100 }
    ply._limbs.thorax = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100, infection = 0, infectionSpeed = 0 }
    ply._limbs.head = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100, infection = 0, infectionSpeed = 0 }
    ply._limbs.neck = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100, infection = 0, infectionSpeed = 0 }
    ply.IsPlayer = function() return true end
    ply.Alive = function() return true end
    ply.Nick = function() return "regression_player" end
    ply.SetNetVar = function() end
    ply.GetNWBool = function(self, key, fallback) local v = self._nw[key]; if v == nil then return fallback end; return v end
    ply.SetNWBool = function(self, key, value) self._nw[key] = value end
    ply.organism = {
        owner = ply, blood = 5000, bleed = 0, internalBleed = 0,
        pain = 0, avgpain = 0, painadd = 0, shock = 0,
        consciousness = 1, pulse = 70, brain = 0,
        wounds = {}, arterialwounds = {}, rarm = 0,
    }
    return ply
end
WoundSystem.Health.GetLimbs = function(ply) return ply._limbs end
WoundSystem.Health.GetLimbState = function(ply, id) return ply._limbs[id] end
WoundSystem.Health.GetBody = function(ply) return ply._body end
WoundSystem.Health.SendLimbUpdate = function() end
WoundSystem.Health.SendCardioUpdate = function() end
WoundSystem.Health.ResetPlayer = function(ply)
    for _, state in pairs(ply._limbs) do
        state.shrapnel, state.bleed, state.pain = 0, 0, 0
        state.broken, state.dislocated = false, false
    end
    ply._body.unconscious = false
    return true
end
WSZC.StopAllMinigames = function() return true end
function MakeDamage(weaponClass, numBullet, ammoId, damageType)
    local weapon = { NumBullet = numBullet, GetClass = function() return weaponClass end }
    local attacker = { GetActiveWeapon = function() return weapon end }
    return {
        GetDamageType = function() return damageType end,
        GetDamage = function() return 30 end,
        GetAmmoType = function() return ammoId end,
        GetInflictor = function() return weapon end,
        GetAttacker = function() return attacker end,
    }
end
''')

    sources = lua.execute(r'''
local pistolPlayer = MakePlayer()
WSZC.InjectDamageShrapnel(pistolPlayer, MakeDamage("weapon_pistol", 1, 9, 1), HITGROUP_RIGHTARM, 30)
WSZC.InjectDamageShrapnel(pistolPlayer, MakeDamage("weapon_pistol", 1, 9, 2), HITGROUP_RIGHTARM, 30)
local pistolClean = pistolPlayer._limbs.hand_R.shrapnel == 0
    and pistolPlayer._limbs.forearm_R.shrapnel == 0

local shotgunPlayer = MakePlayer()
WSZC.InjectDamageShrapnel(shotgunPlayer, MakeDamage("weapon_spas12", 8, 12, 0), HITGROUP_RIGHTARM, 30)
local org = shotgunPlayer.organism
local sources = org.wszc_shrapnel_sources.forearm_R
return pistolClean, shotgunPlayer._limbs.forearm_R.shrapnel == 3
    and sources.shotgun == 3 and sources.glass == nil
''')
    check("R01 pistol and bare DMG_BUCKSHOT create no fragments", sources[0])
    check("R02 confirmed shotgun creates its own fragment source", sources[1])

    physical_pellets = lua.execute(r'''
local function PhysBullet(class, pellets)
    local weapon = { NumBullet = pellets, GetClass = function() return class end }
    local attacker = { GetActiveWeapon = function() return weapon end }
    return {
        GetDamageType = function() return DMG_BULLET end,
        GetDamage = function() return 30 end,
        GetAmmoType = function() return -1 end,
        GetInflictor = function() return attacker end, -- real ZCity PhysBullet
        GetAttacker = function() return attacker end,
    }
end
local shotgun = MakePlayer()
WSZC.InjectDamageShrapnel(shotgun, PhysBullet("weapon_spas12", 8), HITGROUP_RIGHTARM, 30)
local activeWeaponWorks = shotgun._limbs.forearm_R.shrapnel == 3
    and shotgun.organism.wszc_shrapnel_sources.forearm_R.shotgun == 3
local pistol = MakePlayer()
WSZC.InjectDamageShrapnel(pistol, PhysBullet("weapon_pistol", 1), HITGROUP_RIGHTARM, 30)
return activeWeaponWorks, pistol._limbs.hand_R.shrapnel == 0 and pistol._limbs.forearm_R.shrapnel == 0
''')
    check("R12 PhysBullet inflictor=attacker still identifies active shotgun", physical_pellets[0])
    check("R13 active pistol with DMG_BULLET still creates no fragments", physical_pellets[1])

    placement = lua.execute(r'''
local ALL = {
    "head", "neck", "thorax", "abdomen", "pelvis",
    "arm_L", "forearm_L", "hand_L", "arm_R", "forearm_R", "hand_R",
    "thigh_L", "crus_L", "foot_L", "thigh_R", "crus_R", "foot_R",
}
local function AllLimbPlayer()
    local ply = MakePlayer()
    for _, id in ipairs(ALL) do
        ply._limbs[id] = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100 }
    end
    return ply
end
local shotgunActual, nativeWoundSchema = true, true
for _, id in ipairs(ALL) do
    local ply = AllLimbPlayer()
    local added = WSZC.AddShrapnel(ply, id, 1, "shotgun")
    local state = ply._limbs[id]
    local sources = ply.organism.wszc_shrapnel_sources[id]
    if not added or state.shrapnel ~= 3 or not sources or sources.shotgun ~= 3 then
        shotgunActual = false
    end
    for otherId, other in pairs(ply._limbs) do
        if otherId ~= id and (other.shrapnel or 0) ~= 0 then shotgunActual = false end
    end
    local wound = WSZC.EnsureLodgedWound(ply, ply.organism, id, 3)
    if not wound or not wound[2] or type(wound[2].GetNegated) ~= "function" or wound[3] == nil then
        nativeWoundSchema = false
    end
end

local glassOnly = true
for _, id in ipairs(ALL) do
    local ply = AllLimbPlayer()
    local lower = string.lower(id)
    local side = string.sub(id, -2) == "_L" and "_L" or "_R"
    local isLeg = string.find(lower, "thigh", 1, true) or string.find(lower, "crus", 1, true)
        or string.find(lower, "foot", 1, true)
    local expected = (isLeg and "foot" or "hand") .. side
    WSZC.AddShrapnel(ply, id, 1, "glass")
    for otherId, state in pairs(ply._limbs) do
        local expectedCount = otherId == expected and 3 or 0
        if (state.shrapnel or 0) ~= expectedCount then glassOnly = false end
    end
    local sources = ply.organism.wszc_shrapnel_sources[expected]
    if not sources or sources.glass ~= 3 or sources.shotgun ~= nil then glassOnly = false end
end
return shotgunActual, glassOnly, nativeWoundSchema
''')
    check("R29 shotgun stays on each actually hit limb across all 17 C:U limbs", placement[0])
    check("R30 glass alone keeps its hands/feet-only spawn mapping", placement[1])
    check("R31 synthetic shrapnel wounds satisfy native localPos/localAng schema", placement[2])

    native_damage = lua.execute(r'''
local post = hook._t.PostEntityTakeDamage.WSZC_AuthorityDamagePost
local proxy = { IsPlayer = function() return false end }
local ply = MakePlayer()
ply.organism.dmgstack = { [HITGROUP_RIGHTARM] = { 30, CurTime() } }
local dmg = MakeDamage("weapon_spas12", 8, -1, 0)
-- Real ZCity order: collision proxy first, then the actual player/ragdoll,
-- same CTakeDamageInfo, no explicit hitgroup, and took=false after return true.
post(proxy, dmg, false)
local proxyRetryable = WSZC.ShrapnelHandled[dmg] == nil
    and ply._limbs.hand_R.shrapnel == 0
post(ply, dmg, false)
local stackResolved = ply._limbs.forearm_R.shrapnel == 3
    and ply.organism.wszc_shrapnel_sources.forearm_R.shotgun == 3
post(ply, dmg, false)
local deduplicated = ply._limbs.forearm_R.shrapnel == 3

local bonesPlayer = MakePlayer()
bonesPlayer.organism.dmgstack = {}
bonesPlayer.HitBones = { ["ValveBiped.Bip01_R_Hand"] = CurTime() + 30 }
post(bonesPlayer, MakeDamage("weapon_xm1014", 8, -1, 0), false)
local bonesResolved = bonesPlayer._limbs.hand_R.shrapnel == 3
return proxyRetryable and stackResolved and deduplicated, bonesResolved
''')
    check("R23 proxy + nil hitgroup + dmgstack follows the real public damage hook", native_damage[0])
    check("R24 nil hitgroup resolves fresh ZCity HitBones without duplicate fragments", native_damage[1])

    upper_arm = lua.execute(r'''
local ply = MakePlayer()
ply._limbs.arm_R = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100 }
ply.organism.dmgstack = {}
ply.HitBones = { ["ValveBiped.Bip01_R_UpperArm"] = CurTime() + 30 }
local post = hook._t.PostEntityTakeDamage.WSZC_AuthorityDamagePost
post(ply, MakeDamage("weapon_spas12", 8, -1, 0), false)
return ply._limbs.arm_R.shrapnel == 3
    and ply._limbs.forearm_R.shrapnel == 0 and ply._limbs.hand_R.shrapnel == 0
    and ply.organism.wszc_shrapnel_sources.arm_R.shotgun == 3
''')
    check("R34 upper-arm HitBones stays on arm_R instead of forearm/hand fallback", upper_arm)

    effects = lua.execute(r'''
local ply = MakePlayer()
local normal = { 4, nil, nil, "ValveBiped.Bip01_R_Hand", 0 }
ply.organism.wounds = { normal }
WSZC.AddShrapnel(ply, "hand_R", 1, "shotgun")
WSZC.AddShrapnel(ply, "hand_R", 1, "glass")
local org = ply.organism
local tagged
for _, wound in pairs(org.wounds) do if wound.wszcShrapnel then tagged = wound end end
local severity = tagged[1]
WSZC.TickLodgedShrapnel(ply, org, 0.5)
local separate = org.wszc_shrapnel_sources.hand_R.shotgun == 3
    and org.wszc_shrapnel_sources.hand_R.glass == 2
local grows = tagged[1] > severity and org.avgpain > 0 and org.painadd > 0 and org.pain > 0
ply._WSZCLimbsRef = ply._limbs
ply._limbs.hand_R.shrapnel = 0
WSZC.SyncShrapnel(ply, org)
local lodgedLeft, extractionLeft = false, false
for _, wound in pairs(org.wounds) do
    if wound.wszcShrapnel then lodgedLeft = true end
    if wound.wszcShrapnelExtraction and wound[1] >= 0.3 then extractionLeft = true end
end
local removed = not lodgedLeft and extractionLeft and normal[1] == 4
    and org.wszc_shrapnel_sources.hand_R == nil
    and org.wszc_shrapnel_irritation.hand_R == nil
    and org.wszc_shrapnel_aftercare.hand_R.awaitingBandage == true
return separate, grows, removed
''')
    check("R03 shotgun and glass counts remain separate", effects[0])
    check("R04 lodged fragments increase real wound severity and pain", effects[1])
    check("R05 extraction replaces lodged wound with a separate aftercare wound", effects[2])

    reset = lua.execute(r'''
local ply = MakePlayer()
WSZC.AddShrapnel(ply, "hand_R", 1, "shotgun")
WSZC.MarkBandagedShrapnel(ply, "hand_R", { ["ValveBiped.Bip01_R_Hand"] = true })
ply.organism.wszc_bandaged_shrapnel.hand_R.infection = 12
ply.organism.wszc_infection = 12
ply._limbs.hand_R.isBandaged = true
ply._limbs.hand_R.infection = 12
ply.bandaged_limbs = { ["ValveBiped.Bip01_R_Hand"] = true }
ply.tourniquets = { { 0, 0, "ValveBiped.Bip01_R_Hand" } }
ply.organism.otrub = true
ply.organism.blood, ply.organism.pain = 1200, 80
hg.send_organism = function() end; hg.send_bareinfo = function() end
hg.organism = { Clear = function(org)
    local owner = org.owner
    -- Native Org Clear "Main" resets org.chest but forgets the derived
    -- org.brokenribs value.  Preserve that real upstream omission here so the
    -- reset regression cannot be hidden by an unrealistically complete mock.
    local nativeStaleBrokenRibs = org.brokenribs
    for key in pairs(org) do if key ~= "owner" then org[key] = nil end end
    org.owner = owner
    org.alive, org.otrub, org.blood, org.pain = true, false, 5000, 0
    org.bleed, org.internalBleed = 0, 0
    org.chest, org.brokenribs = 0, nativeStaleBrokenRibs
    org.wounds, org.arterialwounds = {}, {}
end }
restoreCalls = 0
hg.WoundBridge = {
    GetPlayer = function(ent)
        if ent.IsPlayer and ent:IsPlayer() and ent:Alive() then return ent end
        local org = ent.organism
        local owner = type(org) == "table" and org.owner or nil
        if owner and owner:Alive() and owner.FakeRagdoll == ent then return owner end
        return nil
    end,
    Sync = function() end,
    RestoreRagdoll = function() restoreCalls = restoreCalls + 1 end,
    -- Source-faithful WB.ResetOrganism order from sv_woundbridge.lua.
    ResetOrganism = function(ent)
        local target = hg.WoundBridge.GetPlayer(ent)
        if not target then return false end
        if not WoundSystem.Health.ResetPlayer(target) then return false end
        local org = target.organism
        if org then
            hg.organism.Clear(org)
            hg.WoundBridge.Sync(target, org)
            org.needotrub, org.otrub, org.needfake, org.fake = false, false, false, false
        end
        hg.WoundBridge.RestoreRagdoll(target, nil, false)
        if org then hg.send_bareinfo(org); hg.send_organism(org, target) end
        return true
    end,
}
WSZC.InstallResetStructureGuard()
hg.organism.Clear(ply.organism)
local transitionKept = ply.organism.otrub == true
    and ply.organism.wszc_shrapnel.hand_R == 3
    and ply.organism.wszc_shrapnel_sources.hand_R.shotgun == 3
    and ply.organism.wszc_bandaged_shrapnel.hand_R.infection == 12
    and ply.organism.wszc_infection == 12
ply.organism.blood, ply.organism.pain = 1200, 80
-- Reproduce the reported high-fall brain injury immediately before reset.
ply.organism.brain, ply.organism.alive = 0.85, false
ply.organism.unconscious, ply.organism.otrub_start = true, 80
ply.organism.needotrub, ply.organism.uncon_timer = true, 20
ply.organism.fake, ply.organism.needfake = true, true
ply._body.unconscious = true
ply._nw.WoundSystemUnconscious = true
ply._WSZCShadowNext = 1000 -- prove explicit reset bypasses the 4 Hz throttle
local resetResult = hg.WoundBridge.ResetOrganism(ply)
local explicitCleared = resetResult == true and restoreCalls == 0 and ply.organism.otrub == false
    and ply.organism.fake == true and ply.organism.needfake == true
    and ply.organism.blood == 5000
    and (ply.organism.wszc_shrapnel == nil or (ply.organism.wszc_shrapnel.hand_R or 0) == 0)
    and ply.organism.wszc_shrapnel_sources == nil
    and ply.organism.wszc_shrapnel_irritation == nil
    and ply.organism.wszc_bandaged_shrapnel == nil and ply.organism.wszc_infection == nil
    and #ply.organism.wounds == 0 and ply.organism.pain == 0
    and ply.organism.bleed == 0 and ply._limbs.hand_R.shrapnel == 0
    and ply._limbs.hand_R.isBandaged == false and ply._limbs.hand_R.infection == 0
    and next(ply.bandaged_limbs) == nil and next(ply.tourniquets) == nil
local brainReset = resetResult == true and restoreCalls == 0
    and ply.organism.alive == true and (tonumber(ply.organism.brain) or 0) == 0
    and ply.organism.otrub == false and ply.organism.needotrub == false
    and ply.organism.unconscious == false and ply.organism.otrub_start == nil
    and ply.organism.uncon_timer == 0
    and ply.organism.fake == true and ply.organism.needfake == true
    and ply._body.unconscious == false
    and ply:GetNWBool("WoundSystemUnconscious", true) == false
    and ply._WSZCShadowNext < 1000
ResetDebug = { result = resetResult, restoreCalls = restoreCalls,
    otrub = ply.organism.otrub, blood = ply.organism.blood, pain = ply.organism.pain,
    shrapnel = ply.organism.wszc_shrapnel, sources = ply.organism.wszc_shrapnel_sources,
    irritation = ply.organism.wszc_shrapnel_irritation,
    covered = ply.organism.wszc_bandaged_shrapnel, infection = ply.organism.wszc_infection,
    wounds = #ply.organism.wounds, bleed = ply.organism.bleed,
    limbShrapnel = ply._limbs.hand_R.shrapnel, limbBandaged = ply._limbs.hand_R.isBandaged,
    limbInfection = ply._limbs.hand_R.infection,
    bandages = next(ply.bandaged_limbs), tourniquets = next(ply.tourniquets) }
return transitionKept, explicitCleared, brainReset
''')
    check("R06 ordinary ragdoll clear still preserves fragments", reset[0])
    check("R07 explicit reset fully clears fragments and medical residue", reset[1])
    check("R94 brain-injury reset clears death/unconscious state but keeps conscious ragdoll", reset[2])
    if not reset[1]:
        debug = lua.globals().ResetDebug
        print("RESET_DEBUG", {k: debug[k] for k in (
            "result", "restoreCalls", "otrub", "blood", "pain", "shrapnel", "sources",
            "irritation", "covered", "infection", "wounds", "bleed", "limbShrapnel",
            "limbBandaged", "limbInfection", "bandages", "tourniquets")})

    fresh_after_reset = lua.execute(r'''
local bone = "ValveBiped.Bip01_R_Hand"
local ply = MakePlayer()
local rag = { bandaged_limbs = {}, SetNetVar = function(self, key, val) self.net = self.net or {}; self.net[key] = val end }
local current = { bandaged_limbs = {}, SetNetVar = rag.SetNetVar }
ply.FakeRagdoll = rag
hg.GetCurrentCharacter = function() return current end
WSZC.AddShrapnel(ply, "hand_R", 1, "shotgun")
WSZC.ApplyBandageToOrganism({ ply = ply, limbId = "hand_R", limb = ply._limbs.hand_R },
    { effects = { bandageSlowAmount = 15 } }, 1)
local formerlyCovered = WSZC.IsShrapnelBandaged(ply, "hand_R")
    and ply.bandaged_limbs[bone] and rag.bandaged_limbs[bone] and current.bandaged_limbs[bone]
-- The native C:U reset may detach the old ragdoll before hg.organism.Clear.
local originalReset = WoundSystem.Health.ResetPlayer
WoundSystem.Health.ResetPlayer = function(target)
    local ok = originalReset(target)
    target.FakeRagdoll = nil
    hg.GetCurrentCharacter = function(p) return p end
    return ok
end
local success = hg.WoundBridge.ResetOrganism(ply)
WoundSystem.Health.ResetPlayer = originalReset
local clean = success and next(ply.bandaged_limbs) == nil and next(rag.bandaged_limbs) == nil
    and next(current.bandaged_limbs) == nil and next(rag.net.bandaged_limbs) == nil
    and next(current.net.bandaged_limbs) == nil and ply._limbs.hand_R.isBandaged == false
    and not ply.organism.wszc_bandaged_shrapnel
-- Simulate a later transition pulling the old representation back in.
ply.FakeRagdoll = rag
ply.bandaged_limbs = table.Copy(rag.bandaged_limbs)
WSZC.AddShrapnel(ply, "hand_R", 1, "shotgun")
local fresh = ply._limbs.hand_R.shrapnel == 3
    and not WSZC.IsShrapnelBandaged(ply, "hand_R")
    and WSZC.GetBandageBleeding(ply, "hand_R") > 0
    and (not ply.organism.wszc_shrapnel_closed or not ply.organism.wszc_shrapnel_closed.hand_R)
WSZC.SyncShrapnel(ply, ply.organism)
WSZC.TickLodgedShrapnel(ply, ply.organism, 0.5)
local stable = not WSZC.IsShrapnelBandaged(ply, "hand_R") and WSZC.GetBandageBleeding(ply, "hand_R") > 0
hg.GetCurrentCharacter = nil
return formerlyCovered, clean, fresh and stable
''')
    check("R107 real dressing reaches player, ragdoll and current character", fresh_after_reset[0])
    check("R108 reset clears detached and current character dressing tables and netvars", fresh_after_reset[1])
    check("R109 a new pellet after reset remains an uncovered bleeding wound", fresh_after_reset[2])

    tracked_reset = lua.execute(r'''
local ply = MakePlayer()
local rag = { bandaged_limbs = { old = true }, tourniquets = { { 1 } },
    wounds = { { 5 } }, arterialwounds = { { 10 } },
    SetNetVar = function(self, key, value) self.net = self.net or {}; self.net[key] = value end }
ply.FakeRagdoll = rag
hook._t.Fake.WSZC_ShrapnelRagdollKeep(ply, rag)
ply.FakeRagdoll = nil -- the old body is no longer discoverable by current-character lookups
ply.bandaged_limbs, ply.tourniquets = { old = true }, { { 1 } }
ply._limbs.hand_R.customStatuses = { TOURNIQUET = 5, OTHER_MEDICAL = 10 }
ply._limbs.hand_R.hasInjection, ply._limbs.hand_R.disinfectTime = true, 55
hg.TourniquetGuys = { rag, ply }
local ok = hg.WoundBridge.ResetOrganism(ply)
local clean = ok and next(rag.bandaged_limbs) == nil and next(rag.tourniquets) == nil
    and next(rag.net.bandaged_limbs) == nil and next(rag.net.Tourniquets) == nil
    and next(rag.wounds) == nil and next(rag.arterialwounds) == nil
    and next(rag.net.wounds) == nil and next(rag.net.arterialwounds) == nil
    and next(ply.bandaged_limbs) == nil and next(ply.tourniquets) == nil
    and #hg.TourniquetGuys == 0 and next(ply._limbs.hand_R.customStatuses) == nil
    and not ply._limbs.hand_R.hasInjection and ply._limbs.hand_R.disinfectTime == 0
return clean
''')
    check("R111 explicit reset clears tracked detached bodies, tourniquets and all medical statuses", tracked_reset)

    physical_on_error = lua.execute(r'''
local ply = MakePlayer()
local rag = { bandaged_limbs = { old = true }, tourniquets = { 1 },
    SetNetVar = function(self, key, value) self.net = self.net or {}; self.net[key] = value end }
ply.FakeRagdoll = rag
local previous = WoundSystem.Health.GetLimbs
WoundSystem.Health.GetLimbs = function() error("broken C:U limb accessor") end
local ok = pcall(WSZC.ClearAllShrapnel, ply, ply.organism)
WoundSystem.Health.GetLimbs = previous
return not ok and next(rag.bandaged_limbs) == nil and next(rag.tourniquets) == nil
    and next(rag.net.bandaged_limbs) == nil and next(rag.net.Tourniquets) == nil
''')
    check("R112 physical dressing cleanup runs even if C:U limb reset fails", physical_on_error)

    visual_broadcast = lua.execute(r'''
local previous = net
local written = {}
net = { Start = function(name) written.name = name end,
    WriteUInt = function(value, bits) written[#written + 1] = { value, bits } end,
    Broadcast = function() written.broadcast = true end }
WSZC.SendMedicalVisualReset({ { EntIndex = function() return 14 end },
    { EntIndex = function() return 29 end } })
net = previous
return written.name == "WSZC_ResetMedicalVisuals" and written.broadcast
    and written[1][1] == 2 and written[1][2] == 8
    and written[2][1] == 14 and written[2][2] == 16
    and written[3][1] == 29 and written[3][2] == 16
''')
    check("R115 reset notifies all clients to remove physical treatment models", visual_broadcast)

    death_reset = lua.execute(r'''
local dead = MakePlayer()
dead.Alive = function() return false end
dead.organism.blood = 900
WSZC.AddShrapnel(dead, "hand_R", 1, "shotgun")
local ragdoll = { IsPlayer = function() return false end, organism = dead.organism }
dead.DeathRagdoll = ragdoll
player.GetAll = function() return { dead } end
local nativeResult = hg.WoundBridge.ResetOrganism(ragdoll)
local deathCleared = nativeResult == false -- stock WB cannot accept a dead owner
    and (dead.organism.wszc_shrapnel == nil or (dead.organism.wszc_shrapnel.hand_R or 0) == 0)
    and dead.organism.wszc_shrapnel_sources == nil
    and dead.organism.blood == 5000 and next(dead.HitBones) == nil
    and dead._limbs.hand_R.shrapnel == 0

hg.RagdollOwner = function(ent)
    if ent.IsPlayer and ent:IsPlayer() and ent:Alive() then return ent end
    local org = ent.organism
    local owner = type(org) == "table" and org.owner or nil
    if owner and owner:Alive() and owner.FakeRagdoll == ent then return owner end
    return nil
end
local originalResolver = hg.RagdollOwner
WSZC.AddShrapnel(dead, "hand_R", 1, "shotgun")
propertyNick = nil
ragdoll.bandaged_limbs, ragdoll.tourniquets = { stale = true }, { 1 }
ragdoll.SetNetVar = function(self, key, value) self.net = self.net or {}; self.net[key] = value end
dead.DeathRagdoll = nil -- admin targets a ragdoll no longer attached to its owner
local property = { Filter = function() return true end }
property.Receive = function(self, length, admin)
    local ent = net.ReadEntity()
    if not self:Filter(ent, admin) then return end
    ent = hg.RagdollOwner(ent) or ent
    if not hg.WoundBridge.ResetOrganism(ent) then hg.organism.Clear(ent.organism) end
    propertyNick = ent:Nick() -- stock source: errors here if ent is still a ragdoll
    return true
end
local propertyList = { reset_org = property }
properties = { GetTable = function() return propertyList end }
net = { ReadEntity = function() return ragdoll end }
WSZC.InstallResetStructureGuard()
local ok, err = pcall(property.Receive, property, 0, dead)
local propertyWorks = ok and propertyNick == "regression_player"
    and (dead.organism.wszc_shrapnel == nil or (dead.organism.wszc_shrapnel.hand_R or 0) == 0)
    and dead.organism.blood == 5000
    and hg.RagdollOwner == originalResolver and WSZC._ExplicitResetDepth == 0
    and WSZC._ResetPropertyTarget == nil and next(ragdoll.bandaged_limbs) == nil
    and next(ragdoll.tourniquets) == nil and next(ragdoll.net.Tourniquets) == nil
if not ok then propertyError = tostring(err) end

local cleanupPlayer = MakePlayer()
local stockRestore = hg.WoundBridge.RestoreRagdoll
local stockGetLimbs = WoundSystem.Health.GetLimbs
WoundSystem.Health.GetLimbs = function() error("intentional cleanup regression probe") end
local cleanupCallOK, cleanupResult = pcall(hg.WoundBridge.ResetOrganism, cleanupPlayer)
WoundSystem.Health.GetLimbs = stockGetLimbs
local cleanupFinally = cleanupCallOK and cleanupResult == false
    and WSZC._ExplicitResetDepth == 0 and cleanupPlayer._WSZCExplicitReset ~= true
    and hg.WoundBridge.RestoreRagdoll == stockRestore

DeathDebug = { nativeResult = nativeResult, blood = dead.organism.blood,
    shrapnel = dead.organism.wszc_shrapnel, sources = dead.organism.wszc_shrapnel_sources,
    hitBones = next(dead.HitBones), limbShrapnel = dead._limbs.hand_R.shrapnel,
    ok = ok, error = propertyError, nick = propertyNick,
    resolverRestored = hg.RagdollOwner == originalResolver,
    depth = WSZC._ExplicitResetDepth }
return deathCleared, propertyWorks, cleanupFinally
''')
    check("R25 death-ragdoll reset uses native Clear fallback and clears residue", death_reset[0])
    check("R26 stock reset_org resolves dead owner and never calls Nick on ragdoll", death_reset[1])
    check("R28 reset cleanup errors still restore depth, marker and RestoreRagdoll", death_reset[2])
    if not all(death_reset):
        debug = lua.globals().DeathDebug
        print("DEATH_RESET_DEBUG", {k: debug[k] for k in (
            "nativeResult", "blood", "shrapnel", "sources", "hitBones", "limbShrapnel",
            "ok", "error", "nick", "resolverRestored", "depth")})

    complications = lua.execute(r'''
local ply = MakePlayer()
local notices = {}
ply.Notify = function(_, text) notices[#notices + 1] = text end
ply.PrintMessage = function(_, kind, text) notices[#notices + 1] = text end
WSZC.AddShrapnel(ply, "hand_R", 1, "shotgun")
local limb = ply._limbs.hand_R
limb.isBandaged = false
local treated = WSZC.ApplyBandageToOrganism(
    { ply = ply, limbId = "hand_R", limb = limb },
    { effects = { bandageSlowAmount = 15 } }, 1)
local entry = ply.organism.wszc_bandaged_shrapnel.hand_R
local bandageAllowed = treated > 0 and WSZC.IsShrapnelBandaged(ply, "hand_R")
    and ply._limbs.hand_R.shrapnel == 3 and entry.covered == true
    and WSZC.GetBandageBleeding(ply, "hand_R") == 0
for _ = 1, 120 do WSZC.TickLodgedShrapnel(ply, ply.organism, 0.5) end
local noRegrow = WSZC.GetBandageBleeding(ply, "hand_R") == 0
for _, wound in pairs(ply.organism.wounds) do
    if wound.wszcShrapnel and (tonumber(wound[1]) or 0) > 0 then noRegrow = false end
end
for _ = 1, 10 do WSZC.TickBandagedShrapnel(ply, ply.organism, 0.5) end
local infected = entry.infectionAge == 5 and limb.infection >= 25
    and limb.infectionSpeed == 0 and limb.disinfectTime == 0
    and ply._limbs.thorax.infection == 0 and ply._limbs.head.infection == 0
local infectionBefore = entry.infectionAge

local refs = {}
local sessions = { Shrapnel = { [ply] = { limbId = "hand_R", id = 41 } } }
local closed, built, opened, consumed, unwrapStarted = 0, 0, 0, 0, 0
refs.Sessions = sessions
refs.SendShrapnelOpen = function() opened = opened + 1 end
refs.CloseShrapnelSession = function(_, reason)
    closed = closed + 1
    sessions.Shrapnel[ply] = nil
end
refs.BuildShrapnelSession = function(limbId, count)
    built = built + 1
    return { limbId = limbId, amount = count, id = 42 }
end
refs.ShrapnelItemHasTweezers = function() return true end
refs.ConsumeToolDurability = function() consumed = consumed + 1; return true end
refs.BroadcastMinigameOneShot = function() end
WSZC.FindUpvalue = function(name) return refs[name] end
WSZC.StartShrapnelUnwrap = function(_, limbId)
    unwrapStarted = unwrapStarted + 1
    return limbId == "hand_R"
end
net = {
    Receivers = { WoundSystem_ShrapnelStart = function() error("old receiver must be replaced") end },
    Receive = function(name, fn) net.Receivers[name] = fn end,
    ReadString = function() return "hand_R" end,
    ReadUInt = function() return 0 end,
    BytesLeft = function() return 1, 0 end,
}
local installed = WSZC.InstallShrapnelBandageGuard()
net.Receivers.WoundSystem_ShrapnelStart(0, ply)
local unwrapGate = installed and closed == 1 and unwrapStarted == 1
    and built == 0 and consumed == 0 and sessions.Shrapnel[ply] == nil
    and ply._limbs.hand_R.shrapnel == 3
    and WSZC.IsShrapnelBandaged(ply, "hand_R")
    and entry.infectionAge == infectionBefore and limb.isBandaged ~= false
-- In real GMod net.Receive stores lowercase keys. A remote covered click
-- must open the operator's session for the patient, and retries must not stack.
local medic = MakePlayer()
local capturedOperator, capturedPatient
WSZC.RemoteNativeOperator = function(patient) if patient == ply then return medic end end
WSZC.StartShrapnelUnwrap = function(operator, limbId, target)
    capturedOperator, capturedPatient = operator, target
    return limbId == "hand_R"
end
net.Receivers = { woundsystem_shrapnelstart = function() end }
net.Receive = function(name, fn) net.Receivers[string.lower(name)] = fn end
local installedLower = WSZC.InstallShrapnelBandageGuard()
local guarded = net.Receivers.woundsystem_shrapnelstart
local retry = WSZC.InstallShrapnelBandageGuard()
net.Receivers.woundsystem_shrapnelstart(0, ply)
local remoteGuard = installedLower and retry and guarded == net.Receivers.woundsystem_shrapnelstart
    and capturedOperator == medic and capturedPatient == ply and WSZC.IsShrapnelBandaged(ply, "hand_R")
WSZC.RemoteNativeOperator = nil
net.Receivers.WoundSystem_ShrapnelStart = net.Receivers.woundsystem_shrapnelstart

-- This is the callback used by the server after a 360-degree reverse input.
local completionUnwrapped = WSZC.RemoveBandageForShrapnel(ply, "hand_R")
    and not WSZC.IsShrapnelBandaged(ply, "hand_R")
    and limb.isBandaged == false and entry.infectionAge == infectionBefore
net.Receivers.WoundSystem_ShrapnelStart(0, ply)
local secondClickNative = completionUnwrapped and built == 1 and opened == 1 and consumed == 1
    and sessions.Shrapnel[ply] and sessions.Shrapnel[ply].id == 42

-- Partial extraction also starts aftercare.  Re-dressing with two fragments
-- still inside closes ALL external blood but deliberately keeps the infection.
ply._WSZCLimbsRef = ply._limbs
ply._limbs.hand_R.shrapnel = 2
WSZC.SyncShrapnel(ply, ply.organism)
limb.isBandaged = false
WSZC.ApplyBandageToOrganism(
    { ply = ply, limbId = "hand_R", limb = limb },
    { effects = { bandageSlowAmount = 15 } }, 1)
local partialCovered = WSZC.GetBandageBleeding(ply, "hand_R") == 0
    and ply.organism.wszc_shrapnel_aftercare.hand_R == nil
    and ply.organism.wszc_bandaged_shrapnel.hand_R == entry
    and WSZC.IsShrapnelBandaged(ply, "hand_R")
    and ply._limbs.hand_R.infection >= 25
-- A second completed reverse minigame exposes the remaining fragments.
WSZC.RemoveBandageForShrapnel(ply, "hand_R")
ply._limbs.hand_R.shrapnel = 0
WSZC.SyncShrapnel(ply, ply.organism)
local aftercare = ply.organism.wszc_shrapnel_aftercare.hand_R
local extractionWound
for _, wound in pairs(ply.organism.wounds) do
    if wound.wszcShrapnelExtraction then extractionWound = wound end
end
local initialExtractionBleed = extractionWound and extractionWound[1] or 0
local initialPain = ply.organism.painadd
for _ = 1, 100 do
    WSZC.TickShrapnelAftercare(ply, ply.organism, 0.5)
    WSZC.TickBandagedShrapnel(ply, ply.organism, 0.5)
end
local extractionPersists = aftercare and extractionWound
    and extractionWound[1] > initialExtractionBleed
    and ply.organism.painadd > initialPain
    and entry.infectionAge > infectionBefore
    and ply.organism.wszc_bandaged_shrapnel.hand_R == entry
    and ply._limbs.hand_R.infection >= 25

limb.isBandaged = false
WSZC.ApplyBandageToOrganism(
    { ply = ply, limbId = "hand_R", limb = limb },
    { effects = { bandageSlowAmount = 15 } }, 1)
local extractionTagLeft = false
for _, wound in pairs(ply.organism.wounds) do
    if wound.wszcShrapnelExtraction then extractionTagLeft = true end
end
local painAtCure = ply.organism.painadd
WSZC.TickShrapnelAftercare(ply, ply.organism, 0.5)
local rebandageCures = WSZC.GetBandageBleeding(ply, "hand_R") == 0
    and not extractionTagLeft
    and (ply.organism.wszc_shrapnel_aftercare == nil
        or ply.organism.wszc_shrapnel_aftercare.hand_R == nil)
    and ply.organism.wszc_bandaged_shrapnel.hand_R == nil
    and ply.organism.wszc_infection == nil
    and ply._limbs.hand_R.infection == 0
    and ply._limbs.thorax.infection == 0 and ply._limbs.head.infection == 0
    and ply.organism.painadd == painAtCure

local preDressed = MakePlayer()
preDressed._limbs.hand_R.isBandaged = true
preDressed.bandaged_limbs = { ["ValveBiped.Bip01_R_Hand"] = true }
WSZC.AddShrapnel(preDressed, "hand_R", 1, "shotgun")
local preDressedCovered = WSZC.IsShrapnelBandaged(preDressed, "hand_R")
    and preDressed.organism.wszc_bandaged_shrapnel.hand_R.bones["ValveBiped.Bip01_R_Hand"] == true
    and WSZC.GetBandageBleeding(preDressed, "hand_R") == 0
    and preDressed._limbs.hand_R.infection >= 25
    and preDressed._limbs.hand_R.disinfectTime == 0
return bandageAllowed, noRegrow, infected, unwrapGate, secondClickNative,
    extractionPersists, rebandageCures, preDressedCovered, partialCovered, remoteGuard, #notices == 0
''')
    check("R14 a complete bandage stops external bleeding with shrapnel still lodged", complications[0])
    check("R53 covered shrapnel never regrows or recreates its external wound", complications[1])
    check("R55 covered shrapnel immediately uses infection, not disinfect/processing", complications[2])
    check("R16 covered click starts reverse minigame without click-unwrap or tool cost", complications[3])
    check("R17 completed unwrap then permits the native shrapnel session", complications[4])
    check("R18 extraction retains infection and adds growing bleeding and pain", complications[5])
    check("R54 only full re-bandaging clears extraction aftercare and infection", complications[6])
    check("R22 a pellet into an already dressed limb is covered without external bleed", complications[7])
    check("R59 partial extraction can be re-bandaged without curing remaining infection", complications[8])
    check("R96 lowercase native shrapnel guard is idempotent and opens remote unwrap for medic", complications[9])
    check("shrapnel bandaging and extraction do not emit instructional messages", complications[10])

    timed_bandage = lua.execute(r'''
-- Real GAUZE: a 100-durability roll, 12 complete turns, one partial effect per
-- turn.  A second ordinary wound deliberately remains after the shrapnel is
-- closed: the old code recreated the fragment wound on the very next tick.
local ply = MakePlayer()
table.insert(ply.organism.wounds, {
    12, Vector(0, 0, 0), Angle(0, 0, 0),
    "ValveBiped.Bip01_R_Hand", CurTime(),
})
WSZC.AddShrapnel(ply, "hand_R", 3, "shotgun") -- physical maximum: 5 pieces
local function TaggedWound()
    for _, wound in pairs(ply.organism.wounds) do
        if wound.wszcShrapnel then return wound end
    end
end
local function NativeWound()
    for _, wound in pairs(ply.organism.wounds) do
        if not wound.wszcShrapnel and not wound.wszcShrapnelExtraction then return wound end
    end
end
local operator = MakePlayer()
WSZC.MinigameSessions = {
    [operator] = {
        kind = "bandage", mode = "gauze", target = ply,
        limbId = "hand_R", closed = false,
    },
}
local function NativeRemoveZeroWounds(org)
    -- Exact native sv_blood behaviour: zero entries do NOT survive for our
    -- managed-zero table check to find on the next tick.
    for i = #org.wounds, 1, -1 do
        if type(org.wounds[i]) == "table" and (tonumber(org.wounds[i][1]) or 0) == 0 then
            table.remove(org.wounds, i)
        end
    end
end
local profile = { effects = { bandageSlowAmount = 45 } }
local perWrap = 100 / 12
local firstClosed, firstDidNotRespawn = false, false
for wrap = 1, 12 do
    WSZC.ApplyBandageToOrganism(
        { ply = ply, limbId = "hand_R", limb = ply._limbs.hand_R },
        profile, (perWrap / perWrap) / 12)
    local tagged, native = TaggedWound(), NativeWound()
    if wrap == 1 then
        firstClosed = tagged and tagged[1] == 0
            and native and native[1] > 0
            and not WSZC.IsShrapnelBandaged(ply, "hand_R")
            and ply.organism.wszc_shrapnel_closed.hand_R == true
        NativeRemoveZeroWounds(ply.organism)
        WSZC.TickLodgedShrapnel(ply, ply.organism, 0.5)
        WSZC.TickShrapnelAftercare(ply, ply.organism, 0.5)
        tagged = TaggedWound()
        firstDidNotRespawn = (not tagged or tagged[1] == 0)
            and ply.organism.wszc_shrapnel_closed.hand_R == true
    else
        WSZC.TickLodgedShrapnel(ply, ply.organism, 0.5)
        WSZC.TickShrapnelAftercare(ply, ply.organism, 0.5)
    end
    WSZC.TickBandagedShrapnel(ply, ply.organism, 0.5)
end
local entry = ply.organism.wszc_bandaged_shrapnel.hand_R
local completed = firstClosed and firstDidNotRespawn
    and WSZC.GetBandageBleeding(ply, "hand_R") == 0
    and WSZC.IsShrapnelBandaged(ply, "hand_R")
    and ply._limbs.hand_R.shrapnel == 5
    and (not TaggedWound() or TaggedWound()[1] == 0)
    and ply.organism.wszc_shrapnel_closed.hand_R == true
    and entry and entry.infectionAge > 0
WSZC.MinigameSessions = {}

-- Active treatment freezes NEW fragment growth, not the existing bleed.  Once
-- the session ends the ordinary lodged-wound simulation resumes normally.
local waiting = MakePlayer()
WSZC.AddShrapnel(waiting, "hand_R", 3, "shotgun")
local waitingWound = WSZC.EnsureLodgedWound(waiting, waiting.organism, "hand_R", 5)
local severity, pain = waitingWound[1], waiting.organism.avgpain
WSZC.MinigameSessions = {
    [operator] = { kind = "bandage", mode = "gauze", target = waiting,
                   limbId = "hand_R", closed = false },
}
for _ = 1, 20 do WSZC.TickLodgedShrapnel(waiting, waiting.organism, 0.5) end
local grace = waitingWound[1] == severity and waiting.organism.avgpain == pain
    and WSZC.GetBandageBleeding(waiting, "hand_R") > 0
WSZC.MinigameSessions = {}
WSZC.TickLodgedShrapnel(waiting, waiting.organism, 0.5)
local resumed = waitingWound[1] > severity and waiting.organism.avgpain > pain

-- With no unrelated wound, one complete physical turn now closes even the
-- maximum initial 5-piece wound; the fragment itself and infection cycle stay.
local quick = MakePlayer()
WSZC.AddShrapnel(quick, "hand_R", 3, "shotgun")
WSZC.ApplyBandageToOrganism(
    { ply = quick, limbId = "hand_R", limb = quick._limbs.hand_R },
    profile, 1 / 12)
local oneTurn = WSZC.GetBandageBleeding(quick, "hand_R") == 0
    and WSZC.IsShrapnelBandaged(quick, "hand_R")
    and quick._limbs.hand_R.shrapnel == 5

-- The SAME native table.remove race exists for aftercare.  Close its small
-- wound while a larger ordinary wound remains, delete zero entries exactly as
-- sv_blood does, and verify that only pain/age (not external bleed) continues.
local after = MakePlayer()
table.insert(after.organism.wounds, {
    20, Vector(0, 0, 0), Angle(0, 0, 0),
    "ValveBiped.Bip01_R_Hand", CurTime(),
})
WSZC.StartShrapnelAftercare(after, after.organism, "hand_R", 1)
WSZC.ApplyBandageToOrganism(
    { ply = after, limbId = "hand_R", limb = after._limbs.hand_R }, profile, 1 / 12)
local aftercareMarker = after.organism.wszc_shrapnel_aftercare_closed
    and after.organism.wszc_shrapnel_aftercare_closed.hand_R == true
NativeRemoveZeroWounds(after.organism)
WSZC.TickShrapnelAftercare(after, after.organism, 0.5)
local extractionReopened, ordinaryLeft = false, false
for _, wound in pairs(after.organism.wounds) do
    if wound.wszcShrapnelExtraction and (tonumber(wound[1]) or 0) > 0 then
        extractionReopened = true
    elseif not wound.wszcShrapnelExtraction and (tonumber(wound[1]) or 0) > 0 then
        ordinaryLeft = true
    end
end
local aftercareStable = aftercareMarker and not extractionReopened and ordinaryLeft
    and WSZC.ShrapnelAftercarePending(after, "hand_R")
    and after.organism.wszc_shrapnel_aftercare_closed.hand_R == true

-- A clot marker must never suppress a NEW pellet on a limb whose shrapnel was
-- closed but whose unrelated native wound keeps it out of the covered state.
local reinjured = MakePlayer()
table.insert(reinjured.organism.wounds, {
    20, Vector(0, 0, 0), Angle(0, 0, 0),
    "ValveBiped.Bip01_R_Hand", CurTime(),
})
WSZC.AddShrapnel(reinjured, "hand_R", 1, "shotgun") -- 3 pieces
WSZC.ApplyBandageToOrganism(
    { ply = reinjured, limbId = "hand_R", limb = reinjured._limbs.hand_R }, profile, 1 / 12)
local closedNotCovered = reinjured.organism.wszc_shrapnel_closed.hand_R == true
    and not WSZC.IsShrapnelBandaged(reinjured, "hand_R")
-- Keep the clot record but remove the physical dressing; otherwise the stock
-- rule for a pellet into an ALREADY DRESSED limb correctly covers the new hit.
reinjured.bandaged_limbs = {}
reinjured._limbs.hand_R.isBandaged = false
WSZC.AddShrapnel(reinjured, "hand_R", 1, "shotgun") -- 5 pieces, NEW injury
local reopenedSeverity = 0
for _, wound in pairs(reinjured.organism.wounds) do
    if wound.wszcShrapnel then reopenedSeverity = math.max(reopenedSeverity, wound[1]) end
end
local newHitOpens = closedNotCovered and reinjured._limbs.hand_R.shrapnel == 5
    and math.abs(reopenedSeverity - 4) < 0.001
    and reinjured.organism.wszc_shrapnel_closed.hand_R ~= true
return completed, grace and resumed, oneTurn, aftercareStable, newHitOpens
''')
    check("R60 timed GAUZE wraps close mixed shrapnel bleeding without wound respawn", timed_bandage[0])
    check("R61 active bandaging pauses only new shrapnel growth, then ticks resume", timed_bandage[1])
    check("R62 one real GAUZE turn can close the maximum initial shrapnel wound", timed_bandage[2])
    check("R63 native zero-wound removal cannot reopen partially dressed aftercare", timed_bandage[3])
    check("R64 a new pellet reopens a previously clotted but uncovered shrapnel wound", timed_bandage[4])

    infection_timeline = lua.execute(r'''
local ply = MakePlayer()
ply._alive = true
ply._kills = 0
local notices = {}
ply.Notify = function(_, text) notices[#notices + 1] = text end
ply.PrintMessage = function(_, kind, text) notices[#notices + 1] = text end
ply.Alive = function(self) return self._alive end
ply.Kill = function(self) self._alive = false; self._kills = self._kills + 1 end
WSZC.AddShrapnel(ply, "hand_R", 1, "shotgun")
WSZC.ApplyBandageToOrganism(
    { ply = ply, limbId = "hand_R", limb = ply._limbs.hand_R },
    { effects = { bandageSlowAmount = 15 } }, 1)
local entry = ply.organism.wszc_bandaged_shrapnel.hand_R
local initialLimb = ply._limbs.hand_R.infection == 25
    and ply._limbs.thorax.infection == 0 and ply._limbs.head.infection == 0
for _ = 1, 480 do WSZC.TickBandagedShrapnel(ply, ply.organism, 0.5) end
local torsoStage = entry.infectionAge == 240
    and ply._limbs.hand_R.infection == 89
    and ply._limbs.thorax.infection == 25 and ply._limbs.head.infection == 0
    and ply.organism.alive ~= false
for _ = 1, 360 do WSZC.TickBandagedShrapnel(ply, ply.organism, 0.5) end
local brainStage = entry.infectionAge == 420
    and ply._limbs.thorax.infection == 89
    and ply._limbs.head.infection == 25 and ply.organism.alive ~= false
for _ = 1, 359 do WSZC.TickBandagedShrapnel(ply, ply.organism, 0.5) end
local beforeFatal = entry.infectionAge == 599.5 and ply.organism.alive ~= false
WSZC.TickBandagedShrapnel(ply, ply.organism, 0.5)
local fatal = entry.infectionAge == 600 and entry.terminal == true
    and ply._limbs.head.infection == 99 and ply.organism.brain == 1
    and ply.organism.alive == false and ply.organism.needfake == true
    and ply._kills == 1 and ply:Alive() == false
return initialLimb, torsoStage, brainStage, beforeFatal and fatal, #notices == 0
''')
    check("R15 infection starts in the limb and reaches torso at 240 seconds", infection_timeline[0] and infection_timeline[1])
    check("R56 torso infection reaches the brain at 420 seconds", infection_timeline[2])
    check("R57 untreated covered shrapnel is fatal at 600 seconds, not before", infection_timeline[3])
    check("infection progresses without instructional player notifications", infection_timeline[4])

    infection_all_parts = lua.execute(r'''
local ids = { "head", "neck", "thorax", "abdomen", "pelvis",
    "arm_L", "forearm_L", "hand_L", "arm_R", "forearm_R", "hand_R",
    "thigh_L", "crus_L", "foot_L", "thigh_R", "crus_R", "foot_R" }
local errors = {}
for _, id in ipairs(ids) do
    local ply = MakePlayer()
    for _, part in ipairs(ids) do
        if not ply._limbs[part] then
            ply._limbs[part] = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100,
                infection = 0, infectionSpeed = 0 }
        end
    end
    local function fail(phase) errors[#errors + 1] = id .. ":" .. phase end
    if not WSZC.AddShrapnel(ply, id, 1, "shotgun") then fail("spawn") end
    WSZC.TickBandagedShrapnel(ply, ply.organism, 0.5)
    if (ply._limbs[id].infection or 0) ~= 0 then fail("uncovered") end
    local treated = WSZC.ApplyBandageToOrganism(
        { ply = ply, limbId = id, limb = ply._limbs[id] },
        { effects = { bandageSlowAmount = 15 } }, 1)
    local entry = ply.organism.wszc_bandaged_shrapnel and ply.organism.wszc_bandaged_shrapnel[id]
    if treated <= 0 or not entry or entry.infectionAge ~= 0
        or ply._limbs[id].infection ~= 25 or not WSZC.IsShrapnelBandaged(ply, id) then
        fail("bandage")
    else
        for _ = 1, 480 do WSZC.TickBandagedShrapnel(ply, ply.organism, 0.5) end
        if entry.infectionAge ~= 240 or (ply._limbs[id].infection or 0) < 25
            or (ply._limbs.thorax.infection or 0) < 25 then fail("torso") end
        for _ = 1, 360 do WSZC.TickBandagedShrapnel(ply, ply.organism, 0.5) end
        if entry.infectionAge ~= 420 or (ply._limbs[id].infection or 0) < 25
            or (ply._limbs.head.infection or 0) < 25 then fail("head") end
        if not WSZC.RemoveBandageForShrapnel(ply, id) then fail("unwrap") end
        ply._WSZCLimbsRef = ply._limbs
        ply._limbs[id].shrapnel = 0
        WSZC.SyncShrapnel(ply, ply.organism)
        WSZC.TickBandagedShrapnel(ply, ply.organism, 0.5)
        if (ply._limbs[id].infection or 0) < 25 or entry.infectionAge ~= 420.5 then
            fail("extraction")
        end
        WSZC.ApplyBandageToOrganism(
            { ply = ply, limbId = id, limb = ply._limbs[id] },
            { effects = { bandageSlowAmount = 15 } }, 1)
        if ply.organism.wszc_bandaged_shrapnel[id] ~= nil
            or ply.organism.wszc_infection ~= nil or (ply._limbs[id].infection or 0) ~= 0
            or (ply._limbs.thorax.infection or 0) ~= 0 or (ply._limbs.head.infection or 0) ~= 0 then
            fail("aftercare")
        end
    end
end
return table.concat(errors, ", ")
''')
    check("covered shrapnel infection starts, spreads and fully heals on all 17 body parts" +
          (": " + infection_all_parts if infection_all_parts else ""), not infection_all_parts)

    core_infection = lua.execute(r'''
local function patient()
    local ply = MakePlayer()
    ply._limbs.abdomen = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100, infection = 0 }
    ply._alive, ply._kills = true, 0
    ply.Alive = function(self) return self._alive end
    ply.Kill = function(self) self._alive = false; self._kills = self._kills + 1 end
    return ply
end
local terminal = true
for _, id in ipairs({ "head", "thorax", "abdomen" }) do
    local ply = patient()
    WSZC.AddShrapnel(ply, id, 1, "shotgun")
    WSZC.ApplyBandageToOrganism({ ply = ply, limbId = id, limb = ply._limbs[id] },
        { effects = { bandageSlowAmount = 15 } }, 1)
    local entry = ply.organism.wszc_bandaged_shrapnel[id]
    entry.infectionAge = 599.5
    WSZC.TickBandagedShrapnel(ply, ply.organism, 0.5)
    terminal = terminal and entry.terminal and ply._kills == 1 and ply.organism.brain == 1
        and ply._limbs.head.infection == 99 and ply._limbs[id].infection >= 25
end
local ply = patient()
for _, id in ipairs({ "thorax", "head" }) do
    WSZC.AddShrapnel(ply, id, 1, "shotgun")
    WSZC.ApplyBandageToOrganism({ ply = ply, limbId = id, limb = ply._limbs[id] },
        { effects = { bandageSlowAmount = 15 } }, 1)
end
local first = ply.organism.wszc_bandaged_shrapnel.thorax
local second = ply.organism.wszc_bandaged_shrapnel.head
first.infectionAge, second.infectionAge = 500, 1
WSZC.TickBandagedShrapnel(ply, ply.organism, 0)
local before = ply._limbs.head._wszcShrapnelInfectionOwner == first
WSZC.ClearShrapnelInfection(ply, ply.organism, "thorax")
WSZC.TickBandagedShrapnel(ply, ply.organism, 0)
local takeover = ply._limbs.head._wszcShrapnelInfectionOwner == second
    and ply._limbs.head.infection >= 25 and ply.organism.wszc_infection > 0
return terminal, before and takeover
''')
    check("untreated head, thorax and abdomen infections reach the native fatal outcome", core_infection[0])
    check("a remaining head infection takes over after an older source is cleared", core_infection[1])

    zero_aftercare = lua.execute(r'''
local ply = MakePlayer()
WSZC.AddShrapnel(ply, "hand_R", 1, "shotgun")
WSZC.ApplyBandageToOrganism(
    { ply = ply, limbId = "hand_R", limb = ply._limbs.hand_R },
    { effects = { bandageSlowAmount = 15 } }, 1)
ply._WSZCLimbsRef = ply._limbs
ply._limbs.hand_R.shrapnel = 0
WSZC.SyncShrapnel(ply, ply.organism)
for _, wound in pairs(ply.organism.wounds) do
    if wound.wszcShrapnelExtraction then wound[1] = 0 end
end
ply._limbs.hand_R.isBandaged = false
local treated = WSZC.ApplyBandageToOrganism(
    { ply = ply, limbId = "hand_R", limb = ply._limbs.hand_R },
    { effects = { bandageSlowAmount = 15 } }, 1)
return treated == 0
    and ply.organism.wszc_shrapnel_aftercare.hand_R == nil
    and ply.organism.wszc_bandaged_shrapnel.hand_R == nil
    and ply._limbs.hand_R.infection == 0
''')
    check("R58 final dressing completes aftercare even if extraction bleeding clotted", zero_aftercare)
    check("S16 disinfect/injection + ordinary bleed are filtered; fracture/dislocation and mechanics survive",
          "function WSZC.InstallDisinfectedIconFilter()" in layout_s
          and "HIDDEN_NATIVE_STATUS_KEYS" in layout_s
          and "disinfected = true, injection = true" in layout_s
          and "fracture = true, fracture2 = true" not in layout_s
          and "WSZC.IsHiddenNativeStatusIcon(mat, nativeIcons)" in layout_s
          and "WSZC_ARTERIAL_BLEEDING" in shared_s
          and 'icons.disinfected = Material("casunknown-images/icons/infection.png"' not in layout_s
          and "state.disinfectTime = 0" in organism_s
          and "state.infectionSpeed = 0" in organism_s)

    # Load the real exported H.ApplyItemToBody implementation as well.  The
    # physical SWEP reaches this through WB.SwepHeal, not through a direct call
    # to ApplyTourniquetToOrganism.
    lua.execute(r'''
AddCSLuaFile = function() end
HITGROUP_HEAD, HITGROUP_CHEST, HITGROUP_STOMACH = 1, 2, 3
HITGROUP_LEFTARM, HITGROUP_RIGHTARM = 4, 5
HITGROUP_LEFTLEG, HITGROUP_RIGHTLEG = 6, 7
HITGROUP_GEAR, HITGROUP_GENERIC = 10, 0
''')
    lua.execute(server_main_s)
    physical_tourniquet = lua.execute(r'''
local item = { max = 100, use = { apply = function() return false end } }
WoundSystem.Items = {
    Get = function(id) return id == "TOURNIQUET" and item or nil end,
    GetMax = function() return 100 end,
    CreateSlot = function(id, amount) return { type = "tool", toolName = id, durability = amount } end,
    LimbAllowed = function() return true end,
}
local function Patient()
    local ply = MakePlayer()
    ply._limbs.thigh_R = { shrapnel = 0, bleed = 26, pain = 20, muscle = 100, skin = 100 }
    ply.organism.rlegartery = 1
    ply.organism.bleed = 10
    ply.organism.wounds = {
        { 10, nil, nil, "ValveBiped.Bip01_R_Thigh", 0 },
        { 7, nil, nil, "ValveBiped.Bip01_L_Hand", 0 },
    }
    ply.organism.arterialwounds = {
        { 2, nil, nil, "ValveBiped.Bip01_R_Thigh", 0, nil, "rlegartery" },
    }
    return ply
end
local nativeCalls = 0
WoundSystem.UseMedicalItem = function() nativeCalls = nativeCalls + 1; return false, 0 end
local rejected = Patient()
local ok, used = WSZC.ApplyItemToBodyImpl(rejected, "TOURNIQUET", "thigh_R", 100)
local rejectStillHeals = ok == true and used == 100 and nativeCalls == 1
    and #rejected.organism.arterialwounds == 0 and rejected.organism.rlegartery == 0
    and #rejected.organism.wounds == 1 and rejected.organism.wounds[1][1] == 7
    and rejected._limbs.thigh_R.bleed == 0 and rejected._limbs.thigh_R.tourniqueted == true
    and math.abs(rejected.organism.bleed - 4.8) < 0.001

WoundSystem.UseMedicalItem = function() error("native C:U apply failure") end
local errored = Patient()
local ok2, used2 = WSZC.ApplyItemToBodyImpl(errored, "TOURNIQUET", "thigh_R", 100)
local errorStillHeals = ok2 == true and used2 == 100
    and #errored.organism.arterialwounds == 0 and #errored.organism.wounds == 1
    and math.abs(errored.organism.bleed - 4.8) < 0.001

WoundSystem.UseMedicalItem = function() nativeCalls = nativeCalls + 1; return true end
local empty = Patient()
empty.organism.wounds, empty.organism.arterialwounds = {}, {}
empty._limbs.thigh_R.bleed = 0
local beforeCalls = nativeCalls
local ok3, used3 = WSZC.ApplyItemToBodyImpl(empty, "TOURNIQUET", "thigh_R", 100)
local noFalseConsumption = ok3 == false and used3 == 0 and nativeCalls == beforeCalls
PhysicalDebug = { ok = ok, used = used, nativeCalls = nativeCalls,
    arterial = #rejected.organism.arterialwounds, artery = rejected.organism.rlegartery,
    wounds = #rejected.organism.wounds, leftSeverity = rejected.organism.wounds[1] and rejected.organism.wounds[1][1],
    limbBleed = rejected._limbs.thigh_R.bleed, marker = rejected._limbs.thigh_R.tourniqueted,
    orgBleed = rejected.organism.bleed, ok2 = ok2, used2 = used2,
    arterial2 = #errored.organism.arterialwounds, wounds2 = #errored.organism.wounds,
    orgBleed2 = errored.organism.bleed }
return rejectStillHeals, errorStillHeals, noFalseConsumption
''')
    check("R19 physical tourniquet heals real wounds when native C:U rejects", physical_tourniquet[0])
    check("R20 physical tourniquet survives native apply error without double mirror", physical_tourniquet[1])
    check("R21 tourniquet is not consumed when no real wound was treated", physical_tourniquet[2])
    if not all(physical_tourniquet):
        debug = lua.globals().PhysicalDebug
        print("PHYSICAL_DEBUG", {k: debug[k] for k in (
            "ok", "used", "nativeCalls", "arterial", "artery", "wounds", "leftSeverity",
            "limbBleed", "marker", "orgBleed", "ok2", "used2", "arterial2", "wounds2", "orgBleed2")})

    medical_wrapper = lua.execute(r'''
local patient = MakePlayer()
patient._limbs.forearm_R.bleed = 50
patient._limbs.thigh_R = { shrapnel = 0, bleed = 26, pain = 20, muscle = 100, skin = 100 }
patient.organism.rarmartery, patient.organism.rlegartery = 1, 1
patient.organism.bleed = 10
patient.organism.wounds = {}
patient.organism.arterialwounds = {
    { 5, nil, nil, "ValveBiped.Bip01_R_Forearm", 0, nil, "rarmartery" },
    { 2, nil, nil, "ValveBiped.Bip01_R_Thigh", 0, nil, "rlegartery" },
}
local bodyRemoved, bodyHidden, ragdollRemoved, ragdollHidden = false, false, false, false
patient.Remove = function() bodyRemoved = true end
patient.SetNoDraw = function() bodyHidden = true end
local ragdoll = {
    IsPlayer = function() return false end,
    IsRagdoll = function() return true end,
    organism = patient.organism,
    _net = {},
    TranslatePhysBoneToBone = function() return 12 end,
    GetBoneName = function() return "ValveBiped.Bip01_R_Thigh" end,
    SetNetVar = function(self, key, value) self._net[key] = value end,
    Remove = function() ragdollRemoved = true end,
    SetNoDraw = function() ragdollHidden = true end,
}
patient.FakeRagdoll = ragdoll
local previousOwnerResolver = hg.RagdollOwner
hg.RagdollOwner = function(ent)
    if ent == ragdoll then return patient end
    return previousOwnerResolver and previousOwnerResolver(ent) or nil
end
hg.GetCurrentCharacter = function(owner) return owner == patient and ragdoll or owner end
hg.eyeTrace = function(owner)
    if owner ~= patient then return nil end
    return { Entity = ragdoll, PhysicsBone = 7 }
end
local swep = {
    modeValues = { 1 },
    GetOwner = function() return patient end,
    GetClass = function() return "weapon_tourniquet" end,
}
-- Source-faithful native behaviour for this regression: self_use suppresses
-- AimedLimb and BestLimb picks the worse-bleeding arm.  The compatibility
-- wrapper must route the traced thigh BEFORE this call reaches treatment.
hg.WoundBridge.SwepHeal = function(swep, ent, mode, bone)
    local target = hg.RagdollOwner(ent) or ent
    local selfUse = ent == hg.GetCurrentCharacter(swep:GetOwner())
    local aimed = (not selfUse) and "thigh_R" or nil
    local bestLimb = "forearm_R"
    return WoundSystem.Health.ApplyItemToBody(target, "TOURNIQUET", bestLimb, 100)
end
WSZC.Ready, WSZC.H = true, WoundSystem.Health
WoundSystem.Health.ApplyItemToBody = WSZC.ApplyItemToBodyImpl
WSZC.WithVanillaContext = function(fn, ...) return fn(...) end
local installed = WSZC.InstallMedicalBridge()
local ok, used = hg.WoundBridge.SwepHeal(swep, ragdoll, 1)
local remaining = patient.organism.arterialwounds[1]
local marker = patient.tourniquets and patient.tourniquets[1]
local legTreated = installed and ok == true and used == 100
    and #patient.organism.arterialwounds == 1
    and remaining and remaining[7] == "rarmartery"
    and patient.organism.rlegartery == 0 and patient.organism.rarmartery == 1
    and patient._limbs.thigh_R.tourniqueted == true
    and patient._limbs.forearm_R.tourniqueted ~= true
    and marker and marker[3] == "ValveBiped.Bip01_R_Thigh"
    and marker[1] and type(marker[1].GetNegated) == "function"
    and ragdoll.tourniquets and ragdoll.tourniquets[1][3] == "ValveBiped.Bip01_R_Thigh"
local bodyPreserved = not (bodyRemoved or bodyHidden or ragdollRemoved or ragdollHidden)
    and WSZC.TourniquetLimbOverride == nil
MedicalDebug = { installed = installed, ok = ok, used = used,
    remaining = remaining and remaining[7], rleg = patient.organism.rlegartery,
    rarm = patient.organism.rarmartery, marker = marker and marker[3],
    thigh = patient._limbs.thigh_R.tourniqueted, arm = patient._limbs.forearm_R.tourniqueted }
return legTreated, bodyPreserved
''')
    check("R32 traced self-use tourniquet treats and marks the leg through WB.SwepHeal", medical_wrapper[0])
    check("R33 tourniquet path never removes/hides player or FakeRagdoll and cleans routing", medical_wrapper[1])
    if not all(medical_wrapper):
        debug = lua.globals().MedicalDebug
        print("MEDICAL_DEBUG", {k: debug[k] for k in (
            "installed", "ok", "used", "remaining", "rleg", "rarm", "marker", "thigh", "arm")})

    native_wrapper = lua.execute(r'''
local ply = MakePlayer()
local ragdoll = { IsPlayer = function() return false end, organism = ply.organism }
ply.FakeRagdoll = ragdoll
nestedDamageCalls = 0
hook.Add("EntityTakeDamage", "homigrad-damage", function(ent, dmginfo)
    if ent.IsPlayer and ent:IsPlayer() and IsValid(ent.FakeRagdoll) then
        -- Real ZCity forwards the same DamageInfo to the fake ragdoll.
        return hook._t.EntityTakeDamage["homigrad-damage"](ent.FakeRagdoll, dmginfo)
    end
    nestedDamageCalls = nestedDamageCalls + 1
    local owner = ent.organism.owner
    owner.organism.dmgstack = { [HITGROUP_RIGHTARM] = { 30, CurTime() } }
    owner.HitBones = { ["ValveBiped.Bip01_R_Hand"] = CurTime() + 30 }
    return true -- this can suppress the engine's public post hook
end)
WSZC.Ready, WSZC.H = true, WoundSystem.Health
WSZC.WithVanillaContext = function(fn, ...) return fn(...) end
local installed = WSZC.InstallOrganismMode()
local dmg = MakeDamage("weapon_spas12", 8, -1, 0)
local blocked = hook._t.EntityTakeDamage["homigrad-damage"](ply, dmg)
local afterNative = ply._limbs.forearm_R.shrapnel
hook._t.PostEntityTakeDamage.WSZC_AuthorityDamagePost(ply, dmg, false)
return installed and blocked == true and nestedDamageCalls == 1
    and afterNative == 3 and ply._limbs.forearm_R.shrapnel == 3
    and ply.organism.wszc_shrapnel_sources.forearm_R.shotgun == 3
''')
    check("R27 player->FakeRagdoll->native hook injects once even when Post is suppressed", native_wrapper)

    amputation = lua.execute(r'''
if type(WSZC.SyncOrganismShadow) ~= "function" then return false, false end
WoundSystem.Statuses = { Stored = {}, Order = {} }
WoundSystem.Statuses.Register = function(id, data)
    WoundSystem.Statuses.Stored[id] = data
    table.insert(WoundSystem.Statuses.Order, id)
    table.sort(WoundSystem.Statuses.Order, function(a, b)
        return WoundSystem.Statuses.Stored[a].order < WoundSystem.Statuses.Stored[b].order
    end)
    return data
end
local ply = MakePlayer()
for _, id in ipairs({ "arm_R", "hand_R", "arm_L", "forearm_L", "hand_L",
    "thigh_R", "crus_R", "foot_R", "thigh_L", "crus_L", "foot_L" }) do
    ply._limbs[id] = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100,
        customStatuses = {} }
end
ply._limbs.arm_R.customStatuses = {}
ply._limbs.forearm_R.customStatuses = {}
ply._limbs.hand_R.customStatuses = {}
ply.organism.rarmamputated = true
ply.organism.arterialwounds = {
    { 10, Vector(1, 2, 3), Angle(4, 5, 6), "ValveBiped.Bip01_R_UpperArm", 0,
      Vector(-100, 0, 0), "rarmartery" },
}
local originalArtery = ply.organism.arterialwounds[1]
WSZC.SyncOrganismShadow(ply, ply.organism)
local anatomy = ply._limbs.arm_R.dismembered == false
    and ply._limbs.forearm_R.dismembered == true
    and ply._limbs.hand_R.dismembered == true
    and ply._limbs.thigh_R.dismembered == false
local independent = ply.organism.rarmamputated == true
    and ply.organism.arterialwounds[1] == originalArtery
    and originalArtery[1] == 10 and ply._limbs.arm_R.bleed == 30
    and ply._limbs.arm_R.customStatuses.WSZC_AMPUTATION == true
    and ply._limbs.forearm_R.customStatuses.WSZC_AMPUTATION == nil
return anatomy, independent
''')
    check("R35 ZCity forearm amputation keeps the upper-arm stump, not a whole-arm deletion", amputation[0])
    check("R36 amputation status and arterial wound remain independent in shadow/UI", amputation[1])

    amputation_priority = lua.execute(r'''
if type(WSZC.BestTourniquetLimb) ~= "function" then return false, false, false end
local ply = MakePlayer()
for _, id in ipairs({ "arm_R", "forearm_R", "hand_R", "thigh_L", "crus_L", "foot_L" }) do
    ply._limbs[id] = { bleed = 0, dismembered = false, tourniqueted = false }
end
ply.organism.rarmamputated = true
ply.organism.arterialwounds = {
    { 5, Vector(), Angle(), "ValveBiped.Bip01_R_UpperArm", 0, Vector(), "rarmartery" },
    { 40, Vector(), Angle(), "ValveBiped.Bip01_L_Thigh", 0, Vector(), "llegartery" },
}
ply._limbs.arm_R.bleed = 15
ply._limbs.thigh_L.bleed = 100
local selected = WSZC.BestTourniquetLimb(ply, { item = "TOURNIQUET", pick = "extremity" })
local noFakeBleed = ply._limbs.arm_R.bleed == 15 and ply._limbs.thigh_L.bleed == 100
WSZC.TourniquetLimbOverride = { ply = ply, limbId = "forearm_R" }
local routed = WSZC.BestTourniquetLimb(ply, { item = "TOURNIQUET", pick = "extremity" })
WSZC.TourniquetLimbOverride = nil
ply.organism.arterialwounds[1][1] = 0
ply._limbs.arm_R.bleed = 0
local ordinaryFallback = WSZC.BestTourniquetLimb(ply, { item = "TOURNIQUET", pick = "extremity" })
return selected == "arm_R" and noFakeBleed, routed == "arm_R", ordinaryFallback == "thigh_L"
''')
    check("R37 a bleeding amputation stump outranks a heavier ordinary artery", amputation_priority[0])
    check("R38 aimed distal bone on an amputated arm resolves to its proximal stump", amputation_priority[1])
    check("R39 without stump bleeding the tourniquet falls back to the real artery", amputation_priority[2])

    fakeup_snapshot = lua.execute(r'''
local ply = MakePlayer()
ply.organism.fake = true
ply.organism.rarmamputated = true
ply.organism.llegamputated = true
ply.organism.wounds = { { 7, Vector(1, 2, 3), Angle(), "ValveBiped.Bip01_R_UpperArm", 0 } }
ply.organism.arterialwounds = {
    { 10, Vector(4, 5, 6), Angle(), "ValveBiped.Bip01_R_UpperArm", 0, Vector(), "rarmartery" },
}
ply.organism.blood = 2345
ply.organism.consciousness = 0.71
ply.organism.brokenribs = 3
ply.organism.customNativeOrgan = { nested = { value = 42 } }
OverrideSpawn = true -- native hg.FakeUp sets this around its internal ply:Spawn()
hg.organism.Clear(ply.organism)
OverrideSpawn = nil
local preserved = ply.organism.rarmamputated == true
    and ply.organism.llegamputated == true
    and ply.organism.blood == 2345 and ply.organism.consciousness == 0.71
    and #ply.organism.wounds == 1 and ply.organism.wounds[1][1] == 7
    and #ply.organism.arterialwounds == 1 and ply.organism.arterialwounds[1][1] == 10
    and ply.organism.customNativeOrgan.nested.value == 42
    and ply.organism.brokenribs == 3
    and ply.organism.owner == ply
ply.organism.rarmamputated = true
hg.WoundBridge.ResetOrganism(ply)
local explicitStillClears = ply.organism.rarmamputated ~= true
    and ply.organism.llegamputated ~= true and #ply.organism.arterialwounds == 0
return preserved, explicitStillClears
''')
    check("R40 FakeUp spawn retains native wounds, arteries, amputations and custom organs", fakeup_snapshot[0])
    check("R41 explicit organism reset still clears every amputation and artery", fakeup_snapshot[1])

    rib_reset = lua.execute(r'''
local ply = MakePlayer()
ply._limbs.thorax = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100 }
ply.organism.chest = 1
ply.organism.brokenribs = 3
WSZC.SyncOrganismShadow(ply, ply.organism)
local reproduced = WSZC.Fractured(ply.organism, "thorax", { dmg = "chest" })
    and ply._limbs.thorax.broken == true
assert(hg.WoundBridge.ResetOrganism(ply))
-- Let the normal 4 Hz shadow pass run after reset.  It must not resurrect the
-- icon from native Org Clear's stale brokenribs field.
ply._WSZCShadowNext = 0
WSZC.SyncOrganismShadow(ply, ply.organism)
local cleared = (tonumber(ply.organism.chest) or 0) == 0
    and (tonumber(ply.organism.brokenribs) or 0) == 0
    and not WSZC.Fractured(ply.organism, "thorax", { dmg = "chest" })
    and ply._limbs.thorax.broken == false
return reproduced, cleared
''')
    check("R51 explicit reset clears native stale brokenribs and the thorax fracture icon", rib_reset[0] and rib_reset[1])

    respawn_ribs = lua.execute(r'''
local ply = MakePlayer()
ply.organism.chest = 1
ply.organism.brokenribs = 3
hg.organism.Clear(ply.organism) -- genuine standing spawn, not FakeUp/ragdoll
return (tonumber(ply.organism.chest) or 0) == 0
    and (tonumber(ply.organism.brokenribs) or 0) == 0
''')
    check("R52 genuine organism spawn clear also removes stale brokenribs", respawn_ribs)

    context_client = LuaRuntime(unpack_returned_tuples=True)
    context_client.execute(r'''
CLIENT = true; SERVER = false
WSZC = {}
IsValid = function(v) return v ~= nil and v ~= false end
local ply = { Alive = function() return true end, GetNWBool = function() return false end }
LocalPlayer = function() return ply end
function SetContextPlayer(value) ply = value end
''')
    context_fn = layout_s.split('function WSZC.MinigameContextOK()', 1)[1].split('--- Only OUR', 1)[0]
    context_client.execute('function WSZC.MinigameContextOK()' + context_fn)
    ragdoll_context = context_client.execute(r'''
local conscious = { Alive = function() return true end, GetNWBool = function() return false end,
    FakeRagdoll = {}, organism = { fake = true, needfake = true, consciousness = 1 } }
SetContextPlayer(conscious)
local consciousAllowed = WSZC.MinigameContextOK()
conscious.organism.otrub = true
local otrubClosed = not WSZC.MinigameContextOK()
conscious.organism.otrub = false
conscious.organism.consciousness = 0.39
local lowConsciousnessClosed = not WSZC.MinigameContextOK()
return consciousAllowed, otrubClosed and lowConsciousnessClosed
''')
    check("R42 client keeps minigames alive in a conscious fake/ragdoll", ragdoll_context[0])
    check("R43 client still blocks otrub and consciousness below 0.4", ragdoll_context[1])

    client = LuaRuntime(unpack_returned_tuples=True)
    client.execute(r'''
CLIENT = true; SERVER = false
CurTime = function() return 100 end
IsValid = function(v) return v ~= nil and v ~= false end
include = function() end
timer = { Simple = function() end, Create = function() end, Remove = function() end }
hook = { _t = {}, GetTable = function() return hook._t end,
         Add = function(e, n, f) hook._t[e] = hook._t[e] or {}; hook._t[e][n] = f end,
         Remove = function() end, Call = function() end }
net = { _receivers = {}, Receive = function(name, fn) net._receivers[name] = fn end,
        ReadString = function() return net._reason or "unconscious" end,
        Start = function() end, SendToServer = function() end, WriteString = function() end,
        WriteBool = function() end, WriteUInt = function() end, WriteFloat = function() end }
gui = { EnableScreenClicker = function() end, MousePos = function() return 0, 0 end }
input = { IsMouseDown = function() return false end, IsKeyDown = function() return false end }
vgui = { CursorVisible = function() return true end,
         GetWorldPanel = function() return { GetCursor = function() return "arrow" end, SetCursor = function() end } end }
MOUSE_LEFT, MOUSE_RIGHT, KEY_ESCAPE = 107, 108, 70
WoundSystemInventorySlots, WoundSystemDragState, WoundSystemWorldDrag = {}, {}, {}
WoundSystem = { HealthGUI = {}, Client = {}, CloseHealthHUD = function() WoundSystemHealthHUDOpen = false end }
WoundSystemHealthHUDOpen = true
WoundSystemDislocationMinigame = { active = true }
WoundSystemShrapnelMinigame = { active = true }
WoundSystemFractureMinigame = { active = true }
WoundSystemAEDMinigame = { active = true }
WoundSystemAmputationMinigame = { active = true }
WoundSystemHealthHUDMinigame = { active = true }
WSZC = { MinigameContextOK = function() return true end,
         ForceReleaseMinigameCursor = function() WSZC.released = true end,
         RestoreMinigameCursor = function() end,
         NativeMinigameActive = function() return false end }
''')
    client.execute(client_mg_s)
    cleanup = client.execute(r'''
local requested = 0
local removed = false
WSZCBandageMinigame = { active = true, inputSeq = 0, IsActive = function() return true end,
    RequestClose = function() requested = requested + 1 end,
    overlay = { Remove = function() removed = true end } }
WSZCSyringeMinigame = { active = false }
net._receivers["WSZC_MinigameForceClose"]()
local closed = WSZCBandageMinigame.active == false and requested == 0 and removed
    and WoundSystemDislocationMinigame.active == false
    and WoundSystemShrapnelMinigame.active == false
    and WoundSystemHealthHUDOpen == false and WSZC.released == true
WSZCBandageMinigame.active = true
WoundSystemHealthHUDOpen = true
net._reason = "death"
WSZC.ClearAllMinigameState(true)
return closed, requested == 1 and WSZCBandageMinigame.active == false
''')
    check("R08 force-close removes native/WSZC UI without a duplicate request", cleanup[0])
    check("R09 death cleanup still requests authoritative closure", cleanup[1])

    spawn_transition = client.execute(r'''
WSZCBandageMinigame.active = true
WoundSystemHealthHUDOpen = true
WSZC.MinigameContextOK = function() return true end
hook._t.PlayerSpawn.WSZC_MinigameSpawnCleanup({})
local consciousSpawnKept = WSZCBandageMinigame.active == true and WoundSystemHealthHUDOpen == true
WSZCBandageMinigame.active = true
WSZC.MinigameContextOK = function() return false end
hook._t.PlayerSpawn.WSZC_MinigameSpawnCleanup({})
local deadSpawnClosed = WSZCBandageMinigame.active == false
return consciousSpawnKept, deadSpawnClosed
''')
    check("R44 FakeUp PlayerSpawn does not destroy an active conscious minigame", spawn_transition[0])
    check("R45 PlayerSpawn still cleans a dead/incapacitated client context", spawn_transition[1])

    server = LuaRuntime(unpack_returned_tuples=True)
    server.execute(r'''
SERVER = true; CLIENT = false
WSZC = { Ready = true, BridgeEnabled = function() return true end,
         Bridged = function() return true end }
CreateConVar = function(name, def) return { GetBool = function() return def ~= "0" end } end
GetConVar = function() return nil end
FindMetaTable = function() return nil end
util = { AddNetworkString = function() end }
net = { sent = {}, Receive = function() end, Start = function(name) net.current = name end,
        Send = function(ply) table.insert(net.sent, net.current) end,
        WriteString = function() end, WriteBool = function() end,
        WriteUInt = function() end, WriteFloat = function() end }
hook = { _t = {}, Add = function(e, n, f) hook._t[e] = hook._t[e] or {}; hook._t[e][n] = f end,
         Remove = function() end }
timer = { Simple = function() end, Create = function() end, Remove = function() end }
include = function() end
IsValid = function(v) return v ~= nil and v ~= false end
CurTime = function() return 100 end
player = { GetAll = function() return {} end }
''')
    server.execute(server_mg_s)
    native_close = server.execute(r'''
local medic = { organism = {}, IsPlayer = function() return true end,
    Alive = function() return true end, GetNWBool = function() return false end }
local patient = { organism = { otrub = true }, Alive = function() return true end }
local patientDoesNotIncapacitateMedic = not WSZC.PlayerMinigameIncapacitated(medic)
    and WSZC.PlayerMinigameIncapacitated(patient)
medic.organism.otrub = true
local medicIncapacitated = WSZC.PlayerMinigameIncapacitated(medic)
local closed = {}
WSZC.CUSessions = { Shrapnel = {}, Dislocation = {}, Aed = {}, Bandage = {}, Syringe = {} }
for kind, sessions in pairs(WSZC.CUSessions) do sessions[medic] = { id = 1 } end
local function close(kind)
    return function(ply, reason)
        closed[kind] = reason
        WSZC.CUSessions[kind][ply] = nil
    end
end
WSZC.CUCloseShrapnelSession = close("Shrapnel")
WSZC.CUCloseDislocationSession = close("Dislocation")
WSZC.CUCloseAedSession = close("Aed")
WSZC.CUCloseBandageSession = close("Bandage")
WSZC.CUCloseSyringeSession = close("Syringe")
WSZC.MinigameSessions[medic] = { kind = "bandage", id = 1, deferredUsed = 0, startAmount = 0 }
hook._t["HG_OnOtrub"]["WSZC_MinigameUnconscious"](medic)
local allClosed = WSZC.MinigameSessions[medic] == nil
for _, kind in ipairs({ "Shrapnel", "Dislocation", "Aed", "Bandage", "Syringe" }) do
    allClosed = allClosed and closed[kind] == "unconscious" and WSZC.CUSessions[kind][medic] == nil
end
local forced = false
for _, name in ipairs(net.sent) do if name == "WSZC_MinigameForceClose" then forced = true end end
return patientDoesNotIncapacitateMedic and medicIncapacitated, allClosed and forced
''')
    check("R10 only the operator's incapacity controls the session", native_close[0])
    check("R11 unconscious closes every native session plus WSZC", native_close[1])

    ragdoll_server = server.execute(r'''
local medic = { organism = { fake = true, needfake = true, consciousness = 1 },
    FakeRagdoll = {}, IsPlayer = function() return true end,
    Alive = function() return true end, GetNWBool = function() return false end }
local consciousAllowed = not WSZC.PlayerMinigameIncapacitated(medic)
WSZC.MinigameSessions[medic] = { kind = "bandage", id = 11, deferredUsed = 0, startAmount = 0 }
OverrideSpawn = true -- native FakeUp's internal ply:Spawn(), not a real respawn
hook._t.PlayerSpawn.WSZC_MinigameSpawn(medic)
OverrideSpawn = nil
local spawnKept = WSZC.MinigameSessions[medic] ~= nil
hook._t.Fake.WSZC_MinigameUnconscious(medic)
local fakeKept = WSZC.MinigameSessions[medic] ~= nil
medic.organism.otrub = true
hook._t.Fake.WSZC_MinigameUnconscious(medic)
local otrubClosed = WSZC.MinigameSessions[medic] == nil
return consciousAllowed and spawnKept and fakeKept, otrubClosed
''')
    check("R46 server PlayerSpawn/Fake preserve a conscious operator's session", ragdoll_server[0])
    check("R47 Fake still force-closes when that operator is actually in otrub", ragdoll_server[1])

    genuine_respawn = server.execute(r'''
local medic = { organism = { consciousness = 1 }, IsPlayer = function() return true end,
    Alive = function() return true end, GetNWBool = function() return false end }
WSZC.MinigameSessions[medic] = { kind = "bandage", id = 12, deferredUsed = 0, startAmount = 0 }
OverrideSpawn = nil
hook._t.PlayerSpawn.WSZC_MinigameSpawn(medic)
local closed = WSZC.MinigameSessions[medic] == nil
local forced = false
for _, name in ipairs(net.sent) do if name == "WSZC_MinigameForceClose" then forced = true end end
return closed and forced
''')
    check("R48 genuine PlayerSpawn still force-closes a missed-death client/session", genuine_respawn)

    selector_upvalue = lua.execute(r'''
local ply = MakePlayer()
ply._limbs.arm_R = { bleed = 15, dismembered = false, tourniqueted = false }
ply._limbs.thigh_L = { bleed = 100, dismembered = false, tourniqueted = false }
ply.organism.rarmamputated = true
ply.organism.arterialwounds = {
    { 5, Vector(), Angle(), "ValveBiped.Bip01_R_UpperArm", 0, Vector(), "rarmartery" },
    { 40, Vector(), Angle(), "ValveBiped.Bip01_L_Thigh", 0, Vector(), "llegartery" },
}
-- A dressed hand still has a REAL ordinary wound; the much larger thigh bleed
-- is artery-only shadow presentation and must not steal the bandage target.
ply._limbs.hand_R = { bleed = 25, isBandaged = true, dismembered = false }
ply.organism.wounds = {
    { 4, Vector(), Angle(), "ValveBiped.Bip01_R_Hand", 0 },
}
local BestLimb = function() return "native_bandage_site" end
local NativeSwepHeal = function(target, spec, preferred)
    return BestLimb(target, spec, preferred)
end
local patched = WSZC.PatchTourniquetBestLimb(NativeSwepHeal)
local tourniquet = NativeSwepHeal(ply, { kind = "apply", item = "TOURNIQUET", pick = "extremity" })
local bandage = NativeSwepHeal(ply, { kind = "bandage", item = "GAUZE" }, "hand_R")
local arteryOnly = NativeSwepHeal(ply, { kind = "bandage", item = "GAUZE" }, "thigh_L")
return patched and tourniquet == "arm_R" and bandage == "hand_R"
    and arteryOnly == "hand_R" -- never the phantom 100-bleed artery-only thigh
''')
    check("R49 installed BestLimb uses real tourniquet/bandage targets despite stale shadow flags", selector_upvalue)

    selector_no_debug = lua.execute(r'''
local ply = MakePlayer()
ply._limbs.arm_R = { bleed = 15, dismembered = false, tourniqueted = false }
ply.organism.rarmamputated = true
ply.organism.arterialwounds = {
    { 5, Vector(), Angle(), "ValveBiped.Bip01_R_UpperArm", 0, Vector(), "rarmartery" },
}
local BestLimb = function() return "native_bandage_site" end
local NativeSwepHeal = function(target, spec, preferred)
    return BestLimb(target, spec, preferred)
end
local wb = hg.WoundBridge
local saved = { wb._WSZCEmbedded, wb._WSZCBridgeRefs, wb._WSZCReplaceBestLimb, wb.SwepHeal }
wb._WSZCEmbedded = true
wb._WSZCBridgeRefs = { version = 1, BestLimb = BestLimb }
wb.SwepHeal = NativeSwepHeal
local replaced = false
wb._WSZCReplaceBestLimb = function(swepHeal, replacement)
    if swepHeal ~= NativeSwepHeal or type(replacement) ~= "function" then return false end
    BestLimb = replacement
    replaced = true
    return true
end
local previousDebug = debug
debug = nil
local ok, result = pcall(function()
    local patched = WSZC.PatchTourniquetBestLimb(NativeSwepHeal)
    local tourniquet = NativeSwepHeal(ply, { kind = "apply", item = "TOURNIQUET", pick = "extremity" })
    local syringe = NativeSwepHeal(ply, { kind = "syringe", item = "MORPHINE" })
    return patched and replaced and tourniquet == "arm_R" and syringe == "native_bandage_site"
end)
debug = previousDebug
wb._WSZCEmbedded, wb._WSZCBridgeRefs, wb._WSZCReplaceBestLimb, wb.SwepHeal = saved[1], saved[2], saved[3], saved[4]
return ok and result == true
''')
    check("R89 embedded BestLimb selector works without debug upvalues", selector_no_debug)

    status_client = LuaRuntime(unpack_returned_tuples=True)
    status_client.execute(r'''
CLIENT = true; SERVER = false
WSZC = {}
WoundSystem = {}
string.Trim = function(value) return value end
''')
    status_client.execute(limb_statuses_s)
    status_registration = shared_s.split('WSZC.AMPUTATION_STATUS_ID =', 1)[1].split('-- Short-lived context flag:', 1)[0]
    status_client.execute('WSZC.AMPUTATION_STATUS_ID =' + status_registration)
    native_status_order = status_client.execute(r'''
WoundSystem.Statuses.Register("TOURNIQUET", { title = "Tourniquet", order = 30, type = "number" })
assert(WSZC.InstallAmputationStatus())
local state = { customStatuses = { TOURNIQUET = 4, WSZC_AMPUTATION = true } }
local active = WoundSystem.Statuses.GetActive(state)
return #active == 2 and active[1].id == "WSZC_AMPUTATION" and active[2].id == "TOURNIQUET"
    and active[1].data.icon == ""
''')
    check("R50 amputation stays tracked without an extra WoundView icon", native_status_order)

    internal_registration = shared_s.split('WSZC.INTERNAL_BLEEDING_STATUS_ID =', 1)[1].split('-- Short-lived context flag:', 1)[0]
    status_client.execute('WSZC.INTERNAL_BLEEDING_STATUS_ID =' + internal_registration)
    native_internal_icon = status_client.execute(r'''
assert(WSZC.InstallInternalBleedingStatus())
local state = { customStatuses = { WSZC_INTERNAL_BLEEDING = 6.25 } }
local active = WoundSystem.Statuses.GetActive(state)
local ok = #active == 1 and active[1].id == "WSZC_INTERNAL_BLEEDING"
    and active[1].data.icon == "casunknown-images/moodles/internalbleed_red.png"
    and active[1].data.type == "number" and active[1].data.order == -9000
state.customStatuses.WSZC_INTERNAL_BLEEDING = 0
return ok and #WoundSystem.Statuses.GetActive(state) == 0
''')
    check("R43 native client status resolves the red internal-bleed icon only above zero", native_internal_icon)

    native_arterial_icon = status_client.execute(r'''
assert(WSZC.InstallArterialBleedingStatus())
local state = { customStatuses = { WSZC_ARTERIAL_BLEEDING = 12 } }
local active = WoundSystem.Statuses.GetActive(state)
local ok = #active == 1 and active[1].id == "WSZC_ARTERIAL_BLEEDING"
    and active[1].data.icon == "wszc/unitmenu/status/arterial.png"
    and active[1].data.color[1] == 255 and active[1].data.color[2] == 255
    and active[1].data.type == "number" and active[1].data.order == -8000
state.customStatuses.WSZC_ARTERIAL_BLEEDING = 0
return ok and #WoundSystem.Statuses.GetActive(state) == 0
''')
    check("R96 arterial marker uses its own red blood material and disappears at zero", native_arterial_icon)

    refreshed_status = status_client.execute(r'''
local statuses = WoundSystem.Statuses.Stored
statuses.WSZC_AMPUTATION.icon = "casunknown-images/moodles/amputation.png"
statuses.WSZC_ARTERIAL_BLEEDING.icon = "casunknown-images/icons/strongbleed.png"
assert(WSZC.InstallAmputationStatus() and WSZC.InstallArterialBleedingStatus())
return statuses.WSZC_AMPUTATION.icon == ""
    and statuses.WSZC_ARTERIAL_BLEEDING.icon == "wszc/unitmenu/status/arterial.png"
    and statuses.WSZC_ARTERIAL_BLEEDING.color[2] == 255
''')
    check("R113 reload removes the unwanted icon and refreshes the distinct arterial marker", refreshed_status)
    check("R114 distinct arterial icon is bundled", (CONN / "materials/wszc/unitmenu/status/arterial.png").is_file())

    neck_state = lua.execute(r'''
local ply = MakePlayer()
local h = WoundSystem.Health
h.Const = {
    ParentLimb = {},
    LimbToBones = { head = { "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Neck1" } },
    RagdollDamageBones = {
        { limb = "head", patterns = { "head", "neck", "jaw" } },
        { limb = "thorax", patterns = { "spine2" } },
    },
}
h.InitPlayer = function(target)
    target._limbs = {
        head = { skin = 100, muscle = 100, broken = true, boneHealTimer = 15,
            dislocated = false, dislocationTimer = 0, shrapnel = 0, bleed = 0, pain = 0 },
    }
end
assert(WSZC.InstallNeckState(h))
h.InitPlayer(ply) -- real exported wrapper: native reset, then added neck/pelvis states
local firstLife = ply._limbs.neck ~= nil
    and hook._t.PlayerSpawn.WSZC_NeckFirstLifeSync ~= nil
    and h.Const.ParentLimb.neck == "head"
    and h.Const.RagdollDamageBones[1].limb == "neck"
    and #h.Const.LimbToBones.head == 1

ply.organism.skull, ply.organism.spine3 = 1, 0.7
ply.organism.wounds = {
    { 2, Vector(), Angle(), "ValveBiped.Bip01_Neck1", 0 },
    { 3, Vector(), Angle(), "ValveBiped.Bip01_Head1", 0 },
}
ply.organism.arterialwounds = {
    { 4, Vector(), Angle(), "ValveBiped.Bip01_Neck1", 0, Vector(), "neckartery" },
}
assert(WSZC.RestoreBones(ply))
WSZC.SyncOrganismShadow(ply, ply.organism)
local separated = ply._limbs.neck.broken == true and ply._limbs.head.broken == false
    and math.abs(ply._limbs.neck.muscle - 30) < 0.001 and ply._limbs.head.muscle == 0
    and ply._limbs.neck.boneHealTimer == 70 and ply._limbs.head.boneHealTimer == 0
local bleed = WSZC.LimbBleedMap(ply, ply.organism)
local routed = bleed.neck == 16 and bleed.head == 6

-- Skull and cervical spine are independent; C:U muscle treatments cannot
-- silently fix the cervical spine in place of ZCity's native regeneration.
ply._limbs.head.muscle = 0
local beforeHead = WSZC.SnapshotMedical(ply, "head")
ply._limbs.head.muscle = 100
WSZC.ApplyMedicalDelta(ply, "head", beforeHead)
local headOnly = math.abs(ply.organism.skull) < 0.0001 and ply.organism.spine3 == 0.7
ply._limbs.neck.muscle = 0
local beforeNeck = WSZC.SnapshotMedical(ply, "neck")
ply._limbs.neck.muscle = 100
WSZC.ApplyMedicalDelta(ply, "neck", beforeNeck)
local spineProtected = ply.organism.spine3 == 0.7
return firstLife, separated, routed, headOnly and spineProtected
''')
    check("R65 first-life InitPlayer creates and synchronizes one real neck state", neck_state[0])
    check("R66 cervical fracture uses spine3; skull muscle damage stays on head", neck_state[1])
    check("R67 Neck1 and neckartery route separately from Head1 wounds", neck_state[2])
    check("R68 head treatment addresses skull and never substitutes for spine treatment", neck_state[3])

    pelvis_state = lua.execute(r'''
local ply = MakePlayer()
local h = WoundSystem.Health
h.Const = {
    ParentLimb = {}, LimbToBones = {},
    ConnectedLimbs = { thorax = { "head", "abdomen" }, abdomen = { "thorax", "thigh_R", "thigh_L" } },
    NonDismemberableCoreLimbs = { abdomen = true, thorax = true },
    RagdollDamageBones = {
        { limb = "thorax", patterns = { "spine2" } },
        { limb = "abdomen", patterns = { "pelvis", "spine", "spine1" } },
    },
}
h.InitPlayer = function(target)
    target._limbs = {
        head = { skin = 100, muscle = 100, shrapnel = 0, bleed = 0, pain = 0 },
        thorax = { skin = 100, muscle = 100, shrapnel = 0, bleed = 0, pain = 0 },
        abdomen = { skin = 12, muscle = 34, shrapnel = 0, bleed = 0, pain = 0,
            customStatuses = { OLD = true } },
    }
end
assert(WSZC.InstallNeckState(h))
h.InitPlayer(ply)
local pelvis = ply._limbs.pelvis
local firstLife = pelvis ~= nil and ply._limbs.neck ~= nil
    and pelvis.skin == 100 and pelvis.muscle == 100 and pelvis.customStatuses.OLD == nil
    and h.Const.ParentLimb.pelvis == "abdomen"
    and h.Const.ParentLimb.thigh_R == "pelvis"
    and h.Const.NonDismemberableCoreLimbs.pelvis == true
    and h.Const.ConnectedLimbs.abdomen[2] == "pelvis"

ply.organism.pelvis = 0.4
ply.organism.wounds = {
    { 2, Vector(), Angle(), "ValveBiped.Bip01_Spine1", 0 },
    { 3, Vector(), Angle(), "ValveBiped.Bip01_Pelvis", 0 },
    { 5, Vector(), Angle(), "ValveBiped.Bip01_Spine2", 0 },
}
WSZC.SyncOrganismShadow(ply, ply.organism)
local bleed = WSZC.LimbBleedMap(ply, ply.organism)
local routed = bleed.abdomen == 4 and bleed.pelvis == 6 and bleed.thorax == 10
    and ply._limbs.abdomen.bleed == 4 and ply._limbs.pelvis.bleed == 6

local treated, before, after = WSZC.ApplyBandageToOrganism({
    ply = ply, limbId = "pelvis", limb = ply._limbs.pelvis,
}, { effects = { bandageSlowAmount = 2 } }, 1)
local abdomenWound, thoraxWound
for _, wound in pairs(ply.organism.wounds) do
    if wound[4] == "ValveBiped.Bip01_Spine1" then abdomenWound = wound[1] end
    if wound[4] == "ValveBiped.Bip01_Spine2" then thoraxWound = wound[1] end
end
local treatmentSeparated = before == 6 and after == 0 and treated == 6
    and abdomenWound == 2 and thoraxWound == 5

ply._limbs.pelvis.muscle = 60
local beforeMedical = WSZC.SnapshotMedical(ply, "pelvis")
ply._limbs.pelvis.muscle = 80
WSZC.ApplyMedicalDelta(ply, "pelvis", beforeMedical)
local oneDelta = math.abs(ply.organism.pelvis - 0.2) < 0.0001
return firstLife, routed, treatmentSeparated, oneDelta
''')
    check("R69 first-life pelvis is fresh, native and parented between abdomen/thighs", pelvis_state[0])
    check("R70 Spine1/Pelvis/Spine2 wounds route to abdomen/pelvis/thorax exactly", pelvis_state[1])
    check("R71 pelvis bandage treats only pelvis, never abdomen or thorax wounds", pelvis_state[2])
    check("R72 pelvis muscle treatment applies ONE org.pelvis delta", pelvis_state[3])

    # Load the real native status registry and the shared connector definition
    # into the server runtime, then exercise the full organism -> shadow path.
    lua.execute('string.Trim = function(value) return value end')
    lua.execute(limb_statuses_s)
    lua.execute('WSZC.INTERNAL_BLEEDING_STATUS_ID =' + internal_registration)
    internal_bleeding_shadow = lua.execute(r'''
assert(WSZC.InstallInternalBleedingStatus())
local ply = MakePlayer()
ply._limbs.abdomen = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100,
    infection = 3, infectionSpeed = 1, disinfectTime = 120,
    customStatuses = { KEEP_ME = true } }
ply._limbs.pelvis = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100,
    customStatuses = {} }
ply.organism.internalBleed = 7.25
WSZC.SyncOrganismShadow(ply, ply.organism)
local id = WSZC.INTERNAL_BLEEDING_STATUS_ID
local abdomen, pelvis = ply._limbs.abdomen, ply._limbs.pelvis
local active = WoundSystem.Statuses.GetActive(abdomen)
local present = abdomen.customStatuses[id] == 7.25
    and ply._body.internalBleeding == 7.25 and abdomen.bleed == 0
    and #active == 1 and active[1].data.icon == "casunknown-images/moodles/internalbleed_red.png"
local abdomenOnly = pelvis.customStatuses[id] == nil
    and ply._limbs.thorax.customStatuses == nil
local mechanicsUntouched = abdomen.disinfectTime == 120
    and abdomen.infection == 3 and abdomen.infectionSpeed == 1
    and abdomen.customStatuses.KEEP_ME == true

-- Exercise C:U's actual status wire format, not a second hand-written copy.
local wire, readAt = {}, 0
local function push(value) wire[#wire + 1] = value end
local function pop()
    readAt = readAt + 1
    return wire[readAt]
end
local oldNet = net
net = { WriteUInt = push, WriteString = push, WriteFloat = push, WriteBool = push,
    ReadUInt = pop, ReadString = pop, ReadFloat = pop, ReadBool = pop }
SERVER, CLIENT = true, false
WoundSystem.Statuses.WriteNet(abdomen)
local received = {}
SERVER, CLIENT = false, true
WoundSystem.Statuses.ReadNet(received)
SERVER, CLIENT = true, false
net = oldNet
local networked = received.customStatuses[id] == 7.25
    and #WoundSystem.Statuses.GetActive(received) == 1

ply.organism.internalBleed = 0
ply._WSZCShadowNext = 0
WSZC.SyncOrganismShadow(ply, ply.organism)
local cleared = abdomen.customStatuses[id] == nil
    and pelvis.customStatuses[id] == nil and ply._body.internalBleeding == 0
    and #WoundSystem.Statuses.GetActive(abdomen) == 0
    and abdomen.customStatuses.KEEP_ME == true
return present, abdomenOnly and mechanicsUntouched, cleared, networked
''')
    check("R73 real org.internalBleed creates the native red abdomen marker, not external bleed", internal_bleeding_shadow[0])
    check("R74 internal marker is abdomen-only and preserves disinfection/infection/custom statuses", internal_bleeding_shadow[1])
    check("R75 stopping internal bleeding clears the marker and native status", internal_bleeding_shadow[2])
    check("R76 native WriteNet/ReadNet round-trip carries the abdomen marker to the client", internal_bleeding_shadow[3])
    external_only = lua.execute(r'''
local ply = MakePlayer()
ply.organism.internalBleed = 0
ply.organism.bleed = 12
ply._body.internalBleeding = 9 -- stale native shadow from an earlier event
ply._limbs.abdomen = { bleed = 0, pain = 0, muscle = 100, skin = 100,
    customStatuses = { [WSZC.INTERNAL_BLEEDING_STATUS_ID] = 9 } }
WSZC.SyncOrganismShadow(ply, ply.organism)
return ply._body.internalBleeding == 0
    and ply._limbs.abdomen.customStatuses[WSZC.INTERNAL_BLEEDING_STATUS_ID] == nil
    and ply.organism.bleed == 12 and ply.organism.internalBleed == 0
''')
    check("R97 external bleeding clears stale internal-bleed presentation without changing organism", external_only)

    internal_resync = lua.execute(r'''
local ply = MakePlayer()
local id = WSZC.INTERNAL_BLEEDING_STATUS_ID
local h = WoundSystem.Health
local oldSend = h.SendLimbUpdate
local sent, failOnce = {}, true
h.SendLimbUpdate = function(target, limb, force)
    if limb == "abdomen" and failOnce then error("simulated send failure") end
    sent[limb] = { force = force, value = target._limbs[limb].customStatuses
        and target._limbs[limb].customStatuses[id] }
end
ply.organism.internalBleed = 0
ply._limbs.abdomen = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100,
    customStatuses = { [id] = 5, KEEP = true } }
ply._limbs.forearm_R.customStatuses = { [id] = 5, KEEP = true }
WSZC.SyncOrganismShadow(ply, ply.organism)
local staleCleared = ply._limbs.forearm_R.customStatuses[id] == nil
    and ply._limbs.forearm_R.customStatuses.KEEP and sent.forearm_R.force
    and sent.forearm_R.value == nil and ply._WSZCInternalBleedPending.abdomen
failOnce = false
ply._WSZCShadowNext = 0
WSZC.SyncOrganismShadow(ply, ply.organism)
local retried = sent.abdomen.force and sent.abdomen.value == nil
    and ply._WSZCInternalBleedPending == nil
ply.organism.internalBleed = 0.001
ply._WSZCShadowNext = 0
WSZC.SyncOrganismShadow(ply, ply.organism)
local positive = ply._limbs.abdomen.customStatuses[id] == 0.001
    and sent.abdomen.force and sent.abdomen.value == 0.001
ply.organism.internalBleed = 0
ply._WSZCShadowNext = 0
WSZC.SyncOrganismShadow(ply, ply.organism)
local stopped = ply._limbs.abdomen.customStatuses[id] == nil and sent.abdomen.value == nil
h.SendLimbUpdate = oldSend
return staleCleared, retried, positive, stopped
''')
    check("internal-bleed stale markers on other limbs are removed and force-sent", internal_resync[0])
    check("failed internal-bleed updates are retried", internal_resync[1])
    check("even small positive ZCity internal bleeding remains visible", internal_resync[2])
    check("zero internal bleeding force-clears the abdomen marker", internal_resync[3])

    # Use the actual C:U icon chooser and status wire to distinguish an ordinary
    # abdomen hit from genuine organism-wide internal bleeding.  Both can be
    # present simultaneously and neither may suppress the other.
    gui_s = (CONN / "lua/wszc_vendor/cu/woundsystem/client/cl_health_gui.lua").read_text(encoding="utf-8")
    rate_s = 'local function ClientLimbBleedRate(state)' + gui_s.split('local function ClientLimbBleedRate(state)', 1)[1].split('WoundSystemHealthHUDOpen =', 1)[0]
    icon_s = 'local function BleedPhaseColor(rate, alpha)' + gui_s.split('local function BleedPhaseColor(rate, alpha)', 1)[1].split('WoundSystemActionButtonPos =', 1)[0]
    lua.execute('''
local Icons = { smallbleed = "normal", midbleed = "normal", strongbleed = "normal",
    extremebleed = "normal", smallbleed_bandaged = "bandaged", midbleed_bandaged = "bandaged",
    strongbleed_bandaged = "bandaged", extremebleed_bandaged = "bandaged" }
local function ClientBleedingSpeedMultiplier() return 1 end
local function Color(r, g, b, a) return { r, g, b, a } end
local function LerpColor(t, a, b) return a end
''' + rate_s + icon_s + '\nTestActualBleedHudIcon = GetBleedHudIcon\n')
    bleed_paths = lua.execute(r'''
local ply = MakePlayer()
local id = WSZC.INTERNAL_BLEEDING_STATUS_ID
ply._limbs.abdomen = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100 }
ply.organism.wounds = {
    { 2, Vector(), Angle(), "ValveBiped.Bip01_Spine1", 0 },
    { 2, Vector(), Angle(), "ValveBiped.Bip01_R_Forearm", 0 },
}
ply.organism.bleed, ply.organism.internalBleed = 4, 0
local function sync()
    ply._WSZCShadowNext = 0
    WSZC.SyncOrganismShadow(ply, ply.organism)
end
local function wireCopy(state)
    local wire, i = {}, 0
    local function push(v) wire[#wire + 1] = v end
    local function pop() i = i + 1; return wire[i] end
    local old = net
    net = { WriteUInt = push, WriteString = push, WriteFloat = push, WriteBool = push,
        ReadUInt = pop, ReadString = pop, ReadFloat = pop, ReadBool = pop }
    SERVER, CLIENT = true, false
    WoundSystem.Statuses.WriteNet(state)
    local result = { bleed = state.bleed }
    SERVER, CLIENT = false, true
    WoundSystem.Statuses.ReadNet(result)
    SERVER, CLIENT, net = true, false, old
    return result
end
sync()
local abdomen, arm = wireCopy(ply._limbs.abdomen), wireCopy(ply._limbs.forearm_R)
local ordinary = TestActualBleedHudIcon(abdomen, 255) == "normal"
    and TestActualBleedHudIcon(arm, 255) == "normal"
    and abdomen.bleed == arm.bleed and not WoundSystem.Statuses.Has(abdomen, id)
ply.organism.internalBleed = 1.25
sync()
abdomen, arm = wireCopy(ply._limbs.abdomen), wireCopy(ply._limbs.forearm_R)
local both = TestActualBleedHudIcon(abdomen, 255) == "normal"
    and WoundSystem.Statuses.GetValue(abdomen, id) == 1.25
    and not WoundSystem.Statuses.Has(arm, id)
ply.organism.wounds, ply.organism.bleed = {}, 0
sync()
abdomen = wireCopy(ply._limbs.abdomen)
local internalOnly = TestActualBleedHudIcon(abdomen, 255) == nil
    and WoundSystem.Statuses.Has(abdomen, id)
ply.organism.internalBleed = 0
sync()
abdomen = wireCopy(ply._limbs.abdomen)
local neither = TestActualBleedHudIcon(abdomen, 255) == nil
    and not WoundSystem.Statuses.Has(abdomen, id)
ply._limbs.abdomen.customStatuses[id] = 0
ply.organism.internalBleed = 0.001
sync()
local positiveAfterZero = WoundSystem.Statuses.Has(wireCopy(ply._limbs.abdomen), id)
return ordinary, both, internalOnly, neither, positiveAfterZero
''')
    check("ordinary abdomen and arm wounds use the same native bleed icon, not the internal icon", bleed_paths[0])
    check("real internal and ordinary abdomen bleeding display independently together", bleed_paths[1])
    check("internal bleeding alone does not create an external wound icon", bleed_paths[2])
    check("both icons clear when their independent ZCity sources stop", bleed_paths[3])
    check("a stale zero status cannot hide small positive internal bleeding", bleed_paths[4])

    arterial_bleeding_shadow = lua.execute(r'''
assert(WSZC.InstallArterialBleedingStatus())
local ply = MakePlayer()
local id = WSZC.ARTERIAL_BLEEDING_STATUS_ID
ply.organism.wounds = {
    { 2, vector_origin, angle_zero, "ValveBiped.Bip01_R_Forearm", 0, 0 },
}
WSZC.SyncOrganismShadow(ply, ply.organism)
local ordinaryOnly = ply._limbs.forearm_R.bleed > 0
    and (not ply._limbs.forearm_R.customStatuses
        or ply._limbs.forearm_R.customStatuses[id] == nil)

ply.organism.arterialwounds = {
    { 4, vector_origin, angle_zero, "ValveBiped.Bip01_R_Forearm", 0, 0, "rarmartery" },
}
ply._WSZCShadowNext = 0
WSZC.SyncOrganismShadow(ply, ply.organism)
local state = ply._limbs.forearm_R
local active = WoundSystem.Statuses.GetActive(state)
local present = state.customStatuses[id] == 12 and state.bleed > 12
    and #active == 1 and active[1].id == id
    and active[1].data.icon == "wszc/unitmenu/status/arterial.png"
    and (not ply._limbs.hand_R.customStatuses
        or ply._limbs.hand_R.customStatuses[id] == nil)

ply.organism.arterialwounds = {}
ply._WSZCShadowNext = 0
WSZC.SyncOrganismShadow(ply, ply.organism)
local cleared = state.customStatuses[id] == nil and state.bleed > 0
    and #WoundSystem.Statuses.GetActive(state) == 0
return ordinaryOnly, present, cleared
''')
    check("R97 ordinary wound bleeding never creates an arterial marker", arterial_bleeding_shadow[0])
    check("R98 real arterialwounds create the native red marker on the mapped limb", arterial_bleeding_shadow[1])
    check("R99 closing the artery clears only its marker; ordinary bandage bleed remains", arterial_bleeding_shadow[2])

    standing_fall = lua.execute(r'''
if type(WSZC.ApplyStandingFall) ~= "function" then return false, false, false end
local ply = MakePlayer()
local org = ply.organism
org.lleg, org.rleg, org.immobilization = 0, 0, 0
org.painadd, org.shock, org.adrenaline, org.alive = 0, 0, 0, true
org.wsmovemult = 0.02 -- stale C:U override would bypass every vanilla slowdown term
ply._body.jumpSpeed = 6.5
for _, id in ipairs({ "foot_L", "foot_R", "crus_L", "crus_R", "thigh_L", "thigh_R" }) do
    ply._limbs[id] = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100 }
end
WoundSystem.Health.GetRecentFallSpeed = function() return 900 end
WoundSystem.Health.FallSpeedToImpactForce = function(speed)
    return math.max((speed - 420) / 60, 0)
end
local function FallDamage()
    return { IsFallDamage = function() return true end, GetDamage = function() return 30 end }
end
local dmg = FallDamage()
local handled = WSZC.ApplyStandingFall(ply, dmg, 30)
local injured = handled == true and org.lleg > 0 and org.rleg > 0
    and org.immobilization > 0 and org.painadd > 0 and org.wsmovemult == nil
ply._WSZCShadowNext = 0
WSZC.SyncOrganismShadow(ply, org)
local shadowMatches = ply._limbs.foot_L.muscle < 100 and ply._limbs.foot_R.muscle < 100

local rag = MakePlayer()
rag.organism.lleg, rag.organism.rleg, rag.organism.immobilization = 0, 0, 0
rag.FakeRagdoll = {}
local ragHandled = WSZC.ApplyStandingFall(rag, FallDamage(), 30)
local noDouble = ragHandled == false and rag.organism.lleg == 0
    and rag.organism.rleg == 0 and rag.organism.immobilization == 0

local low = MakePlayer()
low.organism.lleg, low.organism.rleg, low.organism.immobilization = 0, 0, 0
low._body.jumpSpeed = 6.5
WoundSystem.Health.GetRecentFallSpeed = function() return 600 end
local lowHandled = WSZC.ApplyStandingFall(low, FallDamage(), 0)
local lowSafe = lowHandled == false and low.organism.lleg == 0
    and low.organism.rleg == 0 and low.organism.immobilization == 0
return injured and shadowMatches, noDouble, lowSafe
''')
    check("R77 nonfatal standing fall damages authoritative legs and adds temporary slowdown", standing_fall[0])
    check("R78 standing-fall mirror never double-hits an existing fake ragdoll", standing_fall[1])
    check("R79 sub-threshold landing remains free of artificial muscle damage", standing_fall[2])

    fatal_fall = lua.execute(r'''
local p = MakePlayer()
p.Alive = function() return false end
p.organism.lleg, p.organism.rleg, p.organism.immobilization = 0, 0, 0
local dmg = { IsFallDamage = function() return true end, GetDamage = function() return 100 end }
return WSZC.ApplyStandingFall(p, dmg, 100) == false
    and p.organism.lleg == 0 and p.organism.rleg == 0 and p.organism.immobilization == 0
''')
    check("R87 fatal fall receives no post-mortem standing-leg mirror", fatal_fall)

    small_fall_minute = lua.execute(r'''
local prevCurTime = CurTime
local simNow = 1000
CurTime = function() return simNow end

local ply = MakePlayer()
local org = ply.organism
org.lleg, org.rleg, org.immobilization = 0, 0, 0
org.painadd, org.shock, org.adrenaline, org.analgesia, org.painkiller = 0, 0, 0, 0, 0
org.alive = true
for _, id in ipairs({ "foot_L", "foot_R", "crus_L", "crus_R", "thigh_L", "thigh_R" }) do
    ply._limbs[id] = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100 }
end

-- Exact GMod small-height -10 HP fall (speed ~540 u/s, default mp_falldamage 0 -> 10 HP)
WoundSystem.Health.GetRecentFallSpeed = function() return 540 end
local dmg10 = { IsFallDamage = function() return true end, GetDamage = function() return 10 end }
local okLanding = WSZC.ApplyStandingFall(ply, dmg10, 10)
ply._WSZCShadowNext = 0
WSZC.SyncOrganismShadow(ply, org)

local speedMultAt0 = math.Clamp(5 / ((org.immobilization or 0) + 1), 0.45, 1)
local initialOK = okLanding == true
    and org.lleg >= 0.25 and org.lleg < 1.0
    and org.rleg >= 0.25 and org.rleg < 1.0
    and ply._limbs.foot_L.muscle <= 75 and ply._limbs.foot_R.muscle <= 75
    and speedMultAt0 < 0.65

-- Simulate vanilla ZCity sv_pain + WSZC.TickFallSlowdown for 45s (must STILL have slowdown + muscle damage)
for step = 1, 45 do
    simNow = simNow + 1
    org.immobilization = math.max((org.immobilization or 0) - 2, 0)
    org.lleg = math.max((org.lleg or 0) - (1 / 240), 0)
    org.rleg = math.max((org.rleg or 0) - (1 / 240), 0)
    WSZC.TickFallSlowdown(ply, org, 1, false)
end
ply._WSZCShadowNext = 0
WSZC.SyncOrganismShadow(ply, org)
local speedMultAt45 = math.Clamp(5 / ((org.immobilization or 0) + 1), 0.45, 1)
local midMinuteOK = org.lleg > 0.05 and org.rleg > 0.05
    and ply._limbs.foot_L.muscle < 95
    and org.immobilization > 4.0 and speedMultAt45 < 0.95

-- Advance past ~65s: both muscle bruise and slowdown recover naturally to 100%
for step = 1, 22 do
    simNow = simNow + 1
    org.immobilization = math.max((org.immobilization or 0) - 2, 0)
    org.lleg = math.max((org.lleg or 0) - (1 / 240), 0)
    org.rleg = math.max((org.rleg or 0) - (1 / 240), 0)
    WSZC.TickFallSlowdown(ply, org, 1, false)
end
ply._WSZCShadowNext = 0
WSZC.SyncOrganismShadow(ply, org)
local speedMultAt67 = math.Clamp(5 / ((org.immobilization or 0) + 1), 0.45, 1)
local recoveredOK = org.lleg == 0 and org.rleg == 0
    and ply._limbs.foot_L.muscle == 100 and ply._limbs.foot_R.muscle == 100
    and speedMultAt67 == 1 and org.wszc_fall_slow_until == nil

-- Also verify speed > 600 where ZCity fallStun creates FakeRagdoll on the same OnPlayerHitGround tick
local stunned = MakePlayer()
stunned.organism.lleg, stunned.organism.rleg, stunned.organism.immobilization = 0, 0, 0
stunned.organism.alive = true
stunned._wszcStandingLandingTime = simNow
stunned._wszcStandingLandingSpeed = 620
stunned.FakeRagdoll = {} -- created on landing tick by ZCity fallStun
local stunHandled = WSZC.ApplyStandingFall(stunned, { IsFallDamage = function() return true end, GetDamage = function() return 10 end }, 10)
local stunOK = stunHandled == true and stunned.organism.lleg >= 0.25 and stunned.organism.immobilization > 4

CurTime = prevCurTime
return initialOK and midMinuteOK and recoveredOK, stunOK
''')
    check("R96 small -10 HP fall deals ~1-minute leg muscle damage and sustained slowdown", small_fall_minute[0])
    check("R97 same-tick ZCity fallStun landing (>600 speed) still applies 1-minute fall bruise", small_fall_minute[1])

    genuine_life = lua.execute(r'''
if type(WSZC.InstallSpawnContextGuard) ~= "function" then return false, false end
local function InjuredPlayer()
    local p = MakePlayer()
    p._limbs.arm_R = { shrapnel = 0, bleed = 0, pain = 0, muscle = 30, skin = 100,
        dislocated = true, dislocationTimer = 35 }
    p.organism.otrub, p.organism.fake = true, true
    p.organism.rarm, p.organism.rarmdislocation = 0.7, true
    p.organism.wounds = { { 7 } }
    p.organism.wszc_shrapnel = { arm_R = 3 }
    p._limbs.arm_R.shrapnel = 3
    p.FakeRagdoll = {}
    return p
end
hook.Add("Player Spawn", "homigrad-organism", function(p)
    hg.organism.Clear(p.organism)
end)
WSZC.InstallSpawnContextGuard()

local dead = InjuredPlayer()
dead._WSZCRagdollTransitionUntil = CurTime() + 5
dead.Alive = function() return false end
local death = hook._t.PlayerDeath and hook._t.PlayerDeath.WSZC_RagdollTransitionDeath
if death then death(dead) end
dead.Alive = function() return true end
OverrideSpawn = nil
hook._t["Player Spawn"]["homigrad-organism"](dead)
WSZC.ReconcileSpawnShrapnel(dead)
dead._WSZCShadowNext = 0
WSZC.SyncOrganismShadow(dead, dead.organism)
local clean = (tonumber(dead.organism.rarm) or 0) == 0
    and dead.organism.rarmdislocation ~= true
    and #dead.organism.wounds == 0
    and (dead.organism.wszc_shrapnel == nil or (dead.organism.wszc_shrapnel.arm_R or 0) == 0)
    and (dead._limbs.arm_R.shrapnel or 0) == 0
    and dead._limbs.arm_R.dislocated ~= true

local standing = InjuredPlayer()
OverrideSpawn = true
hook._t["Player Spawn"]["homigrad-organism"](standing)
OverrideSpawn = nil
local fakeUpKept = standing.organism.rarm == 0.7
    and standing.organism.rarmdislocation == true
    and #standing.organism.wounds >= 1 and standing.organism.wounds[1][1] == 7
    and standing.organism.wszc_shrapnel.arm_R == 3
return clean, fakeUpKept
''')
    check("R80 genuine death/respawn clears organism and connector injuries despite stale down flags", genuine_life[0])
    check("R81 the same native spawn hook still preserves the complete organism during FakeUp", genuine_life[1])

    corpse_life = lua.execute(r'''
local p = MakePlayer()
WSZC.AddShrapnel(p, "hand_R", 1, "shotgun")
local corpse = {}
for key, value in pairs(p.organism) do corpse[key] = value end -- native table.Merge is shallow
local woundCount = #corpse.wounds
local death = hook._t.PlayerDeath and hook._t.PlayerDeath.WSZC_RagdollTransitionDeath
if death then death(p) end
p.Alive = function() return false end
hg.organism.Clear(p.organism)
local tagged = false
for _, wound in pairs(corpse.wounds) do if wound.wszcShrapnel then tagged = true end end
local corpseKept = #corpse.wounds == woundCount and tagged
    and corpse.wszc_shrapnel.hand_R == 3
p.Alive = function() return true end
OverrideSpawn = nil
hook._t["Player Spawn"]["homigrad-organism"](p)
local newLifeClean = (p.organism.wszc_shrapnel == nil
    or (p.organism.wszc_shrapnel.hand_R or 0) == 0)
    and #p.organism.wounds == 0
return corpseKept, newLifeClean
''')
    check("R84 PostPlayerDeath clear does not erase shallow-copied corpse wounds", corpse_life[0])
    check("R85 the following genuine spawn still removes the previous life's connector state", corpse_life[1])

    reconcile_fallback = lua.execute(r'''
local p = MakePlayer()
p.organism.wszc_shrapnel = { hand_R = 3 }
p.organism.wounds = { { 4, wszcShrapnel = true } }
p._limbs.hand_R.shrapnel = 3
p._WSZCSpawnKind = "genuine"
p._WSZCSpawnCleanupAt = nil
WSZC.ReconcileSpawnShrapnel(p)
local clean = (p.organism.wszc_shrapnel == nil
    or (p.organism.wszc_shrapnel.hand_R or 0) == 0)
    and p._limbs.hand_R.shrapnel == 0 and #p.organism.wounds == 0
local knownCleanTable = p._WSZCLimbsRef == p._limbs
-- The following ordinary shadow pass must not interpret this as a ragdoll
-- table replacement and restore the previous life again.
p._WSZCShadowNext = 0
WSZC.SyncOrganismShadow(p, p.organism)
return clean and knownCleanTable and p._limbs.hand_R.shrapnel == 0
''')
    check("R86 genuine Reconcile is a self-sufficient fallback against shrapnel resurrection", reconcile_fallback)

    delayed_respawn = lua.execute(r'''
local p = MakePlayer()
p._WSZCSpawnKind = "genuine"
p._WSZCSpawnCleanupAt = nil
local closes = 0
WSZC.StopAllMinigames = function() closes = closes + 1 return true end
WSZC.ReconcileSpawnShrapnel(p, false)
-- C:U LoadPlayerPersistData merges old values into THIS SAME limb table from
-- a later PlayerSpawn hook.  Identity and the CurTime cleanup marker stay put.
p._limbs.hand_R.shrapnel = 3
p._limbs.hand_R.dislocated = true
p.organism.wszc_shrapnel = { hand_R = 3 }
WSZC.ReconcileSpawnShrapnel(p, true)
return closes == 2 and p._limbs.hand_R.shrapnel == 0
    and p._limbs.hand_R.dislocated == false
    and (p.organism.wszc_shrapnel == nil or (p.organism.wszc_shrapnel.hand_R or 0) == 0)
    and p._WSZCLimbsRef == p._limbs
''')
    check("R88 delayed genuine reset clears a late same-table C:U persist restore", delayed_respawn)

    native_reduction = lua.execute(r'''
if type(WSZC.InstallNativeDislocationBridge) ~= "function" then return false, false end
local oldNet = net
net = { Receivers = {} }
local p = MakePlayer()
p._limbs.arm_R = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100,
    dislocated = true, dislocationTimer = 20 }
p.organism.rarmdislocation = true
p._WSZCShadowNext = 0
WSZC.SyncOrganismShadow(p, p.organism)
net.Receivers.WoundSystem_DislocationInput = function()
    -- This mock represents ONLY the native server's already accepted success
    -- transition (session timer < native threshold), not a client prediction.
    p._limbs.arm_R.dislocated = false
    p._limbs.arm_R.dislocationTimer = 0
end
WSZC.InstallNativeDislocationBridge()
net.Receivers.WoundSystem_DislocationInput(0, p)
local committed = p.organism.rarmdislocation == false

local missed = MakePlayer()
missed._limbs.arm_R = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100,
    dislocated = true, dislocationTimer = 20 }
missed.organism.rarmdislocation = true
net.Receivers.WoundSystem_DislocationInput = function() end
WSZC.InstallNativeDislocationBridge()
net.Receivers.WoundSystem_DislocationInput(0, missed)
local missKept = missed.organism.rarmdislocation == true
local lower = MakePlayer()
lower._limbs.arm_R = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100,
    dislocated = true, dislocationTimer = 20 }
lower.organism.rarmdislocation = true
net.Receivers = { woundsystem_dislocationinput = function()
    lower._limbs.arm_R.dislocated = false
    lower._limbs.arm_R.dislocationTimer = 0
end }
local installedLower = WSZC.InstallNativeDislocationBridge()
net.Receivers.woundsystem_dislocationinput(0, lower)
local lowerCommitted = installedLower and lower.organism.rarmdislocation == false
net = oldNet
return committed, missKept, lowerCommitted
''')
    check("R82 accepted native dislocation success commits to ZCity immediately", native_reduction[0])
    check("R83 unsuccessful native dislocation input cannot clear the ZCity injury", native_reduction[1])
    check("R98 lowercase GMod native dislocation input commits to organism", native_reduction[2])

    visual_fn_start = shared_s.index('function WSZC.DislocationVisualAligned')
    visual_fn_end = shared_s.index('\nend\n', visual_fn_start) + 5
    lua.execute(shared_s[visual_fn_start:visual_fn_end])
    session_refs_fn_start = server_main_s.index('function WSZC.RefreshNativeSessionRefs')
    session_refs_fn_end = server_main_s.index('\nend\n', session_refs_fn_start) + 5
    lua.execute(server_main_s[session_refs_fn_start:session_refs_fn_end])
    visual_reduction = lua.execute(r'''
WSZC.Ready = true
WSZC.RemoteNativeSessions = {}
local closed = {}
WSZC.CUCloseDislocationSession = function(target, reason)
    closed[target] = (closed[target] or 0) + 1
    WSZC.CUSessions.Dislocation[target] = nil
end
local function Injured(sessionId)
    local p = MakePlayer()
    p._limbs.arm_R = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100,
        dislocated = true, dislocationTimer = 35 }
    p.organism.rarmdislocation = true
    WSZC.SyncOrganismShadow(p, p.organism)
    WSZC.CUSessions = WSZC.CUSessions or { Dislocation = {} }
    WSZC.CUSessions.Dislocation[p] = {
        id = sessionId, limbId = "arm_R", boneX = 800, boneY = 400,
        boneVelX = 20, boneVelY = -10, dislocationTimer = 35,
    }
    return p
end
WSZC.CUSessions = { Dislocation = {} }
local selfPatient = Injured(501)
local selfOK = WSZC.HandleDislocationVisualComplete(selfPatient, 501, 451.82, 229.82)
local selfCommitted = selfOK and selfPatient._limbs.arm_R.dislocated == false
    and selfPatient._limbs.arm_R.dislocationTimer == 0
    and selfPatient.organism.rarmdislocation == false
    and closed[selfPatient] == 1 and WSZC.CUSessions.Dislocation[selfPatient] == nil

local rejected = Injured(502)
local wrongId = WSZC.HandleDislocationVisualComplete(rejected, 999, 421.82, 229.82)
local far = WSZC.HandleDislocationVisualComplete(rejected, 502, 521.82, 229.82)
-- A circular 40-unit radius accepts a near miss but never the 50-unit
-- minimum start displacement; malformed inputs and outside positions fail.
local thresholdForgiving = WSZC.DislocationVisualAligned(461.81, 229.82) == true
    and WSZC.DislocationVisualAligned(461.83, 229.82) == false
    and WSZC.DislocationVisualAligned(449.82, 257.82) == true
    and WSZC.DislocationVisualAligned(450.82, 258.82) == false
    and not WSZC.DislocationVisualAligned(471.82, 229.82)
    and not WSZC.DislocationVisualAligned(nil, 229.82)
    and not WSZC.DislocationVisualAligned(0/0, 229.82)
    and not WSZC.DislocationVisualAligned(math.huge, 229.82)
local rejectionHeld = wrongId == false and far == false and thresholdForgiving
    and rejected._limbs.arm_R.dislocated == true
    and rejected.organism.rarmdislocation == true and closed[rejected] == nil

local medic, remotePatient = MakePlayer(), Injured(503)
WSZC.RemoteNativeSessions[remotePatient] = { Dislocation = { operator = medic } }
WSZC.RemoteMedicalValidPair = function(operator, target)
    return operator == medic and target == remotePatient
end
local remoteOK = WSZC.HandleDislocationVisualComplete(medic, 503, 445.82, 253.82)
local remoteCommitted = remoteOK and remotePatient._limbs.arm_R.dislocated == false
    and remotePatient.organism.rarmdislocation == false
    and closed[remotePatient] == 1 and closed[medic] == nil
    and WSZC.RemoteNativeSessions[remotePatient] == nil

-- Reproduce the modern native-api early return: NO test session refs are
-- preinstalled in WSZC.  The receiver must discover the real native tables.
local lazyPatient = Injured(504)
local nativeSessions = WSZC.CUSessions
local nativeClose = WSZC.CUCloseDislocationSession
WSZC.CUSessions, WSZC.CUCloseDislocationSession = nil, nil
WoundSystem.Health._WSZCBridgeRefs = {
    Sessions = nativeSessions, CloseDislocationSession = nativeClose,
}
local oldFindUpvalue = WSZC.FindUpvalue
WSZC.FindUpvalue = function(wanted)
    if wanted == "Sessions" then return nativeSessions end
    if wanted == "CloseDislocationSession" then return nativeClose end
    return nil
end
local lazyOK = WSZC.HandleDislocationVisualComplete(lazyPatient, 504, 421.82, 229.82)
local lazyCommitted = lazyOK and WSZC.CUSessions == nativeSessions
    and WSZC.CUCloseDislocationSession == nativeClose
    and lazyPatient._limbs.arm_R.dislocated == false
    and lazyPatient.organism.rarmdislocation == false and closed[lazyPatient] == 1
WSZC.FindUpvalue = oldFindUpvalue
WoundSystem.Health._WSZCBridgeRefs = nil
return selfCommitted, rejectionHeld, remoteCommitted, lazyCommitted
''')
    check("R90 approximate socket hit commits native + ZCity reduction immediately", visual_reduction[0])
    check("R91 wrong-session and non-aligned visual packets cannot heal", visual_reduction[1])
    check("R92 rendered remote reduction treats the patient and clears operator metadata", visual_reduction[2])
    check("R95 modern native-api path lazily discovers Sessions and accepts visual completion", visual_reduction[3])

    legacy_block = lua.execute(r'''
local previousCommand, previousWB = concommand, hg.WoundBridge
local previousBlocked = WSZC.LegacyRadialMedicineBlocked
local previousWrapper = WSZC._LegacyFixDislocationCommandWrapper
local blocked = true
WSZC.LegacyRadialMedicineBlocked = function() return blocked end
local bridgeCalls, commandCalls = 0, 0
local wb = { FixDislocation = function() bridgeCalls = bridgeCalls + 1 return "legacy_bridge" end }
hg.WoundBridge = wb
local commands = { hg_fixdislocation = function()
    commandCalls = commandCalls + 1
    return "legacy_command"
end }
concommand = {
    GetTable = function() return commands end,
    Add = function(name, callback) commands[name] = callback end,
}
WSZC._LegacyFixDislocationCommandWrapper = nil
WSZC.InstallLegacyRadialMedicineBlock()
WSZC.InstallLegacyRadialMedicineBlock() -- reapply must not stack wrappers
local blockedBridge = wb.FixDislocation(nil, {}) == true and bridgeCalls == 0
local blockedCommand = commands.hg_fixdislocation(nil, nil, {}) == true and commandCalls == 0
blocked = false
local fallbackBridge = wb.FixDislocation(nil, {}) == "legacy_bridge" and bridgeCalls == 1
local fallbackCommand = commands.hg_fixdislocation(nil, nil, {}) == "legacy_command" and commandCalls == 1
concommand, hg.WoundBridge = previousCommand, previousWB
WSZC.LegacyRadialMedicineBlocked = previousBlocked
WSZC._LegacyFixDislocationCommandWrapper = previousWrapper
return blockedBridge and blockedCommand and fallbackBridge and fallbackCommand
''')
    check("R93 ready gate blocks radial bridge/command; unsupported state preserves fallback", legacy_block)

    reset_regression = lua.execute(r'''
local ply = MakePlayer()
local org = ply.organism
org.blood, org.pain, org.rarm, org.chest, org.brokenribs = 900, 90, 1, 1, 3
org.rarmdislocation, org.rarmamputated = true, true
org.otrub, org.unconscious, org.fake, org.needfake = true, true, true, true
ply.FakeRagdoll = { valid = true, organism = org }
ply._limbs.forearm_R.broken, ply._limbs.forearm_R.dismembered = true, true
ply._limbs.forearm_R.muscle, ply._limbs.forearm_R.skin = 1, 1
ply._limbs.forearm_R.customStatuses = { WSZC_ARTERIAL_BLEEDING = 10 }
-- Simulate a late replacement bridge which returns success without calling
-- organism.Clear. WB.Sync projects authoritative fractures back to the UI.
local previousReset, previousSync = hg.WoundBridge.ResetOrganism, hg.WoundBridge.Sync
local updates, cancellations = 0, 0
local previousNotify, previousCancel = WSZC.NotifyRemotePatientUpdated, WSZC.CancelRemotePatientTreatment
WSZC.NotifyRemotePatientUpdated = function(target) if target == ply then updates = updates + 1 end end
WSZC.CancelRemotePatientTreatment = function(target) if target == ply then cancellations = cancellations + 1 end end
hg.WoundBridge.ResetOrganism = function() return true end
hg.WoundBridge.Sync = function(target, source)
    target._limbs.forearm_R.broken = (tonumber(source.rarm) or 0) >= 1
    target._limbs.thorax.broken = (tonumber(source.brokenribs) or 0) > 0
end
WSZC.InstallResetStructureGuard()
local result = hg.WoundBridge.ResetOrganism(ply)
hg.WoundBridge.Sync(ply, org)
local clean = result and org.blood == 5000 and org.pain == 0 and org.rarm == 0
    and org.chest == 0 and org.brokenribs == 0 and not org.rarmdislocation
    and not org.rarmamputated and not org.otrub and not org.unconscious
    and org.fake and org.needfake and ply.FakeRagdoll.organism == org
    and not ply._limbs.forearm_R.broken and not ply._limbs.thorax.broken
    and not ply._limbs.forearm_R.dismembered and ply._limbs.forearm_R.muscle == 100
    and not ply._limbs.forearm_R.customStatuses.WSZC_ARTERIAL_BLEEDING
    and updates > 0 and cancellations > 0
hg.WoundBridge.ResetOrganism, hg.WoundBridge.Sync = previousReset, previousSync
WSZC.NotifyRemotePatientUpdated, WSZC.CancelRemotePatientTreatment = previousNotify, previousCancel
return clean
''')
    check("R99 successful bridge without Clear still resets organism and survives sync", reset_regression)

    direct_reset = lua.execute(r'''
local ply = MakePlayer()
local bone = "ValveBiped.Bip01_R_Hand"
local rag = { bandaged_limbs = { [bone] = true }, SetNetVar = function(self, key, value) self[key .. "Net"] = value end }
ply.FakeRagdoll = rag
ply.bandaged_limbs = { [bone] = true }
ply._limbs.hand_R.isBandaged = true
local oldClear = hg.organism.Clear
hg.organism.Clear = function(org)
    org.owner.FakeRagdoll = nil
    org.wounds = {}; org.arterialwounds = {}
end
WSZC.InstallResetStructureGuard()
WSZC._ExplicitResetDepth = 1
hg.organism.Clear(ply.organism)
WSZC._ExplicitResetDepth = 0
local cleaned = next(rag.bandaged_limbs) == nil and next(rag.bandaged_limbsNet) == nil
    and next(ply.bandaged_limbs) == nil and not ply._limbs.hand_R.isBandaged
WSZC.AddShrapnel(ply, "hand_R", 1, "shotgun")
local open = not WSZC.IsShrapnelBandaged(ply, "hand_R") and WSZC.GetBandageBleeding(ply, "hand_R") > 0
hg.organism.Clear = oldClear
return cleaned and open
''')
    check("R110 direct explicit organism clear retains old ragdoll reference for cleanup", direct_reset)

    # Execute the exact movement expressions from the shipped ZCity archive,
    # then compare them to the actual connector shadow at the same thresholds.
    movement_start = native_org_s.index('\torg.canmove = (org.spine2 < hg.organism.fake_spine2')
    movement_end = native_org_s.index('\n\tif (org.blood < 2700)', movement_start)
    movement_source = native_org_s[movement_start:movement_end]
    lua.execute('function NativeZCitySpineTick(org)\n' + movement_source + '\nend')
    spine = lua.execute(r'''
local ply = MakePlayer()
local org = ply.organism
hg.organism = { fake_spine1 = 1, fake_spine2 = 1, fake_spine3 = 0.5 }
org.spine1, org.spine2, org.stun, org.otrub = 0, 0, 0, false
org.skull, org.spine3 = 1, 0
org.needfake = false
NativeZCitySpineTick(org)
ply._WSZCShadowNext = 0; WSZC.SyncOrganismShadow(ply, org)
local skullOnly = org.canmove and org.canmovehead and not org.needfake
    and not ply._limbs.neck.broken and ply._limbs.head.muscle == 0
org.spine3 = 0.5; org.needfake = false
NativeZCitySpineTick(org)
ply._WSZCShadowNext = 0; WSZC.SyncOrganismShadow(ply, org)
local broken = not org.canmove and not org.canmovehead and org.needfake
    and ply._limbs.neck.broken and not ply._limbs.head.broken
    and not WSZC.CanBandageZCityFracture(ply, "neck")
    and WSZC.CanBandageZCityFracture(ply, "head")
ply._limbs.neck.splinted = true
ply._limbs.neck.customStatuses = { SPLINTED = 100 }
WSZC.TickSplints(ply, org, 1)
local noFictionalCure = org.spine3 == 0.5
ply._limbs.neck.splinted = false
local bandaged = WSZC.StabilizeZCityFracture(ply, "head", ply, nil)
    and math.abs(org.skull - 0.59) < 0.001 and org.spine3 == 0.5
org.spine3 = 0.49; org.needfake = false
NativeZCitySpineTick(org)
ply._WSZCShadowNext = 0; WSZC.SyncOrganismShadow(ply, org)
local healed = org.canmove and org.canmovehead and not org.needfake and not ply._limbs.neck.broken
-- Honour servers changing the native fake_spine3 threshold.
hg.organism.fake_spine3 = 0.7
org.spine3 = 0.6; org.needfake = false
NativeZCitySpineTick(org)
ply._WSZCShadowNext = 0; WSZC.SyncOrganismShadow(ply, org)
local custom = org.canmove and org.canmovehead and not ply._limbs.neck.broken
return skullOnly, broken and bandaged and noFictionalCure, healed and custom
''')
    check("R100 skull alone never produces a neck fracture or fake", spine[0])
    check("R101 actual ZCity spine3 threshold disables movement and shows neck fracture", spine[1])
    check("R102 native recovery and custom spine3 thresholds restore movement and icon", spine[2])
    check("S19 actual ZCity lethal neck snap remains native and is never synthesized from skull",
          'function hg.BreakNeck(ent)' in native_input_s
          and 'if ply:Alive() then ply:Kill() end' in native_input_s
          and 'if neck_not_broken and org.spine3 >= 0.8 then' in native_input_s
          and 'hg.BreakNeck(' not in organism_s and 'hg.BreakNeck(' not in server_main_s)

    # Install the real bridge context and the real Org Think wrapper around a
    # representative native early return and the archive's movement code.
    context_start = shared_s.index('function WSZC.WithVanillaContext(fn, ...)')
    context_end = shared_s.index('\nlocal attempts = 0', context_start)
    lua.execute(r'''
hg.WoundBridge = { IsBridged = function() return true end }
WSZC.Supports = function() return true end
WSZC.InVanillaContext = function() return (WSZC.VanillaContext or 0) > 0 end
WSZC.OrganismAuthority = function() return true end
WSZC.Warn = function() end
''')
    lua.execute(shared_s[context_start:context_end])
    lua.execute('WSZC.PatchIsBridged()')
    wrapper_start = organism_s.index('local function WrapHook(event, name, pre, post)')
    wrapper_end = organism_s.index('local function CaptureRawDamage', wrapper_start)
    lua.execute(r'''
WrappedRuns = 0
hook.Add("Org Think", "Main", function(owner, org, dt)
    if hg.WoundBridge.IsBridged(owner) then return end
    WrappedRuns = WrappedRuns + 1
    NativeZCitySpineTick(org)
end)
''')
    lua.execute('local wrappedByKey, wrappedFns = {}, {}; local function Authority() return WSZC.OrganismAuthority() end; local function Debug() end; local function Warn() end\n'
                + organism_s[wrapper_start:wrapper_end]
                + '\nWrapHook("Org Think", "Main", function(owner, org, dt) WSZC.TickFallSlowdown(owner, org, dt, true) end, function(owner, org, dt) WSZC.TickFallSlowdown(owner, org, dt, false) end)')
    wrapped = lua.execute(r'''
local ply = MakePlayer()
local org = ply.organism
hg.organism = { fake_spine1 = 1, fake_spine2 = 1, fake_spine3 = 0.5 }
org.spine1, org.spine2, org.spine3, org.stun, org.otrub, org.needfake = 0, 0, 0.6, 0, false, false
hook._t["Org Think"].Main(ply, org, 0.1)
return WrappedRuns == 1 and not org.canmove and not org.canmovehead and org.needfake
    and hg.WoundBridge.IsBridged(ply) and not WSZC.InVanillaContext()
''')
    check("R105 real Org Think wrapper lets native paralysis run despite bridge early return", wrapped)
    fakeup_start = native_org_s.index('hook.Add("Should Fake Up", "organism"')
    fakeup_end = native_org_s.index('\nlocal hg_unreliable_nets', fakeup_start)
    lua.execute(native_org_s[fakeup_start:fakeup_end])
    fakeup = lua.execute(r'''
local ply = MakePlayer(); local org = ply.organism
org.spine1, org.spine2, org.spine3 = 0, 0, 0.5
org.otrub, org.fake, org.lleg, org.rleg, org.berserk, org.blood, org.consciousness = false, false, 0, 0, 0, 5000, 1
local f = hook._t["Should Fake Up"].organism
local blocked = f(ply) == false
org.spine3 = 0.49
return blocked and f(ply) == nil
''')
    check("R106 shipped ZCity Should Fake Up blocks standing until spine recovers", fakeup)

    # Exercise the exact wake callback, which is registered by the legacy
    # adapter, including the original normal-wake behaviour and authority-off.
    wake_start = server_main_s.index('    hook.Add("HG_OnWakeOtrub", "WSZC_Wake"')
    wake_end = server_main_s.index('    local function ClearRagdollState(ply)', wake_start)
    lua.execute(r'''
WSZC.Ready = true
WSZC.OrganismAuthority = function() return WakeAuthority end
WakeAuthority = true
hg.organism = { fake_spine1 = 1, fake_spine2 = 1, fake_spine3 = 0.5 }
hg.WoundBridge = { RestoreRagdoll = function() WakeRestores = WakeRestores + 1 end }
WoundSystem.Health.RestorePlayerFromUnconsciousRagdoll = function() CUrises = CUrises + 1 end
''')
    lua.execute('local H = WoundSystem.Health; local WB = hg.WoundBridge; local function BridgeEnabled() return true end\n'
                + server_main_s[wake_start:wake_end])
    wake = lua.execute(r'''
local hookFn = hook._t.HG_OnWakeOtrub.WSZC_Wake
local ply = MakePlayer()
ply.FakeRagdoll = { name = "native_fake" }
ply.organism.spine1, ply.organism.spine2, ply.organism.spine3 = 0, 0, 0.5
ply.organism.fake, ply.organism.needfake = true, true
ply._body.unconscious, ply._body.unconsciousRagdoll = true, ply.FakeRagdoll
WakeRestores, CUrises = 0, 0
hookFn(ply)
local remains = WakeRestores == 0 and CUrises == 0 and ply.organism.fake
    and ply.organism.needfake and ply._body.unconscious == false
    and ply._body.unconsciousRagdoll == ply.FakeRagdoll
ply.organism.spine3 = 0.49
hookFn(ply)
local normal = WakeRestores == 1 and CUrises == 1 and not ply.organism.fake
    and not ply.organism.needfake
WakeAuthority = false
ply.organism.spine3 = 1; ply.organism.fake = true
hookFn(ply)
local legacy = WakeRestores == 2 and CUrises == 2 and not ply.organism.fake
WakeAuthority = true
return remains, normal and legacy
''')
    check("R103 waking with cervical injury never forces standing or clears fake state", wake[0])
    check("R104 normal recovery and non-authority wake retain previous behavior", wake[1])

passed = sum(1 for _, ok in results if ok)
print("TEST_OK %d / %d" % (passed, len(results)))
sys.exit(0 if passed == len(results) else 1)
