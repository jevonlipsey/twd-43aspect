/* The Walking Dead: The Telltale Definitive Series 4:3 patcher - browser runtime (pure JavaScript, no
 * WebAssembly). Classic script that needs twd43-data.js and pako.min.js first; defines globalThis.TWD43:
 *   TWD43.load(onProgress) -> Promise<void>      idempotent
 *   TWD43.patch(File[], {skip: bool}) -> Promise<{ok, reason, output (zip Blob: WDC.exe + Archives/<10 files>, +10 with skip), zipName, zipSha256,
 *       outputs [{name, blob, sha256, dest}] (the same eleven files one by one; 21 with opts.skip, the optional
 *       hold-RB skip sets from tools/build_skip43.py, whose S1 hook also takes the stock module_dialog_manager.lua from the archive),
 *       skip (bool, whether the skip sets are included),
 *       log, passed, failed, skipped, failures, missing, inputSha256, outputSha256, version}>
 * It is the same work as the command-line tools, byte for byte:
 *   WDC.exe: tools/unstub.py (SteamStub 3.1, .bind kept) + tools/patch43.py --level p10
 *   Archives: tools/build_fix43.py <S1|S2|S3|S4|M> --release (ttarch2.py: Telltale Blowfish v7, raw deflate level 9)
 * The game's own Tooltip.lua is read from the user's WDC_pc_ProjectSeason1_data.ttarch2 and never shipped.
 */
