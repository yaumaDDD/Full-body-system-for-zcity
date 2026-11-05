#!/usr/bin/env python3
"""Generate the WoundView doll / status materials from the repository UI archive.

Source:  origin/main:для переделывания интерфейса.zip
         (addon "human_hands_for_z_city_casualties_medical_system_heavy_wip")

The archive contains 15 already-positioned 1500x1500 RGBA limb layers.  Their
baked positions produce a wide "coat" with stubby legs, so we resample each
layer's alpha into an explicit HUMAN-PROPORTION blueprint (the reference
silhouette the owner supplied).  C:U's WoundView draws one small sprite per
limb (middle + outline) at its own ox/oy, so every layer is emitted as:

    woundsystem_zcity_compat/materials/wszc/unitmenu/limbs/<id>_fill.png
    woundsystem_zcity_compat/materials/wszc/unitmenu/limbs/<id>_edge.png
    woundsystem_zcity_compat/materials/wszc/unitmenu/status/<name>.png
    woundsystem_zcity_compat/lua/autorun/client/wszc_unitmenu_geometry.lua

Visual contract (owner's live correction after 6e2196f, confirmed by choice):

  * the doll keeps the HUMAN-PROPORTION blueprint (small head, narrow torso,
    T-pose, long legs, whole feet) - the anatomy is NOT reverted to C:U;
  * colour is the STANDARD black: DOLL_RGB = (0, 0, 0), exactly the RGB of
    the archive's own limb layers.  The slate (42, 56, 60) was rejected live;
  * the outline is a THIN line that follows the SHAPE OF EACH LIMB, like
    C:U's own `casunknown-images/outlines/<part>outline.png` sprites.  It is
    derived from each limb's alpha contour, never from the rectangular sprite
    bounds, and a 4 px inset keeps it off all four sprite edges - so no white
    box/frame can appear ("constructor" / Lego robot);
  * the outline sprite is non-empty, so C:U's `finalOutline` + `HoverAnims`
    keep darkening it on hover (reaction preserved);
  * no single union outer band and no explicit rectangular seam lines: those
    were the previous build's rejected look.

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

CANVAS = 1500

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

DOLL_RGB = (0, 0, 0)         # standard black, exactly the archive layers' RGB
ALPHA_THRESHOLD = 96          # r_foot.png has a transparent left half
JOINT_ERODE = 5               # 2 px inset for the fill, leaving a hairline seam
EDGE_PAD = 6                  # inset the shape inside its cell so the contour
                              # can never touch the rectangular sprite border
EDGE_WIDTH = 9                # MinFilter size -> ~4 px contour along the shape.
                              # Owner asked for the body outline to be a little
                              # thicker; 5 was a hairline (~0.9 px on screen at
                              # the live 0.43 scale), 9 reads as ~1.7 px.
                              # EDGE_PAD=6 still keeps it off every sprite border.

# Limb sizes in the canonical 1500x1500 canvas.  EVERY cell is measured off
# Screenshot_3-6.png (the owner's third screenshot, 338x309): its silhouette
# is 262x277 px with seams at x = 28 / 50 / 99 / 134 / 188 / 225 / 266 / 289
# and y = 15 / 57 / 113 / 174 / 223 / 270 / 291.  The reference is mapped onto
# the same 101..1401 vertical span the doll already occupied, so the HUD
# scale, hover boxes and click geometry keep their overall footprint:
#   X = 750 + (x_ref - 158.5) * 4.7047,  Y = 101 + (y_ref - 15) * 4.7047.
# Left/right pairs are symmetrised from the reference (cx_R + cx_L == 1500),
# arms share one cy (T-pose), feet stay whole and compact.
#   limb id: (cx, cy, w, h)
HUMAN_LAYOUT = {
    'head':      (750, 190, 126, 178),
    'thorax':    (750, 395, 250, 232),
    'abdomen':   (750, 649, 236, 276),
    'arm_R':     (539, 376, 171, 104),
    'forearm_R': (348, 376, 211, 104),
    'hand_R':    (190, 376, 107, 104),
    'arm_L':     (961, 376, 171, 104),
    'forearm_L': (1152, 376, 211, 104),
    'hand_L':    (1310, 376, 107, 104),
    'thigh_R':   (690, 933, 115, 292),
    'thigh_L':   (810, 933, 115, 292),
    'crus_R':    (686, 1190, 84, 222),
    'crus_L':    (814, 1190, 84, 222),
    'foot_R':    (675, 1351, 80, 100),
    'foot_L':    (825, 1351, 80, 100),
}


def load_archive(arg=None):
    if arg:
        return Path(arg).read_bytes()
    env = dict(os.environ, GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.quotepath',
               GIT_CONFIG_VALUE_0='false')
    return subprocess.check_output(
        ['git', 'show', 'origin/main:' + ARCHIVE_REL], cwd=ROOT, env=env)


def cell(limb_id):
    """(left, top, right, bottom) of the limb's sprite in the 1500 canvas."""
    cx, cy, w, h = HUMAN_LAYOUT[limb_id]
    return (round(cx - w / 2), round(cy - h / 2),
            round(cx - w / 2) + w, round(cy - h / 2) + h)


