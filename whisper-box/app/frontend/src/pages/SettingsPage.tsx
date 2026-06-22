import { useState, useEffect, ChangeEvent, FormEvent } from 'react'
import { Loader2, CheckCircle, AlertCircle, FolderOpen } from 'lucide-react'
import { useSettings, useUpdateSettings, useOpenDataDir } from '../api/settings'
import apiClient, { HealthResponse, Settings } from '../api/client'
import { useAppStore } from '../stores/appStore'

const MODELS = ['tiny', 'base', 'small', 'medium', 'large', 'large-v2', 'large-v3', 'large-v3-turbo'] as const
const LANGUAGES: { value: string; label: string }[] = [
  { value: '', label: 'Auto-détection' },
  { value: 'fr', label: 'Français' },
  { value: 'en', label: 'Anglais' },
  { value: 'nl', label: 'Néerlandais' },
  { value: 'de', label: 'Allemand' },
  { value: 'es', label: 'Espagnol' },
  { value: 'it', label: 'Italien' },
  { value: 'pt', label: 'Portugais' },
  { value: 'ar', label: 'Arabe' },
  { value: 'zh', label: 'Chinois' },
  { value: 'ja', label: 'Japonais' },
]
const OUTPUT_FORMATS = ['txt', 'srt', 'vtt', 'json', 'tsv'] as const

