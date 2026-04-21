你是一个资深机器人系统架构师，精通 ROS1 Noetic、Flutter SDK、BLE（BlueZ）、TCP 网络通信、MQTT，以及分布式通信系统设计。

请设计并实现一个机器狗控制系统（Robot OS Lite）。

系统包含：
- Flutter App（主应用 + 图形化编程）
- Ubuntu 机器人端（ROS1 Noetic）
- BLE（核心实现）
- TCP（局域网/USB网络，框架）
- MQTT（云端，框架 + Router）
- 统一二进制协议

================================================
【⚠️ 强制执行流程】
================================================

必须严格按三阶段执行：

------------------------------------------------
【PHASE 0 - PLAN（必须先做）】
------------------------------------------------

输出：

1. 完整系统架构图（App / SDK / Server）
2. BLE / TCP / MQTT 数据流
3. ROS1控制路径设计
4. 协议设计确认（详细字段级）
5. Command Queue设计
6. ACK + 重传机制设计
7. 风险分析
8. 确认开发顺序

⚠️ 禁止写代码

------------------------------------------------
【PHASE 1 - SKELETON】
------------------------------------------------

创建完整工程结构：

robot_factory/
├── mobile_sdk
├── robot_server
├── protocol
├── apps

要求：
- 所有模块必须有 interface / stub
- 不实现业务逻辑

------------------------------------------------
【PHASE 2 - IMPLEMENTATION（按顺序）】
------------------------------------------------

========================
1️⃣ BLE（必须完整实现🔥）
========================

- BlueZ GATT Server
- Service:
  RobotControlService

Characteristics:
- cmd_char (write without response)
- state_char (notify)

要求：
- 二进制收发
- MTU考虑
- 粘包处理
- ACK + 重传（3次，100ms timeout）
- 10Hz state push

========================
2️⃣ Protocol Layer（统一协议🔥）
========================

数据帧：

| 0xAA55 | Type | Seq | Len | Payload | CRC |

Type:
0x01 CMD
0x02 STATE
0x03 ACK

CMD Payload：

MOVE（0x01）：
| cmd_id | vx(int16) | vy(int16) | yaw(int16) |
说明：实际值 * 100

DISCRETE：
| cmd_id |
0x10 stand
0x11 sit
0x12 stop

STATE：
| battery | roll(int16) | pitch | yaw |

ACK：
| seq |

要求：
- 支持粘包解析
- CRC校验
- stream decoder

========================
3️⃣ Command Queue（必须实现🔥）
========================

规则：

- move：只保留最新（覆盖）
- discrete：FIFO执行

ACK关系：
- 未ACK → 阻塞重传逻辑

========================
4️⃣ TCP（框架）
========================

- socket server
- stream input
- 接入 protocol parser
- 不做BLE级别完整优化

========================
5️⃣ MQTT（框架 + Router）
========================

Topic：

robot/{id}/control
robot/{id}/state
robot/{id}/event

规则：

- control → binary protocol
- state → binary
- event → JSON

必须实现：
- Topic Router
- Protocol dispatch

========================
6️⃣ ROS1 集成（Noetic）
========================

- rospy
- 发布 /cmd_vel
- geometry_msgs/Twist

映射：

vx → linear.x
yaw → angular.z

频率：
- 10Hz control sync

========================
7️⃣ Flutter SDK
========================

RobotClient API：

- connectBLE()
- connectTCP()
- connectMQTT()

- move(vx, vy, yaw)
- stand()
- sit()
- stop()

- stateStream

Transport：

- BLE（完整实现）
- TCP（接口）
- MQTT（接口）

========================
8️⃣ 图形化编程（App内模块）
========================

Action Engine：

输入：
[
  {cmd:"stand"},
  {cmd:"move", vx:0.5, duration:2000},
  {cmd:"sit"}
]

要求：
- 状态机执行
- 支持暂停 / 停止
- 调用 RobotClient

================================================
【输出要求】
================================================

必须输出：

1. Phase 0（设计）
2. Phase 1（架构）
3. Phase 2（代码实现）