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

The 15 source layers have 1-2 px gaps between joints, so a per-limb outline
would draw white seams through the body.  A morphological close on the union
produces ONE continuous silhouette and ONE outer contour; each limb sprite
receives only the part of that contour inside its bounding box.

The runtime connector (cl_zcity_woundsystem_compat_layout.lua) swaps C:U's
`Limbs` upvalue materials/geometry in place; no file inside the original ZIP
addons is modified.

Usage:  python3 tools/build_unitmenu_materials.py [path/to/ui.zip]
        (without an argument the archive is read from origin/main via git)
Requires Pillow for the edge/alpha operations.
"""
import io
import os
import struct
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

    # Load all 15 layers first.  The archive leaves 1-2 px gaps between
    # adjacent limbs (neck, waist, elbow, knee, ankle).  Drawing a white ring
    # around EACH layer separately therefore painted bright seams straight
    # through the torso and limbs - the live screenshots showed a doll made of
    # stacked rectangles.  We close those gaps once on the UNION and derive one
    # single outer contour, then cut that contour into the 15 limb boxes.
    layers = {}
    for limb_id, layer in LIMB_LAYERS.items():
        layers[limb_id] = Image.open(
            io.BytesIO(z.read(PREFIX + 'zcity_delta/unitmenu/limbs/' + layer + '.png'))
        ).convert('RGBA')

    canvas = next(iter(layers.values())).size
    union = Image.new('L', canvas, 0)
    for src in layers.values():
        union = ImageChops.lighter(union, src.getchannel('A'))
    # Morphological closing: bridge the seams, then restore the outer boundary.
    body = union.filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.MinFilter(15))
    # The source alpha is anti-aliased: dilating the GREYSCALE mask would leave
    # bright pixels inside semi-transparent edges and paint faint seams again.
    # Binarise first so the contour is strictly OUTSIDE the silhouette.
    mask = body.point(lambda p: 255 if p > 127 else 0)
    outline = ImageChops.subtract(mask.filter(ImageFilter.MaxFilter(7)), mask)

    centers, boxes = {}, []
    for limb_id, src in layers.items():
        a = src.getchannel('A')
        bbox = a.getbbox()
        assert bbox, limb_id
        x0, y0, x1, y1 = bbox
        pad = 5
        box = (max(0, x0 - pad), max(0, y0 - pad),
               min(src.width, x1 + pad), min(src.height, y1 + pad))
        crop = src.crop(box)

        # Fill: the closed union clipped to this limb's box, so neighbouring
        # sprites overlap by a pixel or two and never show the world through
        # a transparent seam.
        crop.putalpha(body.crop(box))
        crop.save(OUT / 'limbs' / (limb_id + '_fill.png'), optimize=True)

        # Edge: ONLY the global outer contour inside this box.  No internal
        # rings, hence no white lines across the chest/arms/legs.
        edge = Image.new('RGBA', crop.size, (255, 255, 255, 0))
        edge.putalpha(outline.crop(box))
        edge.save(OUT / 'limbs' / (limb_id + '_edge.png'), optimize=True)

        centers[limb_id] = ((x0 + x1) / 2, (y0 + y1) / 2, crop.width, crop.height)
        boxes.append(box)

    # Every pixel of the single contour must be reachable by one of the 15
    # sprites C:U draws; otherwise a piece of the outline would be missing.
    coverage = Image.new('L', canvas, 0)
    from PIL import ImageDraw
    draw = ImageDraw.Draw(coverage)
    for box in boxes:
        draw.rectangle(box, fill=255)
    missed = ImageChops.multiply(outline, ImageChops.invert(coverage))
    assert missed.getbbox() is None, 'outer outline not covered by limb boxes'
    assert outline.getbbox() is not None, 'empty outline'

    for name in STATUS:
        src = Image.open(io.BytesIO(z.read(PREFIX + 'zcity_delta/unitmenu/status/' + name + '.png')))
        src = src.convert('RGBA')
        # C:U scales HUD icons by 1.5 * dollScale; 64 px becomes ~144 px.
        # 32 px keeps them the same visual weight as the native icons.
        src.resize((32, 32), Image.Resampling.NEAREST).save(
            OUT / 'status' / (name + '.png'), optimize=True)

    # Geometry is consumed by the Lua installer as a generated Lua table so the
    # bounding boxes and the shipped PNGs can never drift apart.
    lines = ['-- Generated by tools/build_unitmenu_materials.py. Do not edit by hand.',
             'WSZC_UNITMENU_LIMB_GEOMETRY = {']
    for limb_id in LIMB_LAYERS:
        cx, cy, w, h = centers[limb_id]
        lines.append('    %s = { cx = %.1f, cy = %.1f, w = %d, h = %d },' %
                     (limb_id, cx, cy, w, h))
    lines += ['}', '']
    (ROOT / 'woundsystem_zcity_compat' / 'lua' / 'autorun' / 'client' /
     'wszc_unitmenu_geometry.lua').write_text('\n'.join(lines), encoding='utf-8')
    print('generated', len(LIMB_LAYERS) * 2, 'limb materials,', len(STATUS),
          'status icons + geometry table')
    for limb_id in ('head', 'thorax', 'hand_R', 'foot_L'):
        print('  ', limb_id, centers[limb_id])


if __name__ == '__main__':
    main()
