#!/usr/bin/env python3
"""Persistent regression suite for the ZCity <-> Casualties: Unknown connector.

Earlier suites lived in /tmp and disappeared together with the sandbox scratch
space, so this one is committed.  It checks the shipped files, not a transient
build directory:

  * static markers for every previous live-screenshot fix,
  * runtime behaviour of the HUD filter, full-screen minigames, hand pivot and
    cursor hiding (lupa / LuaRuntime; skipped if lupa is unavailable),
  * the generated doll PNGs really form ONE seam-free silhouette (Pillow),
  * both ZIPs, the 647-material mirror and MANIFEST sha256.

Usage: python3 tools/tests/test_wszc_regression.py
"""
import glob
import hashlib
import io
import json
import os
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONN = ROOT / 'woundsystem_zcity_compat'
CLIENT = CONN / 'lua/autorun/client'
SERVER = CONN / 'lua/autorun/server'
LAYOUT = CLIENT / 'cl_zcity_woundsystem_compat_layout.lua'
ORGANISM = SERVER / 'sv_zcity_woundsystem_compat_organism.lua'

results = []


def check(name, ok):
    results.append((name, bool(ok)))


def check_raises_free(name, fn):
    try:
        check(name, fn())
    except Exception as exc:
        print('ERR', name, type(exc).__name__, str(exc)[:160])
        results.append((name, False))


def src(rel):
    return (ROOT / rel).read_text(encoding='utf-8')


# ---------------------------------------------------------------- static ----
layout_s = LAYOUT.read_text(encoding='utf-8')
organism_s = ORGANISM.read_text(encoding='utf-8')
generator_s = src('tools/build_unitmenu_materials.py')
readme_s = src('README.md')

check('S01 hidden-region filter is split into raw + whitelisted',
      'HiddenRegionRaw' in layout_s and 'WSZC.CUHudHiddenRegionRaw' in layout_s)
check('S02 doll / status / uiPoint materials are whitelisted',
      'DOLL_DRAW_MARKERS' in layout_s and 'IsDollDrawMaterial' in layout_s)
check('S03 material tracker installed by every Think path',
      'InstallMaterialTracker' in layout_s and layout_s.count('WSZC.InstallMaterialTracker()') >= 2)
check('S04 death-screen suppression keeps top priority',
      'if WSZC.CUDeathVisualsHidden == true then return true end' in layout_s)
check('S05 all minigames can be full-screen',
      'MinigameFullscreenNative' in layout_s and 'NativeFullscreenK' in layout_s)
check('S06 full-screen native defaults on, cursor hiding defaults on',
      '"zc_woundsystem_compat_fullscreen_native", "1"' in layout_s
      and '"zc_woundsystem_compat_hide_minigame_cursor", "1"' in layout_s)
check('S07 hand pivot + size cap convars exist',
      all(x in layout_s for x in ('hand_pivot_x', 'hand_pivot_y', 'hand_max_screen')))
check('S08 hand rect is derived from the cursor',
      'HandRectForCursor' in layout_s and '(0.5 - px) * nw' in layout_s)
check('S09 the OS cursor is blanked and restored',
      'SetCursor, panel, "blank"' in layout_s and 'RestoreMinigameCursor' in layout_s)
check('S10 glass shrapnel has both damage hooks',
      'hook.Add("EntityTakeDamage", "WSZC_GlassStrikePre"' in organism_s
      and 'hook.Add("PostEntityTakeDamage", "WSZC_GlassStrike"' in organism_s)
check('S11 reset keeps only the down structure and clears sprint penalties',
      '"canmove", "alive", "stun"' not in organism_s
      and 'ClearMovementPenalties' in organism_s
      and organism_s.count('ClearMovementPenalties(org)') >= 3)
check('S12 hemogen blood is explicitly untouched',
      'advancedblood/' not in ''.join(
          p.read_text(encoding='utf-8') for p in CONN.rglob('*.lua')))
check('S13 generator builds one union silhouette, not 15 separate rings',
      'ImageChops.lighter' in generator_s
      and 'MaxFilter(15)' in generator_s and 'MinFilter(15)' in generator_s
      and 'outline.crop(box)' in generator_s)
check('S14 docs describe the seamless doll, hand pivot and hidden cursor',
      'белых шв' in readme_s or 'белыми швами' in readme_s)

# Lua syntax (luaparser is optional).
try:
    sys.path.insert(0, '/tmp/luaparser_pkg')
    from luaparser import ast
    lua_files = sorted(glob.glob(str(CONN / 'lua/**/*.lua'), recursive=True))
    bad = []
    for f in lua_files:
        try:
            ast.parse(Path(f).read_text(encoding='utf-8'))
        except Exception as exc:
            bad.append((f, str(exc)[:120]))
    check('S15 ALL_LUA_OK %d/%d' % (len(lua_files) - len(bad), len(lua_files)), not bad and len(lua_files) == 11)
