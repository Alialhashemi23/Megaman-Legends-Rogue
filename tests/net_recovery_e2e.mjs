// Windows/POSIX runner for the existing net_driver mishap journey.
// One coordinated heavy job; every save/log is under its own isolated directory.
import fs from "node:fs";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
import { createServer } from "../server/server.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const godot = process.env.GODOT;
if (!godot) throw new Error("Set GODOT.");
const folder = path.join(root, "save", `net-recovery-${Date.now()}`);
fs.mkdirSync(folder, { recursive: true });
const lobby = `RECOVERY-${Date.now()}`;
let app = createServer({ port: 0, log: () => {}, readiness: { countdownMs: 300 } });
const port = await app.listen();
const children = [];
const logs = [];
function run(role, id) {
  const child = spawn(godot, ["--headless", "--path", root, "--", `--net-test=${role}`, `--player-id=${id}`, `--checkpoint-path=${path.join(folder, id + ".dat")}`, `--server=ws://127.0.0.1:${port}/ws`, `--lobby-name=${lobby}`], {
    cwd: root, windowsHide: true, env: { ...process.env, APPDATA: path.join(folder, `runtime-${role}`) }, stdio: ["ignore", "pipe", "pipe"],
  });
  children.push(child);
  let log = "";
  const record = data => { log += data.toString(); fs.appendFileSync(path.join(folder, role + ".log"), data); };
  child.stdout.on("data", record);
  child.stderr.on("data", record);
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${role} timed out\n${log}`)), 180000);
    child.on("error", reject);
    child.on("exit", code => {
      clearTimeout(timer);
      fs.writeFileSync(path.join(folder, role + ".log"), log);
      logs.push(log);
      if (code !== 0 || !log.includes(`NET_PASS ${role}`) || /SCRIPT ERROR|NET_FAIL/.test(log)) return reject(new Error(`${role} failed exit=${code}\n${log}`));
      console.log(`NET_RECOVERY_PASS ${role}`);
      resolve();
    });
  });
}
try {
  const host = run("host", "host-id");
  // Attach rejection handlers immediately while role ordering waits on peers.
  host.catch(() => {});
  const guest = run("guest", "guest-id");
  const late = run("late", "late-id"); late.catch(() => {});
  await guest;
  const guest2 = run("guest2", "guest-id"); guest2.catch(() => {});
  await host;
  const host2 = run("host2", "host-id");
  await Promise.all([guest2, late, host2]);
  await run("host3", "host-id");
  await app.close();
  app = createServer({ port, log: () => {} });
  await app.listen();
  await run("host4", "host-id");
  const all = logs.join("\n");
  for (const depth of [1, 2]) {
    const fingerprints = [...all.matchAll(/FINGERPRINT \w+ (.+)/g)].map(m => m[1]).filter(s => s.startsWith(`d=${depth} `));
    assert.equal(new Set(fingerprints).size, 1, `B${depth} generation agrees`);
  }
  const states = [...all.matchAll(/^STATE \w+ (.+)$/gm)].map(m => m[1]);
  assert.equal(new Set(states).size, 1, "server/local restored dig identity and state agree");
  console.log(`NET_RECOVERY_COMPLETE: 7 roles, logs in ${folder}`);
} finally {
  for (const child of children) if (child.exitCode === null) {
    if (process.platform === "win32") spawnSync("taskkill", ["/PID", String(child.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" });
    else child.kill("SIGKILL");
  }
  await app.close();
}
