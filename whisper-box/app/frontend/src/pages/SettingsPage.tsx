import { useState, useEffect, ChangeEvent, FormEvent } from 'react'
import { Loader2, CheckCircle, AlertCircle, FolderOpen, Trash2 } from 'lucide-react'
import { useSettings, useUpdateSettings, useOpenDataDir } from '../api/settings'
import {
  useClaudeStatus,
  useSaveToken,
  useDeleteToken,
  useVerifyToken,
} from '../api/claude'
import apiClient, { HealthResponse, Settings } from '../api/client'
import { useAppStore } from '../stores/appStore'
import { useQueryClient } from '@tanstack/react-query'
import { claudeKeys } from '../api/claude'

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
const CLAUDE_MODELS = ['claude-opus-4-8', 'claude-sonnet-4-6'] as const
const CLAUDE_MODES = [
  { value: 'summary', label: 'Résumé' },
  { value: 'cleanup', label: 'Nettoyage' },
  { value: 'action-items', label: 'Actions à réaliser' },
] as const

export default function SettingsPage() {
  const { data: settings, isLoading } = useSettings()
  const { mutate: updateSettings, isPending: isSaving } = useUpdateSettings()
  const { mutate: openDataDir } = useOpenDataDir()
  const setStoreSettings = useAppStore((s) => s.setSettings)
  const qc = useQueryClient()

  // ── Whisper form ───────────────────────────────────────────────────────
  const [form, setForm] = useState<Settings>({
    default_model: 'large-v3-turbo',
    default_language: '',
    default_output_format: 'txt',
    default_output_dir: '',
  })
  const [saved, setSaved] = useState(false)

  // ── Diagnostics ────────────────────────────────────────────────────────
  const [health, setHealth] = useState<HealthResponse | null>(null)
  const [healthLoading, setHealthLoading] = useState(false)
  const [healthError, setHealthError] = useState<string | null>(null)

  // ── Claude settings ────────────────────────────────────────────────────
  const [claudeEnabled, setClaudeEnabled] = useState(false)
  const [claudeModel, setClaudeModel] = useState<string>('claude-opus-4-8')
  const [claudeMode, setClaudeMode] = useState<string>('summary')
  const [claudeAuto, setClaudeAuto] = useState(false)
  const [claudeSaved, setClaudeSaved] = useState(false)

  // ── Token UI ───────────────────────────────────────────────────────────
  const [tokenInput, setTokenInput] = useState('')
  const [tokenMsg, setTokenMsg] = useState<{ ok: boolean; text: string } | null>(null)

  const { data: claudeStatus, isLoading: statusLoading } = useClaudeStatus()
  const { mutate: saveToken, isPending: savingToken } = useSaveToken()
  const { mutate: deleteToken, isPending: deletingToken } = useDeleteToken()
  const { mutate: verifyToken, isPending: verifying } = useVerifyToken()
  const [verifyResult, setVerifyResult] = useState<{ ok: boolean; text: string } | null>(null)

  // ── Sync from server ───────────────────────────────────────────────────
  useEffect(() => {
    if (!settings) return
    setForm({
      default_model: settings.default_model ?? 'large-v3-turbo',
      default_language: settings.default_language ?? '',
      default_output_format: settings.default_output_format ?? 'txt',
      default_output_dir: settings.default_output_dir ?? '',
    })
    setClaudeEnabled(settings.claude_enabled === 'true')
    setClaudeModel(settings.claude_model ?? 'claude-opus-4-8')
    setClaudeMode(settings.claude_default_mode ?? 'summary')
    setClaudeAuto(settings.claude_auto_after_transcribe === 'true')
  }, [settings])

  // ── Whisper handlers ───────────────────────────────────────────────────
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

  // ── Diagnostics handler ────────────────────────────────────────────────
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

  // ── Claude handlers ────────────────────────────────────────────────────
  function handleSaveClaudeSettings() {
    updateSettings(
      {
        claude_enabled: claudeEnabled ? 'true' : 'false',
        claude_model: claudeModel,
        claude_default_mode: claudeMode,
        claude_auto_after_transcribe: claudeAuto ? 'true' : 'false',
      },
      {
        onSuccess: (updated) => {
          setStoreSettings(updated as unknown as Record<string, string>)
          setClaudeSaved(true)
          setTimeout(() => setClaudeSaved(false), 2000)
        },
      },
    )
  }

  function handleSaveToken() {
    if (!tokenInput.trim()) return
    saveToken(tokenInput.trim(), {
      onSuccess: () => {
        setTokenInput('')
        setTokenMsg({ ok: true, text: 'Token enregistré dans le Keychain.' })
        void qc.invalidateQueries({ queryKey: claudeKeys.status })
        setTimeout(() => setTokenMsg(null), 4000)
      },
      onError: (e: unknown) => {
        const msg = e instanceof Error ? e.message : 'Erreur inconnue'
        setTokenMsg({ ok: false, text: msg })
      },
    })
  }

  function handleDeleteToken() {
    deleteToken(undefined, {
      onSuccess: () => {
        setTokenMsg({ ok: true, text: 'Token supprimé.' })
        void qc.invalidateQueries({ queryKey: claudeKeys.status })
        setTimeout(() => setTokenMsg(null), 3000)
      },
    })
  }

  function handleVerify() {
    setVerifyResult(null)
    verifyToken(undefined, {
      onSuccess: (res) => {
        setVerifyResult({ ok: true, text: `Connexion OK — réponse : ${res.response ?? '…'}` })
      },
      onError: (e: unknown) => {
        const msg = e instanceof Error ? e.message : 'Erreur inconnue'
        setVerifyResult({ ok: false, text: msg })
      },
    })
  }

  const inputCls =
    'w-full rounded-lg bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-700 px-3 py-2 text-sm text-gray-900 dark:text-gray-200 focus:outline-none focus:ring-1 focus:ring-violet-500'

  if (isLoading) {
    return (
      <div className="text-center py-16 text-gray-500 text-sm">Chargement…</div>
    )
  }

  return (
    <div className="max-w-lg space-y-6">
      <h1 className="text-xl font-semibold text-gray-900 dark:text-white">Paramètres</h1>

      {/* ── Whisper settings ──────────────────────────────────────────────── */}
      <form
        onSubmit={handleSubmit}
        className="bg-white dark:bg-gray-800/40 rounded-xl border border-gray-200 dark:border-gray-700/50 p-5 space-y-4"
      >
        <h2 className="text-sm font-semibold text-gray-500 dark:text-gray-300 uppercase tracking-wide">
          Valeurs par défaut
        </h2>

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

        <div>
          <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">
            Dossier de sortie par défaut{' '}
            <span className="text-gray-600">(vide = ~/Whisper Memory/transcripts/)</span>
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
            {isSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
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

      {/* ── Claude (IA) ───────────────────────────────────────────────────── */}
      <div className="bg-white dark:bg-gray-800/40 rounded-xl border border-gray-200 dark:border-gray-700/50 p-5 space-y-4">
        <h2 className="text-sm font-semibold text-gray-500 dark:text-gray-300 uppercase tracking-wide">
          Claude (IA)
        </h2>

        {/* Enable toggle */}
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-gray-800 dark:text-gray-200">Activer Claude</p>
            <p className="text-xs text-gray-500 dark:text-gray-500 mt-0.5">
              Nécessite le CLI Claude Code installé et un token OAuth actif.
            </p>
          </div>
          <button
            type="button"
            onClick={() => setClaudeEnabled((v) => !v)}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors focus:outline-none ${
              claudeEnabled ? 'bg-violet-600' : 'bg-gray-300 dark:bg-gray-600'
            }`}
          >
            <span
              className={`inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${
                claudeEnabled ? 'translate-x-6' : 'translate-x-1'
              }`}
            />
          </button>
        </div>

        {claudeEnabled && (
          <>
            {/* CLI status */}
            <div className="rounded-lg bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 p-3 text-sm space-y-1">
              {statusLoading ? (
                <div className="flex items-center gap-2 text-gray-400">
                  <Loader2 className="w-4 h-4 animate-spin" />
                  Vérification…
                </div>
              ) : claudeStatus ? (
                <>
                  <div className="flex items-center gap-2">
                    {claudeStatus.available ? (
                      <CheckCircle className="w-4 h-4 text-green-400 shrink-0" />
                    ) : (
                      <AlertCircle className="w-4 h-4 text-red-400 shrink-0" />
                    )}
                    <span className="text-gray-300">
                      CLI :{' '}
                      {claudeStatus.available
                        ? `disponible (${claudeStatus.version || '—'})`
                        : 'introuvable'}
                    </span>
                  </div>
                  <div className="flex items-center gap-2">
                    {claudeStatus.token_present ? (
                      <CheckCircle className="w-4 h-4 text-green-400 shrink-0" />
                    ) : (
                      <AlertCircle className="w-4 h-4 text-amber-400 shrink-0" />
                    )}
                    <span className="text-gray-300">
                      Token : {claudeStatus.token_present ? 'présent' : 'absent'}
                    </span>
                  </div>
                  {claudeStatus.api_key_conflict && (
                    <div className="flex items-center gap-2 text-amber-400">
                      <AlertCircle className="w-4 h-4 shrink-0" />
                      ANTHROPIC_API_KEY détectée — sera retirée du sous-processus.
                    </div>
                  )}
                  {claudeStatus.error && (
                    <div className="text-red-400 text-xs mt-1">{claudeStatus.error}</div>
                  )}
                </>
              ) : null}
            </div>

            {/* Token input */}
            <div className="space-y-2">
              <label className="block text-xs text-gray-500 dark:text-gray-400">
                Token OAuth Claude
              </label>
              <p className="text-xs text-gray-500 dark:text-gray-500">
                Exécutez{' '}
                <code className="bg-gray-200 dark:bg-gray-700 rounded px-1">
                  claude setup-token
                </code>{' '}
                dans le Terminal, puis collez le token ici.
              </p>
              <div className="flex gap-2">
                <input
                  type="password"
                  value={tokenInput}
                  onChange={(e: ChangeEvent<HTMLInputElement>) =>
                    setTokenInput(e.target.value)
                  }
                  placeholder="sk-ant-oat01-…"
                  className={`${inputCls} font-mono`}
                />
                <button
                  type="button"
                  onClick={handleSaveToken}
                  disabled={savingToken || !tokenInput.trim()}
                  className="shrink-0 flex items-center gap-1 px-3 py-2 rounded-lg bg-violet-600 hover:bg-violet-500 disabled:opacity-40 text-white text-sm transition-colors"
                >
                  {savingToken ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
                  Enregistrer
                </button>
                {claudeStatus?.token_present && (
                  <button
                    type="button"
                    onClick={handleDeleteToken}
                    disabled={deletingToken}
                    title="Supprimer le token"
                    className="shrink-0 flex items-center gap-1 px-3 py-2 rounded-lg bg-red-900/40 hover:bg-red-800/50 disabled:opacity-40 text-red-400 text-sm transition-colors"
                  >
                    {deletingToken ? (
                      <Loader2 className="w-4 h-4 animate-spin" />
                    ) : (
                      <Trash2 className="w-4 h-4" />
                    )}
                  </button>
                )}
              </div>
              {tokenMsg && (
                <div
                  className={`flex items-center gap-2 text-sm ${
                    tokenMsg.ok ? 'text-green-400' : 'text-red-400'
                  }`}
                >
                  {tokenMsg.ok ? (
                    <CheckCircle className="w-4 h-4 shrink-0" />
                  ) : (
                    <AlertCircle className="w-4 h-4 shrink-0" />
                  )}
                  {tokenMsg.text}
                </div>
              )}
            </div>

            {/* Model */}
            <div>
              <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">
                Modèle Claude
              </label>
              <select
                className={inputCls}
                value={claudeModel}
                onChange={(e: ChangeEvent<HTMLSelectElement>) =>
                  setClaudeModel(e.target.value)
                }
              >
                {CLAUDE_MODELS.map((m) => (
                  <option key={m} value={m}>
                    {m}
                  </option>
                ))}
              </select>
            </div>

            {/* Default mode */}
            <div>
              <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">
                Mode par défaut
              </label>
              <select
                className={inputCls}
                value={claudeMode}
                onChange={(e: ChangeEvent<HTMLSelectElement>) =>
                  setClaudeMode(e.target.value)
                }
              >
                {CLAUDE_MODES.map(({ value, label }) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </div>

            {/* Auto after transcription */}
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-800 dark:text-gray-200">
                  Lancer automatiquement après transcription
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-500 mt-0.5">
                  Génère le fichier .md dès que la transcription est terminée.
                </p>
              </div>
              <button
                type="button"
                onClick={() => setClaudeAuto((v) => !v)}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors focus:outline-none ${
                  claudeAuto ? 'bg-violet-600' : 'bg-gray-300 dark:bg-gray-600'
                }`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${
                    claudeAuto ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>

            {/* Save Claude settings + Verify */}
            <div className="flex flex-wrap items-center gap-3 pt-1">
              <button
                type="button"
                onClick={handleSaveClaudeSettings}
                disabled={isSaving}
                className="flex items-center gap-2 px-4 py-2 rounded-lg bg-violet-600 hover:bg-violet-500 disabled:opacity-40 text-white text-sm font-medium transition-colors"
              >
                {isSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
                Enregistrer
              </button>

              <button
                type="button"
                onClick={handleVerify}
                disabled={verifying || !claudeStatus?.token_present}
                className="flex items-center gap-2 px-4 py-2 rounded-lg bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 disabled:opacity-40 text-gray-700 dark:text-gray-200 text-sm transition-colors"
              >
                {verifying ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
                Vérifier la connexion
              </button>

              {claudeSaved && (
                <div className="flex items-center gap-1 text-green-400 text-sm">
                  <CheckCircle className="w-4 h-4" />
                  Sauvegardé
                </div>
              )}
            </div>

            {verifyResult && (
              <div
                className={`flex items-start gap-2 text-sm rounded-lg p-3 ${
                  verifyResult.ok
                    ? 'bg-green-900/20 text-green-300'
                    : 'bg-red-900/20 text-red-400'
                }`}
              >
                {verifyResult.ok ? (
                  <CheckCircle className="w-4 h-4 shrink-0 mt-0.5" />
                ) : (
                  <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
                )}
                <span className="break-all">{verifyResult.text}</span>
              </div>
            )}
          </>
        )}
      </div>

      {/* ── Diagnostics ───────────────────────────────────────────────────── */}
      <div className="bg-white dark:bg-gray-800/40 rounded-xl border border-gray-200 dark:border-gray-700/50 p-5 space-y-4">
        <h2 className="text-sm font-semibold text-gray-500 dark:text-gray-300 uppercase tracking-wide">
          Diagnostics
        </h2>

        <div className="space-y-2">
          <button
            onClick={() => void handleTestFfmpeg()}
            disabled={healthLoading}
            className="flex items-center gap-2 px-4 py-2 rounded-lg bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 disabled:opacity-40 text-gray-700 dark:text-gray-200 text-sm transition-colors"
          >
            {healthLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
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
