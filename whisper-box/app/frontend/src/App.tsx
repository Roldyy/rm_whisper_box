import { useEffect, useState } from 'react'
import {
  createBrowserRouter,
  RouterProvider,
  NavLink,
  Outlet,
} from 'react-router-dom'
import {
  Mic2,
  History,
  ScrollText,
  Settings,
  Sun,
  Moon,
  RefreshCw,
  Loader2,
} from 'lucide-react'
import TranscribePage from './pages/TranscribePage'
import HistoryPage from './pages/HistoryPage'
import LogsPage from './pages/LogsPage'
import SettingsPage from './pages/SettingsPage'
import { useAppStore } from './stores/appStore'
import { useUpdate } from './api/settings'

function Layout() {
  const theme = useAppStore((s) => s.theme)
  const toggleTheme = useAppStore((s) => s.toggleTheme)
  const initTheme = useAppStore((s) => s.initTheme)
  const { mutate: triggerUpdate, isPending: isUpdating } = useUpdate()
  const [updateMsg, setUpdateMsg] = useState<string | null>(null)

  useEffect(() => {
    initTheme()
  }, [initTheme])

  function handleUpdate() {
    setUpdateMsg(null)
    triggerUpdate(undefined, {
      onSuccess: (data) => setUpdateMsg(data.message),
      onError: () => setUpdateMsg('Erreur lors de la mise à jour.'),
    })
  }

  const navItems = [
    { to: '/', label: 'Transcrire', icon: Mic2, end: true },
    { to: '/history', label: 'Historique', icon: History, end: false },
    { to: '/logs', label: 'Logs', icon: ScrollText, end: false },
    { to: '/settings', label: 'Paramètres', icon: Settings, end: false },
  ]

  return (
    <div className="flex h-full min-h-screen bg-gray-50 dark:bg-gray-900 text-gray-900 dark:text-gray-100">
      {/* Sidebar */}
      <aside className="w-52 shrink-0 flex flex-col bg-white dark:bg-gray-950 border-r border-gray-200 dark:border-gray-800">
        {/* Logo */}
        <div className="px-5 py-5 border-b border-gray-200 dark:border-gray-800">
          <div className="flex items-center gap-2">
            <Mic2 className="text-violet-500 w-5 h-5" />
            <span className="font-semibold text-gray-900 dark:text-white tracking-tight">Whisper Box</span>
          </div>
        </div>

        {/* Nav */}
        <nav className="flex-1 py-4 flex flex-col gap-1 px-2">
          {navItems.map(({ to, label, icon: Icon, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                  isActive
                    ? 'bg-violet-600 text-white'
                    : 'text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-100 hover:bg-gray-100 dark:hover:bg-gray-800'
                }`
              }
            >
              <Icon className="w-4 h-4 shrink-0" />
              {label}
            </NavLink>
          ))}
        </nav>

        {/* Bottom actions */}
        <div className="px-3 py-3 border-t border-gray-200 dark:border-gray-800 space-y-1">
          {/* Update button */}
          <button
            onClick={handleUpdate}
            disabled={isUpdating}
            title="Mettre à jour l'application (git pull + rebuild)"
            className="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-xs font-medium text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-100 hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors disabled:opacity-50"
          >
            {isUpdating ? (
              <Loader2 className="w-3.5 h-3.5 animate-spin shrink-0" />
            ) : (
              <RefreshCw className="w-3.5 h-3.5 shrink-0" />
            )}
            {isUpdating ? 'Mise à jour…' : 'Mettre à jour'}
          </button>

          {updateMsg && (
            <p className={`text-xs px-1 leading-tight ${
              updateMsg.startsWith('Erreur')
                ? 'text-red-500'
                : updateMsg.includes('à jour') && !updateMsg.includes('Mise')
                  ? 'text-green-500 dark:text-green-400'
                  : 'text-violet-500 dark:text-violet-400'
            }`}>
              {updateMsg}
            </p>
          )}

          {/* Theme toggle + version */}
          <div className="flex items-center justify-between px-1 pt-1">
            <span className="text-xs text-gray-400 dark:text-gray-600">v1.0.0</span>
            <button
              onClick={toggleTheme}
              title={theme === 'dark' ? 'Mode clair' : 'Mode sombre'}
              className="p-1.5 rounded-lg text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-100 hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
            >
              {theme === 'dark' ? <Sun className="w-3.5 h-3.5" /> : <Moon className="w-3.5 h-3.5" />}
            </button>
          </div>
        </div>
      </aside>

      {/* Main content */}
      <main className="flex-1 overflow-y-auto p-6">
        <Outlet />
      </main>
    </div>
  )
}

const router = createBrowserRouter([
  {
    path: '/',
    element: <Layout />,
    children: [
      { index: true, element: <TranscribePage /> },
      { path: 'history', element: <HistoryPage /> },
      { path: 'logs', element: <LogsPage /> },
      { path: 'settings', element: <SettingsPage /> },
    ],
  },
])

export default function App() {
  return <RouterProvider router={router} />
}
