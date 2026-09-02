#!/usr/bin/env bash
set -Eeuo pipefail

readonly robot_ws="/home/carelink/robot_ws"
readonly maps_dir="$robot_ws/src/articubot_one/maps"
readonly active_map_file="/home/carelink/.config/carelink/active-map"
readonly autonomy_service="carelink-autonomy.service"

robot_pid=""
lidar_pid=""
slam_pid=""
service_was_active=0
stack_stopped=0
map_saved=0
active_tmp=""

usage() {
  cat <<'EOF'
Usage: ./start-carelink-mapping.sh MAP_NAME [--no-start]

Creates MAP_NAME.pgm and MAP_NAME.yaml with keyboard teleoperation. Pressing
Ctrl-C stops teleoperation and opens a save/resume/discard prompt. A successful
save selects the new map and starts CareLink autonomy unless --no-start is used.

MAP_NAME may contain ASCII letters, numbers, underscores, and hyphens only.
Existing map files are never overwritten.
EOF
}

stop_child() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return
  kill -0 "$pid" 2>/dev/null || return

  kill -INT "$pid" 2>/dev/null || true
  for _attempt in $(seq 1 30); do
    kill -0 "$pid" 2>/dev/null || return
    sleep 0.1
  done

  echo "[carelink-map] Process $pid did not stop after SIGINT; terminating it" >&2
  kill -TERM "$pid" 2>/dev/null || true
  for _attempt in $(seq 1 20); do
    kill -0 "$pid" 2>/dev/null || return
    sleep 0.1
  done

  echo "[carelink-map] Process $pid did not terminate; killing it" >&2
  kill -KILL "$pid" 2>/dev/null || true
}

stop_mapping_stack() {
  if (( stack_stopped )); then
    return
  fi
  stack_stopped=1

  stop_child "$slam_pid"
  [[ -z "$slam_pid" ]] || wait "$slam_pid" 2>/dev/null || true

  stop_child "$lidar_pid"
  [[ -z "$lidar_pid" ]] || wait "$lidar_pid" 2>/dev/null || true

  stop_child "$robot_pid"
  [[ -z "$robot_pid" ]] || wait "$robot_pid" 2>/dev/null || true
}

on_exit() {
  local exit_code=$?
  trap - INT TERM EXIT
  stop_mapping_stack

  if [[ -n "$active_tmp" && -e "$active_tmp" ]]; then
    rm -f -- "$active_tmp"
  fi

  if (( exit_code != 0 && service_was_active && ! map_saved )); then
    echo "[carelink-map] Mapping did not complete; restoring autonomy service" >&2
    systemctl --user start "$autonomy_service" || true
  fi
  exit "$exit_code"
}

trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if (( $# == 0 )) || [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if (( $# > 2 )); then
  usage >&2
  exit 2
fi

map_name="$1"
start_after_save=1
if (( $# == 2 )); then
  if [[ "$2" != "--no-start" ]]; then
    usage >&2
    exit 2
  fi
  start_after_save=0
fi

if [[ ! "$map_name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  echo "[carelink-map] Invalid map name: $map_name" >&2
  usage >&2
  exit 2
fi
if [[ ! -t 0 || ! -t 1 ]]; then
  echo "[carelink-map] Run this command from an interactive terminal" >&2
  exit 2
fi

map_prefix="$maps_dir/$map_name"
map_yaml="$map_prefix.yaml"
map_image="$map_prefix.pgm"
if [[ -e "$map_yaml" || -e "$map_image" ]]; then
  echo "[carelink-map] Refusing to overwrite existing map: $map_name" >&2
  exit 2
fi

mkdir -p "$maps_dir"

if systemctl --user is-active --quiet "$autonomy_service"; then
  service_was_active=1
  echo "[carelink-map] Stopping autonomy and person-following service"
  systemctl --user stop "$autonomy_service"
fi

# ROS setup scripts legitimately inspect variables that may be unset.
set +u
source /opt/ros/jazzy/setup.bash
source "$robot_ws/install/setup.bash"
set -u

echo "[carelink-map] Starting ROS 2 motor stack"
ros2 launch articubot_one launch_robot.launch.py &
robot_pid=$!

echo "[carelink-map] Waiting for diff_cont controller"
controller_ready=0
for _attempt in $(seq 1 60); do
  if ! kill -0 "$robot_pid" 2>/dev/null; then
    echo "[carelink-map] Motor stack exited during startup" >&2
    exit 1
  fi
  controllers="$(timeout 2 ros2 control list_controllers \
    --controller-manager /controller_manager 2>/dev/null || true)"
  if awk '$1 == "diff_cont" && $NF == "active" { found=1 } END { exit !found }' \
      <<<"$controllers"; then
    controller_ready=1
    break
  fi
  sleep 1
done
if (( ! controller_ready )); then
  echo "[carelink-map] Timed out waiting for diff_cont" >&2
  exit 1
fi

echo "[carelink-map] Starting RPLIDAR A1"
ros2 launch sllidar_ros2 sllidar_a1_launch.py \
  serial_port:=/dev/serial/by-id/usb-Silicon_Labs_CP2102_USB_to_UART_Bridge_Controller_0001-if00-port0 \
  frame_id:=laser &
lidar_pid=$!

echo "[carelink-map] Waiting for lidar scans"
scan_ready=0
for _attempt in $(seq 1 30); do
  if ! kill -0 "$lidar_pid" 2>/dev/null; then
    echo "[carelink-map] Lidar exited during startup" >&2
    exit 1
  fi
  if timeout 2 ros2 topic echo /scan --once >/dev/null 2>&1; then
    scan_ready=1
    break
  fi
  sleep 1
done
if (( ! scan_ready )); then
  echo "[carelink-map] Timed out waiting for /scan" >&2
  exit 1
fi

echo "[carelink-map] Starting slam_toolbox"
ros2 launch carelink_patrol mapping.launch.py &
slam_pid=$!

echo "[carelink-map] Waiting for the first map"
slam_ready=0
for _attempt in $(seq 1 60); do
  if ! kill -0 "$slam_pid" 2>/dev/null; then
    echo "[carelink-map] slam_toolbox exited during startup" >&2
    exit 1
  fi
  if timeout 2 ros2 topic echo /map --once >/dev/null 2>&1; then
    slam_ready=1
    break
  fi
  sleep 1
done
if (( ! slam_ready )); then
  echo "[carelink-map] Timed out waiting for /map" >&2
  exit 1
fi

cat <<EOF

[carelink-map] Mapping is ready: $map_name
  Drive slowly with the keyboard and return near the starting area.
  i/k/, : forward/stop/backward
  j/l   : rotate left/right
  Ctrl-C: stop driving and choose save, resume, or discard

  Teleop speed is limited to 0.15 m/s and 0.50 rad/s.
  Mapping mode does not provide Nav2 obstacle avoidance.
EOF

while true; do
  ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args \
    -p stamped:=true -p speed:=0.15 -p turn:=0.50 \
    -r cmd_vel:=/diff_cont/cmd_vel

  while true; do
    printf '\n[carelink-map] [s]ave, [r]esume mapping, or [d]iscard? [d] '
    IFS= read -r decision
    case "${decision,,}" in
      s|save)
        save_requested=1
        break
        ;;
      r|resume)
        save_requested=0
        echo "[carelink-map] Resuming keyboard teleoperation"
        break
        ;;
      ''|d|discard)
        echo "[carelink-map] Discarding this map without saving"
        exit 3
        ;;
      *)
        echo "[carelink-map] Enter s, r, or d"
        ;;
    esac
  done

  if (( save_requested )); then
    break
  fi
done

echo "[carelink-map] Saving map to $map_yaml"
timeout 30 ros2 run nav2_map_server map_saver_cli \
  -t map -f "$map_prefix" --fmt pgm --mode trinary \
  --ros-args -p save_map_timeout:=15.0

if [[ ! -s "$map_yaml" || ! -s "$map_image" ]]; then
  echo "[carelink-map] Map saver did not create both YAML and PGM files" >&2
  exit 1
fi

mkdir -p "$(dirname "$active_map_file")"
active_tmp="$(mktemp "$(dirname "$active_map_file")/.active-map.XXXXXX")"
printf '%s\n' "$map_yaml" >"$active_tmp"
mv -f -- "$active_tmp" "$active_map_file"
active_tmp=""
map_saved=1

stop_mapping_stack
trap - INT TERM EXIT

echo "[carelink-map] Saved and selected map: $map_yaml"
if (( start_after_save )); then
  echo "[carelink-map] Starting autonomy with the new map"
  systemctl --user start "$autonomy_service"
  echo "[carelink-map] The Firebase map will update when Nav2 finishes starting"
else
  echo "[carelink-map] Autonomy was not started (--no-start)"
fi
