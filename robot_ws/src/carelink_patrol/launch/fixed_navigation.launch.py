"""Start Nav2 with the CareLink fixed map and the Firebase goal bridge."""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    articubot = get_package_share_directory('articubot_one')
    nav2 = get_package_share_directory('nav2_bringup')
    default_map = os.path.join(articubot, 'maps', 'new_map02.yaml')
    default_params = os.path.join(articubot, 'config', 'nav2_params.yaml')

    return LaunchDescription([
        DeclareLaunchArgument('map', default_value=default_map),
        DeclareLaunchArgument('params_file', default_value=default_params),
        DeclareLaunchArgument('use_sim_time', default_value='false'),
        DeclareLaunchArgument('autostart', default_value='true'),
        DeclareLaunchArgument('start_bridge', default_value='true'),
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(
                os.path.join(nav2, 'launch', 'bringup_launch.py')),
            launch_arguments={
                'map': LaunchConfiguration('map'),
                'params_file': LaunchConfiguration('params_file'),
                'use_sim_time': LaunchConfiguration('use_sim_time'),
                'autostart': LaunchConfiguration('autostart'),
            }.items()),
        Node(
            package='carelink_patrol', executable='firebase_nav_bridge',
            name='firebase_nav_bridge', output='screen',
            respawn=True, respawn_delay=5.0,
            condition=IfCondition(LaunchConfiguration('start_bridge')),
            parameters=[{'map_yaml_path': LaunchConfiguration('map')}]),
        Node(
            package='carelink_patrol', executable='cmd_vel_mux',
            name='carelink_cmd_vel_mux', output='screen'),
        Node(
            package='carelink_patrol', executable='dock_pose_initializer',
            name='dock_pose_initializer', output='screen',
            parameters=[{'map_yaml_path': LaunchConfiguration('map')}]),
        Node(
            package='carelink_patrol', executable='battery_firebase',
            name='battery_firebase', output='screen'),
    ])
