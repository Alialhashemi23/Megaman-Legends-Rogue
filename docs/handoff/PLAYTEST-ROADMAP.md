# Playtest and next-work handoff

The full prototype loop is implemented and automated checks pass. The user has reviewed recordings, but there is no recorded full human playtest yet. The next work should address concrete feedback rather than expanding systems indiscriminately.

## First human session

1. Play as helmet-off Mega. Walk, run, strafe, backpedal, jump and dash before shooting. Judge whether pass 07 feels compact and springy like Legends rather than stiff marching. Check boots and arm motion in actual play.
2. Fight with free aim and lock-on. Check camera collision near walls/doorways, muzzle visibility, target switching, cover and hit feedback. Note enemies or warnings that are hard to read.
3. Explore a branch before the guardian. Look for recognizable room functions, useful salvage and reasons to choose a route. Record empty or repetitive stretches.
4. Try stacking parts across a descent. Check whether descriptions make the effect understandable, upgrades change the build, and healing/caches create useful scrap decisions.
5. Defeat a guardian and descend. Check preparation/recovery windows, fairness, retained build, music changes and navigation to the lift. End the run deliberately to check recorded unlocks.
6. Repeat a short section with Roll. Check original-model presentation and the shared buster behavior. Test sound levels and menu readability at the intended monitor size.

## How to record useful feedback

For each issue, note character, descent, room or nearby landmark, weapon/parts, free aim versus lock-on, action taken, expected result and observed result. A short clip is useful for motion and camera problems. Record the seed if available. Do not overwrite personal saves to reproduce a bug; use isolated test profiles.

## Candidate improvements after feedback

| Area | Candidate work | Current status |
|---|---|---|
| Movement/camera | Tune cadence, transitions, distance and obstruction handling | Functional; newest motion pass needs human judgment |
| Combat readability | Tune warnings, guardian windows and target feedback | Three guardian attack mixes implemented |
| Exploration | Denser environmental storytelling, stronger room identities, secrets/puzzles | Five cover arrangements; puzzle design undecided |
| Progression | Drop frequency, stack balance, cache prices and unlock pacing | Complete prototype systems; balance unproven |
| Character expression | Additional faithful poses or per-character personality | Twelve authored clips for each; mechanics shared |
| Accessibility/input | Controller support and more settings | Not implemented |
| Run continuity | Mid-run resume | Implemented in pass 10 (checkpoints, Continue/Rejoin Dig); see NETWORK.md |
| Boss identity | Distinct meshes and silhouettes | Guardians currently share a base silhouette |

This list is a set of possibilities, not authorization to implement every feature. Prioritize the user's next request. Keep exploration unhurried, power reset between runs, the Legends art direction, and the existing playable loop intact.
