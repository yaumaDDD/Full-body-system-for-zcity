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
server_main_s = SERVER_MAIN.read_text(encoding="utf-8")
server_mg_s = SERVER_MG.read_text(encoding="utf-8")
client_mg_s = CLIENT_MG.read_text(encoding="utf-8")
layout_s = LAYOUT.read_text(encoding="utf-8")
with ZipFile(ROOT / "zcity.zip") as zcity_zip:
    tourniquet_swep_s = zcity_zip.read("z_city/lua/weapons/weapon_tourniquet.lua").decode("utf-8-sig")
    bandage_swep_s = zcity_zip.read("z_city/lua/weapons/weapon_bandage_sh.lua").decode("utf-8-sig")
    woundbridge_s = zcity_zip.read("z_city/lua/homigrad/woundbridge/sv_woundbridge.lua").decode("utf-8-sig")
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
      and "SnapshotZCityStructure(org, false)" in organism_s
      and "_ExplicitResetDepth" in organism_s)
check("S04 added WoundView cards are rolled back; native geometry remains",
      "zc_woundsystem_compat_woundview_polish" not in layout_s
      and "WSZC_WoundViewPolishBackground" not in layout_s
      and "DrawVitalRow" not in layout_s and "LIMB STATUS" not in layout_s
      and "WSZC_UNITMENU_LIMB_GEOMETRY" in layout_s)
check("S05 bandage budget and ordinary bleed are bounded for a physical roll",
      'zc_woundsystem_compat_bandage_strength", "2"' in organism_s
      and 'zc_woundsystem_compat_bleeding_multiplier", "0.55"' in organism_s
      and "org.bleedingmul = math.min" in organism_s
      and "+ count * (0.018 + irritation * 0.002) * dt * growth, 0.5, 8)" in organism_s)
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
    "head", "thorax", "abdomen",
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
    check("R29 shotgun stays on each actually hit limb across all 15 C:U limbs", placement[0])
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
local removed = #org.wounds == 1 and org.wounds[1] == normal
    and org.wszc_shrapnel_sources.hand_R == nil
    and org.wszc_shrapnel_irritation.hand_R == nil
return separate, grows, removed
''')
    check("R03 shotgun and glass counts remain separate", effects[0])
    check("R04 lodged fragments increase real wound severity and pain", effects[1])
    check("R05 extraction removes only tagged shrapnel wounds", effects[2])

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
    for key in pairs(org) do if key ~= "owner" then org[key] = nil end end
    org.owner = owner
    org.alive, org.otrub, org.blood, org.pain = true, false, 5000, 0
    org.bleed, org.internalBleed = 0, 0
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
local resetResult = hg.WoundBridge.ResetOrganism(ply)
local explicitCleared = resetResult == true and restoreCalls == 0 and ply.organism.otrub == true
    and ply.organism.blood == 5000
    and (ply.organism.wszc_shrapnel == nil or (ply.organism.wszc_shrapnel.hand_R or 0) == 0)
    and ply.organism.wszc_shrapnel_sources == nil
    and ply.organism.wszc_shrapnel_irritation == nil
    and ply.organism.wszc_bandaged_shrapnel == nil and ply.organism.wszc_infection == nil
    and #ply.organism.wounds == 0 and ply.organism.pain == 0
    and ply.organism.bleed == 0 and ply._limbs.hand_R.shrapnel == 0
    and ply._limbs.hand_R.isBandaged == false and ply._limbs.hand_R.infection == 0
    and next(ply.bandaged_limbs) == nil and next(ply.tourniquets) == nil
ResetDebug = { result = resetResult, restoreCalls = restoreCalls,
    otrub = ply.organism.otrub, blood = ply.organism.blood, pain = ply.organism.pain,
    shrapnel = ply.organism.wszc_shrapnel, sources = ply.organism.wszc_shrapnel_sources,
    irritation = ply.organism.wszc_shrapnel_irritation,
    covered = ply.organism.wszc_bandaged_shrapnel, infection = ply.organism.wszc_infection,
    wounds = #ply.organism.wounds, bleed = ply.organism.bleed,
    limbShrapnel = ply._limbs.hand_R.shrapnel, limbBandaged = ply._limbs.hand_R.isBandaged,
    limbInfection = ply._limbs.hand_R.infection,
    bandages = next(ply.bandaged_limbs), tourniquets = next(ply.tourniquets) }
return transitionKept, explicitCleared
''')
    check("R06 ordinary ragdoll clear still preserves fragments", reset[0])
    check("R07 explicit reset fully clears fragments and medical residue", reset[1])
    if not reset[1]:
        debug = lua.globals().ResetDebug
        print("RESET_DEBUG", {k: debug[k] for k in (
            "result", "restoreCalls", "otrub", "blood", "pain", "shrapnel", "sources",
            "irritation", "covered", "infection", "wounds", "bleed", "limbShrapnel",
            "limbBandaged", "limbInfection", "bandages", "tourniquets")})

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
WSZC.AddShrapnel(ply, "hand_R", 1, "shotgun")
local limb = ply._limbs.hand_R
limb.isBandaged = false
local treated = WSZC.ApplyBandageToOrganism(
    { ply = ply, limbId = "hand_R", limb = limb },
    { effects = { bandageSlowAmount = 15 } }, 1)
