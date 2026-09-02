#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
camera_bin="$project_dir/local/bin/cam"
output_dir="$project_dir/artifacts"

if [[ ! -x "$camera_bin" ]]; then
    echo "Local camera binary not found: $camera_bin" >&2
    exit 1
fi

mkdir -p "$output_dir"

camera_command="LD_LIBRARY_PATH='$project_dir/local/lib' '$camera_bin' --camera 1 --capture=5 --stream role=viewfinder,width=640,height=480,pixelformat=RGB888 --file='$output_dir/frame-#.ppm'"

if id -nG | tr ' ' '\n' | grep -qx video; then
    bash -c "$camera_command"
else
    sg video -c "$camera_command"
fi

echo "Captured frames:"
ls -lh "$output_dir"/frame-*.ppm
