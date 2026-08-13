using System;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;

namespace EvenG2DebugBridge.Editor
{
    /// <summary>
    /// Unity Editorの[Even]ログをエンジン非依存ブリッジサーバーへ送信します。
    /// logMessageReceivedThreaded内ではUnity APIを呼ばず、EditorApplication.update
    /// （メインスレッド）でJSON化と送信を行います。
    /// </summary>
    internal sealed class EvenG2DebugClient : IDisposable
    {
        public const string LOG_TAG = EvenG2DebugBridgeConstants.LogTag;
        public const double SendIntervalSeconds = 0.25d;

        private readonly string _serverUrl;
        private readonly object _sync = new object();

        private ClientWebSocket _webSocket;
        private CancellationTokenSource _cancellation;
        private Task _inFlightSend;
        private bool _started;
        private bool _disposed;

        private string _pendingCondition;
        private LogType _pendingLogType;
        private bool _hasPendingLog;
        private string _pendingPreview;
        private double _lastSendTime;
        private int _coalescedLogCount;
        private bool _throttleWarningIssued;

        private bool _pendingConnectionNotification;
        private bool _pendingConnectionState;
        private string _pendingConnectionDetail;

        public event Action<bool, string> ConnectionStateChanged;
        public event Action<string> LogSent;

        public bool IsConnected => _webSocket != null && _webSocket.State == WebSocketState.Open;
        public int CoalescedLogCount { get; private set; }

        public EvenG2DebugClient(string serverUrl)
        {
            if (string.IsNullOrWhiteSpace(serverUrl))
            {
                throw new ArgumentException("WebSocket URLを指定してください。", nameof(serverUrl));
            }

            _serverUrl = serverUrl;
        }

        public async Task StartAsync()
        {
            ThrowIfDisposed();
            if (_started)
            {
                return;
            }

            _cancellation = new CancellationTokenSource();
            await ConnectAsync();
            PublishQueuedConnectionState();
            if (!IsConnected)
            {
                return;
            }

            _started = true;
            Application.logMessageReceivedThreaded += OnLogMessageReceived;
            EditorApplication.update += OnEditorUpdate;
        }

        public async Task StopAsync()
        {
            if (_disposed)
            {
                return;
            }

            _started = false;
            Application.logMessageReceivedThreaded -= OnLogMessageReceived;
            EditorApplication.update -= OnEditorUpdate;
            _cancellation?.Cancel();

            if (_webSocket != null && _webSocket.State == WebSocketState.Open)
            {
                try
                {
                    await _webSocket.CloseAsync(
                        WebSocketCloseStatus.NormalClosure,
                        "Stopped by Unity Editor",
                        CancellationToken.None);
                }
                catch (WebSocketException)
                {
                    // 接続断と競合した終了処理は無視する。
                }
            }

            QueueConnectionState(false, "サーバーから切断しました");
        }

        private async Task ConnectAsync()
        {
            _webSocket?.Dispose();
            _webSocket = new ClientWebSocket();

            try
            {
                await _webSocket.ConnectAsync(new Uri(_serverUrl), _cancellation.Token);
                await SendRawAsync(JsonUtility.ToJson(new EngineHelloPayload()));
                QueueConnectionState(true, "サーバーに接続しました");
                _ = ReceiveLoopAsync();
            }
            catch (Exception exception) when (!(exception is OperationCanceledException))
            {
                QueueConnectionState(false, $"接続に失敗しました: {exception.Message}");
            }
        }

        private async Task ReceiveLoopAsync()
        {
            var buffer = new byte[1024];
            try
            {
                while (IsConnected && !_cancellation.IsCancellationRequested)
                {
                    var result = await _webSocket.ReceiveAsync(
                        new ArraySegment<byte>(buffer),
                        _cancellation.Token);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        QueueConnectionState(false, "サーバー側から接続を終了しました");
                        return;
                    }
                }
            }
            catch (OperationCanceledException)
            {
                // 停止操作による正常終了。
            }
            catch (Exception exception)
            {
                QueueConnectionState(false, $"受信エラー: {exception.Message}");
            }
        }

        private void OnLogMessageReceived(string condition, string stackTrace, LogType type)
        {
            if (string.IsNullOrEmpty(condition) ||
                condition.IndexOf(LOG_TAG, StringComparison.Ordinal) < 0)
            {
                return;
            }

            lock (_sync)
            {
                if (_hasPendingLog)
                {
                    _coalescedLogCount++;
                }

                _pendingCondition = condition;
                _pendingLogType = type;
                _hasPendingLog = true;
            }
        }

