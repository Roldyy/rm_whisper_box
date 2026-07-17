import axios from 'axios'

// ── TypeScript interfaces ─────────────────────────────────────────────────

export interface TranscriptionJob {
  id: number
  source_path: string
  source_filename: string
  model: string
  language: string | null
  output_format: string
  output_path: string | null
  status: 'pending' | 'running' | 'success' | 'error' | 'cancelled'
  progress: number
  duration_audio: number | null
  duration_run: number | null
  device_used: string | null
  error_message: string | null
  detected_language: string | null
  // Advanced Whisper options
  task: string
  word_timestamps: number
  initial_prompt: string | null
  condition_on_previous_text: number
  temperature: number
  compression_ratio_threshold: number
  no_speech_threshold: number
  created_at: string
  updated_at: string
}

export interface WhisperModelInfo {
  name: string
  params: string
  vram: string
  speed: string
}

export interface ExecutionLog {
  id: number
  job_id: number | null
  operation_type: string
  status: string
  log_content?: string
  created_at: string
}

export interface Settings {
  default_model: string
  default_language: string
  default_output_format: string
  default_output_dir: string
  // Claude (IA) settings
  claude_enabled?: string
  claude_token_present?: string
  claude_model?: string
  claude_default_mode?: string
  claude_auto_after_transcribe?: string
}

export interface HealthResponse {
  status: string
  version: string
  ffmpeg_available: boolean
  ffmpeg_version: string
  device: 'mps' | 'cpu'
}

export interface TranscribeRequest {
  source_path: string
  model: string
  language: string
  output_format: string
  output_dir: string
  // Advanced Whisper options
  task?: string
  temperature?: number
  word_timestamps?: boolean
  initial_prompt?: string | null
  condition_on_previous_text?: boolean
  compression_ratio_threshold?: number
  no_speech_threshold?: number
}

export interface TranscribeResponse {
  job_id: number
  status: string
}

// ── Axios instance ────────────────────────────────────────────────────────

const apiClient = axios.create({
  baseURL: window.location.origin,
  headers: {
    'Content-Type': 'application/json',
  },
})

apiClient.interceptors.response.use(
  (response) => response,
  (error: unknown) => {
    if (axios.isAxiosError(error)) {
      const msg =
        (error.response?.data as { detail?: string } | undefined)?.detail ??
        error.message
      console.error('[API Error]', msg)
    }
    return Promise.reject(error)
  },
)

export default apiClient
