# PT-02 — level-up tuning proposal

**For owner approval; no stat-system implementation in build 36.** Run power
still resets each dig. Workshop bonuses and part unlocks stay permanent.

| Stat shown | One pick | Formula mapping |
|---|---|---|
| Life | +20 maximum Life; heal 20 | Existing `base_health += 20`; preserve each digger's starting Life and Workshop multipliers. |
| Armor | +18 armor points | Damage received / `(1 + 0.18 × Plating stacks + 0.18 × Armor picks)`; show actual reduction %. |
| Buster Power | +16 power points | Keep BAL-02 `power_picks`: damage = base × `(1 + 0.16 × [Lens stacks + Power picks])` × Workshop. |
| Rapid | +14 rapid points | Keep BAL-02 `haste_picks`: fire delay = weapon delay / existing multipliers / `(1 + 0.14 × [Spring stacks + Rapid picks])`. |
| Run Speed | +9 speed points | Speed = existing digger/Workshop base × `(1 + 0.09 × [Gyro Soles stacks + Speed picks])`. Dash cooldown stays separate. |
| Luck | +2.5 percentage points to part drops; +5 points to bonus-salvage chance | Existing part chance `7% + Clover × 2.5% + Scavenger × 5%`, plus Luck (Luck contribution capped at 25 points). Separate bonus roll grants +2 scrap per machine; chance capped at 50%. Ordinary guaranteed scrap stays. Rare drops can use Luck later. |

**Offers and rerolls.** Draw three distinct stats from these six at each level;
exclude Luck when both contributions are capped. Three free rerolls **per level**,
independent of the existing one part/milestone reroll per descent. Each reroll
changes at least one option, never spends scrap, and never resets on reconnect.

**One-screen layout.** Left: portrait and all six current stats. Right: three
cards showing the stat, exact gain and current → proposed value. Hover, arrows
or pad focus previews max Life/heal, actual damage reduction, buster damage,
shots/second, movement m/s or both drop chances. Footer: rerolls remaining,
Confirm and Back. Keep cobalt panels and the Handheld layout. Use direct copy
such as “Buster Power +16”; remove “like a Lens / like a Spring.”

**Migration and online.** Keep existing Life, Power and Rapid values exactly;
new Armor/Speed/Luck picks default to zero. Tag builds `stats_version: 2` and
store the new picks, exact pending offer, offer seed/counter and remaining level
rerolls in builds/checkpoints. Honor already queued old level offers until used.
Keep checkpoint envelope v3. A future implementation increments game protocol
13 → 14 so every client previews the same formulas; no account-schema change.

**Approval requested:** approve these six stats, values and three-reroll rule,
or specify changes before implementation.
