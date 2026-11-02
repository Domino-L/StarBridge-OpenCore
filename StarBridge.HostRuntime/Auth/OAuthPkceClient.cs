using StarBridge.Core.Identity;
using StarBridge.Core.Profiles;
using System.Diagnostics;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Auth;

public sealed record ScmOAuthSession(
    string AuthorityId,
    string Subject,
    string DisplayName,
    string AccessToken,
    DateTimeOffset ExpiresAt,
    string[] Capabilities,
    bool GameIdentityVerified = false,
    string? CorrelationId = null,
    string? GameIdentityHandle = null,
    ScmGameIdentityStatus GameIdentityStatus = ScmGameIdentityStatus.Unknown,
    string? GameIdentityNormalizedHandle = null,
    string? GameIdentityVerificationMethod = null,
    DateTimeOffset? GameIdentityVerifiedAt = null,
    ScmOverlayEntitlementSnapshot? OverlayEntitlements = null)
{
    // New for every token rotation; preserved by record metadata copies.
    public Guid CredentialVersion { get; internal init; } = Guid.NewGuid();

    public ScmGameIdentitySnapshot AuthoritativeGameIdentity => new(
        GameIdentityStatus != ScmGameIdentityStatus.Unknown
            ? GameIdentityStatus
            : GameIdentityVerified
                ? ScmGameIdentityStatus.Verified
                : ScmGameIdentityStatus.Unknown,
        GameIdentityHandle,
        GameIdentityNormalizedHandle);

    // Candidate-only callers use this to repair verification authorization.
    // Verified, pending and unknown identity states never qualify.
    internal bool RequiresFirstUseGameIdentityReauthorization =>
        AuthoritativeGameIdentity.Status is (ScmGameIdentityStatus.Unverified or
            ScmGameIdentityStatus.ReverifyRequired or ScmGameIdentityStatus.Revoked) &&
        !Capabilities.Contains("game_identity.verify", StringComparer.Ordinal);

    public IReadOnlyList<string> ActiveOverlayEntitlements =>
        OverlayEntitlements?.ResolveActive(DateTimeOffset.UtcNow) ?? [];
}

public sealed record ScmGameIdentityContract(
    string? Status,
    string? Handle,
    string? NormalizedHandle,
    bool Verified,
    string? VerificationMethod = null,
    DateTimeOffset? VerifiedAt = null)
{
    public ScmGameIdentitySnapshot ToSnapshot() => new(
        ParseStatus(Status, Verified),
        string.IsNullOrWhiteSpace(Handle) ? null : Handle.Trim(),
        string.IsNullOrWhiteSpace(NormalizedHandle)
            ? null
            : NormalizedHandle.Trim().ToLowerInvariant());

    private static ScmGameIdentityStatus ParseStatus(string? status, bool verified) =>
        status?.Trim().ToUpperInvariant() switch
        {
            "UNVERIFIED" => ScmGameIdentityStatus.Unverified,
            "PENDING" => ScmGameIdentityStatus.Pending,
            "VERIFIED" => ScmGameIdentityStatus.Verified,
            "REVERIFY_REQUIRED" => ScmGameIdentityStatus.ReverifyRequired,
            "REVOKED" => ScmGameIdentityStatus.Revoked,
            "UNKNOWN" => ScmGameIdentityStatus.Unknown,
            _ when verified => ScmGameIdentityStatus.Verified,
            _ => ScmGameIdentityStatus.Unknown
        };
}

public enum ScmSessionRestoreOutcome
{
    NotAttempted,
    Restored,
    NoStoredCredential,
    CredentialTemporarilyUnavailable,
    ReauthorizationRequired
}

public sealed record ScmGameIdentityVerificationCode(
    bool Available,
    bool Success,
    string? Message,
    string? VerificationCode,
    [property: JsonPropertyName("expireTime")] long? ExpireTimeValue)
{
    // SCM may omit the expiry on rejection. Keep the numeric desktop API while
    // preserving null in the wire contract; zero cannot produce an issued code.
    [JsonIgnore]
    public long ExpireTime => ExpireTimeValue ?? 0;
}

public sealed record ScmGameIdentityVerificationResult(
    bool Available,
    bool Success,
    string? Message);

public sealed record ScmBootstrapProfile(
    string Subject,
    string? DisplayName,
    string? AvatarUrl,
    bool? GameIdentityVerified,
    string? Email = null,
    string? Locale = null,
    string? TimeZone = null,
    ScmGameIdentityContract? GameIdentity = null);

public sealed record ScmBootstrapIdentityLink(bool Linked, string? LegacyAccountId);

public sealed record ScmTemporaryOverlayEntitlementGrant(
    string Entitlement,
    DateTimeOffset ExpiresAt);

public sealed record ScmOverlayEntitlementSnapshot(
    string? Status,
    string? AccountId,
    string[]? Entitlements,
    ScmTemporaryOverlayEntitlementGrant[]? TemporaryEntitlements,
    DateTimeOffset? ObservedAt = null,
    JsonElement? OfflineReceipt = null)
{
    public string[] ResolveActive(DateTimeOffset now)
    {
        if (!string.Equals(Status?.Trim(), "ready", StringComparison.OrdinalIgnoreCase))
        {
            return [];
        }

        return (Entitlements ?? [])
            .Concat((TemporaryEntitlements ?? [])
                .Where(grant => grant.ExpiresAt > now)
                .Select(grant => grant.Entitlement))
            .Select(value => value?.Trim())
            .Where(value => !string.IsNullOrWhiteSpace(value) && value.Length <= 80)
            .Select(value => value!)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
            .Take(64)
            .ToArray();
    }
}

public sealed record ScmBootstrapFleet(
    long Id,
    string Sid,
    string Name,
    string? LogoUrl,
    bool Primary,
    string? RankName,
    int? RankValue,
    string[] Capabilities);

public sealed record ScmBootstrapSnapshot(
    ScmBootstrapProfile Profile,
    ScmBootstrapIdentityLink IdentityLink,
    ScmBootstrapFleet[] Fleets,
    ScmBootstrapFleet? PrimaryFleet,
    long UnreadNotifications,
    long BlacklistVersion,
    Dictionary<string, long> ResourceVersions,
    DateTimeOffset ServerTime,
    string[] Capabilities,
    ScmOverlayEntitlementSnapshot? OverlayEntitlements = null);

public sealed record ScmBootstrapResult(
    ScmBootstrapSnapshot Snapshot,
    ScmOAuthSession ActiveSession);

public sealed record ScmProfileResult(
    ScmSelfProfileContract Profile,
    ScmOAuthSession ActiveSession);

public sealed record ScmPersonalProfileResult(
    PersonalProfileDocumentContract Profile,
    ScmOAuthSession ActiveSession)
{
    /// <summary>Set (with a null Profile) when a visitor read returned only the public header.</summary>
    internal StarBridge.HostRuntime.Account.PersonalProfilePublicHeader? Restricted { get; init; }
}

public sealed record ScmTimeZoneDirectoryEntry(
    long Id,
    string Value,
    string Label,
    string Offset,
    int OffsetMinutes);

public sealed record ScmWebSocketTicket(string Ticket, DateTimeOffset ExpiresAt);

public sealed record ScmWebSocketTicketResult(
    ScmWebSocketTicket Ticket,
    ScmOAuthSession ActiveSession);

public sealed record ScmPresenceStatus(int SignInStatus, long Timestamp, bool Anonymous);

public sealed record ScmPresenceStatusResult(
    ScmPresenceStatus Status,
    ScmOAuthSession ActiveSession);

public sealed record ScmDesktopDeviceStatus(bool Trusted);

public interface IIdentityLinkAuthorizationClient
{
    Task<ScmOAuthSession> AuthorizeIdentityLinkAsync(
        ScmOAuthSession currentSession,
        CancellationToken cancellationToken,
        Action<string>? reportProgress = null);
}

public interface IProfileWriteAuthorizationClient
{
    Task<ScmOAuthSession> AuthorizeProfileWriteAsync(
        ScmOAuthSession currentSession,
        CancellationToken cancellationToken,
        Action<string>? reportProgress = null);
}

