#!/usr/bin/env python3
"""Build the per-season 4:3 UI set (re-anchor + choice wrap + vert+ channel): one resource-set patch per season.

  TWD_LUAC=<luac from tools/build_luac52.sh> python3 tools/build_fix43.py <S1|S2|S3|S4|M> [outdir] [--release]

S1 -> set PC_P43_S1X on <ProjectSeason1>, priority 710: overrides Tooltip.lua again (the shipped label fix from
      mod/ProjectSeason1/Tooltip.lua + require("TWD43_fix.lua")); the shipped PC_P43_S1 set stays untouched beside it.
S2/S3/S4/M -> set PC_P43_S<n> on <ProjectSeason<n>>, priority 700: overrides Brightness.lua (an empty stock chunk
      that every EpisodeSystem.lua requires) with require(stock copy) + require("TWD43_fix.lua").
TWD43_fix.lua = season config + mod/TWD43/anchors_<season>.lua (tools/gen_anchor43.py) + mod/TWD43/TWD43_fix.lua.
All Lua is compiled to the game's Lua 5.2 bytecode and LEn-encrypted (encrypted source is silently ignored).
--release drops the " [43]" markers."""
import hashlib, os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ttarch2  # noqa: E402
from build_tooltipmod import DESCRIPTOR as S1_DESCRIPTOR, HEADER  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEASON = {
    'S1': dict(set='PC_P43_S1X', dest='ProjectSeason1', prio=710, hook='Tooltip.lua', arch='ProjectSeason1',
               marked=['ui_choice_notification_text', 'ui_helptext_text', 'ui_dialog_Item2Gamepad', 'ui_dialog_Item3Gamepad']),
    'S2': dict(set='PC_P43_S2', dest='ProjectSeason2', prio=700, hook='Brightness.lua', arch='ProjectSeason2',
               marked=['ui_reticle_textVerb', 'ui_notification_textExclamation', 'ui_notification_textQuestion',
                       'ui_death_text'] + ['ui_dialog_button%d' % i for i in range(1, 5)]),
    'S3': dict(set='PC_P43_S3', dest='ProjectSeason3', prio=700, hook='Brightness.lua', arch='ProjectSeason3',
               marked=['ui_reticle_textVerb', 'ui_notification_text'] + ['ui_dialog_controller%d' % i for i in range(1, 5)]),
    'S4': dict(set='PC_P43_S4', dest='ProjectSeason4', prio=700, hook='Brightness.lua', arch='ProjectSeason4',
               marked=['ui_notification_text'] + ['ui_dialog_controller%d' % i for i in range(1, 5)],
               extra_wrap=11.0),
    'M': dict(set='PC_P43_SM', dest='ProjectSeasonM', prio=700, hook='Brightness.lua', arch='ProjectSeasonM',
              marked=['ui_reticle_textVerb', 'ui_notification_choiceText', 'ui_notification_tutorialText',
                      'ui_titleCard_textTitle'] + ['ui_dialog_controller%d' % i for i in range(1, 5)],
              extra_wrap=11.0),
}


def descriptor(c):
    arch = 'WDC_pc_%s_data.ttarch2' % c['set']
    d = S1_DESCRIPTOR.replace('PC_P43_S1', c['set']).replace('<ProjectSeason1>', '<%s>' % c['dest'])
    d = d.replace('set.priority = 700', 'set.priority = %d' % c['prio'])
    assert c['set'] in d and ('<%s>' % c['dest']) in d and ('priority = %d' % c['prio']) in d
    return d, '_resdesc_50_%s_01.lua' % c['set'], arch


def luac(src_text, name):
    luacp = os.environ.get('TWD_LUAC') or sys.exit('set TWD_LUAC to the luac built by tools/build_luac52.sh')
    with tempfile.TemporaryDirectory() as d:
        open(os.path.join(d, name), 'wb').write(src_text)
        subprocess.run([luacp, '-o', 'out.luac', name], cwd=d, check=True)
        bc = open(os.path.join(d, 'out.luac'), 'rb').read()
    assert bc.startswith(HEADER), 'luac output is not the game\'s Lua 5.2 bytecode format'
    return ttarch2.encrypt_lua(bc, b'\x1bLEn'), bc


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    release = '--release' in sys.argv
    season = args[0]; c = SEASON[season]
    out = args[1] if len(args) > 1 else os.path.join(REPO, 'out', 'fix43_' + season)
    _, stock = ttarch2.read_archive(os.path.join(REPO, 'original', 'archives', 'WDC_pc_%s_data.ttarch2' % c['arch']))
    stock = {f['name']: f['data'] for f in stock}
    hook_stock = stock[c['hook']]; assert hook_stock[:4] == b'\x1bLEn'
    stock_name = 'TWD43_%s_stock.lua' % c['hook'][:-4]
    cfg = 'TWD43_SEASON = "%s"\nTWD43_MARKER = %s\nTWD43_MARKED = {%s}\n' % (
        season, 'nil' if release else '" [43]"', ', '.join('"%s"' % m for m in c['marked']))
    anchors = open(os.path.join(REPO, 'mod', 'TWD43', 'anchors_%s.lua' % season)).read()
    if c.get('extra_wrap'):
        rows = ''.join('  {"ui_dialog_%s%d", 0, %.3f},  -- runtime-only choice agents (not in the scene files)\n'
                       % (k, i, c['extra_wrap']) for k in ('controller', 'mouse') for i in range(1, 5))
        anchors = anchors.replace('TWD43_WRAP = {\n', 'TWD43_WRAP = {\n' + rows)
    fix = cfg + anchors + open(os.path.join(REPO, 'mod', 'TWD43', 'TWD43_fix.lua')).read()
    fix_enc, fix_bc = luac(fix.encode(), 'TWD43_fix.lua')
    if season == 'S1':
        t = open(os.path.join(REPO, 'mod', 'ProjectSeason1', 'Tooltip.lua'), 'rb').read()
        if release:
            t = t.replace(b'TWD43_MARKER = " [43]"', b'TWD43_MARKER = nil')
        hook_src = t + b'\nrequire("TWD43_fix.lua")\n'
        stock_name = 'TWD43_Tooltip_stock.lua'
    else:
        hook_src = ('require("%s")\nrequire("TWD43_fix.lua")\n' % stock_name).encode()
    hook_enc, hook_bc = luac(hook_src, c['hook'])
    files = [(c['hook'], hook_enc), (stock_name, hook_stock), ('TWD43_fix.lua', fix_enc)]
    desc, dname, aname = descriptor(c)
    os.makedirs(out, exist_ok=True)
    ttarch2.write_archive(os.path.join(out, aname), files)
    open(os.path.join(out, dname), 'wb').write(ttarch2.encrypt_lua(desc.encode(), b'\x1bLEo'))
    _, back = ttarch2.read_archive(os.path.join(out, aname))
    got = {f['name']: f['data'] for f in back}
    assert ttarch2.decrypt_lua(got[c['hook']]) == hook_bc and ttarch2.decrypt_lua(got['TWD43_fix.lua']) == fix_bc
    assert got[stock_name] == hook_stock
    assert ttarch2.decrypt_lua(open(os.path.join(out, dname), 'rb').read()) == desc.encode()
    open(os.path.join(out, 'TWD43_fix.src.lua'), 'w').write(fix)   # for the Mac stub test (not deployed)
    for n in (dname, aname):
        p = os.path.join(out, n)
        print(hashlib.sha256(open(p, 'rb').read()).hexdigest(), n, os.path.getsize(p))


if __name__ == '__main__':
    main()
