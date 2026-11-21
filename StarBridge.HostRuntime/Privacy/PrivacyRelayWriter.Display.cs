using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Privacy;

/// <summary>Relay r49 SCM display settings: one callsign and the game ID locations,
/// sharing one revision and one identity stamp (section=callsign / section=game-id).</summary>
internal sealed record ScmDisplaySettings(
    [property: JsonRequired] int SchemaVersion, [property: JsonRequired] long Revision,
    string? Callsign, [property: JsonRequired] int Locations, [property: JsonRequired] bool CanConfigure,
    [property: JsonRequired] string IdentityStamp);

internal sealed partial class PrivacyRelayWriter
{
    // Same rules as legacy accounts: trim, blank clears, CJK counts 2, at most 10.
    // Weight counts UTF-16 units, exactly like the Relay (GetCallsignWeight).
    internal static string? NormalizeDisplayCallsign(string? value)
    {
        var trimmed = value?.Trim();
        if (string.IsNullOrEmpty(trimmed)) return null;
        if (CallsignWeight(trimmed) > 10 || trimmed.Any(char.IsControl)) throw new AccountBridgeHostException("callsign.invalid");
        return trimmed;
    }

    internal static int CallsignWeight(string value) => value.Sum(c =>
        c is >= '一' and <= '鿿' or >= '㐀' and <= '䶿' or >= '豈' and <= '﫿' ? 2 : 1);

    internal async Task<ScmDisplaySettings> ReadDisplayAsync(string bearer, CancellationToken token)
    {
        using var request = Request(HttpMethod.Get, new Uri(_players, "/api/auth/session?section=callsign"), bearer);
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        await RequireDisplaySuccessAsync(response, token);
        using var document = await ReadAsync(response, token);
        return ParseDisplay(document.RootElement);
    }

    private static ScmDisplaySettings ParseDisplay(JsonElement root)
    {
        LocalPrivacyStore.RejectDuplicates(root);
        if (root.ValueKind != JsonValueKind.Object || root.EnumerateObject().Count() != 6) throw new JsonException();
        var value = root.Deserialize<ScmDisplaySettings>(LocalPrivacyStore.Json) ?? throw new JsonException();
        if (value.SchemaVersion != 1 || value.Revision < 0 || value.Locations is < 0 or > 15 ||
            value.IdentityStamp is not { Length: 64 } || value.IdentityStamp.Any(c => !char.IsAsciiHexDigit(c)) ||
            value.Callsign is { } callsign && (callsign != callsign.Trim() || callsign.Length == 0 || CallsignWeight(callsign) > 10))
            throw new JsonException();
        return value;
    }

    internal Task<ScmDisplaySettings> SaveDisplayCallsignAsync(string bearer, long revision, string stamp,
        string? callsign, Action ensureCurrent, CancellationToken token) =>
        // The Relay identity stamp includes the callsign, so a rename yields a new stamp.
        SaveDisplayAsync(bearer, revision, stamp, "callsign",
            new { schemaVersion = 1, expectedRevision = revision, identityStamp = stamp, callsign },
            saved => saved.Callsign == callsign, stampMayChange: true, ensureCurrent, token);

    internal Task<ScmDisplaySettings> SaveDisplayLocationsAsync(string bearer, long revision, string stamp,
        int locations, Action ensureCurrent, CancellationToken token, bool importExplicit = false) =>
        SaveDisplayAsync(bearer, revision, stamp, "game-id",
            importExplicit
                ? new { schemaVersion = 1, expectedRevision = revision, identityStamp = stamp, locations, importExplicit = true }
                : (object)new { schemaVersion = 1, expectedRevision = revision, identityStamp = stamp, locations },
            saved => saved.Locations == locations, stampMayChange: false, ensureCurrent, token);

