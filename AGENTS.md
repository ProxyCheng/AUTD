# AGENTS.md — AUTD(Godot 项目约束文件)

> 本文件依据现有代码(2026-09 快照)提炼,是此仓库 **唯一** 的架构/代码约束来源。
> 任何 AI 助手或开发者在本仓库新增/修改代码前必须先读本文件,并遵循其中全部规则。
> 存量代码中与本文件冲突的地方(如 `runtime/frontend/controllers/camera_controller.gd` 的 `-> void`、无 `in_` 前缀形参、遗留的 `@export jack`)属于历史遗留,**新代码不得沿用**,重构时应向本文件收敛。

- 引擎:GDScript / Godot 4.8,Forward+,Jolt Physics
- 主场景:`res://runtime/frontend/scenes/battle.tscn`(`project.godot` 中 `run/main_scene`)
- 坐标系:y=0 地平面,网格单位 1×1;后端用 `Vector2(x, z)`,前端转 `Vector3(x, 0, z)`
- Godot 编辑器为**本地自编译版本**,可执行文件:`E:\Projects\CPP\godot\bin\godot.windows.editor.dev.x86_64.exe`(日常用 `--path E:\Projects\Godot\autd --editor` 启动);命令行跑/诊断主场景可直接调该 exe 加 `--path` 与场景路径,绕过编辑器内存/缓存

---

## 1. 总体架构:前后端分离

仓库按"纯逻辑 / 表现 / 编辑工具"切成三层,**依赖单向**,不可反向:

```
runtime/backend   ← 玩法模拟(纯逻辑,无渲染、无输入、无 UI)
runtime/frontend  ← 表现层(场景、Actor、模型、输入模式、UI)
editor/           ← 关卡数据编辑工具(@tool,只在编辑器内运行)
```

| 层 | 职责 | 可以 | 禁止 |
|---|---|---|---|
| **backend** | 世界状态本体 + 每帧 `tick()` 模拟 | 读写自身状态、发信号、被 frontend 调用 | ❌ `load()`/引用任何 `res://runtime/frontend/*`、`res://editor/*`;❌ 使用 `get_viewport()`、`Input`、`Camera3D` 等表现 API;❌ 持有视觉节点;❌ 引用音频(音频资源、`AudioManager`)——音频一律属 frontend(§5.7) |
| **frontend** | 读取 backend 状态、连接 backend 信号做表现;接收输入后**调用 backend 公开方法**改状态 | 引用 backend 的类与节点;播放音频(§5.7) | ❌ 复制玩法规则/状态(如血量、寻路)到自己内部;❌ 不通过 backend 方法直接改后端状态 |
| **editor** | 编辑 `*.tres` 数据资源 | 引用 backend 的 `*Data` 类与 frontend 的模型场景 | ❌ 被 runtime 反向引用 |

**状态流约定:**
- 后端每帧被推进:`level_actor.gd` 里 `level.tick(in_delta * speed)`,逐层下发 `Map.tick → Cell.tick → Building.tick`、`Room.tick → Entity.tick → 当前行为树 update`。
- backend 状态变化通过信号向外广播(`cells_changed` / `entities_changed` / `position_changed` / `state_changed`…),frontend 只依赖这些信号刷新表现。
- frontend 的输入意图(如 `BuildingMode` 点格子)最终调用 backend 方法(`map.place_building(axis, data)`)落状态,再由信号回流刷新。
- 可观察属性一律走"getter/setter + guard + 发信号"模式(见 §5.4),而不是轮询。

---

## 2. 目录结构与存放规则

```
autd/
├─ project.godot          # 引擎配置(主场景、输入映射)。少手改
├─ default_bus_layout.tres # 音频总线布局:Master/SFX/Music/Ambience(§5.7)
├─ icon.svg
├─ runtime/
│  ├─ backend/            # 纯逻辑。extends Node / Resource
│  │  ├─ level.gd map.gd room.gd land.gd cell.gd
│  │  ├─ bag.gd main_base_bag.gd logistics.gd damage.gd
│  │  ├─ buildings/       # 具体建筑:<type>.gd(building.gd / crossbow.gd / main_base.gd / enemy_spawner.gd)
│  │  ├─ data/            # 纯数据 Resource 类:*_data.gd
│  │  └─ entities/        # 具体实体:<type>.gd(entity/creature/enemy/labor/slime/arrow.gd)
│  │     └─ ai/           # LimboAI 行为树:ai/tasks/<type>_task.gd(class_name <Type>Task)+ *.tres 树资源 + README.md(节点速查/查证/验证)
│  ├─ configs/            # *.tres 关卡/初始数据文件(如 level0.tres)
│  └─ frontend/           # 表现层
│     ├─ scenes/          # 顶层组合场景 + 其根脚本(battle.tscn、level_actor.gd)
│     ├─ actors/          # backend 对象的可视化镜像:<object>_actor.gd + .tscn
│     ├─ modes/           # 输入模式 Mode 子类,每个 mode 一个文件 + 一个场景节点
│     ├─ controllers/     # camera_controller.gd light_controller.gd audio_manager.gd(摄像机/灯光/音频)
│     ├─ ui/              # Control 组合(building_card.gd/.tscn)
│     ├─ audio/           # 音频:audio_library.gd(id→流表)+ sfx/ music/ ambience/ + LICENSES/
│     ├─ models/          # 美术资源,按类型分子目录
│     │  ├─ buildings/<type>/<type>.tscn + <type>_model.gd
│     │  ├─ entities/<type>/<type>.tscn + <type>_model.gd
│     │  └─ tools/<type>/<type>.fbx + <type>.blend(纯表现道具,无 backend 类)
│     └─ textures/        # land_<type>.png 等地形贴图
├─ editor/                # @tool 编辑器场景:cell_editor / map_editor / level_editor(.gd + .tscn)
├─ test/                  # headless 测试:ai_behavior_tree_test.gd(行为树结构/行为 + 装饰器守卫)
└─ addons/                # 第三方插件(不得手改)
```

