import { useEffect, useState } from "react";
import { getStartupStatus } from "./lib/ipc";
import type { StartupStatus } from "./lib/types";
import Dashboard from "./pages/Dashboard";

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
              Phase 2 — hardware detection
              {status ? ` · build ${status.osBuild}.${status.osRevision}` : ""}
            </p>
          </div>
          <AdminBadge status={status} />
        </header>

        <div className="mt-6">
          <Dashboard />
        </div>
      </div>
    </main>
  );
}