except ImportError:
    print('SKIP S15 luaparser unavailable')

# CJK check.
cjk = re.compile(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]')
bad_cjk = []
for p in list(ROOT.glob('*.md')) + list(CONN.rglob('*.md')) + list(CONN.rglob('*.lua')):
    if cjk.search(p.read_text(encoding='utf-8')):
        bad_cjk.append(str(p))
check('S16 CJK_CLEAN', not bad_cjk)

# -------------------------------------------------------------- materials ---
try:
    sys.path.insert(0, '/tmp/pil_pkg')
    from PIL import Image, ImageChops, ImageFilter
    geom_text = (CLIENT / 'wszc_unitmenu_geometry.lua').read_text(encoding='utf-8')
    geom = {m[0]: tuple(m[1:]) for m in re.findall(
        r'(\w+)\s*=\s*\{\s*cx\s*=\s*([\d.]+),\s*cy\s*=\s*([\d.]+),\s*w\s*=\s*(\d+),\s*h\s*=\s*(\d+)',
        geom_text)}
    assert len(geom) == 15, len(geom)
    limb_dir = CONN / 'materials/wszc/unitmenu/limbs'
    body = Image.new('L', (1500, 1500), 0)
    edges = Image.new('L', (1500, 1500), 0)
    for limb, (cx, cy, w, h) in geom.items():
        cx, cy, w, h = float(cx), float(cy), int(w), int(h)
        box = (round(cx - w / 2), round(cy - h / 2))
        fill = Image.open(limb_dir / (limb + '_fill.png')).convert('RGBA')
        edge = Image.open(limb_dir / (limb + '_edge.png')).convert('RGBA')
        assert fill.size == (w, h) and edge.size == (w, h), (limb, fill.size, edge.size, w, h)
        fa, ea = fill.getchannel('A'), edge.getchannel('A')
        flayer, elayer = Image.new('L', (1500, 1500), 0), Image.new('L', (1500, 1500), 0)
        flayer.paste(fa, box)
        elayer.paste(ea, box)
        body = ImageChops.lighter(body, flayer)
        edges = ImageChops.lighter(edges, elayer)
    mask = body.point(lambda p: 255 if p > 127 else 0)
    outer = ImageChops.subtract(mask.filter(ImageFilter.MaxFilter(7)), mask)
    interior = mask.filter(ImageFilter.MinFilter(11))
    seams = ImageChops.multiply(edges, interior)
    check('S17 doll has NO internal white seams', seams.getbbox() is None)
    check('S18 doll has a complete outer outline', outer.getbbox() is not None and edges.getbbox() is not None)
    check('S19 every outline pixel belongs to the outer contour',
          ImageChops.multiply(edges, ImageChops.invert(outer.filter(ImageFilter.MaxFilter(5)))).getbbox() is None)
    mats = [p for p in (CONN / 'materials').rglob('*') if p.is_file()]
    check('S20 connector ships 647 UI materials', len(mats) == 647)
    checksums = (CONN / 'MATERIALS.sha256').read_text(encoding='utf-8').splitlines()
    check('S21 MATERIALS.sha256 has 614 entries',
          len([l for l in checksums if l.strip() and not l.startswith('#')]) == 614)
except ImportError:
    print('SKIP S17-S21 Pillow unavailable')

