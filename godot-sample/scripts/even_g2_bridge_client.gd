class_name EvenG2BridgeClient
extends RefCounted

## Even G2 Debug Bridge用のGodot 4 WebSocketクライアントです。
## WebSocketPeerは毎フレームpoll()する必要があります。

signal connection_changed(connected: bool, detail: String)
signal log_sent(preview: String)

const LOG_TAG := "[Even]"
const PROTOCOL_VERSION := 1
const SEND_INTERVAL_MSEC := 250

var _socket := WebSocketPeer.new()
var _server_url := ""
var _handshake_sent := false
var _server_ready := false
var _was_open := false
var _pending_log: Dictionary = {}
var _next_send_at_msec := 0
var _coalesced_log_count := 0
var _throttle_warning_issued := false


func connect_to_server(server_url: String) -> Error:
    _server_url = server_url
    _socket = WebSocketPeer.new()
    _handshake_sent = false
    _server_ready = false
    _was_open = false
    return _socket.connect_to_url(server_url)


func poll() -> void:
    _socket.poll()
    var state := _socket.get_ready_state()

    if state == WebSocketPeer.STATE_OPEN:
        if not _was_open:
            _was_open = true
            connection_changed.emit(true, "WebSocket connected: %s" % _server_url)
        if not _handshake_sent:
            _send_hello()
        _read_server_messages()
        _flush_latest_log()
    elif state == WebSocketPeer.STATE_CLOSED:
        if _was_open:
            _was_open = false
            _server_ready = false
            connection_changed.emit(false, "WebSocket closed: %s" % _socket.get_close_reason())


func queue_console_style_log(console_text: String, level: String = "Log") -> bool:
    ## Unityと同じ[Even]タグ規約を利用します。タグのないログは送信しません。
    if not console_text.contains(LOG_TAG):
        return false

    if not _pending_log.is_empty():
        _coalesced_log_count += 1

    _pending_log = {
        "type": "log",
        "level": _normalize_level(level),
        "message": console_text.replace(LOG_TAG, "").strip_edges(),
        "timestamp": Time.get_time_string_from_system(),
        "tag": LOG_TAG,
        "protocol_version": PROTOCOL_VERSION,
    }
    return true


func is_server_ready() -> bool:
    return _server_ready


func get_coalesced_log_count() -> int:
    return _coalesced_log_count


func close() -> void:
    if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        _socket.close(1000, "Godot sample finished")


func _send_hello() -> void:
    _handshake_sent = true
    var error := _socket.send_text(JSON.stringify({
        "type": "engine",
        "protocol_version": PROTOCOL_VERSION,
    }))
    if error != OK:
        connection_changed.emit(false, "Failed to send engine handshake: %s" % error_string(error))


func _read_server_messages() -> void:
    while _socket.get_available_packet_count() > 0:
        var packet := _socket.get_packet()
        if not _socket.was_string_packet():
            continue
        var parsed = JSON.parse_string(packet.get_string_from_utf8())
        if parsed is Dictionary and parsed.get("type", "") == "connected":
            _server_ready = true
            connection_changed.emit(true, "Bridge protocol handshake completed")


func _flush_latest_log() -> void:
    if not _server_ready or _pending_log.is_empty():
        return

    var now := Time.get_ticks_msec()
    if now < _next_send_at_msec:
        if not _throttle_warning_issued:
            _throttle_warning_issued = true
            push_warning("[EvenG2DebugBridge] Log frequency is too high. Intermediate messages are coalesced to a 250ms interval.")
        return

    var payload := _pending_log
    _pending_log = {}
    _next_send_at_msec = now + SEND_INTERVAL_MSEC
    var error := _socket.send_text(JSON.stringify(payload))
    if error == OK:
        log_sent.emit("[%s] %s" % [payload["level"], payload["message"]])
    else:
        push_warning("[EvenG2DebugBridge] Failed to send log: %s" % error_string(error))


func _normalize_level(level: String) -> String:
    if level in ["Log", "Warning", "Error", "Exception"]:
        return level
    return "Log"
