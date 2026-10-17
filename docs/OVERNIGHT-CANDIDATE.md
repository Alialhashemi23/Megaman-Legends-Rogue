# Overnight candidate — not packaged or live

The shipped Windows/Web packages remain build 34 (`0e50a95`). These source
changes are being developed in two isolated branches. Integrate and validate
both before assigning a build number or replacing any download.

## New controls and playtest tools (Codex branch)

- Part and guardian-milestone offers have **one reroll per descent per digger**.
  Unused rerolls do not accumulate. Each offer can be rerolled once. Choose
  **Reroll**, press **R**, or press **Y** on an Xbox-style pad. Level-up stat
  cards cannot be rerolled. Closing, rejoining and reloading retain the cards
  and spent budget. A fresh press is required after a reroll.
- **Options → Controller test** shows the detected pad name/GUID, Godot axes
  and buttons, and raw browser mapping/axis/button values in the Web build.
  It changes no bindings or deadzones. A tests the button; B/Esc returns.
  Mouse/keyboard can select another pad or raw-data page. Native builds
  show Godot data; browser-only raw data is explicitly unavailable there.
- **Dig ended → Dig Log / Playtest** opens the last 20 local digs: the build
  at each first observed guardian fight, observed fight seconds, sampled Life
  lost, and picks/rerolls. Select a guardian to inspect its build. Build and
  pick pages reveal long records; Older/Newer selects another dig. This is
  device-local and is not uploaded to an account or added to co-op messages.
- Four painted part icons extend the existing atlas; the combat parts come
  from Claude's branch. Existing icon locations are preserved.
- Full co-op build updates for shot counters, cooldowns, Life and XP are
  coalesced to four per second. Durable build/choice changes and peer entry
  still send immediately; regular movement/shot traffic is unchanged.

### Reading the log

Guardian time counts observed live simulation, excluding Solo pauses and
connection gaps. A `*` marks an interrupted/partial fight, including reloads
and joining an already damaged guardian. A fight may start when its first
active/attack/damage state is observed, so it is not a synchronized host timer.
Life lost is the sum of observed positive Life drops after physics. Same-tick
healing can hide some damage, and overkill is capped by remaining Life. Treat
it as playtest evidence, not an exact damage meter. A replaced unfinished dig
is retained as interrupted; an active log is saved approximately every five
seconds and on picks/rerolls. The event list is bounded to the last 512 events
per dig, with total pick/reroll counts retained.

Desktop storage is `save/dig-log.json`; Web/Android use the game's `user://`
storage. A full disk or invalid log does not block progress or checkpoint
saving. The log has no account ids, player names, tokens or network addresses.

## Combat/content candidate (Claude branch, per its handoff)

Claude reports part-fairness tuning, additive level-up power/haste pools,
stronger later guardians with Overdrive helpers, Grenadier and Mender robots,
exposed guardian cores, B3 crumbling cover, a Power Relay event and four new
parts: Refractor Crystal, Flare Cartridge, Shatter Core and Overclock Relay.
The Relay vault gives each digger a better part offer. The combined reroll
implementation must retain that weighted offer rule.

These combat changes require **protocol 12**. Codex did not change the protocol
or add messages. The morning integrator must preserve Claude's protocol bump,
rebuild the relay/container for its account part gates, and produce matching
Web, Windows and signed Android packages. Build-34/protocol-11 APKs will not
join protocol-12 lobbies.

## Validation still required before delivery

Codex's focused native checks and disposable seven-role recovery journey pass
on its own branch. Native screenshots at 1440×900 and 960×540 were reviewed.
Synthetic controller data was used for the diagnostic previews. Both branches
still need combined focused checks and a real Relay/reroll recovery journey.
The actual exported browser build (including trusted-click mouse recapture),
signed-in co-op, physical Xbox/Elite, Retroid readability/performance and the
owner's playtest remain open. No export or package test was done overnight.

[Permanent gear proposal](GEAR-01-PROPOSAL.md) is design only and adds no gear.
