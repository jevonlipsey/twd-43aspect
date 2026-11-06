#!/usr/bin/env python3
"""Linear-sweep .text with capstone, index every RIP-relative operand target -> [(va, text)].
usage: ripxref.py WDC.exe out.pickle"""
import sys, pickle, pefile, capstone
from collections import defaultdict
pe = pefile.PE(sys.argv[1]); base = pe.OPTIONAL_HEADER.ImageBase
d = open(sys.argv[1],'rb').read()
t = [s for s in pe.sections if s.Name.startswith(b'.text')][0]
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64); md.detail = True
idx = defaultdict(list)
code = d[t.PointerToRawData:t.PointerToRawData+t.Misc_VirtualSize]
va = base + t.VirtualAddress; pos = 0
while pos < len(code):
    n = 0
    for ins in md.disasm(code[pos:pos+0x100000], va + pos):
        n += 1
        for op in ins.operands:
            if op.type == capstone.x86.X86_OP_MEM and op.mem.base == capstone.x86.X86_REG_RIP:
                idx[ins.address + ins.size + op.mem.disp].append(ins.address)
        last = ins
    if n == 0: pos += 1
    else: pos = last.address + last.size - va
pickle.dump(dict(idx), open(sys.argv[2],'wb'))
print(len(idx), 'targets')
