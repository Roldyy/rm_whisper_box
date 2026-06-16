import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import apiClient, { Settings, HealthResponse } from './client'

// ── Query keys ────────────────────────────────────────────────────────────

export const settingsKeys = {
  all: ['settings'] as const,
  health: ['health'] as const,
}

// ── API calls ─────────────────────────────────────────────────────────────

async function fetchSettings(): Promise<Settings> {
  const { data } = await apiClient.get<Settings>('/api/settings')
  return data
}

async function updateSettings(
  body: Partial<Settings>,
): Promise<Settings> {
  const { data } = await apiClient.post<Settings>('/api/settings', body)
  return data
}

async function fetchHealth(): Promise<HealthResponse> {
  const { data } = await apiClient.get<HealthResponse>('/api/health')
  return data
}

async function openDataDir(): Promise<{ opened?: string; error?: string }> {
  const { data } = await apiClient.get<{ opened?: string; error?: string }>(
    '/api/settings/open-data-dir',
  )
  return data
}

// ── Hooks ─────────────────────────────────────────────────────────────────

export function useSettings() {
  return useQuery({
    queryKey: settingsKeys.all,
    queryFn: fetchSettings,
  })
}

export function useUpdateSettings() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: updateSettings,
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: settingsKeys.all })
    },
  })
}

export function useHealth() {
  return useQuery({
    queryKey: settingsKeys.health,
    queryFn: fetchHealth,
    enabled: false, // manual trigger only
  })
}

export function useOpenDataDir() {
  return useMutation({
    mutationFn: openDataDir,
  })
}

async function triggerUpdate(): Promise<{ status: string; message: string }> {
  const { data } = await apiClient.post<{ status: string; message: string }>('/api/update')
  return data
}

export function useUpdate() {
  return useMutation({ mutationFn: triggerUpdate })
}
