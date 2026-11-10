// RUN crowd backend (WP-B / RUN-E): raw `rareKills` submissions -> public rollups.
// CANONICAL SOURCE: run-forever/functions-run/index.js. The deployable copy is the
// Foresight repo's functions/rareKills.js (same bytes; its index.js re-exports
// rareKillsOnWrite - a Firebase project has ONE functions source). Keep them equal.
//
// Server-trust laws (docs/NOTES.md section 6): the raw collection is write-only and
// shape-locked by rules; THIS function is the only writer of the public docs; every
// valuable number is recomputed server-side (the slay tier comes from `snap`, never
// the client's claimed odds); per-clientId rate limits; MIN_BUCKET small-bucket
// suppression before anything publishes; creature names publish only at k-of-n
// distinct reporters. Privacy: no PII exists in the schema (rules hasOnly), and the
// public docs carry no clientIds - clientId is used for dedup/rate limiting only.

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

if (!getApps().length) initializeApp();
const db = getFirestore();

const MIN_BUCKET = 5;          // suppress public totals below this many events
const MAX_EVENTS = 100;        // envelope cap (rules enforce it too)
const RATE_MAX_PER_DAY = 20;   // submissions per clientId per UTC day
const SLAYS_MAX_PER_SUB = 5;   // giantSlayer entries honoured per submission
const KOFN_NAMES = 3;          // distinct clientIds before a sighted name publishes
const NAME_CANDIDATES_MAX = 10; // name candidates tracked per npc (abuse bound)
const NPC_MAX = 10000000;
const KINDS = ["death", "slay", "sighting", "wipe", "calib"];
const MODES = ["pve", "pvp", "hc"];
const SIGHTING_CLS = ["rare", "rareelite", "worldboss"];

// The SAME coarse odds model the addon ships (RUN/model/odds.lua): classification
// penalties rare .35 / elite .8 / rareelite 1.3, z = 1.1 - 0.28*delta - penalty,
// p = 1/(1+e^-z). Kept to the recomputable inputs (no health term: the snap carries
// levels + classification only; omitting health can only RAISE p, which is the
// strict direction - a wager that fails this check at full health was never a wager).
const CLS_PENALTY = { normal: 0, rare: 0.35, elite: 0.8, rareelite: 1.3 };

function plausibleNpc(n) {
  return Number.isInteger(n) && n >= 1 && n <= NPC_MAX;
}

function validSeason(s) {
  return typeof s === "string" && /^[a-z0-9]{1,8}$/.test(s);
}

function hasOnly(obj, allowed) {
  return Object.keys(obj).every((k) => allowed.includes(k));
}

// Recompute the win odds from the slay snapshot. Returns p in (0,1) or null when
// the snap is missing/off-shape (fail closed: unverifiable slays earn nothing).
function recomputeSlayOdds(snap) {
  if (!snap || typeof snap !== "object" || Array.isArray(snap)) return null;
  if (!hasOnly(snap, ["pLevel", "cLevel", "cls"])) return null;
  const { pLevel, cLevel, cls } = snap;
  if (!Number.isFinite(pLevel) || pLevel < 1 || pLevel > 200) return null;
  if (!Number.isFinite(cLevel) || cLevel < -1 || cLevel > 200) return null;
  if (typeof cls !== "string" || !(cls in CLS_PENALTY)) return null;
  const creature = cLevel === -1 ? pLevel + 10 : cLevel; // skull = +10, as the addon does
  const z = 1.1 - 0.28 * (creature - pLevel) - CLS_PENALTY[cls];
  return 1 / (1 + Math.exp(-z));
}

// A chosen handle: charset-clamped, trimmed, max 24, or null.
function clampHandle(h) {
  if (typeof h !== "string") return null;
  const cleaned = h.replace(/[^A-Za-z0-9_ -]/g, "").trim().slice(0, 24).trim();
  return cleaned.length > 0 ? cleaned : null;
}