**存放硬规则:**
1. **一个脚本文件 = 一个 `class_name` 全局类**,文件名 = 类名 snake_case(`LevelActor` → `level_actor.gd`)。
2. 新建 backend 类放 `runtime/backend/`,按上表归属子目录;**不要**把纯逻辑类放进 frontend,也不要让 backend 类带任何视觉节点。
3. 数据类定义统一在 `runtime/backend/data/`,`extends Resource` + `@tool`(`*.tres` 数据文件则放 `runtime/configs/`)。数据类是 backend 与 editor 的共同契约,字段用 `@export` 暴露。
4. 具体建筑/实体脚本按类型名放在 backend 对应目录,并由类型字符串**推导路径**实例化(见 §5.5),不要在代码里手写一长串绝对路径。
5. 新增建筑/实体类型时,backend 脚本与 frontend 模型场景**必须成对出现**并保持同名同路径,否则 `load()` 会失败(参考 §8 清单)。
6. `.tscn` 与同根脚本分离:可实例化的 Actor/UI 场景是一个文件夹内 `xxx.gd + xxx.tscn + xxx.gd.uid`;模型文件夹内含导入源(`.fbx/.blend`)与 `.import`、`.gd.uid`,全部提交,不提交 `.godot/`。
7. `runtime/frontend/modes/` 下是 `Mode` 子类;每个 mode 在 battle.tscn 的 `%modes` 下有一个**同名单节点**(`roaming`/`building`),靠节点 `name` 与 `set_mode(&"id")` 匹配,故 mode 场景节点名与 `&"id"` 必须一致。
8. 音频资源与音频代码**一律放 frontend**(资源表 `runtime/frontend/audio/` + 播放器 `runtime/frontend/controllers/audio_manager.gd`);backend 不得引用音频,发声只能由 frontend 监听 backend 信号后触发(§5.7)。

---

## 3. 命名规范

| 对象 | 规则 | 示例(取自现有代码) |
|---|---|---|
| 文件 | snake_case,与类名一致 | `building_actor.gd` `move_to_target_task.gd` |
| `class_name` | PascalCase | `Cell` `LevelActor` `MapEditor` `BuildingData` `MoveToTargetTask` |
| 变量/属性/局部量 | snake_case | `fire_timer` `move_speed` `entity_actors_pool` |
| 常量 | UPPER_SNAKE(或类型内 `const`) | `const PHYSICAL: int = 0`;`const SUCCESS: int = 0` |
| 枚举 | 类型名用 PascalCase,成员用 Pascal | `enum BagState { Satisified, Understocked, Overstocked }`(注意现有拼写,新枚举成员用 PascalCase) |
| 函数/方法 | snake_case | `place_building` `get_entity` `_on_cells_changed` |
| 私有成员/方法 | `_` 前缀 | `_visible_cells` `_place_actor` `_recycle_actor` |
| 信号 | snake_case;属性变化用 `<prop>_changed` | `cells_changed` `entities_changed` `position_changed` `damage_taken` |
| 信号处理回调 | `_on_<signal>` | `_on_cells_changed` `_on_entity_position_changed` |
| 类型标识字符串 | 全小写 snake | `"crossbow"` `"slime"` `"dirt"` `"path"` `&"roaming"` |
| 场景节点名 | lower_snake_case(UI 根控件可用 PascalCase) | `map` `camera` `modes` `card_crossbow`;根 UI `BuildingCard` |
| 前端模型控制脚本 | 类名 `<Type>Model`,文件 `<type>_model.gd`(与 backend 同名逻辑类区分) | `SlimeModel`/`slime_model.gd`、`CrossbowModel`/`crossbow_model.gd` |
| 炮塔类模型基类 | 抽象类(`@abstract`);"可转向 + 俯仰"的建筑模型继承它(见 §6) | `TurretModel`/`turret_model.gd` |
| 音频 id | 全小写 snake;多变体用 `<组名>_<序号>` | `&"ui_click"` `&"build_place"`;`hit_0`..`hit_2`(组 `&"hit"`) |
| 音频类 | 播放器 `AudioManager` / 资源表 `AudioLibrary` | `audio_manager.gd` `audio_library.gd` |

**信号参数不带 `in_` 前缀**(它们是"被广播的数据"而非函数入参),但必须标注类型:
```gdscript
signal cells_changed(axis: Dictionary[Vector2i, bool])
signal entities_changed(added_entity_ids: Array, removed_entity_ids: Array)
```

---

## 4. GDScript 类型与写法规范

### 4.1 类型必须写清楚
- **成员变量**:显式类型 + 默认值(`var health: float = 100`、`var target: Entity = null`、`var axis: Vector2i = Vector2i.ZERO`)。
- **函数形参**:全部显式类型。
- **返回值**:非 void **必须**标注(`-> Land`、`-> BehaviorTree`、`-> bool`);**void 一律省略 `-> void`**(存量 `camera_controller.gd` 等带 `-> void` 的写法不沿用)。
- **局部变量**:用显式类型或 `:=` 推导均可,现有代码两种都用;禁止无标注、无初始化的动态 `var x;`。
- **容器**:优先泛型容器 `Array[T]`、`Dictionary[K, V]`,如 `Array[CellRowData]`、`Dictionary[Vector2i, bool]`。
- **类型化遍历**:`for cell: Cell in cells.values()`、`for worker: Labor in chosen`。
- 不写动态类型后置转型的绕行 hack(如把字段声明成 `var x` 再在别处 `as` 来回转)。

