#!/usr/bin/env python3
"""Make the connector addon self-contained: bundle EVERY UI material it needs.

Sources (both live in origin/main of this repository):

  1. "для переделывания интерфейса.zip"
       human_hands.../materials/<rel>           -> materials/<rel>
       (unitmenu limbs, status icons, handanim frames, moodles, traits...)

  2. "для того чтобы все работало вместе материалы для UI.zip"
       для того чтобы.../<rel>                  -> materials/<rel>
       (the FULL casunknown-images/* + woundsystem/* set that the stock
        casualties_unknown_health_system_beta addon is missing: middle/ and
        outlines/ limb sprites incl. _padded, icons, screen, minigames,
        moodles, items, .vtf/.vmt overlays)

The stock "casualites unknown.zip" contains Lua ONLY - no materials at all.
That is why WoundView, the scanner, item icons and minigames rendered as
ERROR textures and had to be copied in by hand.  This script puts all of them
inside the connector addon, then resolves every material path referenced by
C:U / WSZC Lua:

  * exact-case aliases for the 25 camelCase names (the archive is lowercase;
    Windows is case-insensitive, Linux clients are NOT);
  * aliases for hand / board sprites that C:U requests from the dislocation,
    shrapnel and syringe folders while the archive keeps them only under
    bandageminigame/;
  * a "_red" blood variant alias for hemothoraxfill.

Finally it asserts that NO referenced UI material is missing, so a future
archive change cannot silently reintroduce ERROR textures.

The 14 loose "(...)" PNGs at the root of archive 2 are byte-identical
duplicates of files already under casunknown-images/bandageminigame/ and are
deliberately skipped.

Usage: python3 tools/pack_ui_materials.py [ui.zip [ui_materials.zip]]
"""
import hashlib
import io
import os
import re
import subprocess
import sys
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'woundsystem_zcity_compat' / 'materials'
ARCHIVE_1 = 'для переделывания интерфейса.zip'
ARCHIVE_2 = 'для того чтобы все работало вместе материалы для UI.zip'
PREFIX_1 = 'human_hands_for_z_city_casualties_medical_system_heavy_wip/materials/'
PREFIX_2 = 'для того чтобы все работало вместе материалы для UI/'
LOOSE_DIR = 'casunknown-images/bandageminigame/'
KNOWN_PREFIXES = ('casunknown-images', 'woundsystem', 'homigrad',
                  'zcity_delta', 'zcity_delta_moodles', 'traits', 'smiley', 'wszc')
ASSET_EXT = ('.png', '.jpg', '.vtf', '.vmt')


def git_show(rel):
    env = dict(os.environ, GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.quotepath',
               GIT_CONFIG_VALUE_0='false')
    return subprocess.check_output(['git', 'show', 'origin/main:' + rel], cwd=ROOT, env=env)


def safe(rel):
    parts = rel.split('/')
    return (rel and not rel.startswith('/') and '..' not in parts
            and '\\' not in rel and not any(p.startswith('.') for p in parts if p))


def collect_lua_sources():
    """All Lua text that can reference a UI material."""
    texts = []
    cu = ROOT / 'casualites unknown.zip'
    with zipfile.ZipFile(cu) as z:
        for n in z.namelist():
            if n.endswith('.lua'):
                texts.append(('C:U ' + n, z.read(n).decode('utf-8', 'ignore')))
    for p in sorted((ROOT / 'woundsystem_zcity_compat' / 'lua').rglob('*.lua')):
        texts.append((p.name, p.read_text(encoding='utf-8')))
    return texts


def referenced_paths(texts):
    refs = defaultdict(list)
    for label, text in texts:
        prefixes = {m.group(1): m.group(2)
                    for m in re.finditer(r'local\s+(\w*[Pp]ath\w*)\s*=\s*"([^"]+)"', text)}
        pat = r'"((?:%s)/[^"]+\.(?:png|jpg|vtf|vmt))"' % '|'.join(KNOWN_PREFIXES)
        for m in re.finditer(pat, text):
            refs[m.group(1)].append(label)
        for m in re.finditer(r'(\w*[Pp]ath\w*)\s*\.\.\s*"([^"]+\.(?:png|jpg|vtf|vmt))"', text):
            if m.group(1) in prefixes:
                refs[prefixes[m.group(1)] + m.group(2)].append(label)
    return refs


