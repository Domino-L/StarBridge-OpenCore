using System.Runtime.ExceptionServices;
using System.Net.Http;

namespace StarBridge.HostRuntime.Auth;

public sealed record ScmGameIdentityVerificationAttempt(
    bool Accepted,
    bool Reconciled,
    string? Message,
    ScmOAuthSession ActiveSession);

/// <summary>
/// Treats the SCM identity projection as authoritative when a verification write has an
/// ambiguous transport outcome. A timed-out POST may already have committed server-side,
/// so the client performs one bounded read-back before offering a retry.
/// </summary>
public sealed class ScmGameIdentityVerificationCoordinator
{
    private readonly OAuthPkceClient _client;
    private readonly TimeSpan _requestTimeout;
    private readonly TimeSpan _reconciliationTimeout;

    public ScmGameIdentityVerificationCoordinator(
        OAuthPkceClient client,
        TimeSpan? requestTimeout = null,
        TimeSpan? reconciliationTimeout = null)
    {
        _client = client;
        _requestTimeout = requestTimeout ?? TimeSpan.FromSeconds(30);
        _reconciliationTimeout = reconciliationTimeout ?? TimeSpan.FromSeconds(10);
    }

    public async Task<ScmGameIdentityVerificationAttempt> VerifyAsync(
        ScmOAuthSession session,
        string gameName,
        string contact,
        CancellationToken cancellationToken)
    {
        ScmGameIdentityVerificationResult? result = null;
        Exception? ambiguousFailure = null;

        try
        {
            using var requestCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            requestCancellation.CancelAfter(_requestTimeout);
            result = await _client.VerifyGameIdentityAsync(
                session,
                gameName,
                contact,
                requestCancellation.Token);
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            ambiguousFailure = exception;
        }
        catch (HttpRequestException exception)
        {
            ambiguousFailure = exception;
        }

        cancellationToken.ThrowIfCancellationRequested();

        try
        {
            using var reconciliationCancellation =
                CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            reconciliationCancellation.CancelAfter(_reconciliationTimeout);
            var refreshedSession = await _client.RefreshIdentityAsync(
                session,
                reconciliationCancellation.Token);
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
                    ActiveSession: refreshedSession);
            }
        }
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
                ActiveSession: session);
        }

        ExceptionDispatchInfo.Capture(
            ambiguousFailure ?? new HttpRequestException("SCM 游戏身份验证状态未知。"))
            .Throw();
        throw new InvalidOperationException("Unreachable");
    }
}