```gdscript
# 合规示例(runtime/backend/map.gd)
func get_cell(in_axis: Vector2i) -> Cell:
    return cells.get(in_axis)

func tick(in_delta: float):                      # void → 不写 -> void
    for cell: Cell in cells.values():
        cell.tick(in_delta)
```

### 4.2 函数形参一律 `in_` 前缀
- **所有**函数入参(包括 setter 形参、`bind`/`load_data`/回调形参)前缀 `in_`:
  `tick(in_delta: float)`、`load_data(in_data: MapData)`、`begin_tree(in_tree: BehaviorTree)`、`_init(in_required_count: int, in_priority: int)`、属性 `set(in_target)`。
- 例外:无。参考 `runtime/backend/cell.gd` `room.gd` `buildings/crossbow.gd`、`runtime/frontend/actors/*`。
- **属性 getter/setter 内局部暂存量、`for` 迭代变量不要求 `in_`**(它们不是入参)。

### 4.3 控制流与可读性
- guard 早退优于深层嵌套:`if not entity: return`、`if cell.building: return false`。
- 用 `if not x` / `if x is not Y` / `is` 类型判断(`entity is not Enemy`),不写 `!= null` 也避免反直觉的双重否定。
- 布尔 API 语义化:`is_alive()`、`is_running()`、`can_place_building()`。
- 事件回调里避免魔法数字拼接 UI;路径、数值集中管理(如需可加常量/数据字段)。

### 4.4 字符串与 StringName
- **StringName** 用 `&"..."` 字面量:`set_mode(&"roaming")`、`%AnimationPlayer.play(&"bone|boneAction_001")`、`blackboard.set_var(&"target_position", …)` —— 用于跨帧缓存比较的 id / 动画名 / 黑板变量名。
- 游戏内普通文本/可变化值用 `String`(`var state: String`、`item_type: String`)。
- 字符串拼接统一 `%`:`"Entity_%s" % type`、`"res://runtime/backend/entities/%s.gd" % in_type`。

### 4.5 注释
- 解释 **why / 几何数学 / 不变式**,不写显而易见的事。
- 字典键语义必须注释:`var bags: Dictionary = {}  # { bag_id: bag }`、`var changed_bags: Dictionary = {}  # { bag_id: true }`。
- 复杂算法允许分节横幅注释与前置说明(参照 `camera_controller.gd` 中"Viewing Axis"段的写法,但**代码风格本身**要向本文件收敛)。

---

## 5. 既有架构模式(新代码必须沿用)

### 5.1 Backend 对象结构
- 顶层:每个后端对象一个 `Node`,`class_name` 注册,挂到 `Level` 树。`Level` 是后端组合根(`level.gd`)。
- `Level._init()` 创建子模块并 `add_child`;`_ready()` 里做 `owner` 透传,保证运行时构建的树也能正确保存:
  ```gdscript
  # level.gd
  static var current: Level = null      # 全局单例指针,由前端组合根在 _ready 赋值
  ```
- 全局唯一实例用 `static var current`(参考 `Level.current`、`MainBase.current`),由组合根初始化,不要做全局 `autoload` 到处 new。

### 5.2 工厂 + 类型注册约定
- 建筑/实体统一经 `static func create(in_type: String)`,由类型名推导 backend 脚本路径:
  ```gdscript
  # entity.gd
  static func create(in_type: String) -> Entity:
      var entity_class = load("res://runtime/backend/entities/%s.gd" % in_type)
      var entity: Entity = entity_class.new()
      entity.type = in_type
      return entity
  ```
- 轻值对象用"命名构造"式静态方法(如 `Damage.physical(10)`),返回类型标注清楚。
- **type 字符串即注册表主键**:backend 脚本路径、frontend 模型路径、`get_type_key()` 全部由它推出,新增类型见 §8。

