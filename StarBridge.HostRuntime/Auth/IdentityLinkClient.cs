using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Auth;

public sealed record ScmIdentityLinkChallenge(
    string ChallengeId,
    string Nonce,
    string Audience,
    string Issuer,
    string Subject,
    [property: JsonConverter(typeof(JavaInstantDateTimeOffsetConverter))] DateTimeOffset ExpiresAt);

public sealed class JavaInstantDateTimeOffsetConverter : JsonConverter<DateTimeOffset>
{
    public override DateTimeOffset Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.String)
        {
            if (reader.TryGetDateTimeOffset(out var timestamp))
            {
                return timestamp;
            }

            var encodedTimestamp = reader.GetString();
                if (DateTimeOffset.TryParse(
                    encodedTimestamp,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                    out timestamp))
                {
                return timestamp;
                }

            if (double.TryParse(
                    encodedTimestamp,
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out var encodedUnixTimestamp))
            {
                return FromUnixTimestamp(encodedUnixTimestamp);
            }
        }

        if (reader.TokenType == JsonTokenType.Number && reader.TryGetDouble(out var numericUnixTimestamp))
        {
            return FromUnixTimestamp(numericUnixTimestamp);
        }

        if (reader.TokenType == JsonTokenType.StartObject)
        {
            using var instant = JsonDocument.ParseValue(ref reader);
            if (instant.RootElement.TryGetProperty("epochSecond", out var epochSecond) &&
                epochSecond.TryGetInt64(out var seconds))
            {
                var nanoseconds = instant.RootElement.TryGetProperty("nano", out var nano) &&
                                  nano.TryGetInt32(out var parsedNanoseconds)
                    ? parsedNanoseconds
                    : 0;
                if (nanoseconds is >= 0 and < 1_000_000_000)
                {
                    try
                    {
                        return DateTimeOffset.FromUnixTimeSeconds(seconds).AddTicks(nanoseconds / 100);
                    }
                    catch (ArgumentOutOfRangeException exception)
                    {
                        throw new JsonException("SCM 返回的 challenge 过期时间超出有效范围。", exception);
                    }
                }
            }

            var propertyNames = string.Join(",", instant.RootElement
                .EnumerateObject()
                .Select(property => property.Name));
            throw new JsonException(
                $"SCM 返回的 challenge 过期时间对象格式无效，properties={propertyNames}。");
        }

        var shape = reader.TokenType == JsonTokenType.String
            ? $"stringValue={reader.GetString()}"
            : $"tokenType={reader.TokenType}";
        throw new JsonException($"SCM 返回的 challenge 过期时间格式无效，{shape}。");
    }

    public override void Write(
        Utf8JsonWriter writer,
        DateTimeOffset value,
        JsonSerializerOptions options) => writer.WriteStringValue(value);

    private static DateTimeOffset FromUnixTimestamp(double unixTimestamp)
    {
        var milliseconds = Math.Abs(unixTimestamp) >= 100_000_000_000d
            ? unixTimestamp
            : unixTimestamp * 1000d;
        try
        {
            return DateTimeOffset.FromUnixTimeMilliseconds(checked((long)Math.Round(milliseconds)));
        }
        catch (ArgumentOutOfRangeException exception)
        {
            throw new JsonException("SCM 返回的 challenge 过期时间超出有效范围。", exception);
        }
    }
}

public sealed record SignedIdentityLinkProof(string Payload, string Signature);

public sealed record LegacyIdentityLinkPasswordCredential(string AccountName, string Password);

public sealed record ScmIdentityLinkResult(
    string Status,
    string LegacyAccountId,
    string? ConflictId);

public sealed record ScmIdentityLinkProjection(string Status, string LegacyAccountId);

public interface IIdentityLinkClient
{
    Task<ScmIdentityLinkChallenge> CreateChallengeAsync(
        ScmOAuthSession linkSession,
        CancellationToken cancellationToken);

    Task<SignedIdentityLinkProof> RequestLegacyProofAsync(
        ScmIdentityLinkChallenge challenge,
        LegacyMigrationCredential credential,
        CancellationToken cancellationToken);

    Task<SignedIdentityLinkProof> RequestLegacyProofAsync(
        ScmIdentityLinkChallenge challenge,
        LegacyIdentityLinkPasswordCredential credential,
        CancellationToken cancellationToken);

    Task<ScmIdentityLinkResult> ConsumeProofAsync(
        ScmOAuthSession linkSession,
        SignedIdentityLinkProof proof,
        CancellationToken cancellationToken);

    Task<ScmIdentityLinkResult> ProvisionCompatibilityAccountAsync(
        ScmOAuthSession linkSession,
        string commandId,
        CancellationToken cancellationToken);

    Task<ScmIdentityLinkProjection?> ResolveAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken);
}

