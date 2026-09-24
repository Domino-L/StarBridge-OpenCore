using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.Core.Events;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Privacy;

internal sealed record EventSharingRemoteSnapshot(
    [property: JsonRequired] int SchemaVersion,
    [property: JsonRequired] long Revision,
    [property: JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? OperationId,
    [property: JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? AppliedAt,
    [property: JsonRequired] bool PublicationEnabled,
    [property: JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.Never)] SharedEventPreferences? Settings);

internal sealed partial class PrivacyRelayWriter
{
    internal async Task<EventSharingRemoteSnapshot> ReadEventsAsync(string bearer, CancellationToken token)
    {
        using var request = Request(HttpMethod.Get, _eventSettings, bearer);
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        RequireEventSuccess(response);
        try
        {
            using var document = await ReadAsync(response, token);
            return ParseEvents(document.RootElement);
        }
        catch (AccountBridgeHostException error) when (error.Code == "privacy_publication.response_invalid")
        { throw new AccountBridgeHostException("events.response_invalid"); }
        catch (JsonException)
        { throw new AccountBridgeHostException("events.response_invalid"); }
    }

    internal async Task<EventSharingRemoteSnapshot> SaveEventsAsync(string bearer, long expectedRevision,
        string operationId, bool publicationEnabled, SharedEventPreferences settings,
        Action ensureCurrent, CancellationToken token)
    {
        if (expectedRevision < 0 || expectedRevision == long.MaxValue || !Guid.TryParseExact(operationId, "N", out _))
            throw new AccountBridgeHostException("events.invalid_request");
        if (settings is null) throw new AccountBridgeHostException("events.invalid_request");
        try { settings = settings.ValidatedCopy(); }
        catch (ArgumentException)
        { throw new AccountBridgeHostException("events.invalid_request"); }
        bool Matches(EventSharingRemoteSnapshot value) => value.Revision == expectedRevision + 1 &&
            value.OperationId == operationId && value.PublicationEnabled == publicationEnabled &&
            JsonSerializer.Serialize(value.Settings, LocalPrivacyStore.Json) == JsonSerializer.Serialize(settings, LocalPrivacyStore.Json);
        ensureCurrent();
        token.ThrowIfCancellationRequested();
        try
        {
            using var request = Request(HttpMethod.Post, _eventSettings, bearer);
            request.Content = JsonContent.Create(new { schemaVersion = 1, expectedRevision, operationId, publicationEnabled, settings }, options: LocalPrivacyStore.Json);
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            ensureCurrent();
            RequireEventSuccess(response);
            using var document = await ReadAsync(response, token);
            var result = ParseEvents(document.RootElement);
            ensureCurrent();
            if (!Matches(result)) throw new AccountBridgeHostException("events.response_invalid");
            return result;
        }
        catch (Exception error) when (error is HttpRequestException || error is OperationCanceledException && !token.IsCancellationRequested ||
            error is AccountBridgeHostException { Code: "events.response_invalid" or "privacy_publication.response_invalid" or "events.temporarily_unavailable" } || error is JsonException)
        {
            // One write only. A lost/malformed receipt gets one bounded readback,
            // never another POST. A later competing revision is not our success.
            ensureCurrent();
            token.ThrowIfCancellationRequested();
            try
            {
                var current = await ReadEventsAsync(bearer, token);
                ensureCurrent();
                if (Matches(current)) return current;
            }
            catch (Exception readError) when (readError is HttpRequestException or JsonException ||
                readError is OperationCanceledException && !token.IsCancellationRequested ||
                readError is AccountBridgeHostException { Code: "events.response_invalid" or "events.temporarily_unavailable" }) { }
            throw new AccountBridgeHostException("events.write_unconfirmed");
        }
    }

    private static EventSharingRemoteSnapshot ParseEvents(JsonElement root)
    {
        try
        {
            var result = root.Deserialize<EventSharingRemoteSnapshot>(LocalPrivacyStore.Json);
            if (result is null || result.SchemaVersion != 1 || result.Revision < 0 ||
                (result.Revision == 0 ? result.OperationId is not null || result.AppliedAt is not null || result.Settings is not null || result.PublicationEnabled :
                    !Guid.TryParseExact(result.OperationId, "N", out _) || result.AppliedAt is null ||
                    result.AppliedAt <= DateTimeOffset.UnixEpoch || result.Settings is null)) throw new JsonException();
            return result with { Settings = result.Settings?.ValidatedCopy() };
        }
        catch (Exception error) when (error is JsonException or ArgumentException)
        { throw new AccountBridgeHostException("events.response_invalid"); }
    }

    private static void RequireEventSuccess(HttpResponseMessage response)
    {
        if (response.StatusCode == HttpStatusCode.OK) return;
        throw new AccountBridgeHostException(response.StatusCode switch
        {
            HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed or HttpStatusCode.Gone => "events.unavailable",
            HttpStatusCode.Unauthorized => "events.identity_unavailable",
            HttpStatusCode.Forbidden => "events.forbidden",
            HttpStatusCode.Conflict => "events.conflict",
            HttpStatusCode.PreconditionRequired => "events.identity_required",
            HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests or HttpStatusCode.InternalServerError or
                HttpStatusCode.BadGateway or HttpStatusCode.ServiceUnavailable or HttpStatusCode.GatewayTimeout => "events.temporarily_unavailable",
            _ => "events.response_invalid"
        });
    }
}
