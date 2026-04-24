from __future__ import annotations

import json
import logging
from typing import Any, Callable, Dict, Optional, Union

from robot_protocol import (
    CommandId,
    DiscreteCommand,
    DogBehavior,
    Operation,
    ServiceId,
    SkillInvokeCommand,
)

from ..config import ROSConfig

try:
    import actionlib
    import rospy
    from agent_msgs.msg import ExecuteAction, ExecuteGoal
except ImportError:  # pragma: no cover - runtime dependency on target robot
    actionlib = None
    rospy = None
    ExecuteAction = None
    ExecuteGoal = None


LOGGER = logging.getLogger(__name__)

_DOG_BEHAVIOR_NAMES = {
    DogBehavior.CONFUSED: "confused",
    DogBehavior.CONFUSED_AGAIN: "confused_again",
    DogBehavior.RECOVERY_BALANCE_STAND_1: "recovery_balance_stand_1",
    DogBehavior.RECOVERY_BALANCE_STAND: "recovery_balance_stand",
    DogBehavior.RECOVERY_BALANCE_STAND_HIGH: "recovery_balance_stand_high",
    DogBehavior.FORCE_RECOVERY_BALANCE_STAND: "force_recovery_balance_stand",
    DogBehavior.FORCE_RECOVERY_BALANCE_STAND_HIGH: "force_recovery_balance_stand_high",
    DogBehavior.RECOVERY_DANCE_STAND_AND_PARAMS: "recovery_dance_stand_and_params",
    DogBehavior.RECOVERY_DANCE_STAND: "recovery_dance_stand",
    DogBehavior.RECOVERY_DANCE_STAND_HIGH: "recovery_dance_stand_high",
    DogBehavior.RECOVERY_DANCE_STAND_HIGH_AND_PARAMS: "recovery_dance_stand_high_and_params",
    DogBehavior.RECOVERY_DANCE_STAND_POSE: "recovery_dance_stand_pose",
    DogBehavior.RECOVERY_DANCE_STAND_HIGH_POSE: "recovery_dance_stand_high_pose",
    DogBehavior.RECOVERY_STAND_POSE: "recovery_stand_pose",
    DogBehavior.RECOVERY_STAND_HIGH_POSE: "recovery_stand_high_pose",
    DogBehavior.WAIT: "wait",
    DogBehavior.CUTE: "cute",
    DogBehavior.CUTE_2: "cute_2",
    DogBehavior.ENJOY_TOUCH: "enjoy_touch",
    DogBehavior.VERY_ENJOY: "very_enjoy",
    DogBehavior.EAGER: "eager",
    DogBehavior.EXCITED_2: "excited_2",
    DogBehavior.EXCITED: "excited",
    DogBehavior.CRAWL: "crawl",
    DogBehavior.STAND_AT_EASE: "stand_at_ease",
    DogBehavior.REST: "rest",
    DogBehavior.SHAKE_SELF: "shake_self",
    DogBehavior.BACK_FLIP: "back_flip",
    DogBehavior.FRONT_FLIP: "front_flip",
    DogBehavior.LEFT_FLIP: "left_flip",
    DogBehavior.RIGHT_FLIP: "right_flip",
    DogBehavior.EXPRESS_AFFECTION: "express_affection",
    DogBehavior.YAWN: "yawn",
    DogBehavior.DANCE_IN_PLACE: "dance_in_place",
    DogBehavior.SHAKE_HAND: "shake_hand",
    DogBehavior.WAVE_HAND: "wave_hand",
    DogBehavior.DRAW_HEART: "draw_heart",
    DogBehavior.PUSH_UP: "push_up",
    DogBehavior.BOW: "bow",
}

ActionClient = Any
ActionClientFactory = Callable[[str, Any], ActionClient]
GoalFactory = Callable[[], Any]
DurationFactory = Callable[[float], Any]


