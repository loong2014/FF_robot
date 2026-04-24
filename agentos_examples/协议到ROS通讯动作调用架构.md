# 协议到 ROS 通讯动作调用架构（面向 Cursor 自动化编程）

> 输入依据：  
> - `agentos_examples/protocol_format.md`（二进制协议）  
> - `agentos_examples/动作执行记录.md`（实测调用）  
> - `agentos_examples/AlphaDog_功能清单.md`（技能与动作清单）  
> - `agentos_examples/python/*.py`（调用示例）

---

## 1. 目标与边界

本文档定义一条统一链路：

**协议帧（TCP/BLE/MQTT） -> 网关解析 -> ROS Skill 调用 -> Result/State 回传 -> 协议回包**

用于指导后续 Cursor 自动生成：
- 协议解析器（Frame 解码/编码）
- 命令路由器（CMD 到 do_action/do_dog_behavior/set_motion_params）
- ROS 客户端调用层（Python actionlib + service）
- 错误映射与重试控制

---

## 2. 总体架构

```text
App/上位机
   |
   | 二进制帧 (0xAA55 | Type | Seq | Len | Payload | CRC16)
   v
Protocol Gateway (Python)
   ├─ StreamDecoder: 粘包/半包/CRC恢复
   ├─ CommandRouter: cmd_id -> ROS Skill
   ├─ SkillInvoker: actionlib/service 封装
   ├─ StateBridge: ROS 状态 -> STATE 帧
   └─ AckManager: CMD -> ACK(seq)
   |
   v
ROS (agent_skill/*, alphadog_node/*)
```

---

## 3. 协议层与 ROS 层映射

## 3.1 CMD 映射策略

`protocol_format.md` 当前 CMD 仅定义：
- `MOVE` (`cmd_id=0x01`)
- 离散：`stand(0x10)`, `sit(0x11)`, `stop(0x12)`

推荐映射：

| 协议 CMD | ROS 调用 | 说明 |
|---|---|---|
| `MOVE(0x01)` | 优先 `set_motion_params` 或 `set_velocity` topic | 连续速度控制 |
| `stand(0x10)` | `do_action` `action_id=3` 或 `4` | 建议统一为恢复站立 |
| `sit(0x11)` | `do_action` `action_id=5` | 坐下 |
| `stop(0x12)` | 取消当前 goal + `action_id=6`（soft stop） | 安全停止 |

> 注意：当前实测里“前进”常通过扩展动作 `20524 step_forward`，不建议简单等价成固定速度流控。  
> 若走 `MOVE`，应允许固件侧根据模式转换。

## 3.2 扩展建议（为了 Scratch/业务动作）

建议在协议层新增业务命令族（保持向后兼容）：
- `CMD_SKILL_ACTION`：传 `action_id`
- `CMD_SKILL_BEHAVIOR`：传 `behavior_name`
- `CMD_SKILL_CONTROL`：pause/resume/cancel

这样可直接覆盖 `do_action` / `do_dog_behavior`，避免把复杂动作塞进 `MOVE`。

---

## 4. do_action 与 do_dog_behavior 的路由决策

## 4.1 默认规则

1. **能用 behavior 就用 behavior**（稳定）
2. 需要底层精控或 behavior 未覆盖时用 action

## 4.2 推荐白名单（来自实测经验）

- 空翻类：优先 `do_dog_behavior`（如 `back_flip`），不要直接 `do_action 260`
- 编排动作（画爱心/挥手/鞠躬）：优先 behavior
- 原子扩展动作（如 `20524 step_forward`）：可直接 `do_action`

---

## 5. Python 实现分层（建议 Cursor 生成目录）

```text
agentos_examples/python_gateway/
  protocol/
    frame_codec.py          # 编解码 + CRC16
    stream_decoder.py       # 粘包/半包恢复
  ros/
    skill_client.py         # execute/control/hold/release 统一封装
    state_subscriber.py     # battery/imu/wifi/result
  app/
    command_router.py       # cmd_id -> ros call
    error_mapper.py         # ros result -> ack/error code
    main_gateway.py         # 入口
```

---

## 6. Skill 调用约定（统一接口）

## 6.1 Execute

- Action: `/agent_skill/do_action/execute`
- Behavior: `/agent_skill/do_dog_behavior/execute`

请求统一字段：
- `invoker`（建议固定网关标识）
- `invoke_priority`（默认 30，关键动作 50）
- `hold_time`（默认 10s）
- `args`（json 字符串）

## 6.2 Control/Hold

- Control Action：`/agent_skill/<name>/control`
- Hold Service：`/agent_skill/<name>/hold`
- Release Hold：`/agent_skill/<name>/release_hold`