### 5.3 行为树(LimboAI)
- 实体 AI 用 **LimboAI 行为树**(v1.8 GDExtension):叶子任务写在 `runtime/backend/entities/ai/tasks/<type>_task.gd`(`class_name <Type>Task`,按需 `extends BTAction/BTCondition/BTDecorator`);行为树以 `.tres` 存 `runtime/backend/entities/ai/`。BTTask 是 **Resource**,子节点用 `add_child`;状态常量用 `BT.Status.SUCCESS/FAILURE/RUNNING`;取实体/黑板用 `get_agent()` / `get_blackboard()`。
- **用节点表达控制流,不要用数据协议模拟它**(铁律):"某步失败就继续"用 `BTSelector`;"某步可做可不做"用 `BTAlwaysSucceed` **装饰器**;"反复重跑"用 `BTRepeat`;"卡住就放弃"用 `BTTimeLimit`/`BTRunLimit`。反面教材(已修,勿重犯):①让叶子返回 SUCCESS 只为让整棵树结束,靠"树死掉 → 重建"达成循环(现为 `idle.tres` 的 `BTRepeat(forever = true)`);②用 `@export optional` 把叶子的 FAILURE 翻成 SUCCESS,使同一叶子对不同调用方承担两套矛盾契约(现为 `man_building.tres` 里被 `BTAlwaysSucceed` 装饰的那段)。判据:**同一条逻辑换个调用方就要换语义 ⇒ 它该是树上的结构,不是叶子上的开关**。
- **装饰器必须装饰,不许当裸叶子挂在组合节点下**(铁律):`BTAlwaysSucceed`/`BTAlwaysFail`/`BTInvert`/`BTRepeat*`/`BTTimeLimit`/`BTRunLimit`/`BTDelay`/`BTForEach`/`BTCooldown`/`BTProbability` 都是"改写其唯一子节点结果"的装饰器,必须有子节点;写 `BTSelector[序列, BTAlwaysSucceed]` 是错的(Selector 在扮演装饰器,还留下一个唯一作用是返回 true 的占位节点),应写 `BTAlwaysSucceed(序列)`。天生不带子节点、当"调用/占位"用的只有 `BTSubtree`(它是"调用另一棵树",继承 `BTNewScope`)与 `BTComment`。
- **`BT.Status` 的数值**:`FRESH = 0` / `RUNNING = 1` / `FAILURE = 2` / `SUCCESS = 3`(写断言、读日志、打印状态时别猜)。
- **`BTSubtree` 会开一层新黑板作用域**(它继承 `BTNewScope`):子树内写的黑板键**不会**漏到外面;要往外传的结果不能只放黑板。
- 节点速查表、全部 48 个 `BT*` 节点的属性、`.tres` 序列化写法、ClassDB 查证命令、headless 验证脚本模板,见 `runtime/backend/entities/ai/README.md`。
- **行为逻辑优先落 `.tres`,不用代码组装**:实体的行为链——固定树、派发给工人的活(如 `man_building.tres`)——尽量以 `BehaviorTree` `.tres` 资源表达,用 `preload` 引用(例外:引用树的脚本若处于 Level/Logistics 依赖链内,必须改用按需 `load()` —— 树里含依赖 Logistics 的叶子时,`preload` 会把"脚本 → 树 → 叶子 → Level/Logistics → 该脚本"闭合成编译期环,启动即报 `Could not preload resource file` 并连带 logistics/labor 一起编译失败;见 `transport_task.gd` / `man_building_task.gd` 的注释);同一 `.tres` 模板被多个实例共享是安全的(`instantiate` 时深拷贝 task 树),实例差异一律放黑板传参(`&"target_position"`、`ProvideWorkloadTask.BB_BUILDING` 等键),不要在脚本里 `BehaviorTree.new()` + `set_root_task` 手拼整树。仅当树的形态完全由运行期数据决定、无法静态定义时才允许代码组装,且叶子一律仍走 `tasks/<type>_task.gd`。
- **一棵树 = 一次任务,跑完重建**:`Creature` 持 `current_tree + bt_instance`,每帧 `bt_instance.update(in_delta)`(固定短 tick,无时间溢出/剩余时间语义);树返回非 RUNNING 即本任务结束,下帧经虚方法 `create_tree() -> BehaviorTree` 请求新树(`begin_tree(in_tree)` 供外部直接换活,如 LaborManager 派发)。`instantiate(agent, blackboard, owner, scene_root)` 需提供非空 scene root。
- **运行时数据走黑板**(每实体一个 `Blackboard`):目标点、派发的活等用 `set_var/get_var` 传递;instantiate 会深拷贝 task 树,故共享 `.tres` 模板安全,实体差异放黑板。
- 树内叶子只消费 `in_delta` 计时(不用墙钟),与固定 tick 一致;dizzy 等打断只是暂停喂树,实例状态原样保留(勿在恢复时重建实例)。
- **移动一律取 `Entity.get_move_speed()`**(不要直接读 `entity.move_speed`):基础值即 `move_speed`,子类可覆写表达派生减速(如 `Labor` 按 `head_bag` 装载比例负重减速,满载为 `LOADED_SPEED_FACTOR` 倍);派生量从数据源推算,不缓存第二份。
- **frontend state 契约**:叶子输出的 `state` 取值与 model 动画约定一致(`"idle"`/`"walk"`…,参考 §5.4),由叶子 `_enter/_tick` 里设实体可观察属性。
- **LaborManager 派活**:每工人一棵 `JobRunnerTask` 包装树,运行数据(`job_tree`/`active_task`)写进该工人黑板;JobRunnerTask 每 tick 查 `active_task.is_cancelled`,取消即 FAILURE,工人经 `request_work` 归还调度池。

### 5.4 可观察属性模式
凡"外部(frontend)需要跟随变化"的属性,统一走:
```gdscript
var position: Vector2:
    get:
        return position
    set(in_position):
        if in_position == position:
            return
        position = in_position
        position_changed.emit()
signal position_changed()
```
- setter 先 guard 相同值早退,再赋值、发信号。派生属性(如 `Building.axis`、`Land.type`)做只读 getter 从数据源推算,不存两份。
- `Bag.item_type` 也是可观察属性:同样走 getter/setter + 同值 guard + `signal item_type_changed()` 模式,frontend 依赖该信号刷新表现,不得轮询。
- **`progress` 契约**:数据层恒输出 [0,1] 归一化进度(如蓄力/冷却完成度),禁止输出原始秒数等任意区间值;到动画时间轴/播放方向的换算**一律在 frontend model 的 `set_progress` 完成**,backend 不感知动画资源。`state` 取值由各对象(如 `Building` 子类)自行定义,并与对应 model `set_state` 的分支约定一致。

