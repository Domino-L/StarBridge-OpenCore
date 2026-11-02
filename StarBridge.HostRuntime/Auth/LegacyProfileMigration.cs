using System.Net;
using System.Net.Http;
using System.Net.Http.Json;

namespace StarBridge.HostRuntime.Auth;

// Deliberately excludes legacy account ids, source keys, staged documents and all credentials.
public sealed record LegacyProfileMigrationSummary(
    string CallSign, string Introduction, int Modules, int Favorites, long? PlayTimeSeconds);
public sealed record LegacyProfileMigrationView(
    string State, string? PreviewId = null, string? SourceGameId = null,
    long SourceRevision = 0, long TargetRevision = 0, DateTimeOffset? ExpiresAt = null,
    bool Conflict = false, LegacyProfileMigrationSummary? Source = null,
    LegacyProfileMigrationSummary? Target = null, long? CompletedRevision = null,
    LegacyProfileImportChoices? Choices = null, string? AvatarPreview = null,
    LegacyProfileSelectedContent? SelectedContent = null, LegacyProfilePresentation? Presentation = null);
public sealed record LegacyProfilePresentation(string CallSign, int AvatarStyle, string WallpaperId,
    StarBridge.Core.Profiles.PersonalProfileContentContract Content);
public sealed record LegacyProfileSelectedModule(string Id, int Span);
public sealed record LegacyProfileSelectedContent(string? CallSign, LegacyProfileSelectedModule[] Modules,
    string[]? SkilledRoles, string[]? SupportCapabilities, string[]? ParticipationInterests)
{
    public bool Matches(LegacyProfileImportChoices choices)
    {
        try { new LegacyProfileImportSelection(choices.Modules, choices.ReplaceModules,
            choices.UseLegacyCallSign, choices.UseLegacyAvatar).Validate(); }
        catch (ArgumentException) { return false; }
        static bool Tags(string[]? values) => values is not null && values.Length <= 8 &&
            values.Distinct(StringComparer.Ordinal).Count() == values.Length &&
            values.All(v => !string.IsNullOrWhiteSpace(v) && v.Length <= 80 && !v.Any(char.IsControl));
        if (Modules is null || choices.Modules is null || Modules.Length != choices.Modules.Length ||
            Modules.Any(m => m is null || m.Span is < 1 or > 3) ||
            !Modules.Select(m => m.Id).SequenceEqual(choices.Modules)) return false;
        if (choices.UseLegacyCallSign ? string.IsNullOrWhiteSpace(CallSign) || CallSign.Length > 32 || CallSign.Any(char.IsControl)
            : CallSign is not null) return false;
        return choices.Modules.Contains("skilled-roles", StringComparer.Ordinal)
            ? Tags(SkilledRoles) && Tags(SupportCapabilities) && Tags(ParticipationInterests)
            : SkilledRoles is null && SupportCapabilities is null && ParticipationInterests is null;
    }
}
public sealed record LegacyProfileImportSelection(string[] Modules, string[] ReplaceModules, bool UseLegacyCallSign,
    bool UseLegacyAvatar = false, string? PreviousCompletedPreviewId = null, bool ReplaceAllDisplayContent = false)
{
    public void Validate()
    {
        static bool Valid(string[]? values) => values is not null && values.Length <= 3 &&
            values.Distinct(StringComparer.Ordinal).Count() == values.Length &&
            values.All(value => value is "favorite-ships" or "hangar-summary" or "skilled-roles");
        if (PreviousCompletedPreviewId is { } previous &&
            (string.IsNullOrWhiteSpace(previous) || previous.Length > 64 || previous.Any(char.IsControl)))
            throw new ArgumentException("Invalid previous import receipt.");
        if (!Valid(Modules) || !Valid(ReplaceModules) || ReplaceModules.Any(value => !Modules.Contains(value)) ||
            (ReplaceAllDisplayContent ? Modules.Length != 0 || ReplaceModules.Length != 0 || UseLegacyCallSign || UseLegacyAvatar
                : Modules.Length == 0 && !UseLegacyCallSign && !UseLegacyAvatar))
            throw new ArgumentException("Invalid module import selection.");
    }
}
public sealed record LegacyProfileImportChoices(int Version, string[] Modules, string[] ReplaceModules,
    bool UseLegacyCallSign, string[] NeedsReselection, bool UseLegacyAvatar = false);
public sealed record LegacyProfileMigrationResult(LegacyProfileMigrationView View, ScmOAuthSession ActiveSession);
public sealed record LegacyProfileCredential(string AccountName, string Password)
{
    public override string ToString() => "LegacyProfileCredential[REDACTED]";
}

