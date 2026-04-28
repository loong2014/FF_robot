# robot_app

`apps/robot_app` 是仓库里的 Flutter 产品 App / 演示控制台，用来验证 `mobile_sdk`、`robot_server` 和真实机器狗链路。

## 当前能力

- BLE 扫描、连接与数据交互验证
- BLE 扫描列表仅展示名称以 `Robot` 开头的设备
- 记录最近一次成功连接的 BLE 设备，并在下次启动时自动尝试重连
- BLE 意外断开后的自动重连
- 新增正式遥控页：双摇杆 + 动作矩阵控制
- TCP / MQTT 连接配置弹窗
- 连接状态展示
- 首页快捷动作直控（stand / sit / stop / 常用 dog behavior）
- 语音控制模块：基于 Sherpa ONNX 的 `KWS + ASR + VAD` 双阶段链路，先做 `D-Dog` 唤醒，再持续识别到静音结束；支持中文 / 英文 / 中英混合唤醒别名，Android 前台监听，iOS 前台监听。
- 电量 / 姿态 / 最近 STATE 帧可视化
- 动作序列编辑、执行、暂停、恢复、停止
- 动作编排已支持 `move/stand/sit/stop` 以及 `do_action` / `do_dog_behavior`

## 当前定位

这个 App 目前是“可联调、可演示”的控制台，而不是已经完整产品化的正式 App。

还未完成的部分包括：

- 更完整的设备管理（例如多设备绑定、设备别名、最近连接列表）
- 更完整的手动遥控 UI
- 更细的错误恢复与引导
- 用户级配置管理
- 语音模块的 Sherpa 模型打包、资产缓存策略与唤醒误触调优
- 语音模块的更深层错误诊断与权限引导

## 正式遥控页说明

- 控制页主流程面向 BLE，页面内只提供 BLE 连接入口。
- 摇杆和动作按钮统一通过 `mobile_sdk/RobotClient` 下发，不直接依赖 transport 实现。
- 机器人端必须开启 `ROBOT_ROS_ENABLED=true`，`MOVE` 才会真正进入机器人对应的 ROS 控制链；AlphaDog 默认是 `/alphadog_node/set_velocity`。
- 右上角急停按钮在 `急停` / `恢复` 间切换；`恢复` 会发送恢复命令，摇杆首次进入还会先发送一次“进入运动模式”命令。
- 若要让左摇杆的横向移动真正生效，机器人端部署配置还需设置 `ROBOT_ROS_ENABLE_LATERAL=true`。

## 运行

`apps/robot_app` 默认使用官方 `pub.dev` 源。若当前 shell 里手动设置过 Flutter / Pub 镜像环境变量，先清掉它们，确保 `flutter pub get` / `flutter run` 走官方源：

```bash
unset PUB_HOSTED_URL FLUTTER_STORAGE_BASE_URL
# 或者显式指定为官方源
export PUB_HOSTED_URL=https://pub.dev
export FLUTTER_STORAGE_BASE_URL=https://storage.googleapis.com
```

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
