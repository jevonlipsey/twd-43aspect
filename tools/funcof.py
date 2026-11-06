#!/usr/bin/env python3
"""funcof.py exe VA...: print the .pdata function containing each VA."""
import sys,struct,bisect,pefile
pe=pefile.PE(sys.argv[1]);b=pe.OPTIONAL_HEADER.ImageBase
rf=sorted((f.struct.BeginAddress,f.struct.EndAddress) for f in pe.DIRECTORY_ENTRY_EXCEPTION)
st=[x[0] for x in rf]
for a in sys.argv[2:]:
    r=int(a,16)-b;i=bisect.bisect_right(st,r)-1
    print(a,'in',hex(b+rf[i][0]),hex(b+rf[i][1]) if rf[i][0]<=r<rf[i][1] else '(none)')