// Creature/encounter names are game data but still text: strip markup-ish chars
// and control chars, trim, cap 48, require 2+ chars.
function cleanName(nm) {
  if (typeof nm !== "string") return null;
  const cleaned = nm.replace(/[|{}<>\\]/g, "").replace(/[\x00-\x1f]/g, "").trim().slice(0, 48);
  return cleaned.length >= 2 ? cleaned : null;
}

function normName(nm) {
  return nm.toLowerCase().replace(/\s+/g, " ").trim();
}

// Fletcher16 over the canonical event string (mirrors the addon + web mirror).
// ASCII-safe tokens only, so charCodeAt always agrees with Lua's byte().
function fletcher16(s) {
  s = String(s == null ? "" : s);
  let a = 0, b = 0;
  for (let i = 0; i < s.length; i++) { a = (a + s.charCodeAt(i)) % 255; b = (b + a) % 255; }
  return b * 256 + a;
}

function canonical(payload) {
  const events = Array.isArray(payload.events) ? payload.events : [];
  const toks = events.map((e) => `${e && e.k}:${e && typeof e.npc === "number" ? e.npc : "x"}`);
  return `${payload.v}|${payload.season}|${events.length}|${toks.join(",")}`;
}

// ---- per-kind event validation (deep; rules cannot iterate lists) ------------
// Each returns a CLEAN event object or null. Nothing off-shape ever reaches a
// rollup; nothing is copied wholesale.

function validDeath(e) {
  if (!hasOnly(e, ["k", "npc", "mode", "bracket", "zone", "season"])) return null;
  if (!plausibleNpc(e.npc) || !MODES.includes(e.mode) || !validSeason(e.season)) return null;
  if (e.bracket !== undefined
      && !(Number.isFinite(e.bracket) && e.bracket >= 0 && e.bracket <= 200
           && e.bracket % 10 === 0)) return null;
  if (e.zone !== undefined && !Number.isFinite(e.zone)) return null;
  return { k: "death", npc: e.npc, mode: e.mode, season: e.season };
}

function validSlay(e) {
  if (!hasOnly(e, ["k", "npc", "p", "snap", "mode", "season"])) return null;
  if (!plausibleNpc(e.npc) || !MODES.includes(e.mode) || !validSeason(e.season)) return null;
  if (!(Number.isFinite(e.p) && e.p >= 0 && e.p <= 1)) return null;
  const p = recomputeSlayOdds(e.snap);
  if (p === null) return null;     // unverifiable: fail closed
  if (p >= 0.5) return null;       // no wager existed at these odds; reject the claim
  return {
    k: "slay", npc: e.npc, mode: e.mode, season: e.season,
    p, tier: p < 0.25 ? "giantslayer" : "underdog",
  };
}

function validSighting(e) {
  if (!hasOnly(e, ["k", "npc", "nm", "cls", "zone", "season"])) return null;
  if (!plausibleNpc(e.npc) || !SIGHTING_CLS.includes(e.cls) || !validSeason(e.season)) return null;
  const nm = cleanName(e.nm);
  if (!nm) return null;
  return { k: "sighting", npc: e.npc, nm, cls: e.cls, season: e.season };
}

function validWipe(e) {
  if (!hasOnly(e, ["k", "npc", "enc", "size", "mode", "season"])) return null;
  if (!MODES.includes(e.mode) || !validSeason(e.season)) return null;
  const hasNpc = e.npc !== undefined, hasEnc = e.enc !== undefined;
  if (hasNpc === hasEnc) return null;  // exactly one of npc | enc
  if (hasNpc && !plausibleNpc(e.npc)) return null;
  let enc = null;
  if (hasEnc) {
    enc = cleanName(e.enc);
    if (!enc) return null;
  }
  if (e.size !== undefined
      && !(Number.isFinite(e.size) && e.size >= 0 && e.size <= 40)) return null;
  return hasNpc
    ? { k: "wipe", npc: e.npc, season: e.season }
    : { k: "wipe", enc, season: e.season };
}

