#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command="LD_LIBRARY_PATH='$project_dir/local/lib' '$project_dir/local/bin/libcamerify' python3 '$project_dir/fall_detector.py' $*"

if id -nG | tr ' ' '\n' | grep -qx video; then
    bash -c "$command"
else
    sg video -c "$command"
fi
