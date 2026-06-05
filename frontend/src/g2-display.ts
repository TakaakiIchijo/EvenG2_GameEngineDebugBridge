/**
 * g2-display.ts
 * Even G2 スマートグラスへのログ表示ロジック。
 *
 * SDK 0.0.10 対応:
 *   - onLaunchSource()       : 起動元（appMenu / glassesMenu）をコンソールに記録
 *   - DeviceConnectType      : connectionFailed を含む詳細な接続状態を判定
 *   - ShutDownContaniner     : 型安全なシャットダウン呼び出し
 *   - EvenHubErrorCodeName   : createStartUpPageContainer の失敗理由を詳細ログに記録
 *
 * ページライフサイクルの原則:
 *   - 未初期化時: createStartUpPageContainer を使用
 *   - 初期化済み: rebuildPageContainer を使用
 * この使い分けを initialized フラグで管理する。
 */

import {
  waitForEvenAppBridge,
  EvenAppBridge,
  CreateStartUpPageContainer,
  RebuildPageContainer,
  TextContainerProperty,
  StartUpPageCreateResult,
  OsEventTypeList,
  DeviceConnectType,
  ShutDownContaniner,
  EvenHubErrorCodeName,
  type LaunchSource,
} from '@evenrealities/even_hub_sdk'

// ---------------------------------------------------------------------------
// 定数
// ---------------------------------------------------------------------------
const G2_WIDTH = 576
const G2_HEIGHT = 288
const CONTAINER_ID = 1
const CONTAINER_NAME = 'debug-log'
const MAX_DISPLAY_CHARS = 900  // BLE 900バイト制限に対応した安全な上限

// ---------------------------------------------------------------------------
// 状態
// ---------------------------------------------------------------------------
interface G2State {
  initialized: boolean
  bridge: EvenAppBridge | null
  onStatusChange: ((connected: boolean, detail?: string) => void) | null
  launchSource: LaunchSource | null
}

const state: G2State = {
  initialized: false,
  bridge: null,
  onStatusChange: null,
  launchSource: null,
}

// ---------------------------------------------------------------------------
// 公開 API
// ---------------------------------------------------------------------------

/**
 * Even G2 ブリッジを初期化する。
 * Even Hub アプリ（または Simulator）が WebView を注入するまで待機する。
 *
 * @param onStatusChange 接続状態変化時のコールバック。detail に詳細メッセージを渡す。
 */
export async function initG2(
  onStatusChange: (connected: boolean, detail?: string) => void,
): Promise<void> {
  state.onStatusChange = onStatusChange
  try {
    const bridge = await waitForEvenAppBridge()
    state.bridge = bridge

    // ---- SDK 0.0.10: 起動元の記録 ----------------------------------------
    bridge.onLaunchSource((source: LaunchSource) => {
      state.launchSource = source
      console.log(`[G2] 起動元: ${source}`)
    })

    // ---- SDK 0.0.10: 詳細な接続状態の監視 -----------------------------------
    bridge.onDeviceStatusChanged((status) => {
      switch (status.connectType) {
        case DeviceConnectType.Connected:
          onStatusChange(true, 'G2 に接続しました')
          break
        case DeviceConnectType.Connecting:
          onStatusChange(false, 'G2 に接続中...')
          break
        case DeviceConnectType.ConnectionFailed:
          // SDK 0.0.10 で追加された connectionFailed を明示的に処理
          onStatusChange(false, 'G2 への接続に失敗しました')
          console.warn('[G2] 接続失敗 (connectionFailed)')
          break
        case DeviceConnectType.Disconnected:
          onStatusChange(false, 'G2 との接続が切断されました')
          state.initialized = false  // 切断時は初期化状態をリセット
          break
        default:
          break
      }
    })

    // ---- ダブルクリックでアプリを終了 ----------------------------------------
    bridge.onEvenHubEvent((event) => {
      if (event.sysEvent?.eventType === OsEventTypeList.DOUBLE_CLICK_EVENT) {
        // SDK 0.0.10: ShutDownContaniner 型を使った型安全な呼び出し
        const shutDown = new ShutDownContaniner({ exitMode: 0 })
        bridge.shutDownPageContainer(shutDown.exitMode)
      }
    })

    onStatusChange(true, 'G2 ブリッジに接続しました')
  } catch (e) {
    console.error('[G2] ブリッジの初期化に失敗しました:', e)
    onStatusChange(false, 'G2 ブリッジの初期化に失敗しました（Simulator または Even Hub アプリで開いてください）')
  }
}