// Calibration pairs (RUN-P): recompute the predicted odds exactly as the
// addon's coarse model does (RUN/model/odds.lua) - skull (cl -1) plays as
// player+10; skull and worldboss floor to 0.01; trivial/minus carry no
// penalty. The client's claimed p is kept ONLY as an advisory mean (sumPc);
// every published number derives from THIS recomputation (server-trust law).
const CAL_CLS = ["normal", "elite", "rare", "rareelite", "worldboss", "trivial", "minus"];

function recomputeCalibOdds(pl, cl, cls) {
  const creature = cl === -1 ? pl + 10 : cl;
  const z = 1.1 - 0.28 * (creature - pl) - (CLS_PENALTY[cls] || 0);
  let p = 1 / (1 + Math.exp(-z));
  if (cl === -1 || cls === "worldboss") p = 0.01;
  return p;
}

function validCalib(e) {
  if (!hasOnly(e, ["k", "npc", "pl", "cl", "cls", "p", "out", "season"])) return null;
  if (!plausibleNpc(e.npc) || !validSeason(e.season)) return null;
  if (!Number.isInteger(e.pl) || e.pl < 1 || e.pl > 100) return null;
  if (!Number.isInteger(e.cl) || e.cl < -1 || e.cl > 103) return null;
  if (typeof e.cls !== "string" || !CAL_CLS.includes(e.cls)) return null;
  if (!Number.isInteger(e.p) || e.p < 1 || e.p > 99) return null;
  if (e.out !== "win" && e.out !== "death") return null;
  return {
    k: "calib", npc: e.npc, out: e.out, season: e.season,
    p: recomputeCalibOdds(e.pl, e.cl, e.cls),   // trusted, recomputed
    pc: e.p / 100,                              // client-claimed, advisory only
  };
}

const VALIDATORS = { death: validDeath, slay: validSlay, sighting: validSighting, wipe: validWipe, calib: validCalib };

// ---- rollup helpers -----------------------------------------------------------
// Internal tallies live in `rareKillMeta` (no rules match block = default-deny =
// admin-only). The public projection in `rareKillCounts` is derived from the tally
// with MIN_BUCKET suppression, so clients only ever see pre-suppressed numbers.

function publicProjection(tally) {
  const counts = tally.counts || { pve: 0, pvp: 0, hc: 0 };
  const total = (counts.pve || 0) + (counts.pvp || 0) + (counts.hc || 0);
  const wipes = tally.wipes || 0;
  const base = { season: tally.season || "s0", updated: FieldValue.serverTimestamp() };
  if (tally.npc !== undefined) base.npc = tally.npc;
  if (tally.enc !== undefined) base.enc = tally.enc;
  // The k-of-n-verified creature name is game data (never a player), so it may
  // ride even suppressed docs; totals stay behind the MIN_BUCKET floor.
  const named = (typeof tally.name === "string" && tally.name.length > 0)
    ? { name: tally.name } : {};
  // Calibration rollup rides with its OWN bucket floor: only the derived rates
  // publish (fights + win% vs predicted%), never anything per-player.
  const cal = (tally.calib && (tally.calib.fights || 0) >= MIN_BUCKET)
    ? {
        calib: {
          fights: tally.calib.fights,
          winPct: Math.round((100 * tally.calib.wins) / tally.calib.fights),
          predPct: Math.round((100 * tally.calib.sumP) / tally.calib.fights),
        },
      }
    : {};
  if (Math.max(total, wipes) < MIN_BUCKET) {
    return { ...base, ...named, ...cal, low: true };  // suppressed: no totals below the floor
  }
  return { ...base, ...named, ...cal, counts, total, wipes };
}

