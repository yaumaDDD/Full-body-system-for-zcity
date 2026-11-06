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

Target boxes come from the native C:U doll in Screenshot_1.png:
    218 / 322 / 452 / 594 / 710 / 820 / 869   (652 px tall)
    head 650..712, thorax 621..743, arms 368..983, legs 594..869.
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

PIXEL FIT (native Screenshot_1.png: identical placement/proportions, our style)
------------------------------------------------------------------
tools/fit_unitmenu_geometry.py renders the VERBATIM archive silhouettes into
screen space with exactly the same linear placement C:U uses, and compares
that black mask with native Screenshot_1.png (max(RGB) < 20 plus connected
components rejects the shelf/background).  A bounded coordinate descent over
(tx, ty, w, h), independently for every limb and with no shape editing,
raises the 14 measurable body-part fits to 0.82..0.99 IoU (most >0.94).
The semi-transparent head is checked from its visible contour separately.
Earlier live fixes remain history: Screenshot_6-2.png / Screenshot_7.png
showed 44 px arm sprites, and Screenshot_1-11.png rejected seam-closing masks.
The authored underarm notches and native ankle gap are NOT filled.  Styling is
UNCHANGED: pure black fill + a thin outline along each limb's own contour, no
rectangular frames and no seam-closing masks for arms.

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

# Live calibration constants (see module docstring).
LIVE_S = 0.4155
LIVE_CX, LIVE_CY = 682.5, 558.2

# Native Screenshot_1.png boxes: (target_cx, target_cy, width, height).
# Each side is fitted independently; native arms/hands are not exactly symmetric.
# Widths include a small compensation: MinFilter(JOINT_ERODE) and LANCZOS
# shave ~2 px off each side of an inner box before it reaches the screen.
# Without it the head/legs simulate 6-10 px narrower than the native doll.
REFERENCE_BOXES = {
    'head':      (682.5, 268.0, 67, 102),
    'thorax':    (681.5, 385.5, 125, 129),
    'abdomen':   (681.5, 521.5, 128, 138),
    # Independent pixel fit against native Screenshot_1.png.  The native arms
    # are NOT exactly symmetric about the thorax, so every limb owns its box;
    # no coordinates are mirrored or forced to add up to a canvas constant.
    # All 15 archive silhouettes stay VERBATIM, DOLL_RGB stays pure black and
    # every outline still follows its limb's own contour.
    'arm_R':     (576.9, 361.0, 83, 57),
    'arm_L':     (787.1, 364.0, 85, 58),
    'forearm_R': (481.0, 356.0, 111, 38),
    'forearm_L': (879.0, 356.0, 94, 36),
    'hand_R':    (395.0, 356.0, 54, 43),
    'hand_L':    (955.0, 354.0, 54, 43),
    'thigh_R':   (652.5, 650.0, 58, 112),
    'thigh_L':   (711.5, 650.0, 56, 114),
    'crus_R':    (649.5, 761.0, 45, 104),
    'crus_L':    (714.5, 761.0, 47, 104),
    'foot_R':    (646.0, 843.0, 46, 50),
    'foot_L':    (719.0, 843.0, 46, 47),
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
        # Round to 0.1 exactly like the emitted Lua.  Do NOT mirror the other
        # side: Screenshot_1.png has measurably asymmetric arm/hand placement.
        layout[limb_id] = (round(cx, 1), round(cy, 1), w, h, px, py,
                           inner_w, inner_h)
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
        # Owner (Screenshot_1-11.png): "а не меняй то как оно выглядит".
        # The 15 archive silhouettes are emitted VERBATIM for every arm/hand:
        # no closing, no band straightening.  Only the feet keep the flat sole
        # requested in Screenshot_8.png; proportions are fixed in
        # REFERENCE_BOXES below, not by redrawing the anatomy.
        if limb_id.startswith('foot_'):
            scaled = SquareToe(scaled)
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
             '-- pixel-for-pixel against native Screenshot_1.png using the live',
             '-- S=0.4155 / centre=(682.5,558.2); each limb is fitted independently.',
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
