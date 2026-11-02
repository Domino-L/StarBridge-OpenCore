using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    public sealed record PersonalProfileCallSignResult(int SchemaVersion, long Revision, string CallSign);

    public async Task<PersonalProfileCallSignResult> UpdatePersonalProfileCallSignAsync(
        ScmOAuthSession writeSession, long expectedRevision, string callSign, CancellationToken token)
    {
        if (!writeSession.Capabilities.Contains("profile.write", StringComparer.Ordinal))
            throw new ScmApiForbiddenException("Call sign update requires profile.write.");
        if (expectedRevision < 0 || expectedRevision == long.MaxValue || string.IsNullOrWhiteSpace(callSign) ||
            callSign != callSign.Trim() || callSign.Length > 32 || callSign.Any(char.IsControl))
            throw new ArgumentException("Invalid call sign update.");
        using var request = new HttpRequestMessage(HttpMethod.Patch,
            new Uri(options.PersonalProfileEndpoint.AbsoluteUri.TrimEnd('/') + "/callsign"))
        { Content = JsonContent.Create(new { expectedRevision, callSign }) };
        using var response = await scmHttpClient.SendAsync(request, writeSession.AccessToken, token,
            completionOption: HttpCompletionOption.ResponseHeadersRead);
        await ScmHttpClient.EnsureSuccessAsync(response, "Call sign update", token);
        using var document = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 8 * 1024);
        var result = document.RootElement.Deserialize<PersonalProfileCallSignResult>(new JsonSerializerOptions(JsonSerializerDefaults.Web));
        if (result is null || result.SchemaVersion != 1 || result.Revision != expectedRevision + 1 || result.CallSign != callSign)
            throw new ScmApiProtocolException("Call sign write acknowledgement is invalid.");
        return result; // A write grant must never replace the normal read session.
    }
}
