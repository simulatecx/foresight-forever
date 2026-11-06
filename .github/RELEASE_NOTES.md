## 0.59.0 - understand your character

**New here? Foresight reads your character for you.**
The first time you log in with Foresight installed, it gives you a plain-language read of
your character: your archetype and strongest lens, your biggest hits, what your talent
build actually stacks (and the payoff it builds toward), a hidden synergy your class can
exploit, and one quick coaching nudge. Want it again later? `/foresight insights`. It's
all advice, nothing is changed on your character, and it only greets you once.

**Learning from top players**
Now that the Forever Armory is live, the build listener can draw on top players' builds as
examples - ranked by rating, with Foresight's synergy analysis attached, and run through
human review before anything ships. It uses the build, never the player's identity. (The
hook is in place; it switches on once the armory endpoint is confirmed.)

Under the hood: the daily listener no longer files a duplicate review each day when nothing
has changed.

Ship gate: Forever 312 checks, Classic 266. Display-and-advice only, official APIs only.
