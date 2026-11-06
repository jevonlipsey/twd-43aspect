import sys,pickle,pefile
pe=pefile.PE(sys.argv[1]);base=pe.OPTIONAL_HEADER.ImageBase
idx=pickle.load(open(sys.argv[2],'rb'))
def o2v(o):
    for s in pe.sections:
        if s.PointerToRawData<=o<s.PointerToRawData+s.SizeOfRawData: return base+o-s.PointerToRawData+s.VirtualAddress
for a in sys.argv[3:]:
    o=int(a,16); v=o2v(o); print(a,hex(v),[hex(x) for x in idx.get(v,[])])
