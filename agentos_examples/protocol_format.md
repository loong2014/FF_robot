# Robot Protocol 格式汇总

## 1. 协议范围

本项目协议分为两部分：

- 二进制协议：用于 `control` / `state`
- JSON 事件：仅用于 MQTT `robot/{id}/event`

本文重点说明二进制协议格式；最后补充 MQTT topic 约定。

## 2. 二进制帧总览

每一帧的结构固定为：

```text
0xAA55 | Type | Seq | Len | Payload | CRC16
```

按字节展开：

| 字段 | 字节数 | 偏移 | 说明 |
| --- | ---: | ---: | --- |
| Magic | 2 | 0 | 固定 `0xAA 0x55` |
| Type | 1 | 2 | 帧类型 |
| Seq | 1 | 3 | 序号，`0~255` 循环 |
| Len | 2 | 4 | `Payload` 长度，`uint16`，小端 |
| Payload | N | 6 | 业务负载 |
| CRC16 | 2 | `6 + N` | CRC 校验值，`uint16`，小端 |

说明：

- 帧头固定长度为 `6` 字节：`Magic(2) + Type(1) + Seq(1) + Len(2)`
- 整帧固定开销为 `8` 字节：帧头 `6` + CRC `2`
- 当前实现的最大 `Payload` 长度为 `512` 字节
- 字节序统一使用 little-endian

## 3. CRC 规则

CRC 算法为 `CRC16-CCITT`，代码实现的初始值和多项式如下：

- 初始值：`0xFFFF`
- 多项式：`0x1021`
- 输出宽度：16 bit
- CRC 覆盖范围：`Type + Seq + Len + Payload`
- `Magic` 不参与 CRC
- CRC 结果写入帧尾时使用小端

对应 Python 实现见 `protocol/python/robot_protocol/crc.py`。

## 4. Frame Type 定义

| 名称 | 值 | 含义 |
| --- | ---: | --- |
| `CMD` | `0x01` | 控制命令 |
| `STATE` | `0x02` | 机器人状态 |
| `ACK` | `0x03` | 对 `CMD` 的确认 |

## 5. Payload 定义

### 5.1 `CMD` Payload

`CMD` 用于下发控制命令，分为 `MOVE` 和离散命令两类。

#### `MOVE`

| 字段 | 类型 | 字节数 | 说明 |
| --- | --- | ---: | --- |
| `cmd_id` | `uint8` | 1 | 固定 `0x01` |
| `vx` | `int16` | 2 | 线速度 x，实际值乘以 `100` |
| `vy` | `int16` | 2 | 线速度 y，实际值乘以 `100` |
| `yaw` | `int16` | 2 | 角速度 yaw，实际值乘以 `100` |

总长度：`7` 字节。

编码示例：

- `vx = 0.55` -> `55` -> `0x0037` -> 小端写入 `37 00`
- `vy = -0.20` -> `-20` -> `0xFFEC` -> 小端写入 `EC FF`
- `yaw = 1.25` -> `125` -> `0x007D` -> 小端写入 `7D 00`

#### 离散命令

离散命令只有 1 字节：

| 命令 | `cmd_id` | Payload |
| --- | ---: | --- |
| `stand` | `0x10` | `10` |
| `sit` | `0x11` | `11` |
| `stop` | `0x12` | `12` |

总长度：`1` 字节。

### 5.2 `STATE` Payload

`STATE` 用于机器人周期性上报状态。

| 字段 | 类型 | 字节数 | 说明 |
| --- | --- | ---: | --- |
| `battery` | `uint8` | 1 | 电量，当前实现按 `0~100` 使用 |
| `roll` | `int16` | 2 | 横滚角，实际值乘以 `100` |
| `pitch` | `int16` | 2 | 俯仰角，实际值乘以 `100` |
| `yaw` | `int16` | 2 | 偏航角，实际值乘以 `100` |

总长度：`7` 字节。

示例：

- `battery = 87` -> `57`
- `roll = 1.20` -> `120` -> `78 00`
- `pitch = -0.50` -> `-50` -> `CE FF`
- `yaw = 35.66` -> `3566` -> `EE 0D`

### 5.3 `ACK` Payload

`ACK` 负载只有 1 字节：

| 字段 | 类型 | 字节数 | 说明 |
| --- | --- | ---: | --- |
| `seq` | `uint8` | 1 | 被确认的命令序号 |

总长度：`1` 字节。

当前实现里：

- `ACK` 帧头里的 `Seq`
- `ACK Payload` 里的 `seq`

这两个值相同，都会写成被确认的序号。

## 6. 数值缩放规则

协议中浮点量不直接上传输，统一缩放为 `int16`：

| 字段类别 | 缩放倍数 |
| --- | ---: |
| `MOVE` 速度 | `100` |
| `STATE` 姿态角 | `100` |
| `MOVE.yaw` | `100` |

换算规则：

```text
encoded = round(actual * 100)
actual = encoded / 100
```

如果缩放后的结果超出 `int16` 范围 `[-32768, 32767]`，编码会直接报错。

## 7. 帧长度公式

设 `payload_len = N`，则：

```text
frame_len = 2 + 1 + 1 + 2 + N + 2
          = 8 + N
```

常见帧长度：

