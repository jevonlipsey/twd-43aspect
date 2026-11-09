#!/usr/bin/env python3
"""Build the per-season 4:3 UI set (re-anchor + choice wrap + vert+ channel): one resource-set patch per season.

  TWD_LUAC=<luac from tools/build_luac52.sh> python3 tools/build_fix43.py <S1|S2|S3|S4|M> [outdir] [--release]

S1 -> set PC_P43_S1X on <ProjectSeason1>, priority 710: overrides Tooltip.lua again (the shipped label fix from
      mod/ProjectSeason1/Tooltip.lua + require("TWD43_fix.lua")); the shipped PC_P43_S1 set stays untouched beside it.
S2/S3/S4/M -> set PC_P43_S<n> on <ProjectSeason<n>>, priority 700: overrides Brightness.lua (an empty stock chunk
      that every EpisodeSystem.lua requires) with require(stock copy) + require("TWD43_fix.lua").
TWD43_fix.lua = season config + mod/TWD43/anchors_<season>.lua (tools/gen_anchor43.py) + mod/TWD43/TWD43_fix.lua.
All Lua is compiled to the game's Lua 5.2 bytecode and LEn-encrypted (encrypted source is silently ignored).
--release drops the " [43]" markers and the warp tour (mod/TWD43/TWD43_tour.lua, test builds only).
--play (hand test) keeps the markers but drops the forced-wrap choice tail and the tour.
--diag (S1 only, test) = test build + mod/TWD43/TWD43_diag.lua: choice widths flip stock/ours every 3 s, the long
      tail only on Item1/Item2Gamepad, and the tour stays in WalkingDead101 (one recorded run A/Bs the layout)."""
import hashlib, os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ttarch2  # noqa: E402
from build_tooltipmod import DESCRIPTOR as S1_DESCRIPTOR, HEADER  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEASON = {
    'S1': dict(set='PC_P43_S1X', dest='ProjectSeason1', prio=710, hook='Tooltip.lua', arch='ProjectSeason1',
               marked=['ui_choice_notification_text', 'ui_helptext_text'] + ['ui_dialog_Item%dGamepad' % i for i in range(1, 5)],
               long=['ui_dialog_Item%dGamepad' % i for i in range(1, 5)],
               # controller choice cluster (device-measured 2026-11-08, screenshots c4-s118/120/123: text moves
               # 89 px/unit, icons 67 px/unit when the parent moves): lift the cluster 0.6 (icons ~40 px) so the
               # timer bar sits below it, then Y text clear above its icon, X/B text level with theirs, A text under A
               nudge=[('dialogParentGamepad', 0.0, 0.0, 0.0, 0.6, 'add', None),
                      ('ui_dialog_Item4Gamepad', 0.0, 0.65, 0.0, 0.32, None, 1),
                      ('ui_dialog_Item2Gamepad', 0.5, -0.025, 0.0, 0.65, None, None),
                      ('ui_dialog_Item3Gamepad', -0.5, -0.025, 0.0, 0.65, None, None),
                      ('ui_dialog_Item1Gamepad', 0.0, -0.575, 0.0, 0.72, None, -1),
                      # timer bar (dialogParent child, authored y 0.465): one A line (40 px) down per extra A line
                      ('ui_dialog_timer', 0.0, 0.465, 0.0, 0.0, None, -2.67, 'ui_dialog_Item1Gamepad')]),
    'S2': dict(set='PC_P43_S2', dest='ProjectSeason2', prio=700, hook='Brightness.lua', arch='ProjectSeason2',
               marked=['ui_reticle_textVerb', 'ui_notification_textExclamation', 'ui_notification_textQuestion',
                       'ui_death_text'] + ['ui_dialog_button%d' % i for i in range(1, 5)],
               long=['ui_dialog_button%d' % i for i in range(1, 5)],
               # authored Text Offsets (ui_dialog_button1-4.prop; button1 = A below, 2 = B, 3 = X, 4 = Y above)
               glue=[('ui_dialog_button1', 0.0, -0.6), ('ui_dialog_button2', 0.6, 0.0),
                     ('ui_dialog_button3', -0.6, 0.0), ('ui_dialog_button4', 0.0, 0.6)],
               # timer (mesh, drawn at 0.75): 1.706 under the X/B row -> down 1.706 / 3 so its drawn gap stays authored
               nudge=[('ui_dialog_timer', 0.0, 0.377, 0.0, -0.57, None, None)]),
    'S3': dict(set='PC_P43_S3', dest='ProjectSeason3', prio=700, hook='Brightness.lua', arch='ProjectSeason3',
               marked=['ui_reticle_textVerb', 'ui_notification_text'] + ['ui_dialog_controller%d' % i for i in range(1, 5)],
               # UISeason3 ui_dialog_controllerFacebutton{Down,Right,Left,Up}.prop (Y text bottom-aligned, A top-aligned)
               glue=[('ui_dialog_controller1', 0.0, -0.2), ('ui_dialog_controller2', 0.25, -0.004),
                     ('ui_dialog_controller3', -0.25, -0.004), ('ui_dialog_controller4', 0.0, 0.225)],
               nudge=[('ui_dialog_timerParent', 0.0, -4.75, 0.0, -0.4, None, None)]),   # 1.2 under the cluster
    'S4': dict(set='PC_P43_S4', dest='ProjectSeason4', prio=700, hook='Brightness.lua', arch='ProjectSeason4',
               marked=['ui_notification_text'] + ['ui_dialog_controller%d' % i for i in range(1, 5)],
               # UISeason4 ui_dialog_controllerFacebutton.prop + scene overrides (icons are child agents)
               glue=[('ui_dialog_controller1', 0.0, 0.0), ('ui_dialog_controller2', 0.2, 0.0),
                     ('ui_dialog_controller3', -0.2, 0.0), ('ui_dialog_controller4', 0.0, 0.25)],
               nudge=[('ui_dialog_timerParent', 0.0, -4.75, 0.0, -0.4, None, None)]),
    'M': dict(set='PC_P43_SM', dest='ProjectSeasonM', prio=700, hook='Brightness.lua', arch='ProjectSeasonM',
              marked=['ui_reticle_textVerb', 'ui_notification_choiceText', 'ui_notification_tutorialText',
                      'ui_titleCard_textTitle'] + ['ui_dialog_controller%d' % i for i in range(1, 5)],
              # UISeasonM ui_dialog_controllerFacebutton{Down,Right,Left,Up}.prop (Text Scale 1.5)
              glue=[('ui_dialog_controller1', 0.0, -0.428), ('ui_dialog_controller2', 0.38, 0.025),
                    ('ui_dialog_controller3', -0.38, 0.025), ('ui_dialog_controller4', 0.0, 0.48)],
              nudge=[('ui_dialog_timerParent', 0.0, -4.85, 0.0, -0.45, None, None)]),   # 1.35 under the cluster
}

