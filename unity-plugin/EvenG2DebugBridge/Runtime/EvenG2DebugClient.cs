using System;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using UnityEngine;

namespace EvenG2DebugBridge
{
    public class EvenG2DebugClient : IDisposable
    {
        public const string LOG_TAG = "[Even]";
        private const float THROTTLE_INTERVAL_SECONDS = 0.25f; // 250ms (4 FPS)

        private readonly string _serverUrl;
        private ClientWebSocket _ws;
        private CancellationTokenSource _cts;
        private bool _disposed;

        // スロットリング用フィールド
        private string _lastLogMessage;
        private LogType _lastLogType;
        private bool _hasPendingLog = false;
        private double _lastSendTime = 0;
        private bool _warningIssued = false;

        public event Action<bool> OnConnectionStateChanged;
        public event Action<string> OnLogSent;

        public bool IsConnected => _ws?.State == WebSocketState.Open;

        public EvenG2DebugClient(string serverUrl)
        {
            _serverUrl = serverUrl;
        }

        public async Task StartAsync()
        {
            if (_disposed) throw new ObjectDisposedException(nameof(EvenG2DebugClient));

            _cts = new CancellationTokenSource();
            await ConnectAsync();

            Application.logMessageReceivedThreaded += OnLogMessageReceived;
            UnityEditor.EditorApplication.update += OnEditorUpdate; // Editor の Update ループを利用
        }

        public async Task StopAsync()
        {
            Application.logMessageReceivedThreaded -= OnLogMessageReceived;
            UnityEditor.EditorApplication.update -= OnEditorUpdate;
            _cts?.Cancel();

            if (_ws != null && _ws.State == WebSocketState.Open)
            {
                try
                {
                    await _ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "Stopped by user", CancellationToken.None);
                }
                catch (Exception) { /* Ignore */ }
            }

            OnConnectionStateChanged?.Invoke(false);
        }

        private async Task ConnectAsync()
        {
            _ws?.Dispose();
            _ws = new ClientWebSocket();

            try
            {
                await _ws.ConnectAsync(new Uri(_serverUrl), _cts.Token);
                var handshake = Serialize(new { type = "engine" });
                await SendRawAsync(handshake);
                OnConnectionStateChanged?.Invoke(true);
                Debug.Log($"[EvenG2DebugBridge] サーバーに接続しました: {_serverUrl}");
                _ = ReceiveLoopAsync();
            }
            catch (Exception ex)
            {
                OnConnectionStateChanged?.Invoke(false);
                Debug.LogWarning($"[EvenG2DebugBridge] 接続失敗: {ex.Message}");
            }
        }

        private async Task ReceiveLoopAsync()
        {
            var buffer = new byte[4096];
            try
            {
                while (_ws.State == WebSocketState.Open && !_cts.IsCancellationRequested)
                {
                    var result = await _ws.ReceiveAsync(new ArraySegment<byte>(buffer), _cts.Token);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        OnConnectionStateChanged?.Invoke(false);
                        break;
                    }
                }
            }
            catch (OperationCanceledException) { /* Normal closure */ }
            catch (Exception ex)
            {
                Debug.LogWarning($"[EvenG2DebugBridge] 受信エラー: {ex.Message}");
                OnConnectionStateChanged?.Invoke(false);
            }
        }

        private void OnLogMessageReceived(string condition, string stackTrace, LogType type)
        {
            if (!condition.Contains(LOG_TAG)) return;

            // ログをバッファリング
            lock (this)
            {
                _lastLogMessage = condition;
                _lastLogType = type;
                _hasPendingLog = true;
            }
        }

        private void OnEditorUpdate()
        {
            if (!_hasPendingLog || _ws?.State != WebSocketState.Open) return;

            var currentTime = UnityEditor.EditorApplication.timeSinceStartup;
            if (currentTime - _lastSendTime < THROTTLE_INTERVAL_SECONDS)
            {
                if (!_warningIssued)
                {
                    Debug.LogWarning("[EvenG2DebugBridge] Log frequency is too high. Some messages are being throttled.");
                    _warningIssued = true; // このセッションでは警告は一度だけ
                }
                return; // 間引く
            }

            string logMessage;
            LogType logType;

            lock (this)
            {
                if (!_hasPendingLog) return;
                logMessage = _lastLogMessage;
                logType = _lastLogType;
                _hasPendingLog = false;
            }

            _lastSendTime = currentTime;

            var message = logMessage.Replace(LOG_TAG, string.Empty).Trim();
            var timestamp = DateTime.Now.ToString("HH:mm:ss");
            var level = logType switch
            {
                LogType.Error => "Error",
                LogType.Exception => "Exception",
                LogType.Warning => "Warning",
                _ => "Log",
            };

            var payload = Serialize(new
            {
                type = "log",
                level = level,
                message = message,
                timestamp = timestamp,
                tag = LOG_TAG,
            });

            _ = SendRawAsync(payload);
            OnLogSent?.Invoke($"[{level}] {message}");
        }

        private async Task SendRawAsync(string json)
        {
            if (_ws?.State != WebSocketState.Open) return;
            try
            {
                var bytes = Encoding.UTF8.GetBytes(json);
                await _ws.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, _cts?.Token ?? CancellationToken.None);
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[EvenG2DebugBridge] 送信エラー: {ex.Message}");
            }
        }

        private static string Serialize(object obj)
        {
            // Unity 2020.1+ では JsonUtility はメインスレッド以外で動作しないため、
            // この実装は EditorApplication.update からの呼び出しに依存する。
            return JsonUtility.ToJson(obj);
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            UnityEditor.EditorApplication.update -= OnEditorUpdate;
            Application.logMessageReceivedThreaded -= OnLogMessageReceived;
            _cts?.Cancel();
            _cts?.Dispose();
            _ws?.Dispose();
        }
    }
}
