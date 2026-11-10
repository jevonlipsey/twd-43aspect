#!/usr/bin/env python3
"""Build the optional hold-B cutscene skip sets (one per season) that sit BESIDE the 4:3 sets.

  TWD_LUAC=<luac from tools/build_luac52.sh> python3 tools/build_skip43.py <S1|S2|S3|S4|M|all> [outdir_prefix]
  -> out/skip43_<s>/ : _resdesc_50_PC_P43_SKIP_<s>_01.lua + WDC_pc_PC_P43_SKIP_<s>_data.ttarch2 (+ .src for stubs)

Mechanism adapted from the Nexus "TWDG-Skip" mod (TWD Definitive Series mod 333): mod/TWD43/TWD43_skip.lua.
Sets: PC_P43_SKIP_<s> -> <ProjectSeason..>, priority 720 (above the 4:3 sets' 700/710), "patch", constant.
Hooks:
  S1      module_dialog_manager.lua (as the original mod): our wrapper requires the stock file, renamed
          TWD43_skip_dlgmgr_stock.lua (stock LEn bytes from the user's WDC_pc_ProjectSeason1_data.ttarch2), then
          the skip. The 4:3 S1 sets override Tooltip.lua, not this file: no overlap.
  S2-M    Brightness.lua, an EMPTY stock chunk that the 4:3 sets ALSO override (with exactly
          `require("TWD43_fix.lua")`). MERGED: ours first runs that same require when the 4:3 set is installed
          (ResourceExists), then the skip, so the 4:3 fix still loads exactly as before. No game file in these sets.
          The build asserts that the 4:3 hook is still that one line (else the merge would drop something).
"""
import hashlib, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import ttarch2  # noqa: E402
import build_fix43  # noqa: E402

SEASONS = {
    'S1': dict(set='PC_P43_SKIP_S1', dest='ProjectSeason1', n=1, hook='module_dialog_manager.lua'),
    'S2': dict(set='PC_P43_SKIP_S2', dest='ProjectSeason2', n=2, hook='Brightness.lua'),
    'S3': dict(set='PC_P43_SKIP_S3', dest='ProjectSeason3', n=3, hook='Brightness.lua'),
    'S4': dict(set='PC_P43_SKIP_S4', dest='ProjectSeason4', n=4, hook='Brightness.lua'),
    'M': dict(set='PC_P43_SKIP_SM', dest='ProjectSeasonM', n=5, hook='Brightness.lua'),
}
PRIO = 720
STOCK_DLGMGR = '65f453745b23f6cb'   # sha256 prefix of the stock S1 module_dialog_manager.lua (LEn) in the Steam build
FIX43_HOOK = b'require("TWD43_fix.lua")\n'   # the 4:3 sets' Brightness.lua source (build_fix43.py)


def hook_source(c):
    skip = ('TWDSkipIntegratedSeason = %d\n'
            'local ok, err = pcall(require, "TWD43_skip.lua")\n'
            'TWDSkipIntegratedSeason = nil\n' % c['n'])
    if c['hook'] == 'Brightness.lua':
        return ('-- twd-43aspect skip set: merged hook (stock Brightness.lua is empty)\n'
                'if ResourceExists("TWD43_fix.lua") then\n  require("TWD43_fix.lua")\nend\n' + skip).encode()
    return ('require("TWD43_skip_dlgmgr_stock.lua")\n' + skip).encode()


def build(season, out):
    c = SEASONS[season]
    _, stock = ttarch2.read_archive(os.path.join(REPO, 'original', 'archives', 'WDC_pc_%s_data.ttarch2' % c['dest']))
    stock = {f['name']: f['data'] for f in stock}
    hook_stock = stock[c['hook']]
    assert hook_stock[:4] == b'\x1bLEn'
    files = []
    if c['hook'] == 'Brightness.lua':
        assert hashlib.sha256(hook_stock).hexdigest() in build_fix43.EMPTY_BRIGHTNESS, 'stock Brightness.lua changed'
        # the 4:3 hook we shadow must still be the one-line require
        src = open(os.path.join(HERE, 'build_fix43.py')).read()
        assert "hook_src = b'require(\"TWD43_fix.lua\")\\n'" in src, '4:3 Brightness hook changed: re-merge'
    else:
        assert hashlib.sha256(hook_stock).hexdigest().startswith(STOCK_DLGMGR), 'stock module_dialog_manager changed'
        files.append(('TWD43_skip_dlgmgr_stock.lua', hook_stock))
    skip_src = open(os.path.join(REPO, 'mod', 'TWD43', 'TWD43_skip.lua'), 'rb').read()
    hook_enc, hook_bc = build_fix43.luac(hook_source(c), c['hook'])
    skip_enc, skip_bc = build_fix43.luac(skip_src, 'TWD43_skip.lua')
    files = [(c['hook'], hook_enc), ('TWD43_skip.lua', skip_enc)] + files
    desc, dname, aname = build_fix43.descriptor(dict(set=c['set'], dest=c['dest'], prio=PRIO))
    os.makedirs(out, exist_ok=True)
    ttarch2.write_archive(os.path.join(out, aname), files)
    open(os.path.join(out, dname), 'wb').write(ttarch2.encrypt_lua(desc.encode(), b'\x1bLEo'))
    # round trip
    _, back = ttarch2.read_archive(os.path.join(out, aname))
    got = {f['name']: f['data'] for f in back}
    assert set(got) == {n for n, _ in files}
    assert ttarch2.decrypt_lua(got[c['hook']]) == hook_bc and ttarch2.decrypt_lua(got['TWD43_skip.lua']) == skip_bc
    assert 'TWD43_skip_dlgmgr_stock.lua' not in got or got['TWD43_skip_dlgmgr_stock.lua'] == hook_stock
    assert ttarch2.decrypt_lua(open(os.path.join(out, dname), 'rb').read()) == desc.encode()
    open(os.path.join(out, 'hook.src.lua'), 'wb').write(hook_source(c))   # for the Mac stub test (not deployed)
    for n in (dname, aname):
        p = os.path.join(out, n)
        print(hashlib.sha256(open(p, 'rb').read()).hexdigest(), os.path.join(os.path.basename(out), n),
              os.path.getsize(p))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    seasons = list(SEASONS) if args[0] == 'all' else [args[0]]
    prefix = args[1] if len(args) > 1 else os.path.join(REPO, 'out', 'skip43')
    for s in seasons:
        build(s, '%s_%s' % (prefix, s))


if __name__ == '__main__':
    main()
