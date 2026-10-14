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
3. **App Check**: register the web app with **reCAPTCHA Enterprise / "Fraud Defense"**
   (the current provider - classic reCAPTCHA v3 is retired for new projects). In the
   flow, create a reCAPTCHA **key** of type *Website* with domains
   `wow-foresight.firebaseapp.com`, `wow-foresight.web.app`, and `localhost` (testing);
   paste the resulting **site key** (starts with `6L...`) into `web/app.js`
   (`RECAPTCHA_ENTERPRISE_SITE_KEY`), then set Firestore to **enforce** App Check.
   Note: reCAPTCHA Enterprise runs on the Google Cloud project and may require the
   **Blaze** (pay-as-you-go) plan with a billing account linked; usage sits inside a
   generous free tier (~10k assessments/month) so a niche addon should cost $0.
   Interim option if you don't want billing yet: leave App Check in **monitor** (not
   enforce) and rely on anonymous-auth + the shape-locked create-only rules as the
   write gate for the pilot - the data is write-only, non-readable, and allow-listed,
   so the abuse surface is small; switch to enforce when scaling.
4. **Hosting**: `firebase init hosting` (public dir = `web/`), `firebase deploy`.
5. **Rules**: `firebase deploy --only firestore:rules` (uses `web/firestore.rules`).
6. **Cloud Function** (aggregation) - the one remaining code piece to write next; it
   reads `contributions`, computes per-bracket percentiles with suppression, writes
   `aggregates`. (Admin credentials stay in function config, never in the repo.)

Decisions already made (safe defaults, change if you want): anonymous auth (frictionless)
over sign-in; web-paste over a file-reading companion exe; compare shown in the web app
now, baked into the addon via the pipeline later.

## 8. Opt-in identifying tier: shareable builds + Armory link (user ask 2026-10-14)

Players want to OPT IN to publish their **full talent tree** and **WoW Armory profile
link**, and (future) let others **copy** a build. This is a deliberately IDENTIFYING
feature - an Armory link is `.../character/<realm>/<name>`, i.e. name + realm = PII -
so it is a SEPARATE tier from the anonymous crowd data, governed by privacy-by-design:

- **Two tiers, never mixed.** Tier 1 = the anonymous `contributions` (today; no
  identity, ever). Tier 2 = `sharedBuilds` (new): the user CHOOSES to be identifiable,
  the way linking your Warcraft Logs / Armory is a choice. Tier 2 never changes Tier 1.
- **Separate explicit consent.** A distinct checkbox, not the anonymous one: "Publish
  my build and Armory link so others can view/copy it - this makes my character name
  and realm public." Default off. Its own disclosure paragraph in `privacy.html`.
- **Shape (allow-list):** `{ v, class, spec, level, talentString (the game's import
  string), armoryUrl (validated: host is the official Armory domain, length-capped),
  clientId }`. NO free text, no notes. `talentString` is opaque game data; `armoryUrl`
  is the only identifying field and only because the user is publishing it on purpose.
- **Rules:** `sharedBuilds` is publicly READABLE (that's the point - others copy it),
  create gated by auth + App Check + shape; update/delete only via the owner's
  `clientId` match (so a person can pull their own shared build). This is a PUBLIC
  projection by consent, kept thin (no stats dump, no observations).
- **Erasure:** because it's identity-by-choice, self-service removal is required - a
  "remove my shared build" action keyed off the clientId in the user's share text, plus
  an ops delete. (Tier 1 needs none; Tier 2 does.)
- **The "copy talents" future (data-only law):** importing someone's `talentString`
  is DATA parsing that feeds the planner/what-if only - NEVER loadstring, never an
  automated apply of protected talent operations (the suggest-only + untrusted-input
  laws). The addon shows "here's their build; here's the diff vs yours," you spend the
  points yourself.
- **Policy-practice sync:** `privacy.html` + any T&Cs land the Tier-2 paragraph in the
  SAME change that ships the collection.

Status: ☐ designed, not built - it introduces PII (by consent) + a public surface, so
it ships only after the owner confirms this approach (section 6-style console review +
this design). Build order TBD with the owner.

## 7. Build status

- ☑ Addon share contract (`core/crowd.lua`): allow-list payload + JSON encoder +
  `/foresight share`; selftest-pinned (no PII/timestamp can leak).
- ☑ Firestore rules (deny-all / validated-write / aggregate-read) - **deployed** to
  wow-foresight. Numeric fields use `is number` not `is int` (the web SDK can encode
  integers as doubles; the range clamp is the real check).
- ☑ Web app (`web/`) - **deployed** to https://wow-foresight.web.app (Firebase
  Hosting). App Check uses the real reCAPTCHA Enterprise key
  `6LdlDe4t...` (public client id). JS/HTML served no-cache + the module import is
  versioned (`app.js?v=N`) so deploys aren't masked by the browser cache - bump N on
  change.
- ☑ Privacy disclosure (`web/privacy.html`).
- ☑ `firebase.json` / `.firebaserc` deploy config; `web/` excluded from the addon
  package (`.pkgmeta`).
- ☑ END-TO-END TESTED (2026-10-14, Playwright): page loads clean (0 console errors
  with the real key); client validation gates correctly; **Compare read works**
  (graceful empty-bucket message); **Contribute** passes auth + shape + write (proven
  with the gate temporarily relaxed, then restored) - the only pending item is App
  Check token validation into `request.app`, which was still propagating on the
  minutes-old key. Test contribution was deleted; no residual data.
- ◐ App Check propagation: the key is correctly configured (domains
  web.app/firebaseapp.com/localhost, SCORE). Writes start succeeding once Firestore's
  backend validates the new key (minutes to ~1h). If it persists, confirm App Check is
  **Enforced** for Firestore in the console and the web App Check provider is
  registered to this key.
- ☑ Cloud Function aggregation (`functions/index.js`) - **deployed + proven live**
  (2026-10-14). `aggregateOnWrite` (Firestore trigger) + `aggregateDaily` (scheduled),
  Node 22. Dedups by clientId, groups per class/spec/level-bucket, writes per-lens
  QUANTILES (min/p25/p50/p75/p90/max/mean) with MIN_BUCKET=5 suppression; carries no
  clientIds/raw rows. The web Compare places your value against the quantiles (tested:
  7-contributor bucket → "spellcasting 118 = top ~8%", "meleeDps 145 = top ~90%"). Test
  data was seeded then fully deleted.
  - Owner IAM note (Gen2 first-time): the compute SA
    `443733238250-compute@developer.gserviceaccount.com` was granted
    `roles/cloudbuild.builds.builder` (to build) and `roles/datastore.user` (to read
    contributions / write aggregates). Both done.
- ◐ App Check WRITE gate: contributions still deny client writes until the new
  reCAPTCHA Enterprise key's App Check tokens validate into `request.app` (propagation;
  key config verified correct). Reads + aggregation are unaffected. Confirm a real
  Contribute once it propagates; if it lingers, ensure the web App Check provider is
  registered to the key and Firestore App Check is Enforced.
- ☐ Pipeline bake-back `peer_baselines.lua` + in-addon "vs your spec" readout.
- ☐ Gated on S12 publish for real-user scale.
- ☐ OPT-IN IDENTIFYING TIER (user ask 2026-10-14): share full talent tree + WoW Armory
  profile link. The Armory link contains character name+realm = **PII** - must be a
  SEPARATE explicit opt-in, stored apart from the anonymous contributions, with its own
  consent + disclosure (see section 8).
