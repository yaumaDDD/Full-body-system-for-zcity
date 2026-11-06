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
  * both ZIPs, the 649-material mirror and MANIFEST sha256.

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
minigames_s = (CLIENT / 'cl_zcity_woundsystem_compat_minigames.lua').read_text(encoding='utf-8')
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
check('S06 native geometry unchanged; C:U human hand is the default pointer',
      '"zc_woundsystem_compat_fullscreen_native", "0"' in layout_s
      and '"zc_woundsystem_compat_native_minigame_zoom", "1"' in layout_s
      and '"zc_woundsystem_compat_hide_minigame_cursor", "1"' in layout_s
      and '"zc_woundsystem_compat_hide_minigame_hand", "0"' in layout_s
      and '"zc_woundsystem_compat_handanim", "1"' in layout_s)
check('S07 hand pivot + native scale convars exist',
      all(x in layout_s for x in ('hand_pivot_x', 'hand_pivot_y', 'hand_max_screen')))
check('S08 human hand keeps exact native C:U rect and rotation',
      'HandRectForCursor' in layout_s
      and 'return cx, cy, nw, nh' in layout_s
      and 'WSZC.HandRectForCursor(x, y, w, h, rot)' in layout_s
      and 'origRectRotated(nx, ny, nw, nh, rot, ...)' in layout_s
      and 'UnitmenuHandRotatedCenter' not in layout_s)
check('S09 blank cursor is hand-only, active-only, with an arrow fallback',
      'function WSZC.BlankMinigameCursor()' in layout_s
      and 'if not cvHideCursor:GetBool() or not WSZC.ShowMinigameHand() then' in layout_s
      and 'panel.SetCursor, panel, "arrow"' in layout_s
      and 'panel.SetCursor, panel, "blank"' in layout_s
      and 'if active and cvHideCursor:GetBool() and WSZC.ShowMinigameHand() then' in layout_s
      and 'if WSZC.SyncMinigameCursor then WSZC.SyncMinigameCursor() end' in layout_s
      and 'WSZC.RestoreMinigameCursor(true)' in layout_s)
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
      and 'ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(EDGE_WIDTH)))' in generator_s
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
check('S24 white tint is for *_fill.png ONLY (outline hover stays C:U-owned)',
      'zc_woundsystem_compat_unitmenu_tint' in layout_s
      and 'origSetDrawColor(255, 255, 255, a or 255)' in layout_s
      and 'IsDollLimbMaterial' in layout_s
      and 'lower:find("_fill", 1, true)' in layout_s
      and 'DollMiddleKind' not in layout_s)
check('S25 opt-in archive hand can still be pinned to the real cursor',
      'zc_woundsystem_compat_hand_pin_cursor' in layout_s
      and 'PinNativeHandToCursor' in layout_s
      and 'mg.handScreenX, mg.handScreenY = mx, my' in layout_s)
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
# Screenshot_2-10.png native boxes are now the SOURCE of truth: the generator
# inverts C:U's linear placement with the live calibration measured from
# Screenshot_1-10.png and emits POT sprites (C:U sizes limbs by mat:Width(),
# which GMod rounds to a power of two).  A uniform scale of w/h can never work.
check('S33 REFERENCE_BOXES = independent native Screenshot_1 boxes, POT-calibrated',
      "'head':      (682.5, 268.0, 67, 102)" in generator_s
      and "'thorax':    (681.5, 385.5, 125, 129)" in generator_s
      and "'abdomen':   (681.5, 521.5, 128, 138)" in generator_s
      and "'arm_R':     (576.9, 361.0, 83, 57)" in generator_s
      and "'arm_L':     (787.1, 364.0, 85, 58)" in generator_s
      and "'forearm_R': (481.0, 356.0, 111, 38)" in generator_s
      and "'forearm_L': (879.0, 356.0, 94, 36)" in generator_s
      and "'hand_R':    (395.0, 356.0, 54, 43)" in generator_s
      and "'hand_L':    (955.0, 354.0, 54, 43)" in generator_s
      and "'thigh_R':   (652.5, 650.0, 58, 112)" in generator_s
      and "'thigh_L':   (711.5, 650.0, 56, 114)" in generator_s
      and "'crus_R':    (649.5, 761.0, 45, 104)" in generator_s
      and "'crus_L':    (714.5, 761.0, 47, 104)" in generator_s
      and "'foot_R':    (646.0, 843.0, 46, 50)" in generator_s
      and "'foot_L':    (719.0, 843.0, 46, 47)" in generator_s
      and 'Screenshot_1.png' in generator_s
      and 'Screenshot_6-2.png' in generator_s
      and 'Screenshot_8.png' in generator_s
      and 'independently for every limb' in generator_s
      and '44 px arm sprites' in generator_s
      and 'tools/fit_unitmenu_geometry.py' in generator_s
      and 'EDGE_WIDTH = 9' in generator_s
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
      and organism_s.count('BoneAnchor(limbId, "dislocation")') == 2
      and 'limbSet("broken", Fractured(org, limbId, map))' in organism_s
      and 'limbSet("dislocated", out)' in organism_s
      and 'WSZC.BoneAnchor = BoneAnchor' in organism_s)
