using System;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;

namespace EvenG2DebugBridge.Editor
{
    /// <summary>
    /// Even G2 Debug Bridge の Unity Editor 拡張ウィンドウ。
    ///
    /// 機能:
    ///   - Python ローカルサーバーへの WebSocket 接続の開始・停止
    ///   - 接続状態のリアルタイム表示
    ///   - スマートフォンのEven HubアプリでアクセスするURLのQRコード表示
    ///   - 直近の送信ログのプレビュー
    ///
    /// 開き方: Unity メニュー > Window > Even G2 Debug Bridge
    /// </summary>
    public class EvenG2DebugBridgeWindow : EditorWindow
    {
        // ----------------------------------------------------------------
        // 定数
        // ----------------------------------------------------------------
        private const string PREFS_SERVER_URL = "EvenG2DebugBridge_ServerUrl";
        private const string PREFS_HTTP_PORT  = "EvenG2DebugBridge_HttpPort";
        private const int    DEFAULT_WS_PORT   = 8766;
        private const int    DEFAULT_HTTP_PORT  = 8765;
        private const int    LOG_PREVIEW_MAX    = 8;

        // ----------------------------------------------------------------
        // フィールド
        // ----------------------------------------------------------------
        private EvenG2DebugClient _client;
        private bool   _isConnected;
        private string _serverUrl;
        private int    _httpPort;
        private string _localIp;
        private string _lastError;

        // QRコード表示用テクスチャ
        private Texture2D _qrTexture;
        private string    _qrTargetUrl;

        // ログプレビュー
        private readonly System.Collections.Generic.Queue<string> _logPreview
            = new System.Collections.Generic.Queue<string>();

        // スクロール位置
        private Vector2 _logScrollPos;

        // ----------------------------------------------------------------
        // メニュー登録
        // ----------------------------------------------------------------
        [MenuItem("Window/Even G2 Debug Bridge")]
        public static void ShowWindow()
        {
            var window = GetWindow<EvenG2DebugBridgeWindow>("Even G2 Debug Bridge");
            window.minSize = new Vector2(340, 480);
        }

        // ----------------------------------------------------------------
        // ライフサイクル
        // ----------------------------------------------------------------
        private void OnEnable()
        {
            _localIp    = GetLocalIpAddress();
            _serverUrl  = EditorPrefs.GetString(PREFS_SERVER_URL, $"ws://{_localIp}:{DEFAULT_WS_PORT}");
            _httpPort   = EditorPrefs.GetInt(PREFS_HTTP_PORT, DEFAULT_HTTP_PORT);
        }

        private void OnDisable()
        {
            _ = StopClientAsync();
        }

        private void OnDestroy()
        {
            _ = StopClientAsync();
        }

        // ----------------------------------------------------------------
        // GUI 描画
        // ----------------------------------------------------------------
        private void OnGUI()
        {
            DrawHeader();
            DrawConnectionSection();
            DrawQRCodeSection();
            DrawLogPreviewSection();
        }

        private void DrawHeader()
        {
            EditorGUILayout.Space(8);
            var titleStyle = new GUIStyle(EditorStyles.boldLabel)
            {
                fontSize  = 14,
                alignment = TextAnchor.MiddleCenter,
            };
            EditorGUILayout.LabelField("Even G2 Debug Bridge", titleStyle, GUILayout.Height(24));
            EditorGUILayout.LabelField(
                $"タグ: {EvenG2DebugClient.LOG_TAG} のログをスマートグラスに転送します",
                EditorStyles.centeredGreyMiniLabel
            );
            EditorGUILayout.Space(8);
            DrawHorizontalLine();
        }

