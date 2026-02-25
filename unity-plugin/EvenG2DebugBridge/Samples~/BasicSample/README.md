# Basic Sample - Even G2 Debug Bridge

## このサンプルについて

`EvenG2DebugSampleLogger` コンポーネントを使った最小構成のサンプルです。
一定間隔で `[Even]` タグ付きのログを出力し、Even G2 スマートグラスにリアルタイム表示されることを確認できます。

## セットアップ手順

1. `BasicSampleScene` を開く（`Scenes/BasicSampleScene.unity`）
2. Unity メニュー > **Window > Even G2 Debug Bridge** を開く
3. Python サーバーを起動する（`server/` ディレクトリで `python server.py`）
4. Debug Bridge ウィンドウで **接続開始** をクリックする
5. Even Hub Simulator（または実機）でフロントエンドの URL を開く
6. シーンを **再生** する
7. 3秒ごとにサンプルメッセージがグラスに表示されることを確認する

## サンプルコードの使い方

```csharp
// 任意のスクリプトから Even G2 にメッセージを送信する
EvenG2DebugSampleLogger.SendToG2("プレイヤーがエリアに入りました");
EvenG2DebugSampleLogger.SendWarningToG2("HPが残り20%です");
EvenG2DebugSampleLogger.SendErrorToG2("アイテムのロードに失敗しました");

// または直接 Debug.Log を使う
Debug.Log("[Even] 任意のメッセージ");
```