(function () {
  'use strict';

  var D = globalThis.TWD43_DATA;
  var VERSION = D ? D.version : 'v1.0';
  var ZIP_NAME = 'TWD-4x3-patch.zip';

  // ---- bytes ----
  function unhex(h) { var o = new Uint8Array(h.length / 2); for (var i = 0; i < o.length; i++) o[i] = parseInt(h.substr(i * 2, 2), 16); return o; }
  function hex(b) { var s = ''; for (var i = 0; i < b.length; i++) s += ('0' + b[i].toString(16)).slice(-2); return s; }
  function b64(s) {
    if (typeof atob === 'function') { var t = atob(s), o = new Uint8Array(t.length); for (var i = 0; i < t.length; i++) o[i] = t.charCodeAt(i); return o; }
    return new Uint8Array(Buffer.from(s, 'base64'));
  }
  function ascii(s) { var o = new Uint8Array(s.length); for (var i = 0; i < s.length; i++) o[i] = s.charCodeAt(i) & 255; return o; }
  function concat(parts) {
    var n = 0, i; for (i = 0; i < parts.length; i++) n += parts[i].length;
    var o = new Uint8Array(n), p = 0;
    for (i = 0; i < parts.length; i++) { o.set(parts[i], p); p += parts[i].length; }
    return o;
  }
  function eq(a, b) { if (a.length !== b.length) return false; for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false; return true; }
  function sha256(bytes) { return crypto.subtle.digest('SHA-256', bytes).then(function (h) { return hex(new Uint8Array(h)); }); }
  function readFile(file) {
    if (file.arrayBuffer) return file.arrayBuffer().then(function (x) { return new Uint8Array(x); });
    return new Promise(function (res, rej) {
      var r = new FileReader();
      r.onload = function () { res(new Uint8Array(r.result)); };
      r.onerror = function () { rej(r.error || new Error('Could not read the file.')); };
      r.readAsArrayBuffer(file);
    });
  }
  function yieldUi() { return new Promise(function (r) { setTimeout(r, 0); }); }

  // ---- Telltale Blowfish v7 (tools/ttarch2.py BF7): rounds 1-4 use P[3],P[4],P[1],P[2]; s0[118] byteswapped ----
  var BF = null;
  function bfInit() {
    if (BF) return BF;
    var key = unhex(D.blowfish.key), n = key.length;
    var P = new Uint32Array(D.blowfish.P), S = D.blowfish.S.map(function (s) { return new Uint32Array(s); });
    var j = 0, i;
    for (i = 0; i < 18; i++) {
      P[i] ^= (key[j % n] << 24) | (key[(j + 1) % n] << 16) | (key[(j + 2) % n] << 8) | key[(j + 3) % n];
      j = (j + 4) % n;
    }
    var v = S[0][118];
    S[0][118] = ((v & 255) << 24) | ((v >>> 8 & 255) << 16) | ((v >>> 16 & 255) << 8) | (v >>> 24);
    var s0 = S[0], s1 = S[1], s2 = S[2], s3 = S[3];
    function F(x) { return ((((s0[x >>> 24] + s1[x >>> 16 & 255]) >>> 0) ^ s2[x >>> 8 & 255]) + s3[x & 255]) >>> 0; }
    var l = 0, r = 0;
    function encStd() {
      l = (l ^ P[0]) >>> 0;
      for (var k = 1; k < 17; k += 2) { r = (r ^ F(l) ^ P[k]) >>> 0; l = (l ^ F(r) ^ P[k + 1]) >>> 0; }
      r = (r ^ P[17]) >>> 0;
      var t = l; l = r; r = t;
    }
    for (i = 0; i < 18; i += 2) { encStd(); P[i] = l; P[i + 1] = r; }
    for (var si = 0; si < 4; si++) for (i = 0; i < 256; i += 2) { encStd(); S[si][i] = l; S[si][i + 1] = r; }
    var Pr = new Uint32Array(18);
    Pr[0] = P[0]; Pr[1] = P[3]; Pr[2] = P[4]; Pr[3] = P[1]; Pr[4] = P[2];
    for (i = 5; i < 18; i++) Pr[i] = P[i];
    BF = { P: Pr, F: F };
    return BF;
  }
  // ECB over whole 8-byte blocks (little-endian words); a trailing partial block is left as is.
  function bfCrypt(data, decrypt) {
    var b = bfInit(), P = b.P, F = b.F;
    var out = data.slice();
    var dv = new DataView(out.buffer, out.byteOffset, out.byteLength);
    var nb = out.length >> 3;
    for (var k = 0; k < nb; k++) {
      var o = k * 8, l = dv.getUint32(o, true), r = dv.getUint32(o + 4, true), i;
      if (decrypt) {
        l = (l ^ P[17]) >>> 0;
        for (i = 16; i > 0; i -= 2) { r = (r ^ F(l) ^ P[i]) >>> 0; l = (l ^ F(r) ^ P[i - 1]) >>> 0; }
        r = (r ^ P[0]) >>> 0;
      } else {
        l = (l ^ P[0]) >>> 0;
        for (i = 1; i < 17; i += 2) { r = (r ^ F(l) ^ P[i]) >>> 0; l = (l ^ F(r) ^ P[i + 1]) >>> 0; }
        r = (r ^ P[17]) >>> 0;
      }
      dv.setUint32(o, r, true); dv.setUint32(o + 4, l, true);
    }
    return out;
  }

  // ---- CRC64-ECMA-182 of the lowercased name (ttarch2.crc64) ----
  var CRC = null;
  function crc64(name) {
    var M = (1n << 64n) - 1n, i;
    if (!CRC) {
      CRC = [];
      var poly = 0x42F0E1EBA9EA3693n;
      for (i = 0; i < 256; i++) {
        var c = BigInt(i) << 56n;
        for (var k = 0; k < 8; k++) c = ((c & (1n << 63n)) ? ((c << 1n) ^ poly) : (c << 1n)) & M;
        CRC.push(c);
      }
    }
    var s = ascii(name.toLowerCase()), v = 0n;
    for (i = 0; i < s.length; i++) v = CRC[Number(((v >> 56n) ^ BigInt(s[i])) & 255n)] ^ ((v << 8n) & M);
    return v;
  }

  // ---- ttarch2 (ECTT: chunks of Blowfish(raw deflate) over a TTA4 stream) ----
  function readArchive(raw) {
    var dv = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
    var magic = String.fromCharCode(raw[0], raw[1], raw[2], raw[3]);
    if (magic !== 'ECTT') throw new Error('not an ECTT archive (' + magic + ')');
    var n = dv.getUint32(8, true), parts = [];
    for (var i = 0; i < n; i++) {
      var a = Number(dv.getBigUint64(12 + 8 * i, true)), b = Number(dv.getBigUint64(20 + 8 * i, true));
      parts.push(pako.inflateRaw(bfCrypt(raw.subarray(a, b), true)));
    }
    var st = concat(parts), sv = new DataView(st.buffer);
    if (String.fromCharCode(st[0], st[1], st[2], st[3]) !== '4ATT') throw new Error('archive stream is not TTA4');
    var namesSize = sv.getUint32(4, true), count = sv.getUint32(8, true);
    var namesAt = 12 + 28 * count, dataAt = namesAt + namesSize, files = [];
    for (i = 0; i < count; i++) {
      var e = 12 + 28 * i;
      var off = Number(sv.getBigUint64(e + 8, true)), size = sv.getUint32(e + 16, true);
      var p = namesAt + sv.getUint16(e + 24, true) * 0x10000 + sv.getUint16(e + 26, true), q = p;
      while (st[q]) q++;
      var name = ''; for (var k = p; k < q; k++) name += String.fromCharCode(st[k]);
      files.push({ name: name, data: st.subarray(dataAt + off, dataAt + off + size) });
    }
    return files;
  }

  function writeArchive(files, chunk) {
    files = files.map(function (f) { return { name: f.name, data: f.data, crc: crc64(f.name) }; })
      .sort(function (a, b) { return a.crc < b.crc ? -1 : a.crc > b.crc ? 1 : 0; });
    var names = [], nlen = 0, pos = [];
    files.forEach(function (f) {
      var nb = concat([ascii(f.name), new Uint8Array(1)]);
      if ((nlen % 0x10000) + nb.length > 0x10000) { var pad = 0x10000 - nlen % 0x10000; names.push(new Uint8Array(pad)); nlen += pad; }
      pos.push(nlen); names.push(nb); nlen += nb.length;
    });
    var npad = (0x10000 - nlen % 0x10000) % 0x10000;
    names.push(new Uint8Array(npad)); nlen += npad;
    var toc = new Uint8Array(12 + 28 * files.length), tv = new DataView(toc.buffer);
    toc.set(ascii('4ATT')); tv.setUint32(4, nlen, true); tv.setUint32(8, files.length, true);
    var off = 0;
    files.forEach(function (f, i) {
      var e = 12 + 28 * i;
      tv.setBigUint64(e, f.crc, true); tv.setBigUint64(e + 8, BigInt(off), true);
      tv.setUint32(e + 16, f.data.length, true); tv.setUint32(e + 20, 0, true);
      tv.setUint16(e + 24, Math.floor(pos[i] / 0x10000), true); tv.setUint16(e + 26, pos[i] % 0x10000, true);
      off += f.data.length;
    });
    var body = concat([toc].concat(names, files.map(function (f) { return f.data; })));
    var stream = new Uint8Array(body.length + (chunk - body.length % chunk) % chunk);
    stream.set(body);
    var outChunks = [];
    for (var c = 0; c < stream.length; c += chunk) {
      outChunks.push(bfCrypt(pako.deflateRaw(stream.subarray(c, c + chunk), { level: 9, windowBits: 15, memLevel: 8 }), false));
    }
    var hdr = new Uint8Array(12 + 8 * (outChunks.length + 1)), hv = new DataView(hdr.buffer);
    hdr.set(ascii('ECTT')); hv.setUint32(4, chunk, true); hv.setUint32(8, outChunks.length, true);
    var at = hdr.length;
    hv.setBigUint64(12, BigInt(at), true);
    outChunks.forEach(function (z, i) { at += z.length; hv.setBigUint64(20 + 8 * i, BigInt(at), true); });
    return concat([hdr].concat(outChunks));
  }

  function encryptLua(b, like) {
    if (like === 'LEn') return concat([ascii('\x1bLEn'), bfCrypt(b.subarray(4), false)]);   // header kept, rest encrypted
    return concat([ascii('\x1bLEo'), bfCrypt(b, false)]);                                   // whole file encrypted
  }

  // ---- zip (stored; same writer as hades-43aspect): fixed timestamp, no compression, so it is the same in every browser ----
  var CRC32 = null;
  function crc32(bytes) {
    if (!CRC32) {
      CRC32 = new Uint32Array(256);
      for (var n = 0; n < 256; n++) {
        var c = n;
        for (var k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
        CRC32[n] = c >>> 0;
      }
    }
    var crc = 0xFFFFFFFF;
    for (var i = 0; i < bytes.length; i++) crc = CRC32[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }
  // entries: [{path, bytes}] -> Uint8Array
  function makeZip(entries) {
    var DOS_TIME = 0, DOS_DATE = (46 << 9) | (1 << 5) | 1; // 2026-01-01 00:00
    var chunks = [], central = [], offset = 0;
    entries.forEach(function (e) {
      var name = ascii(e.path), crc = crc32(e.bytes), size = e.bytes.length;
      var lh = new DataView(new ArrayBuffer(30));
      lh.setUint32(0, 0x04034b50, true); lh.setUint16(4, 20, true); lh.setUint16(6, 0x0800, true);
      lh.setUint16(8, 0, true); lh.setUint16(10, DOS_TIME, true); lh.setUint16(12, DOS_DATE, true);
      lh.setUint32(14, crc, true); lh.setUint32(18, size, true); lh.setUint32(22, size, true);
      lh.setUint16(26, name.length, true); lh.setUint16(28, 0, true);
      chunks.push(new Uint8Array(lh.buffer), name, e.bytes);
      var ch = new DataView(new ArrayBuffer(46));
      ch.setUint32(0, 0x02014b50, true); ch.setUint16(4, 20, true); ch.setUint16(6, 20, true);
      ch.setUint16(8, 0x0800, true); ch.setUint16(10, 0, true); ch.setUint16(12, DOS_TIME, true);
      ch.setUint16(14, DOS_DATE, true); ch.setUint32(16, crc, true); ch.setUint32(20, size, true);
      ch.setUint32(24, size, true); ch.setUint16(28, name.length, true); ch.setUint16(30, 0, true);
      ch.setUint16(32, 0, true); ch.setUint16(34, 0, true); ch.setUint16(36, 0, true);
      ch.setUint32(38, 0, true); ch.setUint32(42, offset, true);
      central.push(new Uint8Array(ch.buffer), name);
      offset += 30 + name.length + size;
    });
    var cdSize = central.reduce(function (n, c) { return n + c.length; }, 0);
    var end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true); end.setUint16(8, entries.length, true); end.setUint16(10, entries.length, true);
    end.setUint32(12, cdSize, true); end.setUint32(16, offset, true);
    return concat(chunks.concat(central, [new Uint8Array(end.buffer)]));
  }

  // ---- PE / SteamStub 3.1 (tools/unstub.py) ----
  function parsePe(d) {
    var dv = new DataView(d.buffer, d.byteOffset, d.byteLength);
    if (d.length < 0x200 || d[0] !== 0x4d || d[1] !== 0x5a) return null;
    var pe = dv.getUint32(0x3c, true);
    if (pe + 24 > d.length || dv.getUint32(pe, true) !== 0x4550) return null;
    var ns = dv.getUint16(pe + 6, true), opt = pe + 24, so = opt + dv.getUint16(pe + 20, true), secs = {}, list = [];
    for (var i = 0; i < ns; i++) {
      var o = so + 40 * i, nm = '';
      for (var k = 0; k < 8 && d[o + k]; k++) nm += String.fromCharCode(d[o + k]);
      var s = { name: nm, hdr: o, vsize: dv.getUint32(o + 8, true), va: dv.getUint32(o + 12, true), rsize: dv.getUint32(o + 16, true), raw: dv.getUint32(o + 20, true) };
      secs[nm] = s; list.push(s);
    }
    return { dv: dv, pe: pe, opt: opt, secs: secs, list: list };
  }

  function stubHeader(d, pe) {
    var b = pe.secs['.bind'];
    if (!b) return null;
    var ep = pe.dv.getUint32(pe.opt + 16, true);
    var fo = ep - b.va + b.raw - 0xf0;
    if (fo < 0 || fo + 0xf0 > d.length) return null;
    var h = d.slice(fo, fo + 0xf0), hv = new DataView(h.buffer);
    var key = hv.getUint32(0, true);
    for (var i = 4; i < 0xf0; i += 4) { var v = hv.getUint32(i, true); hv.setUint32(i, (v ^ key) >>> 0, true); key = v; }
    if (hv.getUint32(4, true) !== 0xC0DEC0DF) return null;
    return { h: h, hv: hv };
  }

  // AES-256-CBC without padding through WebCrypto: append the block that makes the PKCS#7 check pass
  // (CBC-encrypting an empty message with IV = the last ciphertext block yields exactly that block).
  function aesCbcRaw(keyBytes, iv, cipher) {
    var s = crypto.subtle;
    return s.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['encrypt', 'decrypt']).then(function (key) {
      return s.encrypt({ name: 'AES-CBC', iv: cipher.slice(cipher.length - 16) }, key, new Uint8Array(0)).then(function (pad) {
        return s.decrypt({ name: 'AES-CBC', iv: iv }, key, concat([cipher, new Uint8Array(pad)]));
      });
    }).then(function (p) { return new Uint8Array(p); });
  }

  async function unstubKeepBind(d, pe, st) {
    var hv = st.hv, h = st.h;
    var oep = Number(hv.getBigUint64(0x20, true));
    var codeVa = Number(hv.getBigUint64(0x48, true)), codeSize = Number(hv.getBigUint64(0x50, true));
    var aesKey = h.slice(0x58, 0x78), ivEnc = h.slice(0x78, 0x88), stolen = h.slice(0x88, 0x98);
    var t = pe.secs['.text'];
    if (!t || t.va !== codeVa || codeSize % 16) throw new Error('stub header does not describe .text');
    if (!(t.va <= oep && oep < t.va + t.vsize)) throw new Error('original entry point is outside .text');
    var iv = await aesCbcRaw(aesKey, new Uint8Array(16), ivEnc);   // one ECB block = CBC with a zero IV
    var cipher = concat([stolen, d.subarray(t.raw, t.raw + codeSize)]).subarray(0, codeSize);
    var plain = await aesCbcRaw(aesKey, iv, cipher);
    var out = d.slice();
    out.set(plain, t.raw);
    var ov = new DataView(out.buffer);
    ov.setUint32(pe.opt + 16, oep, true);
    out.fill(0, 0x40, pe.pe);   // the "VLV" stub signature block in the DOS stub area
    return { out: out, oep: oep };
  }

  function rva2off(pe, va, base) {
    var r = va - base;
    for (var i = 0; i < pe.list.length; i++) {
      var s = pe.list[i];
      if (s.va <= r && r < s.va + s.vsize) return r - s.va + s.raw;
    }
    throw new Error('va 0x' + va.toString(16) + ' is not in any section');
  }

  // ---- what each picked file is ----
  async function classify(file) {
    var n = (file.name || '').toLowerCase();
    if (n === 'wdc.exe') return 'exe';
    if (n === D.mod.sourceArchive.toLowerCase()) return 'archive';
    var head = await readFile(file.slice(0, 4));
    if (head[0] === 0x4d && head[1] === 0x5a) return 'exe';
    if (head[0] === 0x45 && head[1] === 0x43 && head[2] === 0x54 && head[3] === 0x54) return 'archive';
    return null;
  }

  var TWD43 = {
    version: VERSION,
    makeZip: makeZip, crc32: crc32,
    required: ['WDC.exe', D ? 'Archives/' + D.mod.sourceArchive : ''],

    load: function (onProgress) {
      if (!D) return Promise.reject(new Error('twd43-data.js is missing'));
      if (typeof pako === 'undefined' || !pako.deflateRaw) return Promise.reject(new Error('pako.min.js is missing'));
      if (!(globalThis.crypto && crypto.subtle)) return Promise.reject(new Error('crypto.subtle is unavailable (the page must be served over https)'));
      if (typeof BigInt !== 'function' || !DataView.prototype.setBigUint64) return Promise.reject(new Error('this browser has no BigInt support'));
      bfInit();
      if (onProgress) onProgress({ label: 'Ready' });
      return Promise.resolve();
    },

    patch: async function (fileList, opts) {
      var log = [], passed = 0, failures = [];
      function res(reason, extra) {
        var r = { ok: false, reason: reason, output: null, outputs: [], log: log.join('\n'), passed: passed, failed: failures.length,
          skipped: 0, failures: failures, missing: [], inputSha256: '', outputSha256: null, version: VERSION };
        for (var k in extra) r[k] = extra[k];
        return r;
      }
      function check(ok, what) { if (ok) passed++; else failures.push(what); return ok; }
      if (!D) throw new Error('twd43-data.js is missing');
      log.push('TWD Definitive 4:3 patcher ' + VERSION);

      var files = Array.prototype.slice.call(fileList || []), exeFile = null, archFile = null;
      for (var i = 0; i < files.length; i++) {
        var kind = await classify(files[i]);
        log.push('Picked ' + files[i].name + ' (' + files[i].size + ' bytes): ' + (kind || 'not used'));
        if (kind === 'exe' && !exeFile) exeFile = files[i];
        if (kind === 'archive' && (!archFile || (files[i].name || '').toLowerCase() === D.mod.sourceArchive.toLowerCase())) archFile = files[i];
      }
      var missing = [];
      if (!exeFile) missing.push('WDC.exe (the game folder)');
      if (!archFile) missing.push(D.mod.sourceArchive + ' (the Archives folder)');
      if (missing.length) { log.push('Missing: ' + missing.join(', ')); return res('incomplete', { missing: missing }); }

      // ---- WDC.exe ----
      var exe = await readFile(exeFile);
      var inSha = await sha256(exe);
      log.push('WDC.exe SHA-256 ' + inSha);
      if (D.exe.patched[inSha]) { log.push('Known patched build: ' + D.exe.patched[inSha]); return res('already_patched', { inputSha256: inSha }); }
      var pe = parsePe(exe);
      if (!pe) return res('not_twd', { inputSha256: inSha });
      var st = stubHeader(exe, pe);
      if (!st) { log.push('No SteamStub header: not the original Steam WDC.exe'); return res('not_twd', { inputSha256: inSha }); }
      if (!check(inSha === D.exe.pristine, 'WDC.exe SHA-256 is ' + inSha + ', this patcher supports the Steam build ' + D.exe.pristine)) {
        return res('verify_failed', { inputSha256: inSha });
      }
      await yieldUi();
      var us = await unstubKeepBind(exe, pe, st);
      log.push('SteamStub removed (.text decrypted, entry point 0x' + us.oep.toString(16) + ', .bind kept for the cave)');
      var out = us.out, base = D.exe.base;
      var ko = rva2off(pe, D.exe.k43Va, base), k43 = unhex(D.exe.k43);
      check(eq(out.subarray(ko, ko + 4), k43), 'float 4/3 at 0x' + D.exe.k43Va.toString(16) + ': found ' + hex(out.subarray(ko, ko + 4)));
      var cave = unhex(D.exe.cave), co = rva2off(pe, D.exe.caveVa, base);
      out.set(cave, co);
      log.push('cave 0x' + D.exe.caveVa.toString(16) + ': ' + cave.length + ' bytes');
      D.exe.patches.forEach(function (p) {
        var o = rva2off(pe, p.va, base), old = unhex(p.old), nw = unhex(p.new), cur = out.subarray(o, o + old.length);
        if (check(eq(cur, old), p.name + ' @0x' + p.va.toString(16) + ': found ' + hex(cur) + ', expected ' + p.old)) {
          out.set(nw, o);
          log.push('patched ' + p.name + ' @0x' + p.va.toString(16) + ' ' + p.old + ' -> ' + p.new);
        }
      });
      if (failures.length) return res('verify_failed', { inputSha256: inSha });
      var outSha = await sha256(out);
      log.push('WDC.exe output SHA-256 ' + outSha);
      if (!check(outSha === D.exe.output, 'patched WDC.exe SHA-256 is ' + outSha + ', expected ' + D.exe.output)) return res('verify_failed', { inputSha256: inSha });
      await yieldUi();

      // ---- the per-season 4:3 UI sets (two new files each for Archives/) ----
      var raw = await readFile(archFile), archSha = await sha256(raw), entries;
      log.push(D.mod.sourceArchive + ' SHA-256 ' + archSha);
      try { entries = readArchive(raw); } catch (e) {
        failures.push(archFile.name + ' could not be read as a Telltale archive: ' + (e && e.message || e));
        return res('verify_failed', { inputSha256: inSha });
      }
      var stock = entries.filter(function (f) { return f.name === D.mod.stockName; });
      if (!check(stock.length === 1, 'Tooltip.lua was not found in ' + archFile.name + ' (is it ' + D.mod.sourceArchive + '?)')) return res('verify_failed', { inputSha256: inSha });
      var stockSha = await sha256(stock[0].data);
      log.push('stock Tooltip.lua: ' + stock[0].data.length + ' bytes, SHA-256 ' + stockSha);
      if (!check(stockSha === D.mod.stockSha256, 'Tooltip.lua in your archive has SHA-256 ' + stockSha + ', this patcher supports ' + D.mod.stockSha256)) return res('verify_failed', { inputSha256: inSha });
      var stocks = { 'Tooltip.lua': stock[0].data };
      var skipOn = !!(opts && opts.skip);
      if (skipOn) {
        // the optional skip sets' S1 hook needs the stock dialog manager from the same archive
        var dlg = entries.filter(function (f) { return f.name === D.mod.stockDlgName; });
        if (!check(dlg.length === 1, D.mod.stockDlgName + ' was not found in ' + archFile.name + ' (is it ' + D.mod.sourceArchive + '?)')) return res('verify_failed', { inputSha256: inSha });
        var dlgSha = await sha256(dlg[0].data);
        log.push('stock ' + D.mod.stockDlgName + ': ' + dlg[0].data.length + ' bytes, SHA-256 ' + dlgSha);
        if (!check(dlgSha === D.mod.stockDlgSha256, D.mod.stockDlgName + ' in your archive has SHA-256 ' + dlgSha + ', this patcher supports ' + D.mod.stockDlgSha256)) return res('verify_failed', { inputSha256: inSha });
        stocks[D.mod.stockDlgName] = dlg[0].data;
      }
      var newFiles = [];
      var allSets = D.mod.sets.map(function (x) { return { set: x, tag: x.season }; });
      if (skipOn) D.mod.skipSets.forEach(function (x) { allSets.push({ set: x, tag: x.season + ' skip' }); });
      for (var si = 0; si < allSets.length; si++) {
        var set = allSets[si].set, tag = allSets[si].tag, want = {};
        var arch = writeArchive(set.files.map(function (f) {
          var data = f.stock ? stocks[f.stock] : encryptLua(b64(f.bytecode), 'LEn');
          want[f.name] = f;
          return { name: f.name, data: data };
        }), D.mod.chunk);
        var desc = encryptLua(ascii(set.descriptor), 'LEo');
        // read the new archive back: every file present, ours decrypt to our bytecode, the stock one unchanged
        var back = readArchive(arch), got = {};
        back.forEach(function (f) { got[f.name] = f.data; });
        check(back.length === set.files.length, set.archName + ' read-back: ' + back.length + ' files');
        set.files.forEach(function (f) {
          var g = got[f.name];
          if (f.stock) check(g && eq(g, stocks[f.stock]), set.archName + ' read-back: ' + f.name);
          else { var bc = b64(f.bytecode); check(g && eq(bfCrypt(g.subarray(4), true), bc.subarray(4)), set.archName + ' read-back: ' + f.name); }
        });
        var archOutSha = await sha256(arch), descSha = await sha256(desc);
        log.push(tag + ': ' + set.archName + ' ' + arch.length + ' bytes, SHA-256 ' + archOutSha);
        log.push(tag + ': ' + set.descName + ' ' + desc.length + ' bytes, SHA-256 ' + descSha);
        check(archOutSha === set.outArch, set.archName + ' SHA-256 is ' + archOutSha + ', expected ' + set.outArch);
        check(descSha === set.outDesc, set.descName + ' SHA-256 is ' + descSha + ', expected ' + set.outDesc);
        newFiles.push({ name: set.descName, bytes: desc, sha256: descSha }, { name: set.archName, bytes: arch, sha256: archOutSha });
        await yieldUi();
      }
      if (failures.length) return res('verify_failed', { inputSha256: inSha });

      // one zip laid out like the game folder: WDC.exe at the top, the new files under Archives/
      var zip = makeZip([{ path: 'WDC.exe', bytes: out }].concat(newFiles.map(function (f) {
        return { path: 'Archives/' + f.name, bytes: f.bytes };
      })));
      var zipSha = await sha256(zip);
      log.push(ZIP_NAME + ' ' + zip.length + ' bytes, SHA-256 ' + zipSha);
      var exeBlob = new Blob([out], { type: 'application/octet-stream' });
      log.push('All ' + passed + ' checks passed');
      return {
        ok: true, reason: 'ok', output: new Blob([zip], { type: 'application/zip' }), zipName: ZIP_NAME, zipSha256: zipSha, skip: skipOn,
        log: log.join('\n'), passed: passed, failed: 0, skipped: 0, failures: [], missing: [],
        inputSha256: inSha, outputSha256: outSha, version: VERSION,
        outputs: [{ name: 'WDC.exe', blob: exeBlob, sha256: outSha, dest: 'game folder' }].concat(newFiles.map(function (f) {
          return { name: f.name, blob: new Blob([f.bytes], { type: 'application/octet-stream' }), sha256: f.sha256, dest: 'Archives' };
        }))
      };
    }
  };

  globalThis.TWD43 = TWD43;
})();