### 5.5 Actor 镜像 + 对象池
- 每个可显示的 backend 对象在 frontend 有一个 **Actor** 镜像(`EntityActor`/`BuildingActor`/`LandActor`),场景内节点与 backend 状态解耦。
- `bind(in_obj)` / `bind(null)` 负责连接/断开信号并全量刷新一次(**先 disconnect 旧连接再 connect,防重绑重复回调**——参照 `entity_actor.gd`)。
- **回收复用优先于创建销毁**:不可见时 `hide()` + 按 `get_type_key()` 存池,需要时从池取、`bind()`、`show()`(参照 `room_actor.gd` / `map_actor.gd`),避免频繁 `instantiate/queue_free`。
- 跨对象引用统一走 `get_type_key()`(backend 与 frontend 格式一致:`"Entity_%s"` / `"Building_%s"` / `"land_%s"`),用于池 key 与场景路径推导。
- 前端只在大地图可见格区域生成 Actor:`map_actor.gd` / `room_actor.gd` 监听摄像机 `viewing_axis_changed` 决定放置/回收(新 Actor 一律沿用此可见性策略)。
- **`ItemStack` 是 backend `Bag` 的规范前端镜像**:经 `ItemStack.bind(in_bag: Bag)` 绑定(先 disconnect 旧连接再 connect、绑定后全量刷新一次,并对 `in_bag` 与自身做 `is_instance_valid` 守卫),表现一律由 bag 信号回流,**禁止**外部逐帧命令式驱动。各消费方的表现差异只放导出参数 `count_mode`(Raw/Fill)与 `count_offset`,不写进模型逻辑。
- 显示袋子的建筑覆写 `Building.get_display_bag()`(决定展示哪个 bag),`BuildingActor` 把它转发给模型的 `bind_bag(in_bag: Bag)`(见 §8)。

### 5.6 输入模式(Mode)
- `Mode`(`enter/tick/leave`),子类挂在 battle.tscn 的 `%modes` 下,`owner.set_mode(&"id")` 切换,靠节点 `name` 匹配;切换时先 `leave()` 旧的再 `enter()` 新的(`level_actor.set_mode`)。
- 表现层"预览放置"类逻辑归 Mode;放置落库调 backend 方法;UI 操作经 `%` 唯一名与信号连接,不直接遍历写节点属性。

### 5.7 音效(纯前端)

音频**全部属表现层**:backend 不 `load()` 音频、不持有播放器、不引用 `AudioManager`;所有发声由 frontend 监听既有 backend 信号后触发,**不为此在 backend 增状态/信号**(需要新触发点时优先复用 §5.4 已有的可观察信号)。

- **单例**:`AudioManager`(`runtime/frontend/controllers/audio_manager.gd`)用 `static var current`,由组合根 `level_actor.gd._ready()` 赋值为 battle.tscn 的 `%audio` 节点(不做 autoload,见 §5.1)。调用一律走静态入口 `AudioManager.sfx(...)` / `sfx_at(...)` / `music(...)` / `ambience(...)`;入口内对 `current` 做 `is_instance_valid` 守卫,未就绪时静默跳过,故调用方无需判空。
- **两类发声**(按"声音发生在屏幕空间还是世界空间"选):
  - `sfx(id)` —— 非定位音(UI/全局反馈),平铺池,音量恒定;
  - `sfx_at(id, position)` —— 世界空间音(建造/工作/开火/受击/死亡/脚步),用 `AudioStreamPlayer3D` 在 `position` 处发声,**按到监听者(当前 `Camera3D`)的距离自动衰减**(近大远小)。位置用世界坐标:`Vector3(axis.x, 0, axis.y)` 或 actor 的 `global_position`。
- **资源表**:`AudioLibrary`(`runtime/frontend/audio/audio_library.gd`)是 `id → preload AudioStream` 的 `const Dictionary`。**新增音效只登记 id,不改 AudioManager**。多变体音效以"组 id + 变体数"登记在 `_VARIANT_COUNTS`(`play_sfx(&"hit")` 随机取 `hit_0..hit_N`,避免重复听感);单发音效直接登记 `_SFX`。
- **总线**:Master/SFX/Music/Ambience 定义在根目录 `default_bus_layout.tres`(Godot 默认路径自动加载);`sfx*` 走 SFX、`music` 走 Music、`ambience` 走 Ambience。
- **并发与优先级**:SFX 池固定大小、优先复用空闲播放器。池满时:`in_can_drop=true` 的低优先级音(脚步等高频音)**直接丢弃**不抢占;`in_can_drop=false`(默认)的关键音(开火/受击/UI)才顶掉最老的。**高频音必须传 `in_can_drop=true`**。
- **防补播**:Actor 复用池重绑(`bind()`)时,把"上次已发声状态"缓存**对齐当前状态**再刷新(如 `building_actor._last_state = building.state`),避免滚回视野/复用池时补播一次状态音;**逐帧量(`progress_changed`)不得作为发声触发点**。
- **素材与授权**:只收 **CC0 / 公共领域** 素材,或项目自有的原创素材;按用途放 `runtime/frontend/audio/sfx|music|ambience/`。第三方 CC0 素材的来源 URL/作者/授权登记在 `LICENSES/CC0_SOURCES.txt`;项目原创素材登记在 `LICENSES/ORIGINAL_WORKS.txt`。**新增素材必须一并提交授权/来源记录**。

### 5.8 仓库内容与按件状态(Bag / BagItem)

`Bag` 内容存为 `Array[BagItem]`(`bag_item.gd`),每格是"同类型的若干件":

- **无状态散料**(原木/石头/箭/炮弹…):只记 `item_type` + `count`,同类型**恒合并成一格**;
- **有状态物品**(工具耐久、未来的保鲜度…):`count` 恒 1,`state` 指向该件自己的状态载体,**每件各占一格**。

**单类型 vs 多类型**:仓结构上支持多类型,但**默认每只仓只装一种**(`item_type` 声明,Logistics 按它做单类型供需撮合)。**多类型目前只用在工人头顶仓**(`Labor.head_bag`,头顶携带的散料)—— 它不注册 Logistics,故供需撮合不受影响(工人手上另有一只容量 1 的 `Labor.hand_bag`,只放那件手持物品,同样不注册 Logistics);多类型仓按类型读写走 `*_of` 系列(`count_of` / `add_count_of` / `remove_count_of`),展示侧用 `ItemStack.bind(bag, type)` 绑到指定类型。