// Apply one submission's events for a single rollup key inside a transaction.
// key: "123" (npc) or "enc:Name". deaths = {pve,pvp,hc} increments; wipes = n;
// sightings = [{ nm, clientId }].
async function applyToKey(key, delta) {
  const tallyRef = db.collection("rareKillMeta").doc(`tally-${key}`);
  const publicRef = db.collection("rareKillCounts").doc(key);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(tallyRef);
    const tally = snap.exists ? snap.data() : {};
    tally.season = delta.season || tally.season || "s0";
    if (delta.npc !== undefined) tally.npc = delta.npc;
    if (delta.enc !== undefined) tally.enc = delta.enc;
    const counts = tally.counts || {};
    for (const m of MODES) counts[m] = (counts[m] || 0) + (delta.deaths[m] || 0);
    tally.counts = counts;
    tally.wipes = (tally.wipes || 0) + (delta.wipes || 0);

    if (delta.calib && delta.calib.fights > 0) {
      const cal = tally.calib || { fights: 0, wins: 0, sumP: 0, sumPc: 0 };
      cal.fights += delta.calib.fights;
      cal.wins += delta.calib.wins;
      cal.sumP += delta.calib.sumP;
      cal.sumPc += delta.calib.sumPc;
      tally.calib = cal;
    }

    // Sighted-name k-of-n: a normalized name publishes once >= KOFN_NAMES distinct
    // clientIds reported it for this npc. Candidate + voter sets are capped.
    if (delta.sightings.length > 0) {
      const names = tally.names || {};
      for (const s of delta.sightings) {
        const norm = normName(s.nm);
        if (!names[norm] && Object.keys(names).length >= NAME_CANDIDATES_MAX) continue;
        const entry = names[norm] || { display: s.nm, clients: {} };
        if (Object.keys(entry.clients).length < 2 * KOFN_NAMES) {
          entry.clients[s.clientId] = true;
        }
        names[norm] = entry;
        if (!tally.name && Object.keys(entry.clients).length >= KOFN_NAMES) {
          tally.name = entry.display;
        }
      }
      tally.names = names;
    }

    tally.updated = FieldValue.serverTimestamp();
    tx.set(tallyRef, tally);
    tx.set(publicRef, publicProjection(tally));
  });
}

