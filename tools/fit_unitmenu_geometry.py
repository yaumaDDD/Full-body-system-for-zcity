#!/usr/bin/env python3
"""Verify pixel-exact WoundView materials against the owner's clean 1435.png.

Default mode traces every anatomical region in
``tools/tests/woundview_reference_clean_1365x1079.png``, downsamples every
checked-in POT sprite exactly like C:U, and compares the COMPLETE black and
white masks in all 16 destination cells.  ``PIXEL_EXACT`` requires zero wrong
pixels; it is stronger than the old bbox/IoU approximation.

``--optimize`` retains the legacy archive-only coordinate fit for diagnostics
when explicitly requested.  It is not used for the shipped 1435-traced assets.

Usage:
    python3 tools/fit_unitmenu_geometry.py
    python3 tools/fit_unitmenu_geometry.py --overlay /tmp/reference-render.png
    python3 tools/fit_unitmenu_geometry.py --reference /path/2222.png --optimize

Requires Pillow.  Legacy archive layers come from ``git show origin/main:<zip>``.
"""
import argparse
import io
import os
import subprocess
import sys
import zipfile
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import build_unitmenu_materials as G  # noqa: E402

W, H = 1365, 1079
ROI = (300, 200, 1050, 900)
S, CX, CY = G.LIVE_S, G.LIVE_CX, G.LIVE_CY
# The native arms/hands are measurably asymmetric.  Fit every limb separately;
# the semi-transparent head+neck composite is contour-checked separately, not
# threshold-fitted.  Neck is a crop of that same head source, not a new shape.
ORDER = tuple(k for k in G.LIMB_LAYERS if k not in ('head', 'neck'))
SEEDS = {
    'thorax': (688, 397), 'abdomen': (687, 500),
    'arm_R': (595, 376), 'arm_L': (786, 378),
    'forearm_R': (505, 369), 'forearm_L': (870, 370),
    'hand_R': (419, 368), 'hand_L': (946, 367),
    'thigh_R': (661, 638), 'thigh_L': (714, 639),
    'crus_R': (659, 739), 'crus_L': (718, 740),
    'foot_R': (654, 812), 'foot_L': (724, 813),
}


def target_mask(path):
    src = Image.open(path).convert('RGB')
    px = src.load()
    raw = Image.new('L', (W, H), 0)
    op = raw.load()
    for y in range(ROI[1], ROI[3]):
        for x in range(ROI[0], ROI[2]):
            if max(px[x, y]) < 20:
                op[x, y] = 255
    raw = raw.filter(ImageFilter.MedianFilter(3)).crop(ROI)

    # A shelf crosses the head and several background props pass the same dark
    # threshold.  Keep only the 14 connected components seeded inside native
    # body parts.  The head's translucent material needs a different colour
    # model and is deliberately excluded from this black-mask metric.
    rp = raw.load()
    rw, rh = raw.size
    kept = set()
    for sx, sy in SEEDS.values():
        start = (sx - ROI[0], sy - ROI[1])
        if not (0 <= start[0] < rw and 0 <= start[1] < rh and rp[start]):
            raise ValueError('native reference does not match the expected body layout: %r' % (start,))
        stack = [start]
        kept.add(start)
        while stack:
            x, y = stack.pop()
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                p = (nx, ny)
                if 0 <= nx < rw and 0 <= ny < rh and rp[p] and p not in kept:
                    kept.add(p)
                    stack.append(p)
    out = Image.new('L', raw.size, 0)
    op = out.load()
    for x, y in kept:
        op[x, y] = 255
    return out


def archive_alphas():
    env = dict(os.environ, GIT_CONFIG_COUNT='1',
               GIT_CONFIG_KEY_0='core.quotepath', GIT_CONFIG_VALUE_0='false')
    raw = subprocess.check_output(
        ['git', 'show', 'origin/main:' + G.ARCHIVE_REL], cwd=ROOT, env=env)
    z = zipfile.ZipFile(io.BytesIO(raw))
    out = {}
    head_alpha = None
    for limb, layer in G.LIMB_LAYERS.items():
        src = Image.open(io.BytesIO(
            z.read(G.PREFIX + 'zcity_delta/unitmenu/limbs/' + layer + '.png')
        )).convert('RGBA')
        a = src.getchannel('A')
        bbox = a.point(lambda p: 255 if p > G.ALPHA_THRESHOLD else 0).getbbox()
        if limb == 'head':
            head_alpha = a.crop(bbox)
            split = round(head_alpha.height * G.HEAD_SPLIT_FRAC)
            out[limb] = head_alpha.crop((0, 0, head_alpha.width, split))
        elif limb != 'neck':
            out[limb] = a.crop(bbox)
    out['neck'] = head_alpha.crop((0, split, head_alpha.width, head_alpha.height))
    return out


