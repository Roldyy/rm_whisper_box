import { ChangeEvent, useState } from 'react'
import { Loader2, PlayCircle, ChevronDown, ChevronRight } from 'lucide-react'
import { useWhisperModels } from '../api/jobs'
import { WhisperModelInfo } from '../api/client'

const MULTILINGUAL_MODELS = [
  'tiny', 'base', 'small', 'medium', 'large', 'large-v2', 'large-v3', 'large-v3-turbo',
]

const LANGUAGES: { value: string; label: string }[] = [
  { value: '', label: 'Auto-détection' },
  { value: 'fr', label: 'Français' },
  { value: 'en', label: 'Anglais' },
  { value: 'nl', label: 'Néerlandais' },
  { value: 'de', label: 'Allemand' },
  { value: 'es', label: 'Espagnol' },
  { value: 'it', label: 'Italien' },
  { value: 'pt', label: 'Portugais' },
  { value: 'ar', label: 'Arabe' },
  { value: 'zh', label: 'Chinois' },
  { value: 'ja', label: 'Japonais' },
]

const OUTPUT_FORMATS: { value: string; label: string }[] = [
  { value: 'txt', label: 'Texte (.txt)' },
  { value: 'srt', label: 'Sous-titres SRT (.srt)' },
  { value: 'vtt', label: 'Sous-titres VTT (.vtt)' },
  { value: 'json', label: 'JSON (.json)' },
  { value: 'tsv', label: 'TSV (.tsv)' },
  { value: 'md', label: 'Markdown (.md)' },
]

export interface FormValues {
  model: string
  language: string
  output_format: string
  output_dir: string
  // Main options
  task: string
  word_timestamps: boolean
  // Advanced options
  initial_prompt: string
  temperature: number
  beam_size: number
  best_of: number
  condition_on_previous_text: boolean
  fp16: boolean
  compression_ratio_threshold: number
  no_speech_threshold: number
}

interface TranscribeFormProps {
  values: FormValues
  onChange: (key: keyof FormValues, val: string | boolean | number) => void
  onSubmit: () => void
  disabled: boolean
  isLoading: boolean
}

