# The Walking Dead: The Telltale Definitive Series, 4:3

A 4:3 mod for The Walking Dead: The Telltale Definitive Series (Steam 1449690), made for 1280x960 handhelds such as the Retroid Pocket Nova.

## Install

**Web patcher** (any browser, including your phone): <https://jevonlipsey.github.io/twd-43aspect/>. It runs locally and nothing is uploaded.

1. Choose two files from your own Steam copy of the game: `WDC.exe` from the game folder, and `Archives/WDC_pc_ProjectSeason1_data.ttarch2`. The archive is only read: the Season One fix needs the game's own `Tooltip.lua`, which this repo doesn't ship.
2. Download `TWD-4x3-patch.zip`. It is laid out like the game folder: the patched `WDC.exe`, plus ten new files in `Archives/` (two per game: Season One, Season Two, A New Frontier, The Final Season, Michonne). The page also offers the files one by one.
3. Close the game. Rename your original `WDC.exe` to `WDC.exe.bak`, then unzip into the game folder. Nothing else is replaced.
   - DroidDeck: the game folder is `/mnt/droiddeck-sd/steamapps/common/The Walking Dead The Telltale Definitive Series/` (internal storage: `/root/.local/share/Steam/steamapps/common/The Walking Dead The Telltale Definitive Series/`). Downloads are in `/root/Storage/Download`.
4. Launch through Steam as usual, because the patched exe still needs Steam. Play fullscreen at 1280x960. On DroidDeck, set Resolution to Match screen (1280x960) and 16:9 game fit to Stretch (or off).
5. A game update or Steam's "Verify integrity of game files" restores the original `WDC.exe`. Patch again afterwards.

**Roll back:** delete the new `WDC.exe` and rename `WDC.exe.bak` back. Then delete every `_resdesc_50_PC_P43_*.lua` and `WDC_pc_PC_P43_*.ttarch2` file from `Archives/`.

**Updating from the first patcher (v1):** restore `WDC.exe.bak` first (the patcher only accepts the original exe), then patch and unzip again. The two old `P43_S1` files can stay.

The patcher accepts only the current Steam build (`WDC.exe` sha256 `5f44e53f…`). Its output is byte-identical to the command-line build (`tools/patch43.py --level p10` + `tools/build_fix43.py <season> --release`):

| file | sha256 |
|---|---|
| `WDC.exe` | `85fb1aa64867d41aa17203ed5a853b16bc817376e707a0c2cbaf543d6471824a` |
| `Archives/_resdesc_50_PC_P43_S1X_01.lua` | `14a716282b52545236d7d8243ae15cf6036d93a76eb79deea4d161b70df141eb` |
| `Archives/WDC_pc_PC_P43_S1X_data.ttarch2` | `f68a1c47e8464d64c94639511f9b9e5c624cae514d2bd70877a55334ca596837` |
| `Archives/_resdesc_50_PC_P43_S2_01.lua` | `bb9bfd9cbfda21328a42aaf22a4566a266da93c50917991bcbe2dfb0f1404694` |
| `Archives/WDC_pc_PC_P43_S2_data.ttarch2` | `222ac89c69f2348fcef310e077d530ea461ee243402fa8d99505f5fee3eff3c3` |
| `Archives/_resdesc_50_PC_P43_S3_01.lua` | `4e6e9e565537d33aa1c0d99269a7dadd0c557ee28e74320b221550433761e336` |
| `Archives/WDC_pc_PC_P43_S3_data.ttarch2` | `54debb80021deab4778d3515c3a39aff63019954662fedfdda5ecd68f071b93c` |
| `Archives/_resdesc_50_PC_P43_S4_01.lua` | `6c5a732b0457b31459af8e762f39c8e52f2c14dfc9b7c68dc596c8579bd4afc5` |
| `Archives/WDC_pc_PC_P43_S4_data.ttarch2` | `8e286fdc654a12228f4a5d04aaf07f6b22e4afaf61dbb666c25b52a7c8e85bb1` |
| `Archives/_resdesc_50_PC_P43_SM_01.lua` | `61c717d433343f1276affa98adfc3df2215fe465e644ed10b78ffd59825fea71` |
| `Archives/WDC_pc_PC_P43_SM_data.ttarch2` | `edf2eeca5ac0a335060253329936a4dbc7ab1cdc0bd1c5b684f99abb8d0ffabd` |

