/**
 * main.ts
 * Even G2 Debug Bridge フロントエンドのエントリポイント。
 *
 * 役割:
 *   1. Python ローカルサーバーに WebSocket で接続し、ログを受信する。
 *   2. 受信したログを Even G2 スマートグラスに表示する。
 *   3. ブラウザ UI のステータスを更新する。
 */

import { initG2, displayLogOnG2 } from './g2-display'

// ---------------------------------------------------------------------------
// 設定
// ---------------------------------------------------------------------------
// サーバーの WebSocket ポートを URL パラメータから取得（デフォルト: 8766）
const params = new URLSearchParams(window.location.search)
const WS_PORT = params.get('wsPort') ?? '8766'
const WS_HOST = window.location.hostname
const WS_URL = `ws://${WS_HOST}:${WS_PORT}`

const RECONNECT_INTERVAL_MS = 3000

// ---------------------------------------------------------------------------
// DOM 参照
// ---------------------------------------------------------------------------
const serverDot = document.getElementById('server-dot')!
const serverStatus = document.getElementById('server-status')!
const g2Dot = document.getElementById('g2-dot')!
const g2Status = document.getElementById('g2-status')!
const latestLog = document.getElementById('latest-log')!
const logCount = document.getElementById('log-count')!

// ---------------------------------------------------------------------------
// 状態
// ---------------------------------------------------------------------------
interface LogEntry {
  type: string
  level: string
  message: string
  timestamp: string
  tag: string
}

let receivedCount = 0

// ---------------------------------------------------------------------------
// Even G2 初期化
// ---------------------------------------------------------------------------
initG2((connected) => {
  if (connected) {
    g2Dot.className = 'dot connected'
    g2Status.textContent = 'G2 に接続しました'
  } else {
    g2Dot.className = 'dot error'
    g2Status.textContent = 'G2 への接続に失敗しました（Simulator または Even Hub アプリで開いてください）'
  }
})

// ---------------------------------------------------------------------------
// WebSocket 接続（サーバーへの接続）
// ---------------------------------------------------------------------------
function connectToServer(): void {
  serverDot.className = 'dot connecting'
  serverStatus.textContent = `サーバーに接続中... (${WS_URL})`

  const ws = new WebSocket(WS_URL)

  ws.onopen = () => {
    // ブラウザクライアントとして自己紹介
    ws.send(JSON.stringify({ type: 'browser' }))
    serverDot.className = 'dot connected'
    serverStatus.textContent = 'サーバーに接続しました'
  }

  ws.onmessage = async (event) => {
    try {
      const data = JSON.parse(event.data as string)

      if (data.type === 'log') {
        await handleLogEntry(data as LogEntry)
      } else if (data.type === 'history') {
        // 接続時に受信する過去ログ（最新の1件のみ表示）
        const logs: LogEntry[] = data.logs ?? []
        if (logs.length > 0) {
          const latest = logs[logs.length - 1]
          await handleLogEntry(latest)
          receivedCount = logs.length
          updateLogCount()
        }
      }
    } catch (e) {
      console.error('メッセージの解析に失敗しました:', e)
    }
  }

  ws.onclose = () => {
    serverDot.className = 'dot connecting'
    serverStatus.textContent = `サーバーから切断されました。再接続中... (${RECONNECT_INTERVAL_MS / 1000}秒後)`
    setTimeout(connectToServer, RECONNECT_INTERVAL_MS)
  }

  ws.onerror = () => {
    serverDot.className = 'dot error'
    serverStatus.textContent = `サーバーへの接続に失敗しました (${WS_URL})`
  }
}

// ---------------------------------------------------------------------------
// ログ処理
// ---------------------------------------------------------------------------
async function handleLogEntry(entry: LogEntry): Promise<void> {
  receivedCount++
  updateLogCount()

  // ブラウザ UI を更新
  const levelClass = getLevelClass(entry.level)
  latestLog.className = `message ${levelClass}`
  latestLog.textContent = `[${entry.level}] ${entry.message}`

  // Even G2 に表示
  await displayLogOnG2(entry.level, entry.message, entry.timestamp)
}

function updateLogCount(): void {
  logCount.textContent = `受信ログ: ${receivedCount} 件`
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

// ---------------------------------------------------------------------------
// 起動
// ---------------------------------------------------------------------------
connectToServer()
