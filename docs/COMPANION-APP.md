# Companion app - the always-on uploader ("play = contribute")

Authoritative design for the optional desktop companion. Firebase project
**wow-foresight**. Governs a new top-level `companion/` tree (does not yet exist) and
extends the crowd contract in `docs/S13-CROWD-BACKEND.md`. Written 2026-10-14.
Status: **spec / not built** (backlog story in `SPRINTS.md`).

## 1. The one-paragraph architecture

A WoW addon **cannot send data** - the addon sandbox has no network API, and any
out-of-game workaround (memory reads, input injection, game-file writes) is a bannable
ToS violation and forbidden by our account-safety doctrine. So "contribute just by
playing" cannot live in the addon. It lives in a tiny **desktop companion** that only
**reads the SavedVariables file the addon already writes** and uploads the same
sanitized payload the web app would - the Warcraft Logs / WowUp model. The game is never
touched: no process access, no memory, no input, no game-file writes, nothing but a
read of one `.lua` text file. Install once, consent once, and from then on playing
builds the shared database with zero clicks.

```
addon (local only, never networks)
   |  journals to disk
   v
WTF/Account/.../SavedVariables/ForesightDB.lua   (plain text the addon already writes)
   |  companion READS this file (read-only), watches for changes
   v
companion: safe-parse (neutered Lua sandbox) -> build sanitized payload (ONE contract)
   |  Firebase anonymous auth (public apiKey) + Firestore REST write
   v
contributions (write-only, shape-locked)  ->  Cloud Fn aggregate  ->  aggregates
```

The manual path (copy `/foresight share` into the web app) stays as-is for people who
don't want to install anything. The companion is strictly additive.

## 2. Hard invariants (carried, non-negotiable)

- **The addon still never networks.** The companion is a SEPARATE process. The addon's
  "never touches the network" promise is unchanged and must stay literally true in the
  marketing + privacy copy. The companion's network access is disclosed as its own thing.
- **Read-only, file-only.** The companion opens exactly one path: the Foresight
  SavedVariables file, for reading. It never writes it, never opens any other game file,
  never reads the client process/memory, never sends input, never launches the game.
  This is what keeps it in the Warcraft Logs / WowUp "safe" category.
- **Same non-identifying data contract.** It uploads ONLY what `Crowd.buildPayload`
  allow-lists (class/level/lenses/metrics/talents/items/observed/clientId). No name,
  realm, account, guild, IP, timestamps, or free text - ever. Names/armory links are the
  separate opt-in identifying tier (doc S8/S8a) and are NOT part of the default companion.
- **Untrusted-input law.** SavedVariables is user-editable data. The companion MUST parse
  it in the neutered Lua sandbox (`pipeline/harvest.py` `sandbox_selfcheck()` pattern),
  never `loadfile`/`require`/raw `load`. A hostile SavedVariables file must not be able to
  execute anything or read the host filesystem.
- **No shipped credentials.** The companion authenticates as an anonymous CLIENT (public
  `apiKey` only, already public) via Identity Toolkit REST, exactly like the web app. It
  NEVER embeds a service account / Admin SDK key (those bypass rules and can't be shipped
  in a distributed binary). The deny-all rules + `hasOnly` shape-lock + small-bucket
  suppression remain the only server-side gate.
- **Consent, asked + recorded + revocable.** First run shows exactly what is collected,
  that it is anonymous and aggregate-only, and a link to the privacy page. A visible
  on/off toggle stops uploads immediately. A local settings file records the consent
  (the consent-column pattern). Consent is never exceeded - the identifying tier is a
  second, explicit, off-by-default opt-in.

## 3. Tech choice - Python + PyInstaller (DECISION)

**Chosen: Python, packaged per-OS with PyInstaller.** Rationale:
- **Reuse.** The neutered Lua sandbox + the harvest payload logic already exist in
  `pipeline/` (Python). The companion reuses that sandbox verbatim - the hardest,
  most security-sensitive part is already written and selftest-gated.
- **No new language in the repo.** The codebase is Python (pipeline) + JS (web/functions)
  + Lua (addon). Python keeps the maintenance surface the same.
- **REST, no SDK weight.** Upload is plain HTTPS to the Firebase REST endpoints
  (`fetch_baselines.py` already talks Firestore REST) - no bundled native SDK.

Rejected: Electron/Tauri (a whole JS/Rust toolchain + bigger binary for a background
uploader with no real UI need), Go (would re-implement the Lua sandbox from scratch -
loses the reuse that makes this safe).

The UI is minimal: a tray icon + a tiny settings window (consent toggle, "last uploaded",
status, open-privacy). No game-facing UI.

## 4. Data flow in detail

