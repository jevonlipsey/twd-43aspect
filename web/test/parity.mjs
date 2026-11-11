// Runs the browser runtime under node on the real game files and checks its three outputs are byte-identical
// to the command-line tools (tools/patch43.py p10, tools/build_fix43.py <season> --release) and to the hashes
// recorded in twd43-data.js. Then runs it again with {skip: true} and checks the ten extra hold-RB skip files
// against tools/build_skip43.py the same way (and that the first eleven are unchanged).
// usage: node web/test/parity.mjs [WDC.exe] [WDC_pc_ProjectSeason1_data.ttarch2]
//   env PYTHON (default: python3; needs pycryptodome), TWD_LUAC (luac from tools/build_luac52.sh; without it the
//   archive is compared with the verified hashes only)
import fs from 'node:fs';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import vm from 'node:vm';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.join(here, '..', '..');
const app = path.join(here, '..', 'app');
const exePath = process.argv[2] || path.join(repo, 'original', 'WDC.exe');
const archPath = process.argv[3] || path.join(repo, 'original', 'archives', 'WDC_pc_ProjectSeason1_data.ttarch2');
for (const f of ['twd43-data.js', 'pako.min.js', 'patcher-runtime.js']) vm.runInThisContext(fs.readFileSync(path.join(app, f), 'utf8'));
const g = globalThis, T = g.TWD43_DATA;
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
const file = (p, name) => new File([fs.readFileSync(p)], name || path.basename(p));
const zlibCrc = (b) => zlib.crc32(b);
let bad = 0;
const expect = (ok, msg) => { console.log((ok ? 'ok   ' : 'FAIL ') + msg); if (!ok) bad++; };

await g.TWD43.load();
const t0 = Date.now();
const res = await g.TWD43.patch([file(exePath, 'WDC.exe'), file(archPath)]);
if (!res.ok) { console.error(res.reason, res.log, res.failures); process.exit(1); }
console.log('patched in', Date.now() - t0, 'ms,', res.passed, 'checks');
const got = {};
for (const o of res.outputs) got[o.name] = Buffer.from(await o.blob.arrayBuffer());

// reference: the CLI
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'twd-parity-'));
const py = process.env.PYTHON || 'python3';
execFileSync(py, ['-I', path.join(repo, 'tools', 'patch43.py'), '--level', 'p10', exePath, path.join(tmp, 'WDC.exe')], { stdio: 'pipe' });
const ref = { 'WDC.exe': fs.readFileSync(path.join(tmp, 'WDC.exe')) };
if (process.env.TWD_LUAC) {
  // the CLI builder reads its stock Tooltip.lua from original/archives/WDC_pc_ProjectSeason1_data.ttarch2
  const flags = JSON.parse(execFileSync(py, ['-I', '-c', 'import sys, json; sys.path.insert(0, sys.argv[1]); import build_fix43; print(json.dumps(build_fix43.RELEASE))', path.join(repo, 'tools')]).toString());
  for (const set of T.mod.sets) {
    const d = path.join(tmp, set.season);
    execFileSync(py, ['-I', path.join(repo, 'tools', 'build_fix43.py'), set.season, d, '--release', ...flags[set.season]], { stdio: 'pipe' });
    for (const n of [set.descName, set.archName]) ref[n] = fs.readFileSync(path.join(d, n));
  }
}
const skipRef = {};
if (process.env.TWD_LUAC) {
  for (const set of T.mod.skipSets) {
    execFileSync(py, ['-I', path.join(repo, 'tools', 'build_skip43.py'), set.season, path.join(tmp, 'skip')], { stdio: 'pipe' });
    for (const n of [set.descName, set.archName]) skipRef[n] = fs.readFileSync(path.join(tmp, 'skip_' + set.season, n));
  }
}
fs.rmSync(tmp, { recursive: true, force: true });

const verified = { 'WDC.exe': T.exe.output };
for (const set of T.mod.sets) { verified[set.descName] = set.outDesc; verified[set.archName] = set.outArch; }
const modNames = T.mod.sets.flatMap((x) => [x.descName, x.archName]);
for (const o of res.outputs) {
  const h = sha(got[o.name]);
  expect(h === o.sha256, `${o.name}: runtime reported ${o.sha256.slice(0, 16)}…, bytes hash ${h.slice(0, 16)}…`);
  expect(h === verified[o.name], `${o.name}: matches the recorded build ${verified[o.name].slice(0, 16)}…`);
  if (ref[o.name]) expect(Buffer.compare(got[o.name], ref[o.name]) === 0, `${o.name}: byte-identical to the CLI output (${ref[o.name].length} bytes)`);
}
expect(res.inputSha256 === T.exe.pristine, 'input WDC.exe is the pristine Steam build');

