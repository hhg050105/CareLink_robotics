# CareLink keyboard mapping

This workflow creates a map without the mobile app. It stops the normal
autonomy service, starts only the motor stack, lidar, and `slam_toolbox`, then
uses `teleop_twist_keyboard` to drive the robot. Saving writes the local map,
stops the mapping stack, and uploads directly to `robot_maps/main`. It reads
back the image and metadata before selecting the new map and starting autonomy.
Network failures are retried up to five times with bounded request timeouts.

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

The autonomy service reads this file on every start. Firebase already contains
the verified new image and `mapVersion` before the new map is selected. The
bridge also uploads and verifies the selected map on startup; if it exits, its
launch configuration restarts it after five seconds. Goals,
patrol points, and the dock pose must be selected again because coordinates
from the previous map do not belong to the new map.

Use `--no-start` to save, upload, verify, and select the map without restarting autonomy:

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

## Upload failure and retry

If all upload attempts fail, the saved YAML/PGM files remain on disk and the
previous active-map selection is retained. If autonomy was previously running,
the script restores it with the previous map. Do not remap or overwrite the
saved files to retry an upload.

To upload an existing saved map without moving the robot:

```bash
source /opt/ros/jazzy/setup.bash
source /home/carelink/robot_ws/install/setup.bash
ros2 run carelink_patrol upload_fixed_map /home/carelink/robot_ws/src/articubot_one/maps/ward_b.yaml
```

This standalone command uploads only; it does not select the map or restart
navigation. After a successful retry, select that same YAML in
`/home/carelink/.config/carelink/active-map` and restart autonomy before sending
navigation goals against it. The app must refresh `robot_maps/main`; upload
verification does not confirm that the app has rendered the new map.

Mapping-time live previews are not enabled by this change.
