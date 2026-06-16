interface ProgressBarProps {
  percent: number
  className?: string
}

export default function ProgressBar({ percent, className = '' }: ProgressBarProps) {
  const clamped = Math.min(100, Math.max(0, percent))

  return (
    <div className={`w-full rounded-full bg-gray-700 h-2 overflow-hidden ${className}`}>
      <div
        className="h-full bg-violet-500 transition-all duration-300 ease-out rounded-full"
        style={{ width: `${clamped}%` }}
      />
    </div>
  )
}
