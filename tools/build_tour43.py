#!/usr/bin/env python3
"""Build the TEST-ONLY warp tour set (never shipped): set PC_P43_TOUR -> <Menu>, priority 700, one file DebugLoader.lua.

  TWD_LUAC=<luac from tools/build_luac52.sh> python3 tools/build_tour43.py [outdir]

Stock ships no DebugLoader.lua; Menu/Menu_main.lua:16 requires it when present. mod/TWD43/DebugLoader.lua sets prefs
"TWD43 Tour" = 1 in the Definitive menu and starts WalkingDead101; the season test sets (build_fix43.py without
--release, which append mod/TWD43/TWD43_tour.lua) chain 201 -> 301 -> 401 -> M101. Rollback = delete the two files."""
import hashlib, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ttarch2  # noqa: E402
from build_fix43 import REPO, descriptor, luac  # noqa: E402

TOUR = dict(set='PC_P43_TOUR', dest='Menu', prio=700)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    first = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--first=')), None)
    out = args[0] if args else os.path.join(REPO, 'out', 'tour43')
    src = open(os.path.join(REPO, 'mod', 'TWD43', 'DebugLoader.lua'), 'rb').read()
    if first:   # test: start the tour at another episode (e.g. --first=WalkingDead201)
        assert b'local kFirst = "WalkingDead101"' in src
        src = src.replace(b'local kFirst = "WalkingDead101"', ('local kFirst = "%s"' % first).encode())
    enc, bc = luac(src, 'DebugLoader.lua')
    desc, dname, aname = descriptor(TOUR)
    os.makedirs(out, exist_ok=True)
    ttarch2.write_archive(os.path.join(out, aname), [('DebugLoader.lua', enc)])
    open(os.path.join(out, dname), 'wb').write(ttarch2.encrypt_lua(desc.encode(), b'\x1bLEo'))
    _, back = ttarch2.read_archive(os.path.join(out, aname))
    got = {f['name']: f['data'] for f in back}
    assert list(got) == ['DebugLoader.lua'] and ttarch2.decrypt_lua(got['DebugLoader.lua']) == bc
    assert ttarch2.decrypt_lua(open(os.path.join(out, dname), 'rb').read()) == desc.encode()
    assert 'set.logicalDestination = "<Menu>"' in desc and 'set.priority = 700' in desc
    for n in (dname, aname):
        p = os.path.join(out, n)
        print(hashlib.sha256(open(p, 'rb').read()).hexdigest(), n, os.path.getsize(p))


if __name__ == '__main__':
    main()
