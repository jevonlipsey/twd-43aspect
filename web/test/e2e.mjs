// end-to-end: drives the real UI (web/dist/index.html, not ?mock) in headless Chrome with the real game files.
//   node web/test/e2e.mjs [--dist web/dist] [--exe original/WDC.exe] [--arch original/archives/WDC_pc_ProjectSeason1_data.ttarch2]
//                         [--shot out.png] [--one-by-one] [--skip]
// --skip ticks "Also add hold RB to skip cutscenes" first and checks the 10 extra files, the zip contents and the OK text.
// --one-by-one picks WDC.exe first, checks the "one more file is needed" view, then adds the archive.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
import { serve, launchChrome } from './cdp.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const dist = path.resolve(opt('--dist', path.join(root, 'web/dist')));
const exe = path.resolve(opt('--exe', path.join(root, 'original/WDC.exe')));
const arch = path.resolve(opt('--arch', path.join(root, 'original/archives/WDC_pc_ProjectSeason1_data.ttarch2')));
const shot = opt('--shot', path.join(process.env.TMPDIR || '/tmp', 'twd43-e2e.png'));
const oneByOne = argv.includes('--one-by-one');
const withSkip = argv.includes('--skip');
for (const f of [exe, arch]) if (!fs.existsSync(f)) { console.error('FAIL: input missing ' + f); process.exit(1); }
vm.runInThisContext(fs.readFileSync(path.join(root, 'web/app/twd43-data.js'), 'utf8'));
const T = globalThis.TWD43_DATA;
const expected = { 'WDC.exe': T.exe.output };
for (const s of T.mod.sets) { expected[s.descName] = s.outDesc; expected[s.archName] = s.outArch; }

if (withSkip) for (const s of T.mod.skipSets) { expected[s.descName] = s.outDesc; expected[s.archName] = s.outArch; }

const srv = await serve(dist);
const chrome = await launchChrome();
let failed = 0;
const ok = (c, m) => { console.log((c ? '  ok   ' : '  FAIL ') + m); if (!c) failed++; };
const pageErrors = [];
chrome.on('Runtime.exceptionThrown', (p) => pageErrors.push(p.exceptionDetails.exception?.description || p.exceptionDetails.text));
const waitView = () => chrome.evaluate(`new Promise((res) => { const t0 = Date.now(); (function w() {
    const ok = !document.getElementById('view-ok').hidden, fail = !document.getElementById('view-fail').hidden;
    if (ok || fail || Date.now() - t0 > 120000) return res(ok ? 'ok' : fail ? 'fail' : 'timeout'); setTimeout(w, 200); })(); })`);
