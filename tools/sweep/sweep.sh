#!/usr/bin/env bash
# Offline glslang sweep of every pack program in all three dimensions, plus the six voxy patch
# variants, with an Iris settings file applied. Needs glslangValidator (nix-shell -p glslang).
# Runs a matrix: LOD mode x Iris version for the pack programs, Iris version for the patches.
#
#   PACK_ROOT       shaders directory to sweep        (default: this repo's shaders/)
#   SWEEP_OPTS      Iris settings file, <pack>.zip.txt (default: none, pack defaults)
#   VOXY_JAR        voxy mod jar, for the patch variants (default: none, patches skipped)
#   SWEEP_OUT       output directory                  (default: $TMPDIR/rv-sweep)
#   SWEEP_TAG       name of this output set           (default: main)
#   SWEEP_LODS      pack-program LOD modes, any of voxy none dh   (default: all three)
#   SWEEP_IRIS      IRIS_VERSION values                           (default: "11104 11103")
#   SWEEP_ONLY      extended regex; only result names matching it run
#   SWEEP_BASELINE  directory of r_*.txt files from an earlier run; prints "NEW FAIL <config> <name>"
#                   for each program failing now that passed or was absent there, exits 1 if any
# Results: $SWEEP_OUT/r_<tag>_<config>.txt, logs under ap_<tag>_<config>/ and vt_<tag>_<iris>/.
# Configs are <lod>-<iris> (e.g. voxy-11104) for pack programs and patch-<iris> for the voxy patches.
set -u
H=$(cd "$(dirname "$0")" && pwd)
export PACK_ROOT=${PACK_ROOT:-$(cd "$H/../.." && pwd)/shaders}
OUT=${SWEEP_OUT:-${TMPDIR:-/tmp}/rv-sweep}
T=${SWEEP_TAG:-main}
OPTS=${SWEEP_OPTS:-}
LODS=${SWEEP_LODS:-voxy none dh}
IRISES=${SWEEP_IRIS:-11104 11103}
ONLY=${SWEEP_ONLY:-.}
BASE=${SWEEP_BASELINE:-}
mkdir -p "$OUT"
CONFIGS=()

apply() { # src -> opt, with the settings file when one is given
  if [ -n "$OPTS" ]; then python3 "$H/apply_opts.py" "$1" "$OPTS" "$2" >/dev/null; else cp "$1" "$2"; fi
}

for lod in $LODS; do for iris in $IRISES; do
  c=$lod-$iris; CONFIGS+=("$c")
  O=$OUT/ap_${T}_$c; mkdir -p "$O"; R=$OUT/r_${T}_$c.txt; : > "$R"
  for w in world0 world1 world-1; do
    wn=${w/-/m}
    for f in "$PACK_ROOT/$w"/*.fsh "$PACK_ROOT/$w"/*.vsh "$PACK_ROOT/$w"/*.csh; do
      [ -f "$f" ] || continue
      b=$(basename "$f"); ext=${b##*.}; n=${b%.*}
      case $ext in fsh) st=frag;; vsh) st=vert;; csh) st=comp;; esac
      name=${wn}_${n}_${ext}
      echo "$name" | grep -qE "$ONLY" || continue
      o=$O/$name
      python3 "$H/build_pack_prog.py" "$w/$b" "$o.src" "$lod" "$iris"
      apply "$o.src" "$o.opt"
      if glslangValidator -S $st "$o.opt" > "$o.log" 2>&1; then echo "PASS $name"; else echo "FAIL $name"; fi >> "$R"
    done
  done
done; done

if [ -n "${VOXY_JAR:-}" ]; then
  export VOXY_SHADERS=$OUT/vxsh
  [ -d "$VOXY_SHADERS/assets/voxy/shaders" ] || unzip -o -q "$VOXY_JAR" 'assets/voxy/shaders/*' -d "$VOXY_SHADERS"
  for iris in $IRISES; do
    c=patch-$iris; CONFIGS+=("$c")
    V=$OUT/vt_${T}_$iris; mkdir -p "$V"; R=$OUT/r_${T}_$c.txt; : > "$R"
    for w in world0 world1 world-1; do for m in opaque translucent; do
      wn=${w/-/m}; name=voxy_${wn}_$m; o=$V/${wn}_$m
      echo "$name" | grep -qE "$ONLY" || continue
      python3 "$H/build_voxy_patch.py" "$o.src" $w $m "$iris" >/dev/null
      apply "$o.src" "$o.opt"
      if glslangValidator -S frag "$o.opt" > "$o.log" 2>&1; then echo "PASS $name"; else echo "FAIL $name"; fi >> "$R"
    done; done
  done
else
  echo "VOXY_JAR unset: voxy patch variants skipped" >&2
fi

for c in "${CONFIGS[@]}"; do
  R=$OUT/r_${T}_$c.txt
  echo "$c: PASS $(grep -c '^PASS' "$R")  FAIL $(grep -c '^FAIL' "$R")  ($R)"
done

if [ -n "$BASE" ]; then
  new=0
  for c in "${CONFIGS[@]}"; do
    R=$OUT/r_${T}_$c.txt; B=$BASE/r_${T}_$c.txt
    while read -r st name; do
      [ "$st" = FAIL ] || continue
      if [ ! -f "$B" ] || ! grep -qx "FAIL $name" "$B"; then echo "NEW FAIL $c $name"; new=1; fi
    done < "$R"
  done
  [ $new = 0 ] || exit 1
fi