function ToggleSwitch({
  checked,
  onChange,
  label,
  id,
}: {
  checked: boolean
  onChange: (val: boolean) => void
  label: string
  id: string
}) {
  return (
    <label htmlFor={id} className="flex items-center gap-3 cursor-pointer select-none">
      <div className="relative">
        <input
          id={id}
          type="checkbox"
          className="sr-only"
          checked={checked}
          onChange={(e) => onChange(e.target.checked)}
        />
        <div
          className={`w-9 h-5 rounded-full transition-colors ${checked ? 'bg-violet-600' : 'bg-gray-700'}`}
        />
        <div
          className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-white transition-transform ${checked ? 'translate-x-4' : ''}`}
        />
      </div>
      <span className="text-sm text-gray-300">{label}</span>
    </label>
  )
}

export default function TranscribeForm({
  values,
  onChange,
  onSubmit,
  disabled,
  isLoading,
}: TranscribeFormProps) {
  const [advancedOpen, setAdvancedOpen] = useState(false)
  const { data: modelsInfo, isLoading: modelsLoading } = useWhisperModels()

  const selectCls =
    'w-full rounded-lg bg-gray-800 border border-gray-700 px-3 py-2 text-sm text-gray-200 focus:outline-none focus:ring-1 focus:ring-violet-500'
  const inputCls =
    'w-full rounded-lg bg-gray-800 border border-gray-700 px-3 py-2 text-sm text-gray-200 focus:outline-none focus:ring-1 focus:ring-violet-500'
  const labelCls = 'block text-xs text-gray-400 mb-1'

  const multilingualModels = modelsInfo?.filter((m: WhisperModelInfo) =>
    MULTILINGUAL_MODELS.includes(m.name),
  ) ?? []
  const englishModels = modelsInfo?.filter(
    (m: WhisperModelInfo) => !MULTILINGUAL_MODELS.includes(m.name),
  ) ?? []

  function modelOptionLabel(m: WhisperModelInfo) {
    return `${m.name}  (${m.params}, VRAM ${m.vram}, ${m.speed})`
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-3 gap-4">
        {/* Model */}
        <div>
          <label className={labelCls}>Modèle</label>
          <select
            className={selectCls}
            value={values.model}
            onChange={(e: ChangeEvent<HTMLSelectElement>) =>
              onChange('model', e.target.value)
            }
            disabled={modelsLoading}
          >
            {modelsLoading ? (
              <option>Chargement…</option>
            ) : modelsInfo ? (
              <>
                <optgroup label="Multilingues">
                  {multilingualModels.map((m: WhisperModelInfo) => (
                    <option key={m.name} value={m.name}>
                      {modelOptionLabel(m)}
                    </option>
                  ))}
                </optgroup>
                <optgroup label="English-only">
                  {englishModels.map((m: WhisperModelInfo) => (
                    <option key={m.name} value={m.name}>
                      {modelOptionLabel(m)}
                    </option>
                  ))}
                </optgroup>
              </>
            ) : (
              // Fallback static list if API fails
              <>
                {['tiny', 'base', 'small', 'medium', 'large', 'large-v2', 'large-v3', 'large-v3-turbo'].map((m) => (
                  <option key={m} value={m}>{m}</option>
                ))}
              </>
            )}
          </select>
        </div>

        {/* Language */}
        <div>
          <label className={labelCls}>Langue</label>
          <select
            className={selectCls}
            value={values.language}
            onChange={(e: ChangeEvent<HTMLSelectElement>) =>
              onChange('language', e.target.value)
            }
          >
            {LANGUAGES.map(({ value, label }) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </div>

        {/* Output format */}
        <div>
          <label className={labelCls}>Format sortie</label>
          <select
            className={selectCls}
            value={values.output_format}
            onChange={(e: ChangeEvent<HTMLSelectElement>) =>
              onChange('output_format', e.target.value)
            }
          >
            {OUTPUT_FORMATS.map(({ value, label }) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* Output dir */}
      <div>
        <label className={labelCls}>
          Dossier de sortie{' '}
          <span className="text-gray-600">(laisser vide pour ~/Whisper Memory/transcripts/)</span>
        </label>
        <input
          type="text"
          placeholder="/Users/…/transcripts"
          value={values.output_dir}
          onChange={(e: ChangeEvent<HTMLInputElement>) =>
            onChange('output_dir', e.target.value)
          }
          className="w-full rounded-lg bg-gray-800 border border-gray-700 px-3 py-2 text-sm text-gray-200 placeholder-gray-600 focus:outline-none focus:ring-1 focus:ring-violet-500 font-mono"
        />
      </div>

      {/* Main options — task + word_timestamps */}
      <div className="space-y-3 pt-1 border-t border-gray-700/50">
        {/* Task */}
        <div>
          <label className={labelCls}>Tâche</label>
          <div className="flex gap-4">
            {[
              { value: 'transcribe', label: 'Transcrire' },
              { value: 'translate', label: 'Traduire en anglais' },
            ].map(({ value, label }) => (
              <label key={value} className="flex items-center gap-2 cursor-pointer text-sm text-gray-300">
                <input
                  type="radio"
                  name="task"
                  value={value}
                  checked={values.task === value}
                  onChange={() => onChange('task', value)}
                  className="accent-violet-500"
                />
                {label}
              </label>
            ))}
          </div>
        </div>

        {/* Word timestamps */}
        <ToggleSwitch
          id="word_timestamps"
          checked={values.word_timestamps}
          onChange={(v) => onChange('word_timestamps', v)}
          label="Timestamps par mot (utile pour SRT/VTT)"
        />
      </div>

      {/* Advanced options accordion */}
      <div className="border border-gray-700/50 rounded-lg overflow-hidden">
        <button
          type="button"
          onClick={() => setAdvancedOpen((o) => !o)}
          className="w-full flex items-center justify-between px-4 py-2.5 text-sm text-gray-400 hover:text-gray-200 hover:bg-gray-800/40 transition-colors"
        >
          <span>Options avancées</span>
          {advancedOpen ? (
            <ChevronDown className="w-4 h-4" />
          ) : (
            <ChevronRight className="w-4 h-4" />
          )}
        </button>

        {advancedOpen && (
          <div className="px-4 pb-4 pt-2 space-y-4 bg-gray-800/20">
            {/* Initial prompt */}
            <div>
              <label className={labelCls}>Contexte initial</label>
              <textarea
                rows={2}
                placeholder="Ex: Noms propres, vocabulaire technique..."
                value={values.initial_prompt}
                onChange={(e: ChangeEvent<HTMLTextAreaElement>) =>
                  onChange('initial_prompt', e.target.value)
                }
                className={inputCls + ' resize-none'}
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              {/* Temperature */}
              <div>
                <label className={labelCls}>
                  Température —{' '}
                  <span className="text-violet-400 font-mono">{values.temperature.toFixed(1)}</span>
                </label>
                <input
                  type="range"
                  min={0}
                  max={1}
                  step={0.1}
                  value={values.temperature}
                  onChange={(e: ChangeEvent<HTMLInputElement>) =>
                    onChange('temperature', parseFloat(e.target.value))
                  }
                  className="w-full accent-violet-500"
                />
                <div className="flex justify-between text-xs text-gray-600 mt-0.5">
                  <span>0.0</span><span>1.0</span>
                </div>
              </div>

              {/* No speech threshold */}
              <div>
                <label className={labelCls}>
                  Seuil silence —{' '}
                  <span className="text-violet-400 font-mono">{values.no_speech_threshold.toFixed(2)}</span>
                </label>
                <input
                  type="range"
                  min={0}
                  max={1}
                  step={0.05}
                  value={values.no_speech_threshold}
                  onChange={(e: ChangeEvent<HTMLInputElement>) =>
                    onChange('no_speech_threshold', parseFloat(e.target.value))
                  }
                  className="w-full accent-violet-500"
                />
                <div className="flex justify-between text-xs text-gray-600 mt-0.5">
                  <span>0.0</span><span>1.0</span>
                </div>
              </div>
            </div>

            <div className="grid grid-cols-3 gap-4">
              {/* Beam size */}
              <div>
                <label className={labelCls}>
                  Faisceau (beam) — plus grand = plus précis, plus lent
                </label>
                <input
                  type="number"
                  min={1}
                  max={10}
                  value={values.beam_size}
                  onChange={(e: ChangeEvent<HTMLInputElement>) =>
                    onChange('beam_size', parseInt(e.target.value, 10))
                  }
                  className={inputCls}
                />
              </div>

              {/* Best of */}
              <div>
                <label className={labelCls}>Candidats (actif si température &gt; 0)</label>
                <input
                  type="number"
                  min={1}
                  max={10}
                  value={values.best_of}
                  onChange={(e: ChangeEvent<HTMLInputElement>) =>
                    onChange('best_of', parseInt(e.target.value, 10))
                  }
                  className={inputCls}
                />
              </div>

              {/* Compression ratio threshold */}
              <div>
                <label className={labelCls}>Seuil compression</label>
                <input
                  type="number"
                  min={0}
                  max={10}
                  step={0.1}
                  value={values.compression_ratio_threshold}
                  onChange={(e: ChangeEvent<HTMLInputElement>) =>
                    onChange('compression_ratio_threshold', parseFloat(e.target.value))
                  }
                  className={inputCls}
                />
              </div>
            </div>

            <div className="flex flex-col gap-3">
              <ToggleSwitch
                id="condition_on_previous_text"
                checked={values.condition_on_previous_text}
                onChange={(v) => onChange('condition_on_previous_text', v)}
                label="Utiliser le contexte précédent"
              />
              <ToggleSwitch
                id="fp16"
                checked={values.fp16}
                onChange={(v) => onChange('fp16', v)}
                label="Précision FP16 (plus rapide)"
              />
            </div>
          </div>
        )}
      </div>

      {/* Submit */}
      <button
        onClick={onSubmit}
        disabled={disabled}
        className="flex items-center gap-2 px-5 py-2.5 rounded-lg bg-violet-600 hover:bg-violet-500 disabled:opacity-40 disabled:cursor-not-allowed text-white font-medium text-sm transition-colors"
      >
        {isLoading ? (
          <Loader2 className="w-4 h-4 animate-spin" />
        ) : (
          <PlayCircle className="w-4 h-4" />
        )}
        Transcrire
      </button>
    </div>
  )
}
