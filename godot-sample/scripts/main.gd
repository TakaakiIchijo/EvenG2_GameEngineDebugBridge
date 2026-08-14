extends Control

const DEFAULT_SERVER_URL := "ws://127.0.0.1:8766"
const SAMPLE_LOGS := [
    {"level": "Log", "message": "Godot: プレイヤーがテストエリアに入りました"},
    {"level": "Warning", "message": "Godot: メモリ使用量が警告しきい値に近づいています"},
    {"level": "Error", "message": "Godot: テスト用エラー通知"},
    {"level": "Log", "message": "Godot: Even G2 Debug Bridge integration completed"},
]

@onready var _status_label: Label = %StatusLabel
@onready var _log_label: RichTextLabel = %LogLabel
@onready var _send_button: Button = %SendButton

var _bridge := EvenG2BridgeClient.new()
var _server_url := DEFAULT_SERVER_URL
var _sample_index := 0
var _next_sample_at_msec := 0
var _sent_all_samples := false


func _ready() -> void:
    _server_url = _read_server_url_from_arguments()
    _bridge.connection_changed.connect(_on_connection_changed)
    _bridge.log_sent.connect(_on_log_sent)
    _send_button.pressed.connect(_send_next_sample_log)
    _status_label.text = "Connecting to %s" % _server_url

    var error := _bridge.connect_to_server(_server_url)
    if error != OK:
        _status_label.text = "Connection request failed: %s" % error_string(error)
        push_error(_status_label.text)
        return

    # 実行テストではサーバー接続後に4件のログを送ります。
    _next_sample_at_msec = Time.get_ticks_msec() + 300


func _process(_delta: float) -> void:
    _bridge.poll()
    if not _bridge.is_server_ready() or _sent_all_samples:
        return

    if Time.get_ticks_msec() >= _next_sample_at_msec:
        _send_next_sample_log()
        _next_sample_at_msec = Time.get_ticks_msec() + 350


func _exit_tree() -> void:
    _bridge.close()


func _send_next_sample_log() -> void:
    # 自動送信完了後も、UIボタンでは同じログ列を繰り返し確認できる。
    if _sample_index >= SAMPLE_LOGS.size():
        _sample_index = 0

    var entry: Dictionary = SAMPLE_LOGS[_sample_index]
    _sample_index += 1
    var tagged_log := "%s %s" % [EvenG2BridgeClient.LOG_TAG, entry["message"]]
    print(tagged_log)
    _bridge.queue_console_style_log(tagged_log, entry["level"])

    if _sample_index >= SAMPLE_LOGS.size():
        _sent_all_samples = true


func _on_connection_changed(connected: bool, detail: String) -> void:
    _status_label.text = detail
    if not connected:
        _status_label.modulate = Color("ff8080")
    elif _bridge.is_server_ready():
        _status_label.modulate = Color("7ee787")
    else:
        _status_label.modulate = Color("f2cc60")


func _on_log_sent(preview: String) -> void:
    _log_label.append_text("[color=#7ee787]%s[/color]\n" % preview)


func _read_server_url_from_arguments() -> String:
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--bridge-url="):
            return argument.trim_prefix("--bridge-url=")
    return DEFAULT_SERVER_URL
