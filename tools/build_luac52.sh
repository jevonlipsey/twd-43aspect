#!/usr/bin/env bash
# Build a luac that writes the game's Lua bytecode: Lua 5.2.4, 4-byte float lua_Number, 4-byte size_t.
#   tools/build_luac52.sh <workdir>   -> <workdir>/lua-5.2.4/src/luac
# Verified: it re-dumps the game's own Tooltip.lua bytecode byte for byte.
set -eu
W="${1:?workdir}"; mkdir -p "$W"; cd "$W"
[ -f lua-5.2.4.tar.gz ] || curl -sSLO https://www.lua.org/ftp/lua-5.2.4.tar.gz
echo "b9e2e4aad6789b3b63a056d442f7b39f0ecfca3ae0f1fc0ae4e9614401b69f4b  lua-5.2.4.tar.gz" | shasum -a 256 -c -
rm -rf lua-5.2.4 && tar xzf lua-5.2.4.tar.gz && cd lua-5.2.4/src
sed -i '' 's/^#define LUA_NUMBER_DOUBLE/\/* LUA_NUMBER_DOUBLE off: float *\//; s/^#define LUA_NUMBER	double/#define LUA_NUMBER	float/; s/"%lf"/"%f"/; s/"%.14g"/"%.7g"/' luaconf.h
python3 -I - <<'PY'
s=open('ldump.c').read()
s=s.replace("  size_t size=0;\n  DumpVar(size,D);","  unsigned int size=0;\n  DumpVar(size,D);")
s=s.replace("  size_t size=s->tsv.len+1;","  unsigned int size=(unsigned int)(s->tsv.len+1);")
open('ldump.c','w').write(s)
s=open('lundump.c').read()
s=s.replace(" size_t size;\n LoadVar(S,size);"," unsigned int size;\n LoadVar(S,size);")
s=s.replace("*h++=cast_byte(sizeof(size_t));","*h++=cast_byte(4);")
open('lundump.c','w').write(s)
PY
make -s macosx >/dev/null 2>&1
ls -l luac
