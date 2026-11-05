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
    bounds, and a per-limb inset keeps it off all four sprite edges - so no
    white box/frame can appear ("constructor" / Lego robot);
  * the outline sprite is non-empty, so C:U's `finalOutline` + `HoverAnims`
    keep darkening it on hover (reaction preserved);
  * no single union outer band and no explicit rectangular seam lines: those
    were the previous build's rejected look.

WHY THE PREVIOUS SIZES WERE WRONG (live Screenshot_1-10.png rejection)
-----------------------------------------------------------------------
C:U's DrawSprite does NOT use the numbers from our geometry table to size a
limb.  It calls `mat:Width() * scaleMult` (and `mat:Height() * scaleMult`).
Garry's Mod uploads a PNG into the nearest power-of-two texture, so a
145x235 PNG reports Width=256 and Height=256; a 288x304 PNG reports 512x512.
The visible limb therefore scales with POT(w), NOT with w.  That is exactly
why the live doll had a 196 px torso while 288 * 0.4155 predicted 120 px,
and why a uniform 1.15x resize of every (cx,cy,w,h) could never match the
native Screenshot_2-10.png owner reference ("бля ну одинаково делай по
размерам как на том скриншоте").  A global scale leaves every limb in the
same POT bucket, so nothing changes.

THE FIX
-------
Every sprite is now emitted with an EXPLICIT power-of-two width/height, so
`mat:Width()` == `w` and `mat:Height()` == `h` under any rounding rule.  The
opaque silhouette is placed in a centred inner box whose size is exactly
`target_px / S`, where S is the live px-per-canvas-unit measured from BOTH
screenshots at the same resolution:

    S          = 0.4155     (live Screenshot_1-10.png; verified by head top
                             248, head seam 346, arm span 391..975, foot
                             bottom 869 - all four land within 2 px)
    centre     = (682.5, 558.2)   = (ScrW()/2, ScrH()/2 + 20*scale)

Target boxes come from the native C:U doll in Screenshot_2-10.png:
    218 / 320 / 451 / 592 / 708 / 810 / 865   (647 px tall)
    head 650..712, thorax 621..742, arms 303..980, legs 592..865.
For every limb: cx = 750 + (target_cx - 682.5)/S, cy likewise, and
inner = target/S.  C:U stays strictly LINEAR - only sprite dimensions and
positions change; no convar, no runtime scaling, no non-linear "calibration".

`hoverW`/`hoverH` in the Lua table carry the VISIBLE inner box, because
ApplyDoll feeds `limb.sourceW/sourceH` into C:U's hover hit test; using the
padded POT sprite there would make every hover rect far too big.

`cl_zcity_woundsystem_compat_layout.lua` forces a white draw colour for the
`*_fill.png` sprites ONLY (C:U otherwise multiplies them by a black
`finalMiddle`); `*_edge.png` is deliberately NOT overridden so C:U keeps
control of the outline colour and its hover animation.

LIVE PROPORTION CORRECTION (Screenshot_6-2.png / Screenshot_7.png)
------------------------------------------------------------------
Pixel-column profiling against Screenshot_2-10.png showed the doll was NOT
mis-positioned: head (98 vs 100 px), thorax (129/133 vs 128/139 px), thighs
(114 vs 112 px) and calves (99 vs 101 px) all matched within 1-3 px.  The
mismatch was limb THICKNESS - all six arm sprites rendered 44 px tall
(y 333..377) where the native doll is 33..36 px (y 337..373), i.e. the arms
looked like thick rectangular bars instead of human limbs.  The six arm
REFERENCE_BOXES heights went 50 -> 40; the centre is unchanged, so the top
and bottom edges each move 4 px toward the middle.  POT height drops from
256 to 128 for those sprites, but the opaque inner box stays centred, so
C:U's `mat:Height() * scale` still places the visible silhouette correctly.

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

# The diagnostic compositing canvas.  C:U positions limbs linearly about
# canvas centre 750; the calibrated reference reaches -202..1550, so the
# scratch canvas is padded.  The Lua table ALWAYS stores unpadded cx/cy.
CANVAS_PAD = 320
CANVAS = 1500 + 2 * CANVAS_PAD
CENTRE = 750.0

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
JOINT_ERODE = 3               # 1 px inset for the fill.  Screenshot_3-7 live
                              # seams were 6-11 px wide vs the native 2-4 px
                              # on Screenshot_2-10; the old MinFilter(5) ate
                              # 2 px per side and then got magnified by POT.
EDGE_PAD_MIN = 6              # minimum inset of the shape inside its POT sprite
EDGE_WIDTH = 9                # MinFilter size -> ~4 px contour along the shape.
                              # Owner asked for the body outline to be a little
                              # thicker; 5 was a hairline, 9 reads as ~1.7 px.
ERODE_MARGIN = 4              # MinFilter(JOINT_ERODE) eats 2 px per side
JOINT_SQUARE_FRAC = 0.12      # Screenshot_8.png red circles: the archive arms
                              # end in a diagonal notch (stepped shoulder /
                              # wrist) and the feet are wedge "boots", leaving
                              # white gaps at the joints.  Straighten only the
                              # outer 12% of each joint face.
SEAM_LIMBS = {
    'arm_R', 'arm_L', 'forearm_R', 'forearm_L', 'hand_R', 'hand_L',
    'foot_R', 'foot_L',
}

# Live calibration constants (see module docstring).
LIVE_S = 0.4155
LIVE_CX, LIVE_CY = 682.5, 558.2

# Native Screenshot_2-10.png boxes: (target_cx, target_cy, width, height).
# Symmetric pairs are pre-mirrored about 682.5 so cx_R + cx_L == 1500 exactly.
# Widths include a small compensation: MinFilter(JOINT_ERODE) and LANCZOS
# shave ~2 px off each side of an inner box before it reaches the screen.
# Without it the head/legs simulate 6-10 px narrower than the native doll.
REFERENCE_BOXES = {
    'head':      (682.5, 267.0, 70, 102),
    'thorax':    (682.5, 385.5, 122, 131),
    'abdomen':   (682.5, 521.5, 132, 141),
    # Screenshot_6-2.png / Screenshot_7.png live measurement: the arms were
    # 44 px thick (y 333..377) while the native Screenshot_2-10.png doll is
    # 33..36 px (y 337..373).  Head/torso/thighs/calves already matched in
    # +/-1..3 px, so this is a PROPORTION fix, not a repositioning: shrinking
    # the height about the same centre automatically moves the top edge down
    # 4 px and the bottom edge up 4 px, exactly onto the native band.
    'arm_R':     (578.9, 355.0, 82, 40),
    'arm_L':     (786.1, 355.0, 82, 40),
    'forearm_R': (480.0, 355.0, 110, 40),
    'forearm_L': (885.0, 355.0, 110, 40),
    'hand_R':    (400.0, 355.0, 47, 40),
    'hand_L':    (965.0, 355.0, 47, 40),
    'thigh_R':   (652.5, 650.0, 60, 116),
    'thigh_L':   (712.5, 650.0, 60, 116),
    'crus_R':    (649.5, 759.0, 46, 102),
    'crus_L':    (715.5, 759.0, 46, 102),
    'foot_R':    (650.0, 837.5, 45, 55),
    'foot_L':    (715.0, 837.5, 45, 55),
}


def next_pot(v):
    p = 16
    while p < v:
        p *= 2
    return p


def build_layout():
    """Exact inverse of C:U's linear placement for the reference screenshot."""
    layout = {}
    for limb_id, (tx, ty, tw, th) in REFERENCE_BOXES.items():
        cx = CENTRE + (tx - LIVE_CX) / LIVE_S
        cy = CENTRE + (ty - LIVE_CY) / LIVE_S
        inner_w = int(round(tw / LIVE_S))
        inner_h = int(round(th / LIVE_S))
        w = next_pot(inner_w + 2 * EDGE_PAD_MIN + ERODE_MARGIN)
        h = next_pot(inner_h + 2 * EDGE_PAD_MIN + ERODE_MARGIN)
        px = (w - inner_w) // 2
        py = (h - inner_h) // 2
        assert px >= EDGE_PAD_MIN and py >= EDGE_PAD_MIN, limb_id
        # Round to 0.1 exactly like the emitted Lua, then RE-ASSERT symmetry
        # in the same representation that C:U will read.
        layout[limb_id] = (round(cx, 1), round(cy, 1), w, h, px, py,
                           inner_w, inner_h)
    for a, b in (('arm_R', 'arm_L'), ('forearm_R', 'forearm_L'),
                 ('hand_R', 'hand_L'), ('thigh_R', 'thigh_L'),
                 ('crus_R', 'crus_L'), ('foot_R', 'foot_L')):
        assert layout[a][0] + layout[b][0] == 1500.0, (a, b)
    return layout


HUMAN_LAYOUT = build_layout()


def load_archive(arg=None):
    if arg:
        return Path(arg).read_bytes()
    env = dict(os.environ, GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.quotepath',
               GIT_CONFIG_VALUE_0='false')
    return subprocess.check_output(
        ['git', 'show', 'origin/main:' + ARCHIVE_REL], cwd=ROOT, env=env)


def cell(limb_id):
    """(left, top, right, bottom) inside the padded diagnostic canvas."""
    cx, cy, w, h = HUMAN_LAYOUT[limb_id][:4]
    left, top = round(cx - w / 2) + CANVAS_PAD, round(cy - h / 2) + CANVAS_PAD
    return (left, top, left + w, top + h)


def CloseMask(mask):
    """Morphological closing: smooth notches without changing thickness."""
    from PIL import ImageFilter
    return mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))


