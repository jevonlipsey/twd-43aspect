#!/usr/bin/env python3
"""gen_anchor43.py: derive the 4:3 re-anchor table for one season from its UI scenes (decomp/raw), as Lua.

  python3 -I tools/gen_anchor43.py <S1|S2|S3|S4|M>  > mod/TWD43/anchors_<season>.lua

Geometry: each UI scene has one camera (cam_*). The engine renders a camera at 0.75 x its authored "Field of View"
(S1 tooltip measurement; every pin then sits exactly on the 16:9 edge). Half-height at an agent = d * tan(0.375*fov).
An agent is CUT at 4:3 when 0.97*h43 < |x| <= 1.03*h169. For each cut agent we move the highest ancestor that is
itself off-centre (|x| > 0.5*h43), skipping anything under a pin (ui_pin.prop: UI.lua snaps those at runtime) and
art/debug scenes. Rows: {scene, agent, authored local x, half-height, sign}. At runtime dx = halfH*(16/9-aspect),
x_new = x - sign*dx (keeps the authored distance from the screen edge, at authored size).
Dialogue: every agent of ui_dialog*.scene whose effective "Text Width" (own or inherited through its parent props;
0 = unlimited) is wider than the room left inside 4:3 gets that room as its wrap width (never widened)."""
import sys, os, math, struct
HERE = os.path.dirname(os.path.abspath(__file__)); REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import ttarch2
RAW = os.path.join(REPO, 'decomp', 'raw')
SETS = {'S1': ['ProjectSeason1'], 'S2': ['ProjectSeason2'], 'S3': ['UISeason3', 'ProjectSeason3'],
        'S4': ['UISeason4', 'ProjectSeason4'], 'M': ['UISeasonM', 'ProjectSeasonM']}
EXCLUDE = {'text_activateDF_old', 'ui_dialogBox_windowLayer6', 'ui_dialogBox_windowLayer7'}
SKIP_SCENE = ('credits', 'crowdplay', 'debug', 'fx_', 'platformdata', 'animatable', 'legaltext', 'tooltip')
FOVK = struct.pack('<Q', ttarch2.crc64('Field of View'))
WIDK = struct.pack('<Q', ttarch2.crc64('Text Width'))
ALNK = struct.pack('<Q', ttarch2.crc64('Text Alignment Horizontal'))
SCK = struct.pack('<Q', ttarch2.crc64('Text Scale'))
OFK = struct.pack('<Q', ttarch2.crc64('Text Offset'))
MLK = struct.pack('<Q', ttarch2.crc64('Text Max Lines To Display'))
LOCK = bytes.fromhex('3501f227b521abcd')      # "Scene: Location Info" (pos/quat + attach)
POSK = bytes.fromhex('39c4d804443bfba1')      # older scenes: position Vector3
ATTK = bytes.fromhex('41a5371ef75bbf42')      # "Scene: Attach Agent"
PINP = struct.pack('<Q', ttarch2.crc64('ui_pin.prop'))


def records(b):
    import re
    out = []
    for m in re.finditer(rb'[\x05-\x7f]\x00\x00\x00([\x01-\x77])\x00\x00\x00', b):
        blk = struct.unpack_from('<I', b, m.start())[0]; ln = m.group(1)[0]
        if blk != ln + 8: continue
        s = b[m.end():m.end() + ln]
        if re.fullmatch(rb'[A-Za-z0-9_.\-]+', s) and struct.unpack_from('<I', b, m.end() + ln + 4)[0] == 2:
            out.append((m.start(), s.decode()))
    res = {}
    for i, (o, name) in enumerate(out):
        end = out[i + 1][0] if i + 1 < len(out) else len(b)
        seg = b[o:end]; pos = None; att = ''
        k = seg.find(LOCK)
        if k >= 0:
            q = o + k + 8; sblk = struct.unpack_from('<I', b, q)[0]
            sd = b[q + 4:q + sblk]
            if len(sd) > 4: att = sd[4:4 + struct.unpack_from('<I', sd, 0)[0]].decode('latin-1')
            for t in range(q + sblk, min(q + sblk + 200, len(b) - 32)):
                if struct.unpack_from('<I', b, t)[0] == 0x20:
                    f = struct.unpack_from('<7f', b, t + 4)
                    if abs(sum(x * x for x in f[:4]) - 1) < 1e-3: pos = f[4:7]; break
        else:
            k = seg.find(POSK)
            if k >= 0:
                pos = struct.unpack_from('<3f', b, o + k + 8)
                ka = seg.find(ATTK)
                if ka >= 0:
                    ln = struct.unpack_from('<I', b, o + ka + 8)[0]; att = b[o + ka + 12:o + ka + 12 + ln].decode('latin-1')
        if pos is None or name in res: continue
        res[name] = dict(pos=pos, att=att, seg=seg)
    return res


