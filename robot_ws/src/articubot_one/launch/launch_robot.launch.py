import os

from ament_index_python.packages import get_package_share_directory

from launch import LaunchDescription
from launch_ros.actions import Node

import xacro


def generate_launch_description():

    pkg_path = get_package_share_directory('articubot_one')

    # Real robot URDF
    xacro_file = os.path.join(
        pkg_path,
        'description',
        'robot_real.urdf.xacro'
    )

    robot_description = xacro.process_file(xacro_file).toxml()

    # ros2_control controller configuration
    controller_config = os.path.join(
        pkg_path,
        'config',
        'my_controllers.yaml'
    )

    # Publish robot_description and TF
    robot_state_publisher = Node(
        package='robot_state_publisher',
        executable='robot_state_publisher',
        output='screen',
        parameters=[
            {'robot_description': robot_description}
        ]
    )

    # ros2_control Controller Manager
    controller_manager = Node(
    	package='controller_manager',
    	executable='ros2_control_node',
    	parameters=[
        	controller_config
    	],
    	output='screen'
    )

    # Joint State Broadcaster
    joint_state_broadcaster = Node(
        package='controller_manager',
        executable='spawner',
        arguments=[
            'joint_broad',
            '--controller-manager',
            '/controller_manager'
        ],
        output='screen'
    )

    # Differential Drive Controller
    diff_drive_controller = Node(
        package='controller_manager',
        executable='spawner',
        arguments=[
            'diff_cont',
            '--controller-manager',
            '/controller_manager'
        ],
        output='screen'
    )

    return LaunchDescription([
        robot_state_publisher,
        controller_manager,
        joint_state_broadcaster,
        diff_drive_controller
    ])
