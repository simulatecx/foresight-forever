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

// Keep this allow-list in sync with Foresight/core/crowd.lua.
const ALLOW = ["v", "build", "class", "spec", "level", "lenses", "metrics", "talents",
               "items", "observed", "clientId"];
function sanitize(raw) {
  if (typeof raw !== "object" || raw === null) return null;
  if (raw.v !== 1) return null;
  if (typeof raw.class !== "string" || !/^[A-Z]+$/.test(raw.class)) return null;
  if (!Number.isInteger(raw.level) || raw.level < 1 || raw.level > 200) return null;
  const banned = ["name", "realm", "account", "guild", "reports", "notes"];
  for (const b of banned) if (b in raw) return null;
  const out = {};
  for (const k of ALLOW) if (k in raw) out[k] = raw[k];
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
    AGG_CACHE = qs.docs.map((d) => d.data()).filter((d) => d && d.count >= (d.minBucket || 5));
  } catch (e) { AGG_CACHE = []; }
  return AGG_CACHE;
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
  $("trialRecord").textContent = best
    ? `Standing record: ${Math.round(best.max)} (${titleCase(best.cls)})`
    : "No champion has answered yet - be the first.";
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
function renderLadder(klass) {
  const board = $("ladderBoard");
  const aggs = AGG_CACHE || [];
  const rows = ladderCardsFor(aggs, klass);
  if (!rows.length) {
    board.innerHTML = `<p class="muted">No ladders yet${klass === "ALL" ? "" : " for " + esc(titleCase(klass))} - the records are empty until champions submit. Be the first.</p>`;
    return;
  }
  board.innerHTML = rows.map((r) =>
    `<div class="ladder-card" style="--class:${r.color}">
       <h4>${esc(r.label)}</h4>
       <span class="record">Record ${esc(r.record)}</span>
       <span class="sub"> · ${esc(titleCase(r.cls))} · level ${esc(r.lvl)}+ · ${esc(r.n)} champions</span>
     </div>`).join("");
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
initLadders();
fromShareLink();
