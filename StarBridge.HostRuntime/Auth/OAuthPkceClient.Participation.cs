using System.Net.Http.Json;
using System.Text.Json;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // Explicit authenticated self participation, never a target selected by search.
    internal async Task RegisterParticipantAsync(ScmOAuthSession session, string expectedId, CancellationToken token,
        bool refreshOnly = false)
    {
        using var request = new HttpRequestMessage(refreshOnly ? HttpMethod.Put : HttpMethod.Post,
            new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/business-identity/registration" +
                (refreshOnly ? "/discovery" : "")))
            { Content = JsonContent.Create(new { }) };
        using var response = await scmHttpClient.SendAsync(request, session.AccessToken, token,
            requestTimeout: TimeSpan.FromSeconds(5), completionOption: HttpCompletionOption.ResponseHeadersRead);
        await ScmHttpClient.EnsureSuccessAsync(response, "参与者登记", token);
        using var stream = await response.Content.ReadAsStreamAsync(token);
        var bytes = new byte[4097];
        var count = 0;
        while (count < bytes.Length) {
            var read = await stream.ReadAsync(bytes.AsMemory(count), token);
            if (read == 0) break;
            count += read;
        }
        if (count > 4096) throw new ScmApiProtocolException("参与者登记回执过大。");
        using var json = JsonDocument.Parse(bytes.AsMemory(0, count));
        var root = json.RootElement;
        if (root.ValueKind != JsonValueKind.Object || root.EnumerateObject().Count() != 2 ||
            !root.TryGetProperty("schemaVersion", out var version) || !version.TryGetInt32(out var schema) || schema != 1 ||
            !root.TryGetProperty("businessSubjectId", out var id) || id.ValueKind != JsonValueKind.String ||
            id.GetString() != expectedId)
            throw new ScmApiProtocolException("参与者登记回执与当前账号不一致。");
    }
}
