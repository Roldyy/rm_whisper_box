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

// ── Hook ──────────────────────────────────────────────────────────────────

export function useTranscriptionWs(jobId: number | null) {
  const wsRef = useRef<WebSocket | null>(null)
  const queryClient = useQueryClient()
  const { updateJobProgress, appendLog, clearJob, setJobError, setActiveJob } = useAppStore()

  useEffect(() => {
    if (jobId === null) return

    const url = `ws://127.0.0.1:7843/api/ws/${jobId}`
    const ws = new WebSocket(url)
    wsRef.current = ws

    ws.onmessage = (event: MessageEvent) => {
      let parsed: WsEvent
      try {
        parsed = JSON.parse(event.data as string) as WsEvent
      } catch {
        return
      }

      switch (parsed.type) {
        case 'progress':
          updateJobProgress(jobId, parsed.percent, parsed.segment)
          break

        case 'log':
          appendLog(jobId, parsed.message)
          break

        case 'done': {
          void queryClient.invalidateQueries({ queryKey: jobKeys.all })
          void queryClient.invalidateQueries({ queryKey: jobKeys.detail(jobId) })
          setTimeout(() => { clearJob(jobId); setActiveJob(null) }, 3000)
          ws.close()
          break
        }

        case 'error': {
          setJobError(jobId, parsed.message)
          void queryClient.invalidateQueries({ queryKey: jobKeys.all })
          void queryClient.invalidateQueries({ queryKey: jobKeys.detail(jobId) })
          setTimeout(() => { clearJob(jobId); setActiveJob(null) }, 5000)
          ws.close()
          break
        }
      }
    }

    ws.onerror = () => {
      void queryClient.invalidateQueries({ queryKey: jobKeys.all })
    }

    return () => {
      ws.close()
      wsRef.current = null
    }
  }, [jobId, queryClient, updateJobProgress, appendLog, clearJob, setJobError, setActiveJob])

  return wsRef
}
