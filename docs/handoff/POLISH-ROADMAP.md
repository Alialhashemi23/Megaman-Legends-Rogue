# Polish roadmap — 2026-10-15

Status: P1–P6 are implemented and verified (builds 23–28) and pushed to `main`
(2026-10-15). All six are deployed; P6 went live after the owner's playtest
session. Next is P7 (dash
animation first). Still pending: owner sign-off on visuals and specialization or
milestone balance, browser frame-time measurement, Retroid checks and an Android
APK rebuild (needed for profile 4 and protocol 10).
Phase labels P0–P8 distinguish this work from the earlier account/Android roadmap.
Product decisions: [POLISH-PROGRESSION.md](POLISH-PROGRESSION.md).

## Current baseline and owner direction

The hosting checkout is `D:\code repos\Megaman-Legends-Rogue`. It is ahead of
the OneDrive planning workspace: inspected on 2026-10-15 at `0c88816`, branch
`main`, clean before adding this plan. Its handoff records deployed co-op map/
reward fixes, accounts and owner dashboard, plus merged Android support still
needing real Retroid testing. Do not reimplement those features from the older
workspace's handoff. Recheck current Git state before implementation.

Use the latest hosting checkout's playtest feedback, account/network handoffs,
and server rules. Preserve Claude's work and any changes made since this review.

Priorities: original PS1 Legends ruins and atmosphere; meaningful run builds;
a separate fully unlockable Sphere Grid-inspired Workshop per character; equal
solo/co-op support. Zenny buys connected nodes, one specialization is equipped
per dig, and routes never permanently close other branches.

Music feedback: the owner likes the current melodies and says the MIDI music
sounds good, but is only about **50% of the desired quality** and needs significant
polish. This is subjective owner feedback, not an objective measurement. Preserve
the recognizable melodies and original late-1990s adventure character while
improving arrangement, instruments, phrasing, dynamics, looping, and mix.

## Phases

| Phase | Work | Completion evidence |
|---|---|---|
| P0 — Reconcile the working baseline | Start from current hosting `main`; carry these planning decisions forward, inspect applicable instructions, and preserve concurrent work. Establish the existing build/deployment configuration without printing secrets. | Exact source/build baseline recorded; no older checkout copied over newer gameplay. This is preparation, not a separate feature deployment. |
| P1 — Visible UI fixes | Fix Workshop character-to-node focus, Credits/Dig Record overlap, and misleading account-state labels from the owner's playtest. Investigate reported frame drops with a focused browser/native comparison before changing rendering. | Controller and small-screen navigation work; signed-in, guest, restoring and offline states are accurate; performance findings distinguish measurements from hypotheses. |
| P2 — Legends ruins polish | Establish a representative room/passage treatment, then extend the successful visual language through all three descents: painted textures, mechanical landmarks, useful props, distinct palettes and restrained lighting. | Comparable in-game renders; original character/ruin styles agree; routes, shots and telegraphs stay readable; no material performance regression. |
| P3 — Music polish | Preserve all seven original cues and their melodic identities. Refine voicings, bass movement, percussion, call-and-response, MIDI articulation/velocity, instrument balance, transitions and seamless loops. Start with title and first-descent cues, then apply the treatment to the others. | Before/after audio excerpts and in-game listening; clean loops/crossfades, no clipping, and warnings remain audible. Update MIDI/composer sources and rendered runtime audio together. |
| P4 — Sphere Grid foundation | Four connected character grids with pan/zoom, controller navigation, node states, prerequisites and descriptions. Convert existing purchases without loss. Keep all paths eventually purchasable with Zenny. Update account-server rules and local profile migration together. | Each grid can reach 100%; old local/account progress survives; authoritative purchase validation, retry and sync agree with the client; readable on desktop and Retroid-sized layouts. |
| P5 — Character specializations | Populate meaningful character branches and implement one equipped specialization per dig, free switching between digs, and distinct solo/co-op-useful effects. Two specializations per character are the proposed initial scope. | Effects change gameplay, only the equipped branch's specialization effects apply, full-grid passive power stays modest, and reconnects preserve the exact build. |
| P6 — Guardian build milestones | Add major personal guardian rewards influenced by current parts, retaining frequent regular stacking upgrades. Reuse the already-shipped deferred selection flow. Resolve the final guardian reward's usefulness within the three-descent loop before shipping. | Useful offers for sparse and developed builds; clear effect descriptions and visuals; no duplicate rewards; effects reset each dig and survive co-op reconnects. |
| P7 — Animation and movement | Fix the owner's report that dash has no visible animation first. Then refine start/stop and directional transitions, foot placement, jump/landing motion and character personality using the supplied rigs. Inspect existing dash activation/blending as well as the authored clip. | A clearly visible dash onset, travel pose and recovery on every digger, locally and in co-op; compact Legends motion, responsive controls and steady buster aim. Judge actual movement footage when testing is allowed. |
| P8 — Balance and finish | Tune Zenny costs, full-grid progression, specialization tradeoffs, reward frequency, difficulty and presentation using actual play feedback. Address regressions across browser/Windows and compatible Android builds. | A coherent full run, visible progression over repeated digs, targeted co-op recovery checks, and a clear record of any real-device checks still awaiting the owner. |