/**
 * ログメッセージを Even G2 に表示する。
 * 文字数が上限を超える場合は末尾を切り捨て、省略記号を付与する。
 */
export async function displayLogOnG2(
  level: string,
  message: string,
  timestamp: string,
): Promise<void> {
  const { bridge } = state
  if (!bridge) return

  // 表示テキストを組み立てる
  const levelLabel = formatLevel(level)
  const header = `${levelLabel} ${timestamp}\n`
  const body = message
  let content = header + body

  // BLE 900バイト制限: 文字数制限を超える場合は切り詰める
  if (content.length > MAX_DISPLAY_CHARS) {
    content = content.slice(0, MAX_DISPLAY_CHARS - 3) + '...'
  }

  const textProp = new TextContainerProperty({
    xPosition: 0,
    yPosition: 0,
    width: G2_WIDTH,
    height: G2_HEIGHT,
    borderWidth: 0,
    borderColor: 5,
    paddingLength: 6,
    containerID: CONTAINER_ID,
    containerName: CONTAINER_NAME,
    content,
    isEventCapture: 1,
  })

  await renderPage(bridge, textProp)
}

// ---------------------------------------------------------------------------
// 内部関数
// ---------------------------------------------------------------------------

/**
 * ページを描画する。
 * initialized フラグに応じて create / rebuild を使い分ける。
 */
async function renderPage(bridge: EvenAppBridge, textProp: TextContainerProperty): Promise<void> {
  if (!state.initialized) {
    const page = new CreateStartUpPageContainer({
      containerTotalNum: 1,
      textObject: [textProp],
    })
    const result = await bridge.createStartUpPageContainer(page)

    // SDK 0.0.10: EvenHubErrorCodeName を使った詳細なエラーログ
    if (result === StartUpPageCreateResult.success) {
      state.initialized = true
    } else if (result === StartUpPageCreateResult.oversize) {
      console.warn(
        `[G2] createStartUpPageContainer 失敗: ${EvenHubErrorCodeName.APP_REQUEST_CREATE_OVERSIZE_RESPONSE_CONTAINER}`,
      )
    } else if (result === StartUpPageCreateResult.outOfMemory) {
      console.warn(
        `[G2] createStartUpPageContainer 失敗: ${EvenHubErrorCodeName.APP_REQUEST_CREATE_OUTOFMEMORY_CONTAINER}`,
      )
    } else if (result === StartUpPageCreateResult.invalid) {
      console.warn(
        `[G2] createStartUpPageContainer 失敗: ${EvenHubErrorCodeName.APP_REQUEST_CREATE_INVAILD_CONTAINER}`,
      )
    }

    // ナレッジ: rebuildPageContainer の戻り値が false でもレイアウトが適用される場合があるため、
    // initialized が true でなくても次回以降は rebuild を試みる。
    // ただし、oversize / outOfMemory の場合は initialized をリセットしない（再試行しない）。
  } else {
    const page = new RebuildPageContainer({
      containerTotalNum: 1,
      textObject: [textProp],
    })
    const rebuildResult = await bridge.rebuildPageContainer(page)

    // SDK 0.0.10: rebuild 失敗時のエラーログ
    if (!rebuildResult) {
      console.warn(
        `[G2] rebuildPageContainer 失敗: ${EvenHubErrorCodeName.APP_REQUEST_REBUILD_PAGE_FAILD}`,
      )
      // 失敗時は次回 create から再試行する
      state.initialized = false
    }
  }
}

/**
 * ログレベルを G2 表示用のラベルに変換する。
 */
function formatLevel(level: string): string {
  switch (level.toLowerCase()) {
    case 'error':
    case 'exception':
      return '[ERR]'
    case 'warning':
    case 'warn':
      return '[WRN]'
    default:
      return '[LOG]'
  }
}
