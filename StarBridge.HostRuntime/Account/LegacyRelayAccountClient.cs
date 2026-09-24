namespace StarBridge.HostRuntime.LegacyRelay;

using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Auth;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

/// <summary>
/// HTTP adapter for old Relay APIs under SCM bearer authentication. A
/// successful /api/auth/session probe creates an in-memory lease scoped to the
/// SCM authority, subject and linked legacy account ID.
/// </summary>
internal sealed class LegacyRelayAccountClient : ILegacyRelayAccountPort, IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions =
        new(JsonSerializerDefaults.Web);

    private readonly HttpClient _httpClient;
    private readonly Uri _baseUri;
    private readonly bool _ownsHttpClient;
    private readonly object _leaseGate = new();
    private LeaseIdentity? _lease;
    private bool _disposed;

    internal LegacyRelayAccountClient(Uri baseUri)
        : this(new HttpClient(), baseUri, ownsHttpClient: true)
    {
    }

    internal LegacyRelayAccountClient(
        HttpClient httpClient,
        Uri baseUri,
        bool ownsHttpClient = false)
    {
        _httpClient = httpClient ?? throw new ArgumentNullException(nameof(httpClient));
        _baseUri = NormalizeAndValidateBaseUri(baseUri);
        _ownsHttpClient = ownsHttpClient;
    }

    public async Task<LegacyRelayAccessState> EstablishAsync(
        ScmOAuthSession session,
        string expectedLegacyAccountId,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(session);
        var expected = RequireLegacyAccountId(expectedLegacyAccountId);
        var identity = LeaseIdentity.Create(session, expected);
        lock (_leaseGate)
        {
            if (_lease == identity)
            {
                return LegacyRelayAccessState.Ready;
            }
        }

        using var request = CreateRequest(HttpMethod.Get, "api/auth/session", session);
        try
        {
            using var response = await _httpClient
                .SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
                .ConfigureAwait(false);
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            {
                Reset();
                return LegacyRelayAccessState.AuthorizationRequired;
            }

            if (!response.IsSuccessStatusCode)
            {
                Reset();
                return LegacyRelayAccessState.Unavailable;
            }

            var projection = await response.Content
                .ReadFromJsonAsync<LegacyRelaySessionProjection>(JsonOptions, cancellationToken)
                .ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(projection?.AccountId) ||
                !projection.AccountId.Trim().Equals(expected, StringComparison.Ordinal))
            {
                Reset();
                return LegacyRelayAccessState.AccountMismatch;
            }

            lock (_leaseGate)
            {
                _lease = identity;
            }
            return LegacyRelayAccessState.Ready;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception) when (
            exception is HttpRequestException or JsonException or InvalidOperationException or IOException or TaskCanceledException)
        {
            Reset();
            return LegacyRelayAccessState.Unavailable;
        }
    }

    public async Task<LegacyRelayProfileReadResult> ReadOwnProfileAsync(
        ScmOAuthSession session,
        string expectedLegacyAccountId,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(session);
        var expected = RequireLegacyAccountId(expectedLegacyAccountId);
        var identity = LeaseIdentity.Create(session, expected);
        lock (_leaseGate)
        {
            if (_lease != identity)
            {
                return new LegacyRelayProfileReadResult(
                    LegacyRelayAccessState.NotEstablished);
            }
        }

        using var request = CreateRequest(HttpMethod.Get, "api/profile/me", session);
        try
        {
            using var response = await _httpClient
                .SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
                .ConfigureAwait(false);
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            {
                Reset();
                return new LegacyRelayProfileReadResult(
                    LegacyRelayAccessState.AuthorizationRequired);
            }

            if (!response.IsSuccessStatusCode)
            {
                return new LegacyRelayProfileReadResult(
                    LegacyRelayAccessState.Unavailable);
            }

            var profile = await response.Content
                .ReadFromJsonAsync<PersonalProfileDocumentContract>(JsonOptions, cancellationToken)
                .ConfigureAwait(false);
            if (profile is null ||
                profile.SchemaVersion != PersonalProfileContractPolicy.CurrentSchemaVersion)
            {
                return new LegacyRelayProfileReadResult(
                    LegacyRelayAccessState.Unavailable);
            }

            return new LegacyRelayProfileReadResult(
                LegacyRelayAccessState.Ready,
                profile with
                {
                    Content = PersonalProfileContractPolicy.Normalize(profile.Content)
                });
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception) when (
            exception is HttpRequestException or JsonException or InvalidOperationException or IOException or TaskCanceledException)
        {
            return new LegacyRelayProfileReadResult(LegacyRelayAccessState.Unavailable);
        }
    }

    public void Reset()
    {
        lock (_leaseGate)
        {
            _lease = null;
        }
    }

    private HttpRequestMessage CreateRequest(
        HttpMethod method,
        string relativePath,
        ScmOAuthSession session)
    {
        var request = new HttpRequestMessage(method, new Uri(_baseUri, relativePath));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", session.AccessToken);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        if (!string.IsNullOrWhiteSpace(session.CorrelationId))
        {
            request.Headers.TryAddWithoutValidation(
                "X-Correlation-ID",
                session.CorrelationId.Trim());
        }
        return request;
    }

    private static Uri NormalizeAndValidateBaseUri(Uri baseUri)
    {
        ArgumentNullException.ThrowIfNull(baseUri);
        if (!baseUri.IsAbsoluteUri ||
            (!baseUri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) &&
             !baseUri.IsLoopback))
        {
            throw new ArgumentException(
                "Legacy Relay must use HTTPS or an explicit loopback endpoint.",
                nameof(baseUri));
        }

        return new Uri(baseUri.AbsoluteUri.TrimEnd('/') + "/", UriKind.Absolute);
    }

    private static string RequireLegacyAccountId(string value)
    {
        var normalized = (value ?? string.Empty).Trim();
        return normalized.Length is > 0 and <= 128
            ? normalized
            : throw new ArgumentException(
                "Legacy account ID must be present and bounded.",
                nameof(value));
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        Reset();
        if (_ownsHttpClient)
        {
            _httpClient.Dispose();
        }
    }

    private sealed record LegacyRelaySessionProjection(string? AccountId);

    private sealed record LeaseIdentity(
        string Authority,
        string Subject,
        string LegacyAccountId)
    {
        internal static LeaseIdentity Create(
            ScmOAuthSession session,
            string legacyAccountId) => new(
                session.AuthorityId,
                session.Subject,
                legacyAccountId);
    }
}
