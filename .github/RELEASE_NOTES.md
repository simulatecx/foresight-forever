## 0.57.0 - why builds work

Foresight has always shown you what a talent does. Now it explains why a whole build
holds together - and starts learning from the builds players actually run.

**Every example build explains itself**
Open the planner's "Examples" list and hover a build: Foresight now shows its synergy
rationale - the levers it stacks ("3 talents push Fire damage"), the stat converters it
feeds, and the capstone it pays off into. You see why a build works before you load it,
for all nine classes, on both Forever and Classic Era.

**A listener for popular builds**
Behind the scenes, a new daily pipeline pulls candidate popular builds from public
sources, analyzes each one through Foresight's own synergy engine to explain why it
works, and queues it for human review. Approved builds become new example presets you
can load. Nothing is automated onto your character and nothing leaves your client - the
addon still only reads your sheet and gives advice.

**A sturdier Forever button**
The "Foresight Planner" button on the talent frame now re-checks for its home for a few
seconds after you log in, so it reliably appears even when the talent UI loads late. The
`/foresight planner` command and the character-sheet buttons remain independent ways in.

Also folds in the read-only RUN-bridge character-profile API (0.55-0.56) for the sibling
living-world addon - addon-to-addon only, nothing leaves the client.

Ship gate: Forever 309 checks, Classic 264. Display-and-advice only, official APIs only.