用于暂停/恢复/互斥抢占管理。

---

## 7. 状态与 ACK 回传设计

## 7.1 ACK 回传

- 收到并受理 `CMD` 后立即回 `ACK(seq)`（协议层）
- 业务成功/失败不要混在 ACK，走 `STATE` 扩展字段或 `event`（MQTT JSON）

## 7.2 STATE 回传

建议最小集：
- battery（`/alphadog_aux/battery_state`）
- roll/pitch/yaw（`/alphadog_node/imu`）
- last_action_result（从 `execute/result` 聚合）

> 当前 `protocol_format.md` 里 `STATE` 固定 7 字节，可先保留；  
> 业务细节建议走 `robot/{id}/event` JSON。

---

## 8. 错误处理与重试策略

## 8.1 协议层

- CRC 错误：丢 1 字节继续找帧头
- Len 非法（>512）：丢 1 字节恢复
- ACK 超时（默认 100ms）：重发最多 3 次

## 8.2 ROS 层

- `status=3 && result=1` 视为成功
- `status=4/result=3`：失败，透传 `text`
- 空翻类冷却/前置姿态失败：不盲目重试，先执行恢复动作

---

## 9. Cursor 自动化生成规范（关键）

后续让 Cursor 生成代码时，建议固定以下规则：

1. **先生成分层骨架，再填业务逻辑**（协议/ROS/路由分离）
2. **所有 skill 调用走统一 `SkillClient`**，禁止散落调用
3. **每个 cmd_id 必须有显式映射和默认兜底错误**
4. **日志必须带 `seq`, `cmd_id`, `skill`, `status`, `result`**
5. **单元测试至少覆盖**：
   - 粘包/半包/CRC坏包恢复
   - cmd 路由正确性
   - result 映射
6. **实机测试脚本复用现有**：
   - `scripts/dog_cmd.sh`
   - `scripts/probe_actions.sh`
   - `scripts/probe_behaviors.sh`

---

## 10. 全量 Demo 代码（自包含，不依赖外部文件引用）

下面给出一个“可直接落地改造”的单文件网关示例，包含：
- CRC16 + 帧编解码
- 粘包/半包流解码
- CMD 路由（MOVE/STAND/SIT/STOP）
- ROS skill 调用（do_action / do_dog_behavior）
- ACK 回包

> 运行前提：ROS Noetic 环境、`agent_msgs` 可用、`rospy` + `actionlib` 可导入。

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import socket
import struct
import threading
import time
from dataclasses import dataclass
from typing import List, Tuple, Optional

import rospy
import actionlib
from agent_msgs.msg import ExecuteAction, ExecuteGoal


# =========================
# 1) 协议常量与CRC
# =========================
MAGIC = b"\xAA\x55"
TYPE_CMD = 0x01
TYPE_STATE = 0x02
TYPE_ACK = 0x03

CMD_MOVE = 0x01
CMD_STAND = 0x10
CMD_SIT = 0x11
CMD_STOP = 0x12

MAX_PAYLOAD = 512


def crc16_ccitt(data: bytes, init: int = 0xFFFF, poly: int = 0x1021) -> int:
    crc = init
    for b in data:
        crc ^= (b << 8)
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ poly) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc & 0xFFFF


# =========================
# 2) 帧编解码
# =========================
@dataclass
class Frame:
    ftype: int
    seq: int
    payload: bytes


def encode_frame(ftype: int, seq: int, payload: bytes) -> bytes:
    if len(payload) > MAX_PAYLOAD:
        raise ValueError(f"payload too long: {len(payload)}")
    header = MAGIC + bytes([ftype & 0xFF, seq & 0xFF]) + struct.pack("<H", len(payload))
    crc_input = header[2:] + payload  # Type + Seq + Len + Payload
    crc = crc16_ccitt(crc_input)
    return header + payload + struct.pack("<H", crc)


def decode_one_frame(buf: bytes) -> Tuple[Optional[Frame], int]:
    """
    返回 (frame_or_none, consumed_bytes)
    - frame_or_none 为 None 且 consumed=0 表示需要更多字节
    - frame_or_none 为 None 且 consumed>0 表示丢弃 consumed 字节继续找帧
    """
    if len(buf) < 8:  # 最短帧 8 字节
        return None, 0

    idx = buf.find(MAGIC)
    if idx < 0:
        return None, len(buf)  # 全丢
    if idx > 0:
        return None, idx       # 丢弃头前垃圾

    # idx==0, 解析头
    if len(buf) < 6:
        return None, 0
    ftype = buf[2]
    seq = buf[3]
    payload_len = struct.unpack("<H", buf[4:6])[0]

    if payload_len > MAX_PAYLOAD:
        return None, 1  # 非法长度，右移1字节重找

    frame_len = 8 + payload_len
    if len(buf) < frame_len:
        return None, 0

    payload = buf[6:6 + payload_len]
    crc_recv = struct.unpack("<H", buf[6 + payload_len: 8 + payload_len])[0]
    crc_calc = crc16_ccitt(buf[2:6 + payload_len])
    if crc_recv != crc_calc:
        return None, 1  # CRC 错，右移1字节重找

    return Frame(ftype=ftype, seq=seq, payload=payload), frame_len


