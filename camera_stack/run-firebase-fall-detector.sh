#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command="cd '$project_dir' && LD_LIBRARY_PATH='$project_dir/local/lib' '$project_dir/local/bin/libcamerify' '$project_dir/.venv-yolo/bin/python' '$project_dir/firebase_detector_runner.py' $*"
if id -nG | tr ' ' '\n' | grep -qx video; then bash -c "$command"; else sg video -c "$command"; fi
