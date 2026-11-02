using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Onboarding;

// Borrowed control route: never hold the account callback lease being retired.
// Configuration stays in Native composition; the renderer supplies only revision.
public sealed class FirstUseOnlineInstallationBridgeDispatcher : IBridgeRequestDispatcher
{
    public const string Capability = "onboarding.onlineInstallation.v1";
    public const string ReadRequest = "onboarding.onlineInstallation.read";
    public const string InstallRequest = "onboarding.onlineInstallation.install";
    public static bool Handles(string name) => name is ReadRequest or InstallRequest;
    private readonly FirstUseModeRuntime _mode;
    private readonly NativeAccountRuntimeBinding _native;
    private readonly Action<AccountBridgeRuntime> _configure;
    private volatile bool _disposed;

    internal FirstUseOnlineInstallationBridgeDispatcher(FirstUseModeRuntime mode,
        NativeAccountRuntimeBinding native, Action<AccountBridgeRuntime> configure)
    { _mode = mode; _native = native; _configure = configure; }
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
    {
        try
        {
            token.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_disposed || request.SessionGeneration < 0 || request.SessionGeneration != _mode.ControlGeneration)
                return Error(request, "firstUse.context_changed");
            if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null ||
                !Handles(request.Name) || request.Payload.ValueKind != JsonValueKind.Object)
                return Error(request, "firstUse.invalid_request");
            var fields = request.Payload.EnumerateObject().Select(p => p.Name).ToArray();
            if (fields.Length != 2 || fields.Distinct(StringComparer.Ordinal).Count() != 2 ||
                fields.Except(new[] { "schemaVersion", "revision" }, StringComparer.Ordinal).Any() ||
                !request.Payload.GetProperty("schemaVersion").TryGetInt32(out var schema) || schema != 1 ||
                !request.Payload.GetProperty("revision").TryGetInt64(out var revision) || revision < 0)
                return Error(request, "firstUse.invalid_request");
            if (request.Name == InstallRequest)
                await _native.InstallConfirmedOnlineAsync(revision, _configure, token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            if (_disposed) return Error(request, "firstUse.context_changed");
            var observed = _native.ObserveOnlineInstallation(revision);
            // Installation legitimately advances control generation. Keep the
            // original correlation/generation so its observer can receive the
            // reply. The bounded next-generation fact grants no account context;
            // the client must separately reread the installed account/bootstrap.
            var payload = new Dictionary<string, object?> {
                ["schemaVersion"] = 1, ["revision"] = observed.Revision,
                ["phase"] = observed.Phase, ["controlGeneration"] = observed.ControlGeneration,
                ["modeRevision"] = observed.Mode.Revision, ["modeState"] = observed.Mode.State
            };
            if (observed.Failure is { } failure) payload["failure"] = failure;
            return new(BridgeEnvelope.Response(request, payload, preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request with { AccountContext = null }), []); }
        catch (LocalFirstUseException error) { return Error(request, error.Code); }
        catch (Exception error) when (error is JsonException or InvalidOperationException or ArgumentException or KeyNotFoundException)
        { return Error(request, "firstUse.invalid_request"); }
        catch { return Error(request, "firstUse.installation_failed"); }
    }

    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request with { AccountContext = null },
            new(code, "Online installation could not be confirmed.", true)), []);
    public void Dispose() => _disposed = true;
}