**状态载体**:入库时按类型取载体 —— 本仓的 `state_factory` 优先,否则走 `Bag.default_state_factory`(按类型名探 `backend/entities/<type>.gd`,是 `Tool` 就实例化并写 `type`)。故**任意仓都能自动保住工具的按件状态**(如接收工人归还工具的 Stockpile),不必逐仓配置;`Bag.is_stateful(type)` 带缓存地回答"该类型是否按件保存"。

- `count` 是**只读派生量**(各格求和),写入一律经 `add_count*` / `remove_count*`;
- 新增一种带状态物品**只需写一个载体类**,`Bag`、Logistics、生产消耗都不必改;
- 读按件状态用 `peek_state(type := "")`(**只读、不取出**);`remove_count*` 对有状态格是**丢弃语义**(摘格并释放载体);**仓间搬运一律走 `Bag.move_to(dest, type, amount)`** —— 搬运单位是"物品"而非"件数"(等价 Minecraft 的 `extractItem`/`insertItem`):有状态物品搬实例本身(耐久等按件状态跟着走、不重置),散料按"目标余量 ∩ 本仓存量 ∩ 请求量"截断,目标拒收则原样放回、绝不丢件。`take_state`/`add_state` 只是它内部的手段,不要在新代码里直接配对使用(手写 `remove_count` + `add_count_of` 搬有状态物品会销毁实例、重置耐久);
- `clear_fungible()` 只清散料格、保留有状态单体(任务结束兜底清仓用它,否则会把工人手上的工具一起销毁);
- 单类型仓的 `item_type` 不可破;真要让某仓装多种,消费方必须改用 `*_of` 系列。
- **主基地的仓是 `MainBaseBag` 子类**(不是裸 `Bag`):通配(接受任意类型)、无限容量、`preferred_min_count = 0`(永不作为需求方 —— 无限仓一旦被当需求方,会把全图库存吸进自己),`preferred_max_count = 0` 表示"有货即供给"。**两条优先级轴必须同档**(取用/归还要么双 FIRST 要么双 LAST):当前是**双 FIRST** —— 工人要工具先从这里拿、用不上的工具也先还回这里,于是它是地图的主动枢纽,库存随劳动节奏可见地涨落(而不是只在别的仓全满/全空时才挪动的被动蓄水池)。**不要**混搭 FIRST/LAST —— 那会组成单向流(取它排第一、还它排最后 ⇒ 只出不进,实测就是这样把基地抽干的;反过来则只进不出)。语义细节与理由见 `main_base_bag.gd` 的类注释。

---

## 6. 场景与节点规范

- **跨层级取节点一律用 unique-name 语法 `%`**,例如 `%map` `%room` `%camera` `%modes` `%AnimationPlayer` `%cog_top`;这些节点在 `.tscn` 中须开 `unique_name_in_owner = true`。
- **禁止**手写 `get_node("../../../…")` 长路径;跨场景注入的资源引用用 `@export`(如 `LevelActor.level_data`)。
- 场景根节点挂同名脚本(如 battle.tscn 根 `level` ← `level_actor.gd`;`xxx_actor.tscn` 根 ← `xxx_actor.gd`)。
- 可复用 UI 做成独立场景 + 信号(如 `building_card.gd` 只 `signal clicked`),由父级连接处理,不在子控件里写具体玩法。
- 模型脚本是"哑"表现脚本:命名 `<type>_model.gd` + `class_name <Type>Model`(避免与 backend 同名逻辑类冲突,如 `SlimeModel` ≠ `Slime`),提供 `set_state` / `set_progress` / `set_target_position` 等可选方法,由 Actor 通过 `has_method` 探测调用(见 `building_actor._update_direction`),**不得反向持有 backend 逻辑**。弩炮/火炮这类"可转向 + 俯仰 + 备弹垛"的建筑模型继承抽象基类 `TurretModel`(`models/buildings/turret_model.gd`),只实现弹道求解 `_aim_pitch()` 与各状态动画钩子;炮管的 rest 姿态由**模型自己负责摆平**(`body.rotation.x = 0` 时炮管须沿 `body` 局部 -Y 且水平),炮管在 Blender 里不水平会让俯仰整体偏掉,该偏置属模型、不在代码里补。

---

## 7. 工程纪律

- **提交偏好:按功能/原子单元分开提交**(一个提交只含一个可独立回滚的功能点,参照仓库 `git log` 的关键词风格如 `actions`/`logistics`/`crossbow anim`);禁止把多个无关功能混成一坨大提交,也禁止把无关的编辑器残留/工具配置夹带进功能提交。
- **做完即提交**:功能/修复单元按本节自查项验证通过后**直接提交**,不必等用户发话;若用户随后发现问题,修复后用 `git commit --amend` 并入原提交(维持"一个功能一个提交"),不要新起修补提交。
- `.godot/` 已 ignore,不提交;不提交 `.tscn` 编辑器残留临时文件(如仓库里遗留的 `battle.tscn838091254.tmp`,应删除)。
- `*.gd.uid`、`*.import`、场景与脚本的 uid 引用随源文件提交,别手动改 uid。
- `addons/` 为第三方插件,不修改其内容;不改 `.gitattributes` / `.editorconfig` 的编码约定(UTF-8、制表符缩进)。
- 新写/改动脚本后,自查:类型是否显式、void 是否省略、形参是否 `in_`、文件名与 class_name 是否一致、backend 是否泄漏了视觉引用。
- 不要在 backend 逻辑里出现 `print`/调试 UI 残留;异常路径尽量用 `assert(cond, "message")` 表达程序不变式。

---

## 8. 新增内容检查清单

**新增建筑类型 `foo`:**
1. `runtime/backend/buildings/foo.gd`:`extends Building`,加 `class_name`,实现 `tick`/特殊行为;
2. `runtime/frontend/models/buildings/foo/foo.tscn` + `foo_model.gd`(`class_name FooModel`;含模型/动画,脚本 `set_state`/`set_progress` 等可选);
3. 数据层字段 `BuildingData.type = "foo"`;`Building.create("foo")` 自动生效,无需改工厂。

