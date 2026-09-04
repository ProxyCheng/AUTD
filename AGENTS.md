# AGENTS.md — AUTD(Godot 项目约束文件)

> 本文件依据现有代码(2026-09 快照)提炼,是此仓库 **唯一** 的架构/代码约束来源。
> 任何 AI 助手或开发者在本仓库新增/修改代码前必须先读本文件,并遵循其中全部规则。
> 存量代码中与本文件冲突的地方(如 `runtime/frontend/controllers/camera_controller.gd` 的 `-> void`、无 `in_` 前缀形参、遗留的 `@export jack`)属于历史遗留,**新代码不得沿用**,重构时应向本文件收敛。

- 引擎:GDScript / Godot 4.8,Forward+,Jolt Physics
- 主场景:`res://runtime/frontend/scenes/battle.tscn`(`project.godot` 中 `run/main_scene`)
- 坐标系:y=0 地平面,网格单位 1×1;后端用 `Vector2(x, z)`,前端转 `Vector3(x, 0, z)`

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
| **backend** | 世界状态本体 + 每帧 `tick()` 模拟 | 读写自身状态、发信号、被 frontend 调用 | ❌ `load()`/引用任何 `res://runtime/frontend/*`、`res://editor/*`;❌ 使用 `get_viewport()`、`Input`、`Camera3D` 等表现 API;❌ 持有视觉节点 |
| **frontend** | 读取 backend 状态、连接 backend 信号做表现;接收输入后**调用 backend 公开方法**改状态 | 引用 backend 的类与节点 | ❌ 复制玩法规则/状态(如血量、寻路)到自己内部;❌ 不通过 backend 方法直接改后端状态 |
| **editor** | 编辑 `*.tres` 数据资源 | 引用 backend 的 `*Data` 类与 frontend 的模型场景 | ❌ 被 runtime 反向引用 |

**状态流约定:**
- 后端每帧被推进:`level_actor.gd` 里 `level.tick(in_delta * speed)`,逐层下发 `Map.tick → Cell.tick → Building.tick`、`Room.tick → Entity.tick → Action.tick`。
- backend 状态变化通过信号向外广播(`cells_changed` / `entities_changed` / `position_changed` / `state_changed`…),frontend 只依赖这些信号刷新表现。
- frontend 的输入意图(如 `BuildingMode` 点格子)最终调用 backend 方法(`map.place_building(axis, data)`)落状态,再由信号回流刷新。
- 可观察属性一律走"getter/setter + guard + 发信号"模式(见 §5.4),而不是轮询。

---

## 2. 目录结构与存放规则

