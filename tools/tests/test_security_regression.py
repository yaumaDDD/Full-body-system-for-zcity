#!/usr/bin/env python3
"""Behavioral checks for embedded playtest spawner and dislocation input guards."""
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / 'woundsystem_zcity_compat/lua/wszc_vendor/cu/woundsystem/server/sv_health.lua').read_text()
start = source.index('net.Receive("WoundSystem_SpawnMedicalItem", function(_, ply)')
end = source.index('\nend)', start) + len('\nend)')
spawner = source[start:end]
start = source.index('net.Receive("WoundSystem_DislocationInput", function(_, ply)')
end = source.index('-- BANDAGE NETWORKING', start)
input_receiver = source[start:end]
start = source.index('net.Receive("WoundSystem_BandageInput", function(_, ply)')
end = source.index('-- SYRINGE NETWORKING', start)
native_bandage = source[start:end]
assert 'WSZC.FilterBandageDegrees(ply, degreesMoved, session.lastInputAt)' in native_bandage
assert 'if v ~= v or v == math.huge or v == -math.huge then return end' in input_receiver
assert 'if now - (session.lastInputAt or now) < 0.01 then return end' in input_receiver
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
math.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
CurTime = function() return 100 end
IsValid = function(p) return p ~= nil end
WoundSystemHealthEnabled = function() return true end
NormalizeToolId = function(s) return s end
calls = 0
WoundSystem = {
    Items = { Get = function(id) return { id = id, max = 100 } end,
        GetMax = function() return 100 end },
    WorldItems = { SpawnAtPlayer = function(p, id, durability)
        calls = calls + 1; spawnedId, spawnedDurability = id, durability
    end },
}
net = { Receive = function(_, fn) receiver = fn end,
        ReadString = function() return "GAUZE" end,
        ReadFloat = function() return 25 end }
''')
lua.execute(spawner)
results = lua.execute(r'''
local player = { Alive = function() return true end, IsAdmin = function() return false end }
receiver(0, player)
local denied = calls == 0 and player.WoundSystemNextMedicalSpawner == nil
player.IsAdmin = function() return true end
receiver(0, player)
local allowed = calls == 1 and spawnedId == "GAUZE" and spawnedDurability == 25
receiver(0, player)
local cooldown = calls == 1
return denied, allowed, cooldown
''')
for label, result in zip(('non-admin denied', 'admin allowed', 'admin cooldown'), results):
    print(('PASS ' if result else 'FAIL ') + label)
    assert result
print('PASS embedded dislocation finite-input and clock guards')
# Execute the real native receiver against the real shared budget function.
minigames = (ROOT / 'woundsystem_zcity_compat/lua/autorun/server/sv_zcity_woundsystem_compat_minigames.lua').read_text()
pos = minigames.index('function WSZC.FilterBandageDegrees')
filter_fn = minigames[pos:minigames.index('\nend', pos) + len('\nend')]
receiver = native_bandage[:native_bandage.index('\nend)') + len('\nend)')]
lua.execute(r'''
WSZC = {}
local time = 200
CurTime = function() return time end
Advance = function(dt) time = time + dt end
player = { Alive = function() return true end }
Sessions = { Bandage = { [player] = { id = 10, limbId = "arm_R", slotIdx = 1,
    itemId = "GAUZE", lastInputAt = 200 } } }
net.ReadUInt = function() return 10 end
net.ReadFloat = function() return 360 end
ReadOptionalInputSeq = function() return 1 end
GetLimbState = function() return {} end
Fn = { GetBandageProfile = function() return { durabilityPerWrap = 10 } end }
slot = { durability = 100 }
ValidateToolSlot = function() return slot end
spent = 0
ConsumeToolDurability = function(_, _, cost) spent = spent + cost; return true end
BuildMedicalItemContext = function() return {} end
ApplyBandageProfile = function() return true end
SendLimbUpdate = function() end
SendMinigameAck = function() end
MINIGAME_ACK_BANDAGE = 1
WoundSystem.Health = { Constants = { BandageDurabilityPerWrap = 10 } }
''')
lua.execute(filter_fn)
lua.execute(receiver)
assert lua.execute(r'''
receiver(0, player)
for i = 1, 20 do receiver(0, player) end
local nativeLimited = math.abs(spent - 4) < 0.0001
local crossProtocol = WSZC.FilterBandageDegrees(player, 360, 200) == 0
Advance(0.5)
receiver(0, player)
return nativeLimited and crossProtocol and math.abs(spent - 14) < 0.0001
''')
print('PASS native and connector share a time budget across protocols')
print('TEST_OK 5 / 5')
