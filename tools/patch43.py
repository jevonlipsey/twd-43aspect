#!/usr/bin/env python3
"""WDC.exe (The Walking Dead: Definitive Series, SteamStub 3.1) -> 4:3 build.

    python3 -I tools/patch43.py [--level p1] original/WDC.exe out/WDC.<level>.exe

Input must be the pristine stubbed exe (sha256 checked). The output is UNSTUBBED (a patched
stubbed exe fails the stub's module verification) plus the byte patches of the level.
Needs pycryptodome (use the sor4 venv or `pip install pycryptodome`).
Levels are cumulative:
  p1 = stop forcing 16:9 (viewport fills the window; vertical FOV kept, so the sides are cropped)
  p2 = p1 + keep the 16:9 horizontal FOV: tan(half vfov) is scaled by 4/3 in the two projection
       builders (perspective matrix, frustum corners) through a 28-byte cave in the dead SteamStub
       .bind section (so p2 is built with --keep-bind semantics).
"""
import hashlib, struct, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from unstub import unstub

PRISTINE = "5f44e53fcaec4c59c8c2f79403722076fc1c518c0d006d2a1262efeaec656782"
BASE = 0x140000000

# (name, va, expected bytes, new bytes) -- va in .text/.rdata, all verified against `expected`
P1 = [
    # Lua RenderForce_16_by_9_AspectRatio(): `mov cl,1; call SetForceAspect` -> `mov cl,0`
    ("force16x9 flag off", 0x1406794f5, bytes.fromhex("b101"), bytes.fromhex("b100")),
]

# p2: cave in .bind (stub code, never executed after unstubbing):  tan(x) * 4/3
CAVE = 0x14122e000
TAN = 0x140b28510
K43 = 0x140c00770          # float 1.3333334 in .rdata (verified below)
def cave_bytes():
    b = bytearray()
    b += bytes.fromhex("4883ec28")                                  # sub rsp,0x28
    b += b"\xe8" + struct.pack("<i", TAN - (CAVE + len(b) + 5))     # call tan
    b += bytes.fromhex("4883c428")                                  # add rsp,0x28
    b += bytes.fromhex("f30f5905") + struct.pack("<i", K43 - (CAVE + len(b) + 8))   # mulss xmm0,[K43]
    b += b"\xc3"
    return bytes(b)
def callrel(site, tgt):
    return b"\xe8" + struct.pack("<i", tgt - (site + 5))
P2 = P1 + [
    ("tan call (persp matrix)", 0x14003929f, callrel(0x14003929f, TAN), callrel(0x14003929f, CAVE)),
    ("tan call (frustum)", 0x1404571eb, callrel(0x1404571eb, TAN), callrel(0x1404571eb, CAVE)),
]
# p3 experiment E1: design-aspect getter (0x14053e0a0, movss xmm0,[16/9]) returns 4/3 -> UI "fit" layers become full window
def rip(site, ilen, tgt): return struct.pack("<i", tgt - (site + ilen))
P3 = P2 + [
    ("design aspect 16/9 -> 4/3", 0x14053e0a4, rip(0x14053e0a0, 8, 0x140c1c840), rip(0x14053e0a0, 8, 0x140c00770)),
]

# p4: camera-only, conditional (only cameras with aspect field <= 0, i.e. "use window aspect"):
#   tan cave in the frustum builder, and a post-call fix (matrix m0,m5 *= 0.75) after the camera's perspective call.
# The shared perspective builder (also used by light/shadow projections) is left alone.
def cave4():
    base = CAVE
    b = bytearray()
    def here(): return base + len(b)
    tcave = here()
    b += bytes.fromhex("4883ec28")
    b += b"\xe8" + struct.pack("<i", TAN - (here() + 5)); b += bytes.fromhex("4883c428")
    b += bytes.fromhex("0f57c9" "0f2f8bc4010000" "7208")
    b += bytes.fromhex("f30f5905") + struct.pack("<i", K43 - (here() + 8)) + b"\xc3"
    pcave = here()
    b += bytes.fromhex("440f28442458" "0f57c0" "0f2f83c4010000")
    jb = len(b); b += bytes.fromhex("72") + b"\x00"
    kpos = []
    for ld, st in (("f30f1007", "f30f1107"), ("f30f104714", "f30f114714")):
        b += bytes.fromhex(ld) + bytes.fromhex("f30f5905") + b"\x00\x00\x00\x00"; kpos.append(len(b))
        b += bytes.fromhex(st)
    b[jb + 1] = len(b) - (jb + 2)
    b += b"\xc3"
    while len(b) % 4: b += b"\xcc"
    k075 = here(); b += struct.pack("<f", 0.75)
    for p in kpos: b[p - 4:p] = struct.pack("<i", k075 - (base + p))
    return bytes(b), tcave, pcave