class StreamDecoder:
    def __init__(self):
        self._buf = bytearray()

    def feed(self, chunk: bytes) -> List[Frame]:
        self._buf.extend(chunk)
        out: List[Frame] = []
        while True:
            frame, consumed = decode_one_frame(bytes(self._buf))
            if frame is None:
                if consumed == 0:
                    break
                del self._buf[:consumed]
                continue
            out.append(frame)
            del self._buf[:consumed]
        return out


# =========================
# 3) ROS Skill 调用封装
# =========================
class SkillClient:
    def __init__(self):
        self.cli_action = actionlib.SimpleActionClient("/agent_skill/do_action/execute", ExecuteAction)
        self.cli_behavior = actionlib.SimpleActionClient("/agent_skill/do_dog_behavior/execute", ExecuteAction)

        rospy.loginfo("Waiting for do_action server...")
        if not self.cli_action.wait_for_server(timeout=rospy.Duration(3.0)):
            raise RuntimeError("do_action action server not ready")
        rospy.loginfo("Waiting for do_dog_behavior server...")
        if not self.cli_behavior.wait_for_server(timeout=rospy.Duration(3.0)):
            raise RuntimeError("do_dog_behavior action server not ready")

    @staticmethod
    def _make_goal(args_obj: dict, invoker="gateway", priority=30, hold_time=10.0) -> ExecuteGoal:
        g = ExecuteGoal()
        g.invoker = invoker
        g.invoke_priority = int(priority)
        g.hold_time = float(hold_time)
        g.args = json.dumps(args_obj, ensure_ascii=False)
        return g

    def do_action(self, action_id: int, priority=30, hold_time=10.0, timeout_sec=20.0):
        goal = self._make_goal({"action_id": int(action_id)}, priority=priority, hold_time=hold_time)
        self.cli_action.send_goal(goal)
        if not self.cli_action.wait_for_result(timeout=rospy.Duration(timeout_sec)):
            return False, "TIMEOUT"
        res = self.cli_action.get_result()
        ok = getattr(res, "result", 3) == 1
        return ok, getattr(res, "response", "")

    def do_behavior(self, behavior: str, priority=30, hold_time=10.0, timeout_sec=20.0):
        goal = self._make_goal({"behavior": behavior}, priority=priority, hold_time=hold_time)
        self.cli_behavior.send_goal(goal)
        if not self.cli_behavior.wait_for_result(timeout=rospy.Duration(timeout_sec)):
            return False, "TIMEOUT"
        res = self.cli_behavior.get_result()
        ok = getattr(res, "result", 3) == 1
        return ok, getattr(res, "response", "")

    def cancel_all(self):
        self.cli_action.cancel_all_goals()
        self.cli_behavior.cancel_all_goals()


# =========================
# 4) 协议 CMD 路由
# =========================
class CommandRouter:
    def __init__(self, skill_client: SkillClient):
        self.skill = skill_client

    @staticmethod
    def _decode_move(payload: bytes) -> Tuple[float, float, float]:
        # payload: cmd_id(1) + vx(int16) + vy(int16) + yaw(int16)
        if len(payload) != 7:
            raise ValueError(f"invalid MOVE payload len={len(payload)}")
        _, vx_i, vy_i, yaw_i = struct.unpack("<Bhhh", payload)
        return vx_i / 100.0, vy_i / 100.0, yaw_i / 100.0

    def route_cmd(self, payload: bytes) -> Tuple[bool, str]:
        if not payload:
            return False, "EMPTY_CMD"
        cmd_id = payload[0]

        if cmd_id == CMD_MOVE:
            # MVP 简化策略：vx>0 用 step_forward，vx<0 用 step_back，yaw 先忽略
            vx, vy, yaw = self._decode_move(payload)
            rospy.loginfo(f"[MOVE] vx={vx:.2f}, vy={vy:.2f}, yaw={yaw:.2f}")
            if vx > 0.05:
                return self.skill.do_action(20524, priority=30, hold_time=5.0)  # step_forward
            if vx < -0.05:
                return self.skill.do_action(20528, priority=30, hold_time=5.0)  # step_back
            # 速度接近0，视为停止
            self.skill.cancel_all()
            return self.skill.do_action(6, priority=50, hold_time=2.0)         # soft stop

        if cmd_id == CMD_STAND:
            return self.skill.do_action(3, priority=30, hold_time=5.0)         # recovery stand

        if cmd_id == CMD_SIT:
            return self.skill.do_action(5, priority=30, hold_time=5.0)         # sit down

        if cmd_id == CMD_STOP:
            self.skill.cancel_all()
            return self.skill.do_action(6, priority=50, hold_time=2.0)         # soft stop

        return False, f"UNSUPPORTED_CMD:{cmd_id}"


