using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Privacy;

internal sealed record GameIdSettingsSnapshot(
    [property: JsonRequired] int SchemaVersion, [property: JsonRequired] long Revision,
    [property: JsonRequired] int Locations, [property: JsonRequired] bool CanConfigure,
    [property: JsonRequired] string IdentityStamp);

internal sealed partial class PrivacyRelayWriter
{
    internal async Task<GameIdSettingsSnapshot> ReadGameIdAsync(string bearer, CancellationToken token)
    {
        using var request = Request(HttpMethod.Get, new Uri(_players, "/api/auth/session?section=game-id"), bearer);
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        RequireEventSuccess(response);
        using var document = await ReadAsync(response, token);
        return ParseGameId(document.RootElement);
    }
    private static GameIdSettingsSnapshot ParseGameId(JsonElement root)
    {
        LocalPrivacyStore.RejectDuplicates(root);
        var value = root.Deserialize<GameIdSettingsSnapshot>(LocalPrivacyStore.Json) ?? throw new JsonException();
        if (value.SchemaVersion != 1 || value.Revision < 0 || value.Locations is < 0 or > 15 ||
            value.IdentityStamp is not { Length: 64 } || value.IdentityStamp.Any(c => !char.IsAsciiHexDigit(c)) ||
            !value.CanConfigure && value.Locations != 15) throw new JsonException();
        return value;
    }
    internal async Task<GameIdSettingsSnapshot> SaveGameIdAsync(string bearer, long revision, string stamp,
        int locations, Action ensureCurrent, CancellationToken token)
    {
        if (revision < 0 || revision == long.MaxValue || locations is < 0 or > 15 || stamp is not { Length: 64 } ||
            stamp.Any(c => !char.IsAsciiHexDigit(c))) throw new JsonException();
        ensureCurrent();
        // Older Relay versions ignore the query and return a full AuthResponse.
        // Strictly verify the compact capability before sending any partial body.
        var before = await ReadGameIdAsync(bearer, token);
        ensureCurrent();
        if (!before.CanConfigure || before.Revision != revision || before.IdentityStamp != stamp)
            throw new AccountBridgeHostException("gameId.conflict");
        bool Matches(GameIdSettingsSnapshot value) => value.Revision == revision + 1 && value.IdentityStamp == stamp && value.Locations == locations;
        try
        {
            using var request = Request(HttpMethod.Post, new Uri(_players, "/api/auth/profile?section=game-id"), bearer);
            request.Content = JsonContent.Create(new { schemaVersion = 1, expectedRevision = revision, identityStamp = stamp, locations });
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            ensureCurrent(); RequireEventSuccess(response);
            using var document = await ReadAsync(response, token);
            var saved = ParseGameId(document.RootElement);
            ensureCurrent();
            if (!Matches(saved)) throw new JsonException();
            return saved;
        }
        catch (Exception e) when (e is HttpRequestException or JsonException ||
            e is OperationCanceledException && !token.IsCancellationRequested ||
            e is AccountBridgeHostException { Code: "events.temporarily_unavailable" or "privacy_publication.response_invalid" })
        {
            ensureCurrent(); token.ThrowIfCancellationRequested();
            var saved = await ReadGameIdAsync(bearer, token);
            ensureCurrent();
            if (Matches(saved)) return saved;
            throw new AccountBridgeHostException("gameId.write_unconfirmed");
        }
    }
}
