"""Search Reddit for WoW: Forever talent content and queue a VERIFICATION review draft.

The verification loop (owner, 2026-10-16): community posts often carry talent values,
hotfix observations, and screenshots before any export updates. This tool SEARCHES
Reddit's public JSON API for Forever talent discussion, extracts talent-name mentions
plus nearby numeric claims, diffs them against our shipped per-rank data, and writes a
HUMAN-REVIEW draft under pipeline/collected/ (gitignored - drafts never publish).

NOTHING here is auto-applied. The source-of-truth ladder is fixed:
  Blizzard/client data > in-game tooltip scans > release notes > community (Reddit, sites).
A community claim only reaches shipped data through the normal review path (overrides.lua
or a verifiedRules push) after k-of-n agreement and human sign-off.

Etiquette: public read-only JSON endpoints, a descriptive User-Agent with contact, 2s
between requests, bounded result counts, responses cached (re-run without --force reads
the cache, zero network).

Usage: python pipeline/fetch_reddit.py [--force] [--limit N] [--days N]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).parent
CACHE = ROOT / "cache" / "reddit"
TF_CACHE = ROOT / "cache" / "talentsforever"
OUT_DIR = ROOT / "collected"
USER_AGENT = "foresight-pipeline/0.49 (WoW Forever talent verification; contact admin@simulatecx.com)"

# AUTH (verified 2026-10-16): Reddit blocks ALL anonymous JSON now (www/api 403; old.reddit
# serves a browser-check HTML page). The supported path is a registered app - the OWNER
# creates one once at https://www.reddit.com/prefs/apps (type "script", any name/about URL),
# then puts the two values in pipeline/reddit_auth.json (GITIGNORED):
#   {"client_id": "<under the app name>", "client_secret": "<secret>"}
# or env vars REDDIT_CLIENT_ID / REDDIT_CLIENT_SECRET. App-only OAuth (client_credentials)
# is read-only public data - no account scope, standard API etiquette.
AUTH_FILE = ROOT / "reddit_auth.json"
OAUTH_BASE = "https://oauth.reddit.com"
SEARCHES = [
    ("r/wowforever", OAUTH_BASE + "/r/wowforever/new?limit={limit}"),
    ("r/wowforever talents", OAUTH_BASE + "/r/wowforever/search"
     "?q=talent&restrict_sr=1&sort=new&t=year&limit={limit}"),
    ("r/classicwow forever talents", OAUTH_BASE + "/r/classicwow/search"
     "?q=%22forever%22%20talent&restrict_sr=1&sort=new&t=month&limit={limit}"),
    ("site-wide forever talent tree", OAUTH_BASE + "/search"
     "?q=%22wow%20forever%22%20talent&sort=new&t=month&limit={limit}"),
]


def oauth_token() -> str | None:
    import base64
    import os
    cid = os.environ.get("REDDIT_CLIENT_ID")
    sec = os.environ.get("REDDIT_CLIENT_SECRET")
    if not (cid and sec) and AUTH_FILE.exists():
        try:
            d = json.loads(AUTH_FILE.read_text(encoding="utf-8"))
            cid, sec = d.get("client_id"), d.get("client_secret")
        except Exception:  # noqa: BLE001
            pass
    if not (cid and sec):
        return None
    data = urllib.parse.urlencode({"grant_type": "client_credentials"}).encode()
    req = urllib.request.Request(
        "https://www.reddit.com/api/v1/access_token", data=data,
        headers={"User-Agent": USER_AGENT,
                 "Authorization": "Basic "
                 + base64.b64encode(f"{cid}:{sec}".encode()).decode()})
    tok = json.loads(urllib.request.urlopen(req, timeout=30).read().decode("utf-8"))
    return tok.get("access_token")

# Numeric claims near a talent mention: "15%", "by 3 sec", "5/10/15", "33 / 66 / 100".
CLAIM_RE = re.compile(
    r"(\d+(?:\.\d+)?(?:\s*/\s*\d+(?:\.\d+)?)+\s*%?"   # progressions: 5/10/15[%]
    r"|\d+(?:\.\d+)?\s*%"                             # single percents: 15%
    r"|\bby\s+\d+(?:\.\d+)?\b)",                      # "by 3", "by 0.5"
    re.IGNORECASE)


def http_json(url: str, force: bool, token: str | None) -> dict | None:
    CACHE.mkdir(parents=True, exist_ok=True)
    key = re.sub(r"[^A-Za-z0-9]+", "_", url)[:120] + ".json"
    dest = CACHE / key
    if dest.exists() and not force:
        return json.loads(dest.read_text(encoding="utf-8"))
    if token is None and url.startswith(OAUTH_BASE):
        return None  # oauth endpoints need credentials; nothing cached - quiet skip
    try:
        headers = {"User-Agent": USER_AGENT}
        if token:
            headers["Authorization"] = "Bearer " + token
        req = urllib.request.Request(url, headers=headers)
        raw = urllib.request.urlopen(req, timeout=30).read().decode("utf-8")
        if raw.lstrip()[:1] == "<":  # an HTML interstitial, not data - treat as blocked
            raise ValueError("HTML response (browser-check page), not JSON")
        parsed = json.loads(raw)
        dest.write_text(raw, encoding="utf-8")
        time.sleep(2)  # etiquette: never hammer
        return parsed
    except Exception as e:  # noqa: BLE001 - a blocked/failed search degrades to cache/skip
        if dest.exists():
            print(f"  fetch failed ({e}); using cached copy")
            return json.loads(dest.read_text(encoding="utf-8"))
        print(f"  SKIP {url.split('?')[0]} ({e})")
        return None


def talent_names() -> dict[str, str]:
    """name(lower) -> 'CLASS: per-rank text' from the talentsforever cache (all 9 classes)."""
    names: dict[str, str] = {}
    for f in sorted(TF_CACHE.glob("*.json")):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            continue
        cls = d.get("class", f.stem)
        for tree in (d.get("talents") or {}).get("trees", []) or []:
            for t in tree.get("talents", []) or []:
                nm = (t.get("name") or "").strip()
                desc = t.get("desc") or []
                if len(nm) >= 6:  # skip short/generic names that false-positive everywhere
                    names[nm.lower()] = f"{cls}: " + " | ".join(
                        f"r{i + 1}: {d_}" for i, d_ in enumerate(desc))
    return names


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="refetch instead of cache")
    parser.add_argument("--limit", type=int, default=50, help="posts per search")
    parser.add_argument("--days", type=int, default=45, help="ignore posts older than this")
    args = parser.parse_args()

    known = talent_names()
    if not known:
        print("no talentsforever cache - run pipeline/fetch_talentsforever.py first")
        return 1
    print(f"matching against {len(known)} known talent names")

    token = None
    try:
        token = oauth_token()
    except Exception as e:  # noqa: BLE001
        print(f"reddit auth failed ({e}) - will try cache only")
    if not token:
        print("NO REDDIT CREDENTIALS: create an app at reddit.com/prefs/apps (type 'script')")
        print("and save pipeline/reddit_auth.json {\"client_id\":..., \"client_secret\":...}.")
        print("Continuing from cache (no network).")

    cutoff = time.time() - args.days * 86400
    posts: dict[str, dict] = {}
    for label, url in SEARCHES:
        data = http_json(url.format(limit=args.limit), args.force, token)
        got = 0
        for child in ((data or {}).get("data") or {}).get("children", []) or []:
            p = child.get("data") or {}
            pid = p.get("id")
            if not pid or pid in posts or (p.get("created_utc") or 0) < cutoff:
                continue
            posts[pid] = p
            got += 1
        print(f"{label}: +{got} posts")

    findings = []
    for p in posts.values():
        text = ((p.get("title") or "") + "\n" + (p.get("selftext") or ""))
        low = text.lower()
        hits = [nm for nm in known if nm in low]
        if not hits:
            continue
        # numeric claims within ~160 chars of each talent mention
        claims = {}
        for nm in hits:
            i = low.find(nm)
            window = text[max(0, i - 40): i + len(nm) + 160]
            nums = CLAIM_RE.findall(window)
            if nums:
                claims[nm] = nums[:6]
        findings.append({
            "title": p.get("title"), "subreddit": p.get("subreddit"),
            "url": "https://www.reddit.com" + (p.get("permalink") or ""),
            "score": p.get("score"), "author": p.get("author"),
            "created": datetime.fromtimestamp(p.get("created_utc") or 0,
                                              tz=timezone.utc).strftime("%Y-%m-%d"),
            "talents": hits, "claims": claims,
        })
    findings.sort(key=lambda f: (len(f["claims"]), f["score"] or 0), reverse=True)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(tz=timezone.utc).strftime("%Y-%m-%d")
    (OUT_DIR / "reddit_review.json").write_text(
        json.dumps({"generated": stamp, "posts_scanned": len(posts),
                    "findings": findings}, indent=1), encoding="utf-8")

    lines = [
        f"# Reddit talent-verification review - {stamp}",
        "",
        "REVIEW DRAFT - nothing here is applied automatically. For each claim: check it",
        "against the in-game tooltip (source of truth); if it holds and 2+ independent",
        "sources agree, promote via overrides.lua / push_verified.py as usual.",
        f"Scanned {len(posts)} posts; {len(findings)} mention known talents.",
        "",
    ]
    for f in findings:
        lines.append(f"## [{f['title']}]({f['url']})")
        lines.append(f"r/{f['subreddit']} · {f['created']} · score {f['score']} · u/{f['author']}")
        for nm in f["talents"]:
            claim = f["claims"].get(nm)
            lines.append(f"- **{nm}**" + (f" - claims near mention: `{claim}`" if claim else " (mentioned, no numbers nearby)"))
            ours = known.get(nm, "")
            if claim and ours:
                lines.append(f"  - ours: {ours[:300]}")
        lines.append("")
    (OUT_DIR / "reddit_review.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"\n{len(findings)} finding(s) from {len(posts)} posts -> {OUT_DIR / 'reddit_review.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