**新增显示袋子的建筑:** 建筑脚本须覆写 `get_display_bag() -> Bag`(决定展示哪个 bag),对应模型脚本须实现 `bind_bag(in_bag: Bag)`(`BuildingActor` 负责转发,内部走 `ItemStack` 镜像,见 §5.5);工人随身库存是挂在 `Labor` 上的两只 `Bag`(`Labor.head_bag` 头顶多类型仓 + `Labor.hand_bag` 容量 1 的手仓),不是 `Creature` 的字段。

**新增实体类型 `bar`:** 同构 —— `runtime/backend/entities/bar.gd`(按需 `extends Creature`/`Entity`)+ `models/entities/bar/bar.tscn` + `bar_model.gd`(`class_name BarModel`)。

**新增可检视类型 / 给检视面板加内容:** 检视面板是**一套通用面板**,不要按类型复制一份。面板(`building_inspector_panel.gd`)收集 `%Components` 下全部 `InspectorComponent`,对 `supports(target)` 为真的逐个 `bind(target)`;目标类型是 `Object`,建筑与生物(`Creature`,含 `Labor`/`Enemy`/`Slime`)共用同一面板,当前选中由 `LevelActor.selected_target` 持有。因此**加内容 = 只加一个组件**:`runtime/frontend/ui/<name>_component.gd`(`class_name <Name>Component extends InspectorComponent`,实现 `supports(in_target) -> in_target is <类型>`、`_connect_signals`/`_disconnect_signals`(先断旧再连)、`refresh()`(全量重读、不缓存),并在 `_ready()` 里 `if target: refresh()` 补一次)+ 同目录 `.tscn`(根 `VBoxContainer`、`mouse_filter = 2`、内部节点用 `%Name`),再在 `building_inspector_panel.tscn` 的 `%Components` 下加一个实例 —— **面板与宿主零改动**。标题由 `TITLES` 决定(未列出的类型回退 `type.capitalize()`,故敌人无需登记)。选中高亮:建筑走 `BuildingActor.set_selected`,实体走 `EntityActor.set_selected`(环尺寸由模型包围盒推出、`bind()` 里复位防池复用残留)。拾取:建筑与生物共用 `ActorPick.hit_distance`(射线 vs 模型本地 AABB,唯一实现),`LevelActor.pick_target` 对两类候选取**最近命中**(故遮挡正确:站在建筑后面的生物不会被误选);`EntityActor`/`BuildingActor` 各自缓存 `_model_local_box`,后者测量失败时退回格子脚印盒保证仍可点。**backend 不记录选中态**(§1)。

**新增工具/道具类型 `foo`:** 美术源 `runtime/frontend/models/tools/foo/foo.fbx` + `foo.blend`(源,§9)。网格约定:手柄沿 +Z、工具平面落在 XZ 平面(刀头朝 −X)、原点在握把(手柄末端)、平直着色;材质按部位拆成无贴图纯色(`wood`/`metal`/`edge`),不引贴图。若它要作为道具在仓里/工人手上显示,再建 `runtime/frontend/models/entities/foo/foo.tscn`(+ `foo_model.gd`)并登记进 `ItemStack.ITEM_MODEL_SCENES` —— 该场景须**把美术实例放平使长轴落在 +Z**(ItemStack 约定,见 §5.5)。带耐久这类**按件状态**的物品,再写一个状态载体类即可(默认工厂会按类型名认出来,§5.8);工具即 `extends Tool` 的实体类。工人持工具走 `Labor.hand_bag` 那格有状态单体(手仓容量 1):配方还要用的工具一直握着(每件都"还了再领"会白走数格,见 `ManBuildingTask._write_return_plan`);工人空闲时由空闲树 `idle.tres` 把不再需要的物品就近放进收得下的仓,全图无处可收才留在手上(§5.8)。**工具加速的契约**:配方用 `RecipeData.tool_bonuses` 声明 { 工具类型: 注入倍率 }(空表 = 无需工具);`ProvideWorkloadTask` 取工人随身仓里**表内倍率最高**的那件工具放大注入量并按注入量磨损它 —— 配方要求工具而工人空手时仍按基准 1.0 计(工具是**纯增益**,不是硬需求),不需要工具的配方同样恒 1.0。故**新增一种工具 = 一个 `Tool` 子类(声明 `WEAR_PER_WORKLOAD`)+ 配方表加一行 + 前端模型场景,AI 侧零改动**(取/还/留着/报废全按 `tool_bonuses` 泛化);要加更强的变体(如铁斧)只改倍率数据,不加 AI 逻辑。

**新增 AI 叶子任务/行为树:** 叶子脚本 `runtime/backend/entities/ai/tasks/<type>_task.gd`(`class_name <Type>Task`,如 `MoveToTargetTask`/`EnemyAttackTask`);固定行为树以 `.tres` 落 `runtime/backend/entities/ai/`(优先 `.tres`,不代码组装,约定见 §5.3),`BT.Status.*` 常量与 `get_agent()/get_blackboard()` 用法见 §5.3。

**给 Labor 加"活":** 写 `LaborTask` 子类并实现 `make_tree(in_labor) -> BehaviorTree`(每人一棵动作链树),经 `LaborManager.register_task` 提交;不需要再动 Labor 的执行模型。

**新增地表类型 `baz`:** 确保 `land.gd` 的 `type` 取值 `"baz"`,并放 `runtime/frontend/textures/land_baz.png`(贴图路径由 `"land_%s" % type` 推导)。

