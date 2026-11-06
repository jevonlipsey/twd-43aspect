# The Walking Dead: The Telltale Definitive Series, 4:3

A 4:3 mod for The Walking Dead: The Telltale Definitive Series (Steam 1449690), made for 1280x960 handhelds such as the Retroid Pocket Nova.

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

## Install / roll back
- **Install:** copy the two output files into `<game>/Archives/`.
- **Roll back:** delete the two files.
