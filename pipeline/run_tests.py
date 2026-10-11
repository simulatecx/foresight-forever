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


def toc_files() -> list[Path]:
    toc = ADDON_DIR / "Foresight.toc"
    files = []
    for line in toc.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("##"):
            files.append(ADDON_DIR / line.replace("\\", "/"))
    return files


def main() -> int:
    # Compliance gate first: a selftest pass means nothing if the code breaks the
    # rules the account depends on. Red here blocks the ship outright.
    import check_compliance

    if check_compliance.main() != 0:
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
    missing = [f for f in toc_files() if not f.exists()]
    if missing:
        print("missing files listed in TOC:")
        for f in missing:
            print(f"  {f}")
        return 1

    for path in toc_files():
        source = path.read_text(encoding="utf-8")
        try:
            load_chunk(source, path.name, ns)
        except lupa.LuaError as exc:
            print(f"LOAD FAILED {path.name}: {exc}")
            return 1
    print(f"loaded {len(toc_files())} files from Foresight.toc")

    lines: list[str] = []
    collect = lambda s: lines.append(str(s))  # noqa: E731
    ok = lua.eval("function(ns, out) return ns.runSelftest(out) end")(ns, collect)
    print("\n".join(lines))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
