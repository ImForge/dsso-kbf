import { useEffect, useState } from "react";
import { getStartupStatus } from "./lib/ipc";
import type { StartupStatus } from "./lib/types";
import Backups from "./pages/Backups";
import Dashboard from "./pages/Dashboard";
import Tweaks from "./pages/Tweaks";

type Page = "dashboard" | "tweaks" | "backups";

const PAGES: { id: Page; label: string }[] = [
  { id: "dashboard", label: "Dashboard" },
  { id: "tweaks", label: "Tweaks" },
  { id: "backups", label: "Backups" },
];

function AdminBadge({ status }: { status: StartupStatus | null }) {
  if (!status) {
    return <span className="text-xs text-zinc-600">checking…</span>;
  }
  return (
    <span
      className={`rounded-full border px-2.5 py-1 font-mono text-xs ${
        status.elevated
          ? "border-emerald-900 bg-emerald-950/50 text-emerald-300"
          : "border-red-900 bg-red-950/50 text-red-300"
      }`}
    >
      admin: {status.elevated ? "yes" : "no"}
    </span>
  );
}

export default function App() {
  const [status, setStatus] = useState<StartupStatus | null>(null);
  const [page, setPage] = useState<Page>("dashboard");

  useEffect(() => {
    getStartupStatus()
      .then(setStatus)
      .catch(() => setStatus(null));
  }, []);

  return (
    <main className="min-h-full bg-zinc-950 text-zinc-100">
      <div className="mx-auto max-w-3xl px-6 py-6">
        <header className="flex items-center justify-between">
          <div>
            <h1 className="text-lg font-semibold tracking-tight">
              Da Sigma Squads Optimizer <span className="text-emerald-400">KBF</span>
            </h1>
            <p className="mt-0.5 text-xs text-zinc-500">
              {status ? `Windows 11 build ${status.osBuild}.${status.osRevision}` : "…"}
            </p>
          </div>
          <AdminBadge status={status} />
        </header>

        <nav className="mt-5 flex gap-1 border-b border-zinc-800">
          {PAGES.map((p) => (
            <button
              key={p.id}
              className={`-mb-px border-b-2 px-3 py-2 text-sm ${
                page === p.id
                  ? "border-emerald-500 font-medium text-zinc-100"
                  : "border-transparent text-zinc-500 hover:text-zinc-300"
              }`}
              onClick={() => setPage(p.id)}
            >
              {p.label}
            </button>
          ))}
        </nav>

        <div className="mt-6 pb-10">
          {page === "dashboard" && <Dashboard />}
          {page === "tweaks" && <Tweaks />}
          {page === "backups" && <Backups />}
        </div>
      </div>
    </main>
  );
}
