// Foresight crowd web app (S13). Account-safe companion: the WoW addon never
// networks; this page uploads ONLY what the user pastes from /foresight share,
// after explicit opt-in. Everything is re-validated client-side (defense in depth
// on top of the addon's allow-list) and gated server-side by firestore.rules.
//
// The apiKey below is a PUBLIC web identifier (not a secret) - security is the
// Firestore rules + App Check, not this key. Do NOT put Admin SDK / service-account
// credentials in this repo; those live only in Cloud Functions config.

import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
import { initializeAppCheck, ReCaptchaV3Provider }
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

// App Check (abuse control). Register a reCAPTCHA v3 site key in the Firebase
// console (App Check) and paste it here. Until then, uploads will be rejected by
// the rules' appChecked() guard - which is the safe default.
const RECAPTCHA_SITE_KEY = "TODO-RECAPTCHA-V3-SITE-KEY";
try {
  initializeAppCheck(app, {
    provider: new ReCaptchaV3Provider(RECAPTCHA_SITE_KEY),
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
      const pct = agg.percentileOf ? agg.percentileOf[id] : null; // function-provided
      return `<li><b>${id}</b>: ${val}${pct != null
        ? ` - top ~${100 - pct}% of your spec (p)` : ""}</li>`;
    }).join("");
    resEl.innerHTML = `<h2>Your spec, level ~${levelBucket(p.level)}+
      (${agg.count} contributors)</h2><ul>${rows}</ul>
      <p class="fine">Aggregate percentiles; (p) = presumed until the bracket is large.</p>`;
  } catch (e) {
    resEl.innerHTML = `<p>Couldn't load peer data (${e.code || e.message}).</p>`;
  }
}

$("compare").addEventListener("click", async () => {
  const p = parsePayload();
  if (p) await showCompare(p);
});

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