```
autd/
├─ project.godot          # 引擎配置(主场景、输入映射)。少手改
├─ icon.svg
├─ runtime/
│  ├─ backend/            # 纯逻辑。extends Node / Resource
│  │  ├─ level.gd map.gd room.gd land.gd cell.gd
│  │  ├─ bag.gd logistics.gd damage.gd
│  │  ├─ buildings/       # 具体建筑:<type>.gd(building.gd / crossbow.gd / main_base.gd / enemy_spawner.gd)
│  │  ├─ data/            # 纯数据 Resource 类:*_data.gd
│  │  └─ entities/        # 具体实体:<type>.gd(entity/creature/enemy/labor/slime/arrow.gd)
│  │     ├─ actions/      # 行为节点:action_status.gd action.gd composite/sequence/selector/idle/move_to/…
│  │     └─ brains/       # 劳工大脑:<name>_brain.gd
│  ├─ configs/            # *.tres 关卡/初始数据文件(如 level0.tres)
│  └─ frontend/           # 表现层
│     ├─ scenes/          # 顶层组合场景 + 其根脚本(battle.tscn、level_actor.gd)
│     ├─ actors/          # backend 对象的可视化镜像:<object>_actor.gd + .tscn
│     ├─ modes/           # 输入模式 Mode 子类,每个 mode 一个文件 + 一个场景节点
│     ├─ controllers/     # camera_controller.gd light_controller.gd(摄像机/灯光)
│     ├─ ui/              # Control 组合(building_card.gd/.tscn)
│     ├─ models/          # 美术资源,按类型分子目录
│     │  ├─ buildings/<type>/<type>.tscn + <type>_model.gd
│     │  └─ entities/<type>/<type>.tscn + <type>_model.gd
│     └─ textures/        # land_<type>.png 等地形贴图
├─ editor/                # @tool 编辑器场景:cell_editor / map_editor / level_editor(.gd + .tscn)
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

---

## 3. 命名规范

| 对象 | 规则 | 示例(取自现有代码) |
|---|---|---|
| 文件 | snake_case,与类名一致 | `building_actor.gd` `move_to_action.gd` |
| `class_name` | PascalCase | `Cell` `LevelActor` `MapEditor` `BuildingData` `MoveToAction` |
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
- **返回值**:非 void **必须**标注(`-> Land`、`-> ActionStatus`、`-> bool`);**void 一律省略 `-> void`**(存量 `camera_controller.gd` 等带 `-> void` 的写法不沿用)。
- **局部变量**:用显式类型或 `:=` 推导均可,现有代码两种都用;禁止无标注、无初始化的动态 `var x;`。
- **容器**:优先泛型容器 `Array[T]`、`Dictionary[K, V]`,如 `Array[CellRowData]`、`Dictionary[Vector2i, bool]`。
- **类型化遍历**:`for cell: Cell in cells.values()`、`for child: Action in get_children()`。
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
  `tick(in_delta: float)`、`load_data(in_data: MapData)`、`set_brain(in_brain_type: StringName)`、`_init(in_type: int, in_remained_time: float = 0)`、属性 `set(in_target)`。
- 例外:无。参考 `runtime/backend/cell.gd` `room.gd` `buildings/crossbow.gd`、`runtime/frontend/actors/*`。
- **属性 getter/setter 内局部暂存量、`for` 迭代变量不要求 `in_`**(它们不是入参)。

### 4.3 控制流与可读性
- guard 早退优于深层嵌套:`if not entity: return`、`if cell.building: return false`。
- 用 `if not x` / `if x is not Y` / `is` 类型判断(`entity is not Enemy`),不写 `!= null` 也避免反直觉的双重否定。
- 布尔 API 语义化:`is_alive()`、`is_running()`、`can_place_building()`。
- 事件回调里避免魔法数字拼接 UI;路径、数值集中管理(如需可加常量/数据字段)。

### 4.4 字符串与 StringName
- **StringName** 用 `&"..."` 字面量:`set_mode(&"roaming")`、`%AnimationPlayer.play(&"bone|boneAction_001")`、`set_brain(&"courier")` —— 用于跨帧缓存比较的 id / 动画名。
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
- 轻值对象用"命名构造"式静态方法(如 `Damage.physical(10)`、`ActionStatus.success(0)`),返回类型标注清楚。
- **type 字符串即注册表主键**:backend 脚本路径、frontend 模型路径、`get_type_key()` 全部由它推出,新增类型见 §8。

### 5.3 行为树 Actions / Brains
- `Entity` 持有 `action: Action`;`Creature.tick_action()` 用 `while remained_time > 0` 消费时间,`assert(action_status.remained_time < remained_time, "Loop Detected")` 防死循环。
- `Action`: `enter()` / `tick(in_delta) -> ActionStatus` / `leave()`;`ActionStatus` 返回剩余时间并带 `is_success/is_failure/is_running()`。
- 组合用 `CompositeAction`(把子 Action `add_child`),派生出 `SequenceAction` / `SelectorAction`。
- 实体把"当前该干什么"委托给一个 `Action`(`Enemy.create_action()` 返回 `SequenceAction([...])`);`Labor` 更进一步用 `Brain`(`set_brain(&"courier")` 动态 `load` `brains/%s_brain.gd`)。
- Action/Brain 运行时才挂到实体下:记得 `add_child` + `owner = owner`,`leave()` 后 `queue_free()`。

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
- **`progress` 契约**:数据层恒输出 [0,1] 归一化进度(如蓄力/冷却完成度),禁止输出原始秒数等任意区间值;到动画时间轴/播放方向的换算**一律在 frontend model 的 `set_progress` 完成**,backend 不感知动画资源。`state` 取值由各对象(如 `Building` 子类)自行定义,并与对应 model `set_state` 的分支约定一致。

### 5.5 Actor 镜像 + 对象池
- 每个可显示的 backend 对象在 frontend 有一个 **Actor** 镜像(`EntityActor`/`BuildingActor`/`LandActor`),场景内节点与 backend 状态解耦。
- `bind(in_obj)` / `bind(null)` 负责连接/断开信号并全量刷新一次(**先 disconnect 旧连接再 connect,防重绑重复回调**——参照 `entity_actor.gd`)。
- **回收复用优先于创建销毁**:不可见时 `hide()` + 按 `get_type_key()` 存池,需要时从池取、`bind()`、`show()`(参照 `room_actor.gd` / `map_actor.gd`),避免频繁 `instantiate/queue_free`。
- 跨对象引用统一走 `get_type_key()`(backend 与 frontend 格式一致:`"Entity_%s"` / `"Building_%s"` / `"land_%s"`),用于池 key 与场景路径推导。
- 前端只在大地图可见格区域生成 Actor:`map_actor.gd` / `room_actor.gd` 监听摄像机 `viewing_axis_changed` 决定放置/回收(新 Actor 一律沿用此可见性策略)。

### 5.6 输入模式(Mode)
- `Mode`(`enter/tick/leave`),子类挂在 battle.tscn 的 `%modes` 下,`owner.set_mode(&"id")` 切换,靠节点 `name` 匹配;切换时先 `leave()` 旧的再 `enter()` 新的(`level_actor.set_mode`)。
- 表现层"预览放置"类逻辑归 Mode;放置落库调 backend 方法;UI 操作经 `%` 唯一名与信号连接,不直接遍历写节点属性。

---

## 6. 场景与节点规范

- **跨层级取节点一律用 unique-name 语法 `%`**,例如 `%map` `%room` `%camera` `%modes` `%AnimationPlayer` `%cog_top`;这些节点在 `.tscn` 中须开 `unique_name_in_owner = true`。
- **禁止**手写 `get_node("../../../…")` 长路径;跨场景注入的资源引用用 `@export`(如 `LevelActor.level_data`)。
- 场景根节点挂同名脚本(如 battle.tscn 根 `level` ← `level_actor.gd`;`xxx_actor.tscn` 根 ← `xxx_actor.gd`)。
- 可复用 UI 做成独立场景 + 信号(如 `building_card.gd` 只 `signal clicked`),由父级连接处理,不在子控件里写具体玩法。
- 模型脚本是"哑"表现脚本:命名 `<type>_model.gd` + `class_name <Type>Model`(避免与 backend 同名逻辑类冲突,如 `SlimeModel` ≠ `Slime`),提供 `set_state` / `set_progress` / `set_target_position` 等可选方法,由 Actor 通过 `has_method` 探测调用(见 `building_actor._update_direction`),**不得反向持有 backend 逻辑**。

---

## 7. 工程纪律

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

**新增实体类型 `bar`:** 同构 —— `runtime/backend/entities/bar.gd`(按需 `extends Creature`/`Entity`)+ `models/entities/bar/bar.tscn` + `bar_model.gd`(`class_name BarModel`);若需新行为,加 `entities/actions/`;若 Labor 要新大脑,加 `entities/brains/<name>_brain.gd`。

**新增地表类型 `baz`:** 确保 `land.gd` 的 `type` 取值 `"baz"`,并放 `runtime/frontend/textures/land_baz.png`(贴图路径由 `"land_%s" % type` 推导)。

**新增输入模式:** `runtime/frontend/modes/<mode_name>_mode.gd`(`extends Mode`)+ 在 battle.tscn 的 `%modes` 下加同名子节点,节点名 = `set_mode` 的 `&"<mode_name>"`。

**修改 backend 状态字段(如实体属性):** 若要被表现层跟随,必须走 §5.4 可观察属性模式并补信号,禁止前端轮询。
