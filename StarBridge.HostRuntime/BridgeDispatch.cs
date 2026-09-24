namespace StarBridge.HostRuntime;

using StarBridge.NativeBridge;

public sealed record BridgeDispatchBatch(
    BridgeEnvelope Response,
    IReadOnlyList<BridgeEnvelope> Events);

/// <summary>
/// The single request seam consumed by the pipe server. Feature dispatchers
/// hide protocol parsing, generation checks and response/event ordering behind
/// this interface.
/// </summary>
public interface IBridgeRequestDispatcher : IDisposable
{
    event Action<BridgeEnvelope>? EventReady;

    ValueTask<BridgeDispatchBatch> DispatchAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken = default);
}
