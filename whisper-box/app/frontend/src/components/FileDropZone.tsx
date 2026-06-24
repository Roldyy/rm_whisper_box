import { useState, useRef, ChangeEvent } from 'react'
import { FileAudio, FolderOpen, Loader2 } from 'lucide-react'
import axios from 'axios'

interface FileDropZoneProps {
  value: string
  onChange: (path: string) => void
}

// Mirrors SUPPORTED_EXTENSIONS on the backend.
const ACCEPT = '.mp3,.mp4,.wav,.m4a,.ogg,.flac,.webm,.mkv,.avi,.mov,.aac'

export default function FileDropZone({ value, onChange }: FileDropZoneProps) {
  const [uploading, setUploading] = useState(false)
  const [progress, setProgress] = useState(0)
  const [error, setError] = useState<string | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  function openPicker() {
    inputRef.current?.click()
  }

  async function handleFileSelected(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    // Reset so picking the same file again still fires onChange.
    e.target.value = ''
    if (!file) return

    setError(null)
    setUploading(true)
    setProgress(0)
    try {
      const formData = new FormData()
      formData.append('file', file)
      // Use the bare axios instance (not apiClient) so the browser sets the
      // multipart Content-Type with its boundary; our shared client forces
      // application/json, which breaks multipart parsing.
      const { data } = await axios.post<{ path: string }>(
        `${window.location.origin}/api/upload`,
        formData,
        {
          onUploadProgress: (evt) => {
            if (evt.total) setProgress(Math.round((evt.loaded / evt.total) * 100))
          },
        },
      )
      if (data.path) onChange(data.path)
    } catch (err) {
      const msg = axios.isAxiosError(err)
        ? ((err.response?.data as { detail?: string } | undefined)?.detail ?? err.message)
        : 'Échec du téléversement du fichier.'
      setError(msg)
    } finally {
      setUploading(false)
    }
  }

  const displayName = value ? value.split('/').pop() ?? value : null
  const isAbsolute = value.startsWith('/')

  return (
    <div className="space-y-3">
      <input
        ref={inputRef}
        type="file"
        accept={ACCEPT}
        className="hidden"
        onChange={handleFileSelected}
      />

      {/* Browser-native file picker (instant) + upload */}
      <button
        type="button"
        onClick={openPicker}
        disabled={uploading}
        className={`relative w-full cursor-pointer rounded-xl border-2 border-dashed p-8 text-center transition-colors disabled:cursor-not-allowed ${
          isAbsolute
            ? 'border-violet-600/50 bg-gray-800/50'
            : 'border-gray-600 hover:border-gray-500 bg-gray-800/50'
        }`}
      >
        {uploading ? (
          <div className="flex flex-col items-center gap-2">
            <Loader2 className="w-8 h-8 text-violet-400 animate-spin" />
            <p className="text-sm text-gray-400">Téléversement… {progress}%</p>
          </div>
        ) : displayName ? (
          <div className="flex flex-col items-center gap-2">
            <FileAudio className={`w-8 h-8 ${isAbsolute ? 'text-violet-400' : 'text-amber-400'}`} />
            <span className={`text-sm font-medium break-all ${isAbsolute ? 'text-violet-300' : 'text-amber-300'}`}>
              {displayName}
            </span>
            <span className="text-xs text-gray-500">Cliquer pour changer de fichier</span>
          </div>
        ) : (
          <div className="flex flex-col items-center gap-2">
            <FolderOpen className="w-8 h-8 text-gray-500" />
            <p className="text-sm text-gray-400">
              Cliquer pour <span className="text-violet-400 underline">choisir un fichier</span>
            </p>
            <p className="text-xs text-gray-600">
              MP3 · MP4 · WAV · M4A · OGG · FLAC · WEBM · MKV · AVI · MOV · AAC
            </p>
          </div>
        )}
      </button>

      {error && <p className="text-xs text-red-400">{error}</p>}

      {/* Manual absolute path — for files already on disk */}
      <div>
        <label className="block text-xs text-gray-500 mb-1">
          Ou saisir un chemin absolu
        </label>
        <input
          type="text"
          placeholder="/Users/…/audio.mp3"
          value={value}
          onChange={(e: ChangeEvent<HTMLInputElement>) =>
            onChange(e.target.value.replace(/\\(.)/g, '$1'))
          }
          className="w-full rounded-lg bg-gray-800 border border-gray-700 px-3 py-2 text-sm text-gray-200 placeholder-gray-600 focus:outline-none focus:ring-1 focus:ring-violet-500 font-mono"
        />
      </div>
    </div>
  )
}