        private void DrawConnectionSection()
        {
            EditorGUILayout.Space(6);
            EditorGUILayout.LabelField("サーバー設定", EditorStyles.boldLabel);

            EditorGUI.BeginDisabledGroup(_isConnected);
            {
                EditorGUI.BeginChangeCheck();
                _serverUrl = EditorGUILayout.TextField("WebSocket URL", _serverUrl);
                _httpPort  = EditorGUILayout.IntField("HTTP ポート (WebApp)", _httpPort);
                if (EditorGUI.EndChangeCheck())
                {
                    EditorPrefs.SetString(PREFS_SERVER_URL, _serverUrl);
                    EditorPrefs.SetInt(PREFS_HTTP_PORT, _httpPort);
                    // URL 変更時は QR コードをリセット
                    _qrTexture   = null;
                    _qrTargetUrl = null;
                }
            }
            EditorGUI.EndDisabledGroup();

            EditorGUILayout.Space(4);

            // 接続状態インジケーター
            var statusColor  = _isConnected ? Color.green : Color.gray;
            var statusLabel  = _isConnected ? "● 接続中" : "○ 未接続";
            var statusStyle  = new GUIStyle(EditorStyles.label) { normal = { textColor = statusColor } };
            EditorGUILayout.LabelField(statusLabel, statusStyle);

            if (!string.IsNullOrEmpty(_lastError))
            {
                var errorStyle = new GUIStyle(EditorStyles.helpBox) { normal = { textColor = new Color(1f, 0.4f, 0.4f) } };
                EditorGUILayout.LabelField(_lastError, errorStyle);
            }

            EditorGUILayout.Space(4);

            if (!_isConnected)
            {
                if (GUILayout.Button("接続開始", GUILayout.Height(32)))
                    _ = StartClientAsync();
            }
            else
            {
                if (GUILayout.Button("切断", GUILayout.Height(32)))
                    _ = StopClientAsync();
            }

            DrawHorizontalLine();
        }

        private void DrawQRCodeSection()
        {
            EditorGUILayout.Space(6);
            EditorGUILayout.LabelField("スマートフォン接続用 QR コード", EditorStyles.boldLabel);

            var webAppUrl = $"http://{_localIp}:{_httpPort}";
            EditorGUILayout.LabelField($"URL: {webAppUrl}", EditorStyles.miniLabel);

            if (GUILayout.Button("QR コードを生成", GUILayout.Height(28)))
            {
                GenerateQRCode(webAppUrl);
            }

            if (_qrTexture != null)
            {
                EditorGUILayout.Space(4);
                var rect = GUILayoutUtility.GetRect(200, 200, GUILayout.ExpandWidth(false));
                // ウィンドウ中央に配置
                rect.x = (position.width - 200) / 2f;
                GUI.DrawTexture(rect, _qrTexture, ScaleMode.ScaleToFit);
                EditorGUILayout.Space(4);
                EditorGUILayout.LabelField(
                    "スマートフォンのEven HubアプリでこのQRコードを読み取ってください",
                    EditorStyles.centeredGreyMiniLabel
                );
            }

            DrawHorizontalLine();
        }

        private void DrawLogPreviewSection()
        {
            EditorGUILayout.Space(6);
            EditorGUILayout.LabelField("送信ログ プレビュー", EditorStyles.boldLabel);

            _logScrollPos = EditorGUILayout.BeginScrollView(_logScrollPos, GUILayout.Height(120));
            {
                if (_logPreview.Count == 0)
                {
                    EditorGUILayout.LabelField("ログ待機中...", EditorStyles.centeredGreyMiniLabel);
                }
                else
                {
                    foreach (var log in _logPreview)
                    {
                        EditorGUILayout.LabelField(log, EditorStyles.miniLabel);
                    }
                }
            }
            EditorGUILayout.EndScrollView();
        }

        // ----------------------------------------------------------------
        // クライアント制御
        // ----------------------------------------------------------------
        private async Task StartClientAsync()
        {
            _lastError = null;
            _client    = new EvenG2DebugClient(_serverUrl);

            _client.OnConnectionStateChanged += connected =>
            {
                _isConnected = connected;
                if (!connected)
                    _lastError = $"サーバーへの接続が切断されました ({_serverUrl})";
                Repaint();
            };

            _client.OnLogSent += log =>
            {
                _logPreview.Enqueue(log);
                while (_logPreview.Count > LOG_PREVIEW_MAX)
                    _logPreview.Dequeue();
                Repaint();
            };

            try
            {
                await _client.StartAsync();
            }
            catch (Exception ex)
            {
                _lastError = ex.Message;
                _isConnected = false;
                Repaint();
            }
        }

        private async Task StopClientAsync()
        {
            if (_client == null) return;
            await _client.StopAsync();
            _client.Dispose();
            _client      = null;
            _isConnected = false;
            Repaint();
        }

