interface ProgressBarProps {
  percent: number
  /** Show a sweeping animation instead of a fixed width — use when the engine
   *  is working but hasn't reported real incremental progress yet. */
  indeterminate?: boolean
  className?: string
}

export default function ProgressBar({ percent, indeterminate = false, className = '' }: ProgressBarProps) {
  const clamped = Math.min(100, Math.max(0, percent))

  return (
    <div className={`relative w-full rounded-full bg-gray-700 h-2 overflow-hidden ${className}`}>
      {indeterminate ? (
        <div className="wb-indeterminate-bar bg-violet-500 rounded-full" />
      ) : (
        <div
          className="h-full bg-violet-500 transition-all duration-300 ease-out rounded-full"
          style={{ width: `${clamped}%` }}
        />
      )}
    </div>
  )
}
