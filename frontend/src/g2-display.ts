import {
  CreateStartUpPageContainer,
  DeviceConnectType,
  EvenAppBridge,
  ImageContainerProperty,
  ImageRawDataUpdate,
  ImageRawDataUpdateResult,
  OsEventTypeList,
  RebuildPageContainer,
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
const MAP_IMAGE_ID = 11
const MAP_IMAGE_NAME = 'dungeon-minimap'
const MAP_STATUS_ID = 12
const MAP_STATUS_NAME = 'dungeon-status'
const MAP_IMAGE_SIZE = 104
const MAX_G2_CONTENT_BYTES = 880
const DISPLAY_INTERVAL_MS = 250

export type G2ConnectionState = 'ready' | 'connecting' | 'connected' | 'disconnected' | 'failed'

export interface MinimapState {
  type: 'minimap'
  width: number
  height: number
  walls: string
  explored: string
  player: { x: number; y: number; facing: number }
  goal: { x: number; y: number }
  revision: number
  state: string
}

type StatusListener = (state: G2ConnectionState, detail: string) => void
type PageMode = 'log' | 'minimap'

interface PendingLog {
  level: string
  message: string
  timestamp: string
}

interface G2State {
  bridge: EvenAppBridge | null
  pageCreated: boolean
  pageMode: PageMode
  pendingLog: PendingLog | null
  pendingMinimap: MinimapState | null
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
  pageMode: 'log',
  pendingLog: null,
  pendingMinimap: null,
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
      if (sysType === OsEventTypeList.DOUBLE_CLICK_EVENT || textType === OsEventTypeList.DOUBLE_CLICK_EVENT) {
        void closePage(bridge)
        return
      }
      if (sysType === OsEventTypeList.SYSTEM_EXIT_EVENT || sysType === OsEventTypeList.ABNORMAL_EXIT_EVENT) {
        state.pageCreated = false
      }
    })

    // 初回レイアウトは最初に届くコンテンツ種別で決める。
    // ミニマップを先に受信した場合は、ログページを経由せず画像ページを起動ページとして作成する。
    notifyStatus('ready', 'Even App ブリッジの準備ができました')
  } catch (error) {
    console.error('[G2] ブリッジの初期化に失敗しました', error)
    notifyStatus('failed', 'Even App または Simulator 上で開いてください')
  }
}

/** 通常ログを表示待ちキューへ登録する。ミニマップ画面中はマップを優先する。 */
export function queueLogForG2(level: string, message: string, timestamp: string): void {
  state.pendingLog = { level, message, timestamp }
  schedulePendingRender()
}

/** 最新ミニマップを表示待ちキューへ登録する。中間状態は常に最新値へ集約する。 */
export function queueMinimapForG2(minimap: MinimapState): void {
  if (!isValidMinimap(minimap)) {
    console.warn('[G2] 不正なミニマップを無視しました', minimap)
    return
  }
  state.pendingMinimap = minimap
  schedulePendingRender()
}

/** WebView離脱時のイベント購読とタイマーを解放する。 */
export function disposeG2(): void {
  if (state.renderTimer !== null) window.clearTimeout(state.renderTimer)
  state.renderTimer = null
  state.pendingLog = null
  state.pendingMinimap = null
  state.pageCreated = false
  state.pageMode = 'log'
  state.unsubscribeLaunchSource?.()
  state.unsubscribeDeviceStatus?.()
  state.unsubscribeHubEvents?.()
  state.unsubscribeLaunchSource = null
  state.unsubscribeDeviceStatus = null
  state.unsubscribeHubEvents = null
  state.bridge = null
}

function schedulePendingRender(): void {
  if (state.renderTimer !== null) return
  const delay = Math.max(0, DISPLAY_INTERVAL_MS - (Date.now() - state.lastRenderAt))
  state.renderTimer = window.setTimeout(() => {
    state.renderTimer = null
    void flushPendingRender()
  }, delay)
}

async function flushPendingRender(): Promise<void> {
  if (state.pendingMinimap) {
    const minimap = state.pendingMinimap
    state.pendingMinimap = null
    await renderMinimap(minimap)
  } else if (state.pendingLog && state.pageMode !== 'minimap') {
    const log = state.pendingLog
    state.pendingLog = null
    await renderLog(log)
  }

  state.lastRenderAt = Date.now()
  if (state.pendingMinimap || (state.pendingLog && state.pageMode !== 'minimap')) schedulePendingRender()
}

async function renderLog(pending: PendingLog): Promise<void> {
  if (!state.bridge) return
  const content = fitUtf8(`${formatLevel(pending.level)} ${pending.timestamp}\n${pending.message}`, MAX_G2_CONTENT_BYTES)
  try {
    if (await ensureLogPage(state.bridge, content)) {
      const updated = await state.bridge.textContainerUpgrade(new TextContainerUpgrade({
        containerID: LOG_CONTAINER_ID,
        containerName: LOG_CONTAINER_NAME,
        content,
      }))
      if (!updated) state.pageCreated = false
    }
  } catch (error) {
    console.error('[G2] ログ表示に失敗しました', error)
    state.pageCreated = false
  }
}

