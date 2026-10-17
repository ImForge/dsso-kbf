import { useCallback, useEffect, useMemo, useState } from "react";
import { applyTweaks, detectTweak, getTweakItems, listTweaks } from "../lib/ipc";
import type {
  ApplySummary,
  DetectState,
  Risk,
  TweakItem,
  TweakListEntry,
  TweakSelection,
} from "../lib/types";

const RISK_ORDER: Risk[] = ["safe", "caution", "advanced"];
const RISK_LABEL: Record<Risk, string> = {
  safe: "Safe",
  caution: "Caution — opt-in",
  advanced: "Advanced — opt-in",
};

function StateBadge({ state }: { state: DetectState | "loading" | undefined }) {
  if (state === undefined || state === "loading") {
    return <span className="font-mono text-xs text-zinc-600">checking…</span>;
  }
  const style: Record<DetectState, string> = {
    applied: "border-emerald-900 bg-emerald-950/50 text-emerald-300",
    "not-applied": "border-zinc-700 bg-zinc-800/60 text-zinc-300",
    partial: "border-amber-900 bg-amber-950/50 text-amber-300",
    unknown: "border-zinc-800 bg-zinc-900 text-zinc-500",
  };
  return (
    <span className={`rounded-full border px-2 py-0.5 font-mono text-xs ${style[state]}`}>
      {state}
    </span>
  );
}

