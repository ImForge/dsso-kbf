import { useCallback, useEffect, useMemo, useState } from "react";
import { listBenchmarkRuns, runGameBenchmark, runSystemBenchmark } from "../lib/ipc";
import type { BenchmarkRun } from "../lib/types";

interface MetricRow {
  name: string;
  before: number | null;
  after: number | null;
  unit: string;
  higherIsBetter: boolean;
}

function rowsFor(before: BenchmarkRun, after: BenchmarkRun): MetricRow[] {
  if (before.game && after.game) {
    const b = before.game;
    const a = after.game;
    return [
      { name: "Avg FPS", before: b.fps_avg, after: a.fps_avg, unit: "", higherIsBetter: true },
      { name: "1% low FPS", before: b.fps_1_low, after: a.fps_1_low, unit: "", higherIsBetter: true },
      { name: "0.1% low FPS", before: b.fps_01_low, after: a.fps_01_low, unit: "", higherIsBetter: true },
      {
        name: "Frametime stddev",
        before: b.frametime_stddev_ms,
        after: a.frametime_stddev_ms,
        unit: " ms",
        higherIsBetter: false,
      },
    ];
  }
  if (before.system && after.system) {
    const b = before.system;
    const a = after.system;
    return [
      {
        name: "Idle CPU usage",
        before: b.cpu_usage_percent,
        after: a.cpu_usage_percent,
        unit: " %",
        higherIsBetter: false,
      },
      { name: "RAM used", before: b.ram_used_mb, after: a.ram_used_mb, unit: " MB", higherIsBetter: false },
      { name: "Boot time", before: b.boot_time_ms, after: a.boot_time_ms, unit: " ms", higherIsBetter: false },
    ];
  }
  return [];
}