export default function SettingsPage() {
  const { data: settings, isLoading } = useSettings()
  const { mutate: updateSettings, isPending: isSaving } = useUpdateSettings()
  const { mutate: openDataDir } = useOpenDataDir()
  const setStoreSettings = useAppStore((s) => s.setSettings)

  const [form, setForm] = useState<Settings>({
    default_model: 'large-v3-turbo',
    default_language: '',
    default_output_format: 'txt',
    default_output_dir: '',
  })

  const [saved, setSaved] = useState(false)
  const [health, setHealth] = useState<HealthResponse | null>(null)
  const [healthLoading, setHealthLoading] = useState(false)
  const [healthError, setHealthError] = useState<string | null>(null)

  useEffect(() => {
    if (settings) {
      setForm({
        default_model: settings.default_model ?? 'large-v3-turbo',
        default_language: settings.default_language ?? '',
        default_output_format: settings.default_output_format ?? 'txt',
        default_output_dir: settings.default_output_dir ?? '',
      })
    }
  }, [settings])

  function handleChange(key: keyof Settings, val: string) {
    setForm((prev) => ({ ...prev, [key]: val }))
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    updateSettings(form, {
      onSuccess: (updated) => {
        setStoreSettings(updated as unknown as Record<string, string>)
        setSaved(true)
        setTimeout(() => setSaved(false), 2000)
      },
    })
  }

  async function handleTestFfmpeg() {
    setHealthLoading(true)
    setHealthError(null)
    setHealth(null)
    try {
      const { data } = await apiClient.get<HealthResponse>('/api/health')
      setHealth(data)
    } catch {
      setHealthError('Impossible de contacter le backend.')
    } finally {
      setHealthLoading(false)
    }
  }

  const inputCls =
    'w-full rounded-lg bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-700 px-3 py-2 text-sm text-gray-900 dark:text-gray-200 focus:outline-none focus:ring-1 focus:ring-violet-500'

  if (isLoading) {
    return (
      <div className="text-center py-16 text-gray-500 text-sm">
        Chargement…
      </div>
    )
  }

  return (
    <div className="max-w-lg space-y-6">
      <h1 className="text-xl font-semibold text-gray-900 dark:text-white">Paramètres</h1>

      {/* Settings form */}
      <form
        onSubmit={handleSubmit}
        className="bg-white dark:bg-gray-800/40 rounded-xl border border-gray-200 dark:border-gray-700/50 p-5 space-y-4"
      >
        <h2 className="text-sm font-semibold text-gray-500 dark:text-gray-300 uppercase tracking-wide">
          Valeurs par défaut
        </h2>

        {/* Default model */}
        <div>
          <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">
            Modèle par défaut
          </label>
          <select
            className={inputCls}
            value={form.default_model}
            onChange={(e: ChangeEvent<HTMLSelectElement>) =>
              handleChange('default_model', e.target.value)
            }
          >
            {MODELS.map((m) => (
              <option key={m} value={m}>
                {m}
              </option>
            ))}
          </select>
        </div>

        {/* Default language */}
        <div>
          <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">
            Langue par défaut
          </label>
          <select
            className={inputCls}
            value={form.default_language}
            onChange={(e: ChangeEvent<HTMLSelectElement>) =>
              handleChange('default_language', e.target.value)
            }
          >
            {LANGUAGES.map(({ value, label }) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </div>

        {/* Default output format */}
        <div>
          <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">
            Format de sortie par défaut
          </label>
          <select
            className={inputCls}
            value={form.default_output_format}
            onChange={(e: ChangeEvent<HTMLSelectElement>) =>
              handleChange('default_output_format', e.target.value)
            }
          >
            {OUTPUT_FORMATS.map((f) => (
              <option key={f} value={f}>
                {f.toUpperCase()}
              </option>
            ))}
          </select>
        </div>

        {/* Default output dir */}
        <div>
          <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">
            Dossier de sortie par défaut{' '}
            <span className="text-gray-600">
              (vide = ~/Whisper Memory/transcripts/)
            </span>
          </label>
          <input
            type="text"
            placeholder="/Users/…/transcripts"
            value={form.default_output_dir}
            onChange={(e: ChangeEvent<HTMLInputElement>) =>
              handleChange('default_output_dir', e.target.value)
            }
            className={`${inputCls} font-mono`}
          />
        </div>

        <div className="flex items-center gap-3 pt-1">
          <button
            type="submit"
            disabled={isSaving}
            className="flex items-center gap-2 px-4 py-2 rounded-lg bg-violet-600 hover:bg-violet-500 disabled:opacity-40 text-white text-sm font-medium transition-colors"
          >
            {isSaving ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : null}
            Enregistrer
          </button>

          {saved && (
            <div className="flex items-center gap-1 text-green-400 text-sm">
              <CheckCircle className="w-4 h-4" />
              Sauvegardé
            </div>
          )}
        </div>
      </form>

      {/* Diagnostics */}
      <div className="bg-white dark:bg-gray-800/40 rounded-xl border border-gray-200 dark:border-gray-700/50 p-5 space-y-4">
        <h2 className="text-sm font-semibold text-gray-500 dark:text-gray-300 uppercase tracking-wide">
          Diagnostics
        </h2>

        {/* Test ffmpeg */}
        <div className="space-y-2">
          <button
            onClick={() => void handleTestFfmpeg()}
            disabled={healthLoading}
            className="flex items-center gap-2 px-4 py-2 rounded-lg bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 disabled:opacity-40 text-gray-700 dark:text-gray-200 text-sm transition-colors"
          >
            {healthLoading ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : null}
            Tester ffmpeg
          </button>

          {health && (
            <div className="rounded-lg bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 p-3 text-sm space-y-1">
              <div className="flex items-center gap-2">
                {health.ffmpeg_available ? (
                  <CheckCircle className="w-4 h-4 text-green-400" />
                ) : (
                  <AlertCircle className="w-4 h-4 text-red-400" />
                )}
                <span className="text-gray-300">
                  ffmpeg :{' '}
                  {health.ffmpeg_available
                    ? `disponible (${health.ffmpeg_version})`
                    : 'introuvable'}
                </span>
              </div>
              <div className="text-gray-500">
                Device : <span className="text-gray-300">{health.device}</span>
              </div>
              <div className="text-gray-500">
                Version : <span className="text-gray-300">{health.version}</span>
              </div>
            </div>
          )}

          {healthError && (
            <div className="flex items-center gap-2 text-red-400 text-sm">
              <AlertCircle className="w-4 h-4" />
              {healthError}
            </div>
          )}
        </div>

        {/* Open data dir */}
        <button
          onClick={() => openDataDir()}
          className="flex items-center gap-2 px-4 py-2 rounded-lg bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-200 text-sm transition-colors"
        >
          <FolderOpen className="w-4 h-4" />
          Ouvrir le dossier de données
        </button>
      </div>
    </div>
  )
}