    private async Task<ScmDisplaySettings> SaveDisplayAsync(string bearer, long revision, string stamp, string section,
        object body, Func<ScmDisplaySettings, bool> applied, bool stampMayChange, Action ensureCurrent, CancellationToken token)
    {
        if (revision < 0 || revision == long.MaxValue || stamp is not { Length: 64 } || stamp.Any(c => !char.IsAsciiHexDigit(c)))
            throw new AccountBridgeHostException("gameId.invalid_request");
        ensureCurrent();
        // Strictly read the compact r49 shape first: an older Relay ignores the
        // section and must never receive a partial body.
        var before = await ReadDisplayAsync(bearer, token);
        ensureCurrent();
        if (before.Revision != revision || before.IdentityStamp != stamp) throw new AccountBridgeHostException("gameId.conflict");
        bool Matches(ScmDisplaySettings value) => value.Revision == revision + 1 && applied(value) &&
            (stampMayChange || value.IdentityStamp == stamp);
        ScmDisplaySettings saved;
        try
        {
            using var request = Request(HttpMethod.Post, new Uri(_players, "/api/auth/profile?section=" + section), bearer);
            request.Content = JsonContent.Create(body);
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            ensureCurrent();
            await RequireDisplaySuccessAsync(response, token);
            using var document = await ReadAsync(response, token);
            saved = ParseDisplay(document.RootElement);
            ensureCurrent();
            if (!Matches(saved)) throw new JsonException();
        }
        catch (Exception e) when (e is HttpRequestException or JsonException ||
            e is OperationCanceledException && !token.IsCancellationRequested ||
            e is AccountBridgeHostException { Code: "gameId.unavailable" })
        {
            // An ambiguous write gets one readback, never a second POST.
            ensureCurrent(); token.ThrowIfCancellationRequested();
            var recovered = await ReadDisplayAsync(bearer, token);
            ensureCurrent();
            if (Matches(recovered)) return recovered;
            throw new AccountBridgeHostException("gameId.write_unconfirmed");
        }
        // Confirm a normal receipt against an independent read (never a second POST).
        var confirmed = await ReadDisplayAsync(bearer, token);
        ensureCurrent();
        if (confirmed.Revision != saved.Revision || confirmed.IdentityStamp != saved.IdentityStamp || !applied(confirmed))
            throw new AccountBridgeHostException("gameId.write_unconfirmed");
        return confirmed;
    }

    private static async Task RequireDisplaySuccessAsync(HttpResponseMessage response, CancellationToken token)
    {
        if (response.StatusCode == HttpStatusCode.OK) return;
        if (response.StatusCode == HttpStatusCode.Conflict)
        {
            // Decision 乙: hiding needs an independent callsign; a stale draft stays a plain conflict.
            string? error = null;
            try
            {
                using var body = await ReadAsync(response, token);
                if (body.RootElement.ValueKind == JsonValueKind.Object &&
                    body.RootElement.TryGetProperty("error", out var value) && value.ValueKind == JsonValueKind.String)
                    error = value.GetString();
            }
            catch (Exception e) when (e is JsonException or AccountBridgeHostException or IOException) { }
            throw new AccountBridgeHostException(error is "gameId.callsign_required" or "callsign.hidden_requires_callsign"
                ? error : "gameId.conflict");
        }
        throw response.StatusCode switch
        {
            HttpStatusCode.BadRequest => new AccountBridgeHostException("callsign.invalid"),
            HttpStatusCode.Unauthorized => new AccountBridgeHostException("gameId.account_changed"),
            HttpStatusCode.Forbidden => new AccountBridgeHostException("gameId.forbidden"),
            HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed or HttpStatusCode.Gone =>
                new AccountBridgeHostException("gameId.relay_outdated"),
            HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests or HttpStatusCode.InternalServerError or
                HttpStatusCode.BadGateway or HttpStatusCode.ServiceUnavailable or HttpStatusCode.GatewayTimeout =>
                new AccountBridgeHostException("gameId.unavailable", retryable: true),
            _ => new AccountBridgeHostException("gameId.invalid_response")
        };
    }
}
