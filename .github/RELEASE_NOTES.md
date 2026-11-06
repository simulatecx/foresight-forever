## 0.60.0 - the character button, made reliable

**Fixes the missing Foresight button on the character sheet.**
On the launch client, the FS / Share / Options buttons on your character sheet could fail
to appear if the sheet's show signal was missed. Foresight now hooks the character-sheet
open directly and re-checks for a few seconds after login, so the buttons reliably show
whenever your character sheet is open. (The `/foresight` commands and the talent-frame
Planner button remain independent ways in.)

**Under the hood.** Kicked off a shared-element cleanup from an internal audit: the
green-up / red-down number coloring now runs through one shared helper so it stays
consistent everywhere, with the rest of the cleanup tracked for careful, verified
follow-ups. No visible change.

Ship gate: Forever 313 checks, Classic 267. Display-and-advice only, official APIs only.
