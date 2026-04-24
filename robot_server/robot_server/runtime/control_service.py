from __future__ import annotations

import logging
from collections import defaultdict, deque
from typing import Deque, Dict, Optional, Set, Tuple

from robot_protocol import (
    Frame,
    FrameType,
    MoveCommand,
    SkillInvokeCommand,
    build_ack_frame,
    encode_frame,
    parse_command_payload,
    parse_state_payload,
)

from ..models import ReplyFn
from ..ros.bridge import RosControlBridge
from ..ros.skill_bridge import RosSkillBridge
from .state_store import StateStore

LOGGER = logging.getLogger(__name__)
CommandFingerprint = Tuple[int, bytes]


class RobotControlService:
    def __init__(
        self,
        ros_bridge: RosControlBridge,
        state_store: StateStore,
        ros_skill_bridge: Optional[RosSkillBridge] = None,
        duplicate_window: int = 64,
    ) -> None:
        self._ros_bridge = ros_bridge
        self._ros_skill_bridge = ros_skill_bridge
        self._state_store = state_store
        self._duplicate_window = duplicate_window
        self._recent_commands: Dict[str, Deque[CommandFingerprint]] = defaultdict(deque)
        self._recent_sets: Dict[str, Set[CommandFingerprint]] = defaultdict(set)

    async def handle_frame(self, peer_key: str, frame: Frame, reply: ReplyFn) -> None:
        if frame.frame_type == FrameType.CMD:
            command = parse_command_payload(frame.payload)
            fingerprint = (frame.seq, bytes(frame.payload))
            if self._is_duplicate(peer_key, fingerprint):
                LOGGER.debug(
                    "duplicate cmd ignored peer=%s seq=%d payload_len=%d",
                    peer_key,
                    frame.seq,
                    len(frame.payload),
                )
                await reply(encode_frame(build_ack_frame(frame.seq)))
                return

            if isinstance(command, MoveCommand):
                LOGGER.info(
                    "cmd peer=%s seq=%d type=MOVE vx=%.2f vy=%.2f yaw=%.2f",
                    peer_key,
                    frame.seq,
                    command.vx,
                    command.vy,
                    command.yaw,
                )
                self._ros_bridge.apply_command(command)
            elif isinstance(command, SkillInvokeCommand):
                LOGGER.info(
                    "cmd peer=%s seq=%d type=SKILL_INVOKE service=%s op=%s ack=%s",
                    peer_key,
                    frame.seq,
                    command.service_id.name,
                    command.operation.name,
                    command.require_ack,
                )
                if self._ros_skill_bridge is not None:
                    self._ros_skill_bridge.apply_command(command)
            else:
                LOGGER.info(
                    "cmd peer=%s seq=%d type=%s",
                    peer_key,
                    frame.seq,
                    command.command_id.name,
                )
                self._ros_bridge.apply_command(command)
                if self._ros_skill_bridge is not None:
                    self._ros_skill_bridge.apply_command(command)
            self._state_store.observe_command(command)
            self._remember_command(peer_key, fingerprint)
            await reply(encode_frame(build_ack_frame(frame.seq)))
            return

        if frame.frame_type == FrameType.STATE:
            self._state_store.replace(parse_state_payload(frame.payload))
            return

        if frame.frame_type == FrameType.ACK:
            return

    def _is_duplicate(self, peer_key: str, fingerprint: CommandFingerprint) -> bool:
        seen = self._recent_sets[peer_key]
        return fingerprint in seen

    def _remember_command(self, peer_key: str, fingerprint: CommandFingerprint) -> None:
        window = self._recent_commands[peer_key]
        seen = self._recent_sets[peer_key]
        window.append(fingerprint)
        seen.add(fingerprint)
        if len(window) > self._duplicate_window:
            removed = window.popleft()
            seen.discard(removed)
