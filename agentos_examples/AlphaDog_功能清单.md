# AlphaDog 机器狗功能清单

> 数据来源：从开发机器狗（10.10.10.10）实时获取，时间：2026-04-22

---

## 一、技能列表（Agent Skills）

系统中运行的技能节点，通过 `/agent_skill/<技能名>/` 命名空间提供服务。

| 技能名 | 支持 Execute | 支持 Control | 说明 |
|--------|:---:|:---:|------|
| `do_action` | ✅ | ✅ | 执行预设运动动作 |
| `do_dog_behavior` | ✅ | ✅ | 执行拟生物行为 |
| `smart_action` | ✅ | ✅ | 智能动作（AI 驱动） |
| `set_motion_params` | ✅ | ✅ | 设置运动参数 |
| `set_fan` | ✅ | ✅ | 风扇控制（散热） |
| `on_patrol` | ❌ | ✅ | 巡逻模式 |
| `phone_call` | ❌ | ✅ | 通话功能 |
| `watch_dog` | ❌ | ✅ | 看门狗/守护模式 |

---

## 二、可用运动动作（Available Actions）

通过 `do_action` 技能执行，参数为 `{"action_id": <id>}`。

| action_id | 动作名称 | 说明 |
|-----------|---------|------|
| 0 | EStop | 紧急停止 |
| 1 | Wake | 唤醒 |
| 2 | Get down | 趴下 |
| 3 | Recovery stand | 恢复站立 |
| 4 | Move | 移动（站立并准备行走） |
| 5 | Sit down | 坐下 |
| 6 | Soft stop | 软停止 |
| 257 | Jump | 跳跃 |
| 258 | Jump round | 原地跳转 |
| 259 | Jump forward | 向前跳 |
| 260 | Back flip | 后空翻 |
| 261 | Front flip | 前空翻 |
| 262 | Left flip | 左空翻 |
| 263 | Right flip | 右空翻 |
| 273 | Sway | 摇摆 |
| 274 | Adjust center of mass | 调整重心 |
| 275 | Back stand | 后仰站立 |
| 276 | Front stand | 前倾站立 |
| 277 | Left stand | 左倾站立 |
| 278 | Right stand | 右倾站立 |
| 513 | Pee | 撒尿 |
| 514 | Shake hand | 握手 |
| 515 | Knock | 敲门 |
| 516 | Kick | 踢腿 |
| 545 | Coax | 撒娇 |

---

## 三、扩展动作（Ext Actions）

通过 `do_action` 技能执行，参数为 `{"action_id": <id>}`。共 134 个扩展动作。

