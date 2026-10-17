# GEAR-01 — small permanent-chip proposal

Design proposal only, 2026-10-17. No inventory, grants, schema, UI or combat
implementation is included. This turns the existing rare-find direction into
a bounded first experiment; it does not reopen the 80-question questionnaire.
Existing agreed rules remain: temporary run parts/power reset, persistent
unlocks remain, original PS1 art/menu direction, one equipped specialization,
no trading/paid pulls/random-affix crafting.

## Recommended first slice

Use **one chip slot per digger**, chosen before starting. Chips are handcrafted
named finds, account-owned when signed in and device-owned for Guest. Inventory
ownership can be shared across the four diggers, but each digger remembers its
own equipped chip. Start with **three utility chips**, one rarity and no chip
levels. Every dig remains viable with the slot empty.

Keep direct buster damage, fire rate, crits, elemental procs and starting part
counts untouched in this prototype. Set the initial power ceiling at **at most
5% of maximum Life in additional survival help per descent**, including any
chip/circuit interaction. No extra revives, invulnerability, milestone budget,
rerolls or account income. Evaluate this against a fully unlocked Workshop
baseline and the fragile Servbot, not just a new Mega character.

| Candidate | Identity and bounded behavior | Budget |
|---|---|---|
| Survey Chip | After clearing a chamber, briefly point toward its nearest unopened cache. No automatic opening, map completion or extra drops. | Information only; no combat/currency change |
| Salvage Magnet | When standing still for half a second, extend pickup reach by 2 m; return to normal reach as soon as movement resumes. Never collect another digger's reserved core. | Convenience; no extra entitlement, healing or loot rolls |
| Reserve Patch | Once per descent, a well can restore an extra 5% of your maximum Life. It still consumes the ordinary well use and cannot exceed maximum Life. | One small survival benefit, not an emergency revive |

These are prototype candidates, not an approved final catalogue. The current
Workshop already contains pickup utility; if Salvage Magnet feels redundant,
cut it rather than invent a stronger passive. Use the same cobalt inventory
windows and painted chip icons; avoid tier-color clutter and a separate hub.

## Find, secure and duplicate rules

Recommended: **secure on pickup**, retain on defeat. The rare find should feel
like something the player keeps, while temporary run power still resets.

Give each eligible digger one personal chip-find roll after B2's guardian,
with a proposed **15% chance per dig**. B3 is not a second roll. Present it as a
small world find/reveal after the fight, never interrupt combat with a full
screen. This cadence is provisional; start small and compare actual retention
and excitement after several playtests. There are no daily caps, streaks or
paid attempts.

Choose an unowned catalogue chip if any remain; when the catalogue is complete,
a duplicate gets a short repeat-discovery acknowledgement with **no currency,
upgrade materials or accumulating power**. Do not invent a conversion economy
before the small experiment proves fun. Reconnecting cannot change the roll or
turn a duplicate into another attempt.

Personal entitlement belongs to members who were present when the encounter
became active. A marked digger retains it across a dropout/rejoin; someone
joining after the guardian fell does not mint a new roll. One account in two
clients cannot claim twice. Solo follows the same rule. Offline Guest grants
are explicitly local and do not promise anti-cheat security.

## Persistence and account contract before code (GEAR-02)

The next design/implementation card must specify a catalogue version, inventory
ownership and per-digger equipment fields, backwards-compatible migration,
server grant receipts, and deterministic operation identities based on account,
dig and reward source. An operation settles once and returns the same receipt
on a lost response/retry. Equipment is checked against catalogue and ownership,
and a removed/invalid chip safely equips nothing without deleting other items.

Follow the existing Guest/account policy: a new/empty account can receive the
Guest profile once; signing into an established account keeps that account's
progress. Do not quietly union every device's Guest inventory into an existing
account or spend pending Zenny. Inventory migration needs its own tests and
must retain every existing circuit, specialization and part unlock.

**Authority limit:** the present relay does not simulate or prove guardian
kills. Idempotent account grants prevent duplicated settlement; they do not
make a client-reported kill trustworthy. GEAR-02 must explicitly choose the
casual host-attestation trust model with server-bounded one-per-dig eligibility,
or provide stronger encounter receipts. Do not describe a client-supplied
pickup id as secure proof. An online grant must remain pending if the service
cannot acknowledge it, and retry without changing the result.

Freeze the selected chip alongside the launch loadout after the future
contract is approved. Changing it must invalidate readiness through the same
existing party-consent system. **Do not add an ad hoc readiness protocol or
send unknown fields into ready_v1 today.** GEAR-02 must define the versioned
selection/build/checkpoint extension and compatibility gates together.

## Suggested delivery order and evidence

1. Approve or adjust this bounded proposal; keep GEAR-01 in proposal status.
2. GEAR-02: catalogue, migration and idempotent grant/eligibility contract; no art-heavy inventory yet.
3. GEAR-03: one slot, three chips, small reveal, equip preview and focused solo/duo/four-player checks.
4. GEAR-04: lost responses, offline/rejoin, duplicate-account clients, old saves,
   invalid equipment, new/veteran parties and physical handheld readability.

Accept the experiment only if an empty-slot newcomer remains useful, chip
choice changes a small habit, and duplicate discovery creates no chores.
Measure guardian time, survival help, join/recovery correctness and readability.
Keep a catalogue-level disable switch for the prototype; disabling a chip must
preserve inventory ownership and make equipment fall back safely.

The irreversible economy choices (security on pickup, slot count, entitlement,
power ceiling and duplicate conversion) remain explicitly proposed here. Broad
implementation discretion in the overnight UI track is not approval to ship a
new permanent economy. This file gives the owner a concrete proposal to review
when phase 4 is assigned.