# ------------------------------------------------------------------- ZIPs ---
def validate_zips():
    with zipfile.ZipFile(ROOT / 'woundsystem_zcity_compat.zip') as z:
        assert z.testzip() is None
        compat = {i.filename: z.read(i.filename) for i in z.infolist()}
    with zipfile.ZipFile(ROOT / 'zcity_full_pack.zip') as z:
        assert z.testzip() is None
        full = {i.filename: z.read(i.filename) for i in z.infolist()}
    conn_files = {p.relative_to(CONN).as_posix(): p.read_bytes() for p in CONN.rglob('*') if p.is_file()}
    assert len(conn_files) == len(compat) == 662
    assert all(compat['woundsystem_zcity_compat/' + r] == d for r, d in conn_files.items())
    mirror = {n[len('garrysmod/addons/casualties_unknown_health_system_beta/materials/'):]: d
              for n, d in full.items()
              if n.startswith('garrysmod/addons/casualties_unknown_health_system_beta/materials/')}
    assert len(mirror) == 647
    assert all(mirror[r[len('materials/'):]] == d for r, d in conn_files.items() if r.startswith('materials/'))
    assert json.loads(compat['woundsystem_zcity_compat/addon.json'])
    bridge = [n for n in full if n.endswith('woundbridge/sv_woundbridge.lua')]
    assert len(bridge) == 1 and b'Not completed - nothing was applied' not in full[bridge[0]]
    manifest = full['MANIFEST.txt'].decode('utf-8')
    shas = re.findall(r'woundsystem_zcity_compat/lua/[^\s]+\.lua\s+([0-9a-f]{64})', manifest)
    assert len(shas) == 11
    assert all(hashlib.sha256(d).hexdigest() in shas for r, d in conn_files.items() if r.endswith('.lua'))
    assert 'HandRectForCursor' in full['garrysmod/addons/woundsystem_zcity_compat/lua/autorun/client/cl_zcity_woundsystem_compat_layout.lua'].decode('utf-8')
    assert 'INSTALL_RU.md' not in full and 'zc_woundsystem_compat_fullscreen_native' in full['ZCity_binds.md'].decode('utf-8')
    assert len(full) == 2765
    return True


check_raises_free('S22 FULL_ZIP_OK / COMPAT_ZIP_OK / MANIFEST_OK / MIRROR_OK', validate_zips)

# --------------------------------------------------------------- runtime ----
try:
    sys.path.insert(0, '/tmp/lupa_pkg')
    from lupa import LuaRuntime
except ImportError:
    LuaRuntime = None

if LuaRuntime is None:
    print('SKIP R01-R16 lupa unavailable')
else:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
CLIENT = true; SERVER = false
math.Clamp = function(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end
CurTime = function() return 100 end
RealTime = function() return 100 end
FrameTime = function() return 0.016 end
ScrW = function() return 1000 end
ScrH = function() return 1000 end
IsValid = function(v) return v ~= nil end
GetConVar = function() return nil end
ConVarExists = function() return false end
GetGlobalBool = function(_, fb) return fb end
LocalPlayer = function() return { Alive = function() return true end } end
ErrorNoHalt = function() end
Lerp = function(t, a, b) return a + (b - a) * t end
convars = {}
CreateClientConVar = function(name, def, _, _, _, lo, hi)
    local cv = { _v = def,
        GetBool = function(s) return s._v == "1" end,
        GetFloat = function(s) return tonumber(s._v) or 0 end }
    convars[name] = cv
    return cv
end
hook = { _t = {},
    Add = function(e, n, f) hook._t[e] = hook._t[e] or {}; hook._t[e][n] = f end,
    Remove = function(e, n) if hook._t[e] then hook._t[e][n] = nil end end,
    GetTable = function() return hook._t end }
include = function() end
timer = { Simple = function() end, Create = function() end, Remove = function() end }
cursorValue = "arrow"
worldPanel = { SetCursor = function(_, v) cursorValue = v end,
               GetCursor = function() return cursorValue end }
vgui = { GetWorldPanel = function() return worldPanel end,
         CursorVisible = function() return true end }
gui = { EnableScreenClicker = function(on) clickerOn = on end,
        MousePos = function() return 500, 400 end }
clickerOn = false
input = { IsMouseDown = function() return false end, IsKeyDown = function() return false end }
net = { Receive = function() end, Start = function() end, SendToServer = function() end }
MOUSE_LEFT, MOUSE_RIGHT, KEY_ESCAPE = 107, 108, 70
WoundSystem = { MinigameClip = {
                    Scale = function() return 1000 / 1080 end,
                    GetRect = function() return 260, 40, 760, 760, 18 end,
                    Begin = function() return false end, End = function() end,
                    DrawExitGuide = function() end },
                Client = { RequestInventoryMove = function() end }, HealthGUI = {} }
WoundSystemHealthHUDOpen = false
WoundSystemInventorySlots, WoundSystemDragState, WoundSystemWorldDrag = {}, {}, {}
draw = { SimpleText = function() end, SimpleTextOutlined = function() end,
         RoundedBox = function() end }
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
surfaceCalls = {}
surface = {
    SetMaterial = function(m) table.insert(surfaceCalls, { kind = "mat", m = m }) end,
    SetDrawColor = function() end,
    DrawTexturedRect = function(x, y, w, h)
        table.insert(surfaceCalls, { kind = "rect", x = x, y = y, w = w, h = h }) end,
    DrawTexturedRectUV = function(x, y, w, h)
        table.insert(surfaceCalls, { kind = "uv", x = x, y = y, w = w, h = h }) end,
    DrawTexturedRectRotated = function(x, y, w, h, rot)
        table.insert(surfaceCalls, { kind = "rot", x = x, y = y, w = w, h = h, rot = rot }) end,
    DrawRect = function(x, y, w, h)
        table.insert(surfaceCalls, { kind = "filled", x = x, y = y, w = w, h = h }) end,
    DrawOutlinedRect = function(x, y, w, h)
        table.insert(surfaceCalls, { kind = "outline", x = x, y = y, w = w, h = h }) end,
    DrawLine = function() end, DrawPoly = function() end, DrawText = function() end,
}
MATERIAL_CACHE = {}
Material = function(path)
    if MATERIAL_CACHE[path] then return MATERIAL_CACHE[path] end
    local m = { _path = path, IsError = function() return false end,
        Width = function() return 64 end, Height = function() return 64 end,
        GetName = function(s) return s._path end }
    MATERIAL_CACHE[path] = m
    return m
end
file = { Exists = function(p) return p == "materials/homigrad/handanim/hand.png" end }
Icons = { fracture = Material("cu/fracture") }
WoundSystemDislocationMinigame, WoundSystemShrapnelMinigame = { active = false }, { active = false }
WSZC = { WSZCMinigameActive = function() return false end }
''')
    lua.execute((CLIENT / 'wszc_unitmenu_geometry.lua').read_text(encoding='utf-8'))
    lua.execute(layout_s)

    def rt(name, code):
        try:
            check(name, bool(lua.eval(code)))
        except Exception as exc:
            print('ERR', name, type(exc).__name__, str(exc)[:160])
            results.append((name, False))

    rt('R01 installers come up', '''
(function()
    WSZC.NextCUInventoryInstall = 0
    hook._t["Think"]["WSZC_CUInventoryLayout"]()
    hook._t["Think"]["WSZC_FullscreenClipInit"]()
    return WSZC.InstallMaterialTracker() and WSZC.ApplyFullscreenClip()
       and WSZC.InstallNativeHandOverride()
end)()
''')

    rt('R02 slot outlines hidden, doll limb drawn', '''
(function()
    WSZC.CUHudFiltered = true; WSZC.CUDeathVisualsHidden = false
    surfaceCalls = {}
    surface.SetMaterial(Material("wszc/unitmenu/limbs/head_fill.png"))
    surface.DrawOutlinedRect(100, 800, 80, 80)
    surface.SetMaterial(Material("wszc/unitmenu/limbs/foot_R_fill.png"))
    surface.DrawTexturedRect(100, 800, 80, 80)
    local outline, limb = 0, 0
    for _, c in ipairs(surfaceCalls) do
        if c.kind == "outline" then outline = outline + 1 end
        if c.kind == "rect" then limb = limb + 1 end
    end
    return outline == 0 and limb == 1
end)()
''')

    rt('R03 action-point label survives without its black backing', '''
(function()
    WSZC.CUHudFiltered = true
    surface.SetMaterial(Material("casunknown-images/screen/uiPoint.png"))
    return WSZC.CUHudHiddenRegion(100, 380, 180, 24) == false
       and WSZC.CUHudHiddenRegionRaw(100, 380, 180, 24) == true
end)()
''')

    rt('R04 death screen beats both filters', '''
(function()
    WSZC.CUDeathVisualsHidden = true
    WSZC._DrawMaterialName = "wszc/unitmenu/limbs/head_fill.png"
    local a = WSZC.CUHudHiddenRegion(100, 100, 80, 80)
    local b = WSZC.CUHudHiddenRegionRaw(100, 100, 80, 80)
    WSZC.CUDeathVisualsHidden = false
    return a and b
end)()
''')

    rt('R05 native minigames are full-screen with a grown scale', '''
(function()
    convars["zc_woundsystem_compat_fullscreen_minigame"]._v = "1"
    convars["zc_woundsystem_compat_fullscreen_native"]._v = "1"
    WoundSystemShrapnelMinigame = { active = true }
    local x, y, w, h, r = WoundSystem.MinigameClip.GetRect()
    local s = WoundSystem.MinigameClip.Scale()
    WoundSystemShrapnelMinigame = { active = false }
    return x == 0 and y == 0 and w == 1000 and h == 1000 and r == 0 and s > 1
end)()
''')

    rt('R06 fullscreen_native 0 restores the 570 px square', '''
(function()
    convars["zc_woundsystem_compat_fullscreen_native"]._v = "0"
    WoundSystemDislocationMinigame = { active = true }
    local x, y, w, h, r = WoundSystem.MinigameClip.GetRect()
    WoundSystemDislocationMinigame = { active = false }
    convars["zc_woundsystem_compat_fullscreen_native"]._v = "1"
    return w == 570 and h == 570 and r < 18
end)()
''')

    rt('R07 the hand grip point lands exactly on the cursor', '''
(function()
    WoundSystemShrapnelMinigame = { active = true }
    surfaceCalls = {}
    surface.SetMaterial(Material("casunknown-images/shrapnelminigame/handGraspIdle1.png"))
    surface.DrawTexturedRectRotated(500, 400, 512, 1260, 290)
    WoundSystemShrapnelMinigame = { active = false }
    local c = surfaceCalls[#surfaceCalls]
    if not c or c.kind ~= "rot" then return false end
    local px, py = WSZC.HandPivot()
    return math.abs((c.x + (px - 0.5) * c.w) - 500) < 0.001
       and math.abs((c.y + (py - 0.5) * c.h) - 400) < 0.001
end)()
''')

    rt('R08 hand rotation is forced to zero', '''
(function()
    WoundSystemShrapnelMinigame = { active = true }
    surfaceCalls = {}
    surface.SetMaterial(Material("casunknown-images/shrapnelminigame/handGraspClick.png"))
    surface.DrawTexturedRectRotated(500, 400, 512, 1260, 290)
    WoundSystemShrapnelMinigame = { active = false }
    return surfaceCalls[#surfaceCalls].rot == 0
end)()
''')

    rt('R09 hand width is capped at 34% of the screen', '''
(function()
    local x, y, w, h = WSZC.HandRectForCursor(500, 400, 5000, 12000)
    return w <= 340.001 and w > 0 and h > 0
end)()
''')

    rt('R10 cursor is blank while a minigame is open', '''
(function()
    cursorValue = "arrow"
    WoundSystemShrapnelMinigame = { active = true }
    WSZC.SyncMinigameCursor()
    local hidden = cursorValue == "blank"
    WoundSystemShrapnelMinigame = { active = false }
    WSZC.SyncMinigameCursor()
    return hidden and cursorValue == "arrow"
end)()
''')

    rt('R11 enabling the screen clicker re-blanks the cursor', '''
(function()
    cursorValue = "arrow"
    WoundSystemDislocationMinigame = { active = true }
    WSZC.SyncMinigameCursor()
    cursorValue = "arrow"
    gui.EnableScreenClicker(true)
    local ok = cursorValue == "blank"
    WoundSystemDislocationMinigame = { active = false }
    WSZC.SyncMinigameCursor()
    return ok
end)()
''')

    rt('R12 hide_minigame_cursor 0 restores the arrow', '''
(function()
    convars["zc_woundsystem_compat_hide_minigame_cursor"]._v = "0"
    cursorValue = "blank"
    WoundSystemShrapnelMinigame = { active = true }
    WSZC.SyncMinigameCursor()
    WoundSystemShrapnelMinigame = { active = false }
    convars["zc_woundsystem_compat_hide_minigame_cursor"]._v = "1"
    return cursorValue == "arrow"
end)()
''')

    rt('R13 no minigame => no blank cursor', '''
(function()
    cursorValue = "arrow"
    WSZC.SyncMinigameCursor()
    return cursorValue == "arrow"
end)()
''')

    rt('R14 a dead player is never treated as in a minigame', '''
(function()
    local old = LocalPlayer
    LocalPlayer = function() return { Alive = function() return false end } end
    WoundSystemShrapnelMinigame = { active = true }
    cursorValue = "arrow"
    WSZC.SyncMinigameCursor()
    WoundSystemShrapnelMinigame = { active = false }
    LocalPlayer = old
    return cursorValue == "arrow"
end)()
''')

    rt('R15 unitmenu doll defaults and hand pivots', '''
(function()
    return convars["zc_woundsystem_compat_unitmenu_scale"]._v == "0.24"
       and convars["zc_woundsystem_compat_hand_pivot_x"]._v == "0.16"
       and convars["zc_woundsystem_compat_hand_pivot_y"]._v == "0.45"
       and convars["zc_woundsystem_compat_unitmenu_doll"]._v == "1"
end)()
''')

    rt('R16 geometry table has all 15 limbs', '''
(function()
    local n = 0
    for _ in pairs(WSZC_UNITMENU_LIMB_GEOMETRY) do n = n + 1 end
    return n == 15 and WSZC_UNITMENU_LIMB_GEOMETRY.head.w > 0
end)()
''')

for name, ok in results:
    print(('PASS ' if ok else 'FAIL ') + name)
passed = sum(1 for _, ok in results if ok)
print('TEST_OK %d / %d' % (passed, len(results)))
sys.exit(0 if passed == len(results) else 1)
