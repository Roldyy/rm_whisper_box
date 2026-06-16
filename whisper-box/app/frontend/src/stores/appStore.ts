import { create } from 'zustand'

interface JobState {
  percent: number
  logs: string[]
}

type Theme = 'dark' | 'light'

interface AppStore {
  activeJobId: number | null
  runningJobs: Map<number, JobState>
  settings: Record<string, string>
  theme: Theme

  setActiveJob: (id: number | null) => void
  updateJobProgress: (jobId: number, percent: number, segment?: string) => void
  appendLog: (jobId: number, message: string) => void
  clearJob: (jobId: number) => void
  setSettings: (s: Record<string, string>) => void
  toggleTheme: () => void
  initTheme: () => void
}

function applyTheme(theme: Theme) {
  const root = document.documentElement
  if (theme === 'dark') {
    root.classList.add('dark')
    root.classList.remove('light')
  } else {
    root.classList.remove('dark')
    root.classList.add('light')
  }
}

const savedTheme = (localStorage.getItem('wb-theme') as Theme | null) ?? 'dark'

export const useAppStore = create<AppStore>((set) => ({
  activeJobId: null,
  runningJobs: new Map(),
  settings: {},
  theme: savedTheme,

  setActiveJob: (id) => set({ activeJobId: id }),

  updateJobProgress: (jobId, percent, segment) =>
    set((state) => {
      const next = new Map(state.runningJobs)
      const existing = next.get(jobId) ?? { percent: 0, logs: [] }
      const logs = segment ? [...existing.logs, segment] : existing.logs
      next.set(jobId, { percent, logs })
      return { runningJobs: next }
    }),

  appendLog: (jobId, message) =>
    set((state) => {
      const next = new Map(state.runningJobs)
      const existing = next.get(jobId) ?? { percent: 0, logs: [] }
      next.set(jobId, { ...existing, logs: [...existing.logs, message] })
      return { runningJobs: next }
    }),

  clearJob: (jobId) =>
    set((state) => {
      const next = new Map(state.runningJobs)
      next.delete(jobId)
      return { runningJobs: next }
    }),

  setSettings: (s) => set({ settings: s }),

  toggleTheme: () =>
    set((state) => {
      const next: Theme = state.theme === 'dark' ? 'light' : 'dark'
      localStorage.setItem('wb-theme', next)
      applyTheme(next)
      return { theme: next }
    }),

  initTheme: () => {
    applyTheme(savedTheme)
  },
}))
