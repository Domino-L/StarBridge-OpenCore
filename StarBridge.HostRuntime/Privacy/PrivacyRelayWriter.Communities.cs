using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Privacy;

internal sealed record CommunitySharingTarget(
    [property: JsonRequired] string Code,
    [property: JsonRequired] string Name,
    [property: JsonRequired] DateTimeOffset JoinedAt,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? LogoImageData = null);
internal sealed record CommunitySharingTargets(
    [property: JsonRequired] int SchemaVersion,
    [property: JsonRequired] string? PrimaryFleetCode,
    [property: JsonRequired] CommunitySharingTarget[] Communities);

internal sealed partial class PrivacyRelayWriter
{
    // This is a capability probe and authenticated membership read, never an
    // authorization migration. In particular, JoinedAt is never rebound here.
    internal async Task<CommunitySharingTargets> ReadCommunityTargetsAsync(string bearer, CancellationToken token)
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        int? status = null;
        var code = "unclassified";
        try
        {
            var result = await ReadCommunityTargetsCoreAsync(bearer, token, value => status = value);
            code = "ok";
            return result;
        }
        catch (AccountBridgeHostException error) { code = error.Code; throw; }
        catch (HttpRequestException) { code = "network"; throw; }
        catch (OperationCanceledException) { code = "cancelled"; throw; }
        finally
        {
            try { CommunityReadDiagnostic?.Invoke("relay", code, status, watch.ElapsedMilliseconds); }
            catch { /* Diagnostics must never change the request result. */ }
        }
    }

    private async Task<CommunitySharingTargets> ReadCommunityTargetsCoreAsync(string bearer, CancellationToken token, Action<int> status)
    {
        using var request = Request(HttpMethod.Get, _communityTargets, bearer);
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        status((int)response.StatusCode);
        if (response.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed or HttpStatusCode.Gone)
            throw new AccountBridgeHostException("privacy_publication.community_scopes_unavailable");
        RequireSuccess(response);
        return await ObservePublicationReceiptAsync(response, async () =>
        {
            using var document = await ReadAsync(response, token);
            try
            {
                var result = document.RootElement.Deserialize<CommunitySharingTargets>(LocalPrivacyStore.Json);
                if (result is null || result.SchemaVersion != 2 || result.Communities is null ||
                    result.Communities.Any(row => row is null || string.IsNullOrWhiteSpace(row.Name) ||
                        row.Name.Length > 256 || row.Name.Any(char.IsControl))) throw Invalid();
                CommunityRealtimeScope.ValidateAndCopy(result.Communities.Select(row =>
                    new CommunityRealtimeScope(row.Code, row.JoinedAt, 0, false, false, [])));
                if (result.PrimaryFleetCode is not null && !result.Communities.Any(row =>
                    string.Equals(row.Code, result.PrimaryFleetCode, StringComparison.OrdinalIgnoreCase))) throw Invalid();
                return result;
            }
            catch (Exception error) when (error is JsonException or ArgumentException) { throw Invalid(); }
        }, "publication-community-directory");
    }

    private async Task SendCommunitiesAsync(string bearer, JsonElement payload, CancellationToken token,
        bool membershipRetry = true, Action? current = null, PositivePublicationAdmission? admission = null)
    {
        CommunityRealtimeScope[] saved;
        try { saved = CommunityRealtimeScope.ValidateAndCopy(payload.GetProperty("communities")
            .Deserialize<CommunityRealtimeScope[]>(LocalPrivacyStore.Json)!); }
        catch (Exception error) when (error is JsonException or ArgumentException) { throw Invalid(); }
        // Removing every audience cannot add membership authority. Do not make
        // a compensating withdrawal depend on a slow/unavailable directory read.
        // The scoped POST still authenticates and requires its exact receipt.
        var clearsAllAudiences = saved.Length == 0 &&
            !payload.GetProperty("online").GetBoolean() &&
            !payload.GetProperty("roomMembersCanView").GetBoolean() &&
            payload.GetProperty("roomSharedStateFields").GetInt32() == 0 &&
            !payload.GetProperty("fleetMembersCanView").GetBoolean() &&
            !payload.GetProperty("fleetAdministratorsCanView").GetBoolean() &&
            payload.GetProperty("fleetSharedStateFields").GetInt32() == 0 &&
            !payload.GetProperty("friendsCanViewPresence").GetBoolean();
        var targets = clearsAllAudiences ? new CommunitySharingTargets(2, null, []) :
            await ReadCommunityTargetsAsync(bearer, token);
        // Departed/rejoined organizations lose their old grant; other valid
        // organizations and rooms continue without forcing a manual refresh.
        var scopes = saved.Where(scope => targets.Communities.Any(target =>
            string.Equals(scope.Code, target.Code, StringComparison.OrdinalIgnoreCase) &&
            scope.JoinedAt == target.JoinedAt)).ToArray();
        // Never downgrade an individual denial into an older all-members grant.
        const int schemaVersion = 3;
        scopes = scopes.Select(scope => scope with {
            VisibilityGroupIds = [],
            MemberOverrides = schemaVersion == 3 ? scope.MemberOverrides ?? [] : null
        }).ToArray();
        var body = JsonNode.Parse(payload.GetRawText())!.AsObject();
        body.Remove("communities");
        body["fleet"] = "No Fleet";
        body["fleetSharedStateFields"] = 0;
        body["fleetAdministratorsCanView"] = false;
        body["fleetMembersCanView"] = false;
        body["fleetVisibilityGroupIds"] = new JsonArray();
        var fields = payload.GetProperty("roomMembersCanView").GetBoolean()
            ? (PlayerSharedStateFields)payload.GetProperty("roomSharedStateFields").GetInt32() & CommunityRealtimeScope.SupportedFields : 0;
        foreach (var scope in scopes)
            fields |= scope.PotentialFields;
        if (!fields.HasFlag(PlayerSharedStateFields.Ship)) { body["ship"] = "Unknown"; body["shipConfidence"] = "None"; }
        if (!fields.HasFlag(PlayerSharedStateFields.Location))
        { body["location"] = "Unknown"; body["locationConfidence"] = "None"; body["arrivalPendingConfirmation"] = false; body["arrivalTargetCode"] = null; }
        if (!fields.HasFlag(PlayerSharedStateFields.Server)) { body["serverShard"] = null; body["serverRegion"] = null; }
        if (fields == 0) { body["online"] = false; body["liveStatus"] = "Offline"; }
        var state = JsonSerializer.SerializeToElement(body);
        using var request = Request(HttpMethod.Post, _scopedPlayers, bearer);
        request.Content = JsonContent.Create(new { schemaVersion, state, communities = scopes }, options: LocalPrivacyStore.Json);
        using var response = await SendAdmittedAsync(request, token, current, admission);
        if (response.StatusCode == HttpStatusCode.Forbidden && membershipRetry && !clearsAllAudiences)
        {
            // A leave may race the preflight read. Reconcile only a demonstrable
            // membership change, once; never retry a forbidden unchanged grant.
            var latest = await ReadCommunityTargetsAsync(bearer, token);
            if (scopes.Any(scope => !latest.Communities.Any(target =>
                string.Equals(scope.Code, target.Code, StringComparison.OrdinalIgnoreCase) && scope.JoinedAt == target.JoinedAt)))
            {
                await SendCommunitiesAsync(bearer, payload, token, membershipRetry: false, current: current, admission: admission);
                return;
            }
        }
        await RecordPublicationErrorAsync(response, token);
        RequireSuccess(response);
        await ObservePublicationReceiptAsync(response, async () =>
        {
            if (!response.Headers.TryGetValues("X-StarBridge-Realtime-Version", out var versions) ||
                !versions.SequenceEqual(new[] { schemaVersion.ToString(System.Globalization.CultureInfo.InvariantCulture) })) throw Invalid();
            using var document = await ReadAsync(response, token);
            var receipt = document.RootElement;
            if (!receipt.TryGetProperty("schemaVersion", out var version) || version.GetInt32() != schemaVersion ||
                !receipt.TryGetProperty("communities", out var confirmed) ||
                !receipt.TryGetProperty("state", out var confirmedState)) throw Invalid();
            CommunityRealtimeScope[] accepted;
            try { accepted = CommunityRealtimeScope.ValidateAndCopy(confirmed.Deserialize<CommunityRealtimeScope[]>(LocalPrivacyStore.Json)!); }
            catch (Exception error) when (error is JsonException or ArgumentException) { throw Invalid(); }
            if (!SameCommunityScopes(accepted, scopes)) throw Invalid();
            ValidateReceipt(confirmedState, state);
        });
    }

    private static bool SameCommunityScopes(CommunityRealtimeScope[] accepted, CommunityRealtimeScope[] expected) =>
        accepted.Length == expected.Length && expected.All(scope => accepted.Any(row =>
            row.Code == scope.Code && row.JoinedAt == scope.JoinedAt && row.Fields == scope.Fields &&
            row.AdministratorsCanView == scope.AdministratorsCanView && row.AllMembersCanView == scope.AllMembersCanView &&
            row.VisibilityGroupIds.Order().SequenceEqual(scope.VisibilityGroupIds.Order()) &&
            SameOverrides(row.MemberOverrides, scope.MemberOverrides)));

    private static bool SameOverrides(CommunityMemberFieldOverride[]? actual, CommunityMemberFieldOverride[]? expected) =>
        actual is null || expected is null ? actual is null && expected is null :
        actual.OrderBy(row => row.AccountId, StringComparer.Ordinal)
            .SequenceEqual(expected.OrderBy(row => row.AccountId, StringComparer.Ordinal));
}
