extends SceneTree

const DEFAULT_SERVER_URL := "ws://127.0.0.1:8766"
const TIMEOUT_MSEC := 5000

var _socket := WebSocketPeer.new()
var _server_url := DEFAULT_SERVER_URL
var _deadline_msec := 0
var _hello_sent := false
var _log_sent := false


func _initialize() -> void:
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--bridge-url="):
            _server_url = argument.trim_prefix("--bridge-url=")

    _deadline_msec = Time.get_ticks_msec() + TIMEOUT_MSEC
    var error := _socket.connect_to_url(_server_url)
    if error != OK:
        _fail("connect_to_url failed: %s" % error_string(error))


func _process(_delta: float) -> bool:
    if Time.get_ticks_msec() > _deadline_msec:
        _fail("Timed out while waiting for the bridge handshake")
        return true

    _socket.poll()
    var state := _socket.get_ready_state()
    if state == WebSocketPeer.STATE_CLOSED:
        _fail("WebSocket closed: %s" % _socket.get_close_reason())
        return true
    if state != WebSocketPeer.STATE_OPEN:
        return false

    if not _hello_sent:
        _hello_sent = true
        _socket.send_text(JSON.stringify({"type": "engine", "protocol_version": 1}))

    while _socket.get_available_packet_count() > 0:
        var packet := _socket.get_packet()
        if not _socket.was_string_packet():
            continue
        var payload = JSON.parse_string(packet.get_string_from_utf8())
        if payload is Dictionary and payload.get("type", "") == "connected" and not _log_sent:
            _log_sent = true
            _socket.send_text(JSON.stringify({
                "type": "log",
                "level": "Log",
                "message": "Godot headless smoke test passed",
                "timestamp": Time.get_time_string_from_system(),
                "tag": "[Even]",
                "protocol_version": 1,
            }))
            print("[Even] Godot headless smoke test passed")
            quit(0)
            return true

    return false


func _fail(message: String) -> void:
    push_error(message)
    quit(1)