try {
  await chrome.goto(srv.origin + '/index.html');
  const t0 = Date.now();
  await chrome.evaluate(`new Promise((res, rej) => { const t0 = Date.now(); (function w() {
    const e = document.getElementById('runtime'); if (e && e.classList.contains('ready')) return res(1);
    if (e && e.classList.contains('failed')) return rej(new Error('runtime failed: ' + document.getElementById('runtime-fail-text').textContent));
    if (Date.now() - t0 > 60000) return rej(new Error('runtime load timeout')); setTimeout(w, 100); })(); })`);
  console.log(`runtime ready after ${Date.now() - t0} ms`);

  const box = JSON.parse(await chrome.evaluate(`(() => { const b = document.getElementById('opt-skip'); const r = b.getBoundingClientRect();
    return JSON.stringify({ checked: b.checked, visible: b.offsetParent !== null && r.width > 0, label: b.closest('label').textContent.replace(/\\s+/g, ' ').trim() }); })()`));
  ok(box.visible && box.checked === false && /hold RB to skip cutscenes/.test(box.label), 'skip tick box is shown and off by default');
  if (withSkip) {
    await chrome.evaluate(`document.getElementById('opt-skip').click()`);
    ok(await chrome.evaluate(`document.getElementById('opt-skip').checked`), 'skip tick box ticked');
  }

  const doc = await chrome.send('DOM.getDocument');
  const { nodeId } = await chrome.send('DOM.querySelector', { nodeId: doc.root.nodeId, selector: '#file' });
  const t1 = Date.now();
  if (oneByOne) {
    await chrome.send('DOM.setFileInputFiles', { nodeId, files: [exe] });
    const s1 = await waitView();
    const title = await chrome.evaluate(`document.getElementById('fail-title-text').textContent`);
    const addMore = await chrome.evaluate(`!document.getElementById('add-more').hidden`);
    ok(s1 === 'fail' && /one more file/i.test(title) && addMore, `exe alone: "${title}", add button shown: ${addMore}`);
    await chrome.send('DOM.setFileInputFiles', { nodeId, files: [arch] });
  } else {
    await chrome.send('DOM.setFileInputFiles', { nodeId, files: [exe, arch] });
  }
  const state = await waitView();
  console.log(`result state: ${state} after ${Date.now() - t1} ms`);
  ok(state === 'ok', 'success view is shown');
  const info = JSON.parse(await chrome.evaluate(`(async () => {
    const out = [];
    document.querySelector('details.more-hashes').open = true;
    for (const a of [...document.querySelectorAll('#download-files a'), document.getElementById('download')]) {
      const id = a.id || a.textContent; const r = await fetch(a.href); const b = new Uint8Array(await r.arrayBuffer());
      const hex = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', b)), (x) => x.toString(16).padStart(2, '0')).join('');
      out.push({ id, visible: a.offsetParent !== null, href: a.href.slice(0, 5), name: a.getAttribute('download'), size: b.length, sha: hex });
    }
    const shown = [document.getElementById('ok-out-hash'), ...document.querySelectorAll('#ok-more-hashes dd')].map((e) => e.textContent.trim());
    return JSON.stringify({ out, shown, verified: document.getElementById('ok-verified').textContent.trim() });
  })()`));
  console.log('  ' + info.verified);
  const zip = info.out.pop();
  const zipNames = JSON.parse(await chrome.evaluate(`(async () => {
    const z = new Uint8Array(await (await fetch(document.getElementById('download').href)).arrayBuffer()), v = new DataView(z.buffer), names = [];
    let o = 0;
    while (v.getUint32(o, true) === 0x04034b50) { const size = v.getUint32(o + 18, true), nl = v.getUint16(o + 26, true), xl = v.getUint16(o + 28, true);
      names.push(new TextDecoder().decode(z.subarray(o + 30, o + 30 + nl))); o += 30 + nl + xl + size; }
    return JSON.stringify(names); })()`));
  const wantZip = ['WDC.exe', ...Object.keys(expected).filter((n) => n !== 'WDC.exe').map((n) => 'Archives/' + n)];
  ok(zipNames.length === wantZip.length && wantZip.every((n) => zipNames.includes(n)), `zip holds ${zipNames.length} files (${withSkip ? 'with' : 'without'} the SKIP sets): ` + (withSkip ? 'has' : 'has no') + ' PC_P43_SKIP_* entries');
  ok(zipNames.some((n) => n.includes('PC_P43_SKIP_')) === withSkip, 'SKIP entries present only when ticked');
  const okText = await chrome.evaluate(`document.getElementById('view-ok').innerText`);
  ok(/twenty new files/.test(okText) === withSkip && /hold\s+RB/i.test(okText) === withSkip, 'OK view mentions the skip files only when ticked');
  ok(zip.visible && zip.href === 'blob:' && zip.name === 'TWD-4x3-patch.zip' && zip.size > info.out.reduce((n, o) => n + o.size, 0),
    `download (primary) saves as ${zip.name} (${zip.size} bytes)`);
  ok(info.out.length === Object.keys(expected).length, `${info.out.length} files offered one by one`);
  info.out.forEach((o, i) => {
    ok(o.visible && o.href === 'blob:', `${o.id} visible with a blob: url, saves as ${o.name} (${o.size} bytes)`);
    ok(o.sha === info.shown[i], `${o.name}: blob sha256 equals the hash shown in the UI`);
    ok(o.sha === expected[o.name], `${o.name}: blob sha256 equals the published build ${expected[o.name].slice(0, 16)}…`);
  });
  const png = await chrome.send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true });
  fs.writeFileSync(shot, Buffer.from(png.data, 'base64'));
  console.log('screenshot ' + shot);
  ok(pageErrors.length === 0, 'no uncaught page exceptions' + (pageErrors.length ? ': ' + pageErrors.join('; ') : ''));
} catch (e) { console.log('  FAIL ' + e.message); failed++; }
finally { await chrome.close(); srv.close(); }
console.log(failed ? 'E2E FAILED' : 'E2E OK');
process.exit(failed ? 1 : 0);
