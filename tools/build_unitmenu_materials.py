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

Visual contract (owner's live correction after be9c0b5):

  * the doll is ONE continuous dark-slate silhouette with human proportions;
  * the ONLY white pixels are THIN joint lines at the seams BETWEEN limbs;
  * there is NO white box/frame around each rectangular sprite.  The previous
    build dilated every limb independently, so each of the 15 sprites got a
    white border on all four sides and the doll looked like a Lego robot.
  * the outline sprite is still non-empty, so C:U's `finalOutline` +
    `HoverAnims` keep darkening it on hover (reaction preserved);
  * colour is unchanged: DOLL_RGB = (42, 56, 60).

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

DOLL_RGB = (42, 56, 60)      # unchanged dark slate - the owner asked not to recolor
ALPHA_THRESHOLD = 96          # r_foot.png has a transparent left half
JOINT_ERODE = 5               # 2 px inset for the fill, leaving a hairline seam

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
    #    Keep SOFT alpha for the fill (no stair-stepping after LANCZOS) and
    #    derive a HARD mask for the seam maths.
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
        scaled = alpha.crop(bbox).resize((w, h), Image.Resampling.LANCZOS)
        soft[limb_id] = scaled
        hard[limb_id] = scaled.point(lambda p: 255 if p > ALPHA_THRESHOLD else 0)

    # ------------------------------------------------------------------
    # 2. Union of ALL limb masks = ONE continuous body silhouette.
    #    The white outline is derived from this union, never from an
    #    individual rectangular sprite, so no sprite gets a white frame.
    # ------------------------------------------------------------------
    union = Image.new('L', (CANVAS, CANVAS), 0)
    for limb_id, mask in hard.items():
        layer = Image.new('L', (CANVAS, CANVAS), 0)
        layer.paste(mask, cell(limb_id)[:2])
        union = ImageChops.lighter(union, layer)

    # Joint lines are drawn EXPLICITLY on the border between two touching
    # limb cells, then clipped to the continuous body silhouette.  Deriving
    # them from each sprite's own contour was the bug: it also drew white
    # along the sprite's OUTER edges, turning the doll into a Lego robot.
    # A border line is only produced where two cells actually meet, so no
    # sprite ever gets a full white frame.
    from PIL import ImageDraw
    seam_lines = Image.new('L', (CANVAS, CANVAS), 0)
    d = ImageDraw.Draw(seam_lines)
    ids = list(LIMB_LAYERS)
    for i, a_id in enumerate(ids):
        ax0, ay0, ax1, ay1 = cell(a_id)
        for b_id in ids[i + 1:]:
            bx0, by0, bx1, by1 = cell(b_id)
            # Vertical seam: right edge of one == left edge of the other.
            if abs(ax1 - bx0) <= 6 or abs(bx1 - ax0) <= 6:
                x = (ax1 + bx0) // 2 if abs(ax1 - bx0) <= 6 else (bx1 + ax0) // 2
                y0, y1 = max(ay0, by0), min(ay1, by1)
                if y1 - y0 > 12:
                    d.rectangle((x - 1, y0, x + 1, y1), fill=255)
            # Horizontal seam: bottom edge of one == top edge of the other.
            if abs(ay1 - by0) <= 6 or abs(by1 - ay0) <= 6:
                y = (ay1 + by0) // 2 if abs(ay1 - by0) <= 6 else (by1 + ay0) // 2
                x0, x1 = max(ax0, bx0), min(ax1, bx1)
                if x1 - x0 > 12:
                    d.rectangle((x0, y - 1, x1, y + 1), fill=255)
    # Outer outline of the ONE continuous silhouette (not of each sprite).
    # `union - erode(union)` hugs the real body shape, so no rectangular
    # frame appears.  C:U tints this sprite with finalOutline/HoverAnims,
    # which is exactly the original hover reaction the owner asked to keep.
    outer_band = ImageChops.subtract(union, union.filter(ImageFilter.MinFilter(5)))
    seam_lines = ImageChops.lighter(seam_lines, outer_band)
    seam_lines = ImageChops.multiply(seam_lines, union)

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

        edge_alpha = seam_lines.crop((left, top, right, bottom))
        edge = Image.new('RGBA', (w, h), (255, 255, 255, 0))
        edge.putalpha(edge_alpha)
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

    # Diagnostics: the composite must be ONE silhouette with THIN internal
    # joint lines.  A sprite may have white on at most two of its four edges
    # (where it touches a neighbour) - never a closed white frame.
    all_fill = Image.new('L', (CANVAS, CANVAS), 0)
    for limb_id, mask in hard.items():
        layer = Image.new('L', (CANVAS, CANVAS), 0)
        layer.paste(mask.filter(ImageFilter.MinFilter(JOINT_ERODE)),
                    cell(limb_id)[:2])
        all_fill = ImageChops.lighter(all_fill, layer)
    composite = Image.new('RGB', (CANVAS, CANVAS), (70, 110, 120))
    composite.paste(Image.new('RGB', (CANVAS, CANVAS), DOLL_RGB), (0, 0), all_fill)
    composite.paste(Image.new('RGB', (CANVAS, CANVAS), (245, 245, 245)), (0, 0), seam_lines)
    composite.save('/tmp/doll_fixed_preview.png')

    # A closed rectangular frame would mean EVERY border pixel of a sprite is
    # white.  Real outlines only follow the body shape, so border coverage
    # stays well below 100% for every limb.
    worst = 0.0
    for limb_id in LIMB_LAYERS:
        a = Image.open(OUT / 'limbs' / (limb_id + '_edge.png')).convert('RGBA').getchannel('A')
        w, h = a.size
        p = a.load()
        border = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)]
        border += [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
        white = sum(1 for xy in border if p[xy[0], xy[1]] > 0)
        worst = max(worst, white / len(border))
    print('generated', len(LIMB_LAYERS) * 2,
          'limb materials (continuous slate silhouette + outline + joint lines),',
          len(STATUS), 'status icons + human-proportioned geometry table')
    print('max white border coverage: %.1f%% (must be < 60%%)' % (worst * 100))
    assert worst < 0.60, 'a limb still has a rectangular white frame'
    for limb_id in ('head', 'thorax', 'hand_R', 'foot_L'):
        print('  ', limb_id, HUMAN_LAYOUT[limb_id])


if __name__ == '__main__':
    main()
