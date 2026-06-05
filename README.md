# EvenG2 Game Engine Debug Bridge

## 概要

ゲームのテストプレイ中に、Unityのコンソールログ（`Debug.Log`）をEven G2スマートグラス上にリアルタイムで表示するためのツールです。特にゲーム展示会のような環境で、開発者が秘密のログを確認する用途を想定しています。

将来的にUnreal EngineやGodotのような他のゲームエンジンにも対応できるよう、エンジン非依存のアーキテクチャで設計されています。

## 主な機能

- **リアルタイムログストリーミング**: Unity Editorで `[Even]` タグを付けたログが、即座にEven G2グラスにストリーミングされます。
- **エンジン非依存アーキテクチャ**: バックエンドサーバー（Python）とフロントエンド（TypeScript）はUnityから独立しており、将来的に他のゲームエンジンへも容易に統合可能です。
- **BLE帯域を考慮したスロットリング**: Unityプラグインは、BLE接続の帯域を圧迫しないよう、ログメッセージを自動的に間引きます（250ms間隔）。送信頻度が高すぎる場合はUnity Editorのコンソールに警告を表示します。
- **ログレベルの色分け表示**: `[Log]`（緑）・`[Warning]`（黄）・`[Error]`（赤）・`[Exception]`（赤）の各レベルに応じた色でグラスに表示されます。
- **接続状態の詳細表示**: 接続成功・切断・接続失敗の各状態をWebアプリ上でリアルタイムに表示します。

## システム構成

本システムは、主に3つのコンポーネントで構成されています。

1. **Pythonローカルサーバー** (`server/`): ゲームエンジンからログを受信し、Even HubにWebアプリケーションを配信するWebSocketおよびHTTPサーバーです。
2. **Even G2 Webアプリケーション** (`frontend/`): Even Hub（またはシミュレーター）上で動作し、グラスにログを表示するVite + TypeScript製のアプリケーションです。
3. **Unity Editorプラグイン** (`unity-plugin/`): コンソールログを監視し、`[Even]` タグをフィルタリングしてローカルサーバーに送信するUnityパッケージです。

## 動作要件

| コンポーネント | バージョン |
| :--- | :--- |
| Python | 3.9 以降 |
| Node.js | 18 以降 |
| Unity | 2021.3 LTS 以降 |
| Even Hub SDK | 0.0.10 |
| Even Hub Simulator | 0.4.1 |
| スマートフォン | Even Hubアプリをインストール済みのiOS/Android端末 |

## 利用方法

### 1. ローカルサーバーの起動

venvで仮想環境を作成します。

```bash
py -m venv ~/evendebug
source ~/evendebug/bin/activate  # Windows: ~/evendebug/Scripts/activate
```

`server` ディレクトリに移動し、依存関係をインストールしてサーバーを起動します。

```bash
cd server
pip install -r requirements.txt
python server.py
```

サーバーは `0.0.0.0` のポート `8766`（WebSocket）と `8767`（HTTP）で起動します。

### 2. Unityパッケージのインストール

1. Unityプロジェクトを開きます。
2. `Window > Package Manager` を選択します。
3. `+` ボタンをクリックし、`Add package from disk...` を選択します。
4. `unity-plugin/EvenG2DebugBridge` ディレクトリに移動し、`package.json` ファイルを選択します。

### 3. Unityからの接続

1. Unityで `Window > Even G2 Debug Bridge` を開きます。
2. ウィンドウにローカルサーバーのURLを含むQRコードが表示されます。
3. スマートフォンのEven HubアプリでQRコードをスキャンし、Webアプリケーションに接続します。
4. Unity Editorのウィンドウで **Start Connection** をクリックします。

### 4. ログの表示

Unity コンソールのログメッセージに `[Even]` タグを含めると、その内容がEven G2グラスに表示されます。

```csharp
Debug.Log("[Even] Player health: 100");
Debug.LogWarning("[Even] Low ammo!");
Debug.LogError("[Even] NullReferenceException detected");
```

ログ送信頻度が250ms間隔（毎秒4回）を超えた場合、Unityコンソールに以下の警告が表示されます。

```
[EvenG2DebugBridge] Log frequency is too high. Some messages are being throttled.
```

## 開発者向け: モックテスト

