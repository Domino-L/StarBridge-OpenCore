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
    public ScmGameIdentitySnapshot AuthoritativeGameIdentity => new(
        GameIdentityStatus != ScmGameIdentityStatus.Unknown
            ? GameIdentityStatus
            : GameIdentityVerified
                ? ScmGameIdentityStatus.Verified
                : ScmGameIdentityStatus.Unknown,
        GameIdentityHandle,
        GameIdentityNormalizedHandle);

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
    long ExpireTime);

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
    DateTimeOffset? ObservedAt = null)
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
    ScmOAuthSession ActiveSession);

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
    Func<string>? deviceIdProvider = null) : IIdentityLinkAuthorizationClient, IProfileWriteAuthorizationClient
{
    private const string IdentityLinkScope = "openid profile.read identity.link";
    private const string ProfileWriteScope = "openid profile.read profile.write";
    // Resource requests include Java introspection plus an upstream SCM
    // operation. Leave room for both bounded 20-second integration hops.
    private static readonly TimeSpan ResourceRequestTimeout = TimeSpan.FromSeconds(45);
    private static readonly TimeSpan TokenRequestTimeout = TimeSpan.FromSeconds(30);
    private readonly SemaphoreSlim _refreshGate = new(1, 1);
    private ScmOAuthSession? _currentSession;

    public event Action<OAuthPkceClient, ScmOAuthSession>? SessionInvalidated;

    public ScmSessionRestoreOutcome LastSessionRestoreOutcome { get; private set; }

    public async Task<ScmOAuthSession> SignInAsync(
        CancellationToken cancellationToken,
        Action<string>? reportProgress = null)
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
            var pkce = OAuthPkceParameters.Create();
            await using var callback = LoopbackCallbackListener.Start(options.CallbackPath);
            ScmAuthDiagnostics.Write(
                correlationId,
                "callback-listener",
                "ready",
                $"redirect={ScmAuthDiagnostics.Endpoint(callback.RedirectUri)} pkceMethod=S256");
            var authorizeUri = BuildAuthorizeUri(callback.RedirectUri, pkce, options.Scope);

            Process.Start(new ProcessStartInfo(authorizeUri.AbsoluteUri) { UseShellExecute = true });
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
            reportProgress?.Invoke("令牌交换完成，正在验证账号身份...");
            var identity = await LoadIdentityAsync(correlationId, tokenResponse.AccessToken, timeout.Token);
            if (string.IsNullOrWhiteSpace(identity.Subject))
            {
                ScmAuthDiagnostics.Write(correlationId, "identity-validation", "failed", "subjectPresent=false");
                throw new InvalidOperationException("SCM 返回的账号主体无效。");
            }

            var session = CreateSession(identity, tokenResponse, correlationId);
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
                var accountKey = AccountKey(identity.Subject);
                DeletePreviousAccountCredential(accountKey);
                var vaultStopwatch = ScmAuthDiagnostics.Start(correlationId, "refresh-token-vault-save");
                tokenVault.SaveRefreshToken(accountKey, tokenResponse.RefreshToken);
                ScmAuthDiagnostics.Completed(correlationId, "refresh-token-vault-save", vaultStopwatch);
                _currentSession = session;
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
            Process.Start(new ProcessStartInfo(authorizeUri.AbsoluteUri) { UseShellExecute = true });
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
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var authorizeStopwatch = ScmAuthDiagnostics.Start(
            correlationId,
            "profile-write-authorize",
            $"authorize={ScmAuthDiagnostics.Endpoint(options.AuthorizeEndpoint)} clientId={options.ClientId}");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromMinutes(3));
        try
        {
            var pkce = OAuthPkceParameters.Create();
            await using var callback = LoopbackCallbackListener.Start(options.CallbackPath);
            var authorizeUri = BuildAuthorizeUri(callback.RedirectUri, pkce, ProfileWriteScope);
            Process.Start(new ProcessStartInfo(authorizeUri.AbsoluteUri) { UseShellExecute = true });
            var authorization = await callback.WaitForCallbackAsync(pkce.State, timeout.Token);
            reportProgress?.Invoke("已收到 SCM 资料授权，正在验证账号...");
            var tokenResponse = await ExchangeCodeAsync(
                correlationId,
                authorization.Code,
                callback.RedirectUri,
                pkce.CodeVerifier,
                timeout.Token,
                requireRefreshToken: false);
            if (!ContainsScope(tokenResponse.Scope, "profile.write"))
            {
                throw new ScmApiForbiddenException("SCM 未授予资料偏好修改权限。");
            }

            var identity = await LoadIdentityAsync(correlationId, tokenResponse.AccessToken, timeout.Token);
            if (!string.Equals(identity.Subject, currentSession.Subject, StringComparison.Ordinal))
            {
                throw new ScmApiAuthenticationException("资料授权账号与当前 SCM 登录账号不一致。");
            }

            var writeSession = CreateSession(identity, tokenResponse, correlationId) with
            {
                Capabilities = ["profile.write"]
            };
            ScmAuthDiagnostics.Completed(
                correlationId,
                "profile-write-authorize",
                authorizeStopwatch,
                "subjectMatched=true scopeGranted=true persisted=false");
            return writeSession;
        }
        catch (OperationCanceledException) when (timeout.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
        {
            throw new TimeoutException("Profile authorization timed out.");
        }
        catch (Exception exception)
        {
            ScmAuthDiagnostics.Failed(correlationId, "profile-write-authorize", authorizeStopwatch, exception);
            throw;
        }
    }

    public async Task<ScmOAuthSession?> TryRestoreSessionAsync(CancellationToken cancellationToken)
    {
        LastSessionRestoreOutcome = ScmSessionRestoreOutcome.NotAttempted;
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var restoreStopwatch = ScmAuthDiagnostics.Start(correlationId, "session-restore");
        await _refreshGate.WaitAsync(cancellationToken);
        try
        {
            if (_currentSession is not null && _currentSession.ExpiresAt > DateTimeOffset.UtcNow.AddMinutes(1))
            {
                LastSessionRestoreOutcome = ScmSessionRestoreOutcome.Restored;
                ScmAuthDiagnostics.Completed(correlationId, "session-restore", restoreStopwatch, "source=memory");
                return _currentSession;
            }

            var vaultLoadStopwatch = ScmAuthDiagnostics.Start(correlationId, "refresh-token-vault-load");
            var accountKey = tokenVault.LoadActiveAccountKey();
            if (string.IsNullOrWhiteSpace(accountKey) || !accountKey.StartsWith(options.AuthorityId + ":", StringComparison.Ordinal))
            {
                LastSessionRestoreOutcome = ScmSessionRestoreOutcome.NoStoredCredential;
                ScmAuthDiagnostics.Completed(
                    correlationId,
                    "refresh-token-vault-load",
                    vaultLoadStopwatch,
                    "activeAccountPresent=false");
                ScmAuthDiagnostics.Completed(correlationId, "session-restore", restoreStopwatch, "outcome=no-credential");
                return null;
            }

            var refreshToken = tokenVault.LoadRefreshToken(accountKey);
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
            try
            {
                var tokenResponse = await RefreshTokenAsync(correlationId, refreshToken, cancellationToken);
                var vaultSaveStopwatch = ScmAuthDiagnostics.Start(correlationId, "refresh-token-vault-rotate");
                tokenVault.SaveRefreshToken(accountKey, tokenResponse.RefreshToken);
                ScmAuthDiagnostics.Completed(correlationId, "refresh-token-vault-rotate", vaultSaveStopwatch);
                var identity = await LoadIdentityAsync(correlationId, tokenResponse.AccessToken, cancellationToken);
                if (string.IsNullOrWhiteSpace(identity.Subject) || !AccountKey(identity.Subject).Equals(accountKey, StringComparison.Ordinal))
                {
                    LastSessionRestoreOutcome = ScmSessionRestoreOutcome.ReauthorizationRequired;
                    tokenVault.DeleteRefreshToken(accountKey);
                    ScmAuthDiagnostics.Write(
                        correlationId,
                        "session-restore",
                        "identity-mismatch",
                        $"subjectPresent={!string.IsNullOrWhiteSpace(identity.Subject)}");
                    throw new InvalidOperationException("SCM 刷新后的账号身份与本地凭据不匹配。");
                }

                var restoredSession = CreateSession(identity, tokenResponse, correlationId);
                if (deviceIdProvider is not null)
                {
                    var deviceStatus = await GetDesktopDeviceStatusAsync(
                        restoredSession, deviceIdProvider(), cancellationToken);
                    if (!deviceStatus.Trusted)
                    {
                        LastSessionRestoreOutcome = ScmSessionRestoreOutcome.ReauthorizationRequired;
                        tokenVault.DeleteRefreshToken(accountKey);
                        _currentSession = null;
                        ScmAuthDiagnostics.Completed(
                            correlationId,
                            "session-restore",
                            restoreStopwatch,
                            "outcome=device-untrusted credentialDeleted=true");
                        return null;
                    }
                }

                _currentSession = restoredSession;
                LastSessionRestoreOutcome = ScmSessionRestoreOutcome.Restored;
                ScmAuthDiagnostics.Completed(
                    correlationId,
                    "session-restore",
                    restoreStopwatch,
                    $"outcome=success capabilityCount={_currentSession.Capabilities.Length}");
                return _currentSession;
            }
            catch (ScmRefreshTokenRejectedException)
            {
                LastSessionRestoreOutcome = ScmSessionRestoreOutcome.ReauthorizationRequired;
                tokenVault.DeleteRefreshToken(accountKey);
                _currentSession = null;
                ScmAuthDiagnostics.Completed(
                    correlationId,
                    "session-restore",
                    restoreStopwatch,
                    "outcome=refresh-token-rejected credentialDeleted=true");
                return null;
            }
        }
        catch (Exception exception)
        {
            ScmAuthDiagnostics.Failed(correlationId, "session-restore", restoreStopwatch, exception);
            throw;
        }
        finally
        {
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
            var refreshToken = tokenVault.LoadRefreshToken(accountKey);
            tokenVault.DeleteRefreshToken(accountKey);
            if (ReferenceEquals(_currentSession, session))
            {
                _currentSession = null;
            }

            ScmAuthDiagnostics.Write(
                correlationId,
                "session-revoke-local",
                "completed",
                "credentialDeleted=true memorySessionCleared=true");
            if (!string.IsNullOrWhiteSpace(refreshToken))
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
        var accountKey = $"{session.AuthorityId}:{session.Subject}";
        await _refreshGate.WaitAsync(cancellationToken);
        try
        {
            tokenVault.DeleteRefreshToken(accountKey);
            if (_currentSession is not null &&
                string.Equals(_currentSession.AuthorityId, session.AuthorityId, StringComparison.Ordinal) &&
                string.Equals(_currentSession.Subject, session.Subject, StringComparison.Ordinal))
            {
                _currentSession = null;
            }
        }
        finally
        {
            _refreshGate.Release();
        }
    }

    public async Task<ScmOAuthSession> RefreshIdentityAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken)
    {
        session = await EnsureActiveSessionAsync(session, cancellationToken);
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var (identity, activeSession) = await SendResourceRequestWithRefreshAndSessionAsync(
            session,
            (activeSession, token) => LoadIdentityAsync(correlationId, activeSession.AccessToken, token),
            cancellationToken);
        if (!string.Equals(identity.Subject, activeSession.Subject, StringComparison.Ordinal))
        {
            throw new InvalidOperationException("SCM 返回的账号身份与当前会话不匹配。");
        }

        _currentSession = activeSession with
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
        return _currentSession;
    }

    public Task<ScmGameIdentityVerificationCode> GetGameIdentityVerificationCodeAsync(
        ScmOAuthSession session,
        string gameName,
        CancellationToken cancellationToken) => SendResourceRequestWithRefreshAsync(
            session,
            (activeSession, token) => SendGameIdentityRequestAsync<ScmGameIdentityVerificationCode>(
                new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/game-identity/verification-code"),
                activeSession,
                new { gameName },
                token),
            cancellationToken);

    public Task<ScmGameIdentityVerificationResult> VerifyGameIdentityAsync(
        ScmOAuthSession session,
        string gameName,
        string userMobile,
        CancellationToken cancellationToken) => SendResourceRequestWithRefreshAsync(
            session,
            (activeSession, token) => SendGameIdentityRequestAsync<ScmGameIdentityVerificationResult>(
                new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/game-identity/verify"),
                activeSession,
                new { gameName, userMobile },
                token),
            cancellationToken);

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
        _currentSession = activeSession with
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
        };
        return new ScmBootstrapResult(snapshot, _currentSession);
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

    public async Task<ScmProfileResult> LoadProfileAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken)
    {
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var endpoint = new UriBuilder(options.ProfileEndpoint) { Query = "view=self" }.Uri;
        var (profile, activeSession) = await ReadAccountResourceAsync<ScmSelfProfileContract>(
            session, endpoint, correlationId, "account-profile-read", cancellationToken);
        var normalized = profile.Normalize();
        if (!string.Equals(normalized.Subject, activeSession.Subject, StringComparison.Ordinal))
        {
            throw new InvalidOperationException("SCM 资料返回了其他账号的数据。");
        }

        _currentSession = activeSession with
        {
            DisplayName = normalized.DisplayName ?? activeSession.DisplayName,
            CorrelationId = correlationId
        };
        return new ScmProfileResult(normalized, _currentSession);
    }

    public async Task<ScmPersonalProfileResult> LoadPersonalProfileAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken)
    {
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var (profile, activeSession) = await ReadAccountResourceAsync<PersonalProfileDocumentContract>(
            session, options.PersonalProfileEndpoint, correlationId, "personal-profile-read", cancellationToken);
        if (profile.SchemaVersion != PersonalProfileContractPolicy.CurrentSchemaVersion)
        {
            throw new ScmApiProtocolException("个人页面合同版本不受支持。");
        }

        _currentSession = activeSession with { CorrelationId = correlationId };
        return new ScmPersonalProfileResult(
            profile with { Content = PersonalProfileContractPolicy.Normalize(profile.Content) },
            _currentSession);
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

        _currentSession = profileWriteSession with { CorrelationId = correlationId };
        return new ScmPersonalProfileResult(
            profile with { Content = PersonalProfileContractPolicy.Normalize(profile.Content) },
            _currentSession);
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
                    token);
            },
            cancellationToken);
        _currentSession = activeSession with { CorrelationId = correlationId };
        return new ScmWebSocketTicketResult(ticket, _currentSession);
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
                        token);
                },
                cancellationToken);
            _currentSession = activeSession with { CorrelationId = correlationId };
            ScmAuthDiagnostics.Completed(
                correlationId,
                "presence-status-update",
                stopwatch,
                $"status={result.SignInStatus}");
            return new ScmPresenceStatusResult(result, _currentSession);
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
        using var response = await scmHttpClient.SendAsync(request,
            cancellationToken: cancellationToken, requestTimeout: TokenRequestTimeout);
        if (!response.IsSuccessStatusCode)
        {
            var oauthError = await ReadOAuthErrorAsync(response, cancellationToken);
            ScmAuthDiagnostics.Write(
                correlationId,
                "token-exchange",
                "http-error",
                $"status={(int)response.StatusCode} error={oauthError.Error} description={oauthError.Description}");
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
            $"status={(int)response.StatusCode} tokenType={result.TokenType} expiresIn={result.ExpiresIn} " +
            $"scopeCount={CountScopes(result.Scope)}");
        return result;
    }

    private async Task<ScmTokenResponse> RefreshTokenAsync(
        string correlationId,
        string refreshToken,
        CancellationToken cancellationToken)
    {
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
        using var response = await scmHttpClient.SendAsync(request,
            cancellationToken: cancellationToken, requestTimeout: TokenRequestTimeout);
        if (!response.IsSuccessStatusCode)
        {
            if (response.StatusCode is System.Net.HttpStatusCode.BadRequest or System.Net.HttpStatusCode.Unauthorized)
            {
                var error = await response.Content.ReadFromJsonAsync<ScmOAuthErrorResponse>(cancellationToken);
                if (string.Equals(error?.Error, "invalid_grant", StringComparison.Ordinal))
                {
                    ScmAuthDiagnostics.Write(
                        correlationId,
                        "refresh-token",
                        "rejected",
                        $"status={(int)response.StatusCode} error=invalid_grant elapsedMs={stopwatch.ElapsedMilliseconds}");
                    throw new ScmRefreshTokenRejectedException();
                }
            }
            ScmAuthDiagnostics.Write(
                correlationId,
                "refresh-token",
                "http-error",
                $"status={(int)response.StatusCode} elapsedMs={stopwatch.ElapsedMilliseconds}");
            response.EnsureSuccessStatusCode();
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
                $"code={payload.Code} message={payload.Message}");
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
        var identity = await response.Content.ReadFromJsonAsync<ScmIdentityResponse>(cancellationToken);
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
        using var response = await scmHttpClient.SendAsync(request, session.AccessToken, cancellationToken);
        return await scmHttpClient.ReadJsonAsync<T>(response, "游戏身份验证", cancellationToken);
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
                response, "设备安全验证", cancellationToken);
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
        CancellationToken cancellationToken)
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
                    using var request = new HttpRequestMessage(HttpMethod.Get, endpoint);
                    request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, correlationId);
                    using var response = await scmHttpClient.SendAsync(request, currentSession.AccessToken, token,
                        requestTimeout: ResourceRequestTimeout);
                    return await scmHttpClient.ReadJsonAsync<T>(response, step, token);
                },
                deadline.Token);
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
        var candidate = _currentSession is not null &&
                        string.Equals(_currentSession.Subject, session.Subject, StringComparison.Ordinal)
            ? _currentSession
            : session;
        if (candidate.ExpiresAt > DateTimeOffset.UtcNow.AddMinutes(1))
        {
            return candidate;
        }

        return await TryRestoreSessionAsync(cancellationToken)
            ?? throw new ScmApiAuthenticationException("SCM 登录已失效，请重新授权。");
    }

    private async Task<T> SendResourceRequestWithRefreshAsync<T>(
        ScmOAuthSession session,
        Func<ScmOAuthSession, CancellationToken, Task<T>> sendAsync,
        CancellationToken cancellationToken)
    {
        var (result, _) = await SendResourceRequestWithRefreshAndSessionAsync(
            session,
            sendAsync,
            cancellationToken);
        return result;
    }

    internal Task<(T Result, ScmOAuthSession ActiveSession)> SendResourceRequestAsync<T>(
        ScmOAuthSession session,
        Func<ScmOAuthSession, CancellationToken, Task<T>> sendAsync,
        CancellationToken cancellationToken) =>
        SendResourceRequestWithRefreshAndSessionAsync(session, sendAsync, cancellationToken);

    private async Task<(T Result, ScmOAuthSession ActiveSession)> SendResourceRequestWithRefreshAndSessionAsync<T>(
        ScmOAuthSession session,
        Func<ScmOAuthSession, CancellationToken, Task<T>> sendAsync,
        CancellationToken cancellationToken)
    {
        try
        {
            var activeSession = await EnsureActiveSessionAsync(session, cancellationToken);
            try
            {
                return (await sendAsync(activeSession, cancellationToken), activeSession);
            }
            catch (ScmApiAuthenticationException)
            {
                activeSession = await RefreshSessionAfterUnauthorizedAsync(activeSession, cancellationToken);
                return (await sendAsync(activeSession, cancellationToken), activeSession);
            }
        }
        catch (ScmApiAuthenticationException)
        {
            await InvalidateSessionAfterAuthenticationFailureAsync(session);
            throw;
        }
    }

    private async Task InvalidateSessionAfterAuthenticationFailureAsync(ScmOAuthSession session)
    {
        try
        {
            await ClearLocalCredentialAsync(session, CancellationToken.None);
        }
        catch (Exception exception)
        {
            ScmAuthDiagnostics.Write(
                session.CorrelationId ?? "authentication-expired",
                "authentication-expired-local-credential-clear",
                "failed",
                $"exceptionType={exception.GetType().Name}");
        }

        var handlers = SessionInvalidated;
        if (handlers is null)
        {
            return;
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
    }

    private async Task<ScmOAuthSession> RefreshSessionAfterUnauthorizedAsync(
        ScmOAuthSession rejectedSession,
        CancellationToken cancellationToken)
    {
        _currentSession = rejectedSession with { ExpiresAt = DateTimeOffset.MinValue };
        return await TryRestoreSessionAsync(cancellationToken)
            ?? throw new ScmApiAuthenticationException("SCM 登录已失效，请重新授权。");
    }

    private static async Task<(string Error, string Description)> ReadOAuthErrorAsync(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        try
        {
            var error = await response.Content.ReadFromJsonAsync<ScmOAuthErrorResponse>(cancellationToken);
            return (SafeLogValue(error?.Error), SafeLogValue(error?.ErrorDescription));
        }
        catch (JsonException)
        {
            return ("unparseable", "none");
        }
    }

    private static string SafeLogValue(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "none";
        }
        var sanitized = new string(value
            .Take(160)
            .Select(character => char.IsLetterOrDigit(character) || character is '-' or '_' or '.' or ':' or ' '
                ? character
                : '?')
            .ToArray());
        return sanitized.Replace(' ', '_');
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

    private void DeletePreviousAccountCredential(string nextAccountKey)
    {
        var previousAccountKey = tokenVault.LoadActiveAccountKey();
        if (!string.IsNullOrWhiteSpace(previousAccountKey) &&
            !string.Equals(previousAccountKey, nextAccountKey, StringComparison.Ordinal))
        {
            tokenVault.DeleteRefreshToken(previousAccountKey);
        }
    }

    private ScmOAuthSession CreateSession(
        ScmIdentityResponse identity,
        ScmTokenResponse tokenResponse,
        string correlationId)
    {
        var gameIdentity = identity.GameIdentitySnapshot;
        return new ScmOAuthSession(
            options.AuthorityId,
            identity.Subject,
            string.IsNullOrWhiteSpace(identity.DisplayName) ? "SCM 用户" : identity.DisplayName,
            tokenResponse.AccessToken,
            DateTimeOffset.UtcNow.AddSeconds(Math.Max(1, tokenResponse.ExpiresIn)),
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
