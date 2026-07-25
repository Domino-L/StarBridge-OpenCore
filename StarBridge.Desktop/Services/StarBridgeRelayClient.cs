using System.Net.Http;
using System.Net.Http.Json;
using System.Net.Http.Headers;

namespace StarBridge.Desktop;

public sealed class StarBridgeRelayClient
{
    private readonly HttpClient _httpClient;
    private readonly Func<string> _baseUrlProvider;
    private readonly Func<string?> _relayKeyProvider;
    private readonly Func<string?> _authTokenProvider;
    private readonly Func<bool> _userDataSyncAllowed;

    public StarBridgeRelayClient(
        HttpClient httpClient,
        Func<string> baseUrlProvider,
        Func<string?> relayKeyProvider,
        Func<string?> authTokenProvider,
        Func<bool>? userDataSyncAllowed = null)
    {
        _httpClient = httpClient;
        _baseUrlProvider = baseUrlProvider;
        _relayKeyProvider = relayKeyProvider;
        _authTokenProvider = authTokenProvider;
        _userDataSyncAllowed = userDataSyncAllowed ?? (() => true);
    }

    public Uri BuildUri(string path)
    {
        var baseUrl = _baseUrlProvider().Trim();
        if (string.IsNullOrWhiteSpace(baseUrl))
        {
            baseUrl = "https://api.scstarbridge.com";
        }

        if (!baseUrl.EndsWith("/", StringComparison.Ordinal))
        {
            baseUrl += "/";
        }

        return new Uri(new Uri(baseUrl), path);
    }

    public async Task<T?> GetFromJsonAsync<T>(string path)
    {
        EnsureUserDataSyncAllowed(path);
        using var request = new HttpRequestMessage(HttpMethod.Get, BuildUri(path));
        AddAuthHeaders(request);
        using var response = await _httpClient.SendAsync(request);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<T>();
    }

    public Task<HttpResponseMessage> GetAsync(string path)
    {
        EnsureUserDataSyncAllowed(path);
        var request = new HttpRequestMessage(HttpMethod.Get, BuildUri(path));
        AddAuthHeaders(request);
        return _httpClient.SendAsync(request);
    }

    public Task<HttpResponseMessage> PostJsonAsync<T>(string path, T payload)
    {
        EnsureUserDataSyncAllowed(path);
        var request = new HttpRequestMessage(HttpMethod.Post, BuildUri(path))
        {
            Content = JsonContent.Create(payload)
        };
        AddAuthHeaders(request);
        return _httpClient.SendAsync(request);
    }

    public Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken = default)
    {
        EnsureUserDataSyncAllowed(request.RequestUri?.AbsolutePath ?? "");
        AddAuthHeaders(request);
        return _httpClient.SendAsync(request, cancellationToken);
    }

    private void AddAuthHeaders(HttpRequestMessage request)
    {
        var key = _relayKeyProvider()?.Trim();
        if (!string.IsNullOrWhiteSpace(key))
        {
            request.Headers.Add("X-StarBridge-Key", key);
        }

        var authToken = _authTokenProvider()?.Trim();
        if (!string.IsNullOrWhiteSpace(authToken))
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authToken);
        }
    }

    private void EnsureUserDataSyncAllowed(string path)
    {
        if (_userDataSyncAllowed() || IsIdentityIndependentPath(path))
        {
            return;
        }

        throw new IdentitySyncBlockedException();
    }

    private static bool IsIdentityIndependentPath(string path)
    {
        var normalized = path.Trim().TrimStart('/');
        return normalized.StartsWith("api/auth/", StringComparison.OrdinalIgnoreCase) ||
               normalized.StartsWith("api/update", StringComparison.OrdinalIgnoreCase) ||
               normalized.StartsWith("api/app-stats", StringComparison.OrdinalIgnoreCase) ||
               normalized.StartsWith("api/feedback", StringComparison.OrdinalIgnoreCase) ||
               normalized.Equals("health", StringComparison.OrdinalIgnoreCase) ||
               normalized.Equals("api/health", StringComparison.OrdinalIgnoreCase);
    }
}

public sealed class IdentitySyncBlockedException : InvalidOperationException
{
    public IdentitySyncBlockedException()
        : base("无法验证游戏身份，所有用户数据同步已暂停。")
    {
    }
}
