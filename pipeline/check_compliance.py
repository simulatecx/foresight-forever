"""Compliance gate: static scan proving the Foresight addon stays inside Blizzard's rules.

Protects the failure class "a code change introduces an automation call, protected-API
use, or sandbox escape that could put the account at risk / break addon policy".
Foresight is display-and-advice only BY DESIGN, so the gate is maximally conservative:
any casting, targeting, movement, item-use, or macro-execution call is a violation,
even ones addons may legally make on a hardware event - this addon never needs them.

Runs standalone (python check_compliance.py) and inside run_tests.py (the ship gate).
False positive? Append `-- compliance-allow: <reason>` to the exact line, with a real
justification; the allowance itself is reported so reviews see it.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ADDON_DIR = Path(__file__).parent.parent / "Foresight"

# Automation / protected-action APIs: display-only addons have zero business calling
# these. Word-boundary + call-paren so prose in tooltips/comments doesn't trip it.
AUTOMATION_CALLS = [
    "CastSpell", "CastSpellByName", "CastSpellByID", "CastPetAction",
    "CastShapeshiftForm", "UseAction", "UseItemByName", "UseInventoryItem",
    "UseContainerItem", "RunMacro", "RunMacroText", "RunScript",
    "TargetUnit", "TargetNearestEnemy", "TargetLastEnemy", "TargetNearestFriend",
    "AssistUnit", "FocusUnit", "InteractUnit", "ClearTarget",
    "AttackTarget", "StartAttack", "PetAttack", "PetFollow",
    "JumpOrAscendStart", "AscendStop", "MoveForwardStart", "MoveBackwardStart",
    "StrafeLeftStart", "StrafeRightStart", "TurnLeftStart", "TurnRightStart",
    "MoveAndSteerStart", "ToggleAutoRun", "FollowUnit",
    "AcceptTrade", "InitiateTrade", "AcceptGroup", "AcceptQuest",
    "BuyMerchantItem", "SendMail", "PlaceAuctionBid",
]
AUTOMATION_RE = re.compile(
    r"(?<![\w.])(?:C_\w+\.)?(" + "|".join(AUTOMATION_CALLS) + r")\s*\("
)

# Sandbox escapes / policy problems. The WoW client doesn't even expose these, but the
# gate ensures nothing creeps in that would only "work" in the test harness, and that
# code stays non-obfuscated (addon policy requires fully visible source).
ESCAPE_PATTERNS = [
    (re.compile(r"(?<![\w.])os\.\w"), "os.* (no OS access in addon code)"),
    (re.compile(r"(?<![\w.])io\.\w"), "io.* (no file I/O in addon code)"),
    (re.compile(r"(?<![\w.])require\s*\("), "require() (no module loading)"),
    (re.compile(r"(?<![\w.])loadstring\s*\("), "loadstring() (no dynamic code)"),
    (re.compile(r"(?<![\w.])dofile\s*\("), "dofile() (no file execution)"),
    (re.compile(r"(?<![\w.])loadfile\s*\("), "loadfile() (no file loading)"),
]

ALLOW_MARKER = "-- compliance-allow:"

# ---- Lua 5.1 dialect lint -----------------------------------------------------
# The client runs Lua 5.1; the headless harness runs newer Lua, which ACCEPTS the
# 5.3+ constructs below - so without this lint, code using them would pass every
# test and then fail to load in game. Gate the dialect, not just the policy.
# Strings and comments are scrubbed first (newlines preserved so line numbers
# hold): WoW color codes ("|cff...") and URLs would otherwise false-positive.

def _scrub_lua(text: str) -> str:
    def blank(m: re.Match) -> str:
        return re.sub(r"[^\n]", " ", m.group(0))

    text = re.sub(r"--\[(=*)\[.*?\]\1\]", blank, text, flags=re.S)  # long comments
    text = re.sub(r"\[(=*)\[.*?\]\1\]", blank, text, flags=re.S)    # long strings
    text = re.sub(r'"(?:\\.|[^"\\\n])*"', blank, text)              # "strings"
    text = re.sub(r"'(?:\\.|[^'\\\n])*'", blank, text)              # 'strings'
    text = re.sub(r"--[^\n]*", "", text)                            # line comments
    return text


DIALECT_PATTERNS = [
    (re.compile(r"(?<![\w])goto\s+\w"), "goto (Lua 5.2+)"),
    (re.compile(r"::\w+::"), "::label:: (Lua 5.2+)"),
    (re.compile(r"//"), "// integer division (Lua 5.3+)"),
    (re.compile(r"~(?!=)"), "~ bitwise op (Lua 5.3+; only ~= exists in 5.1)"),
    (re.compile(r"(?<!\|)\|(?!\|)|&"), "&/| bitwise op (Lua 5.3+)"),
    (re.compile(r"<<|>>"), "<</>> bit shift (Lua 5.3+)"),
]


def dialect_scan() -> list[str]:
    violations: list[str] = []
    for path in sorted(ADDON_DIR.rglob("*.lua")):
        rel = path.relative_to(ADDON_DIR.parent)
        raw_lines = path.read_text(encoding="utf-8-sig").splitlines()
        scrubbed = _scrub_lua("\n".join(raw_lines)).splitlines()
        for lineno, line in enumerate(scrubbed, 1):
            hits = [label for pattern, label in DIALECT_PATTERNS if pattern.search(line)]
            if not hits:
                continue
            original = raw_lines[lineno - 1] if lineno <= len(raw_lines) else ""
            if ALLOW_MARKER in original:
                continue  # documented allowance (reported by the policy scan)
            violations.append(f"{rel}:{lineno} {'; '.join(hits)} :: {original.strip()[:120]}")
    return violations


def scan() -> tuple[list[str], list[str]]:
    violations: list[str] = []
    allowances: list[str] = []
    lua_files = sorted(ADDON_DIR.rglob("*.lua"))
    if not lua_files:
        violations.append("no .lua files found under Foresight/ - wrong directory?")
        return violations, allowances

    for path in lua_files:
        rel = path.relative_to(ADDON_DIR.parent)
        # utf-8-sig: tolerate BOMs (common when files are written by Windows tools).
        for lineno, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
            hits: list[str] = []
            m = AUTOMATION_RE.search(line)
            if m:
                hits.append(f"automation call {m.group(1)}()")
            for pattern, label in ESCAPE_PATTERNS:
                if pattern.search(line):
                    hits.append(label)
            if not hits:
                continue
            if ALLOW_MARKER in line:
                reason = line.split(ALLOW_MARKER, 1)[1].strip() or "(no reason given!)"
                allowances.append(f"{rel}:{lineno} allowed [{'; '.join(hits)}] reason: {reason}")
            else:
                violations.append(f"{rel}:{lineno} {'; '.join(hits)} :: {line.strip()[:120]}")

    toc = ADDON_DIR / "Foresight.toc"
    if not toc.exists():
        violations.append("Foresight.toc missing")
    else:
        toc_text = toc.read_text(encoding="utf-8")
        if "## Interface:" not in toc_text:
            violations.append("Foresight.toc: missing ## Interface")
    return violations, allowances


def main() -> int:
    # The gate's own output must never crash on exotic characters (cp1252 consoles).
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    violations, allowances = scan()
    for a in allowances:
        print(f"ALLOWED  {a}")
    if violations:
        print("COMPLIANCE GATE RED - the following must be removed (this addon is")
        print("display-and-advice only; automation or sandbox escapes are never OK):")
        for v in violations:
            print(f"  {v}")
        return 1
    dialect = dialect_scan()
    if dialect:
        print("DIALECT LINT RED - Lua 5.2+ constructs load in the test harness but")
        print("FAIL in the 5.1 game client (the harness can't catch these - this can):")
        for v in dialect:
            print(f"  {v}")
        return 1
    files = len(list(ADDON_DIR.rglob("*.lua")))
    print(f"compliance gate green: {files} Lua files scanned, 0 violations, "
          f"{len(allowances)} documented allowance(s); Lua 5.1 dialect lint green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
