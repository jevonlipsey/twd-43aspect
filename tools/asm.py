#!/usr/bin/env python3
"""asm.py file.s : assemble x86-64 intel-syntax source with Apple clang (no external relocs allowed) -> hex bytes on stdout."""
import subprocess, sys, tempfile, os, re
src = open(sys.argv[1]).read()
with tempfile.TemporaryDirectory() as d:
    s = os.path.join(d, "a.s"); o = os.path.join(d, "a.o")
    open(s, "w").write(".intel_syntax noprefix\n.text\n" + src + "\n")
    subprocess.check_call(["clang", "-target", "x86_64-apple-macos", "-c", s, "-o", o])
    out = subprocess.check_output(["otool", "-t", "-X", o]).decode()
    h = "".join(re.sub(r"^[0-9a-f]{16}\s", "", l).replace(" ", "") for l in out.splitlines())
    print(h)
