#!/usr/bin/env bash
# Offline glslang sweep of every pack program in all three dimensions, plus the six voxy patch
# variants, with an Iris settings file applied. Needs glslangValidator (nix-shell -p glslang).
#
#   PACK_ROOT   shaders directory to sweep        (default: this repo's shaders/)
#   SWEEP_OPTS  Iris settings file, <pack>.zip.txt (default: none, pack defaults)
#   VOXY_JAR    voxy mod jar, for the patch variants (default: none, patches skipped)
#   SWEEP_OUT   output directory                  (default: $TMPDIR/rv-sweep)
#   SWEEP_TAG   name of this output set           (default: main)
set -u
H=$(cd "$(dirname "$0")" && pwd)
export PACK_ROOT=${PACK_ROOT:-$(cd "$H/../.." && pwd)/shaders}
OUT=${SWEEP_OUT:-${TMPDIR:-/tmp}/rv-sweep}
T=${SWEEP_TAG:-main}
OPTS=${SWEEP_OPTS:-}
O=$OUT/ap_$T; mkdir -p "$O"; R=$OUT/r_$T.txt; : > "$R"

apply() { # src -> opt, with the settings file when one is given
  if [ -n "$OPTS" ]; then python3 "$H/apply_opts.py" "$1" "$OPTS" "$2" >/dev/null; else cp "$1" "$2"; fi
}

for w in world0 world1 world-1; do
  wn=${w/-/m}
  for f in "$PACK_ROOT/$w"/*.fsh "$PACK_ROOT/$w"/*.vsh "$PACK_ROOT/$w"/*.csh; do
    [ -f "$f" ] || continue
    b=$(basename "$f"); ext=${b##*.}; n=${b%.*}
    case $ext in fsh) st=frag;; vsh) st=vert;; csh) st=comp;; esac
    o=$O/${wn}_${n}_${ext}
    python3 "$H/build_pack_prog.py" "$w/$b" "$o.src" voxy
    apply "$o.src" "$o.opt"
    if glslangValidator -S $st "$o.opt" > "$o.log" 2>&1; then echo "PASS ${wn}_${n}_${ext}"; else echo "FAIL ${wn}_${n}_${ext}"; fi >> "$R"
  done
done

if [ -n "${VOXY_JAR:-}" ]; then
  export VOXY_SHADERS=$OUT/vxsh
  [ -d "$VOXY_SHADERS/assets/voxy/shaders" ] || unzip -o -q "$VOXY_JAR" 'assets/voxy/shaders/*' -d "$VOXY_SHADERS"
  V=$OUT/vt_$T; mkdir -p "$V"
  for w in world0 world1 world-1; do for m in opaque translucent; do
    wn=${w/-/m}; o=$V/${wn}_$m
    python3 "$H/build_voxy_patch.py" "$o.src" $w $m >/dev/null
    apply "$o.src" "$o.opt"
    if glslangValidator -S frag "$o.opt" > "$o.log" 2>&1; then echo "PASS voxy_${wn}_$m"; else echo "FAIL voxy_${wn}_$m"; fi >> "$R"
  done; done
else
  echo "VOXY_JAR unset: voxy patch variants skipped" >&2
fi

echo "PASS $(grep -c PASS "$R")  FAIL $(grep -c FAIL "$R")  (details: $R, logs under $O and $OUT/vt_$T)"
grep FAIL "$R" | tr '\n' ' '; echo