LONG_TAIL = ' wrap test: this option is deliberately long so that it has to break onto a second line'


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
    play = '--play' in sys.argv   # hand-test build: keeps the " [43]" marker, drops the forced-wrap tail and the tour
    diag = '--diag' in sys.argv
    assert not (diag and (release or play)), '--diag is a test build'
    season = args[0]; c = SEASON[season]
    out = args[1] if len(args) > 1 else os.path.join(REPO, 'out', 'fix43_' + season)
    _, stock = ttarch2.read_archive(os.path.join(REPO, 'original', 'archives', 'WDC_pc_%s_data.ttarch2' % c['arch']))
    stock = {f['name']: f['data'] for f in stock}
    hook_stock = stock[c['hook']]; assert hook_stock[:4] == b'\x1bLEn'
    stock_name = 'TWD43_%s_stock.lua' % c['hook'][:-4]
    cfg = 'TWD43_SEASON = "%s"\nTWD43_MARKER = %s\nTWD43_MARKED = {%s}\n' % (
        season, 'nil' if release else '" [43]"', ', '.join('"%s"' % m for m in c['marked']))
    longarg = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--long=')), None)
    longs = longarg.split(',') if longarg else (c.get('long', [])[:2] if diag else c.get('long', []))
    if not release and not play and longs:   # S3/S4/M choices keep their stock 2-line widths: no tail there
        cfg += 'TWD43_LONG = {%s}\nTWD43_LONG_TAIL = "%s"\n' % (
            ', '.join('["%s"] = true' % m for m in longs), LONG_TAIL)
    if c.get('glue'):
        cfg += 'TWD43_GLUE = {\n%s}\n' % ''.join('  {"%s", %r, %r},\n' % r for r in c['glue'])
    if c.get('nudge'):
        lua = lambda v: 'nil' if v is None else ('"%s"' % v if isinstance(v, str) else repr(v))
        cfg += 'TWD43_NUDGE = {\n%s}\n' % ''.join('  {%s},\n' % ', '.join(lua(v) for v in r) for r in c['nudge'])
    anchors = open(os.path.join(REPO, 'mod', 'TWD43', 'anchors_%s.lua' % season)).read()
    tour = '' if (release or play) else open(os.path.join(REPO, 'mod', 'TWD43', 'TWD43_tour.lua')).read()
    dwell = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--dwell=')), None)
    if dwell:   # test: per-episode tour dwell, e.g. --dwell=WalkingDead201:170,WalkingDead301:480
        assert 'kDwell = {WalkingDead101 = 180}' in tour
        tour = tour.replace('kDwell = {WalkingDead101 = 180}', 'kDwell = {%s}' % ', '.join(
            '%s = %d' % (k, int(v)) for k, v in (kv.split(':') for kv in dwell.split(','))))
    if diag:
        assert season in ('S1', 'S2')
        if season == 'S1' and not dwell:
            tour = tour.replace('kDwell = {WalkingDead101 = 180}', 'kDwell = {WalkingDead101 = 900}')
        tour += open(os.path.join(REPO, 'mod', 'TWD43', 'TWD43_diag.lua')).read()
    if '--fake' in sys.argv:
        assert not (release or play)
        tour += open(os.path.join(REPO, 'mod', 'TWD43', 'TWD43_fake.lua')).read()
    fix = cfg + anchors + tour + open(os.path.join(REPO, 'mod', 'TWD43', 'TWD43_fix.lua')).read()
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
