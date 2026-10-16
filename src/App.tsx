import { useEffect, useState } from "react";
import { getStartupStatus } from "./lib/ipc";
import type { StartupStatus } from "./lib/types";

function Row({ label, value, ok }: { label: string; value: string; ok?: boolean }) {
  return (
    <div className="flex items-center justify-between border-b border-zinc-800 py-3 last:border-b-0">
      <span className="text-sm text-zinc-400">{label}</span>
      <span
        className={`font-mono text-sm ${
          ok === undefined ? "text-zinc-100" : ok ? "text-emerald-400" : "text-red-400"
        }`}
      >
        {value}
      </span>
    </div>
  );
}

export default function App() {
  const [status, setStatus] = useState<StartupStatus | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getStartupStatus()
      .then(setStatus)
      .catch((e: unknown) => setError(String(e)));
  }, []);

  return (
    <main className="flex h-full items-center justify-center bg-zinc-950 text-zinc-100">
      <div className="w-full max-w-md px-6">
        <h1 className="text-lg font-semibold tracking-tight">
          Da Sigma Squads Optimizer <span className="text-emerald-400">KBF</span>
        </h1>
        <p className="mt-1 text-xs text-zinc-500">Phase 1 scaffold — startup checks</p>

        <div className="mt-6 rounded-lg border border-zinc-800 bg-zinc-900/60 px-4">
          {error && <p className="py-3 font-mono text-sm text-red-400">{error}</p>}
          {!error && !status && <p className="py-3 text-sm text-zinc-500">Checking…</p>}
          {status && (
            <>
              <Row
                label="Running as admin"
                value={status.elevated ? "yes" : "no"}
                ok={status.elevated}
              />
              <Row
                label="Windows build"
                value={`${status.osBuild}.${status.osRevision} (${status.osVersion} ${status.osEdition})`}
                ok={status.osSupported}
              />
              <Row label="Log directory" value={status.logDir} />
            </>
          )}
        </div>
      </div>
    </main>
  );
}