C4, TCAVE, PCAVE = cave4()
P4 = P1 + [
    ("tan call (frustum, cond)", 0x1404571eb, callrel(0x1404571eb, TAN), callrel(0x1404571eb, TCAVE)),
    ("camera post-persp fix", 0x14045c64f, bytes.fromhex("440f28442450"), callrel(0x14045c64f, PCAVE)[0:5] + b"\x90"),
]

# dbg: p1 + camera logger (ring of 8 x 0x210 bytes at LOG, camera object bytes [0,0x200)); .bind made writable.
LOGPAGE = 0x140f2c000
LOG = 0x140f2cb00   # padding at the end of .rdata (zero, unused); made RWX at runtime by VirtualProtect (IAT 0x140bbf3e8)
def cave_dbg():
    b = bytearray(bytes.fromhex("440f28442458"))            # movaps xmm8,[rsp+0x58]
    b += bytes.fromhex("4883ec38" "48b9") + struct.pack("<Q", LOGPAGE) + bytes.fromhex("ba00100000" "41b804000000" "4c8d4c2430" "ff15")
    b += struct.pack("<i", 0x140bbf3e8 - (CAVE + len(b) + 4)) + bytes.fromhex("4883c438")   # VirtualProtect(page,0x1000,RWX,&old)
    b += bytes.fromhex("48b8") + struct.pack("<Q", LOG)     # mov rax,LOG
    b += bytes.fromhex("8b08" "8d5101" "8910")              # ecx=[rax]; [rax]=ecx+1
    b += bytes.fromhex("83e10f" "c1e106")                   # and ecx,15 ; shl ecx,6   (64-byte entries)
    b += bytes.fromhex("4c8d0408" "4983c010")               # lea r8,[rax+rcx] ; add r8,0x10
    b += bytes.fromhex("49895800")                          # mov [r8],rbx
    b += bytes.fromhex("488b8424" + struct.pack("<I", 0x90).hex()) # mov rax,[rsp+0x90]  (enclosing function's return address)
    b += bytes.fromhex("49894008")                          # mov [r8+8],rax
    b += bytes.fromhex("0f1083c0010000" "410f114010")       # movups xmm0,[rbx+0x1c0]; movups [r8+0x10],xmm0
    b += bytes.fromhex("0f1083cc010000" "410f114020")       # movups xmm0,[rbx+0x1cc]; movups [r8+0x20],xmm0
    b += bytes.fromhex("488b4350" "49894030")               # mov rax,[rbx+0x50]; mov [r8+0x30],rax
    b += bytes.fromhex("488b4358" "49894038")               # mov rax,[rbx+0x58]; mov [r8+0x38],rax
    b += b"\xc3"
    return bytes(b)
P_DBG = P1 + [
    ("camera logger", 0x14045c64f, bytes.fromhex("440f28442450"), callrel(0x14045c64f, CAVE)[0:5] + b"\x90"),
]

# p5: flag-conditional. The "force 16:9" byte (0x140fd6da6, set by the Lua RenderForce_16_by_9_AspectRatio) is left to the
# scripts, but the viewport sizer no longer shrinks the window for it. Cameras are Hor+ (tan*4/3) only while the flag is 0.
FLAG = 0x140fd6da6
def cave5():
    base = CAVE
    b = bytearray()
    def here(): return base + len(b)
    tcave = here()
    b += bytes.fromhex("4883ec28")
    b += b"\xe8" + struct.pack("<i", TAN - (here() + 5)); b += bytes.fromhex("4883c428")
    b += bytes.fromhex("803d") + struct.pack("<i", FLAG - (here() + 7)) + b"\x00" + bytes.fromhex("7508")   # cmp byte [FLAG],0 ; jne skip
    b += bytes.fromhex("f30f5905") + struct.pack("<i", K43 - (here() + 8)) + b"\xc3"
    pcave = here()
    b += bytes.fromhex("440f28442458")
    b += bytes.fromhex("803d") + struct.pack("<i", FLAG - (here() + 7)) + b"\x00"
    jne = len(b); b += bytes.fromhex("75") + b"\x00"
    kpos = []
    for ld, st in (("f30f1007", "f30f1107"), ("f30f104714", "f30f114714")):
        b += bytes.fromhex(ld) + bytes.fromhex("f30f5905") + b"\x00\x00\x00\x00"; kpos.append(len(b))
        b += bytes.fromhex(st)
    b[jne + 1] = len(b) - (jne + 2)
    b += b"\xc3"
    while len(b) % 4: b += b"\xcc"
    k075 = here(); b += struct.pack("<f", 0.75)
    for p in kpos: b[p - 4:p] = struct.pack("<i", k075 - (base + p))
    return bytes(b), tcave, pcave
