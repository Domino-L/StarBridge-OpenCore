namespace StarBridge.NativeBridge;

public interface IBridgeConnection : IAsyncDisposable
{
    ValueTask SendAsync(BridgeEnvelope envelope, CancellationToken cancellationToken = default);

    IAsyncEnumerable<BridgeEnvelope> ReadAllAsync(CancellationToken cancellationToken = default);
}

public sealed record BridgeDiagnosticEvent(
    string Code,
    string State,
    string? MessageName = null);

public interface IBridgeDiagnostics
{
    void Record(BridgeDiagnosticEvent diagnosticEvent);
}

public sealed class NullBridgeDiagnostics : IBridgeDiagnostics
{
    public static NullBridgeDiagnostics Instance { get; } = new();

    private NullBridgeDiagnostics()
    {
    }

    public void Record(BridgeDiagnosticEvent diagnosticEvent)
    {
    }
}