def layout_for(boxes):
    out = {}
    for k, (tx, ty, tw, th) in boxes.items():
        cx = G.CENTRE + (tx - CX) / S
        cy = G.CENTRE + (ty - CY) / S
        iw, ih = int(round(tw / S)), int(round(th / S))
        w = G.next_pot(iw + 2 * G.EDGE_PAD_MIN + G.ERODE_MARGIN)
        h = G.next_pot(ih + 2 * G.EDGE_PAD_MIN + G.ERODE_MARGIN)
        px, py = (w - iw) // 2, (h - ih) // 2
        if px < G.EDGE_PAD_MIN or py < G.EDGE_PAD_MIN:
            return None
        out[k] = (round(cx, 1), round(cy, 1), w, h, px, py, iw, ih)
    return out


def render(boxes, alphas, include_head=True):
    """Black fill mask in screen space, exactly what C:U will draw."""
    lay = layout_for(boxes)
    if lay is None:
        return None
    canvas = Image.new('L', (W, H), 0)
    white = {}
    for limb, authored in lay.items():
        if limb in ('head', 'neck') and not include_head:
            continue
        cx, cy, w, h, px, py, iw, ih = authored
        scaled = alphas[limb].resize((iw, ih), Image.Resampling.LANCZOS)
        cell = Image.new('L', (w, h), 0)
        cell.paste(scaled, (px, py))
        hard = cell.point(lambda p: 255 if p > G.ALPHA_THRESHOLD else 0)
        soft_inner = cell.filter(ImageFilter.MinFilter(G.JOINT_ERODE))
        edge_width = G.EDGE_WIDTH_OVERRIDES.get(limb, G.EDGE_WIDTH)
        contour = ImageChops.subtract(
            hard, hard.filter(ImageFilter.MinFilter(edge_width)))
        if limb not in G.OUTER_EDGE_EXCLUDED:
            outer = ImageChops.subtract(
                hard.filter(ImageFilter.MaxFilter(G.OUTER_EDGE_WIDTH)), hard)
            contour = ImageChops.lighter(contour, outer)
        if limb != 'neck':
            contour = contour.filter(ImageFilter.GaussianBlur(G.EDGE_AA_RADIUS))
        if limb == 'abdomen':
            tx, ty, tw, th = boxes['abdomen']
            seam_y = py + round((G.ABDOMEN_SEAM_Y - (ty - th / 2)) / S)
            seam = Image.new('L', (w, h), 0)
            seam_start = seam_y - G.ABDOMEN_SEAM_WIDTH // 2
            for yy in range(seam_start, seam_start + G.ABDOMEN_SEAM_WIDTH):
                if 0 <= yy < h:
                    seam.paste(hard.crop((0, yy, w, yy + 1)), (0, yy))
            contour = ImageChops.lighter(contour, seam)
        # C:U draws the white edge AFTER the fill.  The fitting metric must
        # subtract that contour instead of scoring the old fill-only mask.
        visible_black = ImageChops.subtract(soft_inner, contour)
        sw, sh = max(1, round(w * S)), max(1, round(h * S))
        visible_black = visible_black.resize((sw, sh), Image.Resampling.LANCZOS).point(
            lambda p: 255 if p > G.ALPHA_THRESHOLD else 0)
        left = round(CX + (round(cx - w / 2) - G.CENTRE) * S)
        top = round(CY + (round(cy - h / 2) - G.CENTRE) * S)
        if (sw, sh) not in white:
            white[(sw, sh)] = Image.new('L', (sw, sh), 255)
        canvas.paste(white[(sw, sh)], (left, top), visible_black)
    return canvas.crop(ROI)


def iou(img, target_bytes, target_n):
    a, b = img.tobytes(), target_bytes
    inter = n = 0
    for x, y in zip(a, b):
        if x:
            n += 1
            if y:
                inter += 1
    return inter / (n + target_n - inter) if (n + target_n - inter) else 0.0


def unpack(base):
    return [[float(x) for x in base[k]] for k in ORDER]


def repack(v, base):
    boxes = {k: tuple(p) for k, p in base.items()}
    for k, p in zip(ORDER, v):
        boxes[k] = tuple(p)
    return boxes


