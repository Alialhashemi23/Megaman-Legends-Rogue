// The account server re-implements the game's progression rules. These tests
// read the GDScript sources and fail if the two copies disagree.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { NODES, PART_GATES, OLD_GATES, PROFILE_VERSION, reward, validateProfile, validateOutcome, applyOutcome, buy, fresh, isEmpty } from "../accounts/rules.js";

const scripts = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "scripts");
const progression = fs.readFileSync(path.join(scripts, "progression.gd"), "utf8");
const game = fs.readFileSync(path.join(scripts, "game.gd"), "utf8");

test("skill nodes, costs and prerequisites match progression.gd", () => {
  const gd = [...progression.matchAll(/\{"id": "(\w+)", "name": "[^"]*", "cost": (\d+), "requires": "(\w*)"/g)].map((m) => ({ id: m[1], cost: Number(m[2]), requires: m[3] }));
  assert.deepEqual(gd, NODES);
  assert.match(progression, new RegExp(`const VERSION = ${PROFILE_VERSION}\\b`));
  assert.match(progression, /id != "mastery" or "ability" in skills/, "mastery still needs the signature circuit");
});

test("part unlock gates match game.gd ITEMS and the legacy gates", () => {
  const items = Object.fromEntries([...game.matchAll(/^\t"(\w+)": \{"name": .*"unlock": (\d+)\}/gm)].map((m) => [m[1], Number(m[2])]));
  assert.deepEqual(items, PART_GATES);
  const old = progression.match(/const OLD_GATES = (\{[^}]*\})/)[1];
  assert.deepEqual(JSON.parse(old), OLD_GATES);
});

test("Zenny reward matches the formula in progression.gd", () => {
  assert.match(progression, /clampi\(depth, 1, 3\) \* 25 \+ clampi\(guardians, 0, 3\) \* 60 \+ clampi\(scrap, 0, 1000000\) \/ 5/);
  assert.equal(reward(1, 0, 0), 25);
  assert.equal(reward(3, 3, 37), 75 + 180 + 7);
  assert.equal(reward(9, 9, 4), 75 + 180 + 0);
});

test("profile validation follows the game's rules", () => {
  assert.deepEqual(validateProfile({ version: 2 }), fresh());
  assert.equal(validateProfile({ version: 3 }), null, "future versions are refused");
  assert.equal(validateProfile({ version: 2, wins: 2, runs: 1 }), null, "more wins than runs");
  assert.equal(validateProfile({ version: 2, deepest: 4 }), null);
  assert.equal(validateProfile({ version: 2, zenny: 1.5 }), null);
  assert.equal(validateProfile({ version: 2, trees: { 0: ["mobility"] } }), null, "missing prerequisite");
  assert.equal(validateProfile({ version: 2, trees: { 0: ["frame", "mobility", "mastery"] } }), null, "mastery without the circuit");
  assert.equal(validateProfile({ version: 2, trees: { 4: ["frame"] } }), null, "no fifth digger");
  assert.equal(validateProfile({ version: 2, legacy_unlocks: ["lens"] }), null, "lens was never gated");
  const v1 = validateProfile({ version: 1, kills: 30, runs: 3 });
  assert.deepEqual(v1.legacy_unlocks.sort(), ["coil", "echo", "ember", "prism"], "v1 profiles keep what they had earned");
  assert.equal(v1.version, 2);
  assert.ok(isEmpty(fresh()) && !isEmpty({ ...fresh(), runs: 1 }));
});

test("run outcomes are bounded and applied like finish_run()", () => {
  const ok = { won: false, depth: 2, guardians: 1, scrap: 37, kills: 41, run_time: 655.2, character: 1 };
  assert.ok(validateOutcome(ok));
  assert.equal(validateOutcome({ ...ok, guardians: 3 }), null, "more guardians than descents");
  assert.equal(validateOutcome({ ...ok, won: true }), null, "a win needs all three descents");
  assert.equal(validateOutcome({ ...ok, kills: 9999 }), null);
  assert.equal(validateOutcome({ ...ok, depth: 1.5 }), null);
  assert.equal(validateOutcome({ ...ok, won: "yes" }), null);
  const start = { ...fresh(), kills: 30, best_time: 900 };
  const lost = applyOutcome(start, validateOutcome(ok));
  assert.equal(lost.zenny, 50 + 60 + 7);
  assert.equal(lost.profile.zenny, 117);
  assert.equal(lost.profile.runs, 1);
  assert.equal(lost.profile.deepest, 2);
  assert.equal(lost.profile.best_time, 900, "only wins set the best time");
  assert.deepEqual(lost.newUnlocks.sort(), ["coil", "ember"]);
  const won = applyOutcome(start, validateOutcome({ ...ok, won: true, depth: 3, guardians: 3, run_time: 812.5 }));
  assert.equal(won.profile.wins, 1);
  assert.equal(won.profile.best_time, 812.5);
  const abandoned = applyOutcome(start, validateOutcome({ ...ok, abandoned: true }));
  assert.deepEqual([abandoned.zenny, abandoned.profile.runs, abandoned.profile.kills, abandoned.profile.deepest], [0, 0, 71, 0], "abandoned digs only add kills");
});

test("purchases check prerequisites and balance", () => {
  const rich = { ...fresh(), zenny: 1000 };
  assert.ok(buy(rich, 0, "mobility").error, "prerequisite");
  const one = buy(rich, 0, "frame").profile;
  assert.deepEqual([one.zenny, one.trees["0"]], [900, ["frame"]]);
  assert.ok(buy(one, 0, "frame").error, "already owned");
  assert.ok(buy({ ...one, zenny: 10 }, 0, "mobility").error, "not enough Zenny");
  assert.ok(buy(one, 4, "frame").error, "no fifth digger");
  assert.ok(buy(one, 0, "nope").error, "unknown node");
  assert.equal(buy(one, 1, "frame").profile.trees["1"][0], "frame", "trees are per digger");
});
