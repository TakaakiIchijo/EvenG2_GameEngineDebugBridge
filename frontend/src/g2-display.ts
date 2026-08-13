import {
  CreateStartUpPageContainer,
  DeviceConnectType,
  EvenAppBridge,
  OsEventTypeList,
  StartUpPageCreateResult,
  TextContainerProperty,
  TextContainerUpgrade,
  waitForEvenAppBridge,
  type LaunchSource,
} from '@evenrealities/even_hub_sdk'

const DISPLAY_WIDTH = 576
const DISPLAY_HEIGHT = 288
const LOG_CONTAINER_ID = 1
const LOG_CONTAINER_NAME = 'debug-log'
const MAX_G2_CONTENT_BYTES = 880
const DISPLAY_INTERVAL_MS = 250

export type G2ConnectionState = 'ready' | 'connecting' | 'connected' | 'disconnected' | 'failed'

type StatusListener = (state: G2ConnectionState, detail: string) => void

interface PendingLog {
  level: string
  message: string
  timestamp: string
}

interface G2State {
  bridge: EvenAppBridge | null
  pageCreated: boolean
  pendingLog: PendingLog | null
  renderTimer: number | null
  lastRenderAt: number
  statusListener: StatusListener | null
  unsubscribeLaunchSource: (() => void) | null
  unsubscribeDeviceStatus: (() => void) | null
  unsubscribeHubEvents: (() => void) | null
}

const state: G2State = {
  bridge: null,
  pageCreated: false,
  pendingLog: null,
  renderTimer: null,
  lastRenderAt: 0,
  statusListener: null,
  unsubscribeLaunchSource: null,
  unsubscribeDeviceStatus: null,
  unsubscribeHubEvents: null,
}

/** Even App WebViewブリッジを初期化し、G2の接続状態を監視する。 */
export async function initG2(onStatusChange: StatusListener): Promise<void> {
  disposeG2()
  state.statusListener = onStatusChange
  notifyStatus('connecting', 'Even App ブリッジに接続中...')

  try {
    const bridge = await waitForEvenAppBridge()
    state.bridge = bridge

    // 起動元イベントはロード後に1回だけ届くため、ブリッジ取得直後に購読する。
    state.unsubscribeLaunchSource = bridge.onLaunchSource((source: LaunchSource) => {
      console.info(`[G2] 起動元: ${source}`)
    })

    state.unsubscribeDeviceStatus = bridge.onDeviceStatusChanged((device) => {
      switch (device.connectType) {
        case DeviceConnectType.Connected:
          notifyStatus('connected', `G2 に接続しました${formatBattery(device.batteryLevel)}`)
          break
        case DeviceConnectType.Connecting:
          notifyStatus('connecting', 'G2 に接続中...')
          break
        case DeviceConnectType.ConnectionFailed:
          state.pageCreated = false
          notifyStatus('failed', 'G2 への接続に失敗しました')
          break
        case DeviceConnectType.Disconnected:
          state.pageCreated = false
          notifyStatus('disconnected', 'G2 との接続が切断されました')
          break
        default:
          break
      }
    })

    state.unsubscribeHubEvents = bridge.onEvenHubEvent((event) => {
      const sysType = eventTypeOf(event.sysEvent)
      const textType = eventTypeOf(event.textEvent)

      if (
        sysType === OsEventTypeList.DOUBLE_CLICK_EVENT ||
        textType === OsEventTypeList.DOUBLE_CLICK_EVENT
      ) {
        void closePage(bridge)
        return
      }

      if (
        sysType === OsEventTypeList.SYSTEM_EXIT_EVENT ||
        sysType === OsEventTypeList.ABNORMAL_EXIT_EVENT
      ) {
        state.pageCreated = false
      }
    })

    notifyStatus('ready', 'Even App ブリッジの準備ができました')
    await ensurePage(bridge, 'ログ待機中...')
  } catch (error) {
    console.error('[G2] ブリッジの初期化に失敗しました', error)
    notifyStatus('failed', 'Even App または Simulator 上で開いてください')
  }
}

/**
 * 最新ログを表示待ちキューへ登録する。
 * 高頻度入力では中間ログを破棄し、最大4回/秒で最新ログだけをグラスへ送る。
 */
export function queueLogForG2(level: string, message: string, timestamp: string): void {
  state.pendingLog = { level, message, timestamp }
  schedulePendingRender()
}

