#!/usr/bin/env python3

import math
import time

import rclpy

from rclpy.node import Node
from rclpy.time import Time

from geometry_msgs.msg import PointStamped, PoseStamped
from control_msgs.msg import DynamicJointState
from tf2_ros import Buffer, TransformListener

from nav2_simple_commander.robot_navigator import (
    BasicNavigator,
    TaskResult,
)


# ==========================================================
# CareLink 3-Point Patrol + Auto Dock
# ==========================================================

NUM_POINTS = 3


# ----------------------------------------------------------
# 충전스테이션에서 처음 빠져나오기
# ----------------------------------------------------------

UNDOCK_DISTANCE = 0.30      # [m]
UNDOCK_SPEED = 0.05         # [m/s]


# ----------------------------------------------------------
# 순찰 후 충전스테이션 앞 복귀 지점
# ----------------------------------------------------------

PRE_DOCK_DISTANCE = 0.30    # [m]


# ----------------------------------------------------------
# 최종 도킹
#
# 고정된 0.8 m 제한을 두지 않는다.
# dock_state = 1이 될 때까지 20 cm 단위로 계속 전진한다.
# ----------------------------------------------------------

FINAL_DOCK_SPEED = 0.02     # [m/s]

DOCK_CHUNK_DISTANCE = 0.20  # 한 번에 전진할 거리 [m]

# 센서 이상 등에 대비한 안전 제한
# 0.02 m/s × 90 s ≈ 최대 1.8 m
MAX_DOCK_TIME = 90.0        # [s]


# ----------------------------------------------------------
# 현재 dock_state는 약 1 Hz로 갱신되므로
# 언도킹 직후 상태가 0으로 바뀌는 것을 기다리는 시간
# ----------------------------------------------------------

DOCK_RELEASE_WAIT = 3.0     # [s]


# ==========================================================
# CareLink Monitor Node
# ==========================================================

class CareLinkMonitor(Node):

    def __init__(self):

        super().__init__(
            'carelink_patrol_monitor'
        )

        self.points = []

        self.dock_state = None
        self.battery_voltage = None


        # --------------------------------------------------
        # TF
        # --------------------------------------------------

        self.tf_buffer = Buffer()

        self.tf_listener = TransformListener(
            self.tf_buffer,
            self
        )


        # --------------------------------------------------
        # RViz Publish Point
        # --------------------------------------------------

        self.point_sub = self.create_subscription(
            PointStamped,
            '/clicked_point',
            self.point_callback,
            10
        )


        # --------------------------------------------------
        # Battery / Dock 상태
        # --------------------------------------------------

        self.status_sub = self.create_subscription(
            DynamicJointState,
            '/dynamic_joint_states',
            self.status_callback,
            10
        )


    # ======================================================
    # RViz Publish Point Callback
    # ======================================================

    def point_callback(self, msg):

        if msg.header.frame_id != 'map':

            self.get_logger().warn(
                f'Clicked frame is '
                f'"{msg.header.frame_id}", '
                f'but "map" is required.'
            )

            return


        if len(self.points) >= NUM_POINTS:
            return


        self.points.append(
            (
                msg.point.x,
                msg.point.y
            )
        )


        index = len(
            self.points
        )


        self.get_logger().info(
            f'P{index} saved: '
            f'x={msg.point.x:.3f}, '
            f'y={msg.point.y:.3f}'
        )


    # ======================================================
    # Battery / Dock State Callback
    # ======================================================

    def status_callback(self, msg):

        for i, joint_name in enumerate(
            msg.joint_names
        ):

            if joint_name != 'carelink_status':
                continue


            if i >= len(
                msg.interface_values
            ):
                continue


            data = (
                msg.interface_values[i]
            )


            for j, interface_name in enumerate(
                data.interface_names
            ):

                if j >= len(
                    data.values
                ):
                    continue


                value = (
                    data.values[j]
                )


                if interface_name == 'dock_state':

                    self.dock_state = (
                        value >= 0.5
                    )


                elif interface_name == 'battery_voltage':

                    self.battery_voltage = (
                        value
                    )


# ==========================================================
# Utility Functions
# ==========================================================

