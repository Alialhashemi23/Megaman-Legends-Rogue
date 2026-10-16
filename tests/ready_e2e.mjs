// One heavy job: serial disposable relay sessions, each with two/four Godot clients.
// GODOT points to the engine. No live services, personal profiles or database.
import fs from "node:fs";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
import { createServer } from "../server/server.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const godot = process.env.GODOT;
if (!godot) throw new Error("Set GODOT to an engine executable.");
const folder = path.join(root, "save", `ready-e2e-${Date.now()}`);
fs.mkdirSync(folder, { recursive: true });

for (const [party, scenario] of [[2, "slow"], [4, "cancel"], [2, "failure"]]) {
  const session = `READY-${party}-${scenario}`;
  const app = createServer({ port: 0, log: () => {}, readiness: { countdownMs: 300, prepareTimeoutMs: 12000 } });
  const port = await app.listen();
  const events = [];
  const emit = app.registry.emit;
  app.registry.emit = (lobby, message) => { events.push(message); emit(lobby, message); };
  const children = [];
  let timer;
  try {
    const results = await Promise.race([
      Promise.all(Array.from({ length: party }, (_, n) => new Promise((resolve, reject) => {
        const index = n + 1;
        const caseFolder = path.join(folder, session);
        fs.mkdirSync(caseFolder, { recursive: true });
        const child = spawn(godot, ["--headless", "--path", root, "--script", "tests/ready_driver.gd", "--", `--server=ws://127.0.0.1:${port}/ws`, `--player-id=ready-${scenario}-${index}`, `--ready-index=${index}`, `--ready-party=${party}`, `--ready-scenario=${scenario}`, `--ready-session=${session}`, `--ready-folder=${caseFolder}`], {
          cwd: root, windowsHide: true,
          env: { ...process.env, APPDATA: path.join(caseFolder, `runtime-${index}`) },
          stdio: ["ignore", "pipe", "pipe"],
        });
        children.push(child);
        let log = "";
        child.stdout.on("data", data => { log += data.toString(); });
        child.stderr.on("data", data => { log += data.toString(); });
        child.on("error", reject);
        child.on("exit", code => {
          fs.writeFileSync(path.join(caseFolder, `p${index}.log`), log);
          const match = log.match(/READY_SESSION_PASS (.+)/);
          if (code !== 0 || !match || /SCRIPT ERROR|READY_SESSION_FAIL/.test(log)) return reject(new Error(`${session} P${index} exit=${code}\n${log}`));
          resolve(JSON.parse(match[1]));
        });
      }))),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`${session} timeout`)), 45000); }),
    ]);
    assert.equal(new Set(results.map(r => r.runId)).size, 1, "one world-run identity");
    assert.equal(new Set(results.map(r => r.seed)).size, 1, "same seed for all clients");
    assert.equal(events.filter(e => e.t === "launch_commit").length, 1, "one commit");
    if (scenario !== "slow") assert.ok(events.some(e => e.t === "launch_aborted"), "explicit failure/cancel tested");
    console.log(`READY_E2E_PASS ${party} players / ${scenario}: ${JSON.stringify(results)}`);
  } finally {
    clearTimeout(timer);
    for (const child of children) if (child.exitCode === null) {
      if (process.platform === "win32") spawnSync("taskkill", ["/PID", String(child.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" });
      else child.kill("SIGKILL");
    }
    await app.close();
  }
}
console.log(`READY_E2E_COMPLETE: logs and isolated saves in ${folder}`);
