import { useState } from 'react'
import { FolderOpen, RotateCcw, Trash2, Copy, CheckCheck, Sparkles, X } from 'lucide-react'
import { TranscriptionJob } from '../api/client'
import { useDeleteJob, useRerunJob, useOpenJobOutput } from '../api/jobs'
import { useEnhanceTranscript, EnhanceResult } from '../api/claude'
import StatusBadge from './StatusBadge'
import ConfirmDialog from './ConfirmDialog'

interface HistoryTableProps {
  jobs: TranscriptionJob[]
}

const CLAUDE_MODES = [
  { value: 'summary', label: 'Résumé' },
  { value: 'cleanup', label: 'Nettoyage' },
  { value: 'action-items', label: 'Actions' },
] as const

const CLAUDE_MODELS = ['claude-opus-4-8', 'claude-sonnet-4-6'] as const

function fmtDuration(sec: number | null): string {
  if (sec == null) return '—'
  if (sec < 60) return `${sec.toFixed(0)}s`
  return `${Math.floor(sec / 60)}m${Math.floor(sec % 60)}s`
}

function fmtDate(iso: string): string {
  return new Date(iso).toLocaleString('fr-BE', {
    dateStyle: 'short',
    timeStyle: 'short',
  })
}

export default function HistoryTable({ jobs }: HistoryTableProps) {
  const [confirmId, setConfirmId] = useState<number | null>(null)
  const [copiedPath, setCopiedPath] = useState<string | null>(null)

  // Enhance panel state per job
  const [enhanceJobId, setEnhanceJobId] = useState<number | null>(null)
  const [enhanceMode, setEnhanceMode] = useState<string>('summary')
  const [enhanceModel, setEnhanceModel] = useState<string>('claude-opus-4-8')
  const [enhanceResults, setEnhanceResults] = useState<Map<number, EnhanceResult>>(new Map())
  const [enhanceError, setEnhanceError] = useState<string | null>(null)

  const { mutate: deleteJob } = useDeleteJob()
  const { mutate: rerunJob } = useRerunJob()
  const { mutate: openOutput } = useOpenJobOutput()
  const { mutate: enhance, isPending: enhancing } = useEnhanceTranscript()

  function handleOpen(job: TranscriptionJob) {
    if (!job.output_path) return
    openOutput(job.id, {
      onError: () => {
        if (job.output_path) {
          void navigator.clipboard.writeText(job.output_path)
          setCopiedPath(job.output_path)
          setTimeout(() => setCopiedPath(null), 2000)
        }
      },
    })
  }

  function handleDelete(id: number) {
    deleteJob(id)
    setConfirmId(null)
  }

  function handleEnhanceOpen(job: TranscriptionJob) {
    setEnhanceError(null)
    setEnhanceJobId(enhanceJobId === job.id ? null : job.id)
  }

  function handleEnhanceRun() {
    if (!enhanceJobId) return
    setEnhanceError(null)
    enhance(
      { jobId: enhanceJobId, mode: enhanceMode, model: enhanceModel },
      {
        onSuccess: (result) => {
          setEnhanceResults((prev) => new Map(prev).set(enhanceJobId, result))
        },
        onError: (e: unknown) => {
          const msg = e instanceof Error ? e.message : 'Erreur inconnue'
          setEnhanceError(msg)
        },
      },
    )
  }

  const selectCls =
    'rounded-lg bg-gray-100 dark:bg-gray-700 border border-gray-300 dark:border-gray-600 px-2 py-1 text-xs text-gray-800 dark:text-gray-200 focus:outline-none focus:ring-1 focus:ring-violet-500'

  if (jobs.length === 0) {
    return (
      <div className="text-center py-16 text-gray-600 text-sm">
        Aucune transcription dans l'historique.
      </div>
    )
  }

  return (
    <>
      {confirmId != null && (
        <ConfirmDialog
          message="Supprimer ce job de l'historique ? Le fichier de sortie ne sera pas supprimé."
          onConfirm={() => handleDelete(confirmId)}
          onCancel={() => setConfirmId(null)}
        />
      )}

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-xs text-gray-500 border-b border-gray-700">
              <th className="pb-2 pr-4 font-medium">Fichier</th>
              <th className="pb-2 pr-4 font-medium">Modèle</th>
              <th className="pb-2 pr-4 font-medium">Langue</th>
              <th className="pb-2 pr-4 font-medium">Format</th>
              <th className="pb-2 pr-4 font-medium">Durée</th>
              <th className="pb-2 pr-4 font-medium">Device</th>
              <th className="pb-2 pr-4 font-medium">Statut</th>
              <th className="pb-2 pr-4 font-medium">Date</th>
              <th className="pb-2 font-medium">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-800">
            {jobs.map((job) => (
              <>
                <tr key={job.id} className="hover:bg-gray-800/30 transition-colors">
                  <td className="py-2.5 pr-4 max-w-xs">
                    <span
                      className="block truncate text-gray-200 font-medium"
                      title={job.source_filename}
                    >
                      {job.source_filename}
                    </span>
                    {job.error_message && (
                      <span
                        className="block truncate text-xs text-red-400 mt-0.5"
                        title={job.error_message}
                      >
                        {job.error_message}
                      </span>
                    )}
                  </td>
                  <td
                    className="py-2.5 pr-4 text-gray-400"
                    title={`task: ${job.task ?? 'transcribe'} | temp: ${job.temperature ?? 0} | timestamps: ${job.word_timestamps ? 'oui' : 'non'}`}
                  >
                    {job.model}
                  </td>
                  <td className="py-2.5 pr-4 text-gray-400">{job.language ?? 'auto'}</td>
                  <td className="py-2.5 pr-4 text-gray-400 uppercase">{job.output_format}</td>
                  <td className="py-2.5 pr-4 text-gray-400 tabular-nums">
                    {fmtDuration(job.duration_audio)}
                  </td>
                  <td className="py-2.5 pr-4 text-gray-400">{job.device_used ?? '—'}</td>
                  <td className="py-2.5 pr-4">
                    <StatusBadge status={job.status} />
                  </td>
                  <td className="py-2.5 pr-4 text-gray-500 tabular-nums whitespace-nowrap">
                    {fmtDate(job.created_at)}
                  </td>
                  <td className="py-2.5">
                    <div className="flex items-center gap-2">
                      {/* Open file */}
                      {job.output_path && (
                        <button
                          onClick={() => handleOpen(job)}
                          title={
                            copiedPath === job.output_path
                              ? 'Chemin copié !'
                              : 'Ouvrir le fichier'
                          }
                          className="text-gray-400 hover:text-violet-300 transition-colors"
                        >
                          {copiedPath === job.output_path ? (
                            <CheckCheck className="w-4 h-4 text-green-400" />
                          ) : (
                            <FolderOpen className="w-4 h-4" />
                          )}
                        </button>
                      )}

                      {/* Copy path */}
                      {job.output_path && (
                        <button
                          onClick={() => {
                            if (job.output_path) {
                              void navigator.clipboard.writeText(job.output_path)
                              setCopiedPath(job.output_path)
                              setTimeout(() => setCopiedPath(null), 2000)
                            }
                          }}
                          title="Copier le chemin"
                          className="text-gray-400 hover:text-gray-200 transition-colors"
                        >
                          <Copy className="w-4 h-4" />
                        </button>
                      )}

                      {/* Enhance with Claude */}
                      {job.status === 'success' && job.output_path && (
                        <button
                          onClick={() => handleEnhanceOpen(job)}
                          title="Améliorer avec Claude"
                          className={`transition-colors ${
                            enhanceJobId === job.id
                              ? 'text-violet-400'
                              : 'text-gray-400 hover:text-violet-400'
                          }`}
                        >
                          <Sparkles className="w-4 h-4" />
                        </button>
                      )}

                      {/* Rerun */}
                      <button
                        onClick={() => rerunJob(job.id)}
                        title="Relancer"
                        className="text-gray-400 hover:text-blue-300 transition-colors"
                      >
                        <RotateCcw className="w-4 h-4" />
                      </button>

                      {/* Delete */}
                      <button
                        onClick={() => setConfirmId(job.id)}
                        title="Supprimer"
                        className="text-gray-400 hover:text-red-400 transition-colors"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </td>
                </tr>

                {/* Enhance panel */}
                {enhanceJobId === job.id && (
                  <tr key={`enhance-${job.id}`}>
                    <td colSpan={9} className="px-0 pb-3">
                      <div className="mx-0 rounded-lg bg-gray-900/60 border border-violet-700/40 p-4 space-y-3">
                        <div className="flex items-center justify-between">
                          <p className="text-xs font-semibold text-violet-300 uppercase tracking-wide">
                            Améliorer avec Claude
                          </p>
                          <button
                            onClick={() => {
                              setEnhanceJobId(null)
                              setEnhanceError(null)
                            }}
                            className="text-gray-500 hover:text-gray-300"
                          >
                            <X className="w-4 h-4" />
                          </button>
                        </div>

                        <div className="flex flex-wrap gap-3 items-end">
                          <div>
                            <label className="block text-xs text-gray-500 mb-1">Mode</label>
                            <select
                              className={selectCls}
                              value={enhanceMode}
                              onChange={(e) => setEnhanceMode(e.target.value)}
                            >
                              {CLAUDE_MODES.map(({ value, label }) => (
                                <option key={value} value={value}>
                                  {label}
                                </option>
                              ))}
                            </select>
                          </div>
                          <div>
                            <label className="block text-xs text-gray-500 mb-1">Modèle</label>
                            <select
                              className={selectCls}
                              value={enhanceModel}
                              onChange={(e) => setEnhanceModel(e.target.value)}
                            >
                              {CLAUDE_MODELS.map((m) => (
                                <option key={m} value={m}>
                                  {m}
                                </option>
                              ))}
                            </select>
                          </div>
                          <button
                            onClick={handleEnhanceRun}
                            disabled={enhancing}
                            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-violet-600 hover:bg-violet-500 disabled:opacity-50 text-white text-xs font-medium transition-colors"
                          >
                            {enhancing ? (
                              <>
                                <span className="inline-block w-3 h-3 border-2 border-white/40 border-t-white rounded-full animate-spin" />
                                En cours…
                              </>
                            ) : (
                              <>
                                <Sparkles className="w-3 h-3" />
                                Lancer
                              </>
                            )}
                          </button>
                        </div>

                        {enhanceError && (
                          <p className="text-xs text-red-400">{enhanceError}</p>
                        )}

                        {enhanceResults.has(job.id) && (
                          <div className="space-y-2">
                            <div className="flex items-center justify-between">
                              <p className="text-xs text-green-400">
                                Fichier : {enhanceResults.get(job.id)!.summary_path}
                              </p>
                              <button
                                onClick={() => {
                                  const r = enhanceResults.get(job.id)
                                  if (r) void navigator.clipboard.writeText(r.content)
                                }}
                                title="Copier le contenu"
                                className="text-gray-500 hover:text-gray-300"
                              >
                                <Copy className="w-3.5 h-3.5" />
                              </button>
                            </div>
                            <pre className="text-xs text-gray-300 bg-gray-950 rounded p-3 overflow-auto max-h-48 whitespace-pre-wrap">
                              {enhanceResults.get(job.id)!.content}
                            </pre>
                          </div>
                        )}
                      </div>
                    </td>
                  </tr>
                )}
              </>
            ))}
          </tbody>
        </table>
      </div>
    </>
  )
}