async function renderMinimap(minimap: MinimapState): Promise<void> {
  if (!state.bridge) return
  try {
    const mapReady = await ensureMinimapPage(state.bridge, mapStatusText(minimap))
    if (!mapReady) return

    // SDK上ではrebuildPageContainerがfalseでも実機側にレイアウトが適用済みの場合がある。
    // そのため、ページ作成後は画像更新を必ず試行する。
    const imageResult = await state.bridge.updateImageRawData(new ImageRawDataUpdate({
      containerID: MAP_IMAGE_ID,
      containerName: MAP_IMAGE_NAME,
      imageData: Array.from(await encodeMinimapPng(minimap)),
    }))
    if (imageResult !== ImageRawDataUpdateResult.success) {
      console.warn('[G2] ミニマップ画像の更新に失敗しました', imageResult)
    } else {
      console.info('[G2] ミニマップ画像を更新しました', minimap.revision)
    }

    const textUpdated = await state.bridge.textContainerUpgrade(new TextContainerUpgrade({
      containerID: MAP_STATUS_ID,
      containerName: MAP_STATUS_NAME,
      content: mapStatusText(minimap),
    }))
    if (!textUpdated) console.warn('[G2] ミニマップ状態テキストの更新に失敗しました')
    else console.info('[G2] ミニマップ状態テキストを更新しました', minimap.revision)
  } catch (error) {
    console.error('[G2] ミニマップ表示に失敗しました', error)
    state.pageCreated = false
  }
}

async function ensureLogPage(bridge: EvenAppBridge, initialContent: string): Promise<boolean> {
  if (state.pageCreated && state.pageMode === 'log') return true
  if (state.pageCreated) return false

  const textContainer = new TextContainerProperty({
    xPosition: 0, yPosition: 0, width: DISPLAY_WIDTH, height: DISPLAY_HEIGHT,
    borderWidth: 0, borderColor: 5, paddingLength: 6,
    containerID: LOG_CONTAINER_ID, containerName: LOG_CONTAINER_NAME,
    content: fitUtf8(initialContent, MAX_G2_CONTENT_BYTES), isEventCapture: 1,
  })
  const result = await bridge.createStartUpPageContainer(new CreateStartUpPageContainer({
    containerTotalNum: 1,
    textObject: [textContainer],
  }))
  if (result !== StartUpPageCreateResult.success) {
    console.warn('[G2] ログ初期ページの作成に失敗しました', result)
    state.pageCreated = false
    return false
  }
  state.pageCreated = true
  state.pageMode = 'log'
  return true
}

async function ensureMinimapPage(bridge: EvenAppBridge, initialStatus: string): Promise<boolean> {
  if (state.pageCreated && state.pageMode === 'minimap') return true

  const imageContainer = new ImageContainerProperty({
    xPosition: 236, yPosition: 0, width: MAP_IMAGE_SIZE, height: MAP_IMAGE_SIZE,
    containerID: MAP_IMAGE_ID, containerName: MAP_IMAGE_NAME, zOrderIndex: 1,
  })
  const statusContainer = new TextContainerProperty({
    xPosition: 28, yPosition: 116, width: 520, height: 150,
    borderWidth: 0, borderColor: 5, paddingLength: 4,
    containerID: MAP_STATUS_ID, containerName: MAP_STATUS_NAME,
    content: fitUtf8(initialStatus, MAX_G2_CONTENT_BYTES), isEventCapture: 1, zOrderIndex: 2,
  })

  if (!state.pageCreated) {
    const result = await bridge.createStartUpPageContainer(new CreateStartUpPageContainer({
      containerTotalNum: 2,
      imageObject: [imageContainer],
      textObject: [statusContainer],
    }))
    if (result !== StartUpPageCreateResult.success) {
      console.warn('[G2] ミニマップ初期ページの作成に失敗しました', result)
      return false
    }
  } else {
    const rebuilt = await bridge.rebuildPageContainer(new RebuildPageContainer({
      containerTotalNum: 2,
      imageObject: [imageContainer],
      textObject: [statusContainer],
    }))
    if (!rebuilt) console.warn('[G2] ミニマップページ再構築がfalseを返しました。画像送信を継続します。')
  }

  state.pageCreated = true
  state.pageMode = 'minimap'
  return true
}

