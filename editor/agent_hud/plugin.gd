@tool
extends EditorPlugin

## Tablet-side agent HUD.
##
## Surfaces the two things needed when driving this project from a phone: the
## LAN address to open in the browser, and whether the two local servers are
## actually listening.
##
##   :9080  Godot MCP (addons/godot_mcp) -- the agent's tool surface
##   :4096  opencode web                  -- the UI the phone connects to
##
## Screen-off is deliberately NOT handled here. The editor already applies
## interface/editor/display/keep_screen_on through DisplayServer.screen_set_keep_on()
## on startup and on every change to that settings group (editor_node.cpp), so
## keeping the display awake is an editor setting; this dock only reports it.
##
## Setup on the tablet:
##   1. enable this plugin in project.godot [editor_plugins]
##   2. set interface/editor/display/keep_screen_on = true in Editor Settings
##   3. copy termux/godot-agent-watchdog.sh to Termux $HOME and the
##      termux/bashrc.snippet block into ~/.bashrc, which starts the watchdog
##   4. open the project once so the editor registers it in projects.cfg
##
## The editor has to stay in the foreground. Android freezes a backgrounded
## app's main loop, and the MCP server then keeps accepting connections on
## :9080 without ever replying, so the agent silently loses its godot_* tools.

const MCP_PORT: int = 9080
const AGENT_PORT: int = 4096

## connect_to_host() is non-blocking: the probe settles over a few polls.
## Kept short because each probe blocks the main thread while it settles.
const PROBE_POLL_COUNT: int = 10
const PROBE_POLL_DELAY_MSEC: int = 5

const REFRESH_INTERVAL: float = 3.0

const STATUS_UP: String = "UP"
const STATUS_DOWN: String = "DOWN"

const COLOR_OK := Color(0.45, 0.85, 0.55)
const COLOR_BAD := Color(0.9, 0.45, 0.45)

var _dock: EditorDock = null
var _url_label: Label = null
var _mcp_label: Label = null
var _agent_label: Label = null
var _screen_label: Label = null
var _timer: Timer = null


func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "Agent"
	_dock.layout_key = "agent_hud"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	_dock.add_child(_build_content())
	add_dock(_dock)

	_timer = Timer.new()
	_timer.wait_time = REFRESH_INTERVAL
	_timer.autostart = true
	_timer.timeout.connect(_refresh)
	add_child(_timer)

	_refresh()


func _exit_tree() -> void:
	if _timer:
		_timer.stop()
		_timer.queue_free()
		_timer = null
	if _dock:
		remove_dock(_dock)
		_dock.queue_free()
		_dock = null


func _build_content() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "AgentHUDContent"
	box.add_theme_constant_override(&"separation", 8)

	var heading := Label.new()
	heading.text = "Phone -> Agent"
	heading.add_theme_font_size_override(&"font_size", 16)
	box.add_child(heading)

	_url_label = Label.new()
	_url_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_url_label.add_theme_font_size_override(&"font_size", 20)
	_url_label.add_theme_color_override(&"font_color", COLOR_OK)
	box.add_child(_url_label)

	var copy_button := Button.new()
	copy_button.text = "Copy URL"
	copy_button.pressed.connect(_on_copy_pressed)
	box.add_child(copy_button)

	box.add_child(HSeparator.new())

	_mcp_label = Label.new()
	box.add_child(_mcp_label)

	_agent_label = Label.new()
	box.add_child(_agent_label)

	_screen_label = Label.new()
	box.add_child(_screen_label)

	box.add_child(HSeparator.new())

	var refresh_button := Button.new()
	refresh_button.text = "Refresh now"
	refresh_button.pressed.connect(_refresh)
	box.add_child(refresh_button)

	var hint := Label.new()
	hint.text = "Open the green URL on the phone over the same Wi-Fi.\nThe agent is kept up by ~/godot-agent-watchdog.sh in Termux."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override(&"font_size", 11)
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	box.add_child(hint)

	return box


func _refresh() -> void:
	if not _url_label:
		return

	_url_label.text = "http://%s:%d" % [_lan_ip(), AGENT_PORT]

	var mcp_up: bool = _is_port_open(MCP_PORT)
	_apply_status(_mcp_label, "Godot MCP", MCP_PORT, mcp_up)

	var agent_up: bool = _is_port_open(AGENT_PORT)
	_apply_status(_agent_label, "Agent (opencode)", AGENT_PORT, agent_up)

	var kept_on: bool = DisplayServer.screen_is_kept_on()
	_screen_label.text = "Screen kept on: %s" % ("yes" if kept_on else "no")
	_screen_label.add_theme_color_override(&"font_color", COLOR_OK if kept_on else COLOR_BAD)


func _apply_status(in_label: Label, in_name: String, in_port: int, in_up: bool) -> void:
	in_label.text = "%s  :%d  %s" % [in_name, in_port, STATUS_UP if in_up else STATUS_DOWN]
	in_label.add_theme_color_override(&"font_color", COLOR_OK if in_up else COLOR_BAD)


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_url_label.text)


## Returns the address the phone should dial. IP.get_local_addresses() also
## carries loopback, IPv6 and (on some devices) cellular addresses, none of
## which the phone can reach, so the private Wi-Fi ranges win.
static func _lan_ip() -> String:
	var fallback: String = ""
	for address: String in IP.get_local_addresses():
		if address.contains(":"):
			continue
		if address.begins_with("127.") or address.begins_with("169.254."):
			continue
		if address.begins_with("10.") or address.begins_with("192.168.") or address.begins_with("172."):
			return address
		if fallback.is_empty():
			fallback = address
	return fallback if not fallback.is_empty() else "no-lan-ip"


## A TCP connect is a better liveness probe than an HTTP request here: the MCP
## server answers 401 without a token, which still proves it is listening.
static func _is_port_open(in_port: int) -> bool:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", in_port) != OK:
		return false
	for _i: int in PROBE_POLL_COUNT:
		peer.poll()
		var status: int = peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
			return true
		if status == StreamPeerTCP.STATUS_ERROR:
			return false
		OS.delay_msec(PROBE_POLL_DELAY_MSEC)
	peer.disconnect_from_host()
	return false
