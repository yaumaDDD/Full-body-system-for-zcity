#!/usr/bin/env python3
"""Generate the WoundView doll / status materials from the repository UI archive.

Source:  origin/main:для переделывания интерфейса.zip
         (addon "human_hands_for_z_city_casualties_medical_system_heavy_wip")

The archive contains 15 already-positioned 1500x1500 RGBA limb layers.  Their
baked positions produce a wide "coat" with stubby legs, so instead of trusting
them we resample each layer's alpha into an explicit HUMAN-PROPORTION blueprint
(taken from the reference silhouette the owner supplied).  C:U's WoundView draws
one small sprite per limb (middle + outline) at its own ox/oy, so every layer is
emitted as:

    woundsystem_zcity_compat/materials/wszc/unitmenu/limbs/<id>_fill.png
    woundsystem_zcity_compat/materials/wszc/unitmenu/limbs/<id>_edge.png
    woundsystem_zcity_compat/materials/wszc/unitmenu/status/<name>.png
    woundsystem_zcity_compat/lua/autorun/client/wszc_unitmenu_geometry.lua

Visual contract (owner's latest live correction):

  * the doll keeps its EXISTING dark slate colour - DOLL_RGB never changes;
  * each limb again has its ORIGINAL white outline.  A thin white ring around
    the eroded fill is exactly the shape C:U tints with `finalOutline`
    (white -> black on hover), so the native hover reaction is preserved;
  * thin erosion gaps keep neighbouring limbs separated, so the white rings
    read as joint outlines instead of one thick blob;
  * the 15 limb ids, hover hitboxes and action-point labels never change.

`cl_zcity_woundsystem_compat_layout.lua` forces a white draw colour for the
`*_fill.png` sprites ONLY (C:U otherwise multiplies them by a black
`finalMiddle`); `*_edge.png` is deliberately NOT overridden so C:U keeps
control of the outline colour and its hover animation.

Usage: python3 tools/build_unitmenu_materials.py [path/to/ui.zip]
Requires Pillow.
"""
import io
import os
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'woundsystem_zcity_compat' / 'materials' / 'wszc' / 'unitmenu'
GEOMETRY_LUA = (ROOT / 'woundsystem_zcity_compat' / 'lua' / 'autorun' /
                'client' / 'wszc_unitmenu_geometry.lua')
ARCHIVE_REL = 'для переделывания интерфейса.zip'
PREFIX = 'human_hands_for_z_city_casualties_medical_system_heavy_wip/materials/'

# C:U limb id -> source layer.  *_R is drawn on the LEFT of the screen, so it
# maps to the archive's l_* half; *_L maps to r_*.
LIMB_LAYERS = {
    'head': 'head',
    'thorax': 'chest',
    'abdomen': 'pelvis',
    'arm_R': 'l_upperarm', 'arm_L': 'r_upperarm',
    'forearm_R': 'l_forearm', 'forearm_L': 'r_forearm',
    'hand_R': 'l_hand', 'hand_L': 'r_hand',
    'thigh_R': 'l_thigh', 'thigh_L': 'r_thigh',
    'crus_R': 'l_calf', 'crus_L': 'r_calf',
    'foot_R': 'l_foot', 'foot_L': 'r_foot',
}
STATUS = ('bleeding', 'dislocation', 'fracture')

DOLL_RGB = (42, 56, 60)      # unchanged dark slate - the owner asked not to recolor
JOINT_ERODE = 7              # 3 px each side -> thin gaps / white joint outlines
OUTLINE_RING = 7             # 3 px white ring, the original C:U outline

# Human-proportioned layout in the canonical 1500x1500 canvas.
# Derived from the reference silhouette (small head, shoulders at arm height,
# narrow torso, legs about as long as head+torso, arms in a T-pose).
#   limb id: (cx, cy, w, h)
HUMAN_LAYOUT = {
    'head':      (750, 190, 120, 178),
    'thorax':    (750, 445, 263, 335),
    'abdomen':   (750, 707, 234, 191),
    'arm_R':     (530, 413, 177, 110),
    'forearm_R': (375, 413, 134, 100),
    'hand_R':    (236, 413, 143, 110),
    'arm_L':     (970, 413, 177, 110),
    'forearm_L': (1125, 413, 134, 100),
    'hand_L':    (1264, 413, 143, 110),
    'thigh_R':   (695, 922, 105, 239),
    'thigh_L':   (805, 922, 105, 239),
    'crus_R':    (695, 1168, 95, 253),
    'crus_L':    (805, 1168, 95, 253),
    'foot_R':    (692, 1347, 105, 105),
    'foot_L':    (808, 1347, 105, 105),
}


