namespace StarBridge.HostRuntime.Account;

using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;
using System.Net.Http;
using System.Text.Json;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<LegacyProfileMigrationView> MigrateLegacyProfileAsync(
        BridgeAccountContext context, string action, string? previewId, bool replaceExisting,
        CancellationToken cancellationToken, LegacyProfileCredential? credentials = null)
    {
        await _mutationGate.WaitAsync(cancellationToken);
        try
        {
            var original = RequireSession(context);
            var session = action != "confirm" ? original
                : await _oauth.AuthorizeProfileWriteAsync(original, cancellationToken);
            RequireSameSession(original, session);
            var result = await _oauth.ExecuteLegacyProfileMigrationAsync(
                session, action, previewId, replaceExisting, cancellationToken, credentials);
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
