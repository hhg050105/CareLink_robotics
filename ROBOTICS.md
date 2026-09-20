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
- `camera_stack`: shared YOLO camera processing and Firebase fall alerts
- `robot_ws/camera_stack`: Firebase person-follow control sharing camera detections
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

## Updated runtime (2026-09-20)

- The autonomy service starts `robot_ws/camera_stack/run-vision-control.sh`.
  Fall detection and following share one camera and inference worker.
- App following uses `robots/carelink-01/control/personFollower` (`FOLLOW` / `STOP`).
- Mapping: `./start-carelink-mapping.sh new_map03`, drive, then Ctrl-C and `s`.
  Saving uploads and verifies Firestore `robot_maps/main` before selecting the
  new map. Network failures retry five times. Mapping launch processes run in
  separate sessions so cleanup does not abort a successful save.
- Patrol accepts points within 0.30 m without final heading alignment, with a
  0.35 m/s speed ceiling. Single-goal navigation keeps orientation checking.
- `new_map02` is the included default map. A local `active-map` file overrides
  this default. Previous map files were removed from the current tree.

The runtime directories must be placed at `/home/carelink/camera_stack` and
`/home/carelink/robot_ws`. Keep the existing camera Python environment,
libcamera installation, model, and credentials on the robot. On a new install,
after provisioning those dependencies, link the shared assets:

```bash
cd /home/carelink/robot_ws/camera_stack
ln -s /home/carelink/camera_stack/.venv-yolo .venv-yolo
ln -s /home/carelink/camera_stack/local local
ln -s /home/carelink/camera_stack/models models
ln -s /home/carelink/camera_stack/secrets secrets
```

Install `systemd/carelink-autonomy.service` as a user service and enable it;
user lingering is required to start it without logging in. Credentials,
models, active-map selection, and saved dock pose are local deployment data.
Set the initial pose again when changing maps.
