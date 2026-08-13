# EvenG2 Game Engine Debug Bridge

> **言語:** [日本語](#日本語) / [English](#english)

<a id="日本語"></a>

## 概要

**EvenG2 Game Engine Debug Bridge** は、ゲームプレイ中に開発者だけが確認したいログをEven G2スマートグラスへ送る、ローカルネットワーク向けのデバッグ支援ツールです。Unity Editorプラグインは`[Even]`タグを含むコンソールログだけを送信します。PythonブリッジサーバーとEven Hub Webアプリはゲームエンジン固有の情報を持たないため、同じ通信プロトコルを実装すればUnreal EngineやGodotへも接続できます。

フロントエンドはEven Hub SDK **0.0.13**、Even Hub Simulator **0.8.0**、Even Hub CLI **0.1.13**を基準にしています。SDK 0.0.13を使う配布パッケージでは、Even Realities App **2.2.6以降**とNode.js **20以降または22以降**が必要です。[1]

## 構成

| コンポーネント | ディレクトリ | 役割 |
| :--- | :--- | :--- |
| ローカルブリッジサーバー | `server/` | WebSocketでエンジン側ログを受信し、Webアプリへ配信します。ビルド済みWebアプリもHTTP配信します。 |
| Even Hub Webアプリ | `frontend/` | Even App WebView上でログを受信し、G2のテキストコンテナに表示します。 |
| Unity Editorプラグイン | `unity-plugin/EvenG2DebugBridge/` | Unity Editorログを監視し、送信対象を`[Even]`タグに限定します。 |
| モックエンジン | `server/mock_engine.py` | Unityを起動せず、バックエンドとWebアプリの統合テストを実行します。 |

## 主な仕様

| 項目 | 実装内容 |
| :--- | :--- |
| 送信対象 | Unityの`Log`、`Warning`、`Error`、`Exception`のうち、本文に`[Even]`を含むものだけを送信します。 |
| Unity側の送信制御 | `Application.logMessageReceivedThreaded`では最新ログをバッファするだけにし、メインスレッドから**250ms間隔**で送信します。過剰なログは最新1件へ集約し、Unity Consoleに一度だけ警告します。 |
| Webアプリ側の表示制御 | Unity以外の将来のクライアントも考慮し、Webアプリ側でも最新ログを保持して最大**毎秒4回**に更新を制限します。 |
| G2データ量 | UTF-8で最大**880バイト**に切り詰めます。日本語を含む表示データを保守的に900バイト未満へ収めるためです。実機での最終確認は必須です。 |
| SDKページ操作 | 初回だけ`createStartUpPageContainer()`でテキストコンテナを作成し、以後は`textContainerUpgrade()`で本文だけを更新します。 |
| 終了操作 | G2のダブルクリックで終了ダイアログを要求し、イベント購読とタイマーを解放します。 |
| パッケージ化 | `app.manifest.template.json`から接続先LANオリジンを含む`app.json`を生成し、`.ehpk`へパッケージ化します。SDK 0.0.13のマニフェスト要件に従います。[1] |

G2ページはテキストコンテナを1個だけ使用し、イベント捕捉コンテナも1個だけにしています。これはSDKのページコンテナ制約に沿うためです。[1]

## 動作要件

| 項目 | 要件 |
| :--- | :--- |
| Python | Python 3.9以降。`websockets` 16系を使用します。 |
| Node.js | `^20.0.0` または `>=22.0.0`。[2] |
| Unity | Unity 2021.3 LTS以降。 |
| Even Hub SDK | `@evenrealities/even_hub_sdk` 0.0.13。 |
| Even Hub Simulator | 0.8.0（開発・検証用）。 |
| Even Hub CLI | 0.1.13（QR Local Testing・パッケージ化用）。 |
| Even Realities App | 2.2.6以降（SDK 0.0.13の配布パッケージ）。[2] |
| ネットワーク | 開発PCとスマートフォンを同一LANへ接続します。実機のLocal TestingではPCのLAN IPアドレスを使用します。[3] |

## 導入と実行

### 1. リポジトリの取得

```bash
git clone https://github.com/TakaakiIchijo/EvenG2_GameEngineDebugBridge.git
cd EvenG2_GameEngineDebugBridge
```

### 2. Pythonローカルサーバーの起動

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate                 # Windowsでは .venv\Scripts\activate
pip install -r requirements.txt
python server.py
```

サーバーは既定で以下を起動します。

| 用途 | 既定ポート | 例 |
| :--- | :--- | :--- |
| WebSocket（ゲームエンジン・Webアプリ） | `8766` | `ws://<LAN_IP>:8766` |
| HTTP（ビルド済みWebアプリ） | `8765` | `http://<LAN_IP>:8765` |
| ヘルスチェック | `8765` | `http://<LAN_IP>:8765/health` |

HTTP配信には`frontend/dist`が必要です。初回またはフロントエンド変更後は、次節の`npm run build`を先に実行してください。

### 3. フロントエンドのビルドとシミュレーター検証

SDKはプロジェクトへ、SimulatorとCLIはグローバル環境へ導入します。

```bash
cd frontend
npm install
npm run build

# 一度だけ導入する開発ツール
npm install -g @evenrealities/evenhub-simulator@0.8.0 @evenrealities/evenhub-cli@0.1.13

# Viteを使う開発時のみ、別ターミナルで実行
npm run dev
evenhub-simulator http://localhost:5173 --automation-port 9898
```

Simulatorでは、グラス表示領域ではなくWebUI上の **Up / Down / Click / Double Click** ボタンで入力を確認してください。自動検証では`/api/ping`、`/api/console`、`/api/screenshot/glasses`を利用できます。[4]

### 4. Unityパッケージの導入

1. Unityプロジェクトで **Window > Package Manager** を開きます。
2. `+`から **Add package from disk...** を選びます。
3. `unity-plugin/EvenG2DebugBridge/package.json`を指定します。
4. 必要に応じてPackage Managerの **Samples** タブから **Basic Sample** をImportします。
5. `Samples/Even G2 Debug Bridge/Basic Sample/Scenes/BasicSampleScene.unity`を開くと、3秒ごとに`[Even]`ログを出力するサンプルを確認できます。

### 5. Unity Editorからの接続とログ送信

1. ローカルサーバーを起動します。
2. Unityで **Window > Even G2 Debug Bridge** を開き、WebSocket URLを確認します。
3. **接続開始**を選択します。
4. スマートフォン上のEven HubでローカルWebアプリを開きます。
5. `[Even]`タグを含むログを出力します。

```csharp
Debug.Log("[Even] Player health: 100");
Debug.LogWarning("[Even] Low ammo");
Debug.LogError("[Even] EnemyController reference is missing");
```

ログ頻度が送信可能な間隔を超えると、Unity Consoleに次の警告を一度だけ出力します。中間ログは破棄され、最新ログが送信されます。

```text
[EvenG2DebugBridge] Log frequency is too high. Intermediate messages are coalesced to stay within the configured 250ms send interval.
```

> **QRコードについて:** Unity Editorウィンドウで読み取り可能なQRコードを生成するには、Unityプロジェクト側へZXing.Net（`ZXing.Unity`）を導入してください。未導入時はURLを示すプレースホルダーになるため、スキャンには使えません。代わりに、次節の`evenhub qr`を使用してください。

### 6. 実機のLocal Testing

実機確認では、PCのLAN IPアドレスを指定したURLをQR化します。例えばローカルサーバーが`192.168.1.20`の場合は次の通りです。

```bash
evenhub qr --url "http://192.168.1.20:8765"
```

開発PCとスマートフォンを同一LANへ接続してください。パッケージ化して配布する場合は、次節のマニフェスト生成で接続先オリジンを`network.whitelist`に含める必要があります。`whitelist`とサーバー側CORSは別の制約です。[3]

### 7. Even Hubパッケージの生成

`app.json`はLAN接続先ごとに生成するため、Git管理しません。`<LAN_IP>`を実際のPCアドレスに置き換えます。

```bash
cd frontend
EVEN_BRIDGE_ORIGIN="http://<LAN_IP>:8765" npm run pack
```

成功すると`release/even-g2-debug-bridge.ehpk`が生成されます。マニフェストにはSDK 0.0.13およびEven App 2.2.6の最小バージョンを設定します。[1]

## モックエンジンによる統合テスト

Unityを起動せずにサーバーとフロントエンドを確認できます。サーバーとSimulatorまたはEven Hub Webアプリを起動してから実行してください。

```bash
cd server
python mock_engine.py --mode sequential
python mock_engine.py --mode levels
python mock_engine.py --mode rapid --count 20 --interval 0.05
python mock_engine.py --mode long
```

| シナリオ | 確認内容 |
| :--- | :--- |
| `sequential` | 通常ログの順次受信と最新ログ表示。 |
| `levels` | Log、Warning、Error、Exceptionのプロトコル受信。 |
| `rapid` | 高頻度ログを最新値へ集約し、G2更新を250ms間隔に保つこと。 |
| `long` | 日本語を含む長文をUTF-8の880バイト以内に切り詰めること。 |

このリポジトリではSimulator v0.8.0、モックエンジン、Pythonサーバーを用いて、通常ログ、高頻度20件、長文、ダブルクリック終了を検証しています。SimulatorはBLE帯域・実機フォント・端末固有の接続状態を再現しないため、最終的な表示量と接続安定性は実機のLocal Testing、Private Testing、Beta Testingで確認してください。[4]

## セキュリティと運用上の注意

このツールは展示会や社内テストなど、信頼できる同一LAN内での利用を想定しています。ローカルブリッジサーバーをインターネットへ直接公開しないでください。また、配布する`.ehpk`にはAPIキー、トークン、秘密鍵を含めないでください。[3] デバッグログにも個人情報、認証情報、未公開コンテンツを含めない運用が必要です。

## ライセンス

MIT Licenseです。詳細は[LICENSE](LICENSE)を参照してください。

## 参照資料

[1] [Even Hub SDK — Glasses UIとパッケージ要件](https://www.npmjs.com/package/@evenrealities/even_hub_sdk)

[2] [Even Hub SDK README — SDK 0.0.13の実行要件](https://www.npmjs.com/package/@evenrealities/even_hub_sdk)

[3] [Even Hub開発ガイド — ネットワーク権限、CORS、Local Testing](https://hub.evenrealities.com/docs)

[4] [Even Hub Simulator — 自動化と検証](https://www.npmjs.com/package/@evenrealities/evenhub-simulator)

---

<a id="english"></a>

# EvenG2 Game Engine Debug Bridge — English

## Overview

**EvenG2 Game Engine Debug Bridge** is a local-network debugging tool that sends developer-only logs to Even G2 smart glasses during game playtests. The Unity Editor plugin forwards only console messages that contain the `[Even]` tag. The Python bridge server and Even Hub web app are independent of any game engine, so Unreal Engine or Godot clients can use the same transport protocol in the future.

The frontend targets **Even Hub SDK 0.0.13**, **Even Hub Simulator 0.8.0**, and **Even Hub CLI 0.1.13**. An SDK 0.0.13 package requires Even Realities App **2.2.6 or later** and Node.js **20 or later, or 22 or later**. [1]

## Components

| Component | Directory | Responsibility |
| :--- | :--- | :--- |
| Local bridge server | `server/` | Receives logs through WebSocket, broadcasts them to the web app, and serves the built frontend over HTTP. |
| Even Hub web app | `frontend/` | Receives bridge messages in the Even App WebView and writes them to the G2 text container. |
| Unity Editor plugin | `unity-plugin/EvenG2DebugBridge/` | Watches Unity Editor logs and filters messages by the `[Even]` tag. |
| Mock engine | `server/mock_engine.py` | Runs server and web-app integration tests without launching Unity. |

## Core behavior

| Area | Behavior |
| :--- | :--- |
| Unity sending | The threaded Unity log callback only buffers the newest message. Serialization and sends run on the Editor main thread every **250ms**. Intermediate logs are coalesced and a single warning is printed to the Unity Console. |
| Frontend rendering | The web app also coalesces incoming entries and limits G2 updates to **four per second**, protecting future Unreal or Godot clients that do not implement Unity-side throttling. |
| G2 payload | The display text is truncated by UTF-8 byte length to **880 bytes**, a conservative value below the practical 900-byte target for Japanese text. Validate the final limit on hardware. |
| SDK lifecycle | The app creates one startup text container, then updates only its content with `textContainerUpgrade()`. |
| Exit | A G2 double click requests the system close dialog and releases event subscriptions and timers. |
| Packaging | A per-LAN `app.json` is generated from `app.manifest.template.json`, then packaged as `.ehpk` with the SDK 0.0.13 manifest requirements. [1] |

## Requirements

| Item | Requirement |
| :--- | :--- |
| Python | Python 3.9+ with `websockets` 16.x. |
| Node.js | `^20.0.0` or `>=22.0.0`. [2] |
| Unity | Unity 2021.3 LTS or later. |
| Even Hub SDK | `@evenrealities/even_hub_sdk` 0.0.13. |
| Simulator / CLI | Even Hub Simulator 0.8.0 and Even Hub CLI 0.1.13. |
| Even Realities App | 2.2.6 or later for the SDK 0.0.13 package. [2] |
| Network | Development PC and smartphone on the same LAN for Local Testing. [3] |

## Quick start

### Run the bridge server

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python server.py
```

The default endpoints are `ws://<LAN_IP>:8766`, `http://<LAN_IP>:8765`, and `http://<LAN_IP>:8765/health`. Run `npm run build` in `frontend/` before using the server's HTTP hosting.

### Build and test the web app

```bash
cd frontend
npm install
npm run build
npm install -g @evenrealities/evenhub-simulator@0.8.0 @evenrealities/evenhub-cli@0.1.13
npm run dev
evenhub-simulator http://localhost:5173 --automation-port 9898
```

Use the Simulator WebUI controls—not the glass display—to test input. Its automation API exposes `/api/ping`, `/api/console`, and `/api/screenshot/glasses`. [4]

### Install the Unity package and send logs

Use **Window > Package Manager > Add package from disk...** and select `unity-plugin/EvenG2DebugBridge/package.json`. Then open **Window > Even G2 Debug Bridge**, enter the bridge WebSocket URL, and select **接続開始**.

```csharp
Debug.Log("[Even] Player health: 100");
Debug.LogWarning("[Even] Low ammo");
Debug.LogError("[Even] EnemyController reference is missing");
```

The included Basic Sample scene is located at `Samples/Even G2 Debug Bridge/Basic Sample/Scenes/BasicSampleScene.unity` after sample import.

> **QR code note:** The Unity Editor window generates a scannable QR code only when ZXing.Net (`ZXing.Unity`) is installed in the Unity project. Otherwise it shows a non-scannable placeholder. Use `evenhub qr` as the reliable alternative.

### Local Testing on hardware

```bash
evenhub qr --url "http://192.168.1.20:8765"
```

Replace the IP address with the development PC's LAN address. For packaged distribution, generate `app.json` with the same bridge origin so it is included in `network.whitelist`; this requirement is separate from server-side CORS. [3]

### Generate an `.ehpk` package

```bash
cd frontend
EVEN_BRIDGE_ORIGIN="http://<LAN_IP>:8765" npm run pack
```

The output is `release/even-g2-debug-bridge.ehpk`. The generated manifest sets `min_sdk_version` to `0.0.13` and `min_app_version` to `2.2.6`. [1]

## Mock engine tests

```bash
cd server
python mock_engine.py --mode sequential
python mock_engine.py --mode levels
python mock_engine.py --mode rapid --count 20 --interval 0.05
python mock_engine.py --mode long
```

Simulator testing in this repository covers sequential logs, 20 high-frequency entries, long UTF-8 messages, and double-click shutdown. Simulator does not model BLE bandwidth, device fonts, or native connection behavior. Use Local, Private, and Beta Testing on physical hardware before distribution. [4]

## Security and license

This tool is intended for trusted LANs such as exhibitions and internal playtests. Do not expose the local bridge server directly to the public internet, and never bundle API keys, tokens, or private keys inside `.ehpk` packages. [3] The project is available under the [MIT License](LICENSE).

## References

[1] [Even Hub SDK — Glasses UI and package requirements](https://www.npmjs.com/package/@evenrealities/even_hub_sdk)

[2] [Even Hub SDK README — runtime requirements for 0.0.13](https://www.npmjs.com/package/@evenrealities/even_hub_sdk)

[3] [Even Hub documentation — networking, CORS, and Local Testing](https://hub.evenrealities.com/docs)

[4] [Even Hub Simulator — automation and testing](https://www.npmjs.com/package/@evenrealities/evenhub-simulator)
