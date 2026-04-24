# robot_server

Ubuntu 机器人端服务，负责：

- 接入 BLE / TCP / MQTT
- 解析统一二进制协议
- 成功接受 `CMD` 进入本地处理链后回 ACK；重复包只回 ACK 不重复执行业务动作
- 以 10Hz 向外广播状态
- 将 `MOVE` 同步到 ROS1 `/cmd_vel`
- 将 `STAND` / `SIT` / `STOP` 以及 `0x20 skill_invoke` 路由到 `/agent_skill/.../execute`
- 从 ROS1 订阅电池 / IMU / 里程 / 诊断，填充真实状态并推送事件

## 默认链路：BLE-only

`robot_server` 的 BLE 服务端实现已经直接替换为当前项目里在机器狗上跑通的
BlueZ GATT 外设代码骨架。保留了 `robot_server` 的 transport 接口、ACK / STATE
协议和单测接口，但底层的 GATT 注册、广告、读写 characteristic 流程换成了
已验证实现。

默认行为仍然是：

- `ROBOT_BLE_ENABLED=true`
- `ROBOT_TCP_ENABLED=false`
- `ROBOT_MQTT_ENABLED=false`

需要调试旁路时，再显式打开 TCP / MQTT。

## 主要模块

- `transports/ble/bluez_gatt_glib.py`
  移植后的 BLE 外设实现，基于当前项目已验证的 `dbus-python + GLib`
- `transports/ble/bluez_gatt.py`
  兼容层，保留原类名 `BlueZGATTTransport`
- `transports/tcp/server.py`
  TCP socket server
- `transports/mqtt/router.py`
  MQTT Topic Router
- `runtime/control_service.py`
  ACK / 去重 / 命令分发
- `runtime/state_store.py`
  `RobotState` + `RobotStateExtras`
- `runtime/robot_runtime.py`
  整体编排与 10Hz 状态推送
- `ros/bridge.py`
  ROS1 控制桥（下行 `/cmd_vel`，10Hz）
- `ros/skill_bridge.py`
  ROS1 skill bridge（下行 `do_action` / `do_dog_behavior`）
- `ros/state_bridge.py`
  ROS1 状态桥（上行 battery / IMU / odom / diagnostics）

## 当前命令映射

- `0x01 MOVE`
  继续走 `/cmd_vel` 连续控制
- `0x10 STAND`
  默认映射 `do_action(action_id=3)`
- `0x11 SIT`
  默认映射 `do_action(action_id=5)`
- `0x12 STOP`
  先取消当前 skill goal，再执行 `do_action(action_id=6)`
- `0x20 skill_invoke`
  一期已接 `do_action(action_id:uint16)` 与 `do_dog_behavior(behavior_id:uint8)`

ACK 语义保持不变：只表示命令成功进入 `robot_server` 本地处理链，不表示机器人动作执行完成。

## 依赖

- `python3-dbus` + `python3-gi`
  真机 BLE 主路径依赖
- `paho-mqtt`
- `rospy` 与 `sensor_msgs` / `nav_msgs` / `diagnostic_msgs` / `geometry_msgs`
  由 ROS1 Noetic 系统环境提供
- 厂商扩展 ROS Python 包（如 `agent_msgs`）
  若安装在 `/opt/*/lib/python3/dist-packages`，`scripts/start_robot_server.sh` 会自动补进 `PYTHONPATH`

## 相关文档

- BLE 联调：[`docs/ble_integration.md`](../docs/ble_integration.md)
- 部署步骤：[`docs/deploy.md`](../docs/deploy.md)
- ROS 状态采集：[`docs/ros_state_integration.md`](../docs/ros_state_integration.md)

## 运行单元测试

```bash
PYTHONDONTWRITEBYTECODE=1 \
PYTHONPATH=protocol/python:robot_server \
python3 -m unittest discover -s robot_server/tests
```