def main():
    args = sys.argv[1:]
    data1 = Path(args[0]).read_bytes() if len(args) > 0 else git_show(ARCHIVE_1)
    data2 = Path(args[1]).read_bytes() if len(args) > 1 else git_show(ARCHIVE_2)

    # Build the CURRENT 17-part doll before the copy/coverage pass.  Otherwise
    # this script restored the old 15-part head whenever it was rerun after a
    # standalone neck/pelvis build, making the result depend on command order.
    doll_cmd = [sys.executable, str(ROOT / 'tools/build_unitmenu_materials.py')]
    if args:
        doll_cmd.append(str(Path(args[0]).resolve()))
    subprocess.run(doll_cmd, cwd=ROOT, check=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/build_minigame_hand.py')],
                   cwd=ROOT, check=True)

    entries = {}
    sources = Counter()

    z1 = zipfile.ZipFile(io.BytesIO(data1))
    for n in z1.namelist():
        if not n.startswith(PREFIX_1) or n.endswith('/'):
            continue
        rel = n[len(PREFIX_1):]
        assert safe(rel), n
        entries[rel] = z1.read(n)
        sources['archive1'] += 1

    z2 = zipfile.ZipFile(io.BytesIO(data2))
    loose = []
    for n in z2.namelist():
        if n.endswith('/'):
            continue
        if not n.startswith(PREFIX_2):
            loose.append(n)
            continue
        rel = n[len(PREFIX_2):]
        assert safe(rel), n
        if rel in entries and entries[rel] != z2.read(n):
            raise SystemExit('conflicting duplicate: ' + rel)
        entries[rel] = z2.read(n)
        sources['archive2'] += 1

    # The loose root PNGs must be exact duplicates of bandageminigame files.
    for n in loose:
        d = z2.read(n)
        clean = re.sub(r' \(\d+\)', '', n)
        twin = LOOSE_DIR + clean
        if entries.get(twin) != d:
            raise SystemExit('loose file is not a known duplicate: ' + n)
    print('archives:', len(entries), 'files', dict(sources),
          '| skipped duplicate loose PNGs:', len(loose))

    # Preserve the native bandaged-fracture silhouette but invert black/white:
    # a black symbol with a white outline remains legible on the dark doll.
    from PIL import Image
    with Image.open(io.BytesIO(entries['casunknown-images/icons/splinticon.png'])) as im:
        im = im.convert('RGBA')
        im.putdata([(255-r, 255-g, 255-b, a) if a else (0, 0, 0, 0)
                    for r, g, b, a in im.getdata()])
        out = OUT / 'wszc/unitmenu/status/fracture_bandaged.png'
        out.parent.mkdir(parents=True, exist_ok=True)
        im.save(out)

    # Generated WSZC art already exists on disk but is deliberately NOT part of
    # the two source archives (or their 614-entry checksum manifest).
    generated = {
        p.relative_to(OUT).as_posix(): p.read_bytes()
        for folder in ('wszc/unitmenu', 'wszc/minigame')
        for p in (OUT / folder).rglob('*') if p.is_file()
    }
    assert len(generated) == 40, ('34 limb + 4 status + 2 hand PNGs', len(generated))

    # ------------------------------------------------------------------ aliases
    refs = referenced_paths(collect_lua_sources())
    by_lower = {r.lower(): r for r in entries}
    by_basename = defaultdict(list)
    for r in entries:
        by_basename[os.path.basename(r).lower()].append(r)

    aliases = {}
    unresolved = []
    for wanted in sorted(refs):
        if wanted in entries or wanted in generated:
            continue
        cand = by_lower.get(wanted.lower())
        if cand is None:
            base = os.path.basename(wanted)
            same = by_basename.get(base.lower())
            if same:
                cand = same[0]
            elif base.lower().endswith('_red.png'):
                cand = by_basename.get(base.lower().replace('_red.png', '.png'), [None])[0]
            elif base.lower().endswith('_red_padded.png'):
                cand = by_basename.get(base.lower().replace('_red_padded.png', '_padded.png'), [None])[0]
        if cand is None:
            unresolved.append(wanted)
            continue
        aliases[wanted] = entries[cand]

    if unresolved:
        for r in unresolved:
            print('UNRESOLVED', r, refs[r][:2])
        raise SystemExit('%d material paths cannot be resolved' % len(unresolved))
    entries.update(aliases)
    print('resolved aliases:', len(aliases),
          '(', sum(1 for a in aliases if a.lower() in by_lower), 'case-only,',
          sum(1 for a in aliases if a.lower() not in by_lower), 'relocated/red )')

    # Every reference is now present.  C:U's PaddedMaterial() also probes
    # "<name>_padded.png"; the 18 native limb sprites must have it.
    for folder, suffix in (('middle', 'middle'), ('outlines', 'outline')):
        for part in ('foot', 'crus', 'thigh', 'abdomen', 'thorax', 'arm',
                     'forearm', 'hand', 'head'):
            base = 'casunknown-images/%s/%s%s.png' % (folder, part, suffix)
            padded = base.replace('.png', '_padded.png')
            assert base in entries and padded in entries, base

    # Antiseptic spray and syringe-puncture icons are removed by owner request.
    # Keep valid 4x4 fully transparent PNGs at those exact paths so VFS overrides
    # external Workshop C:U assets without triggering Source missing-texture errors.
    removed_status_icons = (
        'casunknown-images/icons/disinfected.png',
        'casunknown-images/icons/disinfected_padded.png',
        'casunknown-images/icons/injectionwound.png',
        'casunknown-images/icons/injectionwound_padded.png',
        'casunknown-images/icons/injectionwound_red.png',
        'casunknown-images/icons/injectionwound_padded_red.png',
    )
    import struct, zlib
    def _png_chunk(tag, payload):
        return (struct.pack('>I', len(payload)) + tag + payload
                + struct.pack('>I', zlib.crc32(tag + payload) & 0xffffffff))
    raw_rows = b''.join(b'\x00' + (b'\x00\x00\x00\x00' * 4) for _ in range(4))
    transparent_png = (
        b'\x89PNG\r\n\x1a\n'
        + _png_chunk(b'IHDR', struct.pack('>IIBBBBB', 4, 4, 8, 6, 0, 0, 0))
        + _png_chunk(b'IDAT', zlib.compress(raw_rows, 9))
        + _png_chunk(b'IEND', b'')
    )
    for rel in removed_status_icons:
        entries[rel] = transparent_png

    for rel, data in entries.items():
        assert data, rel
        if rel.endswith('.png'):
            assert data[:8] == b'\x89PNG\r\n\x1a\n', rel
        p = OUT / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        if not p.exists() or p.read_bytes() != data:
            p.write_bytes(data)

    exts = Counter(os.path.splitext(r)[1].lower() for r in entries)
    print('packed', len(entries), 'materials', dict(exts))
    actual_materials = [p for p in OUT.rglob('*') if p.is_file()]
    limb_pngs = [p for p in (OUT / 'wszc/unitmenu/limbs').glob('*.png')]
    assert len(actual_materials) == 654, ('complete material count', len(actual_materials))
    assert len(limb_pngs) == 34, ('17 fill + 17 edge sprites', len(limb_pngs))
    print('ALL_LUA_UI_MATERIALS_RESOLVED', len(refs), 'referenced paths')

    lines = ['# UI materials bundled into woundsystem_zcity_compat/materials/',
             '# Generated by tools/pack_ui_materials.py - do not edit by hand.',
             '# Sources: origin/main:для переделывания интерфейса.zip',
             '#          origin/main:' + ARCHIVE_2,
             '# Aliases resolve exact-case / relocated names referenced by C:U Lua.', '']
    for rel in sorted(entries):
        lines.append('%s  %s' % (hashlib.sha256(entries[rel]).hexdigest()[:16], rel))
    (ROOT / 'woundsystem_zcity_compat' / 'MATERIALS.sha256').write_text(
        '\n'.join(lines) + '\n', encoding='utf-8')
    print('MATERIALS.sha256 written with', len(entries), 'entries')


if __name__ == '__main__':
    main()
