using System.Net.Http;

namespace StarBridge.HostRuntime.Auth;

public sealed record ScmGameIdentityVerificationAttempt(
    bool Accepted,
    bool Reconciled,
    string? Message,
    ScmOAuthSession ActiveSession,
    bool OutcomeUnknown = false);

/// <summary>
/// Treats the SCM identity projection as authoritative when a verification write has an
/// ambiguous transport outcome. A timed-out POST may already have committed server-side,
/// so the client performs one bounded read-back before offering a retry.
/// </summary>
public sealed class ScmGameIdentityVerificationCoordinator
{
    private readonly TimeSpan _requestTimeout;
    private readonly TimeSpan _reconciliationTimeout;
    private readonly Func<ScmOAuthSession, CancellationToken, Action<ScmOAuthSession>?, Task<ScmOAuthSession>> _readIdentity;
    private readonly Func<ScmOAuthSession, string, string, CancellationToken, Action<ScmOAuthSession>?, Task<ScmGameIdentityVerificationResult>> _verifyIdentity;

    public ScmGameIdentityVerificationCoordinator(
        OAuthPkceClient client,
        TimeSpan? requestTimeout = null,
        TimeSpan? reconciliationTimeout = null)
    {
        _requestTimeout = requestTimeout ?? TimeSpan.FromSeconds(30);
        _reconciliationTimeout = reconciliationTimeout ?? TimeSpan.FromSeconds(10);
        _readIdentity = client.RefreshIdentityAsync;
        _verifyIdentity = client.VerifyGameIdentityAsync;
    }

    // Candidate IO must never enter the installed resource-session pipeline.
    // Ordinary account/WPF callers retain exactly the public constructor policy.
    internal ScmGameIdentityVerificationCoordinator(OAuthPkceClient client,
        Func<ScmOAuthSession, CancellationToken, Action<ScmOAuthSession>?, Task<ScmOAuthSession>> readIdentity,
        Func<ScmOAuthSession, string, string, CancellationToken, Action<ScmOAuthSession>?, Task<ScmGameIdentityVerificationResult>> verifyIdentity)
        : this(client)
    { _readIdentity = readIdentity; _verifyIdentity = verifyIdentity; }

    public async Task<ScmGameIdentityVerificationAttempt> VerifyAsync(
        ScmOAuthSession session,
        string gameName,
        string contact,
        CancellationToken cancellationToken, Action<ScmOAuthSession>? sessionReady = null)
    {
        void Adopt(ScmOAuthSession active) { sessionReady?.Invoke(active); session = active; }
        ScmGameIdentityVerificationResult? result = null;

        try
        {
            using var requestCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            requestCancellation.CancelAfter(_requestTimeout);
            result = await _verifyIdentity(
                session,
                gameName,
                contact,
                requestCancellation.Token, Adopt);
        }
        catch (ScmApiForbiddenException) { throw; }
        catch (ScmApiAuthenticationException) { throw; }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested) { }
        catch (HttpRequestException) { }

        cancellationToken.ThrowIfCancellationRequested();

        try
        {
            using var reconciliationCancellation =
                CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            reconciliationCancellation.CancelAfter(_reconciliationTimeout);
            var refreshedSession = await _readIdentity(
                session,
                reconciliationCancellation.Token, Adopt);
            if (refreshedSession.GameIdentityVerified)
            {
                return new ScmGameIdentityVerificationAttempt(
                    Accepted: true,
                    Reconciled: result?.Success != true,
                    Message: result?.Message,
                    ActiveSession: refreshedSession);
            }

            if (result is not null)
            {
                return new ScmGameIdentityVerificationAttempt(
                    Accepted: result.Available && result.Success,
                    Reconciled: false,
                    Message: result.Message,
                    ActiveSession: refreshedSession,
                    OutcomeUnknown: !result.Available);
            }
        }
        catch (ScmApiForbiddenException) { throw; }
        catch (ScmApiAuthenticationException) { throw; }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // The read-back has its own bounded budget. Preserve the original outcome below.
        }
        catch (HttpRequestException)
        {
            // The authoritative read is temporarily unavailable. Preserve the original outcome.
        }

        cancellationToken.ThrowIfCancellationRequested();
        if (result is not null)
        {
            return new ScmGameIdentityVerificationAttempt(
                Accepted: result.Available && result.Success,
                Reconciled: false,
                Message: result.Message,
                ActiveSession: session,
                OutcomeUnknown: !result.Available);
        }

        // Neither a transport exception nor its text is safe to propagate:
        // handlers and upstream failures can include the submitted private data.
        throw new HttpRequestException("SCM game identity verification outcome is unknown.");
    }
}
