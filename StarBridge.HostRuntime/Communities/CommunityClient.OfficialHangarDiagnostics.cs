using System.Diagnostics;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private async Task<T> ObserveOfficialHangarRead<T>(string stage, Func<Task<T>> read, int? status = null)
    {
        var started = Stopwatch.GetTimestamp();
        var code = "ok";
        try
        {
            var result = await read();
            if (result is HttpResponseMessage response)
            {
                status = (int)response.StatusCode;
                code = response.IsSuccessStatusCode ? "ok" : "http-error";
            }
            return result;
        }
        catch (Exception error)
        {
            code = error switch
            {
                AccountBridgeHostException { Code: "communities.dataInvalid" or "communities.refreshRequired" or
                    "communities.unavailable" or "communities.identityUnavailable" } host => host.Code,
                HttpRequestException or IOException or UnauthorizedAccessException => "network",
                OperationCanceledException => "cancelled",
                JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException => "communities.dataInvalid",
                _ => "unclassified"
            };
            throw;
        }
        finally
        {
            try { ReadDiagnostic?.Invoke(stage, code, status, (long)Stopwatch.GetElapsedTime(started).TotalMilliseconds); }
            catch { /* Diagnostics must preserve the original result and exception. */ }
        }
    }
}
