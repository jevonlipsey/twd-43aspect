#!/usr/bin/env python3
"""Build the 4:3 interaction-label mod: a resource-set patch on <ProjectSeason1>, no exe change.

  TWD_LUAC=<luac from tools/build_luac52.sh> python3 tools/build_tooltipmod.py [outdir] [--release]

Output (copy both into the game's Archives/ folder):
  _resdesc_50_PC_P43_S1_01.lua        descriptor (LEo-encrypted source, like the game's own)
  WDC_pc_PC_P43_S1_data.ttarch2       Tooltip.lua (mod/ProjectSeason1/Tooltip.lua compiled to the game's
                                      Lua 5.2 bytecode, LEn-encrypted like every stock script) and
                                      TWD43_Tooltip_stock.lua (the user's own Tooltip.lua, byte for byte)
--release drops the " [43]" test marker.
"""
import hashlib, os, subprocess, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ttarch2  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SET = 'PC_P43_S1'
DESC = '_resdesc_50_%s_01.lua' % SET
ARCH = 'WDC_pc_%s_data.ttarch2' % SET
HEADER = bytes.fromhex('1b4c7561520001040404040019930d0a1a0a')   # the game's Lua 5.2 bytecode header

DESCRIPTOR = '''local set = {}
set.name = "%(set)s"
set.setName = "%(set)s"
set.descriptionFilenameOverride = "%(desc)s"
set.logicalName = "<%(set)s>"
set.logicalDestination = "<ProjectSeason1>"
set.priority = 700
set.localDir = _currentDirectory
set.enableMode = "constant"
set.version = "patch"
set.descriptionPriority = 0
set.gameDataName = "%(set)s Game Data"
set.gameDataPriority = 0
set.gameDataEnableMode = "constant"
set.localDirIncludeBase = true
set.localDirRecurse = false
set.localDirIncludeOnly =
{
    "AllPlatforms/Project/",
    "AllPlatforms/_Project/",
    "HighEnd/Project/",
    "HighEnd/_Project/",
    "PC/Project/",
    "PC/_Project/"
}
set.localDirExclude =
{
    "AllPlatforms/Builds/",
    "AllPlatforms/Languages/",
    "AllPlatforms/Platforms/"
}
set.gameDataArchives =
{
    _currentDirectory .. "%(arch)s"
}
RegisterSetDescription(set)
''' % dict(set=SET, desc=DESC, arch=ARCH)


def compile_lua(luac, src, release):
    text = open(src, 'rb').read()
    if release:
        text = text.replace(b'TWD43_MARKER = " [43]"', b'TWD43_MARKER = nil')
    with tempfile.TemporaryDirectory() as d:
        name = os.path.basename(src)
        open(os.path.join(d, name), 'wb').write(text)
        subprocess.run([luac, '-o', 'out.luac', name], cwd=d, check=True)
        bc = open(os.path.join(d, 'out.luac'), 'rb').read()
    assert bc.startswith(HEADER), 'luac output is not the game\'s Lua 5.2 bytecode format'
    return bc


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    release = '--release' in sys.argv
    out = args[0] if args else os.path.join(REPO, 'out', 'tooltipmod')
    luac = os.environ.get('TWD_LUAC') or sys.exit('set TWD_LUAC to the luac built by tools/build_luac52.sh')
    stock_arch = os.path.join(REPO, 'original', 'archives', 'WDC_pc_ProjectSeason1_data.ttarch2')
    _, s1 = ttarch2.read_archive(stock_arch)
    stock = [f['data'] for f in s1 if f['name'] == 'Tooltip.lua']
    assert len(stock) == 1 and stock[0][:4] == b'\x1bLEn'
    bc = compile_lua(luac, os.path.join(REPO, 'mod', 'ProjectSeason1', 'Tooltip.lua'), release)
    files = [('Tooltip.lua', ttarch2.encrypt_lua(bc, b'\x1bLEn')), ('TWD43_Tooltip_stock.lua', stock[0])]
    os.makedirs(out, exist_ok=True)
    ttarch2.write_archive(os.path.join(out, ARCH), files)
    open(os.path.join(out, DESC), 'wb').write(ttarch2.encrypt_lua(DESCRIPTOR.encode(), b'\x1bLEo'))
    _, back = ttarch2.read_archive(os.path.join(out, ARCH))
    got = {f['name']: f['data'] for f in back}
    assert ttarch2.decrypt_lua(got['Tooltip.lua']) == bc and got['TWD43_Tooltip_stock.lua'] == stock[0]
    assert ttarch2.decrypt_lua(open(os.path.join(out, DESC), 'rb').read()) == DESCRIPTOR.encode()
    for n in (DESC, ARCH):
        p = os.path.join(out, n)
        print(hashlib.sha256(open(p, 'rb').read()).hexdigest(), n, os.path.getsize(p))


if __name__ == '__main__':
    main()
