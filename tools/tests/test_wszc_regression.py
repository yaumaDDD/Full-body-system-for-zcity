#!/usr/bin/env python3
"""Persistent regression suite for the ZCity <-> Casualties: Unknown connector.

Earlier suites lived in /tmp and disappeared together with the sandbox scratch
space, so this one is committed.  It checks the shipped files, not a transient
build directory:

  * static markers for every previous live-screenshot fix,
  * the human-proportioned doll: STANDARD BLACK fill, a thin outline following
    EACH limb's shape (never a rectangular sprite frame), and C:U's untouched
    hover colour on the outline,
  * minigame text is removed by a font-scoped filter only, so ZCity
    notifications / AED status labels / death text / icons all survive,
  * runtime behaviour of the HUD filter, full-screen minigames, hand pivot and
    cursor hiding (lupa / LuaRuntime; skipped if lupa is unavailable),
  * both ZIPs, the 654-material mirror and MANIFEST sha256.

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
REMOTE_SERVER = SERVER / 'sv_zcity_woundsystem_compat_remote.lua'
REMOTE_CLIENT = CLIENT / 'cl_zcity_woundsystem_compat_remote.lua'

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
remote_server_s = REMOTE_SERVER.read_text(encoding='utf-8')
remote_client_s = REMOTE_CLIENT.read_text(encoding='utf-8')
minigames_s = (CLIENT / 'cl_zcity_woundsystem_compat_minigames.lua').read_text(encoding='utf-8')
inspect_s = (CLIENT / 'cl_zcity_woundsystem_compat_inspect.lua').read_text(encoding='utf-8')
shared_s = (CONN / 'lua/autorun/sh_zcity_woundsystem_compat.lua').read_text(encoding='utf-8')
server_minigames_s = (SERVER / 'sv_zcity_woundsystem_compat_minigames.lua').read_text(encoding='utf-8')
bandage_client_s = (CLIENT / 'wszc_cl_bandage.lua').read_text(encoding='utf-8')
generator_s = src('tools/build_unitmenu_materials.py')
readme_s = src('README.md')
install_ru_s = src('INSTALL_RU.md')
binds_s = src('ZCity_binds.md')
compat_readme_s = src('woundsystem_zcity_compat/README.md')
source_index_s = src('woundsystem_zcity_compat/SOURCE_INDEX.md')
all_docs = '\n'.join((readme_s, install_ru_s, binds_s,
                      compat_readme_s, source_index_s))

check('S01 hidden-region filter is split into raw + whitelisted',
      'HiddenRegionRaw' in layout_s and 'WSZC.CUHudHiddenRegionRaw' in layout_s)
check('S02 doll / status / uiPoint materials are whitelisted',
      'DOLL_DRAW_MARKERS' in layout_s and 'IsDollDrawMaterial' in layout_s)
check('S03 material tracker + text filter installed by Think paths',
      'InstallMaterialTracker' in layout_s
      and layout_s.count('WSZC.InstallMaterialTracker()') >= 2
      and layout_s.count('WSZC.InstallMinigameTextFilter()') >= 1)
check('S04 death-screen suppression keeps top priority',
      'if WSZC.CUDeathVisualsHidden == true then return true end' in layout_s)
check('S05 WSZC minigames stay full-screen; native C:U games keep authored geometry',
      'MinigameFullscreenNative' in layout_s and 'NativeFullscreenK' in layout_s
      and 'WSZC.WSZCMinigameActive()' in layout_s)
check('S06 native geometry uses a moderate 0.85 zoom; C:U human hand is the default',
      '"zc_woundsystem_compat_fullscreen_native", "0"' in layout_s
      and '"zc_woundsystem_compat_native_minigame_zoom", "0.85"' in layout_s
      and '"zc_woundsystem_compat_minigame_zoom", "0.85"' in layout_s
      and '"zc_woundsystem_compat_hide_minigame_cursor", "1"' in layout_s
      and '"zc_woundsystem_compat_hide_minigame_hand", "0"' in layout_s
      and '"zc_woundsystem_compat_handanim", "1"' in layout_s)
check('S07 hand pivot + native scale convars exist',
      all(x in layout_s for x in ('hand_pivot_x', 'hand_pivot_y', 'hand_max_screen')))
check('S08 compact hand anchors the rotated pivot, aspect and native rotation',
      'HandRectForCursor' in layout_s
      and 'return WSZC.HandRectAtPivot(cx, cy, nw, nh, rot, px, py)' in layout_s
      and 'cvHandScale:GetFloat() * cvHandanimScale:GetFloat()' in layout_s
      and 'WSZC.HandRectForCursor(x, y, w, h, rot)' in layout_s
      and 'origRectRotated(nx, ny, nw, nh, rot, ...)' in layout_s
      and 'UnitmenuHandRotatedCenter' not in layout_s)
check('S09 every active minigame blanks world + overlay cursor, even without hand art',
      'function WSZC.BlankMinigameCursor()' in layout_s
      and 'if not cvHideCursor:GetBool() then' in layout_s
      and 'panel.SetCursor, panel, "arrow"' in layout_s
      and 'panel.SetCursor, panel, "blank"' in layout_s
      and 'if active and cvHideCursor:GetBool() then' in layout_s
      and 'SetMinigameOverlayCursors("blank")' in layout_s
      and 'SetMinigameOverlayCursors("arrow")' in layout_s
      and 'if active and cvHideCursor:GetBool() and WSZC.ShowMinigameHand() then' not in layout_s
      and 'if WSZC.SyncMinigameCursor then WSZC.SyncMinigameCursor() end' in layout_s
      and 'WSZC.RestoreMinigameCursor(true)' in layout_s)
check('S09b radial legacy medicine is filtered and rendered reduction has a namespaced packet',
      'zzzz_WSZC_DisableLegacyMedicine' in inspect_s
      and 'WSZC.IsLegacyRadialMedicalOption' in inspect_s
      and 'WSZC_DislocationVisualCompletion' in minigames_s
      and 'net.WriteFloat(x)' in minigames_s and 'net.WriteFloat(y)' in minigames_s
      and '"WSZC_DislocationVisualComplete"' in server_minigames_s
      and 'function WSZC.DislocationVisualAligned' in shared_s)
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
check('S13 generator: standard black, anatomy kept, per-limb shaped outline, NO frames',
      'HUMAN_LAYOUT' in generator_s
      and 'REFERENCE_BOXES' in generator_s
      and 'DOLL_RGB = (0, 0, 0)' in generator_s
      and 'ALPHA_THRESHOLD = 96' in generator_s
      and 'EDGE_PAD_MIN = 6' in generator_s
      and 'JOINT_ERODE = 3' in generator_s
      and 'LIVE_S = 0.4155' in generator_s
      and 'LIVE_CX, LIVE_CY = 682.5, 558.2' in generator_s
      and 'assert w == next_pot(w) and h == next_pot(h)' in generator_s
      and 'ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(edge_width)))' in generator_s
      and 'outer_band' not in generator_s
      and 'union = ImageChops.lighter(union, layer)' not in generator_s
      and 'MaxFilter(15)' not in generator_s
      and 'transparent sprite' not in generator_s)
check('S14 docs describe human proportions, restored outline, hover, no minigame text',
      'человеческ' in all_docs.lower()
      and 'бел' in all_docs.lower() and 'обводк' in all_docs.lower()
      and 'наведен' in all_docs.lower()
      and 'hide_minigame_text' in all_docs
      and 'без белой обводки' not in all_docs
      and 'полностью прозрачный `_edge`' not in all_docs)
check('S23 WoundView dark backdrop is suppressed only while the HUD is open',
      'zc_woundsystem_compat_hide_woundview_backdrop' in layout_s
      and 'WoundSystemHealthHUDOpen == true' in layout_s)
check('S24 muscle-damage tint is for *_fill.png ONLY without flashAlpha blink (outline hover stays C:U-owned)',
      'zc_woundsystem_compat_unitmenu_tint' in layout_s
      and 'DollLimbFillDrawColor' in layout_s
      and 'DollLimbIdFromMaterial' in layout_s
      and 'IsDollLimbMaterial' in layout_s
      and 'lower:find("_fill", 1, true)' in layout_s
      and 'DollMiddleKind' not in layout_s)
check('S25 shared cursor pin drives both gameplay state and visible hand',
      'zc_woundsystem_compat_hand_pin_cursor' in layout_s
      and 'PinNativeHandToCursor' in layout_s
      and 'function WSZC.PinMinigameHandToCursor(mg)' in layout_s
      and 'function WSZC.InstallNativeHandPhysicsPin()' in layout_s
      and 'WSZC.InstallNativeHandPhysicsPin()' in layout_s
      and 'mg.handScreenX, mg.handScreenY = mx, my' in layout_s
      and 'mg.handScreenVelX, mg.handScreenVelY = 0, 0' in layout_s)
check('S26 human hand is default; arrow remains optional; status texts untouched',
      '"zc_woundsystem_compat_handanim", "1"' in layout_s
      and '"zc_woundsystem_compat_hide_minigame_hand", "0"' in layout_s
      and 'HGNotificationsThink' not in layout_s
      and 'panel.SetCursor, panel, "arrow"' in layout_s
      and 'panel.SetCursor, panel, "blank"' in layout_s)
check('S27 the rejected native-doll experiment is fully rolled back',
      'cvNativeDoll' not in layout_s
      and 'native_doll' not in layout_s
      and 'DollMiddleKind' not in layout_s
      and '"native"' not in layout_s)
check('S28 minigame text convar defaults on, filter is shared by all games',
      '"zc_woundsystem_compat_hide_minigame_text", "1"' in layout_s
      and 'function WSZC.InstallMinigameTextFilter()' in layout_s
      and 'MINIGAME_TEXT_BASES' in layout_s)
check('S29 font filter covers ALL minigame fonts incl. AED, but no ZCity fonts',
      'function WSZC.IsMinigameTextFont(font)' in layout_s
      and 'font:match("^(.-)_%d+$")' in layout_s
      and 'WSZC.MinigameTextHidden() and WSZC.IsMinigameTextFont(font)' in layout_s
      and 'WoundSystemAEDStatus = true' in layout_s
      and 'WoundSystemSelfHarmMinigame' in layout_s
      and 'WSZC.MinigameTextHidden()' in layout_s
      and 'BerserkFont = true' not in layout_s
      and 'ZB_ProotOSMedium = true' not in layout_s)
check('S30 DrawHeader keeps the icon but blanks text + top bar; backdrop KEPT',
      'clip._WSZCOrigDrawHeader' in layout_s
      and 'clean.title, clean.value, clean.guide' in layout_s
      and 'clean.panelAlpha = 0' in layout_s
      and 'clip["_WSZCOrig" .. name] = orig' in layout_s
      and '{"DrawExitGuide"}' in layout_s
      and 'clip._WSZCBackdropWrapped' in layout_s
      and 'WSZC._MinigameBackdropDrawing = true' in layout_s
      and 'if WSZC._MinigameBackdropDrawing == true then return false end' in layout_s
      and 'function WSZC.MinigameDrawnRecently()' in layout_s
      and 'WSZC._HoldMinigameCursor == true' in layout_s)
check('S31 wound FRONT LAYER + gameplay sprites are protected, never suppressed',
      'MINIGAME_WOUND_MARKER = "minigameshrapnel"' in layout_s
      and 'function WSZC.IsMinigameWoundLayer(name)' in layout_s
      and 'function WSZC.IsMinigameGameplaySprite(name)' in layout_s
      and 'WSZC.IsMinigameBoardMaterial = WSZC.IsMinigameWoundLayer' in layout_s
      and 'IsMinigameGameplaySprite(WSZC._DrawMaterialName)' in layout_s
      and 'NO DrawTexturedRect suppression here' in layout_s
      and 'and WSZC.IsMinigameBoardMaterial(WSZC._DrawMaterialName) then' not in layout_s
      and 'local origBoardRect = surface.DrawTexturedRect' not in layout_s)
check('S32 FindCULimbs has fallbacks + a PreDrawHUD retry',
      'function WSZC.FindCULimbs' not in layout_s
      and 'local function FindCULimbs()' in layout_s
      and 'cachedCULimbs' in layout_s
      and 'WSZC.ClearCULimbsCache' in layout_s
      and 'hook.Add("PreDrawHUD", "WSZC_UnitmenuDollRetry"' in layout_s
      and 'HUDPaintBackground' in layout_s)
# The supplied green WoundView reference (2222.png) is the source of truth.
# Every visible black silhouette is calibrated independently, then C:U's
# placement is inverted and each PNG cell is rounded to a power of two.
check('S33 REFERENCE_BOXES = green reference, independent POT-calibrated limbs',
      "'head':      (688.5, 279.5, 64.3, 83.3)" in generator_s
      and "'neck':      (688.0, 326.5, 79.8, 23.3)" in generator_s
      and "'thorax':    (687.5, 396.5, 119.3, 124.3)" in generator_s
      and "'abdomen':   (687.0, 488.0, 122.3, 68.0)" in generator_s
      and "'pelvis':    (687.0, 553.0, 122.3, 66.0)" in generator_s
      and "'arm_R':     (594.9, 376.0, 79.8, 62.8)" in generator_s
      and "'arm_L':     (785.6, 378.0, 83.3, 61.3)" in generator_s
      and "'forearm_R': (505.0, 369.0, 106.8, 41.3)" in generator_s
      and "'forearm_L': (869.5, 369.5, 90.3, 38.3)" in generator_s
      and "'hand_R':    (427.0, 369.0, 56.0, 47.5)" in generator_s
      and "'hand_L':    (939.0, 367.0, 56.0, 46.5)" in generator_s
      and "'thigh_R':   (661.0, 638.0, 59.8, 108.8)" in generator_s
      and "'thigh_L':   (714.0, 638.5, 55.3, 108.8)" in generator_s
      and "'crus_R':    (659.0, 739.0, 49.3, 102.3)" in generator_s
      and "'crus_L':    (718.0, 740.0, 49.3, 104.8)" in generator_s
      and "'foot_R':    (654.0, 814.0, 49.8, 51.8)" in generator_s
      and "'foot_L':    (724.5, 813.0, 50.3, 51.3)" in generator_s
      and 'woundview_reference_1365x1079.png' in generator_s
      and '2222.png' in generator_s
      and 'independently for every limb' in generator_s
      and 'tools/fit_unitmenu_geometry.py' in generator_s
      and 'EDGE_WIDTH = 17' in generator_s
      and 'EDGE_PAD_MIN = 6' in generator_s
      and 'DOLL_RGB = (0, 0, 0)' in generator_s
      and 'hoverW = %d, hoverH = %d' in generator_s
      and 'limb.sourceW = g.hoverW or g.w' in layout_s
      and 'limb.sourceH = g.hoverH or g.h' in layout_s)
check('S42 glass alone maps to hands/feet; shotgun + blast keep the actual limb',
      'local GLASS_SHRAPNEL_LIMBS = {' in organism_s
      and 'hand_R = true, hand_L = true,' in organism_s
      and 'foot_R = true, foot_L = true,' in organism_s
      and 'function WSZC.ShrapnelSpawnLimb(limbId)' in organism_s
      and 'if reason == "glass" then\n        limbId = ShrapnelSpawnLimb(limbId)\n    else\n        limbId = NormalizeLimb(limbId)' in organism_s
      and 'if reason ~= "glass" then return false end' in organism_s
      and 'state = ShrapnelState(ply, "hand_R")' in organism_s
      and 'limbId = limbId or "thorax"' not in organism_s
      and 'WSZC.AddShrapnel(ply, limbId, shotgunAdded, "shotgun")' in organism_s
      and 'WSZC.AddShrapnel(ply, limbId, blastAdded, "blast")' in organism_s
      and 'WSZC.AddShrapnel(ply, limbId, 1, "glass")' in organism_s)
check('S43 marked limb gets 3..5 fragments, persistence/ragdoll untouched',
      'SHRAPNEL_MIN_PIECES = 3' in organism_s
      and 'SHRAPNEL_MAX_PIECES = 5' in organism_s
      and 'count + 2' in organism_s
      and 'math.min(SHRAPNEL_MAX_PIECES, MaxShrapnel())' in organism_s
      and 'WSZC.ReconcileSpawnShrapnel' in organism_s
      and 'hook.Add("Fake", "WSZC_ShrapnelRagdollKeep"' in organism_s
      and 'hook.Add("FakeUp", "WSZC_ShrapnelRagdollKeep"' in organism_s
      and 'RestoreBones' in organism_s)
check('S34 docs no longer claim the rejected transparent-edge build',
      'без белой обводки' not in all_docs
      and 'прозрачный `_edge`' not in all_docs)
check('S38 hand can move: no zeroed mouse delta and no extra maxLength cap',
      minigames_s.count('cmd:SetMouseX(0)') == 0
      and minigames_s.count('cmd:SetMouseY(0)') == 0
      and 'opts.maxLength = 45' not in layout_s
      and 'Do NOT force `opts.maxLength` here' in layout_s
      and 'DO NOT zero cmd:SetMouseX / SetMouseY here' in minigames_s
      and 'MouseX/MouseY are intentionally NOT zeroed in SetupMove' in minigames_s
      and 'cmd:SetViewAngles(ang)' in minigames_s
      and 'return nil' in minigames_s)
check('S45 minigame cursor is held for games our IsActive() probes miss',
      'WSZC.MinigameDrawnRecently and WSZC.MinigameDrawnRecently()' in minigames_s
      and 'WSZC._CUMinigameActiveWrapper == WoundSystemIsAnyWoundMinigameActive' in minigames_s
      and 'WSZC._AllowClickerRelease = true' in minigames_s
      and 'WSZC._HoldMinigameCursor = running and true or false' in minigames_s
      and 'WSZC._NextCursorFix = now + 0.05' in minigames_s
      and minigames_s.count('cmd:SetMouseX(0)') == 0
      and minigames_s.count('cmd:SetMouseY(0)') == 0)
_enable_cursor_block = minigames_s.split('local function EnableMinigameClicker()', 1)[1].split('\nend', 1)[0]
check('S53 cursor watchdog never reasserts the arrow over an active hand',
      'if WSZC.SyncMinigameCursor then WSZC.SyncMinigameCursor() end' in _enable_cursor_block
      and 'RestoreMinigameCursor' not in _enable_cursor_block
      and 'producing the visible arrow flicker' in _enable_cursor_block)
check('S54 native and WSZC bandage hands share pivot; pin removes C:U offset/inertia',
      'function WSZC.HandRectAtPivot(cx, cy, w, h, rot, px, py)' in layout_s
      and 'return cx + lx * c - ly * s, cy + lx * s + ly * c, w, h' in layout_s
      and 'return WSZC.HandRectAtPivot(cx, cy, nw, nh, rot, px, py)' in layout_s
      and 'handTargetX, handTargetY, handDrawW, handDrawH, angle, handPivotX, handPivotY' in bandage_client_s
      and 'local handTargetX, handTargetY = screenX, screenY' in bandage_client_s
      and 'WSZC.PinMinigameHandToCursor(MG)' in bandage_client_s
      and 'if not cursorPinned then' in bandage_client_s
      and 'HandRectAtPivot(\n                handX, handY' not in bandage_client_s
      and 'handX + (handDrawW * handPivotX)' not in bandage_client_s)
check('S55 moderate zoom scales both native clipping and native hitbox coordinates',
      'return base * math.Clamp(cvNativeZoom:GetFloat(), 0.4, 1.2)' in layout_s
      and 'WSZC.NativeMinigameActive() and not WSZC.MinigameFullscreenNative()' in layout_s
      and '{ cvZoom, 0.85 }, { cvNativeZoom, 0.85 }' in layout_s
      and 'cvHandModeRevision:GetFloat() >= 6' in layout_s)
# One fracture / one dislocation point per arm or leg (owner 2026-11-05).
# Parse the actual Lua anchor table so a future edit cannot silently smear
# bone states back onto all three C:U limbs of an arm/leg.
import re as _re
_anchor = _re.search(r'local BONE_ANCHOR = \{(.*?)\n\}', organism_s, _re.S)
_anchor_sets = {}
if _anchor:
    for _kind, _body in _re.findall(r'(\w+)\s*=\s*\{(.*?)\}', _anchor.group(1), _re.S):
        _anchor_sets[_kind] = set(_re.findall(r'(\w+)\s*=\s*true', _body))
_disloc = _re.search(r'local DISLOC_FLAGS = \{(.*?)\n\}', organism_s, _re.S)
_disloc_limbs = _re.findall(r'\{ "(\w+)" \}', _disloc.group(1)) if _disloc else []
check('S46 one fracture point (middle limb) + one dislocation point (limb above)',
      _anchor_sets.get('fracture') ==
          {'forearm_L', 'forearm_R', 'crus_L', 'crus_R'}
      and _anchor_sets.get('dislocation') ==
          {'arm_L', 'arm_R', 'thigh_L', 'thigh_R'}
      and len(_disloc_limbs) == 4
      and set(_disloc_limbs) == {'arm_L', 'arm_R', 'thigh_L', 'thigh_R'}
      and 'if not BoneAnchor(limbId, "fracture") then return false end' in organism_s
      and organism_s.count('BoneAnchor(limbId, "dislocation")') == 3
      and 'limbSet("broken", fractured)' in organism_s
      and 'limbSet("boneHealTimer", fractured and math.Clamp(dmg * 100, 0, 100) or 0)' in organism_s
      and 'limbSet("dislocated", out)' in organism_s
      and 'WSZC.BoneAnchor = BoneAnchor' in organism_s)
check('S47 human hand + hidden arrow, action button offset, post-game release',
      '"zc_woundsystem_compat_hide_minigame_cursor", "1"' in layout_s
      and '"zc_woundsystem_compat_hide_minigame_hand", "0"' in layout_s
      and '"zc_woundsystem_compat_handanim", "1"' in layout_s
      and '"zc_woundsystem_compat_hand_pin_cursor", "1"' in layout_s
      and 'function WSZC.ShowMinigameHand()' in layout_s
      and 'if cvHideHand:GetBool() then return 0 end' in layout_s
      and 'if handHide then' in layout_s
      and 'WSZC.MigrateHumanHandDefaults()' in layout_s
      and 'vgui.CursorVisible and not vgui.CursorVisible()' in layout_s
      and 'if on then WSZC.SyncMinigameCursor() end' in layout_s
      and 'cvHandanim:GetBool() or cvHideHand:GetBool()' in layout_s
      and 'local function PatchActionButtonOffset()' in layout_s
      and 'point.OffsetY = -14' in layout_s
      and 'PatchActionButtonOffset()' in layout_s
      and 'function WSZC.ForceReleaseMinigameCursor()' in layout_s
      and 'WSZC.ForceReleaseMinigameCursor()' in minigames_s
      and '_MinigameForceOffUntil' in layout_s and '_MinigameForceOffUntil' in minigames_s
      and 'MinigameDrawnRecently() is deliberately NOT included here' in minigames_s
      and 'if WSZC.MinigameHUDOpen == true and cmd.SetButtons' in minigames_s
      and 'if WSZC.MinigameHUDOpen ~= true then return end' in minigames_s
      and 'if session and cmd.SetButtons then cmd:SetButtons(0) end'
          in src('woundsystem_zcity_compat/lua/autorun/server/sv_zcity_woundsystem_compat_minigames.lua'))
check('S51 human C:U hand artwork, native rotation and one-time default migration',
      'wszc/minigame/hand_idle.png' in layout_s
      and 'wszc/minigame/hand_click.png' in layout_s
      and 'WSZC.UnitmenuHandSrcW = 512' in layout_s
      and 'WSZC.UnitmenuHandSrcH = 1260' in layout_s
      and 'return tonumber(angle) or 0' in layout_s
      and 'origRectRotated(nx, ny, nw, nh, rot, ...)' in layout_s
      and 'zc_woundsystem_compat_hand_mode_revision' in layout_s
      and 'function WSZC.MigrateHumanHandDefaults()' in layout_s
      and 'UnitmenuHandRotatedCenter' not in src('woundsystem_zcity_compat/lua/autorun/client/wszc_cl_bandage.lua')
      and '"zc_woundsystem_compat_hand_cursor_scale", "0.55"' in layout_s
      and '"zc_woundsystem_compat_handanim_scale", "1"' in layout_s
      and 'cvHandModeRevision:SetInt' not in layout_s
      and 'cvHandModeRevision, 6' in layout_s
      and (CONN / 'materials/wszc/minigame/hand_idle.png').is_file()
      and (CONN / 'materials/wszc/minigame/hand_click.png').is_file())
check('S48 silhouettes keep native anatomy; head/neck are crop-first calibrated',
      'woundview_reference_1365x1079.png' in generator_s
      and '2222.png' in generator_s
      and 'SEAM_LIMBS' not in generator_s
      and 'def CloseMask(mask):' not in generator_s
      and 'def FlattenLimbBand(mask):' not in generator_s
      and 'def SquareToe(mask):' not in generator_s
      and 'JOINT_SQUARE_FRAC' not in generator_s
      and 'no shape editing' in generator_s
      and "'forearm_R': (505.0, 369.0, 106.8, 41.3)" in generator_s
      and "'arm_R':     (594.9, 376.0, 79.8, 62.8)" in generator_s
      and "head_alpha.crop((0, 0, head_alpha.width, source_split))" in generator_s
      and "head_alpha.crop((0, source_split, head_alpha.width, head_alpha.height))" in generator_s
      and 'HEAD_SOURCE_LAYOUT' not in generator_s
      and 'HEAD_SOURCE_BOX' not in generator_s)
check('S49 opioid dose reaches the ZCity organism (morphine / fentanyl)',
      'opiateAmount = tonumber(body.opiateAmount) or 0' in organism_s
      and 'add("analgesiaAdd", (after.opiateAmount - before.opiateAmount) * 0.006, 0, 4)' in organism_s
      and 'WSZC.BoneAnchor = BoneAnchor' in organism_s)
fit_s = (ROOT / 'tools' / 'fit_unitmenu_geometry.py').read_text(encoding='utf-8')
check('S50 clean-reference pixel tracing + measured legacy fallback are present',
      'def traced_roundtrip(' in fit_s
      and 'G.trace_reference_masks(reference)' in fit_s
      and 'woundview_reference_clean_1365x1079.png' in fit_s
      and 'clean-reference full-cell black/white mismatches' in fit_s
      and 'PIXEL_EXACT' in fit_s
      and 'max(px[x, y]) < 20' in fit_s
      and 'def iou(' in fit_s
      and 'def optimize(' in fit_s
      and 'def render(' in fit_s
      and 'G.REFERENCE_BOXES' in fit_s
      and 'ImageChops.subtract(soft_inner, contour)' in fit_s
      and "ORDER = tuple(k for k in G.LIMB_LAYERS if k not in ('head', 'neck'))" in fit_s
      and 'PAIRS =' not in fit_s
      and 'SEEDS = {' in fit_s
      and 'include_head=False' in fit_s
      and 'DOLL_RGB = (0, 0, 0)' in generator_s)
check('S56 neck is a real client/server limb without hover card, with first-life sync',
      'local function EnsureNeckLimb(limbs)' in layout_s
      and 'function WSZC.UnitmenuTooltipLines(id, state)' not in layout_s
      and 'hook.Remove("PostDrawHUD", "WSZC_UnitmenuLimbTooltip")' in layout_s
      and 'hook.Add("PostDrawHUD", "WSZC_UnitmenuLimbTooltip"' not in layout_s
      and 'function WSZC.EnsureNeckState(ply)' in organism_s
      and 'hook.Add("PlayerSpawn", "WSZC_NeckFirstLifeSync"' in organism_s
      and 'neck      = { dmg = "spine3"' in organism_s
      and 'head      = { dmg = "skull",  amp = "headamputated", dis = nil },' in organism_s
      and 'neckartery = "neck"' in organism_s
      and 'if string.find(lower, "neck", 1, true) then return "neck" end' in organism_s)
check('S56b pelvis is a real 17th client/server limb with bone-routed wounds',
      'local function EnsurePelvisLimb(limbs)' in layout_s
      and 'local function EnsurePelvisClientState()' in layout_s
      and 'pelvis.id = "pelvis"' in layout_s
      and 'function WSZC.EnsurePelvisState(ply)' in organism_s
      and 'const.ParentLimb.pelvis = "abdomen"' in organism_s
      and 'const.NonDismemberableCoreLimbs.pelvis = true' in organism_s
      and 'pelvis    = { dmg = "pelvis", amp = nil' in organism_s
      and 'pelvis = "ValveBiped.Bip01_Pelvis"' in organism_s
      and 'pelvis = "pelvis", spine = "pelvis", hips = "pelvis", hip = "pelvis"' in organism_s
      and 'if string.find(lower, "spine1")' in organism_s)
packer_s = (ROOT / 'tools/pack_ui_materials.py').read_text(encoding='utf-8')
check('S57 packer regenerates the 17-part doll and keeps generated/source counts separate',
      "subprocess.run(doll_cmd, cwd=ROOT, check=True)" in packer_s
      and "len(generated) == 40" in packer_s
      and "wanted in entries or wanted in generated" in packer_s
      and "len(actual_materials) == 654" in packer_s
      and "len(limb_pngs) == 34" in packer_s
      and 'HEAD_SPLIT_FRAC' in generator_s
      and 'HEAD_SOURCE_LAYOUT' not in generator_s
      and len(set(re.findall(r"^    '(\w+)':", generator_s, re.M))) == 17)
source_archive_hashes = {
    'zcity.zip': 'a122484c29e5afeed7e0eb43a6685c68654fe07ae0a288c0ccc1380a0dc401c4',
    'casualites unknown.zip': '3c77c030cc44a634a0fa588cefaa3204e6b80abcfef215166cfc83dc09a9a786',
    'zcity organs +.zip': '8c38888907d85901d9cbfb68690b94894d84eb93fd76ec11b61bd93b0ef3f01f',
}
check('S58 the three user source ZIPs remain byte-for-byte untouched',
      all((ROOT / name).is_file() and hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
          for name, digest in source_archive_hashes.items()))
check('S39 shrapnel survives ragdoll -> standing (authoritative organism)',
      '"wszc_shrapnel", "wszc_shrapnel_floor", "wszc_shrapnel_irritation"' in organism_s
      and '_WSZCRagdollTransitionUntil' in organism_s
      and 'CarryShrapnelShadow' in organism_s
      and 'RestoreShrapnelShadow' in organism_s
      and 'WSZC.ReconcileSpawnShrapnel' in organism_s
      and 'org.wszc_shrapnel = nil' not in organism_s
      and 'hook.Add("Fake", "WSZC_ShrapnelRagdollKeep"' in organism_s
      and 'hook.Add("FakeUp", "WSZC_ShrapnelRagdollKeep"' in organism_s)
check('S40 clicking empty WoundView space closes it, interactive zones excluded',
      'function WSZC.WoundViewEmptyClick(mx, my, s)' in layout_s
      and 'hook.Add("Think", "WSZC_WoundViewEmptyClickClose"' in layout_s
      and 'WoundSystem.CloseHealthHUD()' in layout_s
      and 'WoundSystemActionButtonPos' in layout_s
      and 'WoundSystemDragState' in layout_s
      and '"zc_woundsystem_compat_close_on_empty_click", "1"' in layout_s)
check('S41 text=all no longer deletes gameplay sprites / the wound front layer',
      'NO DrawTexturedRect suppression here' in layout_s
      and 'IsMinigameGameplaySprite' in layout_s
      and 'handgrasp' in layout_s
      and 'shrapnelpiece' in layout_s
      and 'bandageouter' in layout_s
      and 'WSZC.MinigameTextHidden()' in layout_s)

# Remote treatment is an adapter around C:U, never a second health model.
check('S51 separate remote radial option; self inspection remains intact',
      'Лечить игрока' in remote_client_s
      and 'ZCity_WoundBridge_RemoteInspect_WSZC' in remote_client_s
      and '_WSZCRemoteInspect = true' in remote_client_s
      and 'target ~= ply' in remote_client_s
      and 'hg.RagdollOwner' in remote_client_s
      and 'pcall(hg.eyeTrace, ply)' in remote_client_s
      and 'util.TraceHull' not in remote_client_s
      and 'IsValid(MENUPANELHUYHUY) and ValidPatient(ply, Remote.focusTarget)' in remote_client_s
      and 'for _, key in ipairs({ "FakeRagdoll", "WoundSystemUnconsciousRagdoll" })' in remote_client_s
      and 'local function PatientEntity(target)' in remote_client_s
      and 'WSZC.OpenCUWoundMenu = function(...)' in remote_client_s
      and 'ZCity_WoundBridge_RemoteInspect_WSZC'
          not in src('woundsystem_zcity_compat/lua/autorun/client/cl_zcity_woundsystem_compat_inspect.lua'))
check('S52 namespaced protocol carries an explicit patient and exact schemas',
      'WSZC_RemoteMedicalAction' in remote_server_s
      and 'local EXPECTED = {' in remote_server_s
      and 'local INPUT_TYPES = {' in remote_server_s
      and 'payload.n or #payload' in remote_server_s
      and 'inspection.target ~= target or not ValidPair(operator, target)' in remote_server_s
      and 'operator == target' in remote_server_s
      and 'not operator:Alive() or not target:Alive()' in remote_server_s
      and 'local function PatientEntity(ply)' in remote_server_s
      and 'from:Distance(Position(target))' in remote_server_s
      and 'distance <= RANGE' in remote_server_s)
check('S53 native sessions belong to patient; traffic and slots belong to operator',
      'receiver(0, target)' in remote_server_s
      and 'targetInventory[slotIdx] = operatorSlot' in remote_server_s
      and 'targetInventory[slotIdx] = originalSlot or EmptySlot()' in remote_server_s
      and 'operatorInventory[slotIdx] = EmptySlot()' in remote_server_s
      and 'originalSend(activeNet.operator' in remote_server_s
      and 'originalSend(meta.operator' in remote_server_s
      and 'message == "WoundSystem_SyncInventory" then return end' in remote_server_s)
check('S54 remote client restores limbs, cardio and skills; drops self updates only remotely',
      'selfUpdateOriginals' in remote_client_s
      and 'if Remote.active then return end' in remote_client_s
      and 'Remote.selfStats' in remote_client_s
      and 'ApplyStatsSnapshot(cardio)' in remote_client_s
      and 'ReplaceContents(currentStats, Remote.selfStats)' in remote_client_s
      and 'RestoreSelfState()' in remote_client_s)
check('S55 native minigames and AED timers revalidate the remote pair',
      'MetaFor(target, "Aed")' in remote_server_s
      and 'not ValidPair(operator, target) then return end' in remote_server_s
      and 'WithNativeContext(operator, target, meta.slotIdx' in remote_server_s
      and 'NativeSession(target, kind)' in remote_server_s
      and 'OperatorBusy(operator)' in remote_server_s)
check('S56 bandage/syringe reuse external sessions; one applied dose equals one consume',
      'h.StartExternalMinigame' in remote_server_s
      and 'pcall(apply, target, itemId, limbId, cost)' in remote_server_s
      and 'WSZC.ApplyItemToBodyImpl or h.ApplyItemToBody' in remote_server_s
      and 'ConsumeSlot(operator, idx, itemId, cost, true)' in remote_server_s
      and 'ConsumeSlot(operator, idx, itemId, cost)' in remote_server_s
      and 'if durability <= 0 then return false end' in remote_server_s
      and '.remote = true' in remote_server_s
      and 'RemoteSessionValid(ply, session)' in src('woundsystem_zcity_compat/lua/autorun/server/sv_zcity_woundsystem_compat_minigames.lua'))
check('S57 pending opens and all remote/native/external sessions have a close path',
      'FinishRemote("open_timeout")' in remote_client_s
      and 'if Remote.active or Remote.pending then FinishRemote("replaced") end' in remote_client_s
      and 'WSZC_RemoteMedicalWatchdog' in remote_server_s
      and 'CloseNativeMeta(target, kind' in remote_server_s
      and 'StopExternalMinigame' in remote_server_s
      and 'PlayerDisconnected' in remote_server_s)
check('S58 remote client/server modules are registered for download and include',
      'AddCSLuaFile("autorun/client/cl_zcity_woundsystem_compat_remote.lua")' in src('woundsystem_zcity_compat/lua/autorun/server/sv_zcity_woundsystem_compat.lua')
      and 'include("autorun/server/sv_zcity_woundsystem_compat_remote.lua")' in src('woundsystem_zcity_compat/lua/autorun/server/sv_zcity_woundsystem_compat.lua'))

check('S59 C:U inventory stays hidden identically for self and remote; only virtual slot 6 remains',
      'InventoryAllowed' not in layout_s
      and 'WSZC.RemoteMedical' not in layout_s
      and 'if key == 6 then return rawget(real, 6) end' in layout_s
      and 'if type(key) == "number" and key >= 1 and key <= 5 then' in layout_s
      and 'WSZC.CUHudHiddenRegion' in layout_s)

check('S60 remote treatment usage, controls and limitations are documented',
      'Лечить игрока' in all_docs
      and 'zc_woundsystem_compat_remote_inspect_button' in all_docs
      and 'wszc_treat_player' in all_docs
      and 'двух' in all_docs.lower()
      and 'предметы' in all_docs.lower() and 'лекар' in all_docs.lower())

check('S61 remote and self share the same advanced WoundView and explicit session contract',
      'WSZC.OpenCUWoundMenu = function(...)' in remote_client_s
      and 'WSZC_RemoteMedicalPatientBanner' not in remote_client_s
      and 'hook.Add("HUDPaint"' not in remote_client_s
      and 'target = target, spec = spec, idx = idx, maxDur = maxDur' in remote_server_s
      and 'live = live, oneDose = oneDose' in remote_server_s
      and 'data[name] ~= nil then return data[name]' in src('woundsystem_zcity_compat/lua/autorun/server/sv_zcity_woundsystem_compat_minigames.lua'))

check('S62 WoundView has no ZCity medicine strip or duplicate treatment buttons',
      all(marker not in inspect_s for marker in (
          'WSZC_WoundViewTreatHUD', 'ZCITY_MED_BAR_DEFS', 'CollectMedicineBarEntries',
          'BuildLimbContextActions', 'InstallLimbActionButtons', 'WSZC.SendWoundViewTreat',
          'ПЕРЕВЯЗАТЬ РАНУ', 'ПЕРЕБИНТОВАТЬ ПЕРЕЛОМ', 'НАЛОЖИТЬ ЖГУТ'))
      and '_ActiveTreatRects' not in layout_s
      and 'WoundSystemActionButtonPos' in layout_s
      and 'InstallUnconsciousInspectionBridge' in inspect_s)

# Lua syntax (luaparser is optional).
try:
    sys.path.insert(0, '/tmp/luaparser_pkg')
    from luaparser import ast
    lua_files = sorted(
        f for f in glob.glob(str(CONN / 'lua/**/*.lua'), recursive=True)
        if '/wszc_vendor/cu/' not in f and '/wszc_vendor/zcity/woundbridge/' not in f
    )
    bad = []
    for f in lua_files:
        try:
            ast.parse(Path(f).read_text(encoding='utf-8'))
        except Exception as exc:
            bad.append((f, str(exc)[:120]))
    check('S15 ALL_LUA_OK %d/%d' % (len(lua_files) - len(bad), len(lua_files)), not bad and len(lua_files) == 15)
except ImportError:
    print('SKIP S15 luaparser unavailable')

# CJK check.
cjk = re.compile(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]')
bad_cjk = []
for p in list(ROOT.glob('*.md')) + list(CONN.rglob('*.md')) + list(CONN.rglob('*.lua')):
    if 'wszc_vendor' in p.parts:
        continue  # vendored upstream sources are verified by embed_runtime.py --check
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
    assert len(geom) == 17, len(geom)
    limb_dir = CONN / 'materials/wszc/unitmenu/limbs'
    body = Image.new('L', (1500, 1500), 0)
    edges = Image.new('L', (1500, 1500), 0)
    edge_boxes, edge_white = 0, 0
    for limb, (cx, cy, w, h) in geom.items():
        cx, cy, w, h = float(cx), float(cy), int(w), int(h)
        box = (round(cx - w / 2), round(cy - h / 2))
        fill = Image.open(limb_dir / (limb + '_fill.png')).convert('RGBA')
        edge = Image.open(limb_dir / (limb + '_edge.png')).convert('RGBA')
        assert fill.size == (w, h) and edge.size == (w, h), (limb, fill.size, edge.size, w, h)
        fa, ea = fill.getchannel('A'), edge.getchannel('A')
        if ea.getbbox() is not None:
            edge_boxes += 1
        ep = edge.load()
        for yy in range(0, h, 3):
            for xx in range(0, w, 3):
                px = ep[xx, yy]
                if px[3] > 200 and px[:3] == (255, 255, 255):
                    edge_white += 1
        flayer, elayer = Image.new('L', (1500, 1500), 0), Image.new('L', (1500, 1500), 0)
        flayer.paste(fa, box)
        elayer.paste(ea, box)
        body = ImageChops.lighter(body, flayer)
        edges = ImageChops.lighter(edges, elayer)
    check('S17 white outline restored: 17 opaque white _edge.png',
          edge_boxes == 17 and edge_white > 100 and edges.getbbox() is not None)
    # Regression for the live "Lego robot" screenshot: a per-sprite white
    # frame means white pixels touch the rectangular sprite border.  The
    # owner chose an outline that follows EACH limb's shape instead, so the
    # contour is inset (EDGE_PAD) and NO border pixel may be white at all.
    worst_border = 0.0
    for limb, (cx, cy, w, h) in geom.items():
        w, h = int(w), int(h)
        a = Image.open(limb_dir / (limb + '_edge.png')).convert('RGBA').getchannel('A')
        p = a.load()
        border = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)]
        border += [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
        white = sum(1 for x, y in border if p[x, y] > 0)
        worst_border = max(worst_border, white / len(border))
    check('S36 NO rectangular frame: outlines never touch a sprite border (%.1f%%)' % (worst_border * 100),
          worst_border == 0.0)
    thorax = Image.open(limb_dir / 'thorax_fill.png').convert('RGBA')
    r, g, b, a = thorax.getpixel((thorax.width // 2, thorax.height // 2))
    check('S18 neutral white *_fill mask (renders black at 100% muscle, red on damage)',
          a > 200 and (r, g, b) == (255, 255, 255))
    # Every outline must be non-empty (b47a0cb's transparent _edge was rejected)
    # and must follow its limb's shape rather than a box: white pixels sit in
    # the interior of the sprite, not on its border.
    check('S37 generator emits neutral white fill masks + shape-following per-limb contours',
          edge_boxes == 17
          and 'DOLL_RGB = (0, 0, 0)' in generator_s
          and 'FILL_RGB = (255, 255, 255)' in generator_s
          and 'EDGE_PAD_MIN = 6' in generator_s
          and 'EDGE_WIDTH = 17' in generator_s
          and "EDGE_WIDTH_OVERRIDES = {'hand_R': 11, 'hand_L': 11}" in generator_s
          and 'ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(edge_width)))' in generator_s
          and 'outer_band' not in generator_s
          and 'ABDOMEN_SEAM_Y = 520.5' in generator_s
          and 'ABDOMEN_SEAM_WIDTH = 2' in generator_s
          and 'ImageDraw' not in generator_s
          and 'assert worst == 0.0' in generator_s)
    # Thin transparent joint gaps between neighbouring fills.  The white
    # outline is a SEPARATE sprite, so the fill mask still shows seams.
    mask = body.point(lambda p: 255 if p > 127 else 0)
    px = mask.load()
    seam_pixels = 0
    for y in range(170, 1470, 2):
        for x in range(130, 1340, 2):
            if px[x, y] == 0 and y > 8 and y < 1492 and px[x, y - 8] > 127 and px[x, y + 8] > 127:
                seam_pixels += 1
    check('S19 thin joint gaps are present (%d px)' % seam_pixels, seam_pixels > 20)
    # Human proportions in the generated Lua geometry.  Use the VISIBLE head
    # hitbox, not its new/smaller POT cell: head and neck now own separate cells.
    hover = {m[0]: (m[1], m[2]) for m in re.findall(
        r'(\w+)\s*=\s*\{[^\n]*?hoverW\s*=\s*(\d+),\s*hoverH\s*=\s*(\d+)',
        geom_text)}
    g = {k: tuple(float(v) for v in vals) for k, vals in geom.items()}
    head_top = g['head'][1] - float(hover['head'][1]) / 2
    torso_bottom = g['pelvis'][1] + float(hover['pelvis'][1]) / 2
    leg_top = g['thigh_R'][1] - float(hover['thigh_R'][1]) / 2
    leg_bottom = g['foot_R'][1] + float(hover['foot_R'][1]) / 2
    torso_h, leg_h = torso_bottom - head_top, leg_bottom - leg_top
    # The supplied green reference keeps a roughly 0.73 leg/torso ratio.
    # Its arms and legs are intentionally asymmetric, so symmetry is checked
    # against the measured geometry rather than forcing mirrored boxes.
    check('S20 limb sizes follow the green reference proportions',
          leg_h >= 0.70 * torso_h
          and leg_h <= 0.80 * torso_h
          and g['thorax'][2] > g['head'][2]
          and g['thigh_R'][2] < g['thorax'][2]
          and g['abdomen'][3] + g['pelvis'][3] >= g['thorax'][3]
          and g['forearm_R'][2] > g['arm_R'][2]
          and g['hand_R'][2] < g['forearm_R'][2]
          and g['foot_R'][2] <= g['crus_R'][2]
          and abs(g['arm_R'][0] + g['arm_L'][0] - 1537.3) < 0.2
          and abs(g['thigh_R'][0] + g['thigh_L'][0] - 1524.1) < 0.2
          and abs(g['foot_R'][1] - g['foot_L'][1]) < 3
          # C:U reads mat:Width()/Height(); GMod rounds PNG textures to a
          # power of two, so EVERY emitted sprite must already be POT-sized.
          and all(int(v[2]) > 0 and int(v[2]) & (int(v[2]) - 1) == 0
                  and int(v[3]) > 0 and int(v[3]) & (int(v[3]) - 1) == 0
                  for v in g.values()))
    check('S44 hover boxes are the visible silhouettes, not the padded POT sprites',
          len(hover) == 17
          and all(int(hover[k][0]) <= int(g[k][2]) and int(hover[k][1]) <= int(g[k][3])
                  for k in hover))

    # Screen-space proof against the supplied green 1365x1079 reference.
    # C:U draws fill first and edge second; doing only a black-source fit is
    # insufficient because a bold contour can otherwise leave white fingers
    # outside the intended silhouette.  Check both visible masks per limb.
    sys.path.insert(0, str(ROOT / 'tools'))
    import build_unitmenu_materials as generator
    clean_fixture = ROOT / 'tools/tests/woundview_reference_clean_1365x1079.png'
    clean_reference = Image.open(clean_fixture).convert('RGB')
    traced_reference = generator.trace_reference_masks(clean_reference)
    reference_black, reference_white_hands = {}, {}
    for limb in generator.LIMB_LAYERS:
        left, top, sw, sh = generator.reference_screen_cell(limb)
        box = (left, top, left + sw, top + sh)
        bbox = traced_reference[limb]['black'].crop(box).getbbox()
        assert bbox is not None, limb
        reference_black[limb] = (left + bbox[0], top + bbox[1],
                                 left + bbox[2], top + bbox[3])
        if limb in ('hand_R', 'hand_L'):
            edge = traced_reference[limb]['edge'].crop(box).point(
                lambda p: 255 if p > 180 else 0)
            bbox = edge.getbbox()
            reference_white_hands[limb] = (left + bbox[0], top + bbox[1],
                                           left + bbox[2], top + bbox[3])
    rendered = Image.new('RGB', (1365, 1079), (10, 30, 20))
    black_errors, white_errors = {}, {}
    for limb in generator.LIMB_LAYERS:
        left, top, sw, sh = generator.reference_screen_cell(limb)
        fill_alpha = Image.open(limb_dir / (limb + '_fill.png')).convert('RGBA').getchannel('A').resize(
            (sw, sh), Image.Resampling.LANCZOS)
        edge_alpha = Image.open(limb_dir / (limb + '_edge.png')).convert('RGBA').getchannel('A').resize(
            (sw, sh), Image.Resampling.LANCZOS)
        rendered.paste(Image.new('RGB', (sw, sh), (0, 0, 0)), (left, top), fill_alpha)
        rendered.paste(Image.new('RGB', (sw, sh), (255, 255, 255)), (left, top), edge_alpha)
        threshold = generator.ALPHA_THRESHOLD
        fill_mask = fill_alpha.point(lambda p: 255 if p > threshold else 0)
        edge_mask = edge_alpha.point(lambda p: 255 if p > threshold else 0)
        bbox = ImageChops.subtract(fill_mask, edge_mask).getbbox()
        assert bbox is not None, limb
        actual = (left + bbox[0], top + bbox[1], left + bbox[2], top + bbox[3])
        black_errors[limb] = tuple(a - b for a, b in zip(actual, reference_black[limb]))
        if limb in reference_white_hands:
            bbox = edge_alpha.point(lambda p: 255 if p > 180 else 0).getbbox()
            actual = (left + bbox[0], top + bbox[1], left + bbox[2], top + bbox[3])
            white_errors[limb] = tuple(a - b for a, b in zip(actual, reference_white_hands[limb]))
    worst_black = max(abs(v) for errors in black_errors.values() for v in errors)
    check('S53 all 17 visible black boxes match the green reference (worst %d px)' % worst_black,
          len(black_errors) == 17 and worst_black == 0)
    worst_white = max(abs(v) for errors in white_errors.values() for v in errors)
    check('S53b hand WHITE exteriors also match, including fingers (worst %d px)' % worst_white,
          len(white_errors) == 2 and worst_white == 0)

    def white_runs(y):
        p = rendered.load()
        xs = [x for x in range(650, 726)
              if min(p[x, y]) > 180 and max(p[x, y]) - min(p[x, y]) < 45]
        runs = []
        for x in xs:
            if not runs or x > runs[-1][1] + 1:
                runs.append([x, x])
            else:
                runs[-1][1] = x
        return runs

    check('S53c head/neck have ONE native seam at y=317, x=663..713',
          white_runs(317) == [[663, 713]]
          and all(not any(b - a > 10 for a, b in white_runs(y)) for y in (315, 316, 318)))
    rp = rendered.load()
    check('S53d abdomen/pelvis seam is one dominant row at native y=520',
          rp[687, 520][0] >= 180
          and max(rp[687, 519][0], rp[687, 521][0]) < 150
          and max(rp[687, 518][0], rp[687, 522][0]) < 20)
    reference_fixture = ROOT / 'tools/tests/woundview_reference_1365x1079.png'
    check('S53e pinned 2222 + clean 1435 reference fixtures are unchanged',
          reference_fixture.is_file()
          and hashlib.sha256(reference_fixture.read_bytes()).hexdigest()
          == 'f48e70ba545853aee9e3763975bf28273e8312b35c2803670b2f0060fd1bd901'
          and clean_fixture.is_file()
          and hashlib.sha256(clean_fixture.read_bytes()).hexdigest()
          == generator.REFERENCE_CLEAN_SHA256)
    # These pixels belong to the REFERENCE'S OUTER white stroke.  The previous
    # inner-only contour failed every first anchor, although black bboxes still
    # passed.  They pin the visible outline, not just its silhouette position.
    outer_stroke_anchors = {
        'head': ((657, 270), (660, 270)),
        'abdomen': ((633, 480), (636, 480)),
        'thigh_R': ((631, 640), (634, 640)),
        'crus_R': ((634, 740), (638, 740)),
        'foot_R': ((633, 815), (636, 815)),
    }
    outer_ok = True
    for limb, points in outer_stroke_anchors.items():
        for x, y in points:
            pixel = rp[x, y]
            if min(pixel) <= 150 or max(pixel) - min(pixel) >= 55:
                outer_ok = False
    check('S53f outer white stroke hits the measured 2222 head/body/leg anchors', outer_ok)

    # Strong reference test: every shipped POT sprite is downsampled exactly as
    # in C:U and compared with ALL traced pixels in its destination cell.  A
    # good bbox cannot hide a wrong finger, underarm notch, sole or seam here.
    roundtrip_mismatch = 0
    for limb in generator.LIMB_LAYERS:
        left, top, sw, sh = generator.reference_screen_cell(limb)
        box = (left, top, left + sw, top + sh)
        fill_alpha = Image.open(limb_dir / (limb + '_fill.png')).convert('RGBA').getchannel('A').resize(
            (sw, sh), Image.Resampling.LANCZOS)
        edge_alpha = Image.open(limb_dir / (limb + '_edge.png')).convert('RGBA').getchannel('A').resize(
            (sw, sh), Image.Resampling.LANCZOS)
        black = ImageChops.subtract(
            fill_alpha.point(lambda p: 255 if p > generator.ALPHA_THRESHOLD else 0),
            edge_alpha.point(lambda p: 255 if p > generator.ALPHA_THRESHOLD else 0))
        white = edge_alpha.point(lambda p: 255 if p > 180 else 0)
        target_black = traced_reference[limb]['black'].crop(box)
        target_white = traced_reference[limb]['edge'].crop(box).point(
            lambda p: 255 if p > 180 else 0)
        roundtrip_mismatch += sum(a != b for a, b in zip(black.tobytes(), target_black.tobytes()))
        roundtrip_mismatch += sum(a != b for a, b in zip(white.tobytes(), target_white.tobytes()))
    check('S54 clean 1435 full-cell black/white round-trip has ZERO wrong pixels',
          roundtrip_mismatch == 0)

    def neutral_runs(image, y, x0, x1):
        pixels = image.load()
        xs = [x for x in range(x0, x1)
              if min(pixels[x, y]) > 150 and max(pixels[x, y]) - min(pixels[x, y]) < 55]
        runs = []
        for x in xs:
            if not runs or x > runs[-1][1] + 1:
                runs.append([x, x])
            else:
                runs[-1][1] = x
        return runs

    scanlines = (
        (270, 640, 735), (365, 350, 1000), (400, 605, 765),
        (480, 605, 765), (520, 620, 755), (640, 610, 755),
        (740, 610, 755), (815, 610, 760), (317, 650, 725),
    )
    check('S54b all nine white scanlines are EXACTLY the original 1435',
          all(neutral_runs(rendered, y, x0, x1) == neutral_runs(clean_reference, y, x0, x1)
              for y, x0, x1 in scanlines))

    hand_frames = [Image.open(CONN / 'materials/wszc/minigame' / name).convert('RGBA')
                   for name in ('hand_idle.png', 'hand_click.png')]
    grip_pixels = [im.getpixel((round(0.4 * (im.width - 1)),
                                round(0.1 * (im.height - 1)))) for im in hand_frames]
    check('S52 human hand sprites use the native canvas and grip is on skin',
          all(im.size == (512, 1260) for im in hand_frames)
          and all(px[3] > 200 and px[0] > px[1] > px[2] for px in grip_pixels))
    mats = [p for p in (CONN / 'materials').rglob('*') if p.is_file()]
    check('S21 connector ships 654 UI materials', len(mats) == 654)
    checksums = (CONN / 'MATERIALS.sha256').read_text(encoding='utf-8').splitlines()
    check('S22 MATERIALS.sha256 has 614 source entries',
          len([l for l in checksums if l.strip() and not l.startswith('#')]) == 614)
except ImportError:
    print('SKIP S17-S22 Pillow unavailable')

# ------------------------------------------------------------------- ZIPs ---
def validate_zips():
    with zipfile.ZipFile(ROOT / 'woundsystem_zcity_compat.zip') as z:
        assert z.testzip() is None
        compat = {i.filename: z.read(i.filename) for i in z.infolist()}
    with zipfile.ZipFile(ROOT / 'zcity_full_pack.zip') as z:
        assert z.testzip() is None
        full = {i.filename: z.read(i.filename) for i in z.infolist()}
    conn_files = {p.relative_to(CONN).as_posix(): p.read_bytes() for p in CONN.rglob('*') if p.is_file()}
    assert len(conn_files) == len(compat) == 754
    assert all(compat['woundsystem_zcity_compat/' + r] == d for r, d in conn_files.items())
    mirror = {n[len('garrysmod/addons/casualties_unknown_health_system_beta/materials/'):]: d
              for n, d in full.items()
              if n.startswith('garrysmod/addons/casualties_unknown_health_system_beta/materials/')}
    assert len(mirror) == 654
    assert all(mirror[r[len('materials/'):]] == d for r, d in conn_files.items() if r.startswith('materials/'))
    assert json.loads(compat['woundsystem_zcity_compat/addon.json'])
    external_bridge = full['garrysmod/addons/z_city/lua/homigrad/woundbridge/sv_woundbridge.lua']
    embedded_bridge = full['garrysmod/addons/woundsystem_zcity_compat/lua/wszc_vendor/zcity/woundbridge/sv_woundbridge.lua']
    # Full pack preserves the historical external source patch.  The embedded
    # copy remains byte-provenance-clean; the connector's runtime PrintMessage
    # filter suppresses this same notice for both runtime selections.
    assert b'Not completed - nothing was applied' not in external_bridge
    assert b'WSZC: the empty-dose centre notice is intentionally suppressed.' in external_bridge
    assert b'Not completed - nothing was applied' in embedded_bridge
    manifest = full['MANIFEST.txt'].decode('utf-8')
    shas = re.findall(r'woundsystem_zcity_compat/lua/[^\s]+\.lua\s+([0-9a-f]{64})', manifest)
    assert len(shas) == 89
    assert all(hashlib.sha256(d).hexdigest() in shas for r, d in conn_files.items() if r.endswith('.lua'))
    shipped_layout = full['garrysmod/addons/woundsystem_zcity_compat/lua/autorun/client/cl_zcity_woundsystem_compat_layout.lua'].decode('utf-8')
    assert 'HandRectForCursor' in shipped_layout
    assert 'WSZC.InstallMinigameTextFilter()' in shipped_layout
    assert 'WSZC.IsMinigameWoundLayer' in shipped_layout
    assert 'WSZC.IsMinigameGameplaySprite' in shipped_layout
    assert 'origBoardRect' not in shipped_layout
    assert 'function WSZC.WoundViewEmptyClick' in shipped_layout
    assert 'local function EnsureNeckLimb' in shipped_layout
    assert 'local function EnsurePelvisLimb' in shipped_layout
    assert 'function WSZC.UnitmenuTooltipLines' not in shipped_layout
    assert 'hook.Remove("PostDrawHUD", "WSZC_UnitmenuLimbTooltip")' in shipped_layout
    assert 'woundsystem_zcity_compat/materials/wszc/unitmenu/limbs/neck_fill.png' in compat
    assert 'woundsystem_zcity_compat/materials/wszc/unitmenu/limbs/pelvis_fill.png' in compat
    # The mini-game uses the existing red shard art, not a recolored/renamed
    # replacement; it must be available to both standalone and full packs.
    with zipfile.ZipFile(ROOT / 'для того чтобы все работало вместе материалы для UI.zip') as art:
        for shard in ('shrapnelpiece_red.png', 'shrapnelpiece_padded_red.png'):
            rel = 'casunknown-images/shrapnelminigame/' + shard
            source = next(n for n in art.namelist() if n.endswith('/' + rel))
            assert compat['woundsystem_zcity_compat/materials/' + rel] == art.read(source)
            assert mirror[rel] == art.read(source)
    assert 'wszc/unitmenu/limbs/neck_edge.png' in mirror
    assert 'wszc/unitmenu/limbs/pelvis_edge.png' in mirror
    assert 'INSTALL_RU.md' not in full and 'zc_woundsystem_compat_fullscreen_native' in full['ZCity_binds.md'].decode('utf-8')
    # +4 neck/pelvis PNGs in the connector and +4 in the C:U material mirror.
    # Six fonts/shaders moved C:U -> connector without changing the old total.
    # The isolated embedded runtime adds 75 Lua files + one provenance manifest.
    assert len(full) == 2858
    declared_total = re.search(r'Всего файлов в архиве:\s*(\d+)', manifest)
    assert declared_total and int(declared_total.group(1)) == len(full)
    return True


check_raises_free('S35 FULL_ZIP_OK / COMPAT_ZIP_OK / MANIFEST_OK / MIRROR_OK', validate_zips)

# --------------------------------------------------------------- runtime ----
try:
    sys.path.insert(0, '/tmp/lupa_pkg')
    from lupa import LuaRuntime
except ImportError:
    LuaRuntime = None

if LuaRuntime is None:
    print('SKIP runtime checks (lupa unavailable)')
else:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
CLIENT = true; SERVER = false
math.Clamp = function(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end
math.Round = function(v) return math.floor(v + 0.5) end
table.Copy = function(t)
    local out = {}
    for k, v in pairs(t or {}) do if type(v) == "table" then out[k] = table.Copy(v) else out[k] = v end end
    return out
end
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
        GetFloat = function(s) return tonumber(s._v) or 0 end,
        SetFloat = function(s, v) s._v = tostring(v) end,
        SetInt = function(s, v) s._v = tostring(v) end }
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
mouseX, mouseY = 500, 400
gui = { EnableScreenClicker = function(on) clickerOn = on end,
        MousePos = function() return mouseX, mouseY end }
clickerOn = false
WoundSystemHealthHUDOpen = false
input = { IsMouseDown = function() return false end, IsKeyDown = function() return false end }
netMessages, currentNetMessage, resetReceivers = {}, nil, {}
net = {
    Receive = function(name, fn) resetReceivers[name] = fn end,
    Start = function(name) currentNetMessage = { name = name, writes = {} } end,
    WriteUInt = function(value, bits) table.insert(currentNetMessage.writes, { "uint", value, bits }) end,
    WriteFloat = function(value) table.insert(currentNetMessage.writes, { "float", value }) end,
    SendToServer = function() table.insert(netMessages, currentNetMessage) end,
}
MOUSE_LEFT, MOUSE_RIGHT, KEY_ESCAPE = 107, 108, 70
clipCalls, textCalls = {}, {}
WoundSystem = { MinigameClip = {
                    Scale = function() return 1000 / 1080 end,
                    GetRect = function() return 260, 40, 760, 760, 18 end,
                    Begin = function() return false end, End = function() end,
                    DrawHeader = function(d) table.insert(clipCalls, { kind = "header", d = d }) end,
                    DrawExitGuide = function() table.insert(clipCalls, { kind = "exit" }) end,
                    DrawBackdrop = function(d) table.insert(clipCalls, { kind = "backdrop" }) end },
                Client = { RequestInventoryMove = function() end }, HealthGUI = {} }
WoundSystemHealthHUDOpen = false
WoundSystemInventorySlots, WoundSystemDragState, WoundSystemWorldDrag = {}, {}, {}
draw = { SimpleText = function(t, f) table.insert(textCalls, { t = t, f = f }) end,
         SimpleTextOutlined = function(t, f) table.insert(textCalls, { t = t, f = f }) end,
         DrawText = function(t, f) table.insert(textCalls, { t = t, f = f }) end,
         RoundedBox = function() end }
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
surfaceCalls = {}
surface = {
    SetMaterial = function(m) table.insert(surfaceCalls, { kind = "mat", m = m }) end,
    SetDrawColor = function(r, g, b, a)
        table.insert(surfaceCalls, { kind = "color", r = r, g = g, b = b, a = a }) end,
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
    SetFont = function(_) end,
    GetTextSize = function(t) return #t * 10, 22 end,
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
file = { Exists = function(p) return p == "materials/wszc/minigame/hand_idle.png" end }
EnableDrawnHandMode = function()
    convars["zc_woundsystem_compat_hide_minigame_hand"]._v = "0"
    convars["zc_woundsystem_compat_handanim"]._v = "1"
    convars["zc_woundsystem_compat_hand_pin_cursor"]._v = "1"
    convars["zc_woundsystem_compat_hide_minigame_cursor"]._v = "1"
end
RestoreStandardCursorMode = function()
    convars["zc_woundsystem_compat_hide_minigame_hand"]._v = "1"
    convars["zc_woundsystem_compat_handanim"]._v = "0"
    convars["zc_woundsystem_compat_hand_pin_cursor"]._v = "0"
    convars["zc_woundsystem_compat_hide_minigame_cursor"]._v = "0"
end
Icons = { fracture = Material("cu/fracture") }
WoundSystemDislocationMinigame, WoundSystemShrapnelMinigame = { active = false }, { active = false }
WSZC = { WSZCMinigameActive = function() return false end }
''')
    lua.execute((CLIENT / 'wszc_unitmenu_geometry.lua').read_text(encoding='utf-8'))
    lua.execute('hook.Add("PostDrawHUD", "WSZC_UnitmenuLimbTooltip", function() error("old card was not removed") end)')
    lua.execute(layout_s)
    lua.execute(minigames_s)
    visual_fn_start = shared_s.index('function WSZC.DislocationVisualAligned')
    visual_fn_end = shared_s.index('\nend\n', visual_fn_start) + 5
    lua.execute(shared_s[visual_fn_start:visual_fn_end])

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
       and WSZC.InstallNativeHandOverride() and WSZC.InstallMinigameTextFilter()
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

    rt('R06 native game frame and hitbox scale stay together at default 0.85', '''
(function()
    convars["zc_woundsystem_compat_fullscreen_native"]._v = "0"
    WoundSystemDislocationMinigame = { active = true }
    local x, y, w, h, r = WoundSystem.MinigameClip.GetRect()
    local s = WoundSystem.MinigameClip.Scale()
    WoundSystemDislocationMinigame = { active = false }
    convars["zc_woundsystem_compat_fullscreen_native"]._v = "0"
    return math.abs(w - 646) < 0.001 and math.abs(h - 646) < 0.001
       and math.abs(x - 317) < 0.001 and math.abs(y - 97) < 0.001
       and math.abs(r - 18 * 0.85) < 0.001
       and math.abs(s - (1000 / 1080) * 0.85) < 0.0001
end)()
''')

    rt('R07 compact rotated hand puts its visible pivot exactly on the cursor', '''
(function()
    EnableDrawnHandMode()
    WoundSystemShrapnelMinigame = { active = true }
    surfaceCalls = {}
    surface.SetMaterial(Material("casunknown-images/shrapnelminigame/handGraspIdle1.png"))
    surface.DrawTexturedRectRotated(500, 400, 512, 1260, 290)
    WoundSystemShrapnelMinigame = { active = false }
    local c = surfaceCalls[#surfaceCalls]
    if not c or c.kind ~= "rot" then return false end
    local a = math.rad(c.rot)
    local co, si = math.cos(a), math.sin(a)
    local ox, oy = (0.4 - 0.5) * c.w, (0.1 - 0.5) * c.h
    local gripX = c.x + ox * co - oy * si
    local gripY = c.y + ox * si + oy * co
    return math.abs(gripX - 500) < 0.001 and math.abs(gripY - 400) < 0.001
       and c.rot == 290
       and math.abs(c.w - 512 * 0.55) < 0.001
       and math.abs(c.h - 1260 * 0.55) < 0.001
end)()
''')

    rt('R08 human hand preserves the native C:U rotation', '''
(function()
    EnableDrawnHandMode()
    WoundSystemShrapnelMinigame = { active = true }
    surfaceCalls = {}
    surface.SetMaterial(Material("casunknown-images/shrapnelminigame/handGraspClick.png"))
    surface.DrawTexturedRectRotated(500, 400, 512, 1260, 290)
    WoundSystemShrapnelMinigame = { active = false }
    return surfaceCalls[#surfaceCalls].rot == 290
end)()
''')

    rt('R09 shared 0.55 scale applies once without a screen cap', '''
(function()
    EnableDrawnHandMode()
    local x, y, w, h = WSZC.HandRectForCursor(500, 400, 5000, 12000)
    return math.abs(w - 5000 * 0.55) < 0.001
       and math.abs(h - 12000 * 0.55) < 0.001
end)()
''')

    rt('R10 visible human hand replaces the OS arrow only in a minigame', '''
(function()
    EnableDrawnHandMode()
    cursorValue = "arrow"
    WoundSystemShrapnelMinigame = { active = true }
    WSZC.UnitmenuHandMat(false) -- every real hand draw re-hides a reset arrow
    local perFrame = cursorValue == "blank"
    cursorValue = "arrow"
    WSZC.SyncMinigameCursor()
    local handPointer = cursorValue == "blank"
    local blankWorks = WSZC.BlankMinigameCursor() == true
        and cursorValue == "blank"
    WoundSystemShrapnelMinigame = { active = false }
    WSZC.SyncMinigameCursor()
    return perFrame and handPointer and blankWorks and cursorValue == "arrow"
end)()
''')

    rt('R11 enabling the screen clicker restores the hand, not a second arrow', '''
(function()
    EnableDrawnHandMode()
    cursorValue = "arrow"
    WoundSystemDislocationMinigame = { active = true }
    gui.EnableScreenClicker(true)
    local ok = clickerOn == true and cursorValue == "blank"
    WoundSystemDislocationMinigame = { active = false }
    WSZC.SyncMinigameCursor()
    return ok and cursorValue == "arrow"
end)()
''')

    rt('R12 hiding hand art never restores the OS cursor; overlay is blank too', '''
(function()
    convars["zc_woundsystem_compat_hide_minigame_cursor"]._v = "1"
    convars["zc_woundsystem_compat_hide_minigame_hand"]._v = "1"
    cursorValue = "arrow"
    local overlayCursor = "arrow"
    local overlay = { SetCursor = function(_, value) overlayCursor = value end }
    WoundSystemShrapnelMinigame = { active = true, overlay = overlay }
    WSZC.SyncMinigameCursor()
    local hidden = cursorValue == "blank" and overlayCursor == "blank"
        and WSZC.BlankMinigameCursor() == true
    WoundSystemShrapnelMinigame = { active = false, overlay = overlay }
    WSZC.SyncMinigameCursor()
    local restored = cursorValue == "arrow" and overlayCursor == "arrow"
    convars["zc_woundsystem_compat_hide_minigame_hand"]._v = "0"
    return hidden and restored
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

    rt('R14b approximate rendered dislocation alignment sends immediate session packet', '''
(function()
    local oldGetGlobalBool = GetGlobalBool
    GetGlobalBool = function(key, fallback)
        if key == "WSZC_Ready" then return true end
        return fallback
    end
    netMessages = {}
    WoundSystemDislocationMinigame = {
        active = true, closeRequested = false, sessionId = 77,
        boneDrawX = 451.82, boneDrawY = 229.82,
        boneX = 600, boneY = 400, -- deliberately different server-prediction copy
    }
    hook._t["Think"]["WSZC_DislocationVisualCompletion"]()
    local sentAligned = #netMessages == 1
        and netMessages[1].name == "WSZC_DislocationVisualComplete"
        and netMessages[1].writes[1][2] == 77
        and netMessages[1].writes[2][2] == 451.82
        and netMessages[1].writes[3][2] == 229.82
    WoundSystemDislocationMinigame.boneDrawX = 700
    WoundSystemDislocationMinigame._WSZCNextVisualComplete = 0
    hook._t["Think"]["WSZC_DislocationVisualCompletion"]()
    local rejectedFar = #netMessages == 1
    WoundSystemDislocationMinigame = { active = false }
    GetGlobalBool = oldGetGlobalBool
    return sentAligned and rejectedFar
end)()
''')

    rt('R15 unitmenu defaults and WSZC hand use the shared 0.55 scale', '''
(function()
    local effectiveScale = 2 * WSZC.HandCursorScale()
    local w, h, px, py = WSZC.UnitmenuHandGeometry(512, 1260, effectiveScale)
    return convars["zc_woundsystem_compat_unitmenu_scale"]._v == "0.25"
       and convars["zc_woundsystem_compat_hand_pivot_x"]._v == "0.4"
       and convars["zc_woundsystem_compat_hand_pivot_y"]._v == "0.1"
       and convars["zc_woundsystem_compat_hand_cursor_scale"]._v == "0.55"
       and convars["zc_woundsystem_compat_handanim_scale"]._v == "1"
       and math.abs(w - 512 * 1.1) < 0.001
       and math.abs(h - 1260 * 1.1) < 0.001
       and px == 0.4 and py == 0.1
       and convars["zc_woundsystem_compat_unitmenu_doll"]._v == "1"
       and convars["zc_woundsystem_compat_hide_minigame_text"]._v == "1"
end)()
''')

    rt('R16 geometry table has 17 limbs with neck + abdomen/pelvis joints', '''
(function()
    local n = 0
    for _ in pairs(WSZC_UNITMENU_LIMB_GEOMETRY) do n = n + 1 end
    local g = WSZC_UNITMENU_LIMB_GEOMETRY
    return n == 17 and g.head.cy < g.neck.cy and g.neck.cy < g.thorax.cy
       and g.head.hoverW == 155 and g.head.hoverH == 200
       and g.neck.hoverW == 192 and g.neck.hoverH == 56
       and g.thorax.cy < g.abdomen.cy and g.abdomen.cy < g.pelvis.cy
       and g.pelvis.cy < g.thigh_R.cy and g.pelvis.hoverH > 0
       and g.thorax.cy < g.thigh_R.cy
       and g.thigh_R.cy < g.crus_R.cy and g.crus_R.cy < g.foot_R.cy
       and g.thorax.w > g.head.w and g.thigh_R.w < g.thorax.w
       and math.abs(g.arm_R.cx + g.arm_L.cx - 1537.3) < 0.11
       and g.hand_R.cx == 135.1 and g.hand_L.cx == 1367.3
end)()
''')

    rt('R17 WoundView backdrop hidden, unconscious blackout preserved', '''
(function()
    WSZC.CUHudFiltered = true; WSZC.CUDeathVisualsHidden = false
    convars["zc_woundsystem_compat_hide_woundview_backdrop"]._v = "1"
    WoundSystemHealthHUDOpen = true
    local hid = WSZC.CUHudHiddenRegionRaw(0, 0, 1000, 1000) == true
    WoundSystemHealthHUDOpen = false
    local kept = WSZC.CUHudHiddenRegionRaw(0, 0, 1000, 1000) == false
    convars["zc_woundsystem_compat_hide_woundview_backdrop"]._v = "0"
    WoundSystemHealthHUDOpen = true
    local off = WSZC.CUHudHiddenRegionRaw(0, 0, 1000, 1000) == false
    WoundSystemHealthHUDOpen = false
    convars["zc_woundsystem_compat_hide_woundview_backdrop"]._v = "1"
    WSZC.CUHudFiltered = false
    return hid and kept and off
end)()
''')

    rt('R18 *_fill tints black->red by muscle without transparent blink; *_edge and icons untouched', '''
(function()
    WSZC.InstallMaterialTracker()
    local prevCS = _G.WoundSystemClientState
    _G.WoundSystemClientState = {
        PlayerLimbs = {
            head = { muscle = 100 },
            arm_R = { muscle = 50 },
            crus_L = { muscle = 0 },
        }
    }
    surfaceCalls = {}
    surface.SetMaterial(Material("wszc/unitmenu/limbs/head_fill.png"))
    surface.SetDrawColor(0, 0, 0, 255)
    surface.SetMaterial(Material("wszc/unitmenu/limbs/arm_R_fill.png"))
    surface.SetDrawColor(128, 0, 0, 255)
    surface.SetMaterial(Material("wszc/unitmenu/limbs/crus_L_fill.png"))
    surface.SetDrawColor(255, 0, 0, 7) -- C:U flashAlpha near 0 must NOT blink transparent
    surface.SetMaterial(Material("wszc/unitmenu/limbs/head_edge.png"))
    surface.SetDrawColor(60, 70, 80, 255)
    surface.SetMaterial(Material("casunknown-images/icons/fracturedbone.png"))
    surface.SetDrawColor(12, 34, 56, 255)
    _G.WoundSystemClientState = prevCS
    local cols = {}
    for _, c in ipairs(surfaceCalls) do
        if c.kind == "color" then cols[#cols + 1] = c end
    end
    return #cols == 5
       and cols[1].r == 0 and cols[1].g == 0 and cols[1].b == 0 and cols[1].a == 255
       and cols[2].r == 128 and cols[2].g == 0 and cols[2].b == 0 and cols[2].a == 255
       and cols[3].r == 255 and cols[3].g == 0 and cols[3].b == 0 and cols[3].a == 255
       and cols[4].r == 60 and cols[4].g == 70 and cols[4].b == 80 and cols[4].a == 255
       and cols[5].r == 12 and cols[5].g == 34 and cols[5].b == 56 and cols[5].a == 255
end)()
''')

    rt('R19 hand pinned to the REAL cursor, C:U state kept in sync', '''
(function()
    EnableDrawnHandMode()
    mouseX, mouseY = 700, 300
    WoundSystemShrapnelMinigame = { active = true, handScreenX = 100, handScreenY = 100,
        handScreenVelX = 9, handScreenVelY = -7, _hp_acc = 2 }
    local originalStepCalls = 0
    local HandPhysics = { Step = function(mg)
        originalStepCalls = originalStepCalls + 1
        mg.handScreenX, mg.handScreenY = 999, 999
    end }
    local function NativeShrapnelThink()
        HandPhysics.Step(WoundSystemShrapnelMinigame, 0.016, {})
    end
    hook.Add("Think", "WoundSystem_ShrapnelInput", NativeShrapnelThink)
    WSZC.InstallNativeHandPhysicsPin()
    NativeShrapnelThink()
    local nativeStepPinned = HandPhysics._WSZCCursorPinned == true
        and originalStepCalls == 0
        and WoundSystemShrapnelMinigame.handScreenX == 700
        and WoundSystemShrapnelMinigame.handScreenY == 300
    WoundSystemShrapnelMinigame.handScreenX = 100 -- verify Paint sync separately
    WoundSystemShrapnelMinigame.handScreenY = 100
    surfaceCalls = {}
    surface.SetMaterial(Material("casunknown-images/shrapnelminigame/handGraspIdle1.png"))
    surface.DrawTexturedRectRotated(200, 150, 512, 1260, 0)
    local c = surfaceCalls[#surfaceCalls]
    local state = WoundSystemShrapnelMinigame
    local pinned700 = state.handScreenX == 700 and state.handScreenY == 300
    mouseX, mouseY = 0, 0
    local zx, zy = WSZC.PinMinigameHandToCursor(state)
    local originPinned = zx == 0 and zy == 0
        and state.handScreenX == 0 and state.handScreenY == 0
    convars["zc_woundsystem_compat_hand_pin_cursor"]._v = "0"
    NativeShrapnelThink()
    local legacyFallback = originalStepCalls == 1
        and state.handScreenX == 999 and state.handScreenY == 999
    convars["zc_woundsystem_compat_hand_pin_cursor"]._v = "1"
    WoundSystemShrapnelMinigame = { active = false }
    hook.Remove("Think", "WoundSystem_ShrapnelInput")
    mouseX, mouseY = 500, 400
    local gripX = c.x + (0.4 - 0.5) * c.w
    local gripY = c.y + (0.1 - 0.5) * c.h
    return c.kind == "rot" and math.abs(gripX - 700) < 0.001
       and math.abs(gripY - 300) < 0.001
       and math.abs(c.w - 512 * 0.55) < 0.001
       and math.abs(c.h - 1260 * 0.55) < 0.001
       and pinned700
       and state.handScreenVelX == 0 and state.handScreenVelY == 0
       and state._hp_acc == 0 and originPinned and nativeStepPinned and legacyFallback
end)()
''')

    rt('R20 hand_pin_cursor 0 restores C:U\'s own hand position', '''
(function()
    EnableDrawnHandMode()
    convars["zc_woundsystem_compat_hand_pin_cursor"]._v = "0"
    mouseX, mouseY = 700, 300
    local x, y, w, h = WSZC.HandRectForCursor(200, 150, 512, 1260)
    convars["zc_woundsystem_compat_hand_pin_cursor"]._v = "1"
    mouseX, mouseY = 500, 400
    local gripX = x + (0.4 - 0.5) * w
    local gripY = y + (0.1 - 0.5) * h
    return math.abs(gripX - 200) < 0.001 and math.abs(gripY - 150) < 0.001
       and math.abs(w - 512 * 0.55) < 0.001
       and math.abs(h - 1260 * 0.55) < 0.001
end)()
''')

    rt('R21 defaults: cursor-pinned C:U human hand, black doll, empty-click close', '''
(function()
    EnableDrawnHandMode()
    convars["zc_woundsystem_compat_hand_pin_cursor"]._v = "1"
    return convars["zc_woundsystem_compat_handanim"]._v == "1"
       and convars["zc_woundsystem_compat_hide_minigame_hand"]._v == "0"
       and convars["zc_woundsystem_compat_hand_pin_cursor"]._v == "1"
       and convars["zc_woundsystem_compat_hide_woundview_backdrop"]._v == "1"
       and convars["zc_woundsystem_compat_unitmenu_tint"]._v == "1"
       and convars["zc_woundsystem_compat_hide_minigame_cursor"]._v == "1"
       and convars["zc_woundsystem_compat_hide_minigame_text"]._v == "1"
       and convars["zc_woundsystem_compat_fullscreen_native"]._v == "0"
       and convars["zc_woundsystem_compat_native_minigame_zoom"]._v == "0.85"
       and convars["zc_woundsystem_compat_minigame_zoom"]._v == "0.85"
       and convars["zc_woundsystem_compat_close_on_empty_click"]._v == "1"
end)()
''')

    rt('R22 IsMinigameTextFont matches chrome + AED fonts and _scale suffix only', '''
(function()
    return WSZC.IsMinigameTextFont("RetroTooltipTitle") == true
       and WSZC.IsMinigameTextFont("RetroTooltipTitle_150") == true
       and WSZC.IsMinigameTextFont("RetroMinigameGuide_200") == true
       and WSZC.IsMinigameTextFont("RetroTooltipDesc") == true
       and WSZC.IsMinigameTextFont("WoundSystemAEDStatus") == true
       and WSZC.IsMinigameTextFont("WoundSystemAEDStatus_150") == true
       and WSZC.IsMinigameTextFont("BerserkFont") == false
       and WSZC.IsMinigameTextFont("HuyFont") == false
       and WSZC.IsMinigameTextFont("ZB_ProotOSMedium") == false
       and WSZC.IsMinigameTextFont(nil) == false
end)()
''')

    rt('R23 MinigameTextHidden is true only with convar AND an active game', '''
(function()
    local outside = WSZC.MinigameTextHidden() == false
    WoundSystemShrapnelMinigame = { active = true }
    local inside = WSZC.MinigameTextHidden() == true
    convars["zc_woundsystem_compat_hide_minigame_text"]._v = "0"
    local off = WSZC.MinigameTextHidden() == false
    convars["zc_woundsystem_compat_hide_minigame_text"]._v = "1"
    WoundSystemShrapnelMinigame = { active = false }
    WoundSystemSelfHarmMinigame = { active = true }
    local selfharm = WSZC.MinigameTextHidden() == true
    WoundSystemSelfHarmMinigame = { active = false }
    return outside and inside and off and selfharm
end)()
''')

    rt('R24 DrawHeader blanks text/bar, exit no-op, dark backdrop RESTORED', '''
(function()
    WSZC.InstallMinigameTextFilter()
    WoundSystemShrapnelMinigame = { active = true }
    clipCalls = {}
    local icon = Material("casunknown-images/icons/shrapnel.png")
    WoundSystem.MinigameClip.DrawHeader({
        title = "Shrapnel extraction (1/5)", value = "1/5",
        guide = "Pull the shrapnel out slowly.", panelAlpha = 200, mat = icon })
    WoundSystem.MinigameClip.DrawExitGuide()
    WoundSystem.MinigameClip.DrawBackdrop({ alpha = 200 })
    local hdr = clipCalls[1]
    local kept = hdr and hdr.kind == "header" and hdr.d.title == ""
        and hdr.d.value == "" and hdr.d.guide == "" and hdr.d.panelAlpha == 0
        and hdr.d.mat == icon
    -- DrawExitGuide is gone, but the shared dark backdrop MUST still be drawn:
    -- the owner asked for the darkened world behind EVERY minigame again.
    local noChrome = #clipCalls == 2 and clipCalls[2].kind == "backdrop"
    -- The backdrop's draw.RoundedBox would otherwise be eaten by HiddenRegionRaw.
    WSZC.CUHudFiltered = true
    WSZC._MinigameBackdropDrawing = true
    local backdropSurvivesFilter = WSZC.CUHudHiddenRegionRaw(0, 0, 1365, 1079) == false
    WSZC._MinigameBackdropDrawing = false
    WSZC.CUHudFiltered = false
    -- convar 0 restores the chrome functions verbatim
    convars["zc_woundsystem_compat_hide_minigame_text"]._v = "0"
    clipCalls = {}
    WoundSystem.MinigameClip.DrawExitGuide()
    WoundSystem.MinigameClip.DrawBackdrop({ alpha = 200 })
    local restored = #clipCalls == 2 and clipCalls[1].kind == "exit"
        and clipCalls[2].kind == "backdrop"
    convars["zc_woundsystem_compat_hide_minigame_text"]._v = "1"
    -- Convar ON but NO minigame running: the chrome must survive untouched.
    WoundSystemShrapnelMinigame = { active = false }
    clipCalls = {}
    WoundSystem.MinigameClip.DrawHeader({ title = "Keep me", mat = icon })
    local outside = #clipCalls == 1 and clipCalls[1].d.title == "Keep me"
    WoundSystemShrapnelMinigame = { active = false }
    return kept and noChrome and restored and outside and backdropSurvivesFilter
end)()
''')

    rt('R32 minigame cursor survives the C:U watchdog, but our close releases it', '''
(function()
    WSZC._LastMinigameDraw = CurTime()
    local recent = WSZC.MinigameDrawnRecently() == true
    WSZC._LastMinigameDraw = CurTime() - 1
    local stale = WSZC.MinigameDrawnRecently() == false

    clickerOn = true
    WSZC._HoldMinigameCursor = true
    WSZC._AllowClickerRelease = false
    gui.EnableScreenClicker(false)              -- C:U watchdog / radial menu
    local held = clickerOn == true
    WSZC._AllowClickerRelease = true           -- our own DisableMinigameClicker
    gui.EnableScreenClicker(false)
    local released = clickerOn == false
    WSZC._AllowClickerRelease = false
    WSZC._HoldMinigameCursor = false
    return recent and stale and held and released
end)()
''')

    rt('R25 ZCity notification survives, ALL minigame text incl. AED suppressed', '''
(function()
    WSZC.InstallMinigameTextFilter()
    WoundSystemShrapnelMinigame = { active = true }
    textCalls = {}
    draw.SimpleText("Fuck, I just puked blood", "BerserkFont", 10, 10, Color(255,0,0))
    draw.SimpleText("ANALYZING...", "WoundSystemAEDStatus", 10, 20, Color(255,255,255))
    draw.SimpleText("HP 68%", "ZB_ProotOSMedium", 10, 30, Color(255,255,255))
    draw.SimpleText("Shrapnel extraction", "RetroTooltipTitle_150", 10, 40, Color(255,255,255))
    draw.SimpleTextOutlined("Press RMB/ESC to exit", "RetroTooltipTitle", 10, 50, Color(255,255,255))
    local fonts = {}
    for _, c in ipairs(textCalls) do fonts[#fonts + 1] = c.f end
    local inside = #textCalls == 2 and fonts[1] == "BerserkFont"
       and fonts[2] == "ZB_ProotOSMedium"
    -- Outside a minigame the AED label is ordinary HUD text; it must survive.
    WoundSystemShrapnelMinigame = { active = false }
    textCalls = {}
    draw.SimpleText("ANALYZING...", "WoundSystemAEDStatus", 10, 20, Color(255,255,255))
    local outside = #textCalls == 1 and textCalls[1].f == "WoundSystemAEDStatus"
    return inside and outside
end)()
''')

    rt('shrapnel minigame replaces only the extracted shard with the red asset', '''
(function()
    WSZC.InstallMaterialTracker()
    WoundSystemShrapnelMinigame = { active = true }
    local root = "casunknown-images/shrapnelminigame/"
    surfaceCalls = {}
    surface.SetMaterial(Material(root .. "shrapnelpiece.png"))
    local normal = surfaceCalls[#surfaceCalls].m:GetName() == root .. "shrapnelpiece_red.png"
        and WSZC._DrawMaterialName == root .. "shrapnelpiece_red.png"
    local redPadded = Material(root .. "shrapnelpiece_padded_red.png")
    redPadded.IsError = function() return true end
    surface.SetMaterial(Material(root .. "shrapnelpiece_padded.png"))
    local fallback = surfaceCalls[#surfaceCalls].m:GetName() == root .. "shrapnelpiece_padded.png"
    redPadded.IsError = function() return false end
    surface.SetMaterial(Material(root .. "shrapnelpiece_padded.png"))
    local padded = surfaceCalls[#surfaceCalls].m:GetName() == root .. "shrapnelpiece_padded_red.png"
    surface.SetMaterial(Material(root .. "shrapnelpiece_red.png"))
    local alreadyRed = surfaceCalls[#surfaceCalls].m:GetName() == root .. "shrapnelpiece_red.png"
    surface.SetMaterial(Material(root .. "minigameShrapnel.png"))
    local wound = surfaceCalls[#surfaceCalls].m:GetName() == root .. "minigameShrapnel.png"
    surface.SetMaterial(Material("casunknown-images/icons/shrapnel.png"))
    local hud = surfaceCalls[#surfaceCalls].m:GetName() == "casunknown-images/icons/shrapnel.png"
    WoundSystemShrapnelMinigame.active = false
    surface.SetMaterial(Material(root .. "shrapnelpiece.png"))
    local outside = surfaceCalls[#surfaceCalls].m:GetName() == root .. "shrapnelpiece.png"
    return normal and fallback and padded and alreadyRed and wound and hud and outside
end)()
''')

    rt('R26 wound front layer identified; ALL gameplay sprites protected', '''
(function()
    return WSZC.IsMinigameWoundLayer("casunknown-images/shrapnelminigame/minigameShrapnel.png") == true
       and WSZC.IsMinigameWoundLayer("casunknown-images/syringeminigame/minigameshrapnel.png") == true
       and WSZC.IsMinigameWoundLayer("casunknown-images/shrapnelminigame/shrapnelpiece.png") == false
       and WSZC.IsMinigameWoundLayer(nil) == false
       and WSZC.IsMinigameGameplaySprite("casunknown-images/shrapnelminigame/minigameShrapnel.png") == true
       and WSZC.IsMinigameGameplaySprite("casunknown-images/shrapnelminigame/shrapnelpiece.png") == true
       and WSZC.IsMinigameGameplaySprite("casunknown-images/shrapnelminigame/handGraspIdle1.png") == true
       and WSZC.IsMinigameGameplaySprite("casunknown-images/bandageminigame/bandageOuter.png") == true
       and WSZC.IsMinigameGameplaySprite("casunknown-images/icons/fracturedbone.png") == true
       and WSZC.IsMinigameGameplaySprite(nil) == false
end)()
''')

    rt('R27 wound front layer + shrapnel piece BOTH draw while text is hidden', '''
(function()
    WoundSystemShrapnelMinigame = { active = true }
    convars["zc_woundsystem_compat_hide_minigame_text"]._v = "1"
    surfaceCalls = {}
    surface.SetMaterial(Material("casunknown-images/shrapnelminigame/minigameShrapnel.png"))
    surface.DrawTexturedRect(0, 700, 1000, 600)
    surface.SetMaterial(Material("casunknown-images/shrapnelminigame/shrapnelpiece.png"))
    surface.DrawTexturedRect(500, 400, 40, 200)
    local onRects = 0
    for _, c in ipairs(surfaceCalls) do if c.kind == "rect" then onRects = onRects + 1 end end
    convars["zc_woundsystem_compat_hide_minigame_text"]._v = "0"
    surfaceCalls = {}
    surface.SetMaterial(Material("casunknown-images/shrapnelminigame/minigameShrapnel.png"))
    surface.DrawTexturedRect(0, 700, 1000, 600)
    local offRects = 0
    for _, c in ipairs(surfaceCalls) do if c.kind == "rect" then offRects = offRects + 1 end end
    convars["zc_woundsystem_compat_hide_minigame_text"]._v = "1"
    WoundSystemShrapnelMinigame = { active = false }
    return onRects == 2 and offRects == 1
end)()
''')

    rt('R28 ApplyDoll writes compensated 2222 geometry and visible hitboxes', '''
(function()
    local mats, limbs = {}, {}
    for id, g in pairs(WSZC_UNITMENU_LIMB_GEOMETRY) do
        mats[id] = { fill = Material("wszc/unitmenu/limbs/" .. id .. "_fill.png"),
                     edge = Material("wszc/unitmenu/limbs/" .. id .. "_edge.png"),
                     cx = g.cx, cy = g.cy, w = g.w, h = g.h,
                     hoverW = g.hoverW, hoverH = g.hoverH }
        limbs[#limbs + 1] = { id = id, matM = Material("cu/m"), matO = Material("cu/o"),
                              ox = 0, oy = 0, size = 2, sourceW = 64, sourceH = 64,
                              texturePadding = 1, flip = true }
    end
    local k = convars["zc_woundsystem_compat_unitmenu_scale"]:GetFloat()
    WSZC.ApplyUnitmenuDoll(limbs, mats, k)
    local head, neck
    for _, l in ipairs(limbs) do
        if l.id == "head" then head = l end
        if l.id == "neck" then neck = l end
    end
    local gh = WSZC_UNITMENU_LIMB_GEOMETRY.head
    local gn = WSZC_UNITMENU_LIMB_GEOMETRY.neck
    local expectedSize, centreOY = WSZC.UnitmenuReferenceDollTransform(k)
    return #limbs == 17 and head ~= nil and neck ~= nil
       and neck.matM == mats.neck.fill and neck.matO == mats.neck.edge
       and neck.sourceW == gn.hoverW and neck.sourceH == gn.hoverH
       and math.abs(neck.oy - ((gn.cy - 750) * expectedSize + centreOY)) < 0.001
       and head.matM == mats.head.fill and head.matO == mats.head.edge
       and math.abs(head.ox - (gh.cx - 750) * expectedSize) < 0.001
       and math.abs(head.oy - ((gh.cy - 750) * expectedSize + centreOY)) < 0.001
       and head.size == expectedSize and head.sourceW == gh.hoverW and head.sourceH == gh.hoverH
       and head.texturePadding == 0 and head.flip == false
       and head._WSZCUnitmenuOriginal.matM ~= nil
end)()
''')

    rt('R38 native first-life insertion creates independent neck + pelvis states', '''
(function()
    local mats, limbs = {}, {}
    for id, g in pairs(WSZC_UNITMENU_LIMB_GEOMETRY) do
        mats[id] = { fill = Material("wszc/unitmenu/limbs/" .. id .. "_fill.png"),
                     edge = Material("wszc/unitmenu/limbs/" .. id .. "_edge.png"),
                     cx = g.cx, cy = g.cy, w = g.w, h = g.h,
                     hoverW = g.hoverW, hoverH = g.hoverH }
        if id ~= "neck" and id ~= "pelvis" then
            limbs[#limbs + 1] = { id = id, matM = Material("cu/m"), matO = Material("cu/o"),
                ox = 0, oy = 0, size = 2, order = id == "head" and 8 or 5,
                sourceW = 64, sourceH = 64, texturePadding = 1, flip = true }
        end
    end
    local GUIState = { HoverAnims = { head = 0 }, LastHoverStates = { head = false },
        HudLimbShakeScratch = {}, openTime = 0 }
    local function CUFactory(GUIState, Limbs)
        return function() return GUIState, Limbs end
    end
    hook.Add("HUDPaint", "WoundDollAndPanel", CUFactory(GUIState, limbs))
    WoundSystemClientState = { PlayerLimbs = {
        head = { skin = 12, muscle = 34, broken = true, customStatuses = { OLD = true } },
        abdomen = { skin = 56, muscle = 78, broken = false, customStatuses = { OLD = true } },
    } }
    WSZC.ClearCULimbsCache()
    WSZC.ApplyUnitmenuDoll(limbs, mats, 0.25)
    local headAt, neckAt, abdomenAt, pelvisAt = 0, 0, 0, 0
    for i, limb in ipairs(limbs) do
        if limb.id == "head" then headAt = i end
        if limb.id == "neck" then neckAt = i end
        if limb.id == "abdomen" then abdomenAt = i end
        if limb.id == "pelvis" then pelvisAt = i end
    end
    local state = WoundSystemClientState.PlayerLimbs.neck
    local pelvisState = WoundSystemClientState.PlayerLimbs.pelvis
    local created = #limbs == 17 and neckAt == headAt + 1 and pelvisAt == abdomenAt + 1
        and GUIState.HoverAnims.neck == 0 and GUIState.LastHoverStates.neck == false
        and GUIState.HoverAnims.pelvis == 0 and GUIState.LastHoverStates.pelvis == false
        and state and state.skin == 100 and state.muscle == 100
        and state.broken == false and state.customStatuses.OLD == nil
        and pelvisState and pelvisState.skin == 100 and pelvisState.muscle == 100
        and pelvisState.customStatuses.OLD == nil
    WSZC.ApplyUnitmenuDoll(limbs, mats, 0.25)
    local idempotent = #limbs == 17
    local restored = WSZC.RestoreUnitmenuDoll() and #limbs == 15
    WSZC.ApplyUnitmenuDoll(limbs, mats, 0.25)
    _WSZCTestLimbs, _WSZCTestMats = limbs, mats
    return created and idempotent and restored and #limbs == 17
end)()
''')

    rt('R39 neck hitbox remains selectable and old hover card is removed', '''
(function()
    local neck
    for _, limb in ipairs(_WSZCTestLimbs) do if limb.id == "neck" then neck = limb end end
    local scale = ScrH() / 1080
    local dollScale = 1.5 * scale
    mouseX = ScrW() / 2 + neck.ox * dollScale
    mouseY = ScrH() / 2 + 20 * scale + neck.oy * dollScale
    local hit = WSZC.UnitmenuHover(mouseX, mouseY)
    return hit and hit.id == "neck"
        and (not hook._t.PostDrawHUD or not hook._t.PostDrawHUD.WSZC_UnitmenuLimbTooltip)
        and WSZC.UnitmenuTooltipLines == nil
end)()
''')

    rt('R41 pelvis retains its hitbox and native state without a hover card', '''
(function()
    local pelvis
    for _, limb in ipairs(_WSZCTestLimbs) do if limb.id == "pelvis" then pelvis = limb end end
    local scale = ScrH() / 1080
    local dollScale = 1.5 * scale
    mouseX = ScrW() / 2 + pelvis.ox * dollScale
    mouseY = ScrH() / 2 + 20 * scale + pelvis.oy * dollScale
    local hit = WSZC.UnitmenuHover(mouseX, mouseY)
    local state = WoundSystemClientState.PlayerLimbs.pelvis
    return hit and hit.id == "pelvis" and hit.state == state
        and (not hook._t.PostDrawHUD or not hook._t.PostDrawHUD.WSZC_UnitmenuLimbTooltip)
end)()
''')

    rt('R40 Broken neck moodle reads neck.broken, never a duplicate head fracture', '''
(function()
    WoundSystem.Moodles = { Definitions = {}, DefById = {}, rebuilt = false }
    WoundSystem.Moodles.Register = function(id, def)
        WoundSystem.Moodles.DefById[id] = def
        WoundSystem.Moodles.Definitions[#WoundSystem.Moodles.Definitions + 1] = def
    end
    WoundSystem.Moodles.RebuildNow = function() WoundSystem.Moodles.rebuilt = true end
    local states = WoundSystemClientState.PlayerLimbs
    states.neck.broken, states.neck.boneHealTimer = true, 50
    states.head.broken = true
    local installed = WSZC.InstallNeckMoodle()
    local def = WoundSystem.Moodles.DefById.brokenneck
    local mood = def and def.condition({ limbs = states }) or nil
    states.neck.broken = false
    local headOnly = def and def.condition({ limbs = states }) or false
    hook.Remove("HUDPaint", "WoundDollAndPanel")
    WSZC.ClearCULimbsCache()
    return installed and mood and mood.title == "Broken neck"
       and mood.desc == "The neck is fractured." and mood.intensity == 2
       and headOnly == false and WoundSystem.Moodles.rebuilt
end)()
''')

    rt('R30 empty-click predicate: empty corners close, doll/slots/action do not', '''
(function()
    local function S() return 1 end
    local far = WSZC.WoundViewEmptyClick(960, 60, S())
    local panel = WSZC.WoundViewEmptyClick(100, 400, S())
    local doll = WSZC.WoundViewEmptyClick(500, 500, S())
    local slot = WSZC.WoundViewEmptyClick(500, 795, S())
    WoundSystemActionButtonPos = { x = 700, y = 300 }
    local action = WSZC.WoundViewEmptyClick(710, 305, S())
    WoundSystemActionButtonPos = { x = nil, y = nil }
    local badArgs = WSZC.WoundViewEmptyClick(nil, 10, S())
    return far == true and panel == false and doll == false
       and slot == false and action == false and badArgs == false
end)()
''')

    rt('R31 gameplay sprites survive the WoundView hidden-region filter', '''
(function()
    WSZC.CUHudFiltered = true; WSZC.CUDeathVisualsHidden = false
    WoundSystemHealthHUDOpen = true
    surface.SetMaterial(Material("casunknown-images/shrapnelminigame/minigameShrapnel.png"))
    local wound = WSZC.CUHudHiddenRegion(0, 0, 1000, 1000)
    surface.SetMaterial(Material("casunknown-images/shrapnelminigame/shrapnelpiece.png"))
    local piece = WSZC.CUHudHiddenRegion(0, 0, 1000, 1000)
    surface.SetMaterial(Material("casunknown-images/bandageminigame/bandageOuter.png"))
    local bandage = WSZC.CUHudHiddenRegion(0, 0, 1000, 1000)
    surface.SetMaterial(Material("cu/scanner"))
    local chrome = WSZC.CUHudHiddenRegion(0, 0, 1000, 1000)
    WSZC.CUHudFiltered = false
    WoundSystemHealthHUDOpen = false
    return wound == false and piece == false and bandage == false and chrome == true
end)()
''')

    rt('R29 FindCULimbs falls back to a differently-named HUD hook', '''
(function()
    WSZC.ClearCULimbsCache()
    local fake = {}
    for i = 1, 15 do
        fake[i] = { id = "limb" .. i, matM = Material("cu/m"), matO = Material("cu/o"),
                    ox = i, oy = -i, size = 2 }
    end
    local function otherHook() return fake[1] end
    hook.Add("HUDPaint", "WSZCTestOtherHook", otherHook)
    local found = WSZC.FindCULimbs()
    hook.Remove("HUDPaint", "WSZCTestOtherHook")
    WSZC.ClearCULimbsCache()
    return found ~= nil and #found == 15 and found[1].id == "limb1"
end)()
''')

    rt('R33 human hand + hidden arrow + lower action button + hard post-game release', '''
(function()
    EnableDrawnHandMode()
    convars["zc_woundsystem_compat_hand_pin_cursor"]._v = "0"
    local handDefault = convars["zc_woundsystem_compat_hide_minigame_cursor"]._v == "1"
        and convars["zc_woundsystem_compat_hide_minigame_hand"]._v == "0"
        and convars["zc_woundsystem_compat_handanim"]._v == "1"
    local visibleHand = WSZC.UnitmenuHandAlpha(153) == 255
        and WSZC.ShowMinigameHand() == true

    WoundSystemLimbUIConfig = { ShrapnelPoint = { OffsetY = -60,
        Actions = { DISLOCATION = { OffsetY = -60 },
                    SHRAPNEL = { OffsetY = -30 } } } }
    WoundSystemActionButtonPos = { x = 100, y = 100 }
    local patched = WSZC.PatchActionButtonOffset() == true
        and WoundSystemLimbUIConfig.ShrapnelPoint.OffsetY == -14
        and WoundSystemLimbUIConfig.ShrapnelPoint.Actions.DISLOCATION.OffsetY == -14
        and WoundSystemLimbUIConfig.ShrapnelPoint.Actions.SHRAPNEL.OffsetY == -14
        and WoundSystemActionButtonPos.y == nil
    local twice = WSZC.PatchActionButtonOffset() == false

    clickerOn = true
    WSZC._HoldMinigameCursor = true
    WSZC.BlankMinigameCursor()
    WSZC.ForceReleaseMinigameCursor()
    local released = clickerOn == false
        and WSZC._HoldMinigameCursor == false
        and worldPanel:GetCursor() == "arrow"
        and (WSZC._MinigameForceOffUntil or 0) > CurTime()
    return handDefault and visibleHand and patched and twice and released
end)()
''')

    rt('R35 archived no-hand settings migrate once, then user choices stay untouched', '''
(function()
    RestoreStandardCursorMode()
    convars["zc_woundsystem_compat_hand_cursor_scale"]._v = "0.45"
    convars["zc_woundsystem_compat_handanim_scale"]._v = "0.55"
    convars["zc_woundsystem_compat_hand_pivot_x"]._v = "0.32"
    convars["zc_woundsystem_compat_hand_pivot_y"]._v = "0.11"
    convars["zc_woundsystem_compat_minigame_zoom"]._v = "1"
    convars["zc_woundsystem_compat_native_minigame_zoom"]._v = "1"
    convars["zc_woundsystem_compat_hand_mode_revision"]._v = "4"
    local migrated = WSZC.MigrateHumanHandDefaults() == true
        and convars["zc_woundsystem_compat_handanim"]._v == "1"
        and convars["zc_woundsystem_compat_hand_cursor_scale"]._v == "0.55"
        and convars["zc_woundsystem_compat_handanim_scale"]._v == "1"
        and convars["zc_woundsystem_compat_hide_minigame_hand"]._v == "0"
        and convars["zc_woundsystem_compat_hide_minigame_cursor"]._v == "1"
        and convars["zc_woundsystem_compat_hand_pivot_x"]._v == "0.4"
        and convars["zc_woundsystem_compat_hand_pivot_y"]._v == "0.1"
        and convars["zc_woundsystem_compat_minigame_zoom"]._v == "0.85"
        and convars["zc_woundsystem_compat_native_minigame_zoom"]._v == "0.85"
        and convars["zc_woundsystem_compat_hand_pin_cursor"]._v == "1"
        and convars["zc_woundsystem_compat_hand_mode_revision"]._v == "6"
    convars["zc_woundsystem_compat_handanim_scale"]._v = "0.9"
    convars["zc_woundsystem_compat_hide_minigame_hand"]._v = "1"
    local preserved = WSZC.MigrateHumanHandDefaults() == false
        and convars["zc_woundsystem_compat_handanim_scale"]._v == "0.9"
        and convars["zc_woundsystem_compat_hide_minigame_hand"]._v == "1"
    convars["zc_woundsystem_compat_hand_mode_revision"]._v = "0"
    WSZC.MigrateHumanHandDefaults()
    return migrated and preserved
end)()
''')

    rt('R36 cursor watchdog leaves the arrow hidden on every refresh', '''
(function()
    EnableDrawnHandMode()
    WoundSystemShrapnelMinigame = { active = true }
    WSZC._MinigameForceOffUntil = 0
    WSZC._NextCursorFix = 0
    cursorValue = "arrow"
    hook._t["Think"]["WSZC_MinigameCursorWatch"]()
    local first = clickerOn == true and cursorValue == "blank"
    -- Simulate C:U/ZCity resetting the VGUI cursor between watchdog ticks.
    cursorValue = "arrow"
    WSZC._NextCursorFix = 0
    hook._t["Think"]["WSZC_MinigameCursorWatch"]()
    local second = clickerOn == true and cursorValue == "blank"
    WoundSystemShrapnelMinigame = { active = false }
    WSZC.ForceReleaseMinigameCursor()
    return first and second and cursorValue == "arrow"
end)()
''')

    rt('R37 hand pivot remains exact at zero and arbitrary native rotations', '''
(function()
    EnableDrawnHandMode()
    convars["zc_woundsystem_compat_hand_pin_cursor"]._v = "0"
    local good = true
    for _, rot in ipairs({ 0, 37, 90, 290 }) do
        local x, y, w, h = WSZC.HandRectForCursor(500, 400, 512, 1260, rot)
        local a = math.rad(rot)
        local co, si = math.cos(a), math.sin(a)
        local ox, oy = (0.4 - 0.5) * w, (0.1 - 0.5) * h
        local gripX = x + ox * co - oy * si
        local gripY = y + ox * si + oy * co
        if math.abs(gripX - 500) > 0.001 or math.abs(gripY - 400) > 0.001 then
            good = false
        end
        if math.abs(w - 512 * 0.55) > 0.001
            or math.abs(h - 1260 * 0.55) > 0.001 then good = false end
    end
    return good
end)()
''')

    rt('R34 added WoundView cards are gone; unconscious gate remains', '''
(function()
    local ply = { organism = {}, Alive = function() return true end }
    LocalPlayer = function() return ply end
    WoundSystemHealthHUDOpen = true
    local noCustomLayer = WSZC.DrawWoundViewForeground == nil
        and WSZC.WoundViewPolishActive == nil
        and (not hook._t["PostDrawHUD"]
            or not hook._t["PostDrawHUD"]["WSZC_WoundViewPolishForeground"])
    local conscious = WSZC.MinigameContextOK()
    ply.organism.otrub = true
    local unconsciousBlocked = not WSZC.MinigameContextOK()
    ply.organism.otrub = nil
    WoundSystemHealthHUDOpen = false
    return noCustomLayer and conscious and unconsciousBlocked
end)()
''')

    rt('R38 native HUD hides disinfect/injection but keeps ordinary bleed/fracture/dislocation/arterial', '''
(function()
    filterCalls = {}
    TEXFILTER = { LINEAR = 77 }
    render = {
        PushFilterMag = function(v) filterCalls[#filterCalls + 1] = "mag:" .. v end,
        PushFilterMin = function(v) filterCalls[#filterCalls + 1] = "min:" .. v end,
        PopFilterMin = function() filterCalls[#filterCalls + 1] = "popMin" end,
        PopFilterMag = function() filterCalls[#filterCalls + 1] = "popMag" end,
    }
    Icons.disinfected = Material("native/disinfected")
    Icons.infectionneutral = Material("native/infection")
    Icons.smallbleed = Material("native/bleeding")
    Icons.fracture = Material("native/fracture")
    Icons.dislocate = Material("native/dislocation")
    Icons.injection = Material("native/injection")
    local arterial = Material("zcity_delta_moodles/48px-moodle_heavybleeding_2_critical.png")
    local handState = { disinfectTime = 120, infection = 4 }
    WoundSystemClientState = { PlayerLimbs = { hand_R = handState } }

    local function AddHudIcon(items, mat)
        items[#items + 1] = mat
    end
    local function NativeWoundView()
        local items = {}
        AddHudIcon(items, Icons.disinfected)
        AddHudIcon(items, Icons.infectionneutral)
        AddHudIcon(items, Icons.fracture)
        AddHudIcon(items, Icons.dislocate)
        AddHudIcon(items, Icons.injection)
        AddHudIcon(items, Icons.smallbleed)
        AddHudIcon(items, arterial)
        NativeWoundViewIcons = items
    end
    hook.Add("HUDPaint", "WoundDollAndPanel", NativeWoundView)
    local installed = WSZC.InstallCUHudFilter()
    local installedAgain = WSZC.InstallDisinfectedIconFilter()
    hook._t["HUDPaint"]["WoundDollAndPanel"]()

    local count, infection, fracture, dislocation, bleedKept, arterialKept = 0, 0, 0, 0, 0, 0
    for _, mat in ipairs(NativeWoundViewIcons or {}) do
        count = count + 1
        if mat == Icons.infectionneutral then infection = infection + 1 end
        if mat == Icons.fracture then fracture = fracture + 1 end
        if mat == Icons.dislocate then dislocation = dislocation + 1 end
        if mat == Icons.smallbleed then bleedKept = bleedKept + 1 end
        if mat == arterial then arterialKept = arterialKept + 1 end
    end
    local filters = table.concat(filterCalls, ",")
    return installed and installedAgain and count == 5
        and infection == 1 and fracture == 1 and dislocation == 1
        and bleedKept == 1 and arterialKept == 1
        and handState.disinfectTime == 120
        and handState.infection == 4
        and filters == "" -- no LINEAR smoothing / no filter-stack side effects
end)()
''')

    # Live C:U keeps Icons in a local upvalue, not in _G.  Exercise that exact
    # load shape and put AddHudIcon one closure below WoundDollAndPanel.
    rt('R42 local/nested Icons and exact paths hide processing/injection but keep ordinary bleed/fracture/shrapnel/infection/arterial', '''
(function()
    local nativeItems = {}
    local Icons = {
        disinfected = Material("native/local_disinfected"),
        shrapnel = Material("casunknown-images/icons/shrapnel.png"),
        infection_up = Material("casunknown-images/icons/infectionup.png"),
    }
    local function AddHudIcon(items, mat) table.insert(items, mat) end
    local function DrawNativeIcons()
        AddHudIcon(nativeItems, Icons.disinfected)
        AddHudIcon(nativeItems, Icons.shrapnel)
        AddHudIcon(nativeItems, Icons.infection_up)
    end
    local function NativeWoundView() DrawNativeIcons() end
    hook.Add("HUDPaint", "WoundDollAndPanel", NativeWoundView)
    _G.Icons = nil
    local installed = WSZC.InstallDisinfectedIconFilter()
    NativeWoundView()
    local localIconsOK = installed == true and #nativeItems == 2
        and nativeItems[1] == Icons.shrapnel
        and nativeItems[2] == Icons.infection_up

    -- No Icons upvalue/global at all: exact C:U paths keep ordinary bleeding + arterial.
    local pathItems = {}
    local function AddHudIcon(items, mat) table.insert(items, mat) end
    local fracture = Material("casunknown-images/icons/fracturedbone.png")
    local ordinaryBleed = Material("wszc/unitmenu/status/bleeding_padded.png")
    local arterial = Material("zcity_delta_moodles/48px-moodle_heavybleeding_2_critical.png")
    local function PathNativeWoundView()
        AddHudIcon(pathItems, Material("casunknown-images/icons/disinfected.png"))
        AddHudIcon(pathItems, fracture)
        AddHudIcon(pathItems, ordinaryBleed)
        AddHudIcon(pathItems, arterial)
    end
    hook.Add("HUDPaint", "WoundDollAndPanel", PathNativeWoundView)
    local pathInstalled = WSZC.InstallDisinfectedIconFilter()
    PathNativeWoundView()
    return localIconsOK and pathInstalled and #pathItems == 3
        and pathItems[1] == fracture and pathItems[2] == ordinaryBleed and pathItems[3] == arterial
end)()
''')

    rt('R44 injection draw filter is WoundView-scoped while ordinary bleed and arterial are visible', '''
(function()
    local oldFlag = WSZC.CUStatusIconFiltered
    WSZC.CUStatusIconFiltered = true
    WSZC._DrawMaterialName = "casunknown-images/icons/injectionwound.png"
    local injectionHidden = WSZC.HiddenNativeStatusIconDraw()
    WSZC._DrawMaterialName = "wszc/unitmenu/status/bleeding.png"
    local ordinaryBloodKept = not WSZC.HiddenNativeStatusIconDraw()
        and WSZC.IsDollDrawMaterial(WSZC._DrawMaterialName)
    WSZC._DrawMaterialName = "zcity_delta_moodles/48px-moodle_heavybleeding_2_critical.png"
    local arterialKept = not WSZC.HiddenNativeStatusIconDraw()
        and WSZC.IsDollDrawMaterial(WSZC._DrawMaterialName)
    WSZC.CUStatusIconFiltered = false
    WSZC._DrawMaterialName = "casunknown-images/icons/injectionwound.png"
    local outsideWoundViewKept = not WSZC.HiddenNativeStatusIconDraw()
    WSZC.CUStatusIconFiltered = oldFlag
    return injectionHidden and ordinaryBloodKept and arterialKept and outsideWoundViewKept
end)()
''')

    rt('R40 2222 screen scale/centre are invariant under native UI scale', '''
(function()
    local oldW, oldH, oldGetConVar = ScrW, ScrH, GetConVar
    ScrW, ScrH = function() return 1365 end, function() return 1079 end
    local uiValue = 1
    GetConVar = function(name)
        if name == "woundsys_ui_scale" then
            return { GetFloat = function() return uiValue end }
        end
        return nil
    end
    local gh = WSZC_UNITMENU_LIMB_GEOMETRY.head
    local ok, previousSize = true, nil
    for _, ui in ipairs({ 0.6, 1.0, 1.25, 1.6 }) do
        uiValue = ui
        local size, centreOY, targetScale, targetCY = WSZC.UnitmenuReferenceDollTransform(0.25)
        local nativeScale = (1079 / 1080) * ui
        local nativeDollScale = 1.5 * nativeScale
        local nativeCY = 1079 / 2 + 20 * nativeScale
        local actualScale = nativeDollScale * size
        local actualCX = 1365 / 2 + (gh.cx - 750) * size * nativeDollScale
        local actualCY = nativeCY + ((gh.cy - 750) * size + centreOY) * nativeDollScale
        local expectedCX = 1365 / 2 + (gh.cx - 750) * 0.4155
        local expectedCY = 558.2 + (gh.cy - 750) * 0.4155
        if math.abs(actualScale - 0.4155) > 0.00001
            or math.abs(actualCX - expectedCX) > 0.00001
            or math.abs(actualCY - expectedCY) > 0.00001
            or math.abs(targetScale - 0.4155) > 0.00001
            or math.abs(targetCY - 558.2) > 0.00001 then ok = false end
        if previousSize and math.abs(previousSize - size) < 0.00001 then ok = false end
        previousSize = size
    end
    ScrW, ScrH, GetConVar = oldW, oldH, oldGetConVar
    return ok
end)()
''')

    rt('R43 self and remote both hide C:U inventory; virtual slot 6 remains writable', '''
(function()
    WSZC.InstallCUInventoryProxy()
    local real = WSZC._CURealInventory
    real[1] = { type = "tool", toolName = "MORPHINE", durability = 10 }
    WSZC.RemoteMedical = nil
    WSZC.CUHudFiltered = true
    local selfSlotHidden = WoundSystemInventorySlots[1].type == "empty"
        and WSZC.CUHudHiddenRegionRaw(760, 240, 50, 50) == true
    WoundSystemInventorySlots[1] = { type = "tool", toolName = "BAD" }
    local selfWriteBlocked = real[1].toolName == "MORPHINE"
    WSZC.RemoteMedical = { active = true }
    local remoteSlotHidden = WoundSystemInventorySlots[1].type == "empty"
        and WSZC.CUHudHiddenRegionRaw(760, 240, 50, 50) == true
    WoundSystemInventorySlots[1] = { type = "tool", toolName = "AED", durability = 5 }
    local remoteWriteBlocked = real[1].toolName == "MORPHINE"
    WoundSystemInventorySlots[6] = { type = "tool", toolName = "GAUZE", durability = 20 }
    local virtualSlotWritable = real[6] == WoundSystemInventorySlots[6]
        and real[6].toolName == "GAUZE"
    WSZC.RemoteMedical = nil
    WSZC.CUHudFiltered = false
    return selfSlotHidden and selfWriteBlocked and remoteSlotHidden
        and remoteWriteBlocked and virtualSlotWritable
end)()
''')

# Remote treatment uses isolated server/client Lua states and representative
# native C:U receivers.  It exercises behavior rather than source markers.
if LuaRuntime is not None:
    remote_fixture = (ROOT / 'tools/tests/remote_medical_runtime.lua').read_text(encoding='utf-8')
    for mode, remote_source in (('server', remote_server_s), ('client', remote_client_s)):
        remote_lua = LuaRuntime(unpack_returned_tuples=True)
        remote_lua.globals().MODE = mode
        remote_lua.globals().REMOTE_SOURCE = remote_source
        remote_lua.globals().MINIGAME_SOURCE = (SERVER / 'sv_zcity_woundsystem_compat_minigames.lua').read_text(encoding='utf-8')
        try:
            remote_cases = remote_lua.execute(remote_fixture)
            invoke = remote_lua.eval('function(fn) local ok, err = pcall(fn); return ok, err end')
            index = 1
            while remote_cases[index] is not None:
                case = remote_cases[index]
                try:
                    ok, err = invoke(case.fn)
                    check(case.name, ok)
                    if not ok:
                        print('ERR', case.name, str(err)[:240])
                except Exception as exc:
                    check(case.name, False)
                    print('ERR', case.name, type(exc).__name__, str(exc)[:240])
                index += 1
        except Exception as exc:
            check('REMOTE_' + mode.upper() + '_HARNESS_LOAD', False)
            print('ERR REMOTE_' + mode.upper() + '_HARNESS_LOAD', type(exc).__name__, str(exc)[:300])

if LuaRuntime is not None:
    radial_lua = LuaRuntime(unpack_returned_tuples=True)
    radial_lua.execute(r'''
CLIENT = true; SERVER = false
WSZC = {}
Blocked = true
concommand = { Add = function() end }
CreateClientConVar = function() return { GetBool = function() return true end } end
GetConVar = function() return nil end
GetGlobalBool = function() return true end
hook = { _t = {}, Add = function(event, name, fn)
    hook._t[event] = hook._t[event] or {}; hook._t[event][name] = fn
end }
timer = { Simple = function() end }
hg = { radialOptions = {} }
''')
    radial_lua.execute(inspect_s)
    radial_filter = radial_lua.execute(r'''
WSZC.LegacyRadialMedicineBlocked = function() return Blocked end
local function legacy(label) return { function() end, label } end
hg.radialOptions = {
    legacy("Fix dislocation (leg)"),
    legacy("Fix Steven's dislocation (arm)"),
    { function() end, "Do Gesture\nRMB - Menu" },
    { function() end, "Dislocation inspection", _WSZCInspect = true },
    { function() end, "Dislocation patient", _WSZCRemoteInspect = true },
}
hook._t["radialOptions"]["zzzz_WSZC_DisableLegacyMedicine"]()
local filtered = #hg.radialOptions == 3
    and hg.radialOptions[1][2] == "Do Gesture\nRMB - Menu"
    and hg.radialOptions[2]._WSZCInspect == true
    and hg.radialOptions[3]._WSZCRemoteInspect == true
Blocked = false
hg.radialOptions[#hg.radialOptions + 1] = legacy("Fix dislocation (leg)")
hook._t["radialOptions"]["zzzz_WSZC_DisableLegacyMedicine"]()
return filtered and #hg.radialOptions == 4
''')
    check('R44 ready-only radial filter removes legacy reduction, preserves WSZC/gestures', radial_filter)

    unconscious_inspection = radial_lua.execute(r'''
IsValid = function(v) return v ~= nil end
local ply = { alive = true, nw = true }
ply.Alive = function(self) return self.alive end
ply.GetNWBool = function(self, key, fallback)
    if key == "WoundSystemUnconscious" then return self.nw end
    return fallback
end
ply.SetNWBool = function(self, key, value)
    if key == "WoundSystemUnconscious" then self.nw = value end
end
LocalPlayer = function() return ply end
hook.GetTable = function() return hook._t end
hg.WoundBridge = {}
WoundSystem = { Health = {} }
local CardioState = { unconscious = true }
local GUIState = { hudOpen = false }
WoundSystemHealthHUDOpen = false
function WoundSystem.OpenHealthHUD()
    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:Alive() then return end
    if CardioState.unconscious or lp:GetNWBool("WoundSystemUnconscious", false) then return end
    GUIState.hudOpen = true
    WoundSystemHealthHUDOpen = true
end
local function NativeThink()
    if CardioState.unconscious or ply:GetNWBool("WoundSystemUnconscious", false) then
        GUIState.hudOpen = false
        WoundSystemHealthHUDOpen = false
    else
        WoundSystemHealthHUDOpen = GUIState.hudOpen
    end
end
hook.Add("Think", "ToggleHUDInput", NativeThink)

-- Prove the representative native guard really closes the panel first.
GUIState.hudOpen = true; WoundSystemHealthHUDOpen = true
NativeThink()
local nativeBlocked = GUIState.hudOpen == false and WoundSystemHealthHUDOpen == false
-- Remote treatment leaves a transparent OpenHealthHUD wrapper installed.
local nativeOpen = WoundSystem.OpenHealthHUD
WoundSystem.OpenHealthHUD = function(...) return nativeOpen(...) end
local opened = WSZC.OpenHealthHUDForInspection()
local restoredAfterOpen = opened and CardioState.unconscious == true and ply.nw == true
hook.GetTable().Think.ToggleHUDInput()
local stayedOpen = GUIState.hudOpen == true and WoundSystemHealthHUDOpen == true
    and WSZC._InspectionWhileUnconscious == true
    and CardioState.unconscious == true and ply.nw == true
GUIState.hudOpen = false; WoundSystemHealthHUDOpen = false
hook.GetTable().Think.ToggleHUDInput()
local closedCleanly = WSZC._InspectionWhileUnconscious == nil
    and GUIState.hudOpen == false and CardioState.unconscious == true and ply.nw == true
return nativeBlocked and restoredAfterOpen and stayedOpen and closedCleanly
''')
    check('R45 brain-injury unconscious inspection opens, survives Think and closes cleanly', unconscious_inspection)

    no_medicine_ui = radial_lua.execute(r'''
local nativeCalls = 0
local nativeAction = function() nativeCalls = nativeCalls + 1 end
_G.WoundSystemDrawLimbActionPoint = nativeAction
local patient = { alive = true }
local medic = { alive = true, Alive = function(self) return self.alive end }
LocalPlayer = function() return medic end
WSZC.RemoteMedical = { active = true, target = patient }
WSZC.InstallUnconsciousInspectionBridge()
local callsAfterInstall = _G.WoundSystemDrawLimbActionPoint == nativeAction
_G.WoundSystemDrawLimbActionPoint("hand_R", { shrapnel = 1 })
local post = hook.GetTable().PostDrawHUD or {}
return callsAfterInstall and nativeCalls == 1
    and post.WSZC_WoundViewTreatHUD == nil
    and WSZC.BuildLimbContextActions == nil
    and WSZC.SendWoundViewTreat == nil
''')
    check('R46 WoundView preserves native limb actions without adding medicine controls', no_medicine_ui)

    native_gui = src('woundsystem_zcity_compat/lua/wszc_vendor/cu/woundsystem/client/cl_health_gui.lua')
    start = native_gui.index('function WoundSystemDrawLimbActionPoint(')
    end = native_gui.index('hook.Add("HUDPaint", "WoundDollAndPanel"', start)
    radial_lua.execute(r'''
WoundSystemActionButtonPos = { x = nil, y = nil }
WoundSystemLimbUIConfig = { ShrapnelPoint = { TextEnabled = false } }
GUIState = { lastMouseState = false }
Icons = { uiPoint = {} }
render = { SetScissorRect = function() end }
surface = { SetDrawColor = function() end }
draw = { SimpleText = function() end }
math.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
RealFrameTime = function() return 0.1 end
Lerp = function(t, a, b) return a + t * (b - a) end
SetGuiMaterial = function() end
DrawRectInt = function() end
WoundSystemTooltipText = function() return "", "" end
WoundSystemQueueDirectTooltip = function() end
NativeRequests = {}
RequestShrapnelMinigameStart = function(id) NativeRequests[#NativeRequests + 1] = {"shrapnel", id} end
RequestDislocationMinigameStart = function(id) NativeRequests[#NativeRequests + 1] = {"dislocation", id} end
RequestRemoveLimbStatus = function(id, status) NativeRequests[#NativeRequests + 1] = {status, id} end
''')
    radial_lua.execute(native_gui[start:end])
    native_actions = radial_lua.execute(r'''
local function click(state)
    WoundSystemActionButtonPos = { x = nil, y = nil }
    WoundSystemDrawLimbActionPoint("forearm_R", state, { x = 560, y = 460 },
        400, 300, 1, 1.5, 611, 370, true, false, false)
end
click({ shrapnel = 1, dislocated = true })
click({ shrapnel = 0, dislocated = true })
click({ shrapnel = 0, customStatuses = { TOURNIQUET = true } })
click({ shrapnel = 0, customStatuses = { SPLINTED = true } })
click({ shrapnel = 0, bleed = 10, broken = true })
return #NativeRequests == 4
    and NativeRequests[1][1] == "shrapnel" and NativeRequests[1][2] == "forearm_R"
    and NativeRequests[2][1] == "dislocation"
    and NativeRequests[3][1] == "TOURNIQUET"
    and NativeRequests[4][1] == "SPLINTED"
''')
    check('R47 native action point retains shrapnel, dislocation and removal, not medicine buttons', native_actions)

    # Exercise the shipped C:U action renderer with the actual connector
    # installer and queue function: hover descriptions disappear, not actions.
    lua.execute(r'''
WoundSystem = { Client = {} }
QueuedActions = {}
WoundSystemQueueDirectTooltip = function(key, ...)
    QueuedActions[#QueuedActions + 1] = key
    return true
end
WoundSystem.Client.QueueDirectTooltip = WoundSystemQueueDirectTooltip
WoundSystemTooltipText = function(key) return "Remove shrapnel", "Try to remove embedded shrapnel by hand." end
WoundSystemActionButtonPos = { x = nil, y = nil }
WoundSystemLimbUIConfig = { ShrapnelPoint = { TextEnabled = true } }
GUIState = { lastMouseState = false }
Icons = { uiPoint = {} }
render = { SetScissorRect = function() end }
RealFrameTime = function() return 0.1 end
Lerp = function(t, a, b) return a + t * (b - a) end
SetGuiMaterial = function() end
ActionLabels, ActionPanels = 0, 0
draw.SimpleText = function() ActionLabels = ActionLabels + 1 end
surface.DrawTexturedRect = function() ActionPanels = ActionPanels + 1 end
DrawRectInt = function(...) surface.DrawTexturedRect(...) end
ActionRequests = {}
RequestShrapnelMinigameStart = function(id) ActionRequests[#ActionRequests + 1] = "shrapnel" end
RequestDislocationMinigameStart = function(id) ActionRequests[#ActionRequests + 1] = "dislocation" end
RequestRemoveLimbStatus = function(id, status) ActionRequests[#ActionRequests + 1] = status end
WSZC.InstallCUHudDrawWrappers()
''')
    lua.execute(native_gui[start:end])
    action_tooltips = lua.execute(r'''
assert(WSZC.InstallActionPointVisualFilter())
local installed = WoundSystemDrawLimbActionPoint
WSZC.InstallActionPointVisualFilter()
local stableAction = WoundSystemDrawLimbActionPoint == installed
local oldRect, oldText = surface.DrawTexturedRect, draw.SimpleText
local function click(state)
    WoundSystemActionButtonPos = { x = nil, y = nil }
    WoundSystemDrawLimbActionPoint("forearm_R", state, { x = 560, y = 460 },
        400, 300, 1, 1.5, 611, 370, true, false, false)
end
click({ shrapnel = 1 })
click({ dislocated = true })
click({ customStatuses = { TOURNIQUET = true } })
click({ customStatuses = { SPLINTED = true } })
local blocked = #QueuedActions == 0
local usable = #ActionRequests == 4 and ActionRequests[1] == "shrapnel"
    and ActionRequests[2] == "dislocation" and ActionRequests[3] == "TOURNIQUET"
    and ActionRequests[4] == "SPLINTED" and ActionLabels == 0 and ActionPanels == 0
    and surface.DrawTexturedRect == oldRect and draw.SimpleText == oldText and stableAction
surface.DrawTexturedRect(1, 2, 3, 4)
draw.SimpleText("unrelated")
local outside = ActionLabels == 1 and ActionPanels == 1
local kept = WoundSystemQueueDirectTooltip("moodle_pain", "Pain", "Other tooltip", 10) == true
    and #QueuedActions == 1 and QueuedActions[1] == "moodle_pain"
    and WoundSystem.Client.QueueDirectTooltip("action_SHRAPNEL", "Title", "Description", 35) == false
-- Reinstallation must also cover a C:U reload without stacking wrappers.
local old = WoundSystemQueueDirectTooltip
WSZC.InstallCUHudDrawWrappers()
local stable = WoundSystemQueueDirectTooltip == old
WoundSystemQueueDirectTooltip = function(key) QueuedActions[#QueuedActions + 1] = key; return true end
WoundSystem.Client.QueueDirectTooltip = WoundSystemQueueDirectTooltip
WSZC.InstallCUHudDrawWrappers()
local reload = WoundSystemQueueDirectTooltip("action_SHRAPNEL", "Title", "Description", 35) == false
    and WoundSystem.Client.QueueDirectTooltip == WoundSystemQueueDirectTooltip
    and WoundSystemQueueDirectTooltip("other", "Other", "", 10) == true
-- A late native reload and an error must not leak the temporary draw hooks.
WoundSystemDrawLimbActionPoint = function() error("simulated action draw failure") end
WSZC.InstallActionPointVisualFilter()
local ok = pcall(WoundSystemDrawLimbActionPoint)
local errorRestored = not ok and surface.DrawTexturedRect == oldRect and draw.SimpleText == oldText
return blocked, usable and outside and errorRestored, kept and stable and reload
''')
    check('R48 action hover descriptions are suppressed for all four native actions', action_tooltips[0])
    check('R49 action banner is hidden while clicks work; other drawing and errors are unaffected', action_tooltips[1])
    check('R50 unrelated tooltips survive; late load and reload keep filtering', action_tooltips[2])

    # Use C:U's actual status registry, colour and scratch-list code; the
    # WoundView closure follows the original ordering (fracture before status).
    statuses_s = src('woundsystem_zcity_compat/lua/wszc_vendor/cu/woundsystem/shared/sh_limb_statuses.lua')
    lua.execute(r'''
WoundSystem = {}
string.Trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
''')
    lua.execute(statuses_s)
    bandage_status_start = shared_s.index('WSZC.FRACTURE_BANDAGED_STATUS_ID =')
    bandage_status_end = shared_s.index('-- Short-lived context flag:', bandage_status_start)
    lua.execute(shared_s[bandage_status_start:bandage_status_end])
    lua.execute(r'''
WSZC.InstallFractureBandagedStatus()
WoundSystem.Statuses.Register("SPLINTED", { icon = "casunknown-images/icons/splinticon.png", type = "bool", order = 35 })
WoundSystem.Statuses.Register("OTHER", { icon = "casunknown-images/icons/shrapnel.png", type = "bool", order = 40 })
''')
    color_start = native_gui.index('local function GetStatusIconColor(')
    color_end = native_gui.index('\nfunction WoundSystem.Client.GetBloodBagFillColor', color_start)
    add_start = native_gui.index('local function AddHudIcon(')
    add_end = native_gui.index('\nlocal function BleedPhaseColor', add_start)
    lua.execute(r'''
local Icons = {
    fracture = Material("wszc/unitmenu/status/fracture.png"),
    dislocate = Material("wszc/unitmenu/status/dislocation.png"),
}
''' + native_gui[color_start:color_end] + native_gui[add_start:add_end] + r'''
local function NativeWoundView()
    local state = FractureTestState
    local iconItems = {}
    if state.broken then
        AddHudIcon(iconItems, Icons.fracture, Color(255, 0, 0, 210))
    end
    if state.dislocated then
        AddHudIcon(iconItems, Icons.dislocate, Color(255, 0, 0, 210))
    end
    for _, status in ipairs(WoundSystem.Statuses.GetActive(state)) do
        -- Exact native GetStatusIconMaterial behavior: empty icons are skipped.
        local mat = status.data.icon ~= "" and Material(status.data.icon) or nil
        if mat then AddHudIcon(iconItems, mat, GetStatusIconColor(status.data, 210, status.value)) end
    end
    FractureTestItems = iconItems
end
hook.Add("HUDPaint", "WoundDollAndPanel", NativeWoundView)
FractureTestRender = NativeWoundView
WSZC.InstallCUHudFilter()
function DrawFractureTest(state)
    FractureTestState = state
    WoundSystemClientState = { PlayerLimbs = { forearm_R = state } }
    hook._t.HUDPaint.WoundDollAndPanel()
end
''')
    fracture_icons = lua.execute(r'''
local status = WoundSystem.Statuses.Stored.WSZC_FRACTURE_BANDAGED
local hidden = status.icon == ""
status.icon = "wszc/unitmenu/status/fracture_bandaged.png"
WSZC.InstallFractureBandagedStatus()
hidden = hidden and status.icon == ""

FractureTestState = { broken = true, customStatuses = {} }
DrawFractureTest(FractureTestState)
local untreated = #FractureTestItems == 1
    and FractureTestItems[1].mat:GetName() == "wszc/unitmenu/status/fracture.png"
    and FractureTestItems[1].color.r == 255
FractureTestState.customStatuses.WSZC_FRACTURE_BANDAGED = true
FractureTestState.customStatuses.OTHER = true
FractureTestState.dislocated = true
DrawFractureTest(FractureTestState)
local treated = #FractureTestItems == 2
    and FractureTestItems[1].mat:GetName() == "wszc/unitmenu/status/dislocation.png"
    and FractureTestItems[2].mat:GetName() == "casunknown-images/icons/shrapnel.png"
    and FractureTestState.broken and FractureTestState.customStatuses.WSZC_FRACTURE_BANDAGED
-- The ordinary removable SPLINTED status is not a bandage treatment and must
-- never replace the fracture, even though it uses the same material.
FractureTestState = { broken = true, customStatuses = { SPLINTED = true } }
DrawFractureTest(FractureTestState)
local splintNotBandage = #FractureTestItems == 2
    and FractureTestItems[1].mat:GetName() == "wszc/unitmenu/status/fracture.png"
    and FractureTestItems[2].mat:GetName() == "casunknown-images/icons/splinticon.png"
    and FractureTestItems[2].color.r == 255
-- A new fracture after the server clears the treatment marker is red again.
FractureTestState = { broken = true, customStatuses = {} }
DrawFractureTest(FractureTestState)
local rebreak = #FractureTestItems == 1
    and FractureTestItems[1].mat:GetName() == "wszc/unitmenu/status/fracture.png"
FractureTestState.broken = false
FractureTestState.customStatuses.WSZC_FRACTURE_BANDAGED = true -- stale net packet
DrawFractureTest(FractureTestState)
local healed = #FractureTestItems == 0
    and FractureTestState.customStatuses.WSZC_FRACTURE_BANDAGED == true
-- Even if the native HUD errors, the live medical state must be restored.
local original = { broken = true, customStatuses = { WSZC_FRACTURE_BANDAGED = true } }
WoundSystemClientState = { PlayerLimbs = { forearm_R = original } }
hook.Add("HUDPaint", "WoundDollAndPanel", function() error("native HUD test") end)
WSZC.InstallCUHudFilter()
local ok = pcall(hook._t.HUDPaint.WoundDollAndPanel)
local restored = not ok and original.broken == true and original.customStatuses.WSZC_FRACTURE_BANDAGED == true
return hidden and untreated, treated, splintNotBandage and rebreak and healed and restored
''')
    check('R51 untreated fracture stays red; internal bandage marker has no icon after reload', fracture_icons[0])
    check('R52 bandaged fracture shows neither icon and retains other injury icons', fracture_icons[1])
    check('R53 splints, healed states, rebreak and HUD errors preserve medical state', fracture_icons[2])

    independent_hud = lua.execute(r'''
-- Another C:U build may inline icon rendering or disable debug upvalue access.
-- Suppression must still work without AddHudIcon / GetStatusIconColor wrappers.
local priorDebug = debug
debug = nil
local state = { broken = true, customStatuses = { WSZC_FRACTURE_BANDAGED = true } }
local other = { broken = true, customStatuses = {} }
WoundSystemClientState = { PlayerLimbs = { forearm_R = state, crus_L = other } }
local red, black, otherRed = false, false, false
hook.Add("HUDPaint", "WoundDollAndPanel", function()
    red = state.broken
    black = state.customStatuses.WSZC_FRACTURE_BANDAGED == true
    otherRed = other.broken
end)
local installed = WSZC.InstallCUHudFilter()
hook._t.HUDPaint.WoundDollAndPanel()
local treated = installed and not red and black and otherRed and state.broken == true
    and other.broken == true and state.customStatuses.WSZC_FRACTURE_BANDAGED == true
state.broken = false
hook._t.HUDPaint.WoundDollAndPanel()
local healed = not red and not black and otherRed and state.broken == false
    and other.broken == true and state.customStatuses.WSZC_FRACTURE_BANDAGED == true
debug = priorDebug
return treated and healed
''')
    check('R54 red icon hidden after bandaging even when native renderer is inlined and debug is unavailable', independent_hud)

    client_visual_reset = lua.execute(r'''
local removed = 0
local function model() return { Remove = function() removed = removed + 1 end } end
local ent = { bandaged_limbs = { hand = true }, tourniquets = { 1 },
    wounds = { 1 }, arterialwounds = { 2 }, bandagesModel = model(), tourniquetsM = { model(), model() } }
local other = { bandaged_limbs = { safe = true }, tourniquets = { 1 } }
local objects = { [12] = ent, [13] = other }
Entity = function(index) return objects[index] end
zb = { net = { [12] = { bandaged_limbs = { hand = true }, Tourniquets = { 1 },
                        wounds = { 1 }, arterialwounds = { 2 } },
               [13] = { bandaged_limbs = { safe = true }, Tourniquets = { 1 } } } }
local values, cursor = { 2, 12, 99 }, 0
net.ReadUInt = function(bits) cursor = cursor + 1; return values[cursor] end
resetReceivers.WSZC_ResetMedicalVisuals()
return removed == 3 and ent.bandagesModel == nil and ent.tourniquetsM == nil
    and next(ent.bandaged_limbs) == nil and next(ent.tourniquets) == nil
    and next(zb.net[12].bandaged_limbs) == nil and next(zb.net[12].Tourniquets) == nil
    and next(ent.wounds) == nil and next(ent.arterialwounds) == nil
    and next(zb.net[12].wounds) == nil and next(zb.net[12].arterialwounds) == nil
    and other.bandaged_limbs.safe == true and #other.tourniquets == 1
''')
    check('R57 reset message removes client models and netvar shadows only for addressed entities', client_visual_reset)

    selection_reset = lua.execute(r'''
local limb = { skin = 12, broken = true }
local GUIState = { hudOpen = true, openTime = 1, selectedLimbData = { id = "head", state = limb },
    HoverAnims = { head = 0.5, arm = 0.2 }, LastHoverStates = { head = true, arm = false } }
local function NativeHUD()
    return GUIState.selectedLimbData, GUIState.HoverAnims, GUIState.LastHoverStates
end
hook.Add("HUDPaint", "WoundDollAndPanel", NativeHUD)
WSZC.ClearCULimbsCache()
WSZC.InstallCUHudFilter()
WoundSystemHealthHUDOpen = true
WoundSystemSelectedLimbId = "head"
local first = hook._t.HUDPaint.WoundDollAndPanel()
local fresh = first == nil and WoundSystemSelectedLimbId == nil and GUIState.HoverAnims.head == 0
    and GUIState.LastHoverStates.head == false
GUIState.selectedLimbData = { id = "head", state = limb }
GUIState.HoverAnims.head = 0.5
GUIState.LastHoverStates.head = true
WoundSystemSelectedLimbId = "head"
local stillSelected = hook._t.HUDPaint.WoundDollAndPanel() ~= nil
WoundSystemHealthHUDOpen = false
hook._t.Think.WSZC_ClearClosedWoundViewSelection()
local closed = GUIState.selectedLimbData == nil and WoundSystemSelectedLimbId == nil
    and GUIState.HoverAnims.head == 0 and GUIState.LastHoverStates.head == false
-- If close and reopen happen before Think, the changed native openTime still
-- clears the previous selection before the first native draw.
WoundSystemHealthHUDOpen = true
GUIState.openTime = 2
hook._t.HUDPaint.WoundDollAndPanel()
GUIState.selectedLimbData = { id = "head", state = limb }
WoundSystemSelectedLimbId = "head"
GUIState.openTime = 3
local reopened = hook._t.HUDPaint.WoundDollAndPanel() == nil
    and WoundSystemSelectedLimbId == nil
return fresh and stillSelected and closed, reopened and limb.skin == 12 and limb.broken == true
''')
    check('R55 WoundView selection and hover reset on close, but remain during an open view', selection_reset[0])
    check('R56 fast reopen clears stale selection before native draw without changing damage', selection_reset[1])

for name, ok in results:
    print(('PASS ' if ok else 'FAIL ') + name)
passed = sum(1 for _, ok in results if ok)
print('TEST_OK %d / %d' % (passed, len(results)))
sys.exit(0 if passed == len(results) else 1)
