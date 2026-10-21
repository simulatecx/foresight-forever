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
    // DAILY ACHIEVEMENT - today's featured challenge (same day-of-year pick as the hero)
    // and your standing on it, surfaced first.
    const now = new Date();
    const doy = Math.floor((now - new Date(now.getFullYear(), 0, 0)) / 86400000);
    const feat = FEATURED[doy % FEATURED.length];
    const fVal = p.metrics && p.metrics[feat.key];
    const fAgg = agg.metrics && agg.metrics[feat.key];
    let dailyHtml;
    if (typeof fVal === "number" && fAgg) {
      dailyHtml = row(feat.label, Math.round(fVal), pctFromQuantiles(fAgg, fVal), `record ${Math.round(fAgg.max)} · n=${fAgg.n}`);
    } else if (fAgg) {
      dailyHtml = `<p class="meta">Today's trial is <b>${esc(feat.label)}</b> - standing record ${Math.round(fAgg.max)}. Your submission didn't include it.</p>`;
    } else {
      dailyHtml = `<p class="meta">Today's trial is <b>${esc(feat.label)}</b> - no mark in your bracket yet. Be the first.</p>`;
    }

    // OVERALL SUBMISSIONS - everything you've submitted: all lenses + challenge metrics
    // (today's featured one is shown above, so it's skipped here).
    let overall = "";
    for (const [id, val] of Object.entries(p.lenses || {})) {
      const s = agg.lenses && agg.lenses[id];
      if (!s) continue;
      overall += row(id, Math.round(val), pctFromQuantiles(s, val), `n=${s.n}, median ${Math.round(s.p50)}`);
    }
    for (const [k, val] of Object.entries(p.metrics || {})) {
      if (k === feat.key) continue;
      const s = agg.metrics && agg.metrics[k];
      if (!s) continue;
      overall += row(metricLabel(k), Math.round(val), pctFromQuantiles(s, val), `record ${Math.round(s.max)} · n=${s.n}`);
    }
    resEl.innerHTML =
      `<h2>${esc(titleCase(p.class))} · level ${levelBucket(p.level)}+ <span class="muted">(${agg.count} champions)</span></h2>` +
      `<div class="section-title">Daily Achievement</div>${dailyHtml}` +
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

// Daily rotating trial - deterministic by day-of-year so everyone sees the same one.
const FEATURED = [
  { label: "Most Armor", key: "stat.armor" },
  { label: "Biggest Earth Shock", key: "ability:Earth Shock" },
  { label: "Most Frost Spell Damage", key: "school.frost" },
  { label: "Most Health", key: "stat.maxHealth" },
  { label: "Biggest Fireball", key: "ability:Fireball" },
  { label: "Most Fire Spell Damage", key: "school.fire" },
  { label: "Biggest Greater Heal", key: "ability:Greater Heal" },
];
async function renderDailyTrial() {
  const now = new Date();
  const doy = Math.floor((now - new Date(now.getFullYear(), 0, 0)) / 86400000);
  const f = FEATURED[doy % FEATURED.length];
  $("trialTitle").textContent = f.label;
  $("trialSub").textContent = "Top the ladder for this one and the crown is yours. Submit today if you're the highest!";
  const aggs = await loadAggregates();
  let best = null;
  for (const a of aggs) {
    const s = a.metrics && a.metrics[f.key];
    if (s && typeof s.max === "number" && (!best || s.max > best.max)) best = { max: s.max, cls: a.class };
  }
  if (best) {
    $("trialRecord").textContent = `Standing record: ${Math.round(best.max)} (${titleCase(best.cls)})`;
  } else {
    const t = tallyFor(aggs, "ALL");
    $("trialRecord").textContent = t.champions > 0
      ? `${t.champions} champion${t.champions === 1 ? "" : "s"} entered so far - the record unlocks when a bracket reaches 5.`
      : "No champion has answered yet - be the first.";
  }
}

