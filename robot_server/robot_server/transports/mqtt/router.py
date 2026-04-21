"""MQTT router transport.

Wraps a paho-mqtt client so that :class:`RobotRuntime` can dispatch /
receive binary protocol frames over three topics:

- ``robot/{id}/control`` (binary protocol frames, client -> robot)
- ``robot/{id}/state``   (binary protocol frames, robot -> client, both
  ACK replies and 10Hz STATE broadcasts)
- ``robot/{id}/event``   (JSON payload, robot -> client, coarse events)

The transport intentionally stays thin: it does not decode frames (that
is :class:`RobotRuntime`'s job) and does not enforce auth / TLS
requirements on clients. Auth and TLS are opt-in via ``MQTTConfig`` so
that local development / CI can still connect to an unauthenticated
broker.

Reconnection is delegated to paho-mqtt's built-in exponential retry
(`reconnect_delay_set`) combined with `loop_start`, which keeps the
background thread alive across broker restarts.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, Callable, Dict, Optional

from ...config import MQTTConfig
from ...models import TransportEnvelope
from ..base import EnvelopeHandler, RuntimeTransport

try:
    import paho.mqtt.client as mqtt
except ImportError:  # pragma: no cover - optional dependency at runtime
    mqtt = None  # type: ignore[assignment]


_logger = logging.getLogger(__name__)


MqttClientFactory = Callable[[MQTTConfig], Any]


def _default_client_factory(config: MQTTConfig) -> Any:
    if mqtt is None:
        raise RuntimeError("paho-mqtt is required to enable MQTT transport")

    try:
        return mqtt.Client(
            client_id=config.client_id,
            protocol=mqtt.MQTTv311,
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
        )
    except AttributeError:
        # paho-mqtt < 2.0 fallback (no callback_api_version kwarg).
        return mqtt.Client(client_id=config.client_id, protocol=mqtt.MQTTv311)


class MqttRouterTransport(RuntimeTransport):
    name = "mqtt"

    def __init__(
        self,
        config: MQTTConfig,
        *,
        client_factory: Optional[MqttClientFactory] = None,
    ) -> None:
        self._config = config
        self._factory = client_factory or _default_client_factory
        self._client: Optional[Any] = None
        self._handler: Optional[EnvelopeHandler] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._session_id = f"router:{config.robot_id}"

    @property
    def config(self) -> MQTTConfig:
        return self._config

    async def start(self, handler: EnvelopeHandler) -> None:
        if not self._config.enabled:
            return

        self._handler = handler
        self._loop = asyncio.get_running_loop()

        client = self._factory(self._config)
        if self._config.username is not None:
            client.username_pw_set(self._config.username, self._config.password)
        if self._config.tls:
            client.tls_set()
        client.reconnect_delay_set(
            min_delay=max(1, int(self._config.reconnect_min_delay)),
            max_delay=max(1, int(self._config.reconnect_max_delay)),
        )
        client.on_connect = self._on_connect
        client.on_disconnect = self._on_disconnect
        client.on_message = self._on_message
        client.connect(self._config.host, self._config.port, self._config.keepalive)
        client.loop_start()
        self._client = client
        _logger.info(
            "MQTT transport started host=%s:%s client_id=%s robot_id=%s",
            self._config.host,
            self._config.port,
            self._config.client_id,
            self._config.robot_id,
        )

    async def stop(self) -> None:
        client = self._client
        if client is None:
            return
        try:
            client.loop_stop()
        except Exception:  # pragma: no cover - best-effort shutdown
            _logger.debug("MQTT loop_stop raised", exc_info=True)
        try:
            client.disconnect()
        except Exception:  # pragma: no cover - best-effort shutdown
            _logger.debug("MQTT disconnect raised", exc_info=True)
        self._client = None
        _logger.info("MQTT transport stopped robot_id=%s", self._config.robot_id)

    async def send(self, session_id: str, payload: bytes) -> None:
        # MQTT is a shared channel; per-session send is treated as a
        # state-topic publish so ACK frames coming from RobotRuntime.reply
        # are broadcast alongside the 10Hz STATE loop (matches BLE/TCP
        # where ACK and STATE share the robot -> client direction).
        await self._publish_state(payload)

    async def broadcast(self, payload: bytes) -> None:
        await self._publish_state(payload)

    async def publish_event(self, event: Dict[str, Any]) -> None:
        client = self._client
        if client is None:
            return
        try:
            encoded = json.dumps(event, ensure_ascii=False).encode("utf-8")
        except (TypeError, ValueError) as exc:
            _logger.error("MQTT event payload is not JSON-serializable: %s", exc)
            return
        client.publish(self._config.event_topic, encoded, qos=self._config.qos)

    async def _publish_state(self, payload: bytes) -> None:
        client = self._client
        if client is None:
            return
        client.publish(self._config.state_topic, payload, qos=self._config.qos)

    # ------------------------------------------------------------------ callbacks

    def _on_connect(
        self,
        client: Any,
        userdata: object,
        flags: object,
        reason_code: Any,
        properties: object = None,
    ) -> None:
        code = int(reason_code) if reason_code is not None else 0
        if code == 0:
            client.subscribe(self._config.control_topic, qos=self._config.qos)
            _logger.info(
                "MQTT connected, subscribed to %s", self._config.control_topic
            )
        else:
            _logger.warning("MQTT connect failed reason_code=%s", reason_code)

    def _on_disconnect(
        self,
        client: Any,
        userdata: object,
        *args: Any,
        **kwargs: Any,
    ) -> None:
        reason = args[-1] if args else kwargs.get("reason_code")
        _logger.warning("MQTT disconnected reason=%s, auto-reconnect scheduled", reason)

    def _on_message(self, client: Any, userdata: object, message: Any) -> None:
        if message.topic != self._config.control_topic:
            return
        handler = self._handler
        loop = self._loop
        if handler is None or loop is None:
            return

        async def reply(payload: bytes) -> None:
            await self._publish_state(payload)

        envelope = TransportEnvelope(
            transport_name=self.name,
            session_id=self._session_id,
            payload=bytes(message.payload),
            reply=reply,
        )
        asyncio.run_coroutine_threadsafe(handler(envelope), loop)
