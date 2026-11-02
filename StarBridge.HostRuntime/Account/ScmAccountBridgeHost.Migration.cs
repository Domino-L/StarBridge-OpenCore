namespace StarBridge.HostRuntime.Account;

using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;
using System.Net.Http;
using System.Text.Json;

internal sealed partial class ScmAccountBridgeHost
{
    internal Profiles.SelectedProfileImportCoordinator? ProfileImportCoordinator { get; set; }
    public async Task<LegacyProfileMigrationView> MigrateLegacyProfileAsync(
        BridgeAccountContext context, string action, string? previewId, bool replaceExisting,
        CancellationToken cancellationToken, LegacyProfileCredential? credentials = null,
        LegacyProfileImportSelection? selection = null)
    {
        await _mutationGate.WaitAsync(cancellationToken);
        try
        {
            var original = RequireSession(context);
            var generation = Generation;
            if (selection?.ReplaceAllDisplayContent == true && ProfileImportCoordinator is null)
                return new("unsupportedData");
            if (ProfileImportCoordinator is { } coordinator)
                return await coordinator.RunAsync(context,
                    () => !_disposed && !_reauthorizationRequired && !_credentialTemporarilyUnavailable &&
                        !cancellationToken.IsCancellationRequested && CurrentContext == context && Generation == generation,
                    async local =>
                    {
                        if (action == "confirm")
                        {
                            var fullPresentation = local.FullPresentation(previewId!);
                            if (fullPresentation && !replaceExisting) return new("replacementRequired");
                            local.BeforeConfirm(previewId!, recordConsent: false);
                            // A lost confirmation response is recovered by a read, never an automatic POST replay.
                            var status = await _oauth.ExecuteLegacyProfileMigrationAsync(original, "status", null, false,
                                cancellationToken);
                            RequireSameSession(original, status.ActiveSession);
                            _session = status.ActiveSession;
                            if (status.View.State == "completed")
                            {
                                local.BeforeConfirm(previewId!);
                                return local.Apply(status.View);
                            }
                            if (status.View.State != "previewed") return status.View;
                            if (status.View.PreviewId != previewId) return new("previewRequired");
                            var grant = await _profileAuthorization.AuthorizeProfileWriteAsync(status.ActiveSession, cancellationToken);
                            RequireSameSession(original, grant);
                            local.BeforeConfirm(previewId!);
                            var confirmed = await _oauth.ExecuteLegacyProfileMigrationAsync(grant, "confirm", previewId,
                                fullPresentation && replaceExisting, cancellationToken, presentationConfirm: fullPresentation);
                            RequireSameSession(original, confirmed.ActiveSession);
                            return local.Apply(confirmed.View);
                        }
                        if (action == "preview") local.BeforePreview(selection);
                        var result = await _oauth.ExecuteLegacyProfileMigrationAsync(original, action, previewId,
                            replaceExisting, cancellationToken, credentials, selection);
                        RequireSameSession(original, result.ActiveSession);
                        _session = result.ActiveSession;
                        return action == "preview" ? local.Stage(result.View, selection) : local.Status(result.View);
                    });
            var session = action != "confirm" ? original
                : await _profileAuthorization.AuthorizeProfileWriteAsync(original, cancellationToken);
            RequireSameSession(original, session);
            var result = await _oauth.ExecuteLegacyProfileMigrationAsync(
                session, action, previewId, replaceExisting, cancellationToken, credentials, selection);
            RequireSameSession(original, result.ActiveSession);
            if (action != "confirm") _session = result.ActiveSession;
            return result.View;
        }
        catch (ScmApiAuthenticationException)
        {
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        }
        catch (ScmApiForbiddenException)
        {
            return new LegacyProfileMigrationView("authorizationRequired");
        }
        catch (OAuthAuthorizationDeniedException)
        { throw new OperationCanceledException("Profile import authorization was cancelled."); }
        catch (TimeoutException)
        { throw new AccountBridgeHostException(AccountBridgeStableErrors.LoginTimeout, retryable: true); }
        catch (Profiles.LocalProfileException exception)
        {
            return new LegacyProfileMigrationView(exception.Code switch
            {
                "profile_local.conflict" => "localTargetChanged",
                "profile_local.account_changed" => "authorizationRequired",
                "profile_local.import_replacement_required" => "moduleReplacementRequired",
                "profile_local.import_reselection_required" => "localReselectionRequired",
                "profile_local.import_preview_required" => "localPreviewRequired",
                "profile_local.invalid_request" => "unsupportedData",
                _ => "localSaveUnavailable"
            });
        }
        catch (Hangar.LocalHangarStoreException)
        { return new LegacyProfileMigrationView("localReselectionRequired"); }
        catch (System.Security.Cryptography.CryptographicException)
        { return new LegacyProfileMigrationView("localSaveUnavailable"); }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return new LegacyProfileMigrationView("sourceUnavailable");
        }
        catch (Exception exception) when (
            exception is HttpRequestException or IOException or JsonException or ScmApiProtocolException)
        {
            return new LegacyProfileMigrationView("sourceUnavailable");
        }
        finally { _mutationGate.Release(); }
    }
}
