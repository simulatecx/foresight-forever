# Security Policy

Foresight is a display-and-advice-only WoW: Forever addon plus a companion web app for
crowd comparisons. We take account safety and user privacy seriously and welcome
responsible disclosure.

## Reporting a vulnerability

Please report privately - do **not** open a public issue for a security problem.

- Preferred: open a **GitHub private security advisory**
  (repo → Security → *Report a vulnerability*).
- Or email **admin@simulatecx.com** with "Foresight security" in the subject.

Include what you found, steps to reproduce, and the impact. We aim to acknowledge within
a few days and to fix confirmed issues before any public disclosure. If you'd like
credit, say so and we'll name you once a fix ships.

## In scope

- **The addon** (`Foresight/`): any way it could perform or enable a protected/automated
  action, read memory, inject input, modify game files, or send data on its own - all of
  which it is designed never to do (`pipeline/check_compliance.py` enforces this).
- **The companion web app** (`web/`) and **Firebase backend**: auth/App-Check bypass,
  Firestore rule gaps, a way to read raw contributions, write unvalidated data, XSS, or
  deanonymize a contributor.
- **The data contract**: any path by which identifying data (character name, realm,
  account, free text) could leave a player's machine or reach the dataset.

## Out of scope

- The Firebase web `apiKey` and the reCAPTCHA site key appearing in client code - these
  are **public client identifiers by design**; security is enforced by Firestore rules +
  App Check, not by their secrecy.
- Forking or copying the (MIT-licensed, public) source.
- Reports requiring a tampered/unofficial build - only builds from our official channels
  (CurseForge, Wago Addons, GitHub Releases) are supported.

## Our standing guarantees

- The addon uses official APIs only, never networks, and is statically scanned for
  automation/sandbox-escape on every release (the ship gate).
- Crowd data is non-identifying and aggregate-only; raw contributions are never publicly
  readable; small brackets are suppressed. Full design: `docs/S13-CROWD-BACKEND.md`.