        private void OnEditorUpdate()
        {
            PublishQueuedConnectionState();
            PublishCompletedSend();

            if (!_started || !IsConnected || (_inFlightSend != null && !_inFlightSend.IsCompleted))
            {
                return;
            }

            var now = EditorApplication.timeSinceStartup;
            if (now - _lastSendTime < SendIntervalSeconds)
            {
                WarnAboutThrottleIfNeeded();
                return;
            }

            string condition;
            LogType logType;
            int coalescedCount;
            lock (_sync)
            {
                if (!_hasPendingLog)
                {
                    return;
                }

                condition = _pendingCondition;
                logType = _pendingLogType;
                coalescedCount = _coalescedLogCount;
                _hasPendingLog = false;
                _coalescedLogCount = 0;
            }

            if (coalescedCount > 0)
            {
                CoalescedLogCount += coalescedCount;
                WarnAboutThrottleIfNeeded();
            }

            var payload = new EngineLogPayload
            {
                level = ToProtocolLevel(logType),
                message = condition.Replace(LOG_TAG, string.Empty).Trim(),
                timestamp = DateTime.Now.ToString("HH:mm:ss"),
                tag = LOG_TAG,
            };

            _pendingPreview = $"[{payload.level}] {payload.message}";
            _lastSendTime = now;
            _inFlightSend = SendRawAsync(JsonUtility.ToJson(payload));
        }

        private void PublishCompletedSend()
        {
            if (_inFlightSend == null || !_inFlightSend.IsCompleted)
            {
                return;
            }

            var completed = _inFlightSend;
            _inFlightSend = null;
            if (completed.IsFaulted || completed.IsCanceled)
            {
                QueueConnectionState(false, "ログ送信に失敗しました");
                return;
            }

            LogSent?.Invoke(_pendingPreview);
            _pendingPreview = null;
        }

        private void WarnAboutThrottleIfNeeded()
        {
            if (_throttleWarningIssued)
            {
                return;
            }

            _throttleWarningIssued = true;
            Debug.LogWarning(
                "[EvenG2DebugBridge] Log frequency is too high. " +
                "Intermediate messages are coalesced to stay within the configured 250ms send interval.");
        }

        private async Task SendRawAsync(string json)
        {
            if (!IsConnected)
            {
                throw new WebSocketException("WebSocket is not connected.");
            }

            var bytes = Encoding.UTF8.GetBytes(json);
            await _webSocket.SendAsync(
                new ArraySegment<byte>(bytes),
                WebSocketMessageType.Text,
                true,
                _cancellation.Token);
        }

        private void QueueConnectionState(bool connected, string detail)
        {
            lock (_sync)
            {
                _pendingConnectionState = connected;
                _pendingConnectionDetail = detail;
                _pendingConnectionNotification = true;
            }
        }

        private void PublishQueuedConnectionState()
        {
            bool hasUpdate;
            bool connected;
            string detail;
            lock (_sync)
            {
                hasUpdate = _pendingConnectionNotification;
                connected = _pendingConnectionState;
                detail = _pendingConnectionDetail;
                _pendingConnectionNotification = false;
            }

            if (hasUpdate)
            {
                ConnectionStateChanged?.Invoke(connected, detail);
            }
        }

        private static string ToProtocolLevel(LogType logType)
        {
            switch (logType)
            {
                case LogType.Error:
                    return "Error";
                case LogType.Exception:
                    return "Exception";
                case LogType.Warning:
                    return "Warning";
                default:
                    return "Log";
            }
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
            {
                throw new ObjectDisposedException(nameof(EvenG2DebugClient));
            }
        }

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            _started = false;
            Application.logMessageReceivedThreaded -= OnLogMessageReceived;
            EditorApplication.update -= OnEditorUpdate;
            _cancellation?.Cancel();
            _cancellation?.Dispose();
            _webSocket?.Dispose();
        }

        [Serializable]
        private sealed class EngineHelloPayload
        {
            public string type = "engine";
            public int protocol_version = 1;
        }

        [Serializable]
        private sealed class EngineLogPayload
        {
            public string type = "log";
            public string level;
            public string message;
            public string timestamp;
            public string tag;
            public int protocol_version = 1;
        }
    }
}
