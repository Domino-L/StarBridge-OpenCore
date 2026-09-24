namespace StarBridge.HostRuntime.Account;

using StarBridge.Core.Identity;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;
using System.IO;
using System.Net;
using System.Net.Http;

/// <summary>
/// Native account owner for the Flutter bridge. OAuth, token persistence,
/// cache access and Game.log-derived identity stay inside this process.
/// </summary>
internal sealed partial class ScmAccountBridgeHost : IAccountBridgeHost, IDisposable
{
    private static readonly IReadOnlyList<string> SupportedLocales = ["zh-CN", "en-US"];

    private readonly OAuthPkceClient _oauth;
    private readonly S2CompatibilityReader? _compatibilityReader;
    private readonly LegacyPasswordRecoveryClient? _passwordRecovery;
    private readonly LegacyPasswordLoginClient? _legacyPasswordLogin;
    private CancellationTokenSource? _legacyLoginCancellation;
    private readonly StarBridge.HostRuntime.PartyRooms.PartyRoomReader? _partyRooms;
    private readonly StarBridge.HostRuntime.Friends.FriendsReader? _friends;
    private readonly AccountSafetyClient? _accountSafety;
    private readonly StarBridge.HostRuntime.Communities.CommunityClient? _communities;
    private readonly IProfileWriteAuthorizationClient _profileAuthorization;
    private readonly ScmProfileCacheStore _profileCache;
    private readonly string _environment;
    private readonly Func<string?> _detectedGameIdentity;
    private readonly Func<LocalIdentityCheckState> _lastGameIdentityCheck;
    private readonly SemaphoreSlim _mutationGate = new(1, 1);
    private readonly object _loginGate = new();
    private ScmOAuthSession? _session;
    private LegacyMigrationCredential? _legacySession;
    private string? _legacyDisplayName;
    private ScmGameIdentitySnapshot? _legacyIdentity;
    private string? _legacyAvatarImageData;
    private ScmOverlayEntitlementSnapshot? _legacyEntitlements;
    private bool _legacyRestoreUnavailable;
    private CancellationTokenSource? _loginCancellation;
    private CancellationTokenSource? _compatibilityCancellation;
    private bool _restoreAttempted;
    private bool _credentialTemporarilyUnavailable;
    private bool _reauthorizationRequired;
    private bool _disposed;
    private long _generation;

    internal ScmAccountBridgeHost(
        OAuthPkceClient oauth,
        ScmProfileCacheStore profileCache,
        string environment,
        Func<string?> detectedGameIdentity,
        ScmOAuthSession? initialSession = null,
        long initialGeneration = 0,
        IProfileWriteAuthorizationClient? profileAuthorization = null,
        Func<LocalIdentityCheckState>? lastGameIdentityCheck = null,
        StarBridge.HostRuntime.PartyRooms.PartyRoomReader? partyRooms = null,
        StarBridge.HostRuntime.Friends.FriendsReader? friends = null,
        StarBridge.HostRuntime.Communities.CommunityClient? communities = null,
        S2CompatibilityReader? compatibilityReader = null,
        LegacyPasswordRecoveryClient? passwordRecovery = null,
        LegacyPasswordLoginClient? legacyPasswordLogin = null,
        AccountSafetyClient? accountSafety = null)
    {
        _oauth = oauth ?? throw new ArgumentNullException(nameof(oauth));
        _compatibilityReader = compatibilityReader;
        _passwordRecovery = passwordRecovery;
        _legacyPasswordLogin = legacyPasswordLogin;
        _partyRooms = partyRooms;
        _friends = friends;
        _accountSafety = accountSafety;
        _communities = communities;
        _profileAuthorization = profileAuthorization ?? oauth;
        _profileCache = profileCache ?? throw new ArgumentNullException(nameof(profileCache));
        _environment = string.IsNullOrWhiteSpace(environment)
            ? throw new ArgumentException("SCM environment is required.", nameof(environment))
            : environment.Trim();
        _detectedGameIdentity = detectedGameIdentity ??
            throw new ArgumentNullException(nameof(detectedGameIdentity));
        _lastGameIdentityCheck = lastGameIdentityCheck ??
            (() => LocalIdentityCheckState.NotObserved);
        _session = initialSession;
        _restoreAttempted = initialSession is not null;
        _generation = initialGeneration >= 0
            ? initialGeneration
            : throw new ArgumentOutOfRangeException(nameof(initialGeneration));
        _oauth.SessionInvalidated += OnSessionInvalidated;
    }

