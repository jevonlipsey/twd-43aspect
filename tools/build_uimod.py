#!/usr/bin/env python3
"""Build the 4:3 UI mod: a resource-set patch that overrides Lua files, no exe change.

  python3 tools/build_uimod.py [outdir] [WDC_pc_Project_data.ttarch2]
      (defaults out/uimod and original/archives/WDC_pc_Project_data.ttarch2, the user's own copy)

Output (copy both into the game's Archives/ folder):
  _resdesc_50_PC_P43_Proj_01.lua            descriptor, LEo-encrypted source like the game's own
  WDC_pc_PC_p43_proj_compressed.ttarch2     ECTT archive: the files under mod/Project/, plus the game's
                                            original ProjectSettingsShared.lua copied byte for byte as
                                            ProjectSettingsShared_stock.lua (the mod runs it after its hook)

The descriptor mirrors the official patch _resdesc_50_PC_P02_Proj_01.lua (a set mapped onto
<Project> at a higher priority), so mod/Project/<name> replaces <name> from WDC_pc_Project_data.
`--repack [Project_data.ttarch2]` instead writes out/uimod-repack/WDC_pc_Project_data.ttarch2 (plan B).
Lua is shipped as LEo-encrypted source (the engine reads source; descriptors are the same).
"""
import hashlib, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ttarch2  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SET = 'PC_P43_Proj'
DESC = '_resdesc_50_%s_01.lua' % SET
ARCH = 'WDC_pc_PC_p43_proj_compressed.ttarch2'

DESCRIPTOR = '''local set = {}
set.name = "%(set)s"
set.setName = "%(set)s"
set.descriptionFilenameOverride = "%(desc)s"
set.logicalName = "<%(set)s>"
set.logicalDestination = "<Project>"
set.priority = 443
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


def repack(stock_arch, out):
    """Plan B: the same two files written into a copy of WDC_pc_Project_data.ttarch2 itself."""
    os.makedirs(out, exist_ok=True)
    _, proj = ttarch2.read_archive(stock_arch)
    files = [(f['name'], f['data']) for f in proj]
    stock = [d for n, d in files if n == 'ProjectSettingsShared.lua'][0]
    mine = open(os.path.join(REPO, 'mod', 'Project', 'ProjectSettingsShared.lua'), 'rb').read()
    files = [(n, d) for n, d in files if n != 'ProjectSettingsShared.lua']
    files += [('ProjectSettingsShared.lua', ttarch2.encrypt_lua(mine, b'\x1bLEo')), ('ProjectSettingsShared_stock.lua', stock)]
    p = os.path.join(out, os.path.basename(stock_arch))
    ttarch2.write_archive(p, files)
    _, back = ttarch2.read_archive(p)
    assert len(back) == len(proj) + 1
    print(hashlib.sha256(open(p, 'rb').read()).hexdigest(), p)


def main():
    if '--repack' in sys.argv:
        a = [x for x in sys.argv[1:] if x != '--repack']
        repack(a[0] if a else os.path.join(REPO, 'original', 'archives', 'WDC_pc_Project_data.ttarch2'),
               os.path.join(REPO, 'out', 'uimod-repack'))
        return
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, 'out', 'uimod')
    os.makedirs(out, exist_ok=True)
    src = os.path.join(REPO, 'mod', 'Project')
    files = []
    for n in sorted(os.listdir(src)):
        d = open(os.path.join(src, n), 'rb').read()
        if n.endswith('.lua'):
            d = ttarch2.encrypt_lua(d, b'\x1bLEo')
        files.append((n, d))
    stock_arch = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, 'original', 'archives', 'WDC_pc_Project_data.ttarch2')
    _, proj = ttarch2.read_archive(stock_arch)
    stock = [f['data'] for f in proj if f['name'] == 'ProjectSettingsShared.lua']
    assert len(stock) == 1 and stock[0][:4] == b'\x1bLEn', 'ProjectSettingsShared.lua not found in ' + stock_arch
    files.append(('ProjectSettingsShared_stock.lua', stock[0]))
    ttarch2.write_archive(os.path.join(out, ARCH), files)
    open(os.path.join(out, DESC), 'wb').write(ttarch2.encrypt_lua(DESCRIPTOR.encode(), b'\x1bLEo'))
    # round-trip check: the archive and descriptor decode back to the sources
    _, back = ttarch2.read_archive(os.path.join(out, ARCH))
    for f in back:
        if f['name'] == 'ProjectSettingsShared_stock.lua':
            assert f['data'] == stock[0]
            continue
        want = open(os.path.join(src, f['name']), 'rb').read()
        got = ttarch2.decrypt_lua(f['data'])
        assert got[:len(want)] == want and not got[len(want):].strip(b'\0'), f['name']
    assert ttarch2.decrypt_lua(open(os.path.join(out, DESC), 'rb').read()).startswith(DESCRIPTOR.encode()[:-8])
    for n in (DESC, ARCH):
        p = os.path.join(out, n)
        print(hashlib.sha256(open(p, 'rb').read()).hexdigest(), n, os.path.getsize(p))


if __name__ == '__main__':
    main()
