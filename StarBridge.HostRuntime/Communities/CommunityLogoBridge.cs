using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Communities;

public sealed record CommunityLogoSource(string SourceRef, string PreviewImageData, int Width, int Height);

/// <summary>Native picker retains the original image. Flutter sees a bounded preview and opaque reference, never a path.</summary>
public interface ICommunityLogoPicker : IDisposable
{
    Task<CommunityLogoSource?> PickAsync(CancellationToken token);
    string Crop(string sourceRef, double x, double y, double size);
    string CropAvatar(string sourceRef, double x, double y, double size) => Crop(sourceRef, x, y, size);
    void Clear();
}

internal sealed class CommunityLogoBridge(ICommunityLogoPicker picker,
    Func<(BridgeAccountContext? Context, long Generation)> owner) : IDisposable
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private CancellationTokenSource _scope = new();
    private bool _disposed;
    internal static readonly string[] Requests = ["communities.pickLogo", "communities.cropLogo", "communities.clearLogo",
        "account.pickAvatar", "account.cropAvatar", "account.clearAvatarDraft"];

    internal async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
    {
        var entered = false;
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var current = owner();
            if (_disposed || request.MessageType != BridgeMessageTypes.Request || current.Context is null ||
                request.AccountContext != current.Context || request.SessionGeneration != current.Generation)
                return Error(request, "identityUnavailable");
            var names = request.Payload.EnumerateObject().Select(p => p.Name).ToArray();
            var crop = request.Name is "communities.cropLogo" or "account.cropAvatar";
            string[] allowed = crop ? ["schemaVersion", "sourceRef", "x", "y", "size"] : ["schemaVersion"];
            if (!Requests.Contains(request.Name) || names.Length != allowed.Length || names.Distinct().Count() != names.Length ||
                names.Except(allowed).Any() || request.Payload.GetProperty("schemaVersion").GetInt32() != 1)
                return Error(request, "invalidImage");
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(token, _scope.Token);
            entered = await _gate.WaitAsync(0, linked.Token).ConfigureAwait(false);
            if (!entered) return Error(request, "busy");
            if (current != owner() || _disposed) return Error(request, "identityUnavailable");
            object result;
            if (request.Name is "communities.pickLogo" or "account.pickAvatar")
            {
                var source = await picker.PickAsync(linked.Token).ConfigureAwait(false);
                if (source is not null && (source.PreviewImageData.Length > 700000 || source.Width <= 0 || source.Height <= 0))
                    throw new InvalidDataException();
                result = new { schemaVersion = 1, status = source is null ? "cancelled" : "selected", source };
            }
            else if (crop)
            {
                var body = request.Payload;
                var sourceRef = body.GetProperty("sourceRef").GetString() ?? "";
                var x = body.GetProperty("x").GetDouble();
                var y = body.GetProperty("y").GetDouble();
                var size = body.GetProperty("size").GetDouble();
                if (sourceRef.Length != 32 || !sourceRef.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f') ||
                    !double.IsFinite(x) || !double.IsFinite(y) || !double.IsFinite(size) ||
                    x is < 0 or > 1 || y is < 0 or > 1 || size is < .2 or > 1) throw new InvalidDataException();
                var imageData = request.Name == "account.cropAvatar"
                    ? picker.CropAvatar(sourceRef, x, y, size) : picker.Crop(sourceRef, x, y, size);
                if (imageData.Length > 700000) throw new InvalidDataException();
                result = new { schemaVersion = 1, status = "cropped", imageData };
            }
            else { picker.Clear(); result = new { schemaVersion = 1, status = "cleared" }; }
            linked.Token.ThrowIfCancellationRequested();
            if (current != owner() || _disposed) { picker.Clear(); return Error(request, "identityUnavailable"); }
            return new(BridgeEnvelope.Response(request, result), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (BridgeProtocolException) { return Error(request, "invalidImage"); }
        catch (Exception e) when (e is ArgumentException or InvalidOperationException or IOException or InvalidDataException or UnauthorizedAccessException or JsonException or KeyNotFoundException or FormatException)
        { return Error(request, "invalidImage"); }
        finally { if (entered) _gate.Release(); }
    }

    internal void Invalidate()
    {
        if (_disposed) return;
        var previous = Interlocked.Exchange(ref _scope, new CancellationTokenSource());
        previous.Cancel();
        picker.Clear();
        // A pending call may still be observing the old token. Disposal is deferred to GC.
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string error) =>
        new(BridgeEnvelope.ErrorResponse(request, new("communities." + error, "Organization image request failed.")), []);
    public void Dispose()
    {
        if (_disposed) return;
        Invalidate();
        _disposed = true;
        _scope.Cancel();
        picker.Dispose();
    }
}
