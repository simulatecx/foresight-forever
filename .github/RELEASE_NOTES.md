## 0.64.0 - hybrids are hybrids

A hardening pass on spec awareness, matched to how players actually talk about builds.

**Hybrid builds get named properly.** A 20/21 split now reads "Arms/Fury hybrid (20/21/0)"
with the familiar X/Y/Z triplet - not "a Fury warrior by one point." Deep builds like
31/20 stay named by their deep tree, the way everyone names them. Hybrid characters get an
engine from either of their trees, honestly labeled.

**Classic Era fix.** Spec-aware engine selection silently didn't work on Classic Era (the
classic client reports talents by name only, and we were matching by internal id). Fixed -
your Era characters now get the spec-matched engine too.

**Small but real:** equal points in two trees now always resolve the same way, and the
character insights read leads with your spec identity ("Your build - Arms (12/0/0): ...").

Ship gate: Forever 321 checks, Classic 275. Display-and-advice only, official APIs only.
