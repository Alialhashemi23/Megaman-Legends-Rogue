# Claude: verify and ship polish P1/P2

> **Done 2026-10-15:** verified and shipped as build 23. Results are in
> HANDOFF.md and CHANGELOG.md. This brief is kept for reference.

## Start here

Work in **`D:\code repos\Megaman-Legends-Rogue`**, not the older OneDrive Codex
workspace. Read AGENTS.md, HANDOFF.md, then only relevant subsystem notes.
At handoff, HEAD is `0c88816` on `main`; P1/P2 and planning documents are local,
uncommitted edits. Inspect current status and preserve all concurrent work.

**No tests, Godot imports, renders, exports, packaging, pushes or deployments
have been performed for these changes.** The owner asked to avoid testing while
playing League. This document is a test plan, not evidence that the restriction
has been lifted. Run the checks once the owner says it is okay to resume testing.
Never use personal saves or the live account database as test fixtures.

## What changed

**P1 — `scripts/hud.gd`:**
- Workshop entry/character selection focuses the first affordable node, falling
  back to first unowned or first fitted node. Focus resolves during the next draw.
- Left/Right, horizontal stick and LB/RB switch Workshop diggers; C/Y also works.
- Credits moved from y=94 to y=274, clear of the title Dig Record panel.
- Title account label/caption now reflects auth state and pending profile
  requests, with width-limited text; no authentication/storage behavior changed.

**P2 — `scripts/art.gd`, `scripts/ruins.gd`, `assets/textures/`:**
- Three revised base SVGs (wall/floor/metal), six new SVGs (three machinery panels,
  border, floor seal, twelve-cell crest atlas), and a texture README.
- Distinct Archive/Garden/Core colors, existing lamp tints, wall/door/fixture
  signs and ceramic inlays. New `DiverArt.panels()` batches opaque QuadMeshes;
  `room_crest()` crops a 4-column/3-row atlas. Painted specular is now zero.
- Intended to be cosmetic: no new colliders/lights or gameplay RNG draws;
  protocol/checkpoint/profile versions were not changed. Verify that assumption.
- These are authored source assets, **not visually approved results**. Preserve
  the original painted PS1 Legends style and supplied character models.

The roadmap also adds **P7 animation/movement**, specifically the owner's report
that dash has no visible animation. Dash is NOT fixed in this pass. Existing
`character.gd` selects a dash clip; later investigate poses/blending/state timing.
Final balance moved to P8. Do not start new phases just to verify P1/P2.

## Focused verification order

1. Follow TECHNICAL.md's isolated runtime/profile setup. Import changed/new SVGs
   and run a headless parse/smoke check. Fix actual errors before rendering.
2. Run relevant UI/options/account checks from AUDIO-UI.md and ACCOUNT-SYNC.md.
   Add only focused regression coverage where it catches a real issue. Verify:
   - Workshop entry and each character tab, affordable/locked/completed trees,
     queued cloud purchases, mouse, keyboard, shoulders and held-stick input.
     Ensure focus does not jump back to tabs or buy for the wrong character.
   - Title at desktop and 960×600/Retroid-sized layouts, with/without saved digs.
     Credits/account/record/digger panels must not overlap; Start Dig stays default.
   - Guest, initial browser session check, signing in, restoring, offline restore,
     signed in + Synced/Saving/Offline, expired session and long display names.
     Stale request generations must not show a spurious account check.
3. Render representative rooms from all three descents using isolated saves.
   Inspect north/east/south/west panel orientation, atlas cell selection, texture
   import/mip behavior, door lintels, short hall spans, forks/dead ends, vaults,
   terraces and grand halls. Check clipping, z-fighting, stretched/mirrored art,
   floor seal visibility and overly bright/busy surfaces. Review with the actual
   character models visible. Repair visuals if they miss the Legends target.
4. Run relevant movement/cover/ruin checks. Verify seeded layouts, gameplay RNG
   outcomes, colliders and interaction positions still agree with the baseline.
   Check attack telegraphs and loot remain readable among new markings.
5. Measure representative browser/native frame times when the owner is no longer
   gaming. Compare like-for-like scenes; batching is not proof of a performance
   improvement. Do not attribute the reported frame drops to a cause without data.
6. Check browser loading and a focused two-player dig/rejoin after export. Only
   broaden suites for failures or changed shared behavior; no blanket suite rerun
   solely to establish context. Keep real Retroid checks explicitly pending if
   the hardware is unavailable.

## Ship after checks pass

The owner explicitly authorized updating this checkout, pushing GitHub **main**
at `https://github.com/Alialhashemi23/Megaman-Legends-Rogue`, and deploying each
completed phase to the existing local container behind **megaman.galosengen.dev**.
No additional deployment approval is required once the gaming/test restriction
is lifted. See POLISH-ROADMAP.md for the full completion workflow.

- Update handoffs/changelog to distinguish validated/shipped from pending.
- Export Windows `.pck`, run `tools/package-windows.ps1` and
  `tools/package-web.ps1`; ship matching Windows/web ZIPs and notices. Account for
  Android's shared content using its current handoff/signing/update policies.
- Review exact commit contents. Preserve existing edits and exclude secrets,
  saves, database data, backups, caches, raw captures and loose executables.
  Commit/push the tested changes to main without force-pushing or copying the
  old OneDrive tree over this checkout.
- Preserve `.env`'s account Compose overlays, PostgreSQL volumes, backups and
  Cloudflare Tunnel. Briefly announce the restart, then use the current equivalent
  of `docker compose up -d --build relic-diver`. Do not print resolved secrets or
  run `compose down -v`. No database/schema changes are intended in P1/P2.
- Verify local/public health, exact served pack against the export, browser boot,
  and affected lobby/account flows. Record commit/build and actual deploy result.
- Give the owner a mini explanation: changes, checks, live status, and what to try.

Useful references: ART-ANIMATION.md (P2 details), AUDIO-UI.md (P1 details),
POLISH-ROADMAP.md (phase order/shipping), ACCOUNT-SYNC.md and TECHNICAL.md.
