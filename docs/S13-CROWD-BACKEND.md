# S13 - Crowd backend (Firebase) + "compare to your spec"

Authoritative design for the crowd-data phase. Firebase project **wow-foresight**.
Governs the web app (`web/`), the Firestore model, the addon's share contract
(`Foresight/core/crowd.lua`), and the pipeline bake-back. Written 2026-10-13.

## 1. The one-paragraph architecture

The WoW addon **never networks** (account-safety doctrine). It journals game data
locally and, on `/foresight share`, builds a **sanitized, allow-listed JSON payload**
(`core/crowd.lua`). The user pastes that into the companion web app
(`wow-foresight.firebaseapp.com`), ticks consent, and it's written to Firestore
`contributions`. A Cloud Function aggregates contributions into per-`class/spec/level`
**percentile buckets** under `aggregates` (small-bucket suppressed). The web app reads
those to show "your spellcasting is ~top 30% of your spec." The pipeline periodically
reads the aggregates and bakes a human-reviewed `peer_baselines.lua` into the addon so
the in-game panels can show the comparison without the addon ever fetching anything.

```
addon (local only) --/foresight share--> user copy/paste --> web app
   |                                                            |  (opt-in, re-validated)
   | (pipeline bake, reviewed)                                  v
peer_baselines.lua  <-- pipeline <-- aggregates <-- Cloud Fn <-- contributions (write-only)
```

## 2. Data contract (PII classification + allow/deny)

Built by an **allow-list** in `core/crowd.lua` (`Crowd.buildPayload`) and re-checked by
`web/app.js` `sanitize()` and by `web/firestore.rules` `validContribution()` - three
gates, same shape. Every field is classified; there is **no direct or indirect PII**.

| Field | Classification | Why it's here |
|---|---|---|
| `v`, `build` | none | schema/data-build compatibility |
| `class`, `spec`, `level` | none | the comparison bracket |
| `lenses{}` | none | computed dimension indices (numbers) |
| `talents{}` | none | node id -> rank (build shape) |
| `items{}` | none | item id -> count (the "what's in game" DB) |
| `observed{}` | none | spellId -> {n, stats} (live buff facts) |
| `clientId` | pseudonym | random per-install token; count distinct contributors / dedup. NOT identity. |

**Never collected** (rejected by all three gates): character name, realm, account,
guild, zone, IP-linked identity, timestamps (`.at`/`.last` are stripped), and any free
text - the `/foresight report` notes, taint events, and tooltip-owner strings stay on
the user's machine. `Crowd.FORBIDDEN_KEYS` + the selftest assert this; the Firestore
rules' `hasOnly()` rejects any extra key even from a modified client.

## 3. Security model (best practices)

- **The apiKey is public, by design.** A Firebase web apiKey identifies the project; it
  is not a secret and is expected in client code. Security is the rules + App Check,
  never key secrecy. **No Admin SDK / service-account JSON ever enters this repo** - it
  lives only in Cloud Functions runtime config.
- **Default-deny Firestore** (`web/firestore.rules`): the only writable path is
  `contributions`, create-only, **App Check + anonymous-auth required**, and
  shape-validated (`hasOnly` allow-list + type/range clamps). Raw contributions are
  **never client-readable**. `aggregates` are read-only to clients and writable only by
  the Cloud Function (admin SDK bypasses rules).
- **App Check** (reCAPTCHA v3) stops scripted abuse of the write path.
- **Small-bucket suppression**: the aggregation function emits percentiles only for
  brackets at/above `minBucket` (default 5); smaller brackets expose a count only.
- **Aggregates carry no clientIds, no raw rows** - just counts + percentile tables.

## 4. Minimal human review (the user's "least review" goal)

- Contributions flow in automatically; no human gates the raw intake (it's shape-locked
  and identity-free, so there's nothing to moderate).
- The **only** human-review step is the standing law: before any crowd signal changes
  `overrides.lua` / ships a `peer_baselines.lua`, the pipeline produces a reviewed diff
  (k-of-n distinct `clientId`s). That stays - it's how bad/aberrant data can't silently
  move the addon's numbers. Everything else is automated.

## 5. Retention / erasure

Contributions are pseudonymous **aggregate-source** data (no identity attached). Intent:
keep for aggregation; the `clientId` is the only handle. A contributor who kept their
share-text id can request deletion of that id's rows (ops script, dry-run first per
`safe-data-ops`). No account system = no per-person erasure surface to build.

## 6. WHAT WE NEED FROM YOU (Firebase console - one-time)

These can only be done by the project owner in the console; the code is ready for them:

1. **Firestore**: create the database (production mode).
2. **Authentication**: enable **Anonymous** sign-in.
3. **App Check**: register the web app, create a **reCAPTCHA v3** site key, paste it
   into `web/app.js` (`RECAPTCHA_SITE_KEY`), and set Firestore to **enforce** App Check.
4. **Hosting**: `firebase init hosting` (public dir = `web/`), `firebase deploy`.
5. **Rules**: `firebase deploy --only firestore:rules` (uses `web/firestore.rules`).
6. **Cloud Function** (aggregation) - the one remaining code piece to write next; it
   reads `contributions`, computes per-bracket percentiles with suppression, writes
   `aggregates`. (Admin credentials stay in function config, never in the repo.)

Decisions already made (safe defaults, change if you want): anonymous auth (frictionless)
over sign-in; web-paste over a file-reading companion exe; compare shown in the web app
now, baked into the addon via the pipeline later.

## 7. Build status

- ☑ Addon share contract (`core/crowd.lua`): allow-list payload + JSON encoder +
  `/foresight share`; selftest-pinned (no PII/timestamp can leak).
- ☑ Firestore rules (deny-all / validated-write / aggregate-read).
- ☑ Web app skeleton (consent gate, client re-validation, contribute + compare).
- ☑ Privacy disclosure (`web/privacy.html`).
- ☐ Cloud Function aggregation (percentiles + suppression) - next.
- ☐ Firebase console setup (section 6) - owner.
- ☐ Pipeline bake-back `peer_baselines.lua` + in-addon "vs your spec" readout.
- ☐ Gated on S12 publish for real-user scale.
