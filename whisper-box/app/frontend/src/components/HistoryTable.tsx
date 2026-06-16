import { useState } from 'react'
import { FolderOpen, RotateCcw, Trash2, Copy, CheckCheck } from 'lucide-react'
import { TranscriptionJob } from '../api/client'
import { useDeleteJob, useRerunJob, useOpenJobOutput } from '../api/jobs'
import StatusBadge from './StatusBadge'
import ConfirmDialog from './ConfirmDialog'

interface HistoryTableProps {
  jobs: TranscriptionJob[]
}

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

  const { mutate: deleteJob } = useDeleteJob()
  const { mutate: rerunJob } = useRerunJob()
  const { mutate: openOutput } = useOpenJobOutput()

  function handleOpen(job: TranscriptionJob) {
    if (!job.output_path) return
    openOutput(job.id, {
      onError: () => {
        // Fallback: copy path to clipboard
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
                  title={`task: ${job.task ?? 'transcribe'} | temp: ${job.temperature ?? 0} | beam: ${job.beam_size ?? 5} | timestamps: ${job.word_timestamps ? 'oui' : 'non'}`}
                >
                  {job.model}
                </td>
                <td className="py-2.5 pr-4 text-gray-400">
                  {job.language ?? 'auto'}
                </td>
                <td className="py-2.5 pr-4 text-gray-400 uppercase">
                  {job.output_format}
                </td>
                <td className="py-2.5 pr-4 text-gray-400 tabular-nums">
                  {fmtDuration(job.duration_audio)}
                </td>
                <td className="py-2.5 pr-4 text-gray-400">
                  {job.device_used ?? '—'}
                </td>
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
            ))}
          </tbody>
        </table>
      </div>
    </>
  )
}