// The ladders: every challenge record, filterable by class.
function ladderCardsFor(aggs, klass) {
  const rows = [];
  for (const a of aggs) {
    if (klass !== "ALL" && a.class !== klass) continue;
    const metrics = a.metrics || {};
    for (const [k, s] of Object.entries(metrics)) {
      if (typeof s.max !== "number") continue;
      rows.push({ label: metricLabel(k), record: Math.round(s.max), n: s.n,
        cls: a.class, lvl: a.levelBucket, color: classColor(a.class) });
    }
  }
  rows.sort((x, y) => y.record - x.record);
  return rows.slice(0, 40);
}
// Brackets still filling toward a record (count < 5): shown count-only so a contributor
// sees their submission landed, without exposing any suppressed value.
function fillingCardsFor(aggs, klass) {
  const rows = [];
  for (const a of aggs) {
    if (klass !== "ALL" && a.class !== klass) continue;
    const c = typeof a.count === "number" ? a.count : 0;
    const min = a.minBucket || 5;
    if (c > 0 && c < min) {
      rows.push({ cls: a.class, lvl: a.levelBucket, n: c, need: min - c, color: classColor(a.class) });
    }
  }
  rows.sort((x, y) => y.n - x.n);
  return rows.slice(0, 40);
}
function renderLadder(klass) {
  const board = $("ladderBoard");
  const aggs = AGG_CACHE || [];
  const { champions, brackets } = tallyFor(aggs, klass);
  const forKlass = klass === "ALL" ? "" : " for " + esc(titleCase(klass));
  const tally = `<p class="ladder-tally">${champions} champion${champions === 1 ? "" : "s"} answered across ${brackets} bracket${brackets === 1 ? "" : "s"}${forKlass}. Records unlock once a bracket reaches 5.</p>`;
  const rows = ladderCardsFor(aggs, klass);
  const cards = rows.map((r) =>
    `<div class="ladder-card" style="--class:${r.color}">
       <h4>${esc(r.label)}</h4>
       <span class="record">Record ${esc(r.record)}</span>
       <span class="sub"> · ${esc(titleCase(r.cls))} · level ${esc(r.lvl)}+ · ${esc(r.n)} champions</span>
     </div>`).join("");
  const filling = fillingCardsFor(aggs, klass);
  const fillingBlock = filling.length
    ? `<h4 class="ladder-subhead">Brackets filling</h4>` + filling.map((r) =>
        `<div class="ladder-card filling" style="--class:${r.color}">
           <h4>${esc(titleCase(r.cls))} · level ${esc(r.lvl)}+</h4>
           <span class="sub">${esc(r.n)} champion${r.n === 1 ? "" : "s"} · ${esc(r.need)} more to unlock the record</span>
         </div>`).join("")
    : "";
  if (!rows.length && !filling.length) {
    board.innerHTML = tally + `<p class="muted">No champions yet${forKlass} - be the first to answer the call.</p>`;
    return;
  }
  board.innerHTML = tally
    + (cards || `<p class="muted">No records unlocked yet${forKlass} - the first bracket to reach 5 sets one.</p>`)
    + fillingBlock;
}
// CHAMPIONS (S34c show-off tier): the named top-N for today's featured metric, from the
// backend `leaderboards/<metricKey>` doc (only opt-in named submissions appear here).
function championCard(e, rank) {
  const color = classColor(e.class);
  const name = esc(e.name || "Champion");
  const safeArmory = (typeof e.armory === "string" && /^https:\/\//.test(e.armory)) ? e.armory : null;
  const who = safeArmory
    ? `<a href="${esc(safeArmory)}" target="_blank" rel="noopener noreferrer nofollow" style="color:${color}">${name}</a>`
    : `<span style="color:${color}">${name}</span>`;
  const buffs = (e.buffs && typeof e.buffs === "object") ? Object.values(e.buffs) : [];
  const buffRow = buffs.length
    ? `<span class="champion-buffs">with ${buffs.slice(0, 8).map((b) => esc(b)).join(", ")}</span>` : "";
  return `<div class="ladder-card champion" style="--class:${color}">
    <h4><span class="champion-rank">#${rank}</span> ${who}</h4>
    <span class="record">${esc(Math.round(e.value))}</span>
    <span class="sub"> · ${esc(titleCase(e.class))} · level ${esc(e.level)}</span>
    ${buffRow}
  </div>`;
}
async function renderChampions() {
  const board = $("championBoard");
  if (!board) return;
  const now = new Date();
  const doy = Math.floor((now - new Date(now.getFullYear(), 0, 0)) / 86400000);
  const f = FEATURED[doy % FEATURED.length];
  try {
    const snap = await getDoc(doc(db, "leaderboards", f.key));
    const entries = (snap.exists() && Array.isArray(snap.data().entries)) ? snap.data().entries : [];
    if (!entries.length) {
      board.innerHTML = `<p class="muted">No champion has stepped forward for <b>${esc(f.label)}</b> yet - opt in in-game and be the first to claim it.</p>`;
      return;
    }
    board.innerHTML = `<h4 class="ladder-subhead">${esc(f.label)}</h4>` +
      entries.map((e, i) => championCard(e, i + 1)).join("");
  } catch (e) {
    board.innerHTML = `<p class="muted">Couldn't summon the champions (${esc(e.code || e.message)}).</p>`;
  }
}

async function initLadders() {
  const aggs = await loadAggregates();
  const sel = $("classFilter");
  const classes = ["ALL", ...Array.from(new Set(aggs.map((a) => a.class))).sort()];
  sel.innerHTML = classes.map((c) => `<option value="${esc(c)}">${c === "ALL" ? "All classes" : esc(titleCase(c))}</option>`).join("");
  sel.addEventListener("change", () => renderLadder(sel.value));
  renderLadder("ALL");
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

// Boot.
renderDailyTrial();
renderChampions();
initLadders();
fromShareLink();

// ===========================================================================
// THE DEADLIEST - RUN crowd boards (WP-C). Everything below is ADDITIVE; no
// code above this line changed. RUN ("Immersive Enemy Builder" - enemies grow
// with every player they fell) shares this Firebase project; these boards read
// the aggregated `rareKillCounts` + `giantSlayers` collections written by
// RUN's backend. Until those collections + read rules land, every fetch fails
// into graceful-empty. Tier thresholds, tier colours, and the deterministic
// title hash are ported VERBATIM from RUN/model/notoriety.lua +
// RUN/data/titles.lua - the same creature carries the same earned title here,
// in-game, and for everyone, forever.
// ===========================================================================

// Kills required to REACH each tier (1..10) - RUN/model/notoriety.lua THRESHOLDS.
const RUN_THRESHOLDS = [1, 2, 5, 10, 15, 25, 40, 60, 80, 100];
// Tier colours: ember -> blood as the legend grows (notoriety.lua TIER_COLORS,
// converted 0-1 floats -> hex). Index 0 = unranked grey.
const RUN_TIER_COLORS = [
  "#b3b3b3", "#f2d98c", "#ffc76b", "#ffb359", "#ff9e4d", "#ff8c47",
  "#ff7a42", "#ff6640", "#ff543d", "#ff453b", "#ff3333",
];
// The title pools, tier 1-10 - RUN/data/titles.lua, ported verbatim.
const RUN_TITLES = {
  1: ["the Blooded", "the Biter", "the Prowler", "the Snatcher",
      "the Creeper", "the First Cut"],
  2: ["the Scarred", "the Hungry", "the Stalker", "the Ambusher",
      "the Rabid", "the Vicious"],
  3: ["the Cruel", "the Savage", "the Mauler", "the Relentless",
      "the Grim", "the Gouger"],
  4: ["the Widowmaker", "Bonebreaker", "the Merciless", "Gravemaker",
      "the Butcher", "Fleshrender"],
  5: ["the Manslayer", "Skullkeeper", "Bloodreaper", "Corpsemaker",
      "the Dread", "the Hollowing"],
  6: ["Doomfang", "the Harrower", "Plaguebearer", "Soulrender",
      "the Nightstalker", "the Undying Hunger"],
  7: ["Herald of Ruin", "the Unkillable", "Dreadmaw", "Bane of the Living",
      "the Reaper's Hand", "the Long Dark"],
  8: ["Scourge of the Land", "the Deathless", "Harbinger of Sorrow",
      "the Devourer", "the Final Mistake", "Graveherald"],
  9: ["Death Incarnate", "the Worldbane", "the Inevitable",
      "Nightmare Made Flesh", "the Apocalypse Crawling", "Slaughter's Legend"],
  10: ["Death Itself", "the End of All Runs", "the Last Thing You See",
       "Azeroth's Reckoning", "the Unforgiven", "the Legend"],
};
function runTierFor(total) {
  total = Number(total) || 0;
  let tier = 0;
  for (let i = 0; i < RUN_THRESHOLDS.length; i++) {
    if (total >= RUN_THRESHOLDS[i]) tier = i + 1; else break;
  }
  return tier;
}
// Deterministic title: same npcID -> same name, for everyone, every session.
// Lua is 1-based: idx = ((id*97 + tier*131) % #pool) + 1, pool[idx]. In JS the
// same element is pool[(id*97 + tier*131) % pool.length].
function runTitleFor(npcID, tier) {
  tier = Math.min(Math.max(Number(tier) || 0, 0), 10);
  if (tier < 1) return null;
  const pool = RUN_TITLES[tier];
  if (!pool || !pool.length) return null;
  const id = Number(npcID) || 0;
  return pool[(id * 97 + tier * 131) % pool.length];
}
const runTierColor = (tier) =>
  RUN_TIER_COLORS[Math.min(Math.max(Number(tier) || 0, 0), 10)];

// One fetch per board, cached; any failure (collection absent, rules not live
// yet, offline) degrades to an empty board - never an error on the page.
let RUN_KILLS_CACHE = null, RUN_SLAYERS_CACHE = null;
async function loadRunBoards() {
  if (RUN_KILLS_CACHE && RUN_SLAYERS_CACHE) return;
  const read = async (name) => {
    try {
      const qs = await getDocs(collection(db, name));
      return qs.docs.map((d) => d.data()).filter(Boolean);
    } catch (e) { return []; }
  };
  [RUN_KILLS_CACHE, RUN_SLAYERS_CACHE] =
    await Promise.all([read("rareKillCounts"), read("giantSlayers")]);
}

const RUN_MODE_LABELS = { pve: "PvE", pvp: "PvP", hc: "Hardcore" };
function runCreatureName(d) {
  return (typeof d.name === "string" && d.name) ? d.name : "creature #" + (d.npc != null ? d.npc : "?");
}
// Giant-slayer odds arrive as ~pct to win. Tolerate both 22 and 0.22 encodings:
// anything under 1 is clearly a fraction (a wager only exists under 50%).
function runPct(p) {
  let v = Number(p);
  if (!Number.isFinite(v) || v < 0) return null;
  if (v > 0 && v < 1) v = v * 100;
  return Math.min(100, Math.max(0, Math.round(v)));
}

// DEADLIEST CREATURES rows: filtered by mode + season, ranked by kills.
// Suppressed docs ({low:true} - the backend's small-bucket gate) are tallied
// but never itemized, mirroring the armory's own suppression stance.
function deadliestRows(mode, season) {
  const rows = []; let suppressed = 0;
  for (const d of RUN_KILLS_CACHE || []) {
    if (typeof d !== "object" || d === null) continue;
    if (d.low === true) { suppressed += 1; continue; }
    if (season !== "ALL" && String(d.season) !== season) continue;
    const counts = (d.counts && typeof d.counts === "object") ? d.counts : {};
    const n = mode === "ALL"
      ? (typeof d.total === "number" ? d.total
         : (Number(counts.pve) || 0) + (Number(counts.pvp) || 0) + (Number(counts.hc) || 0))
      : (Number(counts[mode]) || 0);
    if (n <= 0) continue;
    const tier = runTierFor(n);
    rows.push({
      name: runCreatureName(d), n, tier, title: runTitleFor(d.npc, tier),
      wipes: Number(d.wipes) || 0, season: d.season, color: runTierColor(tier),
    });
  }
  rows.sort((a, b) => b.n - a.n);
  return { rows: rows.slice(0, 30), suppressed };
}
function renderDeadliestCreatures(mode, season) {
  const board = $("deadliestBoard");
  if (!board) return;
  const { rows, suppressed } = deadliestRows(mode, season);
  const suppNote = suppressed
    ? `<p class="muted">${esc(suppressed)} more creature${suppressed === 1 ? " is" : "s are"} gathering infamy in the dark - records show once enough reports verify.</p>`
    : "";
  if (!rows.length) {
    board.innerHTML = `<p class="muted">No legends born yet - the world has not begun keeping score${mode !== "ALL" ? " in " + esc(RUN_MODE_LABELS[mode] || mode) : ""}. Be careful out there.</p>` + suppNote;
    return;
  }
  board.innerHTML = rows.map((r) => {
    const title = r.title ? ` <span class="deadliest-title" style="color:${esc(r.color)}">&ldquo;${esc(r.title)}&rdquo;</span>` : "";
    const wipes = r.wipes > 0 ? ` · wiped ${esc(r.wipes)} group${r.wipes === 1 ? "" : "s"}` : "";
    const season2 = r.season != null ? ` · season ${esc(r.season)}` : "";
    return `<div class="ladder-card" style="--class:${esc(r.color)}">
       <h4>${esc(r.name)}${title}<span class="tier-tag" style="color:${esc(r.color)}">TIER ${esc(r.tier)}</span></h4>
       <span class="record">has killed ~${esc(r.n)} player${r.n === 1 ? "" : "s"}</span>
       <span class="sub">${wipes}${season2}</span>
     </div>`;
  }).join("") + suppNote;
}
// GIANT SLAYERS: the players who took the wager and won - lowest odds first.
function renderGiantSlayers(season) {
  const board = $("slayerBoard");
  if (!board) return;
  const rows = [];
  for (const d of RUN_SLAYERS_CACHE || []) {
    if (typeof d !== "object" || d === null) continue;
    if (season !== "ALL" && String(d.season) !== season) continue;
    if (typeof d.handle !== "string" || !d.handle) continue;
    const pct = runPct(d.pct);
    if (pct == null) continue;
    rows.push({
      handle: d.handle, creature: runCreatureName(d), pct,
      underdog: d.tier === "underdog", season: d.season,
    });
  }
  rows.sort((a, b) => a.pct - b.pct);
  if (!rows.length) {
    board.innerHTML = `<p class="muted">No one has beaten the odds yet - take the wager in-game with <code>RISK IT!</code> and your deed goes in the ledger.</p>`;
    return;
  }
  board.innerHTML = rows.slice(0, 30).map((r) => {
    const badge = r.underdog
      ? `<span class="slayer-badge underdog">Underdog</span>`
      : `<span class="slayer-badge">Giant Slayer</span>`;
    const season2 = r.season != null ? ` · season ${esc(r.season)}` : "";
    return `<div class="ladder-card" style="--class:${r.underdog ? "#ffb37a" : "#8dffc4"}">
       <h4>${esc(r.handle)}${badge}</h4>
       <span class="record">beat ${esc(r.creature)}</span>
       <span class="sub"> at ~${esc(r.pct)}% odds${season2}</span>
     </div>`;
  }).join("");
}
function renderRunBoards() {
  const mode = $("runModeFilter") ? $("runModeFilter").value : "ALL";
  const season = $("runSeasonFilter") ? $("runSeasonFilter").value : "ALL";
  renderDeadliestCreatures(mode, season);
  renderGiantSlayers(season);
}
async function initDeadliest() {
  // Element-guarded like the feedback wiring: a stale cached index.html without
  // the section must never throw and halt the page.
  if (!$("deadliestBoard") || !$("slayerBoard")) return;
  await loadRunBoards();
  const seasonSel = $("runSeasonFilter");
  if (seasonSel) {
    const seasons = new Set();
    for (const d of [...(RUN_KILLS_CACHE || []), ...(RUN_SLAYERS_CACHE || [])]) {
      if (d && d.season != null) seasons.add(String(d.season));
    }
    const sorted = Array.from(seasons).sort((a, b) => String(b).localeCompare(String(a), undefined, { numeric: true }));
    seasonSel.innerHTML = `<option value="ALL">All seasons</option>` +
      sorted.map((s) => `<option value="${esc(s)}">Season ${esc(s)}</option>`).join("");
    seasonSel.addEventListener("change", renderRunBoards);
  }
  if ($("runModeFilter")) $("runModeFilter").addEventListener("change", renderRunBoards);
  renderRunBoards();
}
initDeadliest();
