#!/usr/bin/env python3
"""Generate pixel-exact WoundView limb materials from the clean 1435 reference.

PRIMARY PATH: tools/tests/woundview_reference_clean_1365x1079.png is the owner's
1435.png (SHA-256 pinned).  It shows the SAME doll as 2222 but has no tooltip
covering the abdomen.  trace_reference_masks() extracts each limb's actual black
fill and white outline, and emit_reference_traced() proves a FULL-CELL zero-pixel
round trip through the shipped POT textures.  Status icons still come from the
repository UI archive.  The old archive-shape fitting below is ONLY a fallback
when the clean reference file is absent.

Legacy fallback source: origin/main:для переделывания интерфейса.zip
         (addon "human_hands_for_z_city_casualties_medical_system_heavy_wip")

The archive contains 15 already-positioned 1500x1500 RGBA limb layers.  Their
baked positions produce a wide "coat" with stubby legs, so we resample each
layer's alpha into an explicit HUMAN-PROPORTION blueprint (the green WoundView
reference the owner supplied).  The source head also contains the neck: the
generator CROPS that source BEFORE calibration, then fits independent head and
neck sprites without putting a second stretched skull into the neck.
C:U's WoundView therefore draws 16 small sprites (middle + outline), each at its
own ox/oy:

    woundsystem_zcity_compat/materials/wszc/unitmenu/limbs/<id>_fill.png
    woundsystem_zcity_compat/materials/wszc/unitmenu/limbs/<id>_edge.png
    woundsystem_zcity_compat/materials/wszc/unitmenu/status/<name>.png
    woundsystem_zcity_compat/lua/autorun/client/wszc_unitmenu_geometry.lua

Visual contract (owner's live correction after 6e2196f, confirmed by choice):

  * the doll keeps the HUMAN-PROPORTION blueprint (small head, narrow torso,
    T-pose, long legs, whole feet) - the anatomy is NOT reverted to C:U;
  * colour is the STANDARD black: DOLL_RGB = (0, 0, 0), exactly the RGB of
    the archive's own limb layers.  The slate (42, 56, 60) was rejected live;
  * the outline follows the SHAPE OF EACH LIMB and matches the green reference:
    EDGE_WIDTH=17 for the bold 3-4 px body contour and 11 for the finer finger
    contour.  It is derived from each limb's alpha, never from the rectangular
    sprite bounds, and a per-limb inset keeps it off all four sprite edges - so
    no white box/frame can appear ("constructor" / Lego robot);
  * neck owns the single head/neck seam at screen y=317; abdomen has its native
    internal seam at y=520.  Neither joint is a rectangular sprite frame;
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

    S          = 0.4155     (2222.png at 1365x1079)
    centre     = (682.5, 558.2)   = Scr centre + measured 18.7 px Y offset

Target boxes come from the pinned green reference
``tools/tests/woundview_reference_1365x1079.png`` (the owner's 2222.png):
head top 242, head/neck seam 317, thorax 338..455, abdomen 457..584,
legs 587..836, and asymmetric hand/forearm spans.  For every limb:
cx = 750 + (target_cx - 682.5)/S, cy likewise, and inner = target/S.
C:U placement stays strictly LINEAR.  At runtime 0.25 selects this exact
reference transform; UnitmenuReferenceDollTransform compensates the saved
woundsys_ui_scale and native centreY, so 1111.png's accidental S=0.469 cannot
reappear when that C:U setting is 1.25.

`hoverW`/`hoverH` in the Lua table carry the VISIBLE inner box, because
ApplyDoll feeds `limb.sourceW/sourceH` into C:U's hover hit test; using the
padded POT sprite there would make every hover rect far too big.

`cl_zcity_woundsystem_compat_layout.lua` forces a white draw colour for the
`*_fill.png` sprites ONLY (C:U otherwise multiplies them by a black
`finalMiddle`); `*_edge.png` is deliberately NOT overridden so C:U keeps
control of the outline colour and its hover animation.

PIXEL FIT (green WoundView reference: placement, contour, and joints)
------------------------------------------------------------------
tools/fit_unitmenu_geometry.py renders the VERBATIM archive silhouettes into
screen space with exactly the same linear placement C:U uses, subtracts the
white contour (fill is drawn first, edge second), and compares the visible
black mask with the pinned reference.  Connected components reject the green
room and interface text.  A bounded coordinate descent can adjust only
(tx, ty, w, h), independently for every limb and with no shape editing.
Regression S53 checks every visible black bbox to at most two pixels, checks
the WHITE exterior of both hands as well, and verifies the single y=317 neck
seam and y=520 abdomen seam.  The authored underarm notches and native ankle
gap are NOT filled; there are no rectangular frames or seam-closing arm masks.

Usage: python3 tools/build_unitmenu_materials.py [path/to/ui.zip]
Requires Pillow.
"""
import hashlib
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
REFERENCE_CLEAN = ROOT / 'tools/tests/woundview_reference_clean_1365x1079.png'
REFERENCE_CLEAN_SHA256 = '110ba623aab4d00262113887a6570bfba46ba8bc940b5eb1fbafd5017e8e38f6'
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
    'neck': 'head',  # lower joint of the SAME scaled source silhouette
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
EDGE_WIDTH = 17               # MinFilter size -> ~8 source px / 3.3 live px.
                              # woundview_reference_1365x1079.png uses a bold
                              # 3-4 px native contour; 9 was only ~1.7 px.