public sealed partial class OAuthPkceClient(
    ScmHttpClient scmHttpClient,
    ITokenVault tokenVault,
    ScmOAuthOptions options,
    Func<string>? deviceIdProvider = null,
    Action<Uri>? authorizationBrowser = null) : IIdentityLinkAuthorizationClient, IProfileWriteAuthorizationClient
{
    private const string IdentityLinkScope = "openid profile.read identity.link";
    // Resource requests include Java introspection plus an upstream SCM
    // operation. Leave room for both bounded 20-second integration hops.
    private static readonly TimeSpan ResourceRequestTimeout = TimeSpan.FromSeconds(45);
    private static readonly TimeSpan TokenRequestTimeout = TimeSpan.FromSeconds(30);
    private readonly SemaphoreSlim _refreshGate = new(1, 1);
    private ScmOAuthSession? _currentSession;
    internal ScmRouteState? RouteState { get; init; }

    private void OpenAuthorizationBrowser(Uri uri)
    {
        if (authorizationBrowser is not null) authorizationBrowser(uri);
        else Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
    }

    internal bool OpenGameIdentityProfile()
    {
        try { OpenAuthorizationBrowser(new Uri("https://robertsspaceindustries.com/account/profile")); return true; }
        catch { return false; }
    }

    public event Action<OAuthPkceClient, ScmOAuthSession>? SessionInvalidated;

    public ScmSessionRestoreOutcome LastSessionRestoreOutcome { get; private set; }

    public async Task<ScmOAuthSession> SignInAsync(
        CancellationToken cancellationToken,
        Action<string>? reportProgress = null)
        => await SignInCoreAsync(cancellationToken, reportProgress).ConfigureAwait(false);

    // Normal sign-in retires the original previous account at commit. Only a Native
    // retained-session owner supplies the narrower same-owner commit callbacks.
    private async Task<ScmOAuthSession> SignInCoreAsync(CancellationToken cancellationToken,
        Action<string>? reportProgress, Func<ScmOAuthSession, bool>? acceptable = null,
        Func<ScmOAuthSession, string, bool>? commit = null, Func<bool>? active = null)
    {
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var signInStopwatch = ScmAuthDiagnostics.Start(
            correlationId,
            "sign-in",
            $"authorize={ScmAuthDiagnostics.Endpoint(options.AuthorizeEndpoint)} " +
            $"token={ScmAuthDiagnostics.Endpoint(options.TokenEndpoint)} " +
            $"me={ScmAuthDiagnostics.Endpoint(options.MeEndpoint)} clientId={options.ClientId}");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromMinutes(3));
        try
        {
            var previousCredential = commit is null ? CaptureSignInPreviousVersion() : null;
            var pkce = OAuthPkceParameters.Create();
            await using var callback = LoopbackCallbackListener.Start(options.CallbackPath);
            ScmAuthDiagnostics.Write(
                correlationId,
                "callback-listener",
                "ready",
                $"redirect={ScmAuthDiagnostics.Endpoint(callback.RedirectUri)} pkceMethod=S256");
            var authorizeUri = BuildAuthorizeUri(callback.RedirectUri, pkce, options.Scope);

            timeout.Token.ThrowIfCancellationRequested();
            if (active is not null && !active())
                throw new ScmApiAuthenticationException("Original authorization owner changed.");
            OpenAuthorizationBrowser(authorizeUri);
            ScmAuthDiagnostics.Write(correlationId, "authorize-browser", "opened");
            var callbackStopwatch = ScmAuthDiagnostics.Start(correlationId, "callback-wait");
            var authorization = await callback.WaitForCallbackAsync(pkce.State, timeout.Token);
            ScmAuthDiagnostics.Completed(correlationId, "callback-wait", callbackStopwatch, "codePresent=true stateValidated=true");
            reportProgress?.Invoke("已收到 SCM 授权，正在交换安全令牌...");
            var tokenResponse = await ExchangeCodeAsync(
                correlationId,
                authorization.Code,
                callback.RedirectUri,
                pkce.CodeVerifier,
                timeout.Token);
            var tokenReceivedAt = SessionNow;
            timeout.Token.ThrowIfCancellationRequested();
            if (commit is not null && tokenResponse.ExpiresIn <= 0)
                throw new ScmApiAuthenticationException("Authorization lifetime cannot be verified.");
            reportProgress?.Invoke("令牌交换完成，正在验证账号身份...");
            var identity = await LoadIdentityAsync(correlationId, tokenResponse.AccessToken, timeout.Token);
            if (string.IsNullOrWhiteSpace(identity.Subject))
            {
                ScmAuthDiagnostics.Write(correlationId, "identity-validation", "failed", "subjectPresent=false");
                throw new InvalidOperationException("SCM 返回的账号主体无效。");
            }

            var session = CreateSession(identity, tokenResponse, correlationId,
                commit is null ? null : tokenReceivedAt.AddSeconds(tokenResponse.ExpiresIn));
            timeout.Token.ThrowIfCancellationRequested();
            if (acceptable is not null && !acceptable(session))
                throw new ScmApiAuthenticationException("Original authorization owner cannot be verified.");
            if (deviceIdProvider is not null)
            {
                reportProgress?.Invoke("账号身份验证完成，正在登记可信设备...");
                var deviceStatus = await RegisterDesktopDeviceAsync(
                    session,
                    deviceIdProvider(),
                    timeout.Token);
                if (!deviceStatus.Trusted)
                {
                    throw new ScmApiProtocolException("SCM 未确认当前 Desktop 可信设备。");
                }
            }

            await _refreshGate.WaitAsync(timeout.Token);
            try
            {
                timeout.Token.ThrowIfCancellationRequested();
                var accountKey = AccountKey(identity.Subject);
                var vaultStopwatch = ScmAuthDiagnostics.Start(correlationId, "refresh-token-vault-save");
                if (commit is null)
                {
                    SaveSignInCredential(accountKey, tokenResponse.RefreshToken, previousCredential);
                }
                else if (!commit(session, tokenResponse.RefreshToken))
                    throw new ScmApiAuthenticationException("Original authorization version changed.");
                ScmAuthDiagnostics.Completed(correlationId, "refresh-token-vault-save", vaultStopwatch);
                _retainedRefresh = null;
                _rejectedSession = null;
                _notifiedCredentialVersion = null;
                _currentSession = session;
                RouteState?.LoginSucceeded();
                _sessionWasInstalled = true;
                ClearSessionExpired();
                ScmAuthDiagnostics.Completed(
                    correlationId,
                    "sign-in",
                    signInStopwatch,
                    $"capabilityCount={_currentSession.Capabilities.Length}");
                return _currentSession;
            }
            finally
            {
                _refreshGate.Release();
            }
        }
        catch (Exception exception)
        {
            ScmAuthDiagnostics.Failed(correlationId, "sign-in", signInStopwatch, exception);
            throw;
        }
    }

    public async Task<ScmOAuthSession> AuthorizeIdentityLinkAsync(
        ScmOAuthSession currentSession,
        CancellationToken cancellationToken,
        Action<string>? reportProgress = null)
    {
        ArgumentNullException.ThrowIfNull(currentSession);
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var authorizeStopwatch = ScmAuthDiagnostics.Start(
            correlationId,
            "identity-link-authorize",
            $"authorize={ScmAuthDiagnostics.Endpoint(options.AuthorizeEndpoint)} clientId={options.ClientId}");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromMinutes(3));
        try
        {
            var pkce = OAuthPkceParameters.Create();
            await using var callback = LoopbackCallbackListener.Start(options.CallbackPath);
            var authorizeUri = BuildAuthorizeUri(callback.RedirectUri, pkce, IdentityLinkScope);
            OpenAuthorizationBrowser(authorizeUri);
            var authorization = await callback.WaitForCallbackAsync(pkce.State, timeout.Token);
            reportProgress?.Invoke("已收到 SCM 关联授权，正在验证账号...");
            var tokenResponse = await ExchangeCodeAsync(
                correlationId,
                authorization.Code,
                callback.RedirectUri,
                pkce.CodeVerifier,
                timeout.Token,
                requireRefreshToken: false);
            if (!ContainsScope(tokenResponse.Scope, "identity.link"))
            {
                throw new ScmApiForbiddenException("SCM 未授予旧账号关联权限。");
            }

            var identity = await LoadIdentityAsync(correlationId, tokenResponse.AccessToken, timeout.Token);
            if (!string.Equals(identity.Subject, currentSession.Subject, StringComparison.Ordinal))
            {
                throw new InvalidOperationException("关联授权账号与当前 SCM 登录账号不一致。");
            }

            var linkSession = CreateSession(identity, tokenResponse, correlationId) with
            {
                Capabilities = ["identity.link"]
            };
            ScmAuthDiagnostics.Completed(
                correlationId,
                "identity-link-authorize",
                authorizeStopwatch,
                "subjectMatched=true scopeGranted=true persisted=false");
            return linkSession;
        }
        catch (Exception exception)
        {
            ScmAuthDiagnostics.Failed(correlationId, "identity-link-authorize", authorizeStopwatch, exception);
            throw;
        }
    }

    public async Task<ScmOAuthSession> AuthorizeProfileWriteAsync(
        ScmOAuthSession currentSession,
        CancellationToken cancellationToken,
        Action<string>? reportProgress = null)
    {
        ArgumentNullException.ThrowIfNull(currentSession);
        cancellationToken.ThrowIfCancellationRequested();
        if (!currentSession.Capabilities.Contains("profile.write", StringComparer.Ordinal))
            throw new ScmApiAuthenticationException("account.reauthorization_required");
        // Writes use the ordinary refreshable login, never a temporary browser grant.
        if (_currentSession is { } owner && !SameOwner(owner, currentSession))
            throw new ScmApiAuthenticationException("Original profile write owner changed.");
        var active = await EnsureActiveSessionAsync(currentSession, cancellationToken);
        cancellationToken.ThrowIfCancellationRequested();
        if (!string.Equals(active.AuthorityId, currentSession.AuthorityId, StringComparison.Ordinal) ||
            !string.Equals(active.Subject, currentSession.Subject, StringComparison.Ordinal))
            throw new ScmApiAuthenticationException("资料保存账号与当前 SCM 登录账号不一致。");
        if (!active.Capabilities.Contains("profile.write", StringComparer.Ordinal))
            throw new ScmApiAuthenticationException("当前登录未获资料修改权限，请重新登录 SCM 并授权。");
        return active;
    }

    public Task<ScmOAuthSession?> TryRestoreSessionAsync(CancellationToken cancellationToken) =>
        RestoreSessionAsync(cancellationToken, null);

    private async Task<ScmOAuthSession?> RestoreSessionCoreAsync(
        CancellationToken cancellationToken, ScmOAuthSession? rejectedSession, Task drained, CancellationToken displayOwnerCancellation)
    {
        LastSessionRestoreOutcome = ScmSessionRestoreOutcome.NotAttempted;
        _offlineDisplayReady = false;
        Volatile.Write(ref _offlineDisplayOwner, null);
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var restoreStopwatch = ScmAuthDiagnostics.Start(correlationId, "session-restore");
        await _refreshGate.WaitAsync(cancellationToken);
        try
        {
            CleanupStartupCredentials();
            // Invalidate only the rejected access token while holding the same
            // gate as refresh. A late 401 must not invalidate a newer session.
            if (rejectedSession is not null)
            {
                var current = _currentSession;
                if (current is not null &&
                    (!string.Equals(current.AuthorityId, rejectedSession.AuthorityId, StringComparison.Ordinal) ||
                     !string.Equals(current.Subject, rejectedSession.Subject, StringComparison.Ordinal)))
                    throw new ScmRefreshTemporarilyUnavailableException("SCM account changed during recovery.");
                if (current is null && tokenVault.LoadActiveAccountKey() !=
                    $"{rejectedSession.AuthorityId}:{rejectedSession.Subject}")
                    throw new ScmRefreshTemporarilyUnavailableException("Credential selection changed during request.");
                if (current is null || SameCredential(current, rejectedSession))
                    _currentSession = rejectedSession with { ExpiresAt = DateTimeOffset.MinValue };
            }
            // The refresh owner carries the installed session's verified stamp,
            // before any expiry check or selection of a resume credential.
            var previousSession = _currentSession;
            var originalVersion = previousSession is not null && tokenVault is WindowsTokenVault
                ? CurrentCredentialRetirement(previousSession) : _credentialRetirement;
            if (_currentSession is not null && _currentSession.ExpiresAt > SessionNow.AddMinutes(1))
            {
                LastSessionRestoreOutcome = ScmSessionRestoreOutcome.Restored;
                ScmAuthDiagnostics.Completed(correlationId, "session-restore", restoreStopwatch, "source=memory");
                return _currentSession;
            }

            var vaultLoadStopwatch = ScmAuthDiagnostics.Start(correlationId, "refresh-token-vault-load");
            // Carry the installed owner's own stamp into capture. Reading the
            // selected same-account credential cannot create refresh ancestry.
            var restoreCredential = tokenVault is WindowsTokenVault selectedVault
                ? selectedVault.CaptureResumeCredential(options.AuthorityId) : null;
            if (tokenVault is WindowsTokenVault && previousSession is not null &&
                (originalVersion is null || restoreCredential?.Version != originalVersion))
                throw new ScmRefreshTemporarilyUnavailableException("Original credential changed before refresh capture.");
            var accountKey = tokenVault is WindowsTokenVault
                ? restoreCredential?.AccountKey : tokenVault.LoadActiveAccountKey();
            if (string.IsNullOrWhiteSpace(accountKey) || !accountKey.StartsWith(options.AuthorityId + ":", StringComparison.Ordinal))
            {
                // A retired sign-in asks to sign in again rather than looking like
                // a user who never signed in (2026-10-21).
                var expired = SessionExpired();
                LastSessionRestoreOutcome = expired
                    ? ScmSessionRestoreOutcome.ReauthorizationRequired
                    : ScmSessionRestoreOutcome.NoStoredCredential;
                ScmAuthDiagnostics.Completed(
                    correlationId,
                    "refresh-token-vault-load",
                    vaultLoadStopwatch,
                    "activeAccountPresent=false");
                ScmAuthDiagnostics.Completed(correlationId, "session-restore", restoreStopwatch,
                    expired ? "outcome=session-expired" : "outcome=no-credential");
                return null;
            }

            var refreshToken = tokenVault is WindowsTokenVault
                ? restoreCredential?.RefreshToken : tokenVault.LoadRefreshToken(accountKey);
            if (string.IsNullOrWhiteSpace(refreshToken))
            {
                LastSessionRestoreOutcome = ScmSessionRestoreOutcome.NoStoredCredential;
                ScmAuthDiagnostics.Completed(
                    correlationId,
                    "refresh-token-vault-load",
                    vaultLoadStopwatch,
                    "activeAccountPresent=true refreshTokenPresent=false");
                ScmAuthDiagnostics.Completed(correlationId, "session-restore", restoreStopwatch, "outcome=no-refresh-token");
                return null;
            }
            ScmAuthDiagnostics.Completed(
                correlationId,
                "refresh-token-vault-load",
                vaultLoadStopwatch,
                "activeAccountPresent=true refreshTokenPresent=true");

            LastSessionRestoreOutcome = ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable;
            CaptureOfflineDisplayOwner(restoreCredential, cancellationToken, drained, displayOwnerCancellation);
            try
            {
                // Expiry can discard a retained access response, but cannot
                // discard the proof of the input rotation it already committed.
                var inputLineage = _retainedRefresh?.Lineage;
                var retained = ReusableRefresh(accountKey, refreshToken);
                var lineage = retained?.Lineage;
                ScmTokenResponse tokenResponse;
                if (retained is not null)
                {
                    // Already rotated and committed; retry only the identity read.
                    tokenResponse = retained.Response;
                    ScmAuthDiagnostics.Write(correlationId, "refresh-token", "reused", "source=committed-unconfirmed");
                }
                else
                {
                    tokenResponse = await RefreshTokenAsync(correlationId, refreshToken, cancellationToken);
                    var receivedAt = SessionNow;
                    cancellationToken.ThrowIfCancellationRequested();
                    var vaultSaveStopwatch = ScmAuthDiagnostics.Start(correlationId, "refresh-token-vault-rotate");
                    if (tokenVault is WindowsTokenVault rotatingVault)
                    {
                        lock (_installedLineageGate)
                        {
                            bool OwnsRefreshInput() => !cancellationToken.IsCancellationRequested &&
                                _credentialRetirement == originalVersion &&
                                (previousSession is null ? _currentSession is null : _currentSession is { } actual &&
                                    SameCredential(actual, previousSession) && actual.AccessToken == previousSession.AccessToken) &&
                                (previousSession is null || restoreCredential?.Version == originalVersion);
                            var version = restoreCredential is null ? null : rotatingVault.RotateResumeCredential(
                                restoreCredential, tokenResponse.RefreshToken, OwnsRefreshInput);
                            if (version is null) throw new HttpRequestException("Stored session changed during restoration.");
                            // RotateResumeCredential compared this exact input under
                            // its storage writer fence before producing the output.
                            if (previousSession is not null && originalVersion is not null)
                            {
                                var earlier = inputLineage;
                                lineage = earlier is not null && earlier.Output == originalVersion &&
                                    SameCredential(earlier.Original, previousSession)
                                    ? earlier with { Output = version } : new(previousSession, originalVersion, version);
                            }
                            _credentialRetirement = version;
                            _locallyRevokedSession = null;
                            restoreCredential = restoreCredential! with { RefreshToken = tokenResponse.RefreshToken, Version = version };
                        }
                    }
                    else SaveSessionRefreshToken(accountKey, tokenResponse.RefreshToken);
                    RotateOfflineDisplayOwner(accountKey);
                    ScmAuthDiagnostics.Completed(correlationId, "refresh-token-vault-rotate", vaultSaveStopwatch);
                    RetainRefresh(accountKey, tokenResponse, receivedAt, restoreCredential?.Version, lineage);
                }
                var identity = await LoadIdentityAsync(correlationId, tokenResponse.AccessToken, cancellationToken);
                if (string.IsNullOrWhiteSpace(identity.Subject) || !AccountKey(identity.Subject).Equals(accountKey, StringComparison.Ordinal))
                {
                    _retainedRefresh = null;
                    ClearRestoreCredential(accountKey, restoreCredential, cancellationToken);
                    _sessionWasInstalled = true;
                    _rejectedSession = _currentSession;
                    _currentSession = null;
                    MarkSessionExpired();
                    LastSessionRestoreOutcome = ScmSessionRestoreOutcome.ReauthorizationRequired;
                    ScmAuthDiagnostics.Write(
                        correlationId,
                        "session-restore",
                        "identity-mismatch",
                        $"subjectPresent={!string.IsNullOrWhiteSpace(identity.Subject)}");
                    throw new InvalidOperationException("SCM 刷新后的账号身份与本地凭据不匹配。");
                }

                // A reused refresh keeps its original expiry, not one restarted now.
                var restoredSession = CreateSession(identity, tokenResponse, correlationId, retained?.ExpiresAt) with
                { CredentialVersion = _retainedRefresh!.CredentialVersion };
                if (deviceIdProvider is not null)
                {
                    var deviceStatus = await GetDesktopDeviceStatusAsync(
                        restoredSession, deviceIdProvider(), cancellationToken);
                    if (!deviceStatus.Trusted)
                    {
                        _retainedRefresh = null;
                        ClearRestoreCredential(accountKey, restoreCredential, cancellationToken);
                        MarkSessionExpired();
                        LastSessionRestoreOutcome = ScmSessionRestoreOutcome.ReauthorizationRequired;
                        _sessionWasInstalled = true;
                        _rejectedSession = _currentSession;
                        _currentSession = null;
                        ScmAuthDiagnostics.Completed(
                            correlationId,
                            "session-restore",
                            restoreStopwatch,
                            "outcome=device-untrusted credentialDeleted=true");
                        return null;
                    }
                }

                restoredSession = await RefreshOverlayQualificationAsync(
                    restoredSession, previousSession, cancellationToken);
                if (tokenVault is WindowsTokenVault currentVault &&
                    (restoreCredential is null || !currentVault.IsRetirementCurrent(restoreCredential.Version)))
                    throw new HttpRequestException("Stored session changed during restoration.");
                cancellationToken.ThrowIfCancellationRequested();
                lock (_installedLineageGate)
                {
                    void Commit()
                    {
                        RecordCommittedRefresh(lineage, restoreCredential?.Version, restoredSession);
                        _currentSession = restoredSession;
                    }
                    if (tokenVault is WindowsTokenVault publishingVault)
                    {
                        if (restoreCredential is null || !publishingVault.ObserveCurrentRetirement(restoreCredential.Version,
                            () => !cancellationToken.IsCancellationRequested && _credentialRetirement == restoreCredential.Version, Commit))
                            throw new ScmRefreshTemporarilyUnavailableException("Stored session changed before refresh publication.");
                    }
                    else Commit();
                }
                RouteState?.LoginSucceeded();
                _sessionWasInstalled = true;
                _rejectedSession = null;
                _retainedRefresh = null;
                ClearSessionExpired();
                LastSessionRestoreOutcome = ScmSessionRestoreOutcome.Restored;
                ScmAuthDiagnostics.Completed(
                    correlationId,
                    "session-restore",
                    restoreStopwatch,
                    $"outcome=success capabilityCount={restoredSession.Capabilities.Length}");
                return restoredSession;
            }
            catch (ScmApiAuthenticationException)
            {
                // /me, bootstrap and device-status are resources too. Their 401
                // cannot reject the newly committed refresh credential.
                if (_currentSession is { } current)
                    _currentSession = current with { ExpiresAt = DateTimeOffset.MinValue };
                throw new ScmRefreshTemporarilyUnavailableException("Refreshed access token is temporarily unavailable.");
            }
            catch (ScmRefreshTokenRejectedException)
            {
                _sessionWasInstalled = true;
                _rejectedSession = _currentSession;
                _retainedRefresh = null;
                ClearRestoreCredential(accountKey, restoreCredential, cancellationToken);
                MarkSessionExpired();
                LastSessionRestoreOutcome = ScmSessionRestoreOutcome.ReauthorizationRequired;
                _currentSession = null;
                ScmAuthDiagnostics.Completed(
                    correlationId,
                    "session-restore",
                    restoreStopwatch,
                    "outcome=authentication-rejected credentialDeleted=true");
                return null;
            }
        }
        catch (Exception exception)
        {
            ScmAuthDiagnostics.Failed(correlationId, "session-restore", restoreStopwatch, exception);
            _offlineDisplayReady = !cancellationToken.IsCancellationRequested && !displayOwnerCancellation.IsCancellationRequested &&
                LastSessionRestoreOutcome == ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable &&
                exception is HttpRequestException or OperationCanceledException;
            throw;
        }
        finally
        {
            // The original root transaction owns any display read until its
            // response. Stop renewal here; do not retire another root's receipt.
            Volatile.Write(ref _restoreDisplayRead, null);
            _refreshGate.Release();
        }
    }

    public async Task RevokeAsync(ScmOAuthSession session, CancellationToken cancellationToken)
    {
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var revokeStopwatch = ScmAuthDiagnostics.Start(
            correlationId,
            "session-revoke",
            $"endpoint={ScmAuthDiagnostics.Endpoint(options.RevokeEndpoint)}");
        var accountKey = $"{session.AuthorityId}:{session.Subject}";
        await _refreshGate.WaitAsync(cancellationToken);
        try
        {
            _sessionWasInstalled = true;
            string? refreshToken;
            try
            {
                var retirement = CurrentCredentialRetirement(session);
                refreshToken = tokenVault.LoadRefreshToken(accountKey);
                DeleteSessionRefreshToken(session, accountKey, retirement, cancellationToken);
            }
            catch (Exception error) when (error is ScmRefreshTemporarilyUnavailableException || CredentialStorageFailure(error))
            { throw new ScmLocalCredentialRetirementException(error); }
            if (ReferenceEquals(_currentSession, session))
            {
                _currentSession = null;
            }
            // An explicit sign-out is not an expired sign-in.
            _retainedRefresh = null;
            ClearSessionExpired();

            ScmAuthDiagnostics.Write(
                correlationId,
                "session-revoke-local",
                "completed",
                "credentialDeleted=true memorySessionCleared=true");
            if (!string.IsNullOrWhiteSpace(refreshToken))
            {
                try
                {
                using var request = new HttpRequestMessage(HttpMethod.Post, options.RevokeEndpoint)
                {
                    Content = new FormUrlEncodedContent(new Dictionary<string, string>
                    {
                        ["token"] = refreshToken,
                        ["token_type_hint"] = "refresh_token",
                        ["client_id"] = options.ClientId
                    })
                };
                request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, correlationId);
                using var response = await scmHttpClient.SendAsync(request, cancellationToken: cancellationToken);
                ScmAuthDiagnostics.Write(
                    correlationId,
                    "revoke-request",
                    response.IsSuccessStatusCode ? "completed" : "http-error",
                    $"status={(int)response.StatusCode}");
                response.EnsureSuccessStatusCode();
                // RFC-style empty revoke responses remain valid; reject an optional SCM error object.
                var body = await response.Content.ReadAsStringAsync(cancellationToken);
                if (!string.IsNullOrWhiteSpace(body))
                {
                    try
                    {
                        using var document = JsonDocument.Parse(body);
                        ScmHttpClient.EnsureBusinessSuccess(document.RootElement);
                    }
                    catch (JsonException) { /* Preserve the existing non-JSON revoke contract. */ }
                }
                }
                catch (HttpRequestException error) { throw new ScmRemoteRevocationException(error); }
            }
            else
            {
                ScmAuthDiagnostics.Write(correlationId, "revoke-request", "skipped", "refreshTokenPresent=false");
            }

            ScmAuthDiagnostics.Completed(
                correlationId,
                "session-revoke",
                revokeStopwatch,
                "credentialDeleted=true memorySessionCleared=true");
        }
        finally
        {
            _refreshGate.Release();
        }
    }

    public async Task ClearLocalCredentialAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(session);
        await _refreshGate.WaitAsync(cancellationToken);
        try
        {
            // This only ends an inferred rejected in-memory lifecycle. Explicit
            // server force-logout uses DeleteCredentialForRemoteLogoutAsync.
            _sessionWasInstalled = true;
            var current = _currentSession;
            if (current is null || !SameCredential(current, session) || _retainedRefresh is not null ||
                tokenVault.LoadActiveAccountKey() != AccountKey(session.Subject)) return;
            // End this in-memory lifecycle. A socket/resource rejection cannot
            // establish invalid_grant and must never delete a refresh credential.
            _currentSession = null;
        }
        finally
        {
            _refreshGate.Release();
        }
    }

    public async Task<ScmOAuthSession> RefreshIdentityAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken, Action<ScmOAuthSession>? sessionReady = null)
    {
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var (identity, activeSession) = await SendResourceRequestWithRefreshAndSessionAsync(
            session,
            (activeSession, token) => LoadIdentityAsync(correlationId, activeSession.AccessToken, token),
            cancellationToken, sessionReady);
        if (!string.Equals(identity.Subject, activeSession.Subject, StringComparison.Ordinal))
        {
            throw new InvalidOperationException("SCM 返回的账号身份与当前会话不匹配。");
        }

        var refreshed = PublishResourceSession(RefreshedIdentity(activeSession, identity, correlationId));
        sessionReady?.Invoke(refreshed);
        return refreshed;
    }

    internal async Task<ScmOAuthSession> RefreshFirstUseIdentityAsync(ScmOAuthSession session, CancellationToken token)
    {
        await _refreshGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            if (!IsFreshFirstUseSessionCurrent(session)) throw new ScmApiAuthenticationException("SCM authorization changed.");
            var correlationId = ScmAuthDiagnostics.NewCorrelationId();
            // Deliberately no EnsureActiveSession / selected-vault restore / 401
            // replay: this read belongs only to the explicit fresh OAuth commit.
            var identity = await LoadIdentityAsync(correlationId, session.AccessToken, token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            if (!IsFreshFirstUseSessionCurrent(session) || identity.Subject != session.Subject)
                throw new ScmApiAuthenticationException("SCM authorization changed.");
            ValidateFirstUseIdentity(identity.GameIdentity);
            return _currentSession = RefreshedIdentity(session, identity, correlationId);
        }
        finally { _refreshGate.Release(); }
    }

    private static ScmOAuthSession RefreshedIdentity(ScmOAuthSession activeSession, ScmIdentityResponse identity, string correlationId) =>
        activeSession with
        {
            DisplayName = string.IsNullOrWhiteSpace(identity.DisplayName) ? activeSession.DisplayName : identity.DisplayName,
            Capabilities = identity.Capabilities ?? [],
            GameIdentityVerified = identity.GameIdentitySnapshot.Status == ScmGameIdentityStatus.Verified,
            CorrelationId = correlationId,
            GameIdentityHandle = identity.GameIdentitySnapshot.Status == ScmGameIdentityStatus.Verified
                ? identity.GameIdentitySnapshot.Handle
                : null,
            GameIdentityStatus = identity.GameIdentitySnapshot.Status,
            GameIdentityNormalizedHandle = identity.GameIdentitySnapshot.Status == ScmGameIdentityStatus.Verified
                ? identity.GameIdentitySnapshot.CanonicalHandle
                : null,
            GameIdentityVerificationMethod = identity.GameIdentity?.VerificationMethod,
            GameIdentityVerifiedAt = identity.GameIdentity?.VerifiedAt
        };

    // Preserve the ordinary compatibility policy. A first-use handoff needs an
    // explicit authoritative state, not the old boolean fallback for an unknown
    // status or two contradictory Handle representations.
    private static void ValidateFirstUseIdentity(ScmGameIdentityContract? identity)
    {
        var status = identity?.Status?.Trim().ToUpperInvariant();
        if (status is not ("UNVERIFIED" or "PENDING" or "VERIFIED" or "REVERIFY_REQUIRED" or "REVOKED" or "UNKNOWN"))
            throw new ScmApiProtocolException("SCM identity state is unavailable.");
        if (status != "VERIFIED")
        {
            if (identity!.Verified) throw new ScmApiProtocolException("SCM identity state is contradictory.");
            return;
        }
        if (!identity!.Verified || identity.Handle is null && identity.NormalizedHandle is null ||
            identity.Handle is not null && !IdentityBindingPolicy.IsValidGameName(identity.Handle) ||
            identity.NormalizedHandle is not null && !IdentityBindingPolicy.IsValidGameName(identity.NormalizedHandle) ||
            identity.Handle is not null && identity.NormalizedHandle is not null &&
                !string.Equals(identity.Handle.Trim(), identity.NormalizedHandle.Trim(), StringComparison.OrdinalIgnoreCase))
            throw new ScmApiProtocolException("SCM identity Handle is unavailable.");
    }

    public Task<ScmGameIdentityVerificationCode> GetGameIdentityVerificationCodeAsync(
        ScmOAuthSession session,
        string gameName,
        CancellationToken cancellationToken, Action<ScmOAuthSession>? sessionReady = null) => SendResourceRequestWithRefreshAsync(
            session,
            (activeSession, token) => SendGameIdentityRequestAsync<ScmGameIdentityVerificationCode>(
                new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/game-identity/verification-code"),
                activeSession,
                new { gameName },
                token),
            cancellationToken, sessionReady);

    public Task<ScmGameIdentityVerificationResult> VerifyGameIdentityAsync(
        ScmOAuthSession session,
        string gameName,
        string userMobile,
        CancellationToken cancellationToken, Action<ScmOAuthSession>? sessionReady = null) => SendResourceRequestWithRefreshAsync(
            session,
            (activeSession, token) => SendGameIdentityRequestAsync<ScmGameIdentityVerificationResult>(
                new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/game-identity/verify"),
                activeSession,
                new { gameName, userMobile },
                token),
            cancellationToken, sessionReady);

    public Task<ScmDesktopDeviceStatus> RegisterDesktopDeviceAsync(
        ScmOAuthSession session,
        string deviceId,
        CancellationToken cancellationToken) => SendDesktopDeviceRequestAsync(
            options.DeviceRegisterEndpoint,
            session,
            new { deviceId },
            cancellationToken);

    public Task<ScmDesktopDeviceStatus> GetDesktopDeviceStatusAsync(
        ScmOAuthSession session,
        string deviceId,
        CancellationToken cancellationToken) => SendDesktopDeviceRequestAsync(
            options.DeviceStatusEndpoint,
            session,
            new { deviceId },
            cancellationToken);

    public async Task<ScmBootstrapResult> LoadBootstrapAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken)
    {
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var (snapshot, activeSession) = await ReadAccountResourceAsync<ScmBootstrapSnapshot>(
            session, options.BootstrapEndpoint, correlationId, "bootstrap-read", cancellationToken);
        if (!string.Equals(snapshot.Profile.Subject, activeSession.Subject, StringComparison.Ordinal))
        {
            throw new InvalidOperationException("SCM Bootstrap 返回了其他账号的数据。");
        }

        var bootstrapIdentity = ResolveBootstrapGameIdentity(snapshot.Profile, activeSession);
        var overlayEntitlements = ValidateOverlayEntitlements(snapshot);
        var projectedSession = PublishResourceSession(activeSession with
        {
            DisplayName = string.IsNullOrWhiteSpace(snapshot.Profile.DisplayName)
                ? activeSession.DisplayName
                : snapshot.Profile.DisplayName,
            Capabilities = snapshot.Capabilities ?? [],
            GameIdentityVerified = bootstrapIdentity.Status == ScmGameIdentityStatus.Verified,
            CorrelationId = correlationId,
            GameIdentityHandle = bootstrapIdentity.Status == ScmGameIdentityStatus.Verified
                ? bootstrapIdentity.Handle
                : null,
            GameIdentityStatus = bootstrapIdentity.Status,
            GameIdentityNormalizedHandle = bootstrapIdentity.Status == ScmGameIdentityStatus.Verified
                ? bootstrapIdentity.CanonicalHandle
                : null,
            GameIdentityVerificationMethod = snapshot.Profile.GameIdentity?.VerificationMethod ??
                                             activeSession.GameIdentityVerificationMethod,
            GameIdentityVerifiedAt = snapshot.Profile.GameIdentity?.VerifiedAt ??
                                     activeSession.GameIdentityVerifiedAt,
            OverlayEntitlements = overlayEntitlements
        });
        return new ScmBootstrapResult(snapshot, projectedSession);
    }

    private static ScmOverlayEntitlementSnapshot? ValidateOverlayEntitlements(
        ScmBootstrapSnapshot snapshot)
    {
        var projection = snapshot.OverlayEntitlements;
        if (projection is null ||
            !string.Equals(projection.Status?.Trim(), "ready", StringComparison.OrdinalIgnoreCase))
        {
            return projection;
        }

        var expectedAccountId = snapshot.IdentityLink.LegacyAccountId?.Trim();
        if (!snapshot.IdentityLink.Linked ||
            string.IsNullOrWhiteSpace(expectedAccountId) ||
            string.IsNullOrWhiteSpace(projection.AccountId) ||
            !projection.AccountId.Trim().Equals(expectedAccountId, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("SCM Bootstrap 返回了其他账号的外观资格。");
        }

        return projection;
    }

    internal sealed record BusinessIdentityProjection(int SchemaVersion, string Issuer, string Subject,
        string BusinessSubjectId, string[] Scopes);

    internal async Task<(string BusinessSubjectId, ScmOAuthSession ActiveSession)> LoadBusinessIdentityAsync(
        ScmOAuthSession session, CancellationToken cancellationToken)
    {
        var (identity, active) = await ReadAccountResourceAsync<BusinessIdentityProjection>(session,
            new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/business-identity"),
            ScmAuthDiagnostics.NewCorrelationId(), "business-identity-read", cancellationToken);
        ValidateBusinessIdentity(identity, active.Subject);
        return (identity.BusinessSubjectId, active);
    }

    // The configured Java resource server is the identity authority. Do not
    // derive its opaque storage key from a display name or a legacy account.
    internal static void ValidateBusinessIdentity(BusinessIdentityProjection? identity, string subject)
    {
        if (identity is null || identity.SchemaVersion != 1 || identity.Subject != subject ||
            // Java's configured issuer is an opaque identity key, not an
            // endpoint. Preserve its exact case/value; transport trust is
            // already enforced by the configured authenticated resource read.
            string.IsNullOrWhiteSpace(subject) || identity.Issuer is not { Length: > 0 and <= 160 } ||
            identity.Issuer != identity.Issuer.Trim() || identity.Issuer.Any(char.IsControl) ||
            identity.BusinessSubjectId is not { Length: 71 } key || !key.StartsWith("scm-v1:", StringComparison.Ordinal) ||
            key[7..].Any(c => c is not (>= '0' and <= '9' or >= 'a' and <= 'f')) ||
            identity.Scopes is null || !identity.Scopes.Contains("profile.read", StringComparer.Ordinal))
            throw new ScmApiProtocolException("SCM business identity does not match the active account.");
    }

    public async Task<ScmProfileResult> LoadProfileAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken)
    {
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var endpoint = new UriBuilder(options.ProfileEndpoint) { Query = "view=self" }.Uri;
        var (profile, activeSession) = await ReadAccountResourceAsync<ScmSelfProfileContract>(
            session, endpoint, correlationId, "account-profile-read", cancellationToken);
        ScmSelfProfileContract normalized;
        try { normalized = profile.Normalize(); }
        catch (ArgumentException) { throw new ScmApiProtocolException("SCM 账号资料字段无效。"); }
        if (!string.Equals(normalized.Subject, activeSession.Subject, StringComparison.Ordinal))
        {
            throw new ScmApiProtocolException("SCM 资料返回了其他账号的数据。");
        }

        var projectedSession = PublishResourceSession(activeSession with
        {
            DisplayName = normalized.DisplayName ?? activeSession.DisplayName,
            CorrelationId = correlationId
        });
        return new ScmProfileResult(normalized, projectedSession);
    }

    public async Task<ScmPersonalProfileResult> LoadPersonalProfileAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken)
    {
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var (profile, activeSession) = await ReadAccountResourceAsync<PersonalProfileDocumentContract>(
            session, options.PersonalProfileEndpoint, correlationId, "personal-profile-read", cancellationToken);
        if (profile.SchemaVersion != PersonalProfileContractPolicy.CurrentSchemaVersion ||
            string.IsNullOrWhiteSpace(profile.PublicId) || profile.Identity is null ||
            profile.Content is null || profile.Revision < 0 ||
            profile.Presentation is not null && !ValidPagePresentation(profile.Presentation))
        {
            throw new ScmApiProtocolException("个人页面合同版本不受支持。");
        }

        var projectedSession = PublishResourceSession(activeSession with { CorrelationId = correlationId });
        return new ScmPersonalProfileResult(
            profile.Presentation is null
                ? profile with { Content = PersonalProfileContractPolicy.Normalize(profile.Content) }
                : profile,
            projectedSession);
    }

    public sealed record PersonalProfileBackgroundResult(int SchemaVersion, long Revision, string WallpaperId);

    internal Task<ScmPersonalProfileResult> LoadVisitorPersonalProfileAsync(
        ScmOAuthSession session, string businessSubjectId, CancellationToken token)
    {
        VisitorReadDiagnostics.Select(VisitorReadDiagnostics.Route.ScmMember);
        if (!session.Capabilities.Contains("profile.read", StringComparer.Ordinal))
            throw new ScmApiForbiddenException("当前授权不包含 profile.read。");
        if (businessSubjectId.Length != 71 || !businessSubjectId.StartsWith("scm-v1:", StringComparison.Ordinal) ||
            businessSubjectId[7..].Any(c => c is not (>= '0' and <= '9' or >= 'a' and <= 'f')))
            throw new ArgumentException("Invalid visitor target.");
        return LoadVisitorPersonalProfileAtAsync(session,
            new Uri(options.PersonalProfileEndpoint.AbsoluteUri.TrimEnd('/') + "/visitor/" + Uri.EscapeDataString(businessSubjectId)),
            businessSubjectId, token);
    }

    private async Task<ScmPersonalProfileResult> LoadVisitorPersonalProfileAtAsync(
        ScmOAuthSession session, Uri endpoint, string? expectedSubject, CancellationToken token,
        Func<HttpRequestMessage>? createRequest = null)
    {
        if (!session.Capabilities.Contains("profile.read", StringComparer.Ordinal))
            throw new ScmApiForbiddenException("当前授权不包含 profile.read。");
        var result = await SendResourceRequestWithRefreshAndSessionAsync(session, async (active, ct) =>
        {
            // The factory owns fresh content on every send, including refresh/retry.
            using var request = createRequest?.Invoke() ?? new HttpRequestMessage(HttpMethod.Get, endpoint);
            request.Options.Set(VisitorReadDiagnostics.VisitorRequest, true);
            request.Headers.TryAddWithoutValidation(StarBridge.HostRuntime.Account.PersonalProfilePublicHeader.AcceptHeader,
                StarBridge.HostRuntime.Account.PersonalProfilePublicHeader.AcceptValues);
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, ct);
            await ScmHttpClient.EnsureSuccessAsync(response, "读取个人页面", ct);
            if (!response.Headers.TryGetValues("X-StarBridge-Profile-Subject", out var subjects) ||
                subjects.ToArray() is not [var confirmed] || !ValidVisitorSubject(confirmed) ||
                expectedSubject is not null && !string.Equals(confirmed, expectedSubject, StringComparison.Ordinal))
                throw new ScmApiProtocolException("个人页面身份未得到确认。");
            using var json = await StarBridge.HostRuntime.Account.LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(
                response.Content, ct, 8 * 1024 * 1024);
            if (StarBridge.HostRuntime.Account.PersonalProfilePublicHeader.IsRestricted(json.RootElement))
            {
                try { return (Profile: (PersonalProfileDocumentContract?)null,
                    Header: StarBridge.HostRuntime.Account.PersonalProfilePublicHeader.Parse(json.RootElement, null)); }
                catch (JsonException) { throw new ScmApiProtocolException("个人页面公开头部无效。"); }
            }
            var profile = json.RootElement.Deserialize<PersonalProfileDocumentContract>(new JsonSerializerOptions(JsonSerializerDefaults.Web));
            if (profile is null || profile.SchemaVersion != PersonalProfileContractPolicy.CurrentSchemaVersion ||
                profile.Revision < 0 || string.IsNullOrWhiteSpace(profile.PublicId) || profile.Identity is null || profile.Content is null)
                throw new ScmApiProtocolException("个人页面响应无效。");
            ct.ThrowIfCancellationRequested();
            return (Profile: profile with { Content = NormalizeVisitorContent(profile.Content) },
                Header: (StarBridge.HostRuntime.Account.PersonalProfilePublicHeader?)null);
        }, token);
        return new ScmPersonalProfileResult(result.Result.Profile!, result.ActiveSession) { Restricted = result.Result.Header };
    }

    public sealed record PersonalProfileVisibilityResult(int SchemaVersion, long Revision, string Visibility);

    internal static bool ValidProfileVisibility(string? value) =>
        value is "public" or "friendsAndMainFleet" or "friendsOnly" or "private";

    public async Task<PersonalProfileVisibilityResult> UpdatePersonalProfileVisibilityAsync(
        ScmOAuthSession writeSession, long expectedRevision, string visibility, CancellationToken token)
    {
        if (!writeSession.Capabilities.Contains("profile.write", StringComparer.Ordinal))
            throw new ScmApiForbiddenException("当前授权不包含 profile.write。");
        if (expectedRevision < 0 || expectedRevision == long.MaxValue || !ValidProfileVisibility(visibility))
            throw new ArgumentException("Invalid profile visibility update.");
        using var request = new HttpRequestMessage(HttpMethod.Patch,
            new Uri(options.PersonalProfileEndpoint.AbsoluteUri.TrimEnd('/') + "/visibility"))
        { Content = JsonContent.Create(new { expectedRevision, visibility }) };
        using var response = await scmHttpClient.SendAsync(request, writeSession.AccessToken, token);
        var result = await scmHttpClient.ReadJsonAsync<PersonalProfileVisibilityResult>(response, "资料可见范围修改", token);
        if (result.SchemaVersion != 1 || result.Revision != expectedRevision + 1 || result.Visibility != visibility)
            throw new ScmApiProtocolException("可见范围保存结果未得到确认。");
        return result; // The one-time write grant never becomes the normal login/read session.
    }

    public async Task<PersonalProfileBackgroundResult> UpdatePersonalProfileBackgroundAsync(
        ScmOAuthSession writeSession, long expectedRevision, string wallpaperId, CancellationToken token)
    {
        if (!writeSession.Capabilities.Contains("profile.write", StringComparer.Ordinal))
            throw new ScmApiForbiddenException("当前授权不包含 profile.write。");
        using var request = new HttpRequestMessage(HttpMethod.Patch,
            new Uri(options.PersonalProfileEndpoint.AbsoluteUri.TrimEnd('/') + "/background"))
        {
            Content = JsonContent.Create(new { expectedRevision, wallpaperId })
        };
        using var response = await scmHttpClient.SendAsync(request, writeSession.AccessToken, token);
        var result = await scmHttpClient.ReadJsonAsync<PersonalProfileBackgroundResult>(response, "个人页面背景修改", token);
        if (result.SchemaVersion != 1 || expectedRevision < 0 || expectedRevision == long.MaxValue ||
            result.Revision != expectedRevision + 1 || result.WallpaperId != wallpaperId)
            throw new ScmApiProtocolException("背景保存结果未得到确认。");
        // A one-time write grant must never replace the normal read/login session.
        return result;
    }

    public async Task<ScmPersonalProfileResult> UpdatePersonalProfileAsync(
        ScmOAuthSession profileWriteSession,
        PersonalProfilePresentationUpdateContract update,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(profileWriteSession);
        ArgumentNullException.ThrowIfNull(update);
        if (!profileWriteSession.Capabilities.Contains("profile.write", StringComparer.Ordinal))
        {
            throw new ScmApiForbiddenException("当前授权不包含 profile.write。");
        }

        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        using var request = new HttpRequestMessage(HttpMethod.Patch, options.PersonalProfileEndpoint)
        {
            Content = JsonContent.Create(new
            {
                expectedRevision = update.ExpectedRevision,
                visibility = update.Visibility,
                callSign = update.CallSign,
                avatarStyle = update.AvatarStyle,
                wallpaperId = update.WallpaperId,
                content = new
                {
                    introduction = update.Introduction,
                    modules = update.Modules
                }
            })
        };
        request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, correlationId);
        using var response = await scmHttpClient.SendAsync(
            request,
            profileWriteSession.AccessToken,
            cancellationToken);
        var profile = await scmHttpClient.ReadJsonAsync<PersonalProfileDocumentContract>(
            response,
            "个人页面修改",
            cancellationToken);
        if (profile.SchemaVersion != PersonalProfileContractPolicy.CurrentSchemaVersion)
        {
            throw new ScmApiProtocolException("个人页面修改合同版本不受支持。");
        }

        var projectedSession = PublishResourceSession(profileWriteSession with { CorrelationId = correlationId });
        return new ScmPersonalProfileResult(
            profile with { Content = PersonalProfileContractPolicy.Normalize(profile.Content) },
            projectedSession);
    }

    public async Task<IReadOnlyList<ScmTimeZoneDirectoryEntry>> LoadTimeZoneDirectoryAsync(
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, options.TimeZoneDirectoryEndpoint);
        using var response = await scmHttpClient.SendAsync(request, cancellationToken: cancellationToken);
        var envelope = await scmHttpClient.ReadJsonAsync<ScmTimeZoneDirectoryEnvelope>(
            response,
            "时区目录",
            cancellationToken);
        if (envelope.Code != 0)
        {
            throw new ScmApiProtocolException(
                string.IsNullOrWhiteSpace(envelope.Msg)
                    ? "SCM 时区目录返回了失败状态。"
                    : envelope.Msg.Trim());
        }

        var entries = new List<ScmTimeZoneDirectoryEntry>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in envelope.Data ?? [])
        {
            string? normalized;
            try
            {
                normalized = ScmProfileContractPolicy.NormalizeIanaTimeZone(entry.Value);
            }
            catch (ArgumentException exception)
            {
                throw new ScmApiProtocolException(
                    $"SCM 时区目录包含无效的 IANA 标识：{exception.ParamName ?? "timeZone"}。");
            }

            if (normalized is null || !seen.Add(normalized))
            {
                continue;
            }

            entries.Add(entry with
            {
                Value = normalized,
                Label = string.IsNullOrWhiteSpace(entry.Label) ? normalized : entry.Label.Trim(),
                Offset = string.IsNullOrWhiteSpace(entry.Offset) ? string.Empty : entry.Offset.Trim()
            });
        }

        if (entries.Count == 0)
        {
            throw new ScmApiProtocolException("SCM 时区目录为空，已拒绝打开资料偏好编辑器。");
        }

        return entries;
    }

    public async Task<ScmProfileResult> UpdateProfileAsync(
        ScmOAuthSession profileWriteSession,
        ScmProfilePatchContract patch,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(profileWriteSession);
        ArgumentNullException.ThrowIfNull(patch);
        if (!profileWriteSession.Capabilities.Contains("profile.write", StringComparer.Ordinal))
        {
            throw new ScmApiForbiddenException("当前授权不包含 profile.write。");
        }

        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        using var request = new HttpRequestMessage(HttpMethod.Patch, options.ProfileEndpoint)
        {
            Content = JsonContent.Create(patch.ToWirePayload())
        };
        request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, correlationId);
        using var response = await scmHttpClient.SendAsync(
            request,
            profileWriteSession.AccessToken,
            cancellationToken);
        var profile = (await scmHttpClient.ReadJsonAsync<ScmSelfProfileContract>(
            response,
            "账号资料修改",
            cancellationToken)).Normalize();
        if (!string.Equals(profile.Subject, profileWriteSession.Subject, StringComparison.Ordinal))
        {
            throw new InvalidOperationException("SCM 资料修改返回了其他账号的数据。");
        }

        return new ScmProfileResult(profile, profileWriteSession with
        {
            DisplayName = profile.DisplayName ?? profileWriteSession.DisplayName,
            CorrelationId = correlationId
        });
    }

    internal ScmRealtimeClient? CreateRealtimeClient(
        Action<long, int> statusUpdated, Action<long, string?> forcedLogout,
        Func<CancellationToken, Task<ScmWebSocketTicketResult>> issueTicket,
        Action<long> disconnected, Action<long>? marketplaceInvalidated = null,
        Action<long, JsonElement>? tradeNotice = null, Action<long>? inboxInvalidated = null)
    {
        // Device registration and realtime must use the same Host-owned ID.
        // OAuth-only harnesses without a device provider do not start sockets.
        var deviceId = deviceIdProvider?.Invoke();
        return string.IsNullOrWhiteSpace(deviceId) ? null : new(this, options, deviceId,
            (_, _) => { }, statusUpdated, forcedLogout, (_, _, _, _) => { }, issueTicket, disconnected, marketplaceInvalidated, tradeNotice,
            inboxInvalidated: inboxInvalidated);
    }

    public async Task<ScmWebSocketTicketResult> IssueWebSocketTicketAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken)
    {
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var (ticket, activeSession) = await SendResourceRequestWithRefreshAndSessionAsync(
            session,
            async (currentSession, token) =>
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, options.WebSocketTicketEndpoint);
                request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, correlationId);
                using var response = await scmHttpClient.SendAsync(request, currentSession.AccessToken, token);
                return await scmHttpClient.ReadJsonAsync<ScmWebSocketTicket>(
                    response,
                    "实时连接票据",
                    token, checkBusinessCode: true);
            },
            cancellationToken);
        var projectedSession = PublishResourceSession(activeSession with { CorrelationId = correlationId });
        return new ScmWebSocketTicketResult(ticket, projectedSession);
    }

    public async Task<ScmPresenceStatusResult> UpdatePresenceStatusAsync(
        ScmOAuthSession session,
        int status,
        CancellationToken cancellationToken)
    {
        if (status is < 1 or > 3)
        {
            throw new ArgumentOutOfRangeException(nameof(status));
        }

        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var stopwatch = ScmAuthDiagnostics.Start(
            correlationId,
            "presence-status-update",
            $"endpoint={ScmAuthDiagnostics.Endpoint(options.PresenceStatusEndpoint)} status={status}");
        try
        {
            var (result, activeSession) = await SendResourceRequestWithRefreshAndSessionAsync(
                session,
                async (currentSession, token) =>
                {
                    using var request = new HttpRequestMessage(HttpMethod.Put, options.PresenceStatusEndpoint)
                    {
                        Content = JsonContent.Create(new { status })
                    };
                    request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, correlationId);
                    using var response = await scmHttpClient.SendAsync(request, currentSession.AccessToken, token);
                    return await scmHttpClient.ReadJsonAsync<ScmPresenceStatus>(
                        response,
                        "在线状态更新",
                        token, checkBusinessCode: true);
                },
                cancellationToken);
            var projectedSession = PublishResourceSession(activeSession with { CorrelationId = correlationId });
            ScmAuthDiagnostics.Completed(
                correlationId,
                "presence-status-update",
                stopwatch,
                $"status={result.SignInStatus}");
            return new ScmPresenceStatusResult(result, projectedSession);
        }
        catch (Exception exception)
        {
            ScmAuthDiagnostics.Failed(
                correlationId,
                "presence-status-update",
                stopwatch,
                exception,
                $"requestedStatus={status}");
            throw;
        }
    }

    internal Uri BuildAuthorizeUri(Uri redirectUri, OAuthPkceParameters pkce, string scope)
    {
        var values = new Dictionary<string, string>
        {
            ["response_type"] = "code",
            ["client_id"] = options.ClientId,
            ["redirect_uri"] = redirectUri.AbsoluteUri,
            ["scope"] = scope,
            ["resource"] = options.Resource,
            ["state"] = pkce.State,
            ["code_challenge"] = pkce.CodeChallenge,
            ["code_challenge_method"] = "S256"
        };
        return new UriBuilder(options.AuthorizeEndpoint)
        {
            Query = string.Join("&", values.Select(pair => $"{Uri.EscapeDataString(pair.Key)}={Uri.EscapeDataString(pair.Value)}"))
        }.Uri;
    }

    private async Task<ScmTokenResponse> ExchangeCodeAsync(
        string correlationId,
        string code,
        Uri redirectUri,
        string codeVerifier,
        CancellationToken cancellationToken,
        bool requireRefreshToken = true)
    {
        var callerToken = cancellationToken;
        using var tokenDeadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        tokenDeadline.CancelAfter(TokenRequestTimeout);
        cancellationToken = tokenDeadline.Token;
        var stopwatch = ScmAuthDiagnostics.Start(
            correlationId,
            "token-exchange",
            $"endpoint={ScmAuthDiagnostics.Endpoint(options.TokenEndpoint)}");
        using var request = new HttpRequestMessage(HttpMethod.Post, options.TokenEndpoint)
        {
            Content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["grant_type"] = "authorization_code",
                ["client_id"] = options.ClientId,
                ["code"] = code,
                ["redirect_uri"] = redirectUri.AbsoluteUri,
                ["code_verifier"] = codeVerifier
            })
        };
        request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, correlationId);
        using var response = await SendRouteTokenRequestAsync(request, cancellationToken, callerToken);
        if (!response.IsSuccessStatusCode)
        {
            var businessCode = await ReadTokenFailureCodeAsync(response, cancellationToken);
            ScmAuthDiagnostics.Write(
                correlationId,
                "token-exchange",
                "http-error",
                $"status={(int)response.StatusCode} code={businessCode} error=http-error");
            throw new HttpRequestException(
                "SCM 无法完成令牌交换，请重新授权。",
                null,
                response.StatusCode);
        }
        var result = await ReadTokenResponseAsync(response, correlationId, "token-exchange", cancellationToken);
        if (result is null ||
            string.IsNullOrWhiteSpace(result.AccessToken) ||
            requireRefreshToken && string.IsNullOrWhiteSpace(result.RefreshToken))
        {
            ScmAuthDiagnostics.Write(
                correlationId,
                "token-exchange",
                "invalid-payload",
                $"payloadPresent={result is not null} accessTokenPresent={!string.IsNullOrWhiteSpace(result?.AccessToken)} " +
                $"refreshTokenPresent={!string.IsNullOrWhiteSpace(result?.RefreshToken)}");
            throw new InvalidOperationException("SCM 返回的令牌响应无效。");
        }
        ScmAuthDiagnostics.Completed(
            correlationId,
            "token-exchange",
            stopwatch,
            $"status={(int)response.StatusCode} expiresIn={result.ExpiresIn} " +
            $"scopeCount={CountScopes(result.Scope)}");
        return result;
    }

    private async Task<ScmTokenResponse> RefreshTokenAsync(
        string correlationId,
        string refreshToken,
        CancellationToken cancellationToken)
    {
        var callerToken = cancellationToken;
        using var tokenDeadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        tokenDeadline.CancelAfter(TokenRequestTimeout);
        cancellationToken = tokenDeadline.Token;
        var stopwatch = ScmAuthDiagnostics.Start(
            correlationId,
            "refresh-token",
            $"endpoint={ScmAuthDiagnostics.Endpoint(options.TokenEndpoint)}");
        using var request = new HttpRequestMessage(HttpMethod.Post, options.TokenEndpoint)
        {
            Content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["grant_type"] = "refresh_token",
                ["client_id"] = options.ClientId,
                ["refresh_token"] = refreshToken
            })
        };
        request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, correlationId);
        using var response = await SendRouteTokenRequestAsync(request, cancellationToken, callerToken);
        if (!response.IsSuccessStatusCode)
        {
            // Only an explicit OAuth invalid_grant rejects this user's credential.
            // A client/configuration or gateway 401 must retain it for recovery.
            var error = await ReadRefreshErrorAsync(response, cancellationToken);
            if (response.StatusCode is System.Net.HttpStatusCode.BadRequest or System.Net.HttpStatusCode.Unauthorized &&
                string.Equals(error, "invalid_grant", StringComparison.Ordinal))
            {
                ScmAuthDiagnostics.Write(correlationId, "refresh-token", "rejected",
                    $"status={(int)response.StatusCode} error=rejected");
                throw new ScmRefreshTokenRejectedException();
            }
            if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized)
            {
                var diagnosticError = error == "invalid_client" ? "invalid_client" : "unparsed";
                ScmAuthDiagnostics.Write(correlationId, "refresh-token", "http-error",
                    $"status=401 error={diagnosticError}");
            }
            else
            {
                var businessCode = await ReadTokenFailureCodeAsync(response, cancellationToken);
                ScmAuthDiagnostics.Write(correlationId, "refresh-token", "http-error",
                    $"status={(int)response.StatusCode} code={businessCode} error=http-error");
            }
            throw new ScmRefreshTemporarilyUnavailableException("SCM token refresh is temporarily unavailable.");
        }

        var result = await ReadTokenResponseAsync(response, correlationId, "refresh-token", cancellationToken);
        if (result is null || string.IsNullOrWhiteSpace(result.AccessToken) || string.IsNullOrWhiteSpace(result.RefreshToken))
        {
            ScmAuthDiagnostics.Write(
                correlationId,
                "refresh-token",
                "invalid-payload",
                $"payloadPresent={result is not null} accessTokenPresent={!string.IsNullOrWhiteSpace(result?.AccessToken)} " +
                $"refreshTokenPresent={!string.IsNullOrWhiteSpace(result?.RefreshToken)}");
            throw new InvalidOperationException("SCM 返回的刷新令牌响应无效。");
        }
        ScmAuthDiagnostics.Completed(
            correlationId,
            "refresh-token",
            stopwatch,
            $"status={(int)response.StatusCode} expiresIn={result.ExpiresIn} scopeCount={CountScopes(result.Scope)}");
        return result;
    }

    private static async Task<ScmTokenResponse?> ReadTokenResponseAsync(
        HttpResponseMessage response,
        string correlationId,
        string step,
        CancellationToken cancellationToken)
    {
        var payload = await response.Content.ReadFromJsonAsync<ScmTokenEnvelope>(cancellationToken);
        if (payload is null)
        {
            return null;
        }
        if (payload.Code is not null && payload.Code != 0)
        {
            ScmAuthDiagnostics.Write(
                correlationId,
                step,
                "business-error",
                $"status={(int)response.StatusCode} code={payload.Code} error=business-error");
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(payload.Message)
                ? "SCM 拒绝了令牌请求。"
                : $"SCM 拒绝了令牌请求：{payload.Message}");
        }
        return payload.Data ?? payload.AsTokenResponse();
    }

    private async Task<ScmIdentityResponse> LoadIdentityAsync(
        string correlationId,
        string accessToken,
        CancellationToken cancellationToken)
    {
        var stopwatch = ScmAuthDiagnostics.Start(
            correlationId,
            "me-request",
            $"endpoint={ScmAuthDiagnostics.Endpoint(options.MeEndpoint)}");
        using var request = new HttpRequestMessage(HttpMethod.Get, options.MeEndpoint);
        request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, correlationId);
        using var response = await scmHttpClient.SendAsync(request, accessToken, cancellationToken,
            requestTimeout: ResourceRequestTimeout);
        try
        {
            await ScmHttpClient.EnsureSuccessAsync(response, "身份资料", cancellationToken);
        }
        catch (HttpRequestException exception)
        {
            ScmAuthDiagnostics.Failed(correlationId, "me-request", stopwatch, exception);
            throw;
        }
        var identity = await scmHttpClient.ReadJsonAsync<ScmIdentityResponse>(response, "身份资料", cancellationToken, checkBusinessCode: true);
        if (identity is null)
        {
            ScmAuthDiagnostics.Write(correlationId, "me-request", "invalid-payload", "payloadPresent=false");
            throw new InvalidOperationException("SCM 返回的账号资料无效。");
        }
        ScmAuthDiagnostics.Completed(
            correlationId,
            "me-request",
            stopwatch,
            $"status={(int)response.StatusCode} subjectPresent={!string.IsNullOrWhiteSpace(identity.Subject)} " +
            $"capabilityCount={identity.Capabilities?.Length ?? 0}");
        return identity;
    }

    private async Task<T> SendGameIdentityRequestAsync<T>(
        Uri endpoint,
        ScmOAuthSession session,
        object body,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = JsonContent.Create(body)
        };
        // Never put SCM's private rejection message into an exception. It is
        // returned only as a bounded response field on an explicit rejection.
        const string failure = "SCM game identity request is unavailable.";
        try
        {
            using var response = await scmHttpClient.SendAsync(request, session.AccessToken, cancellationToken);
            if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized) throw new ScmApiAuthenticationException(failure);
            if (response.StatusCode == System.Net.HttpStatusCode.Forbidden) throw new ScmApiForbiddenException(failure);
            if (response.StatusCode is System.Net.HttpStatusCode.BadRequest or System.Net.HttpStatusCode.Conflict or
                System.Net.HttpStatusCode.UnprocessableEntity)
            {
                using var document = await response.Content.ReadFromJsonAsync<JsonDocument>(cancellationToken);
                if (document?.RootElement is not { ValueKind: JsonValueKind.Object } root)
                    throw new ScmApiProtocolException(failure);
                if (root.TryGetProperty("code", out var businessCode) && businessCode.TryGetInt32(out var code))
                {
                    if (code == 401) throw new ScmApiAuthenticationException(failure);
                    if (code == 403) throw new ScmApiForbiddenException(failure);
                }
                var message = root.TryGetProperty("message", out var field) && field.ValueKind == JsonValueKind.String
                    ? field.GetString() : null;
                message = message is { Length: > 512 } ? message[..512] : message;
                return (T)(object)(typeof(T) == typeof(ScmGameIdentityVerificationCode)
                    ? (object)new ScmGameIdentityVerificationCode(true, false, message, null, 0)
                    : new ScmGameIdentityVerificationResult(true, false, message));
            }
            if (response.StatusCode >= System.Net.HttpStatusCode.InternalServerError)
                throw new ScmApiUnavailableException(failure, response.StatusCode);
            if (!response.IsSuccessStatusCode) throw new HttpRequestException(failure, null, response.StatusCode);
            return await scmHttpClient.ReadJsonAsync<T>(response, "游戏身份验证", cancellationToken, checkBusinessCode: true);
        }
        catch (ScmApiAuthenticationException) { throw new ScmApiAuthenticationException(failure); }
        catch (ScmApiForbiddenException) { throw new ScmApiForbiddenException(failure); }
        catch (ScmApiUnavailableException error) { throw new ScmApiUnavailableException(failure, error.StatusCode); }
        catch (OperationCanceledException) { throw new OperationCanceledException(failure, cancellationToken); }
        catch (HttpRequestException error) { throw new HttpRequestException(failure, null, error.StatusCode); }
        catch (Exception error) when (error is JsonException or InvalidOperationException or NotSupportedException)
        { throw new ScmApiProtocolException(failure); }
    }

    private async Task<ScmDesktopDeviceStatus> SendDesktopDeviceRequestAsync(
        Uri endpoint,
        ScmOAuthSession session,
        object body,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = JsonContent.Create(body)
        };
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var step = endpoint == options.DeviceRegisterEndpoint ? "device-register" : "device-status";
        request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, correlationId);
        var stopwatch = ScmAuthDiagnostics.Start(correlationId, step);
        try
        {
            using var response = await scmHttpClient.SendAsync(request, session.AccessToken, cancellationToken,
                requestTimeout: ResourceRequestTimeout);
            var status = await scmHttpClient.ReadJsonAsync<ScmDesktopDeviceStatus>(
                response, "设备安全验证", cancellationToken, checkBusinessCode: true);
            ScmAuthDiagnostics.Completed(correlationId, step, stopwatch,
                $"trusted={status.Trusted}");
            return status;
        }
        catch (Exception exception)
        {
            ScmAuthDiagnostics.Failed(correlationId, step, stopwatch, exception);
            throw;
        }
    }

    private async Task<(T Result, ScmOAuthSession ActiveSession)> ReadAccountResourceAsync<T>(
        ScmOAuthSession session,
        Uri endpoint,
        string correlationId,
        string step,
        CancellationToken cancellationToken,
        int? maximumResponseBytes = null, Action<ScmOAuthSession>? sessionReady = null)
    {
        // One finite budget covers session recovery, HTTP and decoding together.
        // Only these GETs use this policy; writes keep their existing deadlines.
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(ResourceRequestTimeout);
        var stopwatch = ScmAuthDiagnostics.Start(correlationId, step);
        try
        {
            var result = await SendResourceRequestWithRefreshAndSessionAsync(
                session,
                async (currentSession, token) =>
                {
                    ScmAuthDiagnostics.Write(correlationId, step, "sending",
                        $"credentialVersion={currentSession.CredentialVersion:N}");
                    using var request = new HttpRequestMessage(HttpMethod.Get, endpoint);
                    request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, correlationId);
                    using var response = await scmHttpClient.SendAsync(request, currentSession.AccessToken, token,
                        requestTimeout: ResourceRequestTimeout,
                        completionOption: maximumResponseBytes is null ? HttpCompletionOption.ResponseContentRead : HttpCompletionOption.ResponseHeadersRead);
                    if (maximumResponseBytes is { } maximum)
                    {
                        await ScmHttpClient.EnsureSuccessAsync(response, step, token);
                        await using var stream = await response.Content.ReadAsStreamAsync(token);
                        using var buffer = new MemoryStream();
                        var block = new byte[16384];
                        int count;
                        while ((count = await stream.ReadAsync(block, token)) != 0)
                        {
                            if (buffer.Length + count > maximum) throw new ScmApiProtocolException("SCM source exceeds the read budget.");
                            buffer.Write(block, 0, count);
                        }
                        try {
                            using var document = JsonDocument.Parse(buffer.ToArray());
                            ScmHttpClient.EnsureBusinessSuccess(document.RootElement);
                            return document.RootElement.Deserialize<T>(new JsonSerializerOptions(JsonSerializerDefaults.Web))
                                ?? throw new ScmApiProtocolException("SCM source returned no collection.");
                        } catch (System.Text.Json.JsonException) { throw new ScmApiProtocolException("SCM source returned invalid JSON."); }
                    }
                    return await scmHttpClient.ReadJsonAsync<T>(response, step, token, checkBusinessCode: true);
                },
                deadline.Token, sessionReady);
            ScmAuthDiagnostics.Completed(correlationId, step, stopwatch);
            return result;
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            ScmAuthDiagnostics.Failed(correlationId, step, stopwatch, exception);
            throw new ScmApiUnavailableException("Account resource read timed out.");
        }
        catch (Exception exception)
        {
            ScmAuthDiagnostics.Failed(correlationId, step, stopwatch, exception);
            throw;
        }
    }

    private async Task<ScmOAuthSession> EnsureActiveSessionAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken)
    {
        await AdoptInitialResourceSessionAsync(session, cancellationToken);
        if (_currentSession is null && _sessionWasInstalled)
            throw new ScmRefreshTemporarilyUnavailableException("Original session lifecycle has ended.");
        if (_currentSession is { } installed && !SameOwner(installed, session))
            throw new ScmRefreshTemporarilyUnavailableException("SCM account changed during request.");
        var candidate = _currentSession is not null &&
                        SameOwner(_currentSession, session)
            ? _currentSession
            : session;
        if (candidate.ExpiresAt > SessionNow.AddMinutes(1))
        {
            return candidate;
        }

        return await TryRestoreSessionAsync(cancellationToken)
            ?? throw new ScmApiAuthenticationException("SCM 登录已失效，请重新授权。");
    }

    private async Task<T> SendResourceRequestWithRefreshAsync<T>(
        ScmOAuthSession session,
        Func<ScmOAuthSession, CancellationToken, Task<T>> sendAsync,
        CancellationToken cancellationToken, Action<ScmOAuthSession>? sessionReady = null)
    {
        var (result, _) = await SendResourceRequestWithRefreshAndSessionAsync(
            session,
            sendAsync,
            cancellationToken, sessionReady);
        return result;
    }

    internal Task<(T Result, ScmOAuthSession ActiveSession)> SendResourceRequestAsync<T>(
        ScmOAuthSession session,
        Func<ScmOAuthSession, CancellationToken, Task<T>> sendAsync,
        CancellationToken cancellationToken, Action<ScmOAuthSession>? sessionReady = null) =>
        SendResourceRequestWithRefreshAndSessionAsync(session, sendAsync, cancellationToken, sessionReady);

    private async Task<(T Result, ScmOAuthSession ActiveSession)> SendResourceRequestWithRefreshAndSessionAsync<T>(
        ScmOAuthSession session,
        Func<ScmOAuthSession, CancellationToken, Task<T>> sendAsync,
        CancellationToken cancellationToken, Action<ScmOAuthSession>? sessionReady = null)
    {
        var installed = Volatile.Read(ref _currentSession);
        var activeSession = installed is not null && SameOwner(installed, session) ? installed : session;
        try
        {
            activeSession = await EnsureActiveSessionAsync(activeSession, cancellationToken);
            sessionReady?.Invoke(activeSession);
            try
            {
                return (await sendAsync(activeSession, cancellationToken), activeSession);
            }
            catch (ScmApiAuthenticationException)
            {
                activeSession = await RefreshSessionAfterUnauthorizedAsync(activeSession, cancellationToken);
                sessionReady?.Invoke(activeSession);
                return (await sendAsync(activeSession, cancellationToken), activeSession);
            }
        }
        catch (ScmApiAuthenticationException)
        {
            cancellationToken.ThrowIfCancellationRequested();
            // A shared restore may have rejected a newer expired version.
            // Carry that actual owner into notification after its guarded clear.
            if (_currentSession is null && _rejectedSession is { } rejected && SameOwner(rejected, activeSession))
                activeSession = rejected;
            if (await InvalidateSessionAfterAuthenticationFailureAsync(activeSession)) throw;
            if (await ExpireRejectedResourceSessionAsync(activeSession))
                throw new ScmRefreshTemporarilyUnavailableException("Resource access is temporarily unavailable.");
            // A late failure belongs to a superseded version. One bounded retry
            // with the current session; never rotate again for the old rejection.
            activeSession = await ReuseSupersedingSessionAsync(activeSession, cancellationToken);
            sessionReady?.Invoke(activeSession);
            try { return (await sendAsync(activeSession, cancellationToken), activeSession); }
            catch (ScmApiAuthenticationException)
            {
                cancellationToken.ThrowIfCancellationRequested();
                await ExpireRejectedResourceSessionAsync(activeSession);
                throw new ScmRefreshTemporarilyUnavailableException("Session changed during resource retry.");
            }
        }
    }

    private async Task<bool> InvalidateSessionAfterAuthenticationFailureAsync(ScmOAuthSession session)
    {
        var retirement = await ObserveAuthoritativeCredentialRejectionAsync(session);
        if (!retirement.Retired) return false;
        if (!retirement.Notify) return true;
        var handlers = SessionInvalidated;
        if (handlers is null)
        {
            return true;
        }

        foreach (Action<OAuthPkceClient, ScmOAuthSession> handler in handlers.GetInvocationList())
        {
            try
            {
                handler(this, session);
            }
            catch (Exception exception)
            {
                ScmAuthDiagnostics.Write(
                    session.CorrelationId ?? "authentication-expired",
                    "authentication-expired-notification",
                    "failed",
                    $"exceptionType={exception.GetType().Name}");
            }
        }
        return true;
    }

    private async Task<ScmOAuthSession> RefreshSessionAfterUnauthorizedAsync(
        ScmOAuthSession rejectedSession,
        CancellationToken cancellationToken)
    {
        var restored = await RestoreSessionAsync(cancellationToken, rejectedSession);
        // A joined ordinary restore may only have returned the rejected memory
        // version. It did not refresh that 401; force its one refresh now.
        if (restored is not null && SameCredential(restored, rejectedSession))
            restored = await RestoreSessionAsync(cancellationToken, rejectedSession);
        return restored ?? throw new ScmApiAuthenticationException("SCM 登录已失效，请重新授权。");
    }

    private static async Task<string?> ReadRefreshErrorAsync(HttpResponseMessage response, CancellationToken token)
    {
        try
        {
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
            return document.RootElement is { ValueKind: JsonValueKind.Object } root &&
                root.TryGetProperty("error", out var error) && error.ValueKind == JsonValueKind.String
                ? error.GetString() : null;
        }
        catch (JsonException) { return null; }
    }

    private static async Task<int?> ReadTokenFailureCodeAsync(HttpResponseMessage response, CancellationToken token)
    {
        try
        {
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
            return document?.RootElement is { ValueKind: JsonValueKind.Object } root &&
                root.TryGetProperty("code", out var code) && code.ValueKind == JsonValueKind.Number && code.TryGetInt32(out var number) ? number : null;
        }
        catch (JsonException) { return null; }
    }

    private static int CountScopes(string? scopes) =>
        string.IsNullOrWhiteSpace(scopes)
            ? 0
            : scopes.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;

    private static bool ContainsScope(string? scopes, string expectedScope) =>
        !string.IsNullOrWhiteSpace(scopes) &&
        scopes.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Contains(expectedScope, StringComparer.Ordinal);

    private string AccountKey(string subject) => $"{options.AuthorityId}:{subject}";

    private ScmOAuthSession CreateSession(
        ScmIdentityResponse identity,
        ScmTokenResponse tokenResponse,
        string correlationId,
        DateTimeOffset? fixedExpiresAt = null)
    {
        var gameIdentity = identity.GameIdentitySnapshot;
        return new ScmOAuthSession(
            options.AuthorityId,
            identity.Subject,
            string.IsNullOrWhiteSpace(identity.DisplayName) ? "SCM 用户" : identity.DisplayName,
            tokenResponse.AccessToken,
            fixedExpiresAt ?? SessionNow.AddSeconds(Math.Max(1, tokenResponse.ExpiresIn)),
            identity.Capabilities ?? [],
            gameIdentity.Status == ScmGameIdentityStatus.Verified,
            correlationId,
            gameIdentity.Status == ScmGameIdentityStatus.Verified ? gameIdentity.Handle : null,
            gameIdentity.Status,
            gameIdentity.Status == ScmGameIdentityStatus.Verified ? gameIdentity.CanonicalHandle : null,
            identity.GameIdentity?.VerificationMethod,
            identity.GameIdentity?.VerifiedAt);
    }

    private static ScmGameIdentitySnapshot ResolveBootstrapGameIdentity(
        ScmBootstrapProfile profile,
        ScmOAuthSession activeSession)
    {
        if (profile.GameIdentity is not null)
        {
            return profile.GameIdentity.ToSnapshot();
        }

        return profile.GameIdentityVerified switch
        {
            true => new ScmGameIdentitySnapshot(
                ScmGameIdentityStatus.Verified,
                activeSession.GameIdentityHandle,
                activeSession.GameIdentityNormalizedHandle),
            false => new ScmGameIdentitySnapshot(
                ScmGameIdentityStatus.Unverified,
                null,
                null),
            null => activeSession.AuthoritativeGameIdentity
        };
    }

    private sealed record ScmTokenResponse(
        [property: JsonPropertyName("access_token")] string AccessToken,
        [property: JsonPropertyName("refresh_token")] string RefreshToken,
        [property: JsonPropertyName("token_type")] string TokenType,
        [property: JsonPropertyName("expires_in")] long ExpiresIn,
        string? Scope);

    private sealed record ScmTokenEnvelope(
        int? Code,
        [property: JsonPropertyName("msg")] string? Message,
        ScmTokenResponse? Data,
        [property: JsonPropertyName("access_token")] string? AccessToken,
        [property: JsonPropertyName("refresh_token")] string? RefreshToken,
        [property: JsonPropertyName("token_type")] string? TokenType,
        [property: JsonPropertyName("expires_in")] long ExpiresIn,
        string? Scope)
    {
        internal ScmTokenResponse? AsTokenResponse() => string.IsNullOrWhiteSpace(AccessToken)
            ? null
            : new ScmTokenResponse(AccessToken, RefreshToken ?? string.Empty, TokenType ?? string.Empty, ExpiresIn, Scope);
    }

    private sealed record ScmIdentityResponse(
        string Subject,
        string? DisplayName,
        string? AvatarUrl,
        string? Locale,
        string? TimeZone,
        string[]? Capabilities,
        ScmGameIdentityContract? GameIdentity = null)
    {
        internal ScmGameIdentitySnapshot GameIdentitySnapshot =>
            GameIdentity?.ToSnapshot() ??
            new ScmGameIdentitySnapshot(ScmGameIdentityStatus.Unknown, null, null);
    }

    private sealed record ScmOAuthErrorResponse(
        [property: JsonPropertyName("error")] string? Error,
        [property: JsonPropertyName("error_description")] string? ErrorDescription = null);

    private sealed record ScmTimeZoneDirectoryEnvelope(
        int Code,
        ScmTimeZoneDirectoryEntry[]? Data,
        string? Msg);

    private sealed class ScmRefreshTokenRejectedException : Exception;
}
