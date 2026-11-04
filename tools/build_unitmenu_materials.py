#!/usr/bin/env python3
"""Generate the WoundView doll / status materials from the repository UI archive.

Source:  origin/main:для переделывания интерфейса.zip
         (addon "human_hands_for_z_city_casualties_medical_system_heavy_wip")

The archive contains 15 already-positioned 1500x1500 RGBA limb layers.  C:U's
WoundView draws one small sprite per limb (middle + outline) at its own ox/oy,
so we crop every layer to its alpha bounding box and emit:

    woundsystem_zcity_compat/materials/wszc/unitmenu/limbs/<id>_fill.png
    woundsystem_zcity_compat/materials/wszc/unitmenu/limbs/<id>_edge.png
    woundsystem_zcity_compat/materials/wszc/unitmenu/status/<name>.png

Target look (live screenshot #2): ONE dark slate silhouette with thin
background-coloured lines at the joints and NO white outline.  The source
layers are solid black with 1-2 px gaps between them; a white ring around each
layer (previous build) turned those gaps into bright seams and made the doll
look like stacked rectangles.  Now:

  * each `_fill.png` is a dark slate silhouette, eroded by 3 px so the gaps
    between neighbouring sprites stay visible as thin light joint lines;
  * each `_edge.png` is fully transparent - C:U tints `matO` white, and that
    white outline was the other visual bug;
  * `cl_zcity_woundsystem_compat_layout.lua` forces a white draw colour for
    limb materials, because C:U otherwise multiplies them by a black
    `finalMiddle` colour and the slate PNG would render pure black.

Geometry, the 15 limb ids, hover hitboxes and the action-point labels never
change.  Usage: python3 tools/build_unitmenu_materials.py [path/to/ui.zip]
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

DOLL_RGB = (42, 56, 60)      # dark slate, matches the reference screenshot
JOINT_ERODE = 7              # 3 px each side -> ~6 px gap at 1500 px source


def load_archive(arg=None):
    if arg:
        return Path(arg).read_bytes()
    env = dict(os.environ, GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.quotepath',
               GIT_CONFIG_VALUE_0='false')
    return subprocess.check_output(
        ['git', 'show', 'origin/main:' + ARCHIVE_REL], cwd=ROOT, env=env)


def main():
    sys.path.insert(0, '/tmp/pil_pkg')
    from PIL import Image, ImageFilter

    z = zipfile.ZipFile(io.BytesIO(load_archive(sys.argv[1] if len(sys.argv) > 1 else None)))
    (OUT / 'limbs').mkdir(parents=True, exist_ok=True)
    (OUT / 'status').mkdir(parents=True, exist_ok=True)

    centers = {}
    for limb_id, layer in LIMB_LAYERS.items():
        src = Image.open(
            io.BytesIO(z.read(PREFIX + 'zcity_delta/unitmenu/limbs/' + layer + '.png'))
        ).convert('RGBA')
        a = src.getchannel('A')
        bbox = a.getbbox()
        assert bbox, limb_id
        x0, y0, x1, y1 = bbox
        pad = 5
        box = (max(0, x0 - pad), max(0, y0 - pad),
               min(src.width, x1 + pad), min(src.height, y1 + pad))

        # Eroding each layer separately widens the natural gaps at neck,
        # shoulders, waist, elbows, knees and ankles.  Those gaps show the
        # world/background through the doll: the thin joint lines of the
        # reference UI.  No white contour is generated at all.
        inner = a.filter(ImageFilter.MinFilter(JOINT_ERODE)).crop(box)
        fill = Image.new('RGBA', (box[2] - box[0], box[3] - box[1]), DOLL_RGB + (0,))
        fill.putalpha(inner)
        fill.save(OUT / 'limbs' / (limb_id + '_fill.png'), optimize=True)

        # C:U draws matO with a white tint.  A transparent sprite removes the
        # outline completely without touching C:U's Lua files.
        edge = Image.new('RGBA', fill.size, (0, 0, 0, 0))
        edge.save(OUT / 'limbs' / (limb_id + '_edge.png'), optimize=True)

        centers[limb_id] = ((x0 + x1) / 2, (y0 + y1) / 2,
                            box[2] - box[0], box[3] - box[1])

    for name in STATUS:
        src = Image.open(io.BytesIO(z.read(PREFIX + 'zcity_delta/unitmenu/status/' + name + '.png')))
        src = src.convert('RGBA')
        # C:U scales HUD icons by 1.5 * dollScale; 32 px keeps them readable.
        src.resize((32, 32), Image.Resampling.NEAREST).save(
            OUT / 'status' / (name + '.png'), optimize=True)

    lines = ['-- Generated by tools/build_unitmenu_materials.py. Do not edit by hand.',
             'WSZC_UNITMENU_LIMB_GEOMETRY = {']
    for limb_id in LIMB_LAYERS:
        cx, cy, w, h = centers[limb_id]
        lines.append('    %s = { cx = %.1f, cy = %.1f, w = %d, h = %d },' %
                     (limb_id, cx, cy, w, h))
    lines += ['}', '']
    (ROOT / 'woundsystem_zcity_compat' / 'lua' / 'autorun' / 'client' /
     'wszc_unitmenu_geometry.lua').write_text('\n'.join(lines), encoding='utf-8')
    print('generated', len(LIMB_LAYERS) * 2, 'limb materials (slate fill, transparent outline),',
          len(STATUS), 'status icons + geometry table')
    for limb_id in ('head', 'thorax', 'hand_R', 'foot_L'):
        print('  ', limb_id, centers[limb_id])


if __name__ == '__main__':
    main()
