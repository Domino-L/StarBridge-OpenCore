using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Onboarding;

// Accountless mode control must not hold the Native account lease that it
// retires. This is a borrowed route, not a login or onboarding completion grant.
public sealed partial class FirstUseModeBridgeDispatcher : IBridgeRequestDispatcher
{
    public const string Capability = "onboarding.mode.v1";
    public const string ReadRequest = "onboarding.mode.read";
    public const string OfflineRequest = "onboarding.mode.offline";
    public const string HangarRequest = "onboarding.mode.hangar";
    public const string ProfileRequest = "onboarding.mode.profile";
    public const string AchievementsRequest = "onboarding.mode.achievements";
    public const string ScmAchievementsRequest = "onboarding.mode.scmAchievements";
    public const string OrganizationsCapability = "onboarding.mode.directory.v1";
    public const string OrganizationsRequest = "onboarding.mode.communities";
    public const string OrganizationMediaRequest = "onboarding.mode.communityMedia";
    public static bool Handles(string name) => name is ReadRequest or OfflineRequest or HangarRequest or ProfileRequest or AchievementsRequest or ScmAchievementsRequest or OrganizationsRequest or OrganizationMediaRequest;
    private readonly FirstUseModeRuntime _mode;
    private readonly NativeAccountRuntimeBinding _native;
    private volatile bool _disposed;
    internal FirstUseModeBridgeDispatcher(FirstUseModeRuntime mode, NativeAccountRuntimeBinding native)
    { _mode = mode; _native = native; }
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
    {
        bool Current() => !_disposed && request.SessionGeneration >= 0 && request.SessionGeneration == _mode.ControlGeneration;
        try
        {
            token.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (!Current()) return Error(request, "firstUse.context_changed");
            if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null ||
                !Handles(request.Name) || request.Payload.ValueKind != JsonValueKind.Object)
                return Error(request, "firstUse.invalid_request");
            if (request.Name == HangarRequest) return ReadHangar(request, Current);
            if (request.Name is OrganizationsRequest or OrganizationMediaRequest) return ReadOrganizations(request, Current);
            if (request.Name == ScmAchievementsRequest)
            {
                var keys = request.Payload.EnumerateObject().Select(p => p.Name).ToArray();
                if (keys.Distinct().Count() != keys.Length || keys.Any(p => p is not ("schemaVersion" or "revision" or "offset" or "snapshotId")) ||
                    request.Payload.GetProperty("schemaVersion").GetInt32() != 1) return Error(request, "firstUse.invalid_request");
                var state = _mode.Current;
                var revision = request.Payload.GetProperty("revision").GetInt64();
                if (revision != state.Revision || state.State != "offline") return Error(request, "firstUse.context_changed");
                var catalog = _mode.OfflineScmAchievements(revision);
                if (catalog is null) return Error(request, "offlineAccount.unavailable");
                var result = Achievements.ScmAchievementPages.Read(catalog,
                    request.Payload.TryGetProperty("offset", out var offset) ? offset.GetInt32() : 0,
                    request.Payload.TryGetProperty("snapshotId", out var version) ? version.GetString() : null, true);
                return Current() && _mode.Current == state ? new(BridgeEnvelope.Response(request, result, preserveRequestAccountContext: false), [])
                    : Error(request, "firstUse.context_changed");
            }
            string[] expected = request.Name == ReadRequest ? ["schemaVersion"] : ["schemaVersion", "revision"];
            var fields = request.Payload.EnumerateObject().Select(p => p.Name).ToArray();
            if (fields.Length != expected.Length || fields.Distinct(StringComparer.Ordinal).Count() != fields.Length ||
                fields.Except(expected, StringComparer.Ordinal).Any() ||
                !request.Payload.GetProperty("schemaVersion").TryGetInt32(out var schema) || schema != 1)
                return Error(request, "firstUse.invalid_request");
            var observed = _mode.Current;
            if (request.Name == AchievementsRequest)
            {
                if (!request.Payload.GetProperty("revision").TryGetInt64(out var achievementRevision) ||
                    achievementRevision != observed.Revision || observed.State != "offline")
                    return Error(request, "firstUse.context_changed");
                var achievements = _mode.OfflineAchievements(achievementRevision);
                if (achievements is null) return Error(request, "offlineAccount.unavailable");
                if (!Current() || _mode.Current != observed) return Error(request, "firstUse.context_changed");
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1,
                    achievements.Collection, achievements.CachedAtUtc }, preserveRequestAccountContext: false), []);
            }
            if (request.Name == ProfileRequest)
            {
                if (!request.Payload.GetProperty("revision").TryGetInt64(out var profileRevision) ||
                    profileRevision != observed.Revision || observed.State != "offline")
                    return Error(request, "firstUse.context_changed");
                var profile = _mode.OfflineProfile(profileRevision);
                var remote = _mode.OfflineRemoteProfile(profileRevision);
                if (profile is null && remote is null) return Error(request, "offlineAccount.unavailable");
                if (!Current() || _mode.Current != observed) return Error(request, "firstUse.context_changed");
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1,
                    revision = profile?.Revision ?? 0, savedAt = profile?.SavedAt, content = profile?.Content,
                    remote }, preserveRequestAccountContext: false), []);
            }
            if (request.Name == OfflineRequest)
            {
                if (!request.Payload.GetProperty("revision").TryGetInt64(out var revision) || revision < 0 ||
                    revision != observed.Revision || observed.State != "online")
                    return Error(request, "firstUse.context_changed");
                observed = await _mode.ApplyManualOfflineAsync(revision, Guid.NewGuid().ToString("N"),
                    _native, token).ConfigureAwait(false);
            }
            token.ThrowIfCancellationRequested();
            if (!Current() || _mode.Current != observed) return Error(request, "firstUse.context_changed");
            var payload = new Dictionary<string, object?> {
                ["schemaVersion"] = 1, ["revision"] = observed.Revision, ["state"] = observed.State,
                ["activeMode"] = observed.ActiveMode, ["publicationSuspended"] = observed.PublicationSuspended,
                ["canEnterOffline"] = _mode.CanEnterManualOffline(_native)
            };
            if (_mode.OfflineAccount is { } offlineAccount) payload["offlineAccount"] = offlineAccount;
            if (!Current() || _mode.Current != observed) return Error(request, "firstUse.context_changed");
            return new(BridgeEnvelope.Response(request, payload, preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (LocalFirstUseException error) { return Error(request, error.Code); }
        catch (Exception error) when (error is JsonException or InvalidOperationException or ArgumentException or KeyNotFoundException)
        { return Error(request, "firstUse.invalid_request"); }
        catch { return Error(request, "firstUse.mode_failed"); }
    }

    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request with { AccountContext = null },
            new(code, "Mode transition could not be confirmed.", true)), []);

    private BridgeDispatchBatch ReadHangar(BridgeEnvelope request, Func<bool> current)
    {
        var body = request.Payload;
        var fields = body.EnumerateObject().Select(p => p.Name).ToArray();
        if (fields.Distinct(StringComparer.Ordinal).Count() != fields.Length ||
            fields.Any(p => p is not ("schemaVersion" or "revision" or "inventoryRevision" or "offset" or "former")) ||
            body.GetProperty("schemaVersion").GetInt32() != 1 || !body.GetProperty("revision").TryGetInt64(out var revision))
            return Error(request, "firstUse.invalid_request");
        var offset = body.TryGetProperty("offset", out var skip) ? skip.GetInt32() : 0;
        var former = body.TryGetProperty("former", out var history) && history.GetBoolean();
        if (offset < 0 || offset > 20000) return Error(request, "firstUse.invalid_request");
        var snapshot = _mode.OfflineHangar(revision);
        if (snapshot is null) return Error(request, "offlineAccount.unavailable");
        if (body.TryGetProperty("inventoryRevision", out var expected) && expected.GetInt64() != snapshot.Revision)
            return Error(request, "hangar.revision_conflict");
        if (!current() || _mode.Current is not { State: "offline" } observed || observed.Revision != revision)
            return Error(request, "firstUse.context_changed");
        return Hangar.HangarReaderDispatcher.InventoryView(request, snapshot, offset, former);
    }
    public void Dispose() => _disposed = true;
}