def main():
    sys.path.insert(0, '/tmp/pil_pkg')
    from PIL import Image, ImageChops, ImageFilter

    z = zipfile.ZipFile(io.BytesIO(load_archive(sys.argv[1] if len(sys.argv) > 1 else None)))
    (OUT / 'limbs').mkdir(parents=True, exist_ok=True)
    (OUT / 'status').mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # 1. Place every archive silhouette into its human-proportioned cell.
    #    The shape is inset by EDGE_PAD on all four sides.  That single change
    #    is what makes the outline follow the LIMB SHAPE instead of becoming a
    #    rectangular frame: a contour derived from `hard` can never touch the
    #    sprite border (the earlier be9c0b5 build resized the shape to fill
    #    the entire cell, so MaxFilter produced a white line on all 4 sides).
    # ------------------------------------------------------------------
    soft, hard = {}, {}
    for limb_id, layer in LIMB_LAYERS.items():
        cx, cy, w, h = HUMAN_LAYOUT[limb_id]
        src = Image.open(
            io.BytesIO(z.read(PREFIX + 'zcity_delta/unitmenu/limbs/' + layer + '.png'))
        ).convert('RGBA')
        alpha = src.getchannel('A')
        # r_foot.png contains a fully transparent left half (the authored
        # sprite is 216 px wide but only the right 95 px are opaque).  Cropping
        # by the raw alpha bbox would squash the foot into a thin sliver.
        bbox = alpha.point(lambda p: 255 if p > ALPHA_THRESHOLD else 0).getbbox()
        assert bbox, limb_id
        inner_w, inner_h = w - 2 * EDGE_PAD, h - 2 * EDGE_PAD
        assert inner_w > 8 and inner_h > 8, limb_id
        scaled = alpha.crop(bbox).resize((inner_w, inner_h), Image.Resampling.LANCZOS)
        cell_soft = Image.new('L', (w, h), 0)
        cell_soft.paste(scaled, (EDGE_PAD, EDGE_PAD))
        soft[limb_id] = cell_soft
        hard[limb_id] = cell_soft.point(lambda p: 255 if p > ALPHA_THRESHOLD else 0)

    # ------------------------------------------------------------------
    # 2. One THIN outline per limb, following that limb's own silhouette.
    #    `mask - erode(mask)` is the inner boundary of the shape: it curves
    #    with the head / arm / foot exactly like C:U's own outlines/*.png.
    #    No union band, no explicit seam rectangles, no per-sprite ring: the
    #    previous build's single outer contour and 4-sided seams were both
    #    rejected live.  EDGE_PAD keeps every contour pixel off the sprite's
    #    rectangular border, so a closed white frame is impossible.
    # ------------------------------------------------------------------
    edge_lines = Image.new('L', (CANVAS, CANVAS), 0)
    for limb_id, mask in hard.items():
        contour = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(EDGE_WIDTH)))
        layer = Image.new('L', (CANVAS, CANVAS), 0)
        layer.paste(contour, cell(limb_id)[:2])
        edge_lines = ImageChops.lighter(edge_lines, layer)

    # ------------------------------------------------------------------
    # 3. Emit one FILL + one EDGE per limb, cropped back to its own cell.
    # ------------------------------------------------------------------
    for limb_id in LIMB_LAYERS:
        left, top, right, bottom = cell(limb_id)
        w, h = right - left, bottom - top

        soft_inner = soft[limb_id].filter(ImageFilter.MinFilter(JOINT_ERODE))
        fill = Image.new('RGBA', (w, h), DOLL_RGB + (0,))
        fill.putalpha(soft_inner)
        fill.save(OUT / 'limbs' / (limb_id + '_fill.png'), optimize=True)

        edge_alpha = edge_lines.crop((left, top, right, bottom))
        edge = Image.new('RGBA', (w, h), (255, 255, 255, 0))
        edge.putalpha(edge_alpha)
        edge.save(OUT / 'limbs' / (limb_id + '_edge.png'), optimize=True)

    for name in STATUS:
        src = Image.open(io.BytesIO(z.read(PREFIX + 'zcity_delta/unitmenu/status/' + name + '.png')))
        src = src.convert('RGBA')
        src.resize((32, 32), Image.Resampling.NEAREST).save(
            OUT / 'status' / (name + '.png'), optimize=True)

    lines = ['-- Generated by tools/build_unitmenu_materials.py. Do not edit by hand.',
             '-- Standard black fill + per-limb shaped outline (no rectangular frames).',
             '-- Limb sizes follow Screenshot_3-6.png, iterated once more against'
             ' the live Screenshot_4-5.png proportions; cx/cy are in the 1500x1500 canvas.',
             'WSZC_UNITMENU_LIMB_GEOMETRY = {']
    for limb_id in LIMB_LAYERS:
        cx, cy, w, h = HUMAN_LAYOUT[limb_id]
        lines.append('    %s = { cx = %.1f, cy = %.1f, w = %d, h = %d },' %
                     (limb_id, cx, cy, w, h))
    lines += ['}', '']
    GEOMETRY_LUA.write_text('\n'.join(lines), encoding='utf-8')

    # Diagnostics: the composite is a standard black human-proportioned doll
    # with a THIN outline following each limb's shape.  No sprite may have a
    # single white pixel on its rectangular border - that is the "constructor"
    # / Lego-robot frame the owner rejected twice.
    all_fill = Image.new('L', (CANVAS, CANVAS), 0)
    for limb_id, mask in hard.items():
        layer = Image.new('L', (CANVAS, CANVAS), 0)
        layer.paste(mask.filter(ImageFilter.MinFilter(JOINT_ERODE)),
                    cell(limb_id)[:2])
        all_fill = ImageChops.lighter(all_fill, layer)
    composite = Image.new('RGB', (CANVAS, CANVAS), (70, 110, 120))
    composite.paste(Image.new('RGB', (CANVAS, CANVAS), DOLL_RGB), (0, 0), all_fill)
    composite.paste(Image.new('RGB', (CANVAS, CANVAS), (245, 245, 245)), (0, 0), edge_lines)
    composite.save('/tmp/doll_fixed_preview.png')

    worst = 0.0
    empty_edges = []
    for limb_id in LIMB_LAYERS:
        a = Image.open(OUT / 'limbs' / (limb_id + '_edge.png')).convert('RGBA').getchannel('A')
        w, h = a.size
        p = a.load()
        border = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)]
        border += [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
        white = sum(1 for xy in border if p[xy[0], xy[1]] > 0)
        worst = max(worst, white / len(border))
        if a.getbbox() is None:
            empty_edges.append(limb_id)
    print('generated', len(LIMB_LAYERS) * 2,
          'limb materials (standard black fill + per-limb shaped outline),',
          len(STATUS), 'status icons + human-proportioned geometry table')
    print('max white border coverage: %.1f%% (must be 0%%)' % (worst * 100))
    assert worst == 0.0, 'a limb outline touches its rectangular sprite border'
    assert not empty_edges, 'empty outline sprites: ' + ', '.join(empty_edges)
    for limb_id in ('head', 'thorax', 'hand_R', 'foot_L'):
        print('  ', limb_id, HUMAN_LAYOUT[limb_id])


if __name__ == '__main__':
    main()
