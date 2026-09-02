# CareLink fixed-map navigation

## Firestore contract

The fixed map is published to `robot_maps/main`. `mapVersion` is the SHA-256
identity of the YAML and PGM pair. The app must keep the displayed
`mapVersion` and submit a goal only against that same version.

Write a navigation request to `robot_commands/navigation`:

```json
{
  "commandId": "goal-001",
  "command": "NAVIGATE",
  "status": "REQUESTED",
  "x": 1.25,
  "y": -0.8,
  "yaw": 0.0,
  "mapVersion": "value read from robot_maps/main",
  "requestedAt": "Firestore server timestamp"
}
```

The bridge atomically claims the request and writes `ACCEPTED`, then `MOVING`,
then `ARRIVED` or `FAILED`. A rejected/canceled Nav2 result is recorded as
`FAILED`/`CANCELLED`; `error`, `acceptedAt`, `movingAt`, and `completedAt`
are maintained as applicable.

Cancellation uses the same document:

```json
{
  "commandId": "cancel-001",
  "command": "CANCEL",
  "targetCommandId": "goal-001",
  "status": "REQUESTED"
}
```

For a three-point patrol, write exactly three map coordinates. The robot visits
them in array order, and `yaw` is optional (default `0.0`):

```json
{
  "commandId": "patrol-001",
  "command": "PATROL",
  "status": "REQUESTED",
  "points": [
    {"x": 1.25, "y": -0.8},
    {"x": 2.1, "y": 0.4, "yaw": 1.57},
    {"x": 0.3, "y": 1.0}
  ],
  "mapVersion": "value read from robot_maps/main",
  "requestedAt": "Firestore server timestamp"
}
```

During patrol, `currentPoint` is 1, 2, or 3 and `totalPoints` is 3. `ARRIVED`
means all three points completed. If a point fails, the command becomes
`FAILED` and movement stops without sending the remaining points.

## App touch conversion

`robot_maps/main` declares a top-left image origin, x to the right, and y down.
For an image shown with fit-center, first remove display scaling and letterbox:

```text
scale = min(viewWidth / imageWidth, viewHeight / imageHeight)
drawWidth = imageWidth * scale
drawHeight = imageHeight * scale
offsetX = (viewWidth - drawWidth) / 2
offsetY = (viewHeight - drawHeight) / 2
pixelX = (touchX - offsetX) / scale
pixelY = (touchY - offsetY) / scale
```

Reject touches outside `[offsetX, offsetX + drawWidth)` or
`[offsetY, offsetY + drawHeight)`. For this unrotated map:

```text
mapX = originX + pixelX * resolution
mapY = originY + (imageHeight - pixelY) * resolution
```

For crop-center use `scale = max(...)` and retain the possibly negative
offsets. Do not use screen coordinates directly. The bridge performs the final
map-boundary and free-cell check.

## Safe real-robot sequence

Never run navigation while `carelink_person_follower` is publishing motion.
The installed `carelink-autonomy.service` currently starts both the motor stack
and motion-enabled follower, so stop that unit and start the motor stack alone.

```bash
systemctl --user stop carelink-autonomy.service
source /opt/ros/jazzy/setup.bash
source /home/carelink/robot_ws/install/setup.bash
ros2 launch articubot_one launch_robot.launch.py
```

In another terminal, start lidar if it is not already present, then verify
hardware before Nav2:

```bash
ros2 control list_controllers
ros2 topic hz /scan
ros2 topic echo /diff_cont/odom --once
ros2 run tf2_ros tf2_echo odom base_link
```

Start fixed-map Nav2 without Firebase first:

Before doing so, stop any separately launched `localization_launch.py` or other
Nav2 process. The combined launch below already starts map server, AMCL, and the
navigation servers; running either half twice causes duplicate node names.

```bash
ros2 launch carelink_patrol fixed_navigation.launch.py start_bridge:=false
ros2 lifecycle get /map_server
ros2 lifecycle get /amcl
ros2 action list | grep navigate_to_pose
ros2 run tf2_ros tf2_echo map base_link
ros2 topic info /diff_cont/cmd_vel -v
```

Set the initial pose in RViz and confirm AMCL convergence. Ensure the only
motion path is Nav2 collision monitor to `/diff_cont/cmd_vel`; there must be no
person-follower publisher. Test a short clear-space RViz goal at low speed with
an operator at the emergency stop. Only then start the bridge:

```bash
ros2 run carelink_patrol firebase_nav_bridge
```

Do not start `patrol_dock`, `firebase_patrol_bridge`, or `firebase_live_map`
during this flow. They remain legacy/manual tools and are not launched by the
new fixed navigation launch file.
