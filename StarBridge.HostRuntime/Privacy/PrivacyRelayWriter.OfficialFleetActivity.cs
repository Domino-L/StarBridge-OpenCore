using System.Net.Http.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Privacy;

internal sealed partial class PrivacyRelayWriter
{
    internal async Task<bool> WaitOfficialRuntimeAsync(string bearer, string sourceRef, IReadOnlyList<string> subjects,
        CancellationToken token, Action current)
    {
        if (subjects.Count > 100 || subjects.Distinct(StringComparer.Ordinal).Count() != subjects.Count) throw Invalid();
        using var request = Request(HttpMethod.Post, OfficialUri("activity"), bearer);
        request.Content = JsonContent.Create(new { schemaVersion = 4, sourceRef, ownerBusinessSubjectIds = subjects });
        current();
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        RequireSuccess(response); using var document = await ReadAsync(response, token); current();
        try {
            var root = document.RootElement;
            if (root.GetProperty("schemaVersion").GetInt32() != 4 || root.GetProperty("sourceRef").GetString() != sourceRef ||
                root.EnumerateObject().Count() != 3) throw Invalid();
            var changed = root.GetProperty("changed").GetBoolean(); current(); return changed;
        } catch (Exception error) when (error is System.Text.Json.JsonException or InvalidOperationException or KeyNotFoundException or FormatException) { throw Invalid(); }
    }
}
