namespace StarBridge.HostRuntime.Storage;

public sealed record StorageMigrationChoice(string Ticket, string Source, string Destination);

/// <summary>Host-owned, one-use confirmation. Picking is read-only; only the
/// trusted handoff delegate may schedule offline work, never a path from Flutter.</summary>
public sealed class StorageMigrationSelection
{
    private readonly Func<CancellationToken, Task<string?>> _choose;
    private readonly Func<string> _source;
    private readonly Func<string, string, CancellationToken, Task> _handoff;
    private readonly string _bootstrap;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private (StorageMigrationChoice Choice, Func<bool> Current)? _pending;

    public StorageMigrationSelection(string bootstrap, Func<string> currentSource,
        Func<CancellationToken, Task<string?>> choose,
        Func<string, string, CancellationToken, Task> trustedHandoff)
    {
        _bootstrap = StorageRootLocator.Normalize(bootstrap);
        _source = currentSource;
        _choose = choose;
        _handoff = trustedHandoff;
    }

    public async Task<StorageMigrationChoice?> ChooseAsync(Func<bool> current, CancellationToken cancellation)
    {
        if (!await _gate.WaitAsync(0, cancellation)) throw new InvalidOperationException("Storage operation in progress.");
        try
        {
            _pending = null;
            RequireCurrent(current, cancellation);
            var source = StorageRootLocator.Normalize(_source());
            var selected = await _choose(cancellation);
            RequireCurrent(current, cancellation);
            RequireSource(source);
            if (selected is null) return null;
            var destination = Validate(source, selected);
            if (Equal(source, destination)) return null;
            var choice = new StorageMigrationChoice(Guid.NewGuid().ToString("N"), source, destination);
            _pending = (choice, current);
            return choice;
        }
        finally { _gate.Release(); }
    }

    public async Task ConfirmAsync(string ticket, Func<bool> current, CancellationToken cancellation)
    {
        if (!await _gate.WaitAsync(0, cancellation)) throw new InvalidOperationException("Storage operation in progress.");
        try
        {
            RequireCurrent(current, cancellation);
            var pending = _pending;
            if (pending is null || pending.Value.Choice.Ticket != ticket)
                throw new InvalidOperationException("Unknown storage confirmation.");
            // Consume before validation/handoff: failure or an uncertain result
            // requires a fresh explicit choice, never an automatic replay.
            _pending = null;
            RequireCurrent(pending.Value.Current, cancellation);
            var choice = pending.Value.Choice;
            RequireSource(choice.Source);
            Validate(choice.Source, choice.Destination);
            await _handoff(choice.Source, choice.Destination, cancellation);
            RequireCurrent(current, cancellation);
        }
        finally { _gate.Release(); }
    }

    private string Validate(string source, string selected)
    {
        var destination = StorageMigrationDestination.Validate(source, selected);
        if (!Equal(source, _bootstrap) &&
            (Equal(destination, _bootstrap) || Nested(destination, _bootstrap) || Nested(_bootstrap, destination)))
            throw new InvalidOperationException("Destination overlaps storage controls.");
        return destination;
    }

    private void RequireSource(string expected)
    {
        // Check both active stores and the persisted locator. A changed pointer
        // cannot authorize migration from a cached, previously active root.
        if (!Equal(StorageRootLocator.Normalize(_source()), expected) ||
            !Equal(StorageRootLocator.Read(_bootstrap), expected))
            throw new InvalidOperationException("Storage root changed; choose again.");
    }

    private static void RequireCurrent(Func<bool> current, CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        if (!current()) throw new InvalidOperationException("Storage session changed.");
    }
    private static bool Equal(string left, string right) => string.Equals(left, right, StringComparison.OrdinalIgnoreCase);
    private static bool Nested(string parent, string child) => child.StartsWith(parent + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
}
