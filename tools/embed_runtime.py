#!/usr/bin/env python3
"""Vendor the supplied C:U and ZCity WoundBridge into the portable connector.

The embedded files use an isolated Lua namespace.  Only quoted *.lua paths and
C:U's medical_tools include directory are rewritten; data/sound paths such as
woundsystem/persist and woundsystem/*.ogg intentionally stay untouched.

Usage:
    python3 tools/embed_runtime.py           # regenerate
    python3 tools/embed_runtime.py --check   # verify without writing
"""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent
CONN = ROOT / "woundsystem_zcity_compat"
CU_ZIP = ROOT / "casualites unknown.zip"
ZCITY_ZIP = ROOT / "zcity.zip"
CU_SOURCE_PREFIX = "casualties_unknown_health_system_beta/lua/"
CU_DEST = CONN / "lua/wszc_vendor/cu"
BRIDGE_SOURCE_PREFIX = "z_city/lua/homigrad/woundbridge/"
BRIDGE_DEST = CONN / "lua/wszc_vendor/zcity/woundbridge"
VENDOR_LUA_PREFIX = b"wszc_vendor/cu/woundsystem/"
MANIFEST = CONN / "VENDOR_RUNTIME.sha256"
LUA_PATH = re.compile(rb"(['\"])woundsystem/([^'\"]+?\.lua)\1")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def transform_cu(data: bytes) -> bytes:
    data = LUA_PATH.sub(
        lambda match: match.group(1) + VENDOR_LUA_PREFIX
        + match.group(2) + match.group(1),
        data,
    )
    for quote in (b'"', b"'"):
        data = data.replace(
            quote + b"woundsystem/medical_tools" + quote,
            quote + b"wszc_vendor/cu/woundsystem/medical_tools" + quote,
        )
    return data


def collect() -> tuple[dict[str, bytes], list[tuple[str, str, str]]]:
    files: dict[str, bytes] = {}
    provenance: list[tuple[str, str, str]] = []
    with ZipFile(CU_ZIP) as source:
        names = sorted(
            name for name in source.namelist()
            if name.startswith(CU_SOURCE_PREFIX) and name.endswith(".lua")
        )
        assert len(names) == 71, ("C:U Lua count", len(names))
        for name in names:
            rel = name[len(CU_SOURCE_PREFIX):]
            original = source.read(name)
            transformed = transform_cu(original)
            if rel == "autorun/sh_health_init.lua":
                # AddCSLuaFile may execute this loader automatically before the
                # client bootstrap includes it.  Never run the embedded loader
                # twice; the external C:U loader is not modified.
                transformed = (
                    b"if WoundSystem and WoundSystem._WSZCEmbeddedLoaderRan then return end\n"
                    b"WoundSystem = WoundSystem or {}\n"
                    b"WoundSystem._WSZCEmbeddedLoaderRan = true\n"
                    b"WoundSystem._WSZCEmbedded = true\n\n"
                ) + transformed
            files[(CU_DEST / rel).relative_to(CONN).as_posix()] = transformed
            provenance.append((name, sha(original), sha(transformed)))
    with ZipFile(ZCITY_ZIP) as source:
        names = sorted(
            name for name in source.namelist()
            if name.startswith(BRIDGE_SOURCE_PREFIX) and name.endswith(".lua")
        )
        assert len(names) == 3, ("WoundBridge Lua count", len(names))
        for name in names:
            rel = name[len(BRIDGE_SOURCE_PREFIX):]
            original = source.read(name)
            files[(BRIDGE_DEST / rel).relative_to(CONN).as_posix()] = original
            provenance.append((name, sha(original), sha(original)))
    return files, provenance


def manifest_text(provenance: list[tuple[str, str, str]]) -> str:
    lines = [
        "# Embedded runtime provenance; regenerate with tools/embed_runtime.py",
        "# source_zip_sha256  source_path  source_lua_sha256  vendored_lua_sha256",
        f"{sha(CU_ZIP.read_bytes())}  casualites unknown.zip",
        f"{sha(ZCITY_ZIP.read_bytes())}  zcity.zip",
    ]
    lines.extend(f"{source_sha}  {vendored_sha}  {name}" for name, source_sha, vendored_sha in provenance)
    return "\n".join(lines) + "\n"


def main() -> None:
    check = sys.argv[1:] == ["--check"]
    if not check and sys.argv[1:]:
        raise SystemExit("usage: embed_runtime.py [--check]")
    files, provenance = collect()
    expected = dict(files)
    expected[MANIFEST.relative_to(CONN).as_posix()] = manifest_text(provenance).encode("utf-8")
    stale = []
    for rel, data in expected.items():
        path = CONN / rel
        if not path.is_file() or path.read_bytes() != data:
            stale.append(rel)
    # Extra source files in the generated trees almost always mean a stale
    # vendor generation; the hand-written bootstrap lives one level above cu/.
    actual_generated = {
        path.relative_to(CONN).as_posix()
        for base in (CU_DEST, BRIDGE_DEST)
        for path in base.rglob("*.lua")
    }
    extras = sorted(actual_generated - set(files))
    if check:
        if stale or extras:
            print("STALE", *stale, sep="\n")
            print("EXTRA", *extras, sep="\n")
            raise SystemExit(1)
        print(f"EMBEDDED_RUNTIME_OK cu=71 bridge=3 manifest={len(provenance)}")
        return
    for rel, data in expected.items():
        path = CONN / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    for rel in extras:
        (CONN / rel).unlink()
    print(f"EMBEDDED_RUNTIME_OK cu=71 bridge=3 files={len(files)} manifest={len(provenance)}")


if __name__ == "__main__":
    main()