/** WebView離脱時のイベント購読とタイマーを解放する。 */
export function disposeG2(): void {
  if (state.renderTimer !== null) {
    window.clearTimeout(state.renderTimer)
  }

  state.renderTimer = null
  state.pendingLog = null
  state.pageCreated = false
  state.unsubscribeLaunchSource?.()
  state.unsubscribeDeviceStatus?.()
  state.unsubscribeHubEvents?.()
  state.unsubscribeLaunchSource = null
  state.unsubscribeDeviceStatus = null
  state.unsubscribeHubEvents = null
  state.bridge = null
}

function schedulePendingRender(): void {
  if (state.renderTimer !== null) {
    return
  }

  const delay = Math.max(0, DISPLAY_INTERVAL_MS - (Date.now() - state.lastRenderAt))
  state.renderTimer = window.setTimeout(() => {
    state.renderTimer = null
    void flushPendingLog()
  }, delay)
}

async function flushPendingLog(): Promise<void> {
  const pending = state.pendingLog
  state.pendingLog = null

  if (!pending || !state.bridge) {
    return
  }

  const content = fitUtf8(`${formatLevel(pending.level)} ${pending.timestamp}\n${pending.message}`, MAX_G2_CONTENT_BYTES)

  try {
    const pageReady = await ensurePage(state.bridge, content)
    if (pageReady) {
      const updated = await state.bridge.textContainerUpgrade(
        new TextContainerUpgrade({
          containerID: LOG_CONTAINER_ID,
          containerName: LOG_CONTAINER_NAME,
          content,
        }),
      )

      if (!updated) {
        console.warn('[G2] テキスト更新に失敗しました。次回はページを再作成します。')
        state.pageCreated = false
      }
    }
  } catch (error) {
    console.error('[G2] ログ表示に失敗しました', error)
    state.pageCreated = false
  } finally {
    state.lastRenderAt = Date.now()
    if (state.pendingLog) {
      schedulePendingRender()
    }
  }
}

async function ensurePage(bridge: EvenAppBridge, initialContent: string): Promise<boolean> {
  if (state.pageCreated) {
    return true
  }

  const textContainer = new TextContainerProperty({
    xPosition: 0,
    yPosition: 0,
    width: DISPLAY_WIDTH,
    height: DISPLAY_HEIGHT,
    borderWidth: 0,
    borderColor: 5,
    paddingLength: 6,
    containerID: LOG_CONTAINER_ID,
    containerName: LOG_CONTAINER_NAME,
    content: fitUtf8(initialContent, MAX_G2_CONTENT_BYTES),
    isEventCapture: 1,
  })

  const result = await bridge.createStartUpPageContainer(
    new CreateStartUpPageContainer({
      containerTotalNum: 1,
      textObject: [textContainer],
    }),
  )

  if (result !== StartUpPageCreateResult.success) {
    console.warn('[G2] 初期ページの作成に失敗しました', result)
    state.pageCreated = false
    return false
  }

  state.pageCreated = true
  return true
}

async function closePage(bridge: EvenAppBridge): Promise<void> {
  try {
    await bridge.shutDownPageContainer(1)
  } finally {
    state.pageCreated = false
    disposeG2()
  }
}

function eventTypeOf(envelope?: { eventType?: OsEventTypeList }): OsEventTypeList | null {
  if (!envelope) {
    return null
  }
  // CLICK_EVENTは0であり、SDKのイベントエンベロープでは省略される場合がある。
  return envelope.eventType ?? OsEventTypeList.CLICK_EVENT
}

function notifyStatus(connectionState: G2ConnectionState, detail: string): void {
  state.statusListener?.(connectionState, detail)
}

function formatBattery(level: number | undefined): string {
  return typeof level === 'number' ? `（バッテリー ${level}%）` : ''
}

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

/** UTF-8のバイト数で末尾を省略する。日本語を含むログでも上限を超えない。 */
function fitUtf8(value: string, maxBytes: number): string {
  const encoder = new TextEncoder()
  if (encoder.encode(value).byteLength <= maxBytes) {
    return value
  }

  const suffix = '…'
  let end = value.length
  while (end > 0 && encoder.encode(`${value.slice(0, end)}${suffix}`).byteLength > maxBytes) {
    end -= 1
  }

  return `${value.slice(0, end)}${suffix}`
}
