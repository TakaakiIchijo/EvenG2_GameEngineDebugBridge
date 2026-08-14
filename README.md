# EvenG2 Game Engine Debug Bridge

> **言語:** [日本語](#日本語) / [English](#english)

<a id="日本語"></a>

## 概要

**EvenG2 Game Engine Debug Bridge** は、ゲームプレイ中に開発者だけが確認したいログをEven G2スマートグラスへ送る、ローカルネットワーク向けのデバッグ支援ツールです。Unity EditorプラグインとGodot 4サンプルは、`[Even]`タグを含むログだけを送信します。PythonブリッジサーバーとEven Hub Webアプリはゲームエンジン固有の情報を持たないため、同じ通信プロトコルを実装すればUnreal Engineなどのクライアントも接続できます。

フロントエンドはEven Hub SDK **0.0.13**、Even Hub Simulator **0.8.0**、Even Hub CLI **0.1.13**を基準にしています。SDK 0.0.13を使う配布パッケージでは、Even Realities App **2.2.6以降**とNode.js **20以降または22以降**が必要です。[1]

## 構成

| コンポーネント | ディレクトリ | 役割 |
| :--- | :--- | :--- |
| ローカルブリッジサーバー | `server/` | WebSocketでエンジン側ログを受信し、Webアプリへ配信します。ビルド済みWebアプリもHTTP配信します。 |
| Even Hub Webアプリ | `frontend/` | Even App WebView上でログを受信し、G2のテキストコンテナに表示します。 |
| Unity Editorプラグイン | `unity-plugin/EvenG2DebugBridge/` | Unity Editorログを監視し、送信対象を`[Even]`タグに限定します。 |
| Godot 4サンプル | `godot-sample/` | Godotの`WebSocketPeer`から`[Even]`タグ付きLog、Warning、Errorを送信する最小プロジェクトです。 |
| Godotダンジョンゲーム | `godot-dungeon/` | ランダムグリッド迷路、銃撃戦、10種類の敵、探索ミニマップを含む3D探索ゲームです。 |
| モックエンジン | `server/mock_engine.py` | UnityやGodotを起動せず、バックエンドとWebアプリの統合テストを実行します。 |

## 主な仕様

| 項目 | 実装内容 |
| :--- | :--- |
| 送信対象 | Unityの`Log`、`Warning`、`Error`、`Exception`のうち、本文に`[Even]`を含むものだけを送信します。 |
| Unity側の送信制御 | `Application.logMessageReceivedThreaded`では最新ログをバッファするだけにし、メインスレッドから**250ms間隔**で送信します。過剰なログは最新1件へ集約し、Unity Consoleに一度だけ警告します。 |
| Godot側の送信制御 | `WebSocketPeer.poll()`を毎フレーム実行し、サーバーとのハンドシェイク完了後にテキストWebSocketフレームで送信します。サンプルは250ms間隔で最新ログを送るクライアントを含みます。[5] |
| Webアプリ側の表示制御 | Unity以外のクライアントも考慮し、Webアプリ側でも最新ログを保持して最大**毎秒4回**に更新を制限します。 |
| G2データ量 | UTF-8で最大**880バイト**に切り詰めます。日本語を含む表示データを保守的に900バイト未満へ収めるためです。実機での最終確認は必須です。 |
| SDKページ操作 | 初回はコンテンツ種別に応じて`createStartUpPageContainer()`を使います。ログは`textContainerUpgrade()`、ダンジョンのミニマップは`updateImageRawData()`で更新します。 |
| ミニマップ転送 | Godotは壁・探索済みセル・プレイヤー・ゴールを構造化JSONで送ります。Webアプリが104×104のグレースケールPNGへ変換し、画像コンテナ1個と状態テキスト1個へ直列送信します。 |
| ミニマップ更新制御 | 新規セル到達・回転・再生成・戦闘後だけ状態を更新します。GodotクライアントとWebアプリの双方で250ms間隔に集約します。 |
| 終了操作 | G2のダブルクリックで終了ダイアログを要求し、イベント購読とタイマーを解放します。 |
| パッケージ化 | `app.manifest.template.json`から接続先LANオリジンを含む`app.json`を生成し、`.ehpk`へパッケージ化します。SDK 0.0.13のマニフェスト要件に従います。[1] |

ログページはテキストコンテナを1個だけ使用します。ダンジョンのミニマップページは画像コンテナ1個とイベント捕捉用テキストコンテナ1個を使用し、両コンテナに一意の`zOrderIndex`を指定します。これはSDKのページコンテナ制約に沿うためです。[1]

## 動作要件

| 項目 | 要件 |
| :--- | :--- |
| Python | Python 3.9以降。`websockets` 16系を使用します。 |
| Node.js | `^20.0.0` または `>=22.0.0`。[2] |
| Unity | Unity 2021.3 LTS以降。 |
| Godot | Godot Engine 4.7.1で検証済み。Godot 4系の`WebSocketPeer`を使用します。[5] |
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

### 6. Godot 4サンプルの実行

Godot 4.7.1の標準Linux版で、実際のブリッジ接続・ログ送信を検証しています。Godotの公式配布は自己完結型のため、展開後に実行できます。[6]

```bash
# Godotエディタから godot-sample/project.godot をImportして実行するか、
# Linuxでは次のようにヘッドレスで実行します。
godot --headless --path godot-sample -- --bridge-url=ws://127.0.0.1:8766
```

起動後、サンプルは`[Even]`タグ付きのLog、Warning、Error、Logを4件送信します。画面上の **Send next [Even] sample log** ボタンでは追加のサンプルログを送信できます。ヘッドレスの回帰確認には、ローカルブリッジを起動した状態で以下を実行します。

```bash
godot --headless --path godot-sample \
  --script res://tests/bridge_smoke_test.gd -- \
  --bridge-url=ws://127.0.0.1:8766
```

### 7. Godot Grid Dungeon Explorerの実行

`godot-dungeon/`は、13×13の完全迷路をシードから生成する一人称3D探索ゲームです。プレイヤーは銃を使い、移動・攻撃方法の異なる雑魚7種、中ボス2種、出口を守るボス1種と対戦します。敵は開始地点から距離を取って出現し、出口へ到達するにはボスを撃破する必要があります。

画面は暗い炭色と砂岩色を基調とし、暖色の方向光、320×180相当のnearest補間、控えめな色数削減・ディザ・走査線で低解像度の質感を付与します。HUDは別レイヤーに配置するため、この画面処理で文字の可読性を損ないません。戦闘時は画面をわずかに脱彩します。

ダンジョンには、弾薬箱、医療アンプル、鍵の欠片、データカセット、電力セル、祭壇コアの6種類の低ポリゴンアイテムが出現します。各アイテムは背景から区別できる色と形状を持ち、回収時に弾薬・HP・進行情報などを更新します。

```bash
# ローカルブリッジを起動済みにしてから、Godotエディタで
# godot-dungeon/project.godot をImportしてMain.tscnを実行します。
# コマンド実行例:
godot --path godot-dungeon -- --bridge-url=ws://127.0.0.1:8766
```

| 操作 | 内容 |
| :--- | :--- |
| `W` / `S`、上下キー | 前進・後退（グリッド単位） |
| `A` / `D`、左右キー | 90度回転 |
| `Space` | 銃を発射します。射線上で最初に当たった敵へダメージを与えます。 |
| `F` | リロードします。 |
| `R` | 新しいシードのダンジョンを生成します。 |

ミニマップは壁、未探索セル、探索済みセル、ゴール、プレイヤー位置を表示します。Godotの初期化、迷路の連結性、ゴール到達性、敵10種の編成、戦闘HUD、ターン、移動は次のヘッドレステストで確認できます。

```bash
godot --headless --path godot-dungeon --script res://tests/dungeon_generation_test.gd
godot --headless --path godot-dungeon --script res://tests/enemy_encounter_test.gd
godot --headless --path godot-dungeon --script res://tests/gameplay_flow_test.gd
godot --headless --path godot-dungeon --script res://tests/item_pickup_test.gd
```

Simulatorでは、GodotからのミニマップJSON受信、画像更新APIの`success`、状態テキスト更新APIの成功を確認しました。SimulatorのG2スクリーンショットには画像コンテナが描画されない挙動があったため、グラス上でのミニマップの最終的な可視性と連続画像更新は、実機でLocal Testingを行って確認してください。[4]

### 8. 実機のLocal Testing

実機確認では、PCのLAN IPアドレスを指定したURLをQR化します。例えばローカルサーバーが`192.168.1.20`の場合は次の通りです。

```bash
evenhub qr --url "http://192.168.1.20:8765"
```

開発PCとスマートフォンを同一LANへ接続してください。パッケージ化して配布する場合は、次節のマニフェスト生成で接続先オリジンを`network.whitelist`に含める必要があります。`whitelist`とサーバー側CORSは別の制約です。[3]

### 9. Even Hubパッケージの生成

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

このリポジトリではSimulator v0.8.0、モックエンジン、Pythonサーバーを用いて、通常ログ、高頻度20件、長文、ダブルクリック終了を検証しています。加えてGodot Engine 4.7.1の実行プロセスから4件の`[Even]`ログを送信し、サーバー受信、WebView表示、G2 RGBAキャプチャの非透明描画領域を確認しました。SimulatorはBLE帯域・実機フォント・端末固有の接続状態を再現しないため、最終的な表示量と接続安定性は実機のLocal Testing、Private Testing、Beta Testingで確認してください。[4]

## セキュリティと運用上の注意

このツールは展示会や社内テストなど、信頼できる同一LAN内での利用を想定しています。ローカルブリッジサーバーをインターネットへ直接公開しないでください。また、配布する`.ehpk`にはAPIキー、トークン、秘密鍵を含めないでください。[3] デバッグログにも個人情報、認証情報、未公開コンテンツを含めない運用が必要です。

## ライセンス

MIT Licenseです。詳細は[LICENSE](LICENSE)を参照してください。

## 参照資料

[1] [Even Hub SDK — Glasses UIとパッケージ要件](https://www.npmjs.com/package/@evenrealities/even_hub_sdk)

[2] [Even Hub SDK README — SDK 0.0.13の実行要件](https://www.npmjs.com/package/@evenrealities/even_hub_sdk)

[3] [Even Hub開発ガイド — ネットワーク権限、CORS、Local Testing](https://hub.evenrealities.com/docs)

[4] [Even Hub Simulator — 自動化と検証](https://www.npmjs.com/package/@evenrealities/evenhub-simulator)

[5] [Godot Engine 4.7 — WebSocketPeer](https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html)

[6] [Godot Engine 4.7.1 — Linux標準版ダウンロード](https://godotengine.org/download/linux/)

---

<a id="english"></a>

# EvenG2 Game Engine Debug Bridge — English

## Overview

**EvenG2 Game Engine Debug Bridge** is a local-network debugging tool that sends developer-only logs to Even G2 smart glasses during game playtests. The Unity Editor plugin and Godot 4 sample forward only messages that contain the `[Even]` tag. The Python bridge server and Even Hub web app are engine-agnostic, so clients such as Unreal Engine can use the same transport protocol.

The frontend targets **Even Hub SDK 0.0.13**, **Even Hub Simulator 0.8.0**, and **Even Hub CLI 0.1.13**. An SDK 0.0.13 package requires Even Realities App **2.2.6 or later** and Node.js **20 or later, or 22 or later**. [1]

## Components

| Component | Directory | Responsibility |
| :--- | :--- | :--- |
| Local bridge server | `server/` | Receives logs through WebSocket, broadcasts them to the web app, and serves the built frontend over HTTP. |
| Even Hub web app | `frontend/` | Receives bridge messages in the Even App WebView and writes them to the G2 text container. |
| Unity Editor plugin | `unity-plugin/EvenG2DebugBridge/` | Watches Unity Editor logs and filters messages by the `[Even]` tag. |
| Godot 4 sample | `godot-sample/` | Minimal project that sends `[Even]`-tagged Log, Warning, and Error entries with Godot `WebSocketPeer`. |
| Godot dungeon game | `godot-dungeon/` | 3D exploration game with a random grid maze, gun combat, ten enemy types, and an exploration minimap. |
| Mock engine | `server/mock_engine.py` | Runs server and web-app integration tests without launching Unity or Godot. |

## Core behavior

| Area | Behavior |
| :--- | :--- |
| Unity sending | The threaded Unity log callback only buffers the newest message. Serialization and sends run on the Editor main thread every **250ms**. Intermediate logs are coalesced and a single warning is printed to the Unity Console. |
| Godot sending | The client calls `WebSocketPeer.poll()` every frame, waits for the bridge handshake, and then sends text WebSocket frames. The sample client coalesces logs to a 250ms interval. [5] |
| Frontend rendering | The web app also coalesces incoming entries and limits G2 updates to **four per second**, protecting future Unreal or Godot clients that do not implement Unity-side throttling. |
| G2 payload | The display text is truncated by UTF-8 byte length to **880 bytes**, a conservative value below the practical 900-byte target for Japanese text. Validate the final limit on hardware. |
| SDK lifecycle | The first page is created for the first received content type. Logs use `textContainerUpgrade()`; dungeon minimaps use `updateImageRawData()`. |
| Minimap transport | Godot sends walls, explored cells, player state, and goal state as structured JSON. The web app converts it to a 104×104 greyscale PNG and serially updates one image container plus one status text container. |
| Minimap pacing | State changes are emitted only after a move, turn, regeneration, or combat action. Both the Godot client and web app coalesce updates to a 250ms interval. |
| Exit | A G2 double click requests the system close dialog and releases event subscriptions and timers. |
| Packaging | A per-LAN `app.json` is generated from `app.manifest.template.json`, then packaged as `.ehpk` with the SDK 0.0.13 manifest requirements. [1] |

## Requirements

| Item | Requirement |
| :--- | :--- |
| Python | Python 3.9+ with `websockets` 16.x. |
| Node.js | `^20.0.0` or `>=22.0.0`. [2] |
| Unity | Unity 2021.3 LTS or later. |
| Godot | Validated with Godot Engine 4.7.1 using the Godot 4 `WebSocketPeer` API. [5] |
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

### Run the Godot 4 sample

The sample has been exercised with the Godot Engine 4.7.1 standard Linux build. Godot's official Linux distribution is self-contained: extract it and run the binary. [6]

```bash
godot --headless --path godot-sample -- --bridge-url=ws://127.0.0.1:8766
```

At startup, the sample sends four `[Even]`-tagged Log, Warning, Error, and Log entries. The **Send next [Even] sample log** button sends an additional entry. Run the repeatable headless smoke test against a running local bridge as follows:

```bash
godot --headless --path godot-sample \
  --script res://tests/bridge_smoke_test.gd -- \
  --bridge-url=ws://127.0.0.1:8766
```

### Run the Godot Grid Dungeon Explorer

`godot-dungeon/` is a first-person 3D exploration game that generates a seeded 13×13 perfect maze. The player uses a gun against seven minion types, two midbosses, and one boss guarding the exit. Enemies spawn away from the start position; the exit remains blocked until the boss is defeated.

The visual direction uses charcoal and sandstone as its base, warm directional lighting, nearest-neighbour sampling at an effective 320×180 resolution, plus restrained colour quantisation, dithering, and scanlines. HUD elements render on a separate layer so this treatment does not reduce text readability. Combat briefly desaturates the scene.

Six low-poly pickup types appear in the dungeon: ammo box, medical ampoule, key fragment, data cassette, power cell, and altar core. Each uses a distinct silhouette and accent colour, and its pickup updates ammunition, health, or progression information.

```bash
# Start the local bridge first, then import godot-dungeon/project.godot in Godot.
# Command-line example:
godot --path godot-dungeon -- --bridge-url=ws://127.0.0.1:8766
```

| Control | Action |
| :--- | :--- |
| `W` / `S`, Up / Down | Move forward or backward by one grid cell. |
| `A` / `D`, Left / Right | Turn 90 degrees. |
| `Space` | Fire the gun; the first enemy on the line of fire receives damage. |
| `F` | Reload. |
| `R` | Generate a dungeon with a new seed. |

The minimap includes walls, unexplored cells, explored cells, the goal, and the player position. Run these repeatable headless tests to verify scene initialization, maze connectivity and reachability, the ten-enemy roster, combat HUD setup, turning, and movement.

```bash
godot --headless --path godot-dungeon --script res://tests/dungeon_generation_test.gd
godot --headless --path godot-dungeon --script res://tests/enemy_encounter_test.gd
godot --headless --path godot-dungeon --script res://tests/gameplay_flow_test.gd
godot --headless --path godot-dungeon --script res://tests/item_pickup_test.gd
```

Simulator validation confirmed receipt of the Godot minimap JSON plus successful image-update and status-text-update API responses. Its G2 screenshot did not visibly render the image container, so final minimap visibility and continuous image updates must be confirmed in Local Testing on physical glasses. [4]

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

Simulator testing in this repository covers sequential logs, 20 high-frequency entries, long UTF-8 messages, and double-click shutdown. A real Godot Engine 4.7.1 process also sent a dungeon minimap state to the local bridge; the WebView receipt plus successful image and status-text API responses were confirmed. Simulator does not model BLE bandwidth, device fonts, native image transfer, or native connection behavior. Use Local, Private, and Beta Testing on physical hardware before distribution. [4]

## Security and license

This tool is intended for trusted LANs such as exhibitions and internal playtests. Do not expose the local bridge server directly to the public internet, and never bundle API keys, tokens, or private keys inside `.ehpk` packages. [3] The project is available under the [MIT License](LICENSE).

## References

[1] [Even Hub SDK — Glasses UI and package requirements](https://www.npmjs.com/package/@evenrealities/even_hub_sdk)

[2] [Even Hub SDK README — runtime requirements for 0.0.13](https://www.npmjs.com/package/@evenrealities/even_hub_sdk)

[3] [Even Hub documentation — networking, CORS, and Local Testing](https://hub.evenrealities.com/docs)

[4] [Even Hub Simulator — automation and testing](https://www.npmjs.com/package/@evenrealities/evenhub-simulator)

[5] [Godot Engine 4.7 — WebSocketPeer](https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html)

[6] [Godot Engine 4.7.1 — standard Linux download](https://godotengine.org/download/linux/)