EDGE_WIDTH_OVERRIDES = {'hand_R': 11, 'hand_L': 11}
                              # Native fingers use a finer ~2 px contour; 17
                              # eats the narrow finger interiors completely.
EDGE_AA_RADIUS = 0.45         # Sub-source-pixel alpha fringe: smooth the live
                              # contour without moving its measured silhouette.
OUTER_EDGE_WIDTH = 9          # Radius 4 source px (~1.7 reference px).  2222's
                              # white stroke extends OUTSIDE the fill as well as
                              # inside it; inner-only contours looked too thin.
# Arms/thorax already match 2222 with the inner stroke; adding a second outer
# band where their sprites overlap makes the shoulder/underarm lines too bold.
OUTER_EDGE_EXCLUDED = {
    'hand_R', 'hand_L', 'neck', 'thorax',
    'arm_R', 'arm_L', 'forearm_R', 'forearm_L',
}
ABDOMEN_SEAM_Y = 520.5        # Sub-pixel phase puts the dominant row at 520.
ABDOMEN_SEAM_WIDTH = 2        # One dominant screen row; neighbours stay < 11/255.
HEAD_SEAM_WIDTH = 3           # Native head/neck joint is one row at y=317.
ERODE_MARGIN = 4              # MinFilter(JOINT_ERODE) eats 2 px per side
# Live calibration constants (see module docstring).
LIVE_S = 0.4155
LIVE_CX, LIVE_CY = 682.5, 558.2

# Green-reference boxes: (target_cx, target_cy, width, height).
# Each side is fitted independently; native arms/hands are not exactly symmetric.
# Widths include a small compensation: MinFilter(JOINT_ERODE) and LANCZOS
# shave ~2 px off each side of an inner box before it reaches the screen.
# Without it the head/legs simulate 6-10 px narrower than the native doll.
# Exact target: tools/tests/woundview_reference_1365x1079.png (green room,
# Abdomen tooltip).  Boxes were fitted against the black INTERIOR of every
# native limb WITH the bold EDGE_WIDTH=17 contour already applied.  Most boxes
# have zero left/top/right/bottom error in the screen renderer; the remaining
# error is at most two pixels and is checked again by the regression suite.
# The head source is cropped into two segments BEFORE these independent
# calibrations, so neck never contains a second stretched copy of the skull.
REFERENCE_BOXES = {
    'head':      (688.5, 279.5, 64.3, 83.3),
    'neck':      (688.0, 326.5, 79.8, 23.3),
    'thorax':    (687.5, 396.5, 119.3, 124.3),
    'abdomen':   (687.0, 520.5, 122.3, 134.3),
    'arm_R':     (594.9, 376.0, 79.8, 62.8),
    'arm_L':     (785.6, 378.0, 83.3, 61.3),
    'forearm_R': (505.0, 369.0, 106.8, 41.3),
    'forearm_L': (869.5, 369.5, 90.3, 38.3),
    'hand_R':    (427.0, 369.0, 56.0, 47.5),
    'hand_L':    (939.0, 367.0, 56.0, 46.5),
    'thigh_R':   (661.0, 638.0, 59.8, 108.8),
    'thigh_L':   (714.0, 638.5, 55.3, 108.8),
    'crus_R':    (659.0, 739.0, 49.3, 102.3),
    'crus_L':    (718.0, 740.0, 49.3, 104.8),
    'foot_R':    (654.0, 814.0, 49.8, 51.8),
    'foot_L':    (724.5, 813.0, 50.3, 51.3),
}