def spin_monitor(
    node,
    timeout=0.02
):

    rclpy.spin_once(
        node,
        timeout_sec=timeout
    )


# ----------------------------------------------------------
# Quaternion -> Yaw
# ----------------------------------------------------------

def quaternion_to_yaw(q):

    return math.atan2(
        2.0 * (
            q.w * q.z
            +
            q.x * q.y
        ),
        1.0
        -
        2.0 * (
            q.y * q.y
            +
            q.z * q.z
        )
    )


# ----------------------------------------------------------
# 두 좌표 사이의 방향
# ----------------------------------------------------------

def heading(
    x1,
    y1,
    x2,
    y2
):

    return math.atan2(
        y2 - y1,
        x2 - x1
    )


# ----------------------------------------------------------
# Nav2용 PoseStamped 생성
# ----------------------------------------------------------

def make_pose(
    navigator,
    x,
    y,
    yaw
):

    pose = PoseStamped()


    pose.header.frame_id = 'map'

    pose.header.stamp = (
        navigator
        .get_clock()
        .now()
        .to_msg()
    )


    pose.pose.position.x = float(
        x
    )

    pose.pose.position.y = float(
        y
    )

    pose.pose.position.z = 0.0


    pose.pose.orientation.x = 0.0
    pose.pose.orientation.y = 0.0

    pose.pose.orientation.z = (
        math.sin(
            yaw / 2.0
        )
    )

    pose.pose.orientation.w = (
        math.cos(
            yaw / 2.0
        )
    )


    return pose


# ----------------------------------------------------------
# 현재 map -> base_link TF 얻기
# ----------------------------------------------------------

def get_start_tf(
    monitor
):

    start_tf = None


    while (
        rclpy.ok()
        and
        start_tf is None
    ):

        spin_monitor(
            monitor,
            0.05
        )


        try:

            start_tf = (
                monitor
                .tf_buffer
                .lookup_transform(
                    'map',
                    'base_link',
                    Time()
                )
            )

        except Exception:
            pass


    return start_tf


# ==========================================================
# Main
# ==========================================================

