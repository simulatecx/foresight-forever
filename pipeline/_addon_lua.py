"""Load the Foresight addon into a headless Lua VM (lupa) and hand back (lua, ns).

The addon's WoW-client wiring is gated on CreateFrame, so every TOC-listed file loads
under lupa - the same invariant the ship gate relies on. Shared by run-time analysis tools
(fetch_top_builds) that need the addon's OWN engine (TB.decode, Synergy.analyzeBuild) rather
than a Python re-implementation that could drift from what ships. No files are executed
beyond the TOC list; the VM has no os/io exposed to loaded chunks' return values.
"""
from pathlib import Path

import lupa

ADDON_DIR = Path(__file__).parent.parent / "Foresight"


def toc_files(toc_name: str = "Foresight.toc") -> list[Path]:
    toc = ADDON_DIR / toc_name
    files = []
    for line in toc.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(ADDON_DIR / line.replace("\\", "/"))
    return files


def load_addon(toc_name: str = "Foresight.toc"):
    """Return (lua, ns) with every TOC file loaded. ns is the HM namespace table."""
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    load_chunk = lua.eval(
        'function(source, name, ns)\n'
        '  local chunk, err = load(source, "@" .. name)\n'
        '  if not chunk then error(err) end\n'
        '  return chunk("Foresight", ns)\n'
        'end'
    )
    ns = lua.table()
    for path in toc_files(toc_name):
        if path.exists():
            load_chunk(path.read_text(encoding="utf-8"), path.name, ns)
    return lua, ns
