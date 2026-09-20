#!/usr/bin/env bash
set -eo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
robot_ws="${CARELINK_ROBOT_WS:-/home/carelink/robot_ws}"

source /opt/ros/jazzy/setup.bash
if [[ -f "$robot_ws/install/setup.bash" ]]; then
  source "$robot_ws/install/setup.bash"
fi

runner=(
  env "LD_LIBRARY_PATH=$project_dir/local/lib:${LD_LIBRARY_PATH:-}"
  "$project_dir/local/bin/libcamerify"
  "$project_dir/.venv-yolo/bin/python"
  "$project_dir/person_follower.py"
  "$@"
)

if id -nG | tr ' ' '\n' | grep -qx video; then
  exec "${runner[@]}"
fi

printf -v quoted_command '%q ' "${runner[@]}"
exec sg video -c "$quoted_command"