function CompareTable({ before, after }: { before: BenchmarkRun; after: BenchmarkRun }) {
  const rows = rowsFor(before, after);
  if (rows.length === 0) {
    return (
      <p className="text-xs text-amber-400">
        Pick two runs of the same kind (two game captures or two system snapshots).
      </p>
    );
  }
  return (
    <table className="w-full text-left text-xs">
      <thead>
        <tr className="text-zinc-500">
          <th className="py-1 font-normal">Metric</th>
          <th className="py-1 font-normal">Before ({before.id})</th>
          <th className="py-1 font-normal">After ({after.id})</th>
          <th className="py-1 font-normal">Change</th>
        </tr>
      </thead>
      <tbody className="font-mono">
        {rows.map((r) => {
          if (r.before === null || r.after === null) {
            return (
              <tr key={r.name} className="border-t border-zinc-800">
                <td className="py-1.5 font-sans text-zinc-300">{r.name}</td>
                <td className="py-1.5">{r.before ?? "–"}</td>
                <td className="py-1.5">{r.after ?? "–"}</td>
                <td className="py-1.5 text-zinc-600">not comparable</td>
              </tr>
            );
          }
          const delta = r.after - r.before;
          const improved = r.higherIsBetter ? delta > 0 : delta < 0;
          const unchanged = Math.abs(delta) < 1e-9;
          return (
            <tr key={r.name} className="border-t border-zinc-800">
              <td className="py-1.5 font-sans text-zinc-300">{r.name}</td>
              <td className="py-1.5 text-zinc-400">
                {r.before}
                {r.unit}
              </td>
              <td className="py-1.5 text-zinc-100">
                {r.after}
                {r.unit}
              </td>
              <td
                className={`py-1.5 ${
                  unchanged ? "text-zinc-500" : improved ? "text-cyan-400" : "text-red-400"
                }`}
              >
                {delta > 0 ? "+" : ""}
                {Math.round(delta * 100) / 100}
                {r.unit}
                {unchanged ? "" : improved ? " (better)" : " (WORSE)"}
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

export default function Benchmark() {
  const [runs, setRuns] = useState<BenchmarkRun[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [process, setProcess] = useState("");
  const [duration, setDuration] = useState(30);
  const [label, setLabel] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [picked, setPicked] = useState<string[]>([]);

  const reload = useCallback(() => {
    listBenchmarkRuns()
      .then(setRuns)
      .catch((e: unknown) => setError(String(e)));
  }, []);
  useEffect(reload, [reload]);

  const start = (kind: "game" | "system") => {
    setError(null);
    setBusy(kind === "game" ? `capturing ${process} for ${duration}s…` : "measuring (~6s)…");
    const call =
      kind === "game"
        ? runGameBenchmark(process, duration, label || undefined)
        : runSystemBenchmark(label || undefined);
    call
      .then(() => reload())
      .catch((e: unknown) => setError(String(e)))
      .finally(() => setBusy(null));
  };

  const pick = (id: string, on: boolean) => {
    setPicked((p) => {
      const rest = p.filter((x) => x !== id);
      if (!on) return rest;
      return [...rest, id].slice(-2);
    });
  };

  const compare = useMemo(() => {
    if (!runs || picked.length !== 2) return null;
    const a = runs.find((r) => r.id === picked[0]);
    const b = runs.find((r) => r.id === picked[1]);
    if (!a || !b) return null;
    // Older run = before.
    return a.id < b.id ? { before: a, after: b } : { before: b, after: a };
  }, [runs, picked]);

  return (
    <div className="space-y-5">
      <section className="rounded-lg border border-zinc-800 bg-zinc-900/70 backdrop-blur-sm p-4">
        <h2 className="text-[11px] font-semibold uppercase tracking-widest text-zinc-500">
          New capture
        </h2>
        <div className="mt-3 flex flex-wrap items-end gap-3">
          <label className="text-xs text-zinc-400">
            Game exe name
            <input
              className="mt-1 block w-44 rounded-md border border-zinc-700 bg-zinc-950 px-2 py-1.5 font-mono text-xs text-zinc-100 placeholder-zinc-600 focus:border-cyan-600 focus:outline-none"
              placeholder="game.exe"
              value={process}
              onChange={(e) => setProcess(e.target.value)}
            />
          </label>
          <label className="text-xs text-zinc-400">
            Duration
            <select
              className="mt-1 block rounded-md border border-zinc-700 bg-zinc-950 px-2 py-1.5 text-xs text-zinc-100"
              value={duration}
              onChange={(e) => setDuration(Number(e.target.value))}
            >
              <option value={10}>10 s</option>
              <option value={30}>30 s</option>
              <option value={60}>60 s</option>
              <option value={120}>120 s</option>
            </select>
          </label>
          <label className="text-xs text-zinc-400">
            Label (optional)
            <input
              className="mt-1 block w-40 rounded-md border border-zinc-700 bg-zinc-950 px-2 py-1.5 text-xs text-zinc-100 placeholder-zinc-600 focus:border-cyan-600 focus:outline-none"
              placeholder="before tweaks"
              value={label}
              onChange={(e) => setLabel(e.target.value)}
            />
          </label>
          <button
            className="rounded-md bg-cyan-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-cyan-500 disabled:cursor-not-allowed disabled:opacity-40"
            disabled={!!busy || process.trim() === ""}
            onClick={() => start("game")}
          >
            Capture game FPS
          </button>
          <button
            className="rounded-md border border-zinc-700 px-3 py-1.5 text-xs text-zinc-300 hover:bg-zinc-800 disabled:cursor-not-allowed disabled:opacity-40"
            disabled={!!busy}
            onClick={() => start("system")}
          >
            Snapshot system metrics
          </button>
        </div>
        <p className="mt-2 text-xs text-zinc-600">
          Run the game first, then capture. Compare a "before tweaks" run against an "after"
          run below — same game, same scene, same duration, or the numbers mean nothing.
        </p>
        {busy && <p className="mt-2 text-xs text-cyan-300">{busy}</p>}
        {error && <p className="mt-2 font-mono text-xs text-red-400">{error}</p>}
      </section>

      {compare && (
        <section className="rounded-lg border border-zinc-700 bg-zinc-900 p-4">
          <h2 className="text-[11px] font-semibold uppercase tracking-widest text-zinc-500">
            Before / after
          </h2>
          <div className="mt-3">
            <CompareTable before={compare.before} after={compare.after} />
          </div>
        </section>
      )}

      <section>
        <h2 className="text-[11px] font-semibold uppercase tracking-widest text-zinc-500">
          Stored runs {runs && runs.length > 0 ? "(pick two to compare)" : ""}
        </h2>
        <div className="mt-2 space-y-2">
          {!runs && <p className="text-sm text-zinc-500">Loading…</p>}
          {runs && runs.length === 0 && (
            <p className="text-sm text-zinc-500">No runs yet.</p>
          )}
          {runs?.map((r) => (
            <label
              key={r.id}
              className="flex items-start gap-3 rounded-lg border border-zinc-800 bg-zinc-900/70 backdrop-blur-sm p-3"
            >
              <input
                type="checkbox"
                className="mt-0.5 accent-cyan-500"
                checked={picked.includes(r.id)}
                onChange={(e) => pick(r.id, e.target.checked)}
              />
              <div className="min-w-0 flex-1">
                <p className="font-mono text-xs text-zinc-200">
                  {r.id}
                  {r.label && <span className="ml-2 text-cyan-300">{r.label}</span>}
                  <span className="ml-2 text-zinc-500">
                    {r.game ? `game · ${r.process} · ${r.duration_s}s` : "system snapshot"}
                  </span>
                </p>
                {r.game && (
                  <p className="mt-1 font-mono text-xs text-zinc-400">
                    {r.game.fps_avg} avg · {r.game.fps_1_low} 1% low · {r.game.fps_01_low} 0.1% ·{" "}
                    {r.game.frametime_stddev_ms} ms σ · {r.game.frames} frames
                  </p>
                )}
                {r.system && (
                  <p className="mt-1 font-mono text-xs text-zinc-400">
                    CPU {r.system.cpu_usage_percent}% · RAM {r.system.ram_used_mb}/
                    {r.system.ram_total_mb} MB · boot{" "}
                    {r.system.boot_time_ms === null ? "n/a" : `${r.system.boot_time_ms} ms`}
                  </p>
                )}
              </div>
            </label>
          ))}
        </div>
      </section>
    </div>
  );
}
