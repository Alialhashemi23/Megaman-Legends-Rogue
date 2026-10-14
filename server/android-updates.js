// Operator-staged immutable Android files; no publication or auto-download.
import fs from 'node:fs';
import path from 'node:path';

export function validRelease(m) {
  return m && ['versionCode','gameProtocol','minimumOnlineVersionCode','bytes'].every(k => Number.isSafeInteger(m[k]) && m[k] > 0 && m[k] <= 2147483647)
    && m.minimumOnlineVersionCode <= m.versionCode
    && typeof m.versionName === 'string' && m.versionName.length > 0 && m.versionName.length <= 64
    && typeof m.notes === 'string' && m.notes.length <= 4000
    && ['sha256','signingFingerprint'].every(k => typeof m[k] === 'string' && /^[a-f0-9]{64}$/i.test(m[k]))
    && m.downloadUrl === '/downloads/android/';
}

const escape = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

export function androidReleases(directory) {
  function current() {
    if (!directory) return null;
    try {
      const file = path.join(directory,'stable.json');
      if (fs.statSync(file).size > 16384) return null;
      const m = JSON.parse(fs.readFileSync(file,'utf8'));
      return validRelease(m) ? m : null;
    } catch { return null; }
  }
  function handle(req,res,url) {
    if (url.pathname !== '/updates/android/stable.json' && !url.pathname.startsWith('/downloads/android/')) return false;
    const metadata = current();
    res.setHeader('X-Content-Type-Options','nosniff');
    res.setHeader('Cache-Control','no-store');
    if (!['GET','HEAD'].includes(req.method)) {res.writeHead(405,{Allow:'GET, HEAD'});res.end();return true;}
    if (!metadata) {res.writeHead(404);res.end('No Android release published.');return true;}
    let body, type;
    if (url.pathname === '/updates/android/stable.json') {
      body = JSON.stringify(metadata); type = 'application/json';
    } else if (url.pathname === '/downloads/android/') {
      body = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Relic Diver Android</title><style>body{background:#16357f;color:#fff9df;font:18px system-ui;max-width:760px;margin:3em auto;padding:1em}a{color:#ffdc68}code{overflow-wrap:anywhere}pre{white-space:pre-wrap}</style><h1>Relic Diver ${escape(metadata.versionName)}</h1><p>${(metadata.bytes/1048576).toFixed(1)} MB · build ${metadata.versionCode}</p><pre>${escape(metadata.notes)}</pre><p><a href="relic-diver-${metadata.versionCode}.apk">Download Android APK</a></p><p>Install over your existing app. Do not uninstall: uninstalling removes local saves. Android must accept the same signing key. If installation fails, cancel and keep your current app.</p><p>SHA-256: <code>${metadata.sha256}</code></p><p>Signing certificate SHA-256: <code>${metadata.signingFingerprint}</code></p><p>Engine and asset notices are included in the app. This is a non-profit fan game.</p></html>`;
      type = 'text/html; charset=utf-8';
      res.setHeader('Content-Security-Policy',"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'");
    } else {
      if (!/^\/downloads\/android\/relic-diver-[1-9][0-9]*\.apk(?:\.sha256)?$/.test(url.pathname)) {res.writeHead(404);res.end();return true;}
      const file = path.join(directory,path.basename(url.pathname));
      let stat; try {stat=fs.statSync(file);} catch {res.writeHead(404);res.end();return true;}
      if (!stat.isFile()) {res.writeHead(404);res.end();return true;}
      res.setHeader('Cache-Control','public, max-age=31536000, immutable');
      res.writeHead(200,{'Content-Type':file.endsWith('.apk')?'application/vnd.android.package-archive':'text/plain','Content-Length':stat.size});
      if (req.method === 'HEAD') res.end(); else fs.createReadStream(file).on('error',()=>res.destroy()).pipe(res);
      return true;
    }
    res.writeHead(200,{'Content-Type':type,'Content-Length':Buffer.byteLength(body)});
    res.end(req.method === 'HEAD' ? undefined : body);
    return true;
  }
  return {current,handle};
}
