// Foresight crowd compare - companion site for the WoW: Forever addon.
// The addon never networks; this page only uploads what the user pastes, with consent.
// The Firebase config below is the public client config - access is controlled by the
// Firestore security rules, not by keeping it secret.

import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
import { initializeAppCheck, ReCaptchaEnterpriseProvider, getToken }
  from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app-check.js";
import { getAuth, signInAnonymously }
  from "https://www.gstatic.com/firebasejs/10.12.0/firebase-auth.js";
import { getFirestore, collection, addDoc, doc, getDoc, getDocs }
  from "https://www.gstatic.com/firebasejs/10.12.0/firebase-firestore.js";
// The allow-list contract, single-sourced (data/crowd-schema.json) and shared with the
// addon builder + the Firestore rules. Generated - see pipeline/gen_crowd_schema.py.
import { CROWD_SCHEMA } from "./crowd-schema.js";

const firebaseConfig = {
  apiKey: "AIzaSyDtlBj2Khodgq8d4aE2RKWwayPWrAeWwL8",
  authDomain: "wow-foresight.firebaseapp.com",
  projectId: "wow-foresight",
  storageBucket: "wow-foresight.firebasestorage.app",
  messagingSenderId: "443733238250",
  appId: "1:443733238250:web:08ab3b0176a78ae8c7d293",
  measurementId: "G-8VGTVWBLXR",
};
const app = initializeApp(firebaseConfig);

const RECAPTCHA_ENTERPRISE_SITE_KEY = "6LdlDe4tAAAAADDs-IpXu1osYeWMC2FcwKeiApQd";
let appCheck = null;
try {
  appCheck = initializeAppCheck(app, {
    provider: new ReCaptchaEnterpriseProvider(RECAPTCHA_ENTERPRISE_SITE_KEY),
    isTokenAutoRefreshEnabled: true,
  });
  console.info("[Foresight] App Check initialized");
} catch (e) {
  // Don't swallow silently - a failed init means writes carry no token and get
  // permission-denied, which looks like a rules bug but isn't.
  console.error("[Foresight] App Check init FAILED:", (e && (e.message || e.code)) || e);
}

// Make sure an App Check token is actually ready before a write (contribute/feedback):
// forces the fetch, eliminates the first-call race, and turns a silent permission-denied
// into a clear reason in the console. Returns "ok" or a short diagnostic string.
async function ensureAppCheck() {
  if (!appCheck) return "no-appcheck-instance (init failed - see console error above)";
  try { const t = await getToken(appCheck, false); return (t && t.token) ? "ok" : "empty-token"; }
  catch (e) { return "token-error: " + ((e && (e.code || e.message)) || e); }
}

const auth = getAuth(app);
const db = getFirestore(app);

// Allow-list + banned keys are the generated schema's - the SAME source the addon builder
// and the Firestore rules derive from, so the three can never drift apart.
const ALLOW = CROWD_SCHEMA.allow;
const BANNED = CROWD_SCHEMA.forbidden;
function sanitize(raw) {
  if (typeof raw !== "object" || raw === null) return null;
  if (raw.v !== CROWD_SCHEMA.version) return null;
  if (typeof raw.class !== "string" || !/^[A-Z]+$/.test(raw.class)) return null;
  if (!Number.isInteger(raw.level) || raw.level < 1 || raw.level > 200) return null;
  for (const b of BANNED) if (b in raw) return null;
  const out = {};
  for (const k of ALLOW) if (k in raw) out[k] = raw[k];
  // Identifying fields (handle/armory) require the explicit opt-in flag; strip them when
  // it's absent. The Firestore rules enforce the same gate server-side - this is defense
  // in depth + keeps anonymous payloads clean. Schema-driven so it tracks new tiers.
  if (out.named !== true) {
    for (const f of CROWD_SCHEMA.fields) if (f.tier === "identifying") delete out[f.key];
  }
  return out;
}