# =========================
# 5) 网关主循环（TCP 示例）
# =========================
class GatewayServer:
    def __init__(self, host="0.0.0.0", port=19090):
        self.host = host
        self.port = port
        self.decoder = StreamDecoder()
        self.skill_client = SkillClient()
        self.router = CommandRouter(self.skill_client)

    def _handle_frame(self, frame: Frame) -> bytes:
        # 仅 CMD 需要处理并 ACK
        if frame.ftype != TYPE_CMD:
            return b""

        ok, msg = self.router.route_cmd(frame.payload)
        rospy.loginfo(f"[CMD] seq={frame.seq} ok={ok} msg={msg}")

        # ACK payload: 被确认 seq（1字节）
        ack_payload = bytes([frame.seq & 0xFF])
        return encode_frame(TYPE_ACK, frame.seq, ack_payload)

    def serve_forever(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((self.host, self.port))
        s.listen(1)
        rospy.loginfo(f"Gateway listening on {self.host}:{self.port}")

        while not rospy.is_shutdown():
            conn, addr = s.accept()
            rospy.loginfo(f"client connected: {addr}")
            try:
                while not rospy.is_shutdown():
                    data = conn.recv(2048)
                    if not data:
                        break
                    for frame in self.decoder.feed(data):
                        resp = self._handle_frame(frame)
                        if resp:
                            conn.sendall(resp)
            except Exception as e:
                rospy.logerr(f"connection error: {e}")
            finally:
                conn.close()
                rospy.loginfo("client disconnected")


if __name__ == "__main__":
    rospy.init_node("protocol_ros_gateway")
    server = GatewayServer(host="0.0.0.0", port=19090)
    server.serve_forever()
```

## 10.1 可选：STATE 编码桥接（独立线程）

如果你需要把 ROS 状态回传成 `TYPE_STATE` 二进制帧，可在网关中加一个状态缓存与定时发送线程。

```python
import struct
import threading

from sensor_msgs.msg import Imu
from sensor_msgs.msg import BatteryState

class StateBridge:
    def __init__(self):
        self.battery = 100
        self.roll = 0.0
        self.pitch = 0.0
        self.yaw = 0.0
        self._lock = threading.Lock()

        rospy.Subscriber("/alphadog_aux/battery_state", BatteryState, self._on_battery, queue_size=1)
        rospy.Subscriber("/alphadog_node/imu", Imu, self._on_imu, queue_size=1)

    def _on_battery(self, msg: BatteryState):
        with self._lock:
            # 兼容：BatteryState.percentage 是 0~1，转 0~100
            p = msg.percentage * 100.0 if msg.percentage <= 1.0 else msg.percentage
            self.battery = max(0, min(100, int(round(p))))

    def _on_imu(self, msg: Imu):
        # 这里省略四元数->欧拉角转换，按你的现有姿态来源替换
        pass

    def build_state_frame(self, seq: int) -> bytes:
        with self._lock:
            roll_i = int(round(self.roll * 100))
            pitch_i = int(round(self.pitch * 100))
            yaw_i = int(round(self.yaw * 100))
            payload = struct.pack("<Bhhh", self.battery, roll_i, pitch_i, yaw_i)
        return encode_frame(TYPE_STATE, seq, payload)
```

---

## 11. 最小落地清单（MVP）

- [ ] 协议解码器可稳定解包（含坏包恢复）
- [ ] 支持 4 个 CMD：MOVE/STAND/SIT/STOP
- [ ] 打通 do_action execute
- [ ] 支持 result 监听与状态回传
- [ ] ACK 超时重传
- [ ] 5 条实机回归用例（站立、坐下、停止、一步前进、画爱心）

---

## 12. 一句话实施建议

先把“协议层稳定 + do_action 打通 + ACK/STATE 闭环”做成网关 MVP，  
再把高层业务动作迁移到 `do_dog_behavior`，最后补 Scratch 事件编排。

