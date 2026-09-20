#!/usr/bin/env bash
set -Eeuo pipefail

readonly robot_ws="/home/carelink/robot_ws"
readonly fall_detector_dir="/home/carelink/camera_stack"
readonly maps_dir="$robot_ws/src/articubot_one/maps"
readonly default_map="$maps_dir/new_map02.yaml"
readonly active_map_file="/home/carelink/.config/carelink/active-map"

navigation_map="$default_map"
robot_pid=""
fall_detector_pid=""
lidar_pid=""
navigation_pid=""
cleaning_up=0

stop_child() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return
  kill -0 "$pid" 2>/dev/null || return

  kill -INT "$pid" 2>/dev/null || true
  for _attempt in $(seq 1 30); do
    kill -0 "$pid" 2>/dev/null || return
    sleep 0.1
  done

  echo "[carelink] Process $pid did not stop after SIGINT; terminating it" >&2
  kill -TERM "$pid" 2>/dev/null || true
  for _attempt in $(seq 1 20); do
    kill -0 "$pid" 2>/dev/null || return
    sleep 0.1
  done

  echo "[carelink] Process $pid did not terminate; killing it" >&2
  kill -KILL "$pid" 2>/dev/null || true
}

cleanup() {
  if (( cleaning_up )); then
    return
  fi
  cleaning_up=1
  trap - INT TERM EXIT

  stop_child "$fall_detector_pid"
  [[ -z "$fall_detector_pid" ]] || wait "$fall_detector_pid" 2>/dev/null || true

  stop_child "$navigation_pid"
  [[ -z "$navigation_pid" ]] || wait "$navigation_pid" 2>/dev/null || true

  stop_child "$lidar_pid"
  [[ -z "$lidar_pid" ]] || wait "$lidar_pid" 2>/dev/null || true

  stop_child "$robot_pid"
  [[ -z "$robot_pid" ]] || wait "$robot_pid" 2>/dev/null || true
}

trap cleanup INT TERM EXIT

# ROS setup scripts legitimately inspect variables that may be unset.
set +u
source /opt/ros/jazzy/setup.bash
source "$robot_ws/install/setup.bash"
set -u

if [[ -s "$active_map_file" ]]; then
  IFS= read -r navigation_map <"$active_map_file"
fi
case "$navigation_map" in
  "$maps_dir"/*.yaml) ;;
  *)
    echo "[carelink] Active map must be a YAML file inside $maps_dir" >&2
    exit 1
    ;;
esac
if [[ ! -r "$navigation_map" ]]; then
  echo "[carelink] Active map is not readable: $navigation_map" >&2
  exit 1
fi

echo "[carelink] Starting ROS 2 motor stack"
ros2 launch articubot_one launch_robot.launch.py &
robot_pid=$!

echo "[carelink] Waiting for diff_cont controller to become active"
controller_ready=0
for _attempt in $(seq 1 60); do
  if ! kill -0 "$robot_pid" 2>/dev/null; then
    echo "[carelink] Motor stack exited before diff_cont became active" >&2
    exit 1
  fi

  controllers="$(timeout 2 ros2 control list_controllers --controller-manager /controller_manager 2>/dev/null || true)"
  if awk '$1 == "diff_cont" && $NF == "active" { found=1 } END { exit !found }' <<<"$controllers"; then
    controller_ready=1
    break
  fi
  sleep 1
done

if (( ! controller_ready )); then
  echo "[carelink] Timed out waiting for active diff_cont controller" >&2
  exit 1
fi

echo "[carelink] Motor controller active; starting RPLIDAR A1"
ros2 launch sllidar_ros2 sllidar_a1_launch.py \
  serial_port:=/dev/serial/by-id/usb-Silicon_Labs_CP2102_USB_to_UART_Bridge_Controller_0001-if00-port0 \
  frame_id:=laser &
lidar_pid=$!

echo "[carelink] Waiting for lidar scan data"
scan_ready=0
for _attempt in $(seq 1 30); do
  if ! kill -0 "$lidar_pid" 2>/dev/null; then
    echo "[carelink] Lidar exited before publishing /scan" >&2
    exit 1
  fi
  if timeout 2 ros2 topic echo /scan --once >/dev/null 2>&1; then
    scan_ready=1
    break
  fi
  sleep 1
done
if (( ! scan_ready )); then
  echo "[carelink] Timed out waiting for /scan" >&2
  exit 1
fi

echo "[carelink] Lidar ready; starting Nav2 with map $navigation_map"
ros2 launch carelink_patrol fixed_navigation.launch.py map:="$navigation_map" &
navigation_pid=$!

echo "[carelink] Starting shared YOLO fall detection and Firebase person follower"
cd "$fall_detector_dir"
"$robot_ws/camera_stack/run-vision-control.sh" --headless --enable-motion \
  --cmd-topic /carelink/follower_cmd_vel &
fall_detector_pid=$!

# A failure in any managed process restarts the complete stack through systemd.
wait -n "$robot_pid" "$lidar_pid" "$navigation_pid" "$fall_detector_pid"
exit_code=$?
echo "[carelink] A managed process exited (status $exit_code); restarting stack" >&2
exit "$exit_code"
