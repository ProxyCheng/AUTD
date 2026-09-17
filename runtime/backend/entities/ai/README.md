# LimboAI 行为树 —— 速查与查证

> AGENTS.md §5.3 放**铁律**(必须遵守);本文件放**查得到的细节**(节点清单、`.tres` 写法、怎么查证、怎么验证)。
> 节点数据由 Godot 4.8.dev(自编译)+ LimboAI v1.8 GDExtension 的 ClassDB **实测导出**,不是凭记忆写的。
> **换插件版本后必须按 §5 重新导出核对** —— 记忆会错(例:`BTRepeat` 只有 `forever`,没有 `times`/`abort_on_failure`)。

## 1. 铁律

1. **用节点表达控制流,不要用数据协议模拟它。**
   "失败就继续"用 `BTSelector`;"可做可不做"用 `BTAlwaysSucceed` **装饰**;"反复重跑"用 `BTRepeat`;"卡住就放弃"用 `BTTimeLimit`。
   - 反面教材(已修,勿重犯):①让叶子返回 SUCCESS 只为让整棵树结束,靠"树死掉 → 重建"达成循环;②用 `@export optional` 把叶子的 FAILURE 翻成 SUCCESS,使同一叶子对不同调用方承担两套矛盾契约。
   - 判据:**同一条逻辑换个调用方就要换语义 ⇒ 它该是树上的结构,不是叶子上的开关。**
2. **装饰器必须装饰,不许当裸叶子挂在组合节点下。**
   `BTSelector[序列, BTAlwaysSucceed]` 是错的(Selector 在扮演装饰器,还留下一个唯一作用是返回 true 的占位节点),应写 `BTAlwaysSucceed(序列)`。
   天生不带子节点、作为"调用/占位"使用的只有 `BTSubtree`(调用另一棵树)与 `BTComment`。
3. **`BT.Status` 数值**:`FRESH = 0` / `RUNNING = 1` / `FAILURE = 2` / `SUCCESS = 3`。写断言、读日志、打印状态时别猜。
4. **`BTSubtree` 会开一层新黑板作用域**(它继承 `BTNewScope`):子树内写的键**不会**漏到外面;要往外传的结果不能只放黑板。
5. **行为逻辑优先落 `.tres`**,不在脚本里 `BehaviorTree.new()` 手拼(含 `preload` 编译环的例外,见 AGENTS.md §5.3)。

## 2. 什么时候用哪个

| 想要 | 用什么 | 关键属性 |
|---|---|---|
| 依次做 A、B、C,任一失败即整体失败 | `BTSequence` | — |
| 依次试 A、B、C,任一成功即整体成功(含"失败就继续") | `BTSelector` | — |
| 每 tick 重新评估该从哪个孩子继续 | `BTDynamicSelector` / `BTDynamicSequence` | — |
| 并行跑多个孩子,按成功/失败数收束 | `BTParallel` | `num_successes_required` `num_failures_required` `repeat` |
| 随机顺序 / 按权重选择 | `BTRandomSelector` `BTRandomSequence` `BTProbabilitySelector` | `abort_on_failure` |
| **无论孩子成败都算成功**("这一步可做可不做") | `BTAlwaysSucceed` **装饰**那段 | — |
| 无论孩子成败都算失败 | `BTAlwaysFail` | — |
| 反转结果 | `BTInvert` | — |
| 反复跑 / 永远跑 / 跑到成功 / 跑到失败 | `BTRepeat` / `BTRepeatUntilSuccess` / `BTRepeatUntilFailure` | `BTRepeat.forever` |
| 超时即失败 | `BTTimeLimit` | `time_limit` |
| 最多跑 N 次 | `BTRunLimit` | `run_limit` `count_policy` |
| 等真实时长 / 等 N tick / 随机时长 | `BTDelay` / `BTWait` / `BTWaitTicks` / `BTRandomWait` | `seconds` / `duration` / `num_ticks` / `min_duration` `max_duration` |
| 冷却期内不重复跑 | `BTCooldown` | `duration` `cooldown_state_var` `start_cooled` `trigger_on_failure` |
| 按概率决定跑不跑 | `BTProbability` | `run_chance` |
| 遍历数组每个元素 | `BTForEach` | `array_var` `save_var` |
| **调用另一棵树(复用)** | `BTSubtree` | `subtree`;注意它开新作用域(§1.4) |
| 条件判断 | `BTCheckVar` / `BTCheckAgentProperty` / `BTCheckTrigger` | `variable` `check_type` `value` / `property` |
| 写黑板 / 写代理属性 / 调方法 / 求表达式 | `BTSetVar` / `BTSetAgentProperty` / `BTCallMethod` / `BTEvaluateExpression` | `variable` `operation` `value` … |
| 在树里留说明 | `BTComment` | — |
| 恒失败(占位/测试) | `BTFail` | — |
| 调试输出 | `BTConsolePrint` | `text` `bb_format_parameters` |
| 动画(本项目**不用**:动画归 model,见 AGENTS.md §6) | `BTPlayAnimation` `BTPauseAnimation` `BTStopAnimation` `BTAwaitAnimation` | — |