    public long Generation => Interlocked.Read(ref _generation);

    // Legacy reads do not refresh or replace credentials. SCM resource reads
    // still share mutable refresh state, so retain their serialized dispatch.
    public bool SupportsConcurrentReads => !_disposed && _restoreAttempted &&
        _session is null && _legacySession is not null &&
        !_reauthorizationRequired && !_credentialTemporarilyUnavailable && !_legacyRestoreUnavailable;

    public StarBridge.HostRuntime.Hangar.HangarAccountIdentity? HangarIdentity {
        get {
            var session = _session;
            if (session is null && LegacyContext is { } legacy && !_legacyRestoreUnavailable)
                return new(legacy, Generation, _legacyIdentity ?? new(ScmGameIdentityStatus.Unknown, null, null));
            return session is null || _reauthorizationRequired || _credentialTemporarilyUnavailable
                ? null : StarBridge.HostRuntime.Hangar.HangarAccountIdentity.FromSession(_environment, Generation, session);
        }
    }

    public BridgeAccountContext? CurrentContext
    {
        get { var session = _session; return session is null ? LegacyContext : ToContext(session); }
    }

    private BridgeAccountContext? LegacyContext => _legacySession is { } legacy && _legacyPasswordLogin is not null
        ? new(_environment, _legacyPasswordLogin.AuthorityId, legacy.AccountId) : null;

    public BridgeAccountContext? GameplayTimeContext =>
        _reauthorizationRequired || _credentialTemporarilyUnavailable || _legacyRestoreUnavailable ? null : CurrentContext;

    public IReadOnlyList<string> CurrentOverlayEntitlements
    {
        get
        {
            var session = _session;
            if (session is null && !_disposed && !_legacyRestoreUnavailable && !_reauthorizationRequired && !_credentialTemporarilyUnavailable &&
                _legacySession is { } legacy && _legacyEntitlements?.AccountId == legacy.AccountId)
                return _legacyEntitlements.ResolveActive(DateTimeOffset.UtcNow);
            return session is null || _reauthorizationRequired || _credentialTemporarilyUnavailable
                ? []
                : session.ActiveOverlayEntitlements;
        }
    }

    public event Action<long>? AccountChanged;

    public async Task<AccountBridgeSessionProjection> GetCurrentAsync(
        CancellationToken cancellationToken)
    {
        await EnsureRestoredAsync(cancellationToken);
        return ProjectCurrent();
    }

    public async Task<AccountBridgeSessionProjection> LoginAsync(
        CancellationToken cancellationToken)
    {
        if (!await _mutationGate.WaitAsync(0, cancellationToken))
        {
            throw new AccountBridgeHostException(AccountBridgeStableErrors.OperationInProgress);
        }

        using var loginCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        lock (_loginGate)
        {
            if (_loginCancellation is not null)
            {
                _mutationGate.Release();
                throw new AccountBridgeHostException(AccountBridgeStableErrors.OperationInProgress);
            }

            _loginCancellation = loginCancellation;
        }

        try
        {
            var session = await _oauth.SignInAsync(loginCancellation.Token);
            _legacyPasswordLogin?.ForgetSession();
            PublishSession(session, reauthorizationRequired: false);
            return ProjectCurrent();
        }
        catch (OperationCanceledException) when (loginCancellation.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException)
        {
            throw new AccountBridgeHostException(AccountBridgeStableErrors.LoginTimeout, true);
        }
        catch (TimeoutException)
        {
            throw new AccountBridgeHostException(AccountBridgeStableErrors.LoginTimeout, true);
        }
        finally
        {
            lock (_loginGate)
            {
                if (ReferenceEquals(_loginCancellation, loginCancellation))
                {
                    _loginCancellation = null;
                }
            }

            _mutationGate.Release();
        }
    }

    public Task CancelLoginAsync()
    {
        lock (_loginGate)
        {
            _loginCancellation?.Cancel();
        }

        return Task.CompletedTask;
    }

