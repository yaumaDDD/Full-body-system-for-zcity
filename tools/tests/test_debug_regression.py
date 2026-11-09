#!/usr/bin/env python3
"""Private connector diagnostics: real shared logger in server/client realms."""
from pathlib import Path
import sys

sys.path.insert(0, '/tmp/lupa_pkg')
try:
    from lupa import LuaRuntime
except ImportError:
    print('SKIP runtime checks (lupa unavailable)')
    sys.exit(0)

ROOT = Path(__file__).resolve().parents[2]
shared = (ROOT / 'woundsystem_zcity_compat/lua/autorun/sh_zcity_woundsystem_compat.lua').read_text()
bootstrap = (ROOT / 'woundsystem_zcity_compat/lua/wszc_vendor/bootstrap.lua').read_text()
results = []

def check(label, ok):
    results.append(bool(ok))
    print(('PASS ' if ok else 'FAIL ') + label)

setup = r'''
LOGS, COMMANDS, MESSAGES, RECEIVERS, NETWORK = {}, {}, {}, {}, {}
print = function(...) local p = {}; for i=1,select('#',...) do p[#p+1]=tostring(select(i,...)) end; LOGS[#LOGS+1]=table.concat(p,' ') end
NULL = {}
IsValid = function(v) return v ~= nil and v ~= false and v ~= NULL end
HUD_PRINTCONSOLE = 4
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 1, 2, 4
ConVarExists = function() return false end
CreateConVar = function(name, value) return { GetBool = function() return value ~= '0' end } end
GetConVar = function() return nil end
AddCSLuaFile = function() end
include = function() return {} end
file = { Exists = function() return false end }
hook = { Add = function() end, Remove = function() end, GetTable = function() return {} end }
timer = { Simple = function() end, Create = function() end }
util = { AddNetworkString = function(name) NETWORK[name] = true end }
concommand = { GetTable = function() return COMMANDS end, Add = function(n, fn) COMMANDS[n] = fn end }
net = {
 Receive = function(n, fn) RECEIVERS[n] = fn end,
 Start = function(n) Pending = {name=n} end,
 WriteBool = function(v) Pending.value = v end,
 Send = function(ply) Pending.ply = ply; MESSAGES[#MESSAGES+1] = Pending end,
 ReadBool = function() return NetReadBool end,
}
SetGlobalBool = function() end
GetGlobalBool = function(_, fallback) return fallback end
function Player(admin)
 local ply = { admin = admin, messages = {} }
 ply.IsAdmin = function(self) return self.admin end
 ply.PrintMessage = function(self, kind, msg) self.messages[#self.messages+1] = msg end
 return ply
end
'''
server = LuaRuntime(unpack_returned_tuples=True)
server.execute('SERVER, CLIENT = true, false\n' + setup)
server.execute('PreviousCalls = 0; COMMANDS.debug = function() PreviousCalls = PreviousCalls + 1 end')
server.execute(shared)
server_results = server.execute(r'''
local admin, admin2, user = Player(true), Player(true), Player(false)
WSZC.Log('startup'); WSZC.Warn('failure'); WSZC.Debug('test %d', 1)
local quiet = #LOGS == 0 and #admin.messages == 0 and #user.messages == 0 and #WSZC.DebugHistory == 3
COMMANDS.debug(user, 'debug', {'wscz'}, 'wscz')
COMMANDS.wszc_compat_status(user)
local denied = #LOGS == 0 and #user.messages == 0 and #MESSAGES == 0 and not WSZC.DebugAllowed(user)
COMMANDS.debug(admin, 'debug', {'wscz'}, 'wscz')
local enabled = WSZC.DebugAllowed(admin) and not WSZC.DebugAllowed(admin2)
 and #admin.messages == 4 and #MESSAGES == 1 and MESSAGES[1].ply == admin and MESSAGES[1].value == true
WSZC.Warn('private'); WSZC.Debug('fracture %d', 7)
local private = #admin.messages == 6 and #admin2.messages == 0 and #user.messages == 0 and #LOGS == 0
COMMANDS.wszc_compat_status(user)
local statusBefore = #admin.messages
COMMANDS.wszc_compat_status(admin)
local afterDenied = #user.messages == 0 and #admin.messages > statusBefore
COMMANDS.debug(admin2, 'debug', {'wscz'}, 'wscz')
local second = WSZC.DebugAllowed(admin2) and #admin2.messages > 1
COMMANDS.debug(admin, 'debug', {'wscz'}, 'wscz')
local count = #admin.messages
WSZC.Log('after disable')
local off = #admin.messages == count and #admin2.messages > 1 and MESSAGES[3].value == false
admin2.admin = false
local count2 = #admin2.messages
WSZC.Log('after demotion')
local demoted = #admin2.messages == count2 and not WSZC.DebugAllowed(admin2)
COMMANDS.debug(user, 'debug', {'another_command'}, 'another_command')
local preserved = PreviousCalls == 1
for i=1, 200 do WSZC.Debug('line %d', i) end
local bounded = #WSZC.DebugHistory == 150 and string.find(WSZC.DebugHistory[150], 'line 200', 1, true) ~= nil
COMMANDS.debug(NULL, 'debug', {'wscz'}, 'wscz')
local console = WSZC.DebugConsole and #LOGS > 0
local before = #LOGS
COMMANDS.debug(NULL, 'debug', {'wscz'}, 'wscz')
WSZC.Warn('silent again')
local consoleOff = not WSZC.DebugConsole and #LOGS == before + 1
return quiet, denied, enabled and private and afterDenied and second, off and demoted,
       preserved and bounded and console and consoleOff
''')
for name, value in zip([
    'all connector logs are quiet by default',
    'non-admin cannot subscribe or see status',
    'only subscribed admins receive server diagnostics and history',
    'toggle and loss of admin rights revoke output',
    'existing debug command preserved, history bounded, server console opt-in',
], server_results): check(name, value)

