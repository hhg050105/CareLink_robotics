# CareLink Robotics

ROS 2 Jazzy software for the CareLink mobile robot: fixed-map Nav2 navigation,
three-point patrol, keyboard mapping, motor control, RPLIDAR, and
Firebase-connected YOLO fall detection.

## Repository layout

- `robot_ws/src/carelink_patrol`: patrol, Firebase navigation bridge, docking
  pose initialization, velocity mux, battery bridge, and launch files
- `robot_ws/src/articubot_one`: robot description, ros2_control, Nav2 settings,
  and maps
- `robot_ws/src/diffdrive_arduino`: differential-drive hardware plugin
- `robot_ws/src/sllidar_ros2`: RPLIDAR ROS 2 driver
- `robot_ws/start-carelink-autonomy.sh`: complete autonomous runtime
- `robot_ws/start-carelink-mapping.sh`: interactive mapping workflow
- `camera_stack`: YOLO fall detection and optional person-following source
- `systemd/carelink-autonomy.service`: user service definition

## Build

```bash
source /opt/ros/jazzy/setup.bash
cd /home/carelink/robot_ws
colcon build --symlink-install
```

The runtime currently targets the `carelink` Linux account and expects this
workspace at `/home/carelink/robot_ws`.

## Runtime

```bash
systemctl --user start carelink-autonomy.service
systemctl --user status carelink-autonomy.service
```

See `robot_ws/src/carelink_patrol/CARELINK_MAPPING.md` for map creation and
activation.

## Local-only files

Credentials and model binaries are intentionally excluded:

- `/home/carelink/camera_stack/secrets/firebase-service-account.json`
- `/home/carelink/camera_stack/models/yolo11n.onnx`

Never commit Firebase credentials, SSH keys, generated builds, logs, or camera
captures.

## Safety

Keep an emergency stop available. Keyboard mapping has no Nav2 obstacle
avoidance. Confirm localization and clear the robot's path before navigation.
