from __future__ import annotations

import logging
from collections import defaultdict, deque
from typing import Deque, Dict, Set

from robot_protocol import (
    Frame,
    FrameType,
    MoveCommand,
    build_ack_frame,
    encode_frame,
    parse_command_payload,
    parse_state_payload,
)

from ..models import ReplyFn
from ..ros.bridge import RosControlBridge
from .state_store import StateStore

LOGGER = logging.getLogger(__name__)


class RobotControlService:
    def __init__(
        self,
        ros_bridge: RosControlBridge,
        state_store: StateStore,
        duplicate_window: int = 64,
    ) -> None:
        self._ros_bridge = ros_bridge
        self._state_store = state_store
        self._duplicate_window = duplicate_window
        self._recent_sequences: Dict[str, Deque[int]] = defaultdict(deque)
        self._recent_sets: Dict[str, Set[int]] = defaultdict(set)

    async def handle_frame(self, peer_key: str, frame: Frame, reply: ReplyFn) -> None:
        if frame.frame_type == FrameType.CMD:
            await reply(encode_frame(build_ack_frame(frame.seq)))
            if self._is_duplicate(peer_key, frame.seq):
                LOGGER.debug("duplicate cmd ignored peer=%s seq=%d", peer_key, frame.seq)
                return

            command = parse_command_payload(frame.payload)
            if isinstance(command, MoveCommand):
                LOGGER.info(
                    "cmd peer=%s seq=%d type=MOVE vx=%.2f vy=%.2f yaw=%.2f",
                    peer_key,
                    frame.seq,
                    command.vx,
                    command.vy,
                    command.yaw,
                )
            else:
                LOGGER.info(
                    "cmd peer=%s seq=%d type=%s",
                    peer_key,
                    frame.seq,
                    command.command_id.name,
                )
            self._ros_bridge.apply_command(command)
            self._state_store.observe_command(command)
            return

        if frame.frame_type == FrameType.STATE:
            self._state_store.replace(parse_state_payload(frame.payload))
            return

        if frame.frame_type == FrameType.ACK:
            return

    def _is_duplicate(self, peer_key: str, seq: int) -> bool:
        seen = self._recent_sets[peer_key]
        if seq in seen:
            return True

        window = self._recent_sequences[peer_key]
        window.append(seq)
        seen.add(seq)
        if len(window) > self._duplicate_window:
            removed = window.popleft()
            seen.discard(removed)
        return False
