class_name AudioManager
extends Node3D

# 前端音频管理器(表现层,见 §1):后端不感知音频,所有播放都由 frontend 监听
# backend 信号后调用本类。唯一实例经 static current 暴露,由组合根(LevelActor)
# 在 _ready 赋值,不做 autoload(见 §5.1)。
#
# 播放能力:
#   sfx(id)            —— 非定位短音效(UI/全局反馈),UI 池,音量恒定;
#   sfx_at(id, pos)    —— 世界空间短音效,按到监听者(当前摄像机)的距离自然衰减,
#                         实现"近大远小";建筑/单位/战斗音效一律走这里;
#   music(id)          —— 循环 BGM,单实例,重复请求同一首时不重启;
#   ambience(id)       —— 循环环境音,单实例。
# 资源解析全部委托 AudioLibrary(语义 id → AudioStream);调用方统一走静态
# AudioManager.sfx/sfx_at 入口,免去各处判空。
#
# 3D 衰减由 AudioStreamPlayer3D 自动完成:unit_size 内为基准音量,max_distance
# 外不再继续衰减;监听者默认是 current 的 Camera3D(本工程即 battle 的 %camera)。

static var current: AudioManager = null

const WORLD_POOL_SIZE: int = 12   # 世界空间(3D)音效池
const UI_POOL_SIZE: int = 6       # 非定位(UI)音效池

@export var sfx_volume_db: float = -4.0
@export var music_volume_db: float = -10.0
@export var ambience_volume_db: float = -16.0

# 距离衰减参数(单位与网格一致,1 格 = 1 米)。调大可让近处更"贴脸"、远处更轻。
@export var attenuation_unit_size: float = 6.0
@export var attenuation_max_distance: float = 45.0
@export var attenuation_model: AudioStreamPlayer3D.AttenuationModel = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE

var _world_players: Array[AudioStreamPlayer3D] = []
var _world_cursor: int = 0
var _ui_players: Array[AudioStreamPlayer] = []
var _ui_cursor: int = 0
var _music_player: AudioStreamPlayer = null
var _ambience_player: AudioStreamPlayer = null
var _music_id: StringName = &""
var _ambience_id: StringName = &""


func _ready():
	_world_players.resize(WORLD_POOL_SIZE)
	for i in WORLD_POOL_SIZE:
		_world_players[i] = _make_world_player()
	_ui_players.resize(UI_POOL_SIZE)
	for i in UI_POOL_SIZE:
		_ui_players[i] = _make_flat_player(&"SFX", sfx_volume_db)
	_music_player = _make_flat_player(&"Music", music_volume_db)
	_ambience_player = _make_flat_player(&"Ambience", ambience_volume_db)


# 世界空间播放器:按到摄像机的距离自动衰减。
func _make_world_player() -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.bus = &"SFX"
	player.volume_db = sfx_volume_db
	player.unit_size = attenuation_unit_size
	player.max_distance = attenuation_max_distance
	player.attenuation_model = attenuation_model
	add_child(player)
	return player


# 非定位播放器:音量恒定,用于 UI 与循环音乐/环境音。
func _make_flat_player(in_bus: StringName, in_volume_db: float) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.bus = in_bus
	player.volume_db = in_volume_db
	add_child(player)
	return player


# —— 静态入口:current 未就绪时静默跳过,调用方无需判空 ——

static func sfx(in_id: StringName, in_pitch_scale: float = 1.0, in_volume_offset_db: float = 0.0, in_can_drop: bool = false):
	if is_instance_valid(current):
		current.play_sfx(in_id, in_pitch_scale, in_volume_offset_db, in_can_drop)


static func sfx_at(in_id: StringName, in_position: Vector3, in_pitch_scale: float = 1.0, in_volume_offset_db: float = 0.0, in_can_drop: bool = false):
	if is_instance_valid(current):
		current.play_sfx_at(in_id, in_position, in_pitch_scale, in_volume_offset_db, in_can_drop)