def load_archive(arg=None):
    if arg:
        return Path(arg).read_bytes()
    env = dict(os.environ, GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.quotepath',
               GIT_CONFIG_VALUE_0='false')
    return subprocess.check_output(
        ['git', 'show', 'origin/main:' + ARCHIVE_REL], cwd=ROOT, env=env)


def main():
    sys.path.insert(0, '/tmp/pil_pkg')
    from PIL import Image, ImageChops, ImageFilter

    z = zipfile.ZipFile(io.BytesIO(load_archive(sys.argv[1] if len(sys.argv) > 1 else None)))
    (OUT / 'limbs').mkdir(parents=True, exist_ok=True)
    (OUT / 'status').mkdir(parents=True, exist_ok=True)

    for limb_id, layer in LIMB_LAYERS.items():
        cx, cy, w, h = HUMAN_LAYOUT[limb_id]
        src = Image.open(
            io.BytesIO(z.read(PREFIX + 'zcity_delta/unitmenu/limbs/' + layer + '.png'))
        ).convert('RGBA')
        # r_foot.png contains a fully transparent left half (the authored
        # sprite is 216 px wide but only the right 95 px are opaque).  Cropping
        # by the raw alpha bbox would squash the foot into a thin sliver, so
        # threshold first and crop the OPAQUE silhouette only.
        hard = src.getchannel('A').point(lambda p: 255 if p > 96 else 0)
        bbox = hard.getbbox()
        assert bbox, limb_id

        # Resample the archive silhouette into its human-proportioned box.
        # A hard alpha threshold keeps the limbs crisp after LANCZOS scaling.
        alpha = hard.crop(bbox).resize(
            (w, h), Image.Resampling.LANCZOS).point(lambda p: 255 if p > 96 else 0)

        # Eroding each layer separately widens the natural gaps at neck,
        # shoulders, waist, elbows, knees and ankles.  The white ring that
        # fills those gaps is C:U's original outline (and its hover target).
        inner = alpha.filter(ImageFilter.MinFilter(JOINT_ERODE))
        fill = Image.new('RGBA', (w, h), DOLL_RGB + (0,))
        fill.putalpha(inner)
        fill.save(OUT / 'limbs' / (limb_id + '_fill.png'), optimize=True)

        dilated = inner.filter(ImageFilter.MaxFilter(OUTLINE_RING))
        ring = ImageChops.subtract(dilated, inner)
        edge = Image.new('RGBA', (w, h), (255, 255, 255, 0))
        edge.putalpha(ring)
        edge.save(OUT / 'limbs' / (limb_id + '_edge.png'), optimize=True)

    for name in STATUS:
        src = Image.open(io.BytesIO(z.read(PREFIX + 'zcity_delta/unitmenu/status/' + name + '.png')))
        src = src.convert('RGBA')
        src.resize((32, 32), Image.Resampling.NEAREST).save(
            OUT / 'status' / (name + '.png'), optimize=True)

    lines = ['-- Generated by tools/build_unitmenu_materials.py. Do not edit by hand.',
             '-- Human-proportioned layout; cx/cy are in the 1500x1500 source canvas.',
             'WSZC_UNITMENU_LIMB_GEOMETRY = {']
    for limb_id in LIMB_LAYERS:
        cx, cy, w, h = HUMAN_LAYOUT[limb_id]
        lines.append('    %s = { cx = %.1f, cy = %.1f, w = %d, h = %d },' %
                     (limb_id, cx, cy, w, h))
    lines += ['}', '']
    GEOMETRY_LUA.write_text('\n'.join(lines), encoding='utf-8')
    print('generated', len(LIMB_LAYERS) * 2,
          'limb materials (slate fill + original white outline),',
          len(STATUS), 'status icons + human-proportioned geometry table')
    for limb_id in ('head', 'thorax', 'hand_R', 'foot_L'):
        print('  ', limb_id, HUMAN_LAYOUT[limb_id])


if __name__ == '__main__':
    main()
