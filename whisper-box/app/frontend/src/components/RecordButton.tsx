import { Square, Mic } from 'lucide-react'

interface RecordButtonProps {
  isRecording: boolean
  elapsedSeconds: number
  onStart: () => void
  onStop: () => void
  disabled?: boolean
}

function formatElapsed(seconds: number): string {
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const s = Math.floor(seconds % 60)
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
}

export default function RecordButton({
  isRecording,
  elapsedSeconds,
  onStart,
  onStop,
  disabled = false,
}: RecordButtonProps) {
  if (isRecording) {
    return (
      <div className="flex items-center gap-4">
        {/* Pulsing indicator */}
        <div className="flex items-center gap-2">
          <span className="relative flex h-3 w-3">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75" />
            <span className="relative inline-flex rounded-full h-3 w-3 bg-red-500" />
          </span>
          <span className="text-sm font-mono font-medium text-red-500 dark:text-red-400 tabular-nums">
            {formatElapsed(elapsedSeconds)}
          </span>
        </div>

        {/* Stop button */}
        <button
          onClick={onStop}
          className="flex items-center gap-2 px-5 py-2.5 rounded-lg bg-red-600 hover:bg-red-500 text-white font-medium text-sm transition-colors"
        >
          <Square className="w-4 h-4" />
          Arrêter et transcrire
        </button>
      </div>
    )
  }

  return (
    <button
      onClick={onStart}
      disabled={disabled}
      className="flex items-center gap-2 px-5 py-2.5 rounded-lg bg-red-600 hover:bg-red-500 disabled:opacity-40 disabled:cursor-not-allowed text-white font-medium text-sm transition-colors"
    >
      <Mic className="w-4 h-4" />
      Commencer l'enregistrement
    </button>
  )
}
