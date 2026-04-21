# robot_factory 部署与联调指南

> 目标环境：Ubuntu 20.04 + ROS1 Noetic + Python 3.8

当前推荐部署拓扑：

```text
bluetooth.service            robot_server.service
   BlueZ daemon   <------>   Runtime + GATT peripheral + TCP/MQTT/ROS
                                   |
                                   +--> BLE client / 手机
                                   +--> optional TCP / MQTT debug
```

当前推荐路径里，BLE 由 `robot_server` 进程内直接注册到 BlueZ，不再依赖独立
`robot_ble_peripheral.service`。

## 1. 交付物

| 文件 | 用途 |
|---|---|
| `.env.example` | `robot_server` 环境变量模板 |
| `scripts/start_robot_server.sh` | 启动 `robot_server` |
| `scripts/robot_server.service` | `robot_server` 的 systemd unit |
| `scripts/bluetooth.service.d/robot-factory.conf` | BlueZ drop-in |
| `scripts/recover_bluetooth.sh` | 蓝牙恢复脚本 |
| `docs/ble_integration.md` | BLE 联调说明 |
| `docs/ros_state_integration.md` | ROS 状态采集说明 |

仓库中仍保留 `scripts/robot_ble_peripheral.*` 作为历史参考，但当前部署不依赖它们。

## 2. 系统依赖

```bash
sudo apt update
sudo apt install -y \
    python3 python3-pip python3-venv python3-dev \
    bluez bluez-tools rfkill \
    python3-dbus python3-gi \
    ros-noetic-ros-base \
    ros-noetic-sensor-msgs ros-noetic-nav-msgs \
    ros-noetic-diagnostic-msgs ros-noetic-geometry-msgs \
    mosquitto-clients
```

说明：

- `rospy` 由 ROS1 Noetic 系统环境提供，不要 `pip install rospy`
- 若启用 MQTT，再额外准备 broker
- 机器狗板载蓝牙仍依赖下面的 BlueZ drop-in

## 3. Python 依赖

```bash
cd /opt/robot_factory
python3 -m venv .venv          # 可选
source .venv/bin/activate      # 可选

pip install -U pip
pip install -e protocol/python
pip install paho-mqtt
```

`python3-dbus` / `python3-gi` 使用系统包提供；若在 venv 里启动，确保系统
`dist-packages` 在 `PYTHONPATH` 中。推荐直接走 `scripts/start_robot_server.sh`。

## 4. 环境文件

```bash
sudo mkdir -p /etc/robot_factory
sudo cp /opt/robot_factory/.env.example /etc/robot_factory/robot_server.env
sudo chmod 640 /etc/robot_factory/robot_server.env
```

推荐保持的关键默认值：

```bash
ROBOT_BLE_ENABLED=true
ROBOT_BLE_DEVICE_NAME=RobotOSLite-BLE
ROBOT_TCP_ENABLED=false
ROBOT_MQTT_ENABLED=false
```

需要旁路调试时，再显式打开 TCP / MQTT。

## 5. BlueZ 配置

### 5.1 bluetooth.service drop-in

```bash
sudo mkdir -p /etc/systemd/system/bluetooth.service.d
sudo cp /opt/robot_factory/scripts/bluetooth.service.d/robot-factory.conf \
  /etc/systemd/system/bluetooth.service.d/robot-factory.conf
```

### 5.2 `/etc/bluetooth/main.conf`

确保包含：

```ini
ReverseServiceDiscovery = false

[GATT]
Cache = no
```

### 5.3 停掉厂商 BLE

```bash
sudo systemctl stop teleop_robot.service || true
sudo systemctl disable teleop_robot.service || true
```

## 6. 启动顺序

1. `bluetooth.service`
2. `robot_server.service`

安装并启动：

```bash
sudo cp /opt/robot_factory/scripts/robot_server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now robot_server.service
```

查看状态：

```bash
sudo systemctl status bluetooth.service
sudo systemctl status robot_server.service
sudo journalctl -u robot_server.service -f
```

## 7. 手动启动

```bash
cd /opt/robot_factory
scripts/start_robot_server.sh
```

## 8. 烟雾测试

### 8.1 核心运行时

```bash
PYTHONDONTWRITEBYTECODE=1 \
PYTHONPATH=protocol/python:robot_server \
python3 -m unittest discover -s robot_server/tests
```

若启用 TCP 调试，再检查：

```bash
ss -ltnp | grep 9000
```

### 8.2 BLE

用 `BLE调试助手` 或 `nRF Connect`：

1. 扫描 `ROBOT_BLE_DEVICE_NAME`
2. 连接
3. 找到 `ROBOT_BLE_SERVICE_UUID`
4. 给 `ROBOT_BLE_STATE_UUID` 开启 notify
5. 往 `ROBOT_BLE_CMD_UUID` 写入协议帧

预期：

- 连接不超时
- 立即收到 ACK
- state notify 约 10Hz

注意：当前 `robot_server` 走统一二进制协议；写入纯文本 `hello` 不会像旧的独立
BLE 脚本那样返回 `no hook configured`。

## 9. 故障恢复

如果 BlueZ 或控制器状态异常：

```bash
sudo /opt/robot_factory/scripts/recover_bluetooth.sh
```

它会：

- 重装 `bluetooth.service` drop-in
- 修正 `/etc/bluetooth/main.conf`
- 停掉 `robot_server.service`、厂商 BLE 服务和遗留独立 BLE 服务
- 重新 bring-up 板载蓝牙
- 重启 `bluetooth.service` 与 `robot_server.service`

## 10. 常见问题

### 手机能扫到广播，但连接超时

优先检查：

- `teleop_robot.service` 是否已停
- `ReverseServiceDiscovery = false` 是否生效
- `busctl tree org.bluez` 是否存在 `/org/bluez/hci0`
- `journalctl -u robot_server.service -b` 是否出现 BLE registration 超时或报错

### `ROBOT_BLE_BACKEND=glib` 启动时报依赖错误

通常是系统里缺 `python3-dbus` / `python3-gi`，或 venv 没看到系统包：

```bash
python3 -c "import dbus; from gi.repository import GLib"
```

### `robot_server` 启动后 `import rospy` 失败

确认是用 `scripts/start_robot_server.sh` 启动，而不是直接裸跑 `python3`。  
这个脚本会自动 source `/opt/ros/noetic/setup.bash` 并把系统 `dist-packages`
加入 `PYTHONPATH`。
