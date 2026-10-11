#!/bin/bash
# shot.sh OUT_DIR FRAMES [PRESSES] [game args, e.g. --autotest --track=6]
# Runs the game with software rendering (no graphics chip: this laptop has
# frozen running GPU-heavy apps) on a hidden X display, and saves shot_N.png
# at each frame in FRAMES (e.g. 30,90). PRESSES like 60:ui_down,70:ui_accept.
# SHOT_SCENE=res://scenes/race.tscn starts straight in that scene.
# Start the hidden display once (Hyprland):
#   hyprctl dispatch 'hl.dsp.exec_cmd("Xwayland :99 -geometry 1920x1080 -noreset", { workspace = "special:hkemu silent" })'
OUT=$1; FRAMES=$2; PRESSES=$3; shift 3
DPY=${SHOT_DISPLAY:-:99}
[ -S /tmp/.X11-unix/X${DPY#:} ] || { echo "no X display $DPY (see the header)"; exit 1; }
mkdir -p "$OUT"
cd "$(dirname "$0")/.."
sync
env -u WAYLAND_DISPLAY DISPLAY=$DPY LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe \
  __GLX_VENDOR_LIBRARY_NAME=mesa \
  godot --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy --path . $SHOT_SCENE \
  -- --shot="$OUT" --at="$FRAMES" ${PRESSES:+--press=$PRESSES} "$@" > "$OUT/godot.log" 2>&1 &
PID=$!
for i in $(seq 1 240); do
  kill -0 $PID 2>/dev/null || break
  if ls -l /proc/$PID/fd 2>/dev/null | grep -q /dev/dri; then
    echo "graphics chip opened: killing"; kill -9 $PID; exit 1
  fi
  sleep 0.5
done
kill -9 $PID 2>/dev/null
grep -iE "error|warning" "$OUT/godot.log" | head -20
ls "$OUT"/shot_*.png 2>/dev/null
