import { useEffect, useRef } from 'react'

interface LogViewerProps {
  logs: string[]
  className?: string
}

export default function LogViewer({ logs, className = '' }: LogViewerProps) {
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [logs])

  return (
    <div
      className={`overflow-y-auto bg-gray-950 rounded-lg border border-gray-700 p-3 font-mono text-xs text-gray-300 ${className}`}
    >
      {logs.length === 0 ? (
        <span className="text-gray-600">En attente de logs…</span>
      ) : (
        logs.map((line, i) => (
          <div key={i} className="leading-5">
            {line}
          </div>
        ))
      )}
      <div ref={bottomRef} />
    </div>
  )
}
