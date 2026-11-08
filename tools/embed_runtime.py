#!/usr/bin/env python3
"""Vendor the supplied C:U and ZCity WoundBridge into the portable connector.

The embedded files use an isolated Lua namespace.  Quoted *.lua paths and C:U's
medical_tools include directory are rewritten; data/sound paths such as
woundsystem/persist and woundsystem/*.ogg intentionally stay untouched.  The
known embedded server sources also receive narrow versioned no-debug bridge
contracts, so dedicated servers without debug.getupvalue/setupvalue do not need
unsafe introspection.  External addons are never modified.

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

# Some dedicated servers remove debug.getupvalue/setupvalue.  The embedded
# sources are known and version-pinned, so expose a narrow lexical contract
# instead of requiring unsafe debug introspection.  No new file-scope locals
# are introduced in sv_health.lua (LuaJIT's 200-local limit matters here).
CU_NO_DEBUG_EXPORTS = r'''

if WoundSystem._WSZCEmbedded then
    WoundSystem.Health._WSZCBridgeRefs = {
        version = 1,
        Fn = Fn,
        Const = Const,
        SendCardioUpdate = SendCardioUpdate,
        ProcessImpactDamage = ProcessImpactDamage,
        SendLimbUpdate = SendLimbUpdate,
        BodyState = BodyState,
        PlayerLimbs = PlayerLimbs,
        GetBody = GetBody,
        TryCreateUnconsciousRagdoll = TryCreateUnconsciousRagdoll,
        GuessRagdollDamageLimb = GuessRagdollDamageLimb,
        RagdollBoneNameToLimb = RagdollBoneNameToLimb,
        BuildMedicalItemContext = BuildMedicalItemContext,
        ApplyBandageProfile = ApplyBandageProfile,
        GetSyringeProfile = GetSyringeProfile,
        ApplySyringeProfile = ApplySyringeProfile,
        Sessions = Sessions,
        CloseBandageSession = CloseBandageSession,
        CloseSyringeSession = CloseSyringeSession,
        CloseShrapnelSession = CloseShrapnelSession,
        CloseDislocationSession = CloseDislocationSession,
        CloseAedSession = CloseAedSession,
    }

    function WoundSystem.Health._WSZCReplaceUpvalue(fn, wanted, newValue)
        if type(fn) ~= "function" or type(newValue) ~= "table" then return false end
        local hooks = hook.GetTable and hook.GetTable() or nil
        local damage = type(hooks) == "table" and hooks.EntityTakeDamage or nil
        if type(damage) ~= "table" or damage.WoundSystem_Damage ~= fn then return false end

        if wanted == "Fn" then
            Fn = newValue
        elseif wanted == "Const" then
            Const = newValue
        else
            return false
        end
        return true
    end
end
'''

ZCITY_NO_DEBUG_EXPORTS = r'''

-- WSZC embedded no-debug contract.  External ZCity is never modified.
WB._WSZCBridgeRefs = { version = 1, BestLimb = BestLimb }
function WB._WSZCReplaceBestLimb(swepHeal, replacement)
    if swepHeal ~= WB.SwepHeal or type(replacement) ~= "function" then return false end
    BestLimb = replacement
    return true
end
'''

ZCITY_MINIGAME_CONTEXT = b'''\
\t\tswep = swep,
\t\tidx = idx,
\t\tspec = spec,
\t\ttarget = target,
\t\tmaxDur = maxDur,
\t\tlive = live,
\t\toneDose = oneDose,
\t\t_WSZCSetAppliedLive = function(value)
\t\t\tappliedLive = math.max(tonumber(value) or 0, 0)
\t\tend,
'''


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
            if rel == "woundsystem/server/sv_health.lua":
                transformed += CU_NO_DEBUG_EXPORTS.replace("\n", "\r\n").encode("utf-8")
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
            transformed = original
            if rel == "sv_woundbridge.lua":
                newline = b"\r\n" if b"\r\n" in original else b"\n"
                needle = b"\t\tamount = amount," + newline
                assert original.count(needle) == 1, "embedded minigame context anchor"
                context = ZCITY_MINIGAME_CONTEXT.replace(b"\n", newline)
                transformed = original.replace(needle, needle + context, 1)
                transformed += ZCITY_NO_DEBUG_EXPORTS.replace("\n", newline.decode()).encode("utf-8")
            files[(BRIDGE_DEST / rel).relative_to(CONN).as_posix()] = transformed
            provenance.append((name, sha(original), sha(transformed)))
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
