class_name DungeonBridgeClient
extends RefCounted

## 3Dダンジョンのミニマップ状態をEven G2 Debug Bridgeへ送信する。

signal connection_changed(connected: bool, detail: String)
signal minimap_sent(revision: int)

const PROTOCOL_VERSION := 1
const SEND_INTERVAL_MSEC := 250

var _socket := WebSocketPeer.new()
var _server_url := ""
var _handshake_sent := false
var _server_ready := false
var _was_open := false
var _pending_minimap: Dictionary = {}
var _next_send_at_msec := 0


func connect_to_server(server_url: String) -> Error:
    _server_url = server_url
    _socket = WebSocketPeer.new()
    _handshake_sent = false
    _server_ready = false
    _was_open = false
    return _socket.connect_to_url(server_url)


func poll() -> void:
    _socket.poll()
    var ready_state := _socket.get_ready_state()

    if ready_state == WebSocketPeer.STATE_OPEN:
        if not _was_open:
            _was_open = true
            connection_changed.emit(true, "Bridge WebSocket connected")
        if not _handshake_sent:
            _send_hello()
        _read_server_messages()
        _flush_minimap()
    elif ready_state == WebSocketPeer.STATE_CLOSED and _was_open:
        _was_open = false
        _server_ready = false
        connection_changed.emit(false, "Bridge WebSocket closed: %s" % _socket.get_close_reason())


func queue_minimap(payload: Dictionary) -> void:
    _pending_minimap = payload.duplicate(true)


func is_server_ready() -> bool:
    return _server_ready


func close() -> void:
    if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        _socket.close(1000, "Dungeon game closed")


func _send_hello() -> void:
    _handshake_sent = true
    var error := _socket.send_text(JSON.stringify({
        "type": "engine",
        "protocol_version": PROTOCOL_VERSION,
    }))
    if error != OK:
        connection_changed.emit(false, "Bridge handshake failed: %s" % error_string(error))


func _read_server_messages() -> void:
    while _socket.get_available_packet_count() > 0:
        var packet := _socket.get_packet()
        if not _socket.was_string_packet():
            continue
        var payload: Variant = JSON.parse_string(packet.get_string_from_utf8())
        if payload is Dictionary and payload.get("type", "") == "connected":
            _server_ready = true
            connection_changed.emit(true, "Even G2 bridge ready")


func _flush_minimap() -> void:
    if not _server_ready or _pending_minimap.is_empty():
        return

    var now := Time.get_ticks_msec()
    if now < _next_send_at_msec:
        return

    var payload: Dictionary = _pending_minimap
    _pending_minimap = {}
    _next_send_at_msec = now + SEND_INTERVAL_MSEC
    var error := _socket.send_text(JSON.stringify(payload))
    if error == OK:
        minimap_sent.emit(int(payload.get("revision", 0)))
    else:
        push_warning("[DungeonBridge] Failed to send minimap: %s" % error_string(error))