C5, TCAVE5, PCAVE5 = cave5()
P5 = [
    ("viewport: ignore force16x9", 0x14053e143, bytes.fromhex("744b"), bytes.fromhex("eb4b")),
    ("tan call (frustum, flag)", 0x1404571eb, callrel(0x1404571eb, TAN), callrel(0x1404571eb, TCAVE5)),
    ("camera post-persp fix (flag)", 0x14045c64f, bytes.fromhex("440f28442450"), callrel(0x14045c64f, PCAVE5)[0:5] + b"\x90"),
]

# p6: caller-selective camera Hor+. ALLOW = env TWD_ALLOW, comma list of indices into CALLERS (default all).
CALLERS = [0x14045646a, 0x1404569bd, 0x140456a8e, 0x140456c59, 0x140457384]   # return addresses into callers of 0x14045c550
import os
def cave6():
    anyc = os.environ.get("TWD_ALLOW") == "any"
    allow = [] if anyc else [int(x) for x in os.environ.get("TWD_ALLOW", "0,1,2,3,4").split(",") if x != ""]
    base = CAVE
    b = bytearray()
    def here(): return base + len(b)
    tcave = here()                                           # frustum: always scale (superset, culling only)
    b += bytes.fromhex("4883ec28")
    b += b"\xe8" + struct.pack("<i", TAN - (here() + 5)); b += bytes.fromhex("4883c428")
    b += bytes.fromhex("f30f5905") + struct.pack("<i", K43 - (here() + 8)) + b"\xc3"
    pcave = here()
    fovmin = float(os.environ.get("TWD_FOVMIN", "0"))
    b += bytes.fromhex("440f28442458")                                           # movaps xmm8,[rsp+0x58]
    fovj = None
    if fovmin > 0:
        b += bytes.fromhex("f30f1083cc010000")                                   # movss xmm0,[rbx+0x1cc]
        b += bytes.fromhex("0f2f05") + b"\0\0\0\0"; fovk = len(b)                  # comiss xmm0,[rip+fovmin]
        b += bytes.fromhex("7200"); fovj = len(b) - 1                            # jb ret
    if not anyc: b += bytes.fromhex("8b8424" + struct.pack("<I", 0x90).hex())   # mov eax,[rsp+0x90]
    jes = []
    for i in allow:
        b += b"\x3d" + struct.pack("<I", CALLERS[i] & 0xffffffff)               # cmp eax,imm32
        jes.append(len(b)); b += bytes.fromhex("74") + b"\x00"                   # je do
    rt = len(b)
    if not anyc: b += b"\xc3"
    do = len(b)
    for j in jes: b[j + 1] = do - (j + 2)
    kpos = []
    for ld, st in (("f30f1007", "f30f1107"), ("f30f104714", "f30f114714")):
        b += bytes.fromhex(ld) + bytes.fromhex("f30f5905") + b"\x00\x00\x00\x00"; kpos.append(len(b))
        b += bytes.fromhex(st)
    endret = len(b); b += b"\xc3"
    if fovj is not None: b[fovj] = endret - (fovj + 1)
    while len(b) % 4: b += b"\xcc"
    k075 = here(); b += struct.pack("<f", 0.75)
    kf = here(); b += struct.pack("<f", fovmin)
    for p in kpos: b[p - 4:p] = struct.pack("<i", k075 - (base + p))
    if fovj is not None: b[fovk - 4:fovk] = struct.pack("<i", kf - (base + fovk))
    return bytes(b), tcave, pcave
C6, TCAVE6, PCAVE6 = cave6()
P6 = P1 + [
    ("tan call (frustum)", 0x1404571eb, callrel(0x1404571eb, TAN), callrel(0x1404571eb, TCAVE6)),
    ("camera post-persp fix (caller-selective)", 0x14045c64f, bytes.fromhex("440f28442450"), callrel(0x14045c64f, PCAVE6)[0:5] + b"\x90"),
]