export default function Tweaks() {
  const [entries, setEntries] = useState<TweakListEntry[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [states, setStates] = useState<Record<string, DetectState | "loading">>({});
  const [checked, setChecked] = useState<Record<string, boolean>>({});
  const [items, setItems] = useState<Record<string, TweakItem[] | "loading">>({});
  const [itemChecks, setItemChecks] = useState<Record<string, Record<string, boolean>>>({});
  const [reviewing, setReviewing] = useState(false);
  const [applying, setApplying] = useState(false);
  const [summary, setSummary] = useState<ApplySummary | null>(null);

  const refreshStates = useCallback((list: TweakListEntry[]) => {
    for (const e of list) {
      if (!e.applicable || e.manifest.list_driven) continue;
      const id = e.manifest.id;
      setStates((s) => ({ ...s, [id]: "loading" }));
      detectTweak(id)
        .then((st) => setStates((s) => ({ ...s, [id]: st })))
        .catch(() => setStates((s) => ({ ...s, [id]: "unknown" })));
    }
  }, []);

  useEffect(() => {
    listTweaks()
      .then((list) => {
        setEntries(list);
        refreshStates(list);
      })
      .catch((e: unknown) => setError(String(e)));
  }, [refreshStates]);

  const loadItems = (id: string) => {
    if (items[id]) return;
    setItems((m) => ({ ...m, [id]: "loading" }));
    getTweakItems(id)
      .then((list) => setItems((m) => ({ ...m, [id]: list })))
      .catch(() => setItems((m) => ({ ...m, [id]: [] })));
  };

  const selections = useMemo<TweakSelection[]>(() => {
    if (!entries) return [];
    const out: TweakSelection[] = [];
    for (const e of entries) {
      if (!e.applicable) continue;
      const id = e.manifest.id;
      if (e.manifest.list_driven) {
        const picks = Object.entries(itemChecks[id] ?? {})
          .filter(([, on]) => on)
          .map(([itemId]) => itemId);
        if (picks.length > 0) out.push({ id, items: picks });
      } else if (checked[id]) {
        out.push({ id });
      }
    }
    return out;
  }, [entries, checked, itemChecks]);

  const runApply = () => {
    setApplying(true);
    applyTweaks(selections)
      .then((s) => {
        setSummary(s);
        setReviewing(false);
        if (entries) refreshStates(entries);
      })
      .catch((e: unknown) => setError(String(e)))
      .finally(() => setApplying(false));
  };

  if (error) {
    return (
      <div className="rounded-lg border border-red-900 bg-red-950/40 p-4 font-mono text-sm text-red-300">
        {error}
      </div>
    );
  }
  if (!entries) {
    return <p className="text-sm text-zinc-500">Loading tweaks…</p>;
  }

  const findEntry = (id: string) => entries.find((e) => e.manifest.id === id);

  return (
    <div className="space-y-6">
      {summary && (
        <div className="rounded-lg border border-zinc-700 bg-zinc-900 p-4">
          <h3 className="text-sm font-semibold text-zinc-100">
            Session {summary.session_id}
          </h3>
          {!summary.restore_point.created && (
            <p className="mt-1 text-xs text-amber-400">
              No system restore point (
              {summary.restore_point.reason === "24h-skip"
                ? "Windows skips restore points within 24h of the last one"
                : summary.restore_point.reason === "protection-off"
                  ? "System Protection is disabled on C:"
                  : summary.restore_point.reason}
              ) — per-tweak backups were taken.
            </p>
          )}
          <ul className="mt-2 space-y-1">
            {summary.results.map((r) => (
              <li key={r.id} className="font-mono text-xs">
                <span
                  className={
                    r.status === "applied"
                      ? "text-emerald-400"
                      : r.status === "skipped"
                        ? "text-zinc-400"
                        : "text-red-400"
                  }
                >
                  {r.status}
                </span>{" "}
                <span className="text-zinc-300">{r.id}</span>
                {r.requires_reboot && <span className="text-amber-400"> · needs sign-out/reboot</span>}
                {r.error && <span className="text-red-400"> — {r.error}</span>}
              </li>
            ))}
          </ul>
          <p className="mt-2 text-xs text-zinc-500">
            Revert any of this from the Backups page.
          </p>
        </div>
      )}

      {RISK_ORDER.map((risk) => {
        const group = entries.filter((e) => e.manifest.risk === risk);
        if (group.length === 0) return null;
        return (
          <section key={risk}>
            <h2 className="text-[11px] font-semibold uppercase tracking-widest text-zinc-500">
              {RISK_LABEL[risk]}
            </h2>
            <div className="mt-2 space-y-2">
              {group.map((e) => {
                const m = e.manifest;
                const tweakItems = items[m.id];
                return (
                  <div
                    key={m.id}
                    className={`rounded-lg border p-3 ${
                      e.applicable
                        ? "border-zinc-800 bg-zinc-900/60"
                        : "border-zinc-900 bg-zinc-950 opacity-50"
                    }`}
                  >
                    <div className="flex items-start gap-3">
                      {!m.list_driven && (
                        <input
                          type="checkbox"
                          className="mt-1 accent-emerald-500"
                          disabled={!e.applicable}
                          checked={checked[m.id] ?? false}
                          onChange={(ev) =>
                            setChecked((c) => ({ ...c, [m.id]: ev.target.checked }))
                          }
                        />
                      )}
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center justify-between gap-2">
                          <p className="text-sm text-zinc-100">{m.name}</p>
                          {e.applicable ? (
                            <StateBadge state={m.list_driven ? undefined : states[m.id]} />
                          ) : (
                            <span className="text-xs text-zinc-600">not applicable</span>
                          )}
                        </div>
                        <p className="mt-1 text-xs text-zinc-500">{m.description}</p>
                        {m.warning && (
                          <p className="mt-1 text-xs text-amber-400">⚠ {m.warning}</p>
                        )}
                        {m.list_driven && e.applicable && (
                          <div className="mt-2">
                            {!tweakItems && (
                              <button
                                className="text-xs text-emerald-400 hover:underline"
                                onClick={() => loadItems(m.id)}
                              >
                                Show items on this machine…
                              </button>
                            )}
                            {tweakItems === "loading" && (
                              <p className="text-xs text-zinc-600">scanning…</p>
                            )}
                            {Array.isArray(tweakItems) && tweakItems.length === 0 && (
                              <p className="text-xs text-zinc-600">nothing found</p>
                            )}
                            {Array.isArray(tweakItems) && tweakItems.length > 0 && (
                              <ul className="space-y-1">
                                {tweakItems.map((it) => (
                                  <li key={it.id} className="flex items-start gap-2">
                                    <input
                                      type="checkbox"
                                      className="mt-0.5 accent-emerald-500"
                                      disabled={!it.active}
                                      checked={itemChecks[m.id]?.[it.id] ?? false}
                                      onChange={(ev) =>
                                        setItemChecks((c) => ({
                                          ...c,
                                          [m.id]: { ...c[m.id], [it.id]: ev.target.checked },
                                        }))
                                      }
                                    />
                                    <span className="min-w-0 text-xs text-zinc-300">
                                      {it.name}
                                      {!it.active && (
                                        <span className="text-zinc-600"> (already off)</span>
                                      )}
                                      {it.detail && (
                                        <span className="block truncate font-mono text-[10px] text-zinc-600">
                                          {it.detail}
                                        </span>
                                      )}
                                    </span>
                                  </li>
                                ))}
                              </ul>
                            )}
                          </div>
                        )}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </section>
        );
      })}

      <div className="sticky bottom-4">
        <button
          className="w-full rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white shadow-lg hover:bg-emerald-500 disabled:cursor-not-allowed disabled:bg-zinc-800 disabled:text-zinc-500"
          disabled={selections.length === 0}
          onClick={() => setReviewing(true)}
        >
          Review &amp; Apply ({selections.length})
        </button>
      </div>

      {reviewing && (
        <div className="fixed inset-0 z-10 flex items-center justify-center bg-black/70 p-6">
          <div className="max-h-full w-full max-w-lg overflow-y-auto rounded-lg border border-zinc-700 bg-zinc-900 p-5">
            <h3 className="text-sm font-semibold text-zinc-100">
              Review — exactly this will change
            </h3>
            <div className="mt-3 space-y-4">
              {selections.map((sel) => {
                const entry = findEntry(sel.id);
                if (!entry) return null;
                const tweakItems = items[sel.id];
                return (
                  <div key={sel.id}>
                    <p className="text-sm text-zinc-200">{entry.manifest.name}</p>
                    <ul className="mt-1 space-y-0.5">
                      {entry.manifest.touches.map((t) => (
                        <li key={t} className="break-all font-mono text-[11px] text-zinc-500">
                          {t}
                        </li>
                      ))}
                    </ul>
                    {sel.items && Array.isArray(tweakItems) && (
                      <ul className="mt-1 space-y-0.5">
                        {sel.items.map((itemId) => (
                          <li key={itemId} className="text-xs text-amber-300">
                            → {tweakItems.find((i) => i.id === itemId)?.name ?? itemId}
                          </li>
                        ))}
                      </ul>
                    )}
                  </div>
                );
              })}
            </div>
            <div className="mt-5 flex justify-end gap-2">
              <button
                className="rounded-md border border-zinc-700 px-3 py-1.5 text-sm text-zinc-300 hover:bg-zinc-800"
                onClick={() => setReviewing(false)}
                disabled={applying}
              >
                Cancel
              </button>
              <button
                className="rounded-md bg-emerald-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-emerald-500 disabled:bg-zinc-700"
                onClick={runApply}
                disabled={applying}
              >
                {applying ? "Applying… (backing up first)" : "Apply with backup"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
