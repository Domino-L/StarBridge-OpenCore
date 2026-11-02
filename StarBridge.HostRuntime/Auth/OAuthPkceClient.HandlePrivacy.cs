using System.Net.Http.Json;
using StarBridge.HostRuntime.Privacy;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    internal async Task<(GameIdSettingsSnapshot Result, ScmOAuthSession ActiveSession)> ReadHandlePrivacyAsync(
        ScmOAuthSession session, CancellationToken token)
    {
        var result = await ReadAccountResourceAsync<GameIdSettingsSnapshot>(session, options.HandlePrivacyEndpoint,
            session.CorrelationId ?? Guid.NewGuid().ToString("N"), "handle-privacy-read", token);
        ValidateHandlePrivacy(result.Result);
        ScmSessionProbeDiagnostics.Snapshot(SessionProbeSnapshot.ValidatedResponse, result.Result);
        return result;
    }

    internal async Task<GameIdSettingsSnapshot> SaveHandlePrivacyAsync(ScmOAuthSession writeSession,
        long revision, string stamp, int locations, CancellationToken token)
    {
        if (!writeSession.Capabilities.Contains("profile.write", StringComparer.Ordinal))
            throw new ScmApiForbiddenException("当前授权不包含 profile.write。");
        if (revision < 0 || revision == long.MaxValue || locations is < 0 or > 15 || !ValidHandleStamp(stamp))
            throw new ArgumentException("Invalid Handle privacy update.");
        using var request = new HttpRequestMessage(HttpMethod.Patch, options.HandlePrivacyEndpoint)
        { Content = JsonContent.Create(new { expectedRevision = revision, identityStamp = stamp, locations }) };
        using var response = await scmHttpClient.SendAsync(request, writeSession.AccessToken, token);
        var result = await scmHttpClient.ReadJsonAsync<GameIdSettingsSnapshot>(response, "Handle 隐私保存", token);
        ValidateHandlePrivacy(result);
        if (result.Revision != revision + 1 || result.IdentityStamp != stamp || result.Locations != locations)
            throw new ScmApiProtocolException("Handle 隐私保存结果未得到确认。");
        return result; // Never install the one-time write grant as the normal read session.
    }

    private static bool ValidHandleStamp(string? stamp) => stamp is { Length: 64 } &&
        stamp.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');

    private static void ValidateHandlePrivacy(GameIdSettingsSnapshot result)
    {
        if (result.SchemaVersion != 1 || result.Revision < 0 || result.Locations is < 0 or > 15 ||
            !ValidHandleStamp(result.IdentityStamp) || !result.CanConfigure && result.Locations != 0)
            throw new ScmApiProtocolException("Handle 隐私响应无效。");
    }
}
