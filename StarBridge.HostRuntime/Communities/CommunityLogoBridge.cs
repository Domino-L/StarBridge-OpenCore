using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Communities;

public sealed record CommunityLogoSource(string SourceRef, string PreviewImageData, int Width, int Height);

/// <summary>Native picker retains the original image. Flutter sees a bounded preview and opaque reference, never a path.</summary>
public interface ICommunityLogoPicker : IDisposable
{
    Task<CommunityLogoSource?> PickAsync(CancellationToken token);
    bool SupportsWideImage => false;
    Task<CommunityLogoSource?> PickWideAsync(CancellationToken token) => PickAsync(token);
    string CropWide(string sourceRef, string kind, double x, double y, double width) => throw new InvalidDataException();
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
    private sealed record WideSource(string Ref, string Kind, int Width, int Height);
    private volatile WideSource? _wideSource;
    internal static readonly string[] Requests = ["communities.pickLogo", "communities.cropLogo", "communities.clearLogo",
        "account.pickAvatar", "account.cropAvatar", "account.clearAvatarDraft",
        "communities.pickWideImage", "communities.cropWideImage", "communities.clearWideImage"];

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
            var wide = request.Name is "communities.pickWideImage" or "communities.cropWideImage" or "communities.clearWideImage";
            if (wide && !picker.SupportsWideImage) return Error(request, "unavailable");
            var crop = request.Name is "communities.cropLogo" or "account.cropAvatar" or "communities.cropWideImage";
            string[] allowed = wide && crop ? ["schemaVersion", "sourceRef", "kind", "x", "y", "width"] :
                crop ? ["schemaVersion", "sourceRef", "x", "y", "size"] :
                request.Name == "communities.pickWideImage" ? ["schemaVersion", "kind"] : ["schemaVersion"];
            if (!Requests.Contains(request.Name) || names.Length != allowed.Length || names.Distinct().Count() != names.Length ||
                names.Except(allowed).Any() || request.Payload.GetProperty("schemaVersion").GetInt32() != 1)
                return Error(request, "invalidImage");
            var kind = wide && request.Name != "communities.clearWideImage" ? request.Payload.GetProperty("kind").GetString() : null;
            if (kind is not null && kind is not ("banner" or "background") ||
                wide && request.Name != "communities.clearWideImage" && kind is null) return Error(request, "invalidImage");
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(token, _scope.Token);
            entered = await _gate.WaitAsync(0, linked.Token).ConfigureAwait(false);
            if (!entered) return Error(request, "busy");
            if (current != owner() || _disposed) return Error(request, "identityUnavailable");
            object result;
            if (request.Name is "communities.pickLogo" or "account.pickAvatar" or "communities.pickWideImage")
            {
                _wideSource = null;
                var source = await (wide ? picker.PickWideAsync(linked.Token) : picker.PickAsync(linked.Token)).ConfigureAwait(false);
                if (source is not null && (source.PreviewImageData.Length > 700000 ||
                    !source.PreviewImageData.StartsWith("data:image/png;base64,", StringComparison.Ordinal) ||
                    source.Width <= 0 || source.Height <= 0 || (long)source.Width * source.Height > 16 * 1024 * 1024))
                    throw new InvalidDataException();
                if (wide && source is not null)
                {
                    if (source.SourceRef.Length != 32 || !source.SourceRef.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f'))
                        throw new InvalidDataException();
                    _wideSource = new(source.SourceRef, kind!, source.Width, source.Height);
                }
                result = new { schemaVersion = 1, status = source is null ? "cancelled" : "selected", source };
            }
            else if (crop)
            {
                var body = request.Payload;
                var sourceRef = body.GetProperty("sourceRef").GetString() ?? "";
                var x = body.GetProperty("x").GetDouble();
                var y = body.GetProperty("y").GetDouble();
                var size = body.GetProperty(wide ? "width" : "size").GetDouble();
                if (sourceRef.Length != 32 || !sourceRef.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f') ||
                    !double.IsFinite(x) || !double.IsFinite(y) || !double.IsFinite(size) ||
                    x is < 0 or > 1 || y is < 0 or > 1 || size is < .2 or > 1) throw new InvalidDataException();
                if (wide)
                {
                    var source = _wideSource;
                    var ratio = kind == "banner" ? 4.0 : 16.0 / 9;
                    if (source is null || source.Ref != sourceRef || source.Kind != kind ||
                        x + size > 1 + 1e-12 || y * source.Height + size * source.Width / ratio > source.Height + 1e-9)
                        throw new InvalidDataException();
                }
                var imageData = wide ? picker.CropWide(sourceRef, kind!, x, y, size) : request.Name == "account.cropAvatar"
                    ? picker.CropAvatar(sourceRef, x, y, size) : picker.Crop(sourceRef, x, y, size);
                if (wide)
                {
                    const string prefix = "data:image/jpeg;base64,";
                    if (imageData.Length > 2796236 || !imageData.StartsWith(prefix, StringComparison.Ordinal) ||
                        Convert.FromBase64String(imageData[prefix.Length..]).Length is 0 or > 2 * 1024 * 1024)
                        throw new InvalidDataException();
                }
                else if (imageData.Length > 700000) throw new InvalidDataException();
                result = new { schemaVersion = 1, status = "cropped", imageData };
            }
            else { _wideSource = null; picker.Clear(); result = new { schemaVersion = 1, status = "cleared" }; }
            linked.Token.ThrowIfCancellationRequested();
            if (current != owner() || _disposed) { _wideSource = null; picker.Clear(); return Error(request, "identityUnavailable"); }
            return new(BridgeEnvelope.Response(request, result), []);
        }
        catch (OperationCanceledException) { if (entered) { _wideSource = null; picker.Clear(); } return new(BridgeEnvelope.CancelledResponse(request), []); }
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
        _wideSource = null;
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
