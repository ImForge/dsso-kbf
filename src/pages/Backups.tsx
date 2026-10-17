import { useCallback, useEffect, useState } from "react";
import { listBackupSessions, revertBackupSession, revertBackupTweak } from "../lib/ipc";
import type { SessionRecord, TweakRunStatus } from "../lib/types";

const STATUS_STYLE: Record<TweakRunStatus, string> = {
  applied: "text-emerald-400",
  reverted: "text-zinc-400",
  failed: "text-red-400",
  skipped: "text-zinc-500",
};

/// Two-step confirm: first click arms, second fires (window.confirm is
/// unreliable inside the webview).
function ConfirmButton({
  label,
  onConfirm,
  busy,
}: {
  label: string;
  onConfirm: () => void;
  busy?: boolean;
}) {
  const [armed, setArmed] = useState(false);
  useEffect(() => {
    if (!armed) return;
    const t = setTimeout(() => setArmed(false), 4000);
    return () => clearTimeout(t);
  }, [armed]);
  return (
    <button
      className={`rounded-md border px-2.5 py-1 text-xs ${
        armed
          ? "border-red-800 bg-red-950/60 text-red-300"
          : "border-zinc-700 text-zinc-300 hover:bg-zinc-800"
      } disabled:opacity-50`}
      disabled={busy}
      onClick={() => {
        if (armed) {
          setArmed(false);
          onConfirm();
        } else {
          setArmed(true);
        }
      }}
    >
      {busy ? "working…" : armed ? "Click again to confirm" : label}
    </button>
  );
}

export default function Backups() {
  const [sessions, setSessions] = useState<SessionRecord[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const reload = useCallback(() => {
    listBackupSessions()
      .then(setSessions)
      .catch((e: unknown) => setError(String(e)));
  }, []);

  useEffect(reload, [reload]);

  const revertSession = (id: string) => {
    setBusy(id);
    setNotice(null);
    revertBackupSession(id)
      .then((results) => {
        const failed = results.filter((r) => !r.ok);
        setNotice(
          failed.length === 0
            ? `Session ${id}: ${results.length} tweak(s) reverted.`
            : `Session ${id}: ${failed.length} revert(s) FAILED — ${failed
                .map((f) => `${f.id}: ${f.error}`)
                .join("; ")}`,
        );
        reload();
      })
      .catch((e: unknown) => setNotice(String(e)))
      .finally(() => setBusy(null));
  };

  const revertOne = (sessionId: string, tweakId: string) => {
    setBusy(`${sessionId}/${tweakId}`);
    setNotice(null);
    revertBackupTweak(sessionId, tweakId)
      .then(() => {
        setNotice(`${tweakId} reverted.`);
        reload();
      })
      .catch((e: unknown) => setNotice(String(e)))
      .finally(() => setBusy(null));
  };

  if (error) {
    return (
      <div className="rounded-lg border border-red-900 bg-red-950/40 p-4 font-mono text-sm text-red-300">
        {error}
      </div>
    );
  }
  if (!sessions) {
    return <p className="text-sm text-zinc-500">Loading backup sessions…</p>;
  }

  return (
    <div className="space-y-4">
      {notice && (
        <div className="rounded-lg border border-zinc-700 bg-zinc-900 p-3 text-xs text-zinc-200">
          {notice}
        </div>
      )}
      {sessions.length === 0 && (
        <p className="text-sm text-zinc-500">
          No backup sessions yet. Every Apply creates one here.
        </p>
      )}
      {sessions.map((s) => {
        const revertible = s.tweaks.some((t) => t.status === "applied");
        return (
          <section key={s.id} className="rounded-lg border border-zinc-800 bg-zinc-900/60 p-4">
            <div className="flex items-center justify-between gap-2">
              <div>
                <p className="font-mono text-sm text-zinc-100">{s.id}</p>
                <p className="mt-0.5 text-xs text-zinc-500">
                  {new Date(s.created).toLocaleString()} ·{" "}
                  {s.restore_point.created
                    ? "restore point created"
                    : `no restore point (${s.restore_point.reason})`}
                </p>
              </div>
              {revertible && (
                <ConfirmButton
                  label="Revert whole session"
                  busy={busy === s.id}
                  onConfirm={() => revertSession(s.id)}
                />
              )}
            </div>
            <ul className="mt-3 space-y-1.5">
              {s.tweaks.map((t) => (
                <li key={t.id} className="flex items-center justify-between gap-2">
                  <span className="font-mono text-xs text-zinc-300">
                    {t.id}{" "}
                    <span className={STATUS_STYLE[t.status]}>{t.status}</span>
                    {t.requires_reboot && <span className="text-amber-400"> · reboot</span>}
                    {t.items.length > 0 && (
                      <span className="text-zinc-600"> · {t.items.length} item(s)</span>
                    )}
                    {t.error && <span className="text-red-400"> — {t.error}</span>}
                  </span>
                  {t.status === "applied" && (
                    <ConfirmButton
                      label="Revert"
                      busy={busy === `${s.id}/${t.id}`}
                      onConfirm={() => revertOne(s.id, t.id)}
                    />
                  )}
                </li>
              ))}
              {s.tweaks.length === 0 && (
                <li className="text-xs text-zinc-600">empty session</li>
              )}
            </ul>
          </section>
        );
      })}
    </div>
  );
}