def optimize(base, alphas, target_bytes, target_n, sweeps=5):
    v0 = unpack(base)
    cur = [p[:] for p in v0]

    def score(v):
        img = render(repack(v, base), alphas, include_head=False)
        if img is None:
            return -1.0
        penalty = sum(abs(p[i] - q[i]) for p, q in zip(v, v0) for i in range(4))
        return iou(img, target_bytes, target_n) - 0.00006 * penalty

    best = score(cur)
    steps = {0: (-10, -6, -3, -1, 1, 3, 6, 10),
             1: (-8, -5, -3, -1, 1, 3, 5, 8),
             2: (-9, -5, -2, 2, 5, 9),
             3: (-10, -6, -3, -1, 1, 3, 6, 10)}
    for sweep in range(sweeps):
        improved = False
        for j in range(len(cur)):
            for i in range(4):
                for d in steps[i]:
                    trial = [p[:] for p in cur]
                    trial[j][i] += d
                    if i in (2, 3) and not (0.72 * v0[j][i] <= trial[j][i] <= 1.35 * v0[j][i]):
                        continue
                    if i == 0 and abs(trial[j][0] - v0[j][0]) > 14:
                        continue
                    if i == 1 and abs(trial[j][1] - v0[j][1]) > 12:
                        continue
                    s = score(trial)
                    if s > best + 1e-7:
                        best, cur, improved = s, trial, True
        print('  sweep %d: penalised %.5f' % (sweep, best))
        if not improved:
            break
    return repack(cur, base)


def overlay(img, target, path):
    a = img.point(lambda p: 255 if p > 128 else 0).load()
    b = target.load()
    out = Image.new('RGB', target.size, (0, 0, 0))
    o = out.load()
    for y in range(target.size[1]):
        for x in range(target.size[0]):
            has_a, has_b = a[x, y] > 0, b[x, y] > 0
            if has_a and has_b:
                o[x, y] = (255, 255, 80)
            elif has_b:
                o[x, y] = (255, 60, 60)
            elif has_a:
                o[x, y] = (60, 255, 60)
    out.save(path)
    print('overlay ->', path, '(yellow = match, red = reference only, green = ours only)')


def traced_roundtrip(reference_path, overlay_path=None):
    """Validate the shipped reference-traced textures, not an archive guess."""
    reference = Image.open(reference_path).convert('RGB')
    traced = G.trace_reference_masks(reference)
    limb_dir = ROOT / 'woundsystem_zcity_compat/materials/wszc/unitmenu/limbs'
    preview = Image.new('RGB', reference.size, (10, 30, 20))
    mismatch = 0
    for limb in G.LIMB_LAYERS:
        left, top, sw, sh = G.reference_screen_cell(limb)
        box = (left, top, left + sw, top + sh)
        fill = Image.open(limb_dir / (limb + '_fill.png')).convert('RGBA').getchannel('A').resize(
            (sw, sh), Image.Resampling.LANCZOS)
        edge = Image.open(limb_dir / (limb + '_edge.png')).convert('RGBA').getchannel('A').resize(
            (sw, sh), Image.Resampling.LANCZOS)
        black = ImageChops.subtract(
            fill.point(lambda p: 255 if p > G.ALPHA_THRESHOLD else 0),
            edge.point(lambda p: 255 if p > G.ALPHA_THRESHOLD else 0))
        white = edge.point(lambda p: 255 if p > 180 else 0)
        target_black = traced[limb]['black'].crop(box)
        target_white = traced[limb]['edge'].crop(box).point(lambda p: 255 if p > 180 else 0)
        mismatch += sum(a != b for a, b in zip(black.tobytes(), target_black.tobytes()))
        mismatch += sum(a != b for a, b in zip(white.tobytes(), target_white.tobytes()))
        preview.paste(Image.new('RGB', (sw, sh), (0, 0, 0)), (left, top), fill)
        preview.paste(Image.new('RGB', (sw, sh), (255, 255, 255)), (left, top), edge)
    if overlay_path:
        preview.save(overlay_path)
        print('reference render ->', overlay_path)
    return mismatch


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--reference', default=str(G.REFERENCE_CLEAN))
    ap.add_argument('--optimize', action='store_true',
                    help='legacy archive-only fit; not used for the pixel-traced 1435 materials')
    ap.add_argument('--overlay')
    args = ap.parse_args()

    if not args.optimize:
        mismatch = traced_roundtrip(args.reference, args.overlay)
        print('clean-reference full-cell black/white mismatches: %d' % mismatch)
        print('PIXEL_EXACT' if mismatch == 0 else 'PIXEL_MISMATCH')
        raise SystemExit(0 if mismatch == 0 else 1)

    base = {k: tuple(v) for k, v in G.REFERENCE_BOXES.items()}
    alphas = archive_alphas()
    target = target_mask(args.reference)
    tb, tn = target.tobytes(), sum(1 for x in target.tobytes() if x)
    img = render(base, alphas, include_head=False)
    print('reference doll pixels: %d' % tn)
    print('IoU (checked-in geometry, 14 black-mask body parts): %.4f' % iou(img, tb, tn))
    if args.optimize:
        fitted = optimize(base, alphas, tb, tn)
        img = render(fitted, alphas, include_head=False)
        print('IoU (fitted): %.4f' % iou(img, tb, tn))
        for k in G.LIMB_LAYERS:
            print('    %-11s (%.1f, %.1f, %d, %d),' % (k, *fitted[k]))
    if args.overlay:
        overlay(img, target, args.overlay)


if __name__ == '__main__':
    main()
