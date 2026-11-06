#!/usr/bin/env python3
"""Strip SteamStub 3.1 from SOR4.exe: write a runnable exe with .text decrypted and the entry
point restored (the same result as Steamless' default for this variant).

    .venv/bin/python -I tools/unstub.py [--keep-bind] in.exe out.exe

Works on the pristine exe or on tools/patch43.py's output: the patch never touches .text, the
.bind section or the stub header, so unstub(patch(x)) == patch(unstub(x)) byte for byte.

Stub header (0xF0 bytes before the entry point, XOR-chained dwords; the first dword is the key
and each later dword is XORed with the previous *encrypted* dword):
  +0x04 signature 0xC0DEC0DF, +0x20 original entry point rva, +0x48/+0x50 code section va/raw
  size, +0x58 AES-256 key, +0x78 IV (stored ECB-encrypted under the key), +0x88 16 bytes.
Those 16 bytes are the FIRST CIPHERTEXT BLOCK of .text, not plaintext: the stub removed the
section's first 16 ciphertext bytes from the file (so file byte 0 of .text is block 1) and
parks them in its header. The AES-256-CBC stream is therefore stolen + file[:size-16], which
decrypts in place from the section's first byte. (Earlier tools treated the 16 bytes as
plaintext and shifted by one block, which left the first 32 bytes of .text wrong; verified
against .pdata function starts, a Steamless run, and decoding the first function.)

Then: entry point = original entry point. The .bind section (the stub code, never executed
afterwards) is dropped like Steamless does by default: header slot zeroed, NumberOfSections
and SizeOfImage reduced, file truncated; --keep-bind leaves it in place instead. Checksum is
left as found (0; Windows does not verify it for exes). The "VLV" signature block in the DOS
stub area (0x40..e_lfanew, read only by the stub) is zeroed, as Steamless does. Needs pycryptodome.
"""
import struct
import sys

from Crypto.Cipher import AES

SECT_ALIGN_DEFAULT = 0x1000


def parse(d):
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    ns = struct.unpack_from("<H", d, pe + 6)[0]
    opt = pe + 24
    so = opt + struct.unpack_from("<H", d, pe + 20)[0]
    secs = {}
    for i in range(ns):
        o = so + 40 * i
        secs[d[o:o + 8].rstrip(b"\0").decode()] = (o,) + struct.unpack_from("<IIII", d, o + 8)
    return pe, ns, opt, so, secs


def decode_header(d, opt, secs):
    ep = struct.unpack_from("<I", d, opt + 16)[0]
    _, _, bva, _, bra = secs[".bind"]
    fo = ep - bva + bra - 0xF0
    h = bytearray(d[fo:fo + 0xF0])
    key = struct.unpack_from("<I", h, 0)[0]
    for i in range(4, 0xF0, 4):
        v = struct.unpack_from("<I", h, i)[0]
        struct.pack_into("<I", h, i, v ^ key)
        key = v
    if struct.unpack_from("<I", h, 4)[0] != 0xC0DEC0DF:
        raise SystemExit("not a SteamStub 3.x header (already unstubbed?)")
    return h


def unstub(d, keep_bind=False):
    pe, ns, opt, so, secs = parse(d)
    h = decode_header(d, opt, secs)
    oep = struct.unpack_from("<Q", h, 0x20)[0]
    code_va, code_size = struct.unpack_from("<QQ", h, 0x48)
    aes_key, iv = bytes(h[0x58:0x78]), bytes(h[0x78:0x88])
    stolen = bytes(h[0x88:0x98])
    iv = AES.new(aes_key, AES.MODE_ECB).decrypt(iv)
    _, tvs, tva, _, tra = secs[".text"]
    assert tva == code_va and code_size % 16 == 0
    assert tva <= oep < tva + tvs, "original entry point is outside .text"
    cipher = (stolen + bytes(d[tra:tra + code_size]))[:code_size]
    out = bytearray(d)
    out[tra:tra + code_size] = AES.new(aes_key, AES.MODE_CBC, iv).decrypt(cipher)
    struct.pack_into("<I", out, opt + 16, oep)
    out[0x40:pe] = bytes(pe - 0x40)  # the "VLV" stub signature block in the DOS stub area
    if not keep_bind:
        ho, bvs, bva, brs, bra = secs[".bind"]
        last = max(secs.values(), key=lambda s: s[2])
        assert last[0] == ho and ho == so + 40 * (ns - 1), ".bind is not the last section"
        assert bra + brs == len(d), "data after .bind"
        # nothing may point into the removed range
        for i in range(16):
            rva, size = struct.unpack_from("<II", d, opt + 112 + 8 * i)
            assert size == 0 or not (bva <= rva < bva + max(bvs, brs)), "data directory %d in .bind" % i
        out[ho:ho + 40] = bytes(40)
        struct.pack_into("<H", out, pe + 6, ns - 1)
        align = struct.unpack_from("<I", d, opt + 32)[0] or SECT_ALIGN_DEFAULT
        prev = max((s for s in secs.values() if s[0] != ho), key=lambda s: s[2])
        struct.pack_into("<I", out, opt + 56, (prev[2] + prev[1] + align - 1) // align * align)
        del out[bra:]
    return bytes(out), oep


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    if len(args) != 2 or set(flags) - {"--keep-bind"}:
        raise SystemExit(__doc__)
    out, oep = unstub(open(args[0], "rb").read(), "--keep-bind" in flags)
    open(args[1], "wb").write(out)
    print("entry point -> %#x, %d bytes" % (oep, len(out)))
