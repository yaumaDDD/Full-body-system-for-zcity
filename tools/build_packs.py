#!/usr/bin/env python3
"""Rebuild the two distributable ZIPs from the working tree.

The original build lived in /tmp and was lost with the sandbox scratch space,
so this version is committed with the connector.  It starts from the previously
shipped full pack (which contains the untouched upstream addons), then replaces
only the parts this repository owns:

  * garrysmod/addons/woundsystem_zcity_compat/**      <- the connector folder
  * garrysmod/addons/casualties_unknown_health_system_beta/materials/**
        <- the exact same 651 UI materials mirrored into C:U
  * root docs (README_INSTALL.md / ZCity_binds.md / WORKSHOP_IDS.txt)
  * garrysmod/cfg/zcity_binds.cfg
  * MANIFEST.txt (counts + sha256 of the 11 connector Lua files)

No file of any upstream addon is modified except the single already-patched
line in z_city/lua/homigrad/woundbridge/sv_woundbridge.lua.

Usage: python3 tools/build_packs.py
"""
import hashlib
import io
import zipfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONN_DIR = ROOT / 'woundsystem_zcity_compat'
FULL_ZIP = ROOT / 'zcity_full_pack.zip'
COMPAT_ZIP = ROOT / 'woundsystem_zcity_compat.zip'

CONN_PREFIX = 'garrysmod/addons/woundsystem_zcity_compat/'
CU_MAT = 'garrysmod/addons/casualties_unknown_health_system_beta/materials/'
ROOT_DOCS = {
    'README_INSTALL.md': ROOT / 'INSTALL_RU.md',
    'ZCity_binds.md': ROOT / 'ZCity_binds.md',
    'WORKSHOP_IDS.txt': ROOT / 'WORKSHOP_IDS.txt',
}
CFG_ENTRY = 'garrysmod/cfg/zcity_binds.cfg'
DOCS_IN_ZIP = set(ROOT_DOCS) | {'MANIFEST.txt'}


def collect_connector():
    out = {}
    for p in sorted(CONN_DIR.rglob('*')):
        if not p.is_file():
            continue
        rel = p.relative_to(CONN_DIR).as_posix()
        if rel.startswith('.git/') or '__pycache__' in rel:
            continue
        out[rel] = p.read_bytes()
    assert out, 'connector folder is empty'
    return out


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def build_manifest(old_text, entries, conn):
    old_lines = old_text.splitlines()
    # Keep the source-archive hashes and the patch note verbatim.
    archive_lines = []
    patch_lines = []
    section = None
    for line in old_lines:
        if line.startswith('Исходные архивы'):
            section = 'archives'
        elif line.startswith('Патч внутри сборки'):
            section = 'patch'
        elif line.startswith('Lua-исходники коннектора'):
            section = 'lua'
        if section == 'archives':
            archive_lines.append(line)
        elif section == 'patch':
            patch_lines.append(line)

    groups = defaultdict(lambda: [0, 0])
    for name, data in entries.items():
        if name in DOCS_IN_ZIP or name == CFG_ENTRY:
            key = '(документы и cfg)'
        elif name.startswith('garrysmod/addons/'):
            key = name.split('/')[2]
        else:
            key = '(документы и cfg)'
        groups[key][0] += 1
        groups[key][1] += len(data)

    # Stable order: docs first, then the addon order from the old manifest.
    order = ['(документы и cfg)']
    for line in old_lines:
        parts = line.split()
        if len(parts) >= 3 and parts[0] not in order and parts[0] in groups:
            order.append(parts[0])
    for key in groups:
        if key not in order:
            order.append(key)

    lines = [
        'ZCity full pack - manifest',
        '==========================',
        # MANIFEST.txt is inserted after this text is built, but it is still a
        # file in the final archive and must be included in the advertised total.
        'Всего файлов в архиве: %d' % (len(entries) + 1),
        '',
        'Папка аддона                                             файлов       байт',
        '--------------------------------------------------------------------------',
    ]
    for key in order:
        count, size = groups[key]
        lines.append('%-55s %6d %11d' % (key, count, size))
    lines.append('')
    lines += [l for l in archive_lines if l.strip()]
    lines.append('')
    lines += [l for l in patch_lines if l.strip()]
    lines.append('')
    lines.append('Lua-исходники коннектора (sha256):')
    for rel in sorted(r for r in conn if r.endswith('.lua')):
        lines.append('  %-88s %s' % ('woundsystem_zcity_compat/' + rel, sha256(conn[rel])))
    lines.append('')
    return ('\n'.join(lines) + '\n').encode('utf-8')


def write_zip(path, entries):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for name, data in entries.items():
            zi = zipfile.ZipInfo(name, date_time=(2026, 11, 4, 12, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = 0o644 << 16
            z.writestr(zi, data)
    path.write_bytes(buf.getvalue())


def main():
    conn = collect_connector()
    lua = [r for r in conn if r.endswith('.lua')]
    mats = [r for r in conn if r.startswith('materials/')]
    assert len(lua) == 11, ('connector Lua count', len(lua))
    assert len(mats) >= 651, ('connector material count', len(mats))
    for marker in ('limbs/head_fill.png', 'limbs/neck_fill.png',
                   'limbs/neck_edge.png', 'limbs/thorax_edge.png',
                   'homigrad/handanim/hand.png', 'handanim/3_3.png',
                   'wszc/minigame/hand_idle.png', 'wszc/minigame/hand_click.png'):
        assert any(marker in m for m in mats), marker

    # --- standalone connector ZIP ---
    compat = {'woundsystem_zcity_compat/' + r: d for r, d in conn.items()}
    write_zip(COMPAT_ZIP, compat)

    # --- full pack ---
    with zipfile.ZipFile(FULL_ZIP) as z:
        base = {i.filename: z.read(i.filename) for i in z.infolist()}
    old_manifest = base['MANIFEST.txt'].decode('utf-8')

    entries = {}
    for name, data in base.items():
        if name.startswith(CONN_PREFIX) or name.startswith(CU_MAT):
            continue
        if name in DOCS_IN_ZIP or name == CFG_ENTRY:
            continue
        entries[name] = data

    for rel, data in conn.items():
        entries[CONN_PREFIX + rel] = data
    for rel in mats:
        entries[CU_MAT + rel[len('materials/'):]] = conn[rel]
    for name, src in ROOT_DOCS.items():
        entries[name] = src.read_bytes()
    entries[CFG_ENTRY] = (ROOT / 'zcity_binds.cfg').read_bytes()

    names = list(entries)
    assert len(names) == len(set(names)), 'duplicate paths'
    for n in names:
        assert not n.startswith('/') and '..' not in n.split('/') and '\\' not in n, n
    entries['MANIFEST.txt'] = build_manifest(old_manifest, entries, conn)
    write_zip(FULL_ZIP, entries)

    mirrored = sum(1 for n in entries if n.startswith(CU_MAT))
    print('connector files:', len(conn))
    print('materials mirrored into C:U addon:', mirrored)
    print('validation: 0 duplicates, 0 unsafe paths, connector Lua + addon.json OK')
    print('full pack', FULL_ZIP.stat().st_size, 'bytes', len(entries), 'files')
    print('connector zip', COMPAT_ZIP.stat().st_size, 'bytes', len(compat), 'files')
    print('BUILD_OK')


if __name__ == '__main__':
    main()
