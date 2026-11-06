#!/usr/bin/env python3
"""dis.py exe VA [count] [back]: disassemble from VA-back (default 0) for count instrs (64-bit)."""
import sys,pefile,capstone
pe=pefile.PE(sys.argv[1]);b=pe.OPTIONAL_HEADER.ImageBase;d=open(sys.argv[1],'rb').read()
va=int(sys.argv[2],16);n=int(sys.argv[3]) if len(sys.argv)>3 else 40;back=int(sys.argv[4],0) if len(sys.argv)>4 else 0
va-=back
for s in pe.sections:
    if b+s.VirtualAddress<=va<b+s.VirtualAddress+s.Misc_VirtualSize:
        o=va-b-s.VirtualAddress+s.PointerToRawData;break
md=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_64)
for i,ins in enumerate(md.disasm(d[o:o+n*15],va)):
    if i>=n:break
    print('%x  %s %s'%(ins.address,ins.mnemonic,ins.op_str))
