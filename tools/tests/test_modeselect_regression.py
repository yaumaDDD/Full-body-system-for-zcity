#!/usr/bin/env python3
"""Regression checks for the F6 admin/queue ZFrame nil-panel fix."""
import re
import runpy
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRY = 'z_city/gamemodes/zcity/gamemode/libraries/cl_modeselect_menu.lua'
FULL_ENTRY = 'garrysmod/addons/' + ENTRY
results = []


def check(name, ok):
    results.append((name, bool(ok)))


with zipfile.ZipFile(ROOT / 'zcity.zip') as z:
    original = z.read(ENTRY)
build_api = runpy.run_path(str(ROOT / 'tools/build_packs.py'))
patched = build_api['patch_modeselect_menu'](original)

check('S01 both admin and queue frames use DFrame only as fallback',
      patched.count(b'local frame = vgui.Create("ZFrame") or vgui.Create("DFrame")') == 2
      and patched.count(b'if frame.SetBorder then frame:SetBorder(false) end') == 2)
check('S02 rebuilding an already patched menu is idempotent',
      build_api['patch_modeselect_menu'](patched) == patched and patched != original)

try:
    from luaparser import ast
    # GMod's `continue` is a native extension; neutralize only that token for
    # the standard-Lua parser, leaving every patched expression untouched.
    lua_source = re.sub(r'\bcontinue\b', 'do end', patched.decode('utf-8-sig'))
    ast.parse(lua_source)
    parsed = True
except Exception as exc:
    print('ERR Lua parser', type(exc).__name__, str(exc)[:180])
    parsed = False
check('S03 patched cl_modeselect_menu.lua parses', parsed)

with zipfile.ZipFile(ROOT / 'zcity_full_pack.zip') as z:
    shipped = z.read(FULL_ENTRY)
    manifest = z.read('MANIFEST.txt').decode('utf-8')
    assert z.testzip() is None
check('S04 full pack ships the exact patch and documents it',
      shipped == patched and 'cl_modeselect_menu.lua' in manifest)

# The manifest itself is fed back into the next build.  Its patch section must
# survive that cycle exactly once, including the older woundbridge note.
dummy_entries = {'garrysmod/addons/z_city/probe.txt': b'probe'}
dummy_conn = {'lua/probe.lua': b'return true\n'}
manifest_once = build_api['build_manifest'](manifest, dummy_entries, dummy_conn).decode('utf-8')
manifest_twice = build_api['build_manifest'](manifest_once, dummy_entries, dummy_conn).decode('utf-8')
check('S05 repeated manifest builds keep both patch notes exactly once',
      manifest_once == manifest_twice
      and manifest_once.count('cl_modeselect_menu.lua') == 1
      and manifest_once.count('sv_woundbridge.lua') == 1)

for name, ok in results:
    print(('PASS ' if ok else 'FAIL ') + name)
passed = sum(1 for _, ok in results if ok)
print('TEST_OK %d / %d' % (passed, len(results)))
sys.exit(0 if passed == len(results) else 1)
