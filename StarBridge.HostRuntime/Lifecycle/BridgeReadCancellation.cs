namespace StarBridge.HostRuntime.Lifecycle;

using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Account;

// Per connection, register before the bounded pipe queue. Only explicitly
// audited read requests participate; this never cancels login or a write.
internal sealed class BridgeReadCancellation(CancellationToken lifetime) : IAsyncDisposable
{
    private readonly object _gate = new();
    private readonly Dictionary<(long Generation, string Id), Entry> _entries = [];
    private static bool IsRead(string name) => BridgeRequestPolicy.IsActivityWait(name) || name is
        AccountBridgeRequestNames.ReadProfileDisplayCache or AccountBridgeRequestNames.GetProfileDisplayData or
        AccountBridgeRequestNames.GetProfileTimeZoneDirectory or AccountBridgeRequestNames.GetProfile or
        AccountBridgeRequestNames.GetGameIdentityPolicy or AccountBridgeRequestNames.GetCompatibilityState or
        AccountBridgeRequestNames.ReadAvatar;

    internal bool Register(BridgeEnvelope request)
    {
        if (!IsRead(request.Name)) return true;
        try {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
        } catch (BridgeProtocolException) { return true; } // Owning dispatcher reports malformed input.
        if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is null) return true;
        lock (_gate)
        {
            var key = (request.SessionGeneration, request.CorrelationId!);
            // Wait registration must not consume ordinary reads' existing budget.
            var activity = BridgeRequestPolicy.IsActivityWait(request.Name);
            var limit = activity ? NativeHostPipeServer.ActivityWaitCapacity : BridgeProtocol.DefaultQueueCapacity + 16;
            if (_entries.Values.Count(e => BridgeRequestPolicy.IsActivityWait(e.Request.Name) == activity) >= limit ||
                _entries.ContainsKey(key)) return false;
            _entries.Add(key, new(request, CancellationTokenSource.CreateLinkedTokenSource(lifetime)));
            return true;
        }
    }

    internal bool Cancel(BridgeEnvelope request)
    {
        if (request.Name != "bridge.cancel") return false;
        try {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null ||
                request.Payload.ValueKind != System.Text.Json.JsonValueKind.Object ||
                request.Payload.EnumerateObject().Count() != 1 ||
                !request.Payload.TryGetProperty("targetCorrelationId", out var target) ||
                target.ValueKind != System.Text.Json.JsonValueKind.String) return false;
            Entry? entry;
            lock (_gate) _entries.TryGetValue((request.SessionGeneration, target.GetString()!), out entry);
            return entry?.Cancel() == true;
        } catch (BridgeProtocolException) { return false; }
    }

    internal CancellationToken TokenFor(BridgeEnvelope request)
    {
        lock (_gate) return Find(request)?.Token ?? lifetime;
    }

    private Entry? Find(BridgeEnvelope request) => request.CorrelationId is { } id &&
        _entries.TryGetValue((request.SessionGeneration, id), out var entry) && ReferenceEquals(entry.Request, request)
            ? entry : null;

    internal async ValueTask CompleteAsync(BridgeEnvelope request)
    {
        Entry? entry;
        lock (_gate)
        {
            entry = Find(request);
        }
        if (entry is null) return;
        await entry.DisposeAsync().ConfigureAwait(false);
        lock (_gate) if (ReferenceEquals(Find(request), entry))
            _entries.Remove((request.SessionGeneration, request.CorrelationId!));
    }

    public async ValueTask DisposeAsync()
    {
        Entry[] entries;
        lock (_gate) { entries = _entries.Values.ToArray(); _entries.Clear(); }
        foreach (var entry in entries) await entry.DisposeAsync().ConfigureAwait(false);
    }

    private sealed class Entry(BridgeEnvelope request, CancellationTokenSource source) : IAsyncDisposable
    {
        private readonly object _gate = new();
        private Task? _cancellation;
        private bool _disposed;
        internal BridgeEnvelope Request { get; } = request;
        internal CancellationToken Token { get; } = source.Token;
        internal bool Cancel()
        {
            lock (_gate) try {
                if (_disposed) return false;
                // CancelAsync marks the token synchronously but runs callbacks
                // away from the pipe reader. The actual work retains its slot.
                _cancellation ??= Observe(source.CancelAsync());
                return true;
            } catch (ObjectDisposedException) { return false; }
        }
        private static async Task Observe(Task cancellation)
        {
            try { await cancellation.ConfigureAwait(false); }
            catch (Exception) { /* Callback failure cannot undo cancellation or close the connection. */ }
        }
        public async ValueTask DisposeAsync()
        {
            Task? cancellation;
            lock (_gate) { _disposed = true; cancellation = _cancellation; }
            if (cancellation is not null) await cancellation.ConfigureAwait(false);
            source.Dispose();
        }
    }
}
