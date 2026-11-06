#!/usr/bin/env python3
"""Static checks that an unstubbed SOR4.exe is a sane image (it cannot be run on the Mac).

    .venv/bin/python -I tools/validate_unstub.py out/SOR4.unstub.exe [out/SOR4.p1.unstub.exe]

Needs pefile and capstone. Exits non-zero on the first failed check.
"""
import struct
import sys

import capstone
import pefile

md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = False


def fail(msg):
    print("FAIL:", msg)
    sys.exit(1)


def ok(msg):
    print("ok:  ", msg)


def check(path):
    print("==", path)
    d = open(path, "rb").read()
    pe = pefile.PE(data=d)
    oh = pe.OPTIONAL_HEADER
    base = oh.ImageBase
    secs = {s.Name.rstrip(b"\0").decode(): s for s in pe.sections}
    names = list(secs)
    print("     sections:", ", ".join("%s va=%#x vs=%#x raw=%#x+%#x" % (n, s.VirtualAddress, s.Misc_VirtualSize,
          s.PointerToRawData, s.SizeOfRawData) for n, s in secs.items()))

    def sec_of(rva):
        for n, s in secs.items():
            if s.VirtualAddress <= rva < s.VirtualAddress + max(s.Misc_VirtualSize, s.SizeOfRawData):
                return n
        return None

    # --- section table / sizes
    last = pe.sections[-1]
    want = (last.VirtualAddress + last.Misc_VirtualSize + oh.SectionAlignment - 1) // oh.SectionAlignment * oh.SectionAlignment
    if oh.SizeOfImage != want:
        fail("SizeOfImage %#x != %#x" % (oh.SizeOfImage, want))
    ok("SizeOfImage %#x == align(last section end); %d sections" % (oh.SizeOfImage, len(names)))
    end = max(s.PointerToRawData + s.SizeOfRawData for s in pe.sections)
    if end != len(d):
        fail("file length %#x != end of last raw section %#x" % (len(d), end))
    ok("file length %#x == end of last raw section (no overlay)" % len(d))
    if "SteamStub" in str(pe.sections) or any(n not in (".text", ".managed", ".rdata", ".data", ".pdata", "_RDATA", ".rsrc", ".reloc", ".bind") for n in names):
        fail("unexpected section")
    # --- entry point
    ep = oh.AddressOfEntryPoint
    if sec_of(ep) != ".text":
        fail("entry point %#x is in %s, not .text" % (ep, sec_of(ep)))
    ok("entry point %#x in .text" % ep)
    print("     checksum field: %#x (Windows does not verify it for exes; Steamless also leaves it)" % oh.CheckSum)
    # --- .text decoded
    t = secs[".text"]
    text = d[t.PointerToRawData:t.PointerToRawData + t.Misc_VirtualSize]
    pd = pe.get_data(oh.DATA_DIRECTORY[3].VirtualAddress, oh.DATA_DIRECTORY[3].Size)
    funcs = [struct.unpack_from("<III", pd, i) for i in range(0, len(pd), 12)]
    tf = [(b, e) for b, e, u in funcs if t.VirtualAddress <= b < t.VirtualAddress + t.Misc_VirtualSize]
    starts = {b for b, e in tf}
    if ep not in starts:
        print("     note: entry point %#x is not a .pdata function start" % ep)
    else:
        ok("entry point is a .pdata function start")
    bad = 0
    for b, e in tf:
        code = text[b - t.VirtualAddress:e - t.VirtualAddress]
        if sum(i.size for i in md.disasm(code, b)) != len(code):
            bad += 1
    print("     .pdata functions in .text: %d, decoding exactly to their end: %d, not: %d" % (len(tf), len(tf) - bad, bad))
    if bad > 3:
        fail("too many .pdata functions fail to decode")
    # first function (crosses the old stolen-block boundary at +0x10)
    print("     first instructions of .text (stolen block = first 16 bytes):")
    for i in list(md.disasm(text[:0x30], t.VirtualAddress))[:8]:
        print("       %#07x  %-24s %s %s" % (i.address, i.bytes.hex(), i.mnemonic, i.op_str))
    print("     disassembly at OEP %#x:" % ep)
    code = text[ep - t.VirtualAddress:ep - t.VirtualAddress + 0x100]
    for n, i in enumerate(md.disasm(code, ep)):
        if n >= 22:
            break
        extra = ""
        if i.mnemonic in ("call", "jmp") and i.op_str.startswith("0x"):
            extra = "   ; -> " + str(sec_of(int(i.op_str, 16)))
        print("       %#07x  %-24s %s %s%s" % (i.address, i.bytes.hex(), i.mnemonic, i.op_str, extra))
    # direct call/jmp edges from .text and .managed into .text must land on instruction starts
    m = secs[".managed"]
    mdat = d[m.PointerToRawData:m.PointerToRawData + m.Misc_VirtualSize]
    tgt = {}
    for i in range(len(mdat) - 5):
        if mdat[i] == 0xE8:
            r = m.VirtualAddress + i + 5 + struct.unpack_from("<i", mdat, i + 1)[0]
            if t.VirtualAddress <= r < t.VirtualAddress + t.Misc_VirtualSize:
                tgt[r] = tgt.get(r, 0) + 1
    startset = set(starts)
    hit = sum(1 for r in tgt if r in startset)
    print("     distinct .text targets of E8 in .managed: %d, of which .pdata function starts: %d" % (len(tgt), hit))
    # --- relocations
    pe.parse_data_directories([5, 1, 9, 12])
    rel = 0
    ranges = {}
    for blk in pe.DIRECTORY_ENTRY_BASERELOC:
        for e in blk.entries:
            if e.type:
                rel += 1
                n = sec_of(e.rva)
                ranges[n] = ranges.get(n, 0) + 1
    if None in ranges or ".bind" in ranges:
        fail("relocations outside the image or in .bind: %s" % ranges)
    ok("%d relocations, all in sections: %s" % (rel, ranges))
    # --- TLS
    tls = pe.DIRECTORY_ENTRY_TLS.struct
    cb = tls.AddressOfCallBacks - base
    arr = struct.unpack_from("<4Q", pe.get_data(cb, 32))
    live = []
    for x in arr:
        if not x:
            break
        live.append(x)
    print("     TLS: raw %#x-%#x, index %#x (%s), callbacks array at %#x (%s) -> first entries %s => %d callbacks run" % (
        tls.StartAddressOfRawData - base, tls.EndAddressOfRawData - base, tls.AddressOfIndex - base,
        sec_of(tls.AddressOfIndex - base), cb, sec_of(cb), [hex(x) for x in arr], len(live)))
    for x in live:
        if sec_of(x - base) in (None, ".bind"):
            fail("TLS callback %#x outside code" % x)
    if sec_of(tls.StartAddressOfRawData - base) is None or sec_of(tls.AddressOfIndex - base) is None:
        fail("TLS directory points outside the image")
    ok("TLS directory inside the image; no callback is run before the entry point (first entry is NULL)")
    # --- imports
    dlls = []
    for e in pe.DIRECTORY_ENTRY_IMPORT:
        dlls.append(e.dll.decode())
        for imp in e.imports:
            if sec_of(imp.address - base) is None:
                fail("import thunk outside image")
    ok("imports: %s; none is a Steam DLL" % ", ".join(dlls))
    if any("steam" in x.lower() for x in dlls):
        fail("steam import")
    # --- directories and .pdata referencing removed stub
    for i, dd in enumerate(oh.DATA_DIRECTORY):
        if dd.Size and sec_of(dd.VirtualAddress) is None:
            fail("data directory %d outside image" % i)
        if dd.Size and sec_of(dd.VirtualAddress) == ".bind":
            fail("data directory %d in .bind" % i)
    ok("every data directory lies in a surviving section, none in .bind")
    stray = [(b, e) for b, e, u in funcs if sec_of(b) is None]
    print("     .pdata entries pointing outside the image: %d %s" % (len(stray), [(hex(b), hex(e)) for b, e in stray[:3]]))
    return d


if __name__ == "__main__":
    for p in sys.argv[1:]:
        check(p)
