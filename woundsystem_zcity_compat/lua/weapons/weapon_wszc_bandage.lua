-- Connector-owned standalone bandage.  This class deliberately does NOT
-- inherit ZCity's weapon_bandage_sh and never calls WB.SwepHeal, so it is an
-- isolated acceptance/fallback path for Workshop versions with incompatible
-- medical SWEP code.  ZCity supplies only the organism and the world model.
if SERVER then AddCSLuaFile() end

SWEP.Base = "weapon_base"
SWEP.PrintName = "WSZC Bandage (standalone)"
SWEP.Author = "WSZC"
SWEP.Instructions = "Connector-owned bandage. LMB: treat yourself. RMB: treat another player."
SWEP.Category = "ZCity Medicine"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.ViewModel = ""
SWEP.WorldModel = "models/bandages.mdl"
SWEP.HoldType = "slam"
SWEP.UseHands = false
SWEP.Weight = 3
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize()
    self.modeValues = self.modeValues or { 40 }
    self.modeValuesdef = self.modeValuesdef or { { 40, true } }
    if self.SetWeaponHoldType then self:SetWeaponHoldType(self.HoldType) end
end

local function UseStandalone(self, secondary)
    if not SERVER then return end
    self:SetNextPrimaryAttack(CurTime() + 0.5)
    self:SetNextSecondaryAttack(CurTime() + 0.5)

    local owner = self:GetOwner()
    if not IsValid(owner) then return end
    local target = owner
    if secondary then
        local trace
        if hg and hg.eyeTrace then
            trace = hg.eyeTrace(owner)
        elseif owner.GetEyeTrace then
            trace = owner:GetEyeTrace()
        end
        local ent = trace and trace.Entity or nil
        local bridge = hg and hg.WoundBridge
        if bridge and bridge.GetPlayer then
            target = bridge.GetPlayer(ent)
        elseif IsValid(ent) and ent:IsPlayer() then
            target = ent
        else
            target = nil
        end
    end

    if not (WSZC and WSZC.UseStandaloneBandage) then
        if owner.PrintMessage then
            owner:PrintMessage(HUD_PRINTCENTER or 2, "WSZC is not ready")
        end
        return
    end
    WSZC.UseStandaloneBandage(self, target)
end

function SWEP:PrimaryAttack()
    UseStandalone(self, false)
end

function SWEP:SecondaryAttack()
    UseStandalone(self, true)
end
