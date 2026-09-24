using System.Net;
using System.Net.Http;
using System.Net.Http.Json;

namespace StarBridge.HostRuntime.Auth;

// Deliberately excludes legacy account ids, source keys, staged documents and all credentials.
public sealed record LegacyProfileMigrationSummary(
    string CallSign, string Introduction, int Modules, int Favorites, long? PlayTimeSeconds);
public sealed record LegacyProfileMigrationView(
    string State, string? PreviewId = null, string? SourceGameId = null,
    long SourceRevision = 0, long TargetRevision = 0, DateTimeOffset? ExpiresAt = null,
    bool Conflict = false, LegacyProfileMigrationSummary? Source = null,
    LegacyProfileMigrationSummary? Target = null, long? CompletedRevision = null);
public sealed record LegacyProfileMigrationResult(LegacyProfileMigrationView View, ScmOAuthSession ActiveSession);
public sealed record LegacyProfileCredential(string AccountName, string Password)
{
    public override string ToString() => "LegacyProfileCredential[REDACTED]";
}

public sealed partial class OAuthPkceClient
{
    public async Task<LegacyProfileMigrationResult> ExecuteLegacyProfileMigrationAsync(
        ScmOAuthSession session, string action, string? previewId, bool replaceExisting,
        CancellationToken cancellationToken, LegacyProfileCredential? credentials = null)
    {
        if (action is not ("status" or "preview" or "confirm"))
            throw new ArgumentException("Unknown migration operation.", nameof(action));
        if (action == "confirm" && !session.Capabilities.Contains("profile.write", StringComparer.Ordinal))
            throw new ScmApiForbiddenException("Migration requires profile.write.");
        var endpoint = new Uri(options.ResourceServerBaseUri,
            "app-api/starbridge/v1/legacy-profile-migration" + (action == "status" ? "" : "/" + action));
        async Task<LegacyProfileMigrationView> Send(ScmOAuthSession current, CancellationToken token)
            {
                using var request = new HttpRequestMessage(action == "status" ? HttpMethod.Get : HttpMethod.Post, endpoint);
                if (action == "confirm")
                    request.Content = JsonContent.Create(new { previewId, replaceExisting });
                else if (action == "preview" && credentials is not null)
                    request.Content = JsonContent.Create(new { credentials.AccountName, credentials.Password });
                using var response = await scmHttpClient.SendAsync(request, current.AccessToken, token,
                    action == "preview" ? TimeSpan.FromSeconds(45) : null);
                // Domain failures are safe allowlisted states, never arbitrary backend error strings.
                if (response.StatusCode is HttpStatusCode.Conflict or HttpStatusCode.ServiceUnavailable)
                {
                    var failed = await response.Content.ReadFromJsonAsync<LegacyProfileMigrationView>(token);
                    return new LegacyProfileMigrationView(AllowedFailure(failed?.State));
                }
                var result = await scmHttpClient.ReadJsonAsync<LegacyProfileMigrationView>(response, "Migration", token);
                if (result.State is not ("notStarted" or "previewed" or "completed") &&
                    AllowedFailure(result.State) != result.State)
                    throw new ScmApiProtocolException("Unknown migration response.");
                if (result.State == "previewed" &&
                    (string.IsNullOrWhiteSpace(result.PreviewId) || result.PreviewId.Length > 64 ||
                     result.Source is null || result.Target is null || result.ExpiresAt is null))
                    throw new ScmApiProtocolException("Incomplete migration preview.");
                return result;
            }
        // The short-lived write grant has no refresh token. Do not refresh it with the ordinary
        // read session, and do not replace the long-lived login session with this grant.
        if (action == "confirm")
            return new LegacyProfileMigrationResult(await Send(session, cancellationToken), session);
        var (view, activeSession) = await SendResourceRequestWithRefreshAndSessionAsync(
            session, Send, cancellationToken);
        _currentSession = activeSession;
        return new LegacyProfileMigrationResult(view, activeSession);
    }

    private static string AllowedFailure(string? code) => code switch
    {
        "linkRequired" or "accountMismatch" or "authorizationRequired" or "unsupportedData" or
        "previewRequired" or "previewExpired" or "replacementRequired" or "targetChanged" or
        "sourceNotConfigured" or "credentialRequired" or "credentialRejected" or
        "verificationRateLimited" or "profileNotFound" => code,
        _ => "sourceUnavailable"
    };
}