| 帧类型 | Payload 长度 | 整帧长度 |
| --- | ---: | ---: |
| `CMD(MOVE)` | 7 | 15 |
| `CMD(STAND/SIT/STOP)` | 1 | 9 |
| `STATE` | 7 | 15 |
| `ACK` | 1 | 9 |

## 8. 流式解码规则

协议支持半包、粘包和坏包恢复，解码逻辑如下：

1. 在字节流中查找帧头 `0xAA55`
2. 找到后读取 `Len`
3. 若当前缓存长度不足整帧长度，则继续等待更多字节
4. 若 `Len > 512`，认为当前头非法，丢掉 1 字节后继续搜索
5. 若 CRC 校验失败，丢掉 1 字节后重新搜帧
6. 成功解出一帧后，从缓冲区移除该帧，继续解析后续数据

这套逻辑同时体现在：

- Python：`protocol/python/robot_protocol/stream_decoder.py`
- Dart：`protocol/dart/lib/src/stream_decoder.dart`

因此它可以处理：

- TCP 粘包
- TCP 半包
- BLE 分片后的重组
- 连续多帧拼接输入

## 9. ACK 与重传语义

协议层本身只定义 `ACK` 帧格式；当前项目约定的时序语义如下：

- 只有 `CMD` 需要 ACK
- 收到合法 `CMD` 后，机器人端立即回复 `ACK`
- 若检测为重复包，仍回复 `ACK`，但不重复执行业务动作
- 默认 ACK 超时为 `100ms`
- 默认最大重试次数为 `3`

这些默认值定义在：

- `DEFAULT_ACK_TIMEOUT_MS = 100`
- `DEFAULT_MAX_RETRIES = 3`

注意：

- 这些值属于项目运行约定，不是帧内字段
- 当前 `protocol` 模块只提供帧格式和编解码，不直接管理重传状态机

## 10. 状态推送语义

- 默认状态推送频率：`10Hz`
- `STATE` 为机器人端主动下发
- BLE / TCP / MQTT 都复用同一套 `STATE` 二进制格式

默认值定义在：

- `DEFAULT_STATE_HZ = 10`

## 11. MQTT Topic 约定

二进制帧在 MQTT 下的承载方式如下：

| Topic | 方向 | 负载格式 |
| --- | --- | --- |
| `robot/{id}/control` | App -> Robot | 二进制协议帧，通常是 `CMD` |
| `robot/{id}/state` | Robot -> App | 二进制协议帧，承载 `STATE` 和 `ACK` |
| `robot/{id}/event` | Robot -> App | JSON 事件，不走本文的二进制帧格式 |

也就是说：

- MQTT 下 `ACK` 不是单独 topic，而是跟 `STATE` 共用 `robot/{id}/state`
- `event` 不带 `0xAA55` 帧头，它是纯 JSON

## 12. 示例帧

以下示例均按当前 Python 实现实时编码得到。

### 12.1 `MOVE` 示例

语义：

- `type = CMD`
- `seq = 7`
- `vx = 0.55`
- `vy = -0.20`
- `yaw = 1.25`

十六进制：

```text
AA5501070700013700ECFF7D000584
```

拆解：

```text
AA55          Magic
01            Type = CMD
07            Seq = 7
0700          Len = 7
01            cmd_id = MOVE
3700          vx = 55 -> 0.55
ECFF          vy = -20 -> -0.20
7D00          yaw = 125 -> 1.25
0584          CRC16 (little-endian)
```

### 12.2 `STAND` 示例

语义：

- `type = CMD`
- `seq = 8`
- `cmd_id = STAND`

十六进制：

```text
AA5501080100109F1B
```

拆解：

```text
AA55          Magic
01            Type = CMD
08            Seq = 8
0100          Len = 1
10            cmd_id = STAND
9F1B          CRC16
```

### 12.3 `STATE` 示例

语义：

- `type = STATE`
- `seq = 9`
- `battery = 87`
- `roll = 1.20`
- `pitch = -0.50`
- `yaw = 35.66`

十六进制：

```text
AA5502090700577800CEFFEE0D9967
```

拆解：

```text
AA55          Magic
02            Type = STATE
09            Seq = 9
0700          Len = 7
57            battery = 87
7800          roll = 120 -> 1.20
CEFF          pitch = -50 -> -0.50
EE0D          yaw = 3566 -> 35.66
9967          CRC16
```

### 12.4 `ACK` 示例

语义：

- `type = ACK`
- `seq = 42`
- `ack payload = 42`

十六进制：

```text
AA55032A01002A2312
```

拆解：

```text
AA55          Magic
03            Type = ACK
2A            Seq = 42
0100          Len = 1
2A            ack seq = 42
2312          CRC16
```

## 13. 代码锚点

如果后续需要继续核对实现，优先看这些文件：

- Python 编解码：`agentos_examples/protocol/python/robot_protocol/codec.py`
- Python 流解码：`agentos_examples/protocol/python/robot_protocol/stream_decoder.py`
- Python 常量：`agentos_examples/protocol/python/robot_protocol/constants.py`
- Dart 编解码：`agentos_examples/protocol/dart/lib/src/codec.dart`
- Dart 流解码：`agentos_examples/protocol/dart/lib/src/stream_decoder.dart`
- Python 测试：`agentos_examples/protocol/python/tests/test_protocol.py`

