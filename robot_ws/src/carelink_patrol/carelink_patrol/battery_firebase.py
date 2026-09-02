#!/usr/bin/env python3
"""Publish estimated 3S Li-ion battery status to Firestore."""

from pathlib import Path
from typing import Optional

import rclpy
from control_msgs.msg import DynamicJointState
from rclpy.node import Node
from rclpy.executors import ExternalShutdownException


LI_ION_DISCHARGE_CURVE = (
    (3.20, 0), (3.40, 5), (3.50, 10), (3.60, 20), (3.70, 40),
    (3.75, 50), (3.80, 60), (3.90, 75), (4.00, 85), (4.10, 95),
    (4.20, 100),
)


def estimate_battery_percent(pack_voltage: float, cell_count: int = 3) -> int:
    """Estimate state of charge from pack voltage using interpolation."""
    if cell_count <= 0:
        raise ValueError('cell_count must be greater than zero')
    cell_voltage = pack_voltage / cell_count
    if cell_voltage <= LI_ION_DISCHARGE_CURVE[0][0]:
        return 0
    if cell_voltage >= LI_ION_DISCHARGE_CURVE[-1][0]:
        return 100
    for (low_v, low_pct), (high_v, high_pct) in zip(
            LI_ION_DISCHARGE_CURVE, LI_ION_DISCHARGE_CURVE[1:]):
        if cell_voltage <= high_v:
            ratio = (cell_voltage - low_v) / (high_v - low_v)
            return round(low_pct + ratio * (high_pct - low_pct))
    return 100


class BatteryFirebaseNode(Node):
    """Read battery voltage from ros2_control and update Firestore."""

    def __init__(self) -> None:
        super().__init__('battery_firebase')
        self.declare_parameter(
            'credential_path',
            '/home/carelink/camera_stack/secrets/firebase-service-account.json')
        self.declare_parameter('document_path', 'robot_status/main')
        self.declare_parameter('upload_interval_sec', 10.0)
        self.declare_parameter('cell_count', 3)
        self.declare_parameter('capacity_mah', 5200)

        self.cell_count = int(self.get_parameter('cell_count').value)
        self.capacity_mah = int(self.get_parameter('capacity_mah').value)
        interval = float(self.get_parameter('upload_interval_sec').value)
        if self.cell_count <= 0:
            raise ValueError('cell_count must be greater than zero')
        if interval <= 0:
            raise ValueError('upload_interval_sec must be greater than zero')

        self.latest_voltage: Optional[float] = None
        self.document = self._connect_firestore()
        self.create_subscription(
            DynamicJointState, '/dynamic_joint_states',
            self.status_callback, 10)
        self.create_timer(interval, self.upload_status)

    def _connect_firestore(self):
        import firebase_admin
        from firebase_admin import credentials, firestore
        credential_path = Path(
            str(self.get_parameter('credential_path').value)).expanduser()
        if not credential_path.is_file():
            raise FileNotFoundError(
                f'Firebase credential not found: {credential_path}')
        if not firebase_admin._apps:
            firebase_admin.initialize_app(
                credentials.Certificate(str(credential_path)))
        document_path = str(
            self.get_parameter('document_path').value).strip('/')
        if document_path.count('/') != 1:
            raise ValueError(
                'document_path must be collection/document, e.g. robot_status/main')
        self.firestore = firestore
        self.get_logger().info(f'Firebase connected: {document_path}')
        return firestore.client().document(document_path)

    def status_callback(self, msg: DynamicJointState) -> None:
        for index, joint_name in enumerate(msg.joint_names):
            if joint_name != 'carelink_status':
                continue
            if index >= len(msg.interface_values):
                return
            data = msg.interface_values[index]
            for value_index, interface_name in enumerate(data.interface_names):
                if (interface_name == 'battery_voltage' and
                        value_index < len(data.values)):
                    voltage = float(data.values[value_index])
                    if voltage > 0.0:
                        self.latest_voltage = voltage
                    return

    def upload_status(self) -> None:
        if self.latest_voltage is None:
            return
        voltage = self.latest_voltage
        percent = estimate_battery_percent(voltage, self.cell_count)
        payload = {
            'batteryVoltage': round(voltage, 3),
            'batteryPercent': percent,
            'batteryCapacityMah': self.capacity_mah,
            'batteryCellCount': self.cell_count,
            'batteryUpdatedAt': self.firestore.SERVER_TIMESTAMP,
        }
        try:
            self.document.set(payload, merge=True, timeout=5.0)
            self.get_logger().info(
                f'Firebase battery: {voltage:.3f} V, {percent}%')
        except Exception as error:
            self.get_logger().error(f'Firebase battery update failed: {error}')


def main(args=None) -> None:
    rclpy.init(args=args)
    node = None
    try:
        node = BatteryFirebaseNode()
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    except ExternalShutdownException:
        pass
    finally:
        if node is not None:
            node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
