#!/usr/bin/env python3
"""Minimal Telltale ttarch2 reader/writer for WDC (The Walking Dead: Definitive Series, PC).

Format (from TTG Tools' ArchiveUnpacker, re-implemented here):
  "ECTT" (compressed + encrypted) | "ZCTT" (compressed) | "NCTT" (plain)
  ECTT/ZCTT: u32 chunk_size (0x10000), u32 n, u64 offs[n+1] (absolute; chunk i = offs[i]..offs[i+1]).
  Each chunk: Telltale Blowfish v7 (ECB, trailing <8 bytes left as is) of raw deflate.
  Inflated stream: "TTA4", u32 names_size, u32 count, count * {u64 crc64, u64 off, u32 size, u32 ?,
  u16 name_block, u16 name_off}, names, then file data (off relative to data start).
Lua files inside are "\\x1bLEn" (header kept, rest encrypted) or "\\x1bLEo" (whole file encrypted).

Usage:
  ttarch2.py list  <archive>
  ttarch2.py x     <archive> <outdir> [--decrypt-lua]
  ttarch2.py pack  <indir> <out.ttarch2> [--encrypt-lua]   (ZCTT? no: writes ECTT like the game's own)
"""
import os, struct, sys, zlib

KEY = bytes([0x96, 0xCA, 0x99, 0x9F, 0x8D, 0xDA, 0x9A, 0x87, 0xD7, 0xCD, 0xD9, 0xBB, 0x93, 0xD1, 0xBE, 0xC0,
             0xD7, 0x91, 0x71, 0xDC, 0x9E, 0xD9, 0x8D, 0xD0, 0xD1, 0x8C, 0xD8, 0xC3, 0xA0, 0xB0, 0xC6, 0x95,
             0xC3, 0x9C, 0x93, 0xBB, 0xCC, 0xCC, 0xA7, 0xD3, 0xB9, 0xD9, 0xD9, 0xD0, 0x8E, 0x93, 0xBE, 0xDA,
             0xAE, 0xD1, 0x8D, 0x77, 0xD5, 0xD3, 0xA3])


def _pi_tables():
    # Blowfish initial P/S tables (hex digits of pi), taken from the reference implementation.
    from _bf_tables import P, S
    return list(P), [list(s) for s in S]


class BF7:
    """Telltale's v7 Blowfish: rounds 1..4 use P[3],P[4],P[1],P[2]; s0[118] byteswapped after key xor."""

    def __init__(self, key):
        P, S = _pi_tables()
        n = len(key)
        j = 0
        for i in range(18):
            d = (key[j % n] << 24) | (key[(j + 1) % n] << 16) | (key[(j + 2) % n] << 8) | key[(j + 3) % n]
            P[i] ^= d
            j = (j + 4) % n
        v = S[0][118]
        S[0][118] = int.from_bytes(v.to_bytes(4, 'little'), 'big')
        self.P, self.S = P, S
        l = r = 0
        for i in range(0, 18, 2):
            l, r = self._enc_std(l, r)
            P[i], P[i + 1] = l, r
        for s in S:
            for i in range(0, 256, 2):
                l, r = self._enc_std(l, r)
                s[i], s[i + 1] = l, r
        # round key order for the v7 cipher
        self.Pr = [P[0], P[3], P[4], P[1], P[2]] + P[5:]

    def _F(self, b):
        s0, s1, s2, s3 = self.S
        return ((((s0[b >> 24] + s1[(b >> 16) & 255]) & 0xffffffff) ^ s2[(b >> 8) & 255]) + s3[b & 255]) & 0xffffffff

    def _enc_std(self, l, r):
        P = self.P
        F = self._F
        l ^= P[0]
        for i in range(1, 17, 2):
            r ^= F(l) ^ P[i]
            l ^= F(r) ^ P[i + 1]
        r ^= P[17]
        return r, l

    def crypt(self, data, decrypt):
        P = self.Pr
        s0, s1, s2, s3 = self.S
        out = bytearray(data)
        nb = len(data) // 8
        words = list(struct.unpack_from('<%dI' % (nb * 2), data))
        if decrypt:
            order = [(i, i - 1) for i in range(16, 0, -2)]
            first, last = P[17], P[0]
        else:
            order = [(i, i + 1) for i in range(1, 17, 2)]
            first, last = P[0], P[17]
        for k in range(nb):
            l = words[2 * k]
            r = words[2 * k + 1]
            l ^= first
            for a, b in order:
                f = ((((s0[l >> 24] + s1[(l >> 16) & 255]) & 0xffffffff) ^ s2[(l >> 8) & 255]) + s3[l & 255]) & 0xffffffff
                r ^= f ^ P[a]
                f = ((((s0[r >> 24] + s1[(r >> 16) & 255]) & 0xffffffff) ^ s2[(r >> 8) & 255]) + s3[r & 255]) & 0xffffffff
                l ^= f ^ P[b]
            r ^= last
            words[2 * k] = r
            words[2 * k + 1] = l
        struct.pack_into('<%dI' % (nb * 2), out, 0, *words)
        return bytes(out)


_bf = None


def bf():
    global _bf
    if _bf is None:
        _bf = BF7(KEY)
    return _bf