    public async Task LogoutAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken)
    {
        await _mutationGate.WaitAsync(cancellationToken);
        try
        {
            if (_session is null && LegacyContext is { } legacyContext && legacyContext == context)
            {
                _legacyPasswordLogin!.ForgetSession();
                PublishSession(null, reauthorizationRequired: false);
                return;
            }
            var session = RequireSession(context);
            try
            {
                await _oauth.RevokeAsync(session, cancellationToken);
            }
            catch (HttpRequestException)
            {
                // RevokeAsync deletes the local DPAPI-backed credential before
                // the best-effort remote revocation request is made.
            }

            PublishSession(null, reauthorizationRequired: false);
        }
        finally
        {
            _mutationGate.Release();
        }
    }

    public async Task<AccountBridgeProfileProjection> GetProfileAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken)
    {
        var session = RequireSession(context);
        try
        {
            var result = await _oauth.LoadProfileAsync(session, cancellationToken);
            RequireSameSession(session, result.ActiveSession);
            _session = result.ActiveSession;
            var directory = await LoadDirectoryAsync(cancellationToken);
            var route = CurrentRoute();
            _profileCache.Save(route, result.Profile, DateTimeOffset.UtcNow);
            return ProjectProfile(result.Profile, "live", null, directory);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception) when (exception is HttpRequestException or InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            var cached = _profileCache.Load(CurrentRoute());
            if (cached is null)
            {
                throw new AccountBridgeHostException(
                    AccountBridgeStableErrors.ProfileReadUnavailable,
                    retryable: true);
            }

            return ProjectProfile(
                cached.ToOfflineProfile(),
                "cache",
                cached.CachedAtUtc,
                []);
        }
    }

    public async Task<object> RecoverPasswordAsync(string action, System.Text.Json.JsonElement payload, CancellationToken token)
    {
        if (_disposed || _passwordRecovery is null) throw new AccountBridgeHostException("bridge.capability_unavailable");
        return await _passwordRecovery.ExecuteAsync(action, payload, token);
    }

    public async Task<AccountBridgeCompatibilityProjection> GetCompatibilityStateAsync(
        BridgeAccountContext context, CancellationToken cancellationToken)
    {
        var session = RequireSession(context);
        var generation = Generation;
        if (_credentialTemporarilyUnavailable || _reauthorizationRequired || _compatibilityReader is null)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityReadUnavailable, true);
        AccountBridgeCompatibilityProjection result;
        try { result = await _compatibilityReader.ReadAsync(session, cancellationToken).ConfigureAwait(false); }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or
            System.Text.Json.JsonException or InvalidOperationException or OperationCanceledException)
        {
            _compatibilityReader.Reset();
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityReadUnavailable, true);
        }
        if (_disposed || Generation != generation || !ReferenceEquals(_session, session))
        {
            _compatibilityReader.Reset();
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityReadUnavailable, true);
        }
        return result;
    }

    public async Task<AccountBridgeCompatibilityProjection> LinkLegacyAccountAsync(
        BridgeAccountContext context, AccountBridgeLegacyCredential? credential,
        CancellationToken cancellationToken)
    {
        if (credential is null || string.IsNullOrWhiteSpace(credential.AccountName) ||
            credential.AccountName.Length > 320 || string.IsNullOrEmpty(credential.Password) || credential.Password.Length > 1024)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.LegacyCredentialsRequired);
        if (_disposed || _compatibilityReader is null || _reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityWriteUnavailable, true);
        if (!await _mutationGate.WaitAsync(0, cancellationToken))
            throw new AccountBridgeHostException(AccountBridgeStableErrors.OperationInProgress);
        using var operation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        operation.CancelAfter(TimeSpan.FromMinutes(3));
        try
        {
            var original = RequireSession(context);
            var generation = Generation;
            lock (_loginGate) { _compatibilityCancellation = operation; }
            if (_disposed || generation != Generation || CurrentContext != context)
                throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityWriteUnavailable, true);
            var result = await _compatibilityReader.LinkAsync(original,
                new LegacyIdentityLinkPasswordCredential(credential.AccountName.Trim(), credential.Password), operation.Token);
            operation.Token.ThrowIfCancellationRequested();
            if (_disposed || generation != Generation || CurrentContext != context)
                throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityWriteUnavailable, true);
            return result;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (AccountBridgeHostException) { throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or InvalidOperationException or
            System.Text.Json.JsonException or OperationCanceledException or TimeoutException)
        {
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityWriteUnavailable, true);
        }
        finally
        {
            lock (_loginGate)
            {
                if (ReferenceEquals(_compatibilityCancellation, operation)) _compatibilityCancellation = null;
            }
            if (!_disposed) _mutationGate.Release();
        }
    }

    public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(
        BridgeAccountContext context, CancellationToken cancellationToken) =>
        throw new AccountBridgeHostException(BridgeErrorCodes.CapabilityUnavailable);

    public async Task<AccountBridgeProfileProjection> PatchPreferencesAsync(
        BridgeAccountContext context,
        AccountBridgePreferencePatch patch,
        CancellationToken cancellationToken)
    {
        if (patch.IsEmpty)
        {
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ProfileWriteConflict);
        }

        await _mutationGate.WaitAsync(cancellationToken);
        try
        {
            var originalSession = RequireSession(context);
            var contract = ToProfilePatch(patch);
            try
            {
                var writeSession = await _profileAuthorization.AuthorizeProfileWriteAsync(
                    originalSession,
                    cancellationToken);
                RequireSameSession(originalSession, writeSession);
                var update = await _oauth.UpdateProfileAsync(
                    writeSession,
                    contract,
                    cancellationToken);
                RequireSameSession(originalSession, update.ActiveSession);
                var confirmed = await _oauth.LoadProfileAsync(
                    originalSession,
                    cancellationToken);
                RequireSameSession(originalSession, confirmed.ActiveSession);
                _session = confirmed.ActiveSession;
                var directory = await LoadDirectoryAsync(cancellationToken);
                _profileCache.Save(CurrentRoute(), confirmed.Profile, DateTimeOffset.UtcNow);
                return ProjectProfile(confirmed.Profile, "live", null, directory);
            }
            catch (ScmApiForbiddenException)
            {
                throw new AccountBridgeHostException(AccountBridgeStableErrors.ProfileWriteForbidden);
            }
            catch (OAuthAuthorizationDeniedException)
            {
                throw new OperationCanceledException("Profile authorization was cancelled.");
            }
            catch (TimeoutException)
            {
                throw new AccountBridgeHostException(AccountBridgeStableErrors.LoginTimeout, retryable: true);
            }
            catch (ScmApiAuthenticationException)
            {
                throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            }
            catch (HttpRequestException exception) when (exception.StatusCode == HttpStatusCode.Conflict)
            {
                throw new AccountBridgeHostException(
                    AccountBridgeStableErrors.ProfileWriteConflict,
                    retryable: true);
            }
            catch (HttpRequestException)
            {
                throw new AccountBridgeHostException(
                    AccountBridgeStableErrors.ProfileWriteConflict,
                    retryable: true);
            }
        }
        finally
        {
            _mutationGate.Release();
        }
    }

    public async Task<PersonalProfileDocumentContract> GetPersonalProfileAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken)
    {
        if (_session is null)
        {
            var legacy = RequireRelaySession(context);
            var result = await SendRelayRequestAsync(legacy,
                (active, ct) => _legacyPasswordLogin!.ReadOwnProfileAsync(active.Legacy!, ct), cancellationToken);
            RequireSameRelaySession(legacy, RequireRelaySession(context));
            return result.Result;
        }
        var session = RequireSession(context);
        try
        {
            var result = await _oauth.LoadPersonalProfileAsync(session, cancellationToken)
                .ConfigureAwait(false);
            RequireSameSession(session, result.ActiveSession);
            _session = result.ActiveSession;
            return result.Profile;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (ScmApiAuthenticationException)
        {
            throw new AccountBridgeHostException(
                AccountBridgeStableErrors.ReauthorizationRequired);
        }
        catch (Exception exception) when (
            exception is HttpRequestException or InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            throw new AccountBridgeHostException(
                AccountBridgeStableErrors.PersonalProfileReadUnavailable,
                retryable: true);
        }
    }

    public async Task<PersonalProfileDocumentContract> UpdatePersonalProfileAsync(
        BridgeAccountContext context,
        PersonalProfilePresentationUpdateContract update,
        CancellationToken cancellationToken)
    {
        await _mutationGate.WaitAsync(cancellationToken);
        try
        {
            var originalSession = RequireSession(context);
            try
            {
                var writeSession = await _oauth.AuthorizeProfileWriteAsync(
                    originalSession,
                    cancellationToken);
                RequireSameSession(originalSession, writeSession);
                var result = await _oauth.UpdatePersonalProfileAsync(
                    writeSession,
                    update,
                    cancellationToken);
                RequireSameSession(originalSession, result.ActiveSession);
                _session = result.ActiveSession;
                return result.Profile;
            }
            catch (ScmApiForbiddenException)
            {
                throw new AccountBridgeHostException(
                    AccountBridgeStableErrors.PersonalProfileWriteForbidden);
            }
            catch (ScmApiAuthenticationException)
            {
                throw new AccountBridgeHostException(
                    AccountBridgeStableErrors.ReauthorizationRequired);
            }
            catch (HttpRequestException exception) when (exception.StatusCode == HttpStatusCode.Conflict)
            {
                throw new AccountBridgeHostException(
                    AccountBridgeStableErrors.PersonalProfileWriteConflict,
                    retryable: true);
            }
            catch (Exception exception) when (
                exception is HttpRequestException or InvalidOperationException or IOException or UnauthorizedAccessException)
            {
                throw new AccountBridgeHostException(
                    AccountBridgeStableErrors.PersonalProfileWriteConflict,
                    retryable: true);
            }
        }
        finally
        {
            _mutationGate.Release();
        }
    }

    public async Task<AccountBridgeOfficialFleetProjection> GetOfficialFleetAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken)
    {
        var session = RequireSession(context);
        try
        {
            var result = await _oauth.LoadBootstrapAsync(session, cancellationToken)
                .ConfigureAwait(false);
            RequireSameSession(session, result.ActiveSession);
            _session = result.ActiveSession;
            return ProjectOfficialFleet(result.Snapshot, DateTimeOffset.UtcNow);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (AccountBridgeHostException)
        {
            throw;
        }
        catch (ScmApiAuthenticationException)
        {
            throw new AccountBridgeHostException(
                AccountBridgeStableErrors.ReauthorizationRequired);
        }
        catch (Exception exception) when (
            exception is HttpRequestException or InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            throw new AccountBridgeHostException(
                AccountBridgeStableErrors.OfficialFleetReadUnavailable,
                retryable: true);
        }
    }

    public Task<bool> ClearProfileCacheAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _ = RequireSession(context);
        try
        {
            return Task.FromResult(_profileCache.Clear(CurrentRoute()));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw new AccountBridgeHostException("profile.cache_clear_unavailable", retryable: true);
        }
    }

    public Task<AccountBridgeIdentityProjection> GetGameIdentityPolicyAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var relaySession = RequireRelaySession(context);
        var identity = relaySession.Scm?.AuthoritativeGameIdentity ??
            _legacyIdentity ?? new(ScmGameIdentityStatus.Unknown, null, null);
        var detected = _detectedGameIdentity();
        var assessment = detected is null
            ? IdentityBindingPolicy.Evaluate(
                identity,
                _lastGameIdentityCheck())
            : IdentityBindingPolicy.Evaluate(
                identity,
                detected);
        if (relaySession.Legacy is not null && detected is null &&
            _lastGameIdentityCheck() == LocalIdentityCheckState.NotObserved &&
            assessment.State == IdentityVerificationState.Verified)
            assessment = assessment with { State = IdentityVerificationState.AwaitingGameIdentity };
        var state = assessment.State switch
        {
            IdentityVerificationState.Verified => "match",
            IdentityVerificationState.Mismatch => "mismatch",
            IdentityVerificationState.AwaitingGameIdentity => "awaitingGameIdentity",
            IdentityVerificationState.ReverificationRequired => "reverifyRequired",
            IdentityVerificationState.Revoked => "revoked",
            _ => "unknown"
        };
        return Task.FromResult(
            new AccountBridgeIdentityProjection(
                state,
                assessment.BoundGameName,
                assessment.CanUseIdentitySensitiveNetworkWrites));
    }

    private async Task EnsureRestoredAsync(CancellationToken cancellationToken)
    {
        if (_restoreAttempted && !_credentialTemporarilyUnavailable && !_legacyRestoreUnavailable)
        {
            return;
        }

        await _mutationGate.WaitAsync(cancellationToken);
        try
        {
            if (_restoreAttempted && !_credentialTemporarilyUnavailable && !_legacyRestoreUnavailable)
            {
                return;
            }

            // This file records an explicitly selected legacy login, not a migration
            // source. Successful SCM login deletes it. Restore that selected authority
            // directly; SCM availability must not gate a Relay account.
            if (_legacyPasswordLogin is not null)
            {
                var legacy = await _legacyPasswordLogin.RestoreAsync(cancellationToken);
                cancellationToken.ThrowIfCancellationRequested();
                if (legacy.Result.Outcome != "absent")
                {
                    _restoreAttempted = true;
                    _credentialTemporarilyUnavailable = false;
                    _reauthorizationRequired = false;
                    var unavailable = legacy.Result.Outcome == "unavailable";
                    if (legacy.Credential is not null)
                    {
                        var displayName = unavailable && _legacySession == legacy.Credential
                            ? _legacyDisplayName : legacy.DisplayName;
                        var identity = unavailable && _legacySession == legacy.Credential ? _legacyIdentity : legacy.Identity;
                        var avatar = unavailable && _legacySession == legacy.Credential ? _legacyAvatarImageData : legacy.AvatarImageData;
                        if (_legacySession != legacy.Credential || _legacyRestoreUnavailable != unavailable ||
                            _legacyDisplayName != displayName || _legacyIdentity != identity || _legacyAvatarImageData != avatar)
                            PublishLegacySession(legacy.Credential, unavailable, displayName, identity, avatar, legacy.Entitlements);
                    }
                    else if (legacy.Result.Outcome == "rejected")
                        PublishSession(null, reauthorizationRequired: false);
                    else
                        _legacyRestoreUnavailable = unavailable;
                    return;
                }
            }

            ScmOAuthSession? restored;
            try
            {
                restored = await _oauth.TryRestoreSessionAsync(cancellationToken);
            }
            catch (HttpRequestException)
            {
                restored = null;
            }
            catch (OperationCanceledException) when (
                !cancellationToken.IsCancellationRequested &&
                _oauth.LastSessionRestoreOutcome == ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable)
            {
                // An HTTP deadline does not mean the user cancelled sign-in.
                restored = null;
            }
            catch (InvalidOperationException) when (
                _oauth.LastSessionRestoreOutcome ==
                ScmSessionRestoreOutcome.ReauthorizationRequired)
            {
                restored = null;
            }

            _restoreAttempted = true;
            _credentialTemporarilyUnavailable =
                _oauth.LastSessionRestoreOutcome ==
                ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable;
            _reauthorizationRequired =
                _oauth.LastSessionRestoreOutcome == ScmSessionRestoreOutcome.ReauthorizationRequired;
            if (restored is not null)
            {
                PublishSession(restored, reauthorizationRequired: false);
            }
        }
        finally
        {
            _mutationGate.Release();
        }
    }

    private async Task<IReadOnlyList<AccountBridgeTimeZone>> LoadDirectoryAsync(
        CancellationToken cancellationToken)
    {
        try
        {
            var directory = await _oauth.LoadTimeZoneDirectoryAsync(cancellationToken);
            return directory
                .Select(entry => new AccountBridgeTimeZone(entry.Value, entry.Label, entry.Offset))
                .ToArray();
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception) when (exception is HttpRequestException or InvalidOperationException)
        {
            throw new AccountBridgeHostException(
                AccountBridgeStableErrors.ProfileDirectoryUnavailable,
                retryable: true);
        }
    }

    private AccountBridgeSessionProjection ProjectCurrent()
    {
        var session = _session;
        if (session is not null)
        {
            return new AccountBridgeSessionProjection(
                "signedIn",
                Generation,
                ToContext(session),
                EmptyToNull(session.DisplayName),
                null);
        }

        if (_legacySession is { } legacy)
            return new AccountBridgeSessionProjection(
                _legacyRestoreUnavailable ? "legacyUnavailable" : "legacySignedIn",
                Generation, LegacyContext, _legacyDisplayName ?? legacy.AccountName, null, _legacyAvatarImageData,
                AccountDisplayLabel.Mask(legacy.AccountName));

        return new AccountBridgeSessionProjection(
            _reauthorizationRequired
                ? "reauthorizationRequired"
                : _credentialTemporarilyUnavailable
                    ? "credentialTemporarilyUnavailable"
                    : "signedOut",
            Generation,
            null,
            null,
            null);
    }

    private static AccountBridgeProfileProjection ProjectProfile(
        ScmSelfProfileContract profile,
        string source,
        DateTimeOffset? cachedAtUtc,
        IReadOnlyList<AccountBridgeTimeZone> directory)
    {
        var normalized = profile.Normalize();
        return new AccountBridgeProfileProjection(
            new AccountBridgeProfile(
                normalized.DisplayName,
                normalized.AvatarUrl,
                source == "cache" ? null : normalized.Email,
                normalized.Locale,
                normalized.TimeZone),
            source,
            cachedAtUtc,
            SupportedLocales,
            directory);
    }

    internal static AccountBridgeOfficialFleetProjection ProjectOfficialFleet(
        ScmBootstrapSnapshot snapshot,
        DateTimeOffset observedAtUtc)
    {
        var fleets = snapshot.Fleets;
        if (fleets is null || fleets.Length > 1 || fleets.Any(fleet => fleet is null))
        {
            throw InvalidOfficialFleetData();
        }

        var primary = snapshot.PrimaryFleet;
        if (primary is not null &&
            (fleets.Length != 1 ||
             primary.Id != fleets[0].Id ||
             primary.Sid != fleets[0].Sid ||
             primary.Name != fleets[0].Name ||
             primary.LogoUrl != fleets[0].LogoUrl ||
             primary.RankName != fleets[0].RankName ||
             primary.RankValue != fleets[0].RankValue ||
             primary.Primary != fleets[0].Primary))
        {
            throw InvalidOfficialFleetData();
        }

        var resourceVersion = snapshot.ResourceVersions is { } versions &&
                              versions.TryGetValue("fleets", out var value)
            ? (long?)value
            : null;
        if (resourceVersion < 0)
        {
            throw InvalidOfficialFleetData();
        }
        var fleet = primary ?? fleets.SingleOrDefault();
        if (fleet is null)
        {
            return new AccountBridgeOfficialFleetProjection(
                "notMember",
                null,
                "live",
                resourceVersion,
                observedAtUtc);
        }

        var sid = EmptyToNull(fleet.Sid);
        var name = EmptyToNull(fleet.Name);
        if (fleet.Id <= 0 ||
            sid is null ||
            name is null ||
            fleet.RankValue is < 1 or > 5)
        {
            throw InvalidOfficialFleetData();
        }

        var logoUrl = EmptyToNull(fleet.LogoUrl);
        if (logoUrl is not null &&
            (!Uri.TryCreate(logoUrl, UriKind.Absolute, out var logoUri) ||
             logoUri.Scheme != Uri.UriSchemeHttps ||
             string.IsNullOrEmpty(logoUri.Host) ||
             !string.IsNullOrEmpty(logoUri.UserInfo)))
        {
            throw InvalidOfficialFleetData();
        }

        return new AccountBridgeOfficialFleetProjection(
            "member",
            new AccountBridgeOfficialFleetSummary(
                $"officialFleet:{fleet.Id}",
                sid,
                name,
                logoUrl,
                EmptyToNull(fleet.RankName),
                fleet.RankValue),
            "live",
            resourceVersion,
            observedAtUtc);
    }

    private static AccountBridgeHostException InvalidOfficialFleetData() => new(
        AccountBridgeStableErrors.OfficialFleetDataInvalid,
        retryable: true);

    private static ScmProfilePatchContract ToProfilePatch(
        AccountBridgePreferencePatch patch)
    {
        try
        {
            var contract = new ScmProfilePatchContract(
                patch.Locale.IsSpecified
                    ? ScmProfilePatchField.Set(patch.Locale.Value)
                    : ScmProfilePatchField.Unspecified,
                patch.TimeZone.IsSpecified
                    ? ScmProfilePatchField.Set(patch.TimeZone.Value)
                    : ScmProfilePatchField.Unspecified);
            _ = contract.ToWirePayload();
            return contract;
        }
        catch (ArgumentException)
        {
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ProfileWriteConflict);
        }
    }

    private ScmOAuthSession RequireSession(BridgeAccountContext context)
    {
        var session = _session ??
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var current = ToContext(session);
        if (!context.Environment.Equals(current.Environment, StringComparison.OrdinalIgnoreCase) ||
            !context.Authority.Equals(current.Authority, StringComparison.OrdinalIgnoreCase) ||
            !context.Subject.Equals(current.Subject, StringComparison.Ordinal))
        {
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        }

        return session;
    }

    private void PublishSession(ScmOAuthSession? session, bool reauthorizationRequired,
        LegacyMigrationCredential? legacy = null, bool legacyUnavailable = false, string? legacyDisplayName = null,
        ScmGameIdentitySnapshot? legacyIdentity = null, string? legacyAvatarImageData = null, ScmOverlayEntitlementSnapshot? legacyEntitlements = null)
    {
        lock (_loginGate) { _compatibilityCancellation?.Cancel(); }
        _compatibilityReader?.Reset();
        _legacySession = legacy;
        _legacyDisplayName = legacyDisplayName;
        _legacyIdentity = legacyIdentity;
        _legacyAvatarImageData = legacyAvatarImageData;
        _legacyEntitlements = legacyEntitlements;
        _legacyRestoreUnavailable = legacyUnavailable;
        _session = session;
        _restoreAttempted = true;
        _credentialTemporarilyUnavailable = false;
        _reauthorizationRequired = reauthorizationRequired;
        var generation = Interlocked.Increment(ref _generation);
        _communities?.InvalidateProfileEdits();
        _communities?.InvalidateHangarEdits();
        _communities?.InvalidateRolesEdits();
        _communities?.InvalidateMemberRoleEdits();
        _communities?.InvalidateMemberRemovalEdits();
        _communities?.InvalidateOwnershipTransferEdits();
        _communities?.InvalidateInvitePreviews();
        AccountChanged?.Invoke(generation);
    }

    private void PublishLegacySession(LegacyMigrationCredential credential, bool unavailable = false, string? displayName = null,
        ScmGameIdentitySnapshot? identity = null, string? avatarImageData = null, ScmOverlayEntitlementSnapshot? entitlements = null)
    {
        // A separate Relay authority; RequireSession still rejects SCM-only operations.
        PublishSession(null, reauthorizationRequired: false, legacy: credential, legacyUnavailable: unavailable, legacyDisplayName: displayName, legacyIdentity: identity, legacyAvatarImageData: avatarImageData, legacyEntitlements: entitlements);
    }

    private void OnSessionInvalidated(OAuthPkceClient source, ScmOAuthSession invalidated)
    {
        var current = _session;
        if (current is null ||
            !current.AuthorityId.Equals(invalidated.AuthorityId, StringComparison.Ordinal) ||
            !current.Subject.Equals(invalidated.Subject, StringComparison.Ordinal))
        {
            return;
        }

        PublishSession(null, reauthorizationRequired: true);
    }

    private AccountRouteIdentity CurrentRoute()
    {
        var session = _session ??
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        return AccountRouteIdentity.Create(
            _environment,
            session.AuthorityId,
            session.Subject,
            legacyAccountId: null);
    }

    private BridgeAccountContext ToContext(ScmOAuthSession session) =>
        new(_environment, session.AuthorityId, session.Subject);

    private static void RequireSameSession(
        ScmOAuthSession expected,
        ScmOAuthSession actual)
    {
        if (!expected.AuthorityId.Equals(actual.AuthorityId, StringComparison.Ordinal) ||
            !expected.Subject.Equals(actual.Subject, StringComparison.Ordinal))
        {
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        }
    }

    private static string? EmptyToNull(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    public void Dispose()
    {
        lock (_loginGate)
        {
            if (_disposed) return;
            _disposed = true;
            _compatibilityCancellation?.Cancel();
            _legacyLoginCancellation?.Cancel();
        }
        _compatibilityReader?.Dispose();
        _passwordRecovery?.Dispose();
        _legacyPasswordLogin?.Dispose();
        _partyRooms?.Dispose();
        _friends?.Dispose();
        _accountSafety?.Dispose();
        _communities?.Dispose();
        _privacyWriter?.Dispose();
        _oauth.SessionInvalidated -= OnSessionInvalidated;
        lock (_loginGate)
        {
            _loginCancellation?.Cancel();
            _loginCancellation = null;
        }

        _mutationGate.Dispose();
    }

}
