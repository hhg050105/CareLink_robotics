#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
camera_bin="$project_dir/local/bin/cam"

if [[ -z "${DISPLAY:-}" ]]; then
    echo "No X11 display is available." >&2
    echo "Reconnect from your computer with: ssh -Y carelink@192.168.0.73" >&2
    exit 1
fi

camera_command="LD_LIBRARY_PATH='$project_dir/local/lib' '$camera_bin' --camera 1 --capture --stream role=viewfinder,width=640,height=480,pixelformat=RGB888 --sdl"

if id -nG | tr ' ' '\n' | grep -qx video; then
    bash -c "$camera_command"
else
    sg video -c "$camera_command"
fi
