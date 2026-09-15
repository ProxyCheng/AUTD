#!/data/data/com.termux/files/usr/bin/bash
# Keeps the opencode agent web server alive and connected to the Godot editor.
#
# Godot cannot launch Termux itself: the editor APK never declared
# com.termux.permission.RUN_COMMAND, so `pm grant` is refused and the
# RUN_COMMAND intent is unreachable. This watchdog inverts the direction -- it
# waits for Godot instead of Godot pushing to Termux -- which needs no
# permissions at all.
#
# The MCP addon binds 9080 as soon as the editor opens a project, but Android
# freezes a backgrounded app's main loop, and a frozen editor still accepts the
# TCP connection while never replying. A port probe would therefore call a
# frozen editor healthy, so liveness is decided by a real JSON-RPC initialize.
# Any HTTP status counts as alive (the server answers 401 without a valid
# token, which still proves the main loop is running).

export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export PATH=$PREFIX/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib

PROJ=/sdcard/Documents/autd
PORT=4096
MCP_PORT=9080
TOKEN=$(cat "$HOME/.mcp_token" 2>/dev/null)
LOG=$HOME/oc-web.log
WATCH_LOG=$HOME/watchdog.log

MCP_BODY='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"watchdog","version":"1.0"}}}'

port_open() {
	(exec 3<>/dev/tcp/127.0.0.1/$1) 2>/dev/null
}

mcp_ready() {
	local line rc
	exec 3<>/dev/tcp/127.0.0.1/$MCP_PORT 2>/dev/null || return 1
	if ! printf 'POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:%s\r\nAuthorization: Bearer %s\r\nContent-Type: application/json\r\nAccept: application/json, text/event-stream\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
		"$MCP_PORT" "$TOKEN" "${#MCP_BODY}" "$MCP_BODY" >&3 2>/dev/null; then
		exec 3<&- 3>&-
		return 1
	fi
	read -t 5 -r line <&3
	rc=$?
	exec 3<&- 3>&-
	[ $rc -eq 0 ] || return 1
	case "$line" in
		HTTP/*) return 0 ;;
		*) return 1 ;;
	esac
}

kill_agent() {
	ps -A 2>/dev/null | grep -i opencode | while read -r line; do
		set -- $line
		kill "$1" 2>/dev/null
	done
	sleep 2
	ps -A 2>/dev/null | grep -i proot | while read -r line; do
		set -- $line
		kill "$1" 2>/dev/null
	done
	sleep 2
}

start_agent() {
	# stdin must be redirected: a background process that reads the controlling
	# terminal is stopped with SIGTTIN, which leaves opencode alive but frozen.
	nohup proot-distro login ubuntu -- bash -lc \
		"cd $PROJ && exec /root/.opencode/bin/opencode web --port $PORT --hostname 0.0.0.0" \
		< /dev/null >> "$LOG" 2>&1 &
}

termux-wake-lock 2>/dev/null
echo "$(date '+%F %T') watchdog start (pid $$)" >> "$WATCH_LOG"

mcp_was_ready=0
last_restart=0

while true; do
	if mcp_ready; then
		if ! port_open "$PORT"; then
			echo "$(date '+%F %T') editor foreground, agent down -> starting" >> "$WATCH_LOG"
			start_agent
			sleep 20
		elif [ "$mcp_was_ready" -eq 0 ]; then
			# opencode was started while the editor was frozen, so its MCP
			# client already gave up and will not retry. Now that the server
			# answers again, restart it so it picks the tools up.
			now=$(date +%s)
			if [ $((now - last_restart)) -gt 120 ]; then
				echo "$(date '+%F %T') mcp recovered -> restarting agent" >> "$WATCH_LOG"
				kill_agent
				start_agent
				last_restart=$now
				sleep 20
			fi
		fi
		mcp_was_ready=1
	else
		mcp_was_ready=0
	fi
	sleep 5
done
