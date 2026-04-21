# BLE 联调指南

`robot_server` 里的 BLE 服务端实现已经替换成当前项目里在机器狗上跑通的
BlueZ GATT 外设代码骨架。也就是说：

- BLE 仍然挂在 `robot_server/transports/ble`
- `RuntimeTransport` / ACK / STATE 协议接口保持不变
- 底层的 GATT Application、Advertisement、Command/State characteristic
  实现改成了已验证版本

## 1. 代码位置

- `robot_server/robot_server/transports/ble/bluez_gatt_glib.py`
  当前真实实现
- `robot_server/robot_server/transports/ble/bluez_gatt.py`
  兼容导出层

## 2. 关键行为

Service / characteristic UUID 仍然由 `BLEConfig` 决定：

- service UUID: `ROBOT_BLE_SERVICE_UUID`
- command characteristic: `ROBOT_BLE_CMD_UUID`
- state characteristic: `ROBOT_BLE_STATE_UUID`

与之前不同的是，底层 BlueZ 注册逻辑已经不再使用原来的大状态机，而是直接走
当前项目里已经在机器狗上验证通过的 `dbus-python + GLib` 外设服务骨架。

保留的 `robot_server` 行为：

- command write 进入 `TransportEnvelope`
- `RobotRuntime` 继续做 ACK / 去重 / 命令分发
- state frame 继续通过 notify 推送
- `StateCharacteristic` 仍按 session MTU 分片

## 3. 真机依赖

```bash
sudo apt update
sudo apt install -y \
  bluez bluez-tools rfkill \
  python3-dbus python3-gi \
  ros-noetic-ros-base ros-noetic-geometry-msgs
```

如果在 venv 里启动，确保系统 `dist-packages` 已进入 `PYTHONPATH`。  
推荐直接用 `scripts/start_robot_server.sh` 启动。

## 4. BlueZ 配置

为了让这套实现在机器狗上稳定工作，仍然建议保留已经验证过的系统配置：

1. 安装 `bluetooth.service` drop-in：

```bash
sudo mkdir -p /etc/systemd/system/bluetooth.service.d
sudo cp /opt/robot_factory/scripts/bluetooth.service.d/robot-factory.conf \
  /etc/systemd/system/bluetooth.service.d/robot-factory.conf
```

2. 确保 `/etc/bluetooth/main.conf` 包含：

```ini
ReverseServiceDiscovery = false

[GATT]
Cache = no
```

3. 停掉厂商自带 BLE 服务：

```bash
sudo systemctl stop teleop_robot.service || true
sudo systemctl disable teleop_robot.service || true
```

## 5. 启动方式

```bash
cd /opt/robot_factory
scripts/start_robot_server.sh
```

如果走 systemd，`robot_server.service` 应放在 `bluetooth.service` 之后启动。

## 6. 联调步骤

1. 启动 `robot_server`
2. 用 `BLE调试助手` 或 `nRF Connect` 扫描设备
3. 连接后找到 `ROBOT_BLE_SERVICE_UUID`
4. 给 `ROBOT_BLE_STATE_UUID` 开启 notify
5. 往 `ROBOT_BLE_CMD_UUID` 写入协议帧

预期：

- 机器人端日志出现 command write
- ACK 通过 state characteristic 回来
- 10Hz state notify 正常

## 7. 排障

### 手机能扫到广播，但连接超时

优先检查：

- `systemctl status bluetooth.service`
- `bluetoothctl show`
- `busctl tree org.bluez`
- `teleop_robot.service` 是否仍在运行

### `ROBOT_BLE_BACKEND=glib` 启动时报依赖错误

说明系统里缺 `python3-dbus` / `python3-gi`，或 venv 没看到系统包。  
先确认：

```bash
python3 -c "import dbus; from gi.repository import GLib"
```

### 仍然起不来

可使用已经保留下来的恢复脚本：

```bash
sudo /opt/robot_factory/scripts/recover_bluetooth.sh
```
