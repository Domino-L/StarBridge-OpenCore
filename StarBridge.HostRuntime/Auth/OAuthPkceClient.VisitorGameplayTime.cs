using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    internal async Task<(VisitorGameplayTimeResult Result, ScmOAuthSession ActiveSession)> WriteVisitorGameplayTimeAsync(
        ScmOAuthSession session, VisitorGameplayTime value, CancellationToken token, Action<ScmOAuthSession>? sessionReady = null)
    {
        if (!value.IsValid) throw new ArgumentOutOfRangeException(nameof(value));
        var rejected = false;
        try
        {
            return await SendResourceRequestAsync(session, async (active, ct) =>
            {
                if (!active.Capabilities.Contains("profile.write", StringComparer.Ordinal))
                    throw new ScmApiForbiddenException("Gameplay time write requires profile.write.");

                using var request = new HttpRequestMessage(HttpMethod.Put,
                    new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/personal-profile/gameplay-time"));
                request.Content = value.SourceRevision is { } revision
                    ? JsonContent.Create(new { schemaVersion = 1, playTimeSeconds = value.Seconds, sourceRevision = revision })
                    : JsonContent.Create(new { schemaVersion = 1, playTimeSeconds = value.Seconds });
                using var response = await scmHttpClient.SendAsync(request, active.AccessToken, ct,
                    completionOption: HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false);
                if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
                {
                    rejected = true;
                    // Use the existing guarded refresh and credential rejection path for both statuses.
                    throw new ScmApiAuthenticationException("Gameplay time write authorization rejected.");
                }
                return await ReadVisitorGameplayTimeResultAsync(response, ct).ConfigureAwait(false);
            }, token, sessionReady).ConfigureAwait(false);
        }
        catch (ScmRefreshTemporarilyUnavailableException) when (rejected)
        {
            // The resource authentication flow already handled this rejection.
            throw new ScmApiAuthenticationException("Gameplay time write authorization unavailable.");
        }
    }

    private static async Task<VisitorGameplayTimeResult> ReadVisitorGameplayTimeResultAsync(
        HttpResponseMessage response, CancellationToken token)
    {
        switch (response.StatusCode)
        {
            case HttpStatusCode.NotFound:
                return new(VisitorGameplayTimeOutcome.Unavailable);
            case HttpStatusCode.TooManyRequests:
                var retry = response.Headers.RetryAfter;
                return new(VisitorGameplayTimeOutcome.TemporaryFailure, RetryAfter: retry?.Delta, RetryAt: retry?.Date);
            case >= HttpStatusCode.InternalServerError and <= (HttpStatusCode)599:
                return new(VisitorGameplayTimeOutcome.TemporaryFailure);
            case HttpStatusCode.BadRequest:
            case HttpStatusCode.Conflict:
            case HttpStatusCode.OK:
                break;
            default:
                return new(VisitorGameplayTimeOutcome.ProtocolError);
        }

        try
        {
            using var document = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(
                response.Content, token, 4096).ConfigureAwait(false);
            var root = document.RootElement;
            if (response.StatusCode == HttpStatusCode.BadRequest)
            {
                var field = root.TryGetProperty("field", out var item) && item.ValueKind == JsonValueKind.String
                    ? VisitorGameplayTimeResult.SafeField(item.GetString()) : null;
                return new(VisitorGameplayTimeOutcome.Invalid, Field: field);
            }
            if (!root.TryGetProperty("schemaVersion", out var version) ||
                version.ValueKind != JsonValueKind.Number || !version.TryGetInt32(out var schema) || schema != 1)
                return new(VisitorGameplayTimeOutcome.ProtocolError);
            if (response.StatusCode == HttpStatusCode.OK &&
                root.TryGetProperty("updatedAt", out var updatedAt) && updatedAt.ValueKind == JsonValueKind.String &&
                updatedAt.TryGetDateTimeOffset(out _))
                return new(VisitorGameplayTimeOutcome.Ok);
            if (response.StatusCode == HttpStatusCode.Conflict &&
                root.TryGetProperty("error", out var error) && error.ValueKind == JsonValueKind.String &&
                error.GetString() == "gameplay_time.stale_revision" &&
                root.TryGetProperty("sourceRevision", out var revision) && revision.ValueKind == JsonValueKind.Number &&
                revision.TryGetInt64(out var stored) && stored is >= 0 and <= VisitorGameplayTime.MaximumRevision)
                return new(VisitorGameplayTimeOutcome.StaleRevision, StoredRevision: stored);
        }
        catch (JsonException) when (response.StatusCode == HttpStatusCode.BadRequest)
        {
            return new(VisitorGameplayTimeOutcome.Invalid);
        }
        catch (JsonException) { }
        return new(VisitorGameplayTimeOutcome.ProtocolError);
    }
}