        // ----------------------------------------------------------------
        // QR コード生成
        // ----------------------------------------------------------------
        /// <summary>
        /// 指定 URL の QR コードを Texture2D として生成する。
        /// 外部ライブラリ不要の純粋な C# 実装（ZXing.Net が利用可能な場合は差し替え推奨）。
        /// </summary>
        private void GenerateQRCode(string url)
        {
            if (_qrTargetUrl == url && _qrTexture != null) return;
            _qrTargetUrl = url;

            // ZXing.Net が利用可能かどうかを実行時に確認する
            // 利用可能な場合は高品質な QR コードを生成し、そうでない場合はプレースホルダーを表示する
            var zxingType = Type.GetType("ZXing.BarcodeWriter, ZXing.Unity");
            if (zxingType != null)
            {
                _qrTexture = GenerateQRCodeWithZXing(url, zxingType);
            }
            else
            {
                _qrTexture = GenerateQRCodePlaceholder(url);
            }
        }

        private static Texture2D GenerateQRCodeWithZXing(string url, Type barcodeWriterType)
        {
            try
            {
                // ZXing.Net を動的に呼び出す（コンパイル時依存を避けるため）
                dynamic writer = Activator.CreateInstance(barcodeWriterType);
                var formatType = Type.GetType("ZXing.BarcodeFormat, ZXing.Unity");
                if (formatType != null)
                {
                    var qrCodeValue = Enum.Parse(formatType, "QR_CODE");
                    writer.Format = qrCodeValue;
                }
                var optionsType = Type.GetType("ZXing.QrCode.QrCodeEncodingOptions, ZXing.Unity");
                if (optionsType != null)
                {
                    dynamic options = Activator.CreateInstance(optionsType);
                    options.Width  = 200;
                    options.Height = 200;
                    options.Margin = 1;
                    writer.Options = options;
                }
                Color32[] pixels = writer.Write(url);
                var tex = new Texture2D(200, 200);
                tex.SetPixels32(pixels);
                tex.Apply();
                return tex;
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[EvenG2DebugBridge] ZXing QR 生成失敗: {ex.Message}");
                return GenerateQRCodePlaceholder(url);
            }
        }

        /// <summary>
        /// ZXing.Net が未インストールの場合に表示するプレースホルダーテクスチャを生成する。
        /// </summary>
        private static Texture2D GenerateQRCodePlaceholder(string url)
        {
            const int size = 200;
            var tex = new Texture2D(size, size);
            var pixels = new Color[size * size];

            // 背景を白に塗りつぶす
            for (int i = 0; i < pixels.Length; i++)
                pixels[i] = Color.white;

            // 枠線を黒で描く
            for (int x = 0; x < size; x++)
            {
                for (int y = 0; y < size; y++)
                {
                    if (x < 4 || x >= size - 4 || y < 4 || y >= size - 4)
                        pixels[y * size + x] = Color.black;
                }
            }

            // 中央に「QR」テキスト代わりのパターンを描く（視覚的なプレースホルダー）
            int cx = size / 2, cy = size / 2;
            for (int dx = -20; dx <= 20; dx++)
            {
                for (int dy = -20; dy <= 20; dy++)
                {
                    if (Math.Abs(dx) == 20 || Math.Abs(dy) == 20 || (dx == 0 && dy == 0))
                        pixels[(cy + dy) * size + (cx + dx)] = Color.black;
                }
            }

            tex.SetPixels(pixels);
            tex.Apply();

            Debug.Log(
                $"[EvenG2DebugBridge] QR コードのプレースホルダーを表示しています。\n" +
                $"高品質な QR コードを生成するには ZXing.Net (ZXing.Unity) を\n" +
                $"Package Manager でインストールしてください。\n" +
                $"接続 URL: {url}"
            );
            return tex;
        }

        // ----------------------------------------------------------------
        // ユーティリティ
        // ----------------------------------------------------------------
        private static string GetLocalIpAddress()
        {
            try
            {
                using var socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, 0);
                socket.Connect("8.8.8.8", 65530);
                return ((IPEndPoint)socket.LocalEndPoint).Address.ToString();
            }
            catch
            {
                return "127.0.0.1";
            }
        }

        private static void DrawHorizontalLine()
        {
            EditorGUILayout.Space(4);
            var rect = EditorGUILayout.GetControlRect(false, 1);
            EditorGUI.DrawRect(rect, new Color(0.3f, 0.3f, 0.3f));
            EditorGUILayout.Space(4);
        }
    }
}