def fval(seg, key):
    i = seg.find(key)
    return struct.unpack_from('<f', seg, i + 8)[0] if i >= 0 else None


_INDEX = None


def _prop_index():
    global _INDEX
    if _INDEX is None:
        _INDEX = {}
        for d, _, fs in os.walk(RAW):
            for f in fs:
                if f.endswith('.prop'):
                    _INDEX.setdefault(f.lower(), []).append(os.path.join(d, f))
    return _INDEX


def _prop_file_parents(b):
    """Parent prop names of a .prop file's own PropertySet (header after the class table)."""
    from scenedump_lite import _names
    try:
        ncls = struct.unpack_from('<I', b, 0x10)[0]; p0 = 0x14 + 12 * ncls - 4
        psz, ver, flags, blk, npar = struct.unpack_from('<IIIII', b, p0)
    except struct.error:
        return []
    if ver != 2 or npar > 20: return []
    return [_names().get(struct.unpack_from('<Q', b, p0 + 20 + 8 * k)[0], '?') for k in range(npar)]


def prop_raw(names, dirs, key, depth=0, seen=None):
    """(file bytes, offset of key) of the first parent prop (depth-first through the whole parent chain, the way a
    PropertySet inherits) that defines key; season dirs are preferred over Project and other sets."""
    seen = set() if seen is None else seen
    for n in names:
        if not n or n == '?' or n.lower() in seen or depth > 12: continue
        seen.add(n.lower())
        paths = _prop_index().get(n.lower(), [])
        pref = [os.path.join(RAW, d, n).lower() for d in dirs + ['Project']]
        paths = sorted(paths, key=lambda q: pref.index(q.lower()) if q.lower() in pref else len(pref))
        for p in paths[:1]:
            b = open(p, 'rb').read(); i = b.find(key)
            if i >= 0: return b, i
            r = prop_raw(_prop_file_parents(b), dirs, key, depth + 1, seen)
            if r: return r
    return None


def prop_val(names, dirs, key, depth=0):
    r = prop_raw(names, dirs, key)
    return struct.unpack_from('<f', r[0], r[1] + 8)[0] if r else None


def parents_of(seg):
    try:
        psz, ver, flags, blk, npar = struct.unpack_from('<IIIII', seg, 8 + struct.unpack_from('<I', seg, 4)[0])
    except struct.error:
        return []
    return []


def scene(path, dirs):
    from scenedump_lite import parent_names
    b = open(path, 'rb').read(); R = records(b)
    cams = [n for n in R if n.startswith('cam')]
    if not cams: return None
    cam = cams[0]; cz = R[cam]['pos'][2]
    fov = fval(R[cam]['seg'], FOVK) or prop_val(parent_names(R[cam]['seg']), dirs, FOVK)
    if not fov: return None
    t = math.tan(math.radians(fov * 0.75) / 2)

    def world(n, d=0):
        x, y, z = R[n]['pos']
        a = R[n]['att']
        if a and a in R and d < 12:
            px, py, pz = world(a, d + 1); return x + px, y + py, z + pz
        return x, y, z

    def chain(n):
        c = [n]
        while R[c[-1]]['att'] in R and len(c) < 12: c.append(R[c[-1]]['att'])
        return c

    def is_pin(n):
        return PINP in R[n]['seg'][:200] or 'pin' in n.lower().split('_')[-1].lower()
    return dict(R=R, cam=cam, cz=cz, t=t, world=world, chain=chain, is_pin=is_pin, fov=fov)