local entry = ply.organism.wszc_bandaged_shrapnel.hand_R
local bandageAllowed = treated > 0 and WSZC.IsShrapnelBandaged(ply, "hand_R")
    and ply._limbs.hand_R.shrapnel == 3 and entry.covered == true
for _ = 1, 330 do WSZC.TickBandagedShrapnel(ply, ply.organism, 0.5) end
local infected = entry.infection > 20 and ply.organism.internalBleed > 0
    and ply.organism.blood < 5000 and ply._limbs.hand_R.shrapnel == 3
local infectionBefore = entry.infection

local refs = {}
local sessions = { Shrapnel = { [ply] = { limbId = "hand_R", id = 41 } } }
local closed, built, opened, consumed = 0, 0, 0, 0
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
net = {
    Receivers = { WoundSystem_ShrapnelStart = function() error("old receiver must be replaced") end },
    Receive = function(name, fn) net.Receivers[name] = fn end,
    ReadString = function() return "hand_R" end,
    ReadUInt = function() return 0 end,
    BytesLeft = function() return 1, 0 end,
}
local installed = WSZC.InstallShrapnelBandageGuard()
net.Receivers.WoundSystem_ShrapnelStart(0, ply)
local unwrapOnly = installed and closed == 1 and built == 0 and consumed == 0
    and sessions.Shrapnel[ply] == nil and ply._limbs.hand_R.shrapnel == 3
    and not WSZC.IsShrapnelBandaged(ply, "hand_R")
    and entry.infection == infectionBefore and limb.isBandaged == false
local reopened = false
for _, wound in pairs(ply.organism.wounds) do
    if wound.wszcShrapnel and wound[1] >= 2.5 then reopened = true end
end
net.Receivers.WoundSystem_ShrapnelStart(0, ply)
local secondClickNative = built == 1 and opened == 1 and consumed == 1
    and sessions.Shrapnel[ply] and sessions.Shrapnel[ply].id == 42

ply._WSZCLimbsRef = ply._limbs
ply._limbs.hand_R.shrapnel = 0
WSZC.SyncShrapnel(ply, ply.organism)
WSZC.TickBandagedShrapnel(ply, ply.organism, 0.5)
local extractionDecay = (ply.organism.wszc_shrapnel.hand_R or 0) == 0
    and entry.infection < infectionBefore and ply.organism.internalBleed > 0
local preDressed = MakePlayer()
preDressed._limbs.hand_R.isBandaged = true
preDressed.bandaged_limbs = { ["ValveBiped.Bip01_R_Hand"] = true }
WSZC.AddShrapnel(preDressed, "hand_R", 1, "shotgun")
local preDressedCovered = WSZC.IsShrapnelBandaged(preDressed, "hand_R")
    and preDressed.organism.wszc_bandaged_shrapnel.hand_R.bones["ValveBiped.Bip01_R_Hand"] == true
return bandageAllowed, infected, unwrapOnly and reopened, secondClickNative, extractionDecay, preDressedCovered
''')
    check("R14 bandage covers shrapnel instead of rejecting treatment", complications[0])
    check("R15 covered fragments cause gradual internal infection and blood loss", complications[1])
    check("R16 first click unwraps without extraction, session or tool cost", complications[2])
    check("R17 second click starts the native shrapnel session and spends tool", complications[3])
    check("R18 extracting the last fragment stops growth and starts infection decay", complications[4])
    check("R22 a pellet into an already dressed limb is covered too", complications[5])

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
    and ply.organism.owner == ply
ply.organism.rarmamputated = true
hg.WoundBridge.ResetOrganism(ply)
local explicitStillClears = ply.organism.rarmamputated ~= true
    and ply.organism.llegamputated ~= true and #ply.organism.arterialwounds == 0
return preserved, explicitStillClears
''')
    check("R40 FakeUp spawn retains native wounds, arteries, amputations and custom organs", fakeup_snapshot[0])
    check("R41 explicit organism reset still clears every amputation and artery", fakeup_snapshot[1])

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
local BestLimb = function() return "native_bandage_site" end
local NativeSwepHeal = function(target, spec, preferred)
    return BestLimb(target, spec, preferred)
end
local patched = WSZC.PatchTourniquetBestLimb(NativeSwepHeal)
local tourniquet = NativeSwepHeal(ply, { kind = "apply", item = "TOURNIQUET", pick = "extremity" })
local bandage = NativeSwepHeal(ply, { kind = "bandage", item = "GAUZE" })
return patched and tourniquet == "arm_R" and bandage == "native_bandage_site"
''')
    check("R49 installed BestLimb upvalue prioritizes only tourniquet, never bandage", selector_upvalue)

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
    and active[1].data.icon == "casunknown-images/moodles/amputation.png"
''')
    check("R50 native Statuses.GetActive draws amputation before tourniquet/bleed statuses", native_status_order)

passed = sum(1 for _, ok in results if ok)
print("TEST_OK %d / %d" % (passed, len(results)))
sys.exit(0 if passed == len(results) else 1)
