"""Headless test harness: load the Foresight addon files in TOC order inside a Lua VM
(lupa) with the WoW addon vararg convention, then run the in-addon selftest.

Usage: python run_tests.py
Exit code 0 = all checks pass. This is the ship gate for addon-logic changes.
"""

from __future__ import annotations

import sys
from pathlib import Path

import lupa

ADDON_DIR = Path(__file__).parent.parent / "Foresight"

# Every flavor TOC gates: the main Forever TOC always; the Classic Era flavor (S43) when
# its TOC exists. Both must load clean and pass the full selftest - one engine, two datasets.
def flavor_tocs() -> list[str]:
    tocs = ["Foresight.toc"]
    if (ADDON_DIR / "Foresight_Vanilla.toc").exists():
        tocs.append("Foresight_Vanilla.toc")
    return tocs


def toc_files(toc_name: str = "Foresight.toc") -> list[Path]:
    toc = ADDON_DIR / toc_name
    files = []
    for line in toc.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(ADDON_DIR / line.replace("\\", "/"))
    return files


def version_sync_check() -> bool:
    """Every flavor TOC's Version must equal core/init.lua HM.version. Incident
    2026-10-11: the constant sat three releases behind and a harvest mis-diagnosed
    the live client."""
    import re

    init = (ADDON_DIR / "core" / "init.lua").read_text(encoding="utf-8")
    code_ver = re.search(r'^HM\.version\s*=\s*"([^"]+)"', init, re.M)
    for toc_name in flavor_tocs():
        toc = (ADDON_DIR / toc_name).read_text(encoding="utf-8")
        toc_ver = re.search(r"^## Version:\s*(\S+)", toc, re.M)
        if not (toc_ver and code_ver) or toc_ver.group(1) != code_ver.group(1):
            print(f"VERSION DRIFT RED - {toc_name} says "
                  f"{toc_ver.group(1) if toc_ver else '?'} but core/init.lua HM.version is "
                  f"{code_ver.group(1) if code_ver else '?'} - keep them identical")
            return False
    print(f"version sync green: v{code_ver.group(1)} across {len(flavor_tocs())} flavor TOC(s)")
    return True


def main() -> int:
    # Compliance gate first: a selftest pass means nothing if the code breaks the
    # rules the account depends on. Red here blocks the ship outright.
    import check_compliance

    if check_compliance.main() != 0:
        return 1

    if not version_sync_check():
        return 1

    # Harvest sandbox gate: untrusted SavedVariables must never reach os/io/python.
    import harvest

    if not harvest.sandbox_selfcheck():
        print("HARVEST SANDBOX RED - hostile SavedVariables payload escaped the sandbox")
        return 1
    print("harvest sandbox green: hostile payloads blocked, benign data parses")

    # Harvest analysis gate: the rank-rule voting must work end-to-end on real
    # generated data (guards the id-keyed table contract in lua_to_py).
    if not harvest.analyze_selfcheck():
        print("HARVEST ANALYZE RED - rank-rule voting broke (table shapes or math)")
        return 1
    print("harvest analyze green: synthetic probe votes as expected (A+B, trained+untrained)")

    # Observed-vs-generated gate: the play-verification compare must verdict
    # confirmed/mismatch/learned correctly and render a reviewable draft.
    if not harvest.observed_selfcheck():
        print("OBSERVED COMPARE RED - verdicts or the overrides draft broke")
        return 1
    print("observed compare green: confirmed/mismatch/learned verdicts + draft render")

    # Crowd-schema parity gate: the allow-list lives in ONE place (data/crowd-schema.json);
    # the addon builder, web sanitize, and Firestore rules are generated from it. Fail if
    # any committed mirror drifted, so a new field can't land in one and leak past another.
    import gen_crowd_schema

    if not gen_crowd_schema.check():
        return 1

    for toc_name in flavor_tocs():
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        load_chunk = lua.eval(
            """
            function(source, name, ns)
                local chunk, err = load(source, "@" .. name)
                if not chunk then error(err) end
                return chunk("Foresight", ns)
            end
            """
        )
        ns = lua.table()
        missing = [f for f in toc_files(toc_name) if not f.exists()]
        if missing:
            print(f"missing files listed in {toc_name}:")
            for f in missing:
                print(f"  {f}")
            return 1

        for path in toc_files(toc_name):
            source = path.read_text(encoding="utf-8")
            try:
                load_chunk(source, path.name, ns)
            except lupa.LuaError as exc:
                print(f"LOAD FAILED {path.name} [{toc_name}]: {exc}")
                return 1
        print(f"loaded {len(toc_files(toc_name))} files from {toc_name}")

        lines: list[str] = []
        collect = lambda s: lines.append(str(s))  # noqa: E731
        ok = lua.eval("function(ns, out) return ns.runSelftest(out) end")(ns, collect)
        print("\n".join(lines))
        if not ok:
            print(f"SELFTEST RED on flavor {toc_name}")
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
