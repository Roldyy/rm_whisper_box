import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import apiClient, { ExecutionLog } from './client'

// ── Query keys ────────────────────────────────────────────────────────────

export const logKeys = {
  all: ['logs'] as const,
  list: (params: ListLogsParams) => ['logs', 'list', params] as const,
  detail: (id: number) => ['logs', 'detail', id] as const,
}

// ── Types ─────────────────────────────────────────────────────────────────

interface ListLogsParams {
  status?: string
  limit?: number
  offset?: number
}

// ── API calls ─────────────────────────────────────────────────────────────

async function fetchLogs(params: ListLogsParams): Promise<ExecutionLog[]> {
  const { data } = await apiClient.get<ExecutionLog[]>('/api/logs', { params })
  return data
}

async function fetchLog(id: number): Promise<ExecutionLog> {
  const { data } = await apiClient.get<ExecutionLog>(`/api/logs/${id}`)
  return data
}

async function deleteLog(id: number): Promise<void> {
  await apiClient.delete(`/api/logs/${id}`)
}

// ── Hooks ─────────────────────────────────────────────────────────────────

export function useLogs(params: ListLogsParams) {
  return useQuery({
    queryKey: logKeys.list(params),
    queryFn: () => fetchLogs(params),
  })
}

export function useLog(id: number) {
  return useQuery({
    queryKey: logKeys.detail(id),
    queryFn: () => fetchLog(id),
  })
}

export function useDeleteLog() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: deleteLog,
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: logKeys.all })
    },
  })
}
