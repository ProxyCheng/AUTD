class_name AudioLibrary
extends RefCounted

# 前端音频资源表:语义 id → 预加载 AudioStream。
#
# 约定:
#   - 单发声效直接以 id 登记(_SFX),AudioManager.play_sfx(&"ui_click") 播放;
#   - 多变体音效以"组 id + 变体数"登记(_VARIANT_COUNTS),play_sfx(&"hit") 会
#     随机取 hit_0..hit_(N-1) 之一,避免连续播放同一采样产生机械感。
# 新增音效:把 .ogg 放进 runtime/frontend/audio/sfx/,在此登记即可,AudioManager
# 无需改动(与 §5.5 "按 key 推导资源" 同思路)。
#
# 音效素材为 Kenney.nl 的 CC0 资源;音乐/环境音来源见 runtime/frontend/audio/LICENSES/。

const _SFX: Dictionary = {
	# —— UI ——
	&"ui_click": preload("res://runtime/frontend/audio/sfx/ui_click.ogg"),
	&"ui_select": preload("res://runtime/frontend/audio/sfx/ui_select.ogg"),
	&"ui_open": preload("res://runtime/frontend/audio/sfx/ui_open.ogg"),
	&"ui_close": preload("res://runtime/frontend/audio/sfx/ui_close.ogg"),
	&"ui_error": preload("res://runtime/frontend/audio/sfx/ui_error.ogg"),
	&"ui_toggle": preload("res://runtime/frontend/audio/sfx/ui_toggle.ogg"),
	&"ui_hover": preload("res://runtime/frontend/audio/sfx/ui_hover.ogg"),
	# —— 建造 ——
	&"build_place": preload("res://runtime/frontend/audio/sfx/build_place.ogg"),
	&"build_remove": preload("res://runtime/frontend/audio/sfx/build_remove.ogg"),
	# —— 工作(多变体)—— 
	&"work_chop_0": preload("res://runtime/frontend/audio/sfx/work_chop_0.ogg"),
	&"work_chop_1": preload("res://runtime/frontend/audio/sfx/work_chop_1.ogg"),
	&"work_chop_2": preload("res://runtime/frontend/audio/sfx/work_chop_2.ogg"),
	&"work_mine_0": preload("res://runtime/frontend/audio/sfx/work_mine_0.ogg"),
	&"work_mine_1": preload("res://runtime/frontend/audio/sfx/work_mine_1.ogg"),
	&"work_mine_2": preload("res://runtime/frontend/audio/sfx/work_mine_2.ogg"),
	&"work_craft_0": preload("res://runtime/frontend/audio/sfx/work_craft_0.ogg"),
	&"work_craft_1": preload("res://runtime/frontend/audio/sfx/work_craft_1.ogg"),
	&"work_craft_2": preload("res://runtime/frontend/audio/sfx/work_craft_2.ogg"),
	# —— 战斗 ——
	&"crossbow_load": preload("res://runtime/frontend/audio/sfx/crossbow_load.ogg"),
	&"crossbow_fire": preload("res://runtime/frontend/audio/sfx/crossbow_fire.ogg"),
	&"cannon_load_0": preload("res://runtime/frontend/audio/sfx/cannon_load_0.ogg"),
	&"cannon_load_1": preload("res://runtime/frontend/audio/sfx/cannon_load_1.ogg"),
	&"cannon_load_2": preload("res://runtime/frontend/audio/sfx/cannon_load_2.ogg"),
	&"cannon_fire_0": preload("res://runtime/frontend/audio/sfx/cannon_fire_0.ogg"),
	&"cannon_fire_1": preload("res://runtime/frontend/audio/sfx/cannon_fire_1.ogg"),
	&"cannon_fire_2": preload("res://runtime/frontend/audio/sfx/cannon_fire_2.ogg"),
	&"hit_0": preload("res://runtime/frontend/audio/sfx/hit_0.ogg"),
	&"hit_1": preload("res://runtime/frontend/audio/sfx/hit_1.ogg"),
	&"hit_2": preload("res://runtime/frontend/audio/sfx/hit_2.ogg"),
	&"die_0": preload("res://runtime/frontend/audio/sfx/die_0.ogg"),
	&"die_1": preload("res://runtime/frontend/audio/sfx/die_1.ogg"),
	&"die_2": preload("res://runtime/frontend/audio/sfx/die_2.ogg"),
	# —— 脚步 ——
	&"footstep_0": preload("res://runtime/frontend/audio/sfx/footstep_0.ogg"),
	&"footstep_1": preload("res://runtime/frontend/audio/sfx/footstep_1.ogg"),
	&"footstep_2": preload("res://runtime/frontend/audio/sfx/footstep_2.ogg"),
	&"footstep_3": preload("res://runtime/frontend/audio/sfx/footstep_3.ogg"),
	&"footstep_4": preload("res://runtime/frontend/audio/sfx/footstep_4.ogg"),
	# —— 语音 ——
	&"voice_labor_0": preload("res://runtime/frontend/audio/sfx/voice_labor_0.ogg"),
	&"voice_labor_1": preload("res://runtime/frontend/audio/sfx/voice_labor_1.ogg"),
	&"voice_labor_2": preload("res://runtime/frontend/audio/sfx/voice_labor_2.ogg"),
	&"voice_enemy_0": preload("res://runtime/frontend/audio/sfx/voice_enemy_0.ogg"),
	&"voice_enemy_1": preload("res://runtime/frontend/audio/sfx/voice_enemy_1.ogg"),
	&"voice_enemy_2": preload("res://runtime/frontend/audio/sfx/voice_enemy_2.ogg"),
}

# 变体组:组 id → 变体数量。play_sfx 传组 id 时随机取 <id>_0..<id>_(N-1)。
const _VARIANT_COUNTS: Dictionary = {
	&"footstep": 5,
	&"work_chop": 3,
	&"work_mine": 3,
	&"work_craft": 3,
	&"hit": 3,
	&"die": 3,
	&"cannon_load": 3,
	&"cannon_fire": 3,
	&"voice_labor": 3,
	&"voice_enemy": 3,
}

# 循环音乐 / 环境音:由 AudioManager 以循环方式播放,单独登记以区分总线。
# 来源与授权见 LICENSES/:bgm.mp3 为项目原创(ORIGINAL_WORKS.txt),
# 其余为 CC0(OpenGameArt,CC0_SOURCES.txt)。
const _MUSIC: Dictionary = {
	&"bgm": preload("res://runtime/frontend/audio/music/bgm.mp3"),
	&"bgm_tavern": preload("res://runtime/frontend/audio/music/old_tower_inn.ogg"),
}

const _AMBIENCE: Dictionary = {
	&"ambience": preload("res://runtime/frontend/audio/ambience/forest.mp3"),
	&"ambience_night": preload("res://runtime/frontend/audio/ambience/crickets.mp3"),
}


static func get_sfx(in_id: StringName) -> AudioStream:
	if _SFX.has(in_id):
		return _SFX[in_id]
	# 组 id:随机取一个变体。
	var count: int = _VARIANT_COUNTS.get(in_id, 0)
	if count <= 0:
		return null
	var variant: StringName = StringName("%s_%d" % [in_id, randi_range(0, count - 1)])
	return _SFX.get(variant)


static func get_music(in_id: StringName) -> AudioStream:
	return _MUSIC.get(in_id)


static func get_ambience(in_id: StringName) -> AudioStream:
	return _AMBIENCE.get(in_id)


static func has_sfx(in_id: StringName) -> bool:
	return _SFX.has(in_id) or _VARIANT_COUNTS.has(in_id)