# p7 = p6 + 2D "fit to 16:9 box" layers fit to the 4:3 WIDTH instead of cropping the sides.
# The UI ortho builder 0x140039110(rcx=matrix, xmm1=left, xmm2=right, xmm3=bottom, [rsp+0x28]=top at entry, ...) is
# called by the 2D passes with an x range squeezed to 0.75 wide ([0.125,0.875]) for 4:3, which crops 12.5% off each side.
# Hook: when right-left == 0.75, make the x range 1 wide (same centre) and widen the y range by 1/0.75 about its centre.
ORTHO = 0x140039110
K_ORTHO = 0x140bcc3c4        # float constant the replaced 'movss xmm5,[rip+..]' loaded
def cave7(off):
    base = CAVE + off
    b = bytearray()
    def here(): return base + len(b)
    def rip(op, target, extra=0):            # op bytes + disp32 + extra immediate bytes already counted by caller
        d = struct.pack("<i", 0)
        b.extend(bytes.fromhex(op)); pos = len(b); b.extend(d); return pos
    fix = []                                  # (pos, target label)
    def ripref(op, label):
        pos = rip(op, 0); fix.append((pos, label))
    code = bytearray()
    b += bytes.fromhex("f30f10e2" "f30f5ce1")                  # movss xmm4,xmm2 ; subss xmm4,xmm1   (w)
    ripref("0f2f25", "lo"); jb = len(b); b += bytes.fromhex("0f82") + b"\0\0\0\0"
    ripref("0f2f25", "hi"); ja = len(b); b += bytes.fromhex("0f87") + b"\0\0\0\0"
    ripref("f30f102d", "half")
    b += bytes.fromhex("f30f10442428" "f30f58c3" "f30f59c5")  # xmm0=(top+bottom)*0.5
    b += bytes.fromhex("0f28e8" "f30f5ceb" "f30f5eec" "0f28d8" "f30f5cdd")   # xmm5=yc; xmm5-=b ; /=w ; xmm3=yc ; xmm3-=xmm5
    b += bytes.fromhex("f30f106c2428" "f30f5ce8" "f30f5eec" "f30f58e8" "f30f116c2428")          # top = yc+(top-yc)/w
    ripref("f30f102d", "half")
    b += bytes.fromhex("0f28c1" "f30f58c2" "f30f59c5" "0f28c8" "f30f5ccd" "0f28d0" "f30f58d5")  # x: centre +-0.5
    skip = len(b)
    b += bytes.fromhex("4883ec28")
    ripref("f30f102d", "K")
    b += b"\xe9" + struct.pack("<i", (ORTHO + 12) - (here() + 5))
    while len(b) % 4: b += b"\xcc"
    lab = {"lo": len(b)}; b += struct.pack("<f", 0.7499)
    lab["hi"] = len(b); b += struct.pack("<f", 0.7501)
    lab["half"] = len(b); b += struct.pack("<f", 0.5)
    for pos, label in fix:
        tgt = (K_ORTHO if label == "K" else base + lab[label])
        b[pos:pos + 4] = struct.pack("<i", tgt - (base + pos + 4))
    b[jb + 2:jb + 6] = struct.pack("<i", skip - (jb + 6))
    b[ja + 2:ja + 6] = struct.pack("<i", skip - (ja + 6))
    return bytes(b), base
C7, CAVE7 = cave7(0x200)
P7 = P6 + [
    ("ortho builder fit-to-width", ORTHO, bytes.fromhex("4883ec28f30f102d") + struct.pack("<i", K_ORTHO - (ORTHO + 12)), b"\xe9" + struct.pack("<i", CAVE7 - (ORTHO + 5)) + b"\x90" * 7),
]

# dbgs: p1 + OutputDebugStringA camera trace (asm/camlog.s, assembled with tools/asm.py; needs clang, dev only)
def cave_dbgs():
    import subprocess
    h = subprocess.check_output([sys.executable, "-I", os.path.join(os.path.dirname(os.path.abspath(__file__)), "asm.py"),
                                 os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "asm", "camlog.s")]).decode().strip()
    return bytes.fromhex(h)
P_DBGS = P1 + [
    ("camera trace", 0x14045c64f, bytes.fromhex("440f28442450"), callrel(0x14045c64f, CAVE)[0:5] + b"\x90"),
]

# p8 experiment: Lua RenderGetAspectRatio returns the 16:9 design aspect (scripts lay UI out for 16:9)
P8 = P6 + [
    ("Lua RenderGetAspectRatio -> 16:9", 0x140679618, callrel(0x140679618, 0x14053e0f0), callrel(0x140679618, 0x14053e0a0)),
]
LEVELS = {"p8": P8, "dbgs": P_DBGS, "p7": P7, "p6": P6, "p5": P5, "p1": P1, "p2": P2, "p3": P3, "p4": P4, "dbg": P_DBG, "dbg0": P_DBG}


