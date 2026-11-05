#!/usr/bin/env python3
"""Pixel-fit the WoundView doll against the owner's native reference screenshot.

The owner's standing requirement is "бля ну одинаково делай по размерам как на
том скриншоте" while keeping OUR styling (pure black anatomy + a thin outline
that follows each limb's own shape).  This tool makes that measurable instead
of eyeballed:

  1. build a target mask from Screenshot_1.png.  The doll is true black
     (RGB 0..8) while the woven room background is RGB 30..80, so
     ``max(RGB) < 20`` isolates the doll without touching it;
  2. render the 15 VERBATIM archive silhouettes into SCREEN space using the
     exact same linear placement C:U uses (S=0.4155, centre=(682.5,558.2),
     mat:Width()/Height() are the POT sprite sizes);
  3. report intersection-over-union, and optionally run a bounded coordinate
     descent over the REFERENCE_BOXES numbers (tx, ty, w, h).  Every limb is
     independent (native arms are asymmetric), widths/heights stay within
     +/-35% of the checked-in values, and NOT ONE silhouette pixel is redrawn.
     The translucent head is excluded from the black-mask metric.

Only the four numbers per limb ever change: position and proportion, never
shape, colour, outline or T-pose.

Usage:
    python3 tools/fit_unitmenu_geometry.py --reference /path/Screenshot_1.png
    python3 tools/fit_unitmenu_geometry.py --reference ... --optimize
    python3 tools/fit_unitmenu_geometry.py --reference ... --overlay /tmp/overlay.png

Requires Pillow.  The archive layers come from ``git show origin/main:<zip>``,
exactly like tools/build_unitmenu_materials.py.
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
# the semi-transparent head is contour-checked separately, not threshold-fitted.
ORDER = tuple(k for k in G.LIMB_LAYERS if k != 'head')
SEEDS = {
    'thorax': (682, 400), 'abdomen': (682, 500),
    'arm_R': (580, 350), 'arm_L': (780, 350),
    'forearm_R': (480, 350), 'forearm_L': (880, 360),
    'hand_R': (390, 350), 'hand_L': (950, 350),
    'thigh_R': (650, 650), 'thigh_L': (710, 650),
    'crus_R': (650, 750), 'crus_L': (715, 750),
    'foot_R': (645, 845), 'foot_L': (720, 845),
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
    for limb, layer in G.LIMB_LAYERS.items():
        src = Image.open(io.BytesIO(
            z.read(G.PREFIX + 'zcity_delta/unitmenu/limbs/' + layer + '.png')
        )).convert('RGBA')
        a = src.getchannel('A')
        bbox = a.point(lambda p: 255 if p > G.ALPHA_THRESHOLD else 0).getbbox()
        out[limb] = a.crop(bbox)
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
    for limb, (cx, cy, w, h, px, py, iw, ih) in lay.items():
        if limb == 'head' and not include_head:
            continue
        scaled = alphas[limb].resize((iw, ih), Image.Resampling.LANCZOS)
        if limb.startswith('foot_'):
            scaled = G.SquareToe(scaled)   # Screenshot_8 flat sole, unchanged
        cell = Image.new('L', (w, h), 0)
        cell.paste(scaled, (px, py))
        hard = cell.point(lambda p: 255 if p > G.ALPHA_THRESHOLD else 0)
        hard = hard.filter(ImageFilter.MinFilter(G.JOINT_ERODE))
        sw, sh = max(1, round(w * S)), max(1, round(h * S))
        hard = hard.resize((sw, sh), Image.Resampling.LANCZOS).point(
            lambda p: 255 if p > 128 else 0)
        left = round(CX + (round(cx - w / 2) - G.CENTRE) * S)
        top = round(CY + (round(cy - h / 2) - G.CENTRE) * S)
        if (sw, sh) not in white:
            white[(sw, sh)] = Image.new('L', (sw, sh), 255)
        canvas.paste(white[(sw, sh)], (left, top), hard)
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--reference', default='/tmp/arena-coding-uploads/Screenshot_1.png')
    ap.add_argument('--optimize', action='store_true')
    ap.add_argument('--overlay')
    args = ap.parse_args()

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
