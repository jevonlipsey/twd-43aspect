# The Walking Dead: The Telltale Definitive Series 4:3 (Steam 1449690)

Native byte patch of `WDC.exe` (Telltale Tool engine, x64, SteamStub 3.1). Device procedure: `~/.claude/skills/nova-43aspect/SKILL.md`.

## Engine facts
- `.text` is AES-encrypted by SteamStub 3.1 (`.bind` section). The patcher unstubs first (`tools/unstub.py`, copied from sor4-43aspect, needs pycryptodome); a patched stubbed exe would fail the stub's module check. Runs in Steam mode only (no `DROIDDECK_NO_STEAM`).
- Lua `RenderForce_16_by_9_AspectRatio` (VA 0x1406794d0) calls SetForceAspect(1) (0x14053e0b0) and sets the forced ratio 16/9 (0x14053e0d0). The viewport sizer (0x14053e120) shrinks the window to the forced ratio when that flag is set: that is the black bars. p1 flips the `mov cl,1` at 0x1406794f5 to 0.
- Camera FOV is vertical (perspective builder 0x140039260: m5 = 1/tan(fov/2), m0 = m5/aspect). Camera aspect falls back to window w/h (getter 0x14053e0f0) when the camera's aspect field (+0x1c4) is 0, so after p1 the 3D scene is undistorted but the sides are cropped.
- p2 keeps the 16:9 horizontal FOV: the `call tan` (0x140b28510) in the perspective builder (0x14003929f) and the frustum-corner builder (0x1404571eb) are redirected to a cave (`tan(x)*4/3`) placed in the dead `.bind` section at 0x14122e000. p2 therefore keeps `.bind` (unstub with keep_bind). The 4/3 factor is hardcoded for a 4:3 window.
- prefs.prop (binary Telltale stream) is not hand-editable; no prefs key was needed.

## Commands
- `~/Downloads/sor4-43aspect/.venv/bin/python -I tools/patch43.py --level p2 original/WDC.exe out/WDC.p2.exe` (levels p1, p2; refuses non-pristine input)
- `tools/deploy.sh <pristine|unstub|p1|p2> | --rollback | --status` (ADB_SERIAL=... for wireless). Takes the device lock, backs up prefs, keeps `WDC.exe.orig`.
- `tools/ripxref.py`, `tools/callers.py`, `tools/disasm.py`: capstone helpers for the unstubbed exe.