def main():
    season = sys.argv[1]; dirs = SETS[season]
    anchors, widths = {}, []
    for d in dirs:
        for f in sorted(os.listdir(os.path.join(RAW, d))):
            if not f.endswith('.scene') or any(s in f.lower() for s in SKIP_SCENE): continue
            S = scene(os.path.join(RAW, d, f), dirs)
            if not S: continue
            R, world, cz, t = S['R'], S['world'], S['cz'], S['t']
            for n in R:
                if n == S['cam'] or n.startswith('light') or n.endswith('.scene'): continue
                x, y, z = world(n); dd = abs(cz - z)
                if dd < 1e-3: continue
                hh = dd * t; h43, h169 = hh * 4 / 3, hh * 16 / 9
                ch = S['chain'](n)
                if any(S['is_pin'](c) for c in ch): continue
                if f.startswith('ui_dialog') and not f.startswith('ui_dialogBox'):
                    from scenedump_lite import parent_names
                    pn = parent_names(R[n]['seg'])
                    w = fval(R[n]['seg'], WIDK)
                    if w is None:                 # inherited through the parent props (0 = unlimited)
                        w = prop_val(pn, dirs, WIDK)
                    ai = R[n]['seg'].find(ALNK)
                    if ai >= 0:
                        al = R[n]['seg'][ai + 8]
                    else:
                        ra = prop_raw(pn, dirs, ALNK)
                        al = ra[0][ra[1] + 8] if ra else 2
                    # S2 buttons place their text with "Text Offset" (+-0.6 from the icon): count it in the reach
                    oi = R[n]['seg'].find(OFK)
                    ofs = struct.unpack_from('<f', R[n]['seg'], oi + 8)[0] if oi >= 0 else 0.0
                    if oi < 0:
                        ro = prop_raw(pn, dirs, OFK)
                        ofs = struct.unpack_from('<f', ro[0], ro[1] + 8)[0] if ro else 0.0
                    reach = abs(x + ofs)
                    room = (2 * (h43 - 0.4 - reach)) if al == 2 else (h43 - 0.4 - reach)
                    # "Text Width" is in unscaled text units: the wrap happens at width * "Text Scale" in the scene
                    # (device-measured 2026-11-08, S1 choices at scale 0.547 broke at ~half the room without this)
                    sc = fval(R[n]['seg'], SCK) or prop_val(pn, dirs, SCK) or 1.0
                    room = room / sc
                    import re as _re
                    choice = _re.fullmatch(r'ui_dialog_(controller|button|box|mouse|mouseAJ|Item)\d(Gamepad)?', n)
                    # only ever NARROW the authored wrap width (or give an unlimited choice line one): a row that
                    # widened it would change the authored layout (S2 buttons 9.0, S3/M 4.5, S4 7.0 with 2 lines)
                    # an authored width within 10% of the room is left alone (inside the 0.4 edge margin; M's 2-line
                    # controller choices are 4.5 vs 4.3), and crowd-play icons are never choice text
                    # a line-capped choice (S3/S4/M controllers: Max Lines 2) is never narrowed: an extra wrapped
                    # line would be cut off, not shown
                    mi = R[n]['seg'].find(MLK)
                    if mi >= 0:
                        ml = struct.unpack_from('<i', R[n]['seg'], mi + 8)[0]
                    else:
                        rm = prop_raw(pn, dirs, MLK)
                        ml = struct.unpack_from('<i', rm[0], rm[1] + 8)[0] if rm else 0
                    if ml <= 0 and 'crowdplay' not in n.lower() and room > 0.5 and ((w and w > 1.1 * room) or (choice and not w)):
                        widths.append((f, n, round(w or 0, 3), round(room, 3), al))
                if not (0.97 * h43 < abs(x) <= 1.03 * h169): continue
                tgt = n
                for c in ch[1:]:
                    if abs(world(c)[0]) > 0.5 * h43: tgt = c
                    else: break
                if tgt in anchors: continue
                sign = 1 if world(tgt)[0] > 0 else -1
                anchors[tgt] = (f, round(R[tgt]['pos'][0], 4), round(hh, 4), sign, tuple(S['chain'](tgt)[1:]))
    for n in list(anchors):                       # never move both an agent and one of its ancestors
        if any(a in anchors for a in anchors[n][4]): del anchors[n]
    for n in list(anchors):                       # hand-checked exclusions (unused/legacy/offscreen art)
        if n in EXCLUDE: del anchors[n]
    print('-- generated by tools/gen_anchor43.py %s (do not edit by hand)' % season)
    print('TWD43_ANCHORS = {')
    for n, (f, x, hh, s, _) in sorted(anchors.items(), key=lambda kv: (kv[1][0], kv[0])):
        print('  {"%s", %.4f, %.4f, %d},  -- %s' % (n, x, hh, s, f))
    print('}')
    print('TWD43_WRAP = {')
    for f, n, w, room, al in widths:
        print('  {"%s", %.3f, %.3f},  -- %s authored width %.3f, align %d' % (n, w, room, f, w, al))
    print('}')


if __name__ == '__main__':
    main()
