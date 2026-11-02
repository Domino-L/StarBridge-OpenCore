using System.Diagnostics;

namespace StarBridge.HostRuntime.Account;

// This owner has no dependency on dispatcher/business locks. Record never touches disk.
internal sealed class AccountCurrentDiagnosticSummary : IDisposable
{
    private sealed class Totals
    {
        internal long Count, Detailed, WaitTotal, WorkTotal, WaitMax, WorkMax;
    }
    private sealed class Budget(long start)
    {
        internal long Start = start;
        internal int Used;
    }
    private readonly object _gate = new(), _writerGate = new();
    private readonly Dictionary<(bool Projected, CurrentProjectionReason Reason), Totals> _totals = [];
    private readonly Dictionary<CurrentProjectionReason, Budget> _budgets = [];
    private readonly Queue<string> _details = new();
    private readonly TimeProvider _time;
    private readonly Action<string> _write;
    private readonly ITimer _timer;
    private bool _scheduled, _disposed;

    internal AccountCurrentDiagnosticSummary(Action<string> write, TimeProvider? time = null)
    {
        _write = write;
        _time = time ?? TimeProvider.System;
        _timer = _time.CreateTimer(_ => Flush(), null, TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(5));
    }

    internal void Record(bool projected, CurrentProjectionReason reason, long wait, long work, int readers, int queued)
    {
        // Keep both cardinality and output closed even if an internal caller supplies an invalid enum.
        if (!Enum.IsDefined(reason)) reason = CurrentProjectionReason.projectionUnsupported;
        wait = Math.Clamp(wait, 0, 3600000);
        work = Math.Clamp(work, 0, 3600000);
        var schedule = false;
        lock (_gate)
        {
            if (_disposed) return;
            var key = (projected, reason);
            if (!_totals.TryGetValue(key, out var total)) _totals[key] = total = new();
            total.Count++;
            total.WaitTotal += wait; total.WorkTotal += work;
            total.WaitMax = Math.Max(total.WaitMax, wait); total.WorkMax = Math.Max(total.WorkMax, work);
            if (!projected)
            {
                var now = _time.GetTimestamp();
                if (!_budgets.TryGetValue(reason, out var budget) ||
                    _time.GetElapsedTime(budget.Start, now) >= TimeSpan.FromMinutes(1))
                    _budgets[reason] = budget = new(now);
                if (budget.Used < 10 && _details.Count < 256)
                {
                    budget.Used++; total.Detailed++;
                    _details.Enqueue(FormattableString.Invariant($"{_time.GetUtcNow():O} path=full reason={reason} waitMs={wait} workMs={work} readers={readers} queuedShared={queued}{Environment.NewLine}"));
                    if (!_scheduled) { _scheduled = true; schedule = true; }
                }
            }
        }
        if (schedule) ThreadPool.QueueUserWorkItem(_ => Drain(false));
    }

    internal void Flush() => Drain(true);

    private void Drain(bool summary)
    {
        // Only writer coordination is held during IO. Record and business work remain independent.
        lock (_writerGate)
        {
            List<string> lines;
            lock (_gate)
            {
                lines = new(_details);
                _details.Clear(); _scheduled = false;
                if (summary)
                {
                    foreach (var (key, total) in _totals)
                        lines.Add(FormattableString.Invariant($"{_time.GetUtcNow():O} summary path={(key.Projected ? "projection" : "full")} reason={key.Reason} count={total.Count} detailed={total.Detailed} suppressed={total.Count - total.Detailed} waitMsMax={total.WaitMax} waitMsTotal={total.WaitTotal} workMsMax={total.WorkMax} workMsTotal={total.WorkTotal}{Environment.NewLine}"));
                    _totals.Clear();
                }
            }
            foreach (var line in lines)
                try { _write(line); }
                catch { /* Diagnostics cannot affect getCurrent, timer or exit. */ }
        }
    }

    // Also used by the process-exit callback: stop collection, then flush once outside business locks.
    public void Dispose()
    {
        lock (_gate) { if (_disposed) return; _disposed = true; }
        _timer.Dispose();
        Flush();
    }
}
