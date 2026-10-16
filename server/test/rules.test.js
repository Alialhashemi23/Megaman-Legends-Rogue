// The account server re-implements the game's progression rules. These tests
// read the GDScript sources and fail if the two copies disagree.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { NODES, LINKS, START, PART_GATES, OLD_GATES, PROFILE_VERSION, connected, reward, validateProfile, validateOutcome, applyOutcome, buy, fresh, isEmpty } from "../accounts/rules.js";

const scripts = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "scripts");
const progression = fs.readFileSync(path.join(scripts, "progression.gd"), "utf8");
const game = fs.readFileSync(path.join(scripts, "game.gd"), "utf8");

test("grid nodes, costs and links match progression.gd", () => {
  const gd = [...progression.matchAll(/\{"id": "(\w+)", "name": "[^"]*", "cost": (\d+),/g)].map((m) => ({ id: m[1], cost: Number(m[2]) }));
  assert.deepEqual(gd, NODES);
  assert.deepEqual(JSON.parse(progression.match(/const LINKS = (\[.*\])/)[1]), LINKS);
  assert.match(progression, new RegExp(`const START = "${START}"`));
  assert.match(progression, new RegExp(`const VERSION = ${PROFILE_VERSION}\\b`));
});

test("every grid is one connected piece and old v2 trees stay valid", () => {
  const ids = NODES.map((n) => n.id);
  assert.ok(connected(ids), "the whole grid is reachable, so 100% is possible");
  for (const [a, b] of LINKS) assert.ok(ids.includes(a) && ids.includes(b));
  for (const tree of [["frame"], ["frame", "mobility"], ["frame", "salvage", "ability"], ["frame", "mobility", "salvage", "ability", "mastery"], ["frame", "salvage", "mobility"]])
    assert.ok(validateProfile({ version: 2, trees: { 0: tree } }), `v2 tree ${tree} survives`);
  let profile = { ...fresh(), zenny: 100000 };
  for (const id of ids) profile = buy(profile, 2, id).profile;
  assert.equal(profile.trees["2"].length, NODES.length, "the listed order buys the full grid");
  assert.equal(profile.zenny, 100000 - NODES.reduce((n, e) => n + e.cost, 0));
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
  assert.equal(validateProfile({ version: 5 }), null, "future versions are refused");
  assert.equal(validateProfile({ version: 2, wins: 2, runs: 1 }), null, "more wins than runs");
  assert.equal(validateProfile({ version: 2, deepest: 4 }), null);
  assert.equal(validateProfile({ version: 2, zenny: 1.5 }), null);
  assert.equal(validateProfile({ version: 2, trees: { 0: ["mobility"] } }), null, "missing prerequisite");
  assert.equal(validateProfile({ version: 2, trees: { 0: ["frame", "mobility", "mastery"] } }), null, "mastery is not linked to mobility");
  assert.equal(validateProfile({ version: 2, trees: { 4: ["frame"] } }), null, "no fifth digger");
  assert.equal(validateProfile({ version: 2, legacy_unlocks: ["lens"] }), null, "lens was never gated");
  const v1 = validateProfile({ version: 1, kills: 30, runs: 3 });
  assert.deepEqual(v1.legacy_unlocks.sort(), ["coil", "echo", "ember", "prism"], "v1 profiles keep what they had earned");
  assert.equal(v1.version, 4);
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
  assert.ok(buy(rich, 0, "mobility").error, "must link to an owned node");
  const one = buy(rich, 0, "frame").profile;
  assert.deepEqual([one.zenny, one.trees["0"]], [900, ["frame"]]);
  assert.ok(buy(one, 0, "frame").error, "already owned");
  assert.ok(buy({ ...one, zenny: 10 }, 0, "mobility").error, "not enough Zenny");
  assert.ok(buy(one, 4, "frame").error, "no fifth digger");
  assert.ok(buy(one, 0, "nope").error, "unknown node");
  assert.equal(buy(one, 1, "frame").profile.trees["1"][0], "frame", "trees are per digger");
  assert.equal(buy({ ...one, version: 2 }, 0, "plating").profile.version, 4, "buying upgrades the stored profile version");
  assert.ok(buy(one, 0, "barrel").error, "barrel links from plating or salvage, not frame");
  assert.ok(buy(buy(one, 0, "salvage").profile, 0, "barrel").profile, "a second route reaches the same node");
});