def next_pot(v):
    p = 16
    while p < v:
        p *= 2
    return p


def layout_entry(box):
    """Exact inverse of C:U's linear placement for one reference box."""
    tx, ty, tw, th = box
    cx = CENTRE + (tx - LIVE_CX) / LIVE_S
    cy = CENTRE + (ty - LIVE_CY) / LIVE_S
    inner_w = int(round(tw / LIVE_S))
    inner_h = int(round(th / LIVE_S))
    w = next_pot(inner_w + 2 * EDGE_PAD_MIN + ERODE_MARGIN)
    h = next_pot(inner_h + 2 * EDGE_PAD_MIN + ERODE_MARGIN)
    px = (w - inner_w) // 2
    py = (h - inner_h) // 2
    assert px >= EDGE_PAD_MIN and py >= EDGE_PAD_MIN, box
    # Round to 0.1 exactly like the emitted Lua.  Do NOT mirror the other
    # side: the green reference has measurably asymmetric arm/hand placement.
    return (round(cx, 1), round(cy, 1), w, h, px, py, inner_w, inner_h)


def build_layout():
    return {limb_id: layout_entry(box)
            for limb_id, box in REFERENCE_BOXES.items()}


HUMAN_LAYOUT = build_layout()
HEAD_SPLIT_FRAC = 185 / 245   # Authored skull/neck cut in the source alpha.


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


# Clean 1435.png: same doll as 2222, but WITHOUT the Abdomen tooltip covering
# pixels.  Each region owns its joints; this prevents a neighbour's white seam
# from leaking into a sprite.  Seeds select only the real black limb component,
# never the dark room/viewmodel behind it.
TRACE_REGIONS = {
    'head': ((640, 225, 736, 317), [(688, 278)]),
    'neck': ((640, 317, 736, 338), [(688, 327)]),
    'thorax': ((620, 338, 756, 456), [(688, 395)]),
    'abdomen': ((620, 456, 756, 586), [(650, 480), (650, 550)]),
    'arm_R': ((540, 330, 633, 410), [(595, 375)]),
    'arm_L': ((744, 330, 840, 410), [(790, 375)]),
    'forearm_R': ((450, 335, 559, 400), [(505, 369)]),
    'forearm_L': ((824, 335, 925, 400), [(870, 369)]),
    'hand_R': ((385, 330, 455, 405), [(427, 369)]),
    'hand_L': ((912, 330, 980, 405), [(939, 369)]),
    'thigh_R': ((620, 584, 689, 695), [(650, 640)]),
    'thigh_L': ((689, 584, 750, 695), [(715, 640)]),
    'crus_R': ((625, 690, 686, 795), [(650, 740)]),
    'crus_L': ((690, 690, 750, 795), [(718, 740)]),
    'foot_R': ((615, 787, 684, 850), [(650, 815)]),
    'foot_L': ((690, 787, 760, 850), [(725, 815)]),
}


def reference_screen_cell(limb_id):
    """POT cell's exact destination rectangle on the 1365x1079 reference."""
    cx, cy, w, h = HUMAN_LAYOUT[limb_id][:4]
    sw, sh = round(w * LIVE_S), round(h * LIVE_S)
    left = round(LIVE_CX + (round(cx - w / 2) - CENTRE) * LIVE_S)
    top = round(LIVE_CY + (round(cy - h / 2) - CENTRE) * LIVE_S)
    return left, top, sw, sh