// the zip: stored entries laid out like the game folder, each byte-identical to the file served one by one
{
  const z = Buffer.from(await res.output.arrayBuffer());
  expect(res.zipName === 'TWD-4x3-patch.zip' && sha(z) === res.zipSha256, `zip ${res.zipName}: ${z.length} bytes, sha256 ${sha(z).slice(0, 16)}…`);
  const want = { 'WDC.exe': 'WDC.exe' };
  for (const n of modNames) want[`Archives/${n}`] = n;
  const seen = [];
  let o = 0;
  while (z.readUInt32LE(o) === 0x04034b50) {
    const method = z.readUInt16LE(o + 8), crc = z.readUInt32LE(o + 14), size = z.readUInt32LE(o + 18), nl = z.readUInt16LE(o + 26), xl = z.readUInt16LE(o + 28);
    const name = z.subarray(o + 30, o + 30 + nl).toString(), body = z.subarray(o + 30 + nl + xl, o + 30 + nl + xl + size);
    expect(method === 0 && want[name] && Buffer.compare(body, got[want[name]]) === 0 && crc === (zlibCrc(body) >>> 0),
      `zip entry ${name}: stored, crc ok, identical to ${want[name]}`);
    seen.push(name); o += 30 + nl + xl + size;
  }
  expect(seen.length === 1 + modNames.length && Object.keys(want).every((k) => seen.includes(k)), `zip holds exactly the ${1 + modNames.length} files: ` + seen.join(', '));
  const again = Buffer.from(g.TWD43.makeZip([{ path: 'WDC.exe', bytes: got['WDC.exe'] },
    ...modNames.map((n) => ({ path: `Archives/${n}`, bytes: got[n] }))]));
  expect(Buffer.compare(again, z) === 0, 'zip is deterministic');
}

// option on: the same eleven files plus ten skip files, each equal to the CLI output
{
  const skipNames = T.mod.skipSets.flatMap((x) => [x.descName, x.archName]);
  expect(res.skip !== true && res.outputs.length === 11, 'option off: 11 outputs, no skip files');
  const rs = await g.TWD43.patch([file(exePath, 'WDC.exe'), file(archPath)], { skip: true });
  if (!rs.ok) { console.error(rs.reason, rs.log, rs.failures); process.exit(1); }
  expect(rs.skip === true && rs.outputs.length === 21, 'option on: 21 outputs');
  const gs = {};
  for (const o of rs.outputs) gs[o.name] = Buffer.from(await o.blob.arrayBuffer());
  for (const n of Object.keys(got)) expect(Buffer.compare(gs[n], got[n]) === 0, `option on: ${n} is unchanged`);
  const verifiedSkip = {};
  for (const set of T.mod.skipSets) { verifiedSkip[set.descName] = set.outDesc; verifiedSkip[set.archName] = set.outArch; }
  for (const n of skipNames) {
    expect(!!gs[n] && sha(gs[n]) === verifiedSkip[n], `${n}: matches the recorded build ${verifiedSkip[n].slice(0, 16)}…`);
    if (skipRef[n]) expect(Buffer.compare(gs[n], skipRef[n]) === 0, `${n}: byte-identical to the CLI output (${skipRef[n].length} bytes)`);
  }
  if (!process.env.TWD_LUAC) console.log('note: TWD_LUAC not set, skip files compared with the recorded hashes only');
  const z = Buffer.from(await rs.output.arrayBuffer());
  const want = { 'WDC.exe': 'WDC.exe' };
  for (const n of [...modNames, ...skipNames]) want[`Archives/${n}`] = n;
  const seen = [];
  let o = 0;
  while (z.readUInt32LE(o) === 0x04034b50) {
    const size = z.readUInt32LE(o + 18), nl = z.readUInt16LE(o + 26), xl = z.readUInt16LE(o + 28);
    const name = z.subarray(o + 30, o + 30 + nl).toString(), body = z.subarray(o + 30 + nl + xl, o + 30 + nl + xl + size);
    expect(want[name] && Buffer.compare(body, gs[want[name]]) === 0, `skip zip entry ${name}: identical to ${want[name]}`);
    seen.push(name); o += 30 + nl + xl + size;
  }
  expect(seen.length === 21 && Object.keys(want).every((k) => seen.includes(k)), 'skip zip holds exactly the 21 files');
  expect(/^[0-9a-f]{64}$/.test(T.mod.stockDlgSha256) && T.mod.stockDlgSha256.startsWith('65f453745b23f6cb'), 'stock dialog manager hash is pinned');
  expect(!JSON.stringify(T.mod.skipSets).includes(T.mod.stockDlgSha256), 'no game file embedded in the data');
}

// negatives
const r2 = await g.TWD43.patch([new File([got['WDC.exe']], 'WDC.exe'), file(archPath)]);
expect(r2.reason === 'already_patched', 'patched WDC.exe is recognised: ' + r2.reason);
const r3 = await g.TWD43.patch([file(exePath, 'WDC.exe')]);
expect(r3.reason === 'incomplete' && r3.missing.length === 1, 'exe alone asks for the archive: ' + r3.reason + ' ' + r3.missing);
const r4 = await g.TWD43.patch([file(exePath, 'renamed.bin'), file(archPath, 'other-name.ttarch2')]);
expect(r4.ok === true, 'renamed files are recognised by their contents: ' + r4.reason);
const wrong = path.join(path.dirname(archPath), 'WDC_pc_Boot_data.ttarch2');
if (fs.existsSync(wrong)) {
  const r5 = await g.TWD43.patch([file(exePath, 'WDC.exe'), file(wrong, 'WDC_pc_ProjectSeason1_data.ttarch2')]);
  expect(r5.reason === 'verify_failed', 'a different archive is refused: ' + r5.reason + ' ' + r5.failures[0]);
}
if (bad) { console.error(bad + ' check(s) failed'); process.exit(1); }
console.log('parity OK');
