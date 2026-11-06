#!/usr/bin/env python3
"""callers.py exe VA...: list direct call/jmp rel32 sites targeting VA (scan .text for E8/E9)."""
import sys,struct,pefile
pe=pefile.PE(sys.argv[1]);b=pe.OPTIONAL_HEADER.ImageBase;d=open(sys.argv[1],'rb').read()
t=[s for s in pe.sections if s.Name.startswith(b'.text')][0]
tg=[int(a,16) for a in sys.argv[2:]]
for i in range(t.PointerToRawData,t.PointerToRawData+t.SizeOfRawData-5):
    if d[i] in (0xE8,0xE9):
        va=b+t.VirtualAddress+i-t.PointerToRawData
        x=va+5+struct.unpack_from('<i',d,i+1)[0]
        if x in tg: print(hex(x),'<-',hex(va),'call' if d[i]==0xE8 else 'jmp')