def main(args=None):

    rclpy.init(
        args=args
    )


    monitor = (
        CareLinkMonitor()
    )


    navigator = (
        BasicNavigator()
    )


    try:

        print()

        print(
            '=========================================='
        )

        print(
            ' CareLink 3-Point Patrol + Auto Dock'
        )

        print(
            '=========================================='
        )

        print()


        # ==================================================
        # 1. Dock 상태 확인
        # ==================================================

        print(
            '[1] Waiting for dock status...'
        )


        while (
            rclpy.ok()
            and
            monitor.dock_state is None
        ):

            spin_monitor(
                monitor
            )


        if not rclpy.ok():
            return


        print(
            f'    dock_state = '
            f'{int(monitor.dock_state)}'
        )


        if (
            monitor.battery_voltage
            is not None
        ):

            print(
                f'    battery_voltage = '
                f'{monitor.battery_voltage:.3f} V'
            )


        # --------------------------------------------------
        # 반드시 충전스테이션에 붙은 상태에서 시작
        # --------------------------------------------------

        if not monitor.dock_state:

            print()

            print(
                'ERROR: dock_state is not 1.'
            )

            print(
                'Robot must start from '
                'the charging station.'
            )

            return


        # ==================================================
        # 2. START 위치 / 방향 저장
        # ==================================================

        print()

        print(
            '[2] Saving charging-station '
            'START pose...'
        )


        start_tf = (
            get_start_tf(
                monitor
            )
        )


        if start_tf is None:

            print(
                'ERROR: Cannot obtain '
                'map -> base_link TF.'
            )

            return


        start_x = (
            start_tf
            .transform
            .translation
            .x
        )


        start_y = (
            start_tf
            .transform
            .translation
            .y
        )


        start_yaw = (
            quaternion_to_yaw(
                start_tf
                .transform
                .rotation
            )
        )


        print(
            f'    START x   = '
            f'{start_x:.3f}'
        )


        print(
            f'    START y   = '
            f'{start_y:.3f}'
        )


        print(
            f'    START yaw = '
            f'{start_yaw:.3f} rad'
        )


        # ==================================================
        # 3. RViz Publish Point 3개 입력
        # ==================================================

        print()

        print(
            '[3] RViz -> Publish Point'
        )


        print(
            '    P1 -> P2 -> P3 '
            '순서로 3개 지점만 찍으세요.'
        )


        print()


        print(
            '    ★ P3를 찍는 순간 '
            '자동 출발합니다.'
        )


        print()


        while (
            rclpy.ok()
            and
            len(monitor.points)
            < NUM_POINTS
        ):

            spin_monitor(
                monitor
            )


        if not rclpy.ok():
            return


        print()

        print(
            '    P1, P2, P3 received.'
        )


        for i, point in enumerate(
            monitor.points
        ):

            print(
                f'    P{i + 1}: '
                f'x={point[0]:.3f}, '
                f'y={point[1]:.3f}'
            )


        # ==================================================
        # 4. Nav2 확인
        # ==================================================

        print()

        print(
            '[4] Checking Nav2...'
        )


        navigator.waitUntilNav2Active()


        print(
            '    Nav2 ready.'
        )


        # ==================================================
        # 5. 충전스테이션에서 자동 후진
        # ==================================================

        print()

        print(
            '[5] UNDOCKING'
        )


        print(
            f'    Backup '
            f'{UNDOCK_DISTANCE:.2f} m '
            f'at '
            f'{UNDOCK_SPEED:.2f} m/s'
        )


        navigator.backup(
            backup_dist=UNDOCK_DISTANCE,
            backup_speed=UNDOCK_SPEED,
            time_allowance=10
        )


        dock_released = False


        # --------------------------------------------------
        # 후진하면서 dock_state 확인
        # --------------------------------------------------

        while not navigator.isTaskComplete():

            spin_monitor(
                monitor,
                0.05
            )


            if (
                monitor.dock_state
                is False
            ):

                if not dock_released:

                    print()

                    print(
                        '    dock_state changed: '
                        '1 -> 0'
                    )


                dock_released = True


        backup_result = (
            navigator.getResult()
        )


        if (
            backup_result
            != TaskResult.SUCCEEDED
        ):

            print()

            print(
                'ERROR: Backup behavior failed.'
            )

            return


        # --------------------------------------------------
        # dock_state가 약 1 Hz이므로
        # 후진 완료 후 최대 3초 추가 대기
        # --------------------------------------------------

        if not dock_released:

            print()

            print(
                '    Waiting for '
                'dock_state update...'
            )


            wait_start = (
                time.monotonic()
            )


            while (
                rclpy.ok()
                and
                time.monotonic()
                -
                wait_start
                <
                DOCK_RELEASE_WAIT
            ):

                spin_monitor(
                    monitor,
                    0.05
                )


                if (
                    monitor.dock_state
                    is False
                ):

                    dock_released = True


                    print(
                        '    dock_state changed: '
                        '1 -> 0'
                    )


                    break


        if not dock_released:

            print()


            if monitor.dock_state is None:

                print(
                    'ERROR: dock_state '
                    'is unavailable.'
                )

            else:

                print(
                    f'ERROR: dock_state = '
                    f'{int(monitor.dock_state)}'
                )


            print(
                'Dock release was '
                'not detected.'
            )


            return


        print()

        print(
            '    dock_state = 0'
        )


        print(
            '    UNDOCK SUCCESS'
        )


        # ==================================================
        # 6. PRE_DOCK 좌표 계산
        # ==================================================

        pre_dock_x = (
            start_x
            -
            PRE_DOCK_DISTANCE
            *
            math.cos(
                start_yaw
            )
        )


        pre_dock_y = (
            start_y
            -
            PRE_DOCK_DISTANCE
            *
            math.sin(
                start_yaw
            )
        )


        print()

        print(
            f'    PRE_DOCK = '
            f'({pre_dock_x:.3f}, '
            f'{pre_dock_y:.3f})'
        )


        # ==================================================
        # 7. P1 / P2 / P3 방향 계산
        # ==================================================

        p1 = monitor.points[0]
        p2 = monitor.points[1]
        p3 = monitor.points[2]


        yaw1 = heading(
            p1[0],
            p1[1],
            p2[0],
            p2[1]
        )


        yaw2 = heading(
            p2[0],
            p2[1],
            p3[0],
            p3[1]
        )


        yaw3_return = heading(
            p3[0],
            p3[1],
            p2[0],
            p2[1]
        )


        yaw2_return = heading(
            p2[0],
            p2[1],
            p1[0],
            p1[1]
        )


        yaw1_return = heading(
            p1[0],
            p1[1],
            pre_dock_x,
            pre_dock_y
        )


        waypoint_poses = [

            make_pose(
                navigator,
                p1[0],
                p1[1],
                yaw1
            ),

            make_pose(
                navigator,
                p2[0],
                p2[1],
                yaw2
            ),

            make_pose(
                navigator,
                p3[0],
                p3[1],
                yaw3_return
            ),

            make_pose(
                navigator,
                p2[0],
                p2[1],
                yaw2_return
            ),

            make_pose(
                navigator,
                p1[0],
                p1[1],
                yaw1_return
            ),
        ]


        # ==================================================
        # 8. P1 -> P2 -> P3 -> P2 -> P1
        # ==================================================

        print()

        print(
            '[6] PATROLLING'
        )


        print(
            '    P1 -> P2 -> P3 -> P2 -> P1'
        )


        navigator.followWaypoints(
            waypoint_poses
        )


        last_waypoint = -1
        waypoint_names = ['P1', 'P2', 'P3', 'P2', 'P1']


        while not navigator.isTaskComplete():

            spin_monitor(
                monitor
            )


            feedback = (
                navigator.getFeedback()
            )


            if feedback is not None:

                if (
                    feedback.current_waypoint
                    !=
                    last_waypoint
                ):

                    last_waypoint = (
                        feedback
                        .current_waypoint
                    )


                    print(
                        f'    Moving to '
                        f'{waypoint_names[last_waypoint]}'
                    )


        patrol_result = (
            navigator.getResult()
        )


        if (
            patrol_result
            !=
            TaskResult.SUCCEEDED
        ):

            print()

            print(
                'ERROR: Patrol failed.'
            )

            return


        print()

        print(
            '    P1 -> P2 -> P3 -> P2 -> P1 COMPLETE'
        )


        # ==================================================
        # 9. PRE_DOCK 복귀
        # ==================================================

        print()

        print(
            '[7] RETURNING TO '
            'CHARGING STATION'
        )


        pre_dock_pose = (
            make_pose(
                navigator,
                pre_dock_x,
                pre_dock_y,
                start_yaw
            )
        )


        navigator.goToPose(
            pre_dock_pose
        )


        while not navigator.isTaskComplete():

            spin_monitor(
                monitor
            )


        return_result = (
            navigator.getResult()
        )


        if (
            return_result
            !=
            TaskResult.SUCCEEDED
        ):

            print()

            print(
                'ERROR: Failed to '
                'reach PRE_DOCK.'
            )

            return


        print(
            '    PRE_DOCK reached.'
        )


        # ==================================================
        # 10. 최종 도킹
        #
        # 고정 거리로 끝내지 않는다.
        #
        # dock_state가 0이면:
        #    20 cm 직진
        #
        # 그래도 0이면:
        #    다시 20 cm 직진
        #
        # dock_state가 1이 되면:
        #    즉시 cancelTask()
        # ==================================================

        print()

        print(
            '[8] FINAL DOCKING'
        )


        print(
            f'    Final approach speed '
            f'= {FINAL_DOCK_SPEED:.2f} m/s'
        )


        print(
            '    Continue until '
            'dock_state = 1'
        )


        print(
            f'    Safety timeout '
            f'= {MAX_DOCK_TIME:.0f} s'
        )


        dock_success = False


        dock_start_time = (
            time.monotonic()
        )


        while (
            rclpy.ok()
            and
            not dock_success
        ):

            # ----------------------------------------------
            # 상태 최신화
            # ----------------------------------------------

            spin_monitor(
                monitor,
                0.02
            )


            # ----------------------------------------------
            # 이미 포고핀 접촉
            # ----------------------------------------------

            if monitor.dock_state:

                dock_success = True

                break


            # ----------------------------------------------
            # 안전 제한시간
            # ----------------------------------------------

            elapsed = (
                time.monotonic()
                -
                dock_start_time
            )


            if (
                elapsed
                >=
                MAX_DOCK_TIME
            ):

                print()

                print(
                    'ERROR: Docking timeout.'
                )

                break


            # ----------------------------------------------
            # 20 cm 직진
            # ----------------------------------------------

            print(
                f'    Docking forward '
                f'{DOCK_CHUNK_DISTANCE:.2f} m...'
            )


            navigator.driveOnHeading(
                dist=DOCK_CHUNK_DISTANCE,
                speed=FINAL_DOCK_SPEED,
                time_allowance=20
            )


            # ----------------------------------------------
            # 해당 20 cm 이동 중 계속 k값 확인
            # ----------------------------------------------

            while (
                not navigator.isTaskComplete()
            ):

                spin_monitor(
                    monitor,
                    0.01
                )


                # ==========================================
                # 포고핀 접촉
                # ==========================================

                if monitor.dock_state:

                    print()

                    print(
                        '    dock_state = 1 !!!'
                    )


                    print(
                        '    POGO CONTACT DETECTED'
                    )


                    dock_success = True


                    # --------------------------------------
                    # 진행 중인 직진 즉시 취소
                    # --------------------------------------

                    navigator.cancelTask()


                    break


                # ------------------------------------------
                # 최종 도킹 전체 안전시간 확인
                # ------------------------------------------

                elapsed = (
                    time.monotonic()
                    -
                    dock_start_time
                )


                if (
                    elapsed
                    >=
                    MAX_DOCK_TIME
                ):

                    print()

                    print(
                        'ERROR: '
                        'Docking timeout.'
                    )


                    navigator.cancelTask()

                    break


            # ----------------------------------------------
            # k = 1이면 최종 종료
            # ----------------------------------------------

            if dock_success:
                break


            # ----------------------------------------------
            # 제한시간 초과
            # ----------------------------------------------

            if (
                time.monotonic()
                -
                dock_start_time
                >=
                MAX_DOCK_TIME
            ):

                break


            # ----------------------------------------------
            # 20 cm 이동 완료 후에도 k=0이면
            # 다음 반복에서 다시 20 cm 전진
            # ----------------------------------------------

            spin_monitor(
                monitor,
                0.05
            )


            if monitor.dock_state:

                dock_success = True

                break


        # ==================================================
        # 11. Dock 성공 시 취소 명령 처리 확인
        # ==================================================

        if dock_success:

            stop_wait = (
                time.monotonic()
            )


            while (
                time.monotonic()
                -
                stop_wait
                <
                2.0
            ):

                spin_monitor(
                    monitor,
                    0.02
                )


                if (
                    navigator
                    .isTaskComplete()
                ):

                    break


        else:

            # ----------------------------------------------
            # 실패 / timeout 시에도 주행 중지
            # ----------------------------------------------

            try:

                navigator.cancelTask()

            except Exception:
                pass


        # ==================================================
        # 12. 결과
        # ==================================================

        print()

        print(
            '=========================================='
        )


        if dock_success:

            print(
                ' DOCKING SUCCESS'
            )


            print()


            print(
                ' P1 -> P2 -> P3 -> P2 -> P1 complete'
            )


            print(
                ' Charging station reached'
            )


            print(
                ' dock_state = 1'
            )


            print(
                ' Robot stopped'
            )


        else:

            print(
                ' DOCKING FAILED'
            )


            print()


            print(
                ' dock_state did not '
                'become 1.'
            )


            print(
                ' Robot stopped by '
                'safety timeout.'
            )


        print(
            '=========================================='
        )


        print()


    # ======================================================
    # Ctrl + C
    # ======================================================

    except KeyboardInterrupt:

        print()

        print(
            'Manual stop requested.'
        )


        try:

            navigator.cancelTask()

        except Exception:
            pass


    # ======================================================
    # 종료
    # ======================================================

    finally:

        monitor.destroy_node()

        navigator.destroyNode()


        if rclpy.ok():

            rclpy.shutdown()


# ==========================================================
# Entry Point
# ==========================================================

if __name__ == '__main__':

    main()