from __future__ import annotations

import asyncio
import json
import unittest
from typing import Any, List, Tuple

from robot_server.config import MQTTConfig
from robot_server.models import TransportEnvelope
from robot_server.transports.mqtt import MqttRouterTransport


class _Message:
    def __init__(self, topic: str, payload: bytes) -> None:
        self.topic = topic
        self.payload = payload


class _FakeMqttClient:
    """Test double emulating the subset of paho-mqtt we rely on."""

    def __init__(self, config: MQTTConfig) -> None:
        self.config = config
        self.connect_calls: List[Tuple[str, int, int]] = []
        self.publishes: List[Tuple[str, bytes, int]] = []
        self.subscribes: List[Tuple[str, int]] = []
        self.loop_started = False
        self.loop_stopped = False
        self.disconnected = False
        self.username: Any = None
        self.password: Any = None
        self.tls_enabled = False
        self.reconnect_delay: Tuple[int, int] = (0, 0)
        self.on_connect = None
        self.on_disconnect = None
        self.on_message = None

    def username_pw_set(self, username: Any, password: Any = None) -> None:
        self.username = username
        self.password = password

    def tls_set(self) -> None:
        self.tls_enabled = True

    def reconnect_delay_set(self, min_delay: int, max_delay: int) -> None:
        self.reconnect_delay = (min_delay, max_delay)

    def connect(self, host: str, port: int, keepalive: int) -> None:
        self.connect_calls.append((host, port, keepalive))

    def loop_start(self) -> None:
        self.loop_started = True

    def loop_stop(self) -> None:
        self.loop_stopped = True

    def disconnect(self) -> None:
        self.disconnected = True

    def subscribe(self, topic: str, qos: int = 0) -> None:
        self.subscribes.append((topic, qos))

    def publish(self, topic: str, payload: bytes, qos: int = 0) -> None:
        self.publishes.append((topic, payload, qos))

    def trigger_connect(self, reason_code: int = 0) -> None:
        assert self.on_connect is not None
        self.on_connect(self, None, {}, reason_code, None)

    def emit_message(self, topic: str, payload: bytes) -> None:
        assert self.on_message is not None
        self.on_message(self, None, _Message(topic, payload))


class MQTTConfigValidationTests(unittest.TestCase):
    def test_rejects_wildcard_robot_id(self) -> None:
        for bad in ("", "+bad", "ro/bot", "ro#bot"):
            with self.subTest(robot_id=bad):
                with self.assertRaises(ValueError):
                    MQTTConfig(robot_id=bad)

    def test_default_client_id_and_topics(self) -> None:
        cfg = MQTTConfig(robot_id="dog-42")
        self.assertEqual(cfg.client_id, "robot-server-dog-42")
        self.assertEqual(cfg.control_topic, "robot/dog-42/control")
        self.assertEqual(cfg.state_topic, "robot/dog-42/state")
        self.assertEqual(cfg.event_topic, "robot/dog-42/event")

    def test_invalid_qos_raises(self) -> None:
        with self.assertRaises(ValueError):
            MQTTConfig(qos=3)