check('S47 human hand + hidden arrow, action button offset, post-game release',
      '"zc_woundsystem_compat_hide_minigame_cursor", "1"' in layout_s
      and '"zc_woundsystem_compat_hide_minigame_hand", "0"' in layout_s
      and '"zc_woundsystem_compat_handanim", "1"' in layout_s
      and '"zc_woundsystem_compat_hand_pin_cursor", "0"' in layout_s
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
      and '"zc_woundsystem_compat_hand_cursor_scale", "1"' in layout_s
      and '"zc_woundsystem_compat_handanim_scale", "1"' in layout_s
      and (CONN / 'materials/wszc/minigame/hand_idle.png').is_file()
      and (CONN / 'materials/wszc/minigame/hand_click.png').is_file())
check('S48 silhouettes are NOT redrawn; only native limb boxes change',
      'Screenshot_1-11.png' in generator_s
      and 'Screenshot_8.png' in generator_s
      and 'SEAM_LIMBS' not in generator_s
      and 'def CloseMask(mask):' not in generator_s
      and 'def FlattenLimbBand(mask):' not in generator_s
      and 'def SquareToe(mask):' in generator_s
      and "limb_id.startswith('foot_')" in generator_s
      and 'no shape editing' in generator_s
      and "'forearm_R': (481.0, 356.0, 111, 38)" in generator_s
      and "'arm_R':     (576.9, 361.0, 83, 57)" in generator_s)
check('S49 opioid dose reaches the ZCity organism (morphine / fentanyl)',
      'opiateAmount = tonumber(body.opiateAmount) or 0' in organism_s
      and 'add("analgesiaAdd", (after.opiateAmount - before.opiateAmount) * 0.006, 0, 4)' in organism_s
      and 'WSZC.BoneAnchor = BoneAnchor' in organism_s)
