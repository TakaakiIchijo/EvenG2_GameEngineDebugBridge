import { disposeG2, initG2, queueLogForG2, queueMinimapForG2, type G2ConnectionState, type MinimapState } from './g2-display'

interface LogEntry {
  type: 'log'
  level: string
  message: string
  timestamp: string
  tag: string
  protocol_version?: number
}

interface HistoryPayload {
  type: 'history'
  logs: LogEntry[]
}

interface StatusPayload {
  type: 'status'
  status: string
  detail?: string
}

type MinimapPayload = MinimapState & { protocol_version?: number }

const params = new URLSearchParams(window.location.search)
const wsPort = params.get('wsPort') ?? '8766'
const wsUrl = params.get('wsUrl') ?? `${window.location.protocol === 'https:' ? 'wss' : 'ws'}://${window.location.hostname}:${wsPort}`
const reconnectBaseMs = 1000
const reconnectMaxMs = 10000

const serverDot = document.querySelector<HTMLElement>('#server-dot')
const serverStatus = document.querySelector<HTMLElement>('#server-status')
const g2Dot = document.querySelector<HTMLElement>('#g2-dot')
const g2Status = document.querySelector<HTMLElement>('#g2-status')
const latestLog = document.querySelector<HTMLElement>('#latest-log')
const logCount = document.querySelector<HTMLElement>('#log-count')

let receivedCount = 0
let reconnectAttempts = 0
let reconnectTimer: number | null = null
let activeSocket: WebSocket | null = null
let stopped = false

function setStatus(
  dot: HTMLElement | null,
  text: HTMLElement | null,
  state: 'connected' | 'connecting' | 'error',
  detail: string,
): void {
  if (dot) {
    dot.className = `dot ${state}`
  }
  if (text) {
    text.textContent = detail
  }
}

function updateG2Status(state: G2ConnectionState, detail: string): void {
  const visualState = state === 'connected' || state === 'ready'
    ? 'connected'
    : state === 'connecting'
      ? 'connecting'
      : 'error'
  setStatus(g2Dot, g2Status, visualState, detail)
}

function connectToServer(): void {
  if (stopped) {
    return
  }

  setStatus(serverDot, serverStatus, 'connecting', `サーバーに接続中... (${wsUrl})`)

  const socket = new WebSocket(wsUrl)
  activeSocket = socket

  socket.addEventListener('open', () => {
    if (socket !== activeSocket) {
      return
    }
    socket.send(JSON.stringify({ type: 'browser', protocol_version: 1 }))
    reconnectAttempts = 0
    setStatus(serverDot, serverStatus, 'connected', 'サーバーに接続しました')
  })

  socket.addEventListener('message', event => {
    try {
      handleServerMessage(JSON.parse(String(event.data)))
    } catch (error) {
      console.error('[Bridge] サーバーメッセージの解析に失敗しました', error)
    }
  })

  socket.addEventListener('error', () => {
    if (socket === activeSocket) {
      setStatus(serverDot, serverStatus, 'error', `サーバーへの接続に失敗しました (${wsUrl})`)
    }
  })

  socket.addEventListener('close', () => {
    if (socket !== activeSocket || stopped) {
      return
    }
    activeSocket = null
    scheduleReconnect()
  })
}

function handleServerMessage(payload: unknown): void {
  if (!payload || typeof payload !== 'object' || !('type' in payload)) {
    console.warn('[Bridge] 不正なサーバーメッセージを無視しました', payload)
    return
  }

  const typedPayload = payload as { type: string }
  if (typedPayload.type === 'log') {
    handleLogEntry(typedPayload as LogEntry)
    return
  }

  if (typedPayload.type === 'minimap') {
    handleMinimap(typedPayload as MinimapPayload)
    return
  }

  if (typedPayload.type === 'history') {
    const history = typedPayload as HistoryPayload
    receivedCount = history.logs.length
    updateLogCount()
    const latest = history.logs.length > 0 ? history.logs[history.logs.length - 1] : undefined
    if (latest) {
      updateBrowserPreview(latest)
      queueLogForG2(latest.level, latest.message, latest.timestamp)
    }
    return
  }

  if (typedPayload.type === 'status') {
    const status = typedPayload as StatusPayload
    console.warn(`[Bridge] サーバー通知: ${status.status}${status.detail ? ` (${status.detail})` : ''}`)
  }
}

function handleMinimap(minimap: MinimapPayload): void {
  queueMinimapForG2(minimap)
  if (latestLog) {
    latestLog.className = 'message level-log'
    latestLog.textContent = `Dungeon map r${minimap.revision}: ${minimap.width}×${minimap.height}, player ${minimap.player.x},${minimap.player.y}`
  }
}

function handleLogEntry(entry: LogEntry): void {
  receivedCount += 1
  updateLogCount()
  updateBrowserPreview(entry)
  queueLogForG2(entry.level, entry.message, entry.timestamp)
}

function updateBrowserPreview(entry: LogEntry): void {
  if (latestLog) {
    latestLog.className = `message ${getLevelClass(entry.level)}`
    latestLog.textContent = `[${entry.level}] ${entry.message}`
  }
}

function updateLogCount(): void {
  if (logCount) {
    logCount.textContent = `受信ログ: ${receivedCount} 件`
  }
}

function getLevelClass(level: string): string {
  switch (level.toLowerCase()) {
    case 'error':
    case 'exception':
      return 'level-error'
    case 'warning':
    case 'warn':
      return 'level-warning'
    default:
      return 'level-log'
  }
}

function scheduleReconnect(): void {
  reconnectAttempts += 1
  const delay = Math.min(reconnectBaseMs * 2 ** (reconnectAttempts - 1), reconnectMaxMs)
  setStatus(serverDot, serverStatus, 'connecting', `サーバーから切断されました。${Math.ceil(delay / 1000)}秒後に再接続します`)
  reconnectTimer = window.setTimeout(connectToServer, delay)
}

window.addEventListener('beforeunload', () => {
  stopped = true
  if (reconnectTimer !== null) {
    window.clearTimeout(reconnectTimer)
  }
  activeSocket?.close()
  disposeG2()
})

void initG2(updateG2Status)
connectToServer()
