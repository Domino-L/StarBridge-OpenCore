using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> ReadOfficialFleetShipsAsync(BridgeAccountContext context, JsonElement body, CancellationToken token)
    {
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
        budget.CancelAfter(TimeSpan.FromSeconds(12));
        var generation = Generation;
        RequireFleetReadOwner(context, generation);
        var descriptor = Volatile.Read(ref _fleetPublicSource);
        var sourceRef = body.GetProperty("sourceRef").GetString();
        if (descriptor is null || descriptor.Owner != context || descriptor.Generation != generation || descriptor.SourceRef != sourceRef)
            throw new AccountBridgeHostException("communities.identityUnavailable");
        var session = RequireRelaySession(context);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        var scope = FriendScope(context, generation) + "|" + sourceRef;
        var fields = body.EnumerateObject().Where(p => p.Name != "sourceRef").ToDictionary(p => p.Name, p => p.Value);
        var payload = JsonSerializer.SerializeToElement(fields);
        var observations = new Dictionary<long, OfficialFleetMemberIdentityObservation>();
        DateTimeOffset? projectionValidUntilUtc = null;
        void Current()
        {
            RequireFleetReadOwner(context, generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
            if (descriptor != Volatile.Read(ref _fleetPublicSource)) throw new AccountBridgeHostException("communities.identityUnavailable");
            client.RequireOfficialFleetTarget(payload, sourceRef!, scope);
            var now = _oauth.OfficialFleetIdentityObservationClock.GetUtcNow();
            if (projectionValidUntilUtc is { } deadline && now >= deadline)
                throw new AccountBridgeHostException("communities.identityUnavailable");
            OfficialFleetMemberIdentityObservation.EnsureCurrent(observations.Values, now);
        }
        async Task<IReadOnlyDictionary<string, CommunityClient.OfficialShipOwner>> Authorize(JsonElement page, CancellationToken ct)
        {
            Current();
            var lookups = page.GetProperty("ownerLookups");
            if (lookups.ValueKind != JsonValueKind.Array || lookups.GetArrayLength() > 20) throw OfficialFleetMemberIdentity.Invalid();
            var rows = new Dictionary<string, (long Id, string State, string? Callsign, string? Binding)>(StringComparer.Ordinal);
            var ids = new HashSet<long>();
            foreach (var row in lookups.EnumerateArray())
            {
                var names = row.EnumerateObject().Select(p => p.Name).ToArray();
                if (names.Length != 5 || names.Distinct().Count() != 5 || names.Any(name => name is not ("memberRef" or "memberId" or "state" or "callsign" or "identityBinding")))
                    throw OfficialFleetMemberIdentity.Invalid();
                var reference = row.GetProperty("memberRef").GetString();
                var id = row.GetProperty("memberId").GetInt64();
                var state = row.GetProperty("state").GetString();
                var callsign = row.GetProperty("callsign").GetString();
                var binding = row.GetProperty("identityBinding").GetString();
                if (reference is null || reference.Length != 64 || reference.Any(c => !char.IsAsciiHexDigit(c) || char.IsUpper(c)) ||
                    id <= 0 || !ids.Add(id) || state is not ("visible" or "restricted") ||
                    state == "restricted" && (callsign is not null || binding is not null) ||
                    !rows.TryAdd(reference, (id, state!, callsign, binding))) throw OfficialFleetMemberIdentity.Invalid();
            }
            var shipOwnerRefs = page.GetProperty("ships").EnumerateArray().Select(row => row.GetProperty("ownerMemberId").GetString()!).ToHashSet(StringComparer.Ordinal);
            if (!shipOwnerRefs.SetEquals(rows.Keys)) throw OfficialFleetMemberIdentity.Invalid();
            var fresh = await ReadFleetIdentityObservationsAsync(context, generation, sourceRef!, ids, ct);
            Current();
            var result = new Dictionary<string, CommunityClient.OfficialShipOwner>(StringComparer.Ordinal);
            foreach (var pair in rows)
            {
                var observed = fresh[pair.Value.Id];
                var identity = observed.Identity;
                if (identity.State != pair.Value.State || identity.Callsign != pair.Value.Callsign)
                    throw OfficialFleetMemberIdentity.Invalid();
                observations[pair.Value.Id] = observed;
                if (identity.State == "restricted")
                {
                    result.Add(pair.Key, new("restricted", "", null, null, null, pair.Value.Id));
                    continue;
                }
                var binding = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
                    "StarBridge.OfficialFleet.SharedShipOwner.v1\n" + sourceRef + "\n" + pair.Key + "\n" + identity.BusinessSubjectId))).ToLowerInvariant();
                if (binding != pair.Value.Binding) throw OfficialFleetMemberIdentity.Invalid();
                string? version = null;
                if (identity.AvatarImageData is { } data)
                {
                    var bytes = Convert.FromBase64String(data[(data.IndexOf(',') + 1)..]);
                    version = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
                }
                result.Add(pair.Key, new("visible", identity.Callsign!,
                    OfficialFleetMemberReference(generation, sourceRef!, identity.MemberId), identity.AvatarImageData, version, pair.Value.Id));
            }
            Current();
            return result;
        }
        try
        {
            Current();
            var response = await SendRelayRequestAsync<object>(session,
                (active, ct) => client.ReadOfficialShipsAsync(active.AccessToken, payload, sourceRef!, scope, Current, Authorize, _oauth.OfficialFleetIdentityObservationClock, ct, value => projectionValidUntilUtc = value), budget.Token);
            Current();
            var projected = JsonSerializer.SerializeToElement(response.Result);
            var visible = projected.GetProperty("owners").EnumerateArray()
                .Select(row => row.GetProperty("profileReference").GetString()).Where(value => value is not null).ToHashSet();
            var selected = observations.Values.Select(value => value.Identity).Where(identity =>
                visible.Contains(OfficialFleetMemberReference(generation, sourceRef!, identity.MemberId))).ToDictionary(identity => identity.MemberId);
            RememberFleetProfileTargets(context, generation, sourceRef!, observations.Values.Select(value => value.Identity)
                .Where(identity => identity.State != "visible").ToDictionary(identity => identity.MemberId));
            RememberFleetProfileTargets(context, generation, sourceRef!, selected);
            Current(); CommitSharingSession(session, response.ActiveSession); Current();
            return response.Result;
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        {
            ClearOfficialFleetProfileTargets();
            throw new AccountBridgeHostException("communities.identityUnavailable");
        }
        catch
        {
            ClearOfficialFleetProfileTargets();
            throw;
        }
    }
}
