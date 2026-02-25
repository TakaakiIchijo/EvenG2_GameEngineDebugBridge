using UnityEngine;

namespace EvenG2DebugBridge.Samples
{
    /// <summary>
    /// Even G2 Debug Bridge のサンプルロガー。
    ///
    /// このコンポーネントをシーン内の GameObject にアタッチすると、
    /// 一定間隔で [Even] タグ付きのサンプルログを出力します。
    ///
    /// 使い方:
    ///   1. Unity メニュー > Window > Even G2 Debug Bridge を開く
    ///   2. 「接続開始」ボタンをクリックする
    ///   3. このシーンを再生する
    ///   4. Even G2 スマートグラス（または Simulator）にログが表示されることを確認する
    /// </summary>
    public class EvenG2DebugSampleLogger : MonoBehaviour
    {
        [Header("ログ出力設定")]
        [Tooltip("ログを出力する間隔（秒）")]
        [SerializeField] private float _intervalSeconds = 3f;

        [Tooltip("出力するサンプルメッセージの一覧")]
        [SerializeField] private string[] _sampleMessages = new[]
        {
            "プレイヤーがエリア A に入りました",
            "FPS: 60 | メモリ: 128MB",
            "アイテム取得: ソード x1",
            "ボス戦開始 - HP: 1000",
            "チェックポイント到達",
        };

        private float _timer;
        private int   _messageIndex;

        private void Update()
        {
            _timer += Time.deltaTime;
            if (_timer < _intervalSeconds) return;

            _timer = 0f;
            SendSampleLog();
        }

        private void SendSampleLog()
        {
            if (_sampleMessages == null || _sampleMessages.Length == 0) return;

            var message = _sampleMessages[_messageIndex % _sampleMessages.Length];
            _messageIndex++;

            // [Even] タグを付けてログを出力する
            // このタグが付いたログのみ Even G2 に転送される
            Debug.Log($"{EvenG2DebugClient.LOG_TAG} {message}");
        }

        /// <summary>
        /// Inspector や他のスクリプトから任意のメッセージを送信するためのヘルパーメソッド。
        /// </summary>
        /// <param name="message">送信するメッセージ</param>
        public static void SendToG2(string message)
        {
            Debug.Log($"{EvenG2DebugClient.LOG_TAG} {message}");
        }

        /// <summary>
        /// 警告レベルのメッセージを送信する。
        /// </summary>
        public static void SendWarningToG2(string message)
        {
            Debug.LogWarning($"{EvenG2DebugClient.LOG_TAG} {message}");
        }

        /// <summary>
        /// エラーレベルのメッセージを送信する。
        /// </summary>
        public static void SendErrorToG2(string message)
        {
            Debug.LogError($"{EvenG2DebugClient.LOG_TAG} {message}");
        }
    }
}
