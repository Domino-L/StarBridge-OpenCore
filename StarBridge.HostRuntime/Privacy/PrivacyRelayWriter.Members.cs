using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Privacy;

internal sealed partial class PrivacyRelayWriter
{
    internal async Task<CommunityMemberDirectoryPage> ReadCommunityMembersAsync(
        string bearer, CommunityMemberDirectoryRequest input, CancellationToken token)
    {
        ValidateMemberRequest(input);
        using var request = Request(HttpMethod.Post, _communityMembers, bearer);
        request.Content = JsonContent.Create(input, options: LocalPrivacyStore.Json);
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        if (response.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed or HttpStatusCode.Gone)
            throw new AccountBridgeHostException("privacy_publication.member_scopes_unavailable");
        if (response.StatusCode == HttpStatusCode.Conflict)
            throw new AccountBridgeHostException("privacy_publication.members_changed");
        RequireSuccess(response);
        using var document = await ReadAsync(response, token);
        try
        {
            var page = document.RootElement.Deserialize<CommunityMemberDirectoryPage>(LocalPrivacyStore.Json);
            if (page is null || page.SchemaVersion != 3 || page.Code != input.Scope.Code ||
                page.JoinedAt != input.Scope.JoinedAt || page.Offset != input.Offset ||
                page.Total < page.Offset || page.Total > 100000 || !ValidRevision(page.Revision) ||
                input.Offset > 0 && page.Revision != input.Revision || page.Members is null ||
                page.Members.Length != Math.Min(100, page.Total - page.Offset)) throw Invalid();
            foreach (var member in page.Members)
            {
                if (member is null || !ValidMemberText(member.Name, 256) || !ValidMemberText(member.Handle, 256)) throw Invalid();
                CommunityMemberFieldOverride.ValidateAndCopy([
                    new(member.AccountId, member.JoinedAt, member.LegacyGroupFields)]);
            }
            if (page.Members.Select(row => row.AccountId).Distinct(StringComparer.OrdinalIgnoreCase).Count() != page.Members.Length ||
                page.Members.Count(row => row.IsSelf) > 1) throw Invalid();
            return page;
        }
        catch (Exception error) when (error is JsonException or ArgumentException) { throw Invalid(); }
    }

    internal static void ValidateMemberRequest(CommunityMemberDirectoryRequest input)
    {
        if (input.SchemaVersion != 3 || input.Offset < 0 || input.Offset > 100000 ||
            input.Offset % 100 != 0 || input.Offset > 0 && !ValidRevision(input.Revision) ||
            input.Offset == 0 && input.Revision is not null)
            throw new ArgumentException("Invalid member directory request.");
        CommunityRealtimeScope.ValidateAndCopy([input.Scope]);
    }

    private static bool ValidRevision(string? value) => value is { Length: 64 } && value.All(Uri.IsHexDigit);
    private static bool ValidMemberText(string? value, int maximum) => value is not null &&
        value.Length <= maximum && !value.Any(char.IsControl);
}
