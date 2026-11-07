#!/usr/bin/env python3
"""Build human C:U-style minigame hands from the bundled real hand frames.

The source frames point left and include a horizontal sleeve.  C:U instead
holds the fingertips upward with the sleeve below them.  Rotate both frames by
75 degrees clockwise, crop transparent space and place them on C:U's exact
512x1260 canvas.  No silhouette, anatomy or skin texture is synthesized.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'woundsystem_zcity_compat/materials/homigrad/handanim'
OUTPUT = ROOT / 'woundsystem_zcity_compat/materials/wszc/minigame'
CANVAS = (512, 1260)
MARGIN = 16
ROTATE = -75


def build(source_name, output_name):
    source = Image.open(SOURCE / source_name).convert('RGBA')
    rotated = source.rotate(ROTATE, Image.Resampling.BICUBIC, expand=True)
    alpha = rotated.getchannel('A').point(lambda value: 255 if value > 8 else 0)
    bbox = alpha.getbbox()
    assert bbox, source_name
    rotated = rotated.crop(bbox)

    available = (CANVAS[0] - 2 * MARGIN, CANVAS[1] - 2 * MARGIN)
    scale = min(available[0] / rotated.width, available[1] / rotated.height)
    size = (round(rotated.width * scale), round(rotated.height * scale))
    resized = rotated.resize(size, Image.Resampling.LANCZOS)

    result = Image.new('RGBA', CANVAS, (0, 0, 0, 0))
    pos = ((CANVAS[0] - size[0]) // 2, CANVAS[1] - MARGIN - size[1])
    result.alpha_composite(resized, pos)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    result.save(OUTPUT / output_name, optimize=True)
    print(output_name, 'source', source.size, 'visible', size, 'offset', pos)


def main():
    build('hand.png', 'hand_idle.png')
    build('3_3.png', 'hand_click.png')


if __name__ == '__main__':
    main()