exports.rareKillsOnWrite = onDocumentCreated("rareKills/{id}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const d = snap.data();

  // Envelope validation (rules already shape-locked this; defence in depth).
  if (d.v !== 1 || !Array.isArray(d.kinds) || !Array.isArray(d.events)
      || d.events.length < 1 || d.events.length > MAX_EVENTS
      || !validSeason(d.season)
      || !d.kinds.every((k) => KINDS.includes(k))) {
    console.warn("[rareKills] envelope rejected", snap.id);
    return;
  }
  // The checksum is a tamper/truncation tell, not a secret; verify when present.
  if (d.sum !== undefined && d.sum !== fletcher16(canonical(d))) {
    console.warn("[rareKills] checksum mismatch; rejected", snap.id);
    return;
  }

  // Per-clientId rate limit: a doc counter per UTC day. Submissions without a
  // clientId share one "anon" bucket, so omitting the id never bypasses the cap.
  const cid = (typeof d.clientId === "string" && /^[0-9a-zA-Z-]{1,40}$/.test(d.clientId))
    ? d.clientId : "anon";
  const day = new Date().toISOString().slice(0, 10).replace(/-/g, "");
  const rlRef = db.collection("rareKillMeta").doc(`rl-${cid}-${day}`);
  const allowed = await db.runTransaction(async (tx) => {
    const doc = await tx.get(rlRef);
    const n = (doc.exists && typeof doc.data().n === "number") ? doc.data().n : 0;
    if (n >= RATE_MAX_PER_DAY) return false;
    tx.set(rlRef, { n: n + 1, updated: FieldValue.serverTimestamp() }, { merge: true });
    return true;
  });
  if (!allowed) {
    await snap.ref.delete();   // over the cap: no rollup, and the raw row is shed
    console.warn("[rareKills] rate limit hit; dropped", snap.id, cid);
    return;
  }

  // Deep-validate every event; invalid ones are skipped (never the whole batch:
  // one malformed row must not cost a player their honest events).
  const clean = [];
  for (const e of d.events) {
    if (!e || typeof e !== "object" || Array.isArray(e)) continue;
    const v = VALIDATORS[e.k];
    const ok = v ? v(e) : null;
    if (ok) clean.push(ok);
  }
  if (clean.length === 0) return;

  // Group into per-key rollup deltas.
  const deltas = new Map(); // key -> { npc?/enc?, season, deaths:{}, wipes, sightings:[] }
  const bucket = (key, seed) => {
    if (!deltas.has(key)) {
      deltas.set(key, {
        ...seed, deaths: { pve: 0, pvp: 0, hc: 0 }, wipes: 0, sightings: [],
        calib: { fights: 0, wins: 0, sumP: 0, sumPc: 0 },
      });
    }
    return deltas.get(key);
  };
  const slays = [];
  for (const e of clean) {
    if (e.k === "death") {
      bucket(String(e.npc), { npc: e.npc, season: e.season }).deaths[e.mode] += 1;
    } else if (e.k === "wipe" && e.npc !== undefined) {
      bucket(String(e.npc), { npc: e.npc, season: e.season }).wipes += 1;
    } else if (e.k === "wipe") {
      bucket(`enc:${normName(e.enc)}`, { enc: e.enc, season: e.season }).wipes += 1;
    } else if (e.k === "sighting") {
      bucket(String(e.npc), { npc: e.npc, season: e.season })
        .sightings.push({ nm: e.nm, clientId: cid });
    } else if (e.k === "calib") {
      const cal = bucket(String(e.npc), { npc: e.npc, season: e.season }).calib;
      cal.fights += 1;
      if (e.out === "win") cal.wins += 1;
      cal.sumP += e.p;
      cal.sumPc += e.pc;
    } else if (e.k === "slay") {
      slays.push(e);
    }
  }

  for (const [key, delta] of deltas) {
    await applyToKey(key, delta);
  }

  // The season calibration CURVE: recomputed-p deciles -> { fights, wins, sumP },
  // one doc per season in rareKillMeta (no rules match block = admin-only; the
  // daily review reads it with owner credentials). Counts only - k-anonymous.
  const curveBySeason = new Map();
  for (const e of clean) {
    if (e.k !== "calib") continue;
    const dec = `d${Math.min(9, Math.floor(e.p * 10))}`;
    if (!curveBySeason.has(e.season)) curveBySeason.set(e.season, {});
    const inc = curveBySeason.get(e.season);
    const slot = inc[dec] || { fights: 0, wins: 0, sumP: 0 };
    slot.fights += 1;
    if (e.out === "win") slot.wins += 1;
    slot.sumP += e.p;
    inc[dec] = slot;
  }
  for (const [season, inc] of curveBySeason) {
    const curveRef = db.collection("rareKillMeta").doc(`calcurve-${season}`);
    await db.runTransaction(async (tx) => {
      const snapC = await tx.get(curveRef);
      const cur = snapC.exists ? snapC.data() : { season, deciles: {} };
      const deciles = cur.deciles || {};
      for (const [dk, add] of Object.entries(inc)) {
        const slot = deciles[dk] || { fights: 0, wins: 0, sumP: 0 };
        slot.fights += add.fights;
        slot.wins += add.wins;
        slot.sumP += add.sumP;
        deciles[dk] = slot;
      }
      cur.deciles = deciles;
      cur.updated = FieldValue.serverTimestamp();
      tx.set(curveRef, cur);
    });
  }

  // Giant Slayers: ONLY the opt-in named tier, ONLY server-verified slays, and the
  // published pct is the RECOMPUTED one. Anonymous slays earn nothing public.
  const handle = d.named === true ? clampHandle(d.handle) : null;
  if (handle && slays.length > 0) {
    const honoured = slays.slice(0, SLAYS_MAX_PER_SUB);
    for (const s of honoured) {
      const entry = {
        handle,
        npc: s.npc,
        pct: Math.round(s.p * 100),
        tier: s.tier,
        season: s.season,
        updated: FieldValue.serverTimestamp(),
      };
      const tallySnap = await db.collection("rareKillMeta").doc(`tally-${s.npc}`).get();
      const name = tallySnap.exists ? tallySnap.data().name : undefined;
      if (typeof name === "string" && name.length > 0) entry.name = name;
      await db.collection("giantSlayers").add(entry);
    }
  }

  console.log("[rareKills] processed", snap.id,
    { events: clean.length, keys: deltas.size, slays: slays.length, named: !!handle,
      calib: clean.filter((e) => e.k === "calib").length });
});