| action_id | 动作名称 | 中文说明 |
|-----------|---------|---------|
| 20736 | stand | 站立 |
| 20737 | recovery_pose | 恢复姿态 |
| 20738 | half_sit | 半坐 |
| 20739 | lie_on_elbows | 趴肘 |
| 20740 | stand_high | 高站 |
| 20741 | recovery_high_pose | 恢复高姿态 |
| 20742 | prepare_flip_x | 准备前/后翻 |
| 20743 | prepare_flip_y | 准备左/右翻 |
| 20481 | shake_self | 抖动身体 |
| 20482 | fast_rotate | 快速旋转 |
| 20483 | wag_tail | 摇尾巴 |
| 20484 | prostrate | 匍匐 |
| 20485 | eager | 急切/兴奋 |
| 20486 | ask_for_play | 求玩耍 |
| 20487 | enjoy_being_touched | 享受抚摸 |
| 20488 | sniff_left | 左嗅 |
| 20489 | sniff_right | 右嗅 |
| 20490 | rear_strech | 后腿伸展 |
| 20491 | front_strech | 前腿伸展 |
| 20492 | sphinx_lie | 狮身人面卧 |
| 20493 | sphinx_left_lie | 狮身人面左卧 |
| 20494 | sphinx_right_lie | 狮身人面右卧 |
| 20496 | check_front_leg | 检查前腿 |
| 20497 | check_fr_leg | 检查右前腿 |
| 20498 | check_fl_leg | 检查左前腿 |
| 20499 | explore_road_yaw | 探路（偏航） |
| 20500 | explore_road_roll | 探路（翻滚） |
| 20501 | search_env_yaw | 搜索环境（偏航） |
| 20502 | search_env_roll | 搜索环境（翻滚） |
| 20503 | front_rear_strech | 前后伸展 |
| 20504 | push_up | 俯卧撑 |
| 20505 | nod_head | 点头 |
| 20506 | shake_head | 摇头 |
| 20507 | nod_head_twice | 点头两次 |
| 20508 | shake_head_twice | 摇头两次 |
| 20509 | shit | 拉便便 |
| 20510 | bow | 鞠躬 |
| 20511 | stand_at_ease | 稍息 |
| 20512 | confused | 困惑 |
| 20513 | bark | 吠叫 |
| 20514 | swim | 游泳 |
| 20515 | rub_eyes | 揉眼睛 |
| 20516 | point_to_sky_left | 左指天 |
| 20517 | point_to_sky_right | 右指天 |
| 20518 | sniff_left_slow | 慢速左嗅 |
| 20519 | sniff_right_slow | 慢速右嗅 |
| 20520 | push_ahead | 向前推 |
| 20521 | look_around | 环顾四周 |
| 20522 | look_around_2 | 环顾四周 2 |
| 20523 | look_around_3 | 环顾四周 3 |
| 20524 | step_forward | 向前一步 |
| 20525 | rotate_180 | 旋转180° |
| 20526 | rotate_-180 | 反向旋转180° |
| 20527 | search_tag | 搜索标记 |
| 20528 | step_back | 后退一步 |
| 20529 | dance_4x1500 | 舞蹈（4拍x1500ms） |
| 20530 | cute | 卖萌 |
| 20531 | stick | 粘人 |
| 20532 | sniff_ahead | 向前嗅 |
| 20533 | sniff_ahead_3 | 向前嗅 3 |
| 20534 | affection | 撒娇 |
| 20535 | look_around_5 | 环顾四周 5 |
| 20536 | look_around_6 | 环顾四周 6 |
| 20537 | look_around_7 | 环顾四周 7 |
| 20538 | body_tag_search | 身体标签搜索 |
| 20539 | think | 思考 |
| 20540 | chatting | 聊天 |
| 20541 | shake_hand_2 | 握手 2 |
| 20542 | wave_hand | 挥手 |
| 20543 | clap_hand | 拍手 |
| 20544 | chatting__1 | 聊天 1 |
| 20545 | chatting__2 | 聊天 2 |
| 20546 | thinking__1 | 思考 1 |
| 20547 | thinking__2 | 思考 2 |
| 20548 | talking | 说话 |
| 20549 | affection_7s | 撒娇（7秒） |
| 20550 | chatting_5s | 聊天（5秒） |
| 20551 | pee_2 | 撒尿 2 |
| 20552 | dance_9x1000 | 舞蹈（9拍x1000ms） |
| 20553 | lion_dance | 舞狮 |
| 20554 | wait_for_praise | 等待表扬 |
| 20555 | lucky_cat_1 | 招财猫 1 |
| 20556 | lucky_cat_2 | 招财猫 2 |
| 20557 | drama_hearing | 戏剧性倾听 |
| 20558 | jingle | 叮当 |
| 20559 | lucky_cat_3 | 招财猫 3 |
| 20560 | step_idle | 原地踏步 |
| 20561 | sway_front_back | 前后摇摆 |
| 20562 | front_strech_without_modelscale | 前腿伸展（无缩放） |
| 20563 | nod_with_beats | 随节拍点头 |
| 20564 | joy_walk | 欢乐行走 |
| 20565 | head_up_down | 抬头低头 |
| 20566 | dance_with_beats | 随节拍跳舞 |
| 20567 | shoulder_dance | 肩部舞蹈 |
| 20568 | dance_with_beatsx4 | 随节拍跳舞 x4 |
| 20569 | be_sleepy | 犯困 |
| 20570 | flex_muscles | 秀肌肉 |
| 20571 | stand_at_attention | 立正 |
| 20572 | nod_off | 打瞌睡 |
| 20573 | long_fart | 长放屁 |
| 20574 | short_fart | 短放屁 |
| 20575 | sniff_up | 向上嗅 |
| 20576 | bark_bark | 汪汪叫 |
| 20577 | observe | 观察 |
| 20578 | coquetry_1 | 撒娇 1 |
| 20579 | coquetry_2 | 撒娇 2 |
| 20580 | recovery_pose_with_nod_off | 恢复姿态（带打瞌睡） |
| 20581 | look_down | 低头看 |
| 20582 | snuggle_y | 依偎（Y轴） |
| 20583 | snuggle_x | 依偎（X轴） |
| 20584 | touch_happy | 摸摸开心 |
| 20585 | jump_forward | 向前跳 |
| 20589 | bored_half_sit | 无聊半坐 |
| 20589 | duck_walk | 鸭子步 |
| 20590 | listen_left | 左耳倾听 |
| 20591 | listen_right | 右耳倾听 |
| 20592 | listen_right_and_left | 左右倾听 |
| 20593 | draw_heart | 画爱心 |
| 20594 | good_night_wave | 晚安挥手 |
| 20595 | cry | 哭泣 |
| 20596 | encourage | 鼓励 |
| 20597 | explore_new_home | 探索新家 |
| 20598 | cooking_right_and_left | 左右翻炒 |
| 20599 | cooking_right_and_left_with_recovery | 左右翻炒（带恢复） |
| 20600 | tossing | 抛物 |
| 20601 | tossing_left | 左抛 |
| 20602 | tossing_right | 右抛 |
| 20603 | eating_swallow | 吃东西吞咽 |
| 20604 | brush_teeth_right_start | 右刷牙开始 |
| 20605 | opening_cute_dog | 开场卖萌 |
| 20606 | brush_teeth_left | 左刷牙 |
| 20607 | eating_only | 只吃东西 |
| 20608 | brush_teeth_right | 右刷牙 |