public sealed class IdentityLinkClient(
    ScmHttpClient scmHttpClient,
    HttpClient legacyHttpClient,
    ScmOAuthOptions options,
    Func<Uri> legacyBaseUriProvider) : IIdentityLinkClient
{
    public async Task<ScmIdentityLinkChallenge> CreateChallengeAsync(
        ScmOAuthSession linkSession,
        CancellationToken cancellationToken)
    {
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/identity-link/challenge"));
        try
        {
            using var response = await scmHttpClient.SendAsync(request, linkSession.AccessToken, cancellationToken);
            return await scmHttpClient.ReadJsonAsync<ScmIdentityLinkChallenge>(
                response,
                "旧账号关联挑战",
                cancellationToken);
        }
        catch (JsonException exception)
        {
            ScmAuthDiagnostics.Write(
                correlationId,
                "identity-link-challenge-json",
                "failed",
                $"path={exception.Path ?? "unknown"} detail={exception.Message.Replace('\r', ' ').Replace('\n', ' ')}");
            throw;
        }
    }

    public async Task<SignedIdentityLinkProof> RequestLegacyProofAsync(
        ScmIdentityLinkChallenge challenge,
        LegacyMigrationCredential credential,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(challenge);
        ArgumentNullException.ThrowIfNull(credential);
        var endpoint = BuildLegacyUri("api/auth/identity-link/proof");
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var stopwatch = ScmAuthDiagnostics.Start(
            correlationId,
            "identity-link-proof-request",
            $"endpoint={ScmAuthDiagnostics.Endpoint(endpoint)} credentialType=bearer");
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = JsonContent.Create(new { Challenge = challenge })
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential.AuthToken);
        try
        {
            using var response = await legacyHttpClient.SendAsync(request, cancellationToken);
            EnsureLegacyProofSuccess(response);
            var proof = await response.Content.ReadFromJsonAsync<SignedIdentityLinkProof>(cancellationToken)
                ?? throw new ScmApiProtocolException("旧账号证明服务返回了空响应。");
            ScmAuthDiagnostics.Completed(
                correlationId,
                "identity-link-proof-request",
                stopwatch,
                $"status={(int)response.StatusCode}");
            return proof;
        }
        catch (Exception exception)
        {
            ScmAuthDiagnostics.Failed(correlationId, "identity-link-proof-request", stopwatch, exception);
            throw;
        }
    }

    public async Task<SignedIdentityLinkProof> RequestLegacyProofAsync(
        ScmIdentityLinkChallenge challenge,
        LegacyIdentityLinkPasswordCredential credential,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(challenge);
        ArgumentNullException.ThrowIfNull(credential);
        var endpoint = BuildLegacyUri("api/auth/identity-link/proof");
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var stopwatch = ScmAuthDiagnostics.Start(
            correlationId,
            "identity-link-proof-request",
            $"endpoint={ScmAuthDiagnostics.Endpoint(endpoint)} credentialType=password");
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = JsonContent.Create(new
            {
                Challenge = challenge,
                UserName = credential.AccountName,
                Password = credential.Password
            })
        };
        try
        {
            using var response = await legacyHttpClient.SendAsync(request, cancellationToken);
            EnsureLegacyProofSuccess(response);
            var proof = await response.Content.ReadFromJsonAsync<SignedIdentityLinkProof>(cancellationToken)
                ?? throw new ScmApiProtocolException("旧账号证明服务返回了空响应。");
            ScmAuthDiagnostics.Completed(
                correlationId,
                "identity-link-proof-request",
                stopwatch,
                $"status={(int)response.StatusCode}");
            return proof;
        }
        catch (Exception exception)
        {
            ScmAuthDiagnostics.Failed(correlationId, "identity-link-proof-request", stopwatch, exception);
            throw;
        }
    }

    private static void EnsureLegacyProofSuccess(HttpResponseMessage response)
    {
        if (!response.IsSuccessStatusCode)
        {
            if (response.StatusCode == HttpStatusCode.Unauthorized)
            {
                throw new LegacyIdentityLinkAuthenticationException();
            }

            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                throw new LegacyIdentityLinkRateLimitException(response.Headers.RetryAfter?.Delta);
            }

            throw new HttpRequestException(
                $"旧账号证明请求失败（HTTP {(int)response.StatusCode}）。",
                null,
                response.StatusCode);
        }
    }

    public async Task<ScmIdentityLinkResult> ConsumeProofAsync(
        ScmOAuthSession linkSession,
        SignedIdentityLinkProof proof,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/identity-link/consume"))
        {
            Content = JsonContent.Create(proof)
        };
        using var response = await scmHttpClient.SendAsync(request, linkSession.AccessToken, cancellationToken);
        return await scmHttpClient.ReadJsonAsync<ScmIdentityLinkResult>(
            response,
            "旧账号关联确认",
            cancellationToken);
    }

    public async Task<ScmIdentityLinkResult> ProvisionCompatibilityAccountAsync(
        ScmOAuthSession linkSession,
        string commandId,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(commandId);
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/identity-link/provision"))
        {
            Content = JsonContent.Create(new { CommandId = commandId })
        };
        using var response = await scmHttpClient.SendAsync(request, linkSession.AccessToken, cancellationToken);
        return await scmHttpClient.ReadJsonAsync<ScmIdentityLinkResult>(
            response,
            "兼容档案创建",
            cancellationToken);
    }

    public async Task<ScmIdentityLinkProjection?> ResolveAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/identity-link"));
        using var response = await scmHttpClient.SendAsync(request, session.AccessToken, cancellationToken);
        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }

        return await scmHttpClient.ReadJsonAsync<ScmIdentityLinkProjection>(
            response,
            "旧账号关联查询",
            cancellationToken);
    }

    private Uri BuildLegacyUri(string path)
    {
        var baseUri = legacyBaseUriProvider();
        if (!baseUri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) && !baseUri.IsLoopback)
        {
            throw new InvalidOperationException("旧账号证明服务必须使用 HTTPS；本地测试仅允许 loopback HTTP。");
        }

        return new Uri(baseUri.AbsoluteUri.EndsWith("/", StringComparison.Ordinal)
            ? baseUri
            : new Uri(baseUri.AbsoluteUri + "/"), path);
    }
}

public sealed class LegacyIdentityLinkAuthenticationException()
    : HttpRequestException("旧账号身份验证失败。", null, HttpStatusCode.Unauthorized);

public sealed class LegacyIdentityLinkRateLimitException(TimeSpan? retryAfter)
    : HttpRequestException("旧账号验证尝试过于频繁。", null, HttpStatusCode.TooManyRequests)
{
    public TimeSpan? RetryAfter { get; } = retryAfter;
}
