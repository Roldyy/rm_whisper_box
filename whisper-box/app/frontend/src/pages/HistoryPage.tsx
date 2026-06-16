import { useState, useCallback, ChangeEvent } from 'react'
import { Search, RefreshCw } from 'lucide-react'
import { useJobs } from '../api/jobs'
import HistoryTable from '../components/HistoryTable'

const STATUS_OPTIONS = [
  { value: '', label: 'Tous les statuts' },
  { value: 'pending', label: 'En attente' },
  { value: 'running', label: 'En cours' },
  { value: 'success', label: 'Succès' },
  { value: 'error', label: 'Erreur' },
  { value: 'cancelled', label: 'Annulé' },
]

export default function HistoryPage() {
  const [search, setSearch] = useState('')
  const [debouncedSearch, setDebouncedSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [debounceTimer, setDebounceTimer] = useState<ReturnType<typeof setTimeout> | null>(null)

  const { data: jobs = [], isLoading, refetch } = useJobs({
    search: debouncedSearch || undefined,
    status: statusFilter || undefined,
    limit: 50,
  })

  const handleSearchChange = useCallback(
    (e: ChangeEvent<HTMLInputElement>) => {
      const val = e.target.value
      setSearch(val)
      if (debounceTimer) clearTimeout(debounceTimer)
      const t = setTimeout(() => setDebouncedSearch(val), 300)
      setDebounceTimer(t)
    },
    [debounceTimer],
  )

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4 flex-wrap">
        <h1 className="text-xl font-semibold text-gray-900 dark:text-white">Historique</h1>

        <div className="flex items-center gap-3">
          {/* Search */}
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
            <input
              type="text"
              placeholder="Rechercher un fichier…"
              value={search}
              onChange={handleSearchChange}
              className="pl-9 pr-3 py-2 text-sm rounded-lg bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-700 text-gray-900 dark:text-gray-200 placeholder-gray-400 dark:placeholder-gray-600 focus:outline-none focus:ring-1 focus:ring-violet-500 w-52"
            />
          </div>

          {/* Status filter */}
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

          {/* Refresh */}
          <button
            onClick={() => void refetch()}
            title="Rafraîchir"
            className="p-2 rounded-lg bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-700 text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200 transition-colors"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
        </div>
      </div>

      {isLoading ? (
        <div className="text-center py-16 text-gray-400 dark:text-gray-500 text-sm">
          Chargement…
        </div>
      ) : (
        <div className="bg-white dark:bg-gray-800/40 rounded-xl border border-gray-200 dark:border-gray-700/50 p-4">
          <HistoryTable jobs={jobs} />
        </div>
      )}
    </div>
  )
}