---

## 四、狗行为（Dog Behaviors）

通过 `do_dog_behavior` 技能执行，参数为行为名称字符串。共 39 个行为。

| 行为名称 | 中文说明 |
|---------|---------|
| confused | 困惑 |
| confused_again | 再次困惑 |
| recovery_balance_stand_1 | 恢复平衡站立 1 |
| recovery_balance_stand | 恢复平衡站立 |
| recovery_balance_stand_high | 恢复高平衡站立 |
| force_recovery_balance_stand | 强制恢复平衡站立 |
| force_recovery_balance_stand_high | 强制恢复高平衡站立 |
| recovery_dance_stand_and_params | 恢复舞蹈站立（带参数） |
| recovery_dance_stand | 恢复舞蹈站立 |
| recovery_dance_stand_high | 恢复高舞蹈站立 |
| recovery_dance_stand_high_and_params | 恢复高舞蹈站立（带参数） |
| recovery_dance_stand_pose | 恢复舞蹈站立姿态 |
| recovery_dance_stand_high_pose | 恢复高舞蹈站立姿态 |
| recovery_stand_pose | 恢复站立姿态 |
| recovery_stand_high_pose | 恢复高站立姿态 |
| wait | 等待 |
| cute | 卖萌 |
| cute_2 | 卖萌 2 |
| enjoy_touch | 享受抚摸 |
| very_enjoy | 非常享受 |
| eager | 急切 |
| excited_2 | 兴奋 2 |
| excited | 兴奋 |
| crawl | 匍匐前进 |
| stand_at_ease | 稍息 |
| rest | 休息 |
| shake_self | 抖动身体 |
| back_flip | 后空翻 |
| front_flip | 前空翻 |
| left_flip | 左空翻 |
| right_flip | 右空翻 |
| express_affection | 表达感情 |
| yawn | 打哈欠 |
| dance_in_place | 原地跳舞 |
| shake_hand | 握手 |
| wave_hand | 挥手 |
| draw_heart | 画爱心 |
| push_up | 俯卧撑 |
| bow | 鞠躬 |

---

## 五、底层运动控制参数

通过 `/alphadog_node/set_*` 话题直接设置。

| 话题 | 功能 |
|------|------|
| `set_velocity` | 设置移动速度（线速度 + 角速度） |
| `set_gait` | 设置步态（走/跑/小跑等） |
| `set_body_position` | 设置身体位置 |
| `set_rpy` | 设置身体姿态（Roll/Pitch/Yaw） |
| `set_foot_height` | 设置抬脚高度 |
| `set_friction` | 设置摩擦系数 |
| `set_jump_angle` | 设置跳跃角度 |
| `set_jump_distance` | 设置跳跃距离 |
| `set_swing_duration` | 设置摆腿时长 |
| `set_swaying_duration` | 设置摇摆时长 |
| `set_swing_traj_type` | 设置摆腿轨迹类型 |
| `set_collision_protect` | 碰撞保护开关 |
| `set_decelerate` | 减速设置 |
| `set_free_leg` | 释放某条腿 |
| `set_dynamic_params` | 动态参数设置 |
| `set_model_scale` | 模型缩放 |
| `set_ground_model` | 地面模型 |
| `set_controller_type` | 控制器类型 |
| `set_user_mode` | 用户模式 |
| `set_led_screen` | LED 屏幕控制 |
| `set_velocity_decay` | 速度衰减 |
| `set_remote_controller_config` | 遥控器配置 |

---

## 六、底层服务

通过 `rosservice call` 调用的底层服务。

