# The Walking Dead: The Telltale Definitive Series, 4:3

A 4:3 mod for The Walking Dead: The Telltale Definitive Series (Steam 1449690), made for 1280x960 handhelds such as the Retroid Pocket Nova.

## Install

**Web patcher** (any browser, including your phone): <https://jevonlipsey.github.io/twd-43aspect/>. It runs locally and nothing is uploaded.

1. Choose two files from your own Steam copy of the game: `WDC.exe` from the game folder, and `Archives/WDC_pc_ProjectSeason1_data.ttarch2`. The archive is only read: the label fix needs the game's own `Tooltip.lua`, which this repo doesn't ship.
2. Download `TWD-4x3-patch.zip`. It is laid out like the game folder: the patched `WDC.exe`, plus two new files in `Archives/`. The page also offers the three files one by one.
3. Close the game. Rename your original `WDC.exe` to `WDC.exe.bak`, then unzip into the game folder. Nothing else is replaced.
   - DroidDeck: the game folder is `/mnt/droiddeck-sd/steamapps/common/The Walking Dead The Telltale Definitive Series/` (internal storage: `/root/.local/share/Steam/steamapps/common/The Walking Dead The Telltale Definitive Series/`). Downloads are in `/root/Storage/Download`.
4. Launch through Steam as usual, because the patched exe still needs Steam. Play fullscreen at 1280x960. On DroidDeck, set Resolution to Match screen (1280x960) and 16:9 game fit to Stretch (or off).
5. A game update or Steam's "Verify integrity of game files" restores the original `WDC.exe`. Patch again afterwards.

**Roll back:** delete the new `WDC.exe` and rename `WDC.exe.bak` back. Then delete `_resdesc_50_PC_P43_S1_01.lua` and `WDC_pc_PC_P43_S1_data.ttarch2` from `Archives/`.

The patcher accepts only the current Steam build (`WDC.exe` sha256 `5f44e53f…`). Its output is byte-identical to the build verified on a Retroid Pocket Nova:

| file | sha256 |
|---|---|
| `WDC.exe` | `0884f3fed72b76e70b73540357a9b7643b00853f907bfffc6377f2e984ad683b` |
| `Archives/_resdesc_50_PC_P43_S1_01.lua` | `c45f2a17f721b056bb21b49f1fcbeea5c9685b9d480e3dc150fdf66a8a84ee53` |
| `Archives/WDC_pc_PC_P43_S1_data.ttarch2` | `89415229e30900f85fff8f1f633afd15dcd8a3d61522240dbc2a4e350d51d5fb` |

## What it changes
- **Camera (`WDC.exe`):** `tools/patch43.py --level p6` (with `TWD_ALLOW=any TWD_FOVMIN=15`) removes the forced 16:9 letterbox. Gameplay cameras keep the 16:9 horizontal view and gain extra vertical view (Hor+).
- **Interaction label (Lua, no exe change):** the "Examine / ATM" style label is authored 1.95 units inside the left edge of a 16:9 frame, which puts it past the left edge of a 4:3 frame. Only "ne" was visible. The mod moves both text lines inward by `halfHeight * (16/9 - aspect)`, so they keep the authored margin from the real 4:3 edge at their normal size. Nothing changes on a 16:9 screen.
  - It is a resource-set patch on `<ProjectSeason1>`, priority 700, in the same style as the official patches.
  - It is two new files in `Archives/`, and no game file is overwritten:
    - `_resdesc_50_PC_P43_S1_01.lua`, the set descriptor.
    - `WDC_pc_PC_P43_S1_data.ttarch2`, which holds `Tooltip.lua` and the game's own `Tooltip.lua` renamed `TWD43_Tooltip_stock.lua`. The new `Tooltip.lua` (`mod/ProjectSeason1/Tooltip.lua`) runs the stock one first, then applies the move.

## Build
```
tools/build_luac52.sh /tmp/luac52     # luac for the game's bytecode: Lua 5.2.4, float numbers, 4-byte size_t
TWD_LUAC=/tmp/luac52/lua-5.2.4/src/luac python3 tools/build_tooltipmod.py out/tooltip --release
```
The builder reads `Tooltip.lua` from your own `Archives/WDC_pc_ProjectSeason1_data.ttarch2`, which you copy to `original/archives/`. Game data is never shipped in this repo.

The game only runs scripts that are compiled to its own Lua 5.2 bytecode and encrypted (`\x1bLEn`). Lua source packed into an archive is silently ignored.

## Web patcher (development)
`web/app/` is plain JavaScript, with no WebAssembly. `patcher-runtime.js` does the same work as the CLI tools: it unstubs SteamStub 3.1 (AES through WebCrypto), applies the `patch43.py` p6 edits, and writes the ttarch2 archive (Telltale Blowfish, raw deflate through pako). `web/app/twd43-data.js` is generated from the CLI sources and committed. It holds no game code.
```
TWD_LUAC=/tmp/luac52/lua-5.2.4/src/luac python3 tools/gen_web_data.py   # regenerate twd43-data.js
tools/build_web.sh                                                       # web/dist (what Pages serves)
TWD_LUAC=... PYTHON=<python with pycryptodome> node web/test/parity.mjs  # browser == CLI == verified hashes
node web/test/e2e.mjs [--one-by-one]                                     # drives web/dist in headless Chrome
```
Open `web/app/index.html?mock` to see every state without game files (`?mock=ok|incomplete|already_patched|not_twd|verify_failed|error|loadfail`).

## Manual install (CLI build)
- Install the label mod: copy the two output files into `<game>/Archives/`.
- Roll it back: delete the two files.
