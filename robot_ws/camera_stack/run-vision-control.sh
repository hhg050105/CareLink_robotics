#!/usr/bin/env bash
set -eo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source /opt/ros/jazzy/setup.bash
source /home/carelink/robot_ws/install/setup.bash
cd /home/carelink/camera_stack
exec env "LD_LIBRARY_PATH=$project_dir/local/lib:${LD_LIBRARY_PATH:-}" \
  "$project_dir/local/bin/libcamerify" "$project_dir/.venv-yolo/bin/python" \
  "$project_dir/vision_control.py" "$@"
