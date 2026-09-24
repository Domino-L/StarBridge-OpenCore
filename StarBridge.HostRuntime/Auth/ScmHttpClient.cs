using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Auth;

public sealed class ScmHttpClient
{
    private readonly HttpClient _httpClient;

    public ScmHttpClient()
        : this(new HttpClientHandler
        {
            UseCookies = false,
            AllowAutoRedirect = false
        })
    {
    }

    public ScmHttpClient(HttpMessageHandler primaryHandler)
    {
        var handler = new ScmHttpHandler
        {
            InnerHandler = primaryHandler
        };
        _httpClient = new HttpClient(handler)
        {
            Timeout = Timeout.InfiniteTimeSpan
        };
        var version = typeof(ScmHttpClient).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";
        _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd($"StarBridge-NativeHost/{version}");
    }

    public async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        string? accessToken = null,
        CancellationToken cancellationToken = default,
        TimeSpan? requestTimeout = null)
    {
        if (!string.IsNullOrWhiteSpace(accessToken))
        {
            request.Options.Set(ScmHttpHandler.AccessTokenOption, accessToken);
        }

        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(requestTimeout ?? TimeSpan.FromSeconds(15));
        return await _httpClient.SendAsync(request, deadline.Token);
    }

    public async Task<T> ReadJsonAsync<T>(
        HttpResponseMessage response,
        string operation,
        CancellationToken cancellationToken = default)
    {
        await EnsureSuccessAsync(response, operation, cancellationToken);
        try
        {
            var result = await response.Content.ReadFromJsonAsync<T>(cancellationToken);
            return result ?? throw new ScmApiProtocolException($"SCM {operation} 返回了空响应。");
        }
        catch (Exception exception) when (exception is JsonException or NotSupportedException)
        {
            throw new ScmApiProtocolException($"SCM {operation} 返回了无效响应。");
        }
    }

    public static async Task EnsureSuccessAsync(
        HttpResponseMessage response,
        string operation,
        CancellationToken cancellationToken = default)
    {
        if (response.IsSuccessStatusCode)
        {
            return;
        }

        var message = await TryReadErrorMessageAsync(response, cancellationToken);
        var detail = string.IsNullOrWhiteSpace(message)
            ? $"SCM {operation} 请求失败（HTTP {(int)response.StatusCode}）。"
            : message;
        throw response.StatusCode switch
        {
            HttpStatusCode.Unauthorized => new ScmApiAuthenticationException(detail),
            HttpStatusCode.Forbidden => new ScmApiForbiddenException(detail),
            HttpStatusCode.TooManyRequests => new ScmApiRateLimitException(detail, response.Headers.RetryAfter?.Delta),
            >= HttpStatusCode.InternalServerError => new ScmApiUnavailableException(detail),
            _ => new HttpRequestException(detail, null, response.StatusCode)
        };
    }

    private static async Task<string?> TryReadErrorMessageAsync(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        try
        {
            var payload = await response.Content.ReadFromJsonAsync<ScmErrorPayload>(cancellationToken);
            return payload?.Message ?? payload?.Msg ?? payload?.ErrorDescription ?? payload?.Error;
        }
        catch (Exception exception) when (exception is JsonException or NotSupportedException)
        {
            return null;
        }
    }

    private sealed record ScmErrorPayload(
        string? Message,
        string? Msg,
        string? Error,
        [property: JsonPropertyName("error_description")] string? ErrorDescription);
}

internal sealed class ScmHttpHandler : DelegatingHandler
{
    internal static readonly HttpRequestOptionsKey<string> AccessTokenOption =
        new("StarBridge.Scm.AccessToken");

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        if (!request.Headers.Accept.Any(header => header.MediaType == "application/json"))
        {
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        }

        if (!request.Headers.Contains(ScmAuthDiagnostics.CorrelationHeader))
        {
            request.Headers.TryAddWithoutValidation(
                ScmAuthDiagnostics.CorrelationHeader,
                ScmAuthDiagnostics.NewCorrelationId());
        }

        if (request.Headers.Authorization is null &&
            request.Options.TryGetValue(AccessTokenOption, out var accessToken) &&
            !string.IsNullOrWhiteSpace(accessToken))
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        }

        var response = await base.SendAsync(request, cancellationToken);
        ScmAuthDiagnostics.Write(
            request.Headers.GetValues(ScmAuthDiagnostics.CorrelationHeader).FirstOrDefault()
                ?? "missing",
            "http-response",
            response.IsSuccessStatusCode ? "success" : "http-error",
            $"method={request.Method.Method} status={(int)response.StatusCode}");
        return response;
    }
}

public class ScmApiProtocolException(string message) : InvalidOperationException(message);

public class ScmApiAuthenticationException(string message) : HttpRequestException(message, null, HttpStatusCode.Unauthorized);

public class ScmApiForbiddenException(string message) : HttpRequestException(message, null, HttpStatusCode.Forbidden);

public class ScmApiUnavailableException(string message) : HttpRequestException(message);

public sealed class ScmApiRateLimitException(string message, TimeSpan? retryAfter) : HttpRequestException(message)
{
    public TimeSpan? RetryAfter { get; } = retryAfter;
}
