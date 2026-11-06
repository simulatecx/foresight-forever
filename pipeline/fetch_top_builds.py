"""Daily top-builds listener (DATA-top-builds).

Pulls TOP-RATED talent builds from a PUBLIC source (owner steer 2026-11-06: examples are
what the community rates highly, NOT builds we invent) - each candidate carries the
source's rating so the draft ranks by it. Treats every imported code as DATA ONLY (decoded
+ re-validated by the addon's own TB.decode -> isLegal; never executed), runs each through
the addon's OWN synergy engine (Synergy.analyzeBuild, via lupa - one analyzer, no Python
re-implementation to drift) to explain WHY it works - INCLUDING cross-tree "hidden synergy"
insights the community often overlooks (Synergy.crossTreeInsights) - and writes a
HUMAN-REVIEW draft. NOTHING auto-ships: this mirrors the reddit / data-freshness
review-gated flow and the crowd-data law (k-of-n + a human-reviewed PR). Approved builds
are promoted BY HAND into pipeline/data/curated_builds.json, which gen_presets.py merges as
extra named presets (re-validated legal at generate time).

The addon never networks - this is offline dev tooling. Run daily by
.github/workflows/top-builds.yml, or locally:  python pipeline/fetch_top_builds.py

Sources (pluggable, priority order):
  1. crowd      - our own Firebase "most-run build per spec" aggregate (what real players
                  run; needs the backend build-aggregation + an authed token, like
                  fetch_baselines). STUB until the backend aggregates builds - see S46.
  2. talentsforever - featured/popular builds if the site exposes them. STUB.
  3. seed       - pipeline/data/community_builds.json (codes dropped in by hand for review)
                  + the shipped presets as a baseline, so the job always produces a draft.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from _addon_lua import load_addon

ROOT = Path(__file__).parent
COLLECTED = ROOT / "collected"            # gitignored (drafts never commit)
DATA = ROOT / "data"
SEED_FILE = DATA / "community_builds.json"  # hand-curated candidate codes (optional)


# ---- sources ----------------------------------------------------------------------------

def _seed_candidates() -> list[dict]:
    """Candidates from the local seed file + the shipped presets as a baseline. The seed
    file is a JSON list of {class, spec, code, source?} - data only, validated downstream."""
    out = []
    if SEED_FILE.exists():
        try:
            raw = json.loads(SEED_FILE.read_text(encoding="utf-8"))
            for b in raw if isinstance(raw, list) else []:
                if isinstance(b, dict) and isinstance(b.get("code"), str):
                    out.append({"class": str(b.get("class", "?")), "spec": str(b.get("spec", "?")),
                                "code": b["code"], "source": b.get("source", "community_builds.json"),
                                "rating": b.get("rating")})
        except (ValueError, OSError):
            pass
    return out


def _crowd_candidates() -> list[dict]:
    # TODO(S46): read the Firebase per-spec "most-run build" aggregate (authed token, like
    # fetch_baselines). Needs the backend to aggregate submitted talent builds first -
    # the share payload already carries the build, the aggregation is the missing half.
    return []


def _talentsforever_candidates() -> list[dict]:
    # TODO: if talentsforever.com exposes featured/popular builds, map them to FT codes here
    # (credited, as with the per-rank text ingest). No scraping of rejected sources.
    return []


# The Forever ARMORY (owner 2026-11-06: "WoW Armory Forever is live - look at top players'
# builds"). A public character armory lists real players' live talent trees. We can ingest
# TOP players' BUILDS as top-rated examples PROVIDED:
#   - DATA ONLY: read the talent tree, map it to an FT code, re-validate via TB.decode. The
#     armory is public-by-design, but we store/show the BUILD, not the player's identity -
#     no name/realm republished in-addon (the no-PII crowd-data contract; named tiers are
#     the separate opt-in S8a). Credit the armory site as a source, like talentsforever.
#   - ENDPOINT CONFIG: the base URL + how to list "top" characters + how to read a tree live
#     in pipeline/data/armory_source.json (NOT hardcoded - we don't know the live shape yet,
#     and the owner confirms the site's terms allow it). Absent/!enabled = [] (today).
# This keeps it "simply wired" the moment the real endpoint + shape are known, without
# fabricating a scraper against an unverified site.
ARMORY_CONFIG = DATA / "armory_source.json"


def _armory_candidates() -> list[dict]:
    if not ARMORY_CONFIG.exists():
        return []
    try:
        cfg = json.loads(ARMORY_CONFIG.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return []
    if not (isinstance(cfg, dict) and cfg.get("enabled")):
        return []
    # When enabled, cfg supplies pre-fetched candidates (a human/tool populates `builds`
    # from the armory out-of-band so this file never makes a live call without a reviewed,
    # terms-checked integration). Each: {class, spec, code, rating?, player?} - player is
    # kept ONLY for the review draft's provenance, never shipped into the addon.
    out = []
    for b in cfg.get("builds", []) if isinstance(cfg.get("builds"), list) else []:
        if isinstance(b, dict) and isinstance(b.get("code"), str):
            out.append({"class": str(b.get("class", "?")), "spec": str(b.get("spec", "?")),
                        "code": b["code"], "source": "forever-armory",
                        "rating": b.get("rating"), "player": b.get("player")})
    return out


def gather_candidates(sources: list[str]) -> list[dict]:
    funcs = {"crowd": _crowd_candidates, "talentsforever": _talentsforever_candidates,
             "armory": _armory_candidates, "seed": _seed_candidates}
    cands, seen = [], set()
    for s in sources:
        for c in funcs.get(s, lambda: [])():
            key = c.get("code")
            if key and key not in seen:
                seen.add(key)
                cands.append(c)
    return cands


# ---- analysis (the addon's OWN engine, via lupa) ----------------------------------------

def analyze(candidates: list[dict], toc: str = "Foresight.toc") -> list[dict]:
    """Decode + synergy-analyze each candidate with the shipped engine. A code that fails
    TB.decode (illegal / wrong-dataset / malformed) is DROPPED with its reason - that is the
    data-only, re-validated gate. Returns enriched dicts with the rationale."""
    lua, ns = load_addon(toc)
    tb = ns["TalentBuild"]
    syn = ns["Synergy"]
    if not (tb and syn and syn["analyzeBuild"]):
        raise SystemExit("addon did not expose TalentBuild/Synergy - load failed")
    decode = lua.eval("function(tb, code) local b, cls = tb.decode(code); return b, cls end")
    out = []
    for c in candidates:
        build, cls = decode(tb, c["code"])
        if build is None:
            out.append({**c, "ok": False, "reason": str(cls or "did not decode")})
            continue
        syn["_reset"](syn)
        an = syn["analyzeBuild"](build)
        lines = syn["analysisLines"](an, 4) if an else None
        rationale = []
        if lines:
            i = 1
            while lines[i] is not None:
                rationale.append(str(lines[i]["text"]))
                i += 1
        out.append({**c, "ok": True, "decodedClass": str(cls),
                    "headline": str(an["headline"]) if an else "",
                    "rationale": rationale})
    return out


# ---- review draft (human-gated; never auto-applied) -------------------------------------

def write_draft(results: list[dict]) -> tuple[Path, Path]:
    COLLECTED.mkdir(parents=True, exist_ok=True)
    md = ["# Top-builds review draft (NOT auto-applied)",
          "",
          "Candidate popular builds pulled by `fetch_top_builds.py`. Each was decoded +",
          "re-validated by the addon's TB.decode and analyzed by Synergy.analyzeBuild.",
          "To promote one: copy its `{class, spec, code}` into",
          "`pipeline/data/curated_builds.json`, then regenerate - gen_presets.py merges it",
          "as a named preset (re-validated legal). Reject by leaving it here.",
          ""]
    ok = [r for r in results if r.get("ok")]
    bad = [r for r in results if not r.get("ok")]
    # Rank by the source's rating (top-rated first); unrated sink to the bottom.
    ok.sort(key=lambda r: (r.get("rating") is None, -(r.get("rating") or 0)))
    md.append(f"## {len(ok)} legal candidate(s) (top-rated first)\n")
    for r in ok:
        rating = f", rating {r['rating']}" if r.get("rating") is not None else ""
        md.append(f"### {r['class']} - {r['spec']}  _(source: {r.get('source','?')}{rating})_")
        md.append(f"- code: `{r['code']}`")
        md.append(f"- why it works: **{r.get('headline','')}**")
        for line in r.get("rationale", []):
            md.append(f"  {line}")
        md.append("")
    if bad:
        md.append(f"## {len(bad)} rejected (did not decode / illegal)\n")
        for r in bad:
            md.append(f"- {r['class']} / {r['spec']} (`{r['code'][:32]}...`): {r['reason']}")
    md_path = COLLECTED / "top_builds_review.md"
    json_path = COLLECTED / "top_builds_review.json"
    hash_path = COLLECTED / "top_builds_review.hash"
    md_path.write_text("\n".join(md) + "\n", encoding="utf-8")
    json_path.write_text(json.dumps(results, indent=2), encoding="utf-8")
    # Content hash over the LEGAL candidate set (sorted codes), so the daily job can skip
    # opening a duplicate review issue when nothing changed - the dedup hardening. Only the
    # codes matter (same builds = same review), not ordering or transient analysis text.
    digest = hashlib.sha1("\n".join(sorted(r["code"] for r in ok)).encode("utf-8")).hexdigest()[:12]
    hash_path.write_text(digest + "\n", encoding="utf-8")
    return md_path, json_path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--sources", default="crowd,talentsforever,armory,seed",
                    help="comma list: crowd,talentsforever,armory,seed")
    ap.add_argument("--toc", default="Foresight.toc", help="flavor TOC to analyze against")
    args = ap.parse_args()

    cands = gather_candidates([s.strip() for s in args.sources.split(",") if s.strip()])
    if not cands:
        print("no candidate builds from any source - drop codes into "
              f"{SEED_FILE.relative_to(ROOT.parent)} or wire the crowd source (S46).")
        return 0
    results = analyze(cands, args.toc)
    md_path, json_path = write_draft(results)
    ok = sum(1 for r in results if r.get("ok"))
    print(f"analyzed {len(results)} candidate(s): {ok} legal, {len(results) - ok} rejected")
    print(f"review draft -> {md_path.relative_to(ROOT.parent)}  (NOT auto-applied)")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