static func music(in_id: StringName):
	if is_instance_valid(current):
		current.play_music(in_id)


static func ambience(in_id: StringName):
	if is_instance_valid(current):
		current.play_ambience(in_id)


# —— 实例实现 ——

# 非定位短音效(UI)。in_id 可为单发 id 或变体组 id(见 AudioLibrary)。
# in_pitch_scale 给同采样加轻微音高抖动;in_volume_offset_db 在基准音量上叠加偏移。
# in_can_drop=true 表示池满时宁可丢弃也不抢占(高频低优先级音,如脚步)。
func play_sfx(in_id: StringName, in_pitch_scale: float = 1.0, in_volume_offset_db: float = 0.0, in_can_drop: bool = false):
	if _ui_players.is_empty():
		return
	var stream: AudioStream = AudioLibrary.get_sfx(in_id)
	if not stream:
		return
	var player: AudioStreamPlayer = _find_free_flat_player()
	if not player:
		if in_can_drop:
			return
		player = _ui_players[_ui_cursor]
		_ui_cursor = (_ui_cursor + 1) % _ui_players.size()
	player.stream = stream
	player.pitch_scale = in_pitch_scale
	player.volume_db = sfx_volume_db + in_volume_offset_db
	player.play()


# 世界空间短音效:在 in_position 处发声,由 AudioStreamPlayer3D 按距离衰减(近大远小)。
func play_sfx_at(in_id: StringName, in_position: Vector3, in_pitch_scale: float = 1.0, in_volume_offset_db: float = 0.0, in_can_drop: bool = false):
	if _world_players.is_empty():
		return
	var stream: AudioStream = AudioLibrary.get_sfx(in_id)
	if not stream:
		return
	var player: AudioStreamPlayer3D = _find_free_world_player()
	if not player:
		if in_can_drop:
			return
		player = _world_players[_world_cursor]
		_world_cursor = (_world_cursor + 1) % _world_players.size()
	player.global_position = in_position
	player.stream = stream
	player.pitch_scale = in_pitch_scale
	player.volume_db = sfx_volume_db + in_volume_offset_db
	player.play()


# 优先复用空闲播放器;全部占用时返回 null,由调用方决定丢弃还是抢占最老的(游标)。
func _find_free_flat_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _ui_players:
		if not player.playing:
			return player
	return null


func _find_free_world_player() -> AudioStreamPlayer3D:
	for player: AudioStreamPlayer3D in _world_players:
		if not player.playing:
			return player
	return null


func play_music(in_id: StringName):
	if in_id == _music_id and _music_player and _music_player.playing:
		return
	var stream: AudioStream = AudioLibrary.get_music(in_id)
	if not stream:
		return
	_music_id = in_id
	_play_loop(_music_player, stream)


func play_ambience(in_id: StringName):
	if in_id == _ambience_id and _ambience_player and _ambience_player.playing:
		return
	var stream: AudioStream = AudioLibrary.get_ambience(in_id)
	if not stream:
		return
	_ambience_id = in_id
	_play_loop(_ambience_player, stream)


func stop_music():
	if _music_player:
		_music_player.stop()
	_music_id = &""


func stop_ambience():
	if _ambience_player:
		_ambience_player.stop()
	_ambience_id = &""


# 循环播放:各流类型默认不循环,需在实例上打开循环开关再播。
# OggVorbis/MP3 用 bool loop;WAV 用 loop_mode 枚举。
func _play_loop(in_player: AudioStreamPlayer, in_stream: AudioStream):
	if not in_player:
		return
	if in_stream is AudioStreamOggVorbis:
		(in_stream as AudioStreamOggVorbis).loop = true
	elif in_stream is AudioStreamMP3:
		(in_stream as AudioStreamMP3).loop = true
	elif in_stream is AudioStreamWAV:
		(in_stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	in_player.stream = in_stream
	in_player.play()
