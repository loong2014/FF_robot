from __future__ import annotations

import json
import unittest
from typing import Dict

from robot_protocol import (
    CommandId,
    DiscreteCommand,
    DogBehavior,
    SkillInvokeCommand,
)

from robot_server.config import ROSConfig
from robot_server.ros import RosSkillBridge


class _FakeGoal:
    def __init__(self) -> None:
        self.invoker = ""
        self.invoke_priority = 0
        self.hold_time = 0.0
        self.args = ""


class _FakeActionClient:
    def __init__(self, topic: str) -> None:
        self.topic = topic
        self.timeouts = []
        self.goals = []
        self.cancel_count = 0
        self.ready = True

    def wait_for_server(self, timeout: object) -> bool:
        self.timeouts.append(timeout)
        return self.ready

    def send_goal(self, goal: object) -> None:
        self.goals.append(goal)

    def cancel_all_goals(self) -> None:
        self.cancel_count += 1


class RosSkillBridgeTests(unittest.TestCase):
    def test_discrete_commands_map_to_do_action_defaults(self) -> None:
        config = ROSConfig(enabled=True, skill_enabled=True, node_name="robot_test")
        clients: Dict[str, _FakeActionClient] = {}

        def client_factory(topic: str, _: object) -> _FakeActionClient:
            client = _FakeActionClient(topic)
            clients[topic] = client
            return client

        bridge = RosSkillBridge(
            config=config,
            action_client_factory=client_factory,
            goal_factory=_FakeGoal,
            duration_factory=lambda seconds: seconds,
        )
        bridge.start()

        bridge.apply_command(DiscreteCommand(CommandId.STAND))
        bridge.apply_command(DiscreteCommand(CommandId.SIT))
        bridge.apply_command(DiscreteCommand(CommandId.STOP))

        action_client = clients["/agent_skill/do_action/execute"]
        self.assertEqual(len(action_client.goals), 3)

        stand_goal = action_client.goals[0]
        self.assertEqual(json.loads(stand_goal.args), {"action_id": 3})
        self.assertEqual(stand_goal.invoke_priority, 30)

        sit_goal = action_client.goals[1]
        self.assertEqual(json.loads(sit_goal.args), {"action_id": 5})

        stop_goal = action_client.goals[2]
        self.assertEqual(json.loads(stop_goal.args), {"action_id": 6})
        self.assertEqual(stop_goal.invoke_priority, 50)
        self.assertEqual(action_client.cancel_count, 1)

    def test_skill_invoke_commands_route_to_action_and_behavior_clients(self) -> None:
        config = ROSConfig(enabled=True, skill_enabled=True, node_name="robot_test")
        clients: Dict[str, _FakeActionClient] = {}

        def client_factory(topic: str, _: object) -> _FakeActionClient:
            client = _FakeActionClient(topic)
            clients[topic] = client
            return client

        bridge = RosSkillBridge(
            config=config,
            action_client_factory=client_factory,
            goal_factory=_FakeGoal,
            duration_factory=lambda seconds: seconds,
        )
        bridge.start()

        bridge.apply_command(SkillInvokeCommand.do_action(action_id=20524))
        bridge.apply_command(
            SkillInvokeCommand.do_dog_behavior(behavior_id=DogBehavior.WAVE_HAND)
        )

        action_goal = clients["/agent_skill/do_action/execute"].goals[0]
        self.assertEqual(json.loads(action_goal.args), {"action_id": 20524})
        self.assertEqual(action_goal.invoker, "robot_server")

        behavior_goal = clients["/agent_skill/do_dog_behavior/execute"].goals[0]
        self.assertEqual(json.loads(behavior_goal.args), {"behavior": "wave_hand"})
        self.assertEqual(behavior_goal.invoke_priority, 50)


if __name__ == "__main__":
    unittest.main()