def FlattenLimbBand(mask):
    """Straighten an arm/forearm into a flush, gap-free band.

    The archive upper-arm layer ends in a deep diagonal underarm notch.  In
    C:U's own doll that notch met a differently shaped torso; in our POT doll
    it leaves a bright wedge between the upper arm, the forearm and the chest
    (Screenshot_8.png red circles).  The native Screenshot_2-10.png doll has
    straight horizontal arms with thin seam lines, so a constant rectangular
    band - not a new anatomy - is the faithful shape.  Width/height/centre are
    untouched; only the empty pixels INSIDE the inner box are filled.
    """
    px = mask.load()
    w, h = mask.size
    top, bottom = h, -1
    for x in range(int(w * 0.30), int(w * 0.70)):
        ys = [y for y in range(h) if px[x, y] > ALPHA_THRESHOLD]
        if ys:
            top, bottom = min(top, ys[0]), max(bottom, ys[-1])
    if bottom <= top:
        return mask
    # Replace the whole inner box with one constant-height band.  Filling only
    # downward left the original underarm notch BELOW `bottom` in place: that
    # was the diagonal still visible on the first attempt.
    for x in range(w):
        for y in range(h):
            px[x, y] = 255 if top <= y <= bottom else 0
    return mask


def SquareToe(mask):
    """Turn the archive's wedge "boot" into a flat-soled shoe.

    Screenshot_8.png bottom circle: our feet are trapezoids that taper to a
    point, while the native doll wears straight-sided boots.  Fill the lowest
    JOINT_SQUARE_FRAC of rows to the widest part of the foot so the sole is
    horizontal; the ankle and the shaped top stay as authored.
    """
    px = mask.load()
    w, h = mask.size
    left, right = w, -1
    for y in range(int(h * 0.45), h):
        xs = [x for x in range(w) if px[x, y] > ALPHA_THRESHOLD]
        if xs:
            left, right = min(left, xs[0]), max(right, xs[-1])
    if right <= left:
        return mask
    for y in range(h - max(2, int(h * JOINT_SQUARE_FRAC)), h):
        for x in range(left, right + 1):
            px[x, y] = 255
    return mask


