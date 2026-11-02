using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.PartyRooms;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    public sealed record PersonalProfileAvatarResult(int SchemaVersion, long Revision, string ImageData, string? RequestSha256);

    public async Task<PersonalProfileAvatarResult> UpdatePersonalProfileAvatarAsync(
        ScmOAuthSession writeSession, long expectedRevision, string imageData, CancellationToken token)
    {
        if (!writeSession.Capabilities.Contains("profile.write", StringComparer.Ordinal))
            throw new ScmApiForbiddenException("Avatar update requires profile.write.");
        if (expectedRevision < 0 || expectedRevision == long.MaxValue || RoomAvatarProjection.Normalize(imageData, 512 * 1024) is null)
            throw new ArgumentException("Invalid avatar update.");
        using var request = new HttpRequestMessage(HttpMethod.Patch,
            new Uri(options.PersonalProfileEndpoint.AbsoluteUri.TrimEnd('/') + "/avatar"))
        { Content = JsonContent.Create(new { expectedRevision, imageData }) };
        using var response = await scmHttpClient.SendAsync(request, writeSession.AccessToken, token,
            completionOption: HttpCompletionOption.ResponseHeadersRead);
        await ScmHttpClient.EnsureSuccessAsync(response, "Avatar update", token);
        using var document = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 720 * 1024);
        var result = document.RootElement.Deserialize<PersonalProfileAvatarResult>(new JsonSerializerOptions(JsonSerializerDefaults.Web));
        // The server normalizes pixels/metadata. Bind its acknowledgement to the exact request, not encoded-byte equality.
        var requestHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(imageData))).ToLowerInvariant();
        if (result is null || result.SchemaVersion != 1 || result.Revision != expectedRevision + 1 ||
                result.RequestSha256 != requestHash || RoomAvatarProjection.Normalize(result.ImageData, 512 * 1024) is not { } confirmed)
            throw new ScmApiProtocolException("Avatar write acknowledgement is invalid.");
        return result with { ImageData = confirmed }; // Never replace the normal session with a write grant.
    }
}
