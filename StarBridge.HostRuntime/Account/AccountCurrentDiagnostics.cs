namespace StarBridge.HostRuntime.Account;

using System.Diagnostics;

internal enum CurrentProjectionReason
{
    none, pendingEvents, projectionUnsupported, hostDeclined, gateDisposed,
    gateBarrierRunning, gateNonReorderableQueued, noLastFull, hostDisposed,
    businessStartupDeferred, restoreNotAttempted, reauthRequired,
    credentialTemporary, legacyUnavailable, participantLoopOff, ageNegative,
    ageExpired, ownerContextMissing, ownerBindingMissing, ownerAuthenticationChanged,
    ownerGenerationChanged, ownerStale, projectionChanged
}

// Only closed enums and counts cross this boundary. Never accepts request/account data.
internal sealed class AccountCurrentDiagnostics : IDisposable
{
    private static readonly AccountCurrentDiagnosticSummary Summary = CreateSummary();

    private static AccountCurrentDiagnosticSummary CreateSummary()
    {
        var summary = new AccountCurrentDiagnosticSummary(WriteLine);
        AppDomain.CurrentDomain.ProcessExit += (_, _) => summary.Dispose();
        return summary;
    }

    internal static void Flush() => Summary.Flush();
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private long _waitStart;
    private long _workStart;
    private bool _waiting;
    private bool _working;
    internal bool Projected;
    internal CurrentProjectionReason Reason = CurrentProjectionReason.projectionUnsupported;
    internal int Readers;
    internal int QueuedShared;
    internal void Waiting() { _waiting = true; _working = false; _waitStart = _clock.ElapsedMilliseconds; }
    internal void Working() { _working = true; _workStart = _clock.ElapsedMilliseconds; }

    public void Dispose()
    {
        var end = _clock.ElapsedMilliseconds;
        var wait = _waiting ? (_working ? _workStart : end) - _waitStart : 0;
        var work = _working ? end - _workStart : 0;
        try { Summary.Record(Projected, Reason, wait, work, Readers, QueuedShared); }
        catch { /* Diagnostics never change a response or an exception. */ }
    }

    private static void WriteLine(string line)
    {
        var directory = Path.GetFullPath(HostDataRoot.CurrentRoot);
        for (var parent = new DirectoryInfo(directory); parent is not null; parent = parent.Parent)
            if (parent.Exists && parent.Attributes.HasFlag(FileAttributes.ReparsePoint)) return;
        var path = Path.Combine(directory, "account-current-diagnostics.log");
        if (File.Exists(path) && File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)) return;
        Directory.CreateDirectory(directory);
        var mode = File.Exists(path) && new FileInfo(path).Length >= 128 * 1024 ? FileMode.Create : FileMode.Append;
        // A best-effort background diagnostic must not block root retirement or test cleanup.
        using var stream = OpenLogStream(path, mode);
        using var writer = new StreamWriter(stream);
        writer.Write(line);
    }

    internal static FileStream OpenLogStream(string path, FileMode mode) =>
        new(path, mode, FileAccess.Write, FileShare.Read | FileShare.Delete);
}
