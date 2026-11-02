using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private const string RetainedDataRequest = "account.offlineData.read";

    private BridgeDispatchBatch ReadRetainedData(BridgeEnvelope request, CancellationToken token)
    {
        BridgeDispatchBatch Error(string code) => new(BridgeEnvelope.ErrorResponse(request with { AccountContext = null },
            new(code, "Retained account data is unavailable. Refresh account status and try again.", true)), []);
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null || request.Payload.ValueKind != JsonValueKind.Object)
                return Error("offlineAccount.invalid_request");
            var body = request.Payload;
            var fields = body.EnumerateObject().Select(p => p.Name).ToArray();
            if (fields.Distinct(StringComparer.Ordinal).Count() != fields.Length ||
                body.GetProperty("schemaVersion").GetInt32() != 1 ||
                body.GetProperty("readId").GetString() is not { } id || !Guid.TryParseExact(id, "N", out _) ||
                body.GetProperty("kind").GetString() is not ("hangar" or "profile" or "achievements" or "scmAchievements" or "communities" or "communityMedia" or "friends"))
                return Error("offlineAccount.invalid_request");
            var kind = body.GetProperty("kind").GetString();
            string[] allowed = kind switch {
                "scmAchievements" => ["schemaVersion", "readId", "kind", "offset", "snapshotId"],
                "hangar" => ["schemaVersion", "readId", "kind", "offset", "former", "inventoryRevision"],
                "communities" => ["schemaVersion", "readId", "kind", "offset", "directoryVersion"],
                "communityMedia" => ["schemaVersion", "readId", "kind", "offset", "directoryVersion", "id", "version"],
                "friends" => ["schemaVersion", "readId", "kind", "pagedResponse", "offset", "snapshotId"],
                _ => ["schemaVersion", "readId", "kind"]
            };
            if (fields.Except(allowed).Any()) return Error("offlineAccount.invalid_request");
            var resolved = ResolveRetainedRead(id, request, token);
            if (resolved is not { } access || _offlineAccount is null)
                return Error("offlineAccount.context_changed");
            bool Current() => access.Current();
            if (!Current()) return Error("offlineAccount.context_changed");
            if (kind is "communities" or "communityMedia")
            {
                var directory = _offlineAccount.ReadSelectedOrganizations(access.Owner, Current);
                if (directory is null) return Error("offlineAccount.unavailable");
                var projection = OfflineOrganizationProjection.Read(directory, body, kind == "communityMedia");
                return Current() ? new(BridgeEnvelope.Response(request, projection, preserveRequestAccountContext: false), [])
                    : Error("offlineAccount.context_changed");
            }
            if (kind == "hangar")
            {
                var offset = body.TryGetProperty("offset", out var skip) ? skip.GetInt32() : 0;
                var former = body.TryGetProperty("former", out var history) && history.GetBoolean();
                if (offset < 0 || offset > 20000) return Error("offlineAccount.invalid_request");
                var snapshot = _offlineAccount.ReadSelectedHangar(access.Owner, Current);
                if (snapshot is null) return Error("offlineAccount.unavailable");
                if (body.TryGetProperty("inventoryRevision", out var revision) && revision.GetInt64() != snapshot.Revision)
                    return Error("hangar.revision_conflict");
                var result = Hangar.HangarReaderDispatcher.InventoryView(request, snapshot, offset, former);
                return Current() ? result : Error("offlineAccount.context_changed");
            }
            object payload;
            if (kind == "scmAchievements")
            {
                var data = _offlineAccount.ReadSelectedScmAchievements(access.Owner, Current);
                if (data is null) return Error("offlineAccount.unavailable");
                payload = Achievements.ScmAchievementPages.Read(data,
                    body.TryGetProperty("offset", out var offset) ? offset.GetInt32() : 0,
                    body.TryGetProperty("snapshotId", out var version) ? version.GetString() : null, true);
            }
            else if (kind == "friends")
            {
                payload = ReadRetainedFriends(request, id, access.Owner, Current);
            }
            else if (kind == "profile")
            {
                var data = _offlineAccount.ReadSelectedProfile(access.Owner, Current);
                if (data is null || data.Local is null && data.Remote is null) return Error("offlineAccount.unavailable");
                payload = new { schemaVersion = 1, revision = data.Local?.Revision ?? 0,
                    savedAt = data.Local?.SavedAt, content = data.Local?.Content, remote = data.Remote };
            }
            else
            {
                var data = _offlineAccount.ReadSelectedAchievements(access.Owner, Current);
                if (data is null) return Error("offlineAccount.unavailable");
                payload = new { schemaVersion = 1, data.Collection, data.CachedAtUtc };
            }
            var response = new BridgeDispatchBatch(BridgeEnvelope.Response(request, payload, preserveRequestAccountContext: false), []);
            return Current() ? response : Error("offlineAccount.context_changed");
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or ArgumentException or KeyNotFoundException or FormatException or OverflowException)
        { return Error("offlineAccount.invalid_request"); }
        catch (BridgeProtocolException) { return Error("offlineAccount.invalid_request"); }
        catch (AccountBridgeHostException error) { return Error(error.Code); }
        catch (Exception error) when (CacheFailure(error)) { return Error("offlineAccount.unavailable"); }
    }
}
