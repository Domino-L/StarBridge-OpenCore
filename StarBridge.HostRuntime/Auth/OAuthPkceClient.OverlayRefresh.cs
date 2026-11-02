using System.Net.Http;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    private async Task<ScmOAuthSession> RefreshOverlayQualificationAsync(
        ScmOAuthSession restored, ScmOAuthSession? previous, CancellationToken cancellationToken)
    {
        // Cold restoration has no previous projection; its Host still owns the
        // initial bootstrap. Rotation of a live account must revalidate the
        // projection, not silently erase it or copy potentially revoked grants.
        if (previous?.OverlayEntitlements is null ||
            !string.Equals(previous.AuthorityId, restored.AuthorityId, StringComparison.Ordinal) ||
            !string.Equals(previous.Subject, restored.Subject, StringComparison.Ordinal))
            return restored;

        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(ResourceRequestTimeout);
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        const string step = "overlay-qualification-refresh";
        var stopwatch = ScmAuthDiagnostics.Start(correlationId, step);
        try
        {
            // The caller owns the refresh gate and has just rotated the token.
            // Never re-enter the automatic-refresh wrapper here: that would
            // deadlock the gate for a near-expiry token or a returned 401.
            ScmAuthDiagnostics.Write(correlationId, step, "sending",
                $"credentialVersion={restored.CredentialVersion:N}");
            using var request = new HttpRequestMessage(HttpMethod.Get, options.BootstrapEndpoint);
            request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, correlationId);
            using var response = await scmHttpClient.SendAsync(request, restored.AccessToken, deadline.Token,
                requestTimeout: ResourceRequestTimeout);
            var snapshot = await scmHttpClient.ReadJsonAsync<ScmBootstrapSnapshot>(response, step, deadline.Token);
            if (snapshot.Profile is null ||
                !string.Equals(snapshot.Profile.Subject, restored.Subject, StringComparison.Ordinal))
                throw new ScmApiProtocolException("SCM bootstrap does not match the refreshed account.");
            var qualification = ValidateOverlayEntitlements(snapshot);
            deadline.Token.ThrowIfCancellationRequested();
            ScmAuthDiagnostics.Completed(correlationId, step, stopwatch,
                $"snapshotPresent={qualification is not null}");
            return restored with { OverlayEntitlements = qualification };
        }
        catch (OperationCanceledException error) when (!cancellationToken.IsCancellationRequested)
        {
            ScmAuthDiagnostics.Failed(correlationId, step, stopwatch, error);
            throw new ScmApiUnavailableException("Overlay qualification read timed out.");
        }
        catch (Exception error)
        {
            ScmAuthDiagnostics.Failed(correlationId, step, stopwatch, error);
            throw;
        }
    }
}