// Labels and class colours.
const METRIC_LABELS = {
  "stat.armor": "Most Armor", "stat.maxHealth": "Most Health",
  "stat.spellDamage": "Most Spell Power",
  "school.frost": "Most Frost Spell Damage", "school.fire": "Most Fire Spell Damage",
  "school.nature": "Most Nature Spell Damage", "school.shadow": "Most Shadow Spell Damage",
  "school.arcane": "Most Arcane Spell Damage", "school.holy": "Most Holy Spell Damage",
};
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
// Escape anything inserted into innerHTML - the ladder shows strings submitted by other
// users (metric keys, class), so this prevents HTML injection.
const esc = (s) => String(s == null ? "" : s).replace(/[&<>"']/g,
  (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
function metricLabel(k) {
  if (METRIC_LABELS[k]) return METRIC_LABELS[k];
  if (k.startsWith("ability:")) return "Biggest " + k.slice(8);
  if (k.startsWith("school.")) return "Most " + cap(k.slice(7)) + " Spell Damage";
  if (k.startsWith("stat.")) return "Most " + cap(k.slice(5));
  return "Most " + k;
}
const CLASS_COLORS = {
  WARRIOR: "#C79C6E", PALADIN: "#F58CBA", HUNTER: "#ABD473", ROGUE: "#FFF569",
  PRIEST: "#ffffff", SHAMAN: "#0070DE", MAGE: "#69CCF0", WARLOCK: "#9482C9", DRUID: "#FF7D0A",
};
const classColor = (c) => CLASS_COLORS[c] || "#c8a24c";
const titleCase = (c) => c ? c.charAt(0) + c.slice(1).toLowerCase() : c;

// Turn a stored quantile set into a percentile for the player's value.
function levelBucket(level) { return Math.floor(level / 5) * 5; }
function pctFromQuantiles(s, v) {
  const pts = [[s.min, 0], [s.p25, 25], [s.p50, 50], [s.p75, 75], [s.p90, 90], [s.max, 100]]
    .filter((p) => typeof p[0] === "number");
  if (pts.length < 2) return null;
  if (v <= pts[0][0]) return 0;
  if (v >= pts[pts.length - 1][0]) return 100;
  for (let i = 1; i < pts.length; i++) {
    if (v <= pts[i][0]) {
      const [x0, y0] = pts[i - 1], [x1, y1] = pts[i];
      return x1 === x0 ? y1 : y0 + (y1 - y0) * (v - x0) / (x1 - x0);
    }
  }
  return 100;
}

// UI wiring.
const $ = (id) => document.getElementById(id);
const statusEl = $("status");
function setStatus(msg, kind) { statusEl.textContent = msg || ""; statusEl.className = "status" + (kind ? " " + kind : ""); }
function parsePayload() {
  let raw = $("payload").value.trim();
  if (!raw) return null;
  // Accept a pasted share LINK (or a bare "#d=..." fragment), not only raw JSON - the
  // in-game instruction says you can paste the link right here, so honour that.
  const m = raw.match(/[#&]d=([^&\s]+)/);
  if (m) { try { raw = decodeURIComponent(m[1]); } catch { return null; } }
  try { return sanitize(JSON.parse(raw)); } catch { return null; }
}
let lastCompared = "";
function refreshButtons() {
  const p = parsePayload();
  const ok = p !== null;
  $("contribute").disabled = !(ok && $("consent").checked);
  const raw = $("payload").value.trim();
  // Named opt-in heads-up: if this payload carries the show-off opt-in, say plainly that the
  // chosen handle + build will be shown publicly on the ladders (policy-practice honesty).
  const notice = $("namedNotice");
  if (notice) {
    if (ok && p.named === true) {
      const who = (typeof p.name === "string" && p.name) ? `"${esc(p.name)}"` : "your chosen handle";
      notice.innerHTML = `You opted in to the public ladders: ${who}${p.armory ? " and your armory link" : ""} and your build will be shown publicly as a champion. Everyone else stays anonymous - turn it off in-game with <code>/foresight set named off</code>.`;
      notice.classList.remove("hidden");
    } else {
      notice.classList.add("hidden");
    }
  }
  if (!ok) {
    lastCompared = "";
    if (raw) setStatus("That doesn't look like valid /foresight share data.", "warn");
    else if (document.activeElement === $("payload")) setStatus("");
    return;
  }
  // Valid data: just show the standings - no separate "compare" button to click.
  if (raw !== lastCompared) { lastCompared = raw; setStatus(""); showCompare(p); }
}
$("payload").addEventListener("input", refreshButtons);
$("consent").addEventListener("change", refreshButtons);

// a percentile "row" with a gold fill bar + optional rank badge
function row(name, youText, pct, metaText) {
  const top = pct == null ? null : Math.max(1, Math.round(100 - pct));
  const badge = top == null ? "" :
    `<span class="badge${top <= 1 ? " rank1" : ""}">top ${top}%</span>`;
  const bar = pct == null ? "" : `<span class="bar"><i style="width:${Math.max(3, Math.round(pct))}%"></i></span>`;
  return `<div class="rowline"><span class="name">${esc(name)}${badge}</span>` +
    `<span class="val">${esc(youText)}</span>` +
    (metaText ? `<span class="meta">${esc(metaText)}</span>` : "") + bar + `</div>`;
}

// Compare: read the player's bucket and rank them in it.
async function showCompare(p) {
  const bucket = `${p.class}-${p.spec == null ? "any" : p.spec}-${levelBucket(p.level)}`;
  const resEl = $("result");
  resEl.classList.remove("hidden");
  resEl.style.setProperty("--class", classColor(p.class));
  try {
    const snap = await getDoc(doc(db, "aggregates", bucket));
    if (!snap.exists()) {
      resEl.innerHTML = `<h2>${esc(titleCase(p.class))} · level ${levelBucket(p.level)}+</h2>
        <p class="muted">No champions in your bracket yet - contribute and you'll set the first record.</p>`;
      return;
    }
    const agg = snap.data();
    if (agg.count && agg.count < (agg.minBucket || 5)) {
      resEl.innerHTML = `<h2>${esc(titleCase(p.class))} · level ${levelBucket(p.level)}+</h2>
        <p class="muted">Only ${agg.count} champion(s) here so far - not enough to rank (small brackets stay hidden). Check back soon.</p>`;
      return;
    }
    // TODAY'S CHALLENGES - your standing on the Daily Stat + your class's Daily Spell.
    const spell = dailySpellFor(p.class);
    const daily = [[dailyStatKey(), "Daily Stat"]];
    if (spell) daily.push(["ability:" + spell, "Daily Spell"]);
    const dailyKeys = new Set(daily.map(([k]) => k));
    let dailyHtml = "";
    for (const [key, kind] of daily) {
      const v = p.metrics && p.metrics[key];
      const s = agg.metrics && agg.metrics[key];
      if (typeof v === "number" && s) {
        dailyHtml += row(`${kind}: ${metricLabel(key)}`, Math.round(v), pctFromQuantiles(s, v), `record ${Math.round(s.max)} · n=${s.n}`);
      } else if (s) {
        dailyHtml += `<p class="meta"><b>${esc(kind)}: ${esc(metricLabel(key))}</b> - record ${Math.round(s.max)}; your submission didn't include it.</p>`;
      } else {
        dailyHtml += `<p class="meta"><b>${esc(kind)}: ${esc(metricLabel(key))}</b> - no mark in your bracket yet. Be the first.</p>`;
      }
    }

    // OVERALL - everything else you submitted (the two daily ones are shown above).
    let overall = "";
    for (const [id, val] of Object.entries(p.lenses || {})) {
      const s = agg.lenses && agg.lenses[id];
      if (!s) continue;
      overall += row(id, Math.round(val), pctFromQuantiles(s, val), `n=${s.n}, median ${Math.round(s.p50)}`);
    }
    for (const [k, val] of Object.entries(p.metrics || {})) {
      if (dailyKeys.has(k)) continue;
      const s = agg.metrics && agg.metrics[k];
      if (!s) continue;
      overall += row(metricLabel(k), Math.round(val), pctFromQuantiles(s, val), `record ${Math.round(s.max)} · n=${s.n}`);
    }
    resEl.innerHTML =
      `<h2>${raceClass(p)} · level ${levelBucket(p.level)}+ <span class="muted">(${agg.count} champions)</span></h2>` +
      `<div class="section-title">Today's Challenges</div>${dailyHtml}` +
      (overall ? `<div class="section-title">Overall Submissions</div>${overall}` : "") +
      `<p class="meta" style="margin-top:14px">Percentiles are approximate from the bracket's distribution (p).</p>`;
    resEl.scrollIntoView({ behavior: "smooth", block: "nearest" });
  } catch (e) {
    resEl.innerHTML = `<p class="warn">Couldn't load the ladder (${e.code || e.message}).</p>`;
  }
}

// Aggregates feed, shared by the daily trial and the ladders.
let AGG_CACHE = null;
async function loadAggregates() {
  if (AGG_CACHE) return AGG_CACHE;
  try {
    const qs = await getDocs(collection(db, "aggregates"));
    // Keep ALL buckets, including small ones. Small-bucket suppression is about VALUES
    // (percentiles/records), which the backend already strips - the COUNT is non-identifying
    // and safe to show, so a lone submission still appears in the tally instead of vanishing.
    AGG_CACHE = qs.docs.map((d) => d.data()).filter(Boolean);
  } catch (e) { AGG_CACHE = []; }
  return AGG_CACHE;
}

// Non-identifying tally across buckets (counts only). `minBucket`-suppressed buckets still
// count here; only their records/percentiles stay hidden until the bracket fills.
function tallyFor(aggs, klass) {
  let champions = 0, brackets = 0;
  for (const a of aggs) {
    if (klass !== "ALL" && a.class !== klass) continue;
    const c = typeof a.count === "number" ? a.count : 0;
    if (c > 0) { champions += c; brackets += 1; }
  }
  return { champions, brackets };
}

// ---- Daily challenges: two rotations, deterministic by day-of-year (everyone sees the
// same ones). (1) a class-agnostic Daily Stat, (2) a Daily Spell resolved PER CLASS. -------
function dayIndex() {
  const now = new Date();
  return Math.floor((now - new Date(now.getFullYear(), 0, 0)) / 86400000);
}
const DAILY_STATS = ["stat.armor", "stat.maxHealth", "stat.spellDamage",
  "school.frost", "school.fire", "school.nature", "school.shadow", "school.arcane", "school.holy"];
function dailyStatKey() { return DAILY_STATS[dayIndex() % DAILY_STATS.length]; }

// Each class's signature abilities; the metric key the addon shares is `ability:<name>`.
const CLASS_SPELLS = {
  WARRIOR: ["Mortal Strike", "Execute", "Overpower"],
  PALADIN: ["Judgement", "Holy Light", "Hammer of Wrath"],
  HUNTER:  ["Aimed Shot", "Arcane Shot", "Multi-Shot"],
  ROGUE:   ["Sinister Strike", "Eviscerate", "Backstab"],
  PRIEST:  ["Smite", "Greater Heal", "Mind Blast"],
  SHAMAN:  ["Earth Shock", "Lightning Bolt", "Healing Wave"],
  MAGE:    ["Fireball", "Frostbolt", "Arcane Missiles"],
  WARLOCK: ["Shadow Bolt", "Immolate", "Corruption"],
  DRUID:   ["Wrath", "Starfire", "Healing Touch"],
};
const CLASS_ORDER = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"];
function dailySpellFor(cls) {
  const list = CLASS_SPELLS[cls];
  return list ? list[dayIndex() % list.length] : null;
}
// Record for a metric across buckets (optionally class-scoped), from the aggregates.
function recordFor(aggs, metric, klass) {
  let best = null;
  for (const a of aggs) {
    if (klass && a.class !== klass) continue;
    const s = a.metrics && a.metrics[metric];
    if (s && typeof s.max === "number" && (!best || s.max > best.value)) best = { value: s.max, cls: a.class };
  }
  return best;
}

function renderDailyChallenges() {
  const aggs = AGG_CACHE || [], lb = LB_CACHE || new Map();
  // Daily Stat card
  const statKey = dailyStatKey();
  if ($("dailyStatTitle")) $("dailyStatTitle").textContent = metricLabel(statKey);
  if ($("dailyStatRecord")) {
    const rec = recordFor(aggs, statKey, null);
    $("dailyStatRecord").innerHTML = rec
      ? `Record <b>${Math.round(rec.value)}</b> &middot; ${esc(titleCase(rec.cls))}`
      : `<span class="muted">No mark yet - be the first to set it.</span>`;
  }
  // Daily Spell by Class list
  const list = $("dailySpellList");
  if (list) {
    list.innerHTML = CLASS_ORDER.map((cls) => {
      const spell = dailySpellFor(cls);
      if (!spell) return "";
      const metric = "ability:" + spell;
      const champ = (lb.get(metric) || []).filter((e) => e.class === cls).sort((a, b) => b.value - a.value)[0];
      const rec = champ ? null : recordFor(aggs, metric, cls);
      const lead = champ
        ? `<span class="cs-lead">${Math.round(champ.value)} <span class="cs-by">${charLabel(champ)}</span></span>`
        : rec ? `<span class="cs-lead">${Math.round(rec.value)}</span>`
        : `<span class="cs-none">be the first</span>`;
      return `<div class="cs-row" style="--class:${classColor(cls)}">
        <span class="cs-class">${esc(titleCase(cls))}</span>
        <span class="cs-spell">${esc(spell)}</span>${lead}</div>`;
    }).join("");
  }
}

// Named champions per metric (leaderboards/<metricKey>) - only opt-in named submissions.
let LB_CACHE = null;
async function loadLeaderboards() {
  if (LB_CACHE) return LB_CACHE;
  try {
    const qs = await getDocs(collection(db, "leaderboards"));
    LB_CACHE = new Map(qs.docs.map((d) => {
      const data = d.data() || {};
      return [data.metric || d.id, Array.isArray(data.entries) ? data.entries : []];
    }));
  } catch (e) { LB_CACHE = new Map(); }
  return LB_CACHE;
}

// Bucket lookup so a character's (class, level, value) resolves to a percentile in its
// bracket. Forever spec is "any" (talent-tree, no retail spec). Returns "top N%" or null
// when the bracket is too small / suppressed - we never fake a ranking.
function bucketIndex(aggs) {
  const m = new Map();
  for (const a of aggs) if (a.bucket) m.set(a.bucket, a);
  return m;
}
function topPctFor(idx, klass, level, metric, value) {
  const agg = idx.get(`${klass}-any-${levelBucket(level)}`);
  const q = agg && agg.count >= (agg.minBucket || 5) && agg.metrics && agg.metrics[metric];
  if (!q) return null;
  const pct = pctFromQuantiles(q, value);
  return pct == null ? null : Math.max(1, Math.round(100 - pct));
}

// Stat-type taxonomy for the ladder filter.
function statCategory(k) {
  if (k === "stat.armor" || k === "stat.maxHealth") return "survival";
  if (k.startsWith("stat.")) return "power";
  if (k.startsWith("school.")) return "school";
  if (k.startsWith("ability:")) return "ability";
  return "other";
}
const STAT_TYPES = [["all", "All stats"], ["survival", "Survival"], ["power", "Spell power"],
  ["school", "Spell schools"], ["ability", "Abilities"]];

// Race token -> readable label. Tokens are locale-free CamelCase ("NightElf", "Scourge");
// map the few that differ from their common name, else split CamelCase ("NightElf" -> "Night
// Elf"). Shown the moment the addon sends it; absent on older submissions (falls back cleanly).
const RACE_LABELS = { Scourge: "Undead", NightElf: "Night Elf", Skyborne: "Skyborne" };
function raceLabel(r) {
  return r ? (RACE_LABELS[r] || String(r).replace(/([a-z])([A-Z])/g, "$1 $2")) : "";
}
// "Orc Shaman" when race is known, else "Shaman" - used in the meta line + anon fallback.
function raceClass(e) {
  const cls = titleCase(e && e.class) || "Adventurer";
  return e && e.race ? esc(raceLabel(e.race) + " " + cls) : esc(cls);
}
// A character's primary label: chosen handle if named, else race + class (never a real name).
function charLabel(e) {
  if (e && typeof e.name === "string" && e.name) return esc(e.name);
  return raceClass(e);
}
function armoryWrap(e, inner, color) {
  const safe = (e && typeof e.armory === "string" && /^https:\/\//.test(e.armory)) ? e.armory : null;
  return safe
    ? `<a href="${esc(safe)}" target="_blank" rel="noopener noreferrer nofollow" style="color:${color}">${inner}</a>`
    : `<span style="color:${color}">${inner}</span>`;
}
function buffLine(e, cls) {
  const buffs = (e.buffs && typeof e.buffs === "object") ? Object.values(e.buffs) : [];
  return buffs.length ? `<span class="${cls}">with ${buffs.slice(0, 6).map((b) => esc(b)).join(", ")}</span>` : "";
}

// ---- THE LADDERS: one card per stat, character rows, filter by stat type + class ------
function renderLadders() {
  const board = $("ladderBoard");
  const aggs = AGG_CACHE || [];
  const lb = LB_CACHE || new Map();
  const idx = bucketIndex(aggs);
  const statType = $("statTypeFilter") ? $("statTypeFilter").value : "all";
  const klass = $("classFilter") ? $("classFilter").value : "ALL";

  const { champions, brackets } = tallyFor(aggs, klass);
  const forKlass = klass === "ALL" ? "" : " for " + esc(titleCase(klass));
  $("ladderTally").textContent =
    `${champions} character${champions === 1 ? "" : "s"} entered across ${brackets} bracket${brackets === 1 ? "" : "s"}${forKlass}. Records unlock once a bracket reaches 5.`;

  const metrics = new Set();
  for (const a of aggs) for (const k of Object.keys(a.metrics || {})) metrics.add(k);
  for (const k of lb.keys()) metrics.add(k);

  const cards = [];
  for (const metric of metrics) {
    if (statType !== "all" && statCategory(metric) !== statType) continue;
    let record = null;
    for (const a of aggs) {
      if (klass !== "ALL" && a.class !== klass) continue;
      const s = a.metrics && a.metrics[metric];
      if (s && typeof s.max === "number" && (!record || s.max > record.value))
        record = { value: s.max, cls: a.class, lvl: a.levelBucket };
    }
    const champs = (lb.get(metric) || [])
      .filter((e) => klass === "ALL" || e.class === klass)
      .slice().sort((a, b) => b.value - a.value).slice(0, 5);
    if (!record && !champs.length) continue;

    const color = record ? classColor(record.cls) : classColor(champs[0] && champs[0].class);
    const rows = champs.map((e, i) => {
      const top = topPctFor(idx, e.class, e.level, metric, e.value);
      const pct = top != null ? `<span class="pct">top ${top}%</span>` : "";
      return `<div class="lad-row" style="--class:${classColor(e.class)}">
        <span class="lad-rank">${i + 1}</span>
        <span class="lad-name">${armoryWrap(e, charLabel(e), classColor(e.class))}
          <span class="lad-meta">${raceClass(e)} · lvl ${esc(e.level)}</span>
          ${buffLine(e, "row-buffs")}</span>
        <span class="lad-val">${esc(Math.round(e.value))}${pct}</span></div>`;
    }).join("");
    const anonRow = (!champs.length && record)
      ? `<div class="lad-row anon" style="--class:${color}">
           <span class="lad-rank">★</span>
           <span class="lad-name">Anonymous
             <span class="lad-meta">${esc(titleCase(record.cls))} · lvl ${esc(record.lvl)}+</span></span>
           <span class="lad-val">${esc(Math.round(record.value))}</span></div>`
      : "";
    const recLine = record
      ? `Record ${esc(Math.round(record.value))} · ${esc(titleCase(record.cls))} ${esc(record.lvl)}+`
      : `${champs.length} champion${champs.length === 1 ? "" : "s"}`;
    cards.push({
      sort: record ? record.value : (champs[0] ? champs[0].value : 0),
      html: `<div class="lad-card" style="--class:${color}">
        <div class="lad-card-head"><h4>${esc(metricLabel(metric))}</h4>
          <span class="lad-record">${recLine}</span></div>
        ${rows || anonRow}</div>`,
    });
  }
  if (!cards.length) {
    board.innerHTML = `<p class="muted">No ladders here yet${forKlass} - be the first to answer the call.</p>`;
    return;
  }
  board.innerHTML = cards.sort((a, b) => b.sort - a.sort).map((c) => c.html).join("");
}

// ---- CHAMPIONS: each named character shown by the single stat they command best -------
function renderChampions() {
  const board = $("championBoard");
  if (!board) return;
  const aggs = AGG_CACHE || [];
  const lb = LB_CACHE || new Map();
  const idx = bucketIndex(aggs);
  const byChar = new Map();
  for (const [metric, entries] of lb) {
    for (const e of entries) {
      if (!e || typeof e.name !== "string" || !e.name) continue;
      const key = `${e.name}|${e.class}|${e.level}`;
      const top = topPctFor(idx, e.class, e.level, metric, e.value);
      const score = top != null ? (100 - top) : 0;
      const cur = byChar.get(key);
      if (!cur || score > cur.score || (score === cur.score && e.value > cur.e.value)) {
        byChar.set(key, { e, metric, top, score });
      }
    }
  }
  const champs = [...byChar.values()]
    .sort((a, b) => b.score - a.score || b.e.value - a.e.value).slice(0, 24);
  if (!champs.length) {
    board.innerHTML = `<p class="muted">No champion has stepped into the light yet - opt in in-game with <code>/foresight set named on</code> and a handle to be the first.</p>`;
    return;
  }
  board.innerHTML = champs.map(({ e, metric, top }) => {
    const color = classColor(e.class);
    const pct = top != null ? `<span class="pct">top ${top}%</span>` : "";
    return `<div class="champ-card" style="--class:${color}">
      <div class="champ-name">${armoryWrap(e, charLabel(e), color)}</div>
      <div class="champ-class">${raceClass(e)} · level ${esc(e.level)}</div>
      <div class="champ-stat">${esc(metricLabel(metric))}</div>
      <div class="champ-val">${esc(Math.round(e.value))}${pct}</div>
      ${buffLine(e, "champ-buffs")}</div>`;
  }).join("");
}

async function initLadders() {
  const [aggs] = await Promise.all([loadAggregates(), loadLeaderboards()]);
  const st = $("statTypeFilter");
  if (st) {
    st.innerHTML = STAT_TYPES.map(([v, l]) => `<option value="${v}">${esc(l)}</option>`).join("");
    st.addEventListener("change", renderLadders);
  }
  const cf = $("classFilter");
  if (cf) {
    const classes = ["ALL", ...Array.from(new Set(aggs.map((a) => a.class).filter(Boolean))).sort()];
    cf.innerHTML = classes.map((c) => `<option value="${esc(c)}">${c === "ALL" ? "All classes" : esc(titleCase(c))}</option>`).join("");
    cf.addEventListener("change", renderLadders);
  }
  renderLadders();
  renderChampions();
  renderDailyChallenges();
}

// Prefill from a share link (#d=<url-encoded JSON>).
function fromShareLink() {
  const m = (location.hash || "").match(/[#&]d=([^&]+)/);
  if (!m) return;
  try {
    $("payload").value = decodeURIComponent(m[1]);
    refreshButtons();
    const p = parsePayload();
    if (p) { setStatus("Loaded from your link - reading the omens…", "ok"); showCompare(p); }
  } catch (e) { setStatus("That share link looked malformed - paste your data manually.", "warn"); }
}

$("contribute").addEventListener("click", async () => {
  const p = parsePayload(); if (!p) return;
  setStatus("Signing the ledger…");
  try {
    await signInAnonymously(auth);
    const ac = await ensureAppCheck();
    if (ac !== "ok") console.warn("[Foresight] App Check not ready at contribute:", ac);
    setStatus("Entering you on the ladder…");
    await addDoc(collection(db, "contributions"), p);
    setStatus("Entered - your deeds are recorded. Reading the ladder…", "ok");
    AGG_CACHE = null; // the ladder just changed
    await showCompare(p);
  } catch (e) {
    console.error("[Foresight] contribute failed:", e);
    setStatus("Submission failed: " + (e.code || e.message) + " (see browser console for details).", "warn");
  }
});

// Feedback - writes to the `feedback` collection (separate from contributions, same
// project). Only what the user types is sent; contact is optional and opt-in.
const fbStatus = $("fbStatus");
function setFb(msg, kind) { if (fbStatus) { fbStatus.textContent = msg || ""; fbStatus.className = "status" + (kind ? " " + kind : ""); } }
function fbRefresh() {
  const b = $("fbSubmit");
  if (b) b.disabled = !($("fbMessage").value.trim().length > 0 && $("fbConsent").checked);
}
// Guard the wiring: a stale cached index.html (without the feedback markup) loading against
// this script must not throw on a missing element and halt the rest of app.js (the boot).
if ($("fbMessage")) $("fbMessage").addEventListener("input", fbRefresh);
if ($("fbConsent")) $("fbConsent").addEventListener("change", fbRefresh);
if ($("fbSubmit")) $("fbSubmit").addEventListener("click", async () => {
  const message = $("fbMessage").value.trim().slice(0, 2000);
  if (!message) return;
  const fb = { type: $("fbType").value || "other", message };
  const contact = $("fbContact").value.trim().slice(0, 120);
  if (contact) fb.contact = contact;
  // If they pasted a share link above, attach one line of non-identifying context.
  const p = parsePayload();
  if (p) fb.context = `${p.class || "?"} lvl ${p.level || "?"} v${p.build || "?"}`.slice(0, 300);
  setFb("Sending…");
  try {
    await signInAnonymously(auth);
    const ac = await ensureAppCheck();
    if (ac !== "ok") console.warn("[Foresight] App Check not ready at feedback:", ac);
    await addDoc(collection(db, "feedback"), fb);
    setFb("Sent - thank you. The team reads every one.", "ok");
    $("fbMessage").value = ""; $("fbContact").value = ""; $("fbConsent").checked = false;
    fbRefresh();
  } catch (e) {
    console.error("[Foresight] feedback failed:", e);
    setFb("Couldn't send: " + (e.code || e.message) + " (see browser console for details).", "warn");
  }
});

// Mobile nav: a collapsible menu (the ☰ toggle shows only at narrow widths via CSS).
const navToggle = $("navToggle"), navEl = document.querySelector(".nav");
if (navToggle && navEl) {
  navToggle.addEventListener("click", () => {
    const open = navEl.classList.toggle("open");
    navToggle.setAttribute("aria-expanded", open ? "true" : "false");
  });
  navEl.addEventListener("click", (e) => {
    if (e.target.closest(".nav-links a")) {
      navEl.classList.remove("open");
      navToggle.setAttribute("aria-expanded", "false");
    }
  });
}

// Boot.
initLadders();   // loads aggregates + leaderboards, then renders ladders + champions + dailies
fromShareLink();
