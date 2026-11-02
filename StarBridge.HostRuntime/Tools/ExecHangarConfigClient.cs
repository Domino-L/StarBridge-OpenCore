using System.Text.Json;
using StarBridge.Core.Tools;

namespace StarBridge.HostRuntime.Tools;

public interface IExecHangarConfigClient
{
    Task<ExecHangarConfig> FetchAsync(CancellationToken token);
}

/// <summary>A bounded anonymous GET to the configured SCM authority. No token or cookie transport.</summary>
public sealed class ExecHangarConfigClient : IExecHangarConfigClient, IDisposable
{
    private readonly HttpClient _http;
    private readonly Uri _endpoint;
    public ExecHangarConfigClient(Uri apiBase, HttpMessageHandler? handler = null)
    {
        if (apiBase.Scheme != "https" && !(apiBase.Scheme == "http" && apiBase.IsLoopback) ||
            apiBase.UserInfo.Length != 0) throw new ArgumentException("Invalid SCM authority.");
        _endpoint = new(apiBase, "app-api/system/exec-hangar/config");
        _http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false });
        _http.Timeout = TimeSpan.FromSeconds(8);
    }
    public async Task<ExecHangarConfig> FetchAsync(CancellationToken token)
    {
        using var response = await _http.GetAsync(_endpoint, HttpCompletionOption.ResponseHeadersRead, token);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength is > 32768) throw new InvalidDataException();
        using var stream = await response.Content.ReadAsStreamAsync(token);
        using var bytes = new MemoryStream(); var buffer = new byte[4096];
        int count;
        while ((count = await stream.ReadAsync(buffer, token)) != 0) {
            if (bytes.Length + count > 32768) throw new InvalidDataException();
            bytes.Write(buffer, 0, count);
        }
        using var json = JsonDocument.Parse(bytes.ToArray(), new() { MaxDepth = 8 });
        var root = json.RootElement;
        if (root.GetProperty("code").GetInt32() != 0) throw new InvalidDataException();
        var data = root.GetProperty("data");
        if (data.EnumerateObject().Select(p => p.Name).Distinct().Count() != data.EnumerateObject().Count())
            throw new InvalidDataException();
        var result = new ExecHangarConfig(data.GetProperty("version").GetString()!,
            data.GetProperty("lastModified").GetString()!,
            data.TryGetProperty("sourceUrl", out var source) ? source.GetString() : null,
            data.GetProperty("initialOpenTime").GetDateTimeOffset(), data.GetProperty("cycleDriftMs").GetInt32(),
            data.GetProperty("designOnlineMin").GetInt32(), data.GetProperty("designOfflineMin").GetInt32(),
            data.GetProperty("cycleNumberOffset").GetInt32(),
            !data.TryGetProperty("stale", out var stale) || stale.GetBoolean());
        result.Validate(); return result;
    }
    public void Dispose() => _http.Dispose();
}
