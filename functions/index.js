// Foresight crowd aggregation (S13). Turns raw `contributions` into per-spec/level
// `aggregates` the web app reads to rank you against your spec. Runs with the Admin
// SDK (bypasses security rules - the ONLY writer of `aggregates`). Privacy law:
// aggregates carry NO clientIds and NO raw rows - only counts + per-lens quantiles,
// and only for buckets at/above MIN_BUCKET distinct contributors (small-bucket
// suppression). clientId is used here solely to dedup re-uploads, then discarded.

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

const MIN_BUCKET = 5; // suppress percentiles below this many distinct contributors
const MAX_READ = 50000; // pilot-scale cap; revisit with indexed per-bucket queries later
const LEADERBOARD_TOP_N = 25; // named champions shown per metric (S34c)
const LENS_IDS = ["spellcasting", "meleeDps", "rangedDps", "healing",
                  "survivability", "sustain", "threat", "tankability"];

const levelBucket = (lvl) => Math.floor(lvl / 5) * 5;
const bucketId = (c) => `${c.class}-${c.spec == null ? "any" : c.spec}-${levelBucket(c.level)}`;

// Quantiles from a sorted number array (linear interpolation). Compact + privacy-safe:
// we expose distribution shape, never individual values.
function quantiles(sorted) {
  const q = (p) => {
    const i = (sorted.length - 1) * p, lo = Math.floor(i), hi = Math.ceil(i);
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (i - lo);
  };
  return {
    n: sorted.length, min: sorted[0], p25: q(0.25), p50: q(0.5),
    p75: q(0.75), p90: q(0.9), max: sorted[sorted.length - 1],
    mean: sorted.reduce((a, b) => a + b, 0) / sorted.length,
  };
}

async function rebuild() {
  const snap = await db.collection("contributions").limit(MAX_READ).get();

  // Dedup by clientId (keep the newest by document create time); contributions with no
  // clientId each count once. clientId never leaves this function.
  const byClient = new Map();
  const anon = [];
  snap.forEach((doc) => {
    const d = doc.data();
    const ct = (doc.createTime && doc.createTime.toMillis) ? doc.createTime.toMillis() : 0;
    if (typeof d.clientId === "string") {
      const prev = byClient.get(d.clientId);
      if (!prev || ct > prev.ct) byClient.set(d.clientId, { d, ct });
    } else {
      anon.push(d);
    }
  });
  const rows = [...[...byClient.values()].map((x) => x.d), ...anon];

  // Group into buckets.
  const buckets = new Map();
  for (const c of rows) {
    if (!c.class || typeof c.level !== "number") continue;
    const id = bucketId(c);
    if (!buckets.has(id)) buckets.set(id, []);
    buckets.get(id).push(c);
  }

  // Firestore batches cap at 500 writes; chunk if needed (pilot rarely hits this).
  let batch = db.batch(), pending = 0;
  const flush = async () => { if (pending) { await batch.commit(); batch = db.batch(); pending = 0; } };

  for (const [id, members] of buckets) {
    const first = members[0];
    const base = {
      bucket: id, class: first.class, spec: first.spec == null ? null : first.spec,
      levelBucket: levelBucket(first.level), count: members.length,
      minBucket: MIN_BUCKET, updatedAt: FieldValue.serverTimestamp(),
    };
    let doc = base;
    if (members.length >= MIN_BUCKET) {
      const lenses = {};
      for (const lid of LENS_IDS) {
        const vals = members.map((m) => m.lenses && m.lenses[lid])
          .filter((v) => typeof v === "number").sort((a, b) => a - b);
        if (vals.length >= MIN_BUCKET) lenses[lid] = quantiles(vals);
      }
      // CHALLENGE METRICS: dynamic key set (union across members) - any metric with
      // enough values gets quantiles. `max` is the current challenge record.
      const metrics = {};
      const metricKeys = new Set();
      for (const m of members) {
        if (m.metrics) for (const k of Object.keys(m.metrics)) metricKeys.add(k);
      }
      for (const k of metricKeys) {
        const vals = members.map((m) => m.metrics && m.metrics[k])
          .filter((v) => typeof v === "number").sort((a, b) => a - b);
        if (vals.length >= MIN_BUCKET) metrics[k] = quantiles(vals);
      }
      doc = { ...base, lenses, metrics };
    }
    batch.set(db.collection("aggregates").doc(id), doc);
    if (++pending >= 450) await flush();
  }

  // NAMED LEADERBOARDS (S34c show-off tier): top-N per metric drawn ONLY from opt-in
  // `named` submissions. Anonymous rows still feed the quantiles above but never appear as
  // a named row. These docs are public-readable (leaderboards/{metricKey}); they carry a
  // CHOSEN handle (not a real name), class/level, the value, an optional armory link, and
  // buff provenance - never a clientId, never PII. The metric key is a valid Firestore doc
  // id (no "/" in any key: stat.armor, school.frost, "ability:Earth Shock").
  const named = rows.filter((c) => c.named === true && typeof c.name === "string"
    && c.name.length > 0 && c.class && typeof c.level === "number");
  const boards = new Map(); // metricKey -> [{ value, class, level, name, armory, buffs }]
  for (const c of named) {
    if (!c.metrics) continue;
    for (const [k, v] of Object.entries(c.metrics)) {
      if (typeof v !== "number") continue;
      if (!boards.has(k)) boards.set(k, []);
      boards.get(k).push({
        value: v, class: c.class, level: c.level, name: c.name,
        armory: typeof c.armory === "string" ? c.armory : null,
        buffs: (c.buffs && typeof c.buffs === "object") ? c.buffs : null,
      });
    }
  }
  const seenMetrics = new Set();
  for (const [k, entries] of boards) {
    entries.sort((a, b) => b.value - a.value);
    batch.set(db.collection("leaderboards").doc(k), {
      metric: k, updatedAt: FieldValue.serverTimestamp(),
      entries: entries.slice(0, LEADERBOARD_TOP_N),
    });
    seenMetrics.add(k);
    if (++pending >= 450) await flush();
  }

  await flush();
  return { buckets: buckets.size, boards: seenMetrics.size };
}

// Recompute when a contribution lands (pilot: full rebuild; bounded by MAX_READ).
exports.aggregateOnWrite = onDocumentCreated("contributions/{id}", async () => {
  await rebuild();
});

// Safety-net daily rebuild (also recomputes suppression as buckets cross MIN_BUCKET).
exports.aggregateDaily = onSchedule("every 24 hours", async () => {
  await rebuild();
});
