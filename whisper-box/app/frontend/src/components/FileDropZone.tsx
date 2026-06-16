import { useRef, useState, DragEvent, ChangeEvent } from 'react'
import { Upload, FileAudio } from 'lucide-react'

const ACCEPT = '.mp3,.mp4,.wav,.m4a,.ogg,.flac,.webm,.mkv,.avi,.mov,.aac'

interface FileDropZoneProps {
  value: string
  onChange: (path: string) => void
}

export default function FileDropZone({ value, onChange }: FileDropZoneProps) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [dragOver, setDragOver] = useState(false)
  const [manualPath, setManualPath] = useState('')

  const handleDragOver = (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault()
    setDragOver(true)
  }

  const handleDragLeave = () => setDragOver(false)

  const handleDrop = (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault()
    setDragOver(false)
    const file = e.dataTransfer.files[0]
    if (file) {
      // In browser context we can get the name; the actual path is the
      // webkitRelativePath or we fall back to the name for display.
      // The backend expects an absolute path — so we store the full path
      // from the file object if available (Electron / Tauri), or the name.
      const path =
        (file as File & { path?: string }).path ?? file.name
      onChange(path)
      setManualPath('')
    }
  }

  const handleFileChange = (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      const path =
        (file as File & { path?: string }).path ?? file.name
      onChange(path)
      setManualPath('')
    }
  }

  const handleManualChange = (e: ChangeEvent<HTMLInputElement>) => {
    setManualPath(e.target.value)
    onChange(e.target.value)
  }

  const displayName = value
    ? value.split('/').pop() ?? value
    : null

  return (
    <div className="space-y-3">
      {/* Drop zone */}
      <div
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
        onClick={() => inputRef.current?.click()}
        className={`relative cursor-pointer rounded-xl border-2 border-dashed p-8 text-center transition-colors ${
          dragOver
            ? 'border-violet-400 bg-violet-500/10'
            : 'border-gray-600 hover:border-gray-500 bg-gray-800/50'
        }`}
      >
        <input
          ref={inputRef}
          type="file"
          accept={ACCEPT}
          className="hidden"
          onChange={handleFileChange}
        />

        {displayName ? (
          <div className="flex flex-col items-center gap-2">
            <FileAudio className="w-8 h-8 text-violet-400" />
            <span className="text-sm font-medium text-violet-300 break-all">
              {displayName}
            </span>
            <span className="text-xs text-gray-500">
              Cliquer ou glisser pour changer
            </span>
          </div>
        ) : (
          <div className="flex flex-col items-center gap-2">
            <Upload className="w-8 h-8 text-gray-500" />
            <p className="text-sm text-gray-400">
              Glisser un fichier ici ou{' '}
              <span className="text-violet-400 underline">parcourir</span>
            </p>
            <p className="text-xs text-gray-600">
              MP3 · MP4 · WAV · M4A · OGG · FLAC · WEBM · MKV · AVI · MOV · AAC
            </p>
          </div>
        )}
      </div>

      {/* Manual path input */}
      <div>
        <label className="block text-xs text-gray-500 mb-1">
          Ou saisir un chemin absolu
        </label>
        <input
          type="text"
          placeholder="/Users/…/audio.mp3"
          value={manualPath}
          onChange={handleManualChange}
          className="w-full rounded-lg bg-gray-800 border border-gray-700 px-3 py-2 text-sm text-gray-200 placeholder-gray-600 focus:outline-none focus:ring-1 focus:ring-violet-500 font-mono"
        />
      </div>
    </div>
  )
}
