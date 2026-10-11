#!/bin/bash
# net_test.sh OUT [host args...]: a class game on this computer over ENet:
# a host and two players (robots play each), each saving screenshots, all on
# the hidden display (see tools/shot.sh). Prints what each one logged.
OUT=$1; shift
DPY=${SHOT_DISPLAY:-:99}
mkdir -p "$OUT"/host "$OUT"/p1 "$OUT"/p2
cd "$(dirname "$0")/.."
run() {
  env -u WAYLAND_DISPLAY DISPLAY=$DPY LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe __GLX_VENDOR_LIBRARY_NAME=mesa \
    godot --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy --path . -- "$@"
}
run --shot="$OUT/host" --at=${HOST_AT:-300,900} --test-host=${PLAYERS:-2} "$@" > "$OUT/host/log.txt" 2>&1 &
H=$!
sleep 4
run --shot="$OUT/p1" --at=${P_AT:-300,800} --test-join --autoplay > "$OUT/p1/log.txt" 2>&1 &
run --shot="$OUT/p2" --at=${P_AT:-300,800} ${P2:---test-join} --autoplay > "$OUT/p2/log.txt" 2>&1 &
wait $H
sleep 2
pkill -f "test-joi[n]" 2>/dev/null
for w in host p1 p2; do echo "== $w"; grep -E "SCRIPT ERROR|ERROR:" -A2 "$OUT/$w/log.txt" | grep -v "resources still in use" | sort -u | head -8; done
