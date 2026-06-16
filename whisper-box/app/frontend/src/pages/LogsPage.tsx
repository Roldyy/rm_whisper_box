import { useState, ChangeEvent } from 'react'
import { ChevronDown, ChevronRight, Trash2 } from 'lucide-react'
import { useLogs, useLog, useDeleteLog } from '../api/logs'
import { ExecutionLog } from '../api/client'
import ConfirmDialog from '../components/ConfirmDialog'

const STATUS_OPTIONS = [
  { value: '', label: 'Tous' },
  { value: 'running', label: 'En cours' },
  { value: 'success', label: 'Succès' },
  { value: 'error', label: 'Erreur' },
]

function LogRow({ log, onDelete }: { log: ExecutionLog; onDelete: (id: number) => void }) {
  const [expanded, setExpanded] = useState(false)
  const { data: fullLog, refetch } = useLog(log.id)

  function handleToggle() {
    if (!expanded) {
      void refetch()
    }
    setExpanded((v) => !v)
  }

  const statusColor: Record<string, string> = {
    running: 'text-blue-400',
    success: 'text-green-400',
    error: 'text-red-400',
  }

  return (
    <>
      <tr
        className="hover:bg-gray-100 dark:hover:bg-gray-800/30 cursor-pointer transition-colors"
        onClick={handleToggle}
      >
        <td className="py-2.5 pr-4 w-6">
          {expanded ? (
            <ChevronDown className="w-4 h-4 text-gray-500" />
          ) : (
            <ChevronRight className="w-4 h-4 text-gray-500" />
          )}
        </td>
        <td className="py-2.5 pr-4 text-gray-400 tabular-nums">{log.id}</td>
        <td className="py-2.5 pr-4 text-gray-400 tabular-nums">
          {log.job_id ?? '—'}
        </td>
        <td className="py-2.5 pr-4 text-gray-300">{log.operation_type}</td>
        <td className="py-2.5 pr-4">
          <span className={`text-sm font-medium ${statusColor[log.status] ?? 'text-gray-400'}`}>
            {log.status}
          </span>
        </td>
        <td className="py-2.5 pr-4 text-gray-500 text-sm tabular-nums whitespace-nowrap">
          {new Date(log.created_at).toLocaleString('fr-BE', {
            dateStyle: 'short',
            timeStyle: 'short',
          })}
        </td>
        <td className="py-2.5">
          <button
            onClick={(e) => {
              e.stopPropagation()
              onDelete(log.id)
            }}
            title="Supprimer"
            className="text-gray-500 hover:text-red-400 transition-colors"
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </td>
      </tr>
      {expanded && (
        <tr>
          <td colSpan={7} className="pb-3">
            <div className="mx-6 rounded-lg bg-gray-50 dark:bg-gray-950 border border-gray-200 dark:border-gray-700 p-3 font-mono text-xs text-gray-700 dark:text-gray-300 max-h-64 overflow-y-auto whitespace-pre-wrap">
              {fullLog?.log_content ?? 'Chargement…'}
            </div>
          </td>
        </tr>
      )}
    </>
  )
}

export default function LogsPage() {
  const [statusFilter, setStatusFilter] = useState('')
  const [confirmId, setConfirmId] = useState<number | null>(null)

  const { data: logs = [], isLoading } = useLogs({
    status: statusFilter || undefined,
    limit: 50,
  })

  const { mutate: deleteLog } = useDeleteLog()

  function handleDelete(id: number) {
    deleteLog(id)
    setConfirmId(null)
  }

  return (
    <div className="space-y-4">
      {confirmId != null && (
        <ConfirmDialog
          message="Supprimer ce log ?"
          onConfirm={() => handleDelete(confirmId)}
          onCancel={() => setConfirmId(null)}
        />
      )}

      <div className="flex items-center justify-between gap-4">
        <h1 className="text-xl font-semibold text-gray-900 dark:text-white">Logs</h1>

        <select
          value={statusFilter}
          onChange={(e: ChangeEvent<HTMLSelectElement>) =>
            setStatusFilter(e.target.value)
          }
          className="py-2 px-3 text-sm rounded-lg bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-700 text-gray-900 dark:text-gray-200 focus:outline-none focus:ring-1 focus:ring-violet-500"
        >
          {STATUS_OPTIONS.map(({ value, label }) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </div>

      {isLoading ? (
        <div className="text-center py-16 text-gray-400 dark:text-gray-500 text-sm">Chargement…</div>
      ) : logs.length === 0 ? (
        <div className="text-center py-16 text-gray-400 dark:text-gray-600 text-sm">
          Aucun log disponible.
        </div>
      ) : (
        <div className="bg-white dark:bg-gray-800/40 rounded-xl border border-gray-200 dark:border-gray-700/50 p-4 overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-gray-400 dark:text-gray-500 border-b border-gray-200 dark:border-gray-700">
                <th className="pb-2 w-6" />
                <th className="pb-2 pr-4 font-medium">#</th>
                <th className="pb-2 pr-4 font-medium">Job</th>
                <th className="pb-2 pr-4 font-medium">Opération</th>
                <th className="pb-2 pr-4 font-medium">Statut</th>
                <th className="pb-2 pr-4 font-medium">Date</th>
                <th className="pb-2 font-medium" />
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100 dark:divide-gray-800">
              {logs.map((log) => (
                <LogRow
                  key={log.id}
                  log={log}
                  onDelete={(id) => setConfirmId(id)}
                />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
