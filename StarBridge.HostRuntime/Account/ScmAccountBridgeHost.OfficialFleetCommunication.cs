using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public Task<object> OfficialFleetCommunicationAsync(BridgeAccountContext context, JsonElement body, CancellationToken token) =>
        ObserveOfficialAnnouncement(OfficialAnnouncementStage(body), () => OfficialFleetCommunicationCoreAsync(context, body, token));

    private async Task<object> OfficialFleetCommunicationCoreAsync(BridgeAccountContext context, JsonElement body, CancellationToken token)
    {
        _ = RequireSession(context); // Official facts never use a legacy session.
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        try
        {
            if (body.ValueKind != JsonValueKind.Object || !body.TryGetProperty("schemaVersion", out var schema) ||
                schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var version) || version != 1)
                throw new AccountBridgeHostException("communities.dataInvalid");
            var publicationToken = token; var operationStarted = System.Diagnostics.Stopwatch.GetTimestamp();
            var boundedRead = body.TryGetProperty("action", out var requestedAction) && requestedAction.GetString() is "open" or "announcements" or "announcementDetail" or "chat" or "chatDetail" or "chatAuthorRenewal";
            using var operation = boundedRead ? CancellationTokenSource.CreateLinkedTokenSource(token) : null;
            operation?.CancelAfter(TimeSpan.FromSeconds(12)); if (operation is not null) token = operation.Token;
            var sourceRef = body.GetProperty("sourceRef").GetString();
            var action = body.GetProperty("action").GetString();
            if (sourceRef is null || !Regex.IsMatch(sourceRef, "^officialFleet:[1-9][0-9]{0,18}$") ||
                action is not ("open" or "announcements" or "announcementDetail" or "chat" or "chatDetail" or "chatAuthorRenewal" or "sendChat" or "markChatRead"))
                throw new AccountBridgeHostException("communities.dataInvalid");
            var values = body.EnumerateObject().Where(value => value.Name is not ("sourceRef" or "action"))
                .ToDictionary(value => value.Name, value => value.Value);
            var payload = JsonSerializer.SerializeToElement(values);
            var scope = FriendScope(context, generation) + "|" + sourceRef;
            void Current()
            {
                publicationToken.ThrowIfCancellationRequested();
                if (boundedRead && System.Diagnostics.Stopwatch.GetElapsedTime(operationStarted) >= TimeSpan.FromSeconds(12))
                    throw new OperationCanceledException("Official communication read budget expired", publicationToken);
                if (_disposed || Generation != generation) throw new BridgeStaleGenerationException(generation, Generation);
                _ = RequireSession(context);
                RequireSameRelaySession(RequireRelaySession(context), session);
            }
            Current();
            if (action == "open")
            {
                if (values.Keys.Any(key => key != "schemaVersion")) throw new AccountBridgeHostException("communities.dataInvalid");
            }
            else client.RequireOfficialFleetTarget(payload, sourceRef, scope);
            var response = await SendRelayRequestAsync<object>(session, (active, ct) => action switch
            {
                "open" => client.OpenOfficialFleetAsync(active.AccessToken, sourceRef, scope, Current, ct),
                "announcements" => client.ReadAnnouncementsAsync(active.AccessToken, payload, scope, Current, ct),
                "announcementDetail" => client.ReadAnnouncementDetailAsync(active.AccessToken, payload, scope, Current, ct),
                "chatDetail" => client.ReadChatDetailAsync(active.AccessToken, payload, scope, Current, ct),
                "chatAuthorRenewal" => client.ReadChatAuthorRenewalAsync(active.AccessToken, payload, scope, Current, ct, JsonSerializer.Serialize(context)),
                "sendChat" => client.SendChatAsync(active.AccessToken, payload, scope, Current, ct),
                "markChatRead" => client.MarkChatReadAsync(active.AccessToken, payload, scope, Current, ct),
                _ => client.ReadChatAsync(active.AccessToken, payload, scope, Current, ct, JsonSerializer.Serialize(context)),
            }, token);
            Current();
            CommitSharingSession(session, response.ActiveSession);
            return response.Result;
        }
        catch (Exception error) when (error is KeyNotFoundException or InvalidOperationException or ArgumentException or JsonException)
        {
            throw new AccountBridgeHostException("communities.dataInvalid");
        }
    }
}
