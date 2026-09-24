using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.Core.Identity;
using StarBridge.Core.Profiles;

namespace StarBridge.HostRuntime.Account;

internal sealed record LegacyPasswordLoginResult(int SchemaVersion, string Outcome, int RetryAfterSeconds = 0);

// Private transport result, never a Bridge DTO (and never loggable via record ToString).
internal sealed class LegacyPasswordLoginAttempt(LegacyPasswordLoginResult result, LegacyMigrationCredential? credential = null, string? displayName = null,
    ScmGameIdentitySnapshot? identity = null, string? avatarImageData = null, ScmOverlayEntitlementSnapshot? entitlements = null)
{
    internal LegacyPasswordLoginResult Result { get; } = result;
    internal LegacyMigrationCredential? Credential { get; } = credential;
    internal string? DisplayName { get; } = displayName;
    internal ScmGameIdentitySnapshot? Identity { get; } = identity;
    internal string? AvatarImageData { get; } = avatarImageData;
    internal ScmOverlayEntitlementSnapshot? Entitlements { get; } = entitlements;
}

// Reuses WPF's anonymous /api/auth/login contract and its protected migration store.
// An old AuthToken is a Relay credential, never an SCM session or SCM scope grant.
internal sealed partial class LegacyPasswordLoginClient : IDisposable
{
    private readonly Uri _baseUri;
    private readonly HttpClient _http;
    private readonly ILegacyMigrationCredentialStore _store;
    private readonly ILegacyMigrationCredentialStore? _sessionStore;
    internal string AuthorityId => "starbridge-relay-" + Convert.ToHexString(
        System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(_baseUri.AbsoluteUri)))[..16].ToLowerInvariant();

    internal LegacyPasswordLoginClient(Uri baseUri, ILegacyMigrationCredentialStore store, HttpMessageHandler? handler = null,
        ILegacyMigrationCredentialStore? sessionStore = null)
    {
        if (!baseUri.IsAbsoluteUri || (baseUri.Scheme != "https" && !(baseUri.Scheme == "http" && baseUri.IsLoopback)) ||
            baseUri.UserInfo.Length != 0 || baseUri.Query.Length != 0 || baseUri.Fragment.Length != 0)
            throw new ArgumentException("Legacy login requires HTTPS or a loopback test endpoint.", nameof(baseUri));
        _baseUri = baseUri;
        _store = store;
        _sessionStore = sessionStore;
        _http = new HttpClient(handler ?? new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(20) };
    }

    internal async Task<LegacyPasswordLoginAttempt> VerifyAsync(JsonElement payload, CancellationToken token)
    {
        string[] fields = ["schemaVersion", "email", "password"];
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Any(p => !fields.Contains(p.Name)) ||
            payload.EnumerateObject().Select(p => p.Name).Distinct().Count() != 3 ||
            payload.EnumerateObject().Count() != 3 ||
            !payload.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number ||
            !schema.TryGetInt32(out var version) || version != 1)
            throw new AccountBridgeHostException("bridge.invalid_envelope");
        var email = Text(payload, "email")?.Trim();
        var password = Text(payload, "password");
        // Login must accept existing passwords, not impose the new/reset password policy.
        if (string.IsNullOrWhiteSpace(email) || email.Length > 320 || string.IsNullOrWhiteSpace(password) || password.Length > 1024)
            return new(new(1, "invalidInput"));
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_baseUri, "api/auth/login"))
            {
                Content = JsonContent.Create(new { Email = email, Password = password })
            };
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            if (response.StatusCode == HttpStatusCode.Unauthorized) return new(new(1, "rejected"));
            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                var retry = response.Headers.RetryAfter?.Delta?.TotalSeconds ??
                    (response.Headers.RetryAfter?.Date - DateTimeOffset.UtcNow)?.TotalSeconds ?? 60;
                return new(new(1, "throttled", (int)Math.Clamp(Math.Ceiling(retry), 1, 3600)));
            }
            if (!response.IsSuccessStatusCode) return new(new(1, "unavailable"));
            // Bound the response; only validated display media crosses the Bridge.
            using var body = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 2 * 1024 * 1024);
            var id = Text(body.RootElement, "accountId")?.Trim();
            var authToken = Text(body.RootElement, "token");
            var accountName = Text(body.RootElement, "email") ?? Text(body.RootElement, "userName");
            if (string.IsNullOrWhiteSpace(id) || id.Length > 256 || string.IsNullOrWhiteSpace(authToken) || authToken.Length > 16384 ||
                string.IsNullOrWhiteSpace(accountName) || accountName.Length > 320 || !accountName.Trim().Equals(email, StringComparison.OrdinalIgnoreCase))
                return new(new(1, "unavailable"));
            token.ThrowIfCancellationRequested();
            return new(new(1, "verified"), new(id, accountName.Trim(), authToken, DateTimeOffset.UtcNow), DisplayName(body.RootElement), Identity(body.RootElement), Avatar(body.RootElement), ParseLegacyEntitlements(body.RootElement, id));
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or JsonException or OperationCanceledException)
        { return new(new(1, "unavailable")); }
    }

    internal LegacyPasswordLoginResult SaveVerified(LegacyPasswordLoginAttempt attempt)
    {
        if (attempt.Credential is null) return attempt.Result;
        try { _store.Save(attempt.Credential); _sessionStore?.Save(attempt.Credential); return attempt.Result; }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.Cryptography.CryptographicException)
        { return new(1, "storageUnavailable"); }
    }

    // WPF S2's still-live own-profile read. No SCM fallback, migration or remote write.
    internal async Task<PersonalProfileDocumentContract> ReadOwnProfileAsync(
        LegacyMigrationCredential credential, CancellationToken token)
        => await ReadProfileDocumentAsync(credential, null, token);

    internal Task<PersonalProfileDocumentContract> ReadVisitorProfileAsync(
        LegacyMigrationCredential credential, string publicId, CancellationToken token) =>
        ReadProfileDocumentAsync(credential, publicId, token);

    private async Task<PersonalProfileDocumentContract> ReadProfileDocumentAsync(
        LegacyMigrationCredential credential, string? publicId, CancellationToken token)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_baseUri,
                publicId is null ? "api/profile/me" : "api/profiles/" + Uri.EscapeDataString(publicId)));
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", credential.AuthToken);
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            if (publicId is not null && response.StatusCode is System.Net.HttpStatusCode.NotFound or System.Net.HttpStatusCode.Forbidden)
                throw new AccountBridgeHostException("profile.visitor_not_visible");
            if (!response.IsSuccessStatusCode) throw new HttpRequestException();
            using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 8 * 1024 * 1024);
            var profile = json.RootElement.Deserialize<PersonalProfileDocumentContract>(new JsonSerializerOptions(JsonSerializerDefaults.Web));
            token.ThrowIfCancellationRequested();
            if (profile is null || profile.SchemaVersion != PersonalProfileContractPolicy.CurrentSchemaVersion ||
                profile.PublicId != (publicId ?? credential.AccountId) || profile.Identity is null || profile.Content is null || profile.Revision < 0)
                throw new JsonException();
            if (profile.Hangar is { } hangar && (hangar.Ships is null || hangar.Ships.Length > 20000 ||
                hangar.Ships.Any(ship => ship is null || string.IsNullOrWhiteSpace(ship.Code) ||
                    string.IsNullOrWhiteSpace(ship.DisplayName) || ship.Code.Length > 1024 || ship.DisplayName.Length > 1024)))
                throw new JsonException();
            var affiliation = profile.FleetAffiliation;
            if (affiliation is not null)
                affiliation = affiliation with { Kind = "community",
                    LogoImageData = await ReadAffiliationLogoAsync(credential, affiliation.FleetCode, token) };
            token.ThrowIfCancellationRequested();
            return profile with { Content = PersonalProfileContractPolicy.Normalize(profile.Content), FleetAffiliation = affiliation };
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or JsonException or OperationCanceledException)
        {
            throw new AccountBridgeHostException(AccountBridgeStableErrors.PersonalProfileReadUnavailable, retryable: true);
        }
    }

    private async Task<string?> ReadAffiliationLogoAsync(LegacyMigrationCredential credential, string code, CancellationToken token)
    {
        // WPF's existing directory projection supplies the logo missing from
        // /profile/me. Match the exact returned affiliation code, never its name.
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_baseUri, "api/fleets"));
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", credential.AuthToken);
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            if (!response.IsSuccessStatusCode) return null;
            using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 8 * 1024 * 1024, JsonValueKind.Array);
            var matches = json.RootElement.EnumerateArray().Where(item =>
                string.Equals(Text(item, "code"), code, StringComparison.OrdinalIgnoreCase)).Take(2).ToArray();
            // Same organization-image budget as CommunityClient.WpfS2Discovery,
            // not the smaller default used for room-list avatars.
            return matches.Length == 1 ? StarBridge.HostRuntime.PartyRooms.RoomAvatarProjection.Normalize(Text(matches[0], "logoImageData"), 512 * 1024) : null;
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or JsonException or OperationCanceledException)
        { return null; }
    }

    internal async Task<LegacyPasswordLoginAttempt> RestoreAsync(CancellationToken token)
    {
        // Restore only the route-scoped session established by explicit login.
        // Preserved WPF credentials are not permission to sign the user back in,
        // particularly after logout. Legacy password login remains independent of SCM.
        LegacyMigrationCredential? saved;
        try { saved = _sessionStore?.Load(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.Cryptography.CryptographicException)
        { return new(new(1, "unavailable")); }
        if (saved is null) return new(new(1, "absent"));
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_baseUri, "api/auth/session"));
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", saved.AuthToken);
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            {
                token.ThrowIfCancellationRequested();
                _sessionStore!.Delete();
                return new(new(1, "rejected"));
            }
            if (!response.IsSuccessStatusCode) return new(new(1, "unavailable"), saved);
            using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 2 * 1024 * 1024);
            var id = Text(json.RootElement, "accountId");
            if (!string.Equals(id, saved.AccountId, StringComparison.Ordinal))
                return new(new(1, "unavailable"), saved);
            token.ThrowIfCancellationRequested();
            return new(new(1, "verified"), saved, DisplayName(json.RootElement), Identity(json.RootElement), Avatar(json.RootElement), ParseLegacyEntitlements(json.RootElement, saved.AccountId));
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or JsonException or OperationCanceledException)
        { return new(new(1, "unavailable"), saved); }
    }

    internal void ForgetSession() => _sessionStore?.Delete();

    private static string? Avatar(JsonElement value) =>
        // WPF accepts 512 KiB account images. Do not apply the smaller room-list budget here.
        StarBridge.HostRuntime.PartyRooms.RoomAvatarProjection.Normalize(Text(value, "avatarImageData"), 512 * 1024);

    // Same authoritative fields as WPF UpdateIdentityBindingFromAuth. Callsign
    // and locally observed Game.log alone never establish account ownership.
    private static ScmGameIdentitySnapshot Identity(JsonElement value)
    {
        var handle = Text(value, "gameName")?.Trim();
        var supported = value.TryGetProperty("identityBindingRequired", out var required) &&
            required.ValueKind is JsonValueKind.True or JsonValueKind.False;
        var confirmed = value.TryGetProperty("identityBindingConfirmedAt", out var date) &&
            date.ValueKind == JsonValueKind.String && date.TryGetDateTimeOffset(out _);
        if (!supported || !confirmed || string.IsNullOrWhiteSpace(handle) || handle.Length > 128 || handle.Any(char.IsControl))
            return new(ScmGameIdentityStatus.Unknown, null, null);
        return new(ScmGameIdentityStatus.Verified, handle, handle.ToLowerInvariant());
    }

    private static string? DisplayName(JsonElement value)
    {
        var name = Text(value, "callsign")?.Trim();
        return !string.IsNullOrWhiteSpace(name) && name.Length <= 128 ? name : null;
    }

    private static string? Text(JsonElement value, string key) =>
        value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var item) && item.ValueKind == JsonValueKind.String ? item.GetString() : null;
    public void Dispose() => _http.Dispose();
}
