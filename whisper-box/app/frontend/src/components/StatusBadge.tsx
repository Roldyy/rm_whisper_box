import { TranscriptionJob } from '../api/client'

type Status = TranscriptionJob['status']

const CONFIG: Record<
  Status,
  { label: string; className: string }
> = {
  pending: {
    label: 'En attente',
    className: 'bg-gray-700 text-gray-300',
  },
  running: {
    label: 'En cours',
    className: 'bg-blue-500/20 text-blue-300 animate-pulse',
  },
  success: {
    label: 'Succès',
    className: 'bg-green-500/20 text-green-300',
  },
  error: {
    label: 'Erreur',
    className: 'bg-red-500/20 text-red-300',
  },
  cancelled: {
    label: 'Annulé',
    className: 'bg-orange-500/20 text-orange-300',
  },
}

interface StatusBadgeProps {
  status: Status
}

export default function StatusBadge({ status }: StatusBadgeProps) {
  const { label, className } = CONFIG[status] ?? CONFIG.pending
  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${className}`}
    >
      {label}
    </span>
  )
}
