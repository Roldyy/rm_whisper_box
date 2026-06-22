import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { AlertCircle } from 'lucide-react'
import TranscribeForm, { FormValues } from '../components/TranscribeForm'
import RecordButton from '../components/RecordButton'
import { useRecordingStatus, useStartRecording, useStopRecording } from '../api/recording'
import { useSettings } from '../api/settings'
import { useAppStore } from '../stores/appStore'

export default function RecordPage() {
  const navigate = useNavigate()
  const { data: settings } = useSettings()
  const { data: status } = useRecordingStatus()
  const { mutate: startRecording, isPending: isStarting, error: startError } = useStartRecording()
  const { mutate: stopRecording, isPending: isStopping } = useStopRecording()
  const setActiveJob = useAppStore((s) => s.setActiveJob)

  const [captureMic, setCaptureMic] = useState(true)
  const [form, setForm] = useState<FormValues>({
    model: settings?.default_model ?? 'large-v3-turbo',
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

  const isRecording = status?.is_recording ?? false
  const elapsed = status?.elapsed_seconds ?? 0

  function handleFormChange(key: keyof FormValues, val: string | boolean | number) {
    setForm((prev) => ({ ...prev, [key]: val }))
  }

  function handleStart() {
    startRecording({
      capture_mic: captureMic,
      model: form.model,
      language: form.language,
      output_format: form.output_format,
      output_dir: form.output_dir,
      task: form.task,
      word_timestamps: form.word_timestamps,
      initial_prompt: form.initial_prompt || null,
      temperature: form.temperature,
      beam_size: form.beam_size,
      best_of: form.best_of,
      condition_on_previous_text: form.condition_on_previous_text,
      fp16: form.fp16,
      compression_ratio_threshold: form.compression_ratio_threshold,
      no_speech_threshold: form.no_speech_threshold,
    })
  }

  function handleStop() {
    stopRecording(undefined, {
      onSuccess: (data) => {
        setActiveJob(data.job_id)
        navigate('/history')
      },
    })
  }

  const errorMsg = startError
    ? ((startError as { response?: { data?: { detail?: string } } })?.response?.data?.detail ?? 'Erreur lors du démarrage')
    : null

  return (
    <div className="max-w-2xl space-y-6">
      <h1 className="text-xl font-semibold text-gray-900 dark:text-white">Enregistrer et transcrire</h1>

      {/* Permission note */}
      <div className="flex items-start gap-3 p-4 rounded-xl bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800/50">
        <AlertCircle className="w-4 h-4 text-amber-500 mt-0.5 shrink-0" />
        <p className="text-xs text-amber-700 dark:text-amber-300 leading-relaxed">
          Au premier lancement, macOS demandera l'autorisation d'enregistrement d'écran pour capturer
          l'audio système. Accordez-la dans Réglages Système → Confidentialité → Enregistrement d'écran.
        </p>
      </div>

      {/* Mic toggle + record button */}
      <section className="bg-white dark:bg-gray-800/40 rounded-xl p-5 border border-gray-200 dark:border-gray-700/50 space-y-4">
        {/* Mic toggle */}
        <label className="flex items-center gap-3 cursor-pointer select-none w-fit">
          <div className="relative">
            <input
              type="checkbox"
              className="sr-only"
              checked={captureMic}
              disabled={isRecording}
              onChange={(e) => setCaptureMic(e.target.checked)}
            />
            <div className={`w-9 h-5 rounded-full transition-colors ${captureMic ? 'bg-violet-600' : 'bg-gray-700'} ${isRecording ? 'opacity-50' : ''}`} />
            <div className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-white transition-transform ${captureMic ? 'translate-x-4' : ''}`} />
          </div>
          <span className="text-sm text-gray-300">Inclure le microphone</span>
        </label>

        {errorMsg && (
          <p className="text-xs text-red-400">{errorMsg}</p>
        )}

        <RecordButton
          isRecording={isRecording}
          elapsedSeconds={elapsed}
          onStart={handleStart}
          onStop={handleStop}
          disabled={isStarting || isStopping}
        />
      </section>

      {/* Transcription options — locked while recording */}
      <section className={`bg-white dark:bg-gray-800/40 rounded-xl p-5 border border-gray-200 dark:border-gray-700/50 space-y-4 ${isRecording ? 'opacity-50 pointer-events-none' : ''}`}>
        <p className="text-xs text-gray-500 dark:text-gray-400">
          Options de transcription appliquées à l'enregistrement
        </p>
        <TranscribeForm
          values={form}
          onChange={handleFormChange}
          onSubmit={() => {}}
          disabled={true}
          isLoading={false}
        />
      </section>
    </div>
  )
}