async function encodeMinimapPng(map: MinimapState): Promise<Uint8Array> {
  const grayscale = rasterizeMinimap(map)
  const canvas = document.createElement('canvas')
  canvas.width = MAP_IMAGE_SIZE
  canvas.height = MAP_IMAGE_SIZE
  const context = canvas.getContext('2d')
  if (!context) throw new Error('Canvas 2D context is unavailable')

  const pixels = context.createImageData(MAP_IMAGE_SIZE, MAP_IMAGE_SIZE)
  for (let index = 0; index < grayscale.length; index += 1) {
    const shade = grayscale[index] * 17
    const offset = index * 4
    pixels.data[offset] = shade
    pixels.data[offset + 1] = shade
    pixels.data[offset + 2] = shade
    pixels.data[offset + 3] = 255
  }
  context.putImageData(pixels, 0, 0)
  const blob = await new Promise<Blob>((resolve, reject) => {
    canvas.toBlob(result => result ? resolve(result) : reject(new Error('PNG encoding failed')), 'image/png')
  })
  return new Uint8Array(await blob.arrayBuffer())
}

function rasterizeMinimap(map: MinimapState): Uint8Array {
  const image = new Uint8Array(MAP_IMAGE_SIZE * MAP_IMAGE_SIZE)
  image.fill(1)
  const cellSize = Math.max(1, Math.floor(MAP_IMAGE_SIZE / Math.max(map.width, map.height)))
  const offsetX = Math.floor((MAP_IMAGE_SIZE - map.width * cellSize) / 2)
  const offsetY = Math.floor((MAP_IMAGE_SIZE - map.height * cellSize) / 2)

  for (let y = 0; y < map.height; y += 1) {
    for (let x = 0; x < map.width; x += 1) {
      const index = y * map.width + x
      const isWall = map.walls[index] === '1'
      const wasExplored = map.explored[index] === '1'
      let shade = isWall ? 0 : wasExplored ? 9 : 3
      if (x === map.goal.x && y === map.goal.y) shade = 12
      if (x === map.player.x && y === map.player.y) shade = 15
      fillCell(image, offsetX + x * cellSize, offsetY + y * cellSize, cellSize, shade)
    }
  }
  return image
}

function fillCell(image: Uint8Array, startX: number, startY: number, size: number, shade: number): void {
  for (let y = startY; y < startY + size && y < MAP_IMAGE_SIZE; y += 1) {
    for (let x = startX; x < startX + size && x < MAP_IMAGE_SIZE; x += 1) {
      if (x >= 0 && y >= 0) image[y * MAP_IMAGE_SIZE + x] = shade
    }
  }
}

function mapStatusText(map: MinimapState): string {
  const exploredCount = [...map.explored].filter(value => value === '1').length
  const heading = ['N', 'E', 'S', 'W'][map.player.facing] ?? '?'
  return fitUtf8(`DUNGEON MAP\nEXPLORED ${exploredCount}/${map.width * map.height}\nPOS ${map.player.x},${map.player.y}  DIR ${heading}\nSTATE ${map.state.toUpperCase()}`, MAX_G2_CONTENT_BYTES)
}

function isValidMinimap(map: MinimapState): boolean {
  const size = map.width * map.height
  return Number.isInteger(map.width) && Number.isInteger(map.height)
    && map.width >= 5 && map.height >= 5 && map.width <= 31 && map.height <= 31
    && map.walls.length === size && map.explored.length === size
    && /^[01]+$/.test(map.walls) && /^[01]+$/.test(map.explored)
    && Number.isInteger(map.player.x) && Number.isInteger(map.player.y)
    && Number.isInteger(map.goal.x) && Number.isInteger(map.goal.y)
    && map.player.x >= 0 && map.player.x < map.width && map.player.y >= 0 && map.player.y < map.height
    && map.goal.x >= 0 && map.goal.x < map.width && map.goal.y >= 0 && map.goal.y < map.height
    && Number.isInteger(map.player.facing) && map.player.facing >= 0 && map.player.facing <= 3
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
  if (!envelope) return null
  return envelope.eventType ?? OsEventTypeList.CLICK_EVENT
}

function notifyStatus(connectionState: G2ConnectionState, detail: string): void {
  state.statusListener?.(connectionState, detail)
}

function formatBattery(level: number | undefined): string {
  return typeof level === 'number' ? `（バッテリー ${level}%）` : ''
}

function formatLevel(level: string): string {
  if (level.toLowerCase() === 'error' || level.toLowerCase() === 'exception') return '[ERR]'
  if (level.toLowerCase() === 'warning' || level.toLowerCase() === 'warn') return '[WRN]'
  return '[LOG]'
}

function fitUtf8(value: string, maxBytes: number): string {
  const encoder = new TextEncoder()
  if (encoder.encode(value).byteLength <= maxBytes) return value
  const suffix = '…'
  let end = value.length
  while (end > 0 && encoder.encode(`${value.slice(0, end)}${suffix}`).byteLength > maxBytes) end -= 1
  return `${value.slice(0, end)}${suffix}`
}
