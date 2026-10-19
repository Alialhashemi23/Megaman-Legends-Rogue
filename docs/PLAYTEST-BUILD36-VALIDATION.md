# Build 36 playtest validation

All P0/P1 cards in the owner's 2026-10-17 feedback are implemented. Each card
has its own implementation commit. PT-02 remains a proposal awaiting approval;
see [the stat proposal](PT-02-LEVEL-STATS-PROPOSAL.md). Phase 4 is deferred.

Checks use isolated profiles, APPDATA and browser contexts. No personal saves or
production accounts were used. Controller events are simulated; physical pad and
Retroid checks remain for owner playtesting.

| Check | Passing result |
|---|---|
| Menu input / Solo / Workshop Back | 15 checks |
| Guardian leash / damage / real B1 projectiles with Tron | 19 checks |
| Purchase selection, held input, atomic save, account op retry/conflict | 138 checks |
| UI / Options / progression / handheld | 94 / 46 / 311 / 256 checks |
| Variety, relay timing/frequency, legacy generation, fire cap/budget | 60 checks |
| Combat / guardian milestones | 7,784 / 59 checks |
| Checkpoint resume / co-op feedback / readiness | 31 / 60 / 57 checks |
| Audio | 67 checks |
| Relay/server + account progression rules | 40 + 7 tests |
| Source and packaged Windows game loop | Smoke pass |

Real local two-client tests cover victory, defeat, everyone down, a guest leaving,
same room code, Ready reset and another dig without rejoining. Both clients must
observe each other's cosmetic ignition; remote fires never apply duplicate damage.
The seven-role recovery journey also passes: guest refresh, late join, host crash
and migration, host return, empty-room resume and server-restart resume.

A headful Edge instance tested the ordinary production Web export: Options
fullscreen entry/exit, browser exit followed by re-toggle, inline Guest selection
and purchase, held input, one deduction and persisted reload. Native Windows
fullscreen/windowed transitions also passed. Browser Escape can be consumed just
after leaving fullscreen; the release test clicks Options Back to restore focus.

Native captures cover four fire ages, Workshop selection/receipt, results and Solo.
Web captures cover fullscreen, windowed, inline purchase, reload and Solo Back.
Captures and detailed logs stay in the worktree's ignored save directory.

Windows/Web archives were checked for corruption, path separators, excluded data
and license notices. Their embedded PCKs and the loose Windows PCK match:
`861bd507b060429b36fdbec82e2980f119b720c22bb4935e539990b01b3891bf`.
Pack resources exclude saves, tests, server, tools and backups, and include the
new fire resource and build-36 credits. Windows ZIP: 91,487,598 bytes; Web ZIP:
16,081,973 bytes. Published Android0.21.0 remains protocol12; a matching protocol13
APK is pending and was not built or published by this task.
