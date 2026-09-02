# CareLink

CareLink combines the mobile-robot software with Flutter applications for
care recipients and guardians.

## Repository layout

- `lib`, `android`, `ios`, `web`, and the other Flutter platform directories:
  the CareLink care-recipient application
- `carelink_guardian`: the CareLink guardian Flutter application
- `robot_ws/src/carelink_patrol`: patrol, Firebase navigation bridge, docking
  pose initialization, velocity mux, battery bridge, and launch files
- `robot_ws/src/articubot_one`: robot description, ros2_control, Nav2 settings,
  and maps
- `robot_ws/src/diffdrive_arduino`: differential-drive hardware plugin
- `robot_ws/src/sllidar_ros2`: RPLIDAR ROS 2 driver
- `camera_stack`: fall detection and optional person-following source
- `systemd/carelink-autonomy.service`: user service definition

## Flutter applications

From the repository root, run the care-recipient application with:

```bash
flutter pub get
flutter run
```

Run the guardian application with:

```bash
cd carelink_guardian
flutter pub get
flutter run
```

## Robot build

```bash
source /opt/ros/jazzy/setup.bash
cd /home/carelink/robot_ws
colcon build --symlink-install
```

The robot runtime currently targets the `carelink` Linux account and expects
the workspace at `/home/carelink/robot_ws`.

## Robot runtime

```bash
systemctl --user start carelink-autonomy.service
systemctl --user status carelink-autonomy.service
```

See `robot_ws/src/carelink_patrol/CARELINK_MAPPING.md` for map creation and
activation.

## Local-only files

Credentials, model binaries, generated builds, logs, and local SDK files are
excluded from Git. Never commit Firebase service-account credentials, SSH keys,
camera captures, or other private configuration.

## Safety

Keep an emergency stop available. Keyboard mapping has no Nav2 obstacle
avoidance. Confirm localization and clear the robot's path before navigation.
