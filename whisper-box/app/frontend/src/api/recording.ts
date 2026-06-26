import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import apiClient from './client'
import { jobKeys } from './jobs'

export interface StartRecordingRequest {
  capture_mic?: boolean
  model?: string
  language?: string
  output_format?: string
  output_dir?: string
  task?: string
  word_timestamps?: boolean
  initial_prompt?: string | null
  temperature?: number
  condition_on_previous_text?: boolean
  compression_ratio_threshold?: number
  no_speech_threshold?: number
}

export interface RecordingStatus {
  is_recording: boolean
  elapsed_seconds: number
}

async function startRecording(req: StartRecordingRequest): Promise<{ status: string; output_path: string }> {
  const { data } = await apiClient.post('/api/recording/start', req)
  return data
}

async function stopRecording(): Promise<{ job_id: number; status: string }> {
  const { data } = await apiClient.post('/api/recording/stop')
  return data
}

async function fetchRecordingStatus(): Promise<RecordingStatus> {
  const { data } = await apiClient.get<RecordingStatus>('/api/recording/status')
  return data
}

export function useRecordingStatus() {
  return useQuery({
    queryKey: ['recording-status'],
    queryFn: fetchRecordingStatus,
    refetchInterval: (query) => (query.state.data?.is_recording ? 1000 : false),
  })
}

export function useStartRecording() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: startRecording,
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['recording-status'] })
    },
  })
}

export function useStopRecording() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: stopRecording,
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['recording-status'] })
      void qc.invalidateQueries({ queryKey: jobKeys.all })
    },
  })
}
