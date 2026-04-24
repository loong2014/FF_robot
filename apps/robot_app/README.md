# robot_app

`apps/robot_app` 是仓库里的 Flutter 产品 App / 演示控制台，用来验证 `mobile_sdk`、`robot_server` 和真实机器狗链路。

## 当前能力

- BLE 扫描、连接与数据交互验证
- TCP / MQTT 连接配置弹窗
- 连接状态展示
- 首页快捷动作直控（stand / sit / stop / 常用 dog behavior）
- 电量 / 姿态 / 最近 STATE 帧可视化
- 动作序列编辑、执行、暂停、恢复、停止
- 动作编排已支持 `move/stand/sit/stop` 以及 `do_action` / `do_dog_behavior`

## 当前定位

这个 App 目前是“可联调、可演示”的控制台，而不是已经完整产品化的正式 App。

还未完成的部分包括：

- 设备绑定与持久化
- 更完整的手动遥控 UI
- 更细的错误恢复与引导
- 用户级配置管理

## 运行

```bash
cd /path/to/robot_factory/apps/robot_app
flutter pub get
flutter run
```

## 测试

```bash
cd /path/to/robot_factory/apps/robot_app
flutter test
```
