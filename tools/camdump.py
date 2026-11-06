#!/usr/bin/env python3
"""camdump.py dump.bin : decode the dbg camera log. dump.bin = 0x1000 bytes from VA 0x140f2c000; log at +0xb00,
16 entries x 64 bytes after a 16-byte header: cam, ret addr, cam[0x1c0..0x1d0), cam[0x1cc..0x1dc), cam[0x50], cam[0x58]."""
import sys,struct
d=open(sys.argv[1],'rb').read()[0xb00:]
for i in range(16):
    o=0x10+i*64
    cam,ret=struct.unpack_from('<QQ',d,o)
    if not cam: continue
    f=struct.unpack_from('<8f',d,o+16)   # 0x1c0,1c4,1c8,1cc | 1cc,1d0,1d4,1d8
    p50,p58=struct.unpack_from('<QQ',d,o+48)
    print('%2d cam %#x ret %#x  aspect1c4=%g fscale1c8=%g fov1cc=%g 1d0=%g 1d4=%g 1d8=%g 1c0=%#x [50]=%#x [58]=%#x'%(i,cam,ret,f[1],f[2],f[3],f[5],f[6],f[7],struct.unpack_from('<I',d,o+16)[0],p50,p58))
