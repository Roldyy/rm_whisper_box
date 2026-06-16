import { useState } from 'react'
import { Loader2, XCircle } from 'lucide-react'
import FileDropZone from '../components/FileDropZone'
import TranscribeForm, { FormValues } from '../components/TranscribeForm'
import ProgressBar from '../components/ProgressBar'
import LogViewer from '../components/LogViewer'
import { useCreateTranscription, useCancelJob } from '../api/jobs'
import { useAppStore } from '../stores/appStore'
import { useTranscriptionWs } from '../hooks/useTranscriptionWs'
import { useSettings } from '../api/settings'

export default function TranscribePage() {
  const { data: settings } = useSettings()

  const [filePath, setFilePath] = useState('')
  const [form, setForm] = useState<FormValues>({
    model: settings?.default_model ?? 'base',
    language: settings?.default_language ?? '',
    output_format: settings?.default_output_format ?? 'txt',
    output_dir: settings?.default_output_dir ?? '',
    task: 'transcribe',
    word_timestamps: false,
    initial_prompt: '',
    temperature: 0.0,
    beam_size: 5,
    best_of: 5,
    condition_on_previous_text: true,
    fp16: true,
    compression_ratio_threshold: 2.4,
    no_speech_threshold: 0.6,
  })

  const activeJobId = useAppStore((s) => s.activeJobId)
  const runningJobs = useAppStore((s) => s.runningJobs)
  const setActiveJob = useAppStore((s) => s.setActiveJob)

  const jobState = activeJobId != null ? runningJobs.get(activeJobId) : undefined
  const percent = jobState?.percent ?? 0
  const logs = jobState?.logs ?? []

  const { mutate: createJob, isPending } = useCreateTranscription()
  const { mutate: cancelJob } = useCancelJob()

  // WebSocket
  useTranscriptionWs(activeJobId)

  const isRunning = activeJobId != null && (jobState !== undefined)

  function handleFormChange(key: keyof FormValues, val: string | boolean | number) {
    setForm((prev) => ({ ...prev, [key]: val }))
  }

  function handleSubmit() {
    if (!filePath.trim()) return
    createJob(
      {
        source_path: filePath.trim(),
        model: form.model,
        language: form.language,
        output_format: form.output_format,
        output_dir: form.output_dir,
        task: form.task,
        temperature: form.temperature,
        word_timestamps: form.word_timestamps,
        initial_prompt: form.initial_prompt || null,
        condition_on_previous_text: form.condition_on_previous_text,
        fp16: form.fp16,
        beam_size: form.beam_size,
        best_of: form.best_of,
        compression_ratio_threshold: form.compression_ratio_threshold,
        no_speech_threshold: form.no_speech_threshold,
      },
      {
        onSuccess: (data) => {
          setActiveJob(data.job_id)
        },
      },
    )
  }

  function handleCancel() {
    if (activeJobId != null) {
      cancelJob(activeJobId)
      setActiveJob(null)
    }
  }

  return (
    <div className="max-w-2xl space-y-6">
      <h1 className="text-xl font-semibold text-gray-900 dark:text-white">Transcrire un fichier</h1>

      {/* File drop zone */}
      <section className="bg-white dark:bg-gray-800/40 rounded-xl p-5 border border-gray-200 dark:border-gray-700/50 space-y-4">
        <FileDropZone value={filePath} onChange={setFilePath} />
      </section>

      {/* Options + Stop button */}
      <section className="bg-white dark:bg-gray-800/40 rounded-xl p-5 border border-gray-200 dark:border-gray-700/50 space-y-4">
        <TranscribeForm
          values={form}
          onChange={handleFormChange}
          onSubmit={handleSubmit}
          disabled={!filePath.trim() || isPending || isRunning}
          isLoading={isPending}
        />

        {/* Stop button — always visible, disabled when no job running */}
        <div className="pt-1 border-t border-gray-100 dark:border-gray-700/50">
          <button
            onClick={handleCancel}
            disabled={!isRunning}
            className="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-colors
              bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800/50
              text-red-500 dark:text-red-400
              hover:bg-red-100 dark:hover:bg-red-900/40
              disabled:opacity-30 disabled:cursor-not-allowed"
          >
            <XCircle className="w-4 h-4" />
            Arrêter la transcription
          </button>
        </div>
      </section>

      {/* Progress */}
      {(isRunning || percent > 0) && (
        <section className="bg-white dark:bg-gray-800/40 rounded-xl p-5 border border-gray-200 dark:border-gray-700/50 space-y-3">
          <div className="flex items-center gap-2">
            <Loader2 className="w-4 h-4 text-violet-400 animate-spin" />
            <span className="text-sm font-medium text-gray-600 dark:text-gray-300">
              Transcription en cours… {percent}%
            </span>
          </div>

          <ProgressBar percent={percent} />

          <LogViewer logs={logs} className="h-40" />
        </section>
      )}
    </div>
  )
}