class RosSkillBridge:
    def __init__(
        self,
        config: ROSConfig,
        action_client_factory: Optional[ActionClientFactory] = None,
        goal_factory: Optional[GoalFactory] = None,
        duration_factory: Optional[DurationFactory] = None,
    ) -> None:
        self._config = config
        self._action_client_factory = action_client_factory
        self._goal_factory = goal_factory
        self._duration_factory = duration_factory
        self._action_client: Optional[ActionClient] = None
        self._behavior_client: Optional[ActionClient] = None

    def start(self) -> None:
        if not self._config.enabled or not self._config.skill_enabled:
            return
        if (
            self._action_client_factory is None
            and (actionlib is None or ExecuteAction is None)
        ):
            raise RuntimeError("ROS skill bridge requires actionlib and agent_msgs")
        if self._goal_factory is None and ExecuteGoal is None:
            raise RuntimeError("ROS skill bridge requires agent_msgs ExecuteGoal")

        if rospy is not None and not rospy.core.is_initialized():
            rospy.init_node(self._config.node_name, anonymous=True, disable_signals=True)

        self._action_client = self._create_client(self._execute_topic(self._config.action_skill_name))
        self._behavior_client = self._create_client(
            self._execute_topic(self._config.behavior_skill_name)
        )

    def stop(self) -> None:
        for client in (self._action_client, self._behavior_client):
            if client is None:
                continue
            cancel_all = getattr(client, "cancel_all_goals", None)
            if cancel_all is not None:
                cancel_all()
        self._action_client = None
        self._behavior_client = None

    def apply_command(
        self,
        command: Union[DiscreteCommand, SkillInvokeCommand],
    ) -> None:
        if not self._config.enabled or not self._config.skill_enabled:
            return

        if isinstance(command, DiscreteCommand):
            if command.command_id == CommandId.STAND:
                self._send_action(
                    action_id=self._config.stand_action_id,
                    priority=self._config.action_priority,
                    hold_time=self._config.action_hold_time_sec,
                )
                return
            if command.command_id == CommandId.SIT:
                self._send_action(
                    action_id=self._config.sit_action_id,
                    priority=self._config.action_priority,
                    hold_time=self._config.action_hold_time_sec,
                )
                return
            if command.command_id == CommandId.STOP:
                self.cancel_all()
                self._send_action(
                    action_id=self._config.stop_action_id,
                    priority=self._config.stop_priority,
                    hold_time=self._config.stop_hold_time_sec,
                )
                return
            return

        if command.service_id == ServiceId.DO_ACTION and command.operation == Operation.EXECUTE:
            self._send_action(
                action_id=command.action_id,
                priority=self._config.action_priority,
                hold_time=self._config.action_hold_time_sec,
            )
            return

        if command.service_id == ServiceId.DO_DOG_BEHAVIOR and command.operation == Operation.EXECUTE:
            self._send_behavior(
                behavior_id=command.behavior_id,
                priority=self._config.behavior_priority,
                hold_time=self._config.behavior_hold_time_sec,
            )
            return

        raise ValueError(
            "unsupported skill invoke command service=%s op=%s"
            % (command.service_id.name, command.operation.name)
        )

    def cancel_all(self) -> None:
        for client in (self._action_client, self._behavior_client):
            if client is None:
                continue
            cancel_all = getattr(client, "cancel_all_goals", None)
            if cancel_all is not None:
                cancel_all()

    def _send_action(self, action_id: int, priority: int, hold_time: float) -> None:
        LOGGER.info(
            "ros skill do_action action_id=%d priority=%d hold=%.2f",
            action_id,
            priority,
            hold_time,
        )
        client = self._require_client(self._action_client, self._config.action_skill_name)
        client.send_goal(self._make_goal({"action_id": action_id}, priority, hold_time))

    def _send_behavior(
        self,
        behavior_id: DogBehavior,
        priority: int,
        hold_time: float,
    ) -> None:
        behavior_name = _DOG_BEHAVIOR_NAMES[behavior_id]
        LOGGER.info(
            "ros skill do_dog_behavior behavior=%s priority=%d hold=%.2f",
            behavior_name,
            priority,
            hold_time,
        )
        client = self._require_client(
            self._behavior_client,
            self._config.behavior_skill_name,
        )
        client.send_goal(self._make_goal({"behavior": behavior_name}, priority, hold_time))

    def _make_goal(self, args_obj: Dict[str, Any], priority: int, hold_time: float) -> Any:
        goal_factory = self._goal_factory or ExecuteGoal
        goal = goal_factory()
        goal.invoker = self._config.skill_invoker
        goal.invoke_priority = int(priority)
        goal.hold_time = float(hold_time)
        goal.args = json.dumps(args_obj, separators=(",", ":"), ensure_ascii=False)
        return goal

    def _create_client(self, topic: str) -> ActionClient:
        client_factory = self._action_client_factory or actionlib.SimpleActionClient
        action_type = ExecuteAction if ExecuteAction is not None else object
        client = client_factory(topic, action_type)
        duration_factory = self._duration_factory or self._default_duration
        if not client.wait_for_server(timeout=duration_factory(self._config.skill_server_wait_sec)):
            raise RuntimeError("ROS action server not ready: %s" % topic)
        return client

    def _require_client(self, client: Optional[ActionClient], skill_name: str) -> ActionClient:
        if client is None:
            raise RuntimeError("ROS skill client not started: %s" % skill_name)
        return client

    def _default_duration(self, seconds: float) -> Any:
        assert rospy is not None
        return rospy.Duration(seconds)

    def _execute_topic(self, skill_name: str) -> str:
        return "/agent_skill/%s/execute" % skill_name
