# 蔚蓝机器狗 ROS 通讯与动作调用开发指南

> 面向开发者：希望通过 ROS 让机器狗执行动作  
> 结论先行：**优先调用 `do_dog_behavior`，必要时再调用 `do_action`**。

---

## 1. 该调用 `do_action` 还是 `do_dog_behavior`？

## 推荐顺序

1. **优先 `do_dog_behavior`**（高层行为，稳定性更好）
2. 需要精细控制或行为库里没有时，使用 **`do_action`**（底层动作）

## 对比

| 维度 | `do_dog_behavior` | `do_action` |
|---|---|---|
| 输入 | `behavior` 字符串 | `action_id` 数字 |
| 适用 | 业务动作（挥手、画爱心、鞠躬等） | 底层动作编排、调试、新动作验证 |
| 风险 | 低（通常封装了前置姿态） | 高（容易命中前置条件失败） |
| 推荐级别 | **首选** | 按需使用 |

你可以理解为：
- `do_dog_behavior` = “产品级动作接口”
- `do_action` = “工程级底层接口”

---

## 2. 用 Python 还是其他语言？

## 推荐

- 在 ROS 体系内开发：**Python（`rospy + actionlib`）优先**
- 原因：
  - 上手快，调试效率高
  - 你项目里已有样例：`agentos_examples/python/skill_contrl.py`、`agentos_examples/python/hold_skill.py`
  - 与 `agent_msgs`、Action/Service 生态配套

## 其他语言建议

- C++：性能更强，但开发成本高，适合核心控制节点
- 非 ROS 客户端（Web/App）：建议走 ROSBridge/SDK 网关，不直接碰 ROS Topic/Action 细节

---

## 3. Python 最小可用示例

## 3.1 调用 `do_dog_behavior`（推荐）

```python
#!/usr/bin/env python3
import json
import rospy
import actionlib
from agent_msgs.msg import ExecuteAction, ExecuteGoal

rospy.init_node("demo_behavior")
cli = actionlib.SimpleActionClient("/agent_skill/do_dog_behavior/execute", ExecuteAction)
if not cli.wait_for_server(timeout=rospy.Duration(3.0)):
    raise RuntimeError("do_dog_behavior action server not ready")

goal = ExecuteGoal()
goal.invoker = "my_app"
goal.invoke_priority = 50
goal.hold_time = 10.0
goal.args = json.dumps({"behavior": "draw_heart"})  # 例如画爱心

cli.send_goal(goal)
if not cli.wait_for_result(timeout=rospy.Duration(20.0)):
    raise RuntimeError("behavior timeout")

res = cli.get_result()
print("result:", res)
```

## 3.2 调用 `do_action`（底层）

```python
#!/usr/bin/env python3
import json
import rospy
import actionlib
from agent_msgs.msg import ExecuteAction, ExecuteGoal

rospy.init_node("demo_action")
cli = actionlib.SimpleActionClient("/agent_skill/do_action/execute", ExecuteAction)
if not cli.wait_for_server(timeout=rospy.Duration(3.0)):
    raise RuntimeError("do_action action server not ready")

goal = ExecuteGoal()
goal.invoker = "my_app"
goal.invoke_priority = 50
goal.hold_time = 10.0
goal.args = json.dumps({"action_id": 20593})  # 例如 draw_heart 底层动作

cli.send_goal(goal)
if not cli.wait_for_result(timeout=rospy.Duration(20.0)):
    raise RuntimeError("action timeout")

res = cli.get_result()
print("result:", res)
```

---

## 4. 开发流程建议（落地顺序）

1. 先用 `do_dog_behavior` 跑通业务流程（成功率优先）
2. 再用 `do_action` 做细粒度控制或扩展动作验证
3. 对失败项检查：
   - 前置姿态是否满足（常见提示：先 `get-down/recovery-stand/move`）
   - 是否处于急停/未 boot 完成状态
   - 是否需要冷却/电量门槛
4. 批量验证建议配合你已有脚本：
   - `scripts/probe_behaviors.sh`
   - `scripts/probe_actions.sh`
   - `scripts/probe_ext_actions.sh`

---

## 5. 常见误区

- 误区 1：所有动作都走 `do_action`  
  - 正解：业务动作优先 `do_dog_behavior`，底层才用 `do_action`

- 误区 2：只看“命令发出成功”  
  - 正解：必须看 `execute/result` 的状态与返回文本

- 误区 3：忽略运行时状态  
  - 正解：先检查就绪/急停/电量/姿态，再下发动作

---

## 6. 一句话建议

如果你的目标是“稳定地让狗执行动作”，请采用：

**Python + `do_dog_behavior` 为主，`do_action` 为辅，状态订阅做保护。**

