"""Tiny helper for gen_anchor43.py: parent prop names of a scene agent record (seg starts at the name block)."""
import os, re, struct, pickle
HERE = os.path.dirname(os.path.abspath(__file__))
import ttarch2
_N = None
def _names():
    global _N
    if _N is None:
        s = set()
        raw = os.path.join(os.path.dirname(HERE), 'decomp', 'raw')
        for d, _, fs in os.walk(raw):
            s.update(f for f in fs if f.endswith('.prop'))
        _N = {ttarch2.crc64(x): x for x in s}
    return _N
def parent_names(seg):
    ln = struct.unpack_from('<I', seg, 4)[0]
    p0 = 8 + ln
    psz, ver, flags, blk, npar = struct.unpack_from('<IIIII', seg, p0)
    if ver != 2 or npar > 20: return []
    N = _names()
    return [N.get(struct.unpack_from('<Q', seg, p0 + 20 + 8 * k)[0], '?') for k in range(npar)]
