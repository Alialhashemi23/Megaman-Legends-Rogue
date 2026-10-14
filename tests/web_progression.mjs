// Real browser coverage for branding, Workshop purchases, save import and reload.
// Uses a fresh browser profile and a local server; never touches the live site.
import path from 'node:path';
import fs from 'node:fs';
import crypto from 'node:crypto';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { createServer } from '../server/server.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ? pathToFileURL(process.env.PLAYWRIGHT_MODULE).href : 'playwright');
const app = createServer({ port: 0, webRoot: path.join(root, 'build/web'), log: () => {} });
const port = await app.listen();
const base = `http://127.0.0.1:${port}`;
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'] });
const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: base });
const page = await context.newPage();
const errors = [];
const logs = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { logs.push(message.text()); if (/SCRIPT ERROR|Parse Error|Invalid access/.test(message.text())) errors.push(message.text()); });
const click = async (x, y) => { await page.mouse.click(x * 1280 / 1440, y * 800 / 900); await page.waitForTimeout(400); };
const screenshot = name => page.screenshot({ path: path.join(root, 'screenshots', `next-web-${name}.png`) });
try {
  let release;
  const gate = new Promise(resolve => release = resolve);
  await page.route('**/index.pck', async route => { await gate; await route.continue(); });
  await page.goto(base, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1500);
  await screenshot('loading');
  const icon = await page.locator('link[rel="icon"]').last().getAttribute('href');
  if (!icon.startsWith('volnutt-icon.png')) throw new Error('Volnutt favicon is missing');
  const response = await context.request.get(`${base}/${icon}`);
  if (!(await response.body()).equals(fs.readFileSync(path.join(root, 'assets/ui/icon.png')))) throw new Error('Favicon bytes differ from project icon');
  release();
  await page.locator('#loader').waitFor({ state: 'hidden', timeout: 120000 });
  await page.waitForTimeout(3000);
  await click(300, 874); // Workshop from title.
  await screenshot('workshop');
  await click(220, 854); // Save Codes.
  const profile = { version: 2, kills: 0, runs: 0, wins: 0, deepest: 0, discovered: {}, best_time: 0, zenny: 500, trees: {}, legacy_unlocks: [] };
  const body = JSON.stringify(profile);
  const code = `RD2.${Buffer.from(body).toString('base64')}.${crypto.createHash('sha256').update(body).digest('hex')}`;
  await page.evaluate(value => navigator.clipboard.writeText(value), code);
  await click(250, 593); // Explicit async browser clipboard paste.
  await page.waitForTimeout(1000);
  await click(530, 795); // Check code.
  await screenshot('import-preview');
  await click(860, 795); // Explicit replacement after preview.
  await click(1200, 795); // Back to Workshop.
  await click(1250, 390); // Reinforced Frame, 100 Zenny.
  await click(220, 854); // Save Codes.
  await page.evaluate(() => navigator.clipboard.writeText('WAITING FOR EXPORT'));
  await click(200, 795); // Export + clipboard.
  const readExport = async () => {
    const value = await page.evaluate(() => navigator.clipboard.readText());
    return JSON.parse(Buffer.from(value.split('.')[1], 'base64').toString());
  };
  let result = await readExport();
  if (result.zenny !== 400 || !result.trees['0'].includes('frame')) throw new Error(`Purchase/import failed: ${JSON.stringify(result)}`);
  const recoveryCode = await page.evaluate(() => localStorage.getItem('relicDiverProgressV2'));
  const recovery = JSON.parse(Buffer.from(recoveryCode.split('.')[1], 'base64').toString());
  if (recovery.zenny !== 400 || recovery.revision < 1) throw new Error('Synchronous recovery copy was not written');
  // Wait for the real IndexedDB commit, rather than guessing a disk-sync delay.
  await page.waitForFunction(async () => {
    for (const info of await indexedDB.databases()) {
      const result = await new Promise(resolve => {
        const request = indexedDB.open(info.name);
        request.onsuccess = () => {
          const db = request.result;
          const tx = db.transaction('FILE_DATA', 'readonly');
          const store = tx.objectStore('FILE_DATA');
          const keys = store.getAllKeys();
          const values = store.getAll();
          tx.oncomplete = () => {
            let saved = false;
            keys.result.forEach((key, i) => {
              if (String(key).endsWith('/archive.json')) {
                try { saved = JSON.parse(new TextDecoder().decode(values.result[i].contents)).zenny === 400; } catch {}
              }
            });
            db.close(); resolve(saved);
          };
        };
      });
      if (result) return true;
    }
    return false;
  }, null, { timeout: 60000 });
  // Simulate an interrupted primary write in this isolated browser profile.
  // The validated synchronous mirror must recover the purchase on reload.
  await page.evaluate(async () => {
    for (const info of await indexedDB.databases()) {
      await new Promise(resolve => {
        const request = indexedDB.open(info.name);
        request.onsuccess = () => {
          const db = request.result;
          const tx = db.transaction('FILE_DATA', 'readwrite');
          const store = tx.objectStore('FILE_DATA');
          const keys = store.getAllKeys();
          keys.onsuccess = () => keys.result.filter(key => String(key).endsWith('/archive.json')).forEach(key => store.delete(key));
          tx.oncomplete = () => { db.close(); resolve(); };
        };
      });
    }
  });
  const navigation = await page.reload();
  if (navigation.status() !== 200) throw new Error(`Reload returned HTTP ${navigation.status()}`);
  await page.locator('#loader').waitFor({ state: 'hidden', timeout: 120000 });
  await page.waitForTimeout(3000);
  await click(300, 874);
  await screenshot('saved-purchase');
  await click(220, 854);
  await page.evaluate(() => navigator.clipboard.writeText('WAITING FOR EXPORT'));
  await click(200, 795);
  result = await readExport();
  if (result.zenny !== 400 || !result.trees['0'].includes('frame')) throw new Error(`Purchase did not survive IndexedDB reload: ${JSON.stringify(result)}`);
  if (errors.length) throw new Error(errors.join('\n'));
  console.log('WEB_PROGRESSION_PASS: loading art, favicon, import preview, purchase, export, IndexedDB commit and interrupted-write recovery on reload');
} catch (error) {
  await screenshot('failure').catch(() => {});
  console.error(error);
  console.error(logs.slice(-30).join('\n'));
  process.exitCode = 1;
} finally {
  await browser.close();
  await app.close();
}