def rva2off(d, va):
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    ns = struct.unpack_from("<H", d, pe + 6)[0]
    so = pe + 24 + struct.unpack_from("<H", d, pe + 20)[0]
    for i in range(ns):
        o = so + 40 * i
        vs, vaddr, rs, ro = struct.unpack_from("<IIII", d, o + 8)
        r = va - BASE
        if vaddr <= r < vaddr + vs:
            return r - vaddr + ro
    raise SystemExit("va %#x not in any section" % va)


def add_unwind(out, begin_va, size, prolog, alloc):
    """Register a RUNTIME_FUNCTION (+ UNWIND_INFO in .bind at CAVE+0x300) so exceptions raised inside API calls made
    from the cave (OutputDebugString raises DBG_PRINTEXCEPTION_C) can unwind through it. Cave prologue: `sub rsp,alloc`."""
    pe = struct.unpack_from("<I", out, 0x3C)[0]
    ns = struct.unpack_from("<H", out, pe + 6)[0]
    opt = pe + 24
    so = opt + struct.unpack_from("<H", out, pe + 20)[0]
    sec = {}
    for i in range(ns):
        o = so + 40 * i
        sec[bytes(out[o:o + 8]).rstrip(b"\0")] = o
    ex_o = opt + 112 + 8 * 3
    ex_rva, ex_sz = struct.unpack_from("<II", out, ex_o)
    pd = sec[b".pdata"]
    vs, va, rs, ro = struct.unpack_from("<IIII", out, pd + 8)
    assert ex_rva == va and ex_sz + 12 <= rs, "no room in .pdata"
    uw_va = CAVE + 0x300
    uw = bytes([1, prolog, 1, 0, prolog, ((alloc - 8) // 8 << 4) | 2, 0, 0])      # ver1, prolog, 1 code: ALLOC_SMALL
    uo = rva2off(out, uw_va); out[uo:uo + len(uw)] = uw
    ent = struct.pack("<III", begin_va - BASE, begin_va - BASE + size, uw_va - BASE)
    out[ro + ex_sz:ro + ex_sz + 12] = ent
    struct.pack_into("<II", out, ex_o, ex_rva, ex_sz + 12)
    struct.pack_into("<I", out, pd + 8, max(vs, ex_sz + 12))


def main():
    a = sys.argv[1:]
    level = "p1"
    if a[:1] == ["--level"]:
        level, a = a[1], a[2:]
    if level not in LEVELS or len(a) != 2:
        raise SystemExit(__doc__)
    d = open(a[0], "rb").read()
    h = hashlib.sha256(d).hexdigest()
    if h != PRISTINE:
        raise SystemExit("refusing: input sha256 %s is not the known pristine WDC.exe" % h)
    out, _ = unstub(d, keep_bind=(level != "p1"))
    out = bytearray(out)
    if level != "p1":
        k = rva2off(out, K43)
        assert struct.unpack_from("<f", out, k)[0] == struct.unpack("<f", struct.pack("<f", 4 / 3))[0], "K43 constant moved"
        cb = C6 if level == "p8" else cave_dbgs() if level == "dbgs" else (C6 + b"\xcc" * (0x200 - len(C6)) + C7) if level == "p7" else C6 if level == "p6" else C5 if level == "p5" else C4 if level == "p4" else ((cave_dbg() if level == "dbg" else bytes.fromhex("440f28442458c3")) if level in ("dbg", "dbg0") else cave_bytes()); co = rva2off(out, CAVE)
        out[co:co + len(cb)] = cb
        print("cave %#x: %s" % (CAVE, cb.hex()))
    if level == "dbgs":
        add_unwind(out, CAVE, len(cave_dbgs()), 10, 0x78)
    for name, va, old, new in LEVELS[level]:
        o = rva2off(out, va)
        if bytes(out[o:o + len(old)]) != old:
            raise SystemExit("pattern mismatch for %s at %#x: %s" % (name, va, out[o:o + len(old)].hex()))
        out[o:o + len(new)] = new
        print("patched %-24s %#x %s -> %s" % (name, va, old.hex(), new.hex()))
    open(a[1], "wb").write(out)
    print("wrote %s sha256 %s" % (a[1], hashlib.sha256(out).hexdigest()))


main()