class MqttRouterTransportTests(unittest.IsolatedAsyncioTestCase):
    def _make_router(self, **overrides: Any) -> Tuple[MqttRouterTransport, _FakeMqttClient]:
        config = MQTTConfig(enabled=True, robot_id="dog-1", qos=1, **overrides)
        client = _FakeMqttClient(config)

        def factory(_: MQTTConfig) -> _FakeMqttClient:
            return client

        router = MqttRouterTransport(config, client_factory=factory)
        return router, client

    async def test_start_subscribes_control_and_dispatches_binary_frames(self) -> None:
        router, client = self._make_router()
        received: List[TransportEnvelope] = []
        dispatched = asyncio.Event()

        async def handler(envelope: TransportEnvelope) -> None:
            received.append(envelope)
            await envelope.reply(b"ack-bytes")
            dispatched.set()

        await router.start(handler)
        self.assertEqual(client.connect_calls, [("127.0.0.1", 1883, 60)])
        self.assertTrue(client.loop_started)

        client.trigger_connect(reason_code=0)
        self.assertEqual(client.subscribes, [("robot/dog-1/control", 1)])

        client.emit_message("robot/dog-1/control", b"\xAA\x55binary")
        await asyncio.wait_for(dispatched.wait(), timeout=1.0)

        self.assertEqual(len(received), 1)
        env = received[0]
        self.assertEqual(env.transport_name, "mqtt")
        self.assertEqual(env.payload, b"\xAA\x55binary")
        self.assertEqual(env.peer_key, "mqtt:router:dog-1")

        # reply() inside handler publishes ACK bytes to the state topic.
        self.assertIn(("robot/dog-1/state", b"ack-bytes", 1), client.publishes)

        await router.stop()
        self.assertTrue(client.loop_stopped)
        self.assertTrue(client.disconnected)

    async def test_messages_on_foreign_topic_are_ignored(self) -> None:
        router, client = self._make_router()
        calls: List[TransportEnvelope] = []

        async def handler(envelope: TransportEnvelope) -> None:
            calls.append(envelope)

        await router.start(handler)
        client.trigger_connect()
        try:
            client.emit_message("robot/other/control", b"payload")
            client.emit_message("robot/dog-1/state", b"not-a-command")
            await asyncio.sleep(0)
            self.assertEqual(calls, [])
        finally:
            await router.stop()

    async def test_broadcast_and_publish_event_use_correct_topics(self) -> None:
        router, client = self._make_router()

        async def handler(_: TransportEnvelope) -> None:
            pass

        await router.start(handler)
        try:
            await router.broadcast(b"state-bytes")
            await router.send("ignored-session", b"ack-bytes")
            await router.publish_event({"type": "battery_low", "level": 15})

            topics = [item[0] for item in client.publishes]
            self.assertEqual(
                topics,
                [
                    "robot/dog-1/state",
                    "robot/dog-1/state",
                    "robot/dog-1/event",
                ],
            )
            event_payload = client.publishes[-1][1]
            self.assertEqual(
                json.loads(event_payload.decode("utf-8")),
                {"type": "battery_low", "level": 15},
            )
        finally:
            await router.stop()

    async def test_publish_event_skips_non_serializable(self) -> None:
        router, client = self._make_router()

        await router.start(lambda _envelope: asyncio.sleep(0))
        try:
            # A lambda is not JSON-serializable; publish_event must swallow it.
            await router.publish_event({"type": "bad", "fn": lambda: None})  # type: ignore[dict-item]
            self.assertEqual(client.publishes, [])
        finally:
            await router.stop()

    async def test_disabled_config_is_noop(self) -> None:
        called: List[MQTTConfig] = []

        def factory(cfg: MQTTConfig) -> _FakeMqttClient:
            called.append(cfg)
            return _FakeMqttClient(cfg)

        router = MqttRouterTransport(MQTTConfig(enabled=False), client_factory=factory)
        await router.start(lambda _envelope: asyncio.sleep(0))
        await router.stop()
        self.assertEqual(called, [])

    async def test_auth_and_tls_applied(self) -> None:
        router, client = self._make_router(
            username="robot",
            password="secret",
            tls=True,
            keepalive=45,
            reconnect_min_delay=2.0,
            reconnect_max_delay=20.0,
        )
        await router.start(lambda _envelope: asyncio.sleep(0))
        try:
            self.assertEqual(client.username, "robot")
            self.assertEqual(client.password, "secret")
            self.assertTrue(client.tls_enabled)
            self.assertEqual(client.reconnect_delay, (2, 20))
            self.assertEqual(client.connect_calls[0][2], 45)
        finally:
            await router.stop()


if __name__ == "__main__":
    unittest.main()