def trace_reference_masks(reference):
    """Trace independent fill/edge/black masks directly from clean 1435.png."""
    from PIL import Image, ImageChops, ImageFilter

    assert reference.size == (1365, 1079), reference.size
    reference = reference.convert('RGB')
    width, height = reference.size
    pixels = reference.load()
    traced = {}
    for limb_id, (region, seeds) in TRACE_REGIONS.items():
        x0, y0, x1, y1 = region
        raw = Image.new('L', (width, height), 0)
        rp = raw.load()
        for y in range(y0, y1):
            for x in range(x0, x1):
                if max(pixels[x, y]) < 32:
                    rp[x, y] = 255

        kept = set()
        for seed in seeds:
            if seed in kept:
                continue
            assert rp[seed], (limb_id, 'reference seed is not black', seed)
            stack, kept = [seed], kept | {seed}
            while stack:
                x, y = stack.pop()
                for point in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    nx, ny = point
                    if (x0 <= nx < x1 and y0 <= ny < y1 and rp[point]
                            and point not in kept):
                        kept.add(point)
                        stack.append(point)
        black = Image.new('L', (width, height), 0)
        bp = black.load()
        for x, y in kept:
            bp[x, y] = 255

        # Neutral white is accepted ONLY within nine pixels of this limb's own
        # black fill.  Grey background and orange/skin viewmodels cannot leak
        # into the outline.  The nine-pixel band also covers every finger.
        near = black.filter(ImageFilter.MaxFilter(19))
        np = near.load()
        edge = Image.new('L', (width, height), 0)
        ep = edge.load()
        # Do NOT paste the search padding itself: a neighbouring forearm seam
        # inside that padding is not part of the hand sprite.  Each white pixel
        # belongs to its explicit anatomical region and to no other limb.
        for y in range(y0, y1):
            for x in range(x0, x1):
                r, g, b = pixels[x, y]
                if np[x, y] and min(r, g, b) > 150 and max(r, g, b) - min(r, g, b) < 55:
                    ep[x, y] = 255
        traced[limb_id] = {
            'black': black,
            'edge': edge,
            'fill': ImageChops.lighter(black, edge),
        }
    return traced


