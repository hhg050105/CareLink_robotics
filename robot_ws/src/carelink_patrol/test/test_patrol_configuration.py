from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock
import xml.etree.ElementTree as ET

import pytest
import yaml
from ament_index_python.packages import get_package_share_directory
from carelink_patrol.firebase_nav_bridge import FirebaseNavBridge


@pytest.mark.parametrize('patrol', [False, True])
def test_patrol_selects_its_own_tree(patrol):
    fake = SimpleNamespace(active_points=[(1., 2., 0.)], active_point_index=0,
                           active_is_patrol=patrol, action_client=Mock(),
                           get_parameter=lambda name: SimpleNamespace(value='/test/patrol.xml'),
                           _goal_response=Mock())
    FirebaseNavBridge._send_active_point(fake)
    goal = fake.action_client.send_goal_async.call_args.args[0]
    assert goal.behavior_tree == ('/test/patrol.xml' if patrol else '')


def test_trees_select_valid_controllers_and_goal_checkers():
    config = yaml.safe_load((Path(get_package_share_directory('articubot_one')) /
                             'config/nav2_params.yaml').read_text())
    server = config['controller_server']['ros__parameters']
    trees = Path(get_package_share_directory('carelink_patrol')) / 'behavior_trees'
    for name, checker, controller in [('patrol', 'patrol_goal_checker', 'PatrolFollowPath'),
                                      ('navigate', 'general_goal_checker', 'FollowPath')]:
        tree = ET.parse(trees / f'{name}.xml')
        assert tree.find('.//FollowPath').attrib['goal_checker_id'] == checker
        assert tree.find('.//ControllerSelector').attrib['default_controller'] == controller
        assert checker in server['goal_checker_plugins']
        assert controller in server['controller_plugins']
    assert server['patrol_goal_checker']['plugin'] == 'nav2_controller::PositionGoalChecker'
    assert server['patrol_goal_checker']['xy_goal_tolerance'] == .30
    assert server['PatrolFollowPath']['GoalAngleCritic']['enabled'] is False
    assert server['FollowPath']['GoalAngleCritic']['enabled'] is True
    limits = yaml.safe_load((Path(get_package_share_directory('articubot_one')) /
                             'config/my_controllers.yaml').read_text())['diff_cont']['ros__parameters']
    smoother = config['velocity_smoother']['ros__parameters']
    assert server['PatrolFollowPath']['vx_max'] <= smoother['max_velocity'][0] <= limits['linear.x.max_velocity']