client = LuaRuntime(unpack_returned_tuples=True)
client.execute('SERVER, CLIENT = false, true\n' + setup)
client.execute('Local = Player(false); LocalPlayer = function() return Local end')
client.execute(shared)
client_results = client.execute(r'''
WSZC.Warn('client startup')
local quiet = #LOGS == 0 and #WSZC.DebugHistory == 1
NetReadBool = true; RECEIVERS.WSZC_DebugControl()
COMMANDS.wszc_compat_client_status()
WSZC.Debug('should remain private')
local denied = #LOGS == 0 and not WSZC.DebugClient
Local.admin = true; NetReadBool = true; RECEIVERS.WSZC_DebugControl()
local enabled = WSZC.DebugClient and #LOGS == 3
WSZC.Log('client active')
local live = #LOGS == 4
Local.admin = false
WSZC.Warn('demoted')
local demoted = #LOGS == 4
Local.admin = true; NetReadBool = false; RECEIVERS.WSZC_DebugControl()
WSZC.Log('disabled')
local disabled = #LOGS == 4 and not WSZC.DebugClient
return quiet and denied, enabled and live, demoted and disabled
''')
for name, value in zip([
    'client diagnostics default to silent and non-admin cannot activate',
    'server enable lets only admin see buffered and live client diagnostics',
    'client demotion and disable immediately stop logging',
], client_results): check(name, value)

early = LuaRuntime(unpack_returned_tuples=True)
early.execute('SERVER, CLIENT = true, false\n' + setup)
early.execute('include = function() error("bootstrap test failure") end')
early.execute(shared)
check('early bootstrap failure is retained privately without a console message', early.execute(r'''
return #LOGS == 0 and #WSZC.DebugHistory == 1
    and string.find(WSZC.DebugHistory[1], "bootstrap test failure", 1, true) ~= nil
'''))

# The connector bootstrap reports through the same logger, without changing
# the byte-identical embedded or external ZCity/C:U source files.
check('bootstrap has no unconditional console logging', 'print(' not in bootstrap and 'WSZC.Log' in bootstrap)
print('TEST_OK %d / %d' % (sum(results), len(results)))
sys.exit(0 if all(results) else 1)