def emit_reference_traced(z):
    """Emit pixel-exact 1435 sprites; archive fitting remains only a fallback."""
    from PIL import Image, ImageChops

    digest = hashlib.sha256(REFERENCE_CLEAN.read_bytes()).hexdigest()
    assert digest == REFERENCE_CLEAN_SHA256, 'clean 1435 reference changed'
    reference = Image.open(REFERENCE_CLEAN).convert('RGB')
    traced = trace_reference_masks(reference)
    preview = Image.new('RGB', reference.size, (10, 30, 20))
    total_mismatch = 0

    for limb_id in LIMB_LAYERS:
        left, top, sw, sh = reference_screen_cell(limb_id)
        w, h = HUMAN_LAYOUT[limb_id][2:4]
        box = (left, top, left + sw, top + sh)
        masks = traced[limb_id]
        target_fill = masks['fill'].crop(box)
        target_edge = masks['edge'].crop(box)
        target_black = masks['black'].crop(box)

        allowed = Image.new('L', reference.size, 0)
        allowed.paste(255, box)
        outside = ImageChops.subtract(
            masks['fill'], ImageChops.multiply(masks['fill'], allowed))
        assert outside.getbbox() is None, (limb_id, 'traced pixel outside POT cell')

        fill_alpha = target_fill.resize((w, h), Image.Resampling.LANCZOS)
        edge_alpha = target_edge.resize((w, h), Image.Resampling.LANCZOS)
        # LANCZOS can leave a sub-1/255 ringing value on the technical POT
        # border even when the traced shape is several pixels away.  Keep the
        # old no-rectangular-frame invariant without touching visible pixels.
        for alpha in (fill_alpha, edge_alpha):
            alpha.paste(0, (0, 0, w, 1))
            alpha.paste(0, (0, h - 1, w, h))
            alpha.paste(0, (0, 0, 1, h))
            alpha.paste(0, (w - 1, 0, w, h))
        fill = Image.new('RGBA', (w, h), DOLL_RGB + (0,))
        fill.putalpha(fill_alpha)
        fill.save(OUT / 'limbs' / (limb_id + '_fill.png'), optimize=True)
        edge = Image.new('RGBA', (w, h), (255, 255, 255, 0))
        edge.putalpha(edge_alpha)
        edge.save(OUT / 'limbs' / (limb_id + '_edge.png'), optimize=True)

        # Prove the actual shipped POT textures reproduce the reference after
        # C:U/GMod's downsample.  This is a FULL CELL mask comparison, not a
        # bbox/IoU approximation: black interior AND white exterior must match.
        down_fill = fill_alpha.resize((sw, sh), Image.Resampling.LANCZOS)
        down_edge = edge_alpha.resize((sw, sh), Image.Resampling.LANCZOS)
        black = ImageChops.subtract(
            down_fill.point(lambda p: 255 if p > ALPHA_THRESHOLD else 0),
            down_edge.point(lambda p: 255 if p > ALPHA_THRESHOLD else 0))
        white = down_edge.point(lambda p: 255 if p > 180 else 0)
        target_white = target_edge.point(lambda p: 255 if p > 180 else 0)
        total_mismatch += sum(a != b for a, b in zip(black.tobytes(), target_black.tobytes()))
        total_mismatch += sum(a != b for a, b in zip(white.tobytes(), target_white.tobytes()))
        preview.paste(Image.new('RGB', (sw, sh), DOLL_RGB), (left, top), down_fill)
        preview.paste(Image.new('RGB', (sw, sh), (255, 255, 255)), (left, top), down_edge)

    assert total_mismatch == 0, ('1435 round-trip pixel mismatch', total_mismatch)
    preview.save('/tmp/doll_reference_traced_preview.png')

    for name in STATUS:
        src = Image.open(io.BytesIO(
            z.read(PREFIX + 'zcity_delta/unitmenu/status/' + name + '.png'))).convert('RGBA')
        src.resize((32, 32), Image.Resampling.NEAREST).save(
            OUT / 'status' / (name + '.png'), optimize=True)

    lines = ['-- Generated by tools/build_unitmenu_materials.py. Do not edit by hand.',
             '-- PIXEL-TRACED from clean 1435.png; black fill + white per-limb outline.',
             '-- Full-cell black/white round-trip mismatch: 0 pixels on all 16 limbs.',
             '-- Head/neck seams and abdomen seam are traced, not approximated.',
             '-- POT cells + canonical S=0.4155 / centre=(682.5,558.2).',
             '-- cx/cy are canvas coordinates; hoverW/hoverH are native hitboxes.',
             'WSZC_UNITMENU_LIMB_GEOMETRY = {']
    for limb_id in LIMB_LAYERS:
        cx, cy, w, h, px, py, inner_w, inner_h = HUMAN_LAYOUT[limb_id]
        lines.append('    %s = { cx = %.1f, cy = %.1f, w = %d, h = %d, '
                     'hoverW = %d, hoverH = %d },' %
                     (limb_id, cx, cy, w, h, inner_w, inner_h))
    lines += ['}', '']
    GEOMETRY_LUA.write_text('\n'.join(lines), encoding='utf-8')

    worst = 0.0
    for limb_id in LIMB_LAYERS:
        alpha = Image.open(OUT / 'limbs' / (limb_id + '_edge.png')).convert('RGBA').getchannel('A')
        w, h = alpha.size
        p = alpha.load()
        border = ([(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)]
                  + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)])
        worst = max(worst, sum(1 for x, y in border if p[x, y] > 0) / len(border))
    assert worst == 0.0, 'a traced outline touches its rectangular sprite border'
    print('generated 32 PIXEL-TRACED 1435 limb materials; full-cell mismatch: 0')
    print('max white border coverage: %.1f%% (must be 0%%)' % (worst * 100))