Unity Editorを使わずにサーバーとフロントエンドの動作を確認する場合は、モックスクリプトを使用します。

```bash
cd server
python mock_engine.py --mode sequential   # 通常ログを順番に送信
python mock_engine.py --mode levels       # 各ログレベルを送信
python mock_engine.py --mode rapid        # 高頻度送信（スロットリングの確認）
python mock_engine.py --mode long         # 長文メッセージの送信
```

## ライセンス

このプロジェクトはMITライセンスです。詳細は [LICENSE](LICENSE) ファイルをご覧ください。

---

# EvenG2 Game Engine Debug Bridge (English)

## Overview

This tool allows you to display Unity's console logs (`Debug.Log`) in real-time on Even G2 smart glasses during game test plays, especially useful for checking secret logs at events like game exhibitions.

It is designed to be engine-agnostic, with the potential to support other engines like Unreal and Godot in the future.

## Features

- **Real-time Log Streaming**: Logs tagged with `[Even]` in the Unity Editor are instantly streamed to the Even G2 glasses.
- **Engine-Agnostic Architecture**: The backend server (Python) and frontend (TypeScript) are independent of Unity, allowing for future integration with other game engines.
- **BLE-Aware Throttling**: The Unity plugin automatically throttles log messages (250ms interval) to prevent overloading the BLE connection. A warning is shown in the Unity console if the log frequency is too high.
- **Log Level Color Coding**: Logs are displayed in color based on their level: `[Log]` (green), `[Warning]` (yellow), `[Error]` (red), `[Exception]` (red).
- **Detailed Connection Status**: The web app shows real-time connection status including connected, disconnected, and connection failed states.

## System Architecture

The system consists of three main components:

1. **Python Local Server** (`server/`): A WebSocket and HTTP server that receives logs from the game engine and serves the web application to the Even Hub.
2. **Even G2 Web Application** (`frontend/`): A Vite + TypeScript application that runs on the Even Hub (or Simulator) and displays the logs on the glasses.
3. **Unity Editor Plugin** (`unity-plugin/`): A Unity package that monitors console logs, filters for the `[Even]` tag, and sends them to the local server.

## Requirements

| Component | Version |
| :--- | :--- |
| Python | 3.9+ |
| Node.js | 18+ |
| Unity | 2021.3 LTS or later |
| Even Hub SDK | 0.0.10 |
| Even Hub Simulator | 0.4.1 |
| Smartphone | iOS/Android with Even Hub app installed |

## Getting Started

### 1. Run the Local Server

Create a virtual environment with venv:

```bash
py -m venv ~/evendebug
source ~/evendebug/bin/activate  # Windows: ~/evendebug/Scripts/activate
```

Navigate to the `server` directory and start the server:

```bash
cd server
pip install -r requirements.txt
python server.py
```

The server will start on `0.0.0.0` at port `8766` (WebSocket) and `8767` (HTTP).

### 2. Install the Unity Package

1. Open your Unity project.
2. Go to `Window > Package Manager`.
3. Click the `+` button and select `Add package from disk...`.
4. Navigate to the `unity-plugin/EvenG2DebugBridge` directory and select the `package.json` file.

### 3. Connect from Unity

1. In Unity, go to `Window > Even G2 Debug Bridge`.
2. The window will display a QR code containing the local server's URL.
3. Open the Even Hub app on your smartphone and scan the QR code to connect to the web application.
4. Click **Start Connection** in the Unity Editor window.

### 4. View Logs

Any log message in the Unity console that includes the `[Even]` tag will be displayed on your Even G2 glasses.

```csharp
Debug.Log("[Even] Player health: 100");
Debug.LogWarning("[Even] Low ammo!");
Debug.LogError("[Even] NullReferenceException detected");
```

If the log frequency exceeds 250ms intervals (4 times per second), the following warning will appear in the Unity console:

```
[EvenG2DebugBridge] Log frequency is too high. Some messages are being throttled.
```

## For Developers: Mock Testing

To test the server and frontend without Unity Editor, use the mock script:

```bash
cd server
python mock_engine.py --mode sequential   # Send logs sequentially
python mock_engine.py --mode levels       # Send each log level
python mock_engine.py --mode rapid        # High-frequency sending (throttle test)
python mock_engine.py --mode long         # Send long messages
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
