using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // DEPLOY-QUEUE §4b: the owner's SCM trade window is copied to the StarBridge profile service so
    // visitors outside the profile's visibility can still see it. Only the four window fields travel;
    // the SCM member id and contact never leave the Host. Best effort: a failure never touches the
    // trade profile result and the next read tries again.
    private readonly object _tradeWindowGate = new();
    private string? _tradeWindowSynced;
    private string? _tradeWindowUnsupported;

    /// <summary>The most recent background sync, for tests; null before the first one.</summary>
    internal Task? LastTradeWindowSync { get; private set; }

    internal void StartTradeWindowSync(ScmOAuthSession active, JsonElement scmProfile)
    {
        if (!active.Capabilities.Contains("profile.write", StringComparer.Ordinal)) return;
        var owner = active.AuthorityId + "\n" + active.Subject;
        var window = PersonalProfileTradeWindow.FromScm(scmProfile);
        var key = owner + "\n" + (window?.Fingerprint ?? "cleared");
        lock (_tradeWindowGate)
        {
            // Same value already confirmed, or the server said it does not take it (switch off).
            if (_tradeWindowSynced == key || _tradeWindowUnsupported == owner) return;
        }
        LastTradeWindowSync = SyncTradeWindowAsync(active, window, owner, key);
    }

    private async Task SyncTradeWindowAsync(ScmOAuthSession active, PersonalProfileTradeWindow? window, string owner, string key)
    {
        using var budget = new CancellationTokenSource(TimeSpan.FromSeconds(8));
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Put,
                new Uri(options.PersonalProfileEndpoint.AbsoluteUri.TrimEnd('/') + "/trade-window"))
            {
                Content = JsonContent.Create(window is null
                    ? (object)new { schemaVersion = 1, cleared = true }
                    : new { schemaVersion = 1, days = window.Days, start = window.Start, end = window.End, timezoneId = window.TimezoneId })
            };
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, budget.Token);
            lock (_tradeWindowGate)
            {
                if (response.StatusCode == HttpStatusCode.NoContent) _tradeWindowSynced = key;
                else if (response.StatusCode == HttpStatusCode.NotFound) _tradeWindowUnsupported = owner;
            }
            ScmAuthDiagnostics.Write("trade-window", "trade-window-sync", "status",
                "status=" + ((int)response.StatusCode).ToString(System.Globalization.CultureInfo.InvariantCulture));
        }
        catch (Exception exception)
        {
            ScmAuthDiagnostics.Write("trade-window", "trade-window-sync", "failed", $"exceptionType={exception.GetType().Name}");
        }
    }
}
