namespace StarBridge.HostRuntime.Support;

using System.Text.Json;
using StarBridge.NativeBridge;

public sealed class ClientLicenseBridgeDispatcher(ClientLicenseReader reader, Func<long> generation,
    TestBuildNoticeStore? notice = null)
    : IBridgeRequestDispatcher
{
    public const string RequestName = "legal.getClientLicense";
    public const string NoticeRead = "legal.readTestBuildNotice";
    public const string NoticeAccept = "legal.acceptTestBuildNotice";
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } = ["legal.clientLicense"];
    private volatile bool _disposed;
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_disposed || request.SessionGeneration != generation()) return Unavailable(request);
            if (notice is not null && request.Name is NoticeRead or NoticeAccept)
                return await DispatchNoticeAsync(request, cancellationToken).ConfigureAwait(false);
            if (request.MessageType != BridgeMessageTypes.Request || request.Name != RequestName ||
                request.AccountContext is not null || request.Payload.ValueKind != JsonValueKind.Object ||
                request.Payload.EnumerateObject().Count() != 1 ||
                !request.Payload.TryGetProperty("schemaVersion", out var schema) ||
                schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var version) || version != 1)
                return new(BridgeEnvelope.ErrorResponse(request,
                    new BridgeError(BridgeErrorCodes.InvalidEnvelope, "Invalid license request.")), []);
            var document = await reader.ReadAsync(cancellationToken).ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();
            if (_disposed || request.SessionGeneration != generation()) return Unavailable(request);
            return new(BridgeEnvelope.Response(request, new Dictionary<string, object?>
            {
                ["schemaVersion"] = 1, ["state"] = document.State, ["text"] = document.Text
            }, preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch { return Unavailable(request); }
    }

    private async Task<BridgeDispatchBatch> DispatchNoticeAsync(BridgeEnvelope request, CancellationToken token)
    {
        var body = request.Payload;
        var accepting = request.Name == NoticeAccept;
        if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null ||
            body.ValueKind != JsonValueKind.Object || body.EnumerateObject().Count() != (accepting ? 2 : 1) ||
            body.GetProperty("schemaVersion").GetInt32() != 1 ||
            accepting && body.GetProperty("termsVersion").GetString() != TestBuildNoticeStore.TermsVersion)
            return Unavailable(request);
        var document = await reader.ReadAsync(token).ConfigureAwait(false);
        bool Current() => !_disposed && !token.IsCancellationRequested && request.SessionGeneration == generation();
        if (!Current() || document.State != "ready" || document.Text is null) return Unavailable(request);
        if (accepting) notice!.Acknowledge(TestBuildNoticeStore.TermsVersion, document.Text, Current);
        return new(BridgeEnvelope.Response(request, new {
            schemaVersion = 1, termsVersion = TestBuildNoticeStore.TermsVersion,
            acknowledged = notice!.IsAcknowledged()
        }, preserveRequestAccountContext: false), []);
    }

    private static BridgeDispatchBatch Unavailable(BridgeEnvelope request) => new(
        BridgeEnvelope.ErrorResponse(request, new BridgeError("legal.unavailable", "License unavailable.", true)), []);
    public void Dispose() => _disposed = true;
}