## 3. 全部 48 个 `BT*` 节点(ClassDB 实测)

「自有属性」= 该类自己的存盘字段(不含继承来的);**所有任务都从 `BTTask` 继承 `children` / `_enabled` / `custom_name`** —— 这也是为什么装饰器的子节点字段和组合节点**同名**,都叫 `children`。

**基类**

| 类 | 父类 | 自有属性 |
|---|---|---|
| `BT` | `Resource` | — |
| `BTTask` | `BT` | `_enabled` `children` `custom_name` |
| `BTComposite` | `BTTask` | — |
| `BTDecorator` | `BTTask` | — |
| `BTAction` | `BTTask` | — |
| `BTCondition` | `BTTask` | — |

**组合节点(孩子按各自规则执行)**

| 类 | 父类 | 自有属性 |
|---|---|---|
| `BTSequence` | `BTComposite` | — |
| `BTSelector` | `BTComposite` | — |
| `BTDynamicSequence` | `BTComposite` | — |
| `BTDynamicSelector` | `BTComposite` | — |
| `BTParallel` | `BTComposite` | `num_failures_required` `num_successes_required` `repeat` |
| `BTRandomSequence` | `BTComposite` | — |
| `BTRandomSelector` | `BTComposite` | — |
| `BTProbabilitySelector` | `BTComposite` | `abort_on_failure` |

**装饰器(改写其唯一子节点的结果;必须有子节点)**

| 类 | 父类 | 自有属性 |
|---|---|---|
| `BTAlwaysSucceed` | `BTDecorator` | — |
| `BTAlwaysFail` | `BTDecorator` | — |
| `BTInvert` | `BTDecorator` | — |
| `BTRepeat` | `BTDecorator` | `forever` |
| `BTRepeatUntilSuccess` | `BTDecorator` | — |
| `BTRepeatUntilFailure` | `BTDecorator` | — |
| `BTTimeLimit` | `BTDecorator` | `time_limit` |
| `BTRunLimit` | `BTDecorator` | `run_limit` `count_policy` |
| `BTDelay` | `BTDecorator` | `seconds` |
| `BTForEach` | `BTDecorator` | `array_var` `save_var` |
| `BTCooldown` | `BTDecorator` | `duration` `cooldown_state_var` `process_pause` `start_cooled` `trigger_on_failure` |
| `BTProbability` | `BTDecorator` | `run_chance` |
| `BTNewScope` | `BTDecorator` | `blackboard_plan` |

**动作**

