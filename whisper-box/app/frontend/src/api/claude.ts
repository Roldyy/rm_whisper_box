import { useQuery, useMutation } from '@tanstack/react-query'
import apiClient from './client'

// ── Types ─────────────────────────────────────────────────────────────────

export interface ClaudeStatus {
  available: boolean
  version: string
  token_present: boolean
  api_key_conflict: boolean
  error: string | null
}

export interface EnhanceResult {
  job_id: number
  mode: string
  model: string
  summary_path: string
  content: string
}

export interface VerifyResult {
  ok: boolean
  response?: string
}

// ── API calls ─────────────────────────────────────────────────────────────

async function fetchClaudeStatus(): Promise<ClaudeStatus> {
  const { data } = await apiClient.get<ClaudeStatus>('/api/claude/status')
  return data
}

async function saveToken(token: string): Promise<{ saved: boolean }> {
  const { data } = await apiClient.post<{ saved: boolean }>('/api/claude/token', {
    token,
  })
  return data
}

async function deleteToken(): Promise<{ deleted: boolean }> {
  const { data } = await apiClient.delete<{ deleted: boolean }>('/api/claude/token')
  return data
}

async function verifyToken(): Promise<VerifyResult> {
  const { data } = await apiClient.post<VerifyResult>('/api/claude/verify')
  return data
}

async function enhanceTranscript(args: {
  jobId: number
  mode: string
  model: string
}): Promise<EnhanceResult> {
  const { data } = await apiClient.post<EnhanceResult>(
    `/api/claude/transcripts/${args.jobId}/enhance`,
    { mode: args.mode, model: args.model },
  )
  return data
}

// ── Hooks ─────────────────────────────────────────────────────────────────

export const claudeKeys = {
  status: ['claude', 'status'] as const,
}

export function useClaudeStatus() {
  return useQuery({
    queryKey: claudeKeys.status,
    queryFn: fetchClaudeStatus,
    staleTime: 30_000,
  })
}

export function useSaveToken() {
  return useMutation({ mutationFn: saveToken })
}

export function useDeleteToken() {
  return useMutation({ mutationFn: deleteToken })
}

export function useVerifyToken() {
  return useMutation({ mutationFn: verifyToken })
}

export function useEnhanceTranscript() {
  return useMutation({ mutationFn: enhanceTranscript })
}
