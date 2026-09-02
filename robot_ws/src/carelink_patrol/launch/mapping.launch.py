"""Start slam_toolbox in mapping mode for the CareLink real robot."""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration


def generate_launch_description():
    articubot = get_package_share_directory('articubot_one')
    slam_toolbox = get_package_share_directory('slam_toolbox')
    default_params = os.path.join(
        articubot, 'config', 'mapper_params_online_async.yaml')

    return LaunchDescription([
        DeclareLaunchArgument(
            'slam_params_file', default_value=default_params),
        DeclareLaunchArgument('use_sim_time', default_value='false'),
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(
                os.path.join(
                    slam_toolbox, 'launch', 'online_async_launch.py')),
            launch_arguments={
                'slam_params_file': LaunchConfiguration('slam_params_file'),
                'use_sim_time': LaunchConfiguration('use_sim_time'),
                'autostart': 'true',
                'use_lifecycle_manager': 'false',
            }.items()),
    ])
