import { useEffect, useState } from "react";
import { revealItemInDir } from "@tauri-apps/plugin-opener";
import { getStartupStatus } from "./lib/ipc";
import type { StartupStatus } from "./lib/types";
import Backups from "./pages/Backups";
import Benchmark from "./pages/Benchmark";
import Dashboard from "./pages/Dashboard";
import Tweaks from "./pages/Tweaks";

type Page = "dashboard" | "tweaks" | "benchmark" | "backups";

const PAGES: { id: Page; label: string }[] = [
  { id: "dashboard", label: "Dashboard" },
  { id: "tweaks", label: "Tweaks" },
  { id: "benchmark", label: "Benchmark" },
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
          ? "border-cyan-900 bg-cyan-950/50 text-cyan-300"
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
  const [logNote, setLogNote] = useState<string | null>(null);

  useEffect(() => {
    getStartupStatus()
      .then(setStatus)
      .catch(() => setStatus(null));
  }, []);

  const openLogs = () => {
    if (!status) return;
    revealItemInDir(status.logDir).catch(() => setLogNote(status.logDir));
  };

  return (
    <main className="flex min-h-full flex-col text-zinc-100">
      <div className="mx-auto flex w-full max-w-3xl flex-1 flex-col px-6 py-6">
        <header className="flex items-center justify-between gap-3">
          <div className="min-w-0">
            <h1 className="truncate text-lg font-semibold tracking-tight">
              Da Sigma Squads Optimizer <span className="text-cyan-400">KBF</span>
            </h1>
            <p className="mt-0.5 text-xs text-zinc-500">
              {status ? `Windows 11 build ${status.osBuild}.${status.osRevision}` : "…"}
            </p>
          </div>
          <AdminBadge status={status} />
        </header>

        <nav aria-label="Pages" className="mt-5 flex gap-1 border-b border-zinc-800">
          {PAGES.map((p) => (
            <button
              key={p.id}
              aria-current={page === p.id ? "page" : undefined}
              className={`-mb-px border-b-2 px-3 py-2 text-sm transition-colors ${
                page === p.id
                  ? "border-cyan-500 font-medium text-zinc-100"
                  : "border-transparent text-zinc-500 hover:text-zinc-300"
              }`}
              onClick={() => setPage(p.id)}
            >
              {p.label}
            </button>
          ))}
        </nav>

        <div className="mt-6 flex-1 pb-8">
          {page === "dashboard" && <Dashboard />}
          {page === "tweaks" && <Tweaks />}
          {page === "benchmark" && <Benchmark />}
          {page === "backups" && <Backups />}
        </div>

        <footer className="mt-auto flex items-center justify-between border-t border-zinc-900 pt-3 text-xs text-zinc-600">
          <span>{status ? `v${status.version}` : ""}</span>
          <span className="flex items-center gap-2">
            {logNote && <span className="font-mono text-zinc-500">{logNote}</span>}
            <button
              className="hover:text-zinc-400 hover:underline"
              onClick={openLogs}
              disabled={!status}
            >
              Open logs folder
            </button>
          </span>
        </footer>
      </div>
    </main>
  );
}
