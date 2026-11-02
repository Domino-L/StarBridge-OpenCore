using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // This is a target-type route, never a fallback after a Java/SCM read fails.
    internal async Task<ScmPersonalProfileResult> LoadLegacyMemberVisitorPersonalProfileAsync(
        ScmOAuthSession session, string legacyId, CancellationToken token)
    {
        VisitorReadDiagnostics.Select(VisitorReadDiagnostics.Route.LegacyMember);
        if (!session.Capabilities.Contains("profile.read", StringComparer.Ordinal))
            throw new ScmApiForbiddenException("当前授权不包含 profile.read。");
        if (legacyId.Length is < 8 or > 128 || legacyId.Any(char.IsControl) || legacyId.StartsWith("scm-v1:", StringComparison.Ordinal))
            throw new AccountBridgeHostException("profile.visitor_identity_unavailable");
        var result = await SendResourceRequestWithRefreshAndSessionAsync(session, async (active, ct) =>
        {
            using var request = new HttpRequestMessage(HttpMethod.Post,
                new Uri(options.PersonalProfileEndpoint.AbsoluteUri.TrimEnd('/') + "/visitor-legacy"))
            { Content = JsonContent.Create(new { schemaVersion = 1, legacyAccountId = legacyId }) };
            request.Options.Set(VisitorReadDiagnostics.VisitorRequest, true);
            request.Headers.TryAddWithoutValidation(PersonalProfilePublicHeader.AcceptHeader, PersonalProfilePublicHeader.AcceptValue);
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(ct);
            budget.CancelAfter(TimeSpan.FromSeconds(12));
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, budget.Token);
            if (response.StatusCode == HttpStatusCode.Unauthorized)
                throw new ScmApiAuthenticationException("当前登录需要重新确认。");
            if (!response.IsSuccessStatusCode && response.StatusCode != HttpStatusCode.NotFound)
                throw new AccountBridgeHostException("profile.visitor_identity_unavailable", retryable: true);
            JsonDocument document;
            try { document = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, budget.Token, 8 * 1024 * 1024); }
            catch (JsonException) { throw new AccountBridgeHostException("profile.visitor_identity_unavailable"); }
            using var json = document;
            var root = json.RootElement;
            if (response.StatusCode == HttpStatusCode.NotFound && root.ValueKind == JsonValueKind.Object &&
                root.TryGetProperty("code", out var code) && code.GetString() == "PERSONAL_PROFILE_NOT_AVAILABLE")
                throw new AccountBridgeHostException("profile.visitor_not_visible");
            // A missing route, disabled rollout or unavailable authority is not proof of an unlinked/private account.
            if (!response.IsSuccessStatusCode)
                throw new AccountBridgeHostException("profile.visitor_identity_unavailable", retryable: true);
            if (PersonalProfilePublicHeader.IsRestricted(root))
            {
                try { return (Profile: (PersonalProfileDocumentContract?)null, Header: (PersonalProfilePublicHeader?)PersonalProfilePublicHeader.Parse(root, legacyId)); }
                catch (JsonException) { throw new AccountBridgeHostException("profile.visitor_identity_unavailable"); }
            }
            if (root.ValueKind != JsonValueKind.Object || root.EnumerateObject().Count() != 3 ||
                root.EnumerateObject().Select(p => p.Name).Distinct().Count() != 3 ||
                root.GetProperty("schemaVersion").GetInt32() != 1 || root.GetProperty("legacyAccountId").GetString() != legacyId)
                throw new AccountBridgeHostException("profile.visitor_identity_unavailable");
            var profile = root.GetProperty("profile").Deserialize<PersonalProfileDocumentContract>(new JsonSerializerOptions(JsonSerializerDefaults.Web));
            if (profile is null || profile.SchemaVersion != PersonalProfileContractPolicy.CurrentSchemaVersion ||
                profile.Revision < 0 || string.IsNullOrWhiteSpace(profile.PublicId) || profile.Identity is null || profile.Content is null)
                throw new ScmApiProtocolException("个人页面响应无效。");
            ct.ThrowIfCancellationRequested();
            return (Profile: profile with { Content = NormalizeVisitorContent(profile.Content) }, Header: (PersonalProfilePublicHeader?)null);
        }, token);
        return new(result.Result.Profile!, result.ActiveSession) { Restricted = result.Result.Header };
    }
}