def main():
    sys.path.insert(0, '/tmp/pil_pkg')
    from PIL import Image, ImageChops, ImageFilter

    z = zipfile.ZipFile(io.BytesIO(load_archive(sys.argv[1] if len(sys.argv) > 1 else None)))
    (OUT / 'limbs').mkdir(parents=True, exist_ok=True)
    (OUT / 'status').mkdir(parents=True, exist_ok=True)

    if REFERENCE_CLEAN.is_file():
        emit_reference_traced(z)
        return

    # ------------------------------------------------------------------
    # FALLBACK when the pinned clean reference is unavailable.
    # 1. Place every archive silhouette into its POT sprite's inner box.
    #    The inner box is exactly target_px / LIVE_S wide/tall, so once GMod
    #    reports mat:Width() == w the limb lands on the native pixel box.
    #    A per-limb inset keeps the contour off the rectangular sprite edge.
    # ------------------------------------------------------------------
    def archive_cell(limb_id, layer, layout, source=None):
        """Resize one archive alpha/cropped segment into its POT cell."""
        cx, cy, w, h, px, py, inner_w, inner_h = layout
        assert w == next_pot(w) and h == next_pot(h), limb_id
        if source is None:
            source = Image.open(
                io.BytesIO(z.read(PREFIX + 'zcity_delta/unitmenu/limbs/' + layer + '.png'))
            ).convert('RGBA')
        alpha = source if source.mode == 'L' else source.getchannel('A')
        # r_foot.png contains a fully transparent left half (the authored
        # sprite is 216 px wide but only the right 95 px are opaque).  Cropping
        # by the raw alpha bbox would squash the foot into a thin sliver.
        bbox = alpha.point(lambda p: 255 if p > ALPHA_THRESHOLD else 0).getbbox()
        assert bbox, limb_id
        assert inner_w > 8 and inner_h > 8, limb_id
        scaled = alpha.crop(bbox).resize((inner_w, inner_h), Image.Resampling.LANCZOS)
        # The archive silhouettes are emitted VERBATIM for every limb: no
        # closing, band straightening, or square-toe override.  In particular,
        # the green reference has rounded boot soles, so the former SquareToe
        # shape edit was removed.  Only REFERENCE_BOXES changes proportions.
        result = Image.new('L', (w, h), 0)
        result.paste(scaled, (px, py))
        return result

    # Split the ORIGINAL alpha before calibration.  The reference neck is
    # relatively wider/shorter than the old build, so each already-cropped
    # segment gets its own measured box.  No full skull is ever resized into
    # the neck sprite, and no second head silhouette is introduced.
    head_source = Image.open(io.BytesIO(
        z.read(PREFIX + 'zcity_delta/unitmenu/limbs/head.png'))).convert('RGBA')
    head_alpha = head_source.getchannel('A')
    head_bbox = head_alpha.point(
        lambda p: 255 if p > ALPHA_THRESHOLD else 0).getbbox()
    head_alpha = head_alpha.crop(head_bbox)
    source_split = round(head_alpha.height * HEAD_SPLIT_FRAC)
    head_segments = {
        'head': head_alpha.crop((0, 0, head_alpha.width, source_split)),
        'neck': head_alpha.crop((0, source_split, head_alpha.width, head_alpha.height)),
    }

    soft, hard = {}, {}
    for limb_id, layer in LIMB_LAYERS.items():
        layout = HUMAN_LAYOUT[limb_id]
        cell_soft = archive_cell(limb_id, layer, layout,
                                 source=head_segments.get(limb_id))
        soft[limb_id] = cell_soft
        hard[limb_id] = cell_soft.point(lambda p: 255 if p > ALPHA_THRESHOLD else 0)

    # ------------------------------------------------------------------
    # 2. One reference-matched outline per limb, following its own silhouette.
    #    `mask - erode(mask)` is the inner boundary of the shape: it curves
    #    with the head / arm / foot exactly like C:U's own outlines/*.png.
    #    No union band or per-sprite rectangular ring; internal joints are
    #    clipped to the anatomy and owned by exactly one neighbouring limb.
    # ------------------------------------------------------------------
    edge_lines = Image.new('L', (CANVAS, CANVAS), 0)
    contours = {}

    def source_row_for_screen(limb_id, screen_y):
        cx, cy, w, h = HUMAN_LAYOUT[limb_id][:4]
        cell_top = round(LIVE_CY + (round(cy - h / 2) - CENTRE) * LIVE_S)
        return max(0, min(h, int((screen_y - cell_top) / LIVE_S + 0.999999)))

    def thin_horizontal_joint(mask, contour, edge_width, from_top=False):
        """Keep only the lowest 3 source px of a long horizontal joint."""
        bounds = mask.getbbox()
        if from_top:
            rows = range(bounds[1], min(mask.height, bounds[1] + edge_width // 2 + 3))
        else:
            rows = range(max(0, bounds[3] - edge_width // 2 - 2), bounds[3])
        pixels = contour.load()
        horizontal = {}
        for yy in rows:
            runs = []
            for xx in range(mask.width):
                if pixels[xx, yy]:
                    if not runs or xx != runs[-1][1] + 1:
                        runs.append([xx, xx])
                    else:
                        runs[-1][1] = xx
            for left, right in runs:
                if right - left + 1 >= max(12, int(mask.width * 0.20)):
                    for xx in range(left, right + 1):
                        horizontal.setdefault(xx, []).append(yy)
        if from_top:
            cx, cy, w, h = HUMAN_LAYOUT['neck'][:4]
            cell_left = round(LIVE_CX + (round(cx - w / 2) - CENTRE) * LIVE_S)
        for xx, rows in horizontal.items():
            if from_top:
                screen_x = cell_left + xx * LIVE_S
                # One source-column fringe becomes the measured x=663..713
                # run after LANCZOS; the extra input column is intentional.
                if screen_x < 663 or screen_x > 714:
                    for yy in rows:
                        pixels[xx, yy] = 0
                    continue
            for yy in rows[:-HEAD_SEAM_WIDTH]:
                pixels[xx, yy] = 0

    for limb_id, mask in hard.items():
        edge_width = EDGE_WIDTH_OVERRIDES.get(limb_id, EDGE_WIDTH)
        contour = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(edge_width)))
        if limb_id not in OUTER_EDGE_EXCLUDED:
            # The reference stroke is centred on the silhouette, not clipped
            # wholly inside it.  This outer band cannot eat the black interior.
            outer = ImageChops.subtract(
                mask.filter(ImageFilter.MaxFilter(OUTER_EDGE_WIDTH)), mask)
            contour = ImageChops.lighter(contour, outer)
        # MinFilter produces a binary, stair-stepped source contour.  Keep its
        # exact measured shape/width, but add a tiny alpha fringe before GMod
        # downsamples it.  Neck is excluded because its calibrated one-row seam
        # is threshold-sensitive; the head cut and abdomen seam are authored
        # BELOW this step and retain their exact native profile.
        if limb_id != 'neck':
            contour = contour.filter(ImageFilter.GaussianBlur(EDGE_AA_RADIUS))
        if limb_id == 'head':
            # Neck owns the one-row joint at y=317; do not draw a second
            # horizontal head outline into the same pixels.
            cut_y = source_row_for_screen('head', 317)
            contour.paste(0, (0, cut_y, mask.width, mask.height))
        elif limb_id == 'neck':
            thin_horizontal_joint(mask, contour, edge_width, from_top=True)
        if limb_id == 'abdomen':
            # The native reference has one hairline across the MIDDLE of the
            # abdomen as well as its outer contour.  Clip the added line to the
            # actual silhouette; it is never a rectangular sprite-frame line.
            tx, ty, tw, th = REFERENCE_BOXES['abdomen']
            px, py = HUMAN_LAYOUT['abdomen'][4], HUMAN_LAYOUT['abdomen'][5]
            seam_y = py + round((ABDOMEN_SEAM_Y - (ty - th / 2)) / LIVE_S)
            seam = Image.new('L', mask.size, 0)
            seam_start = seam_y - ABDOMEN_SEAM_WIDTH // 2
            for yy in range(seam_start, seam_start + ABDOMEN_SEAM_WIDTH):
                if 0 <= yy < mask.height:
                    seam.paste(mask.crop((0, yy, mask.width, yy + 1)), (0, yy))
            contour = ImageChops.lighter(contour, seam)
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
        if limb_id == 'head':
            # The head interior ends immediately before the neck-owned seam.
            cut_y = source_row_for_screen('head', 317)
            soft_inner.paste(0, (0, cut_y, w, h))
        elif limb_id == 'neck':
            # Thinning the white top joint must not expose black pixels above
            # the reference seam.  The native neck interior starts at y=318.
            cut_y = source_row_for_screen('neck', 318)
            if cut_y:
                soft_inner.paste(0, (0, 0, w, cut_y))
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
             '-- Head/neck are cropped from ONE source alpha BEFORE calibration;',
             '-- neither sprite contains a second stretched copy of the full head.',
             '-- POT sprite sizes: C:U sizes limbs by mat:Width()/Height(), which GMod',
             '-- rounds to a power of two.  All 16 visible boxes + bold contours are',
             '-- calibrated against woundview_reference_1365x1079.png using the live',
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
    # with the reference-matched contour following each limb's shape.  No sprite may have a
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
    for limb_id in ('head', 'neck', 'thorax', 'hand_R', 'foot_L'):
        print('  ', limb_id, HUMAN_LAYOUT[limb_id][:4])


if __name__ == '__main__':
    main()
