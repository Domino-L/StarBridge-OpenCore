using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;
namespace StarBridge.HostRuntime.Achievements;

/// <summary>Independent image selection; never reads or changes an avatar/community draft.</summary>
internal sealed class AchievementIdeaImageBridge(ICommunityLogoPicker picker,
    Func<(BridgeAccountContext? Context, long Generation)> owner) : IDisposable
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private CancellationTokenSource _scope = new();
    private bool _disposed;
    internal async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token)
    {
        var entered = false;
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var current = owner();
            if (_disposed || request.MessageType != BridgeMessageTypes.Request || current.Context is null ||
                request.AccountContext != current.Context || request.SessionGeneration != current.Generation)
                return Error(request, "ideas.account_changed");
            if (request.Name != "achievementIdeas.pickImage" || request.Payload.ValueKind != JsonValueKind.Object ||
                request.Payload.EnumerateObject().Count() != 1 || request.Payload.GetProperty("schemaVersion").GetInt32() != 1)
                return Error(request, "ideas.invalid_request");
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(token, _scope.Token);
            entered = await _gate.WaitAsync(0, linked.Token);
            if (!entered) return Error(request, "ideas.busy");
            var source = await picker.PickAsync(linked.Token);
            linked.Token.ThrowIfCancellationRequested();
            if (_disposed || current != owner()) return Error(request, "ideas.account_changed");
            if (source is not null && (source.PreviewImageData.Length > 700000 ||
                !source.PreviewImageData.StartsWith("data:image/png;base64,", StringComparison.Ordinal)))
                return Error(request, "ideas.invalid_image");
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1,
                status = source is null ? "cancelled" : "selected", imageData = source?.PreviewImageData }), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (Exception error) when (error is BridgeProtocolException or ArgumentException or InvalidOperationException or IOException or JsonException or KeyNotFoundException)
        { return Error(request, "ideas.invalid_image"); }
        finally { if (entered) { picker.Clear(); _gate.Release(); } }
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "Achievement image request failed.")), []);
    internal void Invalidate()
    {
        if (_disposed) return;
        Interlocked.Exchange(ref _scope, new()).Cancel(); picker.Clear();
    }
    public void Dispose() { if (_disposed) return; Invalidate(); _disposed = true; _scope.Cancel(); picker.Dispose(); }
}