## What it changes
- **Camera (`WDC.exe`):** `tools/patch43.py --level p10` removes the forced 16:9 letterbox. Cameras keep the 16:9 horizontal view and gain extra view above and below (vert+), including dialogue close-ups during gameplay.
- **UI (Lua, no exe change, one small resource set per game):** edge elements that were authored for 16:9 are moved inward to the real 4:3 edges at their normal size: the interaction label, "will remember this" notifications, help text, peek arrows, back buttons, end-of-episode stats. Long dialogue choices wrap instead of clipping, and the controller choice prompts sit beside their icons in all five games.
- **Reticle:** it can reach the whole 4:3 picture. Before, it stopped at the middle 75% of the width and inside the old 16:9 height, so things near the edges could not be selected.
- Each set is two new files in `Archives/` (`_resdesc_50_PC_P43_<game>_01.lua` + `WDC_pc_PC_P43_<game>_data.ttarch2`), priority 700/710, in the same style as the official patches. No game file is overwritten, and nothing changes on a 16:9 screen.
- **Optional: hold RB / R1 to skip a cutscene** (`tools/build_skip43.py`, one more small set per game; the web patcher has a tick box for it, off by default). Hold RB for one second during a cutscene to jump to its end; Q on a keyboard also works. Choices, quick-time events and action scenes are never skipped. Adapted from [TWDG-Skip](https://www.nexusmods.com/thewalkingdeadthetelltaledefinitiveseries/mods/333), with credit to its author.
- Checked on a device: Season One, Season Two and A New Frontier. The choice prompts in The Final Season and Michonne, and Michonne's hover label, use the same fix but have only been checked against the game's layout data, not seen in play yet. In The Final Season the label text of an interaction icon near the screen edge may sit further out than its icon.

## Build
```
tools/build_luac52.sh /tmp/luac52     # luac for the game's bytecode: Lua 5.2.4, float numbers, 4-byte size_t
TWD_LUAC=/tmp/luac52/lua-5.2.4/src/luac python3 tools/build_fix43.py S1 out/fix43_S1 --release   # also S2, S3, S4 --noglue, M --noglue
```
The builder reads `Tooltip.lua` from your own `Archives/WDC_pc_ProjectSeason1_data.ttarch2`, which you copy to `original/archives/`. Game data is never shipped in this repo.

The game only runs scripts that are compiled to its own Lua 5.2 bytecode and encrypted (`\x1bLEn`). Lua source packed into an archive is silently ignored.

## Web patcher (development)
`web/app/` is plain JavaScript, with no WebAssembly. `patcher-runtime.js` does the same work as the CLI tools: it unstubs SteamStub 3.1 (AES through WebCrypto), applies the `patch43.py` p10 edits, and writes the five ttarch2 archives (Telltale Blowfish, raw deflate through pako). `web/app/twd43-data.js` is generated from the CLI sources and committed. It holds no game code. An optional tick box ("Also add hold RB to skip cutscenes", off by default) adds the ten skip files (`PC_P43_SKIP_*`, from `build_skip43.py`) to the zip; the S1 one needs the stock `module_dialog_manager.lua`, which the page reads from the same archive and hash-checks.
```
TWD_LUAC=/tmp/luac52/lua-5.2.4/src/luac python3 tools/gen_web_data.py   # regenerate twd43-data.js
tools/build_web.sh                                                       # web/dist (what Pages serves)
TWD_LUAC=... PYTHON=<python with pycryptodome> node web/test/parity.mjs  # browser == CLI == verified hashes
node web/test/e2e.mjs [--one-by-one] [--skip]                                   # drives web/dist in headless Chrome
```
Open `web/app/index.html?mock` to see every state without game files (`?mock=ok|incomplete|already_patched|not_twd|verify_failed|error|loadfail`).

## Manual install (CLI build)
- Install a set: copy its two output files into `<game>/Archives/`.
- Roll it back: delete the two files.
