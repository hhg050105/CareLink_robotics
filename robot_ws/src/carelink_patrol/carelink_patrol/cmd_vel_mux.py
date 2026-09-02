#!/usr/bin/env python3
"""Select exactly one CareLink motion source for the base controller."""

from geometry_msgs.msg import TwistStamped
import rclpy
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from std_msgs.msg import Bool


class CmdVelMux(Node):
    """Route follower commands in FOLLOW mode, otherwise route Nav2."""

    def __init__(self) -> None:
        super().__init__('carelink_cmd_vel_mux')
        self.declare_parameter('timeout_sec', 0.6)
        self.timeout = float(self.get_parameter('timeout_sec').value)
        if self.timeout <= 0.0:
            raise ValueError('timeout_sec must be greater than zero')
        self.follow_active = False
        self.commands = {'follow': None, 'navigation': None}
        self.received_at = {'follow': None, 'navigation': None}
        self.publisher = self.create_publisher(TwistStamped, '/diff_cont/cmd_vel', 10)
        self.create_subscription(Bool, '/carelink/person_follow_active', self._mode_callback, 10)
        self.create_subscription(TwistStamped, '/carelink/follower_cmd_vel', lambda msg: self._command_callback('follow', msg), 10)
        self.create_subscription(TwistStamped, '/carelink/navigation_cmd_vel', lambda msg: self._command_callback('navigation', msg), 10)
        self.create_timer(0.05, self._publish_selected)
        self.get_logger().info('Motion mux ready: FOLLOW selects follower; otherwise Nav2')

    def _mode_callback(self, message: Bool) -> None:
        active = bool(message.data)
        if active != self.follow_active:
            self.follow_active = active
            source = 'person follower' if active else 'Nav2'
            self.get_logger().info(f'Motion source changed to {source}')

    def _command_callback(self, source: str, message: TwistStamped) -> None:
        self.commands[source] = message
        self.received_at[source] = self.get_clock().now()

    def _publish_selected(self) -> None:
        source = 'follow' if self.follow_active else 'navigation'
        message = self.commands[source]
        received = self.received_at[source]
        if (message is None or received is None or
                (self.get_clock().now() - received).nanoseconds / 1e9 > self.timeout):
            message = TwistStamped()
            message.header.frame_id = 'base_link'
        message.header.stamp = self.get_clock().now().to_msg()
        self.publisher.publish(message)


def main(args=None) -> None:
    rclpy.init(args=args)
    node = CmdVelMux()
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