P2/P3 can be reordered if the user prefers. P4 precedes P5; P5 precedes final
synergy balancing in P6. Ship complete, tested phases rather than half-wired menus.
Exact node counts, ability numbers and prices are tuning proposals, not settled
user requirements. No run-count promise for completing a grid has been made.

Save-code removal is in the older playtest feedback, with guest behavior still
open. Keep that as a small explicit scope decision rather than silently deleting
the only guest transfer route. Windows persistent sign-in is likewise separate
from fixing account labels. Neither should block unrelated phase work.

## Later content roadmap

After these phases, expand secrets and room events, distinctive enemies and boss
silhouettes/mechanics, additional character gadgets, and a small surface hub.
These are desired directions, not fully designed implementation commitments.
Accounts, Android and co-op map sharing already exist in the newer checkout;
remaining hardware testing is follow-through, not a new feature rebuild.

## Authorized completion workflow for each implemented phase

The user's 2026-10-15 instruction explicitly authorizes updating the hosting
checkout, pushing GitHub `main`, and deploying completed phases to the existing
local container at `https://megaman.galosengen.dev`. This supersedes older
"user deploys" / "ask before future deployments" notes for this scoped work.
No repeated deployment approval is needed. This planning turn does not deploy.

1. Implement against the latest hosting checkout or a safe working branch based
   on it. Inspect and preserve concurrent edits; never overwrite the hosting
   checkout with this older OneDrive tree or force-push `main`.
2. Run relevant checks and review the phase's actual gameplay, visuals or audio.
   Update handoffs, changelog and notices. Preserve personal saves and database
   progress. When changing schemas/account rules, follow current account ops,
   backup/migration and compatibility procedures.
3. Refresh `build/RelicDiver.pck`, `build/RelicDiver-Windows.zip` and
   `build/RelicDiver-Web.zip` with the project's export/package tools. Rebuild
   Android when shared gameplay/protocol/account changes require it; preserve
   existing signing and updater policies. No public GitHub release is authorized.
4. Review the exact commit contents, update GitHub
   `https://github.com/Alialhashemi23/Megaman-Legends-Rogue` **main**, and ensure
   `D:\code repos\Megaman-Legends-Rogue` contains the same tested commit and
   artifacts. Exclude secrets, saves, databases, backups, caches and raw captures.
5. Announce the impending restart briefly, since it interrupts live lobbies.
   From the hosting checkout, preserve the configured account Compose overlays,
   PostgreSQL volumes, backups and Cloudflare Tunnel. Use the current equivalent
   of `docker compose up -d --build relic-diver`; do not tear down the stack or
   replace tunnel configuration. Do not print resolved secret-bearing config.
6. Verify local and public health, the served build against the exported build,
   browser loading, and affected lobby/account flows. Health alone does not prove
   the new game shipped. If verification fails, repair or restore the previous
   compatible deployment without destroying data; report partial status honestly.
7. Give a short explanation: what changed, what was checked, commit/build, live
   deployment result, and what the owner should try (including a refresh when
   needed). Do not claim a push/deploy succeeded without tool confirmation.

This authorization is for this repository, existing local server and tunnel.
It does not authorize paid provisioning, monetization, publishing elsewhere, or
GitHub releases. If access becomes unavailable, finish independent local work
and state the specific remaining blocker.