| 类 | 父类 | 自有属性 |
|---|---|---|
| `BTWait` | `BTAction` | `duration` |
| `BTWaitTicks` | `BTAction` | `num_ticks` |
| `BTRandomWait` | `BTAction` | `min_duration` `max_duration` |
| `BTFail` | `BTAction` | — |
| `BTSetVar` | `BTAction` | `operation` `value` `variable` |
| `BTSetAgentProperty` | `BTAction` | `operation` `property` `value` |
| `BTCallMethod` | `BTAction` | `method` `node` `args` `args_include_delta` `result_var` |
| `BTEvaluateExpression` | `BTAction` | `expression_string` `input_names` `input_values` `input_include_delta` `node` `result_var` |
| `BTConsolePrint` | `BTAction` | `text` `bb_format_parameters` |
| `BTPlayAnimation` | `BTAction` | `animation_name` `animation_player` `await_completion` `blend` `from_end` `speed` |
| `BTPauseAnimation` | `BTAction` | `animation_player` |
| `BTStopAnimation` | `BTAction` | `animation_name` `animation_player` `keep_state` |
| `BTAwaitAnimation` | `BTAction` | `animation_name` `animation_player` `max_time` |

**条件**

| 类 | 父类 | 自有属性 |
|---|---|---|
| `BTCheckVar` | `BTCondition` | `variable` `check_type` `value` |
| `BTCheckAgentProperty` | `BTCondition` | `property` `check_type` `value` |
| `BTCheckTrigger` | `BTCondition` | `variable` |

**树 / 调用 / 运行时**

| 类 | 父类 | 自有属性 |
|---|---|---|
| `BTSubtree` | `BTNewScope` | `subtree`(另继承 `blackboard_plan`) |
| `BTComment` | `BTTask` | — |
| `BTPlayer` | `Node` | `behavior_tree` `blackboard_plan` `agent_node` `active` `update_mode` `monitor_performance` |
| `BTState` | `LimboState` | `behavior_tree` `success_event` `failure_event` `monitor_performance`(另继承 `LimboState.blackboard_plan`) |
| `BTInstance` | `RefCounted` | `monitor_performance` |

> 本项目**不用** `BTPlayer`/`BTState`(状态机)—— 实体侧由 `Creature` 持 `current_tree + bt_instance` 自行驱动,见 AGENTS.md §5.3。

## 4. `.tres` 序列化写法

- 脚本叶子写成 `sub_resource type="BTAction"` + `script = ExtResource(...)`(条件叶同理用 `type="BTCondition"`;自定义叶子若继承 `BTDecorator`,则用 `type="BTDecorator"`)。
- **子节点字段一律叫 `children`**(`Array`),装饰器与组合节点同名 —— 因为 `children` 定义在 `BTTask` 上。所以装饰器写成:

  ```
  [sub_resource type="BTAlwaysSucceed" id="BTAlwaysSucceed_shed"]
  children = [SubResource("BTSequence_shed")]
  ```

  组合节点写成:

  ```
  [sub_resource type="BTSequence" id="BTSequence_root"]
  children = [SubResource("A"), SubResource("B")]
  ```

- **引用另一棵树(`BTSubtree`)要三样**:`ext_resource` 指向 `.tres` + `sub_resource type="BTSubtree"` 里 `subtree = ExtResource(...)` + 一份 `blackboard_plan`:

  ```
  [ext_resource type="BehaviorTree" uid="uid://..." path="res://.../x.tres" id="1_x"]

  [sub_resource type="BTSubtree" id="BTSubtree_x"]
  subtree = ExtResource("1_x")
  blackboard_plan = SubResource("BlackboardPlan_x")
  ```

- 每棵树一个 `blackboard_plan`;根任务用 `root_task = SubResource(...)`。
- `description` 请写清这棵树的意图 —— 它是唯一能在编辑器里读到的**树级**文档(比在树里撒 `BTComment` 更合适)。

## 5. 怎么查证(不要猜属性名 / 枚举值)

**A. 项目内(推荐)**:godot-mcp 的 `get_class_api_metadata(class_name="BTSelector")` 读单个类的属性/方法/信号;或 `execute_editor_script` 跑 ClassDB:

```gdscript
for c: String in ClassDB.get_class_list():
	if c.begins_with("BT"):
		_custom_print(c, ClassDB.get_parent_class(c), ClassDB.class_get_property_list(c, false))
```

