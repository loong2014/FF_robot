# robot_app

`apps/robot_app` 是仓库里的 Flutter 产品 App / 演示控制台，用来验证 `mobile_sdk`、`robot_server` 和真实机器狗链路。

## 当前能力

- BLE 扫描、连接与数据交互验证
- BLE 扫描列表仅展示名称以 `Robot` 开头的设备
- 记录最近一次成功连接的 BLE 设备，并在下次启动时自动尝试重连
- BLE 意外断开后的自动重连
- 新增正式遥控页：双摇杆 + 动作矩阵控制
- 正式遥控页在 BLE 断开 / 重连 / 命令错误后会重置本地运动模式缓存；下一次摇杆会重新发送 `enterMotionMode()`，避免机器狗异常恢复后只发速度命令而不进入运行模式。
- 正式遥控页在 BLE 连接状态离开 connected 后会立即停止本地摇杆定时发送；真机侧还需要 `robot_server` 的 BLE 断开保护把 ROS 速度清零。
- 首页新增完整动作控制页：打包 `robot_skill` JSON，展示全部 `do_action` / `do_dog_behavior`
- TCP / MQTT 连接配置弹窗
- 连接状态展示
- 首页快捷动作直控（stand / sit / stop / 常用 dog behavior）
- 完整动作控制页展示连接状态、电量、姿态，以及全部动作 / 行为列表；点击后通过 `RobotClient.doAction` / `RobotClient.doDogBehavior` 下发
- 手动控制页与首页快捷控制使用 `RobotClient` 默认实时语义，连续点击时只保留最后一个尚未发送的控制命令
- 语音控制模块：基于 Sherpa ONNX 的 `KWS + ASR + VAD` 双阶段链路，固定 `Lumi` / `鲁米` 唤醒；唤醒后只用最终 ASR 做命令匹配，支持站起、坐下、停止、前进、后退、左移、右移；App 级 `VoiceRobotController` 持有当前 `RobotClient` 并用 last-wins API 执行语音命令。Android 使用前台服务和通知停止 action，iOS 仅前台监听并在退后台 / 中断时释放麦克风。
- 手势控制模块：`command` / `follow` 双模式手势状态机已接入当前 `RobotClient`；离散手势走 last-wins 短促控制并补零速，follow 连续移动节流到约 10Hz；原生识别页固定单一横屏，关闭后恢复 App 方向偏好。
- 电量 / 姿态 / 最近 STATE 帧可视化
- 动作序列编辑、执行、暂停、恢复、停止
- 动作编排已支持 `move/stand/sit/stop` 以及 `do_action` / `do_dog_behavior`，内部走 `RobotClient.*Queued()` 保持 FIFO 顺序执行

## 当前定位

这个 App 目前是“可联调、可演示”的控制台，而不是已经完整产品化的正式 App。

还未完成的部分包括：

- 更完整的设备管理（例如多设备绑定、设备别名、最近连接列表）
- 更完整的手动遥控 UI
- 更细的错误恢复与引导
- 用户级配置管理
- 语音模块的 Sherpa 模型误触调优与 iOS / Android 真机长时稳定性回归
- 语音模块的更深层错误诊断与权限引导

## 正式遥控页说明

- 控制页主流程面向 BLE，页面内只提供 BLE 连接入口。
- 摇杆和动作按钮统一通过 `mobile_sdk/RobotClient` 下发，不直接依赖 transport 实现；手动控制使用默认实时语义，避免连续点击把多个动作排成 FIFO。
- 机器人端必须开启 `ROBOT_ROS_ENABLED=true`，`MOVE` 才会真正进入机器人对应的 ROS 控制链；AlphaDog 默认是 `/alphadog_node/set_velocity`。
- 右上角急停按钮在 `急停` / `恢复` 间切换；`急停` 会发送真机 `EStop`，`恢复` 会发送 `Recovery stand`，每次新的摇杆会话都会先发送一次“进入运动模式”命令。当前 BLE STATE 不包含真机运行模式字段，因此这里采用保守重发，而不是声称已经能监听真实运行模式。
- 若要让左摇杆的横向移动真正生效，机器人端部署配置还需设置 `ROBOT_ROS_ENABLE_LATERAL=true`。

## 完整动作控制页说明

- 首页入口为“完整动作控制”。
- 页面资源来自 `apps/robot_app/assets/robot_skill/do_action/ext_actions.json` 与 `apps/robot_app/assets/robot_skill/do_dog_behavior/dog_behaviors.json`。
- 页面顶部状态只展示当前协议已有字段：连接状态、电量、roll、pitch、yaw。
- `do_action` 列表按 `action_id + action_name` 作为 UI key；当前资源里 `action_id=20589` 重复，页面会显示重复 ID 提示。
- `do_dog_behavior` 仍受协议枚举限制；当前 39 个资源行为都能映射到 `DogBehavior`。

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
