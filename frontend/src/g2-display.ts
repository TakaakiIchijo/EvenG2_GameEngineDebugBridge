/**
 * g2-display.ts
 * Even G2 スマートグラスへのログ表示ロジック。
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
} from '@evenrealities/even_hub_sdk'

// ---------------------------------------------------------------------------
// 定数
// ---------------------------------------------------------------------------
const G2_WIDTH = 576
const G2_HEIGHT = 288
const CONTAINER_ID = 1
const CONTAINER_NAME = 'debug-log'
const MAX_DISPLAY_CHARS = 900  // rebuildPageContainer の上限 1000 に余裕を持たせる

// ---------------------------------------------------------------------------
// 状態
// ---------------------------------------------------------------------------
interface G2State {
  initialized: boolean
  bridge: EvenAppBridge | null
  onStatusChange: ((connected: boolean) => void) | null
}

const state: G2State = {
  initialized: false,
  bridge: null,
  onStatusChange: null,
}

// ---------------------------------------------------------------------------
// 公開 API
// ---------------------------------------------------------------------------

/**
 * Even G2 ブリッジを初期化する。
 * Even Hub アプリ（または Simulator）が WebView を注入するまで待機する。
 */
export async function initG2(onStatusChange: (connected: boolean) => void): Promise<void> {
  state.onStatusChange = onStatusChange
  try {
    const bridge = await waitForEvenAppBridge()
    state.bridge = bridge
    onStatusChange(true)

    // ダブルクリックでアプリを終了できるようにする
    bridge.onEvenHubEvent((event) => {
      if (event.sysEvent?.eventType === OsEventTypeList.DOUBLE_CLICK_EVENT) {
        bridge.shutDownPageContainer(0)
      }
    })
  } catch (e) {
    console.error('G2 ブリッジの初期化に失敗しました:', e)
    onStatusChange(false)
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

  // 文字数制限を超える場合は切り詰める
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
    borderRdaius: 4, // SDK の typo のためそのまま使う
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
    if (result === StartUpPageCreateResult.success) {
      state.initialized = true
    }
    // rebuildPageContainer の戻り値が false でもレイアウトが適用される場合があるため、
    // アイコン送信はスキップしない（ナレッジ参照）
  } else {
    const page = new RebuildPageContainer({
      containerTotalNum: 1,
      textObject: [textProp],
    })
    await bridge.rebuildPageContainer(page)
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