def inflate_archive(raw):
    magic = raw[:4]
    if magic == b'NCTT':
        size = struct.unpack_from('<Q', raw, 4)[0]
        return magic, 0x10000, raw[12:12 + size]
    assert magic in (b'ECTT', b'ZCTT'), magic
    chunk, n = struct.unpack_from('<II', raw, 4)
    offs = struct.unpack_from('<%dQ' % (n + 1), raw, 12)
    parts = []
    for i in range(n):
        c = raw[offs[i]:offs[i + 1]]
        if magic == b'ECTT':
            c = bf().crypt(c, True)
        parts.append(zlib.decompress(c, -15))
    return magic, chunk, b''.join(parts)


def parse_toc(stream):
    assert stream[:4] == b'4ATT', stream[:4]
    names_size, count = struct.unpack_from('<II', stream, 4)
    base = 12
    names_at = base + 28 * count
    data_at = names_at + names_size
    files = []
    for i in range(count):
        crc, off, size, unk, nb, no = struct.unpack_from('<QQIIHH', stream, base + 28 * i)
        p = names_at + nb * 0x10000 + no
        e = stream.index(b'\0', p)
        files.append(dict(name=stream[p:e].decode('latin-1'), crc=crc, off=off, size=size, unk=unk))
    return files, data_at


def read_archive(path):
    raw = open(path, 'rb').read()
    magic, chunk, stream = inflate_archive(raw)
    files, data_at = parse_toc(stream)
    for f in files:
        f['data'] = stream[data_at + f['off']: data_at + f['off'] + f['size']]
    return magic, files


def decrypt_lua(b):
    if b[:4] == b'\x1bLEn':
        return b'\x1bLua' + bf().crypt(b[4:], True)
    if b[:4] == b'\x1bLEo':
        return bf().crypt(b[4:], True)
    return b


def encrypt_lua(b, like):
    """Re-encrypt to the same container style as the original file (`like` = original header)."""
    if like == b'\x1bLEn':
        assert b[:4] == b'\x1bLua'
        return b'\x1bLEn' + bf().crypt(b[4:], False)
    if like == b'\x1bLEo':
        return b'\x1bLEo' + bf().crypt(b, False)
    return b


# --- CRC64 (ECMA-182, as used by Telltale for file name hashes) ---------------------------------
_CRC_TAB = None


def crc64(s):
    global _CRC_TAB
    if _CRC_TAB is None:
        poly = 0x42F0E1EBA9EA3693
        t = []
        for i in range(256):
            c = i << 56
            for _ in range(8):
                c = ((c << 1) ^ poly) if c & (1 << 63) else (c << 1)
                c &= 0xffffffffffffffff
            t.append(c)
        _CRC_TAB = t
    c = 0
    for ch in s.lower().encode('latin-1'):
        c = _CRC_TAB[((c >> 56) ^ ch) & 255] ^ ((c << 8) & 0xffffffffffffffff)
    return c


def write_archive(path, files, magic=b'ECTT', chunk=0x10000):
    """files: list of (name, data). Writes a TTA4 stream, chunked, deflated, encrypted (ECTT)."""
    files = sorted(files, key=lambda f: crc64(f[0]))
    names = b''
    name_pos = []
    for name, _ in files:
        nb = name.encode('latin-1') + b'\0'
        # names must not straddle a 64 KB block boundary
        if (len(names) % 0x10000) + len(nb) > 0x10000:
            names += b'\0' * (0x10000 - len(names) % 0x10000)
        name_pos.append(len(names))
        names += nb
    names += b'\0' * (-len(names) % 0x10000)   # like the game's archives: name table in whole 64 KB blocks
    toc = bytearray(b'4ATT' + struct.pack('<II', len(names), len(files)))
    off = 0
    data = bytearray()
    for (name, d), np in zip(files, name_pos):
        toc += struct.pack('<QQIIHH', crc64(name), off, len(d), 0, np // 0x10000, np % 0x10000)
        data += d
        off += len(d)
    stream = bytes(toc) + names + bytes(data)
    stream += b'\0' * (-len(stream) % chunk)   # and the stream padded to whole chunks
    chunks = [stream[i:i + chunk] for i in range(0, len(stream), chunk)]
    out_chunks = []
    for c in chunks:
        co = zlib.compressobj(9, zlib.DEFLATED, -15)
        z = co.compress(c) + co.flush()
        if magic == b'ECTT':
            z = bf().crypt(z, False)
        out_chunks.append(z)
    hdr = bytearray(magic + struct.pack('<II', chunk, len(out_chunks)))
    pos = len(hdr) + 8 * (len(out_chunks) + 1)
    offs = [pos]
    for z in out_chunks:
        pos += len(z)
        offs.append(pos)
    hdr += struct.pack('<%dQ' % len(offs), *offs)
    with open(path, 'wb') as fh:
        fh.write(bytes(hdr) + b''.join(out_chunks))


def main(argv):
    cmd = argv[1]
    if cmd == 'list':
        magic, files = read_archive(argv[2])
        for f in files:
            print('%8d %016x %s %s' % (f['size'], f['crc'], f['data'][:4], f['name']))
        print(len(files), 'files', magic)
    elif cmd == 'x':
        magic, files = read_archive(argv[2])
        out = argv[3]
        os.makedirs(out, exist_ok=True)
        for f in files:
            d = f['data']
            if '--decrypt-lua' in argv and f['name'].endswith('.lua'):
                d = decrypt_lua(d)
            open(os.path.join(out, f['name']), 'wb').write(d)
        print('extracted', len(files), 'files to', out)
    elif cmd == 'pack':
        ind, outp = argv[2], argv[3]
        files = [(n, open(os.path.join(ind, n), 'rb').read()) for n in sorted(os.listdir(ind))]
        write_archive(outp, files)
        print('wrote', outp, len(files), 'files')
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main(sys.argv)
