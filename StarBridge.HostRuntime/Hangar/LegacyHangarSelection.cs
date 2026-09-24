using StarBridge.Core.Hangar;

namespace StarBridge.HostRuntime.Hangar;

public interface ILegacyHangarFilePicker
{
    Task<string?> PickAsync(string locale, CancellationToken token);
}

internal sealed record LegacyHangarSelectionInfo(string State, string? SelectionRef = null, string? FileName = null);

// User confirmation declares ownership; it is not server identity evidence or import consent.
// No file content is opened before confirmation. Only the native picker can supply a path.
internal sealed class LegacyHangarSelection(ILegacyHangarFilePicker picker,
    Func<(MigrationOwner? Owner, long Generation)> current, Func<bool> hasStorageLease,
    TimeProvider? clock = null) : IDisposable
{
    private readonly object _gate = new();
    private readonly TimeProvider _clock = clock ?? TimeProvider.System;
    private CancellationTokenSource _scope = new();
    private string? _path, _reference;
    private (MigrationOwner? Owner, long Generation) _owner;
    private DateTimeOffset _expires;
    private LegacyHangarFileResult? _snapshot;
    private bool _disposed;

    internal async Task<LegacyHangarSelectionInfo> SelectAsync(string locale, CancellationToken token)
    {
        CancellationTokenSource linked;
        (MigrationOwner? Owner, long Generation) owner;
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            Invalidate();
            owner = current();
            if (_disposed || owner.Owner is null || !hasStorageLease()) throw new InvalidOperationException();
            linked = CancellationTokenSource.CreateLinkedTokenSource(token, _scope.Token);
        }
        using (linked)
        {
            var path = await picker.PickAsync(locale, linked.Token);
            lock (_gate)
            {
                linked.Token.ThrowIfCancellationRequested();
                if (_disposed || current() != owner || !hasStorageLease()) throw new InvalidOperationException();
                if (path is null) return new("cancelled");
                if (!Path.IsPathFullyQualified(path) || path.StartsWith(@"\\", StringComparison.Ordinal) ||
                    path.IndexOf(':', 2) >= 0 || !string.Equals(Path.GetExtension(path), ".database", StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException();
                _path = Path.GetFullPath(path);
                _owner = owner;
                _reference = Guid.NewGuid().ToString("N");
                _expires = _clock.GetUtcNow().AddMinutes(5);
                return new("selected", _reference, Path.GetFileName(_path));
            }
        }
    }

    internal LegacyHangarFileResult Confirm(string reference, bool belongsToCurrentAccount)
    {
        lock (_gate)
        {
            Require(reference);
            if (!belongsToCurrentAccount) throw new InvalidOperationException();
            // Repeated reads use one immutable snapshot, never silently reread a changed file.
            return _snapshot ??= LegacyHangarMigrationFile.Inspect(_path!, _owner.Owner!);
        }
    }

    internal LegacyHangarFileResult Read(string reference)
    {
        lock (_gate)
        {
            Require(reference);
            return _snapshot ?? throw new InvalidOperationException();
        }
    }

    internal void Clear(string reference)
    {
        lock (_gate) { if (_reference == reference) Invalidate(); }
    }

    private void Require(string reference)
    {
        if (_disposed || _path is null || _reference != reference || current() != _owner ||
            _owner.Owner is null || _clock.GetUtcNow() >= _expires || !hasStorageLease())
        {
            Invalidate();
            throw new InvalidOperationException();
        }
    }

    internal void Invalidate()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _scope.Cancel();
            _scope.Dispose();
            _scope = new();
            _path = _reference = null;
            _snapshot = null;
            _owner = default;
        }
    }
    public void Dispose()
    {
        lock (_gate) { if (_disposed) return; Invalidate(); _disposed = true; _scope.Dispose(); }
    }
}
