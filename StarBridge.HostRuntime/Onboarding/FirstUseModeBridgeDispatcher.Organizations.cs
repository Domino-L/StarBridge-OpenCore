using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Onboarding;

public sealed partial class FirstUseModeBridgeDispatcher
{
    private BridgeDispatchBatch ReadOrganizations(BridgeEnvelope request, Func<bool> current)
    {
        try
        {
            var media = request.Name == OrganizationMediaRequest;
            var fields = request.Payload.EnumerateObject().Select(property => property.Name).ToArray();
            string[] allowed = media ? ["schemaVersion", "revision", "directoryVersion", "id", "offset", "version"]
                : ["schemaVersion", "revision", "directoryVersion", "offset"];
            if (fields.Distinct(StringComparer.Ordinal).Count() != fields.Length || fields.Except(allowed).Any() ||
                request.Payload.GetProperty("schemaVersion").GetInt32() != 1)
                return Error(request, "firstUse.invalid_request");
            var revision = request.Payload.GetProperty("revision").GetInt64();
            var observed = _mode.Current;
            if (observed.State != "offline" || observed.Revision != revision) return Error(request, "firstUse.context_changed");
            bool Scope() => current() && _mode.Current == observed;
            var data = _mode.OfflineOrganizations(revision, Scope);
            if (data is null) return Error(request, "offlineAccount.unavailable");
            var payload = OfflineOrganizationProjection.Read(data, request.Payload, media);
            return Scope() ? new(BridgeEnvelope.Response(request, payload, preserveRequestAccountContext: false), [])
                : Error(request, "firstUse.context_changed");
        }
        catch (AccountBridgeHostException error) { return Error(request, error.Code); }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { return Error(request, "firstUse.invalid_request"); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or CryptographicException or ArgumentException)
        { return Error(request, "offlineAccount.unavailable"); }
    }
}
