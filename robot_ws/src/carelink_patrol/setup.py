from glob import glob
import os

from setuptools import find_packages, setup

package_name = 'carelink_patrol'

setup(
    name=package_name,
    version='0.0.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        (os.path.join('share', package_name, 'launch'), glob('launch/*.launch.py')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='carelink',
    maintainer_email='hhg050105@g.seoultech.ac.kr',
    description='TODO: Package description',
    license='TODO: License declaration',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
        'console_scripts': [
            'patrol_dock = carelink_patrol.patrol_dock:main',
            'battery_firebase = carelink_patrol.battery_firebase:main',
            'firebase_patrol_bridge = carelink_patrol.firebase_patrol_bridge:main',
            'firebase_live_map = carelink_patrol.firebase_live_map:main',
            'firebase_nav_bridge = carelink_patrol.firebase_nav_bridge:main',
            'cmd_vel_mux = carelink_patrol.cmd_vel_mux:main',
            'dock_pose_initializer = carelink_patrol.dock_pose_initializer:main',
        ],
    },
)
