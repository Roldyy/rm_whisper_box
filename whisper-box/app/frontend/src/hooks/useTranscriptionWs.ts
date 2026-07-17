import { useEffect, useRef } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useAppStore } from '../stores/appStore'
import { jobKeys } from '../api/jobs'

// ── WS event shapes ───────────────────────────────────────────────────────

interface WsProgressEvent {
  type: 'progress'
  percent: number
  segment: string
}

interface WsLogEvent {
  type: 'log'
  message: string
}

interface WsDoneEvent {
  type: 'done'
  status: string
  output_path: string
}

interface WsErrorEvent {
  type: 'error'
  message: string
}

type WsEvent = WsProgressEvent | WsLogEvent | WsDoneEvent | WsErrorEvent

// Reconnect backoff (ms) — capped so a backend hiccup doesn't strand the UI.
const MAX_RECONNECT_DELAY = 5000

function wsUrl(jobId: number): string {
  const proto = window.location.protocol === 'https:' ? 'wss' : 'ws'
  return `${proto}://${window.location.host}/api/ws/${jobId}`
}

// ── Hook ──────────────────────────────────────────────────────────────────

export function useTranscriptionWs(jobId: number | null) {
  const wsRef = useRef<WebSocket | null>(null)
  const queryClient = useQueryClient()
  const { updateJobProgress, appendLog, clearJob, setJobError, setActiveJob } = useAppStore()

  useEffect(() => {
    if (jobId === null) return

    // Track timers and lifecycle so cleanup never fires against a stale job,
    // and so an intentional close doesn't trigger a reconnect.
    const timers: ReturnType<typeof setTimeout>[] = []
    let disposed = false
    let finished = false
    let reconnectAttempt = 0

    const schedule = (fn: () => void, ms: number) => {
      timers.push(setTimeout(fn, ms))
    }

    function connect() {
      if (disposed) return

      const ws = new WebSocket(wsUrl(jobId as number))
      wsRef.current = ws

      ws.onopen = () => {
        reconnectAttempt = 0
      }

      ws.onmessage = (event: MessageEvent) => {
        let parsed: WsEvent
        try {
          parsed = JSON.parse(event.data as string) as WsEvent
        } catch {
          return
        }

        switch (parsed.type) {
          case 'progress':
            updateJobProgress(jobId as number, parsed.percent, parsed.segment)
            break

          case 'log':
            appendLog(jobId as number, parsed.message)
            break

          case 'done': {
            finished = true
            void queryClient.invalidateQueries({ queryKey: jobKeys.all })
            void queryClient.invalidateQueries({ queryKey: jobKeys.detail(jobId as number) })
            schedule(() => {
              clearJob(jobId as number)
              setActiveJob(null)
            }, 3000)
            ws.close()
            break
          }

          case 'error': {
            finished = true
            setJobError(jobId as number, parsed.message)
            void queryClient.invalidateQueries({ queryKey: jobKeys.all })
            void queryClient.invalidateQueries({ queryKey: jobKeys.detail(jobId as number) })
            schedule(() => {
              clearJob(jobId as number)
              setActiveJob(null)
            }, 5000)
            ws.close()
            break
          }
        }
      }

      ws.onerror = () => {
        void queryClient.invalidateQueries({ queryKey: jobKeys.all })
      }

      ws.onclose = () => {
        // Reconnect only if the job is still in flight and we didn't tear down
        // the hook ourselves (e.g. transient backend restart / network blip).
        if (disposed || finished) return
        reconnectAttempt += 1
        const delay = Math.min(500 * 2 ** (reconnectAttempt - 1), MAX_RECONNECT_DELAY)
        schedule(connect, delay)
      }
    }

    connect()

    return () => {
      disposed = true
      timers.forEach(clearTimeout)
      wsRef.current?.close()
      wsRef.current = null
    }
  }, [jobId, queryClient, updateJobProgress, appendLog, clearJob, setJobError, setActiveJob])

  return wsRef
}