`class_get_property_list(类, false)` 的 `false` = **包含继承**(要"只看自有属性",拿父类列表相减)。
`execute_editor_script` 里不要对 `Resource`/`RefCounted` 调 `free()`(会静默中止、输出为空);返回值一律用 `_custom_print`。

**B. 外部**:LimboAI 文档 <https://limboai.readthedocs.io/>(节点参考)、源码 <https://github.com/limboai/limboai>。

## 6. 怎么验证一次改动

**结构与行为一起验,别只看结构** —— 一个"不 tick 子节点、直接返回 SUCCESS"的装饰器写法能骗过纯结构检查。
做法:写一个继承 `SceneTree` 的脚本,用 headless 跑:

```
<godot.exe> --path <项目> --headless --script <临时目录>/verify_ai.gd
```

脚本在 `_init()` 里做三件事,最后打 `RESULT failed=N` 并 `quit()`:

1. **读结构** —— `ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as BehaviorTree`,检查 `root_task` 的类型与 `get_child_count()`。
2. **真跑行为** —— `tree.instantiate(agent, agent.blackboard, agent, agent)`(需非空 scene root),然后循环 `update(0.05)` 直到非 RUNNING,断言副作用(如"3 件原木真的进了仓")。
3. **通用守卫** —— 任何"必须有子节点"的装饰器若被当**裸叶子**挂在组合节点下,直接判失败。类名单:
   `BTAlwaysSucceed` `BTAlwaysFail` `BTInvert` `BTRepeat` `BTRepeatUntilSuccess` `BTRepeatUntilFailure` `BTTimeLimit` `BTRunLimit` `BTDelay` `BTForEach` `BTCooldown` `BTProbability` `BTNewScope`;
   **例外**(天生不带子节点):`BTSubtree`、`BTComment`。
   注意用 `get_class()` 取类名比对字符串,而不是 `is` —— 这样脚本不会因插件缺类而编译失败。

改完**还要跑一次主场景**:

```
<godot.exe> --path <项目> --headless --quit-after 240 res://runtime/frontend/scenes/battle.tscn
```

只 `ResourceLoader.load` 一棵树**不会编译它引用的叶子脚本**,曾因此漏掉真实的启动崩溃(见 `f17c374`)。

## 7. 本项目的树与黑板键

| 树 | 形态 | 用途 |
|---|---|---|
| `idle.tres` | `BTRepeat(forever)[ BTSequence[ shed_subtree, WanderTask ] ]` | 空闲:每轮先试着卸掉用不上的随身物品,再原地游荡;刻意永不结束(派活走 `begin_tree()`,不依赖本树结束) |
| `shed_load.tres` | `BTAlwaysSucceed[ BTSequence[ FindDepositBagTask, MoveToTargetTask(deposit_access), DepositLoadTask ] ]` | 共享"卸货"子树:能卸就卸,无处可收也算已了事 |
| `transport_haul.tres` | `BTSequence[ shed_subtree, move_take, TakeFromBagTask, move_put, PutToBagTask ]` | 搬运一趟 |
| `man_building.tres` | `BTSequence[ shed_subtree, PlanReturnTask, move_return, ReturnToolTask, BTAlwaysSucceed[ BTSequence[ move_tool, TakeFromBagTask ] ], move_work, ProvideWorkloadTask ]` | 顶岗;取工具那一对由 `BTAlwaysSucceed` 包住 —— 取不到就空手开工 |
| `enemy_siege.tres` | `BTSequence[ MoveToTargetTask, EnemyAttackTask ]` | 敌人进攻:走向主基地,抵达即自毁 |

黑板键(经实体自己的 `Blackboard` 跨叶子传参):
`&target_position` `&work_building` `&source_bag` `&dest_bag` `&carry_amount` `&take_access` `&put_access` `&tool_access` `&return_access` `&return_bag` `&deposit_type` `&deposit_bag` `&deposit_access` `&wander_anchor`;
脚本内常量键:`ProvideWorkloadTask.BB_BUILDING`、`TransportTask.BB_ITEM_TYPE`、`TransportTask.BB_SOURCE_BAG` 等。