public sealed partial class OAuthPkceClient
{
    public async Task<LegacyProfileMigrationResult> ExecuteLegacyProfileMigrationAsync(
        ScmOAuthSession session, string action, string? previewId, bool replaceExisting,
        CancellationToken cancellationToken, LegacyProfileCredential? credentials = null,
        LegacyProfileImportSelection? selection = null, bool presentationConfirm = false)
    {
        if (action is not ("status" or "preview" or "confirm"))
            throw new ArgumentException("Unknown migration operation.", nameof(action));
        if (action == "confirm" && !session.Capabilities.Contains("profile.write", StringComparer.Ordinal))
            throw new ScmApiForbiddenException("Migration requires profile.write.");
        selection?.Validate();
        if (selection is not null && action != "preview") throw new ArgumentException("Selection requires preview.");
        if (presentationConfirm && (action != "confirm" || !replaceExisting))
            throw new ArgumentException("Full display replacement requires explicit confirmation.");
        var endpoint = new Uri(options.ResourceServerBaseUri,
            "app-api/starbridge/v1/legacy-profile-migration" + (action == "status" ? "" :
                action == "preview" && selection?.ReplaceAllDisplayContent == true ? "/presentation-preview" :
                action == "confirm" && presentationConfirm ? "/presentation-confirm" :
                action == "preview" && selection is not null ? "/selected-preview" :
                action == "confirm" ? "/selected-confirm" : "/" + action));
        async Task<LegacyProfileMigrationView> Send(ScmOAuthSession current, CancellationToken token)
            {
                using var request = new HttpRequestMessage(action == "status" ? HttpMethod.Get : HttpMethod.Post, endpoint);
                if (action == "confirm")
                    request.Content = JsonContent.Create(new { previewId, replaceExisting });
                else if (action == "preview" && selection?.ReplaceAllDisplayContent == true)
                    request.Content = JsonContent.Create(new { credentials, replaceAllDisplayContent = true,
                        selection.PreviousCompletedPreviewId });
                else if (action == "preview" && selection is not null)
                    request.Content = JsonContent.Create(new { credentials,
                        selection = new { selection.Modules, selection.ReplaceModules }, selection.UseLegacyCallSign,
                        selection.UseLegacyAvatar, selection.PreviousCompletedPreviewId });
                else if (action == "preview" && credentials is not null)
                    request.Content = JsonContent.Create(new { credentials.AccountName, credentials.Password });
                using var response = await scmHttpClient.SendAsync(request, current.AccessToken, token,
                    action == "preview" ? TimeSpan.FromSeconds(45) : null);
                // Domain failures are safe allowlisted states, never arbitrary backend error strings.
                if (response.StatusCode is HttpStatusCode.Conflict or HttpStatusCode.ServiceUnavailable)
                {
                    var failed = await response.Content.ReadFromJsonAsync<LegacyProfileMigrationView>(token);
                    return new LegacyProfileMigrationView(AllowedFailure(failed?.State));
                }
                var result = await scmHttpClient.ReadJsonAsync<LegacyProfileMigrationView>(response, "Migration", token);
                if (result.State is not ("notStarted" or "previewed" or "completed") &&
                    AllowedFailure(result.State) != result.State)
                    throw new ScmApiProtocolException("Unknown migration response.");
                if (result.State == "previewed" &&
                    (string.IsNullOrWhiteSpace(result.PreviewId) || result.PreviewId.Length > 64 ||
                     result.Source is null || result.Target is null || result.ExpiresAt is null))
                    throw new ScmApiProtocolException("Incomplete migration preview.");
                if (selection?.ReplaceAllDisplayContent == true && result.State == "previewed" &&
                    (result.Choices is not { Version: 2 } || result.Presentation is null || !result.Conflict || result.SelectedContent is not null))
                    throw new ScmApiProtocolException("Full display replacement was not acknowledged.");
                if (selection is { ReplaceAllDisplayContent: false } && result.State == "previewed" &&
                    (result.Choices is not { Version: 1 } choices || choices.Modules is null || choices.ReplaceModules is null ||
                     !choices.Modules.SequenceEqual(selection.Modules) || !choices.ReplaceModules.SequenceEqual(selection.ReplaceModules) ||
                     choices.UseLegacyCallSign != selection.UseLegacyCallSign || choices.UseLegacyAvatar != selection.UseLegacyAvatar))
                    throw new ScmApiProtocolException("Migration selection was not acknowledged.");
                if ((result.State == "previewed" && result.Choices?.UseLegacyAvatar == true && result.AvatarPreview is null) ||
                    (result.AvatarPreview is { } avatar && !ValidAvatarPreview(avatar)))
                    throw new ScmApiProtocolException("Invalid avatar preview.");
                if (result.SelectedContent is { } content && (result.Choices is null || !content.Matches(result.Choices)) ||
                    result.State == "previewed" && selection is { ReplaceAllDisplayContent: false } && result.SelectedContent is null)
                    throw new ScmApiProtocolException("Invalid selected profile content.");
                return result;
            }
        // The short-lived write grant has no refresh token. Do not refresh it with the ordinary
        // read session, and do not replace the long-lived login session with this grant.
        if (action == "confirm")
            return new LegacyProfileMigrationResult(await Send(session, cancellationToken), session);
        var (view, activeSession) = await SendResourceRequestWithRefreshAndSessionAsync(
            session, Send, cancellationToken);
        activeSession = PublishResourceSession(activeSession);
        return new LegacyProfileMigrationResult(view, activeSession);
    }

    private static bool ValidAvatarPreview(string value)
    {
        const string prefix = "data:image/png;base64,";
        if (value.Length > 100000 || !value.StartsWith(prefix, StringComparison.Ordinal)) return false;
        try
        {
            var bytes = Convert.FromBase64String(value[prefix.Length..]);
            if (bytes.Length < 24 || !bytes.AsSpan(0, 8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }))
                return false;
            var width = System.Buffers.Binary.BinaryPrimitives.ReadUInt32BigEndian(bytes.AsSpan(16, 4));
            var height = System.Buffers.Binary.BinaryPrimitives.ReadUInt32BigEndian(bytes.AsSpan(20, 4));
            return width is > 0 and <= 128 && height is > 0 and <= 128;
        }
        catch (FormatException) { return false; }
    }

    private static string AllowedFailure(string? code) => code switch
    {
        "linkRequired" or "accountMismatch" or "authorizationRequired" or "unsupportedData" or
        "previewRequired" or "previewExpired" or "replacementRequired" or "targetChanged" or
        "sourceNotConfigured" or "credentialRequired" or "credentialRejected" or
        "verificationRateLimited" or "profileNotFound" or "selectionRequired" or "moduleReplacementRequired" or
        "sourceModuleMissing" or "invalidModuleSelection" or "replacementNotSelected" or "sourceAvatarUnavailable" => code,
        _ => "sourceUnavailable"
    };
}
