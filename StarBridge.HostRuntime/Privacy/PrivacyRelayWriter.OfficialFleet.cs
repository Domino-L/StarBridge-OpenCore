using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Privacy;

internal sealed record OfficialRealtimeConsentWire(string OwnerSubject, OfficialFleetRealtimeTarget Target,
    PlayerSharedStateFields Fields, string Revision, string OperationId,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull), JsonNumberHandling(JsonNumberHandling.Strict)]
    int? MaximumRankValue = null);
internal sealed record OfficialRealtimeContextWire(int SchemaVersion, string SourceRef, OfficialFleetRealtimeTarget Target,
    OfficialRealtimeConsentWire? Consent, string ExpectedRevision, bool WritesAvailable, bool AudienceRankSupported = false);
internal sealed partial class PrivacyRelayWriter
{
    private Uri OfficialUri(string operation) => new(_players, "/api/official-fleets/realtime/" + operation);
    internal async Task<OfficialRealtimeContextWire> ReadOfficialRealtimeContextAsync(string bearer, CancellationToken token)
    {
        using var request = Request(HttpMethod.Get, OfficialUri("context"), bearer);
        request.Headers.Add("X-StarBridge-Official-Audience", "1");
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        RequireSuccess(response);
        return await ObservePublicationReceiptAsync(response, async () =>
        {
            using var data = await ReadAsync(response, token);
            try {
                var value = data.RootElement.Deserialize<OfficialRealtimeContextWire>(LocalPrivacyStore.Json);
                if (value is null || value.SchemaVersion != 4 || !value.Target.IsValid ||
                    value.SourceRef != "officialFleet:" + value.Target.OrganizationId ||
                    value.ExpectedRevision != (value.Consent?.Revision ?? "initial")) throw Invalid();
                return value;
            } catch (JsonException) { throw Invalid(); }
        }, "publication-official-context");
    }
    private async Task<OfficialRealtimeConsentWire?> ReadOwnOfficialConsentAsync(string bearer, CancellationToken token)
    {
        using var request = Request(HttpMethod.Get, OfficialUri("consent"), bearer);
        request.Headers.Add("X-StarBridge-Official-Audience", "1");
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        RequireSuccess(response);
        return await ObservePublicationReceiptAsync(response, async () =>
        {
            using var data = await ReadAsync(response, token);
            return ReadConsent(data.RootElement);
        }, "publication-official-consent-read");
    }
    private static OfficialRealtimeConsentWire? ReadConsent(JsonElement root)
    {
        if (root.GetProperty("schemaVersion").GetInt32() != 4 || root.EnumerateObject().Count() != 2) throw Invalid();
        var row = root.GetProperty("consent");
        if (row.ValueKind == JsonValueKind.Null) return null;
        try {
            var result = row.Deserialize<OfficialRealtimeConsentWire>(LocalPrivacyStore.Json);
            if (result is null || !result.Target.IsValid || !Guid.TryParseExact(result.Revision, "N", out _) ||
                !Guid.TryParseExact(result.OperationId, "N", out _) || (result.Fields & ~CommunityRealtimeScope.SupportedFields) != 0 ||
                result.MaximumRankValue is not (null or >= 1 and <= 4))
                throw Invalid();
            return result;
        } catch (JsonException) { throw Invalid(); }
    }
    private async Task SendOfficialFleetAsync(string bearer, JsonElement payload, CancellationToken token, Action? current,
        bool allowOfficialPositive, PositivePublicationAdmission? admission)
    {
        var choice = payload.GetProperty("officialFleet").Deserialize<OfficialFleetRealtimeChoice>(LocalPrivacyStore.Json);
        if (choice is not { IsValid: true }) throw Invalid();
        var positive = payload.GetProperty("online").GetBoolean() && choice.Fields != PlayerSharedStateFields.None &&
            (payload.GetProperty("appPresenceConfirmed").GetBoolean() || payload.GetProperty("gameObserved").GetBoolean());
        if (positive && !allowOfficialPositive) throw new AccountBridgeHostException("official_fleet.runtime_unavailable");
        // A refreshed remote revision is never adopted to replay an older local choice.
        var clearing = IsCompleteWithdrawal(payload);
        if (choice.MaximumRankValue is not null && !clearing &&
            !(await ReadOfficialRealtimeContextAsync(bearer, token)).AudienceRankSupported)
            throw new AccountBridgeHostException("official_fleet.audience_unsupported");
        var consent = await ReadOwnOfficialConsentAsync(bearer, token);
        var initialWithdrawal = consent is null && clearing;
        var existingWithdrawal = clearing && consent?.Target == choice.Target;
        if (!initialWithdrawal && !existingWithdrawal && (consent is null || consent.OperationId != choice.OperationId || consent.Target != choice.Target || consent.Fields != choice.Fields || consent.MaximumRankValue != choice.MaximumRankValue))
        {
            var decreasing = consent is not null && consent.Target == choice.Target && (choice.Fields & ~consent.Fields) == 0 &&
                (choice.Fields == PlayerSharedStateFields.None ||
                OfficialFleetRealtimeChoice.AudienceIsSubset(choice.MaximumRankValue, consent.MaximumRankValue) &&
                (choice.Fields != consent.Fields || choice.MaximumRankValue != consent.MaximumRankValue));
            // Offline/Stop never creates or restores positive consent. A configuration
            // outage may only keep an exact existing grant or perform real authority decrease.
            if (!decreasing && choice.Fields != PlayerSharedStateFields.None && (!allowOfficialPositive || !positive))
                throw new AccountBridgeHostException("official_fleet.runtime_unavailable");
            using var save = Request(HttpMethod.Put, OfficialUri("consent"), bearer);
            save.Headers.Add("X-StarBridge-Official-Audience", "1");
            var command = decreasing ? choice with { ExpectedServerRevision = consent!.Revision } : choice;
            // Refreshing a revision is allowed only for exact-target authority decrease, never positive replay.
            save.Content = JsonContent.Create(new { schemaVersion = 4, choice = command });
            using var saved = await SendAdmittedAsync(save, token, current, admission);
            RequireSuccess(saved);
            await ObservePublicationReceiptAsync(saved, async () =>
            {
                using var document = await ReadAsync(saved, token);
                consent = ReadConsent(document.RootElement);
            }, "publication-official-consent-save");
            // This check can fail only after a save: otherwise consent already
            // matched the choice, or an initial/existing withdrawal bypassed it.
            await ObservePublicationReceiptAsync(saved, () =>
            {
                if (consent is null || consent.Target != choice.Target || consent.Fields != choice.Fields ||
                    consent.OperationId != choice.OperationId || consent.MaximumRankValue != choice.MaximumRankValue) throw Invalid();
                return Task.CompletedTask;
            }, "publication-official-consent-check");
        }
        var revision = initialWithdrawal ? "initial" : consent!.Revision;
        var state = JsonNode.Parse(payload.GetRawText())!.AsObject();
        if (PrivacyPublicationPayload.IsOfficialAppOnly(payload)) { state["name"] = ""; state["callsign"] = null; }
        CommunityRealtimeScope[] communities;
        try {
            var saved = payload.TryGetProperty("communities", out var scopes)
                ? scopes.Deserialize<CommunityRealtimeScope[]>(LocalPrivacyStore.Json) : [];
            communities = CommunityRealtimeScope.ValidateAndCopy(saved!).Select(scope => scope with {
                VisibilityGroupIds = [], MemberOverrides = scope.MemberOverrides ?? []
            }).ToArray();
        } catch (Exception error) when (error is JsonException or ArgumentException) { throw Invalid(); }
        var app = payload.GetProperty("appPresenceConfirmed").GetBoolean();
        var playing = payload.GetProperty("gameObserved").GetBoolean();
        var hasServerSession = payload.GetProperty("hasServerSession").Deserialize<bool?>();
        foreach (var key in new[] { "officialFleet", "communities", "appPresenceConfirmed", "gameObserved", "hasServerSession", "gameVersion" }) state.Remove(key);
        state["sharedEventTypes"] = 0;
        if ((state["fleetSharedStateFields"]?.GetValue<int>() ?? 0) != 0 || state["fleetMembersCanView"]?.GetValue<bool>() == true ||
            state["fleetAdministratorsCanView"]?.GetValue<bool>() == true)
            throw new AccountBridgeHostException("privacy_publication.protocol_upgrade_required");
        using var request = Request(HttpMethod.Post, OfficialUri("publish"), bearer);
        var sent = JsonSerializer.SerializeToElement(state);
        request.Content = JsonContent.Create(new { schemaVersion = 4, state = sent, communities, target = choice.Target,
            consentRevision = revision, appPresenceConfirmed = app, gameObserved = playing, hasServerSession });
        using var response = await SendAdmittedAsync(request, token, current, admission);
        await RecordPublicationErrorAsync(response, token);
        RequireSuccess(response);
        await ObservePublicationReceiptAsync(response, async () =>
        {
            if (!response.Headers.TryGetValues("X-StarBridge-Realtime-Version", out var versions) || !versions.SequenceEqual(new[] { "4" })) throw Invalid();
            using var receipt = await ReadAsync(response, token);
            var root = receipt.RootElement;
            CommunityRealtimeScope[] accepted, expected;
            try {
                accepted = CommunityRealtimeScope.ValidateAndCopy(root.GetProperty("communities").Deserialize<CommunityRealtimeScope[]>(LocalPrivacyStore.Json)!);
                expected = communities;
            } catch (Exception error) when (error is JsonException or ArgumentException) { throw Invalid(); }
            if (root.GetProperty("schemaVersion").GetInt32() != 4 || root.EnumerateObject().Count() != 4 ||
                root.GetProperty("officialAudience").EnumerateObject().Count() != 3 ||
                root.GetProperty("officialAudience").GetProperty("withdrawOnly").GetBoolean() != !positive ||
                root.GetProperty("officialAudience").GetProperty("consentRevision").GetString() != revision ||
                root.GetProperty("officialAudience").GetProperty("target").Deserialize<OfficialFleetRealtimeTarget>(LocalPrivacyStore.Json) != choice.Target ||
                !SameCommunityScopes(accepted, expected)) throw Invalid();
            ValidateReceipt(root.GetProperty("state"), sent);
        });
        current?.Invoke();
    }
}
