import { useEffect, useState, type ReactNode } from "react";
import { getSystemProfile } from "../lib/ipc";
import type { SystemProfile } from "../lib/types";

function Card({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="rounded-lg border border-zinc-800 bg-zinc-900/60 p-4">
      <h2 className="text-[11px] font-semibold uppercase tracking-widest text-zinc-500">
        {title}
      </h2>
      <div className="mt-3">{children}</div>
    </section>
  );
}

function Chip({ label, on, invert }: { label: string; on: boolean; invert?: boolean }) {
  // invert: for flags where "on" is the performance-unfriendly state.
  const good = invert ? !on : on;
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs ${
        good
          ? "border-emerald-900 bg-emerald-950/50 text-emerald-300"
          : "border-zinc-700 bg-zinc-800/60 text-zinc-400"
      }`}
    >
      <span className={`h-1.5 w-1.5 rounded-full ${good ? "bg-emerald-400" : "bg-zinc-500"}`} />
      {label}: {on ? "on" : "off"}
    </span>
  );
}

const VENDOR_LABEL: Record<string, string> = {
  nvidia: "NVIDIA",
  amd: "AMD",
  intel: "Intel",
  unknown: "Unknown",
};

function gb(mb: number): string {
  return `${(mb / 1024).toFixed(mb % 1024 === 0 ? 0 : 1)} GB`;
}

function SkeletonCard() {
  return (
    <div className="animate-pulse rounded-lg border border-zinc-800 bg-zinc-900/60 p-4">
      <div className="h-2.5 w-20 rounded bg-zinc-800" />
      <div className="mt-4 h-3.5 w-3/4 rounded bg-zinc-800" />
      <div className="mt-2 h-3 w-1/2 rounded bg-zinc-800/70" />
    </div>
  );
}

export default function Dashboard() {
  const [profile, setProfile] = useState<SystemProfile | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const load = (refresh: boolean) => {
    setError(null);
    if (refresh) setRefreshing(true);
    getSystemProfile(refresh)
      .then(setProfile)
      .catch((e: unknown) => setError(String(e)))
      .finally(() => setRefreshing(false));
  };

  useEffect(() => load(false), []);

  if (error) {
    return (
      <div className="rounded-lg border border-red-900 bg-red-950/40 p-4 text-sm text-red-300">
        <p className="font-mono">Detection failed: {error}</p>
        <button
          className="mt-3 rounded-md border border-red-800 px-3 py-1.5 text-xs text-red-200 hover:bg-red-950"
          onClick={() => load(true)}
        >
          Try again
        </button>
      </div>
    );
  }

  if (!profile) {
    return (
      <div>
        <p className="mb-4 flex items-center gap-2 text-sm text-zinc-500">
          <span className="h-2 w-2 animate-pulse rounded-full bg-emerald-400" />
          Profiling this machine…
        </p>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <SkeletonCard />
          <SkeletonCard />
          <SkeletonCard />
          <SkeletonCard />
        </div>
      </div>
    );
  }

  const { os, cpu, gpu, ram_mb, storage, form_factor, state } = profile;

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <div className="flex items-center justify-between sm:col-span-2">
        <p className="text-xs text-zinc-600">
          Detected hardware — tweak eligibility is based on this.
        </p>
        <button
          className="rounded-md border border-zinc-700 px-2.5 py-1 text-xs text-zinc-300 hover:bg-zinc-800 disabled:cursor-not-allowed disabled:opacity-40"
          disabled={refreshing}
          onClick={() => load(true)}
        >
          {refreshing ? "Re-detecting…" : "Re-detect"}
        </button>
      </div>
      <Card title="System">
        <p className="text-sm text-zinc-100">
          Windows 11 {os.version} <span className="text-zinc-500">· {os.edition}</span>
        </p>
        <p className="mt-1 font-mono text-xs text-zinc-500">build {os.build}</p>
        <p className="mt-2 text-sm text-zinc-300">
          {form_factor === "laptop" ? "Laptop" : form_factor === "desktop" ? "Desktop" : "Unknown form factor"}
          <span className="text-zinc-500"> · power plan: {state.power_plan}</span>
        </p>
      </Card>

      <Card title="CPU">
        <p className="text-sm text-zinc-100">{cpu.name}</p>
        <p className="mt-1 text-xs text-zinc-500">
          {VENDOR_LABEL[cpu.vendor]} · {cpu.cores} cores / {cpu.threads} threads
          {cpu.hybrid ? " · hybrid (P+E cores)" : ""}
        </p>
      </Card>

      <Card title={gpu.length > 1 ? "GPUs" : "GPU"}>
        <ul className="space-y-3">
          {gpu.map((g) => (
            <li key={g.name}>
              <p className="text-sm text-zinc-100">{g.name}</p>
              <p className="mt-0.5 text-xs text-zinc-500">
                {VENDOR_LABEL[g.vendor]} · driver {g.driver} · {gb(g.vram_mb)} VRAM
              </p>
            </li>
          ))}
          {gpu.length === 0 && <li className="text-sm text-zinc-500">No PCI GPU detected</li>}
        </ul>
      </Card>

      <Card title="Memory & storage">
        <p className="text-sm text-zinc-100">{gb(ram_mb)} RAM</p>
        <ul className="mt-2 space-y-1">
          {storage.map((d) => (
            <li key={d.drive} className="text-xs text-zinc-400">
              <span className="font-mono text-zinc-300">{d.drive}</span>{" "}
              <span className="uppercase">{d.type}</span>
            </li>
          ))}
        </ul>
      </Card>

      <Card title="Gaming-relevant state">
        <div className="flex flex-wrap gap-2">
          <Chip label="Game Mode" on={state.game_mode} />
          <Chip label="Game DVR" on={state.game_dvr} invert />
          <Chip label="HAGS" on={state.hags_enabled} />
          <Chip label="FSO" on={state.fso_global} invert />
          <Chip label="Mouse accel" on={state.mouse_accel} invert />
        </div>
      </Card>

      <Card title="Security (advanced-tier tradeoffs)">
        <div className="flex flex-wrap gap-2">
          <Chip label="VBS" on={state.vbs_enabled} />
          <Chip label="HVCI" on={state.hvci_enabled} />
        </div>
        <p className="mt-2 text-xs text-zinc-600">
          Shown for transparency — disabling these trades security for performance.
        </p>
      </Card>
    </div>
  );
}
