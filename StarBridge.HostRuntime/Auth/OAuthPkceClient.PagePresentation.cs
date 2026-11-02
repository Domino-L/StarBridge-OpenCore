using System.Net.Http.Headers;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    private static readonly string[] PageGroups =
        ["introduction", "layout", "favorites", "schedule", "playStyle", "wishlist", "avatarStyle", "wallpaper"];

    private static PersonalProfileContentContract NormalizeVisitorContent(PersonalProfileContentContract content)
    {
        // Visitor responses intentionally omit owner edit provenance. That is
        // not a signal to downgrade their authorized layout to the old 3-card contract.
        var modules = content.Modules ?? [];
        var selected = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (modules.Length > 64 || modules.Any(module => module is null || module.Id is null ||
                (!Profiles.LocalProfileModulePolicy.IsFavorite(module.Id) &&
                 module.Id is not ("hangar-summary" or "skilled-roles")) ||
                module.Span is < 1 or > 3 || module.Position is < -1 or > 191 || module.Order < 0) ||
            modules.Select(module => module.Id).Distinct(StringComparer.Ordinal).Count() != modules.Length)
            throw new ScmApiProtocolException("Invalid visitor page layout.");
        foreach (var module in modules)
        {
            if (module.FavoriteShipIds is not { } ids) continue;
            if (!Profiles.LocalProfileModulePolicy.IsFavorite(module.Id) || ids.Length > module.Span ||
                ids.Any(id => !Guid.TryParseExact(id, "N", out _) || !selected.Add(id)))
                throw new ScmApiProtocolException("Invalid visitor page layout.");
        }
        // Display selections do not create a hangar or confer ownership.
        return PersonalProfileContractPolicy.Normalize(content) with { Modules = modules };
    }

    public async Task<PersonalProfileDocumentContract> UpdatePagePresentationAsync(
        ScmOAuthSession writeSession, PersonalProfilePageEditContract edit, CancellationToken token)
    {
        ArgumentNullException.ThrowIfNull(writeSession);
        ArgumentNullException.ThrowIfNull(edit);
        if (!writeSession.Capabilities.Contains("profile.write", StringComparer.Ordinal))
            throw new ScmApiForbiddenException("Page update requires profile.write.");
        var bytes = EncodePageEdit(edit);
        using var request = new HttpRequestMessage(HttpMethod.Patch,
            new Uri(options.PersonalProfileEndpoint.AbsoluteUri.TrimEnd('/') + "/presentation"))
        { Content = new ByteArrayContent(bytes) };
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        using var response = await scmHttpClient.SendAsync(request, writeSession.AccessToken, token,
            completionOption: HttpCompletionOption.ResponseHeadersRead);
        await ScmHttpClient.EnsureSuccessAsync(response, "Page presentation update", token);
        using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 1024 * 1024);
        var result = json.RootElement.Deserialize<PersonalProfileDocumentContract>(new JsonSerializerOptions(JsonSerializerDefaults.Web));
        if (result is null || result.SchemaVersion != PersonalProfileContractPolicy.CurrentSchemaVersion ||
            result.Revision != edit.ExpectedRevision + 1 || result.Content is null || result.Identity is null ||
            !ValidPagePresentation(result.Presentation) ||
            edit.EditedGroups.Any(group => result.Presentation!.Origins[group] != "custom"))
            throw new ScmApiProtocolException("Page write acknowledgement is invalid.");
        return result; // Host confirms via the normal read authority; never replace its session with this grant.
    }

    internal static byte[] EncodePageEdit(PersonalProfilePageEditContract edit)
    {
        ArgumentNullException.ThrowIfNull(edit);
        if (edit.ExpectedRevision < 0 || edit.ExpectedRevision == long.MaxValue ||
            !ValidPageSourceVersion(edit.SourceVersion) || edit.EditedGroups is not { Length: > 0 and <= 8 } ||
            edit.EditedGroups.Distinct(StringComparer.Ordinal).Count() != edit.EditedGroups.Length ||
            edit.EditedGroups.Any(group => !PageGroups.Contains(group, StringComparer.Ordinal)) ||
            edit.AvatarStyle is < 0 or > 3 || string.IsNullOrEmpty(edit.WallpaperId) ||
            edit.Content is null || edit.Content.PresenceIntent is not null)
            throw new ArgumentException("Invalid page update.");

        // Do not normalize here: normalization can silently discard rich local
        // layouts. The versioned server contract must accept the exact content.
        var content = JsonSerializer.SerializeToNode(edit.Content, new JsonSerializerOptions(JsonSerializerDefaults.Web))!.AsObject();
        content.Remove("presenceIntent");
        var bytes = JsonSerializer.SerializeToUtf8Bytes(new
        {
            schemaVersion = 1, expectedRevision = edit.ExpectedRevision,
            sourceVersion = edit.SourceVersion, editedGroups = edit.EditedGroups,
            page = new { avatarStyle = edit.AvatarStyle, wallpaperId = edit.WallpaperId, content }
        });
        if (bytes.Length > 64 * 1024) throw new ArgumentException("Page update exceeds the contract limit.");
        return bytes;
    }

    internal static bool ValidPagePresentation(PersonalProfilePagePresentationContract? value) =>
        value is { SchemaVersion: 1, Origins: not null } && ValidPageSourceVersion(value.SourceVersion) &&
        value.Origins.Count == PageGroups.Length && PageGroups.All(group =>
            value.Origins.TryGetValue(group, out var origin) && origin is "default" or "custom" or "imported" or "unknown" or "linkedLegacy");

    private static bool ValidPageSourceVersion(string? value) => value is null ||
        value.Length == 64 && value.All(character => character is >= '0' and <= '9' or >= 'a' and <= 'f');
}