**新增输入模式:** `runtime/frontend/modes/<mode_name>_mode.gd`(`extends Mode`)+ 在 battle.tscn 的 `%modes` 下加同名子节点,节点名 = `set_mode` 的 `&"<mode_name>"`。

**新增音效:** 把 `.ogg`(或 `.mp3`)放 `runtime/frontend/audio/sfx/`,在 `audio_library.gd` 登记 id(多变体则加进 `_VARIANT_COUNTS` 并登记 `<id>_0..<id>_N`);在 frontend 触发点调 `AudioManager.sfx_at(id, 世界坐标)`(世界内)或 `AudioManager.sfx(id)`(UI);授权文件放 `LICENSES/`。**backend 不加任何代码**(见 §5.7)。

**修改 backend 状态字段(如实体属性):** 若要被表现层跟随,必须走 §5.4 可观察属性模式并补信号,禁止前端轮询。

---

## 9. 模型资产:从 Blender 导出 FBX

模型本体改 `*.blend`,**FBX 是导出物**。重导出会换掉 FBX 内部的节点 ID,而 `*.tscn` 里对"实例内节点"的覆写(如 `crossbow.tscn` 的 `body` / `wheel` / `Skeleton3D` / `ArrowPointA` / `ArrowPointB` / `Arrow` / `muzzle`)依赖这些 ID —— 设置错了或随手保存场景,就会出现"节点跑到根节点""弓上的箭消失"这类事故。

### 9.1 必须勾的导出设置

**`Object Types` 里 `Empty` 与 `Armature` 必须勾上。** 模型的层级里 `body` 是 Empty、`bone` 是 Armature;漏掉它们,挂在下头的 `wheel` / 骨架 / `skin` 会被重挂到场景根,节点名变成 `base_cog_top_deck_bracket_body#wheel` 这种(整条路径塞进名字),`SKIN_PATH` 与 `*.tscn` 的覆写全部失效。

| 设置 | 值 | 为什么 |
|---|---|---|
| `Include → Selected Objects` | 关(或导出前全选) | 开着且漏选 `body`/`bone`,会得到同样残缺的结果 |
| `add_leaf_bones` | **开** | 场景覆写了 `bones/0..6` = **7** 根骨(5 实骨 + 2 leaf);不开只有 5 根,蒙皮关节索引会越界 |
| `bake_anim_use_all_actions` | **开** | take 名取 action 名,Godot 才得到"骨架名 + action 名"的动画名;用"只导当前 action"会把 take 命名成场景名 `Scene`,动画名对不上 |
| `axis_forward` / `axis_up` | `-Z` / `Y`(默认) | 根节点才会带那个 −90° X(见 §6:FBX 内 `base` rotX≈−90°) |
| `apply_unit_scale` | 开 | 保持比例;`base` 的 scale 由场景覆写,不靠 FBX |

### 9.2 可复制的导出脚本

```python
import bpy
bpy.ops.export_scene.fbx(
    filepath=r"E:\Projects\Godot\autd\runtime\frontend\models\buildings\<type>\<type>.fbx",
    use_selection=False, use_visible=False, use_active_collection=False,
    object_types={'EMPTY', 'ARMATURE', 'MESH'},
    apply_unit_scale=True, apply_scale_options='FBX_SCALE_NONE',
    axis_forward='-Z', axis_up='Y',
    use_mesh_modifiers=True, mesh_smooth_type='FACE', use_tspace=False,
    add_leaf_bones=True,
    primary_bone_axis='Y', secondary_bone_axis='X',
    bake_anim=True, bake_anim_use_all_bones=True,
    bake_anim_use_nla_strips=False, bake_anim_use_all_actions=True,
    bake_anim_force_startend_keying=True,
    bake_anim_step=1.0, bake_anim_simplify_factor=1.0,
    path_mode='AUTO', embed_textures=False, use_metadata=True,
)
```

### 9.3 导出后必查

1. **材质名别改**:Godot 的 `<type>.fbx.import` 按材质名(`Default` / `Default.002` …)映射到外部 `<type>.tres`。
2. **节点齐**:`*.tscn` 覆写的每个节点都能解析(`%wheel` / `%body` / `SKIN_PATH` / `ArrowPointA` / `ArrowPointB` / `muzzle` 均非 null)。
3. **动画名对**:`%AnimationPlayer.get_animation(&"bone|boneAction_001")` 非空。
4. **跑一次主场景无脚本错误**(自查见 §7)。

### 9.4 别在编辑器里"顺手保存"模型场景

重导出换 ID 后,`*.tscn` 里 `parent_id_path=PackedInt32Array(...)` 这类按 ID 的引用就过期了;此时在编辑器里打开并保存场景,Godot 会把解析不到的节点甩到场景根(现象:`%wheel` 为 null、弓上的箭消失且缩放到 1%)。**改完模型先在编辑器里确认节点还在原位再保存**;若已被甩出,`git checkout` 该 `.tscn` 即可还原(节点路径本身仍有效)。`crossbow.tscn` 已去掉这些过期 ID,只按 `parent="路径"` 解析。

### 9.5 模型侧的姿态不变式

炮塔类模型(弩炮/火炮)的炮管**必须在 rest 位就是水平的**:导出后 `body.rotation.x = 0` 时炮管沿 `body` 局部 −Y 且水平(见 §6 的 `TurretModel`)。炮管在 Blender 里不水平,整个俯仰会偏掉一个固定角,且**不能在代码里补**。注意运行时 `TurretModel.set_target_position` 会把 `body.rotation.x` 整个覆写成 `-pitch`,而导出器会把 `body` 的旋转烘进子节点 —— 所以调平既可以转 `body`、也可以转它的子节点,但判断依据是**导出后的模型实测**,不是 Blender 里看着平不平。