1. **Locate** the SavedVariables file. WoW path:
   `<WoW>/_classic_beta_/WTF/Account/<ACCT>/SavedVariables/ForesightDB.lua` (and the
   per-character variant if used). Auto-detect the WoW install (registry on Windows,
   standard paths on macOS); let the user override the path. Handle multiple accounts.
2. **Watch** the file (mtime poll or a filesystem watcher), debounced - the game flushes
   SavedVariables on `/reload` and logout, so uploads naturally land at session
   boundaries, not mid-play.
3. **Safe-parse** `ForesightDB` in the neutered sandbox -> a plain data table.
4. **Build the sanitized payload** via the ONE shared allow-list (see §5). Reuse the
   addon's `clientId` from the store so the aggregator dedups the same contributor.
5. **Auth** anonymously: Identity Toolkit `accounts:signUp` (anonymous) with the public
   apiKey -> `idToken` (cached, refreshed).
6. **Upload** a `contributions` document via Firestore REST `POST .../documents/contributions`
   with the idToken. The existing `validContribution` rule + Cloud Function do the rest.
7. **Record** last-upload time + the payload hash so an unchanged file isn't re-sent.

## 5. The ONE allow-list (drift is the real risk)

Today the payload shape lives in three mirrors: `core/crowd.lua` (`buildPayload`),
`web/app.js` (`sanitize`), `web/firestore.rules` (`validContribution`). The companion
would be a FOURTH. Four hand-synced copies of a privacy-critical allow-list is how a PII
leak gets born. **Decision:** before the companion ships, extract the allow-list to a
single declarative schema (a small JSON: allowed keys, types, clamps, caps) that the
addon, web, rules-generator, and companion all consume. The companion's sanitizer is
generated from that schema, never hand-written. This is a prerequisite task, not an
afterthought.

## 6. Consent + privacy UX

- **First run:** a plain-language screen - "Foresight's companion uploads your *anonymous*
  game data (class, level, talents, stats, gear seen) to the shared database so the guides
  get sharper for everyone. Never your name, realm, or account. Turn it off anytime." +
  the privacy-page link + an explicit Enable button (no pre-ticked default).
- **Anonymous tier default-eligible, identifying tier strict opt-in.** The anonymous
  stream (incl. the low-risk talent rank-rule votes) is the whole default product. A name
  / armory link is a SECOND toggle, off by default, with its own consent copy (it's PII).
- **Revocable + transparent:** the toggle stops uploads at once; a "what was last sent"
  view shows the exact JSON so there are no secrets about what leaves the machine.
- **Policy-practice sync:** shipping the companion updates the privacy page in the same
  change (it introduces a new processor + a network egress the addon never had).

## 7. Open questions (decide before build)

- **App Check on desktop.** reCAPTCHA Enterprise is web-only; desktop needs a custom
  App Check provider or we lean on anon-auth + shape-lock + a server-side rate limit
  (per-clientId / per-IP in the Cloud Function). App Check writes are already relaxed
  server-side today, so the companion can ship on anon-auth + rate-limit and adopt a
  custom App Check provider later. DECISION PENDING: confirm the rate-limit design.
- **Distribution.** CurseForge hosts addons, not executables. Ship the companion via
  **GitHub Releases + the website**, signed where possible (Windows SmartScreen / macOS
  notarization are real friction - plan for them). The addon TOC can show a one-line
  "get the optional companion at <url>" note.
- **Auto-update** of the companion itself (a background uploader that never updates is a
  liability) - a simple version check against GitHub Releases.
- **Abuse / rate-limit.** An always-on uploader is easier to script-spam than a manual
  paste. The Cloud Function must cap writes per clientId per window and ignore floods
  (the aggregator already dedups by clientId; add a write-rate guard).

## 8. Out of scope (explicitly not building)

- Anything that reads the game process, memory, or sends input - never.
- Writing or modifying ANY game file (including SavedVariables) - read-only, always.
- Shipping service-account / Admin credentials - never; anonymous client auth only.
- The identifying tier (names/armory) as a default - that's doc S8, separate consent.
- A rich desktop UI - a tray icon + a minimal settings/consent window is the whole thing.

## 9. Build order

1. **Single-source the allow-list** (§5) - the schema + regenerate the addon/web/rules
   consumers from it, selftest-gated. Prerequisite; no companion until this lands.
2. **Core library** (Python): locate file -> safe-parse (reuse harvest sandbox) ->
   build payload from the schema -> anonymous auth -> Firestore REST write. Headless,
   unit-tested against a captured real `ForesightDB.lua` + hostile fixtures.
3. **Rate-limit guard** in the Cloud Function (per-clientId write window).
4. **Tray UI + consent** + file-watch + last-sent transparency view.
5. **Packaging/signing** (Windows + macOS) + GitHub Releases + website download +
   privacy-page update (same change).
6. **Auto-update** check.
