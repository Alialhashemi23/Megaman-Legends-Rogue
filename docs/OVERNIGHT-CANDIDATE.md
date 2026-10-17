# Build 35 feature notes

Shipped in build 35 (protocol 12). Player-facing summary: build/CHANGELOG.md.
These notes keep the detail on rerolls, the controller test and the dig log.

## New controls and playtest tools

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

## Combat and content

Part-fairness tuning, additive level-up power/haste pools,
stronger later guardians with Overdrive helpers, Grenadier and Mender robots,
exposed guardian cores, B3 crumbling cover, a Power Relay event and four new
parts: Refractor Crystal, Flare Cartridge, Shatter Core and Overclock Relay.
The Relay vault gives each digger a better part offer. The combined reroll
implementation must retain that weighted offer rule.

These changes use **protocol 12**: build-34 / protocol-11 clients (including older APKs) can't join protocol-12 lobbies.
