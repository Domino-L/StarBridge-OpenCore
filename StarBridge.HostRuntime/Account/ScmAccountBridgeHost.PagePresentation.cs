using System.Net;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<PersonalProfileDocumentContract> UpdatePagePresentationAsync(
        BridgeAccountContext context, PersonalProfilePageEditContract edit, CancellationToken token)
    {
        try { _ = OAuthPkceClient.EncodePageEdit(edit); }
        catch (ArgumentException) { throw new AccountBridgeHostException("personalProfile.write_invalid"); }
        await _mutationGate.WaitAsync(token);
        var attempted = false;
        try
        {
            var owner = RequireSession(context);
            var generation = Generation;
            void Current()
            {
                token.ThrowIfCancellationRequested();
                RequireSameSession(owner, RequireSession(context));
                if (_disposed || Generation != generation)
                    throw new AccountBridgeHostException("account.reauthorization_required");
            }
            if (!owner.Capabilities.Contains("profile.read", StringComparer.Ordinal))
                throw new ScmApiForbiddenException("Page preflight requires profile.read.");
            var before = await GetPersonalProfileAsync(context, token);
            Current();
            if (!OAuthPkceClient.ValidPagePresentation(before.Presentation) ||
                before.Revision != edit.ExpectedRevision || before.Presentation!.SourceVersion != edit.SourceVersion)
                throw new AccountBridgeHostException(AccountBridgeStableErrors.PersonalProfileWriteConflict);
            var grant = await _profileAuthorization.AuthorizeProfileWriteAsync(RequireSession(context), token);
            RequireSameSession(owner, grant);
            Current();
            if (!grant.Capabilities.Contains("profile.write", StringComparer.Ordinal))
                throw new ScmApiForbiddenException("Page mutation requires profile.write.");
            attempted = true;
            var saved = await _oauth.UpdatePagePresentationAsync(grant, edit, token);
            Current();
            var confirmed = await GetPersonalProfileAsync(context, token);
            Current();
            if (confirmed.Revision != saved.Revision || confirmed.PublicId != before.PublicId ||
                !OAuthPkceClient.ValidPagePresentation(confirmed.Presentation) ||
                edit.EditedGroups.Any(group => confirmed.Presentation!.Origins[group] != "custom") ||
                !PageEditMatches(edit, confirmed))
                throw new AccountBridgeHostException("personalProfile.write_unconfirmed");
            return confirmed;
        }
        catch (AccountBridgeHostException e) when (attempted && PersonalProfileReadFailures.IsReadFailure(e.Code))
        { throw new AccountBridgeHostException("personalProfile.write_unconfirmed"); }
        catch (ScmApiForbiddenException)
        { throw new AccountBridgeHostException(attempted ? "personalProfile.write_unconfirmed" : AccountBridgeStableErrors.PersonalProfileWriteForbidden); }
        catch (ScmApiAuthenticationException)
        { throw new AccountBridgeHostException(attempted ? "personalProfile.write_unconfirmed" : AccountBridgeStableErrors.ReauthorizationRequired); }
        catch (OAuthAuthorizationDeniedException)
        { throw new OperationCanceledException("Page authorization was cancelled."); }
        catch (HttpRequestException e) when (e.StatusCode == HttpStatusCode.Conflict)
        { throw new AccountBridgeHostException(AccountBridgeStableErrors.PersonalProfileWriteConflict); }
        catch (OperationCanceledException) when (attempted)
        { throw new AccountBridgeHostException("personalProfile.write_unconfirmed"); }
        catch (Exception e) when (e is HttpRequestException or IOException or InvalidOperationException)
        { throw new AccountBridgeHostException(attempted ? "personalProfile.write_unconfirmed" : "personalProfile.read_unavailable"); }
        finally { if (!_disposed) _mutationGate.Release(); }
    }

    private static bool PageEditMatches(PersonalProfilePageEditContract edit, PersonalProfileDocumentContract profile)
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var expected = JsonSerializer.SerializeToElement(edit.Content, options);
        var actual = JsonSerializer.SerializeToElement(profile.Content, options);
        foreach (var group in edit.EditedGroups)
        {
            if (group == "avatarStyle") { if (edit.AvatarStyle != profile.AvatarStyle) return false; continue; }
            if (group == "wallpaper") { if (edit.WallpaperId != profile.WallpaperId) return false; continue; }
            string[] fields = group switch
            {
                "introduction" => ["introduction"], "layout" => ["modules"],
                "favorites" => ["favoriteShipCodes"], "wishlist" => ["shipWishlist"],
                "playStyle" => ["skilledRoles", "supportCapabilities", "participationInterests"],
                "schedule" => ["showOnlineTime", "onlineTimeStart", "onlineTimeEnd", "activityRhythm", "availabilityTimeZoneId", "availabilityWindows"],
                _ => throw new InvalidOperationException("Unsupported page group")
            };
            if (fields.Any(field => expected.GetProperty(field).GetRawText() != actual.GetProperty(field).GetRawText())) return false;
        }
        return true;
    }
}