def main():
    sys.path.insert(0, '/tmp/pil_pkg')
    from PIL import Image, ImageChops, ImageFilter

    z = zipfile.ZipFile(io.BytesIO(load_archive(sys.argv[1] if len(sys.argv) > 1 else None)))
    (OUT / 'limbs').mkdir(parents=True, exist_ok=True)
    (OUT / 'status').mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # 1. Place every archive silhouette into its POT sprite's inner box.
    #    The inner box is exactly target_px / LIVE_S wide/tall, so once GMod
    #    reports mat:Width() == w the limb lands on the native pixel box.
    #    A per-limb inset keeps the contour off the rectangular sprite edge.
    # ------------------------------------------------------------------
    soft, hard = {}, {}
    for limb_id, layer in LIMB_LAYERS.items():
        cx, cy, w, h, px, py, inner_w, inner_h = HUMAN_LAYOUT[limb_id]
        assert w == next_pot(w) and h == next_pot(h), limb_id
        src = Image.open(
            io.BytesIO(z.read(PREFIX + 'zcity_delta/unitmenu/limbs/' + layer + '.png'))
        ).convert('RGBA')
        alpha = src.getchannel('A')
        # r_foot.png contains a fully transparent left half (the authored
        # sprite is 216 px wide but only the right 95 px are opaque).  Cropping
        # by the raw alpha bbox would squash the foot into a thin sliver.
        bbox = alpha.point(lambda p: 255 if p > ALPHA_THRESHOLD else 0).getbbox()
        assert bbox, limb_id
        assert inner_w > 8 and inner_h > 8, limb_id
        scaled = alpha.crop(bbox).resize((inner_w, inner_h), Image.Resampling.LANCZOS)
        if limb_id in SEAM_LIMBS:
            scaled = CloseMask(scaled)
            if limb_id.startswith('arm_') or limb_id.startswith('forearm_'):
                scaled = FlattenLimbBand(scaled)
            elif limb_id.startswith('foot_'):
                scaled = SquareToe(scaled)
            # hand_* keeps its authored fingers - straightening them produced
            # the square "claw" the owner rejected on Screenshot_8.png.
        cell_soft = Image.new('L', (w, h), 0)
        cell_soft.paste(scaled, (px, py))
        soft[limb_id] = cell_soft
        hard[limb_id] = cell_soft.point(lambda p: 255 if p > ALPHA_THRESHOLD else 0)

    # ------------------------------------------------------------------
    # 2. One THIN outline per limb, following that limb's own silhouette.
    #    `mask - erode(mask)` is the inner boundary of the shape: it curves
    #    with the head / arm / foot exactly like C:U's own outlines/*.png.
    #    No union band, no explicit seam rectangles, no per-sprite ring.
    # ------------------------------------------------------------------
    edge_lines = Image.new('L', (CANVAS, CANVAS), 0)
    contours = {}
    for limb_id, mask in hard.items():
        contour = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(EDGE_WIDTH)))
        contours[limb_id] = contour
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

        # POT cells overlap in the padded canvas, so cropping the shared
        # outline canvas would leak a neighbour's contour onto this sprite's
        # rectangular border.  Use THIS limb's own contour instead.
        edge_alpha = contours[limb_id]
        assert edge_alpha.size == (w, h), limb_id
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
             '-- POT sprite sizes: C:U sizes limbs by mat:Width()/Height(), which GMod',
             '-- rounds to a power of two.  Inner silhouette boxes are calibrated',
             '-- pixel-for-pixel against native Screenshot_2-10.png using the live',
             '-- S=0.4155 / centre=(682.5,558.2) from Screenshot_1-10.png.',
             '-- cx/cy are in the 1500x1500 canvas; hoverW/hoverH are the VISIBLE',
             '-- inner boxes (used for C:U sourceW/sourceH hit tests).',
             'WSZC_UNITMENU_LIMB_GEOMETRY = {']
    for limb_id in LIMB_LAYERS:
        cx, cy, w, h, px, py, inner_w, inner_h = HUMAN_LAYOUT[limb_id]
        lines.append('    %s = { cx = %.1f, cy = %.1f, w = %d, h = %d, '
                     'hoverW = %d, hoverH = %d },' %
                     (limb_id, cx, cy, w, h, inner_w, inner_h))
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
          len(STATUS), 'status icons + POT-calibrated geometry table')
    print('max white border coverage: %.1f%% (must be 0%%)' % (worst * 100))
    assert worst == 0.0, 'a limb outline touches its rectangular sprite border'
    assert not empty_edges, 'empty outline sprites: ' + ', '.join(empty_edges)
    for limb_id in ('head', 'thorax', 'hand_R', 'foot_L'):
        print('  ', limb_id, HUMAN_LAYOUT[limb_id][:4])


if __name__ == '__main__':
    main()
