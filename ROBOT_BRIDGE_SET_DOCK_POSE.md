# Robot bridge contract: `SET_DOCK_POSE`

The Flutter app writes `robot_commands/navigation` with `status: REQUESTED`.
The robot bridge must implement the following state machine for the same
`commandId` (updates must be atomic and must not overwrite a newer command):

1. Ignore commands other than `SET_DOCK_POSE` in this handler.
2. Validate that `x`, `y`, and `yaw` are finite numbers, `yaw` is in radians,
   the current map version equals `mapVersion`, the pose is inside the map, and
   its occupancy cell is known and free.
3. Verify from the robot's charging/dock signal that it is physically docked.
4. Change the status to `ACCEPTED`.
5. Publish the pose in the ROS `map` frame as the AMCL initial pose. Convert yaw
   to a quaternion (`z = sin(yaw / 2)`, `w = cos(yaw / 2)`) and use an
   appropriate localization covariance.
6. Persist `{x, y, yaw, mapVersion}` using an atomic file/database replacement.
   Load and apply this pose on boot only when the robot starts docked and the
   stored `mapVersion` still matches the active map.
7. Change the status to `SAVED` only after both AMCL application and durable
   persistence succeed. On any error use `FAILED` and add a user-readable
   `errorMessage`.

Recommended additional response fields are `acceptedAt`, `savedAt` or
`failedAt`, all server timestamps. The bridge should retain processed
`commandId` values (or make persistence idempotent) so reconnects cannot apply
the same request twice.
