# CareLink keyboard mapping

This workflow creates a map without the mobile app. It stops the normal
autonomy service, starts only the motor stack, lidar, and `slam_toolbox`, then
uses `teleop_twist_keyboard` to drive the robot. A successful save selects the
new map, restarts autonomy, and the existing Firebase navigation bridge uploads
the map to `robot_maps/main` for the app.

## Create and activate a map

Keep the robot near the intended starting or dock area. From an interactive
SSH terminal run:

```bash
cd /home/carelink/robot_ws
./start-carelink-mapping.sh ward_b
```

Map names may contain letters, numbers, underscores, and hyphens. Existing
maps are never overwritten.

Keyboard controls:

```text
i / ,   forward / backward
j / l   rotate left / right
k       stop
Ctrl-C  stop teleoperation and open the action prompt
```

After Ctrl-C, choose one action:

```text
s       save and activate the map
r       resume mapping without losing the current SLAM map
d       discard the map without saving
Enter   discard (safe default)
```

The script limits teleoperation to 0.15 m/s and 0.50 rad/s. Mapping mode does
not run Nav2 collision avoidance, so keep an operator at the emergency stop,
drive slowly, and keep clear of people and obstacles.

For a useful map:

1. Drive around the complete boundary and visible obstacles.
2. Avoid wheel slip and moving objects near the lidar.
3. Revisit previously mapped corridors so loop closure can align the map.
4. Return near the starting area before choosing save.

The map is saved as:

```text
/home/carelink/robot_ws/src/articubot_one/maps/ward_b.yaml
/home/carelink/robot_ws/src/articubot_one/maps/ward_b.pgm
```

The selected YAML path is stored in:

```text
/home/carelink/.config/carelink/active-map
```

The autonomy service reads this file on every start. When Nav2 and the Firebase
bridge finish starting, the app receives the new image and `mapVersion`. Goals,
patrol points, and the dock pose must be selected again because coordinates
from the previous map do not belong to the new map.

Use `--no-start` to save and select the map without restarting autonomy:

```bash
./start-carelink-mapping.sh ward_b --no-start
```

## View the map from the Ubuntu laptop

With ROS 2 Jazzy installed and the laptop on the same ROS network as the robot:

```bash
source /opt/ros/jazzy/setup.bash
export ROS_DOMAIN_ID=0
export ROS_LOCALHOST_ONLY=0
rviz2
```

Set the fixed frame to `map`, then add the `/map` and `/scan` displays.

## Check startup

```bash
systemctl --user status carelink-autonomy.service
journalctl --user -u carelink-autonomy.service -f
```

The bridge log should report `Fixed map uploaded` with the new map version.