| 服务 | 功能 |
|------|------|
| `/alphadog_node/get_actions` | 获取可用动作列表 |
| `/alphadog_node/power_off` | 关机 |
| `/alphadog_node/set_dynamic_dance` | 设置动态舞蹈 |
| `/alphadog_node/set_foot_traj` | 设置足端轨迹 |
| `/alphadog_node/set_joints_action` | 设置关节动作 |
| `/alphadog_node/set_leg_traj` | 设置腿部轨迹 |
| `/alphadog_node/set_parameters` | 设置参数 |
| `/alphadog_node/start_record` | 开始录制动作 |
| `/alphadog_node/finish_record` | 完成录制 |
| `/alphadog_node/save_record` | 保存录制 |
| `/alphadog_node/delete_record` | 删除录制 |
| `/alphadog_node/save_com` | 保存质心数据 |

---

## 七、动作录制与回放

支持通过 Action 接口录制、保存、回放和删除自定义动作。

| Action 话题 | 功能 |
|-------------|------|
| `/alphadog_node/do_action` | 执行动作 |
| `/alphadog_node/start_record_action` | 开始录制动作 |
| `/alphadog_node/finish_record_action` | 完成录制 |
| `/alphadog_node/save_record_action` | 保存录制的动作 |
| `/alphadog_node/delete_record_action` | 删除录制的动作 |

---

## 八、状态监控

| 话题 | 内容 |
|------|------|
| `/alphadog_node/robot_ready` | 机器人就绪状态 |
| `/alphadog_node/boot_up_state` | 开机状态 |
| `/alphadog_node/body_status` | 身体状态 |
| `/alphadog_node/dog_ctrl_state` | 控制状态机 |
| `/alphadog_node/dog_ctrl_config` | 控制配置 |
| `/alphadog_node/robot_ctrl_status` | 机器人控制状态 |
| `/alphadog_node/joint_states` | 关节状态 |
| `/alphadog_node/imu` | IMU 惯性测量 |
| `/alphadog_node/ground_status` | 地面接触状态 |
| `/alphadog_node/ext_force_status` | 外力检测 |
| `/alphadog_node/spi_status` | SPI 总线状态 |
| `/alphadog_node/spine_info` | 脊椎板信息 |
| `/alphadog_node/robot_system_info` | 系统信息 |
| `/alphadog_node/wifi` | WiFi 信息 |
| `/alphadog_aux/battery_state` | 电池状态 |
| `/alphago_slam/slam_pose` | SLAM 定位 |

---

## 九、外部连接

| 模块 | 说明 |
|------|------|
| **蓝牙 BLE** | `/alphadog_aux/ble_gatt_server/` — 手机 App 通过蓝牙连接控制 |
| **遥控器** | `/alphadog_aux/teleop_robot/` — 遥控器/手柄控制 |
| **ROSBridge** | `/x_rosbridge/` — WebSocket 接口，支持 Web/App 远程调用 |
| **OTA 升级** | `/alpha_ota/` — 空中升级（版本检查、下载、WiFi 管理） |

---

## 十、当前设备状态

| 项目 | 值 |
|------|-----|
| 电池电压 | 28.62V |
| 电池温度 | 25.5°C |
| 电量百分比 | 100% |
| 充电状态 | 充电中（status=2） |
| 设计容量 | 4.0Ah |

---

## 调用示例

### 执行"趴下"动作

```python
import json
import rospy
import actionlib
from agent_msgs.msg import ExecuteAction, ExecuteGoal

rospy.init_node('get_down')
cli = actionlib.SimpleActionClient('/agent_skill/do_action/execute', ExecuteAction)
cli.wait_for_server(timeout=rospy.Duration(3.0))

goal = ExecuteGoal()
goal.invoker = 'my_app'
goal.invoke_priority = 25
goal.hold_time = 3.0
goal.args = json.dumps({'action_id': 2})  # Get down = 趴下

cli.send_goal(goal)
cli.wait_for_result(timeout=rospy.Duration(10.0))
print(cli.get_result())
```

### 执行"握手"行为

```python
import json
import rospy
import actionlib
from agent_msgs.msg import ExecuteAction, ExecuteGoal

rospy.init_node('shake_hand')
cli = actionlib.SimpleActionClient('/agent_skill/do_dog_behavior/execute', ExecuteAction)
cli.wait_for_server(timeout=rospy.Duration(3.0))

goal = ExecuteGoal()
goal.invoker = 'my_app'
goal.invoke_priority = 25
goal.hold_time = 5.0
goal.args = json.dumps({'behavior': 'shake_hand'})

cli.send_goal(goal)
cli.wait_for_result(timeout=rospy.Duration(10.0))
print(cli.get_result())
```
