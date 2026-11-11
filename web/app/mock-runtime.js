/* DEV ONLY - fake TWD43 runtime that implements the real contract with delays.
 * Loaded by main.js only when the URL has ?mock. Always overrides any existing TWD43.
 *
 * Choose the outcome with a query param:
 *   ?mock=ok | incomplete | already_patched | not_twd | verify_failed | error | loadfail
 * Otherwise (plain ?mock) it is picked from the chosen file names (case-insensitive):
 *   only one file -> incomplete, "patched" -> already_patched, "nottwd" -> not_twd,
 *   "bad" or "fail" -> verify_failed, "error" -> error, anything else -> ok.
 * Extra knobs:  ?loadms=3000 (runtime load time)  ?patchms=4000 (patch time)  ?version=1.0-mock
 */
(function () {
  'use strict';
  var q = new URLSearchParams(location.search);
  var forced = q.get('mock');
  var LOAD_MS = +(q.get('loadms') || 2500);
  var PATCH_MS = +(q.get('patchms') || 3000);
  var VERSION = q.get('version') || 'v1.0-mock';
  var TOTAL = 1048576;
  var loadP = null;

  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  function hex(buf) {
    return Array.prototype.map.call(new Uint8Array(buf), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }
  function sha256(bytes) {
    if (globalThis.crypto && crypto.subtle) return crypto.subtle.digest('SHA-256', bytes).then(hex);
    var s = ''; for (var i = 0; i < 64; i++) s += ((bytes[i % bytes.length] || 0) + i * 7 & 15).toString(16);
    return Promise.resolve(s);
  }

  function pick(files) {
    if (forced === 'ok') return 'ok';
    if (forced) return forced;
    if (files.length < 2) return 'incomplete';
    var n = files.map(function (f) { return f.name || ''; }).join(' ').toLowerCase();
    if (n.indexOf('patched') >= 0) return 'already_patched';
    if (n.indexOf('nottwd') >= 0) return 'not_twd';
    if (n.indexOf('bad') >= 0 || n.indexOf('fail') >= 0) return 'verify_failed';
    if (n.indexOf('error') >= 0) return 'error';
    return 'ok';
  }

  var TWD43 = {
    version: undefined,   // real runtime may leave this unset; version arrives with patch()

    load: function (onProgress) {
      if (loadP) return loadP;
      loadP = (async function () {
        if (forced === 'loadfail') {
          if (onProgress) onProgress({ loaded: 0, total: TOTAL, label: 'Downloading runtime' });
          await sleep(800);
          throw new Error('mock: runtime failed to start (simulated)');
        }
        var steps = 25;
        for (var i = 0; i <= steps; i++) {
          if (onProgress) {
            if (i < 3) onProgress({ label: 'Starting' });                         // label-only call
            else onProgress({ loaded: Math.round(TOTAL * i / steps), total: TOTAL, label: i === steps ? 'Initializing' : 'Downloading' });
          }
          await sleep(LOAD_MS / steps);
        }
      })();
      return loadP;
    },

    patch: async function (files, opts) {
      files = Array.prototype.slice.call(files || []);
      var first = files[0] || new Blob([]);
      var bytes = new Uint8Array(await first.slice(0, 4096).arrayBuffer());
      var reason = pick(files);
      await sleep(PATCH_MS);
      var inSha = await sha256(bytes);
      var base = { ok: false, reason: reason, output: null, outputs: [], log: '', passed: 0, failed: 0, skipped: 0, failures: [], missing: [],
        inputSha256: inSha, outputSha256: null, version: VERSION };
      var log = ['[mock] patcher ' + VERSION];
      files.forEach(function (f) { log.push('[mock] picked ' + f.name + ' (' + f.size + ' bytes)'); });

      if (reason === 'ok') {
        var rev = inSha.split('').reverse().join('');
        var exe = new Blob([first, 'mock'], { type: 'application/octet-stream' });
        base.ok = true; base.outputSha256 = rev; base.zipName = 'TWD-4x3-patch.zip';
        base.output = new Blob(['PK mock zip: ', exe], { type: 'application/zip' });
        base.outputs = [
          { name: 'WDC.exe', blob: exe, sha256: rev, dest: 'game folder' }
        ];
        ['S1X', 'S2', 'S3', 'S4', 'SM'].forEach(function (s, i) {
          base.outputs.push({ name: '_resdesc_50_PC_P43_' + s + '_01.lua', blob: new Blob(['mock descriptor ' + s]), sha256: rev.slice(8 + i) + rev.slice(0, 8 + i), dest: 'Archives' });
          base.outputs.push({ name: 'WDC_pc_PC_P43_' + s + '_data.ttarch2', blob: new Blob(['mock archive ' + s]), sha256: rev.slice(16 + i) + rev.slice(0, 16 + i), dest: 'Archives' });
        });
        if (opts && opts.skip) {
          base.skip = true;
          ['S1', 'S2', 'S3', 'S4', 'SM'].forEach(function (s, i) {
            base.outputs.push({ name: '_resdesc_50_PC_P43_SKIP_' + s + '_01.lua', blob: new Blob(['mock skip descriptor ' + s]), sha256: rev.slice(24 + i) + rev.slice(0, 24 + i), dest: 'Archives' });
            base.outputs.push({ name: 'WDC_pc_PC_P43_SKIP_' + s + '_data.ttarch2', blob: new Blob(['mock skip archive ' + s]), sha256: rev.slice(32 + i) + rev.slice(0, 32 + i), dest: 'Archives' });
          });
        }
        base.passed = 12;
        log.push('[mock] SteamStub removed, exe patched, 5 season sets built');
        log.push('[mock] verify: 12 passed');
      } else if (reason === 'incomplete') {
        base.inputSha256 = '';
        base.missing = ['WDC_pc_ProjectSeason1_data.ttarch2 (the Archives folder)'];
        log.push('[mock] missing: ' + base.missing[0]);
      } else if (reason === 'already_patched') {
        log.push('[mock] known patched build: p10');
      } else if (reason === 'not_twd') {
        log.push('[mock] no SteamStub header: not the original Steam WDC.exe');
      } else if (reason === 'verify_failed') {
        base.passed = 0; base.failed = 1;
        base.failures = ['WDC.exe SHA-256 is ' + inSha + ', this patcher supports the Steam build 5f44e53fcaec4c59c8c2f79403722076fc1c518c0d006d2a1262efeaec656782'];
        log.push('[mock] verify: 0 passed, 1 failed');
        base.failures.forEach(function (f) { log.push('FAIL ' + f); });
      } else {
        base.reason = 'error';
        log.push('[mock] TypeError: Cannot read properties of undefined (reading \'subarray\')');
        log.push('   at readArchive (patcher-runtime.js)');
      }
      base.log = log.join('\n');
      return base;
    }
  };

  globalThis.TWD43 = TWD43;
})();
