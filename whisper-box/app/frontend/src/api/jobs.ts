import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import apiClient, {
  TranscriptionJob,
  TranscribeRequest,
  TranscribeResponse,
  WhisperModelInfo,
} from './client'

// ── Query keys ────────────────────────────────────────────────────────────

export const jobKeys = {
  all: ['jobs'] as const,
  list: (params: ListJobsParams) => ['jobs', 'list', params] as const,
  detail: (id: number) => ['jobs', 'detail', id] as const,
}

// ── Types ─────────────────────────────────────────────────────────────────

interface ListJobsParams {
  status?: string
  search?: string
  limit?: number
  offset?: number
}

// ── API calls ─────────────────────────────────────────────────────────────

async function fetchJobs(params: ListJobsParams): Promise<TranscriptionJob[]> {
  const { data } = await apiClient.get<TranscriptionJob[]>('/api/jobs', {
    params,
  })
  return data
}

async function fetchJob(id: number): Promise<TranscriptionJob> {
  const { data } = await apiClient.get<TranscriptionJob>(`/api/jobs/${id}`)
  return data
}

async function deleteJob(id: number): Promise<void> {
  await apiClient.delete(`/api/jobs/${id}`)
}

async function cancelJob(id: number): Promise<void> {
  await apiClient.post(`/api/jobs/${id}/cancel`)
}

async function rerunJob(id: number): Promise<TranscribeResponse> {
  const { data } = await apiClient.post<TranscribeResponse>(
    `/api/jobs/${id}/rerun`,
  )
  return data
}

async function createTranscription(
  req: TranscribeRequest,
): Promise<TranscribeResponse> {
  const { data } = await apiClient.post<TranscribeResponse>(
    '/api/transcribe',
    req,
  )
  return data
}

async function openJobOutput(id: number): Promise<{ opened?: string; error?: string }> {
  const { data } = await apiClient.get<{ opened?: string; error?: string }>(
    `/api/jobs/${id}/open`,
  )
  return data
}

// ── Hooks ─────────────────────────────────────────────────────────────────

export function useJobs(params: ListJobsParams) {
  return useQuery({
    queryKey: jobKeys.list(params),
    queryFn: () => fetchJobs(params),
  })
}

export function useJob(id: number) {
  return useQuery({
    queryKey: jobKeys.detail(id),
    queryFn: () => fetchJob(id),
  })
}

export function useDeleteJob() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: deleteJob,
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: jobKeys.all })
    },
  })
}

export function useCancelJob() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: cancelJob,
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: jobKeys.all })
    },
  })
}

export function useRerunJob() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: rerunJob,
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: jobKeys.all })
    },
  })
}

export function useCreateTranscription() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: createTranscription,
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: jobKeys.all })
    },
  })
}

export function useOpenJobOutput() {
  return useMutation({
    mutationFn: openJobOutput,
  })
}

async function fetchWhisperModels(): Promise<WhisperModelInfo[]> {
  const { data } = await apiClient.get<WhisperModelInfo[]>('/api/whisper/models')
  return data
}

export function useWhisperModels() {
  return useQuery({
    queryKey: ['whisper-models'],
    queryFn: fetchWhisperModels,
    staleTime: Infinity,
  })
}
