// Foresight crowd web app (S13). Account-safe companion: the WoW addon never
// networks; this page uploads ONLY what the user pastes from /foresight share,
// after explicit opt-in. Everything is re-validated client-side (defense in depth
// on top of the addon's allow-list) and gated server-side by firestore.rules.
//
// The apiKey below is a PUBLIC web identifier (not a secret) - security is the
// Firestore rules + App Check, not this key. Do NOT put Admin SDK / service-account
// credentials in this repo; those live only in Cloud Functions config.

import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
import { initializeAppCheck, ReCaptchaEnterpriseProvider }
  from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app-check.js";
import { getAuth, signInAnonymously }
  from "https://www.gstatic.com/firebasejs/10.12.0/firebase-auth.js";
import { getFirestore, collection, addDoc, doc, getDoc }
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

// App Check (abuse control) via reCAPTCHA Enterprise / "Fraud Defense" - the current
// App Check provider (classic reCAPTCHA v3 is retired for new projects). Create a
// reCAPTCHA Enterprise key (type: Website; domains: wow-foresight.firebaseapp.com,
// wow-foresight.web.app, localhost) in the App Check flow, then paste the SITE KEY
// (starts with 6L...) here. Until then, uploads stay denied by the rules' appChecked()
// guard - the safe default.
const RECAPTCHA_ENTERPRISE_SITE_KEY = "6LdlDe4tAAAAADDs-IpXu1osYeWMC2FcwKeiApQd";
try {
  initializeAppCheck(app, {
    provider: new ReCaptchaEnterpriseProvider(RECAPTCHA_ENTERPRISE_SITE_KEY),
    isTokenAutoRefreshEnabled: true,
  });
} catch (e) { /* App Check not configured yet; writes stay denied by rules */ }

const auth = getAuth(app);
const db = getFirestore(app);

// ---- client-side allow-list mirror (must match Foresight/core/crowd.lua) --------
const ALLOW = ["v", "build", "class", "spec", "level", "lenses", "talents",
               "items", "observed", "clientId"];
function sanitize(raw) {
  if (typeof raw !== "object" || raw === null) return null;
  if (raw.v !== 1) return null;
  if (typeof raw.class !== "string" || !/^[A-Z]+$/.test(raw.class)) return null;
  if (!Number.isInteger(raw.level) || raw.level < 1 || raw.level > 200) return null;
  const out = {};
  for (const k of ALLOW) if (k in raw) out[k] = raw[k];
  // hard strip: anything not allow-listed simply isn't copied. Reject if the input
  // tried to smuggle identity keys (surface it rather than silently clean).
  const banned = ["name", "realm", "account", "guild", "reports", "notes"];
  for (const b of banned) if (b in raw) return null;
  return out;
}

// ---- UI wiring ------------------------------------------------------------------
const $ = (id) => document.getElementById(id);
const statusEl = $("status");
function setStatus(msg, kind) {
  statusEl.textContent = msg;
  statusEl.className = "status" + (kind ? " " + kind : "");
}
function parsePayload() {
  try { return sanitize(JSON.parse($("payload").value.trim())); }
  catch { return null; }
}
function refreshButtons() {
  const ok = parsePayload() !== null;
  $("compare").disabled = !ok;
  $("contribute").disabled = !(ok && $("consent").checked);
  if (!ok && $("payload").value.trim())
    setStatus("That doesn't look like valid /foresight share data.", "warn");
  else setStatus("");
}
$("payload").addEventListener("input", refreshButtons);
$("consent").addEventListener("change", refreshButtons);

// ---- compare: read the pre-suppressed aggregate for this class/spec/level -------
function levelBucket(level) { return Math.floor(level / 5) * 5; } // 5-level buckets

// Estimate a value's percentile (0-100) from the bucket's stored quantiles, by
// piecewise-linear interpolation over (min,0) (p25,25) (p50,50) (p75,75) (p90,90)
// (max,100). "top ~N%" = 100 - percentile.
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
async function showCompare(p) {
  const bucket = `${p.class}-${p.spec ?? "any"}-${levelBucket(p.level)}`;
  const resEl = $("result");
  resEl.classList.remove("hidden");
  try {
    const snap = await getDoc(doc(db, "aggregates", bucket));
    if (!snap.exists()) {
      resEl.innerHTML = `<p>No peer data yet for <b>${p.class}</b> around level
        ${p.level}. Contribute and check back as the dataset grows.</p>`;
      return;
    }
    const agg = snap.data();
    if (agg.count && agg.count < (agg.minBucket ?? 5)) {
      resEl.innerHTML = `<p>Only ${agg.count} contributor(s) in your bracket so far -
        not enough to rank yet (we suppress small buckets). Check back soon.</p>`;
      return;
    }
    const rows = Object.entries(p.lenses || {}).map(([id, val]) => {
      const stats = agg.lenses ? agg.lenses[id] : null;
      if (!stats) return `<li><b>${id}</b>: ${val}</li>`;
      const pct = pctFromQuantiles(stats, val);
      const top = pct == null ? null : Math.max(1, Math.round(100 - pct));
      return `<li><b>${id}</b>: ${val}${top != null
        ? ` - <b>top ~${top}%</b> of your spec <span class="fine">(n=${stats.n}, median ${Math.round(stats.p50)})</span>`
        : ""}</li>`;
    }).join("");
    resEl.innerHTML = `<h2>Your spec, level ~${levelBucket(p.level)}+
      (${agg.count} contributors)</h2><ul>${rows}</ul>
      <p class="fine">Percentiles are approximate from the bracket's distribution (p).</p>`;
  } catch (e) {
    resEl.innerHTML = `<p>Couldn't load peer data (${e.code || e.message}).</p>`;
  }
}

$("compare").addEventListener("click", async () => {
  const p = parsePayload();
  if (p) await showCompare(p);
});

// Prefill from an in-game share link (#d=<url-encoded JSON>): the player copies one
// link in-game and pastes it into the address bar - the compare opens ready. The
// fragment is never sent to a server; contributing still needs the explicit opt-in.
(function fromShareLink() {
  const m = (location.hash || "").match(/[#&]d=([^&]+)/);
  if (!m) return;
  try {
    $("payload").value = decodeURIComponent(m[1]);
    refreshButtons();
    const p = parsePayload();
    if (p) { setStatus("Loaded from your link - comparing...", "ok"); showCompare(p); }
  } catch (e) { setStatus("That share link looked malformed - paste your data manually.", "warn"); }
})();

$("contribute").addEventListener("click", async () => {
  const p = parsePayload();
  if (!p) return;
  setStatus("Signing in anonymously...");
  try {
    await signInAnonymously(auth);
    setStatus("Uploading your contribution...");
    // Exactly the allow-listed payload - no extra keys (the rules' hasOnly() rejects
    // any addition, and a timestamp here would be both rejected and needless).
    await addDoc(collection(db, "contributions"), p);
    setStatus("Thanks - contributed. Loading your comparison...", "ok");
    await showCompare(p);
  } catch (e) {
    setStatus("Upload failed: " + (e.code || e.message)
      + " (App Check / Auth may not be enabled yet).", "warn");
  }
});