fit_s = (ROOT / 'tools' / 'fit_unitmenu_geometry.py').read_text(encoding='utf-8')
check('S50 geometry is measured against the native reference, not eyeballed',
      'max(px[x, y]) < 20' in fit_s
      and 'def iou(' in fit_s
      and 'def optimize(' in fit_s
      and 'def render(' in fit_s
      and 'G.REFERENCE_BOXES' in fit_s
      and 'Screenshot_1.png' in fit_s
      and "ORDER = tuple(k for k in G.LIMB_LAYERS if k != 'head')" in fit_s
      and 'PAIRS =' not in fit_s
      and 'NOT ONE silhouette pixel' in fit_s
      and 'SEEDS = {' in fit_s
      and 'include_head=False' in fit_s
      and 'DOLL_RGB = (0, 0, 0)' in generator_s)
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
    check('S17 white outline restored: 15 opaque white _edge.png',
          edge_boxes == 15 and edge_white > 100 and edges.getbbox() is not None)
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
    check('S18 standard BLACK fill restored (not slate 42,56,60)',
          a > 200 and (r, g, b) == (0, 0, 0))
    # Every outline must be non-empty (b47a0cb's transparent _edge was rejected)
    # and must follow its limb's shape rather than a box: white pixels sit in
    # the interior of the sprite, not on its border.
    check('S37 generator emits standard black + shape-following per-limb contours',
          edge_boxes == 15
          and 'DOLL_RGB = (0, 0, 0)' in generator_s
          and 'EDGE_PAD_MIN = 6' in generator_s
          and 'EDGE_WIDTH = 9' in generator_s
          and 'ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(EDGE_WIDTH)))' in generator_s
          and 'outer_band' not in generator_s
          and 'seam_lines' not in generator_s
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
    # Human proportions in the generated Lua geometry.
    g = {k: tuple(float(v) for v in vals) for k, vals in geom.items()}
    head_top = g['head'][1] - g['head'][3] / 2
    torso_bottom = g['abdomen'][1] + g['abdomen'][3] / 2
    leg_top = g['thigh_R'][1] - g['thigh_R'][3] / 2
    leg_bottom = g['foot_R'][1] + g['foot_R'][3] / 2
    torso_h, leg_h = torso_bottom - head_top, leg_bottom - leg_top
    # Screenshot_2-10.png is the native C:U UNIT-HEALTH V2.04 doll the owner
    # asked to reproduce: its torso (218..592) and legs (592..865) give a
    # leg/torso ratio of ~0.73, not the ~0.95 of the rejected Screenshot_4-5
    # iteration.  Keep the shape/width/symmetry relations, but measure the
    # ratio against the NEW reference seams.
    check('S20 limb sizes follow Screenshot_1 native proportions',
          leg_h >= 0.70 * torso_h
          and leg_h <= 0.80 * torso_h
          and g['thorax'][2] > g['head'][2]
          and g['thigh_R'][2] < g['thorax'][2]
          and g['abdomen'][3] >= g['thorax'][3]
          and g['forearm_R'][2] > g['arm_R'][2]
          and g['hand_R'][2] < g['forearm_R'][2]
          and g['foot_R'][2] <= g['crus_R'][2]
          and abs(g['arm_R'][0] + g['arm_L'][0] - 1497.5) < 0.2
          and abs(g['thigh_R'][0] + g['thigh_L'][0] - 1497.6) < 0.2
          and abs(g['foot_R'][1] - g['foot_L'][1]) < 1
          # C:U reads mat:Width()/Height(); GMod rounds PNG textures to a
          # power of two, so EVERY emitted sprite must already be POT-sized.
          and all(int(v[2]) > 0 and int(v[2]) & (int(v[2]) - 1) == 0
                  and int(v[3]) > 0 and int(v[3]) & (int(v[3]) - 1) == 0
                  for v in g.values()))
    hover = {m[0]: (m[1], m[2]) for m in re.findall(
        r'(\w+)\s*=\s*\{[^\n]*?hoverW\s*=\s*(\d+),\s*hoverH\s*=\s*(\d+)',
        geom_text)}
    check('S44 hover boxes are the visible silhouettes, not the padded POT sprites',
          len(hover) == 15
          and all(int(hover[k][0]) <= int(g[k][2]) and int(hover[k][1]) <= int(g[k][3])
                  for k in hover))
    hand_frames = [Image.open(CONN / 'materials/wszc/minigame' / name).convert('RGBA')
                   for name in ('hand_idle.png', 'hand_click.png')]
    grip_pixels = [im.getpixel((round(0.4 * (im.width - 1)),
                                round(0.1 * (im.height - 1)))) for im in hand_frames]
    check('S52 human hand sprites use the native canvas and grip is on skin',
          all(im.size == (512, 1260) for im in hand_frames)
          and all(px[3] > 200 and px[0] > px[1] > px[2] for px in grip_pixels))
    mats = [p for p in (CONN / 'materials').rglob('*') if p.is_file()]
    check('S21 connector ships 649 UI materials', len(mats) == 649)
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
    assert len(conn_files) == len(compat) == 664
    assert all(compat['woundsystem_zcity_compat/' + r] == d for r, d in conn_files.items())
    mirror = {n[len('garrysmod/addons/casualties_unknown_health_system_beta/materials/'):]: d
              for n, d in full.items()
              if n.startswith('garrysmod/addons/casualties_unknown_health_system_beta/materials/')}
    assert len(mirror) == 649
    assert all(mirror[r[len('materials/'):]] == d for r, d in conn_files.items() if r.startswith('materials/'))
    assert json.loads(compat['woundsystem_zcity_compat/addon.json'])
    bridge = [n for n in full if n.endswith('woundbridge/sv_woundbridge.lua')]
    assert len(bridge) == 1 and b'Not completed - nothing was applied' not in full[bridge[0]]
    manifest = full['MANIFEST.txt'].decode('utf-8')
    shas = re.findall(r'woundsystem_zcity_compat/lua/[^\s]+\.lua\s+([0-9a-f]{64})', manifest)
    assert len(shas) == 11
    assert all(hashlib.sha256(d).hexdigest() in shas for r, d in conn_files.items() if r.endswith('.lua'))
    shipped_layout = full['garrysmod/addons/woundsystem_zcity_compat/lua/autorun/client/cl_zcity_woundsystem_compat_layout.lua'].decode('utf-8')
    assert 'HandRectForCursor' in shipped_layout
    assert 'WSZC.InstallMinigameTextFilter()' in shipped_layout
    assert 'WSZC.IsMinigameWoundLayer' in shipped_layout
    assert 'WSZC.IsMinigameGameplaySprite' in shipped_layout
    assert 'origBoardRect' not in shipped_layout
    assert 'function WSZC.WoundViewEmptyClick' in shipped_layout
    assert 'INSTALL_RU.md' not in full and 'zc_woundsystem_compat_fullscreen_native' in full['ZCity_binds.md'].decode('utf-8')
    assert len(full) == 2769
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
net = { Receive = function() end, Start = function() end, SendToServer = function() end }
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

    rt('R06 native games keep C:U\'s own 760 px board at zoom 1 by default', '''
(function()
    convars["zc_woundsystem_compat_fullscreen_native"]._v = "0"
    WoundSystemDislocationMinigame = { active = true }
    local x, y, w, h, r = WoundSystem.MinigameClip.GetRect()
    local s = WoundSystem.MinigameClip.Scale()
    WoundSystemDislocationMinigame = { active = false }
    convars["zc_woundsystem_compat_fullscreen_native"]._v = "0"
    return w == 760 and h == 760 and r == 18 and math.abs(s - (1000 / 1080)) < 0.0001
end)()
''')

    rt('R07 pinned hand uses the exact native C:U rect at the cursor', '''
(function()
    EnableDrawnHandMode()
    WoundSystemShrapnelMinigame = { active = true }
    surfaceCalls = {}
    surface.SetMaterial(Material("casunknown-images/shrapnelminigame/handGraspIdle1.png"))
    surface.DrawTexturedRectRotated(500, 400, 512, 1260, 290)
    WoundSystemShrapnelMinigame = { active = false }
    local c = surfaceCalls[#surfaceCalls]
    if not c or c.kind ~= "rot" then return false end
    return c.x == 500 and c.y == 400 and c.w == 512 and c.h == 1260 and c.rot == 290
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

    rt('R09 native hand size has no hidden shrink or screen cap', '''
(function()
    EnableDrawnHandMode()
    local x, y, w, h = WSZC.HandRectForCursor(500, 400, 5000, 12000)
    return w == 5000 and h == 12000
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

    rt('R12 hide_minigame_hand 1 is a safe standard-arrow fallback', '''
(function()
    convars["zc_woundsystem_compat_hide_minigame_cursor"]._v = "1"
    convars["zc_woundsystem_compat_hide_minigame_hand"]._v = "1"
    cursorValue = "blank"
    WoundSystemShrapnelMinigame = { active = true }
    WSZC.SyncMinigameCursor()
    local fallback = cursorValue == "arrow"
        and WSZC.BlankMinigameCursor() == false and cursorValue == "arrow"
    WoundSystemShrapnelMinigame = { active = false }
    convars["zc_woundsystem_compat_hide_minigame_hand"]._v = "0"
    return fallback
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

    rt('R15 unitmenu defaults and WSZC hand geometry are exact C:U', '''
(function()
    local w, h, px, py = WSZC.UnitmenuHandGeometry(512, 1260, 2)
    return convars["zc_woundsystem_compat_unitmenu_scale"]._v == "0.25"
       and convars["zc_woundsystem_compat_hand_pivot_x"]._v == "0.4"
       and convars["zc_woundsystem_compat_hand_pivot_y"]._v == "0.1"
       and convars["zc_woundsystem_compat_hand_cursor_scale"]._v == "1"
       and convars["zc_woundsystem_compat_handanim_scale"]._v == "1"
       and w == 1024 and h == 2520 and px == 0.4 and py == 0.1
       and convars["zc_woundsystem_compat_unitmenu_doll"]._v == "1"
       and convars["zc_woundsystem_compat_hide_minigame_text"]._v == "1"
end)()
''')

    rt('R16 geometry table has 15 human-proportioned limbs', '''
(function()
    local n = 0
    for _ in pairs(WSZC_UNITMENU_LIMB_GEOMETRY) do n = n + 1 end
    local g = WSZC_UNITMENU_LIMB_GEOMETRY
    return n == 15 and g.head.cy < g.thorax.cy and g.thorax.cy < g.thigh_R.cy
       and g.thigh_R.cy < g.crus_R.cy and g.crus_R.cy < g.foot_R.cy
       and g.thorax.w > g.head.w and g.thigh_R.w < g.thorax.w
       and math.abs(g.arm_R.cx + g.arm_L.cx - 1497.5) < 0.11
       and g.hand_R.cx == 58.1 and g.hand_L.cx == 1405.8
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

    rt('R18 *_fill tinted white; *_edge keeps C:U hover colour; icons untouched', '''
(function()
    WSZC.InstallMaterialTracker()
    surfaceCalls = {}
    surface.SetMaterial(Material("wszc/unitmenu/limbs/head_fill.png"))
    surface.SetDrawColor(0, 0, 0, 255)
    surface.SetMaterial(Material("wszc/unitmenu/limbs/head_edge.png"))
    surface.SetDrawColor(60, 70, 80, 255)
    surface.SetMaterial(Material("casunknown-images/icons/fracturedbone.png"))
    surface.SetDrawColor(12, 34, 56, 255)
    local cols = {}
    for _, c in ipairs(surfaceCalls) do
        if c.kind == "color" then cols[#cols + 1] = c end
    end
    return #cols == 3
       and cols[1].r == 255 and cols[1].g == 255 and cols[1].b == 255
       and cols[2].r == 60 and cols[2].g == 70 and cols[2].b == 80
       and cols[3].r == 12 and cols[3].g == 34 and cols[3].b == 56
end)()
''')

    rt('R19 hand pinned to the REAL cursor, C:U state kept in sync', '''
(function()
    EnableDrawnHandMode()
    mouseX, mouseY = 700, 300
    WoundSystemShrapnelMinigame = { active = true, handScreenX = 100, handScreenY = 100 }
    surfaceCalls = {}
    surface.SetMaterial(Material("casunknown-images/shrapnelminigame/handGraspIdle1.png"))
    surface.DrawTexturedRectRotated(200, 150, 512, 1260, 0)
    local c = surfaceCalls[#surfaceCalls]
    local state = WoundSystemShrapnelMinigame
    WoundSystemShrapnelMinigame = { active = false }
    mouseX, mouseY = 500, 400
    return c.kind == "rot" and c.x == 700 and c.y == 300
       and c.w == 512 and c.h == 1260
       and state.handScreenX == 700 and state.handScreenY == 300
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
    return x == 200 and y == 150 and w == 512 and h == 1260
end)()
''')

    rt('R21 defaults: C:U human hand, black doll, empty-click close', '''
(function()
    EnableDrawnHandMode()
    convars["zc_woundsystem_compat_hand_pin_cursor"]._v = "0"
    return convars["zc_woundsystem_compat_handanim"]._v == "1"
       and convars["zc_woundsystem_compat_hide_minigame_hand"]._v == "0"
       and convars["zc_woundsystem_compat_hand_pin_cursor"]._v == "0"
       and convars["zc_woundsystem_compat_hide_woundview_backdrop"]._v == "1"
       and convars["zc_woundsystem_compat_unitmenu_tint"]._v == "1"
       and convars["zc_woundsystem_compat_hide_minigame_cursor"]._v == "1"
       and convars["zc_woundsystem_compat_hide_minigame_text"]._v == "1"
       and convars["zc_woundsystem_compat_fullscreen_native"]._v == "0"
       and convars["zc_woundsystem_compat_native_minigame_zoom"]._v == "1"
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

    rt('R28 ApplyDoll writes native geometry, 0.25 scale and visible hitboxes', '''
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
    local head
    for _, l in ipairs(limbs) do if l.id == "head" then head = l end end
    local gh = WSZC_UNITMENU_LIMB_GEOMETRY.head
    return #limbs == 15 and head ~= nil
       and head.matM == mats.head.fill and head.matO == mats.head.edge
       and math.abs(head.ox - (gh.cx - 750) * k) < 0.001
       and math.abs(head.oy - (gh.cy - 750) * k) < 0.001
       and head.size == 0.25 and head.sourceW == gh.hoverW and head.sourceH == gh.hoverH
       and head.texturePadding == 0 and head.flip == false
       and head._WSZCUnitmenuOriginal.matM ~= nil
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
    convars["zc_woundsystem_compat_hand_mode_revision"]._v = "2"
    local migrated = WSZC.MigrateHumanHandDefaults() == true
        and convars["zc_woundsystem_compat_handanim"]._v == "1"
        and convars["zc_woundsystem_compat_hand_cursor_scale"]._v == "1"
        and convars["zc_woundsystem_compat_handanim_scale"]._v == "1"
        and convars["zc_woundsystem_compat_hide_minigame_hand"]._v == "0"
        and convars["zc_woundsystem_compat_hide_minigame_cursor"]._v == "1"
        and convars["zc_woundsystem_compat_hand_pivot_x"]._v == "0.4"
        and convars["zc_woundsystem_compat_hand_pivot_y"]._v == "0.1"
        and convars["zc_woundsystem_compat_hand_mode_revision"]._v == "3"
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

for name, ok in results:
    print(('PASS ' if ok else 'FAIL ') + name)
passed = sum(1 for _, ok in results if ok)
print('TEST_OK %d / %d' % (passed, len(results)))
sys.exit(0 if passed == len(results) else 1)
