import { useState, ChangeEvent } from 'react'
import { FileAudio, FolderOpen, Loader2 } from 'lucide-react'
import apiClient from '../api/client'

interface FileDropZoneProps {
  value: string
  onChange: (path: string) => void
}

export default function FileDropZone({ value, onChange }: FileDropZoneProps) {
  const [picking, setPicking] = useState(false)

  async function handleNativePick() {
    setPicking(true)
    try {
      const { data } = await apiClient.get<{ path: string | null }>('/api/pick-file')
      if (data.path) onChange(data.path)
    } catch {
      // user cancelled or backend doesn't support it yet
    } finally {
      setPicking(false)
    }
  }

  const displayName = value ? value.split('/').pop() ?? value : null
  const isAbsolute = value.startsWith('/')

  return (
    <div className="space-y-3">
      {/* Native macOS file picker */}
      <button
        type="button"
        onClick={handleNativePick}
        disabled={picking}
        className={`relative w-full cursor-pointer rounded-xl border-2 border-dashed p-8 text-center transition-colors disabled:cursor-not-allowed ${
          isAbsolute
            ? 'border-violet-600/50 bg-gray-800/50'
            : 'border-gray-600 hover:border-gray-500 bg-gray-800/50'
        }`}
      >
        {displayName ? (
          <div className="flex flex-col items-center gap-2">
            <FileAudio className={`w-8 h-8 ${isAbsolute ? 'text-violet-400' : 'text-amber-400'}`} />
            <span className={`text-sm font-medium break-all ${isAbsolute ? 'text-violet-300' : 'text-amber-300'}`}>
              {displayName}
            </span>
            <span className="text-xs text-gray-500">Cliquer pour changer de fichier</span>
          </div>
        ) : (
          <div className="flex flex-col items-center gap-2">
            {picking ? (
              <Loader2 className="w-8 h-8 text-violet-400 animate-spin" />
            ) : (
              <FolderOpen className="w-8 h-8 text-gray-500" />
            )}
            <p className="text-sm text-gray-400">
              {picking ? 'En attente de la sélection…' : (
                <>
                  Cliquer pour <span className="text-violet-400 underline">choisir un fichier</span>
                </>
              )}
            </p>
            <p className="text-xs text-gray-600">
              MP3 · MP4 · WAV · M4A · OGG · FLAC · WEBM · MKV · AVI · MOV · AAC
            </p>
          </div>
        )}
      </button>

      {/* Manual absolute path */}
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
