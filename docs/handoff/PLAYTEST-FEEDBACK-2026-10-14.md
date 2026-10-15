# Owner playtest feedback — 2026-10-14

Two full runs by the owner after the phase 4–6 deployment. Verdict: "game is
good." The items below are the owner's notes, with code locations and open
questions. **None is implemented yet.** The skill-grid redesign is the next
feature candidate; the UI fixes are small and can go first.

## 1. Workshop skill tree → Final Fantasy X–style grid (feature)

**Owner:** "The skill tree is super lacking." Wants a Final Fantasy X Sphere
Grid–style skill grid.

**Today:** five nodes per digger in a fixed list (`scripts/progression.gd`
`NODES`): Reinforced Frame (+8% Life) → Lightweight Joints (+4% speed) and
Salvage Research (one signature part early) → Signature Circuit → Master
Mechanic (+5% attack speed). Drawn as rows in `scripts/hud.gd`
`draw_workshop()`. The server validates purchases with the same rules
(`server/accounts/rules.js` `buy`).

**What an FFX-style grid means here (proposal to confirm):**
- A board of connected nodes per digger. You unlock a node only if it's next to
  one you already own, so each digger grows along paths you choose instead of a
  fixed list.
- Node types: small stat nodes (Life, move speed, attack speed, buster damage,
  dash recovery), signature-ability upgrades, part research (adds parts to the
  early drop pool), and a few larger "key" nodes that open new branches.
- Paths that cross into another digger's area (like FFX characters wandering
  into each other's sections), e.g. Roll picking up some buster nodes.
- A cobalt Legends-style board with pan/zoom, a cursor that moves node to node
  with the controller, and a details panel. Readable on the Retroid's 5.5".

**Constraints from DESIGN.md:** run power still resets each dig; permanent
bonuses stay *modest* (pillar 5) so the grid adds options and identity rather
than raw power creep; keep the Legends look.

**Questions for the owner before building:**
1. One grid per digger, or one shared grid where each digger starts in its own
   area?
2. Currency: keep Zenny, or add a dig-earned item like FFX's spheres (e.g.
   salvaged "refractor" pieces), with Zenny for something else?
3. Roughly how big: about 20–30 nodes per digger, or a large board (60+)?
4. Should it allow a full or partial respec (refund), and at what cost?
5. Locked "key" nodes: gate them by depth reached, guardians beaten, or a
   rare drop?

**Technical impact:** needs profile `VERSION` 3 with a migration that refunds or
converts existing purchases; an additive server change (new grid rules and
purchase validation in `rules.js`, still `/api/v1`, old clients refused politely
instead of mis-buying); web, Windows and Android rebuilds; and a deploy. Game
protocol 7 is unaffected unless co-op needs to show grid bonuses.

## 2. Workshop navigation (bug)

**Owner:** picking a character doesn't move you into their skills. You have to
step through every character tab before focus reaches the skill list.

**Where:** `draw_workshop()` lays out the four character tabs
(`tree_character`), then the skill buttons (`buy_skill`). Focus follows hit
order, so the skills come after every tab. **Fix:** choosing a character tab
should jump focus to that digger's first available node. Left/Right or LB/RB
should switch digger from anywhere on the page. This also matters for the
grid redesign.

## 3. Title screen: Credits button covers the Dig Record (bug)

**Where:** `draw_title()` in `scripts/hud.gd`. The Dig Record panel is at
x 1080, y 32–136; *Credits / Licenses* is at x 1020, y 94–136, so they overlap
(visible in the owner's screenshot). **Fix:** move Credits out of that column,
e.g. into the left menu next to Options/Quit, or onto the Options page. Check
controller focus order and the Android layout afterwards.

## 4. Account button says "Sign In / Play as Guest" while signed in (bug/UX)

**Owner:** "I'm logged in but it shows me Sign In / Play as Guest."

**Where:** `draw_title()` shows that label whenever `game.profile_source ==
"guest"`, and the caption reads "Guest progress / this device". The label is
static: it doesn't say whether you're signed in.

**Likely causes to check (unconfirmed, need to know which build was used):**
- **Windows exe:** sign-ins are memory-only by design, so after restarting the
  exe you're signed out, even if the browser `/account` page is signed in.
- **Browser:** the game and the `/account` page share the cookie, so the game
  should switch to the account on load. If it still shows Guest, that's a real
  bug (check the startup `account.refresh()` result). Note that choosing *Play
  as Guest* in the browser currently signs the cookie session out.
- **Android:** restore may still be in progress or offline.

**Fix direction:** make the button reflect state ("Signed in as NAME" /
"Guest — Sign in to sync" / "Restoring account…"), and decide whether Windows
should remember sign-ins securely (Windows Credential Manager/DPAPI), which
phase 4 deliberately left out.

## 5. Remove save codes / backups (cleanup)

**Owner:** "Save codes/backups shouldn't be necessary any more."

**Where:** Workshop button *Save Codes / Backup* (`draw_workshop()`), the
`save_codes` page (`draw_save_codes()`), and the import/export and guest-adoption
logic it drives.

**Decision needed:** remove entirely, or keep only for Guests who never sign in
(offline-only players and moving Guest progress between devices). Account
progress is already server-side with encrypted daily backups, so for signed-in
players the page is redundant. Guest-to-account adoption also offers "use this
PC's progress", which doesn't need save codes. Removing them changes docs,
tests (`tests/progression_checks.gd` save-code checks, UI checks) and the
README.

## 6. Performance on the owner's PC (investigate)

Friends report good performance; the owner sees frame drops on an RTX 4090
with Docker, Bambu Studio and several Claude/Codex sessions running. The GPU
isn't the limit for this scene. Next steps: compare the Windows exe with the
browser build, confirm the browser uses hardware WebGL2 (`chrome://gpu`),
note when drops occur (always / combat / entering rooms). Optional: add a
frame-time overlay plus frame cap, V-Sync and resolution scale to Options so
players can measure.

## Suggested order

1. Small UI fixes: Credits overlap (3), Workshop focus (2), account button
   state (4).
2. Save-code decision and cleanup (5).
3. Owner answers the grid questions (1), then design → implement on its own
   branch.
4. Performance overlay if the exe comparison still shows drops (6).
