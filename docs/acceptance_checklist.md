# robot_factory 验收 Checklist

> 适用范围：`robot_server` 内嵌 BLE + 可选 TCP / MQTT / ROS
> 在 Ubuntu 20.04 + ROS1 Noetic 真机上的首轮验收。

## 0. 环境准备

- [ ] Ubuntu 20.04 + ROS1 Noetic 已安装
- [ ] Python 3.8 可用
- [ ] BlueZ ≥ 5.53
- [ ] 仓库已部署到 `/opt/robot_factory`
- [ ] `/etc/robot_factory/robot_server.env` 已配置
- [ ] `/etc/systemd/system/bluetooth.service.d/robot-factory.conf` 已安装
- [ ] `/etc/bluetooth/main.conf` 包含 `ReverseServiceDiscovery = false`
- [ ] `/etc/bluetooth/main.conf` 的 `[GATT]` 下包含 `Cache = no`
- [ ] `teleop_robot.service` 已停止 / 禁用

## 1. 单元测试

- [ ] `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=protocol/python python3 -m unittest discover -s protocol/python/tests`
- [ ] `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=protocol/python:robot_server python3 -m unittest discover -s robot_server/tests`

## 2. 启动与存活

- [ ] `sudo systemctl start robot_server.service` 成功
- [ ] `systemctl status bluetooth.service` 为 `active (running)`
- [ ] `systemctl status robot_server.service` 为 `active (running)`
- [ ] `bluetoothctl show` 显示 `Powered: yes`
- [ ] `busctl tree org.bluez` 存在 `/org/bluez/hci0`

## 3. robot_server 核心通路

- [ ] `journalctl -u robot_server.service -b` 中没有 `BLE registration failed` / `timed out`
- [ ] 若启用外部 TCP 调试：把 `ROBOT_TCP_ENABLED=true` 且 `ROBOT_TCP_HOST=0.0.0.0` 后，`scripts/tcp_smoke.py` 能收到 ACK + STATE
- [ ] `ROBOT_ROS_ENABLED=true` 时，`rostopic hz /cmd_vel` 稳定输出约 10Hz

## 4. BLE 服务

- [ ] 手机能扫描到 `ROBOT_BLE_DEVICE_NAME`
- [ ] 点击连接后不超时
- [ ] 能发现 `ROBOT_BLE_SERVICE_UUID`
- [ ] 给 `ROBOT_BLE_STATE_UUID` 开启 notify 成功
- [ ] 向 `ROBOT_BLE_CMD_UUID` 写入协议帧后收到 ACK
- [ ] state notify 稳定约 10Hz

## 5. MQTT 通路（若启用）

- [ ] `ROBOT_MQTT_ENABLED=true` 后，robot_server 日志出现连接成功
- [ ] broker 上能看到 `robot/<id>/state`
- [ ] 控制指令经过 MQTT 能产生 ACK

## 6. ROS 状态采集（若启用）

- [ ] `ROBOT_ROS_STATE_ENABLED=true` 后，日志出现 battery / imu / odom / diagnostics 订阅
- [ ] 电池话题变化能反映到状态
- [ ] IMU / yaw 变化能反映到状态
- [ ] diagnostics 错误能产生事件

## 7. 故障恢复

- [ ] 重启 `robot_server.service` 后，广播能恢复
- [ ] 重启 `bluetooth.service` 后，再重启 `robot_server.service`，BLE 能重新工作
- [ ] 执行 `sudo /opt/robot_factory/scripts/recover_bluetooth.sh` 后，`bluetooth.service` 与 `robot_server.service` 都恢复

## 8. 记录项

- [ ] 记录验收日期 / 机器狗型号 / 提交版本
- [ ] 若失败，附 `journalctl -u robot_server.service -b`
- [ ] 若 BLE 连接异常，附 `bluetoothctl show` 与 `busctl tree org.bluez`
